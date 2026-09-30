/// Áudio para MIDI: o servidor analisa o áudio (job `audio_to_midi`) e devolve as notas em
/// segundos; aqui elas viram um clipe MIDI posicionado sobre o clipe de áudio de origem.
library;

import 'dart:async';
import 'dart:math' as math;

import '../api/client.dart';
import '../api/sync_api.dart';
import 'model.dart';

/// Os dois ajustes da análise, com os padrões do servidor (`MidiParams::default`). A faixa é a da
/// interface; o servidor aceita mais (0 a 5000 ms, -120 a 0 dB) e recusa o que passar disso.
class MidiConvertOptions {
  static const minNoteMsRange = (20.0, 500.0);
  static const rmsFloorDbRange = (-80.0, -20.0);

  /// Notas mais curtas que isto (em ms) são descartadas.
  final double minNoteMs;

  /// Abaixo deste nível (dB) o trecho conta como silêncio.
  final double rmsFloorDb;

  const MidiConvertOptions({this.minNoteMs = 60, this.rmsFloorDb = -45});

  MidiConvertOptions copyWith({double? minNoteMs, double? rmsFloorDb}) =>
      MidiConvertOptions(minNoteMs: minNoteMs ?? this.minNoteMs, rmsFloorDb: rmsFloorDb ?? this.rmsFloorDb);

  Map<String, dynamic> toParams() => {'min_note_ms': minNoteMs, 'rms_floor_db': rmsFloorDb};
}

/// Uma nota como o servidor a devolve: tempos em segundos do áudio inteiro.
class ServerNote {
  final int pitch;
  final double start, length, velocity;
  const ServerNote(this.pitch, this.start, this.length, this.velocity);
}

/// O resultado do job: as notas e a duração analisada.
class ConvertedNotes {
  final List<ServerNote> notes;
  final double duration;
  const ConvertedNotes(this.notes, this.duration);

  factory ConvertedNotes.fromJson(Map<String, dynamic> j) => ConvertedNotes([
    for (final n in (j['notes'] as List? ?? const []))
      ServerNote(
        (n['pitch'] as num).round().clamp(0, 127),
        (n['start'] as num).toDouble(),
        (n['length'] as num).toDouble(),
        ((n['velocity'] as num?) ?? 0.8).toDouble().clamp(0.01, 1.0),
      ),
  ], (j['duration'] as num? ?? 0).toDouble());
}

/// As notas de [r] como notas de um clipe MIDI que cobre o mesmo trecho do clipe de áudio [clip]:
/// o clipe de áudio toca a partir de `offset` segundos do arquivo por `length` segundos, então só
/// valem as notas (ou pedaços delas) dentro dessa janela, e o zero do clipe MIDI é o `offset`.
/// Segundos viram batidas pelo andamento [bpm].
List<MidiNote> notesForClip(ConvertedNotes r, AudioClip clip, double bpm) {
  final from = clip.offset, to = clip.offset + clip.length;
  final toBeats = bpm / 60;
  final out = <MidiNote>[];
  for (final n in r.notes) {
    final s = math.max(n.start, from), e = math.min(n.start + n.length, to);
    // fora da janela, ou sobrou menos que uma fração de milissegundo
    if (e - s < 1e-4) continue;
    out.add(MidiNote(pitch: n.pitch, start: (s - from) * toBeats, length: (e - s) * toBeats, velocity: n.velocity));
  }
  out.sort((a, b) => a.start != b.start ? a.start.compareTo(b.start) : a.pitch.compareTo(b.pitch));
  return out;
}

/// A conversão foi cancelada pela pessoa.
class ConversionCancelled implements Exception {
  @override
  String toString() => 'conversão cancelada';
}

/// Cria o job e acompanha por polling até terminar. [onProgress] recebe a etapa e a fração (null
/// quando o servidor não informa). Falha do job vira [StateError] com a mensagem do servidor;
/// falha de rede no meio do acompanhamento é tolerada algumas vezes seguidas, já que o job segue
/// no servidor.
Future<ConvertedNotes> runAudioToMidi(
  SyncApi api,
  String sample, {
  void Function(String stage, double? progress)? onProgress,
  bool Function()? isCancelled,
  Duration pollEvery = const Duration(seconds: 1),
  MidiConvertOptions options = const MidiConvertOptions(),
}) async {
  bool cancelled() => isCancelled?.call() ?? false;
  onProgress?.call('Analisando o áudio…', null);
  var job = await api.createJob('audio_to_midi', sample, options.toParams());
  var failures = 0;
  while (true) {
    if (cancelled()) throw ConversionCancelled();
    switch (job.status) {
      case JobStatus.done:
        final result = job.result;
        if (result == null) throw StateError('O servidor terminou sem devolver as notas.');
        return ConvertedNotes.fromJson(result);
      case JobStatus.failed:
        throw StateError(job.error ?? 'A conversão falhou no servidor.');
      case JobStatus.queued:
        onProgress?.call('Na fila do servidor…', null);
      case JobStatus.running:
        onProgress?.call('Analisando o áudio…', job.progress);
    }
    await Future<void>.delayed(pollEvery);
    if (cancelled()) throw ConversionCancelled();
    try {
      job = await api.job(job.id);
      failures = 0;
    } on Unauthenticated {
      rethrow;
    } on ApiException catch (e) {
      if (e.status < 500) rethrow;
      if (++failures > 5) rethrow;
    } catch (_) {
      if (++failures > 5) rethrow;
    }
  }
}
