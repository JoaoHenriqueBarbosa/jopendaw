import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jopendaw_app/audio/engine.dart';
import 'package:jopendaw_app/audio/engine_ffi.dart' show parseRecordedNotes, prepareRenderCalls;
import 'package:jopendaw_app/daw/controller.dart';
import 'package:jopendaw_app/daw/expression_wheels.dart';
import 'package:jopendaw_app/daw/export_options.dart';
import 'package:jopendaw_app/daw/instruments.dart';
import 'package:jopendaw_app/daw/midi_cc.dart';
import 'package:jopendaw_app/daw/model.dart';

import 'fake_engine.dart';

MidiCc cc(int id, double beat, double value) => MidiCc(cc: id, beat: beat, value: value);

MidiClip clipWith(List<MidiCc> events, {double start = 0, double length = 4, String id = 'm'}) =>
    MidiClip(id: id, start: start, length: length, controls: events);

DawTrack synthTrack(List<MidiClip> clips, {String id = 's'}) => DawTrack(id: id, name: 'Synth', color: 0, kind: TrackKind.synth)..midi.addAll(clips);

List<(int, int, double, double)> flat(List<DawTrack> tracks) => [for (final e in flattenControls(tracks)) (e.track, e.cc, e.beat, e.value)];

EngineState state(double beat, {bool playing = true}) => EngineState(beat, playing, Float32List(0));

void main() {
  late FakeEngine e;
  setUp(() => e = FakeEngine());

  group('modelo', () {
    test('documento sem controles: o JSON do clipe não ganha campo nenhum', () {
      final clip = MidiClip(id: 'a', name: 'x', start: 1, length: 4, notes: [MidiNote(pitch: 60, start: 0, length: 1)]);
      expect(clip.toJson().keys, ['id', 'name', 'start', 'length', 'notes']);
    });

    test('documento antigo (sem o campo) abre igual, com a lista vazia, e reescreve igual', () {
      final old = {
        'id': 'a',
        'name': 'x',
        'start': 1.0,
        'length': 4.0,
        'notes': [
          {'pitch': 60, 'start': 0.0, 'length': 1.0, 'velocity': 0.8},
        ],
      };
      final clip = MidiClip.fromJson(old);
      expect(clip.controls, isEmpty);
      expect(jsonEncode(clip.toJson()), jsonEncode(old));
    });

    test('controles vão e voltam pelo JSON, inclusive dentro do documento', () {
      final track = synthTrack([
        clipWith([cc(ccBend, 0.5, -0.25), cc(ccMod, 1, 1), cc(ccSustain, 2, 1)]),
      ]);
      final doc = DawDoc(bpm: 120, beatsPerBar: 4, tracks: [track]);
      final back = DawDoc.fromJson(jsonDecode(jsonEncode(doc.toJson())));
      final e = back.tracks.single.midi.single.controls;
      expect([for (final x in e) (x.cc, x.beat, x.value)], [(128, 0.5, -0.25), (1, 1.0, 1.0), (64, 2.0, 1.0)]);
    });

    test('valores fora da faixa são limitados por controle', () {
      expect(MidiCc.clampValue(ccBend, 5), 1);
      expect(MidiCc.clampValue(ccBend, -5), -1);
      expect(MidiCc.clampValue(ccMod, -1), 0);
      expect(MidiCc.clampValue(ccSustain, 3), 1);
    });
  });

  group('flattenControls: do clipe para o motor', () {
    test('batidas absolutas, ordem por batida e faixa certa', () {
      final t0 = DawTrack(id: 'a', name: 'Áudio', color: 0);
      final t1 = synthTrack([
        clipWith([cc(ccBend, 1, 0.5), cc(ccBend, 0, 0.25), cc(ccMod, 0.5, 0.75)], start: 8),
      ]);
      expect(flat([t0, t1]), [(1, ccBend, 8.0, 0.25), (1, ccMod, 8.5, 0.75), (1, ccBend, 9.0, 0.5), (1, ccBend, 12.0, 0.0), (1, ccMod, 12.0, 0.0)]);
    });

    test('só as faixas de instrumento; faixa de áudio com eventos perdidos não manda nada', () {
      final audio = DawTrack(id: 'a', name: 'Áudio', color: 0)..midi.add(clipWith([cc(ccBend, 0, 1)]));
      expect(flat([audio]), isEmpty);
    });

    test('eventos fora do clipe (antes do 0, depois do fim), não finitos e sem valor ficam de fora', () {
      final t = synthTrack([
        clipWith([cc(ccBend, -1, 0.5), cc(ccBend, 5, 0.5), cc(ccBend, 1, double.nan), cc(ccBend, double.nan, 1), cc(ccBend, 4, 0.5), cc(ccBend, 0, 0.25)]),
      ]);
      // o de 4 (exatamente no fim) entra; o resto não. O bend deixado em 0,5 volta a 0 no fim do clipe
      expect(flat([t]), [(0, ccBend, 0.0, 0.25), (0, ccBend, 4.0, 0.5)]);
    });

    test('valores fora da faixa são limitados; controle desconhecido não vai', () {
      final t = synthTrack([
        clipWith([cc(ccBend, 0, 3), cc(ccMod, 0, -2), cc(ccSustain, 0, 9), cc(7, 0, 1)]),
      ]);
      expect(flat([t]).where((x) => x.$3 == 0.0).map((x) => (x.$2, x.$4)).toSet(), {(ccBend, 1.0), (ccMod, 0.0), (ccSustain, 1.0)});
      expect(flat([t]).any((x) => x.$2 == 7), isFalse);
    });

    test('pedal que o clipe deixa embaixo é solto no fim do clipe', () {
      final t = synthTrack([
        clipWith([cc(ccSustain, 1, 1)], start: 4, length: 2),
      ]);
      expect(flat([t]), [(0, ccSustain, 5.0, 1.0), (0, ccSustain, 6.0, 0.0)]);
    });

    test('pedal que o clipe já soltou não ganha evento extra; bend e roda no repouso também não', () {
      final t = synthTrack([
        clipWith([cc(ccSustain, 1, 1), cc(ccSustain, 2, 0), cc(ccBend, 1, 0.5), cc(ccBend, 3, 0), cc(ccMod, 1, 0.4), cc(ccMod, 2, 0)]),
      ]);
      expect(flat([t]).where((x) => x.$3 == 4.0), isEmpty);
      expect(flat([t]), hasLength(6));
    });

    test('clipes vizinhos no mesmo estado: o pedal segue embaixo na emenda, sem subir e descer', () {
      final t = synthTrack([
        clipWith([cc(ccSustain, 0, 1)], start: 0, length: 4, id: 'a'),
        clipWith([cc(ccSustain, 0, 1)], start: 4, length: 4, id: 'b'),
      ]);
      expect(flat([t]), [(0, ccSustain, 0.0, 1.0), (0, ccSustain, 4.0, 1.0), (0, ccSustain, 8.0, 0.0)]);
    });

    test('clipes vizinhos em estados diferentes: o repouso do fim de um vem antes do primeiro evento do seguinte', () {
      final t = synthTrack([
        clipWith([cc(ccSustain, 0, 1)], start: 0, length: 4, id: 'a'),
        clipWith([cc(ccBend, 0, 0.5), cc(ccSustain, 0, 0), cc(ccSustain, 1, 1)], start: 4, length: 4, id: 'b'),
      ]);
      expect(flat([t]).where((x) => x.$2 == ccSustain).toList(), [
        (0, ccSustain, 0.0, 1.0),
        (0, ccSustain, 4.0, 0.0),
        (0, ccSustain, 4.0, 0.0),
        (0, ccSustain, 5.0, 1.0),
        (0, ccSustain, 8.0, 0.0),
      ]);
      // o bend do segundo clipe também não ganha repouso onde não havia nada
      expect(flat([t]).where((x) => x.$2 == ccBend).first, (0, ccBend, 4.0, 0.5));
    });

    test('clipe aparado na esquerda: o pedal que valia no novo começo segue valendo (pontos de antes ficam mudos)', () {
      // o clipe começava em 0 com o pedal descendo em 1; aparou-se até 2 (pontos deslocados: -1 e 1)
      final t = synthTrack([
        clipWith([cc(ccSustain, -1, 1), cc(ccSustain, 1, 0), cc(ccBend, -1, 0.5)], start: 2, length: 4),
      ]);
      expect(flat([t]), [(0, ccBend, 2.0, 0.5), (0, ccSustain, 2.0, 1.0), (0, ccSustain, 3.0, 0.0), (0, ccBend, 6.0, 0.0)]);
    });

    test('clipe aparado com o pedal já solto antes do começo não ganha evento', () {
      final t = synthTrack([
        clipWith([cc(ccSustain, -2, 1), cc(ccSustain, -1, 0), cc(ccSustain, 1, 1)], start: 2, length: 4),
      ]);
      expect(flat([t]).first, (0, ccSustain, 3.0, 1.0));
    });

    test('a ordem da lista vale no mesmo instante', () {
      final t = synthTrack([
        clipWith([cc(ccSustain, 1, 1), cc(ccSustain, 1, 0), cc(ccSustain, 1, 1)]),
      ]);
      final values = [
        for (final x in flat([t])) x.$4,
      ];
      expect(values.take(3), [1.0, 0.0, 1.0]);
    });

    test('clipe sem eventos e clipe vazio não geram nada', () {
      expect(
        flat([
          synthTrack([clipWith([]), MidiClip(id: 'n', start: 0, length: 4)]),
        ]),
        isEmpty,
      );
      expect(flat(const []), isEmpty);
    });
  });

  group('cortar, mover e escalar', () {
    test('splitMidiClip divide os eventos e o pedal embaixo continua no clipe da direita', () {
      final clip = clipWith([cc(ccBend, 0.5, 0.5), cc(ccSustain, 1, 1), cc(ccMod, 3, 0.5)], start: 2, length: 4);
      final right = splitMidiClip(clip, 4)!;
      expect([for (final x in clip.controls) (x.cc, x.beat, x.value)], [(ccBend, 0.5, 0.5), (ccSustain, 1.0, 1.0)]);
      // 4 é o corte (2 batidas do clipe): o pedal estava embaixo e entra no começo da direita; o
      // bend em 0,5 também estava fora do repouso
      final r = [for (final x in right.controls) (x.cc, x.beat, x.value)];
      expect(r, containsAll([(ccBend, 0.0, 0.5), (ccSustain, 0.0, 1.0), (ccMod, 1.0, 0.5)]));
      expect(r, hasLength(3));
    });

    test('evento exatamente no corte fica na direita, sem repetir o estado antigo', () {
      final clip = clipWith([cc(ccSustain, 0, 1), cc(ccSustain, 2, 0)], length: 4);
      final right = splitMidiClip(clip, 2)!;
      expect([for (final x in clip.controls) (x.beat, x.value)], [(0.0, 1.0)]);
      expect([for (final x in right.controls) (x.beat, x.value)], [(0.0, 0.0)]);
    });

    test('corte com tudo em repouso não acrescenta nada; corte fora do clipe não mexe', () {
      final clip = clipWith([cc(ccBend, 0.5, 0.5), cc(ccBend, 1, 0)], length: 4);
      final right = splitMidiClip(clip, 3)!;
      expect(right.controls, isEmpty);
      final none = clipWith([cc(ccBend, 1, 1)]);
      expect(splitMidiClip(none, 0), isNull);
      expect(none.controls, hasLength(1));
    });

    test('splitAtPlayhead e duplicar levam os eventos junto', () {
      final c = fakeController(
        e,
        tracks: [
          synthTrack([
            clipWith([cc(ccSustain, 1, 1), cc(ccBend, 3, 1)], start: 0, length: 4),
          ]),
        ],
      );
      c.beat.value = 2;
      c.selectedClip = 'm';
      c.splitAtPlayhead();
      final clips = c.doc.tracks[0].midi;
      expect(clips, hasLength(2));
      expect([for (final x in clips[0].controls) (x.cc, x.beat)], [(ccSustain, 1.0)]);
      expect([for (final x in clips[1].controls) (x.cc, x.beat)], unorderedEquals([(ccSustain, 0.0), (ccBend, 1.0)]));
      c.selectedClip = clips[0].id;
      c.duplicateSelected();
      final dup = c.doc.tracks[0].midi.last;
      expect(dup.id, isNot(clips[0].id));
      expect([for (final x in dup.controls) (x.cc, x.beat, x.value)], [(ccSustain, 1.0, 1.0)]);
      // cópia profunda: mexer nela não mexe no original
      dup.controls.first.value = 0;
      expect(clips[0].controls.first.value, 1);
    });

    test('mover o clipe muda a batida absoluta dos eventos sem mexer nos relativos', () {
      final t = synthTrack([
        clipWith([cc(ccBend, 1, 0.5)], start: 0),
      ]);
      expect(flat([t]).first.$3, 1.0);
      t.midi.single.start = 6;
      expect(flat([t]).first.$3, 7.0);
      expect(t.midi.single.controls.single.beat, 1.0);
    });

    test('placeOnTop: o clipe de cima corta o de baixo e os eventos da parte que sobra ficam no lugar', () {
      final under = clipWith([cc(ccBend, 1, 0.5), cc(ccBend, 6, 0.75)], start: 0, length: 8, id: 'u');
      final top = clipWith([], start: 2, length: 2, id: 't');
      final c = fakeController(
        e,
        tracks: [
          synthTrack([under, top]),
        ],
      );
      c.edit((_) => c.placeOnTop('t'));
      final clips = c.doc.tracks[0].midi;
      expect(clips, hasLength(3));
      final right = clips.firstWhere((x) => x.start == 4);
      // o evento de 6 (absoluto) fica em 2 do clipe da direita, que começa em 4
      expect([for (final x in right.controls) (x.cc, x.beat, x.value)], contains((ccBend, 2.0, 0.75)));
      expect(under.controls.first.beat, 1.0);
    });

    test('placeOnTop: o clipe de baixo aparado à esquerda desloca os eventos como as notas', () {
      final under = clipWith([cc(ccBend, 5, 0.5)], start: 4, length: 4, id: 'u')..notes.add(MidiNote(pitch: 60, start: 5, length: 1));
      final top = clipWith([], start: 0, length: 6, id: 't');
      final c = fakeController(
        e,
        tracks: [
          synthTrack([under, top]),
        ],
      );
      c.edit((_) => c.placeOnTop('t'));
      expect(under.start, 6);
      expect(under.notes.single.start, 3);
      expect(under.controls.single.beat, 3);
    });

    test('scaleControls escala a partir da origem, só o trecho quando pedido, e nunca antes do 0', () {
      final events = [cc(ccBend, 1, 0.5), cc(ccBend, 2, 0.25), cc(ccMod, 3, 1)];
      final all = scaleControls(events, 2, 1);
      expect([for (final x in all) x.beat], [1.0, 3.0, 5.0]);
      expect([for (final x in events) x.beat], [1.0, 2.0, 3.0], reason: 'o original não muda');
      final part = scaleControls(events, 2, 1, from: 1, to: 2);
      expect([for (final x in part) x.beat], [1.0, 3.0, 3.0]);
      final early = scaleControls([cc(ccBend, 0, 1)], 3, 1);
      expect(early.single.beat, 0.0);
      expect(scaleControls(events, 0, 1).map((x) => x.beat), [1.0, 2.0, 3.0], reason: 'fator inválido não mexe');
      expect(scaleControls(events, double.nan, 1).map((x) => x.beat), [1.0, 2.0, 3.0]);
    });

    test('mirrorControls espelha bend e roda no trecho e deixa o pedal onde está', () {
      final events = [cc(ccBend, 1, 0.5), cc(ccMod, 2, 0.25), cc(ccSustain, 1, 1), cc(ccBend, 5, 1)];
      final m = mirrorControls(events, 1, 3);
      expect([for (final x in m) (x.cc, x.beat)], [(ccBend, 3.0), (ccMod, 2.0), (ccSustain, 1.0), (ccBend, 5.0)]);
    });
  });

  group('afinar a gravação (thinControls) e desenhar (drawControlLine)', () {
    test('rajada densa vira poucos pontos e o último valor fica', () {
      final burst = [for (var i = 0; i <= 200; i++) cc(ccBend, i * 0.002, i / 200)];
      final t = thinControls(burst);
      expect(t.length, lessThan(30));
      expect(t.last.value, closeTo(1, 0.02));
      // sempre em ordem de batida e sem repetir valor em seguida
      for (var i = 1; i < t.length; i++) {
        expect(t[i].beat, greaterThanOrEqualTo(t[i - 1].beat));
        expect(t[i].value, isNot(t[i - 1].value));
      }
    });

    test('o retorno ao centro da roda sempre entra; o primeiro evento no repouso é dispensado', () {
      final t = thinControls([cc(ccBend, 0, 0), cc(ccBend, 1, 0.8), cc(ccBend, 1.001, 0.9), cc(ccBend, 2, 0)]);
      expect([for (final x in t) (x.beat, x.value)], [(1.0, 0.9), (2.0, 0.0)]);
    });

    test('pedal: só as mudanças de estado', () {
      final t = thinControls([
        cc(ccSustain, 0, 0),
        cc(ccSustain, 1, 1),
        cc(ccSustain, 1.5, 1),
        cc(ccSustain, 2, 0.9),
        cc(ccSustain, 3, 0),
        cc(ccSustain, 3.01, 0),
      ]);
      expect([for (final x in t) (x.beat, x.value)], [(1.0, 1.0), (3.0, 0.0)]);
    });

    test('lixo não passa: não finitos saem e os valores são limitados', () {
      final t = thinControls([cc(ccBend, double.nan, 1), cc(ccMod, 1, double.infinity), cc(ccBend, 1, 9), cc(ccMod, 2, 0.5), cc(7, 1, 1)]);
      expect([for (final x in t) (x.cc, x.value)], [(ccBend, 1.0), (ccMod, 0.5)]);
    });

    test('lista vazia', () => expect(thinControls(const []), isEmpty));

    test('closeControls devolve ao repouso o pedal, o bend e a roda que ficaram fora dele', () {
      final down = closeControls([cc(ccSustain, 1, 1), cc(ccBend, 1, 0.5), cc(ccMod, 1, 0.3)], 3);
      expect(
        [for (final x in down) (x.cc, x.beat, x.value)],
        [(ccSustain, 1.0, 1.0), (ccBend, 1.0, 0.5), (ccMod, 1.0, 0.3), (ccBend, 3.0, 0.0), (ccMod, 3.0, 0.0), (ccSustain, 3.0, 0.0)],
      );
      // o que já voltou ao repouso não ganha evento
      expect(closeControls([cc(ccSustain, 1, 1), cc(ccSustain, 2, 0), cc(ccBend, 1, 0.5), cc(ccBend, 2, 0)], 3), hasLength(4));
    });

    test('drawControlLine: reta com um ponto por passo, substituindo o trecho e mantendo o resto', () {
      final base = [cc(ccBend, 0, 0.1), cc(ccBend, 1.5, 0.9), cc(ccBend, 6, 0.3), cc(ccMod, 1.5, 0.6)];
      final r = drawControlLine(base, ccBend, 1, 2, 0, 1, step: 0.25);
      final mine = r.where((x) => x.cc == ccBend).toList()..sort((a, b) => a.beat.compareTo(b.beat));
      expect([for (final x in mine) x.beat], [0.0, 1.0, 1.25, 1.5, 1.75, 2.0, 6.0]);
      expect(mine[3].value, closeTo(0.5, 1e-9));
      expect(r.where((x) => x.cc == ccMod), hasLength(1), reason: 'outro controle intacto');
      // o de 1,5 (0,9) foi substituído pelo da reta
      expect(mine.any((x) => x.value == 0.9), isFalse);
    });

    test('drawControlLine de trás para frente dá a mesma reta; ponto só vira um evento', () {
      final a = drawControlLine(const [], ccMod, 1, 2, 0, 1, step: 0.5);
      final b = drawControlLine(const [], ccMod, 2, 1, 1, 0, step: 0.5);
      expect([for (final x in a) (x.beat, x.value)], [for (final x in b) (x.beat, x.value)]);
      expect(drawControlLine(const [], ccBend, 2, 2, 0.5, 0.5), hasLength(1));
      // valores fora da faixa são limitados; batida negativa vira 0
      final c = drawControlLine(const [], ccBend, -1, 1, -3, 3, step: 1);
      expect(c.every((x) => x.value.abs() <= 1 && x.beat >= 0), isTrue);
    });

    test('drawControlLine no pedal: um degrau só', () {
      final r = drawControlLine(const [], ccSustain, 1, 3, 0.9, 0.2);
      expect([for (final x in r) (x.beat, x.value)], [(1.0, 1.0)]);
    });

    test('controlValueAt: o último evento até a batida; nenhum antes → null', () {
      final ev = [cc(ccBend, 1, 0.5), cc(ccBend, 1, 0.7), cc(ccBend, 3, 0.1)];
      expect(controlValueAt(ev, ccBend, 0.5), isNull);
      expect(controlValueAt(ev, ccBend, 1), 0.7, reason: 'no mesmo instante vale o último da lista');
      expect(controlValueAt(ev, ccBend, 2), 0.7);
      expect(controlValueAt(ev, ccBend, 9), 0.1);
      expect(controlValueAt(ev, ccMod, 9), isNull);
    });

    test('sameControls compara campo a campo', () {
      expect(sameControls([cc(ccBend, 1, 0.5)], [cc(ccBend, 1, 0.5)]), isTrue);
      expect(sameControls([cc(ccBend, 1, 0.5)], [cc(ccBend, 1, 0.6)]), isFalse);
      expect(sameControls([cc(ccBend, 1, 0.5)], const []), isFalse);
    });
  });

  group('sincronização com o motor', () {
    test('documento sem controles nunca manda cc_clear nem cc_add', () async {
      final c = fakeController(
        e,
        tracks: [
          synthTrack([
            MidiClip(id: 'm', start: 0, length: 4, notes: [MidiNote(pitch: 60, start: 0, length: 1)]),
          ]),
        ],
      );
      c.edit((_) => c.doc.tracks[0].midi.single.notes.add(MidiNote(pitch: 64, start: 1, length: 1)));
      c.addInstrumentTrack(TrackKind.fm);
      expect(e.sent('note_add'), isNotEmpty);
      expect(e.sent('cc_clear'), isEmpty);
      expect(e.sent('cc_add'), isEmpty);
    });

    test('controles vão uma vez, em batidas absolutas e na ordem, e só de novo quando mudam', () {
      final c = fakeController(
        e,
        tracks: [
          DawTrack(id: 'a', name: 'Áudio', color: 0),
          synthTrack([
            clipWith([cc(ccBend, 1, 0.5), cc(ccSustain, 0, 1), cc(ccSustain, 2, 0)], start: 4),
          ]),
        ],
      );
      c.edit((_) {});
      expect(e.sent('cc_clear'), hasLength(1));
      expect(e.sent('cc_add'), [
        ['cc_add', 1, 64, 4.0, 1.0],
        ['cc_add', 1, 128, 5.0, 0.5],
        ['cc_add', 1, 64, 6.0, 0.0],
        ['cc_add', 1, 128, 8.0, 0.0],
      ]);
      // mexer em outra coisa (parâmetro, nota) não reenvia
      c.edit((_) => c.doc.tracks[1].midi.single.notes.add(MidiNote(pitch: 60, start: 0, length: 1)));
      expect(e.sent('cc_clear'), hasLength(1));
      // mudar um evento reenvia a lista inteira, depois do cc_clear
      e.log = [];
      c.edit((_) => c.doc.tracks[1].midi.single.controls[0].value = 0.75);
      expect(e.sent('cc_clear'), hasLength(1));
      expect(e.sent('cc_add').first, ['cc_add', 1, 64, 4.0, 1.0]);
      expect(e.sent('cc_add').any((x) => x[4] == 0.75), isTrue);
      final names = [for (final x in e.log!) x.first];
      expect(names.indexOf('cc_clear'), lessThan(names.indexOf('cc_add')));
    });

    test('apagar todos os controles manda o cc_clear e mais nada; desfazer reenvia', () {
      final c = fakeController(
        e,
        tracks: [
          synthTrack([
            clipWith([cc(ccBend, 1, 0.5)]),
          ]),
        ],
      );
      c.edit((_) {});
      e.log = [];
      c.edit((_) => c.doc.tracks[0].midi.single.controls.clear());
      expect(e.sent('cc_clear'), hasLength(1));
      expect(e.sent('cc_add'), isEmpty);
      e.log = [];
      c.undo();
      expect(e.sent('cc_clear'), hasLength(1));
      expect(e.sent('cc_add'), isNotEmpty);
    });

    test('faixas reordenadas: se o motor tinha controles, todos vão de novo; se não tinha, nada', () {
      final c = fakeController(
        e,
        tracks: [
          synthTrack([
            clipWith([cc(ccBend, 1, 0.5)]),
          ], id: 'a'),
          synthTrack([], id: 'b'),
        ],
      );
      c.edit((_) {});
      e.log = [];
      c.edit((d) => d.tracks.insert(0, d.tracks.removeAt(1)));
      expect(e.sent('cc_clear'), hasLength(1));
      expect(e.sent('cc_add').first[1], 1, reason: 'a faixa dos controles agora é o índice 1');

      final plain = fakeController(
        e,
        tracks: [
          synthTrack([], id: 'a'),
          synthTrack([], id: 'b'),
        ],
      );
      plain.edit((_) {});
      e.log = [];
      plain.edit((d) => d.tracks.insert(0, d.tracks.removeAt(1)));
      expect(e.sent('cc_clear'), isEmpty);
    });

    test('o render (exportação) leva os controles junto do documento', () async {
      final c = fakeController(
        e,
        tracks: [
          synthTrack([
            clipWith([cc(ccSustain, 1, 1), cc(ccSustain, 3, 0)]),
          ]),
        ],
      );
      c.doc.tracks[0].midi.single.notes.add(MidiNote(pitch: 60, start: 0, length: 1));
      await c.exportAudio(const ExportOptions());
      final calls = e.renders.single.calls;
      expect(calls.where((x) => x.first == 'cc_add'), [
        ['cc_add', 0, 64, 1.0, 1.0],
        ['cc_add', 0, 64, 3.0, 0.0],
      ]);
    });
  });

  group('ao vivo: MIDI e rodas', () {
    Future<DawController> live({TrackKind kind = TrackKind.synth}) async {
      final c = fakeController(
        e,
        tracks: [DawTrack(id: 'a', name: 'Áudio', color: 0)],
      );
      c.addInstrumentTrack(kind);
      await c.enableMidiInput();
      e.log = [];
      return c;
    }

    test('pitch bend de 14 bits: centro, extremos e passos', () async {
      await live();
      final midi = e.onMidi!;
      midi(0xE0, 0, 64); // 8192: centro
      midi(0xE0, 127, 127); // 16383: máximo
      midi(0xE0, 0, 0); // 0: mínimo
      midi(0xE0, 0, 96); // 12288: metade para cima
      midi(0xE0, 0, 32); // 4096: metade para baixo
      final bends = e.sent('live_bend');
      expect([for (final b in bends) b[2] as double], [closeTo(0, 1e-9), closeTo(16383 / 8192 - 1, 1e-9), -1.0, 0.5, -0.5]);
      expect(bends.every((b) => b[1] == 1), isTrue);
      // o primeiro (centro) não precisava ir, mas vai: o motor ignora o que não muda
    });

    test('roda de modulação (CC 1) e pedal (CC 64) vão como live_cc, na faixa de entrada', () async {
      await live();
      final midi = e.onMidi!;
      midi(0xB0, 1, 127);
      midi(0xB0, 1, 64);
      midi(0xB0, 64, 127);
      midi(0xB0, 64, 63);
      midi(0xB0, 64, 64);
      expect(e.sent('live_cc'), [
        ['live_cc', 1, 1, 1.0],
        ['live_cc', 1, 1, 64 / 127],
        ['live_cc', 1, 64, 1.0],
        ['live_cc', 1, 64, 0.0],
        ['live_cc', 1, 64, 1.0],
      ]);
    });

    test('bytes MIDI fora dos 7 bits e mensagens de outros canais não quebram', () async {
      await live();
      final midi = e.onMidi!;
      midi(0xE5, 255, 255); // canal 6, dados sujos: 0x7F em cada byte
      midi(0xB9, 1, 200);
      expect(e.sent('live_bend'), hasLength(1));
      expect(e.sent('live_bend').single[2] as double, closeTo(16383 / 8192 - 1, 1e-9));
      expect(e.sent('live_cc').single[3] as double, closeTo((200 & 0x7F) / 127, 1e-9));
    });

    test('a roda que muda de faixa deixa a antiga no repouso', () async {
      final c = await live();
      c.addInstrumentTrack(TrackKind.synth);
      c.selectedTrack = 1;
      e.onMidi!(0xE0, 0, 96);
      c.selectedTrack = 2;
      e.log = [];
      e.onMidi!(0xE0, 0, 96);
      expect(e.sent('live_bend'), [
        ['live_bend', 1, 0.0],
        ['live_bend', 2, 0.5],
      ]);
    });

    test('CC 121 (reset dos controles) leva bend, roda e pedal ao repouso, cada um na faixa dele', () async {
      await live();
      final midi = e.onMidi!;
      midi(0xE0, 0, 96);
      midi(0xB0, 1, 100);
      midi(0xB0, 64, 127);
      e.log = [];
      midi(0xB0, 121, 0);
      expect(e.sent('live_bend'), [
        ['live_bend', 1, 0.0],
      ]);
      expect(e.sent('live_cc').toSet().map((x) => (x[2], x[3])), {(1, 0.0), (64, 0.0)});
      // de novo: nada mais a soltar
      e.log = [];
      midi(0xB0, 121, 0);
      expect(e.log, isEmpty);
    });

    test('CC 120 (all sound off) manda o pânico e esquece o que estava fora do repouso', () async {
      await live();
      final midi = e.onMidi!;
      midi(0xB0, 64, 127);
      e.log = [];
      midi(0xB0, 120, 0);
      expect(e.sent('panic'), hasLength(1));
      // o pedal do app já voltou a solto: apertar de novo é uma mudança e vai ao motor
      e.log = [];
      midi(0xB0, 64, 127);
      expect(e.sent('live_cc'), hasLength(1));
    });

    test('pitchBend e modWheel do teclado da tela: limitam, ignoram lixo e não fazem nada sem faixa de instrumento', () async {
      final c = await live();
      c.pitchBend(5);
      c.pitchBend(-5);
      c.pitchBend(double.nan);
      c.pitchBend(double.infinity);
      c.modWheel(-1);
      c.modWheel(2);
      expect([for (final b in e.sent('live_bend')) b[2]], [1.0, -1.0]);
      expect([for (final b in e.sent('live_cc')) b[3]], [0.0, 1.0]);
      e.log = [];
      c.pitchBend(0.5, track: 0); // faixa de áudio
      c.pitchBend(0.5, track: 9); // não existe
      c.pitchBend(0.5, track: -1);
      expect(e.log, isEmpty);
      // faixa explícita (a do painel) vale mesmo que a seleção seja outra
      c.pitchBend(0.25, track: 1);
      expect(e.sent('live_bend'), [
        ['live_bend', 1, 0.25],
      ]);
    });

    test('a tecla solta com o pedal embaixo sai na hora: quem segura é o motor', () async {
      final c = await live();
      e.onMidi!(0xB0, 64, 127);
      e.onMidi!(0x90, 60, 100);
      e.onMidi!(0x80, 60, 0);
      expect(e.sent('live_off'), [
        ['live_off', 1, 60],
      ]);
      expect(c.liveNotes.value, isEmpty);
    });

    test('sem o motor pronto nada vai', () async {
      final c = await live();
      c.ready = false;
      c.pitchBend(1);
      e.onMidi!(0xE0, 0, 127);
      expect(e.log, isEmpty);
    });
  });

  group('gravar bend, roda e pedal', () {
    /// Grava com a faixa de instrumento armada e devolve o controlador (o "motor" devolve [notes]).
    Future<DawController> record(
      List<double> notes, {
      double start = 4,
      bool countIn = false,
      Duration elapsed = const Duration(seconds: 2),
      void Function(DawController c)? setup,
    }) async {
      final c = fakeController(e);
      c.addInstrumentTrack(TrackKind.synth);
      c.doc.countIn = countIn;
      setup?.call(c);
      c.setArmed(1, true);
      c.beat.value = start;
      await c.toggleRecord();
      if (countIn) c.debugEngineState(state(start + 0.01));
      e.notes = Float32List.fromList(notes);
      c.debugRecordingElapsed(elapsed);
      await c.toggleRecord();
      return c;
    }

    // as batidas chegam do motor em float de 32 bits: compara com três casas
    double r3(double v) => double.parse(v.toStringAsFixed(3));
    List<(int, double, double)> ccs(MidiClip clip) => [for (final x in clip.controls) (x.cc, r3(x.beat), r3(x.value))];

    test('entram no clipe novo, com a batida relativa ao clipe, e o pedal que ficou embaixo é solto no fim', () async {
      final c = await record([
        1, 60, 4.5, 5, 0.8, // uma nota
        1, 384, 4.6, 4.6, 0.5, // bend
        1, 384, 5, 5, 0, // volta ao centro
        1, 257, 5, 5, 0.6, // roda
        1, 320, 5.5, 5.5, 1, // pedal embaixo (e nunca sobe)
      ]);
      final clip = c.doc.tracks[1].midi.single;
      expect(clip.notes, hasLength(1));
      final got = ccs(clip);
      expect(got, containsAll([(ccBend, 0.6, 0.5), (ccBend, 1.0, 0.0), (ccMod, 1.0, 0.6), (ccSustain, 1.5, 1.0)]));
      // o pedal foi fechado no fim da gravação (elapsed 2 s a 120 bpm = 4 batidas, começando em 4)
      final up = got.where((x) => x.$1 == ccSustain && x.$3 == 0).single;
      expect(up.$2, greaterThan(1.5));
      c.undo();
      expect(c.doc.tracks[1].midi, isEmpty);
    });

    test('rajada de bend é afinada, mas onde a roda parou fica', () async {
      final burst = <double>[1, 60, 4, 6, 0.8];
      for (var i = 0; i <= 100; i++) {
        burst.addAll([1, 384, 4 + i * 0.005, 4 + i * 0.005, i / 100]);
      }
      final c = await record(burst);
      final bends = c.doc.tracks[1].midi.single.controls.where((x) => x.cc == ccBend).toList();
      expect(bends.length, lessThan(30));
      // onde a roda parou (1) fica, e a gravação fecha o bend no centro ao parar
      expect(bends[bends.length - 2].value, closeTo(1, 0.03));
      expect(bends.last.value, 0);
    });

    test('só controles, sem nota nenhuma, entram no clipe que estava sob o cursor (overdub do pedal)', () async {
      final c = await record(
        [1, 320, 5, 5, 1, 1, 320, 6, 6, 0],
        start: 4,
        setup: (c) => c.doc.tracks[1].midi.add(MidiClip(id: 'm', start: 4, length: 4, notes: [MidiNote(pitch: 60, start: 0, length: 1)])),
      );
      final clip = c.doc.tracks[1].midi.single;
      expect(clip.notes, hasLength(1));
      expect(ccs(clip), [(ccSustain, 1.0, 1.0), (ccSustain, 2.0, 0.0)]);
    });

    test('só controles e nenhum clipe sob o cursor: cria o clipe (vazio de notas) com os pontos e o repouso no fim', () async {
      final c = await record([1, 384, 5, 5, 0.5, 1, 320, 6, 6, 1]);
      final clip = c.doc.tracks[1].midi.single;
      expect(clip.notes, isEmpty);
      expect(clip.start, 4);
      final got = ccs(clip);
      expect(got, containsAll([(ccBend, 1.0, 0.5), (ccSustain, 2.0, 1.0)]));
      expect(got.where((x) => x.$3 == 0).map((x) => x.$1).toSet(), {ccBend, ccSustain}, reason: 'bend e pedal soltos ao parar');
      expect(c.error, isNull);
      c.undo();
      expect(c.doc.tracks[1].midi, isEmpty);
    });

    test('bateria não recebe controle ao vivo nem grava ponto nenhum', () async {
      final c = fakeController(e);
      c.addInstrumentTrack(TrackKind.drums);
      c.doc.countIn = false;
      c.setArmed(1, true);
      await c.enableMidiInput();
      e.log = [];
      c.pitchBend(0.5);
      c.modWheel(0.5);
      e.onMidi!(0xB0, 64, 127);
      expect(e.sent('live_bend'), isEmpty);
      expect(e.sent('live_cc'), isEmpty);
      c.beat.value = 4;
      await c.toggleRecord();
      // um motor mais velho (ou outra origem) ainda devolve eventos para a faixa da bateria
      e.notes = Float32List.fromList([1, 60, 4.5, 5, 0.8, 1, 384, 5, 5, 0.5, 1, 320, 5, 5, 1]);
      c.debugRecordingElapsed(const Duration(seconds: 2));
      await c.toggleRecord();
      final clip = c.doc.tracks[1].midi.single;
      expect(clip.notes, hasLength(1));
      expect(clip.controls, isEmpty);
    });

    test('o que foi tocado substitui, no trecho, o que o clipe já tinha do mesmo controle', () async {
      final c = await record(
        [1, 60, 5, 6, 0.8, 1, 384, 5, 5, 0.5, 1, 384, 6, 6, 0],
        start: 4,
        setup: (c) => c.doc.tracks[1].midi.add(
          MidiClip(id: 'm', start: 4, length: 4, controls: [cc(ccBend, 0.5, 0.9), cc(ccBend, 1.5, 0.9), cc(ccBend, 3, 0.4), cc(ccMod, 1.5, 0.7)]),
        ),
      );
      final clip = c.doc.tracks[1].midi.single;
      // o de 0,5 e o de 3 ficam; o de 1,5 (dentro do trecho 1..2) sai; o outro controle não é tocado
      expect(ccs(clip), containsAll([(ccBend, 0.5, 0.9), (ccBend, 1.0, 0.5), (ccBend, 2.0, 0.0), (ccBend, 3.0, 0.4), (ccMod, 1.5, 0.7)]));
      expect(ccs(clip).any((x) => x.$1 == ccBend && x.$2 == 1.5), isFalse);
    });

    test('overdub que estica o clipe à esquerda leva os eventos velhos junto', () async {
      final c = await record(
        [1, 60, 1, 1.5, 0.8],
        start: 2,
        setup: (c) => c.doc.tracks[1].midi.add(MidiClip(id: 'm', start: 2, length: 4, controls: [cc(ccBend, 1, 0.5)])),
      );
      final clip = c.doc.tracks[1].midi.single;
      expect(clip.start, 0);
      expect(clip.controls.single.beat, 3.0, reason: 'o evento estava em 3 absoluto: segue lá');
    });

    test('em loop só a última passada dos controles vale', () async {
      final c = await record(
        [1, 60, 0.5, 1, 0.8, 1, 384, 1, 1, 0.9, 1, 384, 3, 3, 0.9, /* volta */ 1, 384, 1, 1, 0.2, 1, 384, 3, 3, 0],
        start: 0,
        elapsed: const Duration(seconds: 5),
        setup: (c) => c.doc
          ..loopOn = true
          ..loopStart = 0
          ..loopEnd = 4,
      );
      final got = ccs(c.doc.tracks[1].midi.single).where((x) => x.$1 == ccBend).toList();
      expect(got, [(ccBend, 1.0, 0.2), (ccBend, 3.0, 0.0)], reason: 'a passada de 0,9 saiu; só a última ficou');
    });

    test('o que se tocou na contagem fica de fora', () async {
      final c = await record([1, 60, 4.5, 5, 0.8, 1, 384, 2, 2, 0.9, 1, 384, 5, 5, 0.3], countIn: true);
      final got = ccs(c.doc.tracks[1].midi.single);
      expect(got.first, (ccBend, 1.0, 0.3));
      expect(got, hasLength(2), reason: 'o segundo é o retorno ao centro ao parar');
    });

    test('evento de faixa desarmada ou que não existe é ignorado; controle desconhecido também', () async {
      final c = await record([1, 60, 4.5, 5, 0.8, 0, 384, 5, 5, 0.9, 7, 384, 5, 5, 0.9, 1, 256 + 9, 5, 5, 1, 1, 384, 5, 5, double.nan]);
      expect(c.doc.tracks[1].midi.single.controls, isEmpty);
    });

    test('o registro passa as alturas de controle sem clampar em 127', () {
      // o parser do motor nativo: 384 é bend, não a nota 127
      final notes = parseRecordedNotes(Float32List.fromList([1, 384, 5, 5, -0.5, 1, 60, 5, 6, 3, 1, 257, 2, 2, 7]));
      expect(notes[0], (track: 1, pitch: 384, start: 5.0, end: 5.0, velocity: -0.5));
      expect(notes[1].pitch, 60);
      expect(notes[1].velocity, 1.0, reason: 'nota: velocidade limitada a 0..1');
      expect(notes[2], (track: 1, pitch: 257, start: 2.0, end: 2.0, velocity: 1.0), reason: 'roda limitada a 0..1... até 1 (o valor 7 é lixo)');
    });
  });

  group('render fora de tempo real', () {
    test('live_bend e live_cc não entram; cc_add antes do fim passa; depois só o pedal que sobe, no fim', () {
      final calls = <List<Object>>[
        ['live_bend', 0, 1.0],
        ['live_cc', 0, 64, 1.0],
        ['cc_clear'],
        ['cc_add', 0, 128, 1.0, 0.5],
        ['cc_add', 0, 128, 9.0, 0.5],
        ['cc_add', 0, 64, 9.5, 0.0],
        ['cc_add', 0, 64, 9.5, 1.0],
        ['cc_add', 0, 64, 2.0, 1.0],
      ];
      final out = prepareRenderCalls(calls, 8, 120);
      expect(out, [
        ['cc_clear'],
        ['cc_add', 0, 128, 1.0, 0.5],
        ['cc_add', 0, 64, 8.0, 0.0],
        ['cc_add', 0, 64, 2.0, 1.0],
      ]);
    });
  });

  group('painel: rodas do teclado da tela', () {
    testWidgets('a roda de bend segue o dedo e volta ao centro ao soltar; a de modulação fica', (tester) async {
      final sent = <(String, double)>[];
      final c = fakeController(e, tracks: [synthTrack([])]);
      c.selectedTrack = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: ExpressionWheels(c: c, track: 0, height: 100, color: Colors.teal),
            ),
          ),
        ),
      );
      final bend = find.byKey(const ValueKey('bend-0'));
      final mod = find.byKey(const ValueKey('mod-0'));
      final top = tester.getTopLeft(bend), size = tester.getSize(bend);
      // no meio: 0
      final g = await tester.startGesture(top + Offset(size.width / 2, size.height / 2));
      await tester.pump();
      // arrasta ao topo: bend ~1
      await g.moveTo(top + Offset(size.width / 2, 0));
      await tester.pump();
      expect(e.sent('live_bend').last[2] as double, closeTo(1, 0.05));
      await g.up();
      await tester.pumpAndSettle();
      expect(e.sent('live_bend').last[2], 0.0, reason: 'voltou ao centro');
      // a de modulação vai a 1 no topo e fica
      final mt = tester.getTopLeft(mod);
      final g2 = await tester.startGesture(mt + Offset(size.width / 2, 0));
      await g2.up();
      await tester.pumpAndSettle();
      expect(e.sent('live_cc').last[3] as double, closeTo(1, 0.05));
      expect(sent, isEmpty);
    });
  });

  group('polimento: corte, aparo, cópia e origens', () {
    List<(int, double, double)> pts(MidiClip c) => [for (final x in c.controls) (x.cc, x.beat, x.value)];

    test('corte de clipe (K na linha do tempo): a direita começa com o pedal em vigor e a emenda não solta as notas', () {
      final clip = MidiClip(
        id: 'a',
        start: 0,
        length: 8,
        notes: [MidiNote(pitch: 60, start: 0, length: 6)],
        controls: [cc(ccSustain, 1, 1), cc(ccSustain, 7, 0), cc(ccBend, 3, 0.4)],
      );
      final right = splitMidiClip(clip, 4)!;
      expect(pts(right), [(ccSustain, 0.0, 1.0), (ccBend, 0.0, 0.4), (ccSustain, 3.0, 0.0)]);
      final t = synthTrack([clip, right]);
      final sustain = flat([t]).where((x) => x.$2 == ccSustain).toList();
      expect(sustain, [(0, ccSustain, 1.0, 1.0), (0, ccSustain, 4.0, 1.0), (0, ccSustain, 7.0, 0.0)], reason: 'o pedal não sobe e desce na batida do corte');
      // o bend, que ficou fora do centro, também emenda; o único retorno ao repouso é o do fim do clipe da direita
      expect(flat([t]).where((x) => x.$2 == ccBend).toList(), [(0, ccBend, 3.0, 0.4), (0, ccBend, 4.0, 0.4), (0, ccBend, 8.0, 0.0)]);
    });

    test('empilhar um clipe no meio de outro: a parte que sobra à direita começa com o estado que valia ali', () async {
      final c = fakeController(e);
      c.addInstrumentTrack(TrackKind.synth);
      final t = c.doc.tracks[1];
      t.midi.addAll([
        MidiClip(id: 'o', start: 0, length: 12, controls: [cc(ccSustain, 1, 1), cc(ccSustain, 11, 0)]),
        MidiClip(id: 'top', start: 4, length: 4),
      ]);
      c.placeOnTop('top');
      final parts = t.midi.where((m) => m.id != 'top' && m.id != 'o').single;
      expect(parts.start, 8);
      expect(pts(parts), [(ccSustain, 0.0, 1.0), (ccSustain, 3.0, 0.0)]);
      final sustain = flat(c.doc.tracks).where((x) => x.$2 == ccSustain).toList();
      expect(sustain.where((x) => x.$3 == 8.0), [(1, ccSustain, 8.0, 1.0)], reason: 'o "solta" do fim do clipe cortado não vem antes do "desce" da direita');
    });

    test('empilhar por cima do começo de outro (aparo): o pedal em vigor no novo começo é escrito no clipe', () async {
      final c = fakeController(e);
      c.addInstrumentTrack(TrackKind.synth);
      final t = c.doc.tracks[1];
      t.midi.addAll([
        MidiClip(id: 'o', start: 4, length: 8, controls: [cc(ccSustain, 1, 1), cc(ccSustain, 7, 0)]),
        MidiClip(id: 'top', start: 0, length: 6),
      ]);
      c.placeOnTop('top');
      final o = t.midi.firstWhere((m) => m.id == 'o');
      expect(o.start, 6);
      expect(o.controls.first.beat, 0);
      expect(o.controls.first.value, 1);
      expect(flat([t]).where((x) => x.$2 == ccSustain).first, (0, ccSustain, 6.0, 1.0));
    });

    test('copiar e colar controles do trecho: pontos, valor que já valia e repouso no fim', () {
      final ev = [cc(ccSustain, 0.5, 1), cc(ccSustain, 3, 0), cc(ccBend, 1.5, 0.5), cc(ccBend, 2, 0), cc(ccMod, 5, 0.9)];
      final region = copyControls(ev, 1, 3.5);
      expect(
        [for (final x in region) (x.cc, x.beat, x.value)],
        [(ccBend, 0.5, 0.5), (ccBend, 1.0, 0.0), (ccSustain, 0.0, 1.0), (ccSustain, 2.0, 0.0)],
        reason: 'o pedal já embaixo em 1 entra; o mod de 5 fica de fora',
      );
      final pasted = pasteControls(ev, region, 6);
      expect([
        for (final x in pasted.where((x) => x.beat >= 6)) (x.cc, x.beat, x.value),
      ], containsAll([(ccBend, 6.5, 0.5), (ccBend, 7.0, 0.0), (ccSustain, 6.0, 1.0), (ccSustain, 8.0, 0.0)]));
      expect(pasted.length, ev.length + 4, reason: 'nada do que já havia fora do trecho sumiu');
      // o pedal que termina fora do repouso ganha o retorno no fim do trecho
      expect(copyControls([cc(ccSustain, 1, 1)], 0, 4).map((x) => (x.beat, x.value)), [(1.0, 1.0), (4.0, 0.0)]);
      expect(copyControls([cc(ccSustain, 9, 1)], 0, 4), isEmpty);
    });

    test('roda da tela numa faixa e MIDI noutra não devolvem o valor um do outro ao repouso', () async {
      final c = fakeController(
        e,
        tracks: [DawTrack(id: 'a', name: 'Áudio', color: 0)],
      );
      c.addInstrumentTrack(TrackKind.synth); // 1
      c.addInstrumentTrack(TrackKind.synth); // 2
      await c.enableMidiInput();
      c.pitchBend(0.5, track: 1, screen: true);
      c.selectedTrack = 2;
      e.log = [];
      e.onMidi!(0xE0, 0, 96); // MIDI: bend 0.5 na faixa de entrada (2)
      expect(e.sent('live_bend'), [
        ['live_bend', 2, 0.5],
      ], reason: 'a faixa 1 (roda da tela) fica como está');
      // mudar a entrada do MIDI de faixa solta só o que era do MIDI
      c.selectedTrack = 1;
      e.log = [];
      e.onMidi!(0xE0, 0, 96);
      expect(e.sent('live_bend'), [
        ['live_bend', 2, 0.0],
        ['live_bend', 1, 0.5],
      ]);
      // soltar a roda da tela numa faixa não esquece o registro da roda de outra
      e.log = [];
      c.pitchBend(0.0, track: 1, screen: true);
      expect(e.sent('live_bend'), [
        ['live_bend', 1, 0.0],
      ]);
    });

    test('a resolução do bend é a mesma em qualquer origem (14 bits) e a da roda é 1/127', () async {
      final c = fakeController(e);
      c.addInstrumentTrack(TrackKind.synth);
      e.log = [];
      c.pitchBend(0.30001, track: 1, screen: true);
      c.pitchBend(4097 / 8192, track: 1);
      c.modWheel(0.5, track: 1, screen: true);
      expect(e.sent('live_bend').map((x) => x[2] as double), [(0.30001 * 8192).round() / 8192, 4097 / 8192]);
      expect(e.sent('live_cc').single[3], 64 / 127);
      expect(quantizeControl(ccBend, -1), -1);
      expect(quantizeControl(ccBend, 0.00001), 0);
      expect(quantizeControl(ccSustain, 0.6), 1);
      expect(quantizeControl(ccMod, double.nan), 0);
    });

    test('quantizar as notas não mexe nos pontos de controle', () async {
      final c = fakeController(e);
      c.addInstrumentTrack(TrackKind.synth);
      final clip = MidiClip(
        id: 'q',
        start: 0,
        length: 4,
        notes: [MidiNote(pitch: 60, start: 0.13, length: 1)],
        controls: [cc(ccSustain, 0.13, 1), cc(ccSustain, 2.07, 0)],
      );
      c.doc.tracks[1].midi.add(clip);
      c.quantizeNotes(clip, clip.notes, 0.25);
      expect(clip.notes.single.start, 0.25);
      expect([for (final x in clip.controls) x.beat], [0.13, 2.07]);
    });
  });
}
