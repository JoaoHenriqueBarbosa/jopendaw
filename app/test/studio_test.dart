// A tela do projeto montada inteira (transporte, arranjo e painel de baixo) com o controlador de
// verdade e o motor stub: cada painel com cada tipo de faixa, no computador e no celular, e o
// encadeamento das teclas (teclado musical → editor → atalhos).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jopendaw_app/audio/engine.dart';
import 'package:jopendaw_app/daw/controller.dart';
import 'package:jopendaw_app/daw/effects.dart';
import 'package:jopendaw_app/daw/instruments.dart';
import 'package:jopendaw_app/daw/model.dart';
import 'package:jopendaw_app/models/project.dart';
import 'package:jopendaw_app/screens/project_screen.dart';
import 'package:jopendaw_app/widgets/theme.dart';

final engine = AudioEngine.instance;

DawController studio() {
  final c = DawController(
    Project.fromJson({
      'id': 'p',
      'name': 'Teste',
      'bpm': 120,
      'beats_per_bar': 4,
      'beat_unit': 4,
      'sample_rate': 48000,
      'created_at': '2026-01-01T00:00:00Z',
      'updated_at': '2026-01-01T00:00:00Z',
    }),
  );
  c.doc = DawDoc(
    bpm: 120,
    beatsPerBar: 4,
    tracks: [
      DawTrack(id: 'a', name: 'Áudio 1', color: 0),
      DawTrack(
        id: 's',
        name: 'Sintetizador 1',
        color: 1,
        kind: TrackKind.synth,
        midi: [
          MidiClip(
            id: 'm1',
            name: 'Riff',
            start: 0,
            length: 4,
            notes: [MidiNote(pitch: 60, start: 0, length: 1), MidiNote(pitch: 64, start: 1, length: 1, velocity: 0.5)],
          ),
        ],
      ),
      DawTrack(
        id: 'd',
        name: 'Bateria 1',
        color: 2,
        kind: TrackKind.drums,
        midi: [
          MidiClip(id: 'm2', name: '', start: 4, length: 4, notes: [MidiNote(pitch: 36, start: 0, length: 0.25)]),
        ],
      ),
      DawTrack(id: 'p', name: 'Sampler 1', color: 3, kind: TrackKind.sampler),
    ],
  );
  c.ready = true;
  return c;
}

Future<void> mount(WidgetTester t, DawController c, Size size) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      theme: buildTheme(),
      home: Scaffold(body: DawStudio(c: c)),
    ),
  );
  await t.pump();
}

/// Deixa passar o salvamento adiado do controlador (senão o teste acaba com um Timer pendente).
Future<void> flushSave(WidgetTester t) => t.pump(const Duration(seconds: 1));

List<List<Object>> sent(String name) => [
  for (final c in engine.log!)
    if (c.first == name) c,
];

void main() {
  setUp(() => engine.log = []);

  for (final (label, size) in [('computador', const Size(1400, 900)), ('celular', const Size(400, 820))]) {
    testWidgets('$label: todo painel com todo tipo de faixa monta sem erro', (t) async {
      final c = studio();
      await mount(t, c, size);
      for (final dock in [Dock.mixer, Dock.editor, Dock.instrument]) {
        for (var i = 0; i < c.doc.tracks.length; i++) {
          c.selectTrack(i);
          if (dock == Dock.editor && c.doc.tracks[i].midi.isNotEmpty) {
            c.openPianoRoll(c.doc.tracks[i].midi.first.id);
          } else {
            c.setDock(dock);
          }
          await t.pump();
          expect(t.takeException(), isNull, reason: '$dock na faixa $i');
        }
      }
      c.setDock(Dock.none);
      await t.pump();
      expect(t.takeException(), isNull);
      await flushSave(t);
    });
  }

  testWidgets('teclas: teclado musical antes dos atalhos, Ctrl+K liga, E abre o editor no clipe', (t) async {
    final c = studio();
    await mount(t, c, const Size(1400, 900));

    // S sem o teclado ligado é o atalho de cortar; com Ctrl+K ligado, vira nota
    c.selectTrack(1);
    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.keyK);
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(c.keyboardOn, isTrue);
    await t.sendKeyDownEvent(LogicalKeyboardKey.keyA, physicalKey: PhysicalKeyboardKey.keyA);
    expect(sent('live_on'), [
      ['live_on', 1, 60, c.keyboardVelocity],
    ]);
    await t.sendKeyUpEvent(LogicalKeyboardKey.keyA, physicalKey: PhysicalKeyboardKey.keyA);
    expect(sent('live_off'), [
      ['live_off', 1, 60],
    ]);
    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.keyK);
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(c.keyboardOn, isFalse);

    // E abre o editor no clipe de notas selecionado; Esc fecha
    c.selectClip('m1');
    await t.sendKeyEvent(LogicalKeyboardKey.keyE);
    await t.pump();
    expect(c.dock, Dock.editor);
    expect(c.editingClip, 'm1');
    expect(c.editorKeyHandler, isNotNull);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pump();
    expect(c.dock, Dock.none);
    expect(c.editorKeyHandler, isNull);

    // Delete com o editor fechado apaga o clipe selecionado do arranjo; desfazer traz de volta
    await t.sendKeyEvent(LogicalKeyboardKey.delete);
    await t.pump();
    expect(c.findMidiClip('m1'), isNull);
    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await t.pump();
    expect(c.findMidiClip('m1'), isNotNull);
    expect(t.takeException(), isNull);
    await flushSave(t);
  });

  testWidgets('cortar no cursor divide o clipe de notas pelo controlador (a nota que cruza vira duas)', (t) async {
    final c = studio();
    await mount(t, c, const Size(1400, 900));
    c.selectClip('m1');
    c.seek(1.5);
    await t.sendKeyEvent(LogicalKeyboardKey.keyS);
    await t.pump();
    final clips = c.doc.tracks[1].midi;
    expect(clips.length, 2);
    final right = clips.firstWhere((m) => m.id != 'm1');
    expect(right.start, 1.5);
    expect(right.notes.single.pitch, 64);
    expect(right.notes.single.length, 0.5);
    expect(c.findMidiClip('m1')!.$2.notes.map((n) => (n.pitch, n.length)), [(60, 1.0), (64, 0.5)]);
    await flushSave(t);
  });

  test('toda chamada que o controlador manda existe no motor wasm, com o número certo de argumentos', () async {
    final src = File('../engine/wasm/src/lib.rs').readAsStringSync();
    final exports = <String, int>{
      for (final m in RegExp(r'pub (?:unsafe )?extern "C" fn (\w+)\(([^)]*)\)').allMatches(src))
        m.group(1)!: m.group(2)!.trim().isEmpty ? 0 : m.group(2)!.split(',').length,
    };
    expect(exports, contains('note_add'));

    final c = studio();
    c.doc.tracks[3].sample = 'x';
    c.mutate((_) {});
    c.setParam(1, 13, 800);
    c.applyPreset(2, const {48: 1.0});
    c.noteOn(60, track: 1);
    c.noteOff(60, track: 1);
    // fase 3: efeitos (faixa e master), barramento, envio, saída, automação e observação
    final bus = c.addBusTrack();
    final comp = c.addEffect(1, EffectKind.compressor);
    c.setEffectParam(1, comp.id, 0, -24);
    c.setEffectParam(1, comp.id, 10, 2);
    final rev = c.addEffect(4, EffectKind.reverb);
    c.setEffectBypass(4, rev.id, true);
    c.addEffect(-1, EffectKind.limiter);
    expect(c.setSend(1, bus.id), isTrue);
    expect(c.setSend(1, bus.id, level: 0.3), isTrue);
    expect(c.setOutput(2, bus.id), isTrue);
    final lanes = [
      c.addLane(1, AutoTarget(AutoKind.effect, ref: comp.id, param: 0)),
      c.addLane(1, AutoTarget(AutoKind.send, ref: bus.id)),
      c.addLane(-1, const AutoTarget(AutoKind.volume)),
    ];
    c.mutate((_) {
      for (final l in lanes) {
        l.points.addAll([AutoPoint(beat: 0, value: 0.2), AutoPoint(beat: 4, value: 0.8, curve: 0.5)]);
      }
    });
    c.watchEffect(1, comp.id);
    c.watchAnalyzer(-1);
    c.watchAnalyzer(null);
    c.seek(2);
    await c.togglePlay();
    await c.stop();
    c.removeTrack(0);
    c.dispose();

    expect(engine.log, isNotEmpty);
    for (final call in engine.log!) {
      final name = call.first as String;
      expect(exports.keys, contains(name), reason: 'o motor não exporta $name');
      expect(call.length - 1, exports[name], reason: 'argumentos de $name: $call');
    }
    final names = {for (final call in engine.log!) call.first};
    expect(names, containsAll(['track_kind', 'param', 'instrument_sample', 'notes_clear', 'note_add', 'live_on', 'live_off', 'panic']));
    expect(
      names,
      containsAll([
        'fx_count',
        'fx_set',
        'fx_param',
        'fx_bypass',
        'sends_count',
        'send_set',
        'track_output',
        'auto_clear',
        'auto_lane',
        'auto_point',
        'watch_fx',
        'watch_analyzer',
      ]),
    );
    // o motor também exporta o que o worklet lê a cada estado
    expect(exports.keys, containsAll(['fx_meter', 'analyzer', 'peaks', 'beat', 'playing']));
  });
}
