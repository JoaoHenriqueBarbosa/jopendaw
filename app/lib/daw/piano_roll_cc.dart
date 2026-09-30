part of 'piano_roll.dart';

/// As faixas de controle sob a grade do piano roll: Velocidade | Pitch bend | Modulação | Sustain.
/// A velocidade continua sendo a de sempre (`_velocityLane`); as outras três editam os eventos de
/// controle do clipe ([MidiClip.controls]), que o motor toca junto das notas.
///
/// Gestos (mouse e toque): arrastar no vazio desenha a curva (o lápis, com um ponto por passo da
/// grade), com Shift, ou com "Linha reta" ligado no menu do canto, traça uma reta entre o ponto de
/// partida e onde soltar; arrastar um ponto o move (na batida e no valor); clique direito, Alt+clique
/// ou segurar o dedo sobre um ponto o apaga. No pedal o lápis pinta trechos de pedal embaixo (ou os
/// apaga, se começar sobre um). Um gesto é uma edição só no histórico, e um gesto que não muda nada
/// não deixa nada nele.

/// Preferências da faixa de controle (valem para a sessão, de um clipe para outro).
abstract final class _CcPrefs {
  /// 0 = velocidade das notas; senão o controle ([ccBend], [ccMod] ou [ccSustain]).
  static var lane = 0;

  /// Lápis ou reta.
  static var line = false;
}

const _laneNames = {0: 'Velocidade', ccBend: 'Pitch bend', ccMod: 'Modulação', ccSustain: 'Sustain'};
const _laneShort = {0: 'Vel.', ccBend: 'Bend', ccMod: 'Mod.', ccSustain: 'Pedal'};

/// Ids do parâmetro "Alcance do bend" de cada instrumento (espelho de `instruments.dart`).
int? _bendRangeId(TrackKind k) => switch (k) {
  TrackKind.synth => 35,
  TrackKind.fm => 42,
  TrackKind.wavetable => 39,
  TrackKind.sampler => 9,
  _ => null,
};

/// Alcance do bend da faixa, em semitons (2 se o parâmetro não foi mexido).
double _bendRange(DawTrack t) {
  final id = _bendRangeId(t.kind);
  return id == null ? 2.0 : (t.params[id] ?? 2.0);
}

extension _ControlLanes on _PianoRollState {
  /// O canto esquerdo da faixa: o rótulo do que ela mostra e o menu que troca de faixa.
  Widget _controlCorner(BuildContext context, _Dims d) {
    final lane = _CcPrefs.lane;
    final clip = _clip;
    final n = clip == null ? 0 : clip.controls.where((e) => e.cc == lane).length;
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white54);
    final Widget face = lane == 0
        ? _velocityCorner(context, d)
        : Container(
            height: d.velocity,
            decoration: const BoxDecoration(
              color: Palette.canvas,
              border: Border(
                top: BorderSide(color: Palette.hairlineStrong),
                right: BorderSide(color: Palette.hairlineStrong),
              ),
            ),
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(d.keys >= 90 ? _laneNames[lane]! : _laneShort[lane]!, style: style, maxLines: 1, overflow: TextOverflow.fade, softWrap: false),
                Text(
                  '$n ${n == 1 ? 'ponto' : 'pontos'}',
                  style: style?.copyWith(color: Colors.white38, fontSize: 9),
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                ),
              ],
            ),
          );
    return PopupMenuButton<String>(
      tooltip: 'Faixa de controle: velocidade, pitch bend, modulação e sustain',
      padding: EdgeInsets.zero,
      position: PopupMenuPosition.over,
      onSelected: (v) {
        if (v == 'line') {
          _CcPrefs.line = !_CcPrefs.line;
        } else if (v == 'clear') {
          final c0 = _clip;
          if (c0 != null && c0.controls.any((e) => e.cc == lane)) c.edit((_) => c0.controls.removeWhere((e) => e.cc == lane));
        } else {
          _CcPrefs.lane = int.parse(v);
        }
        _active = true;
        _refresh();
      },
      itemBuilder: (_) => [
        for (final id in const [0, ccBend, ccMod, ccSustain]) CheckedPopupMenuItem(value: '$id', checked: lane == id, child: Text(_laneNames[id]!)),
        if (lane != 0) ...[
          const PopupMenuDivider(),
          // o pedal é degrau: lá o gesto é sempre pintura, então a reta não existe
          if (lane != ccSustain) CheckedPopupMenuItem(value: 'line', checked: _CcPrefs.line, child: const Text('Linha reta (ou Shift)')),
          PopupMenuItem(value: 'clear', enabled: n > 0, child: Text('Limpar ${_laneNames[lane]!.toLowerCase()}')),
        ],
      ],
      child: face,
    );
  }

  /// A faixa sob a grade: velocidade ou o controle escolhido.
  Widget _controlLane(_Geo g, MidiClip clip, List<Color> colors) {
    final cc = _CcPrefs.lane;
    if (cc == 0) return _velocityLane(g, clip, colors);
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerSignal: (e) => _onSignal(e, _Area.velocity),
      onPointerPanZoomStart: _panZoomStart,
      onPointerPanZoomUpdate: (e) => _panZoomUpdate(e, _Area.velocity),
      child: _CcLane(
        c: c,
        g: g,
        clip: clip,
        cc: cc,
        color: trackColorAt(_track!.color),
        height: _dims.velocity,
        line: _CcPrefs.line,
        range: _bendRange(_track!),
        step: _unit,
        snap: _snapRound,
        activate: _activate,
        font: _font(context),
      ),
    );
  }
}

enum _CcOp { none, pencil, line, grab, paintPedal }

class _CcLane extends StatefulWidget {
  final DawController c;
  final _Geo g;
  final MidiClip clip;
  final int cc;
  final Color color;
  final double height;
  final bool line;

  /// Alcance do bend da faixa (semitons), só para o rótulo.
  final double range;

  /// Passo da grade (batidas) entre os pontos do lápis e o encaixe das batidas.
  final double step;
  final double Function(double beat) snap;
  final VoidCallback activate;
  final TextStyle font;

  const _CcLane({
    required this.c,
    required this.g,
    required this.clip,
    required this.cc,
    required this.color,
    required this.height,
    required this.line,
    required this.range,
    required this.step,
    required this.snap,
    required this.activate,
    required this.font,
  });

  @override
  State<_CcLane> createState() => _CcLaneState();
}

class _CcLaneState extends State<_CcLane> {
  _CcOp _op = _CcOp.none;
  int? _pointer;
  bool _touch = false;
  bool _checkpointed = false;
  bool _moved = false;
  MidiCc? _grab;
  Offset _down = Offset.zero;
  double _lastBeat = 0, _lastValue = 0, _startBeat = 0, _startValue = 0;
  List<MidiCc> _before = const [];
  double _paint = 1, _paintFrom = 0;
  Timer? _hold;
  (Offset, String)? _tip;

  bool get _pedal => widget.cc == ccSustain;

  double get _inner => math.max(1.0, widget.height - 2 * _velPad);

  double _y(double v) => _velPad + (1 - (widget.cc == ccBend ? (v + 1) / 2 : v)) * _inner;

  double _valueAtY(double y) {
    final up = (1 - (y - _velPad) / _inner).clamp(0.0, 1.0);
    if (_pedal) return up >= .5 ? 1.0 : 0.0;
    var v = widget.cc == ccBend ? up * 2 - 1 : up;
    // o centro do bend atrai: voltar ao zero exato tem de ser fácil
    if (widget.cc == ccBend && v.abs() < .03) v = 0;
    return quantizeControl(widget.cc, v);
  }

  /// A batida do ponteiro, encaixada na grade e dentro do clipe.
  double _beatAt(double x) => widget.snap(widget.g.beatAt(x)).clamp(0.0, widget.clip.length).toDouble();

  List<MidiCc> get _mine => [
    for (final e in widget.clip.controls)
      if (e.cc == widget.cc) e,
  ];

  MidiCc? _hitPoint(Offset p) {
    final tol = _touch ? 16.0 : 8.0;
    MidiCc? best;
    var bestD = double.infinity;
    for (final e in _mine) {
      final d = (Offset(widget.g.x(e.beat), _y(e.value)) - p).distance;
      if (d <= tol && d < bestD) {
        bestD = d;
        best = e;
      }
    }
    return best;
  }

  @override
  void dispose() {
    _hold?.cancel();
    super.dispose();
  }

  void _change(VoidCallback fn) {
    if (!_checkpointed) {
      widget.c.checkpoint();
      _checkpointed = true;
    }
    widget.c.mutate((_) => fn());
  }

  void _showTip(Offset at, double beat, double value) {
    final text = switch (widget.cc) {
      ccBend => '${value >= 0 ? '+' : ''}${(value * widget.range).toStringAsFixed(2)} st',
      ccMod => '${(value * 100).round()}%',
      _ => value >= .5 ? 'Pedal embaixo' : 'Pedal solto',
    };
    setState(() => _tip = (at, text));
  }

  void _down_(PointerDownEvent e) {
    widget.activate();
    if (_pointer != null) return;
    _touch = e.kind == PointerDeviceKind.touch;
    final p = e.localPosition;
    final hit = _hitPoint(p);
    final keys = HardwareKeyboard.instance;
    // apagar: botão direito, Alt ou (abaixo) o dedo parado
    if (hit != null && (e.buttons == kSecondaryMouseButton || keys.isAltPressed)) {
      widget.c.edit((_) => widget.clip.controls.remove(hit));
      return;
    }
    _pointer = e.pointer;
    _down = p;
    _moved = false;
    _checkpointed = false;
    _before = [for (final m in widget.clip.controls) m.copy()];
    final beat = _beatAt(p.dx), value = _valueAtY(p.dy);
    _lastBeat = _startBeat = beat;
    _lastValue = _startValue = value;
    if (hit != null) {
      _op = _CcOp.grab;
      _grab = hit;
      _showTip(p, hit.beat, hit.value);
      // segurar o dedo (ou o mouse) parado sobre o ponto o apaga
      _hold = Timer(const Duration(milliseconds: 550), () {
        if (_pointer == null || _moved || _grab == null) return;
        final g = _grab!;
        _pointer = null;
        _op = _CcOp.none;
        _grab = null;
        _tip = null;
        widget.c.edit((_) => widget.clip.controls.remove(g));
      });
      return;
    }
    if (_pedal) {
      _op = _CcOp.paintPedal;
      final now = controlValueAt(widget.clip.controls, ccSustain, beat) ?? 0;
      _paint = pedalDown(now) ? 0 : 1;
      _paintFrom = beat;
      _applyPedal(beat);
    } else if (keys.isShiftPressed || widget.line) {
      _op = _CcOp.line;
      _applyLine(beat, value);
    } else {
      _op = _CcOp.pencil;
      _change(() => widget.clip.controls = drawControlLine(widget.clip.controls, widget.cc, beat, beat, value, value));
    }
    _showTip(p, beat, value);
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer != _pointer) return;
    final p = e.localPosition;
    if (!_moved && (p - _down).distance < (_touch ? 8 : 3)) return;
    if (!_moved) _hold?.cancel();
    _moved = true;
    final beat = _beatAt(p.dx), value = _valueAtY(p.dy);
    switch (_op) {
      case _CcOp.grab:
        final g = _grab;
        if (g == null) return;
        if (g.beat != beat || g.value != value) {
          _change(() {
            g.beat = beat;
            g.value = value;
          });
        }
      case _CcOp.pencil:
        if (beat != _lastBeat || value != _lastValue) {
          final from = _lastBeat, v0 = _lastValue;
          _change(() => widget.clip.controls = drawControlLine(widget.clip.controls, widget.cc, from, beat, v0, value, step: widget.step));
        }
      case _CcOp.line:
        _applyLine(beat, value);
      case _CcOp.paintPedal:
        _applyPedal(beat);
      case _CcOp.none:
        break;
    }
    _lastBeat = beat;
    _lastValue = value;
    _showTip(p, beat, value);
  }

  /// A reta do ponto de partida até aqui, refeita a cada passo a partir do que havia antes.
  void _applyLine(double beat, double value) {
    final base = [for (final m in _before) m.copy()];
    _change(() => widget.clip.controls = drawControlLine(base, widget.cc, _startBeat, beat, _startValue, value, step: widget.step));
  }

  /// O trecho pintado de pedal (do ponto de partida até aqui), refeito a partir do que havia antes;
  /// depois dele o pedal volta ao estado que tinha ali.
  void _applyPedal(double beat) {
    final lo = math.min(_paintFrom, beat), hi = math.max(_paintFrom, beat);
    final base = [for (final m in _before) m.copy()];
    final after = controlValueAt(base, ccSustain, hi + 1e-9) ?? 0;
    final next = base.where((m) => !(m.cc == ccSustain && m.beat >= lo - 1e-9 && m.beat <= hi + 1e-9)).toList();
    next.add(MidiCc(cc: ccSustain, beat: lo, value: _paint));
    if (hi - lo > 1e-9 && pedalDown(after) != pedalDown(_paint)) next.add(MidiCc(cc: ccSustain, beat: hi, value: after));
    _change(() => widget.clip.controls = next);
  }

  void _up(PointerEvent e) {
    if (e.pointer != _pointer) return;
    _hold?.cancel();
    _pointer = null;
    _op = _CcOp.none;
    _grab = null;
    _tip = null;
    // gesto que voltou ao ponto de partida: tira o checkpoint que ficaria vazio no histórico
    if (_checkpointed && sameControls(_before, widget.clip.controls)) widget.c.undo();
    _checkpointed = false;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.opaque,
    onPointerDown: _down_,
    onPointerMove: _move,
    onPointerUp: _up,
    onPointerCancel: _up,
    child: MouseRegion(
      cursor: SystemMouseCursors.precise,
      child: ClipRect(
        child: CustomPaint(
          size: Size.infinite,
          painter: _CcPainter(g: widget.g, clip: widget.clip, cc: widget.cc, color: widget.color, grab: _grab, tip: _tip, font: widget.font),
        ),
      ),
    ),
  );
}

class _CcPainter extends CustomPainter {
  final _Geo g;
  final MidiClip clip;
  final int cc;
  final Color color;
  final MidiCc? grab;
  final (Offset, String)? tip;
  final TextStyle font;
  _CcPainter({required this.g, required this.clip, required this.cc, required this.color, required this.grab, required this.tip, required this.font});

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final inner = math.max(1.0, h - 2 * _velPad);
    double yOf(double v) => _velPad + (1 - (cc == ccBend ? (v + 1) / 2 : v)) * inner;
    canvas.drawRect(Offset.zero & size, Paint()..color = Palette.canvas);
    // batidas e compassos (só quando o zoom deixa distinguir)
    if (g.ppb >= 12) {
      final first = g.scrollX.floor(), last = g.beatAt(size.width).ceil();
      for (var b = math.max(0, first); b <= last; b++) {
        canvas.drawRect(Rect.fromLTWH(g.x(b.toDouble()).roundToDouble(), 0, 1, h), Paint()..color = const Color(0x08FFFFFF));
      }
    }
    final guide = Paint()..color = const Color(0x0BFFFFFF);
    final zero = yOf(0).roundToDouble();
    if (cc == ccBend) {
      canvas.drawRect(Rect.fromLTWH(0, zero, size.width, 1), Paint()..color = const Color(0x33FFFFFF));
      for (final v in const [-.5, .5]) {
        canvas.drawRect(Rect.fromLTWH(0, yOf(v).roundToDouble(), size.width, 1), guide);
      }
    } else {
      for (final v in const [.25, .5, .75, 1.0]) {
        canvas.drawRect(Rect.fromLTWH(0, yOf(v).roundToDouble(), size.width, 1), guide);
      }
    }
    final events = [
      for (final e in clip.controls)
        if (e.cc == cc) e,
    ]..sort((a, b) => a.beat.compareTo(b.beat));
    final base = cc == ccBend ? zero : yOf(0);
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    final fill = Paint()..color = color.withValues(alpha: .22);
    final xEnd = g.x(clip.length);
    // a curva é em degraus: cada evento vale até o seguinte (é assim que o motor toca)
    var x = g.x(0);
    // o valor que já vale no começo do clipe (pontos de antes dele, de um clipe aparado à esquerda)
    var y = yOf(controlValueAt(events, cc, 0) ?? 0);
    final path = Path()..moveTo(x, y);
    final area = Path()..moveTo(x, base);
    area.lineTo(x, y);
    for (final e in events) {
      final ex = g.x(math.min(e.beat, clip.length));
      path
        ..lineTo(ex, y)
        ..lineTo(ex, yOf(e.value));
      area
        ..lineTo(ex, y)
        ..lineTo(ex, yOf(e.value));
      x = ex;
      y = yOf(e.value);
    }
    path.lineTo(xEnd, y);
    area
      ..lineTo(xEnd, y)
      ..lineTo(xEnd, base)
      ..close();
    canvas.drawPath(area, fill);
    canvas.drawPath(path, line);
    final dot = Paint()..color = color;
    final rim = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (final e in events) {
      final p = Offset(g.x(e.beat), yOf(e.value));
      if (p.dx < -6 || p.dx > size.width + 6) continue;
      final held = identical(e, grab);
      canvas.drawCircle(p, held ? 5 : 3.5, held ? (Paint()..color = Colors.white) : dot);
      if (!held) canvas.drawCircle(p, 3.5, rim);
    }
    final shade = Paint()..color = const Color(0x8C000000);
    final xs = g.x(0);
    if (xs > 0) canvas.drawRect(Rect.fromLTRB(0, 0, xs, h), shade);
    if (xEnd < size.width) canvas.drawRect(Rect.fromLTRB(math.max(0, xEnd), 0, size.width, h), shade);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, 1), Paint()..color = Palette.hairlineStrong);
    final t = tip;
    if (t != null) {
      final tp = _text(font, t.$2, 11, Colors.white, bold: true, cache: false);
      final tx = (t.$1.dx + 10).clamp(2.0, math.max<double>(2, size.width - tp.width - 12));
      final ty = (t.$1.dy - tp.height - 8).clamp(2.0, math.max<double>(2, h - tp.height - 8));
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(tx, ty, tp.width + 8, tp.height + 4), const Radius.circular(4)),
        Paint()..color = const Color(0xEE242932),
      );
      tp.paint(canvas, Offset(tx + 4, ty + 2));
      tp.dispose();
    }
  }

  @override
  bool shouldRepaint(_CcPainter o) => true;
}
