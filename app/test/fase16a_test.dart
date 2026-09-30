// Fase 16, item A: correções de pastas de faixa, fades e crossfades, gravação de automação, presets do usuário e
// andamento do .mid (cada teste confirma o defeito achado por leitura de código e a correção).
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart' hide Curve;
import 'package:flutter_test/flutter_test.dart';
import 'package:jopendaw_app/daw/automation_math.dart';
import 'package:jopendaw_app/daw/automation_mode.dart';
import 'package:jopendaw_app/daw/controller.dart';
import 'package:jopendaw_app/daw/effects.dart';
import 'package:jopendaw_app/daw/export_options.dart';
import 'package:jopendaw_app/daw/fade_length_dialog.dart';
import 'package:jopendaw_app/daw/instruments.dart';
import 'package:jopendaw_app/daw/midi_file.dart';
import 'package:jopendaw_app/daw/model.dart';
import 'package:jopendaw_app/daw/project_file.dart';
import 'package:jopendaw_app/daw/structure_menu.dart';
import 'package:jopendaw_app/daw/tempo_map.dart';
import 'package:jopendaw_app/daw/track_groups.dart';
import 'package:jopendaw_app/daw/track_groups_ui.dart';
import 'package:jopendaw_app/daw/user_presets.dart';
import 'package:jopendaw_app/daw/user_presets_ui.dart';
import 'package:jopendaw_app/daw/wav.dart';
import 'package:jopendaw_app/widgets/theme.dart';

import 'controller_test.dart' show newController;
import 'fake_engine.dart';
import 'midi_file_test.dart' show eot, smf, vlq;
import 'studio_test.dart' show flushSave, mount, studio;
import 'track_groups_test.dart' as tg;

const pan = AutoTarget(AutoKind.pan);

AudioClip audio(String id, double start, double secs) => AudioClip(id: id, sample: 's', start: start, length: secs);

Widget host(Widget Function(BuildContext) build) => MaterialApp(
  theme: buildTheme(),
  home: Scaffold(body: Builder(builder: build)),
);

Future<BuildContext> pumpContext(WidgetTester t) async {
  late BuildContext ctx;
  await t.pumpWidget(
    host((c) {
      ctx = c;
      return const SizedBox();
    }),
  );
  return ctx;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('pastas', () {
    test('(1) mudar a saída para fora da pasta tira a faixa dela (o bloco segue contíguo); a própria pasta não tira', () {
      final c = tg.newController();
      final f = c.groupTracks(['a1', 'a2'], name: 'G').folder!; // G a1 a2 s d p r
      final before = tg.snap(c);
      expect(c.folderLeftByOutput(1, f.id), isNull);
      expect(c.folderLeftByOutput(1, 'r'), same(f));
      expect(c.setOutput(1, f.id), isTrue);
      expect(tg.snap(c), before, reason: 'a mesma saída: nada muda');
      expect(c.setOutput(1, 'r'), isTrue);
      expect(tg.track(c, 'a1').groupId, isNull);
      expect(tg.track(c, 'a1').output, 'r');
      expect(tg.names(c), ['G', 'Áudio 2', 'Áudio 1', 'Synth', 'Bateria', 'Sampler', 'Reverb']);
      expect(c.doc.membersOf(0), [1], reason: 'só a Áudio 2 ficou no bloco');
      expect(c.doc.folderOf(2), -1);
      c.undo();
      expect(tg.snap(c), before);
      // para o Master também sai
      expect(c.setOutput(2, null), isTrue);
      expect(tg.track(c, 'a2').groupId, isNull);
      expect(tg.track(c, 'a2').output, isNull);
    });

    testWidgets('(1) o menu de saída do mixer avisa antes de tirar a faixa da pasta', (t) async {
      final c = studio();
      final f = c.groupTracks(['a', 's'], name: 'G').folder!;
      await mount(t, c, const Size(1400, 900));
      c.setDock(Dock.mixer);
      await t.pump();
      await t.tap(find.byTooltip('Saída: G').first);
      await t.pumpAndSettle();
      await t.tap(find.text('Master').last);
      await t.pumpAndSettle();
      expect(find.text('Tirar "Áudio 1" da pasta?'), findsOneWidget);
      await t.tap(find.text('Cancelar'));
      await t.pumpAndSettle();
      expect(tg.track(c, 'a').groupId, f.id, reason: 'cancelar deixa tudo');
      await t.tap(find.byTooltip('Saída: G').first);
      await t.pumpAndSettle();
      await t.tap(find.text('Master').last);
      await t.pumpAndSettle();
      await t.tap(find.text('Tirar da pasta'));
      await t.pumpAndSettle();
      expect(tg.track(c, 'a').groupId, isNull);
      expect(tg.track(c, 'a').output, isNull);
      await flushSave(t);
    });

    test('(2) congelar em áudio uma filha: a faixa nova entra na pasta, logo abaixo, sem quebrar o bloco', () async {
      final e = FakeEngine();
      final c = fakeController(e);
      await c.importBytes(
        [
          ('voz.wav', encodeWav([Float32List(200)..fillRange(0, 200, 0.25)], 100, ExportFormat.wav32f)),
        ],
        at: 0,
        track: 0,
      );
      final f = c.groupTracks([c.doc.tracks[0].id], name: 'G').folder!;
      f.collapsed = true;
      e.renderResult = (outputs) => [
        [Float32List(450)..fillRange(0, 250, 0.3), Float32List(450)..fillRange(0, 250, 0.3)],
      ];
      final idx = c.doc.tracks.indexWhere((t) => t.groupId == f.id);
      await c.bounceTrack(idx);
      expect(c.error, isNull);
      final frozen = c.doc.tracks[idx + 1];
      expect(frozen.name, endsWith('(áudio)'));
      expect(frozen.groupId, f.id);
      expect(frozen.output, f.id);
      expect(frozen.collapsed, isFalse);
      expect(c.doc.membersOf(0), [idx, idx + 1], reason: 'o bloco da pasta segue contíguo');
      expect(planTrackMove(c.doc.tracks, idx, idx), isNull);
    });

    test('(3) as notas de "Tirar da pasta", "Mover para a pasta" e "Agrupar" dizem o que muda na saída', () {
      final c = tg.newController();
      final f = c.groupTracks(['a1', 'a2'], name: 'G').folder!;
      expect(c.leaveGroupNotes('a1'), ['a saída de "Áudio 1" para a pasta "G" (volta ao master)']);
      c.setOutput(c.doc.tracks.indexWhere((t) => t.id == 'd'), 'r'); // Bateria → Reverb
      expect(c.joinGroupNotes('d', f.id), ['a saída de "Bateria" para "Reverb" (passa a ir para a pasta "G")']);
      expect(c.joinGroupNotes('p', f.id), isEmpty, reason: 'Sampler sai no master: nada troca');
      expect(c.groupNotes(['d', 'p']), ['a saída de "Bateria" para "Reverb" (passa a ir para a pasta nova)']);
      expect(c.groupNotes(['p']), isEmpty);
      c.setOutput(1, 'r'); // Áudio 1 sai da pasta, mas continua sendo do Reverb: nada a avisar ao tirá-la
      expect(c.leaveGroupNotes('a1'), isEmpty);
    });

    testWidgets('(3)(4) "Tirar da pasta" e "Mover para a pasta" pedem confirmação, com o texto de pasta', (t) async {
      final c = tg.newController();
      final f = c.groupTracks(['a1', 'a2'], name: 'G').folder!;
      c.setOutput(c.doc.tracks.indexWhere((t) => t.id == 'd'), 'r');
      final ctx = await pumpContext(t);
      final before = tg.snap(c);
      unawaited(onGroupMenu(ctx, c, 1, 'grp:leave'));
      await t.pumpAndSettle();
      expect(find.text('Tirar "Áudio 1" da pasta?'), findsOneWidget);
      expect(find.textContaining('Barramento só manda'), findsNothing, reason: 'texto de pasta, não o de barramento');
      await t.tap(find.text('Cancelar'));
      await t.pumpAndSettle();
      expect(tg.snap(c), before);
      unawaited(onGroupMenu(ctx, c, 1, 'grp:leave'));
      await t.pumpAndSettle();
      await t.tap(find.text('Tirar da pasta'));
      await t.pumpAndSettle();
      expect(tg.track(c, 'a1').groupId, isNull);
      c.undo();
      expect(tg.snap(c), before);

      final di = c.doc.tracks.indexWhere((t) => t.id == 'd');
      unawaited(onGroupMenu(ctx, c, di, 'grp:join:${f.id}'));
      await t.pumpAndSettle();
      expect(find.text('Mover "Bateria" para a pasta "G"?'), findsOneWidget);
      expect(find.textContaining('passa a ir para a pasta "G"'), findsOneWidget);
      await t.tap(find.text('Mover para a pasta'));
      await t.pumpAndSettle();
      expect(tg.track(c, 'd').groupId, f.id);
      expect(tg.track(c, 'd').output, f.id);
      // uma faixa sem saída trocada entra sem perguntar
      await onGroupMenu(ctx, c, c.doc.tracks.indexWhere((t) => t.id == 'p'), 'grp:join:${f.id}');
      expect(tg.track(c, 'p').groupId, f.id);
      await flushSave(t);
    });

    testWidgets('(3) agrupar faixa que já saía para outro barramento pergunta pelo diálogo', (t) async {
      final c = tg.newController();
      c.setOutput(c.doc.tracks.indexWhere((t) => t.id == 'd'), 'r');
      final ctx = await pumpContext(t);
      unawaited(showGroupDialog(ctx, c, preselect: 'd'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('group-confirm')));
      await t.pumpAndSettle();
      expect(find.text('Agrupar as faixas?'), findsOneWidget);
      expect(find.textContaining('(passa a ir para a pasta nova)'), findsOneWidget);
      await t.tap(find.text('Cancelar').last);
      await t.pumpAndSettle();
      expect(c.doc.hasGroups, isFalse);
      await t.tap(find.byKey(const ValueKey('group-confirm')));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, 'Agrupar').last);
      await t.pumpAndSettle();
      expect(c.doc.hasGroups, isTrue);
      expect(tg.track(c, 'd').output, c.doc.tracks.firstWhere((t) => t.isGroup).id);
      await flushSave(t);
    });

    testWidgets('(4) mover com aviso só de pasta usa o texto de pasta; com os dois, mostra os dois', (t) async {
      final c = tg.newController();
      c.groupTracks(['a1', 'a2'], name: 'G');
      c.setOutput(4, 'r'); // Bateria → Reverb
      final ctx = await pumpContext(t);
      unawaited(moveTrackAsking(ctx, c, 4, 2));
      await t.pumpAndSettle();
      expect(find.textContaining('Barramento só manda'), findsNothing);
      expect(find.textContaining('troca de saída'), findsOneWidget);
      expect(find.textContaining('passa a ir para a pasta "G"'), findsOneWidget);
      await t.tap(find.text('Cancelar'));
      await t.pumpAndSettle();
      await flushSave(t);
    });

    test('(5) importar .jopendaw reaponta o group_id junto com saída e envios; pasta que não existe some', () {
      final doc = DawDoc(
        bpm: 120,
        beatsPerBar: 4,
        tracks: [
          DawTrack(id: 'pasta 1', name: 'G', color: 0, kind: TrackKind.bus, isGroup: true),
          DawTrack(id: 'faixa 1', name: 'F', color: 1, groupId: 'pasta 1', output: 'pasta 1'),
          DawTrack(id: 'faixa 2', name: 'Órfã', color: 2, groupId: 'pasta que sumiu'),
        ],
      );
      remapDocIds(doc);
      final folder = doc.tracks[0], child = doc.tracks[1];
      expect(folder.id, isNot('pasta 1'));
      expect(child.groupId, folder.id);
      expect(child.output, folder.id);
      expect(doc.folderOf(1), 0);
      expect(doc.tracks[2].groupId, isNull);
    });

    test('(6) desagrupar uma pasta com efeito mantém as filhas saindo no barramento (ele segue com entrada)', () {
      final c = tg.newController();
      final f = c.groupTracks(['a1', 'a2'], name: 'G').folder!;
      c.addEffect(0, EffectKind.compressor);
      final grouped = tg.snap(c);
      expect(c.ungroup(f.id), UngroupResult.keptAsBus);
      expect(tg.track(c, 'a1').groupId, isNull);
      expect(tg.track(c, 'a1').output, f.id);
      expect(tg.track(c, 'a2').output, f.id);
      expect(f.isGroup, isFalse);
      expect(tg.lastOutputs()[1], 0, reason: 'no motor a filha continua saindo no barramento');
      c.undo();
      expect(tg.snap(c), grouped);
    });

    test('(6) só receber de outras faixas: as filhas vão ao master e o barramento fica', () {
      final c = tg.newController();
      final f = c.groupTracks(['a1', 'a2'], name: 'G').folder!;
      c.setSend(c.doc.tracks.indexWhere((t) => t.id == 's'), f.id);
      expect(c.ungroup(f.id), UngroupResult.keptAsBus);
      expect(tg.track(c, 'a1').output, isNull);
    });

    testWidgets('(7) "Apagar a pasta (as faixas ficam)" existe no menu, confirma e as filhas seguem soltas no master', (t) async {
      final c = studio();
      final f = c.groupTracks(['a', 's'], name: 'G').folder!;
      c.addEffect(0, EffectKind.compressor);
      await mount(t, c, const Size(1400, 900));
      await t.tap(find.byKey(const ValueKey('group-menu')));
      await t.pumpAndSettle();
      await t.tap(find.text('Apagar a pasta (as faixas ficam)…'));
      await t.pumpAndSettle();
      expect(find.text('Apagar a pasta "G"?'), findsOneWidget);
      await t.tap(find.text('Cancelar'));
      await t.pumpAndSettle();
      expect(c.doc.hasGroups, isTrue);
      await t.tap(find.byKey(const ValueKey('group-menu')));
      await t.pumpAndSettle();
      await t.tap(find.text('Apagar a pasta (as faixas ficam)…'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, 'Apagar a pasta'));
      await t.pumpAndSettle();
      expect(c.doc.hasGroups, isFalse);
      expect(c.doc.tracks.any((x) => x.id == f.id), isFalse);
      expect(tg.track(c, 'a').groupId, isNull);
      expect(tg.track(c, 'a').output, isNull);
      c.undo();
      expect(c.doc.hasGroups, isTrue);
      await flushSave(t);
    });
  });

  group('fades', () {
    test('(1) apagar um dos clipes de um crossfade devolve o fade do outro', () {
      final c = newController();
      final t = c.doc.tracks[0]..clips.addAll([audio('a', 0, 4), audio('top', 6, 4)]);
      t.clips[0].fadeOutShape = FadeShape.sCurve;
      c.placeOnTop('top', crossfade: true);
      final a = t.clips.firstWhere((x) => x.id == 'a');
      expect((a.fadeOut, a.fadeOutShape, a.autoFadeOut != null), (1.0, FadeShape.equalPower, true));
      c.selectClip('top');
      c.deleteSelected();
      expect(t.clips.single.id, 'a');
      expect((a.fadeOut, a.fadeOutShape, a.autoFadeOut), (0.0, FadeShape.sCurve, null));
    });

    test('(2) cortar no cursor limpa as marcas dos fades zerados (o reconcile não os "devolve")', () {
      final c = newController();
      final t = c.doc.tracks[0]..clips.addAll([audio('a', 0, 4), audio('top', 6, 4)]);
      t.clips[0].fadeOutShape = FadeShape.sCurve;
      c.placeOnTop('top', crossfade: true);
      c.selectClip('a');
      c.beat.value = 4; // no meio do clipe a (batidas 0 a 8)
      c.splitAtPlayhead();
      final left = t.clips.firstWhere((x) => x.id == 'a');
      final right = t.clips.firstWhere((x) => x.id != 'a' && x.id != 'top');
      expect((left.fadeOut, left.autoFadeOut), (0.0, null));
      expect(right.autoFadeIn, isNull);
      expect(right.autoFadeOut, isNotNull, reason: 'a metade da direita segue no crossfade');
      c.reconcileAutoFades();
      expect(left.fadeOutShape, FadeShape.equalPower, reason: 'sem a marca, o reconcile não volta à curva de antes');
      expect(left.fadeOut, 0.0);
    });

    test('(2) o corte por placeOnTop no meio de um clipe limpa as marcas dos lados zerados', () {
      final c = newController();
      final t = c.doc.tracks[0];
      final o = audio('o', 0, 8)
        ..fadeIn = 1
        ..autoFadeIn = const AutoFade(0.4, FadeShape.sCurve)
        ..fadeOut = 1
        ..autoFadeOut = const AutoFade(0.4, FadeShape.sCurve);
      t.clips.addAll([o, audio('top', 4, 2)]); // o de cima cai no meio do de baixo (batidas 4 a 8; o vai de 0 a 16)
      c.placeOnTop('top');
      final right = t.clips.firstWhere((x) => x.id != 'o' && x.id != 'top');
      // sem limpar a marca, o reconcile "devolveria" 0,4 s de fade nos lados que o corte zerou
      expect((o.fadeOut, o.autoFadeOut), (0.0, null));
      expect((right.fadeIn, right.autoFadeIn), (0.0, null));
    });

    test('(3) "crossfade nas sobreposições" vale para o clipe clicado (ou a faixa toda) e diz o que fez', () {
      final c = newController();
      final t = c.doc.tracks[0]..clips.addAll([audio('a', 0, 4), audio('b', 6, 4), audio('c', 12, 4)]);
      final before = jsonEncode(c.doc.toJson());
      expect(c.crossfadeOverlaps('a'), 1, reason: 'só o par a/b');
      expect(c.notice, '1 crossfade aplicado.');
      final a = t.clips[0], b = t.clips[1], cc = t.clips[2];
      expect((a.fadeOut, b.fadeIn, b.fadeOut, cc.fadeIn), (1.0, 1.0, 0.0, 0.0));
      c.undo();
      expect(jsonEncode(c.doc.toJson()), before);
      expect(c.crossfadeOverlaps('b'), 2, reason: 'b cruza a e c');
      expect(c.notice, '2 crossfades aplicados.');
      c.undo();
      expect(c.crossfadeOverlaps('a', wholeTrack: true), 2);
      final clips = c.doc.tracks[0].clips;
      expect((clips[1].fadeOut, clips[2].fadeIn), (1.0, 1.0));
      c.clearNotice();
      expect(c.notice, isNull);
      // sem sobreposição: nada é aplicado e o aviso diz isso
      final d = newController();
      d.doc.tracks[0].clips.addAll([audio('x', 0, 1), audio('y', 10, 1)]);
      expect(d.crossfadeOverlaps('x'), 0);
      expect(d.notice, contains('não cruza a borda'));
    });

    test('(4) tamanho do fade por campo: limita ao que sobra do clipe, desfaz e deixa de ser automático', () {
      final c = newController();
      final t = c.doc.tracks[0]..clips.add(audio('a', 0, 4));
      final a = t.clips.single;
      c.setFadeLength('a', fadeIn: 0.25);
      expect(a.fadeIn, 0.25);
      c.setFadeLength('a', fadeOut: 100);
      expect(a.fadeOut, closeTo(3.75, 1e-9), reason: 'o resto do clipe depois do fade de entrada');
      c.setFadeLength('a', fadeIn: -3);
      expect(a.fadeIn, 0.0);
      c.undo();
      final back = c.audioClip('a')!;
      expect(back.fadeIn, 0.25);
      back.autoFadeIn = const AutoFade(0, FadeShape.linear);
      c.setFadeLength('a', fadeIn: 0.1);
      expect(c.audioClip('a')!.autoFadeIn, isNull);
    });

    testWidgets('(4) o diálogo "Fade de entrada…" aceita ms e batidas', (t) async {
      final c = newController();
      c.doc.tracks[0].clips.add(audio('a', 0, 4));
      final ctx = await pumpContext(t);
      unawaited(showFadeLengthDialog(ctx, c, 'a', fadeIn: true));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const ValueKey('fade-length-field')), '250');
      await t.tap(find.byKey(const ValueKey('fade-length-apply')));
      await t.pumpAndSettle();
      expect(c.audioClip('a')!.fadeIn, closeTo(0.25, 1e-9));
      unawaited(showFadeLengthDialog(ctx, c, 'a', fadeIn: false));
      await t.pumpAndSettle();
      await t.tap(find.text('batidas'));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const ValueKey('fade-length-field')), '1,5');
      await t.tap(find.byKey(const ValueKey('fade-length-apply')));
      await t.pumpAndSettle();
      expect(c.audioClip('a')!.fadeOut, closeTo(0.75, 1e-9), reason: '1,5 batida a 120 BPM');
      unawaited(showFadeLengthDialog(ctx, c, 'a', fadeIn: true));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const ValueKey('fade-length-field')), 'abc');
      await t.tap(find.byKey(const ValueKey('fade-length-apply')));
      await t.pumpAndSettle();
      expect(find.textContaining('Digite um número'), findsOneWidget);
      await flushSave(t);
    });

    test('(5) o rótulo do código 0 é "Suave (padrão)" (a curva e o código são os de sempre)', () {
      expect(FadeShape.linear.index, 0);
      expect(FadeShape.linear.label, 'Suave (padrão)');
      expect(FadeShape.linear.gain(0.5), 0.25);
    });

    testWidgets('(3)(5) o menu do clipe traz os itens novos e o aviso de crossfade aparece na tela', (t) async {
      final c = studio();
      c.doc.tracks[0].clips.addAll([audio('c1', 0, 4), audio('c2', 6, 4)]);
      await mount(t, c, const Size(1400, 900));
      c.crossfadeOverlaps('c1');
      await t.pump();
      expect(find.text('1 crossfade aplicado.'), findsOneWidget);
      await flushSave(t);
    });
  });

  group('automação', () {
    test('(3) os modos dizem que só começam ao mexer no valor', () {
      for (final m in [AutoMode.write, AutoMode.touch, AutoMode.latch]) {
        expect(m.hint, startsWith('Começa ao mexer no controle'), reason: m.label);
      }
    });

    test('(4) Toque no loop: depois da volta, o dedo que segue se mexendo não reabre o trecho; um gesto novo reabre', () {
      final c = fakeController(FakeEngine())..addInstrumentTrack(TrackKind.synth);
      final lane = c.addLane(0, pan);
      lane.points.addAll([AutoPoint(beat: 0, value: 0), AutoPoint(beat: 4, value: 0)]);
      c.doc.loopOn = true;
      c.doc.loopEnd = 4;
      c.autoRec.setMode(AutoMode.touch);
      void move(double v) {
        c.autoRec.value(0, pan, v);
        c.mutate((d) => d.tracks[0].pan = v);
      }

      c.beat.value = 0;
      c.playing.value = true;
      c.beat.value = 3;
      c.autoRec.touch(0, pan);
      c.checkpoint();
      move(0.6);
      c.beat.value = 3.9;
      c.beat.value = 0.1; // a volta do loop
      expect(c.autoRec.isRecording(0, pan), isFalse);
      move(0.7); // o dedo segue se mexendo
      c.beat.value = 1;
      move(0.8);
      expect(c.autoRec.isRecording(0, pan), isFalse, reason: 'sem gesto novo não reabre');
      c.beat.value = 2;
      c.autoRec.release(0, pan);
      c.beat.value = 2.5;
      c.autoRec.touch(0, pan); // gesto novo
      move(0.3);
      expect(c.autoRec.isRecording(0, pan), isTrue);
      c.beat.value = 3;
      c.autoRec.release(0, pan);
      c.playing.value = false;
      double at(double b) => autoValueAt(lane.points, b, 0);
      expect(at(1.0), closeTo(0.0, 1e-9), reason: 'a volta 2 não gravou o movimento do dedo');
      expect(at(2.8), closeTo(0.3, 0.05), reason: 'o gesto novo gravou');
    });
  });

  group('presets do usuário', () {
    const kind = 'gate';
    Map<int, double> values() => UserPresets.capture(PresetFamily.effect, kind, (i) => 0);

    test('(1) arquivo ilegível guardado à parte: é aviso (dispensável), não problema; salvar segue sem alarme', () async {
      final st = MemoryUserPresetStorage()..data = '{isto não é json';
      final s = UserPresets(st);
      await s.load();
      expect(s.loadNotice, contains('userpresets.bak'));
      expect(s.infoNotice, s.loadNotice);
      expect(s.problem, isNull, reason: 'a gravação funciona');
      expect(s.hasBackup, isTrue);
      s.save(PresetFamily.effect, kind, 'g', values());
      await s.flush();
      expect(s.problem, isNull);
      expect(jsonDecode(st.data!)['presets'], hasLength(1));
      s.dismissLoadNotice();
      expect(s.infoNotice, isNull);
      expect(s.loadNotice, isNull);
    });

    test('(1) versão futura (só leitura) e falha de gravação seguem como problema', () async {
      final future = jsonEncode({'format': 'jopendaw-user-presets', 'version': 99, 'presets': []});
      final s = UserPresets(MemoryUserPresetStorage()..data = future);
      await s.load();
      expect(s.problem, contains('versão mais nova'));
      expect(s.infoNotice, isNull);
      s.dismissLoadNotice();
      expect(s.problem, isNotNull, reason: 'problema não se dispensa');
    });

    testWidgets('(1) o menu mostra o aviso informativo sem vermelho, dispensa ao tocar, e salvar não abre "Presets não guardados"', (t) async {
      final store = UserPresets(MemoryUserPresetStorage()..data = '{isto não é json');
      await store.load();
      final ctx = await pumpContext(t);
      final entries = userPresetEntries(presets: const [], color: Colors.blue, problem: store.problem, notice: store.infoNotice, hasBackup: store.hasBackup);
      expect(entries.any((e) => e.key == const ValueKey('user-preset-problem')), isFalse);
      expect(entries.any((e) => e.key == const ValueKey('user-preset-notice')), isTrue);
      expect(entries.any((e) => e.key == const ValueKey('user-preset-restore')), isTrue);
      await handleUserPresetChoice(ctx, const DismissUserPresetNotice(), family: PresetFamily.effect, kind: kind, capture: () => {}, presets: store);
      expect(store.infoNotice, isNull);
      unawaited(handleUserPresetChoice(ctx, const SaveUserPreset(), family: PresetFamily.effect, kind: kind, capture: values, presets: store));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const ValueKey('user-preset-name')), 'Meu');
      await t.pump();
      await t.tap(find.byKey(const ValueKey('user-preset-name-ok')));
      await t.pumpAndSettle();
      expect(store.ofEffect(EffectKind.gate).single.name, 'Meu');
      expect(find.text('Presets não guardados'), findsNothing);
    });

    test('(2) restaurar do backup recupera os presets inteiros de um arquivo cortado ao meio e não duplica', () async {
      UserPreset mk(String id, String name) => UserPreset(id: id, family: PresetFamily.effect, kind: kind, name: name, values: values());
      final json = jsonEncode({
        'format': 'jopendaw-user-presets',
        'version': 1,
        'presets': [mk('a', 'Um').toJson(), mk('b', 'Dois').toJson(), mk('c', 'Três').toJson()],
      });
      final cut = json.substring(0, json.lastIndexOf('{"id":"c"') + 40); // o terceiro chega pela metade
      final st = MemoryUserPresetStorage()..data = cut;
      final s = UserPresets(st);
      await s.load();
      expect(s.ofEffect(EffectKind.gate), isEmpty);
      expect(s.hasBackup, isTrue);
      s.save(PresetFamily.effect, kind, 'Dois', values()); // já existe um com esse nome
      final r = await s.restoreFromBackup();
      expect((r.restored, r.skipped), (1, 1));
      expect(s.ofEffect(EffectKind.gate).map((p) => p.name), ['Dois', 'Um']);
      await s.flush();
      expect(jsonDecode(st.data!)['presets'], hasLength(2));
      expect(st.backup, cut, reason: 'a cópia segue intacta');
      final again = await s.restoreFromBackup();
      expect((again.restored, again.skipped), (0, 2));
    });

    test('(2) restaurar sem cópia, com lixo total ou em modo leitura explica o motivo', () async {
      final none = UserPresets(MemoryUserPresetStorage());
      await expectLater(none.restoreFromBackup(), throwsA(isA<PresetFormatException>().having((e) => e.message, 'm', contains('Não há cópia'))));
      final junk = UserPresets(MemoryUserPresetStorage()..data = 'lixo');
      await junk.load();
      await expectLater(junk.restoreFromBackup(), throwsA(isA<PresetFormatException>().having((e) => e.message, 'm', contains('danificado demais'))));
      final ro = UserPresets(MemoryUserPresetStorage()..data = jsonEncode({'format': 'jopendaw-user-presets', 'version': 9, 'presets': []}));
      await ro.load();
      await expectLater(ro.restoreFromBackup(), throwsA(isA<PresetFormatException>().having((e) => e.message, 'm', contains('só para leitura'))));
    });

    testWidgets('(2) a ação "Restaurar presets do backup…" confirma, restaura e conta', (t) async {
      UserPreset mk(String id, String name) => UserPreset(id: id, family: PresetFamily.effect, kind: kind, name: name, values: values());
      final json = jsonEncode({
        'format': 'jopendaw-user-presets',
        'version': 1,
        'presets': [mk('a', 'Um').toJson(), mk('b', 'Dois').toJson()],
      });
      final store = UserPresets(MemoryUserPresetStorage()..data = json.substring(0, json.length - 20));
      await store.load();
      final ctx = await pumpContext(t);
      unawaited(handleUserPresetChoice(ctx, const RestoreUserPresets(), family: PresetFamily.effect, kind: kind, capture: () => {}, presets: store));
      await t.pumpAndSettle();
      expect(find.text('Restaurar do backup?'), findsOneWidget);
      await t.tap(find.text('Restaurar'));
      await t.pumpAndSettle();
      expect(find.text('Presets restaurados'), findsOneWidget);
      expect(find.textContaining('1 preset restaurado'), findsOneWidget);
      expect(store.ofEffect(EffectKind.gate).single.name, 'Um');
    });
  });

  group('andamento e .mid', () {
    Future<MidiFileData> fileAt(double bpm) {
      final us = (60000000 / bpm).round();
      final conductor = [0, 0xFF, 0x51, 3, us ~/ 65536 % 256, us ~/ 256 % 256, us % 256, ...eot];
      final notes = [0, 0x90, 60, 64, ...vlq(96), 0x80, 60, 0, ...eot];
      return parseMidiFile(smf(1, 96, [conductor, notes]));
    }

    test('(1) a fração do andamento conta: 98,4 num projeto em 98 abre a pergunta; 98,02 não', () async {
      final doc = DawDoc(bpm: 98, beatsPerBar: 4, tracks: []);
      expect(midiTempoDiffers(await fileAt(98.4), doc), isTrue);
      expect(midiTempoDiffers(await fileAt(97.5), doc), isTrue);
      expect(midiTempoDiffers(await fileAt(98.02), doc), isFalse, reason: 'dentro de 0,05 BPM');
      expect(midiTempoDiffers(await fileAt(98), doc), isFalse);
    });

    test('(2) o texto do limite de compassos bate com o aviso da importação (o compasso inicial conta)', () {
      expect(maxMeterChanges, 1024);
      expect(meterChangesFullMessage, contains('${maxMeterChanges - 1} mudanças'));
      expect(meterChangesFullMessage, isNot(contains('$maxMeterChanges mudanças')));
    });

    test('(4) o rótulo curto do formato não traz parênteses (o texto do resultado não fica com dois)', () {
      expect(ExportFormat.mp3.shortLabel, 'MP3');
      expect(ExportFormat.flac.shortLabel, 'FLAC');
      expect(ExportFormat.wav24.shortLabel, 'WAV 24 bits');
      for (final f in ExportFormat.values) {
        expect(f.shortLabel, isNot(contains('(')), reason: f.name);
      }
    });
  });
}
