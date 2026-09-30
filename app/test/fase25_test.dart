// Fase 25: swing do sequenciador com dica persistente, Passo zera o arrasto, Padrões só tira o swing
// conhecido, faixa fatiada tolerante, migração do volume do metrônomo, parar logo ao gravar, tap tempo
// sem empate e recusa de documento de versão futura (.jopendaw e sincronização).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jopendaw_app/daw/controller.dart';
import 'package:jopendaw_app/daw/instruments.dart';
import 'package:jopendaw_app/daw/model.dart';
import 'package:jopendaw_app/daw/sampler_zones.dart';
import 'package:jopendaw_app/daw/step_sequencer.dart';
import 'package:jopendaw_app/daw/sync.dart';
import 'package:jopendaw_app/daw/tap_tempo.dart';

import 'fake_engine.dart';
import 'fake_sync_api.dart';
import 'step_sequencer_ui_test.dart' show StepDaw, host, setView, starts;
import 'sync_test.dart' show docJson, opened, storeWith, trackName;

MidiNote note(int pitch, double start) => MidiNote(pitch: pitch, start: start, length: 0.125, velocity: 0.8);

StepLayout grid(double step, {double length = 4}) => StepLayout(step: step, steps: stepsFor(length, 1, step));

void main() {
  group('swing: dica persistente', () {
    final l16 = grid(0.25);
    // só nos passos pares (o 2º, o 4º...): contratempos
    List<MidiNote> offbeats() => [for (var i = 1; i < 16; i += 2) note(42, i * 0.25)];

    test('clipe só com contratempos: a leitura das notas dá 0, a dica dá o swing e tirar volta às notas', () {
      final n = offbeats();
      final orig = [for (final x in n) x.start];
      expect(retimeSwing(n, l16, 0, 0.4), 8);
      expect(detectSwing(n, l16), 0, reason: 'sem nota num passo ímpar a leitura não enxerga');
      final hint = encodeSwingHint('1/16', 0.4);
      expect(hint, '1/16:40');
      expect(swingFor(n, l16, hint), closeTo(0.4, 1e-9));
      expect(removeSwing(n, 4, hint: hint), 8);
      expect([for (final x in n) x.start], orig);
    });

    test('50% com rolo de 1/32: a leitura dá 0, a dica dá 50% e tirar volta às notas', () {
      final n = [for (var i = 0; i < 16; i++) note(42, i * 0.25), note(38, 0.125), note(38, 0.25 * 4 + 0.125)];
      final orig = [for (final x in n) x.start];
      retimeSwing(n, l16, 0, 0.5);
      expect(detectSwing(n, l16), 0);
      expect(swingFor(n, l16, '1/16:50'), 0.5);
      removeSwing(n, 4, hint: '1/16:50');
      expect([for (final x in n) x.start], orig);
    });

    test('dica que não bate com as notas é ignorada', () {
      final n = offbeats();
      retimeSwing(n, l16, 0, 0.4);
      expect(validSwingHint(n, 4, '1/16:40'), isNotNull);
      expect(validSwingHint(n, 4, '1/16:30'), isNull, reason: 'outro deslocamento');
      expect(validSwingHint(n, 4, '1/8:40'), isNull, reason: 'outra resolução');
      expect(validSwingHint(n, 4, 'lixo'), isNull);
      expect(validSwingHint(n, 4, '1/16:99'), isNull);
      expect(validSwingHint(n, 4, null), isNull);
      // alguém desfez o swing à mão (notas retas): a dica some
      for (final x in n) {
        x.start = (x.start / 0.25).floor() * 0.25;
      }
      expect(validSwingHint(n, 4, '1/16:40'), isNull);
      expect(swingFor(n, l16, '1/16:40'), 0);
      expect(removeSwing(n, 4, hint: '1/16:40'), 0, reason: 'nada anda com dica inválida');
    });

    test('40% em 1/16 lê 60% em 1/64, mas tirar pela dica leva as notas à grade de 1/16', () {
      final n = [for (var i = 0; i < 16; i++) note(42, i * 0.25)];
      final orig = [for (final x in n) x.start];
      retimeSwing(n, l16, 0, 0.4);
      final l64 = grid(0.0625);
      expect(swingFor(n, l64, '1/16:40'), closeTo(0.6, 1e-9), reason: 'na grade de 1/64 lê o que as notas dizem');
      removeSwing(n, 4, hint: '1/16:40');
      expect([for (final x in n) x.start], orig);
    });

    test('removeSwing não move notas que só por acaso formam swing em outra resolução', () {
      // colcheias a 0,4 passo de 1/16 (swing 40% em 1/16) mas pedimos só 1/8 e nenhuma dica
      final n = [for (var i = 0; i < 16; i++) note(42, i * 0.25 + (i.isOdd ? 0.1 : 0))];
      final before = [for (final x in n) x.start];
      expect(removeSwing(n, 4, resolutions: ['1/8']), 0);
      expect([for (final x in n) x.start], before);
    });

    test('o clipe guarda a dica no JSON só quando existe', () {
      final c = MidiClip(id: 'c', start: 0, length: 4);
      expect(c.toJson().containsKey('swing_hint'), isFalse);
      c.swingHint = '1/16:40';
      final back = MidiClip.fromJson(jsonDecode(jsonEncode(c.toJson())) as Map<String, dynamic>);
      expect(back.swingHint, '1/16:40');
      expect(MidiClip.fromJson({'id': 'x', 'start': 0, 'length': 4, 'notes': []}).swingHint, isNull);
    });

    testWidgets('Aplicar e Tirar swing num clipe só com contratempos voltam exatamente às notas', (t) async {
      await setView(t, 1000, 520);
      final orig = [for (var i = 1; i < 16; i += 2) i * 0.25];
      final c = StepDaw(notes: [for (final s in orig) note(42, s)]);
      await t.pumpWidget(host(c, width: 1000));
      final slider = find.byKey(const ValueKey('step-swing'));
      await t.drag(slider, const Offset(30, 0));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('step-swing-apply')));
      await t.pump();
      expect(c.clip.swingHint, startsWith('1/16:'));
      expect(starts(c, 42).first, greaterThan(0.25));
      // o controle lê o swing aplicado e "Tirar swing" está aceso
      expect(t.widget<Slider>(slider).value, greaterThan(0));
      expect(t.widget<TextButton>(find.byKey(const ValueKey('step-swing-off'))).onPressed, isNotNull);
      expect(t.widget<TextButton>(find.byKey(const ValueKey('step-swing-apply'))).onPressed, isNull);
      await t.tap(find.byKey(const ValueKey('step-swing-off')));
      await t.pump();
      expect(starts(c, 42), orig);
      expect(c.clip.swingHint, isNull);
      expect(t.widget<Slider>(slider).value, 0);
      // desfazer devolve o swing e a dica juntos
      c.undo();
      await t.pump();
      expect(c.clip.swingHint, startsWith('1/16:'));
      expect(t.widget<TextButton>(find.byKey(const ValueKey('step-swing-off'))).onPressed, isNotNull);
      await t.pump(const Duration(seconds: 1));
    });

    testWidgets('trocar o Passo zera o valor arrastado do swing', (t) async {
      await setView(t, 1000, 520);
      final c = StepDaw(notes: [for (var i = 0; i < 16; i++) note(42, i * 0.25)]);
      await t.pumpWidget(host(c, width: 1000));
      final slider = find.byKey(const ValueKey('step-swing'));
      await t.drag(slider, const Offset(30, 0));
      await t.pump();
      expect(t.widget<Slider>(slider).value, greaterThan(0));
      await t.tap(find.byKey(const ValueKey('step-res')));
      await t.pumpAndSettle();
      await t.tap(find.textContaining('1/8 ·').last);
      await t.pumpAndSettle();
      expect(t.widget<Slider>(slider).value, 0, reason: 'o arrasto de outra resolução não vale');
      expect(t.widget<TextButton>(find.byKey(const ValueKey('step-swing-apply'))).onPressed, isNull);
      await t.pump(const Duration(seconds: 1));
    });

    testWidgets('Padrões não move notas fora do padrão que só formam swing por acaso', (t) async {
      await setView(t, 1000, 520);
      // uma nota de outro instrumento (fora do kit) em 0,3: não é swing de nada
      final c = StepDaw(notes: [for (var i = 0; i < 16; i++) note(42, i * 0.25 + (i.isOdd ? 0.25 * 0.4 : 0)), note(60, 2.0), note(60, 2.0 + 1 / 3)]);
      await t.pumpWidget(host(c, width: 1000));
      await t.tap(find.byKey(const ValueKey('step-presets')));
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const ValueKey('step-preset-four')));
      await t.tap(find.byKey(const ValueKey('step-preset-four')));
      await t.pumpAndSettle();
      expect(starts(c, 60), [2.0, 2.0 + 1 / 3], reason: 'nota fora do kit e sem swing conhecido fica onde está');
      await t.pump(const Duration(seconds: 1));
    });
  });

  group('faixa fatiada tolerante', () {
    DawTrack sampler(List<SamplerZone> z) => DawTrack(id: 't', name: 'x', color: 0, kind: TrackKind.sampler, zones: z);

    test('uma zona editada (modo, áudio, faixa de notas) vira Zona e as outras seguem Fatia', () {
      for (final edit in <void Function(SamplerZone)>[
        (z) => z.oneShot = false,
        (z) => z.sample = 'outro',
        (z) => z.hi = z.lo + 3,
      ]) {
        var n = 0;
        final z = sliceZones('abc', [0.0, 0.25, 0.5, 0.75, 1.0], () => 'z${n++}');
        edit(z[1]);
        final t = sampler(z);
        expect(isSlicedTrack(t), isTrue);
        final names = zoneRows(t).map((r) => r.name.split(' ').first).toList();
        expect(names, ['Fatia', 'Zona', 'Fatia', 'Fatia', 'Fatia']);
        expect(zoneRows(t)[2].name, startsWith('Fatia 3'), reason: 'a numeração não desliza');
      }
    });

    test('metade editada já não é fatiada; multi-sample e zona única continuam Zona', () {
      var n = 0;
      final z = sliceZones('abc', [0.0, 0.5, 1.0], () => 'z${n++}');
      z[0].oneShot = false;
      expect(isSlicedTrack(sampler([z[0], z[1]])), isFalse, reason: '1 de 2 não é maioria');
      expect(isSlicedTrack(sampler([z[1]])), isFalse);
    });
  });

  group('metrônomo: migração do volume da versão 1', () {
    Map<String, dynamic> base(int version, {Map<String, dynamic>? options, List<Map<String, dynamic>>? tracks}) => {
      'version': version,
      'bpm': 120,
      'beats_per_bar': 4,
      'tracks': tracks ?? [],
      'samples': <String, dynamic>{},
      'loop_on': false,
      'loop_start': 0,
      'loop_end': 16,
      'metronome': false,
      'master_gain': 1,
      'master_pan': 0,
      'metronome_options': ?options,
    };
    Map<String, dynamic> track(Map<String, dynamic> extra) => {...DawTrack(id: 't', name: 'x', color: 0).toJson(), ...extra};

    test('versão 1 sem marca da fase 20+: 50% (o padrão do tempo)', () {
      expect(DawDoc.fromJson(base(1)).metronomeOptions.volume, 0.5);
      expect(DawDoc.fromJson(base(1, options: {'timbre': 'wood'})).metronomeOptions.volume, 0.5);
    });

    test('versão 1 com marca da fase 20+ (mudo, fase, loop de clipe, faixa congelada, dica de swing): 60%', () {
      final clip = AudioClip(id: 'c', sample: 's', start: 0, length: 1).toJson();
      for (final extra in <Map<String, dynamic>>[
        {'clips': [{...clip, 'muted': true}]},
        {'clips': [{...clip, 'invert': true}]},
        {'clips': [{...clip, 'loop_length': 2.0}]},
        {'frozen': {'sample': 's', 'start': 0.0, 'length': 1.0, 'tail': 0.0}},
        {'midi': [{'id': 'm', 'start': 0, 'length': 4, 'notes': [], 'swing_hint': '1/16:40'}]},
      ]) {
        final d = DawDoc.fromJson(base(1, tracks: [track({...extra})]));
        expect(d.metronomeOptions.volume, 0.6, reason: '$extra');
      }
    });

    test('o volume escolhido vale; a versão 2 sem o campo é o padrão novo; regravar guarda a versão 2', () {
      expect(DawDoc.fromJson(base(1, options: {'volume': 0.8})).metronomeOptions.volume, 0.8);
      expect(DawDoc.fromJson(base(2)).metronomeOptions.volume, 0.6);
      final saved = DawDoc.fromJson(base(1)).toJson();
      expect(saved['version'], DawDoc.version);
      expect(DawDoc.fromJson(saved).metronomeOptions.volume, 0.5, reason: 'o 50% migrado fica explícito');
    });
  });

  group('gravar e parar na hora', () {
    late FakeEngine e;
    setUp(() => e = FakeEngine());

    test('R duas vezes no ponto de gravar (sem contagem nem pré-roll): aviso claro, nenhum clipe', () async {
      final c = fakeController(e);
      c.doc
        ..countIn = false
        ..preRollBars = 0;
      c.beat.value = 8;
      c.setArmed(0, true);
      await settle();
      await c.toggleRecord();
      expect(c.recording, isTrue);
      await c.toggleRecord();
      expect(c.recording, isFalse);
      expect(c.notice, contains('muito curta'));
      expect(c.notice, contains('nada foi gravado'));
      expect(c.error, isNull, reason: 'não é falha da entrada');
      expect(c.doc.tracks[0].clips, isEmpty);
      expect(c.doc.tracks[0].midi, isEmpty);
    });
  });

  group('tap tempo sem empate', () {
    test('a espera de aplicar é maior que o maior intervalo aceito (24 BPM regulares: 2,5 s)', () {
      expect(TapTempo.slowestBpm, 24);
      for (final bpm in [24.0, 20.0, 30.0, 60.0, 120.0]) {
        expect(DawController.tapCommitWait(bpm), greaterThan(Duration(milliseconds: (60000 / bpm).round().clamp(0, (TapTempo.resetAfter * 1000).round()))), reason: '$bpm BPM');
      }
      expect(DawController.tapCommitWait(24).inMilliseconds, greaterThan(TapTempo.resetAfter * 1000));
    });

    test('a batida que chega depois do limite e antes da espera aplica a sequência pendente e recomeça', () async {
      final e = FakeEngine();
      final c = fakeController(e);
      var now = 0.0;
      c.debugTapClock = () => now;
      for (final s in [0.0, 2.0, 4.5]) {
        now = s;
        c.tapTempo();
      }
      expect(c.tapBpm.value, closeTo(26.7, 0.1));
      now = 4.5 + 2.55; // passou do limite (2,5 s) e ainda não deu a espera (2,6 s)
      final v = c.tapTempo();
      expect(v, isNull, reason: 'recomeçou');
      await settle();
      expect(c.doc.bpm, closeTo(26.7, 0.1), reason: 'a sequência anterior foi aplicada, não jogada fora');
      c.dispose();
    });

    test('24 BPM regulares (2,5 s) depois de lançado o ritmo ainda contam: sem empate com a espera', () {
      final run = TapTempo();
      run.tap(0);
      run.tap(2.0);
      run.tap(4.5);
      expect(run.tap(7.0), isNotNull);
      expect(run.count, 4);
    });
  });

  group('documento de versão futura', () {
    test('a mensagem diz o documento e até onde esta versão lê', () {
      final msg = DawDoc.newerVersionMessage({'version': DawDoc.version + 1});
      expect(msg, contains('documento ${DawDoc.version + 1}; esta versão lê até o ${DawDoc.version}'));
      expect(DawDoc.newerVersionMessage({'version': DawDoc.version}), isNull);
      expect(DawDoc.newerVersionMessage({}), isNull);
    });

    test('sincronização: o servidor com documento futuro não é aplicado e a mensagem aparece', () async {
      final future = docJson()..['version'] = DawDoc.version + 1;
      final api = FakeSyncApi()
        ..version = 2
        ..doc = future;
      final c = await opened(api, storeWith(local: docJson(track: 'Local', bpm: 120), version: 1));
      expect(trackName(c), 'Local', reason: 'o documento local não é trocado nem rebaixado');
      expect(c.sync.phase, SyncPhase.error);
      expect(c.sync.message, contains('documento ${DawDoc.version + 1}; esta versão lê até o ${DawDoc.version}'));
      c.dispose();
    });
  });
}
