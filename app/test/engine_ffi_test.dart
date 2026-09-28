// O que o motor nativo do Android recebe e devolve, conferido no computador sem a biblioteca: o
// JSON das chamadas, o plano do render (o mesmo do render-worker.js da web, conferido contra ele
// pelo node quando há) e a leitura do estado, das notas gravadas e das entradas de áudio.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jopendaw_app/audio/engine.dart';
import 'package:jopendaw_app/audio/engine_ffi.dart';
import 'package:jopendaw_app/daw/controller.dart';
import 'package:jopendaw_app/daw/effects.dart';
import 'package:jopendaw_app/daw/instruments.dart';
import 'package:jopendaw_app/daw/model.dart';
import 'package:jopendaw_app/models/project.dart';

List<Object?> decoded(List<List<Object>> calls) => jsonDecode(utf8.decode(encodeCalls(calls).json)) as List<Object?>;

/// As chamadas como o worklet as vê: booleanos viram 0/1.
List<List<Object>> asWorklet(List<List<Object>> calls) => [
  for (final c in calls) [for (final a in c) a is bool ? (a ? 1 : 0) : a],
];

/// Compara listas de chamadas com os números pelo valor (1 e 1.0 são o mesmo número no JSON); com
/// [tolerance], até essa diferença (contas escritas à mão no teste).
void expectSameCalls(Object? actual, Object? expected, {String? reason, double tolerance = 0}) {
  final a = actual as List, e = expected as List;
  expect(a.length, e.length, reason: reason);
  for (var i = 0; i < a.length; i++) {
    final x = a[i] as List, y = e[i] as List;
    expect(x.length, y.length, reason: '${reason ?? ''} chamada $i: $x ≠ $y');
    for (var k = 0; k < x.length; k++) {
      if (x[k] is num && y[k] is num) {
        final value = (y[k] as num).toDouble();
        expect((x[k] as num).toDouble(), tolerance == 0 ? value : closeTo(value, tolerance), reason: '${reason ?? ''} chamada $i: $x ≠ $y');
      } else {
        expect(x[k], y[k], reason: '${reason ?? ''} chamada $i: $x ≠ $y');
      }
    }
  }
}

DawController studio() {
  final c = DawController(
    Project.fromJson({
      'id': 'p',
      'name': 'Teste',
      'bpm': 97,
      'beats_per_bar': 3,
      'beat_unit': 4,
      'sample_rate': 48000,
      'created_at': '2026-01-01T00:00:00Z',
      'updated_at': '2026-01-01T00:00:00Z',
    }),
  );
  c.doc = DawDoc(
    bpm: 97,
    beatsPerBar: 3,
    tracks: [
      DawTrack(id: 'a', name: 'Áudio 1', color: 0, gain: 0.7, pan: -0.3, mute: true),
      DawTrack(
        id: 's',
        name: 'Sintetizador 1',
        color: 1,
        kind: TrackKind.synth,
        midi: [
          MidiClip(
            id: 'm1',
            name: 'Riff',
            start: 0.5,
            length: 4,
            notes: [MidiNote(pitch: 60, start: 0, length: 1.25), MidiNote(pitch: 64, start: 1, length: 1, velocity: 0.33)],
          ),
        ],
      ),
      DawTrack(id: 'd', name: 'Bateria 1', color: 2, kind: TrackKind.drums, solo: true),
      DawTrack(id: 'b', name: 'Barramento 1', color: 3, kind: TrackKind.bus),
    ],
  );
  c.ready = true;
  return c;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('JSON das chamadas', () {
    test('nomes, inteiros, doubles e booleanos (0/1) como o worklet recebe', () {
      final r = encodeCalls([
        ['tempo', 120, 4],
        ['track', 0, 0.5, -0.25, true, false],
        ['seek', 1e-7],
        ['master', 1.0, 0],
        ['auto_point', 3, 1234567.890625, -1e21, 0.1],
      ]);
      expect(r.skipped, 0);
      expect(utf8.decode(r.json), '[["tempo",120,4],["track",0,0.5,-0.25,1,0],["seek",1e-7],["master",1.0,0],["auto_point",3,1234567.890625,-1e+21,0.1]]');
    });

    test('número não finito tira a chamada inteira (o JSON não tem NaN) e o resto vai', () {
      final r = encodeCalls([
        ['seek', double.nan],
        ['tempo', double.infinity, 4],
        ['play'],
        ['master', 1, double.negativeInfinity],
      ]);
      expect(r.skipped, 3);
      expect(utf8.decode(r.json), '[["play"]]');
      expect(utf8.decode(encodeCalls(const []).json), '[]');
    });

    test('nome com acento e aspas vai escapado em UTF-8; chamada sem nome ou argumento estranho é erro', () {
      expect(
        decoded([
          ['çã"\\', 1],
        ]),
        [
          ['çã"\\', 1],
        ],
      );
      expect(() => encodeCalls([[]]), throwsArgumentError);
      expect(
        () => encodeCalls([
          [1, 2],
        ]),
        throwsArgumentError,
      );
      expect(
        () => encodeCalls([
          ['param', 'x'],
        ]),
        throwsArgumentError,
      );
    });

    test('tudo o que o controlador manda num sync completo passa pelo JSON sem perder nada', () {
      final engine = AudioEngine.instance;
      engine.log = [];
      final c = studio();
      c.addEffect(-1, EffectKind.compressor);
      c.addEffect(1, EffectKind.reverb);
      c.mutate((_) {});
      final log = engine.log!;
      engine.log = null;
      expect(log.length, greaterThan(20));
      final r = encodeCalls(log);
      expect(r.skipped, 0, reason: 'o documento não tem número não finito');
      expectSameCalls(jsonDecode(utf8.decode(r.json)), asWorklet(log));
    });
  });

  group('plano do render', () {
    test('andamento: o último vale, no limite do motor; sem nenhum, 120', () {
      expect(renderTempo(const []), 120);
      expect(
        renderTempo([
          ['tempo', 90, 4],
          ['play'],
          ['tempo', 133.5, 3],
        ]),
        133.5,
      );
      expect(
        renderTempo([
          ['tempo', 5, 4],
        ]),
        20,
      );
      expect(
        renderTempo([
          ['tempo', 5000, 4],
        ]),
        999,
      );
      expect(
        renderTempo([
          ['tempo', 100, 4],
          ['tempo', double.nan, 4],
        ]),
        100,
      );
    });

    test('batidas viram quadros pelo andamento e a cauda pelos segundos', () {
      expect(renderFrames(0, 4, 1.5, 120, 48000), (range: 96000, tail: 72000, total: 168000));
      expect(renderFrames(2, 3, 0, 60, 44100), (range: 44100, tail: 0, total: 44100));
      // um terço de batida a 120 é 8000 quadros; arredonda, não trunca
      expect(renderFrames(0, 1 / 3, 0, 120, 48000).range, 8000);
      expect(renderFrames(5, 4, 1, 120, 48000), (range: 0, tail: 48000, total: 48000));
      expect(renderFrames(0, 1, double.nan, 120, 48000).tail, 0);
    });

    test('corta o que passa do fim: clipe com fade curto, nota encurtada, o que começa no fim sai', () {
      final out = prepareRenderCalls(
        [
          ['tempo', 120, 4],
          ['play'],
          ['seek', 0],
          ['live_on', 0, 60, 1],
          ['watch_fx', -1, -1],
          ['capture_add', 0],
          // 120 bpm: meio segundo por batida
          ['clip_add', 0, 1, 0, 0, 1.0, 1, 0, 0], // termina na batida 2: fica
          ['clip_add', 0, 1, 3, 0.25, 2.0, 0.8, 0.1, 0], // atravessa a batida 4: corta em 0,5 s com fade de 10 ms
          ['clip_add', 0, 1, 3, 0, 2.0, 1, 0, 1.8], // o fade de 1,8 s perde 1,5 s: sobram 0,3 s
          ['clip_add', 0, 1, 4, 0, 1.0, 1, 0, 0], // começa no fim: sai
          ['note_add', 1, 3, 2, 60, 0.7], // atravessa: vai até a 4
          ['note_add', 1, 4, 1, 62, 0.7], // começa no fim: sai
          ['note_add', 1, 1, 1, 64, 0.7],
        ],
        4,
        120,
      );
      expectSameCalls(out, [
        ['tempo', 120, 4],
        ['clip_add', 0, 1, 0, 0, 1.0, 1, 0, 0],
        ['clip_add', 0, 1, 3, 0.25, 0.5, 0.8, 0.1, 0.01],
        ['clip_add', 0, 1, 3, 0, 0.5, 1, 0, 0.3],
        ['note_add', 1, 3, 1, 60, 0.7],
        ['note_add', 1, 1, 1, 64, 0.7],
      ], tolerance: 1e-12);
    });

    test('preparação: sem loop, metrônomo nem observação, uma captura por saída na ordem, e toca do começo', () {
      final s = renderSetupCalls([-1, 3, -5, 0], 2.5);
      expectSameCalls(s.calls, [
        ['loop_set', 0, 0, 0],
        ['metronome', 0, 0],
        ['watch_fx', -1, -1],
        ['watch_analyzer', -2],
        ['capture_clear'],
        ['capture_add', -1],
        ['capture_add', 3],
        ['capture_add', 0],
        ['seek', 2.5],
        ['play'],
      ]);
      expect(s.indices, [0, 1, -1, 2], reason: 'saída inválida fica sem captura e não desloca as outras');
    });

    test('pedido inválido explica o problema', () {
      expect(checkRenderJob(0, 4, 1, 48000, const [-1]), isNull);
      expect(checkRenderJob(0, 4, 1, 4000, const [-1]), contains('Taxa'));
      expect(checkRenderJob(-1, 4, 1, 48000, const [-1]), contains('Trecho'));
      expect(checkRenderJob(0, double.nan, 1, 48000, const [-1]), contains('Trecho'));
      expect(checkRenderJob(0, 4, 1, 48000, const []), contains('Nenhuma saída'));
      expect(checkRenderJob(0, 4, -1, 48000, const [-1]), contains('Cauda'));
    });

    final node = _hasNode();
    test('igual ao render-worker.js da web (andamento, quadros e chamadas aparadas)', () async {
      final rnd = math.Random(7);
      final cases = <Map<String, Object>>[];
      for (var k = 0; k < 40; k++) {
        final bpm = 40 + rnd.nextInt(200) + rnd.nextDouble();
        final to = (1 + rnd.nextInt(32)) + (rnd.nextBool() ? rnd.nextDouble() : 0.0);
        final calls = <List<Object>>[
          ['tempo', bpm, 4],
          ['play'],
          ['watch_analyzer', -1],
        ];
        for (var i = 0; i < 12; i++) {
          final start = rnd.nextInt(40) / 2 + (rnd.nextBool() ? 0 : rnd.nextDouble());
          calls.add([
            'clip_add',
            rnd.nextInt(4),
            1 + rnd.nextInt(3),
            start,
            rnd.nextDouble(),
            rnd.nextDouble() * 12,
            1,
            rnd.nextDouble() * 0.2,
            rnd.nextDouble() * 3,
          ]);
          calls.add(['note_add', rnd.nextInt(4), start, rnd.nextDouble() * 6, 36 + rnd.nextInt(48), rnd.nextDouble()]);
        }
        // uma nota e um clipe começando exatamente no fim
        calls.add(['note_add', 0, to, 1, 60, 1]);
        calls.add(['clip_add', 0, 1, to, 0, 1, 1, 0, 0]);
        cases.add({'calls': calls, 'from': rnd.nextInt(3).toDouble(), 'to': to, 'tail': rnd.nextDouble() * 4, 'rate': 44100.0 + rnd.nextInt(3) * 3900});
      }
      final dir = await Directory.systemTemp.createTemp('jopendaw_render');
      addTearDown(() => dir.delete(recursive: true));
      final input = File('${dir.path}/cases.json')..writeAsStringSync(jsonEncode({'cases': cases}));
      final script = File('${dir.path}/run.js')
        ..writeAsStringSync('''
const rw = require(process.argv[2]);
const input = JSON.parse(require('fs').readFileSync(process.argv[3], 'utf8'));
process.stdout.write(JSON.stringify(input.cases.map((c) => {
  const bpm = rw.tempoOf(c.calls);
  return { bpm, frames: rw.frameCounts(c.from, c.to, c.tail, bpm, c.rate), calls: rw.prepareCalls(c.calls, c.to, bpm) };
})));
''');
      final r = await Process.run('node', [script.path, File('web/engine/render-worker.js').absolute.path, input.path]);
      expect(r.exitCode, 0, reason: '${r.stderr}');
      final expected = jsonDecode(r.stdout as String) as List;
      for (var k = 0; k < cases.length; k++) {
        final c = cases[k];
        final calls = c['calls'] as List<List<Object>>;
        final e = expected[k] as Map;
        final bpm = renderTempo(calls);
        expect(bpm, (e['bpm'] as num).toDouble(), reason: 'caso $k');
        final f = renderFrames(c['from'] as double, c['to'] as double, c['tail'] as double, bpm, c['rate'] as double);
        final ef = e['frames'] as Map;
        expect([f.range, f.tail, f.total], [ef['range'], ef['tail'], ef['total']], reason: 'caso $k');
        expectSameCalls(prepareRenderCalls(calls, c['to'] as double, bpm), e['calls'], reason: 'caso $k');
      }
    }, skip: node ? false : 'sem node para rodar o render-worker.js');
  });

  group('leituras do motor', () {
    (Float32List, Float64List) memory(int max) {
      final f64 = Float64List(max);
      return (Float32List.view(f64.buffer), f64);
    }

    test('estado em f32: batida, tocando, indicador e os picos', () {
      final (f32, f64) = memory(16);
      f32.setAll(0, [12.25, 1, -4.5, 4, 0.5, 0.25, 1, 0.75]);
      final s = parseEngineState(f32, f64, 8)!;
      expect(s.beat, 12.25);
      expect(s.playing, isTrue);
      expect(s.fxMeter, -4.5);
      expect(s.peaks, [0.5, 0.25, 1, 0.75]);
      expect(s.spectrum, isNull);
      final spectrum = Float32List.fromList([-60, -50]);
      expect(parseEngineState(f32, f64, 8, spectrum: spectrum)!.spectrum, same(spectrum));
    });

    test('estado escrito em f64 também é entendido (a batida longe do zero não perde precisão)', () {
      final (f32, f64) = memory(16);
      f64.setAll(0, [1234.000123, 1, -2, 2, 0.5, 0.125]);
      final s = parseEngineState(f32, f64, 6)!;
      expect(s.beat, 1234.000123);
      expect(s.playing, isTrue);
      expect(s.fxMeter, -2);
      expect(s.peaks, [0.5, 0.125]);
      // parado no zero, as duas leituras dão o mesmo
      f64.setAll(0, [0, 0, 0, 0]);
      final z = parseEngineState(f32, f64, 4)!;
      expect((z.beat, z.playing, z.peaks.length), (0, false, 0));
    });

    test('estado sem sentido (pouco, contagem maior que o escrito, tocando fora de 0/1) é ignorado', () {
      // cada caso numa memória nova, com valores que não fazem sentido nem lidos como f64
      EngineState? parse(List<double> values, int n) {
        final (f32, f64) = memory(16);
        f32.setAll(0, values);
        return parseEngineState(f32, f64, n);
      }

      expect(parse(const [1, 1, 0], 3), isNull);
      expect(parse(const [1, 1, 0.25, 9, 0.5], 5), isNull, reason: 'mais picos que o escrito');
      expect(parse(const [1, 0.5, 0.25, 0], 4), isNull, reason: 'tocando 0,5');
      expect(parse(const [1, 1, 0.25, 1.5, 0.5], 5), isNull, reason: 'contagem quebrada');
      final s = parse([double.nan, 1, double.infinity, 1, double.nan], 5)!;
      expect((s.beat, s.fxMeter, s.peaks.single), (0, 0, 0), reason: 'não finito vira zero');
    });

    test('notas gravadas: grupos de 5, com os mesmos cuidados da web', () {
      final notes = parseRecordedNotes(
        Float32List.fromList([
          1, 60, 4, 5.5, 0.8, //
          0, 200, 2, 1, double.nan, // altura no limite, fim antes do início, velocidade inválida
          0, double.nan, 1, 2, 1, // altura inválida: sai
          2, 61, 3, 4, 1.5,
          9, 9, // pedaço de grupo: sai
        ]),
      );
      expect(notes.length, 3);
      expect((notes[0].track, notes[0].pitch, notes[0].start, notes[0].end), (1, 60, 4.0, 5.5));
      expect(notes[0].velocity, closeTo(0.8, 1e-6));
      expect(notes[1], (track: 0, pitch: 127, start: 2.0, end: 2.0, velocity: 0.8));
      expect(notes[2].velocity, 1);
    });

    test('entradas de áudio: objetos ou pares, sem a padrão (id negativo), sem repetidas, com nome', () {
      expect(parseInputDevices('[{"id":-1,"name":"Padrão"},{"id":3,"name":" Microfone "},{"id":7},{"id":3,"name":"De novo"}]'), [
        ('3', 'Microfone'),
        ('7', 'Entrada 7'),
      ]);
      expect(parseInputDevices('[[12,"USB"],[2.0,"Bluetooth"],["5","Fone"],["-1","Padrão"],[null,"x"]]'), [('12', 'USB'), ('2', 'Bluetooth'), ('5', 'Fone')]);
      expect(parseInputDevices('não é json'), isEmpty);
      expect(parseInputDevices('{"id":1}'), isEmpty);
    });
  });
}

bool _hasNode() {
  try {
    return Process.runSync('node', ['--version']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}
