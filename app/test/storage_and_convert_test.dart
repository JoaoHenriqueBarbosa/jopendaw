import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jopendaw_app/api/storage.dart';
import 'package:jopendaw_app/api/sync_api.dart';
import 'package:jopendaw_app/daw/audio_to_midi.dart';
import 'package:jopendaw_app/daw/export_options.dart';
import 'package:jopendaw_app/daw/midi_convert_dialog.dart';
import 'package:jopendaw_app/daw/model.dart';
import 'package:jopendaw_app/daw/wav.dart';
import 'package:jopendaw_app/widgets/format.dart';

import 'fake_engine.dart';
import 'fake_sync_api.dart';

/// Guarda os parâmetros que o app manda no job.
class _SpyApi extends FakeSyncApi {
  final params = <Map<String, dynamic>>[];

  @override
  Future<SyncJob> createJob(String kind, String sample, [Map<String, dynamic> p = const {}]) {
    params.add(p);
    return super.createJob(kind, sample, p);
  }
}

final _done = SyncJob.fromJson({
  'id': 'j1',
  'status': 'done',
  'progress': 1,
  'result': {
    'notes': [
      {'pitch': 60, 'start': 0.0, 'length': 1.0, 'velocity': 0.9},
    ],
    'duration': 2,
  },
});

void main() {
  test('fmtBytes: unidades, vírgula decimal e limites', () {
    expect(fmtBytes(0), '0 B');
    expect(fmtBytes(1023), '1023 B');
    expect(fmtBytes(1536), '1,5 KB');
    expect(fmtBytes(12 * 1024 * 1024 + 300 * 1024), '12,3 MB');
    expect(fmtBytes(4 * 1024 * 1024 * 1024), '4,0 GB');
    expect(fmtBytes(500 * 1024 * 1024), '500 MB');
  });

  test('StorageUsage lê a resposta do servidor', () {
    final u = StorageUsage.fromJson(
      jsonDecode('''
{"quota_bytes": 4294967296, "used_bytes": 1073741824, "unused_bytes": 100, "unused_count": 1,
 "samples": [
  {"hash": "a", "name": "kick.wav", "size": 924, "created_at": "2026-09-30T10:00:00Z", "unused": false, "project_count": 1, "projects": [{"id": "p1", "name": "Música"}]},
  {"hash": "b", "name": null, "size": 100, "created_at": "2026-09-30T10:00:00Z", "unused": true, "project_count": 0, "projects": []}
 ]}''') as Map<String, dynamic>,
    );
    expect(u.fraction, 0.25);
    expect((u.unusedCount, u.unusedBytes), (1, 100));
    expect(u.samples[0].projects, ['Música']);
    expect((u.samples[0].unused, u.samples[1].unused, u.samples[1].name), (false, true, null));
    expect(CleanupResult.fromJson({'removed': 2, 'freed_bytes': 50, 'skipped_recent': 1}).freedBytes, 50);
    // sem cota informada não divide por zero
    expect(const StorageUsage(quotaBytes: 0, usedBytes: 5, unusedBytes: 0, unusedCount: 0).fraction, 0);
  });

  test('runAudioToMidi manda os ajustes escolhidos; sem escolha, os padrões do servidor', () async {
    final api = _SpyApi()..script = [_done];
    await runAudioToMidi(api, 'h');
    await runAudioToMidi(api, 'h', options: const MidiConvertOptions(minNoteMs: 120, rmsFloorDb: -30));
    expect(api.params, [
      {'min_note_ms': 60.0, 'rms_floor_db': -45.0},
      {'min_note_ms': 120.0, 'rms_floor_db': -30.0},
    ]);
  });

  group('diálogo de conversão', () {
    Future<(_SpyApi, dynamic, WidgetTester)> open(WidgetTester t) async {
      final bytes = encodeWav([Float32List.fromList(List.filled(200, 0.5))], 100, ExportFormat.wav32f);
      final h = sha256.convert(bytes).toString();
      final store = MemoryStore()..data['sample:$h'] = bytes;
      final api = _SpyApi()..script = [_done];
      final c = fakeController(
        FakeEngine(),
        store: store,
        api: api,
        canSync: () => true,
        tracks: [
          DawTrack(
            id: 'a',
            name: 'Áudio 1',
            color: 0,
            clips: [AudioClip(id: 'c1', sample: h, start: 0, length: 2)],
          ),
        ],
      );
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: TextButton(onPressed: () => showConvertToMidi(ctx, c, 'c1'), child: const Text('abrir')),
            ),
          ),
        ),
      );
      await t.tap(find.text('abrir'));
      await t.pumpAndSettle();
      return (api, c, t);
    }

    testWidgets('mostra os ajustes antes de enviar; Cancelar não cria job', (t) async {
      final (api, _, _) = await open(t);
      expect(find.text('Nota mínima: 60 ms'), findsOneWidget);
      expect(find.text('Nível de silêncio: -45 dB'), findsOneWidget);
      expect(api.calls.where((x) => x.startsWith('job:')), isEmpty);
      await t.tap(find.text('Cancelar'));
      await t.pumpAndSettle();
      expect(find.text('Converter em notas (MIDI)'), findsNothing);
      expect(api.params, isEmpty);
    });

    testWidgets('Converter envia os ajustes do controle deslizante', (t) async {
      final (api, c, _) = await open(t);
      // arrasta o "nota mínima" até o fim (500 ms)
      await t.drag(find.byKey(const Key('convert-min-note')), const Offset(2000, 0));
      await t.pump();
      expect(find.text('Nota mínima: 500 ms'), findsOneWidget);
      await t.tap(find.text('Converter'));
      await t.pumpAndSettle(const Duration(seconds: 2));
      expect(api.params.single['min_note_ms'], 500.0);
      expect(api.params.single['rms_floor_db'], -45.0);
      expect(c.doc.tracks, hasLength(2), reason: 'a faixa MIDI entrou');
    });
  });
}
