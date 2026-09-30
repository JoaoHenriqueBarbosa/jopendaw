// Fase 13, item C: telas do MIDI learn (contorno, armar, menu de contexto, painel de mapeamentos,
// atalho), polimentos do .mid (compasso do arquivo, limites, aviso em pt-BR), "Meus presets" no
// topo dos menus e o deslizador do cabeçalho com prioridade sobre o reordenar.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Curve;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jopendaw_app/daw/effects.dart';
import 'package:jopendaw_app/daw/controller.dart';
import 'package:jopendaw_app/daw/effects_panel.dart';
import 'package:jopendaw_app/daw/instrument_panel.dart';
import 'package:jopendaw_app/daw/instruments.dart';
import 'package:jopendaw_app/daw/knob.dart';
import 'package:jopendaw_app/daw/midi_file.dart';
import 'package:jopendaw_app/daw/midi_file_ui.dart';
import 'package:jopendaw_app/daw/midi_learn.dart';
import 'package:jopendaw_app/daw/midi_learn_ui.dart';
import 'package:jopendaw_app/daw/midi_map.dart';
import 'package:jopendaw_app/daw/model.dart';
import 'package:jopendaw_app/daw/presets.dart';
import 'package:jopendaw_app/daw/tempo_map.dart';
import 'package:jopendaw_app/daw/user_presets.dart';
import 'package:jopendaw_app/daw/fx_presets.dart';
import 'package:jopendaw_app/widgets/theme.dart';

import 'fake_engine.dart' hide settle;
import 'midi_file_test.dart' show eot, smf, vlq;
import 'piano_roll_test.dart' show TestDaw, host, mac, settle;
import 'rack_test.dart' show RackDaw;
import 'studio_test.dart' show flushSave, mount, studio;

Widget app(Widget child) => MaterialApp(
  theme: buildTheme(),
  home: Scaffold(body: child),
);

Finder knobOf(int id) => find.byWidgetPredicate((w) => w is Knob && w.spec.id == id);

void main() {
  group('MIDI learn na tela', () {
    testWidgets('modo aprender: contorno nos knobs, clicar arma, o CC mapeia, o pontinho fica e Esc sai', (t) async {
      t.view.physicalSize = const Size(1400, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final c = fakeController(FakeEngine());
      addTearDown(c.midiLearn.dispose);
      c.addInstrumentTrack(TrackKind.synth);
      await t.pumpWidget(
        app(
          ListenableBuilder(
            listenable: c,
            builder: (_, _) => Column(
              children: [
                MidiLearnBanner(c: c),
                Expanded(child: InstrumentPanel(c: c)),
              ],
            ),
          ),
        ),
      );
      final cutoffKey = find.byKey(const ValueKey('midi-learn-1_instrument_null_13'));
      expect(cutoffKey, findsNothing, reason: 'fora do modo não há contorno');
      c.midiLearn.setLearning(true);
      await t.pump();
      expect(find.byKey(const ValueKey('midi-learn-banner')), findsOneWidget);
      await t.ensureVisible(cutoffKey);
      await t.tap(cutoffKey);
      await t.pump();
      expect(c.midiLearn.armed?.target, const AutoTarget(AutoKind.instrument, param: 13));
      expect(find.textContaining('Mexa no controle do seu teclado'), findsOneWidget);
      // o teclado manda o CC 74: vira o mapeamento e desarma
      expect(c.midiLearn.handle(0xB0, 74, 64), isTrue);
      await t.pump();
      expect(c.midiLearn.armed, isNull);
      expect(find.text('CC74'), findsOneWidget, reason: 'o contorno diz de onde vem');
      expect(find.textContaining('Aprendido: Canal 1 · CC 74'), findsOneWidget);
      // clicar de novo no armado desarma
      await t.tap(cutoffKey);
      await t.pump();
      expect(c.midiLearn.armed, isNotNull);
      await t.tap(cutoffKey);
      await t.pump();
      expect(c.midiLearn.armed, isNull);
      c.midiLearn.setLearning(false);
      await t.pump();
      expect(cutoffKey, findsNothing);
      expect(find.byKey(const ValueKey('midi-mapped-dot')), findsOneWidget, reason: 'fora do modo, o mapeado leva um pontinho');
      expect(t.takeException(), isNull);
      await flushSave(t);
    });

    testWidgets('botão direito no knob: digitar o valor, aprender e remover mapeamento', (t) async {
      t.view.physicalSize = const Size(1400, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final c = fakeController(FakeEngine());
      addTearDown(c.midiLearn.dispose);
      c.addInstrumentTrack(TrackKind.synth);
      await t.pumpWidget(
        app(
          ListenableBuilder(
            listenable: c,
            builder: (_, _) => InstrumentPanel(c: c),
          ),
        ),
      );
      final knob = knobOf(SynthId.cutoff);
      await t.ensureVisible(knob);
      await t.pump();
      await t.tap(knob, buttons: kSecondaryButton);
      await t.pumpAndSettle();
      expect(find.text('Digitar o valor…'), findsOneWidget);
      expect(find.text('Remover mapeamento (Canal 1 · CC 74)'), findsNothing);
      await t.tap(find.text('Aprender MIDI'));
      await t.pumpAndSettle();
      expect(c.midiLearn.learning, isTrue);
      expect(c.midiLearn.armed?.target.param, SynthId.cutoff);
      c.midiLearn.handle(0xB0, 74, 10);
      c.midiLearn.setLearning(false);
      await t.pump();
      await t.tap(knob, buttons: kSecondaryButton);
      await t.pumpAndSettle();
      await t.tap(find.text('Remover mapeamento (Canal 1 · CC 74)'));
      await t.pumpAndSettle();
      expect(c.doc.midiMap.isEmpty, isTrue);
      // "Digitar o valor…" continua abrindo o campo do knob
      await t.tap(knob, buttons: kSecondaryButton);
      await t.pumpAndSettle();
      await t.tap(find.text('Digitar o valor…'));
      await t.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      await t.tap(find.text('Cancelar'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await flushSave(t);
    });

    testWidgets('painel de mapeamentos: lista, invertido, curva, faixa, takeover, remover e padrão', (t) async {
      t.view.physicalSize = const Size(1000, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final store = MemoryStore();
      final c = fakeController(FakeEngine(), store: store);
      addTearDown(c.midiLearn.dispose);
      c.addInstrumentTrack(TrackKind.synth);
      final slot = c.addEffect(1, EffectKind.reverb);
      final l = c.midiLearn;
      l.arm(1, const AutoTarget(AutoKind.instrument, param: SynthId.cutoff));
      l.handle(0xB0, 74, 20);
      l.arm(-1, const AutoTarget(AutoKind.pan));
      l.handle(0xE1, 0, 64);
      l.arm(1, AutoTarget(AutoKind.effect, ref: slot.id, param: slot.kind.params.first.id));
      l.handle(0xB0, 20, 1);
      await t.pumpWidget(app(MidiMapPanel(c: c)));
      expect(find.text('Mapeamentos MIDI'), findsOneWidget);
      expect(find.text('Canal 1 · CC 74'), findsOneWidget);
      expect(find.text('Canal 2 · Pitch bend'), findsOneWidget);
      expect(find.textContaining('Master · Pan'), findsOneWidget);
      expect(find.textContaining('Sintetizador 1 · Instrumento · Corte'), findsOneWidget);
      final cut = c.doc.midiMap.items.firstWhere((m) => m.target.param == SynthId.cutoff && m.target.kind == AutoKind.instrument);

      // invertido
      await t.tap(find.byKey(ValueKey('midi-invert-${cut.id}')));
      await t.pump();
      expect(cut.inverted, isTrue);
      // curva
      await t.tap(find.byKey(ValueKey('midi-curve-${cut.id}')));
      await t.pumpAndSettle();
      await t.tap(find.text('Logarítmica').last);
      await t.pumpAndSettle();
      expect(cut.curve, MidiCurve.log);
      // faixa: arrastar o ponto de baixo do controle
      final range = find.byKey(ValueKey('midi-range-${cut.id}'));
      final box = t.getRect(range);
      await t.dragFrom(Offset(box.left + 12, box.center.dy), Offset(box.width * 0.4, 0));
      await t.pump();
      expect(cut.min, greaterThan(0.2));
      // takeover
      expect(c.doc.midiMap.soft, isTrue);
      await t.tap(find.byKey(const ValueKey('midi-soft')));
      await t.pump();
      expect(c.doc.midiMap.soft, isFalse);
      // padrão para novos projetos
      await t.tap(find.byKey(const ValueKey('midi-default-save')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('midi-note')), findsOneWidget);
      final saved = await loadMidiDefault(store);
      expect(saved, isA<Map>());
      expect((saved! as Map)['items'], hasLength(2), reason: 'o efeito não vai no padrão');
      await t.tap(find.byKey(const ValueKey('midi-default-clear')));
      await t.pumpAndSettle();
      expect(await loadMidiDefault(store), isNull);
      // remover um
      await t.tap(find.byKey(ValueKey('midi-remove-${cut.id}')));
      await t.pump();
      expect(find.text('Canal 1 · CC 74'), findsNothing);
      expect(c.doc.midiMap.items.length, 2);
      // efeito removido: a linha fica, avisando, para o usuário poder tirá-la
      c.removeEffect(1, slot.id);
      await t.pump();
      expect(find.textContaining('alvo removido'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('midi-clear')));
      await t.pump();
      expect(find.textContaining('Nenhum mapeamento'), findsOneWidget);
      expect(t.takeException(), isNull);
      await flushSave(t);
    });

    testWidgets('Shift+K liga o modo pela tela do projeto, o botão da barra acompanha e Esc desarma e sai', (t) async {
      final c = studio();
      addTearDown(c.midiLearn.dispose);
      await mount(t, c, const Size(1400, 900));
      expect(c.midiLearn.learning, isFalse);
      await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await t.sendKeyEvent(LogicalKeyboardKey.keyK);
      await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await t.pump();
      expect(c.midiLearn.learning, isTrue);
      expect(find.byKey(const ValueKey('midi-learn-banner')), findsOneWidget);
      // clicar num controle contornado do mixer arma; Esc desarma; Esc de novo sai
      c.selectTrack(1);
      c.setDock(Dock.mixer);
      await t.pump();
      c.midiLearn.arm(1, const AutoTarget(AutoKind.volume));
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pump();
      expect(c.midiLearn.armed, isNull);
      expect(c.midiLearn.learning, isTrue);
      expect(c.dock, Dock.mixer, reason: 'o primeiro Esc é do aprender, não fecha o painel');
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pump();
      expect(c.midiLearn.learning, isFalse);
      // o botão da barra liga e desliga
      c.midiEnabled = true; // o botão só aparece com o MIDI ligado
      await t.pump();
      await t.ensureVisible(find.byKey(const ValueKey('midi-learn-button')));
      await t.tap(find.byKey(const ValueKey('midi-learn-button')));
      await t.pump();
      expect(c.midiLearn.learning, isTrue);
      await t.tap(find.byKey(const ValueKey('midi-learn-button')));
      await t.pump();
      expect(c.midiLearn.learning, isFalse);
      expect(t.takeException(), isNull);
      await flushSave(t);
    });

    testWidgets('mixer no modo aprender: fader, pan e envio ganham contorno e aprendem', (t) async {
      final c = studio();
      addTearDown(c.midiLearn.dispose);
      await mount(t, c, const Size(1400, 900));
      c.selectTrack(1);
      c.setDock(Dock.mixer);
      c.midiLearn.setLearning(true);
      await t.pump();
      for (final k in ['0_volume_null_0', '0_pan_null_0', '1_volume_null_0', '-1_volume_null_0']) {
        expect(find.byKey(ValueKey('midi-learn-$k')), findsWidgets, reason: k);
      }
      await t.tap(find.byKey(const ValueKey('midi-learn--1_volume_null_0')).first);
      await t.pump();
      expect(c.midiLearn.armed, (track: -1, target: const AutoTarget(AutoKind.volume)));
      c.midiLearn.handle(0xB0, 7, 100);
      expect(c.doc.midiMap.items.single.trackId, isNull, reason: 'o master não tem faixa');
      expect(t.takeException(), isNull);
      c.midiLearn.setLearning(false);
      await t.pump();
      await flushSave(t);
    });
  });

  group('menus de presets: Meus presets no topo', () {
    testWidgets('instrumento: a seção do usuário e salvar/importar vêm antes dos de fábrica', (t) async {
      t.view.physicalSize = const Size(1400, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      UserPresets.instance = UserPresets(MemoryUserPresetStorage());
      final c = fakeController(FakeEngine());
      addTearDown(c.dispose);
      c.addInstrumentTrack(TrackKind.synth);
      UserPresets.instance.save(PresetFamily.instrument, 'synth', 'Meu lead', UserPresets.capture(PresetFamily.instrument, 'synth', c.doc.tracks[1].param));
      await t.pumpWidget(
        app(
          ListenableBuilder(
            listenable: c,
            builder: (_, _) => InstrumentPanel(c: c),
          ),
        ),
      );
      await t.tap(find.byTooltip('Presets').first);
      await t.pumpAndSettle();
      final first = presetsFor(TrackKind.synth).first;
      final mine = t.getTopLeft(find.text('MEUS PRESETS')).dy;
      expect(mine, lessThan(t.getTopLeft(find.text(first.category.toUpperCase())).dy));
      expect(t.getTopLeft(find.text('Meu lead').last).dy, lessThan(t.getTopLeft(find.text(first.name)).dy));
      expect(t.getTopLeft(find.text('Salvar como preset…')).dy, lessThan(t.getTopLeft(find.text(first.category.toUpperCase())).dy));
      expect(t.getTopLeft(find.text('Importar preset…')).dy, lessThan(t.getTopLeft(find.text(first.name)).dy));
      expect(find.text('MEUS PRESETS'), findsOneWidget);
      // aplicar de dentro do topo continua funcionando, e o rótulo vai a "(editado)" com a mão
      await t.tap(find.text('Meu lead').last);
      await t.pumpAndSettle();
      c.setParam(1, SynthId.cutoff, 1234);
      await t.pump();
      expect(find.text('Meu lead (editado)'), findsOneWidget);
      await flushSave(t);
    });

    testWidgets('efeito: idem, acima dos de fábrica', (t) async {
      t.view.physicalSize = const Size(1280, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      UserPresets.instance = UserPresets(MemoryUserPresetStorage());
      final c = RackDaw();
      addTearDown(c.dispose);
      c.addEffect(0, EffectKind.reverb);
      c.showEffects(0);
      final probe = EffectSlot(id: 'p', kind: EffectKind.reverb);
      UserPresets.instance.save(PresetFamily.effect, 'reverb', 'Minha sala', UserPresets.capture(PresetFamily.effect, 'reverb', probe.param));
      await t.pumpWidget(
        app(
          ListenableBuilder(
            listenable: c,
            builder: (_, _) => EffectsPanel(c: c),
          ),
        ),
      );
      await t.pump();
      await t.tap(find.byTooltip('Presets e mais').first);
      await t.pumpAndSettle();
      final factory = effectPresetsFor(EffectKind.reverb).first;
      expect(t.getTopLeft(find.text('MEUS PRESETS')).dy, lessThan(t.getTopLeft(find.text('PRESETS')).dy));
      expect(t.getTopLeft(find.text('Salvar como preset…')).dy, lessThan(t.getTopLeft(find.text(factory.name)).dy));
      expect(t.getTopLeft(find.text('Importar preset…')).dy, lessThan(t.getTopLeft(find.text(factory.name)).dy));
      expect(find.text('Reiniciar (valores padrão)'), findsOneWidget, reason: 'as ações do efeito seguem no menu');
    });
  });

  group('.mid: compasso e avisos', () {
    test('o compasso do clipe usa o mesmo limite do documento (1–32), não 12', () {
      expect(importedMeterBeats(const MeterChange(1, 13, 4)), 13);
      expect(importedMeterBeats(const MeterChange(1, 4, 1)), 16, reason: '4/1 tem 16 semínimas');
      expect(importedMeterBeats(const MeterChange(1, 64, 4)), 32);
      expect(importedMeterBeats(const MeterChange(1, 5, 8)), 3);
      expect(importedMeter(_data(13, 2))!.beatsPerBar, 13);
    });

    test('um arquivo em 13/4 cria o clipe fechando em compassos de 13 batidas', () async {
      final c = fakeController(FakeEngine());
      final bytes = smf(0, 480, [_meterTrack(13, 2)]);
      final r = await c.importMidiBytes('x.mid', bytes, confirmTempo: (_) async => true, at: 0);
      expect(r!.tempoApplied, isTrue);
      expect(c.doc.beatsPerBar, 13);
      // uma nota de 1 batida: o clipe fecha no compasso de 13
      expect(c.doc.tracks.last.midi.single.length, 13);
    });

    test('aviso de fusão: vírgula decimal e plural pt-BR', () async {
      // dois andamentos que diferem menos que o mínimo: a mudança é fundida
      List<int> track(List<int> second) => [
        0, 0xFF, 0x51, 3, 0x0A, 0x2C, 0x2B, // 90 BPM: o projeto está em 120, então o arquivo é levado a sério
        0, 0x90, 60, 100,
        ...vlq(480), ...second, // +0,01 BPM
        0, 0x80, 60, 0,
        ...eot,
      ];
      final c = fakeController(FakeEngine());
      final one = await c.importMidiBytes(
        'x.mid',
        smf(0, 480, [
          track([0xFF, 0x51, 3, 0x0A, 0x2B, 0xC7]),
        ]),
        confirmTempo: (_) async => true,
        at: 0,
      );
      final w = one!.warnings.single;
      expect(w, contains('1 mudança de andamento'), reason: w);
      expect(w, contains('0,05 BPM'));
      expect(w, isNot(contains('0.05')));
      expect(w, isNot(contains('1 mudanças')));
      expect(w, contains('0 ficaram no mapa'));
    });

    testWidgets('a pergunta dos andamentos mostra o compasso real do projeto (6/8 não vira 3/4)', (t) async {
      final c = fakeController(FakeEngine());
      c.setMeterMap(const [MeterChange(1, 6, 8)]);
      final data = await t.runAsync(() => parseMidiFile(smf(0, 480, [_meterTrack(3, 2)])));
      await t.pumpWidget(
        app(
          Builder(
            builder: (context) => TextButton(onPressed: () => askUseFileTempo(context, data!, c), child: const Text('abrir')),
          ),
        ),
      );
      await t.tap(find.text('abrir'));
      await t.pumpAndSettle();
      expect(find.textContaining('o projeto está em 120 BPM, 6/8'), findsOneWidget);
      expect(find.textContaining('3/4'), findsOneWidget, reason: 'é o compasso do arquivo');
      expect(find.textContaining('o projeto está em 120 BPM, 3/4'), findsNothing);
      await t.tap(find.text('Manter o do projeto'));
      await t.pumpAndSettle();
    });

    testWidgets('a lista de tempos por compasso vai a 32/4 e mostra o valor atual', (t) async {
      final c = studio();
      c.doc.beatsPerBar = 13;
      await mount(t, c, const Size(1400, 900));
      await t.tap(find.textContaining('BPM · 13/4'));
      await t.pumpAndSettle();
      expect(find.text('13/4'), findsOneWidget, reason: 'o valor atual está selecionado na lista');
      await t.tap(find.text('13/4'));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(find.text('32/4'), 60, scrollable: find.byType(Scrollable).last);
      expect(find.text('32/4'), findsOneWidget, reason: 'a lista vai até o limite do documento');
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      await t.tap(find.text('Cancelar'));
      await t.pumpAndSettle();
      await flushSave(t);
    });
  });

  group('piano roll: encaixe que colide', () {
    mac('Prender seleção na escala e Inverter na altura descartam a nota que cairia em cima de outra', (t) async {
      t.view.physicalSize = const Size(1200, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      Future<void> open(List<String> path) async {
        await t.tap(find.text('Ferramentas'));
        await t.pumpAndSettle();
        for (final label in path) {
          await t.tap(find.text(label).last);
          await t.pumpAndSettle();
        }
      }

      // 61 cairia no 60 que já está lá: sobra uma só
      final c = TestDaw(notes: [MidiNote(pitch: 60, start: 0, length: 1), MidiNote(pitch: 61, start: 0, length: 1)]);
      c.clip.scale = '0:major';
      await t.pumpWidget(host(c, height: 500));
      await t.pump();
      await open(['Escala e acordes', 'Prender seleção na escala']);
      expect([for (final n in c.clip.notes) n.pitch], [60]);
      c.undo();
      await t.pump();
      expect(c.clip.notes.length, 2);

      // inverter na altura com o encaixe ligado: 64,65 espelham em 61,60 e o 61 cai no 60
      final d = TestDaw(notes: [MidiNote(pitch: 60, start: 1, length: 1), MidiNote(pitch: 65, start: 0, length: 1), MidiNote(pitch: 64, start: 0, length: 1)]);
      d.clip.scale = '0:major';
      await t.pumpWidget(host(d, height: 500));
      await t.pump();
      await open(['Escala e acordes', 'Prender na escala']);
      await open(['Escala e acordes', 'Manter o encaixe ao mudar a altura']);
      await open(['Seleção', 'Inverter na altura']);
      expect(d.clip.notes.length, 2, reason: 'a nota duplicada não fica: ${[for (final n in d.clip.notes) (n.pitch, n.start)]}');
      expect({for (final n in d.clip.notes) (n.pitch, n.start)}, {(65, 1.0), (60, 0.0)});
      // limpa as preferências da sessão
      await open(['Escala e acordes', 'Manter o encaixe ao mudar a altura']);
      await open(['Escala e acordes', 'Prender na escala']);
      await settle(t);
    });
  });

  group('cabeçalho: o deslizador de volume tem prioridade sobre o reordenar', () {
    Finder headerSliderOf(WidgetTester t, String trackName) {
      final title = t.getCenter(find.text(trackName));
      final sliders = find.byType(Slider).evaluate().where((e) => e.renderObject is RenderBox).toList();
      // o deslizador do cabeçalho dessa faixa: o mais perto abaixo do nome, na mesma coluna
      sliders.sort((a, b) {
        double d(Element e) {
          final r = e.renderObject! as RenderBox;
          final p = r.localToGlobal(r.size.center(Offset.zero));
          return p.dy < title.dy - 4 || p.dx > 260 ? double.infinity : (p.dy - title.dy);
        }

        return d(a).compareTo(d(b));
      });
      return find.byElementPredicate((e) => identical(e, sliders.first));
    }

    Future<void> hold(WidgetTester t, Offset at, {Offset? drag}) async {
      final g = await t.createGesture(kind: PointerDeviceKind.mouse);
      await g.addPointer(location: at);
      await g.moveTo(at);
      await t.pump();
      await g.down(at);
      await t.pump(const Duration(milliseconds: 700));
      if (drag != null) {
        for (var i = 0; i < 4; i++) {
          await g.moveBy(drag);
          await t.pump(const Duration(milliseconds: 16));
        }
      }
      // o texto do modo reordenar aparece enquanto o dedo segura
      holdReordering = find.textContaining('para a posição').evaluate().isNotEmpty;
      await g.up();
      await t.pump();
      await g.removePointer();
    }

    testWidgets('segurar em cima do deslizador (e a 12 px dele) não liga o reordenar; no resto do cabeçalho liga', (t) async {
      final c = studio();
      addTearDown(c.midiLearn.dispose);
      await mount(t, c, const Size(1400, 900));
      final names = c.doc.tracks.map((x) => x.name).toList();
      final slider = headerSliderOf(t, 'Sampler 1');
      final r = t.getRect(slider);
      // em cima da barra
      await hold(t, r.center, drag: const Offset(0, -20));
      expect(holdReordering, isFalse, reason: 'o toque longo começou no deslizador');
      expect(c.doc.tracks.map((x) => x.name).toList(), names);
      // 12 px acima da barra: ainda é zona do deslizador
      await hold(t, Offset(r.center.dx, r.top - 12));
      expect(holdReordering, isFalse, reason: 'dentro dos ~15 px em volta');
      // o título da faixa: reordena, como sempre
      await hold(t, t.getCenter(find.text('Sampler 1')), drag: const Offset(0, -20));
      expect(holdReordering, isTrue, reason: 'o resto do cabeçalho segue reordenando');
      expect(c.doc.tracks.map((x) => x.name).toList(), ['Áudio 1', 'Sintetizador 1', 'Sampler 1', 'Bateria 1']);
      await flushSave(t);
    });

    testWidgets('arrastar o deslizador continua mudando o volume', (t) async {
      final c = studio();
      addTearDown(c.midiLearn.dispose);
      await mount(t, c, const Size(1400, 900));
      final slider = headerSliderOf(t, 'Sampler 1');
      final r = t.getRect(slider);
      final before = c.doc.tracks[3].gain;
      await t.dragFrom(Offset(r.center.dx, r.center.dy), const Offset(-40, 0));
      await t.pump();
      expect(c.doc.tracks[3].gain, lessThan(before));
      await flushSave(t);
    });
  });
}

bool holdReordering = false;

/// Um .mid de um compasso [nn]/2^[dd] com uma nota de uma batida (480 ticks).
List<int> _meterTrack(int nn, int dd) => [
  0, 0xFF, 0x58, 4, nn, dd, 24, 8, //
  0, 0x90, 60, 100,
  ...vlq(480), 0x80, 60, 0,
  ...eot,
];

MidiFileData _data(int nn, int dd) =>
    MidiFileData(format: 0, ppq: 480, tracks: const [], tempoMap: const [], beatsPerBar: nn, warnings: const [], meterMap: [MeterChange(1, nn, 1 << dd)]);
