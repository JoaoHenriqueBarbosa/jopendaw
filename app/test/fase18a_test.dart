// Fase 18, item A: correções de modulação, atalhos personalizáveis e presets do usuário (cada teste confirma o defeito
// achado por leitura de código e a correção).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show TargetPlatform, debugDefaultTargetPlatformOverride;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Curve;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jopendaw_app/daw/controller.dart';
import 'package:jopendaw_app/daw/dock.dart';
import 'package:jopendaw_app/daw/effects.dart';
import 'package:jopendaw_app/daw/instruments.dart';
import 'package:jopendaw_app/daw/keymap.dart';
import 'package:jopendaw_app/daw/knob.dart';
import 'package:jopendaw_app/daw/midi_learn_ui.dart';
import 'package:jopendaw_app/daw/model.dart';
import 'package:jopendaw_app/daw/shortcuts_dialog.dart';
import 'package:jopendaw_app/daw/user_presets.dart';
import 'package:jopendaw_app/widgets/theme.dart';

import 'fake_engine.dart';
import 'studio_test.dart' show flushSave, mount, studio;

KeyCombo k(String s) => KeyCombo.parse(s)!;

/// Guardado de atalhos com leitura lenta: o `load` demora até o teste soltar.
class _SlowKeymapStorage extends MemoryKeymapStorage {
  final gate = Completer<void>();
  @override
  Future<String?> read() async {
    await gate.future;
    return data;
  }
}

/// Guardado de presets com as cópias extras `.bak.<ms>`.
class _ManyBackups extends MemoryUserPresetStorage implements MultiBackupStorage {
  List<String> extra = [];
  @override
  Future<List<String>> readBackups() async => [...extra, ?backup];
}

class _BrokenRead extends _ManyBackups {
  @override
  Future<String?> read() async => throw StateError('sem acesso');
}

void main() {
  group('modulação', () {
    test('(6) ir de Efeitos a Modulação (e volta) mantém a faixa à vista, também o master', () {
      final c = fakeController(
        FakeEngine(),
        tracks: [
          DawTrack(id: 'a', name: 'A', color: 0),
          DawTrack(id: 'b', name: 'B', color: 1),
        ],
      );
      c.selectTrack(1);
      c.showEffects(-1);
      expect(c.effectsTrack, -1);
      showDock(c, Dock.modulation);
      expect(c.dock, Dock.modulation);
      expect(c.effectsTrack, -1, reason: 'o master aberto pelo rack continua');
      showDock(c, Dock.effects);
      expect(c.dock, Dock.effects);
      expect(c.effectsTrack, -1);
      // de outro painel, abre pela seleção como antes
      showDock(c, Dock.mixer);
      showDock(c, Dock.modulation);
      expect(c.effectsTrack, 1);
      c.dispose();
    });

    testWidgets('(4) toque longo no fader/pan abre o menu com "Modular…" e o tooltip do knob o cita', (t) async {
      final c = fakeController(
        FakeEngine(),
        tracks: [DawTrack(id: 'a', name: 'A', color: 0)],
      );
      addTearDown(c.dispose);
      const volume = AutoTarget(AutoKind.volume);
      await t.pumpWidget(
        MaterialApp(
          theme: buildTheme(),
          home: Scaffold(
            body: Center(
              child: MidiLearnControl(
                c: c,
                track: 0,
                target: volume,
                secondaryMenu: true,
                child: const SizedBox(width: 60, height: 120, child: ColoredBox(color: Colors.grey)),
              ),
            ),
          ),
        ),
      );
      final g = await t.startGesture(t.getCenter(find.byType(ColoredBox).last), kind: PointerDeviceKind.touch);
      await t.pump(const Duration(milliseconds: 700));
      await g.up();
      await t.pumpAndSettle();
      expect(find.text('Modular…'), findsOneWidget);
      expect(find.text('Aprender MIDI'), findsOneWidget);
      // o item "Mapeamentos MIDI…" estoura na fonte larga dos testes (Ahem); não é do que se testa aqui
      t.takeException();
      await t.tapAt(const Offset(2, 2));
      await t.pumpAndSettle();

      // o knob lista as entradas do menu na dica
      await t.pumpWidget(
        MaterialApp(
          theme: buildTheme(),
          home: Scaffold(
            body: Center(
              child: Knob(
                spec: synthParams.firstWhere((p) => p.name == 'Corte'),
                value: 2400,
                onChanged: (_) {},
                extraActions: () => midiLearnActions(c, 0, const AutoTarget(AutoKind.volume)),
              ),
            ),
          ),
        ),
      );
      final tip = t.widget<Tooltip>(find.byType(Tooltip).first).message!;
      expect(tip, contains('Modular…'));
      expect(tip, contains('toque longo'));
      expect(tip, isNot(contains('Remover mapeamento')));
    });
  });

  group('atalhos', () {
    test('(1) as dicas saem do Keymap: personalizar muda o texto; sem atalho some o parêntese', () {
      final old = Keymap.instance;
      final km = Keymap(MemoryKeymapStorage());
      Keymap.instance = km;
      addTearDown(() => Keymap.instance = old);
      expect(shortcutHint('transport.loop'), ' (L)');
      expect(shortcutHint('transport.stop'), contains('Enter'));
      km.assign('transport.loop', k('B'), slot: 0);
      expect(shortcutHint('transport.loop'), ' (B)');
      km.removeBinding('transport.loop', 0);
      expect(shortcutHint('transport.loop'), '');
      expect(shortcutLabel('transport.loop'), '');
      // tooltip do teclado do computador
      expect(keyboardTooltip(on: false, octave: 4, velocityPercent: 80), endsWith('(${modKeyLabelOf('kbd.toggle')})'));
      km.removeBinding('kbd.toggle', 0);
      expect(keyboardTooltip(on: false, octave: 4, velocityPercent: 80), isNot(contains('(')));
      expect(keyboardTooltip(on: true, octave: 4, velocityPercent: 80), contains('Desligue pelo botão'));
      expect(keyboardTooltip(on: true, octave: 4, velocityPercent: 80), contains('Shift+L toca a nota L'));
    });

    test('(1) nenhum texto de dica escrito à mão com a tecla padrão fica nos widgets', () {
      // os lugares que já foram trocados por shortcutHint: se alguém voltar a escrever "(L)" à mão, quebra aqui
      final hand = RegExp(r"'[^']*(Loop|Metrônomo|Mixer|Fechar o painel|Punch) \((L|C|X|Esc|P)\)");
      for (final f in ['transport_bar.dart', 'dock.dart', 'structure_menu.dart']) {
        final src = File('lib/daw/$f').readAsStringSync();
        expect(hand.hasMatch(src), isFalse, reason: f);
      }
    });

    test('(2) uma mudança antes do load não sobrescreve o guardado; e a sessão vence conflito', () async {
      final st = _SlowKeymapStorage()
        ..data = jsonEncode({
          'format': 'jopendaw-keymap',
          'version': 1,
          'bindings': {
            'panel.effects': ['G'],
            'panel.instrument': ['B'],
          },
        });
      final km = Keymap(st);
      // antes do load acabar, a pessoa põe B no mixer (o guardado põe B no instrumento: conflito na mesma camada)
      km.assign('panel.mixer', k('B'), slot: 0);
      await Future<void>.delayed(Duration.zero);
      expect(st.data, contains('panel.effects'), reason: 'nada gravado por cima antes do carregamento');
      st.gate.complete();
      await km.load();
      await km.flush();
      expect(km.bindingsOf('panel.mixer'), [k('B')]);
      expect(km.bindingsOf('panel.effects'), [k('G')], reason: 'o guardado que não conflita entra');
      expect(km.bindingsOf('panel.instrument'), isNot(contains(k('B'))), reason: 'o guardado que conflita com a sessão sai');
      expect(km.loadNotice, contains('descartado'));
      final saved = jsonDecode(st.data!)['bindings'] as Map;
      expect(saved['panel.effects'], ['G']);
      expect(saved['panel.mixer'], ['B']);
      // nenhuma combinação em duas ações da mesma camada
      final seen = <KeyCombo>{};
      for (final a in keyCatalog.where((a) => !a.fixed && a.context == KeyContext.global)) {
        for (final c in km.bindingsOf(a.id)) {
          expect(seen.add(c), isTrue, reason: '${c.label} repetida');
        }
      }
    });

    test('(3) toda ação do catálogo tem tratamento nos switches das telas', () {
      final s0 = [
        'lib/screens/project_screen.dart',
        'lib/daw/piano_roll_input.dart',
        'lib/daw/controller.dart',
      ].map((f) => File(f).readAsStringSync()).join('\n');
      String body(String path, String from, String to) {
        final src = File(path).readAsStringSync();
        final i = src.indexOf(from);
        expect(i, greaterThanOrEqualTo(0), reason: '$path: $from');
        final j = src.indexOf(to, i);
        expect(j, greaterThan(i), reason: '$path: $to');
        return src.substring(i, j);
      }

      final idPattern = RegExp(r"'([a-z]+\.[A-Za-z]+)'");
      Set<String> ids(String text) => {for (final m in idPattern.allMatches(text)) m.group(1)!};
      // camada geral e arranjo: _actionFor da tela do projeto
      final screen = ids(body('lib/screens/project_screen.dart', 'void Function()? _actionFor', '/// Teclas da tela, em camadas'));
      // piano roll: _handleKey do editor
      final roll = ids(
        body(
          'lib/daw/piano_roll_input.dart',
          'bool _handleKey(KeyEvent e)',
          '  // ------------------------------------------------------------------ comandos',
        ),
      );
      // teclado tocando: handleNoteKey do controlador
      final playing = ids(
        body('lib/daw/controller.dart', 'bool handleNoteKey(KeyEvent e)', '// ------------------------------------------------------------------ MIDI'),
      );
      final missing = <String>[];
      for (final a in keyCatalog) {
        final handled = switch (a.context) {
          KeyContext.global || KeyContext.arrangement => screen,
          KeyContext.pianoRoll => roll,
          KeyContext.playing => playing,
        };
        if (!handled.contains(a.id)) missing.add('${a.id} (${a.context.label})');
      }
      expect(missing, isEmpty, reason: 'ações no catálogo sem `case` que as trate: a tecla apareceria e não faria nada');
      // e o inverso: nenhum `case` de id que o catálogo desconhece
      // (só os `case`: comparações como `startsWith('pr.bar')` não são ids)
      final cases = RegExp(r"case [^:]*:").allMatches(s0).map((m) => m.group(0)!).join('\n');
      for (final id in ids(cases)) {
        expect(keyActionById(id), isNotNull, reason: 'o switch trata "$id", que não está no catálogo');
      }
    });

    test('(4) importar guarda o instantâneo e desfazer volta; outra mudança o descarta', () {
      final km = Keymap(MemoryKeymapStorage());
      km.assign('panel.mixer', k('B'), slot: 0);
      final file = utf8.encode(
        jsonEncode({
          'format': 'jopendaw-keymap-file',
          'version': 1,
          'bindings': {
            'panel.effects': ['G'],
          },
        }),
      );
      final plan = km.planImport(Uint8List.fromList(file));
      expect((plan.incoming, plan.replacing), (1, 1));
      expect(km.bindingsOf('panel.effects'), [k('F')], reason: 'planejar não aplica');
      km.applyImport(plan);
      expect(km.bindingsOf('panel.mixer'), [k('X')]);
      expect(km.canUndoImport, isTrue);
      expect(km.undoImport(), isTrue);
      expect(km.bindingsOf('panel.mixer'), [k('B')]);
      expect(km.bindingsOf('panel.effects'), [k('F')]);
      km.applyImport(plan);
      km.assign('panel.editor', k('N'), slot: 0);
      expect(km.canUndoImport, isFalse, reason: 'mudar outra coisa depois descarta o instantâneo');
    });

    test('(5) Shift+/ vale como ?, com aviso no arquivo', () {
      expect(k('Shift+/'), k('?'));
      expect(k('Shift+/').shift, isFalse);
      final km = Keymap(MemoryKeymapStorage());
      final r = km.importBytes(
        Uint8List.fromList(
          utf8.encode(
            jsonEncode({
              'format': 'jopendaw-keymap-file',
              'version': 1,
              'bindings': {
                'help.shortcuts': ['Shift+/'],
              },
            }),
          ),
        ),
      );
      expect(r.warnings.any((w) => w.contains('Shift+/')), isTrue);
      // o teclado manda Shift+/ como o caractere ?: agora dispara a ação
      final s = KeyCombo.fromKey(LogicalKeyboardKey.slash, character: '?', shift: true)!;
      expect(km.resolve(s, KeyContext.global).map((a) => a.id), contains('help.shortcuts'));
    });

    test('(7) sem atalho no liga/desliga do teclado, a janela não escreve "Sem atalho liga"', () {
      final km = Keymap(MemoryKeymapStorage());
      km.removeBinding('kbd.toggle', 0);
      final groups = shortcutGroups(km);
      final titles = groups.map((g) => g.$1).toList();
      expect(titles.any((t) => t.contains('Sem atalho')), isFalse);
      expect(titles, contains('Teclado do computador'));
      final all = groups.expand((g) => g.$2).map((r) => r.$2).join('\n');
      expect(all, isNot(contains('Sem atalho desliga')));
      expect(all, contains('desliga pelo botão da barra'));
      // com atalho, como antes
      expect(shortcutGroups(Keymap(MemoryKeymapStorage())).map((g) => g.$1), contains(startsWith('Teclado do computador (')));
    });

    test('(8) a janela diz que o Shift não muda a tecla de nota', () {
      final rows = shortcutGroups(Keymap(MemoryKeymapStorage())).expand((g) => g.$2).toList();
      expect(rows.any((r) => r.$1 == 'Com Shift' && r.$2.contains('Shift+L toca a nota L')), isTrue);
    });

    test('(9) o rótulo das teclas por posição segue o layout aprendido', () {
      final h = KeyboardLayoutHints.instance..reset();
      addTearDown(h.reset);
      expect(h.labelFor('Z'), 'Z');
      expect(h.differsFromQwerty, isFalse);
      // layout AZERTY: a tecla física do Z produz W? (aqui: a do A produz Q)
      h.learn(PhysicalKeyboardKey.keyA, LogicalKeyboardKey.keyQ);
      expect(h.labelFor('A'), 'Q (posição do A)');
      expect(h.differsFromQwerty, isTrue);
      final km = Keymap(MemoryKeymapStorage());
      h.learn(PhysicalKeyboardKey.keyB, LogicalKeyboardKey.keyN);
      km.assign('kbd.octaveDown', k('B'), slot: 0);
      expect(km.labelOf('kbd.octaveDown'), 'N (posição do B)', reason: 'a tecla física B tem a letra N neste layout');
      // ação que não é por posição não muda
      expect(km.labelOf('transport.loop'), 'L');
      final rows = shortcutGroups(km).expand((g) => g.$2).toList();
      expect(rows.any((r) => r.$1 == 'Por posição'), isTrue);
    });

    test('(6) o aviso de teclado físico só no celular sem tecla vista', () {
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(shortcutsNeedKeyboardHint(false), isTrue);
      expect(shortcutsNeedKeyboardHint(true), isFalse);
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      expect(shortcutsNeedKeyboardHint(false), isFalse);
    });
  });

  group('presets do usuário', () {
    const kind = 'gate';
    Map<int, double> values() => UserPresets.capture(PresetFamily.effect, kind, (i) => 0);
    UserPreset mk(String id, String name) => UserPreset(id: id, family: PresetFamily.effect, kind: kind, name: name, values: values());
    String file(List<UserPreset> ps) => jsonEncode({
      'format': 'jopendaw-user-presets',
      'version': 1,
      'presets': [for (final p in ps) p.toJson()],
    });

    test('(1) restaurar separa os que já existiam dos que passariam do limite por tipo', () async {
      final st = _ManyBackups()..backup = file([mk('a', 'Um'), mk('b', 'Dois'), mk('c', 'Três')]);
      final s = UserPresets(st);
      await s.load();
      s.save(PresetFamily.effect, kind, 'Dois', values());
      // enche o tipo até 1 vaga antes do limite: entra um e o outro passa do limite
      for (var i = 0; s.of(PresetFamily.effect, kind).length < maxUserPresetsPerKind - 1; i++) {
        s.save(PresetFamily.effect, kind, 'cheio $i', values());
      }
      final r = await s.restoreFromBackup();
      expect((r.restored, r.duplicates, r.overLimit), (1, 1, 1));
      expect(r.skipped, 2);
    });

    test('(1) hasBackup vale mesmo quando a leitura do arquivo principal falha', () async {
      final st = _BrokenRead()..backup = file([mk('a', 'Um')]);
      final s = UserPresets(st);
      await s.load();
      expect(s.loadNotice, isNotNull);
      expect(s.hasBackup, isTrue);
    });

    test('(1) restaurar lê também as cópias extras, da mais recente para a mais antiga', () async {
      final st = _ManyBackups()
        ..backup = file([mk('a', 'Velho'), mk('z', 'Igual')])
        ..extra = [
          file([mk('b', 'Novo'), mk('y', 'Igual')]),
        ];
      final s = UserPresets(st);
      await s.load();
      expect(s.hasBackup, isTrue);
      final r = await s.restoreFromBackup();
      expect(r.copies, 2);
      expect(r.restored, 3);
      expect(r.duplicates, 1, reason: '"Igual" aparece nas duas cópias: entra a mais recente');
      expect(s.ofEffect(EffectKind.gate).map((p) => p.name).toSet(), {'Velho', 'Novo', 'Igual'});
    });
  });

  group('avisos', () {
    testWidgets('(2) o aviso informativo some sozinho em 6 s e o novo tem o seu tempo', (t) async {
      final c = studio();
      addTearDown(c.dispose);
      await mount(t, c, const Size(1400, 900));
      c.notice = 'Não há crossfade a aplicar.';
      c.mutate((_) {});
      await t.pump();
      expect(find.text('Não há crossfade a aplicar.'), findsOneWidget);
      await t.pump(const Duration(seconds: 5));
      expect(find.text('Não há crossfade a aplicar.'), findsOneWidget);
      c.notice = 'Outro aviso';
      c.mutate((_) {});
      await t.pump();
      await t.pump(const Duration(seconds: 5));
      expect(find.text('Outro aviso'), findsOneWidget, reason: 'o tempo recomeça a cada aviso');
      await t.pump(const Duration(seconds: 2));
      expect(c.notice, isNull);
      expect(find.text('Outro aviso'), findsNothing);
      await flushSave(t);
    });
  });
}

/// O rótulo do atalho de [id] (o `modKey` já vem dentro dele).
String modKeyLabelOf(String id) => Keymap.instance.labelOf(id);
