/// Ferramentas de produtor sobre listas de notas MIDI: escalas, acordes, arpejo, humanizar e as
/// transformações de seleção do piano roll.
///
/// Tudo aqui é puro (sem widgets nem controlador): as funções recebem notas e devolvem notas
/// novas, sem tocar nas originais. As que transformam uma a uma devolvem a lista alinhada com a
/// entrada (a nota `i` de saída vem da `i` de entrada); as que criam, unem ou removem notas devolvem
/// o conjunto que substitui a entrada. O editor troca as antigas pelas novas numa edição só, o que
/// deixa cada ferramenta desfazível num passo.
library;

import 'dart:math' as math;

import 'model.dart';

/// Diferença abaixo da qual duas posições em batidas contam como a mesma.
const _eps = 1e-6;

/// Tira o ruído de ponto flutuante das somas (tercinas), para o documento não guardar 0.30000000000000004.
double tidyBeats(double v) => (v * 1e9).roundToDouble() / 1e9;

/// Velocidade nos 127 degraus do MIDI (nunca zero: nota com velocidade 0 é nota desligada).
double _vel127(double v) => (v * 127).round().clamp(1, 127) / 127;

int _clampPitch(int p) => p.clamp(0, 127);

// ---------------------------------------------------------------------- escalas

/// Uma escala: os semitons acima da tônica, em ordem.
class Scale {
  final String id, name;
  final List<int> intervals;
  const Scale(this.id, this.name, this.intervals);
}

const scales = <Scale>[
  Scale('major', 'Maior', [0, 2, 4, 5, 7, 9, 11]),
  Scale('minor', 'Menor natural', [0, 2, 3, 5, 7, 8, 10]),
  Scale('harmonicMinor', 'Menor harmônica', [0, 2, 3, 5, 7, 8, 11]),
  Scale('melodicMinor', 'Menor melódica', [0, 2, 3, 5, 7, 9, 11]),
  Scale('dorian', 'Dórico', [0, 2, 3, 5, 7, 9, 10]),
  Scale('phrygian', 'Frígio', [0, 1, 3, 5, 7, 8, 10]),
  Scale('lydian', 'Lídio', [0, 2, 4, 6, 7, 9, 11]),
  Scale('mixolydian', 'Mixolídio', [0, 2, 4, 5, 7, 9, 10]),
  Scale('locrian', 'Lócrio', [0, 1, 3, 5, 6, 8, 10]),
  Scale('pentatonicMajor', 'Pentatônica maior', [0, 2, 4, 7, 9]),
  Scale('pentatonicMinor', 'Pentatônica menor', [0, 3, 5, 7, 10]),
  Scale('blues', 'Blues', [0, 3, 5, 6, 7, 10]),
  Scale('wholeTone', 'Tons inteiros', [0, 2, 4, 6, 8, 10]),
  Scale('diminished', 'Diminuta (tom e semitom)', [0, 2, 3, 5, 6, 8, 9, 11]),
  Scale('chromatic', 'Cromática', [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]),
];

Scale? scaleById(String id) {
  for (final s in scales) {
    if (s.id == id) return s;
  }
  return null;
}

const rootNames = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];

/// A escala escolhida num clipe: tônica (0 = C .. 11 = B) e o tipo. Guardada no JSON do clipe
/// como "tônica:id" (por exemplo "9:minor").
class ClipScale {
  final int root;
  final Scale scale;
  ClipScale(int root, this.scale) : root = root % 12;

  String encode() => '$root:${scale.id}';

  /// Null se o texto é vazio, malformado ou de uma escala que esta versão não conhece.
  static ClipScale? parse(String? s) {
    if (s == null) return null;
    final i = s.indexOf(':');
    if (i <= 0) return null;
    final root = int.tryParse(s.substring(0, i));
    final scale = scaleById(s.substring(i + 1));
    if (root == null || scale == null || root < 0 || root > 11) return null;
    return ClipScale(root, scale);
  }

  String get label => '${rootNames[root]} ${scale.name.toLowerCase()}';

  bool contains(int pitch) => inScale(pitch, root, scale);
  bool isRoot(int pitch) => pitch % 12 == root;
  int snap(int pitch, {bool preferUp = false}) => snapToScale(pitch, root, scale, preferUp: preferUp);
}

bool inScale(int pitch, int root, Scale scale) => scale.intervals.contains(((pitch - root) % 12 + 12) % 12);

/// A nota da escala mais próxima; em empate (a meio caminho entre duas), a de baixo, ou a de cima
/// com [preferUp] (quem arrasta uma nota para cima precisa que o empate ande para cima, senão ela
/// nunca sai da nota de partida).
int snapToScale(int pitch, int root, Scale scale, {bool preferUp = false}) {
  if (inScale(pitch, root, scale)) return pitch;
  for (var d = 1; d <= 6; d++) {
    final down = pitch - d >= 0 && inScale(pitch - d, root, scale), up = pitch + d <= 127 && inScale(pitch + d, root, scale);
    if (preferUp && up) return pitch + d;
    if (down) return pitch - d;
    if (up) return pitch + d;
  }
  return pitch;
}

/// Alturas da escala de [lo] a [hi], em ordem crescente.
List<int> scalePitches(int root, Scale scale, {int lo = 0, int hi = 127}) => [
  for (var p = lo; p <= hi; p++)
    if (inScale(p, root, scale)) p,
];

/// Leva as alturas para a escala (as notas fora dela vão para a mais próxima).
List<MidiNote> snapNotes(List<MidiNote> notes, ClipScale scale) => [for (final n in notes) n.copy()..pitch = scale.snap(n.pitch)];

// ---------------------------------------------------------------------- acordes

class ChordType {
  final String id, name;

  /// Semitons acima da fundamental.
  final List<int> intervals;
  const ChordType(this.id, this.name, this.intervals);
}

const chordTypes = <ChordType>[
  ChordType('maj', 'Maior', [0, 4, 7]),
  ChordType('min', 'Menor', [0, 3, 7]),
  ChordType('dim', 'Diminuto', [0, 3, 6]),
  ChordType('aug', 'Aumentado', [0, 4, 8]),
  ChordType('sus2', 'Sus2', [0, 2, 7]),
  ChordType('sus4', 'Sus4', [0, 5, 7]),
  ChordType('7', 'Sétima (7)', [0, 4, 7, 10]),
  ChordType('maj7', 'Sétima maior (maj7)', [0, 4, 7, 11]),
  ChordType('m7', 'Menor com sétima (m7)', [0, 3, 7, 10]),
  ChordType('m7b5', 'Meio-diminuto (m7b5)', [0, 3, 6, 10]),
  ChordType('dim7', 'Diminuto com sétima (dim7)', [0, 3, 6, 9]),
  ChordType('6', 'Sexta (6)', [0, 4, 7, 9]),
  ChordType('m6', 'Menor com sexta (m6)', [0, 3, 7, 9]),
  ChordType('add9', 'Add9', [0, 4, 7, 14]),
  ChordType('9', 'Nona (9)', [0, 4, 7, 10, 14]),
  ChordType('maj9', 'Nona maior (maj9)', [0, 4, 7, 11, 14]),
  ChordType('m9', 'Menor com nona (m9)', [0, 3, 7, 10, 14]),
  ChordType('5', 'Quinta (power chord)', [0, 7]),
];

/// Acordes montados em terças sobre o grau da escala: só existem com uma escala escolhida.
const diatonicChords = <(String, String, int)>[('dia3', 'Diatônico: tríade', 3), ('dia4', 'Diatônico: sétima', 4), ('dia5', 'Diatônico: nona', 5)];

/// Passa a inversão [inversion] vezes a nota mais grave para cima, uma oitava.
List<int> invertChord(List<int> pitches, int inversion) {
  final p = List.of(pitches)..sort();
  for (var i = 0; i < inversion && p.length > 1; i++) {
    p.add(p.removeAt(0) + 12);
  }
  return p;
}

/// As alturas do acorde [typeId] sobre [base], da mais grave para a mais aguda, com a
/// [inversion]. Os acordes diatônicos (`dia3`, `dia4`, `dia5`) empilham terças da escala a partir
/// do grau em que [base] cai (a nota vai para a escala antes); sem escala valem como o acorde
/// maior. Alturas além do MIDI (0..127) ficam de fora.
List<int> chordPitches(int base, String typeId, {int inversion = 0, ClipScale? scale}) {
  List<int> raw;
  final dia = diatonicChords.where((d) => d.$1 == typeId).firstOrNull;
  if (dia != null && scale != null) {
    final all = scalePitches(scale.root, scale.scale);
    final at = all.indexOf(scale.snap(base));
    // terças são de dois em dois graus; escala pentatônica ou cromática também empilha "de dois em dois"
    raw = [
      for (var i = 0; i < dia.$3; i++)
        if (at >= 0 && at + 2 * i < all.length) all[at + 2 * i],
    ];
  } else {
    final type = chordTypes.where((t) => t.id == typeId).firstOrNull ?? chordTypes.first;
    raw = [for (final i in type.intervals) base + i];
  }
  return [
    for (final p in invertChord(raw, inversion))
      if (p >= 0 && p <= 127) p,
  ];
}

/// Uma nota para cada altura, com o início, a duração e a velocidade de [base].
List<MidiNote> chordNotes(MidiNote base, List<int> pitches) => [for (final p in pitches) base.copy()..pitch = p];

/// Desdobra cada acorde (notas que começam juntas) em arpejo: as notas, da mais grave à mais aguda,
/// dividem a duração do acorde em partes iguais. Nota sozinha fica como está.
List<MidiNote> spreadChords(List<MidiNote> notes) {
  final out = <MidiNote>[];
  for (final g in _groupsByStart(notes)) {
    if (g.length < 2) {
      out.addAll(g.map((n) => n.copy()));
      continue;
    }
    final start = g.first.start;
    final dur = g.map((n) => n.length).reduce(math.max);
    final sorted = List.of(g)..sort((a, b) => a.pitch.compareTo(b.pitch));
    final part = dur / sorted.length;
    for (var i = 0; i < sorted.length; i++) {
      out.add(
        sorted[i].copy()
          ..start = tidyBeats(start + i * part)
          ..length = tidyBeats(part),
      );
    }
  }
  return out;
}

/// Agrupa as notas que começam no mesmo instante, na ordem dos inícios (e, dentro do grupo, na
/// ordem em que vieram).
List<List<MidiNote>> _groupsByStart(List<MidiNote> notes) {
  final sorted = List.of(notes);
  // sort do Dart não é estável: o índice desempata
  final index = {for (var i = 0; i < notes.length; i++) notes[i]: i};
  sorted.sort((a, b) {
    final c = a.start.compareTo(b.start);
    return c != 0 ? c : index[a]!.compareTo(index[b]!);
  });
  final groups = <List<MidiNote>>[];
  for (final n in sorted) {
    if (groups.isNotEmpty && (n.start - groups.last.first.start).abs() < _eps) {
      groups.last.add(n);
    } else {
      groups.add([n]);
    }
  }
  return groups;
}

// ---------------------------------------------------------------------- arpejador

enum ArpPattern {
  up('Subir'),
  down('Descer'),
  upDown('Subir e descer'),
  random('Aleatório'),
  played('Ordem tocada');

  final String label;
  const ArpPattern(this.label);
}

/// Taxas do arpejador em batidas, com o rótulo.
const arpRates = <(String, double)>[
  ('1/4', 1),
  ('1/4T', 2 / 3),
  ('1/8', .5),
  ('1/8T', 1 / 3),
  ('1/16', .25),
  ('1/16T', 1 / 6),
  ('1/32', .125),
  ('1/32T', 1 / 12),
];

/// Arpeja cada acorde (notas que começam juntas; nota sozinha vira uma repetição): dentro da
/// duração do acorde toca uma nota a cada [rate] batidas, percorrendo as alturas segundo o
/// [pattern] em [octaves] oitavas, cada uma com [gate] da taxa de duração e a velocidade média do
/// acorde. O aleatório usa [seed]: a mesma semente dá sempre o mesmo arpejo.
List<MidiNote> arpeggiate(List<MidiNote> notes, {ArpPattern pattern = ArpPattern.up, double rate = .25, int octaves = 1, double gate = 1, int seed = 1}) {
  if (!(rate > 0)) return [for (final n in notes) n.copy()];
  final rng = math.Random(seed);
  final oct = octaves.clamp(1, 4);
  final out = <MidiNote>[];
  for (final g in _groupsByStart(notes)) {
    final start = g.first.start;
    final dur = g.map((n) => n.length).reduce(math.max);
    final vel = g.map((n) => n.velocity).reduce((a, b) => a + b) / g.length;
    // "ordem tocada" respeita a ordem em que as notas vieram; as demais, a altura
    final base = pattern == ArpPattern.played ? g.map((n) => n.pitch).toList() : (g.map((n) => n.pitch).toList()..sort());
    final pool = <int>[
      for (var o = 0; o < oct; o++)
        for (final p in base)
          if (p + 12 * o <= 127) p + 12 * o,
    ];
    if (pool.isEmpty) continue;
    final order = switch (pattern) {
      ArpPattern.down => pool.reversed.toList(),
      // sem repetir as pontas: 1 2 3 2 | 1 2 3 2
      ArpPattern.upDown => pool.length > 2 ? [...pool, ...pool.reversed.skip(1).take(pool.length - 2)] : pool,
      _ => pool,
    };
    // o resto que não completa uma taxa ainda toca, curto, até o fim do acorde
    final steps = math.max(1, ((dur - _eps) / rate).ceil());
    for (var i = 0; i < steps; i++) {
      final at = tidyBeats(start + i * rate);
      if (at >= start + dur - _eps) break;
      final pitch = pattern == ArpPattern.random ? pool[rng.nextInt(pool.length)] : order[i % order.length];
      // a última nota não passa do fim do acorde
      final len = math.min(rate, start + dur - at) * gate.clamp(.05, 1.0);
      out.add(MidiNote(pitch: pitch, start: at, length: tidyBeats(len), velocity: vel));
    }
  }
  return out;
}

// ---------------------------------------------------------------------- seleção

/// Desloca cada nota no tempo (até ±[timing] batidas) e na velocidade (até ±[velocity], em 0..1),
/// tudo vezes [strength]. Determinístico: a mesma [seed] dá o mesmo resultado, e uma nota nunca
/// passa para antes do 0.
List<MidiNote> humanize(List<MidiNote> notes, {double timing = .06, double velocity = .15, double strength = 1, int seed = 1}) {
  final rng = math.Random(seed);
  return [
    for (final n in notes)
      () {
        // as duas sorteadas sempre saem, mesmo com força 0: a semente não depende dos parâmetros
        final a = rng.nextDouble() * 2 - 1, b = rng.nextDouble() * 2 - 1;
        return n.copy()
          ..start = tidyBeats(math.max(0.0, n.start + a * timing * strength))
          ..velocity = _vel127(n.velocity + b * velocity * strength);
      }(),
  ];
}

/// Rampa linear de velocidade do início ao fim da seleção (no tempo, não no índice). Sem [from] e
/// [to], vale a velocidade da primeira e da última nota.
List<MidiNote> velocityRamp(List<MidiNote> notes, {double? from, double? to}) {
  if (notes.isEmpty) return [];
  final first = notes.reduce((a, b) => b.start < a.start ? b : a);
  final last = notes.reduce((a, b) => b.start > a.start ? b : a);
  final v0 = from ?? first.velocity, v1 = to ?? last.velocity;
  final span = last.start - first.start;
  return [for (final n in notes) n.copy()..velocity = span < _eps ? _vel127(v0) : _vel127(v0 + (v1 - v0) * ((n.start - first.start) / span).clamp(0.0, 1.0))];
}

/// Cada nota vai até o início da próxima (a primeira que começa depois dela, de qualquer altura);
/// a última fica como está.
List<MidiNote> legato(List<MidiNote> notes) {
  final starts = notes.map((n) => n.start).toSet().toList()..sort();
  return [
    for (final n in notes)
      () {
        final next = starts.where((s) => s > n.start + _eps).firstOrNull;
        return n.copy()..length = next == null ? n.length : tidyBeats(next - n.start);
      }(),
  ];
}

/// Encurta cada nota para [factor] (0..1) da duração.
List<MidiNote> staccato(List<MidiNote> notes, {double factor = .5}) => [
  for (final n in notes) n.copy()..length = tidyBeats(math.max(1 / 128, n.length * factor)),
];

/// Espelha as notas no tempo (a última vira a primeira) em torno do trecho que elas ocupam.
List<MidiNote> mirrorTime(List<MidiNote> notes) {
  if (notes.isEmpty) return [];
  final lo = notes.map((n) => n.start).reduce(math.min);
  final hi = notes.map((n) => n.end).reduce(math.max);
  return [for (final n in notes) n.copy()..start = tidyBeats(lo + hi - n.end)];
}

/// Espelha as alturas (a mais aguda vira a mais grave) em torno da faixa que elas ocupam.
List<MidiNote> mirrorPitch(List<MidiNote> notes) {
  if (notes.isEmpty) return [];
  final lo = notes.map((n) => n.pitch).reduce(math.min);
  final hi = notes.map((n) => n.pitch).reduce(math.max);
  return [for (final n in notes) n.copy()..pitch = _clampPitch(lo + hi - n.pitch)];
}

/// Multiplica as posições (a partir da primeira nota) e, com [lengths], também as durações.
List<MidiNote> scaleTime(List<MidiNote> notes, double factor, {bool lengths = true}) {
  if (notes.isEmpty || !(factor > 0)) return [for (final n in notes) n.copy()];
  final lo = notes.map((n) => n.start).reduce(math.min);
  return [
    for (final n in notes)
      n.copy()
        ..start = tidyBeats(lo + (n.start - lo) * factor)
        ..length = lengths ? tidyBeats(math.max(1 / 128, n.length * factor)) : n.length,
  ];
}

/// Inverte a ordem das alturas (e velocidades) no tempo, mantendo o ritmo: a melodia toca de trás
/// para frente sobre os mesmos tempos. Notas simultâneas seguem a altura.
List<MidiNote> reverseOrder(List<MidiNote> notes) {
  final order = List.generate(notes.length, (i) => i)
    ..sort((a, b) {
      final c = notes[a].start.compareTo(notes[b].start);
      if (c != 0) return c;
      final p = notes[a].pitch.compareTo(notes[b].pitch);
      return p != 0 ? p : a.compareTo(b);
    });
  final out = [for (final n in notes) n.copy()];
  for (var i = 0; i < order.length; i++) {
    final from = notes[order[order.length - 1 - i]];
    out[order[i]]
      ..pitch = from.pitch
      ..velocity = from.velocity;
  }
  return out;
}

/// Cada nota de duração [unit] (colcheia, por padrão) vira três notas iguais que dividem a
/// duração dela (o efeito de uma tercina de semicolcheia; não muda o ritmo de tercina do compasso). As outras ficam como estão.
List<MidiNote> tripletize(List<MidiNote> notes, {double unit = .5}) {
  final out = <MidiNote>[];
  for (final n in notes) {
    if ((n.length - unit).abs() > 1e-4) {
      out.add(n.copy());
      continue;
    }
    final part = n.length / 3;
    for (var i = 0; i < 3; i++) {
      out.add(
        n.copy()
          ..start = tidyBeats(n.start + i * part)
          ..length = tidyBeats(part),
      );
    }
  }
  return out;
}

/// Corta as notas que atravessam [at] (batidas do clipe) em duas: uma até [at] e outra dali até o
/// fim. As que não atravessam ficam como estão.
List<MidiNote> splitAt(List<MidiNote> notes, double at) {
  final out = <MidiNote>[];
  for (final n in notes) {
    if (n.start + _eps < at && n.end - _eps > at) {
      out.add(n.copy()..length = tidyBeats(at - n.start));
      out.add(
        n.copy()
          ..start = tidyBeats(at)
          ..length = tidyBeats(n.end - at),
      );
    } else {
      out.add(n.copy());
    }
  }
  return out;
}

/// Une notas da mesma altura que se tocam ou se sobrepõem (a seguinte começa até [tolerance]
/// depois do fim da anterior). A nota unida guarda a velocidade da primeira.
List<MidiNote> joinAdjacent(List<MidiNote> notes, {double tolerance = _eps}) {
  final byPitch = <int, List<MidiNote>>{};
  for (final n in notes) {
    byPitch.putIfAbsent(n.pitch, () => []).add(n);
  }
  final out = <MidiNote>[];
  for (final list in byPitch.values) {
    list.sort((a, b) => a.start.compareTo(b.start));
    MidiNote? cur;
    for (final n in list) {
      if (cur != null && n.start <= cur.end + tolerance) {
        final end = math.max(cur.end, n.end);
        cur.length = tidyBeats(end - cur.start);
      } else {
        if (cur != null) out.add(cur);
        cur = n.copy();
      }
    }
    if (cur != null) out.add(cur);
  }
  out.sort((a, b) {
    final c = a.start.compareTo(b.start);
    return c != 0 ? c : a.pitch.compareTo(b.pitch);
  });
  return out;
}

/// Tira as notas repetidas (mesma altura e mesmo início); de cada grupo fica a mais longa (a
/// primeira, se empatam). A ordem das que ficam é a de entrada.
List<MidiNote> removeDuplicates(List<MidiNote> notes) {
  final drop = <int>{};
  for (var i = 0; i < notes.length; i++) {
    if (drop.contains(i)) continue;
    for (var j = i + 1; j < notes.length; j++) {
      if (drop.contains(j) || notes[j].pitch != notes[i].pitch || (notes[j].start - notes[i].start).abs() > _eps) continue;
      if (notes[j].length > notes[i].length + _eps) {
        drop.add(i);
        break;
      }
      drop.add(j);
    }
  }
  return [
    for (var i = 0; i < notes.length; i++)
      if (!drop.contains(i)) notes[i].copy(),
  ];
}

/// Apara as notas da mesma altura que se sobrepõem: a anterior termina onde a seguinte começa.
/// Devolve a lista alinhada com a entrada. Notas que começam juntas não são tocadas (são
/// duplicadas, caso de [removeDuplicates]).
List<MidiNote> trimOverlaps(List<MidiNote> notes) {
  final out = [for (final n in notes) n.copy()];
  final byPitch = <int, List<int>>{};
  for (var i = 0; i < out.length; i++) {
    byPitch.putIfAbsent(out[i].pitch, () => []).add(i);
  }
  for (final ids in byPitch.values) {
    ids.sort((a, b) => out[a].start.compareTo(out[b].start));
    for (var k = 0; k + 1 < ids.length; k++) {
      final a = out[ids[k]], b = out[ids[k + 1]];
      if (b.start - a.start > _eps && a.end > b.start + _eps) a.length = tidyBeats(b.start - a.start);
    }
  }
  return out;
}

/// As duas listas têm as mesmas notas, campo a campo e na mesma ordem (para não gravar uma
/// edição que não mudou nada).
bool sameNotes(List<MidiNote> a, List<MidiNote> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    final x = a[i], y = b[i];
    if (x.pitch != y.pitch || (x.start - y.start).abs() > 1e-9 || (x.length - y.length).abs() > 1e-9 || (x.velocity - y.velocity).abs() > 1e-9) return false;
  }
  return true;
}
