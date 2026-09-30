/// O motor de áudio nativo (`engine/android`, `libjopendaw_engine.so`) visto pelo dart:ffi.
///
/// É o mesmo motor em Rust que a web roda em WASM no AudioWorklet. Aqui a thread de áudio do
/// Oboe/AAudio é a dona dele: as funções `jd_*` só enfileiram comandos (sem trava) ou leem o que
/// ela publicou, então são chamadas direto da thread da interface. O estado (posição, picos,
/// indicador do efeito, espectro) vem por polling a ~60 Hz, como o worklet mandaria; o que é pesado
/// (decodificar, renderizar, sha-256 de arquivo grande) roda num isolate para a tela não travar.
///
/// Contrato binário assumido (C ABI). Inteiros vão como `intptr_t`, que serve para `u32`, `i32` e
/// `usize` do lado do Rust (o chamado só olha os bits do tipo dele); handles são do tamanho de
/// ponteiro (0 = falhou); áudio é f32; taxas, batidas e latências são f64:
///
///     f64    jd_start()                                   taxa da saída (≤ 0: não abriu)
///     void   jd_stop()
///     i32    jd_calls(u8* json, usize len)                0 ok, < 0 erro
///     void   jd_sample_load(id, f32* l, f32* r, usize frames, f64 rate)   r nulo = mono; copia
///     void   jd_sample_drop(id)
///     usize  jd_state(f32* out, usize max)                [batida, tocando, fxMeter, n, picos...]; em f64 também serve
///     usize  jd_spectrum(f32* out, usize n)               faixas em dB; 0 sem nada observado
///     handle jd_decode(u8* bytes, usize len)
///     void   jd_decoded_info(handle, *frames, *channels, f64* rate)   inteiros de até 64 bits
///     void   jd_decoded_copy(handle, usize channel, f32* out)          `frames` floats
///     void   jd_decoded_free(handle)
///     handle jd_stretch(f32* l, f32* r, usize frames, f64 rate, f64 ratio, f64 semitones)   como jd_decode
///     i32    jd_detect_bpm(f32* l, f32* r, usize frames, f64 rate, f64* bpm, f64* confidence)
///     f64    jd_input_start(i32 device)                   latência de entrada (s); < 0 erro; −1 = padrão
///     void   jd_input_stop()
///     usize  jd_input_devices(u8* out, usize max)         tamanho do JSON (maior que max: não coube)
///     void   jd_capture(on)
///     usize  jd_recorded(f32* l, f32* r, usize max, f64* out_beat)     quadros; batida do primeiro
///     f32    jd_input_level()                             pico desde a leitura; < 0: a entrada caiu
///     usize  jd_rec_notes(f32* out, usize max)            grupos de 5 floats, como o rec_notes do wasm
///     handle jd_offline_new(f64 rate)
///     void   jd_offline_calls(handle, u8* json, usize len)
///     void   jd_offline_sample(handle, id, f32* l, f32* r, usize frames, f64 rate)
///     void   jd_offline_process(handle, usize frames)     até 4096 quadros
///     void   jd_offline_captured(handle, i32 index, f32* l, f32* r, usize n)
///     void   jd_offline_free(handle)
///     f64    jd_latency()                                 latência de saída (s)
///
/// O render usa as capturas do motor para toda saída, inclusive o master (`capture_add(-1)`, que é
/// exatamente o que o `process` devolve), então não depende de onde o `jd_offline_process` deixa a
/// saída dele. Os `jd_*` que faltarem na biblioteca só derrubam o recurso que os usa: os símbolos
/// são procurados no primeiro uso (os que toda tela usa, já no [FfiEngine.start]). Toda leitura
/// nativa tem espaço para `max` doubles, para uma biblioteca que escreva f64 não passar do fim.
///
/// O `test/native/fake_engine.c` implementa este mesmo contrato para os testes no computador.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener, AppLifecycleState;
import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

import 'engine_types.dart';

/// A biblioteca que o `engine/build-android.sh` põe em `jniLibs` (o Android acha pelo nome).
const nativeLibraryName = 'libjopendaw_engine.so';

/// Nota tocada ao vivo durante uma captura (faixa, altura MIDI, início e fim em batidas,
/// velocidade 0..1); igual à do engine_web.dart.
typedef RecordedNote = ({int track, int pitch, double start, double end, double velocity});

/// O render foi cancelado por `AudioEngine.cancelRender` (não é falha: não pede aviso); igual à do
/// engine_web.dart.
class RenderCanceled implements Exception {
  const RenderCanceled();

  @override
  String toString() => 'A renderização foi cancelada.';
}

/// O que o motor entrega ao `AudioEngine` (os callbacks que o controlador põe nele).
abstract interface class EngineEvents {
  void Function(EngineState state)? get onState;
  void Function(int status, int data1, int data2)? get onMidi;
  void Function(List<String> inputs)? get onMidiInputs;
  void Function(Float32List left, Float32List right)? get onRecord;
  void Function(double peak)? get onInputLevel;
  void Function(List<RecordedNote> notes)? get onCaptureEnd;
  void Function(String message)? get onInputLost;

  /// Batida do primeiro quadro do bloco que [onRecord] está entregando.
  double get recordBeat;
  set recordBeat(double beat);
}

// ------------------------------------------------------------------ biblioteca

/// As funções `jd_*` da biblioteca, procuradas no primeiro uso.
final class EngineLib {
  EngineLib(this._lib);

  /// Abre a biblioteca: no Android, pelo nome (o sistema acha em `jniLibs`); nos testes, pelo
  /// caminho de uma de mentira.
  factory EngineLib.open(String path) => EngineLib(DynamicLibrary.open(path));

  final DynamicLibrary _lib;

  late final start = _lib.lookupFunction<Double Function(), double Function()>('jd_start');
  late final stop = _lib.lookupFunction<Void Function(), void Function()>('jd_stop');
  late final calls = _lib.lookupFunction<Int32 Function(Pointer<Uint8>, IntPtr), int Function(Pointer<Uint8>, int)>('jd_calls');
  late final sampleLoad = _lib
      .lookupFunction<Void Function(IntPtr, Pointer<Float>, Pointer<Float>, IntPtr, Double), void Function(int, Pointer<Float>, Pointer<Float>, int, double)>(
        'jd_sample_load',
      );
  late final sampleDrop = _lib.lookupFunction<Void Function(IntPtr), void Function(int)>('jd_sample_drop');
  late final state = _lib.lookupFunction<IntPtr Function(Pointer<Float>, IntPtr), int Function(Pointer<Float>, int)>('jd_state');
  late final spectrum = _lib.lookupFunction<IntPtr Function(Pointer<Float>, IntPtr), int Function(Pointer<Float>, int)>('jd_spectrum');
  late final decode = _lib.lookupFunction<IntPtr Function(Pointer<Uint8>, IntPtr), int Function(Pointer<Uint8>, int)>('jd_decode');
  late final decodedInfo = _lib
      .lookupFunction<
        Void Function(IntPtr, Pointer<Uint64>, Pointer<Uint64>, Pointer<Double>),
        void Function(int, Pointer<Uint64>, Pointer<Uint64>, Pointer<Double>)
      >('jd_decoded_info');
  late final decodedCopy = _lib.lookupFunction<Void Function(IntPtr, IntPtr, Pointer<Float>), void Function(int, int, Pointer<Float>)>('jd_decoded_copy');
  late final decodedFree = _lib.lookupFunction<Void Function(IntPtr), void Function(int)>('jd_decoded_free');
  late final stretch = _lib
      .lookupFunction<
        IntPtr Function(Pointer<Float>, Pointer<Float>, IntPtr, Double, Double, Double),
        int Function(Pointer<Float>, Pointer<Float>, int, double, double, double)
      >('jd_stretch');
  late final detectBpm = _lib
      .lookupFunction<
        Int32 Function(Pointer<Float>, Pointer<Float>, IntPtr, Double, Pointer<Double>, Pointer<Double>),
        int Function(Pointer<Float>, Pointer<Float>, int, double, Pointer<Double>, Pointer<Double>)
      >('jd_detect_bpm');
  late final inputStart = _lib.lookupFunction<Double Function(IntPtr), double Function(int)>('jd_input_start');
  late final inputStop = _lib.lookupFunction<Void Function(), void Function()>('jd_input_stop');
  late final inputDevices = _lib.lookupFunction<IntPtr Function(Pointer<Uint8>, IntPtr), int Function(Pointer<Uint8>, int)>('jd_input_devices');
  late final capture = _lib.lookupFunction<Void Function(IntPtr), void Function(int)>('jd_capture');
  late final recorded = _lib
      .lookupFunction<
        IntPtr Function(Pointer<Float>, Pointer<Float>, IntPtr, Pointer<Double>),
        int Function(Pointer<Float>, Pointer<Float>, int, Pointer<Double>)
      >('jd_recorded');
  late final inputLevel = _lib.lookupFunction<Float Function(), double Function()>('jd_input_level');
  late final recNotes = _lib.lookupFunction<IntPtr Function(Pointer<Float>, IntPtr), int Function(Pointer<Float>, int)>('jd_rec_notes');
  late final offlineNew = _lib.lookupFunction<IntPtr Function(Double), int Function(double)>('jd_offline_new');
  late final offlineCalls = _lib.lookupFunction<Void Function(IntPtr, Pointer<Uint8>, IntPtr), void Function(int, Pointer<Uint8>, int)>('jd_offline_calls');
  late final offlineSample = _lib
      .lookupFunction<
        Void Function(IntPtr, IntPtr, Pointer<Float>, Pointer<Float>, IntPtr, Double),
        void Function(int, int, Pointer<Float>, Pointer<Float>, int, double)
      >('jd_offline_sample');
  late final offlineProcess = _lib.lookupFunction<Void Function(IntPtr, IntPtr), void Function(int, int)>('jd_offline_process');
  late final offlineCaptured = _lib
      .lookupFunction<Void Function(IntPtr, IntPtr, Pointer<Float>, Pointer<Float>, IntPtr), void Function(int, int, Pointer<Float>, Pointer<Float>, int)>(
        'jd_offline_captured',
      );
  late final offlineFree = _lib.lookupFunction<Void Function(IntPtr), void Function(int)>('jd_offline_free');
  late final latency = _lib.lookupFunction<Double Function(), double Function()>('jd_latency');
  late final loudness = _lib.lookupFunction<Double Function(Int32), double Function(int)>('jd_loudness');
}

/// Copia [bytes] para memória nativa, chama [fn] com o ponteiro e o tamanho, e solta.
T _withNativeBytes<T>(Uint8List bytes, T Function(Pointer<Uint8> data, int length) fn) {
  final p = malloc<Uint8>(math.max(1, bytes.length));
  try {
    p.asTypedList(bytes.length).setAll(0, bytes);
    return fn(p, bytes.length);
  } finally {
    malloc.free(p);
  }
}

/// Copia um canal para memória nativa ([frames] quadros), chama [fn] e solta. Sem canal: ponteiro
/// nulo (o lado mono do `sample_load`).
T _withNativeFloats<T>(Float32List? data, int frames, T Function(Pointer<Float> p) fn) {
  if (data == null) return fn(nullptr);
  final p = malloc<Float>(math.max(1, frames));
  try {
    p.asTypedList(frames).setRange(0, frames, data);
    return fn(p);
  } finally {
    malloc.free(p);
  }
}

// ------------------------------------------------------------------ o que passa pela fronteira

/// As chamadas do motor em JSON UTF-8 (`[[nome, arg...], ...]`), como o worklet recebe: booleanos
/// viram 0/1, inteiros e doubles vão como números. Uma chamada com número não finito fica de fora
/// inteira ([skipped] conta quantas): o JSON não tem NaN nem infinito, e o worklet repassaria um
/// valor que o motor não tem como usar.
({Uint8List json, int skipped}) encodeCalls(List<List<Object>> calls) {
  final b = StringBuffer('[');
  var first = true;
  var skipped = 0;
  for (final c in calls) {
    final name = c.isEmpty ? null : c.first;
    if (name is! String) throw ArgumentError('chamada do motor sem nome: $c');
    var finite = true;
    for (var i = 1; i < c.length; i++) {
      final a = c[i];
      if (a is double && !a.isFinite) finite = false;
      if (a is! num && a is! bool) throw ArgumentError('argumento do motor: $a');
    }
    if (!finite) {
      skipped++;
      continue;
    }
    if (!first) b.write(',');
    first = false;
    b
      ..write('[')
      ..write(jsonEncode(name));
    for (var i = 1; i < c.length; i++) {
      final a = c[i];
      b
        ..write(',')
        ..write(a is bool ? (a ? '1' : '0') : a.toString());
    }
    b.write(']');
  }
  b.write(']');
  return (json: utf8.encode(b.toString()), skipped: skipped);
}

/// O estado que `jd_state` escreveu ([n] valores): batida, tocando (0/1), indicador do efeito,
/// quantos picos e os picos. Lido como f32 (o contrato) e, se não fizer sentido assim, como f64
/// (uma biblioteca que escreva tudo em f64 para não perder precisão na batida): as duas vistas são
/// da mesma memória, reservada com espaço para `max` doubles. Nenhuma das duas válida: null.
EngineState? parseEngineState(Float32List asF32, Float64List asF64, int n, {Float32List? spectrum}) =>
    _stateFrom(asF32, n, spectrum) ?? _stateFrom(asF64, n, spectrum);

EngineState? _stateFrom(List<double> v, int n, Float32List? spectrum) {
  if (n < 4 || n > v.length) return null;
  final playing = v[1];
  final count = v[3];
  if (playing != 0 && playing != 1) return null;
  if (!count.isFinite || count < 0 || count != count.roundToDouble() || count > n - 4) return null;
  final peaks = Float32List(count.toInt());
  for (var i = 0; i < peaks.length; i++) {
    final p = v[4 + i];
    peaks[i] = p.isFinite ? p : 0;
  }
  final beat = v[0];
  final meter = v[2];
  return EngineState(beat.isFinite ? beat : 0, playing == 1, peaks, fxMeter: meter.isFinite ? meter : 0, spectrum: spectrum);
}

/// Notas do registro do motor: grupos de 5 floats (faixa, altura, início, fim, velocidade), com os
/// mesmos cuidados do engine_web.dart (grupo com número inválido sai; fim antes do início vira o
/// início; velocidade inválida vira 0,8).
List<RecordedNote> parseRecordedNotes(Float32List flat) {
  final notes = <RecordedNote>[];
  for (var i = 0; i + 5 <= flat.length; i += 5) {
    final start = flat[i + 2];
    final end = flat[i + 3];
    if (!start.isFinite || !end.isFinite || !flat[i].isFinite || !flat[i + 1].isFinite) continue;
    final velocity = flat[i + 4];
    // altura 256 + controle é um evento de controle (1 modulação, 64 pedal, 128 pitch bend), com o
    // valor no lugar da velocidade (bend de −1 a 1)
    final code = flat[i + 1].round();
    final isCc = code >= ccPitchBase;
    notes.add((
      track: flat[i].round(),
      pitch: isCc ? code : code.clamp(0, 127),
      start: start,
      end: end < start ? start : end,
      velocity: isCc ? (velocity.isFinite ? velocity.clamp(-1, 1).toDouble() : 0.0) : (velocity.isFinite ? velocity.clamp(0, 1).toDouble() : 0.8),
    ));
  }
  return notes;
}

/// Entradas de áudio (id, nome) do JSON de `jd_input_devices`: lista de objetos `{id, name}` ou de
/// pares `[id, nome]`. Id negativo é a pseudo-entrada padrão (a padrão é o id null do app) e sai;
/// id repetido vale uma vez; sem nome, "Entrada" e o id.
List<(String, String)> parseInputDevices(String json) {
  final Object? v;
  try {
    v = jsonDecode(json);
  } on FormatException {
    return const [];
  }
  if (v is! List) return const [];
  final out = <(String, String)>[];
  final seen = <String>{};
  for (final d in v) {
    Object? id, name;
    if (d is Map) {
      id = d['id'];
      name = d['name'] ?? d['label'];
    } else if (d is List && d.isNotEmpty) {
      id = d[0];
      name = d.length > 1 ? d[1] : null;
    }
    final String key;
    if (id is num) {
      if (!id.isFinite || id < 0) continue;
      key = id == id.roundToDouble() ? id.round().toString() : id.toString();
    } else if (id is String && id.trim().isNotEmpty) {
      key = id.trim();
      final asNumber = int.tryParse(key);
      if (asNumber != null && asNumber < 0) continue;
    } else {
      continue;
    }
    if (!seen.add(key)) continue;
    final label = name is String && name.trim().isNotEmpty ? name.trim() : 'Entrada $key';
    out.add((key, label));
  }
  return out;
}

// ------------------------------------------------------------------ render fora de tempo real

/// Quadros por `jd_offline_process`: o motor fatia numa grade fixa de 128 contada do começo do
/// render, então o bloco maior só economiza chamadas; bem abaixo do máximo com capturas (4096).
const renderBlock = 1024;

/// Capturas por motor (`record::MAX_CAPTURES`): com mais saídas, o render roda em passadas.
const maxCaptures = 64;

/// Teto da memória das saídas de um render no aparelho (todas as pedidas, os dois canais): 1,5 GiB
/// são ~68 min de estéreo a 48 kHz. O controlador já divide as saídas em lotes de 384 MB; o teto
/// segura um pedido absurdo antes de o sistema matar o app.
const maxRenderBytes = 1536 * 1024 * 1024;

/// Fade de um clipe cortado no fim do trecho (o do motor ao parar), igual ao render-worker.js.
const _cutFadeSecs = 0.01;

/// Folga para o que começa "exatamente" no fim do trecho (erro de ponto flutuante).
const _edgeEps = 1e-9;

/// Chamadas que não entram no render (as mesmas do render-worker.js): transporte e observação são
/// dele, notas ao vivo e entrada não existem ali, memória e amostras chegam por outro caminho.
const renderSkip = {
  'init',
  'alloc',
  'dealloc',
  'process',
  'sample_load',
  'sample_drop',
  'play',
  'stop',
  'seek',
  'panic',
  'live_on',
  'live_off',
  'live_bend',
  'live_cc',
  'watch_fx',
  'watch_analyzer',
  'set_input',
  'input_monitor',
  'rec_notes_start',
  'rec_notes_stop',
  'rec_notes',
  'capture_clear',
  'capture_add',
  'captured',
  'peaks',
  'analyzer',
  'beat',
  'playing',
  'fx_meter',
  'loudness',
  'loudness_reset',
};

double? _num(List<Object> c, int i) {
  if (i >= c.length) return null;
  final v = c[i];
  return v is num ? v.toDouble() : null;
}

/// O andamento que vale no fim das chamadas (a última ganha), com o limite do motor (20..999).
double renderTempo(List<List<Object>> calls) {
  var bpm = 120.0;
  for (final c in calls) {
    if (c.isEmpty || c.first != 'tempo') continue;
    final v = _num(c, 1);
    if (v != null && v.isFinite) bpm = v;
  }
  return bpm.clamp(20.0, 999.0);
}

/// Quadros do trecho (medido no andamento [bpm]) e da cauda (em segundos), como no render-worker.js.
({int range, int tail, int total}) renderFrames(double fromBeat, double toBeat, double tailSeconds, double bpm, double rate) {
  final perBeat = 60 / bpm * rate;
  final range = math.max(0, ((toBeat - fromBeat) * perBeat).round());
  final tail = math.max(0, ((tailSeconds.isFinite ? tailSeconds : 0) * rate).round());
  return (range: range, tail: tail, total: range + tail);
}

/// As chamadas do documento como o render aplica: sem as de [renderSkip] e com o que passa do fim
/// aparado. O transporte segue na cauda (a automação continua valendo), mas nada começa depois do
/// fim: clipes e notas que começam ali saem, e os que atravessam terminam no fim (clipe com um fade
/// curto, nota com a soltura do instrumento). A mesma regra do render-worker.js.
List<List<Object>> prepareRenderCalls(List<List<Object>> calls, double toBeat, double bpm) {
  final secsPerBeat = 60 / bpm;
  final out = <List<Object>>[];
  for (final c in calls) {
    final name = c.isEmpty ? null : c.first;
    if (name is! String || renderSkip.contains(name)) continue;
    if (name == 'clip_add' && c.length >= 9) {
      // clip_add(faixa, amostra, início em batidas, offset s, duração s, ganho, fade in s, fade out s)
      final start = _num(c, 3), length = _num(c, 5), fadeOut = _num(c, 8);
      if (start == null || length == null || fadeOut == null) {
        out.add(c);
        continue;
      }
      if (start >= toBeat - _edgeEps) continue;
      final end = start + length / secsPerBeat;
      if (end <= toBeat) {
        out.add(c);
        continue;
      }
      final cut = (toBeat - start) * secsPerBeat;
      // o fade de saída começa onde começava (se o corte cai dentro dele, só fica mais íngreme)
      final removed = length - cut;
      var fade = fadeOut > removed ? fadeOut - removed : 0.0;
      fade = math.min(cut, math.max(fade, _cutFadeSecs));
      out.add(['clip_add', c[1], c[2], c[3], c[4], cut, c[6], c[7], fade]);
    } else if (name == 'note_add' && c.length >= 6) {
      // note_add(faixa, início em batidas, duração em batidas, altura, velocidade)
      final start = _num(c, 2), length = _num(c, 3);
      if (start == null || length == null) {
        out.add(c);
        continue;
      }
      if (start >= toBeat - _edgeEps) continue;
      out.add(start + length > toBeat ? ['note_add', c[1], c[2], toBeat - start, c[4], c[5]] : c);
    } else if (name == 'cc_add' && c.length >= 5) {
      // cc_add(faixa, controle, batida, valor): depois do fim só fica o pedal que sobe, no próprio
      // fim (senão as notas cortadas ali seguiriam presas por um pedal que o trecho não solta)
      final beat = _num(c, 3), value = _num(c, 4);
      if (beat == null || value == null || beat < toBeat - _edgeEps) {
        out.add(c);
      } else if (c[2] == 64 && value < 0.5) {
        out.add(['cc_add', c[1], c[2], toBeat, c[4]]);
      }
    } else {
      out.add(c);
    }
  }
  return out;
}

/// O problema do pedido de render, para o usuário (null = pode renderizar).
String? checkRenderJob(double fromBeat, double toBeat, double tailSeconds, double rate, List<int> outputs) {
  if (!rate.isFinite || rate < 8000 || rate > 384000) return 'Taxa de amostragem inválida para o render: $rate.';
  if (!fromBeat.isFinite || !toBeat.isFinite || fromBeat < 0) return 'Trecho inválido para o render.';
  if (outputs.isEmpty) return 'Nenhuma saída pedida para o render.';
  if (!tailSeconds.isFinite || tailSeconds < 0) return 'Cauda inválida para o render.';
  return null;
}

/// As chamadas que preparam uma passada do render depois das do documento: sem loop, sem metrônomo,
/// sem observação, uma captura por saída de [outputs] (−1 = master) e o transporte andando de
/// [fromBeat]. [indices] é o índice da captura de cada saída (as capturas são numeradas na ordem,
/// do zero, depois do `capture_clear`); saída inválida (menor que −1) fica sem captura (−1) e sai
/// em silêncio.
({List<List<Object>> calls, List<int> indices}) renderSetupCalls(List<int> outputs, double fromBeat) {
  final calls = <List<Object>>[
    ['loop_set', 0, 0, 0],
    ['metronome', 0, 0],
    ['watch_fx', -1, -1],
    ['watch_analyzer', -2],
    ['capture_clear'],
  ];
  final indices = <int>[];
  var next = 0;
  for (final o in outputs) {
    if (o < -1 || next >= maxCaptures) {
      indices.add(-1);
      continue;
    }
    calls.add(['capture_add', o]);
    indices.add(next++);
  }
  calls
    ..add(['seek', fromBeat])
    ..add(['play']);
  return (calls: calls, indices: indices);
}

/// Pedido de render para o isolate (só dados: vai copiado para lá).
final class RenderJob {
  RenderJob({
    required this.calls,
    required this.samples,
    required this.fromBeat,
    required this.toBeat,
    required this.tailSeconds,
    required this.outputs,
    required this.rate,
    this.maxBytes = maxRenderBytes,
  });

  final List<List<Object>> calls;

  /// Os áudios pelo id do motor; o render troca por um vazio quando o motor já tem todos (ver
  /// `releaseSamples` em [renderNow]).
  Map<int, DecodedAudio> samples;
  final double fromBeat, toBeat, tailSeconds, rate;
  final List<int> outputs;
  final int maxBytes;
}

/// Resultado de [renderNow]: os canais (esq, dir) de cada saída, ou o código do erro (`empty`,
/// `memory`, `canceled`, `failed`) com a mensagem para o usuário.
typedef RenderOutcome = ({List<List<Float32List>>? outputs, String? code, String? message});

RenderOutcome _renderError(String code, String message) => (outputs: null, code: code, message: message);

/// Renderiza [job] num motor próprio da biblioteca [library], sem thread de áudio (roda no isolate
/// que chamar). O progresso (0..1) vai por [progress] algumas vezes por segundo; um valor diferente
/// de zero no int32 nativo em [cancelAddress] interrompe no próximo bloco.
///
/// Mais de [maxCaptures] saídas vão em passadas, cada uma num motor novo com o documento inteiro:
/// o resultado é o mesmo, só leva mais tempo. [releaseSamples] solta `job.samples` quando o motor
/// já tem os áudios (só num isolate, onde o pedido é uma cópia).
RenderOutcome renderNow(RenderJob job, {required String library, SendPort? progress, int cancelAddress = 0, bool releaseSamples = false}) {
  final problem = checkRenderJob(job.fromBeat, job.toBeat, job.tailSeconds, job.rate, job.outputs);
  if (problem != null) return _renderError('failed', problem);
  final bpm = renderTempo(job.calls);
  final frames = renderFrames(job.fromBeat, job.toBeat, job.tailSeconds, bpm, job.rate);
  if (frames.range == 0) return _renderError('empty', 'Nada para renderizar: o trecho está vazio.');
  final total = frames.total;
  final count = job.outputs.length;
  RenderOutcome noMemory() {
    final minutes = (total / job.rate / 60).toStringAsFixed(1).replaceAll('.', ',');
    final outs = '$count ${count == 1 ? 'saída' : 'saídas'}';
    return _renderError('memory', 'Não há memória para renderizar $minutes min em $outs. Exporte um trecho menor ou menos faixas separadas.');
  }

  // os canais de saída primeiro: se não couberem, nem vale abrir o motor
  if (count * 2 * total * 4 > job.maxBytes) return noMemory();
  final List<List<Float32List>> result;
  try {
    result = [
      for (var i = 0; i < count; i++) [Float32List(total), Float32List(total)],
    ];
  } on OutOfMemoryError {
    return noMemory();
  }

  final EngineLib lib;
  try {
    lib = EngineLib.open(library);
  } on Object catch (e) {
    return _renderError('failed', 'O motor de áudio não carregou para o render: $e');
  }
  final cancel = cancelAddress == 0 ? null : Pointer<Int32>.fromAddress(cancelAddress);
  final docJson = encodeCalls(prepareRenderCalls(job.calls, job.toBeat, bpm)).json;
  final passes = (count + maxCaptures - 1) ~/ maxCaptures;
  final left = malloc<Float>(renderBlock);
  final right = malloc<Float>(renderBlock);
  final clock = Stopwatch()..start();
  var lastReport = -1000;
  try {
    for (var pass = 0; pass < passes; pass++) {
      final first = pass * maxCaptures;
      final outs = job.outputs.sublist(first, math.min(count, first + maxCaptures));
      final handle = lib.offlineNew(job.rate);
      if (handle == 0) return _renderError('failed', 'O motor não conseguiu preparar o render.');
      try {
        _offlineSamples(lib, handle, job.samples);
        // na última passada a cópia que veio para o isolate já não serve: solta antes do render
        // (num projeto longo, os áudios em dobro pesam tanto quanto as saídas)
        if (releaseSamples && pass == passes - 1) job.samples = const {};
        _withNativeBytes(docJson, (p, n) => lib.offlineCalls(handle, p, n));
        final setup = renderSetupCalls(outs, job.fromBeat);
        _withNativeBytes(encodeCalls(setup.calls).json, (p, n) => lib.offlineCalls(handle, p, n));
        var done = 0;
        while (done < total) {
          if (cancel != null && cancel.value != 0) return _renderError('canceled', 'A renderização foi cancelada.');
          final n = math.min(renderBlock, total - done);
          lib.offlineProcess(handle, n);
          for (var k = 0; k < outs.length; k++) {
            final index = setup.indices[k];
            if (index < 0) continue;
            lib.offlineCaptured(handle, index, left, right, n);
            final [l, r] = result[first + k];
            l.setRange(done, done + n, left.asTypedList(n));
            r.setRange(done, done + n, right.asTypedList(n));
          }
          done += n;
          if (progress != null && clock.elapsedMilliseconds - lastReport >= 100) {
            lastReport = clock.elapsedMilliseconds;
            progress.send((pass + done / total) / passes);
          }
        }
      } finally {
        lib.offlineFree(handle);
      }
    }
  } finally {
    malloc.free(left);
    malloc.free(right);
  }
  progress?.send(1.0);
  return (outputs: result, code: null, message: null);
}

void _offlineSamples(EngineLib lib, int handle, Map<int, DecodedAudio> samples) {
  for (final MapEntry(key: id, value: audio) in samples.entries) {
    if (audio.channels.isEmpty) continue;
    final l = audio.channels[0];
    final n = l.length;
    if (n == 0 || !audio.rate.isFinite || audio.rate <= 0) continue;
    final r = audio.channels.length > 1 && audio.channels[1].length == n ? audio.channels[1] : null;
    _withNativeFloats(l, n, (pl) => _withNativeFloats(r, n, (pr) => lib.offlineSample(handle, id, pl, pr, n, audio.rate)));
  }
}

// ------------------------------------------------------------------ decodificação

const _undecodable = 'Não deu para decodificar este áudio: o formato não é suportado ou o arquivo está danificado.';

/// Decodifica [bytes] (wav, flac, mp3, ogg/vorbis, aac/m4a) pela biblioteca [library], no isolate
/// que chamar: os dois primeiros canais, na taxa do arquivo (o motor converte ao tocar).
/// Arquivo que não decodifica: [FormatException] com a mensagem para o usuário.
DecodedAudio decodeNow(Uint8List bytes, String library) {
  if (bytes.isEmpty) throw const FormatException(_undecodable);
  final lib = EngineLib.open(library);
  final handle = _withNativeBytes(bytes, lib.decode);
  if (handle == 0) throw const FormatException(_undecodable);
  // células de 64 bits zeradas: um u32 ou um usize escrito nelas se lê igual em little-endian
  final framesCell = calloc<Uint64>();
  final channelsCell = calloc<Uint64>();
  final rateCell = calloc<Double>();
  try {
    lib.decodedInfo(handle, framesCell, channelsCell, rateCell);
    final frames = framesCell.value, channels = channelsCell.value, rate = rateCell.value;
    if (frames <= 0 || channels <= 0 || !rate.isFinite || rate <= 0) throw const FormatException(_undecodable);
    // mais que isso não cabe num Float32List (nem na memória de um celular)
    if (frames > 0x7fffffff ~/ 4) throw const FormatException('Este áudio é longo demais para abrir no aparelho.');
    final Pointer<Float> out;
    try {
      out = malloc<Float>(frames);
    } on ArgumentError {
      throw const FormatException('Não há memória para abrir este áudio no aparelho.');
    }
    try {
      final list = <Float32List>[];
      for (var c = 0; c < math.min(2, channels); c++) {
        lib.decodedCopy(handle, c, out);
        list.add(Float32List.fromList(out.asTypedList(frames)));
      }
      return DecodedAudio(list, rate);
    } on OutOfMemoryError {
      throw const FormatException('Não há memória para abrir este áudio no aparelho.');
    } finally {
      malloc.free(out);
    }
  } finally {
    calloc
      ..free(framesCell)
      ..free(channelsCell)
      ..free(rateCell);
    lib.decodedFree(handle);
  }
}

/// Esticar e transpor no isolate atual (o chamado roda num isolate; ver [FfiEngine.stretch]).
DecodedAudio stretchNow(DecodedAudio a, double ratio, double semitones, String library) {
  final lib = EngineLib.open(library);
  final l = a.channels[0];
  final r = a.channels.length > 1 ? a.channels[1] : null;
  final frames = r == null ? l.length : math.min(l.length, r.length);
  final handle = _withNativeFloats(l, frames, (pl) => _withNativeFloats(r, frames, (pr) => lib.stretch(pl, pr, frames, a.rate, ratio, semitones)));
  if (handle == 0) throw StateError('Não deu para processar este áudio (memória ou parâmetros inválidos).');
  final framesCell = calloc<Uint64>();
  final channelsCell = calloc<Uint64>();
  final rateCell = calloc<Double>();
  try {
    lib.decodedInfo(handle, framesCell, channelsCell, rateCell);
    final n = framesCell.value, channels = channelsCell.value;
    final out = malloc<Float>(math.max(1, n));
    try {
      final list = <Float32List>[];
      for (var c = 0; c < math.min(2, channels); c++) {
        lib.decodedCopy(handle, c, out);
        list.add(Float32List.fromList(out.asTypedList(n)));
      }
      return DecodedAudio(list, a.rate);
    } finally {
      malloc.free(out);
    }
  } finally {
    calloc
      ..free(framesCell)
      ..free(channelsCell)
      ..free(rateCell);
    lib.decodedFree(handle);
  }
}

/// Estimar o andamento no isolate atual.
({double bpm, double confidence}) detectBpmNow(DecodedAudio a, String library) {
  final lib = EngineLib.open(library);
  final l = a.channels[0];
  final r = a.channels.length > 1 ? a.channels[1] : null;
  final frames = r == null ? l.length : math.min(l.length, r.length);
  final bpm = calloc<Double>();
  final confidence = calloc<Double>();
  try {
    final code = _withNativeFloats(l, frames, (pl) => _withNativeFloats(r, frames, (pr) => lib.detectBpm(pl, pr, frames, a.rate, bpm, confidence)));
    if (code != 0) throw StateError('Não deu para analisar o andamento deste áudio.');
    return (bpm: bpm.value, confidence: confidence.value);
  } finally {
    calloc
      ..free(bpm)
      ..free(confidence);
  }
}

// ------------------------------------------------------------------ o motor que toca

/// O motor nativo tocando no aparelho, com a mesma interface do engine_web.dart (a documentação de
/// cada coisa está lá); os callbacks vão para [EngineEvents].
final class FfiEngine {
  FfiEngine(this._events, {this.library = nativeLibraryName, Future<PermissionStatus> Function()? microphonePermission})
    : _microphonePermission = microphonePermission ?? Permission.microphone.request;

  final EngineEvents _events;

  /// Caminho (ou nome) da biblioteca: nos testes, uma de mentira.
  final String library;

  final Future<PermissionStatus> Function() _microphonePermission;

  EngineLib? _lib;

  /// Taxa da saída; null com o motor parado.
  double? _rate;

  EngineLib _open() {
    final lib = _lib;
    if (lib != null) return lib;
    try {
      return _lib = EngineLib.open(library);
    } on Object catch (e) {
      debugPrint('motor de áudio: $e');
      throw UnsupportedError(
        'O motor de áudio não carregou neste aparelho (a biblioteca nativa não veio no app para este processador). Atualize o app e tente de novo.',
      );
    }
  }

  /// A biblioteca com o motor ligado; parado, [StateError].
  EngineLib _running() {
    final lib = _lib;
    if (lib == null || _rate == null) throw StateError('O motor de áudio não está ligado.');
    return lib;
  }

  /// Sobe a saída de áudio (baixa latência, taxa nativa do aparelho) e o motor; devolve a taxa.
  /// Ligado, só devolve a taxa.
  Future<double> start() async {
    final running = _rate;
    if (running != null) return running;
    final lib = _open();
    final double rate;
    try {
      // o que o controlador usa em toda tela: faltando, melhor dizer já do que falhar no meio
      lib
        ..calls
        ..sampleLoad
        ..state;
      rate = lib.start();
    } on ArgumentError catch (e) {
      debugPrint('motor de áudio: $e');
      throw UnsupportedError('O motor de áudio deste app está incompleto. Atualize o app e tente de novo.');
    }
    if (!rate.isFinite || rate <= 0) {
      throw StateError('Não deu para abrir a saída de áudio do aparelho. Feche outros apps que estejam usando o áudio e tente de novo.');
    }
    _rate = rate;
    _watchLifecycle();
    _schedule();
    return rate;
  }

  /// No navegador destrava o áudio depois de um gesto; aqui a saída já toca desde o [start].
  Future<void> resume() async {}

  void calls(List<List<Object>> list) {
    for (final c in list) {
      if (c.length > 1 && c.first == 'watch_analyzer') {
        final track = c[1];
        _analyzing = track is num && track != -2;
        if (!_analyzing) _spectrum = null;
      }
    }
    final lib = _lib;
    // antes de ligar não há motor para receber (na web as chamadas também se perdem)
    if (lib == null || _rate == null || list.isEmpty) return;
    final (:json, :skipped) = encodeCalls(list);
    if (skipped > 0) debugPrint('motor de áudio: $skipped chamada(s) com número não finito ficaram de fora');
    final p = _jsonBuffer(json.length);
    p.asTypedList(json.length).setAll(0, json);
    final r = lib.calls(p, json.length);
    if (r < 0) debugPrint('motor de áudio: jd_calls devolveu $r');
  }

  Pointer<Uint8> _json = nullptr;
  int _jsonCapacity = 0;

  /// Memória reaproveitada para o JSON das chamadas: o `jd_calls` lê na hora (o parse é na thread
  /// de quem chama), então a mesma serve para a próxima.
  Pointer<Uint8> _jsonBuffer(int n) {
    if (n > _jsonCapacity) {
      if (_json != nullptr) malloc.free(_json);
      var capacity = math.max(4096, _jsonCapacity);
      while (capacity < n) {
        capacity *= 2;
      }
      _json = malloc<Uint8>(capacity);
      _jsonCapacity = capacity;
    }
    return _json;
  }

  void loadSample(int id, DecodedAudio audio) {
    final lib = _lib;
    if (lib == null || _rate == null || audio.channels.isEmpty) return;
    final l = audio.channels[0];
    final r = audio.channels.length > 1 ? audio.channels[1] : null;
    final frames = r == null ? l.length : math.min(l.length, r.length);
    // um áudio vazio não soa, e ponteiro de zero quadros o Rust não aceita como fatia
    if (frames == 0 || !audio.rate.isFinite || audio.rate <= 0) return;
    _withNativeFloats(l, frames, (pl) => _withNativeFloats(r, frames, (pr) => lib.sampleLoad(id, pl, pr, frames, audio.rate)));
  }

  double get latency {
    final lib = _lib;
    if (lib == null || _rate == null) return 0;
    try {
      final l = lib.latency();
      return l.isFinite && l > 0 ? l : 0;
    } on ArgumentError {
      return 0;
    }
  }

  /// Decodifica num isolate (arquivo grande não trava a tela).
  Future<DecodedAudio> decode(Uint8List bytes) {
    _open();
    return _decodeIn(bytes, library);
  }

  // estático: o closure do isolate não pode levar o motor junto (timers e portas não viajam)
  static Future<DecodedAudio> _decodeIn(Uint8List bytes, String library) => Isolate.run(() => decodeNow(bytes, library), debugName: 'jopendaw: decodificar');

  /// Warp num isolate (o processamento leva de centenas de ms a segundos e não trava a tela).
  Future<DecodedAudio> stretch(DecodedAudio a, {required double ratio, double semitones = 0}) {
    _open();
    return _stretchIn(a, ratio, semitones, library);
  }

  static Future<DecodedAudio> _stretchIn(DecodedAudio a, double ratio, double semitones, String library) =>
      Isolate.run(() => stretchNow(a, ratio, semitones, library), debugName: 'jopendaw: warp');

  Future<({double bpm, double confidence})> detectBpm(DecodedAudio a) {
    _open();
    return _detectIn(a, library);
  }

  static Future<({double bpm, double confidence})> _detectIn(DecodedAudio a, String library) =>
      Isolate.run(() => detectBpmNow(a, library), debugName: 'jopendaw: andamento');

  /// sha-256 em hexa; arquivo grande num isolate (centenas de MB levariam segundos na tela).
  Future<String> sha256Hex(Uint8List bytes) async {
    if (bytes.length < 1 << 20) return sha256.convert(bytes).toString();
    return _sha256In(bytes);
  }

  static Future<String> _sha256In(Uint8List bytes) => Isolate.run(() => sha256.convert(bytes).toString(), debugName: 'jopendaw: sha-256');

  // ---------------------------------------------------------------- estado por polling

  /// Valores que cabem na leitura do estado: batida, tocando, indicador, quantos picos e os picos
  /// (esq, dir) de até 1024 faixas mais o master.
  static const _stateMax = 4 + 2 * 1025;

  /// Faixas do espectro (FFT de 2048 pontos), como o analisador do worklet.
  static const _spectrumBins = 1024;

  /// A cada quantos estados vem um espectro (~20 por segundo, como no worklet).
  static const _spectrumEvery = 3;

  /// O pico da entrada vai a ~30 por segundo (a cada 2 leituras de ~16 ms).
  static const _levelEvery = 2;

  Timer? _timer;
  int _tick = 0;
  bool _background = false;
  bool _analyzing = false;
  Float32List? _spectrum;
  AppLifecycleListener? _lifecycle;

  // memórias nativas das leituras, reservadas uma vez; com espaço para doubles, para uma leitura
  // escrita em f64 não passar do fim
  Pointer<Double> _stateBuf = nullptr;
  Float32List? _stateF32;
  Float64List? _stateF64;
  Pointer<Double> _spectrumBuf = nullptr;

  /// Liga o polling quando alguém precisa dele: o estado com o app na frente, a captura e o pico
  /// da entrada sempre (em segundo plano o que chega da entrada precisa continuar saindo da fila).
  void _schedule() {
    final want = _rate != null && (!_background || _inputOpen || _capturing || _finishing != null);
    if (want && _timer == null) {
      _timer = Timer.periodic(const Duration(milliseconds: 16), (_) => _poll());
    } else if (!want && _timer != null) {
      _timer!.cancel();
      _timer = null;
    }
  }

  void _poll() {
    final lib = _lib;
    if (lib == null || _rate == null) return;
    _tick++;
    try {
      if (!_background) _pollState(lib);
      if (_capturing || _finishing != null) _drainRecorded(lib);
      if (_finishing != null) _maybeFinishCapture(lib);
      if (_inputOpen && _tick % _levelEvery == 0) _pollInputLevel(lib);
      if (!_background && _tick % _loudnessEvery == 0) _pollLoudness(lib);
    } on Object catch (e, s) {
      // um erro aqui repetiria 60 vezes por segundo: avisa uma vez por tipo e segue
      if (_pollErrors.add(e.runtimeType)) debugPrint('motor de áudio: $e\n$s');
    }
  }

  final _pollErrors = <Type>{};

  /// A cada quantas leituras vem a medida de loudness (~20 por segundo).
  static const _loudnessEvery = 3;

  /// Loudness do master; o Dart só recebe quando muda.
  void Function(LoudnessReading reading)? onLoudness;
  LoudnessReading? _lastLoudness;
  // uma biblioteca de antes do medidor não tem `jd_loudness`: pergunta uma vez e desiste
  bool _noLoudness = false;

  void _pollLoudness(EngineLib lib) {
    final cb = onLoudness;
    if (cb == null || _noLoudness) return;
    final double Function(int) read;
    try {
      read = lib.loudness;
    } on ArgumentError {
      _noLoudness = true;
      return;
    }
    final r = LoudnessReading.fromList([for (var k = 0; k < 5; k++) read(k)]);
    if (r == _lastLoudness) return;
    _lastLoudness = r;
    cb(r);
  }

  void _pollState(EngineLib lib) {
    final onState = _events.onState;
    if (onState == null) return;
    if (_stateBuf == nullptr) {
      _stateBuf = calloc<Double>(_stateMax);
      _stateF32 = _stateBuf.cast<Float>().asTypedList(2 * _stateMax);
      _stateF64 = _stateBuf.asTypedList(_stateMax);
    }
    final n = lib.state(_stateBuf.cast<Float>(), _stateMax);
    if (_analyzing && _tick % _spectrumEvery == 0) {
      if (_spectrumBuf == nullptr) _spectrumBuf = calloc<Double>(_spectrumBins);
      final bins = math.min(lib.spectrum(_spectrumBuf.cast<Float>(), _spectrumBins), _spectrumBins);
      // sem faixa observada ainda (o motor leva um bloco): fica o último
      if (bins > 0) _spectrum = _spectrumBuf.cast<Float>().asTypedList(bins).sublist(0);
    }
    final s = parseEngineState(_stateF32!, _stateF64!, n, spectrum: _analyzing ? _spectrum : null);
    if (s != null) onState(s);
  }

  void _watchLifecycle() {
    if (_lifecycle != null) return;
    try {
      _lifecycle = AppLifecycleListener(onStateChange: _onLifecycle);
    } on Object catch (e) {
      // sem binding (fora de um app Flutter): o polling fica sempre ligado
      debugPrint('motor de áudio: sem ciclo de vida do app: $e');
    }
  }

  void _onLifecycle(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.hidden || AppLifecycleState.paused:
        _background = true;
      case AppLifecycleState.resumed || AppLifecycleState.inactive:
        _background = false;
      case AppLifecycleState.detached:
        stop();
        return;
    }
    _schedule();
  }

  /// Para o motor: a saída, a entrada e o polling. Vem quando o app é desmontado (a atividade
  /// morreu com o processo vivo), para nada seguir tocando sem ninguém que controle; um [start]
  /// depois sobe tudo de novo. Uma captura pela metade termina vazia.
  void stop() {
    _timer?.cancel();
    _timer = null;
    _lifecycle?.dispose();
    _lifecycle = null;
    final lib = _lib;
    if (lib == null || _rate == null) return;
    final waiting = _capturing || _finishing != null;
    try {
      if (_capturing) lib.capture(0);
      if (_inputOpen) lib.inputStop();
      lib.stop();
    } on Object catch (e) {
      debugPrint('motor de áudio: $e');
    }
    _capturing = false;
    _finishing = null;
    _inputOpen = false;
    _rate = null;
    if (waiting) scheduleMicrotask(() => _events.onCaptureEnd?.call(const []));
  }

  // ---------------------------------------------------------------- entrada e captura

  /// Quadros por leitura da captura.
  static const _recMax = 16384;

  /// Floats da leitura das notas registradas (16384 notas e 32768 eventos de controle de 5 floats,
  /// como no worklet).
  static const _notesMax = 5 * (16384 + 32768);

  bool _inputOpen = false;
  bool _capturing = false;

  /// Desde quando a captura está desligando (o resto do áudio ainda saindo da fila); null fora disso.
  Stopwatch? _finishing;

  Pointer<Double> _recL = nullptr, _recR = nullptr;
  Pointer<Double> _recBeat = nullptr;
  Pointer<Double> _notesBuf = nullptr;

  Future<double> startInput(String? deviceId) async {
    final lib = _running();
    final permission = await _microphonePermission();
    switch (permission) {
      case PermissionStatus.granted || PermissionStatus.limited || PermissionStatus.provisional:
        break;
      case PermissionStatus.permanentlyDenied || PermissionStatus.restricted:
        throw StateError(
          'O Android negou o acesso ao microfone de vez: libere o microfone nas permissões do jopendaw (Configurações › Apps › jopendaw › Permissões) e tente de novo.',
        );
      case PermissionStatus.denied:
        throw StateError('O Android negou o acesso ao microfone. Permita o microfone para o jopendaw e tente de novo.');
    }
    var device = -1;
    if (deviceId != null) {
      final id = int.tryParse(deviceId);
      final present = (await inputDevices()).any((d) => d.$1 == deviceId);
      if (id == null || !present) throw StateError('A entrada de áudio escolhida não está mais conectada. Escolha outra ou volte para a padrão.');
      device = id;
    }
    // abrir de novo troca a entrada
    if (_inputOpen) {
      lib.inputStop();
      _inputOpen = false;
    }
    final latency = lib.inputStart(device);
    if (latency.isNaN || latency < 0) {
      throw StateError(
        'Não deu para abrir a entrada de áudio do aparelho (erro ${latency.isNaN ? '?' : latency.round()}). '
        'Confira se outro app está usando o microfone e tente de novo.',
      );
    }
    _inputOpen = true;
    _schedule();
    return latency.isFinite ? latency : 0;
  }

  Future<void> stopInput() async {
    final lib = _lib;
    if (lib == null || !_inputOpen) return;
    _inputOpen = false;
    lib.inputStop();
    _events.onInputLevel?.call(0);
    _schedule();
  }

  Future<List<(String, String)>> inputDevices() async {
    final lib = _open();
    var capacity = 4096;
    for (var attempt = 0; attempt < 3; attempt++) {
      final p = malloc<Uint8>(capacity);
      try {
        final n = lib.inputDevices(p, capacity);
        if (n <= 0) return const [];
        if (n > capacity) {
          capacity = n;
          continue;
        }
        return parseInputDevices(utf8.decode(p.asTypedList(n), allowMalformed: true));
      } finally {
        malloc.free(p);
      }
    }
    return const [];
  }

  void _pollInputLevel(EngineLib lib) {
    final peak = lib.inputLevel();
    if (peak.isNaN || peak < 0) {
      // a entrada caiu sozinha (fone desconectado, interface desligada, permissão revogada)
      _inputOpen = false;
      lib.inputStop();
      _events.onInputLevel?.call(0);
      _events.onInputLost?.call('A entrada de áudio foi desconectada.');
      _schedule();
      return;
    }
    _events.onInputLevel?.call(peak.isFinite ? math.min(peak, 1.0) : 0);
  }

  void setCapture(bool on) {
    if (on) {
      final lib = _running();
      if (_capturing) return;
      // a captura anterior ainda desligando: termina agora, para as duas não se misturarem
      if (_finishing != null) _finishCapture(lib);
      lib.capture(1);
      _capturing = true;
      _schedule();
      return;
    }
    final lib = _lib;
    if (lib == null || !_capturing) {
      // nada capturando: quem espera o fim recebe um vazio, como se nada tivesse sido tocado
      scheduleMicrotask(() => _events.onCaptureEnd?.call(const []));
      return;
    }
    lib.capture(0);
    _capturing = false;
    _finishing = Stopwatch()..start();
    _schedule();
  }

  /// Tempo para a thread de áudio aplicar o fim da captura e publicar o resto: alguns buffers de
  /// saída, entre 80 e 400 ms.
  Duration get _finishGrace {
    final ms = (latency * 3 * 1000).round().clamp(80, 400);
    return Duration(milliseconds: ms);
  }

  var _lastDrain = 0;

  void _maybeFinishCapture(EngineLib lib) {
    final f = _finishing;
    if (f == null || f.elapsed < _finishGrace) return;
    // ainda chegando áudio: espera esvaziar (com um teto, se a fila nunca parasse)
    if (_lastDrain > 0 && f.elapsed < const Duration(seconds: 2)) return;
    _finishCapture(lib);
  }

  /// Entrega o resto do áudio e depois as notas registradas, nessa ordem (como o worklet).
  void _finishCapture(EngineLib lib) {
    _drainRecorded(lib);
    _finishing = null;
    final notes = _readNotes(lib);
    _schedule();
    _events.onCaptureEnd?.call(notes);
  }

  List<RecordedNote> _readNotes(EngineLib lib) {
    if (_notesBuf == nullptr) _notesBuf = calloc<Double>(_notesMax);
    final all = <double>[];
    try {
      // o registro sai conforme é lido: lê até esvaziar
      for (var i = 0; i < 16; i++) {
        final n = math.min(lib.recNotes(_notesBuf.cast<Float>(), _notesMax), _notesMax);
        if (n <= 0) break;
        all.addAll(_notesBuf.cast<Float>().asTypedList(n));
        if (n < _notesMax) break;
      }
    } on ArgumentError catch (e) {
      debugPrint('motor de áudio: sem notas registradas: $e');
    }
    return parseRecordedNotes(Float32List.fromList(all));
  }

  /// Tira da fila o que a entrada capturou e entrega em [EngineEvents.onRecord], cada leitura com a
  /// batida do primeiro quadro dela. Lê até a fila esvaziar: um salto de posição fecha uma leitura,
  /// e a seguinte vem com a batida nova. Sem ninguém ouvindo, descarta (a fila não pode encher).
  void _drainRecorded(EngineLib lib) {
    if (_recL == nullptr) {
      _recL = calloc<Double>(_recMax);
      _recR = calloc<Double>(_recMax);
      _recBeat = calloc<Double>();
    }
    var total = 0;
    for (var i = 0; i < 64; i++) {
      final n = math.min(lib.recorded(_recL.cast<Float>(), _recR.cast<Float>(), _recMax, _recBeat), _recMax);
      if (n <= 0) break;
      total += n;
      final onRecord = _events.onRecord;
      if (onRecord == null) continue;
      final beat = _recBeat.value;
      _events.recordBeat = beat.isFinite ? beat : 0;
      onRecord(_recL.cast<Float>().asTypedList(n).sublist(0), _recR.cast<Float>().asTypedList(n).sublist(0));
    }
    _lastDrain = total;
  }

  // ---------------------------------------------------------------- render

  final _renderFlags = <Pointer<Int32>>{};

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
    _open();
    final job = RenderJob(calls: calls, samples: samples, fromBeat: fromBeat, toBeat: toBeat, tailSeconds: tailSeconds, outputs: outputs, rate: rate);
    final flag = calloc<Int32>();
    _renderFlags.add(flag);
    final port = ReceivePort();
    port.listen((m) {
      if (m is double && onProgress != null) onProgress(m.isFinite ? m.clamp(0.0, 1.0) : 0.0);
    });
    try {
      final r = await _renderIn(job, library, port.sendPort, flag.address);
      switch (r.code) {
        case null:
          return r.outputs ?? (throw StateError('O render não devolveu áudio.'));
        case 'canceled':
          throw const RenderCanceled();
        default:
          throw StateError(r.message ?? 'O render falhou.');
      }
    } on RenderCanceled {
      rethrow;
    } on StateError {
      rethrow;
    } on Object catch (e) {
      throw StateError('O motor falhou no render: $e');
    } finally {
      port.close();
      _renderFlags.remove(flag);
      calloc.free(flag);
    }
  }

  static Future<RenderOutcome> _renderIn(RenderJob job, String library, SendPort progress, int flag) => Isolate.run(
    () => renderNow(job, library: library, progress: progress, cancelAddress: flag, releaseSamples: true),
    debugName: 'jopendaw: render',
  );

  /// Cada render em andamento para no próximo bloco e termina com [RenderCanceled].
  void cancelRender() {
    for (final f in _renderFlags) {
      f.value = 1;
    }
  }

  // ---------------------------------------------------------------- arquivos

  /// Oferece os bytes para salvar: o seletor de "salvar como" do Android (Storage Access
  /// Framework). Sem ele (aparelho sem o app de arquivos), a folha de compartilhar, que ainda deixa
  /// mandar para o Drive, os Arquivos ou outro app. Cancelar não é erro.
  Future<void> saveFile(String name, Uint8List bytes, String mime) async {
    try {
      await FilePicker.saveFile(fileName: name, bytes: bytes, mimeType: mime, dialogTitle: 'Salvar $name');
      return;
    } on PlatformException catch (e) {
      if (e.code == 'already_active') throw StateError('Já há uma janela de salvar aberta: termine ela e tente de novo.');
      debugPrint('salvar arquivo: $e');
    } on MissingPluginException catch (e) {
      debugPrint('salvar arquivo: $e');
    }
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: mime, name: name)],
        fileNameOverrides: [name],
      ),
    );
  }

  // ---------------------------------------------------------------- MIDI

  MidiCommand? _midi;
  StreamSubscription<MidiPacket>? _midiData;
  StreamSubscription<MidiSetupChange>? _midiSetup;

  /// Liga o MIDI do Android (USB e os aparelhos que o sistema já conhece): conecta em todas as
  /// entradas e passa a ouvir; devolve os nomes delas. Sem MIDI no aparelho: [UnsupportedError];
  /// outra falha: [StateError].
  Future<List<String>> enableMidi() async {
    try {
      final midi = _midi ??= MidiCommand();
      _midiData ??= midi.onMidiPacketReceived?.listen(_onMidiPacket);
      _midiSetup ??= midi.onMidiSetupChanged?.listen((_) => unawaited(_refreshMidi()));
      return await _connectMidi(midi);
    } on MissingPluginException {
      throw UnsupportedError('Este aparelho não dá acesso a MIDI.');
    } on PlatformException catch (e) {
      throw StateError('Não deu para abrir o MIDI: ${e.message ?? e.code}.');
    }
  }

  /// Uma conexão de cada vez: conectar um aparelho avisa que o MIDI mudou, e o aviso não pode
  /// começar outra rodada no meio desta (o mesmo aparelho seria conectado duas vezes).
  Future<void> _midiChain = Future.value();

  Future<List<String>> _connectMidi(MidiCommand midi) {
    final next = _midiChain.then((_) => _connectMidiNow(midi));
    _midiChain = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  /// Conecta o que ainda não está conectado e devolve os nomes de todos os conectados. Ficam de
  /// fora o dispositivo virtual do próprio plugin e o aparelho que só recebe MIDI (não toca nada
  /// aqui); um que não conecta sai sem derrubar os outros.
  Future<List<String>> _connectMidiNow(MidiCommand midi) async {
    final devices = await midi.devices ?? const <MidiDevice>[];
    final names = <String>[];
    for (final d in devices) {
      if (d.type == MidiDeviceType.ownVirtual) continue;
      if (d.outputPorts.isEmpty && d.inputPorts.isNotEmpty) continue;
      if (!d.connected) {
        try {
          await midi.connectToDevice(d, awaitConnectionTimeout: const Duration(seconds: 5));
        } on Object catch (e) {
          debugPrint('MIDI: ${d.name} não conectou: $e');
          continue;
        }
      }
      names.add(d.name.trim().isEmpty ? 'MIDI ${names.length + 1}' : d.name.trim());
    }
    return names;
  }

  Future<void> _refreshMidi() async {
    final midi = _midi;
    if (midi == null) return;
    try {
      _events.onMidiInputs?.call(await _connectMidi(midi));
    } on Object catch (e) {
      debugPrint('MIDI: $e');
    }
  }

  /// Só mensagens de canal (0x80..0xEF): relógio, active sensing e sysex ficam de fora, como na web.
  void _onMidiPacket(MidiPacket p) {
    final d = p.data;
    if (d.isEmpty) return;
    final status = d[0];
    if (status < 0x80 || status >= 0xF0) return;
    _events.onMidi?.call(status, d.length > 1 ? d[1] & 0x7F : 0, d.length > 2 ? d[2] & 0x7F : 0);
  }
}
