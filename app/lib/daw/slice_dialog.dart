/// Diálogo "Fatiar sample…": corta um áudio do projeto (um loop de bateria, por exemplo) em partes
/// por transientes ou em N fatias iguais, mostra os cortes sobre a forma de onda e cria uma zona
/// por fatia no sampler, uma nota cada a partir de C1, cada uma tocando só o seu trecho.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../widgets/feedback.dart';
import 'controller.dart';
import 'sampler_zones.dart';
import 'sampler_zones_controller.dart';
import 'instruments.dart' show noteName;

Future<void> showSliceDialog(BuildContext context, DawController c, int track) => showDialog<void>(
  context: context,
  builder: (_) => SliceDialog(c: c, track: track),
);

class SliceDialog extends StatefulWidget {
  final DawController c;
  final int track;
  const SliceDialog({super.key, required this.c, required this.track});

  @override
  State<SliceDialog> createState() => _SliceDialogState();
}

class _SliceDialogState extends State<SliceDialog> {
  String? _sample;
  bool _transients = true;
  double _sensitivity = 0.5;
  int _count = 8;
  List<double>? _points;

  /// Por transientes o cálculo devolve todos os ataques achados (até aqui), não só os [maxSlices] que viram
  /// nota: assim o diálogo pode dizer quantos passaram do limite.
  static const _foundLimit = 100000;

  DawController get c => widget.c;

  @override
  void initState() {
    super.initState();
    final t = c.doc.tracks[widget.track];
    final candidates = [?t.sample, for (final z in t.zones) z.sample, ...c.doc.samples.keys];
    _sample = candidates.where(c.doc.samples.containsKey).firstOrNull;
    _recompute();
  }

  void _recompute() {
    final s = _sample;
    _points = s == null ? null : c.slicePreview(s, count: _transients ? null : _count, sensitivity: _sensitivity, limit: _foundLimit);
  }

  Future<void> _create() async {
    final s = _sample, p = _points;
    if (s == null || p == null) return;
    final n = c.createSlices(widget.track, s, p);
    if (!mounted) return;
    if (n == 0) {
      setState(() {});
      return;
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final samples = c.doc.samples.entries.toList()..sort((a, b) => a.value.name.toLowerCase().compareTo(b.value.name.toLowerCase()));
    final small = Theme.of(context).textTheme.labelSmall!.copyWith(color: Colors.white54, letterSpacing: 0.6);
    final wave = _sample == null ? null : c.waveforms[_sample!];
    final audio = _sample == null ? null : c.decodedAudio(_sample!);
    final points = _points;
    final zones = c.zonesOf(widget.track);
    final n = points == null ? 0 : math.min(points.length, math.min(maxSlices, 128 - firstSliceNote));
    return AlertDialog(
      title: const Text('Fatiar sample'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (samples.isEmpty)
                const Text('Nenhum áudio no projeto ainda. Importe um arquivo (pelo cartão Áudio ou pelo botão de adicionar zona) e volte aqui.')
              else ...[
                Text('ÁUDIO', style: small),
                const SizedBox(height: 4),
                DropdownButton<String>(
                  value: _sample,
                  isExpanded: true,
                  items: [
                    for (final e in samples)
                      DropdownMenuItem(
                        value: e.key,
                        child: Text(e.value.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) => setState(() {
                    _sample = v;
                    _recompute();
                  }),
                ),
                const SizedBox(height: 10),
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: true, label: Text('Por transientes'), icon: Icon(Icons.graphic_eq, size: 16)),
                    ButtonSegment(value: false, label: Text('N fatias iguais'), icon: Icon(Icons.view_week_outlined, size: 16)),
                  ],
                  selected: {_transients},
                  onSelectionChanged: (s) => setState(() {
                    _transients = s.first;
                    _recompute();
                  }),
                ),
                const SizedBox(height: 8),
                if (_transients)
                  Row(
                    children: [
                      const Text('Sensibilidade', style: TextStyle(fontSize: 12)),
                      Expanded(
                        child: Slider(
                          value: _sensitivity,
                          onChanged: (v) => setState(() => _sensitivity = v),
                          // o cálculo passa pelo áudio inteiro: só refaz quando o dedo solta
                          onChangeEnd: (_) => setState(_recompute),
                        ),
                      ),
                      Text('${(_sensitivity * 100).round()}%', style: const TextStyle(fontSize: 12)),
                    ],
                  )
                else
                  Row(
                    children: [
                      const Text('Fatias', style: TextStyle(fontSize: 12)),
                      IconButton(
                        tooltip: 'Menos uma fatia',
                        onPressed: _count > 2
                            ? () => setState(() {
                                _count--;
                                _recompute();
                              })
                            : null,
                        icon: const Icon(Icons.remove),
                      ),
                      SizedBox(
                        width: 32,
                        child: Text(
                          '$_count',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Mais uma fatia',
                        onPressed: _count < maxSlices
                            ? () => setState(() {
                                _count++;
                                _recompute();
                              })
                            : null,
                        icon: const Icon(Icons.add),
                      ),
                      const Spacer(),
                      for (final k in const [4, 8, 16, 32])
                        Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: ChoiceChip(
                            label: Text('$k'),
                            visualDensity: VisualDensity.compact,
                            selected: _count == k,
                            onSelected: (_) => setState(() {
                              _count = k;
                              _recompute();
                            }),
                          ),
                        ),
                    ],
                  ),
                const SizedBox(height: 8),
                if (wave == null || audio == null)
                  const InlineNotice('Este áudio não está neste aparelho. Importe o arquivo de novo para fatiá-lo.')
                else ...[
                  SizedBox(
                    height: 96,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: CustomPaint(
                        size: Size.infinite,
                        painter: _SlicePainter(wave, audio.duration, points ?? const [], n, Theme.of(context).colorScheme.primary),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    n == 0
                        ? 'Nenhum corte achado: tente mais sensibilidade ou fatias iguais.'
                        : points!.length == 1 && _transients
                        ? 'Nenhum transiente achado: uma fatia só. Tente mais sensibilidade ou fatias iguais.'
                        : '$n ${n == 1 ? 'fatia' : 'fatias'}: ${noteName(firstSliceNote)} a ${noteName(firstSliceNote + n - 1)}, uma nota cada, tocando até o fim de cada trecho.',
                    style: const TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                  if (points != null && points.length > n)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${points.length} fatias achadas; só as $n primeiras viram nota.',
                              style: const TextStyle(fontSize: 12, color: Colors.amberAccent),
                            ),
                          ),
                          TextButton(
                            onPressed: _sensitivity > 0
                                ? () => setState(() {
                                    _sensitivity = math.max(0, _sensitivity - 0.15);
                                    _recompute();
                                  })
                                : null,
                            child: const Text('Menos sensibilidade'),
                          ),
                        ],
                      ),
                    ),
                  if (zones.isNotEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text('Criar substitui as zonas atuais desta faixa (dá para desfazer).', style: TextStyle(fontSize: 12, color: Colors.white54)),
                    ),
                ],
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: points == null || n == 0 || _sample == null ? null : _create, child: const Text('Criar')),
      ],
    );
  }
}

/// A forma de onda com os cortes: uma linha em cada início de fatia, numerada.
class _SlicePainter extends CustomPainter {
  final Waveform wave;
  final double duration;
  final List<double> points;

  /// Quantos pontos viram nota: os seguintes aparecem apagados.
  final int used;
  final Color color;
  _SlicePainter(this.wave, this.duration, this.points, this.used, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF15171C));
    final n = wave.mins.length;
    if (n == 0 || size.width <= 0 || duration <= 0) return;
    var peak = 0.0;
    for (var i = 0; i < n; i++) {
      peak = math.max(peak, math.max(-wave.mins[i], wave.maxs[i]));
    }
    final mid = size.height / 2;
    final amp = (size.height / 2 - 12) / (peak > 1e-4 ? peak : 1);
    final paint = Paint()..color = Colors.white54;
    final cols = size.width.floor();
    for (var px = 0; px < cols; px++) {
      final a = (px * n / cols).floor();
      final b = math.max(a + 1, ((px + 1) * n / cols).floor());
      var lo = 0.0, hi = 0.0;
      for (var i = a; i < b && i < n; i++) {
        if (wave.mins[i] < lo) lo = wave.mins[i];
        if (wave.maxs[i] > hi) hi = wave.maxs[i];
      }
      canvas.drawLine(Offset(px + 0.5, mid - hi * amp), Offset(px + 0.5, mid - lo * amp + 0.5), paint);
    }
    final line = Paint()
      ..color = color
      ..strokeWidth = 1.5;
    final unused = Paint()
      ..color = Colors.white24
      ..strokeWidth = 1;
    for (var i = 0; i < points.length; i++) {
      final x = (points[i] / duration).clamp(0.0, 1.0) * size.width;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), i < used ? line : unused);
      if (i >= used) continue;
      final tp = TextPainter(
        text: TextSpan(
          text: '${i + 1}',
          style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: color),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      if (x + 3 + tp.width < size.width) tp.paint(canvas, Offset(x + 3, 1));
    }
  }

  @override
  bool shouldRepaint(_SlicePainter o) => o.points != points || o.used != used || o.wave != wave || o.color != color;
}
