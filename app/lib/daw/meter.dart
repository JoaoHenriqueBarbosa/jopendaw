/// Medidor de pico estéreo, alimentado pelos picos que o motor manda ~60 vezes por segundo.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../widgets/theme.dart';

class Meter extends StatefulWidget {
  final ValueNotifier<Float32List> peaks;

  /// Faixa [index]; negativo é o master (o último par).
  final int index;
  final double width;
  const Meter({super.key, required this.peaks, required this.index, this.width = 8});

  @override
  State<Meter> createState() => _MeterState();
}

class _MeterState extends State<Meter> {
  double _l = 0, _r = 0;

  @override
  void initState() {
    super.initState();
    widget.peaks.addListener(_onPeaks);
  }

  @override
  void didUpdateWidget(Meter old) {
    super.didUpdateWidget(old);
    if (old.peaks != widget.peaks) {
      old.peaks.removeListener(_onPeaks);
      widget.peaks.addListener(_onPeaks);
    }
  }

  @override
  void dispose() {
    widget.peaks.removeListener(_onPeaks);
    super.dispose();
  }

  void _onPeaks() {
    final p = widget.peaks.value;
    final i = widget.index < 0 ? p.length - 2 : widget.index * 2;
    final (nl, nr) = i >= 0 && i + 1 < p.length ? (p[i].toDouble(), p[i + 1].toDouble()) : (0.0, 0.0);
    // sobe na hora, desce devagar
    final l = math.max(nl, _l * 0.82), r = math.max(nr, _r * 0.82);
    if ((l - _l).abs() < 0.001 && (r - _r).abs() < 0.001) return;
    setState(() {
      _l = l;
      _r = r;
    });
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: widget.width,
    child: CustomPaint(painter: _MeterPainter(_l, _r), size: Size.infinite),
  );
}

/// Pico linear → 0..1 numa escala de −48 a 0 dB.
double _level(double p) {
  if (p <= 0) return 0;
  final db = 20 * math.log(p) / math.ln10;
  return ((db + 48) / 48).clamp(0.0, 1.0);
}

class _MeterPainter extends CustomPainter {
  final double l, r;
  _MeterPainter(this.l, this.r);

  static const _gradient = LinearGradient(
    begin: Alignment.bottomCenter,
    end: Alignment.topCenter,
    colors: [Palette.success, Palette.success, Color(0xFFE3B341), Palette.danger],
    stops: [0, 0.7, 0.88, 1],
  );

  @override
  void paint(Canvas canvas, Size size) {
    final w = (size.width - 1) / 2;
    final bg = Paint()..color = Colors.white.withValues(alpha: 0.06);
    final full = Offset.zero & size;
    final fill = Paint()..shader = _gradient.createShader(full);
    for (final (i, v) in [(0, l), (1, r)]) {
      final x = i * (w + 1);
      canvas.drawRect(Rect.fromLTWH(x, 0, w, size.height), bg);
      final h = _level(v) * size.height;
      canvas.drawRect(Rect.fromLTWH(x, size.height - h, w, h), fill);
    }
  }

  @override
  bool shouldRepaint(_MeterPainter o) => o.l != l || o.r != r;
}
