/// Faixas de automação na linha do tempo: o cabeçalho de cada sub-raia, o editor de pontos que fica
/// embaixo da faixa e a conta da curva (a mesma do motor) com a escala de cada alvo.
///
/// Um ponto guarda batida, valor na unidade do alvo e a curva até o próximo. Entre dois pontos o
/// valor anda por t^(2^(curva·3)) na escala do controle do alvo (curva do fader no volume, a do
/// botão nos parâmetros; ver `automation_math.dart`): o que se desenha reto soa reto. Antes do
/// primeiro e depois do último fica parado.
library;

export 'automation_math.dart' show autoShape, autoValueAt;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Curve;
import 'package:flutter/services.dart';

import '../widgets/theme.dart';
import 'automation_math.dart';
import 'controller.dart';
import 'instruments.dart';
import 'model.dart';

/// Altura de uma sub-raia de automação.
const automationLaneHeight = 56.0;

// ---------------------------------------------------------------------- a curva (funções puras)

/// Índice em que um ponto novo nessa batida entra mantendo a ordem (depois dos que já estão nela).
int autoInsertIndex(List<AutoPoint> points, double beat) {
  var lo = 0, hi = points.length;
  while (lo < hi) {
    final mid = (lo + hi) >> 1;
    if (points[mid].beat <= beat) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  return lo;
}

/// Primeiro índice com batida ≥ [beat].
int _lowerBound(List<AutoPoint> points, double beat) {
  var lo = 0, hi = points.length;
  while (lo < hi) {
    final mid = (lo + hi) >> 1;
    if (points[mid].beat < beat) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  return lo;
}

/// O segmento [i, i+1] que contém a batida (entre o primeiro e o último ponto). Em pontos na
/// mesma batida (um degrau), vale o último deles: o valor já é o de depois do salto.
int _segmentAt(List<AutoPoint> points, double beat) {
  var lo = 0, hi = points.length - 1;
  while (hi - lo > 1) {
    final mid = (lo + hi) >> 1;
    if (points[mid].beat <= beat) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return lo;
}

/// Reordena por batida sem trocar a ordem dos pontos na mesma batida (degraus continuam iguais).
void sortAutoPoints(List<AutoPoint> points) => mergeSort(points, compare: (a, b) => a.beat.compareTo(b.beat));

// ---------------------------------------------------------------------- escala de cada alvo

/// Como o valor de um alvo vira altura na raia (0 embaixo, 1 em cima) e texto.
class AutoScale {
  final double Function(double value) toNorm;
  final double Function(double norm) fromNorm;
  final String Function(double value) format;

  /// Linhas de referência: posição 0..1 e rótulo (null = só a linha).
  final List<(double, String?)> grid;

  /// Valor do alvo sem automação (a linha tracejada da raia vazia).
  final double current;

  const AutoScale({required this.toNorm, required this.fromNorm, required this.format, required this.grid, required this.current});

  /// O valor que a raia consegue representar (inteiros e opções arredondados, dentro da faixa).
  double fit(double v) => fromNorm(toNorm(v));

  /// A escala como caminho da automação entre dois pontos (a mesma que o motor recebe).
  AutoWarp get warp => (toNorm: toNorm, fromNorm: fromNorm);
}

/// Pan em texto: C no centro, E/D e a porcentagem para cada lado.
String formatPan(double v) {
  final p = (v * 100).round();
  return p == 0 ? 'C' : (p < 0 ? 'E ${-p}' : 'D $p');
}

ParamSpec? _spec(List<ParamSpec> params, int id) {
  for (final p in params) {
    if (p.id == id) return p;
  }
  return null;
}

/// Os efeitos de uma faixa, ou do master (−1), direto do documento.
List<EffectSlot> effectChainOf(DawController c, int track) => track < 0 ? c.doc.masterEffects : c.doc.tracks[track].effects;

/// As automações de uma faixa, ou do master (−1).
List<AutoLane> automationLanesOf(DawController c, int track) => track < 0 ? c.doc.masterLanes : c.doc.tracks[track].lanes;

/// O parâmetro (da tabela do instrumento ou do efeito) que o alvo automatiza; null nos outros.
ParamSpec? autoParamSpec(DawController c, int track, AutoTarget target) {
  if (track >= c.doc.tracks.length) return null;
  switch (target.kind) {
    case AutoKind.instrument:
      if (track < 0) return null;
      return _spec(c.doc.tracks[track].kind.params, target.param);
    case AutoKind.effect:
      final slot = effectChainOf(c, track).where((s) => s.id == target.ref).firstOrNull;
      return slot == null ? null : _spec(slot.kind.params, target.param);
    case AutoKind.volume || AutoKind.pan || AutoKind.send:
      return null;
  }
}

/// A escala do alvo, ou null quando ele não existe mais (efeito ou barramento apagado): a raia
/// continua no documento, mas fica apagada até alguém removê-la.
AutoScale? autoScaleFor(DawController c, int track, AutoTarget target) {
  final doc = c.doc;
  if (track >= doc.tracks.length) return null;
  ParamSpec? spec;
  switch (target.kind) {
    case AutoKind.instrument || AutoKind.effect:
      spec = autoParamSpec(c, track, target);
      if (spec == null) return null;
    case AutoKind.send:
      if (track < 0 || !doc.tracks.any((b) => b.id == target.ref && b.kind == TrackKind.bus)) return null;
    case AutoKind.volume || AutoKind.pan:
      break;
  }
  final (lo, hi, current) = c.targetRange(track, target);
  if (spec != null) {
    final s = spec;
    final bipolar = s.min < 0 && s.max > 0 && s.curve != Curve.log;
    return AutoScale(
      toNorm: s.toNorm,
      fromNorm: s.fromNorm,
      format: s.format,
      grid: [if (bipolar) (s.toNorm(0), '0') else (0.5, null), (0.25, null), (0.75, null)],
      current: current,
    );
  }
  if (target.kind == AutoKind.pan) {
    final span = hi > lo ? hi - lo : 2.0;
    final min = hi > lo ? lo : -1.0;
    return AutoScale(
      toNorm: (v) => ((v - min) / span).clamp(0.0, 1.0),
      fromNorm: (n) => min + n.clamp(0.0, 1.0) * span,
      format: formatPan,
      grid: [((0 - min) / span, 'C')],
      current: current,
    );
  }
  // volume e envios: ganho linear, desenhado na curva do fader (0 dB perto de 80% da altura) e
  // com o eixo marcado em dB, como no mixer
  final top = hi > 0 ? gainToFader(hi) : 1.0;
  final maxGain = hi > 0 ? hi : 2.0;
  double toNorm(double g) => (gainToFader(g.clamp(0.0, maxGain)) / top).clamp(0.0, 1.0);
  return AutoScale(
    toNorm: toNorm,
    fromNorm: (n) => faderToGain(n.clamp(0.0, 1.0) * top),
    format: (g) => '${formatDb(g)} dB',
    grid: [
      for (final (db, text) in const [(0.0, '0 dB'), (-12.0, '−12'), (-24.0, null)])
        if (dbToGain(db) <= maxGain * 1.0001) (toNorm(dbToGain(db)), text),
    ],
    current: current,
  );
}

/// Nome do alvo como o controlador o apresenta no menu; null se ele não é mais automatizável.
String? automationName(DawController c, int track, AutoTarget target) {
  for (final (t, name) in c.automatable(track)) {
    if (t == target) return name;
  }
  return null;
}

// ---------------------------------------------------------------------- cabeçalho da sub-raia

class AutomationLaneHeader extends StatelessWidget {
  final DawController c;

  /// Faixa dona da automação (−1 = master).
  final int track;
  final AutoLane lane;
  final Color color;
  final double height;
  final bool compact;
  const AutomationLaneHeader({
    super.key,
    required this.c,
    required this.track,
    required this.lane,
    required this.color,
    required this.height,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final scale = autoScaleFor(c, track, lane.target);
    final name = scale == null ? null : automationName(c, track, lane.target);
    final text = Theme.of(context).textTheme;
    final small = text.labelSmall!.copyWith(color: Colors.white54, fontFeatures: const [FontFeature.tabularFigures()]);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: track >= 0 && c.selectedTrack != track ? () => c.selectTrack(track) : null,
      child: Container(
        height: height,
        decoration: const BoxDecoration(
          color: Palette.canvas,
          border: Border(
            right: BorderSide(color: Palette.hairline),
            bottom: BorderSide(color: Palette.hairline),
          ),
        ),
        child: Row(
          children: [
            Container(width: 4, color: color.withValues(alpha: 0.4)),
            SizedBox(width: compact ? 6 : 12),
            if (!compact) ...[Icon(Icons.show_chart, size: 14, color: scale == null ? Colors.white24 : color), const SizedBox(width: 6)],
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name ?? 'Alvo removido',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.labelMedium!.copyWith(color: scale == null ? Colors.white38 : null),
                  ),
                  const SizedBox(height: 2),
                  if (scale == null)
                    Text('não existe mais', maxLines: 1, overflow: TextOverflow.ellipsis, style: small)
                  else
                    // o valor sob o cursor de reprodução, ao vivo (só este texto se refaz a cada quadro)
                    ValueListenableBuilder<double>(
                      valueListenable: c.beat,
                      builder: (context, beat, _) => Text(
                        scale.format(autoValueAt(lane.points, beat, scale.current, warp: scale.warp)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: small,
                      ),
                    ),
                ],
              ),
            ),
            _HeaderIcon(
              icon: Icons.visibility_off_outlined,
              tooltip: 'Ocultar (a automação continua valendo)',
              onPressed: () => c.edit((_) => lane.open = false, undoable: false),
            ),
            _HeaderIcon(icon: Icons.close, tooltip: 'Remover a automação', onPressed: () => c.removeLane(track, lane.id)),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}

class _HeaderIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  const _HeaderIcon({required this.icon, required this.tooltip, required this.onPressed});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 24,
    height: 24,
    child: IconButton(
      padding: EdgeInsets.zero,
      iconSize: 15,
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, color: Colors.white60),
    ),
  );
}

// ---------------------------------------------------------------------- editor de pontos

/// Coordenadas da raia: batida ↔ x (a mesma janela da linha do tempo) e posição 0..1 ↔ y, com
/// uma folga em cima e embaixo para os pontos nos extremos continuarem pegáveis.
class _Geom {
  static const pad = 7.0;
  final Size size;
  final double scroll, ppb;
  const _Geom(this.size, this.scroll, this.ppb);

  double x(double beat) => (beat - scroll) * ppb;
  double beatAt(double x) => scroll + x / ppb;
  double get inner => math.max(1.0, size.height - 2 * pad);
  double y(double norm) => pad + (1 - norm) * inner;
  double normAt(double y) => (1 - (y - pad) / inner).clamp(0.0, 1.0);
}

enum _Mode { none, move, curve, marquee }

/// Arraste que aceita com a folga do arraste horizontal das raias e da rolagem da lista (o pan
/// comum pede o dobro): recebendo o movimento antes dos ancestrais, ganha a disputa. No toque só
/// pega o gesto que começa num ponto ou numa alça; no vazio, o dedo rola a linha do tempo.
class _LanePanRecognizer extends PanGestureRecognizer {
  _LanePanRecognizer({super.debugOwner});

  bool Function(PointerEvent e)? accepts;

  @override
  bool isPointerAllowed(PointerEvent event) => (accepts?.call(event) ?? true) && super.isPointerAllowed(event);

  @override
  bool hasSufficientGlobalDistanceToAccept(PointerDeviceKind pointerDeviceKind, double? deviceTouchSlop) =>
      globalDistanceMoved.abs() > computeHitSlop(pointerDeviceKind, gestureSettings);
}

/// Toque longo só em cima de um ponto (apaga); no vazio não prende o dedo.
class _PointLongPressRecognizer extends LongPressGestureRecognizer {
  _PointLongPressRecognizer({super.debugOwner}) : super(supportedDevices: const {PointerDeviceKind.touch, PointerDeviceKind.stylus});

  bool Function(PointerDownEvent e)? accepts;

  @override
  bool isPointerAllowed(PointerDownEvent event) => (accepts?.call(event) ?? true) && super.isPointerAllowed(event);
}

/// A sub-raia de uma automação: curva, pontos e os gestos de edição.
///
/// Clique no vazio cria ponto (na grade; Alt livre; perto da linha, em cima dela); arrastar move
/// (Shift só o valor, fino; Alt sem grade); duplo clique, clique direito ou toque longo apaga;
/// a alça no meio de cada segmento (ou Alt+arrastar no segmento) entorta a curva, e duplo clique
/// nela volta à reta; arrastar no vazio seleciona por retângulo (Shift soma); Delete apaga a
/// seleção, Ctrl+A seleciona tudo. Cada arraste é um passo só no desfazer.
class AutomationLaneView extends StatefulWidget {
  final DawController c;

  /// Faixa dona da automação (−1 = master).
  final int track;
  final AutoLane lane;
  final Color color;

  /// Aparelho de toque (só muda a dica da raia vazia; os alvos crescem pelo tipo de ponteiro).
  final bool touch;
  const AutomationLaneView({super.key, required this.c, required this.track, required this.lane, required this.color, required this.touch});

  @override
  State<AutomationLaneView> createState() => _AutomationLaneViewState();
}

class _AutomationLaneViewState extends State<AutomationLaneView> {
  DawController get c => widget.c;
  AutoLane get lane => widget.lane;
  List<AutoPoint> get points => widget.lane.points;

  AutoScale? _scale;
  final _selected = Set<AutoPoint>.identity();

  /// O último clique da tela foi aqui: Delete e Ctrl+A são desta raia.
  bool _active = false;

  /// O ponteiro atual é um dedo (alvos maiores).
  bool _touch = false;

  /// O toque que o roteador global está vendo caiu nesta raia (o Listener dela roda antes).
  bool _downHere = false;

  _Mode _mode = _Mode.none;
  bool _dirty = false;

  /// Ponto pego (mover) ou o começo do segmento (curva).
  AutoPoint? _grab;
  final _orig = Map<AutoPoint, (double, double)>.identity();
  double _minDelta = 0, _maxDelta = 0;

  /// Deslocamento acumulado do arraste: pixels na horizontal e posição 0..1 na vertical (ou
  /// curva). Acumular passo a passo deixa trocar Shift no meio sem o ponto pular.
  double _dx = 0, _dn = 0, _origCurve = 0;
  Offset? _marqueeFrom, _marqueeTo;
  final _marqueeBase = Set<AutoPoint>.identity();

  AutoPoint? _hoverPoint;

  /// Alça de curva sob o mouse (ou sendo arrastada): índice do ponto que começa o segmento.
  int? _hoverHandle;

  // duplo clique: só conta se os dois cliques caíram no mesmo ponto (ou alça) que já existia,
  // senão clicar duas vezes no vazio criaria e apagaria o ponto
  DateTime? _tapAt;
  Object? _tapOn;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onGlobalPointer);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onGlobalPointer);
    super.dispose();
  }

  _Geom get _geom => _Geom(context.size ?? Size.zero, c.scrollBeat, c.pxPerBeat);
  double get _radius => _touch ? 16 : 7;

  // ------------------------------------------------------------------ foco e teclas

  /// Um clique em qualquer lugar decide de quem são as teclas de edição: dentro, desta raia (o
  /// clipe selecionado sai da seleção, senão o Delete apagaria os dois); fora, a seleção some.
  /// "Dentro" é o que o teste de toque achou aqui, não a área: um menu aberto por cima não conta.
  void _onGlobalPointer(PointerEvent e) {
    if (e is! PointerDownEvent || !mounted) return;
    final inside = _downHere;
    _downHere = false;
    if (inside) {
      _touch = e.kind == PointerDeviceKind.touch;
      _active = true;
      if (c.selectedClip != null) c.selectClip(null);
      if (widget.track >= 0 && c.selectedTrack != widget.track) c.selectTrack(widget.track);
    } else if (_active) {
      _active = false;
      if (_selected.isNotEmpty) setState(_selected.clear);
    }
  }

  static bool _typing() => FocusManager.instance.primaryFocus?.context?.widget is EditableText;

  bool _onKey(KeyEvent e) {
    if (!_active || !mounted || e is! KeyDownEvent || _typing()) return false;
    final k = e.logicalKey;
    final keys = HardwareKeyboard.instance;
    if ((k == LogicalKeyboardKey.delete || k == LogicalKeyboardKey.backspace) && _selected.isNotEmpty) {
      _deletePoints(Set<AutoPoint>.identity()..addAll(_selected));
      return true;
    }
    if ((keys.isControlPressed || keys.isMetaPressed) && k == LogicalKeyboardKey.keyA && points.isNotEmpty) {
      setState(() => _selected.addAll(points));
      return true;
    }
    // o Esc segue para a tela (fecha o painel de baixo); aqui só limpa a seleção
    if (k == LogicalKeyboardKey.escape && _selected.isNotEmpty) setState(_selected.clear);
    return false;
  }

  // ------------------------------------------------------------------ o que está sob o ponteiro

  double _yOf(AutoPoint p, _Geom g) => g.y(_scale!.toNorm(p.value));

  AutoPoint? _pointAt(Offset p) {
    if (_scale == null || points.isEmpty) return null;
    final g = _geom;
    final r = _radius;
    AutoPoint? best;
    var bestD = r;
    for (var i = _lowerBound(points, g.beatAt(p.dx - r)); i < points.length; i++) {
      final q = points[i];
      final x = g.x(q.beat);
      if (x > p.dx + r) break;
      final d = (Offset(x, _yOf(q, g)) - p).distance;
      // empate (pontos empilhados num degrau): fica o de cima da lista, o último desenhado
      if (d <= bestD) {
        best = q;
        bestD = d;
      }
    }
    return best;
  }

  /// O segmento [i, i+1] tem alça: largo o bastante na tela e com valores diferentes.
  bool _hasHandle(int i, _Geom g) {
    if (i < 0 || i + 1 >= points.length) return false;
    final a = points[i], b = points[i + 1];
    if (g.x(b.beat) - g.x(a.beat) < 18) return false;
    return (_scale!.toNorm(b.value) - _scale!.toNorm(a.value)).abs() > 0.02;
  }

  Offset _handlePos(int i, _Geom g) {
    final a = points[i], b = points[i + 1];
    final mid = (a.beat + b.beat) / 2;
    return Offset(g.x(mid), g.y(_scale!.toNorm(autoSegment(a, b, mid, _scale!.warp))));
  }

  int? _handleAt(Offset p) {
    if (_scale == null || points.length < 2) return null;
    final g = _geom;
    final beat = g.beatAt(p.dx);
    if (beat < points.first.beat || beat >= points.last.beat) return null;
    final seg = _segmentAt(points, beat);
    for (final i in [seg, seg - 1, seg + 1]) {
      if (_hasHandle(i, g) && (_handlePos(i, g) - p).distance <= _radius) return i;
    }
    return null;
  }

  /// O segmento sob o ponteiro (Alt+arrastar entorta a curva dele), se tiver valores diferentes.
  int? _segmentUnder(Offset p) {
    if (_scale == null || points.length < 2) return null;
    final beat = _geom.beatAt(p.dx);
    if (beat < points.first.beat || beat >= points.last.beat) return null;
    final i = _segmentAt(points, beat);
    return points[i + 1].value != points[i].value ? i : null;
  }

  // ------------------------------------------------------------------ edição

  /// Um passo de arraste: o checkpoint sai na primeira mudança de fato, não ao encostar.
  void _change(VoidCallback fn) {
    if (!_dirty) {
      c.checkpoint();
      _dirty = true;
    }
    c.mutate((_) => fn());
  }

  void _createAt(Offset p) {
    final scale = _scale!;
    final g = _geom;
    final raw = g.beatAt(p.dx);
    final beat = math.max(0.0, HardwareKeyboard.instance.isAltPressed ? raw : c.snapBeat(raw));
    // perto da linha o ponto nasce em cima dela (a forma não muda); longe, onde se clicou
    final lineY = g.y(scale.toNorm(autoValueAt(points, raw, scale.current, warp: scale.warp)));
    final onLine = (p.dy - lineY).abs() <= (_touch ? 12 : 6);
    final value = scale.fit(onLine ? autoValueAt(points, beat, scale.current, warp: scale.warp) : scale.fromNorm(g.normAt(p.dy)));
    final point = AutoPoint(beat: beat, value: value);
    c.edit((_) => lane.points.insert(autoInsertIndex(lane.points, beat), point));
    setState(() {
      _selected
        ..clear()
        ..add(point);
    });
  }

  void _deletePoints(Set<AutoPoint> which) {
    if (which.isEmpty) return;
    c.edit((_) => lane.points.removeWhere(which.contains));
    setState(() {
      _selected.removeWhere(which.contains);
      if (which.contains(_hoverPoint)) _hoverPoint = null;
      _hoverHandle = null;
    });
  }

  void _resetCurve(int i) {
    final a = points[i];
    if (a.curve != 0) c.edit((_) => a.curve = 0);
  }

  // ------------------------------------------------------------------ gestos

  bool _panAccepts(PointerEvent e) {
    if (_scale == null) return false;
    if (e.kind != PointerDeviceKind.touch) return true;
    _touch = true;
    return _pointAt(e.localPosition) != null || _handleAt(e.localPosition) != null;
  }

  bool _longPressAccepts(PointerDownEvent e) {
    // o reconhecedor pergunta antes de filtrar o aparelho: mouse não conta (nem vira "dedo")
    if (e.kind != PointerDeviceKind.touch && e.kind != PointerDeviceKind.stylus) return false;
    _touch = e.kind == PointerDeviceKind.touch;
    return _pointAt(e.localPosition) != null;
  }

  void _onTapUp(TapUpDetails d) {
    if (_scale == null) return;
    final p = d.localPosition;
    final now = DateTime.now();
    final point = _pointAt(p);
    final handle = point == null ? _handleAt(p) : null;
    final Object? on = point != null ? (point, false) : (handle != null ? (points[handle], true) : null);
    final twice = on != null && on == _tapOn && _tapAt != null && now.difference(_tapAt!) < kDoubleTapTimeout;
    _tapAt = now;
    _tapOn = twice ? null : on;
    if (point != null) {
      if (twice) {
        _deletePoints({point});
        return;
      }
      final shift = HardwareKeyboard.instance.isShiftPressed;
      setState(() {
        if (shift) {
          if (!_selected.remove(point)) _selected.add(point);
        } else {
          _selected
            ..clear()
            ..add(point);
        }
      });
      return;
    }
    if (handle != null) {
      if (twice) _resetCurve(handle);
      return;
    }
    _createAt(p);
  }

  void _onSecondaryTapUp(TapUpDetails d) {
    if (_scale == null) return;
    final point = _pointAt(d.localPosition);
    if (point != null) {
      _deletePoints({point});
      return;
    }
    final handle = _handleAt(d.localPosition);
    if (handle != null) {
      _resetCurve(handle);
    } else if (_selected.isNotEmpty) {
      setState(_selected.clear);
    }
  }

  void _onLongPress(LongPressStartDetails d) {
    final point = _pointAt(d.localPosition);
    if (point != null) _deletePoints({point});
  }

  void _onPanStart(DragStartDetails d) {
    if (_scale == null) return;
    final p = d.localPosition;
    final keys = HardwareKeyboard.instance;
    _dirty = false;
    _dx = 0;
    _dn = 0;
    final point = _pointAt(p);
    if (point != null) {
      _beginMove(point, add: keys.isShiftPressed);
      return;
    }
    final handle = _handleAt(p) ?? (keys.isAltPressed ? _segmentUnder(p) : null);
    if (handle != null) {
      setState(() {
        _mode = _Mode.curve;
        _grab = points[handle];
        _origCurve = points[handle].curve;
        _hoverHandle = handle;
      });
      return;
    }
    setState(() {
      _mode = _Mode.marquee;
      _marqueeFrom = p;
      _marqueeTo = p;
      _marqueeBase.clear();
      if (keys.isShiftPressed) _marqueeBase.addAll(_selected);
    });
  }

  void _beginMove(AutoPoint point, {required bool add}) {
    final scale = _scale!;
    if (!_selected.contains(point)) {
      if (!add) _selected.clear();
      _selected.add(point);
    }
    _grab = point;
    _orig.clear();
    for (final p in _selected) {
      _orig[p] = (p.beat, scale.toNorm(p.value));
    }
    // o grupo anda junto sem passar do vizinho não selecionado mais próximo de cada lado (a
    // ordem dos pontos fica) nem de antes do zero
    var lo = double.negativeInfinity, hi = double.infinity;
    double left = 0;
    for (final p in points) {
      if (_selected.contains(p)) {
        lo = math.max(lo, left - p.beat);
      } else {
        left = p.beat;
      }
    }
    double? right;
    for (final p in points.reversed) {
      if (!_selected.contains(p)) {
        right = p.beat;
      } else if (right != null) {
        hi = math.min(hi, right - p.beat);
      }
    }
    setState(() {
      _mode = _Mode.move;
      _minDelta = math.min(0.0, lo);
      _maxDelta = math.max(0.0, hi);
    });
  }

  void _onPanUpdate(DragUpdateDetails d) {
    final scale = _scale;
    if (scale == null) return;
    final keys = HardwareKeyboard.instance;
    final g = _geom;
    switch (_mode) {
      case _Mode.move:
        final grab = _grab;
        if (grab == null || !_orig.containsKey(grab)) return;
        final fine = keys.isShiftPressed;
        if (!fine) _dx += d.delta.dx;
        _dn -= d.delta.dy / g.inner * (fine ? 0.25 : 1);
        final b0 = _orig[grab]!.$1;
        var target = b0 + _dx / c.pxPerBeat;
        if (!keys.isAltPressed) target = c.snapBeat(target);
        final delta = (target - b0).clamp(_minDelta, _maxDelta);
        final next = <(AutoPoint, double, double)>[];
        var same = true;
        for (final MapEntry(key: p, value: (b, n)) in _orig.entries) {
          final nb = b + delta, nv = scale.fromNorm((n + _dn).clamp(0.0, 1.0));
          if (nb != p.beat || nv != p.value) same = false;
          next.add((p, nb, nv));
        }
        if (same) return;
        _change(() {
          for (final (p, b, v) in next) {
            p
              ..beat = b
              ..value = v;
          }
        });
      case _Mode.curve:
        final a = _grab;
        final i = a == null ? -1 : points.indexOf(a);
        if (i < 0 || i + 1 >= points.length) return;
        final sign = (points[i + 1].value - a!.value).sign;
        if (sign == 0) return;
        // subir o meio de um segmento que sobe pede curva menor; num que desce, maior
        _dn += d.delta.dy / 50 * sign * (keys.isShiftPressed ? 0.25 : 1);
        final curve = (_origCurve + _dn).clamp(-1.0, 1.0);
        if (curve != a.curve) _change(() => a.curve = curve);
      case _Mode.marquee:
        final from = _marqueeFrom;
        if (from == null) return;
        final to = d.localPosition;
        final rect = Rect.fromPoints(from, to);
        setState(() {
          _marqueeTo = to;
          _selected
            ..clear()
            ..addAll(_marqueeBase);
          for (var i = _lowerBound(points, g.beatAt(rect.left)); i < points.length; i++) {
            final q = points[i];
            final x = g.x(q.beat);
            if (x > rect.right) break;
            if (rect.contains(Offset(x, _yOf(q, g)))) _selected.add(q);
          }
        });
      case _Mode.none:
        break;
    }
  }

  void _onPanEnd() {
    if (_mode == _Mode.move && _dirty) {
      // o arraste não troca a ordem, mas conta em ponto flutuante não custa conferir
      var sorted = true;
      for (var i = 1; i < points.length; i++) {
        if (points[i].beat < points[i - 1].beat) sorted = false;
      }
      if (!sorted) c.mutate((_) => sortAutoPoints(lane.points));
    }
    if (!mounted) return;
    setState(() {
      _mode = _Mode.none;
      _dirty = false;
      _grab = null;
      _orig.clear();
      _marqueeFrom = _marqueeTo = null;
      _marqueeBase.clear();
    });
  }

  void _onHover(PointerHoverEvent e) {
    _touch = false;
    if (_mode != _Mode.none || _scale == null) return;
    final point = _pointAt(e.localPosition);
    final handle = point == null ? _handleAt(e.localPosition) : null;
    if (point != _hoverPoint || handle != _hoverHandle) {
      setState(() {
        _hoverPoint = point;
        _hoverHandle = handle;
      });
    }
  }

  void _onExit(PointerExitEvent _) {
    if (_mode != _Mode.none || (_hoverPoint == null && _hoverHandle == null)) return;
    setState(() {
      _hoverPoint = null;
      _hoverHandle = null;
    });
  }

  MouseCursor get _cursor {
    if (_scale == null) return SystemMouseCursors.basic;
    return switch (_mode) {
      _Mode.move => SystemMouseCursors.grabbing,
      _Mode.curve => SystemMouseCursors.resizeUpDown,
      _Mode.marquee => SystemMouseCursors.precise,
      _Mode.none =>
        _hoverPoint != null
            ? SystemMouseCursors.grab
            : _hoverHandle != null
            ? SystemMouseCursors.resizeUpDown
            : SystemMouseCursors.precise,
    };
  }

  /// Esquece seleção e foco de pontos que não existem mais (apagados, desfeitos: o desfazer troca
  /// o documento inteiro e os pontos viram outros objetos).
  void _prune() {
    if (_selected.isEmpty && _hoverPoint == null && _hoverHandle == null) return;
    final alive = Set<AutoPoint>.identity()..addAll(points);
    _selected.removeWhere((p) => !alive.contains(p));
    if (_hoverPoint != null && !alive.contains(_hoverPoint)) _hoverPoint = null;
    if (_hoverHandle != null && _hoverHandle! + 1 >= points.length) _hoverHandle = null;
  }

  @override
  Widget build(BuildContext context) {
    final scale = _scale = autoScaleFor(c, widget.track, lane.target);
    if (_mode == _Mode.none) _prune();
    final style = Theme.of(context).textTheme.labelSmall!;
    String? label;
    AutoPoint? labelPoint;
    int? labelHandle;
    if (scale != null) {
      final focus = _mode == _Mode.move ? _grab : (_mode == _Mode.none ? _hoverPoint : null);
      final handle = _mode == _Mode.curve ? (_grab == null ? null : points.indexOf(_grab!)) : (_mode == _Mode.none ? _hoverHandle : null);
      if (focus != null) {
        labelPoint = focus;
        label = '${formatPosition(focus.beat, c.doc.beatsPerBar)} · ${scale.format(focus.value)}';
      } else if (handle != null && handle >= 0 && handle + 1 < points.length) {
        labelHandle = handle;
        final k = (points[handle].curve * 100).round();
        label = k == 0 ? 'Curva: reta' : 'Curva ${k > 0 ? '+' : '−'}${k.abs()}%';
      }
    }
    final painter = _LanePainter(
      points: points,
      scale: scale,
      scroll: c.scrollBeat,
      ppb: c.pxPerBeat,
      color: widget.color,
      selected: _selected,
      hoverPoint: _mode == _Mode.none ? _hoverPoint : null,
      handle: _mode == _Mode.curve ? labelHandle : _hoverHandle,
      marquee: _marqueeFrom != null && _marqueeTo != null ? Rect.fromPoints(_marqueeFrom!, _marqueeTo!) : null,
      label: label,
      labelPoint: labelPoint,
      labelHandle: labelHandle,
      hint: scale == null ? 'O alvo desta automação não existe mais' : (widget.touch ? 'Toque para criar um ponto' : 'Clique para criar um ponto'),
      style: style,
    );
    return Listener(
      onPointerDown: (_) => _downHere = true,
      child: MouseRegion(
        cursor: _cursor,
        onHover: _onHover,
        onExit: _onExit,
        child: RawGestureDetector(
          behavior: HitTestBehavior.opaque,
          gestures: {
            TapGestureRecognizer: GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
              () => TapGestureRecognizer(debugOwner: this),
              (r) => r
                ..onTapUp = _onTapUp
                ..onSecondaryTapUp = _onSecondaryTapUp,
            ),
            _LanePanRecognizer: GestureRecognizerFactoryWithHandlers<_LanePanRecognizer>(
              () => _LanePanRecognizer(debugOwner: this),
              (r) => r
                ..accepts = _panAccepts
                // a zona vale onde o ponteiro encostou, não onde o arraste foi reconhecido
                ..dragStartBehavior = DragStartBehavior.down
                ..onStart = _onPanStart
                ..onUpdate = _onPanUpdate
                ..onEnd = ((_) => _onPanEnd())
                ..onCancel = _onPanEnd,
            ),
            _PointLongPressRecognizer: GestureRecognizerFactoryWithHandlers<_PointLongPressRecognizer>(
              () => _PointLongPressRecognizer(debugOwner: this),
              (r) => r
                ..accepts = _longPressAccepts
                ..onLongPressStart = _onLongPress,
            ),
          },
          child: CustomPaint(
            painter: painter,
            foregroundPainter: scale == null || points.isEmpty ? null : _PlayheadDotPainter(c: c, points: points, scale: scale, color: widget.color),
            size: Size.infinite,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------- desenho

/// Balão de texto dentro da raia, ao lado de [at] (à direita; à esquerda se não couber).
void _bubble(Canvas canvas, Size size, Offset at, String text, TextStyle style) {
  final tp = TextPainter(
    text: TextSpan(
      text: text,
      style: style.copyWith(color: Colors.white, fontSize: 11),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();
  final w = tp.width + 10, h = tp.height + 4;
  var left = at.dx + 9;
  if (left + w > size.width - 2) left = at.dx - 9 - w;
  left = left.clamp(2.0, math.max(2.0, size.width - w - 2)).toDouble();
  final top = (at.dy - h / 2).clamp(1.0, math.max(1.0, size.height - h - 1)).toDouble();
  final r = RRect.fromRectAndRadius(Rect.fromLTWH(left, top, w, h), const Radius.circular(5));
  canvas.drawRRect(r, Paint()..color = const Color(0xF02A2F38));
  canvas.drawRRect(
    r,
    Paint()
      ..style = PaintingStyle.stroke
      ..color = Palette.hairlineStrong,
  );
  tp.paint(canvas, Offset(left + 5, top + 2));
}

class _LanePainter extends CustomPainter {
  final List<AutoPoint> points;
  final AutoScale? scale;
  final double scroll, ppb;
  final Color color;
  final Set<AutoPoint> selected;
  final AutoPoint? hoverPoint;

  /// Alça em destaque (sob o mouse ou sendo arrastada).
  final int? handle;
  final Rect? marquee;
  final String? label;
  final AutoPoint? labelPoint;
  final int? labelHandle;
  final String hint;
  final TextStyle style;

  _LanePainter({
    required this.points,
    required this.scale,
    required this.scroll,
    required this.ppb,
    required this.color,
    required this.selected,
    required this.hoverPoint,
    required this.handle,
    required this.marquee,
    required this.label,
    required this.labelPoint,
    required this.labelHandle,
    required this.hint,
    required this.style,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final s = scale;
    final g = _Geom(size, scroll, ppb);
    final w = size.width;
    final dim = style.copyWith(color: Colors.white30, fontSize: 10);
    if (s == null) {
      final hatch = Paint()
        ..color = Colors.white.withValues(alpha: 0.04)
        ..strokeWidth = 1;
      for (var x = -size.height; x < w; x += 10) {
        canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), hatch);
      }
      _text(canvas, hint, Offset(8, size.height / 2 - 7), w - 16, dim);
      return;
    }

    // linhas de referência (0 dB, centro do pan...)
    final gridPaint = Paint()..color = Colors.white.withValues(alpha: 0.05);
    for (final (n, text) in s.grid) {
      final y = g.y(n);
      canvas.drawRect(Rect.fromLTWH(0, y.roundToDouble(), w, 1), gridPaint);
      if (text != null && size.height >= 40) _text(canvas, text, Offset(3, y - 12 < 0 ? y + 1 : y - 12), 60, dim.copyWith(fontSize: 9));
    }

    if (points.isEmpty) {
      // sem pontos vale o valor do controle: linha tracejada
      final y = g.y(s.toNorm(s.current));
      final dash = Paint()
        ..color = color.withValues(alpha: 0.7)
        ..strokeWidth = 1.2;
      for (var x = 0.0; x < w; x += 9) {
        canvas.drawLine(Offset(x, y), Offset(math.min(w, x + 5), y), dash);
      }
      final hintY = y > size.height / 2 ? 3.0 : size.height - 15;
      _text(canvas, hint, Offset(8, hintY), w - 16, dim);
      _drawMarquee(canvas);
      return;
    }

    // a curva: reta antes do primeiro, segmentos visíveis amostrados a cada 2 px, reta depois
    final line = <Offset>[];
    void add(double x, double v) => line.add(Offset(x, g.y(s.toNorm(v))));
    final first = points.first, last = points.last;
    final fx = g.x(first.beat);
    if (fx > 0) {
      add(0, first.value);
      add(math.min(fx, w), first.value);
    }
    var i = math.max(0, _lowerBound(points, scroll) - 1);
    for (; i < points.length - 1; i++) {
      final a = points[i], b = points[i + 1];
      final xa = g.x(a.beat), xb = g.x(b.beat);
      if (xa > w) break;
      if (xb < 0) continue;
      if (xb - xa < 1e-6) {
        add(xa, a.value);
        add(xb, b.value);
        continue;
      }
      final from = math.max(0.0, xa), to = math.min(w, xb);
      for (var x = from; x < to; x += 2) {
        add(x, autoSegment(a, b, g.beatAt(x), s.warp));
      }
      add(to, to == xb ? b.value : autoSegment(a, b, g.beatAt(to), s.warp));
    }
    final lx = g.x(last.beat);
    if (lx < w) {
      add(math.max(0.0, lx), last.value);
      add(w, last.value);
    }
    if (line.length >= 2) {
      final path = Path()..addPolygon(line, false);
      final fill = Path.from(path)
        ..lineTo(line.last.dx, size.height)
        ..lineTo(line.first.dx, size.height)
        ..close();
      canvas.drawPath(fill, Paint()..color = color.withValues(alpha: 0.10));
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..strokeJoin = StrokeJoin.round
          ..color = color,
      );
    }

    // alças de curva no meio dos segmentos visíveis
    final lo = math.max(0, _lowerBound(points, g.beatAt(-20)) - 1);
    for (var j = lo; j < points.length - 1; j++) {
      final a = points[j], b = points[j + 1];
      final xa = g.x(a.beat), xb = g.x(b.beat);
      if (xa > w + 20) break;
      if (xb - xa < 18 || (s.toNorm(b.value) - s.toNorm(a.value)).abs() <= 0.02) continue;
      final mid = (a.beat + b.beat) / 2;
      final c = Offset(g.x(mid), g.y(s.toNorm(autoSegment(a, b, mid, s.warp))));
      final hot = j == handle;
      canvas.drawCircle(c, hot ? 4 : 2.6, Paint()..color = hot ? color : Palette.ink);
      canvas.drawCircle(
        c,
        hot ? 4 : 2.6,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = color.withValues(alpha: hot ? 1 : 0.6),
      );
    }

    // pontos
    final fillSel = Paint()..color = Colors.white;
    final fillPt = Paint()..color = color;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Palette.ink;
    for (var j = _lowerBound(points, g.beatAt(-8)); j < points.length; j++) {
      final p = points[j];
      final x = g.x(p.beat);
      if (x > w + 8) break;
      final c = Offset(x, g.y(s.toNorm(p.value)));
      final sel = selected.contains(p);
      final r = p == hoverPoint ? 5.0 : (sel ? 4.5 : 3.8);
      canvas.drawCircle(c, r, sel ? fillSel : fillPt);
      canvas.drawCircle(c, r, ring);
      if (sel) {
        canvas.drawCircle(
          c,
          r + 1.5,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = color,
        );
      }
    }

    _drawMarquee(canvas);

    final text = label;
    if (text != null) {
      Offset? at;
      final lp = labelPoint;
      final lh = labelHandle;
      if (lp != null) {
        at = Offset(g.x(lp.beat), g.y(s.toNorm(lp.value)));
      } else if (lh != null && lh + 1 < points.length) {
        final a = points[lh], b = points[lh + 1];
        final mid = (a.beat + b.beat) / 2;
        at = Offset(g.x(mid), g.y(s.toNorm(autoSegment(a, b, mid, s.warp))));
      }
      if (at != null) _bubble(canvas, size, at, text, style);
    }
  }

  void _drawMarquee(Canvas canvas) {
    final m = marquee;
    if (m == null) return;
    canvas.drawRect(m, Paint()..color = color.withValues(alpha: 0.12));
    canvas.drawRect(
      m,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = color.withValues(alpha: 0.8),
    );
  }

  static void _text(Canvas canvas, String text, Offset at, double maxWidth, TextStyle style) {
    if (maxWidth <= 8) return;
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    tp.paint(canvas, at);
  }

  // os pontos mudam no lugar (a lista é a mesma): não há comparação barata, e a raia só se
  // redesenha quando o documento, a visão ou o mouse mudam
  @override
  bool shouldRepaint(_LanePainter old) => true;
}

/// O valor sob o cursor de reprodução como um ponto andando na curva; redesenha só ele a cada
/// quadro do motor.
class _PlayheadDotPainter extends CustomPainter {
  final DawController c;
  final List<AutoPoint> points;
  final AutoScale scale;
  final Color color;
  _PlayheadDotPainter({required this.c, required this.points, required this.scale, required this.color}) : super(repaint: c.beat);

  @override
  void paint(Canvas canvas, Size size) {
    final g = _Geom(size, c.scrollBeat, c.pxPerBeat);
    final beat = c.beat.value;
    final x = g.x(beat);
    if (x < -4 || x > size.width + 4) return;
    final at = Offset(x, g.y(scale.toNorm(autoValueAt(points, beat, scale.current, warp: scale.warp))));
    canvas.drawCircle(at, 3.5, Paint()..color = Colors.white);
    canvas.drawCircle(
      at,
      3.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_PlayheadDotPainter old) => true;
}
