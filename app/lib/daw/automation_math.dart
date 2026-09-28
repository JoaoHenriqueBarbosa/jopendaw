/// A conta da automação, a mesma no desenho da raia e no que vai ao motor.
///
/// Entre dois pontos o valor anda na escala do controle do alvo (a curva do fader no volume e nos
/// envios, a escala logarítmica nos parâmetros em Hz e segundos, reta no pan): uma rampa
/// desenhada reta na raia soa reta, em vez de despencar no fim (ganho linear) ou subir quase toda
/// no começo (Hz linear). O motor só interpola reto no valor, então esses segmentos vão a ele como
/// vários pontos curtos ([autoEnginePoints]).
library;

import 'dart:math' as math;

import 'model.dart';

/// Ida e volta entre o valor do alvo e a posição 0..1 do controle dele; null = reta no valor.
typedef AutoWarp = ({double Function(double value) toNorm, double Function(double norm) fromNorm});

/// Forma entre dois pontos: t^(2^(curva·3)), curva −1..1 (0 reta).
double autoShape(double t, double curve) {
  if (t <= 0) return 0;
  if (t >= 1) return 1;
  if (curve == 0) return t;
  return math.pow(t, math.pow(2, curve.clamp(-1.0, 1.0) * 3)).toDouble();
}

/// Valor no segmento [a, b] numa batida entre os dois.
double autoSegment(AutoPoint a, AutoPoint b, double beat, AutoWarp? warp) {
  final span = b.beat - a.beat;
  if (span <= 0) return b.value;
  final t = autoShape((beat - a.beat) / span, a.curve);
  if (warp == null) return a.value + (b.value - a.value) * t;
  final na = warp.toNorm(a.value), nb = warp.toNorm(b.value);
  return warp.fromNorm(na + (nb - na) * t);
}

/// Valor da automação numa batida (pontos em ordem); sem pontos, [fallback].
double autoValueAt(List<AutoPoint> points, double beat, double fallback, {AutoWarp? warp}) {
  if (points.isEmpty) return fallback;
  if (beat <= points.first.beat) return points.first.value;
  if (beat >= points.last.beat) return points.last.value;
  var lo = 0, hi = points.length - 1;
  while (hi - lo > 1) {
    final mid = (lo + hi) >> 1;
    if (points[mid].beat <= beat) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return autoSegment(points[lo], points[lo + 1], beat, warp);
}

/// Os pontos que vão ao motor (batida, valor, curva). Sem [warp], os próprios pontos. Com ele,
/// cada segmento vira pontos retos a cada 1/8 de batida (de 4 a 64 por segmento): o erro de
/// ligar pontos tão próximos por reta fica abaixo do que se ouve.
List<(double, double, double)> autoEnginePoints(List<AutoPoint> sorted, AutoWarp? warp) {
  if (warp == null) return [for (final p in sorted) (p.beat, p.value, p.curve)];
  final out = <(double, double, double)>[];
  for (var i = 0; i < sorted.length; i++) {
    final a = sorted[i];
    out.add((a.beat, a.value, 0));
    if (i + 1 >= sorted.length) break;
    final b = sorted[i + 1];
    final span = b.beat - a.beat;
    if (span <= 0) continue;
    final n = (span * 8).ceil().clamp(4, 64);
    for (var k = 1; k < n; k++) {
      final beat = a.beat + span * k / n;
      out.add((beat, autoSegment(a, b, beat, warp), 0));
    }
  }
  return out;
}
