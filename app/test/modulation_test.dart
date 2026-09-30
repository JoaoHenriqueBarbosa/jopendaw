// Fase 16, item B: modulação por LFO, seguidor de envelope e macro. O documento (JSON de antes e de
// agora, duplicar, apagar), as chamadas ao motor (só quando mudam), as operações do controlador, os
// presets, o intervalo do anel do knob e o painel (360 px sem estouro).
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Curve;
import 'package:flutter_test/flutter_test.dart';
import 'package:jopendaw_app/daw/controller.dart';
import 'package:jopendaw_app/daw/effects.dart';
import 'package:jopendaw_app/daw/instruments.dart';
import 'package:jopendaw_app/daw/knob.dart';
import 'package:jopendaw_app/daw/model.dart';
import 'package:jopendaw_app/daw/modulation.dart';
import 'package:jopendaw_app/daw/modulation_ops.dart';
import 'package:jopendaw_app/daw/modulation_ui.dart';
import 'package:jopendaw_app/widgets/theme.dart';

import 'fake_engine.dart';

const volume = AutoTarget(AutoKind.volume);
const pan = AutoTarget(AutoKind.pan);
const cutoff = AutoTarget(AutoKind.instrument, param: 13); // Hz, logarítmico
const unison = AutoTarget(AutoKind.instrument, param: 9); // inteiro
const wave = AutoTarget(AutoKind.instrument, param: 0); // opções

/// Áudio 1 (faixa 0) e um sintetizador (faixa 1), já sincronizados; o log do motor começa vazio.
(DawController, FakeEngine) rig() {
  final e = FakeEngine();
  final c = fakeController(
    e,
    tracks: [
      DawTrack(id: 'a', name: 'Áudio 1', color: 0),
      DawTrack(id: 's', name: 'Sintetizador', color: 1, kind: TrackKind.synth),
    ],
  );
  c.mutate((_) {});
  e.log = [];
  return (c, e);
}

List<List<Object>> modCalls(FakeEngine e) => [
  for (final x in e.log!)
    if (x.first.toString().startsWith('mod_')) x,
];

void main() {
  group('documento', () {
    test('sem modulação o JSON fica como antes e abre sem o campo', () {
      final doc = DawDoc(
        bpm: 120,
        beatsPerBar: 4,
        tracks: [DawTrack(id: 'a', name: 'A', color: 0)],
      );
      final json = doc.toJson();
      expect(json.containsKey('master_modulation'), isFalse);
      expect((json['tracks'] as List).first.containsKey('modulation'), isFalse);
      final again = DawDoc.fromJson(jsonDecode(jsonEncode(json)));
      expect(again.tracks.first.modulation.isEmpty, isTrue);
      expect(again.masterModulation.isEmpty, isTrue);
      // salvar de novo dá o mesmo texto
      expect(jsonEncode(again.toJson()), jsonEncode(json));
    });

    test('ida e volta do JSON com os três tipos, os destinos e o master', () {
      final doc = DawDoc(
        bpm: 120,
        beatsPerBar: 4,
        tracks: [DawTrack(id: 's', name: 'S', color: 0, kind: TrackKind.synth)],
      );
      doc.tracks.first.modulation = TrackModulation([
        ModSource(
          id: 'l',
          shape: LfoShape.saw,
          rate: 3.5,
          sync: true,
          division: 7,
          depth: 0.6,
          phase: 0.25,
          bipolar: false,
          dests: [ModDest(cutoff, amount: -0.4), ModDest(volume)],
        ),
        ModSource(id: 'f', kind: ModKind.follower, depth: 4, attack: 3, release: 250, dests: [ModDest(pan, amount: 1)]),
        ModSource(
          id: 'm',
          kind: ModKind.macro,
          value: 0.75,
          dests: [ModDest(const AutoTarget(AutoKind.effect, ref: 'x', param: 1))],
        ),
      ]);
      doc.masterModulation = TrackModulation([
        ModSource(id: 'mm', dests: [ModDest(volume, amount: 0.1)]),
      ]);
      final text = jsonEncode(doc.toJson());
      final back = DawDoc.fromJson(jsonDecode(text));
      expect(jsonEncode(back.toJson()), text);
      final l = back.tracks.first.modulation.sources.first;
      expect((l.shape, l.rate, l.sync, l.division, l.depth, l.phase, l.bipolar), (LfoShape.saw, 3.5, true, 7, 0.6, 0.25, false));
      expect(l.dests.map((d) => (d.target, d.amount)), [(cutoff, -0.4), (volume, 0.25)]);
      expect(back.tracks.first.modulation.sources[1].kind, ModKind.follower);
      expect(back.tracks.first.modulation.sources[2].value, 0.75);
      expect(back.masterModulation.sources.single.dests.single.amount, 0.1);
    });

    test('JSON estragado: limita os valores, ignora o lixo e não passa dos limites de moduladores e destinos', () {
      final t = TrackModulation.fromJson({
        'sources': [
          {
            'id': 'a',
            'kind': 'lfo',
            'rate': 9999,
            'depth': -3,
            'division': 99,
            'value': 7,
            'dests': List.generate(9, (i) => {'target': cutoff.toJson(), 'amount': 5}),
          },
          'lixo',
          {'sem': 'id'},
          for (var i = 0; i < 6; i++) {'id': 'x$i', 'kind': 'macro'},
        ],
      });
      expect(t.sources.length, maxModSources);
      final a = t.sources.first;
      expect((a.rate, a.depth, a.division, a.value), (modRateMax, 0.0, modDivisionCount - 1, 1.0));
      expect(a.dests.length, maxModDests);
      expect(a.dests.every((d) => d.amount == 1.0), isTrue);
      expect(TrackModulation.fromJson(null).isEmpty, isTrue);
      expect(TrackModulation.fromJson('x').isEmpty, isTrue);
    });

    test('divisões: 24 nomes e a duração do ciclo em batidas', () {
      expect(modDivisionLabel(12), '1/4');
      expect(modDivisionLabel(13), '1/4 pontilhada');
      expect(modDivisionLabel(14), '1/4 tercina');
      expect(modDivisionLabel(0), '4 compassos');
      expect({for (var i = 0; i < modDivisionCount; i++) modDivisionLabel(i)}.length, modDivisionCount);
      expect(modDivisionBeats(12), 1);
      expect(modDivisionBeats(13), 1.5);
      expect(modDivisionBeats(14), closeTo(2 / 3, 1e-12));
      expect(modDivisionBeats(0), 16);
    });

    test('duplicar a faixa leva a modulação, com ids novos e os efeitos da cópia como alvo', () {
      final (c, _) = rig();
      final fx = c.addEffect(1, EffectKind.filter);
      final fxTarget = AutoTarget(AutoKind.effect, ref: fx.id, param: 1);
      expect(c.modAssign(1, cutoff), isNull);
      expect(c.modAssign(1, fxTarget, kind: ModKind.macro), isNull);
      c.duplicateTrack(1);
      final src = c.doc.tracks[1].modulation, copy = c.doc.tracks[2].modulation;
      expect(copy.sources.length, 2);
      expect(copy.sources.map((s) => s.id).toSet().intersection(src.sources.map((s) => s.id).toSet()), isEmpty);
      expect(copy.sources[0].dests.single.target, cutoff);
      final copyFx = c.doc.tracks[2].effects.single;
      expect(copyFx.id, isNot(fx.id));
      expect(copy.sources[1].dests.single.target, AutoTarget(AutoKind.effect, ref: copyFx.id, param: 1));
      // a original segue intacta
      expect(src.sources[1].dests.single.target, fxTarget);
    });

    test('apagar o efeito, o envio ou o instrumento tira os destinos; desfazer traz de volta', () {
      final (c, _) = rig();
      final bus = c.addBusTrack();
      final fx = c.addEffect(1, EffectKind.filter);
      c.setSend(1, bus.id);
      final sendTarget = AutoTarget(AutoKind.send, ref: bus.id);
      final fxTarget = AutoTarget(AutoKind.effect, ref: fx.id, param: 1);
      expect(c.modAssign(1, fxTarget), isNull);
      expect(c.modAssign(1, sendTarget, sourceId: c.modulation(1).sources.single.id), isNull);
      expect(c.modAssign(1, cutoff, sourceId: c.modulation(1).sources.single.id), isNull);
      expect(c.modulation(1).sources.single.dests.length, 3);
      c.removeEffect(1, fx.id);
      expect(c.modulation(1).sources.single.dests.map((d) => d.target), [sendTarget, cutoff]);
      c.removeSend(1, bus.id);
      expect(c.modulation(1).sources.single.dests.map((d) => d.target), [cutoff]);
      c.undo();
      c.undo();
      expect(c.modulation(1).sources.single.dests.length, 3);
      c.redo();
      expect(c.modulation(1).sources.single.dests.length, 2);
      // a faixa que sai leva a modulação; o índice das outras se ajusta sozinho
      c.removeTrack(1);
      expect(c.modulation(1), isNotNull);
    });
  });

  group('sincronização com o motor', () {
    test('mod_clear, o modulador e o destino, na ordem certa e nos argumentos do contrato', () {
      final (c, e) = rig();
      expect(c.modAssign(1, cutoff), isNull);
      final calls = modCalls(e);
      expect(calls.map((x) => x.first), ['mod_clear', 'mod_source', 'mod_dest']);
      // faixa, índice, tipo, taxa, sincronizado, profundidade, fase, bipolar, forma, ataque, soltura, valor
      expect(calls[1], ['mod_source', 1, 0, 0, 1.0, false, 1.0, 0.0, true, 0, 10.0, 120.0, 0.0]);
      // faixa, modulador, destino, alvo (2 = instrumento), slot, id, quantidade, mín, máx, escala (1 = log)
      expect(calls[2], ['mod_dest', 1, 0, 0, 2, 0, 13, 0.25, 20.0, 20000.0, 1]);
      expect(calls[1].length - 1, 12);
      expect(calls[2].length - 1, 10);
      // ordem: depois dos instrumentos e efeitos, antes das notas
      final log = e.log!.map((x) => x.first).toList();
      expect(log.indexOf('mod_clear'), lessThan(log.indexOf('mod_source')));
    });

    test('só reenvia quando a lista muda', () {
      final (c, e) = rig();
      c.modAssign(1, cutoff);
      e.log = [];
      c.mutate((_) {});
      c.setParam(1, 13, 500);
      c.mutate((d) => d.tracks[1].gain = 0.5);
      expect(modCalls(e), isEmpty);
      // a quantidade mudou: tudo de novo (o motor guarda o estado do modulador)
      c.editModulation(1, (m) => m.sources.single.dests.single.amount = -0.5);
      expect(modCalls(e).map((x) => x.first), ['mod_clear', 'mod_source', 'mod_dest']);
      expect(modCalls(e).last[7], -0.5);
      e.log = [];
      c.mutate((_) {});
      expect(modCalls(e), isEmpty);
      // desfazer a mudança
      c.undo();
      expect(modCalls(e).last[7], 0.25);
      e.log = [];
      // tirar tudo: só o mod_clear
      c.undo();
      expect(modCalls(e).map((x) => x.first), ['mod_clear']);
      e.log = [];
      c.mutate((_) {});
      expect(modCalls(e), isEmpty);
    });

    test('volume e envio andam na curva do fader; pan, linear; master tem faixa −1', () {
      final (c, e) = rig();
      final bus = c.addBusTrack();
      c.setSend(1, bus.id);
      e.log = [];
      c.modAssign(1, volume);
      c.modAssign(1, pan, sourceId: c.modulation(1).sources.single.id);
      c.modAssign(1, AutoTarget(AutoKind.send, ref: bus.id), sourceId: c.modulation(1).sources.single.id);
      c.modAssign(-1, volume, kind: ModKind.follower);
      final dests = modCalls(e).where((x) => x.first == 'mod_dest').toList().sublist(modCalls(e).where((x) => x.first == 'mod_dest').length - 4);
      // volume: código 0, curso 0..2, escala 2 (fader)
      expect(dests[0], ['mod_dest', 1, 0, 0, 0, 0, 0, 0.25, 0.0, 2.0, 2]);
      // pan: código 1, −1..1, linear
      expect(dests[1], ['mod_dest', 1, 0, 1, 1, 0, 0, 0.25, -1.0, 1.0, 0]);
      // envio: código 4, slot = índice do envio, fader
      expect(dests[2], ['mod_dest', 1, 0, 2, 4, 0, 0, 0.25, 0.0, 2.0, 2]);
      // master: faixa −1
      expect(dests[3][1], -1);
      final srcs = modCalls(e).where((x) => x.first == 'mod_source').toList();
      expect(srcs.last.sublist(0, 4), ['mod_source', -1, 0, 1]);
    });

    test('destino sem alvo (efeito que sumiu no meio) e controle de opções não vão ao motor', () {
      final (c, e) = rig();
      expect(c.modAssign(1, unison), isNotNull);
      expect(c.modAssign(1, wave), isNotNull);
      expect(c.modulation(1).isEmpty, isTrue);
      // um documento antigo com um destino que não resolve: o modulador sem destino válido não sai
      c.doc.tracks[1].modulation = TrackModulation([
        ModSource(
          id: 'z',
          dests: [ModDest(const AutoTarget(AutoKind.effect, ref: 'fantasma', param: 1))],
        ),
      ]);
      c.mutate((_) {});
      // o poda tirou o destino fantasma
      expect(c.modulation(1).sources.single.dests, isEmpty);
      expect(modCalls(e), isEmpty);
    });

    test('o render (motor novo) recebe a modulação inteira', () {
      final (c, _) = rig();
      c.modAssign(1, cutoff);
      c.modAssign(0, volume, kind: ModKind.macro);
      final full = c.debugFullSyncCalls();
      expect(full.where((x) => x.first == 'mod_source').length, 2);
      expect(full.where((x) => x.first == 'mod_dest').length, 2);
      expect(full.indexWhere((x) => x.first == 'mod_clear'), greaterThan(full.indexWhere((x) => x.first == 'track_kind')));
    });
  });

  group('operações', () {
    test('limites: 4 moduladores por faixa, 4 destinos por modulador, sem destino repetido', () {
      final (c, _) = rig();
      for (var i = 0; i < maxModSources; i++) {
        expect(c.modAddSource(1, ModKind.lfo), isNotNull);
      }
      expect(c.modAddSource(1, ModKind.lfo), isNull);
      expect(c.modAssign(1, cutoff), contains('4 moduladores'));
      final id = c.modulation(1).sources.first.id;
      final targets = [cutoff, volume, pan, const AutoTarget(AutoKind.instrument, param: 14), const AutoTarget(AutoKind.instrument, param: 1)];
      for (var i = 0; i < maxModDests; i++) {
        expect(c.modAssign(1, targets[i], sourceId: id), isNull);
      }
      expect(c.modAssign(1, targets[4], sourceId: id), contains('no máximo'));
      // o mesmo alvo no mesmo modulador não duplica
      expect(c.modAssign(1, cutoff, sourceId: id), isNull);
      expect(c.modulation(1).sources.first.dests.length, maxModDests);
      // id que não existe
      expect(c.modAssign(1, cutoff, sourceId: 'nada'), isNotNull);
      // faixa que não existe
      expect(c.modAssign(9, volume), isNotNull);
    });

    test('atribuir é um passo só do histórico e dá 25% ao destino', () {
      final (c, _) = rig();
      expect(c.modAssign(1, cutoff), isNull);
      expect(c.modulation(1).sources.single.dests.single.amount, defaultModAmount);
      c.undo();
      expect(c.modulation(1).isEmpty, isTrue);
      c.redo();
      expect(c.modulation(1).sources.length, 1);
      // apagar destino e modulador
      final id = c.modulation(1).sources.single.id;
      c.modRemoveDest(1, id, 0);
      expect(c.modulation(1).sources.single.dests, isEmpty);
      c.modRemoveSource(1, id);
      expect(c.modulation(1).isEmpty, isTrue);
    });

    test('presets de fábrica criam o modulador e o destino', () {
      final (c, e) = rig();
      ModPreset preset(String id) => modPresets.firstWhere((p) => p.id == id);
      expect(c.modApplyPreset(1, preset('wobble')), isNull);
      var s = c.modulation(1).sources.last;
      expect((s.sync, s.division, s.dests.single.target, s.dests.single.amount), (true, 15, cutoff, s.dests.single.amount));
      expect(s.dests.single.amount, closeTo(1 / (math.log(1000) / math.ln2), 1e-9));
      // ±1 oitava: com o corte padrão (2400 Hz) o extremo fica em 4800 Hz, longe do teto de 20 kHz
      const spec = ParamSpec(13, 'Corte', 'Filtro', 20, 20000, 2400, unit: 'Hz', curve: Curve.log);
      expect(spec.fromNorm(spec.toNorm(2400) + s.dests.single.amount), closeTo(4800, 1));
      expect(c.modApplyPreset(1, preset('tremolo')), isNull);
      s = c.modulation(1).sources.last;
      expect((s.rate, s.sync, s.dests.single.target), (6.0, false, volume));
      expect(c.modApplyPreset(1, preset('autopan')), isNull);
      s = c.modulation(1).sources.last;
      expect((s.sync, s.division, s.dests.single.target), (true, 9, pan));
      // vibrato: só o Sampler tem afinação da faixa; no sintetizador o preset é recusado e some do menu
      expect(c.modApplyPreset(1, preset('vibrato')), contains('não tem o controle'));
      expect(preset('vibrato').availableFor(ModTrackView(c.doc.tracks[1], const [])), isFalse);
      final sp = fakeController(
        FakeEngine(),
        tracks: [DawTrack(id: 'p', name: 'Sampler', color: 2, kind: TrackKind.sampler)],
      );
      expect(sp.modApplyPreset(0, preset('vibrato')), isNull);
      final vt = sp.modulation(0).sources.single.dests.single.target;
      expect(TrackKind.sampler.params.firstWhere((p) => p.id == vt.param).name, 'Afinação');
      // a faixa cheia recusa
      expect(c.modApplyPreset(1, preset('tremolo')), isNull);
      expect(c.modApplyPreset(1, preset('tremolo')), contains('4 moduladores'));
      // faixa de áudio, sem corte nem afinação: o wobble e o vibrato dizem por quê
      expect(c.modApplyPreset(0, preset('wobble')), contains('não tem o controle'));
      expect(c.modApplyPreset(0, preset('vibrato')), contains('não tem o controle'));
      expect(c.modulation(0).isEmpty, isTrue);
      // com um filtro na cadeia, o wobble o encontra
      final fx = c.addEffect(0, EffectKind.filter);
      expect(c.modApplyPreset(0, preset('wobble')), isNull);
      expect(c.modulation(0).sources.single.dests.single.target, AutoTarget(AutoKind.effect, ref: fx.id, param: 1));
      // tudo foi ao motor
      expect(modCalls(e).where((x) => x.first == 'mod_source').length, greaterThanOrEqualTo(5));
    });

    test('o intervalo do anel: soma dos destinos do alvo, na escala do curso', () {
      final t = TrackModulation([
        ModSource(id: 'a', depth: 0.5, dests: [ModDest(cutoff, amount: 0.5)]),
        ModSource(id: 'b', bipolar: false, dests: [ModDest(cutoff, amount: -0.4), ModDest(volume)]),
        ModSource(id: 'c', kind: ModKind.macro, value: 0.5, dests: [ModDest(cutoff, amount: 0.2)]),
      ]);
      // a: ±0,25 · b: 0..−0,4 · c: +0,1 fixo
      final (lo, hi) = t.deltaRange(cutoff)!;
      expect(lo, closeTo(-0.25 - 0.4 + 0.1, 1e-12));
      expect(hi, closeTo(0.25 + 0.1, 1e-12));
      expect(t.deltaRange(volume), (0.0, 0.25));
      expect(t.deltaRange(pan), isNull);
      expect(t.modulates(cutoff), isTrue);
      expect(t.modulates(pan), isFalse);
      // seguidor: 0..min(1, ganho)
      final f = ModSource(id: 'f', kind: ModKind.follower, depth: 0.5);
      expect(f.outputRange, (0.0, 0.5));
      expect(ModSource(id: 'g', kind: ModKind.follower, depth: 4).outputRange, (0.0, 1.0));
    });
  });

  group('painel', () {
    Future<DawController> open(WidgetTester tester, {int track = 1}) async {
      tester.view.physicalSize = const Size(360, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final (c, _) = rig();
      c.showEffects(track);
      c.setDock(Dock.modulation);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(),
          home: Scaffold(
            body: SizedBox(height: 640, child: ModulationPanel(c: c)),
          ),
        ),
      );
      return c;
    }

    testWidgets('vazio: mostra a instrução, sem estourar em 360 px', (tester) async {
      final c = await open(tester);
      expect(find.textContaining('Nenhum modulador'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 1));
      c.dispose();
    });

    testWidgets('quatro moduladores de tipos diferentes com quatro destinos cada cabem em 360 px', (tester) async {
      final c = await open(tester);
      final targets = [cutoff, volume, pan, const AutoTarget(AutoKind.instrument, param: 14)];
      c.editModulation(1, (m) {
        m.sources.addAll([
          ModSource(id: 'l1', shape: LfoShape.sampleHold, sync: true, division: 14, dests: [for (final t in targets) ModDest(t, amount: -0.5)]),
          ModSource(id: 'l2', rate: 12.5, bipolar: false, dests: [for (final t in targets) ModDest(t)]),
          ModSource(id: 'f1', kind: ModKind.follower, dests: [for (final t in targets) ModDest(t, amount: 1)]),
          ModSource(id: 'm1', kind: ModKind.macro, value: 0.4, dests: [for (final t in targets) ModDest(t, amount: 0.01)]),
        ]);
      });
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('mod-l1')), findsOneWidget);
      // a largura do cartão nunca passa da tela
      for (final id in ['l1', 'l2', 'f1', 'm1']) {
        final box = tester.getRect(find.byKey(ValueKey('mod-$id')));
        expect(box.width, lessThanOrEqualTo(360));
      }
      // rolar até o fim tampouco estoura
      await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -2000));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 1));
      c.dispose();
    });

    testWidgets('adicionar pelo menu, aplicar um preset e apagar', (tester) async {
      final c = await open(tester);
      await tester.tap(find.byKey(const ValueKey('mod-add')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('LFO').last);
      await tester.pumpAndSettle();
      expect(c.modulation(1).sources.length, 1);
      expect(find.byKey(ValueKey('mod-${c.modulation(1).sources.single.id}')), findsOneWidget);
      // preset
      await tester.tap(find.byKey(const ValueKey('mod-presets')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tremolo no volume'));
      await tester.pumpAndSettle();
      expect(c.modulation(1).sources.length, 2);
      expect(c.modulation(1).sources.last.dests.single.target, volume);
      // apagar o primeiro
      await tester.tap(find.byKey(ValueKey('mod-remove-${c.modulation(1).sources.first.id}')));
      await tester.pumpAndSettle();
      expect(c.modulation(1).sources.length, 1);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 1));
      c.dispose();
    });

    testWidgets('mexer na quantidade do destino edita o documento e desfaz', (tester) async {
      final c = await open(tester);
      c.modAssign(1, volume);
      await tester.pump();
      final id = c.modulation(1).sources.single.id;
      final slider = find.byKey(ValueKey('mod-amount-$id-0'));
      expect(slider, findsOneWidget);
      await tester.drag(slider, const Offset(60, 0));
      await tester.pump();
      expect(c.modulation(1).sources.single.dests.single.amount, greaterThan(0.25));
      c.undo();
      await tester.pump();
      expect(c.modulation(1).sources.single.dests.single.amount, 0.25);
      await tester.pump(const Duration(seconds: 1));
      c.dispose();
    });

    testWidgets('o knob desenha o anel e o botão direito oferece "Modular…"', (tester) async {
      final (c, _) = rig();
      final spec = synthParams.firstWhere((p) => p.id == 13);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(),
          home: Scaffold(
            body: Center(
              child: Knob(
                key: const ValueKey('k'),
                spec: spec,
                value: 2400,
                onChanged: (_) {},
                extraActions: () => [modulateAction(c, 1, cutoff)],
                modRange: () => c.modulationOf(1)?.deltaRange(cutoff),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      // com modulação o anel entra no desenho (só não pode estourar nem mudar o valor mostrado)
      c.modAssign(1, cutoff);
      await tester.pump();
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(),
          home: Scaffold(
            body: Center(
              child: Knob(
                key: const ValueKey('k'),
                spec: spec,
                value: 2400,
                onChanged: (_) {},
                extraActions: () => [modulateAction(c, 1, cutoff)],
                modRange: () => c.modulationOf(1)?.deltaRange(cutoff),
              ),
            ),
          ),
        ),
      );
      expect(c.modulationOf(1)!.deltaRange(cutoff), (-0.25, 0.25));
      final at = tester.getCenter(find.byKey(const ValueKey('k')));
      await tester.tapAt(at, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      expect(find.text('Digitar o valor…'), findsOneWidget);
      await tester.tap(find.text('Modular…'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Modular: '), findsOneWidget);
      // escolher o modulador que já modula o controle não muda nada e fecha
      await tester.tap(find.byKey(ValueKey('modulate-source-${c.modulation(1).sources.single.id}')));
      await tester.pumpAndSettle();
      expect(c.modulation(1).sources.single.dests.length, 1);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 1));
      c.dispose();
    });

    testWidgets('"Modular…" cria o destino no modulador escolhido e abre o painel', (tester) async {
      tester.view.physicalSize = const Size(360, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final (c, _) = rig();
      addTearDown(c.dispose);
      c.modAddSource(1, ModKind.macro);
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(),
          home: Scaffold(
            body: Builder(
              builder: (context) {
                ctx = context;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      unawaited(showModulateDialog(ctx, c, 1, cutoff));
      await tester.pumpAndSettle();
      expect(find.textContaining('Modular: '), findsOneWidget);
      expect(find.text('Novo LFO'), findsOneWidget);
      // o existente
      await tester.tap(find.byKey(ValueKey('modulate-source-${c.modulation(1).sources.single.id}')));
      await tester.pumpAndSettle();
      expect(c.modulation(1).sources.single.dests.single.target, cutoff);
      expect(c.modulation(1).sources.single.dests.single.amount, 0.25);
      expect(c.dock, Dock.modulation);
      // um novo
      unawaited(showModulateDialog(ctx, c, 1, volume));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('modulate-new-follower')));
      await tester.pumpAndSettle();
      expect(c.modulation(1).sources.length, 2);
      expect(c.modulation(1).sources.last.kind, ModKind.follower);
      // sem vaga: os "novo" ficam desligados e o aviso explica
      c.modAddSource(1, ModKind.lfo);
      c.modAddSource(1, ModKind.lfo);
      unawaited(showModulateDialog(ctx, c, 1, pan));
      await tester.pumpAndSettle();
      expect(find.textContaining('já tem 4 moduladores'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 1));
    });
  });
}

void unawaited(Future<void> f) {}
