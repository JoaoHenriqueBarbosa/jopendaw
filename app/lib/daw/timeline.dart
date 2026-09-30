/// O arranjo: régua, cabeçalhos das faixas e as raias com os clipes (de áudio nas faixas de áudio,
/// de notas nas de instrumento), as sub-raias de automação abertas embaixo de cada faixa, a linha
/// do master no fim e o cursor de reprodução.
///
/// A rolagem horizontal e o zoom são do controlador (a janela começa em `scrollBeat` e cada batida
/// ocupa `pxPerBeat`); a vertical é um scroll comum que leva cabeçalhos e raias juntos, com as
/// alturas de uma conta só ([_Layout]).
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/dialogs.dart';
import '../widgets/feedback.dart';
import '../widgets/format.dart';
import '../widgets/theme.dart';
import 'automation_lane.dart';
import 'clip_gain_dialog.dart';
import 'controller.dart';
import 'fade_length_dialog.dart';
import 'instruments.dart';
import 'marker.dart';
import 'meter.dart';
import 'midi_learn_ui.dart';
import 'midi_cc.dart' show trimControlsLeft;
import 'midi_convert_dialog.dart';
import 'minimap.dart';
import 'tempo_lane.dart';
import 'tempo_map.dart';
import 'warp_dialog.dart';
import 'model.dart';
import 'structure_menu.dart';
import 'track_groups.dart';
import 'track_groups_ui.dart';

const _rulerHeight = 30.0;

/// Altura da linha de "+ Faixa", entre as faixas e o master.
const _addRowHeight = 44.0;

/// Cor do master (e das automações dele) e dos botões A e FX dos cabeçalhos.
const _masterColor = Color(0xFFC9D1D9);
const _automationColor = Palette.accent;
const _effectsColor = Color(0xFF6BA8F0);

/// Gravar: vermelho de verdade, para não confundir com o salmão do mudo ([Palette.danger]).
const _recordColor = Color(0xFFF0464B);

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
double _gridBeats(DawController c, [double at = 0]) => c.snap == Snap.bar ? c.doc.meter.barBeatsAt(math.max(0.0, at)) : c.snap.beats;

class Timeline extends StatelessWidget {
  final DawController c;
  final bool compact;
  const Timeline({super.key, required this.c, required this.compact});

  double get headerWidth => compact ? 132 : 232;
  double get laneHeight => (compact ? 64 : 76) * c.laneScale.factor;

  Widget _header(_Row r) => switch (r.kind) {
    _RowKind.track when c.doc.tracks[r.track].isGroup => GroupHeader(
      key: ValueKey('t:${c.doc.tracks[r.track].id}'),
      c: c,
      index: r.track,
      height: r.height,
      compact: compact,
    ),
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
                          child: Row(
                            children: [
                              Expanded(
                                child: Tooltip(
                                  message: 'Régua em ${c.rulerTime ? 'compassos' : 'minutos e segundos'}: clique para alternar',
                                  child: InkWell(
                                    onTap: c.toggleRulerTime,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 8),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              plural(c.doc.tracks.length, 'faixa'),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: Theme.of(context).textTheme.labelSmall,
                                            ),
                                          ),
                                          Text(
                                            c.rulerTime ? 'mm:ss' : 'comp.',
                                            style: Theme.of(context).textTheme.labelSmall!.copyWith(color: Palette.accent, fontWeight: FontWeight.w700),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: c.tempoLaneVisible ? 'Esconder a faixa de andamento' : 'Mostrar a faixa de andamento',
                                onPressed: c.toggleTempoLane,
                                isSelected: c.tempoLaneVisible,
                                visualDensity: VisualDensity.compact,
                                iconSize: 16,
                                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                padding: EdgeInsets.zero,
                                style: IconButton.styleFrom(foregroundColor: Colors.white54),
                                selectedIcon: const Icon(Icons.speed, color: Palette.accent),
                                icon: const Icon(Icons.speed),
                              ),
                            ],
                          ),
                        ),
                        Expanded(child: _Ruler(c: c)),
                      ],
                    ),
                  ),
                  if (c.tempoLaneVisible)
                    SizedBox(
                      height: tempoLaneHeight,
                      child: Row(
                        children: [
                          Container(
                            width: headerWidth,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            alignment: Alignment.centerLeft,
                            decoration: const BoxDecoration(
                              color: Palette.bar,
                              border: Border(
                                right: BorderSide(color: Palette.hairline),
                                bottom: BorderSide(color: Palette.hairline),
                              ),
                            ),
                            child: Text('Andamento', maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelSmall),
                          ),
                          Expanded(child: TempoLane(c: c)),
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
                  SizedBox(
                    height: minimapHeight,
                    child: Row(
                      children: [
                        Container(
                          width: headerWidth,
                          height: minimapHeight,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          alignment: Alignment.centerLeft,
                          decoration: const BoxDecoration(
                            color: Palette.bar,
                            border: Border(
                              top: BorderSide(color: Palette.hairline),
                              right: BorderSide(color: Palette.hairline),
                            ),
                          ),
                          child: Text('Visão geral', maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelSmall),
                        ),
                        Expanded(child: Minimap(c: c)),
                      ],
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
      // filha de pasta recolhida: sem linha e sem altura (o bloco vazio nunca é a faixa sob um y)
      if (c.doc.hiddenByGroup(i)) {
        ends.add(y);
        continue;
      }
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
    // abaixo de tudo: a última faixa visível (as filhas de pasta recolhida têm bloco vazio)
    var i = blockEnd.length - 1;
    while (i > 0 && blockEnd[i] == blockEnd[i - 1]) {
      i--;
    }
    return i;
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

/// Clicar posiciona o cursor; arrastar desenha a região do loop. Gravando (e na contagem), os dois
/// ficam travados: mexer no meio desalinharia o que está sendo gravado da posição dele no arranjo.
class _Ruler extends StatefulWidget {
  final DawController c;
  const _Ruler({required this.c});
  @override
  State<_Ruler> createState() => _RulerState();
}

class _RulerState extends State<_Ruler> {
  double? _dragFrom;

  /// Batida sob o mouse (null fora da régua): a etiqueta de posição.
  final _hover = ValueNotifier<double?>(null);

  @override
  void dispose() {
    _hover.dispose();
    super.dispose();
  }

  double _beatAt(double x) => widget.c.scrollBeat + x / widget.c.pxPerBeat;

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final locked = c.recording;
    return MouseRegion(
      onHover: (e) => _hover.value = math.max(0.0, _beatAt(e.localPosition.dx)),
      onExit: (_) => _hover.value = null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: locked ? null : (d) => c.seek(c.snapBeat(_beatAt(d.localPosition.dx))),
        onHorizontalDragStart: locked
            ? null
            : (d) {
                c.checkpoint();
                _dragFrom = c.snapBeat(_beatAt(d.localPosition.dx));
              },
        onHorizontalDragUpdate: locked
            ? null
            : (d) {
                final from = _dragFrom;
                if (from != null) c.setLoop(from, c.snapBeat(_beatAt(d.localPosition.dx)));
              },
        onHorizontalDragEnd: locked ? null : (_) => _dragFrom = null,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(
              decoration: const BoxDecoration(
                color: Palette.bar,
                border: Border(bottom: BorderSide(color: Palette.hairline)),
              ),
              child: CustomPaint(
                painter: _RulerPainter(
                  scroll: c.scrollBeat,
                  ppb: c.pxPerBeat,
                  meter: c.doc.meter,
                  tempo: c.doc.tempo,
                  loopOn: c.doc.loopOn,
                  loopStart: c.doc.loopStart,
                  loopEnd: c.doc.loopEnd,
                  timeMode: c.rulerTime,
                  style: Theme.of(context).textTheme.labelSmall!,
                ),
                size: Size.infinite,
              ),
            ),
            MarkerFlags(c: c),
            IgnorePointer(
              child: _HoverLabel(c: c, hover: _hover),
            ),
            if (c.recording && c.countingIn) IgnorePointer(child: _CountInBadge(c: c)),
          ],
        ),
      ),
    );
  }
}

/// Posição sob o mouse na régua: compasso.tempo e mm:ss, com um fio no ponto.
class _HoverLabel extends StatelessWidget {
  final DawController c;
  final ValueNotifier<double?> hover;
  const _HoverLabel({required this.c, required this.hover});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => ValueListenableBuilder<double?>(
      valueListenable: hover,
      builder: (context, b, _) {
        if (b == null) return const SizedBox.shrink();
        final x = (b - c.scrollBeat) * c.pxPerBeat;
        final text = '${formatPosition(b, c.doc.beatsPerBar, meter: c.doc.meter)} · ${formatClock(c.doc.secondsAt(b), tenths: true)}';
        final onRight = x < box.maxWidth - 150;
        return Stack(
          children: [
            Positioned(
              left: x,
              top: 0,
              bottom: 0,
              width: 1,
              child: const ColoredBox(color: Colors.white38),
            ),
            Positioned(
              left: onRight ? x + 6 : null,
              right: onRight ? null : math.max(0.0, box.maxWidth - x + 6),
              bottom: 2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: Palette.overlay,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Palette.hairlineStrong),
                ),
                child: Text(text, style: Theme.of(context).textTheme.labelSmall!.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
              ),
            ),
          ],
        );
      },
    ),
  );
}

/// "Contando…" na régua durante o compasso de contagem, logo à direita do cursor (onde a gravação
/// vai começar), sem sair da janela.
class _CountInBadge extends StatelessWidget {
  final DawController c;
  const _CountInBadge({required this.c});

  static const _label = 'Contando…';
  static const _style = TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white);

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      // o selo tem a largura do texto; medido aqui (só quando o layout muda) para não sair da janela
      final tp = TextPainter(
        text: const TextSpan(text: _label, style: _style),
        textDirection: TextDirection.ltr,
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout();
      final width = tp.width + 8 + 6 + 2 * 8;
      tp.dispose();
      return ValueListenableBuilder<double>(
        valueListenable: c.beat,
        builder: (context, beat, _) {
          final x = (beat - c.scrollBeat) * c.pxPerBeat;
          final left = (x + 10).clamp(4.0, math.max(4.0, box.maxWidth - width - 4)).toDouble();
          return Stack(
            children: [
              Positioned(
                left: left,
                top: 5,
                height: 20,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: _recordColor.withValues(alpha: 0.92), borderRadius: BorderRadius.circular(10)),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.circle, size: 8, color: Colors.white),
                      SizedBox(width: 6),
                      Text(_label, maxLines: 1, softWrap: false, style: _style),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      );
    },
  );
}

/// De quantas em quantas batidas vale desenhar um número, para não amontoar.
int _barStep(double ppb, num beatsPerBar) {
  final barPx = ppb * beatsPerBar;
  var step = 1;
  while (barPx * step < 48) {
    step *= 2;
  }
  return step;
}

class _RulerPainter extends CustomPainter {
  final double scroll, ppb, loopStart, loopEnd;
  final MeterMap meter;
  final TempoMap tempo;
  final bool loopOn, timeMode;
  final TextStyle style;

  _RulerPainter({
    required this.scroll,
    required this.ppb,
    required this.meter,
    required this.tempo,
    required this.loopOn,
    required this.loopStart,
    required this.loopEnd,
    required this.timeMode,
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
    final tick = Paint()..color = Colors.white24;
    final visibleEnd = scroll + size.width / ppb;
    if (timeMode) {
      // números em segundos: o menor passo "redondo" que deixa ao menos 64 px entre rótulos (o
      // andamento vigente à esquerda decide; com mapa, os rótulos ficam onde o tempo cai de fato)
      final pxPerSec = ppb * tempo.bpmAt(scroll) / 60;
      const steps = [0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 1800, 3600];
      final every = steps.firstWhere((s) => s * pxPerSec >= 64, orElse: () => steps.last);
      final from = (tempo.secondsAt(scroll) / every).floor(), to = (tempo.secondsAt(visibleEnd) / every).ceil();
      for (var k = from; k <= to; k++) {
        final sec = k * every;
        final x = (tempo.beatAt(sec.toDouble()) - scroll) * ppb;
        canvas.drawRect(Rect.fromLTWH(x, 8, 1, size.height - 8), tick);
        final tp = TextPainter(
          text: TextSpan(
            text: formatClock(sec.toDouble(), tenths: every < 1),
            style: style.copyWith(color: Colors.white70),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x + 4, 4));
      }
      // os compassos ficam como traços curtos embaixo, para não perder a métrica
      if (ppb * meter.barBeatsAt(scroll) >= 8) {
        for (var bar = meter.barOf(scroll).$1; meter.barStart(bar) <= visibleEnd; bar++) {
          canvas.drawRect(Rect.fromLTWH((meter.barStart(bar) - scroll) * ppb, size.height - 6, 1, 6), tick);
        }
      }
      return;
    }
    final step = _barStep(ppb, meter.barBeatsAt(scroll));
    for (var bar = meter.barOf(scroll).$1; meter.barStart(bar) <= visibleEnd; bar++) {
      final at = meter.barStart(bar);
      final x = (at - scroll) * ppb;
      if ((bar - 1) % step == 0) {
        canvas.drawRect(Rect.fromLTWH(x, 8, 1, size.height - 8), tick);
        final tp = TextPainter(
          text: TextSpan(
            text: '$bar',
            style: style.copyWith(color: Colors.white70),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x + 4, 4));
      }
      final c = meter.changeAt(bar);
      // a fórmula de compasso aparece onde ela muda
      if (c.bar == bar && !meter.isSingle) {
        final tp = TextPainter(
          text: TextSpan(
            text: '${c.numerator}/${c.denominator}',
            style: style.copyWith(color: Palette.accent, fontSize: 10, fontWeight: FontWeight.w700),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x + 4, 15));
      }
      if (ppb * c.unit >= 12) {
        for (var b = 1; b < c.numerator; b++) {
          final bx = x + b * c.unit * ppb;
          canvas.drawRect(Rect.fromLTWH(bx, size.height - 8, 1, 8), tick);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_RulerPainter o) =>
      o.scroll != scroll ||
      o.ppb != ppb ||
      !identical(o.meter, meter) ||
      !identical(o.tempo, tempo) ||
      o.loopOn != loopOn ||
      o.loopStart != loopStart ||
      o.loopEnd != loopEnd ||
      o.timeMode != timeMode;
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

  /// O deslizador de volume do cabeçalho grava automação como o fader do mixer (Escrever/Toque/Trava).
  void _miniStart(int index) {
    c.autoRec.touch(index, const AutoTarget(AutoKind.volume));
    c.checkpoint();
  }

  void _miniGain(int index, double g) {
    c.autoRec.value(index, const AutoTarget(AutoKind.volume), g);
    c.mutate((d) => d.tracks[index].gain = g);
  }

  /// Arraste para reordenar (toque longo + arrastar na vertical: o arraste simples rola a lista).
  double _dragFrom = 0;
  int? _dragTo;

  /// O deslizador de volume do cabeçalho tem prioridade sobre o reordenar: um toque longo que começa
  /// nele (ou a até [_sliderGuard] px acima e abaixo da barra, e uma margem curta dos lados: ao lado dela
  /// ficam o botão FX e o medidor, onde o toque longo reordena) não liga o arraste da faixa.
  static const _sliderGuard = 15.0, _sliderSideGuard = 4.0;
  final _faderKey = GlobalKey();
  bool _skipReorder = false;

  Rect _verticalGuard(RenderBox box) {
    final r = box.localToGlobal(Offset.zero) & box.size;
    return Rect.fromLTRB(r.left, r.top - _sliderGuard, r.right, r.bottom + _sliderGuard);
  }

  bool _onSlider(Offset global) {
    final box = _faderKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return false;
    return (box.localToGlobal(Offset.zero) & box.size).inflate(_sliderSideGuard).expandToInclude(_verticalGuard(box)).contains(global);
  }

  DawController get c => widget.c;
  int get index => widget.index;

  /// A faixa sob a altura [y] (da lista de faixas e automações), contando as automações abertas
  /// como parte da faixa de cima.
  int _trackAt(double y) {
    final layout = _Layout.of(c, height);
    final n = c.doc.tracks.length;
    for (var j = 0; j < n; j++) {
      if (y < layout.blockEnd[j]) return j;
    }
    return n - 1;
  }

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
    final dragging = _dragTo != null;
    // no celular a linha de baixo é ícone, M, S, gravar e A em botões de 20 px com 2 px entre eles
    // (108 px): cabe nos 110 que o cabeçalho de 132 deixa com as margens mais curtas
    final chip = compact ? 20.0 : 24.0;
    final gap = compact ? 2.0 : 4.0;
    return GestureDetector(
      onTapUp: (d) {
        c.selectTrack(index);
        if (_taps(d.globalPosition)) _rename(context, t);
      },
      onLongPressStart: (d) {
        // a guarda vale para ESTE toque longo (a posição onde ele começou), não a do último PointerDown
        _skipReorder = _onSlider(d.globalPosition);
        if (_skipReorder) return;
        HapticFeedback.selectionClick();
        _dragFrom = _Layout.of(c, height).trackTop[index] + d.localPosition.dy;
        setState(() => _dragTo = index);
      },
      onLongPressMoveUpdate: (d) {
        if (_skipReorder) return;
        final to = _trackAt(_dragFrom + d.offsetFromOrigin.dy);
        if (to != _dragTo) setState(() => _dragTo = to);
      },
      onLongPressEnd: (_) {
        final to = _dragTo;
        setState(() => _dragTo = null);
        if (to != null && to != index) moveTrackAsking(context, c, index, to);
      },
      onLongPressCancel: () => setState(() => _dragTo = null),
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (e) => _skipReorder = _onSlider(e.position),
        child: Container(
          height: height,
          foregroundDecoration: dragging ? BoxDecoration(border: Border.all(color: color, width: 2)) : null,
          decoration: BoxDecoration(
            color: dragging ? color.withValues(alpha: 0.18) : (selected ? Palette.overlay : Palette.bar),
            border: const Border(
              right: BorderSide(color: Palette.hairline),
              bottom: BorderSide(color: Palette.hairline),
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Row(
                children: [
                  // filha de pasta: uma tira da cor da pasta na frente (no celular, dentro dos 4 px da barra
                  // da faixa: a linha de baixo do cabeçalho não tem folga)
                  if (!compact && c.doc.folderOf(index) >= 0) GroupIndent(color: trackColorAt(c.doc.tracks[c.doc.folderOf(index)].color)),
                  Container(
                    width: 4,
                    decoration: BoxDecoration(
                      color: color,
                      border: compact && c.doc.folderOf(index) >= 0
                          ? Border(left: BorderSide(color: trackColorAt(c.doc.tracks[c.doc.folderOf(index)].color), width: 2))
                          : null,
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(compact ? 6 : 8, 6, compact ? 2 : 4, 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              // no celular o ícone desce para a linha do M/S: o nome precisa do espaço
                              if (!compact) ...[_KindButton(c: c, index: index, color: color), const SizedBox(width: 4)],
                              Expanded(
                                child: Text(
                                  dragging ? 'Mover para a posição ${_dragTo! + 1}' : t.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.labelLarge,
                                ),
                              ),
                              _TrackMenu(c: c, index: index, onRename: () => _rename(context, t)),
                            ],
                          ),
                          // efeitos, no celular, ficam no menu e no ícone do barramento
                          Row(
                            children: [
                              if (compact) ...[_KindButton(c: c, index: index, color: color, width: chip), SizedBox(width: gap)],
                              ToggleChip(
                                label: 'M',
                                width: chip,
                                on: t.mute,
                                color: Palette.danger,
                                tooltip: 'Mudo',
                                onTap: () => c.edit((_) => t.mute = !t.mute),
                              ),
                              SizedBox(width: gap),
                              ToggleChip(
                                label: 'S',
                                width: chip,
                                on: t.solo,
                                color: const Color(0xFFE3B341),
                                tooltip: 'Solo',
                                onTap: () => c.edit((_) => t.solo = !t.solo),
                              ),
                              SizedBox(width: gap),
                              // barramento não grava; o vão deixa A e FX na mesma coluna das outras faixas
                              if (t.kind == TrackKind.bus) SizedBox(width: chip) else _ArmButton(c: c, track: index, width: chip),
                              SizedBox(width: gap),
                              _AutomationButton(c: c, track: index, width: chip),
                              if (!compact) ...[
                                const SizedBox(width: 4),
                                _EffectsChip(c: c, track: index),
                                const SizedBox(width: 4),
                                Expanded(
                                  // um só widget nos dois casos: a raia ganha pontos no meio do arraste e trocar a
                                  // árvore aqui derrubaria o gesto
                                  child: ListenableBuilder(
                                    listenable: Listenable.merge([c.beat, c.autoRec]),
                                    builder: (_, _) {
                                      const volume = AutoTarget(AutoKind.volume);
                                      final hand = c.autoRec.isRecording(index, volume);
                                      final follows = c.automated(index, AutoKind.volume) && !hand;
                                      return MidiLearnControl(
                                        c: c,
                                        track: index,
                                        target: volume,
                                        radius: 6,
                                        child: _MiniFader(
                                          key: _faderKey,
                                          gain: follows ? c.liveValue(index, AutoKind.volume) : t.gain,
                                          automated: follows && c.playing.value,
                                          onStart: () => _miniStart(index),
                                          onGain: (g) => _miniGain(index, g),
                                          onEnd: () => c.autoRec.release(index, volume),
                                        ),
                                      );
                                    },
                                  ),
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
                  SizedBox(width: compact ? 4 : 6),
                ],
              ),
              // o nível da entrada numa barra fina no rodapé, fora da conta das linhas: é por ele que
              // se acerta o ganho do microfone antes de gravar
              if (t.armed && t.kind == TrackKind.audio)
                Positioned(
                  left: compact ? 10 : 12,
                  right: compact ? 14 : 16,
                  bottom: 2,
                  height: 3,
                  child: _InputMeter(level: c.inputLevel),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ● de armar a faixa para gravar: contornado em vermelho quando armada, cheio enquanto grava de
/// fato (depois da contagem). Durante a gravação não muda: o que está sendo gravado foi decidido ao
/// começar, e trocar no meio deixaria a tela mostrando faixas que não recebem nada.
class _ArmButton extends StatelessWidget {
  final DawController c;
  final int track;
  final double width;
  const _ArmButton({required this.c, required this.track, this.width = 24});

  @override
  Widget build(BuildContext context) {
    final t = c.doc.tracks[track];
    final armed = t.armed;
    final live = armed && c.recording && !c.countingIn;
    final tooltip = c.recording
        ? (armed ? 'Gravando nesta faixa' : 'Pare a gravação para armar esta faixa')
        : armed
        ? 'Desarmar'
        : t.kind.isInstrument
        ? 'Armar para gravar as notas (teclado ou MIDI)'
        : 'Armar para gravar a entrada de áudio';
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: c.recording ? null : () => c.setArmed(track, !armed),
        borderRadius: BorderRadius.circular(4),
        child: Container(
          width: width,
          height: 20,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: live ? _recordColor : (armed ? _recordColor.withValues(alpha: 0.16) : Colors.transparent),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: armed ? _recordColor : Palette.hairlineStrong),
          ),
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(shape: BoxShape.circle, color: live ? Colors.white : (armed ? _recordColor : Colors.white54)),
          ),
        ),
      ),
    );
  }
}

/// Pico linear → 0..1 numa escala de −48 a 0 dB (a mesma dos medidores de saída).
double _meterLevel(double p) {
  if (p <= 0) return 0;
  final db = 20 * math.log(p) / math.ln10;
  return ((db + 48) / 48).clamp(0.0, 1.0);
}

/// Medidor horizontal da entrada de áudio. Sobe na hora e desce devagar; a queda anda por um
/// relógio próprio porque o nível só avisa quando muda (silêncio repetido não chega) e o medidor
/// ficaria parado no meio. Saturou: a ponta fica vermelha por um segundo e meio.
class _InputMeter extends StatefulWidget {
  final ValueNotifier<double> level;
  const _InputMeter({required this.level});

  @override
  State<_InputMeter> createState() => _InputMeterState();
}

class _InputMeterState extends State<_InputMeter> {
  double _v = 0;
  bool _clip = false;
  Timer? _fall, _clipHold;

  @override
  void initState() {
    super.initState();
    widget.level.addListener(_onLevel);
    _v = widget.level.value.clamp(0.0, 2.0);
  }

  @override
  void didUpdateWidget(_InputMeter old) {
    super.didUpdateWidget(old);
    if (old.level != widget.level) {
      old.level.removeListener(_onLevel);
      widget.level.addListener(_onLevel);
    }
  }

  @override
  void dispose() {
    widget.level.removeListener(_onLevel);
    _fall?.cancel();
    _clipHold?.cancel();
    super.dispose();
  }

  void _onLevel() {
    final p = widget.level.value.clamp(0.0, 2.0);
    if (p >= 0.999) {
      _clipHold?.cancel();
      _clipHold = Timer(const Duration(milliseconds: 1500), () {
        if (mounted) setState(() => _clip = false);
      });
      if (!_clip) setState(() => _clip = true);
    }
    if (p >= _v) {
      _fall?.cancel();
      _fall = null;
      if (p != _v) setState(() => _v = p);
      return;
    }
    _fall ??= Timer.periodic(const Duration(milliseconds: 33), (_) {
      final target = widget.level.value.clamp(0.0, 2.0);
      var v = math.max(target, _v * 0.82);
      if (v - target < 0.001) {
        v = target;
        _fall?.cancel();
        _fall = null;
      }
      if (mounted && v != _v) setState(() => _v = v);
    });
  }

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _InputMeterPainter(_meterLevel(_v), _clip), size: Size.infinite);
}

class _InputMeterPainter extends CustomPainter {
  final double level;
  final bool clip;
  _InputMeterPainter(this.level, this.clip);

  static const _gradient = LinearGradient(colors: [Palette.success, Palette.success, Color(0xFFE3B341), Palette.danger], stops: [0, 0.7, 0.88, 1]);

  @override
  void paint(Canvas canvas, Size size) {
    final full = Offset.zero & size;
    canvas.drawRect(full, Paint()..color = Colors.white.withValues(alpha: 0.08));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width * level, size.height), Paint()..shader = _gradient.createShader(full));
    if (clip) canvas.drawRect(Rect.fromLTWH(size.width - 4, 0, 4, size.height), Paint()..color = _recordColor);
  }

  @override
  bool shouldRepaint(_InputMeterPainter o) => o.level != level || o.clip != clip;
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
  final double width;
  const _KindButton({required this.c, required this.index, required this.color, this.width = 24});

  @override
  Widget build(BuildContext context) {
    final t = c.doc.tracks[index];
    final bus = t.kind == TrackKind.bus;
    if (!t.kind.isInstrument && !bus) {
      return Tooltip(
        message: 'Faixa de áudio',
        child: SizedBox(
          width: width,
          height: 24,
          child: Icon(t.kind.icon, size: 16, color: color),
        ),
      );
    }
    final open = bus ? c.dock == Dock.effects && c.effectsTrack == index : c.dock == Dock.instrument && c.selectedTrack == index;
    final tooltip = bus
        ? (open ? 'Fechar os efeitos' : 'Barramento: abrir os efeitos')
        : (open ? 'Fechar o instrumento (I)' : '${t.kind.label}: abrir o instrumento (I)');
    return SizedBox(
      width: width,
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
          case 'up':
            moveTrackAsking(context, c, index, index - 1);
          case 'down':
            moveTrackAsking(context, c, index, index + 1);
          case 'duplicate':
            c.duplicateTrack(index);
          case 'monitor':
            c.setMonitor(index, !c.doc.tracks[index].monitor);
          case 'bounce':
            await _bounce(context, c, index);
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
          default:
            if (v.startsWith('grp:')) await onGroupMenu(context, c, index, v);
        }
      },
      itemBuilder: (context) {
        final t = c.doc.tracks[index];
        final why = _cannotBounce(c, t);
        final caption = Theme.of(context).textTheme.labelSmall!.copyWith(color: Colors.white38);
        return [
          if (t.kind.isInstrument) const PopupMenuItem(value: 'instrument', child: Text('Abrir o instrumento')),
          const PopupMenuItem(value: 'effects', child: Text('Efeitos')),
          if (t.kind == TrackKind.audio) CheckedPopupMenuItem(value: 'monitor', checked: t.monitor, child: const Text('Monitorar a entrada')),
          const PopupMenuItem(value: 'rename', child: Text('Renomear')),
          const PopupMenuItem(value: 'duplicate', child: Text('Duplicar a faixa')),
          PopupMenuItem(
            value: 'bounce',
            enabled: why == null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Congelar em áudio'),
                Text(why ?? 'Vira uma faixa de áudio nova; esta fica muda', style: caption),
              ],
            ),
          ),
          PopupMenuItem(value: 'up', enabled: index > 0, child: const Text('Mover para cima')),
          PopupMenuItem(value: 'down', enabled: index < c.doc.tracks.length - 1, child: const Text('Mover para baixo')),
          ...groupMenuItems(c, index),
          const PopupMenuItem(value: 'color', child: Text('Trocar a cor')),
          const PopupMenuItem(value: 'delete', child: Text('Apagar a faixa')),
        ];
      },
    ),
  );
}

/// Por que a faixa não pode ser congelada agora (null quando pode): barramento só tem o que as
/// outras mandam, faixa sem clipes (ou só com clipes de notas vazios) renderizaria silêncio, e
/// durante a gravação o documento ainda vai mudar.
String? _cannotBounce(DawController c, DawTrack t) {
  if (t.kind == TrackKind.bus) return 'Barramento não tem som próprio';
  final empty = t.kind.isInstrument ? t.midi.every((m) => m.notes.isEmpty) : t.clips.isEmpty;
  if (empty) return 'A faixa está vazia';
  if (c.recording) return 'Pare a gravação antes';
  return null;
}

Future<void> _bounce(BuildContext context, DawController c, int index) async {
  if (!context.mounted || index >= c.doc.tracks.length || _cannotBounce(c, c.doc.tracks[index]) != null) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _BounceDialog(c: c, track: index, name: c.doc.tracks[index].name),
  );
}

/// O erro de uma operação longa como a pessoa deve ler, sem "Bad state:" nem nome de classe.
String _failureText(Object e, String fallback) => switch (e) {
  String s => s,
  StateError(:final message) => message,
  UnimplementedError() => 'Isso ainda não funciona nesta versão.',
  UnsupportedError(:final message) => message ?? fallback,
  _ => '$fallback (${'$e'.replaceFirst('Exception: ', '')})',
};

/// Progresso do congelamento. O render roda fora de tempo real num motor à parte, então dá para
/// esperar aqui; não fecha por fora enquanto trabalha ("Cancelar" interrompe o render e fecha) e,
/// se falhar, mostra o erro no próprio diálogo.
class _BounceDialog extends StatefulWidget {
  final DawController c;
  final int track;
  final String name;
  const _BounceDialog({required this.c, required this.track, required this.name});

  @override
  State<_BounceDialog> createState() => _BounceDialogState();
}

class _BounceDialogState extends State<_BounceDialog> {
  double _progress = 0;
  String? _error;
  bool _canceled = false;

  @override
  void initState() {
    super.initState();
    // depois do primeiro quadro: se o controlador falhar na hora, o diálogo já existe para mostrar
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    final c = widget.c;
    // o controlador não lança: a falha chega no error dele, que começa limpo
    c.clearError();
    try {
      await c.bounceTrack(widget.track, onProgress: _onProgress);
      if (!mounted) return;
      final said = c.error;
      if (said != null && !_canceled) {
        // mostrado aqui, sai da tela de trás
        c.clearError();
        setState(() => _error = said);
      } else {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) setState(() => _error = _failureText(e, 'Não deu para congelar a faixa'));
    }
  }

  void _cancel() {
    setState(() => _canceled = true);
    widget.c.cancelRender();
  }

  void _onProgress(double p) {
    final v = p.isFinite ? p.clamp(0.0, 1.0) : 0.0;
    // o render avisa a cada bloco; a tela só precisa dos passos que se veem
    if (!mounted || ((v - _progress).abs() < 0.005 && v < 1)) return;
    setState(() => _progress = v);
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    return PopScope(
      canPop: error != null,
      child: AlertDialog(
        title: Text(error == null ? 'Congelando "${widget.name}"' : 'Não deu para congelar'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: error != null
              ? InlineNotice(error)
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('A faixa vira áudio com o instrumento e os efeitos, numa faixa nova logo abaixo; esta fica muda.'),
                    const SizedBox(height: 16),
                    LinearProgressIndicator(value: _progress > 0 ? _progress : null),
                    const SizedBox(height: 8),
                    Text(_progress > 0 ? '${(_progress * 100).floor()}%' : 'Preparando…', style: Theme.of(context).textTheme.labelSmall),
                  ],
                ),
        ),
        actions: error == null
            ? [TextButton(onPressed: _canceled ? null : _cancel, child: Text(_canceled ? 'Cancelando…' : 'Cancelar'))]
            : [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Fechar'))],
      ),
    );
  }
}

/// Fader pequeno dos cabeçalhos (faixa e master): [onStart] marca o desfazer, [onGain] muda sem
/// histórico a cada passo.
class _MiniFader extends StatelessWidget {
  final double gain;

  /// Seguindo a automação agora (tocando): cor de automação.
  final bool automated;
  final VoidCallback onStart;
  final ValueChanged<double> onGain;

  /// Soltou o deslizador (fecha a passada de gravação de automação).
  final VoidCallback? onEnd;
  const _MiniFader({super.key, required this.gain, required this.onStart, required this.onGain, this.onEnd, this.automated = false});

  @override
  Widget build(BuildContext context) => Tooltip(
    message: '${formatDb(gain)} dB',
    child: SliderTheme(
      data: SliderTheme.of(context).copyWith(
        activeTrackColor: automated ? automationColor : null,
        thumbColor: automated ? automationColor : null,
        trackHeight: 2,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
      ),
      child: SizedBox(
        height: 22,
        child: Slider(
          value: gainToFader(gain).clamp(0, 1),
          onChangeStart: (_) => onStart(),
          onChanged: (v) => onGain(faderToGain(v)),
          onChangeEnd: (_) => onEnd?.call(),
        ),
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

  /// Largura (24; 20 nos cabeçalhos do celular, onde a linha tem um botão a mais).
  final double width;
  const ToggleChip({
    super.key,
    required this.label,
    required this.on,
    required this.color,
    required this.tooltip,
    required this.onTap,
    this.lit = false,
    this.width = 24,
  });

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        width: width,
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
            case TrackKind.synth || TrackKind.drums || TrackKind.sampler || TrackKind.fm || TrackKind.wavetable:
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
                        // grava automação como o da faixa (Escrever/Toque/Trava); gravando, vale o que a mão pôs
                        child: ListenableBuilder(
                          listenable: Listenable.merge([c.beat, c.autoRec]),
                          builder: (_, _) {
                            const volume = AutoTarget(AutoKind.volume);
                            final hand = c.autoRec.isRecording(-1, volume);
                            final follows = c.automated(-1, AutoKind.volume) && !hand;
                            return _MiniFader(
                              gain: follows ? c.liveValue(-1, AutoKind.volume) : c.doc.masterGain,
                              automated: follows && c.playing.value,
                              onStart: () {
                                c.autoRec.touch(-1, volume);
                                c.checkpoint();
                              },
                              onGain: (g) {
                                c.autoRec.value(-1, volume, g);
                                c.mutate((d) => d.masterGain = g);
                              },
                              onEnd: () => c.autoRec.release(-1, volume),
                            );
                          },
                        ),
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
  final double width;
  const _AutomationButton({required this.c, required this.track, this.width = 24});

  @override
  Widget build(BuildContext context) {
    final lanes = automationLanesOf(c, track);
    return ToggleChip(
      label: 'A',
      width: width,
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
    // gravando, o cursor fica onde está (ver [_Ruler])
    if (!c.recording) c.seek(c.snapBeat(at));
    if (_taps(d.globalPosition) && lane >= 0 && c.doc.tracks[lane].kind.isInstrument) _createClip(lane, at);
  }

  /// Duplo toque no vazio de uma faixa de instrumento: clipe novo no compasso tocado, sem montar
  /// em cima dos vizinhos (começa depois do anterior e termina antes do próximo), já no editor.
  void _createClip(int lane, double at) {
    final t = c.doc.tracks[lane];
    final meter = c.doc.meter;
    final (barNo, _) = meter.barOf(math.max(0.0, at));
    final bar = meter.barBeats(barNo);
    var start = meter.barStart(barNo);
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
    final doc = c.doc;
    final tracks = doc.tracks;
    // o clipe selecionado fica montado mesmo fora da janela: é ele que está sendo arrastado, e
    // desmontar no meio do gesto o perderia
    bool shown(String id, double start, double end) => (end > c.scrollBeat && start < visibleEnd) || id == c.selectedClip;
    final hint = Theme.of(context).textTheme.labelSmall!.copyWith(color: Colors.white30);
    String? hintOf(DawTrack t) {
      if (t.isGroup) return t.collapsed ? null : 'Pasta: o volume, o mudo e os efeitos dela valem para as faixas de baixo';
      if (t.kind == TrackKind.bus) return 'Barramento: recebe o som das faixas que enviam ou saem para ele';
      final empty = t.kind.isInstrument ? t.midi.isEmpty : t.clips.isEmpty;
      if (!empty) return null;
      // armada e vazia: diz o que a gravação vai pôr ali (gravando, a região vermelha já diz)
      if (t.armed) {
        if (c.recording) return null;
        return t.kind.isInstrument ? 'Armada: ao gravar, as notas tocadas viram um clipe aqui' : 'Armada: ao gravar, o som da entrada vira um clipe aqui';
      }
      if (!t.kind.isInstrument) return null;
      return widget.touch ? 'Toque duas vezes para criar um clipe de notas' : 'Clique duas vezes para criar um clipe de notas';
    }

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
                    meter: c.doc.meter,
                    bands: [for (final r in layout.rows) (r.top, r.height, _bandOf(r, tracks))],
                    selected: c.selectedTrack < tracks.length ? layout.trackTop[c.selectedTrack] : null,
                    laneHeight: laneHeight,
                  ),
                ),
              ),
              for (var ti = 0; ti < tracks.length; ti++)
                if (!doc.hiddenByGroup(ti))
                  if (hintOf(tracks[ti]) case final text?)
                    Positioned(
                      left: 12,
                      right: 12,
                      top: layout.trackTop[ti],
                      height: laneHeight,
                      child: IgnorePointer(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: hint),
                        ),
                      ),
                    ),
              // pasta recolhida: a miniatura dos clipes das filhas na linha dela
              for (var ti = 0; ti < tracks.length; ti++)
                if (tracks[ti].isGroup && tracks[ti].collapsed)
                  Positioned(
                    key: ValueKey('group-mini:${tracks[ti].id}'),
                    left: 0,
                    right: 0,
                    top: layout.trackTop[ti],
                    height: laneHeight,
                    child: GroupMiniLane(c: c, index: ti, scrollBeat: c.scrollBeat, pxPerBeat: c.pxPerBeat),
                  ),
              for (var ti = 0; ti < tracks.length; ti++) ...[
                if (!doc.hiddenByGroup(ti)) ...[
                  for (final clip in tracks[ti].clips)
                    if (shown(clip.id, clip.start, doc.clipEnd(clip)))
                      Positioned(
                        key: ValueKey(clip.id),
                        left: (clip.start - c.scrollBeat) * c.pxPerBeat,
                        top: layout.trackTop[ti] + 2,
                        width: math.max(4, doc.clipBeats(clip) * c.pxPerBeat),
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
              ],
              // por cima dos clipes (a gravação substitui o que estiver embaixo); montada só enquanto
              // grava, então o estado dela (onde começou, quantas voltas deu no loop) nasce e morre
              // com a gravação; a chave a mantém no lugar quando a lista de cima muda
              if (c.recording)
                Positioned.fill(
                  key: const ValueKey('recording'),
                  child: IgnorePointer(
                    child: _RecordingOverlay(
                      c: c,
                      rows: [
                        for (var ti = 0; ti < tracks.length; ti++)
                          if (tracks[ti].armed && tracks[ti].kind != TrackKind.bus && !doc.hiddenByGroup(ti)) (layout.trackTop[ti], laneHeight),
                      ],
                    ),
                  ),
                ),
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
  final MeterMap meter;

  /// Topo, altura e tipo de cada linha.
  final List<(double, double, _Band)> bands;

  /// Topo da faixa selecionada.
  final double? selected;
  _GridPainter({required this.scroll, required this.ppb, required this.meter, required this.bands, required this.selected, required this.laneHeight});

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
    final step = _barStep(ppb, meter.barBeatsAt(scroll));
    final visibleEnd = scroll + size.width / ppb;
    for (var barNo = meter.barOf(scroll).$1; meter.barStart(barNo) <= visibleEnd; barNo++) {
      final at = meter.barStart(barNo);
      final x = (at - scroll) * ppb;
      if ((barNo - 1) % step == 0) canvas.drawRect(Rect.fromLTWH(x, 0, 1, size.height), bar);
      final c = meter.changeAt(barNo);
      if (ppb * c.unit >= 16) {
        for (var b = 1; b < c.numerator; b++) {
          canvas.drawRect(Rect.fromLTWH(x + b * c.unit * ppb, 0, 1, size.height), beat);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_GridPainter o) =>
      o.scroll != scroll || o.ppb != ppb || !identical(o.meter, meter) || o.selected != selected || o.laneHeight != laneHeight || !listEquals(o.bands, bands);
}

// ---------------------------------------------------------------------- gravação

/// A região que está sendo gravada, em vermelho translúcido nas faixas armadas, do começo da
/// gravação até o cursor. Na contagem ainda não há região (nada entra). Gravando em loop, cada
/// volta do cursor é uma tomada nova: a passada atual fica forte e o que já foi coberto, fraco.
///
/// A região começa onde a gravação vale ([DawController.recordStart]); sem ela, na primeira
/// posição vista depois da contagem, ou onde o cursor estava quando a gravação ligou se a posição
/// ainda está a menos de meia batida dali (a do motor chega um quadro atrasada).
class _RecordingOverlay extends StatefulWidget {
  final DawController c;

  /// Topo e altura de cada faixa armada.
  final List<(double, double)> rows;
  const _RecordingOverlay({required this.c, required this.rows});

  @override
  State<_RecordingOverlay> createState() => _RecordingOverlayState();
}

class _RecordingOverlayState extends State<_RecordingOverlay> {
  /// Cursor quando a gravação ligou (antes da contagem).
  late double _pressedAt;

  /// Começo da região (null na contagem), última posição vista e a passada atual no loop.
  double? _from;
  double _last = 0;
  int _pass = 1;

  DawController get c => widget.c;

  @override
  void initState() {
    super.initState();
    _pressedAt = c.beat.value;
    c.beat.addListener(_onBeat);
  }

  @override
  void didUpdateWidget(_RecordingOverlay old) {
    super.didUpdateWidget(old);
    if (old.c != widget.c) {
      old.c.beat.removeListener(_onBeat);
      widget.c.beat.addListener(_onBeat);
    }
  }

  @override
  void dispose() {
    c.beat.removeListener(_onBeat);
    super.dispose();
  }

  void _onBeat() => setState(() {});

  /// Acompanha a posição [b]: começo depois da contagem, voltas do loop e saltos para trás. Pode
  /// rodar mais de uma vez com a mesma posição (a tela redesenha por outros motivos) sem efeito.
  void _follow(double b) {
    if (c.countingIn) {
      _from = null;
      _pass = 1;
      return;
    }
    if (_from == null) {
      _from = c.recordStart ?? (b >= _pressedAt && b - _pressedAt < 0.5 ? _pressedAt : b);
      _last = b;
      return;
    }
    // folga de um vigésimo de batida: tremida da posição do motor não é salto
    if (b < _last - 0.05) {
      if (c.doc.loopOn) {
        _pass++;
      } else {
        // voltou sem loop (o cursor foi reposicionado por fora): a região recomeça onde ele está
        _from = b;
        _pass = 1;
      }
    }
    _last = b;
  }

  @override
  Widget build(BuildContext context) {
    final b = c.beat.value;
    _follow(b);
    final from = _from;
    if (from == null || widget.rows.isEmpty) return const SizedBox.expand();
    final looped = _pass > 1;
    return CustomPaint(
      size: Size.infinite,
      painter: _RecordingPainter(
        rows: widget.rows,
        scroll: c.scrollBeat,
        ppb: c.pxPerBeat,
        from: looped ? c.doc.loopStart : from,
        to: b,
        covered: looped ? (math.min(from, c.doc.loopStart), c.doc.loopEnd) : null,
        label: looped ? 'Tomada $_pass' : 'Gravando',
      ),
    );
  }
}

class _RecordingPainter extends CustomPainter {
  final List<(double, double)> rows;
  final double scroll, ppb, from, to;

  /// Já coberto pelas passadas anteriores do loop (em batidas).
  final (double, double)? covered;
  final String label;

  _RecordingPainter({
    required this.rows,
    required this.scroll,
    required this.ppb,
    required this.from,
    required this.to,
    required this.covered,
    required this.label,
  });

  @override
  void paint(Canvas canvas, Size size) {
    double x(double b) => (b - scroll) * ppb;
    final fill = Paint()..color = _recordColor.withValues(alpha: 0.2);
    final faint = Paint()..color = _recordColor.withValues(alpha: 0.08);
    final outline = Paint()
      ..color = _recordColor.withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final head = Paint()..color = _recordColor;
    final l = x(from), r = x(to);
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    for (final (top, h) in rows) {
      final y0 = top + 2, y1 = top + h - 2;
      if (covered case (final a, final z)) canvas.drawRect(Rect.fromLTRB(x(a), y0, x(z), y1), faint);
      if (r - l < 0.5) continue;
      final box = RRect.fromRectAndRadius(Rect.fromLTRB(l, y0, r, y1).deflate(0.5), const Radius.circular(4));
      canvas.drawRRect(box, fill);
      canvas.drawRRect(box, outline);
      // a borda que cresce, junto do cursor
      canvas.drawRect(Rect.fromLTRB(r - 2, y0, r, y1), head);
      // o nome acompanha a borda esquerda da janela quando o começo já saiu dela
      final lx = math.max(l, 0.0) + 6;
      if (r - lx > tp.width + 6) tp.paint(canvas, Offset(lx, y0 + 3));
    }
    tp.dispose();
  }

  @override
  bool shouldRepaint(_RecordingPainter o) =>
      o.scroll != scroll || o.ppb != ppb || o.from != from || o.to != to || o.covered != covered || o.label != label || !listEquals(o.rows, rows);
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

  /// O gesto só mexeu num fade: não reacomoda os clipes da faixa (nem cria crossfade).
  bool _fadeOnly = false;

  void beginEdit() {
    _dirty = false;
    _fadeOnly = false;
  }

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
    if (_fadeOnly) return;
    // travessia de borda vira crossfade (de potência constante) em vez de aparar o de baixo
    ctl.mutate((_) => ctl.placeOnTop(editedClipId, crossfade: true));
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

/// Explica a curva do fade no tooltip do item do menu.
String fadeShapeHint(FadeShape shape) => switch (shape) {
  FadeShape.linear =>
    'Suave (x²): a curva de sempre, que os projetos antigos usam. Num crossfade o nível afunda uns 6 dB no meio; '
        'para manter o nível, use "Potência constante" ou "S".',
  FadeShape.equalPower => 'Mantém a potência no crossfade: o nível não afunda no meio.',
  FadeShape.exponential => 'Na saída cai depressa e some suave; na entrada sobe devagar e acelera.',
  FadeShape.sCurve => 'Suave nas duas pontas e mantém o nível no crossfade.',
};

/// Item das curvas de fade: marca no valor atual e, no tooltip, o que a curva faz.
PopupMenuItem<String> _shapeItem(String value, String prefix, FadeShape shape, bool checked) => PopupMenuItem(
  value: value,
  child: Tooltip(
    message: fadeShapeHint(shape),
    child: Row(
      children: [
        SizedBox(width: 18, child: checked ? const Icon(Icons.check, size: 18) : null),
        const SizedBox(width: 12),
        Expanded(child: Text('$prefix: ${shape.label}')),
      ],
    ),
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
    // segundos da origem por batida: com warp o clipe segue o andamento do áudio, não o do projeto
    // (e com mapa de andamento, o vigente na batida do clipe)
    final tb = c.doc.sourceTempoAt(clip, clip.start);
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
        final minStart = math.max(0.0, _orig.start - _orig.offset * tb / 60);
        final maxStart = math.max(minStart, c.doc.clipEnd(_orig) - minLen * tb / 60);
        start = start.clamp(minStart, maxStart);
        final secs = (start - _orig.start) * 60 / tb;
        if (start != clip.start) {
          change(() {
            clip.start = start;
            clip.offset = _orig.offset + secs;
            clip.length = _orig.length - secs;
          });
        }
      case _Grab.right:
        final end = _snapDrag(c, c.doc.clipEnd(_orig) + dBeats);
        final len = ((end - _orig.start) * 60 / tb).clamp(minLen, math.max<double>(minLen, dur - _orig.offset));
        if (len != clip.length) change(() => clip.length = len);
      case _Grab.fadeIn:
        final f = (_orig.fadeIn + total.dx / c.pxPerBeat * 60 / tb).clamp(0.0, math.max<double>(0.0, clip.length - clip.fadeOut));
        _fadeOnly = true;
        if (f != clip.fadeIn) {
          change(() {
            clip.fadeIn = f;
            clip.autoFadeIn = null; // mexido à mão: deixa de ser automático
          });
        }
      case _Grab.fadeOut:
        final f = (_orig.fadeOut - total.dx / c.pxPerBeat * 60 / tb).clamp(0.0, math.max<double>(0.0, clip.length - clip.fadeIn));
        _fadeOnly = true;
        if (f != clip.fadeOut) {
          change(() {
            clip.fadeOut = f;
            clip.autoFadeOut = null;
          });
        }
    }
  }

  Future<void> _menu(Offset at) async {
    final c = widget.c;
    final takes = widget.clip.takes.length;
    final v = await _showMenuAt(context, at, [
      if (takes > 0) ...[
        PopupMenuItem(
          value: 'takes',
          child: Row(
            children: [
              const Icon(Icons.layers_outlined, size: 18),
              const SizedBox(width: 12),
              const Expanded(child: Text('Tomadas')),
              Text('$takes', style: const TextStyle(fontSize: 12, color: Colors.white54)),
              const Icon(Icons.chevron_right, size: 18),
            ],
          ),
        ),
        const PopupMenuDivider(),
      ],
      _menuItem('duplicate', Icons.copy_all, 'Duplicar', shortcut: withMod('Ctrl+D')),
      _menuItem('split', Icons.content_cut, 'Cortar no cursor', shortcut: 'S'),
      _menuItem('warp', Icons.graphic_eq, 'Warp e altura…'),
      _menuItem('gain', Icons.volume_up_outlined, 'Ganho do clipe…'),
      const PopupMenuDivider(),
      _menuItem('fadein_len', Icons.trending_up, 'Fade de entrada…'),
      _menuItem('fadeout_len', Icons.trending_down, 'Fade de saída…'),
      for (final shape in FadeShape.values) _shapeItem('fin:${shape.index}', 'Fade de entrada', shape, widget.clip.fadeInShape == shape),
      for (final shape in FadeShape.values) _shapeItem('fout:${shape.index}', 'Fade de saída', shape, widget.clip.fadeOutShape == shape),
      _menuItem('crossfade', Icons.compare_arrows, 'Crossfade neste clipe'),
      _menuItem('crossfade_all', Icons.compare_arrows, 'Crossfade em toda a faixa'),
      const PopupMenuDivider(),
      _menuItem('to_midi', Icons.piano, 'Converter em notas (MIDI)'),
      _menuItem('delete', Icons.delete_outline, 'Apagar', shortcut: 'Delete'),
    ]);
    if (v == null || !mounted) return;
    // age sobre este clipe, qualquer que seja a seleção ao fechar o menu
    c.selectClip(widget.clip.id);
    switch (v) {
      case 'takes':
        await _takesMenu(at);
      case 'warp':
        await showWarpDialog(context, c, widget.clip.id);
      case final f when f.startsWith('fin:'):
        c.setFadeShapes(widget.clip.id, fadeIn: FadeShape.values[int.parse(f.substring(4))]);
      case final f when f.startsWith('fout:'):
        c.setFadeShapes(widget.clip.id, fadeOut: FadeShape.values[int.parse(f.substring(5))]);
      case 'gain':
        await showClipGainDialog(context, c, widget.clip.id);
      case 'to_midi':
        await showConvertToMidi(context, c, widget.clip.id);
      case 'fadein_len':
        await showFadeLengthDialog(context, c, widget.clip.id, fadeIn: true);
      case 'fadeout_len':
        await showFadeLengthDialog(context, c, widget.clip.id, fadeIn: false);
      case 'crossfade':
        c.crossfadeOverlaps(widget.clip.id);
      case 'crossfade_all':
        c.crossfadeOverlaps(widget.clip.id, wholeTrack: true);
      case 'duplicate':
        c.duplicateSelected();
      case 'split':
        c.splitAtPlayhead();
      case 'delete':
        c.deleteSelected();
    }
  }

  /// As tomadas de uma gravação em loop, na ordem das passadas, com a ativa marcada; escolher
  /// outra troca o áudio do clipe (posição, corte e fades ficam).
  Future<void> _takesMenu(Offset at) async {
    final c = widget.c;
    final clip = widget.clip;
    if (clip.takes.isEmpty) return;
    // a ativa pela posição: duas passadas iguais (silêncio) teriam o mesmo hash e as duas marcadas
    final active = clip.takes.indexOf(clip.sample);
    final small = Theme.of(context).textTheme.labelSmall!.copyWith(color: Colors.white38, letterSpacing: 0.6);
    final v = await _showMenuAt(context, at, [
      PopupMenuItem<String>(enabled: false, height: 28, child: Text('TOMADAS', style: small)),
      for (final (i, hash) in clip.takes.indexed)
        PopupMenuItem<String>(
          value: '$i',
          height: 40,
          child: Row(
            children: [
              SizedBox(width: 20, child: i == active ? const Icon(Icons.check, size: 16, color: Palette.accent) : null),
              const SizedBox(width: 10),
              Expanded(child: Text('Tomada ${i + 1}')),
              if (c.missing.contains(hash)) ...[const SizedBox(width: 12), Text('fora deste aparelho', style: small)],
            ],
          ),
        ),
    ]);
    if (v == null || !mounted) return;
    final i = int.parse(v);
    // o clipe pode ter perdido tomadas enquanto o menu estava aberto (desfazer)
    if (i == active || i >= clip.takes.length) return;
    c.switchTake(clip.id, clip.takes[i]);
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
    final pxPerSec = c.pxPerBeat * c.doc.sourceTempoAt(clip, clip.start) / 60;
    final width = c.doc.clipBeats(clip) * c.pxPerBeat;
    final takes = clip.takes;
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
                  painter: _FadePainter(
                    fadeIn: clip.fadeIn * pxPerSec,
                    fadeOut: clip.fadeOut * pxPerSec,
                    inShape: clip.fadeInShape,
                    outShape: clip.fadeOutShape,
                  ),
                ),
              ),
              Positioned(
                left: 6,
                // com o selo, a alça do fade de saída (canto de cima à direita) continua livre
                right: takes.isEmpty ? 6 : 16,
                top: 1,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white),
                      ),
                    ),
                    if (clip.processed && width >= 40) ...[
                      const SizedBox(width: 4),
                      _WarpBadge(clip: clip, pending: c.warpPending(clip), failed: c.warpFailure(clip) != null),
                    ],
                    if (takes.isNotEmpty && width >= 60) ...[
                      const SizedBox(width: 4),
                      // o nome fica com pelo menos 20 px; o selo encolhe (e corta o texto) antes de estourar
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: math.max(28.0, width - 22 - 24)),
                        child: _TakesBadge(count: takes.length, active: takes.indexOf(clip.sample), short: width < 150, onTap: _takesMenu),
                      ),
                    ],
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

/// Selo pequeno do warp no canto do clipe: o que está ligado (W esticado ao andamento, semitons,
/// R invertido) ou "processando…" enquanto o som novo não fica pronto.
class _WarpBadge extends StatelessWidget {
  final AudioClip clip;
  final bool pending, failed;
  const _WarpBadge({required this.clip, required this.pending, required this.failed});

  @override
  Widget build(BuildContext context) {
    final parts = [
      if (clip.stretches) 'W',
      if (clip.pitch != 0) '${clip.pitch > 0 ? '+' : ''}${clip.pitch % 1 == 0 ? clip.pitch.toStringAsFixed(0) : clip.pitch.toStringAsFixed(1)}st',
      if (clip.reverse) 'R',
    ];
    final label = pending ? 'processando…' : parts.join(' ');
    return Tooltip(
      message: failed ? 'O warp não ficou pronto: o clipe toca o original' : (pending ? 'Processando o warp…' : 'Warp e altura'),
      child: Container(
        height: 14,
        padding: const EdgeInsets.symmetric(horizontal: 5),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: failed ? Palette.danger : Colors.white24),
        ),
        alignment: Alignment.center,
        child: Text(label.isEmpty ? 'warp' : label, maxLines: 1, style: const TextStyle(fontSize: 9, height: 1.1, color: Colors.white70)),
      ),
    );
  }
}

/// Selo "N tomadas" de um clipe gravado em loop (só o número em clipe estreito); tocar abre a
/// lista para trocar a ativa.
class _TakesBadge extends StatelessWidget {
  final int count;

  /// Posição da tomada ativa (−1 se o áudio do clipe não é nenhuma delas).
  final int active;
  final bool short;
  final ValueChanged<Offset> onTap;
  const _TakesBadge({required this.count, required this.active, required this.short, required this.onTap});

  @override
  Widget build(BuildContext context) => Tooltip(
    message: active >= 0 ? 'Tomada ${active + 1} de $count: escolher outra' : '$count tomadas: escolher uma',
    child: GestureDetector(
      onTapUp: (d) => onTap(d.globalPosition),
      child: Container(
        height: 14,
        padding: const EdgeInsets.symmetric(horizontal: 5),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.layers_outlined, size: 10, color: Colors.white70),
            const SizedBox(width: 3),
            Flexible(
              child: Text(
                short ? '$count' : '$count tomadas',
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.clip,
                style: const TextStyle(fontSize: 9.5, height: 1.1, fontWeight: FontWeight.w600, color: Colors.white70),
              ),
            ),
          ],
        ),
      ),
    ),
  );
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
    final g = _gridBeats(widget.c, widget.clip.start);
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
            // refeito do original a cada passo (o estado escrito abaixo muda a lista): os eventos de antes
            // do novo começo ficam guardados com batida negativa e o que valia ali (o pedal seguro, o
            // bend) vira um evento no começo do clipe, como no corte
            clip.controls = trimControlsLeft(_orig.controls, delta);
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
      _menuItem('duplicate', Icons.copy_all, 'Duplicar', shortcut: withMod('Ctrl+D')),
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
    // com ganho alto a onda passa da altura: corta na área dela (senão invade o nome do clipe)
    canvas.clipRect(Offset.zero & size);
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
  final FadeShape inShape, outShape;
  _FadePainter({required this.fadeIn, required this.fadeOut, this.inShape = FadeShape.linear, this.outShape = FadeShape.linear});

  /// O contorno do fade de [width] px visto da borda do clipe para dentro: o ganho da curva vira a
  /// altura (1 = topo do clipe). A saída é a mesma curva olhada da borda direita.
  List<Offset> _curve(FadeShape shape, double width, double height) {
    final n = math.max(4, math.min(48, (width / 3).ceil()));
    return [for (var i = 0; i <= n; i++) Offset(width * i / n, height * (1 - shape.gain(i / n)))];
  }

  @override
  void paint(Canvas canvas, Size size) {
    final shade = Paint()..color = Colors.black.withValues(alpha: 0.35);
    final line = Paint()
      ..color = Colors.white70
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    if (fadeIn > 0) {
      final pts = _curve(inShape, fadeIn, size.height);
      // o que o fade tira (acima da curva) escurece; a curva é o ganho sobre a onda
      final area = Path()..moveTo(0, 0);
      area.lineTo(fadeIn, 0);
      for (final p in pts.reversed) {
        area.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(area..close(), shade);
      canvas.drawPath(Path()..addPolygon(pts, false), line);
    }
    if (fadeOut > 0) {
      // a saída é a entrada vista de trás: o ganho cai de 1 (esquerda) a 0 (borda direita)
      final pts = [for (final p in _curve(outShape, fadeOut, size.height)) Offset(size.width - p.dx, p.dy)];
      final area = Path()..moveTo(size.width, 0);
      area.lineTo(size.width - fadeOut, 0);
      for (final p in pts.reversed) {
        area.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(area..close(), shade);
      canvas.drawPath(Path()..addPolygon(pts, false), line);
    }
    // alças de fade nos cantos de cima
    final knob = Paint()..color = Colors.white;
    canvas.drawCircle(Offset(math.max(5, fadeIn), 5), 3, knob);
    canvas.drawCircle(Offset(math.min(size.width - 5, size.width - fadeOut), 5), 3, knob);
  }

  @override
  bool shouldRepaint(_FadePainter o) => o.fadeIn != fadeIn || o.fadeOut != fadeOut || o.inShape != inShape || o.outShape != outShape;
}
