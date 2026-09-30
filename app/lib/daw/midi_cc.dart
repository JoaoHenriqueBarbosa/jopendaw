/// Controles MIDI dos clipes de notas (pitch bend, modulação e pedal de sustain): as funções puras
/// que levam os eventos do documento ao motor, cortam, movem, escalam e afinam o que a gravação
/// capturou. Os eventos moram em [MidiClip.controls]; o motor os toca junto das notas
/// (`engine/src/expression.rs`).
library;

import 'dart:math' as math;

import 'instruments.dart' show TrackKind;
import 'model.dart';

/// Um evento pronto para o motor: faixa, controle, batida absoluta da linha do tempo e valor.
typedef EngineCc = ({int track, int cc, double beat, double value});

/// Id do parâmetro "Alcance do bend" de cada instrumento (espelho de `instruments.dart`); a bateria
/// não tem.
int? bendRangeParamId(TrackKind k) => switch (k) {
  TrackKind.synth => 35,
  TrackKind.fm => 42,
  TrackKind.wavetable => 39,
  TrackKind.sampler => 9,
  _ => null,
};

/// Alcance do bend da faixa em semitons (2 se o parâmetro não foi mexido ou o instrumento não tem).
double bendRangeOf(DawTrack t) {
  final id = bendRangeParamId(t.kind);
  return id == null ? 2.0 : t.param(id);
}

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
  final out = <({EngineCc e, int order, int index, double? was})>[];
  var index = 0;
  for (var i = 0; i < tracks.length; i++) {
    final t = tracks[i];
    // a bateria não tem bend, modulação nem pedal: pontos desenhados à mão num clipe dela não vão ao motor
    if (!t.kind.isInstrument || t.kind == TrackKind.drums) continue;
    for (final c in t.midi) {
      for (final cc in ccKinds) {
        final list = [
          for (final e in c.controls)
            if (e.cc == cc && e.beat.isFinite && e.value.isFinite && e.beat >= -_eps && e.beat <= c.length + _eps) e,
        ];
        // o clipe aparado na esquerda (ou coberto por outro) guarda os pontos de antes do começo, mudos:
        // o valor em vigor no começo vale ali, como no corte, senão o pedal seguro sumiria no meio do gesto
        final carried = _valueInForce(c.controls, cc, 0);
        if (carried != null && _active(cc, carried) && !list.any((e) => e.beat <= _eps)) list.insert(0, MidiCc(cc: cc, beat: 0, value: carried));
        if (list.isEmpty) continue;
        // ordem estável: no mesmo instante vale a ordem da lista
        final sorted = [for (var k = 0; k < list.length; k++) (k, list[k])]
          ..sort((a, b) => a.$2.beat.compareTo(b.$2.beat) != 0 ? a.$2.beat.compareTo(b.$2.beat) : a.$1.compareTo(b.$1));
        for (final (_, e) in sorted) {
          out.add((e: (track: i, cc: cc, beat: c.start + math.max(0.0, e.beat), value: MidiCc.clampValue(cc, e.value)), order: 1, index: index++, was: null));
        }
        final last = sorted.last.$2;
        if (_active(cc, last.value) && last.beat < c.length - _eps) {
          out.add((e: (track: i, cc: cc, beat: c.start + c.length, value: MidiCc.neutral), order: 0, index: index++, was: MidiCc.clampValue(cc, last.value)));
        }
      }
    }
  }
  // o repouso do fim de um clipe não vale se o clipe seguinte, colado nele, segue no mesmo estado: o
  // pedal de um clipe cortado em dois não sobe e desce na batida do corte (as notas que ele segura
  // sairiam ali)
  final redundant = {
    for (final r in out)
      if (r.was != null &&
          out.any(
            (o) => o.order == 1 && o.e.track == r.e.track && o.e.cc == r.e.cc && (o.e.beat - r.e.beat).abs() <= _eps && _sameState(r.e.cc, o.e.value, r.was!),
          ))
        r.index,
  };
  out.removeWhere((r) => redundant.contains(r.index));
  out.sort((a, b) {
    final s = a.e.beat.compareTo(b.e.beat);
    if (s != 0) return s;
    return a.order != b.order ? a.order.compareTo(b.order) : a.index.compareTo(b.index);
  });
  return [for (final o in out) o.e];
}

/// Dois valores contam como o mesmo estado do controle (o pedal só tem embaixo e solto).
bool _sameState(int cc, double a, double b) => cc == ccSustain ? pedalDown(a) == pedalDown(b) : a == b;

/// O valor do controle [cc] em [beat] contando os eventos de antes do começo (batidas negativas),
/// ou null se não há nenhum até ali.
double? _valueInForce(List<MidiCc> events, int cc, double beat) => controlValueAt(
  [
    for (final e in events)
      if (e.value.isFinite && e.beat.isFinite) e,
  ],
  cc,
  beat,
);

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

/// Os controles do trecho [lo]..[hi) (batidas do clipe), com as batidas contadas de [lo], para copiar
/// junto das notas. Por controle: os eventos do trecho; o valor que já valia em [lo], se está fora do
/// repouso e nenhum evento cai ali; e o retorno ao repouso em [hi], se o controle termina fora dele
/// (a região colada sozinha não segura o pedal do resto do clipe).
List<MidiCc> copyControls(List<MidiCc> events, double lo, double hi) {
  final out = <MidiCc>[];
  for (final cc in ccKinds) {
    final mine = [
      for (final e in events)
        if (e.cc == cc && e.beat.isFinite && e.value.isFinite && e.beat >= lo - _eps && e.beat < hi - _eps) e,
    ]..sort((a, b) => a.beat.compareTo(b.beat));
    final before = _valueInForce(
      [
        for (final e in events)
          if (e.beat < lo - _eps) e,
      ],
      cc,
      lo,
    );
    final region = <MidiCc>[
      if (before != null && _active(cc, before) && !mine.any((e) => e.beat <= lo + _eps)) MidiCc(cc: cc, beat: 0, value: MidiCc.clampValue(cc, before)),
      for (final e in mine) MidiCc(cc: cc, beat: math.max(0.0, _tidy(e.beat - lo)), value: MidiCc.clampValue(cc, e.value)),
    ];
    if (region.isEmpty) continue;
    if (_active(cc, region.last.value) && hi - lo > _eps) region.add(MidiCc(cc: cc, beat: _tidy(hi - lo), value: MidiCc.neutral));
    out.addAll(region);
  }
  return out;
}

/// Tira os eventos do trecho [lo]..[hi) (o mesmo que [copyControls] copia): o "recortar" das notas
/// leva junto o bend, a modulação e o pedal dali. Depois do trecho nada muda: se tirar os eventos
/// deixaria um controle com outro valor em [hi] (o pedal que soltava dentro do trecho e passaria a
/// ficar preso), entra um evento em [hi] com o valor que valia lá.
List<MidiCc> cutControls(List<MidiCc> events, double lo, double hi) {
  final out = <MidiCc>[];
  for (final e in events) {
    final inside = e.beat.isFinite && e.beat >= lo - _eps && e.beat < hi - _eps;
    if (!inside) out.add(e.copy());
  }
  for (final cc in ccKinds) {
    final was = _valueInForce(events, cc, hi - 2 * _eps);
    final now = _valueInForce(out, cc, hi - 2 * _eps);
    if (was == null) continue;
    // sem nada antes, o controle já estava em repouso: só precisa de ponto se o de antes fica fora dele
    if (now == null ? !_active(cc, was) : _sameState(cc, was, now)) continue;
    if (out.any((e) => e.cc == cc && (e.beat - hi).abs() <= _eps)) continue;
    out.add(MidiCc(cc: cc, beat: _tidy(hi), value: was));
  }
  return out;
}

/// Cola [region] (de [copyControls], batidas contadas do começo do trecho) em [at]: por controle, o
/// que a região traz substitui o que havia entre o primeiro e o último evento colados.
List<MidiCc> pasteControls(List<MidiCc> events, List<MidiCc> region, double at) {
  final out = [for (final e in events) e.copy()];
  for (final cc in ccKinds) {
    final mine = [
      for (final e in region)
        if (e.cc == cc) MidiCc(cc: cc, beat: _tidy(at + e.beat), value: e.value),
    ];
    if (mine.isEmpty) continue;
    final lo = mine.map((e) => e.beat).reduce(math.min), hi = mine.map((e) => e.beat).reduce(math.max);
    out.removeWhere((e) => e.cc == cc && e.beat >= lo - _eps && e.beat <= hi + _eps);
    out.addAll(mine);
  }
  return out;
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

/// Acrescenta o valor de repouso, em [end], ao pedal que ficou embaixo e ao bend e à roda que ficaram
/// fora do centro no fim de uma gravação: a mão soltou (o app devolve tudo ao repouso ao parar), mas o
/// controlador pode não ter mandado o último evento, e sem isso o clipe tocaria o resto dele com o
/// pedal preso ou a nota dobrada.
List<MidiCc> closeControls(List<MidiCc> events, double end) {
  final out = [for (final e in events) e.copy()];
  for (final cc in ccKinds) {
    final last = controlValueAt(out, cc, end);
    if (last != null && _active(cc, last)) out.add(MidiCc(cc: cc, beat: end, value: MidiCc.neutral));
  }
  return out;
}

/// Resolução única dos controles ao vivo, qualquer que seja a origem (roda da tela, faixa de controle,
/// controlador MIDI): o bend em 14 bits normalizados (múltiplos de 1/8192, o centro exato), a
/// modulação em 7 bits (1/127) e o pedal em dois estados.
double quantizeControl(int cc, double v) {
  if (!v.isFinite) return MidiCc.neutral;
  final c = MidiCc.clampValue(cc, v);
  return switch (cc) {
    ccBend => (c * 8192).round() / 8192,
    ccSustain => pedalDown(c) ? 1.0 : 0.0,
    _ => (c * 127).round() / 127,
  };
}

/// Os controles de um clipe aparado à esquerda em [delta] batidas (as batidas do clipe andam [delta] para
/// trás): os de antes do novo começo ficam guardados, com batida negativa, e o estado que valia no novo
/// começo (o pedal seguro, o bend fora do centro) vira um evento em 0, como no corte. Refaz a lista a
/// partir de [orig] (o clipe antes do gesto), então dá para chamar a cada passo do arraste.
List<MidiCc> trimControlsLeft(List<MidiCc> orig, double delta) {
  final out = [for (final e in orig) e.copy()..beat = e.beat - delta];
  carryControls(out, 0);
  return out;
}

/// Garante que o controle em vigor em [at] esteja escrito num evento em [at]: para cada controle fora
/// do repouso ali (por eventos de antes ou de [at]) sem evento exatamente em [at], insere um com esse
/// valor. Usada quando o começo de um clipe anda (o estado do que ficou para trás segue valendo).
void carryControls(List<MidiCc> events, double at) {
  for (final cc in ccKinds) {
    final v = _valueInForce(events, cc, at);
    if (v == null || !_active(cc, v)) continue;
    if (events.any((e) => e.cc == cc && (e.beat - at).abs() <= _eps)) continue;
    events.insert(0, MidiCc(cc: cc, beat: at, value: v));
  }
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
