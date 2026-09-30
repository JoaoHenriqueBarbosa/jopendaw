// Fase 26 A: comping por trecho (escolher a tomada de cada trecho de uma gravação em loop).
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jopendaw_app/daw/comp.dart';
import 'package:jopendaw_app/daw/comp_ui.dart';
import 'package:jopendaw_app/daw/controller.dart';
import 'package:jopendaw_app/daw/export_options.dart';
import 'package:jopendaw_app/daw/model.dart';
import 'package:jopendaw_app/daw/timeline.dart';
import 'package:jopendaw_app/daw/wav.dart';

import 'fake_engine.dart';

/// Controlador com um clipe de 4 s (8 batidas a 120 BPM) de 3 tomadas (valores 0,1 / 0,2 / 0,3), a
/// segunda ativa, como a gravação em loop deixa.
Future<(DawController, FakeEngine, AudioClip)> withTakes() async {
  final e = FakeEngine();
  final c = fakeController(e);
  for (var i = 0; i < 3; i++) {
    final v = Float32List.fromList(List.filled(400, 0.1 * (i + 1)));
    await c.importBytes(
      [
        ('t$i.wav', encodeWav([v], 100, ExportFormat.wav32f)),
      ],
      at: 100.0 * i,
      track: 0,
    );
  }
  final t = c.doc.tracks[0];
  final hashes = [for (final x in t.clips) x.sample];
  t.clips.clear();
  final clip = AudioClip(id: 'g', sample: hashes[1], start: 0, length: 4, takes: hashes);
  t.clips.add(clip);
  c.clearHistory();
  e.log!.clear();
  return (c, e, clip);
}

double r4(double v) => double.parse(v.toStringAsFixed(4));

/// Trechos como (começo s, fim s, índice da tomada), arredondados.
List<(double, double, int)> view(DawController c) => [for (final s in c.compSegs) (r4(s.s), r4(s.e), s.take)];

/// Os trechos cobrem de [from] a [to] sem buracos, vizinhos da mesma tomada ficam juntos e nenhum clipe
/// passa do áudio da tomada nem do que cabe nos fades.
void expectCoherent(DawController c, {double from = 0, double to = 4}) {
  final segs = c.compSegs;
  expect(segs.first.s, closeTo(from, 1e-6));
  expect(segs.last.e, closeTo(to, 1e-6));
  for (var i = 0; i + 1 < segs.length; i++) {
    expect(segs[i].e, closeTo(segs[i + 1].s, 1e-6), reason: 'emenda $i');
    expect(segs[i].take, isNot(segs[i + 1].take), reason: 'vizinhos da mesma tomada ficam juntos');
  }
  for (final clip in c.doc.tracks[0].clips) {
    expect(clip.offset, greaterThanOrEqualTo(-1e-9));
    expect(clip.offset + clip.length, lessThanOrEqualTo(4 + 1e-9), reason: 'não passa do áudio da tomada');
    expect(clip.fadeIn + clip.fadeOut, lessThanOrEqualTo(clip.length + 1e-9));
  }
}

void main() {
  group('comp por trecho', () {
    test('escolher um trecho parte o clipe em três, com offsets certos e crossfade nas emendas', () async {
      final (c, _, clip) = await withTakes();
      expect(c.startComp(clip.id), isTrue);
      expect(c.compOn, isTrue);
      // 1 s a 2 s = batidas 2 a 4, da tomada 0
      c.compPick(0, 2, 4);
      expect(view(c), [(0.0, 1.0, 1), (1.0, 2.0, 0), (2.0, 4.0, 1)]);
      final clips = c.doc.tracks[0].clips..sort((a, b) => a.start.compareTo(b.start));
      expect(clips, hasLength(3));
      final h = clip.takes;
      expect([for (final x in clips) x.sample], [h[1], h[0], h[1]]);
      expect(clips.every((x) => x.takes.length == 3), isTrue);
      // o do meio começa 10 ms antes da emenda (o offset acompanha) e termina 10 ms depois
      expect(clips[1].offset, closeTo(0.99, 1e-9));
      expect(clips[1].start, closeTo(1.98, 1e-9)); // em batidas
      expect(clips[1].length, closeTo(1.02, 1e-9));
      expect(clips[1].fadeIn, closeTo(0.02, 1e-9));
      expect(clips[1].fadeOut, closeTo(0.02, 1e-9));
      expect(clips[1].fadeInShape, FadeShape.equalPower);
      expect(clips[1].autoFadeIn, isNotNull);
      // as bordas de fora do comp ficam como estavam
      expect((clips[0].start, clips[0].offset, clips[0].fadeIn), (0.0, 0.0, 0.0));
      expect(clips[2].offset + clips[2].length, closeTo(4, 1e-9));
      expectCoherent(c);
    });

    test('um passo de desfazer com o nome certo; refazer volta; desfazer restaura o documento byte a byte', () async {
      final (c, _, clip) = await withTakes();
      final before = jsonEncode(c.doc.toJson());
      c.startComp(clip.id);
      c.compPick(0, 2, 4);
      final after = jsonEncode(c.doc.toJson());
      expect(c.nextUndo!.title, 'Comp: escolher trecho');
      c.compPick(2, 5, 7);
      c.undo();
      expect(jsonEncode(c.doc.toJson()), after);
      c.undo();
      expect(jsonEncode(c.doc.toJson()), before);
      expect(c.canUndo, isFalse, reason: 'cada escolha é um passo só');
      c.redo();
      expect(jsonEncode(c.doc.toJson()), after);
      // depois de desfazer tudo o modo segue ligado e o grupo é o clipe inteiro de novo
      c.undo();
      expect(c.compOn, isTrue);
      expect(view(c), [(0.0, 4.0, 1)]);
    });

    test('escolher de novo: junta vizinhos da mesma tomada e cobrir tudo volta a um clipe só', () async {
      final (c, _, clip) = await withTakes();
      c.startComp(clip.id);
      c.compPick(0, 2, 4);
      c.compPick(1, 2, 4); // cobre o meio com a tomada 1
      expect(view(c), [(0.0, 4.0, 1)]);
      expect(c.doc.tracks[0].clips, hasLength(1));
      expect(c.doc.tracks[0].clips.single.autoFadeIn, isNull);
      expect(c.doc.tracks[0].clips.single.fadeIn, 0);
      c.compPick(2, 1, 3);
      c.compPick(0, 2, 5);
      expect(view(c), [(0.0, 0.5, 1), (0.5, 1.0, 2), (1.0, 2.5, 0), (2.5, 4.0, 1)]);
      expectCoherent(c);
    });

    test('o trecho que não mudou segue sendo o mesmo clipe', () async {
      final (c, _, clip) = await withTakes();
      c.startComp(clip.id);
      c.compPick(0, 2, 4);
      final firstId = c.doc.tracks[0].clips.firstWhere((x) => x.start == 0).id;
      c.compPick(2, 4, 6); // 2 s a 3 s: só mexe do meio para a frente
      expect(c.doc.tracks[0].clips.any((x) => x.id == firstId), isTrue);
      expectCoherent(c);
    });

    test('trecho maior que o comp é cortado nas bordas; trecho já igual não gasta passo de desfazer', () async {
      final (c, _, clip) = await withTakes();
      c.startComp(clip.id);
      c.compPick(0, -3, 100);
      expect(view(c), [(0.0, 4.0, 0)]);
      expect(c.doc.tracks[0].clips, hasLength(1));
      expect(c.doc.tracks[0].clips.single.sample, clip.takes[0]);
      c.compPick(0, 1, 3); // já é a tomada 0
      c.undo();
      expect(c.canUndo, isFalse, reason: 'só a primeira escolha entrou no histórico');
    });

    test('trecho minúsculo vira a emenda vizinha; trecho curto ainda faz crossfade que cabe', () async {
      final (c, _, clip) = await withTakes();
      c.startComp(clip.id);
      c.compPick(0, 2, 4);
      // 0,2 ms antes da emenda: não sobra trecho de 0,2 ms
      c.compPick(2, 1.9996, 4);
      expect(view(c).map((s) => s.$3), [1, 2, 1]);
      c.compPick(0, 3, 3.04); // 20 ms
      expectCoherent(c);
      expect(c.compSegs.where((s) => s.take == 0), isNotEmpty);
    });

    test('sem áudio para a emenda (tomada mais curta) fica o corte seco, sem quebrar', () async {
      final (c, _, clip) = await withTakes();
      // a tomada 0 "tem" só 2 s: a emenda em 2 s não pode avançar sobre o que ela não tem
      c.doc.samples[clip.takes[0]] = const SampleInfo('curta', 2.0);
      c.startComp(clip.id);
      c.compPick(0, 2, 4);
      expectCoherent(c);
      final mid = c.doc.tracks[0].clips.firstWhere((x) => x.sample == clip.takes[0]);
      expect(mid.autoFadeOut, isNull, reason: 'sem áudio depois do fim da tomada não há crossfade, fica o corte seco');
      expect(mid.autoFadeIn, isNotNull);
    });

    test('achatar mantém os clipes e as emendas, tira a lista de tomadas e desfaz em um passo', () async {
      final (c, _, clip) = await withTakes();
      c.startComp(clip.id);
      c.compPick(0, 2, 4);
      final before = jsonEncode(c.doc.toJson());
      final n = c.doc.tracks[0].clips.length;
      c.flattenComp();
      expect(c.compOn, isFalse);
      expect(c.doc.tracks[0].clips, hasLength(n));
      expect(c.doc.tracks[0].clips.every((x) => x.takes.isEmpty), isTrue);
      expect(c.doc.tracks[0].clips.where((x) => x.autoFadeIn != null), hasLength(2), reason: 'os crossfades ficam');
      expect(c.nextUndo!.title, 'Comp: achatar');
      c.undo();
      expect(jsonEncode(c.doc.toJson()), before);
      expect(c.startComp(c.doc.tracks[0].clips.first.id), isTrue);
    });

    test('sem campos novos: o JSON é o de sempre e o comp reabre com o projeto', () async {
      final (c, _, clip) = await withTakes();
      c.startComp(clip.id);
      c.compPick(0, 2, 4);
      final json = jsonEncode(c.doc.toJson());
      const known = [
        'id',
        'sample',
        'takes',
        'start',
        'offset',
        'length',
        'gain',
        'fade_in',
        'fade_out',
        'fade_in_shape',
        'fade_out_shape',
        'auto_fade_in',
        'auto_fade_out',
      ];
      for (final x in (jsonDecode(json)['tracks'][0]['clips'] as List)) {
        for (final k in (x as Map).keys) {
          expect(known, contains(k));
        }
      }
      final back = DawDoc.fromJson(jsonDecode(json) as Map<String, dynamic>);
      expect(jsonEncode(back.toJson()), json);
      final g = compGroupOf(back, back.tracks[0], back.tracks[0].clips.first);
      expect(g, isNotNull);
      expect(g!.clips, hasLength(3));
      expect([for (final s in compView(back, g)) s.take], [1, 0, 1]);
      // outro controlador com o documento reaberto: abre o comp a partir de qualquer pedaço
      final c2 = fakeController(FakeEngine())..doc = back;
      expect(c2.startComp(back.tracks[0].clips.last.id), isTrue);
      expect(view(c2), view(c));
      c2.compPick(2, 0, 2);
      expectCoherent(c2);
    });

    test('dividir um pedaço mantém o grupo; duplicar não entra nele; mover um pedaço o tira', () async {
      final (c, _, clip) = await withTakes();
      c.startComp(clip.id);
      c.compPick(0, 2, 4);
      c.seek(6); // 3 s, dentro do último pedaço
      final last = c.doc.tracks[0].clips.firstWhere((x) => x.start > 3);
      c.selectClip(last.id);
      c.splitAtPlayhead();
      expect(c.doc.tracks[0].clips, hasLength(4));
      expect(view(c), [(0.0, 1.0, 1), (1.0, 2.0, 0), (2.0, 3.0, 1), (3.0, 4.0, 1)]);
      // escolher de novo por cima da divisão junta o que é da mesma tomada
      c.compPick(1, 5, 7); // já toca a tomada 1 ali: a divisão do usuário fica como está
      expect(c.doc.tracks[0].clips, hasLength(4));
      c.compPick(0, 5, 7);
      c.compPick(1, 4, 8);
      expect(view(c), [(0.0, 1.0, 1), (1.0, 2.0, 0), (2.0, 4.0, 1)]);
      expectCoherent(c);
      // duplicar vai para depois do clipe (outro alinhamento): não entra no comp aberto
      final first = c.doc.tracks[0].clips.firstWhere((x) => x.start == 0);
      c.selectClip(first.id);
      c.duplicateSelected();
      expect(c.compGroup!.clips, hasLength(3));
      // mover um pedaço o tira do grupo
      final moved = c.doc.tracks[0].clips.firstWhere((x) => x.sample == clip.takes[0]);
      c.edit((_) => moved.start += 1);
      expect(c.compGroup!.clips.contains(moved), isFalse);
    });

    test('durante a reprodução: a escolha vai ao motor já, com o áudio e o offset de cada tomada', () async {
      final (c, e, clip) = await withTakes();
      c.startComp(clip.id);
      c.playing.value = true;
      c.compPick(0, 2, 4);
      final adds = e.sent('clip_add');
      expect(adds, hasLength(3));
      final ids = c.waveforms.keys.toList();
      final take0 = ids.indexOf(clip.takes[0]) + 1, take1 = ids.indexOf(clip.takes[1]) + 1;
      expect([for (final a in adds) a[2]], [take1, take0, take1]);
      final mid = adds[1];
      expect(mid[3] as double, closeTo(1.98, 1e-9));
      expect(mid[4] as double, closeTo(0.99, 1e-9));
      expect(mid[5] as double, closeTo(1.02, 1e-9));
      expect(mid[7] as double, closeTo(0.02, 1e-9));
      // e desfazer durante a reprodução volta ao clipe inteiro no motor
      e.log!.clear();
      c.undo();
      expect(e.sent('clip_add'), hasLength(1));
      c.playing.value = false;
    });

    test('o motor recebe o mesmo de novo no render (as chamadas saem do mesmo lugar do ao vivo)', () async {
      final (c, e, clip) = await withTakes();
      c.startComp(clip.id);
      c.compPick(0, 2, 4);
      final live = e.sent('clip_add');
      e.log!.clear();
      c.edit((_) {}, undoable: false);
      expect(e.sent('clip_add'), live);
    });

    test('tomada que não está neste aparelho não pode ser escolhida', () async {
      final (c, _, clip) = await withTakes();
      c.startComp(clip.id);
      c.missing.add(clip.takes[2]);
      final before = jsonEncode(c.doc.toJson());
      c.compPick(2, 2, 4);
      expect(jsonEncode(c.doc.toJson()), before);
      expect(c.error, contains('não está neste aparelho'));
    });

    test('só abre em clipe com tomadas e sem warp, reverso, transposição ou loop', () async {
      final (c, _, clip) = await withTakes();
      c.doc.tracks[0].clips.add(AudioClip(id: 'p', sample: clip.sample, start: 20, length: 1));
      expect(c.startComp('p'), isFalse);
      expect(c.error, contains('não tem tomadas'));
      expect(c.startComp('nao-existe'), isFalse);
      final tweaks = <void Function(AudioClip)>[
        (x) => x.reverse = true,
        (x) => x.pitch = 3,
        (x) => x.loopLength = 1,
        (x) {
          x.warp = true;
          x.sourceBpm = 100;
        },
      ];
      for (final f in tweaks) {
        final d = AudioClip.fromJson(clip.toJson());
        f(d);
        c.doc.tracks[0].clips
          ..clear()
          ..add(d);
        c.error = null;
        expect(c.startComp(d.id), isFalse);
        expect(c.error, contains('warp, reverso'));
      }
    });

    test('o modo some sozinho quando os clipes somem e o atalho liga e desliga', () async {
      final (c, _, clip) = await withTakes();
      c.startComp(clip.id);
      c.selectClip(clip.id);
      c.deleteSelected();
      expect(c.compOn, isFalse);
      c.undo();
      expect(c.compOn, isTrue);
      c.endComp();
      expect(c.compOn, isFalse);
      c.selectClip(null);
      c.toggleComp();
      expect(c.compOn, isFalse, reason: 'sem clipe selecionado não abre');
      c.selectClip(clip.id);
      c.toggleComp();
      expect(c.compOn, isTrue);
      c.toggleComp();
      expect(c.compOn, isFalse);
    });

    test('todos os pedaços ficam alinhados ao mesmo segundo 0 das tomadas', () async {
      final (c, _, clip) = await withTakes();
      c.startComp(clip.id);
      c.compPick(0, 2, 4);
      c.compPick(2, 5, 6);
      final g = c.compGroup!;
      expect(g.clips.length, greaterThan(3));
      for (final x in g.clips) {
        expect(clipStartSec(c.doc, x) - x.offset, closeTo(g.origin, 1e-9));
      }
    });
  });

  group('raias do comp na linha do tempo', () {
    Future<void> mount(WidgetTester tester, DawController c) => tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: SizedBox(width: 1000, height: 700, child: Timeline(c: c, compact: false)),
        ),
      ),
    );

    testWidgets('uma raia por tomada; arrastar escolhe o trecho; tocar no cabeçalho usa a tomada inteira; achatar fecha', (tester) async {
      final (c, _, clip) = await withTakes();
      await mount(tester, c);
      expect(find.byType(CompLaneView), findsNothing);
      c.startComp(clip.id);
      await tester.pump();
      expect(find.byType(CompLaneView), findsNWidgets(3));
      expect(find.byType(CompLaneHeader), findsNWidgets(3));
      // arrasta na raia da tomada 0 de 1 s a 2 s (batidas 2 a 4)
      final lane = find.byKey(const ValueKey('comp-lane:a:0'));
      final box = tester.getTopLeft(lane);
      final px = c.pxPerBeat;
      final y = box.dy + 10;
      final g = await tester.startGesture(Offset(box.dx + 2 * px, y));
      await g.moveBy(Offset(1 * px, 0));
      await g.moveBy(Offset(1 * px, 0));
      await g.up();
      await tester.pump();
      expect(view(c), [(0.0, 1.0, 1), (1.0, 2.0, 0), (2.0, 4.0, 1)]);
      expect(c.nextUndo!.title, 'Comp: escolher trecho');
      // tocar numa raia usa a tomada no trecho entre emendas (o do meio, de 1 s a 2 s)
      await tester.tapAt(Offset(box.dx + 3 * px, tester.getTopLeft(find.byKey(const ValueKey('comp-lane:a:2'))).dy + 10));
      await tester.pump();
      expect(view(c), [(0.0, 1.0, 1), (1.0, 2.0, 2), (2.0, 4.0, 1)]);
      // cabeçalho: tomada inteira
      await tester.tap(find.byKey(const ValueKey('comp-take-0')));
      await tester.pump();
      expect(view(c), [(0.0, 4.0, 0)]);
      await tester.tap(find.byKey(const ValueKey('comp-flatten')));
      await tester.pump();
      expect(find.byType(CompLaneView), findsNothing);
      expect(c.doc.tracks[0].clips.single.takes, isEmpty);
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('fechar e o desfazer que tira os pedaços mantêm a tela em pé', (tester) async {
      final (c, _, clip) = await withTakes();
      await mount(tester, c);
      c.startComp(clip.id);
      c.compPick(0, 2, 4);
      await tester.pump();
      c.undo();
      await tester.pump();
      expect(find.byType(CompLaneView), findsNWidgets(3));
      await tester.tap(find.byKey(const ValueKey('comp-close')));
      await tester.pump();
      expect(find.byType(CompLaneView), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 1));
    });
  });
}
