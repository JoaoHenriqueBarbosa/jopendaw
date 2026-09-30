/// Sincronização do projeto entre aparelhos, sem nunca atrapalhar o trabalho local.
///
/// O documento e os áudios moram primeiro no aparelho (abre na hora, edita offline). Em segundo
/// plano este serviço conversa com o servidor: traz a versão mais nova quando não há nada
/// pendente aqui, envia o que mudou (áudios antes do documento) e, se os dois lados mudaram,
/// para e deixa a pessoa escolher, sem sobrescrever nada por conta própria.
///
/// O estado por projeto fica no guardado local (`sync:<id>`): a versão do servidor que este
/// aparelho conhece e se há mudanças ainda não enviadas. Sobrevive a fechar o app no meio.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../api/client.dart';
import '../api/sync_api.dart';
import '../audio/engine.dart';

/// O que o serviço precisa do controlador do projeto.
abstract class SyncHost {
  /// O documento de agora, pronto para enviar.
  Map<String, dynamic> docJson();

  /// Todos os áudios que o documento cita.
  Set<String> sampleHashes();

  /// Troca o documento local pelo do servidor (baixando antes os áudios que faltam). Só troca se
  /// [canSwap] ainda disser que nada local mudou no meio do caminho; devolve se trocou.
  Future<bool> applyRemote(Map<String, dynamic> doc, {required void Function(int done, int total) progress, required bool Function() canSwap});

  /// Tenta baixar os áudios que o documento cita e este aparelho não tem.
  Future<void> fetchMissing();
}

/// Falha que repetir não resolve (documento do servidor ilegível, cota estourada).
class SyncFailure implements Exception {
  final String message;
  SyncFailure(this.message);
  @override
  String toString() => message;
}

enum SyncPhase {
  /// Sem sessão (ou ainda não começou): nada a mostrar.
  off,
  synced,
  syncing,

  /// Sem rede ou servidor fora: tenta de novo sozinho.
  offline,
  conflict,
  error,
}

class SyncService extends ChangeNotifier with WidgetsBindingObserver {
  SyncService({required this.projectId, required this.api, required this.store, required this.host, required this.canSync, this.timeScale = 1});

  final String projectId;
  final SyncApi api;
  final LocalStore store;
  final SyncHost host;

  /// Só há envio com usuário autenticado.
  final bool Function() canSync;

  /// Encurta os tempos (espera do envio e recuo) nos testes.
  final double timeScale;

  /// Espera depois da última edição antes de enviar.
  static const debounce = Duration(seconds: 3);
  static const maxBackoff = Duration(minutes: 2);

  SyncPhase phase = SyncPhase.off;

  /// Arquivos enviados/baixados e o total, enquanto [phase] é `syncing` com áudios a mover.
  int filesDone = 0, filesTotal = 0;

  /// Detalhe do erro ou do offline, para o tooltip.
  String? message;

  /// A versão do servidor que disputa com a local (fase `conflict`).
  ServerDoc? conflict;

  /// Quando tenta de novo depois de uma falha de rede (valor nominal, sem [timeScale]).
  Duration? retryIn;

  int _version = 0;
  bool _dirty = false;

  /// Conta as edições: um envio que termina depois de outra edição não zera o pendente.
  int _gen = 0;
  bool _pulled = false, _busy = false, _again = false, _disposed = false, _observing = false;
  int _failures = 0;
  Timer? _timer;
  final _serverHas = <String>{};

  String get _key => 'sync:$projectId';

  @visibleForTesting
  int get knownVersion => _version;
  bool get hasPending => _dirty;

  /// Lê o estado guardado e faz a primeira conversa com o servidor. [localExisted]: já havia um
  /// documento guardado neste aparelho (sem estado de sincronização ele conta como pendente).
  Future<void> start({required bool localExisted}) => starting = _start(localExisted);

  /// A primeira conversa (testes esperam por ela).
  @visibleForTesting
  Future<void>? starting;

  @visibleForTesting
  bool get busy => _busy;

  Future<void> _start(bool localExisted) async {
    try {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    } catch (_) {
      // sem binding (testes de unidade): só não acompanha o voltar ao primeiro plano
    }
    final raw = await store.get(_key);
    var restored = false;
    if (raw is String) {
      try {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        _version = j['version'] as int;
        _dirty = j['dirty'] == true;
        restored = true;
      } catch (_) {
        // estado ilegível: vale como se não houvesse
      }
    }
    if (!restored) {
      _version = 0;
      _dirty = localExisted;
      // fixa o estado da primeira abertura: um documento local que só existe porque foi criado
      // aqui (sem edição) não pode virar "mudança pendente" na abertura seguinte
      await _persist();
    }
    await syncNow();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && (phase == SyncPhase.offline || phase == SyncPhase.error || _dirty || !_pulled)) {
      unawaited(syncNow());
    }
  }

  /// O documento foi salvo com mudanças: marca pendente e agenda o envio.
  Future<void> markDirty() async {
    _gen++;
    _dirty = true;
    await _persist();
    if (_disposed || !canSync() || conflict != null) return;
    // em recuo depois de uma falha, o próprio recuo decide quando tentar de novo
    if (retryIn != null) return;
    if (phase == SyncPhase.synced) _set(SyncPhase.syncing);
    _timer?.cancel();
    _timer = Timer(debounce * timeScale, () => unawaited(syncNow()));
  }

  /// Uma rodada: primeiro traz (se ainda não trouxe), depois envia o pendente. Nunca lança.
  Future<void> syncNow() async {
    if (_disposed) return;
    if (!canSync()) {
      _set(SyncPhase.off);
      return;
    }
    if (_busy) {
      _again = true;
      return;
    }
    _busy = true;
    _timer?.cancel();
    retryIn = null;
    try {
      do {
        _again = false;
        await _step();
      } while (_again && !_disposed && conflict == null && phase != SyncPhase.off);
    } finally {
      _busy = false;
    }
  }

  Future<void> _step() async {
    try {
      if (conflict != null) return;
      if (!_pulled) {
        _set(SyncPhase.syncing);
        await _pull();
        if (conflict != null) return;
      }
      if (_dirty) {
        await _push();
      } else if (phase != SyncPhase.synced) {
        _set(SyncPhase.synced);
      }
      _failures = 0;
    } on DocConflict catch (e) {
      conflict = e.server;
      _set(SyncPhase.conflict);
    } on Unauthenticated {
      // sessão acabou: o app volta ao login; o que está pendente segue guardado
      _set(SyncPhase.off);
    } on SyncFailure catch (e) {
      _set(SyncPhase.error, e.message);
    } on ApiException catch (e) {
      if (e.status >= 500 || e.status == 408 || e.status == 429) {
        _backoff();
      } else {
        _set(SyncPhase.error, e.message);
      }
    } catch (_) {
      // sem rede, tempo esgotado, servidor fora: nada disso chega à interface como exceção
      _backoff();
    }
  }

  void _backoff() {
    _failures++;
    final delay = Duration(seconds: math.min(maxBackoff.inSeconds, 1 << math.min(_failures, 10)));
    retryIn = delay;
    _set(SyncPhase.offline);
    _timer?.cancel();
    _timer = Timer(delay * timeScale, () => unawaited(syncNow()));
  }

  Future<void> _pull() async {
    final s = await api.projectDoc(projectId);
    if (s.version > _version && s.doc != null) {
      if (_dirty) {
        conflict = s;
        _set(SyncPhase.conflict);
        return;
      }
      final gen = _gen;
      final applied = await host.applyRemote(s.doc!, progress: _progress, canSwap: () => gen == _gen);
      if (!applied) {
        // o usuário editou enquanto os áudios desciam: agora há os dois lados
        conflict = s;
        _set(SyncPhase.conflict);
        return;
      }
      _version = s.version;
      await _persist();
    } else if (s.version < _version) {
      // o servidor voltou atrás (restauração): o local é a verdade e vai por cima
      _version = s.version;
      _dirty = true;
      await _persist();
    }
    _pulled = true;
    try {
      await host.fetchMissing();
    } catch (_) {
      // áudio que não baixou continua marcado como faltando; não atrapalha o resto
    }
  }

  void _progress(int done, int total) {
    filesDone = done;
    filesTotal = total;
    _notify();
  }

  Future<void> _push() async {
    _set(SyncPhase.syncing);
    filesDone = filesTotal = 0;
    final gen = _gen;
    final json = host.docJson();
    String? sampleError;
    try {
      await uploadSamples(host.sampleHashes());
    } on ApiException catch (e) {
      // cota ou tamanho: o documento segue mesmo assim (o outro aparelho vê o áudio como faltando)
      if (e.status >= 500 || e.status == 408 || e.status == 429) rethrow;
      sampleError = 'Alguns áudios não foram enviados: ${e.message}';
    }
    _version = await api.putProjectDoc(projectId, _version, json);
    if (gen == _gen) {
      _dirty = false;
    } else {
      _again = true;
    }
    await _persist();
    filesDone = filesTotal = 0;
    if (sampleError != null) {
      _set(SyncPhase.error, sampleError);
    } else {
      _set(_dirty ? SyncPhase.syncing : SyncPhase.synced);
    }
  }

  /// Garante no servidor os áudios dados que ele não tem, um por vez, a partir do guardado local
  /// (os que este aparelho também não tem ficam de fora). Usado pelo envio e pela conversão em MIDI.
  Future<void> uploadSamples(Iterable<String> hashes) async {
    final absent = [
      for (final h in hashes)
        if (!_serverHas.contains(h)) h,
    ];
    if (absent.isEmpty) return;
    final missing = await api.missingSamples(absent);
    _serverHas.addAll(absent.where((h) => !missing.contains(h)));
    final todo = <(String, Uint8List)>[];
    for (final h in missing) {
      final bytes = await store.get('sample:$h');
      if (bytes is Uint8List) todo.add((h, bytes));
    }
    var done = 0;
    filesTotal = todo.length;
    filesDone = 0;
    _notify();
    ApiException? failed;
    for (final (h, bytes) in todo) {
      try {
        await api.putSample(h, bytes);
        _serverHas.add(h);
      } on ApiException catch (e) {
        if (e.status >= 500 || e.status == 408 || e.status == 429) rethrow;
        failed ??= e;
      }
      filesDone = ++done;
      _notify();
    }
    if (failed != null) throw failed;
  }

  // ---- conflito ----

  /// Descarta o que há neste aparelho e fica com a versão do servidor.
  Future<void> useServer() async {
    final c = conflict;
    if (c == null || _disposed) return;
    final doc = c.doc;
    if (doc != null) {
      _set(SyncPhase.syncing);
      try {
        await host.applyRemote(doc, progress: _progress, canSwap: () => true);
      } catch (e) {
        // não conseguiu (sem rede, por exemplo): o conflito segue de pé para tentar de novo
        _set(SyncPhase.conflict, e is SyncFailure ? e.message : 'Não deu para baixar a versão do servidor agora.');
        return;
      }
    }
    _version = c.version;
    _dirty = false;
    _gen++;
    _pulled = true;
    conflict = null;
    await _persist();
    _set(SyncPhase.synced);
  }

  /// Mantém a versão deste aparelho e a envia por cima, tomando a do servidor como base.
  Future<void> keepLocal() async {
    final c = conflict;
    if (c == null || _disposed) return;
    _version = c.version;
    _dirty = true;
    _gen++;
    _pulled = true;
    conflict = null;
    await _persist();
    await syncNow();
  }

  // ---- internos ----

  Future<void> _persist() async {
    try {
      await store.put(_key, jsonEncode({'version': _version, 'dirty': _dirty}));
    } catch (_) {
      // sem gravar o estado, o pior caso é mandar de novo na próxima abertura
    }
  }

  void _set(SyncPhase p, [String? msg]) {
    phase = p;
    message = msg;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
