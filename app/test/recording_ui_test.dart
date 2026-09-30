// A interface da gravação e da exportação (fase 4) com um controlador de mentira por baixo: o que
// se testa é a tela chamar o contrato certo (gravar, armar, monitorar, entrada, exportar) e aguentar
// os estados (gravando, contando, erro, 360 px), não o motor nem a gravação em si.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jopendaw_app/audio/engine.dart';
import 'package:jopendaw_app/daw/controller.dart';
import 'package:jopendaw_app/daw/export.dart';
import 'package:jopendaw_app/daw/export_options.dart';
import 'package:jopendaw_app/daw/instruments.dart';
import 'package:jopendaw_app/daw/mixer_panel.dart';
import 'package:jopendaw_app/daw/model.dart';
import 'package:jopendaw_app/daw/settings_dialog.dart';
import 'package:jopendaw_app/models/project.dart';
import 'package:jopendaw_app/screens/project_screen.dart';
import 'package:jopendaw_app/widgets/theme.dart';

final engine = AudioEngine.instance;

/// O controlador de verdade com as ações da fase 4 trocadas por registros.
class FakeDaw extends DawController {
  FakeDaw()
    : super(
        Project.fromJson({
          'id': 'p',
          'name': 'Teste',
          'bpm': 120,
          'beats_per_bar': 4,
          'beat_unit': 4,
          'sample_rate': 48000,
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-01-01T00:00:00Z',
        }),
      ) {
    doc = DawDoc(
      bpm: 120,
      beatsPerBar: 4,
      loopStart: 4,
      loopEnd: 12,
      tracks: [
        DawTrack(id: 'a', name: 'Voz', color: 0),
        DawTrack(
          id: 's',
          name: 'Sintetizador 1',
          color: 1,
          kind: TrackKind.synth,
          midi: [
            MidiClip(id: 'm1', start: 0, length: 16, notes: [MidiNote(pitch: 60, start: 0, length: 1)]),
          ],
        ),
        DawTrack(id: 'b', name: 'Reverb', color: 2, kind: TrackKind.bus),
      ],
    );
    ready = true;
  }

  final calls = <String>[];

  /// Redesenha como se o controlador tivesse mudado de estado (gravando, contando).
  void poke() => notifyListeners();

  List<(String, String)> devices = const [('default', 'Microfone embutido'), ('usb', 'Interface USB'), ('x', '')];
  Object? recordError, refreshError, exportError;
  ExportOptions? exported;

  /// Segura o render no meio, para o teste olhar o diálogo de progresso.
  Completer<void>? exportGate;

  /// Como o controlador de verdade falha: o motivo vai para `error`, sem lançar.
  String? exportFailure;

  @override
  void cancelRender() {
    calls.add('cancel');
    if (!(exportGate?.isCompleted ?? true)) exportGate!.complete();
  }

  @override
  Future<void> toggleRecord() async {
    calls.add('record');
    if (recordError != null) throw recordError!;
    recording = !recording;
    countingIn = false;
    notifyListeners();
  }

  @override
  void setArmed(int track, bool on) {
    calls.add('arm $track $on');
    mutate((d) => d.tracks[track].armed = on);
  }

  @override
  void setMonitor(int track, bool on) {
    calls.add('monitor $track $on');
    mutate((d) => d.tracks[track].monitor = on);
  }

  @override
  Future<void> refreshInputDevices() async {
    calls.add('refresh');
    if (refreshError != null) throw refreshError!;
    inputDevices = devices;
    notifyListeners();
  }

  @override
  Future<void> setInputDevice(String? id) async {
    calls.add('device $id');
    inputDevice = id;
    notifyListeners();
  }

  @override
  Future<void> exportAudio(ExportOptions options, {void Function(double progress)? onProgress, Future<void> Function(String name, Uint8List wav)? sink}) async {
    exported = options;
    onProgress?.call(0.25);
    await exportGate?.future;
    // cancelado: termina quieto, como o de verdade
    if (calls.contains('cancel')) return;
    if (exportFailure != null) {
      error = exportFailure;
      notifyListeners();
      return;
    }
    onProgress?.call(1);
    if (exportError != null) throw exportError!;
  }
}

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

/// Deixa passar o salvamento adiado do controlador e a luz de saturação do medidor.
Future<void> settle(WidgetTester t) => t.pump(const Duration(seconds: 3));

/// Toca num botão que pode estar fora da vista: na barra do transporte (rola na horizontal) ou
/// num diálogo rolando no celular.
Future<void> tapVisible(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pump();
  await t.tap(f);
}

Finder semantic(String label) => find.byWidgetPredicate((w) => w is Semantics && w.properties.label == label);

List<List<Object>> sent(String name) => [
  for (final c in engine.log!)
    if (c.first == name) c,
];

void main() {
  setUp(() => engine.log = []);

  for (final (label, size) in [('computador', const Size(1400, 900)), ('celular de 360 px', const Size(360, 740))]) {
    testWidgets('$label: gravar na barra, armar/monitorar e medidor de entrada no mixer, sem estouro', (t) async {
      final c = FakeDaw();
      c.doc.tracks[0]
        ..armed = true
        ..monitor = true;
      c.doc.tracks[1].armed = true;
      await mount(t, c, size);
      c.setDock(Dock.mixer);
      await t.pump();
      expect(t.takeException(), isNull);

      // armar nas faixas de áudio e de instrumento; monitorar só na de áudio; barramento nenhum
      expect(semantic('Armar para gravar'), findsNWidgets(2));
      expect(semantic('Monitorar a entrada'), findsOneWidget);
      // o medidor de entrada só na faixa de áudio armada (na de instrumento entram notas)
      expect(find.byType(InputLevelMeter), findsOneWidget);

      // nível subindo até saturar: a luz acende e apaga sozinha
      for (final v in [0.1, 0.5, 1.0, 0.3, 0.0]) {
        c.inputLevel.value = v;
        await t.pump(const Duration(milliseconds: 30));
      }
      expect(t.takeException(), isNull);

      // contando (pisca) e gravando (aceso)
      c.recording = true;
      c.countingIn = true;
      c.poke();
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      await t.pump(const Duration(milliseconds: 300));
      c.countingIn = false;
      c.poke();
      await t.pump();
      expect(t.takeException(), isNull);
      c.recording = false;
      c.setDock(Dock.none);
      await settle(t);
    });
  }

  testWidgets('armar e monitorar chamam o controlador na faixa certa', (t) async {
    final c = FakeDaw();
    await mount(t, c, const Size(1400, 900));
    c.setDock(Dock.mixer);
    await t.pump();
    await t.tap(semantic('Armar para gravar').first);
    await t.tap(semantic('Monitorar a entrada'));
    await t.pump();
    await t.tap(semantic('Armar para gravar').last);
    expect(c.calls, ['arm 0 true', 'monitor 0 true', 'arm 1 true']);
    await t.pump();
    // armada, a de áudio ganha o medidor de entrada
    expect(find.byType(InputLevelMeter), findsOneWidget);
    await settle(t);
  });

  testWidgets('R grava (também com o teclado musical ligado), Ctrl+R não; espaço e Enter gravando encerram a gravação', (t) async {
    final c = FakeDaw();
    await mount(t, c, const Size(1400, 900));

    await t.sendKeyEvent(LogicalKeyboardKey.keyR);
    expect(c.calls, ['record']);
    expect(c.recording, isTrue);

    // espaço gravando: encerra a gravação; o transporte já parado não volta a tocar
    await t.sendKeyEvent(LogicalKeyboardKey.space);
    await t.pump();
    expect(c.calls, ['record', 'record']);
    expect(c.recording, isFalse);
    expect(sent('play'), isEmpty);

    // Enter gravando: encerra e para
    await t.sendKeyEvent(LogicalKeyboardKey.keyR);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    expect(c.calls, ['record', 'record', 'record', 'record']);
    expect(sent('stop'), isNotEmpty);

    // Ctrl+R é do navegador
    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.keyR);
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(c.calls.length, 4);

    // com o teclado musical ligado, A é nota (no sintetizador) e R continua gravando
    c.selectTrack(1);
    c.toggleKeyboard();
    await t.sendKeyDownEvent(LogicalKeyboardKey.keyA, physicalKey: PhysicalKeyboardKey.keyA);
    await t.sendKeyUpEvent(LogicalKeyboardKey.keyA, physicalKey: PhysicalKeyboardKey.keyA);
    expect(sent('live_on'), isNotEmpty);
    await t.sendKeyEvent(LogicalKeyboardKey.keyR, physicalKey: PhysicalKeyboardKey.keyR);
    expect(c.calls.length, 5);
    expect(c.recording, isTrue);

    // gravando, Ctrl+Z não desfaz
    c.edit((d) => d.tracks[0].name = 'Outra');
    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(c.doc.tracks[0].name, 'Outra');
    await settle(t);
  });

  testWidgets('botão gravar, menu da contagem e falha do gravar na tela', (t) async {
    final c = FakeDaw();
    await mount(t, c, const Size(1400, 900));
    await t.tap(semantic('Gravar'));
    await t.pump();
    expect(c.calls, ['record']);
    await t.tap(semantic('Gravar'));
    await t.pump();

    expect(c.doc.countIn, isTrue);
    await t.tap(find.byTooltip('Opções de gravação'));
    await t.pumpAndSettle();
    // o item inteiro (o texto fica embaixo da área de toque do item)
    await t.tap(find.ancestor(of: find.text('Contagem de um compasso'), matching: find.byWidgetPredicate((w) => w is CheckedPopupMenuItem)));
    await t.pumpAndSettle();
    expect(c.doc.countIn, isFalse);

    // uma falha que o controlador deixa escapar vira aviso, sem o prefixo em inglês
    c.recordError = StateError('Sem acesso ao microfone');
    await t.tap(semantic('Gravar'));
    await t.pump();
    expect(find.text('Sem acesso ao microfone.'), findsOneWidget);
    // parar a gravação que falhou também falha: o parar que deu certo depois não apaga o aviso
    c.recording = true;
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    expect(find.text('Sem acesso ao microfone.'), findsOneWidget);
    // a próxima tentativa que dá certo apaga o aviso velho
    c.recordError = null;
    await t.tap(semantic('Gravar'));
    await t.pump();
    expect(find.text('Sem acesso ao microfone.'), findsNothing);
    await settle(t);
  });

  testWidgets('exportar: loop desligado sem região, progresso, concluído; erro volta às opções com as mesmas escolhas', (t) async {
    final c = FakeDaw();
    await mount(t, c, const Size(1400, 900));
    await tapVisible(t, find.byTooltip('Exportar áudio (WAV, FLAC ou MP3)'));
    await t.pumpAndSettle();
    expect(find.text('Exportar áudio'), findsOneWidget);
    // compassos 1 a 4 (16 batidas a 120 BPM = 8 s) mais a cauda padrão
    expect(find.textContaining('Compassos 1 a 4 · 0:08 + 2 s de cauda'), findsOneWidget);
    await t.tap(find.text('Região do loop'));
    await t.pump();
    expect(find.textContaining('Compassos 2 a 3'), findsOneWidget);
    await t.tap(find.text('Stems'));
    await t.pump();

    c.exportGate = Completer();
    await t.tap(find.widgetWithText(FilledButton, 'Exportar').last);
    await t.pump();
    await t.pump();
    expect(find.text('Exportando…'), findsOneWidget);
    expect(find.text('Renderizando 25%'), findsOneWidget);
    c.exportGate!.complete();
    await t.pumpAndSettle();
    expect(find.text('Exportação concluída'), findsOneWidget);
    expect(c.exported!.stems, isTrue);
    expect(c.exported!.range, ExportRange.loop);
    expect(c.exported!.format, ExportFormat.wav24);
    await t.tap(find.text('Fechar'));
    await t.pumpAndSettle();

    // sem região de loop, a opção fica desligada e volta para a música inteira
    c.mutate((d) => d.loopEnd = d.loopStart);
    c.exportError = Exception('Sem espaço para o arquivo');
    await tapVisible(t, find.byTooltip('Exportar áudio (WAV, FLAC ou MP3)'));
    await t.pumpAndSettle();
    final loop = t.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Região do loop'));
    expect(loop.onSelected, isNull);
    expect(t.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Música inteira')).selected, isTrue);
    await t.tap(find.widgetWithText(FilledButton, 'Exportar').last);
    await t.pumpAndSettle();
    expect(find.text('A exportação falhou'), findsOneWidget);
    expect(find.text('Sem espaço para o arquivo.'), findsOneWidget);
    await t.tap(find.text('Voltar às opções'));
    await t.pumpAndSettle();
    expect(find.text('Exportar áudio'), findsOneWidget);
    expect(t.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, 'Stems')).value, isTrue);
    await t.tap(find.text('Cancelar'));
    await t.pumpAndSettle();
    await settle(t);
  });

  testWidgets('exportar: a falha que o controlador põe em error aparece no diálogo; cancelar fecha sem aviso', (t) async {
    final c = FakeDaw();
    await mount(t, c, const Size(1400, 900));
    c.exportFailure = 'A exportação não terminou: sem memória.';
    await tapVisible(t, find.byTooltip('Exportar áudio (WAV, FLAC ou MP3)'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Exportar').last);
    await t.pumpAndSettle();
    expect(find.text('A exportação falhou'), findsOneWidget);
    expect(find.textContaining('sem memória'), findsOneWidget);
    expect(c.error, isNull, reason: 'mostrado no diálogo, sai da tela de trás');
    await t.tap(find.text('Fechar'));
    await t.pumpAndSettle();

    c.exportFailure = null;
    c.exportGate = Completer();
    await tapVisible(t, find.byTooltip('Exportar áudio (WAV, FLAC ou MP3)'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Exportar').last);
    await t.pump();
    await t.pump();
    expect(find.text('Exportando…'), findsOneWidget);
    // o do progresso, por cima do das opções
    await t.tap(find.widgetWithText(TextButton, 'Cancelar').last);
    await t.pumpAndSettle();
    expect(c.calls, contains('cancel'));
    expect(find.text('Exportando…'), findsNothing);
    expect(find.text('Exportação concluída'), findsNothing);
    expect(find.text('A exportação falhou'), findsNothing);
    await settle(t);
  });

  testWidgets('exportar sem clipes: nada para exportar e o botão desligado', (t) async {
    final c = FakeDaw();
    c.doc.tracks[1].midi.clear();
    await mount(t, c, const Size(360, 740));
    await tapVisible(t, find.byTooltip('Exportar áudio (WAV, FLAC ou MP3)'));
    await t.pumpAndSettle();
    expect(find.textContaining('Não há o que exportar'), findsOneWidget);
    expect(t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Exportar')).onPressed, isNull);
    expect(t.takeException(), isNull);
    await t.tap(find.text('Cancelar'));
    await t.pumpAndSettle();
    await settle(t);
  });

  for (final (label, size) in [('computador', const Size(1400, 900)), ('celular de 360 px', const Size(360, 740))]) {
    testWidgets('$label: configurações listam as entradas, trocam, e a latência e a contagem vão ao documento', (t) async {
      final c = FakeDaw();
      await mount(t, c, size);
      await tapVisible(t, find.byTooltip('Configurações: entrada de áudio, latência e contagem'));
      await t.pumpAndSettle();
      expect(c.calls, ['refresh']);
      expect(t.takeException(), isNull);
      // a padrão do Chrome vira o item "padrão" com o nome do aparelho
      expect(find.text('Padrão (Microfone embutido)'), findsOneWidget);

      await t.tap(find.text('Padrão (Microfone embutido)'));
      await t.pumpAndSettle();
      // sem permissão os nomes vêm vazios: numerado
      expect(find.text('Entrada 2').last, findsOneWidget);
      await t.tap(find.text('Interface USB').last);
      await t.pumpAndSettle();
      expect(c.calls, ['refresh', 'device usb']);

      // a entrada escolhida sumiu da lista: aparece como desconectada, sem derrubar o seletor
      c.devices = const [('default', 'Microfone embutido')];
      await t.tap(find.byTooltip('Procurar as entradas de novo (depois de conectar um microfone ou interface)'));
      await t.pumpAndSettle();
      expect(find.text('Entrada desconectada'), findsOneWidget);
      expect(t.takeException(), isNull);

      await t.enterText(find.byType(TextField), '35');
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pump();
      expect(c.doc.recLatencyMs, 35);
      await t.enterText(find.byType(TextField), '900');
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pump();
      expect(find.text('De -200 a 500 ms'), findsOneWidget);
      expect(c.doc.recLatencyMs, 35);
      await t.enterText(find.byType(TextField), '-12');
      await tapVisible(t, find.text('Contagem de um compasso'));
      await t.pump();
      expect(c.doc.countIn, isFalse);
      // fechar leva o número digitado junto
      await t.tap(find.text('Fechar'));
      await t.pumpAndSettle();
      expect(c.doc.recLatencyMs, -12);
      expect(find.byType(SettingsDialog), findsNothing);
      await settle(t);
    });
  }

  testWidgets('configurações: sem permissão do microfone, o motivo aparece na janela', (t) async {
    final c = FakeDaw()..refreshError = UnsupportedError('O navegador negou o microfone');
    await mount(t, c, const Size(1400, 900));
    await tapVisible(t, find.byTooltip('Configurações: entrada de áudio, latência e contagem'));
    await t.pumpAndSettle();
    expect(find.text('O navegador negou o microfone.'), findsOneWidget);
    expect(find.text('Padrão do sistema'), findsOneWidget);
    await t.tap(find.text('Fechar'));
    await t.pumpAndSettle();
    await settle(t);
  });

  testWidgets('diálogo de exportar sozinho: cabe em 360 px com todas as opções', (t) async {
    t.view.physicalSize = const Size(360, 640);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final c = FakeDaw();
    await t.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(onPressed: () => showExportDialog(context, c), child: const Text('abrir')),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('abrir'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    await t.tap(find.text('WAV 24 bits'));
    await t.pumpAndSettle();
    await t.tap(find.text('WAV 32 bits float').last);
    await t.pumpAndSettle();
    expect(find.textContaining('Sem perda nenhuma'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
