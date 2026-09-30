/// Modulação leve (LFO, seguidor de envelope, macro): o modelo que vai no documento, a conta do
/// intervalo em que o valor se move (o anel do knob) e os presets de fábrica.
///
/// Por faixa (e no master) há até [maxModSources] moduladores e, por modulador, até
/// [maxModDests] destinos. Um destino é um alvo no mesmo modelo da automação ([AutoTarget]) com
/// uma quantidade bipolar: −1..1 do curso do controle (−100%..+100%), na escala dele. O valor que
/// o motor toca é a base (o controle ou a automação) mais a modulação; a base nunca é gravada.
library;

import 'dart:math' as math;

import 'effects.dart';
import 'instruments.dart';
import 'model.dart';

/// Moduladores por faixa e destinos por modulador (os limites do motor).
const maxModSources = 4;
const maxModDests = 4;

/// Quantidade padrão de um destino novo (25% do curso).
const defaultModAmount = 0.25;

/// O tipo do modulador. O índice é o código do motor (`mod_source`).
enum ModKind {
  lfo('LFO'),
  follower('Seguidor de envelope'),
  macro('Macro');

  final String label;
  const ModKind(this.label);

  static ModKind parse(Object? s) {
    for (final k in values) {
      if (k.name == s) return k;
    }
    return lfo;
  }
}

/// A forma do LFO. O índice é o código do motor.
enum LfoShape {
  sine('Senoide'),
  triangle('Triângulo'),
  saw('Dente de serra'),
  square('Quadrada'),
  sampleHold('Sample & hold');

  final String label;
  const LfoShape(this.label);

  static LfoShape parse(Object? s) {
    for (final k in values) {
      if (k.name == s) return k;
    }
    return sine;
  }
}

/// Taxa livre do LFO, em Hz.
const modRateMin = 0.01, modRateMax = 50.0;

/// Divisões sincronizadas ao andamento: 8 bases vezes 3 variações (reta, pontilhada, tercina); o
/// índice é `base · 3 + variação`, o mesmo que o motor recebe.
const modDivisionCount = 24;

const _divisionBases = ['4 compassos', '2 compassos', '1 compasso', '1/2', '1/4', '1/8', '1/16', '1/32'];
const _divisionBeats = [16.0, 8.0, 4.0, 2.0, 1.0, 0.5, 0.25, 0.125];

/// O nome da divisão, para o seletor.
String modDivisionLabel(int index) {
  final i = index.clamp(0, modDivisionCount - 1);
  final suffix = switch (i % 3) {
    1 => ' pontilhada',
    2 => ' tercina',
    _ => '',
  };
  return '${_divisionBases[i ~/ 3]}$suffix';
}

/// Duração de um ciclo da divisão, em batidas (compasso de 4 tempos).
double modDivisionBeats(int index) {
  final i = index.clamp(0, modDivisionCount - 1);
  final base = _divisionBeats[i ~/ 3];
  return switch (i % 3) {
    1 => base * 1.5,
    2 => base * 2 / 3,
    _ => base,
  };
}

/// Um destino: o alvo e a quantidade (−1..1 do curso do controle).
class ModDest {
  AutoTarget target;
  double amount;
  ModDest(this.target, {this.amount = defaultModAmount});

  ModDest.fromJson(Map<String, dynamic> j)
    : target = AutoTarget.fromJson(j['target']),
      amount = ((j['amount'] as num?) ?? defaultModAmount).toDouble().clamp(-1.0, 1.0);

  Map<String, dynamic> toJson() => {'target': target.toJson(), 'amount': amount};

  ModDest copy() => ModDest(target, amount: amount);
}

/// Um modulador: o que ele gera e para onde vai.
class ModSource {
  String id;
  ModKind kind;
  LfoShape shape;

  /// Taxa livre, Hz (0,01–50).
  double rate;

  /// Sincronizado ao andamento: a taxa passa a ser a [division].
  bool sync;
  int division;

  /// LFO: amplitude 0..1. Seguidor: ganho 0..8.
  double depth;

  /// Fase inicial do LFO, 0..1 de ciclo.
  double phase;

  /// Saída de −1..1 (senão 0..1).
  bool bipolar;

  /// Seguidor: ataque e soltura, em milissegundos.
  double attack, release;

  /// Macro: o valor 0..1.
  double value;
  List<ModDest> dests;

  ModSource({
    required this.id,
    this.kind = ModKind.lfo,
    this.shape = LfoShape.sine,
    this.rate = 1,
    this.sync = false,
    this.division = 12,
    double? depth,
    this.phase = 0,
    bool? bipolar,
    this.attack = 10,
    this.release = 120,
    this.value = 0,
    List<ModDest>? dests,
  }) : depth = depth ?? (kind == ModKind.follower ? 2 : 1),
       // o LFO nasce bipolar (sobe e desce em volta do valor); o seguidor e a macro, unipolares
       bipolar = bipolar ?? (kind == ModKind.lfo),
       dests = dests ?? [];

  ModSource.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      kind = ModKind.parse(j['kind']),
      shape = LfoShape.parse(j['shape']),
      rate = ((j['rate'] as num?) ?? 1).toDouble().clamp(modRateMin, modRateMax),
      sync = j['sync'] as bool? ?? false,
      division = ((j['division'] as num?) ?? 12).toInt().clamp(0, modDivisionCount - 1),
      depth = ((j['depth'] as num?) ?? 1).toDouble().clamp(0.0, 8.0),
      phase = ((j['phase'] as num?) ?? 0).toDouble().clamp(0.0, 1.0),
      bipolar = j['bipolar'] as bool? ?? true,
      attack = ((j['attack'] as num?) ?? 10).toDouble().clamp(0.0, 5000.0),
      release = ((j['release'] as num?) ?? 120).toDouble().clamp(0.0, 5000.0),
      value = ((j['value'] as num?) ?? 0).toDouble().clamp(0.0, 1.0),
      dests = [for (final d in (j['dests'] as List?) ?? const []) ModDest.fromJson(d as Map<String, dynamic>)];

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    'shape': shape.name,
    'rate': rate,
    'sync': sync,
    'division': division,
    'depth': depth,
    'phase': phase,
    'bipolar': bipolar,
    'attack': attack,
    'release': release,
    'value': value,
    'dests': [for (final d in dests) d.toJson()],
  };

  ModSource copy({String? id}) => ModSource(
    id: id ?? this.id,
    kind: kind,
    shape: shape,
    rate: rate,
    sync: sync,
    division: division,
    depth: depth,
    phase: phase,
    bipolar: bipolar,
    attack: attack,
    release: release,
    value: value,
    dests: [for (final d in dests) d.copy()],
  );

  /// O texto curto do modulador, para listas e o seletor do "Modular…".
  String get summary {
    switch (kind) {
      case ModKind.lfo:
        final r = sync ? modDivisionLabel(division) : '${formatModRate(rate)} Hz';
        return 'LFO ${shape.label.toLowerCase()} · $r';
      case ModKind.follower:
        return 'Seguidor de envelope';
      case ModKind.macro:
        return 'Macro · ${(value * 100).round()}%';
    }
  }

  /// O intervalo (mínimo, máximo) que a saída do modulador percorre, na escala em que ela sai do
  /// motor: LFO ±profundidade (bipolar) ou 0..profundidade; seguidor 0..min(1, ganho) (o nível
  /// real depende do sinal); macro, o valor fixo.
  (double, double) get outputRange {
    switch (kind) {
      case ModKind.lfo:
        return bipolar ? (-depth.clamp(0.0, 1.0), depth.clamp(0.0, 1.0)) : (0.0, depth.clamp(0.0, 1.0));
      case ModKind.follower:
        final top = depth.clamp(0.0, 1.0);
        return bipolar ? (-1.0, 2 * top - 1) : (0.0, top);
      case ModKind.macro:
        final v = bipolar ? 2 * value - 1 : value;
        return (v, v);
    }
  }
}

/// A taxa livre para o texto ("0,25", "4,2", "12").
String formatModRate(double hz) {
  final s = hz < 1 ? hz.toStringAsFixed(2) : (hz < 10 ? hz.toStringAsFixed(1) : hz.toStringAsFixed(0));
  return s.replaceAll('.', ',');
}

/// A modulação de uma faixa (ou do master).
class TrackModulation {
  List<ModSource> sources;
  TrackModulation([List<ModSource>? sources]) : sources = sources ?? [];

  factory TrackModulation.fromJson(Object? j) {
    if (j is! Map) return TrackModulation();
    final list = j['sources'];
    if (list is! List) return TrackModulation();
    final out = <ModSource>[];
    for (final x in list) {
      if (out.length >= maxModSources) break;
      if (x is! Map) continue;
      try {
        final s = ModSource.fromJson(x.cast<String, dynamic>());
        if (s.dests.length > maxModDests) s.dests.length = maxModDests;
        out.add(s);
      } on Object {
        continue;
      }
    }
    return TrackModulation(out);
  }

  bool get isEmpty => sources.isEmpty;

  /// Só vai ao JSON quando há algo: um documento sem modulação sai igual ao de antes.
  Map<String, dynamic> toJson() => {
    'sources': [for (final s in sources) s.toJson()],
  };

  TrackModulation copy() => TrackModulation([for (final s in sources) s.copy()]);

  ModSource? byId(String id) {
    for (final s in sources) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// Todos os destinos em [target] (de qualquer modulador), com o modulador de cada um.
  Iterable<(ModSource, ModDest)> destsFor(AutoTarget target) sync* {
    for (final s in sources) {
      for (final d in s.dests) {
        if (d.target == target) yield (s, d);
      }
    }
  }

  /// O alvo tem modulação?
  bool modulates(AutoTarget target) => destsFor(target).isNotEmpty;

  /// Quanto o valor se afasta da base, em fração do curso do controle: (mínimo, máximo). Soma os
  /// destinos do alvo (os moduladores somam no curso). Null se nenhum modulador o alcança.
  (double, double)? deltaRange(AutoTarget target) {
    var lo = 0.0, hi = 0.0;
    var any = false;
    for (final (s, d) in destsFor(target)) {
      any = true;
      final (a, b) = s.outputRange;
      final x = a * d.amount, y = b * d.amount;
      lo += x < y ? x : y;
      hi += x < y ? y : x;
    }
    return any ? (lo, hi) : null;
  }

  /// Tira os destinos que [keep] rejeita (o efeito foi apagado, o envio saiu, o parâmetro não
  /// existe mais). O modulador que fica sem destino NÃO sai: continua no cartão, à espera de
  /// destinos (quem o apaga é o usuário). Devolve se mudou algo.
  bool prune(bool Function(AutoTarget target) keep) {
    var changed = false;
    for (final s in sources) {
      final before = s.dests.length;
      s.dests.removeWhere((d) => !keep(d.target));
      changed |= s.dests.length != before;
    }
    return changed;
  }

  /// Refaz os alvos dos destinos com [map] (ids novos numa faixa duplicada ou num projeto
  /// importado); o destino cujo alvo volta null sai.
  void remapTargets(AutoTarget? Function(AutoTarget target) map) {
    for (final s in sources) {
      s.dests = [
        for (final d in s.dests)
          if (map(d.target) case final t?) ModDest(t, amount: d.amount),
      ];
    }
  }
}

// ------------------------------------------------------------------------------ presets de fábrica

/// Um preset de modulação: um modulador pronto e o destino que ele procura na faixa.
class ModPreset {
  final String id, name, description;

  /// Cria o modulador (sem destino) com o [id] dado.
  final ModSource Function(String id) build;

  /// Como achar o alvo na faixa: [target] devolve o alvo (ou null se a faixa não tem) e a quantidade.
  final (AutoTarget, double)? Function(ModTrackView track) target;

  /// Esconde o preset do menu quando a faixa não tem o alvo (o vibrato só faz sentido onde há uma
  /// afinação geral da faixa).
  final bool hideWithoutTarget;

  const ModPreset(this.id, this.name, this.description, this.build, this.target, {this.hideWithoutTarget = false});

  /// O preset tem alvo nesta faixa?
  bool availableFor(ModTrackView v) => target(v) != null;
}

/// O que um preset precisa saber da faixa para achar o alvo.
class ModTrackView {
  final DawTrack? track;
  final List<EffectSlot> effects;
  const ModTrackView(this.track, this.effects);
}

/// O parâmetro do instrumento que os presets procuram pelo nome ("Corte") ou pela unidade ("ct").
AutoTarget? _instrumentParam(ModTrackView v, bool Function(ParamSpec p) test) {
  final t = v.track;
  if (t == null || !t.kind.isInstrument) return null;
  for (final p in t.kind.params) {
    if (test(p)) return AutoTarget(AutoKind.instrument, param: p.id);
  }
  return null;
}

/// A quantidade (−1..1 do curso) que move [oct] oitavas para cada lado num parâmetro logarítmico:
/// o curso do corte (20 Hz–20 kHz) tem cerca de 10 oitavas, então ±1 oitava é ±0,1 dele.
double _octaveAmount(ParamSpec p, double oct) => oct / (math.log(p.max / p.min) / math.ln2);

/// Os presets de fábrica.
final modPresets = <ModPreset>[
  ModPreset(
    'wobble',
    'Wobble no corte',
    'LFO sincronizado (1/8) movendo o corte do filtro em ±1 oitava',
    (id) => ModSource(id: id, shape: LfoShape.sine, sync: true, division: 15),
    (v) {
      // ±1 oitava na escala logarítmica do corte (em percentual do curso, 40% prendia a onda no
      // topo com o corte padrão de 2400 Hz)
      final inst = _instrumentParam(v, (p) => p.name == 'Corte');
      if (inst != null) return (inst, _octaveAmount(v.track!.kind.params.firstWhere((p) => p.id == inst.param), 1));
      // sem instrumento com corte: o primeiro filtro da cadeia
      for (final s in v.effects) {
        if (s.kind == EffectKind.filter) {
          return (AutoTarget(AutoKind.effect, ref: s.id, param: 1), _octaveAmount(filterParams.firstWhere((p) => p.id == 1), 1));
        }
      }
      return null;
    },
  ),
  ModPreset(
    'tremolo',
    'Tremolo no volume',
    'LFO de 6 Hz movendo o volume da faixa',
    (id) => ModSource(id: id, shape: LfoShape.sine, rate: 6),
    (v) => (const AutoTarget(AutoKind.volume), 0.15),
  ),
  ModPreset(
    'autopan',
    'Auto-pan',
    'LFO sincronizado (1/2) passeando o som entre os lados',
    (id) => ModSource(id: id, shape: LfoShape.sine, sync: true, division: 9),
    (v) => (const AutoTarget(AutoKind.pan), 0.5),
  ),
  ModPreset(
    'vibrato',
    'Vibrato de afinação',
    'LFO de 5,5 Hz movendo a afinação da faixa em ±12 centésimos (só no Sampler)',
    (id) => ModSource(id: id, shape: LfoShape.sine, rate: 5.5),
    (v) {
      // só o Sampler tem uma afinação da faixa toda; no sintetizador, no FM e no wavetable os
      // parâmetros em ct mexem em um oscilador ou operador só (dá batimento, não vibrato) e a
      // bateria afina por peça: nesses o preset fica escondido
      if (v.track?.kind != TrackKind.sampler) return null;
      final t = _instrumentParam(v, (p) => p.name == 'Afinação' && p.unit == 'ct');
      return t == null ? null : (t, 0.06);
    },
    hideWithoutTarget: true,
  ),
];
