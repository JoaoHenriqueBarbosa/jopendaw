// Faixas de controle do piano roll (pitch bend, modulação, sustain) contra o controlador de verdade:
// desenhar, mover e apagar pontos, reta, pedal, toque, desfazer e as ferramentas de tempo.
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jopendaw_app/daw/model.dart';

import 'piano_roll_test.dart' show G, TestDaw, click, drag, geoFor, host, key, mac, mouseDown, riff, settle;

MidiCc cc(int id, double beat, double value) => MidiCc(cc: id, beat: beat, value: value);

void main() {
  Future<void> sized(WidgetTester t) async {
    t.view.physicalSize = const Size(1200, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
  }

  // a faixa de controle começa 280 px abaixo da origem da grade e tem 72 de altura (6 de margem)
  double top(G g) => g.origin.dy + 280;
  double laneX(G g, double beat) => g.origin.dx + (beat - g.scrollX) * g.ppb;
  double bendY(G g, double v) => top(g) + 6 + (1 - (v + 1) / 2) * 60;
  double unitY(G g, double v) => top(g) + 6 + (1 - v) * 60;
  Offset bend(G g, double beat, double v) => Offset(laneX(g, beat), bendY(g, v));

  /// Escolhe a faixa de controle pelo menu do canto.
  Future<void> pick(WidgetTester t, G g, String name) async {
    await t.tapAt(Offset(25, top(g) + 36));
    await t.pumpAndSettle();
    await t.tap(find.text(name).last, warnIfMissed: false);
    await t.pumpAndSettle();
  }

  List<(int, double, double)> events(TestDaw c) => [for (final e in c.clip.controls) (e.cc, e.beat, double.parse(e.value.toStringAsFixed(3)))];

  mac('o menu do canto troca a faixa e mostra o nome dela', (t) async {
    await sized(t);
    final c = TestDaw(notes: riff());
    await t.pumpWidget(host(c, height: 420));
    final g = geoFor(c);
    expect(find.text('Vel.'), findsOneWidget);
    await t.tapAt(Offset(25, top(g) + 36));
    await t.pumpAndSettle();
    for (final n in ['Velocidade', 'Pitch bend', 'Modulação', 'Sustain']) {
      expect(find.text(n), findsWidgets, reason: n);
    }
    await t.tap(find.text('Pitch bend').last);
    await t.pumpAndSettle();
    expect(find.text('Bend'), findsOneWidget);
    expect(find.text('0 pontos'), findsOneWidget);
    // voltar à velocidade: o comportamento de sempre
    await pick(t, g, 'Velocidade');
    expect(find.text('Vel.'), findsOneWidget);
    expect(c.clip.controls, isEmpty);
    await settle(t);
  });

  mac('o lápis desenha o bend por onde passa, numa edição só no desfazer', (t) async {
    await sized(t);
    final c = TestDaw(notes: riff());
    await t.pumpWidget(host(c, height: 420));
    final g = geoFor(c);
    await pick(t, g, 'Pitch bend');
    expect(c.canUndo, isFalse);
    await drag(t, bend(g, 1, 0), bend(g, 3, 1), steps: 10);
    final e = events(c);
    expect(e.length, greaterThan(3));
    expect(e.every((x) => x.$1 == ccBend), isTrue);
    expect(e.first.$2, 1.0);
    expect(e.last.$2, 3.0);
    expect(e.last.$3, 1.0);
    final sorted = [...e]..sort((a, b) => a.$2.compareTo(b.$2));
    for (var i = 1; i < sorted.length; i++) {
      expect(sorted[i].$3, greaterThanOrEqualTo(sorted[i - 1].$3), reason: 'a curva sobe');
    }
    // o motor recebeu tudo em batidas absolutas do projeto (o clipe começa em 4)
    c.undo();
    expect(c.clip.controls, isEmpty);
    expect(c.canUndo, isFalse, reason: 'um gesto, um passo de desfazer');
    await settle(t);
  });

  mac('o centro do bend atrai: soltar perto do meio dá zero exato', (t) async {
    await sized(t);
    final c = TestDaw(notes: riff());
    await t.pumpWidget(host(c, height: 420));
    final g = geoFor(c);
    await pick(t, g, 'Pitch bend');
    await click(t, bend(g, 2, 0.02));
    expect(events(c), [(ccBend, 2.0, 0.0)]);
    await settle(t);
  });

  mac('a roda de modulação vai de 0 a 1 por clique', (t) async {
    await sized(t);
    final c = TestDaw(notes: riff());
    await t.pumpWidget(host(c, height: 420));
    final g = geoFor(c);
    await pick(t, g, 'Modulação');
    await click(t, Offset(laneX(g, 1), unitY(g, 1)));
    await click(t, Offset(laneX(g, 2), unitY(g, 0)));
    await click(t, Offset(laneX(g, 3), unitY(g, .5)));
    final e = events(c);
    expect([for (final x in e) (x.$1, x.$2)], [(ccMod, 1.0), (ccMod, 2.0), (ccMod, 3.0)]);
    expect([e[0].$3, e[1].$3], [1.0, 0.0]);
    expect(e[2].$3, closeTo(0.5, 0.02));
    await settle(t);
  });

  mac('arrastar um ponto o move na batida e no valor; um gesto que volta ao lugar não deixa histórico', (t) async {
    await sized(t);
    final c = TestDaw(notes: riff());
    // um valor que a faixa alcança exatamente (o bend anda nos 8192 degraus de cada lado, como o MIDI de 14 bits)
    const v = 0.5;
    c.clip.controls.add(cc(ccBend, 1, v));
    await t.pumpWidget(host(c, height: 420));
    final g = geoFor(c);
    await pick(t, g, 'Pitch bend');
    final m = await mouseDown(t, bend(g, 1, v));
    await m.moveTo(bend(g, 2, -0.5));
    await t.pump();
    await m.up();
    await t.pump();
    final e = events(c);
    expect(e, hasLength(1));
    expect(e.single.$2, 2.0);
    expect(e.single.$3, closeTo(-0.5, 0.03));
    c.undo();
    await t.pump();
    expect(c.clip.controls.single.beat, 1.0);
    expect(c.clip.controls.single.value, v);

    // pegar e devolver ao mesmo lugar: nada no histórico
    expect(c.canUndo, isFalse);
    final n = await mouseDown(t, bend(g, 1, v));
    await n.moveTo(bend(g, 3, -1));
    await t.pump();
    await n.moveTo(bend(g, 1, v));
    await t.pump();
    await n.up();
    await t.pump();
    expect(c.clip.controls.single.beat, 1.0);
    expect(c.canUndo, isFalse);
    await settle(t);
  });

  mac('botão direito e Alt+clique apagam um ponto; desfazer traz de volta', (t) async {
    await sized(t);
    final c = TestDaw(notes: riff());
    c.clip.controls.addAll([cc(ccBend, 1, 0.5), cc(ccBend, 3, -0.5)]);
    await t.pumpWidget(host(c, height: 420));
    final g = geoFor(c);
    await pick(t, g, 'Pitch bend');
    await click(t, bend(g, 1, 0.5), buttons: kSecondaryMouseButton);
    expect(events(c).map((e) => e.$2), [3.0]);
    await t.sendKeyDownEvent(LogicalKeyboardKey.alt);
    await click(t, bend(g, 3, -0.5));
    await t.sendKeyUpEvent(LogicalKeyboardKey.alt);
    expect(c.clip.controls, isEmpty);
    c.undo();
    c.undo();
    expect(c.clip.controls, hasLength(2));
    await settle(t);
  });

  mac('Shift ou "Linha reta" traçam uma reta entre a partida e a chegada', (t) async {
    await sized(t);
    final c = TestDaw(notes: riff());
    await t.pumpWidget(host(c, height: 420));
    final g = geoFor(c);
    await pick(t, g, 'Modulação');
    await t.sendKeyDownEvent(LogicalKeyboardKey.shift);
    final m = await mouseDown(t, Offset(laneX(g, 1), unitY(g, 0)));
    // vai e vem: a reta é refeita a cada passo a partir do que havia antes, sem restos
    await m.moveTo(Offset(laneX(g, 4), unitY(g, 1)));
    await t.pump();
    await m.moveTo(Offset(laneX(g, 3), unitY(g, 1)));
    await t.pump();
    await m.up();
    await t.pump();
    await t.sendKeyUpEvent(LogicalKeyboardKey.shift);
    final e = events(c);
    // de 1 a 3 com um ponto por passo da grade (1/16 de batida): 9 pontos e o do meio (beat 2) em 0,5
    expect(e, hasLength(9));
    expect(e.first, (ccMod, 1.0, 0.0));
    expect(e.last, (ccMod, 3.0, 1.0));
    expect(e[4].$3, closeTo(0.5, 0.02));
    c.undo();
    expect(c.clip.controls, isEmpty);

    // pelo menu: sem Shift
    await t.tapAt(Offset(25, top(g) + 36));
    await t.pumpAndSettle();
    await t.tap(find.text('Linha reta (ou Shift)'));
    await t.pumpAndSettle();
    await drag(t, Offset(laneX(g, 1), unitY(g, 1)), Offset(laneX(g, 2), unitY(g, 0)), steps: 3);
    expect(events(c), hasLength(5));
    await settle(t);
  });

  mac('pedal: o lápis pinta trechos embaixo e pintar sobre um trecho o apaga', (t) async {
    await sized(t);
    final c = TestDaw(notes: riff());
    await t.pumpWidget(host(c, height: 420));
    final g = geoFor(c);
    await pick(t, g, 'Sustain');
    final y = unitY(g, 1);
    await drag(t, Offset(laneX(g, 1), y), Offset(laneX(g, 3), y), steps: 4);
    expect(events(c), [(ccSustain, 1.0, 1.0), (ccSustain, 3.0, 0.0)]);
    // dentro do trecho: pinta "solto" de 1,5 a 2 e o pedal volta a descer em 2
    await drag(t, Offset(laneX(g, 1.5), y), Offset(laneX(g, 2), y), steps: 3);
    final e = [...events(c)]..sort((a, b) => a.$2.compareTo(b.$2));
    expect(e, [(ccSustain, 1.0, 1.0), (ccSustain, 1.5, 0.0), (ccSustain, 2.0, 1.0), (ccSustain, 3.0, 0.0)]);
    // desfaz um gesto de cada vez
    c.undo();
    expect(events(c), [(ccSustain, 1.0, 1.0), (ccSustain, 3.0, 0.0)]);
    await settle(t);
  });

  mac('toque: o dedo desenha, e segurar o dedo parado sobre um ponto o apaga', (t) async {
    await sized(t);
    final c = TestDaw(notes: riff());
    await t.pumpWidget(host(c, height: 420));
    final g = geoFor(c);
    await pick(t, g, 'Pitch bend');
    final from = bend(g, 1, 0), to = bend(g, 2, 0.5);
    final f = await t.createGesture(kind: PointerDeviceKind.touch);
    await f.down(from);
    for (var i = 1; i <= 5; i++) {
      await f.moveTo(Offset.lerp(from, to, i / 5)!);
      await t.pump();
    }
    await f.up();
    await t.pump();
    expect(c.clip.controls.length, greaterThan(2));
    // um ponto isolado e o dedo parado em cima dele por mais de meio segundo
    c.clip.controls
      ..clear()
      ..add(cc(ccBend, 3, 0.5));
    await t.pump();
    final h = await t.createGesture(kind: PointerDeviceKind.touch);
    await h.down(bend(g, 3, 0.5));
    await t.pump(const Duration(milliseconds: 700));
    await h.up();
    await t.pump();
    expect(c.clip.controls, isEmpty);
    c.undo();
    expect(c.clip.controls, hasLength(1));
    await settle(t);
  });

  mac('as ferramentas de tempo levam os controles junto: ×2 escala e Inverter no tempo espelha', (t) async {
    await sized(t);
    final c = TestDaw(notes: riff());
    c.clip.controls.addAll([cc(ccBend, 1, 0.5), cc(ccMod, 2, 0.25), cc(ccSustain, 1, 1), cc(ccSustain, 3, 0)]);
    await t.pumpWidget(host(c, height: 500));
    await t.pump();
    Future<void> open(List<String> path) async {
      await t.tap(find.text('Ferramentas'));
      await t.pumpAndSettle();
      for (final label in path) {
        await t.tap(find.text(label).last);
        await t.pumpAndSettle();
      }
    }

    await open(['Escalar o tempo', '×2 (dobro)']);
    expect([for (final e in c.clip.controls) (e.cc, e.beat)], [(ccBend, 2.0), (ccMod, 4.0), (ccSustain, 2.0), (ccSustain, 6.0)]);
    c.undo();
    expect([for (final e in c.clip.controls) (e.cc, e.beat)], [(ccBend, 1.0), (ccMod, 2.0), (ccSustain, 1.0), (ccSustain, 3.0)]);
    expect(c.clip.notes.first.length, 1.0, reason: 'desfazer volta notas e controles juntos');

    // as notas do riff vão de 0 a 9: espelhar leva o bend de 1 para 8 e a roda de 2 para 7; o pedal fica
    await open(['Seleção', 'Inverter no tempo']);
    expect([for (final e in c.clip.controls) (e.cc, e.beat)], [(ccBend, 8.0), (ccMod, 7.0), (ccSustain, 1.0), (ccSustain, 3.0)]);
    await settle(t);
  });

  mac('fora do clipe e além do fim: pontos ficam entre 0 e o fim do clipe', (t) async {
    await sized(t);
    final c = TestDaw(notes: riff());
    await t.pumpWidget(host(c, height: 420));
    final g = geoFor(c);
    await pick(t, g, 'Pitch bend');
    // solta bem depois do fim do clipe (8 batidas) e bem antes do começo
    await drag(t, bend(g, 7, 0), Offset(laneX(g, 12), bendY(g, 1)), steps: 6);
    expect(c.clip.controls.every((e) => e.beat >= 0 && e.beat <= 8), isTrue);
    c.undo();
    await drag(t, bend(g, 1, 0), Offset(laneX(g, -3), bendY(g, 1)), steps: 6);
    expect(c.clip.controls.every((e) => e.beat >= 0 && e.beat <= 8), isTrue);
    await settle(t);
  });

  mac('no sustain o menu não oferece "Linha reta" (lá o gesto é sempre pintura); no bend ele continua', (t) async {
    await sized(t);
    final c = TestDaw(notes: riff());
    await t.pumpWidget(host(c, height: 420));
    final g = geoFor(c);
    await pick(t, g, 'Sustain');
    await t.tapAt(Offset(25, top(g) + 36));
    await t.pumpAndSettle();
    expect(find.text('Linha reta (ou Shift)'), findsNothing);
    expect(find.text('Limpar sustain'), findsOneWidget);
    await t.tapAt(const Offset(5, 5));
    await t.pumpAndSettle();
    await pick(t, g, 'Pitch bend');
    await t.tapAt(Offset(25, top(g) + 36));
    await t.pumpAndSettle();
    expect(find.text('Linha reta (ou Shift)'), findsOneWidget);
    await t.tapAt(const Offset(5, 5));
    await settle(t);
  });

  mac('Ctrl+D e Ctrl+C/V levam os pontos de controle do trecho das notas', (t) async {
    await sized(t);
    final c = TestDaw(notes: riff().take(3).toList());
    c.clip.controls.addAll([cc(ccSustain, 0.5, 1), cc(ccSustain, 1.5, 0), cc(ccBend, 1, 0.5), cc(ccMod, 6, 0.9)]);
    await t.pumpWidget(host(c));
    await key(t, LogicalKeyboardKey.keyA, ctrl: true);
    await key(t, LogicalKeyboardKey.keyD, ctrl: true);
    // as três notas ocupam 0..2: a cópia vai 2 tempos adiante e leva pedal e bend do trecho
    final sustain = [
      for (final e in c.clip.controls)
        if (e.cc == ccSustain) (e.beat, e.value),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    expect(sustain, [(0.5, 1.0), (1.5, 0.0), (2.5, 1.0), (3.5, 0.0)]);
    expect(events(c).where((e) => e.$1 == ccBend).map((e) => (e.$2, e.$3)), containsAll([(1.0, 0.5), (3.0, 0.5), (4.0, 0.0)]));
    expect(events(c).where((e) => e.$1 == ccMod), [(ccMod, 6.0, 0.9)], reason: 'fora do trecho: fica onde está');
    // copiar e colar mais adiante
    await key(t, LogicalKeyboardKey.keyA, ctrl: true);
    await key(t, LogicalKeyboardKey.keyC, ctrl: true);
    c.seek(c.clip.start + 6);
    final before = c.clip.controls.length;
    await key(t, LogicalKeyboardKey.keyV, ctrl: true);
    expect(c.clip.controls.length, greaterThan(before));
    expect(events(c).where((e) => e.$1 == ccSustain && e.$2 >= 6.5).isNotEmpty, isTrue);
    c.undo();
    expect(c.clip.controls.length, before, reason: 'colar é uma edição só, com as notas e os pontos');
    await settle(t);
  });
}
