/// Modelo e conta do MIDI learn, sem Flutter: origem (canal + CC, pitch bend ou pressão), alvo
/// (faixa + controle), faixa, curva e inversão de cada mapeamento, o JSON que vai no documento
/// (`midi_map`, compatível para trás) e o modo pegar/pular (takeover). A parte que mexe no app
/// está em `midi_learn.dart`.
library;

import 'dart:math' as math;

import 'model.dart';

// ------------------------------------------------------------------------- modelo

/// De onde vem o valor: um CC (0..119), o pitch bend (14 bits) ou a pressão do canal.
enum MidiSourceKind {
  cc,
  bend,
  pressure;

  static MidiSourceKind? parse(Object? s) {
    for (final k in values) {
      if (k.name == s) return k;
    }
    return null;
  }
}

/// A origem de um mapeamento: tipo, canal MIDI (0..15) e, no CC, o número do controle. O Web MIDI
/// e o Android entregam só (status, dado1, dado2), sem o aparelho: a origem é canal + controle.
class MidiSource {
  final MidiSourceKind kind;
  final int channel;
  final int cc;
  const MidiSource(this.kind, this.channel, [this.cc = 0]);

  factory MidiSource.fromJson(Map<String, dynamic> j) {
    final k = MidiSourceKind.parse(j['k']);
    if (k == null) throw const FormatException('origem MIDI desconhecida');
    final ch = j['ch'];
    final cc = j['cc'];
    return MidiSource(k, ch is num ? ch.toInt().clamp(0, 15) : 0, cc is num ? cc.toInt().clamp(0, 127) : 0);
  }

  Map<String, dynamic> toJson() => {'k': kind.name, 'ch': channel, if (kind == MidiSourceKind.cc) 'cc': cc};

  /// "Canal 1 · CC 74", para a lista.
  String get label =>
      'Canal ${channel + 1} · ${switch (kind) {
        MidiSourceKind.cc => 'CC $cc',
        MidiSourceKind.bend => 'Pitch bend',
        MidiSourceKind.pressure => 'Pressão do canal',
      }}';

  /// Curto, para o contorno de um controle mapeado: "CC74", "Bend", "Pres.".
  String get shortLabel => switch (kind) {
    MidiSourceKind.cc => 'CC$cc',
    MidiSourceKind.bend => 'Bend',
    MidiSourceKind.pressure => 'Pres.',
  };

  @override
  bool operator ==(Object other) => other is MidiSource && other.kind == kind && other.channel == channel && other.cc == cc;

  @override
  int get hashCode => Object.hash(kind, channel, cc);
}

/// A forma como o valor do controlador vira posição do controle.
enum MidiCurve {
  linear('Linear'),
  log('Logarítmica');

  final String label;
  const MidiCurve(this.label);

  static MidiCurve parse(Object? s) => values.firstWhere((c) => c.name == s, orElse: () => linear);
}

/// Um mapeamento: [source] comanda [target] da faixa [trackId] (null: o master).
///
/// [min] e [max] são frações 0..1 da faixa do controle (na escala dele: o fader, o botão), não do
/// valor bruto: "de 20% a 80% do curso". [inverted] espelha o controlador.
class MidiMapping {
  final String id;
  MidiSource source;
  final String? trackId;
  final AutoTarget target;
  double min, max;
  MidiCurve curve;
  bool inverted;

  MidiMapping({
    required this.id,
    required this.source,
    required this.trackId,
    required this.target,
    this.min = 0,
    this.max = 1,
    this.curve = MidiCurve.linear,
    this.inverted = false,
  });

  /// Lança [FormatException] se falta o essencial; o resto tem padrão. Valores fora de faixa são
  /// levados para dentro dela.
  factory MidiMapping.fromJson(Map<String, dynamic> j) {
    final id = j['id'];
    final src = j['src'];
    final tg = j['target'];
    if (id is! String || src is! Map || tg is! Map) throw const FormatException('mapeamento incompleto');
    final kind = AutoKind.values.where((k) => k.name == tg['kind']).firstOrNull;
    if (kind == null) throw const FormatException('alvo desconhecido');
    final track = j['track'];
    double frac(Object? v, double def) => v is num && v.isFinite ? v.toDouble().clamp(0.0, 1.0) : def;
    return MidiMapping(
      id: id,
      source: MidiSource.fromJson(src.cast<String, dynamic>()),
      trackId: track is String ? track : null,
      target: AutoTarget(kind, ref: tg['ref'] is String ? tg['ref'] : null, param: tg['param'] is num ? (tg['param'] as num).toInt() : 0),
      min: frac(j['min'], 0),
      max: frac(j['max'], 1),
      curve: MidiCurve.parse(j['curve']),
      inverted: j['inv'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'src': source.toJson(),
    'track': trackId,
    'target': target.toJson(),
    'min': min,
    'max': max,
    'curve': curve.name,
    'inv': inverted,
  };

  MidiMapping copy() => MidiMapping(id: id, source: source, trackId: trackId, target: target, min: min, max: max, curve: curve, inverted: inverted);

  bool sameTarget(String? track, AutoTarget t) => trackId == track && target == t;
}

/// O conjunto de mapeamentos do projeto e a opção de takeover.
class MidiMap {
  final List<MidiMapping> items;

  /// Modo pegar/pular: um controle que já tem valor só passa a seguir o controlador quando este
  /// cruza (ou chega perto de) o valor atual, em vez de saltar para ele.
  bool soft;

  MidiMap({List<MidiMapping>? items, this.soft = true}) : items = items ?? [];

  bool get isEmpty => items.isEmpty;

  /// Tolerante: qualquer coisa que não seja um mapa válido vira um mapa vazio, e uma entrada
  /// inválida é descartada sem derrubar as outras (um documento de outra versão abre).
  factory MidiMap.fromJson(Object? j) {
    if (j is! Map) return MidiMap();
    final out = MidiMap(soft: j['soft'] != false);
    final seen = <String>{};
    final list = j['items'];
    if (list is List) {
      for (final x in list) {
        if (x is! Map) continue;
        try {
          final m = MidiMapping.fromJson(x.cast<String, dynamic>());
          if (seen.add(m.id)) out.items.add(m);
        } on Object {
          continue;
        }
      }
    }
    return out;
  }

  Map<String, dynamic> toJson() => {
    'soft': soft,
    'items': [for (final m in items) m.toJson()],
  };

  MidiMap copy() => MidiMap(items: [for (final m in items) m.copy()], soft: soft);
}

// ------------------------------------------------------------------------- conta

/// O valor do controlador em 0..1: CC e pressão em 7 bits, pitch bend em 14 bits (LSB em [d1], MSB
/// em [d2]); sem deslocar acima de 32 bits.
double midiRaw(MidiSourceKind kind, int d1, int d2) => switch (kind) {
  MidiSourceKind.cc => (d2 & 0x7F) / 127,
  MidiSourceKind.pressure => (d1 & 0x7F) / 127,
  MidiSourceKind.bend => ((d2 & 0x7F) * 128 + (d1 & 0x7F)) / 16383,
};

/// A curva sobre 0..1: logarítmica sobe depressa no começo (0→0, 1→1).
double midiCurveApply(MidiCurve c, double n) {
  n = n.clamp(0.0, 1.0);
  return c == MidiCurve.log ? math.log(1 + 9 * n) / math.ln10 : n;
}

/// De 0..1 do controlador à posição 0..1 do controle: curva, inversão e faixa [min, max].
double midiMappingNorm(MidiMapping m, double raw) {
  var n = midiCurveApply(m.curve, raw);
  if (m.inverted) n = 1 - n;
  return m.min + (m.max - m.min) * n;
}

/// Tolerância do takeover: 2% do curso.
const midiPickupTolerance = 0.02;

/// Estado do modo pegar/pular de um mapeamento.
class MidiPickup {
  bool picked = false;

  /// Último valor do controlador (já na escala do controle) e o último que o app aplicou.
  double? lastIn, lastOut;

  /// Decide se o controlador [incoming] (posição 0..1 do controle) deve mexer no controle que está
  /// em [current]; [lo] e [hi] são os limites do mapeamento (o valor atual é levado para dentro
  /// deles, senão um controle fora da faixa nunca seria alcançado).
  bool accept(double incoming, double current, double lo, double hi) {
    // outra mão (o mouse, a automação) mexeu no controle desde a última vez: pega de novo
    final out = lastOut;
    if (picked && out != null && (current - out).abs() > midiPickupTolerance) picked = false;
    if (!picked) {
      final cur = current.clamp(math.min(lo, hi), math.max(lo, hi));
      final prev = lastIn;
      if ((incoming - cur).abs() <= midiPickupTolerance || (prev != null && (prev - cur) * (incoming - cur) <= 0)) picked = true;
    }
    lastIn = incoming;
    return picked;
  }
}
