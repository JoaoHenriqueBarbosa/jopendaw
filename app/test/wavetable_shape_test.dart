// O desenho das tabelas do wavetable (`wavetable_shape.dart`), que espelha as somas de harmônicos do
// motor (`engine/src/wavetable.rs`). As propriedades conferidas aqui são as mesmas que os testes do
// motor conferem nas tabelas de verdade.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:jopendaw_app/daw/wavetable_shape.dart';

/// Amplitude do harmônico [h] de um ciclo.
double bin(List<double> x, int h) {
  var re = 0.0, im = 0.0;
  for (var i = 0; i < x.length; i++) {
    final w = 2 * math.pi * h * i / x.length;
    re += x[i] * math.cos(w);
    im += x[i] * math.sin(w);
  }
  return 2 * math.sqrt(re * re + im * im) / x.length;
}

double peak(List<double> x) => x.fold(0.0, (m, v) => math.max(m, v.abs()));

void main() {
  const n = 512;

  test('8 tabelas em cada uma das 3 séries, com nome', () {
    expect(wavetableTableNames.length, wavetableSeriesNames.length);
    for (final names in wavetableTableNames) {
      expect(names.length, wavetableTables);
      expect(names.toSet().length, wavetableTables);
    }
  });

  test('senoide pura, triângulo em 1/h², serra em 1/h, quadrada só com ímpares', () {
    final sine = wavetableCycle(0, 0, n);
    expect(bin(sine, 1), greaterThan(0.6));
    expect(bin(sine, 2) + bin(sine, 3), lessThan(1e-3));
    final tri = wavetableCycle(0, 1, n);
    expect(bin(tri, 2), lessThan(1e-3));
    expect(bin(tri, 3) / bin(tri, 1), closeTo(1 / 9, 0.01));
    final saw = wavetableCycle(0, 2, n);
    expect(bin(saw, 2) / bin(saw, 1), closeTo(0.5, 0.01));
    expect(bin(saw, 4) / bin(saw, 1), closeTo(0.25, 0.01));
    final square = wavetableCycle(0, 3, n);
    expect(bin(square, 2), lessThan(1e-3));
    expect(bin(square, 3) / bin(square, 1), closeTo(1 / 3, 0.01));
  });

  test('os pulsos ficam mais estreitos, de 50% a 6%', () {
    double duty(List<double> t) => t.where((v) => v > 0.5 * peak(t)).length / t.length;
    final d = [for (var i = 3; i < 8; i++) duty(wavetableCycle(0, i, n))];
    for (var i = 1; i < d.length; i++) {
      expect(d[i], lessThan(d[i - 1]));
    }
    expect(d.first, closeTo(0.5, 0.03));
    expect(d.last, lessThan(0.1));
  });

  test('cada vogal tem o pico do primeiro formante onde a tabela diz (150 Hz por harmônico)', () {
    for (final (table, f1) in [(0, 800.0), (1, 400.0), (2, 300.0), (3, 450.0), (4, 320.0)]) {
      final t = wavetableCycle(1, table, 1024);
      var best = 1;
      for (var h = 1; h <= 40; h++) {
        if (bin(t, h) > bin(t, best)) best = h;
      }
      expect((150.0 * best - f1).abs(), lessThanOrEqualTo(160), reason: 'vogal ${wavetableTableNames[1][table]}');
    }
  });

  test('digital: ímpares só têm ímpares, primos só têm primos', () {
    final odd = wavetableCycle(2, 0, 1024);
    expect(bin(odd, 2), lessThan(1e-3));
    expect(bin(odd, 3), greaterThan(0.05));
    final primes = wavetableCycle(2, 4, 1024);
    expect(bin(primes, 4) + bin(primes, 6) + bin(primes, 9), lessThan(1e-3));
    expect(bin(primes, 7), greaterThan(0.02));
  });

  test('todas as tabelas: finitas, sem DC, pico até 1,65 e volume parecido', () {
    for (var s = 0; s < 3; s++) {
      for (var t = 0; t < 8; t++) {
        final c = wavetableCycle(s, t, n);
        expect(c.every((v) => v.isFinite), isTrue);
        expect((c.reduce((a, b) => a + b) / n).abs(), lessThan(1e-2), reason: '$s/$t');
        expect(peak(c), inInclusiveRange(0.3, 1.7), reason: '$s/$t');
        final rms = math.sqrt(c.fold(0.0, (a, v) => a + v * v) / n);
        expect(rms, inInclusiveRange(0.1, 0.55), reason: '$s/$t');
      }
    }
  });

  test('a posição mistura as vizinhas e é contínua', () {
    final a = wavetableCycle(0, 2, n), b = wavetableCycle(0, 3, n);
    final mid = wavetableShape(0, 2.5 / 7, n);
    for (var i = 0; i < n; i += 37) {
      expect(mid[i], closeTo((a[i] + b[i]) / 2, 1e-9));
    }
    // nas pontas, a tabela pura
    for (final (pos, table) in [(0.0, 0), (1.0, 7)]) {
      final shape = wavetableShape(0, pos, n), pure = wavetableCycle(0, table, n);
      for (var i = 0; i < n; i++) {
        expect(shape[i], closeTo(pure[i], 1e-9));
      }
    }
    // passos pequenos nunca dão salto
    var prev = wavetableShape(2, 0, n);
    for (var i = 1; i <= 70; i++) {
      final cur = wavetableShape(2, i / 70, n);
      final d = [for (var k = 0; k < n; k++) (cur[k] - prev[k]).abs()].reduce(math.max);
      expect(d, lessThan(0.5), reason: 'passo $i');
      prev = cur;
    }
  });

  test('o rótulo diz as tabelas em jogo', () {
    expect(wavetableLabel(0, 0), 'Senoide');
    expect(wavetableLabel(0, 1), 'Pulso 6%');
    expect(wavetableLabel(0, 2.5 / 7), 'Serra 50% + Quadrada 50%');
    expect(wavetableLabel(1, 1 / 7), 'E');
  });
}
