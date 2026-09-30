import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jopendaw_app/audio/engine_types.dart';
import 'package:jopendaw_app/daw/loudness.dart';

const rate = 48000.0;

double dbfs(double db) => math.pow(10, db / 20).toDouble();

Float32List sine(double hz, double amp, double secs, {double sampleRate = rate}) {
  final n = (secs * sampleRate).round();
  return Float32List.fromList([for (var i = 0; i < n; i++) amp * math.sin(2 * math.pi * hz * i / sampleRate)]);
}

Float32List cat(List<Float32List> parts) => Float32List.fromList([for (final p in parts) ...p]);

void main() {
  group('medição (BS.1770-4)', () {
    test('seno estéreo em fase mede o próprio nível: −20 dBFS de pico dão −20 LUFS', () async {
      final s = sine(1000, dbfs(-20), 5);
      final m = await measureLoudness([s, s], rate);
      expect(m.integrated, closeTo(-20, 0.1));
      expect(m.truePeak, closeTo(-20, 0.1));
      expect(m.samplePeak, closeTo(-20, 0.01));
      expect(m.hasLoudness && m.hasPeak, isTrue);
    });

    test('canal único mede 3 dB abaixo do mesmo sinal nos dois', () async {
      final s = sine(1000, dbfs(-20), 5);
      final mono = await measureLoudness([s], rate);
      final dual = await measureLoudness([s, s], rate);
      expect(mono.integrated, closeTo(-23.01, 0.1));
      expect(dual.integrated - mono.integrated, closeTo(3.01, 0.02));
      // os canais além dos dois primeiros não contam
      final many = await measureLoudness([s, s, s, s], rate);
      expect(many.integrated, closeTo(dual.integrated, 1e-9));
    });

    test('a ponderação K vale em outras taxas', () async {
      for (final r in [44100.0, 48000.0, 96000.0, 192000.0]) {
        final s = sine(1000, dbfs(-23), 4, sampleRate: r);
        final m = await measureLoudness([s, s], r);
        expect(m.integrated, closeTo(-23, 0.15), reason: '$r Hz');
      }
    });

    test('a ponderação K muda com a frequência (passa-altas e prateleira)', () async {
      Future<double> at(double hz) async {
        final s = sine(hz, dbfs(-20), 4);
        return (await measureLoudness([s, s], rate)).integrated;
      }

      final l1k = await at(1000), l100 = await at(100), l10k = await at(10000), l30 = await at(30);
      expect(l10k - l1k, inInclusiveRange(3.0, 4.6));
      expect(l1k - l100, inInclusiveRange(1.5, 2.2));
      expect(l1k - l30, greaterThan(2));
    });

    test('silêncio total, vazio e trecho curto: sem loudness, sem NaN', () async {
      final z = Float32List(48000 * 5);
      final m = await measureLoudness([z, z], rate);
      expect(m.integrated, kLoudnessNone);
      expect(m.truePeak, kLoudnessNone);
      expect(m.samplePeak, kLoudnessNone);
      expect(m.hasLoudness || m.hasPeak, isFalse);

      final none = await measureLoudness([], rate);
      expect(none.integrated, kLoudnessNone);
      final empty = await measureLoudness([Float32List(0), Float32List(0)], rate);
      expect(empty.integrated, kLoudnessNone);

      // 399 ms: nenhuma janela fecha, mas o true peak sai
      final short = sine(1000, 0.5, 0.399);
      final s = await measureLoudness([short, short], rate);
      expect(s.integrated, kLoudnessNone);
      expect(s.truePeak, closeTo(-6.02, 0.2));
      // 400 ms já dão o integrado
      final ok = sine(1000, dbfs(-20), 0.4);
      expect((await measureLoudness([ok, ok], rate)).integrated, closeTo(-20, 0.3));
      // uma amostra só
      final one = await measureLoudness([
        Float32List.fromList([0.5]),
        Float32List.fromList([0.5]),
      ], rate);
      expect(one.integrated, kLoudnessNone);
      expect(one.truePeak, closeTo(-6.02, 0.1));
    });

    test('taxa inválida e amostras não finitas nunca dão NaN', () async {
      final s = sine(1000, dbfs(-20), 3);
      for (var i = 0; i < s.length; i += 97) {
        s[i] = [double.nan, double.infinity, double.negativeInfinity][i % 3];
      }
      final m = await measureLoudness([s, s], rate);
      for (final v in [m.integrated, m.truePeak, m.samplePeak]) {
        expect(v.isFinite, isTrue);
      }
      expect(m.integrated, greaterThan(-40));
      for (final bad in [0.0, -1.0, double.nan, double.infinity]) {
        final r = await measureLoudness([sine(1000, 0.1, 1), sine(1000, 0.1, 1)], bad);
        expect(r.integrated, kLoudnessNone);
      }
    });

    test('gate absoluto: o que está abaixo de −70 LUFS não entra', () async {
      final s = cat([sine(1000, dbfs(-20), 10), sine(1000, dbfs(-80), 20)]);
      expect((await measureLoudness([s, s], rate)).integrated, closeTo(-20, 0.15));
      // tudo abaixo do gate: sem loudness
      final quiet = sine(1000, dbfs(-85), 5);
      expect((await measureLoudness([quiet, quiet], rate)).integrated, kLoudnessNone);
    });

    test('gate relativo: o fundo 20 LU abaixo sai, o 9 LU abaixo entra', () async {
      final low = cat([sine(1000, dbfs(-20), 10), sine(1000, dbfs(-40), 10)]);
      expect((await measureLoudness([low, low], rate)).integrated, closeTo(-20, 0.15));
      final near = cat([sine(1000, dbfs(-20), 10), sine(1000, dbfs(-29), 10)]);
      final mean = 10 * math.log((1 + math.pow(10, -0.9)) / 2) / math.ln10 - 20;
      expect((await measureLoudness([near, near], rate)).integrated, closeTo(mean, 0.2));
    });

    test('rajadas separadas por silêncio: só as rajadas contam (com as bordas das janelas)', () async {
      final burst = sine(1000, dbfs(-18), 1);
      final gap = Float32List(48000 * 3);
      final s = cat([
        for (var i = 0; i < 6; i++) ...[burst, gap],
      ]);
      final m = await measureLoudness([s, s], rate);
      // 7 janelas cheias e 6 parciais (1/4, 1/2 e 3/4 de cada lado): média −1,14 dB abaixo
      expect(m.integrated, closeTo(-18 + 10 * math.log(10 / 13) / math.ln10, 0.2));
    });

    test('ruído: mede algo coerente com a energia', () async {
      final rng = math.Random(7);
      final n = Float32List.fromList([for (var i = 0; i < 48000 * 6; i++) (rng.nextDouble() * 2 - 1) * 0.3]);
      final m = await measureLoudness([n, n], rate);
      var sum = 0.0;
      for (final v in n) {
        sum += v * v;
      }
      final flat = 10 * math.log(sum / n.length) / math.ln10 + 3.01 - 0.691;
      expect(m.integrated - flat, inInclusiveRange(3.0, 4.2), reason: 'ganho da prateleira sobre ruído branco');
      expect(m.truePeak, greaterThanOrEqualTo(m.samplePeak - 1e-9));
    });

    test('true peak pega o pico entre amostras (o do intervalo de fs/4 a 45°)', () async {
      final a = math.sqrt1_2;
      final s = Float32List.fromList([
        for (var i = 0; i < 48000; i++) [a, a, -a, -a][i % 4],
      ]);
      final m = await measureLoudness([s, s], rate);
      expect(m.samplePeak, closeTo(-3.01, 0.05));
      expect(m.truePeak, closeTo(0, 0.25));
      expect(m.truePeak, greaterThan(m.samplePeak + 2));
    });

    test('true peak: DC com rampa e seno de amplitude 1 ficam onde devem', () async {
      final dc = Float32List.fromList([for (var i = 0; i < 14400; i++) 0.5 * math.pow(math.min(1.0, math.min(i, 14399 - i) / 4800), 2).toDouble()]);
      expect((await measureLoudness([dc, dc], rate)).truePeak, closeTo(-6.02, 0.02));
      final s = sine(1000, 1, 1);
      expect((await measureLoudness([s, s], rate)).truePeak, closeTo(0, 0.1));
    });

    test('progresso, cancelamento e o laço de eventos', () async {
      final s = sine(1000, dbfs(-20), 6);
      final seen = <double>[];
      final m = await measureLoudness([s, s], rate, onProgress: seen.add);
      expect(seen.last, 1);
      expect(seen.length, greaterThan(3));
      expect(seen, orderedEquals([...seen]..sort()));
      expect(m.integrated, closeTo(-20, 0.1));
      // cancelar no meio devolve a medida parcial sem falhar
      var calls = 0;
      final part = await measureLoudness([s, s], rate, isCanceled: () => ++calls > 2);
      expect(part.integrated.isFinite, isTrue);
    });
  });

  group('ganho até o alvo', () {
    test('sobe até o alvo quando o teto deixa', () {
      final p = planNormalization(measuredLufs: -20, measuredTruePeak: -8, targetLufs: -14)!;
      expect(p.wantedDb, closeTo(6, 1e-9));
      expect(p.appliedDb, closeTo(6, 1e-9));
      expect(p.limitedByCeiling, isFalse);
      expect(p.resultLufs, closeTo(-14, 1e-9));
      expect(p.resultTruePeak, closeTo(-2, 1e-9));
      expect(p.gain, closeTo(1.9953, 1e-3));
    });

    test('o teto de true peak segura o ganho e o resultado fica abaixo do alvo', () {
      final p = planNormalization(measuredLufs: -20, measuredTruePeak: -4, targetLufs: -14)!;
      expect(p.wantedDb, 6);
      expect(p.appliedDb, closeTo(3, 1e-9), reason: 'de −4 dBTP até o teto de −1');
      expect(p.limitedByCeiling, isTrue);
      expect(p.resultLufs, closeTo(-17, 1e-9));
      expect(p.resultTruePeak, closeTo(-1, 1e-9));
    });

    test('descer nunca esbarra no teto; alvo igual ao medido não faz nada', () {
      final down = planNormalization(measuredLufs: -8, measuredTruePeak: -0.2, targetLufs: -14)!;
      expect(down.appliedDb, closeTo(-6, 1e-9));
      expect(down.limitedByCeiling, isFalse);
      expect(down.resultTruePeak, closeTo(-6.2, 1e-9));
      final same = planNormalization(measuredLufs: -14, measuredTruePeak: -3, targetLufs: -14)!;
      expect(same.appliedDb, 0);
      expect(same.gain, 1);
    });

    test('teto personalizado e pico já acima do teto (ganho negativo para caber)', () {
      final c = planNormalization(measuredLufs: -20, measuredTruePeak: -8, targetLufs: -14, ceilingDb: -3)!;
      expect(c.appliedDb, closeTo(5, 1e-9));
      expect(c.limitedByCeiling, isTrue);
      // o áudio já estoura o teto: mesmo querendo subir, o ganho vira uma descida
      final over = planNormalization(measuredLufs: -20, measuredTruePeak: 1, targetLufs: -14)!;
      expect(over.appliedDb, closeTo(-2, 1e-9));
      expect(over.limitedByCeiling, isTrue);
    });

    test('o ganho tem teto de ±40 dB', () {
      final quiet = planNormalization(measuredLufs: -69, measuredTruePeak: -80, targetLufs: 0)!;
      expect(quiet.wantedDb, 40);
      expect(quiet.appliedDb, 40);
      final loud = planNormalization(measuredLufs: 0, measuredTruePeak: -80, targetLufs: -60)!;
      expect(loud.appliedDb, -40);
    });

    test('sem loudness medido (ou entrada inválida): nada a planejar', () {
      expect(planNormalization(measuredLufs: kLoudnessNone, measuredTruePeak: -3, targetLufs: -14), isNull);
      expect(planNormalization(measuredLufs: double.nan, measuredTruePeak: -3, targetLufs: -14), isNull);
      expect(planNormalization(measuredLufs: -20, measuredTruePeak: -3, targetLufs: double.infinity), isNull);
      expect(planNormalization(measuredLufs: -20, measuredTruePeak: -3, targetLufs: -14, ceilingDb: double.nan), isNull);
      // true peak não medido: sem teto a respeitar, só o ganho
      final p = planNormalization(measuredLufs: -20, measuredTruePeak: kLoudnessNone, targetLufs: -14)!;
      expect(p.appliedDb, 6);
      expect(p.resultTruePeak, kLoudnessNone);
    });

    test('alvos prontos e limites da interface', () {
      expect([for (final t in LoudnessTarget.values) t.lufs], [-14, -16, -23, -14]);
      expect(LoudnessTarget.broadcast.label, 'Broadcast');
      expect(kDefaultCeiling, -1);
      for (final t in LoudnessTarget.values) {
        expect(t.lufs, inInclusiveRange(kMinTargetLufs, kMaxTargetLufs));
      }
      expect(kMinCeiling, lessThan(kMaxCeiling));
    });
  });

  group('textos', () {
    test('formatação com vírgula, sinal de menos e "—" sem medida', () {
      expect(formatLufs(-14.24), '−14,2');
      expect(formatLufs(3.06), '3,1');
      expect(formatLufs(-0.01), '0,0', reason: 'sem "−0,0"');
      expect(formatLufs(kLoudnessNone), '—');
      expect(formatLufs(double.nan), '—');
      expect(formatDbtp(-1), '−1,0 dBTP');
      expect(formatDbtp(kLoudnessNone), '—');
      expect(formatDb(6), '6,0 dB');
      expect(formatLu(6.54), '6,5 LU');
      expect(formatLu(kLoudnessNone), '—');
    });

    test('o relatório conta o que aconteceu', () {
      const ok = LoudnessReport(
        targetLufs: -14,
        ceilingDb: -1,
        beforeLufs: -20,
        beforeTruePeak: -8,
        appliedDb: 6,
        limitedByCeiling: false,
        afterLufs: -14.02,
        afterTruePeak: -2,
      );
      expect(ok.describe(), 'A mixagem subiu 6,0 dB até o alvo e mediu −14,0 LUFS · −2,0 dBTP.');
      const limited = LoudnessReport(
        targetLufs: -14,
        ceilingDb: -1,
        beforeLufs: -20,
        beforeTruePeak: -4,
        appliedDb: 3,
        limitedByCeiling: true,
        afterLufs: -17,
        afterTruePeak: -1,
      );
      expect(limited.describe(), contains('abaixo dos −14,0 LUFS pedidos'));
      expect(limited.describe(), contains('teto de −1,0 dBTP'));
      const down = LoudnessReport(
        targetLufs: -23,
        ceilingDb: -1,
        beforeLufs: -10,
        beforeTruePeak: -1,
        appliedDb: -13,
        limitedByCeiling: false,
        afterLufs: -23,
        afterTruePeak: -14,
      );
      expect(down.describe(), contains('desceu 13,0 dB'));
      const none = LoudnessReport(
        targetLufs: -14,
        ceilingDb: -1,
        beforeLufs: kLoudnessNone,
        beforeTruePeak: kLoudnessNone,
        appliedDb: 0,
        limitedByCeiling: false,
        afterLufs: kLoudnessNone,
        afterTruePeak: kLoudnessNone,
        unmeasurable: true,
      );
      expect(none.describe(), contains('sem normalizar'));
    });
  });

  group('LoudnessReading', () {
    test('valores inválidos viram "sem medida" e a lista curta completa com "sem medida"', () {
      final r = LoudnessReading.fromList([-14.5, double.nan, double.infinity, -1.2]);
      expect((r.momentary, r.shortTerm, r.integrated, r.truePeak, r.range), (-14.5, -200, -200, -1.2, -200));
      expect(LoudnessReading.fromList([-500, 900]).momentary, -200);
      expect(LoudnessReading.fromList([-500, 900]).shortTerm, 400);
      expect(LoudnessReading.has(-200), isFalse);
      expect(LoudnessReading.has(-30), isTrue);
      expect(LoudnessReading.fromList([1, 2, 3, 4, 5]), LoudnessReading.fromList([1, 2, 3, 4, 5]));
      expect(const LoudnessReading(), isNot(const LoudnessReading(integrated: -14)));
    });
  });
}
