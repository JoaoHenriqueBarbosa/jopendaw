/// Editores do compressor multibanda, do de-esser e da imagem estéreo (parte de `fx_editors.dart`,
/// que guarda os grupos de knobs, o `_Fx` e o observador de indicador que eles usam).
///
/// - Multibanda: o eixo de frequência com as três bandas, o limiar de cada uma e a redução de
///   ganho ao vivo por banda (o motor empacota as três num só indicador). Arrastar perto de um
///   cruzamento o move.
/// - De-esser: a resposta da banda de detecção; arrastar muda a frequência (horizontal) e o Q
///   (vertical). A redução de ganho vai no medidor de sempre.
/// - Imagem estéreo: a largura de cada banda e o medidor de correlação de fase (−1..1).
part of 'fx_editors.dart';

const _mbLow = 20.0, _mbHigh = 20000.0;

double _freqToX(double f, double w) => math.log(f.clamp(_mbLow, _mbHigh) / _mbLow) / math.log(_mbHigh / _mbLow) * w;
double _xToFreq(double x, double w) => _mbLow * math.pow(_mbHigh / _mbLow, (x / math.max(1, w)).clamp(0.0, 1.0)).toDouble();

class _VizEditor extends StatefulWidget {
  final _Fx x;
  final int track;
  final EffectSlot slot;
  final bool desktop;
  final double height;
  const _VizEditor({required this.x, required this.track, required this.slot, required this.desktop, required this.height});

  static const _meterW = 36.0;

  static double _side(double height) => height.clamp(70.0, 220.0);

  static double _vizWidth(EffectKind kind, double side) => switch (kind) {
    EffectKind.multiband => side * 1.9,
    EffectKind.deesser => side * 1.5,
    _ => side * 1.3,
  };

  static double widthFor(_Fx x, double height) {
    final (knob, rows) = _knobFit(height);
    final side = _side(height);
    final meter = x.kind == EffectKind.deesser ? 8 + _meterW : 0;
    return _vizWidth(x.kind, side) + meter + 14 + _groupsWidth(x.groups(knob), rows);
  }

  @override
  State<_VizEditor> createState() => _VizEditorState();
}

class _VizEditorState extends State<_VizEditor> implements _MeterHost {
  late final _watch = _Watch.of(widget.x.c);

  bool _changed = false;
  int _dragCross = 0;

  _Fx get x => widget.x;
  EffectKind get _kind => widget.slot.kind;

  @override
  int get meterTrack => widget.track;
  @override
  String get meterSlot => widget.slot.id;

  @override
  void initState() {
    super.initState();
    _watch.addDynamics(this);
  }

  @override
  void dispose() {
    _watch.removeDynamics(this);
    super.dispose();
  }

  void _set(int id, double value) {
    final spec = x.spec(id);
    final v = spec.clamp(value);
    if ((x.v(id) - v).abs() < 1e-9) return;
    if (!_changed) {
      _changed = true;
      x.begin();
    }
    x.set(id, v);
  }

  // multibanda: o cruzamento mais perto do toque
  void _mbStart(DragStartDetails d, double w) {
    _changed = false;
    final px = d.localPosition.dx;
    _dragCross = (px - _freqToX(x.v(0), w)).abs() <= (px - _freqToX(x.v(1), w)).abs() ? 0 : 1;
  }

  void _mbUpdate(DragUpdateDetails d, double w) => _set(_dragCross, _xToFreq(d.localPosition.dx, w));

  // de-esser: horizontal a frequência, vertical o Q
  void _dsUpdate(DragUpdateDetails d, double w) {
    _set(0, _dsRange(d.localPosition.dx, w));
    final fine = HardwareKeyboard.instance.isShiftPressed ? 0.2 : 1.0;
    _set(1, x.v(1) * math.exp(-d.delta.dy * 0.012 * fine));
  }

  // o eixo do de-esser vai de 1 kHz a 20 kHz
  double _dsRange(double px, double w) => 1000 * math.pow(20.0, (px / math.max(1, w)).clamp(0.0, 1.0)).toDouble();

  @override
  Widget build(BuildContext context) {
    final font = DefaultTextStyle.of(context).style.fontFamily;
    final values = Float64List.fromList([for (final p in _kind.params) x.v(p.id)]);
    return ValueListenableBuilder<_MeterHost?>(
      valueListenable: _watch.active,
      builder: (context, active, _) {
        final live = active == this && !widget.slot.bypass;
        Widget viz(double w) {
          Widget paint(double meter) => CustomPaint(
            painter: _VizPainter(kind: _kind, values: values, meter: meter, live: live, color: x.color, fontFamily: font, bypassed: widget.slot.bypass),
          );
          final body = live ? ValueListenableBuilder<double>(valueListenable: x.c.fxMeter, builder: (context, m, _) => paint(m)) : paint(0);
          Widget framed = ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Container(
              color: Palette.ink,
              foregroundDecoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Palette.hairline),
              ),
              child: body,
            ),
          );
          framed = switch (_kind) {
            EffectKind.multiband => GestureDetector(
              key: const ValueKey('fx-viz'),
              onHorizontalDragStart: (d) => _mbStart(d, w),
              onHorizontalDragUpdate: (d) => _mbUpdate(d, w),
              onHorizontalDragEnd: (_) => _changed = false,
              child: framed,
            ),
            EffectKind.deesser => GestureDetector(
              key: const ValueKey('fx-viz'),
              onPanStart: (_) => _changed = false,
              onPanUpdate: (d) => _dsUpdate(d, w),
              onPanEnd: (_) => _changed = false,
              child: framed,
            ),
            _ => KeyedSubtree(key: const ValueKey('fx-viz'), child: framed),
          };
          return framed;
        }

        Widget? meter;
        if (_kind == EffectKind.deesser) {
          meter = SizedBox(
            width: _VizEditor._meterW,
            child: Tooltip(
              message: widget.slot.bypass
                  ? 'Efeito desligado: nada a medir'
                  : (live ? 'Redução de ganho agora (o traço segura o pico)' : 'O medidor mostra um efeito por vez: toque neste para medir'),
              waitDuration: const Duration(milliseconds: 600),
              child: _GrMeter(source: live ? x.c.fxMeter : null, max: 24, color: x.color, fontFamily: font),
            ),
          );
        }
        final body = widget.desktop ? _desktop(viz, meter) : _mobile(viz, meter);
        return Listener(onPointerDown: (_) => _watch.activate(this), child: body);
      },
    );
  }

  Widget _desktop(Widget Function(double) viz, Widget? meter) {
    final (knob, rows) = _knobFit(widget.height);
    final side = _VizEditor._side(widget.height);
    final w = _VizEditor._vizWidth(_kind, side);
    return SizedBox(
      height: widget.height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: w, height: side, child: viz(w)),
          if (meter != null) ...[const SizedBox(width: 8), SizedBox(height: side, child: meter)],
          const SizedBox(width: 14),
          _GroupsRow(groups: x.groups(knob), rows: rows, knob: knob),
        ],
      ),
    );
  }

  Widget _mobile(Widget Function(double) viz, Widget? meter) => LayoutBuilder(
    builder: (context, box) {
      final gw = math.max(60.0, box.maxWidth - (meter == null ? 0 : _VizEditor._meterW + 8));
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 150,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: viz(gw)),
                if (meter != null) ...[const SizedBox(width: 8), meter],
              ],
            ),
          ),
          const SizedBox(height: 10),
          _GroupsColumn(groups: x.groups(44)),
        ],
      );
    },
  );
}

/// Desenha o gráfico do efeito. [meter] é o valor cru do indicador do motor: no multibanda, as três
/// reduções empacotadas; na imagem, a correlação; no de-esser não é usado (o medidor é à parte).
class _VizPainter extends CustomPainter {
  final EffectKind kind;
  final Float64List values;
  final double meter;
  final bool live, bypassed;
  final Color color;
  final String? fontFamily;

  _VizPainter({
    required this.kind,
    required this.values,
    required this.meter,
    required this.live,
    required this.bypassed,
    required this.color,
    this.fontFamily,
  });

  double _v(int id) => values[kind.params.indexWhere((p) => p.id == id)];

  @override
  void paint(Canvas canvas, Size size) {
    switch (kind) {
      case EffectKind.multiband:
        _multiband(canvas, size);
      case EffectKind.deesser:
        _deesser(canvas, size);
      default:
        _imager(canvas, size);
    }
  }

  void _text(Canvas canvas, String s, Offset at, {Color c = Colors.white30, bool right = false}) {
    final tp = _axisLabel(s, fontFamily, color: c);
    tp.paint(canvas, Offset(right ? at.dx - tp.width : at.dx, at.dy));
  }

  static String _hz(double f) => f >= 1000 ? '${(f / 1000).toStringAsFixed(f >= 10000 ? 0 : 1)}k' : f.toStringAsFixed(0);

  void _multiband(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final (lowHz, highHz) = effectiveCrossovers(_v(0), _v(1));
    final x1 = _freqToX(lowHz, w), x2 = _freqToX(highHz, w);
    final edges = [0.0, x1, x2, w];
    final gr = live ? unpackMultibandMeter(meter) : const [0.0, 0.0, 0.0];
    for (var b = 0; b < 3; b++) {
      final id = multibandBase + b * multibandStride;
      final off = _v(id + 6) >= 0.5;
      final solo = _v(id + 5) >= 0.5;
      final r = Rect.fromLTRB(edges[b], 0, edges[b + 1], h);
      final tint = off ? Colors.white24 : color;
      canvas.drawRect(r, Paint()..color = tint.withValues(alpha: solo ? 0.22 : 0.10));
      if (solo) {
        canvas.drawRect(
          r.deflate(1),
          Paint()
            ..style = PaintingStyle.stroke
            ..color = color,
        );
      }
      // limiar da banda
      final ty = (-_v(id) / 60).clamp(0.0, 1.0) * (h - 16) + 4;
      canvas.drawLine(
        Offset(r.left + 4, ty),
        Offset(r.right - 4, ty),
        Paint()
          ..color = tint.withValues(alpha: 0.8)
          ..strokeWidth = 1.5,
      );
      // redução de ganho ao vivo, de cima para baixo
      final g = gr[b];
      if (g > 0.05 && !off) {
        final gh = math.sqrt((g / 24).clamp(0.0, 1.0)) * (h - 16);
        canvas.drawRect(Rect.fromLTWH(r.center.dx - 6, 0, 12, gh), Paint()..color = Color.lerp(color, Palette.danger, 0.6)!.withValues(alpha: 0.85));
        _text(canvas, '−${g.toStringAsFixed(1)}', Offset(r.center.dx, h - 14), c: Colors.white70);
      }
      _text(canvas, const ['BAIXA', 'MÉDIA', 'AGUDA'][b], Offset(r.left + 5, 2));
    }
    for (final x in [x1, x2]) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, h),
        Paint()
          ..color = Colors.white54
          ..strokeWidth = 1.5,
      );
    }
    _text(canvas, _hz(lowHz), Offset(x1 + 3, h - 14), c: Colors.white54);
    _text(canvas, _hz(highHz), Offset(x2 + 3, h - 14), c: Colors.white54);
  }

  void _deesser(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final f0 = _v(0), q = _v(1);
    double xOf(double f) => math.log(f / 1000) / math.log(20) * w;
    // resposta do passa-banda de detecção, −36..0 dB
    final path = Path()..moveTo(0, h);
    for (var i = 0; i <= w.floor(); i += 2) {
      final f = 1000 * math.pow(20.0, i / w);
      final t = f / f0 - f0 / f;
      final db = -10 * math.log(1 + q * q * t * t) / math.ln10;
      path.lineTo(i.toDouble(), 6 + (-db / 36).clamp(0.0, 1.0) * (h - 24));
    }
    path.lineTo(w, h);
    path.close();
    canvas.drawPath(path, Paint()..color = color.withValues(alpha: bypassed ? 0.08 : 0.22));
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = color.withValues(alpha: bypassed ? 0.3 : 0.9)
        ..strokeWidth = 1.5,
    );
    final cx = xOf(f0.clamp(1000.0, 20000.0));
    canvas.drawLine(Offset(cx, 0), Offset(cx, h), Paint()..color = Colors.white38);
    _text(canvas, '${_hz(f0)} Hz  Q ${q.toStringAsFixed(1)}', Offset(w - 4, 2), c: Colors.white70, right: true);
    for (final f in const [2000.0, 5000.0, 10000.0]) {
      _text(canvas, _hz(f), Offset(xOf(f) + 2, h - 14));
    }
    if (_v(7) >= 0.5) {
      _text(canvas, 'OUVINDO A BANDA', Offset(4, 2), c: color);
    }
  }

  void _imager(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final labels = ['BAIXA', 'MÉDIA', 'AGUDA'];
    final rowH = (h - 26) / 3;
    for (var b = 0; b < 3; b++) {
      final width = _v(2 + b);
      final top = 4 + b * rowH;
      final track = Rect.fromLTWH(48, top + 4, w - 60, rowH - 10);
      canvas.drawRRect(RRect.fromRectAndRadius(track, const Radius.circular(3)), Paint()..color = Colors.white.withValues(alpha: 0.06));
      // 100% no meio da trilha (200% na ponta)
      final fill = Rect.fromLTWH(track.left, track.top, track.width * (width / 2).clamp(0.0, 1.0), track.height);
      canvas.drawRRect(RRect.fromRectAndRadius(fill, const Radius.circular(3)), Paint()..color = color.withValues(alpha: bypassed ? 0.2 : 0.6));
      canvas.drawLine(Offset(track.center.dx, track.top - 2), Offset(track.center.dx, track.bottom + 2), Paint()..color = Colors.white30);
      _text(canvas, labels[b], Offset(4, top + rowH / 2 - 6));
      _text(canvas, '${(width * 100).round()}%', Offset(track.right - 3, top + rowH / 2 - 6), c: Colors.white70, right: true);
    }
    // correlação de fase: −1 (oposição) .. 0 .. +1 (mono)
    final my = h - 16;
    final track = Rect.fromLTWH(48, my + 3, w - 60, 8);
    canvas.drawRRect(RRect.fromRectAndRadius(track, const Radius.circular(3)), Paint()..color = Colors.white.withValues(alpha: 0.06));
    canvas.drawLine(Offset(track.center.dx, track.top - 2), Offset(track.center.dx, track.bottom + 2), Paint()..color = Colors.white30);
    _text(canvas, 'FASE', Offset(4, my + 1));
    if (live) {
      final c = meter.isFinite ? meter.clamp(-1.0, 1.0) : 0.0;
      final px = track.center.dx + c * track.width / 2;
      final bar = Rect.fromLTRB(math.min(track.center.dx, px), track.top, math.max(track.center.dx, px), track.bottom);
      canvas.drawRect(bar, Paint()..color = c < 0 ? Palette.danger : color);
    }
  }

  @override
  bool shouldRepaint(_VizPainter o) =>
      o.kind != kind || !listEquals(o.values, values) || o.meter != meter || o.live != live || o.bypassed != bypassed || o.color != color;
}
