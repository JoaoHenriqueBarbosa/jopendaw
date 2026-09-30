/// O que a sincronização e os jobs pedem ao servidor, espelhando `server/src/routes/` (documento do
/// projeto, samples e jobs). É uma interface para o `ApiClient` real e um cliente falso nos testes
/// trocarem de lugar.
library;

import 'dart:typed_data';

/// O documento do projeto no servidor. Versão 0 e [doc] null quando ele ainda não recebeu nenhum.
class ServerDoc {
  final int version;
  final Map<String, dynamic>? doc;
  const ServerDoc(this.version, this.doc);
}

/// O servidor recusou o envio porque a versão-base não é mais a atual (409): devolve a atual.
class DocConflict implements Exception {
  final ServerDoc server;
  DocConflict(this.server);
  @override
  String toString() => 'o projeto mudou em outro aparelho';
}

/// O servidor recusou o envio (422) porque um áudio que o documento passou a citar foi apagado no instante: reenviar
/// os áudios de [hashes] e tentar de novo resolve.
class DocSamplesMissing implements Exception {
  final Set<String> hashes;
  final String message;
  DocSamplesMissing(this.hashes, this.message);
  @override
  String toString() => message;
}

enum JobStatus {
  queued,
  running,
  done,
  failed;

  static JobStatus parse(Object? s) => JobStatus.values.firstWhere((v) => v.name == s, orElse: () => JobStatus.running);
}

/// Uma tarefa pesada do servidor (`flac`, `audio_to_midi`).
class SyncJob {
  final String id;
  final JobStatus status;

  /// 0..1, ou null quando o servidor não sabe.
  final double? progress;
  final String? error;
  final Map<String, dynamic>? result;

  const SyncJob(this.id, this.status, {this.progress, this.error, this.result});

  SyncJob.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      status = JobStatus.parse(j['status']),
      progress = _fraction(j['progress']),
      error = j['error'] as String?,
      result = j['result'] is Map ? (j['result'] as Map).cast<String, dynamic>() : null;

  /// O servidor pode mandar 0..1 ou uma porcentagem (0..100).
  static double? _fraction(Object? p) {
    if (p is! num) return null;
    final v = p > 1 ? p / 100 : p.toDouble();
    return v.clamp(0.0, 1.0).toDouble();
  }
}

abstract class SyncApi {
  Future<ServerDoc> projectDoc(String projectId);

  /// Devolve a nova versão. Lança [DocConflict] se [baseVersion] não é a atual e [DocSamplesMissing] se um áudio citado
  /// sumiu do servidor no meio do envio.
  Future<int> putProjectDoc(String projectId, int baseVersion, Map<String, dynamic> doc);

  /// Dos hashes dados, os que o servidor não tem.
  Future<Set<String>> missingSamples(List<String> hashes);

  Future<void> putSample(String hash, Uint8List bytes);

  /// Null quando o servidor não tem o sample (404).
  Future<Uint8List?> getSample(String hash);

  Future<SyncJob> createJob(String kind, String sample, [Map<String, dynamic> params = const {}]);
  Future<SyncJob> job(String id);
}
