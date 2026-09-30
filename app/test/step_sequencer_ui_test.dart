// A aba "Passos" contra o controlador de verdade (o motor é o stub): toque liga e desliga, o arraste
// pinta, desfazer por gesto, presets, faixa de velocidade, ouvir a peça e o layout no desktop e em 360 px.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jopendaw_app/daw/controller.dart';
import 'package:jopendaw_app/daw/dock.dart';
import 'package:jopendaw_app/daw/instruments.dart';
import 'package:jopendaw_app/daw/model.dart';
import 'package:jopendaw_app/daw/sampler_zones.dart';
import 'package:jopendaw_app/daw/step_sequencer.dart';
import 'package:jopendaw_app/daw/step_sequencer_ui.dart';
import 'package:jopendaw_app/models/project.dart';
import 'package:jopendaw_app/widgets/theme.dart';

var _ids = 0;

class StepDaw extends DawController {
  StepDaw({TrackKind kind = TrackKind.drums, List<MidiNote>? notes, double clipLength = 4, bool withClip = true, List<SamplerZone>? zones})
    : super(
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
      ) {
    doc = DawDoc(
      bpm: 120,
      beatsPerBar: 4,
      tracks: [
        DawTrack(
          id: 't1',
          name: 'Bateria',
          color: 0,
          kind: kind,
          zones: zones,
          midi: withClip ? [MidiClip(id: 'c${++_ids}', name: 'Batida', start: 0, length: clipLength, notes: notes)] : [],
        ),
      ],
    );
    ready = true;
    selectedTrack = 0;
    if (withClip) selectedClip = 'c$_ids';
    dock = Dock.steps;
  }

  final log = <String>[];

  MidiClip get clip => doc.tracks[0].midi[0];

  @override
  void noteOn(int pitch, {double velocity = 0.8, int? track}) {
    log.add('on $pitch');
    super.noteOn(pitch, velocity: velocity, track: track);
  }

  @override
  void noteOff(int pitch, {int? track}) {
    log.add('off $pitch');
    super.noteOff(pitch, track: track);
  }
}

Widget host(DawController c, {required double width, double height = 520, Widget? child}) => MaterialApp(
  theme: buildTheme(),
  debugShowCheckedModeBanner: false,
  home: Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: width,
        height: height,
        child: child ?? StepSequencerPanel(c: c),
      ),
    ),
  ),
);

Future<void> setView(WidgetTester t, double w, double h) async {
  t.view.physicalSize = Size(w, h);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

final grid = find.byKey(const ValueKey('step-grid'));

/// Centro do passo [step] da linha [row] na grade de [steps] passos.
Offset cell(WidgetTester t, int row, int step, {int steps = 16}) {
  final tl = t.getTopLeft(grid);
  final w = t.getSize(grid).width / steps;
  return tl + Offset(step * w + w / 2, row * 32.0 + 16);
}

List<double> starts(StepDaw c, int pitch) => [
  for (final n in c.clip.notes)
    if (n.pitch == pitch) n.start,
]..sort();

Future<void> mouseTap(WidgetTester t, Offset p) async {
  final g = await t.createGesture(kind: PointerDeviceKind.mouse);
  await g.down(p);
  await g.up();
  await t.pump();
  await g.removePointer();
}

void main() {
  testWidgets('desktop: a grade tem uma linha por peça, sem overflow, e o toque liga e desliga', (t) async {
    await setView(t, 1000, 520);
    final c = StepDaw();
    await t.pumpWidget(host(c, width: 1000));
    expect(t.takeException(), isNull);
    for (final p in drumPieces) {
      expect(find.byKey(ValueKey('step-row-${p.pitch}')), findsOneWidget);
    }
    expect(find.text('Bumbo'), findsOneWidget);
    expect(find.text('Chimbal fechado'), findsOneWidget);
    // 16 passos por compasso: a célula tem no mínimo 32 px
    expect(t.getSize(grid).width / 16, greaterThanOrEqualTo(32));

    await t.tapAt(cell(t, 0, 0));
    await t.pump();
    expect(starts(c, 36), [0.0]);
    await t.tapAt(cell(t, 0, 4));
    await t.pump();
    expect(starts(c, 36), [0.0, 1.0]);
    // desliga
    await t.pump(const Duration(milliseconds: 400));
    await t.tapAt(cell(t, 0, 4));
    await t.pump();
    expect(starts(c, 36), [0.0]);
    // a caixa é a linha 1
    await t.tapAt(cell(t, 1, 8));
    await t.pump();
    expect(starts(c, 38), [2.0]);
    // notas de fora da grade ou de outras linhas não mudaram
    expect(c.clip.notes.length, 2);
    t.takeException();
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('cada toque é um passo do desfazer, e desfazer volta o passo', (t) async {
    await setView(t, 1000, 520);
    final c = StepDaw();
    await t.pumpWidget(host(c, width: 1000));
    await t.tapAt(cell(t, 0, 0));
    await t.pump();
    await t.tapAt(cell(t, 0, 2));
    await t.pump(const Duration(seconds: 1));
    expect(starts(c, 36), [0.0, 0.5]);
    c.undo();
    expect(starts(c, 36), [0.0]);
    c.undo();
    expect(starts(c, 36), isEmpty);
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('arrastar com o mouse pinta vários passos numa linha e desfaz de uma vez', (t) async {
    await setView(t, 1000, 520);
    final c = StepDaw();
    await t.pumpWidget(host(c, width: 1000));
    final g = await t.createGesture(kind: PointerDeviceKind.mouse);
    await g.down(cell(t, 1, 0));
    for (var s = 1; s <= 5; s++) {
      // a linha do ponteiro pode derivar: a pintura fica na linha em que começou
      await g.moveTo(cell(t, s.isEven ? 2 : 1, s));
    }
    await g.up();
    await t.pump();
    expect(starts(c, 38), [0.0, 0.25, 0.5, 0.75, 1.0, 1.25]);
    expect(starts(c, 39), isEmpty);
    c.undo();
    expect(c.clip.notes, isEmpty, reason: 'um gesto, um passo do desfazer');
    await g.removePointer();
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('arrastar sobre passos ligados apaga', (t) async {
    await setView(t, 1000, 520);
    final c = StepDaw(notes: [for (var i = 0; i < 8; i++) MidiNote(pitch: 42, start: i * 0.25, length: 0.25)]);
    await t.pumpWidget(host(c, width: 1000));
    final g = await t.createGesture(kind: PointerDeviceKind.mouse);
    await g.down(cell(t, 3, 1));
    await g.moveTo(cell(t, 3, 2));
    await g.moveTo(cell(t, 3, 3));
    await g.up();
    await t.pump();
    expect(starts(c, 42), [0.0, 1.0, 1.25, 1.5, 1.75]);
    await g.removePointer();
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('toque longo pinta e o arraste curto do dedo só rola', (t) async {
    await setView(t, 360, 640);
    final c = StepDaw();
    await t.pumpWidget(host(c, width: 360, height: 400));
    expect(t.takeException(), isNull);
    // arrastar o dedo rola a grade e não pinta
    await t.dragFrom(t.getTopLeft(grid) + const Offset(40, 16), const Offset(-120, 0));
    await t.pump();
    expect(c.clip.notes, isEmpty);
    // toque longo e arraste pinta; o gesto começa na grade já rolada
    final start = cell(t, 0, 5, steps: 16);
    final g = await t.startGesture(start);
    await t.pump(const Duration(milliseconds: 400));
    await g.moveBy(const Offset(32, 0));
    await g.moveBy(const Offset(32, 0));
    await g.up();
    await t.pump(const Duration(seconds: 1));
    final s = starts(c, 36);
    expect(s.length, greaterThanOrEqualTo(3));
    expect(s.length, lessThanOrEqualTo(4));
    c.undo();
    expect(c.clip.notes, isEmpty);
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('360 px: sem overflow, passos com pelo menos 32 px e toque curto liga', (t) async {
    await setView(t, 360, 640);
    final c = StepDaw();
    await t.pumpWidget(host(c, width: 360, height: 420));
    expect(t.takeException(), isNull);
    expect(t.getSize(grid).width / 16, greaterThanOrEqualTo(32));
    // a grade é mais larga que a tela: rola na horizontal
    expect(t.getSize(grid).width, greaterThan(360));
    await t.tapAt(cell(t, 0, 1));
    await t.pump();
    expect(starts(c, 36), [0.25]);
    // 64 passos por compasso e 8 compassos: não estoura nem trava
    for (final r in ['1/64']) {
      await t.tap(find.byKey(const ValueKey('step-res')));
      await t.pumpAndSettle();
      await t.tap(find.textContaining('$r ·').last);
      await t.pumpAndSettle();
    }
    for (var i = 0; i < 7; i++) {
      await t.ensureVisible(find.byKey(const ValueKey('step-bars-plus')));
      await t.tap(find.byKey(const ValueKey('step-bars-plus')));
      await t.pump();
    }
    expect(t.takeException(), isNull);
    expect(t.getSize(grid).width, 64 * 8 * 32);
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('duplo toque cria o acento; o pincel escolhe acento e fantasma', (t) async {
    await setView(t, 1000, 520);
    final c = StepDaw();
    await t.pumpWidget(host(c, width: 1000));
    await mouseTap(t, cell(t, 0, 0));
    await mouseTap(t, cell(t, 0, 0)); // rápido, mesmo passo: acento
    expect(c.clip.notes.single.velocity, stepAccentVelocity);
    await t.tap(find.byKey(const ValueKey('step-brush-ghost')));
    await t.pump();
    await mouseTap(t, cell(t, 0, 8));
    expect(c.clip.notes.firstWhere((n) => n.start == 2.0).velocity, stepGhostVelocity);
    await t.tap(find.byKey(const ValueKey('step-brush-accent')));
    await t.pump();
    await mouseTap(t, cell(t, 0, 12));
    expect(c.clip.notes.firstWhere((n) => n.start == 3.0).velocity, stepAccentVelocity);
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('faixa de velocidade: selecionar a linha e arrastar muda a velocidade sem mover a nota', (t) async {
    await setView(t, 1000, 700);
    final c = StepDaw(notes: [MidiNote(pitch: 36, start: 0.56, length: 0.25, velocity: 0.8), MidiNote(pitch: 36, start: 1.0, length: 0.25, velocity: 0.8)]);
    await t.pumpWidget(host(c, width: 1000, height: 700));
    expect(find.byKey(const ValueKey('step-strip')), findsNothing);
    await t.tap(find.byKey(const ValueKey('step-row-36')));
    await t.pump();
    final strip = find.byKey(const ValueKey('step-strip'));
    expect(strip, findsOneWidget);
    final tl = t.getTopLeft(strip);
    final w = t.getSize(strip).width / 16;
    // o passo 4 (1,0) a 25% da altura da faixa (velocidade ~0,75 -> 0,25 no dy = 75%)
    final g = await t.createGesture(kind: PointerDeviceKind.mouse);
    await g.down(tl + Offset(4 * w + w / 2, 64 * 0.75));
    await g.moveTo(tl + Offset(2 * w + w / 2, 64 * 0.5));
    await g.up();
    await t.pump();
    final one = c.clip.notes.firstWhere((n) => n.start == 1.0);
    expect(one.velocity, closeTo(0.25, 0.02));
    final micro = c.clip.notes.firstWhere((n) => n.start == 0.56);
    expect(micro.velocity, closeTo(0.5, 0.02), reason: 'o passo 2 tem a nota fora da grade; a velocidade muda, o tempo não');
    expect(micro.start, 0.56);
    await g.removePointer();
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('nota fora da grade é mostrada e não some ao editar outros passos', (t) async {
    await setView(t, 1000, 520);
    final human = MidiNote(pitch: 36, start: 0.512, length: 0.25, velocity: 0.7);
    final c = StepDaw(notes: [human]);
    await t.pumpWidget(host(c, width: 1000));
    await t.tapAt(cell(t, 0, 8));
    await t.pump();
    await t.tapAt(cell(t, 5, 3));
    await t.pump(const Duration(seconds: 1));
    expect(c.clip.notes.contains(human), isTrue);
    expect(human.start, 0.512);
  });

  testWidgets('ouvir a peça toca com o transporte parado e solta depois', (t) async {
    await setView(t, 1000, 520);
    final c = StepDaw();
    await t.pumpWidget(host(c, width: 1000));
    await t.tap(find.byKey(const ValueKey('step-ear-38')));
    await t.pump();
    expect(c.log, contains('on 38'));
    await t.pump(const Duration(milliseconds: 400));
    expect(c.log, contains('off 38'));
    // ligar um passo também dá a prévia
    c.log.clear();
    await t.tapAt(cell(t, 0, 0));
    await t.pump();
    expect(c.log, contains('on 36'));
    await t.pump(const Duration(milliseconds: 400));
    // tocando, não faz prévia
    c.log.clear();
    c.playing.value = true;
    await t.tapAt(cell(t, 0, 1));
    await t.pump(const Duration(milliseconds: 400));
    expect(c.log, isEmpty);
    c.playing.value = false;
  });

  testWidgets('o cursor corre na grade durante a reprodução sem quebrar', (t) async {
    await setView(t, 1000, 520);
    final c = StepDaw(clipLength: 8);
    await t.pumpWidget(host(c, width: 1000));
    c.playing.value = true;
    for (final b in [0.0, 0.3, 3.9, 4.1, 7.9, 9.0]) {
      c.beat.value = b;
      await t.pump();
    }
    expect(t.takeException(), isNull);
    c.playing.value = false;
    await t.pump();
  });

  testWidgets('Padrões: escolher um padrão preenche as linhas e muda a resolução; desfaz de uma vez', (t) async {
    await setView(t, 1000, 520);
    final c = StepDaw(notes: [MidiNote(pitch: 60, start: 1.0, length: 0.25)]);
    await t.pumpWidget(host(c, width: 1000));
    await t.tap(find.byKey(const ValueKey('step-presets')));
    await t.pumpAndSettle();
    for (final p in stepPresets) {
      expect(find.byKey(ValueKey('step-preset-${p.id}')), findsOneWidget);
    }
    await t.tap(find.byKey(const ValueKey('step-preset-four')));
    await t.pumpAndSettle();
    expect(starts(c, 36), [0.0, 1.0, 2.0, 3.0]);
    expect(starts(c, 39), [1.0, 3.0]);
    expect(c.clip.notes.where((n) => n.pitch == 60).length, 1, reason: 'nota de fora do kit fica');
    c.undo();
    expect(starts(c, 36), isEmpty);
    expect(c.clip.notes.length, 1);

    // trap muda a grade para 1/32: os passos do chimbal continuam na grade
    await t.tap(find.byKey(const ValueKey('step-presets')));
    await t.pumpAndSettle();
    await t.ensureVisible(find.byKey(const ValueKey('step-preset-trap')));
    await t.tap(find.byKey(const ValueKey('step-preset-trap')));
    await t.pumpAndSettle();
    expect(find.textContaining('1/32'), findsWidgets);
    expect(t.getSize(grid).width / 32, greaterThanOrEqualTo(32));
    expect(starts(c, 42).length, 16);
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('ações do menu: preencher a cada N, inverter, deslocar, limpar e repetir', (t) async {
    await setView(t, 1000, 520);
    final c = StepDaw(clipLength: 8);
    await t.pumpWidget(host(c, width: 1000));
    Future<void> action(String label) async {
      await t.tap(find.byKey(const ValueKey('step-actions')));
      await t.pumpAndSettle();
      await t.tap(find.text(label).last);
      await t.pumpAndSettle();
    }

    // linha do bumbo selecionada: as ações valem só para ela
    await t.tap(find.byKey(const ValueKey('step-row-36')));
    await t.pump();
    await action('Preencher a cada N passos…');
    // o controle de valor abre em 4
    await t.tap(find.byKey(const ValueKey('step-number-ok')));
    await t.pumpAndSettle();
    expect(starts(c, 36), [0.0, 1.0, 2.0, 3.0]);
    await action('Deslocar →');
    expect(starts(c, 36), [0.25, 1.25, 2.25, 3.25]);
    await action('Deslocar ←');
    expect(starts(c, 36), [0.0, 1.0, 2.0, 3.0]);
    await action('Repetir até o fim do clipe');
    expect(starts(c, 36), [0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0]);
    expect(find.byKey(const ValueKey('step-notice')), findsOneWidget);
    await action('Copiar padrão');
    await action('Limpar linha');
    expect(starts(c, 36).where((s) => s < 4), isEmpty);
    await action('Colar padrão');
    expect(starts(c, 36).where((s) => s < 4).length, 4);
    await action('Inverter');
    expect(starts(c, 36).where((s) => s < 4).length, 12);
    await action('Limpar tudo');
    expect(starts(c, 36).where((s) => s < 4), isEmpty);
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('swing: aplicar atrasa os passos pares das notas e tirar volta', (t) async {
    await setView(t, 1000, 520);
    final c = StepDaw(notes: [for (var i = 0; i < 4; i++) MidiNote(pitch: 42, start: i * 0.25, length: 0.25)]);
    await t.pumpWidget(host(c, width: 1000));
    final slider = find.byKey(const ValueKey('step-swing'));
    // arrastar o controle até o meio: um valor entre 0 e 75
    await t.drag(slider, const Offset(30, 0));
    await t.pump();
    final apply = find.byKey(const ValueKey('step-swing-apply'));
    await t.tap(apply);
    await t.pump();
    final sw = starts(c, 42);
    expect(sw[0], 0.0);
    expect(sw[1], greaterThan(0.25));
    expect(sw[2], 0.5);
    expect(sw[3], greaterThan(0.75));
    // os passos seguem ligados na grade com swing
    c.undo();
    expect(starts(c, 42), [0.0, 0.25, 0.5, 0.75]);
    await t.tap(apply);
    await t.pump();
    await t.tap(find.byKey(const ValueKey('step-swing-off')));
    await t.pump();
    expect(starts(c, 42), [0.0, 0.25, 0.5, 0.75]);
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('sampler fatiado: uma linha por zona, com a nota da zona', (t) async {
    await setView(t, 1000, 520);
    final zones = sliceZones('abc', [0.0, 0.25, 0.5, 0.75], () => 'z${_ids++}');
    final c = StepDaw(kind: TrackKind.sampler, zones: zones);
    await t.pumpWidget(host(c, width: 1000));
    for (final z in zones) {
      expect(find.byKey(ValueKey('step-row-${z.root}')), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('step-presets')), findsNothing, reason: 'padrões de bateria não valem para fatias');
    await t.tapAt(cell(t, 2, 4));
    await t.pump(const Duration(seconds: 1));
    expect(starts(c, zones[2].root), [1.0]);
  });

  testWidgets('sem clipe sob o cursor: botão cria o clipe da faixa e abre a grade', (t) async {
    await setView(t, 1000, 520);
    final c = StepDaw(withClip: false);
    await t.pumpWidget(host(c, width: 1000));
    expect(find.byKey(const ValueKey('step-create')), findsOneWidget);
    expect(grid, findsNothing);
    await t.tap(find.byKey(const ValueKey('step-create')));
    await t.pump();
    expect(c.doc.tracks[0].midi.length, 1);
    expect(grid, findsOneWidget);
    await t.tapAt(cell(t, 0, 0));
    await t.pump(const Duration(seconds: 1));
    expect(c.doc.tracks[0].midi.single.notes.length, 1);
  });

  testWidgets('faixa que não é de bateria nem sampler com zonas: a aba explica em vez de mostrar a grade', (t) async {
    await setView(t, 1000, 520);
    final c = StepDaw(kind: TrackKind.synth);
    await t.pumpWidget(host(c, width: 1000));
    expect(grid, findsNothing);
    expect(find.textContaining('bateria'), findsWidgets);
    expect(stepTarget(c), isNull);
    final c2 = StepDaw(kind: TrackKind.sampler);
    expect(stepTarget(c2), isNull, reason: 'sampler sem zonas');
    final c3 = StepDaw();
    expect(stepTarget(c3)!.clip, isNotNull);
  });

  testWidgets('o painel: a aba Passos só aparece para bateria e sampler com zonas', (t) async {
    // a fonte dos testes (Ahem) é larga: seis rótulos de aba só cabem em 1600 px
    await setView(t, 1600, 700);
    Future<void> pumpDock(DawController c) async {
      await t.pumpWidget(host(c, width: 1600, height: 700, child: DockPanel(c: c, available: 700, compact: false)));
    }

    final synth0 = StepDaw(kind: TrackKind.synth);
    synth0.dock = Dock.editor;
    await pumpDock(synth0);
    expect(t.takeException(), isNull, reason: 'sem a aba Passos');
    final drums = StepDaw(kind: TrackKind.drums);
    drums.dock = Dock.editor;
    await pumpDock(drums);
    expect(t.takeException(), isNull, reason: 'antes de abrir Passos');
    expect(find.text('Passos'), findsOneWidget);
    await t.tap(find.text('Passos'));
    await t.pumpAndSettle();
    expect(drums.dock, Dock.steps);
    expect(grid, findsOneWidget);
    final ex = t.takeException();
    expect(ex, isNull);

    final synth = StepDaw(kind: TrackKind.synth);
    synth.dock = Dock.editor;
    await pumpDock(synth);
    await t.pumpAndSettle();
    expect(find.text('Passos'), findsNothing);
  });
}
