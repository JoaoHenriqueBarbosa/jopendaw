import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:jopendaw_app/audio/engine.dart';
import 'package:jopendaw_app/audio/engine_ffi.dart' show prepareRenderCalls, renderFrames, renderTempo, renderTempoMap;
import 'package:jopendaw_app/daw/controller.dart';
import 'package:jopendaw_app/daw/model.dart';
import 'package:jopendaw_app/daw/tempo_map.dart';
import 'package:jopendaw_app/models/project.dart';

final engine = AudioEngine.instance;

DawController newController() {
  final c = DawController(
    Project.fromJson({
      'id': 'p',
      'name': 'Teste',
      'bpm': 120,
      'beats_per_bar': 4,
      'beat_unit': 4,
      'sample_rate': 48000,
      'created_at': '2026-01-01T00:00:00Z',
      'updated_at': '2026-01-01T00:00:00Z',
    }),
  );
  c.doc = DawDoc(
    bpm: 120,
    beatsPerBar: 4,
    tracks: [DawTrack(id: 'a', name: 'Áudio 1', color: 0)],
  );
  c.ready = true;
  return c;
}

List<List<Object>> sent(String name) => [
  for (final c in engine.log!)
    if (c.first == name) c,
];

/// O andamento único de antes, por extenso.
double oldSeconds(double beat, double bpm) => beat * 60 / bpm;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    engine.log = [];
  });

  group('TempoMap', () {
    test('um ponto só é exatamente a conta de antes', () {
      final m = TempoMap.constant(137);
      for (final b in [0.0, 0.25, 1.0, 7.5, 1234.567]) {
        expect(m.secondsAt(b), oldSeconds(b, 137));
        expect(m.beatAt(m.secondsAt(b)), closeTo(b, 1e-9));
      }
      expect(m.isSingle, isTrue);
      expect(TempoMap(120, const [TempoPoint(0, 120, ramp: true)]).isSingle, isTrue, reason: 'uma rampa sem ponto seguinte não faz nada');
    });

    test('rampa de 60 a 120 em 4 batidas dura 4·ln 2 segundos', () {
      final m = TempoMap(60, const [TempoPoint(0, 60, ramp: true), TempoPoint(4, 120)]);
      expect(m.secondsAt(4), closeTo(4 * math.ln2, 1e-12));
      expect(m.secondsAt(6), closeTo(4 * math.ln2 + 1, 1e-12));
      expect(m.beatAt(4 * math.ln2), closeTo(4, 1e-12));
      // integração numérica (ponto médio)
      var t = 0.0;
      const n = 100000;
      for (var i = 0; i < n; i++) {
        final x = (i + 0.5) / n * 4;
        t += 60 / (60 + 60 * x / 4) * (4 / n);
      }
      expect(m.secondsAt(4), closeTo(t, 1e-6));
      expect(m.bpmAt(2), closeTo(90, 1e-12));
    });

    test('salto: andamento constante até o ponto seguinte', () {
      final m = TempoMap(120, const [TempoPoint(0, 120), TempoPoint(4, 60), TempoPoint(8, 240)]);
      expect(m.secondsAt(4), 2);
      expect(m.secondsAt(8), 2 + 4);
      expect(m.secondsAt(10), 2 + 4 + 0.5);
      expect(m.bpmAt(3.99), 120);
      expect(m.bpmAt(4), 60);
      expect(m.bpmAt(99), 240);
      expect(m.pointAt(4)?.bpm, 60);
      expect(m.pointAt(5), isNull);
    });

    test('vai e volta em todo o mapa, com andamentos extremos e rampas', () {
      final m = TempoMap(20, const [
        TempoPoint(0, 20, ramp: true),
        TempoPoint(2, 400, ramp: true),
        TempoPoint(6, 60),
        TempoPoint(10, 999, ramp: true),
        TempoPoint(11, 20),
      ]);
      var prev = -1.0;
      for (var b = 0.0; b < 30; b += 0.031) {
        final s = m.secondsAt(b);
        expect(s, greaterThan(prev));
        prev = s;
        expect(m.beatAt(s), closeTo(b, 1e-9), reason: 'batida $b');
      }
    });

    test('256 pontos', () {
      final pts = [for (var i = 0; i < 256; i++) TempoPoint(i * 2.0, 60.0 + (i * 37 % 200), ramp: i % 3 == 0)];
      final m = TempoMap(pts.first.bpm, pts);
      expect(m.points, hasLength(256));
      for (var i = 0; i < 256; i++) {
        final b = i * 2.0 + 0.7;
        expect(m.beatAt(m.secondsAt(b)), closeTo(b, 1e-8));
      }
    });

    test('desordenados, duplicados e sujos são tratados', () {
      final m = TempoMap(120, const [
        TempoPoint(8, 90),
        TempoPoint(4, 60),
        TempoPoint(8, 100, ramp: true), // duplicado: o último vale
        TempoPoint(-5, 70), // negativo vira 0
        TempoPoint(2, 5000), // limite
        TempoPoint(double.nan, 80),
        TempoPoint(3, double.infinity),
      ]);
      expect(m.points.map((p) => p.beat), [0, 2, 4, 8]);
      // o andamento inicial é o do documento (120), não o do ponto sujo
      expect(m.bpm0, 120);
      expect(m.points[1].bpm, maxBpm);
      expect(m.points[3], const TempoPoint(8, 100, ramp: true));
      expect(normalizeTempoPoints(const [], 90), isEmpty);
      expect(normalizeTempoPoints(const [TempoPoint(0, 90, ramp: true)], 90), isEmpty);
      expect(normalizeTempoPoints(const [TempoPoint(4, 90)], 120).first, const TempoPoint(0, 120));
    });

    test('JSON dos pontos', () {
      const p = TempoPoint(4, 90.5, ramp: true);
      expect(p.toJson(), {'beat': 4.0, 'bpm': 90.5, 'ramp': 1});
      expect(TempoPoint.fromJson(p.toJson()), p);
      expect(TempoPoint.fromJson({'beat': 1, 'bpm': 100}), const TempoPoint(1, 100));
      expect(TempoPoint.fromJson({'beat': 1, 'bpm': 100, 'ramp': true}).ramp, isTrue);
    });
  });

  group('MeterMap', () {
    test('compassos com mudanças', () {
      final m = MeterMap(4, const [MeterChange(3, 3, 4), MeterChange(5, 6, 8), MeterChange(7, 7, 8)]);
      expect(m.barStart(1), 0);
      expect(m.barStart(3), 8);
      expect(m.barStart(5), 14);
      expect(m.barStart(7), 20);
      expect(m.barStart(9), 27);
      expect(m.barOf(0), (1, 0.0));
      expect(m.barOf(8), (3, 0.0));
      expect(m.barOf(13.5).$1, 4);
      expect(m.barOf(23.5), (8, 0.0));
      expect(m.barBeats(6), 3);
      expect(m.nearestBarStart(9.4), 8);
      expect(m.nearestBarStart(10.6), 11);
    });

    test('sem mudanças é o compasso de sempre', () {
      final m = MeterMap.constant(3);
      expect(m.isSingle, isTrue);
      expect(m.barStart(4), 9);
      expect(m.barOf(10.5), (4, 1.5));
      expect(normalizeMeterChanges(const [], 4), isEmpty);
      expect(normalizeMeterChanges(const [MeterChange(1, 4, 4)], 4), isEmpty);
      expect(normalizeMeterChanges(const [MeterChange(1, 6, 8)], 4), hasLength(1));
    });

    test('formatPosition usa o mapa de compassos', () {
      final m = MeterMap(4, const [MeterChange(2, 3, 4)]);
      expect(formatPosition(0, 4, meter: m), '1.1.1');
      expect(formatPosition(4, 4, meter: m), '2.1.1');
      expect(formatPosition(7, 4, meter: m), '3.1.1');
      expect(formatPosition(7.5, 4, meter: m), '3.1.3');
      // sem mapa é o de sempre
      expect(formatPosition(9.25, 4), '3.2.2');
      expect(formatPosition(9.25, 4, meter: MeterMap.constant(4)), '3.2.2');
      final six8 = MeterMap(4, const [MeterChange(1, 6, 8)]);
      expect(formatPosition(1.5, 4, meter: six8), '1.4.1', reason: 'cada colcheia é um tempo');
    });
  });

  group('documento', () {
    Map<String, dynamic> oldDoc() => {
      'version': 1,
      'bpm': 100.0,
      'beats_per_bar': 3,
      'tracks': <dynamic>[],
      'samples': <String, dynamic>{},
      'loop_on': false,
      'loop_start': 0.0,
      'loop_end': 16.0,
      'metronome': false,
      'master_gain': 1.0,
      'master_pan': 0.0,
      'count_in': true,
      'rec_latency_ms': 0.0,
      'master_effects': <dynamic>[],
      'master_lanes': <dynamic>[],
      'markers': <dynamic>[],
    };

    test('documento antigo abre e salva igual, sem os campos novos', () {
      final j = oldDoc();
      final d = DawDoc.fromJson(jsonDecode(jsonEncode(j)));
      expect(d.tempoMap, isEmpty);
      expect(d.meterMap, isEmpty);
      expect(d.tempo.isSingle, isTrue);
      expect(jsonEncode(d.toJson()), jsonEncode(j));
      expect(d.toJson().containsKey('tempo_map'), isFalse);
      expect(d.toJson().containsKey('meter_map'), isFalse);
    });

    test('com mapa: ida e volta pelo JSON, o ponto 0 é o bpm do documento', () {
      final d = DawDoc(
        bpm: 90,
        beatsPerBar: 4,
        tempoMap: const [TempoPoint(0, 90, ramp: true), TempoPoint(8, 140), TempoPoint(16, 100)],
        meterMap: const [MeterChange(1, 4, 4), MeterChange(5, 7, 8)],
      );
      final j = jsonDecode(jsonEncode(d.toJson())) as Map<String, dynamic>;
      expect(j['tempo_map'], [
        {'beat': 0.0, 'bpm': 90.0, 'ramp': 1},
        {'beat': 8.0, 'bpm': 140.0, 'ramp': 0},
        {'beat': 16.0, 'bpm': 100.0, 'ramp': 0},
      ]);
      expect(j['meter_map'], [
        {'bar': 1, 'num': 4, 'den': 4},
        {'bar': 5, 'num': 7, 'den': 8},
      ]);
      final back = DawDoc.fromJson(j);
      expect(back.tempoMap, d.tempoMap);
      expect(back.meterMap, d.meterMap);
      expect(jsonEncode(back.toJson()), jsonEncode(d.toJson()));
      // o bpm do documento manda no ponto 0
      d.bpm = 100;
      expect(d.tempo.bpm0, 100);
      expect(d.toJson()['tempo_map'][0]['bpm'], 100.0);
    });

    test('campos estranhos não derrubam', () {
      final j = oldDoc()
        ..['tempo_map'] = [
          {'beat': 8, 'bpm': 90},
          {'beat': 4, 'bpm': 'x'},
        ];
      expect(() => DawDoc.fromJson(j), throwsA(anything), reason: 'ponto com bpm que não é número não passa calado');
      final ok = oldDoc()
        ..['tempo_map'] = [
          {'beat': 8, 'bpm': 90},
          {'beat': 8, 'bpm': 95},
          {'beat': -3, 'bpm': 50},
        ]
        ..['meter_map'] = [
          {'bar': 0, 'num': 200, 'den': 3},
        ];
      final d = DawDoc.fromJson(ok);
      expect(d.tempo.points.map((p) => p.beat), [0, 8]);
      expect(d.tempo.points[0].bpm, 100, reason: 'o bpm do documento manda');
      expect(d.tempo.points[1].bpm, 95);
      // um compasso n/4 só é o `beats_per_bar` do documento: sem mudanças
      expect(d.meterMap, isEmpty);
      expect(d.meter.isSingle, isTrue);
    });

    test('duração e fim do clipe pelo mapa', () {
      final d = DawDoc(bpm: 120, beatsPerBar: 4, tempoMap: const [TempoPoint(0, 120), TempoPoint(4, 60)]);
      final clip = AudioClip(id: 'c', sample: 's', start: 2, length: 4);
      d.tracks.add(DawTrack(id: 't', name: 'A', color: 0, clips: [clip]));
      // começa na batida 2 (1 s), dura 4 s: termina em 5 s = 4 batidas (2 s) + 3 s a 60 bpm = 3 batidas
      expect(d.clipEnd(clip), closeTo(7, 1e-12));
      expect(d.clipBeats(clip), closeTo(5, 1e-12));
      expect(d.contentEnd, closeTo(7, 1e-12));
      expect(d.durationSeconds, closeTo(5, 1e-12));
      // um andamento só: a conta de sempre, com o mesmo resultado exato
      final single = DawDoc(
        bpm: 120,
        beatsPerBar: 4,
        tracks: [
          DawTrack(
            id: 't',
            name: 'A',
            color: 0,
            clips: [AudioClip(id: 'c', sample: 's', start: 2, length: 4)],
          ),
        ],
      );
      expect(single.contentEnd, 2 + 4 * 120 / 60);
      expect(single.durationSeconds, single.contentEnd * 60 / 120);
    });

    test('clipe com warp ocupa o tempo do andamento inicial', () {
      final clip = AudioClip(id: 'c', sample: 's', start: 0, length: 2, warp: true, sourceBpm: 60);
      final d = DawDoc(bpm: 120, beatsPerBar: 4, tempoMap: const [TempoPoint(0, 120), TempoPoint(2, 240)]);
      // 2 s de áudio a 60 BPM esticados para 120: 1 s de tempo real = 2 batidas, no ponto do salto
      expect(clip.seconds(120), 1);
      expect(d.clipEnd(clip), closeTo(2, 1e-12));
      clip.length = 4; // 2 s reais: 1 s a 120 (2 batidas) + 1 s a 240 (4 batidas)
      expect(d.clipEnd(clip), closeTo(6, 1e-12));
    });

    test('segundos da origem entre batidas', () {
      final d = DawDoc(bpm: 120, beatsPerBar: 4, tempoMap: const [TempoPoint(0, 120), TempoPoint(4, 60)]);
      final clip = AudioClip(id: 'c', sample: 's', start: 0, length: 10);
      expect(d.sourceSeconds(clip, 2, 6), closeTo(1 + 2, 1e-12));
      expect(DawDoc(bpm: 120, beatsPerBar: 4).sourceSeconds(clip, 2, 6), 2);
    });
  });

  group('controlador', () {
    test('sem mapa nenhuma chamada nova vai ao motor', () {
      final c = newController();
      c.mutate((d) {});
      for (final n in ['tempo_clear', 'tempo_point', 'meter_clear', 'meter_point']) {
        expect(sent(n), isEmpty, reason: n);
      }
      expect(sent('tempo'), isNotEmpty);
    });

    test('o mapa vai ao motor logo depois do tempo, só quando muda', () async {
      final c = newController();
      c.setTempoMap(const [TempoPoint(0, 100, ramp: true), TempoPoint(8, 160)]);
      expect(c.doc.bpm, 100);
      final calls = engine.log!.where((x) => const ['tempo', 'tempo_clear', 'tempo_point', 'tracks'].contains(x.first)).toList();
      final at = calls.lastIndexWhere((x) => x.first == 'tempo');
      expect(calls.sublist(at, at + 4), [
        ['tempo', 100.0, 4],
        ['tempo_clear'],
        ['tempo_point', 0.0, 100.0, 1],
        ['tempo_point', 8.0, 160.0, 0],
      ]);
      engine.log!.clear();
      c.mutate((d) {}); // nada mudou no mapa: não reenvia
      expect(sent('tempo_clear'), isEmpty);
      expect(sent('tempo_point'), isEmpty);
      // voltar a um andamento só limpa o mapa do motor uma vez
      c.setTempoMap(const []);
      expect(sent('tempo_clear'), hasLength(1));
      expect(sent('tempo_point'), isEmpty);
      engine.log!.clear();
      c.mutate((d) {});
      expect(sent('tempo_clear'), isEmpty);
    });

    test('mapa de compassos vai ao motor', () {
      final c = newController();
      c.setMeterAt(3, 6, 8);
      expect(c.doc.meterMap, const [MeterChange(1, 4, 4), MeterChange(3, 6, 8)]);
      expect(sent('meter_clear'), hasLength(1));
      expect(sent('meter_point'), [
        ['meter_point', 1, 4, 4],
        ['meter_point', 3, 6, 8],
      ]);
      // mudar para o que já vale não faz nada
      final n = c.doc.meterMap.length;
      c.setMeterAt(4, 6, 8);
      expect(c.doc.meterMap, hasLength(n));
      c.removeMeterChange(3);
      expect(c.doc.meterMap, isEmpty);
    });

    test('ganchos do importador de MIDI: setTempoMap e setMeterMap', () {
      final c = newController();
      c.setTempoMap(const [TempoPoint(8, 90), TempoPoint(0, 140), TempoPoint(4, 100, ramp: true)]);
      expect(c.doc.bpm, 140, reason: 'o ponto da batida 0 é o andamento inicial');
      expect(c.doc.tempoMap.map((p) => p.beat), [0, 4, 8]);
      c.setMeterMap(const [MeterChange(1, 3, 4), MeterChange(4, 5, 4)]);
      expect(c.doc.beatsPerBar, 3);
      expect(c.doc.meter.barStart(4), 9);
      c.setMeterMap(const [MeterChange(1, 6, 8)]);
      expect(c.doc.beatsPerBar, 3, reason: '6/8 são 3 batidas de semínima');
      expect(c.doc.meter.changes.single, const MeterChange(1, 6, 8));
      c.setMeterMap(const [MeterChange(1, 5, 4)]);
      expect(c.doc.meterMap, isEmpty);
      expect(c.doc.beatsPerBar, 5);
      c.setTempoMap(const [TempoPoint(0, 111)]);
      expect(c.doc.bpm, 111);
      expect(c.doc.tempoMap, isEmpty);
    });

    test('adicionar, mover, mudar salto/rampa e apagar pontos; desfazer e refazer', () {
      final c = newController();
      c.addTempoPoint(8);
      expect(c.doc.tempo.points.map((p) => (p.beat, p.bpm)), [(0.0, 120.0), (8.0, 120.0)]);
      c.moveTempoPoint(1, bpm: 90);
      expect(c.doc.bpmAt(10), 90);
      c.moveTempoPoint(1, beat: 4);
      expect(c.doc.tempo.points[1].beat, 4);
      c.addTempoPoint(12, bpm: 150);
      c.setTempoPointRamp(1, true);
      expect(c.doc.tempo.points[1].ramp, isTrue);
      expect(c.doc.bpmAt(8), closeTo(120, 1e-9), reason: 'rampa de 90 a 150 na metade');
      // o primeiro ponto só muda de andamento; arrastar além do vizinho para no vizinho
      c.moveTempoPoint(0, beat: 5, bpm: 100);
      expect(c.doc.tempo.points[0].beat, 0);
      expect(c.doc.bpm, 100);
      c.moveTempoPoint(1, beat: 50);
      expect(c.doc.tempo.points[1].beat, lessThan(12));
      // dois pontos na mesma batida não existem: adicionar onde há um só troca o andamento
      final n = c.doc.tempo.points.length;
      c.addTempoPoint(12, bpm: 77);
      expect(c.doc.tempo.points, hasLength(n));
      expect(c.doc.bpmAt(20), 77);
      c.removeTempoPoint(0); // o inicial não sai
      expect(c.doc.tempo.points.first.beat, 0);
      c.removeTempoPoint(2);
      expect(c.doc.tempo.points, hasLength(n - 1));
      // desfazer volta passo a passo
      c.undo();
      expect(c.doc.tempo.points, hasLength(n));
      c.redo();
      expect(c.doc.tempo.points, hasLength(n - 1));
      while (c.canUndo) {
        c.undo();
      }
      expect(c.doc.tempoMap, isEmpty);
      expect(c.doc.bpm, 120);
    });

    test('arrastar é um passo só no histórico', () {
      final c = newController();
      c.addTempoPoint(8);
      final before = c.doc.toJson();
      c.checkpoint();
      for (var b = 100; b >= 60; b -= 5) {
        c.moveTempoPoint(1, bpm: b.toDouble(), undoable: false);
      }
      expect(c.doc.bpmAt(9), 60);
      c.undo();
      expect(jsonEncode(c.doc.toJson()), jsonEncode(before));
    });

    test('relógio em segundos e encaixe usam os mapas', () {
      final c = newController();
      c.setTempoMap(const [TempoPoint(0, 120), TempoPoint(4, 60)]);
      expect(c.secondsAt(4), 2);
      expect(c.secondsAt(6), 4);
      expect(c.bpmAt(5), 60);
      c.setMeterMap(const [MeterChange(1, 4, 4), MeterChange(2, 3, 4)]);
      c.snap = Snap.bar;
      expect(c.snapBeat(6.9), 7);
      expect(c.snapBeat(5.4), 4);
    });

    test('mapa de andamento não muda no meio da gravação', () {
      final c = newController();
      c.recording = true;
      c.addTempoPoint(8);
      c.setMeterAt(2, 3, 4);
      expect(c.doc.tempoMap, isEmpty);
      expect(c.doc.meterMap, isEmpty);
      c.recording = false;
    });

    test('cortar um clipe com mapa de andamento respeita os segundos reais', () {
      final c = newController();
      c.setTempoMap(const [TempoPoint(0, 120), TempoPoint(4, 60)]);
      final clip = AudioClip(id: 'c', sample: 's', start: 0, length: 6);
      c.doc.tracks.first.clips.add(clip);
      c.doc.samples['s'] = const SampleInfo('a', 6);
      c.seek(6);
      c.selectClip('c');
      c.splitAtPlayhead();
      // batida 6 = 2 s (até a 4) + 2 s = 4 s
      final left = c.doc.tracks.first.clips.firstWhere((x) => x.start == 0);
      final right = c.doc.tracks.first.clips.firstWhere((x) => x.start == 6);
      expect(left.length, closeTo(4, 1e-9));
      expect(right.offset, closeTo(4, 1e-9));
      expect(right.length, closeTo(2, 1e-9));
    });
  });

  group('recordingPasses com mapa', () {
    test('as voltas do loop caem no quadro que o motor conta', () {
      // loop 0..4 numa taxa didática de 100 quadros/s: 120 bpm até a batida 2 (1 s), depois 60 (2 s)
      final map = TempoMap(120, const [TempoPoint(0, 120), TempoPoint(2, 60)]);
      final passes = recordingPasses(start: 0, frames: 1000, bpm: 120, rate: 100, loopOn: true, loopStart: 0, loopEnd: 4, tempo: map);
      expect(passes.map((p) => p.frame), [0, 300, 600, 900]);
      // sem mapa, o mesmo loop a 120 bpm: 2 s por volta
      final flat = recordingPasses(start: 0, frames: 1000, bpm: 120, rate: 100, loopOn: true, loopStart: 0, loopEnd: 4);
      expect(flat.map((p) => p.frame), [0, 200, 400, 600, 800]);
    });
  });

  group('render', () {
    test('mapa das chamadas: tempo, tempo_clear e tempo_point em ordem', () {
      final calls = <List<Object>>[
        ['tempo', 100, 4],
        ['tempo_point', 4.0, 50.0, 0],
        ['tempo_clear'],
        ['tempo', 120, 4],
        ['tempo_point', 0.0, 120.0, 1],
        ['tempo_point', 4.0, 60.0, 0],
        ['play'],
      ];
      final m = renderTempoMap(calls);
      expect(m.points, const [TempoPoint(0, 120, ramp: true), TempoPoint(4, 60)]);
      expect(renderTempo(calls), 120);
      expect(renderTempoMap(const []).isSingle, isTrue);
      expect(
        renderTempoMap(const [
          ['tempo', 90, 4],
        ]).bpm0,
        90,
      );
    });

    test('quadros do trecho e clipes cortados seguem o mapa', () {
      final map = TempoMap(120, const [TempoPoint(0, 120), TempoPoint(4, 60)]);
      // 0..6 batidas = 2 s + 2 s
      expect(renderFrames(0, 6, 1, 120, 48000, map: map), (range: 192000, tail: 48000, total: 240000));
      expect(renderFrames(2, 6, 0, 120, 48000, map: map), (range: 144000, tail: 0, total: 144000));
      // sem mapa (ou mapa de um ponto), como antes
      expect(renderFrames(0, 4, 1.5, 120, 48000, map: TempoMap.constant(120)), (range: 96000, tail: 72000, total: 168000));
      final out = prepareRenderCalls(
        [
          ['clip_add', 0, 1, 2.0, 0.0, 6.0, 1.0, 0.0, 0.0], // começa na batida 2 (1 s), dura 6 s
          ['clip_add', 0, 1, 7.0, 0.0, 1.0, 1.0, 0.0, 0.0], // depois do fim
        ],
        6,
        120,
        map: map,
      );
      expect(out, hasLength(1));
      // corta na batida 6: 4 s - 1 s = 3 s de clipe
      expect(out.single[5], closeTo(3, 1e-9));
    });

    test('igual ao render-worker.js da web com mapa de andamento', () async {
      final rnd = math.Random(11);
      final cases = <Map<String, Object>>[];
      for (var k = 0; k < 40; k++) {
        final calls = <List<Object>>[
          ['tempo', 40 + rnd.nextInt(200) + rnd.nextDouble(), 4],
          ['tempo_clear'],
          for (var i = 0; i < 1 + rnd.nextInt(8); i++) ['tempo_point', rnd.nextInt(40) * 0.5, 20 + rnd.nextDouble() * 400, rnd.nextInt(2)],
          if (rnd.nextBool()) ['tempo_point', 0.0, 30 + rnd.nextDouble() * 300, rnd.nextInt(2)],
          ['play'],
        ];
        final to = 4.0 + rnd.nextInt(30) + rnd.nextDouble();
        for (var i = 0; i < 4; i++) {
          calls.add(['clip_add', 0, 1, rnd.nextDouble() * to * 1.2, rnd.nextDouble(), 0.5 + rnd.nextDouble() * 20, 1.0, 0.01, 0.2]);
        }
        cases.add({'calls': calls, 'from': rnd.nextInt(3).toDouble(), 'to': to, 'tail': rnd.nextDouble() * 4, 'rate': 44100.0 + rnd.nextInt(3) * 3900});
      }
      final node = Process.runSync('node', ['--version']).exitCode == 0;
      if (!node) {
        markTestSkipped('sem node para rodar o render-worker.js');
        return;
      }
      final dir = await Directory.systemTemp.createTemp('jopendaw_tempo');
      addTearDown(() => dir.delete(recursive: true));
      final input = File('${dir.path}/cases.json')..writeAsStringSync(jsonEncode({'cases': cases}));
      final script = File('${dir.path}/run.js')
        ..writeAsStringSync('''
const rw = require(process.argv[2]);
const input = JSON.parse(require('fs').readFileSync(process.argv[3], 'utf8'));
process.stdout.write(JSON.stringify(input.cases.map((c) => {
  const bpm = rw.tempoOf(c.calls);
  const map = rw.tempoMapOf(c.calls);
  return { frames: rw.frameCounts(c.from, c.to, c.tail, bpm, c.rate, map), calls: rw.prepareCalls(c.calls, c.to, bpm, map), s: [0, 1, 3.3, 9, 25, 61.7].map((b) => map.secondsAt(b)) };
})));
''');
      final r = await Process.run('node', [script.path, File('web/engine/render-worker.js').absolute.path, input.path]);
      expect(r.exitCode, 0, reason: '${r.stderr}');
      final expected = jsonDecode(r.stdout as String) as List;
      for (var k = 0; k < cases.length; k++) {
        final c = cases[k];
        final calls = c['calls'] as List<List<Object>>;
        final e = expected[k] as Map;
        final map = renderTempoMap(calls);
        final bpm = renderTempo(calls);
        final f = renderFrames(c['from'] as double, c['to'] as double, c['tail'] as double, bpm, c['rate'] as double, map: map);
        final ef = e['frames'] as Map;
        expect([f.range, f.tail, f.total], [ef['range'], ef['tail'], ef['total']], reason: 'caso $k');
        final secs = [
          for (final b in [0, 1, 3.3, 9, 25, 61.7]) map.secondsAt(b.toDouble()),
        ];
        for (var i = 0; i < secs.length; i++) {
          expect(secs[i], closeTo((e['s'] as List)[i] as num, 1e-9), reason: 'caso $k, ponto $i');
        }
        final dart = prepareRenderCalls(calls, c['to'] as double, bpm, map: map);
        final js = (e['calls'] as List).cast<List>();
        expect(dart, hasLength(js.length), reason: 'caso $k');
        for (var i = 0; i < dart.length; i++) {
          expect(dart[i].first, js[i].first);
          for (var a = 1; a < dart[i].length; a++) {
            final x = dart[i][a], y = js[i][a];
            if (x is num) {
              expect(x.toDouble(), closeTo((y as num).toDouble(), 1e-9), reason: 'caso $k, chamada $i, argumento $a');
            } else {
              expect(x, y);
            }
          }
        }
      }
    });
  });
}
