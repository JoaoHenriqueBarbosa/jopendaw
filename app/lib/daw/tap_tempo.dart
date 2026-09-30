/// Tap tempo: o andamento pela média dos intervalos entre as últimas batidas tocadas.
///
/// Regras (o tempo vem de fora, em segundos, para o teste não depender do relógio):
/// - a média usa as últimas [maxTaps] batidas (até 7 intervalos); com só duas, vale o intervalo delas;
/// - parado por mais de [resetAfter] a sequência recomeça na batida nova;
/// - a primeira batida some se a segunda vem depois de [firstGap] (era só um toque solto): a segunda
///   passa a ser a primeira;
/// - um intervalo curto demais ([minInterval], mais de 400 BPM) é o ricochete do toque: a batida é
///   ignorada e não mexe na sequência;
/// - andamento mais lento: com as batidas a intervalos iguais, [slowestSteadyBpm] (30 BPM: o intervalo
///   entre a primeira e a segunda não passa de [firstGap]); depois de lançado o ritmo a média pode
///   cair até [slowestBpm] (24 BPM: nenhum intervalo passa de [resetAfter]). Mais lento que isso
///   recomeça a sequência; o andamento digitado no campo vai até [minBpm];
/// - o resultado fica entre [minBpm] e [maxBpm] e com uma casa decimal (a resolução do resto do app).
library;

import 'tempo_map.dart' show maxBpm, minBpm;

class TapTempo {
  /// Batidas que entram na média.
  static const maxTaps = 8;

  /// Parado por mais que isto (s), recomeça.
  static const resetAfter = 2.5;

  /// Depois da primeira batida, um intervalo maior que isto (s) descarta a primeira.
  static const firstGap = 2.0;

  /// O andamento mais lento que a sequência aguenta (BPM): um intervalo de [resetAfter].
  static const slowestBpm = 60 / resetAfter;

  /// O mais lento com batidas regulares: a segunda vem até [firstGap] depois da primeira.
  static const slowestSteadyBpm = 60 / firstGap;

  /// Intervalo mínimo (s) entre duas batidas.
  static const minInterval = 0.15;

  final _taps = <double>[];

  /// Quantas batidas valem agora.
  int get count => _taps.length;

  bool get isEmpty => _taps.isEmpty;

  /// Instante (s) da última batida que valeu, ou null.
  double? get last => _taps.isEmpty ? null : _taps.last;

  void reset() => _taps.clear();

  /// A batida no instante [now] (s). Devolve o andamento vigente (null com uma batida só).
  double? tap(double now) {
    if (!now.isFinite) return bpm;
    if (_taps.isNotEmpty) {
      final gap = now - _taps.last;
      if (gap < 0 || gap > resetAfter) {
        _taps.clear();
      } else if (gap < minInterval) {
        return bpm;
      } else if (_taps.length == 1 && gap > firstGap) {
        _taps.clear();
      }
    }
    _taps.add(now);
    if (_taps.length > maxTaps) _taps.removeAt(0);
    return bpm;
  }

  /// A média dos intervalos da janela em BPM (uma casa), ou null com menos de duas batidas.
  double? get bpm {
    if (_taps.length < 2) return null;
    final mean = (_taps.last - _taps.first) / (_taps.length - 1);
    final v = (60 / mean).clamp(minBpm, maxBpm);
    return (v * 10).round() / 10;
  }
}
