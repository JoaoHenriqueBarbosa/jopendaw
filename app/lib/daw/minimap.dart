/// Visão geral: uma faixa fina embaixo do arranjo com o projeto inteiro (clipes na cor da faixa,
/// região do loop, marcadores, a janela visível e o cursor). Clicar ou arrastar leva a janela.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../widgets/theme.dart';
import 'controller.dart';

const minimapHeight = 28.0;

/// Quantas batidas o minimapa mostra: o arranjo, a janela e ao menos quatro compassos, com uma
/// folga no fim para poder arrastar a janela um pouco além do último clipe.
double minimapSpan(DawController c) {
  final view = c.viewWidth / c.pxPerBeat;
  final content = math.max(c.arrangementEnd, c.scrollBeat + view);
  return math.max(content * 1.05, c.doc.beatsPerBar * 4.0);
}

class Minimap extends StatelessWidget {
  final DawController c;
  const Minimap({super.key, required this.c});

  void _jump(double x, double width) {
    if (width <= 0) return;
    final span = minimapSpan(c);
    final view = c.viewWidth / c.pxPerBeat;
    // o ponto clicado vira o centro da janela
    c.scrollTo((x / width) * span - view / 2);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => _jump(d.localPosition.dx, box.maxWidth),
        onHorizontalDragStart: (d) => _jump(d.localPosition.dx, box.maxWidth),
        onHorizontalDragUpdate: (d) => _jump(d.localPosition.dx, box.maxWidth),
        child: Semantics(
          label: 'Visão geral do projeto',
          child: Container(
            height: minimapHeight,
            decoration: const BoxDecoration(
              color: Palette.bar,
              border: Border(top: BorderSide(color: Palette.hairline)),
            ),
            child: ValueListenableBuilder<double>(
              valueListenable: c.beat,
              builder: (context, beat, _) => CustomPaint(painter: _MinimapPainter(c, beat), size: Size.infinite),
            ),
          ),
        ),
      ),
    );
  }
}

class _MinimapPainter extends CustomPainter {
  final DawController c;
  final double beat;
  _MinimapPainter(this.c, this.beat);

  @override
  void paint(Canvas canvas, Size size) {
    final d = c.doc;
    final span = minimapSpan(c);
    final px = size.width / span;
    const top = 3.0;
    final area = size.height - 2 * top;

    // região do loop
    if (d.loopEnd > d.loopStart) {
      final color = d.loopOn ? Palette.accent : Colors.white24;
      canvas.drawRect(Rect.fromLTRB(d.loopStart * px, 0, d.loopEnd * px, size.height), Paint()..color = color.withValues(alpha: d.loopOn ? 0.2 : 0.07));
    }

    // um fio por faixa; sem faixas com clipes nada a desenhar
    final n = d.tracks.length;
    if (n > 0) {
      final rowH = area / n;
      final h = math.max(1.0, math.min(rowH - 0.5, 6.0));
      for (var i = 0; i < n; i++) {
        final t = d.tracks[i];
        final p = Paint()..color = trackColorAt(t.color).withValues(alpha: 0.85);
        final y = top + i * rowH + (rowH - h) / 2;
        for (final clip in t.clips) {
          canvas.drawRect(Rect.fromLTWH(clip.start * px, y, math.max(1.5, d.clipBeats(clip) * px), h), p);
        }
        for (final clip in t.midi) {
          canvas.drawRect(Rect.fromLTWH(clip.start * px, y, math.max(1.5, clip.length * px), h), p);
        }
      }
    }

    // marcadores
    for (final m in d.markers) {
      canvas.drawRect(Rect.fromLTWH(m.beat * px - 0.5, 0, 1.5, size.height), Paint()..color = Color(m.color));
    }

    // a janela visível
    final view = c.viewWidth / c.pxPerBeat;
    final win = Rect.fromLTWH(c.scrollBeat * px, 0.5, math.min(view * px, size.width - c.scrollBeat * px), size.height - 1);
    canvas.drawRect(win, Paint()..color = Colors.white.withValues(alpha: 0.1));
    canvas.drawRect(
      win,
      Paint()
        ..color = Colors.white54
        ..style = PaintingStyle.stroke,
    );

    // cursor de reprodução
    final x = beat * px;
    if (x >= 0 && x <= size.width) canvas.drawRect(Rect.fromLTWH(x - 0.5, 0, 1, size.height), Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_MinimapPainter o) => true;
}
