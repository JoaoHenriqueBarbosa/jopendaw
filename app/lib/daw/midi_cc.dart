/// Controles MIDI dos clipes de notas (pitch bend, modulação e pedal de sustain): as funções puras
/// que levam os eventos do documento ao motor, cortam, movem, escalam e afinam o que a gravação
/// capturou. Os eventos moram em [MidiClip.controls]; o motor os toca junto das notas
/// (`engine/src/expression.rs`).
library;

import 'dart:math' as math;

import 'model.dart';

/// Um evento pronto para o motor: faixa, controle, batida absoluta da linha do tempo e valor.
typedef EngineCc = ({int track, int cc, double beat, double value});

/// Folga para batidas que caem "quase" num limite (ponto flutuante).
const _eps = 1e-9;

/// Distância mínima entre dois eventos de um mesmo controle vindos da gravação (1/48 de batida,
/// ~10 ms a 120 bpm): um controlador que manda centenas de valores por segundo não enche o
/// documento com pontos que a mão não distingue.
const recordedControlGap = 1 / 48;

/// O pedal está embaixo a partir de 0,5, como o motor e o MIDI (64 de 127).
bool pedalDown(double value) => value >= 0.5;

/// O valor conta como "fora do repouso": o controle precisa voltar ao neutro quando o clipe acaba.
bool _active(int cc, double value) => cc == ccSustain ? pedalDown(value) : value != MidiCc.neutral;

/// Os eventos dos clipes de todas as faixas de instrumento, na linha do tempo e na ordem em que o
/// motor os aplica (batida, e no mesmo instante os retornos ao repouso de fim de clipe antes dos
/// eventos de um clipe que começa ali). Cada evento é cortado ao trecho do clipe ([0, duração]);
/// fora dele, guardado mas mudo, como as notas. Um controle que o clipe deixa fora do repouso (o
/// pedal embaixo no último evento) volta ao repouso no fim do clipe: sem isso o pedal de um clipe
/// seguraria as notas do resto do projeto.
List<EngineCc> flattenControls(List<DawTrack> tracks) {
  final out = <({EngineCc e, int order, int index})>[];
  var index = 0;
  for (var i = 0; i < tracks.length; i++) {
    final t = tracks[i];
    if (!t.kind.isInstrument) continue;
    for (final c in t.midi) {
      for (final cc in ccKinds) {
        final list = [
          for (final e in c.controls)
            if (e.cc == cc && e.beat.isFinite && e.value.isFinite && e.beat >= -_eps && e.beat <= c.length + _eps) e,
        ];
        if (list.isEmpty) continue;
        // ordem estável: no mesmo instante vale a ordem da lista
        final sorted = [for (var k = 0; k < list.length; k++) (k, list[k])]
          ..sort((a, b) => a.$2.beat.compareTo(b.$2.beat) != 0 ? a.$2.beat.compareTo(b.$2.beat) : a.$1.compareTo(b.$1));
        for (final (_, e) in sorted) {
          out.add((e: (track: i, cc: cc, beat: c.start + math.max(0.0, e.beat), value: MidiCc.clampValue(cc, e.value)), order: 1, index: index++));
        }
        final last = sorted.last.$2;
        if (_active(cc, last.value) && last.beat < c.length - _eps) {
          out.add((e: (track: i, cc: cc, beat: c.start + c.length, value: MidiCc.neutral), order: 0, index: index++));
        }
      }
    }
  }
  out.sort((a, b) {
    final s = a.e.beat.compareTo(b.e.beat);
    if (s != 0) return s;
    return a.order != b.order ? a.order.compareTo(b.order) : a.index.compareTo(b.index);
  });
  return [for (final o in out) o.e];
}

/// O valor do controle [cc] em [beat] (batidas do clipe): o do último evento até ali, ou null se
/// nenhum evento daquele controle veio antes.
double? controlValueAt(List<MidiCc> events, int cc, double beat) {
  MidiCc? best;
  var bestIndex = -1;
  for (var k = 0; k < events.length; k++) {
    final e = events[k];
    if (e.cc != cc || e.beat > beat + _eps) continue;
    if (best == null || e.beat > best.beat || (e.beat == best.beat && k > bestIndex)) {
      best = e;
      bestIndex = k;
    }
  }
  return best?.value;
}

/// Corta os eventos em [cut] (batidas do clipe): à esquerda os anteriores ao corte, à direita os
/// demais, com as batidas contadas do corte. O controle que estava fora do repouso no corte (pedal
/// embaixo, roda ou bend em algum valor) começa o clipe da direita com esse valor: o corte não
/// solta o pedal nem endireita o bend no meio do gesto.
(List<MidiCc>, List<MidiCc>) splitControls(List<MidiCc> events, double cut) {
  final left = <MidiCc>[], right = <MidiCc>[];
  for (final e in events) {
    if (e.beat >= cut - _eps) {
      right.add(e.copy()..beat = math.max(0.0, e.beat - cut));
    } else {
      left.add(e.copy());
    }
  }
  for (final cc in ccKinds) {
    final before = controlValueAt(left, cc, cut);
    if (before == null || !_active(cc, before)) continue;
    if (right.any((e) => e.cc == cc && e.beat <= _eps)) continue;
    right.insert(0, MidiCc(cc: cc, beat: 0, value: before));
  }
  return (left, right);
}

/// Desloca os eventos em [delta] batidas (negativo aproxima do começo do clipe).
void shiftControls(List<MidiCc> events, double delta) {
  for (final e in events) {
    e.beat += delta;
  }
}

/// Multiplica as batidas por [factor] a partir de [origin], como `scaleTime` faz com as notas. Sem
/// [from]/[to], todos os eventos; com eles, só os que caem nesse trecho (o de uma seleção de
/// notas). Nunca passa de antes do começo do clipe.
List<MidiCc> scaleControls(List<MidiCc> events, double factor, double origin, {double? from, double? to}) {
  if (!(factor > 0)) return [for (final e in events) e.copy()];
  return [
    for (final e in events)
      (from != null && to != null && (e.beat < from - _eps || e.beat > to + _eps))
          ? e.copy()
          : (e.copy()..beat = math.max(0.0, _tidy(origin + (e.beat - origin) * factor))),
  ];
}

/// Espelha no tempo o pitch bend e a modulação entre [lo] e [hi] (a curva toca de trás para
/// frente, como as notas). O pedal fica: espelhado, cada "desce" viraria "sobe" e o que era
/// segurado passaria a soltar.
List<MidiCc> mirrorControls(List<MidiCc> events, double lo, double hi) {
  return [for (final e in events) (e.cc == ccSustain || e.beat < lo - _eps || e.beat > hi + _eps) ? e.copy() : (e.copy()..beat = _tidy(lo + hi - e.beat))];
}

double _tidy(double v) => (v * 1e9).roundToDouble() / 1e9;

/// Afina o que a gravação capturou: por controle, no máximo um evento a cada [gap] batidas (dentro
/// da janela, o valor mais recente vence), sem repetir o valor anterior, e sem o primeiro evento se
/// ele só confirma o repouso. O último valor de cada controle (onde a roda parou) sempre fica: ou
/// é um evento ou já é o valor do anterior. O pedal, que só tem dois valores, mantém só as
/// mudanças. Devolve ordenado por batida.
List<MidiCc> thinControls(List<MidiCc> events, {double gap = recordedControlGap}) {
  final out = <MidiCc>[];
  for (final cc in ccKinds) {
    final mine = [
      for (var k = 0; k < events.length; k++)
        if (events[k].cc == cc && events[k].beat.isFinite && events[k].value.isFinite) (k, events[k]),
    ]..sort((a, b) => a.$2.beat.compareTo(b.$2.beat) != 0 ? a.$2.beat.compareTo(b.$2.beat) : a.$1.compareTo(b.$1));
    final windows = <MidiCc>[];
    for (final (_, e) in mine) {
      final v = MidiCc.clampValue(cc, e.value);
      if (cc != ccSustain && windows.isNotEmpty && e.beat - windows.last.beat < gap) {
        windows.last.value = v;
      } else {
        windows.add(MidiCc(cc: cc, beat: e.beat, value: v));
      }
    }
    var state = MidiCc.neutral;
    for (final e in windows) {
      if (cc == ccSustain) {
        final down = pedalDown(e.value);
        if (down == pedalDown(state)) continue;
        state = down ? 1 : 0;
        out.add(MidiCc(cc: cc, beat: e.beat, value: state));
      } else {
        if (e.value == state) continue;
        state = e.value;
        out.add(e);
      }
    }
  }
  out.sort((a, b) => a.beat.compareTo(b.beat));
  return out;
}

/// Acrescenta o valor de repouso ao pedal que ficou embaixo e ao bend/roda que ficaram fora do
/// centro no fim de uma gravação: a mão soltou, mas o controlador pode não ter mandado o último
/// evento. Só para o pedal (o resto continua onde a mão parou, como no MIDI).
List<MidiCc> closePedal(List<MidiCc> events, double end) {
  final out = [for (final e in events) e.copy()];
  final last = controlValueAt(out, ccSustain, end);
  if (last != null && pedalDown(last)) out.add(MidiCc(cc: ccSustain, beat: end, value: 0));
  return out;
}

/// Substitui, no trecho [from]..[to] (batidas do clipe), os eventos do controle [cc] por uma linha
/// reta de ([from], [v0]) a ([to], [v1]) com um ponto a cada [step] batidas. O valor que valia
/// depois do trecho é preservado: um ponto em [to] se o controle tinha outro valor ali.
List<MidiCc> drawControlLine(List<MidiCc> events, int cc, double from, double to, double v0, double v1, {double step = 1 / 8}) {
  final lo = math.min(from, to), hi = math.max(from, to);
  final a = from <= to ? v0 : v1, b = from <= to ? v1 : v0;
  final out = [
    for (final e in events)
      if (!(e.cc == cc && e.beat >= lo - _eps && e.beat <= hi + _eps)) e.copy(),
  ];
  if (hi - lo < _eps) {
    out.add(MidiCc(cc: cc, beat: math.max(0.0, lo), value: MidiCc.clampValue(cc, b)));
    return out;
  }
  if (cc == ccSustain) {
    // o pedal é degrau: uma mudança só, no começo do trecho, com o valor mais próximo do início
    out.add(MidiCc(cc: cc, beat: math.max(0.0, lo), value: pedalDown(a) ? 1 : 0));
    return out;
  }
  final n = math.max(1, ((hi - lo) / step).ceil());
  for (var i = 0; i <= n; i++) {
    final t = i / n;
    out.add(MidiCc(cc: cc, beat: math.max(0.0, _tidy(lo + (hi - lo) * t)), value: MidiCc.clampValue(cc, a + (b - a) * t)));
  }
  return out;
}

/// Iguais nos mesmos campos, na ordem (para o histórico não guardar edição que não mudou nada).
bool sameControls(List<MidiCc> a, List<MidiCc> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].cc != b[i].cc || a[i].beat != b[i].beat || a[i].value != b[i].value) return false;
  }
  return true;
}
