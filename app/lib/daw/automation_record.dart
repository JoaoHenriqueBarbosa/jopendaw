/// Gravação de automação ao mexer nos controles durante a reprodução (Escrever, Toque e Trava).
///
/// Três camadas:
/// - [simplifyAutoSamples]: o que o gesto produziu (uma amostra por quadro) vira poucos pontos.
///   Ramer-Douglas-Peucker na escala do controle (a mesma em que a curva anda entre pontos), com
///   erro máximo de 0,8% da faixa do controle; parâmetros de opções e inteiros guardam só as
///   trocas, em degrau.
/// - [applyAutoTake]: encaixa esses pontos na automação que já existia. Sobrescreve a região
///   gravada (do primeiro ao último ponto) e mantém os de fora; nos limites insere pontos de valor
///   "antes" e "depois" para a curva vizinha não se deformar (um trecho curvo cortado ao meio é
///   reamostrado, porque a curva de um trecho é medida do começo ao fim dele).
/// - [AutoRecorder]: acompanha o transporte e os controles. Só grava com o transporte tocando (e
///   fora da gravação de áudio/MIDI); cada gesto vira um trecho que entra na automação quando o
///   gesto acaba; o que a passada inteira mudou vai ao histórico como um passo só.
///
/// A raia que está sendo gravada sai do motor (o controle vale o que a mão pôs) e o controle mostra
/// o valor fixo em vez da curva; ao acabar o trecho ela volta, já com o que foi gravado.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'automation_math.dart';
import 'automation_mode.dart';
import 'controller.dart';
import 'model.dart';

/// Faixa, escala e valor fixo de um alvo, na unidade dele (ver `DawController.autoInfo`).
typedef AutoInfo = ({double min, double max, double fixed, AutoWarp? warp, bool stepped});

/// Erro máximo do afinamento: fração da faixa do controle (0,8%, abaixo do 1% que se percebe).
const autoSimplifyTolerance = 0.008;

/// Duração da rampa de volta ao valor automatizado, no Toque (batidas).
const autoTouchRamp = 0.25;

/// Posição 0..1 do valor na escala do controle (a mesma em que a curva anda entre pontos).
double autoNorm(double v, AutoInfo info) {
  final w = info.warp;
  if (w != null) return w.toNorm(v);
  final span = info.max - info.min;
  return span > 0 ? (v - info.min) / span : 0;
}

// ---------------------------------------------------------------------- afinamento

/// Reduz amostras (batida, valor) a poucos pontos, sem passar de [tolerance] (fração da faixa,
/// medida em [norm]) de erro. [stepped]: só as trocas de valor, em degrau (dois pontos na mesma
/// batida). Amostras não finitas ou fora de ordem são ignoradas; na mesma batida vale a última.
List<(double, double)> simplifyAutoSamples(
  List<(double, double)> samples, {
  required double Function(double value) norm,
  double tolerance = autoSimplifyTolerance,
  bool stepped = false,
}) {
  final s = <(double, double)>[];
  for (final p in samples) {
    if (!p.$1.isFinite || !p.$2.isFinite) continue;
    if (s.isNotEmpty) {
      if (p.$1 < s.last.$1) continue;
      if (p.$1 == s.last.$1) {
        s[s.length - 1] = p;
        continue;
      }
    }
    s.add(p);
  }
  if (s.length <= 2) return s;
  if (stepped) {
    final out = [s.first];
    var prev = s.first.$2;
    for (var i = 1; i < s.length; i++) {
      final v = s[i].$2;
      if (v == prev) continue;
      out.add((s[i].$1, prev));
      out.add((s[i].$1, v));
      prev = v;
    }
    if (out.last.$1 < s.last.$1) out.add((s.last.$1, prev));
    return out;
  }
  final n = [for (final p in s) norm(p.$2)];
  final keep = List<bool>.filled(s.length, false);
  keep[0] = keep[s.length - 1] = true;
  final stack = <(int, int)>[(0, s.length - 1)];
  while (stack.isNotEmpty) {
    final (lo, hi) = stack.removeLast();
    if (hi - lo < 2) continue;
    final span = s[hi].$1 - s[lo].$1;
    var worst = -1;
    var err = tolerance;
    for (var i = lo + 1; i < hi; i++) {
      final t = span > 0 ? (s[i].$1 - s[lo].$1) / span : 0.0;
      final d = (n[i] - (n[lo] + (n[hi] - n[lo]) * t)).abs();
      if (d > err) {
        err = d;
        worst = i;
      }
    }
    if (worst < 0) continue;
    keep[worst] = true;
    stack
      ..add((lo, worst))
      ..add((worst, hi));
  }
  return [
    for (var i = 0; i < s.length; i++)
      if (keep[i]) s[i],
  ];
}

// ---------------------------------------------------------------------- encaixe na automação

/// A automação que resulta de gravar [take] (pontos já afinados, em ordem) por cima de [existing]
/// (em ordem; não é alterada).
///
/// - A região é do primeiro ao último ponto do [take]: os pontos antigos dentro dela saem.
/// - Antes: um ponto com o valor que a curva antiga tinha ali (ou [fallback], se não havia
///   automação) faz a curva antiga chegar intacta até o começo da região (degrau se o gesto
///   começou noutro valor).
/// - Depois: no Toque, uma rampa curta ([ramp] batidas; em degrau nos parâmetros [stepped]) até o
///   valor que a curva antiga tinha ali (ou [fallback]); no Escrever e na Trava, um degrau de
///   volta ao que a curva antiga tinha, só se há pontos depois (senão a raia segue no último
///   valor gravado).
List<AutoPoint> applyAutoTake({
  required List<AutoPoint> existing,
  required List<(double, double)> take,
  required AutoMode mode,
  required double fallback,
  AutoWarp? warp,
  bool stepped = false,
  double ramp = autoTouchRamp,
  double Function(double value)? norm,
}) {
  AutoPoint copy(AutoPoint p, {double? curve}) => AutoPoint(beat: p.beat, value: p.value, curve: curve ?? p.curve);
  if (take.isEmpty) return [for (final p in existing) copy(p)];
  final ex = existing;
  final hasOrig = ex.isNotEmpty;
  final s = take.first.$1, e = take.last.$1;
  final touch = mode == AutoMode.touch;
  final edge = touch && !stepped ? e + ramp : e;
  double n(double v) => norm != null ? norm(v) : (warp != null ? warp.toNorm(v) : v);
  bool same(double a, double b) => (n(a) - n(b)).abs() < 1e-4;

  var leftEnd = 0;
  while (leftEnd < ex.length && ex[leftEnd].beat < s) {
    leftEnd++;
  }
  var rightStart = ex.length;
  while (rightStart > 0 && ex[rightStart - 1].beat > edge) {
    rightStart--;
  }
  final hasRight = rightStart < ex.length;

  final out = <AutoPoint>[];
  for (var i = 0; i < leftEnd; i++) {
    out.add(copy(ex[i]));
  }
  // o valor que a curva antiga tinha logo antes de s
  double before() {
    if (!hasOrig) return fallback;
    if (leftEnd == 0) return ex.first.value;
    if (leftEnd < ex.length) return autoSegment(ex[leftEnd - 1], ex[leftEnd], s, warp);
    return ex[leftEnd - 1].value;
  }

  // o trecho curvo que a região corta ao meio: reamostrado em retas, senão a curva mudaria de forma
  if (leftEnd > 0 && leftEnd < ex.length && ex[leftEnd - 1].curve != 0 && s - ex[leftEnd - 1].beat > 1e-9) {
    final a = ex[leftEnd - 1], q = ex[leftEnd];
    out.last.curve = 0;
    final k = ((s - a.beat) * 8).ceil().clamp(2, 32);
    for (var i = 1; i < k; i++) {
      final b = a.beat + (s - a.beat) * i / k;
      out.add(AutoPoint(beat: b, value: autoSegment(a, q, b, warp)));
    }
  }
  final pre = before();
  if (s > 1e-9 && !same(pre, take.first.$2)) out.add(AutoPoint(beat: s, value: pre));
  for (final (b, v) in take) {
    out.add(AutoPoint(beat: b, value: v));
  }

  if (touch || hasRight) {
    final at = touch ? edge : e;
    final v = autoValueAt(ex, at, fallback, warp: warp);
    // o ponto da curva antiga que abre o trecho cortado do outro lado da região
    var p = -1;
    for (var i = 0; i < ex.length && ex[i].beat <= at; i++) {
      p = i;
    }
    final curved = hasRight && p >= 0 && ex[p].curve != 0;
    if (curved || at > e || !same(v, take.last.$2)) out.add(AutoPoint(beat: at, value: v));
    if (curved) {
      final q = ex[rightStart];
      final k = ((q.beat - at) * 8).ceil().clamp(2, 32);
      for (var i = 1; i < k; i++) {
        final b = at + (q.beat - at) * i / k;
        out.add(AutoPoint(beat: b, value: autoSegment(ex[p], q, b, warp)));
      }
    }
  }
  for (var i = rightStart; i < ex.length; i++) {
    out.add(copy(ex[i]));
  }
  return out;
}

// ---------------------------------------------------------------------- o gravador

class _Seg {
  final samples = <(double, double)>[];

  void add(double beat, double value) {
    if (samples.isNotEmpty) {
      final last = samples.last;
      if (beat < last.$1) return;
      if (beat == last.$1) {
        samples[samples.length - 1] = (beat, value);
        return;
      }
    }
    samples.add((beat, value));
  }
}

class _Live {
  _Live(this.track, this.target, this.mode, this.info) : last = info.fixed, fallback = info.fixed;
  final int track;
  final AutoTarget target;
  AutoMode mode;
  final AutoInfo info;

  /// O valor fixo do controle antes da primeira mexida: para onde o Toque volta se não havia automação.
  final double fallback;

  /// O último valor que o controle teve.
  double last;

  /// O controle está seguro (Toque e Trava).
  bool held = false;

  /// O trecho em gravação (null: tocou no controle e ainda não mudou nada).
  _Seg? seg;
}

class AutoRecorder extends ChangeNotifier {
  AutoRecorder(this.c) {
    c.playing.addListener(_onPlaying);
    c.beat.addListener(_onBeat);
  }

  final DawController c;

  /// O modo da barra: vale para as raias sem modo próprio.
  AutoMode mode = AutoMode.read;

  /// Modo próprio por raia (id da raia); só existe na sessão, não vai para o projeto.
  final laneModes = <String, AutoMode>{};

  /// Aviso inline (controle sem automação, gravação de áudio em curso); some sozinho.
  String? notice;
  Timer? _noticeTimer;

  final _live = <String, _Live>{};
  final _rejected = <String>{};
  String? _snapshot;
  bool _dirty = false;
  double _lastBeat = 0;
  bool _swallow = false;

  void setMode(AutoMode m) {
    if (m == mode) return;
    mode = m;
    if (c.playing.value) _endSession();
    notifyListeners();
  }

  void setLaneMode(String laneId, AutoMode? m) {
    if (m == null) {
      laneModes.remove(laneId);
    } else {
      laneModes[laneId] = m;
    }
    if (c.playing.value) _endSession();
    notifyListeners();
  }

  /// O modo que vale para o alvo: o da raia dele, se tem, senão o da barra.
  AutoMode modeFor(int track, AutoTarget target) {
    final lane = c.autoLaneOf(track, target);
    return (lane == null ? null : laneModes[lane.id]) ?? mode;
  }

  /// O alvo está sendo gravado agora: o controle mostra o valor fixo e a raia sai do motor.
  bool isRecording(int track, AutoTarget target) => _live[_key(track, target)]?.seg != null;

  /// Alguma raia em gravação (o motor precisa saber quais tirar).
  bool get active => _live.values.any((e) => e.seg != null);

  static String _key(int track, AutoTarget t) => '$track|${t.kind.index}|${t.ref}|${t.param}';

  void _warn(String text) {
    notice = text;
    _noticeTimer?.cancel();
    _noticeTimer = Timer(const Duration(seconds: 5), () {
      notice = null;
      notifyListeners();
    });
    notifyListeners();
  }

  bool _canRecord() {
    if (!c.playing.value) return false;
    if (c.recording || c.countingIn) {
      _warn('A automação não grava junto com a gravação de áudio ou MIDI.');
      return false;
    }
    return true;
  }

  _Live? _entryFor(int track, AutoTarget target, AutoMode m) {
    final k = _key(track, target);
    final ex = _live[k];
    if (ex != null) return ex;
    if (_rejected.contains(k)) return null;
    final info = c.autoInfo(track, target);
    if (info == null || !c.automatable(track).any((e) => e.$1 == target)) {
      _rejected.add(k);
      _warn('Este controle não tem automação.');
      return null;
    }
    return _live[k] = _Live(track, target, m, info);
  }

  // ---- gestos

  /// O controle foi agarrado (chame antes do `checkpoint` do gesto: o ponto de desfazer do gesto é
  /// absorvido, o da passada inteira entra quando o transporte para).
  void touch(int track, AutoTarget target) {
    final m = modeFor(track, target);
    if (!m.records || !_canRecord()) return;
    final e = _entryFor(track, target, m);
    if (e == null) return;
    e.mode = m;
    e.held = true;
    _snapshot ??= c.autoSnapshot();
    _swallow = true;
    scheduleMicrotask(() => _swallow = false);
  }

  /// O controle mudou para [v] (chamado pelos setters, antes de o valor entrar no documento).
  void value(int track, AutoTarget target, double v) {
    if (!v.isFinite || !c.playing.value) return;
    final m = modeFor(track, target);
    if (!m.records || !_canRecord()) return;
    final fresh = !_live.containsKey(_key(track, target));
    final e = _entryFor(track, target, m);
    if (e == null) return;
    if (fresh) {
      // sem `touch` antes: o ponto de desfazer que o gesto acabou de guardar é o de antes de tudo
      final popped = c.autoTakeCheckpoint();
      _snapshot ??= popped ?? c.autoSnapshot();
      e.held = true;
    }
    e.mode = m;
    final val = v.clamp(e.info.min, e.info.max).toDouble();
    e.last = val;
    final beat = c.beat.value;
    final opening = e.seg == null;
    (e.seg ??= _Seg()).add(beat, val);
    if (opening) c.autoSyncNow();
  }

  /// O controle foi solto. O Toque acaba aqui (e volta ao valor automatizado); Escrever e Trava
  /// seguem até o transporte parar.
  void release(int track, AutoTarget target) {
    final e = _live[_key(track, target)];
    if (e == null) return;
    e.held = false;
    if (e.mode == AutoMode.touch) _finish(e);
  }

  /// Todos os controles soltos (o último dedo levantou).
  void releaseAll() {
    for (final e in _live.values.toList()) {
      e.held = false;
      if (e.mode == AutoMode.touch) _finish(e);
    }
  }

  /// Para o `checkpoint` do gesto que acabou de ser anunciado por [touch].
  bool consumeSwallow() {
    final s = _swallow;
    _swallow = false;
    return s;
  }

  // ---- transporte

  void _onPlaying() {
    if (c.playing.value) {
      _lastBeat = c.beat.value;
      _startWrites();
    } else {
      _endSession();
    }
  }

  /// Raias com modo próprio Escrever gravam desde o começo da reprodução.
  void _startWrites() {
    if (c.recording || c.countingIn || laneModes.isEmpty) return;
    var started = false;
    void scan(int track, List<AutoLane> lanes) {
      for (final l in lanes) {
        if (laneModes[l.id] != AutoMode.write) continue;
        final e = _entryFor(track, l.target, AutoMode.write);
        if (e == null || e.seg != null) continue;
        e.mode = AutoMode.write;
        e.seg = _Seg()..add(c.beat.value, e.last);
        started = true;
      }
    }

    for (var i = 0; i < c.doc.tracks.length; i++) {
      scan(i, c.doc.tracks[i].lanes);
    }
    scan(-1, c.doc.masterLanes);
    if (started) {
      _snapshot ??= c.autoSnapshot();
      c.autoSyncNow();
    }
  }

  void _onBeat() {
    final b = c.beat.value, prev = _lastBeat;
    _lastBeat = b;
    if (_live.isEmpty || !c.playing.value || !b.isFinite) return;
    final jumped = b < prev - 1e-6;
    for (final e in _live.values.toList()) {
      final seg = e.seg;
      if (seg == null || !e.last.isFinite) continue;
      if (!jumped) {
        seg.add(b, e.last);
        continue;
      }
      // o loop deu a volta (ou o cursor voltou): a volta que acabou entra na automação e a
      // seguinte começa do zero; onde as duas se cobrem, a última vale
      final le = c.doc.loopEnd;
      if (c.doc.loopOn && le > prev && le - prev < 1) seg.add(le, e.last);
      e.seg = _Seg()..add(b, e.last);
      _apply(e, seg, wrapped: true);
    }
  }

  /// Acaba o trecho: entra na automação e o alvo volta ao motor.
  void _finish(_Live e) {
    _live.remove(_key(e.track, e.target));
    final seg = e.seg;
    if (seg == null) return;
    seg.add(c.beat.value, e.last);
    _apply(e, seg);
    notifyListeners();
  }

  void _apply(_Live e, _Seg seg, {bool wrapped = false}) {
    final info = c.autoInfo(e.track, e.target);
    if (info == null) return;
    final take = simplifyAutoSamples(
      [for (final (b, v) in seg.samples) (b, v.clamp(info.min, info.max).toDouble())],
      norm: (v) => autoNorm(v, info),
      stepped: info.stepped,
    );
    if (take.isEmpty) return;
    // uma volta do loop que continua na seguinte não "volta ao automatizado" no fim
    final m = wrapped && e.mode == AutoMode.touch ? AutoMode.latch : e.mode;
    c.autoApply(
      e.track,
      e.target,
      (existing) =>
          applyAutoTake(existing: existing, take: take, mode: m, fallback: e.fallback, warp: info.warp, stepped: info.stepped, norm: (v) => autoNorm(v, info)),
    );
    _dirty = true;
  }

  /// O transporte parou (ou o modo mudou): fecha o que estava aberto e guarda a passada inteira
  /// como um passo do histórico.
  void _endSession() {
    final entries = _live.values.toList();
    _live.clear();
    final b = c.beat.value;
    for (final e in entries) {
      final seg = e.seg;
      if (seg == null) continue;
      if (e.last.isFinite) seg.add(b, e.last);
      _apply(e, seg);
    }
    final snap = _snapshot;
    if (_dirty && snap != null) c.autoCommitUndo(snap);
    _snapshot = null;
    _dirty = false;
    _rejected.clear();
    if (entries.isNotEmpty) notifyListeners();
  }

  @override
  void dispose() {
    _noticeTimer?.cancel();
    c.playing.removeListener(_onPlaying);
    c.beat.removeListener(_onBeat);
    super.dispose();
  }

  @visibleForTesting
  int get openTargets => _live.length;
}
