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
      _host.setOnState(
        ((JSNumber beat, JSBoolean playing, JSFloat32Array peaks) {
          onState?.call(EngineState(beat.toDartDouble, playing.toDart, peaks.toDart));
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

  /// Latência de saída em segundos (base + dispositivo).
  double get latency => _host.latency();

  static JSAny _js(Object v) => switch (v) {
    final String s => s.toJS,
    final bool b => (b ? 1 : 0).toJS,
    final int i => i.toJS,
    final double d => d.toJS,
    _ => throw ArgumentError('argumento do motor: $v'),
  };
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
