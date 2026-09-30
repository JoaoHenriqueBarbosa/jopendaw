/// A faixa de andamento sob a régua: os pontos do mapa de andamento (duplo clique adiciona, arrastar
/// na vertical muda o BPM e na horizontal move, botão direito ou toque longo abre o menu) e o
/// diálogo de mudança de compasso. A lógica mora no controlador ([DawController.addTempoPoint] e
/// companhia); aqui só a parte de tela.
library;

import 'dart:math' as math;

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/dialogs.dart';
import '../widgets/theme.dart';
import 'controller.dart';
import 'tempo_map.dart';
import 'warp_dialog.dart' show formatBpm, parseBpm;

/// Altura da faixa de andamento.
const tempoLaneHeight = 22.0;

/// Pixels de arraste na vertical por BPM (com Alt, dez vezes mais fino).
const _bpmPerPixel = 0.5;

class TempoLane extends StatefulWidget {
  final DawController c;
  const TempoLane({super.key, required this.c});

  @override
  State<TempoLane> createState() => _TempoLaneState();
}

class _TempoLaneState extends State<TempoLane> {
  DawController get c => widget.c;

  int? _index;
  double _beat0 = 0, _bpm0 = 0;
  Offset _down = Offset.zero, _doubleAt = Offset.zero;
  bool _checkpointed = false;

  double _beatAt(double x) => c.scrollBeat + x / c.pxPerBeat;
  double _xOf(double beat) => (beat - c.scrollBeat) * c.pxPerBeat;

  /// O ponto sob o dedo ou o mouse (null: nenhum perto).
  int? _hit(Offset p) {
    final pts = c.doc.tempo.points;
    int? best;
    var bestD = double.infinity;
    for (var i = 0; i < pts.length; i++) {
      final dx = (_xOf(pts[i].beat) - p.dx).abs();
      if (dx <= 10 && dx < bestD) {
        best = i;
        bestD = dx;
      }
    }
    return best;
  }

  bool get _fine => HardwareKeyboard.instance.isAltPressed;

  double _snap(double beat) => _fine ? beat : c.snapBeat(beat);

  void _panStart(DragStartDetails d) {
    if (c.recording) return;
    _index = _hit(d.localPosition);
    final i = _index;
    if (i == null) return;
    final p = c.doc.tempo.points[i];
    _beat0 = p.beat;
    _bpm0 = p.bpm;
    _down = d.localPosition;
    _checkpointed = false;
  }

  void _panUpdate(DragUpdateDetails d) {
    final i = _index;
    if (i == null || c.recording) return;
    final dx = d.localPosition.dx - _down.dx, dy = d.localPosition.dy - _down.dy;
    // para cima sobe o BPM; no ponto inicial só a vertical vale
    final bpm = (_bpm0 - dy * _bpmPerPixel * (_fine ? 0.1 : 1)).clamp(minBpm, maxBpm).toDouble();
    final rounded = _fine ? (bpm * 10).round() / 10 : bpm.roundToDouble();
    final beat = i == 0 ? 0.0 : math.max(0.0, _snap(_beat0 + dx / c.pxPerBeat));
    if (!_checkpointed) {
      if (rounded == _bpm0 && beat == _beat0) return;
      c.checkpoint('Mudar andamento');
      _checkpointed = true;
    }
    c.moveTempoPoint(i, beat: beat, bpm: rounded, undoable: false);
  }

  void _panEnd([Object? _]) => _index = null;

  Future<void> _doubleTap() async {
    if (c.recording) return;
    final hit = _hit(_doubleAt);
    if (hit != null) {
      await _typeBpm(hit);
      return;
    }
    final beat = math.max(0.0, _snap(_beatAt(_doubleAt.dx)));
    c.addTempoPoint(beat);
  }

  Future<void> _typeBpm(int index) async {
    final pts = c.doc.tempo.points;
    if (index >= pts.length) return;
    final text = await promptText(
      context,
      title: 'Andamento na batida ${formatBeat(pts[index].beat)}',
      label: 'BPM',
      initial: formatBpm(pts[index].bpm),
      action: 'Salvar',
      maxLength: 6,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
    );
    final v = text == null ? null : parseBpm(text);
    if (v == null || !mounted) return;
    c.moveTempoPoint(index, bpm: v);
  }

  Future<void> _menu(Offset local, Offset global) async {
    if (c.recording) return;
    final hit = _hit(local);
    final size = MediaQuery.sizeOf(context);
    final pts = c.doc.tempo.points;
    final items = <PopupMenuEntry<String>>[
      if (hit != null) ...[
        const PopupMenuItem(value: 'type', child: Text('Digitar BPM…')),
        PopupMenuItem(value: 'ramp', enabled: hit + 1 < pts.length, child: Text(pts[hit].ramp ? 'Salto até o próximo ponto' : 'Rampa até o próximo ponto')),
        PopupMenuItem(value: 'delete', enabled: hit > 0, child: const Text('Apagar o ponto')),
      ] else ...[
        const PopupMenuItem(value: 'add', child: Text('Adicionar ponto aqui')),
        if (pts.length > 1) const PopupMenuItem(value: 'clear', child: Text('Apagar todas as mudanças de andamento')),
      ],
    ];
    final v = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(global.dx, global.dy, size.width - global.dx, size.height - global.dy),
      items: items,
    );
    if (v == null || !mounted) return;
    switch (v) {
      case 'type':
        await _typeBpm(hit!);
      case 'ramp':
        c.setTempoPointRamp(hit!, !pts[hit].ramp);
      case 'delete':
        c.removeTempoPoint(hit!);
      case 'add':
        c.addTempoPoint(math.max(0.0, _snap(_beatAt(local.dx))));
      case 'clear':
        c.setTempoMap(const []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tempo = c.doc.tempo;
    return MouseRegion(
      cursor: SystemMouseCursors.precise,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTapDown: (d) => _doubleAt = d.localPosition,
        onDoubleTap: _doubleTap,
        // o arraste conta desde o toque (não desde que passou da folga): 1 px é 1 px
        dragStartBehavior: DragStartBehavior.down,
        onPanStart: _panStart,
        onPanUpdate: _panUpdate,
        onPanEnd: _panEnd,
        onPanCancel: _panEnd,
        onSecondaryTapUp: (d) => _menu(d.localPosition, d.globalPosition),
        onLongPressStart: (d) => _menu(d.localPosition, d.globalPosition),
        child: Container(
          decoration: const BoxDecoration(
            color: Palette.bar,
            border: Border(bottom: BorderSide(color: Palette.hairline)),
          ),
          child: ClipRect(
            child: CustomPaint(
              painter: _TempoPainter(scroll: c.scrollBeat, ppb: c.pxPerBeat, tempo: tempo, style: Theme.of(context).textTheme.labelSmall!),
              size: Size.infinite,
            ),
          ),
        ),
      ),
    );
  }
}

/// "12", "12,5": batida para o título dos diálogos.
String formatBeat(double beat) => (beat % 1 == 0 ? beat.toStringAsFixed(0) : beat.toStringAsFixed(2)).replaceAll('.', ',');

class _TempoPainter extends CustomPainter {
  final double scroll, ppb;
  final TempoMap tempo;
  final TextStyle style;

  _TempoPainter({required this.scroll, required this.ppb, required this.tempo, required this.style});

  @override
  void paint(Canvas canvas, Size size) {
    final pts = tempo.points;
    var lo = pts.map((p) => p.bpm).reduce(math.min), hi = pts.map((p) => p.bpm).reduce(math.max);
    if (hi - lo < 20) {
      final mid = (hi + lo) / 2;
      lo = mid - 10;
      hi = mid + 10;
    }
    double y(double bpm) => size.height - 5 - (bpm - lo) / (hi - lo) * (size.height - 10);
    double x(double beat) => (beat - scroll) * ppb;
    final line = Paint()
      ..color = Palette.accent.withValues(alpha: pts.length == 1 ? 0.35 : 0.9)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final path = Path()..moveTo(math.min(0, x(0)), y(pts.first.bpm));
    for (var i = 0; i < pts.length; i++) {
      final p = pts[i];
      path.lineTo(x(p.beat), y(p.bpm));
      if (i + 1 < pts.length) {
        final q = pts[i + 1];
        if (p.ramp) {
          path.lineTo(x(q.beat), y(q.bpm));
        } else {
          path.lineTo(x(q.beat), y(p.bpm));
        }
      } else {
        path.lineTo(math.max(size.width, x(p.beat)) + 4, y(p.bpm));
      }
    }
    canvas.drawPath(path, line);
    final dot = Paint()..color = Palette.accent;
    for (final p in pts) {
      final px = x(p.beat);
      if (px < -60 || px > size.width + 4) continue;
      if (pts.length > 1) canvas.drawCircle(Offset(px, y(p.bpm)), 3.5, dot);
      final tp = TextPainter(
        text: TextSpan(
          text: formatBpm(p.bpm),
          style: style.copyWith(color: Colors.white70, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(px + 6, 3));
    }
    if (pts.length == 1) {
      final tp = TextPainter(
        text: TextSpan(
          text: 'Duplo clique adiciona uma mudança de andamento',
          style: style.copyWith(color: Colors.white30, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: math.max(0, size.width - 60));
      tp.paint(canvas, Offset(44, size.height - tp.height - 2));
    }
  }

  @override
  bool shouldRepaint(_TempoPainter o) => o.scroll != scroll || o.ppb != ppb || !identical(o.tempo, tempo);
}

// ---------------------------------------------------------------------- compasso

/// "Mudar compasso a partir do compasso N": escolhe o compasso (1 = o primeiro), a fórmula e aplica;
/// havendo uma mudança exatamente nesse compasso (que não seja a do 1), oferece remover.
Future<void> showMeterChangeDialog(BuildContext context, DawController c, {int? bar}) async {
  final start = bar ?? c.doc.meter.barOf(math.max(0.0, c.beat.value)).$1;
  await showDialog<void>(
    context: context,
    builder: (_) => _MeterDialog(c: c, bar: start),
  );
}

class _MeterDialog extends StatefulWidget {
  final DawController c;
  final int bar;
  const _MeterDialog({required this.c, required this.bar});
  @override
  State<_MeterDialog> createState() => _MeterDialogState();
}

class _MeterDialogState extends State<_MeterDialog> {
  late final _bar = TextEditingController(text: '${widget.bar}')..selection = TextSelection(baseOffset: 0, extentOffset: '${widget.bar}'.length);
  late int _num, _den;
  String? _error;

  @override
  void initState() {
    super.initState();
    final at = widget.c.doc.meter.changeAt(widget.bar);
    _num = at.numerator.clamp(1, 32);
    _den = at.denominator;
  }

  @override
  void dispose() {
    _bar.dispose();
    super.dispose();
  }

  int? get _barValue {
    final v = int.tryParse(_bar.text.trim());
    return v == null || v < 1 || v > 9999 ? null : v;
  }

  void _save() {
    final b = _barValue;
    if (b == null) {
      setState(() => _error = 'Entre 1 e 9999.');
      return;
    }
    widget.c.setMeterAt(b, _num, _den);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final b = _barValue;
    final exists = b != null && b > 1 && widget.c.doc.meter.changes.any((x) => x.bar == b);
    return AlertDialog(
      title: Text('Mudar compasso a partir do compasso ${b ?? ''}'.trim()),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _bar,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(labelText: 'A partir do compasso', errorText: _error),
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _num,
                  decoration: const InputDecoration(labelText: 'Tempos'),
                  items: [for (var i = 1; i <= 32; i++) DropdownMenuItem(value: i, child: Text('$i'))],
                  onChanged: (v) => setState(() => _num = v ?? _num),
                ),
              ),
              const Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('/')),
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _den,
                  decoration: const InputDecoration(labelText: 'Unidade'),
                  items: [for (final d in meterDenominators) DropdownMenuItem(value: d, child: Text('$d'))],
                  onChanged: (v) => setState(() => _den = v ?? _den),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'O compasso muda daí em diante, até a próxima mudança. A batida do projeto é a semínima: 6/8 ocupa 3 batidas.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        if (exists)
          TextButton(
            onPressed: () {
              widget.c.removeMeterChange(b);
              Navigator.pop(context);
            },
            child: const Text('Remover a mudança'),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _save, child: const Text('Aplicar')),
      ],
    );
  }
}
