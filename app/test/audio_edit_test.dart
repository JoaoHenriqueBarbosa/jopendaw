import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jopendaw_app/daw/audio_edit.dart';
import 'package:jopendaw_app/daw/controller.dart';
import 'package:jopendaw_app/daw/export_options.dart';
import 'package:jopendaw_app/daw/loudness.dart';
import 'package:jopendaw_app/daw/model.dart';
import 'package:jopendaw_app/daw/tempo_map.dart';
import 'package:jopendaw_app/daw/wav.dart';

import 'fake_engine.dart';

const rate = 48000;

Uint8List wav(Float32List x) => encodeWav([x], rate, ExportFormat.wav32f);

/// Uma bateria sintética: uma rajada de ruído com decaimento de 25 ms em cada tempo de [times]
/// (segundos), ataque seco. Os ataques ficam em posições conhecidas ao quadro.
Float32List drums(List<double> times, {double seconds = 3, double amp = 0.8, int seed = 7}) {
  final x = Float32List((seconds * rate).round());
  final r = math.Random(seed);
  for (final t in times) {
    final f0 = (t * rate).round();
    for (var k = 0; k < rate * 0.15 && f0 + k < x.length; k++) {
      x[f0 + k] += (amp * math.exp(-k / (rate * 0.025)) * (r.nextDouble() * 2 - 1)).toDouble();
    }
  }
  return x;
}

Float32List tone(double seconds, {double hz = 1000, double amp = 0.5}) =>
    Float32List.fromList([for (var i = 0; i < (seconds * rate).round(); i++) (amp * math.sin(2 * math.pi * hz * i / rate)).toDouble()]);

/// Rajadas de ruído (amplitude 0,3) nos trechos [bursts] (início, fim em segundos); o resto é zero.
Float32List noiseBursts(List<(double, double)> bursts, double seconds) {
  final x = Float32List((seconds * rate).round());
  final r = math.Random(3);
  for (final (a, b) in bursts) {
    for (var i = (a * rate).round(); i < (b * rate).round() && i < x.length; i++) {
      x[i] = (0.3 * (r.nextDouble() * 2 - 1)).toDouble();
    }
  }
  return x;
}

/// Um controlador com [x] importado e um clipe "c1" na faixa 0.
Future<(DawController, String)> setup(Float32List x, {double start = 0, double offset = 0, double? length, double fadeIn = 0, double fadeOut = 0}) async {
  final c = fakeController(FakeEngine());
  final hash = (await c.importSampleFile('a.wav', wav(x)))!;
  c.edit((d) {
    d.tracks[0].clips.add(
      AudioClip(id: 'c1', sample: hash, start: start, offset: offset, length: length ?? x.length / rate - offset, fadeIn: fadeIn, fadeOut: fadeOut),
    );
  });
  return (c, hash);
}

List<AudioClip> clipsOf(DawController c) => c.doc.tracks[0].clips;

/// O instante (s, na linha do tempo) em que o ataque em [t] (s do áudio) toca depois da edição: a fatia
/// dona do ataque é a que tem o maior começo nominal (offset mais a cabeça do crossfade) até ele.
double onsetOf(DawController c, double t) {
  AudioClip? owner;
  var best = -1.0;
  for (final k in clipsOf(c)) {
    final nominal = k.offset + (k.offset > 0 && k.fadeIn <= 0.0021 ? k.fadeIn : 0);
    if (nominal <= t + 0.0011 && nominal > best) {
      best = nominal;
      owner = k;
    }
  }
  return c.doc.secondsAt(owner!.start) + (t - owner.offset);
}

String docJson(DawController c) => jsonEncode(c.doc.toJson());

/// Toca os clipes como o motor: cada um lê o áudio de `offset` por `length`, com os fades lineares
/// e o ganho, e tudo soma.
Float32List render(DawController c, List<AudioClip> clips, Float32List src, int frames) {
  final out = Float32List(frames);
  for (final k in clips) {
    final n0 = (c.doc.secondsAt(k.start) * rate).round();
    final s0 = (k.offset * rate).round();
    final len = (k.length * rate).round();
    for (var t = 0; t < len; t++) {
      final o = n0 + t, s = s0 + t;
      if (o < 0 || o >= frames || s < 0 || s >= src.length) continue;
      var w = k.gain;
      if (k.fadeIn > 0 && t < k.fadeIn * rate) w *= t / (k.fadeIn * rate);
      if (k.fadeOut > 0 && len - t < k.fadeOut * rate) w *= (len - t) / (k.fadeOut * rate);
      out[o] += (w * src[s]).toDouble();
    }
  }
  return out;
}

double maxDiff(Float32List a, Float32List b) {
  var m = 0.0;
  for (var i = 0; i < a.length; i++) {
    m = math.max(m, (a[i] - b[i]).abs());
  }
  return m;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const hits = [0.3, 0.8, 1.3, 1.8];

  group('cortes', () {
    test('por transientes: cada corte cai a menos de 1 ms do ataque', () async {
      final (c, _) = await setup(drums(hits));
      final t = c.audioEditTarget('c1');
      final cuts = detectCuts(t.range!, t.clip!, c.doc);
      expect(cuts, hasLength(4));
      for (var i = 0; i < 4; i++) {
        expect((cuts[i] - hits[i]).abs(), lessThan(0.001), reason: 'corte $i em ${cuts[i]}');
      }
      c.dispose();
    });

    test('a distância mínima', () {
      expect(filterCuts([0.1, 0.12, 0.3, 0.31], 0, 1, 0.05), [0.1, 0.3]);
      expect(filterCuts([0.1, 0.12, 0.3, 0.31], 0, 1, 0.15), [0.1, 0.3]);
      expect(filterCuts([0.002, 0.02, 0.5, 0.98, 0.998], 0, 1, 0.05), [0.02, 0.5, 0.98], reason: 'a menos de 5 ms das pontas não corta');
      expect(filterCuts([0.5, 0.5, double.nan, -1, 2], 0, 1, 0), [0.5]);
    });

    test('fatias iguais e na grade', () async {
      final (c, _) = await setup(tone(2));
      final t = c.audioEditTarget('c1');
      final eq = detectCuts(t.range!, t.clip!, c.doc, mode: CutMode.equal, count: 4);
      expect(eq, [0.5, 1.0, 1.5]);
      // 120 bpm: 1/4 = 0,5 s
      final g = detectCuts(t.range!, t.clip!, c.doc, mode: CutMode.grid, grid: EditGrid.quarter);
      expect(g, [0.5, 1.0, 1.5]);
      final g16 = detectCuts(t.range!, t.clip!, c.doc, mode: CutMode.grid, grid: EditGrid.sixteenth);
      expect(g16, hasLength(15));
      expect(g16.first, closeTo(0.125, 1e-9));
      c.dispose();
    });

    test('a grade vale com o clipe fora do zero e com offset', () async {
      final (c, _) = await setup(tone(4), start: 0.75, offset: 0.5, length: 2);
      final t = c.audioEditTarget('c1');
      // o clipe ocupa as batidas 0,75 a 4,75: as linhas de 1/4 caem nas batidas 1, 2, 3 e 4
      final g = detectCuts(t.range!, t.clip!, c.doc, mode: CutMode.grid, grid: EditGrid.quarter, minGap: 0);
      expect(g, hasLength(4));
      expect(g.first, closeTo(0.5 + 0.125, 1e-9), reason: 'a batida 1 cai 0,125 s depois do começo do clipe');
      c.dispose();
    });
  });

  group('dividir por transientes', () {
    test('as fatias cobrem o clipe sem lacuna, a soma das durações se preserva e o som é idêntico', () async {
      final x = drums(hits);
      final (c, _) = await setup(x);
      final orig = clipsOf(c).single;
      final before = render(c, [orig], x, x.length);
      final cuts = detectCuts(c.audioEditTarget('c1').range!, orig, c.doc);
      final r = c.splitClipAt('c1', cuts);
      expect(r.ok, isTrue, reason: r.message);
      final pieces = clipsOf(c);
      expect(pieces, hasLength(5));
      pieces.sort((a, b) => a.start.compareTo(b.start));
      // duração nominal (sem a cabeça do crossfade) soma a do clipe original
      var nominal = 0.0;
      for (var i = 0; i < pieces.length; i++) {
        final head = i == 0 ? 0.0 : pieces[i].fadeIn;
        nominal += pieces[i].length - head;
        if (i > 0) {
          // cada fatia começa no corte menos a cabeça e o corte é o começo da nominal
          expect(c.doc.secondsAt(pieces[i].start) + head, closeTo(pieces[i].offset + head, 1e-9), reason: 'fatia $i fica no lugar dela');
        }
      }
      expect(nominal, closeTo(orig.length, 1e-9));
      // crossfade de 2 ms nas emendas
      for (var i = 1; i < pieces.length; i++) {
        expect(pieces[i].fadeIn, closeTo(microFade, 1e-12));
        expect(pieces[i - 1].fadeOut, closeTo(microFade, 1e-12));
      }
      expect(pieces.first.fadeIn, 0);
      expect(pieces.last.fadeOut, 0);
      // o som em sequência é o mesmo do clipe original
      final after = render(c, pieces, x, x.length);
      expect(maxDiff(before, after), lessThan(1e-5));
      expect(c.selectedClip, pieces.first.id);
      c.dispose();
    });

    test('desfazer restaura o clipe numa edição só', () async {
      final (c, _) = await setup(drums(hits));
      final j = docJson(c);
      final r = c.splitClipAt('c1', detectCuts(c.audioEditTarget('c1').range!, clipsOf(c).single, c.doc));
      expect(r.ok, isTrue);
      expect(docJson(c), isNot(j));
      c.undo();
      expect(docJson(c), j);
      c.redo();
      expect(clipsOf(c), hasLength(5));
      c.dispose();
    });

    test('clipe com fades e offset: os fades originais ficam nas pontas e o som não muda', () async {
      final x = drums(hits);
      final (c, _) = await setup(x, start: 2, offset: 0.2, length: 2.3, fadeIn: 0.05, fadeOut: 0.1);
      final orig = clipsOf(c).single;
      final before = render(c, [orig], x, 5 * rate);
      final r = c.splitClipAt('c1', detectCuts(c.audioEditTarget('c1').range!, orig, c.doc));
      expect(r.ok, isTrue, reason: r.message);
      final pieces = clipsOf(c)..sort((a, b) => a.start.compareTo(b.start));
      expect(pieces.first.fadeIn, 0.05);
      expect(pieces.first.offset, 0.2);
      expect(pieces.first.start, 2);
      expect(pieces.last.fadeOut, 0.1);
      expect(pieces.last.offset + pieces.last.length, closeTo(2.5, 1e-9));
      expect(maxDiff(before, render(c, pieces, x, 5 * rate)), lessThan(1e-5));
      c.dispose();
    });

    test('fade original maior que a fatia é encurtado e avisa', () async {
      final x = drums(hits);
      final (c, _) = await setup(x, fadeIn: 0.5);
      final r = c.splitClipAt('c1', [0.1, 1.0]);
      expect(r.ok, isTrue);
      expect(r.message, contains('encurtado'));
      final p = clipsOf(c)..sort((a, b) => a.start.compareTo(b.start));
      expect(p.first.fadeIn + p.first.fadeOut, lessThanOrEqualTo(p.first.length + 1e-12));
      c.dispose();
    });

    test('casos extremos: sem cortes, sem transientes, clipe de 1 amostra, tudo silêncio', () async {
      var (c, _) = await setup(tone(2));
      final j = docJson(c);
      expect(c.splitClipAt('c1', const []).ok, isFalse);
      // tom contínuo: sem transientes
      final t = c.audioEditTarget('c1');
      expect(detectCuts(t.range!, t.clip!, c.doc), isEmpty);
      expect(docJson(c), j, reason: 'nada mudou');
      c.dispose();

      (c, _) = await setup(Float32List.fromList([0.5]));
      final one = c.audioEditTarget('c1');
      expect(one.error, isNull);
      expect(detectCuts(one.range!, one.clip!, c.doc), isEmpty);
      expect(detectCuts(one.range!, one.clip!, c.doc, mode: CutMode.equal, count: 8), isEmpty);
      expect(c.stripClipSilence('c1', const SilenceSettings()).ok, isFalse, reason: 'um quadro alto não é silêncio');
      expect(clipsOf(c), hasLength(1));
      c.dispose();

      (c, _) = await setup(Float32List(rate));
      final silent = c.audioEditTarget('c1');
      expect(detectCuts(silent.range!, silent.clip!, c.doc), isEmpty);
      c.dispose();
    });

    test('clipe com warp ou inversão é recusado e nada muda', () async {
      final x = drums(hits);
      final (c, _) = await setup(x);
      final j = docJson(c);
      c.setClipWarp('c1', reverse: true);
      final before = docJson(c);
      expect(before, isNot(j));
      final r = c.splitClipAt('c1', const [0.5]);
      expect(r.ok, isFalse);
      expect(r.message, contains('warp'));
      expect(c.quantizeClipSlices('c1', const QuantizeSettings()).ok, isFalse);
      expect(c.stripClipSilence('c1', const SilenceSettings()).ok, isFalse);
      expect(docJson(c), before);
      c.dispose();
    });

    test('áudio fora do aparelho: mensagem clara', () async {
      final (c, hash) = await setup(drums(hits));
      c.mutate((d) => d.tracks[0].clips.single.sample = 'nao-existe');
      final r = c.splitClipAt('c1', const [0.5]);
      expect(r.ok, isFalse);
      expect(r.message, missingAudioMessage);
      expect(hash, isNotEmpty);
      c.dispose();
    });

    test('clipe que não existe', () async {
      final (c, _) = await setup(drums(hits));
      expect(c.splitClipAt('zzz', const [0.5]).ok, isFalse);
      c.dispose();
    });

    test('muitas fatias: recusa sem mexer no documento', () async {
      final (c, _) = await setup(tone(60));
      final j = docJson(c);
      final r = c.splitClipAt('c1', [for (var i = 1; i < 700; i++) i * 0.08]);
      expect(r.ok, isFalse);
      expect(docJson(c), j);
      c.dispose();
    });
  });

  group('remover silêncio', () {
    final bursts = [(0.5, 0.8), (1.5, 1.9)];
    test('divide nos trechos com som, com margem, e diz quanto removeu', () async {
      final x = noiseBursts(bursts, 2.5);
      final (c, _) = await setup(x);
      final plan = planSilence(c.audioEditTarget('c1').range!, const SilenceSettings());
      expect(plan.kept, hasLength(2));
      // silêncio de 0 a 0,5: fica 10 ms antes do som; de 0,8 a 1,5: 20 ms depois e 10 ms antes
      expect(plan.kept[0].$1, closeTo(0.49, 0.0015));
      expect(plan.kept[0].$2, closeTo(0.82, 0.0015));
      expect(plan.kept[1].$1, closeTo(1.49, 0.0015));
      expect(plan.kept[1].$2, closeTo(1.92, 0.0015));
      expect(plan.removedSeconds, closeTo(2.5 - 0.33 - 0.43, 0.004));
      final r = c.stripClipSilence('c1', const SilenceSettings());
      expect(r.ok, isTrue, reason: r.message);
      expect(r.message, matches(RegExp(r'^2 trechos, 1,74 s removidos$')));
      final p = clipsOf(c)..sort((a, b) => a.start.compareTo(b.start));
      expect(p, hasLength(2));
      // ficam no mesmo lugar do tempo (deixa a lacuna)
      expect(c.doc.secondsAt(p[0].start), closeTo(0.49, 0.0015));
      expect(c.doc.secondsAt(p[1].start), closeTo(1.49, 0.0015));
      // 5 ms de fade nos cortes
      expect(p[0].fadeIn, closeTo(0.005, 1e-9));
      expect(p[0].fadeOut, closeTo(0.005, 1e-9));
      // o som que sobra é o mesmo, no mesmo instante, com o silêncio a menos
      final after = render(c, p, x, x.length);
      for (final (a, b) in bursts) {
        final i0 = ((a + 0.02) * rate).round(), i1 = ((b - 0.02) * rate).round();
        for (var i = i0; i < i1; i++) {
          expect(after[i], x[i]);
        }
      }
      c.undo();
      expect(clipsOf(c), hasLength(1));
      c.dispose();
    });

    test('silêncio mais curto que o mínimo fica; limiar mais alto remove mais', () async {
      // 0,3 a 0,6 e 0,65 a 0,9: o vão é de 50 ms
      final x = noiseBursts([(0.3, 0.6), (0.65, 0.9)], 1.2);
      final (c, _) = await setup(x);
      final r = c.audioEditTarget('c1').range!;
      expect(planSilence(r, const SilenceSettings(guardBefore: 0, guardAfter: 0)).kept, hasLength(1), reason: 'o vão de 50 ms fica');
      expect(planSilence(r, const SilenceSettings(guardBefore: 0, guardAfter: 0, minSilence: 0.04)).kept, hasLength(2));
      // ruído a 0,3 de amplitude (−10 dBFS): limiar de 0 dB deixa tudo como silêncio; −20 dB não
      expect(planSilence(r, const SilenceSettings(thresholdDb: 0)).allSilent, isTrue);
      expect(planSilence(r, const SilenceSettings(thresholdDb: -20)).kept, isNotEmpty);
      c.dispose();
    });

    test('margem maior que o silêncio: nada é removido', () async {
      final x = noiseBursts(bursts, 2.5);
      final (c, _) = await setup(x);
      final plan = planSilence(c.audioEditTarget('c1').range!, const SilenceSettings(guardBefore: 0.5, guardAfter: 0.5));
      // as margens de 0,5 s de cada lado engolem os vãos de 0,5 e 0,7 s: só o rabo final (2,4 a 2,5) sai
      expect(plan.removed, hasLength(1));
      expect(plan.kept, hasLength(1));
      expect(plan.removed.single.$1, closeTo(2.4, 0.0015));
      c.dispose();
    });

    test('clipe todo silencioso: recusa e não apaga nada', () async {
      final (c, _) = await setup(Float32List(rate * 2));
      final j = docJson(c);
      final r = c.stripClipSilence('c1', const SilenceSettings());
      expect(r.ok, isFalse);
      expect(r.message, contains('abaixo do limiar'));
      expect(docJson(c), j);
      c.dispose();
    });

    test('sem silêncio: nada a fazer', () async {
      final (c, _) = await setup(tone(1));
      final r = c.stripClipSilence('c1', const SilenceSettings());
      expect(r.ok, isFalse);
      expect(clipsOf(c), hasLength(1));
      c.dispose();
    });

    test('clipe com offset, fades e início no meio do tempo: o corte respeita o trecho', () async {
      final x = noiseBursts(bursts, 2.5);
      // toca de 0,3 a 2,0 do áudio, a partir do segundo 4 (batida 8)
      final (c, _) = await setup(x, start: 8, offset: 0.3, length: 1.7, fadeIn: 0.02, fadeOut: 0.03);
      final r = c.stripClipSilence('c1', const SilenceSettings());
      expect(r.ok, isTrue, reason: r.message);
      final p = clipsOf(c)..sort((a, b) => a.start.compareTo(b.start));
      expect(p, hasLength(2));
      // primeiro trecho: o silêncio do começo do clipe (0,3 a 0,5) sai, ficando 10 ms antes do som
      expect(p[0].offset, closeTo(0.49, 0.0015));
      expect(c.doc.secondsAt(p[0].start), closeTo(4 + (0.49 - 0.3), 0.0015));
      // o segundo termina no fim do clipe (2,0) com o fade de saída original
      expect(p[1].offset + p[1].length, closeTo(1.92, 0.0015));
      // o trecho de fora do clipe nunca entra
      expect(p.every((k) => k.offset >= 0.3 - 1e-9 && k.offset + k.length <= 2.0 + 1e-9), isTrue);
      c.dispose();
    });

    test('silêncio nas pontas do clipe: o primeiro e o último trecho mantêm os fades originais quando tocam a ponta', () async {
      final x = noiseBursts([(0.0, 0.4), (1.0, 1.4)], 1.4);
      final (c, _) = await setup(x, fadeIn: 0.01, fadeOut: 0.02);
      final r = c.stripClipSilence('c1', const SilenceSettings());
      expect(r.ok, isTrue, reason: r.message);
      final p = clipsOf(c)..sort((a, b) => a.start.compareTo(b.start));
      expect(p.first.fadeIn, 0.01);
      expect(p.first.start, 0);
      expect(p.last.fadeOut, 0.02);
      expect(p.first.fadeOut, closeTo(0.005, 1e-9));
      c.dispose();
    });
  });

  group('normalizar', () {
    double peakDb(Float32List x, double gain) => 20 * math.log(x.fold<double>(0, (m, v) => math.max(m, v.abs())) * gain) / math.ln10;

    test('pico: chega a −1 dBFS com ±0,1 dB e diz o ganho', () async {
      final x = tone(1, amp: 0.3);
      final (c, _) = await setup(x);
      final r = await c.normalizeClip('c1', NormalizeMode.peak, -1);
      expect(r.ok, isTrue, reason: r.message);
      expect(peakDb(x, clipsOf(c).single.gain), closeTo(-1, 0.1));
      expect(r.message, contains('Ganho do clipe: +'));
      c.undo();
      expect(clipsOf(c).single.gain, 1);
      c.dispose();
    });

    test('pico para baixo (sinal alto) e alvo personalizado', () async {
      final x = tone(1, amp: 0.9);
      final (c, _) = await setup(x);
      await c.normalizeClip('c1', NormalizeMode.peak, -12);
      expect(peakDb(x, clipsOf(c).single.gain), closeTo(-12, 0.1));
      c.dispose();
    });

    test('mede só o trecho que o clipe toca', () async {
      // metade baixa (0,1), metade alta (0,8): o clipe toca só a baixa
      final x = Float32List.fromList([...tone(1, amp: 0.3), ...tone(1, amp: 0.8)]);
      final (c, _) = await setup(x, length: 1);
      await c.normalizeClip('c1', NormalizeMode.peak, -6);
      expect(peakDb(tone(1, amp: 0.3), clipsOf(c).single.gain), closeTo(-6, 0.1));
      c.dispose();
    });

    test('RMS: o trecho fica no alvo', () async {
      final x = tone(1, amp: 0.1);
      final (c, _) = await setup(x);
      final r = await c.normalizeClip('c1', NormalizeMode.rms, -18);
      expect(r.ok, isTrue, reason: r.message);
      final g = clipsOf(c).single.gain;
      var s = 0.0;
      for (final v in x) {
        s += (v * g) * (v * g);
      }
      expect(20 * math.log(math.sqrt(s / x.length)) / math.ln10, closeTo(-18, 0.1));
      c.dispose();
    });

    test('LUFS: o loudness integrado do clipe fica no alvo', () async {
      final x = tone(3, amp: 0.2);
      final (c, _) = await setup(x);
      final r = await c.normalizeClip('c1', NormalizeMode.lufs, -14);
      expect(r.ok, isTrue, reason: r.message);
      final g = clipsOf(c).single.gain;
      final m = await measureLoudness([
        Float32List.fromList([for (final v in x) v * g]),
      ], rate.toDouble());
      expect(m.integrated, closeTo(-14, 0.1));
      c.dispose();
    });

    test('LUFS de um clipe curto demais explica e não muda nada', () async {
      final (c, _) = await setup(tone(0.2));
      final r = await c.normalizeClip('c1', NormalizeMode.lufs, -14);
      expect(r.ok, isFalse);
      expect(r.message, contains('400 ms'));
      expect(clipsOf(c).single.gain, 1);
      c.dispose();
    });

    test('teto de +12 dB do ganho e teto do zero digital fora do pico', () async {
      final quiet = tone(1, amp: 0.001);
      var (c, _) = await setup(quiet);
      var r = await c.normalizeClip('c1', NormalizeMode.peak, -1);
      expect(r.ok, isTrue);
      expect(clipsOf(c).single.gain, closeTo(maxClipGain, 1e-9));
      expect(r.message, contains('Limitado'));
      c.dispose();

      // sinal com pico alto e RMS baixo: chegar ao RMS alvo estouraria o pico
      final x = Float32List(rate);
      x[100] = 0.9;
      (c, _) = await setup(x);
      r = await c.normalizeClip('c1', NormalizeMode.rms, -10);
      expect(r.ok, isTrue);
      expect(peakDb(x, clipsOf(c).single.gain), lessThanOrEqualTo(0.001));
      expect(r.message, contains('Limitado'));
      c.dispose();
    });

    test('clipe mudo, de 1 amostra e com warp', () async {
      var (c, _) = await setup(Float32List(rate));
      var r = await c.normalizeClip('c1', NormalizeMode.peak, -1);
      expect(r.ok, isFalse);
      expect(r.message, contains('silêncio'));
      c.dispose();

      (c, _) = await setup(Float32List.fromList([0.25]));
      r = await c.normalizeClip('c1', NormalizeMode.peak, -1);
      expect(r.ok, isTrue, reason: r.message);
      expect(peakDb(Float32List.fromList([0.25]), clipsOf(c).single.gain), closeTo(-1, 0.1));
      c.dispose();

      (c, _) = await setup(tone(1, amp: 0.1));
      c.setClipWarp('c1', reverse: true, pitch: 3);
      r = await c.normalizeClip('c1', NormalizeMode.peak, -1);
      expect(r.ok, isTrue, reason: 'ganho vale com warp/inversão');
      c.dispose();
    });
  });

  group('quantizar por fatias', () {
    // 120 bpm: 1/8 = 0,25 s. Ataques fora do tempo, até 30 ms para cada lado.
    final off = [0.02, 0.27, 0.485, 0.78, 1.03, 1.235, 1.53, 1.79];

    test('força 100%: cada transiente cai a menos de 1 ms da grade', () async {
      final x = drums(off, seconds: 2.2);
      final (c, _) = await setup(x);
      final r = c.quantizeClipSlices('c1', const QuantizeSettings(grid: EditGrid.eighth));
      expect(r.ok, isTrue, reason: r.message);
      // o instante em que cada ataque toca: procura a fatia que contém o ataque na fonte e não é só cabeça
      final onsets = [for (final t in off) onsetOf(c, t)];
      for (var i = 0; i < off.length; i++) {
        final grid = (onsets[i] / 0.25).round() * 0.25;
        expect((onsets[i] - grid).abs(), lessThan(0.001), reason: 'ataque $i em ${onsets[i]}');
      }
      expect(r.message, contains('movidas'));
      c.dispose();
    });

    test('ponta a ponta: o áudio renderizado tem os ataques na grade', () async {
      final x = drums(off, seconds: 2.4);
      final (c, _) = await setup(x);
      expect(c.quantizeClipSlices('c1', const QuantizeSettings(grid: EditGrid.eighth)).ok, isTrue);
      final out = render(c, clipsOf(c), x, x.length + rate ~/ 2);
      for (var k = 0; k < off.length; k++) {
        final want = (off[k] / 0.25).round() * 0.25;
        // primeiro quadro acima de 20% do pico, a partir de 20 ms antes da grade
        var peak = 0.0;
        for (var i = math.max(0, ((want - 0.02) * rate).round()); i < ((want + 0.03) * rate).round(); i++) {
          peak = math.max(peak, out[i].abs());
        }
        var first = -1;
        for (var i = math.max(0, ((want - 0.02) * rate).round()); i < ((want + 0.03) * rate).round(); i++) {
          if (out[i].abs() > 0.02) {
            first = i;
            break;
          }
        }
        expect(peak, greaterThan(0.1), reason: 'som no ataque $k');
        expect((first / rate - want).abs(), lessThan(0.001), reason: 'ataque $k tocando em ${first / rate}, grade $want');
      }
      c.dispose();
    });

    test('força 50%: anda metade do caminho', () async {
      final x = drums(off, seconds: 2.2);
      final (c, _) = await setup(x);
      final t = c.audioEditTarget('c1');
      final plan = planQuantize(t.range!, t.clip!, c.doc, const QuantizeSettings(grid: EditGrid.eighth, strength: 0.5));
      final full = planQuantize(t.range!, t.clip!, c.doc, const QuantizeSettings(grid: EditGrid.eighth));
      expect(plan.slices, hasLength(full.slices.length));
      for (var i = 0; i < plan.slices.length; i++) {
        expect(plan.shiftsMs[i], closeTo(full.shiftsMs[i] / 2, 1e-6));
      }
      final zero = planQuantize(t.range!, t.clip!, c.doc, const QuantizeSettings(grid: EditGrid.eighth, strength: 0));
      expect(zero.moved, 0);
      c.dispose();
    });

    test('força 0 equivale a dividir: o som não muda', () async {
      final x = drums(off, seconds: 2.2);
      final (c, _) = await setup(x);
      final before = render(c, clipsOf(c), x, x.length);
      expect(c.quantizeClipSlices('c1', const QuantizeSettings(grid: EditGrid.eighth, strength: 0)).ok, isTrue);
      expect(maxDiff(before, render(c, clipsOf(c), x, x.length)), lessThan(1e-5));
      c.dispose();
    });

    test('sem sobreposição dupla: com "manter juntas" nenhuma fatia passa do começo da seguinte', () async {
      final x = drums(off, seconds: 2.2);
      final (c, _) = await setup(x);
      final r = c.quantizeClipSlices('c1', const QuantizeSettings(grid: EditGrid.eighth, keepTogether: true));
      expect(r.ok, isTrue);
      final p = clipsOf(c)..sort((a, b) => a.start.compareTo(b.start));
      for (var i = 0; i + 1 < p.length; i++) {
        final end = c.doc.secondsAt(p[i].start) + p[i].length;
        // duas fatias que caem no mesmo ponto (a do silêncio antes do primeiro ataque, que a grade leva ao zero) soam juntas
        if (c.doc.secondsAt(p[i + 1].start) - c.doc.secondsAt(p[i].start) < 0.004) continue;
        expect(end, lessThanOrEqualTo(c.doc.secondsAt(p[i + 1].start) + microFade + 1e-6), reason: 'fatia $i');
      }
      c.dispose();
    });

    test('sem "manter juntas": o rabo passa até 10 ms por baixo do ataque novo e some com fade', () async {
      final x = drums(off, seconds: 2.2);
      final (c, _) = await setup(x);
      expect(c.quantizeClipSlices('c1', const QuantizeSettings(grid: EditGrid.eighth)).ok, isTrue);
      final p = clipsOf(c)..sort((a, b) => a.start.compareTo(b.start));
      for (var i = 0; i + 1 < p.length; i++) {
        final end = c.doc.secondsAt(p[i].start) + p[i].length;
        final next = c.doc.secondsAt(p[i + 1].start) + p[i + 1].fadeIn;
        expect(end, lessThanOrEqualTo(next + 0.01 + 1e-6), reason: 'fatia $i');
      }
      c.dispose();
    });

    test('desfazer restaura tudo numa edição só', () async {
      final (c, _) = await setup(drums(off, seconds: 2.2));
      final j = docJson(c);
      expect(c.quantizeClipSlices('c1', const QuantizeSettings(grid: EditGrid.eighth)).ok, isTrue);
      c.undo();
      expect(docJson(c), j);
      c.dispose();
    });

    test('com mapa de andamento a grade é a das batidas, não a dos segundos', () async {
      final x = drums([0.02, 0.27, 0.49, 0.72], seconds: 1.5);
      final (c, _) = await setup(x);
      c.mutate((d) => d.bpm = 100);
      // a 100 bpm, 1/8 = 0,3 s
      final r = c.quantizeClipSlices('c1', const QuantizeSettings(grid: EditGrid.eighth));
      expect(r.ok, isTrue, reason: r.message);
      for (final t in [0.27, 0.49, 0.72]) {
        final on = onsetOf(c, t);
        expect(((on / 0.3) - (on / 0.3).round()).abs() * 0.3, lessThan(0.001));
      }
      c.dispose();
    });

    test('com mapa de andamento (120 e depois 90 bpm) os ataques caem nas batidas', () async {
      final hitsT = [0.52, 1.03, 1.68, 2.31];
      final x = drums(hitsT, seconds: 3);
      final (c, _) = await setup(x);
      c.mutate((d) => d.tempoMap = [const TempoPoint(0, 120), const TempoPoint(2, 90)]);
      final r = c.quantizeClipSlices('c1', const QuantizeSettings(grid: EditGrid.quarter));
      expect(r.ok, isTrue, reason: r.message);
      for (final t in hitsT) {
        final on = onsetOf(c, t);
        final beat = c.doc.beatAtSeconds(on).round();
        expect((c.doc.secondsAt(beat.toDouble()) - on).abs(), lessThan(0.001), reason: 'ataque $t tocando em $on');
      }
      c.dispose();
    });

    test('sem transientes: recusa; clipe de 1 amostra: recusa; grade 1/32 e 1/4', () async {
      var (c, _) = await setup(tone(2));
      var r = c.quantizeClipSlices('c1', const QuantizeSettings());
      expect(r.ok, isFalse);
      expect(r.message, contains('transiente'));
      c.dispose();
      (c, _) = await setup(Float32List.fromList([0.7]));
      r = c.quantizeClipSlices('c1', const QuantizeSettings());
      expect(r.ok, isFalse);
      c.dispose();
      for (final g in EditGrid.values) {
        (c, _) = await setup(drums(off, seconds: 2.2));
        r = c.quantizeClipSlices('c1', QuantizeSettings(grid: g));
        expect(r.ok, isTrue, reason: '${g.label}: ${r.message}');
        c.dispose();
      }
    });

    test('clipe com offset e fades: os fades das pontas e o trecho ficam', () async {
      final x = drums(off, seconds: 2.4);
      final (c, _) = await setup(x, start: 4, offset: 0.1, length: 2, fadeIn: 0.01, fadeOut: 0.05);
      final r = c.quantizeClipSlices('c1', const QuantizeSettings(grid: EditGrid.eighth, keepTogether: true));
      expect(r.ok, isTrue, reason: r.message);
      final p = clipsOf(c)..sort((a, b) => a.start.compareTo(b.start));
      expect(p.first.fadeIn, 0.01);
      expect(p.last.fadeOut, 0.05);
      expect(p.every((k) => k.offset >= 0.1 - microFade - 1e-9), isTrue);
      expect(p.every((k) => k.offset + k.length <= 2.1 + 1e-9), isTrue);
      c.dispose();
    });

    test('a primeira fatia nunca vai para antes do zero', () async {
      // clipe perto do começo do projeto e ataque logo cedo: arredondar para baixo daria batida negativa
      final x = drums([0.012, 0.5], seconds: 1);
      final (c, _) = await setup(x);
      final r = c.quantizeClipSlices('c1', const QuantizeSettings(grid: EditGrid.quarter));
      expect(r.ok, isTrue, reason: r.message);
      expect(clipsOf(c).every((k) => k.start >= 0), isTrue);
      c.dispose();
    });
  });
}
