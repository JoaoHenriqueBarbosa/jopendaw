/// As rodas de pitch bend e de modulação do teclado da tela: a de bend volta ao centro quando o
/// dedo (ou o mouse) solta; a de modulação fica onde foi deixada, como nos teclados de verdade.
/// Os valores vão ao motor por [DawController.pitchBend] e [DawController.modWheel], na faixa em que
/// o teclado toca, e a gravação de MIDI captura o que se fez com elas.
library;

import 'package:flutter/material.dart';

import '../widgets/theme.dart';
import 'controller.dart';
import 'midi_cc.dart';
import 'model.dart';

/// Par de rodas (bend e modulação) para a faixa [track].
class ExpressionWheels extends StatelessWidget {
  final DawController c;
  final int track;
  final double height;
  final Color color;

  const ExpressionWheels({super.key, required this.c, required this.track, required this.height, required this.color});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      ExpressionWheel(
        key: ValueKey('bend-$track'),
        label: 'Pitch bend',
        height: height,
        color: color,
        springBack: true,
        onChanged: (v) => c.pitchBend(v, track: track, screen: true),
      ),
      const SizedBox(width: 4),
      ExpressionWheel(
        key: ValueKey('mod-$track'),
        label: 'Modulação',
        height: height,
        color: color,
        springBack: false,
        onChanged: (v) => c.modWheel(v, track: track, screen: true),
      ),
    ],
  );
}

/// Uma roda vertical. Com [springBack] vai de −1 a 1 e volta a 0 ao soltar (numa curva curta, não
/// num pulo); sem ela vai de 0 a 1 e fica.
class ExpressionWheel extends StatefulWidget {
  final String label;
  final double height;
  final Color color;
  final bool springBack;

  /// Recebe o valor: −1..1 com [springBack], senão 0..1.
  final ValueChanged<double> onChanged;

  const ExpressionWheel({super.key, required this.label, required this.height, required this.color, required this.springBack, required this.onChanged});

  @override
  State<ExpressionWheel> createState() => _ExpressionWheelState();
}

class _ExpressionWheelState extends State<ExpressionWheel> with SingleTickerProviderStateMixin {
  static const _width = 24.0;
  static const _pad = 5.0;

  late final AnimationController _spring = AnimationController(vsync: this, duration: const Duration(milliseconds: 140))..addListener(_springTick);
  double _value = 0;
  double _from = 0;
  int? _pointer;

  @override
  void dispose() {
    _spring.dispose();
    // a roda some com a tela: o que ela deixou no motor volta ao repouso
    if (_value != 0) widget.onChanged(0);
    super.dispose();
  }

  double get _lo => widget.springBack ? -1 : 0;

  void _set(double v, {bool send = true}) {
    v = v.clamp(_lo, 1.0).toDouble();
    // a resolução única dos controles (bend em 14 bits, modulação em 7); o centro é exato
    v = quantizeControl(widget.springBack ? ccBend : ccMod, v);
    if (v == _value) return;
    setState(() => _value = v);
    if (send) widget.onChanged(v);
  }

  void _fromY(double y) {
    final span = (widget.height - 2 * _pad).clamp(1.0, double.infinity);
    final up = (1 - (y - _pad) / span).clamp(0.0, 1.0);
    _set(widget.springBack ? up * 2 - 1 : up);
  }

  void _springTick() {
    _set(_from * (1 - Curves.easeOut.transform(_spring.value)));
  }

  void _release() {
    _pointer = null;
    if (!widget.springBack) return;
    _from = _value;
    _spring.forward(from: 0).whenComplete(() {
      if (mounted && _spring.isCompleted) _set(0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.height;
    final center = widget.springBack;
    // o cursor da roda: 0 embaixo (modulação) ou no meio (bend)
    final norm = center ? (_value + 1) / 2 : _value;
    final y = _pad + (1 - norm) * (h - 2 * _pad);
    return Semantics(
      label: widget.label,
      value: '${(_value * 100).round()}%',
      child: Tooltip(
        message: center ? 'Pitch bend (solta e volta ao centro)' : 'Modulação (vibrato)',
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (e) {
            if (_pointer != null) return;
            _pointer = e.pointer;
            _spring.stop();
            _fromY(e.localPosition.dy);
          },
          onPointerMove: (e) {
            if (e.pointer == _pointer) _fromY(e.localPosition.dy);
          },
          onPointerUp: (e) {
            if (e.pointer == _pointer) _release();
          },
          onPointerCancel: (e) {
            if (e.pointer == _pointer) _release();
          },
          child: SizedBox(
            width: _width,
            height: h,
            child: CustomPaint(
              painter: _WheelPainter(y: y, center: center, color: widget.color, active: _value != 0),
            ),
          ),
        ),
      ),
    );
  }
}

class _WheelPainter extends CustomPainter {
  final double y;
  final bool center, active;
  final Color color;
  const _WheelPainter({required this.y, required this.center, required this.color, required this.active});

  @override
  void paint(Canvas canvas, Size size) {
    final body = RRect.fromRectAndRadius(Rect.fromLTWH(3, 0, size.width - 6, size.height), const Radius.circular(6));
    canvas.drawRRect(body, Paint()..color = Palette.canvas);
    canvas.drawRRect(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = active ? color.withValues(alpha: .8) : Palette.hairlineStrong,
    );
    // ranhuras da roda, para parecer uma roda
    final groove = Paint()..color = const Color(0x14FFFFFF);
    for (var gy = 6.0; gy < size.height - 4; gy += 5) {
      canvas.drawRect(Rect.fromLTWH(6, gy, size.width - 12, 1), groove);
    }
    if (center) canvas.drawRect(Rect.fromLTWH(3, size.height / 2 - .5, size.width - 6, 1), Paint()..color = const Color(0x55FFFFFF));
    final knob = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(size.width / 2, y), width: size.width - 4, height: 8), const Radius.circular(3));
    canvas.drawRRect(knob, Paint()..color = active ? color : Colors.white70);
  }

  @override
  bool shouldRepaint(_WheelPainter o) => o.y != y || o.active != active || o.color != color;
}
