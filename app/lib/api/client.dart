import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../auth/session.dart';
import '../models/account.dart';
import '../models/project.dart';
import 'storage.dart';
import 'sync_api.dart';

class ApiException implements Exception {
  final int status;
  final String message;
  ApiException(this.status, this.message);
  @override
  String toString() => message;
}

/// A sessão morreu no servidor (saiu, refresh reusado ou vencido): o app volta ao login.
class Unauthenticated implements Exception {
  @override
  String toString() => 'sessão encerrada; entre de novo';
}

/// Cliente HTTP da API. Na web usa a mesma origem (o nginx, ou o servidor Rust em
/// desenvolvimento); no `flutter run` e no app Android, a API de produção. `--dart-define=API_BASE=`
/// aponta outra.
///
/// Toda chamada leva o JWT de acesso. Num 401 tenta UMA renovação (dividida entre as chamadas
/// simultâneas) e repete; se a renovação também falha, a sessão acabou.
class ApiClient implements SyncApi {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  static const _production = 'https://jopendaw.johnenrique.tech';
  static const _override = String.fromEnvironment('API_BASE');
  final String base = _override.isNotEmpty
      ? _override
      : kIsWeb && (Uri.base.port == 8080 || Uri.base.host != 'localhost')
      ? Uri.base.origin
      : _production;

  Session get _session => Session.instance;
  Future<bool>? _refreshing;

  Uri _u(String path, [Map<String, String>? q]) => Uri.parse('$base$path').replace(queryParameters: q);

  Map<String, String> _headers({bool json = false}) => {
    if (json) 'content-type': 'application/json',
    if (_session.accessToken != null) 'authorization': 'Bearer ${_session.accessToken}',
  };

  Future<http.Response> _raw(String method, String path, {Object? body, Uint8List? bytes, Map<String, String>? q}) {
    final req = http.Request(method, _u(path, q))..headers.addAll(_headers(json: body != null));
    if (body != null) req.body = jsonEncode(body);
    if (bytes != null) {
      req.headers['content-type'] = 'application/octet-stream';
      req.bodyBytes = bytes;
    }
    return req.send().then(http.Response.fromStream).timeout(const Duration(seconds: 120));
  }

  ApiException _error(http.Response r) {
    String msg = 'HTTP ${r.statusCode}';
    try {
      msg = jsonDecode(utf8.decode(r.bodyBytes))['error'] ?? msg;
    } catch (_) {}
    return ApiException(r.statusCode, msg);
  }

  dynamic _decode(http.Response r) => r.body.isEmpty ? null : jsonDecode(utf8.decode(r.bodyBytes));

  /// Faz o pedido renovando o acesso uma vez num 401; sessão morta vira [Unauthenticated].
  Future<http.Response> _send(String method, String path, {Object? body, Uint8List? bytes, Map<String, String>? q}) async {
    var r = await _raw(method, path, body: body, bytes: bytes, q: q);
    if (r.statusCode == 401 && _session.signedIn) {
      if (!await _refresh()) {
        await _session.signOut(notifyServer: false);
        throw Unauthenticated();
      }
      r = await _raw(method, path, body: body, bytes: bytes, q: q);
    }
    if (r.statusCode == 401) throw Unauthenticated();
    return r;
  }

  Future<dynamic> _req(String method, String path, {Object? body, Map<String, String>? q}) async {
    final r = await _send(method, path, body: body, q: q);
    if (r.statusCode >= 400) throw _error(r);
    return _decode(r);
  }

  /// Renova o acesso. Antes relê o armazenamento: no navegador outra aba pode já ter renovado,
  /// e aí basta usar o token dela. Se o servidor diz que a troca acabou de acontecer (409),
  /// foi outra aba no mesmo instante: espera ela gravar e relê.
  Future<bool> _refresh() {
    return _refreshing ??= () async {
      try {
        final before = _session.refreshToken;
        if (await _session.reloadTokens() && _session.refreshToken != null && _session.refreshToken != before) {
          _adoptedFromOtherTab();
          return true;
        }
        for (var attempt = 0; attempt < 3; attempt++) {
          final r = await http
              .post(_u('/api/auth/refresh'), headers: {'content-type': 'application/json'}, body: jsonEncode({'refresh_token': _session.refreshToken}))
              .timeout(const Duration(seconds: 20));
          if (r.statusCode == 200) {
            await _session.signIn(Tokens.fromJson(_decode(r)));
            return true;
          }
          if (r.statusCode != 409) return false;
          await Future.delayed(Duration(milliseconds: 300 * (attempt + 1)));
          if (await _session.reloadTokens()) {
            if (_session.refreshToken == null) return false;
            _adoptedFromOtherTab();
            return true;
          }
        }
        return false;
      } catch (_) {
        return false;
      } finally {
        _refreshing = null;
      }
    }();
  }

  /// A sessão que veio de outra aba pode ser de outra pessoa (ela saiu e entrou com outro
  /// email): relê quem é, depois que esta renovação terminar.
  void _adoptedFromOtherTab() => Future.microtask(() => _session.refreshMe()).catchError((_) {});

  Future<dynamic> _get(String path, [Map<String, String>? q]) => _req('GET', path, q: q);
  Future<dynamic> _json(String method, String path, Object body, [Map<String, String>? q]) => _req(method, path, body: body, q: q);
  Future<dynamic> _delete(String path, [Map<String, String>? q]) => _req('DELETE', path, q: q);

  // ---- contas ----
  Future<void> requestMagicLink(String email) => _json('POST', '/api/auth/magic-link', {'email': email});

  /// Troca o token do link por uma sessão. Link usado ou vencido vira [Unauthenticated].
  Future<Tokens> verify(String token) async {
    final r = await http.post(_u('/api/auth/verify'), headers: {'content-type': 'application/json'}, body: jsonEncode({'token': token}));
    if (r.statusCode == 401) throw Unauthenticated();
    if (r.statusCode >= 400) throw _error(r);
    return Tokens.fromJson(_decode(r));
  }

  /// Entrada por código de acesso (a conta de demonstração da revisão da Play Store).
  Future<Tokens> accessCode(String email, String code) async {
    final r = await http.post(_u('/api/auth/access-code'), headers: {'content-type': 'application/json'}, body: jsonEncode({'email': email, 'code': code}));
    if (r.statusCode == 401) throw Unauthenticated();
    if (r.statusCode >= 400) throw _error(r);
    return Tokens.fromJson(_decode(r));
  }

  /// Os provedores de entrada ligados no servidor (`google`, `discord`).
  Future<List<String>> authProviders() async {
    final r = await http.get(_u('/api/auth/providers'));
    if (r.statusCode >= 400) throw _error(r);
    return [for (final p in (_decode(r)['providers'] as List)) p as String];
  }

  /// Onde começa a entrada por um provedor; `challenge` é o SHA-256 do segredo do app.
  String oauthStartUrl(String provider, {required String platform, required String challenge}) =>
      _u('/api/auth/oauth/$provider/start', {'platform': platform, 'challenge': challenge}).toString();

  /// Troca a entrada que o provedor devolveu por uma sessão, com o segredo de quem começou.
  Future<Tokens> finishOAuth(String token, String verifier) async {
    final r = await http.post(
      _u('/api/auth/oauth/finish'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'token': token, 'verifier': verifier}),
    );
    if (r.statusCode == 401) throw Unauthenticated();
    if (r.statusCode >= 400) throw _error(r);
    return Tokens.fromJson(_decode(r));
  }

  /// Android com o app do Discord: o endereço de autorização para abrir nele.
  Future<String> discordAppStart(String challenge) async {
    final r = await http.post(_u('/api/auth/oauth/discord/app'), headers: {'content-type': 'application/json'}, body: jsonEncode({'challenge': challenge}));
    if (r.statusCode >= 400) throw _error(r);
    return _decode(r)['url'] as String;
  }

  /// Troca o código que o app do Discord devolveu por uma sessão.
  Future<Tokens> discordAppFinish({required String code, required String state, required String verifier}) async {
    final r = await http.post(
      _u('/api/auth/oauth/discord/app/finish'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'code': code, 'state': state, 'verifier': verifier}),
    );
    if (r.statusCode == 401) throw Unauthenticated();
    if (r.statusCode >= 400) throw _error(r);
    return Tokens.fromJson(_decode(r));
  }

  Future<void> logout() => _json('POST', '/api/auth/logout', {});
  Future<void> logoutAll() => _json('POST', '/api/auth/logout-all', {});
  Future<Me> me() async => Me.fromJson(await _get('/api/me'));
  Future<User> patchMe({required String name}) async => User.fromJson(await _json('PATCH', '/api/me', {'name': name}));

  /// Apaga a conta de quem está logado, com os projetos dela.
  Future<void> deleteAccount() => _delete('/api/me');

  // ---- projetos ----
  Future<List<Project>> projects() async => [for (final p in await _get('/api/projects')) Project.fromJson(p)];
  Future<Project> project(String id) async => Project.fromJson(await _get('/api/projects/$id'));
  Future<Project> createProject(String name) async => Project.fromJson(await _json('POST', '/api/projects', {'name': name}));
  Future<Project> patchProject(String id, Map<String, dynamic> patch) async => Project.fromJson(await _json('PATCH', '/api/projects/$id', patch));
  Future<void> deleteProject(String id) => _delete('/api/projects/$id');

  // ---- sincronização e jobs ----
  @override
  Future<ServerDoc> projectDoc(String projectId) async {
    final j = await _get('/api/projects/$projectId/doc') as Map<String, dynamic>;
    return ServerDoc(j['version'] as int, (j['doc'] as Map?)?.cast<String, dynamic>());
  }

  @override
  Future<int> putProjectDoc(String projectId, int baseVersion, Map<String, dynamic> doc) async {
    final r = await _send('PUT', '/api/projects/$projectId/doc', body: {'base_version': baseVersion, 'doc': doc});
    if (r.statusCode == 409) {
      final j = _decode(r) as Map<String, dynamic>;
      throw DocConflict(ServerDoc(j['version'] as int, (j['doc'] as Map?)?.cast<String, dynamic>()));
    }
    if (r.statusCode >= 400) throw _error(r);
    return (_decode(r) as Map<String, dynamic>)['version'] as int;
  }

  @override
  Future<Set<String>> missingSamples(List<String> hashes) async {
    final j = await _json('POST', '/api/samples/missing', {'hashes': hashes}) as Map<String, dynamic>;
    return {for (final h in j['missing'] as List) h as String};
  }

  @override
  Future<void> putSample(String hash, Uint8List bytes) async {
    final r = await _send('PUT', '/api/samples/$hash', bytes: bytes);
    if (r.statusCode >= 400) throw _error(r);
  }

  @override
  Future<Uint8List?> getSample(String hash) async {
    final r = await _send('GET', '/api/samples/$hash');
    if (r.statusCode == 404) return null;
    if (r.statusCode >= 400) throw _error(r);
    return r.bodyBytes;
  }

  // ---- armazenamento de áudios (tela Conta) ----
  Future<StorageUsage> storageUsage() async => StorageUsage.fromJson(await _get('/api/samples') as Map<String, dynamic>);

  /// Apaga um áudio sem uso; devolve os bytes liberados. Em uso, o servidor responde 409.
  Future<int> deleteSample(String hash) async => ((await _delete('/api/samples/$hash')) as Map<String, dynamic>)['freed_bytes'] as int;

  Future<CleanupResult> cleanupSamples() async => CleanupResult.fromJson(await _json('POST', '/api/samples/cleanup', {}) as Map<String, dynamic>);

  @override
  Future<SyncJob> createJob(String kind, String sample, [Map<String, dynamic> params = const {}]) async =>
      SyncJob.fromJson(await _json('POST', '/api/jobs', {'kind': kind, 'sample': sample, 'params': params}) as Map<String, dynamic>);

  @override
  Future<SyncJob> job(String id) async => SyncJob.fromJson(await _get('/api/jobs/$id') as Map<String, dynamic>);
}
