// Fase 19 A: os achados do sequenciador de passos (swing derivado do documento, swing no clipe todo,
// padrões em outros compassos, repetir sem efeito colateral, nomes de zona, diálogo de padrões).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jopendaw_app/daw/instruments.dart';
import 'package:jopendaw_app/daw/model.dart';
import 'package:jopendaw_app/daw/sampler_zones.dart';
import 'package:jopendaw_app/daw/step_sequencer.dart';

import 'step_sequencer_ui_test.dart' show StepDaw, host, setView, starts;

StepLayout layout({double step = 0.25, int bars = 1, double swing = 0, double bar = 4}) => StepLayout.of(barBeats: bar, bars: bars, step: step, swing: swing);

MidiNote note(int pitch, double start, [double v = 0.8]) => MidiNote(pitch: pitch, start: start, length: 0.25, velocity: v);

List<String> keys(Iterable<MidiNote> ns) => [for (final n in ns) '${n.pitch}@${n.start.toStringAsFixed(6)}v${n.velocity.toStringAsFixed(2)}']..sort();

void main() {
  group('puro', () {
    test('detectSwing lê o swing das notas, por resolução, e empate fica reto', () {
      final full = layout(bars: 2);
      expect(detectSwing([], full), 0);
      expect(detectSwing([for (var i = 0; i < 8; i++) note(42, i * 0.25)], full), 0);
      final swung = [for (var i = 0; i < 8; i++) note(42, i * 0.25 + (i.isOdd ? 0.25 * 0.4 : 0))];
      expect(detectSwing(swung, full), closeTo(0.4, 1e-9));
      expect(detectSwing([note(36, 0), note(36, 0.5)], full), 0, reason: 'só passos pares');
      expect(detectSwing(swung, layout(step: 0.5, bars: 2)), 0, reason: 'em 1/8 são só colcheias retas');
      final n = [for (var i = 0; i < 16; i++) note(42, i * 0.25)];
      retimeSwing(n, full, 0, 0.6);
      expect(detectSwing(n, full), closeTo(0.6, 1e-9));
      retimeSwing(n, full, 0.6, 0);
      expect(detectSwing(n, full), 0);
    });

    test('covering estende a grade ao clipe e o swing anda além do padrão', () {
      final l = layout();
      final c = l.covering(8);
      expect(c.steps, 32);
      final notes = [note(42, 0.25), note(42, 5.25)];
      expect(retimeSwing(notes, l, 0, 0.5), 1, reason: 'a grade do padrão só enxerga a primeira');
      expect(retimeSwing(notes, c, 0, 0.5), 1, reason: 'a do clipe alcança a do compasso 2 (a primeira já está no swing)');
      expect(notes[1].start, closeTo(5.25 + 0.125, 1e-9));
    });

    test('repetir sem notas no padrão não mexe em nada', () {
      final l = layout();
      final notes = [note(60, 5.0), note(36, 6.0)];
      expect(canRepeatPattern(notes, l, 8), isFalse);
      expect(repeatPattern(notes, l, 8), 0);
      expect(notes.length, 2);
      expect(canRepeatPattern([note(36, 0)], l, 8), isTrue);
      expect(canRepeatPattern([note(36, 0)], l, 4), isFalse);
    });

    test('rock: a descrição confere com o desenho; nenhum texto de padrão tem aspas duplas', () {
      final p = stepPresets.firstWhere((x) => x.id == 'rock');
      final kick = p.rows.firstWhere((r) => r.pitch == 36).pattern;
      expect([for (var i = 0; i < kick.length; i++) if (kick[i] != '.') i + 1], [1, 9, 11]);
      expect(p.about, contains('Bumbo no 1, no 3 e no passo 11'));
      for (final q in stepPresets) {
        expect(q.name.contains('"') || q.about.contains('"'), isFalse);
      }
    });

    test('padrões em compassos de 3 tempos cortam o desenho; em 6 e 7 repetem', () {
      final four = stepPresets.firstWhere((x) => x.id == 'four');
      final n3 = presetNotes(four, barBeats: 3);
      expect(n3.every((n) => n.start < 3 - 1e-9), isTrue);
      expect(n3.where((n) => n.pitch == 36).map((n) => n.start).toList()..sort(), [0.0, 1.0, 2.0]);
      expect(n3.where((n) => n.pitch == 39).map((n) => n.start).toList(), [1.0]);
      final n6 = presetNotes(four, barBeats: 6);
      expect(n6.where((n) => n.pitch == 36).map((n) => n.start).toList()..sort(), [0.0, 1.0, 2.0, 3.0, 4.0, 5.0]);
      expect(keys(presetNotes(four, barBeats: 4)), keys(presetNotes(four)));
      final notes = [note(36, 3.25)];
      applyPreset(notes, four, barBeats: 3);
      expect(notes.any((n) => n.pitch == 36 && n.start == 3.25), isTrue, reason: 'fora do compasso de 3 tempos');
      for (final p in stepPresets) {
        for (final b in [3.0, 6.0, 7.0]) {
          expect(presetNotes(p, barBeats: b).every((n) => n.start < p.bars * b - 1e-9), isTrue, reason: '${p.id} $b');
        }
      }
    });

    test('zonas de áudio inteiro levam o nome da zona; fatias seguem Fatia N', () {
      final whole = [SamplerZone(id: 'a', sample: 's', root: 48, lo: 48, hi: 59), SamplerZone(id: 'b', sample: 's', root: 60, lo: 60, hi: 71)];
      final rows = zoneRows(DawTrack(id: 't', name: 'x', color: 0, kind: TrackKind.sampler, zones: whole));
      expect(rows.map((r) => r.name), ['Zona · ${noteName(48)}', 'Zona · ${noteName(60)}']);
      var n = 0;
      final slices = sliceZones('abc', [0.0, 0.5, 1.0], () => 'z${n++}');
      final s = zoneRows(DawTrack(id: 't', name: 'x', color: 0, kind: TrackKind.sampler, zones: slices));
      expect(s.map((r) => r.name.split(' ').first), ['Fatia', 'Fatia', 'Fatia']);
      expect(s[1].name, startsWith('Fatia 2'));
    });
  });

  group('aba', () {
    final apply = find.byKey(const ValueKey('step-swing-apply'));
    final off = find.byKey(const ValueKey('step-swing-off'));
    final slider = find.byKey(const ValueKey('step-swing'));

    Future<void> menu(WidgetTester t, String label) async {
      await t.tap(find.byKey(const ValueKey('step-actions')));
      await t.pumpAndSettle();
      await t.tap(find.text(label));
      await t.pumpAndSettle();
    }

    Future<void> setSwing(WidgetTester t) async {
      await t.drag(slider, const Offset(30, 0));
      await t.pump();
      await t.tap(apply);
      await t.pump();
    }

    Future<void> pickRes(WidgetTester t, String text) async {
      await t.tap(find.byKey(const ValueKey('step-res')));
      await t.pumpAndSettle();
      await t.tap(find.textContaining(text).last);
      await t.pumpAndSettle();
    }

    List<MidiNote> sixteenths() => [for (var i = 0; i < 16; i++) MidiNote(pitch: 42, start: i * 0.25, length: 0.25)];

    testWidgets('1: desfazer após aplicar swing desfaz também o swing', (t) async {
      await setView(t, 1000, 520);
      final c = StepDaw(notes: sixteenths());
      await t.pumpWidget(host(c, width: 1000));
      await setSwing(t);
      expect(t.widget<TextButton>(off).onPressed, isNotNull);
      expect(t.widget<TextButton>(apply).onPressed, isNull);
      c.undo();
      await t.pump();
      expect(starts(c, 42)[1], 0.25);
      expect(t.widget<TextButton>(off).onPressed, isNull);
      expect(t.widget<Slider>(slider).value, 0);
      c.redo();
      await t.pump();
      expect(t.widget<TextButton>(off).onPressed, isNotNull);
      expect(starts(c, 42)[1], greaterThan(0.25));
      await t.pump(const Duration(seconds: 1));
    });

    testWidgets('2: clipe que já tem swing nas notas abre na grade e deixa tirar o swing', (t) async {
      await setView(t, 1000, 520);
      final c = StepDaw(notes: [for (var i = 0; i < 16; i++) MidiNote(pitch: 42, start: i * 0.25 + (i.isOdd ? 0.125 : 0), length: 0.25)]);
      await t.pumpWidget(host(c, width: 1000));
      expect(t.widget<Slider>(slider).value, 50);
      expect(t.widget<TextButton>(off).onPressed, isNotNull);
      expect(readRow(c.clip.notes, 42, layout(swing: 0.5)).values.every((h) => !h.offGrid), isTrue);
      await t.tap(off);
      await t.pump();
      expect(starts(c, 42), [for (var i = 0; i < 16; i++) i * 0.25]);
      await t.pump(const Duration(seconds: 1));
    });

    testWidgets('3: Padrões com swing aplicado entra reto, zera o swing e desfaz num passo só', (t) async {
      await setView(t, 1000, 520);
      final c = StepDaw(notes: sixteenths());
      await t.pumpWidget(host(c, width: 1000));
      await setSwing(t);
      await t.tap(find.byKey(const ValueKey('step-presets')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('step-preset-rock')));
      await t.pumpAndSettle();
      expect(starts(c, 42), [0.0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5]);
      expect(starts(c, 36), [0.0, 2.0, 2.5]);
      expect(t.widget<Slider>(slider).value, 0);
      expect(t.widget<TextButton>(off).onPressed, isNull);
      c.undo();
      await t.pump();
      expect(t.widget<TextButton>(off).onPressed, isNotNull, reason: 'o swing volta junto com as notas');
      await t.pump(const Duration(seconds: 1));
    });

    testWidgets('4: swing vale no clipe inteiro, além dos compassos do padrão', (t) async {
      await setView(t, 1000, 520);
      final c = StepDaw(clipLength: 8, notes: [for (var i = 0; i < 32; i++) MidiNote(pitch: 42, start: i * 0.25, length: 0.25)]);
      await t.pumpWidget(host(c, width: 1000));
      await t.tap(find.byKey(const ValueKey('step-bars-minus')));
      await t.pump();
      expect(t.widget<Text>(find.byKey(const ValueKey('step-bars'))).data, '1');
      await setSwing(t);
      final s = starts(c, 42);
      expect(s[5], greaterThan(1.25), reason: 'compasso 2 também ganhou swing');
      expect(s[21], greaterThan(5.25));
      await t.tap(off);
      await t.pump();
      expect(starts(c, 42), [for (var i = 0; i < 32; i++) i * 0.25]);
      await t.pump(const Duration(seconds: 1));
    });

    testWidgets('4: repetir sem notas no padrão não apaga o resto nem deixa passo vazio no desfazer', (t) async {
      await setView(t, 1000, 520);
      final c = StepDaw(clipLength: 8, notes: [MidiNote(pitch: 60, start: 5.0, length: 0.5), MidiNote(pitch: 36, start: 6.0, length: 0.25)]);
      await t.pumpWidget(host(c, width: 1000));
      await t.tap(find.byKey(const ValueKey('step-bars-minus')));
      await t.pump();
      final before = c.historyCount;
      await menu(t, 'Repetir até o fim do clipe');
      expect(c.clip.notes.length, 2);
      expect(c.historyCount, before);
      expect(find.text('Não há notas no padrão para repetir.'), findsOneWidget);
      await t.pump(const Duration(seconds: 1));
    });

    testWidgets('4: repetir com o padrão do tamanho do clipe também não cria passo no desfazer', (t) async {
      await setView(t, 1000, 520);
      final c = StepDaw(notes: [MidiNote(pitch: 36, start: 0, length: 0.25)]);
      await t.pumpWidget(host(c, width: 1000));
      final before = c.historyCount;
      await menu(t, 'Repetir até o fim do clipe');
      expect(c.historyCount, before);
      expect(find.text('O padrão já ocupa o clipe inteiro.'), findsOneWidget);
      await t.pump(const Duration(seconds: 1));
    });

    testWidgets('5: swing em 1/8 anda os contratempos; sem notas nos passos pares explica em vez de editar', (t) async {
      await setView(t, 1000, 520);
      final c = StepDaw(notes: [for (var i = 0; i < 8; i++) MidiNote(pitch: 42, start: i * 0.5, length: 0.25)]);
      await t.pumpWidget(host(c, width: 1000));
      await pickRes(t, '1/8 ·');
      await setSwing(t);
      final s = starts(c, 42);
      expect(s[0], 0.0);
      expect(s[1], greaterThan(0.5));
      expect(s[2], 1.0);
      expect(t.widget<TextButton>(off).onPressed, isNotNull);

      final d = StepDaw(notes: [MidiNote(pitch: 42, start: 0.25, length: 0.25)]);
      await t.pumpWidget(host(d, width: 1000));
      await pickRes(t, '1/8 ·');
      await t.drag(slider, const Offset(30, 0));
      await t.pump();
      final before = d.historyCount;
      await t.tap(apply);
      await t.pump();
      expect(find.textContaining('Nenhuma nota está nos passos pares de 1/8'), findsOneWidget);
      expect(d.historyCount, before);
      expect(starts(d, 42), [0.25]);
      await t.pump(const Duration(seconds: 1));
    });

    testWidgets('7: Padrões em 3/4 usa as batidas do compasso', (t) async {
      await setView(t, 1000, 520);
      final c = StepDaw(beatsPerBar: 3, clipLength: 3);
      await t.pumpWidget(host(c, width: 1000));
      await t.tap(find.byKey(const ValueKey('step-presets')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('step-preset-four')));
      await t.pumpAndSettle();
      expect(starts(c, 36), [0.0, 1.0, 2.0]);
      expect(starts(c, 39), [1.0]);
      expect(t.widget<Text>(find.byKey(const ValueKey('step-bars'))).data, '1');
      await t.pump(const Duration(seconds: 1));
    });

    testWidgets('9: o aviso do padrão não leva aspas duplas', (t) async {
      await setView(t, 1000, 520);
      final c = StepDaw();
      await t.pumpWidget(host(c, width: 1000));
      await t.tap(find.byKey(const ValueKey('step-presets')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('step-preset-rock')));
      await t.pumpAndSettle();
      final text = t.widget<Text>(find.byKey(const ValueKey('step-notice'))).data!;
      expect(text, 'Padrão Rock aplicado.');
      await t.pump(const Duration(seconds: 1));
    });

    for (final (w, h) in [(360.0, 640.0), (1512.0, 900.0)]) {
      testWidgets('10: o 9º padrão (shuffle) aparece e dá para escolher em ${w.round()} px', (t) async {
        await setView(t, w, h);
        final c = StepDaw();
        await t.pumpWidget(host(c, width: w, height: h));
        // a barra rola na horizontal no celular: o botão pode estar além da borda
        await t.ensureVisible(find.byKey(const ValueKey('step-presets')));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const ValueKey('step-presets')));
        await t.pumpAndSettle();
        expect(stepPresets.length, greaterThanOrEqualTo(9));
        final tile = find.byKey(const ValueKey('step-preset-shuffle'));
        expect(tile, findsOneWidget);
        await t.ensureVisible(tile);
        await t.pumpAndSettle();
        final screen = Offset.zero & Size(w, h);
        expect(screen.contains(t.getTopLeft(tile)) && screen.contains(t.getBottomRight(tile)), isTrue, reason: 'inteiro na tela depois de rolar');
        expect(t.takeException(), isNull);
        await t.tap(tile);
        await t.pumpAndSettle();
        expect(starts(c, 36), [0.0, 2.0]);
        expect(find.text('Padrão Shuffle (tercinas) aplicado.'), findsOneWidget);
        await t.pump(const Duration(seconds: 1));
      });
    }

    testWidgets('8: sampler multi-sample sem fatiar mostra o nome da zona, não Fatia N', (t) async {
      await setView(t, 1000, 520);
      final zones = [SamplerZone(id: 'a', sample: 's1', root: 48, lo: 48, hi: 59), SamplerZone(id: 'b', sample: 's2', root: 60, lo: 60, hi: 71)];
      final c = StepDaw(kind: TrackKind.sampler, zones: zones);
      await t.pumpWidget(host(c, width: 1000));
      expect(find.textContaining('Fatia'), findsNothing);
      expect(find.text('Zona · ${noteName(48)}'), findsOneWidget);
      expect(find.text('Zona · ${noteName(60)}'), findsOneWidget);
      await t.pump(const Duration(seconds: 1));
    });
  });
}
