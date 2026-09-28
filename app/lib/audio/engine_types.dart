import 'dart:typed_data';

/// Áudio decodificado: um ou dois canais na taxa do motor.
class DecodedAudio {
  final List<Float32List> channels;
  final double rate;
  DecodedAudio(this.channels, this.rate);

  int get frames => channels.first.length;
  double get duration => frames / rate;
}

/// Estado que o motor devolve várias vezes por segundo.
class EngineState {
  final double beat;
  final bool playing;

  /// Picos (esq, dir) de cada faixa e, por último, do master, desde a leitura anterior.
  final Float32List peaks;
  const EngineState(this.beat, this.playing, this.peaks);
}
