/// O documento do projeto no DAW: faixas, clipes, loop, metrônomo e master. Fica no aparelho
/// (IndexedDB na web) e vai inteiro para o motor a cada mudança.
///
/// Posições na linha do tempo são em batidas; trechos de áudio (offset, duração, fades) em
/// segundos do áudio de origem.
library;

import 'dart:math' as math;

class AudioClip {
  String id;

  /// sha-256 do arquivo original: a chave do áudio no guardado local.
  String sample;
  double start, offset, length, gain, fadeIn, fadeOut;

  AudioClip({
    required this.id,
    required this.sample,
    required this.start,
    this.offset = 0,
    required this.length,
    this.gain = 1,
    this.fadeIn = 0,
    this.fadeOut = 0,
  });

  AudioClip.fromJson(Map<String, dynamic> j)
    : id = j['id'],
      sample = j['sample'],
      start = (j['start'] as num).toDouble(),
      offset = (j['offset'] as num).toDouble(),
      length = (j['length'] as num).toDouble(),
      gain = (j['gain'] as num? ?? 1).toDouble(),
      fadeIn = (j['fade_in'] as num? ?? 0).toDouble(),
      fadeOut = (j['fade_out'] as num? ?? 0).toDouble();

  Map<String, dynamic> toJson() => {
    'id': id,
    'sample': sample,
    'start': start,
    'offset': offset,
    'length': length,
    'gain': gain,
    'fade_in': fadeIn,
    'fade_out': fadeOut,
  };

  /// Duração em batidas no andamento dado.
  double beats(double bpm) => length * bpm / 60;
  double end(double bpm) => start + beats(bpm);
}

class DawTrack {
  String id, name;
  int color;
  double gain, pan;
  bool mute, solo;
  List<AudioClip> clips;

  DawTrack({
    required this.id,
    required this.name,
    required this.color,
    this.gain = 1,
    this.pan = 0,
    this.mute = false,
    this.solo = false,
    List<AudioClip>? clips,
  }) : clips = clips ?? [];

  DawTrack.fromJson(Map<String, dynamic> j)
    : id = j['id'],
      name = j['name'],
      color = j['color'],
      gain = (j['gain'] as num).toDouble(),
      pan = (j['pan'] as num).toDouble(),
      mute = j['mute'],
      solo = j['solo'],
      clips = [for (final c in j['clips'] as List) AudioClip.fromJson(c)];

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'color': color,
    'gain': gain,
    'pan': pan,
    'mute': mute,
    'solo': solo,
    'clips': [for (final c in clips) c.toJson()],
  };
}

/// O que se sabe de um áudio importado sem abrir o arquivo.
class SampleInfo {
  final String name;
  final double duration;
  const SampleInfo(this.name, this.duration);

  SampleInfo.fromJson(Map<String, dynamic> j) : name = j['name'], duration = (j['duration'] as num).toDouble();
  Map<String, dynamic> toJson() => {'name': name, 'duration': duration};
}

class DawDoc {
  static const version = 1;

  double bpm;
  int beatsPerBar;
  List<DawTrack> tracks;
  Map<String, SampleInfo> samples;
  bool loopOn, metronome;
  double loopStart, loopEnd, masterGain, masterPan;

  DawDoc({
    required this.bpm,
    required this.beatsPerBar,
    List<DawTrack>? tracks,
    Map<String, SampleInfo>? samples,
    this.loopOn = false,
    this.loopStart = 0,
    this.loopEnd = 16,
    this.metronome = false,
    this.masterGain = 1,
    this.masterPan = 0,
  }) : tracks = tracks ?? [],
       samples = samples ?? {};

  DawDoc.fromJson(Map<String, dynamic> j)
    : bpm = (j['bpm'] as num).toDouble(),
      beatsPerBar = j['beats_per_bar'],
      tracks = [for (final t in j['tracks'] as List) DawTrack.fromJson(t)],
      samples = {for (final e in (j['samples'] as Map<String, dynamic>).entries) e.key: SampleInfo.fromJson(e.value)},
      loopOn = j['loop_on'],
      loopStart = (j['loop_start'] as num).toDouble(),
      loopEnd = (j['loop_end'] as num).toDouble(),
      metronome = j['metronome'],
      masterGain = (j['master_gain'] as num).toDouble(),
      masterPan = (j['master_pan'] as num).toDouble();

  Map<String, dynamic> toJson() => {
    'version': version,
    'bpm': bpm,
    'beats_per_bar': beatsPerBar,
    'tracks': [for (final t in tracks) t.toJson()],
    'samples': {for (final e in samples.entries) e.key: e.value.toJson()},
    'loop_on': loopOn,
    'loop_start': loopStart,
    'loop_end': loopEnd,
    'metronome': metronome,
    'master_gain': masterGain,
    'master_pan': masterPan,
  };

  /// Fim do último clipe, em batidas.
  double get contentEnd => tracks.expand((t) => t.clips).fold(0.0, (m, c) => math.max(m, c.end(bpm)));
}

// ------------------------------------------------------------------ utilidades

final _rand = math.Random();

/// Id curto e aleatório para faixas e clipes.
String newId() => List.generate(12, (_) => 'abcdefghijklmnopqrstuvwxyz0123456789'[_rand.nextInt(36)]).join();

/// Ganho linear em dB (−∞ vira −inf).
double gainToDb(double g) => g <= 0.00001 ? double.negativeInfinity : 20 * math.log(g) / math.ln10;

double dbToGain(double db) => math.pow(10, db / 20).toDouble();

/// Posição do fader (0..1) ↔ ganho: curva cúbica, 0 dB em ~0,79 e +6 dB no topo.
double faderToGain(double v) => math.pow(v, 3) * 2;
double gainToFader(double g) => math.pow(g / 2, 1 / 3).toDouble();

String formatDb(double g) {
  final db = gainToDb(g);
  if (db.isInfinite) return '−∞';
  return '${db >= 0 ? '+' : '−'}${db.abs().toStringAsFixed(1)}';
}

/// Batida → "compasso.tempo.dezesseis avos", contando do 1 como os DAWs.
String formatPosition(double beat, int beatsPerBar) {
  final b = beat.clamp(0, double.infinity);
  final bar = b ~/ beatsPerBar + 1;
  final inBar = b - (bar - 1) * beatsPerBar;
  final beatN = inBar.floor() + 1;
  final sixteenth = ((inBar - inBar.floor()) * 4).floor() + 1;
  return '$bar.$beatN.$sixteenth';
}
