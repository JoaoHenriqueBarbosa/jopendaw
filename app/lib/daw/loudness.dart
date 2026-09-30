/// Loudness na exportação: medida do áudio já renderizado (BS.1770-4 / EBU R128, o mesmo cálculo do
/// motor em `engine/src/loudness.rs`, aqui em Dart puro para funcionar igual na web e no Android
/// sem passar nada novo pelas pontes) e a conta do ganho até o alvo respeitando o teto de true
/// peak. Sem Flutter: só matemática, testável sozinha.
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// "Sem medida" (o mesmo −200 do motor).
const double kLoudnessNone = -200;

/// Alvos de loudness integrado da exportação.
enum LoudnessTarget {
  /// −14 LUFS: Spotify, YouTube, Tidal e a maioria dos serviços de streaming.
  streaming('Streaming', -14, 'Spotify, YouTube, Apple Music'),

  /// −16 LUFS: podcasts e vídeo para celular.
  podcast('Podcast', -16, 'podcasts e vídeos'),

  /// −23 LUFS: EBU R128, radiodifusão europeia e TV.
  broadcast('Broadcast', -23, 'EBU R128, rádio e TV'),

  /// Qualquer valor escolhido pela pessoa.
  custom('Personalizado', -14, 'o valor que você escolher');

  final String label;
  final double lufs;
  final String hint;
  const LoudnessTarget(this.label, this.lufs, this.hint);
}

/// Limites do que a interface aceita: alvo de −40 a 0 LUFS, teto de −10 a 0 dBTP.
const double kMinTargetLufs = -40;
const double kMaxTargetLufs = 0;
const double kMinCeiling = -10;
const double kMaxCeiling = 0;

/// O teto de true peak padrão (−1 dBTP, o que o streaming pede para não estourar no codec).
const double kDefaultCeiling = -1;

/// O que a medição achou.
class LoudnessMeasure {
  /// Integrado com os dois gates (LUFS); [kLoudnessNone] se não deu (menos de 400 ms, silêncio ou
  /// tudo abaixo de −70 LUFS).
  final double integrated;

  /// True peak (dBTP) e pico de amostra (dBFS); [kLoudnessNone] em silêncio total.
  final double truePeak;
  final double samplePeak;

  const LoudnessMeasure({required this.integrated, required this.truePeak, required this.samplePeak});

  bool get hasLoudness => integrated > -150;
  bool get hasPeak => truePeak > -150;

  @override
  String toString() => 'LoudnessMeasure($integrated LUFS, $truePeak dBTP, pico $samplePeak dBFS)';
}

// ------------------------------------------------------------------ K-weighting

class _Biquad {
  final double b0, b1, b2, a1, a2;
  double z1 = 0, z2 = 0;
  _Biquad(this.b0, this.b1, this.b2, this.a1, this.a2);

  double run(double x) {
    final y = b0 * x + z1;
    z1 = b1 * x - a1 * y + z2;
    z2 = b2 * x - a2 * y;
    return y;
  }
}

/// Prateleira de agudos e passa-altas da BS.1770 para a taxa [rate] (os coeficientes da norma
/// valem só para 48 kHz; estes vêm dos mesmos protótipos analógicos).
List<_Biquad> _kWeighting(double rate) {
  const f0 = 1681.974450955533, gain = 3.999843853973347, q = 0.7071752369554196;
  var k = math.tan(math.pi * f0 / rate);
  final vh = math.pow(10, gain / 20).toDouble();
  final vb = math.pow(vh, 0.4996667741545416).toDouble();
  var a0 = 1 + k / q + k * k;
  final shelf = _Biquad((vh + vb * k / q + k * k) / a0, 2 * (k * k - vh) / a0, (vh - vb * k / q + k * k) / a0, 2 * (k * k - 1) / a0, (1 - k / q + k * k) / a0);
  const g0 = 38.13547087602444, gq = 0.5003270373238773;
  k = math.tan(math.pi * g0 / rate);
  a0 = 1 + k / gq + k * k;
  final high = _Biquad(1, -2, 1, 2 * (k * k - 1) / a0, (1 - k / gq + k * k) / a0);
  return [shelf, high];
}

// ------------------------------------------------------------------ true peak

const int _half = 8;
const int _taps = 2 * _half;
const double _kaiserBeta = 7;

double _besselI0(double x) {
  var sum = 1.0, term = 1.0;
  final q = x * x / 4;
  for (var k = 1; k < 64; k++) {
    term *= q / (k * k);
    sum += term;
    if (term < sum * 1e-17) break;
  }
  return sum;
}

/// Coeficientes das fases 1 a 3 do interpolador 4× (a fase 0 é a própria amostra), cada uma
/// somando 1. A mesma janela de Kaiser do motor.
List<Float64List> _interpolator() {
  final norm = _besselI0(_kaiserBeta);
  return [
    for (var p = 1; p < 4; p++)
      () {
        final frac = p / 4;
        final taps = Float64List(_taps);
        var sum = 0.0;
        for (var d = 0; d < _taps; d++) {
          final t = (_half - d) - frac;
          final sinc = t == 0 ? 1.0 : math.sin(math.pi * t) / (math.pi * t);
          final r = t / _half;
          final window = r.abs() < 1 ? _besselI0(_kaiserBeta * math.sqrt(1 - r * r)) / norm : 0.0;
          taps[d] = sinc * window;
          sum += taps[d];
        }
        for (var d = 0; d < _taps; d++) {
          taps[d] /= sum;
        }
        return taps;
      }(),
  ];
}

/// O true peak de um canal: histórico das últimas amostras (a mais nova em 0) e o maior valor
/// absoluto, interpolado ou não, visto até agora.
class _TruePeak {
  final List<Float64List> _coef;
  // a soma dos módulos de cada fase, no pior caso: o teto do que um interpolado pode valer, para
  // pular a conta quando a janela é baixa demais para bater o pico já visto
  final double _l1;
  final Float64List _h = Float64List(_taps);
  double peak = 0;

  _TruePeak(this._coef) : _l1 = _coef.map((c) => c.fold<double>(0, (a, b) => a + b.abs())).reduce(math.max);

  void feed(double x) {
    final h = _h;
    for (var d = _taps - 1; d > 0; d--) {
      h[d] = h[d - 1];
    }
    h[0] = x;
    var best = h[_half].abs();
    var window = 0.0;
    for (var d = 0; d < _taps; d++) {
      final a = h[d].abs();
      if (a > window) window = a;
    }
    if (window * _l1 > math.max(peak, best)) {
      for (final phase in _coef) {
        var s = 0.0;
        for (var d = 0; d < _taps; d++) {
          s += phase[d] * h[d];
        }
        if (s.abs() > best) best = s.abs();
      }
    }
    if (best > peak) peak = best;
  }
}

// ------------------------------------------------------------------ medição

/// Mede [channels] (um ou dois canais; só os dois primeiros contam, cada um com peso 1) na taxa
/// [rate]. Como a BS.1770 soma só os canais que existem, um canal único mede 3 dB abaixo do mesmo
/// sinal nos dois. Menos de 400 ms de áudio não fecha janela: o integrado sai [kLoudnessNone]
/// (o true peak sai). Amostras não finitas contam como silêncio. Devolve o controle ao laço de
/// eventos a cada ~0,5 s de áudio (para a tela não travar num arquivo longo) e avisa o andamento
/// (0..1) em [onProgress]; [isCanceled] interrompe (devolve o que mediu até ali).
Future<LoudnessMeasure> measureLoudness(
  List<Float32List> channels,
  double rate, {
  void Function(double progress)? onProgress,
  bool Function()? isCanceled,
}) async {
  final chans = channels.take(2).toList();
  if (chans.isEmpty || !rate.isFinite || rate < 1000) {
    return const LoudnessMeasure(integrated: kLoudnessNone, truePeak: kLoudnessNone, samplePeak: kLoudnessNone);
  }
  final frames = chans.map((c) => c.length).reduce(math.min);
  final hop = math.max(1, (rate * 0.1).round());
  final kw = [for (final _ in chans) _kWeighting(rate)];
  final coef = _interpolator();
  final peaks = [for (final _ in chans) _TruePeak(coef)];

  final energies = <double>[]; // energia de cada bloco de 100 ms
  var acc = 0.0, filled = 0;
  var samplePeak = 0.0;

  final step = math.max(hop, (rate * 0.5).round());
  for (var i = 0; i < frames; i++) {
    for (var c = 0; c < chans.length; c++) {
      var x = chans[c][i].toDouble();
      if (!x.isFinite) x = 0;
      final f = kw[c];
      final y = f[1].run(f[0].run(x));
      acc += y * y;
      final ax = x.abs();
      if (ax > samplePeak) samplePeak = ax;
      peaks[c].feed(x);
    }
    if (++filled == hop) {
      energies.add(acc / hop);
      acc = 0;
      filled = 0;
    }
    if (i % step == step - 1) {
      onProgress?.call(i / frames);
      await Future<void>.delayed(Duration.zero);
      if (isCanceled?.call() ?? false) break;
    }
  }
  // o fim do sinal para o interpolador: como se seguisse em silêncio
  for (var k = 0; k < _half; k++) {
    for (final p in peaks) {
      p.feed(0);
    }
  }
  onProgress?.call(1);
  final truePeak = peaks.map((p) => p.peak).reduce(math.max);
  return LoudnessMeasure(integrated: _integrated(energies), truePeak: _dbOf(truePeak), samplePeak: _dbOf(samplePeak));
}

double _dbOf(double linear) => linear > 0 && linear.isFinite ? math.max(kLoudnessNone, 20 * math.log(linear) / math.ln10) : kLoudnessNone;

double _lufs(double energy) => energy > 0 && energy.isFinite ? math.max(kLoudnessNone, -0.691 + 10 * math.log(energy) / math.ln10) : kLoudnessNone;

/// Integrado com os gates: janelas de 400 ms a cada 100 ms, gate absoluto de −70 LUFS e relativo de
/// 10 LU abaixo da média do que passou.
double _integrated(List<double> hops) {
  if (hops.length < 4) return kLoudnessNone;
  final blocks = <double>[];
  var run = hops[0] + hops[1] + hops[2] + hops[3];
  blocks.add(run / 4);
  for (var i = 4; i < hops.length; i++) {
    run += hops[i] - hops[i - 4];
    blocks.add(math.max(0.0, run) / 4);
  }
  final absolute = [
    for (final e in blocks)
      if (_lufs(e) > -70) e,
  ];
  if (absolute.isEmpty) return kLoudnessNone;
  final gate = _lufs(absolute.fold<double>(0, (a, b) => a + b) / absolute.length) - 10;
  final kept = [
    for (final e in absolute)
      if (_lufs(e) > gate) e,
  ];
  if (kept.isEmpty) return kLoudnessNone;
  return _lufs(kept.fold<double>(0, (a, b) => a + b) / kept.length);
}

// ------------------------------------------------------------------ ganho até o alvo

/// A conta do ganho: o que aplicar e o que vai sobrar.
class NormalizationPlan {
  /// O ganho que levaria ao alvo (dB) e o que de fato vai ser aplicado (dB): o segundo é menor
  /// quando o teto de true peak segura.
  final double wantedDb;
  final double appliedDb;

  /// O teto de true peak foi o que limitou o ganho: o resultado fica abaixo do alvo.
  final bool limitedByCeiling;

  /// O loudness e o true peak previstos depois do ganho (a medida de verdade vem do render).
  final double resultLufs;
  final double resultTruePeak;

  const NormalizationPlan({
    required this.wantedDb,
    required this.appliedDb,
    required this.limitedByCeiling,
    required this.resultLufs,
    required this.resultTruePeak,
  });

  double get gain => math.pow(10, appliedDb / 20).toDouble();
}

/// Maior ganho que a normalização aplica, para cima ou para baixo (dB): um arquivo quase mudo não
/// vira um estouro de ruído.
const double kMaxNormalizeGain = 40;

/// Calcula o ganho para levar [measuredLufs] a [targetLufs] sem passar o true peak de [ceilingDb]
/// ([measuredTruePeak], em dBTP, antes do ganho). O ganho é uma constante para o arquivo todo (não
/// há compressor nem limitador nisso): se o teto segura, o resultado fica abaixo do alvo e
/// [NormalizationPlan.limitedByCeiling] avisa. Sem loudness medido (silêncio, trecho curto)
/// devolve null.
NormalizationPlan? planNormalization({
  required double measuredLufs,
  required double measuredTruePeak,
  required double targetLufs,
  double ceilingDb = kDefaultCeiling,
}) {
  if (!measuredLufs.isFinite || measuredLufs <= -150 || !targetLufs.isFinite || !ceilingDb.isFinite) return null;
  final wanted = (targetLufs - measuredLufs).clamp(-kMaxNormalizeGain, kMaxNormalizeGain).toDouble();
  var applied = wanted;
  var limited = false;
  final hasPeak = measuredTruePeak.isFinite && measuredTruePeak > -150;
  if (hasPeak && measuredTruePeak + wanted > ceilingDb + 1e-9) {
    applied = ceilingDb - measuredTruePeak;
    limited = true;
  }
  return NormalizationPlan(
    wantedDb: wanted,
    appliedDb: applied,
    limitedByCeiling: limited,
    resultLufs: measuredLufs + applied,
    resultTruePeak: hasPeak ? measuredTruePeak + applied : kLoudnessNone,
  );
}

/// O que a exportação com normalização de loudness fez, para a janela do resultado contar.
class LoudnessReport {
  /// Alvo pedido, teto de true peak e o que a mixagem media antes de normalizar.
  final double targetLufs;
  final double ceilingDb;
  final double beforeLufs;
  final double beforeTruePeak;

  /// O ganho aplicado (dB; 0 se não deu para medir) e se o teto limitou.
  final double appliedDb;
  final bool limitedByCeiling;

  /// O que o arquivo final mediu de verdade.
  final double afterLufs;
  final double afterTruePeak;

  /// Não foi possível medir o loudness (áudio curto demais, silêncio ou abaixo de −70 LUFS): nada
  /// foi normalizado.
  final bool unmeasurable;

  const LoudnessReport({
    required this.targetLufs,
    required this.ceilingDb,
    required this.beforeLufs,
    required this.beforeTruePeak,
    required this.appliedDb,
    required this.limitedByCeiling,
    required this.afterLufs,
    required this.afterTruePeak,
    this.unmeasurable = false,
  });

  /// A frase para a janela do resultado, em português.
  String describe() {
    if (unmeasurable) {
      return 'Não deu para medir o loudness (o trecho é curto demais, mudo ou muito baixo): a mixagem foi exportada sem normalizar.';
    }
    final after = '${formatLufs(afterLufs)} LUFS · ${formatDbtp(afterTruePeak)}';
    final moved = appliedDb.abs() < 0.05 ? 'já estava no alvo' : '${appliedDb > 0 ? 'subiu' : 'desceu'} ${formatDb(appliedDb.abs())}';
    if (limitedByCeiling) {
      return 'A mixagem $moved e ficou em $after, abaixo dos ${formatLufs(targetLufs)} LUFS pedidos: o teto de ${formatDbtp(ceilingDb)} '
          'não deixou subir mais sem estourar.';
    }
    return appliedDb.abs() < 0.05 ? 'A mixagem já estava no alvo e mediu $after.' : 'A mixagem $moved até o alvo e mediu $after.';
  }
}

bool _hasValue(double v) => v.isFinite && v > -150;

/// "−14,2" (vírgula decimal, sinal de menos de verdade), [digits] casas; "—" sem medida.
String _fmt(double v, int digits) {
  if (!_hasValue(v)) return '—';
  final text = v.abs().toStringAsFixed(digits);
  final zero = double.parse(text) == 0;
  return '${v < 0 && !zero ? '−' : ''}${text.replaceAll('.', ',')}';
}

/// LUFS com uma casa, sem a unidade ("−14,2"); "—" sem medida.
String formatLufs(double v) => _fmt(v, 1);

/// "−1,0 dBTP"; "—" sem medida.
String formatDbtp(double v) => _hasValue(v) ? '${_fmt(v, 1)} dBTP' : '—';

/// "3,2 dB" (ganho); "—" sem medida.
String formatDb(double v) => _hasValue(v) ? '${_fmt(v, 1)} dB' : '—';

/// "6,5 LU" (faixa de loudness); "—" sem medida.
String formatLu(double v) => _hasValue(v) ? '${_fmt(v, 1)} LU' : '—';

/// Multiplica todas as amostras de [channels] por [gain], no lugar.
void scaleChannels(List<Float32List> channels, double gain) {
  for (final c in channels) {
    for (var i = 0; i < c.length; i++) {
      c[i] = c[i] * gain;
    }
  }
}

/// Normaliza o loudness de [channels] (a mixagem renderizada), no lugar: mede, calcula o ganho até
/// [targetLufs] com o teto de true peak de [ceilingDb] ([planNormalization]), aplica e mede de novo
/// para o relatório dizer o que o arquivo tem de verdade. Sem loudness medível (curto demais, mudo,
/// abaixo de −70 LUFS) não mexe em nada e o relatório diz isso ([LoudnessReport.unmeasurable]).
/// [onProgress] (0..1) cobre as duas medidas; [isCanceled] interrompe (o áudio fica como estava se
/// ainda não foi escalado, e nesse caso o relatório é de "não medido").
Future<({LoudnessReport report, double gainDb})> normalizeLoudness(
  List<Float32List> channels,
  double rate, {
  required double targetLufs,
  double ceilingDb = kDefaultCeiling,
  void Function(double progress)? onProgress,
  bool Function()? isCanceled,
}) async {
  LoudnessReport unmeasurable(LoudnessMeasure m) => LoudnessReport(
    targetLufs: targetLufs,
    ceilingDb: ceilingDb,
    beforeLufs: m.integrated,
    beforeTruePeak: m.truePeak,
    appliedDb: 0,
    limitedByCeiling: false,
    afterLufs: m.integrated,
    afterTruePeak: m.truePeak,
    unmeasurable: true,
  );
  final before = await measureLoudness(channels, rate, onProgress: onProgress == null ? null : (p) => onProgress(p / 2), isCanceled: isCanceled);
  final plan = planNormalization(measuredLufs: before.integrated, measuredTruePeak: before.truePeak, targetLufs: targetLufs, ceilingDb: ceilingDb);
  if (plan == null || (isCanceled?.call() ?? false)) return (report: unmeasurable(before), gainDb: 0.0);
  if (plan.appliedDb != 0) scaleChannels(channels, plan.gain);
  final after = await measureLoudness(channels, rate, onProgress: onProgress == null ? null : (p) => onProgress(0.5 + p / 2), isCanceled: isCanceled);
  return (
    report: LoudnessReport(
      targetLufs: targetLufs,
      ceilingDb: ceilingDb,
      beforeLufs: before.integrated,
      beforeTruePeak: before.truePeak,
      appliedDb: plan.appliedDb,
      limitedByCeiling: plan.limitedByCeiling,
      afterLufs: after.integrated,
      afterTruePeak: after.truePeak,
    ),
    gainDb: plan.appliedDb,
  );
}
