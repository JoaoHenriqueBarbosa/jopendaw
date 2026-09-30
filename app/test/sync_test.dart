import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:jopendaw_app/api/client.dart';
import 'package:jopendaw_app/api/sync_api.dart';
import 'package:jopendaw_app/daw/audio_to_midi.dart';
import 'package:jopendaw_app/daw/controller.dart';
import 'package:jopendaw_app/daw/export_options.dart';
import 'package:jopendaw_app/daw/instruments.dart';
import 'package:jopendaw_app/daw/model.dart';
import 'package:jopendaw_app/daw/sync.dart';
import 'package:jopendaw_app/daw/wav.dart';

import 'fake_engine.dart';
import 'fake_sync_api.dart';

Uint8List wav(double v) => encodeWav([Float32List.fromList(List.filled(200, v))], 100, ExportFormat.wav32f);
String hashOf(Uint8List b) => sha256.convert(b).toString();

/// Documento como o servidor o guarda (JSON), com uma faixa e, opcionalmente, um clipe de áudio.
Map<String, dynamic> docJson({String? sample, String track = 'Servidor', double bpm = 90}) {
  final d = DawDoc(
    bpm: bpm,
    beatsPerBar: 4,
    tracks: [
      DawTrack(
        id: 't1',
        name: track,
        color: 0,
        clips: sample == null ? [] : [AudioClip(id: 'c1', sample: sample, start: 0, length: 2)],
      ),
    ],
    samples: {?sample: SampleInfo('a.wav', 2)},
  );
  return jsonDecode(jsonEncode(d.toJson())) as Map<String, dynamic>;
}

/// Abre o controlador de verdade (local primeiro) com o servidor falso. O recuo e a espera do
/// envio ficam longos (escala 100): os testes disparam as rodadas na mão, sem timers no caminho.
Future<DawController> opened(FakeSyncApi api, MemoryStore store, {bool signedIn = true}) async {
  final c = fakeController(FakeEngine(), store: store, api: api, canSync: () => signedIn, syncTimeScale: 100);
  await c.open();
  await c.sync.starting;
  await idle(c);
  return c;
}

Future<void> idle(DawController c) async {
  while (c.sync.busy) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

/// Dá tempo ao salvamento local (400 ms) e roda uma rodada de sincronização.
Future<void> saveAndSync(DawController c) async {
  await Future<void>.delayed(const Duration(milliseconds: 450));
  await c.sync.syncNow();
  await idle(c);
}

MemoryStore storeWith({Map<String, dynamic>? local, int? version, bool dirty = false}) {
  final s = MemoryStore();
  if (local != null) s.data['doc:p'] = jsonEncode(local);
  if (version != null) s.data['sync:p'] = jsonEncode({'version': version, 'dirty': dirty});
  return s;
}

String trackName(DawController c) => c.doc.tracks.first.name;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('abrir', () {
    test('servidor mais novo e nada pendente: aplica, baixa os áudios e mantém o andamento do projeto', () async {
      final bytes = wav(0.3), h = hashOf(bytes);
      final api = FakeSyncApi()
        ..version = 2
        ..doc = docJson(sample: h)
        ..samples[h] = bytes;
      final store = storeWith(local: docJson(track: 'Local', bpm: 120), version: 1);
      final c = await opened(api, store);

      expect(trackName(c), 'Servidor');
      expect(c.doc.bpm, 120, reason: 'o andamento mora no projeto, não no documento do servidor');
      expect(c.missing, isEmpty);
      expect(c.waveforms, contains(h));
      expect(store.data['sample:$h'], isA<Uint8List>());
      expect(jsonDecode(store.data['doc:p'] as String)['tracks'][0]['name'], 'Servidor');
      expect(jsonDecode(store.data['sync:p'] as String), {'version': 2, 'dirty': false});
      expect(c.sync.phase, SyncPhase.synced);
      expect(c.canUndo, isFalse);
      expect(api.calls, ['doc', 'get_sample:$h']);
      c.dispose();
    });

    test('abre na hora com o local mesmo sem rede: o doc local fica e o estado é offline', () async {
      final api = FakeSyncApi()..failures = 1;
      final c = await opened(api, storeWith(local: docJson(track: 'Local', bpm: 120), version: 1));
      expect(trackName(c), 'Local');
      expect(c.ready, isTrue);
      expect(c.sync.phase, SyncPhase.offline);
      expect(c.sync.retryIn, const Duration(seconds: 2));
      c.dispose();
    });

    test('conflito: servidor mais novo com pendente local não sobrescreve nada', () async {
      final api = FakeSyncApi()
        ..version = 2
        ..doc = docJson();
      final store = storeWith(local: docJson(track: 'Local', bpm: 120), version: 1, dirty: true);
      final c = await opened(api, store);

      expect(c.sync.phase, SyncPhase.conflict);
      expect(c.sync.conflict!.version, 2);
      expect(trackName(c), 'Local');
      expect(jsonDecode(store.data['doc:p'] as String)['tracks'][0]['name'], 'Local');
      expect(api.calls, ['doc'], reason: 'nenhum envio enquanto a pessoa não escolhe');
      expect(api.doc!['tracks'][0]['name'], 'Servidor');
      c.dispose();
    });

    test('conflito: "usar a versão do servidor" descarta o local', () async {
      final api = FakeSyncApi()
        ..version = 2
        ..doc = docJson();
      final store = storeWith(local: docJson(track: 'Local', bpm: 120), version: 1, dirty: true);
      final c = await opened(api, store);
      await c.sync.useServer();

      expect(trackName(c), 'Servidor');
      expect(c.sync.phase, SyncPhase.synced);
      expect(c.sync.conflict, isNull);
      expect(jsonDecode(store.data['sync:p'] as String), {'version': 2, 'dirty': false});
      expect(jsonDecode(store.data['doc:p'] as String)['tracks'][0]['name'], 'Servidor');
      c.dispose();
    });

    test('conflito: "manter esta e enviar" usa a versão do servidor como base', () async {
      final api = FakeSyncApi()
        ..version = 2
        ..doc = docJson();
      final c = await opened(api, storeWith(local: docJson(track: 'Local', bpm: 120), version: 1, dirty: true));
      await c.sync.keepLocal();
      await idle(c);

      expect(api.calls.last, 'put_doc:2');
      expect(api.version, 3);
      expect(api.doc!['tracks'][0]['name'], 'Local');
      expect(c.sync.phase, SyncPhase.synced);
      expect(c.sync.hasPending, isFalse);
      c.dispose();
    });

    test('primeiro envio: servidor sem documento e local com conteúdo manda os áudios e depois o documento', () async {
      final bytes = wav(0.2), h = hashOf(bytes);
      final store = storeWith(
        local: docJson(sample: h, track: 'Local', bpm: 120),
      )..data['sample:$h'] = bytes;
      final api = FakeSyncApi();
      final c = await opened(api, store);

      expect(api.calls, ['doc', 'missing', 'put_sample:$h', 'put_doc:0']);
      expect(api.samples[h], bytes);
      expect(api.version, 1);
      expect(c.sync.phase, SyncPhase.synced);
      expect(jsonDecode(store.data['sync:p'] as String), {'version': 1, 'dirty': false});
      c.dispose();
    });

    test('projeto novo e vazio não vira pendente só por ter sido aberto e fechado', () async {
      final store = MemoryStore();
      final c = await opened(FakeSyncApi(), store);
      expect(c.sync.hasPending, isFalse);
      c.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final again = await opened(FakeSyncApi()..version = 1, store);
      expect(again.sync.phase, SyncPhase.synced, reason: 'sem pendente não há conflito com o servidor');
      again.dispose();
    });
  });

  group('envio', () {
    test('uma edição envia os áudios novos antes do documento, com a versão conhecida como base', () async {
      final api = FakeSyncApi()
        ..version = 1
        ..doc = docJson(track: 'Local', bpm: 120);
      final store = storeWith(local: docJson(track: 'Local', bpm: 120), version: 1);
      final c = await opened(api, store);
      expect(api.calls, ['doc']);

      await c.importBytes([('nova.wav', wav(0.5))]);
      final h = hashOf(wav(0.5));
      await saveAndSync(c);

      expect(api.calls.sublist(1), ['missing', 'put_sample:$h', 'put_doc:1']);
      expect(api.doc!['samples'], contains(h));
      expect(c.sync.phase, SyncPhase.synced);
      expect(jsonDecode(store.data['sync:p'] as String), {'version': 2, 'dirty': false});
      c.dispose();
    });

    test('409 no envio vira conflito e não perde o local; manter e enviar usa a versão nova como base', () async {
      final api = FakeSyncApi()
        ..version = 1
        ..doc = docJson(track: 'Local', bpm: 120);
      final c = await opened(api, storeWith(local: docJson(track: 'Local', bpm: 120), version: 1));
      api.conflictNext = ServerDoc(7, docJson(track: 'Outro'));

      c.addTrack();
      await saveAndSync(c);

      expect(c.sync.phase, SyncPhase.conflict);
      expect(c.sync.conflict!.version, 7);
      expect(c.doc.tracks.length, 2);
      expect(c.sync.hasPending, isTrue);

      api.version = 7;
      await c.sync.keepLocal();
      await idle(c);
      expect(api.calls.last, 'put_doc:7');
      expect(api.doc!['tracks'], hasLength(2));
      expect(c.sync.phase, SyncPhase.synced);
      c.dispose();
    });

    test('sem rede ou com 5xx: recuo de 2, 4, 8 s até 2 min, nunca lança, e volta sozinho', () async {
      final api = FakeSyncApi()
        ..version = 1
        ..doc = docJson(track: 'Local', bpm: 120);
      final c = await opened(api, storeWith(local: docJson(track: 'Local', bpm: 120), version: 1));

      c.addTrack();
      await Future<void>.delayed(const Duration(milliseconds: 450));
      api.failures = 10;
      final delays = <int>[];
      for (var i = 0; i < 10; i++) {
        // a cada falha alterna o tipo: sem rede e servidor fora
        api.failure = i.isEven ? http.ClientException('sem rede') : ApiException(503, 'fora');
        await c.sync.syncNow();
        await idle(c);
        expect(c.sync.phase, SyncPhase.offline);
        delays.add(c.sync.retryIn!.inSeconds);
      }
      expect(delays, [2, 4, 8, 16, 32, 64, 120, 120, 120, 120]);
      expect(c.doc.tracks.length, 2, reason: 'o trabalho local segue intacto');

      await c.sync.syncNow();
      await idle(c);
      expect(c.sync.phase, SyncPhase.synced);
      expect(c.sync.retryIn, isNull);
      expect(api.doc!['tracks'], hasLength(2));
      c.dispose();
    });

    test('sem usuário autenticado nada vai ao servidor, mas o pendente fica guardado', () async {
      final api = FakeSyncApi();
      final store = storeWith(local: docJson(track: 'Local', bpm: 120), version: 1);
      final c = await opened(api, store, signedIn: false);
      c.addTrack();
      await saveAndSync(c);

      expect(api.calls, isEmpty);
      expect(c.sync.phase, SyncPhase.off);
      expect(jsonDecode(store.data['sync:p'] as String)['dirty'], isTrue);
      c.dispose();
    });

    test('áudio recusado (cota) não trava o documento: ele segue e o erro aparece no estado', () async {
      final bytes = wav(0.4), h = hashOf(bytes);
      final store = storeWith(
        local: docJson(sample: h, track: 'Local', bpm: 120),
      )..data['sample:$h'] = bytes;
      final api = _QuotaApi();
      final c = await opened(api, store);
      expect(api.calls, contains('put_doc:0'));
      expect(c.sync.phase, SyncPhase.error);
      expect(c.sync.message, contains('cota'));
      c.dispose();
    });
  });

  group('áudio para MIDI', () {
    test('notas em segundos viram batidas, respeitam o offset do clipe e o que passa do fim é cortado', () {
      // 120 bpm: 2 batidas por segundo; o clipe toca de 1 s a 3 s do arquivo
      final clip = AudioClip(id: 'c', sample: 'h', start: 4, offset: 1, length: 2);
      final r = ConvertedNotes.fromJson({
        'notes': [
          {'pitch': 60, 'start': 0.5, 'length': 1.0, 'velocity': 0.9}, // começa antes do offset: aparada
          {'pitch': 62, 'start': 1.5, 'length': 0.5, 'velocity': 0.5},
          {'pitch': 64, 'start': 2.5, 'length': 1.0, 'velocity': 0.7}, // passa do fim: cortada em 3 s
          {'pitch': 65, 'start': 3.0, 'length': 1.0, 'velocity': 0.7}, // depois do fim: descartada
          {'pitch': 67, 'start': 0.0, 'length': 0.5, 'velocity': 0.7}, // antes do offset: descartada
        ],
        'duration': 5,
      });
      final notes = notesForClip(r, clip, 120);
      expect([for (final n in notes) n.pitch], [60, 62, 64]);
      expect([for (final n in notes) n.start], [0.0, 1.0, 3.0]);
      expect([for (final n in notes) n.length], [1.0, 1.0, 1.0]);
      expect(notes.map((n) => n.velocity), [0.9, 0.5, 0.7]);
    });

    Future<(DawController, FakeSyncApi, MemoryStore)> withClip({bool signedIn = true}) async {
      final bytes = wav(0.6), h = hashOf(bytes);
      final store = MemoryStore()..data['sample:$h'] = bytes;
      final api = FakeSyncApi()
        ..script = [
          const SyncJob('j1', JobStatus.queued),
          const SyncJob('j1', JobStatus.running, progress: 0.5),
          SyncJob.fromJson({
            'id': 'j1',
            'kind': 'audio_to_midi',
            'status': 'done',
            'progress': 1,
            'result': {
              'notes': [
                {'pitch': 60, 'start': 0.5, 'length': 1.0, 'velocity': 0.9},
                {'pitch': 62, 'start': 1.5, 'length': 0.5, 'velocity': 0.5},
                {'pitch': 64, 'start': 2.5, 'length': 1.0, 'velocity': 0.7},
              ],
              'duration': 4,
            },
          }),
        ];
      final c = fakeController(
        FakeEngine(),
        store: store,
        api: api,
        canSync: () => signedIn,
        tracks: [
          DawTrack(
            id: 'a',
            name: 'Áudio 1',
            color: 0,
            clips: [AudioClip(id: 'c1', sample: h, start: 4, offset: 1, length: 2)],
          ),
        ],
      );
      return (c, api, store);
    }

    test('converter cria faixa de sintetizador com o clipe MIDI sobre o de áudio, num passo do desfazer', () async {
      final (c, api, _) = await withClip();
      final stages = <String>[];
      final n = await c.convertToMidi('c1', pollEvery: Duration.zero, onProgress: (s, p) => stages.add(s));

      expect(n, 3);
      expect(api.calls.indexWhere((x) => x.startsWith('put_sample')), lessThan(api.calls.indexOf('job:audio_to_midi')), reason: 'o áudio sobe antes do job');
      expect(api.jobsCreated.single.$1, 'audio_to_midi');
      expect(stages, containsAll(['Enviando o áudio…', 'Na fila do servidor…', 'Analisando o áudio…']));
      expect(c.doc.tracks, hasLength(2));
      final t = c.doc.tracks[1];
      expect(t.kind, TrackKind.synth);
      expect(t.name, 'Sintetizador 1');
      final clip = t.midi.single;
      expect(clip.start, 4);
      expect(clip.length, 4, reason: '2 s a 120 bpm');
      expect([for (final x in clip.notes) (x.pitch, x.start, x.length)], [(60, 0.0, 1.0), (62, 1.0, 1.0), (64, 3.0, 1.0)]);
      expect(c.selectedClip, clip.id);

      c.undo();
      expect(c.doc.tracks, hasLength(1), reason: 'faixa e clipe saem no mesmo passo');
    });

    test('job que falha vira mensagem, sem criar nada', () async {
      final (c, api, _) = await withClip();
      api.script = [const SyncJob('j1', JobStatus.failed, error: 'não achei afinação')];
      await expectLater(c.convertToMidi('c1', pollEvery: Duration.zero), throwsA(isA<StateError>().having((e) => e.message, 'message', contains('afinação'))));
      expect(c.doc.tracks, hasLength(1));
    });

    test('cancelar interrompe o acompanhamento e não cria nada', () async {
      final (c, _, _) = await withClip();
      await expectLater(c.convertToMidi('c1', pollEvery: Duration.zero, isCancelled: () => true), throwsA(isA<ConversionCancelled>()));
      expect(c.doc.tracks, hasLength(1));
    });

    test('sem sessão não converte', () async {
      final (c, api, _) = await withClip(signedIn: false);
      await expectLater(c.convertToMidi('c1', pollEvery: Duration.zero), throwsA(isA<StateError>()));
      expect(api.calls, isEmpty);
    });
  });
}

/// Servidor que recusa todo envio de áudio por cota (413).
class _QuotaApi extends FakeSyncApi {
  @override
  Future<void> putSample(String hash, Uint8List bytes) async {
    calls.add('put_sample:$hash');
    throw ApiException(413, 'cota de armazenamento estourada');
  }
}
