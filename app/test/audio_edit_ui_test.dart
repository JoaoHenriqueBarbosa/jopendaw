import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jopendaw_app/daw/audio_edit_ui.dart';
import 'package:jopendaw_app/daw/controller.dart';
import 'package:jopendaw_app/daw/model.dart';

import 'audio_edit_test.dart' as core;

Future<void> setView(WidgetTester t, double w, double h) async {
  t.view.physicalSize = Size(w, h);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
}

/// Abre o diálogo [open] sobre um app de 360 px (opcionalmente com texto ampliado).
Future<void> host(WidgetTester t, DawController c, Future<void> Function(BuildContext) open, {double textScale = 1}) async {
  await t.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(onPressed: () => open(context), child: const Text('abrir')),
          ),
        ),
      ),
    ),
  );
  await t.tap(find.text('abrir'));
  await t.pumpAndSettle();
}

/// Controladores do teste em andamento: soltos no fim (o salvamento agendado não pode ficar pendente).
final open = <DawController>[];

void uiTest(String name, Future<void> Function(WidgetTester t) body) => testWidgets(name, (t) async {
  await body(t);
  await t.pumpWidget(const SizedBox());
  for (final c in open) {
    c.dispose();
  }
  open.clear();
});

Future<(DawController, String)> project(WidgetTester t, {bool reverse = false, Float32List? x}) async {
  final (c, hash) = await core.setup(x ?? core.drums([0.02, 0.27, 0.485, 0.78, 1.03, 1.235, 1.53, 1.79], seconds: 2.2));
  open.add(c);
  if (reverse) c.setClipWarp('c1', reverse: true);
  await t.pump();
  return (c, hash);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final scale in [1.0, 1.4]) {
    group('360 px, texto ${scale}x', () {
      uiTest('dividir por transientes: sem overflow em cada modo e aplica numa edição só', (t) async {
        await setView(t, 360, 640);
        final (c, _) = await project(t);
        await host(t, c, (ctx) => showSplitTransientsDialog(ctx, c, 'c1'), textScale: scale);
        expect(t.takeException(), isNull);
        expect(find.textContaining('fatias, com emendas'), findsOneWidget);
        for (final label in ['N fatias iguais', 'Na grade', 'Por transientes']) {
          await t.tap(find.text(label));
          await t.pumpAndSettle();
          expect(t.takeException(), isNull, reason: label);
        }
        final json = core.docJson(c);
        await t.ensureVisible(find.text('Dividir'));
        await t.tap(find.text('Dividir'));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(find.textContaining('Dividido em'), findsOneWidget);
        expect(core.clipsOf(c).length, greaterThan(1));
        c.undo();
        expect(core.docJson(c), json);
      });

      uiTest('remover silêncio: sliders, prévia e aplicar', (t) async {
        await setView(t, 360, 640);
        final (c, _) = await project(t, x: core.noiseBursts([(0.5, 0.8), (1.5, 1.9)], 2.5));
        await host(t, c, (ctx) => showStripSilenceDialog(ctx, c, 'c1'), textScale: scale);
        expect(t.takeException(), isNull);
        expect(find.textContaining('trechos'), findsWidgets);
        // mexe num slider e solta: a prévia refaz sem erro
        await t.drag(find.byKey(const Key('strip-threshold')), const Offset(6, 0));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        await t.ensureVisible(find.text('Remover'));
        await t.tap(find.text('Remover'));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(find.textContaining('removidos'), findsOneWidget);
      });

      uiTest('normalizar: mede, mostra o ganho e aplica', (t) async {
        await setView(t, 360, 640);
        final (c, _) = await project(t);
        await host(t, c, (ctx) => showNormalizeClipDialog(ctx, c, 'c1'), textScale: scale);
        expect(t.takeException(), isNull);
        expect(find.byKey(const Key('normalize-gain')), findsOneWidget);
        await t.ensureVisible(find.text('Normalizar').last);
        await t.tap(find.text('Normalizar').last);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(find.textContaining('Ganho do clipe'), findsOneWidget);
        expect(core.clipsOf(c).single.gain, isNot(1.0));
      });

      uiTest('quantizar: grade, força, "manter juntas" e aplicar', (t) async {
        await setView(t, 360, 640);
        final (c, _) = await project(t);
        await host(t, c, (ctx) => showQuantizeSlicesDialog(ctx, c, 'c1'), textScale: scale);
        expect(t.takeException(), isNull);
        await t.tap(find.text('1/8'));
        await t.pumpAndSettle();
        await t.ensureVisible(find.byKey(const Key('quantize-keep')));
        await t.tap(find.byKey(const Key('quantize-keep')));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        await t.ensureVisible(find.text('Quantizar').last);
        await t.tap(find.text('Quantizar').last);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(find.textContaining('movidas'), findsOneWidget);
      });
    });
  }

  uiTest('clipe com inversão: fatiar e quantizar avisam e não aplicam; normalizar vale', (t) async {
    await setView(t, 360, 640);
    final (c, _) = await project(t, reverse: true);
    await host(t, c, (ctx) => showSplitTransientsDialog(ctx, c, 'c1'));
    expect(find.textContaining('warp'), findsOneWidget);
    expect(t.takeException(), isNull);
    final b = t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Dividir'));
    expect(b.onPressed, isNull);
    await t.tap(find.text('Cancelar'));
    await t.pumpAndSettle();

    await host(t, c, (ctx) => showQuantizeSlicesDialog(ctx, c, 'c1'));
    expect(find.textContaining('warp'), findsOneWidget);
    await t.tap(find.text('Cancelar'));
    await t.pumpAndSettle();

    await host(t, c, (ctx) => showNormalizeClipDialog(ctx, c, 'c1'));
    expect(find.byKey(const Key('normalize-gain')), findsOneWidget);
  });

  uiTest('áudio fora do aparelho: mensagem clara em vez de prévia', (t) async {
    await setView(t, 360, 640);
    final (c, _) = await project(t);
    c.mutate((d) => d.tracks[0].clips.single.sample = 'nao-existe');
    await host(t, c, (ctx) => showStripSilenceDialog(ctx, c, 'c1'));
    expect(find.textContaining('não está neste aparelho'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  uiTest('o menu do clipe abre o submenu Editar áudio', (t) async {
    await setView(t, 360, 640);
    final (c, _) = await project(t);
    await host(t, c, (ctx) => showEditAudioMenu(ctx, c, 'c1', const Offset(40, 100)));
    for (final s in ['Dividir por transientes…', 'Remover silêncio…', 'Normalizar clipe…', 'Quantizar por fatias…']) {
      expect(find.text(s), findsOneWidget);
    }
    await t.tap(find.text('Remover silêncio…'));
    await t.pumpAndSettle();
    expect(find.text('Remover silêncio'), findsOneWidget);
    expect(c.doc.tracks[0].clips.single, isA<AudioClip>());
  });

  group('achados do lote 21', () {
    uiTest('dividir: mais de 500 fatias desabilita o botão e avisa, como as outras ações', (t) async {
      await setView(t, 360, 640);
      final (c, _) = await project(t, x: core.tone(60));
      await host(t, c, (ctx) => showSplitTransientsDialog(ctx, c, 'c1'));
      await t.tap(find.text('Na grade'));
      await t.pumpAndSettle();
      await t.tap(find.text('1/32'));
      await t.pumpAndSettle();
      expect(find.textContaining('Fatias demais'), findsOneWidget);
      expect(find.textContaining('grade maior'), findsOneWidget);
      final btn = t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Dividir'));
      expect(btn.onPressed, isNull);
      await t.tap(find.text('1/8'));
      await t.pumpAndSettle();
      expect(t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Dividir')).onPressed, isNotNull);
    });

    uiTest('a grade e as fatias iguais não mostram nem aplicam a distância mínima', (t) async {
      await setView(t, 360, 640);
      final (c, _) = await project(t, x: core.tone(2));
      await host(t, c, (ctx) => showSplitTransientsDialog(ctx, c, 'c1'));
      expect(find.byKey(const Key('split-mingap')), findsOneWidget);
      await t.tap(find.text('Na grade'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('split-mingap')), findsNothing);
      await t.tap(find.text('1/32'));
      await t.pumpAndSettle();
      // 1/32 a 120 bpm em 2 s: 31 cortes, 32 fatias (o padrão de 50 ms de distância não corta nenhum)
      expect(find.textContaining('32 fatias'), findsOneWidget);
    });

    uiTest('a dica de desfazer do aviso final usa o atalho atual', (t) async {
      await setView(t, 360, 640);
      final (c, _) = await project(t);
      await host(t, c, (ctx) => showNormalizeClipDialog(ctx, c, 'c1'));
      await t.pumpAndSettle();
      await t.tap(find.text('Normalizar'));
      await t.pumpAndSettle();
      expect(find.textContaining('Dá para desfazer numa vez só ('), findsOneWidget);
    });
  });
}
