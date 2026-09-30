/// Sequenciador de passos: a conversão entre a grade (linhas × passos) e as notas de um clipe MIDI.
///
/// A grade é uma VISÃO das mesmas notas do `MidiClip` (não um formato novo): uma linha por nota
/// (peça da bateria ou zona do sampler), um passo por subdivisão. O piano roll, a exportação MIDI
/// e o motor seguem lendo as notas de sempre. Tudo aqui é puro (sem widgets) e trabalha numa lista
/// de notas com posições em batidas contadas do início do clipe.
///
/// Uma nota "está no passo" se a diferença para a posição do passo é de até [stepEps] (1/1000 de
/// batida). Nota fora disso (micro-tempo, humanização) aparece no passo mais próximo, marcada como
/// "fora da grade", e só some se o próprio passo for apagado: editar os outros passos não a toca.
library;

import 'dart:math' as math;

import 'instruments.dart';
import 'model.dart';
import 'sampler_zones.dart';

/// Tolerância (em batidas) para uma nota estar num passo.
const stepEps = 1e-3;

/// Máximo de compassos do padrão.
const maxPatternBars = 8;

/// Velocidades dos três tipos de passo.
const stepNormalVelocity = 0.8;
const stepAccentVelocity = 1.0;
const stepGhostVelocity = 0.3;

enum StepDynamic {
  normal,
  accent,
  ghost;

  double get velocity => switch (this) {
    normal => stepNormalVelocity,
    accent => stepAccentVelocity,
    ghost => stepGhostVelocity,
  };

  String get label => switch (this) {
    normal => 'Normal',
    accent => 'Acento',
    ghost => 'Fantasma',
  };
}

/// Acento a partir de 0,95; fantasma até 0,4.
StepDynamic dynamicOf(double velocity) => velocity >= 0.95 ? StepDynamic.accent : (velocity <= 0.4 ? StepDynamic.ghost : StepDynamic.normal);

/// Resolução do passo: a duração dele em batidas (a semínima vale 1).
class StepResolution {
  final String id, label;
  final double beats;
  const StepResolution(this.id, this.label, this.beats);
}

/// Passos por compasso num 4/4: 4, 8, 12, 16, 24, 32 e 64.
const stepResolutions = <StepResolution>[
  StepResolution('1/4', '1/4', 1),
  StepResolution('1/8', '1/8', 0.5),
  StepResolution('1/8T', '1/8 tercina', 1 / 3),
  StepResolution('1/16', '1/16', 0.25),
  StepResolution('1/16T', '1/16 tercina', 1 / 6),
  StepResolution('1/32', '1/32', 0.125),
  StepResolution('1/64', '1/64', 0.0625),
];

const defaultResolutionId = '1/16';

StepResolution resolutionById(String id) => stepResolutions.firstWhere((r) => r.id == id, orElse: () => stepResolutions[3]);

/// Passos de [bars] compassos de [barBeats] batidas com passo de [step] batidas.
int stepsFor(double barBeats, int bars, double step) => math.max(1, (barBeats * bars / step - 1e-6).ceil());

/// A geometria da grade: [steps] passos de [step] batidas; os passos PARES (o 2º, o 4º... contando de
/// 1, como no manual e na tela; são os índices ímpares contando de 0, `i.isOdd`) saem atrasados de
/// [swing] × [step] (0 a 0,75; 1/3 dá a tercina).
class StepLayout {
  final double step;
  final int steps;
  final double swing;

  const StepLayout({required this.step, required this.steps, this.swing = 0});

  factory StepLayout.of({required double barBeats, required int bars, required double step, double swing = 0}) =>
      StepLayout(step: step, steps: stepsFor(barBeats, bars, step), swing: swing);

  StepLayout withSwing(double s) => StepLayout(step: step, steps: steps, swing: s);

  /// A mesma grade estendida até cobrir [length] batidas (o clipe inteiro), não só os compassos do
  /// padrão: as ações que valem para o clipe todo (swing) usam esta.
  StepLayout covering(double length) => StepLayout(step: step, steps: math.max(steps, stepsFor(length, 1, step)), swing: swing);

  /// Comprimento da grade em batidas.
  double get span => steps * step;

  /// Onde o passo [i] (índice de 0) começa (batidas do início do clipe); o 2º, o 4º... levam o swing.
  double pos(int i) => i * step + (i.isOdd ? swing * step : 0);

  /// O passo mais próximo de [start], mesmo fora da faixa 0..steps-1 (o chamador confere);
  /// -1 para o que começa antes do clipe.
  int nearest(double start) {
    if (start < -stepEps) return -1;
    final i0 = (start / step).round();
    var best = math.max(0, i0 - 1);
    var bestD = (start - pos(best)).abs();
    for (var i = math.max(0, i0 - 1) + 1; i <= i0 + 1; i++) {
      final d = (start - pos(i)).abs();
      if (d < bestD - 1e-12) {
        best = i;
        bestD = d;
      }
    }
    return best;
  }

  /// O passo em que a nota aparece, ou null se cai fora da grade (depois do fim do padrão).
  int? cellOf(double start) {
    final i = nearest(start);
    return i < 0 || i >= steps ? null : i;
  }

  bool onGrid(MidiNote n, int i) => (n.start - pos(i)).abs() <= stepEps;
}

/// Comprimento das notas que a grade cria: o passo, no máximo 1/16 (bateria é disparo).
double stepNoteLength(double step) => math.min(step, 0.25);

/// O que há num passo de uma linha: as notas que caem nele.
class StepHit {
  final int index;
  final List<MidiNote> notes;

  /// Nenhuma das notas está exatamente no passo.
  final bool offGrid;

  StepHit(this.index, this.notes, this.offGrid);

  /// A nota que o passo mostra: a que está no passo, senão a primeira.
  MidiNote get primary => notes.first;
  double get velocity => primary.velocity;
}

/// Os passos ligados de uma linha (a nota [pitch]), por índice.
Map<int, StepHit> readRow(Iterable<MidiNote> notes, int pitch, StepLayout l) {
  final byStep = <int, List<MidiNote>>{};
  for (final n in notes) {
    if (n.pitch != pitch) continue;
    final i = l.cellOf(n.start);
    if (i != null) (byStep[i] ??= []).add(n);
  }
  return {
    for (final e in byStep.entries)
      e.key: () {
        final on = [
          for (final n in e.value)
            if (l.onGrid(n, e.key)) n,
        ];
        return StepHit(e.key, on.isNotEmpty ? [...on, ...e.value.where((n) => !on.contains(n))] : e.value, on.isEmpty);
      }(),
  };
}

/// Liga o passo [i] (só se estiver vazio). Devolve se mudou.
bool addStep(List<MidiNote> notes, int pitch, int i, StepLayout l, double velocity) {
  if (i < 0 || i >= l.steps) return false;
  if (readRow(notes, pitch, l).containsKey(i)) return false;
  notes.add(MidiNote(pitch: pitch, start: l.pos(i), length: stepNoteLength(l.step), velocity: velocity.clamp(0.0, 1.0).toDouble()));
  return true;
}

/// Desliga o passo [i]: some com todas as notas que caem nele (as fora da grade também).
bool removeStep(List<MidiNote> notes, int pitch, int i, StepLayout l) {
  final hit = readRow(notes, pitch, l)[i];
  if (hit == null) return false;
  notes.removeWhere(hit.notes.contains);
  return true;
}

/// Muda a velocidade do passo ligado [i], sem mexer no tempo da nota. Devolve se mudou.
bool setStepVelocity(List<MidiNote> notes, int pitch, int i, StepLayout l, double velocity) {
  final hit = readRow(notes, pitch, l)[i];
  if (hit == null) return false;
  final v = velocity.clamp(0.0, 1.0).toDouble();
  var changed = false;
  for (final n in hit.notes) {
    if (n.velocity != v) {
      n.velocity = v;
      changed = true;
    }
  }
  return changed;
}

bool _inPattern(MidiNote n, StepLayout l) => l.cellOf(n.start) != null;

/// Apaga as linhas [pitches] no padrão. Devolve quantas notas saíram.
int clearRows(List<MidiNote> notes, Set<int> pitches, StepLayout l) {
  final before = notes.length;
  notes.removeWhere((n) => pitches.contains(n.pitch) && _inPattern(n, l));
  return before - notes.length;
}

/// Desloca os passos das linhas [pitches] de [by] passos, dando a volta no padrão. O micro-tempo
/// de uma nota fora da grade acompanha.
bool shiftRows(List<MidiNote> notes, Set<int> pitches, StepLayout l, int by) {
  final k = by % l.steps;
  if (k == 0) return false;
  var changed = false;
  for (final n in notes) {
    if (!pitches.contains(n.pitch)) continue;
    final i = l.cellOf(n.start);
    if (i == null) continue;
    final off = l.onGrid(n, i) ? 0.0 : n.start - l.pos(i);
    n.start = math.max(0.0, l.pos((i + k) % l.steps) + off);
    changed = true;
  }
  return changed;
}

/// Inverte as linhas: o que estava ligado desliga, o vazio liga com [velocity].
void invertRows(List<MidiNote> notes, Set<int> pitches, StepLayout l, {double velocity = stepNormalVelocity}) {
  for (final p in pitches) {
    final row = readRow(notes, p, l);
    for (var i = 0; i < l.steps; i++) {
      final hit = row[i];
      if (hit != null) {
        notes.removeWhere(hit.notes.contains);
      } else {
        addStep(notes, p, i, l, velocity);
      }
    }
  }
}

/// Refaz as linhas ao acaso: cada passo liga com probabilidade [density] (0 a 100), velocidades
/// entre 0,55 e 1.
void randomizeRows(List<MidiNote> notes, Set<int> pitches, StepLayout l, double density, math.Random rnd) {
  clearRows(notes, pitches, l);
  for (final p in pitches) {
    for (var i = 0; i < l.steps; i++) {
      if (rnd.nextDouble() * 100 < density) addStep(notes, p, i, l, 0.55 + 0.45 * rnd.nextDouble());
    }
  }
}

/// Refaz as linhas com um passo a cada [n] (a partir do passo [offset]): quatro no chão, contratempos...
void fillEvery(List<MidiNote> notes, Set<int> pitches, StepLayout l, int n, {int offset = 0, double velocity = stepNormalVelocity}) {
  final every = math.max(1, n);
  clearRows(notes, pitches, l);
  for (final p in pitches) {
    for (var i = math.max(0, offset); i < l.steps; i += every) {
      addStep(notes, p, i, l, velocity);
    }
  }
}

/// Muda o swing das notas que estão nos passos pares (o 2º, o 4º...) ([from] → [to], frações de passo):
/// só as que estão exatamente no passo (no swing de [from]) andam; as fora da grade ficam como estão.
/// Devolve quantas notas se moveram.
int retimeSwing(List<MidiNote> notes, StepLayout l, double from, double to) {
  final a = l.withSwing(from), b = l.withSwing(to);
  var moved = 0;
  for (final n in notes) {
    final i = a.cellOf(n.start);
    if (i == null || !i.isOdd || !a.onGrid(n, i)) continue;
    final s = b.pos(i);
    if (s != n.start) {
      n.start = s;
      moved++;
    }
  }
  return moved;
}

/// O swing (fração de passo, em múltiplos de 1%, 0 a 0,75) que as notas de [notes] já têm nesta
/// resolução. É o que liga o estado do swing ao documento: desfazer, reabrir o projeto ou editar no
/// piano roll mudam as notas, e o swing mostrado acompanha. [l] deve cobrir o clipe inteiro.
///
/// A leitura é conservadora, para não confundir humanização, rolos (1/32 visto em 1/16) ou tercinas
/// com swing: só há swing quando (1) TODAS as notas dos passos pares (o 2º, o 4º... contando de 1;
/// o passo vai de `k·passo` até o próximo) estão no mesmo deslocamento, de 1% a 75% do passo; (2) há
/// ao menos uma nota exatamente num passo ímpar (o 1º, o 3º...); e (3) nenhuma nota dos passos ímpares
/// está fora da grade (se estiver, o desenho não é uma grade com swing, e lê 0), salvo as a meio
/// passo: rolos de 1/32 (nos passos ímpares e nos pares) são ignorados quando os outros pares dão um
/// swing; se só há notas a meio passo nos pares, vale 50% só sem rolo nos ímpares. Notas só nos passos
/// pares, ou todas retas, leem 0 (o swing de um clipe assim só se conhece pela dica guardada no clipe,
/// ver [swingFor]). Não há desempate: em 1/8 uma colcheia reta é 0% e só o deslocamento comum a todas
/// as colcheias de contratempo vira swing (75% é o máximo). Um swing aplicado em 1/16 cai, em 1/8, em
/// passos ímpares fora da grade e lê 0 ali: cada resolução lê o seu (ver [detectSwings]).
double detectSwing(Iterable<MidiNote> notes, StepLayout l) {
  int? pct;
  var evens = 0, halfEvens = 0, halfOdds = 0;
  for (final n in notes) {
    final k = (n.start / l.step + 1e-9).floor();
    if (k < 0) continue;
    final off = n.start - k * l.step;
    if (k.isEven) {
      // passo ímpar (o 1º, o 3º...): reto
      if (off.abs() <= stepEps) {
        evens++;
      } else if ((off - l.step / 2).abs() <= stepEps) {
        halfEvens++; // meio passo num passo ímpar: rolo (1/32 em 1/16), não é swing
      } else {
        return 0;
      }
      continue;
    }
    final p = (off / l.step * 100).round();
    if (p < 0 || p > 75 || (off - p / 100 * l.step).abs() > stepEps) return 0;
    if (p == 50) {
      halfOdds++; // num passo par; pode ser rolo ou swing de 50%: decide-se abaixo
      continue;
    }
    if (pct != null && pct != p) return 0;
    pct = p;
  }
  if (pct == null) {
    // só notas a meio passo nos passos pares: swing de 50% se não há rolo nos ímpares
    if (halfOdds == 0 || halfEvens > 0) return 0;
    pct = 50;
  }
  return evens == 0 ? 0 : pct / 100;
}

/// O swing que o clipe de [clipLength] batidas tem em cada resolução de [stepResolutions] (só as
/// que têm): a grade que leu e o swing. Vai da resolução mais grossa à mais fina, tirando o swing que
/// achou antes de olhar a seguinte: um swing de 40% em 1/16 é também, matematicamente, um de 60% em
/// 1/64, e só o primeiro conta. É um diagnóstico: nada no app tira swing de resoluções que o usuário
/// não escolheu (ver [removeSwing]).
List<(StepLayout, double)> detectSwings(Iterable<MidiNote> notes, double clipLength) {
  final work = [for (final n in notes) n.copy()];
  final out = <(StepLayout, double)>[];
  for (final r in stepResolutions) {
    final l = _fullOf(r.beats, clipLength);
    final sw = detectSwing(work, l);
    if (sw <= 0) continue;
    out.add((l, sw));
    retimeSwing(work, l, sw, 0);
  }
  return out;
}

StepLayout _fullOf(double step, double clipLength) => StepLayout(step: step, steps: stepsFor(clipLength, 1, step));

// ------------------------------------------------------------------------- dica de swing

/// A dica de swing guardada no clipe (`MidiClip.swingHint`): "resolução:pct", p. ex. "1/16:40".
/// Só o "Aplicar swing" a escreve. Serve para o que a leitura das notas não alcança (clipe só com
/// notas nos passos pares, swing de 50% com rolos) e para tirar o swing na resolução em que foi
/// aplicado, mesmo com a grade aberta noutra. Nunca vale sozinha: [validSwingHint] a confere contra
/// as notas, e se elas não batem a dica é ignorada.
String encodeSwingHint(String resolutionId, double swing) => '$resolutionId:${(swing * 100).round()}';

/// A dica decodificada, sem conferir com as notas; null se malformada (ou fora de 1% a 75%).
({StepResolution res, int pct})? parseSwingHint(String? hint) {
  if (hint == null) return null;
  final at = hint.lastIndexOf(':');
  if (at <= 0) return null;
  final pct = int.tryParse(hint.substring(at + 1));
  if (pct == null || pct < 1 || pct > 75) return null;
  final id = hint.substring(0, at);
  for (final r in stepResolutions) {
    if (r.id == id) return (res: r, pct: pct);
  }
  return null;
}

/// A dica conferida com as notas: vale se ao menos uma nota está exatamente num passo par (o 2º, o
/// 4º...) deslocado como ela diz e nenhuma nota está exatamente num passo par sem deslocamento (o
/// desenho não é mais o que o "Aplicar" deixou: editaram o clipe). Notas fora da grade e rolos não
/// contam contra. Devolve a grade inteira do clipe e o swing, ou null.
({StepLayout layout, double swing})? validSwingHint(Iterable<MidiNote> notes, double clipLength, String? hint) {
  final h = parseSwingHint(hint);
  if (h == null) return null;
  final step = h.res.beats;
  final shift = h.pct / 100 * step;
  var matched = 0;
  for (final n in notes) {
    final k = (n.start / step + 1e-9).floor();
    if (k < 0 || k.isEven) continue;
    final off = n.start - k * step;
    if ((off - shift).abs() <= stepEps) {
      matched++;
    } else if (off.abs() <= stepEps) {
      return null;
    }
  }
  return matched == 0 ? null : (layout: _fullOf(step, clipLength), swing: h.pct / 100);
}

/// O swing do clipe na grade [l] (que cobre o clipe inteiro): o da dica, se vale e é desta resolução;
/// senão o que as notas mostram ([detectSwing]).
double swingFor(Iterable<MidiNote> notes, StepLayout l, String? hint) {
  final v = validSwingHint(notes, l.span, hint);
  if (v != null && (v.layout.step - l.step).abs() < 1e-12) return v.swing;
  return detectSwing(notes, l);
}

/// Tira o swing do clipe, só o que se sabe que é dele: o da dica (na resolução em que foi aplicado)
/// e o que as notas mostram em cada uma das [resolutions] (ids; a da grade aberta e a do padrão que
/// entra). Notas que só por acaso formam swing em outra resolução não andam. Devolve quantas notas
/// se moveram.
int removeSwing(List<MidiNote> notes, double clipLength, {String? hint, Iterable<String> resolutions = const []}) {
  var moved = 0;
  final v = validSwingHint(notes, clipLength, hint);
  if (v != null) moved += retimeSwing(notes, v.layout, v.swing, 0);
  for (final id in resolutions.toSet()) {
    final l = _fullOf(resolutionById(id).beats, clipLength);
    final sw = detectSwing(notes, l);
    if (sw > 0) moved += retimeSwing(notes, l, sw, 0);
  }
  return moved;
}

/// Há o que repetir: o padrão é menor que o clipe e tem notas nos primeiros [l].span batidas.
bool canRepeatPattern(List<MidiNote> notes, StepLayout l, double clipLength) {
  final span = l.span;
  if (span <= 0 || clipLength - span < stepEps) return false;
  return notes.any((n) => n.start < span - stepEps);
}

/// Repete o padrão (as notas dos primeiros [l].span batidas) até o fim do clipe de [clipLength]
/// batidas, trocando o que havia depois dele. Sem nada a preencher (padrão do tamanho do clipe ou
/// maior, ou sem nenhuma nota no padrão) não mexe em nada. Devolve quantas repetições entraram.
int repeatPattern(List<MidiNote> notes, StepLayout l, double clipLength) {
  final span = l.span;
  if (!canRepeatPattern(notes, l, clipLength)) return 0;
  final src = [
    for (final n in notes)
      if (n.start < span - stepEps) n.copy(),
  ];
  notes.removeWhere((n) => n.start >= span - stepEps);
  var k = 1;
  for (; k * span < clipLength - stepEps; k++) {
    for (final n in src) {
      final s = n.start + k * span;
      if (s >= clipLength - stepEps) continue;
      notes.add(MidiNote(pitch: n.pitch, start: s, length: math.min(n.length, clipLength - s), velocity: n.velocity));
    }
  }
  return k - 1;
}

/// Um padrão copiado: as notas com o início relativo ao começo do padrão.
class PatternClipboard {
  final double span;
  final List<MidiNote> notes;
  PatternClipboard(this.span, this.notes);
}

PatternClipboard copyPattern(List<MidiNote> notes, Set<int> pitches, StepLayout l) => PatternClipboard(l.span, [
  for (final n in notes)
    if (pitches.contains(n.pitch) && _inPattern(n, l)) n.copy(),
]);

/// Cola por cima do padrão: as linhas [pitches] são trocadas pelas notas copiadas (as delas).
void pastePattern(List<MidiNote> notes, Set<int> pitches, StepLayout l, PatternClipboard clip) {
  clearRows(notes, pitches, l);
  for (final n in clip.notes) {
    if (pitches.contains(n.pitch) && n.start < l.span - stepEps) notes.add(n.copy());
  }
}

/// Ordem das notas no clipe: pelo início (estável), como o resto do app espera.
void sortNotes(List<MidiNote> notes) {
  final indexed = [for (var i = 0; i < notes.length; i++) (i, notes[i])];
  indexed.sort((a, b) {
    final c = a.$2.start.compareTo(b.$2.start);
    return c != 0 ? c : a.$1.compareTo(b.$1);
  });
  for (var i = 0; i < indexed.length; i++) {
    notes[i] = indexed[i].$2;
  }
}

// ------------------------------------------------------------------------------------ linhas

/// Uma linha da grade: a nota MIDI e o nome.
class StepRow {
  final int pitch;
  final String name;
  const StepRow(this.pitch, this.name);
}

/// Ordem das peças da bateria na grade: bumbo, caixa, palmas, chimbais, aro, toms, pratos, cowbell.
const _drumRowOrder = [36, 38, 39, 42, 46, 37, 41, 45, 48, 49, 51, 56];

/// As linhas da bateria: uma por peça de `drumPieces`.
List<StepRow> drumRows() {
  final by = {for (final p in drumPieces) p.pitch: p};
  return [
    for (final pitch in _drumRowOrder)
      if (by[pitch] != null) StepRow(pitch, by[pitch]!.name),
    for (final p in drumPieces)
      if (!_drumRowOrder.contains(p.pitch)) StepRow(p.pitch, p.name),
  ];
}

/// Uma zona "de fatia": do áudio dominante da faixa, de uma nota só e em disparo (one-shot).
bool _sliceLike(SamplerZone x, String dominant) => x.sample == dominant && x.oneShot && x.lo == x.hi;

String _dominantSample(List<SamplerZone> z) {
  final count = <String, int>{};
  for (final x in z) {
    count[x.sample] = (count[x.sample] ?? 0) + 1;
  }
  var best = z.first.sample;
  for (final e in count.entries) {
    if (e.value > count[best]!) best = e.key;
  }
  return best;
}

/// A faixa foi fatiada (Fatiar sample…): duas ou mais zonas do mesmo áudio, cada uma de uma nota só,
/// em disparo (one-shot) e ao menos uma com trecho. Tolera edição: basta a MAIORIA das zonas ser
/// assim (mais da metade), então mexer numa zona (modo, áudio, faixa de notas) só tira a dela de
/// "Fatia N" (ela vira "Zona"), não a faixa inteira. Zonas de áudios diferentes (multi-sample) não
/// contam: levam o nome da zona.
bool isSlicedTrack(DawTrack t) {
  final z = t.zones;
  if (z.length < 2) return false;
  final dominant = _dominantSample(z);
  final like = [
    for (final x in z)
      if (_sliceLike(x, dominant)) x,
  ];
  return like.length >= 2 && like.length * 2 > z.length && like.any((x) => x.start > 0 || x.end > 0);
}

/// As linhas de um sampler com zonas: uma por zona (a nota base, ou a mais próxima dentro da faixa
/// da zona); zonas na mesma nota (camadas de velocidade) dividem a linha. Numa faixa fatiada as zonas
/// de fatia levam "Fatia N" (N é a posição da zona na lista, estável se outra zona muda) e as
/// editadas, "Zona".
List<StepRow> zoneRows(DawTrack t) {
  final out = <StepRow>[];
  final seen = <int>{};
  final sliced = isSlicedTrack(t);
  final dominant = t.zones.isEmpty ? '' : _dominantSample(t.zones);
  for (var i = 0; i < t.zones.length; i++) {
    final z = t.zones[i];
    final pitch = z.root.clamp(z.lo, z.hi);
    if (!seen.add(pitch)) continue;
    final slice = sliced && _sliceLike(z, dominant);
    out.add(StepRow(pitch, slice ? 'Fatia ${i + 1} · ${noteName(pitch)}' : 'Zona · ${noteName(pitch)}'));
  }
  return out;
}

/// As linhas da faixa, ou vazio se a faixa não tem sequenciador de passos (só bateria e sampler
/// com zonas).
List<StepRow> stepRowsOf(DawTrack t) => switch (t.kind) {
  TrackKind.drums => drumRows(),
  TrackKind.sampler => zoneRows(t),
  _ => const [],
};

bool stepsAvailable(DawTrack t) => stepRowsOf(t).isNotEmpty;

// ---------------------------------------------------------------------------------- padrões

/// Uma linha de um padrão de fábrica: a nota, o desenho em texto ('.' vazio, 'x' normal, 'X'
/// acento, 'o' fantasma) e a duração de cada caractere em batidas.
class StepPresetRow {
  final int pitch;
  final String pattern;
  final double step;
  const StepPresetRow(this.pitch, this.pattern, [this.step = 0.25]);
}

class StepPreset {
  final String id, name, about;

  /// Resolução em que a grade abre ao aplicar (id de [stepResolutions]).
  final String resolution;

  /// Compassos do desenho (cada um com 4 tempos de texto; num compasso de outro tamanho o desenho
  /// é cortado ou repetido para caber, ver [presetNotes]).
  final int bars;
  final List<StepPresetRow> rows;
  const StepPreset(this.id, this.name, this.about, this.resolution, this.bars, this.rows);

  /// Comprimento em batidas num 4/4.
  double get span => spanIn(4);

  /// Comprimento em batidas em compassos de [barBeats] batidas.
  double spanIn(double barBeats) => bars * barBeats;
}

const _kick = 36, _snare = 38, _clap = 39, _hatC = 42, _hatO = 46, _rim = 37;

const stepPresets = <StepPreset>[
  StepPreset('four', 'Quatro no chão', 'Bumbo em todo tempo, palmas no 2 e no 4.', '1/16', 1, [
    StepPresetRow(_kick, 'x...x...x...x...'),
    StepPresetRow(_clap, '....x.......x...'),
    StepPresetRow(_hatC, 'x.x.x.x.x.x.x.x.'),
  ]),
  StepPreset('rock', 'Rock', 'Bumbo no 1, no 3 e no passo 11 (o e do 3), caixa no 2 e no 4, chimbal em colcheias.', '1/16', 1, [
    StepPresetRow(_kick, 'x.......x.x.....'),
    StepPresetRow(_snare, '....x.......x...'),
    StepPresetRow(_hatC, 'x.x.x.x.x.x.x.x.'),
  ]),
  StepPreset('funk', 'Funk', 'Bumbo sincopado, caixa com notas fantasma, chimbal em semicolcheias.', '1/16', 1, [
    StepPresetRow(_kick, 'x..x...x..x.....'),
    StepPresetRow(_snare, '....x..o.o..x..o'),
    StepPresetRow(_hatC, 'XxxxXxxxXxxxXxxx'),
  ]),
  StepPreset('hiphop', 'Hip-hop', 'Boom bap: bumbo deslocado, caixa seca e chimbal aberto no fim.', '1/16', 1, [
    StepPresetRow(_kick, 'x.....x..x......'),
    StepPresetRow(_snare, '....x.......x...'),
    StepPresetRow(_hatC, 'x.x.x.x.x.x.x.x.'),
    StepPresetRow(_hatO, '..............x.'),
  ]),
  StepPreset('trap', 'Trap', 'Meio tempo, caixa no 3 e chimbal com rolos em 1/32.', '1/32', 1, [
    StepPresetRow(_kick, 'x.........x.x...'),
    StepPresetRow(_snare, '........x.......'),
    StepPresetRow(_hatC, 'x...x...x...x...x.x.x.x.oxoxxXXX', 0.125),
  ]),
  StepPreset('dembow', 'Reggaeton (dembow)', 'Bumbo em todo tempo e a caixa do dembow (4º e 7º passos de cada meio compasso).', '1/16', 1, [
    StepPresetRow(_kick, 'x...x...x...x...'),
    StepPresetRow(_snare, '...x..x....x..x.'),
    StepPresetRow(_hatC, 'x.x.x.x.x.x.x.x.'),
  ]),
  StepPreset('bossa', 'Bossa nova', 'Clave no aro (3-2), bumbo sincopado e chimbal em colcheias.', '1/16', 1, [
    StepPresetRow(_rim, 'x..x..x...x..x..'),
    StepPresetRow(_kick, 'x..x....x..x....'),
    StepPresetRow(_hatC, 'x.x.x.x.x.x.x.x.'),
  ]),
  StepPreset('house', 'House', 'Bumbo em todo tempo, palmas no 2 e no 4, chimbal aberto no contratempo.', '1/16', 1, [
    StepPresetRow(_kick, 'x...x...x...x...'),
    StepPresetRow(_clap, '....x.......x...'),
    StepPresetRow(_hatO, '..x...x...x...x.'),
    StepPresetRow(_hatC, '.o.o.o.o.o.o.o.o'),
  ]),
  StepPreset('shuffle', 'Shuffle (tercinas)', 'Balanço ternário: três passos por tempo.', '1/8T', 1, [
    StepPresetRow(_kick, 'x.....x.....', 1 / 3),
    StepPresetRow(_snare, '...x.....x..', 1 / 3),
    StepPresetRow(_hatC, 'x.xx.xx.xx.x', 1 / 3),
  ]),
];

/// As notas de um padrão de fábrica, com início em batidas do começo do clipe. O desenho é escrito
/// em compassos de 4 tempos; em compassos de [barBeats] batidas cada compasso do desenho é cortado
/// no tamanho do compasso (3/4 fica com os 3 primeiros tempos) ou repetido até preenchê-lo
/// (compassos maiores que 4).
List<MidiNote> presetNotes(StepPreset p, {double barBeats = 4}) {
  final out = <MidiNote>[];
  for (final r in p.rows) {
    for (var i = 0; i < r.pattern.length; i++) {
      final v = switch (r.pattern[i]) {
        'x' => stepNormalVelocity,
        'X' => stepAccentVelocity,
        'o' => stepGhostVelocity,
        _ => null,
      };
      if (v == null) continue;
      final o = i * r.step;
      final bar = (o / 4 + 1e-9).floor();
      final inBar = o - bar * 4;
      for (var base = 0.0; base < barBeats - stepEps; base += 4) {
        final s = bar * barBeats + base + inBar;
        if (base + inBar >= barBeats - stepEps) break;
        out.add(MidiNote(pitch: r.pitch, start: s, length: stepNoteLength(r.step), velocity: v));
      }
    }
  }
  return out;
}

/// Aplica o padrão de fábrica: troca todas as notas de peças da bateria nos primeiros compassos do
/// padrão (compassos de [barBeats] batidas). Notas de fora do kit e as depois do padrão ficam.
/// Devolve as notas que entraram.
int applyPreset(List<MidiNote> notes, StepPreset p, {double? clipLength, double barBeats = 4}) {
  final kit = {for (final d in drumPieces) d.pitch};
  final span = p.spanIn(barBeats);
  notes.removeWhere((n) => kit.contains(n.pitch) && n.start >= -stepEps && n.start < span - stepEps);
  final add = [
    for (final n in presetNotes(p, barBeats: barBeats))
      if (clipLength == null || n.start < clipLength - stepEps) n,
  ];
  notes.addAll(add);
  return add.length;
}
