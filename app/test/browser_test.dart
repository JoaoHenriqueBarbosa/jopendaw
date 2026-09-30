// Fase 26 B: o navegador de áudios (lista do projeto e da conta, busca, pré-escuta à parte do transporte, inserção no
// arranjo e em zonas do sampler, baixar sob demanda) e a aba "Áudios" do painel de baixo.
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show KeyDownEvent, LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:jopendaw_app/api/storage.dart';
import 'package:jopendaw_app/daw/browser.dart';
import 'package:jopendaw_app/daw/browser_panel.dart';
import 'package:jopendaw_app/daw/controller.dart';
import 'package:jopendaw_app/daw/dock.dart';
import 'package:jopendaw_app/daw/export_options.dart';
import 'package:jopendaw_app/daw/instruments.dart';
import 'package:jopendaw_app/daw/model.dart';
import 'package:jopendaw_app/daw/wav.dart';

import 'fake_engine.dart';

/// Um áudio de [secs] segundos (o motor de mentira roda a 100 Hz) com [v] em todas as amostras.
Uint8List audio(double v, {double secs = 2}) => encodeWav([Float32List.fromList(List.filled((secs * 100).round(), v))], 100, ExportFormat.wav32f);

String shaOf(Uint8List b) => sha256.convert(b).toString();

class Rig {
  final FakeEngine engine;
  final MemoryStore store;
  final DawController c;
  final AudioBrowser b;

  /// Bytes que o "servidor" tem, por hash, e quantas vezes cada um foi pedido.
  final server = <String, Uint8List>{};
  final fetched = <String>[];
  var usage = const StorageUsage(quotaBytes: 4000000000, usedBytes: 0, unusedBytes: 0, unusedCount: 0);
  Object? usageFailure;
  Duration now = Duration.zero;

  Rig._(this.engine, this.store, this.c, this.b);

  factory Rig({List<DawTrack>? tracks}) {
    final engine = FakeEngine();
    final store = MemoryStore();
    final c = fakeController(engine, store: store, tracks: tracks);
    late Rig rig;
    final b = AudioBrowser(
      c,
      loadUsage: () async {
        final f = rig.usageFailure;
        if (f != null) throw f;
        return rig.usage;
      },
      fetchBytes: (h) async {
        rig.fetched.add(h);
        return rig.server[h];
      },
      now: () => rig.now,
    );
    rig = Rig._(engine, store, c, b);
    return rig;
  }

  /// Um áudio só do servidor (conta): fora deste aparelho.
  String serverOnly(String name, double v, {List<String> projects = const []}) {
    final bytes = audio(v);
    final hash = shaOf(bytes);
    server[hash] = bytes;
    usage = StorageUsage(
      quotaBytes: usage.quotaBytes,
      usedBytes: usage.usedBytes + bytes.length,
      unusedBytes: 0,
      unusedCount: 0,
      samples: [
        ...usage.samples,
        StoredSample(hash: hash, name: name, size: bytes.length, projects: projects),
      ],
    );
    return hash;
  }

  BrowserEntry entry(String hash) => b.entries.firstWhere((e) => e.hash == hash);

  List<List<Object>> calls(String name) => engine.sent(name);
}

void main() {
  group('busca', () {
    BrowserEntry e(String name, {bool project = false, bool server = false}) =>
        BrowserEntry(hash: name.hashCode.toRadixString(16).padLeft(8, '0'), name: name, inProject: project, onServer: server);

    test('foldText tira acento e caixa', () {
      expect(foldText('Bumbô Ação'), 'bumbo acao');
      expect(foldText('KICK_01.wav'), 'kick_01.wav');
    });

    test('todas as palavras têm de aparecer, em qualquer ordem e sem acento', () {
      final all = [e('Bumbo grave.wav', project: true), e('Caixa seca.wav', project: true), e('Bumbô agudo.wav', server: true)];
      expect([for (final x in filterEntries(all, 'bumbo', BrowserScope.all)) x.name], ['Bumbo grave.wav', 'Bumbô agudo.wav']);
      expect([for (final x in filterEntries(all, 'GRAVE bumbô', BrowserScope.all)) x.name], ['Bumbo grave.wav']);
      expect(filterEntries(all, 'xyz', BrowserScope.all), isEmpty);
      expect(filterEntries(all, '   ', BrowserScope.all), hasLength(3), reason: 'busca só de espaços não filtra');
    });

    test('a origem filtra e o projeto vem antes, depois por nome', () {
      final all = [e('b.wav', server: true), e('a.wav', server: true), e('z.wav', project: true, server: true), e('y.wav', project: true)];
      expect([for (final x in filterEntries(all, '', BrowserScope.all)) x.name], ['y.wav', 'z.wav', 'a.wav', 'b.wav']);
      expect([for (final x in filterEntries(all, '', BrowserScope.project)) x.name], ['y.wav', 'z.wav']);
      expect([for (final x in filterEntries(all, '', BrowserScope.account)) x.name], ['z.wav', 'a.wav', 'b.wav']);
    });

    test('duração como se lê', () {
      expect(fmtDuration(0.4), '0,4 s');
      expect(fmtDuration(7), '0:07');
      expect(fmtDuration(65), '1:05');
      expect(fmtDuration(double.nan), '0:00');
      expect(fmtDuration(7 * 3600), '99:59+');
    });
  });

  group('lista', () {
    test('junta o projeto e a conta por hash, com tamanho, projetos e "fora deste aparelho"', () async {
      final r = Rig();
      final kick = audio(0.5);
      final kickHash = await r.c.importSampleFile('kick.wav', kick);
      r.usage = StorageUsage(
        quotaBytes: 1,
        usedBytes: 1,
        unusedBytes: 0,
        unusedCount: 0,
        samples: [
          StoredSample(hash: kickHash!, name: 'kick.wav', size: kick.length, projects: ['Projeto velho']),
        ],
      );
      final far = r.serverOnly('pad.wav', 0.3, projects: ['Outro']);
      await r.b.refresh();

      final all = r.b.entries;
      expect(all, hasLength(2));
      final k = all.firstWhere((x) => x.hash == kickHash);
      expect((k.inProject, k.onServer, k.onDevice, k.size, k.duration), (true, true, true, kick.length, 2.0));
      expect(k.projects, ['Projeto velho']);
      final p = all.firstWhere((x) => x.hash == far);
      expect((p.inProject, p.onServer, p.onDevice, p.name), (false, true, false, 'pad.wav'));
    });

    test('um áudio do projeto que faltou no aparelho aparece como fora dele', () async {
      final r = Rig();
      r.c.doc.samples['abc123'] = const SampleInfo('perdido.wav', 3);
      r.c.missing.add('abc123');
      await r.b.refresh();
      final x = r.entry('abc123');
      expect((x.inProject, x.onDevice, x.duration), (true, false, 3.0));
    });

    test('servidor fora do ar: a lista segue com o projeto e o erro fica dito', () async {
      final r = Rig();
      await r.c.importSampleFile('kick.wav', audio(0.5));
      r.usageFailure = StateError('sem rede');
      await r.b.refresh();
      expect(r.b.usageError, contains('Não deu para ler os áudios da conta'));
      expect(r.b.entries, hasLength(1));
      r.usageFailure = null;
      await r.b.refresh();
      expect(r.b.usageError, isNull);
    });

    test('áudio sem nome em nenhum lado ganha um nome pelo hash', () async {
      final r = Rig();
      r.usage = const StorageUsage(quotaBytes: 1, usedBytes: 1, unusedBytes: 0, unusedCount: 0, samples: [StoredSample(hash: 'deadbeefcafe', size: 10)]);
      await r.b.refresh();
      expect(r.b.entries.single.name, 'Áudio deadbeef');
    });
  });

  group('pré-escuta', () {
    test('toca pelo id do projeto, sem tocar no documento, no desfazer nem no transporte', () async {
      final r = Rig();
      final hash = (await r.c.importSampleFile('kick.wav', audio(0.5)))!;
      final before = r.c.doc.toJson().toString();
      final canUndo = r.c.canUndo;
      r.engine.log!.clear();
      await r.b.playPreview(r.entry(hash));

      expect(r.b.phase, PreviewPhase.playing);
      final id = r.c.sampleEngineId(hash)!;
      expect(r.calls('preview_play'), [
        ['preview_play', id, 0.0, previewGain],
      ]);
      expect(r.calls('play'), isEmpty);
      expect(r.calls('clips_clear'), isEmpty, reason: 'nenhuma sincronização do documento');
      expect(r.c.doc.toJson().toString(), before);
      expect(r.c.canUndo, canUndo);
      expect(r.engine.loaded.keys.where((k) => k >= previewIdBase), isEmpty, reason: 'o áudio do projeto não é copiado');
      r.b.stopPreview();
    });

    test('a barra anda com o tempo e a pré-escuta termina sozinha no fim do áudio', () async {
      final r = Rig();
      final hash = (await r.c.importSampleFile('kick.wav', audio(0.5)))!;
      await r.b.playPreview(r.entry(hash));
      expect(r.b.previewDuration, 2.0);
      r.now = const Duration(milliseconds: 500);
      r.b.tick();
      expect(r.b.previewPosition, closeTo(0.5, 1e-9));
      expect(r.b.isPreviewing(hash), isTrue);
      r.now = const Duration(milliseconds: 2100);
      r.b.tick();
      expect(r.b.phase, PreviewPhase.idle);
      expect(r.b.previewPosition, 0);
      expect(r.calls('preview_stop'), isEmpty, reason: 'a voz do motor acaba sozinha no fim do áudio');
    });

    test('parar manda o preview_stop; tocar outro troca a voz; tocar o mesmo de novo para', () async {
      final r = Rig();
      final a = (await r.c.importSampleFile('a.wav', audio(0.5)))!;
      final b = (await r.c.importSampleFile('b.wav', audio(0.25)))!;
      await r.b.togglePreview(r.entry(a));
      expect(r.b.previewHash, a);
      await r.b.togglePreview(r.entry(b));
      expect(r.b.previewHash, b);
      expect(r.calls('preview_play'), hasLength(2));
      await r.b.togglePreview(r.entry(b));
      expect(r.b.phase, PreviewPhase.idle);
      expect(r.calls('preview_stop'), hasLength(1));
      r.b.stopPreview();
      expect(r.calls('preview_stop'), hasLength(1), reason: 'parado, parar de novo não manda nada');
    });

    test('a partir de um ponto da barra', () async {
      final r = Rig();
      final hash = (await r.c.importSampleFile('kick.wav', audio(0.5)))!;
      await r.b.playPreview(r.entry(hash), fraction: 0.25);
      expect(r.calls('preview_play').last[2], 0.5);
      expect(r.b.previewPosition, 0.5);
      await r.b.playPreview(r.entry(hash), fraction: 7);
      expect(r.calls('preview_play').last[2], 2.0, reason: 'a fração passa do fim: limitada');
      r.b.stopPreview();
    });

    test('fora do aparelho: baixa sob demanda, guarda no aparelho e toca por um id só da pré-escuta', () async {
      final r = Rig();
      final hash = r.serverOnly('pad.wav', 0.3);
      await r.b.refresh();
      expect(r.entry(hash).onDevice, isFalse);
      await r.b.playPreview(r.entry(hash));
      expect(r.fetched, [hash]);
      expect(r.store.data['sample:$hash'], isA<Uint8List>());
      expect(r.entry(hash).onDevice, isTrue, reason: 'agora está neste aparelho');
      final play = r.calls('preview_play').single;
      expect(play[1] as int, greaterThanOrEqualTo(previewIdBase));
      expect(r.engine.loaded.containsKey(play[1]), isTrue);
      expect(r.c.doc.samples, isEmpty, reason: 'ouvir não põe o áudio no projeto');
      // de novo: sem novo download
      await r.b.playPreview(r.entry(hash));
      expect(r.fetched, hasLength(1));
      r.b.stopPreview();
    });

    test('o servidor não tem o áudio: aviso de erro e nada toca', () async {
      final r = Rig();
      r.usage = const StorageUsage(
        quotaBytes: 1,
        usedBytes: 1,
        unusedBytes: 0,
        unusedCount: 0,
        samples: [StoredSample(hash: 'aaaa1111', name: 'sumiu.wav', size: 5)],
      );
      await r.b.refresh();
      await r.b.playPreview(r.entry('aaaa1111'));
      expect(r.b.phase, PreviewPhase.idle);
      expect(r.b.noticeIsError, isTrue);
      expect(r.b.notice, contains('sumiu.wav'));
      expect(r.calls('preview_play'), isEmpty);
    });

    test('falha de rede no download vira aviso, sem derrubar nada', () async {
      final r = Rig();
      final hash = r.serverOnly('pad.wav', 0.3);
      await r.b.refresh();
      final failing = AudioBrowser(r.c, loadUsage: () async => r.usage, fetchBytes: (_) async => throw StateError('rede caiu'));
      await failing.refresh();
      await failing.playPreview(failing.entries.firstWhere((x) => x.hash == hash));
      expect(failing.phase, PreviewPhase.idle);
      expect(failing.noticeIsError, isTrue);
      expect(failing.isDownloading(hash), isFalse);
    });

    test('no andamento do projeto: estima o andamento, estica e toca o derivado', () async {
      final r = Rig();
      final hash = (await r.c.importSampleFile('loop.wav', audio(0.5)))!;
      r.engine.tempo = (bpm: 60, confidence: 0.9);
      r.b.setAtProjectTempo(true);
      await r.b.playPreview(r.entry(hash));
      // o projeto está a 120: um áudio de 60 BPM dura metade
      expect(r.engine.stretches.single.ratio, 0.5);
      expect(r.b.previewRatio, 0.5);
      expect(r.b.previewDuration, closeTo(1, 1e-9));
      final id = r.calls('preview_play').single[1] as int;
      expect(id, greaterThanOrEqualTo(previewIdBase));
      expect(r.engine.loaded.containsKey(id), isTrue);
      // o mesmo áudio outra vez: o andamento já estimado é reaproveitado
      await r.b.playPreview(r.entry(hash));
      expect(r.engine.detects, 1);
      r.b.stopPreview();
    });

    test('sem andamento confiável toca no original e avisa', () async {
      final r = Rig();
      final hash = (await r.c.importSampleFile('ruido.wav', audio(0.5)))!;
      r.engine.tempo = (bpm: 0, confidence: 0);
      r.b.setAtProjectTempo(true);
      await r.b.playPreview(r.entry(hash));
      expect(r.engine.stretches, isEmpty);
      expect(r.b.previewRatio, 1);
      expect(r.b.notice, contains('Não deu para estimar o andamento'));
      expect(r.b.noticeIsError, isFalse);
      expect(r.calls('preview_play').single[1], r.c.sampleEngineId(hash));
      r.b.stopPreview();
    });

    test('trocar de áudio solta do motor o que a pré-escuta carregou; fechar o painel solta tudo e cala', () async {
      final r = Rig();
      final x = r.serverOnly('x.wav', 0.1);
      final y = r.serverOnly('y.wav', 0.2);
      await r.b.refresh();
      await r.b.playPreview(r.entry(x));
      final idX = r.calls('preview_play').last[1] as int;
      await r.b.playPreview(r.entry(y));
      final idY = r.calls('preview_play').last[1] as int;
      expect(idY, isNot(idX));
      expect(r.calls('sample_drop'), [
        ['sample_drop', idX],
      ]);
      r.b.release();
      expect(r.calls('preview_stop'), hasLength(1));
      expect(r.calls('sample_drop').last, ['sample_drop', idY]);
      expect(r.b.phase, PreviewPhase.idle);
    });
  });

  group('inserir', () {
    test('na faixa de áudio selecionada, no cursor, num passo do desfazer', () async {
      final r = Rig();
      final hash = (await r.c.importSampleFile('kick.wav', audio(0.5)))!;
      r.c.seek(2);
      await r.b.insertAtCursor(r.entry(hash));
      final clips = r.c.doc.tracks.first.clips;
      expect(clips, hasLength(1));
      expect((clips.single.sample, clips.single.start), (hash, 2.0));
      expect(r.b.notice, contains('kick.wav'));
      expect(r.b.noticeIsError, isFalse);
      r.c.undo();
      expect(r.c.doc.tracks.first.clips, isEmpty);
    });

    test('um áudio só da conta é baixado, entra no projeto e fica neste aparelho', () async {
      final r = Rig();
      final hash = r.serverOnly('pad.wav', 0.3);
      await r.b.refresh();
      await r.b.insertAtCursor(r.entry(hash));
      expect(r.fetched, [hash]);
      expect(r.c.doc.samples.containsKey(hash), isTrue);
      expect(r.c.doc.tracks.first.clips.single.sample, hash);
      expect(r.c.decodedAudio(hash), isNotNull);
      expect(r.store.data.containsKey('sample:$hash'), isTrue);
    });

    test('faixa selecionada que não é de áudio: o clipe vai para uma faixa nova', () async {
      final r = Rig(
        tracks: [DawTrack(id: 's', name: 'Synth', color: 0, kind: TrackKind.synth)],
      );
      final hash = (await r.c.importSampleFile('kick.wav', audio(0.5)))!;
      r.c.selectTrack(0);
      await r.b.insertAtCursor(r.entry(hash));
      expect(r.c.doc.tracks, hasLength(2));
      expect(r.c.doc.tracks.last.kind, TrackKind.audio);
      expect(r.c.doc.tracks.last.clips.single.sample, hash);
    });

    test('sampler selecionado: vira zona, não clipe', () async {
      final r = Rig(
        tracks: [DawTrack(id: 's', name: 'Sampler', color: 0, kind: TrackKind.sampler)],
      );
      final hash = (await r.c.importSampleFile('kick.wav', audio(0.5)))!;
      r.c.selectTrack(0);
      await r.b.insertAtCursor(r.entry(hash));
      expect(r.c.doc.tracks.single.zones, hasLength(1));
      expect(r.c.doc.tracks.single.zones.single.sample, hash);
      expect(r.c.doc.tracks.single.clips, isEmpty);
      expect(r.b.notice, contains('zona do sampler'));
      r.c.undo();
      expect(r.c.doc.tracks.single.zones, isEmpty);
    });

    test('criar zona numa faixa que não é sampler: erro dito, nada muda', () async {
      final r = Rig();
      final hash = (await r.c.importSampleFile('kick.wav', audio(0.5)))!;
      expect(await r.b.addAsZone(r.entry(hash), 0), isFalse);
      expect(r.b.noticeIsError, isTrue);
      expect(r.b.notice, contains('sampler'));
    });

    test('soltar no arranjo: ponto da régua na grade, na faixa sob o ponteiro', () async {
      final r = Rig(
        tracks: [
          DawTrack(id: 'a', name: 'Áudio 1', color: 0),
          DawTrack(id: 'b', name: 'Áudio 2', color: 1),
        ],
      );
      final hash = (await r.c.importSampleFile('kick.wav', audio(0.5)))!;
      r.c.snap = Snap.beat;
      await r.b.dropOnTimeline(r.entry(hash), beat: 3.4, track: 1);
      expect(r.c.doc.tracks[0].clips, isEmpty);
      expect(r.c.doc.tracks[1].clips.single.start, 3.0);
    });

    test('soltar abaixo das faixas ou na frente de outro clipe cria uma faixa nova', () async {
      final r = Rig();
      final hash = (await r.c.importSampleFile('kick.wav', audio(0.5)))!;
      await r.b.dropOnTimeline(r.entry(hash), beat: 0, track: null);
      expect(r.c.doc.tracks, hasLength(2));
      expect(r.c.doc.tracks.last.clips.single.start, 0);
      // em cima do clipe que acabou de entrar na faixa 2 (a 2 s = 4 batidas a 120 bpm): outra faixa
      await r.b.dropOnTimeline(r.entry(hash), beat: 1, track: 1);
      expect(r.c.doc.tracks, hasLength(3));
    });

    test('soltar numa faixa de sampler cria a zona', () async {
      final r = Rig(
        tracks: [DawTrack(id: 's', name: 'Sampler', color: 0, kind: TrackKind.sampler)],
      );
      final hash = (await r.c.importSampleFile('kick.wav', audio(0.5)))!;
      await r.b.dropOnTimeline(r.entry(hash), beat: 4, track: 0);
      expect(r.c.doc.tracks.single.zones.single.sample, hash);
    });

    test('servidor sem o áudio: aviso e o projeto fica como estava', () async {
      final r = Rig();
      r.usage = const StorageUsage(
        quotaBytes: 1,
        usedBytes: 1,
        unusedBytes: 0,
        unusedCount: 0,
        samples: [StoredSample(hash: 'aaaa1111', name: 'sumiu.wav', size: 5)],
      );
      await r.b.refresh();
      expect(await r.b.insertAtCursor(r.entry('aaaa1111')), isFalse);
      expect(r.b.noticeIsError, isTrue);
      expect(r.c.doc.tracks.single.clips, isEmpty);
      expect(r.c.doc.samples, isEmpty);
    });

    test('baixar um áudio do projeto que faltava no aparelho o registra de volta', () async {
      final r = Rig();
      final bytes = audio(0.4);
      final hash = shaOf(bytes);
      r.server[hash] = bytes;
      r.c.doc.samples[hash] = const SampleInfo('volta.wav', 2);
      r.c.missing.add(hash);
      r.c.doc.tracks.first.clips.add(AudioClip(id: 'k', sample: hash, start: 0, length: 2));
      await r.b.refresh();
      expect(r.entry(hash).onDevice, isFalse);
      expect(await r.b.download(r.entry(hash)), isTrue);
      expect(r.c.missing.contains(hash), isFalse);
      expect(r.c.decodedAudio(hash), isNotNull);
      expect(r.entry(hash).onDevice, isTrue);
    });
  });

  group('painel', () {
    /// As teclas que chegaram à "tela" (o Focus com autofoco que o estúdio tem em volta de tudo).
    final keys = <LogicalKeyboardKey>[];

    /// Um campo de texto tem o foco (o EditableText se anuncia pelo rótulo do Focus dele).
    bool typing() {
      final w = FocusManager.instance.primaryFocus?.context?.widget;
      return w is Focus && w.debugLabel == 'EditableText';
    }

    Future<Rig> open(WidgetTester t, Size size, {int audios = 2}) async {
      keys.clear();
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final r = Rig();
      for (var i = 0; i < audios; i++) {
        await r.c.importSampleFile('projeto ${i + 1}.wav', audio(0.1 * (i + 1)));
      }
      r.serverOnly('Só na conta com um nome bem comprido para testar o corte do texto.wav', 0.7, projects: ['Outro projeto']);
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Focus(
              autofocus: true,
              onKeyEvent: (_, e) {
                if (e is KeyDownEvent) keys.add(e.logicalKey);
                return KeyEventResult.handled;
              },
              child: ExcludeFocus(
                child: BrowserPanel(c: r.c, browser: r.b),
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      addTearDown(() => r.b.release());
      return r;
    }

    for (final (label, size) in [('celular de 360 px', const Size(360, 640)), ('desktop de 1512 px', const Size(1512, 900))]) {
      testWidgets('$label: lista, busca e pré-escuta sem estourar o layout', (t) async {
        final r = await open(t, size);
        expect(find.text('projeto 1.wav'), findsOneWidget);
        expect(find.textContaining('Só na conta'), findsOneWidget);
        expect(find.text('fora deste aparelho'), findsOneWidget);
        expect(find.byKey(const ValueKey('browser-tempo')), findsOneWidget);

        // a busca funciona mesmo com o estúdio excluindo o foco dos botões
        await t.sendKeyEvent(LogicalKeyboardKey.space);
        expect(keys, [LogicalKeyboardKey.space], reason: 'a tela recebe as teclas enquanto ninguém digita');
        await t.tap(find.byKey(const ValueKey('browser-search')));
        await t.pump();
        expect(typing(), isTrue);
        await t.sendKeyEvent(LogicalKeyboardKey.keyK);
        expect(keys, [LogicalKeyboardKey.space], reason: 'digitando na busca, a tecla não vira atalho');
        await t.enterText(find.byKey(const ValueKey('browser-search')), 'projeto 2');
        await t.pump();
        expect(find.text('projeto 1.wav'), findsNothing);
        expect(find.text('projeto 2.wav'), findsOneWidget);
        await t.enterText(find.byKey(const ValueKey('browser-search')), 'nadaaqui');
        await t.pump();
        expect(find.textContaining('Nenhum áudio com'), findsOneWidget);
        await t.tap(find.byTooltip('Limpar a busca'));
        await t.pump();
        expect(find.text('projeto 1.wav'), findsOneWidget);
        // clicar fora larga o campo e as teclas voltam para a tela
        await t.tapAt(const Offset(2, 2));
        await t.pump();
        expect(typing(), isFalse);
        await t.sendKeyEvent(LogicalKeyboardKey.space);
        expect(keys, [LogicalKeyboardKey.space, LogicalKeyboardKey.space], reason: 'depois da busca, o Espaço volta a tocar');

        // pré-escuta: o botão vira parar e a barra aparece
        final hash = r.c.doc.samples.keys.first;
        await t.tap(find.byKey(ValueKey('browser-play-$hash')));
        await t.pump();
        await t.pump();
        expect(r.b.phase, PreviewPhase.playing);
        expect(find.byKey(const ValueKey('browser-seek')), findsOneWidget);
        expect(find.byTooltip('Parar a pré-escuta'), findsOneWidget);
        // tocar na barra ouve dali
        final seek = t.getRect(find.byKey(const ValueKey('browser-seek')));
        await t.tapAt(Offset(seek.left + seek.width * 0.5, seek.top + 6));
        await t.pump();
        await t.pump();
        expect(r.calls('preview_play').last[2], closeTo(1.0, 0.15));
        await t.tap(find.byTooltip('Parar a pré-escuta'));
        await t.pump();
        expect(r.b.phase, PreviewPhase.idle);
        expect(find.byKey(const ValueKey('browser-seek')), findsNothing);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(seconds: 2));
      });
    }

    testWidgets('inserir pelo botão e pelo menu; "baixar" só para o que está fora do aparelho', (t) async {
      final r = await open(t, const Size(1512, 900), audios: 1);
      final hash = r.c.doc.samples.keys.first;
      await t.tap(find.byKey(ValueKey('browser-insert-$hash')));
      await t.pumpAndSettle();
      expect(r.c.doc.tracks.first.clips.single.sample, hash);

      await t.tap(find.byKey(ValueKey('browser-menu-$hash')));
      await t.pumpAndSettle();
      expect(find.text('Baixar para este aparelho'), findsNothing);
      expect(find.text('Criar zona no sampler selecionado'), findsOneWidget);
      await t.tapAt(Offset.zero);
      await t.pumpAndSettle();

      final far = r.usage.samples.single.hash;
      await t.tap(find.byKey(ValueKey('browser-menu-$far')));
      await t.pumpAndSettle();
      await t.tap(find.text('Baixar para este aparelho'));
      await t.pumpAndSettle();
      expect(r.fetched, [far]);
      expect(find.text('fora deste aparelho'), findsNothing);
    });

    testWidgets('arrastar do navegador para o arranjo solta o clipe no ponto e na faixa', (t) async {
      t.view.physicalSize = const Size(1000, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final r = Rig(
        tracks: [
          DawTrack(id: 'a', name: 'Áudio 1', color: 0),
          DawTrack(id: 'b', name: 'Áudio 2', color: 1),
        ],
      );
      final hash = (await r.c.importSampleFile('kick.wav', audio(0.5)))!;
      r.c.snap = Snap.beat;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  height: 200,
                  child: BrowserDropZone(
                    c: r.c,
                    // duas linhas de 76 px
                    rowAt: (y) => y < 0 || y >= 152 ? null : (track: y ~/ 76, top: (y ~/ 76) * 76.0, height: 76.0),
                    child: const ColoredBox(color: Colors.black),
                  ),
                ),
                Expanded(
                  child: BrowserPanel(c: r.c, browser: r.b),
                ),
              ],
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      addTearDown(() => r.b.release());

      final handle = t.getCenter(find.byIcon(Icons.drag_indicator).first);
      final g = await t.startGesture(handle);
      await g.moveBy(const Offset(0, -40));
      await t.pump();
      // a faixa 2 (y entre 76 e 152), 100 px da esquerda = 100 / pxPerBeat batidas
      final zone = t.getTopLeft(find.byType(BrowserDropZone));
      await g.moveTo(zone + const Offset(100, 100));
      await t.pump();
      await g.up();
      await t.pumpAndSettle();

      expect(r.c.doc.tracks[0].clips, isEmpty);
      final clip = r.c.doc.tracks[1].clips.single;
      expect(clip.sample, hash);
      expect(clip.start, closeTo(r.c.snapBeat(r.c.scrollBeat + 100 / r.c.pxPerBeat), 1e-9));
      // o salvamento automático do documento
      await t.pump(const Duration(seconds: 1));
    });

    testWidgets('a aba Áudios do painel de baixo cabe em 360 px e o atalho abre e fecha', (t) async {
      t.view.physicalSize = const Size(360, 700);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final r = Rig();
      await r.c.importSampleFile('kick.wav', audio(0.5));
      AudioBrowser.use(r.c, r.b);
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(builder: (context) => DockPanel(c: r.c, available: 600, compact: true)),
          ),
        ),
      );
      expect(find.byType(BrowserPanel), findsNothing);
      toggleDock(r.c, Dock.browser);
      await t.pumpAndSettle();
      expect(find.byType(BrowserPanel), findsOneWidget);
      expect(find.text('kick.wav'), findsOneWidget);
      expect(find.text('Áudios do projeto e da conta'), findsOneWidget);
      expect(t.takeException(), isNull);
      toggleDock(r.c, Dock.browser);
      await t.pumpAndSettle();
      expect(find.byType(BrowserPanel), findsNothing);
    });
  });
}
