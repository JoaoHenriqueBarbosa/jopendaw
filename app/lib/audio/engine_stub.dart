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

  // ------------------------------------------------------------------ gravação e render (fase 4)
  // Mesma interface do engine_web.dart (veja a documentação de lá). Fora do navegador ainda não há
  // entrada de áudio nem render: abrir, capturar, renderizar e salvar falham com
  // [UnsupportedError]; fechar e cancelar (limpeza) não têm o que fazer e só voltam.

  static const _noRecording = 'A gravação ainda não funciona fora do navegador: use o jopendaw no navegador por enquanto.';
  static const _noRender = 'Exportar e congelar faixas ainda não funcionam fora do navegador: use o jopendaw no navegador por enquanto.';

  /// Abre a entrada de áudio ([deviceId] null = padrão) sem processamento de voz e devolve a
  /// latência de entrada (s). Aqui: [UnsupportedError].
  Future<double> startInput(String? deviceId) => Future.error(UnsupportedError(_noRecording));

  /// Fecha a entrada. Aqui: nada aberto, nada a fechar.
  Future<void> stopInput() async {}

  /// Entradas de áudio (id, nome), a padrão sendo o id null. Aqui: [UnsupportedError].
  Future<List<(String, String)>> inputDevices() => Future.error(UnsupportedError(_noRecording));

  /// Liga/desliga a captura (áudio da entrada em [onRecord] enquanto o transporte toca, notas ao
  /// vivo no motor; o fim chega em [onCaptureEnd]). Aqui: desligar não tem o que fazer, ligar dá
  /// [UnsupportedError].
  void setCapture(bool on) {
    if (on) throw UnsupportedError(_noRecording);
  }

  /// Blocos capturados da entrada (esq, dir) e o pico dela (~30 por segundo com a entrada aberta).
  void Function(Float32List left, Float32List right)? onRecord;
  void Function(double peak)? onInputLevel;

  /// Batida do transporte no primeiro quadro do bloco que [onRecord] está entregando.
  double recordBeat = 0;

  /// Fim de uma captura, depois do último bloco de [onRecord], com as notas registradas.
  void Function(List<RecordedNote> notes)? onCaptureEnd;

  /// A entrada aberta sumiu sozinha (já fechada); vem a mensagem para o usuário.
  void Function(String message)? onInputLost;

  /// Renderiza fora de tempo real os canais de cada saída em [outputs] (−1 = master, i = faixa i,
  /// pós-fader), de [fromBeat] a [toBeat] mais [tailSeconds]. Aqui: [UnsupportedError].
  Future<List<List<Float32List>>> renderOffline({
    required List<List<Object>> calls,
    required Map<int, DecodedAudio> samples,
    required double fromBeat,
    required double toBeat,
    required double tailSeconds,
    required List<int> outputs,
    required double rate,
    void Function(double progress)? onProgress,
  }) => Future.error(UnsupportedError(_noRender));

  /// Interrompe os renders em andamento ([RenderCanceled]). Aqui: nenhum para cancelar.
  void cancelRender() {}

  /// Oferece os bytes para salvar como arquivo. Aqui: [UnsupportedError].
  Future<void> saveFile(String name, Uint8List bytes, String mime) =>
      Future.error(UnsupportedError('Salvar arquivos ainda não funciona fora do navegador: use o jopendaw no navegador por enquanto.'));
}

/// Nota tocada ao vivo durante uma captura (faixa, altura MIDI, início e fim em batidas,
/// velocidade 0..1); igual à do engine_web.dart.
typedef RecordedNote = ({int track, int pitch, double start, double end, double velocity});

/// O render foi cancelado por [AudioEngine.cancelRender]; igual à do engine_web.dart.
class RenderCanceled implements Exception {
  const RenderCanceled();

  @override
  String toString() => 'A renderização foi cancelada.';
}

/// Guardado local do DAW (documento e áudios).
class LocalStore {
  LocalStore._();
  static final instance = LocalStore._();

  Future<Object?> get(String key) async => null;
  Future<void> put(String key, Object value) async {}
  Future<void> delete(String key) async {}
}
