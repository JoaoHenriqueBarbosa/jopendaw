/// As tabelas do wavetable, para o painel desenhar a forma de onda da posição escolhida.
///
/// Espelho de `harmonic` em `engine/src/wavetable.rs`: as tabelas do motor nascem de somas de
/// harmônicos e aqui as mesmas somas (com menos harmônicos, o bastante para o desenho) dão a
/// mesma forma. Mudou uma definição lá, mude aqui; o teste `wavetable_shape_test.dart` confere
/// as propriedades (senoide pura, serra em 1/h, pulso com a largura certa, vogais no formante).
library;

import 'dart:math' as math;

/// Nomes das séries (a ordem dos ids `OSC*_SERIES`).
const wavetableSeriesNames = ['Clássica', 'Vozes', 'Digital'];

/// As 8 tabelas de cada série, na ordem das posições 0..1.
const wavetableTableNames = <List<String>>[
  ['Senoide', 'Triângulo', 'Serra', 'Quadrada', 'Pulso 35%', 'Pulso 22%', 'Pulso 12%', 'Pulso 6%'],
  ['A', 'E', 'I', 'O', 'U', 'Nasal', 'Coral', 'Rosnado'],
  ['Ímpares', 'Vazada', 'Ressonante', 'Fibonacci', 'Primos', 'Sino', 'Granulada', 'Vidro'],
];

const wavetableTables = 8;

/// Coeficientes (cosseno, seno) do harmônico `h` (1..256) de uma tabela.
(double, double) wavetableHarmonic(int series, int table, int h) {
  final hf = h.toDouble();
  final odd = h.isOdd;
  double gauss(double x, double c, double w) => math.exp(-0.5 * ((x - c) / w) * ((x - c) / w));
  (double, double) sine(double b) => (0.0, b);
  const tau = 2 * math.pi;
  switch ((series, table)) {
    case (0, 0):
      return sine(h == 1 ? 1.0 : 0.0);
    case (0, 1):
      return sine(odd ? 8 / (math.pi * math.pi) * ((h ~/ 2).isEven ? 1.0 : -1.0) / (hf * hf) : 0.0);
    case (0, 2):
      return sine(1 / hf);
    case (0, _):
      // pulso de largura d que começa na fase 0
      final d = const [0.5, 0.35, 0.22, 0.12, 0.06][table - 3];
      return (math.sin(tau * hf * d) / (math.pi * hf), (1 - math.cos(tau * hf * d)) / (math.pi * hf));
    case (1, 7):
      return sine(math.pow(hf, -0.55) * (0.6 + 0.4 * math.sin(0.9 * hf).abs()));
    case (1, _):
      const vowels = [
        [(800.0, 120.0, 1.0), (1150.0, 100.0, 0.8), (2800.0, 220.0, 0.3)],
        [(400.0, 90.0, 1.0), (1700.0, 140.0, 0.7), (2600.0, 220.0, 0.4)],
        [(300.0, 70.0, 1.0), (2300.0, 160.0, 0.6), (3100.0, 240.0, 0.4)],
        [(450.0, 90.0, 1.0), (850.0, 100.0, 0.7), (2800.0, 220.0, 0.25)],
        [(320.0, 70.0, 1.0), (750.0, 90.0, 0.55), (2500.0, 220.0, 0.2)],
        [(280.0, 70.0, 1.0), (1100.0, 60.0, 0.6), (2300.0, 120.0, 0.6)],
        [(500.0, 300.0, 1.0), (1500.0, 400.0, 0.6), (2500.0, 500.0, 0.4)],
      ];
      final f = 150.0 * hf;
      var env = 0.02;
      for (final (c, w, g) in vowels[table]) {
        env += g * gauss(f, c, w);
      }
      return sine(env / hf);
    case (2, 0):
      return sine(odd ? math.pow(hf, -0.5).toDouble() : 0.0);
    case (2, 1):
      return sine(h <= 24 ? (odd ? 1.0 : 0.35) * math.pow(hf, -0.6) : 0.0);
    case (2, 2):
      return sine((1 + 6 * gauss(hf, 7, 1.4)) / hf);
    case (2, 3):
      return sine(_isFibonacci(h) ? math.pow(hf, -0.5).toDouble() : 0.0);
    case (2, 4):
      return sine(_isPrime(h) ? math.pow(hf, -0.55).toDouble() : 0.0);
    case (2, 5):
      return sine(const [2, 3, 4, 5, 7, 9, 12, 16, 21, 27, 35, 44].contains(h) ? math.pow(hf, -0.5).toDouble() : 0.0);
    case (2, 6):
      final amp = math.pow(hf, -0.7).toDouble();
      final ph = (0.7 * hf * hf) % tau;
      return (amp * math.cos(ph), amp * math.sin(ph));
    default:
      return sine((h == 1 ? 1.0 : 0.0) + (h >= 2 ? 0.8 * gauss(hf, 13, 2.5) : 0.0));
  }
}

bool _isPrime(int n) {
  if (n < 2) return false;
  for (var d = 2; d * d <= n; d++) {
    if (n % d == 0) return false;
  }
  return true;
}

bool _isFibonacci(int n) {
  var a = 1, b = 2;
  while (b < n) {
    final next = a + b;
    a = b;
    b = next;
  }
  return n == 1 || a == n || b == n;
}

/// Harmônicos usados no desenho (a série inteira do motor vai a 256; acima disso a diferença não
/// aparece em poucas dezenas de pixels).
const _drawHarmonics = 96;

final _cache = <(int, int, int), List<double>>{};

/// Um ciclo de uma tabela em [points] pontos, com o mesmo ganho que o motor aplica (RMS 0,5
/// limitado a pico 1,6), para o volume relativo das tabelas aparecer no gráfico.
List<double> wavetableCycle(int series, int table, int points) => _cache.putIfAbsent((series, table, points), () {
  final out = List<double>.filled(points, 0);
  for (var h = 1; h <= _drawHarmonics; h++) {
    final (a, b) = wavetableHarmonic(series, table, h);
    if (a == 0 && b == 0) continue;
    for (var i = 0; i < points; i++) {
      final w = 2 * math.pi * h * i / points;
      out[i] += a * math.cos(w) + b * math.sin(w);
    }
  }
  var sum = 0.0, peak = 1e-9;
  for (final v in out) {
    sum += v * v;
    peak = math.max(peak, v.abs());
  }
  final rms = math.max(math.sqrt(sum / points), 1e-9);
  final gain = math.min(0.5 / rms, 1.6 / peak);
  return [for (final v in out) v * gain];
});

/// A mistura das duas tabelas vizinhas de [pos] (0..1): o mesmo que o oscilador do motor lê.
List<double> wavetableShape(int series, double pos, int points) {
  final x = pos.clamp(0.0, 1.0) * (wavetableTables - 1);
  final lo = math.min(x.floor(), wavetableTables - 2);
  final mix = x - lo;
  final a = wavetableCycle(series, lo, points), b = wavetableCycle(series, lo + 1, points);
  return [for (var i = 0; i < points; i++) a[i] + (b[i] - a[i]) * mix];
}

/// "Serra", "Serra 60% + Quadrada 40%": as tabelas em jogo na posição.
String wavetableLabel(int series, double pos) {
  final names = wavetableTableNames[series];
  final x = pos.clamp(0.0, 1.0) * (wavetableTables - 1);
  final lo = math.min(x.floor(), wavetableTables - 2);
  final mix = x - lo;
  if (mix < 0.04) return names[lo];
  if (mix > 0.96) return names[lo + 1];
  return '${names[lo]} ${((1 - mix) * 100).round()}% + ${names[lo + 1]} ${(mix * 100).round()}%';
}
