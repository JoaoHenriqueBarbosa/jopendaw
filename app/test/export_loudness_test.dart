import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jopendaw_app/audio/engine.dart';
import 'package:jopendaw_app/daw/export.dart';
import 'package:jopendaw_app/daw/export_options.dart';
import 'package:jopendaw_app/daw/loudness.dart';
import 'package:jopendaw_app/daw/loudness_panel.dart';
import 'package:jopendaw_app/daw/model.dart';
import 'package:jopendaw_app/daw/wav.dart';

import 'export_test.dart' show project;
import 'fake_engine.dart';

const rate = 48000.0;

double dbfs(double db) => math.pow(10, db / 20).toDouble();

Float32List sine(double amp, double secs, {double hz = 1000}) {
  final n = (secs * rate).round();
  return Float32List.fromList([for (var i = 0; i < n; i++) amp * math.sin(2 * math.pi * hz * i / rate)]);
}

/// A mixagem de mentira: um seno estéreo em fase; as outras saídas (stems) ficam com um seno menor.
List<List<Float32List>> tone(List<int> outputs, {double mix = -20, double stem = -26}) => [
  for (final o in outputs) [sine(dbfs(o == -1 ? mix : stem), 5), sine(dbfs(o == -1 ? mix : stem), 5)],
];

void main() {
  late FakeEngine e;
  setUp(() => e = FakeEngine());

  Future<({double lufs, double tp, double peak})> measured(Uint8List wav) async {
    final w = decodeWav(wav);
    final m = await measureLoudness(w.channels, w.sampleRate.toDouble());
    return (lufs: m.integrated, tp: m.truePeak, peak: m.samplePeak);
  }

  group('exportar com normalização de loudness', () {
    test('leva a mixagem ao alvo e o relatório traz o que o arquivo mede de verdade', () async {
      final c = await project(e);
      e.renderResult = (outputs) => tone(outputs);
      final progress = <double>[];
      await c.exportAudio(const ExportOptions(format: ExportFormat.wav32f, targetLufs: -14, sampleRate: 48000, tail: 0), onProgress: progress.add);
      expect(c.error, isNull);
      final saved = e.saved.single;
      final m = await measured(saved.$2);
      expect(m.lufs, closeTo(-14, 0.1));
      final r = c.exportReport!;
      expect(r.unmeasurable, isFalse);
      expect(r.limitedByCeiling, isFalse);
      expect(r.beforeLufs, closeTo(-20, 0.1));
      expect(r.appliedDb, closeTo(6, 0.1));
      expect(r.afterLufs, closeTo(m.lufs, 0.01), reason: 'o relatório é a medida do arquivo final, não uma previsão');
      expect(r.describe(), contains('subiu 6,0 dB'));
      // o progresso passa pela medida e termina em 1, sem voltar atrás
      expect(progress.last, 1);
      expect(progress, orderedEquals([...progress]..sort()));
    });

    test('o teto de true peak segura o ganho: o resultado fica abaixo do alvo e a interface avisa', () async {
      final c = await project(e);
      // seno de −4 dBFS: −4 dBFS de pico dão −4 LUFS; alvo −14 = descer; use um sinal mais baixo
      // com pico alto: um pulso de −2 dBFS sobre um seno baixo
      e.renderResult = (outputs) => [
        for (final _ in outputs) [sine(dbfs(-30), 5)..[24000] = dbfs(-2), sine(dbfs(-30), 5)..[24000] = dbfs(-2)],
      ];
      await c.exportAudio(const ExportOptions(format: ExportFormat.wav32f, targetLufs: -14, sampleRate: 48000, tail: 0));
      final r = c.exportReport!;
      expect(r.limitedByCeiling, isTrue);
      expect(r.appliedDb, lessThan(r.targetLufs - r.beforeLufs - 1));
      final m = await measured(e.saved.single.$2);
      expect(m.tp, lessThanOrEqualTo(-1 + 0.05), reason: 'o true peak respeita o teto de −1 dBTP');
      expect(m.tp, greaterThan(-1.3), reason: 'e o ganho subiu até o teto, não menos');
      expect(m.lufs, lessThan(-14 - 0.5));
      expect(r.describe(), contains('teto de −1,0 dBTP'));
      expect(r.describe(), contains('abaixo dos −14,0 LUFS pedidos'));
    });

    test('teto e alvo personalizados', () async {
      final c = await project(e);
      e.renderResult = (outputs) => tone(outputs);
      await c.exportAudio(const ExportOptions(format: ExportFormat.wav32f, targetLufs: -23, ceilingDbtp: -6, sampleRate: 48000, tail: 0));
      final m = await measured(e.saved.single.$2);
      expect(m.lufs, closeTo(-23, 0.1));
      expect(c.exportReport!.ceilingDb, -6);
      expect(c.exportReport!.appliedDb, closeTo(-3, 0.1), reason: 'descer 3 dB: −20 para −23');
    });

    test('mixagem muda ou curta demais: exporta sem normalizar e diz isso', () async {
      final c = await project(e);
      e.renderResult = (outputs) => [
        for (final _ in outputs) [Float32List(48000), Float32List(48000)],
      ];
      await c.exportAudio(const ExportOptions(format: ExportFormat.wav32f, targetLufs: -14, sampleRate: 48000, tail: 0));
      expect(c.error, isNull);
      expect(e.saved, hasLength(1), reason: 'a mixagem sai mesmo assim');
      expect(c.exportReport!.unmeasurable, isTrue);
      expect(c.exportReport!.describe(), contains('sem normalizar'));
      // curta: 200 ms
      e.saved.clear();
      e.renderResult = (outputs) => [
        for (final _ in outputs) [sine(0.1, 0.2), sine(0.1, 0.2)],
      ];
      await c.exportAudio(const ExportOptions(format: ExportFormat.wav32f, targetLufs: -14, sampleRate: 48000, tail: 0));
      final w = decodeWav(e.saved.single.$2);
      expect(w.channels[0][100], closeTo(sine(0.1, 0.2)[100], 1e-6), reason: 'áudio intacto');
      expect(c.exportReport!.unmeasurable, isTrue);
    });

    test('stems seguem sem normalização; com o pedido levam o mesmo ganho da mixagem', () async {
      final c = await project(e);
      e.renderResult = (outputs) => tone(outputs);
      await c.exportAudio(const ExportOptions(format: ExportFormat.wav32f, targetLufs: -14, stems: true, sampleRate: 48000, tail: 0));
      expect(e.saved.length, 4, reason: 'a mixagem e os stems das três faixas');
      final raw = decodeWav(e.saved[1].$2);
      expect(raw.channels[0][12], closeTo(sine(dbfs(-26), 5)[12], 1e-6), reason: 'stem como renderizado');

      e.saved.clear();
      await c.exportAudio(const ExportOptions(format: ExportFormat.wav32f, targetLufs: -14, stems: true, normalizeStems: true, sampleRate: 48000, tail: 0));
      final gain = dbToGain(c.exportReport!.appliedDb);
      final stem = decodeWav(e.saved[1].$2);
      expect(stem.channels[0][12], closeTo(sine(dbfs(-26), 5)[12] * gain, 2e-6));
      // o mesmo ganho, então o equilíbrio (a diferença mixagem/stem) se mantém
      final mix = await measured(e.saved[0].$2);
      final stemM = await measured(e.saved[1].$2);
      expect(mix.lufs - stemM.lufs, closeTo(6, 0.15));
    });

    test('normalizar o pico e o loudness juntos: o loudness vale (o pico é ignorado)', () async {
      final c = await project(e);
      e.renderResult = (outputs) => tone(outputs);
      await c.exportAudio(const ExportOptions(format: ExportFormat.wav32f, normalize: true, targetLufs: -14, sampleRate: 48000, tail: 0));
      final m = await measured(e.saved.single.$2);
      expect(m.lufs, closeTo(-14, 0.1));
      expect(m.peak, lessThan(-4), reason: 'não foi levado a −1 dBFS');
    });

    test('sem alvo, nada de relatório e o pico segue como sempre', () async {
      final c = await project(e);
      e.renderResult = (outputs) => tone(outputs);
      await c.exportAudio(const ExportOptions(format: ExportFormat.wav32f, normalize: true, sampleRate: 48000, tail: 0));
      expect(c.exportReport, isNull);
      expect((await measured(e.saved.single.$2)).peak, closeTo(-1, 0.01));
    });

    test('alvo e teto fora dos limites são apertados aos limites da interface', () async {
      final c = await project(e);
      e.renderResult = (outputs) => tone(outputs);
      await c.exportAudio(const ExportOptions(format: ExportFormat.wav32f, targetLufs: 50, ceilingDbtp: 20, sampleRate: 48000, tail: 0));
      expect(c.exportReport!.targetLufs, kMaxTargetLufs);
      expect(c.exportReport!.ceilingDb, kMaxCeiling);
      expect(c.error, isNull);
    });

    test('cancelar durante a medida não salva nada', () async {
      final c = await project(e);
      e.renderResult = (outputs) {
        // o cancelamento chega logo depois do render, antes da medida terminar
        Future<void>.delayed(Duration.zero, c.cancelRender);
        return tone(outputs);
      };
      await c.exportAudio(const ExportOptions(format: ExportFormat.wav32f, targetLufs: -14, sampleRate: 48000, tail: 0));
      expect(e.saved, isEmpty);
      expect(c.error, isNull);
      expect(c.rendering, isFalse);
    });
  });

  group('medição ao vivo no controlador', () {
    test('a leitura do motor chega em loudness e "Zerar" manda loudness_reset', () async {
      final c = fakeController(e);
      await c.open();
      expect(c.loudness.value, const LoudnessReading());
      e.onLoudness!(const LoudnessReading(momentary: -13, shortTerm: -14, integrated: -14.5, truePeak: -0.5, range: 5));
      expect(c.loudness.value.integrated, -14.5);
      c.resetLoudness();
      expect(e.sent('loudness_reset'), [
        ['loudness_reset'],
      ]);
      expect(c.loudness.value, const LoudnessReading());
    });
  });

  group('interface', () {
    testWidgets('a leitura mostra M, S, I e TP; true peak acima de −1 dBTP fica em alerta; Zerar chama o callback', (tester) async {
      final reading = ValueNotifier(const LoudnessReading(momentary: -13.2, shortTerm: -14.04, integrated: -14.5, truePeak: -2.1));
      var resets = 0;
      Widget app(double width) => MaterialApp(
        home: Material(
          child: Center(
            child: SizedBox(
              width: width,
              child: LoudnessPanel(reading: reading, onReset: () => resets++),
            ),
          ),
        ),
      );
      // no canal do master: 84 px úteis
      await tester.pumpWidget(app(84));
      expect(tester.takeException(), isNull);
      var text = tester.widgetList<Text>(find.byType(Text)).map((t) => t.textSpan?.toPlainText() ?? t.data ?? '').join('|');
      expect(text, contains('M −13,2'));
      expect(text, contains('S −14,0'));
      expect(text, contains('I −14,5'));
      expect(text, contains('TP −2,1'));
      Color? tpColor() {
        for (final t in tester.widgetList<RichText>(find.byType(RichText))) {
          if (!t.text.toPlainText().startsWith('TP ')) continue;
          // a cor do número: a do último trecho com texto
          Color? color;
          t.text.visitChildren((span) {
            if (span is TextSpan && span.text != null && span.text != 'TP ') color = span.style?.color;
            return true;
          });
          return color;
        }
        return null;
      }

      expect(tpColor(), Colors.white);
      reading.value = const LoudnessReading(integrated: -9, truePeak: 0.4);
      await tester.pump();
      expect(tpColor(), isNot(Colors.white), reason: 'alerta em cor');
      expect(truePeakAlert(-1), isFalse, reason: 'exatamente no teto ainda não é alerta');
      expect(truePeakAlert(-0.9), isTrue);
      expect(truePeakAlert(-200), isFalse);
      // sem medida: traços, não números
      reading.value = const LoudnessReading();
      await tester.pump();
      text = tester.widgetList<Text>(find.byType(Text)).map((t) => t.textSpan?.toPlainText() ?? t.data ?? '').join('|');
      expect(text, contains('M —'));
      expect(text, contains('TP —'));
      expect(text, isNot(contains('200')));
      await tester.tap(find.text('Zerar'));
      expect(resets, 1);
      // largo: uma linha só
      await tester.pumpWidget(app(400));
      expect(tester.takeException(), isNull);
      expect(find.text('Zerar'), findsOneWidget);
    });

    testWidgets('a janela de exportação: ligar o loudness mostra os alvos; as opções saem nas ExportOptions', (tester) async {
      final c = await project(e);
      ExportOptions? chosen;
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async => chosen = await showDialog<ExportOptions>(
                context: context,
                builder: (_) => ExportDialog(c: c),
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      expect(find.text('Normalizar o loudness'), findsOneWidget);
      expect(find.textContaining('Streaming'), findsNothing);
      await tester.tap(find.text('Normalizar o loudness'));
      await tester.pumpAndSettle();
      expect(find.text('Streaming −14,0'), findsOneWidget);
      expect(find.text('Podcast −16,0'), findsOneWidget);
      expect(find.text('Broadcast −23,0'), findsOneWidget);
      expect(find.text('Personalizado'), findsOneWidget);
      expect(find.text('Teto de true peak'), findsOneWidget);
      expect(find.text('−1,0 dBTP'), findsOneWidget);
      await tester.tap(find.text('Broadcast −23,0'));
      await tester.pump();
      await tester.tap(find.text('Exportar'));
      await tester.pumpAndSettle();
      expect(chosen!.targetLufs, -23);
      expect(chosen!.ceilingDbtp, -1);
      expect(chosen!.normalize, isFalse);
      expect(chosen!.normalizeStems, isFalse);
    });

    testWidgets('ligar o pico desliga o loudness e vice-versa; stems oferecem o mesmo ganho', (tester) async {
      final c = await project(e);
      ExportOptions? chosen;
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async => chosen = await showDialog<ExportOptions>(
                context: context,
                builder: (_) => ExportDialog(c: c, initial: const ExportOptions(targetLufs: -16, stems: true)),
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      // volta com o alvo lembrado (podcast −16) e o interruptor dos stems visível
      expect(find.text('Stems com o mesmo ganho'), findsOneWidget);
      await tester.tap(find.text('Stems com o mesmo ganho'));
      await tester.pump();
      await tester.tap(find.text('Normalizar'));
      await tester.pumpAndSettle();
      expect(find.text('Streaming −14,0'), findsNothing, reason: 'ligar o pico desligou o loudness');
      await tester.tap(find.text('Normalizar o loudness'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Exportar'));
      await tester.pumpAndSettle();
      expect(chosen!.targetLufs, -16);
      expect(chosen!.normalize, isFalse);
      expect(chosen!.normalizeStems, isTrue);
    });
  });
}
