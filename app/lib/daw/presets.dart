/// Presets dos instrumentos: timbres prontos do sintetizador, kits da bateria e envelopes do
/// sampler. Cada preset guarda só o que difere do padrão da tabela (`defaultParams`); o resto
/// volta ao padrão ao aplicar, para que um preset soe igual não importa de onde se parte.
library;

import 'dart:math' as math;

import 'instruments.dart';
import 'model.dart';

/// Ids do sintetizador com nome (espelho de `synth_param` no motor), para presets e painel lerem
/// bem. Os números são os de `synthParams`.
abstract final class SynthId {
  static const osc1Wave = 0, osc1Level = 1, pulse = 2;
  static const osc2Wave = 3, osc2Level = 4, osc2Semi = 5, osc2Detune = 6;
  static const sub = 7, noise = 8, unison = 9, unisonDetune = 10, unisonSpread = 11;
  static const filterType = 12, cutoff = 13, resonance = 14, filterEnv = 15, keytrack = 16, drive = 34;
  static const ampAttack = 17, ampDecay = 18, ampSustain = 19, ampRelease = 20;
  static const fltAttack = 21, fltDecay = 22, fltSustain = 23, fltRelease = 24;
  static const lfoWave = 25, lfoRate = 26, lfoPitch = 27, lfoCutoff = 28, lfoAmp = 29;
  static const glide = 30, voices = 31, velocity = 32, level = 33;
}

/// Ids do sampler com nome (espelho de `sampler_param`).
abstract final class SamplerId {
  static const root = 0, attack = 1, decay = 2, sustain = 3, release = 4, level = 5, oneShot = 6, tune = 7, velocity = 8;
}

/// Ids da bateria: peça × (volume, afinação, decaimento, timbre), mais o volume geral.
abstract final class DrumId {
  static const level = 0, tune = 1, decay = 2, tone = 3, master = 48;
  static int of(int piece, int k) => piece * 4 + k;
}

// formas de onda dos osciladores, tipos de filtro e ondas do LFO, na ordem das opções da tabela
const _saw = 0.0, _square = 1.0, _tri = 2.0, _sine = 3.0;
const _bandPass = 2.0;
const _lfoSine = 0.0, _lfoTri = 1.0;

class Preset {
  final String name;

  /// Seção do menu (Baixos, Leads, Pads...).
  final String category;

  /// Só os parâmetros que diferem do padrão.
  final Map<int, double> values;

  const Preset(this.name, this.category, this.values);
}

const synthPresets = <Preset>[
  Preset('Inicial', 'Básico', {}),

  // ------------------------------------------------------------- baixos (mono, sem cauda longa)
  Preset('Baixo sub', 'Baixos', {
    SynthId.osc1Wave: _sine,
    SynthId.osc1Level: 0.9,
    // uma pitada de triângulo uma oitava acima para o baixo aparecer em caixinha de som
    SynthId.osc2Wave: _tri,
    SynthId.osc2Level: 0.12,
    SynthId.osc2Semi: 12,
    SynthId.osc2Detune: 0,
    SynthId.sub: 0.45,
    SynthId.cutoff: 1800,
    SynthId.resonance: 0,
    SynthId.filterEnv: 0,
    SynthId.keytrack: 0.3,
    SynthId.ampAttack: 0.002,
    SynthId.ampDecay: 0.4,
    SynthId.ampSustain: 0.95,
    SynthId.ampRelease: 0.09,
    SynthId.glide: 0.03,
    SynthId.voices: 1,
    SynthId.velocity: 0.25,
    SynthId.level: 0.85,
  }),
  Preset('Baixo ácido (303)', 'Baixos', {
    SynthId.osc1Wave: _saw,
    SynthId.osc1Level: 0.9,
    SynthId.osc2Level: 0,
    SynthId.cutoff: 260,
    SynthId.resonance: 0.8,
    SynthId.filterEnv: 0.6,
    SynthId.keytrack: 0.25,
    SynthId.drive: 0.45,
    SynthId.fltAttack: 0.001,
    SynthId.fltDecay: 0.25,
    SynthId.fltSustain: 0,
    SynthId.fltRelease: 0.12,
    SynthId.ampAttack: 0.001,
    SynthId.ampDecay: 0.3,
    SynthId.ampSustain: 0.85,
    SynthId.ampRelease: 0.03,
    SynthId.glide: 0.08,
    SynthId.voices: 1,
    SynthId.velocity: 0.6,
    SynthId.level: 0.6,
  }),
  Preset('Reese', 'Baixos', {
    SynthId.osc1Wave: _saw,
    SynthId.osc1Level: 0.75,
    SynthId.osc2Wave: _saw,
    SynthId.osc2Level: 0.75,
    SynthId.osc2Detune: 18,
    SynthId.unison: 3,
    SynthId.unisonDetune: 12,
    SynthId.unisonSpread: 0.7,
    SynthId.sub: 0.35,
    SynthId.cutoff: 700,
    SynthId.resonance: 0.22,
    SynthId.filterEnv: 0.08,
    SynthId.keytrack: 0.4,
    SynthId.drive: 0.35,
    // o corte respira devagar, o que dá o movimento do reese
    SynthId.lfoWave: _lfoTri,
    SynthId.lfoRate: 0.3,
    SynthId.lfoCutoff: 0.7,
    SynthId.ampAttack: 0.004,
    SynthId.ampDecay: 0.5,
    SynthId.ampSustain: 1,
    SynthId.ampRelease: 0.14,
    SynthId.glide: 0.05,
    SynthId.voices: 1,
    SynthId.velocity: 0.3,
    SynthId.level: 0.55,
  }),
  Preset('Baixo Moog', 'Baixos', {
    SynthId.osc1Wave: _saw,
    SynthId.osc1Level: 0.8,
    SynthId.osc2Wave: _square,
    SynthId.osc2Level: 0.6,
    SynthId.osc2Semi: -12,
    SynthId.osc2Detune: 4,
    SynthId.sub: 0.25,
    SynthId.cutoff: 420,
    SynthId.resonance: 0.3,
    SynthId.filterEnv: 0.45,
    SynthId.keytrack: 0.4,
    SynthId.drive: 0.25,
    SynthId.fltAttack: 0.001,
    SynthId.fltDecay: 0.35,
    SynthId.fltSustain: 0.15,
    SynthId.fltRelease: 0.15,
    SynthId.ampAttack: 0.001,
    SynthId.ampDecay: 0.5,
    SynthId.ampSustain: 0.8,
    SynthId.ampRelease: 0.06,
    SynthId.glide: 0.02,
    SynthId.voices: 1,
    SynthId.velocity: 0.5,
    SynthId.level: 0.65,
  }),

  // ------------------------------------------------------------- leads
  Preset('Lead serra', 'Leads', {
    SynthId.osc1Wave: _saw,
    SynthId.osc1Level: 0.8,
    SynthId.osc2Wave: _saw,
    SynthId.osc2Level: 0.6,
    SynthId.osc2Detune: 9,
    SynthId.unison: 5,
    SynthId.unisonDetune: 18,
    SynthId.unisonSpread: 0.7,
    SynthId.cutoff: 3600,
    SynthId.resonance: 0.25,
    SynthId.filterEnv: 0.22,
    SynthId.keytrack: 0.6,
    SynthId.fltAttack: 0.002,
    SynthId.fltDecay: 0.35,
    SynthId.fltSustain: 0.5,
    SynthId.fltRelease: 0.3,
    SynthId.ampAttack: 0.004,
    SynthId.ampDecay: 0.25,
    SynthId.ampSustain: 0.9,
    SynthId.ampRelease: 0.2,
    SynthId.lfoWave: _lfoSine,
    SynthId.lfoRate: 5.5,
    SynthId.lfoPitch: 0.08,
    SynthId.glide: 0.06,
    SynthId.voices: 1,
    SynthId.velocity: 0.5,
    SynthId.level: 0.5,
  }),
  Preset('Lead quadrado', 'Leads', {
    SynthId.osc1Wave: _square,
    SynthId.osc1Level: 0.8,
    SynthId.pulse: 0.42,
    SynthId.osc2Wave: _square,
    SynthId.osc2Level: 0.35,
    SynthId.osc2Semi: 12,
    SynthId.osc2Detune: 4,
    SynthId.cutoff: 2600,
    SynthId.resonance: 0.35,
    SynthId.filterEnv: 0.3,
    SynthId.keytrack: 0.6,
    SynthId.fltAttack: 0.002,
    SynthId.fltDecay: 0.3,
    SynthId.fltSustain: 0.45,
    SynthId.fltRelease: 0.2,
    SynthId.ampAttack: 0.003,
    SynthId.ampDecay: 0.2,
    SynthId.ampSustain: 0.9,
    SynthId.ampRelease: 0.15,
    SynthId.lfoRate: 5.8,
    SynthId.lfoPitch: 0.08,
    SynthId.glide: 0.08,
    SynthId.voices: 1,
    SynthId.velocity: 0.5,
    SynthId.level: 0.55,
  }),
  Preset('Supersaw', 'Leads', {
    SynthId.osc1Wave: _saw,
    SynthId.osc1Level: 0.8,
    SynthId.osc2Wave: _saw,
    SynthId.osc2Level: 0.7,
    SynthId.osc2Detune: -12,
    SynthId.unison: 7,
    SynthId.unisonDetune: 35,
    SynthId.unisonSpread: 1,
    SynthId.cutoff: 6000,
    SynthId.resonance: 0.1,
    SynthId.filterEnv: 0.1,
    SynthId.fltDecay: 0.6,
    SynthId.fltSustain: 0.6,
    SynthId.ampAttack: 0.005,
    SynthId.ampDecay: 0.5,
    SynthId.ampSustain: 0.85,
    SynthId.ampRelease: 0.35,
    SynthId.velocity: 0.4,
    SynthId.level: 0.4,
  }),
  Preset('Chiptune', 'Leads', {
    SynthId.osc1Wave: _square,
    SynthId.osc1Level: 0.8,
    SynthId.pulse: 0.25,
    SynthId.osc2Level: 0,
    // filtro aberto e sem envelope: o pulso cru dos consoles de 8 bits
    SynthId.cutoff: 20000,
    SynthId.resonance: 0,
    SynthId.filterEnv: 0,
    SynthId.keytrack: 0,
    SynthId.ampAttack: 0.001,
    SynthId.ampDecay: 0.1,
    SynthId.ampSustain: 0.75,
    SynthId.ampRelease: 0.03,
    SynthId.voices: 4,
    SynthId.velocity: 0.2,
    SynthId.level: 0.45,
  }),

  // ------------------------------------------------------------- pads
  Preset('Pad quente', 'Pads', {
    SynthId.osc1Wave: _saw,
    SynthId.osc1Level: 0.7,
    SynthId.osc2Wave: _saw,
    SynthId.osc2Level: 0.55,
    SynthId.osc2Detune: 11,
    SynthId.unison: 3,
    SynthId.unisonDetune: 14,
    SynthId.unisonSpread: 0.6,
    SynthId.sub: 0.15,
    SynthId.cutoff: 900,
    SynthId.resonance: 0.15,
    SynthId.filterEnv: 0.25,
    SynthId.keytrack: 0.5,
    SynthId.fltAttack: 1.2,
    SynthId.fltDecay: 2.5,
    SynthId.fltSustain: 0.5,
    SynthId.fltRelease: 1.5,
    SynthId.ampAttack: 0.9,
    SynthId.ampDecay: 1.5,
    SynthId.ampSustain: 0.85,
    SynthId.ampRelease: 1.8,
    SynthId.lfoWave: _lfoTri,
    SynthId.lfoRate: 0.35,
    SynthId.lfoCutoff: 0.35,
    SynthId.voices: 12,
    SynthId.velocity: 0.35,
    SynthId.level: 0.55,
  }),
  Preset('Pad estéreo', 'Pads', {
    SynthId.osc1Wave: _saw,
    SynthId.osc1Level: 0.6,
    SynthId.osc2Wave: _square,
    SynthId.osc2Level: 0.45,
    SynthId.pulse: 0.35,
    SynthId.osc2Semi: 12,
    SynthId.osc2Detune: -8,
    SynthId.unison: 7,
    SynthId.unisonDetune: 28,
    SynthId.unisonSpread: 1,
    SynthId.cutoff: 2200,
    SynthId.resonance: 0.1,
    SynthId.filterEnv: 0.1,
    SynthId.fltAttack: 1.5,
    SynthId.fltDecay: 3,
    SynthId.fltSustain: 0.7,
    SynthId.fltRelease: 2,
    SynthId.ampAttack: 1.4,
    SynthId.ampDecay: 2,
    SynthId.ampSustain: 0.9,
    SynthId.ampRelease: 2.6,
    SynthId.lfoWave: _lfoSine,
    SynthId.lfoRate: 0.18,
    SynthId.lfoCutoff: 0.5,
    SynthId.voices: 10,
    SynthId.velocity: 0.3,
    SynthId.level: 0.45,
  }),
  Preset('Cordas', 'Pads', {
    SynthId.osc1Wave: _saw,
    SynthId.osc1Level: 0.7,
    SynthId.osc2Wave: _saw,
    SynthId.osc2Level: 0.7,
    SynthId.osc2Detune: -9,
    SynthId.unison: 4,
    SynthId.unisonDetune: 16,
    SynthId.unisonSpread: 0.8,
    SynthId.cutoff: 3200,
    SynthId.resonance: 0.05,
    SynthId.filterEnv: 0.05,
    SynthId.keytrack: 0.6,
    SynthId.fltAttack: 0.5,
    SynthId.fltDecay: 1,
    SynthId.fltSustain: 0.8,
    SynthId.fltRelease: 1,
    SynthId.ampAttack: 0.35,
    SynthId.ampDecay: 1,
    SynthId.ampSustain: 0.9,
    SynthId.ampRelease: 0.9,
    SynthId.lfoWave: _lfoTri,
    SynthId.lfoRate: 5.5,
    SynthId.lfoPitch: 0.06,
    SynthId.voices: 12,
    SynthId.velocity: 0.5,
    SynthId.level: 0.5,
  }),
  Preset('Metais', 'Pads', {
    SynthId.osc1Wave: _saw,
    SynthId.osc1Level: 0.8,
    SynthId.osc2Wave: _saw,
    SynthId.osc2Level: 0.7,
    SynthId.osc2Detune: 6,
    SynthId.unison: 2,
    SynthId.unisonDetune: 8,
    SynthId.cutoff: 700,
    SynthId.resonance: 0.12,
    SynthId.filterEnv: 0.45,
    SynthId.keytrack: 0.5,
    SynthId.drive: 0.15,
    // o "sopro": o filtro abre um pouco depois do ataque, como num naipe de verdade
    SynthId.fltAttack: 0.07,
    SynthId.fltDecay: 0.4,
    SynthId.fltSustain: 0.55,
    SynthId.fltRelease: 0.25,
    SynthId.ampAttack: 0.04,
    SynthId.ampDecay: 0.2,
    SynthId.ampSustain: 0.9,
    SynthId.ampRelease: 0.22,
    SynthId.lfoRate: 5,
    SynthId.lfoPitch: 0.06,
    SynthId.voices: 8,
    SynthId.velocity: 0.8,
    SynthId.level: 0.6,
  }),

  // ------------------------------------------------------------- teclas
  Preset('Teclado (EP)', 'Teclas', {
    SynthId.osc1Wave: _sine,
    SynthId.osc1Level: 0.8,
    SynthId.osc2Wave: _tri,
    SynthId.osc2Level: 0.3,
    SynthId.osc2Semi: 12,
    SynthId.osc2Detune: 3,
    SynthId.cutoff: 2000,
    SynthId.resonance: 0.05,
    SynthId.filterEnv: 0.4,
    SynthId.keytrack: 0.7,
    SynthId.fltAttack: 0.001,
    SynthId.fltDecay: 0.6,
    SynthId.fltSustain: 0.15,
    SynthId.fltRelease: 0.4,
    SynthId.ampAttack: 0.002,
    SynthId.ampDecay: 1.8,
    SynthId.ampSustain: 0.25,
    SynthId.ampRelease: 0.45,
    // o tremolo do amplificador das maletas
    SynthId.lfoWave: _lfoSine,
    SynthId.lfoRate: 4.5,
    SynthId.lfoAmp: 0.18,
    SynthId.voices: 12,
    SynthId.velocity: 0.9,
    SynthId.level: 0.75,
  }),
  Preset('Órgão', 'Teclas', {
    SynthId.osc1Wave: _sine,
    SynthId.osc1Level: 0.7,
    SynthId.osc2Wave: _sine,
    SynthId.osc2Level: 0.5,
    SynthId.osc2Semi: 12,
    SynthId.osc2Detune: 0,
    SynthId.sub: 0.5,
    SynthId.cutoff: 8000,
    SynthId.resonance: 0,
    SynthId.filterEnv: 0,
    SynthId.keytrack: 0,
    SynthId.ampAttack: 0.003,
    SynthId.ampDecay: 0.1,
    SynthId.ampSustain: 1,
    SynthId.ampRelease: 0.05,
    SynthId.lfoWave: _lfoSine,
    SynthId.lfoRate: 6.5,
    SynthId.lfoPitch: 0.05,
    SynthId.lfoAmp: 0.12,
    SynthId.voices: 16,
    SynthId.velocity: 0,
    SynthId.level: 0.55,
  }),
  Preset('Sino', 'Teclas', {
    SynthId.osc1Wave: _sine,
    SynthId.osc1Level: 0.7,
    // parcial inarmônico (uma oitava e uma quinta, desafinada): o batimento metálico do sino
    SynthId.osc2Wave: _sine,
    SynthId.osc2Level: 0.5,
    SynthId.osc2Semi: 19,
    SynthId.osc2Detune: 40,
    SynthId.cutoff: 3000,
    SynthId.resonance: 0.5,
    SynthId.filterEnv: 0.3,
    SynthId.keytrack: 1,
    SynthId.fltAttack: 0.001,
    SynthId.fltDecay: 0.12,
    SynthId.fltSustain: 0,
    SynthId.fltRelease: 0.1,
    SynthId.ampAttack: 0.001,
    SynthId.ampDecay: 2.5,
    SynthId.ampSustain: 0,
    SynthId.ampRelease: 2.5,
    SynthId.voices: 16,
    SynthId.velocity: 0.7,
    SynthId.level: 0.6,
  }),

  // ------------------------------------------------------------- plucks e arpejos
  Preset('Pluck', 'Plucks e arpejos', {
    SynthId.osc1Wave: _saw,
    SynthId.osc1Level: 0.8,
    SynthId.osc2Wave: _square,
    SynthId.osc2Level: 0.35,
    SynthId.pulse: 0.3,
    SynthId.osc2Semi: 12,
    SynthId.osc2Detune: 5,
    SynthId.cutoff: 350,
    SynthId.resonance: 0.35,
    SynthId.filterEnv: 0.7,
    SynthId.keytrack: 0.6,
    SynthId.fltAttack: 0.001,
    SynthId.fltDecay: 0.22,
    SynthId.fltSustain: 0,
    SynthId.fltRelease: 0.2,
    SynthId.ampAttack: 0.001,
    SynthId.ampDecay: 0.45,
    SynthId.ampSustain: 0,
    SynthId.ampRelease: 0.3,
    SynthId.voices: 8,
    SynthId.velocity: 0.8,
    SynthId.level: 0.7,
  }),
  Preset('Arpejo', 'Plucks e arpejos', {
    SynthId.osc1Wave: _square,
    SynthId.osc1Level: 0.8,
    SynthId.pulse: 0.3,
    SynthId.osc2Wave: _saw,
    SynthId.osc2Level: 0.4,
    SynthId.osc2Semi: 12,
    SynthId.osc2Detune: 6,
    SynthId.cutoff: 1400,
    SynthId.resonance: 0.4,
    SynthId.filterEnv: 0.45,
    SynthId.keytrack: 0.6,
    SynthId.fltAttack: 0.001,
    SynthId.fltDecay: 0.16,
    SynthId.fltSustain: 0.15,
    SynthId.fltRelease: 0.12,
    SynthId.ampAttack: 0.001,
    SynthId.ampDecay: 0.18,
    SynthId.ampSustain: 0.3,
    SynthId.ampRelease: 0.12,
    SynthId.voices: 6,
    SynthId.velocity: 0.6,
    SynthId.level: 0.65,
  }),
  Preset('Marimba', 'Plucks e arpejos', {
    SynthId.osc1Wave: _tri,
    SynthId.osc1Level: 0.8,
    SynthId.osc2Wave: _sine,
    SynthId.osc2Level: 0.15,
    SynthId.osc2Semi: 24,
    SynthId.osc2Detune: 0,
    SynthId.cutoff: 3000,
    SynthId.resonance: 0,
    SynthId.filterEnv: 0.2,
    SynthId.keytrack: 0.8,
    SynthId.fltAttack: 0.001,
    SynthId.fltDecay: 0.1,
    SynthId.fltSustain: 0,
    SynthId.ampAttack: 0.001,
    SynthId.ampDecay: 0.35,
    SynthId.ampSustain: 0,
    SynthId.ampRelease: 0.3,
    SynthId.voices: 12,
    SynthId.velocity: 0.8,
    SynthId.level: 0.75,
  }),

  // ------------------------------------------------------------- efeitos
  Preset('Wobble', 'Efeitos', {
    SynthId.osc1Wave: _saw,
    SynthId.osc1Level: 0.8,
    SynthId.osc2Wave: _square,
    SynthId.osc2Level: 0.6,
    SynthId.osc2Semi: -12,
    SynthId.osc2Detune: 0,
    SynthId.sub: 0.4,
    SynthId.cutoff: 300,
    SynthId.resonance: 0.5,
    SynthId.filterEnv: 0,
    SynthId.drive: 0.4,
    SynthId.lfoWave: _lfoSine,
    SynthId.lfoRate: 3,
    SynthId.lfoCutoff: 3,
    SynthId.ampAttack: 0.003,
    SynthId.ampSustain: 1,
    SynthId.ampRelease: 0.1,
    SynthId.voices: 1,
    SynthId.velocity: 0.3,
    SynthId.level: 0.55,
  }),
  Preset('Vento', 'Efeitos', {
    SynthId.osc1Level: 0,
    SynthId.osc2Level: 0,
    SynthId.noise: 0.9,
    SynthId.filterType: _bandPass,
    SynthId.cutoff: 900,
    SynthId.resonance: 0.6,
    SynthId.filterEnv: 0,
    SynthId.keytrack: 0.8,
    SynthId.lfoWave: _lfoTri,
    SynthId.lfoRate: 0.15,
    SynthId.lfoCutoff: 2,
    SynthId.ampAttack: 1.5,
    SynthId.ampDecay: 1,
    SynthId.ampSustain: 1,
    SynthId.ampRelease: 2.5,
    SynthId.voices: 4,
    SynthId.velocity: 0.2,
    SynthId.level: 0.6,
  }),
  Preset('Subida (riser)', 'Efeitos', {
    SynthId.osc1Wave: _saw,
    SynthId.osc1Level: 0.4,
    SynthId.osc2Level: 0,
    SynthId.noise: 0.6,
    SynthId.unison: 5,
    SynthId.unisonDetune: 30,
    SynthId.unisonSpread: 1,
    SynthId.cutoff: 200,
    SynthId.resonance: 0.45,
    // o filtro leva 8 s para abrir: segure a nota na virada
    SynthId.filterEnv: 0.8,
    SynthId.fltAttack: 8,
    SynthId.fltDecay: 0.5,
    SynthId.fltSustain: 1,
    SynthId.fltRelease: 1,
    SynthId.ampAttack: 4,
    SynthId.ampSustain: 1,
    SynthId.ampRelease: 1,
    SynthId.voices: 4,
    SynthId.velocity: 0,
    SynthId.level: 0.5,
  }),
];

/// Um ajuste de peça da bateria (os padrões são os da tabela).
typedef _Piece = ({double level, double tune, double decay, double tone});

_Piece _pc({double level = 1, double tune = 0, double decay = 1, double tone = 0.5}) => (level: level, tune: tune, decay: decay, tone: tone);

/// Monta os valores de um kit a partir das peças mexidas (índice de `drumPieces`).
Map<int, double> _kit(Map<int, _Piece> pieces, {double master = 0.8}) => {
  for (final e in pieces.entries) ...{
    DrumId.of(e.key, DrumId.level): e.value.level,
    DrumId.of(e.key, DrumId.tune): e.value.tune,
    DrumId.of(e.key, DrumId.decay): e.value.decay,
    DrumId.of(e.key, DrumId.tone): e.value.tone,
  },
  DrumId.master: master,
};

// peças, na ordem de `drumPieces`
const _kick = 0, _snare = 1, _clap = 2, _closedHat = 3, _openHat = 4, _lowTom = 5, _midTom = 6, _highTom = 7, _crash = 8, _ride = 9, _rim = 10, _cowbell = 11;

final drumKits = <Preset>[
  const Preset('Padrão', 'Kits', {}),
  Preset(
    '808',
    'Kits',
    _kit({
      // bumbo grave e comprido, pouco clique: o boom da 808
      _kick: _pc(level: 1.1, tune: -3, decay: 2.6, tone: 0.25),
      _snare: _pc(level: 0.9, decay: 0.9, tone: 0.35),
      _clap: _pc(decay: 1.3),
      _closedHat: _pc(level: 0.8, decay: 0.6, tone: 0.55),
      _openHat: _pc(level: 0.75, decay: 1.3, tone: 0.55),
      _lowTom: _pc(tune: -3, decay: 1.8, tone: 0.2),
      _midTom: _pc(tune: -1, decay: 1.8, tone: 0.2),
      _highTom: _pc(tune: 2, decay: 1.8, tone: 0.2),
      _crash: _pc(level: 0.7, decay: 0.8, tone: 0.45),
      _ride: _pc(level: 0.6, decay: 0.9, tone: 0.4),
      _rim: _pc(level: 0.9, decay: 0.8, tone: 0.6),
      _cowbell: _pc(),
    }),
  ),
  Preset(
    '909',
    'Kits',
    _kit({
      // bumbo curto com clique na frente, caixa com muito esteira, pratos brilhantes
      _kick: _pc(level: 1.1, tune: 1, decay: 0.8, tone: 0.75),
      _snare: _pc(decay: 0.85, tone: 0.75),
      _clap: _pc(level: 0.95, decay: 1.1, tone: 0.6),
      _closedHat: _pc(decay: 0.45, tone: 0.85),
      _openHat: _pc(decay: 0.9, tone: 0.85),
      _lowTom: _pc(tune: -1, decay: 0.9, tone: 0.6),
      _midTom: _pc(tune: 1, decay: 0.9, tone: 0.6),
      _highTom: _pc(tune: 3, decay: 0.9, tone: 0.6),
      _crash: _pc(decay: 1.4, tone: 0.75),
      _ride: _pc(decay: 1.5, tone: 0.75),
      _rim: _pc(decay: 0.6, tone: 0.7),
      _cowbell: _pc(level: 0.6),
    }),
  ),
  Preset(
    'Acústico eletrônico',
    'Kits',
    _kit({
      _kick: _pc(decay: 0.55, tone: 0.55),
      _snare: _pc(decay: 1.25, tone: 0.6),
      _clap: _pc(level: 0.55),
      _closedHat: _pc(decay: 0.8, tone: 0.6),
      _openHat: _pc(decay: 1.2, tone: 0.6),
      // tons mais abertos entre si, como um kit afinado em intervalos
      _lowTom: _pc(tune: -4, decay: 1.35, tone: 0.45),
      _midTom: _pc(tune: -1, decay: 1.35, tone: 0.45),
      _highTom: _pc(tune: 2, decay: 1.35, tone: 0.45),
      _crash: _pc(decay: 2, tone: 0.6),
      _ride: _pc(decay: 1.7),
      _rim: _pc(level: 0.85),
      _cowbell: _pc(level: 0.5),
    }, master: 0.85),
  ),
  Preset(
    'Lo-fi',
    'Kits',
    _kit({
      // tudo mais escuro e mais curto, como sample de fita
      _kick: _pc(level: 1.15, tune: -1, decay: 0.7, tone: 0.15),
      _snare: _pc(level: 0.95, tune: -1, decay: 0.75, tone: 0.2),
      _clap: _pc(level: 0.8, decay: 0.9, tone: 0.25),
      _closedHat: _pc(level: 0.7, decay: 0.55, tone: 0.2),
      _openHat: _pc(level: 0.6, decay: 0.8, tone: 0.25),
      _lowTom: _pc(decay: 1, tone: 0.15),
      _midTom: _pc(decay: 1, tone: 0.15),
      _highTom: _pc(decay: 1, tone: 0.15),
      _crash: _pc(level: 0.55, decay: 0.7, tone: 0.2),
      _ride: _pc(level: 0.5, decay: 0.7, tone: 0.2),
      _rim: _pc(tone: 0.3),
      _cowbell: _pc(level: 0.6, tone: 0.25),
    }, master: 0.85),
  ),
  Preset(
    'Trap',
    'Kits',
    _kit({
      // o bumbo vira o baixo: afinado para baixo, decaimento máximo
      _kick: _pc(level: 1.2, tune: -5, decay: 4, tone: 0.35),
      _snare: _pc(tune: 2, decay: 0.7, tone: 0.6),
      _clap: _pc(level: 1.1, tone: 0.55),
      _closedHat: _pc(level: 0.75, decay: 0.35, tone: 0.7),
      _openHat: _pc(level: 0.7, decay: 0.7, tone: 0.7),
      _lowTom: _pc(tune: -5, decay: 2.2, tone: 0.2),
      _midTom: _pc(tune: -2, decay: 2, tone: 0.2),
      _highTom: _pc(tune: 1, decay: 1.8, tone: 0.2),
      _crash: _pc(level: 0.7, decay: 1.2, tone: 0.6),
      _ride: _pc(level: 0.6, tone: 0.6),
      _rim: _pc(tone: 0.7),
      _cowbell: _pc(level: 0.7),
    }),
  ),
  Preset(
    'Techno',
    'Kits',
    _kit({
      _kick: _pc(level: 1.15, tune: -2, decay: 1.2, tone: 0.6),
      _snare: _pc(level: 0.8, decay: 0.8, tone: 0.65),
      _clap: _pc(decay: 1.2),
      _closedHat: _pc(decay: 0.4, tone: 0.75),
      _openHat: _pc(decay: 0.8, tone: 0.8),
      _lowTom: _pc(tune: -2, decay: 1.1, tone: 0.5),
      _midTom: _pc(decay: 1.1, tone: 0.5),
      _highTom: _pc(tune: 3, decay: 1.1, tone: 0.5),
      _crash: _pc(level: 0.8, decay: 1.3, tone: 0.7),
      _ride: _pc(level: 0.8, decay: 1.3, tone: 0.8),
      _rim: _pc(decay: 0.7, tone: 0.65),
      _cowbell: _pc(level: 0.55),
    }),
  ),
];

/// Envelopes do sampler. Nota base e afinação são do áudio escolhido: nenhum preset mexe nelas.
const samplerPresets = <Preset>[
  Preset('Padrão', 'Sampler', {}),
  Preset('Instrumento', 'Sampler', {SamplerId.attack: 0.003, SamplerId.decay: 0.5, SamplerId.sustain: 1, SamplerId.release: 0.35, SamplerId.velocity: 0.8}),
  Preset('Percussão (até o fim)', 'Sampler', {SamplerId.oneShot: 1, SamplerId.attack: 0.0005, SamplerId.release: 0.05, SamplerId.velocity: 0.8}),
  Preset('Pad lento', 'Sampler', {SamplerId.attack: 0.8, SamplerId.decay: 1, SamplerId.sustain: 0.9, SamplerId.release: 1.8, SamplerId.velocity: 0.3}),
  Preset('Pluck', 'Sampler', {SamplerId.attack: 0.001, SamplerId.decay: 0.35, SamplerId.sustain: 0, SamplerId.release: 0.25, SamplerId.velocity: 0.8}),
];

/// Ids que pertencem ao áudio escolhido, não ao timbre: um preset não os troca.
const _samplerKeeps = {SamplerId.root, SamplerId.tune};

List<Preset> presetsFor(TrackKind kind) => switch (kind) {
  TrackKind.audio => const [],
  TrackKind.synth => synthPresets,
  TrackKind.drums => drumKits,
  TrackKind.sampler => samplerPresets,
};

/// Os parâmetros completos que o preset põe na faixa: o padrão do tipo com o preset por cima
/// (no sampler, nota base e afinação continuam as da faixa).
Map<int, double> presetParams(Preset p, DawTrack t) => {
  ...defaultParams(t.kind),
  ...p.values,
  if (t.kind == TrackKind.sampler)
    for (final id in _samplerKeeps) id: t.param(id),
};

/// O preset cujos valores batem com os da faixa agora, se algum.
Preset? matchingPreset(DawTrack t) {
  final skip = t.kind == TrackKind.sampler ? _samplerKeeps : const <int>{};
  for (final p in presetsFor(t.kind)) {
    var same = true;
    for (final spec in t.kind.params) {
      if (skip.contains(spec.id)) continue;
      final want = p.values[spec.id] ?? spec.def;
      if ((t.param(spec.id) - want).abs() > 1e-6 * math.max(1, want.abs())) {
        same = false;
        break;
      }
    }
    if (same) return p;
  }
  return null;
}
