// Contrato dos efeitos entre o app e o motor: lê engine/src/effect.rs e confere, efeito por
// efeito, que cada constante dos módulos `*_param` tem o mesmo id e o mesmo parâmetro nas tabelas
// de effects.dart (e nada sobra dos dois lados), que os códigos de `fx_set` batem com EffectKind,
// que as figuras de NOTE_BEATS são as de noteValues e que a faixa escrita no comentário da
// constante é a da tabela. Um id trocado de um lado só mandaria o valor para outro botão.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jopendaw_app/daw/effects.dart';
import 'package:jopendaw_app/daw/instruments.dart';

/// Constante do motor → nome do parâmetro na tabela do app.
const _names = <EffectKind, Map<String, String>>{
  EffectKind.compressor: {
    'THRESHOLD': 'Limiar',
    'RATIO': 'Razão',
    'ATTACK': 'Ataque',
    'RELEASE': 'Soltura',
    'KNEE': 'Joelho',
    'MAKEUP': 'Ganho',
    'MIX': 'Mistura',
    'DETECTOR': 'Detector',
    'SC_HPF': 'Passa-alta',
    'AUTO_MAKEUP': 'Ganho automático',
    'SIDECHAIN': 'Sidechain',
  },
  EffectKind.gate: {
    'THRESHOLD': 'Limiar',
    'ATTACK': 'Ataque',
    'HOLD': 'Retenção',
    'RELEASE': 'Soltura',
    'RANGE': 'Alcance',
    'SC_HPF': 'Passa-alta',
    'SIDECHAIN': 'Sidechain',
  },
  EffectKind.limiter: {'GAIN': 'Ganho', 'CEILING': 'Teto', 'RELEASE': 'Soltura', 'LOOKAHEAD': 'Lookahead', 'LINK': 'Ligação estéreo'},
  EffectKind.utility: {
    'GAIN': 'Ganho',
    'PAN': 'Pan',
    'WIDTH': 'Largura',
    'MONO': 'Mono',
    'INVERT_L': 'Inverter esq.',
    'INVERT_R': 'Inverter dir.',
    'SWAP': 'Trocar E/D',
    'DC': 'Tirar DC',
  },
  EffectKind.reverb: {
    'MIX': 'Mistura',
    'PREDELAY': 'Pré-atraso',
    'SIZE': 'Tamanho',
    'DECAY': 'Decaimento',
    'DAMPING': 'Abafar',
    'LOW_CUT': 'Cortar graves',
    'WIDTH': 'Largura',
    'MODULATION': 'Modulação',
    'EARLY': 'Primeiras reflexões',
    'FREEZE': 'Congelar',
  },
  EffectKind.delay: {
    'MIX': 'Mistura',
    'SYNC': 'Tempo',
    'TIME': 'Tempo livre',
    'NOTE': 'Nota',
    'FEEDBACK': 'Realimentação',
    'PING_PONG': 'Ping-pong',
    'OFFSET': 'Desvio E/D',
    'HIGH_PASS': 'Passa-alta',
    'LOW_PASS': 'Passa-baixa',
    'MODULATION': 'Modulação',
    'DRIVE': 'Saturação',
    'DUCKING': 'Ducking',
  },
  EffectKind.chorus: {
    'MIX': 'Mistura',
    'RATE': 'Taxa',
    'DEPTH': 'Profundidade',
    'DELAY': 'Atraso',
    'VOICES': 'Vozes',
    'FEEDBACK': 'Realimentação',
    'WIDTH': 'Largura',
  },
  EffectKind.phaser: {
    'MIX': 'Mistura',
    'RATE': 'Taxa',
    'DEPTH': 'Profundidade',
    'CENTER': 'Centro',
    'FEEDBACK': 'Realimentação',
    'STAGES': 'Estágios',
    'STEREO': 'Estéreo',
  },
  EffectKind.tremolo: {'RATE': 'Taxa', 'DEPTH': 'Profundidade', 'WAVE': 'Onda', 'STEREO': 'Estéreo', 'SYNC': 'Tempo', 'NOTE': 'Nota'},
  EffectKind.distortion: {
    'DRIVE': 'Drive',
    'TYPE': 'Tipo',
    'TONE': 'Tom',
    'MIX': 'Mistura',
    'OUTPUT': 'Saída',
    'BITS': 'Bits',
    'DOWNSAMPLE': 'Reduzir taxa',
    'OVERSAMPLE': 'Sobreamostragem',
    'DITHER': 'Dither',
  },
  EffectKind.filter: {
    'TYPE': 'Tipo',
    'CUTOFF': 'Corte',
    'RESONANCE': 'Ressonância',
    'LFO_RATE': 'Taxa',
    'LFO_DEPTH': 'Profundidade',
    'LFO_WAVE': 'Onda',
    'ENVELOPE': 'Envelope',
    'DRIVE': 'Drive',
    'MIX': 'Mistura',
    'SYNC': 'Tempo',
    'NOTE': 'Nota',
  },
  EffectKind.deesser: {
    'FREQ': 'Frequência',
    'Q': 'Q',
    'THRESHOLD': 'Limiar',
    'RATIO': 'Razão',
    'ATTACK': 'Ataque',
    'RELEASE': 'Soltura',
    'MODE': 'Modo',
    'LISTEN': 'Ouvir banda',
  },
  EffectKind.imager: {
    'XOVER_LOW': 'Cruzamento baixo/médio',
    'XOVER_HIGH': 'Cruzamento médio/agudo',
    'WIDTH_LOW': 'Baixa',
    'WIDTH_MID': 'Média',
    'WIDTH_HIGH': 'Aguda',
    'BALANCE': 'Balanço',
    'BASS_MONO': 'Mono nos graves',
    'MONO_FREQ': 'Abaixo de',
  },
};

/// Multibanda: constante por banda (k em BAND_BASE + b * BAND_STRIDE + k) → nome na tabela.
const _multibandBand = {
  'BAND_THRESHOLD': 'Limiar',
  'BAND_RATIO': 'Razão',
  'BAND_ATTACK': 'Ataque',
  'BAND_RELEASE': 'Soltura',
  'BAND_MAKEUP': 'Ganho',
  'BAND_SOLO': 'Solo',
  'BAND_BYPASS': 'Bypass',
  'BAND_KNEE': 'Joelho',
};

/// Banda do EQ: constante do motor (k em b * 6 + k) → nome na tabela.
const _eqBand = {'ON': 'Ligada', 'TYPE': 'Tipo', 'FREQ': 'Frequência', 'GAIN': 'Ganho', 'Q': 'Q', 'SLOPE': 'Inclinação'};

/// Uma constante `pub const NOME: u32 = N;` de um módulo, com o comentário `///` logo acima.
typedef _Const = ({String name, int value, String doc});

void main() {
  final src = File('../engine/src/effect.rs').readAsStringSync();

  List<_Const> module(String name) {
    final start = src.indexOf('pub mod $name {');
    expect(start, isNot(-1), reason: 'effect.rs sem o módulo $name');
    final body = src.substring(start, src.indexOf('\n}', start));
    final out = <_Const>[];
    final doc = StringBuffer();
    for (final raw in body.split('\n').skip(1)) {
      final line = raw.trim();
      if (line.startsWith('///')) {
        doc.write('${line.substring(3).trim()} ');
        continue;
      }
      final m = RegExp(r'^pub const (\w+): (?:u32|usize) = (\d+);').firstMatch(line);
      if (m != null) out.add((name: m.group(1)!, value: int.parse(m.group(2)!), doc: doc.toString()));
      doc.clear();
    }
    return out;
  }

  /// Faixa escrita no comentário ("dB, −60..0."), se houver exatamente uma.
  (double, double)? docRange(String doc) {
    double num(String s) => double.parse(s.replaceAll('−', '-').replaceAll(',', '.'));
    final all = RegExp(r'(−?\d+(?:,\d+)?)\.\.(−?\d+(?:,\d+)?)').allMatches(doc).toList();
    return all.length == 1 ? (num(all.single.group(1)!), num(all.single.group(2)!)) : null;
  }

  test('códigos de fx_set iguais aos de EffectKind', () {
    final kinds = module('kind');
    expect(kinds.map((c) => c.name.toLowerCase()), unorderedEquals(EffectKind.values.map((k) => k.name)));
    for (final c in kinds) {
      expect(EffectKind.parse(c.name.toLowerCase())!.code, c.value, reason: c.name);
    }
  });

  test('figuras de NOTE_BEATS iguais a noteValues', () {
    final start = src.indexOf('pub const NOTE_BEATS');
    final body = src.substring(start, src.indexOf('];', start));
    final labels = [for (final m in RegExp(r'// (\S+)').allMatches(body)) m.group(1)!];
    expect(labels, noteValues);
  });

  for (final kind in EffectKind.values.where((k) => k != EffectKind.eq && k != EffectKind.multiband)) {
    test('ids e faixas de ${kind.label} iguais aos do motor', () {
      final consts = module('${kind.name}_param');
      final names = _names[kind]!;
      expect(consts.map((c) => c.name), unorderedEquals(names.keys), reason: 'constantes do motor sem nome no teste (ou o contrário)');
      expect(consts.map((c) => c.value).toSet().length, consts.length, reason: 'id repetido no motor');
      expect(kind.params.map((p) => p.id), unorderedEquals(consts.map((c) => c.value)), reason: 'ids da tabela do app × motor');
      for (final c in consts) {
        final p = kind.params.firstWhere((p) => p.id == c.value);
        expect(p.name, names[c.name], reason: '${kind.name}_param::${c.name} (id ${c.value})');
        final r = docRange(c.doc);
        if (r != null && p.curve != Curve.choice) expect((p.min, p.max), r, reason: 'faixa de ${kind.name}_param::${c.name}');
      }
    });
  }

  test('ids e faixas do EQ iguais aos do motor', () {
    final consts = {for (final c in module('eq_param')) c.name: c};
    expect(consts['BANDS']!.value, 8);
    expect(eqParams.length, 8 * 6 + 1);
    for (var b = 0; b < 8; b++) {
      for (final e in _eqBand.entries) {
        final id = b * 6 + consts[e.key]!.value;
        final p = eqParams.firstWhere((p) => p.id == id, orElse: () => fail('EQ sem o id $id'));
        expect((p.name, p.group), (e.value, 'Banda ${b + 1}'), reason: 'eq_param::${e.key}, banda ${b + 1}');
        final r = docRange(consts[e.key]!.doc);
        if (r != null && p.curve != Curve.choice) expect((p.min, p.max), r, reason: 'faixa de eq_param::${e.key}');
      }
    }
    final out = eqParams.firstWhere((p) => p.id == consts['OUTPUT']!.value);
    expect(out.name, 'Saída');
    expect((out.min, out.max), docRange(consts['OUTPUT']!.doc));
  });

  test('ids e faixas do multibanda iguais aos do motor', () {
    final consts = {for (final c in module('multiband_param')) c.name: c};
    final base = consts['BAND_BASE']!.value, stride = consts['BAND_STRIDE']!.value;
    expect((base, stride, consts['BANDS']!.value), (multibandBase, multibandStride, 3));
    expect(multibandParams.length, 3 + 3 * _multibandBand.length);
    for (final (name, label, group) in [
      ('XOVER_LOW', 'Cruzamento baixo/médio', 'Cruzamento'),
      ('XOVER_HIGH', 'Cruzamento médio/agudo', 'Cruzamento'),
      ('OUTPUT', 'Saída', 'Saída'),
    ]) {
      final p = multibandParams.firstWhere((p) => p.id == consts[name]!.value, orElse: () => fail('multibanda sem $name'));
      expect((p.name, p.group), (label, group), reason: name);
      expect((p.min, p.max), docRange(consts[name]!.doc), reason: 'faixa de $name');
    }
    for (var b = 0; b < 3; b++) {
      for (final e in _multibandBand.entries) {
        final id = base + b * stride + consts[e.key]!.value;
        final p = multibandParams.firstWhere((p) => p.id == id, orElse: () => fail('multibanda sem o id $id'));
        expect(p.name, e.value, reason: '${e.key}, banda $b');
        final r = docRange(consts[e.key]!.doc);
        if (r != null && p.curve != Curve.choice) expect((p.min, p.max), r, reason: 'faixa de ${e.key}');
      }
    }
    expect(multibandParams.map((p) => p.id).toSet().length, multibandParams.length);
  });

  test('indicador do multibanda desempacota como o motor empacota', () {
    // gr0 + 256 * gr1 + 65536 * gr2, décimos de dB
    expect(unpackMultibandMeter(15 + 256 * 123 + 65536 * 255), [1.5, 12.3, 25.5]);
    expect(unpackMultibandMeter(0), [0, 0, 0]);
    expect(unpackMultibandMeter(double.nan), [0, 0, 0]);
    expect(unpackMultibandMeter(-5), [0, 0, 0]);
  });
}
