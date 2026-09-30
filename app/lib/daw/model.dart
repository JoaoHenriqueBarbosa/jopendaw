/// O documento do projeto no DAW: faixas, clipes, loop, metrônomo e master. Fica no aparelho
/// (IndexedDB na web) e vai inteiro para o motor a cada mudança.
///
/// Posições na linha do tempo são em batidas; trechos de áudio (offset, duração, fades) em
/// segundos do áudio de origem.
library;

import 'dart:math' as math;

import 'effects.dart';
import 'instruments.dart';
import 'midi_map.dart';
import 'modulation.dart';
import 'sampler_zones.dart';
import 'tempo_map.dart';

/// Curvas de fade de um clipe de áudio (o código vai ao motor por `clip_fade_shape`). A ordem é a
/// do motor (`FADE_*` em `engine/src/lib.rs`): tipo novo só entra no fim.
enum FadeShape {
  /// O envelope histórico (`x²`): o de todo projeto que nunca escolheu curva. O código (0) e a
  /// curva ficam como sempre foram (senão os projetos antigos mudariam de som); só o rótulo é novo,
  /// porque "Linear" enganava: é suave (x²) e, num crossfade, afunda uns 6 dB no meio.
  linear('Suave (padrão)'),

  /// Potência constante (`sin`): a do crossfade, dois clipes sem correlação somam potência 1.
  equalPower('Potência constante'),

  /// Exponencial: na saída cai depressa e some suave; na entrada sobe devagar e acelera.
  exponential('Exponencial'),

  /// S (seno cosseno): suave nas duas pontas.
  sCurve('S (seno cosseno)');

  final String label;
  const FadeShape(this.label);

  static FadeShape fromCode(Object? code) => code is int && code >= 0 && code < values.length ? values[code] : linear;

  /// Ganho de amplitude no progresso [x] (0 a 1) do fade de entrada; a saída usa o espelho. Espelho
  /// exato de `fade_curve` do motor (0 em 0, 1 em 1, sem decrescer).
  double gain(double x) {
    x = x.clamp(0.0, 1.0);
    return switch (this) {
      FadeShape.linear => x * x,
      FadeShape.equalPower => math.sin(x * math.pi / 2),
      FadeShape.exponential => (math.exp(4 * x) - 1) / (math.exp(4) - 1),
      FadeShape.sCurve => (1 - math.cos(x * math.pi)) / 2,
    };
  }
}

/// Fade que o crossfade automático gerou, com o que havia antes: desfeita a sobreposição, só o que
/// é automático volta ao valor anterior (um fade que o usuário mexeu perde a marca).
class AutoFade {
  final double prevLength;
  final FadeShape prevShape;
  const AutoFade(this.prevLength, this.prevShape);

  AutoFade.fromJson(Map<String, dynamic> j) : prevLength = (j['len'] as num? ?? 0).toDouble(), prevShape = FadeShape.fromCode(j['shape']);

  Map<String, dynamic> toJson() => {'len': prevLength, 'shape': prevShape.index};
}

class AudioClip {
  String id;

  /// sha-256 do arquivo original: a chave do áudio no guardado local.
  String sample;
  double start, offset, length, gain, fadeIn, fadeOut;

  /// Curvas dos fades de entrada e de saída.
  FadeShape fadeInShape, fadeOutShape;

  /// Marca dos fades gerados pelo crossfade automático (nulo = fade do usuário).
  AutoFade? autoFadeIn, autoFadeOut;

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
    this.fadeInShape = FadeShape.linear,
    this.fadeOutShape = FadeShape.linear,
    this.autoFadeIn,
    this.autoFadeOut,
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
      fadeInShape = FadeShape.fromCode(j['fade_in_shape']),
      fadeOutShape = FadeShape.fromCode(j['fade_out_shape']),
      autoFadeIn = j['auto_fade_in'] is Map ? AutoFade.fromJson((j['auto_fade_in'] as Map).cast<String, dynamic>()) : null,
      autoFadeOut = j['auto_fade_out'] is Map ? AutoFade.fromJson((j['auto_fade_out'] as Map).cast<String, dynamic>()) : null,
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
    // curvas e marcas do crossfade só quando fogem do padrão (documento antigo fica como estava)
    if (fadeInShape != FadeShape.linear) 'fade_in_shape': fadeInShape.index,
    if (fadeOutShape != FadeShape.linear) 'fade_out_shape': fadeOutShape.index,
    if (autoFadeIn != null) 'auto_fade_in': autoFadeIn!.toJson(),
    if (autoFadeOut != null) 'auto_fade_out': autoFadeOut!.toJson(),
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

  /// Segundos reais que o clipe ocupa. Sem warp, a duração do próprio áudio; com warp, esticada
  /// para o andamento inicial do projeto [bpm0] (com mapa de andamento o warp usa o inicial: um
  /// clipe esticado não muda de velocidade no meio do caminho, ver `DawDoc.tempo`).
  double seconds(double bpm0) => stretches ? length * sourceBpm! / bpm0 : length;
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

  /// Moduladores (LFO, seguidor, macro) e os destinos deles nesta faixa.
  TrackModulation modulation;

  /// Pasta de faixas (ver `track_groups.dart`): um barramento com esta marca é a linha da pasta e
  /// as faixas dela vêm logo abaixo, com [groupId] igual ao id dele e a saída apontando para ele.
  /// Só faz sentido em [TrackKind.bus]; o motor vê um barramento comum.
  bool isGroup;

  /// Id da pasta a que a faixa pertence (null = fora de pasta).
  String? groupId;

  /// Pasta recolhida (estado de arranjo guardado no documento): as filhas somem da linha do tempo.
  bool collapsed;

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
    TrackModulation? modulation,
    this.isGroup = false,
    this.groupId,
    this.collapsed = false,
  }) : params = params ?? defaultParams(kind),
       zones = zones ?? [],
       clips = clips ?? [],
       midi = midi ?? [],
       effects = effects ?? [],
       sends = sends ?? [],
       lanes = lanes ?? [],
       modulation = modulation ?? TrackModulation();

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
      lanes = [for (final x in (j['lanes'] as List?) ?? []) AutoLane.fromJson(x)],
      modulation = TrackModulation.fromJson(j['modulation']),
      // documento sem pastas (versão anterior): nenhuma faixa é pasta nem filha
      isGroup = (j['group'] as bool? ?? false) && TrackKind.parse(j['kind']) == TrackKind.bus,
      groupId = j['group_id'] as String?,
      collapsed = j['collapsed'] as bool? ?? false;

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
    // sem modulação o documento fica byte a byte como antes
    if (!modulation.isEmpty) 'modulation': modulation.toJson(),
    // só com pastas: um documento sem elas sai igual ao de antes
    if (isGroup) 'group': true,
    if (groupId != null) 'group_id': groupId,
    if (isGroup && collapsed) 'collapsed': true,
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

/// Timbres do clique do metrônomo; o índice é o código do motor.
enum MetronomeTimbre {
  click('Clique'),
  wood('Madeira'),
  beep('Bipe agudo'),
  cowbell('Cowbell'),
  hihat('Hi-hat');

  final String label;
  const MetronomeTimbre(this.label);
}

/// Subdivisões do metrônomo; o índice é o código do motor. Dividem o tempo do compasso (a semínima
/// em x/4, a colcheia em 6/8 e 7/8).
enum MetronomeSubdivision {
  beat('Um clique por tempo'),
  eighth('Colcheias'),
  triplet('Tercinas'),
  sixteenth('Semicolcheias'),
  accentOnly('Só o acento do compasso');

  final String label;
  const MetronomeSubdivision(this.label);
}

/// Quando o metrônomo soa: sempre que estiver ligado, ou só na gravação (contagem e pré-roll inclusos).
enum MetronomeMode {
  always('Sempre que ligado'),
  recording('Só ao gravar');

  final String label;
  const MetronomeMode(this.label);
}

/// Como o metrônomo soa (preferência do projeto). Os padrões são o clique de sempre: o documento só
/// leva o campo quando alguma coisa foge deles.
class MetronomeOptions {
  MetronomeTimbre timbre;
  MetronomeSubdivision subdivision;
  MetronomeMode mode;

  /// Volume do clique comum (0 a 1), o `ganho` da chamada `metronome`.
  double volume;

  /// Nível do acento do primeiro tempo em relação ao volume (0 a 2) e quanto ele é mais agudo que o
  /// clique comum (razão de frequência, 0,5 a 4).
  double accentLevel, accentPitch;

  /// Nível das subdivisões em relação ao volume (0 a 2).
  double subLevel;

  static const defaultVolume = 0.5, defaultAccentLevel = 1.0, defaultAccentPitch = 1.6, defaultSubLevel = 0.5;

  MetronomeOptions({
    this.timbre = MetronomeTimbre.click,
    this.subdivision = MetronomeSubdivision.beat,
    this.mode = MetronomeMode.always,
    this.volume = defaultVolume,
    this.accentLevel = defaultAccentLevel,
    this.accentPitch = defaultAccentPitch,
    this.subLevel = defaultSubLevel,
  });

  /// Lê o JSON; ausente, ruim ou fora da faixa vale o padrão (um documento de versão anterior não tem o campo).
  factory MetronomeOptions.fromJson(Object? j) {
    if (j is! Map) return MetronomeOptions();
    T byName<T extends Enum>(List<T> values, Object? v, T fallback) {
      for (final e in values) {
        if (e.name == v) return e;
      }
      return fallback;
    }

    double number(Object? v, double lo, double hi, double fallback) => v is num && v.isFinite ? v.toDouble().clamp(lo, hi).toDouble() : fallback;
    return MetronomeOptions(
      timbre: byName(MetronomeTimbre.values, j['timbre'], MetronomeTimbre.click),
      subdivision: byName(MetronomeSubdivision.values, j['subdivision'], MetronomeSubdivision.beat),
      mode: byName(MetronomeMode.values, j['mode'], MetronomeMode.always),
      volume: number(j['volume'], 0, 1, defaultVolume),
      accentLevel: number(j['accent_level'], 0, 2, defaultAccentLevel),
      accentPitch: number(j['accent_pitch'], 0.5, 4, defaultAccentPitch),
      subLevel: number(j['sub_level'], 0, 2, defaultSubLevel),
    );
  }

  bool get isDefault => toJson().isEmpty;

  /// Só o que foge do padrão.
  Map<String, dynamic> toJson() => {
    if (timbre != MetronomeTimbre.click) 'timbre': timbre.name,
    if (subdivision != MetronomeSubdivision.beat) 'subdivision': subdivision.name,
    if (mode != MetronomeMode.always) 'mode': mode.name,
    if (volume != defaultVolume) 'volume': volume,
    if (accentLevel != defaultAccentLevel) 'accent_level': accentLevel,
    if (accentPitch != defaultAccentPitch) 'accent_pitch': accentPitch,
    if (subLevel != defaultSubLevel) 'sub_level': subLevel,
  };

  MetronomeOptions copy() => MetronomeOptions.fromJson(toJson());

  /// A chamada do estilo ao motor (`metronome_style`): o que ele precisa para soar assim.
  List<Object> get styleCall => ['metronome_style', timbre.index, subdivision.index, accentLevel, accentPitch, subLevel];
}

class DawDoc {
  static const version = 1;

  /// Teto do pré-roll em compassos.
  static const maxPreRollBars = 4;

  /// O andamento inicial (o do ponto da batida 0 do mapa de andamento) e o compasso inicial
  /// (`beatsPerBar`/4, a menos que o mapa de compassos diga outro).
  double bpm;
  int beatsPerBar;

  /// Mapa de andamento: `[]` sem mudanças (só [bpm]); senão os pontos ordenados, o primeiro na
  /// batida 0 (o andamento inicial, que espelha [bpm]). Troque a lista inteira ao mudar (o cache de
  /// [tempo] repara na troca), preferindo [DawController.setTempoMap].
  List<TempoPoint> tempoMap;

  /// Mapa de compassos: `[]` sem mudanças (só [beatsPerBar]/4); senão as mudanças ordenadas, a
  /// primeira no compasso 1. Mesma regra de troca da lista.
  List<MeterChange> meterMap;
  List<DawTrack> tracks;
  Map<String, SampleInfo> samples;
  bool loopOn, metronome;
  double loopStart, loopEnd, masterGain, masterPan;

  /// Contagem de um compasso de metrônomo antes de gravar.
  bool countIn;

  /// Como o metrônomo soa (timbre, subdivisão, acento, volume, quando). Só vai ao JSON o que foge do padrão.
  MetronomeOptions metronomeOptions;

  /// Compassos que a gravação começa antes do ponto de gravar, tocando sem gravar (0 a 4).
  int preRollBars;

  /// Região de punch (batidas): com [punchOn], a gravação só vale entre [punchIn] e [punchOut]. A região
  /// existe mesmo desligada (null sem região). Ausentes nos documentos antigos.
  double? punchIn, punchOut;
  bool punchOn;

  /// A região de punch válida (início < fim), ou null.
  (double, double)? get punchRegion => punchIn != null && punchOut != null && punchOut! > punchIn! + 1e-9 ? (punchIn!, punchOut!) : null;

  /// O punch está valendo: ligado e com região.
  bool get punchActive => punchOn && punchRegion != null;

  /// Compensação da latência de gravação em milissegundos (o que o áudio gravado chega atrasado
  /// em relação ao que tocava), somada à que o navegador informa. Ajustável nas configurações.
  double recLatencyMs;

  /// Cadeia do master (antes do volume e do limitador de segurança) e a automação dele (alvos
  /// volume, pan e parâmetros desses efeitos).
  List<EffectSlot> masterEffects;
  List<AutoLane> masterLanes;

  /// A modulação do master (volume, pan e parâmetros dos efeitos dele).
  TrackModulation masterModulation;

  /// Marcadores, sempre ordenados por batida. Ausentes nos documentos antigos.
  List<Marker> markers;

  /// Mapeamentos de MIDI learn (controles do teclado → parâmetros). Vazio nos documentos antigos e
  /// só vai ao JSON (`midi_map`) quando há algo: um documento sem mapa sai igual ao de antes.
  MidiMap midiMap;

  DawDoc({
    required this.bpm,
    required this.beatsPerBar,
    List<TempoPoint>? tempoMap,
    List<MeterChange>? meterMap,
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
    MetronomeOptions? metronomeOptions,
    this.preRollBars = 0,
    this.punchIn,
    this.punchOut,
    this.punchOn = false,
    List<EffectSlot>? masterEffects,
    List<AutoLane>? masterLanes,
    TrackModulation? masterModulation,
    List<Marker>? markers,
    MidiMap? midiMap,
  }) : tempoMap = normalizeTempoPoints(tempoMap ?? const [], bpm),
       meterMap = normalizeMeterChanges(meterMap ?? const [], beatsPerBar),
       tracks = tracks ?? [],
       markers = markers ?? [],
       midiMap = midiMap ?? MidiMap(),
       metronomeOptions = metronomeOptions ?? MetronomeOptions(),
       samples = samples ?? {},
       masterEffects = masterEffects ?? [],
       masterLanes = masterLanes ?? [],
       masterModulation = masterModulation ?? TrackModulation();

  DawDoc.fromJson(Map<String, dynamic> j)
    : bpm = (j['bpm'] as num).toDouble(),
      beatsPerBar = j['beats_per_bar'],
      // documento sem os campos (versão anterior): sem mapa, um andamento e um compasso só
      tempoMap = normalizeTempoPoints([for (final x in (j['tempo_map'] as List?) ?? const []) TempoPoint.fromJson(x)], (j['bpm'] as num).toDouble()),
      meterMap = normalizeMeterChanges([for (final x in (j['meter_map'] as List?) ?? const []) MeterChange.fromJson(x)], j['beats_per_bar'] as int),
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
      metronomeOptions = MetronomeOptions.fromJson(j['metronome_options']),
      preRollBars = ((j['pre_roll'] as num?)?.toInt() ?? 0).clamp(0, maxPreRollBars),
      punchIn = _punchOf(j)?.$1,
      punchOut = _punchOf(j)?.$2,
      punchOn = j['punch_on'] == true && _punchOf(j) != null,
      masterEffects = _effects(j['master_effects']),
      masterLanes = [for (final x in (j['master_lanes'] as List?) ?? []) AutoLane.fromJson(x)],
      masterModulation = TrackModulation.fromJson(j['master_modulation']),
      markers = [for (final x in (j['markers'] as List?) ?? []) Marker.fromJson(x)]..sort((a, b) => a.beat.compareTo(b.beat)),
      midiMap = MidiMap.fromJson(j['midi_map']) {
    _repairGroups();
  }

  /// A região de punch do JSON; null se faltar um lado, não for número ou não valer (início ≥ 0 antes do fim).
  static (double, double)? _punchOf(Map<String, dynamic> j) {
    final a = j['punch_in'], b = j['punch_out'];
    if (a is! num || b is! num || !a.isFinite || !b.isFinite || a < 0 || b <= a) return null;
    return (a.toDouble(), b.toDouble());
  }

  /// Solta as filhas cuja pasta não existe (documento editado à mão ou de uma versão que perdeu a
  /// pasta): elas seguem como faixas comuns. Pasta é sempre barramento; barramento nunca é filho.
  void _repairGroups() {
    final folders = {
      for (final t in tracks)
        if (t.isGroup && t.kind == TrackKind.bus) t.id,
    };
    for (final t in tracks) {
      if (t.groupId != null && (!folders.contains(t.groupId) || t.kind == TrackKind.bus)) t.groupId = null;
    }
  }

  Map<String, dynamic> toJson() => {
    'version': version,
    'bpm': bpm,
    'beats_per_bar': beatsPerBar,
    // só com mudanças: um documento sem mapa sai igual ao de antes
    if (!tempo.isSingle) 'tempo_map': [for (final p in tempo.points) p.toJson()],
    if (!meter.isSingle) 'meter_map': [for (final m in meter.changes) m.toJson()],
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
    // só o que foge do padrão: um documento sem essas opções sai igual ao de antes
    if (!metronomeOptions.isDefault) 'metronome_options': metronomeOptions.toJson(),
    if (preRollBars > 0) 'pre_roll': preRollBars,
    if (punchRegion case (final a, final b)) ...{'punch_in': a, 'punch_out': b, if (punchOn) 'punch_on': true},
    'master_effects': [for (final e in masterEffects) e.toJson()],
    'master_lanes': [for (final l in masterLanes) l.toJson()],
    if (!masterModulation.isEmpty) 'master_modulation': masterModulation.toJson(),
    'markers': [for (final m in markers) m.toJson()],
    // só com mapeamentos: um documento sem MIDI learn sai igual ao de antes
    if (!midiMap.isDefault) 'midi_map': midiMap.toJson(),
  };

  // Os mapas viram objetos de conta sob demanda e ficam guardados enquanto a lista, o tamanho e o
  // andamento/compasso inicial não mudam.
  TempoMap? _tempo;
  List<TempoPoint>? _tempoSrc;
  int _tempoLen = -1;
  double _tempoBpm = double.nan;
  MeterMap? _meter;
  List<MeterChange>? _meterSrc;
  int _meterLen = -1;
  int _meterBpb = -1;

  /// A conversão batida ↔ segundos pelo mapa de andamento ([bpm] manda no ponto da batida 0).
  ///
  /// Decisão do warp com mapa de andamento: um clipe com warp é esticado para o andamento INICIAL
  /// do projeto e toca em tempo real constante, como qualquer áudio; se atravessar mudanças de
  /// andamento, deixa de acompanhar a grade nelas (a interface avisa no diálogo de warp).
  TempoMap get tempo {
    var t = _tempo;
    if (t == null || !identical(_tempoSrc, tempoMap) || _tempoLen != tempoMap.length || _tempoBpm != bpm) {
      t = tempoMap.isEmpty ? TempoMap.constant(bpm) : TempoMap(bpm, tempoMap);
      _tempo = t;
      _tempoSrc = tempoMap;
      _tempoLen = tempoMap.length;
      _tempoBpm = bpm;
    }
    return t;
  }

  /// O mapa de compassos ([beatsPerBar] manda no compasso 1 quando ele é `n/4`).
  MeterMap get meter {
    var m = _meter;
    if (m == null || !identical(_meterSrc, meterMap) || _meterLen != meterMap.length || _meterBpb != beatsPerBar) {
      final ch = meterMap;
      // o compasso inicial n/4 é o `beatsPerBar` (o campo que a barra e o servidor conhecem)
      final fixed = ch.isNotEmpty && ch.first.denominator == 4 && ch.first.numerator != beatsPerBar ? [MeterChange(1, beatsPerBar, 4), ...ch.skip(1)] : ch;
      m = fixed.isEmpty ? MeterMap.constant(beatsPerBar) : MeterMap(beatsPerBar, fixed);
      _meter = m;
      _meterSrc = meterMap;
      _meterLen = meterMap.length;
      _meterBpb = beatsPerBar;
    }
    return m;
  }

  /// Segundos da batida 0 até [beat], pelo mapa.
  double secondsAt(double beat) => tempo.secondsAt(beat);

  /// A batida em que caem os segundos.
  double beatAtSeconds(double seconds) => tempo.beatAt(seconds);

  /// O andamento (bpm) na batida.
  double bpmAt(double beat) => tempo.bpmAt(beat);

  /// Duração do clipe de áudio em batidas, no mapa (com um andamento só, a conta de sempre).
  double clipBeats(AudioClip c) => clipEnd(c) - c.start;

  /// Onde o clipe de áudio termina, em batidas: começa na batida dele e ocupa segundos reais
  /// constantes ([AudioClip.seconds]).
  double clipEnd(AudioClip c) {
    final t = tempo;
    return t.isSingle ? c.end(bpm) : t.beatAt(t.secondsAt(c.start) + c.seconds(bpm));
  }

  /// Batidas por minuto que valem para converter entre batidas e os segundos do áudio de origem do
  /// clipe, na [beat] dele (aproximação local, para arrastes e desenho): sem mapa é o
  /// [AudioClip.tempoFor] de sempre; com mapa, o andamento vigente ali (com warp, o do áudio
  /// proporcional ao vigente sobre o inicial).
  double sourceTempoAt(AudioClip c, double beat) {
    final t = tempo;
    if (t.isSingle) return c.tempoFor(bpm);
    final local = t.bpmAt(beat);
    return c.stretches ? c.sourceBpm! * local / bpm : local;
  }

  /// Segundos do áudio de origem (a unidade de `AudioClip.length` e `offset`) que cabem entre duas
  /// batidas da linha do tempo, para um clipe de áudio: cortes e aparas convertem por aqui. Com um
  /// andamento só é a conta de sempre; com mapa, o tempo real entre as batidas (com warp, esticado
  /// para o andamento inicial).
  double sourceSeconds(AudioClip c, double from, double to) {
    final t = tempo;
    if (t.isSingle) return (to - from) * 60 / c.tempoFor(bpm);
    final real = t.secondsAt(to) - t.secondsAt(from);
    return c.stretches ? real * bpm / c.sourceBpm! : real;
  }

  /// Fim do último clipe, em batidas.
  double get contentEnd => math.max(
    tracks.expand((t) => t.clips).fold(0.0, (m, c) => math.max(m, clipEnd(c))),
    tracks.expand((t) => t.midi).fold(0.0, (m, c) => math.max(m, c.end)),
  );

  /// Duração do projeto em segundos: o fim do último clipe pelo mapa de andamento.
  double get durationSeconds => secondsAt(contentEnd);
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
///
/// Com [meter] (o mapa de compassos do documento) o compasso é contado por ele; sem, por
/// [beatsPerBar] fixo.
String formatPosition(double beat, int beatsPerBar, {MeterMap? meter}) {
  final b = beat.clamp(0, double.infinity);
  if (meter != null && !meter.isSingle) {
    final (bar, inBar) = meter.barOf(b.toDouble());
    final unit = meter.changeAt(bar).unit;
    final tick = (inBar / unit + 1e-9).floor();
    final into = inBar - tick * unit;
    return '$bar.${tick + 1}.${(into / unit * 4 + 1e-9).floor() + 1}';
  }
  final bar = b ~/ beatsPerBar + 1;
  final inBar = b - (bar - 1) * beatsPerBar;
  final beatN = inBar.floor() + 1;
  final sixteenth = ((inBar - inBar.floor()) * 4).floor() + 1;
  return '$bar.$beatN.$sixteenth';
}
