// Fase 7, estrutura e navegação: marcadores, seções e loops, zoom, minimapa, régua e os menus da
// barra (sem overflow no celular e no computador).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jopendaw_app/audio/engine.dart';
import 'package:jopendaw_app/daw/minimap.dart';
import 'package:jopendaw_app/daw/model.dart';

import 'controller_test.dart' show newController;
import 'studio_test.dart' show studio, mount, flushSave;

void main() {
  setUp(() => AudioEngine.instance.log = []);

  group('marcadores', () {
    test('criar no cursor, sem duplicar no mesmo ponto, ordenados', () {
      final c = newController();
      c.beat.value = 8;
      final a = c.addMarker();
      expect(a.beat, 8);
      expect(c.addMarker().id, a.id, reason: 'no mesmo ponto devolve o que existe');
      c.beat.value = 2;
      c.addMarker(name: 'Intro');
      expect(c.doc.markers.map((m) => m.beat), [2, 8]);
      expect(c.doc.markers.first.name, 'Intro');
      c.dispose();
    });

    test('mover, renomear, recolorir e apagar são desfazíveis', () {
      final c = newController();
      final m = c.addMarker(beat: 4, name: 'A');
      c.moveMarker(m.id, 12);
      expect(c.doc.markers.single.beat, 12);
      c.undo();
      expect(c.doc.markers.single.beat, 4);
      c.renameMarker(m.id, 'Refrão');
      c.recolorMarker(m.id, 0xFF112233);
      expect(c.doc.markers.single.name, 'Refrão');
      c.undo();
      c.undo();
      expect(c.doc.markers.single.name, 'A');
      c.removeMarker(m.id);
      expect(c.doc.markers, isEmpty);
      c.undo();
      expect(c.doc.markers, hasLength(1));
      c.undo();
      expect(c.doc.markers, isEmpty, reason: 'desfazer a criação');
      c.dispose();
    });

    test('mover por cima de outro reordena a lista', () {
      final c = newController();
      final a = c.addMarker(beat: 4);
      c.addMarker(beat: 8);
      c.moveMarker(a.id, 16);
      expect(c.doc.markers.map((m) => m.beat), [8, 16]);
      c.dispose();
    });

    test('pular para o marcador anterior e o seguinte', () {
      final c = newController();
      for (final b in [4.0, 8.0, 16.0]) {
        c.addMarker(beat: b);
      }
      c.beat.value = 0;
      expect(c.jumpToNextMarker(), isTrue);
      expect(c.beat.value, 4);
      c.jumpToNextMarker();
      expect(c.beat.value, 8);
      c.jumpToPreviousMarker();
      expect(c.beat.value, 4, reason: 'parado num marcador, o anterior é o vizinho');
      c.jumpToPreviousMarker();
      expect(c.beat.value, 0, reason: 'sem marcador antes, volta ao começo');
      c.beat.value = 16;
      expect(c.jumpToNextMarker(), isFalse);
      c.dispose();
    });
  });

  group('loop', () {
    test('loop da seção onde o cursor está, e entre marcadores', () {
      final c = newController();
      c.doc.tracks.first.clips.add(AudioClip(id: 'x', sample: 's', start: 0, length: 60)); // 120 batidas
      c.addMarker(beat: 8);
      c.addMarker(beat: 24);
      c.addMarker(beat: 40);
      c.beat.value = 2;
      expect(c.canLoopSection, isFalse, reason: 'antes do primeiro marcador não há seção');
      c.beat.value = 10;
      expect(c.loopSection(), isTrue);
      expect((c.doc.loopStart, c.doc.loopEnd, c.doc.loopOn), (8.0, 24.0, true));
      c.beat.value = 100;
      c.loopSection();
      expect((c.doc.loopStart, c.doc.loopEnd), (40.0, 120.0), reason: 'a última seção vai até o fim do arranjo');
      c.selectedMarker = null;
      c.loopBetweenMarkers();
      expect((c.doc.loopStart, c.doc.loopEnd), (8.0, 40.0), reason: 'sem seleção: primeiro ao último');
      c.selectedMarker = c.doc.markers[1].id;
      c.loopBetweenMarkers();
      expect((c.doc.loopStart, c.doc.loopEnd), (24.0, 40.0));
      c.undo();
      expect((c.doc.loopStart, c.doc.loopEnd), (8.0, 40.0));
      c.dispose();
    });

    test('loop na seleção usa o clipe selecionado', () {
      final c = newController();
      c.doc.tracks.first.clips.add(AudioClip(id: 'x', sample: 's', start: 4, length: 2)); // 4 batidas
      expect(c.loopSelection(), isFalse);
      c.selectClip('x');
      expect(c.loopSelection(), isTrue);
      expect((c.doc.loopStart, c.doc.loopEnd, c.doc.loopOn), (4.0, 8.0, true));
      c.dispose();
    });
  });

  group('visão', () {
    test('enquadrar tudo e a seleção', () {
      final c = newController();
      c.viewWidth = 1000;
      c.doc.tracks.first.clips.add(AudioClip(id: 'x', sample: 's', start: 16, length: 8)); // 16..32
      c.fitAll();
      expect(c.scrollBeat, 0);
      expect(c.pxPerBeat * c.arrangementEnd, lessThanOrEqualTo(1000));
      expect(c.pxPerBeat * c.arrangementEnd, greaterThan(850));
      c.selectClip('x');
      c.fitSelection();
      expect(c.scrollBeat, closeTo(16 - 16 * 0.04, 1e-9));
      expect(c.pxPerBeat, greaterThan(50));
      c.dispose();
    });

    test('duração do projeto', () {
      final c = newController();
      c.doc.tracks.first.clips.add(AudioClip(id: 'x', sample: 's', start: 0, length: 195)); // 3:15
      expect(c.doc.durationSeconds, closeTo(195, 1e-9));
      expect(formatClock(195), '3:15');
      expect(formatClock(3725), '1:02:05');
      expect(formatClock(5.26, tenths: true), '0:05.2');
      c.dispose();
    });
  });

  test('documento antigo, sem marcadores, abre; com marcadores, ida e volta', () {
    final old = jsonDecode(jsonEncode(newController().doc.toJson())) as Map<String, dynamic>..remove('markers');
    expect(DawDoc.fromJson(old).markers, isEmpty);
    final d = DawDoc.fromJson(old)..markers = [Marker(id: 'b', beat: 9, name: 'B'), Marker(id: 'a', beat: 1.5, name: 'A', color: 0xFF00FF00)];
    final back = DawDoc.fromJson(jsonDecode(jsonEncode(d.toJson())));
    expect(back.markers.map((m) => (m.id, m.beat, m.name, m.color)), [('a', 1.5, 'A', 0xFF00FF00), ('b', 9.0, 'B', 0xFFE3B341)]);
  });

  for (final (label, size) in [('celular', const Size(360, 780)), ('computador', const Size(1400, 900))]) {
    group(label, () {
      testWidgets('minimapa, bandeirinhas e menus sem overflow', (t) async {
        final c = studio();
        c.doc.tracks.first.clips.add(AudioClip(id: 'x', sample: 's', start: 2, length: 6));
        c.addMarker(beat: 0.5, name: 'Um marcador com um nome bem comprido');
        c.addMarker(beat: 3.5, name: 'Ponte');
        await mount(t, c, size);
        expect(find.byType(CustomPaint), findsWidgets);
        expect(find.text('Visão geral'), findsOneWidget);
        expect(find.text('Ponte'), findsOneWidget);
        expect(t.takeException(), isNull);

        for (final tip in ['Seções e marcadores (M cria um no cursor)', 'Visão: enquadrar, altura das faixas, seguir o cursor']) {
          await t.ensureVisible(find.byTooltip(tip));
          await t.tap(find.byTooltip(tip));
          await t.pumpAndSettle();
          expect(t.takeException(), isNull, reason: tip);
          await t.tapAt(const Offset(2, 2));
          await t.pumpAndSettle();
        }
        await flushSave(t);
      });

      testWidgets('o menu Seções leva o cursor ao marcador', (t) async {
        final c = studio();
        c.addMarker(beat: 12, name: 'Ponte');
        c.beat.value = 0;
        await mount(t, c, size);
        final tip = find.byTooltip('Seções e marcadores (M cria um no cursor)');
        await t.ensureVisible(tip);
        await t.tap(tip);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        await t.tap(find.text('Ponte').last);
        await t.pumpAndSettle();
        expect(c.beat.value, 12);
        await flushSave(t);
      });

      testWidgets('clicar no minimapa rola a janela', (t) async {
        final c = studio();
        c.doc.tracks.first.clips.add(AudioClip(id: 'x', sample: 's', start: 0, length: 120)); // 240 batidas
        await mount(t, c, size);
        expect(c.scrollBeat, 0);
        final box = t.getRect(find.byType(Minimap));
        await t.tapAt(Offset(box.left + box.width * 0.9, box.center.dy));
        await t.pump();
        expect(c.scrollBeat, greaterThan(100));
        await flushSave(t);
      });
    });
  }

  testWidgets('teclas: M cria, [ ] pulam, Z enquadra, Shift+L faz o loop do clipe', (t) async {
    final c = studio();
    await mount(t, c, const Size(1400, 900));
    c.beat.value = 8;
    await t.sendKeyEvent(LogicalKeyboardKey.keyM);
    await t.pump();
    expect(c.doc.markers.map((m) => m.beat), [8]);
    await t.sendKeyEvent(LogicalKeyboardKey.bracketLeft);
    expect(c.beat.value, 0);
    await t.sendKeyEvent(LogicalKeyboardKey.bracketRight);
    expect(c.beat.value, 8);
    await t.sendKeyEvent(LogicalKeyboardKey.keyZ);
    expect(c.scrollBeat, 0);
    c.selectClip('m1');
    await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.keyL);
    await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect((c.doc.loopStart, c.doc.loopEnd, c.doc.loopOn), (0.0, 4.0, true));
    await flushSave(t);
  });

  testWidgets('alternar a régua entre compassos e tempo pelo rótulo', (t) async {
    final c = studio();
    await mount(t, c, const Size(400, 820));
    await t.tap(find.text('comp.'));
    await t.pump();
    expect(c.rulerTime, isTrue);
    expect(find.text('mm:ss'), findsWidgets);
    expect(t.takeException(), isNull);
    await flushSave(t);
  });
}
