// Fase 21: achados de leitura de código da fase 18 (modulação, atalhos e presets). Cada teste confirma o
// defeito e a correção.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart' hide Curve;
import 'package:flutter_test/flutter_test.dart';
import 'package:jopendaw_app/daw/effects.dart';
import 'package:jopendaw_app/daw/instruments.dart';
import 'package:jopendaw_app/daw/keymap.dart';
import 'package:jopendaw_app/daw/keymap_ui.dart';
import 'package:jopendaw_app/daw/midi_learn_ui.dart';
import 'package:jopendaw_app/daw/model.dart';
import 'package:jopendaw_app/daw/modulation_ops.dart';
import 'package:jopendaw_app/daw/user_presets.dart';
import 'package:jopendaw_app/widgets/theme.dart';

import 'fake_engine.dart';

class _ManyBackups extends MemoryUserPresetStorage implements MultiBackupStorage {
  List<String> extra = [];
  @override
  Future<List<String>> readBackups() async => [...extra, ?backup];
}

class _BrokenRead extends _ManyBackups {
  @override
  Future<String?> read() async => throw StateError('sem acesso');
}

Uint8List presetFile(List<Map<String, dynamic>> presets) => Uint8List.fromList(
  utf8.encode(jsonEncode({'format': 'jopendaw-user-presets', 'version': 1, 'presets': presets})),
);

String backupOf(List<String> names) => jsonEncode({
  'format': 'jopendaw-user-presets',
  'version': 1,
  'presets': [
    for (final (i, n) in names.indexed)
      {
        'id': 'p$i',
        'family': 'effect',
        'kind': 'gate',
        'name': n,
        'params': {'0': 0.5},
      },
  ],
});

void main() {
  group('presets', () {
    test('(1) o arquivo principal não abre: restaurar do backup funciona e grava, e o modo só leitura acaba', () async {
      final st = _BrokenRead()..backup = backupOf(['Um', 'Dois']);
      final s = UserPresets(st);
      await s.load();
      expect(s.hasBackup, isTrue);
      expect(s.problem, isNotNull, reason: 'antes de restaurar, os presets não estão sendo guardados');
      final r = await s.restoreFromBackup();
      expect(r.restored, 2);
      expect(s.ofEffect(EffectKind.gate).map((p) => p.name).toSet(), {'Um', 'Dois'});
      await s.flush();
      expect(st.data, isNotNull, reason: 'o que voltou foi gravado');
      expect(jsonDecode(st.data!)['presets'], hasLength(2));
      expect(s.problem, isNull, reason: 'deixou de ser só leitura');
      expect(st.backup, isNotNull, reason: 'a cópia continua lá');
    });

    test('(1) arquivo de versão mais nova continua só leitura: restaurar não sobrescreve', () async {
      final st = _ManyBackups()
        ..data = jsonEncode({'format': 'jopendaw-user-presets', 'version': 99, 'presets': []})
        ..backup = backupOf(['Um']);
      final s = UserPresets(st);
      await s.load();
      await expectLater(s.restoreFromBackup(), throwsA(isA<PresetFormatException>()));
      await s.flush();
      expect(jsonDecode(st.data!)['version'], 99);
    });
  });

  group('atalhos', () {
    test('(2) o aviso de atalho descartado não apaga o de arquivo ilegível: os dois aparecem juntos', () async {
      final st = MemoryKeymapStorage()
        ..data = jsonEncode({
          'format': 'jopendaw-keymap',
          'version': 99,
          'bindings': {
            'panel.mixer': ['B'],
          },
        });
      final km = Keymap(st);
      // antes de o carregamento acabar a sessão já usou a tecla B em outra ação
      km.assign('panel.effects', KeyCombo.parse('B')!, slot: 0);
      await km.load();
      final notice = km.loadNotice ?? '';
      // versão futura: o aviso de arquivo não some por causa do aviso de atalho descartado, os dois aparecem
      expect(notice, contains('mais nova'));
      expect(notice, contains('descartado'));
    });

    test('(3) nenhum tooltip ou rótulo escreve o atalho à mão: sempre pelo Keymap (shortcutHint/shortcutLabel)', () {
      final bad = <String>[];
      final re = RegExp(r'\((Ctrl|Cmd|Mod|Shift|Alt|Option)\+[^)\n]+\)|[\wá-úÁ-Ú\}\)] \(([A-Z]|Delete|Backspace|Esc|Enter|Espaço|Space|Tab|F\d{1,2})\)');
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
        // o catálogo do Keymap é quem define os atalhos: lá o texto é dado, não dica escrita à mão
        if (f.path.endsWith('daw/keymap.dart')) continue;
        final lines = f.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final l = lines[i];
          if (l.trimLeft().startsWith('//')) continue;
          if (re.hasMatch(l)) bad.add('${f.path}:${i + 1}: ${l.trim()}');
        }
      }
      expect(bad, isEmpty, reason: bad.join('\n'));
    });

    testWidgets('(4) "Desfazer importação" continua oferecido ao reabrir a tela Personalizar', (t) async {
      final km = Keymap(MemoryKeymapStorage());
      km.assign('panel.mixer', KeyCombo.parse('B')!, slot: 0);
      final bytes = Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'format': 'jopendaw-keymap-file',
            'version': 1,
            'bindings': {
              'panel.effects': ['G'],
            },
          }),
        ),
      );
      km.importBytes(bytes);
      expect(km.canUndoImport, isTrue);
      Future<void> open() async {
        t.view.physicalSize = const Size(800, 900);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        await t.pumpWidget(
          MaterialApp(
            theme: buildTheme(),
            home: Scaffold(body: SingleChildScrollView(child: KeymapEditor(keymap: km))),
          ),
        );
        await t.pumpAndSettle();
      }

      await open();
      expect(find.text('Desfazer importação'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      await open(); // "fechou" e abriu de novo
      expect(find.text('Desfazer importação'), findsOneWidget);
      await t.tap(find.text('Desfazer importação'));
      await t.pumpAndSettle();
      expect(km.canUndoImport, isFalse);
      expect(km.bindingsOf('panel.mixer').map((c) => c.toString()), ['B']);
    });

    testWidgets('(6) a confirmação da importação fala no singular e no plural', (t) async {
      t.view.physicalSize = const Size(800, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final file = Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'format': 'jopendaw-keymap-file',
            'version': 1,
            'bindings': {
              'panel.effects': ['G'],
            },
          }),
        ),
      );
      for (final (n, expected) in [(0, 'Você não tem personalizações agora.'), (1, 'A sua personalização atual será descartada.'), (2, 'As suas 2 personalizações atuais serão descartadas.')]) {
        final km = Keymap(MemoryKeymapStorage());
        if (n >= 1) km.assign('panel.mixer', KeyCombo.parse('B')!, slot: 0);
        if (n >= 2) km.assign('panel.editor', KeyCombo.parse('N')!, slot: 0);
        expect(km.planImport(file).replacing, n);
        await t.pumpWidget(
          MaterialApp(
            theme: buildTheme(),
            home: Scaffold(
              body: SingleChildScrollView(
                child: KeymapEditor(keymap: km, pick: () async => ('a.jokeys', file)),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        await t.ensureVisible(find.byKey(const ValueKey('keymap-import')));
        await t.tap(find.byKey(const ValueKey('keymap-import')));
        await t.pumpAndSettle();
        expect(find.textContaining(expected), findsOneWidget, reason: '$n');
        await t.tap(find.byKey(const ValueKey('keymap-import-cancel')));
        await t.pumpAndSettle();
      }
    });
  });

  group('modulação', () {
    test('(5) a dica do fader/pan sai das ações do menu: só cita "Modular…" quando o menu a tem', () {
      final c = fakeController(
        FakeEngine(),
        tracks: [
          DawTrack(id: 'a', name: 'A', color: 0),
        ],
      );
      addTearDown(c.dispose);
      const volume = AutoTarget(AutoKind.volume);
      final hint = midiLearnMenuHint(c, 0, volume);
      expect(c.canModulate(0, volume), isTrue);
      expect(hint, 'Aprender MIDI, Modular…, Mapeamentos MIDI…');
      // com um mapeamento, o "Remover mapeamento" entra sem o texto do aparelho
      c.midiLearn.arm(0, volume);
      c.midiLearn.handle(0xB0, 7, 64);
      expect(midiLearnMenuHint(c, 0, volume), contains('Remover mapeamento'));
      expect(midiLearnMenuHint(c, 0, volume), isNot(contains('(')));
    });

    test('(7) apagar o modulador 1 de dois LFOs não faz o 2 herdar o índice (nem a fase) do motor', () {
      final e = FakeEngine();
      final c = fakeController(
        e,
        tracks: [
          DawTrack(id: 'a', name: 'Áudio 1', color: 0),
          DawTrack(id: 's', name: 'Sintetizador', color: 1, kind: TrackKind.synth),
        ],
      );
      addTearDown(c.dispose);
      c.mutate((_) {});
      const cutoff = AutoTarget(AutoKind.instrument, param: 13);
      const pan = AutoTarget(AutoKind.pan);
      expect(c.modAssign(1, cutoff), isNull);
      final a = c.modulation(1).sources.single.id;
      expect(c.modAssign(1, pan), isNull);
      final b = c.modulation(1).sources.last.id;
      expect(a, isNot(b));
      List<List<Object>> sources() => [
        for (final x in e.log!)
          if (x.first == 'mod_source') x,
      ];
      e.log = [];
      c.modRemoveSource(1, a);
      // o que sobrou é o `b` e continua no índice 1 (o que o motor já tinha para ele): nada herda a fase do `a`
      expect(c.modulation(1).sources.map((s) => s.id), [b]);
      // o destino do `a` saiu junto; o do `b` (pan) foi reenviado
      final sent = sources();
      expect(sent, hasLength(1));
      expect(sent.single[2], 1, reason: 'índice estável do motor');
      // um modulador novo ocupa o índice livre (o 0), nunca o do que ficou
      e.log = [];
      expect(c.modAssign(1, cutoff), isNull);
      expect({for (final s in sources()) s[2]}, {0, 1});
    });
  });
}
