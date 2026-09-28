/// Os instrumentos próprios do jopendaw e a tabela de parâmetros de cada um.
///
/// Os ids são contrato com o motor (`engine/src/instrument.rs`, módulos `synth_param`,
/// `drum_param` e `sampler_param`): mudar um id quebra projetos salvos. Os valores vão ao motor
/// na unidade da tabela (Hz, segundos, semitons), nunca normalizados.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Tipo da faixa. O índice é o código que o motor recebe em `track_kind`.
enum TrackKind {
  audio('Áudio', Icons.graphic_eq),
  synth('Sintetizador', Icons.piano),
  drums('Bateria', Icons.grid_view),
  sampler('Sampler', Icons.music_note);

  final String label;
  final IconData icon;
  const TrackKind(this.label, this.icon);

  bool get isInstrument => this != audio;

  static TrackKind parse(String? s) => values.firstWhere((k) => k.name == s, orElse: () => audio);

  List<ParamSpec> get params => switch (this) {
    audio => const [],
    synth => synthParams,
    drums => drumParams,
    sampler => samplerParams,
  };
}

/// Como o controle mostra e move o valor.
enum Curve {
  /// Linear.
  linear,

  /// Logarítmica (frequência, tempo): o meio do curso é a média geométrica.
  log,

  /// Inteiro.
  integer,

  /// Lista de opções (o valor é o índice).
  choice,
}

class ParamSpec {
  final int id;
  final String name, group;
  final double min, def;
  final double _max;
  final String unit;
  final Curve curve;
  final List<String> options;

  const ParamSpec(this.id, this.name, this.group, this.min, double max, this.def, {this.unit = '', this.curve = Curve.linear, this.options = const []})
    : _max = max;

  const ParamSpec.choice(this.id, this.name, this.group, this.options, {this.def = 0}) : min = 0, _max = 0, unit = '', curve = Curve.choice;

  double get max => curve == Curve.choice ? options.length - 1.0 : _max;

  double clamp(double v) => v.clamp(min, max).toDouble();

  /// Valor → posição 0..1 do controle.
  double toNorm(double v) {
    v = clamp(v);
    if (curve == Curve.log) {
      final lo = math.max(min, 1e-6);
      return math.log(math.max(v, lo) / lo) / math.log(max / lo);
    }
    return max == min ? 0 : (v - min) / (max - min);
  }

  /// Posição 0..1 → valor (inteiros e opções arredondados).
  double fromNorm(double n) {
    n = n.clamp(0.0, 1.0);
    if (curve == Curve.log) {
      final lo = math.max(min, 1e-6);
      return lo * math.pow(max / lo, n);
    }
    final v = min + (max - min) * n;
    return curve == Curve.integer || curve == Curve.choice ? v.roundToDouble() : v;
  }

  /// Texto do valor para o usuário.
  String format(double v) {
    if (curve == Curve.choice) return options[clamp(v).round()];
    if (curve == Curve.integer) return '${v.round()}$unit';
    switch (unit) {
      case 'Hz':
        return v >= 1000 ? '${(v / 1000).toStringAsFixed(v >= 10000 ? 1 : 2)} kHz' : '${v.toStringAsFixed(v < 10 ? 2 : 0)} Hz';
      case 's':
        return v < 1 ? '${(v * 1000).toStringAsFixed(v < 0.01 ? 1 : 0)} ms' : '${v.toStringAsFixed(2)} s';
      case '%':
        return '${(v * 100).round()}%';
      case 'st':
        return '${v >= 0 ? '+' : ''}${v.toStringAsFixed(v == v.roundToDouble() ? 0 : 1)} st';
      case 'ct':
        return '${v >= 0 ? '+' : ''}${v.round()} ct';
      case 'x':
        return '×${v.toStringAsFixed(2)}';
      case 'oct':
        return '${v.toStringAsFixed(1)} oit';
      default:
        return v.toStringAsFixed(2);
    }
  }
}

const _waves = ['Serra', 'Quadrada', 'Triângulo', 'Senoide'];

/// Sintetizador subtrativo: 2 osciladores + sub + ruído, uníssono, filtro SVF, 2 envelopes, LFO.
const synthParams = <ParamSpec>[
  ParamSpec.choice(0, 'Onda', 'Oscilador 1', _waves),
  ParamSpec(1, 'Nível', 'Oscilador 1', 0, 1, 0.8, unit: '%'),
  ParamSpec(2, 'Pulso', 'Oscilador 1', 0.05, 0.95, 0.5, unit: '%'),
  ParamSpec.choice(3, 'Onda', 'Oscilador 2', _waves),
  ParamSpec(4, 'Nível', 'Oscilador 2', 0, 1, 0.5, unit: '%'),
  ParamSpec(5, 'Semitons', 'Oscilador 2', -24, 24, 0, unit: 'st', curve: Curve.integer),
  ParamSpec(6, 'Desafinação', 'Oscilador 2', -100, 100, 7, unit: 'ct'),
  ParamSpec(7, 'Sub', 'Mistura', 0, 1, 0, unit: '%'),
  ParamSpec(8, 'Ruído', 'Mistura', 0, 1, 0, unit: '%'),
  ParamSpec(9, 'Uníssono', 'Mistura', 1, 7, 1, curve: Curve.integer),
  ParamSpec(10, 'Espalhar', 'Mistura', 0, 100, 20, unit: 'ct'),
  ParamSpec(11, 'Estéreo', 'Mistura', 0, 1, 0.5, unit: '%'),
  ParamSpec.choice(12, 'Tipo', 'Filtro', ['Passa-baixa', 'Passa-alta', 'Passa-banda']),
  ParamSpec(13, 'Corte', 'Filtro', 20, 20000, 2400, unit: 'Hz', curve: Curve.log),
  ParamSpec(14, 'Ressonância', 'Filtro', 0, 1, 0.2, unit: '%'),
  ParamSpec(15, 'Envelope', 'Filtro', -1, 1, 0.3, unit: '%'),
  ParamSpec(16, 'Teclado', 'Filtro', 0, 1, 0.5, unit: '%'),
  ParamSpec(34, 'Drive', 'Filtro', 0, 1, 0, unit: '%'),
  ParamSpec(17, 'Ataque', 'Amplitude', 0.0005, 10, 0.005, unit: 's', curve: Curve.log),
  ParamSpec(18, 'Decaimento', 'Amplitude', 0.001, 10, 0.3, unit: 's', curve: Curve.log),
  ParamSpec(19, 'Sustentação', 'Amplitude', 0, 1, 0.7, unit: '%'),
  ParamSpec(20, 'Soltura', 'Amplitude', 0.001, 10, 0.25, unit: 's', curve: Curve.log),
  ParamSpec(21, 'Ataque', 'Envelope do filtro', 0.0005, 10, 0.005, unit: 's', curve: Curve.log),
  ParamSpec(22, 'Decaimento', 'Envelope do filtro', 0.001, 10, 0.4, unit: 's', curve: Curve.log),
  ParamSpec(23, 'Sustentação', 'Envelope do filtro', 0, 1, 0.2, unit: '%'),
  ParamSpec(24, 'Soltura', 'Envelope do filtro', 0.001, 10, 0.3, unit: 's', curve: Curve.log),
  ParamSpec.choice(25, 'Onda', 'LFO', ['Senoide', 'Triângulo', 'Serra', 'Quadrada', 'Aleatório']),
  ParamSpec(26, 'Velocidade', 'LFO', 0.05, 30, 5, unit: 'Hz', curve: Curve.log),
  ParamSpec(27, 'Vibrato', 'LFO', 0, 12, 0, unit: 'st'),
  ParamSpec(28, 'Filtro', 'LFO', 0, 4, 0, unit: 'oct'),
  ParamSpec(29, 'Tremolo', 'LFO', 0, 1, 0, unit: '%'),
  ParamSpec(30, 'Glide', 'Geral', 0, 2, 0, unit: 's'),
  ParamSpec(31, 'Vozes', 'Geral', 1, 16, 8, curve: Curve.integer),
  ParamSpec(32, 'Velocidade', 'Geral', 0, 1, 0.7, unit: '%'),
  ParamSpec(33, 'Volume', 'Geral', 0, 1.5, 0.7, unit: '%'),
];

/// Uma peça da bateria: nome e a nota MIDI principal (General MIDI).
class DrumPiece {
  final String name;
  final int pitch;
  const DrumPiece(this.name, this.pitch);
}

/// Na ordem dos ids do motor (`drum_param::PIECE_PITCH`).
const drumPieces = <DrumPiece>[
  DrumPiece('Bumbo', 36),
  DrumPiece('Caixa', 38),
  DrumPiece('Palmas', 39),
  DrumPiece('Chimbal fechado', 42),
  DrumPiece('Chimbal aberto', 46),
  DrumPiece('Tom grave', 41),
  DrumPiece('Tom médio', 45),
  DrumPiece('Tom agudo', 48),
  DrumPiece('Prato de ataque', 49),
  DrumPiece('Prato de condução', 51),
  DrumPiece('Aro', 37),
  DrumPiece('Cowbell', 56),
];

/// Peças × (volume, afinação, decaimento, timbre) em `peça * 4 + k`, mais o volume geral (48).
final drumParams = <ParamSpec>[
  for (var i = 0; i < drumPieces.length; i++) ...[
    ParamSpec(i * 4, 'Volume', drumPieces[i].name, 0, 1.5, 1, unit: '%'),
    ParamSpec(i * 4 + 1, 'Afinação', drumPieces[i].name, -12, 12, 0, unit: 'st'),
    ParamSpec(i * 4 + 2, 'Decaimento', drumPieces[i].name, 0.25, 4, 1, unit: 'x', curve: Curve.log),
    ParamSpec(i * 4 + 3, 'Timbre', drumPieces[i].name, 0, 1, 0.5, unit: '%'),
  ],
  const ParamSpec(48, 'Volume', 'Geral', 0, 1.5, 0.8, unit: '%'),
];

/// Nome da peça numa nota, ou null.
String? drumNameFor(int pitch) {
  for (final p in drumPieces) {
    if (p.pitch == pitch) return p.name;
  }
  return null;
}

const samplerParams = <ParamSpec>[
  ParamSpec(0, 'Nota base', 'Áudio', 0, 127, 60, curve: Curve.integer),
  ParamSpec(7, 'Afinação', 'Áudio', -100, 100, 0, unit: 'ct'),
  ParamSpec.choice(6, 'Modo', 'Áudio', ['Sustenta', 'Até o fim']),
  ParamSpec(1, 'Ataque', 'Envelope', 0.0005, 10, 0.002, unit: 's', curve: Curve.log),
  ParamSpec(2, 'Decaimento', 'Envelope', 0.001, 10, 0.5, unit: 's', curve: Curve.log),
  ParamSpec(3, 'Sustentação', 'Envelope', 0, 1, 1, unit: '%'),
  ParamSpec(4, 'Soltura', 'Envelope', 0.001, 10, 0.2, unit: 's', curve: Curve.log),
  ParamSpec(8, 'Velocidade', 'Geral', 0, 1, 0.7, unit: '%'),
  ParamSpec(5, 'Volume', 'Geral', 0, 1.5, 0.8, unit: '%'),
];

/// Todos os parâmetros de um tipo no valor padrão.
Map<int, double> defaultParams(TrackKind kind) => {for (final p in kind.params) p.id: p.def};

const _noteNames = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];

/// Nome de uma nota MIDI (60 = C4).
String noteName(int pitch) => '${_noteNames[pitch % 12]}${pitch ~/ 12 - 1}';

bool isBlackKey(int pitch) => const [1, 3, 6, 8, 10].contains(pitch % 12);
