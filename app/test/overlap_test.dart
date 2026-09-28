import 'package:flutter_test/flutter_test.dart';
import 'package:jopendaw_app/daw/effects.dart';
import 'package:jopendaw_app/daw/instruments.dart';
import 'package:jopendaw_app/daw/model.dart';

import 'controller_test.dart' show newController;

/// Clipe de áudio de [start] (batidas) com [secs] segundos; a 120 BPM, 1 batida = 0,5 s.
AudioClip audio(String id, double start, double secs, {double offset = 0}) => AudioClip(id: id, sample: 's', start: start, length: secs, offset: offset);

void main() {
  group('placeOnTop (áudio, 120 BPM)', () {
    test('o clipe de baixo coberto inteiro some', () {
      final c = newController();
      final t = c.doc.tracks[0]..clips.addAll([audio('a', 2, 1), audio('top', 1, 3)]);
      c.placeOnTop('top');
      expect(t.clips.map((x) => x.id), ['top']);
    });

    test('cobrindo o meio, o de baixo parte em dois com o offset certo', () {
      final c = newController();
      final t = c.doc.tracks[0]..clips.addAll([audio('a', 0, 4), audio('top', 2, 1)]);
      c.placeOnTop('top');
      final a = t.clips.firstWhere((x) => x.id == 'a');
      final right = t.clips.firstWhere((x) => x.id != 'a' && x.id != 'top');
      expect(a.length, closeTo(1, 1e-9)); // até a batida 2
      expect(right.start, closeTo(4, 1e-9)); // depois do de cima (2 + 2 batidas)
      expect(right.offset, closeTo(2, 1e-9));
      expect(right.length, closeTo(2, 1e-9));
    });

    test('cobrindo o fim encurta; cobrindo o começo apara', () {
      final c = newController();
      final t = c.doc.tracks[0]..clips.addAll([audio('a', 0, 2), audio('b', 6, 2), audio('top', 3, 2)]);
      c.placeOnTop('top'); // de cima: batidas 3..7
      final a = t.clips.firstWhere((x) => x.id == 'a');
      final b = t.clips.firstWhere((x) => x.id == 'b');
      expect(a.length, closeTo(1.5, 1e-9)); // 0..3
      expect(b.start, closeTo(7, 1e-9));
      expect(b.offset, closeTo(0.5, 1e-9));
      expect(b.length, closeTo(1.5, 1e-9));
    });

    test('clipes de outras faixas e vizinhos encostados não mudam', () {
      final c = newController();
      final t = c.doc.tracks[0]..clips.addAll([audio('a', 0, 1), audio('top', 2, 1)]);
      c.placeOnTop('top');
      expect(t.clips.firstWhere((x) => x.id == 'a').length, 1);
    });
  });

  test('placeOnTop (MIDI): aparar o começo mantém as notas no lugar absoluto', () {
    final c = newController();
    final t = DawTrack(id: 's', name: 'Synth', color: 1, kind: TrackKind.synth);
    c.doc.tracks.add(t);
    final under = MidiClip(id: 'u', start: 0, length: 8, notes: [MidiNote(pitch: 60, start: 1, length: 1), MidiNote(pitch: 62, start: 6, length: 1)]);
    final top = MidiClip(id: 'top', start: 0, length: 4);
    t.midi.addAll([under, top]);
    c.placeOnTop('top');
    expect(under.start, 4);
    expect(under.length, 4);
    // a nota da batida 6 continua na batida 6 (4 + 2); a da batida 1 ficou antes do começo
    expect(under.notes.map((n) => under.start + n.start), [1, 6]);
  });

  test('duplicar a faixa: cópia logo abaixo, ids novos e automação apontando para o efeito da cópia', () {
    final c = newController();
    final t = c.doc.tracks[0]..clips.add(audio('a', 0, 1));
    final fx = c.addEffect(0, EffectKind.reverb);
    c.addLane(0, AutoTarget(AutoKind.effect, ref: fx.id, param: 0)).points.add(AutoPoint(beat: 0, value: 0.5));
    c.duplicateTrack(0);
    expect(c.doc.tracks, hasLength(2));
    final copy = c.doc.tracks[1];
    expect(copy.name, '${t.name} (2)');
    expect(copy.id, isNot(t.id));
    expect(copy.clips.single.id, isNot('a'));
    expect(copy.effects.single.id, isNot(fx.id));
    expect(copy.lanes.single.target.ref, copy.effects.single.id);
    expect(c.selectedTrack, 1);
    c.undo();
    expect(c.doc.tracks, hasLength(1));
  });

  test('mover faixa: barramento que passa a sair para trás volta ao master', () {
    final c = newController();
    final b1 = c.addBusTrack(); // 1
    final b2 = c.addBusTrack(); // 2
    c.setOutput(1, b2.id);
    expect(c.doc.tracks[1].output, b2.id);
    c.moveTrack(2, 0); // b2 vai para antes de b1: b1 → b2 seria para trás
    expect(c.doc.tracks.firstWhere((x) => x.id == b1.id).output, isNull);
  });
}
