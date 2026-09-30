import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jopendaw_app/audio/engine_ffi.dart' show prepareRenderCalls;
import 'package:jopendaw_app/daw/export_options.dart';
import 'package:jopendaw_app/daw/model.dart';
import 'package:jopendaw_app/daw/wav.dart';

import 'controller_test.dart' show newController;
import 'fake_engine.dart';

/// Clipe de áudio de [start] (batidas) com [secs] segundos; a 120 BPM, 1 batida = 0,5 s.
AudioClip audio(String id, double start, double secs) => AudioClip(id: id, sample: 's', start: start, length: secs);

void main() {
  group('curvas', () {
    test('valores nos quartos, iguais aos do motor (fade_curve), e pontas exatas', () {
      final s2 = math.sqrt1_2;
      final e4 = math.exp(4) - 1;
      final expected = {
        FadeShape.linear: [0.0, 0.0625, 0.25, 0.5625, 1.0],
        FadeShape.equalPower: [0.0, math.sin(math.pi / 8), s2, math.sin(3 * math.pi / 8), 1.0],
        FadeShape.exponential: [0.0, (math.exp(1) - 1) / e4, (math.exp(2) - 1) / e4, (math.exp(3) - 1) / e4, 1.0],
        FadeShape.sCurve: [0.0, (1 - s2) / 2, 0.5, (1 + s2) / 2, 1.0],
      };
      for (final MapEntry(key: shape, value: want) in expected.entries) {
        for (var i = 0; i < 5; i++) {
          expect(shape.gain(i / 4), closeTo(want[i], 1e-12), reason: '$shape em ${i / 4}');
        }
        expect(shape.gain(0), 0);
        expect(shape.gain(1), 1);
        var prev = 0.0;
        for (var i = 0; i <= 1000; i++) {
          final g = shape.gain(i / 1000);
          expect(g, greaterThanOrEqualTo(prev));
          prev = g;
        }
      }
    });

    test('os códigos são os do motor e código estranho vale linear', () {
      expect(FadeShape.values.map((s) => s.index), [0, 1, 2, 3]);
      expect(FadeShape.fromCode(9), FadeShape.linear);
      expect(FadeShape.fromCode(null), FadeShape.linear);
      expect(FadeShape.fromCode(3), FadeShape.sCurve);
    });

    test('documento sem curvas abre linear e volta igual; com curvas e marcas faz a viagem', () {
      final old = {'id': 'a', 'sample': 'h', 'start': 1, 'offset': 0, 'length': 2, 'gain': 1, 'fade_in': 0.2, 'fade_out': 0};
      final c = AudioClip.fromJson(old);
      expect((c.fadeInShape, c.fadeOutShape, c.autoFadeIn, c.autoFadeOut), (FadeShape.linear, FadeShape.linear, null, null));
      for (final k in ['fade_in_shape', 'fade_out_shape', 'auto_fade_in', 'auto_fade_out']) {
        expect(c.toJson().containsKey(k), isFalse, reason: k);
      }
      c
        ..fadeOutShape = FadeShape.equalPower
        ..autoFadeOut = const AutoFade(0.1, FadeShape.sCurve);
      final back = AudioClip.fromJson(jsonDecode(jsonEncode(c.toJson())) as Map<String, dynamic>);
      expect(back.fadeOutShape, FadeShape.equalPower);
      expect((back.autoFadeOut!.prevLength, back.autoFadeOut!.prevShape), (0.1, FadeShape.sCurve));
      expect(back.autoFadeIn, isNull);
    });
  });

  group('crossfade automático (120 BPM)', () {
    test('travessia de borda: anterior sai e posterior entra pelo tamanho da sobreposição, com potência constante', () {
      final c = newController();
      final t = c.doc.tracks[0]..clips.addAll([audio('a', 0, 4), audio('top', 6, 4)]);
      c.placeOnTop('top', crossfade: true);
      final a = t.clips.firstWhere((x) => x.id == 'a'), top = t.clips.firstWhere((x) => x.id == 'top');
      expect(t.clips, hasLength(2));
      expect(a.length, 4); // o de baixo mantém a cauda coberta
      expect((a.fadeOut, a.fadeOutShape), (1.0, FadeShape.equalPower)); // 2 batidas = 1 s
      expect((top.fadeIn, top.fadeInShape), (1.0, FadeShape.equalPower));
      expect(a.autoFadeOut, isNotNull);
      expect(top.autoFadeIn, isNotNull);
      expect((a.fadeIn, top.fadeOut), (0.0, 0.0));
    });

    test('cabeça coberta: o de cima é o anterior', () {
      final c = newController();
      final t = c.doc.tracks[0]..clips.addAll([audio('b', 6, 4), audio('top', 0, 4)]);
      c.placeOnTop('top', crossfade: true);
      final b = t.clips.firstWhere((x) => x.id == 'b'), top = t.clips.firstWhere((x) => x.id == 'top');
      expect(b.start, 6);
      expect((top.fadeOut, b.fadeIn), (1.0, 1.0));
    });

    test('sem a opção, aparar como sempre; com sobreposição demais ou clipe contido, também', () {
      final c = newController();
      final t = c.doc.tracks[0]..clips.addAll([audio('a', 0, 4), audio('top', 6, 4)]);
      c.placeOnTop('top');
      expect(t.clips.firstWhere((x) => x.id == 'a').length, 3);
      expect(t.clips.every((x) => x.autoFadeIn == null && x.autoFadeOut == null), isTrue);

      // sobreposição de 3 s em clipes de 4 s: passa da metade, apara
      final c2 = newController();
      final t2 = c2.doc.tracks[0]..clips.addAll([audio('a', 0, 4), audio('top', 2, 4)]);
      c2.placeOnTop('top', crossfade: true);
      expect(t2.clips.firstWhere((x) => x.id == 'a').length, 1);
      expect(t2.clips.firstWhere((x) => x.id == 'a').autoFadeOut, isNull);

      // contido: some, como antes
      final c3 = newController();
      final t3 = c3.doc.tracks[0]..clips.addAll([audio('a', 2, 1), audio('top', 0, 8)]);
      c3.placeOnTop('top', crossfade: true);
      expect(t3.clips.map((x) => x.id), ['top']);
    });

    test('fade que o usuário pôs não é sobrescrito: apara', () {
      final c = newController();
      final t = c.doc.tracks[0]..clips.addAll([audio('a', 0, 4)..fadeOut = 0.2, audio('top', 6, 4)]);
      c.placeOnTop('top', crossfade: true);
      final a = t.clips.firstWhere((x) => x.id == 'a');
      expect((a.fadeOut, a.length), (0.2, 3));
    });

    test('a sobreposição some: os fades automáticos voltam ao que eram, só eles', () {
      final c = newController();
      final t = c.doc.tracks[0]
        ..clips.addAll([
          audio('a', 0, 4)..fadeOutShape = FadeShape.sCurve,
          audio('top', 6, 4)
            ..fadeOut = 0.4
            ..fadeIn = 0
            ..fadeInShape = FadeShape.exponential,
        ]);
      c.placeOnTop('top', crossfade: true);
      final a = t.clips.firstWhere((x) => x.id == 'a'), top = t.clips.firstWhere((x) => x.id == 'top');
      expect(a.fadeOutShape, FadeShape.equalPower);
      top.start = 20; // arrastado para longe
      c.placeOnTop('top', crossfade: true);
      expect((a.fadeOut, a.fadeOutShape, a.autoFadeOut), (0.0, FadeShape.sCurve, null));
      expect((top.fadeIn, top.fadeInShape, top.autoFadeIn), (0.0, FadeShape.exponential, null));
      expect(top.fadeOut, 0.4); // o fade do usuário no outro lado nunca foi tocado
    });

    test('a sobreposição muda de tamanho: o fade acompanha; fade mexido à mão perde a marca', () {
      final c = newController();
      final t = c.doc.tracks[0]..clips.addAll([audio('a', 0, 4), audio('top', 6, 4)]);
      c.placeOnTop('top', crossfade: true);
      final a = t.clips.firstWhere((x) => x.id == 'a'), top = t.clips.firstWhere((x) => x.id == 'top');
      top.start = 7; // sobreposição de 1 batida
      c.placeOnTop('top', crossfade: true);
      expect((a.fadeOut, top.fadeIn), (0.5, 0.5));
      c.setFadeShapes('a', fadeOut: FadeShape.sCurve);
      expect(a.autoFadeOut, isNull);
      top.start = 30;
      c.placeOnTop('top', crossfade: true);
      expect((a.fadeOut, a.fadeOutShape), (0.5, FadeShape.sCurve)); // manual: fica
      expect(top.fadeIn, 0.0); // automático: volta
    });

    test('comando do menu: aplica nas sobreposições do clipe clicado, em um passo de desfazer', () {
      final c = newController();
      // a: 0..2 s; b: 3..5 s (a batida 6); c: 5,5..7,5 s... a/b e b/c se cruzam por 1 s
      final t = c.doc.tracks[0]..clips.addAll([audio('a', 0, 4), audio('b', 6, 4), audio('c', 12, 4)]);
      final before = jsonEncode(c.doc.toJson());
      expect(c.crossfadeOverlaps('b'), 2, reason: 'b cruza a e c (o comando vale para o clipe clicado)');
      final a = t.clips[0], b = t.clips[1], cc = t.clips[2];
      expect((a.fadeOut, b.fadeIn, b.fadeOut, cc.fadeIn), (1.0, 1.0, 1.0, 1.0));
      expect(b.fadeOutShape, FadeShape.equalPower);
      c.undo();
      expect(jsonEncode(c.doc.toJson()), before);
    });
  });

  group('motor', () {
    test('o sync manda clip_fade_shape depois do clip_add, só para curva fora do padrão', () async {
      final e = FakeEngine();
      final c = fakeController(e);
      await c.importBytes(
        [
          ('a.wav', encodeWav([Float32List(200)], 100, ExportFormat.wav32f)),
        ],
        at: 0,
        track: 0,
      );
      final clip = c.doc.tracks[0].clips.single;
      e.log!.clear();
      c.edit((_) => clip.fadeIn = 0.1);
      var log = e.log!.map((x) => x.first).toList();
      expect(log, contains('clip_add'));
      expect(log, isNot(contains('clip_fade_shape')));
      e.log!.clear();
      c.setFadeShapes(clip.id, fadeIn: FadeShape.equalPower, fadeOut: FadeShape.sCurve);
      log = e.log!.map((x) => x.first).toList();
      final i = log.indexOf('clip_add');
      expect(i, greaterThanOrEqualTo(0));
      expect(log[i + 1], 'clip_fade_shape');
      expect(e.sent('clip_fade_shape').last, ['clip_fade_shape', 1, 3]);
    });

    test('o render aparado leva a curva do clipe que fica e descarta a do que sai', () {
      final out = prepareRenderCalls(
        [
          ['clip_add', 0, 1, 0, 0, 1.0, 1, 0, 0],
          ['clip_fade_shape', 1, 1],
          ['clip_add', 0, 1, 5, 0, 1.0, 1, 0, 0], // começa depois do fim: sai
          ['clip_fade_shape', 2, 2],
          ['clip_add', 0, 1, 1, 0, 9.0, 1, 0, 0], // cortado no fim: fica
          ['clip_fade_shape', 3, 0],
        ],
        4,
        120,
      );
      expect(out.map((c) => c.first), ['clip_add', 'clip_fade_shape', 'clip_add', 'clip_fade_shape']);
      expect(out[1], ['clip_fade_shape', 1, 1]);
      expect(out[3], ['clip_fade_shape', 3, 0]);
    });
  });
}
