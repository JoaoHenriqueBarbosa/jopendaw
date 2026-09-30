// Fase 14, item A: correções da gravação de automação (mini fader do master, ponteiro sem botão, Escrever da raia,
// valor fixo depois do Toque, loop) e dos presets do usuário (aviso de gravação, arquivo ilegível ou de versão futura,
// rótulos, nome, tipo em português, cancelar o "salvar como").
import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Curve;
import 'package:flutter_test/flutter_test.dart';
import 'package:jopendaw_app/daw/automation_math.dart';
import 'package:jopendaw_app/daw/automation_mode.dart';
import 'package:jopendaw_app/daw/controller.dart';
import 'package:jopendaw_app/daw/effects.dart';
import 'package:jopendaw_app/daw/instrument_panel.dart';
import 'package:jopendaw_app/daw/instruments.dart';
import 'package:jopendaw_app/daw/model.dart';
import 'package:jopendaw_app/daw/presets.dart';
import 'package:jopendaw_app/daw/user_presets.dart';
import 'package:jopendaw_app/daw/user_presets_ui.dart';
import 'package:jopendaw_app/widgets/theme.dart';

import 'fake_engine.dart' hide settle;
import 'studio_test.dart' show flushSave, mount, studio;

const pan = AutoTarget(AutoKind.pan);
const volume = AutoTarget(AutoKind.volume);

List<AutoPoint> pts(List<(double, double)> l) => [for (final (b, v) in l) AutoPoint(beat: b, value: v)];

DawController rig() {
  final c = fakeController(FakeEngine());
  c.addInstrumentTrack(TrackKind.synth);
  return c;
}

void grab(DawController c, int track, AutoTarget t) {
  c.autoRec.touch(track, t);
  c.checkpoint();
}

void movePan(DawController c, double v) {
  c.autoRec.value(0, pan, v);
  c.mutate((d) => d.tracks[0].pan = v);
}

Widget app(Widget child) => MaterialApp(
  theme: buildTheme(),
  home: Scaffold(body: child),
);

class _Failing implements UserPresetStorage {
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String json) => Future.error('sem espaço');
  @override
  Future<void> writeBackup(String raw) async {}
  @override
  Future<String?> readBackup() async => null;
}

void main() {
  group('automação', () {
    test('mouse sem botão (hover) não fecha o Toque; só Up/Cancel fecham', () {
      final c = rig();
      final lane = c.addLane(0, pan);
      lane.points.addAll(pts([(0, -1), (8, 1)]));
      c.autoRec.setMode(AutoMode.touch);
      c.beat.value = 2;
      c.playing.value = true;
      grab(c, 0, pan);
      movePan(c, 0.5);
      expect(c.autoRec.openTargets, 1);
      // a roda do mouse: o ponteiro só passa por cima, sem nenhum botão apertado
      c.debugPointer(const PointerHoverEvent(position: Offset(10, 10)));
      c.debugPointer(const PointerHoverEvent(position: Offset(12, 10)));
      expect(c.autoRec.openTargets, 1, reason: 'hover não fecha o trecho');
      c.debugPointer(const PointerUpEvent(position: Offset(10, 10)));
      expect(c.autoRec.openTargets, 0, reason: 'levantar o último dedo fecha');
      c.playing.value = false;

      // cancelamento também
      c.beat.value = 2;
      c.playing.value = true;
      grab(c, 0, pan);
      movePan(c, 0.1);
      c.debugPointer(const PointerCancelEvent(position: Offset(10, 10)));
      expect(c.autoRec.openTargets, 0);
      c.playing.value = false;
    });

    test('Toque: ao fechar, o valor fixo volta ao de antes da mão (não fica no último valor gravado)', () {
      final c = rig();
      c.doc.tracks[0].pan = 0.2;
      final lane = c.addLane(0, pan);
      lane.points.addAll(pts([(0, -1), (8, 1)]));
      c.autoRec.setMode(AutoMode.touch);
      c.beat.value = 2;
      c.playing.value = true;
      grab(c, 0, pan);
      movePan(c, 0.9);
      expect(c.doc.tracks[0].pan, 0.9, reason: 'enquanto segura, o controle vale a mão');
      c.beat.value = 3;
      c.autoRec.release(0, pan);
      expect(c.doc.tracks[0].pan, closeTo(0.2, 1e-9), reason: 'soltou: o fixo de antes');
      c.playing.value = false;
      expect(c.doc.tracks[0].pan, closeTo(0.2, 1e-9));
    });

    test('Toque num parâmetro de instrumento: o fixo também volta', () {
      final c = rig();
      const cutoff = AutoTarget(AutoKind.instrument, param: SynthId.cutoff);
      c.setParam(1, SynthId.cutoff, 1000);
      c.autoRec.setMode(AutoMode.touch);
      c.beat.value = 0;
      c.playing.value = true;
      grab(c, 1, cutoff);
      c.setParam(1, SynthId.cutoff, 4000);
      c.beat.value = 1;
      c.autoRec.release(1, cutoff);
      expect(c.doc.tracks[1].param(SynthId.cutoff), 1000);
      c.playing.value = false;
    });

    test('Toque com loop: a volta seguinte não grava o último valor mantido', () {
      final c = rig();
      final lane = c.addLane(0, pan);
      lane.points.addAll(pts([(0, 0), (4, 0)]));
      c.doc.loopOn = true;
      c.doc.loopEnd = 4;
      c.autoRec.setMode(AutoMode.touch);
      c.beat.value = 0;
      c.playing.value = true;
      c.beat.value = 3;
      grab(c, 0, pan);
      movePan(c, 0.6);
      c.beat.value = 3.9;
      c.beat.value = 0.1; // volta do loop com o controle ainda seguro
      expect(c.autoRec.isRecording(0, pan), isFalse, reason: 'parou de gravar até novo gesto');
      c.beat.value = 1;
      c.beat.value = 2;
      c.beat.value = 3;
      c.autoRec.release(0, pan);
      c.playing.value = false;
      double at(double b) => autoValueAt(lane.points, b, 0);
      expect(at(3.5), closeTo(0.6, 0.05), reason: 'a volta 1 ficou');
      expect(at(1.5), closeTo(0.0, 1e-9), reason: 'a volta 2 não sobrescreveu com 0,6 (a curva antiga vale)');
      expect(c.doc.tracks[0].pan, closeTo(0, 1e-9));
    });

    test('Trava com loop: segue na volta só se o controle ainda está seguro', () {
      for (final held in [true, false]) {
        final c = rig();
        final lane = c.addLane(0, pan);
        lane.points.addAll(pts([(0, 0), (4, 0)]));
        c.doc.loopOn = true;
        c.doc.loopEnd = 4;
        c.autoRec.setMode(AutoMode.latch);
        c.beat.value = 0;
        c.playing.value = true;
        c.beat.value = 3;
        grab(c, 0, pan);
        movePan(c, 0.6);
        if (!held) c.autoRec.release(0, pan);
        c.beat.value = 3.9;
        c.beat.value = 0.1;
        expect(c.autoRec.isRecording(0, pan), held, reason: 'held=$held');
        c.beat.value = 1;
        c.beat.value = 2;
        c.beat.value = 3;
        c.autoRec.release(0, pan);
        c.playing.value = false;
        final v = autoValueAt(lane.points, 1.5, 0);
        if (held) {
          expect(v, closeTo(0.6, 0.05));
        } else {
          expect(v, closeTo(0.0, 1e-9), reason: 'a volta 2 não regravou');
        }
      }
    });

    testWidgets('mini fader do Master grava: Toque escreve na raia do master e devolve o valor fixo', (t) async {
      final c = studio();
      addTearDown(c.midiLearn.dispose);
      await mount(t, c, const Size(1400, 900));
      c.doc.masterGain = 1.0;
      c.autoRec.setMode(AutoMode.touch);
      c.playing.value = true;
      c.beat.value = 1;
      await t.pump();
      // o deslizador do master é o mais baixo da tela (a linha fica no fim da lista)
      double y(Element e) => (e.renderObject! as RenderBox).localToGlobal(Offset.zero).dy;
      final sliders = find.byType(Slider).evaluate().where((e) => e.renderObject is RenderBox).toList()..sort((a, b) => y(a).compareTo(y(b)));
      final box = sliders.last.renderObject! as RenderBox;
      final centre = box.localToGlobal(box.size.center(Offset.zero));
      final g = await t.startGesture(centre);
      await t.pump();
      await g.moveBy(const Offset(-30, 0));
      await t.pump();
      c.beat.value = 2;
      await g.moveBy(const Offset(-20, 0));
      await t.pump();
      expect(c.autoRec.isRecording(-1, volume), isTrue, reason: 'o master entrou na gravação');
      c.beat.value = 3;
      await g.up();
      await t.pump();
      expect(c.autoRec.openTargets, 0);
      final lane = c.doc.masterLanes.where((l) => l.target == volume).single;
      expect(lane.points.length, greaterThanOrEqualTo(2), reason: 'a raia do master ganhou o gesto');
      expect(c.doc.masterGain, closeTo(1.0, 1e-9), reason: 'o Toque devolveu o fixo');
      c.playing.value = false;
      await t.pump();
      await flushSave(t);
    });
  });

  group('presets', () {
    test('falha de gravação: problem mostra o aviso e a tela é avisada', () async {
      final s = UserPresets(_Failing());
      var notified = 0;
      s.addListener(() => notified++);
      s.save(PresetFamily.effect, 'gate', 'g', UserPresets.capture(PresetFamily.effect, 'gate', (i) => 0));
      await s.flush();
      expect(s.problem, 'Não deu para guardar seus presets neste aparelho.');
      expect(notified, greaterThanOrEqualTo(2), reason: 'a mudança e depois o aviso');
    });

    test('arquivo ilegível vai para o backup antes de ser sobrescrito', () async {
      final st = MemoryUserPresetStorage()..data = '{isto não é json';
      final s = UserPresets(st);
      await s.load();
      expect(st.backup, '{isto não é json');
      expect(s.loadNotice, contains('userpresets.bak'));
      s.save(PresetFamily.effect, 'gate', 'g', UserPresets.capture(PresetFamily.effect, 'gate', (i) => 0));
      await s.flush();
      expect(st.backup, '{isto não é json', reason: 'a cópia segue intacta');
      expect(jsonDecode(st.data!)['presets'], hasLength(1));
    });

    test('versão futura: mostra o que dá, não sobrescreve e avisa', () async {
      final future = jsonEncode({
        'format': 'jopendaw-user-presets',
        'version': 99,
        'novo': {'campo': 1},
        'presets': [
          {
            'id': 'a',
            'family': 'effect',
            'kind': 'gate',
            'name': 'Do futuro',
            'params': {'0': 1},
          },
        ],
      });
      final st = MemoryUserPresetStorage()..data = future;
      final s = UserPresets(st);
      // salvar antes de o carregamento acabar também não pode passar por cima
      s.save(PresetFamily.effect, 'gate', 'g', UserPresets.capture(PresetFamily.effect, 'gate', (i) => 0));
      await s.flush();
      expect(st.data, future, reason: 'intacto');
      expect(s.loadNotice, contains('versão mais nova'));
      expect(s.ofEffect(EffectKind.gate).map((p) => p.name), containsAll(['Do futuro', 'g']));
      s.delete(s.ofEffect(EffectKind.gate).first.id);
      await s.flush();
      expect(st.data, future);
    });

    test('nome do tipo em português', () {
      expect(presetKindLabel(PresetFamily.effect, 'reverb'), EffectKind.reverb.label);
      expect(presetKindLabel(PresetFamily.instrument, 'synth'), TrackKind.synth.label);
      expect(presetKindLabel(PresetFamily.instrument, 'holograma'), 'holograma');
    });

    testWidgets('apagar o preset aplicado tira o "(editado)"; renomear atualiza o nome; faixa nova vale "Inicial"', (t) async {
      t.view.physicalSize = const Size(1400, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final store = UserPresets(MemoryUserPresetStorage());
      UserPresets.instance = store;
      final c = fakeController(FakeEngine());
      addTearDown(c.dispose);
      c.addInstrumentTrack(TrackKind.synth);
      final tr = c.doc.tracks[1];
      // preset todo no padrão: numa faixa nova não pode vencer o "Inicial"
      final def = store.save(PresetFamily.instrument, 'synth', 'Padrão meu', UserPresets.capture(PresetFamily.instrument, 'synth', (id) => tr.param(id)))!;
      final cut = store.save(PresetFamily.instrument, 'synth', 'Corte', {SynthId.cutoff: 777})!;
      await t.pumpWidget(
        app(
          ListenableBuilder(
            listenable: c,
            builder: (_, _) => InstrumentPanel(c: c),
          ),
        ),
      );
      expect(find.text('Inicial'), findsOneWidget);
      expect(find.text('Padrão meu'), findsNothing);

      Future<void> apply(String name) async {
        await t.tap(find.byTooltip('Presets').first);
        await t.pumpAndSettle();
        final item = find.widgetWithText(PopupMenuItem<Object>, name);
        await t.ensureVisible(item);
        await t.tap(item);
        await t.pumpAndSettle();
      }

      await apply('Corte');
      c.setParam(1, SynthId.cutoff, 800);
      await t.pump();
      expect(find.text('Corte (editado)'), findsOneWidget);
      store.rename(cut.id, 'Corte novo');
      await t.pump();
      expect(find.text('Corte novo (editado)'), findsOneWidget, reason: 'nome novo, não o antigo');
      store.delete(cut.id);
      await t.pump();
      expect(find.textContaining('(editado)'), findsNothing, reason: 'o preset não existe mais');
      expect(find.text('Personalizado'), findsOneWidget);
      expect(store.byId(def.id), isNotNull);
      expect(t.takeException(), isNull);
      await flushSave(t);
    });

    testWidgets('o menu mostra o aviso quando não guarda; importar de outro tipo usa o nome em português; cancelar o salvar como avisa', (t) async {
      final store = UserPresets(_Failing());
      store.save(PresetFamily.effect, 'reverb', 'Sala', {3: 2});
      await store.flush();
      final p = store.ofEffect(EffectKind.reverb).single;
      await t.pumpWidget(
        app(
          Builder(
            builder: (context) => Column(
              children: [
                PopupMenuButton<Object>(
                  tooltip: 'menu',
                  constraints: const BoxConstraints(minWidth: 300, maxWidth: 400),
                  itemBuilder: (_) => userPresetEntries(presets: [p], color: Colors.blue, problem: store.problem),
                ),
                TextButton(
                  onPressed: () => handleUserPresetChoice(
                    context,
                    UserPresetMore(p),
                    family: PresetFamily.effect,
                    kind: 'reverb',
                    capture: () => {},
                    presets: store,
                    save: (n, b, m) async => false,
                  ),
                  child: const Text('exportar'),
                ),
                TextButton(
                  onPressed: () => handleUserPresetChoice(
                    context,
                    const ImportUserPreset(),
                    family: PresetFamily.instrument,
                    kind: 'synth',
                    capture: () => {},
                    presets: store,
                    pick: () async => ('a.jopreset', store.exportBytes(p)),
                  ),
                  child: const Text('importar'),
                ),
              ],
            ),
          ),
        ),
      );
      await t.tap(find.byTooltip('menu'));
      await t.pumpAndSettle();
      expect(find.text('Não deu para guardar seus presets neste aparelho.'), findsOneWidget);
      await t.tapAt(const Offset(5, 5));
      await t.pumpAndSettle();

      await t.tap(find.text('exportar'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('user-preset-export')));
      await t.pumpAndSettle();
      expect(find.text('Exportação cancelada'), findsOneWidget);
      await t.tap(find.text('Ok'));
      await t.pumpAndSettle();

      await t.tap(find.text('importar'));
      await t.pumpAndSettle();
      expect(find.textContaining('outro tipo (${EffectKind.reverb.label})'), findsOneWidget);
      expect(find.textContaining('(reverb)'), findsNothing);
    });

    testWidgets('o campo de nome barra marcas de largura zero e de direção', (t) async {
      await t.pumpWidget(
        app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => askPresetName(context, title: 'Nome', confirm: 'Ok'),
              child: const Text('go'),
            ),
          ),
        ),
      );
      await t.tap(find.text('go'));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const ValueKey('user-preset-name')), 'a\u200bb\u202Ec\uFEFFd\u200Fe');
      await t.pump();
      expect(t.widget<TextField>(find.byKey(const ValueKey('user-preset-name'))).controller!.text, 'abcde');
    });
  });
}
