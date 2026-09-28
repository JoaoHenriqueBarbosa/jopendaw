/// Modelos de projeto: o documento com que um projeto novo começa. Um projeto vazio desanima; um
/// que já toca mostra o que o DAW faz e serve de ponto de partida.
///
/// As posições são em batidas (valem em qualquer andamento); os timbres vêm dos presets do app.
library;

import 'package:flutter/material.dart';

import 'effects.dart';
import 'fx_presets.dart';
import 'instruments.dart';
import 'model.dart';
import 'presets.dart';

enum ProjectTemplate {
  empty('Vazio', 'Uma faixa de áudio, pronta para importar ou gravar', Icons.crop_square),
  beat('Batida eletrônica', 'Bateria 808, baixo, pad e um reverb em barramento, tocando em loop', Icons.graphic_eq),
  band('Gravação de banda', 'Faixas de voz, violão, baixo e bateria, com metrônomo, contagem e reverb', Icons.mic_none);

  final String label, description;
  final IconData icon;
  const ProjectTemplate(this.label, this.description, this.icon);

  static ProjectTemplate parse(String? s) => values.firstWhere((t) => t.name == s, orElse: () => empty);

  /// O documento do modelo no andamento e compasso do projeto.
  DawDoc build({required double bpm, required int beatsPerBar}) => switch (this) {
    empty => DawDoc(
      bpm: bpm,
      beatsPerBar: beatsPerBar,
      tracks: [DawTrack(id: newId(), name: 'Áudio 1', color: 0)],
      loopEnd: beatsPerBar * 4.0,
    ),
    beat => _beat(bpm, beatsPerBar),
    band => _band(bpm, beatsPerBar),
  };
}

Map<int, double> _synth(String preset) => {...defaultParams(TrackKind.synth), ...synthPresets.firstWhere((p) => p.name == preset).values};

Map<int, double> _kit(String name) => {...defaultParams(TrackKind.drums), ...drumKits.firstWhere((p) => p.name == name).values};

/// Reverb de barramento: 100% molhado (o seco vem das faixas), no timbre do preset.
EffectSlot _returnReverb(String preset) {
  final values = effectPresetsFor(EffectKind.reverb).firstWhere((p) => p.name == preset).values;
  return EffectSlot(id: newId(), kind: EffectKind.reverb, params: {...defaultEffectParams(EffectKind.reverb), ...values, 0: 1.0});
}

MidiNote _n(int pitch, double start, double length, [double velocity = 0.8]) => MidiNote(pitch: pitch, start: start, length: length, velocity: velocity);

DawDoc _beat(double bpm, int beatsPerBar) {
  final bars = 4;
  final len = (beatsPerBar * bars).toDouble();
  final reverb = DawTrack(id: newId(), name: 'Reverb', color: 4, kind: TrackKind.bus, effects: [_returnReverb('Sala')]);

  // bateria: bumbo em todos os tempos, palmas no 2 e 4, chimbal fechado nas semicolcheias (com
  // acento nos tempos) e aberto nos contratempos
  final drums = <MidiNote>[];
  for (var b = 0; b < len; b++) {
    drums.add(_n(36, b.toDouble(), 0.25, 0.95));
    if (b % 2 == 1) drums.add(_n(39, b.toDouble(), 0.25, 0.85));
    drums.add(_n(46, b + 0.5, 0.25, 0.6));
    for (final s in [0.0, 0.25, 0.75]) {
      drums.add(_n(42, b + s, 0.125, s == 0 ? 0.7 : 0.45));
    }
  }

  // lá menor, F, C, G: um compasso cada
  const roots = [45, 41, 48, 43]; // A2 F2 C3 G2
  const chords = [
    [57, 60, 64], // Am
    [53, 57, 60], // F
    [55, 60, 64], // C
    [55, 59, 62], // G
  ];
  final bass = <MidiNote>[];
  final pad = <MidiNote>[];
  for (var bar = 0; bar < bars; bar++) {
    final at = (bar * beatsPerBar).toDouble();
    final root = roots[bar % roots.length];
    // baixo em colcheias, nos contratempos (o bumbo fica com os tempos)
    for (var b = 0; b < beatsPerBar; b++) {
      bass.add(_n(root, at + b + 0.5, 0.4, 0.85));
    }
    for (final p in chords[bar % chords.length]) {
      pad.add(_n(p, at, beatsPerBar - 0.05, 0.6));
    }
  }

  return DawDoc(
    bpm: bpm,
    beatsPerBar: beatsPerBar,
    loopOn: true,
    loopStart: 0,
    loopEnd: len,
    tracks: [
      DawTrack(
        id: newId(),
        name: 'Bateria',
        color: 2,
        kind: TrackKind.drums,
        params: _kit('808'),
        sends: [Send(target: reverb.id, level: 0.12)],
        midi: [MidiClip(id: newId(), name: 'Batida', start: 0, length: len, notes: drums)],
      ),
      DawTrack(
        id: newId(),
        name: 'Baixo',
        color: 1,
        kind: TrackKind.synth,
        gain: 0.8,
        params: _synth('Baixo sub'),
        midi: [MidiClip(id: newId(), name: 'Baixo', start: 0, length: len, notes: bass)],
      ),
      DawTrack(
        id: newId(),
        name: 'Pad',
        color: 3,
        kind: TrackKind.synth,
        gain: 0.55,
        params: _synth('Pad quente'),
        sends: [Send(target: reverb.id, level: 0.45)],
        midi: [MidiClip(id: newId(), name: 'Acordes', start: 0, length: len, notes: pad)],
      ),
      reverb,
    ],
  );
}

DawDoc _band(double bpm, int beatsPerBar) {
  final reverb = DawTrack(id: newId(), name: 'Reverb', color: 4, kind: TrackKind.bus, effects: [_returnReverb('Placa')]);
  DawTrack audio(String name, int color, double send) => DawTrack(
    id: newId(),
    name: name,
    color: color,
    sends: [Send(target: reverb.id, level: send)],
  );
  return DawDoc(
    bpm: bpm,
    beatsPerBar: beatsPerBar,
    metronome: true,
    countIn: true,
    loopEnd: beatsPerBar * 4.0,
    tracks: [
      audio('Voz', 0, 0.3),
      audio('Violão', 1, 0.2),
      audio('Baixo', 5, 0),
      DawTrack(
        id: newId(),
        name: 'Bateria',
        color: 2,
        kind: TrackKind.drums,
        params: _kit('Acústico eletrônico'),
        sends: [Send(target: reverb.id, level: 0.1)],
      ),
      reverb,
    ],
  );
}
