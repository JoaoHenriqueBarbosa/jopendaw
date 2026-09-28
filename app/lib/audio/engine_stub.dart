import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;

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
  void calls(List<List<Object>> list) => log?.addAll(list);
  void Function(EngineState state)? onState;
  double get latency => 0;

  /// Nos testes: guarda aqui as chamadas que iriam ao motor (null não guarda).
  @visibleForTesting
  List<List<Object>>? log;

  /// Mensagens MIDI de entrada (status, dado 1, dado 2).
  void Function(int status, int data1, int data2)? onMidi;

  /// Entradas MIDI conectadas, a cada aparelho que entra ou sai.
  void Function(List<String> inputs)? onMidiInputs;

  /// Pede acesso ao MIDI; fora do navegador ainda não há.
  Future<List<String>> enableMidi() => Future.error(UnsupportedError('O MIDI ainda não funciona fora do navegador.'));

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

/// Guardado local do DAW (documento e áudios).
class LocalStore {
  LocalStore._();
  static final instance = LocalStore._();

  Future<Object?> get(String key) async => null;
  Future<void> put(String key, Object value) async {}
  Future<void> delete(String key) async {}
}
