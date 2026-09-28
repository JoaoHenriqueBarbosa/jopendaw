/// Editor de notas (piano roll) do clipe MIDI aberto em `c.editing`.
///
/// Grade, notas, teclado e faixa de velocidade são pintados por CustomPainters, com o hit-test
/// feito à mão: um widget por nota não aguentaria os milhares de notas de um arranjo de verdade.
/// A visão (zoom e rolagem) é do editor e fica guardada por clipe enquanto o app está aberto;
/// posições e grade contam do início do clipe, como no modelo. Toda edição passa pelo histórico
/// do controlador, e um gesto só faz checkpoint quando muda algo de fato.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/dialogs.dart';
import '../widgets/responsive_scaffold.dart';
import '../widgets/theme.dart';
import 'controller.dart';
import 'instruments.dart';
import 'model.dart';

part 'piano_roll_input.dart';
part 'piano_roll_paint.dart';
part 'piano_roll_view.dart';

class PianoRoll extends StatefulWidget {
  final DawController c;
  const PianoRoll({super.key, required this.c});

  @override
  State<PianoRoll> createState() => _PianoRollState();
}

class _PianoRollState extends State<PianoRoll> {
  DawController get c => widget.c;

  // o clipe aberto, resolvido a cada build (desfazer troca o documento inteiro)
  DawTrack? _track;
  MidiClip? _clip;
  int _trackIndex = -1;

  _View? _view;
  bool _needsFit = false;
  _Rows? _rows;

  /// Linhas congeladas durante um gesto: uma nota saindo de uma altura solta da bateria não pode
  /// fazer a grade pular debaixo do dedo.
  _Rows? _frozenRows;
  _Dims _dims = const _Dims(coarse: false, drums: false);
  Size _gridSize = Size.zero;

  final _sel = <MidiNote>{};
  MidiNote? _hover;

  /// A nota que o último clique criou: o segundo clique de um duplo não a apaga.
  MidiNote? _justCreated;
  MouseCursor _cursor = MouseCursor.defer;
  MouseCursor _rulerCursor = SystemMouseCursors.click;

  /// O editor recebe as teclas de edição enquanto foi o último lugar clicado.
  bool _active = true;

  _Drag? _drag;
  _Pinch? _pinch;
  final _touches = <int, Offset>{};
  Timer? _autoTimer;
  final _gridClicks = _Clicks();
  final _keyClicks = _Clicks();
  String? _label;
  (double, int?)? _labelAt;

  /// Notas soando na prévia (o teclado acende as mesmas).
  final _sounding = <int>{};
  final _blips = <Timer>{};
  int? _keyPointer, _keyPitch;
  double? _pasteBase, _pasteNext;
  double _panScale = 1;

  @override
  void initState() {
    super.initState();
    c.editorKeyHandler = _onKey;
    c.beat.addListener(_onBeat);
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onGlobalPointer);
    // o clique direito apaga notas: quem desliga o menu do navegador é a tela do projeto, pelo
    // tempo em que ela está aberta (ligar de volta ao fechar o editor estragaria o menu dos clipes)
  }

  @override
  void didUpdateWidget(PianoRoll old) {
    super.didUpdateWidget(old);
    if (identical(old.c, widget.c)) return;
    if (old.c.editorKeyHandler == _onKey) old.c.editorKeyHandler = null;
    old.c.beat.removeListener(_onBeat);
    widget.c.editorKeyHandler = _onKey;
    widget.c.beat.addListener(_onBeat);
    for (final p in _sounding) {
      old.c.noteOff(p, track: _trackIndex);
    }
    _sounding.clear();
    if (_clip != null) _leaveClip();
    _clip = null;
  }

  @override
  void dispose() {
    if (c.editorKeyHandler == _onKey) c.editorKeyHandler = null;
    c.beat.removeListener(_onBeat);
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onGlobalPointer);
    _autoTimer?.cancel();
    _drag?.longPress?.cancel();
    for (final t in _blips) {
      t.cancel();
    }
    _silenceAll();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  /// A fonte do tema para os textos pintados à mão (a mesma do resto da tela).
  TextStyle _font(BuildContext context) => Theme.of(context).textTheme.labelSmall ?? const TextStyle();

  void _activate() {
    if (_active) return;
    _active = true;
    _refresh();
  }

  bool _onKey(KeyEvent e) => _handleKey(e);

  /// Um clique fora do editor devolve as teclas de edição (Delete, Ctrl+D…) ao arranjo.
  void _onGlobalPointer(PointerEvent e) {
    if (e is! PointerDownEvent || !mounted) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final inside = (Offset.zero & box.size).contains(box.globalToLocal(e.position));
    if (inside == _active) return;
    _active = inside;
    _refresh();
  }

  /// Tocando dentro do clipe, a janela acompanha o cursor quando ele sai dela.
  void _onBeat() {
    final clip = _clip, v = _view;
    if (clip == null || v == null || !c.follow || !c.playing.value || _drag != null || _pinch != null || _gridSize.width <= 0) return;
    final rel = c.beat.value - clip.start;
    if (rel < 0 || rel > clip.length) return;
    final visible = _gridSize.width / v.ppb;
    if (rel > v.scrollX + visible * .95 || rel < v.scrollX) {
      v.scrollX = rel - visible * .05;
      _clampView();
      _refresh();
    }
  }

  // ------------------------------------------------------------------ clipe aberto

  void _resolve() {
    final e = c.editing;
    if (e == null) {
      if (_clip != null) _leaveClip();
      _track = null;
      _clip = null;
      _trackIndex = -1;
      return;
    }
    final (track, clip) = e;
    if (clip.id != _clip?.id) {
      if (_clip != null) _leaveClip();
      _view = _Prefs.views[clip.id];
      _needsFit = _view == null;
    } else if (!identical(clip, _clip)) {
      // o documento foi trocado inteiro (desfazer, refazer): as notas agora são outros objetos
      _remapSelection(_clip!, clip);
      _dropGesture();
    }
    _track = track;
    _clip = clip;
    _trackIndex = c.doc.tracks.indexOf(track);
  }

  void _leaveClip() {
    _dropGesture();
    _sel.clear();
    _hover = null;
    _justCreated = null;
    _pasteBase = null;
    _rows = null;
  }

  /// Larga o gesto em andamento sem mexer no documento (roda no build: nada de notificar).
  void _dropGesture() {
    _drag?.longPress?.cancel();
    _drag = null;
    _frozenRows = null;
    _label = null;
    _autoTimer?.cancel();
    _autoTimer = null;
    if (_sounding.isNotEmpty) WidgetsBinding.instance.addPostFrameCallback((_) => _silenceAll());
  }

  /// Desfazer um movimento ou uma transposição mantém a ordem das notas: a seleção segue pelos
  /// índices. Se a contagem mudou, não há como saber quem é quem.
  void _remapSelection(MidiClip old, MidiClip now) {
    _hover = null;
    _justCreated = null;
    if (_sel.isEmpty) return;
    if (old.notes.length != now.notes.length) {
      _sel.clear();
      return;
    }
    final index = {for (var i = 0; i < old.notes.length; i++) old.notes[i]: i};
    final keep = [
      for (final n in _sel)
        if (index[n] case final i?) now.notes[i],
    ];
    _sel
      ..clear()
      ..addAll(keep);
  }

  _Rows _rowsFor(MidiClip clip, bool drums) {
    final prev = _rows;
    if (drums) {
      final extra = <int>{
        for (final n in clip.notes)
          if (!_drumPitches.contains(n.pitch)) n.pitch,
      };
      if (prev != null && prev.drums && prev.length == _drumPitches.length + extra.length && extra.every((p) => prev.rowOf(p) != null)) return prev;
      return _Rows.kit(extra);
    }
    var lo = 12, hi = 108;
    for (final n in clip.notes) {
      if (n.pitch < lo) lo = n.pitch;
      if (n.pitch > hi) hi = n.pitch;
    }
    if (prev != null && !prev.drums && prev.pitches.first == hi && prev.pitches.last == lo) return prev;
    return _Rows.melodic(lo, hi);
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      _resolve();
      final platform = defaultTargetPlatform;
      final coarse = !isDesktop(context) || platform == TargetPlatform.android || platform == TargetPlatform.iOS;
      return LayoutBuilder(
        builder: (context, box) {
          // num Expanded o editor ocupa o que deram; solto numa coluna, tem altura própria e uma
          // alça para puxar
          final bounded = box.hasBoundedHeight;
          final screen = MediaQuery.sizeOf(context).height;
          final maxH = math.max(220.0, screen * .85);
          final height = bounded ? box.maxHeight : (_Prefs.panelHeight ??= coarse ? screen * .62 : 380).clamp(200.0, maxH);
          final bodyH = math.max(0.0, height - (bounded ? 0 : _Dims.handle));
          final body = _clip == null ? _empty(context) : _editor(context, box.maxWidth, bodyH, coarse);
          return Container(
            height: bounded ? null : height,
            color: Palette.bar,
            child: Column(
              children: [
                if (!bounded) _resizeHandle(maxH),
                Expanded(child: ClipRect(child: body)),
              ],
            ),
          );
        },
      );
    },
  );

  Widget _resizeHandle(double maxH) => MouseRegion(
    cursor: SystemMouseCursors.resizeRow,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: (d) {
        _Prefs.panelHeight = ((_Prefs.panelHeight ?? 380) - d.delta.dy).clamp(200.0, maxH);
        _refresh();
      },
      child: Container(
        height: _Dims.handle,
        decoration: const BoxDecoration(
          color: Palette.bar,
          border: Border(top: BorderSide(color: Palette.hairlineStrong)),
        ),
        alignment: Alignment.center,
        child: Container(width: 36, height: 2, color: Colors.white24),
      ),
    ),
  );

  Widget _empty(BuildContext context) {
    final theme = Theme.of(context);
    return Stack(
      children: [
        Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.piano, size: 36, color: Colors.white24),
                const SizedBox(height: 12),
                Text('Nenhum clipe de notas aberto', style: theme.textTheme.titleSmall),
                const SizedBox(height: 6),
                Text(
                  'Dê dois cliques num clipe MIDI de uma faixa de instrumento para editar as notas dele aqui.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.white54),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: IconButton(tooltip: 'Fechar o editor', onPressed: () => c.setDock(Dock.none), icon: const Icon(Icons.close)),
        ),
      ],
    );
  }

  Widget _editor(BuildContext context, double width, double height, bool coarse) {
    final t = _track!, clip = _clip!;
    final drums = t.kind == TrackKind.drums;
    final d = _dims = _Dims(coarse: coarse, drums: drums);
    final v = _view ??= _Prefs.views[clip.id] = _View(ppb: 64, rowH: d.row);
    final prev = _rows;
    final rows = _rows = _frozenRows ?? _rowsFor(clip, drums);
    if (prev != null && !identical(prev, rows)) {
      // linhas entraram ou saíram (nota colada fora de C0..C8, altura solta na bateria): a
      // altura que estava no alto da tela continua lá
      final top = (v.scrollY / v.rowH).floor();
      final pitch = prev.pitchAt(top);
      final now = pitch == null ? null : rows.rowOf(pitch);
      if (now != null) v.scrollY += (now - top) * v.rowH;
    }
    _gridSize = Size(math.max(0.0, width - d.keys), math.max(0.0, height - _Dims.toolbar - d.ruler - (_Prefs.velocityLane ? d.velocity : 0)));
    if (_needsFit && _gridSize.width > 0 && _gridSize.height > 0) {
      _needsFit = false;
      _fit(open: true);
    }
    _clampView();
    final g = _Geo(v, rows);
    final color = trackColorAt(t.color);
    final colors = _velocityColors(color);
    return Column(
      children: [
        _toolbar(context, t, clip, color),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: d.keys,
                child: Column(
                  children: [
                    _corner(context, d),
                    Expanded(child: _keyboard(g, drums, color)),
                    if (_Prefs.velocityLane) _velocityCorner(context, d),
                  ],
                ),
              ),
              Expanded(
                child: Stack(
                  children: [
                    Column(
                      children: [
                        SizedBox(height: d.ruler, child: _ruler(g, clip, color)),
                        Expanded(
                          child: Semantics(
                            label: 'Grade de notas de ${clip.name.isEmpty ? 'Clipe MIDI' : clip.name}: ${clip.notes.length} notas',
                            child: _gridArea(g, clip, colors, color, drums),
                          ),
                        ),
                        if (_Prefs.velocityLane) SizedBox(height: d.velocity, child: _velocityLane(g, clip, colors)),
                      ],
                    ),
                    Positioned.fill(
                      child: IgnorePointer(
                        child: RepaintBoundary(
                          child: CustomPaint(
                            painter: _PlayheadPainter(beat: c.beat, clipStart: clip.start, scrollX: v.scrollX, ppb: v.ppb, ruler: d.ruler),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------------ barra

  Widget _toolbar(BuildContext context, DawTrack t, MidiClip clip, Color color) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall!.copyWith(color: Colors.white54);
    final count = clip.notes.length;
    final info = _sel.isEmpty ? '$count ${count == 1 ? 'nota' : 'notas'}' : '${_sel.length} de $count ${_sel.length == 1 ? 'selecionada' : 'selecionadas'}';
    final length = _lengths[_Prefs.length];
    final target = _sel.isNotEmpty ? 'a seleção' : 'todas as notas';
    return Container(
      height: _Dims.toolbar,
      decoration: BoxDecoration(
        color: Palette.bar,
        border: Border(
          top: BorderSide(color: _active ? Palette.accent.withValues(alpha: .55) : Palette.hairlineStrong),
          bottom: const BorderSide(color: Palette.hairline),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                children: [
                  Tooltip(
                    message: 'Renomear o clipe',
                    child: InkWell(
                      onTap: () => _rename(clip),
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
                            ),
                            const SizedBox(width: 8),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 180),
                              child: Text(
                                clip.name.isEmpty ? 'Clipe MIDI' : clip.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelLarge,
                              ),
                            ),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 140),
                              child: Text(' · ${t.name}', maxLines: 1, overflow: TextOverflow.ellipsis, style: muted),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const _Divider(),
                  _ToolToggle(
                    icon: Icons.edit,
                    on: _Prefs.tool == _Tool.draw,
                    tooltip: 'Lápis: clique numa área vazia cria nota, arraste define a duração',
                    onTap: () => _setTool(_Tool.draw),
                  ),
                  _ToolToggle(
                    icon: Icons.highlight_alt,
                    on: _Prefs.tool == _Tool.select,
                    tooltip: 'Seleção: arraste numa área vazia seleciona; dois cliques criam nota',
                    onTap: () => _setTool(_Tool.select),
                  ),
                  const _Divider(),
                  PopupMenuButton<_Grid>(
                    tooltip: 'Grade do editor (Alt ao arrastar desliga)',
                    initialValue: _Prefs.grid,
                    onSelected: (g) {
                      _Prefs.grid = g;
                      _active = true;
                      _refresh();
                    },
                    itemBuilder: (_) => [for (final g in _Grid.values) CheckedPopupMenuItem(value: g, checked: g == _Prefs.grid, child: Text(g.label))],
                    child: _MenuLabel(icon: Icons.grid_on, text: _Prefs.grid.label),
                  ),
                  PopupMenuButton<int>(
                    tooltip: 'Duração da nota nova',
                    initialValue: _Prefs.length,
                    onSelected: (i) {
                      _Prefs.length = i;
                      _active = true;
                      _refresh();
                    },
                    itemBuilder: (_) => [
                      for (var i = 0; i < _lengths.length; i++)
                        CheckedPopupMenuItem(
                          value: i,
                          checked: i == _Prefs.length,
                          child: Text(i == 1 ? '${_lengths[i].label} (${_formatLength(_Prefs.lastLength)})' : _lengths[i].label),
                        ),
                    ],
                    child: _MenuLabel(icon: Icons.straighten, text: 'Nota: ${length.short}'),
                  ),
                  Tooltip(
                    message:
                        'Quantizar $target na grade (Q) · força ${(_Prefs.strength * 100).round()}%'
                        '${_Prefs.ends ? ' · durações também' : ''}',
                    child: TextButton.icon(
                      onPressed: count == 0 ? null : _quantize,
                      icon: const Icon(Icons.align_horizontal_left, size: 18),
                      label: const Text('Quantizar'),
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Opções da quantização',
                    icon: const Icon(Icons.arrow_drop_down),
                    padding: EdgeInsets.zero,
                    onSelected: (v) {
                      if (v == 'ends') {
                        _Prefs.ends = !_Prefs.ends;
                      } else {
                        _Prefs.strength = double.parse(v);
                      }
                      _active = true;
                      _refresh();
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(enabled: false, height: 32, child: Text('Força')),
                      for (final s in const [1.0, .75, .5, .25])
                        CheckedPopupMenuItem(value: '$s', checked: _Prefs.strength == s, child: Text('${(s * 100).round()}%')),
                      const PopupMenuDivider(),
                      CheckedPopupMenuItem(value: 'ends', checked: _Prefs.ends, child: const Text('Quantizar as durações também')),
                    ],
                  ),
                  const _Divider(),
                  _ToolToggle(
                    icon: Icons.bar_chart,
                    on: _Prefs.velocityLane,
                    tooltip: _Prefs.velocityLane ? 'Ocultar a faixa de velocidade' : 'Mostrar a faixa de velocidade',
                    onTap: () {
                      _Prefs.velocityLane = !_Prefs.velocityLane;
                      _refresh();
                    },
                  ),
                  _ToolToggle(
                    icon: _Prefs.preview ? Icons.volume_up : Icons.volume_off,
                    on: _Prefs.preview,
                    tooltip: _Prefs.preview ? 'Não tocar as notas ao editar' : 'Tocar as notas ao editar',
                    onTap: () {
                      _Prefs.preview = !_Prefs.preview;
                      if (!_Prefs.preview) _silenceAll();
                      _refresh();
                    },
                  ),
                  IconButton(
                    tooltip: 'Enquadrar as notas',
                    onPressed: () {
                      _fit();
                      _refresh();
                    },
                    icon: const Icon(Icons.fit_screen),
                  ),
                  const Tooltip(
                    message: _help,
                    triggerMode: TooltipTriggerMode.tap,
                    showDuration: Duration(seconds: 12),
                    child: Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(Icons.help_outline, size: 20, color: Colors.white54),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(info, style: muted.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                ],
              ),
            ),
          ),
          IconButton(tooltip: 'Fechar o editor', onPressed: () => c.setDock(Dock.none), icon: const Icon(Icons.close)),
        ],
      ),
    );
  }

  static const _help =
      'Clique numa área vazia cria uma nota; arraste para definir a duração.\n'
      'Arraste a nota para mover (Alt: sem grade; Alt no começo do arraste: duplica).\n'
      'Bordas da nota redimensionam. Clique direito, dois cliques ou Delete apagam.\n'
      'Shift ou Ctrl + arrastar seleciona por retângulo; Shift + clique acumula.\n'
      'Ctrl+A tudo · Ctrl+C/X/V copia, recorta e cola no cursor · Ctrl+D duplica.\n'
      'Setas ↑↓ transpõem (Shift: oitava) · ←→ movem pela grade (Shift: compasso) · Q quantiza.\n'
      'Dois cliques numa tecla selecionam as notas dela.\n'
      'Ctrl + roda: zoom na horizontal · Alt + roda: altura das linhas (Cmd no lugar de Ctrl no Mac).\n'
      'No toque: toque longo apaga a nota (ou começa a seleção), dois dedos rolam e dão zoom.';

  void _setTool(_Tool t) {
    _Prefs.tool = t;
    _refresh();
  }

  Future<void> _rename(MidiClip clip) async {
    final name = await promptText(context, title: 'Nome do clipe', label: 'Nome', initial: clip.name, action: 'Salvar', maxLength: 60);
    if (name == null || !mounted) return;
    // o documento pode ter sido trocado enquanto o diálogo estava aberto
    final found = c.findMidiClip(clip.id);
    if (found == null) return;
    c.edit((_) => found.$2.name = name.trim());
    _active = true;
  }

  // ------------------------------------------------------------------ áreas

  Widget _corner(BuildContext context, _Dims d) => Container(
    height: d.ruler,
    decoration: const BoxDecoration(
      color: Palette.bar,
      border: Border(
        right: BorderSide(color: Palette.hairlineStrong),
        bottom: BorderSide(color: Palette.hairline),
      ),
    ),
    alignment: Alignment.center,
    child: Text(d.drums ? 'Peças' : 'Notas', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white54)),
  );

  Widget _velocityCorner(BuildContext context, _Dims d) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white54);
    final one = _sel.length == 1 ? _sel.first : null;
    return Container(
      height: d.velocity,
      decoration: const BoxDecoration(
        color: Palette.canvas,
        border: Border(
          top: BorderSide(color: Palette.hairlineStrong),
          right: BorderSide(color: Palette.hairlineStrong),
        ),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(d.keys >= 90 ? 'Velocidade' : 'Vel.', style: style, maxLines: 1, overflow: TextOverflow.fade, softWrap: false),
          if (one != null)
            Text(
              '${(one.velocity * 127).round()}',
              style: style?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
            ),
        ],
      ),
    );
  }

  Widget _keyboard(_Geo g, bool drums, Color color) => Listener(
    behavior: HitTestBehavior.opaque,
    onPointerDown: _keysDown,
    onPointerMove: _keysMove,
    onPointerUp: _keysUp,
    onPointerCancel: _keysUp,
    onPointerSignal: (e) => _onSignal(e, _Area.keys),
    onPointerPanZoomStart: _panZoomStart,
    onPointerPanZoomUpdate: (e) => _panZoomUpdate(e, _Area.keys),
    child: MouseRegion(
      cursor: SystemMouseCursors.click,
      child: ClipRect(
        child: CustomPaint(
          size: Size.infinite,
          painter: _KeysPainter(g: g, drums: drums, pressed: {..._sounding}, accent: color, font: _font(context)),
        ),
      ),
    ),
  );

  Widget _ruler(_Geo g, MidiClip clip, Color color) => Listener(
    behavior: HitTestBehavior.opaque,
    onPointerDown: _rulerDown,
    onPointerMove: _rulerMove,
    onPointerUp: (e) => _release(e, cancelled: false),
    onPointerCancel: (e) => _release(e, cancelled: true),
    onPointerSignal: (e) => _onSignal(e, _Area.ruler),
    onPointerPanZoomStart: _panZoomStart,
    onPointerPanZoomUpdate: (e) => _panZoomUpdate(e, _Area.ruler),
    child: MouseRegion(
      cursor: _rulerCursor,
      onHover: _rulerHover,
      child: ClipRect(
        child: CustomPaint(
          size: Size.infinite,
          painter: _RulerPainter(
            g: g,
            bpb: c.doc.beatsPerBar,
            clipStart: clip.start,
            clipLength: clip.length,
            step: _Prefs.grid.beats,
            accent: color,
            font: _font(context),
          ),
        ),
      ),
    ),
  );

  Widget _gridArea(_Geo g, MidiClip clip, List<Color> colors, Color color, bool drums) {
    final v = _view!;
    final (lo, hi) = _xRange();
    final d = _drag;
    final bar = _dims.coarse ? 14.0 : 10.0;
    return Stack(
      children: [
        Positioned.fill(
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _gridDown,
            onPointerMove: _gridMove,
            onPointerUp: (e) => _release(e, cancelled: false),
            onPointerCancel: (e) => _release(e, cancelled: true),
            onPointerSignal: (e) => _onSignal(e, _Area.grid),
            onPointerPanZoomStart: _panZoomStart,
            onPointerPanZoomUpdate: (e) => _panZoomUpdate(e, _Area.grid),
            child: MouseRegion(
              cursor: _cursor,
              onHover: _gridHover,
              onExit: (_) => _clearHover(),
              child: ClipRect(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: RepaintBoundary(
                        child: CustomPaint(
                          painter: _GridPainter(g: g, drums: drums, bpb: c.doc.beatsPerBar, step: _Prefs.grid.beats),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: RepaintBoundary(
                        child: CustomPaint(
                          painter: _NotesPainter(
                            g: g,
                            notes: clip.notes,
                            sel: _sel,
                            hover: _hover,
                            colors: colors,
                            accent: color,
                            clipLength: clip.length,
                            drums: drums,
                            marquee: d?.op == _Op.rect ? d!.marquee : null,
                            label: _label,
                            labelAt: _labelAt,
                            font: _font(context),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          right: 0,
          top: 0,
          bottom: bar,
          width: bar,
          child: _Scrollbar(
            axis: Axis.vertical,
            viewport: _gridSize.height,
            content: g.rows.length * v.rowH,
            position: v.scrollY,
            onChanged: (p) {
              v.scrollY = p;
              _clampView();
              _refresh();
            },
          ),
        ),
        Positioned(
          left: 0,
          right: bar,
          bottom: 0,
          height: bar,
          child: _Scrollbar(
            axis: Axis.horizontal,
            viewport: _gridSize.width / v.ppb,
            content: hi - lo,
            position: v.scrollX - lo,
            onChanged: (p) {
              v.scrollX = lo + p;
              _clampView();
              _refresh();
            },
          ),
        ),
      ],
    );
  }

  Widget _velocityLane(_Geo g, MidiClip clip, List<Color> colors) {
    final d = _drag;
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _velDown,
      onPointerMove: _velMove,
      onPointerUp: (e) => _release(e, cancelled: false),
      onPointerCancel: (e) => _release(e, cancelled: true),
      onPointerSignal: (e) => _onSignal(e, _Area.velocity),
      onPointerPanZoomStart: _panZoomStart,
      onPointerPanZoomUpdate: (e) => _panZoomUpdate(e, _Area.velocity),
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeUpDown,
        child: ClipRect(
          child: CustomPaint(
            size: Size.infinite,
            painter: _VelocityPainter(
              g: g,
              notes: clip.notes,
              sel: _sel,
              colors: colors,
              clipLength: clip.length,
              labelNote: d != null && (d.op == _Op.velocity || d.op == _Op.velocityPaint) ? d.anchor : null,
              font: _font(context),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------- peças da barra

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) => Container(width: 1, height: 24, margin: const EdgeInsets.symmetric(horizontal: 6), color: Palette.hairline);
}

class _ToolToggle extends StatelessWidget {
  final IconData icon;
  final bool on;
  final String tooltip;
  final VoidCallback onTap;
  const _ToolToggle({required this.icon, required this.on, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onTap,
    isSelected: on,
    style: IconButton.styleFrom(foregroundColor: Colors.white70, backgroundColor: on ? Palette.accent.withValues(alpha: .12) : null),
    selectedIcon: Icon(icon, color: Palette.accent),
    icon: Icon(icon),
  );
}

class _MenuLabel extends StatelessWidget {
  final IconData icon;
  final String text;
  const _MenuLabel({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: Colors.white70),
        const SizedBox(width: 6),
        Text(text, style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()])),
        const Icon(Icons.arrow_drop_down, size: 18, color: Colors.white54),
      ],
    ),
  );
}
