/// O painel de baixo da tela do projeto: mixer, editor de notas (piano roll), instrumento e
/// efeitos da faixa, em abas. O que aparece é do controlador (`c.dock`); a altura é deste widget.
library;

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../widgets/theme.dart';
import 'controller.dart';
import 'effects_panel.dart';
import 'instrument_panel.dart';
import 'instruments.dart';
import 'mixer_panel.dart';
import 'modulation_ops.dart';
import 'modulation_ui.dart';
import 'piano_roll.dart';
import 'step_sequencer.dart';
import 'step_sequencer_ui.dart';

/// Abre o painel, ou fecha se ele já está aberto (botões da barra e atalhos).
void toggleDock(DawController c, Dock d) {
  if (c.dock == d) {
    c.setDock(Dock.none);
  } else {
    showDock(c, d);
  }
}

/// Abre o painel. O editor abre no clipe de notas selecionado no arranjo, se houver um; os efeitos,
/// na faixa selecionada (no master quando não há faixa).
void showDock(DawController c, Dock d) {
  if (d == Dock.modulation) {
    // a modulação fala da mesma faixa que o rack de efeitos (ou do master)
    c.showEffects(c.selectedTrack < c.doc.tracks.length ? c.selectedTrack : -1);
    c.setDock(Dock.modulation);
    return;
  }
  if (d == Dock.effects) {
    c.showEffects(c.selectedTrack < c.doc.tracks.length ? c.selectedTrack : -1);
    return;
  }
  final sel = c.selectedClip;
  if (d == Dock.editor && sel != null && sel != c.editingClip && c.findMidiClip(sel) != null) {
    c.openPianoRoll(sel);
  } else {
    c.setDock(d);
  }
}

/// Ícone do painel do instrumento: o do tipo da faixa selecionada, quando ela é de instrumento.
IconData dockInstrumentIcon(DawController c) {
  final i = c.selectedTrack;
  if (i < c.doc.tracks.length && c.doc.tracks[i].kind.isInstrument) return c.doc.tracks[i].kind.icon;
  return Icons.piano;
}

class DockPanel extends StatefulWidget {
  final DawController c;

  /// Altura do espaço que o painel divide com o arranjo.
  final double available;

  /// Celular: altura fixa numa fração do espaço, sem alça de arrastar.
  final bool compact;

  const DockPanel({super.key, required this.c, required this.available, required this.compact});

  @override
  State<DockPanel> createState() => _DockPanelState();
}

class _DockPanelState extends State<DockPanel> {
  static const _gripHeight = 6.0;
  static const _barHeight = 34.0;
  static const _minHeight = 230.0;

  /// O arranjo nunca fica com menos que isto: a régua e umas duas faixas.
  static const _keepTimeline = 150.0;

  /// No celular, a fração do espaço que o painel ocupa.
  static const _compactShare = 0.6;

  /// Altura escolhida arrastando a borda; vale para a sessão inteira (reabrir o painel não volta
  /// ao padrão). Null: o padrão, metade do espaço (o piano roll precisa de altura para ser útil).
  static double? _chosen;
  double get _height => _chosen ?? math.max(320.0, widget.available * 0.5);
  set _height(double h) => _chosen = h;

  /// Altura de antes de maximizar (null: não está maximizado).
  double? _restore;
  bool _gripHover = false, _dragging = false;

  /// Cabe sempre a barra e um pouco de conteúdo, mesmo em janela baixa, mas nunca mais que o espaço.
  double get _maxHeight => math.max(math.min(_gripHeight + _barHeight + 60, widget.available), widget.available - _keepTimeline);

  double _clamp(double h) {
    final max = _maxHeight;
    return h.clamp(math.min(_minHeight, max), max);
  }

  /// A altura na tela: a guardada, dentro do que cabe agora (a janela pode ter encolhido).
  double get _shown => widget.compact ? widget.available * _compactShare : _clamp(_height);

  void _resize(double dy) => setState(() {
    _height = _clamp(_shown - dy);
    _restore = null;
  });

  void _toggleMax() => setState(() {
    if (_restore != null) {
      _height = _restore!;
      _restore = null;
    } else {
      _restore = _shown;
      _height = _maxHeight;
    }
  });

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.c,
    builder: (context, _) {
      final c = widget.c;
      if (c.dock == Dock.none) {
        // a alça some sem avisar a saída do mouse: não pode voltar acesa na próxima abertura
        _gripHover = _dragging = false;
        return const SizedBox.shrink();
      }
      return SizedBox(
        height: _shown,
        child: Column(
          children: [
            _header(context),
            Expanded(
              child: ColoredBox(
                color: Palette.bar,
                // um conteúdo por vez: o piano roll registra as teclas dele ao montar e só solta
                // ao desmontar, então não pode ficar vivo escondido atrás de outra aba
                child: KeyedSubtree(
                  key: ValueKey(c.dock),
                  child: switch (c.dock) {
                    Dock.mixer => MixerPanel(c: c),
                    Dock.editor => PianoRoll(c: c),
                    Dock.instrument => InstrumentPanel(c: c),
                    Dock.effects => EffectsPanel(c: c),
                    Dock.modulation => ModulationPanel(c: c),
                    Dock.steps => StepSequencerPanel(c: c),
                    Dock.none => const SizedBox.shrink(),
                  },
                ),
              ),
            ),
          ],
        ),
      );
    },
  );

  Widget _header(BuildContext context) {
    final c = widget.c;
    // com a aba Passos (bateria e sampler fatiado) são seis abas: os rótulos só cabem em janela mais larga
    final hasSteps = c.dock == Dock.steps || (c.selectedTrack < c.doc.tracks.length && stepsAvailable(c.doc.tracks[c.selectedTrack]));
    final iconsOnly = MediaQuery.sizeOf(context).width < (hasSteps ? 760 : 560);
    final bar = SizedBox(
      height: _barHeight,
      child: Row(
        children: [
          const SizedBox(width: 4),
          _Tab(
            icon: Icons.tune,
            label: 'Mixer',
            tooltip: 'Mixer (X)',
            iconOnly: iconsOnly,
            selected: c.dock == Dock.mixer,
            onTap: () => showDock(c, Dock.mixer),
          ),
          _Tab(
            icon: Icons.edit_note,
            label: 'Editor',
            tooltip: 'Editor de notas (E)',
            iconOnly: iconsOnly,
            selected: c.dock == Dock.editor,
            onTap: () => showDock(c, Dock.editor),
          ),
          if (hasSteps)
            _Tab(
              icon: Icons.grid_on,
              label: 'Passos',
              tooltip: 'Sequenciador de passos da bateria e do sampler fatiado',
              iconOnly: iconsOnly,
              selected: c.dock == Dock.steps,
              onTap: () => showDock(c, Dock.steps),
            ),
          _Tab(
            icon: dockInstrumentIcon(c),
            label: 'Instrumento',
            tooltip: 'Instrumento da faixa (I)',
            iconOnly: iconsOnly,
            selected: c.dock == Dock.instrument,
            onTap: () => showDock(c, Dock.instrument),
          ),
          _Tab(
            icon: Icons.auto_fix_high,
            label: 'Efeitos',
            tooltip: 'Efeitos da faixa (F)',
            iconOnly: iconsOnly,
            selected: c.dock == Dock.effects,
            // já aberta, não troca o que está à vista (o master aberto pelo mixer, por exemplo)
            onTap: () {
              if (c.dock != Dock.effects) showDock(c, Dock.effects);
            },
          ),
          _Tab(
            icon: Icons.waves,
            label: 'Modulação',
            tooltip: 'Modulação da faixa: LFO, seguidor de envelope e macros',
            iconOnly: iconsOnly,
            selected: c.dock == Dock.modulation,
            onTap: () {
              if (c.dock != Dock.modulation) showDock(c, Dock.modulation);
            },
          ),
          const SizedBox(width: 12),
          Expanded(child: _Subject(c: c)),
          if (!widget.compact)
            _BarButton(
              icon: _restore == null ? Icons.expand_less : Icons.expand_more,
              tooltip: _restore == null ? 'Maximizar o painel' : 'Restaurar a altura',
              onTap: _toggleMax,
            ),
          _BarButton(icon: Icons.close, tooltip: 'Fechar o painel (Esc)', onTap: () => c.setDock(Dock.none)),
          const SizedBox(width: 4),
        ],
      ),
    );
    final lit = _gripHover || _dragging;
    final box = DecoratedBox(
      decoration: const BoxDecoration(
        color: Palette.bar,
        border: Border(
          top: BorderSide(color: Palette.hairlineStrong),
          bottom: BorderSide(color: Palette.hairline),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!widget.compact)
            MouseRegion(
              cursor: SystemMouseCursors.resizeRow,
              onEnter: (_) => setState(() => _gripHover = true),
              onExit: (_) => setState(() => _gripHover = false),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onDoubleTap: _toggleMax,
                child: SizedBox(
                  height: _gripHeight,
                  child: Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      width: lit ? 56 : 36,
                      height: 3,
                      decoration: BoxDecoration(color: lit ? Palette.accent : Colors.white24, borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                ),
              ),
            ),
          bar,
        ],
      ),
    );
    if (widget.compact) return box;
    // a borda e o vazio da barra arrastam; as abas e os botões seguem só com o toque
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // conta desde o toque: a folga até reconhecer o arraste não se perde
      dragStartBehavior: DragStartBehavior.down,
      onVerticalDragStart: (_) => setState(() => _dragging = true),
      onVerticalDragUpdate: (d) => _resize(d.delta.dy),
      onVerticalDragEnd: (_) => setState(() => _dragging = false),
      onVerticalDragCancel: () => setState(() => _dragging = false),
      child: box,
    );
  }
}

class _Tab extends StatelessWidget {
  final IconData icon;
  final String label, tooltip;
  final bool selected, iconOnly;
  final VoidCallback onTap;
  const _Tab({required this.icon, required this.label, required this.tooltip, required this.selected, required this.iconOnly, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = selected ? Palette.accent : Colors.white70;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          height: _DockPanelState._barHeight,
          padding: EdgeInsets.symmetric(horizontal: iconOnly ? 10 : 12),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: selected ? Palette.accent : Colors.transparent, width: 2)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 17, color: color),
              if (!iconOnly) ...[
                const SizedBox(width: 6),
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelLarge!.copyWith(color: color, fontWeight: selected ? FontWeight.w700 : FontWeight.w500),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _BarButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _BarButton({required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 32,
    height: 30,
    child: IconButton(padding: EdgeInsets.zero, iconSize: 18, tooltip: tooltip, onPressed: onTap, icon: Icon(icon)),
  );
}

/// Do que o painel está falando: o clipe no editor, a faixa do instrumento ou a dos efeitos.
class _Subject extends StatelessWidget {
  final DawController c;
  const _Subject({required this.c});

  @override
  Widget build(BuildContext context) {
    String? text;
    Color? dot;
    switch (c.dock) {
      case Dock.editor:
        final e = c.editing;
        if (e == null) {
          text = 'Nenhum clipe aberto';
        } else {
          final (t, clip) = e;
          text = clip.name.isEmpty ? t.name : '${clip.name} · ${t.name}';
          dot = trackColorAt(t.color);
        }
      case Dock.effects:
        final i = c.effectsTrack;
        final master = i < 0 || i >= c.doc.tracks.length;
        final n = c.effectsOf(master ? -1 : i).length;
        final count = n == 0 ? 'sem efeitos' : (n == 1 ? '1 efeito' : '$n efeitos');
        if (master) {
          text = 'Master · $count';
          dot = Colors.white;
        } else {
          text = '${c.doc.tracks[i].name} · $count';
          dot = trackColorAt(c.doc.tracks[i].color);
        }
      case Dock.modulation:
        final i = c.effectsTrack;
        final master = i < 0 || i >= c.doc.tracks.length;
        final n = c.modulation(master ? -1 : i).sources.length;
        final count = n == 0 ? 'sem moduladores' : (n == 1 ? '1 modulador' : '$n moduladores');
        text = master ? 'Master · $count' : '${c.doc.tracks[i].name} · $count';
        dot = master ? Colors.white : trackColorAt(c.doc.tracks[i].color);
      case Dock.instrument:
        if (c.selectedTrack < c.doc.tracks.length) {
          final t = c.doc.tracks[c.selectedTrack];
          text = switch (t.kind) {
            TrackKind.bus => '${t.name} · barramento, sem instrumento',
            TrackKind.audio => '${t.name} · faixa de áudio, sem instrumento',
            _ => '${t.name} · ${t.kind.label}',
          };
          dot = trackColorAt(t.color);
        }
      case Dock.steps:
        final tg = stepTarget(c);
        if (tg != null) {
          final clip = tg.clip;
          text = clip == null || clip.name.isEmpty ? tg.track.name : '${clip.name} · ${tg.track.name}';
          dot = trackColorAt(tg.track.color);
        }
      case Dock.mixer || Dock.none:
        break;
    }
    if (text == null) return const SizedBox.shrink();
    return Row(
      children: [
        if (dot != null) ...[
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium!.copyWith(color: Colors.white70),
          ),
        ),
      ],
    );
  }
}
