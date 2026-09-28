// Piano roll contra o controlador de verdade (o motor é o stub): gestos, teclas, desfazer e
// desempenho. Com `--dart-define=SHOTS=<pasta>` grava capturas PNG de cada estado (com as fontes
// do Material, se o cache do Flutter estiver no lugar de sempre).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jopendaw_app/daw/controller.dart';
import 'package:jopendaw_app/daw/instruments.dart';
import 'package:jopendaw_app/daw/model.dart';
import 'package:jopendaw_app/daw/piano_roll.dart';
import 'package:jopendaw_app/models/project.dart';
import 'package:jopendaw_app/widgets/theme.dart';

const shots = String.fromEnvironment('SHOTS');

var _ids = 0;

/// O controlador de verdade num documento de uma faixa com um clipe aberto no editor; guarda as
/// notas ao vivo e conta as quantizações.
class TestDaw extends DawController {
  TestDaw({TrackKind kind = TrackKind.synth, List<MidiNote>? notes, double clipStart = 4, double clipLength = 8})
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
          name: kind == TrackKind.drums ? 'Bateria' : 'Synth',
          color: 0,
          kind: kind,
          midi: [MidiClip(id: 'c${++_ids}', name: 'Riff', start: clipStart, length: clipLength, notes: notes)],
        ),
      ],
    );
    ready = true;
    editingClip = 'c$_ids';
    dock = Dock.editor;
  }

  final log = <String>[];
  int quantized = 0;

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

  @override
  void quantizeNotes(MidiClip clip, Iterable<MidiNote> notes, double grid, {double strength = 1, bool ends = false}) {
    quantized++;
    super.quantizeNotes(clip, notes, grid, strength: strength, ends: ends);
  }
}

/// Fontes de verdade só para as capturas: sem elas o texto sai em blocos.
Future<void> loadFonts() async {
  final dir = '${Platform.environment['FLUTTER_ROOT'] ?? ''}/bin/cache/artifacts/material_fonts';
  if (shots.isEmpty || !Directory(dir).existsSync()) return;
  Future<void> load(String family, List<String> files) async {
    final l = FontLoader(family);
    for (final f in files) {
      l.addFont(Future.value(ByteData.view(File('$dir/$f').readAsBytesSync().buffer)));
    }
    await l.load();
  }

  for (final fam in ['Roboto', '.AppleSystemUIFont', 'CupertinoSystemText', 'CupertinoSystemDisplay', 'FlutterTest']) {
    await load(fam, ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf']);
  }
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
}

final shotKey = GlobalKey();

Widget host(TestDaw c, {double width = 1000, double height = 420}) => MaterialApp(
  theme: buildTheme(),
  debugShowCheckedModeBanner: false,
  home: Scaffold(
    body: Focus(
      autofocus: true,
      onKeyEvent: (_, e) => (c.editorKeyHandler?.call(e) ?? false) ? KeyEventResult.handled : KeyEventResult.ignored,
      child: Align(
        alignment: Alignment.topLeft,
        child: RepaintBoundary(
          key: shotKey,
          child: SizedBox(
            width: width,
            height: height,
            child: PianoRoll(c: c),
          ),
        ),
      ),
    ),
  ),
);

Future<void> shot(WidgetTester t, String name) async {
  if (shots.isEmpty) return;
  final boundary = shotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await t.runAsync(() async {
    final img = await boundary.toImage(pixelRatio: 1.5);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    File('$shots/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

/// Mesma conta do editor: origem da grade e visão depois do enquadramento de abertura.
class G {
  final Offset origin;
  final double ppb, rowH, scrollX, scrollY;
  final int hi;
  G(this.origin, this.ppb, this.rowH, this.scrollX, this.scrollY, this.hi);
  Offset at(double beat, int pitch, {double dy = .5}) => origin + Offset((beat - scrollX) * ppb, (hi - pitch + dy) * rowH - scrollY);
}

G geoFor(TestDaw c, {double width = 1000, double height = 420}) {
  const keys = 50.0, toolbar = 44.0, ruler = 24.0, vel = 72.0, row = 14.0;
  final gw = width - keys, gh = height - toolbar - ruler - vel;
  final clip = c.clip;
  var s0 = 0.0, s1 = clip.length;
  int? p0, p1;
  for (final n in clip.notes) {
    s0 = s0 < n.start ? s0 : n.start;
    s1 = s1 > n.end ? s1 : n.end;
    p0 = p0 == null || n.pitch < p0 ? n.pitch : p0;
    p1 = p1 == null || n.pitch > p1 ? n.pitch : p1;
  }
  final ppb = ((gw - 16) / (s1 - s0)).clamp(12.0, 320.0);
  const hi = 108;
  final r0 = p1 == null ? hi - 60 : hi - p1, r1 = p0 == null ? hi - 60 : hi - p0;
  var sy = (r0 + r1 + 1) / 2 * row - gh / 2;
  sy = sy.clamp(0.0, 97 * row - gh);
  return G(const Offset(keys, toolbar + ruler), ppb, row, s0, sy, hi);
}

var _now = Duration.zero;

Future<TestGesture> mouseDown(WidgetTester t, Offset p, {int buttons = kPrimaryMouseButton, int gapMs = 600}) async {
  _now += Duration(milliseconds: gapMs);
  final g = await t.createGesture(kind: PointerDeviceKind.mouse, buttons: buttons);
  await g.down(p, timeStamp: _now);
  return g;
}

Future<void> click(WidgetTester t, Offset p, {int buttons = kPrimaryMouseButton, int gapMs = 600}) async {
  final g = await mouseDown(t, p, buttons: buttons, gapMs: gapMs);
  await g.up();
  await t.pump();
}

Future<void> drag(WidgetTester t, Offset from, Offset to, {int steps = 6}) async {
  final g = await mouseDown(t, from);
  for (var i = 1; i <= steps; i++) {
    await g.moveTo(Offset.lerp(from, to, i / steps)!);
    await t.pump();
  }
  await g.up();
  await t.pump();
}

Future<void> key(WidgetTester t, LogicalKeyboardKey k, {bool ctrl = false, bool shift = false, bool alt = false}) async {
  if (ctrl) await t.sendKeyDownEvent(LogicalKeyboardKey.control);
  if (shift) await t.sendKeyDownEvent(LogicalKeyboardKey.shift);
  if (alt) await t.sendKeyDownEvent(LogicalKeyboardKey.alt);
  await t.sendKeyEvent(k);
  if (alt) await t.sendKeyUpEvent(LogicalKeyboardKey.alt);
  if (shift) await t.sendKeyUpEvent(LogicalKeyboardKey.shift);
  if (ctrl) await t.sendKeyUpEvent(LogicalKeyboardKey.control);
  await t.pump();
}

Future<void> settle(WidgetTester t) async {
  await t.pump(const Duration(seconds: 1));
}

List<MidiNote> riff() => [
  MidiNote(pitch: 60, start: 0, length: 1, velocity: .9),
  MidiNote(pitch: 64, start: 1, length: .5, velocity: .5),
  MidiNote(pitch: 67, start: 1.5, length: .5, velocity: .7),
  MidiNote(pitch: 72, start: 2, length: 2, velocity: 1),
  MidiNote(pitch: 62, start: 4, length: .25, velocity: .3),
  MidiNote(pitch: 65, start: 4.5, length: .25, velocity: .6),
  MidiNote(pitch: 69, start: 5, length: 1, velocity: .8),
  MidiNote(pitch: 71, start: 6.5, length: 2.5, velocity: .75),
];

void mac(String name, Future<void> Function(WidgetTester) body) => testWidgets(name, body, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

void main() {
  setUpAll(loadFonts);

  Future<void> sized(WidgetTester t) async {
    t.view.physicalSize = const Size(1200, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
  }

  mac('estado vazio e captura', (t) async {
    await sized(t);
    final c = TestDaw()..editingClip = null;
    await t.pumpWidget(host(c));
    expect(find.text('Nenhum clipe de notas aberto'), findsOneWidget);
    await shot(t, 'pr_empty');
    await settle(t);
  });

  mac('captura com notas (melódico)', (t) async {
    await sized(t);
    final c = TestDaw(notes: riff());
    await t.pumpWidget(host(c));
    await t.pump();
    await shot(t, 'pr_melodic');
    await settle(t);
  });

  mac('captura bateria', (t) async {
    await sized(t);
    final notes = [
      for (var i = 0; i < 16; i++) MidiNote(pitch: 42, start: i * .5, length: .25, velocity: i.isEven ? .9 : .5),
      for (var i = 0; i < 4; i++) MidiNote(pitch: 36, start: i * 2.0, length: .25, velocity: 1),
      for (var i = 0; i < 4; i++) MidiNote(pitch: 38, start: 1 + i * 2.0, length: .25, velocity: .8),
      MidiNote(pitch: 70, start: 7, length: .5),
    ];
    final c = TestDaw(kind: TrackKind.drums, notes: notes);
    await t.pumpWidget(host(c, height: 480));
    await t.pump();
    await shot(t, 'pr_drums');
    await settle(t);
  });

  mac('clique vazio cria nota encaixada; desfazer tira', (t) async {
    await sized(t);
    final c = TestDaw(notes: riff());
    await t.pumpWidget(host(c));
    final g = geoFor(c);
    await click(t, g.at(3.1, 65));
    expect(c.clip.notes.length, 9);
    final n = c.clip.notes.last;
    expect(n.pitch, 65);
    expect(n.start, 3.0); // chão da grade de 1/16 → 3.0 (3.1 está na célula 3.0..3.25)
    expect(n.length, .25);
    expect(c.log, containsAllInOrder(['on 65', 'off 65']));
    expect(c.canUndo, isTrue);
    c.undo();
    await t.pump();
    expect(c.clip.notes.length, 8);
    await settle(t);
  });

  mac('arrastar no vazio define a duração', (t) async {
    await sized(t);
    final c = TestDaw(notes: riff());
    await t.pumpWidget(host(c));
    final g = geoFor(c);
    await drag(t, g.at(3.05, 66), g.at(4.6, 66));
    final n = c.clip.notes.last;
    expect(n.start, 3.0);
    expect(n.length, closeTo(1.75, 1e-9)); // teto de 4.6 na grade = 4.75
    await settle(t);
  });

  mac('mover nota: tempo encaixado e altura; um passo de desfazer', (t) async {
    await sized(t);
    final c = TestDaw(notes: riff());
    await t.pumpWidget(host(c));
    final g = geoFor(c);
    final n = c.clip.notes[3]; // 72 em 2..4
    await drag(t, g.at(2.5, 72), g.at(3.02, 74));
    expect(n.start, 2.5);
    expect(n.pitch, 74);
    expect(c.log.where((e) => e.startsWith('on')).toList(), ['on 72', 'on 73', 'on 74']);
    c.undo();
    await t.pump();
    expect(c.clip.notes[3].start, 2);
    expect(c.clip.notes[3].pitch, 72);
    expect(c.canUndo, isFalse);
    await settle(t);
  });

  mac('clique numa nota sem arrastar não deixa checkpoint', (t) async {
    await sized(t);
    final c = TestDaw(notes: riff());
    await t.pumpWidget(host(c));
    final g = geoFor(c);
    await click(t, g.at(2.5, 72));
    expect(c.canUndo, isFalse);
    await t.pump(const Duration(milliseconds: 500));
    await drag(t, g.at(2.5, 72), g.at(3.5, 73), steps: 3);
    await t.pump(const Duration(milliseconds: 500));
    await drag(t, g.at(3.5, 73), g.at(2.5, 72), steps: 3);
    expect(c.canUndo, isTrue);
    await t.pump(const Duration(milliseconds: 500));
    final g2 = await mouseDown(t, g.at(2.5, 72));
    await g2.moveTo(g.at(3.5, 72));
    await t.pump();
    await g2.moveTo(g.at(2.5, 72));
    await t.pump();
    await g2.up();
    await t.pump();
    // dois arrastes reais (ida e volta) ficam; o de ida e volta no mesmo gesto some
    var steps = 0;
    while (c.canUndo) {
      c.undo();
      steps++;
    }
    expect(steps, 2);
    await settle(t);
  });

  mac('redimensionar pela direita e pela esquerda', (t) async {
    await sized(t);
    final c = TestDaw(notes: riff());
    await t.pumpWidget(host(c));
    final g = geoFor(c);
    final n = c.clip.notes[3]; // 2..4
    final right = g.at(4, 72) - const Offset(2, 0);
    await drag(t, right, right + Offset(g.ppb * .5, 0));
    expect(n.length, 2.5);
    final left = g.at(2, 72) + const Offset(2, 0);
    await drag(t, left, left + Offset(g.ppb * .25, 0));
    expect(n.start, 2.25);
    expect(n.end, 4.5);
    await settle(t);
  });

  mac('clique direito e duplo clique apagam; duplo clique no vazio não apaga a nota criada', (t) async {
    await sized(t);
    final c = TestDaw(notes: riff());
    await t.pumpWidget(host(c));
    final g = geoFor(c);
    await click(t, g.at(2.5, 72), buttons: kSecondaryMouseButton);
    expect(c.clip.notes.length, 7);
    await click(t, g.at(0.5, 60));
    await click(t, g.at(0.5, 60), gapMs: 50);
    expect(c.clip.notes.length, 6);
    // duplo clique no vazio: cria e fica
    await t.pump(const Duration(milliseconds: 500));
    await click(t, g.at(7.1, 70));
    await click(t, g.at(7.1, 70), gapMs: 50);
    expect(c.clip.notes.length, 7);
    await settle(t);
  });

  mac('seleção por retângulo (Shift), Delete apaga', (t) async {
    await sized(t);
    final c = TestDaw(notes: riff());
    await t.pumpWidget(host(c));
    final g = geoFor(c);
    await t.sendKeyDownEvent(LogicalKeyboardKey.shift);
    final m = await mouseDown(t, g.at(3.9, 74));
    await m.moveTo(g.at(6, 64));
    await t.pump();
    await shot(t, 'pr_marquee');
    await m.moveTo(g.at(6.2, 60, dy: 1));
    await t.pump();
    await m.up();
    await t.sendKeyUpEvent(LogicalKeyboardKey.shift);
    await t.pump();
    // 72 (2..4), 62, 65, 69 dentro; 71 começa em 6.5
    await key(t, LogicalKeyboardKey.delete);
    expect(c.clip.notes.map((n) => n.pitch).toList(), [60, 64, 67, 71]);
    await settle(t);
  });

  mac('Ctrl+A, Ctrl+C/V e Ctrl+D', (t) async {
    await sized(t);
    final c = TestDaw(notes: riff().take(3).toList());
    await t.pumpWidget(host(c));
    await key(t, LogicalKeyboardKey.keyA, ctrl: true);
    await key(t, LogicalKeyboardKey.keyD, ctrl: true);
    expect(c.clip.notes.length, 6);
    // 0..2 dura 2 tempos (≤ meio compasso): repete a cada 2 tempos
    expect(c.clip.notes.last.start, 3.5);
    await key(t, LogicalKeyboardKey.keyC, ctrl: true);
    c.seek(c.clip.start + 4);
    await key(t, LogicalKeyboardKey.keyV, ctrl: true);
    expect(c.clip.notes.length, 9);
    expect(c.clip.notes[6].start, 4);
    await key(t, LogicalKeyboardKey.keyV, ctrl: true);
    expect(c.clip.notes.length, 12);
    expect(c.clip.notes[9].start, 6); // colar de novo vai para depois
    expect(c.clip.length, 8);
    await key(t, LogicalKeyboardKey.keyV, ctrl: true);
    expect(c.clip.notes[12].start, 8);
    expect(c.clip.length, 12); // cresceu até o compasso que contém a cópia
    await settle(t);
  });

  mac('duplicar ignora a ligadura que passa do compasso', (t) async {
    await sized(t);
    final c = TestDaw(notes: riff());
    await t.pumpWidget(host(c));
    await key(t, LogicalKeyboardKey.keyA, ctrl: true);
    await key(t, LogicalKeyboardKey.keyD, ctrl: true);
    expect(c.clip.notes.length, 16);
    expect(c.clip.notes[8].start, 8); // B4 acaba em 9, mas começa em 6.5: repete a cada 2 compassos
    expect(c.clip.length, 16);
    await settle(t);
  });

  mac('setas transpõem e movem; segurar é um passo só', (t) async {
    await sized(t);
    final c = TestDaw(notes: riff().take(2).toList());
    await t.pumpWidget(host(c));
    final g = geoFor(c);
    await click(t, g.at(.5, 60));
    await key(t, LogicalKeyboardKey.arrowUp);
    expect(c.clip.notes[0].pitch, 61);
    await key(t, LogicalKeyboardKey.arrowUp, shift: true);
    expect(c.clip.notes[0].pitch, 73);
    await key(t, LogicalKeyboardKey.arrowRight);
    expect(c.clip.notes[0].start, .25);
    await key(t, LogicalKeyboardKey.arrowRight, shift: true);
    expect(c.clip.notes[0].start, 4.25);
    await key(t, LogicalKeyboardKey.arrowLeft, shift: true);
    await key(t, LogicalKeyboardKey.arrowLeft, shift: true);
    expect(c.clip.notes[0].start, 0); // para no início do clipe
    await key(t, LogicalKeyboardKey.escape);
    await key(t, LogicalKeyboardKey.arrowUp);
    expect(c.clip.notes[0].pitch, 73); // sem seleção a tecla não é do editor
    await settle(t);
  });

  mac('Alt + arrastar duplica', (t) async {
    await sized(t);
    final c = TestDaw(notes: riff());
    await t.pumpWidget(host(c));
    final g = geoFor(c);
    await t.sendKeyDownEvent(LogicalKeyboardKey.alt);
    final m = await mouseDown(t, g.at(.5, 60));
    await m.moveTo(g.at(1, 60));
    await t.pump();
    await t.sendKeyUpEvent(LogicalKeyboardKey.alt);
    await m.moveTo(g.at(4.5, 60));
    await t.pump();
    await m.up();
    await t.pump();
    expect(c.clip.notes.length, 9);
    expect(c.clip.notes[0].start, 0);
    expect(c.clip.notes.last.start, 4);
    c.undo();
    expect(c.clip.notes.length, 8);
    await settle(t);
  });

  mac('velocidade: arrastar a haste muda a seleção junto', (t) async {
    await sized(t);
    final c = TestDaw(notes: riff());
    await t.pumpWidget(host(c));
    final g = geoFor(c);
    await key(t, LogicalKeyboardKey.keyA, ctrl: true);
    final top = g.origin.dy + 280; // topo da faixa de velocidade
    final n = c.clip.notes[1]; // .5 em 1
    final x = g.origin.dx + (n.start - g.scrollX) * g.ppb + 1;
    final y = top + 6 + (1 - n.velocity) * 60;
    final m = await mouseDown(t, Offset(x, y));
    await m.moveTo(Offset(x, y - 12));
    await t.pump();
    await shot(t, 'pr_velocity');
    await m.up();
    await t.pump();
    expect(c.clip.notes[1].velocity, closeTo(.7, 1 / 127));
    expect(c.clip.notes[3].velocity, 1); // já no máximo
    expect(c.clip.notes[4].velocity, closeTo(.5, 1 / 127));
    await settle(t);
  });

  mac('fim do clipe arrastável pela régua', (t) async {
    await sized(t);
    final c = TestDaw(notes: riff());
    await t.pumpWidget(host(c));
    final g = geoFor(c);
    final end = Offset(g.origin.dx + (8 - g.scrollX) * g.ppb, 44 + 12);
    await drag(t, end, end + Offset(g.ppb * 2.1, 0));
    expect(c.clip.length, 10);
    await settle(t);
  });

  mac('quantizar chama o controlador com a grade do editor', (t) async {
    await sized(t);
    final c = TestDaw(notes: [MidiNote(pitch: 60, start: .3, length: .5)]);
    await t.pumpWidget(host(c));
    await key(t, LogicalKeyboardKey.keyQ);
    expect(c.quantized, 1);
    expect(c.clip.notes[0].start, .25);
    await settle(t);
  });

  mac('toque: toque cria, toque longo apaga, pinça dá zoom', (t) async {
    await sized(t);
    final c = TestDaw(notes: riff());
    await t.pumpWidget(host(c));
    final g = geoFor(c);
    await t.tapAt(g.at(3.1, 66));
    await t.pump();
    expect(c.clip.notes.length, 9);
    await t.pump(const Duration(milliseconds: 500));
    final lp = await t.startGesture(g.at(2.5, 72));
    await t.pump(const Duration(milliseconds: 600));
    await lp.up();
    await t.pump();
    expect(c.clip.notes.length, 8);
    expect(c.clip.notes.any((n) => n.pitch == 72), isFalse);
    // pinça
    final a = await t.startGesture(g.origin + const Offset(300, 100));
    final b = await t.startGesture(g.origin + const Offset(500, 100));
    await t.pump();
    await a.moveTo(g.origin + const Offset(200, 100));
    await b.moveTo(g.origin + const Offset(600, 100));
    await t.pump();
    await a.up();
    await b.up();
    await t.pump();
    expect(c.clip.notes.length, 8); // a pinça não criou nada
    await shot(t, 'pr_zoomed');
    await settle(t);
  });

  testWidgets('celular: altura própria, linhas maiores', (t) async {
    t.view.physicalSize = const Size(412 * 2.0, 860 * 2.0);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    final c = TestDaw(notes: riff());
    await t.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: RepaintBoundary(
            key: shotKey,
            child: Column(
              children: [
                Expanded(child: Container(color: Colors.black)),
                PianoRoll(c: c),
              ],
            ),
          ),
        ),
      ),
    );
    await t.pump();
    await shot(t, 'pr_phone');
    final size = t.getSize(find.byType(PianoRoll));
    expect(size.height, closeTo(860 * .62, 1));
    // alça: puxar para cima aumenta
    final top = t.getTopLeft(find.byType(PianoRoll));
    await t.dragFrom(top + const Offset(200, 3), const Offset(0, -100));
    await t.pump();
    expect(t.getSize(find.byType(PianoRoll)).height, greaterThan(size.height + 50));
    await settle(t);
  });

  mac('desempenho: 6000 notas', (t) async {
    await sized(t);
    final notes = [for (var i = 0; i < 6000; i++) MidiNote(pitch: 36 + (i * 7) % 48, start: i * .125, length: .25, velocity: (i % 10) / 10 + .05)];
    final c = TestDaw(notes: notes, clipLength: 750);
    await t.pumpWidget(host(c));
    await t.pump();
    final sw = Stopwatch()..start();
    for (var i = 0; i < 30; i++) {
      c.mutate((_) => c.clip.notes[i].velocity = .5);
      await t.pump();
    }
    sw.stop();
    // ignore: avoid_print
    print('30 quadros com 6000 notas: ${sw.elapsedMilliseconds} ms');
    await key(t, LogicalKeyboardKey.keyA, ctrl: true);
    final g = geoFor(c);
    final sw2 = Stopwatch()..start();
    await drag(t, g.at(0.05, 36), g.at(1.05, 38), steps: 10);
    sw2.stop();
    // ignore: avoid_print
    print('arraste de 6000 notas selecionadas (10 passos): ${sw2.elapsedMilliseconds} ms');
    await settle(t);
  });
}
