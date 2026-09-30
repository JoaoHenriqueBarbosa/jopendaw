import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jopendaw_app/api/client.dart';
import 'package:jopendaw_app/api/sync_api.dart';
import 'package:jopendaw_app/daw/audio_to_midi.dart';
import 'package:jopendaw_app/daw/clip_gain_dialog.dart';
import 'package:jopendaw_app/daw/controller.dart';
import 'package:jopendaw_app/daw/local_purge.dart';
import 'package:jopendaw_app/daw/model.dart';
import 'package:jopendaw_app/daw/sync.dart';
import 'package:jopendaw_app/models/project.dart';
import 'package:jopendaw_app/screens/project_screen.dart';

import 'fake_engine.dart';
import 'fake_sync_api.dart';

Map<String, dynamic> docWith({String track = 'Local', double bpm = 120, int beatsPerBar = 4}) => jsonDecode(
  jsonEncode(
    DawDoc(
      bpm: bpm,
      beatsPerBar: beatsPerBar,
      tracks: [DawTrack(id: 't1', name: track, color: 0)],
    ).toJson(),
  ),
);

Future<DawController> opened(FakeSyncApi api, MemoryStore store, {Future<void> Function(String, Map<String, dynamic>)? patch}) async {
  final c = fakeController(FakeEngine(), store: store, api: api, canSync: () => true, syncTimeScale: 100, patchProject: patch);
  await c.open();
  await c.sync.starting;
  while (c.sync.busy) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  return c;
}

const _save = Duration(milliseconds: 450);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('andamento é do documento', () {
    test('PATCH offline não lança, fica pendente e sai de novo no refazer; o desfazer para o valor espelhado não reenvia', () async {
      final sent = <Map<String, dynamic>>[];
      var online = false;
      final c = fakeController(
        FakeEngine(),
        canSync: () => true,
        patchProject: (id, p) async {
          if (!online) throw ApiException(0, 'sem rede');
          sent.add(p);
        },
      );
      await c.setTempo(140, 3);
      expect(c.doc.bpm, 140);
      expect(c.doc.beatsPerBar, 3);
      expect(c.tempoPending, isTrue);
      expect(sent, isEmpty);

      online = true;
      c.undo(); // volta a 120 4/4: é o que o servidor já tem
      await Future<void>.delayed(_save);
      expect(c.tempoPending, isFalse);
      expect(sent, isEmpty);

      c.redo(); // 140 3/4 de novo: o salvamento reenvia
      await Future<void>.delayed(_save);
      expect(sent, [
        {'bpm': 140, 'beats_per_bar': 3},
      ]);
      expect(c.tempoPending, isFalse);

      c.undo();
      await Future<void>.delayed(_save);
      expect(sent.last, {'bpm': 120, 'beats_per_bar': 4});
      c.dispose();
    });

    test('reenvia quando a sincronização volta a dar certo', () async {
      final sent = <Map<String, dynamic>>[];
      var online = false;
      final api = FakeSyncApi()
        ..version = 1
        ..doc = docWith();
      final c = await opened(
        api,
        MemoryStore()
          ..data['doc:p'] = jsonEncode(docWith())
          ..data['sync:p'] = jsonEncode({'version': 1, 'dirty': false}),
        patch: (id, p) async {
          if (!online) throw ApiException(0, 'sem rede');
          sent.add(p);
        },
      );
      await c.setTempo(100, 4);
      expect(c.tempoPending, isTrue);
      online = true;
      await Future<void>.delayed(_save);
      // a rodada de sincronização (envia o documento) termina em "sincronizado" e reenvia o espelho
      await c.sync.syncNow();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(sent, isNotEmpty);
      expect(sent.last['bpm'], 100);
      c.dispose();
    });

    test('ao reabrir, vale o andamento do documento local, não o do servidor carregado', () async {
      final store = MemoryStore()..data['doc:p'] = jsonEncode(docWith(bpm: 93, beatsPerBar: 5));
      final c = await opened(FakeSyncApi(), store);
      expect(c.doc.bpm, 93);
      expect(c.doc.beatsPerBar, 5);
      c.dispose();
    });

    test('subtítulo reflete o documento vivo', () {
      final p = Project.fromJson({
        'id': 'p',
        'name': 'x',
        'bpm': 120,
        'beats_per_bar': 4,
        'beat_unit': 4,
        'sample_rate': 48000,
        'created_at': '2026-01-01T00:00:00Z',
        'updated_at': '2026-01-01T00:00:00Z',
      });
      expect(projectSubtitle(p, null), '120 BPM · 4/4');
      expect(projectSubtitle(p, DawDoc(bpm: 97.5, beatsPerBar: 3, tracks: [])), '97.5 BPM · 3/4');
    });
  });

  group('sincronização', () {
    test('409 contra o próprio documento (resposta perdida) resolve em silêncio, mesmo com chaves em outra ordem', () async {
      final api = FakeSyncApi()
        ..version = 1
        ..doc = docWith();
      final c = await opened(
        api,
        MemoryStore()
          ..data['doc:p'] = jsonEncode(docWith())
          ..data['sync:p'] = jsonEncode({'version': 1, 'dirty': false}),
      );
      c.addTrack();
      final mine = jsonDecode(jsonEncode(c.doc.toJson())) as Map<String, dynamic>;
      // o servidor guarda o mesmo documento (JSONB reordena as chaves)
      api.conflictNext = ServerDoc(5, Map.fromEntries(mine.entries.toList().reversed));
      await Future<void>.delayed(_save);
      await c.sync.syncNow();
      while (c.sync.busy) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      expect(c.sync.phase, SyncPhase.synced);
      expect(c.sync.conflict, isNull);
      expect(c.sync.knownVersion, 5);
      expect(c.sync.hasPending, isFalse);
      c.dispose();
    });

    test('jsonEquals compara por estrutura', () {
      expect(
        jsonEquals(
          {
            'a': 1,
            'b': [1.0, 2],
          },
          {
            'b': [1, 2.0],
            'a': 1.0,
          },
        ),
        isTrue,
      );
      expect(jsonEquals({'a': 1}, {'a': 2}), isFalse);
      expect(jsonEquals([1], [1, 2]), isFalse);
    });

    test('pull periódico traz a edição de outro aparelho quando nada está pendente', () async {
      final api = FakeSyncApi()
        ..version = 1
        ..doc = docWith();
      final c = await opened(
        api,
        MemoryStore()
          ..data['doc:p'] = jsonEncode(docWith())
          ..data['sync:p'] = jsonEncode({'version': 1, 'dirty': false}),
      );
      expect(c.doc.tracks.first.name, 'Local');
      api.version = 2;
      api.doc = docWith(track: 'Do outro aparelho');
      expect(await c.sync.pullNow(), isTrue);
      expect(c.doc.tracks.first.name, 'Do outro aparelho');
      expect(c.sync.knownVersion, 2);
      expect(c.sync.phase, SyncPhase.synced);
      // sem versão nova, nada acontece
      expect(await c.sync.pullNow(), isFalse);
      c.dispose();
    });

    test('pull não sobrescreve trabalho local pendente', () async {
      final api = FakeSyncApi()
        ..version = 1
        ..doc = docWith();
      final c = await opened(
        api,
        MemoryStore()
          ..data['doc:p'] = jsonEncode(docWith())
          ..data['sync:p'] = jsonEncode({'version': 1, 'dirty': false}),
      );
      c.addTrack();
      await Future<void>.delayed(_save); // salvo e marcado pendente
      api.version = 2;
      api.doc = docWith(track: 'Outro');
      expect(await c.sync.pullNow(), isFalse);
      expect(c.doc.tracks.length, 2);
      expect(c.doc.tracks.first.name, 'Local');
      c.dispose();
    });

    test('pull periódico sem rede fica calado', () async {
      final api = FakeSyncApi()
        ..version = 1
        ..doc = docWith();
      final c = await opened(
        api,
        MemoryStore()
          ..data['doc:p'] = jsonEncode(docWith())
          ..data['sync:p'] = jsonEncode({'version': 1, 'dirty': false}),
      );
      api.failures = 1;
      expect(await c.sync.pullNow(), isFalse);
      expect(c.sync.phase, SyncPhase.synced);
      c.dispose();
    });

    test('usar a versão do servidor espera o salvamento local pendente em vez de largar o conflito', () async {
      final api = FakeSyncApi()
        ..version = 1
        ..doc = docWith();
      final c = await opened(
        api,
        MemoryStore()
          ..data['doc:p'] = jsonEncode(docWith())
          ..data['sync:p'] = jsonEncode({'version': 1, 'dirty': false}),
      );
      c.addTrack();
      await Future<void>.delayed(_save);
      api.conflictNext = ServerDoc(9, docWith(track: 'Servidor'));
      await c.sync.syncNow();
      expect(c.sync.phase, SyncPhase.conflict);
      c.addTrack(); // edição agora: o salvamento de 400 ms está pendente
      await c.sync.useServer();
      expect(c.sync.phase, SyncPhase.synced);
      expect(c.doc.tracks.single.name, 'Servidor');
      expect(c.sync.knownVersion, 9);
      c.dispose();
    });
  });

  group('áudio para MIDI coerente com o warp', () {
    final r = ConvertedNotes.fromJson({
      'notes': [
        {'pitch': 60, 'start': 0.0, 'length': 1.0, 'velocity': 0.9},
        {'pitch': 62, 'start': 1.0, 'length': 1.0, 'velocity': 0.9},
      ],
      'duration': 2,
    });

    test('com warp, segundos viram batidas pelo andamento do áudio, não do projeto', () {
      // áudio a 60 bpm (1 batida por segundo) num projeto a 120: o clipe dura 2 batidas
      final clip = AudioClip(id: 'c', sample: 'h', start: 0, length: 2, warp: true, sourceBpm: 60);
      final notes = notesForClip(r, clip, 120);
      expect([for (final n in notes) n.start], [0.0, 1.0]);
      expect([for (final n in notes) n.length], [1.0, 1.0]);
      // e a última nota termina exatamente no fim do clipe
      expect(notes.last.start + notes.last.length, closeTo(clip.beats(120), 1e-9));
    });

    test('sem warp segue o andamento do projeto', () {
      final clip = AudioClip(id: 'c', sample: 'h', start: 0, length: 2);
      final notes = notesForClip(r, clip, 120);
      expect([for (final n in notes) n.start], [0.0, 2.0]);
      expect(notes.last.start + notes.last.length, closeTo(clip.beats(120), 1e-9));
    });

    test('transposição soma à altura, dentro de 0..127', () {
      final clip = AudioClip(id: 'c', sample: 'h', start: 0, length: 2, pitch: 5);
      expect([for (final n in notesForClip(r, clip, 120)) n.pitch], [65, 67]);
      final high = ConvertedNotes([const ServerNote(126, 0, 1, 0.5)], 1);
      expect(notesForClip(high, AudioClip(id: 'c', sample: 'h', start: 0, length: 1, pitch: 12), 120).single.pitch, 127);
    });

    test('invertido, as notas espelham na janela do clipe', () {
      // janela de 1 s a 2 s... [0,2] inteira: a nota 0..1 vira 1..2 e a 1..2 vira 0..1
      final clip = AudioClip(id: 'c', sample: 'h', start: 0, length: 2, reverse: true, warp: true, sourceBpm: 60);
      final notes = notesForClip(r, clip, 90);
      expect([for (final n in notes) n.pitch], [62, 60]);
      expect([for (final n in notes) n.start], [0.0, 1.0]);
      // janela parcial: offset 0.5, comprimento 1 → o trecho [0.5, 1.5] tocado de trás para a frente
      final part = AudioClip(id: 'c', sample: 'h', start: 0, offset: 0.5, length: 1, reverse: true, warp: true, sourceBpm: 60);
      final p = notesForClip(r, part, 90);
      // nota 62 (1.0..1.5) começa a tocar em 0; nota 60 (0.5..1.0) em 0.5 s
      expect([for (final n in p) (n.pitch, n.start, n.length)], [(62, 0.0, 0.5), (60, 0.5, 0.5)]);
    });

    test('convertToMidi com clipe warpado: clipe MIDI e notas cobrem a mesma duração', () async {
      const h = 'h1';
      final store = MemoryStore()..data['sample:$h'] = Uint8List(4);
      final api = FakeSyncApi()
        ..script = [
          SyncJob.fromJson({
            'id': 'j1',
            'kind': 'audio_to_midi',
            'status': 'done',
            'progress': 1,
            'result': {
              'notes': [
                {'pitch': 60, 'start': 0.0, 'length': 1.0, 'velocity': 0.9},
                {'pitch': 64, 'start': 1.0, 'length': 1.0, 'velocity': 0.9},
              ],
              'duration': 2,
            },
          }),
        ];
      final c = fakeController(FakeEngine(), store: store, api: api, canSync: () => true, syncTimeScale: 100);
      c.doc.tracks.first.clips.add(AudioClip(id: 'a', sample: h, start: 0, length: 2, warp: true, sourceBpm: 60));
      c.doc.samples[h] = SampleInfo('a.wav', 2);
      final n = await c.convertToMidi('a', pollEvery: Duration.zero);
      expect(n, 2);
      final midi = c.doc.tracks.last.midi.single;
      expect(midi.length, closeTo(2, 1e-9)); // 2 s do áudio a 60 bpm
      expect(midi.notes.last.start + midi.notes.last.length, closeTo(midi.length, 1e-9));
      c.dispose();
    });
  });

  group('apagar projeto e ganho do clipe', () {
    test('purge remove doc, sync, template e só os áudios que outro projeto não cita', () async {
      final store = MemoryStore();
      DawDoc docOf(List<String> hashes) => DawDoc(
        bpm: 120,
        beatsPerBar: 4,
        tracks: [
          DawTrack(
            id: 't',
            name: 'a',
            color: 0,
            clips: [for (final h in hashes) AudioClip(id: 'c$h', sample: h, start: 0, length: 1)],
          ),
        ],
        samples: {for (final h in hashes) h: SampleInfo('$h.wav', 1)},
      );
      store.data['doc:a'] = jsonEncode(docOf(['x', 'y']).toJson());
      store.data['doc:b'] = jsonEncode(docOf(['y', 'z']).toJson());
      store.data['sync:a'] = '{}';
      store.data['template:a'] = 'vazio';
      for (final h in ['x', 'y', 'z']) {
        store.data['sample:$h'] = Uint8List(1);
      }
      final removed = await purgeLocalProject(store, 'a', ['a', 'b']);
      expect(removed, 1);
      expect(store.data.keys.toSet(), {'doc:b', 'sample:y', 'sample:z'});
    });

    test('ganho do clipe: desfazível, vai ao motor e ao documento; dB de −40 a +12', () async {
      final engine = FakeEngine();
      final c = fakeController(engine);
      final clip = AudioClip(id: 'a', sample: 'h', start: 0, length: 1);
      c.doc.tracks.first.clips.add(clip);
      c.checkpoint();
      c.setClipGain('a', clipGainFromDb(-6), undoable: false);
      expect(clip.gain, closeTo(0.501, 0.001));
      expect(c.doc.toJson().toString(), contains('gain: ${clip.gain}'));
      c.setClipGain('a', 100);
      expect(clip.gain, closeTo(maxClipGain, 1e-9));
      expect(clipGainToDb(maxClipGain), closeTo(12, 1e-9));
      expect(clipGainFromDb(-40), 0);
      expect(formatClipGainDb(1), '0,0 dB');
      expect(formatClipGainDb(clipGainFromDb(-6)), '−6,0 dB');
      c.undo();
      expect(c.doc.tracks.first.clips.first.gain, closeTo(0.501, 0.001));
      c.undo();
      expect(c.doc.tracks.first.clips.first.gain, 1);
      c.dispose();
    });

    test('base da API: localhost em qualquer porta usa a origem; fora da web, a produção', () {
      String base(String url, {bool web = true, String override = ''}) => ApiClient.baseFor(override: override, web: web, page: Uri.parse(url));
      expect(base('http://localhost:8081/'), 'http://localhost:8081');
      expect(base('http://localhost:8080/#/x'), 'http://localhost:8080');
      expect(base('https://jopendaw.johnenrique.tech/'), 'https://jopendaw.johnenrique.tech');
      expect(base('http://localhost:8081/', override: 'http://10.0.2.2:8080'), 'http://10.0.2.2:8080');
      expect(base('http://localhost:8081/', web: false), 'https://jopendaw.johnenrique.tech');
    });
  });
}
