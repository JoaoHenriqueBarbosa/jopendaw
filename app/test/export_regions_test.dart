import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jopendaw_app/daw/controller.dart';
import 'package:jopendaw_app/daw/export.dart';
import 'package:jopendaw_app/daw/export_options.dart';
import 'package:jopendaw_app/daw/export_plan.dart';
import 'package:jopendaw_app/daw/instruments.dart';
import 'package:jopendaw_app/daw/model.dart';
import 'package:jopendaw_app/daw/wav.dart';

import 'fake_engine.dart';

Float32List filled(int n, double v) => Float32List(n)..fillRange(0, n, v);

/// Faixa de áudio (clipe de 2 s = 4 batidas em 0), um sintetizador com nota e um barramento: o conteúdo vai a 8 batidas.
Future<DawController> project(FakeEngine e) async {
  final c = fakeController(e);
  await c.importBytes(
    [
      ('voz.wav', encodeWav([filled(200, 0.25)], 100, ExportFormat.wav32f)),
    ],
    at: 0,
    track: 0,
  );
  c.addInstrumentTrack(TrackKind.synth);
  final clip = c.createMidiClip(1, 4);
  c.edit((_) => clip.notes.add(MidiNote(pitch: 60, start: 0, length: 2)));
  c.addBusTrack();
  return c;
}

List<List<Float32List>> sound(List<int> outputs) => [
  for (final _ in outputs) [filled(100, 0.5), filled(100, 0.5)],
];

void main() {
  late FakeEngine e;
  setUp(() => e = FakeEngine());

  /// Um documento só com o que o plano lê: uma faixa de 8 batidas e os marcadores pedidos (ids m0, m1...).
  DawDoc docWith(List<(String, double)> markers, {double end = 8}) {
    final d = DawDoc(bpm: 120, beatsPerBar: 4);
    d.tracks.add(
      DawTrack(
        id: 't1',
        name: 'A',
        color: 0xFF112233,
        clips: [AudioClip(id: 'c1', sample: 'h', start: 0, length: end / 2)],
      ),
    );
    d.markers = [for (var i = 0; i < markers.length; i++) Marker(id: 'm$i', beat: markers[i].$2, name: markers[i].$1)];
    return d;
  }

  group('nomes', () {
    test('saneia caracteres inválidos, separadores repetidos, pontas e nomes reservados', () {
      expect(sanitizeExportName('a/b:c*d?e"f<g>h|i'), 'a_b_c_d_e_f_g_h_i');
      expect(sanitizeExportName('  --Meu  projeto..  '), 'Meu projeto');
      expect(sanitizeExportName('x--y__z'), 'x-y_z');
      expect(sanitizeExportName('CON'), '_CON');
      expect(sanitizeExportName('///'), 'jopendaw');
      expect(sanitizeExportName('', fallback: 'f'), 'f');
      expect(sanitizeExportName('a' * 300).length, 100);
    });

    test('o modelo troca {projeto}, {marcador} e {n} (com zeros) e descarta o desconhecido', () {
      expect(expandNameTemplate('{projeto}-{marcador}-{n}', project: 'Som', marker: 'Refrão', n: 3, count: 12), 'Som-Refrão-03');
      expect(expandNameTemplate('{PROJETO} {x} {n}', project: 'Som', marker: '', n: 1, count: 5), 'Som 1');
      // marcador vazio não deixa "--"
      expect(expandNameTemplate('{projeto}-{marcador}-{n}', project: 'Som', marker: '', n: 1, count: 1), 'Som-1');
      // tudo vazio cai para o projeto e o número
      expect(expandNameTemplate('{marcador}', project: 'Som', marker: '', n: 2, count: 2), 'Som-2');
      expect(expandNameTemplate('../x', project: 'Som', marker: '', n: 1, count: 1), 'x');
    });

    test('desempata sem distinguir maiúsculas', () {
      expect(uniqueNames(['a', 'A', 'b', 'a']), ['a', 'A (2)', 'b', 'a (3)']);
      expect(uniqueNames(['a'], taken: {'a'}), ['a (2)']);
    });
  });

  group('plano', () {
    test('música inteira e loop mantêm o nome do projeto', () {
      final d = docWith([]);
      final p = planExport(d, const ExportOptions(), project: 'Meu/Som');
      expect((p.spans.single.from, p.spans.single.to, p.spans.single.base), (0.0, 8.0, 'Meu_Som'));
      d.loopStart = d.loopEnd = 2;
      expect(planExport(d, const ExportOptions(range: ExportRange.loop), project: 'x').problem, contains('loop'));
      d.loopEnd = 6;
      expect(planExport(d, const ExportOptions(range: ExportRange.loop), project: 'x').spans.single.to, 6.0);
    });

    test('região sem marcadores: entre marcadores e seções recusam', () {
      final d = docWith([]);
      expect(planExport(d, const ExportOptions(range: ExportRange.sections), project: 'x').problem, contains('Não há marcadores'));
      // um marcador que não existe (apagado depois)
      expect(
        planExport(
          d,
          const ExportOptions(range: ExportRange.markers, fromMarker: 'sumiu'),
          project: 'x',
        ).problem,
        contains('não existe mais'),
      );
      // sem marcador nenhum escolhido é a música inteira, com o nome do modelo
      final all = planExport(d, const ExportOptions(range: ExportRange.markers), project: 'x');
      expect((all.spans.single.from, all.spans.single.to), (0.0, 8.0));
    });

    test('marcador único: do marcador ao fim; e o início até ele', () {
      final d = docWith([('Refrão', 4)]);
      final a = planExport(
        d,
        const ExportOptions(range: ExportRange.markers, fromMarker: 'm0'),
        project: 'Som',
      );
      expect((a.spans.single.from, a.spans.single.to, a.spans.single.label, a.spans.single.base), (4.0, 8.0, 'Refrão', 'Som-Refrão-1'));
      final b = planExport(
        d,
        const ExportOptions(range: ExportRange.markers, toMarker: 'm0'),
        project: 'Som',
      );
      expect((b.spans.single.from, b.spans.single.to), (0.0, 4.0));
      // seções: o trecho antes do marcador ("Início") e o dele
      final s = planExport(d, const ExportOptions(range: ExportRange.sections), project: 'Som');
      expect([for (final x in s.spans) (x.from, x.to, x.base)], [(0.0, 4.0, 'Som-Início-1'), (4.0, 8.0, 'Som-Refrão-2')]);
    });

    test('marcadores iguais: sem trecho; seção não duplica', () {
      final d = docWith([('A', 2), ('B', 2)]);
      final p = planExport(
        d,
        const ExportOptions(range: ExportRange.markers, fromMarker: 'm0', toMarker: 'm1'),
        project: 'x',
      );
      expect(p.problem, contains('mesmo ponto'));
      final s = planExport(d, const ExportOptions(range: ExportRange.sections), project: 'x');
      expect([for (final x in s.spans) (x.from, x.to, x.label)], [(0.0, 2.0, 'Início'), (2.0, 8.0, 'A')]);
    });

    test('ordem: escolher de trás para frente dá o mesmo trecho; fora de ordem na lista vira ordem da música', () {
      final d = docWith([('A', 6), ('B', 2)]);
      final p = planExport(
        d,
        const ExportOptions(range: ExportRange.markers, fromMarker: 'm0', toMarker: 'm1'),
        project: 'x',
      );
      expect((p.spans.single.from, p.spans.single.to, p.spans.single.label), (2.0, 6.0, 'B a A'));
      final s = planExport(d, const ExportOptions(range: ExportRange.sections), project: 'x');
      expect([for (final x in s.spans) x.label], ['Início', 'B', 'A']);
      expect([for (final x in s.spans) x.n], [1, 2, 3]);
    });

    test('marcador depois do fim: trecho vazio recusa; seção no fim não conta', () {
      final d = docWith([('A', 4), ('Fim', 8), ('Além', 12)]);
      final s = planExport(d, const ExportOptions(range: ExportRange.sections), project: 'x');
      expect([for (final x in s.spans) x.label], ['Início', 'A']);
      final p = planExport(
        d,
        const ExportOptions(range: ExportRange.markers, fromMarker: 'm2'),
        project: 'x',
      );
      expect(p.problem, contains('depois do fim'));
    });

    test('nomes duplicados entre seções ganham número; marcadores sem nome ganham um', () {
      final d = docWith([('Verso', 0), ('Verso', 2), ('', 4)]);
      final s = planExport(
        d,
        const ExportOptions(range: ExportRange.sections, nameTemplate: '{marcador}'),
        project: 'Som',
      );
      expect([for (final x in s.spans) x.base], ['Verso', 'Verso (2)', 'Marcador 3']);
      // maiúsculas diferentes colidem no macOS e no Windows
      final d2 = docWith([('verso', 0), ('VERSO', 2)]);
      final s2 = planExport(
        d2,
        const ExportOptions(range: ExportRange.sections, nameTemplate: '{marcador}'),
        project: 'Som',
      );
      expect([for (final x in s2.spans) x.base], ['verso', 'VERSO (2)']);
    });

    test('seções escolhidas: só as marcadas; nenhuma recusa', () {
      final d = docWith([('A', 0), ('B', 4)]);
      final s = planExport(
        d,
        const ExportOptions(range: ExportRange.sections, sectionIds: ['m1']),
        project: 'x',
      );
      expect([for (final x in s.spans) x.label], ['B']);
      expect(
        planExport(
          d,
          const ExportOptions(range: ExportRange.sections, sectionIds: []),
          project: 'x',
        ).problem,
        contains('Nenhuma seção'),
      );
    });

    test('faixas selecionadas vazias recusam; ids velhos são ignorados', () {
      final d = docWith([]);
      expect(planExport(d, const ExportOptions(trackIds: []), project: 'x').problem, contains('Nenhuma faixa'));
      expect(planExport(d, const ExportOptions(trackIds: ['nao-existe']), project: 'x').problem, contains('Nenhuma faixa'));
      expect(exportTrackIndexes(d, const ExportOptions(trackIds: ['nao-existe', 't1'])), [0]);
      expect(exportTrackIndexes(d, const ExportOptions()), [0]);
    });

    test('o zip desempata nomes e sai legível', () {
      final z = ExportZip();
      z.add('a.wav', Uint8List.fromList([1, 2, 3]));
      expect(z.add('A.wav', Uint8List.fromList([4])), 'A (2).wav');
      expect(z.add('../x/b.wav', Uint8List.fromList([5])), 'x_b.wav');
      final back = ZipDecoder().decodeBytes(z.build());
      expect(back.length, 3);
      expect(back.first.name, 'a.wav');
      expect(back.first.content, [1, 2, 3]);
    });
  });

  group('exportar por intervalos', () {
    test('uma seção por marcador: um render por seção, o nome do marcador, o progresso de 0 a 1', () async {
      final c = await project(e);
      c.addMarker(beat: 0, name: 'Intro');
      c.addMarker(beat: 4, name: 'Refrão');
      e.renderResult = sound;
      final progress = <double>[];
      final spans = <String>[];
      await c.exportAudio(
        const ExportOptions(range: ExportRange.sections, format: ExportFormat.wav16, tail: 1),
        onProgress: progress.add,
        onSpan: (i, n, label) => spans.add('$i/$n $label'),
      );
      expect(c.error, isNull);
      expect([for (final r in e.renders) (r.fromBeat, r.toBeat, r.tailSeconds)], [(0.0, 4.0, 1.0), (4.0, 8.0, 1.0)]);
      expect(e.saved.map((s) => s.$1), ['Teste-Intro-1.wav', 'Teste-Refrão-2.wav']);
      expect(spans, ['0/2 Intro', '1/2 Refrão']);
      expect(progress.last, 1);
      for (var i = 1; i < progress.length; i++) {
        expect(progress[i], greaterThanOrEqualTo(progress[i - 1] - 1e-9));
      }
      expect(c.rendering, isFalse);
    });

    test('entre dois marcadores com stems: só o trecho, mixagem e stems com o nome do modelo', () async {
      final c = await project(e);
      final a = c.addMarker(beat: 2, name: 'A');
      final b = c.addMarker(beat: 6, name: 'B');
      e.renderResult = sound;
      await c.exportAudio(ExportOptions(range: ExportRange.markers, fromMarker: a.id, toMarker: b.id, stems: true, nameTemplate: '{marcador} ({projeto})'));
      expect(e.renders.single.fromBeat, 2.0);
      expect(e.renders.single.toBeat, 6.0);
      expect(e.saved.map((s) => s.$1).first, 'A a B (Teste).wav');
      expect(e.saved, hasLength(4));
    });

    test('cancelar no meio: para no intervalo seguinte, o que já saiu fica e não vira erro', () async {
      final c = await project(e);
      c.addMarker(beat: 0, name: 'A');
      c.addMarker(beat: 2, name: 'B');
      c.addMarker(beat: 4, name: 'C');
      var calls = 0;
      e.renderResult = (outputs) {
        calls++;
        if (calls == 2) c.cancelRender();
        return sound(outputs);
      };
      await c.exportAudio(const ExportOptions(range: ExportRange.sections));
      // o segundo render acabou quando o cancelamento chegou: o terceiro nem começa
      expect(e.renders, hasLength(2));
      expect(c.error, isNull);
      expect(c.rendering, isFalse);
      expect(c.exportSavedCount, e.saved.length);
      // e uma exportação nova depois funciona
      e.renders.clear();
      e.saved.clear();
      calls = -100;
      await c.exportAudio(const ExportOptions(range: ExportRange.sections));
      expect(e.renders, hasLength(3));
    });

    test('faixas selecionadas: a mixagem é o solo delas; os stems só delas', () async {
      final c = await project(e);
      e.renderResult = sound;
      final id = c.doc.tracks[1].id;
      await c.exportAudio(ExportOptions(trackIds: [id], stems: true, format: ExportFormat.wav16));
      final r = e.renders.single;
      expect(r.outputs, [-1, 1]);
      expect([for (final t in r.calls.where((x) => x.first == 'track')) t[5]], [false, true, false]);
      expect(e.saved, hasLength(2));
      // sem seleção, o solo do projeto continua como está (nenhum)
      e.renders.clear();
      await c.exportAudio(const ExportOptions());
      expect([for (final t in e.renders.single.calls.where((x) => x.first == 'track')) t[5]], [false, false, false]);
      // o documento de verdade não foi mexido
      expect(c.doc.tracks.every((t) => !t.solo), isTrue);
    });

    test('nenhuma faixa escolhida: aviso e nada é renderizado', () async {
      final c = await project(e);
      await c.exportAudio(const ExportOptions(trackIds: []));
      expect(e.renders, isEmpty);
      expect(c.error, contains('Nenhuma faixa'));
    });

    test('seção sem som fica de fora com aviso; o loudness é por arquivo', () async {
      final c = await project(e);
      c.addMarker(beat: 0, name: 'A');
      c.addMarker(beat: 4, name: 'B');
      var n = 0;
      e.renderResult = (outputs) => ++n == 1
          ? [
              [Float32List(100), Float32List(100)],
            ]
          : sound(outputs);
      await c.exportAudio(const ExportOptions(range: ExportRange.sections));
      expect(e.saved.map((s) => s.$1), ['Teste-B-2.wav']);
      expect(c.error, contains('sem som'));
      e.saved.clear();
      e.renders.clear();
      c.clearError();
      e.renderResult = (outputs) => [
        for (final _ in outputs) [filled(9600, 0.3), filled(9600, 0.3)],
      ];
      await c.exportAudio(const ExportOptions(range: ExportRange.sections, targetLufs: -20));
      expect(c.exportReports.map((r) => r.name), ['Teste-A-1.wav', 'Teste-B-2.wav']);
    });

    test('sem marcadores, o pedido por seções é recusado com aviso', () async {
      final c = await project(e);
      await c.exportAudio(const ExportOptions(range: ExportRange.sections));
      expect(e.renders, isEmpty);
      expect(c.error, contains('marcadores'));
    });
  });

  group('janela', () {
    Future<void> open(WidgetTester tester, DawController c, Size size, {ExportOptions initial = const ExportOptions()}) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<ExportOptions>(
                context: context,
                builder: (_) => ExportDialog(c: c, initial: initial),
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
    }

    for (final size in [const Size(360, 740), const Size(1512, 900)]) {
      testWidgets('seções e faixas em ${size.width.toInt()} px: sem estouro e as escolhas valem', (tester) async {
        final c = await project(e);
        c.addMarker(beat: 0, name: 'Intro');
        c.addMarker(beat: 4, name: 'Refrão');
        await open(tester, c, size);
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.byKey(const Key('export-range-sections')));
        await tester.tap(find.byKey(const Key('export-range-sections')));
        await tester.pumpAndSettle();
        expect(tester.widget<Text>(find.byKey(const Key('export-name-preview'))).data, 'Teste-Intro-1.wav, Teste-Refrão-2.wav');
        // desmarca a primeira seção
        final first = find.byKey(Key('export-section-${c.doc.markers.first.id}'));
        await tester.ensureVisible(first);
        await tester.tap(first);
        await tester.pumpAndSettle();
        expect(find.text('1 de 2 seções'), findsOneWidget);
        expect(tester.takeException(), isNull);
        // com as três faixas nos stems o zip é oferecido
        final stems = find.text('Stems');
        await tester.ensureVisible(stems);
        await tester.tap(stems);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('export-zip')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('faixas: desmarcar todas bloqueia o Exportar; "Só a selecionada" marca uma', (tester) async {
      final c = await project(e);
      c.selectedTrack = 1;
      await open(tester, c, const Size(900, 1800));
      await tester.tap(find.byKey(const Key('export-tracks')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('export-tracks-selected')));
      await tester.pumpAndSettle();
      expect(find.text('1 de 3'), findsOneWidget);
      final chip = find.byKey(Key('export-track-${c.doc.tracks[1].id}'));
      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(find.textContaining('Nenhuma faixa escolhida'), findsWidgets);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Exportar')).onPressed, isNull);
    });

    testWidgets('um marcador que sumiu desde a última vez volta para a música inteira', (tester) async {
      final c = await project(e);
      await open(
        tester,
        c,
        const Size(900, 1800),
        initial: const ExportOptions(range: ExportRange.markers, fromMarker: 'sumiu'),
      );
      expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, ExportRange.song.label)).selected, isTrue);
    });

    testWidgets('o andamento: todos os arquivos das seções saem num .zip só, com o nome do projeto', (tester) async {
      final c = (await tester.runAsync(() => project(e)))!;
      c.addMarker(beat: 0, name: 'Intro');
      c.addMarker(beat: 4, name: 'Refrão');
      e.renderResult = sound;
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: ExportProgressDialog(
            c: c,
            options: const ExportOptions(range: ExportRange.sections, zip: true, format: ExportFormat.wav16),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final (name, bytes, mime) = e.saved.single;
      expect((name, mime), ('Teste.zip', 'application/zip'));
      final zip = ZipDecoder().decodeBytes(bytes);
      expect(zip.map((f) => f.name), ['Teste-Intro-1.wav', 'Teste-Refrão-2.wav']);
      expect(find.textContaining('reunidos em "Teste.zip"'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('o andamento sem zip: um arquivo por seção e a mensagem fala dos intervalos', (tester) async {
      final c = (await tester.runAsync(() => project(e)))!;
      c.addMarker(beat: 0, name: 'Intro');
      c.addMarker(beat: 4, name: 'Refrão');
      e.renderResult = sound;
      await tester.pumpWidget(
        MaterialApp(
          home: ExportProgressDialog(
            c: c,
            options: const ExportOptions(range: ExportRange.sections, format: ExportFormat.wav16),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(e.saved, hasLength(2));
      expect(find.textContaining('2 intervalos'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
    });
  });
}
