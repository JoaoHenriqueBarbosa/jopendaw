/// Os instrumentos próprios do jopendaw e a tabela de parâmetros de cada um.
///
/// Os ids são contrato com o motor (`engine/src/instrument.rs`, módulos `synth_param`,
/// `drum_param`, `sampler_param`, `fm_param` e `wavetable_param`): mudar um id quebra projetos salvos. Os valores vão ao motor
/// na unidade da tabela (Hz, segundos, semitons), nunca normalizados.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Tipo da faixa. O índice é o código que o motor recebe em `track_kind`.
enum TrackKind {
  audio('Áudio', Icons.graphic_eq),
  synth('Sintetizador', Icons.piano),
  drums('Bateria', Icons.grid_view),
  sampler('Sampler', Icons.music_note),

  /// Barramento: retorno de envios ou grupo. Sem clipes; só recebe áudio de outras faixas.
  bus('Barramento', Icons.call_split),

  /// Sintetizador FM de 4 operadores (o código 5 do motor: o índice do enum é o contrato).
  fm('FM', Icons.blur_on),

  /// Sintetizador de wavetable (código 6).
  wavetable('Wavetable', Icons.waves);

  final String label;
  final IconData icon;
  const TrackKind(this.label, this.icon);

  bool get isInstrument => this == synth || this == drums || this == sampler || this == fm || this == wavetable;

  /// Pode ter clipes (de áudio ou de notas).
  bool get hasClips => this != bus;

  static TrackKind parse(String? s) => values.firstWhere((k) => k.name == s, orElse: () => audio);

  List<ParamSpec> get params => switch (this) {
    audio => const [],
    synth => synthParams,
    drums => drumParams,
    sampler => samplerParams,
    bus => const [],
    fm => fmParams,
    wavetable => wavetableParams,
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
      case 'dB':
        return '${v > 0.05 ? '+' : ''}${v.toStringAsFixed(1)} dB';
      case ':1':
        return '${v.toStringAsFixed(v < 10 ? 1 : 0)}:1';
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
  ParamSpec(35, 'Alcance do bend', 'Geral', 0, 24, 2, unit: 'st', curve: Curve.integer),
  ParamSpec(36, 'Vibrato da roda', 'Geral', 0, 2, 1, unit: 'st'),
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
  ParamSpec(9, 'Alcance do bend', 'Geral', 0, 24, 2, unit: 'st', curve: Curve.integer),
];

/// Algoritmos do FM, na ordem dos ids do motor (`fm.rs`). O nome é o roteamento: `a→b` = `a` modula `b`.
const _fmAlgorithms = ['1→2→3→4', '(1+2)→3→4', '(1 + 2→3)→4', '(1→2 + 3)→4', '(1→2) + (3→4)', '1→(2 + 3 + 4)', '(1→2) + 3 + 4', '1 + 2 + 3 + 4'];

const fmAlgorithmNames = _fmAlgorithms;

/// Roteamento de cada algoritmo, igual ao do motor (`ALGORITHMS` em `fm.rs`; um teste confere): para
/// cada operador (0..3), a máscara de bits dos operadores que o modulam (bit 0 = operador 1).
const fmAlgorithmMods = <List<int>>[
  [0, 1, 2, 4],
  [0, 0, 3, 4],
  [0, 0, 2, 5],
  [0, 1, 0, 6],
  [0, 1, 0, 4],
  [0, 1, 1, 1],
  [0, 1, 0, 0],
  [0, 0, 0, 0],
];

/// Máscara dos operadores que vão à saída (portadores) em cada algoritmo.
const fmAlgorithmCarriers = <int>[8, 8, 8, 8, 10, 14, 14, 15];

/// Séries de tabelas do wavetable (na ordem dos ids do motor); as 8 tabelas de cada uma e a forma
/// delas estão em `wavetable_shape.dart`.
const _wtSeries = ['Clássica', 'Vozes', 'Digital'];

/// Sintetizador FM de 4 operadores: 8 algoritmos, realimentação no operador 1, ADSR por operador.
/// Os ids dos operadores são `2 + operador * 8 + k` (razão, fino, nível, A, D, S, R, velocidade).
const fmParams = <ParamSpec>[
  ParamSpec.choice(0, 'Algoritmo', 'Algoritmo', _fmAlgorithms, def: 4),
  ParamSpec(1, 'Realimentação', 'Algoritmo', 0, 1, 0, unit: '%'),
  ParamSpec(2, 'Razão', 'Operador 1', 0.25, 16, 1, unit: 'x', curve: Curve.log),
  ParamSpec(3, 'Fino', 'Operador 1', -100, 100, 0, unit: 'ct'),
  ParamSpec(4, 'Nível', 'Operador 1', 0, 1, 0.5, unit: '%'),
  ParamSpec(5, 'Ataque', 'Operador 1', 0.0005, 10, 0.001, unit: 's', curve: Curve.log),
  ParamSpec(6, 'Decaimento', 'Operador 1', 0.001, 10, 0.6, unit: 's', curve: Curve.log),
  ParamSpec(7, 'Sustentação', 'Operador 1', 0, 1, 0, unit: '%'),
  ParamSpec(8, 'Soltura', 'Operador 1', 0.001, 10, 0.3, unit: 's', curve: Curve.log),
  ParamSpec(9, 'Velocidade', 'Operador 1', 0, 1, 0.5, unit: '%'),
  ParamSpec(10, 'Razão', 'Operador 2', 0.25, 16, 1, unit: 'x', curve: Curve.log),
  ParamSpec(11, 'Fino', 'Operador 2', -100, 100, 0, unit: 'ct'),
  ParamSpec(12, 'Nível', 'Operador 2', 0, 1, 0.8, unit: '%'),
  ParamSpec(13, 'Ataque', 'Operador 2', 0.0005, 10, 0.001, unit: 's', curve: Curve.log),
  ParamSpec(14, 'Decaimento', 'Operador 2', 0.001, 10, 1.2, unit: 's', curve: Curve.log),
  ParamSpec(15, 'Sustentação', 'Operador 2', 0, 1, 0.3, unit: '%'),
  ParamSpec(16, 'Soltura', 'Operador 2', 0.001, 10, 0.3, unit: 's', curve: Curve.log),
  ParamSpec(17, 'Velocidade', 'Operador 2', 0, 1, 0.3, unit: '%'),
  ParamSpec(18, 'Razão', 'Operador 3', 0.25, 16, 14, unit: 'x', curve: Curve.log),
  ParamSpec(19, 'Fino', 'Operador 3', -100, 100, 0, unit: 'ct'),
  ParamSpec(20, 'Nível', 'Operador 3', 0, 1, 0.3, unit: '%'),
  ParamSpec(21, 'Ataque', 'Operador 3', 0.0005, 10, 0.001, unit: 's', curve: Curve.log),
  ParamSpec(22, 'Decaimento', 'Operador 3', 0.001, 10, 0.15, unit: 's', curve: Curve.log),
  ParamSpec(23, 'Sustentação', 'Operador 3', 0, 1, 0, unit: '%'),
  ParamSpec(24, 'Soltura', 'Operador 3', 0.001, 10, 0.15, unit: 's', curve: Curve.log),
  ParamSpec(25, 'Velocidade', 'Operador 3', 0, 1, 0.5, unit: '%'),
  ParamSpec(26, 'Razão', 'Operador 4', 0.25, 16, 1, unit: 'x', curve: Curve.log),
  ParamSpec(27, 'Fino', 'Operador 4', -100, 100, 0, unit: 'ct'),
  ParamSpec(28, 'Nível', 'Operador 4', 0, 1, 0.7, unit: '%'),
  ParamSpec(29, 'Ataque', 'Operador 4', 0.0005, 10, 0.001, unit: 's', curve: Curve.log),
  ParamSpec(30, 'Decaimento', 'Operador 4', 0.001, 10, 1, unit: 's', curve: Curve.log),
  ParamSpec(31, 'Sustentação', 'Operador 4', 0, 1, 0.2, unit: '%'),
  ParamSpec(32, 'Soltura', 'Operador 4', 0.001, 10, 0.3, unit: 's', curve: Curve.log),
  ParamSpec(33, 'Velocidade', 'Operador 4', 0, 1, 0.3, unit: '%'),
  ParamSpec.choice(34, 'Onda', 'LFO', ['Senoide', 'Triângulo', 'Serra', 'Quadrada', 'Aleatório']),
  ParamSpec(35, 'Velocidade', 'LFO', 0.05, 30, 5, unit: 'Hz', curve: Curve.log),
  ParamSpec(36, 'Vibrato', 'LFO', 0, 12, 0, unit: 'st'),
  ParamSpec(37, 'Tremolo', 'LFO', 0, 1, 0, unit: '%'),
  ParamSpec(38, 'Brilho', 'LFO', 0, 1, 0, unit: '%'),
  ParamSpec(39, 'Vozes', 'Geral', 1, 16, 8, curve: Curve.integer),
  ParamSpec(40, 'Glide', 'Geral', 0, 2, 0, unit: 's'),
  ParamSpec(41, 'Volume', 'Geral', 0, 1.5, 0.7, unit: '%'),
  ParamSpec(42, 'Alcance do bend', 'Geral', 0, 24, 2, unit: 'st', curve: Curve.integer),
  ParamSpec(43, 'Vibrato da roda', 'Geral', 0, 2, 1, unit: 'st'),
];

/// Wavetable: 2 osciladores de tabela (série + posição contínua), sub, ruído, uníssono, filtro SVF
/// com envelope, envelope de amplitude e LFO que também pode mover a posição da tabela.
const wavetableParams = <ParamSpec>[
  ParamSpec.choice(0, 'Série', 'Oscilador 1', _wtSeries),
  ParamSpec(1, 'Posição', 'Oscilador 1', 0, 1, 0.3, unit: '%'),
  ParamSpec(2, 'Nível', 'Oscilador 1', 0, 1, 0.8, unit: '%'),
  ParamSpec(3, 'Semitons', 'Oscilador 1', -24, 24, 0, unit: 'st', curve: Curve.integer),
  ParamSpec(4, 'Desafinação', 'Oscilador 1', -100, 100, 0, unit: 'ct'),
  ParamSpec.choice(5, 'Série', 'Oscilador 2', _wtSeries),
  ParamSpec(6, 'Posição', 'Oscilador 2', 0, 1, 0.5, unit: '%'),
  ParamSpec(7, 'Nível', 'Oscilador 2', 0, 1, 0.5, unit: '%'),
  ParamSpec(8, 'Semitons', 'Oscilador 2', -24, 24, 0, unit: 'st', curve: Curve.integer),
  ParamSpec(9, 'Desafinação', 'Oscilador 2', -100, 100, 7, unit: 'ct'),
  ParamSpec(10, 'Sub', 'Mistura', 0, 1, 0, unit: '%'),
  ParamSpec(11, 'Ruído', 'Mistura', 0, 1, 0, unit: '%'),
  ParamSpec(12, 'Uníssono', 'Mistura', 1, 7, 1, curve: Curve.integer),
  ParamSpec(13, 'Espalhar', 'Mistura', 0, 100, 20, unit: 'ct'),
  ParamSpec(14, 'Estéreo', 'Mistura', 0, 1, 0.5, unit: '%'),
  ParamSpec.choice(15, 'Tipo', 'Filtro', ['Passa-baixa', 'Passa-alta', 'Passa-banda']),
  ParamSpec(16, 'Corte', 'Filtro', 20, 20000, 8000, unit: 'Hz', curve: Curve.log),
  ParamSpec(17, 'Ressonância', 'Filtro', 0, 1, 0.1, unit: '%'),
  ParamSpec(18, 'Envelope', 'Filtro', -1, 1, 0, unit: '%'),
  ParamSpec(19, 'Teclado', 'Filtro', 0, 1, 0.5, unit: '%'),
  ParamSpec(20, 'Ataque', 'Amplitude', 0.0005, 10, 0.005, unit: 's', curve: Curve.log),
  ParamSpec(21, 'Decaimento', 'Amplitude', 0.001, 10, 0.3, unit: 's', curve: Curve.log),
  ParamSpec(22, 'Sustentação', 'Amplitude', 0, 1, 0.8, unit: '%'),
  ParamSpec(23, 'Soltura', 'Amplitude', 0.001, 10, 0.3, unit: 's', curve: Curve.log),
  ParamSpec(24, 'Ataque', 'Envelope do filtro', 0.0005, 10, 0.005, unit: 's', curve: Curve.log),
  ParamSpec(25, 'Decaimento', 'Envelope do filtro', 0.001, 10, 0.5, unit: 's', curve: Curve.log),
  ParamSpec(26, 'Sustentação', 'Envelope do filtro', 0, 1, 0.3, unit: '%'),
  ParamSpec(27, 'Soltura', 'Envelope do filtro', 0.001, 10, 0.4, unit: 's', curve: Curve.log),
  ParamSpec.choice(28, 'Onda', 'LFO', ['Senoide', 'Triângulo', 'Serra', 'Quadrada', 'Aleatório']),
  ParamSpec(29, 'Velocidade', 'LFO', 0.05, 30, 4, unit: 'Hz', curve: Curve.log),
  ParamSpec(30, 'Vibrato', 'LFO', 0, 12, 0, unit: 'st'),
  ParamSpec(31, 'Filtro', 'LFO', 0, 4, 0, unit: 'oct'),
  ParamSpec(32, 'Tremolo', 'LFO', 0, 1, 0, unit: '%'),
  ParamSpec(33, 'Posição', 'LFO', -1, 1, 0, unit: '%'),
  ParamSpec(34, 'Glide', 'Geral', 0, 2, 0, unit: 's'),
  ParamSpec(35, 'Vozes', 'Geral', 1, 16, 8, curve: Curve.integer),
  ParamSpec(36, 'Velocidade', 'Geral', 0, 1, 0.7, unit: '%'),
  ParamSpec(37, 'Volume', 'Geral', 0, 1.5, 0.7, unit: '%'),
  ParamSpec(38, 'Posição (env. do filtro)', 'Envelope do filtro', -1, 1, 0, unit: '%'),
  ParamSpec(39, 'Alcance do bend', 'Geral', 0, 24, 2, unit: 'st', curve: Curve.integer),
  ParamSpec(40, 'Vibrato da roda', 'Geral', 0, 2, 1, unit: 'st'),
];

/// Todos os parâmetros de um tipo no valor padrão.
Map<int, double> defaultParams(TrackKind kind) => {for (final p in kind.params) p.id: p.def};

const _noteNames = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];

/// Nome de uma nota MIDI (60 = C4).
String noteName(int pitch) => '${_noteNames[pitch % 12]}${pitch ~/ 12 - 1}';

bool isBlackKey(int pitch) => const [1, 3, 6, 8, 10].contains(pitch % 12);
