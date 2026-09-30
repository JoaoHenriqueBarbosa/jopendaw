/// O documento do projeto no DAW: faixas, clipes, loop, metrônomo e master. Fica no aparelho
/// (IndexedDB na web) e vai inteiro para o motor a cada mudança.
///
/// Posições na linha do tempo são em batidas; trechos de áudio (offset, duração, fades) em
/// segundos do áudio de origem.
library;

import 'dart:math' as math;

import 'effects.dart';
import 'instruments.dart';
import 'sampler_zones.dart';

class AudioClip {
  String id;

  /// sha-256 do arquivo original: a chave do áudio no guardado local.
  String sample;
  double start, offset, length, gain, fadeIn, fadeOut;

  /// Tomadas de uma gravação em loop (sha-256 de cada passada, na ordem); a ativa é [sample].
  /// Vazia para clipe importado ou gravado sem loop.
  List<String> takes;

  /// Warp: com ele ligado o clipe é esticado para seguir o andamento do projeto (a razão de
  /// duração é [sourceBpm] / andamento; sem [sourceBpm] não há o que esticar). É só parâmetro: o
  /// som derivado nunca entra no documento nem no servidor (ver `warp.dart`).
  bool warp;

  /// O andamento original do áudio (batidas por minuto), o que o warp usa como base.
  double? sourceBpm;

  /// Transposição em semitons (−24..24), sem mudar a duração.
  double pitch;

  /// Toca o áudio de trás para a frente.
  bool reverse;

  AudioClip({
    required this.id,
    required this.sample,
    required this.start,
    this.offset = 0,
    required this.length,
    this.gain = 1,
    this.fadeIn = 0,
    this.fadeOut = 0,
    List<String>? takes,
    this.warp = false,
    this.sourceBpm,
    this.pitch = 0,
    this.reverse = false,
  }) : takes = takes ?? [];

  AudioClip.fromJson(Map<String, dynamic> j)
    : id = j['id'],
      sample = j['sample'],
      start = (j['start'] as num).toDouble(),
      offset = (j['offset'] as num).toDouble(),
      length = (j['length'] as num).toDouble(),
      gain = (j['gain'] as num? ?? 1).toDouble(),
      fadeIn = (j['fade_in'] as num? ?? 0).toDouble(),
      fadeOut = (j['fade_out'] as num? ?? 0).toDouble(),
      takes = [for (final t in (j['takes'] as List?) ?? const []) t as String],
      warp = j['warp'] as bool? ?? false,
      sourceBpm = (j['source_bpm'] as num?)?.toDouble(),
      pitch = (j['pitch'] as num? ?? 0).toDouble(),
      reverse = j['reverse'] as bool? ?? false;

  Map<String, dynamic> toJson() => {
    'id': id,
    'sample': sample,
    if (takes.isNotEmpty) 'takes': takes,
    'start': start,
    'offset': offset,
    'length': length,
    'gain': gain,
    'fade_in': fadeIn,
    'fade_out': fadeOut,
    // padrões omitidos: documento sem warp fica byte a byte como antes
    if (warp) 'warp': true,
    if (sourceBpm != null) 'source_bpm': sourceBpm,
    if (pitch != 0) 'pitch': pitch,
    if (reverse) 'reverse': true,
  };

  /// O warp está de fato esticando (ligado e com o andamento original conhecido).
  bool get stretches => warp && (sourceBpm ?? 0) > 0;

  /// Algum processamento (warp, transposição ou inversão) está ativo.
  bool get processed => stretches || pitch != 0 || reverse;

  /// Batidas por minuto que valem para converter entre batidas e os segundos do áudio de origem
  /// (`length`, `offset` e fades são sempre segundos da origem): com warp, o clipe segue o
  /// andamento do projeto, então um segundo da origem ocupa sempre a mesma fração de batida e o
  /// andamento que vale é o do próprio áudio; sem warp, o do projeto.
  double tempoFor(double projectBpm) => stretches ? sourceBpm! : projectBpm;

  /// Duração em batidas no andamento dado.
  double beats(double bpm) => length * tempoFor(bpm) / 60;
  double end(double bpm) => start + beats(bpm);
}

/// Uma nota num clipe MIDI. Início e duração em batidas, contados do início do clipe.
class MidiNote {
  int pitch;
  double start, length;

  /// 0..1.
  double velocity;

  MidiNote({required this.pitch, required this.start, required this.length, this.velocity = 0.8});

  MidiNote.fromJson(Map<String, dynamic> j)
    : pitch = j['pitch'],
      start = (j['start'] as num).toDouble(),
      length = (j['length'] as num).toDouble(),
      velocity = (j['velocity'] as num? ?? 0.8).toDouble();

  Map<String, dynamic> toJson() => {'pitch': pitch, 'start': start, 'length': length, 'velocity': velocity};

  double get end => start + length;
  MidiNote copy() => MidiNote(pitch: pitch, start: start, length: length, velocity: velocity);
}

/// Controles MIDI que o clipe de notas guarda além das notas (ids como no motor, `expression.rs`).
const ccMod = 1;
const ccSustain = 64;

/// O pitch bend não é um CC no MIDI; o motor usa o 128 para ele.
const ccBend = 128;

/// Os controles editáveis do piano roll, na ordem das faixas de controle.
const ccKinds = [ccBend, ccMod, ccSustain];

/// Um evento de controle num clipe: [cc] (1 modulação, 64 pedal, 128 pitch bend), a batida contada
/// do início do clipe e o valor (modulação 0..1, pedal 0 solto/1 embaixo, bend −1..1).
class MidiCc {
  int cc;
  double beat, value;

  MidiCc({required this.cc, required this.beat, required this.value});

  MidiCc.fromJson(Map<String, dynamic> j) : cc = j['cc'] as int, beat = (j['beat'] as num).toDouble(), value = (j['value'] as num).toDouble();

  Map<String, dynamic> toJson() => {'cc': cc, 'beat': beat, 'value': value};

  MidiCc copy() => MidiCc(cc: cc, beat: beat, value: value);

  /// Faixa de valores do controle: −1..1 no bend, 0..1 nos outros.
  static double clampValue(int cc, double v) => cc == ccBend ? v.clamp(-1.0, 1.0).toDouble() : v.clamp(0.0, 1.0).toDouble();

  /// O valor em repouso (bend no centro, roda e pedal em zero).
  static const neutral = 0.0;
}

/// Clipe de notas numa faixa de instrumento. Posição e duração em batidas; notas além da
/// duração (ou antes do 0, depois de aparar a esquerda) ficam guardadas mas não tocam.
class MidiClip {
  String id, name;
  double start, length;
  List<MidiNote> notes;

  /// Eventos de controle (pitch bend, modulação, pedal), com a batida contada do início do clipe.
  /// Ficam de fora do JSON quando vazia: documentos sem controles continuam idênticos.
  List<MidiCc> controls;

  /// Escala escolhida no editor ("tônica:id", ver `ClipScale` em `midi_tools.dart`); null = sem escala.
  String? scale;

  MidiClip({required this.id, this.name = '', required this.start, required this.length, List<MidiNote>? notes, List<MidiCc>? controls, this.scale})
    : notes = notes ?? [],
      controls = controls ?? [];

  MidiClip.fromJson(Map<String, dynamic> j)
    : id = j['id'],
      name = j['name'] ?? '',
      start = (j['start'] as num).toDouble(),
      length = (j['length'] as num).toDouble(),
      notes = [for (final n in j['notes'] as List) MidiNote.fromJson(n)],
      controls = [for (final e in (j['cc'] as List?) ?? const []) MidiCc.fromJson(e)],
      scale = j['scale'] as String?;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'start': start,
    'length': length,
    'notes': [for (final n in notes) n.toJson()],
    if (controls.isNotEmpty) 'cc': [for (final e in controls) e.toJson()],
    // só quando há escala: documentos sem escala continuam idênticos
    if (scale != null) 'scale': scale,
  };

  double get end => start + length;
}

/// Um efeito na cadeia de uma faixa (ou do master).
class EffectSlot {
  String id;
  EffectKind kind;

  /// Parâmetros (ids de `effects.dart`); faltando, vale o padrão.
  Map<int, double> params;
  bool bypass;

  EffectSlot({required this.id, required this.kind, Map<int, double>? params, this.bypass = false}) : params = params ?? defaultEffectParams(kind);

  /// Null quando o tipo salvo não existe mais nesta versão (o slot é descartado ao abrir).
  static EffectSlot? fromJson(Map<String, dynamic> j) {
    final kind = EffectKind.parse(j['kind']);
    if (kind == null) return null;
    return EffectSlot(
      id: j['id'],
      kind: kind,
      params: {for (final e in ((j['params'] as Map<String, dynamic>?) ?? {}).entries) int.parse(e.key): (e.value as num).toDouble()},
      bypass: j['bypass'] ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    'params': {for (final e in params.entries) '${e.key}': e.value},
    'bypass': bypass,
  };

  double param(int id) {
    final v = params[id];
    if (v != null) return v;
    for (final p in kind.params) {
      if (p.id == id) return p.def;
    }
    return 0;
  }
}

/// Envio de uma faixa para um barramento.
class Send {
  /// Id da faixa barramento.
  String target;

  /// Ganho linear (1 = 0 dB).
  double level;

  /// Antes do volume da faixa (pré-fader) ou depois (pós, o comum para reverb/delay).
  bool pre;

  Send({required this.target, this.level = 0.5, this.pre = false});

  Send.fromJson(Map<String, dynamic> j) : target = j['target'], level = (j['level'] as num).toDouble(), pre = j['pre'] ?? false;

  Map<String, dynamic> toJson() => {'target': target, 'level': level, 'pre': pre};
}

/// O que uma faixa de automação controla.
enum AutoKind { volume, pan, instrument, effect, send }

class AutoTarget {
  final AutoKind kind;

  /// Efeito: id do slot. Envio: id da faixa barramento.
  final String? ref;

  /// Parâmetro do instrumento ou do efeito.
  final int param;

  const AutoTarget(this.kind, {this.ref, this.param = 0});

  AutoTarget.fromJson(Map<String, dynamic> j) : kind = AutoKind.values.byName(j['kind']), ref = j['ref'], param = j['param'] ?? 0;

  Map<String, dynamic> toJson() => {'kind': kind.name, 'ref': ref, 'param': param};

  @override
  bool operator ==(Object other) => other is AutoTarget && other.kind == kind && other.ref == ref && other.param == param;

  @override
  int get hashCode => Object.hash(kind, ref, param);
}

/// Um ponto da automação: posição em batidas, valor na unidade do alvo (ganho linear no volume,
/// −1..1 no pan, a unidade da tabela nos parâmetros) e a curva até o próximo ponto (−1..1; 0 reta).
class AutoPoint {
  double beat, value, curve;
  AutoPoint({required this.beat, required this.value, this.curve = 0});

  AutoPoint.fromJson(Map<String, dynamic> j)
    : beat = (j['beat'] as num).toDouble(),
      value = (j['value'] as num).toDouble(),
      curve = (j['curve'] as num? ?? 0).toDouble();

  Map<String, dynamic> toJson() => {'beat': beat, 'value': value, 'curve': curve};
}

class AutoLane {
  String id;
  AutoTarget target;

  /// Ordenados por batida.
  List<AutoPoint> points;

  /// Aberta embaixo da faixa na linha do tempo.
  bool open;

  AutoLane({required this.id, required this.target, List<AutoPoint>? points, this.open = true}) : points = points ?? [];

  AutoLane.fromJson(Map<String, dynamic> j)
    : id = j['id'],
      target = AutoTarget.fromJson(j['target']),
      points = [for (final p in j['points'] as List) AutoPoint.fromJson(p)],
      open = j['open'] ?? true;

  Map<String, dynamic> toJson() => {
    'id': id,
    'target': target.toJson(),
    'points': [for (final p in points) p.toJson()],
    'open': open,
  };
}

List<EffectSlot> _effects(Object? j) => [for (final e in (j as List?) ?? const []) ?EffectSlot.fromJson(e)];

class DawTrack {
  String id, name;
  int color;
  double gain, pan;
  bool mute, solo;
  TrackKind kind;

  /// Parâmetros do instrumento (ids de `instruments.dart`); faltando, vale o padrão.
  Map<int, double> params;

  /// Áudio do sampler (sha-256), quando o tipo é sampler.
  String? sample;

  /// Zonas do sampler (multi-sample); vazia = o sampler de um áudio só (`sample`).
  List<SamplerZone> zones;

  /// Armada para gravar (áudio da entrada nas de áudio, notas nas de instrumento) e monitorando a
  /// entrada (o som do microfone passa pela cadeia da faixa ao vivo).
  bool armed, monitor;

  /// Clipes de áudio (faixas de áudio) e de notas (faixas de instrumento).
  List<AudioClip> clips;
  List<MidiClip> midi;

  /// Inserts, na ordem do sinal.
  List<EffectSlot> effects;
  List<Send> sends;

  /// Id do barramento para onde a faixa sai; null = master.
  String? output;
  List<AutoLane> lanes;

  DawTrack({
    required this.id,
    required this.name,
    required this.color,
    this.gain = 1,
    this.pan = 0,
    this.mute = false,
    this.solo = false,
    this.kind = TrackKind.audio,
    Map<int, double>? params,
    this.sample,
    List<SamplerZone>? zones,
    this.armed = false,
    this.monitor = false,
    List<AudioClip>? clips,
    List<MidiClip>? midi,
    List<EffectSlot>? effects,
    List<Send>? sends,
    this.output,
    List<AutoLane>? lanes,
  }) : params = params ?? defaultParams(kind),
       zones = zones ?? [],
       clips = clips ?? [],
       midi = midi ?? [],
       effects = effects ?? [],
       sends = sends ?? [],
       lanes = lanes ?? [];

  DawTrack.fromJson(Map<String, dynamic> j)
    : id = j['id'],
      name = j['name'],
      color = j['color'],
      gain = (j['gain'] as num).toDouble(),
      pan = (j['pan'] as num).toDouble(),
      mute = j['mute'],
      solo = j['solo'],
      kind = TrackKind.parse(j['kind']),
      params = {for (final e in ((j['params'] as Map<String, dynamic>?) ?? {}).entries) int.parse(e.key): (e.value as num).toDouble()},
      sample = j['sample'],
      zones = [for (final z in (j['zones'] as List?) ?? const []) SamplerZone.fromJson(z as Map<String, dynamic>)],
      armed = j['armed'] ?? false,
      monitor = j['monitor'] ?? false,
      clips = [for (final c in j['clips'] as List) AudioClip.fromJson(c)],
      midi = [for (final c in (j['midi'] as List?) ?? []) MidiClip.fromJson(c)],
      effects = _effects(j['effects']),
      sends = [for (final x in (j['sends'] as List?) ?? []) Send.fromJson(x)],
      output = j['output'],
      lanes = [for (final x in (j['lanes'] as List?) ?? []) AutoLane.fromJson(x)];

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'color': color,
    'gain': gain,
    'pan': pan,
    'mute': mute,
    'solo': solo,
    'kind': kind.name,
    'params': {for (final e in params.entries) '${e.key}': e.value},
    'sample': sample,
    // sem zonas o documento fica byte a byte como antes
    if (zones.isNotEmpty) 'zones': [for (final z in zones) z.toJson()],
    'armed': armed,
    'monitor': monitor,
    'clips': [for (final c in clips) c.toJson()],
    'midi': [for (final c in midi) c.toJson()],
    'effects': [for (final e in effects) e.toJson()],
    'sends': [for (final x in sends) x.toJson()],
    'output': output,
    'lanes': [for (final l in lanes) l.toJson()],
  };

  /// Valor de um parâmetro do instrumento (o padrão da tabela se não foi mexido).
  double param(int id) {
    final v = params[id];
    if (v != null) return v;
    for (final p in kind.params) {
      if (p.id == id) return p.def;
    }
    return 0;
  }
}

/// O que se sabe de um áudio importado sem abrir o arquivo.
class SampleInfo {
  final String name;
  final double duration;
  const SampleInfo(this.name, this.duration);

  SampleInfo.fromJson(Map<String, dynamic> j) : name = j['name'], duration = (j['duration'] as num).toDouble();
  Map<String, dynamic> toJson() => {'name': name, 'duration': duration};
}

/// Bandeirinha na régua: um ponto nomeado do arranjo (refrão, ponte...). Fica no documento, então
/// desfaz e sincroniza como o resto.
class Marker {
  String id, name;

  /// Posição em batidas.
  double beat;

  /// ARGB.
  int color;

  Marker({required this.id, required this.beat, this.name = '', this.color = 0xFFE3B341});

  Marker.fromJson(Map<String, dynamic> j)
    : id = j['id'] ?? newId(),
      beat = (j['beat'] as num).toDouble(),
      name = j['name'] ?? '',
      color = j['color'] ?? 0xFFE3B341;

  Map<String, dynamic> toJson() => {'id': id, 'beat': beat, 'name': name, 'color': color};
}

class DawDoc {
  static const version = 1;

  double bpm;
  int beatsPerBar;
  List<DawTrack> tracks;
  Map<String, SampleInfo> samples;
  bool loopOn, metronome;
  double loopStart, loopEnd, masterGain, masterPan;

  /// Contagem de um compasso de metrônomo antes de gravar.
  bool countIn;

  /// Compensação da latência de gravação em milissegundos (o que o áudio gravado chega atrasado
  /// em relação ao que tocava), somada à que o navegador informa. Ajustável nas configurações.
  double recLatencyMs;

  /// Cadeia do master (antes do volume e do limitador de segurança) e a automação dele (alvos
  /// volume, pan e parâmetros desses efeitos).
  List<EffectSlot> masterEffects;
  List<AutoLane> masterLanes;

  /// Marcadores, sempre ordenados por batida. Ausentes nos documentos antigos.
  List<Marker> markers;

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
    this.countIn = true,
    this.recLatencyMs = 0,
    List<EffectSlot>? masterEffects,
    List<AutoLane>? masterLanes,
    List<Marker>? markers,
  }) : tracks = tracks ?? [],
       markers = markers ?? [],
       samples = samples ?? {},
       masterEffects = masterEffects ?? [],
       masterLanes = masterLanes ?? [];

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
      masterPan = (j['master_pan'] as num).toDouble(),
      countIn = j['count_in'] ?? true,
      recLatencyMs = (j['rec_latency_ms'] as num? ?? 0).toDouble(),
      masterEffects = _effects(j['master_effects']),
      masterLanes = [for (final x in (j['master_lanes'] as List?) ?? []) AutoLane.fromJson(x)],
      markers = [for (final x in (j['markers'] as List?) ?? []) Marker.fromJson(x)]..sort((a, b) => a.beat.compareTo(b.beat));

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
    'count_in': countIn,
    'rec_latency_ms': recLatencyMs,
    'master_effects': [for (final e in masterEffects) e.toJson()],
    'master_lanes': [for (final l in masterLanes) l.toJson()],
    'markers': [for (final m in markers) m.toJson()],
  };

  /// Fim do último clipe, em batidas.
  double get contentEnd => math.max(
    tracks.expand((t) => t.clips).fold(0.0, (m, c) => math.max(m, c.end(bpm))),
    tracks.expand((t) => t.midi).fold(0.0, (m, c) => math.max(m, c.end)),
  );

  /// Duração do projeto em segundos: o fim do último clipe no andamento atual.
  double get durationSeconds => contentEnd * 60 / bpm;
}

/// Segundos → "m:ss" (ou "h:mm:ss"); com [tenths], "m:ss.d".
String formatClock(double seconds, {bool tenths = false}) {
  final s = seconds.isFinite ? math.max(0.0, seconds) : 0.0;
  final t = (s * 10).floor();
  final whole = t ~/ 10, d = t % 10;
  final h = whole ~/ 3600, m = (whole % 3600) ~/ 60, sec = whole % 60;
  final ss = sec.toString().padLeft(2, '0');
  final tail = tenths ? '.$d' : '';
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$ss$tail' : '$m:$ss$tail';
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
