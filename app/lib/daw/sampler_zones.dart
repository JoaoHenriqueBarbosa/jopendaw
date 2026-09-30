/// Zonas do sampler (multi-sample) e fatiamento de loops: o modelo do documento e as contas puras.
///
/// Uma zona toca um áudio do projeto numa faixa de notas e numa faixa de velocidade, com nota base,
/// afinação fina, ganho, pan, modo (sustentado ou até o fim), trecho e loop. Sem zonas o sampler é
/// o de sempre (um áudio, uma nota base). O espelho no motor é `engine/src/sampler_zones.rs`
/// (`ZoneDef`): as faixas e os limites daqui são os de lá. O fatiamento (pontos de corte por
/// transientes ou iguais, e as zonas por fatia) só existe aqui em produção, porque é o app que
/// decodifica o áudio e mostra a prévia; o motor guarda uma cópia de referência só nos testes
/// (`sampler_slice_ref.rs`) e os dois lados conferem os mesmos vetores fixos (grupo "paridade com o
/// motor" em `test/sampler_zones_test.dart`).
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../audio/engine_types.dart';

/// Zonas por sampler (o motor ignora as que passam disto).
const maxZones = 128;

/// Fatias de uma vez (2 a 96) e a primeira nota delas (C1).
const minSlices = 2;
const maxSlices = 96;
const firstSliceNote = 24;

/// Grupos de round-robin: 1..63 (0 = nenhum).
const maxZoneGroup = 63;

int _int(Object? v, int def, int lo, int hi) => v is num && v.isFinite ? v.round().clamp(lo, hi) : def;
double _num(Object? v, double def, double lo, double hi) => v is num && v.isFinite ? v.toDouble().clamp(lo, hi) : def;

class SamplerZone {
  String id;

  /// sha-256 do áudio (uma chave de `doc.samples`).
  String sample;

  /// Nota em que o áudio soa na altura original.
  int root;

  /// Faixa de notas (inclusive), 0..127.
  int lo, hi;

  /// Faixa de velocidade (inclusive), 1..127.
  int vlo, vhi;

  /// Afinação fina em cents (−1200..1200) e ganho em dB (−60..24).
  double cents, gainDb;

  /// −1 (esquerda) a 1 (direita); 0 não muda o nível.
  double pan;

  /// Toca o trecho até o fim ignorando o note off (bateria, fatias). Falso: sustentado, com loop
  /// opcional.
  bool oneShot;

  /// Grupo de round-robin (0 = nenhum): zonas do mesmo grupo que casam com a nota se alternam.
  int group;

  /// Trecho do áudio em segundos; [end] ≤ 0 é o fim do áudio.
  double start, end;

  /// Loop do trecho em segundos (só no modo sustentado): vale quando [loopEnd] > [loopStart].
  double loopStart, loopEnd;

  SamplerZone({
    required this.id,
    required this.sample,
    this.root = 60,
    this.lo = 0,
    this.hi = 127,
    this.vlo = 1,
    this.vhi = 127,
    this.cents = 0,
    this.gainDb = 0,
    this.pan = 0,
    this.oneShot = false,
    this.group = 0,
    this.start = 0,
    this.end = 0,
    this.loopStart = 0,
    this.loopEnd = 0,
  }) {
    normalize();
  }

  /// Documento antigo ou de outra versão: o que faltar vira o padrão e o que passar da faixa é
  /// limitado.
  SamplerZone.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String? ?? '',
      sample = j['sample'] as String? ?? '',
      root = _int(j['root'], 60, 0, 127),
      lo = _int(j['lo'], 0, 0, 127),
      hi = _int(j['hi'], 127, 0, 127),
      vlo = _int(j['vlo'], 1, 1, 127),
      vhi = _int(j['vhi'], 127, 1, 127),
      cents = _num(j['cents'], 0, -1200, 1200),
      gainDb = _num(j['gain_db'], 0, -60, 24),
      pan = _num(j['pan'], 0, -1, 1),
      oneShot = j['one_shot'] as bool? ?? false,
      group = _int(j['group'], 0, 0, maxZoneGroup),
      start = _num(j['start'], 0, 0, double.maxFinite),
      end = _num(j['end'], 0, 0, double.maxFinite),
      loopStart = _num(j['loop_start'], 0, 0, double.maxFinite),
      loopEnd = _num(j['loop_end'], 0, 0, double.maxFinite) {
    normalize();
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'sample': sample,
    'root': root,
    'lo': lo,
    'hi': hi,
    'vlo': vlo,
    'vhi': vhi,
    'cents': cents,
    'gain_db': gainDb,
    'pan': pan,
    'one_shot': oneShot,
    'group': group,
    'start': start,
    'end': end,
    'loop_start': loopStart,
    'loop_end': loopEnd,
  };

  /// Põe cada campo na faixa dele; faixas invertidas trocam de ponta.
  void normalize() {
    root = root.clamp(0, 127);
    lo = lo.clamp(0, 127);
    hi = hi.clamp(0, 127);
    if (lo > hi) {
      final t = lo;
      lo = hi;
      hi = t;
    }
    vlo = vlo.clamp(1, 127);
    vhi = vhi.clamp(1, 127);
    if (vlo > vhi) {
      final t = vlo;
      vlo = vhi;
      vhi = t;
    }
    cents = cents.isFinite ? cents.clamp(-1200.0, 1200.0) : 0;
    gainDb = gainDb.isFinite ? gainDb.clamp(-60.0, 24.0) : 0;
    pan = pan.isFinite ? pan.clamp(-1.0, 1.0) : 0;
    group = group.clamp(0, maxZoneGroup);
    start = start.isFinite && start > 0 ? start : 0;
    end = end.isFinite && end > 0 ? end : 0;
    loopStart = loopStart.isFinite && loopStart > 0 ? loopStart : 0;
    loopEnd = loopEnd.isFinite && loopEnd > 0 ? loopEnd : 0;
  }

  bool get hasLoop => !oneShot && loopEnd > loopStart;

  SamplerZone copy({String? id}) => SamplerZone(
    id: id ?? this.id,
    sample: sample,
    root: root,
    lo: lo,
    hi: hi,
    vlo: vlo,
    vhi: vhi,
    cents: cents,
    gainDb: gainDb,
    pan: pan,
    oneShot: oneShot,
    group: group,
    start: start,
    end: end,
    loopStart: loopStart,
    loopEnd: loopEnd,
  );

  /// A chamada `zone_add` do motor (na ordem dos parâmetros do export do wasm). [sampleId] é o id
  /// do áudio no motor (0: ainda não carregado neste aparelho).
  List<Object> engineCall(int track, int sampleId) => [
    'zone_add',
    track,
    sampleId,
    root,
    lo,
    hi,
    vlo,
    vhi,
    cents,
    gainDb,
    pan,
    oneShot ? 1 : 0,
    start,
    end,
    loopStart,
    loopEnd,
    group,
  ];

  /// A nota e a velocidade (1..127) caem na zona.
  bool matches(int pitch, int velocity) => pitch >= lo && pitch <= hi && velocity >= vlo && velocity <= vhi;
}

/// Onde uma zona nova nasce: a faixa de notas, a nota base e, se o teclado já estava todo coberto,
/// a zona que cede metade da faixa dela ([divides]; o controlador encurta a `hi` dela para `lo - 1`).
/// [overlaps]: nem dividir dava (todas as zonas têm uma nota só), a nova fica por cima das outras.
typedef ZonePlacement = ({int lo, int hi, int root, SamplerZone? divides, bool overlaps});

/// A nota base de uma zona nova, quando não se sabe a altura do áudio: o dó central (C4), ou a nota da
/// faixa mais perto dele.
int defaultZoneRoot(int lo, int hi) => 60.clamp(lo, hi);

/// A primeira zona cobre o teclado todo; da segunda em diante cada uma ocupa a maior lacuna que as
/// zonas existentes deixam (nunca por cima de outra). Sem lacuna, divide ao meio a zona de faixa mais
/// larga (a nova fica com a metade de cima); só se nem isso der, sobrepõe uma oitava a partir do C4.
ZonePlacement nextZoneRange(Iterable<SamplerZone> zones) {
  if (zones.isEmpty) return (lo: 0, hi: 127, root: defaultZoneRoot(0, 127), divides: null, overlaps: false);
  final covered = List<bool>.filled(128, false);
  for (final z in zones) {
    for (var n = z.lo; n <= z.hi; n++) {
      covered[n] = true;
    }
  }
  var bestLo = -1, bestLen = 0;
  for (var n = 0; n < 128;) {
    if (covered[n]) {
      n++;
      continue;
    }
    final from = n;
    while (n < 128 && !covered[n]) {
      n++;
    }
    if (n - from > bestLen) {
      bestLen = n - from;
      bestLo = from;
    }
  }
  if (bestLen > 0) {
    final hi = bestLo + bestLen - 1;
    return (lo: bestLo, hi: hi, root: defaultZoneRoot(bestLo, hi), divides: null, overlaps: false);
  }
  SamplerZone? widest;
  for (final z in zones) {
    if (z.hi - z.lo >= 1 && (widest == null || z.hi - z.lo > widest.hi - widest.lo)) widest = z;
  }
  if (widest != null) {
    final lo = widest.lo + (widest.hi - widest.lo + 1) ~/ 2;
    return (lo: lo, hi: widest.hi, root: defaultZoneRoot(lo, widest.hi), divides: widest, overlaps: false);
  }
  return (lo: 60, hi: 72, root: 60, divides: null, overlaps: true);
}

/// As notas que alguma zona cobre (para marcar o teclado da tela).
Set<int> zoneCoveredNotes(Iterable<SamplerZone> zones) => {
  for (final z in zones)
    for (var n = z.lo; n <= z.hi; n++) n,
};

/// Por que não dá para criar outra zona (null: dá). Só há duas causas e a mensagem é uma só: o limite de
/// [maxZones] ou o teclado todo já ocupado por zonas de uma nota só (sem lacuna nem zona para dividir).
String? zoneAddBlocker(Iterable<SamplerZone> zones) {
  if (zones.length >= maxZones || nextZoneRange(zones).overlaps) {
    return 'Não dá para criar outra zona: o limite é de $maxZones zonas ou o teclado já está todo ocupado por zonas de uma nota só. Apague alguma antes.';
  }
  return null;
}

/// As faixas de velocidade de [n] camadas iguais dentro de [lo]..[hi] (padrão 1..127), sem lacuna nem
/// sobreposição (2 sobre 1..127: 1–63 e 64–127; 3: 1–42, 43–84, 85–127; 4: 1–31, 32–63, 64–95, 96–127).
/// [n] fora de 1..127 é limitado e nunca passa do número de valores da faixa (uma faixa de 3 valores dá
/// no máximo 3 camadas); faixa invertida ou fora de 1..127 é ajustada.
List<(int, int)> velocityLayers(int n, {int lo = 1, int hi = 127}) {
  final a = math.min(lo, hi).clamp(1, 127), b = math.max(lo, hi).clamp(1, 127);
  final span = b - a + 1;
  final k = n.clamp(1, 127).clamp(1, span);
  return [for (var i = 0; i < k; i++) (a + (span * i) ~/ k, a + (span * (i + 1)) ~/ k - 1)];
}

/// Lê uma nota digitada: número 0..127 ou nome ("C4", "c#3", "Db-1", "F♯2"; C4 = 60, como nos rótulos do
/// app). Null se não entendeu ou passou de 0..127.
int? parseNoteInput(String text) {
  final t = text.trim().replaceAll('♯', '#').replaceAll('♭', 'b');
  final number = int.tryParse(t);
  if (number != null) return number >= 0 && number <= 127 ? number : null;
  final m = RegExp(r'^([A-Ga-g])([#b]?)(-?\d)$').firstMatch(t);
  if (m == null) return null;
  const base = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11};
  final accidental = m[2] == '#' ? 1 : (m[2] == 'b' ? -1 : 0);
  final n = (int.parse(m[3]!) + 1) * 12 + base[m[1]!.toUpperCase()]! + accidental;
  return n >= 0 && n <= 127 ? n : null;
}

/// Nome de nota "C4" (60) para os rótulos do mapa.
String zoneNoteName(int n) {
  const names = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
  return '${names[n % 12]}${n ~/ 12 - 1}';
}

// ------------------------------------------------------------------------------------ fatiamento

/// Como escolher os cortes: [count] fatias iguais ou, sem ele, um corte em cada transiente
/// ([sensitivity] 0..1). Por transientes, [limit] é o máximo de pontos devolvidos (padrão [maxSlices], os
/// mais fortes; a paridade com o motor vale com o padrão): o diálogo passa um limite alto para saber
/// quantos ataques há de verdade e avisar quando passam do que vira nota.
List<double> slicePoints(DecodedAudio a, {int? count, double sensitivity = 0.5, int limit = maxSlices}) {
  // sem `1 << 62`: na web (dart2js) o deslocamento é de 32 bits e dava 0, então nada era fatiado
  if (a.channels.isEmpty) return const [];
  final n = a.channels.map((c) => c.length).reduce(math.min);
  if (n == 0 || !(a.rate.isFinite && a.rate > 0)) return const [];
  final frames = count != null ? _equalCuts(n, count) : _transientCuts(a.channels, n, a.rate, sensitivity, limit);
  return [for (final f in frames) f / a.rate];
}

List<int> _equalCuts(int n, int count) {
  final k = math.min(count.clamp(minSlices, maxSlices), n);
  final out = <int>[];
  for (var i = 0; i < k; i++) {
    final f = (i * n / k).round();
    if (out.isEmpty || out.last != f) out.add(f);
  }
  return out;
}

const _hopSecs = 0.005;
const _minGapSecs = 0.05;
const _edgeSecs = 0.01;

double _f32(double v) => (Float32List(1)..[0] = v)[0];

/// Cortes por transientes, em quadros: a mesma conta de `transients` em `sampler_zones.rs` (o
/// envelope em log da energia do sinal e da derivada a cada 5 ms; o fluxo positivo contra a média
/// local e o maior pico; máximos locais a 50 ms um do outro; o corte refinado no áudio e recuado
/// ao cruzamento de zero).
List<int> _transientCuts(List<Float32List> channels, int n, double rate, double sensitivity, int limit) {
  final points = <int>[0];
  final hop = math.max(1, (rate * _hopSecs).round());
  final nf = n ~/ hop;
  if (nf < 4) return points;
  final mono = Float32List(n);
  for (var i = 0; i < n; i++) {
    var s = 0.0;
    for (final c in channels) {
      s += c[i];
    }
    mono[i] = s / channels.length;
  }
  final level = List<double>.filled(nf, 0);
  for (var f = 0; f < nf; f++) {
    var e = 0.0, d = 0.0;
    for (var i = f * hop; i < (f + 1) * hop; i++) {
      e += mono[i] * mono[i];
      if (i > f * hop) {
        final diff = _f32(mono[i] - mono[i - 1]);
        d += diff * diff;
      }
    }
    e /= hop;
    d /= hop;
    level[f] = math.log(1 + 1e4 * e) + math.log(1 + 1e4 * d);
  }
  final flux = List<double>.generate(nf, (f) => f == 0 ? 0 : math.max(level[f] - level[f - 1], 0.0));
  final top = flux.fold<double>(0, (a, b) => math.max(a, b));
  if (top < 0.5) return points;
  final prefix = List<double>.filled(nf + 1, 0);
  for (var f = 0; f < nf; f++) {
    prefix[f + 1] = prefix[f] + flux[f];
  }
  final half = math.max(2, 0.2 ~/ _hopSecs);
  final s = sensitivity.isFinite ? sensitivity.clamp(0.0, 1.0).toDouble() : 0.5;
  final relative = 6.0 - 4.5 * s, floor = 1.2 - 0.8 * s, ofTop = 0.30 - 0.22 * s;
  final gap = math.max(1, _minGapSecs ~/ _hopSecs);
  final edge = (_edgeSecs * rate).toInt();

  final found = <(int, double)>[];
  for (var f = 1; f < nf - 1; f++) {
    final v = flux[f];
    if (v < floor || v < ofTop * top) continue;
    final a = math.max(0, f - gap), b = math.min(nf, f + gap + 1);
    var beaten = flux[f - 1] > v || flux[f + 1] >= v;
    for (var k = a; k < b && !beaten; k++) {
      if (flux[k] > v) beaten = true;
    }
    if (beaten) continue;
    final a2 = math.max(0, f - half), b2 = math.min(nf, f + half + 1);
    if (v < relative * (prefix[b2] - prefix[a2]) / (b2 - a2)) continue;
    found.add((_onset(mono, f, hop, rate), v));
  }
  found.sort((x, y) => x.$1.compareTo(y.$1));
  final minGap = (_minGapSecs * rate).toInt() ~/ 2;
  final kept = <(int, double)>[];
  for (final c in found) {
    if (kept.isNotEmpty && c.$1 - kept.last.$1 < minGap) {
      if (c.$2 > kept.last.$2) kept[kept.length - 1] = c;
    } else {
      kept.add(c);
    }
  }
  kept.removeWhere((c) => !(c.$1 > edge && c.$1 + edge < n));
  if (kept.length > limit - 1) {
    kept.sort((x, y) => y.$2.compareTo(x.$2));
    kept.removeRange(math.max(0, limit - 1), kept.length);
    kept.sort((x, y) => x.$1.compareTo(y.$1));
  }
  return points..addAll(kept.map((c) => c.$1));
}

/// Onde o ataque do quadro de envelope [f] começa no áudio.
int _onset(Float32List mono, int f, int hop, double rate) {
  final n = mono.length;
  final from = math.max(0, f - 1) * hop;
  var peak = 0.0;
  for (var i = f * hop; i < math.min((f + 2) * hop, n); i++) {
    peak = math.max(peak, mono[i].abs());
  }
  var at = f * hop;
  for (var i = from; i < math.min((f + 1) * hop, n); i++) {
    if (mono[i].abs() >= 0.1 * peak) {
      at = i;
      break;
    }
  }
  final back = (0.002 * rate).toInt();
  for (var j = at; j >= math.max(at - back, 1); j--) {
    if (j < n && (mono[j - 1] <= 0) != (mono[j] <= 0)) return j;
  }
  return at;
}

/// Uma zona de uma nota por fatia, a partir de [first] (cromático): cada uma toca só a fatia
/// `[pontos[i], pontos[i+1])` até o fim, na altura original (a nota é a base). [points] em segundos,
/// crescentes; repetidos, fora de ordem ou inválidos são pulados; pára em 127 ou em [maxSlices].
List<SamplerZone> sliceZones(String sample, List<double> points, String Function() newId, {int first = firstSliceNote}) {
  final clean = <double>[];
  for (final p in points) {
    if (p.isFinite && p >= 0 && (clean.isEmpty || p > clean.last)) clean.add(p);
  }
  final out = <SamplerZone>[];
  for (var i = 0; i < clean.length && i < maxSlices; i++) {
    final note = first + i;
    if (note > 127) break;
    out.add(
      SamplerZone(id: newId(), sample: sample, root: note, lo: note, hi: note, oneShot: true, start: clean[i], end: i + 1 < clean.length ? clean[i + 1] : 0),
    );
  }
  return out;
}
