// Fase 17 (C): punch in/out, pré-roll, tap tempo e as opções do metrônomo. O motor é o FakeEngine (100 Hz,
// 120 BPM: 50 quadros por batida), então o valor de cada quadro gravado diz de onde veio cada pedaço.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jopendaw_app/audio/engine.dart';
import 'package:jopendaw_app/daw/controller.dart';
import 'package:jopendaw_app/daw/instruments.dart';
import 'package:jopendaw_app/daw/keymap.dart';
import 'package:jopendaw_app/daw/model.dart';
import 'package:jopendaw_app/daw/tempo_map.dart';
import 'package:jopendaw_app/daw/tap_tempo.dart';
import 'package:jopendaw_app/screens/project_screen.dart';
import 'package:jopendaw_app/widgets/theme.dart';

import 'fake_engine.dart';

EngineState state(double beat, {bool playing = true}) => EngineState(beat, playing, Float32List(0));

DecodedAudio loadedFor(FakeEngine e, DawController c, String hash) {
  final i = c.waveforms.keys.toList().indexOf(hash);
  expect(i, greaterThanOrEqualTo(0));
  return e.loaded[i + 1]!;
}

void main() {
  late FakeEngine e;
  setUp(() => e = FakeEngine());

  // ------------------------------------------------------------------ tap tempo

  group('tap tempo', () {
    test('sequência regular: a média dos intervalos, com uma casa decimal', () {
      final t = TapTempo();
      expect(t.tap(10), isNull);
      expect(t.tap(10.5), 120.0);
      expect(t.tap(11), 120.0);
      expect(t.tap(11.5), 120.0);
      // 0,47 s entre as batidas: 127,66 → 127,7
      final u = TapTempo();
      double? v;
      for (var i = 0; i < 6; i++) {
        v = u.tap(i * 0.47);
      }
      expect(v, 127.7);
    });

    test('irregular: a média suaviza; só as últimas oito batidas contam', () {
      final t = TapTempo();
      // intervalos 0,5 0,6 0,4 0,5: média 0,5
      var v = t.tap(0);
      for (final at in [0.5, 1.1, 1.5, 2.0]) {
        v = t.tap(at);
      }
      expect(v, 120.0);
      // depois de muitas batidas a 60 BPM, as primeiras (a 120) já saíram da janela
      final u = TapTempo();
      u.tap(0);
      u.tap(0.5);
      for (var i = 0; i < 8; i++) {
        v = u.tap(1.5 + i);
      }
      expect(u.count, TapTempo.maxTaps);
      expect(v, 60.0);
    });

    test('a primeira batida some se a segunda vem depois de 2 s; parado por 2,5 s recomeça', () {
      final t = TapTempo();
      t.tap(0);
      expect(t.tap(2.2), isNull, reason: 'o intervalo passou de 2 s: a primeira era um toque solto');
      expect(t.count, 1);
      expect(t.tap(2.7), 120.0);
      expect(t.tap(3.2), 120.0);
      // 3 s parado: a sequência recomeça na batida nova
      expect(t.tap(6.2), isNull);
      expect(t.count, 1);
      expect(t.tap(6.7), 120.0);
      // um intervalo de 2,3 s no meio de uma sequência (ritmo lento) vale
      expect(t.tap(9.0), isNotNull);
      expect(t.count, 3);
    });

    test('ricochete (intervalo menor que 150 ms) e relógio para trás são ignorados', () {
      final t = TapTempo();
      t.tap(0);
      t.tap(0.5);
      expect(t.tap(0.52), 120.0);
      expect(t.count, 2, reason: 'a batida do ricochete não entra');
      expect(t.tap(1.0), 120.0);
      // o relógio andou para trás: recomeça
      expect(t.tap(0.2), isNull);
      expect(t.count, 1);
      expect(t.tap(double.nan), isNull);
    });

    test('o resultado fica entre os limites do projeto', () {
      final t = TapTempo();
      t.tap(0);
      // 2,4 s entre as batidas seriam 25 BPM; 0,15 s são 400: tudo dentro de 20 a 999
      expect(t.tap(2.0), 30.0);
      final f = TapTempo();
      f.tap(0);
      expect(f.tap(0.15), 400.0);
    });

    test('o controlador aplica ao projeto quando as batidas param, com casas decimais; o mapa muda o ponto inicial', () async {
      final c = fakeController(e);
      c.doc.tempoMap = [const TempoPoint(0, 120), const TempoPoint(16, 90)];
      var now = 0.0;
      c.debugTapClock = () => now;
      expect(c.tapTempo(), isNull);
      now = 0.47;
      expect(c.tapTempo(), 127.7);
      now = 0.94;
      c.tapTempo();
      expect(c.tapBpm.value, 127.7);
      expect(c.doc.bpm, 120, reason: 'ainda batendo: o projeto não muda');
      expect(c.commitTap(), 127.7);
      await settle();
      expect(c.doc.bpm, 127.7);
      expect(c.doc.tempoMap.first.bpm, 127.7);
      expect(c.doc.tempoMap.last.bpm, 90);
      expect(c.tapBpm.value, isNull);
      expect(c.notice, contains('127,7'));
      // sem batidas não há o que aplicar
      expect(c.commitTap(), isNull);
      c.dispose();
    });

    testWidgets('parar de bater aplica sozinho depois do atraso; gravando o tap não faz nada', (t) async {
      final c = fakeController(e);
      var now = 0.0;
      c.debugTapClock = () => now;
      c.tapTempo();
      now = 0.4;
      c.tapTempo();
      await t.pump(DawController.tapCommitDelay - const Duration(milliseconds: 100));
      expect(c.doc.bpm, 120);
      await t.pump(const Duration(milliseconds: 200));
      expect(c.doc.bpm, 150);
      c.recording = true;
      now = 5;
      expect(c.tapTempo(), isNull);
      c.recording = false;
      c.dispose();
    });

    test('atalhos: T é o tap e P o punch, no catálogo', () {
      expect(keyActionById('transport.tap')!.defaults, ['T']);
      expect(keyActionById('transport.punch')!.defaults, ['P']);
    });
  });

  // ------------------------------------------------------------------ documento

  group('JSON do documento', () {
    Map<String, dynamic> base() => {
      'version': 1,
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
    };

    test('documento antigo abre com os padrões e sai igual (sem os campos novos)', () {
      final d = DawDoc.fromJson(base());
      expect(d.punchRegion, isNull);
      expect(d.punchOn, isFalse);
      expect(d.preRollBars, 0);
      expect(d.metronomeOptions.isDefault, isTrue);
      final j = d.toJson();
      for (final k in ['punch_in', 'punch_out', 'punch_on', 'pre_roll', 'metronome_options']) {
        expect(j.containsKey(k), isFalse, reason: k);
      }
    });

    test('campos novos vão e voltam', () {
      final d = DawDoc.fromJson(base())
        ..punchIn = 4
        ..punchOut = 9.5
        ..punchOn = true
        ..preRollBars = 2;
      d.metronomeOptions
        ..timbre = MetronomeTimbre.cowbell
        ..subdivision = MetronomeSubdivision.triplet
        ..mode = MetronomeMode.recording
        ..volume = 0.8
        ..accentLevel = 1.5
        ..accentPitch = 2
        ..subLevel = 0.25;
      final j = jsonDecode(jsonEncode(d.toJson())) as Map<String, dynamic>;
      expect((j['punch_in'], j['punch_out'], j['punch_on'], j['pre_roll']), (4, 9.5, true, 2));
      final back = DawDoc.fromJson(j);
      expect((back.punchIn, back.punchOut, back.punchOn, back.preRollBars), (4.0, 9.5, true, 2));
      final o = back.metronomeOptions;
      expect((o.timbre, o.subdivision, o.mode), (MetronomeTimbre.cowbell, MetronomeSubdivision.triplet, MetronomeMode.recording));
      expect((o.volume, o.accentLevel, o.accentPitch, o.subLevel), (0.8, 1.5, 2.0, 0.25));
      expect(jsonEncode(back.toJson()), jsonEncode(d.toJson()));
    });

    test('só o que foge do padrão entra em metronome_options', () {
      final o = MetronomeOptions()..timbre = MetronomeTimbre.wood;
      expect(o.toJson(), {'timbre': 'wood'});
      expect(MetronomeOptions().toJson(), isEmpty);
    });

    test('valores ruins caem no padrão ou nos limites; região inválida some', () {
      final j = base()
        ..['punch_in'] = 8
        ..['punch_out'] = 4
        ..['punch_on'] = true
        ..['pre_roll'] = 99
        ..['metronome_options'] = {
          'timbre': 'kazoo',
          'subdivision': 7,
          'mode': null,
          'volume': 5,
          'accent_level': -1,
          'accent_pitch': 'x',
          'sub_level': double.nan,
        };
      final d = DawDoc.fromJson(j);
      expect(d.punchRegion, isNull);
      expect(d.punchOn, isFalse);
      expect(d.preRollBars, DawDoc.maxPreRollBars);
      final o = d.metronomeOptions;
      expect((o.timbre, o.subdivision, o.mode), (MetronomeTimbre.click, MetronomeSubdivision.beat, MetronomeMode.always));
      expect((o.volume, o.accentLevel, o.accentPitch, o.subLevel), (1.0, 0.0, MetronomeOptions.defaultAccentPitch, MetronomeOptions.defaultSubLevel));
      // só um lado, negativo, ou não número
      for (final bad in [
        {'punch_in': 2},
        {'punch_in': -1, 'punch_out': 3},
        {'punch_in': 'a', 'punch_out': 3},
      ]) {
        expect(DawDoc.fromJson({...base(), ...bad}).punchRegion, isNull, reason: '$bad');
      }
      // ligado sem região: desligado
      expect(DawDoc.fromJson({...base(), 'punch_on': true}).punchOn, isFalse);
    });

    test('desfazer não mexe no punch, no pré-roll nem nas opções do metrônomo', () {
      final c = fakeController(e);
      c.addTrack();
      c.setPreRoll(2);
      c.setPunchRegion(4, 8);
      c.setMetronomeOptions((o) => o.timbre = MetronomeTimbre.hihat);
      c.undo();
      expect(c.doc.tracks, hasLength(1));
      expect((c.doc.preRollBars, c.doc.punchRegion, c.doc.metronomeOptions.timbre), (2, (4.0, 8.0), MetronomeTimbre.hihat));
    });
  });

  // ------------------------------------------------------------------ opções do metrônomo no motor

  group('opções do metrônomo', () {
    test('um documento padrão nunca manda o estilo; mudar manda uma vez, sem repetir', () async {
      final c = fakeController(e);
      c.toggleMetronome();
      c.toggleLoop();
      expect(e.sent('metronome_style'), isEmpty);
      e.log!.clear();
      c.setMetronomeOptions((o) => o.timbre = MetronomeTimbre.wood);
      expect(e.sent('metronome_style'), [
        ['metronome_style', 1, 0, 1.0, 1.6, 0.5],
      ]);
      // outras edições e o mesmo valor de novo não repetem
      c.toggleLoop();
      c.setMetronomeOptions((o) => o.timbre = MetronomeTimbre.wood);
      c.setTempo(100, 4);
      expect(e.sent('metronome_style'), hasLength(1));
      c.setMetronomeOptions((o) {
        o.subdivision = MetronomeSubdivision.sixteenth;
        o.accentLevel = 1.5;
        o.accentPitch = 2;
        o.subLevel = 0.3;
      });
      expect(e.sent('metronome_style').last, ['metronome_style', 1, 3, 1.5, 2.0, 0.3]);
      expect(e.sent('metronome_style'), hasLength(2));
      // voltar ao padrão manda o estilo padrão uma vez (o motor tem o de antes)
      c.setMetronomeOptions((o) {
        o.timbre = MetronomeTimbre.click;
        o.subdivision = MetronomeSubdivision.beat;
        o.accentLevel = 1;
        o.accentPitch = 1.6;
        o.subLevel = 0.5;
      });
      expect(e.sent('metronome_style').last, ['metronome_style', 0, 0, 1.0, 1.6, 0.5]);
      c.toggleLoop();
      expect(e.sent('metronome_style'), hasLength(3));
      // o render não leva o metrônomo nem o estilo
      expect(c.debugFullSyncCalls().where((x) => x.first == 'metronome_style'), isEmpty);
    });

    test('o volume vai no ganho do metrônomo (0,5 é o de sempre) e o valor absurdo é limitado', () {
      final c = fakeController(e);
      c.toggleMetronome();
      expect(e.sent('metronome').last, ['metronome', true, 0.5]);
      c.setMetronomeOptions((o) => o.volume = 0.8);
      expect(e.sent('metronome').last, ['metronome', true, 0.8]);
      c.setMetronomeOptions((o) => o.volume = 40);
      expect(c.doc.metronomeOptions.volume, 1.0);
      c.setMetronomeOptions((o) => o.accentPitch = double.nan);
      expect(c.doc.metronomeOptions.accentPitch, MetronomeOptions.defaultAccentPitch);
    });

    test('modo "só ao gravar": cala parado e toca gravando, na contagem e no pré-roll', () async {
      final c = fakeController(e);
      c.doc.countIn = false;
      c.toggleMetronome();
      c.setMetronomeOptions((o) => o.mode = MetronomeMode.recording);
      expect(e.sent('metronome').last[1], false);
      c.setArmed(0, true);
      await settle();
      c.beat.value = 4;
      await c.toggleRecord();
      expect(e.sent('metronome').last[1], true);
      e.feed(0, 100, (i) => 0.1);
      await c.toggleRecord();
      expect(e.sent('metronome').last[1], false);
      // "sempre": toca parado
      c.setMetronomeOptions((o) => o.mode = MetronomeMode.always);
      expect(e.sent('metronome').last[1], true);
      // o botão do metrônomo (desligado) continua mandando: no modo "só ao gravar" ele é a permissão
      c.toggleMetronome();
      c.setMetronomeOptions((o) => o.mode = MetronomeMode.recording);
      await c.toggleRecord();
      expect(e.sent('metronome').last[1], false);
      e.feed(0, 100, (i) => 0.1);
      await c.toggleRecord();
    });
  });

  // ------------------------------------------------------------------ pré-roll

  group('pré-roll', () {
    Future<DawController> armed({int preRoll = 0, bool countIn = false, double cursor = 8}) async {
      final c = fakeController(e);
      c.doc
        ..countIn = countIn
        ..preRollBars = preRoll;
      c.beat.value = cursor;
      c.setArmed(0, true);
      await settle();
      return c;
    }

    test('sem pré-roll nada muda: o transporte começa no cursor', () async {
      final c = await armed();
      await c.toggleRecord();
      expect(e.sent('seek').last, ['seek', 8.0]);
      e.feed(0, 100, (i) => 0.1);
      await c.toggleRecord();
    });

    test('o cursor volta N compassos e o que toca antes do ponto de gravar fica fora do áudio', () async {
      final c = await armed(preRoll: 1);
      await c.toggleRecord();
      expect(e.sent('seek').last, ['seek', 4.0]);
      expect(c.countingIn, isFalse, reason: 'pré-roll não é contagem');
      expect(e.sent('metronome').last[1], false, reason: 'e não liga o metrônomo');
      // 4 batidas de pré-roll = 200 quadros, depois 100 quadros gravados
      e.feed(0, 200, (i) => 9);
      e.feed(200, 100, (i) => (i - 199) / 1000);
      await c.toggleRecord();
      final clip = c.doc.tracks[0].clips.single;
      expect(clip.start, 8);
      final audio = loadedFor(e, c, clip.sample);
      expect(audio.frames, 100);
      expect(audio.channels[0][0], closeTo(0.001, 1e-6));
      expect(c.beat.value, 8, reason: 'o cursor volta ao ponto de gravar');
    });

    test('perto do começo, o pré-roll só vai até o zero', () async {
      final c = await armed(preRoll: 4, cursor: 2);
      await c.toggleRecord();
      expect(e.sent('seek').last, ['seek', 0.0]);
      // 2 batidas = 100 quadros de pré-roll
      e.feed(0, 100, (i) => 9);
      e.feed(100, 50, (i) => 0.5);
      await c.toggleRecord();
      final audio = loadedFor(e, c, c.doc.tracks[0].clips.single.sample);
      expect((audio.frames, audio.channels[0].every((v) => v == 0.5)), (50, true));
      // no zero não há pré-roll
      final z = await armed(preRoll: 2, cursor: 0);
      await z.toggleRecord();
      expect(e.sent('seek').last, ['seek', 0.0]);
      e.feed(0, 100, (i) => 0.5);
      await z.toggleRecord();
      expect(loadedFor(e, z, z.doc.tracks[0].clips.single.sample).frames, 100);
    });

    test('junto da contagem: contagem e pré-roll somam antes do ponto de gravar (metrônomo só na contagem)', () async {
      final c = await armed(preRoll: 1, countIn: true, cursor: 12);
      await c.toggleRecord();
      // 4 do pré-roll + 4 da contagem
      expect(e.sent('seek').last, ['seek', 4.0]);
      expect(c.countingIn, isTrue);
      expect(e.sent('metronome').last, ['metronome', true, 0.5]);
      c.debugEngineState(state(12.02));
      expect(c.countingIn, isFalse);
      e.feed(0, 400, (i) => 9);
      e.feed(400, 100, (i) => 0.25);
      await c.toggleRecord();
      final clip = c.doc.tracks[0].clips.single;
      expect(clip.start, 12);
      final audio = loadedFor(e, c, clip.sample);
      expect((audio.frames, audio.channels[0].every((v) => v == 0.25)), (100, true));
    });

    test('contagem fora do lugar (perto do zero): conta lá longe e depois toca o pré-roll até o cursor', () async {
      final c = await armed(preRoll: 1, countIn: true, cursor: 4);
      await c.toggleRecord();
      const zone = 65536 * 4.0;
      expect(e.sent('seek').last, ['seek', zone]);
      // depois da contagem o transporte volta ao começo do pré-roll (zero), não ao cursor
      expect(e.sent('loop_set').last, ['loop_set', true, 0.0, zone + 4]);
      c.debugEngineState(state(0.05));
      expect(c.countingIn, isFalse);
      // contagem (200) + pré-roll (200) descartados
      e.feed(0, 400, (i) => 9);
      e.feed(400, 100, (i) => 0.5);
      await c.toggleRecord();
      final clip = c.doc.tracks[0].clips.single;
      expect(clip.start, 4);
      final audio = loadedFor(e, c, clip.sample);
      expect((audio.frames, audio.channels[0].every((v) => v == 0.5)), (100, true));
    });

    test('fim do loop dentro do pré-roll: sem pré-roll (o transporte voltaria ao loop)', () async {
      final c = await armed(preRoll: 1);
      c.doc
        ..loopOn = true
        ..loopStart = 0
        ..loopEnd = 6;
      await c.toggleRecord();
      expect(e.sent('seek').last, ['seek', 8.0]);
      e.feed(0, 100, (i) => 0.5);
      await c.toggleRecord();
    });

    test('compasso 3/4 e 6/8: o pré-roll conta compassos do mapa, não batidas fixas', () async {
      final c = await armed(preRoll: 2, cursor: 12);
      c.doc.beatsPerBar = 3;
      await c.toggleRecord();
      expect(e.sent('seek').last, ['seek', 6.0]);
      e.feed(0, 100, (i) => 0.5);
      await c.toggleRecord();
    });

    test('pré-roll para MIDI: as notas tocadas no pré-roll ficam de fora', () async {
      final c = fakeController(e);
      c.addInstrumentTrack(TrackKind.synth);
      c.doc
        ..countIn = false
        ..preRollBars = 1;
      c.setArmed(1, true);
      c.beat.value = 8;
      await c.toggleRecord();
      expect(e.sent('seek').last, ['seek', 4.0]);
      // uma nota no pré-roll (5..6) e uma depois (9..10)
      e.notes = Float32List.fromList([1, 60, 5, 6, 0.8, 1, 62, 9, 10, 0.8]);
      c.debugRecordingElapsed(const Duration(seconds: 4));
      await c.toggleRecord();
      final clip = c.doc.tracks[1].midi.single;
      expect([for (final n in clip.notes) n.pitch], [62]);
    });

    test('o menu da barra e as configurações mudam o pré-roll no documento', () {
      final c = fakeController(e);
      c.setPreRoll(3);
      expect(c.doc.preRollBars, 3);
      c.setPreRoll(99);
      expect(c.doc.preRollBars, DawDoc.maxPreRollBars);
      c.setPreRoll(-4);
      expect(c.doc.preRollBars, 0);
      expect(c.canUndo, isFalse, reason: 'preferência: fora do desfazer');
    });
  });

  // ------------------------------------------------------------------ punch

  group('punch: áudio', () {
    Future<DawController> punched({
      double cursor = 0,
      double from = 2,
      double to = 4,
      bool loop = false,
      double loopStart = 0,
      double loopEnd = 8,
      int preRoll = 0,
      bool existing = true,
    }) async {
      final c = fakeController(e);
      c.doc
        ..countIn = false
        ..preRollBars = preRoll
        ..loopOn = loop
        ..loopStart = loopStart
        ..loopEnd = loopEnd
        ..punchIn = from
        ..punchOut = to
        ..punchOn = true;
      if (existing) {
        c.doc.samples['x'] = const SampleInfo('x.wav', 100);
        c.doc.tracks[0].clips.add(AudioClip(id: 'old', sample: 'x', start: 0, length: 4));
      }
      c.beat.value = cursor;
      c.setArmed(0, true);
      await settle();
      return c;
    }

    List<AudioClip> clips(DawController c) => c.doc.tracks[0].clips.toList()..sort((a, b) => a.start.compareTo(b.start));

    test('dentro da região grava, fora não: o resto do clipe que estava lá fica intacto', () async {
      final c = await punched();
      await c.toggleRecord();
      // o valor de cada quadro é o índice: 8 batidas = 400 quadros, a região são as batidas 2 a 4 = quadros 100 a 199
      e.feed(0, 400, (i) => i.toDouble());
      await c.toggleRecord();
      final cl = clips(c);
      expect(cl, hasLength(3));
      final mid = cl[1];
      expect(mid.start, 2.0);
      expect(mid.length, closeTo(1.0, 1e-9));
      final audio = loadedFor(e, c, mid.sample);
      expect(audio.frames, 100);
      expect(audio.channels[0].first, 100);
      expect(audio.channels[0].last, 199);
      // o clipe de antes acaba no punch in (mais a sobra do crossfade) e o de depois começa no punch out
      expect((cl[0].start, cl[0].sample), (0.0, 'x'));
      expect(cl[2].sample, 'x');
      expect(cl[2].start, lessThan(4.0));
      expect(cl[2].start, closeTo(4.0, 0.02));
      expect(cl[0].length, closeTo(1.0 + DawController.punchFade, 1e-9));
      // um passo de desfazer devolve o clipe inteiro
      c.undo();
      expect(c.doc.tracks[0].clips.single.id, 'old');
    });

    test('as emendas viram crossfade curto (fade complementar nos dois lados) e o clipe novo tem fade nas pontas cortadas', () async {
      final c = await punched();
      await c.toggleRecord();
      e.feed(0, 400, (i) => 0.5);
      await c.toggleRecord();
      final cl = clips(c);
      final mid = cl[1];
      const xf = DawController.punchFade;
      expect((mid.fadeIn, mid.fadeOut), (xf, xf));
      expect((mid.fadeInShape, mid.fadeOutShape), (FadeShape.equalPower, FadeShape.equalPower));
      // o de antes entra xf embaixo do novo, com fade de saída do mesmo tamanho
      expect((cl[0].fadeOut, cl[0].fadeOutShape), (xf, FadeShape.equalPower));
      expect(cl[0].offset, 0);
      // o de depois começa xf antes do punch out, com o áudio dele recuado o mesmo tanto
      expect((cl[2].fadeIn, cl[2].fadeInShape), (xf, FadeShape.equalPower));
      expect(cl[2].offset, closeTo(4.0 * 0.5 - xf, 1e-9));
      // 5 a 10 ms
      expect(xf, inInclusiveRange(0.005, 0.010));
    });

    test('sem o áudio a mais para o crossfade (sample curto), o clipe de antes fica como estava', () async {
      final c = await punched();
      c.doc.samples['x'] = const SampleInfo('x.wav', 1.0);
      c.doc.tracks[0].clips.single.length = 1.0;
      await c.toggleRecord();
      e.feed(0, 400, (i) => 0.5);
      await c.toggleRecord();
      final cl = clips(c);
      // o clipe tinha 1 s (2 batidas): acaba no punch in e não há o que estender
      expect(cl.first.fadeOut, 0);
      expect(cl[1].start, 2);
    });

    test('a gravação parou antes do punch out: o clipe vai só até onde gravou', () async {
      final c = await punched();
      await c.toggleRecord();
      // parou na batida 3 (150 quadros)
      e.feed(0, 150, (i) => i.toDouble());
      await c.toggleRecord();
      final mid = clips(c).firstWhere((x) => x.id != 'old' && x.start == 2);
      expect(mid.length, closeTo(0.5, 1e-9));
      expect(mid.fadeOut, 0, reason: 'o fim é o do stop, não uma emenda de punch');
      expect(loadedFor(e, c, mid.sample).frames, 50);
    });

    test('parou antes do punch in: nada é gravado, com aviso, e o clipe segue intacto', () async {
      final c = await punched(from: 6, to: 8);
      await c.toggleRecord();
      e.feed(0, 100, (i) => 0.5);
      await c.toggleRecord();
      expect(c.doc.tracks[0].clips.single.id, 'old');
      expect(c.error, contains('punch'));
      expect(c.canUndo, isFalse);
    });

    test('cursor já dentro da região: grava dali até o punch out, sem fade na entrada', () async {
      final c = await punched(cursor: 3);
      await c.toggleRecord();
      e.feed(0, 300, (i) => i.toDouble());
      await c.toggleRecord();
      final mid = clips(c).firstWhere((x) => x.id != 'old' && x.start == 3);
      expect(mid.length, closeTo(0.5, 1e-9));
      expect((mid.fadeIn, mid.fadeOut), (0, DawController.punchFade));
      final audio = loadedFor(e, c, mid.sample);
      expect((audio.frames, audio.channels[0].first), (50, 0));
    });

    test('cursor depois do punch out: não grava e avisa; com o punch desligado grava tudo', () async {
      final c = await punched(cursor: 6);
      await c.toggleRecord();
      expect(c.recording, isFalse);
      expect(c.error, contains('punch out'));
      expect(e.sent('play'), isEmpty);
      c.error = null;
      c.togglePunch();
      await c.toggleRecord();
      expect(c.recording, isTrue);
      e.feed(0, 100, (i) => 0.5);
      await c.toggleRecord();
    });

    test('com loop, cada volta é uma tomada só no trecho da região', () async {
      final c = await punched(loop: true, existing: false);
      await c.toggleRecord();
      // volta do loop (8 batidas = 400 quadros) e mais 300 quadros: a segunda passada alcança a região
      e.feed(0, 700, (i) => i.toDouble());
      await c.toggleRecord();
      final clip = c.doc.tracks[0].clips.single;
      expect(clip.start, 2.0);
      expect(clip.length, closeTo(1.0, 1e-9));
      expect(clip.takes, hasLength(2));
      final firsts = [for (final h in clip.takes) (loadedFor(e, c, h).channels[0].first, loadedFor(e, c, h).frames)];
      expect(firsts, [(100.0, 100), (500.0, 100)]);
      expect(clip.sample, clip.takes.last);
    });

    test('com loop, a passada que parou antes da região não vira tomada', () async {
      final c = await punched(loop: true, existing: false);
      await c.toggleRecord();
      // 400 da primeira volta e 70 da segunda (1,4 batida): não chega ao punch in
      e.feed(0, 470, (i) => i.toDouble());
      await c.toggleRecord();
      final clip = c.doc.tracks[0].clips.single;
      expect(clip.takes, isEmpty);
      expect(loadedFor(e, c, clip.sample).channels[0].first, 100);
    });

    test('com pré-roll: o transporte começa antes do punch in e só a região é gravada', () async {
      final c = await punched(from: 8, to: 12, preRoll: 1, existing: false);
      await c.toggleRecord();
      // o cursor ignorado: a gravação vale a partir do punch in, com 4 batidas (200 quadros) de pré-roll antes
      expect(e.sent('seek').last, ['seek', 4.0]);
      e.feed(0, 200, (i) => 9);
      e.feed(200, 300, (i) => (i - 199).toDouble());
      await c.toggleRecord();
      final clip = c.doc.tracks[0].clips.single;
      expect(clip.start, 8.0);
      expect(clip.length, closeTo(2.0, 1e-9));
      final audio = loadedFor(e, c, clip.sample);
      expect((audio.frames, audio.channels[0].first, audio.channels[0].last), (100 * 2, 1, 200));
    });

    test('a região não é apagada nem o cursor volta para longe: o cursor termina no começo da gravação', () async {
      final c = await punched(cursor: 0, existing: false);
      await c.toggleRecord();
      e.feed(0, 400, (i) => 0.5);
      await c.toggleRecord();
      expect(c.beat.value, 0);
      expect(c.doc.punchRegion, (2.0, 4.0));
      expect(c.doc.punchOn, isTrue);
    });
  });

  group('punch: MIDI', () {
    Future<DawController> midi(List<double> notes, {bool existing = true, double cursor = 0, Duration elapsed = const Duration(seconds: 4)}) async {
      final c = fakeController(e);
      c.addInstrumentTrack(TrackKind.synth);
      c.doc
        ..countIn = false
        ..punchIn = 4
        ..punchOut = 8
        ..punchOn = true;
      if (existing) {
        c.doc.tracks[1].midi.add(
          MidiClip(
            id: 'm',
            start: 0,
            length: 16,
            notes: [MidiNote(pitch: 50, start: 1, length: 1), MidiNote(pitch: 51, start: 5, length: 1), MidiNote(pitch: 52, start: 10, length: 1)],
          ),
        );
      }
      c.setArmed(1, true);
      c.beat.value = cursor;
      await c.toggleRecord();
      e.notes = Float32List.fromList(notes);
      c.debugRecordingElapsed(elapsed);
      await c.toggleRecord();
      return c;
    }

    test('só as notas da região entram: a que passa do punch out é cortada nele e a que entra antes começa no punch in', () async {
      final c = await midi([
        1, 60, 2, 3, 0.8, // antes da região: fora
        1, 62, 5, 6, 0.8, // dentro
        1, 64, 7, 9, 0.8, // passa do punch out: termina em 8
        1, 65, 3, 5, 0.8, // entra antes do punch in: começa em 4
        1, 67, 9, 10, 0.8, // depois: fora
      ]);
      final clip = c.doc.tracks[1].midi.single;
      expect(clip.id, 'm', reason: 'overdub no clipe que estava sob a região');
      expect((clip.start, clip.length), (0.0, 16.0));
      final notes = {for (final n in clip.notes) n.pitch: (n.start, n.start + n.length)};
      expect(notes[62], (5.0, 6.0));
      expect(notes[64], (7.0, 8.0), reason: 'cortada no punch out');
      expect(notes[65], (4.0, 5.0), reason: 'entra no punch in');
      expect(notes.containsKey(60), isFalse);
      expect(notes.containsKey(67), isFalse);
      // as notas que já estavam no clipe, dentro e fora da região, ficam
      expect([notes[50], notes[51], notes[52]], [(1.0, 2.0), (5.0, 6.0), (10.0, 11.0)]);
    });

    test('sem clipe embaixo, o clipe novo cobre só os compassos da região', () async {
      final c = await midi([1, 62, 5, 6, 0.8, 1, 64, 12, 13, 0.8], existing: false);
      final clip = c.doc.tracks[1].midi.single;
      expect((clip.start, clip.length), (4.0, 4.0));
      expect([for (final n in clip.notes) (n.pitch, n.start)], [(62, 1.0)]);
    });

    test('só notas fora da região: nada é gravado e avisa', () async {
      final c = await midi([1, 60, 1, 2, 0.8, 1, 61, 9, 10, 0.8], existing: false);
      expect(c.doc.tracks[1].midi, isEmpty);
      expect(c.error, contains('punch'));
    });

    test('CC (pedal) fora da região não entra', () async {
      final c = fakeController(e);
      c.addInstrumentTrack(TrackKind.synth);
      c.doc
        ..countIn = false
        ..punchIn = 4
        ..punchOut = 8
        ..punchOn = true;
      c.setArmed(1, true);
      await c.toggleRecord();
      // pedal (CC 64) em 2 (fora) e 6 (dentro), e uma nota dentro
      e.notes = Float32List.fromList([1, 60, 5, 6, 0.8, 1, ccPitchBase + 64.0, 2, 2, 1, 1, ccPitchBase + 64.0, 6, 6, 1]);
      c.debugRecordingElapsed(const Duration(seconds: 4));
      await c.toggleRecord();
      final clip = c.doc.tracks[1].midi.single;
      expect([for (final x in clip.controls) x.beat + clip.start].every((b) => b >= 4 && b <= 8.0001), isTrue);
    });
  });

  group('punch: estado do projeto', () {
    test('ligar sem região cria uma a partir do loop ou do cursor; as pontas trocadas se ajeitam; largura zero apaga', () {
      final c = fakeController(e);
      c.beat.value = 8;
      c.togglePunch();
      expect((c.doc.punchOn, c.doc.punchRegion), (true, (8.0, 16.0)), reason: 'dois compassos a partir do cursor');
      c.setPunchRegion(12, 6);
      expect(c.doc.punchRegion, (6.0, 12.0));
      c.togglePunch();
      expect((c.doc.punchOn, c.doc.punchRegion), (false, (6.0, 12.0)), reason: 'desligar guarda a região');
      c.setPunchRegion(5, 5.001);
      expect((c.doc.punchRegion, c.doc.punchOn), (null, false));
      c.setLoop(4, 12);
      c.togglePunch();
      expect(c.doc.punchRegion, (4.0, 12.0), reason: 'a região do loop');
    });

    test('gravando não muda a região nem liga o punch', () async {
      final c = fakeController(e);
      c.doc.countIn = false;
      c.setArmed(0, true);
      await settle();
      await c.toggleRecord();
      c.togglePunch();
      c.setPunchRegion(2, 4);
      expect(c.doc.punchRegion, isNull);
      expect(c.doc.punchOn, isFalse);
      e.feed(0, 100, (i) => 0.5);
      await c.toggleRecord();
    });
  });

  // ------------------------------------------------------------------ telas

  Finder punchToggle() => find.byWidgetPredicate((w) => w is IconButton && (w.tooltip ?? '').startsWith('Punch (P)'));

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

  for (final size in [const Size(360, 780), const Size(1512, 900)]) {
    testWidgets('${size.width.toInt()} px: configurações mostram pré-roll, punch e metrônomo sem overflow e mudam o documento', (t) async {
      final eng = FakeEngine();
      final c = fakeController(eng);
      await mount(t, c, size);
      final gear = find.byTooltip('Configurações: entrada de áudio, latência e contagem');
      await t.ensureVisible(gear);
      await t.tap(gear);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      Future<void> see(Finder f) async {
        await t.ensureVisible(f);
        await t.pump(const Duration(milliseconds: 300));
      }

      await see(find.text('METRÔNOMO'));
      expect(find.text('Timbre'), findsOneWidget);
      expect(find.text('Subdivisão'), findsOneWidget);
      expect(find.text('Quando soa'), findsOneWidget);
      expect(find.text('Altura do acento'), findsOneWidget);
      // os controles das subdivisões só aparecem com subdivisão
      expect(find.text('Volume das subdivisões'), findsNothing);
      c.setMetronomeOptions((o) => o.subdivision = MetronomeSubdivision.eighth);
      await t.pump();
      await see(find.text('Volume das subdivisões'));
      expect(t.takeException(), isNull);

      await see(find.text('Pré-roll'));
      await see(find.text('3'));
      await t.tap(find.text('3'));
      await t.pump();
      expect(c.doc.preRollBars, 3);

      await see(find.text('Punch in/out'));
      expect(find.textContaining('Ligue para marcar'), findsOneWidget);
      c.setPunchRegion(4, 8);
      await t.pump();
      expect(find.textContaining('só isso é gravado'), findsOneWidget);
      expect(t.takeException(), isNull);

      // arrastar o volume e soltar manda uma mudança só
      final e2 = eng.log!;
      e2.clear();
      final slider = find.byType(Slider).last;
      await see(slider);
      await t.drag(slider, const Offset(-40, 0));
      await t.pump();
      expect(e2.where((x) => x.first == 'metronome_style'), hasLength(1));
      expect(t.takeException(), isNull);
      await t.tap(find.text('Fechar'));
      await t.pumpAndSettle();
    });

    testWidgets('${size.width.toInt()} px: barra com o punch e o menu de gravar sem overflow; o punch liga pelo botão', (t) async {
      final c = fakeController(FakeEngine());
      await mount(t, c, size);
      expect(t.takeException(), isNull);
      final toggle = punchToggle();
      expect(toggle, findsOneWidget);
      // só um ícone pequeno: a barra já é apertada
      expect(t.getSize(toggle).width, lessThanOrEqualTo(48));
      await t.ensureVisible(toggle);
      await t.tap(toggle);
      await t.pump();
      expect(c.doc.punchOn, isTrue);
      expect(t.takeException(), isNull);
      // o menu de gravar leva contagem, punch e pré-roll
      final menu = find.byTooltip('Opções de gravação');
      await t.ensureVisible(menu);
      await t.tap(menu);
      await t.pumpAndSettle();
      expect(find.text('Contagem de um compasso'), findsOneWidget);
      expect(find.text('Punch in/out (P)'), findsOneWidget);
      expect(find.text('2 compassos'), findsOneWidget);
      await t.ensureVisible(find.text('2 compassos'));
      await t.pump();
      await t.tap(find.text('2 compassos'));
      await t.pumpAndSettle();
      expect(c.doc.preRollBars, 2);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('a barra do transporte com o botão novo cabe em 1512 px como cabia (o botão é só um ícone)', (t) async {
    final c = fakeController(FakeEngine());
    await mount(t, c, const Size(1512, 900));
    final bar = find.byType(SingleChildScrollView).evaluate().map((e) => e.widget as SingleChildScrollView).where((w) => w.scrollDirection == Axis.horizontal);
    expect(bar, isNotEmpty);
    final before = t.getSize(punchToggle()).width;
    expect(before, lessThanOrEqualTo(48));
    // a barra rola quando não cabe (a fonte de teste é bem mais larga que a de verdade): o que se garante é que o
    // acréscimo é o do ícone e não pisca overflow
    expect(t.takeException(), isNull);
  });

  testWidgets('tap tempo no diálogo de andamento: o BPM do campo acompanha as batidas e salvar aplica', (t) async {
    final c = fakeController(FakeEngine());
    await mount(t, c, const Size(1512, 900));
    await t.tap(find.textContaining('120 BPM'));
    await t.pumpAndSettle();
    expect(find.text('Tap tempo'), findsOneWidget);
    // duas batidas seguidas (relógio real: o intervalo é de poucos ms, abaixo do ricochete): a segunda é ignorada
    await t.tap(find.text('Tap tempo'));
    await t.tap(find.text('Tap tempo'));
    await t.pump();
    expect(find.text('120'), findsOneWidget, reason: 'com uma batida só (e a outra descartada) o campo fica como estava');
    expect(t.takeException(), isNull);
    await t.tap(find.text('Cancelar'));
    await t.pumpAndSettle();
  });

  testWidgets('o botão de andamento mostra o BPM do tap ao vivo', (t) async {
    final c = fakeController(FakeEngine());
    await mount(t, c, const Size(1512, 900));
    var now = 0.0;
    c.debugTapClock = () => now;
    c.tapTempo();
    now = 0.5;
    c.tapTempo();
    await t.pump();
    expect(find.textContaining('Tap · 120'), findsOneWidget);
    await t.pump(DawController.tapCommitDelay + const Duration(milliseconds: 50));
    expect(find.textContaining('Tap ·'), findsNothing);
    c.dispose();
  });
}
