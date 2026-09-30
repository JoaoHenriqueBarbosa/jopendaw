/// Fase 13 (B): sincronização (422 do PUT do documento, pull ocupado, ponteiro preso, aviso de outro aparelho),
/// limpeza local com o warp, resultado da limpeza no servidor e o texto único de andamento e compasso.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jopendaw_app/api/storage.dart';
import 'package:jopendaw_app/api/sync_api.dart';
import 'package:jopendaw_app/daw/controller.dart';
import 'package:jopendaw_app/daw/export_options.dart';
import 'package:jopendaw_app/daw/local_purge.dart';
import 'package:jopendaw_app/daw/model.dart';
import 'package:jopendaw_app/daw/sync.dart';
import 'package:jopendaw_app/daw/tempo_format.dart';
import 'package:jopendaw_app/daw/tempo_map.dart';
import 'package:jopendaw_app/daw/wav.dart';
import 'package:jopendaw_app/models/project.dart';
import 'package:jopendaw_app/screens/account_screen.dart';
import 'package:jopendaw_app/screens/project_screen.dart';

import 'fake_engine.dart';
import 'fake_sync_api.dart';

Uint8List wav(double v) => encodeWav([Float32List.fromList(List.filled(200, v))], 100, ExportFormat.wav32f);
String hashOf(Uint8List b) => sha256.convert(b).toString();

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

MemoryStore storeWith({Map<String, dynamic>? local, int? version, bool dirty = false}) {
  final s = MemoryStore();
  if (local != null) s.data['doc:p'] = jsonEncode(local);
  if (version != null) s.data['sync:p'] = jsonEncode({'version': version, 'dirty': dirty});
  return s;
}

Future<void> idle(DawController c) async {
  while (c.sync.busy) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

/// O servidor sempre responde 422 ao PUT: o reenvio tem limite.
class _AlwaysMissingApi extends FakeSyncApi {
  @override
  Future<int> putProjectDoc(String projectId, int baseVersion, Map<String, dynamic> d) async {
    calls.add('put_doc:$baseVersion');
    throw DocSamplesMissing(samples.keys.toSet(), 'um áudio citado pelo projeto foi apagado neste instante');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('422 do PUT do documento', () {
    test('reenvia os áudios citados em missing e tenta de novo', () async {
      final bytes = wav(0.4), h = hashOf(bytes);
      final store = storeWith(
        local: docJson(sample: h, track: 'Local', bpm: 120),
      )..data['sample:$h'] = bytes;
      final api = FakeSyncApi()..missingNext = {h};
      final c = fakeController(FakeEngine(), store: store, api: api, canSync: () => true, syncTimeScale: 100);
      await c.open();
      await c.sync.starting;
      await idle(c);
      // o áudio subiu, o PUT levou 422 (o servidor o perdeu), o áudio subiu de novo e o segundo PUT valeu
      expect(api.calls, ['doc', 'missing', 'put_sample:$h', 'put_doc:0', 'missing', 'put_sample:$h', 'put_doc:0']);
      expect(c.sync.phase, SyncPhase.synced);
      expect(api.samples, contains(h));
      expect(api.version, 1);
      c.dispose();
    });

    test('com limite: depois de algumas tentativas vira erro do estado, sem laço', () async {
      final bytes = wav(0.4), h = hashOf(bytes);
      final store = storeWith(
        local: docJson(sample: h, track: 'Local', bpm: 120),
      )..data['sample:$h'] = bytes;
      final api = _AlwaysMissingApi();
      final c = fakeController(FakeEngine(), store: store, api: api, canSync: () => true, syncTimeScale: 100);
      await c.open();
      await c.sync.starting;
      await idle(c);
      expect(api.calls.where((x) => x.startsWith('put_doc')).length, 1 + SyncService.maxMissingRetries);
      expect(c.sync.phase, SyncPhase.error);
      expect(c.sync.message, contains('apagado'));
      expect(c.sync.hasPending, isTrue);
      c.dispose();
    });
  });

  group('pull da abertura', () {
    Future<(FakeSyncApi, DawController)> pending({void Function(DawController c)? before}) async {
      final api = FakeSyncApi()
        ..version = 2
        ..doc = docJson();
      final store = storeWith(local: docJson(track: 'Local', bpm: 120), version: 1);
      final c = fakeController(FakeEngine(), store: store, api: api, canSync: () => true, syncTimeScale: 100);
      before?.call(c);
      await c.open();
      await c.sync.starting;
      await idle(c);
      return (api, c);
    }

    test('com um gesto em andamento o documento não é trocado (e não vira conflito); depois do gesto, troca', () async {
      final (_, c) = await pending(before: (c) => c.debugPointer(const PointerDownEvent(pointer: 1)));
      expect(c.doc.tracks.first.name, 'Local');
      expect(c.sync.phase, isNot(SyncPhase.conflict));
      expect(c.sync.conflict, isNull);
      c.debugPointer(const PointerUpEvent(pointer: 1));
      await c.sync.syncNow();
      await idle(c);
      expect(c.doc.tracks.first.name, 'Servidor');
      expect(c.sync.phase, SyncPhase.synced);
      c.dispose();
    });

    test('ponteiro que nunca recebe o PointerUp deixa de segurar o pull depois de um tempo sem movimento', () async {
      final (_, c) = await pending(
        before: (c) {
          c.pointerStaleAfter = const Duration(milliseconds: 5);
          c.debugPointer(const PointerDownEvent(pointer: 7));
        },
      );
      // o gesto ainda parece recente na primeira leitura em máquinas lentas; uma rodada depois já passou
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await c.sync.syncNow();
      await idle(c);
      expect(c.doc.tracks.first.name, 'Servidor');
      c.dispose();
    });

    test('só avisa "atualizado de outro aparelho" quando havia documento local e ele mudou', () async {
      final (_, c) = await pending();
      expect(c.doc.tracks.first.name, 'Servidor');
      expect(c.remoteNotice, contains('outro aparelho'));
      c.dispose();

      // aparelho novo: sem documento local, o que vem do servidor não é "atualização"
      final api = FakeSyncApi()
        ..version = 3
        ..doc = docJson();
      final fresh = fakeController(FakeEngine(), store: MemoryStore(), api: api, canSync: () => true, syncTimeScale: 100);
      await fresh.open();
      expect(fresh.doc.tracks.first.name, 'Servidor');
      expect(fresh.remoteNotice, isNull);
      // e uma atualização de verdade que chega depois, sim
      api
        ..version = 4
        ..doc = docJson(track: 'Outro');
      expect(await fresh.sync.pullNow(), isTrue);
      expect(fresh.doc.tracks.first.name, 'Outro');
      expect(fresh.remoteNotice, contains('outro aparelho'));
      fresh.dispose();
    });
  });

  group('limpeza local', () {
    test('os derivados do warp dos áudios apagados saem junto; os de áudio que outro projeto usa ficam', () async {
      DawDoc docOf(List<String> hashes) => DawDoc(
        bpm: 120,
        beatsPerBar: 4,
        tracks: [
          DawTrack(
            id: 't',
            name: 't',
            color: 0,
            clips: [for (final h in hashes) AudioClip(id: 'c$h', sample: h, start: 0, length: 1)],
          ),
        ],
        samples: {for (final h in hashes) h: SampleInfo('$h.wav', 1)},
      );
      final store = MemoryStore();
      store.data['doc:a'] = jsonEncode(docOf(['x', 'y']).toJson());
      store.data['doc:b'] = jsonEncode(docOf(['y']).toJson());
      for (final h in ['x', 'y']) {
        store.data['sample:$h'] = Uint8List(1);
        store.data['warp:$h|r0.5000|p0.00|fwd'] = Uint8List(1);
      }
      expect(await purgeLocalProject(store, 'a', ['a', 'b']), 1);
      expect(store.data.keys.toSet(), {'doc:b', 'sample:y', 'warp:y|r0.5000|p0.00|fwd'});
    });
  });

  group('limpeza no servidor (tela Conta)', () {
    test('o resultado traz os pulados por uso e por tarefa, e o texto os conta', () {
      final r = CleanupResult.fromJson({'removed': 1, 'freed_bytes': 2048, 'skipped_recent': 0, 'skipped_in_use': 2, 'skipped_job': 1});
      expect((r.skippedInUse, r.skippedJob), (2, 1));
      expect(
        cleanupSummary(r),
        'Liberei 2,0 KB (1 áudio apagado). 2 áudios passaram a ser usados por um projeto e ficaram de fora. '
        '1 áudio com tarefa em andamento ficou de fora; limpe de novo quando ela terminar.',
      );
      expect(cleanupSummary(const CleanupResult(0, 0, 0, 0, 1)), startsWith('Nada para apagar. 1 áudio com tarefa'));
      // servidor antigo, sem os campos novos
      expect(CleanupResult.fromJson({'removed': 0, 'freed_bytes': 0}).skippedInUse, 0);
      expect(cleanupSummary(const CleanupResult(0, 0, 0)), 'Nada para apagar.');
    });
  });

  group('andamento e compasso', () {
    test('um formatador só: uma casa, sem ",0"', () {
      expect(formatBpm(120), '120');
      expect(formatBpm(120.04), '120');
      expect(formatBpm(119.96), '120');
      expect(formatBpm(120.06), '120,1');
      expect(formatBpm(97.5), '97,5');
      expect(formatMeter(6, 8), '6/8');
    });

    test('o cabeçalho usa a figura do compasso do documento, não um /4 fixo', () {
      final p = Project.fromJson({
        'id': 'p',
        'name': 'x',
        'bpm': 120,
        'beats_per_bar': 6,
        'beat_unit': 8,
        'sample_rate': 48000,
        'created_at': '2026-01-01T00:00:00Z',
        'updated_at': '2026-01-01T00:00:00Z',
      });
      expect(projectSubtitle(p, null), '120 BPM · 6/8');
      final d = DawDoc(bpm: 120.04, beatsPerBar: 6, tracks: [], meterMap: [MeterChange(1, 6, 8)]);
      expect(formatDocMeter(d), '6/8');
      expect(projectSubtitle(p, d), '120 BPM · 6/8');
      expect(projectSubtitle(p, DawDoc(bpm: 90, beatsPerBar: 3, tracks: [])), '90 BPM · 3/4');
    });
  });
}
