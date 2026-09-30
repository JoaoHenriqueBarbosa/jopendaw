/// O que a exportação em FLAC e MP3 pede ao servidor (subir o WAV, criar a tarefa `encode_audio`, esperar, baixar e
/// apagar). Interface própria, separada da [SyncApi], para o cliente falso dos testes de exportação não depender da
/// sincronização. O [ApiClient] implementa as duas.
library;

import 'dart:typed_data';

import 'sync_api.dart' show SyncJob;

abstract class ExportApi {
  /// Dos hashes dados, os que o servidor não tem (o WAV que já estava lá não é apagado depois).
  Future<Set<String>> missingSamples(List<String> hashes);

  Future<void> putSample(String hash, Uint8List bytes);

  /// Null quando o servidor não tem o áudio (404).
  Future<Uint8List?> getSample(String hash);

  Future<SyncJob> createJob(String kind, String sample, [Map<String, dynamic> params]);
  Future<SyncJob> job(String id);

  /// Apaga o áudio da conta (`force`: também os enviados na última hora). Devolve os bytes liberados.
  Future<int> deleteSample(String hash, {bool force});

  /// Tira a tarefa do histórico da conta.
  Future<void> deleteJob(String id);
}
