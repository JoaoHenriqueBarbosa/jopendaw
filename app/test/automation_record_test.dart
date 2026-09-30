import 'dart:math' as math;

import 'package:flutter/material.dart' hide Curve;
import 'package:flutter_test/flutter_test.dart';
import 'package:jopendaw_app/daw/automation_math.dart';
import 'package:jopendaw_app/daw/automation_mode.dart';
import 'package:jopendaw_app/daw/automation_record.dart';
import 'package:jopendaw_app/daw/controller.dart';
import 'package:jopendaw_app/daw/effects.dart';
import 'package:jopendaw_app/daw/instruments.dart';
import 'package:jopendaw_app/daw/model.dart';

import 'fake_engine.dart';

const pan = AutoTarget(AutoKind.pan);
const volume = AutoTarget(AutoKind.volume);
const cutoff = AutoTarget(AutoKind.instrument, param: 13);
const unison = AutoTarget(AutoKind.instrument, param: 9);

/// Controlador com uma faixa de áudio (0) e um sintetizador (1).
DawController rig(FakeEngine e) {
  final c = fakeController(e);
  c.addInstrumentTrack(TrackKind.synth);
  return c;
}

List<AutoPoint> pts(List<(double, double)> l, {double curve = 0}) => [for (final (b, v) in l) AutoPoint(beat: b, value: v, curve: curve)];

/// Pan mexido como o mixer faz (o valor passa pela gravação antes de entrar no documento).
void movePan(DawController c, double v, {int track = 0}) {
  c.autoRec.value(track, pan, v);
  c.mutate((d) => d.tracks[track].pan = v);
}

void moveGain(DawController c, double v, {int track = 0}) {
  c.autoRec.value(track, volume, v);
  c.mutate((d) => d.tracks[track].gain = v);
}

/// Um gesto de controle como a interface faz: anuncia, guarda o ponto de desfazer e arrasta.
void grab(DawController c, int track, AutoTarget t) {
  c.autoRec.touch(track, t);
  c.checkpoint();
}

AutoLane laneOf(DawController c, AutoTarget t, {int track = 0}) => c.doc.tracks[track].lanes.firstWhere((l) => l.target == t);

double at(DawController c, AutoTarget t, double beat, {int track = 0}) {
  final r = c.autoInfo(track, t)!;
  return autoValueAt(laneOf(c, t, track: track).points, beat, r.fixed, warp: r.warp);
}

void main() {
  late FakeEngine e;
  setUp(() => e = FakeEngine());

  testWidgets('botão da barra troca o modo; seletor da raia sobrepõe o da barra', (tester) async {
    final c = rig(FakeEngine());
    final lane = c.addLane(0, pan);
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: Column(
            children: [
              AutoModeMenu(c: c, compact: false),
              AutoLaneModeButton(c: c, lane: lane),
            ],
          ),
        ),
      ),
    );
    expect(find.byTooltip('Automação: Ler. Só toca a automação; mexer no controle não grava.'), findsOneWidget);
    await tester.tap(find.byTooltip('Automação: Ler. Só toca a automação; mexer no controle não grava.'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Toque').last);
    await tester.pumpAndSettle();
    expect(c.autoRec.mode, AutoMode.touch);
    expect(find.text('Toque'), findsOneWidget);
    expect(find.text('T'), findsOneWidget, reason: 'a raia segue a barra');
    await tester.tap(find.text('T'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trava').last);
    await tester.pumpAndSettle();
    expect(c.autoRec.laneModes[lane.id], AutoMode.latch);
    expect(c.autoRec.modeFor(0, pan), AutoMode.latch);
    expect(c.autoRec.modeFor(0, volume), AutoMode.touch);
  });

  group('afinamento', () {
    test('senoide de 4 s (8 batidas a 120 bpm) vira poucos pontos com erro < 1%', () {
      // 1 Hz, amplitude 0,5 em torno de 0,5, uma amostra por quadro de 60 Hz
      double f(double beat) => 0.5 + 0.5 * math.sin(2 * math.pi * beat / 2);
      final samples = [for (var i = 0; i <= 240; i++) (i / 30, f(i / 30))];
      final out = simplifyAutoSamples(samples, norm: (v) => v);
      expect(out.length, lessThanOrEqualTo(90), reason: '241 amostras devem virar poucas dezenas');
      expect(out.first, samples.first);
      expect(out.last, samples.last);
      final ps = pts(out);
      var worst = 0.0;
      for (final (b, v) in samples) {
        worst = math.max(worst, (autoValueAt(ps, b, 0) - v).abs());
      }
      expect(worst, lessThan(0.01));
    });

    test('a escala do controle conta: o erro é medido em posição do fader, não em ganho', () {
      // rampa reta na escala do fader: cada amostra na curva do fader
      final samples = [for (var i = 0; i <= 120; i++) (i / 15, faderToGain(i / 120))];
      final out = simplifyAutoSamples(samples, norm: gainToFader);
      expect(out.length, 2, reason: 'uma reta na escala do fader são dois pontos');
      // em ganho linear não seria reta
      final linear = simplifyAutoSamples(samples, norm: (g) => g / 2);
      expect(linear.length, greaterThan(4));
    });

    test('valor constante e pouca amostra: sem inflar; NaN, infinito e fora de ordem caem', () {
      final flat = simplifyAutoSamples([for (var i = 0; i < 100; i++) (i * 0.05, 0.3)], norm: (v) => v);
      expect(flat, [(0.0, 0.3), (4.95, 0.3)]);
      expect(simplifyAutoSamples(const [], norm: (v) => v), isEmpty);
      final dirty = simplifyAutoSamples([(0, 0.1), (1, double.nan), (2, 0.2), (double.infinity, 0.3), (1.5, 0.9), (3, 0.3)], norm: (v) => v);
      expect(dirty.every((p) => p.$1.isFinite && p.$2.isFinite), isTrue);
      expect(dirty.map((p) => p.$1), [0, 2, 3]);
      // na mesma batida vale a última
      expect(simplifyAutoSamples([(1, 0.1), (1, 0.7)], norm: (v) => v), [(1.0, 0.7)]);
    });

    test('parâmetro de opções/inteiros: só as trocas, em degrau', () {
      final out = simplifyAutoSamples([(0, 1), (1, 1), (2, 3), (3, 3), (4, 3), (5, 2), (6, 2)], norm: (v) => v, stepped: true);
      expect(out, [(0.0, 1.0), (2.0, 1.0), (2.0, 3.0), (5.0, 3.0), (5.0, 2.0), (6.0, 2.0)]);
    });

    test('milhares de amostras não estouram (iterativo) e ficam poucas', () {
      final samples = [for (var i = 0; i < 50000; i++) (i / 60, 0.5 + 0.4 * math.sin(i / 3000))];
      final out = simplifyAutoSamples(samples, norm: (v) => v);
      expect(out.length, lessThan(400));
    });
  });

  group('encaixe na automação (função pura)', () {
    test('região substituída, vizinhança preservada, valores de antes e depois nos limites', () {
      final ex = pts([(0, 0), (8, 1)]);
      final out = applyAutoTake(existing: ex, take: [(2, 0.9), (3, 0.9)], mode: AutoMode.latch, fallback: 0);
      expect(out.first.beat, 0);
      expect(out.last.beat, 8);
      // antes: o valor da reta antiga em 2 (0,25), depois em 3 (0,375)
      expect(autoValueAt(out, 1.999, 0), closeTo(0.25, 0.01));
      expect(autoValueAt(out, 2.5, 0), closeTo(0.9, 1e-9));
      expect(autoValueAt(out, 3.001, 0), closeTo(0.375, 0.01));
      expect(autoValueAt(out, 5, 0), closeTo(0.625, 1e-9), reason: 'a reta antiga segue igual fora da região');
      expect(autoValueAt(out, 1, 0), closeTo(0.125, 1e-9));
      expect(ex.length, 2, reason: 'a lista de entrada não muda');
    });

    test('trecho curvo cortado ao meio: a curva vizinha não se deforma', () {
      final ex = pts([(0, 0), (8, 1)], curve: 0.6);
      final out = applyAutoTake(existing: ex, take: [(3, 0.2), (4, 0.2)], mode: AutoMode.latch, fallback: 0);
      for (final b in [0.5, 1.0, 2.0, 2.9, 4.1, 5.0, 6.5, 7.9]) {
        expect(autoValueAt(out, b, 0), closeTo(autoValueAt(ex, b, 0), 0.02), reason: 'batida $b');
      }
    });

    test('a mesma coisa na escala do fader (warp)', () {
      final w = (toNorm: gainToFader, fromNorm: faderToGain);
      final ex = pts([(0, 0), (8, 2)], curve: -0.4);
      final out = applyAutoTake(existing: ex, take: [(3, 0.5), (4, 0.5)], mode: AutoMode.touch, fallback: 1, warp: w, norm: gainToFader);
      // depois da rampa (4,25) volta a ser a curva antiga
      for (final b in [0.5, 1.5, 2.9, 4.3, 5.0, 6.5, 7.9]) {
        expect(
          autoValueAt(out, b, 0, warp: w),
          closeTo(autoValueAt(ex, b, 0, warp: w), 0.04),
          reason: 'batida $b',
        );
      }
    });

    test('Toque sem automação antes: volta ao valor fixo de antes', () {
      final out = applyAutoTake(existing: const [], take: [(2, 0.8), (3, 0.9)], mode: AutoMode.touch, fallback: 0.25);
      expect(out.last.beat, closeTo(3 + autoTouchRamp, 1e-9));
      expect(out.last.value, 0.25);
      expect(autoValueAt(out, 100, 0), 0.25);
      // antes do gesto também valia o fixo
      expect(autoValueAt(out, 1, 0), 0.25);
    });

    test('Trava/Escrever sem pontos depois: a raia segue no último valor; com pontos depois, degrau de volta', () {
      final none = applyAutoTake(existing: pts([(0, 0.1)]), take: [(1, 0.7), (2, 0.9)], mode: AutoMode.latch, fallback: 0.1);
      expect(autoValueAt(none, 50, 0), 0.9);
      final some = applyAutoTake(existing: pts([(0, 0.1), (10, 0.5)]), take: [(1, 0.7), (2, 0.9)], mode: AutoMode.write, fallback: 0.1);
      expect(autoValueAt(some, 2.0001, 0), closeTo(0.1 + 0.4 * 0.2, 0.01));
      final steps = some.where((p) => p.beat == 2).toList();
      expect(steps.length, 2, reason: 'degrau: dois pontos na mesma batida');
    });

    test('take vazio não muda nada; começo em 0 não põe ponto antes', () {
      expect(applyAutoTake(existing: pts([(0, 0.3)]), take: const [], mode: AutoMode.touch, fallback: 0).length, 1);
      final out = applyAutoTake(existing: const [], take: [(0, 0.6), (1, 0.7)], mode: AutoMode.latch, fallback: 0.2);
      expect(out.first.beat, 0);
      expect(out.first.value, 0.6);
      expect(out.length, 2);
    });

    test('parâmetro em degraus: o retorno do Toque é imediato, sem rampa', () {
      final out = applyAutoTake(existing: pts([(0, 1), (8, 5)]), take: [(2, 3), (3, 4)], mode: AutoMode.touch, fallback: 1, stepped: true);
      expect(out.where((p) => p.beat == 3).length, 2);
    });
  });

  group('gravação sobre o controlador', () {
    test('Ler (padrão): mexer tocando não grava nada', () {
      final c = rig(e);
      c.beat.value = 1;
      c.playing.value = true;
      grab(c, 0, pan);
      movePan(c, 0.5);
      c.beat.value = 2;
      movePan(c, 0.7);
      c.playing.value = false;
      expect(c.doc.tracks[0].lanes, isEmpty);
      expect(c.autoRec.mode, AutoMode.read);
    });

    test('parado não grava, mesmo armado', () {
      final c = rig(e);
      c.autoRec.setMode(AutoMode.latch);
      movePan(c, 0.5);
      c.autoRec.touch(0, pan);
      expect(c.doc.tracks[0].lanes, isEmpty);
      expect(c.autoRec.openTargets, 0);
    });

    test('Toque: grava só enquanto segura, volta ao automatizado com rampa; desfaz numa vez', () {
      final c = rig(e);
      final lane = c.addLane(0, pan);
      lane.points.addAll(pts([(0, -1), (8, 1)]));
      c.autoRec.setMode(AutoMode.touch);
      c.beat.value = 1;
      c.playing.value = true;
      // sem mexer: nada
      c.beat.value = 2;
      grab(c, 0, pan);
      movePan(c, 0.0);
      c.beat.value = 2.5;
      movePan(c, 0.3);
      c.beat.value = 3;
      movePan(c, 0.3);
      c.beat.value = 3.5;
      c.autoRec.release(0, pan);
      // depois de soltar, andar não grava
      c.beat.value = 5;
      movePan(c, 0.9); // sem toque anunciado: vira outro gesto (implícito) e é gravado, mas só a partir daqui
      c.autoRec.release(0, pan);
      c.playing.value = false;

      final l = laneOf(c, pan);
      expect(l.points.first.beat, 0);
      expect(l.points.last.beat, 8);
      expect(at(c, pan, 1), closeTo(-0.75, 1e-9), reason: 'vizinhança antes intacta');
      expect(at(c, pan, 2.5), closeTo(0.3, 0.02));
      expect(at(c, pan, 3.2), closeTo(0.3, 0.05), reason: 'ainda dentro da rampa: entre 0,3 e o valor antigo');
      expect(at(c, pan, 6.5), closeTo(0.625, 1e-9), reason: 'reta antiga fora da região');
      expect(at(c, pan, 4), closeTo(0.0, 0.05), reason: 'já voltou à reta antiga (0 em 4)');
      // só um passo de desfazer para a passada inteira (o segundo é o addLane)
      expect(c.autoRec.openTargets, 0);
      c.undo();
      expect(laneOf(c, pan).points.map((p) => (p.beat, p.value)), [(0.0, -1.0), (8.0, 1.0)]);
      expect(c.doc.tracks[0].pan, 0, reason: 'o valor fixo também volta');
      c.redo();
      expect(at(c, pan, 2.5), closeTo(0.3, 0.02));
      c.undo();
      c.undo();
      expect(c.doc.tracks[0].lanes, isEmpty, reason: 'o segundo desfazer já é o addLane');
    });

    test('Trava: segura, solta e mantém o último valor até parar; depois volta ao antigo', () {
      final c = rig(e);
      final lane = c.addLane(0, pan);
      lane.points.addAll(pts([(0, -1), (10, 1)]));
      c.autoRec.setMode(AutoMode.latch);
      c.beat.value = 1;
      c.playing.value = true;
      grab(c, 0, pan);
      movePan(c, 0.0);
      c.beat.value = 2;
      movePan(c, 0.4);
      c.autoRec.release(0, pan);
      for (final b in [3.0, 4.0, 5.0]) {
        c.beat.value = b;
      }
      c.playing.value = false;
      expect(at(c, pan, 2.0), closeTo(0.4, 0.02));
      expect(at(c, pan, 4.5), closeTo(0.4, 1e-9), reason: 'manteve até parar em 5');
      expect(at(c, pan, 5.001), closeTo(-1 + 2 * 0.5, 0.01), reason: 'depois de 5 volta à reta antiga');
      expect(at(c, pan, 10), 1);
      expect(at(c, pan, 0.5), closeTo(-0.9, 1e-9));
    });

    test('Trava sem pontos depois: fica no último valor para sempre', () {
      final c = rig(e);
      c.autoRec.setMode(AutoMode.latch);
      c.beat.value = 0;
      c.playing.value = true;
      grab(c, 0, pan);
      movePan(c, -0.5);
      c.beat.value = 4;
      c.autoRec.release(0, pan);
      c.playing.value = false;
      expect(at(c, pan, 100), closeTo(-0.5, 1e-9));
      expect(at(c, pan, 2), closeTo(-0.5, 1e-9));
    });

    test('Escrever com modo próprio na raia: grava desde o começo o valor fixo, sobrescrevendo', () {
      final c = rig(e);
      c.doc.tracks[0].pan = 0.25;
      final lane = c.addLane(0, pan);
      lane.points.addAll(pts([(0, -1), (4, -1), (12, 1)]));
      c.autoRec.setLaneMode(lane.id, AutoMode.write);
      c.beat.value = 2;
      c.playing.value = true;
      for (final b in [2.2, 2.5, 3.0, 4.0, 5.0, 6.0]) {
        c.beat.value = b;
      }
      c.playing.value = false;
      expect(at(c, pan, 1), closeTo(-1, 1e-9), reason: 'antes de 2 igual');
      expect(at(c, pan, 2.5), closeTo(0.25, 1e-9));
      expect(at(c, pan, 5.9), closeTo(0.25, 1e-9));
      expect(at(c, pan, 12), 1);
      expect(at(c, pan, 8), closeTo(-1 + 2 * (8 - 4) / 8, 0.02), reason: 'a rampa antiga depois de 6 segue igual');
    });

    test('Escrever pela barra começa no primeiro toque no controle e segue até parar', () {
      final c = rig(e);
      c.autoRec.setMode(AutoMode.write);
      c.beat.value = 0;
      c.playing.value = true;
      c.beat.value = 1; // nada foi tocado ainda
      grab(c, 0, pan);
      movePan(c, 0.6);
      c.autoRec.release(0, pan);
      c.beat.value = 2;
      c.beat.value = 3;
      c.playing.value = false;
      final l = laneOf(c, pan);
      expect(l.points.first.beat, 1);
      expect(l.points.last.beat, 3);
      expect(at(c, pan, 2.5), closeTo(0.6, 1e-9));
    });

    test('loop: cada volta grava por cima, a última vale', () {
      final c = rig(e);
      c.doc.loopOn = true;
      c.doc.loopStart = 0;
      c.doc.loopEnd = 4;
      c.autoRec.setMode(AutoMode.latch);
      c.beat.value = 0;
      c.playing.value = true;
      grab(c, 0, pan);
      movePan(c, 0.2);
      for (final b in [1.0, 2.0, 3.0, 3.9]) {
        c.beat.value = b;
      }
      // volta do loop
      c.beat.value = 0.05;
      movePan(c, 0.8);
      c.beat.value = 1.0;
      c.beat.value = 2.0;
      c.autoRec.release(0, pan);
      c.playing.value = false;
      expect(at(c, pan, 1.0), closeTo(0.8, 0.01), reason: 'segunda volta vale onde passou');
      expect(at(c, pan, 1.9), closeTo(0.8, 0.01));
      expect(at(c, pan, 3.0), closeTo(0.2, 0.01), reason: 'onde a segunda volta não chegou fica a primeira');
      final ps = laneOf(c, pan).points;
      for (var i = 1; i < ps.length; i++) {
        expect(ps[i].beat, greaterThanOrEqualTo(ps[i - 1].beat), reason: 'em ordem');
      }
    });

    test('Toque no loop: soltar numa volta e agarrar de novo na próxima', () {
      final c = rig(e);
      final lane = c.addLane(0, pan);
      lane.points.addAll(pts([(0, 0), (4, 0)]));
      c.doc.loopOn = true;
      c.doc.loopEnd = 4;
      c.autoRec.setMode(AutoMode.touch);
      c.beat.value = 0;
      c.playing.value = true;
      c.beat.value = 1;
      grab(c, 0, pan);
      movePan(c, 0.5);
      c.beat.value = 2;
      c.autoRec.release(0, pan);
      c.beat.value = 3.9;
      c.beat.value = 0.1; // volta
      c.beat.value = 1;
      grab(c, 0, pan);
      movePan(c, -0.5);
      c.beat.value = 1.5;
      c.autoRec.release(0, pan);
      c.beat.value = 3;
      c.playing.value = false;
      expect(at(c, pan, 1.2), closeTo(-0.5, 0.05), reason: 'a volta 2 sobrepôs a 1');
      expect(at(c, pan, 1.9), closeTo(0.5, 0.2), reason: 'a volta 1 ainda vale onde a 2 não passou (com a rampa)');
      expect(at(c, pan, 3.5), closeTo(0, 1e-9));
    });

    test('Toque em parâmetro logarítmico grava na escala do knob (setParam de verdade)', () {
      final c = rig(e);
      c.autoRec.setMode(AutoMode.touch);
      c.beat.value = 0;
      c.playing.value = true;
      grab(c, 1, cutoff);
      // varredura de 250 Hz a 8 kHz em 8 batidas, reta na escala do botão
      final spec = TrackKind.synth.params.firstWhere((p) => p.id == 13);
      for (var i = 0; i <= 64; i++) {
        c.beat.value = i / 8;
        c.setParam(1, 13, spec.fromNorm(spec.toNorm(250) + (spec.toNorm(8000) - spec.toNorm(250)) * i / 64));
      }
      c.autoRec.release(1, cutoff);
      c.playing.value = false;
      final l = laneOf(c, cutoff, track: 1);
      expect(l.points.length, lessThan(6), reason: 'reta na escala do botão são poucos pontos (${l.points.length})');
      expect(at(c, cutoff, 4, track: 1), closeTo(math.sqrt(250 * 8000), 30), reason: 'meio do caminho = média geométrica');
      expect(l.points.every((p) => p.value >= 20 && p.value <= 20000), isTrue);
    });

    test('parâmetro inteiro grava degraus', () {
      final c = rig(e);
      c.autoRec.setMode(AutoMode.latch);
      c.beat.value = 0;
      c.playing.value = true;
      grab(c, 1, unison);
      c.setParam(1, 9, 2);
      c.beat.value = 1;
      c.setParam(1, 9, 2);
      c.beat.value = 2;
      c.setParam(1, 9, 5);
      c.beat.value = 3;
      c.autoRec.release(1, unison);
      c.playing.value = false;
      final l = laneOf(c, unison, track: 1);
      expect(l.points.where((p) => p.beat == 2).length, 2, reason: 'degrau');
      expect(at(c, unison, 1.5, track: 1), 2);
      expect(at(c, unison, 2.5, track: 1), 5);
    });

    test('volume: 0 e o máximo passam, nunca NaN nem fora da faixa', () {
      final c = rig(e);
      c.autoRec.setMode(AutoMode.latch);
      c.beat.value = 0;
      c.playing.value = true;
      grab(c, 0, volume);
      moveGain(c, 0);
      c.beat.value = 1;
      moveGain(c, double.nan); // ignorado
      moveGain(c, 99); // vira o máximo
      c.beat.value = 2;
      moveGain(c, double.infinity); // ignorado
      moveGain(c, 0);
      c.beat.value = 3;
      c.autoRec.release(0, volume);
      c.playing.value = false;
      final l = laneOf(c, volume);
      expect(l.points.isNotEmpty, isTrue);
      for (final p in l.points) {
        expect(p.value.isFinite && p.beat.isFinite && p.curve.isFinite, isTrue);
        expect(p.value, inInclusiveRange(0, maxGain));
      }
      expect(l.points.map((p) => p.value), containsAll([0.0, maxGain]));
    });

    test('envio: grava o nível do envio pelo setSend', () {
      final c = rig(e);
      final bus = c.addBusTrack();
      expect(c.setSend(0, bus.id, level: 0.5, undoable: true), isTrue);
      final target = AutoTarget(AutoKind.send, ref: bus.id);
      c.autoRec.setMode(AutoMode.latch);
      c.beat.value = 0;
      c.playing.value = true;
      grab(c, 0, target);
      c.setSend(0, bus.id, level: 1.0);
      c.beat.value = 2;
      c.setSend(0, bus.id, level: 0.25);
      c.autoRec.release(0, target);
      c.beat.value = 3;
      c.playing.value = false;
      expect(at(c, target, 0), closeTo(1.0, 1e-9));
      expect(at(c, target, 1), allOf(greaterThan(0.25), lessThan(1.0)), reason: 'rampa entre os dois valores');
      expect(at(c, target, 3), closeTo(0.25, 1e-9));
    });

    test('parâmetro sem automação (sidechain): avisa e não grava', () {
      final c = rig(e);
      final fx = c.addEffect(0, EffectKind.compressor);
      c.autoRec.setMode(AutoMode.touch);
      c.beat.value = 0;
      c.playing.value = true;
      c.setEffectParam(0, fx.id, 10, 1);
      expect(c.autoRec.notice, isNotNull);
      c.playing.value = false;
      expect(c.doc.tracks[0].lanes, isEmpty);
    });

    test('durante a gravação de áudio/MIDI não grava automação e avisa', () {
      final c = rig(e);
      c.autoRec.setMode(AutoMode.latch);
      c.beat.value = 0;
      c.playing.value = true;
      c.recording = true;
      grab(c, 0, pan);
      movePan(c, 0.5);
      expect(c.autoRec.notice, contains('gravação'));
      expect(c.autoRec.openTargets, 0);
      c.recording = false;
      c.playing.value = false;
      expect(c.doc.tracks[0].lanes, isEmpty);
    });

    test('mudar de modo no meio da reprodução fecha o que estava gravando', () {
      final c = rig(e);
      c.autoRec.setMode(AutoMode.latch);
      c.beat.value = 0;
      c.playing.value = true;
      grab(c, 0, pan);
      movePan(c, 0.5);
      c.beat.value = 2;
      c.autoRec.setMode(AutoMode.read);
      expect(c.autoRec.openTargets, 0);
      expect(at(c, pan, 1), closeTo(0.5, 1e-9));
      c.playing.value = false;
    });

    test('o controle mostra o valor fixo enquanto grava, e a curva depois; o motor não recebe a raia gravada', () {
      final c = rig(e);
      final lane = c.addLane(0, pan);
      lane.points.addAll(pts([(0, -1), (8, 1)]));
      c.autoRec.setMode(AutoMode.touch);
      c.beat.value = 4;
      c.playing.value = true;
      expect(c.liveTargetValue(0, pan, 0.9), closeTo(0.0, 1e-9), reason: 'antes de agarrar: a curva');
      c.autoSyncNow();
      e.log!.clear();
      grab(c, 0, pan);
      movePan(c, 0.9);
      expect(c.liveTargetValue(0, pan, 0.9), 0.9, reason: 'gravando: o que a mão pôs');
      final clear = e.log!.lastIndexWhere((x) => x.first == 'auto_clear');
      expect(clear, greaterThanOrEqualTo(0), reason: 'a raia saiu do motor');
      expect(e.log!.skip(clear).where((x) => x.first == 'auto_lane'), isEmpty);
      e.log!.clear();
      c.beat.value = 5;
      c.autoRec.release(0, pan);
      expect(e.sent('auto_lane'), isNotEmpty, reason: 'ao soltar a raia (com o gravado) volta ao motor');
      c.beat.value = 7;
      expect(c.liveTargetValue(0, pan, 0.9), closeTo(0.75, 1e-6), reason: 'depois da rampa, a curva antiga');
      c.playing.value = false;
    });

    test('sem raia no alvo: a gravação cria a raia e ela já vale', () {
      final c = rig(e);
      c.autoRec.setMode(AutoMode.touch);
      c.beat.value = 1;
      c.playing.value = true;
      grab(c, 0, pan);
      movePan(c, 0.7);
      c.beat.value = 2;
      c.autoRec.release(0, pan);
      c.playing.value = false;
      final l = laneOf(c, pan);
      expect(l.open, isTrue);
      expect(c.automatedTarget(0, pan), isTrue);
      expect(at(c, pan, 1.5), closeTo(0.7, 1e-9));
      expect(at(c, pan, 20), closeTo(0.0, 1e-9), reason: 'depois da rampa volta ao valor fixo de antes (0)');
      // desfazer numa vez remove a raia criada
      c.undo();
      expect(c.doc.tracks[0].lanes, isEmpty);
      expect(c.doc.tracks[0].pan, 0);
    });

    test('a passada com vários alvos vira um passo só', () {
      final c = rig(e);
      c.autoRec.setMode(AutoMode.latch);
      c.beat.value = 0;
      c.playing.value = true;
      grab(c, 0, pan);
      movePan(c, 0.5);
      grab(c, 1, cutoff);
      c.setParam(1, 13, 1000);
      c.beat.value = 3;
      c.setParam(1, 13, 4000);
      moveGain(c, 1.5);
      c.autoRec.releaseAll();
      c.playing.value = false;
      expect(c.doc.tracks[0].lanes.length, 2);
      expect(c.doc.tracks[1].lanes.length, 1);
      c.undo();
      expect(c.canUndo, isFalse, reason: 'um passo desfez tudo');
      expect(c.doc.tracks.expand((t) => t.lanes), isEmpty);
      expect(c.doc.tracks[0].pan, 0);
      expect(c.doc.tracks[0].gain, 1);
    });

    test('pontos do gesto longo ficam poucos (afinados)', () {
      final c = rig(e);
      c.autoRec.setMode(AutoMode.latch);
      c.beat.value = 0;
      c.playing.value = true;
      grab(c, 0, pan);
      // 4 s a 60 Hz de uma senoide larga
      for (var i = 0; i <= 240; i++) {
        c.beat.value = i / 30;
        movePan(c, 0.8 * math.sin(2 * math.pi * i / 120));
      }
      c.autoRec.release(0, pan);
      c.playing.value = false;
      final l = laneOf(c, pan);
      expect(l.points.length, lessThanOrEqualTo(70));
      var worst = 0.0;
      for (var i = 0; i <= 240; i++) {
        worst = math.max(worst, (at(c, pan, i / 30) - 0.8 * math.sin(2 * math.pi * i / 120)).abs());
      }
      expect(worst, lessThan(0.02), reason: 'erro < 1% da faixa (−1..1)');
    });

    test('só o alvo da raia com modo próprio grava; os outros seguem o da barra', () {
      final c = rig(e);
      final a = c.addLane(0, pan);
      c.autoRec.setLaneMode(a.id, AutoMode.latch);
      c.beat.value = 0;
      c.playing.value = true;
      expect(c.autoRec.modeFor(0, pan), AutoMode.latch);
      expect(c.autoRec.modeFor(0, volume), AutoMode.read);
      grab(c, 0, pan);
      movePan(c, 0.5);
      moveGain(c, 0.5);
      c.beat.value = 1;
      c.autoRec.releaseAll();
      c.playing.value = false;
      expect(c.doc.tracks[0].lanes.map((l) => l.target), [pan]);
      expect(a.points, isNotEmpty);
    });
  });
}
