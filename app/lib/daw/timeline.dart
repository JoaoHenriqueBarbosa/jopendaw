/// O arranjo: régua, cabeçalhos das faixas e as raias com os clipes, mais o cursor de reprodução.
///
/// A rolagem horizontal e o zoom são do controlador (a janela começa em `scrollBeat` e cada batida
/// ocupa `pxPerBeat`); a vertical é um scroll comum que leva cabeçalhos e raias juntos.
library;

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/dialogs.dart';
import '../widgets/theme.dart';
import 'controller.dart';
import 'meter.dart';
import 'model.dart';

const _rulerHeight = 30.0;

class Timeline extends StatelessWidget {
  final DawController c;
  final bool compact;
  const Timeline({super.key, required this.c, required this.compact});

  double get headerWidth => compact ? 132 : 232;
  double get laneHeight => compact ? 64 : 76;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => LayoutBuilder(
        builder: (context, box) {
          final laneWidth = math.max(0.0, box.maxWidth - headerWidth);
          c.viewWidth = laneWidth;
          return Stack(
            children: [
              Column(
                children: [
                  SizedBox(
                    height: _rulerHeight,
                    child: Row(
                      children: [
                        Container(
                          width: headerWidth,
                          decoration: const BoxDecoration(
                            color: Palette.bar,
                            border: Border(
                              right: BorderSide(color: Palette.hairline),
                              bottom: BorderSide(color: Palette.hairline),
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          alignment: Alignment.centerLeft,
                          child: Text('${c.doc.tracks.length} faixas', style: Theme.of(context).textTheme.labelSmall),
                        ),
                        Expanded(child: _Ruler(c: c)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Container(
                      color: Palette.ink,
                      child: SingleChildScrollView(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: headerWidth,
                              child: Column(
                                children: [
                                  for (var i = 0; i < c.doc.tracks.length; i++) _TrackHeader(c: c, index: i, height: laneHeight, compact: compact),
                                  _AddTrackRow(c: c, height: laneHeight),
                                ],
                              ),
                            ),
                            SizedBox(
                              width: laneWidth,
                              height: (c.doc.tracks.length + 1) * laneHeight,
                              child: _Lanes(c: c, laneHeight: laneHeight, width: laneWidth),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              // cursor de reprodução por cima de régua e raias
              Positioned(
                left: headerWidth,
                top: 0,
                bottom: 0,
                width: laneWidth,
                child: IgnorePointer(child: _Playhead(c: c)),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------- cursor

class _Playhead extends StatelessWidget {
  final DawController c;
  const _Playhead({required this.c});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<double>(
    valueListenable: c.beat,
    builder: (context, beat, _) {
      final x = (beat - c.scrollBeat) * c.pxPerBeat;
      return CustomPaint(painter: _PlayheadPainter(x), size: Size.infinite);
    },
  );
}

class _PlayheadPainter extends CustomPainter {
  final double x;
  _PlayheadPainter(this.x);

  @override
  void paint(Canvas canvas, Size size) {
    if (x < -1 || x > size.width + 1) return;
    final p = Paint()..color = Colors.white;
    canvas.drawRect(Rect.fromLTWH(x - 0.5, 0, 1, size.height), p);
    final head = Path()
      ..moveTo(x - 6, 0)
      ..lineTo(x + 6, 0)
      ..lineTo(x, 8)
      ..close();
    canvas.drawPath(head, p);
  }

  @override
  bool shouldRepaint(_PlayheadPainter old) => old.x != x;
}

// ---------------------------------------------------------------------- régua

/// Clicar posiciona o cursor; arrastar desenha a região do loop.
class _Ruler extends StatefulWidget {
  final DawController c;
  const _Ruler({required this.c});
  @override
  State<_Ruler> createState() => _RulerState();
}

class _RulerState extends State<_Ruler> {
  double? _dragFrom;

  double _beatAt(double x) => widget.c.scrollBeat + x / widget.c.pxPerBeat;

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (d) => c.seek(c.snapBeat(_beatAt(d.localPosition.dx))),
      onHorizontalDragStart: (d) {
        c.checkpoint();
        _dragFrom = c.snapBeat(_beatAt(d.localPosition.dx));
      },
      onHorizontalDragUpdate: (d) {
        final to = c.snapBeat(_beatAt(d.localPosition.dx));
        c.setLoop(_dragFrom!, to);
      },
      onHorizontalDragEnd: (_) => _dragFrom = null,
      child: Container(
        decoration: const BoxDecoration(
          color: Palette.bar,
          border: Border(bottom: BorderSide(color: Palette.hairline)),
        ),
        child: CustomPaint(
          painter: _RulerPainter(
            scroll: c.scrollBeat,
            ppb: c.pxPerBeat,
            beatsPerBar: c.doc.beatsPerBar,
            loopOn: c.doc.loopOn,
            loopStart: c.doc.loopStart,
            loopEnd: c.doc.loopEnd,
            style: Theme.of(context).textTheme.labelSmall!,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

/// De quantas em quantas batidas vale desenhar um número, para não amontoar.
int _barStep(double ppb, int beatsPerBar) {
  final barPx = ppb * beatsPerBar;
  var step = 1;
  while (barPx * step < 48) {
    step *= 2;
  }
  return step;
}

class _RulerPainter extends CustomPainter {
  final double scroll, ppb, loopStart, loopEnd;
  final int beatsPerBar;
  final bool loopOn;
  final TextStyle style;

  _RulerPainter({
    required this.scroll,
    required this.ppb,
    required this.beatsPerBar,
    required this.loopOn,
    required this.loopStart,
    required this.loopEnd,
    required this.style,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // região do loop
    final lx = (loopStart - scroll) * ppb, rx = (loopEnd - scroll) * ppb;
    if (rx > lx) {
      final color = loopOn ? Palette.accent : Colors.white24;
      canvas.drawRect(Rect.fromLTRB(lx, 0, rx, size.height), Paint()..color = color.withValues(alpha: loopOn ? 0.22 : 0.08));
      canvas.drawRect(Rect.fromLTRB(lx, size.height - 3, rx, size.height), Paint()..color = color);
    }
    final step = _barStep(ppb, beatsPerBar);
    final tick = Paint()..color = Colors.white24;
    final first = (scroll / beatsPerBar).floor();
    final last = ((scroll + size.width / ppb) / beatsPerBar).ceil();
    for (var bar = first; bar <= last; bar++) {
      final x = (bar * beatsPerBar - scroll) * ppb;
      if (bar % step == 0) {
        canvas.drawRect(Rect.fromLTWH(x, 8, 1, size.height - 8), tick);
        final tp = TextPainter(
          text: TextSpan(
            text: '${bar + 1}',
            style: style.copyWith(color: Colors.white70),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x + 4, 4));
      }
      if (ppb >= 12) {
        for (var b = 1; b < beatsPerBar; b++) {
          final bx = x + b * ppb;
          canvas.drawRect(Rect.fromLTWH(bx, size.height - 8, 1, 8), tick);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_RulerPainter o) =>
      o.scroll != scroll || o.ppb != ppb || o.beatsPerBar != beatsPerBar || o.loopOn != loopOn || o.loopStart != loopStart || o.loopEnd != loopEnd;
}

// ---------------------------------------------------------------------- cabeçalhos

class _TrackHeader extends StatelessWidget {
  final DawController c;
  final int index;
  final double height;
  final bool compact;
  const _TrackHeader({required this.c, required this.index, required this.height, required this.compact});

  Future<void> _rename(BuildContext context, DawTrack t) async {
    final name = await promptText(context, title: 'Nome da faixa', label: 'Nome', initial: t.name, action: 'Salvar', maxLength: 60);
    if (name == null || name.trim().isEmpty) return;
    c.edit((_) => t.name = name.trim());
  }

  @override
  Widget build(BuildContext context) {
    final t = c.doc.tracks[index];
    final color = trackColorAt(t.color);
    final selected = c.selectedTrack == index;
    return GestureDetector(
      onTap: () => c.selectTrack(index),
      onDoubleTap: () => _rename(context, t),
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: selected ? Palette.overlay : Palette.bar,
          border: const Border(
            right: BorderSide(color: Palette.hairline),
            bottom: BorderSide(color: Palette.hairline),
          ),
        ),
        child: Row(
          children: [
            Container(width: 4, color: color),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelLarge),
                        ),
                        _TrackMenu(c: c, index: index, onRename: () => _rename(context, t)),
                      ],
                    ),
                    Row(
                      children: [
                        ToggleChip(label: 'M', on: t.mute, color: Palette.danger, tooltip: 'Mudo', onTap: () => c.edit((_) => t.mute = !t.mute)),
                        const SizedBox(width: 4),
                        ToggleChip(label: 'S', on: t.solo, color: const Color(0xFFE3B341), tooltip: 'Solo', onTap: () => c.edit((_) => t.solo = !t.solo)),
                        if (!compact) ...[
                          const SizedBox(width: 4),
                          Expanded(
                            child: _MiniFader(c: c, track: t),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Meter(peaks: c.peaks, index: index, width: 6),
            ),
            const SizedBox(width: 6),
          ],
        ),
      ),
    );
  }
}

class _TrackMenu extends StatelessWidget {
  final DawController c;
  final int index;
  final VoidCallback onRename;
  const _TrackMenu({required this.c, required this.index, required this.onRename});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 28,
    height: 24,
    child: PopupMenuButton<String>(
      padding: EdgeInsets.zero,
      iconSize: 18,
      tooltip: 'Opções da faixa',
      icon: const Icon(Icons.more_vert),
      onSelected: (v) async {
        switch (v) {
          case 'rename':
            onRename();
          case 'color':
            final t = c.doc.tracks[index];
            c.edit((_) => t.color = (t.color + 1) % Palette.tracks.length);
          case 'delete':
            final t = c.doc.tracks[index];
            if (t.clips.isNotEmpty &&
                !await confirmAction(
                  context,
                  title: 'Apagar "${t.name}"?',
                  message: 'A faixa e os clipes dela saem do projeto (dá para desfazer).',
                  action: 'Apagar',
                  destructive: true,
                )) {
              return;
            }
            c.removeTrack(index);
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'rename', child: Text('Renomear')),
        PopupMenuItem(value: 'color', child: Text('Trocar a cor')),
        PopupMenuItem(value: 'delete', child: Text('Apagar a faixa')),
      ],
    ),
  );
}

class _MiniFader extends StatelessWidget {
  final DawController c;
  final DawTrack track;
  const _MiniFader({required this.c, required this.track});

  @override
  Widget build(BuildContext context) => Tooltip(
    message: '${formatDb(track.gain)} dB',
    child: SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 2,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
      ),
      child: SizedBox(
        height: 22,
        child: Slider(
          value: gainToFader(track.gain).clamp(0, 1),
          onChangeStart: (_) => c.checkpoint(),
          onChanged: (v) => c.mutate((_) => track.gain = faderToGain(v)),
        ),
      ),
    ),
  );
}

/// Botão M/S dos canais.
class ToggleChip extends StatelessWidget {
  final String label, tooltip;
  final bool on;
  final Color color;
  final VoidCallback onTap;
  const ToggleChip({super.key, required this.label, required this.on, required this.color, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        width: 24,
        height: 20,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: on ? color : Palette.hairlineStrong),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: on ? Colors.black : Colors.white70),
        ),
      ),
    ),
  );
}

class _AddTrackRow extends StatelessWidget {
  final DawController c;
  final double height;
  const _AddTrackRow({required this.c, required this.height});

  @override
  Widget build(BuildContext context) => Container(
    height: height,
    decoration: const BoxDecoration(
      color: Palette.bar,
      border: Border(right: BorderSide(color: Palette.hairline)),
    ),
    alignment: Alignment.center,
    child: TextButton.icon(onPressed: c.addTrack, icon: const Icon(Icons.add), label: const Text('Faixa')),
  );
}

// ---------------------------------------------------------------------- raias

class _Lanes extends StatelessWidget {
  final DawController c;
  final double laneHeight, width;
  const _Lanes({required this.c, required this.laneHeight, required this.width});

  double _beatAt(double x) => c.scrollBeat + x / c.pxPerBeat;

  void _onSignal(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    final keys = HardwareKeyboard.instance;
    final zoom = keys.isControlPressed || keys.isMetaPressed;
    final horizontal = keys.isShiftPressed || e.scrollDelta.dx.abs() > e.scrollDelta.dy.abs();
    if (!zoom && !horizontal) return; // rolagem vertical fica com a lista
    GestureBinding.instance.pointerSignalResolver.register(e, (ev) {
      final s = ev as PointerScrollEvent;
      if (zoom) {
        c.zoom(math.pow(1.0015, -s.scrollDelta.dy).toDouble(), anchorBeat: _beatAt(s.localPosition.dx));
      } else {
        c.scrollBy(s.scrollDelta.dx != 0 ? s.scrollDelta.dx : s.scrollDelta.dy);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final visibleEnd = c.scrollBeat + width / c.pxPerBeat;
    final bpm = c.doc.bpm;
    return Listener(
      onPointerSignal: _onSignal,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) {
          c.selectClip(null);
          final lane = (d.localPosition.dy / laneHeight).floor();
          if (lane < c.doc.tracks.length) c.selectTrack(lane);
          c.seek(c.snapBeat(_beatAt(d.localPosition.dx)));
        },
        onHorizontalDragUpdate: (d) => c.scrollBy(-d.delta.dx),
        child: ClipRect(
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _GridPainter(
                    scroll: c.scrollBeat,
                    ppb: c.pxPerBeat,
                    beatsPerBar: c.doc.beatsPerBar,
                    laneHeight: laneHeight,
                    lanes: c.doc.tracks.length,
                    selected: c.selectedTrack,
                  ),
                ),
              ),
              for (var ti = 0; ti < c.doc.tracks.length; ti++)
                for (final clip in c.doc.tracks[ti].clips)
                  if (clip.end(bpm) > c.scrollBeat && clip.start < visibleEnd)
                    Positioned(
                      key: ValueKey(clip.id),
                      left: (clip.start - c.scrollBeat) * c.pxPerBeat,
                      top: ti * laneHeight + 2,
                      width: math.max(4, clip.beats(bpm) * c.pxPerBeat),
                      height: laneHeight - 4,
                      child: _ClipView(c: c, clip: clip, track: ti, laneHeight: laneHeight),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  final double scroll, ppb, laneHeight;
  final int beatsPerBar, lanes, selected;
  _GridPainter({required this.scroll, required this.ppb, required this.beatsPerBar, required this.laneHeight, required this.lanes, required this.selected});

  @override
  void paint(Canvas canvas, Size size) {
    if (selected < lanes) {
      canvas.drawRect(Rect.fromLTWH(0, selected * laneHeight, size.width, laneHeight), Paint()..color = Colors.white.withValues(alpha: 0.025));
    }
    final line = Paint()..color = Palette.hairline;
    for (var i = 1; i <= lanes; i++) {
      canvas.drawRect(Rect.fromLTWH(0, i * laneHeight - 1, size.width, 1), line);
    }
    final bar = Paint()..color = Colors.white.withValues(alpha: 0.09);
    final beat = Paint()..color = Colors.white.withValues(alpha: 0.035);
    final step = _barStep(ppb, beatsPerBar);
    final first = scroll.floor();
    final last = (scroll + size.width / ppb).ceil();
    for (var b = first; b <= last; b++) {
      final x = (b - scroll) * ppb;
      if (b % beatsPerBar == 0) {
        if ((b ~/ beatsPerBar) % step == 0) canvas.drawRect(Rect.fromLTWH(x, 0, 1, size.height), bar);
      } else if (ppb >= 16) {
        canvas.drawRect(Rect.fromLTWH(x, 0, 1, size.height), beat);
      }
    }
  }

  @override
  bool shouldRepaint(_GridPainter o) =>
      o.scroll != scroll || o.ppb != ppb || o.beatsPerBar != beatsPerBar || o.lanes != lanes || o.selected != selected || o.laneHeight != laneHeight;
}

// ---------------------------------------------------------------------- clipe

enum _Grab { move, left, right, fadeIn, fadeOut }

class _ClipView extends StatefulWidget {
  final DawController c;
  final AudioClip clip;
  final int track;
  final double laneHeight;
  const _ClipView({required this.c, required this.clip, required this.track, required this.laneHeight});
  @override
  State<_ClipView> createState() => _ClipViewState();
}

class _ClipViewState extends State<_ClipView> {
  _Grab? _grab;
  late AudioClip _orig;
  Offset _drag = Offset.zero;
  MouseCursor _cursor = SystemMouseCursors.grab;

  static const _edge = 8.0;

  _Grab _hit(Offset p, Size size) {
    if (p.dy < 14 && p.dx < 14) return _Grab.fadeIn;
    if (p.dy < 14 && p.dx > size.width - 14) return _Grab.fadeOut;
    if (p.dx < _edge) return _Grab.left;
    if (p.dx > size.width - _edge) return _Grab.right;
    return _Grab.move;
  }

  MouseCursor _cursorFor(_Grab g) => switch (g) {
    _Grab.left || _Grab.right => SystemMouseCursors.resizeLeftRight,
    _Grab.fadeIn || _Grab.fadeOut => SystemMouseCursors.precise,
    _Grab.move => SystemMouseCursors.grab,
  };

  void _start(DragStartDetails d) {
    final c = widget.c;
    final size = context.size!;
    _grab = _hit(d.localPosition, size);
    _orig = AudioClip.fromJson(widget.clip.toJson());
    _drag = Offset.zero;
    c.checkpoint();
    c.selectClip(widget.clip.id);
  }

  void _update(DragUpdateDetails d) {
    final c = widget.c;
    _drag += d.delta;
    final clip = widget.clip;
    final bpm = c.doc.bpm;
    final dBeats = _drag.dx / c.pxPerBeat;
    final dur = c.doc.samples[clip.sample]?.duration ?? (_orig.offset + _orig.length);
    const minLen = 0.01;
    switch (_grab!) {
      case _Grab.move:
        final start = math.max(0.0, c.snapBeat(_orig.start + dBeats));
        c.mutate((_) => clip.start = start);
        final lane = widget.track + (_drag.dy / widget.laneHeight).round();
        final current = c.doc.tracks.indexWhere((t) => t.clips.contains(clip));
        if (lane != current) c.moveClipToTrack(clip.id, lane.clamp(0, c.doc.tracks.length - 1));
      case _Grab.left:
        var start = c.snapBeat(_orig.start + dBeats);
        // não passa do começo do áudio nem do fim do clipe
        final minStart = _orig.start - _orig.offset * bpm / 60;
        final maxStart = _orig.end(bpm) - minLen * bpm / 60;
        start = start.clamp(math.max(0.0, minStart), maxStart);
        final secs = (start - _orig.start) * 60 / bpm;
        c.mutate((_) {
          clip.start = start;
          clip.offset = _orig.offset + secs;
          clip.length = _orig.length - secs;
        });
      case _Grab.right:
        final end = c.snapBeat(_orig.end(bpm) + dBeats);
        final len = ((end - _orig.start) * 60 / bpm).clamp(minLen, dur - _orig.offset);
        c.mutate((_) => clip.length = len);
      case _Grab.fadeIn:
        final f = (_orig.fadeIn + _drag.dx / c.pxPerBeat * 60 / bpm).clamp(0.0, clip.length - clip.fadeOut);
        c.mutate((_) => clip.fadeIn = f);
      case _Grab.fadeOut:
        final f = (_orig.fadeOut - _drag.dx / c.pxPerBeat * 60 / bpm).clamp(0.0, clip.length - clip.fadeIn);
        c.mutate((_) => clip.fadeOut = f);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final clip = widget.clip;
    final t = c.doc.tracks[widget.track];
    final color = trackColorAt(t.color);
    final selected = c.selectedClip == clip.id;
    final missing = c.missing.contains(clip.sample);
    final name = c.doc.samples[clip.sample]?.name ?? 'áudio';
    final bpm = c.doc.bpm;
    final pxPerSec = c.pxPerBeat * bpm / 60;
    return MouseRegion(
      cursor: _cursor,
      onHover: (e) {
        final cur = _cursorFor(_hit(e.localPosition, context.size!));
        if (cur != _cursor) setState(() => _cursor = cur);
      },
      child: GestureDetector(
        onTap: () => c.selectClip(clip.id),
        onPanStart: _start,
        onPanUpdate: _update,
        onPanEnd: (_) => _grab = null,
        child: Container(
          decoration: BoxDecoration(
            color: (missing ? Palette.danger : color).withValues(alpha: selected ? 0.34 : 0.22),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: selected ? Colors.white : color.withValues(alpha: 0.8), width: selected ? 1.5 : 1),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Stack(
              children: [
                Positioned.fill(
                  top: 16,
                  child: missing
                      ? const Center(child: Text('áudio fora deste aparelho', style: TextStyle(fontSize: 11)))
                      : CustomPaint(
                          painter: _WavePainter(
                            wave: c.waveforms[clip.sample],
                            offset: clip.offset,
                            length: clip.length,
                            pxPerSec: pxPerSec,
                            gain: clip.gain,
                            color: color,
                          ),
                        ),
                ),
                Positioned.fill(
                  child: CustomPaint(
                    painter: _FadePainter(fadeIn: clip.fadeIn * pxPerSec, fadeOut: clip.fadeOut * pxPerSec),
                  ),
                ),
                Positioned(
                  left: 6,
                  right: 6,
                  top: 1,
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  final Waveform? wave;
  final double offset, length, pxPerSec, gain;
  final Color color;
  _WavePainter({required this.wave, required this.offset, required this.length, required this.pxPerSec, required this.gain, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = wave;
    if (w == null) return;
    final mid = size.height / 2;
    final amp = size.height / 2 * 0.95 * gain;
    final paint = Paint()
      ..color = color.withValues(alpha: 0.9)
      ..strokeWidth = 1;
    final bucketsPerPx = w.perSecond / pxPerSec;
    final first = offset * w.perSecond;
    final n = w.mins.length;
    // só as colunas visíveis dentro do recorte do clipe
    final clip = canvas.getLocalClipBounds();
    final x0 = math.max(0, clip.left.floor());
    final x1 = math.min(size.width, clip.right.ceil().toDouble()).toInt();
    for (var x = x0; x < x1; x++) {
      final a = (first + x * bucketsPerPx).floor();
      final b = math.max(a + 1, (first + (x + 1) * bucketsPerPx).floor());
      if (a >= n) break;
      var lo = 0.0, hi = 0.0;
      for (var i = a; i < b && i < n; i++) {
        if (w.mins[i] < lo) lo = w.mins[i];
        if (w.maxs[i] > hi) hi = w.maxs[i];
      }
      canvas.drawLine(Offset(x + 0.5, mid - hi * amp), Offset(x + 0.5, mid - lo * amp + 0.5), paint);
    }
  }

  @override
  bool shouldRepaint(_WavePainter o) =>
      o.wave != wave || o.offset != offset || o.length != length || o.pxPerSec != pxPerSec || o.gain != gain || o.color != color;
}

class _FadePainter extends CustomPainter {
  final double fadeIn, fadeOut;
  _FadePainter({required this.fadeIn, required this.fadeOut});

  @override
  void paint(Canvas canvas, Size size) {
    final shade = Paint()..color = Colors.black.withValues(alpha: 0.35);
    final line = Paint()
      ..color = Colors.white70
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    if (fadeIn > 0) {
      canvas.drawPath(
        Path()
          ..moveTo(0, 0)
          ..lineTo(fadeIn, 0)
          ..lineTo(0, size.height)
          ..close(),
        shade,
      );
      canvas.drawLine(Offset(0, size.height), Offset(fadeIn, 0), line);
    }
    if (fadeOut > 0) {
      canvas.drawPath(
        Path()
          ..moveTo(size.width, 0)
          ..lineTo(size.width - fadeOut, 0)
          ..lineTo(size.width, size.height)
          ..close(),
        shade,
      );
      canvas.drawLine(Offset(size.width - fadeOut, 0), Offset(size.width, size.height), line);
    }
    // alças de fade nos cantos de cima
    final knob = Paint()..color = Colors.white;
    canvas.drawCircle(Offset(math.max(5, fadeIn), 5), 3, knob);
    canvas.drawCircle(Offset(math.min(size.width - 5, size.width - fadeOut), 5), 3, knob);
  }

  @override
  bool shouldRepaint(_FadePainter o) => o.fadeIn != fadeIn || o.fadeOut != fadeOut;
}
