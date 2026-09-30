/// As raias do comp na linha do tempo: uma por tomada, empilhadas sob a faixa do clipe. Arrastar numa raia
/// escolhe aquela tomada no trecho; tocar escolhe no trecho (entre emendas) sob o toque.
library;

import 'dart:math' as math;

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';

import '../widgets/theme.dart';
import 'comp.dart';
import 'controller.dart';
import 'tempo_map.dart';

/// Altura de cada raia de tomada.
const compLaneHeight = 30.0;

/// O cabeçalho da raia da tomada [take]: o nome (tocar usa a tomada no comp inteiro) e, na primeira raia, Achatar e Fechar.
class CompLaneHeader extends StatelessWidget {
  final DawController c;
  final int take;
  final Color color;
  final double height;
  final bool compact;
  const CompLaneHeader({super.key, required this.c, required this.take, required this.color, required this.height, required this.compact});

  @override
  Widget build(BuildContext context) {
    final g = c.compGroup;
    final active = g != null && c.compSegs.isNotEmpty && c.compSegs.every((s) => s.take == take);
    final missing = g != null && take < g.takes.length && c.missing.contains(g.takes[take]);
    final text = Theme.of(context).textTheme;
    return Container(
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
          Expanded(
            child: Tooltip(
              message: missing ? 'Esta tomada não está neste aparelho' : 'Usar a tomada ${take + 1} no comp inteiro',
              child: InkWell(
                key: ValueKey('comp-take-$take'),
                onTap: missing ? null : () => c.compPickAll(take),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 10),
                  child: Row(
                    children: [
                      SizedBox(width: 14, child: active ? const Icon(Icons.check, size: 13, color: Palette.accent) : null),
                      Expanded(
                        child: Text(
                          compact ? 'T${take + 1}' : 'Tomada ${take + 1}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.labelMedium!.copyWith(color: missing ? Colors.white38 : null),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (take == 0) ...[
            _btn(Icons.layers_clear_outlined, 'Achatar: manter os clipes e descartar as tomadas', c.flattenComp, 'comp-flatten'),
            _btn(Icons.close, 'Fechar o comp', c.endComp, 'comp-close'),
          ],
        ],
      ),
    );
  }

  Widget _btn(IconData icon, String tip, VoidCallback onTap, String key) => IconButton(
    key: ValueKey(key),
    tooltip: tip,
    onPressed: onTap,
    iconSize: 15,
    visualDensity: VisualDensity.compact,
    constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
    padding: EdgeInsets.zero,
    style: IconButton.styleFrom(foregroundColor: Colors.white54),
    icon: Icon(icon),
  );
}

/// A raia da tomada [take]: a onda dela ao longo do comp, acesa onde ela é a que soa. Arrastar escolhe o trecho.
class CompLaneView extends StatefulWidget {
  final DawController c;
  final int take;
  final Color color;
  const CompLaneView({super.key, required this.c, required this.take, required this.color});

  @override
  State<CompLaneView> createState() => _CompLaneViewState();
}

class _CompLaneViewState extends State<CompLaneView> {
  /// O arraste em curso, em batidas (já na grade).
  double? _from, _to;

  DawController get c => widget.c;

  double _beat(double x) => c.scrollBeat + x / c.pxPerBeat;

  void _end() {
    final a = _from, b = _to;
    setState(() => _from = _to = null);
    if (a == null || b == null || (b - a).abs() < 1e-9) return;
    c.compPick(widget.take, math.min(a, b), math.max(a, b));
  }

  void _tap(double x) {
    final tm = c.doc.tempo;
    final at = tm.secondsAt(_beat(x));
    for (final s in c.compSegs) {
      if (at >= s.s && at < s.e) {
        c.compPick(widget.take, tm.beatAt(s.s), tm.beatAt(s.e));
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = c.compGroup;
    if (g == null) return const SizedBox.shrink();
    final hash = widget.take < g.takes.length ? g.takes[widget.take] : null;
    final gone = hash != null && c.missing.contains(hash);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // o trecho começa onde o dedo ou o mouse tocou, não onde o arraste foi reconhecido (depois da folga)
      dragStartBehavior: DragStartBehavior.down,
      onTapUp: (d) => _tap(d.localPosition.dx),
      onHorizontalDragStart: (d) => setState(() => _from = _to = c.snapBeat(_beat(d.localPosition.dx))),
      onHorizontalDragUpdate: (d) => setState(() => _to = c.snapBeat(_beat(d.localPosition.dx))),
      onHorizontalDragEnd: (_) => _end(),
      onHorizontalDragCancel: () => setState(() => _from = _to = null),
      child: CustomPaint(
        painter: _CompLanePainter(
          wave: hash == null ? null : c.waveforms[hash],
          segs: c.compSegs,
          take: widget.take,
          origin: g.origin,
          tempo: c.doc.tempo,
          scroll: c.scrollBeat,
          ppb: c.pxPerBeat,
          color: gone ? Colors.white24 : widget.color,
          drag: _from == null || _to == null ? null : (math.min(_from!, _to!), math.max(_from!, _to!)),
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _CompLanePainter extends CustomPainter {
  final Waveform? wave;
  final List<CompSeg> segs;
  final int take;
  final double origin, scroll, ppb;
  final TempoMap tempo;
  final Color color;
  final (double, double)? drag;
  _CompLanePainter({
    required this.wave,
    required this.segs,
    required this.take,
    required this.origin,
    required this.tempo,
    required this.scroll,
    required this.ppb,
    required this.color,
    required this.drag,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (segs.isEmpty) return;
    double x(double sec) => (tempo.beatAt(sec) - scroll) * ppb;
    final mid = size.height / 2;
    final amp = size.height / 2 * 0.85;
    for (final s in segs) {
      final x0 = x(s.s), x1 = x(s.e);
      if (x1 < 0 || x0 > size.width) continue;
      final on = s.take == take;
      canvas.drawRect(Rect.fromLTRB(x0, 1, x1, size.height - 1), Paint()..color = color.withValues(alpha: on ? 0.22 : 0.05));
      final w = wave;
      if (w != null) {
        final paint = Paint()
          ..color = color.withValues(alpha: on ? 0.95 : 0.35)
          ..strokeWidth = 1;
        final n = w.mins.length;
        for (var px = math.max(0, x0.floor()); px < math.min(size.width, x1.ceil().toDouble()); px++) {
          final t0 = tempo.secondsAt(scroll + px / ppb) - origin;
          final t1 = tempo.secondsAt(scroll + (px + 1) / ppb) - origin;
          final a = (t0 * w.perSecond).floor();
          final b = math.max(a + 1, (t1 * w.perSecond).floor());
          if (a < 0) continue;
          if (a >= n) break;
          var lo = 0.0, hi = 0.0;
          for (var i = a; i < b && i < n; i++) {
            final mn = w.mins[i], mx = w.maxs[i];
            if (mn < lo) lo = mn;
            if (mx > hi) hi = mx;
          }
          canvas.drawLine(Offset(px + 0.5, mid - hi * amp), Offset(px + 0.5, mid - lo * amp + 0.5), paint);
        }
      }
      // a emenda entre trechos
      canvas.drawRect(Rect.fromLTWH(x0, 0, 1, size.height), Paint()..color = Colors.white.withValues(alpha: 0.35));
    }
    final d = drag;
    if (d != null) {
      final r = Rect.fromLTRB((d.$1 - scroll) * ppb, 0, (d.$2 - scroll) * ppb, size.height);
      canvas.drawRect(r, Paint()..color = Palette.accent.withValues(alpha: 0.25));
      canvas.drawRect(
        r,
        Paint()
          ..color = Palette.accent
          ..style = PaintingStyle.stroke,
      );
    }
  }

  @override
  bool shouldRepaint(_CompLanePainter o) => true;
}
