/// Os efeitos próprios do jopendaw e a tabela de parâmetros de cada um.
///
/// Os ids são contrato com o motor (`engine/src/effect.rs`, módulos `*_param`): mudar um id quebra
/// projetos salvos. Os valores vão ao motor na unidade da tabela (dB, Hz, segundos).
library;

import 'package:flutter/material.dart' hide Curve;

import 'instruments.dart';

/// Tipo de efeito. [code] é o que o motor recebe em `fx_set`.
enum EffectKind {
  eq(1, 'EQ', 'Equalizador paramétrico de 8 bandas', Icons.equalizer),
  compressor(2, 'Compressor', 'Controla a dinâmica: segura os picos e encorpa', Icons.compress),
  gate(3, 'Gate', 'Fecha o som abaixo do limiar (ruído, vazamento)', Icons.door_front_door_outlined),
  limiter(4, 'Limitador', 'Teto absoluto, com lookahead', Icons.vertical_align_top),
  utility(5, 'Utilitário', 'Ganho, pan, largura, mono e fase', Icons.tune),
  reverb(6, 'Reverb', 'Ambiência e salas, do quarto à catedral', Icons.blur_on),
  delay(7, 'Delay', 'Ecos livres ou no andamento, com ping-pong', Icons.repeat),
  chorus(8, 'Chorus', 'Chorus e flanger', Icons.waves),
  phaser(9, 'Phaser', 'Filtros passa-tudo em movimento', Icons.cyclone),
  tremolo(10, 'Tremolo', 'Tremolo e autopan', Icons.vibration),
  distortion(11, 'Distorção', 'Saturação, válvula, fita, fuzz e bitcrusher', Icons.bolt),
  filter(12, 'Filtro', 'Filtro com LFO e seguidor de envelope', Icons.filter_alt_outlined);

  final int code;
  final String label, description;
  final IconData icon;
  const EffectKind(this.code, this.label, this.description, this.icon);

  static EffectKind? parse(String? s) {
    for (final k in values) {
      if (k.name == s) return k;
    }
    return null;
  }

  /// Grupo no menu de adicionar.
  String get family => switch (this) {
    eq || filter => 'Timbre',
    compressor || gate || limiter || utility => 'Dinâmica e utilidade',
    reverb || delay => 'Espaço',
    chorus || phaser || tremolo => 'Modulação',
    distortion => 'Saturação',
  };

  List<ParamSpec> get params => switch (this) {
    eq => eqParams,
    compressor => compressorParams,
    gate => gateParams,
    limiter => limiterParams,
    utility => utilityParams,
    reverb => reverbParams,
    delay => delayParams,
    chorus => chorusParams,
    phaser => phaserParams,
    tremolo => tremoloParams,
    distortion => distortionParams,
    filter => filterParams,
  };
}

/// Figuras dos efeitos sincronizados (espelho de `NOTE_BEATS`).
const noteValues = ['1/32', '1/16T', '1/16', '1/16D', '1/8T', '1/8', '1/8D', '1/4T', '1/4', '1/4D', '1/2', '1/1'];
const _noYes = ['Não', 'Sim'];

const eqBandTypes = ['Passa-alta', 'Prateleira grave', 'Sino', 'Prateleira aguda', 'Passa-baixa', 'Rejeita-faixa'];
const _eqFreqs = [30.0, 100.0, 250.0, 800.0, 2500.0, 6000.0, 12000.0, 18000.0];
const _eqTypes = [0, 1, 2, 2, 2, 2, 3, 4];

/// Banda b em b * 6 + k (liga, tipo, frequência, ganho, Q, inclinação); saída em 48.
final eqParams = <ParamSpec>[
  for (var b = 0; b < 8; b++) ...[
    ParamSpec.choice(b * 6, 'Ligada', 'Banda ${b + 1}', _noYes, def: b == 0 || b == 7 ? 0 : 1),
    ParamSpec.choice(b * 6 + 1, 'Tipo', 'Banda ${b + 1}', eqBandTypes, def: _eqTypes[b].toDouble()),
    ParamSpec(b * 6 + 2, 'Frequência', 'Banda ${b + 1}', 20, 20000, _eqFreqs[b], unit: 'Hz', curve: Curve.log),
    ParamSpec(b * 6 + 3, 'Ganho', 'Banda ${b + 1}', -24, 24, 0, unit: 'dB'),
    ParamSpec(b * 6 + 4, 'Q', 'Banda ${b + 1}', 0.1, 18, _eqTypes[b] == 2 ? 1 : 0.71, curve: Curve.log),
    ParamSpec.choice(b * 6 + 5, 'Inclinação', 'Banda ${b + 1}', ['12 dB/oit', '24 dB/oit', '48 dB/oit'], def: 1),
  ],
  const ParamSpec(48, 'Saída', 'Saída', -24, 24, 0, unit: 'dB'),
];

const compressorParams = <ParamSpec>[
  ParamSpec(0, 'Limiar', 'Compressor', -60, 0, -18, unit: 'dB'),
  ParamSpec(1, 'Razão', 'Compressor', 1, 20, 4, unit: ':1', curve: Curve.log),
  ParamSpec(2, 'Ataque', 'Compressor', 0.0001, 0.25, 0.01, unit: 's', curve: Curve.log),
  ParamSpec(3, 'Soltura', 'Compressor', 0.005, 3, 0.15, unit: 's', curve: Curve.log),
  ParamSpec(4, 'Joelho', 'Compressor', 0, 24, 6, unit: 'dB'),
  ParamSpec(5, 'Ganho', 'Saída', 0, 36, 0, unit: 'dB'),
  ParamSpec.choice(9, 'Ganho automático', 'Saída', _noYes),
  ParamSpec(6, 'Mistura', 'Saída', 0, 1, 1, unit: '%'),
  ParamSpec.choice(7, 'Detector', 'Chave', ['Pico', 'RMS'], def: 1),
  ParamSpec(8, 'Passa-alta', 'Chave', 20, 500, 20, unit: 'Hz', curve: Curve.log),
  ParamSpec(10, 'Sidechain', 'Chave', -1, 63, -1, curve: Curve.integer),
];

const gateParams = <ParamSpec>[
  ParamSpec(0, 'Limiar', 'Gate', -80, 0, -50, unit: 'dB'),
  ParamSpec(1, 'Ataque', 'Gate', 0.0001, 0.1, 0.0005, unit: 's', curve: Curve.log),
  ParamSpec(2, 'Retenção', 'Gate', 0, 1, 0.02, unit: 's'),
  ParamSpec(3, 'Soltura', 'Gate', 0.005, 2, 0.1, unit: 's', curve: Curve.log),
  ParamSpec(4, 'Alcance', 'Gate', -80, 0, -80, unit: 'dB'),
  ParamSpec(5, 'Passa-alta', 'Chave', 20, 2000, 20, unit: 'Hz', curve: Curve.log),
  ParamSpec(6, 'Sidechain', 'Chave', -1, 63, -1, curve: Curve.integer),
];

const limiterParams = <ParamSpec>[
  ParamSpec(0, 'Ganho', 'Limitador', 0, 24, 0, unit: 'dB'),
  ParamSpec(1, 'Teto', 'Limitador', -24, 0, -0.3, unit: 'dB'),
  ParamSpec(2, 'Soltura', 'Limitador', 0.001, 1, 0.05, unit: 's', curve: Curve.log),
  ParamSpec(3, 'Lookahead', 'Limitador', 0, 0.01, 0.003, unit: 's'),
  ParamSpec(4, 'Ligação estéreo', 'Limitador', 0, 1, 1, unit: '%'),
];

const utilityParams = <ParamSpec>[
  ParamSpec(0, 'Ganho', 'Utilitário', -48, 24, 0, unit: 'dB'),
  ParamSpec(1, 'Pan', 'Utilitário', -1, 1, 0),
  ParamSpec(2, 'Largura', 'Utilitário', 0, 2, 1, unit: '%'),
  ParamSpec.choice(3, 'Mono', 'Canais', _noYes),
  ParamSpec.choice(4, 'Inverter esq.', 'Canais', _noYes),
  ParamSpec.choice(5, 'Inverter dir.', 'Canais', _noYes),
  ParamSpec.choice(6, 'Trocar E/D', 'Canais', _noYes),
  ParamSpec.choice(7, 'Tirar DC', 'Canais', _noYes),
];

const reverbParams = <ParamSpec>[
  ParamSpec(0, 'Mistura', 'Reverb', 0, 1, 0.25, unit: '%'),
  ParamSpec(1, 'Pré-atraso', 'Reverb', 0, 0.25, 0.02, unit: 's'),
  ParamSpec(2, 'Tamanho', 'Reverb', 0, 1, 0.6, unit: '%'),
  ParamSpec(3, 'Decaimento', 'Reverb', 0.2, 20, 2.2, unit: 's', curve: Curve.log),
  ParamSpec(4, 'Abafar', 'Timbre', 1000, 20000, 7000, unit: 'Hz', curve: Curve.log),
  ParamSpec(5, 'Cortar graves', 'Timbre', 20, 1000, 120, unit: 'Hz', curve: Curve.log),
  ParamSpec(6, 'Largura', 'Timbre', 0, 1, 1, unit: '%'),
  ParamSpec(7, 'Modulação', 'Timbre', 0, 1, 0.3, unit: '%'),
  ParamSpec(8, 'Primeiras reflexões', 'Timbre', 0, 1, 0.5, unit: '%'),
  ParamSpec.choice(9, 'Congelar', 'Timbre', _noYes),
];

const delayParams = <ParamSpec>[
  ParamSpec(0, 'Mistura', 'Delay', 0, 1, 0.3, unit: '%'),
  ParamSpec.choice(1, 'Tempo', 'Delay', ['Livre', 'Andamento'], def: 1),
  ParamSpec(2, 'Tempo livre', 'Delay', 0.001, 4, 0.375, unit: 's', curve: Curve.log),
  ParamSpec.choice(3, 'Nota', 'Delay', noteValues, def: 6),
  ParamSpec(4, 'Realimentação', 'Delay', 0, 0.98, 0.4, unit: '%'),
  ParamSpec.choice(5, 'Ping-pong', 'Delay', _noYes),
  ParamSpec(6, 'Desvio E/D', 'Delay', -0.05, 0.05, 0, unit: 's'),
  ParamSpec(7, 'Passa-alta', 'Timbre', 20, 2000, 80, unit: 'Hz', curve: Curve.log),
  ParamSpec(8, 'Passa-baixa', 'Timbre', 500, 20000, 8000, unit: 'Hz', curve: Curve.log),
  ParamSpec(9, 'Modulação', 'Timbre', 0, 1, 0, unit: '%'),
  ParamSpec(10, 'Saturação', 'Timbre', 0, 1, 0, unit: '%'),
  ParamSpec(11, 'Ducking', 'Timbre', 0, 1, 0, unit: '%'),
];

const chorusParams = <ParamSpec>[
  ParamSpec(0, 'Mistura', 'Chorus', 0, 1, 0.5, unit: '%'),
  ParamSpec(1, 'Velocidade', 'Chorus', 0.02, 10, 0.8, unit: 'Hz', curve: Curve.log),
  ParamSpec(2, 'Profundidade', 'Chorus', 0, 1, 0.5, unit: '%'),
  ParamSpec(3, 'Atraso', 'Chorus', 0.001, 0.03, 0.012, unit: 's'),
  ParamSpec(4, 'Vozes', 'Chorus', 1, 4, 2, curve: Curve.integer),
  ParamSpec(5, 'Realimentação', 'Chorus', -0.95, 0.95, 0, unit: '%'),
  ParamSpec(6, 'Largura', 'Chorus', 0, 1, 1, unit: '%'),
];

const phaserParams = <ParamSpec>[
  ParamSpec(0, 'Mistura', 'Phaser', 0, 1, 0.5, unit: '%'),
  ParamSpec(1, 'Velocidade', 'Phaser', 0.02, 10, 0.5, unit: 'Hz', curve: Curve.log),
  ParamSpec(2, 'Profundidade', 'Phaser', 0, 1, 0.7, unit: '%'),
  ParamSpec(3, 'Centro', 'Phaser', 100, 8000, 1000, unit: 'Hz', curve: Curve.log),
  ParamSpec(4, 'Realimentação', 'Phaser', -0.95, 0.95, 0.5, unit: '%'),
  ParamSpec.choice(5, 'Estágios', 'Phaser', ['2', '4', '6', '8', '12'], def: 1),
  ParamSpec(6, 'Estéreo', 'Phaser', 0, 1, 0.5, unit: '%'),
];

const tremoloParams = <ParamSpec>[
  ParamSpec(0, 'Velocidade', 'Tremolo', 0.05, 20, 4, unit: 'Hz', curve: Curve.log),
  ParamSpec(1, 'Profundidade', 'Tremolo', 0, 1, 0.5, unit: '%'),
  ParamSpec.choice(2, 'Onda', 'Tremolo', ['Senoide', 'Triângulo', 'Quadrada']),
  ParamSpec(3, 'Estéreo', 'Tremolo', 0, 1, 0, unit: '%'),
  ParamSpec.choice(4, 'Tempo', 'Tremolo', ['Livre', 'Andamento']),
  ParamSpec.choice(5, 'Nota', 'Tremolo', noteValues, def: 5),
];

const distortionParams = <ParamSpec>[
  ParamSpec(0, 'Drive', 'Distorção', 0, 48, 12, unit: 'dB'),
  ParamSpec.choice(1, 'Tipo', 'Distorção', ['Suave', 'Válvula', 'Fita', 'Dura', 'Dobra', 'Bitcrusher']),
  ParamSpec(2, 'Tom', 'Distorção', 500, 20000, 8000, unit: 'Hz', curve: Curve.log),
  ParamSpec(3, 'Mistura', 'Saída', 0, 1, 1, unit: '%'),
  ParamSpec(4, 'Saída', 'Saída', -24, 12, 0, unit: 'dB'),
  ParamSpec(5, 'Bits', 'Bitcrusher', 1, 16, 8, curve: Curve.integer),
  ParamSpec(6, 'Reduzir taxa', 'Bitcrusher', 1, 32, 1, unit: '×', curve: Curve.integer),
  ParamSpec.choice(7, 'Sobreamostragem', 'Saída', ['1×', '2×', '4×'], def: 1),
];

const filterParams = <ParamSpec>[
  ParamSpec.choice(0, 'Tipo', 'Filtro', ['Passa-baixa 12', 'Passa-baixa 24', 'Passa-alta 12', 'Passa-alta 24', 'Passa-banda', 'Rejeita-faixa'], def: 1),
  ParamSpec(1, 'Corte', 'Filtro', 20, 20000, 1000, unit: 'Hz', curve: Curve.log),
  ParamSpec(2, 'Ressonância', 'Filtro', 0, 1, 0.2, unit: '%'),
  ParamSpec(7, 'Drive', 'Filtro', 0, 1, 0, unit: '%'),
  ParamSpec(8, 'Mistura', 'Filtro', 0, 1, 1, unit: '%'),
  ParamSpec.choice(9, 'Tempo', 'LFO', ['Livre', 'Andamento']),
  ParamSpec(3, 'Velocidade', 'LFO', 0.02, 20, 1, unit: 'Hz', curve: Curve.log),
  ParamSpec.choice(10, 'Nota', 'LFO', noteValues, def: 8),
  ParamSpec(4, 'Profundidade', 'LFO', 0, 6, 0, unit: 'oct'),
  ParamSpec.choice(5, 'Onda', 'LFO', ['Senoide', 'Triângulo', 'Serra', 'Quadrada', 'Aleatório']),
  ParamSpec(6, 'Envelope', 'Envelope', -6, 6, 0, unit: 'oct'),
];

/// Todos os parâmetros de um efeito no padrão.
Map<int, double> defaultEffectParams(EffectKind kind) => {for (final p in kind.params) p.id: p.def};
