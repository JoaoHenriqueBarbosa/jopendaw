/// Motor e guardado local de mentira para os testes de gravação, exportação e congelamento: o
/// controlador fala com eles como falaria com o worklet, e o teste lê o que foi pedido e manda os
/// blocos da entrada, as notas e o resultado do render.
library;

import 'dart:async';

import 'package:crypto/crypto.dart';

import 'dart:typed_data';

import 'package:jopendaw_app/api/sync_api.dart';
import 'package:jopendaw_app/audio/engine.dart';
import 'package:jopendaw_app/daw/controller.dart';
import 'package:jopendaw_app/daw/model.dart';
import 'package:jopendaw_app/daw/wav.dart';
import 'package:jopendaw_app/models/project.dart';

typedef RenderCall = ({
  List<List<Object>> calls,
  Map<int, DecodedAudio> samples,
  double fromBeat,
  double toBeat,
  double tailSeconds,
  List<int> outputs,
  double rate,
});

class FakeEngine implements AudioEngine {
  @override
  Future<String> sha256Hex(Uint8List bytes) async => sha256.convert(bytes).toString();

  @override
  bool get supported => true;

  @override
  Future<double> start() async => 100;

  @override
  Future<void> resume() async {}

  @override
  Future<DecodedAudio> decode(Uint8List bytes) async {
    final w = decodeWav(bytes);
    return DecodedAudio(w.channels, w.sampleRate.toDouble());
  }

  /// Áudios que chegaram ao motor, pelo id.
  final loaded = <int, DecodedAudio>{};

  @override
  void loadSample(int id, DecodedAudio audio) => loaded[id] = audio;

  @override
  List<List<Object>>? log = [];

  @override
  void calls(List<List<Object>> list) => log?.addAll(list);

  List<List<Object>> sent(String name) => [
    for (final c in log!)
      if (c.first == name) c,
  ];

  @override
  void Function(EngineState state)? onState;

  @override
  void Function(LoudnessReading reading)? onLoudness;

  @override
  double latency = 0;

  @override
  void Function(int status, int data1, int data2)? onMidi;

  @override
  void Function(List<String> inputs)? onMidiInputs;

  @override
  Future<List<String>> enableMidi() async => const [];

  // entrada

  /// O que o próximo startInput lança (permissão negada, entrada que não existe).
  Object? Function(String? device)? inputFailure;
  double inputLatency = 0;
  final opened = <String?>[];
  int stopped = 0;

  @override
  Future<double> startInput(String? deviceId) async {
    opened.add(deviceId);
    final f = inputFailure?.call(deviceId);
    if (f != null) throw f;
    return inputLatency;
  }

  @override
  Future<void> stopInput() async => stopped++;

  List<(String, String)> devices = const [];

  @override
  Future<List<(String, String)>> inputDevices() async => devices;

  /// Liga/desliga da captura, na ordem; desligar devolve [notes] (grupos de 5: faixa, altura,
  /// início, fim, velocidade, como o motor registra) em [onCaptureEnd], como a ponte devolveria.
  final captures = <bool>[];
  Float32List notes = Float32List(0);

  @override
  void setCapture(bool on) {
    captures.add(on);
    if (!on) {
      onCaptureEnd?.call([
        for (var i = 0; i + 4 < notes.length; i += 5)
          (
            track: notes[i].round(),
            pitch: notes[i + 1].round(),
            start: notes[i + 2].toDouble(),
            end: notes[i + 3].toDouble(),
            velocity: notes[i + 4].toDouble(),
          ),
      ]);
    }
  }

  @override
  void Function(Float32List left, Float32List right)? onRecord;

  @override
  void Function(double peak)? onInputLevel;

  @override
  double recordBeat = 0;

  @override
  void Function(List<RecordedNote> notes)? onCaptureEnd;

  @override
  void Function(String message)? onInputLost;

  /// Cancelamentos pedidos ao render.
  int cancels = 0;

  @override
  void cancelRender() => cancels++;

  /// Manda [frames] quadros pela entrada em blocos de [block], com o valor de cada quadro dado
  /// por [left] e [right] (o índice é contado do começo da captura).
  void feed(int from, int frames, double Function(int i) left, [double Function(int i)? right, int block = 64]) {
    for (var k = 0; k < frames; k += block) {
      final n = (frames - k) < block ? frames - k : block;
      final l = Float32List(n), r = Float32List(n);
      for (var j = 0; j < n; j++) {
        l[j] = left(from + k + j);
        r[j] = (right ?? left)(from + k + j);
      }
      onRecord!(l, r);
    }
  }

  // render

  final renders = <RenderCall>[];

  /// Canais de cada saída pedida (o teste decide o que o render "soou").
  List<List<Float32List>> Function(List<int> outputs) renderResult = (outputs) => [for (final _ in outputs) const []];

  @override
  Future<List<List<Float32List>>> renderOffline({
    required List<List<Object>> calls,
    required Map<int, DecodedAudio> samples,
    required double fromBeat,
    required double toBeat,
    required double tailSeconds,
    required List<int> outputs,
    required double rate,
    void Function(double progress)? onProgress,
  }) async {
    renders.add((calls: calls, samples: samples, fromBeat: fromBeat, toBeat: toBeat, tailSeconds: tailSeconds, outputs: outputs, rate: rate));
    onProgress?.call(0.5);
    return renderResult(outputs);
  }

  /// Os pedidos de warp que chegaram (áudio de origem, razão e semitons), em ordem.
  final stretches = <({DecodedAudio audio, double ratio, double semitones})>[];

  /// Impede o warp de terminar até o teste completar (null: termina na hora).
  Completer<void>? stretchGate;

  /// O que o `detectBpm` devolve e as vezes que foi chamado.
  ({double bpm, double confidence}) tempo = (bpm: 120, confidence: 0.9);
  int detects = 0;

  /// O derivado de mentira: a duração muda pela razão e cada amostra vira `origem + semitons`,
  /// então o teste reconhece o que foi processado.
  @override
  Future<DecodedAudio> stretch(DecodedAudio a, {required double ratio, double semitones = 0, void Function(double progress)? onProgress}) async {
    stretches.add((audio: a, ratio: ratio, semitones: semitones));
    await stretchGate?.future;
    final n = (a.frames * ratio).round();
    return DecodedAudio([
      for (final c in a.channels) Float32List.fromList([for (var i = 0; i < n; i++) c[(i / ratio).floor().clamp(0, c.length - 1)] + semitones * 0.001]),
    ], a.rate);
  }

  @override
  Future<({double bpm, double confidence})> detectBpm(DecodedAudio a) async {
    detects++;
    return tempo;
  }

  final saved = <(String, Uint8List, String)>[];

  @override
  Future<void> saveFile(String name, Uint8List bytes, String mime) async => saved.add((name, bytes, mime));

  // o que ainda vier a entrar na ponte e estes testes não usam
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MemoryStore implements LocalStore {
  final data = <String, Object>{};

  @override
  Future<Object?> get(String key) async => data[key];

  @override
  Future<void> put(String key, Object value) async => data[key] = value;

  @override
  Future<void> delete(String key) async => data.remove(key);
}

/// Controlador pronto, sem abrir o motor, a 120 bpm em 4/4 e com o motor a 100 Hz: uma batida são
/// 50 quadros, um compasso 200 (segundos de áudio em poucas centenas de amostras).
DawController fakeController(
  FakeEngine engine, {
  MemoryStore? store,
  List<DawTrack>? tracks,
  SyncApi? api,
  bool Function()? canSync,
  double syncTimeScale = 1,
}) {
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
    engine: engine,
    store: store ?? MemoryStore(),
    api: api,
    canSync: canSync,
    syncTimeScale: syncTimeScale,
  );
  c.doc = DawDoc(
    bpm: 120,
    beatsPerBar: 4,
    tracks: tracks ?? [DawTrack(id: 'a', name: 'Áudio 1', color: 0)],
  );
  c.engineRate = 100;
  c.ready = true;
  return c;
}

/// Dá a vez às tarefas pendentes (a entrada abre de forma assíncrona).
Future<void> settle() => Future<void>.delayed(Duration.zero);
