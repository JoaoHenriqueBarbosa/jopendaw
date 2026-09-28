import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:jopendaw_app/daw/automation_math.dart';
import 'package:jopendaw_app/daw/instruments.dart';
import 'package:jopendaw_app/daw/model.dart';

void main() {
  test('volume: meia rampa fica no meio do fader, não no meio do ganho linear', () {
    const warp = (toNorm: gainToFader, fromNorm: faderToGain);
    final pts = [AutoPoint(beat: 0, value: 1), AutoPoint(beat: 4, value: 0)];
    final mid = autoValueAt(pts, 2, 0, warp: warp);
    expect(gainToFader(mid), closeTo(gainToFader(1) / 2, 1e-9));
    // em ganho linear o meio seria 0,5 (−6 dB); na curva do fader é bem mais baixo
    expect(mid, lessThan(0.2));
  });

  test('frequência: meia varredura de 20 Hz a 20 kHz cai na média geométrica', () {
    const spec = ParamSpec(1, 'Corte', 'Filtro', 20, 20000, 1000, unit: 'Hz', curve: Curve.log);
    final warp = (toNorm: spec.toNorm, fromNorm: spec.fromNorm);
    final pts = [AutoPoint(beat: 0, value: 20), AutoPoint(beat: 8, value: 20000)];
    expect(autoValueAt(pts, 4, 0, warp: warp), closeTo(math.sqrt(20 * 20000), 1));
  });

  test('pontos para o motor: sem escala vão os próprios; com escala, 1/8 de batida por segmento', () {
    final pts = [AutoPoint(beat: 0, value: 0, curve: 0.3), AutoPoint(beat: 1, value: 1)];
    expect(autoEnginePoints(pts, null), [(0.0, 0.0, 0.3), (1.0, 1.0, 0.0)]);
    final dense = autoEnginePoints(pts, (toNorm: (v) => v, fromNorm: (n) => n));
    expect(dense, hasLength(9));
    expect(dense.first.$1, 0);
    expect(dense.last, (1.0, 1.0, 0.0));
  });
}
