/// Barra do transporte e das ferramentas: tocar, parar, posição, andamento, loop, metrônomo,
/// edição, grade, zoom, os painéis de baixo, as entradas de notas (teclado do computador e MIDI)
/// e importar.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/theme.dart';
import 'controller.dart';
import 'dock.dart';
import 'model.dart';
import 'timeline.dart' show deleteSelectedClip, duplicateSelectedClip, splitClipsAtPlayhead;

class TransportBar extends StatelessWidget {
  final DawController c;
  final bool compact;
  const TransportBar({super.key, required this.c, required this.compact});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final d = c.doc;
        final transport = [
          IconButton(tooltip: 'Parar e voltar (Enter)', onPressed: c.stop, icon: const Icon(Icons.stop)),
          ValueListenableBuilder<bool>(
            valueListenable: c.playing,
            builder: (_, playing, _) => IconButton.filled(
              tooltip: playing ? 'Pausar (espaço)' : 'Tocar (espaço)',
              onPressed: c.togglePlay,
              icon: Icon(playing ? Icons.pause : Icons.play_arrow),
            ),
          ),
          const SizedBox(width: 8),
          _Position(c: c),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () => _editTempo(context),
            child: Text('${d.bpm.round()} BPM · ${d.beatsPerBar}/4', style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()])),
          ),
          _Toggle(icon: Icons.repeat, on: d.loopOn, tooltip: 'Loop (L) · arraste na régua para marcar', onTap: c.toggleLoop),
          _Toggle(icon: Icons.av_timer, on: d.metronome, tooltip: 'Metrônomo (C)', onTap: c.toggleMetronome),
        ];
        final tools = [
          IconButton(tooltip: 'Desfazer (Ctrl+Z)', onPressed: c.canUndo ? c.undo : null, icon: const Icon(Icons.undo)),
          IconButton(tooltip: 'Refazer (Ctrl+Shift+Z)', onPressed: c.canRedo ? c.redo : null, icon: const Icon(Icons.redo)),
          IconButton(tooltip: 'Cortar no cursor (S)', onPressed: () => splitClipsAtPlayhead(c), icon: const Icon(Icons.content_cut)),
          IconButton(tooltip: 'Duplicar (Ctrl+D)', onPressed: c.selectedClip == null ? null : () => duplicateSelectedClip(c), icon: const Icon(Icons.copy_all)),
          IconButton(
            tooltip: 'Apagar o clipe (Delete)',
            onPressed: c.selectedClip == null ? null : () => deleteSelectedClip(c),
            icon: const Icon(Icons.delete_outline),
          ),
          PopupMenuButton<Snap>(
            tooltip: 'Grade de encaixe (Alt ao arrastar: livre)',
            initialValue: c.snap,
            onSelected: c.setSnap,
            itemBuilder: (_) => [for (final s in Snap.values) PopupMenuItem(value: s, child: Text(s.label))],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(children: [const Icon(Icons.grid_4x4, size: 18), const SizedBox(width: 4), Text(c.snap.label)]),
            ),
          ),
          IconButton(tooltip: 'Afastar', onPressed: () => c.zoom(1 / 1.5), icon: const Icon(Icons.zoom_out)),
          IconButton(tooltip: 'Aproximar', onPressed: () => c.zoom(1.5), icon: const Icon(Icons.zoom_in)),
        ];
        final panels = [
          _Toggle(icon: Icons.tune, on: c.dock == Dock.mixer, tooltip: 'Mixer (X)', onTap: () => toggleDock(c, Dock.mixer)),
          _Toggle(icon: Icons.edit_note, on: c.dock == Dock.editor, tooltip: 'Editor de notas (E)', onTap: () => toggleDock(c, Dock.editor)),
          _Toggle(icon: dockInstrumentIcon(c), on: c.dock == Dock.instrument, tooltip: 'Instrumento da faixa (I)', onTap: () => toggleDock(c, Dock.instrument)),
        ];
        final velocity = (c.keyboardVelocity * 100).round();
        final inputs = [
          _Toggle(
            icon: Icons.keyboard,
            on: c.keyboardOn,
            // a oitava à vista: é o que muda com Z/X sem outro retorno na tela
            label: c.keyboardOn ? 'C${c.keyboardOctave}' : null,
            tooltip: c.keyboardOn
                ? 'Teclado do computador ligado (Ctrl+K): A a L tocam a partir do C${c.keyboardOctave}, Z/X mudam a oitava, C/V a intensidade ($velocity%)'
                : 'Tocar com o teclado do computador (Ctrl+K)',
            onTap: c.toggleKeyboard,
          ),
          _Toggle(
            icon: Icons.cable,
            on: c.midiEnabled,
            label: c.midiInputs.isEmpty ? (c.midiEnabled ? '0' : null) : '${c.midiInputs.length}',
            tooltip: !c.midiEnabled
                ? 'Entrada MIDI: ligar teclado ou controlador'
                : c.midiInputs.isEmpty
                ? 'MIDI ligado, nenhum aparelho conectado: conecte e ele aparece aqui sozinho'
                : 'Entrada MIDI: ${c.midiInputs.join(', ')}',
            onTap: c.enableMidiInput,
          ),
        ];
        const divider = Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: SizedBox(width: 1, height: 28, child: ColoredBox(color: Palette.hairline)),
        );
        // largura toda: dentro da coluna da tela a barra encolhia até o conteúdo e ficava centralizada
        return Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            color: Palette.bar,
            border: Border.symmetric(horizontal: BorderSide(color: Palette.hairline)),
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  ...transport,
                  const SizedBox(width: 4),
                  divider,
                  ...tools,
                  divider,
                  ...panels,
                  divider,
                  ...inputs,
                  const SizedBox(width: 12),
                  FilledButton.tonalIcon(
                    onPressed: c.status == null ? c.importAudio : null,
                    icon: const Icon(Icons.file_open_outlined),
                    label: const Text('Importar'),
                  ),
                  if (c.status != null) ...[
                    const SizedBox(width: 12),
                    const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: 8),
                    Text(c.status!, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _editTempo(BuildContext context) async {
    final r = await showDialog<(int, int)>(
      context: context,
      builder: (_) => _TempoDialog(bpm: c.doc.bpm.round(), beatsPerBar: c.doc.beatsPerBar),
    );
    if (r != null) await c.setTempo(r.$1, r.$2);
  }
}

class _Position extends StatelessWidget {
  final DawController c;
  const _Position({required this.c});

  @override
  Widget build(BuildContext context) {
    final mono = Theme.of(context).textTheme.titleMedium!.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    return ValueListenableBuilder<double>(
      valueListenable: c.beat,
      builder: (_, beat, _) {
        final secs = beat * 60 / c.doc.bpm;
        final m = secs ~/ 60, s = secs - m * 60;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: Palette.ink, borderRadius: BorderRadius.circular(6)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(formatPosition(beat, c.doc.beatsPerBar), style: mono.copyWith(color: Palette.accent)),
              Text(
                '$m:${s.toStringAsFixed(2).padLeft(5, '0')}',
                style: Theme.of(context).textTheme.labelSmall!.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Botão de ligar e desligar: aceso na cor da marca. Com [label], mostra um valor ao lado do
/// ícone (a oitava do teclado, quantas entradas MIDI).
class _Toggle extends StatelessWidget {
  final IconData icon;
  final bool on;
  final String tooltip;
  final String? label;
  final VoidCallback onTap;
  const _Toggle({required this.icon, required this.on, required this.tooltip, required this.onTap, this.label});

  @override
  Widget build(BuildContext context) {
    if (label == null) {
      return IconButton(
        tooltip: tooltip,
        onPressed: onTap,
        isSelected: on,
        style: IconButton.styleFrom(foregroundColor: Colors.white70),
        selectedIcon: Icon(icon, color: Palette.accent),
        icon: Icon(icon),
      );
    }
    return Tooltip(
      message: tooltip,
      child: TextButton.icon(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: on ? Palette.accent : Colors.white70,
          backgroundColor: on ? Palette.accent.withValues(alpha: 0.1) : null,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          minimumSize: const Size(40, 40),
        ),
        icon: Icon(icon),
        label: Text(
          label!,
          style: const TextStyle(fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()]),
        ),
      ),
    );
  }
}

class _TempoDialog extends StatefulWidget {
  final int bpm, beatsPerBar;
  const _TempoDialog({required this.bpm, required this.beatsPerBar});
  @override
  State<_TempoDialog> createState() => _TempoDialogState();
}

class _TempoDialogState extends State<_TempoDialog> {
  // valor todo selecionado: digitar substitui em vez de emendar no número que já estava
  late final _bpm = TextEditingController(text: '${widget.bpm}')..selection = TextSelection(baseOffset: 0, extentOffset: '${widget.bpm}'.length);
  late int _bpb = widget.beatsPerBar;
  String? _error;

  void _save() {
    final v = int.tryParse(_bpm.text.trim());
    if (v == null || v < 20 || v > 400) {
      setState(() => _error = 'Entre 20 e 400.');
      return;
    }
    Navigator.pop(context, (v, _bpb));
  }

  @override
  void dispose() {
    _bpm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Andamento e compasso'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _bpm,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(labelText: 'BPM', errorText: _error),
          onSubmitted: (_) => _save(),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<int>(
          initialValue: _bpb,
          decoration: const InputDecoration(labelText: 'Tempos por compasso'),
          items: [for (var i = 1; i <= 12; i++) DropdownMenuItem(value: i, child: Text('$i/4'))],
          onChanged: (v) => setState(() => _bpb = v ?? _bpb),
        ),
      ],
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
      FilledButton(onPressed: _save, child: const Text('Salvar')),
    ],
  );
}
