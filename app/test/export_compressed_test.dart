import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:jopendaw_app/api/client.dart' show ApiException, Unauthenticated;
import 'package:jopendaw_app/api/export_api.dart';
import 'package:jopendaw_app/api/sync_api.dart';
import 'package:jopendaw_app/audio/engine.dart' show RenderCanceled;
import 'package:jopendaw_app/daw/export.dart';
import 'package:jopendaw_app/daw/export_compressed.dart';
import 'package:jopendaw_app/daw/export_options.dart';
import 'package:jopendaw_app/daw/wav.dart';

import 'export_test.dart' show filled, project;
import 'fake_engine.dart';

/// Servidor de mentira da exportação: guarda os áudios, roda um roteiro de tarefas e anota cada chamada.
class FakeExportApi implements ExportApi {
  final samples = <String, Uint8List>{};
  final calls = <String>[];
  final created = <(String, Map<String, dynamic>)>[];
  final encoded = Uint8List.fromList([0x66, 0x4C, 0x61, 0x43, 1, 2, 3]);
  static final outHash = 'b' * 64;

  /// O que cada `job()` devolve, em ordem (o último se repete). Vazio: uma tarefa que termina de primeira.
  List<SyncJob> script = [];
  int _polled = 0;

  /// Lança na chamada cujo nome (`missing`, `put`, `create`, `job`, `get`) devolver não nulo.
  Object? Function(String call)? fail;

  void _maybeFail(String call) {
    calls.add(call);
    final e = fail?.call(call);
    if (e != null) throw e;
  }

  SyncJob get _done => SyncJob('j1', JobStatus.done, progress: 1, result: {'sample': outHash, 'warnings': <String>[], 'filename': 'x'});

  @override
  Future<Set<String>> missingSamples(List<String> hashes) async {
    _maybeFail('missing');
    return {
      for (final h in hashes)
        if (!samples.containsKey(h)) h,
    };
  }

  @override
  Future<void> putSample(String hash, Uint8List bytes) async {
    _maybeFail('put');
    samples[hash] = bytes;
  }

  @override
  Future<Uint8List?> getSample(String hash) async {
    _maybeFail('get');
    return hash == outHash ? encoded : samples[hash];
  }

  @override
  Future<SyncJob> createJob(String kind, String sample, [Map<String, dynamic> params = const {}]) async {
    _maybeFail('create');
    created.add((sample, params));
    return script.isEmpty ? _done : SyncJob('j1', JobStatus.queued);
  }

  @override
  Future<SyncJob> job(String id) async {
    _maybeFail('job');
    if (script.isEmpty) return _done;
    return script[_polled < script.length ? _polled++ : script.length - 1];
  }

  @override
  Future<int> deleteSample(String hash, {bool force = false}) async {
    calls.add('delete_sample:${hash == outHash ? 'result' : 'wav'}:$force');
    samples.remove(hash);
    return 1;
  }

  @override
  Future<void> deleteJob(String id) async => calls.add('delete_job');
}

CompressedExport make(FakeExportApi api, List<(String, Uint8List, String)> saved, {ExportOptions? options, bool signedIn = true, int files = 1}) =>
    CompressedExport(
      api: api,
      options: options ?? const ExportOptions(format: ExportFormat.flac),
      album: 'Projeto',
      expectedFiles: files,
      save: (n, b, m) async {
        saved.add((n, b, m));
        return true;
      },
      signedIn: () => signedIn,
      delay: (_) async {},
    );

Uint8List wav([int n = 200]) => encodeWav([filled(n, 0.25)], 100, ExportFormat.wav16);

void main() {
  group('opções', () {
    test('o WAV renderizado acompanha o formato compactado', () {
      expect(const ExportOptions().renderFormat, ExportFormat.wav24);
      expect(const ExportOptions(format: ExportFormat.wav32f).renderFormat, ExportFormat.wav32f);
      expect(const ExportOptions(format: ExportFormat.flac).renderFormat, ExportFormat.wav24);
      expect(const ExportOptions(format: ExportFormat.flac, flacBits: 16).renderFormat, ExportFormat.wav16);
      expect(const ExportOptions(format: ExportFormat.mp3).renderFormat, ExportFormat.wav16);
    });

    test('parâmetros da tarefa: FLAC, MP3 CBR e VBR', () {
      expect(const ExportOptions(format: ExportFormat.flac, flacBits: 16, flacLevel: FlacLevel.smallest).encodeParams, {
        'format': 'flac',
        'bits': 16,
        'level': 8,
      });
      expect(const ExportOptions(format: ExportFormat.flac).encodeParams, {'format': 'flac', 'bits': 24, 'level': 5});
      expect(const ExportOptions(format: ExportFormat.mp3, mp3Quality: Mp3Quality.cbr320).encodeParams, {'format': 'mp3', 'bitrate': 320});
      expect(const ExportOptions(format: ExportFormat.mp3, mp3Quality: Mp3Quality.vbr0).encodeParams, {'format': 'mp3', 'vbr': 0});
      expect([for (final q in Mp3Quality.values.where((q) => q.vbr != null)) q.vbr], [0, 1, 2, 3, 4]);
      expect([for (final q in Mp3Quality.values.where((q) => q.bitrate != null)) q.bitrate], [128, 192, 256, 320]);
    });

    test('extensão e MIME de cada formato', () {
      expect([for (final f in ExportFormat.values) f.extension], ['wav', 'wav', 'wav', 'flac', 'mp3']);
      expect(ExportFormat.mp3.mime, 'audio/mpeg');
      expect(ExportFormat.flac.mime, 'audio/flac');
      expect(ExportFormat.values.where((f) => f.compressed), [ExportFormat.flac, ExportFormat.mp3]);
      expect(compressedName('Meu - Baixo.wav', ExportFormat.mp3), 'Meu - Baixo.mp3');
    });
  });

  group('compactar pelo servidor', () {
    test('sucesso: sobe, cria a tarefa, baixa, salva com a extensão certa e apaga os dois áudios e a tarefa', () async {
      final api = FakeExportApi()
        ..script = [
          SyncJob('j1', JobStatus.running, progress: 0.4),
          SyncJob(
            'j1',
            JobStatus.done,
            progress: 1,
            result: {
              'sample': FakeExportApi.outHash,
              'warnings': ['aviso de perda'],
            },
          ),
        ];
      final saved = <(String, Uint8List, String)>[];
      final cx = make(
        api,
        saved,
        options: const ExportOptions(format: ExportFormat.mp3, mp3Quality: Mp3Quality.vbr2),
      );
      final w = wav();
      await cx.deliver('Projeto.wav', w);
      final hash = sha256.convert(w).toString();
      expect(api.created.single.$1, hash);
      expect(api.created.single.$2, {'format': 'mp3', 'vbr': 2, 'title': 'Projeto', 'album': 'Projeto'});
      expect(saved.single.$1, 'Projeto.mp3');
      expect(saved.single.$2, api.encoded);
      expect(saved.single.$3, 'audio/mpeg');
      expect(cx.compressed, 1);
      expect(cx.fallbacks, isEmpty);
      expect(cx.failure, isNull);
      expect(cx.warnings, ['aviso de perda']);
      expect(api.calls.where((c) => c.startsWith('delete')), ['delete_sample:result:true', 'delete_job', 'delete_sample:wav:true']);
      expect(api.samples, isEmpty, reason: 'o WAV temporário saiu do servidor');
    });

    test('FLAC leva bits e nível, e o WAV que já estava na conta não é apagado', () async {
      final api = FakeExportApi();
      final w = wav();
      api.samples[sha256.convert(w).toString()] = w;
      final saved = <(String, Uint8List, String)>[];
      final cx = make(
        api,
        saved,
        options: const ExportOptions(format: ExportFormat.flac, flacBits: 16, flacLevel: FlacLevel.fast),
      );
      await cx.deliver('A.wav', w);
      expect(api.created.single.$2['bits'], 16);
      expect(api.created.single.$2['level'], 2);
      expect(saved.single.$1, 'A.flac');
      expect(saved.single.$3, 'audio/flac');
      expect(api.calls, isNot(contains('put')));
      expect(api.calls, isNot(contains('delete_sample:wav:true')));
      expect(api.samples, isNotEmpty);
    });

    test('stems: um job por arquivo, em série', () async {
      final api = FakeExportApi();
      final saved = <(String, Uint8List, String)>[];
      final cx = make(api, saved, files: 3);
      await cx.deliver('P.wav', wav(100));
      await cx.deliver('P - Baixo.wav', wav(120));
      await cx.deliver('P - Voz.wav', wav(140));
      expect([for (final s in saved) s.$1], ['P.flac', 'P - Baixo.flac', 'P - Voz.flac']);
      expect(api.created.length, 3);
      expect(cx.compressed, 3);
      expect(cx.fraction, lessThan(1));
    });

    test('sem sessão: nada vai à rede e o WAV fica guardado para a queda', () async {
      final api = FakeExportApi();
      final saved = <(String, Uint8List, String)>[];
      final cx = make(api, saved, signedIn: false);
      final w = wav();
      await cx.deliver('P.wav', w);
      expect(api.calls, isEmpty);
      expect(cx.failure, contains('Entre na sua conta'));
      expect(cx.fallbacks.single.name, 'P.wav');
      expect(cx.fallbacks.single.bytes, w);
      expect(saved, isEmpty);
      // "Exportar em WAV mesmo assim": salva o WAV já renderizado, com a extensão e o MIME de WAV
      expect(await cx.saveWavs(), 1);
      expect(saved.single, ('P.wav', w, 'audio/wav'));
      expect(cx.fallbacks, isEmpty);
    });

    test('offline (falha de rede): cai para WAV e os stems seguintes nem tentam a rede', () async {
      final api = FakeExportApi()..fail = (c) => http.ClientException('sem rede');
      final saved = <(String, Uint8List, String)>[];
      final cx = make(api, saved, files: 2);
      await cx.deliver('P.wav', wav(100));
      final calls = api.calls.length;
      await cx.deliver('P - Baixo.wav', wav(120));
      expect(api.calls.length, calls, reason: 'depois da primeira falha não tenta de novo');
      expect(cx.failure, contains('sem conexão'));
      expect(cx.fallbacks.map((f) => f.name), ['P.wav', 'P - Baixo.wav']);
      expect(cx.compressed, 0);
      await cx.saveWavs();
      expect(saved.map((s) => s.$1), ['P.wav', 'P - Baixo.wav']);
    });

    test('erro do job: mostra a mensagem do servidor e mantém o WAV', () async {
      final api = FakeExportApi()..script = [SyncJob('j1', JobStatus.failed, error: 'MP3 exige 44,1 ou 48 kHz e o áudio tem 22050 Hz')];
      final saved = <(String, Uint8List, String)>[];
      final cx = make(api, saved, options: const ExportOptions(format: ExportFormat.mp3));
      await cx.deliver('P.wav', wav());
      expect(cx.failure, 'MP3 exige 44,1 ou 48 kHz e o áudio tem 22050 Hz');
      expect(cx.fallbacks, hasLength(1));
      expect(saved, isEmpty);
      // o WAV temporário e a tarefa saem do servidor mesmo assim
      expect(api.calls, containsAll(['delete_job', 'delete_sample:wav:true']));
    });

    test('erro do servidor (cota, sessão) vira motivo em português', () async {
      var api = FakeExportApi()
        ..fail = (c) => c == 'put' ? ApiException(413, 'cota de armazenamento de 4 GB excedida; apague áudios sem uso na tela Conta') : null;
      var cx = make(api, []);
      await cx.deliver('P.wav', wav());
      expect(cx.failure, contains('tela Conta'));
      api = FakeExportApi()..fail = (c) => c == 'create' ? Unauthenticated() : null;
      cx = make(api, []);
      await cx.deliver('P.wav', wav());
      expect(cx.failure, contains('sessão terminou'));
    });

    test('a falha ao apagar é silenciosa', () async {
      final api = FakeExportApi()..fail = (c) => null;
      final saved = <(String, Uint8List, String)>[];
      final failing = _NoDelete(api);
      final cx = CompressedExport(
        api: failing,
        options: const ExportOptions(),
        album: '',
        save: (n, b, m) async {
          saved.add((n, b, m));
          return true;
        },
        signedIn: () => true,
        delay: (_) async {},
      );
      await cx.deliver('P.wav', wav());
      expect(cx.compressed, 1);
      expect(cx.failure, isNull);
    });

    test('tropeço de rede na espera é tolerado; três seguidos derrubam', () async {
      var n = 0;
      var api = FakeExportApi()
        ..script = [SyncJob('j1', JobStatus.running)]
        ..fail = (c) => c == 'job' && ++n <= 2 ? http.ClientException('x') : null;
      // depois de dois tropeços o roteiro só devolve "rodando": termina por tempo
      var cx = CompressedExport(
        api: api,
        options: const ExportOptions(),
        album: '',
        save: (n, b, m) async => true,
        signedIn: () => true,
        delay: (_) async {},
        maxWait: Duration.zero,
      );
      await cx.deliver('P.wav', wav());
      expect(cx.failure, contains('demorou demais'));

      api = FakeExportApi()
        ..script = [SyncJob('j1', JobStatus.running)]
        ..fail = (c) => c == 'job' ? http.ClientException('x') : null;
      cx = make(api, []);
      await cx.deliver('P.wav', wav());
      expect(cx.failure, contains('sem conexão'));
      expect(api.calls.where((c) => c == 'job').length, 3);
    });

    test('cancelar: para a espera, não salva nada e tenta limpar', () async {
      final api = FakeExportApi()..script = [SyncJob('j1', JobStatus.running, progress: 0.2)];
      final saved = <(String, Uint8List, String)>[];
      late CompressedExport cx;
      cx = CompressedExport(
        api: api,
        options: const ExportOptions(),
        album: '',
        save: (n, b, m) async {
          saved.add((n, b, m));
          return true;
        },
        signedIn: () => true,
        delay: (_) async => cx.cancel(),
      );
      await expectLater(cx.deliver('P.wav', wav()), throwsA(isA<RenderCanceled>()));
      expect(saved, isEmpty);
      expect(cx.fallbacks, isEmpty);
      expect(api.calls, contains('delete_job'));
    });
  });

  group('janela de exportação', () {
    Future<(FakeEngine, FakeExportApi, dynamic)> open(WidgetTester tester, {ExportOptions? options, FakeExportApi? api, bool signedIn = true}) async {
      final e = FakeEngine();
      final c = (await tester.runAsync(() => project(e)))!;
      e.renderResult = (outputs) => [
        for (final _ in outputs) [filled(300, 0.5), filled(300, -0.25)],
      ];
      final a = api ?? FakeExportApi();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExportProgressDialog(
              c: c,
              options: options ?? const ExportOptions(format: ExportFormat.flac),
              api: a,
              signedIn: () => signedIn,
            ),
          ),
        ),
      );
      return (e, a, c);
    }

    testWidgets('FLAC com sucesso: o arquivo compactado é salvo e o WAV não', (tester) async {
      final (e, api, _) = await open(tester);
      await tester.pumpAndSettle();
      expect(find.text('Exportação concluída'), findsOneWidget);
      expect(e.saved.map((s) => s.$1), ['Teste.flac']);
      expect(e.saved.single.$3, 'audio/flac');
      expect(api.created.length, 1);
      expect(find.byKey(const Key('export-wav-anyway')), findsNothing);
    });

    testWidgets('sem sessão: oferece WAV mesmo assim e salva o WAV já renderizado, sem renderizar de novo', (tester) async {
      final (e, api, _) = await open(tester, signedIn: false);
      await tester.pumpAndSettle();
      expect(find.text('Não deu para compactar'), findsOneWidget);
      expect(find.textContaining('Entre na sua conta'), findsOneWidget);
      expect(e.saved, isEmpty);
      expect(api.calls, isEmpty);
      final renders = e.renders.length;
      await tester.tap(find.byKey(const Key('export-wav-anyway')));
      await tester.pumpAndSettle();
      expect(find.text('Exportação concluída'), findsOneWidget);
      expect(e.saved.map((s) => s.$1), ['Teste.wav']);
      expect(e.saved.single.$3, 'audio/wav');
      expect(e.renders.length, renders);
    });

    testWidgets('erro do job: a mensagem do servidor aparece dentro da janela', (tester) async {
      final api = FakeExportApi()..script = [SyncJob('j1', JobStatus.failed, error: 'áudio vazio')];
      final (e, _, _) = await open(
        tester,
        api: api,
        options: const ExportOptions(format: ExportFormat.mp3),
      );
      // a espera entre consultas é um Timer, que o pumpAndSettle não enxerga
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.textContaining('áudio vazio'), findsOneWidget);
      expect(find.text('Exportar em WAV mesmo assim'), findsOneWidget);
      expect(e.saved, isEmpty);
    });

    testWidgets('stems em FLAC: um job por arquivo', (tester) async {
      final (e, api, _) = await open(tester, options: const ExportOptions(format: ExportFormat.flac, stems: true));
      await tester.pumpAndSettle();
      expect(e.saved.every((s) => s.$1.endsWith('.flac')), isTrue);
      expect(api.created.length, e.saved.length);
      expect(e.saved.length, greaterThan(1));
    });

    testWidgets('cancelar durante a espera do servidor fecha sem salvar', (tester) async {
      final api = FakeExportApi()..script = [SyncJob('j1', JobStatus.running, progress: 0.3)];
      final (e, _, _) = await open(tester, api: api);
      await tester.pump(const Duration(seconds: 2));
      expect(find.textContaining('Compactando no servidor'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(e.saved, isEmpty);
      expect(find.text('Exportando…'), findsNothing);
    });
  });
}

/// O mesmo servidor, mas apagar sempre falha.
class _NoDelete implements ExportApi {
  final FakeExportApi inner;
  _NoDelete(this.inner);
  @override
  Future<Set<String>> missingSamples(List<String> h) => inner.missingSamples(h);
  @override
  Future<void> putSample(String h, Uint8List b) => inner.putSample(h, b);
  @override
  Future<Uint8List?> getSample(String h) => inner.getSample(h);
  @override
  Future<SyncJob> createJob(String k, String s, [Map<String, dynamic> p = const {}]) => inner.createJob(k, s, p);
  @override
  Future<SyncJob> job(String id) => inner.job(id);
  @override
  Future<int> deleteSample(String hash, {bool force = false}) => throw http.ClientException('sem rede');
  @override
  Future<void> deleteJob(String id) => throw http.ClientException('sem rede');
}
