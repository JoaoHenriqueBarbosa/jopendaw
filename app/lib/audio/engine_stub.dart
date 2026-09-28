import 'dart:typed_data';

import 'engine_types.dart';

/// Fora da web o motor nativo ainda não existe: a tela do projeto avisa em vez de tocar.
class AudioEngine {
  AudioEngine._();
  static final instance = AudioEngine._();

  bool get supported => false;
  Future<double> start() => Future.error(UnsupportedError('O motor de áudio do Android ainda não está pronto.'));
  Future<void> resume() async {}
  Future<DecodedAudio> decode(Uint8List bytes) => Future.error(UnsupportedError('Sem motor de áudio.'));
  void loadSample(int id, DecodedAudio audio) {}
  void calls(List<List<Object>> list) {}
  void Function(EngineState state)? onState;
  double get latency => 0;
}

/// Guardado local do DAW (documento e áudios).
class LocalStore {
  LocalStore._();
  static final instance = LocalStore._();

  Future<Object?> get(String key) async => null;
  Future<void> put(String key, Object value) async {}
  Future<void> delete(String key) async {}
}
