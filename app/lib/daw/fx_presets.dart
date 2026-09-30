/// Presets dos efeitos: pontos de partida pensados para o uso comum de cada um, não receitas.
///
/// Cada preset diz só o que importa; o resto volta ao padrão da tabela (`applyEffectPreset`
/// completa com o padrão), então os valores daqui são sempre na unidade da tabela de
/// `effects.dart` (dB, Hz, segundos, índice nas listas de opções).
library;

import 'effects.dart';
import 'model.dart';

class EffectPreset {
  final String name;

  /// Parâmetro → valor; o que falta vale o padrão.
  final Map<int, double> values;
  const EffectPreset(this.name, this.values);

  /// Valor que o preset dá a um parâmetro (o padrão quando ele não diz).
  double valueOf(EffectKind kind, int id) {
    final v = values[id];
    if (v != null) return v;
    for (final p in kind.params) {
      if (p.id == id) return p.def;
    }
    return 0;
  }
}

/// Uma banda do EQ nos ids do contrato (`b * 6 + k`). Banda citada fica ligada.
Map<int, double> _band(int b, {required int type, required double freq, double gain = 0, double q = 0.71, int slope = 1}) => {
  b * 6: 1,
  b * 6 + 1: type.toDouble(),
  b * 6 + 2: freq,
  b * 6 + 3: gain,
  b * 6 + 4: q,
  b * 6 + 5: slope.toDouble(),
};

// tipos de banda do EQ (espelho de eq_param::TYPE)
const _hp = 0, _lowShelf = 1, _bell = 2, _highShelf = 3, _lp = 4;

final _eq = <EffectPreset>[
  EffectPreset('Corte de graves', {..._band(0, type: _hp, freq: 80)}),
  EffectPreset('Voz presente', {
    ..._band(0, type: _hp, freq: 90),
    // o "embolado" das salas pequenas e dos microfones perto demais
    ..._band(2, type: _bell, freq: 300, gain: -2.5, q: 1.2),
    // presença: a inteligibilidade mora entre 2 e 5 kHz
    ..._band(4, type: _bell, freq: 3000, gain: 3, q: 0.9),
    ..._band(6, type: _highShelf, freq: 10000, gain: 2),
  }),
  EffectPreset('Bumbo', {
    ..._band(0, type: _hp, freq: 30, slope: 0),
    ..._band(1, type: _bell, freq: 60, gain: 4, q: 1.4),
    // a "caixa de papelão" do bumbo
    ..._band(3, type: _bell, freq: 350, gain: -5, q: 1.5),
    // o clique do batedor, que faz o bumbo aparecer em caixas pequenas
    ..._band(4, type: _bell, freq: 3500, gain: 3.5, q: 1.2),
    ..._band(7, type: _lp, freq: 12000, slope: 0),
  }),
  EffectPreset('Brilho', {
    ..._band(3, type: _bell, freq: 400, gain: -1, q: 1),
    ..._band(5, type: _bell, freq: 4500, gain: 1.5, q: 0.7),
    ..._band(6, type: _highShelf, freq: 9000, gain: 4),
  }),
  EffectPreset('Calor', {..._band(1, type: _lowShelf, freq: 180, gain: 2.5), ..._band(5, type: _bell, freq: 3200, gain: -1.5, q: 0.8)}),
  EffectPreset('Telefone', {
    ..._band(0, type: _hp, freq: 400, slope: 2),
    ..._band(4, type: _bell, freq: 1500, gain: 5, q: 0.8),
    ..._band(7, type: _lp, freq: 3200, slope: 2),
  }),
];

// compressor: 0 limiar, 1 razão, 2 ataque, 3 soltura, 4 joelho, 5 ganho, 6 mistura, 7 detector,
// 8 passa-alta da chave, 9 ganho automático
const _compressor = <EffectPreset>[
  EffectPreset('Voz', {0: -20, 1: 3.5, 2: 0.005, 3: 0.08, 4: 6, 5: 4, 6: 1, 7: 1, 8: 80}),
  // ataque lento deixa o transiente passar; a chave sem grave não bombeia no bumbo
  EffectPreset('Bateria cola', {0: -16, 1: 2, 2: 0.03, 3: 0.2, 4: 4, 5: 2, 6: 1, 7: 1, 8: 90}),
  EffectPreset('Baixo', {0: -22, 1: 5, 2: 0.003, 3: 0.12, 4: 3, 5: 5, 6: 1, 7: 1, 8: 20}),
  // compressão de Nova York: esmaga forte e mistura por baixo do sinal limpo
  EffectPreset('Paralelo pesado', {0: -35, 1: 10, 2: 0.001, 3: 0.1, 4: 0, 5: 12, 6: 0.4, 7: 0, 8: 20}),
  EffectPreset('Suave', {0: -12, 1: 1.6, 2: 0.02, 3: 0.3, 4: 12, 5: 0, 6: 1, 7: 1, 8: 20, 9: 1}),
];

// gate: 0 limiar, 1 ataque, 2 retenção, 3 soltura, 4 alcance, 5 passa-alta da chave
const _gate = <EffectPreset>[
  EffectPreset('Ruído de fundo', {0: -55, 1: 0.001, 2: 0.05, 3: 0.2, 4: -30, 5: 20}),
  EffectPreset('Tons de bateria', {0: -30, 1: 0.0005, 2: 0.08, 3: 0.15, 4: -80, 5: 100}),
  EffectPreset('Corte seco', {0: -35, 1: 0.0001, 2: 0.01, 3: 0.02, 4: -80, 5: 20}),
];

// limitador: 0 ganho, 1 teto, 2 soltura, 3 lookahead, 4 ligação
const _limiter = <EffectPreset>[
  EffectPreset('Master −1 dB', {0: 3, 1: -1, 2: 0.08, 3: 0.005, 4: 1}),
  EffectPreset('Transparente', {0: 1.5, 1: -0.5, 2: 0.25, 3: 0.006, 4: 0.7}),
  EffectPreset('Alto', {0: 8, 1: -1, 2: 0.15, 3: 0.006, 4: 0.8}),
];

// utilitário: 0 ganho, 1 pan, 2 largura, 3 mono, 4/5 inverter, 6 trocar, 7 tirar DC
const _utility = <EffectPreset>[
  EffectPreset('Mono', {3: 1}),
  EffectPreset('Estéreo largo', {2: 1.5}),
  EffectPreset('Fase invertida', {4: 1, 5: 1}),
  EffectPreset('−6 dB', {0: -6}),
];

// reverb: 0 mistura, 1 pré-atraso, 2 tamanho, 3 decaimento, 4 abafar, 5 cortar graves, 6 largura,
// 7 modulação, 8 primeiras reflexões, 9 congelar
const _reverb = <EffectPreset>[
  EffectPreset('Quarto', {0: 0.18, 1: 0.005, 2: 0.25, 3: 0.5, 4: 6000, 5: 150, 6: 0.7, 7: 0.2, 8: 0.7}),
  EffectPreset('Sala', {0: 0.22, 1: 0.015, 2: 0.5, 3: 1.4, 4: 7500, 5: 120, 6: 0.9, 7: 0.3, 8: 0.55}),
  EffectPreset('Salão', {0: 0.28, 1: 0.03, 2: 0.8, 3: 2.8, 4: 6000, 5: 100, 6: 1, 7: 0.35, 8: 0.4}),
  // placa: quase sem reflexões iniciais, densa e brilhante desde o começo
  EffectPreset('Placa', {0: 0.25, 1: 0.01, 2: 0.55, 3: 1.8, 4: 12000, 5: 200, 6: 1, 7: 0.45, 8: 0.15}),
  EffectPreset('Catedral', {0: 0.35, 1: 0.06, 2: 1, 3: 7, 4: 4500, 5: 80, 6: 1, 7: 0.4, 8: 0.3}),
  // cauda congelada e bem modulada: um pad etéreo que segura o que entrou
  EffectPreset('Shimmer congelado', {0: 0.5, 1: 0.08, 2: 1, 3: 20, 4: 9000, 5: 300, 6: 1, 7: 0.8, 8: 0.1, 9: 1}),
];

// delay: 0 mistura, 1 tempo (0 livre, 1 andamento), 2 tempo livre, 3 nota, 4 realimentação,
// 5 ping-pong, 6 desvio, 7 passa-alta, 8 passa-baixa, 9 modulação, 10 saturação, 11 ducking.
// Notas: índices de `noteValues` (5 = 1/8, 6 = 1/8D, 8 = 1/4, 9 = 1/4D).
const _delay = <EffectPreset>[
  EffectPreset('1/8 pontilhado', {0: 0.25, 1: 1, 3: 6, 4: 0.35, 7: 150, 8: 6000, 9: 0.05, 11: 0.3}),
  EffectPreset('Ping-pong 1/4', {0: 0.3, 1: 1, 3: 8, 4: 0.45, 5: 1, 7: 120, 8: 7000, 9: 0.1, 11: 0.2}),
  EffectPreset('Slapback', {0: 0.3, 1: 0, 2: 0.11, 4: 0.05, 7: 100, 8: 5000, 10: 0.1}),
  // ecos que escurecem e saturam a cada volta, como numa fita gasta
  EffectPreset('Dub', {0: 0.35, 1: 1, 3: 9, 4: 0.72, 7: 250, 8: 2500, 9: 0.3, 10: 0.45}),
  EffectPreset('Eco largo', {0: 0.22, 1: 1, 3: 8, 4: 0.3, 6: 0.02, 7: 200, 8: 9000, 11: 0.4}),
];

// chorus: 0 mistura, 1 velocidade, 2 profundidade, 3 atraso, 4 vozes, 5 realimentação, 6 largura
const _chorus = <EffectPreset>[
  EffectPreset('Chorus leve', {0: 0.35, 1: 0.6, 2: 0.35, 3: 0.014, 4: 2, 5: 0, 6: 1}),
  // atraso curtíssimo com realimentação alta: o pente varrendo devagar
  EffectPreset('Flanger jato', {0: 0.5, 1: 0.12, 2: 0.8, 3: 0.002, 4: 1, 5: 0.75, 6: 0.8}),
  EffectPreset('Ensemble', {0: 0.5, 1: 1.1, 2: 0.5, 3: 0.018, 4: 4, 5: 0, 6: 1}),
  EffectPreset('Vibrato', {0: 1, 1: 5, 2: 0.25, 3: 0.004, 4: 1, 5: 0, 6: 0}),
];

// phaser: 0 mistura, 1 velocidade, 2 profundidade, 3 centro, 4 realimentação, 5 estágios
// (índice em 2, 4, 6, 8, 12), 6 estéreo
const _phaser = <EffectPreset>[
  EffectPreset('Lento', {0: 0.5, 1: 0.15, 2: 0.8, 3: 800, 4: 0.5, 5: 2, 6: 0.5}),
  EffectPreset('Rápido', {0: 0.5, 1: 3.5, 2: 0.6, 3: 1200, 4: 0.35, 5: 1, 6: 0.25}),
  EffectPreset('Profundo (12 estágios)', {0: 0.5, 1: 0.08, 2: 1, 3: 1500, 4: 0.8, 5: 4, 6: 0.5}),
];

// tremolo: 0 velocidade, 1 profundidade, 2 onda, 3 estéreo, 4 tempo, 5 nota
const _tremolo = <EffectPreset>[
  EffectPreset('Tremolo clássico', {0: 5, 1: 0.5, 2: 0, 3: 0}),
  EffectPreset('Autopan 1/4', {1: 0.8, 2: 0, 3: 0.5, 4: 1, 5: 8}),
  EffectPreset('Picotado 1/16', {1: 1, 2: 2, 3: 0, 4: 1, 5: 2}),
];

// distorção: 0 drive, 1 tipo (0 suave, 1 válvula, 2 fita, 3 dura, 4 dobra, 5 bitcrusher), 2 tom,
// 3 mistura, 4 saída, 5 bits, 6 reduzir taxa, 7 sobreamostragem (0 1×, 1 2×, 2 4×)
const _distortion = <EffectPreset>[
  EffectPreset('Saturação de fita', {0: 6, 1: 2, 2: 12000, 3: 1, 4: -2, 7: 1}),
  EffectPreset('Válvula quente', {0: 14, 1: 1, 2: 7000, 3: 1, 4: -6, 7: 1}),
  EffectPreset('Fuzz', {0: 36, 1: 3, 2: 4500, 3: 1, 4: -12, 7: 2}),
  EffectPreset('Lo-fi 8 bits', {0: 0, 1: 5, 2: 9000, 3: 1, 4: -1, 5: 8, 6: 4, 7: 0}),
  EffectPreset('Dobra metálica', {0: 18, 1: 4, 2: 6000, 3: 0.6, 4: -8, 7: 2}),
];

// filtro: 0 tipo, 1 corte, 2 ressonância, 3 velocidade do LFO, 4 profundidade (oitavas), 5 onda,
// 6 envelope (oitavas), 7 drive, 8 mistura, 9 tempo (0 livre, 1 andamento), 10 nota
const _filter = <EffectPreset>[
  EffectPreset('Varredura lenta', {0: 1, 1: 700, 2: 0.35, 3: 0.1, 4: 3, 5: 0, 7: 0.1, 8: 1, 9: 0}),
  EffectPreset('Wobble 1/8', {0: 1, 1: 400, 2: 0.55, 4: 3.5, 5: 0, 7: 0.3, 8: 1, 9: 1, 10: 5}),
  // o envelope abre o filtro a cada ataque: o "wah" que segue a dinâmica de quem toca
  EffectPreset('Auto-wah', {0: 4, 1: 500, 2: 0.6, 4: 0, 6: 3.5, 8: 1}),
  EffectPreset('Passa-alta de transição', {0: 3, 1: 250, 2: 0.25, 4: 0, 8: 1}),
];

/// Uma banda do multibanda nos ids do contrato (`4 + b * 8 + k`).
Map<int, double> _mb(
  int b, {
  required double threshold,
  required double ratio,
  double attack = 0.01,
  double release = 0.15,
  double makeup = 0,
  double knee = 6,
}) => {4 + b * 8: threshold, 4 + b * 8 + 1: ratio, 4 + b * 8 + 2: attack, 4 + b * 8 + 3: release, 4 + b * 8 + 4: makeup, 4 + b * 8 + 7: knee};

// multibanda: 0 cruzamento baixo/médio, 1 médio/agudo, 2 saída; bandas em 4 + b * 8 (limiar, razão,
// ataque, soltura, ganho, solo, bypass, joelho)
final _multiband = <EffectPreset>[
  EffectPreset('Bateria colada', {
    0: 120,
    1: 4000,
    ..._mb(0, threshold: -20, ratio: 3, attack: 0.03, release: 0.2, makeup: 1),
    ..._mb(1, threshold: -18, ratio: 2.5, attack: 0.02, release: 0.12),
    ..._mb(2, threshold: -22, ratio: 2, attack: 0.005, release: 0.08, makeup: 1),
  }),
  EffectPreset('Mix de bus', {
    0: 150,
    1: 3500,
    2: 1,
    ..._mb(0, threshold: -16, ratio: 2, attack: 0.03, release: 0.3, knee: 10),
    ..._mb(1, threshold: -14, ratio: 1.6, attack: 0.02, release: 0.2, knee: 10),
    ..._mb(2, threshold: -18, ratio: 1.8, attack: 0.01, release: 0.15, knee: 10),
  }),
  EffectPreset('Master suave', {
    0: 100,
    1: 5000,
    ..._mb(0, threshold: -14, ratio: 1.8, attack: 0.04, release: 0.4, knee: 12),
    ..._mb(1, threshold: -12, ratio: 1.4, attack: 0.03, release: 0.25, knee: 12),
    ..._mb(2, threshold: -16, ratio: 1.5, attack: 0.015, release: 0.2, knee: 12),
  }),
  // graves domados e agudos contidos, o médio (a voz) quase intocado
  EffectPreset('Controle de graves', {
    0: 180,
    1: 3000,
    ..._mb(0, threshold: -26, ratio: 5, attack: 0.01, release: 0.15, knee: 3),
    ..._mb(1, threshold: -10, ratio: 1.2),
    ..._mb(2, threshold: -30, ratio: 3, attack: 0.002, release: 0.06, knee: 3),
  }),
];

// de-esser: 0 frequência, 1 Q, 2 limiar, 3 razão, 4 ataque, 5 soltura, 6 modo (0 dividida, 1 larga),
// 7 ouvir
const _deesser = <EffectPreset>[
  EffectPreset('Voz suave', {0: 6500, 1: 1.5, 2: -32, 3: 4, 4: 0.001, 5: 0.05, 6: 0}),
  EffectPreset('Voz feminina', {0: 8000, 1: 1.8, 2: -30, 3: 5, 4: 0.001, 5: 0.04, 6: 0}),
  EffectPreset('Voz masculina', {0: 5500, 1: 1.3, 2: -30, 3: 5, 4: 0.001, 5: 0.06, 6: 0}),
  // comprime tudo quando o "s" estoura: pega os pratos e o chiado de uma vez
  EffectPreset('Banda larga', {0: 7000, 1: 1, 2: -28, 3: 3, 4: 0.0005, 5: 0.08, 6: 1}),
];

// imagem estéreo: 0/1 cruzamentos, 2/3/4 largura baixa/média/aguda, 5 balanço, 6 mono nos graves,
// 7 frequência do mono
const _imager = <EffectPreset>[
  EffectPreset('Mix de bus', {0: 200, 1: 4000, 2: 0.8, 3: 1.1, 4: 1.25, 6: 1, 7: 120}),
  EffectPreset('Graves em mono', {0: 150, 1: 4000, 2: 0, 3: 1, 4: 1, 6: 1, 7: 150}),
  EffectPreset('Largo', {0: 250, 1: 3000, 2: 0.6, 3: 1.4, 4: 1.7, 6: 1, 7: 100}),
  EffectPreset('Quase mono', {0: 200, 1: 4000, 2: 0, 3: 0.4, 4: 0.6}),
];

/// Os presets de um tipo de efeito, na ordem do menu.
List<EffectPreset> effectPresetsFor(EffectKind kind) => switch (kind) {
  EffectKind.eq => _eq,
  EffectKind.compressor => _compressor,
  EffectKind.gate => _gate,
  EffectKind.limiter => _limiter,
  EffectKind.utility => _utility,
  EffectKind.reverb => _reverb,
  EffectKind.delay => _delay,
  EffectKind.chorus => _chorus,
  EffectKind.phaser => _phaser,
  EffectKind.tremolo => _tremolo,
  EffectKind.distortion => _distortion,
  EffectKind.filter => _filter,
  EffectKind.multiband => _multiband,
  EffectKind.deesser => _deesser,
  EffectKind.imager => _imager,
};

/// O preset que bate com os parâmetros do slot agora (null se foi mexido ou é outro). O
/// sidechain não conta: escolher a chave não "desfaz" o preset.
EffectPreset? matchingEffectPreset(EffectSlot slot) {
  final sidechain = switch (slot.kind) {
    EffectKind.compressor => 10,
    EffectKind.gate => 6,
    _ => -1,
  };
  for (final preset in effectPresetsFor(slot.kind)) {
    var same = true;
    for (final p in slot.kind.params) {
      if (p.id == sidechain) continue;
      final a = slot.param(p.id), b = preset.valueOf(slot.kind, p.id);
      if ((a - b).abs() > 1e-6 * (1 + b.abs())) {
        same = false;
        break;
      }
    }
    if (same) return preset;
  }
  return null;
}

/// Os parâmetros do slot estão todos no padrão.
bool isDefaultEffect(EffectSlot slot) {
  for (final p in slot.kind.params) {
    if ((slot.param(p.id) - p.def).abs() > 1e-6 * (1 + p.def.abs())) return false;
  }
  return true;
}
