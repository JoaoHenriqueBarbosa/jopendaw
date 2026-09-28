/// O arranjo: régua, cabeçalhos das faixas e as raias com os clipes (de áudio nas faixas de áudio,
/// de notas nas de instrumento), mais o cursor de reprodução.
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
import 'instruments.dart';
import 'meter.dart';
import 'model.dart';

const _rulerHeight = 30.0;

// ---------------------------------------------------------------------- ações sobre a seleção
// Delete, Ctrl+D, S e os botões da barra valem para clipes de áudio e de notas: o controlador
// trata os dois tipos; aqui só entra o que é da tela (o editor aberto segue a seleção).

/// Apaga o clipe selecionado, de áudio ou de notas.
void deleteSelectedClip(DawController c) => c.deleteSelected();

/// Duplica o clipe selecionado logo depois dele; com o editor aberto, ele passa à cópia.
void duplicateSelectedClip(DawController c) {
  c.duplicateSelected();
  final id = c.selectedClip;
  if (id != null && c.dock == Dock.editor && c.editingClip != id && c.findMidiClip(id) != null) c.openPianoRoll(id);
}

/// Corta no cursor de reprodução o clipe selecionado ou, sem seleção, o que o cursor cruza na faixa
/// atual. Nos clipes de notas, a nota que cruza o corte vira duas ([splitMidiClip]).
void splitClipsAtPlayhead(DawController c) => c.splitAtPlayhead();

/// Seleciona um clipe de notas; com o editor aberto, ele passa a mostrar esse clipe.
void _selectMidi(DawController c, String id, int track) {
  c.selectedTrack = track;
  c.selectClip(id);
  if (c.dock == Dock.editor && c.editingClip != id) c.openPianoRoll(id);
}

/// Encaixe dos arrastes; com Alt apertado, livre (ajuste fino sem mexer na grade).
double _snapDrag(DawController c, double b) => HardwareKeyboard.instance.isAltPressed ? b : c.snapBeat(b);

/// Passo da grade em batidas (0 = livre).
double _gridBeats(DawController c) => c.snap == Snap.bar ? c.doc.beatsPerBar.toDouble() : c.snap.beats;

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
                              child: _Lanes(c: c, laneHeight: laneHeight, width: laneWidth, touch: compact),
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

class _TrackHeader extends StatefulWidget {
  final DawController c;
  final int index;
  final double height;
  final bool compact;
  const _TrackHeader({required this.c, required this.index, required this.height, required this.compact});

  @override
  State<_TrackHeader> createState() => _TrackHeaderState();
}

class _TrackHeaderState extends State<_TrackHeader> {
  // duplo toque à mão: o `onDoubleTap` seguraria por 300 ms os toques nos botões de dentro (M, S,
  // ícone, menu) esperando um segundo toque
  final _taps = _DoubleTap();

  DawController get c => widget.c;
  int get index => widget.index;
  double get height => widget.height;
  bool get compact => widget.compact;

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
      onTapUp: (d) {
        c.selectTrack(index);
        if (_taps(d.globalPosition)) _rename(context, t);
      },
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
                        // no celular o ícone desce para a linha do M/S: o nome precisa do espaço
                        if (!compact) ...[_KindButton(c: c, index: index, color: color), const SizedBox(width: 4)],
                        Expanded(
                          child: Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelLarge),
                        ),
                        _TrackMenu(c: c, index: index, onRename: () => _rename(context, t)),
                      ],
                    ),
                    Row(
                      children: [
                        if (compact) ...[_KindButton(c: c, index: index, color: color), const SizedBox(width: 2)],
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

/// Abre (ou fecha) o painel do instrumento da faixa.
void _toggleInstrument(DawController c, int index) {
  if (c.dock == Dock.instrument && c.selectedTrack == index) {
    c.setDock(Dock.none);
    return;
  }
  c.selectTrack(index);
  c.setDock(Dock.instrument);
}

/// O ícone do tipo da faixa. Nas de instrumento é um botão que abre o painel do instrumento.
class _KindButton extends StatelessWidget {
  final DawController c;
  final int index;
  final Color color;
  const _KindButton({required this.c, required this.index, required this.color});

  @override
  Widget build(BuildContext context) {
    final t = c.doc.tracks[index];
    if (!t.kind.isInstrument) {
      return Tooltip(
        message: 'Faixa de áudio',
        child: SizedBox(width: 24, height: 24, child: Icon(t.kind.icon, size: 16, color: color)),
      );
    }
    final open = c.dock == Dock.instrument && c.selectedTrack == index;
    return SizedBox(
      width: 24,
      height: 24,
      child: IconButton(
        padding: EdgeInsets.zero,
        iconSize: 16,
        tooltip: open ? 'Fechar o instrumento (I)' : '${t.kind.label}: abrir o instrumento (I)',
        style: IconButton.styleFrom(
          backgroundColor: open ? color.withValues(alpha: 0.22) : null,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
        onPressed: () => _toggleInstrument(c, index),
        icon: Icon(t.kind.icon, color: color),
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
          case 'instrument':
            _toggleInstrument(c, index);
          case 'rename':
            onRename();
          case 'color':
            final t = c.doc.tracks[index];
            c.edit((_) => t.color = (t.color + 1) % Palette.tracks.length);
          case 'delete':
            final t = c.doc.tracks[index];
            if ((t.clips.isNotEmpty || t.midi.isNotEmpty) &&
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
      itemBuilder: (_) => [
        if (c.doc.tracks[index].kind.isInstrument) const PopupMenuItem(value: 'instrument', child: Text('Abrir o instrumento')),
        const PopupMenuItem(value: 'rename', child: Text('Renomear')),
        const PopupMenuItem(value: 'color', child: Text('Trocar a cor')),
        const PopupMenuItem(value: 'delete', child: Text('Apagar a faixa')),
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
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Container(
      height: height,
      decoration: const BoxDecoration(
        color: Palette.bar,
        border: Border(right: BorderSide(color: Palette.hairline)),
      ),
      alignment: Alignment.center,
      child: PopupMenuButton<TrackKind>(
        tooltip: 'Nova faixa',
        position: PopupMenuPosition.under,
        onSelected: (k) => k == TrackKind.audio ? c.addTrack() : c.addInstrumentTrack(k),
        itemBuilder: (_) => [
          for (final k in TrackKind.values)
            PopupMenuItem(
              value: k,
              child: Row(children: [Icon(k.icon, size: 18), const SizedBox(width: 12), Text(k.label)]),
            ),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add, size: 18, color: accent),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Faixa',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge!.copyWith(color: accent),
                ),
              ),
              Icon(Icons.arrow_drop_down, size: 18, color: accent),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------- raias

class _Lanes extends StatefulWidget {
  final DawController c;
  final double laneHeight, width;

  /// Aparelho de toque (muda só o texto da dica das faixas vazias).
  final bool touch;
  const _Lanes({required this.c, required this.laneHeight, required this.width, required this.touch});

  @override
  State<_Lanes> createState() => _LanesState();
}

class _LanesState extends State<_Lanes> {
  final _taps = _DoubleTap();

  DawController get c => widget.c;

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

  void _onTapUp(TapUpDetails d) {
    c.selectClip(null);
    final lane = (d.localPosition.dy / widget.laneHeight).floor();
    final at = _beatAt(d.localPosition.dx);
    if (lane < c.doc.tracks.length) c.selectTrack(lane);
    c.seek(c.snapBeat(at));
    if (_taps(d.globalPosition) && lane < c.doc.tracks.length && c.doc.tracks[lane].kind.isInstrument) _createClip(lane, at);
  }

  /// Duplo toque no vazio de uma faixa de instrumento: clipe novo no compasso tocado, sem montar
  /// em cima dos vizinhos (começa depois do anterior e termina antes do próximo), já no editor.
  void _createClip(int lane, double at) {
    final t = c.doc.tracks[lane];
    final bar = c.doc.beatsPerBar.toDouble();
    var start = (math.max(0.0, at) / bar).floor() * bar;
    for (final m in t.midi) {
      if (m.start < at && m.end > start) start = math.max(start, m.end);
    }
    var length = bar;
    for (final m in t.midi) {
      if (m.start > start && m.start < start + length) length = m.start - start;
    }
    final clip = c.createMidiClip(lane, start, length: length);
    c.openPianoRoll(clip.id);
  }

  @override
  Widget build(BuildContext context) {
    final laneHeight = widget.laneHeight;
    final visibleEnd = c.scrollBeat + widget.width / c.pxPerBeat;
    final bpm = c.doc.bpm;
    final tracks = c.doc.tracks;
    // o clipe selecionado fica montado mesmo fora da janela: é ele que está sendo arrastado, e
    // desmontar no meio do gesto o perderia
    bool shown(String id, double start, double end) => (end > c.scrollBeat && start < visibleEnd) || id == c.selectedClip;
    final hint = Theme.of(context).textTheme.labelSmall!.copyWith(color: Colors.white30);
    return Listener(
      onPointerSignal: _onSignal,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: _onTapUp,
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
                    lanes: tracks.length,
                    selected: c.selectedTrack,
                  ),
                ),
              ),
              for (var ti = 0; ti < tracks.length; ti++)
                if (tracks[ti].kind.isInstrument && tracks[ti].midi.isEmpty)
                  Positioned(
                    left: 12,
                    right: 12,
                    top: ti * laneHeight,
                    height: laneHeight,
                    child: IgnorePointer(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          widget.touch ? 'Toque duas vezes para criar um clipe de notas' : 'Clique duas vezes para criar um clipe de notas',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: hint,
                        ),
                      ),
                    ),
                  ),
              for (var ti = 0; ti < tracks.length; ti++) ...[
                for (final clip in tracks[ti].clips)
                  if (shown(clip.id, clip.start, clip.end(bpm)))
                    Positioned(
                      key: ValueKey(clip.id),
                      left: (clip.start - c.scrollBeat) * c.pxPerBeat,
                      top: ti * laneHeight + 2,
                      width: math.max(4, clip.beats(bpm) * c.pxPerBeat),
                      height: laneHeight - 4,
                      child: _ClipView(c: c, clip: clip, track: ti, laneHeight: laneHeight),
                    ),
                for (final clip in tracks[ti].midi)
                  if (shown(clip.id, clip.start, clip.end))
                    Positioned(
                      key: ValueKey('midi:${clip.id}'),
                      left: (clip.start - c.scrollBeat) * c.pxPerBeat,
                      top: ti * laneHeight + 2,
                      width: math.max(4, clip.length * c.pxPerBeat),
                      height: laneHeight - 4,
                      child: _MidiClipView(c: c, clip: clip, track: ti, laneHeight: laneHeight),
                    ),
              ],
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

// ---------------------------------------------------------------------- clipes

enum _Grab { move, left, right, fadeIn, fadeOut }

MouseCursor _cursorFor(_Grab g) => switch (g) {
  _Grab.left || _Grab.right => SystemMouseCursors.resizeLeftRight,
  _Grab.fadeIn || _Grab.fadeOut => SystemMouseCursors.precise,
  _Grab.move => SystemMouseCursors.grab,
};

/// Duplo toque sem o `onDoubleTap` do Flutter, que segura o toque simples por 300 ms esperando o
/// segundo: aqui o primeiro age na hora e o segundo, perto no tempo e no espaço, vira o duplo.
class _DoubleTap {
  DateTime? _at;
  Offset _pos = Offset.zero;

  bool call(Offset global) {
    final now = DateTime.now();
    final hit = _at != null && now.difference(_at!) < kDoubleTapTimeout && (global - _pos).distance < 40;
    _at = hit ? null : now;
    _pos = global;
    return hit;
  }
}

/// Arraste de clipe que aceita com a mesma folga do arraste horizontal das raias e da rolagem
/// vertical da lista (o pan comum pede o dobro). Como o clipe recebe o movimento antes dos
/// ancestrais, ele ganha a disputa; senão arrastar um clipe rolaria a linha do tempo.
class _ClipPanGestureRecognizer extends PanGestureRecognizer {
  _ClipPanGestureRecognizer({super.debugOwner});

  @override
  bool hasSufficientGlobalDistanceToAccept(PointerDeviceKind pointerDeviceKind, double? deviceTouchSlop) =>
      globalDistanceMoved.abs() > computeHitSlop(pointerDeviceKind, gestureSettings);
}

/// Gestos comuns aos clipes: cursor conforme a zona sob o ponteiro, seleção ao encostar, arraste
/// com o deslocamento total desde o início (cada clipe guarda o estado de antes e recalcula a
/// partir dele, sem acumular erro de encaixe), duplo toque e menu de contexto (botão direito, ou
/// toque longo no celular).
class _ClipGestures extends StatefulWidget {
  /// Zona do clipe num ponto; `edge` é a largura das bordas de aparar.
  final _Grab Function(Offset p, Size size, double edge) hit;
  final VoidCallback onSelect;
  final ValueChanged<_Grab> onStart;
  final void Function(_Grab grab, Offset total) onDrag;

  /// Fim (ou cancelamento) do arraste.
  final VoidCallback? onEnd;
  final VoidCallback? onDoubleTap;
  final ValueChanged<Offset>? onMenu;
  final Widget child;

  const _ClipGestures({
    required this.hit,
    required this.onSelect,
    required this.onStart,
    required this.onDrag,
    required this.child,
    this.onEnd,
    this.onDoubleTap,
    this.onMenu,
  });

  @override
  State<_ClipGestures> createState() => _ClipGesturesState();
}

class _ClipGesturesState extends State<_ClipGestures> {
  _Grab? _grab;
  Offset _total = Offset.zero;
  MouseCursor _hover = SystemMouseCursors.grab;
  bool _touch = false;
  final _taps = _DoubleTap();

  /// Dedo pede borda mais larga que o mouse; clipe estreito guarda o meio para mover.
  double _edge(Size size) => math.min(_touch ? 16.0 : 8.0, size.width / 4);

  void _start(DragStartDetails d) {
    final size = context.size!;
    final g = widget.hit(d.localPosition, size, _edge(size));
    _total = Offset.zero;
    setState(() => _grab = g);
    widget.onStart(g);
  }

  void _update(DragUpdateDetails d) {
    final g = _grab;
    if (g == null) return;
    _total += d.delta;
    widget.onDrag(g, _total);
  }

  void _end() {
    final was = _grab;
    if (was != null && mounted) setState(() => _grab = null);
    if (was != null) widget.onEnd?.call();
  }

  @override
  Widget build(BuildContext context) {
    final menu = widget.onMenu;
    return MouseRegion(
      cursor: switch (_grab) {
        null => _hover,
        _Grab.move => SystemMouseCursors.grabbing,
        _Grab g => _cursorFor(g),
      },
      onHover: (e) {
        final size = context.size!;
        final cur = _cursorFor(widget.hit(e.localPosition, size, math.min(8.0, size.width / 4)));
        if (cur != _hover) setState(() => _hover = cur);
      },
      child: Listener(
        onPointerDown: (e) {
          _touch = e.kind == PointerDeviceKind.touch;
          widget.onSelect();
        },
        child: RawGestureDetector(
          gestures: {
            TapGestureRecognizer: GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
              () => TapGestureRecognizer(debugOwner: this),
              (r) => r
                // o toque do clipe precisa existir mesmo sem duplo: é ele que ganha do toque das
                // raias (que desmarcaria o clipe e moveria o cursor)
                ..onTapUp = (d) {
                  if (_taps(d.globalPosition)) widget.onDoubleTap?.call();
                }
                ..onSecondaryTapUp = menu == null ? null : (d) => menu(d.globalPosition),
            ),
            _ClipPanGestureRecognizer: GestureRecognizerFactoryWithHandlers<_ClipPanGestureRecognizer>(
              () => _ClipPanGestureRecognizer(debugOwner: this),
              (r) => r
                // a zona vale onde o dedo encostou, não onde o arraste foi reconhecido
                ..dragStartBehavior = DragStartBehavior.down
                ..onStart = _start
                ..onUpdate = _update
                ..onEnd = ((_) => _end())
                ..onCancel = _end,
            ),
            if (menu != null)
              LongPressGestureRecognizer: GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
                // só no toque: com mouse, segurar parado antes de arrastar é normal
                () => LongPressGestureRecognizer(debugOwner: this, supportedDevices: const {PointerDeviceKind.touch, PointerDeviceKind.stylus}),
                (r) => r..onLongPressStart = (d) => menu(d.globalPosition),
              ),
          },
          child: widget.child,
        ),
      ),
    );
  }
}

/// Um arraste vira um passo só no desfazer, e só se mudou algo: o checkpoint sai na primeira
/// mudança de fato, não ao encostar. Os clipes só chamam [change] quando o valor encaixado muda,
/// então os passos repetidos da grade nem chegam ao motor.
mixin _DragEdit<T extends StatefulWidget> on State<T> {
  DawController get ctl;
  bool _dirty = false;

  void beginEdit() => _dirty = false;

  void ensureCheckpoint() {
    if (_dirty) return;
    ctl.checkpoint();
    _dirty = true;
  }

  void change(void Function() fn) {
    ensureCheckpoint();
    ctl.mutate((_) => fn());
  }

  /// Id do clipe que o gesto mexe.
  String get editedClipId;

  /// Fim do arraste: se mexeu, o clipe fica por cima dos que agora cobre (no mesmo passo do
  /// desfazer, o checkpoint já foi feito no começo).
  void _endDrag() {
    if (!_dirty) return;
    _dirty = false;
    ctl.mutate((_) => ctl.placeOnTop(editedClipId));
  }
}

PopupMenuItem<String> _menuItem(String value, IconData icon, String label, {String? shortcut}) => PopupMenuItem(
  value: value,
  child: Row(
    children: [
      Icon(icon, size: 18),
      const SizedBox(width: 12),
      Expanded(child: Text(label)),
      if (shortcut != null) ...[const SizedBox(width: 16), Text(shortcut, style: const TextStyle(fontSize: 12, color: Colors.white54))],
    ],
  ),
);

Future<String?> _showMenuAt(BuildContext context, Offset global, List<PopupMenuEntry<String>> items) {
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  final p = overlay.globalToLocal(global);
  return showMenu<String>(context: context, position: RelativeRect.fromLTRB(p.dx, p.dy, overlay.size.width - p.dx, overlay.size.height - p.dy), items: items);
}

// ---------------------------------------------------------------------- clipe de áudio

class _ClipView extends StatefulWidget {
  final DawController c;
  final AudioClip clip;
  final int track;
  final double laneHeight;
  const _ClipView({required this.c, required this.clip, required this.track, required this.laneHeight});
  @override
  State<_ClipView> createState() => _ClipViewState();
}

class _ClipViewState extends State<_ClipView> with _DragEdit {
  late AudioClip _orig;
  late int _origTrack;

  @override
  DawController get ctl => widget.c;

  @override
  String get editedClipId => widget.clip.id;

  _Grab _hit(Offset p, Size size, double edge) {
    if (p.dy < 14 && p.dx < 14) return _Grab.fadeIn;
    if (p.dy < 14 && p.dx > size.width - 14) return _Grab.fadeOut;
    if (p.dx < edge) return _Grab.left;
    if (p.dx > size.width - edge) return _Grab.right;
    return _Grab.move;
  }

  void _start(_Grab _) {
    _orig = AudioClip.fromJson(widget.clip.toJson());
    // a faixa de partida: depois de trocar de faixa, `widget.track` já é a nova
    _origTrack = widget.track;
    beginEdit();
  }

  void _drag(_Grab grab, Offset total) {
    final c = widget.c;
    final clip = widget.clip;
    final bpm = c.doc.bpm;
    final dBeats = total.dx / c.pxPerBeat;
    final dur = c.doc.samples[clip.sample]?.duration ?? (_orig.offset + _orig.length);
    const minLen = 0.01;
    switch (grab) {
      case _Grab.move:
        final start = math.max(0.0, _snapDrag(c, _orig.start + dBeats));
        if (start != clip.start) change(() => clip.start = start);
        // áudio só troca para outra faixa de áudio
        final lane = (_origTrack + (total.dy / widget.laneHeight).round()).clamp(0, c.doc.tracks.length - 1);
        final current = c.doc.tracks.indexWhere((t) => t.clips.contains(clip));
        if (current >= 0 && lane != current && c.doc.tracks[lane].kind == TrackKind.audio) {
          ensureCheckpoint();
          c.moveClipToTrack(clip.id, lane);
        }
      case _Grab.left:
        var start = _snapDrag(c, _orig.start + dBeats);
        // não passa do começo do áudio nem do fim do clipe
        final minStart = math.max(0.0, _orig.start - _orig.offset * bpm / 60);
        final maxStart = math.max(minStart, _orig.end(bpm) - minLen * bpm / 60);
        start = start.clamp(minStart, maxStart);
        final secs = (start - _orig.start) * 60 / bpm;
        if (start != clip.start) {
          change(() {
            clip.start = start;
            clip.offset = _orig.offset + secs;
            clip.length = _orig.length - secs;
          });
        }
      case _Grab.right:
        final end = _snapDrag(c, _orig.end(bpm) + dBeats);
        final len = ((end - _orig.start) * 60 / bpm).clamp(minLen, math.max<double>(minLen, dur - _orig.offset));
        if (len != clip.length) change(() => clip.length = len);
      case _Grab.fadeIn:
        final f = (_orig.fadeIn + total.dx / c.pxPerBeat * 60 / bpm).clamp(0.0, math.max<double>(0.0, clip.length - clip.fadeOut));
        if (f != clip.fadeIn) change(() => clip.fadeIn = f);
      case _Grab.fadeOut:
        final f = (_orig.fadeOut - total.dx / c.pxPerBeat * 60 / bpm).clamp(0.0, math.max<double>(0.0, clip.length - clip.fadeIn));
        if (f != clip.fadeOut) change(() => clip.fadeOut = f);
    }
  }

  Future<void> _menu(Offset at) async {
    final c = widget.c;
    final v = await _showMenuAt(context, at, [
      _menuItem('duplicate', Icons.copy_all, 'Duplicar', shortcut: 'Ctrl+D'),
      _menuItem('split', Icons.content_cut, 'Cortar no cursor', shortcut: 'S'),
      _menuItem('delete', Icons.delete_outline, 'Apagar', shortcut: 'Delete'),
    ]);
    if (v == null || !mounted) return;
    // age sobre este clipe, qualquer que seja a seleção ao fechar o menu
    c.selectClip(widget.clip.id);
    switch (v) {
      case 'duplicate':
        c.duplicateSelected();
      case 'split':
        c.splitAtPlayhead();
      case 'delete':
        c.deleteSelected();
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
    return _ClipGestures(
      hit: _hit,
      onSelect: () => c.selectClip(clip.id),
      onStart: _start,
      onDrag: _drag,
      onEnd: _endDrag,
      onMenu: _menu,
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
                          visible: _visibleRange(c, clip.start),
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
    );
  }
}

// ---------------------------------------------------------------------- clipe de notas

class _MidiClipView extends StatefulWidget {
  final DawController c;
  final MidiClip clip;
  final int track;
  final double laneHeight;
  const _MidiClipView({required this.c, required this.clip, required this.track, required this.laneHeight});
  @override
  State<_MidiClipView> createState() => _MidiClipViewState();
}

class _MidiClipViewState extends State<_MidiClipView> with _DragEdit {
  late MidiClip _orig;
  late int _origTrack;

  @override
  DawController get ctl => widget.c;

  @override
  String get editedClipId => widget.clip.id;

  _Grab _hit(Offset p, Size size, double edge) {
    if (p.dx < edge) return _Grab.left;
    if (p.dx > size.width - edge) return _Grab.right;
    return _Grab.move;
  }

  void _start(_Grab _) {
    _orig = MidiClip.fromJson(widget.clip.toJson());
    _origTrack = widget.track;
    beginEdit();
  }

  /// Menor duração ao aparar: um passo da grade (1/16 de batida, livre).
  double _minLength() {
    final g = _gridBeats(widget.c);
    return g > 0 && !HardwareKeyboard.instance.isAltPressed ? g : 0.0625;
  }

  void _drag(_Grab grab, Offset total) {
    final c = widget.c;
    final clip = widget.clip;
    final dBeats = total.dx / c.pxPerBeat;
    switch (grab) {
      case _Grab.move:
        final start = math.max(0.0, _snapDrag(c, _orig.start + dBeats));
        if (start != clip.start) change(() => clip.start = start);
        // notas só trocam para outra faixa de instrumento
        final lane = (_origTrack + (total.dy / widget.laneHeight).round()).clamp(0, c.doc.tracks.length - 1);
        final current = c.doc.tracks.indexWhere((t) => t.midi.contains(clip));
        if (current >= 0 && lane != current && c.doc.tracks[lane].kind.isInstrument) {
          ensureCheckpoint();
          c.moveClipToTrack(clip.id, lane);
        }
      case _Grab.left:
        // aparar à esquerda anda o começo e desconta o mesmo das notas: elas ficam onde estavam
        // na linha do tempo (as que saem antes do 0 ficam guardadas e voltam ao desfazer o corte)
        final hi = math.max(0.0, _orig.end - _minLength());
        final start = _snapDrag(c, _orig.start + dBeats).clamp(0.0, hi);
        if (start != clip.start) {
          final delta = start - _orig.start;
          change(() {
            clip.start = start;
            clip.length = _orig.length - delta;
            for (var i = 0; i < clip.notes.length && i < _orig.notes.length; i++) {
              clip.notes[i].start = _orig.notes[i].start - delta;
            }
          });
        }
      case _Grab.right:
        final end = _snapDrag(c, _orig.end + dBeats);
        final len = math.max(_minLength(), end - _orig.start);
        if (len != clip.length) change(() => clip.length = len);
      case _Grab.fadeIn || _Grab.fadeOut:
        break;
    }
  }

  Future<void> _rename() async {
    final clip = widget.clip;
    final name = await promptText(
      context,
      title: 'Nome do clipe',
      label: 'Nome',
      hint: widget.c.doc.tracks[widget.track].name,
      initial: clip.name,
      action: 'Salvar',
      maxLength: 60,
    );
    if (name == null || name == clip.name) return;
    widget.c.edit((_) => clip.name = name);
  }

  Future<void> _menu(Offset at) async {
    final c = widget.c;
    final v = await _showMenuAt(context, at, [
      _menuItem('open', Icons.edit_note, 'Abrir no editor', shortcut: 'E'),
      _menuItem('rename', Icons.drive_file_rename_outline, 'Renomear'),
      _menuItem('duplicate', Icons.copy_all, 'Duplicar', shortcut: 'Ctrl+D'),
      _menuItem('split', Icons.content_cut, 'Cortar no cursor', shortcut: 'S'),
      _menuItem('delete', Icons.delete_outline, 'Apagar', shortcut: 'Delete'),
    ]);
    if (v == null || !mounted) return;
    _selectMidi(c, widget.clip.id, widget.track);
    switch (v) {
      case 'open':
        c.openPianoRoll(widget.clip.id);
      case 'rename':
        await _rename();
      case 'duplicate':
        duplicateSelectedClip(c);
      case 'split':
        splitClipsAtPlayhead(c);
      case 'delete':
        deleteSelectedClip(c);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final clip = widget.clip;
    final t = c.doc.tracks[widget.track];
    final color = trackColorAt(t.color);
    final selected = c.selectedClip == clip.id;
    final editing = c.dock == Dock.editor && c.editingClip == clip.id;
    return _ClipGestures(
      hit: _hit,
      onSelect: () => _selectMidi(c, clip.id, widget.track),
      onStart: _start,
      onDrag: _drag,
      onEnd: _endDrag,
      onDoubleTap: () => c.openPianoRoll(clip.id),
      onMenu: _menu,
      child: Container(
        decoration: BoxDecoration(
          color: color.withValues(alpha: selected ? 0.42 : 0.3),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: selected ? Colors.white : color.withValues(alpha: 0.9), width: selected ? 1.5 : 1),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Stack(
            children: [
              Positioned.fill(
                top: 16,
                bottom: 3,
                child: CustomPaint(
                  painter: _NotesPainter(
                    notes: clip.notes,
                    length: clip.length,
                    ppb: c.pxPerBeat,
                    color: Color.lerp(color, Colors.white, 0.45)!,
                    visible: _visibleRange(c, clip.start),
                  ),
                ),
              ),
              Positioned(
                left: 6,
                right: 6,
                top: 1,
                child: Row(
                  children: [
                    if (editing) ...[const Icon(Icons.edit_note, size: 13, color: Colors.white), const SizedBox(width: 3)],
                    Expanded(
                      child: Text(
                        clip.name.isEmpty ? t.name : clip.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Faixa horizontal (em pixels do próprio clipe) que está dentro da janela das raias. Os painters
/// desenham só ela, mas não podem descobri-la pelo `canvas.getLocalClipBounds()`: no Flutter web
/// esses limites vêm deslocados e o começo do clipe sumia do desenho.
(double, double) _visibleRange(DawController c, double clipStart) {
  final left = (clipStart - c.scrollBeat) * c.pxPerBeat;
  return (math.max(0.0, -left), c.viewWidth - left);
}

/// Miniatura das notas: a altura do desenho cobre só a faixa de notas que o clipe usa (com teto
/// na espessura de cada linha, para poucas notas não virarem blocos); o que passa do fim do clipe
/// ou fica antes do começo não aparece.
class _NotesPainter extends CustomPainter {
  final List<MidiNote> notes;
  final double length, ppb;
  final Color color;
  final (double, double) visible;
  _NotesPainter({required this.notes, required this.length, required this.ppb, required this.color, required this.visible});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.height <= 0) return;
    var lo = 128, hi = -1;
    for (final n in notes) {
      if (n.start >= length || n.end <= 0) continue;
      if (n.pitch < lo) lo = n.pitch;
      if (n.pitch > hi) hi = n.pitch;
    }
    if (hi < 0) return;
    final rows = hi - lo + 1;
    final rowH = math.min(math.max(2.0, size.height / 5), size.height / rows);
    final top = (size.height - rowH * rows) / 2;
    final barH = math.max(1.0, rowH > 3 ? rowH - 1 : rowH);
    final endX = length * ppb;
    final (viewLeft, viewRight) = visible;
    final paint = Paint();
    for (final n in notes) {
      final x0 = math.max(0.0, n.start) * ppb;
      final x1 = math.min(n.end, length) * ppb;
      if (x1 <= x0 || x0 >= endX || x1 < viewLeft || x0 > viewRight) continue;
      final w = math.max(1.5, x1 - x0 - (x1 - x0 > 4 ? 1 : 0));
      paint.color = color.withValues(alpha: 0.45 + 0.55 * n.velocity.clamp(0.0, 1.0));
      canvas.drawRect(Rect.fromLTWH(x0, top + (hi - n.pitch) * rowH, w, barH), paint);
    }
  }

  // as notas mudam no lugar (a lista é a mesma), então não há o que comparar barato: a linha do
  // tempo só se redesenha quando o documento ou a visão mudam
  @override
  bool shouldRepaint(_NotesPainter o) => true;
}

class _WavePainter extends CustomPainter {
  final Waveform? wave;
  final double offset, length, pxPerSec, gain;
  final Color color;
  final (double, double) visible;
  _WavePainter({
    required this.wave,
    required this.offset,
    required this.length,
    required this.pxPerSec,
    required this.gain,
    required this.color,
    required this.visible,
  });

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
    // só as colunas dentro da janela das raias
    final x0 = math.max(0, visible.$1.floor());
    final x1 = math.min(size.width, visible.$2.ceil().toDouble()).toInt();
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
      o.wave != wave || o.offset != offset || o.length != length || o.pxPerSec != pxPerSec || o.gain != gain || o.color != color || o.visible != visible;
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
