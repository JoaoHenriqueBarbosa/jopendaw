import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jopendaw_app/daw/controller.dart';
import 'package:jopendaw_app/daw/export_options.dart';
import 'package:jopendaw_app/daw/keymap.dart';
import 'package:jopendaw_app/daw/model.dart';
import 'package:jopendaw_app/daw/wav.dart';

import 'fake_engine.dart';

/// Um clipe de 2 s (200 quadros a 100 Hz).
Float32List ramp() => Float32List.fromList([for (var i = 0; i < 200; i++) i / 199]);

Future<(DawController, AudioClip)> project(FakeEngine e) async {
  final c = fakeController(e);
  c.warpDebounce = Duration.zero;
  await c.importBytes([('a.wav', encodeWav([ramp()], 100, ExportFormat.wav32f))], at: 0, track: 0);
  return (c, c.doc.tracks[0].clips.single);
}

/// Os `clip_add` que um motor novo (o render e a exportação) recebe.
List<List<Object>> clipsOf(DawController c) => [
  for (final x in c.debugFullSyncCalls())
    if (x.first == 'clip_add') x,
];

void main() {
  late FakeEngine e;
  setUp(() => e = FakeEngine());

  group('modelo', () {
    test('documento antigo abre com os padrões e volta sem os campos novos', () {
      final old = {'id': 'a', 'sample': 'h', 'start': 1, 'offset': 0, 'length': 2, 'gain': 1, 'fade_in': 0, 'fade_out': 0};
      final c = AudioClip.fromJson(old);
      expect((c.muted, c.invert, c.loopLength, c.looping), (false, false, null, false));
      for (final k in ['muted', 'invert', 'loop_length']) {
        expect(c.toJson().containsKey(k), isFalse, reason: k);
      }
    });

    test('os campos fazem a viagem de ida e volta; loop inválido é ignorado', () {
      final c = AudioClip(id: 'a', sample: 'h', start: 0, length: 4, muted: true, invert: true, loopLength: 1.5);
      final back = AudioClip.fromJson(jsonDecode(jsonEncode(c.toJson())) as Map<String, dynamic>);
      expect((back.muted, back.invert, back.loopLength, back.looping), (true, true, 1.5, true));
      expect(AudioClip.fromJson({...c.toJson(), 'loop_length': -1}).loopLength, isNull);
      expect(AudioClip.fromJson({...c.toJson(), 'loop_length': 0}).loopLength, isNull);
    });

    test('as repetições do loop: trechos inteiros e o resto', () {
      expect(AudioClip(id: 'a', sample: 'h', start: 0, length: 2.5, loopLength: 1).loopPieces(), [1.0, 1.0, 0.5]);
      expect(AudioClip(id: 'b', sample: 'h', start: 0, length: 0.5, loopLength: 1).loopPieces(), [0.5]);
      expect(AudioClip(id: 'c', sample: 'h', start: 0, length: 2).loopPieces(), [2.0]);
      expect(AudioClip(id: 'd', sample: 'h', start: 0, length: 3600, loopLength: 0.001).loopPieces().length, lessThanOrEqualTo(4096));
    });
  });

  group('mudo', () {
    test('o clipe mudo não vai ao motor e voltar a soar o devolve; desfazer acompanha', () async {
      final (c, clip) = await project(e);
      expect(clipsOf(c), hasLength(1));
      c.setClipMuted(clip.id, true);
      expect(clipsOf(c), isEmpty);
      expect(c.doc.tracks[0].clips, hasLength(1), reason: 'continua no arranjo');
      c.undo();
      expect(c.doc.tracks[0].clips.single.muted, isFalse);
      expect(clipsOf(c), hasLength(1));
      c.redo();
      expect(c.doc.tracks[0].clips.single.muted, isTrue);
      expect(clipsOf(c), isEmpty);
    });

    test('mudar o mudo com o transporte tocando atualiza o motor sem parar', () async {
      final (c, clip) = await project(e);
      await c.togglePlay();
      expect(c.playing.value, isTrue);
      e.log!.clear();
      c.setClipMuted(clip.id, true);
      expect(c.playing.value, isTrue);
      expect(e.sent('clips_clear'), isNotEmpty);
      expect(e.sent('clip_add'), isEmpty, reason: 'depois do clips_clear nenhum clipe é reenviado');
      e.log!.clear();
      c.setClipMuted(clip.id, false);
      expect(e.sent('clip_add'), hasLength(1));
      await c.togglePlay();
    });

    test('o atalho alterna o mudo do clipe selecionado', () async {
      final (c, clip) = await project(e);
      c.selectClip(clip.id);
      expect(c.toggleMuteSelectedClip(), isTrue);
      expect(c.doc.tracks[0].clips.single.muted, isTrue);
      c.toggleMuteSelectedClip();
      expect(c.doc.tracks[0].clips.single.muted, isFalse);
      expect(keyCatalog.any((a) => a.id == 'edit.mute'), isTrue);
    });
  });

  group('fase', () {
    test('o motor recebe o ganho com o sinal trocado, o documento guarda o ganho positivo', () async {
      final (c, clip) = await project(e);
      c.setClipGain(clip.id, 0.5);
      c.setClipInvert(clip.id, true);
      expect(clipsOf(c).single[6], -0.5);
      expect(c.doc.tracks[0].clips.single.gain, 0.5);
      c.setClipGain(clip.id, 0.8);
      expect(clipsOf(c).single[6], -0.8);
      c.undo();
      c.undo();
      expect(c.doc.tracks[0].clips.single.invert, isFalse);
      expect(clipsOf(c).single[6], 0.5);
    });

    test('duplicar e dividir herdam mudo, fase e loop', () async {
      final (c, clip) = await project(e);
      c.edit((d) {
        d.bpm = 120;
        clip.muted = true;
        clip.invert = true;
        clip.loopLength = 2;
      });
      c.selectClip(clip.id);
      c.duplicateSelected();
      final dup = c.doc.tracks[0].clips.last;
      expect((dup.muted, dup.invert, dup.loopLength), (true, true, 2.0));
      c.selectClip(clip.id);
      c.beat.value = 1; // 0,5 s
      c.splitAtPlayhead();
      final right = c.doc.tracks[0].clips.where((x) => x.start == 1).single;
      expect((right.muted, right.invert), (true, true));
    });
  });

  group('loop', () {
    test('ligar e desligar; desligar guarda uma repetição só; desfazer volta', () async {
      final (c, clip) = await project(e);
      c.edit((_) => clip.length = 1);
      c.setClipLoop(clip.id, true);
      expect(clip.loopLength, 1.0);
      expect(clipsOf(c), hasLength(1), reason: 'sem esticar ainda é um clipe só');
      c.edit((_) => clip.length = 2.5);
      expect(clipsOf(c), hasLength(3));
      c.setClipLoop(clip.id, false);
      expect((clip.loopLength, clip.length), (null, 1.0));
      c.undo();
      final back = c.doc.tracks[0].clips.single;
      expect((back.loopLength, back.length), (1.0, 2.5));
    });

    test('cada repetição vira um clipe do motor com o mesmo trecho', () async {
      final (c, clip) = await project(e);
      c.edit((d) {
        d.bpm = 120;
        clip.offset = 0.5;
        clip.length = 1.25;
        clip.loopLength = 0.5;
        clip.fadeIn = 0.1;
        clip.fadeOut = 0.1;
      });
      final calls = clipsOf(c);
      expect(calls, hasLength(3));
      // [_, faixa, id, início (batidas), offset, duração, ganho, fade in, fade out]
      expect([for (final x in calls) x[3]], [0.0, 1.0, 2.0]);
      expect([for (final x in calls) x[4]], [0.5, 0.5, 0.5]);
      expect([for (final x in calls) x[5]], [0.5, 0.5, 0.25]);
      expect([for (final x in calls) x[7]], [0.1, 0.0, 0.0], reason: 'fade de entrada só na primeira');
      expect([for (final x in calls) x[8]], [0.0, 0.0, 0.1], reason: 'fade de saída só na última');
    });

    test('loop com inversão: o trecho repetido é o invertido', () async {
      final (c, clip) = await project(e);
      c.edit((d) {
        d.bpm = 120;
        clip.offset = 0.5;
        clip.length = 1.0;
        clip.loopLength = 0.5;
      });
      c.setClipWarp(clip.id, reverse: true);
      await c.debugSettleWarp();
      final calls = clipsOf(c);
      expect(calls, hasLength(2));
      // invertido, o trecho [0,5 s; 1 s) do original é [1 s; 1,5 s) do derivado, nas duas repetições
      expect([for (final x in calls) x[4]], [1.0, 1.0]);
      expect([for (final x in calls) x[5]], [0.5, 0.5]);
    });

    test('dividir no meio de uma repetição mantém o som', () async {
      final (c, clip) = await project(e);
      c.edit((d) {
        d.bpm = 120;
        clip.length = 2.0;
        clip.loopLength = 0.5;
      });
      expect(clipsOf(c), hasLength(4));
      c.selectClip(clip.id);
      c.beat.value = 1.5; // 0,75 s: no meio da segunda repetição
      c.splitAtPlayhead();
      final after = clipsOf(c)..sort((a, b) => (a[3] as double).compareTo(b[3] as double));
      final pieces = [for (final x in after) (x[3] as double, x[4] as double, x[5] as double)];
      var t = 0.0;
      for (final (start, _, len) in pieces) {
        expect(start, closeTo(t * 2, 1e-9), reason: 'contíguos: $pieces');
        t += len;
      }
      expect(t, closeTo(2.0, 1e-9));
      // todo pedaço recomeça no início do trecho, menos a sobra da repetição cortada
      expect([for (final p in pieces) p.$2].where((o) => o != 0).toList(), [0.25]);
    });

    test('dividir numa emenda do loop deixa o loop inteiro dos dois lados', () async {
      final (c, clip) = await project(e);
      c.edit((d) {
        d.bpm = 120;
        clip.length = 2.0;
        clip.loopLength = 0.5;
      });
      c.selectClip(clip.id);
      c.beat.value = 2; // 1 s, emenda
      c.splitAtPlayhead();
      final right = c.doc.tracks[0].clips.where((x) => x.start == 2).single;
      expect((right.offset, right.length, right.loopLength, right.looping), (0.0, 1.0, 0.5, true));
      expect(c.doc.tracks[0].clips.first.length, 1.0);
    });
  });
}
