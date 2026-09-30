/// Edição de áudio por fatias, sem destruir nada: dividir por transientes, remover silêncio,
/// normalizar o clipe e quantizar por fatias.
///
/// Toda ação só cria ou muda clipes que apontam para o mesmo sample (offset, duração, ganho e
/// fades); o arquivo de áudio nunca é tocado e o desfazer volta a edição inteira num passo só.
///
/// As emendas entre fatias vizinhas (dividir e quantizar) são *crossfades* de [microFade]: a fatia
/// seguinte começa [microFade] antes do corte, com fade de entrada em curva S, e a anterior termina
/// no corte com fade de saída em curva S do mesmo tamanho. Como as duas tocam o mesmo trecho do mesmo
/// áudio (sinais correlacionados), o que tem de somar 1 é a *amplitude*: a curva S do motor
/// (`(1−cos πx)/2`, [FadeShape.sCurve]) espelhada soma exatamente 1 em cada instante, então o som em
/// sequência é idêntico ao do clipe original (sem buraco, sem afundar e sem estalo). A curva padrão
/// do motor (`x²`, [FadeShape.linear]) somaria só 0,5 no meio (−6 dB) e não serve aqui.
///
/// Quem perde o crossfade, conforme `buildSlices`: a primeira fatia mantém o fade de entrada do
/// clipe e a última o de saída (nas pontas não há vizinha); a fatia que a seguinte corta por cima
/// (quantização) troca a emenda por um fade de saída simples (seco de [microFade] com "manter juntas",
/// ou o rabo de 10 ms sem ele), e onde há lacuna ou sobreposição curta demais para cortar as fatias
/// são outras partes do áudio, então o fade é só o de entrada/saída de cada uma.
///
/// A edição por fatias trabalha no áudio original: clipes com warp, transposição ou inversão são
/// recusados com uma mensagem clara (a fatia cairia fora do lugar no som esticado). Só a
/// normalização vale para eles, porque ganho é ganho.
///
/// A lógica é pura (Dart, sem plataforma) e roda igual na web e no Android. Não há deslocamento de
/// bits (`<<`) aqui: na web os inteiros têm 32 bits.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../audio/engine_types.dart';
import 'clip_gain_dialog.dart' show formatClipGainDb;
import 'controller.dart';
import 'loudness.dart';
import 'model.dart';
import 'sampler_zones.dart' show slicePoints;

/// O fade de emenda entre fatias (2 ms): curto para não mexer no som, longo para não estalar.
const microFade = 0.002;

/// A curva das emendas: a única do motor cujo par entrada/saída soma amplitude 1 (ver o topo).
const _seamShape = FadeShape.sCurve;

/// O máximo de clipes que uma edição cria de uma vez (protege o documento de uma sensibilidade
/// exagerada num áudio longo).
const maxEditPieces = 500;

/// O rabo de uma fatia que a seguinte cobre (quantização sem "manter juntas"): ela some com um
/// fade desse tamanho por baixo do ataque novo em vez de cortar seco.
const _ring = 0.01;

/// Fatia mais curta que isto não é cortada pela vizinha (viraria um estalo): as duas soam juntas.
const _minTrimmed = 0.004;

const _eps = 1e-7;

/// Uma fatia não nasce com menos disto nas pontas do clipe (o crossfade de emenda precisa de espaço).
const _edgeMin = 0.005;

// ------------------------------------------------------------------------- resultado

/// O que uma edição fez (ou por que não fez).
class AudioEditResult {
  final bool ok;

  /// Texto pronto para a tela (erro inline ou confirmação).
  final String message;

  /// Ids dos clipes que a edição deixou no lugar do original (vazio se não fez nada).
  final List<String> ids;
  const AudioEditResult(this.ok, this.message, [this.ids = const []]);
}

/// Por que [reason]: o clipe não pode ser editado por fatias (null: pode). Vale para dividir, remover silêncio e
/// quantizar; a conversão em notas tem a própria recusa do clipe em loop no controlador.
String? sliceEditBlocker(AudioClip clip) {
  if (clip.processed) {
    return 'Este clipe usa warp, transposição ou inversão. A edição por fatias trabalha no áudio original e ignora o warp; '
        'desligue o processamento em “Warp e altura…” antes de editar.';
  }
  if (clip.looping) {
    return 'Este clipe está em loop: a edição por fatias trabalha no trecho que o clipe toca uma vez só e não enxerga as repetições. '
        'Desligue o loop do clipe antes de editar.';
  }
  return null;
}

const missingAudioMessage = 'Este áudio não está neste aparelho. Importe o arquivo de novo para editá-lo.';

// ------------------------------------------------------------------------- o trecho do clipe

/// O trecho de áudio que o clipe toca (`offset`..`offset + length` do sample), como visão sem
/// cópia; [base] é o segundo do sample onde a visão começa (arredondado ao quadro).
class ClipRange {
  final DecodedAudio audio;
  final double base;
  ClipRange(this.audio, this.base);

  int get frames => audio.channels.isEmpty ? 0 : audio.frames;
  double get duration => frames / audio.rate;
  bool get isEmpty => frames == 0;

  /// O trecho de [clip] dentro de [full]; vazio se o clipe cai fora do áudio ou a taxa é inválida.
  factory ClipRange.of(DecodedAudio full, AudioClip clip) {
    if (full.channels.isEmpty || !(full.rate.isFinite && full.rate > 0)) return ClipRange(DecodedAudio([Float32List(0)], 48000), 0);
    final n = full.channels.map((c) => c.length).reduce(math.min);
    final f0 = (clip.offset * full.rate).round().clamp(0, n);
    final f1 = ((clip.offset + clip.length) * full.rate).round().clamp(f0, n);
    return ClipRange(DecodedAudio([for (final c in full.channels) Float32List.sublistView(c, f0, f1)], full.rate), f0 / full.rate);
  }
}

// ------------------------------------------------------------------------- cortes

/// Como achar os cortes.
enum CutMode {
  /// Um corte em cada transiente.
  transients('Por transientes'),

  /// [count] fatias iguais.
  equal('N fatias iguais'),

  /// Um corte em cada linha da grade.
  grid('Na grade');

  final String label;
  const CutMode(this.label);
}

/// A grade das ações de fatia: 1/4 a 1/32 (o passo da linha do tempo só vai a 1/16).
enum EditGrid {
  quarter('1/4', 1),
  eighth('1/8', 0.5),
  sixteenth('1/16', 0.25),
  thirtySecond('1/32', 0.125);

  final String label;

  /// Batidas (semínimas) de um passo.
  final double beats;
  const EditGrid(this.label, this.beats);

  /// A grade da linha do tempo, ou 1/16 quando ela é "Livre" ou "Compasso".
  static EditGrid fromSnap(Snap s) => switch (s) {
    Snap.beat => EditGrid.quarter,
    Snap.half => EditGrid.eighth,
    _ => EditGrid.sixteenth,
  };
}

/// Os cortes de [clip] em segundos do sample (absolutos, crescentes, todos dentro do trecho e a
/// pelo menos [minGap] uns dos outros e a 5 ms das pontas). [range] é o trecho do clipe.
///
/// Por transientes reaproveita `slicePoints` (o mesmo detector do fatiamento do sampler, com a
/// paridade contra o motor intacta); [sensitivity] vale de 0 a 1. Iguais: [count] de 2 a 96. Grade:
/// as linhas de [grid] (em batidas) pelo mapa de andamento de [doc].
List<double> detectCuts(
  ClipRange range,
  AudioClip clip,
  DawDoc doc, {
  CutMode mode = CutMode.transients,
  double sensitivity = 0.5,
  int count = 8,
  EditGrid grid = EditGrid.sixteenth,
  double minGap = 0.05,
}) {
  if (range.isEmpty) return const [];
  final from = clip.offset, to = clip.offset + clip.length;
  var raw = <double>[];
  switch (mode) {
    case CutMode.transients:
      raw = [for (final p in slicePoints(range.audio, sensitivity: sensitivity, limit: 100000)) range.base + p];
    case CutMode.equal:
      raw = [for (final p in slicePoints(range.audio, count: count)) range.base + p];
    case CutMode.grid:
      raw = gridCuts(clip, doc, grid.beats);
  }
  return filterCuts(raw, from, to, minGap);
}

/// As linhas de grade de [gridBeats] batidas dentro do clipe, em segundos do sample. O clipe sem
/// warp toca em tempo real, então o tempo do sample é o do mapa de andamento.
///
/// Lança [CutLimitException] se o clipe tem mais que [maxGridLines] linhas (antes isso truncava em silêncio).
List<double> gridCuts(AudioClip clip, DawDoc doc, double gridBeats) {
  if (!(gridBeats > 0)) return const [];
  final t0 = doc.secondsAt(clip.start);
  final endBeat = doc.beatAtSeconds(t0 + clip.length);
  final out = <double>[];
  var k = (clip.start / gridBeats).floor() + 1;
  while (true) {
    final b = k * gridBeats;
    if (b >= endBeat - 1e-9) break;
    if (out.length >= maxGridLines) {
      throw CutLimitException('Linhas de grade demais neste clipe (mais de $maxGridLines). Use uma grade maior ou divida o clipe antes.');
    }
    out.add(clip.offset + (doc.secondsAt(b) - t0));
    k++;
  }
  return out;
}

/// O máximo de linhas de grade que [gridCuts] varre.
const int maxGridLines = 20000;

/// A análise dos cortes passou de um limite: [message] está pronta para a tela.
class CutLimitException implements Exception {
  final String message;
  CutLimitException(this.message);
  @override
  String toString() => message;
}

/// Tira o que não serve de corte: fora do trecho, repetido, perto demais de outro corte ([minGap]) ou a
/// menos de 5 ms das pontas. Devolve crescente.
List<double> filterCuts(Iterable<double> cuts, double from, double to, double minGap) {
  final sorted = [
    for (final c in cuts)
      if (c.isFinite && c > from + _eps && c < to - _eps) c,
  ]..sort();
  final out = <double>[];
  var last = from;
  for (final c in sorted) {
    if (c - (out.isEmpty ? from : last) < (out.isEmpty ? _edgeMin : math.max(minGap, _eps))) continue;
    if (to - c < _edgeMin) continue;
    out.add(c);
    last = c;
  }
  return out;
}

// ------------------------------------------------------------------------- fatias e clipes

/// Uma fatia: o trecho `[srcStart, srcEnd)` do sample, com o começo dele caindo em [atSec] (segundos
/// da linha do tempo, pelo mapa de andamento).
class SliceSpec {
  final double srcStart, srcEnd, atSec;
  const SliceSpec(this.srcStart, this.srcEnd, this.atSec);
}

/// O que a construção das fatias observou, para contar ao usuário.
class SliceBuildReport {
  /// Fatias cujo rabo a seguinte cortou, fatias com lacuna depois e fatias sobrepostas que não deu
  /// para cortar (curtas demais: soam juntas).
  int trimmed = 0, gaps = 0, overlapping = 0;

  /// O fade original do clipe era maior que a fatia e foi encurtado.
  bool fadeShortened = false;
}

/// Constrói os clipes das fatias de [orig] (que têm de estar em ordem e cobrir o trecho todo do
/// clipe: a primeira começa em `orig.offset` e a última acaba em `orig.offset + orig.length`).
///
/// Emendas encostadas viram crossfade de [microFade] (ver o topo do arquivo). Fatia que passou do
/// começo da seguinte é cortada ali: com [keepTogether], seco (com o fade de [microFade]); sem ele,
/// deixa um rabo de [_ring] que some por baixo do ataque novo. Lacunas ficam em silêncio (o áudio
/// nunca é esticado).
List<AudioClip> buildSlices(AudioClip orig, DawDoc doc, List<SliceSpec> slices, {bool keepTogether = false, SliceBuildReport? report}) {
  final out = <AudioClip>[];
  for (var i = 0; i < slices.length; i++) {
    final sl = slices[i];
    final first = i == 0, last = i == slices.length - 1;
    final len = sl.srcEnd - sl.srcStart;
    final at = math.max(0.0, sl.atSec);
    // o começo encosta no fim da anterior no áudio: crossfade (a fatia começa um pouco antes)
    var head = first ? 0.0 : math.max(0.0, math.min(microFade, math.min(sl.srcStart - orig.offset, len / 2)));
    if (at - head < 0) head = at;
    final startSec = at - head;
    var endSec = at + len;
    var tail = last ? orig.fadeOut : microFade;
    var tailIsOrig = last;
    var trimmedHere = false;
    if (!last) {
      final nextAt = math.max(0.0, slices[i + 1].atSec);
      if (endSec > nextAt + _eps) {
        final cutAt = keepTogether ? nextAt : nextAt + _ring;
        if (cutAt - at >= _minTrimmed) {
          endSec = math.min(endSec, cutAt);
          tail = keepTogether ? microFade : math.min(_ring, endSec - at);
          report?.trimmed++;
          trimmedHere = true;
        } else {
          report?.overlapping++;
        }
      } else if (endSec < nextAt - _eps - microFade) {
        report?.gaps++;
      }
    }
    var length = endSec - startSec;
    var fin = first ? orig.fadeIn : head;
    var fout = tail;
    if (fin + fout > length && fin + fout > 0) {
      if (first && (orig.fadeIn > 0 || (last && orig.fadeOut > 0))) report?.fadeShortened = true;
      final k = length / (fin + fout);
      fin *= k;
      fout *= k;
    }
    out.add(
      AudioClip.fromJson(orig.toJson())
        ..id = newId()
        ..start = _beatAt(doc, startSec, first && (at - doc.secondsAt(orig.start)).abs() < _eps ? orig.start : null)
        ..offset = sl.srcStart - head
        ..length = length
        ..fadeIn = fin
        ..fadeOut = fout
        ..fadeInShape = first ? orig.fadeInShape : _seamShape
        ..fadeOutShape = tailIsOrig && !trimmedHere ? orig.fadeOutShape : (trimmedHere ? FadeShape.linear : _seamShape)
        ..autoFadeIn = first ? orig.autoFadeIn : null
        ..autoFadeOut = tailIsOrig && !trimmedHere ? orig.autoFadeOut : null,
    );
  }
  return out;
}

double _beatAt(DawDoc doc, double sec, double? exact) => exact ?? doc.beatAtSeconds(sec);

/// As fatias de [cuts] sem mover nada: cada uma no lugar que ela já tem no clipe.
List<SliceSpec> specsForCuts(AudioClip clip, DawDoc doc, List<double> cuts) {
  final t0 = doc.secondsAt(clip.start);
  final edges = [clip.offset, ...cuts, clip.offset + clip.length];
  return [for (var i = 0; i + 1 < edges.length; i++) SliceSpec(edges[i], edges[i + 1], t0 + (edges[i] - clip.offset))];
}

// ------------------------------------------------------------------------- remover silêncio

/// Os ajustes de "Remover silêncio".
class SilenceSettings {
  /// Abaixo disto (dBFS, pico a cada 1 ms) é silêncio.
  final double thresholdDb;

  /// Silêncio mais curto que isto (s) fica.
  final double minSilence;

  /// Margem que fica de cada lado do som (s): antes do som que vem e depois do som que passou.
  final double guardBefore, guardAfter;

  /// Fade de entrada e de saída das fatias que sobram (s).
  final double fade;
  const SilenceSettings({this.thresholdDb = -45, this.minSilence = 0.1, this.guardBefore = 0.01, this.guardAfter = 0.02, this.fade = 0.005});
}

/// Trechos (segundos do sample, absolutos) mantidos e removidos, e a soma removida.
class SilencePlan {
  final List<(double, double)> kept, removed;
  const SilencePlan(this.kept, this.removed);
  double get removedSeconds => removed.fold(0.0, (a, r) => a + (r.$2 - r.$1));
  bool get allSilent => kept.isEmpty;
}

/// Acha os silêncios do trecho: blocos de 1 ms com pico abaixo do limiar, em sequência por pelo menos
/// [SilenceSettings.minSilence]; cada silêncio encolhe pelas margens (nas pontas do clipe não há som
/// do outro lado, então a margem só vale onde há) e o que sobra é removido.
SilencePlan planSilence(ClipRange range, SilenceSettings s) {
  final n = range.frames;
  if (n == 0) return const SilencePlan([], []);
  final rate = range.audio.rate;
  final thr = math.pow(10, s.thresholdDb / 20).toDouble();
  final hop = math.max(1, (rate * 0.001).round());
  final chans = range.audio.channels;
  final removedRel = <(double, double)>[];
  var runStart = -1;
  void closeRun(int endFrame) {
    if (runStart < 0) return;
    final rs = runStart, re = endFrame;
    runStart = -1;
    if ((re - rs) / rate + 1e-9 < s.minSilence) return;
    var a = rs / rate, b = re / rate;
    if (rs > 0) a += s.guardAfter;
    if (re < n) b -= s.guardBefore;
    if (b - a >= 0.001) removedRel.add((a, b));
  }

  for (var f = 0; f < n; f += hop) {
    final end = math.min(n, f + hop);
    var peak = 0.0;
    for (final c in chans) {
      for (var i = f; i < end; i++) {
        final v = c[i].abs();
        if (v > peak) peak = v;
      }
    }
    final quiet = !(peak >= thr); // NaN conta como silêncio
    if (quiet) {
      if (runStart < 0) runStart = f;
    } else {
      closeRun(f);
    }
  }
  closeRun(n);
  final dur = n / rate;
  final kept = <(double, double)>[];
  var cursor = 0.0;
  for (final r in removedRel) {
    if (r.$1 > cursor + 1e-9) kept.add((cursor, r.$1));
    cursor = r.$2;
  }
  if (dur > cursor + 1e-9) kept.add((cursor, dur));
  (double, double) abs((double, double) p) => (range.base + p.$1, range.base + p.$2);
  return SilencePlan([for (final k in kept) abs(k)], [for (final r in removedRel) abs(r)]);
}

/// Os clipes dos trechos mantidos: cada um no lugar que já tinha, com os fades de [fade] onde
/// houve corte (nas pontas do clipe valem os fades originais).
List<AudioClip> buildKept(AudioClip orig, DawDoc doc, SilencePlan plan, double fade) {
  final t0 = doc.secondsAt(orig.start);
  final origEnd = orig.offset + orig.length;
  final out = <AudioClip>[];
  for (final (a, b) in plan.kept) {
    final s = (a - orig.offset).abs() < 1e-4 ? orig.offset : math.max(a, orig.offset);
    final e = (b - origEnd).abs() < 1e-4 ? origEnd : math.min(b, origEnd);
    if (e - s <= 0) continue;
    final atStart = s == orig.offset, atEnd = e == origEnd;
    var fin = atStart ? orig.fadeIn : fade, fout = atEnd ? orig.fadeOut : fade;
    final length = e - s;
    if (fin + fout > length && fin + fout > 0) {
      final k = length / (fin + fout);
      fin *= k;
      fout *= k;
    }
    out.add(
      AudioClip.fromJson(orig.toJson())
        ..id = newId()
        ..start = atStart ? orig.start : doc.beatAtSeconds(t0 + (s - orig.offset))
        ..offset = s
        ..length = length
        ..fadeIn = fin
        ..fadeOut = fout
        ..fadeInShape = atStart ? orig.fadeInShape : FadeShape.linear
        ..fadeOutShape = atEnd ? orig.fadeOutShape : FadeShape.linear
        ..autoFadeIn = atStart ? orig.autoFadeIn : null
        ..autoFadeOut = atEnd ? orig.autoFadeOut : null,
    );
  }
  return out;
}

// ------------------------------------------------------------------------- normalizar

/// Pelo que normalizar.
enum NormalizeMode {
  /// Pico de amostra (dBFS): −1 por padrão.
  peak('Pico', -1),

  /// Valor RMS do trecho todo (dBFS): −18 por padrão.
  rms('RMS', -18),

  /// Loudness integrado (LUFS, BS.1770 com os gates): −14 por padrão. Precisa de 400 ms de áudio.
  lufs('LUFS', -14);

  final String label;
  final double defaultTarget;
  const NormalizeMode(this.label, this.defaultTarget);

  String get unit => this == NormalizeMode.lufs ? 'LUFS' : 'dBFS';
}

/// A medida e o ganho para chegar ao alvo.
class NormalizePlan {
  final NormalizeMode mode;
  final double targetDb;

  /// O trecho medido no modo escolhido (dB) e o pico dele (dBFS).
  final double measuredDb, peakDb;

  /// Ganho linear final do clipe (o absoluto: o ganho antigo é substituído) e em dB.
  final double gain;
  double get gainDb => 20 * math.log(gain) / math.ln10;

  /// O teto de +12 dB do ganho do clipe, ou o pico em 0 dBFS, segurou o ganho: o alvo não foi atingido.
  final bool limited;
  final String? limitReason;
  const NormalizePlan(this.mode, this.targetDb, this.measuredDb, this.peakDb, this.gain, this.limited, this.limitReason);
}

double _db(double lin) => lin > 0 && lin.isFinite ? 20 * math.log(lin) / math.ln10 : -200;

/// Pico de amostra do trecho (linear).
double peakOf(ClipRange r) {
  var peak = 0.0;
  for (final c in r.audio.channels) {
    for (var i = 0; i < c.length; i++) {
      final v = c[i].abs();
      if (v > peak) peak = v;
    }
  }
  return peak;
}

/// RMS do trecho (linear), todos os canais juntos.
double rmsOf(ClipRange r) {
  var sum = 0.0, count = 0;
  for (final c in r.audio.channels) {
    for (var i = 0; i < c.length; i++) {
      final v = c[i];
      if (v.isFinite) sum += v * v;
    }
    count += c.length;
  }
  return count == 0 ? 0 : math.sqrt(sum / count);
}

/// A medida do trecho num modo: o valor (dB; LUFS no modo [NormalizeMode.lufs]) e o pico (dBFS).
typedef NormalizeMeasure = ({double measuredDb, double peakDb});

/// Mede o trecho no [mode]. Devolve o motivo (texto) quando não dá: trecho mudo, ou curto demais
/// para o LUFS. A medida não depende do alvo: o diálogo mede uma vez por modo e refaz só a conta.
Future<({NormalizeMeasure? measure, String? error})> measureForNormalize(ClipRange range, NormalizeMode mode) async {
  if (range.isEmpty) return (measure: null, error: 'O clipe é curto demais para medir.');
  final peak = peakOf(range);
  if (!(peak > 1e-7)) return (measure: null, error: 'O trecho do clipe está em silêncio: não há o que normalizar.');
  final peakDb = _db(peak);
  switch (mode) {
    case NormalizeMode.peak:
      return (measure: (measuredDb: peakDb, peakDb: peakDb), error: null);
    case NormalizeMode.rms:
      return (measure: (measuredDb: _db(rmsOf(range)), peakDb: peakDb), error: null);
    case NormalizeMode.lufs:
      final m = await measureLoudness(range.audio.channels, range.audio.rate);
      if (!m.hasLoudness) {
        return (measure: null, error: 'Não deu para medir o LUFS: o trecho tem menos de 400 ms ou está muito baixo. Use o pico ou o RMS.');
      }
      return (measure: (measuredDb: m.integrated, peakDb: peakDb), error: null);
  }
}

/// O ganho que leva a medida [m] ao alvo [targetDb] no [mode], com os tetos.
NormalizePlan normalizePlanFor(NormalizeMode mode, double targetDb, NormalizeMeasure m) {
  var wanted = targetDb - m.measuredDb;
  var limited = false;
  String? reason;
  // fora do pico, o ganho não pode estourar o zero digital do próprio trecho
  if (mode != NormalizeMode.peak && m.peakDb + wanted > 0) {
    wanted = -m.peakDb;
    limited = true;
    reason = 'o pico do clipe chegou a 0 dBFS antes do alvo';
  }
  final capDb = _db(maxClipGain);
  if (wanted > capDb) {
    wanted = capDb;
    limited = true;
    reason = 'o ganho do clipe vai até +12 dB';
  }
  final gain = math.pow(10, wanted / 20).toDouble().clamp(1e-3, maxClipGain).toDouble();
  return NormalizePlan(mode, targetDb, m.measuredDb, m.peakDb, gain, limited, reason);
}

/// Mede o trecho e calcula o ganho que leva [mode] a [targetDb].
Future<({NormalizePlan? plan, String? error})> planNormalize(ClipRange range, NormalizeMode mode, double targetDb) async {
  final r = await measureForNormalize(range, mode);
  if (r.measure == null) return (plan: null, error: r.error);
  return (plan: normalizePlanFor(mode, targetDb, r.measure!), error: null);
}

/// "−3,2 dB" para a tela.
String formatDbPt(double db) {
  final t = db.abs() < 0.05 ? '0,0' : db.abs().toStringAsFixed(1).replaceAll('.', ',');
  return '${db > 0.05 ? '+' : (db < -0.05 ? '−' : '')}$t dB';
}

// ------------------------------------------------------------------------- quantizar

/// Os ajustes de "Quantizar por fatias".
class QuantizeSettings {
  final EditGrid grid;

  /// 0 (não move) a 1 (cai na grade).
  final double strength;
  final double sensitivity;
  final double minGap;

  /// Cada fatia acaba onde a seguinte começa: se ela passa, é cortada seco ali; sem isto, deixa um
  /// rabo curto que some por baixo do ataque novo. Lacunas ficam em silêncio nos dois casos.
  final bool keepTogether;
  const QuantizeSettings({this.grid = EditGrid.sixteenth, this.strength = 1, this.sensitivity = 0.5, this.minGap = 0.05, this.keepTogether = false});
}

/// O plano: as fatias já no lugar novo, e quanto cada uma andou (ms; positivo = mais tarde).
class QuantizePlan {
  final List<SliceSpec> slices;
  final List<double> shiftsMs;
  const QuantizePlan(this.slices, this.shiftsMs);
  int get moved => shiftsMs.where((s) => s.abs() >= 0.5).length;
  double get maxShiftMs => shiftsMs.fold(0.0, (m, s) => math.max(m, s.abs()));
}

/// Corta [clip] nos transientes e leva o começo de cada fatia à linha de grade mais próxima (a
/// [QuantizeSettings.strength] do caminho). As batidas viram segundos pelo mapa de andamento, então
/// a conta vale com andamento variável.
QuantizePlan planQuantize(ClipRange range, AudioClip clip, DawDoc doc, QuantizeSettings s) {
  final cuts = detectCuts(range, clip, doc, sensitivity: s.sensitivity, minGap: s.minGap);
  final t0 = doc.secondsAt(clip.start);
  final edges = [clip.offset, ...cuts, clip.offset + clip.length];
  final g = s.grid.beats;
  final k = s.strength.isFinite ? s.strength.clamp(0.0, 1.0).toDouble() : 1.0;
  final slices = <SliceSpec>[];
  final shifts = <double>[];
  for (var i = 0; i + 1 < edges.length; i++) {
    final fromSec = t0 + (edges[i] - clip.offset);
    final fromBeat = doc.beatAtSeconds(fromSec);
    final target = (fromBeat / g).round() * g;
    final toBeat = math.max(0.0, fromBeat + k * (target - fromBeat));
    final toSec = k == 0 ? fromSec : doc.secondsAt(toBeat);
    slices.add(SliceSpec(edges[i], edges[i + 1], toSec));
    shifts.add((toSec - fromSec) * 1000);
  }
  return QuantizePlan(slices, shifts);
}

// ------------------------------------------------------------------------- aplicar no controlador

/// A chamada das ações no controlador. Cada uma é uma edição só (um passo do desfazer) e devolve o
/// resultado em texto; nenhuma mexe em nada quando não dá.
extension AudioEditing on DawController {
  (DawTrack, AudioClip)? _locateClip(String id) {
    for (final t in doc.tracks) {
      for (final c in t.clips) {
        if (c.id == id) return (t, c);
      }
    }
    return null;
  }

  /// O clipe, o trecho decodificado dele ou o motivo de não dar; [needSlices] recusa warp/inversão.
  ({DawTrack? track, AudioClip? clip, ClipRange? range, String? error}) audioEditTarget(String clipId, {bool needSlices = true}) {
    final f = _locateClip(clipId);
    if (f == null) return (track: null, clip: null, range: null, error: 'O clipe não existe mais.');
    final (t, clip) = f;
    if (needSlices) {
      final why = sliceEditBlocker(clip);
      if (why != null) return (track: t, clip: clip, range: null, error: why);
    }
    final audio = decodedAudio(clip.sample);
    if (audio == null) return (track: t, clip: clip, range: null, error: missingAudioMessage);
    final range = ClipRange.of(audio, clip);
    if (range.isEmpty) return (track: t, clip: clip, range: range, error: 'O trecho deste clipe está fora do áudio.');
    return (track: t, clip: clip, range: range, error: null);
  }

  void _replaceClip(DawTrack t, AudioClip orig, List<AudioClip> pieces, String label) {
    editAs(label, (_) {
      final i = t.clips.indexWhere((c) => c.id == orig.id);
      if (i >= 0) t.clips.removeAt(i);
      t.clips.insertAll(i < 0 ? t.clips.length : i, pieces);
      selectedClip = pieces.first.id;
    });
  }

  /// Divide o clipe em [cuts] (segundos do sample; use [detectCuts]).
  AudioEditResult splitClipAt(String clipId, List<double> cuts) {
    final tg = audioEditTarget(clipId);
    if (tg.error != null) return AudioEditResult(false, tg.error!);
    final clip = tg.clip!;
    final valid = filterCuts(cuts, clip.offset, clip.offset + clip.length, 0);
    if (valid.isEmpty) return const AudioEditResult(false, 'Nenhum corte: o clipe fica como está.');
    if (valid.length + 1 > maxEditPieces) {
      return AudioEditResult(false, 'Fatias demais (${valid.length + 1}; o máximo é $maxEditPieces). Diminua a sensibilidade.');
    }
    final report = SliceBuildReport();
    final pieces = buildSlices(clip, doc, specsForCuts(clip, doc, valid), report: report);
    _replaceClip(tg.track!, clip, pieces, 'Dividir clipe');
    final extra = report.fadeShortened ? ' O fade original do clipe foi encurtado para caber na fatia.' : '';
    return AudioEditResult(true, 'Dividido em ${pieces.length} fatias, com emendas de 2 ms sem mudar o som.$extra', [for (final p in pieces) p.id]);
  }

  /// Tira o silêncio do clipe e deixa a lacuna. Recusa o clipe todo silencioso (não apaga nada).
  AudioEditResult stripClipSilence(String clipId, SilenceSettings s) {
    final tg = audioEditTarget(clipId);
    if (tg.error != null) return AudioEditResult(false, tg.error!);
    final clip = tg.clip!;
    final plan = planSilence(tg.range!, s);
    if (plan.allSilent) {
      return const AudioEditResult(false, 'O clipe todo está abaixo do limiar: nada seria mantido. Suba o limiar ou diminua o silêncio mínimo.');
    }
    if (plan.removed.isEmpty) return const AudioEditResult(false, 'Nenhum silêncio nesses ajustes: o clipe fica como está.');
    if (plan.kept.length > maxEditPieces) {
      return AudioEditResult(false, 'Trechos demais (${plan.kept.length}; o máximo é $maxEditPieces). Aumente o silêncio mínimo.');
    }
    final pieces = buildKept(clip, doc, plan, s.fade);
    if (pieces.isEmpty) return const AudioEditResult(false, 'Nenhum trecho sobrou.');
    _replaceClip(tg.track!, clip, pieces, 'Remover silêncio');
    return AudioEditResult(true, silenceSummary(plan), [for (final p in pieces) p.id]);
  }

  /// Normaliza o ganho do clipe (mede o trecho que ele toca). Vale também para clipe com warp.
  ///
  /// [measured] é a medida que o diálogo já fez (ver [measureForNormalize]): com ela o clipe não é
  /// medido de novo (o LUFS de um clipe longo custa).
  Future<AudioEditResult> normalizeClip(String clipId, NormalizeMode mode, double targetDb, {NormalizeMeasure? measured}) async {
    final tg = audioEditTarget(clipId, needSlices: false);
    if (tg.error != null) return AudioEditResult(false, tg.error!);
    final NormalizePlan plan;
    if (measured != null) {
      plan = normalizePlanFor(mode, targetDb, measured);
    } else {
      final r = await planNormalize(tg.range!, mode, targetDb);
      if (r.plan == null) return AudioEditResult(false, r.error!);
      plan = r.plan!;
    }
    final id = tg.clip!.id;
    if (audioClip(id) == null) return const AudioEditResult(false, 'O clipe não existe mais.');
    setClipGain(id, plan.gain, label: 'Normalizar clipe');
    return AudioEditResult(true, normalizeSummary(plan), [id]);
  }

  /// Quantiza as fatias do clipe (ver [planQuantize]).
  AudioEditResult quantizeClipSlices(String clipId, QuantizeSettings s) {
    final tg = audioEditTarget(clipId);
    if (tg.error != null) return AudioEditResult(false, tg.error!);
    final clip = tg.clip!;
    final plan = planQuantize(tg.range!, clip, doc, s);
    if (plan.slices.length < 2) return const AudioEditResult(false, 'Nenhum transiente achado: não há o que quantizar. Aumente a sensibilidade.');
    if (plan.slices.length > maxEditPieces) {
      return AudioEditResult(false, 'Fatias demais (${plan.slices.length}; o máximo é $maxEditPieces). Diminua a sensibilidade.');
    }
    final report = SliceBuildReport();
    final pieces = buildSlices(clip, doc, plan.slices, keepTogether: s.keepTogether, report: report);
    _replaceClip(tg.track!, clip, pieces, 'Quantizar por fatias');
    return AudioEditResult(true, quantizeSummary(plan, report), [for (final p in pieces) p.id]);
  }
}

// ------------------------------------------------------------------------- textos

String _secs(double s) => s >= 10 ? '${s.toStringAsFixed(1)} s'.replaceAll('.', ',') : '${s.toStringAsFixed(2)} s'.replaceAll('.', ',');

String silenceSummary(SilencePlan p) {
  final n = p.kept.length;
  return '$n ${n == 1 ? 'trecho' : 'trechos'}, ${_secs(p.removedSeconds)} removidos';
}

String _num1(double v) => v.toStringAsFixed(1).replaceAll('.', ',').replaceFirst('-', '−');

String normalizeSummary(NormalizePlan p) {
  final t =
      'Ganho do clipe: ${formatClipGainDb(p.gain)}. ${p.mode.label} medido: ${_num1(p.measuredDb)} ${p.mode.unit}; alvo: ${_num1(p.targetDb)} ${p.mode.unit}.';
  return p.limited ? '$t Limitado porque ${p.limitReason}: o alvo não foi atingido.' : t;
}

String quantizeSummary(QuantizePlan p, SliceBuildReport r) {
  final parts = <String>[
    '${p.slices.length} fatias, ${p.moved} ${p.moved == 1 ? 'movida' : 'movidas'} (até ${p.maxShiftMs.toStringAsFixed(1).replaceAll('.', ',')} ms).',
    if (r.trimmed > 0) '${r.trimmed} ${r.trimmed == 1 ? 'fatia cortada' : 'fatias cortadas'} onde a seguinte entrou por cima.',
    if (r.gaps > 0) '${r.gaps} ${r.gaps == 1 ? 'lacuna ficou' : 'lacunas ficaram'} em silêncio (o áudio não é esticado).',
    if (r.overlapping > 0) '${r.overlapping} ${r.overlapping == 1 ? 'fatia curta soa' : 'fatias curtas soam'} junto com a vizinha.',
  ];
  return parts.join(' ');
}
