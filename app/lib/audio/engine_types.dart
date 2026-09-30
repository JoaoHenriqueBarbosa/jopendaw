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

  /// Indicador do efeito observado (`watch_fx`): redução de ganho em dB na dinâmica; 0 se nenhum.
  final double fxMeter;

  /// Espectro da faixa observada (`watch_analyzer`), em dB por faixa linear de frequência de 0 à
  /// metade da taxa; null quando nada é observado.
  final Float32List? spectrum;

  const EngineState(this.beat, this.playing, this.peaks, {this.fxMeter = 0, this.spectrum});
}

/// Medida de loudness do master (BS.1770-4 / EBU R128) que o motor entrega várias vezes por
/// segundo: LUFS do momentâneo (400 ms), do curto prazo (3 s) e do integrado (desde o reset), true
/// peak máximo em dBTP e faixa de loudness em LU. [none] (−200) é "sem medida".
class LoudnessReading {
  static const double none = -200;

  final double momentary;
  final double shortTerm;
  final double integrated;
  final double truePeak;
  final double range;

  const LoudnessReading({this.momentary = none, this.shortTerm = none, this.integrated = none, this.truePeak = none, this.range = none});

  /// Nenhum valor não finito passa: vira "sem medida".
  factory LoudnessReading.fromList(List<double> v) {
    double at(int i) => i < v.length && v[i].isFinite ? v[i].clamp(none, 400.0).toDouble() : none;
    return LoudnessReading(momentary: at(0), shortTerm: at(1), integrated: at(2), truePeak: at(3), range: at(4));
  }

  /// Há medida (acima do piso).
  static bool has(double v) => v.isFinite && v > -150;

  @override
  bool operator ==(Object other) =>
      other is LoudnessReading &&
      other.momentary == momentary &&
      other.shortTerm == shortTerm &&
      other.integrated == integrated &&
      other.truePeak == truePeak &&
      other.range == range;

  @override
  int get hashCode => Object.hash(momentary, shortTerm, integrated, truePeak, range);

  @override
  String toString() => 'LoudnessReading($momentary, $shortTerm, $integrated, $truePeak, $range)';
}
