import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jopendaw_app/audio/engine.dart';
import 'package:jopendaw_app/daw/controller.dart';
import 'package:jopendaw_app/daw/instruments.dart';
import 'package:jopendaw_app/daw/model.dart';
import 'package:jopendaw_app/models/project.dart';

final engine = AudioEngine.instance;

/// Controlador com um documento de uma faixa de áudio, sem abrir o motor (o stub guarda as
/// chamadas em `engine.log`).
DawController newController() {
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
    tracks: [DawTrack(id: 'a', name: 'Áudio 1', color: 0)],
  );
  c.ready = true;
  return c;
}

List<List<Object>> sent(String name) => [
  for (final c in engine.log!)
    if (c.first == name) c,
];

KeyEvent down(PhysicalKeyboardKey k) => KeyDownEvent(physicalKey: k, logicalKey: LogicalKeyboardKey.keyA, timeStamp: Duration.zero);
KeyEvent repeat(PhysicalKeyboardKey k) => KeyRepeatEvent(physicalKey: k, logicalKey: LogicalKeyboardKey.keyA, timeStamp: Duration.zero);
KeyEvent up(PhysicalKeyboardKey k) => KeyUpEvent(physicalKey: k, logicalKey: LogicalKeyboardKey.keyA, timeStamp: Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    engine.log = [];
    engine.onMidi = null;
    engine.onMidiInputs = null;
  });

  group('faixas e clipes MIDI', () {
    test('faixa de instrumento ganha nome pelo tipo, parâmetros padrão e fica selecionada', () {
      final c = newController();
      c.addInstrumentTrack(TrackKind.synth);
      c.addInstrumentTrack(TrackKind.synth);
      c.addInstrumentTrack(TrackKind.drums);
      expect(c.doc.tracks.map((t) => t.name), ['Áudio 1', 'Sintetizador 1', 'Sintetizador 2', 'Bateria 1']);
      expect(c.selectedTrack, 3);
      expect(c.doc.tracks[1].params, defaultParams(TrackKind.synth));
      expect(c.doc.tracks[1].color, isNot(c.doc.tracks[2].color));
    });

    test('clipe MIDI novo: um compasso, nome da faixa, selecionado; só em faixa de instrumento', () {
      final c = newController();
      c.addInstrumentTrack(TrackKind.synth);
      final clip = c.createMidiClip(1, 8);
      expect(clip.length, 4);
      expect(clip.name, 'Sintetizador 1');
      expect(c.selectedClip, clip.id);
      expect(c.midiSelection?.$2, same(clip));
      expect(c.findMidiClip(clip.id)?.$1, same(c.doc.tracks[1]));
      expect(() => c.createMidiClip(0, 0), throwsArgumentError);
    });

    test('mover clipe respeita o tipo da faixa', () {
      final c = newController();
      c.addInstrumentTrack(TrackKind.synth);
      c.addInstrumentTrack(TrackKind.sampler);
      final clip = c.createMidiClip(1, 0);
      c.moveClipToTrack(clip.id, 0);
      expect(c.doc.tracks[1].midi, contains(clip));
      c.moveClipToTrack(clip.id, 2);
      expect(c.doc.tracks[2].midi, contains(clip));
      expect(c.doc.tracks[1].midi, isEmpty);
      expect(c.selectedTrack, 2);
    });

    test('duplicar e apagar valem para clipe MIDI', () {
      final c = newController();
      c.addInstrumentTrack(TrackKind.synth);
      final clip = c.createMidiClip(1, 0);
      c.edit((_) => clip.notes.add(MidiNote(pitch: 60, start: 1, length: 1)));
      c.duplicateSelected();
      final midi = c.doc.tracks[1].midi;
      expect(midi, hasLength(2));
      expect(midi[1].start, 4);
      expect(midi[1].notes.single.pitch, 60);
      expect(c.selectedClip, midi[1].id);
      c.deleteSelected();
      expect(midi, [clip]);
      expect(c.selectedClip, isNull);
    });

    test('cortar no cursor divide o clipe MIDI e a nota que cruza', () {
      final c = newController();
      c.addInstrumentTrack(TrackKind.synth);
      final clip = c.createMidiClip(1, 0, length: 8);
      c.edit((_) => clip.notes.addAll([MidiNote(pitch: 60, start: 3, length: 2), MidiNote(pitch: 62, start: 6, length: 1)]));
      c.selectClip(null);
      c.selectTrack(1);
      c.beat.value = 4;
      c.splitAtPlayhead();
      final midi = c.doc.tracks[1].midi;
      expect(midi, hasLength(2));
      expect(midi[0].length, 4);
      expect([for (final n in midi[0].notes) (n.pitch, n.start, n.length)], [(60, 3.0, 1.0)]);
      expect(midi[1].start, 4);
      expect([for (final n in midi[1].notes) (n.pitch, n.start, n.length)], [(60, 0.0, 1.0), (62, 2.0, 1.0)]);
      c.undo();
      expect(c.doc.tracks[1].midi.single.notes, hasLength(2));
    });

    test('o editor fecha quando o clipe aberto some (apagar ou desfazer)', () {
      final c = newController();
      c.addInstrumentTrack(TrackKind.synth);
      final clip = c.createMidiClip(1, 0);
      c.openPianoRoll(clip.id);
      expect(c.dock, Dock.editor);
      expect(c.editing?.$2, same(clip));
      c.deleteSelected();
      expect(c.editingClip, isNull);
      expect(c.dock, Dock.none);
      c.undo();
      c.openPianoRoll(clip.id);
      c.undo(); // desfaz a criação do clipe
      expect(c.editingClip, isNull);
      expect(c.dock, Dock.none);
    });

    test('mixer e editor dividem o painel de baixo', () {
      final c = newController();
      c.toggleMixer();
      expect(c.mixerOpen, isTrue);
      c.addInstrumentTrack(TrackKind.synth);
      final clip = c.createMidiClip(1, 0);
      c.setDock(Dock.editor);
      expect(c.mixerOpen, isFalse);
      expect(c.editingClip, clip.id);
      c.toggleMixer();
      c.toggleMixer();
      expect(c.dock, Dock.none);
    });
  });

  group('motor', () {
    test('o sync manda tipo, parâmetros e notas achatadas', () {
      final c = newController();
      c.addInstrumentTrack(TrackKind.synth);
      final clip = c.createMidiClip(1, 4);
      c.edit((_) => clip.notes.add(MidiNote(pitch: 64, start: 1, length: 0.5, velocity: 0.5)));
      expect(
        sent('track_kind'),
        containsAll([
          ['track_kind', 0, 0],
          ['track_kind', 1, 1],
        ]),
      );
      expect(sent('param'), contains(equals(['param', 1, synthParams[13].id, 2400.0])));
      expect(sent('notes_clear'), isNotEmpty);
      expect(sent('note_add').last, [
        'note_add', 1, 5.0, 0.5, 64, 0.5, //
      ]);
    });

    test('o sync só reenvia instrumento e notas quando mudam', () {
      final c = newController();
      c.addInstrumentTrack(TrackKind.synth);
      engine.log = [];
      c.toggleLoop();
      expect(sent('loop_set'), hasLength(1));
      expect(sent('param'), isEmpty);
      expect(sent('track_kind'), isEmpty);
      expect(sent('notes_clear'), isEmpty);
      // tirar uma faixa muda os índices: tudo volta a ir
      c.removeTrack(0);
      expect(sent('track_kind'), [
        ['track_kind', 0, 1],
      ]);
      expect(sent('param'), hasLength(synthParams.length));
      expect(sent('notes_clear'), hasLength(1));
    });

    test('setParam vai direto ao motor, limitado à faixa; undoable entra no histórico', () {
      final c = newController();
      c.addInstrumentTrack(TrackKind.synth);
      engine.log = [];
      c.setParam(1, 13, 50000);
      expect(engine.log, [
        ['param', 1, 13, 20000.0],
      ]);
      expect(c.doc.tracks[1].param(13), 20000);
      engine.log = [];
      c.setParam(1, 9, 3.4, undoable: true); // uníssono é inteiro
      expect(engine.log, [
        ['param', 1, 9, 3.0],
      ]);
      engine.log = [];
      c.undo();
      expect(c.doc.tracks[1].param(9), 1);
      expect(sent('param'), [
        ['param', 1, 9, 1.0],
      ]);
      c.setParam(0, 13, 1000); // faixa de áudio
      c.setParam(1, 999, 1); // id desconhecido
      expect(c.doc.tracks[0].params, isEmpty);
    });

    test('preset completa com os padrões; sampler recebe o id do áudio', () {
      final c = newController();
      c.addInstrumentTrack(TrackKind.sampler);
      c.setParam(1, 0, 48);
      c.applyPreset(1, {5: 1.2});
      expect(c.doc.tracks[1].param(0), 60);
      expect(c.doc.tracks[1].param(5), 1.2);
      c.doc.samples['h'] = const SampleInfo('bumbo.wav', 1);
      c.setInstrumentSample(1, 'h');
      expect(c.doc.tracks[1].sample, 'h');
      // o áudio não foi carregado neste aparelho: vai 0 (sem áudio)
      expect(sent('instrument_sample').last, ['instrument_sample', 1, 0]);
      c.setInstrumentSample(1, 'desconhecido');
      expect(c.doc.tracks[1].sample, 'h');
    });

    test('quantizar pelo controlador desfaz', () {
      final c = newController();
      c.addInstrumentTrack(TrackKind.synth);
      final clip = c.createMidiClip(1, 0);
      c.edit((_) => clip.notes.add(MidiNote(pitch: 60, start: 0.9, length: 1)));
      c.quantizeNotes(clip, clip.notes, 1);
      expect(clip.notes.single.start, 1);
      c.undo();
      expect(c.findMidiClip(clip.id)!.$2.notes.single.start, 0.9);
    });
  });

  group('notas ao vivo', () {
    test('noteOn só toca em faixa de instrumento', () {
      final c = newController();
      c.noteOn(60);
      expect(sent('live_on'), isEmpty);
      c.addInstrumentTrack(TrackKind.synth);
      c.noteOn(60, velocity: 0.5);
      expect(sent('live_on'), [
        ['live_on', 1, 60, 0.5],
      ]);
      expect(c.liveNotes.value, {60});
      // a seleção muda antes de soltar: o note off vai para onde a nota está
      c.selectTrack(c.doc.tracks.indexWhere((t) => t.kind == TrackKind.drums));
      c.noteOff(60);
      expect(sent('live_off'), [
        ['live_off', 1, 60],
      ]);
      expect(c.liveNotes.value, isEmpty);
    });

    test('teclado do computador: notas, repetição, oitava, velocidade e soltura', () {
      final c = newController();
      c.addInstrumentTrack(TrackKind.synth);
      expect(c.handleNoteKey(down(PhysicalKeyboardKey.keyA)), isFalse);
      c.toggleKeyboard();
      expect(c.handleNoteKey(down(PhysicalKeyboardKey.keyA)), isTrue);
      expect(c.handleNoteKey(repeat(PhysicalKeyboardKey.keyA)), isTrue);
      expect(sent('live_on'), [
        ['live_on', 1, 60, 0.8],
      ]);
      // oitava acima no meio: a tecla solta a nota que tocou
      expect(c.handleNoteKey(down(PhysicalKeyboardKey.keyX)), isTrue);
      expect(c.keyboardOctave, 5);
      expect(c.handleNoteKey(up(PhysicalKeyboardKey.keyA)), isTrue);
      expect(sent('live_off'), [
        ['live_off', 1, 60],
      ]);
      c.handleNoteKey(down(PhysicalKeyboardKey.keyC));
      c.handleNoteKey(down(PhysicalKeyboardKey.keyC));
      expect(c.keyboardVelocity, 0.6);
      c.handleNoteKey(down(PhysicalKeyboardKey.keyW));
      expect(sent('live_on').last, ['live_on', 1, 73, 0.6]);
      // tecla que não é do teclado segue para os atalhos
      expect(c.handleNoteKey(down(PhysicalKeyboardKey.space)), isFalse);
      // desligar solta o que está preso
      c.toggleKeyboard();
      expect(sent('live_off').last, ['live_off', 1, 73]);
      expect(c.handleNoteKey(down(PhysicalKeyboardKey.keyA)), isFalse);
    });

    test('a oitava do teclado é por tipo de faixa: a bateria toca sem apertar Z', () {
      final c = newController();
      c.addInstrumentTrack(TrackKind.drums);
      c.toggleKeyboard();
      expect(c.keyboardOctave, 2);
      c.handleNoteKey(down(PhysicalKeyboardKey.keyA));
      c.handleNoteKey(down(PhysicalKeyboardKey.keyP));
      // A e P caem dentro do que a bateria responde (35–59), sem mexer na oitava
      expect(sent('live_on').map((m) => m[2]), [36, 51]);
      // mudar a oitava na bateria não muda a do sintetizador (e vice-versa)
      c.handleNoteKey(down(PhysicalKeyboardKey.keyX));
      expect(c.keyboardOctave, 3);
      c.addInstrumentTrack(TrackKind.synth);
      expect(c.keyboardOctave, 4);
      c.selectTrack(c.doc.tracks.indexWhere((t) => t.kind == TrackKind.drums));
      expect(c.keyboardOctave, 3);
    });

    test('limites de oitava e velocidade', () {
      final c = newController();
      c.toggleKeyboard();
      for (var i = 0; i < 12; i++) {
        c.handleNoteKey(down(PhysicalKeyboardKey.keyZ));
        c.handleNoteKey(down(PhysicalKeyboardKey.keyC));
      }
      expect(c.keyboardOctave, 0);
      expect(c.keyboardVelocity, 0.1);
      for (var i = 0; i < 12; i++) {
        c.handleNoteKey(down(PhysicalKeyboardKey.keyX));
        c.handleNoteKey(down(PhysicalKeyboardKey.keyV));
      }
      expect(c.keyboardOctave, 8);
      expect(c.keyboardVelocity, 1.0);
    });

    test('MIDI: note on/off, velocidade zero, pedal e all notes off', () async {
      final c = newController();
      c.addInstrumentTrack(TrackKind.synth);
      await c.enableMidiInput();
      // o stub não tem MIDI: vira mensagem, mas o roteamento fica pronto
      expect(c.error, contains('MIDI'));
      expect(c.midiEnabled, isFalse);
      final midi = engine.onMidi!;
      midi(0x90, 60, 127);
      expect(sent('live_on').last, ['live_on', 1, 60, 1.0]);
      midi(0x90, 60, 0);
      expect(sent('live_off').last, ['live_off', 1, 60]);

      engine.log = [];
      // o pedal vai ao motor, que segura as notas soltas (e grava o pedal); a tecla solta na hora
      midi(0xB0, 64, 127);
      expect(sent('live_cc'), [
        ['live_cc', 1, 64, 1.0],
      ]);
      midi(0x91, 62, 64);
      midi(0x81, 62, 0);
      expect(sent('live_off'), [
        ['live_off', 1, 62],
      ]);
      midi(0x91, 64, 64);
      midi(0xB0, 64, 0);
      expect(sent('live_cc').last, ['live_cc', 1, 64, 0.0]);
      expect(sent('live_off'), hasLength(1), reason: 'soltar o pedal não solta tecla nenhuma: quem segura é o motor');
      midi(0xB0, 123, 0);
      expect(sent('live_off').last, ['live_off', 1, 64]);
      expect(c.liveNotes.value, isEmpty);
    });
  });
}
