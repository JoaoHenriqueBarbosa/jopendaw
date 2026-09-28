import 'dart:js_interop';
import 'dart:typed_data';

import 'engine_types.dart';

@JS('jopendawEngine')
external _Host get _host;

extension type _Host._(JSObject _) implements JSObject {
  external JSPromise<JSNumber> start();
  external JSPromise<JSAny?> resume();
  external JSPromise<_Decoded> decode(JSUint8Array bytes);
  external void loadSample(int id, JSArray<JSFloat32Array> channels, double rate);
  external void calls(JSArray<JSArray<JSAny>> list);
  external void setOnState(JSFunction cb);
  external double latency();
  external JSPromise<JSAny?> idbGet(String key);
  external JSPromise<JSAny?> idbPut(String key, JSAny value);
  external JSPromise<JSAny?> idbDelete(String key);
  external JSPromise<_MidiAccess> enableMidi();
  external void setOnMidi(JSFunction cb);
  external void setOnMidiInputs(JSFunction cb);
}

/// Resposta do `enableMidi` do host: as entradas, ou o código do erro (`unsupported`, `denied`,
/// `failed`) com a mensagem do navegador.
extension type _MidiAccess._(JSObject _) implements JSObject {
  external JSArray<JSString>? get inputs;
  external String? get error;
  external String? get message;
}

extension type _Decoded._(JSObject _) implements JSObject {
  external JSArray<JSFloat32Array> get channels;
  external double get rate;
}

/// O motor no AudioWorklet, por `web/engine/host.js`.
class AudioEngine {
  AudioEngine._();
  static final instance = AudioEngine._();

  bool get supported => true;
  void Function(EngineState state)? onState;
  bool _hooked = false;

  /// Sobe o contexto de áudio e o motor; devolve a taxa de amostragem.
  Future<double> start() async {
    if (!_hooked) {
      _hooked = true;
      // medidor do efeito e espectro: opcionais, porque o dart2js despacha a função pelo número de
      // argumentos da chamada (com 5 obrigatórios, um host que manda 3 quebra todo estado); null
      // ou undefined viram 0 e null
      _host.setOnState(
        ((JSNumber beat, JSBoolean playing, JSFloat32Array peaks, [JSNumber? fxMeter, JSFloat32Array? spectrum]) {
          final meter = fxMeter?.toDartDouble ?? 0;
          onState?.call(EngineState(beat.toDartDouble, playing.toDart, peaks.toDart, fxMeter: meter.isFinite ? meter : 0, spectrum: spectrum?.toDart));
        }).toJS,
      );
    }
    return (await _host.start().toDart).toDartDouble;
  }

  /// Precisa vir de um gesto do usuário (o navegador segura o áudio até lá).
  Future<void> resume() => _host.resume().toDart;

  Future<DecodedAudio> decode(Uint8List bytes) async {
    final d = await _host.decode(bytes.toJS).toDart;
    return DecodedAudio([for (final c in d.channels.toDart) c.toDart], d.rate);
  }

  void loadSample(int id, DecodedAudio audio) => _host.loadSample(id, [for (final c in audio.channels) c.toJS].toJS, audio.rate);

  void calls(List<List<Object>> list) {
    _host.calls(
      [
        for (final c in list) [for (final a in c) _js(a)].toJS,
      ].toJS,
    );
  }

  /// Mensagens MIDI de entrada (status, dado 1, dado 2). Só mensagens de canal: relógio e
  /// active sensing ficam no host.
  void Function(int status, int data1, int data2)? onMidi;

  /// Entradas MIDI conectadas, a cada aparelho que entra ou sai.
  void Function(List<String> inputs)? onMidiInputs;
  bool _midiHooked = false;

  /// Pede acesso ao MIDI do navegador (Web MIDI, sem sysex) e passa a ouvir todas as entradas;
  /// devolve os nomes delas. Sem suporte: [UnsupportedError]; permissão negada: [StateError].
  Future<List<String>> enableMidi() async {
    if (!_midiHooked) {
      _midiHooked = true;
      _host.setOnMidi(
        ((JSNumber status, JSNumber data1, JSNumber data2) {
          onMidi?.call(status.toDartInt, data1.toDartInt, data2.toDartInt);
        }).toJS,
      );
      _host.setOnMidiInputs(
        ((JSArray<JSString> names) {
          onMidiInputs?.call(_names(names));
        }).toJS,
      );
    }
    final r = await _host.enableMidi().toDart;
    switch (r.error) {
      case null:
        final inputs = r.inputs;
        return inputs == null ? const [] : _names(inputs);
      case 'unsupported':
        throw UnsupportedError('Este navegador não dá acesso a MIDI. Use o Chrome ou o Edge, com o jopendaw aberto em https.');
      case 'denied':
        throw StateError('O navegador negou o acesso ao MIDI. Libere o MIDI nas permissões do site e tente de novo.');
      default:
        throw StateError('Não deu para abrir o MIDI: ${r.message ?? r.error}.');
    }
  }

  static List<String> _names(JSArray<JSString> names) => [for (final n in names.toDart) n.toDart];

  /// Latência de saída em segundos (base + dispositivo).
  double get latency => _host.latency();

  static JSAny _js(Object v) => switch (v) {
    final String s => s.toJS,
    final bool b => (b ? 1 : 0).toJS,
    final int i => i.toJS,
    final double d => d.toJS,
    _ => throw ArgumentError('argumento do motor: $v'),
  };

  // gravação e render fora de tempo real (contrato da fase 4)

  /// Abre a entrada de áudio ([deviceId] null = padrão) e liga a captura no worklet; devolve a
  /// latência de entrada que o navegador informa (s).
  Future<double> startInput(String? deviceId) => throw UnimplementedError();
  Future<void> stopInput() => throw UnimplementedError();

  /// Entradas de áudio (id, nome); pedir o microfone antes revela os nomes.
  Future<List<(String, String)>> inputDevices() => throw UnimplementedError();

  /// Liga/desliga a captura do que entra (blocos chegam em [onRecord]) e das notas ao vivo no
  /// motor.
  void setCapture(bool on) => throw UnimplementedError();

  /// Blocos capturados da entrada (esq, dir) e o pico dela, enquanto a captura está ligada.
  void Function(Float32List left, Float32List right)? onRecord;
  void Function(double peak)? onInputLevel;

  /// Renderiza fora de tempo real num motor separado (Worker): [calls] são as chamadas do
  /// documento (como o _sync manda), [samples] os áudios por id do motor; devolve os canais de
  /// cada saída pedida em [outputs] (−1 = master, i = só a faixa i, pós-fader).
  Future<List<List<Float32List>>> renderOffline({
    required List<List<Object>> calls,
    required Map<int, DecodedAudio> samples,
    required double fromBeat,
    required double toBeat,
    required double tailSeconds,
    required List<int> outputs,
    required double rate,
    void Function(double progress)? onProgress,
  }) => throw UnimplementedError();

  /// Oferece os bytes para salvar como arquivo (download no navegador).
  Future<void> saveFile(String name, Uint8List bytes, String mime) => throw UnimplementedError();
}

/// Guardado local do DAW no IndexedDB: textos (o documento) e bytes (os áudios importados).
class LocalStore {
  LocalStore._();
  static final instance = LocalStore._();

  Future<Object?> get(String key) async {
    final v = await _host.idbGet(key).toDart;
    if (v == null) return null;
    if (v.isA<JSString>()) return (v as JSString).toDart;
    if (v.isA<JSUint8Array>()) return (v as JSUint8Array).toDart;
    return null;
  }

  Future<void> put(String key, Object value) async {
    final JSAny js = switch (value) {
      final String s => s.toJS,
      final Uint8List b => b.toJS,
      _ => throw ArgumentError('valor do guardado local: ${value.runtimeType}'),
    };
    await _host.idbPut(key, js).toDart;
  }

  Future<void> delete(String key) => _host.idbDelete(key).toDart;
}
