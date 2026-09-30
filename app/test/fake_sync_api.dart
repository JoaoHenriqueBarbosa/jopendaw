/// Servidor de mentira para os testes de sincronização e de jobs: guarda o documento, os áudios e
/// um roteiro de jobs, e anota cada chamada na ordem em que chegou.
library;

import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:jopendaw_app/api/sync_api.dart';

class FakeSyncApi implements SyncApi {
  int version = 0;
  Map<String, dynamic>? doc;
  final samples = <String, Uint8List>{};

  /// Cada chamada, na ordem: `doc`, `put_doc:<base>`, `missing`, `put_sample:<hash>`, `get_sample:<hash>`.
  final calls = <String>[];

  /// As próximas [failures] chamadas de rede falham com [failure].
  int failures = 0;
  Object failure = http.ClientException('sem rede');

  /// O próximo PUT do documento responde 409 com esta versão do servidor.
  ServerDoc? conflictNext;

  /// O próximo PUT do documento responde 422 citando estes áudios (e o servidor os perde), como um apagar no meio.
  Set<String>? missingNext;

  /// Os jobs: `createJob` devolve o primeiro, cada `job` devolve o seguinte (o último se repete).
  List<SyncJob> script = [];
  final jobsCreated = <(String, String)>[];
  int _polled = 0;

  void _maybeFail() {
    if (failures > 0) {
      failures--;
      throw failure;
    }
  }

  @override
  Future<ServerDoc> projectDoc(String projectId) async {
    calls.add('doc');
    _maybeFail();
    return ServerDoc(version, doc);
  }

  @override
  Future<int> putProjectDoc(String projectId, int baseVersion, Map<String, dynamic> d) async {
    calls.add('put_doc:$baseVersion');
    _maybeFail();
    final c = conflictNext;
    if (c != null) {
      conflictNext = null;
      throw DocConflict(c);
    }
    final m = missingNext;
    if (m != null) {
      missingNext = null;
      samples.removeWhere((h, _) => m.contains(h));
      throw DocSamplesMissing(m, 'um áudio citado pelo projeto foi apagado neste instante');
    }
    if (baseVersion != version) throw DocConflict(ServerDoc(version, doc));
    doc = d;
    return ++version;
  }

  @override
  Future<Set<String>> missingSamples(List<String> hashes) async {
    calls.add('missing');
    _maybeFail();
    return {
      for (final h in hashes)
        if (!samples.containsKey(h)) h,
    };
  }

  @override
  Future<void> putSample(String hash, Uint8List bytes) async {
    calls.add('put_sample:$hash');
    _maybeFail();
    samples[hash] = bytes;
  }

  @override
  Future<Uint8List?> getSample(String hash) async {
    calls.add('get_sample:$hash');
    _maybeFail();
    return samples[hash];
  }

  @override
  Future<SyncJob> createJob(String kind, String sample, [Map<String, dynamic> params = const {}]) async {
    calls.add('job:$kind');
    _maybeFail();
    jobsCreated.add((kind, sample));
    return script.first;
  }

  @override
  Future<SyncJob> job(String id) async {
    _maybeFail();
    _polled = (_polled + 1).clamp(0, script.length - 1);
    return script[_polled];
  }
}
