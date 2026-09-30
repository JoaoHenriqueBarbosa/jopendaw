/// A aba "Passos" do painel de baixo: o sequenciador de passos da bateria e do sampler fatiado.
///
/// É uma visão das mesmas notas do clipe de notas (ver `step_sequencer.dart`): uma linha por peça
/// ou zona, um passo por subdivisão. Clicar liga e desliga; arrastar pinta ou apaga; no toque,
/// arrastar rola a grade e o toque longo (ou o mouse) pinta. Cada gesto é um passo do desfazer.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../widgets/theme.dart';
import 'controller.dart';
import 'instruments.dart';
import 'model.dart';
import 'step_sequencer.dart';

/// Configuração da grade de um clipe; vale enquanto o app está aberto (como a visão do piano roll).
class _Prefs {
  String res = defaultResolutionId;

  /// Compassos do padrão; null: os que cobrem as notas do clipe.
  int? bars;

  /// Swing já aplicado às notas e o que o controle mostra.
  double swing = 0, pending = 0;
  int? selected;
  StepDynamic brush = StepDynamic.normal;
}

const _cellMin = 32.0, _cellMax = 56.0, _rowH = 32.0, _headH = 20.0, _stripH = 64.0;

/// A faixa e o clipe que a aba edita: a faixa selecionada e nela o clipe selecionado, o aberto no
/// editor ou o que está sob o cursor. Clipe null: a faixa não tem um sob o cursor.
({DawTrack track, int index, MidiClip? clip})? stepTarget(DawController c) {
  if (c.selectedTrack < 0 || c.selectedTrack >= c.doc.tracks.length) return null;
  final t = c.doc.tracks[c.selectedTrack];
  if (!stepsAvailable(t)) return null;
  MidiClip? clip;
  for (final id in [c.selectedClip, c.editingClip]) {
    final f = id == null ? null : c.findMidiClip(id);
    if (f != null && identical(f.$1, t)) {
      clip = f.$2;
      break;
    }
  }
  if (clip == null) {
    final at = c.beat.value;
    for (final m in t.midi) {
      if (m.start <= at && at < m.end) clip = m;
    }
  }
  return (track: t, index: c.selectedTrack, clip: clip);
}

class StepSequencerPanel extends StatefulWidget {
  final DawController c;
  const StepSequencerPanel({super.key, required this.c});

  @override
  State<StepSequencerPanel> createState() => _StepSequencerPanelState();
}

class _StepSequencerPanelState extends State<StepSequencerPanel> {
  static final _prefs = <String, _Prefs>{};
  static PatternClipboard? _clipboard;

  final _hScroll = ScrollController();
  final _rnd = math.Random();
  final _timers = <Timer>[];
  final _sounding = <int>{};

  /// Rolagem travada enquanto o toque longo pinta.
  bool _locked = false;
  String? _notice;
  double _viewW = 0, _cellW = _cellMin;

  // gesto em curso
  bool _ckpt = false;
  bool? _painting; // true liga, false apaga
  int? _lastRow, _lastStep;
  Timer? _dblTimer;
  ({int row, int step})? _lastCell;

  DawController get c => widget.c;

  @override
  void initState() {
    super.initState();
    c.beat.addListener(_follow);
  }

  @override
  void didUpdateWidget(StepSequencerPanel old) {
    super.didUpdateWidget(old);
    if (old.c != c) {
      old.c.beat.removeListener(_follow);
      c.beat.addListener(_follow);
    }
  }

  @override
  void dispose() {
    c.beat.removeListener(_follow);
    _dblTimer?.cancel();
    for (final t in _timers) {
      t.cancel();
    }
    for (final p in _sounding.toList()) {
      final tg = stepTarget(c);
      if (tg != null) c.noteOff(p, track: tg.index);
    }
    _hScroll.dispose();
    super.dispose();
  }

  _Prefs _prefsOf(MidiClip clip) => _prefs.putIfAbsent(clip.id, _Prefs.new);

  double _barBeats(MidiClip clip) => c.doc.meter.barBeatsAt(clip.start);

  int _barsOf(MidiClip clip, _Prefs p) {
    final explicit = p.bars;
    if (explicit != null) return explicit.clamp(1, maxPatternBars);
    final bar = _barBeats(clip);
    var extent = 0.0;
    for (final n in clip.notes) {
      extent = math.max(extent, n.start);
    }
    final clipBars = (clip.length / bar - 1e-6).ceil().clamp(1, maxPatternBars);
    return ((extent / bar).floor() + 1).clamp(1, clipBars);
  }

  StepLayout _layout(MidiClip clip, _Prefs p) =>
      StepLayout.of(barBeats: _barBeats(clip), bars: _barsOf(clip, p), step: resolutionById(p.res).beats, swing: p.swing);

  /// Segue o cursor na grade durante a reprodução.
  void _follow() {
    if (!c.playing.value || !_hScroll.hasClients) return;
    final t = stepTarget(c);
    final clip = t?.clip;
    if (t == null || clip == null) return;
    final l = _layout(clip, _prefsOf(clip));
    final rel = c.beat.value - clip.start;
    if (rel < 0 || rel >= clip.length) return;
    final x = (rel % l.span) / l.step * _cellW;
    final pos = _hScroll.position;
    if (x < pos.pixels || x > pos.pixels + pos.viewportDimension - _cellW) {
      pos.jumpTo(x.clamp(0.0, pos.maxScrollExtent).toDouble());
    }
  }

  // ------------------------------------------------------------------------------ edição

  MidiClip? _clipNow(String id) => c.findMidiClip(id)?.$2;

  /// Uma edição de um gesto: o checkpoint sai na primeira mudança, as seguintes só alteram.
  void _gestureEdit(MidiClip clip, void Function(List<MidiNote> notes) fn) {
    if (!_ckpt) {
      c.checkpoint('Sequenciador de passos');
      _ckpt = true;
    }
    c.mutate((_) {
      fn(clip.notes);
      sortNotes(clip.notes);
    });
  }

  /// Uma ação de menu: um passo do desfazer.
  void _run(MidiClip clip, void Function(List<MidiNote> notes) fn, {String? notice}) {
    c.checkpoint('Sequenciador de passos');
    c.mutate((_) {
      fn(clip.notes);
      sortNotes(clip.notes);
    });
    setState(() => _notice = notice);
  }

  void _audition(int track, int pitch, double velocity) {
    if (c.playing.value) return;
    c.noteOn(pitch, velocity: velocity, track: track);
    _sounding.add(pitch);
    late final Timer t;
    t = Timer(const Duration(milliseconds: 220), () {
      _timers.remove(t);
      _sounding.remove(pitch);
      c.noteOff(pitch, track: track);
    });
    _timers.add(t);
  }

  ({int row, int step})? _cellAt(Offset p, int rows, StepLayout l) {
    if (p.dx < 0 || p.dy < 0) return null;
    final r = p.dy ~/ _rowH, s = (p.dx / _cellW).floor();
    if (r >= rows || s >= l.steps) return null;
    return (row: r, step: s);
  }

  bool _beyondClip(MidiClip clip, StepLayout l, int step) => l.pos(step) >= clip.length - stepEps;

  void _gridStart(Offset p, String clipId, List<StepRow> rows, int trackIndex) {
    final clip = _clipNow(clipId);
    if (clip == null) return;
    final pr = _prefsOf(clip);
    final l = _layout(clip, pr);
    _ckpt = false;
    _painting = null;
    _lastRow = _lastStep = null;
    final cell = _cellAt(p, rows.length, l);
    if (cell == null) return;
    // dois toques no mesmo passo dentro de 320 ms: acento
    final dbl = _lastCell == cell && (_dblTimer?.isActive ?? false);
    _dblTimer?.cancel();
    _lastCell = cell;
    _dblTimer = Timer(const Duration(milliseconds: 320), () => _lastCell = null);
    _gridApply(clip, pr, l, rows, cell, trackIndex, doubleTap: dbl, first: true);
  }

  void _gridMove(Offset p, String clipId, List<StepRow> rows, int trackIndex) {
    final clip = _clipNow(clipId);
    if (clip == null || _painting == null) return;
    final pr = _prefsOf(clip);
    final l = _layout(clip, pr);
    final cell = _cellAt(p, rows.length, l);
    if (cell == null) return;
    // o arraste pinta na linha em que começou: não muda de linha no meio
    _gridApply(clip, pr, l, rows, (row: _lastRow ?? cell.row, step: cell.step), trackIndex);
  }

  void _gridApply(
    MidiClip clip,
    _Prefs pr,
    StepLayout l,
    List<StepRow> rows,
    ({int row, int step}) cell,
    int trackIndex, {
    bool doubleTap = false,
    bool first = false,
  }) {
    if (_beyondClip(clip, l, cell.step)) return;
    if (!first && cell.row == _lastRow && cell.step == _lastStep) return;
    final pitch = rows[cell.row].pitch;
    final hit = readRow(clip.notes, pitch, l)[cell.step];
    if (first) {
      _painting = doubleTap || hit == null;
      _lastRow = cell.row;
      if (pr.selected != pitch) setState(() => pr.selected = pitch);
    }
    _lastStep = cell.step;
    final on = _painting!;
    final v = doubleTap ? StepDynamic.accent.velocity : pr.brush.velocity;
    if (on) {
      if (hit == null) {
        _gestureEdit(clip, (n) => addStep(n, pitch, cell.step, l, v));
        _audition(trackIndex, pitch, v);
      } else if (doubleTap) {
        _gestureEdit(clip, (n) => setStepVelocity(n, pitch, cell.step, l, v));
        _audition(trackIndex, pitch, v);
      }
    } else if (hit != null) {
      _gestureEdit(clip, (n) => removeStep(n, pitch, cell.step, l));
    }
  }

  void _gridEnd() {
    _painting = null;
    _ckpt = false;
    if (_locked) setState(() => _locked = false);
  }

  // faixa de velocidade
  void _stripAt(Offset p, String clipId, int pitch) {
    final clip = _clipNow(clipId);
    if (clip == null) return;
    final l = _layout(clip, _prefsOf(clip));
    final s = (p.dx / _cellW).floor();
    if (p.dx < 0 || s < 0 || s >= l.steps) return;
    final v = (1 - p.dy / _stripH).clamp(0.05, 1.0).toDouble();
    final hit = readRow(clip.notes, pitch, l)[s];
    if (hit == null || (hit.velocity - v).abs() < 1e-9) return;
    _gestureEdit(clip, (n) => setStepVelocity(n, pitch, s, l, v));
  }

  void _stripStart(Offset p, String clipId, int pitch) {
    _ckpt = false;
    _stripAt(p, clipId, pitch);
  }

  // ------------------------------------------------------------------------------ ações

  Future<int?> _pickNumber(String title, String label, int min, int max, int initial, {String suffix = ''}) => showDialog<int>(
    context: context,
    builder: (ctx) {
      var v = initial;
      return StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$label: $v$suffix'),
              Slider(
                key: const ValueKey('step-number-slider'),
                value: v.toDouble(),
                min: min.toDouble(),
                max: max.toDouble(),
                divisions: max - min,
                onChanged: (x) => set(() => v = x.round()),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            FilledButton(key: const ValueKey('step-number-ok'), onPressed: () => Navigator.pop(ctx, v), child: const Text('Aplicar')),
          ],
        ),
      );
    },
  );

  Future<void> _presets(MidiClip clip, _Prefs pr) async {
    final p = await showDialog<StepPreset>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Padrões de bateria'),
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 420, maxHeight: MediaQuery.sizeOf(ctx).height * 0.6),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final s in stepPresets)
                    ListTile(
                      key: ValueKey('step-preset-${s.id}'),
                      dense: true,
                      title: Text(s.name),
                      subtitle: Text(s.about),
                      onTap: () => Navigator.pop(ctx, s),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    if (p == null || !mounted) return;
    final now = _clipNow(clip.id);
    if (now == null) return;
    pr.res = p.resolution;
    pr.bars = ((p.span / _barBeats(now)) - 1e-6).ceil().clamp(1, maxPatternBars);
    // o swing aplicado vale para o que o usuário desenhar depois; o padrão de fábrica vem reto
    _run(now, (n) => applyPreset(n, p, clipLength: now.length), notice: 'Padrão "${p.name}" aplicado.');
  }

  Future<void> _menu(String v, MidiClip clip, _Prefs pr, StepLayout l, List<StepRow> rows) async {
    final scope = pr.selected != null ? {pr.selected!} : {for (final r in rows) r.pitch};
    switch (v) {
      case 'clear-row':
        if (pr.selected != null) _run(clip, (n) => clearRows(n, {pr.selected!}, l));
      case 'clear-all':
        _run(clip, (n) => clearRows(n, {for (final r in rows) r.pitch}, l));
      case 'copy':
        _clipboard = copyPattern(clip.notes, scope, l);
        setState(() => _notice = 'Padrão copiado (${_clipboard!.notes.length} notas).');
      case 'paste':
        final cb = _clipboard;
        if (cb != null) _run(clip, (n) => pastePattern(n, scope, l, cb));
      case 'left':
        _run(clip, (n) => shiftRows(n, scope, l, -1));
      case 'right':
        _run(clip, (n) => shiftRows(n, scope, l, 1));
      case 'invert':
        _run(clip, (n) => invertRows(n, scope, l, velocity: pr.brush.velocity));
      case 'random':
        final d = await _pickNumber('Aleatorizar', 'Densidade', 0, 100, 40, suffix: '%');
        final now = _clipNow(clip.id);
        if (d != null && now != null && mounted) _run(now, (n) => randomizeRows(n, scope, l, d.toDouble(), _rnd));
      case 'every':
        final n = await _pickNumber('Preencher a cada N passos', 'A cada', 1, math.max(2, l.steps ~/ 2), l.steps >= 16 ? 4 : 2, suffix: ' passos');
        final now = _clipNow(clip.id);
        if (n != null && now != null && mounted) _run(now, (x) => fillEvery(x, scope, l, n, velocity: pr.brush.velocity));
      case 'repeat':
        var done = 0;
        _run(clip, (n) => done = repeatPattern(n, l, clip.length));
        setState(
          () => _notice = done == 0 ? 'O padrão já ocupa o clipe inteiro.' : 'Padrão repetido até o fim do clipe ($done ${done == 1 ? 'vez' : 'vezes'}).',
        );
    }
  }

  void _swing(MidiClip clip, _Prefs pr, StepLayout l, double to) {
    var moved = 0;
    _run(clip, (n) => moved = retimeSwing(n, l, pr.swing, to));
    setState(() {
      pr.swing = to;
      pr.pending = to;
      _notice = to == 0 ? 'Swing tirado ($moved notas).' : 'Swing de ${(to * 100).round()}% aplicado ($moved notas).';
    });
  }

  void _createClip(int lane) {
    final t = c.doc.tracks[lane];
    final meter = c.doc.meter;
    final at = c.beat.value;
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
    c.createMidiClip(lane, start, length: length);
  }

  // ------------------------------------------------------------------------------ widgets

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      final t = stepTarget(c);
      if (t == null) {
        return _message(
          context,
          Icons.grid_view,
          'Sequenciador de passos',
          'Selecione uma faixa de bateria ou um sampler com zonas (fatias) para desenhar batidas em passos.',
        );
      }
      final clip = t.clip;
      if (clip == null) {
        return _message(
          context,
          Icons.grid_view,
          'Nenhum clipe de notas sob o cursor',
          'A faixa ${t.track.name} não tem um clipe de notas aqui.',
          action: FilledButton.icon(
            key: const ValueKey('step-create'),
            onPressed: () => _createClip(t.index),
            icon: const Icon(Icons.add),
            label: const Text('Criar clipe aqui'),
          ),
        );
      }
      return _body(context, t.track, t.index, clip);
    },
  );

  Widget _message(BuildContext context, IconData icon, String title, String text, {Widget? action}) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 36, color: Colors.white24),
            const SizedBox(height: 12),
            Text(title, textAlign: TextAlign.center, style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            Text(
              text,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.white54),
            ),
            if (action != null) ...[const SizedBox(height: 14), action],
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context, DawTrack t, int trackIndex, MidiClip clip) {
    final pr = _prefsOf(clip);
    final rows = stepRowsOf(t);
    if (pr.selected != null && !rows.any((r) => r.pitch == pr.selected)) pr.selected = null;
    final l = _layout(clip, pr);
    final color = trackColorAt(t.color);
    final narrow = MediaQuery.sizeOf(context).width < 560;
    final labelW = narrow ? 112.0 : 152.0;
    return LayoutBuilder(
      builder: (context, box) {
        _viewW = math.max(0.0, box.maxWidth - labelW);
        _cellW = (l.steps > 0 ? _viewW / l.steps : _cellMin).clamp(_cellMin, _cellMax).toDouble();
        final gridW = l.steps * _cellW;
        final reads = [for (final r in rows) readRow(clip.notes, r.pitch, l)];
        final strip = pr.selected;
        final stripRow = strip == null ? -1 : rows.indexWhere((r) => r.pitch == strip);
        final phys = _locked ? const NeverScrollableScrollPhysics() : null;
        final gridH = rows.length * _rowH;
        final totalH = _headH + gridH + (stripRow >= 0 ? _stripH + 4 : 0);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _toolbar(context, t, clip, pr, l, rows),
            if (_notice != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 2),
                child: Text(
                  _notice!,
                  key: const ValueKey('step-notice'),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Palette.accent),
                ),
              ),
            Expanded(
              child: SingleChildScrollView(
                physics: phys,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: labelW,
                      child: Column(
                        children: [
                          const SizedBox(height: _headH),
                          for (final r in rows) _label(context, r, trackIndex, pr, color, narrow),
                          if (stripRow >= 0)
                            Container(
                              height: _stripH + 4,
                              alignment: Alignment.centerLeft,
                              padding: const EdgeInsets.only(left: 8, top: 4),
                              child: Text(
                                'Velocidade\n${rows[stripRow].name}',
                                style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white54),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: SizedBox(
                        height: totalH,
                        child: SingleChildScrollView(
                          controller: _hScroll,
                          physics: phys,
                          scrollDirection: Axis.horizontal,
                          child: SizedBox(
                            width: gridW,
                            height: totalH,
                            child: Column(
                              children: [
                                CustomPaint(size: Size(gridW, _headH), painter: _HeaderPainter(l, _cellW, _barBeats(clip))),
                                _Surface(
                                  key: const ValueKey('step-grid'),
                                  onLock: (v) => setState(() => _locked = v),
                                  onStart: (p) => _gridStart(p, clip.id, rows, trackIndex),
                                  onUpdate: (p) => _gridMove(p, clip.id, rows, trackIndex),
                                  onEnd: _gridEnd,
                                  child: Stack(
                                    children: [
                                      CustomPaint(
                                        size: Size(gridW, gridH),
                                        painter: _GridPainter(
                                          rows: rows,
                                          reads: reads,
                                          l: l,
                                          cellW: _cellW,
                                          color: color,
                                          clipLength: clip.length,
                                          selected: pr.selected,
                                          barBeats: _barBeats(clip),
                                        ),
                                      ),
                                      Positioned.fill(
                                        child: IgnorePointer(
                                          child: RepaintBoundary(
                                            child: CustomPaint(
                                              painter: _PlayheadPainter(c: c, clip: clip, l: l, cellW: _cellW, color: color),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (stripRow >= 0) ...[
                                  const SizedBox(height: 4),
                                  _Surface(
                                    key: const ValueKey('step-strip'),
                                    onLock: (v) => setState(() => _locked = v),
                                    onStart: (p) => _stripStart(p, clip.id, strip!),
                                    onUpdate: (p) => _stripAt(p, clip.id, strip!),
                                    onEnd: _gridEnd,
                                    child: CustomPaint(size: Size(gridW, _stripH), painter: _StripPainter(reads[stripRow], l, _cellW, color)),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _label(BuildContext context, StepRow r, int trackIndex, _Prefs pr, Color color, bool narrow) {
    final sel = pr.selected == r.pitch;
    final style = Theme.of(context).textTheme.labelMedium!
        .copyWith(color: sel ? Colors.white : Colors.white70, fontWeight: sel ? FontWeight.w700 : FontWeight.w500, fontSize: 11);
    return SizedBox(
      height: _rowH,
      child: Material(
        color: sel ? color.withValues(alpha: 0.16) : Colors.transparent,
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                key: ValueKey('step-row-${r.pitch}'),
                onTap: () => setState(() => pr.selected = sel ? null : r.pitch),
                child: Container(
                  height: _rowH,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
                ),
              ),
            ),
            Tooltip(
              message: 'Ouvir ${r.name}',
              child: InkWell(
                key: ValueKey('step-ear-${r.pitch}'),
                onTap: () => _audition(trackIndex, r.pitch, StepDynamic.normal.velocity),
                child: const SizedBox(
                  width: 32,
                  height: _rowH,
                  child: Icon(Icons.volume_up, size: 16, color: Colors.white54),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toolbar(BuildContext context, DawTrack t, MidiClip clip, _Prefs pr, StepLayout l, List<StepRow> rows) {
    final theme = Theme.of(context);
    final small = theme.textTheme.labelMedium!.copyWith(color: Colors.white70);
    final bars = _barsOf(clip, pr);
    final drums = t.kind == TrackKind.drums;
    final scopeName = pr.selected == null ? 'todas as linhas' : rows.firstWhere((r) => r.pitch == pr.selected).name;
    Widget gap() => const SizedBox(width: 12);
    final items = <Widget>[
      Text('Passo', style: small),
      const SizedBox(width: 6),
      DropdownButton<String>(
        key: const ValueKey('step-res'),
        value: pr.res,
        isDense: true,
        dropdownColor: Palette.overlay,
        style: theme.textTheme.labelLarge,
        underline: const SizedBox.shrink(),
        items: [for (final r in stepResolutions) DropdownMenuItem(value: r.id, child: Text('${r.label} · ${stepsFor(_barBeats(clip), 1, r.beats)}/comp.'))],
        onChanged: (v) => setState(() {
          if (v != null) pr.res = v;
          _notice = null;
        }),
      ),
      gap(),
      Text('Compassos', style: small),
      IconButton(
        key: const ValueKey('step-bars-minus'),
        tooltip: 'Menos um compasso',
        visualDensity: VisualDensity.compact,
        onPressed: bars > 1 ? () => setState(() => pr.bars = bars - 1) : null,
        icon: const Icon(Icons.remove, size: 16),
      ),
      Text('$bars', key: const ValueKey('step-bars'), style: theme.textTheme.labelLarge),
      IconButton(
        key: const ValueKey('step-bars-plus'),
        tooltip: 'Mais um compasso',
        visualDensity: VisualDensity.compact,
        onPressed: bars < maxPatternBars ? () => setState(() => pr.bars = bars + 1) : null,
        icon: const Icon(Icons.add, size: 16),
      ),
      gap(),
      Text('Swing ${(pr.pending * 100).round()}%', style: small),
      SizedBox(
        width: 120,
        child: Slider(
          key: const ValueKey('step-swing'),
          value: pr.pending * 100,
          min: 0,
          max: 75,
          divisions: 75,
          onChanged: (v) => setState(() => pr.pending = v.roundToDouble() / 100),
        ),
      ),
      TextButton(
        key: const ValueKey('step-swing-apply'),
        onPressed: (pr.pending - pr.swing).abs() > 1e-9 ? () => _swing(clip, pr, l, pr.pending) : null,
        child: const Text('Aplicar swing'),
      ),
      TextButton(key: const ValueKey('step-swing-off'), onPressed: pr.swing > 0 ? () => _swing(clip, pr, l, 0) : null, child: const Text('Tirar swing')),
      gap(),
      for (final d in StepDynamic.values)
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: ChoiceChip(
            key: ValueKey('step-brush-${d.name}'),
            label: Text(d.label),
            visualDensity: VisualDensity.compact,
            selected: pr.brush == d,
            onSelected: (_) => setState(() => pr.brush = d),
          ),
        ),
      gap(),
      if (drums)
        TextButton.icon(
          key: const ValueKey('step-presets'),
          onPressed: () => _presets(clip, pr),
          icon: const Icon(Icons.library_music, size: 16),
          label: const Text('Padrões'),
        ),
      PopupMenuButton<String>(
        key: const ValueKey('step-actions'),
        tooltip: 'Ações do padrão',
        color: Palette.overlay,
        onSelected: (v) => _menu(v, clip, pr, l, rows),
        itemBuilder: (_) => [
          PopupMenuItem(enabled: false, height: 28, child: Text('Vale para: $scopeName', style: small)),
          PopupMenuItem(value: 'clear-row', enabled: pr.selected != null, child: const Text('Limpar linha')),
          const PopupMenuItem(value: 'clear-all', child: Text('Limpar tudo')),
          const PopupMenuItem(value: 'copy', child: Text('Copiar padrão')),
          PopupMenuItem(value: 'paste', enabled: _clipboard != null, child: const Text('Colar padrão')),
          const PopupMenuItem(value: 'left', child: Text('Deslocar ←')),
          const PopupMenuItem(value: 'right', child: Text('Deslocar →')),
          const PopupMenuItem(value: 'invert', child: Text('Inverter')),
          const PopupMenuItem(value: 'random', child: Text('Aleatorizar…')),
          const PopupMenuItem(value: 'every', child: Text('Preencher a cada N passos…')),
          const PopupMenuItem(value: 'repeat', child: Text('Repetir até o fim do clipe')),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.more_horiz, size: 18),
              const SizedBox(width: 4),
              Text('Ações', style: theme.textTheme.labelLarge),
            ],
          ),
        ),
      ),
    ];
    const pad = EdgeInsets.symmetric(horizontal: 8, vertical: 4);
    // largo: quebra em linhas; estreito (celular): uma linha que rola na horizontal
    if (MediaQuery.sizeOf(context).width >= 700) {
      return Padding(
        padding: pad,
        child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, runSpacing: 2, children: items),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: pad,
      child: Row(children: items),
    );
  }
}

/// Superfície de gestos: o mouse pinta ao arrastar; no toque, arrastar rola e o toque longo pinta.
/// Um toque curto vale um gesto de um passo. Não entra na arena de gestos (usa ponteiros crus),
/// então a rolagem do pai continua funcionando.
class _Surface extends StatefulWidget {
  final Widget child;
  final void Function(Offset local) onStart, onUpdate;
  final VoidCallback onEnd;
  final void Function(bool locked) onLock;
  const _Surface({super.key, required this.child, required this.onStart, required this.onUpdate, required this.onEnd, required this.onLock});

  @override
  State<_Surface> createState() => _SurfaceState();
}

class _SurfaceState extends State<_Surface> {
  static const _slop = 10.0;
  static const _hold = Duration(milliseconds: 300);
  int? _pointer;
  Offset _down = Offset.zero;
  bool _drawing = false, _moved = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _begin(PointerDownEvent e) {
    if (_pointer != null) return;
    _pointer = e.pointer;
    _down = e.localPosition;
    _moved = false;
    if (e.kind == PointerDeviceKind.touch) {
      _drawing = false;
      _timer = Timer(_hold, () {
        if (_pointer == null || _moved) return;
        _drawing = true;
        widget.onLock(true);
        widget.onStart(_down);
      });
    } else {
      _drawing = true;
      widget.onStart(_down);
    }
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer != _pointer) return;
    if (_drawing) {
      widget.onUpdate(e.localPosition);
    } else if (!_moved && (e.localPosition - _down).distance > _slop) {
      _moved = true;
      _timer?.cancel();
    }
  }

  void _finish(PointerEvent e, {bool cancel = false}) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    _timer?.cancel();
    if (_drawing) {
      _drawing = false;
      widget.onEnd();
    } else if (!_moved && !cancel && e.kind == PointerDeviceKind.touch) {
      // toque curto
      widget.onStart(_down);
      widget.onEnd();
    }
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.opaque,
    onPointerDown: _begin,
    onPointerMove: _move,
    onPointerUp: _finish,
    onPointerCancel: (e) => _finish(e, cancel: true),
    child: widget.child,
  );
}

// ------------------------------------------------------------------------------------ pintura

class _HeaderPainter extends CustomPainter {
  final StepLayout l;
  final double cellW, barBeats;
  _HeaderPainter(this.l, this.cellW, this.barBeats);

  @override
  void paint(Canvas canvas, Size size) {
    final perBeat = l.step >= 1 ? 1.0 : 1 / l.step;
    final line = Paint()..color = Colors.white24;
    for (var i = 0; i < l.steps; i++) {
      final beatPos = i * l.step;
      final isBeat = l.step >= 1 || ((beatPos % 1.0) < 1e-6 || (1.0 - (beatPos % 1.0)) < 1e-6);
      if (!isBeat) continue;
      final beat = beatPos.round();
      final inBar = beat % math.max(1, barBeats.round());
      final tp = TextPainter(
        text: TextSpan(
          text: inBar == 0 ? '${beat ~/ math.max(1, barBeats.round()) + 1}' : '${inBar + 1}',
          style: TextStyle(fontSize: 10, color: inBar == 0 ? Colors.white : Colors.white38, fontWeight: inBar == 0 ? FontWeight.w700 : FontWeight.w400),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(i * cellW + 4, (size.height - tp.height) / 2));
      canvas.drawLine(Offset(i * cellW, size.height - 5), Offset(i * cellW, size.height), line);
    }
    // perBeat só para deixar a intenção clara: um número por tempo
    assert(perBeat > 0);
  }

  @override
  bool shouldRepaint(_HeaderPainter o) => o.l.step != l.step || o.l.steps != l.steps || o.cellW != cellW || o.barBeats != barBeats;
}

class _GridPainter extends CustomPainter {
  final List<StepRow> rows;
  final List<Map<int, StepHit>> reads;
  final StepLayout l;
  final double cellW, clipLength, barBeats;
  final Color color;
  final int? selected;
  _GridPainter({
    required this.rows,
    required this.reads,
    required this.l,
    required this.cellW,
    required this.color,
    required this.clipLength,
    required this.selected,
    required this.barBeats,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint();
    final beatsPerCell = l.step;
    for (var r = 0; r < rows.length; r++) {
      final y = r * _rowH;
      fill.color = rows[r].pitch == selected ? color.withValues(alpha: 0.10) : (r.isEven ? const Color(0xFF171A20) : const Color(0xFF14171C));
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, _rowH), fill);
    }
    for (var i = 0; i < l.steps; i++) {
      final x = i * cellW;
      final beat = (i * beatsPerCell).floor();
      if (beat.isOdd) {
        fill.color = const Color(0x0DFFFFFF);
        canvas.drawRect(Rect.fromLTWH(x, 0, cellW, size.height), fill);
      }
      if (l.pos(i) >= clipLength - stepEps) {
        fill.color = const Color(0x99000000);
        canvas.drawRect(Rect.fromLTWH(x, 0, cellW, size.height), fill);
      }
    }
    final grid = Paint()..strokeWidth = 1;
    final bar = math.max(1, barBeats.round());
    for (var i = 0; i <= l.steps; i++) {
      final beatPos = i * l.step;
      final onBeat = (beatPos % 1.0) < 1e-6 || (1.0 - beatPos % 1.0) < 1e-6;
      final onBar = onBeat && beatPos.round() % bar == 0;
      grid.color = onBar ? Colors.white30 : (onBeat ? Colors.white12 : const Color(0x0AFFFFFF));
      canvas.drawLine(Offset(i * cellW, 0), Offset(i * cellW, size.height), grid);
    }
    for (var r = 0; r <= rows.length; r++) {
      canvas.drawLine(Offset(0, r * _rowH), Offset(size.width, r * _rowH), grid..color = const Color(0x14FFFFFF));
    }
    final off = Paint()..color = const Color(0xFF22262E);
    final dot = Paint()..color = const Color(0xFFE3B341);
    for (var r = 0; r < rows.length; r++) {
      for (var i = 0; i < l.steps; i++) {
        final rect = Rect.fromLTWH(i * cellW + 2, r * _rowH + 3, cellW - 4, _rowH - 6);
        final hit = reads[r][i];
        if (hit == null) {
          canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(4)), off);
          continue;
        }
        final v = hit.velocity.clamp(0.0, 1.0);
        final kind = dynamicOf(v);
        // a altura do preenchimento é a velocidade; o acento ganha um filete claro
        canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(4)), off);
        final h = rect.height * (0.3 + 0.7 * v);
        final bar = Rect.fromLTWH(rect.left, rect.bottom - h, rect.width, h);
        fill.color = color.withValues(alpha: kind == StepDynamic.ghost ? 0.45 : 0.95);
        canvas.drawRRect(RRect.fromRectAndRadius(bar, const Radius.circular(4)), fill);
        if (kind == StepDynamic.accent) {
          fill.color = Colors.white;
          canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(rect.left + 3, rect.top + 2, rect.width - 6, 3), const Radius.circular(2)), fill);
        }
        if (hit.offGrid) {
          // fora da grade: contorno tracejado curto e um ponto âmbar
          final stroke = Paint()
            ..color = const Color(0xFFE3B341)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5;
          canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(4)), stroke);
          canvas.drawCircle(Offset(rect.right - 5, rect.top + 5), 2.5, dot);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_GridPainter o) => true;
}

class _StripPainter extends CustomPainter {
  final Map<int, StepHit> row;
  final StepLayout l;
  final double cellW;
  final Color color;
  _StripPainter(this.row, this.l, this.cellW, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF101318));
    final grid = Paint()..color = const Color(0x14FFFFFF);
    for (var i = 0; i <= l.steps; i++) {
      canvas.drawLine(Offset(i * cellW, 0), Offset(i * cellW, size.height), grid);
    }
    final p = Paint();
    for (final e in row.entries) {
      final v = e.value.velocity.clamp(0.0, 1.0);
      final h = math.max(2.0, (size.height - 2) * v);
      p.color = color.withValues(alpha: 0.4 + 0.6 * v);
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(e.key * cellW + 4, size.height - h, cellW - 8, h), const Radius.circular(3)), p);
    }
  }

  @override
  bool shouldRepaint(_StripPainter o) => true;
}

class _PlayheadPainter extends CustomPainter {
  final DawController c;
  final MidiClip clip;
  final StepLayout l;
  final double cellW;
  final Color color;
  _PlayheadPainter({required this.c, required this.clip, required this.l, required this.cellW, required this.color})
    : super(repaint: Listenable.merge([c.beat, c.playing]));

  @override
  void paint(Canvas canvas, Size size) {
    if (!c.playing.value) return;
    final rel = c.beat.value - clip.start;
    if (rel < 0 || rel >= clip.length || l.span <= 0) return;
    final r = rel % l.span;
    var i = (r / l.step).floor().clamp(0, l.steps - 1);
    if (i.isOdd && r < l.pos(i)) i--;
    canvas.drawRect(Rect.fromLTWH(i * cellW, 0, cellW, size.height), Paint()..color = Colors.white.withValues(alpha: 0.10));
    final x = r / l.step * cellW;
    canvas.drawLine(
      Offset(x, 0),
      Offset(x, size.height),
      Paint()
        ..color = Colors.white
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_PlayheadPainter o) => o.clip != clip || o.l.steps != l.steps || o.l.step != l.step || o.cellW != cellW;
}
