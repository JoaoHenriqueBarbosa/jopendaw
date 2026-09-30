/// Telas do submenu "Editar áudio" do clipe de áudio: dividir por transientes, remover silêncio,
/// normalizar e quantizar por fatias (a lógica está em `audio_edit.dart`). Cada diálogo mostra a
/// forma de onda do trecho do clipe com a prévia do que vai acontecer, aplica numa edição só (um
/// passo do desfazer) e, no fim, diz o que fez. Feitos para caber em 360 px de largura.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../widgets/feedback.dart';
import 'audio_edit.dart';
import 'clip_gain_dialog.dart' show formatClipGainDb;
import 'controller.dart';
import 'keymap.dart' show shortcutHint;
import 'model.dart';

/// O submenu com as quatro ações, aberto em [at] (o ponto do toque ou do clique direito).
Future<void> showEditAudioMenu(BuildContext context, DawController c, String clipId, Offset at) async {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final v = await showMenu<String>(
    context: context,
    position: RelativeRect.fromLTRB(at.dx, at.dy, overlay.size.width - at.dx, overlay.size.height - at.dy),
    items: const [
      PopupMenuItem(value: 'split', child: _MenuRow(Icons.call_split, 'Dividir por transientes…')),
      PopupMenuItem(value: 'strip', child: _MenuRow(Icons.content_cut, 'Remover silêncio…')),
      PopupMenuItem(value: 'normalize', child: _MenuRow(Icons.equalizer, 'Normalizar clipe…')),
      PopupMenuItem(value: 'quantize', child: _MenuRow(Icons.grid_on, 'Quantizar por fatias…')),
    ],
  );
  if (v == null || !context.mounted) return;
  switch (v) {
    case 'split':
      await showSplitTransientsDialog(context, c, clipId);
    case 'strip':
      await showStripSilenceDialog(context, c, clipId);
    case 'normalize':
      await showNormalizeClipDialog(context, c, clipId);
    case 'quantize':
      await showQuantizeSlicesDialog(context, c, clipId);
  }
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MenuRow(this.icon, this.label);

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 18),
      const SizedBox(width: 12),
      Expanded(child: Text(label)),
    ],
  );
}

Future<void> showSplitTransientsDialog(BuildContext context, DawController c, String clipId) => showDialog<void>(
  context: context,
  builder: (_) => SplitTransientsDialog(c: c, clipId: clipId),
);

Future<void> showStripSilenceDialog(BuildContext context, DawController c, String clipId) => showDialog<void>(
  context: context,
  builder: (_) => StripSilenceDialog(c: c, clipId: clipId),
);

Future<void> showNormalizeClipDialog(BuildContext context, DawController c, String clipId) => showDialog<void>(
  context: context,
  builder: (_) => NormalizeClipDialog(c: c, clipId: clipId),
);

Future<void> showQuantizeSlicesDialog(BuildContext context, DawController c, String clipId) => showDialog<void>(
  context: context,
  builder: (_) => QuantizeSlicesDialog(c: c, clipId: clipId),
);

// ------------------------------------------------------------------------- peças comuns

/// O casco de todos os diálogos: título, conteúdo rolável e ações; depois de aplicar mostra só o
/// resultado e "Fechar".
class _EditShell extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final String? done;
  final VoidCallback? onApply;
  final String applyLabel;
  const _EditShell({required this.title, required this.children, required this.done, required this.onApply, this.applyLabel = 'Aplicar'});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      title: Text(title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: done != null
                ? [
                    InlineNotice(done!, error: false),
                    const SizedBox(height: 8),
                    Text('Dá para desfazer numa vez só${shortcutHint('edit.undo')}.', style: const TextStyle(fontSize: 12, color: Colors.white54)),
                  ]
                : children,
          ),
        ),
      ),
      actions: done != null
          ? [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fechar'))]
          : [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')), FilledButton(onPressed: onApply, child: Text(applyLabel))],
    );
  }
}

/// Rótulo, valor e slider em duas linhas: cabe em 360 px.
class _SliderRow extends StatelessWidget {
  final String label, value;
  final double v, min, max;
  final int? divisions;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;
  final Key? sliderKey;
  const _SliderRow({
    required this.label,
    required this.value,
    required this.v,
    required this.min,
    required this.max,
    required this.onChanged,
    this.onChangeEnd,
    this.divisions,
    this.sliderKey,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 12))),
          Text(value, style: const TextStyle(fontSize: 12, color: Colors.white70)),
        ],
      ),
      SizedBox(
        height: 32,
        child: Slider(key: sliderKey, value: v.clamp(min, max), min: min, max: max, divisions: divisions, onChanged: onChanged, onChangeEnd: onChangeEnd),
      ),
    ],
  );
}

/// Escolha de uma opção entre poucas (chips que quebram de linha).
class _Choice<T> extends StatelessWidget {
  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;
  const _Choice({required this.options, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 6,
    runSpacing: 0,
    children: [
      for (final (v, label) in options)
        ChoiceChip(label: Text(label), visualDensity: VisualDensity.compact, selected: v == value, onSelected: (_) => onChanged(v)),
    ],
  );
}

String _ms(double s) => '${(s * 1000).round()} ms';
String _pt(double v, [int digits = 1]) => v.toStringAsFixed(digits).replaceAll('.', ',').replaceFirst('-', '−');

/// O que o diálogo sabe do clipe ao abrir: ele, o trecho e o motivo de não dar para editar.
class _Subject {
  final AudioClip? clip;
  final ClipRange? range;
  final String? error;
  const _Subject(this.clip, this.range, this.error);

  factory _Subject.of(DawController c, String id, {bool needSlices = true}) {
    final t = c.audioEditTarget(id, needSlices: needSlices);
    return _Subject(t.clip, t.range, t.error);
  }
}

/// A forma de onda do trecho do clipe com a prévia por cima: linhas de corte numeradas, trechos
/// removidos apagados e, na quantização, cada fatia com uma seta até o lugar novo. Tudo em segundos
/// do sample (os de [ClipPreview.clip]).
class ClipPreview extends StatelessWidget {
  final DawController c;
  final AudioClip clip;
  final List<double> cuts;
  final List<(double, double)> removed;
  final List<(double, double)> moves;
  const ClipPreview({super.key, required this.c, required this.clip, this.cuts = const [], this.removed = const [], this.moves = const []});

  @override
  Widget build(BuildContext context) {
    final wave = c.waveforms[clip.sample];
    if (wave == null) return const SizedBox(height: 96);
    return SizedBox(
      height: moves.isEmpty ? 96 : 112,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: CustomPaint(
          size: Size.infinite,
          painter: _PreviewPainter(wave, clip.offset, clip.length, cuts, removed, moves, Theme.of(context).colorScheme.primary),
        ),
      ),
    );
  }
}

class _PreviewPainter extends CustomPainter {
  final Waveform wave;
  final double from, length;
  final List<double> cuts;
  final List<(double, double)> removed, moves;
  final Color color;
  _PreviewPainter(this.wave, this.from, this.length, this.cuts, this.removed, this.moves, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF15171C));
    final n = wave.mins.length;
    if (n == 0 || size.width <= 0 || length <= 0) return;
    final strip = moves.isEmpty ? 0.0 : 16.0;
    final h = size.height - strip;
    double x(double sec) => ((sec - from) / length).clamp(0.0, 1.0) * size.width;
    final per = wave.perSecond;
    final b0 = (from * per).floor().clamp(0, n - 1);
    final b1 = math.max(b0 + 1, ((from + length) * per).ceil()).clamp(0, n);
    final span = b1 - b0;
    var peak = 0.0;
    for (var i = b0; i < b1; i++) {
      peak = math.max(peak, math.max(-wave.mins[i], wave.maxs[i]));
    }
    final mid = h / 2;
    final amp = (h / 2 - 8) / (peak > 1e-4 ? peak : 1);
    final paint = Paint()..color = Colors.white60;
    final cols = size.width.floor();
    for (var px = 0; px < cols; px++) {
      final a = b0 + (px * span / cols).floor();
      final b = math.max(a + 1, b0 + ((px + 1) * span / cols).floor());
      var lo = 0.0, hi = 0.0;
      for (var i = a; i < b && i < b1; i++) {
        if (wave.mins[i] < lo) lo = wave.mins[i];
        if (wave.maxs[i] > hi) hi = wave.maxs[i];
      }
      canvas.drawLine(Offset(px + 0.5, mid - hi * amp), Offset(px + 0.5, mid - lo * amp + 0.5), paint);
    }
    for (final (a, b) in removed) {
      canvas.drawRect(Rect.fromLTRB(x(a), 0, math.max(x(b), x(a) + 1), h), Paint()..color = const Color(0xB0000000));
    }
    final line = Paint()
      ..color = color
      ..strokeWidth = 1.5;
    for (var i = 0; i < cuts.length; i++) {
      final px = x(cuts[i]);
      canvas.drawLine(Offset(px, 0), Offset(px, h), line);
      if (cuts.length > 60) continue;
      final tp = TextPainter(
        text: TextSpan(
          text: '${i + 1}',
          style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: color),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      if (px + 3 + tp.width < size.width) tp.paint(canvas, Offset(px + 3, 1));
    }
    if (moves.isNotEmpty) {
      final base = h + strip / 2;
      canvas.drawLine(Offset(0, base), Offset(size.width, base), Paint()..color = Colors.white12);
      final arrow = Paint()
        ..color = Colors.amberAccent
        ..strokeWidth = 1.5;
      for (final (a, b) in moves) {
        final xa = x(a), xb = x(b);
        canvas.drawLine(Offset(xa, base), Offset(xb, base), arrow);
        canvas.drawCircle(Offset(xb, base), 2.5, arrow);
        canvas.drawLine(Offset(xa, base - 4), Offset(xa, base + 4), Paint()..color = Colors.white54);
      }
    }
  }

  @override
  bool shouldRepaint(_PreviewPainter o) => o.cuts != cuts || o.removed != removed || o.moves != moves || o.wave != wave || o.from != from || o.length != length;
}

// ------------------------------------------------------------------------- dividir

class SplitTransientsDialog extends StatefulWidget {
  final DawController c;
  final String clipId;
  const SplitTransientsDialog({super.key, required this.c, required this.clipId});

  @override
  State<SplitTransientsDialog> createState() => _SplitState();
}

class _SplitState extends State<SplitTransientsDialog> {
  late final _Subject _s = _Subject.of(widget.c, widget.clipId);
  CutMode _mode = CutMode.transients;
  double _sensitivity = 0.5;
  int _count = 8;
  late EditGrid _grid = EditGrid.fromSnap(widget.c.snap);
  double _minGap = 0.05;
  List<double> _cuts = const [];
  String? _done, _error;

  @override
  void initState() {
    super.initState();
    _recompute();
  }

  void _recompute() {
    final s = _s;
    _cuts = s.error != null
        ? const []
        // a distância mínima é do detector de transientes: fatias iguais e grade cortam onde foi pedido
        : detectCuts(
            s.range!,
            s.clip!,
            widget.c.doc,
            mode: _mode,
            sensitivity: _sensitivity,
            count: _count,
            grid: _grid,
            minGap: _mode == CutMode.transients ? _minGap : 0,
          );
  }

  void _set(VoidCallback f) => setState(() {
    f();
    _recompute();
  });

  void _apply() {
    final r = widget.c.splitClipAt(widget.clipId, _cuts);
    setState(() {
      if (r.ok) {
        _done = r.message;
      } else {
        _error = r.message;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    final n = _cuts.length + 1;
    return _EditShell(
      title: 'Dividir por transientes',
      done: _done,
      onApply: s.error == null && _cuts.isNotEmpty && n <= maxEditPieces ? _apply : null,
      applyLabel: 'Dividir',
      children: [
        if (s.error != null)
          InlineNotice(s.error!)
        else ...[
          _Choice<CutMode>(options: [for (final m in CutMode.values) (m, m.label)], value: _mode, onChanged: (m) => _set(() => _mode = m)),
          const SizedBox(height: 8),
          if (_mode == CutMode.transients) ...[
            _SliderRow(
              label: 'Sensibilidade',
              value: '${(_sensitivity * 100).round()}%',
              v: _sensitivity,
              min: 0,
              max: 1,
              sliderKey: const Key('split-sensitivity'),
              onChanged: (v) => setState(() => _sensitivity = v),
              // o cálculo passa pelo áudio inteiro: só refaz quando o dedo solta
              onChangeEnd: (_) => setState(_recompute),
            ),
            _SliderRow(
              label: 'Distância mínima entre cortes',
              value: _ms(_minGap),
              v: _minGap,
              min: 0.01,
              max: 0.5,
              sliderKey: const Key('split-mingap'),
              onChanged: (v) => setState(() => _minGap = v),
              onChangeEnd: (_) => setState(_recompute),
            ),
          ] else if (_mode == CutMode.equal)
            Row(
              children: [
                const Text('Fatias', style: TextStyle(fontSize: 12)),
                IconButton(tooltip: 'Menos uma fatia', onPressed: _count > 2 ? () => _set(() => _count--) : null, icon: const Icon(Icons.remove)),
                SizedBox(
                  width: 32,
                  child: Text(
                    '$_count',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(tooltip: 'Mais uma fatia', onPressed: _count < 96 ? () => _set(() => _count++) : null, icon: const Icon(Icons.add)),
              ],
            )
          else
            _Choice<EditGrid>(options: [for (final g in EditGrid.values) (g, g.label)], value: _grid, onChanged: (g) => _set(() => _grid = g)),
          const SizedBox(height: 8),
          ClipPreview(c: widget.c, clip: s.clip!, cuts: _cuts),
          const SizedBox(height: 6),
          Text(
            _cuts.isEmpty
                ? (_mode == CutMode.transients
                      ? 'Nenhum transiente achado: tente mais sensibilidade, fatias iguais ou a grade.'
                      : 'Nenhum corte cai dentro do clipe.')
                : n > maxEditPieces
                ? 'Fatias demais ($n; o máximo é $maxEditPieces). ${_mode == CutMode.transients ? 'Diminua a sensibilidade.' : _mode == CutMode.equal ? 'Use menos fatias.' : 'Use uma grade maior.'}'
                : '$n fatias, com emendas de 2 ms que não mudam o som.',
            style: const TextStyle(fontSize: 12, color: Colors.white70),
          ),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: InlineNotice(_error!)),
        ],
      ],
    );
  }
}

// ------------------------------------------------------------------------- remover silêncio

class StripSilenceDialog extends StatefulWidget {
  final DawController c;
  final String clipId;
  const StripSilenceDialog({super.key, required this.c, required this.clipId});

  @override
  State<StripSilenceDialog> createState() => _StripState();
}

class _StripState extends State<StripSilenceDialog> {
  late final _Subject _s = _Subject.of(widget.c, widget.clipId);
  double _threshold = -45, _minSilence = 0.1, _before = 0.01, _after = 0.02, _fade = 0.005;
  SilencePlan? _plan;
  String? _done, _error;

  SilenceSettings get _settings => SilenceSettings(thresholdDb: _threshold, minSilence: _minSilence, guardBefore: _before, guardAfter: _after, fade: _fade);

  @override
  void initState() {
    super.initState();
    _recompute();
  }

  void _recompute() {
    final s = _s;
    _plan = s.error != null ? null : planSilence(s.range!, _settings);
  }

  void _apply() {
    final r = widget.c.stripClipSilence(widget.clipId, _settings);
    setState(() {
      if (r.ok) {
        _done = r.message;
      } else {
        _error = r.message;
      }
    });
  }

  Widget _slider(String key, String label, String value, double v, double min, double max, ValueChanged<double> set) => _SliderRow(
    label: label,
    value: value,
    v: v,
    min: min,
    max: max,
    sliderKey: Key(key),
    onChanged: (x) => setState(() => set(x)),
    onChangeEnd: (_) => setState(_recompute),
  );

  @override
  Widget build(BuildContext context) {
    final s = _s;
    final plan = _plan;
    final ok = plan != null && !plan.allSilent && plan.removed.isNotEmpty && plan.kept.length <= maxEditPieces;
    return _EditShell(
      title: 'Remover silêncio',
      done: _done,
      onApply: ok ? _apply : null,
      applyLabel: 'Remover',
      children: [
        if (s.error != null)
          InlineNotice(s.error!)
        else ...[
          _slider('strip-threshold', 'Limiar', '${_pt(_threshold, 0)} dBFS', _threshold, -80, -10, (v) => _threshold = v.roundToDouble()),
          _slider('strip-min', 'Silêncio mínimo', _ms(_minSilence), _minSilence, 0.01, 2, (v) => _minSilence = v),
          _slider('strip-before', 'Margem antes do som', _ms(_before), _before, 0, 0.3, (v) => _before = v),
          _slider('strip-after', 'Margem depois do som', _ms(_after), _after, 0, 0.3, (v) => _after = v),
          _slider('strip-fade', 'Fade nos cortes', _ms(_fade), _fade, 0, 0.05, (v) => _fade = v),
          const SizedBox(height: 4),
          ClipPreview(c: widget.c, clip: s.clip!, removed: plan?.removed ?? const []),
          const SizedBox(height: 6),
          Text(
            plan == null
                ? ''
                : plan.allSilent
                ? 'O clipe todo está abaixo do limiar: nada seria mantido.'
                : plan.removed.isEmpty
                ? 'Nenhum silêncio com esses ajustes.'
                : plan.kept.length > maxEditPieces
                ? 'Trechos demais (${plan.kept.length}; o máximo é $maxEditPieces). Aumente o silêncio mínimo.'
                : '${silenceSummary(plan)} (a parte apagada da onda). A lacuna fica: o resto do clipe não se move.',
            style: const TextStyle(fontSize: 12, color: Colors.white70),
          ),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: InlineNotice(_error!)),
        ],
      ],
    );
  }
}

// ------------------------------------------------------------------------- normalizar

class NormalizeClipDialog extends StatefulWidget {
  final DawController c;
  final String clipId;
  const NormalizeClipDialog({super.key, required this.c, required this.clipId});

  @override
  State<NormalizeClipDialog> createState() => _NormalizeState();
}

class _NormalizeState extends State<NormalizeClipDialog> {
  // a normalização é só ganho: vale também para clipe com warp ou inversão
  late final _Subject _s = _Subject.of(widget.c, widget.clipId, needSlices: false);
  NormalizeMode _mode = NormalizeMode.peak;
  double _target = NormalizeMode.peak.defaultTarget;
  final _measures = <NormalizeMode, NormalizeMeasure>{};
  final _errors = <NormalizeMode, String>{};
  bool _measuring = false;
  String? _done, _error;

  @override
  void initState() {
    super.initState();
    _measure();
  }

  Future<void> _measure() async {
    final s = _s;
    if (s.error != null || _measures.containsKey(_mode) || _errors.containsKey(_mode)) return;
    final mode = _mode;
    setState(() => _measuring = true);
    final r = await measureForNormalize(s.range!, mode);
    if (!mounted) return;
    setState(() {
      _measuring = false;
      if (r.measure != null) {
        _measures[mode] = r.measure!;
      } else {
        _errors[mode] = r.error!;
      }
    });
  }

  NormalizePlan? get _plan {
    final m = _measures[_mode];
    return m == null ? null : normalizePlanFor(_mode, _target, m);
  }

  Future<void> _apply() async {
    final r = await widget.c.normalizeClip(widget.clipId, _mode, _target, measured: _measures[_mode]);
    if (!mounted) return;
    setState(() {
      if (r.ok) {
        _done = r.message;
      } else {
        _error = r.message;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    final plan = _plan;
    final err = _errors[_mode];
    final current = s.clip?.gain ?? 1;
    final (lo, hi) = _mode == NormalizeMode.peak ? (-24.0, 0.0) : (-40.0, 0.0);
    return _EditShell(
      title: 'Normalizar clipe',
      done: _done,
      onApply: plan != null && !_measuring ? _apply : null,
      applyLabel: 'Normalizar',
      children: [
        if (s.error != null)
          InlineNotice(s.error!)
        else ...[
          _Choice<NormalizeMode>(
            options: [for (final m in NormalizeMode.values) (m, m.label)],
            value: _mode,
            onChanged: (m) {
              setState(() {
                _mode = m;
                _target = m.defaultTarget;
                _error = null;
              });
              _measure();
            },
          ),
          const SizedBox(height: 8),
          _SliderRow(
            label: 'Alvo',
            value: '${_pt(_target)} ${_mode.unit}',
            v: _target,
            min: lo,
            max: hi,
            divisions: ((hi - lo) * 2).round(),
            sliderKey: const Key('normalize-target'),
            onChanged: (v) => setState(() => _target = v),
          ),
          if (_measuring) const LinearProgressIndicator(),
          if (err != null) InlineNotice(err),
          if (plan != null) ...[
            Text('Medido: ${_pt(plan.measuredDb)} ${_mode.unit} (pico ${_pt(plan.peakDb)} dBFS)', style: const TextStyle(fontSize: 12, color: Colors.white70)),
            const SizedBox(height: 4),
            Text(
              'Ganho do clipe: ${formatClipGainDb(plan.gain)} (agora ${formatClipGainDb(current)})',
              key: const Key('normalize-gain'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            if (plan.limited)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: InlineNotice('Limitado porque ${plan.limitReason}: o alvo não será atingido.', error: false),
              ),
          ],
          const SizedBox(height: 6),
          const Text('Mede o trecho que o clipe toca e ajusta só o ganho dele; o áudio não é alterado.', style: TextStyle(fontSize: 12, color: Colors.white54)),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: InlineNotice(_error!)),
        ],
      ],
    );
  }
}

// ------------------------------------------------------------------------- quantizar

class QuantizeSlicesDialog extends StatefulWidget {
  final DawController c;
  final String clipId;
  const QuantizeSlicesDialog({super.key, required this.c, required this.clipId});

  @override
  State<QuantizeSlicesDialog> createState() => _QuantizeState();
}

class _QuantizeState extends State<QuantizeSlicesDialog> {
  late final _Subject _s = _Subject.of(widget.c, widget.clipId);
  late EditGrid _grid = EditGrid.fromSnap(widget.c.snap);
  double _strength = 1, _sensitivity = 0.5;
  bool _keepTogether = false;
  QuantizePlan? _plan;
  String? _done, _error;

  QuantizeSettings get _settings => QuantizeSettings(grid: _grid, strength: _strength, sensitivity: _sensitivity, keepTogether: _keepTogether);

  @override
  void initState() {
    super.initState();
    _recompute();
  }

  void _recompute() {
    final s = _s;
    _plan = s.error != null ? null : planQuantize(s.range!, s.clip!, widget.c.doc, _settings);
  }

  void _set(VoidCallback f) => setState(() {
    f();
    _recompute();
  });

  void _apply() {
    final r = widget.c.quantizeClipSlices(widget.clipId, _settings);
    setState(() {
      if (r.ok) {
        _done = r.message;
      } else {
        _error = r.message;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    final plan = _plan;
    final ok = plan != null && plan.slices.length >= 2 && plan.slices.length <= maxEditPieces;
    final clip = s.clip;
    // setas: do começo da fatia ao lugar novo, em segundos do sample (o clipe toca em tempo real)
    final t0 = clip == null ? 0.0 : widget.c.doc.secondsAt(clip.start);
    final moves = <(double, double)>[
      if (plan != null && clip != null && plan.slices.length <= 96)
        for (var i = 0; i < plan.slices.length; i++)
          if (plan.shiftsMs[i].abs() >= 0.5) (plan.slices[i].srcStart, clip.offset + (plan.slices[i].atSec - t0)),
    ];
    return _EditShell(
      title: 'Quantizar por fatias',
      done: _done,
      onApply: ok ? _apply : null,
      applyLabel: 'Quantizar',
      children: [
        if (s.error != null)
          InlineNotice(s.error!)
        else ...[
          const Text('Grade', style: TextStyle(fontSize: 12)),
          _Choice<EditGrid>(options: [for (final g in EditGrid.values) (g, g.label)], value: _grid, onChanged: (g) => _set(() => _grid = g)),
          const SizedBox(height: 4),
          _SliderRow(
            label: 'Força',
            value: '${(_strength * 100).round()}%',
            v: _strength,
            min: 0,
            max: 1,
            divisions: 20,
            sliderKey: const Key('quantize-strength'),
            onChanged: (v) => _set(() => _strength = v),
          ),
          _SliderRow(
            label: 'Sensibilidade dos transientes',
            value: '${(_sensitivity * 100).round()}%',
            v: _sensitivity,
            min: 0,
            max: 1,
            sliderKey: const Key('quantize-sensitivity'),
            onChanged: (v) => setState(() => _sensitivity = v),
            onChangeEnd: (_) => setState(_recompute),
          ),
          SwitchListTile(
            key: const Key('quantize-keep'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Manter as fatias juntas', style: TextStyle(fontSize: 13)),
            subtitle: const Text(
              'Corta seco a fatia que a seguinte cobre, sem deixar rabo por baixo. Lacunas ficam em silêncio: o áudio nunca é esticado.',
              style: TextStyle(fontSize: 11.5),
            ),
            value: _keepTogether,
            onChanged: (v) => setState(() => _keepTogether = v),
          ),
          if (clip != null)
            ClipPreview(c: widget.c, clip: clip, cuts: [for (final sl in plan?.slices.skip(1) ?? const <SliceSpec>[]) sl.srcStart], moves: moves),
          const SizedBox(height: 6),
          Text(
            plan == null || plan.slices.length < 2
                ? 'Nenhum transiente achado: não há o que quantizar. Aumente a sensibilidade.'
                : plan.slices.length > maxEditPieces
                ? 'Fatias demais (${plan.slices.length}; o máximo é $maxEditPieces). Diminua a sensibilidade.'
                : '${plan.slices.length} fatias, ${plan.moved} ${plan.moved == 1 ? 'movida' : 'movidas'} (até ${_pt(plan.maxShiftMs)} ms). As setas mostram para onde cada uma vai.',
            style: const TextStyle(fontSize: 12, color: Colors.white70),
          ),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: InlineNotice(_error!)),
        ],
      ],
    );
  }
}
