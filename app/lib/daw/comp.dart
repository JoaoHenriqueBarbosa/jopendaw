/// Comping por trecho: escolher, trecho a trecho, qual tomada de uma gravação em loop soa.
///
/// Nada disto entra no documento como campo novo: o resultado de um comp são clipes comuns (um
/// por trecho, cada um com a tomada escolhida como `sample` e a lista `takes` inteira), então o
/// JSON, a sincronização e o arquivo `.jopendaw` seguem como estavam. O "grupo de comp" é
/// derivado: os clipes de uma faixa com a mesma lista de tomadas e o mesmo alinhamento com o
/// áudio (o instante da linha do tempo onde o segundo 0 de cada tomada cairia). Mover um
/// pedaço tira ele do grupo; dividir ou duplicar no mesmo lugar o mantém.
library;

import 'model.dart';

/// Tamanho (s) do crossfade que o comp põe nas emendas entre tomadas diferentes.
const compFade = 0.02;

/// Trecho menor que isto (s) não existe: a borda é puxada para a do vizinho.
const compMinSeg = 1e-3;

/// Um trecho do comp: de [s] a [e] (segundos da linha do tempo) soa a tomada [take].
class CompSeg {
  double s, e;
  int take;

  /// O clipe que já o toca (nulo para o trecho recém-escolhido).
  AudioClip? clip;

  /// Mudou de borda ou de tomada nesta escolha: o clipe precisa ser refeito.
  bool dirty;
  CompSeg(this.s, this.e, this.take, {this.clip, this.dirty = false});
}

/// O conjunto de clipes de uma faixa que formam um comp.
class CompGroup {
  final DawTrack track;

  /// Ordenados por começo.
  final List<AudioClip> clips;
  final List<String> takes;

  /// Instante (s) da linha do tempo onde o segundo 0 das tomadas cairia.
  final double origin;
  CompGroup(this.track, this.clips, this.takes, this.origin);
}

/// Sem warp, reverso, transposição nem loop o clipe é só um pedaço do áudio no lugar dele, e é o único tipo
/// que o comp sabe refatiar.
bool compPlain(AudioClip c) => !c.warp && !c.reverse && c.pitch == 0 && c.loopLength == null;

double _origin(DawDoc d, AudioClip c) => d.tempo.secondsAt(c.start) - c.offset;

bool _sameTakes(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// O grupo de comp de [seed] na faixa [t]; nulo se o clipe não tem tomadas (mais de uma) ou não é liso.
CompGroup? compGroupOf(DawDoc d, DawTrack t, AudioClip seed) {
  if (seed.takes.length < 2 || !compPlain(seed) || !seed.takes.contains(seed.sample)) return null;
  return compGroupByKey(d, t, seed.takes, _origin(d, seed));
}

/// O grupo pela chave (lista de tomadas e origem), o que o modo comp guarda: a chave sobrevive à troca dos clipes.
CompGroup? compGroupByKey(DawDoc d, DawTrack t, List<String> takes, double origin) {
  final list = [
    for (final c in t.clips)
      if (compPlain(c) && _sameTakes(c.takes, takes) && takes.contains(c.sample) && (_origin(d, c) - origin).abs() < 1e-4) c,
  ]..sort((a, b) => a.start.compareTo(b.start));
  if (list.isEmpty) return null;
  return CompGroup(t, list, List.of(takes), origin);
}

/// Início e fim (s) do clipe na linha do tempo.
double clipStartSec(DawDoc d, AudioClip c) => d.tempo.secondsAt(c.start);
double clipEndSec(DawDoc d, AudioClip c) => clipStartSec(d, c) + c.length;

/// Tira do clipe o que o crossfade automático do comp somou (metade da sobreposição de cada lado), devolvendo as bordas ao
/// ponto da emenda e os fades ao que eram antes. É a forma "nominal", de onde as emendas são refeitas.
void compNormalize(DawDoc d, AudioClip c) {
  final ai = c.autoFadeIn, ao = c.autoFadeOut;
  if (ai != null) {
    final h = c.fadeIn / 2;
    final s = clipStartSec(d, c) + h;
    c
      ..start = d.tempo.beatAt(s)
      ..offset += h
      ..length -= h
      ..fadeIn = ai.prevLength
      ..fadeInShape = ai.prevShape
      ..autoFadeIn = null;
  }
  if (ao != null) {
    c
      ..length -= c.fadeOut / 2
      ..fadeOut = ao.prevLength
      ..fadeOutShape = ao.prevShape
      ..autoFadeOut = null;
  }
  if (c.fadeIn + c.fadeOut > c.length) {
    c.fadeIn = c.fadeIn.clamp(0.0, c.length).toDouble();
    c.fadeOut = c.fadeOut.clamp(0.0, c.length - c.fadeIn).toDouble();
  }
}

/// Os trechos do grupo, já na forma nominal (chame [compNormalize] nos clipes antes).
List<CompSeg> compSegments(DawDoc d, CompGroup g) => [
  for (final c in g.clips) CompSeg(clipStartSec(d, c), clipEndSec(d, c), g.takes.indexOf(c.sample), clip: c),
];

/// Os trechos como o usuário os vê, sem mexer no documento: a emenda de um crossfade do comp fica no meio da sobreposição.
List<CompSeg> compView(DawDoc d, CompGroup g) => [
  for (final c in g.clips)
    CompSeg(
      clipStartSec(d, c) + (c.autoFadeIn != null ? c.fadeIn / 2 : 0),
      clipEndSec(d, c) - (c.autoFadeOut != null ? c.fadeOut / 2 : 0),
      g.takes.indexOf(c.sample),
      clip: c,
    ),
];

/// A escolha da tomada [take] no trecho [a]..[b] (segundos) sobre os trechos [segs] (ordenados): o que o trecho cobre sai dos
/// outros (encurta, apara ou parte), o novo entra e vizinhos da mesma tomada se juntam quando um deles mudou.
List<CompSeg> compApply(List<CompSeg> segs, double a, double b, int take) {
  // borda a menos de [compMinSeg] de uma emenda vira a emenda: não sobra trecho minúsculo
  for (final s in segs) {
    if (a > s.s && a - s.s < compMinSeg) a = s.s;
    if (b < s.e && s.e - b < compMinSeg) b = s.e;
  }
  if (b - a < compMinSeg) return segs;
  final out = <CompSeg>[];
  var placed = false;
  void place() {
    if (!placed) out.add(CompSeg(a, b, take, dirty: true));
    placed = true;
  }

  for (final s in segs) {
    if (s.e <= a + 1e-9) {
      out.add(s);
    } else if (s.s >= b - 1e-9) {
      place();
      out.add(s);
    } else {
      if (s.s < a - 1e-9) {
        out.add(CompSeg(s.s, a, s.take, clip: s.clip, dirty: true));
      }
      place();
      if (s.e > b + 1e-9) out.add(CompSeg(b, s.e, s.take, clip: s.clip, dirty: true));
    }
  }
  place();
  // junta vizinhos colados da mesma tomada quando um deles é novo ou foi cortado
  final merged = <CompSeg>[];
  for (final s in out) {
    final p = merged.isEmpty ? null : merged.last;
    if (p != null && p.take == s.take && (p.e - s.s).abs() < 1e-9 && (p.dirty || s.dirty)) {
      p
        ..e = s.e
        ..dirty = true;
    } else {
      merged.add(s);
    }
  }
  return merged;
}
