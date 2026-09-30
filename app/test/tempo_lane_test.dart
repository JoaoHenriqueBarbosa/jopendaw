// Fase 10, mapa de andamento na tela: a faixa de andamento sob a régua, o botão de andamento da
// barra e o diálogo de mudança de compasso (sem estouro no computador e no celular).
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jopendaw_app/audio/engine.dart';
import 'package:jopendaw_app/daw/tempo_lane.dart';
import 'package:jopendaw_app/daw/tempo_map.dart';

import 'studio_test.dart' show studio, mount, flushSave;

void main() {
  setUp(() => AudioEngine.instance.log = []);

  for (final (label, size) in [('computador', const Size(1400, 900)), ('celular', const Size(400, 820))]) {
    testWidgets('$label: régua, grade, faixa de andamento e barra com mapas montam sem erro', (t) async {
      final c = studio();
      c.setTempoMap(const [TempoPoint(0, 90, ramp: true), TempoPoint(8, 150), TempoPoint(16, 60)]);
      c.setMeterMap(const [MeterChange(1, 4, 4), MeterChange(3, 6, 8), MeterChange(5, 7, 8), MeterChange(7, 3, 4)]);
      await mount(t, c, size);
      expect(find.byType(TempoLane), findsOneWidget, reason: 'com mapa a faixa aparece sozinha');
      expect(t.takeException(), isNull);
      // zoom e rolagem passam por outros trechos da grade
      for (final ppb in [8.0, 40.0, 200.0]) {
        c.pxPerBeat = ppb;
        c.scrollBeat = 3;
        c.notifyListeners();
        await t.pump();
        expect(t.takeException(), isNull, reason: 'zoom $ppb');
      }
      c.toggleRulerTime();
      await t.pump();
      expect(t.takeException(), isNull, reason: 'régua em segundos');
      // sem mapa, sem faixa; ligar e desligar à mão
      c.setTempoMap(const []);
      await t.pump();
      expect(find.byType(TempoLane), findsNothing);
      c.toggleTempoLane();
      await t.pump();
      expect(find.byType(TempoLane), findsOneWidget);
      expect(t.takeException(), isNull);
      await flushSave(t);
    });
  }

  testWidgets('duplo clique adiciona, arrastar muda o BPM, menu apaga e alterna salto e rampa', (t) async {
    final c = studio();
    c.toggleTempoLane();
    await mount(t, c, const Size(1400, 900));
    final lane = t.getRect(find.byType(TempoLane));
    Offset at(double beat, [double dy = 11]) => Offset(lane.left + (beat - c.scrollBeat) * c.pxPerBeat, lane.top + dy);

    // duplo clique no vazio: ponto novo no andamento vigente, encaixado na grade
    await t.tapAt(at(8));
    await t.pump(kDoubleTapMinTime);
    await t.tapAt(at(8));
    await t.pump(const Duration(milliseconds: 400));
    expect(c.doc.tempo.points.map((p) => (p.beat, p.bpm)), [(0.0, 120.0), (8.0, 120.0)]);

    // arrastar o ponto para cima: 20 px = +10 BPM
    await t.dragFrom(at(8), const Offset(0, -20));
    await t.pump();
    expect(c.doc.tempo.points[1].bpm, 130);
    expect(c.doc.tempo.points[1].beat, 8);
    // e para o lado (16 = 8 batidas)
    await t.dragFrom(at(8), Offset(8 * c.pxPerBeat, 0));
    await t.pump();
    expect(c.doc.tempo.points[1].beat, 16);
    // desfazer o último arraste volta o ponto, o penúltimo o BPM
    c.undo();
    expect(c.doc.tempo.points[1].beat, 8);
    c.undo();
    expect(c.doc.tempo.points[1].bpm, 120);
    c.redo();
    c.redo();

    // botão direito: rampa e apagar
    Future<void> menu(Offset p, String item) async {
      final g = await t.startGesture(p, kind: PointerDeviceKind.mouse, buttons: kSecondaryButton);
      await g.up();
      await t.pumpAndSettle();
      await t.tap(find.text(item));
      await t.pumpAndSettle();
    }

    await menu(at(0), 'Rampa até o próximo ponto');
    expect(c.doc.tempo.points[0].ramp, isTrue);
    await menu(at(0), 'Salto até o próximo ponto');
    expect(c.doc.tempo.points[0].ramp, isFalse);
    await menu(at(16), 'Apagar o ponto');
    expect(c.doc.tempoMap, isEmpty);
    expect(t.takeException(), isNull);
    await flushSave(t);
  });

  testWidgets('botão de andamento mostra o vigente no cursor; diálogo muda o compasso a partir de um compasso', (t) async {
    final c = studio();
    c.setTempoMap(const [TempoPoint(0, 100), TempoPoint(4, 140, ramp: false)]);
    await mount(t, c, const Size(1400, 900));
    expect(find.text('100 BPM · 4/4'), findsOneWidget);
    c.beat.value = 6;
    await t.pump();
    expect(find.text('140 BPM · 4/4'), findsOneWidget);
    // abre o diálogo pelo botão, vai à mudança de compasso
    await t.tap(find.text('140 BPM · 4/4'));
    await t.pumpAndSettle();
    expect(find.text('BPM inicial'), findsOneWidget);
    await t.tap(find.text('Mudar compasso a partir de um compasso…'));
    await t.pumpAndSettle();
    expect(find.textContaining('Mudar compasso a partir do compasso 2'), findsOneWidget, reason: 'batida 6 = compasso 2');
    await t.enterText(find.byType(TextField).first, '4');
    await t.pump();
    expect(find.textContaining('a partir do compasso 4'), findsOneWidget);
    await t.tap(find.text('Aplicar'));
    await t.pumpAndSettle();
    // 4/4 já vale: nada muda; com outro compasso, muda
    expect(c.doc.meterMap, isEmpty);
    await t.tap(find.text('140 BPM · 4/4'));
    await t.pumpAndSettle();
    await t.tap(find.text('Mudar compasso a partir de um compasso…'));
    await t.pumpAndSettle();
    await t.tap(find.byType(DropdownButtonFormField<int>).first);
    await t.pumpAndSettle();
    await t.tap(find.text('3').last);
    await t.pumpAndSettle();
    await t.tap(find.text('Aplicar'));
    await t.pumpAndSettle();
    expect(c.doc.meterMap, const [MeterChange(1, 4, 4), MeterChange(2, 3, 4)]);
    expect(t.takeException(), isNull);
    await flushSave(t);
  });
}
