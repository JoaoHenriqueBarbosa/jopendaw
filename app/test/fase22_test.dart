// Fase 22: achados da fase 19 confirmados e corrigidos (detecção de swing mais rígida, swing de todas as
// resolutions ao aplicar padrão, plurais, Fatia x Zona, migração do volume do metrônomo, limites do tap
// tempo, cancelar a gravação pela posição do transporte e fade do punch out).
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jopendaw_app/audio/engine.dart';
import 'package:jopendaw_app/daw/controller.dart';
import 'package:jopendaw_app/daw/instruments.dart';
import 'package:jopendaw_app/daw/model.dart';
import 'package:jopendaw_app/daw/sampler_zones.dart';
import 'package:jopendaw_app/daw/step_sequencer.dart';
import 'package:jopendaw_app/daw/tap_tempo.dart';
import 'package:jopendaw_app/widgets/format.dart';

import 'fake_engine.dart';
import 'step_sequencer_ui_test.dart' show StepDaw, host, setView, starts;

MidiNote note(int pitch, double start) => MidiNote(pitch: pitch, start: start, length: 0.125, velocity: 0.8);

StepLayout grid(double step, {double length = 4}) => StepLayout(step: step, steps: stepsFor(length, 1, step));

EngineState state(double beat) => EngineState(beat, true, Float32List(0));

void main() {
  group('sequenciador: swing com rolos de 1/32', () {
    final l16 = grid(0.25);
    // chimbal 1/16 com rolo de 1/32 no fim, mais bumbo e caixa em passos pares e ímpares
    List<MidiNote> clip() => [
      for (var i = 0; i < 16; i++) note(42, i * 0.25),
      for (final b in [3.0, 3.25, 3.5, 3.75]) note(42, b + 0.125),
      note(36, 0), note(36, 0.25 * 7), note(38, 0.25 * 4), note(38, 0.25 * 12), note(38, 0.25 * 13),
    ];

    test('lê o swing apesar dos rolos; aplicar + tirar volta às notas originais', () {
      final n = clip();
      final orig = [for (final x in n) x.start];
      expect(detectSwing(n, l16), 0);
      final moved = retimeSwing(n, l16, 0, 0.41);
      expect(moved, greaterThan(0));
      expect(detectSwing(n, l16), closeTo(0.41, 1e-9));
      expect(detectSwings(n, 4).map((e) => e.$2), [closeTo(0.41, 1e-9)]);
      expect(removeSwing(n, 4, resolutions: ['1/16']), moved);
      expect([for (final x in n) x.start], orig);
    });

    test('rolo 1/32 sozinho e humanização continuam 0', () {
      expect(detectSwing([for (var i = 0; i < 16; i++) note(42, i * 0.125)], l16), 0);
      final n = clip();
      n[1].start += 0.03;
      expect(detectSwing(n, l16), 0);
    });
  });

  group('sequenciador: detectSwing rígido', () {
    final l16 = grid(0.25);

    test('humanização: um rolo 1/32 visto em 1/16 não é swing', () {
      // bumbo no passo 0 e chimbal em 1/32: 0, 0,125, 0,25, 0,375...
      final roll = [for (var i = 0; i < 16; i++) note(42, i * 0.125)];
      expect(detectSwing(roll, l16), 0);
      // só uma nota a meio passo no compasso, o resto reto
      final one = [for (var i = 0; i < 16; i++) note(42, i * 0.25), note(38, 0.375)];
      expect(detectSwing(one, l16), 0, reason: 'o passo ímpar tem nota reta e nota deslocada');
    });

    test('humanização (notas ímpares com desvios diferentes) lê 0', () {
      final n = [
        note(42, 0),
        note(42, 0.25 + 0.02),
        note(42, 0.5),
        note(42, 0.75 + 0.05),
      ];
      expect(detectSwing(n, l16), 0);
    });

    test('tercinas (1/8T) vistas em 1/16 não viram swing de 33%', () {
      final tri = [for (var i = 0; i < 12; i++) note(42, i / 3)];
      expect(detectSwing(tri, l16), 0, reason: 'há notas fora da grade nos passos pares');
      expect(detectSwing(tri, grid(1 / 3)), 0, reason: 'na resolução delas é reto');
    });

    test('precisa de nota num passo par e nota fora da grade nos pares derruba', () {
      final only = [note(42, 0.25 + 0.1), note(42, 0.75 + 0.1)];
      expect(detectSwing(only, l16), 0, reason: 'sem nenhuma nota nos passos pares');
      final swung = [for (var i = 0; i < 8; i++) note(42, i * 0.25 + (i.isOdd ? 0.1 : 0))];
      expect(detectSwing(swung, l16), closeTo(0.4, 1e-9));
      expect(detectSwing([...swung, note(38, 0.5 + 0.06)], l16), 0, reason: 'nota solta fora da grade num passo par');
    });

    test('todos os passos ímpares no mesmo deslocamento: 1%, 50% e 75%', () {
      for (final pct in [1, 33, 50, 75]) {
        final n = [for (var i = 0; i < 16; i++) note(42, i * 0.25 + (i.isOdd ? 0.25 * pct / 100 : 0))];
        expect(detectSwing(n, l16), closeTo(pct / 100, 1e-9), reason: '$pct%');
      }
      // 76% passa do máximo
      final n = [for (var i = 0; i < 4; i++) note(42, i * 0.25 + (i.isOdd ? 0.25 * 0.76 : 0))];
      expect(detectSwing(n, l16), 0);
    });

    test('1/8: a colcheia de contratempo reta é 0%; o swing comum a todas é lido (sem desempate)', () {
      final l8 = grid(0.5);
      expect(detectSwing([for (var i = 0; i < 8; i++) note(42, i * 0.5)], l8), 0);
      expect(detectSwing([for (var i = 0; i < 8; i++) note(42, i * 0.5 + (i.isOdd ? 0.5 * 0.75 : 0))], l8), closeTo(0.75, 1e-9));
      // semicolcheias (1/16) vistas em 1/8: o contratempo tem nota reta e nota a 50%
      expect(detectSwing([for (var i = 0; i < 16; i++) note(42, i * 0.25)], l8), 0);
    });
  });

  group('sequenciador: swing em qualquer resolução', () {
    List<MidiNote> swung16() => [for (var i = 0; i < 16; i++) note(42, i * 0.25 + (i.isOdd ? 0.1 : 0))];

    test('um swing de 1/16 aparece só em 1/16 (0% em 1/8 e em 1/32)', () {
      final n = swung16();
      final list = detectSwings(n, 4);
      expect(list, hasLength(1));
      expect(list.single.$1.step, 0.25);
      expect(list.single.$2, closeTo(0.4, 1e-9));
      expect(detectSwing(n, grid(0.5)), 0);
      expect(detectSwing(n, grid(0.125)), 0);
    });

    test('removeSwing tira o swing das resoluções pedidas e devolve as notas à grade reta', () {
      final n = swung16();
      expect(removeSwing(n, 4, resolutions: ['1/8', '1/16']), 8);
      expect([for (final x in n) x.start], [for (var i = 0; i < 16; i++) i * 0.25]);
      expect(removeSwing(n, 4, resolutions: ['1/16']), 0);
    });

    testWidgets('Padrões em outra resolução (Trap 1/32) tira o swing aplicado em 1/16', (t) async {
      await setView(t, 1000, 520);
      final c = StepDaw(notes: [for (var i = 0; i < 16; i++) note(42, i * 0.25 + (i.isOdd ? 0.25 * 0.4 : 0))]);
      await t.pumpWidget(host(c, width: 1000));
      expect(t.widget<Slider>(find.byKey(const ValueKey('step-swing'))).value, 40);
      await t.tap(find.byKey(const ValueKey('step-presets')));
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const ValueKey('step-preset-trap')));
      await t.tap(find.byKey(const ValueKey('step-preset-trap')));
      await t.pumpAndSettle();
      // o chimbal do Trap não sobrou com o deslocamento de 0,1 batida do swing antigo
      for (final s in starts(c, 42)) {
        expect(((s / 0.125) - (s / 0.125).round()).abs(), lessThan(1e-6), reason: 'nota em $s fora da grade de 1/32');
      }
      expect(detectSwings(c.clip.notes, 4), isEmpty);
      c.undo();
      await t.pump();
      expect(detectSwing(c.clip.notes, grid(0.25)), closeTo(0.4, 1e-9), reason: 'desfazer devolve o swing');
      await t.pump(const Duration(seconds: 1));
    });

    testWidgets('o controle acompanha o documento sem guardar swing no build (arrastar e depois mudar as notas)', (t) async {
      await setView(t, 1000, 520);
      final c = StepDaw(notes: [for (var i = 0; i < 16; i++) note(42, i * 0.25)]);
      await t.pumpWidget(host(c, width: 1000));
      final slider = find.byKey(const ValueKey('step-swing'));
      await t.drag(slider, const Offset(30, 0));
      await t.pump();
      final dragged = t.widget<Slider>(slider).value;
      expect(dragged, greaterThan(0));
      expect(t.widget<TextButton>(find.byKey(const ValueKey('step-swing-apply'))).onPressed, isNotNull);
      // as notas mudam por fora (piano roll): o controle mostra o que as notas têm, não o arrasto
      c.mutate((d) {
        final notes = d.tracks[0].midi[0].notes;
        for (var i = 0; i < notes.length; i++) {
          if (i.isOdd) notes[i].start += 0.125;
        }
      });
      await t.pump();
      expect(t.widget<Slider>(slider).value, 50);
      expect(t.widget<TextButton>(find.byKey(const ValueKey('step-swing-apply'))).onPressed, isNull);
      await t.pump(const Duration(seconds: 1));
    });

    testWidgets('"1 nota" no singular ao aplicar e ao copiar', (t) async {
      await setView(t, 1000, 520);
      final c = StepDaw(notes: [note(42, 0), note(42, 0.25)]);
      await t.pumpWidget(host(c, width: 1000));
      await t.drag(find.byKey(const ValueKey('step-swing')), const Offset(30, 0));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('step-swing-apply')));
      await t.pump();
      final notice = t.widget<Text>(find.byKey(const ValueKey('step-notice'))).data!;
      expect(notice, contains('(1 nota,'));
      expect(notice, isNot(contains('1 notas')));
      await t.tap(find.byKey(const ValueKey('step-swing-off')));
      await t.pump();
      expect(t.widget<Text>(find.byKey(const ValueKey('step-notice'))).data, 'Swing tirado (1 nota, em 1/16).');
      await t.pump(const Duration(seconds: 1));
    });
  });

  group('plural', () {
    test('o auxiliar cobre o singular de notas e arquivos', () {
      expect(plural(1, 'nota'), '1 nota');
      expect(plural(2, 'nota'), '2 notas');
      expect(plural(1, 'arquivo'), '1 arquivo');
    });
  });

  group('Fatia x Zona', () {
    DawTrack sampler(List<SamplerZone> z) => DawTrack(id: 't', name: 'x', color: 0, kind: TrackKind.sampler, zones: z);

    test('uma zona só aparada à mão é Zona, não Fatia', () {
      final rows = zoneRows(sampler([SamplerZone(id: 'a', sample: 's', root: 48, lo: 48, hi: 59, start: 0.2, end: 1.0)]));
      expect(rows.single.name, startsWith('Zona'));
    });

    test('zonas de samples diferentes, mesmo aparadas, são Zona', () {
      final rows = zoneRows(
        sampler([
          SamplerZone(id: 'a', sample: 's1', root: 48, lo: 48, hi: 48, oneShot: true, start: 0.1),
          SamplerZone(id: 'b', sample: 's2', root: 49, lo: 49, hi: 49, oneShot: true, start: 0.1),
        ]),
      );
      expect(rows.map((r) => r.name.split(' ').first), ['Zona', 'Zona']);
    });

    test('o resultado de Fatiar sample vira Fatia N, também com um ponto aparado depois', () {
      var n = 0;
      final z = sliceZones('abc', [0.0, 0.5, 1.0], () => 'z${n++}');
      expect(zoneRows(sampler(z)).map((r) => r.name.split(' ').first), ['Fatia', 'Fatia', 'Fatia']);
      z[1].start = 0.6;
      expect(isSlicedTrack(sampler(z)), isTrue);
      // a fatiada inteira, sem trecho nenhum (start 0 e end 0 em todas): zonas de áudio inteiro
      final whole = [
        SamplerZone(id: 'a', sample: 's', root: 48, lo: 48, hi: 48, oneShot: true),
        SamplerZone(id: 'b', sample: 's', root: 49, lo: 49, hi: 49, oneShot: true),
      ];
      expect(isSlicedTrack(sampler(whole)), isFalse);
    });
  });

  group('gravação e exportação', () {
    late FakeEngine e;
    setUp(() => e = FakeEngine());

    test('metrônomo: o documento antigo (versão 1) sem volume guardado fica em 50%', () {
      Map<String, dynamic> base(int version, {Map<String, dynamic>? options}) => {
        'version': version,
        'bpm': 120,
        'beats_per_bar': 4,
        'tracks': [],
        'samples': <String, dynamic>{},
        'loop_on': false,
        'loop_start': 0,
        'loop_end': 16,
        'metronome': false,
        'master_gain': 1,
        'master_pan': 0,
        'metronome_options': ?options,
      };
      expect(DawDoc.version, 2);
      final old = DawDoc.fromJson(base(1));
      expect(old.metronomeOptions.volume, 0.5, reason: 'o padrão de então era 50%');
      expect(DawDoc.fromJson(base(1, options: {'timbre': 'wood'})).metronomeOptions.volume, 0.5);
      // salvar de novo guarda o valor, e ele sobrevive à releitura já na versão 2
      final saved = old.toJson();
      expect(saved['version'], 2);
      expect((saved['metronome_options'] as Map)['volume'], 0.5);
      expect(DawDoc.fromJson(saved).metronomeOptions.volume, 0.5);
      // escolhido pela pessoa, vale; na versão 2 a ausência é o padrão novo
      expect(DawDoc.fromJson(base(1, options: {'volume': 0.8})).metronomeOptions.volume, 0.8);
      expect(DawDoc.fromJson(base(2)).metronomeOptions.volume, 0.6);
      expect(DawDoc.fromJson(base(2)).metronomeOptions.isDefault, isTrue);
    });

    test('tap tempo: a espera do commit cabe na janela da sequência e os limites estão documentados', () {
      expect(DawController.tapCommitWait(120), DawController.tapCommitDelay);
      expect(DawController.tapCommitWait(40), const Duration(milliseconds: 1950));
      expect(DawController.tapCommitWait(30), const Duration(milliseconds: 2600));
      expect(DawController.tapCommitWait(20), const Duration(milliseconds: 2600), reason: 'nunca além de resetAfter + folga');
      for (final bpm in [200.0, 60.0, 30.0, 24.0, 20.0]) {
        expect(DawController.tapCommitWait(bpm).inMilliseconds, lessThanOrEqualTo((TapTempo.resetAfter * 1000).round() + DawController.tapCommitSlack));
      }
      expect(TapTempo.slowestBpm, 24);
      expect(TapTempo.slowestSteadyBpm, 30);
      // regular a 30 BPM vale; a 24 BPM regular recomeça a cada batida
      final t = TapTempo();
      t.tap(0);
      expect(t.tap(2.0), 30);
      final slow = TapTempo();
      slow.tap(0);
      expect(slow.tap(2.5), isNull, reason: 'a segunda batida depois de firstGap descarta a primeira');
      // depois de lançado o ritmo a média pode cair a 24 BPM (intervalos de 2,5 s)
      final run = TapTempo();
      run.tap(0);
      run.tap(2.0);
      expect(run.tap(4.5), closeTo(26.7, 0.1));
      expect(run.count, 3);
      expect(run.tap(7.0), isNotNull);
      expect(run.tap(10.0), isNull, reason: 'intervalo de 3 s passa de resetAfter: recomeça');
      expect(run.count, 1);
    });

    Future<DawController> armed({int preRoll = 0, double cursor = 8}) async {
      final c = fakeController(e);
      c.doc
        ..countIn = false
        ..preRollBars = preRoll;
      c.beat.value = cursor;
      c.setArmed(0, true);
      await settle();
      return c;
    }

    test('parar logo depois do ponto de gravar (antes de o estado do motor chegar) não cancela', () async {
      final c = await armed(preRoll: 1);
      await c.toggleRecord();
      c.debugEngineState(state(7.99));
      // o transporte passou do ponto, mas nenhum estado novo chegou ainda
      c.beat.value = 8.05;
      await c.toggleRecord();
      expect(c.notice, isNot(contains('cancelada')), reason: 'não é "Gravação cancelada"');
      expect(c.recording, isFalse);
    });

    test('parar ainda no pré-roll continua cancelando', () async {
      final c = await armed(preRoll: 1);
      await c.toggleRecord();
      c.debugEngineState(state(7.0));
      await c.toggleRecord();
      expect(c.notice, contains('cancelada'));
    });

    test('punch out: o clipe ganha o fade de saída mesmo sem sobrar áudio depois do punch out', () async {
      final c = fakeController(e);
      c.doc
        ..countIn = false
        ..punchIn = 2
        ..punchOut = 4
        ..punchOn = true;
      c.beat.value = 0;
      c.setArmed(0, true);
      await settle();
      await c.toggleRecord();
      e.feed(0, 200, (i) => 0.5);
      c.debugEngineState(state(2));
      c.debugEngineState(state(4.0));
      for (var i = 0; i < 10 && c.doc.tracks[0].clips.isEmpty; i++) {
        await settle();
      }
      final clip = c.doc.tracks[0].clips.single;
      expect(clip.start, 2);
      expect(clip.fadeIn, DawController.punchFade);
      expect(clip.fadeOut, DawController.punchFade, reason: 'o fim é o punch out: emenda, não o stop da pessoa');
    });
  });
}
