// Sequenciador de passos: a conversão grade ↔ notas, as ações sobre a grade, os padrões de fábrica
// e a aba (só bateria e sampler com zonas).
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:jopendaw_app/daw/instruments.dart';
import 'package:jopendaw_app/daw/model.dart';
import 'package:jopendaw_app/daw/sampler_zones.dart';
import 'package:jopendaw_app/daw/step_sequencer.dart';

StepLayout layout({double step = 0.25, int bars = 1, double swing = 0, double bar = 4}) => StepLayout.of(barBeats: bar, bars: bars, step: step, swing: swing);

MidiNote note(int pitch, double start, [double v = 0.8]) => MidiNote(pitch: pitch, start: start, length: 0.25, velocity: v);

/// (pitch, start, velocidade) ordenados, para comparar listas de notas.
List<String> keys(Iterable<MidiNote> ns) => [for (final n in ns) '${n.pitch}@${n.start.toStringAsFixed(6)}v${n.velocity.toStringAsFixed(2)}']..sort();

var _zoneIds = 0;

void main() {
  group('grade ↔ notas', () {
    test('ida e volta exata em 8, 12, 16, 24, 32 e 64 passos por compasso', () {
      for (final (id, per) in [('1/8', 8), ('1/8T', 12), ('1/16', 16), ('1/16T', 24), ('1/32', 32), ('1/64', 64)]) {
        final l = layout(step: resolutionById(id).beats);
        expect(l.steps, per, reason: id);
        final notes = <MidiNote>[];
        final on = [
          for (var i = 0; i < l.steps; i++)
            if (i % 3 == 0 || i == l.steps - 1) i,
        ];
        for (final i in on) {
          expect(addStep(notes, 36, i, l, 0.8), isTrue);
        }
        final row = readRow(notes, 36, l);
        expect(row.keys.toList()..sort(), on, reason: id);
        expect(row.values.every((h) => !h.offGrid), isTrue, reason: id);
        for (final i in on) {
          expect(notes.any((n) => (n.start - l.pos(i)).abs() < 1e-12), isTrue);
        }
        for (final i in on) {
          expect(removeStep(notes, 36, i, l), isTrue);
        }
        expect(notes, isEmpty);
      }
    });

    test('tercinas caem em 1/3 de batida', () {
      final l = layout(step: resolutionById('1/8T').beats);
      final notes = [note(38, 1 / 3), note(38, 2 / 3), note(38, 1.0)];
      expect(readRow(notes, 38, l).keys.toList()..sort(), [1, 2, 3]);
      expect(readRow(notes, 38, l).values.every((h) => !h.offGrid), isTrue);
    });

    test('tolerância de 1/1000 de batida: dentro é passo, fora é "fora da grade"', () {
      final l = layout();
      final notes = [note(36, 0.0009), note(36, 0.5 + 0.0011), note(36, 1.0 - 0.0005)];
      final row = readRow(notes, 36, l);
      expect(row[0]!.offGrid, isFalse);
      expect(row[2]!.offGrid, isTrue, reason: '0,5011 é o passo 2 fora da grade');
      expect(row[4]!.offGrid, isFalse);
    });

    test('nota fora da grade aparece no passo mais próximo e é preservada ao editar outros passos', () {
      final l = layout();
      final human = note(36, 0.5 + 0.06, 0.6); // mais perto do passo 2 (0,5) que do 3 (0,75)
      final notes = [human, note(36, 0.0)];
      final row = readRow(notes, 36, l);
      expect(row[2]!.offGrid, isTrue);
      expect(row[2]!.velocity, 0.6);
      addStep(notes, 36, 8, l, 0.8);
      removeStep(notes, 36, 0, l);
      addStep(notes, 38, 2, l, 0.8);
      expect(notes.contains(human), isTrue);
      expect(human.start, 0.56);
      expect(human.velocity, 0.6);
      // ligar um passo já ocupado (mesmo fora da grade) não cria nota
      expect(addStep(notes, 36, 2, l, 0.8), isFalse);
      // desligar o passo some com a nota fora da grade
      expect(removeStep(notes, 36, 2, l), isTrue);
      expect(notes.contains(human), isFalse);
    });

    test('mudar a velocidade não move a nota fora da grade', () {
      final l = layout();
      final n = note(36, 0.56);
      final notes = [n];
      expect(setStepVelocity(notes, 36, 2, l, 1.0), isTrue);
      expect(n.start, 0.56);
      expect(n.velocity, 1.0);
      expect(dynamicOf(1.0), StepDynamic.accent);
      expect(dynamicOf(0.3), StepDynamic.ghost);
      expect(dynamicOf(0.8), StepDynamic.normal);
    });

    test('editar uma linha não altera as notas de outras linhas', () {
      final l = layout();
      final other = [note(38, 1.0), note(42, 0.5), note(60, 0.0), note(38, 9.0)];
      final before = keys(other);
      final notes = [...other.map((n) => n.copy())];
      addStep(notes, 36, 0, l, 0.8);
      addStep(notes, 36, 4, l, 0.8);
      removeStep(notes, 36, 0, l);
      clearRows(notes, {36}, l);
      fillEvery(notes, {36}, l, 4);
      shiftRows(notes, {36}, l, 3);
      invertRows(notes, {36}, l);
      randomizeRows(notes, {36}, l, 50, math.Random(1));
      expect(keys(notes.where((n) => n.pitch != 36)), before);
    });

    test('notas depois do padrão ficam quietas; o que é de fora do kit só some se pedido', () {
      final l = layout();
      final notes = [note(36, 4.0), note(36, 7.5), note(99, 0.0)];
      expect(readRow(notes, 36, l), isEmpty, reason: 'depois do compasso 1');
      clearRows(notes, {36}, l);
      expect(notes.where((n) => n.pitch == 36).length, 2);
      expect(notes.where((n) => n.pitch == 99).length, 1);
    });
  });

  group('ações', () {
    test('limpar linha e tudo', () {
      final l = layout();
      final notes = [note(36, 0), note(36, 1), note(38, 1)];
      expect(clearRows(notes, {36}, l), 2);
      expect(notes.length, 1);
      expect(clearRows(notes, {36, 38}, l), 1);
      expect(notes, isEmpty);
    });

    test('deslocar dá a volta e volta ao lugar', () {
      final l = layout();
      final notes = [note(36, 0), note(36, 0.75), note(38, 1.0)];
      final before = keys(notes);
      shiftRows(notes, {36, 38}, l, 1);
      expect(keys(notes), keys([note(36, 0.25), note(36, 1.0), note(38, 1.25)]));
      shiftRows(notes, {36, 38}, l, -1);
      expect(keys(notes), before);
      shiftRows(notes, {36}, l, 16);
      expect(keys(notes), before);
      final one = [note(36, 0)];
      shiftRows(one, {36}, l, -1);
      expect(one.single.start, 3.75);
    });

    test('deslocar mantém o micro-tempo da nota fora da grade', () {
      final l = layout();
      final n = note(36, 0.51);
      shiftRows([n], {36}, l, 1);
      expect(n.start, closeTo(0.76, 1e-9));
    });

    test('inverter troca ligado por vazio e é involutivo', () {
      final l = layout(step: 0.5);
      final notes = [note(36, 0), note(36, 1.0)];
      invertRows(notes, {36}, l);
      expect(readRow(notes, 36, l).keys.toList()..sort(), [1, 3, 4, 5, 6, 7]);
      invertRows(notes, {36}, l);
      expect(readRow(notes, 36, l).keys.toList()..sort(), [0, 2]);
    });

    test('aleatorizar: densidade 0 esvazia, 100 enche, semente igual repete', () {
      final l = layout();
      final a = <MidiNote>[note(36, 0)];
      randomizeRows(a, {36}, l, 0, math.Random(3));
      expect(a, isEmpty);
      randomizeRows(a, {36}, l, 100, math.Random(3));
      expect(a.length, 16);
      final b = <MidiNote>[], c = <MidiNote>[];
      randomizeRows(b, {36}, l, 40, math.Random(7));
      randomizeRows(c, {36}, l, 40, math.Random(7));
      expect(keys(b), keys(c));
      expect(b.length, inInclusiveRange(1, 15));
      expect(b.every((n) => n.velocity >= 0.55 && n.velocity <= 1.0), isTrue);
    });

    test('preencher a cada N: quatro no chão', () {
      final l = layout();
      final notes = [note(36, 0.25)];
      fillEvery(notes, {36}, l, 4);
      expect(notes.map((n) => n.start).toList()..sort(), [0.0, 1.0, 2.0, 3.0]);
      fillEvery(notes, {36}, l, 3, offset: 1);
      expect(readRow(notes, 36, l).keys.toList()..sort(), [1, 4, 7, 10, 13]);
    });

    test('copiar e colar o padrão por linha', () {
      final l = layout();
      final notes = [note(36, 0), note(36, 2.0), note(38, 1.0)];
      final cb = copyPattern(notes, {36}, l);
      expect(cb.notes.length, 2);
      clearRows(notes, {36}, l);
      addStep(notes, 36, 5, l, 0.8);
      pastePattern(notes, {36}, l, cb);
      expect(readRow(notes, 36, l).keys.toList()..sort(), [0, 8]);
      expect(notes.where((n) => n.pitch == 38).length, 1);
    });

    test('repetir o padrão até o fim do clipe', () {
      final l = layout();
      final notes = [note(36, 0), note(38, 1.0), note(42, 3.75), note(36, 5.0)];
      final n = repeatPattern(notes, l, 16);
      expect(n, 3);
      final k = notes.where((x) => x.pitch == 36).map((x) => x.start).toList()..sort();
      expect(k, [0.0, 4.0, 8.0, 12.0]);
      expect(notes.length, 12, reason: 'o 5.0 antigo foi trocado pelas cópias');
      // clipe que não é múltiplo do padrão: a cópia que não cabe some
      final m = [note(36, 0), note(38, 3.0)];
      expect(repeatPattern(m, l, 6), 1);
      expect(m.where((x) => x.pitch == 38).map((x) => x.start).toList()..sort(), [3.0], reason: '7.0 passa do fim do clipe');
      expect(m.where((x) => x.pitch == 36).length, 2);
      // padrão do tamanho do clipe: nada a fazer
      final z = [note(36, 0)];
      expect(repeatPattern(z, l, 4), 0);
      expect(z.length, 1);
    });

    test('repetir vale para padrões de mais compassos', () {
      final l = layout(bars: 2);
      final notes = [note(36, 0), note(36, 4.0)];
      repeatPattern(notes, l, 24);
      expect(notes.map((n) => n.start).toList()..sort(), [0.0, 4.0, 8.0, 12.0, 16.0, 20.0]);
    });
  });

  group('swing', () {
    test('aplicar atrasa os passos pares e tirar devolve exato', () {
      final l = layout();
      final notes = [for (var i = 0; i < 16; i++) note(42, i * 0.25)];
      final before = keys(notes);
      final moved = retimeSwing(notes, l, 0, 0.5);
      expect(moved, 8);
      for (var i = 0; i < 16; i++) {
        expect(notes[i].start, i.isOdd ? i * 0.25 + 0.125 : i * 0.25);
      }
      // com o swing aplicado, as notas seguem "no passo"
      final row = readRow(notes, 42, l.withSwing(0.5));
      expect(row.length, 16);
      expect(row.values.every((h) => !h.offGrid), isTrue);
      retimeSwing(notes, l, 0.5, 0);
      expect(keys(notes), before);
    });

    test('trocar de swing; notas fora da grade não andam', () {
      final l = layout();
      final human = note(42, 0.27); // perto do passo 1 (0,25), fora da grade
      final notes = [note(42, 0.25), note(42, 0.5), human];
      retimeSwing(notes, l, 0, 1 / 3);
      expect(notes[0].start, closeTo(0.25 + 0.25 / 3, 1e-12));
      expect(notes[1].start, 0.5);
      expect(human.start, 0.27);
      retimeSwing(notes, l, 1 / 3, 0.75);
      expect(notes[0].start, closeTo(0.25 + 0.1875, 1e-12));
      retimeSwing(notes, l, 0.75, 0);
      expect(notes[0].start, closeTo(0.25, 1e-12));
    });

    test('passo ligado com swing aplicado sai na posição atrasada', () {
      final l = layout(swing: 0.5);
      final notes = <MidiNote>[];
      addStep(notes, 42, 1, l, 0.8);
      addStep(notes, 42, 2, l, 0.8);
      expect(notes[0].start, 0.25 + 0.125);
      expect(notes[1].start, 0.5);
    });
  });

  group('padrões de fábrica', () {
    final kit = {for (final d in drumPieces) d.pitch};
    StepPreset by(String id) => stepPresets.firstWhere((p) => p.id == id);

    List<double> starts(StepPreset p, int pitch, {double? v}) => [
      for (final n in presetNotes(p))
        if (n.pitch == pitch && (v == null || n.velocity == v)) n.start,
    ]..sort();

    test('há pelo menos oito, com linhas no kit, textos do tamanho certo e velocidades válidas', () {
      expect(stepPresets.length, greaterThanOrEqualTo(8));
      expect({for (final p in stepPresets) p.id}.length, stepPresets.length);
      for (final p in stepPresets) {
        for (final r in p.rows) {
          expect(kit.contains(r.pitch), isTrue, reason: '${p.id} ${r.pitch}');
          expect(r.pattern.length * r.step, closeTo(p.span, 1e-9), reason: '${p.id}: cada linha cobre o padrão inteiro');
          expect(r.pattern.split('').every((ch) => '.xXo'.contains(ch)), isTrue);
        }
        for (final n in presetNotes(p)) {
          expect(n.start, inInclusiveRange(0, p.span - 1e-9));
          expect(n.velocity, inInclusiveRange(0, 1));
        }
      }
    });

    test('quatro no chão: bumbo em todo tempo, palmas no 2 e no 4', () {
      expect(starts(by('four'), 36), [0.0, 1.0, 2.0, 3.0]);
      expect(starts(by('four'), 39), [1.0, 3.0]);
    });

    test('rock, funk, hip-hop, dembow, bossa e house', () {
      expect(starts(by('rock'), 36), [0.0, 2.0, 2.5]);
      expect(starts(by('rock'), 38), [1.0, 3.0]);
      expect(starts(by('funk'), 38, v: stepGhostVelocity).length, 3);
      expect(starts(by('funk'), 42, v: stepAccentVelocity), [0.0, 1.0, 2.0, 3.0]);
      expect(starts(by('hiphop'), 46), [3.5]);
      expect(starts(by('dembow'), 38), [0.75, 1.5, 2.75, 3.5]);
      expect(starts(by('dembow'), 36), [0.0, 1.0, 2.0, 3.0]);
      expect(starts(by('bossa'), 37), [0.0, 0.75, 1.5, 2.5, 3.25]);
      expect(starts(by('house'), 46), [0.5, 1.5, 2.5, 3.5]);
    });

    test('trap: chimbal em 1/32 com rolo, caixa no 3', () {
      final p = by('trap');
      expect(p.resolution, '1/32');
      final hats = starts(p, 42);
      // 4 colcheias (2 tempos) + 4 semicolcheias + 8 fusas do rolo
      expect(hats.length, 4 + 4 + 8);
      expect(hats.where((s) => s >= 3.0).length, 8);
      expect(starts(p, 38), [2.0]);
      final l = layout(step: resolutionById(p.resolution).beats);
      expect(readRow(presetNotes(p), 42, l).values.every((h) => !h.offGrid), isTrue);
    });

    test('shuffle em tercinas cai na grade de 1/8 tercina', () {
      final p = by('shuffle');
      final l = layout(step: resolutionById(p.resolution).beats);
      final notes = presetNotes(p);
      expect(readRow(notes, 36, l).keys.toList()..sort(), [0, 6]);
      expect(readRow(notes, 38, l).keys.toList()..sort(), [3, 9]);
      expect(readRow(notes, 42, l).values.every((h) => !h.offGrid), isTrue);
    });

    test('aplicar troca só as peças do kit no padrão e respeita o clipe', () {
      final p = by('rock');
      final keep = note(60, 1.0), later = note(36, 6.0);
      final notes = [note(36, 0.5), note(42, 3.9), keep, later];
      final n = applyPreset(notes, p);
      expect(n, presetNotes(p).length);
      expect(notes.contains(keep), isTrue);
      expect(notes.contains(later), isTrue);
      expect(notes.where((x) => x.pitch == 36 && x.start == 0.5), isEmpty);
      final short = <MidiNote>[];
      applyPreset(short, p, clipLength: 2);
      expect(short.every((x) => x.start < 2), isTrue);
      expect(short, isNotEmpty);
    });
  });

  group('linhas e disponibilidade', () {
    test('a bateria tem uma linha por peça de drumPieces, cada uma com o pitch certo', () {
      final rows = drumRows();
      expect(rows.length, drumPieces.length);
      expect({for (final r in rows) r.pitch}, {for (final d in drumPieces) d.pitch});
      for (final r in rows) {
        expect(drumPieces.firstWhere((d) => d.pitch == r.pitch).name, r.name);
      }
      expect(rows.first.pitch, 36);
    });

    test('só bateria e sampler com zonas têm a aba', () {
      DawTrack tr(TrackKind k, {List<SamplerZone>? zones}) => DawTrack(id: 't', name: 'x', color: 0, kind: k, zones: zones);
      expect(stepsAvailable(tr(TrackKind.drums)), isTrue);
      expect(stepsAvailable(tr(TrackKind.synth)), isFalse);
      expect(stepsAvailable(tr(TrackKind.fm)), isFalse);
      expect(stepsAvailable(tr(TrackKind.wavetable)), isFalse);
      expect(stepsAvailable(tr(TrackKind.audio)), isFalse);
      expect(stepsAvailable(tr(TrackKind.bus)), isFalse);
      expect(stepsAvailable(tr(TrackKind.sampler)), isFalse, reason: 'sem zonas');
      final zs = sliceZones('abc', [0.0, 0.5, 1.0], () => 'z${_zoneIds++}');
      expect(zs.length, 3);
      final rows = stepRowsOf(tr(TrackKind.sampler, zones: zs));
      expect(rows.map((r) => r.pitch), [24, 25, 26]);
      expect(rows.first.name, contains('C1'));
      expect(stepsAvailable(tr(TrackKind.sampler, zones: zs)), isTrue);
    });

    test('zonas na mesma nota dividem a linha; a nota base é limitada à faixa', () {
      final a = SamplerZone(id: 'a', sample: 's', root: 60, lo: 60, hi: 60);
      final b = SamplerZone(id: 'b', sample: 's', root: 60, lo: 60, hi: 60, vlo: 64);
      final c = SamplerZone(id: 'c', sample: 's', root: 90, lo: 50, hi: 70);
      final rows = zoneRows(DawTrack(id: 't', name: 'x', color: 0, kind: TrackKind.sampler, zones: [a, b, c]));
      expect(rows.map((r) => r.pitch), [60, 70]);
    });
  });

  test('sortNotes ordena pelo início e é estável', () {
    final a = note(1, 1.0), b = note(2, 0.0), c = note(3, 1.0);
    final l = [a, b, c];
    sortNotes(l);
    expect(l, [b, a, c]);
  });
}
