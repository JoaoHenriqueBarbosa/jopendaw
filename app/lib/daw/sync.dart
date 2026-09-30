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

  /// Não dá para trocar o documento agora (gravando, tocando ou com um gesto em andamento): o pull
  /// periódico espera.
  bool get busyEditing => false;
}

/// Igualdade estrutural de dois JSONs (números por valor, chaves sem ordem): o servidor guarda o
/// documento como JSONB, que reordena as chaves.
bool jsonEquals(Object? a, Object? b) {
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      if (!b.containsKey(k) || !jsonEquals(a[k], b[k])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!jsonEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
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

  /// Quanto espera para tentar trazer o documento de novo quando o projeto está ocupado (gravando, tocando, gesto).
  static const busyRetry = Duration(seconds: 2);

  /// Espera entre o reenvio dos áudios e a nova tentativa depois de um 422 (cresce a cada tentativa).
  static const missingBackoff = Duration(milliseconds: 250);

  /// Quantas vezes o envio reenvia áudios e tenta de novo depois de um 422 (áudio citado apagado no meio).
  static const maxMissingRetries = 3;

  /// De quanto em quanto tempo traz, sem nada pendente aqui, o que outro aparelho mudou.
  static const pullEvery = Duration(seconds: 30);

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
  Timer? _timer, _pullTimer;
  final _serverHas = <String>{};

  String get _key => 'sync:$projectId';

  @visibleForTesting
  int get knownVersion => _version;
  bool get hasPending => _dirty;

  /// Lê o estado guardado e faz a primeira conversa com o servidor. [localExisted]: já havia um
  /// documento guardado neste aparelho (sem estado de sincronização ele conta como pendente).
  ///
  /// [holdFirstPull]: a abertura está esperando esta conversa para mostrar o estúdio (projeto que só
  /// existe no servidor). Se o projeto estiver ocupado (gravando, tocando, gesto), a primeira rodada
  /// espera aqui dentro, em vez de voltar e deixar o estúdio vazio aparecer para ser trocado depois.
  Future<void> start({required bool localExisted, bool holdFirstPull = false}) {
    _holdPull = holdFirstPull;
    return starting = _start(localExisted);
  }

  bool _holdPull = false, _pullWasBusy = false;

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
    if (!_disposed) _pullTimer = Timer.periodic(pullEvery * timeScale, (_) => unawaited(pullNow()));
    await syncNow();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (phase == SyncPhase.offline || phase == SyncPhase.error || _dirty || !_pulled) {
      unawaited(syncNow());
    } else {
      unawaited(pullNow());
    }
  }

  /// Pull leve: só olha se o servidor tem versão mais nova e, se tiver e nada local está pendente,
  /// troca o documento. Fica calado (sem ícone piscando, sem erro) quando não dá para fazer, e
  /// nunca sobrescreve trabalho local: se a pessoa editar no meio, o envio seguinte cai no
  /// conflito de sempre. Devolve se trocou o documento.
  Future<bool> pullNow() async {
    if (_disposed || !canSync() || !_pulled || _busy || _dirty || conflict != null || phase == SyncPhase.off || host.busyEditing) return false;
    _busy = true;
    try {
      final gen = _gen;
      final s = await api.projectDoc(projectId);
      final doc = s.doc;
      if (_disposed || gen != _gen || _dirty || conflict != null || doc == null || s.version <= _version) return false;
      final applied = await host.applyRemote(doc, progress: _progress, canSwap: () => gen == _gen && !_dirty && !host.busyEditing);
      if (!applied) return false;
      _version = s.version;
      await _persist();
      filesDone = filesTotal = 0;
      _notify();
      return true;
    } catch (_) {
      return false;
    } finally {
      _busy = false;
      if (_again && !_disposed) unawaited(syncNow());
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
        while (_pullWasBusy && !_pulled && conflict == null && !_disposed && canSync()) {
          _pullWasBusy = false;
          await Future<void>.delayed(busyRetry * math.min(1.0, timeScale));
          if (_disposed) return;
          await _pull();
        }
        // não trouxe ainda (o projeto estava ocupado com gravação ou gesto): a rodada volta sozinha
        if (conflict != null || !_pulled) return;
      }
      if (_dirty) {
        await _push();
      } else if (phase != SyncPhase.synced) {
        _set(SyncPhase.synced);
      }
      _failures = 0;
    } on DocConflict catch (e) {
      if (_sameAsLocal(e.server)) {
        // o envio chegou, só a resposta se perdeu: o servidor já tem exatamente este documento
        await _adopt(e.server);
        _failures = 0;
        _set(_dirty ? SyncPhase.syncing : SyncPhase.synced);
        if (_dirty) _again = true;
      } else {
        conflict = e.server;
        _set(SyncPhase.conflict);
      }
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
    // o servidor respondeu: as falhas de rede de antes acabaram, mesmo que a rodada saia sem trocar o documento
    _failures = 0;
    _pullWasBusy = false;
    if (s.version > _version && s.doc != null) {
      if (_sameAsLocal(s)) {
        // o servidor já tem exatamente este documento (um envio cuja resposta se perdeu)
        await _adopt(s);
      } else if (_dirty) {
        conflict = s;
        _set(SyncPhase.conflict);
        return;
      } else {
        final gen = _gen;
        final applied = await host.applyRemote(s.doc!, progress: _progress, canSwap: () => gen == _gen && !host.busyEditing);
        if (!applied) {
          if (gen == _gen && !_dirty) {
            // gravando, tocando ou com um gesto em andamento (e nada editado): não é conflito, só não dá para trocar
            // o documento agora. Não marca como trazido; tenta de novo daqui a pouco
            if (_holdPull) {
              _pullWasBusy = true; // a própria rodada espera e repete (ver _step)
              return;
            }
            _timer?.cancel();
            _timer = Timer(busyRetry * timeScale, () => unawaited(syncNow()));
            return;
          }
          // o usuário editou enquanto os áudios desciam: agora há os dois lados
          conflict = s;
          _set(SyncPhase.conflict);
          return;
        }
        _version = s.version;
        await _persist();
      }
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

  /// O documento do servidor é estruturalmente o mesmo que o deste aparelho.
  bool _sameAsLocal(ServerDoc s) => s.doc != null && jsonEquals(s.doc, host.docJson());

  /// Adota a versão do servidor como a conhecida, sem mexer no documento (ele já é igual).
  Future<void> _adopt(ServerDoc s) async {
    _version = s.version;
    _dirty = false;
    _gen++;
    await _persist();
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
    final hashes = host.sampleHashes();
    String? sampleError = await _uploadForPush(hashes);
    // 422: um áudio citado foi apagado no servidor no instante do envio. Reenvia os citados em `missing` (a lista do que o
    // servidor já tinha vale menos que a resposta dele) e tenta de novo, com um recuo curto e limite. Se este aparelho
    // também não tem o áudio, reenviar não adianta: para logo
    for (var attempt = 0; ; attempt++) {
      try {
        _version = await api.putProjectDoc(projectId, _version, json);
        break;
      } on DocSamplesMissing catch (e) {
        _serverHas.removeAll(e.hashes);
        var absentHere = false;
        for (final h in e.hashes) {
          if (await store.get('sample:$h') is! Uint8List) absentHere = true;
        }
        if (absentHere) {
          throw SyncFailure('${e.message}. Faltam áudios neste aparelho: abra o projeto onde eles estão e tente de novo.');
        }
        if (attempt >= maxMissingRetries) {
          throw SyncFailure('${e.message}. Não consegui reenviar o áudio; abra o projeto no aparelho que o tem e tente de novo.');
        }
        await Future<void>.delayed(missingBackoff * (attempt + 1) * math.min(1.0, timeScale));
        if (_disposed) return;
        sampleError = await _uploadForPush(e.hashes) ?? sampleError;
      }
    }
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

  /// Sobe os áudios do envio. Erro que repetir não resolve (cota, tamanho) vira o texto do aviso e o documento segue
  /// mesmo assim (o outro aparelho vê o áudio como faltando); erro de rede ou 5xx sobe.
  Future<String?> _uploadForPush(Iterable<String> hashes) async {
    try {
      await uploadSamples(hashes);
    } on ApiException catch (e) {
      if (e.status >= 500 || e.status == 408 || e.status == 429) rethrow;
      return 'Alguns áudios não foram enviados: ${e.message}';
    }
    return null;
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
        // o documento não troca com um salvamento local pendente (edição dos últimos 400 ms):
        // a pessoa já escolheu o servidor, então espera o salvamento passar e tenta de novo
        var applied = false;
        for (var i = 0; i < 4 && !applied; i++) {
          if (i > 0) await Future<void>.delayed(const Duration(milliseconds: 450));
          if (_disposed) return;
          applied = await host.applyRemote(doc, progress: _progress, canSwap: () => !host.busyEditing);
        }
        if (!applied) {
          _set(
            SyncPhase.conflict,
            host.busyEditing
                ? 'Há uma gravação, a reprodução ou um gesto em andamento e o projeto não pôde ser trocado. Termine e tente de novo.'
                : 'Você editou agora há pouco e o projeto não pôde ser trocado. Tente de novo.',
          );
          return;
        }
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
    _pullTimer?.cancel();
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
