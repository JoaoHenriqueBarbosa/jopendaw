// Automação na linha do tempo: a conta da curva (a mesma do motor) e o uso da tela inteira — menu
// A, sub-raias alinhadas aos cabeçalhos, criar/mover/apagar pontos, curva, seleção por retângulo,
// desfazer, barramento, master e o celular de 360 px. O controlador de teste implementa só o que a
// linha do tempo pede do contrato da fase 3 (automatable, addLane, removeLane, targetRange,
// addBusTrack, showEffects), do jeito mais direto.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Curve;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jopendaw_app/audio/engine.dart';
import 'package:jopendaw_app/daw/automation_lane.dart';
import 'package:jopendaw_app/daw/controller.dart';
import 'package:jopendaw_app/daw/instruments.dart';
import 'package:jopendaw_app/daw/model.dart';
import 'package:jopendaw_app/models/project.dart';
import 'package:jopendaw_app/screens/project_screen.dart';
import 'package:jopendaw_app/widgets/theme.dart';

final _project = Project.fromJson({
  'id': 'p',
  'name': 'Teste',
  'bpm': 120,
  'beats_per_bar': 4,
  'beat_unit': 4,
  'sample_rate': 48000,
  'created_at': '2026-01-01T00:00:00Z',
  'updated_at': '2026-01-01T00:00:00Z',
});

class TestDaw extends DawController {
  TestDaw() : super(_project);

  List<AutoLane> _lanes(int track) => track < 0 ? doc.masterLanes : doc.tracks[track].lanes;

  @override
  List<(AutoTarget, String)> automatable(int track) => [
    (const AutoTarget(AutoKind.volume), 'Volume'),
    (const AutoTarget(AutoKind.pan), 'Pan'),
    if (track >= 0)
      for (final p in doc.tracks[track].kind.params) (AutoTarget(AutoKind.instrument, param: p.id), '${p.group}: ${p.name}'),
  ];

  @override
  AutoLane addLane(int track, AutoTarget target) {
    final old = _lanes(track).where((l) => l.target == target).firstOrNull;
    if (old != null) {
      edit((_) => old.open = true);
      return old;
    }
    final lane = AutoLane(id: newId(), target: target);
    edit((_) => _lanes(track).add(lane));
    return lane;
  }

  @override
  void removeLane(int track, String laneId) => edit((_) => _lanes(track).removeWhere((l) => l.id == laneId));

  @override
  (double, double, double) targetRange(int track, AutoTarget target) {
    final t = track < 0 ? null : doc.tracks[track];
    switch (target.kind) {
      case AutoKind.volume:
        return (0, 2, t?.gain ?? doc.masterGain);
      case AutoKind.pan:
        return (-1, 1, t?.pan ?? doc.masterPan);
      case AutoKind.instrument:
        final p = t!.kind.params.firstWhere((p) => p.id == target.param);
        return (p.min, p.max, t.param(p.id));
      case AutoKind.effect || AutoKind.send:
        return (0, 1, 0);
    }
  }

  @override
  void addBusTrack() => edit((d) {
    d.tracks.add(DawTrack(id: newId(), name: 'Barramento 1', color: d.tracks.length, kind: TrackKind.bus));
    selectedTrack = d.tracks.length - 1;
  });

  @override
  void showEffects(int track) {
    effectsTrack = track;
    setDock(Dock.effects);
  }
}

TestDaw studio() {
  final c = TestDaw();
  c.doc = DawDoc(
    bpm: 120,
    beatsPerBar: 4,
    tracks: [
      DawTrack(
        id: 'a',
        name: 'Áudio 1',
        color: 0,
        clips: [AudioClip(id: 'c1', sample: 'x', start: 0, length: 1)],
      ),
      DawTrack(
        id: 's',
        name: 'Sintetizador 1',
        color: 1,
        kind: TrackKind.synth,
        midi: [MidiClip(id: 'm1', name: 'Riff', start: 0, length: 4)],
      ),
      DawTrack(id: 'b', name: 'Áudio 2', color: 2),
    ],
  );
  c.doc.samples['x'] = SampleInfo('x.wav', 1);
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

Future<void> flushSave(WidgetTester t) => t.pump(const Duration(seconds: 1));

/// Abre (ou cria) a automação de volume da faixa pelo controlador e devolve a raia.
AutoLane volumeLane(TestDaw c, int track) => c.addLane(track, const AutoTarget(AutoKind.volume));

/// Ponto da tela para (batida, posição 0..1) dentro do editor da raia.
Offset at(WidgetTester t, TestDaw c, AutoLane lane, double beat, double norm) {
  final r = t.getRect(find.byKey(ValueKey('auto:${lane.id}')));
  const pad = 7.0;
  return Offset(r.left + (beat - c.scrollBeat) * c.pxPerBeat, r.top + pad + (1 - norm) * (r.height - 2 * pad));
}

Future<void> doubleTapAt(WidgetTester t, Offset p) async {
  await t.tapAt(p);
  await t.pump(const Duration(milliseconds: 60));
  await t.tapAt(p);
  await t.pump();
}

Future<void> mouseDrag(WidgetTester t, Offset from, Offset to, {int steps = 8}) async {
  final g = await t.startGesture(from, kind: PointerDeviceKind.mouse);
  for (var i = 1; i <= steps; i++) {
    await g.moveTo(Offset.lerp(from, to, i / steps)!);
    await t.pump();
  }
  await g.up();
  await t.pump();
}

void main() {
  setUp(() => AudioEngine.instance.log = []);

  group('curva', () {
    test('forma t^(2^(curva·3)): reta, côncava, convexa e limites', () {
      expect(autoShape(0.5, 0), 0.5);
      expect(autoShape(0.5, 1), closeTo(0.5 * 0.5 * 0.5 * 0.5 * 0.5 * 0.5 * 0.5 * 0.5, 1e-12)); // t^8
      expect(autoShape(0.5, -1), closeTo(0.917, 1e-3)); // t^(1/8)
      expect(autoShape(0, 0.7), 0);
      expect(autoShape(1, -0.7), 1);
    });

    test('valor numa batida: parado antes e depois, curva entre pontos, degrau em pontos na mesma batida', () {
      final pts = [
        AutoPoint(beat: 2, value: 0),
        AutoPoint(beat: 4, value: 1, curve: 1),
        AutoPoint(beat: 6, value: 0.5),
        AutoPoint(beat: 6, value: 0.2),
        AutoPoint(beat: 8, value: 0.2),
      ];
      expect(autoValueAt(const [], 3, 0.7), 0.7);
      expect(autoValueAt(pts, 0, 9), 0);
      expect(autoValueAt(pts, 3, 9), 0.5);
      expect(autoValueAt(pts, 5, 9), closeTo(1 - 0.5 * 0.00390625, 1e-9), reason: 'curva 1 no ponto das 4: fica perto de 1 e cai no fim');
      expect(autoValueAt(pts, 6, 9), 0.2, reason: 'no degrau vale o valor de depois do salto');
      expect(autoValueAt(pts, 20, 9), 0.2);
      expect(autoInsertIndex(pts, 6), 4);
      expect(autoInsertIndex(pts, 1), 0);
      expect(autoInsertIndex(pts, 100), 5);
    });

    test('ordenar mantém a ordem de pontos na mesma batida', () {
      final a = AutoPoint(beat: 1, value: 1), b = AutoPoint(beat: 1, value: 2), z = AutoPoint(beat: 0, value: 3);
      final list = [a, b, z];
      sortAutoPoints(list);
      expect(list, [z, a, b]);
    });
  });

  testWidgets('menu A cria a raia embaixo da faixa, alinhada ao cabeçalho; clicar de novo oculta', (t) async {
    final c = studio();
    await mount(t, c, const Size(1400, 900));
    final chips = find.text('A');
    expect(chips, findsNWidgets(4), reason: 'três faixas e o master');
    await t.tap(chips.at(1));
    await t.pumpAndSettle();
    expect(find.text('Pan'), findsOneWidget);
    expect(find.text('Sintetizador'), findsOneWidget, reason: 'parâmetros do instrumento num segundo menu');
    await t.tap(find.text('Volume').last);
    await t.pumpAndSettle();
    final lane = c.doc.tracks[1].lanes.single;
    expect(lane.open, isTrue);
    final header = t.getRect(find.byKey(ValueKey('a:${lane.id}')));
    final editor = t.getRect(find.byKey(ValueKey('auto:${lane.id}')));
    expect(header.top, editor.top);
    expect(header.height, automationLaneHeight);
    // a faixa de baixo desceu junto: cabeçalho e clipe continuam na mesma linha
    final below = t.getRect(find.byKey(const ValueKey('t:b')));
    expect(below.top, header.bottom);

    // segundo nível: o parâmetro do instrumento
    await t.tap(chips.at(1));
    await t.pumpAndSettle();
    await t.tap(find.text('Sintetizador'));
    await t.pumpAndSettle();
    await t.tap(find.text('Corte'));
    await t.pumpAndSettle();
    expect(c.doc.tracks[1].lanes.length, 2);
    expect(c.doc.tracks[1].lanes.last.target, const AutoTarget(AutoKind.instrument, param: 13));

    // escolher uma que já está aberta oculta
    await t.tap(chips.at(1));
    await t.pumpAndSettle();
    await t.tap(find.text('Volume').last);
    await t.pumpAndSettle();
    expect(lane.open, isFalse);
    expect(find.byKey(ValueKey('auto:${lane.id}')), findsNothing);
    expect(t.takeException(), isNull);
    await flushSave(t);
  });

  testWidgets('pontos: clique cria na grade, arrastar move num passo de desfazer, duplo clique e botão direito apagam', (t) async {
    final c = studio();
    final lane = volumeLane(c, 0);
    await mount(t, c, const Size(1400, 900));

    // clique no vazio (longe da linha tracejada do valor atual): ponto na batida da grade
    await t.tapAt(at(t, c, lane, 2.2, 0.3));
    await t.pump();
    expect(lane.points.length, 1);
    expect(lane.points.single.beat, 2);
    expect(lane.points.single.value, closeTo(faderToGain(0.3), 0.01));

    // segundo ponto, depois outro no meio (a lista fica ordenada)
    await t.tapAt(at(t, c, lane, 6, 0.8));
    await t.pump(const Duration(milliseconds: 400));
    await t.tapAt(at(t, c, lane, 4, 0.1));
    await t.pump(const Duration(milliseconds: 400));
    expect(lane.points.map((p) => p.beat), [2, 4, 6]);

    // arrastar o do meio duas batidas para a direita esbarra no vizinho (a ordem não muda)
    final undoBefore = c.canUndo;
    final p = lane.points[1];
    await mouseDrag(t, at(t, c, lane, 4, 0.1), at(t, c, lane, 7, 0.5));
    expect(p.beat, 6, reason: 'para no vizinho da direita');
    expect(c.doc.tracks[0].gain, 1, reason: 'o fader não mexe');
    expect(undoBefore, isTrue);
    c.undo();
    await t.pump();
    final back = c.doc.tracks[0].lanes.single;
    expect(back.points.map((p) => p.beat), [2, 4, 6], reason: 'desfazer volta o arraste inteiro');

    // duplo clique apaga; duplo clique no vazio não cria e apaga
    final fresh = c.doc.tracks[0].lanes.single;
    await doubleTapAt(t, at(t, c, fresh, 4, fresh.points[1].value == 0 ? 0 : gainToFader(fresh.points[1].value)));
    expect(fresh.points.map((p) => p.beat), [2, 6]);
    await t.pump(const Duration(milliseconds: 400));
    await doubleTapAt(t, at(t, c, fresh, 9, 0.2));
    expect(fresh.points.map((p) => p.beat), [2, 6, 9], reason: 'o segundo toque só seleciona o ponto novo');

    // botão direito apaga
    await t.pump(const Duration(milliseconds: 400));
    await t.tapAt(at(t, c, fresh, 9, 0.2), buttons: kSecondaryButton, kind: PointerDeviceKind.mouse);
    await t.pump();
    expect(fresh.points.map((p) => p.beat), [2, 6]);
    expect(t.takeException(), isNull);
    await flushSave(t);
  });

  testWidgets('Shift arrasta só o valor; Alt+arrastar entorta a curva; duplo clique na alça volta à reta', (t) async {
    final c = studio();
    final lane = volumeLane(c, 0);
    c.mutate((_) => lane.points.addAll([AutoPoint(beat: 2, value: faderToGain(0.2)), AutoPoint(beat: 6, value: faderToGain(0.9))]));
    await mount(t, c, const Size(1400, 900));

    await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await mouseDrag(t, at(t, c, lane, 2, 0.2), at(t, c, lane, 4, 0.2 + 0.4));
    await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(lane.points.first.beat, 2);
    expect(gainToFader(lane.points.first.value), closeTo(0.3, 0.02), reason: 'fino: um quarto do movimento');

    // Alt+arrastar para cima no meio de um segmento que sobe: curva negativa (o meio sobe)
    await t.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await mouseDrag(t, at(t, c, lane, 3, 0.1), at(t, c, lane, 3, 0.1) - const Offset(0, 25));
    await t.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    expect(lane.points.first.curve, lessThan(-0.3));

    // duplo clique na alça (meio do segmento, em cima da curva) volta à reta
    final a = lane.points[0], b = lane.points[1];
    const mid = 4.0;
    final v = a.value + (b.value - a.value) * autoShape(0.5, a.curve);
    await doubleTapAt(t, at(t, c, lane, mid, gainToFader(v)));
    expect(lane.points.first.curve, 0);
    expect(lane.points.length, 2, reason: 'a alça não cria ponto');
    expect(t.takeException(), isNull);
    await flushSave(t);
  });

  testWidgets('retângulo seleciona, Delete apaga só os pontos (não o clipe), Ctrl+A e desfazer', (t) async {
    final c = studio();
    final lane = volumeLane(c, 0);
    c.mutate(
      (_) => lane.points.addAll([
        for (final b in [1.0, 3.0, 5.0, 7.0]) AutoPoint(beat: b, value: 0.5),
      ]),
    );
    c.selectClip('c1');
    await mount(t, c, const Size(1400, 900));

    await mouseDrag(t, at(t, c, lane, 2.5, 1), at(t, c, lane, 5.5, 0));
    expect(c.selectedClip, isNull, reason: 'clicar na raia tira a seleção do clipe');
    await t.sendKeyEvent(LogicalKeyboardKey.delete);
    await t.pump();
    expect(lane.points.map((p) => p.beat), [1, 7]);
    expect(c.doc.tracks[0].clips, isNotEmpty);

    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.keyA);
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.backspace);
    await t.pump();
    expect(lane.points, isEmpty);

    c.undo();
    c.undo();
    await t.pump();
    expect(c.doc.tracks[0].lanes.single.points.length, 4);

    // clicar fora devolve o Delete ao arranjo: agora apaga o clipe
    c.selectClip('c1');
    await t.tapAt(t.getCenter(find.text('Sintetizador 1')));
    c.selectClip('c1');
    await t.sendKeyEvent(LogicalKeyboardKey.delete);
    await t.pump();
    expect(c.doc.tracks[0].clips, isEmpty);
    expect(c.doc.tracks[0].lanes.single.points.length, 4);
    expect(t.takeException(), isNull);
    await flushSave(t);
  });

  testWidgets('toque: arrastar no vazio rola a linha do tempo, num ponto move; toque longo apaga', (t) async {
    final c = studio();
    final lane = volumeLane(c, 0);
    c.mutate((_) => lane.points.add(AutoPoint(beat: 4, value: 0.5)));
    c.pxPerBeat = 40;
    await mount(t, c, const Size(1400, 900));

    await t.dragFrom(at(t, c, lane, 8, 0.2), const Offset(-120, 0));
    await t.pump();
    expect(c.scrollBeat, greaterThan(0), reason: 'o vazio não prende o dedo');
    expect(lane.points.length, 1);
    c.scrollBeat = 0;
    await t.pump();

    await t.dragFrom(at(t, c, lane, 4, gainToFader(0.5)), const Offset(80, 0));
    await t.pump();
    expect(lane.points.single.beat, 6);

    await t.longPressAt(at(t, c, lane, 6, gainToFader(0.5)));
    await t.pump();
    expect(lane.points, isEmpty);
    expect(t.takeException(), isNull);
    await flushSave(t);
  });

  testWidgets('clipe arrastado para baixo passa por cima das automações abertas e cai na faixa certa', (t) async {
    final c = studio();
    volumeLane(c, 0);
    c.addLane(0, const AutoTarget(AutoKind.pan));
    await mount(t, c, const Size(1400, 900));
    final clip = t.getRect(find.byKey(const ValueKey('c1')));
    final target = t.getRect(find.byKey(const ValueKey('t:b')));
    await mouseDrag(t, clip.center, Offset(clip.center.dx, target.center.dy));
    expect(c.doc.tracks[2].clips.map((x) => x.id), ['c1'], reason: 'pula a de instrumento e as raias de automação');
    await flushSave(t);
  });

  testWidgets('barramento: item no + Faixa, sem clipes nem dica de criar clipe, clipe não entra', (t) async {
    final c = studio();
    await mount(t, c, const Size(1400, 900));
    await t.tap(find.text('Faixa'));
    await t.pumpAndSettle();
    await t.tap(find.text('Barramento'));
    await t.pumpAndSettle();
    expect(c.doc.tracks.last.kind, TrackKind.bus);
    expect(find.textContaining('Barramento: recebe'), findsOneWidget);
    expect(find.textContaining('Clique duas vezes'), findsNothing);

    // o ícone do barramento abre os efeitos dele
    await t.tap(find.byIcon(TrackKind.bus.icon));
    await t.pump();
    expect(c.dock, Dock.effects);
    expect(c.effectsTrack, 3);

    // áudio arrastado até o barramento fica na faixa dele
    final clip = t.getRect(find.byKey(const ValueKey('c1')));
    final bus = t.getRect(find.byKey(ValueKey('t:${c.doc.tracks[3].id}')));
    await mouseDrag(t, clip.center, Offset(clip.center.dx, bus.center.dy));
    expect(c.doc.tracks[3].clips, isEmpty);
    expect(c.doc.tracks[2].clips.map((x) => x.id), ['c1'], reason: 'a última faixa de áudio antes dele');
    expect(t.takeException(), isNull);
    await flushSave(t);
  });

  testWidgets('master no fim: automação e efeitos do master', (t) async {
    final c = studio();
    await mount(t, c, const Size(1400, 900));
    final master = t.getRect(find.byKey(const ValueKey('master')));
    final last = t.getRect(find.byKey(const ValueKey('t:b')));
    expect(master.top, greaterThan(last.bottom));
    await t.tap(find.text('FX').last);
    await t.pump();
    expect(c.dock, Dock.effects);
    expect(c.effectsTrack, -1);
    await t.tap(find.text('A').last);
    await t.pumpAndSettle();
    expect(find.text('Sintetizador'), findsNothing);
    await t.tap(find.text('Volume').last);
    await t.pumpAndSettle();
    final lane = c.doc.masterLanes.single;
    expect(t.getRect(find.byKey(ValueKey('auto:${lane.id}'))).top, t.getRect(find.byKey(const ValueKey('master'))).bottom);
    await t.tapAt(at(t, c, lane, 1, 0.3));
    await t.pump();
    expect(lane.points.single.beat, 1);
    expect(find.text('Volume'), findsOneWidget, reason: 'nome no cabeçalho da raia');
    expect(t.takeException(), isNull);
    await flushSave(t);
  });

  testWidgets('celular de 360 px: cabeçalhos com A, raias de automação e master sem estouro', (t) async {
    final c = studio();
    volumeLane(c, 1);
    c.addLane(1, const AutoTarget(AutoKind.instrument, param: 13));
    c.addLane(-1, const AutoTarget(AutoKind.pan));
    c.mutate((_) => c.doc.tracks[1].lanes.first.points.addAll([AutoPoint(beat: 0, value: 0.2), AutoPoint(beat: 3, value: 1.4, curve: 0.5)]));
    await mount(t, c, const Size(360, 780));
    expect(t.takeException(), isNull);
    expect(find.text('A'), findsNWidgets(4));
    // oculta pelo cabeçalho: sai da tela e o A fica só contornado
    final lane = c.doc.tracks[1].lanes.first;
    await t.tap(find.descendant(of: find.byKey(ValueKey('a:${lane.id}')), matching: find.byIcon(Icons.visibility_off_outlined)));
    await t.pump();
    expect(lane.open, isFalse);
    expect(find.byKey(ValueKey('auto:${lane.id}')), findsNothing);
    // remove pelo cabeçalho
    final other = c.doc.tracks[1].lanes.last;
    await t.tap(find.descendant(of: find.byKey(ValueKey('a:${other.id}')), matching: find.byIcon(Icons.close)));
    await t.pump();
    expect(c.doc.tracks[1].lanes.length, 1);
    expect(t.takeException(), isNull);
    await flushSave(t);
  });
}
