/// Exportar em FLAC e MP3: o WAV renderizado no aparelho sobe ao servidor, uma tarefa `encode_audio` o converte, o
/// arquivo volta e é salvo. Sem sessão, sem rede ou com erro do servidor, o WAV já renderizado fica guardado para a
/// pessoa salvá-lo mesmo assim, sem renderizar de novo.
library;

import 'dart:async';

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter/foundation.dart';

import '../api/client.dart' show ApiException, Unauthenticated;
import '../api/export_api.dart';
import '../api/sync_api.dart' show JobStatus;
import '../audio/engine.dart' show RenderCanceled;
import 'export_options.dart';

/// Um WAV renderizado que não pôde ser compactado: espera a pessoa escolher salvá-lo assim.
class PendingWav {
  final String name;
  final Uint8List bytes;
  const PendingWav(this.name, this.bytes);
}

/// A tarefa falhou no servidor (a mensagem já vem em português, do próprio servidor).
class _JobFailed implements Exception {
  final String message;
  _JobFailed(this.message);
}

/// Troca a extensão `.wav` do nome de arquivo do render pela do formato compactado.
String compressedName(String wavName, ExportFormat format) {
  final base = wavName.toLowerCase().endsWith('.wav') ? wavName.substring(0, wavName.length - 4) : wavName;
  return '$base.${format.extension}';
}

/// Converte, um arquivo por vez (a mixagem e depois cada stem, em série), os WAV que o render entrega. Vira um
/// [ChangeNotifier] para a janela de andamento mostrar a etapa e o progresso.
class CompressedExport extends ChangeNotifier {
  final ExportApi api;
  final ExportOptions options;

  /// Para o metadado `album` dos arquivos (o nome do projeto).
  final String album;

  /// Quantos arquivos se espera (mixagem e stems), só para a barra andar de forma proporcional.
  final int expectedFiles;

  /// Como um arquivo compactado é salvo (o mesmo caminho dos WAV).
  final Future<bool> Function(String name, Uint8List bytes, String mime) save;
  final bool Function() signedIn;
  final Future<void> Function(Duration) delay;
  final Duration pollEvery;
  final Duration maxWait;

  /// As esperas entre as tentativas de apagar o que a limpeza não conseguiu (tarefa ainda rodando no servidor).
  final List<Duration> retryDelays;

  CompressedExport({
    required this.api,
    required this.options,
    required this.album,
    required this.save,
    required this.signedIn,
    this.expectedFiles = 1,
    this.delay = _sleep,
    this.pollEvery = const Duration(milliseconds: 800),
    this.maxWait = const Duration(minutes: 20),
    this.retryDelays = const [Duration(seconds: 3), Duration(seconds: 10), Duration(seconds: 30)],
  });

  static Future<void> _sleep(Duration d) => Future<void>.delayed(d);

  /// O que não deu para compactar, na ordem em que o render entregou.
  final fallbacks = <PendingWav>[];

  /// Por que caiu para WAV (null enquanto tudo deu certo).
  String? failure;

  /// Avisos do servidor sobre perdas na conversão (repetidos entre arquivos aparecem uma vez).
  final warnings = <String>[];

  /// Arquivos já salvos compactados.
  int compressed = 0;

  /// A pessoa fechou a janela "Salvar" do aparelho sem escolher onde: não conta como salvo, e a exportação para ali
  /// (não abre outra janela por stem). [canceledName] é o arquivo que ficou sem salvar.
  bool saveCanceled = false;
  String? canceledName;

  /// Etapa em andamento, para a janela ("Enviando…", "Compactando 40%…"); null fora de um arquivo.
  String? stage;

  /// 0..1 de todos os arquivos esperados.
  double fraction = 0;

  bool _canceled = false;
  int _index = 0;

  /// Interrompe: o que estiver esperando o servidor larga a espera, e a limpeza pede ao servidor que cancele a tarefa
  /// (ele a interrompe e não guarda o resultado; um servidor antigo responde 409, e a limpeza tenta de novo aos poucos).
  void cancel() {
    _canceled = true;
  }

  void _progress(String text, double within) {
    stage = text;
    fraction = ((_index + within.clamp(0.0, 1.0)) / expectedFiles.clamp(1, 1 << 20)).clamp(0.0, 0.999).toDouble();
    notifyListeners();
  }

  void _checkCanceled() {
    if (_canceled) throw const RenderCanceled();
  }

  /// Recebe um WAV do render (nome já com `.wav`): compacta e salva, ou guarda para a queda para WAV.
  Future<void> deliver(String wavName, Uint8List wav) async {
    _checkCanceled();
    if (failure != null) {
      fallbacks.add(PendingWav(wavName, wav));
      _index++;
      return;
    }
    if (!signedIn()) {
      failure = 'Entre na sua conta para exportar em ${options.format == ExportFormat.mp3 ? 'MP3' : 'FLAC'}: a conversão é feita no servidor.';
      fallbacks.add(PendingWav(wavName, wav));
      _index++;
      return;
    }
    try {
      await _compress(wavName, wav);
      if (saveCanceled) throw const RenderCanceled();
      compressed++;
    } on RenderCanceled {
      rethrow;
    } catch (e) {
      failure = _describe(e);
      fallbacks.add(PendingWav(wavName, wav));
    } finally {
      _index++;
      stage = null;
      notifyListeners();
    }
  }

  String _describe(Object e) => switch (e) {
    Unauthenticated() => 'Sua sessão terminou; entre de novo para exportar em ${options.format == ExportFormat.mp3 ? 'MP3' : 'FLAC'}.',
    ApiException(:final message) => message,
    _JobFailed(:final message) => message,
    TimeoutException() => 'O servidor demorou demais para responder.',
    StateError(:final message) => message,
    _ => 'Não consegui falar com o servidor (sem conexão?).',
  };

  Future<void> _compress(String wavName, Uint8List wav) async {
    final hash = sha256.convert(wav).toString();
    var uploaded = false;
    String? jobId, out;
    try {
      _progress('Enviando ao servidor (${_mb(wav.length)})…', 0);
      // um WAV idêntico que já estava na conta não é do exportador: não se apaga depois
      uploaded = (await api.missingSamples([hash])).contains(hash);
      if (uploaded) await api.putSample(hash, wav);
      _checkCanceled();
      final title = wavName.toLowerCase().endsWith('.wav') ? wavName.substring(0, wavName.length - 4) : wavName;
      final artist = options.artist.trim();
      var job = await api.createJob('encode_audio', hash, {
        ...options.encodeParams,
        'title': title,
        if (artist.isNotEmpty) 'artist': artist,
        if (album.isNotEmpty) 'album': album,
      });
      jobId = job.id;
      final deadline = DateTime.now().add(maxWait);
      var failedPolls = 0;
      while (job.status == JobStatus.queued || job.status == JobStatus.running) {
        _progress(
          job.status == JobStatus.queued ? 'Na fila do servidor…' : 'Compactando no servidor ${(100 * (job.progress ?? 0)).floor()}%…',
          0.1 + 0.8 * (job.progress ?? 0),
        );
        _checkCanceled();
        if (DateTime.now().isAfter(deadline)) throw TimeoutException('a conversão passou de ${maxWait.inMinutes} minutos');
        await delay(pollEvery);
        _checkCanceled();
        try {
          job = await api.job(job.id);
          failedPolls = 0;
        } on Unauthenticated {
          rethrow;
        } on ApiException {
          rethrow;
        } catch (_) {
          // um tropeço de rede na espera não derruba a exportação: três seguidos, sim
          if (++failedPolls >= 3) rethrow;
        }
      }
      if (job.status == JobStatus.failed) throw _JobFailed(job.error ?? 'A conversão falhou no servidor.');
      final result = job.result ?? const {};
      out = result['sample'] as String?;
      if (out == null) throw _JobFailed('O servidor não devolveu o arquivo convertido.');
      _progress('Baixando o arquivo…', 0.92);
      final bytes = await api.getSample(out);
      if (bytes == null) throw _JobFailed('O arquivo convertido sumiu do servidor.');
      for (final w in (result['warnings'] as List? ?? const [])) {
        if (w is String && !warnings.contains(w)) warnings.add(w);
      }
      _progress('Salvando…', 0.98);
      final name = _savedName(result, wavName);
      if (!await save(name, bytes, options.format.mime)) {
        // a janela "Salvar" foi fechada: nada foi salvo, e dizer que sim apagaria o resultado por nada
        saveCanceled = true;
        canceledName = name;
      }
    } finally {
      // limpeza silenciosa: a tarefa (uma em andamento é cancelada lá), o resultado e o WAV temporário saem da conta. O
      // que falhar com 409 (a tarefa ainda roda, num servidor que não a cancela) é tentado de novo aos poucos, sem
      // segurar a janela; o que sobrar fica como áudio sem uso para a limpeza da tela Conta
      final retry = <Future<void> Function()>[];
      Future<void> tidy(Future<void> Function() f) async {
        try {
          await f();
        } on ApiException catch (e) {
          if (e.status == 409) retry.add(f);
        } catch (_) {}
      }

      await tidy(() async {
        if (jobId != null) await api.deleteJob(jobId);
      });
      await tidy(() async {
        if (out != null) await api.deleteSample(out, force: true);
      });
      await tidy(() async {
        if (uploaded) await api.deleteSample(hash, force: true);
      });
      if (retry.isNotEmpty) unawaited(_retryTidy(retry, jobId));
    }
  }

  /// Nome do arquivo: o que o servidor sugere (artista e título) quando vem com a extensão do formato; senão, o do WAV.
  String _savedName(Map<String, dynamic> result, String wavName) {
    final suggested = result['filename'];
    if (suggested is String && suggested.toLowerCase().endsWith('.${options.format.extension}') && suggested.length > options.format.extension.length + 1) {
      return suggested;
    }
    return compressedName(wavName, options.format);
  }

  /// Insiste na limpeza que deu 409, em [retryDelays]: a tarefa (se ainda roda) é apagada primeiro, e só então o WAV.
  Future<void> _retryTidy(List<Future<void> Function()> pending, String? jobId) async {
    for (final wait in retryDelays) {
      await delay(wait);
      final still = <Future<void> Function()>[];
      for (final f in pending) {
        try {
          await f();
        } on ApiException catch (e) {
          if (e.status == 409) still.add(f);
        } catch (_) {}
      }
      pending = still;
      if (pending.isEmpty) return;
    }
  }

  String _mb(int bytes) => bytes < 1 << 20 ? '${(bytes / 1024).ceil()} KB' : '${(bytes / (1 << 20)).toStringAsFixed(1).replaceAll('.', ',')} MB';

  /// "Exportar em WAV mesmo assim": salva os WAV já renderizados que não foram compactados. Devolve quantos foram
  /// salvos e para no primeiro que a pessoa deixou sem salvar (fechou a janela "Salvar"): os outros continuam em
  /// [fallbacks].
  Future<int> saveWavs() async {
    var saved = 0;
    for (final p in List<PendingWav>.of(fallbacks)) {
      if (!await save(p.name, p.bytes, 'audio/wav')) break;
      fallbacks.remove(p);
      saved++;
    }
    notifyListeners();
    return saved;
  }
}
