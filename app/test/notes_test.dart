import 'package:flutter_test/flutter_test.dart';
import 'package:jopendaw_app/daw/controller.dart';
import 'package:jopendaw_app/daw/instruments.dart';
import 'package:jopendaw_app/daw/model.dart';

MidiNote note(double start, double length, {int pitch = 60, double velocity = 0.8}) => MidiNote(pitch: pitch, start: start, length: length, velocity: velocity);

void main() {
  group('flattenNotes', () {
    test('põe as notas na linha do tempo e corta nas bordas do clipe', () {
      final synth = DawTrack(
        id: 's',
        name: 'Sintetizador 1',
        color: 0,
        kind: TrackKind.synth,
        midi: [
          MidiClip(
            id: 'c',
            start: 4,
            length: 4,
            notes: [
              note(0, 1, pitch: 60),
              note(-0.5, 1, pitch: 61), // cruza o começo: toca do 0 em diante
              note(3.5, 1, pitch: 62), // cruza o fim: corta no fim
              note(4, 1, pitch: 63), // começa no fim: fora
              note(-2, 1, pitch: 64), // antes do começo: fora
              note(1, 0.5, pitch: 200), // nota inválida
            ],
          ),
        ],
      );
      final notes = flattenNotes([DawTrack(id: 'a', name: 'Áudio 1', color: 0), synth]);
      expect(notes, [
        (track: 1, start: 4.0, length: 1.0, pitch: 60, velocity: 0.8),
        (track: 1, start: 4.0, length: 0.5, pitch: 61, velocity: 0.8),
        (track: 1, start: 7.5, length: 0.5, pitch: 62, velocity: 0.8),
      ]);
    });

    test('ignora faixa de áudio, ordena por início e limita a velocidade', () {
      final audio = DawTrack(
        id: 'a',
        name: 'Áudio 1',
        color: 0,
        midi: [
          MidiClip(id: 'x', start: 0, length: 4, notes: [note(0, 1)]),
        ],
      );
      final drums = DawTrack(
        id: 'd',
        name: 'Bateria 1',
        color: 1,
        kind: TrackKind.drums,
        midi: [
          MidiClip(id: 'b', start: 8, length: 4, notes: [note(0, 0.25, pitch: 36, velocity: 1.7)]),
          MidiClip(id: 'a', start: 0, length: 4, notes: [note(2, 0.25, pitch: 38), note(0, 0.25, pitch: 36)]),
        ],
      );
      final notes = flattenNotes([audio, drums]);
      expect(notes.map((n) => n.start), [0.0, 2.0, 8.0]);
      expect(notes.every((n) => n.track == 1), isTrue);
      expect(notes.last.velocity, 1.0);
    });

    test('clipe sem duração não toca nada', () {
      final t = DawTrack(
        id: 's',
        name: 'S',
        color: 0,
        kind: TrackKind.sampler,
        midi: [
          MidiClip(id: 'c', start: 0, length: 0, notes: [note(0, 1)]),
        ],
      );
      expect(flattenNotes([t]), isEmpty);
    });
  });

  group('quantizeNoteList', () {
    test('força 1 leva o início à grade e mantém a duração', () {
      final notes = [note(0.9, 0.3), note(1.13, 0.5), note(2.4, 1)];
      quantizeNoteList(notes, 0.25);
      expect(notes.map((n) => n.start), [1.0, 1.25, 2.5]);
      expect(notes.map((n) => n.length), [0.3, 0.5, 1.0]);
    });

    test('força 0,5 anda metade do caminho', () {
      final notes = [note(0.9, 0.3), note(2.2, 1)];
      quantizeNoteList(notes, 1, strength: 0.5);
      expect(notes[0].start, closeTo(0.95, 1e-12));
      expect(notes[1].start, closeTo(2.1, 1e-12));
      expect(notes[1].length, 1.0);
    });

    test('força 0 não mexe', () {
      final n = note(0.9, 0.3);
      quantizeNoteList([n], 1, strength: 0);
      expect(n.start, 0.9);
    });

    test('com ends o fim também vai à grade', () {
      final a = note(0.1, 0.55); // 0,1..0,65 → 0..0,75
      quantizeNoteList([a], 0.25, ends: true);
      expect(a.start, 0.0);
      expect(a.length, closeTo(0.75, 1e-12));
    });

    test('com ends nota curta não some: ocupa uma grade', () {
      final a = note(1.02, 0.05);
      quantizeNoteList([a], 0.25, ends: true);
      expect(a.start, 1.0);
      expect(a.length, 0.25);
    });

    test('a duração nunca fica abaixo de um quarto da grade', () {
      // com força 0,1 o fim só andaria de 0,01 para 0,109: abaixo de 1/4 da grade
      final a = note(0, 0.01);
      quantizeNoteList([a], 1, strength: 0.1, ends: true);
      expect(a.start, 0.0);
      expect(a.length, 0.25);
      // sem ends a duração fica, mas zero não passa
      final b = note(0.3, 0);
      quantizeNoteList([b], 1);
      expect(b.start, 0.0);
      expect(b.length, 0.25);
    });

    test('a grade é a da música: clipe fora da grade desloca as notas', () {
      // clipe em 0,5: a nota em 0,4 do clipe está em 0,9 na música → 1,0 → 0,5 no clipe
      final a = note(0.4, 1);
      quantizeNoteList([a], 1, offset: 0.5);
      expect(a.start, 0.5);
    });

    test('grade zero não faz nada', () {
      final a = note(0.33, 0.1);
      quantizeNoteList([a], 0, ends: true);
      expect(a.start, 0.33);
      expect(a.length, 0.1);
    });
  });

  group('splitMidiClip', () {
    test('nota que cruza o corte vira duas; a direita começa do zero', () {
      final clip = MidiClip(
        id: 'c',
        name: 'Baixo',
        start: 2,
        length: 4,
        notes: [
          note(0, 1, pitch: 40), // só na esquerda
          note(1.5, 1, pitch: 41), // cruza o corte (em 2 do clipe)
          note(2, 1, pitch: 42), // começa no corte: direita
          note(3, 0.5, pitch: 43), // direita
          note(5, 1, pitch: 44), // já estava depois do fim: segue escondida na direita
        ],
      );
      final right = splitMidiClip(clip, 4)!;
      expect(clip.start, 2);
      expect(clip.length, 2);
      expect(right.start, 4);
      expect(right.length, 2);
      expect(right.name, 'Baixo');
      expect(right.id, isNot('c'));
      expect([for (final n in clip.notes) (n.pitch, n.start, n.length)], [(40, 0.0, 1.0), (41, 1.5, 0.5)]);
      expect([for (final n in right.notes) (n.pitch, n.start, n.length)], [(41, 0.0, 0.5), (42, 0.0, 1.0), (43, 1.0, 0.5), (44, 3.0, 1.0)]);
    });

    test('corte fora do clipe ou na borda não corta', () {
      final clip = MidiClip(id: 'c', start: 2, length: 4, notes: [note(0, 1)]);
      expect(splitMidiClip(clip, 2), isNull);
      expect(splitMidiClip(clip, 6), isNull);
      expect(splitMidiClip(clip, 9), isNull);
      expect(clip.length, 4);
      expect(clip.notes, hasLength(1));
    });
  });
}
