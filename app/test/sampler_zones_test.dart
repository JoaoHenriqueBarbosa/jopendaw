import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jopendaw_app/audio/engine.dart';
import 'package:jopendaw_app/daw/controller.dart';
import 'package:jopendaw_app/daw/export_options.dart';
import 'package:jopendaw_app/daw/instrument_panel.dart';
import 'package:jopendaw_app/daw/instruments.dart';
import 'package:jopendaw_app/daw/model.dart';
import 'package:jopendaw_app/daw/presets.dart' show SamplerId;
import 'package:jopendaw_app/daw/sampler_zones.dart';
import 'package:jopendaw_app/daw/sampler_zones_controller.dart';
import 'package:jopendaw_app/daw/sampler_zones_panel.dart';
import 'package:jopendaw_app/daw/slice_dialog.dart';
import 'package:jopendaw_app/daw/wav.dart';

import 'fake_engine.dart';

const rate = 48000.0;

/// Explosões de ruído com decaimento em silêncio quase total (a mesma construção dos testes do motor).
Float32List bursts(List<(double, double)> hits, double secs) {
  final n = (secs * rate).toInt();
  final x = Float32List(n);
  var seed = 12345;
  double rnd() {
    seed = (seed * 1664525 + 1013904223) & 0xFFFFFFFF;
    return (seed >> 8) / (1 << 24) * 2 - 1;
  }

  for (var i = 0; i < n; i++) {
    x[i] = 1e-4 * rnd();
  }
  for (final (t, amp) in hits) {
    final s = (t * rate).toInt();
    for (var k = 0; k < (0.12 * rate).toInt(); k++) {
      if (s + k < n) {
        final env = math.exp(-k / (0.03 * rate));
        final tone = math.sin(2 * math.pi * 220 * k / rate);
        x[s + k] += amp * env * (0.6 * tone + 0.4 * rnd());
      }
    }
  }
  return x;
}

DecodedAudio audio(List<Float32List> ch, [double r = rate]) => DecodedAudio(ch, r);

Uint8List wav(Float32List x, [int r = 48000]) => encodeWav([x], r, ExportFormat.wav32f);

/// Controladores abertos pelo teste de widget em andamento (soltos no fim dele).
final open = <DawController>[];

/// Teste de widget que solta os controladores no fim: o salvamento agendado não pode ficar pendente.
void panelTest(String name, Future<void> Function(WidgetTester tester) body) => testWidgets(name, (tester) async {
  await body(tester);
  await tester.pumpWidget(const SizedBox());
  for (final c in open) {
    c.dispose();
  }
  open.clear();
});

/// Controlador com um sampler (faixa 1) e um áudio importado nele.
Future<(DawController, FakeEngine, String)> sampler({Float32List? x}) async {
  final e = FakeEngine();
  final c = fakeController(e);
  open.add(c);
  c.addInstrumentTrack(TrackKind.sampler);
  await c.importSamplerBytes(1, 'loop.wav', wav(x ?? bursts([(0.3, 0.8), (0.8, 0.7)], 1.5)));
  return (c, e, c.doc.tracks[1].sample!);
}

void main() {
  group('modelo', () {
    test('documento sem zonas fica byte a byte como antes e abre com a lista vazia', () {
      final t = DawTrack(id: 't', name: 'S', color: 0, kind: TrackKind.sampler);
      expect(t.toJson().containsKey('zones'), isFalse);
      final old = jsonDecode(jsonEncode(t.toJson())) as Map<String, dynamic>;
      final back = DawTrack.fromJson(old);
      expect(back.zones, isEmpty);
      expect(jsonEncode(back.toJson()), jsonEncode(t.toJson()));
    });

    test('zonas ida e volta pelo JSON', () {
      final z = SamplerZone(
        id: 'z',
        sample: 'h',
        root: 48,
        lo: 36,
        hi: 59,
        vlo: 20,
        vhi: 90,
        cents: -12.5,
        gainDb: -3,
        pan: 0.25,
        oneShot: true,
        group: 2,
        start: 0.1,
        end: 0.4,
        loopStart: 0.2,
        loopEnd: 0.3,
      );
      final t = DawTrack(id: 't', name: 'S', color: 0, kind: TrackKind.sampler, zones: [z]);
      final back = DawTrack.fromJson(jsonDecode(jsonEncode(t.toJson())) as Map<String, dynamic>);
      expect(jsonEncode(back.zones.single.toJson()), jsonEncode(z.toJson()));
      expect(back.zones.single.oneShot, isTrue);
    });

    test('JSON incompleto ou fora das faixas é completado e limitado', () {
      final z = SamplerZone.fromJson({});
      expect((z.root, z.lo, z.hi, z.vlo, z.vhi, z.oneShot, z.group), (60, 0, 127, 1, 127, false, 0));
      final w = SamplerZone.fromJson({
        'id': 'a',
        'sample': 'h',
        'root': 999,
        'lo': 100,
        'hi': -4,
        'vlo': 0,
        'vhi': 500,
        'cents': 9999,
        'gain_db': double.nan,
        'pan': -7,
        'group': 500,
        'start': -1,
        'end': 'x',
        'loop_start': 1,
        'loop_end': 2,
      });
      expect((w.root, w.lo, w.hi, w.vlo, w.vhi), (127, 0, 100, 1, 127));
      expect((w.cents, w.gainDb, w.pan, w.group), (1200.0, 0.0, -1.0, maxZoneGroup));
      expect((w.start, w.end, w.hasLoop), (0.0, 0.0, true));
    });

    test('a chamada do motor segue a ordem do export zone_add', () {
      final z = SamplerZone(
        id: 'z',
        sample: 'h',
        root: 60,
        lo: 1,
        hi: 2,
        vlo: 3,
        vhi: 4,
        cents: 5,
        gainDb: 6,
        pan: 0.5,
        oneShot: true,
        group: 7,
        start: 8,
        end: 9,
        loopStart: 10,
        loopEnd: 11,
      );
      expect(z.engineCall(3, 42), ['zone_add', 3, 42, 60, 1, 2, 3, 4, 5.0, 6.0, 0.5, 1, 8.0, 9.0, 10.0, 11.0, 7]);
    });

    test('zona nova nasce numa faixa livre, com a nota base perto do C4', () {
      expect(nextZoneRange(const []), (lo: 0, hi: 127, root: 60, divides: null, overlaps: false));
      final a = SamplerZone(id: 'a', sample: 'h', lo: 0, hi: 59);
      expect(nextZoneRange([a]), (lo: 60, hi: 127, root: 60, divides: null, overlaps: false), reason: 'o C4 cabe na faixa');
      final b = SamplerZone(id: 'b', sample: 'h', lo: 70, hi: 80);
      expect(nextZoneRange([a, b]), (lo: 81, hi: 127, root: 81, divides: null, overlaps: false), reason: 'sem C4 na faixa: a nota mais perto dele');
      final low = SamplerZone(id: 'l', sample: 'h', lo: 60, hi: 127);
      expect(nextZoneRange([low]).root, 59, reason: 'faixa abaixo do C4: a de cima dela');
      final hole = [SamplerZone(id: 'a', sample: 'h', lo: 0, hi: 39), SamplerZone(id: 'b', sample: 'h', lo: 41, hi: 127)];
      expect(nextZoneRange(hole), (lo: 40, hi: 40, root: 60.clamp(40, 40), divides: null, overlaps: false));
    });

    test('teclado todo coberto: divide a zona mais larga ao meio; só se não der, sobrepõe', () {
      final full = SamplerZone(id: 'c', sample: 'h');
      final r = nextZoneRange([full]);
      expect((r.lo, r.hi, r.root, r.overlaps), (64, 127, 64, false));
      expect(r.divides, same(full));
      final small = SamplerZone(id: 's', sample: 'h', lo: 0, hi: 9);
      final big = SamplerZone(id: 'b', sample: 'h', lo: 10, hi: 127);
      expect(nextZoneRange([small, big]).divides, same(big));
      // todas de uma nota só, cobrindo tudo: nada a dividir
      final singles = [for (var n = 0; n < 128; n++) SamplerZone(id: 'n$n', sample: 'h', lo: n, hi: n)];
      final o = nextZoneRange(singles);
      expect((o.lo, o.hi, o.root, o.divides, o.overlaps), (60, 72, 60, null, true));
    });

    test('nota digitada: número ou nome, com sustenido e bemol', () {
      expect(parseNoteInput('60'), 60);
      expect(parseNoteInput(' 0 '), 0);
      expect(parseNoteInput('127'), 127);
      expect(parseNoteInput('128'), isNull);
      expect(parseNoteInput('-1'), isNull);
      expect(parseNoteInput('C4'), 60);
      expect(parseNoteInput('c#3'), 49);
      expect(parseNoteInput('Db3'), 49);
      expect(parseNoteInput('F♯2'), 42);
      expect(parseNoteInput('C-1'), 0);
      expect(parseNoteInput('G9'), 127);
      expect(parseNoteInput('G#9'), isNull);
      expect(parseNoteInput('H4'), isNull);
      expect(parseNoteInput(''), isNull);
      expect(parseNoteInput('C'), isNull);
      for (var n = 0; n < 128; n++) {
        expect(parseNoteInput(noteName(n)), n, reason: noteName(n));
      }
    });

    test('camadas de velocidade iguais, sem lacuna nem sobreposição', () {
      expect(velocityLayers(2), [(1, 63), (64, 127)]);
      expect(velocityLayers(3), [(1, 42), (43, 84), (85, 127)]);
      expect(velocityLayers(4), [(1, 31), (32, 63), (64, 95), (96, 127)]);
      for (final n in [1, 2, 3, 4, 5, 7, 16, 127]) {
        final l = velocityLayers(n);
        expect(l, hasLength(n));
        expect(l.first.$1, 1);
        expect(l.last.$2, 127);
        for (var i = 1; i < n; i++) {
          expect(l[i].$1, l[i - 1].$2 + 1, reason: '$n camadas, $i');
          expect(l[i].$1, lessThanOrEqualTo(l[i].$2));
        }
      }
    });
  });

  group('fatiamento', () {
    test('fatias iguais e casos de borda', () {
      final x = Float32List(48000);
      expect(slicePoints(audio([x]), count: 4), [0.0, 0.25, 0.5, 0.75]);
      expect(slicePoints(audio([x]), count: 1), [0.0, 0.5], reason: 'o mínimo é 2');
      expect(slicePoints(audio([x]), count: 0), [0.0, 0.5]);
      expect(slicePoints(audio([x]), count: 10000), hasLength(maxSlices));
      expect(slicePoints(audio([Float32List(3)]), count: 8), [0.0, 1 / rate, 2 / rate]);
      expect(slicePoints(audio([Float32List(0)]), count: 4), isEmpty);
      expect(slicePoints(audio(const []), count: 4), isEmpty);
      expect(slicePoints(audio([x], 0), count: 4), isEmpty);
      expect(slicePoints(audio([x], double.nan)), isEmpty);
    });

    test('transientes acham cada ataque no lugar', () {
      const hits = [0.30, 0.80, 1.20, 1.75];
      final x = bursts([(0.30, 0.8), (0.80, 0.7), (1.20, 0.9), (1.75, 0.6)], 2.4);
      final p = slicePoints(audio([x]));
      expect(p, hasLength(5), reason: '$p');
      expect(p.first, 0);
      for (var i = 0; i < 4; i++) {
        expect(p[i + 1], lessThanOrEqualTo(hits[i] + 0.001), reason: '$p');
        expect(p[i + 1], greaterThan(hits[i] - 0.008), reason: '$p');
      }
    });

    test('sensibilidade, estéreo e taxa diferente', () {
      final x = bursts([(0.3, 0.8), (0.9, 0.8), (1.5, 0.03)], 2.2);
      expect(slicePoints(audio([x]), sensitivity: 0), hasLength(3));
      final loose = slicePoints(audio([x]), sensitivity: 1);
      expect(loose, hasLength(4));
      expect(loose.any((t) => (t - 1.5).abs() < 0.01), isTrue);
      final y = bursts([(0.5, 0.8), (1.0, 0.8)], 1.5);
      expect(slicePoints(audio([y, y])), hasLength(3));
      final low = Float32List.fromList([for (var i = 0; i < y.length; i += 2) y[i]]);
      final p = slicePoints(audio([low], rate / 2));
      expect(p, hasLength(3), reason: '$p');
      expect((p[1] - 0.5).abs(), lessThan(0.01));
      expect((p[2] - 1.0).abs(), lessThan(0.01));
    });

    test('silêncio, tom estável e áudio curtíssimo não têm corte', () {
      expect(slicePoints(audio([Float32List(48000)]), sensitivity: 1), [0.0]);
      final tone = Float32List.fromList([for (var i = 0; i < 48000; i++) math.sin(i * 0.05) * 0.5]);
      expect(slicePoints(audio([tone])), [0.0]);
      expect(slicePoints(audio([Float32List.fromList(List.filled(5, 0.5))])), [0.0]);
      expect(
        slicePoints(
          audio([
            Float32List.fromList([0.5]),
          ]),
          sensitivity: double.nan,
        ),
        [0.0],
      );
    });

    test('ataques colados nas pontas não viram corte, e o excesso fica no limite', () {
      final y = bursts([(0.002, 0.9), (1.0, 0.9)], 1.2);
      for (var i = y.length - 144; i < y.length; i++) {
        y[i] = 0.9;
      }
      final p = slicePoints(audio([y]));
      expect(p.every((t) => t == 0 || (t > 0.02 && t < 1.2 - 0.01)), isTrue, reason: '$p');
      final many = bursts([for (var i = 0; i < 150; i++) (0.1 + i * 0.08, 0.8)], 13);
      final q = slicePoints(audio([many]), sensitivity: 0.7);
      expect(q.length, lessThanOrEqualTo(maxSlices));
      expect(q.length, greaterThan(50));
      for (var i = 1; i < q.length; i++) {
        expect(q[i], greaterThan(q[i - 1]));
      }
    });

    test('zonas de fatias: uma nota cada a partir de C1, só o trecho, até o fim', () {
      var n = 0;
      final z = sliceZones('h', [0, 0.25, 0.5, 0.75], () => 'z${n++}');
      expect(z, hasLength(4));
      for (var i = 0; i < 4; i++) {
        expect((z[i].root, z[i].lo, z[i].hi, z[i].oneShot, z[i].vlo, z[i].vhi), (24 + i, 24 + i, 24 + i, true, 1, 127));
      }
      expect((z[1].start, z[1].end), (0.25, 0.5));
      expect(z[3].end, 0, reason: 'a última vai até o fim do áudio');
      final odd = sliceZones('h', [0, 0, 0.5, 0.3, double.nan, -1, 0.9], () => 'x');
      expect(odd.map((z) => z.start), [0.0, 0.5, 0.9]);
      final long = sliceZones('h', [for (var i = 0; i < 96; i++) i.toDouble()], () => 'y', first: 100);
      expect(long, hasLength(28));
      expect(long.last.hi, 127);
      expect(sliceZones('h', const [], () => 'y'), isEmpty);
    });
  });

  group('controlador', () {
    test('acrescentar, editar, remover e desfazer chegam ao motor', () async {
      final (c, e, hash) = await sampler();
      expect(e.sent('zones_clear'), isEmpty, reason: 'sem zonas nada é mandado');
      expect(e.sent('zone_add'), isEmpty);
      final id = e.loaded.keys.single;

      final z = c.addZone(1, hash)!;
      expect((z.lo, z.hi, z.root), (0, 127, 60));
      expect(e.sent('zones_clear').last, ['zones_clear', 1]);
      expect(e.sent('zone_add').last.sublist(0, 4), ['zone_add', 1, id, 60]);

      final second = c.addZone(1, hash)!;
      expect((second.lo, second.hi), (64, 127), reason: 'teclado cheio: divide a primeira ao meio');
      expect((z.lo, z.hi), (0, 63));
      e.log!.clear();
      c.editZone(1, second.id, (z) {
        z.lo = 80;
        z.hi = 70;
        z.gainDb = 99;
      });
      expect((second.lo, second.hi, second.gainDb), (70, 80, 24.0), reason: 'normalizada');
      // as duas zonas vão de novo, limpas antes
      expect(e.log!.map((c) => c.first as String).where((n) => n.startsWith('zone')), ['zones_clear', 'zone_add', 'zone_add']);

      e.log!.clear();
      c.setParam(1, SamplerId.level, 0.5);
      expect(e.sent('zones_clear'), isEmpty, reason: 'zonas iguais não são mandadas de novo');
      expect(e.sent('zone_add'), isEmpty);

      c.removeZone(1, z.id);
      expect(c.zonesOf(1).map((z) => z.id), [second.id]);
      c.undo();
      expect(c.zonesOf(1).map((z) => z.id), [z.id, second.id]);
      c.undo();
      expect((c.zonesOf(1).last.lo, c.zonesOf(1).last.hi), (64, 127), reason: 'voltou ao antes da edição');
      c.undo();
      expect(c.zonesOf(1).map((z) => z.id), [z.id]);
      c.undo();
      expect(c.zonesOf(1), isEmpty);
      expect(e.log!.last, ['zones_clear', 1]);
      c.redo();
      expect(c.zonesOf(1), hasLength(1));
    });

    test('recusa o que não faz sentido', () async {
      final (c, _, hash) = await sampler();
      expect(c.addZone(0, hash), isNull, reason: 'faixa de áudio');
      expect(c.addZone(9, hash), isNull);
      expect(c.addZone(1, 'nao-existe'), isNull);
      expect(c.zonesOf(0), isEmpty);
      expect(c.zonesOf(99), isEmpty);
      c.editZone(1, 'nada', (z) => z.root = 1);
      c.removeZone(1, 'nada');
      expect(c.duplicateZone(1, 'nada'), isNull);
      expect(c.zoneFromTrackSample(0), isNull);
      for (var i = 0; i < maxZones + 5; i++) {
        c.addZone(1, hash);
      }
      expect(c.zonesOf(1), hasLength(maxZones));
      expect(c.duplicateZone(1, c.zonesOf(1).first.id), isNull, reason: 'no limite');
    });

    test('o áudio único vira a primeira zona; duplicar; apagar tudo', () async {
      final (c, e, hash) = await sampler();
      c.setParam(1, SamplerId.root, 48);
      final z = c.zoneFromTrackSample(1)!;
      expect((z.sample, z.root, z.lo, z.hi), (hash, 48, 0, 127));
      expect(c.zoneFromTrackSample(1), isNull, reason: 'já tem zonas');
      final copy = c.duplicateZone(1, z.id)!;
      expect(c.zonesOf(1).map((z) => z.id), [z.id, copy.id]);
      c.clearZones(1);
      expect(c.zonesOf(1), isEmpty);
      expect(e.log!.last, ['zones_clear', 1]);
    });

    test('abrir o projeto manda as zonas ao motor; sample que chega depois liga a zona', () async {
      final e = FakeEngine();
      final bytes = wav(Float32List.fromList(List.filled(4800, 0.5)));
      final hash = sha256.convert(bytes).toString();
      final z = SamplerZone(id: 'z', sample: hash, root: 55, lo: 40, hi: 70);
      final c = fakeController(
        e,
        tracks: [
          DawTrack(id: 't', name: 'S', color: 0, kind: TrackKind.sampler, zones: [z]),
        ],
      );
      c.doc.samples[hash] = const SampleInfo('a.wav', 0.1);
      c.mutate((_) {});
      expect(e.sent('zones_clear'), [
        ['zones_clear', 0],
      ]);
      expect(e.sent('zone_add').single.sublist(0, 4), ['zone_add', 0, 0, 55], reason: 'áudio ainda não carregado: id 0');
      e.log!.clear();
      await c.importSampleFile('a.wav', bytes);
      c.mutate((_) {});
      final id = e.loaded.keys.single;
      expect(e.sent('zone_add').single.sublist(0, 4), ['zone_add', 0, id, 55], reason: 'agora com o id do áudio');
    });

    test('render fora de tempo real leva as zonas e o áudio delas', () async {
      final (c, e, hash) = await sampler();
      // o áudio único fica sem uso: só a zona cita o áudio
      c.setInstrumentSample(1, null);
      c.addZone(1, hash);
      final clip = c.createMidiClip(1, 4);
      c.edit((_) => clip.notes.add(MidiNote(pitch: 60, start: 0, length: 2)));
      e.renderResult = (outputs) => [
        for (final _ in outputs) [Float32List(100), Float32List(100)],
      ];
      await c.exportAudio(const ExportOptions());
      final r = e.renders.single;
      expect(r.calls.where((c) => c.first == 'zone_add'), hasLength(1));
      expect(r.samples.keys, e.loaded.keys);
    });

    test('fatiar troca as zonas por uma por fatia e desfaz', () async {
      final (c, e, hash) = await sampler(x: bursts([(0.3, 0.8), (0.8, 0.7), (1.2, 0.9)], 1.8));
      c.addZone(1, hash);
      final p = c.slicePreview(hash)!;
      expect(p, hasLength(4), reason: '$p');
      expect(c.createSlices(1, hash, p), 4);
      final z = c.zonesOf(1);
      expect(z.map((z) => z.root), [24, 25, 26, 27]);
      expect(z.every((z) => z.oneShot && z.sample == hash), isTrue);
      expect(e.sent('zone_add'), hasLength(1 + 4), reason: 'a zona anterior, depois as 4 fatias (a anterior foi limpa)');
      expect(c.createSlices(1, hash, const []), 0);
      expect(c.createSlices(1, 'nao-existe', p), 0);
      c.undo();
      expect(c.zonesOf(1), hasLength(1));
      expect(c.slicePreview('nao-existe'), isNull);
      expect(c.slicePreview(hash, count: 8), hasLength(8));
    });
  });

  group('mapa', () {
    const g = ZoneMapGeometry(noteW: 10, height: 127);

    test('conversão entre pixel, nota e velocidade', () {
      expect(g.noteAt(0), 0);
      expect(g.noteAt(9.9), 0);
      expect(g.noteAt(10), 1);
      expect(g.noteAt(99999), 127);
      expect(g.noteAt(-5), 0);
      expect(g.velAt(0), 127);
      expect(g.velAt(126.9), 1);
      expect(g.velAt(-9), 127);
      expect(g.velAt(9999), 1);
      final z = SamplerZone(id: 'a', sample: 'h', lo: 10, hi: 19, vlo: 1, vhi: 127);
      expect(g.rectOf(z), const Rect.fromLTRB(100, 0, 200, 127));
    });

    test('o que cada ponto do bloco pega', () {
      final wide = SamplerZone(id: 'a', sample: 'h', lo: 10, hi: 29);
      final narrow = SamplerZone(id: 'b', sample: 'h', lo: 50, hi: 51);
      final zones = [wide, narrow];
      ({SamplerZone zone, ZonePart part})? at(double x, double y) => g.hit(zones, Offset(x, y));
      expect(at(103, 60)!.part, ZonePart.left);
      expect(at(297, 60)!.part, ZonePart.right);
      expect(at(200, 60)!.part, ZonePart.body);
      expect(at(200, 2)!.part, ZonePart.top);
      expect(at(200, 125)!.part, ZonePart.bottom);
      expect(at(50, 60), isNull, reason: 'fora de todos');
      expect(at(500, 3)!.zone.id, 'b');
      expect(at(500, 60)!.part, ZonePart.body, reason: 'bloco estreito não tem borda dos lados');
      // sobrepostos: o de cima (último) ganha, mas o selecionado passa na frente
      final over = SamplerZone(id: 'c', sample: 'h', lo: 10, hi: 29);
      expect(g.hit([wide, over], const Offset(200, 60))!.zone.id, 'c');
      expect(g.hit([wide, over], const Offset(200, 60), preferred: 'a')!.zone.id, 'a');
    });

    test('arrastar borda, corpo e velocidade', () {
      SamplerZone z() => SamplerZone(id: 'a', sample: 'h', root: 50, lo: 40, hi: 60, vlo: 30, vhi: 100);
      var from = z(), t = z();
      dragZone(t, from, ZonePart.left, note: 20, vel: 0, n0: 0, v0: 0);
      expect((t.lo, t.hi), (20, 60));
      dragZone(t, from, ZonePart.left, note: 90, vel: 0, n0: 0, v0: 0);
      expect((t.lo, t.hi), (60, 60), reason: 'passa da outra borda: fica nela');
      t = z();
      dragZone(t, from, ZonePart.right, note: 10, vel: 0, n0: 0, v0: 0);
      expect((t.lo, t.hi), (40, 40));
      t = z();
      dragZone(t, from, ZonePart.top, note: 0, vel: 10, n0: 0, v0: 0);
      expect((t.vlo, t.vhi), (30, 30), reason: 'não cruza a borda de baixo');
      t = z();
      dragZone(t, from, ZonePart.bottom, note: 0, vel: 127, n0: 0, v0: 0);
      expect((t.vlo, t.vhi), (100, 100));
      t = z();
      dragZone(t, from, ZonePart.body, note: 45, vel: 60, n0: 40, v0: 50);
      expect((t.lo, t.hi, t.root, t.vlo, t.vhi), (45, 65, 55, 30, 100), reason: 'o corpo move só as notas: a velocidade fica');
      dragZone(t, from, ZonePart.body, note: 200, vel: 200, n0: 40, v0: 50);
      expect((t.lo, t.hi, t.root, t.vlo, t.vhi), (107, 127, 117, 30, 100), reason: 'pára no fim do teclado');
      dragZone(t, from, ZonePart.body, note: 0, vel: 1, n0: 100, v0: 100);
      expect((t.lo, t.hi, t.vlo), (0, 20, 30), reason: 'e no começo');
      from = z();
    });
  });

  group('painel', () {
    Future<(DawController, FakeEngine, String)> mount(WidgetTester tester, {double width = 1280, List<SamplerZone> Function(String hash)? zones}) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      late DawController c;
      late FakeEngine e;
      late String hash;
      await tester.runAsync(() async {
        (c, e, hash) = await sampler();
        for (final z in zones?.call(hash) ?? const <SamplerZone>[]) {
          c.doc.tracks[1].zones.add(z);
        }
        c.mutate((_) {});
        e.log!.clear();
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: ListenableBuilder(
                listenable: c,
                builder: (_, _) => SamplerZonesPanel(c: c, track: 1, color: Colors.orange, compact: width < 600),
              ),
            ),
          ),
        ),
      );
      return (c, e, hash);
    }

    Offset mapOrigin(WidgetTester tester) => tester.getTopLeft(find.byKey(const ValueKey('zone-map')));

    panelTest('vazio: mostra a explicação e os atalhos', (tester) async {
      await mount(tester);
      expect(find.textContaining('Sem zonas o sampler toca um áudio só'), findsOneWidget);
      expect(find.text('Adicionar sample como zona'), findsOneWidget);
      expect(find.text('Fatiar sample…'), findsOneWidget);
      expect(find.text('Usar o áudio atual como zona'), findsOneWidget);
      await tester.tap(find.text('Usar o áudio atual como zona'));
      await tester.pump();
      expect(find.byKey(const ValueKey('zone-map')), findsOneWidget);
      expect(find.text('1 zona'), findsOneWidget);
      expect(find.text('Nota base'), findsOneWidget, reason: 'a zona nova já vem selecionada');
    });

    panelTest('arrastar a borda direita muda a faixa de notas, num passo de desfazer', (tester) async {
      final (c, e, _) = await mount(
        tester,
        zones: (h) => [SamplerZone(id: 'z', sample: h, root: 50, lo: 40, hi: 60)],
      );
      final o = mapOrigin(tester);
      // 10 px por nota (1280 de mapa): a nota 60 termina em x = 610
      await tester.dragFrom(o + const Offset(606, 60), const Offset(50, 0));
      await tester.pump();
      final z = c.doc.tracks[1].zones.single;
      expect((z.lo, z.hi), (40, 65));
      expect(e.sent('zone_add').last[5], 65);
      c.undo();
      expect(c.doc.tracks[1].zones.single.hi, 60, reason: 'um passo só');
    });

    panelTest('arrastar a borda de cima muda a velocidade e o corpo move o bloco', (tester) async {
      final (c, _, _) = await mount(
        tester,
        zones: (h) => [SamplerZone(id: 'z', sample: h, root: 50, lo: 40, hi: 60)],
      );
      final o = mapOrigin(tester);
      await tester.dragFrom(o + const Offset(500, 3), const Offset(0, 30));
      await tester.pump();
      final z = c.doc.tracks[1].zones.single;
      expect(z.vhi, inInclusiveRange(90, 96));
      expect(z.vlo, 1);
      final vhi = z.vhi;
      await tester.dragFrom(o + const Offset(500, 70), const Offset(30, 20));
      await tester.pump();
      expect((z.lo, z.hi, z.root), (43, 63, 53));
      expect((z.vlo, z.vhi), (1, vhi), reason: 'arrastar o corpo na diagonal só move as notas');
    });

    panelTest('nota base e velocidade aceitam digitação; passos de 1', (tester) async {
      final (c, _, _) = await mount(
        tester,
        zones: (h) => [SamplerZone(id: 'z', sample: h, root: 50, lo: 40, hi: 60, vlo: 10, vhi: 100)],
      );
      await tester.tapAt(mapOrigin(tester) + const Offset(500, 60));
      await tester.pump();
      final z = c.doc.tracks[1].zones.single;
      final fields = find.byType(TextField);
      expect(fields, findsNWidgets(5));
      await tester.enterText(fields.at(0), 'C#3');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(z.root, 49);
      await tester.enterText(fields.at(0), '61');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(z.root, 61);
      await tester.enterText(fields.at(0), 'lixo');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(z.root, 61, reason: 'o que não entendeu não muda nada');
      expect(tester.widget<TextField>(fields.at(0)).controller!.text, 'C#4', reason: 'e o campo volta ao valor');
      await tester.enterText(fields.at(3), '64');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(z.vlo, 64);
      await tester.enterText(fields.at(3), '0');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(z.vlo, 64, reason: 'velocidade 0 não vale');
      // Menos/Mais andam de 1 em 1 (velocidade de: o quarto stepper)
      await tester.tap(find.byTooltip('Mais').at(3));
      await tester.pump();
      expect(z.vlo, 65);
      await tester.tap(find.byTooltip('Menos').at(4));
      await tester.pump();
      expect(z.vhi, 99);
    });

    panelTest('dividir em camadas de velocidade cria cópias com as faixas iguais', (tester) async {
      final (c, e, _) = await mount(
        tester,
        zones: (h) => [SamplerZone(id: 'z', sample: h, root: 50, lo: 40, hi: 60)],
      );
      await tester.tapAt(mapOrigin(tester) + const Offset(500, 60));
      await tester.pump();
      await tester.ensureVisible(find.text('Camadas de velocidade'));
      await tester.tap(find.text('Camadas de velocidade'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dividir em 3 camadas iguais'));
      await tester.pumpAndSettle();
      final zs = c.doc.tracks[1].zones;
      expect(zs.map((z) => (z.lo, z.hi, z.vlo, z.vhi)), [(40, 60, 1, 42), (40, 60, 43, 84), (40, 60, 85, 127)]);
      expect(zs.map((z) => z.id).toSet(), hasLength(3));
      expect(e.sent('zone_add'), hasLength(3));
      expect(find.textContaining('2 cópias criadas'), findsOneWidget);
      c.undo();
      expect(c.doc.tracks[1].zones, hasLength(1));
      expect((c.doc.tracks[1].zones.single.vlo, c.doc.tracks[1].zones.single.vhi), (1, 127));
    });

    panelTest('acrescentar zona com o teclado cheio divide a existente e avisa', (tester) async {
      final (c, _, hash) = await mount(
        tester,
        zones: (h) => [SamplerZone(id: 'z', sample: h)],
      );
      await tester.tap(find.text('Adicionar sample como zona'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('loop.wav'));
      await tester.pumpAndSettle();
      final zs = c.doc.tracks[1].zones;
      expect(zs, hasLength(2));
      expect((zs[0].lo, zs[0].hi, zs[1].lo, zs[1].hi), (0, 63, 64, 127));
      expect(zs[1].sample, hash);
      expect(find.textContaining('foi dividida'), findsOneWidget);
    });

    panelTest('round-robin oferece os grupos 1 a 63, os mesmos do motor', (tester) async {
      final (c, _, _) = await mount(
        tester,
        zones: (h) => [SamplerZone(id: 'z', sample: h, group: 40)],
      );
      await tester.tapAt(mapOrigin(tester) + const Offset(500, 60));
      await tester.pump();
      expect(find.text('grupo 40'), findsOneWidget, reason: 'um grupo acima de 15 aparece como ele mesmo');
      await tester.ensureVisible(find.text('grupo 40'));
      await tester.tap(find.text('grupo 40'));
      await tester.pumpAndSettle();
      await tester.dragUntilVisible(find.text('grupo 63'), find.byType(Scrollable).last, const Offset(0, -100));
      await tester.tap(find.text('grupo 63'));
      await tester.pumpAndSettle();
      expect(c.doc.tracks[1].zones.single.group, 63);
      expect(maxZoneGroup, 63);
    });

    panelTest('arraste que começa fora de qualquer bloco não muda zona nenhuma', (tester) async {
      final (c, e, _) = await mount(
        tester,
        zones: (h) => [SamplerZone(id: 'z', sample: h, lo: 40, hi: 60)],
      );
      final o = mapOrigin(tester);
      await tester.dragFrom(o + const Offset(900, 60), const Offset(-200, 0));
      await tester.pump();
      final z = c.doc.tracks[1].zones.single;
      expect((z.lo, z.hi), (40, 60));
      expect(e.sent('zone_add'), isEmpty);
    });

    panelTest('tocar seleciona, mostra a edição e os passos mudam a zona', (tester) async {
      final (c, _, _) = await mount(
        tester,
        zones: (h) => [SamplerZone(id: 'z', sample: h, root: 50, lo: 40, hi: 60), SamplerZone(id: 'y', sample: h, root: 80, lo: 70, hi: 90)],
      );
      final o = mapOrigin(tester);
      expect(find.text('Nota base'), findsNothing);
      await tester.tapAt(o + const Offset(800, 60));
      await tester.pump();
      expect(find.text('Nota base'), findsOneWidget);
      // o botão "mais" da nota base: o primeiro dos steppers
      await tester.tap(find.byTooltip('Mais').first);
      await tester.pump();
      expect(c.doc.tracks[1].zones.last.root, 81);
      await tester.tapAt(o + const Offset(1200, 60));
      await tester.pump();
      expect(find.text('Nota base'), findsNothing, reason: 'tocar fora tira a seleção');
    });

    panelTest('modo, grupo e loop editam a zona', (tester) async {
      final (c, _, _) = await mount(
        tester,
        zones: (h) => [SamplerZone(id: 'z', sample: h, lo: 0, hi: 127)],
      );
      final o = mapOrigin(tester);
      await tester.tapAt(o + const Offset(500, 60));
      await tester.pump();
      final z = c.doc.tracks[1].zones.single;
      await tester.ensureVisible(find.text('Loop enquanto a nota está presa'));
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      expect(z.hasLoop, isTrue);
      expect(z.loopEnd, greaterThan(z.loopStart));
      await tester.tap(find.text('Até o fim'));
      await tester.pump();
      expect(z.oneShot, isTrue);
      expect(find.text('Loop enquanto a nota está presa'), findsNothing, reason: 'o loop só vale no modo sustentado');
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pump();
      expect(c.doc.tracks[1].zones, isEmpty);
    });

    panelTest('celular: cabe em 360 px sem estourar e o mapa rola', (tester) async {
      final (c, _, _) = await mount(
        tester,
        width: 360,
        zones: (h) => [SamplerZone(id: 'z', sample: h, lo: 0, hi: 127), SamplerZone(id: 'y', sample: h, lo: 60, hi: 72)],
      );
      await tester.tapAt(mapOrigin(tester) + const Offset(200, 50));
      await tester.pump();
      expect(find.text('Nota base'), findsOneWidget);
      expect(tester.takeException(), isNull);
      // arrastar num vazio rolaria o mapa: aqui o bloco cobre tudo, então só confere o tamanho
      expect(tester.getSize(find.byKey(const ValueKey('zone-map'))).width, 1024);
      expect(c.doc.tracks[1].zones, hasLength(2));
    });

    panelTest('com zonas o Modo do cartão Áudio não vale: envelope normal e teclado marca as notas das zonas', (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      late DawController c;
      await tester.runAsync(() async {
        (c, _, _) = await sampler();
      });
      c.setParam(1, SamplerId.oneShot, 1);
      c.setParam(1, SamplerId.root, 55);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: ListenableBuilder(
              listenable: c,
              builder: (_, _) => InstrumentPanel(c: c),
            ),
          ),
        ),
      );
      Set<int> marks() => (tester.widget(find.byWidgetPredicate((w) => w.runtimeType.toString() == '_PianoKeys')) as dynamic).marks as Set<int>;
      expect(find.text('até o fim: a soltura não entra'), findsOneWidget, reason: 'sem zonas o Modo vale');
      expect(marks(), {55}, reason: 'sem zonas: a nota base do cartão');
      c.doc.tracks[1].zones
        ..add(SamplerZone(id: 'a', sample: c.doc.tracks[1].sample!, lo: 40, hi: 44))
        ..add(SamplerZone(id: 'b', sample: c.doc.tracks[1].sample!, lo: 60, hi: 61));
      c.mutate((_) {});
      await tester.pump();
      expect(find.text('até o fim: a soltura não entra'), findsNothing, reason: 'com zonas o Modo do cartão não vale');
      expect(marks(), {40, 41, 42, 43, 44, 60, 61});
      expect(tester.takeException(), isNull);
    });

    panelTest('diálogo de fatiar: prévia, criar e substituir as zonas', (tester) async {
      tester.view.physicalSize = const Size(900, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      late DawController c;
      await tester.runAsync(() async {
        (c, _, _) = await sampler(x: bursts([(0.3, 0.8), (0.8, 0.7), (1.2, 0.9)], 1.8));
      });
      c.addZone(1, c.doc.tracks[1].sample!);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(body: SliceDialog(c: c, track: 1)),
        ),
      );
      expect(find.textContaining('4 fatias: C1 a D#1'), findsOneWidget);
      expect(find.textContaining('Criar substitui as zonas atuais'), findsOneWidget);
      await tester.tap(find.text('N fatias iguais'));
      await tester.pump();
      expect(find.textContaining('8 fatias: C1 a G1'), findsOneWidget);
      await tester.tap(find.byTooltip('Mais uma fatia'));
      await tester.pump();
      expect(find.textContaining('9 fatias'), findsOneWidget);
      await tester.tap(find.text('4'));
      await tester.pump();
      await tester.tap(find.text('Criar'));
      await tester.pumpAndSettle();
      expect(c.doc.tracks[1].zones, hasLength(4));
      expect(c.doc.tracks[1].zones.first.start, 0);
    });

    panelTest('diálogo de fatiar sem áudio no projeto ou com o áudio ausente do aparelho', (tester) async {
      final e = FakeEngine();
      final c = fakeController(e);
      open.add(c);
      c.addInstrumentTrack(TrackKind.sampler);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(body: SliceDialog(c: c, track: 1)),
        ),
      );
      expect(find.textContaining('Nenhum áudio no projeto ainda'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Criar')).onPressed, isNull);
      c.doc.samples['h'] = const SampleInfo('perdido.wav', 1);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: SliceDialog(key: UniqueKey(), c: c, track: 1),
          ),
        ),
      );
      expect(find.textContaining('não está neste aparelho'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Criar')).onPressed, isNull);
    });
  });

  group('paridade com o motor', () {
    // Os mesmos vetores de `paridade_com_o_dart` em engine/src/sampler_zones_tests.rs (o fatiamento do
    // motor só existe lá como referência de teste): sinal só de aritmética exata, LCG inteiro.
    Float32List paritySignal() {
      var seed = 12345;
      double rnd() {
        seed = (seed * 1664525 + 1013904223) & 0xFFFFFFFF;
        return (seed >> 8) / (1 << 24) * 2 - 1;
      }

      final x = List<double>.generate(96000, (_) => 1e-4 * rnd());
      for (final (s, amp) in [(14400, 0.8), (38400, 0.7), (57600, 0.9), (84000, 0.6)]) {
        for (var k = 0; k < 5760; k++) {
          x[s + k] += amp * math.pow(0.5, k ~/ 1440) * rnd();
        }
      }
      return Float32List.fromList(x);
    }

    void near(List<double> got, List<double> want) {
      expect(got, hasLength(want.length), reason: '$got');
      for (var i = 0; i < want.length; i++) {
        expect(got[i], closeTo(want[i], 1e-12), reason: '$got');
      }
    }

    test('transientes em qualquer sensibilidade', () {
      const want = [0.0, 0.2999791666666667, 0.8, 1.2, 1.7498958333333334];
      for (final sensitivity in [0.0, 0.5, 1.0]) {
        near(slicePoints(audio([paritySignal()]), sensitivity: sensitivity), want);
      }
    });

    test('fatias iguais e as zonas que saem delas', () {
      near(slicePoints(audio([Float32List(50000)]), count: 7), [
        0.0,
        0.1488125,
        0.297625,
        0.4464375,
        0.5952291666666667,
        0.7440416666666667,
        0.8928541666666666,
      ]);
      const want = [0.0, 0.2999791666666667, 0.8, 1.2, 1.7498958333333334];
      final z = sliceZones('h', want, () => 'id');
      expect(z.map((z) => (z.root, z.start, z.end)), [(24, 0.0, want[1]), (25, want[1], 0.8), (26, 0.8, 1.2), (27, 1.2, want[4]), (28, want[4], 0.0)]);
    });
  });
}
