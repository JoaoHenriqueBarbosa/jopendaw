import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jopendaw_app/daw/controller.dart';
import 'package:jopendaw_app/daw/export_options.dart';
import 'package:jopendaw_app/daw/model.dart';
import 'package:jopendaw_app/daw/warp.dart';
import 'package:jopendaw_app/daw/wav.dart';

import 'fake_engine.dart';

/// Um clipe de 2 s (200 quadros a 100 Hz) que sobe de 0 a 1: dá para ver a inversão.
Float32List ramp() => Float32List.fromList([for (var i = 0; i < 200; i++) i / 199]);

Future<(DawController, AudioClip)> project(FakeEngine e, {MemoryStore? store}) async {
  final c = fakeController(e, store: store);
  c.warpDebounce = Duration.zero;
  await c.importBytes(
    [
      ('loop.wav', encodeWav([ramp()], 100, ExportFormat.wav32f)),
    ],
    at: 0,
    track: 0,
  );
  return (c, c.doc.tracks[0].clips.single);
}

List<Object> lastClip(FakeEngine e) => e.sent('clip_add').last;

void main() {
  late FakeEngine e;
  setUp(() => e = FakeEngine());

  group('modelo', () {
    test('documento antigo, sem os campos do warp, abre com os padrões e volta igual', () {
      final old = {'id': 'a', 'sample': 'h', 'start': 1, 'offset': 0, 'length': 2, 'gain': 1, 'fade_in': 0, 'fade_out': 0};
      final c = AudioClip.fromJson(old);
      expect((c.warp, c.sourceBpm, c.pitch, c.reverse, c.processed), (false, null, 0.0, false, false));
      for (final k in ['warp', 'source_bpm', 'pitch', 'reverse']) {
        expect(c.toJson().containsKey(k), isFalse, reason: 'padrão fora do JSON: $k');
      }
      expect(jsonEncode(c.toJson()), jsonEncode(AudioClip.fromJson(c.toJson()).toJson()));
    });

    test('os parâmetros do warp fazem a viagem de ida e volta', () {
      final c = AudioClip(id: 'a', sample: 'h', start: 0, length: 2, warp: true, sourceBpm: 90, pitch: -3, reverse: true);
      final back = AudioClip.fromJson(jsonDecode(jsonEncode(c.toJson())) as Map<String, dynamic>);
      expect((back.warp, back.sourceBpm, back.pitch, back.reverse), (true, 90.0, -3.0, true));
    });

    test('com warp o clipe ocupa as mesmas batidas em qualquer andamento; sem, encolhe', () {
      final w = AudioClip(id: 'a', sample: 'h', start: 0, length: 2, warp: true, sourceBpm: 120);
      expect((w.beats(120), w.beats(60), w.beats(240)), (4.0, 4.0, 4.0));
      final plain = AudioClip(id: 'b', sample: 'h', start: 0, length: 2);
      expect((plain.beats(120), plain.beats(60)), (4.0, 2.0));
      // warp sem andamento original não tem o que esticar
      final blind = AudioClip(id: 'c', sample: 'h', start: 0, length: 2, warp: true);
      expect((blind.stretches, blind.beats(60)), (false, 2.0));
    });

    test('a chave do cache junta a origem e os parâmetros arredondados', () {
      AudioClip clip(double bpm, {double pitch = 0, bool reverse = false}) =>
          AudioClip(id: 'a', sample: 'abc', start: 0, length: 2, warp: true, sourceBpm: bpm, pitch: pitch, reverse: reverse);
      final a = WarpSpec.of(clip(100), 120)!;
      expect(a.key, 'abc|r0.8333|p0.00|fwd');
      // diferença abaixo do arredondamento: a mesma chave, o mesmo som
      expect(WarpSpec.of(clip(100.00001), 120)!.key, a.key);
      expect(WarpSpec.of(clip(100, pitch: 2, reverse: true), 120)!.key, 'abc|r0.8333|p2.00|rev');
      expect(WarpSpec.of(clip(120), 120), isNull, reason: 'razão 1 sem altura nem inversão toca o original');
      expect(WarpSpec.of(AudioClip(id: 'a', sample: 'abc', start: 0, length: 2), 120), isNull);
      // razão fora do limite do motor é apertada
      expect(WarpSpec.of(clip(500), 60)!.ratio, 4.0);
    });
  });

  group('controlador', () {
    test('toca o original até o derivado ficar pronto e então troca o id, com offset e duração convertidos', () async {
      final (c, clip) = await project(e);
      e.stretchGate = Completer();
      c.setClipWarp(clip.id, warp: true, sourceBpm: 100);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      // pendente: o original, sem conversão, e o clipe avisa
      expect(lastClip(e).sublist(2, 6), [1, 0.0, 0.0, 2.0]);
      expect(c.warpPending(clip), isTrue);
      e.stretchGate!.complete();
      await c.debugSettleWarp();
      expect(c.warpPending(clip), isFalse);
      final ratio = (100 / 120 * 10000).round() / 10000;
      final call = lastClip(e);
      expect(call[2], isNot(1), reason: 'id do derivado');
      expect(call[3], 0.0, reason: 'o início, em batidas, não muda');
      expect(call[4], closeTo(0, 1e-9));
      expect(call[5], closeTo(2 * ratio, 1e-9), reason: 'duração em segundos do derivado');
      expect(e.stretches.single.ratio, ratio);
      expect(e.loaded[call[2] as int]!.frames, (200 * ratio).round());
    });

    test('o derivado fica só no guardado local e o documento leva só parâmetros', () async {
      final store = MemoryStore();
      final (c, clip) = await project(e, store: store);
      final samplesBefore = c.doc.samples.keys.toSet();
      c.setClipWarp(clip.id, warp: true, sourceBpm: 100, pitch: 2);
      await c.debugSettleWarp();
      expect(store.data.keys.where((k) => k.startsWith('warp:')), hasLength(1));
      expect(c.doc.samples.keys.toSet(), samplesBefore);
      expect(jsonEncode(c.doc.toJson()), isNot(contains('warp:')));
      expect(c.doc.tracks[0].clips.single.toJson(), containsPair('source_bpm', 100.0));
      expect(e.stretches.single.semitones, 2.0);
    });

    test('mudar o andamento recalcula (com debounce) e solta o derivado velho', () async {
      final (c, clip) = await project(e);
      c.warpDebounce = const Duration(milliseconds: 40);
      c.setClipWarp(clip.id, warp: true, sourceBpm: 120, pitch: 1);
      await c.debugSettleWarp();
      expect(e.stretches, hasLength(1));
      final first = lastClip(e)[2] as int;
      // três valores seguidos de andamento: só o último vira som
      for (final bpm in [130.0, 140.0, 150.0]) {
        c.edit((d) => d.bpm = bpm);
      }
      expect(e.stretches, hasLength(1), reason: 'ainda esperando o debounce');
      expect(lastClip(e)[2], 1, reason: 'sem derivado para o andamento novo, toca o original');
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await c.debugSettleWarp();
      expect(e.stretches, hasLength(2));
      expect(e.stretches.last.ratio, closeTo(120 / 150, 1e-4));
      expect(lastClip(e)[2], isNot(first));
      expect(e.sent('sample_drop').map((x) => x[1]), contains(first));
    });

    test('só inverter não chama o motor de warp; o offset vira o do fim do trecho', () async {
      final (c, clip) = await project(e);
      c.edit((_) {
        clip.offset = 0.5;
        clip.length = 1.0;
      });
      c.setClipWarp(clip.id, reverse: true);
      await c.debugSettleWarp();
      expect(e.stretches, isEmpty);
      final call = lastClip(e);
      // origem de 2 s, trecho 0,5..1,5: invertido, o mesmo trecho começa em 2 − 1,5 = 0,5
      expect(call[4], closeTo(0.5, 1e-9));
      expect(call[5], closeTo(1.0, 1e-9));
      final audio = e.loaded[call[2] as int]!;
      expect(audio.channels[0].first, closeTo(1, 1e-6));
      expect(audio.channels[0].last, closeTo(0, 1e-6));
    });

    test('outro controlador com o mesmo guardado reaproveita o cache sem processar de novo', () async {
      final store = MemoryStore();
      final (c, clip) = await project(e, store: store);
      c.setClipWarp(clip.id, warp: true, sourceBpm: 100);
      await c.debugSettleWarp();
      expect(e.stretches, hasLength(1));
      store.data['doc:p'] = jsonEncode(c.doc.toJson());
      final e2 = FakeEngine();
      final c2 = fakeController(e2, store: store);
      c2.warpDebounce = Duration.zero;
      await c2.open();
      await c2.debugSettleWarp();
      expect(c2.error, isNull);
      expect(e2.stretches, isEmpty, reason: 'veio do guardado');
      expect(e2.sent('clip_add').last[2], isNot(1));
      c2.dispose();
    });

    test('exportar espera o derivado e renderiza com ele', () async {
      final (c, clip) = await project(e);
      e.renderResult = (outputs) => [
        for (final _ in outputs) [Float32List(300)..fillRange(0, 300, 0.5)],
      ];
      c.warpDebounce = const Duration(seconds: 5);
      c.setClipWarp(clip.id, warp: true, sourceBpm: 100);
      expect(e.stretches, isEmpty);
      await c.exportAudio(const ExportOptions());
      expect(c.error, isNull);
      final r = e.renders.single;
      final id = r.calls.firstWhere((x) => x.first == 'clip_add')[2] as int;
      expect(id, isNot(1));
      expect(r.samples.keys, contains(id));
    });

    test('cortar um clipe com warp usa os segundos da origem por batida do áudio', () async {
      final (c, clip) = await project(e);
      c.setClipWarp(clip.id, warp: true, sourceBpm: 60);
      // a 60 bpm de origem, 2 s de áudio são 2 batidas; cortar na batida 1 dá 1 s de cada lado
      c.selectClip(clip.id);
      c.beat.value = 1;
      c.splitAtPlayhead();
      final clips = c.doc.tracks[0].clips;
      expect(clips, hasLength(2));
      for (final x in clips) {
        expect(x.length, closeTo(1.0, 1e-9));
      }
      expect(clips.last.offset, closeTo(1.0, 1e-9));
    });
  });
}
