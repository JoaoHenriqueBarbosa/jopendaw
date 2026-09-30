/// Mapa de andamento e mapa de compassos do documento.
///
/// Posições (clipes, notas, automação, marcadores, loop) continuam em BATIDAS; o mapa só diz quanto
/// tempo real cada batida dura. É a mesma conta do motor (`engine/src/tempo.rs`): pontos
/// `{batida, bpm, rampa}` em que o primeiro (batida 0) é o andamento inicial; entre um ponto e o
/// próximo o andamento é constante (salto) ou varia linearmente com a batida (rampa, até o bpm do
/// seguinte), integrado por partes com a forma fechada da rampa. Sem mudanças (um ponto só), as
/// fórmulas são as do andamento único de antes (`beat * 60 / bpm`).
///
/// O mapa de compassos `{compasso, num, den}` (o primeiro no compasso 1) só muda a numeração e as
/// linhas de compasso da régua e o metrônomo: a batida do documento é a semínima, então um compasso
/// `num/den` dura `num·4/den` batidas (6/8 = 3 batidas).
///
/// Cuidado com os inteiros: no dart2js eles têm 32 bits; aqui só há doubles e contagens pequenas.
library;

import 'dart:math' as math;

/// Limites do mapa de andamento e de compassos: o conjunto único que o app, o espelho do servidor
/// (`valid_bpm`: 20 a 999), a importação do `.jopendaw` e o motor (`engine/src/tempo.rs`:
/// `MIN_BPM`, `MAX_BPM`, `MAX_TEMPO_POINTS`, `MAX_METER_POINTS`) usam. Mude tudo junto.
const double minBpm = 20;
const double maxBpm = 999;

/// O mesmo intervalo em inteiros, para o espelho `bpm` do servidor e os campos inteiros.
const int minBpmInt = 20;
const int maxBpmInt = 999;

/// Pontos de andamento e mudanças de compasso aceitos num documento (o resto é ignorado ao ler).
const int maxTempoPoints = 4096;
const int maxMeterChanges = 1024;

/// Mensagens de limite: quem chama põe no aviso da tela em vez de descartar em silêncio.
const String tempoPointsFullMessage = 'O mapa de andamento chegou ao limite de $maxTempoPoints pontos.';
const String meterChangesFullMessage = 'O mapa de compassos chegou ao limite: o compasso inicial mais ${maxMeterChanges - 1} mudanças.';

/// Um ponto do mapa de andamento.
class TempoPoint {
  final double beat;
  final double bpm;

  /// Rampa linear até o ponto seguinte (senão o andamento salta no ponto seguinte). No último ponto
  /// não há para onde rampar.
  final bool ramp;

  const TempoPoint(this.beat, this.bpm, {this.ramp = false});

  TempoPoint copyWith({double? beat, double? bpm, bool? ramp}) => TempoPoint(beat ?? this.beat, bpm ?? this.bpm, ramp: ramp ?? this.ramp);

  factory TempoPoint.fromJson(Map<String, dynamic> j) {
    final r = j['ramp'];
    return TempoPoint((j['beat'] as num).toDouble(), (j['bpm'] as num).toDouble(), ramp: r is bool ? r : (r as num? ?? 0) != 0);
  }

  Map<String, dynamic> toJson() => {'beat': beat, 'bpm': bpm, 'ramp': ramp ? 1 : 0};

  @override
  bool operator ==(Object other) => other is TempoPoint && other.beat == beat && other.bpm == bpm && other.ramp == ramp;

  @override
  int get hashCode => Object.hash(beat, bpm, ramp);

  @override
  String toString() => 'TempoPoint($beat, $bpm${ramp ? ', rampa' : ''})';
}

/// Uma mudança de compasso: a partir do compasso [bar] (1 = o primeiro) vale [numerator]/[denominator].
class MeterChange {
  final int bar;
  final int numerator;
  final int denominator;

  const MeterChange(this.bar, this.numerator, this.denominator);

  factory MeterChange.fromJson(Map<String, dynamic> j) => MeterChange((j['bar'] as num).toInt(), (j['num'] as num).toInt(), (j['den'] as num).toInt());

  Map<String, dynamic> toJson() => {'bar': bar, 'num': numerator, 'den': denominator};

  /// Batidas (semínimas) por tempo do compasso: o passo do metrônomo e das linhas de tempo.
  double get unit => 4 / denominator;

  /// Batidas de um compasso inteiro.
  double get barBeats => numerator * unit;

  @override
  bool operator ==(Object other) => other is MeterChange && other.bar == bar && other.numerator == numerator && other.denominator == denominator;

  @override
  int get hashCode => Object.hash(bar, numerator, denominator);

  @override
  String toString() => 'MeterChange($bar: $numerator/$denominator)';
}

/// Denominadores aceitos (potências de 2 até 32).
const meterDenominators = [1, 2, 4, 8, 16, 32];

double _clampBpm(double v) => v.clamp(minBpm, maxBpm).toDouble();

/// e^x − 1 sem perder precisão perto de 0.
double _expm1(double x) => x.abs() < 1e-5 ? x + x * x / 2 + x * x * x / 6 : math.exp(x) - 1;

bool _flat(double a, double b) => (b - a).abs() <= 1e-9 * a;

/// Ordena e limpa os pontos como o motor: batida negativa vira 0, bpm entre [minBpm] e [maxBpm],
/// não finito é descartado, na mesma batida o último vale, e a batida 0 sempre existe (se faltar,
/// entra com [bpm0]). Devolve `[]` quando sobra só o andamento inicial sem rampa nem nada: o mapa
/// vazio é "sem mudanças".
List<TempoPoint> normalizeTempoPoints(Iterable<TempoPoint> input, double bpm0) {
  final byBeat = <double, TempoPoint>{};
  var order = <double>[];
  for (final p in input) {
    if (!p.beat.isFinite || !p.bpm.isFinite) continue;
    final b = math.max(0.0, p.beat);
    if (!byBeat.containsKey(b)) order.add(b);
    byBeat[b] = TempoPoint(b, _clampBpm(p.bpm), ramp: p.ramp);
  }
  order.sort();
  if (order.length > maxTempoPoints) order = order.sublist(0, maxTempoPoints);
  final pts = [for (final b in order) byBeat[b]!];
  if (pts.isEmpty || pts.first.beat != 0) pts.insert(0, TempoPoint(0, _clampBpm(bpm0)));
  // um ponto só é "sem mapa" (uma rampa sem ponto seguinte não faz nada)
  return pts.length == 1 ? const [] : pts;
}

/// Ordena e limpa as mudanças de compasso: compasso ≥ 1, `num` 1..64, `den` potência de 2 até 32
/// (senão 4), na mesma barra a última vale, e o compasso 1 sempre existe (se faltar, entra com
/// [beatsPerBar]/4). Devolve `[]` quando sobra só o compasso inicial `n/4`.
List<MeterChange> normalizeMeterChanges(Iterable<MeterChange> input, int beatsPerBar) {
  final byBar = <int, MeterChange>{};
  for (final m in input) {
    final bar = math.max(1, m.bar);
    final den = meterDenominators.contains(m.denominator) ? m.denominator : 4;
    byBar[bar] = MeterChange(bar, m.numerator.clamp(1, 64), den);
  }
  final bars = byBar.keys.toList()..sort();
  final list = [for (final b in bars.take(maxMeterChanges)) byBar[b]!];
  if (list.isEmpty || list.first.bar != 1) list.insert(0, MeterChange(1, beatsPerBar.clamp(1, 32), 4));
  return list.length == 1 && list.first.denominator == 4 ? const [] : list;
}

/// A conversão batida ↔ segundos pelo mapa de andamento. Imutável: refazer ao mudar os pontos.
class TempoMap {
  /// Normalizados, ao menos um, o primeiro na batida 0.
  final List<TempoPoint> points;
  final List<double> _secs;

  TempoMap._(this.points, this._secs);

  /// Um andamento só.
  factory TempoMap.constant(double bpm) => TempoMap._([TempoPoint(0, _clampBpm(bpm))], const [0]);

  /// O mapa de [bpm0] com os pontos dados (já normalizados ou não; o primeiro, na batida 0, manda no
  /// andamento inicial: aqui é o próprio [bpm0]). Vazio ou de um ponto: andamento único.
  factory TempoMap(double bpm0, [Iterable<TempoPoint> points = const []]) {
    var pts = normalizeTempoPoints(points, bpm0);
    if (pts.isEmpty) return TempoMap.constant(bpm0);
    pts = [pts.first.copyWith(bpm: _clampBpm(bpm0)), ...pts.skip(1)];
    final secs = List<double>.filled(pts.length, 0);
    for (var i = 1; i < pts.length; i++) {
      secs[i] = secs[i - 1] + _segmentSeconds(pts, i - 1, pts[i].beat - pts[i - 1].beat);
    }
    return TempoMap._(pts, secs);
  }

  bool get isSingle => points.length == 1;

  double get bpm0 => points.first.bpm;

  static double _segmentSeconds(List<TempoPoint> pts, int i, double x) {
    final p = pts[i];
    if (i + 1 < pts.length && p.ramp && !_flat(p.bpm, pts[i + 1].bpm)) {
      final len = pts[i + 1].beat - p.beat;
      final a = p.bpm, b = pts[i + 1].bpm;
      return 60 * len / (b - a) * math.log((a + (b - a) * x / len) / a);
    }
    return x * 60 / p.bpm;
  }

  /// Índice do trecho que contém a batida (o último ponto com batida ≤ [beat]).
  int indexAt(double beat) {
    var lo = 0, hi = points.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (points[mid].beat <= beat) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  /// Segundos desde o começo até a batida.
  double secondsAt(double beat) {
    if (isSingle || beat <= 0) return beat * 60 / points.first.bpm;
    final i = indexAt(beat);
    return _secs[i] + _segmentSeconds(points, i, beat - points[i].beat);
  }

  /// A batida em que caem os segundos (o inverso de [secondsAt]).
  double beatAt(double seconds) {
    if (isSingle || seconds <= 0) return seconds * points.first.bpm / 60;
    var lo = 0, hi = points.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (_secs[mid] <= seconds) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    final p = points[lo];
    final s = seconds - _secs[lo];
    if (lo + 1 < points.length && p.ramp && !_flat(p.bpm, points[lo + 1].bpm)) {
      final len = points[lo + 1].beat - p.beat;
      final a = p.bpm, b = points[lo + 1].bpm;
      final k = (b - a) / (60 * len);
      return p.beat + (len * a * _expm1(k * s) / (b - a)).clamp(0.0, len);
    }
    return p.beat + s * p.bpm / 60;
  }

  /// O andamento em bpm na batida (na rampa, o valor interpolado).
  double bpmAt(double beat) {
    if (isSingle || beat <= 0) return points.first.bpm;
    final i = indexAt(beat);
    final p = points[i];
    if (i + 1 < points.length && p.ramp) {
      final q = points[i + 1];
      return p.bpm + (q.bpm - p.bpm) * (beat - p.beat) / (q.beat - p.beat);
    }
    return p.bpm;
  }

  /// O ponto que começa exatamente na batida (com tolerância), se houver.
  TempoPoint? pointAt(double beat, [double tolerance = 1e-9]) {
    final i = indexAt(beat);
    if ((points[i].beat - beat).abs() <= tolerance) return points[i];
    if (i + 1 < points.length && (points[i + 1].beat - beat).abs() <= tolerance) return points[i + 1];
    return null;
  }
}

/// O mapa de compassos: onde cada compasso começa, em batidas.
class MeterMap {
  /// Normalizadas, ao menos uma, a primeira no compasso 1.
  final List<MeterChange> changes;
  final List<double> _starts;

  MeterMap._(this.changes, this._starts);

  factory MeterMap.constant(int beatsPerBar) => MeterMap._([MeterChange(1, beatsPerBar.clamp(1, 32), 4)], const [0]);

  /// O mapa com as mudanças dadas; vazio: um compasso `beatsPerBar/4` o tempo todo.
  factory MeterMap(int beatsPerBar, [Iterable<MeterChange> changes = const []]) {
    final list = normalizeMeterChanges(changes, beatsPerBar);
    if (list.isEmpty) return MeterMap.constant(beatsPerBar);
    final starts = List<double>.filled(list.length, 0);
    for (var i = 1; i < list.length; i++) {
      starts[i] = starts[i - 1] + (list[i].bar - list[i - 1].bar) * list[i - 1].barBeats;
    }
    return MeterMap._(list, starts);
  }

  bool get isSingle => changes.length == 1 && changes.first.denominator == 4;

  MeterChange get first => changes.first;

  int _indexOfBar(int bar) {
    var lo = 0, hi = changes.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (changes[mid].bar <= bar) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  /// A mudança que vale no compasso (1 = o primeiro; antes do 1, a primeira).
  MeterChange changeAt(int bar) => changes[_indexOfBar(bar)];

  /// Batida em que começa o compasso [bar].
  double barStart(int bar) {
    final i = _indexOfBar(bar);
    return _starts[i] + (bar - changes[i].bar) * changes[i].barBeats;
  }

  /// Batidas do compasso [bar].
  double barBeats(int bar) => changeAt(bar).barBeats;

  /// O compasso (1 = o primeiro) que contém a batida e a distância dela ao começo dele. Antes da
  /// batida 0 vale 1.
  (int, double) barOf(double beat) {
    if (beat <= 0) return (1, 0);
    var lo = 0, hi = changes.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (_starts[mid] <= beat) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    final c = changes[lo];
    final n = ((beat - _starts[lo]) / c.barBeats + 1e-12).floor();
    return (c.bar + n, beat - _starts[lo] - n * c.barBeats);
  }

  /// Começo do compasso mais próximo da batida (para o encaixe "Compasso").
  double nearestBarStart(double beat) {
    final (bar, into) = barOf(beat);
    final len = barBeats(bar);
    return into * 2 >= len ? barStart(bar + 1) : barStart(bar);
  }

  /// Batidas do compasso que contém a batida.
  double barBeatsAt(double beat) => barBeats(barOf(beat).$1);

  /// Começo do compasso que contém a batida (uma batida no começo exato de um compasso fica nele).
  double floorBarStart(double beat) => barStart(barOf(beat + 1e-9).$1);

  /// Começo do primeiro compasso que não termina antes da batida: a própria batida se ela cai no
  /// começo de um compasso, senão o começo do seguinte.
  double ceilBarStart(double beat) {
    final (bar, into) = barOf(beat);
    return into <= 1e-9 ? barStart(bar) : barStart(bar + 1);
  }

  /// Compassos inteiros e batidas que sobram em [length] batidas a partir de [from]. Contado pelo
  /// mapa quando [from] cai no começo de um compasso; senão, pelo compasso de [from].
  (int, double) spanBars(double from, double length) {
    final (b0, into0) = barOf(math.max(0.0, from));
    if (into0 <= 1e-9) {
      final (b1, into1) = barOf(math.max(0.0, from) + length);
      if (into1 >= barBeats(b1) - 1e-9) return (b1 + 1 - b0, 0);
      return (b1 - b0, into1 <= 1e-9 ? 0 : into1);
    }
    final len = barBeats(b0);
    final bars = (length / len + 1e-9).floor();
    return (bars, length - bars * len);
  }
}

/// As chamadas do motor que levam o mapa de andamento e o de compassos: `tempo_clear` e um
/// `tempo_point` por ponto, `meter_clear` e um `meter_point` por mudança. Vazio quando os dois
/// mapas são simples (o `tempo` que vem antes já carrega o andamento e o compasso únicos).
List<List<Object>> tempoMapCalls(TempoMap tempo, MeterMap meter) => [
  if (!tempo.isSingle) ...[
    ['tempo_clear'],
    for (final p in tempo.points) ['tempo_point', p.beat, p.bpm, p.ramp ? 1 : 0],
  ],
  if (!meter.isSingle) ...[
    ['meter_clear'],
    for (final m in meter.changes) ['meter_point', m.bar, m.numerator, m.denominator],
  ],
];
