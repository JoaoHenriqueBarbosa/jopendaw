/// O arranjo: régua, cabeçalhos das faixas e as raias com os clipes (de áudio nas faixas de áudio,
/// de notas nas de instrumento), as sub-raias de automação abertas embaixo de cada faixa, a linha
/// do master no fim e o cursor de reprodução.
///
/// A rolagem horizontal e o zoom são do controlador (a janela começa em `scrollBeat` e cada batida
/// ocupa `pxPerBeat`); a vertical é um scroll comum que leva cabeçalhos e raias juntos, com as
/// alturas de uma conta só ([_Layout]).
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/dialogs.dart';
import '../widgets/theme.dart';
import 'automation_lane.dart';
import 'controller.dart';
import 'instruments.dart';
import 'meter.dart';
import 'model.dart';

const _rulerHeight = 30.0;

/// Altura da linha de "+ Faixa", entre as faixas e o master.
const _addRowHeight = 44.0;

/// Cor do master (e das automações dele) e dos botões A e FX dos cabeçalhos.
const _masterColor = Color(0xFFC9D1D9);
const _automationColor = Palette.accent;
const _effectsColor = Color(0xFF6BA8F0);

/// Cor da faixa, ou a do master (−1).
Color _trackColor(DawController c, int track) => track < 0 || track >= c.doc.tracks.length ? _masterColor : trackColorAt(c.doc.tracks[track].color);

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

  Widget _header(_Row r) => switch (r.kind) {
    _RowKind.track => _TrackHeader(key: ValueKey('t:${c.doc.tracks[r.track].id}'), c: c, index: r.track, height: r.height, compact: compact),
    _RowKind.lane => AutomationLaneHeader(
      key: ValueKey('a:${r.lane!.id}'),
      c: c,
      track: r.track,
      lane: r.lane!,
      color: _trackColor(c, r.track),
      height: r.height,
      compact: compact,
    ),
    _RowKind.add => _AddTrackRow(key: const ValueKey('add'), c: c, height: r.height),
    _RowKind.master => _MasterHeader(key: const ValueKey('master'), c: c, height: r.height, compact: compact),
  };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => LayoutBuilder(
        builder: (context, box) {
          final laneWidth = math.max(0.0, box.maxWidth - headerWidth);
          c.viewWidth = laneWidth;
          final layout = _Layout.of(c, laneHeight);
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
                              child: Column(children: [for (final r in layout.rows) _header(r)]),
                            ),
                            SizedBox(
                              width: laneWidth,
                              height: layout.height,
                              child: _Lanes(c: c, layout: layout, laneHeight: laneHeight, width: laneWidth, touch: compact),
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

// ---------------------------------------------------------------------- disposição vertical

enum _RowKind { track, lane, add, master }

/// Uma linha da lista vertical: faixa, sub-raia de automação, "+ Faixa" ou master.
class _Row {
  final _RowKind kind;

  /// Faixa da linha; −1 no master, nas automações dele e na linha de adicionar.
  final int track;
  final AutoLane? lane;
  final double top, height;
  const _Row(this.kind, this.track, this.top, this.height, [this.lane]);
}

/// Onde cada linha fica. Cabeçalhos e raias saem da mesma conta, então andam alinhados; cada
/// faixa ocupa um bloco (ela e as automações abertas embaixo), e é por bloco que um clipe
/// arrastado na vertical troca de faixa.
class _Layout {
  final List<_Row> rows;
  final List<double> trackTop, blockEnd;
  final double height;
  const _Layout._(this.rows, this.trackTop, this.blockEnd, this.height);

  factory _Layout.of(DawController c, double laneHeight) {
    final rows = <_Row>[];
    final tops = <double>[], ends = <double>[];
    var y = 0.0;
    void lanes(int track, List<AutoLane> list) {
      for (final l in list) {
        if (!l.open) continue;
        rows.add(_Row(_RowKind.lane, track, y, automationLaneHeight, l));
        y += automationLaneHeight;
      }
    }

    for (var i = 0; i < c.doc.tracks.length; i++) {
      tops.add(y);
      rows.add(_Row(_RowKind.track, i, y, laneHeight));
      y += laneHeight;
      lanes(i, c.doc.tracks[i].lanes);
      ends.add(y);
    }
    rows.add(_Row(_RowKind.add, -1, y, _addRowHeight));
    y += _addRowHeight;
    rows.add(_Row(_RowKind.master, -1, y, laneHeight));
    y += laneHeight;
    lanes(-1, c.doc.masterLanes);
    return _Layout._(rows, tops, ends, y);
  }

  /// A linha na altura y (null fora da lista).
  _Row? rowAt(double y) {
    if (rows.isEmpty || y < 0 || y >= height) return null;
    var lo = 0, hi = rows.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (rows[mid].top <= y) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return rows[lo];
  }

  /// A faixa cujo bloco contém y; acima da primeira vale a primeira, abaixo da última, a última.
  int trackAt(double y) {
    for (var i = 0; i < blockEnd.length; i++) {
      if (y < blockEnd[i]) return i;
    }
    return blockEnd.length - 1;
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
  const _TrackHeader({super.key, required this.c, required this.index, required this.height, required this.compact});

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
                    // no celular a linha é ícone, M, S e A, com 2 px entre eles: cabe nos 104 px
                    // que o cabeçalho de 132 deixa; efeitos ficam no menu e no ícone do barramento
                    Row(
                      children: [
                        if (compact) ...[_KindButton(c: c, index: index, color: color), const SizedBox(width: 2)],
                        ToggleChip(label: 'M', on: t.mute, color: Palette.danger, tooltip: 'Mudo', onTap: () => c.edit((_) => t.mute = !t.mute)),
                        SizedBox(width: compact ? 2 : 4),
                        ToggleChip(label: 'S', on: t.solo, color: const Color(0xFFE3B341), tooltip: 'Solo', onTap: () => c.edit((_) => t.solo = !t.solo)),
                        SizedBox(width: compact ? 2 : 4),
                        _AutomationButton(c: c, track: index),
                        if (!compact) ...[
                          const SizedBox(width: 4),
                          _EffectsChip(c: c, track: index),
                          const SizedBox(width: 4),
                          Expanded(
                            child: _MiniFader(gain: t.gain, onStart: c.checkpoint, onGain: (g) => c.mutate((_) => t.gain = g)),
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

/// Abre (ou fecha) o rack de efeitos da faixa ou do master (−1).
void _toggleEffects(DawController c, int track) {
  if (c.dock == Dock.effects && c.effectsTrack == track) {
    c.setDock(Dock.none);
    return;
  }
  if (track >= 0) c.selectTrack(track);
  c.showEffects(track);
}

/// O ícone do tipo da faixa. Nas de instrumento é um botão que abre o painel do instrumento; no
/// barramento, que não tem instrumento nem clipes, abre os efeitos (é para isso que ele existe).
class _KindButton extends StatelessWidget {
  final DawController c;
  final int index;
  final Color color;
  const _KindButton({required this.c, required this.index, required this.color});

  @override
  Widget build(BuildContext context) {
    final t = c.doc.tracks[index];
    final bus = t.kind == TrackKind.bus;
    if (!t.kind.isInstrument && !bus) {
      return Tooltip(
        message: 'Faixa de áudio',
        child: SizedBox(width: 24, height: 24, child: Icon(t.kind.icon, size: 16, color: color)),
      );
    }
    final open = bus ? c.dock == Dock.effects && c.effectsTrack == index : c.dock == Dock.instrument && c.selectedTrack == index;
    final tooltip = bus
        ? (open ? 'Fechar os efeitos' : 'Barramento: abrir os efeitos')
        : (open ? 'Fechar o instrumento (I)' : '${t.kind.label}: abrir o instrumento (I)');
    return SizedBox(
      width: 24,
      height: 24,
      child: IconButton(
        padding: EdgeInsets.zero,
        iconSize: 16,
        tooltip: tooltip,
        style: IconButton.styleFrom(
          backgroundColor: open ? color.withValues(alpha: 0.22) : null,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
        onPressed: () => bus ? _toggleEffects(c, index) : _toggleInstrument(c, index),
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
          case 'effects':
            _toggleEffects(c, index);
          case 'rename':
            onRename();
          case 'color':
            final t = c.doc.tracks[index];
            c.edit((_) => t.color = (t.color + 1) % Palette.tracks.length);
          case 'delete':
            final t = c.doc.tracks[index];
            final filled = t.clips.isNotEmpty || t.midi.isNotEmpty || t.effects.isNotEmpty || t.lanes.any((l) => l.points.isNotEmpty);
            if (filled &&
                !await confirmAction(
                  context,
                  title: 'Apagar "${t.name}"?',
                  message: 'A faixa e o que há nela (clipes, efeitos, automação) saem do projeto (dá para desfazer).',
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
        const PopupMenuItem(value: 'effects', child: Text('Efeitos')),
        const PopupMenuItem(value: 'rename', child: Text('Renomear')),
        const PopupMenuItem(value: 'color', child: Text('Trocar a cor')),
        const PopupMenuItem(value: 'delete', child: Text('Apagar a faixa')),
      ],
    ),
  );
}

/// Fader pequeno dos cabeçalhos (faixa e master): [onStart] marca o desfazer, [onGain] muda sem
/// histórico a cada passo.
class _MiniFader extends StatelessWidget {
  final double gain;
  final VoidCallback onStart;
  final ValueChanged<double> onGain;
  const _MiniFader({required this.gain, required this.onStart, required this.onGain});

  @override
  Widget build(BuildContext context) => Tooltip(
    message: '${formatDb(gain)} dB',
    child: SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 2,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
      ),
      child: SizedBox(
        height: 22,
        child: Slider(value: gainToFader(gain).clamp(0, 1), onChangeStart: (_) => onStart(), onChanged: (v) => onGain(faderToGain(v))),
      ),
    ),
  );
}

/// Botão M/S dos canais (e A/FX dos cabeçalhos). [lit] contorna na cor quando desligado: há algo
/// ali (automação oculta, efeitos) mesmo com o painel fechado.
class ToggleChip extends StatelessWidget {
  final String label, tooltip;
  final bool on, lit;
  final Color color;
  final VoidCallback onTap;
  const ToggleChip({super.key, required this.label, required this.on, required this.color, required this.tooltip, required this.onTap, this.lit = false});

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
          border: Border.all(color: on || lit ? color : Palette.hairlineStrong),
        ),
        child: Text(
          label,
          maxLines: 1,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: on ? Colors.black : (lit ? color : Colors.white70)),
        ),
      ),
    ),
  );
}

class _AddTrackRow extends StatelessWidget {
  final DawController c;
  final double height;
  const _AddTrackRow({super.key, required this.c, required this.height});

  PopupMenuItem<TrackKind> _item(TrackKind k) => PopupMenuItem(
    value: k,
    child: Row(children: [Icon(k.icon, size: 18), const SizedBox(width: 12), Text(k.label)]),
  );

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
        onSelected: (k) {
          switch (k) {
            case TrackKind.audio:
              c.addTrack();
            case TrackKind.bus:
              c.addBusTrack();
            case TrackKind.synth || TrackKind.drums || TrackKind.sampler:
              c.addInstrumentTrack(k);
          }
        },
        itemBuilder: (_) => [
          for (final k in TrackKind.values)
            if (k != TrackKind.bus) _item(k),
          const PopupMenuDivider(),
          _item(TrackKind.bus),
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

/// A linha do master, fixa no fim da lista: volume, medidor, automação e efeitos do master.
class _MasterHeader extends StatelessWidget {
  final DawController c;
  final double height;
  final bool compact;
  const _MasterHeader({super.key, required this.c, required this.height, required this.compact});

  @override
  Widget build(BuildContext context) => Container(
    height: height,
    decoration: const BoxDecoration(
      color: Palette.bar,
      border: Border(
        top: BorderSide(color: Palette.hairlineStrong),
        right: BorderSide(color: Palette.hairline),
        bottom: BorderSide(color: Palette.hairline),
      ),
    ),
    child: Row(
      children: [
        Container(width: 4, color: _masterColor),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.speaker, size: 16, color: _masterColor),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text('Master', maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelLarge),
                    ),
                  ],
                ),
                Row(
                  children: [
                    _AutomationButton(c: c, track: -1),
                    SizedBox(width: compact ? 2 : 4),
                    _EffectsChip(c: c, track: -1),
                    if (!compact) ...[
                      const SizedBox(width: 4),
                      Expanded(
                        child: _MiniFader(gain: c.doc.masterGain, onStart: c.checkpoint, onGain: (g) => c.mutate((d) => d.masterGain = g)),
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
          child: Meter(peaks: c.peaks, index: -1, width: 6),
        ),
        const SizedBox(width: 6),
      ],
    ),
  );
}

/// FX: abre o rack de efeitos da faixa ou do master (−1); contornado quando a cadeia tem efeitos.
class _EffectsChip extends StatelessWidget {
  final DawController c;
  final int track;
  const _EffectsChip({required this.c, required this.track});

  @override
  Widget build(BuildContext context) {
    final n = effectChainOf(c, track).length;
    final open = c.dock == Dock.effects && c.effectsTrack == track;
    return ToggleChip(
      label: 'FX',
      on: open,
      lit: n > 0,
      color: _effectsColor,
      tooltip: open ? 'Fechar os efeitos' : (n == 0 ? 'Efeitos' : 'Efeitos ($n)'),
      onTap: () => _toggleEffects(c, track),
    );
  }
}

/// A: menu dos alvos automatizáveis da faixa ou do master (−1). Aceso com alguma automação
/// aberta; contornado quando só há automação oculta.
class _AutomationButton extends StatelessWidget {
  final DawController c;
  final int track;
  const _AutomationButton({required this.c, required this.track});

  @override
  Widget build(BuildContext context) {
    final lanes = automationLanesOf(c, track);
    return ToggleChip(
      label: 'A',
      on: lanes.any((l) => l.open),
      lit: lanes.isNotEmpty,
      color: _automationColor,
      tooltip: lanes.isEmpty ? 'Automação' : 'Automação (${lanes.length})',
      onTap: () => _automationMenu(context, c, track),
    );
  }
}

const _showAllLanes = 'show-all', _hideAllLanes = 'hide-all';

/// Grupo de um alvo no menu (os parâmetros do instrumento e os de cada efeito vão num segundo
/// menu, senão seriam centenas de linhas); null para os do primeiro nível.
String? _autoGroup(AutoTarget t) => switch (t.kind) {
  AutoKind.instrument => 'instrument',
  AutoKind.effect => 'fx:${t.ref}',
  AutoKind.volume || AutoKind.pan || AutoKind.send => null,
};

/// Nome e ícone do grupo: o instrumento da faixa, ou o efeito com a posição dele na cadeia (dois
/// reverbs ficam distinguíveis).
(String, IconData) _autoGroupLabel(DawController c, int track, AutoTarget t) {
  if (t.kind == AutoKind.instrument) {
    final k = track >= 0 ? c.doc.tracks[track].kind : TrackKind.synth;
    return (k.label, k.icon);
  }
  final fx = effectChainOf(c, track);
  final i = fx.indexWhere((s) => s.id == t.ref);
  return i < 0 ? ('Efeito', Icons.tune) : ('${i + 1}. ${fx[i].kind.label}', fx[i].kind.icon);
}

PopupMenuItem<Object> _autoTargetItem(AutoTarget t, String name, AutoLane? lane) => PopupMenuItem<Object>(
  value: t,
  height: 36,
  child: Row(
    children: [
      SizedBox(
        width: 20,
        child: lane == null
            ? null
            : Icon(lane.open ? Icons.check : Icons.visibility_off_outlined, size: 16, color: lane.open ? _automationColor : Colors.white38),
      ),
      const SizedBox(width: 10),
      Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis)),
      if (lane != null && lane.points.isNotEmpty) ...[
        const SizedBox(width: 12),
        Text('${lane.points.length} ${lane.points.length == 1 ? 'ponto' : 'pontos'}', style: const TextStyle(fontSize: 11, color: Colors.white38)),
      ],
    ],
  ),
);

/// Abre o menu de automação debaixo do botão. Escolher um alvo abre a sub-raia dele (criando se
/// preciso); escolher um que já está aberto oculta. Mostrar/ocultar não entra no desfazer.
Future<void> _automationMenu(BuildContext context, DawController c, int track) async {
  final box = context.findRenderObject();
  final overlay = Overlay.of(context).context.findRenderObject();
  if (box is! RenderBox || overlay is! RenderBox) return;
  final at = box.localToGlobal(Offset.zero, ancestor: overlay) & box.size;
  final position = RelativeRect.fromRect(Rect.fromLTWH(at.left, at.bottom + 2, at.width, 0), Offset.zero & overlay.size);
  final targets = c.automatable(track);
  AutoLane? laneOf(AutoTarget t) => automationLanesOf(c, track).where((l) => l.target == t).firstOrNull;
  final top = <(AutoTarget, String)>[];
  final groups = <String, List<(AutoTarget, String)>>{};
  for (final e in targets) {
    final g = _autoGroup(e.$1);
    if (g == null) {
      top.add(e);
    } else {
      (groups[g] ??= []).add(e);
    }
  }
  final lanes = automationLanesOf(c, track);
  final hidden = lanes.where((l) => !l.open).length;
  final shown = lanes.length - hidden;
  final small = Theme.of(context).textTheme.labelSmall!.copyWith(color: Colors.white38, letterSpacing: 0.6);
  var pick = await showMenu<Object>(
    context: context,
    position: position,
    items: [
      if (targets.isEmpty) const PopupMenuItem<Object>(enabled: false, child: Text('Nada para automatizar aqui')),
      for (final (t, name) in top) _autoTargetItem(t, name, laneOf(t)),
      if (top.isNotEmpty && groups.isNotEmpty) const PopupMenuDivider(),
      for (final MapEntry(key: g, value: items) in groups.entries)
        PopupMenuItem<Object>(
          value: g,
          height: 40,
          child: Builder(
            builder: (context) {
              final (label, icon) = _autoGroupLabel(c, track, items.first.$1);
              final open = items.where((e) => laneOf(e.$1) != null).length;
              return Row(
                children: [
                  SizedBox(width: 20, child: Icon(icon, size: 16, color: Colors.white60)),
                  const SizedBox(width: 10),
                  Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
                  if (open > 0) Text('$open', style: small),
                  const Icon(Icons.chevron_right, size: 18),
                ],
              );
            },
          ),
        ),
      if (lanes.isNotEmpty) const PopupMenuDivider(),
      if (hidden > 0) PopupMenuItem<Object>(value: _showAllLanes, height: 40, child: Text('Mostrar as ocultas ($hidden)')),
      if (shown > 0) const PopupMenuItem<Object>(value: _hideAllLanes, height: 40, child: Text('Ocultar todas')),
    ],
  );
  if (pick is String && groups.containsKey(pick)) {
    if (!context.mounted) return;
    // segundo nível: os parâmetros do grupo, com um título a cada seção da tabela
    final entries = <PopupMenuEntry<Object>>[];
    String? section;
    for (final (t, name) in groups[pick]!) {
      final spec = autoParamSpec(c, track, t);
      if (spec != null && spec.group != section) {
        section = spec.group;
        entries.add(PopupMenuItem<Object>(enabled: false, height: 26, child: Text(spec.group.toUpperCase(), style: small)));
      }
      entries.add(_autoTargetItem(t, spec?.name ?? name, laneOf(t)));
    }
    pick = await showMenu<Object>(context: context, position: position, items: entries);
  }
  // a faixa pode ter saído enquanto o menu estava aberto
  if (pick == null || track >= c.doc.tracks.length) return;
  final now = automationLanesOf(c, track);
  switch (pick) {
    case _showAllLanes || _hideAllLanes:
      final open = pick == _showAllLanes;
      c.edit((_) {
        for (final l in now) {
          l.open = open;
        }
      }, undoable: false);
    case AutoTarget t:
      final lane = laneOf(t);
      if (lane != null && lane.open) {
        c.edit((_) => lane.open = false, undoable: false);
      } else {
        c.addLane(track, t);
      }
  }
}

// ---------------------------------------------------------------------- raias

class _Lanes extends StatefulWidget {
  final DawController c;
  final _Layout layout;
  final double laneHeight, width;

  /// Aparelho de toque (muda só o texto da dica das faixas vazias).
  final bool touch;
  const _Lanes({required this.c, required this.layout, required this.laneHeight, required this.width, required this.touch});

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
    // as sub-raias de automação tratam os próprios toques; aqui chegam faixas, master e o resto
    final row = widget.layout.rowAt(d.localPosition.dy);
    final lane = row != null && row.kind == _RowKind.track ? row.track : -1;
    final at = _beatAt(d.localPosition.dx);
    if (lane >= 0) c.selectTrack(lane);
    c.seek(c.snapBeat(at));
    if (_taps(d.globalPosition) && lane >= 0 && c.doc.tracks[lane].kind.isInstrument) _createClip(lane, at);
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
    final layout = widget.layout;
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
                    bands: [for (final r in layout.rows) (r.top, r.height, _bandOf(r, tracks))],
                    selected: c.selectedTrack < tracks.length ? layout.trackTop[c.selectedTrack] : null,
                    laneHeight: laneHeight,
                  ),
                ),
              ),
              for (var ti = 0; ti < tracks.length; ti++)
                if ((tracks[ti].kind.isInstrument && tracks[ti].midi.isEmpty) || tracks[ti].kind == TrackKind.bus)
                  Positioned(
                    left: 12,
                    right: 12,
                    top: layout.trackTop[ti],
                    height: laneHeight,
                    child: IgnorePointer(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          tracks[ti].kind == TrackKind.bus
                              ? 'Barramento: recebe o som das faixas que enviam ou saem para ele'
                              : (widget.touch ? 'Toque duas vezes para criar um clipe de notas' : 'Clique duas vezes para criar um clipe de notas'),
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
                      top: layout.trackTop[ti] + 2,
                      width: math.max(4, clip.beats(bpm) * c.pxPerBeat),
                      height: laneHeight - 4,
                      child: _ClipView(c: c, clip: clip, track: ti, laneHeight: laneHeight, layout: layout),
                    ),
                for (final clip in tracks[ti].midi)
                  if (shown(clip.id, clip.start, clip.end))
                    Positioned(
                      key: ValueKey('midi:${clip.id}'),
                      left: (clip.start - c.scrollBeat) * c.pxPerBeat,
                      top: layout.trackTop[ti] + 2,
                      width: math.max(4, clip.length * c.pxPerBeat),
                      height: laneHeight - 4,
                      child: _MidiClipView(c: c, clip: clip, track: ti, laneHeight: laneHeight, layout: layout),
                    ),
              ],
              for (final r in layout.rows)
                if (r.lane != null)
                  Positioned(
                    key: ValueKey('auto:${r.lane!.id}'),
                    left: 0,
                    right: 0,
                    top: r.top,
                    height: r.height,
                    child: AutomationLaneView(c: c, track: r.track, lane: r.lane!, color: _trackColor(c, r.track), touch: widget.touch),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fundo de cada linha no desenho da grade.
enum _Band { track, bus, lane, add, master }

_Band _bandOf(_Row r, List<DawTrack> tracks) => switch (r.kind) {
  _RowKind.track => tracks[r.track].kind == TrackKind.bus ? _Band.bus : _Band.track,
  _RowKind.lane => _Band.lane,
  _RowKind.add => _Band.add,
  _RowKind.master => _Band.master,
};

class _GridPainter extends CustomPainter {
  final double scroll, ppb, laneHeight;
  final int beatsPerBar;

  /// Topo, altura e tipo de cada linha.
  final List<(double, double, _Band)> bands;

  /// Topo da faixa selecionada.
  final double? selected;
  _GridPainter({required this.scroll, required this.ppb, required this.beatsPerBar, required this.bands, required this.selected, required this.laneHeight});

  @override
  void paint(Canvas canvas, Size size) {
    for (final (top, h, band) in bands) {
      final fill = switch (band) {
        _Band.lane => 0.022,
        _Band.bus => 0.012,
        _Band.master => 0.016,
        _Band.track || _Band.add => 0.0,
      };
      if (fill > 0) canvas.drawRect(Rect.fromLTWH(0, top, size.width, h), Paint()..color = Colors.white.withValues(alpha: fill));
    }
    final sel = selected;
    if (sel != null) {
      canvas.drawRect(Rect.fromLTWH(0, sel, size.width, laneHeight), Paint()..color = Colors.white.withValues(alpha: 0.025));
    }
    final line = Paint()..color = Palette.hairline;
    for (final (top, h, band) in bands) {
      if (band == _Band.master) canvas.drawRect(Rect.fromLTWH(0, top, size.width, 1), Paint()..color = Palette.hairlineStrong);
      if (band != _Band.add) canvas.drawRect(Rect.fromLTWH(0, top + h - 1, size.width, 1), line);
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
      o.scroll != scroll || o.ppb != ppb || o.beatsPerBar != beatsPerBar || o.selected != selected || o.laneHeight != laneHeight || !listEquals(o.bands, bands);
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

/// Faixa sob um clipe arrastado [dy] pixels na vertical desde a faixa [from]: a do bloco onde o
/// meio dele caiu (as automações abertas de uma faixa contam como dela).
int _trackUnder(_Layout layout, int from, double laneHeight, double dy) {
  if (from < 0 || from >= layout.trackTop.length) return from;
  return layout.trackAt(layout.trackTop[from] + laneHeight / 2 + dy);
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
  final _Layout layout;
  const _ClipView({required this.c, required this.clip, required this.track, required this.laneHeight, required this.layout});
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
        final lane = _trackUnder(widget.layout, _origTrack, widget.laneHeight, total.dy);
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
  final _Layout layout;
  const _MidiClipView({required this.c, required this.clip, required this.track, required this.laneHeight, required this.layout});
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
        final lane = _trackUnder(widget.layout, _origTrack, widget.laneHeight, total.dy);
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
