/// A tela da modulação: o painel "Modulação" do dock (moduladores da faixa selecionada, com os
/// destinos e as quantidades), o "Modular…" do menu de contexto dos controles e os presets.
library;

import 'package:flutter/material.dart' hide Curve;

import '../widgets/feedback.dart';
import '../widgets/theme.dart';
import 'controller.dart';
import 'instruments.dart';
import 'knob.dart';
import 'model.dart';
import 'modulation.dart';
import 'modulation_ops.dart';

const _rateSpec = ParamSpec(0, 'Taxa', '', modRateMin, modRateMax, 1, unit: 'Hz', curve: Curve.log);
const _depthSpec = ParamSpec(1, 'Profundidade', '', 0, 1, 1, unit: '%');
const _phaseSpec = ParamSpec(2, 'Fase', '', 0, 1, 0, unit: '%');
const _gainSpec = ParamSpec(3, 'Ganho', '', 0, 8, 2, unit: 'x');
const _attackSpec = ParamSpec(4, 'Ataque', '', 0.5, 5000, 10, unit: 'ms', curve: Curve.log);
const _releaseSpec = ParamSpec(5, 'Soltura', '', 5, 5000, 120, unit: 'ms', curve: Curve.log);
const _valueSpec = ParamSpec(6, 'Valor', '', 0, 1, 0, unit: '%');

String _ms(double v) =>
    v < 10 ? '${v.toStringAsFixed(1).replaceAll('.', ',')} ms' : (v < 1000 ? '${v.round()} ms' : '${(v / 1000).toStringAsFixed(2).replaceAll('.', ',')} s');

IconData _kindIcon(ModKind k) => switch (k) {
  ModKind.lfo => Icons.waves,
  ModKind.follower => Icons.show_chart,
  ModKind.macro => Icons.tune,
};

/// A entrada "Modular…" do menu de contexto de um controle: abre o seletor de modulador.
KnobMenuAction modulateAction(DawController c, int track, AutoTarget target) =>
    KnobMenuAction.withContext('Modular…', Icons.waves, (context) => showModulateDialog(context, c, track, target));

/// O seletor do "Modular…": um modulador que já existe na faixa ou um novo (LFO, seguidor de
/// envelope, macro). Cria o destino com 25% e abre o painel de modulação para ajustar.
Future<void> showModulateDialog(BuildContext context, DawController c, int track, AutoTarget target) => showDialog<void>(
  context: context,
  builder: (_) => _ModulateDialog(c: c, track: track, target: target),
);

class _ModulateDialog extends StatefulWidget {
  final DawController c;
  final int track;
  final AutoTarget target;
  const _ModulateDialog({required this.c, required this.track, required this.target});

  @override
  State<_ModulateDialog> createState() => _ModulateDialogState();
}

class _ModulateDialogState extends State<_ModulateDialog> {
  String? _error;

  void _pick({String? sourceId, ModKind kind = ModKind.lfo}) {
    final c = widget.c;
    final err = c.modAssign(widget.track, widget.target, sourceId: sourceId, kind: kind);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    // o painel abre na faixa do controle, para acertar a quantidade
    c.showEffects(widget.track);
    c.setDock(Dock.modulation);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final m = c.modulation(widget.track);
    final full = m.sources.length >= maxModSources;
    final label = modTargetLabel(c, widget.track, widget.target, fallback: 'o controle');
    return SimpleDialog(
      title: Text('Modular: $label', maxLines: 2, overflow: TextOverflow.ellipsis),
      children: [
        if (_error != null) Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 8), child: InlineNotice(_error!)),
        for (final s in m.sources)
          SimpleDialogOption(
            key: ValueKey('modulate-source-${s.id}'),
            onPressed: () => _pick(sourceId: s.id),
            child: Row(
              children: [
                Icon(_kindIcon(s.kind), size: 18, color: modulationColor),
                const SizedBox(width: 12),
                Expanded(child: Text('Modulador ${m.sources.indexOf(s) + 1} · ${s.summary}', maxLines: 1, overflow: TextOverflow.ellipsis)),
                if (s.dests.any((d) => d.target == widget.target)) const Icon(Icons.check, size: 16),
              ],
            ),
          ),
        if (m.sources.isNotEmpty) const Divider(height: 8),
        for (final k in ModKind.values)
          SimpleDialogOption(
            key: ValueKey('modulate-new-${k.name}'),
            onPressed: full ? null : () => _pick(kind: k),
            child: Row(
              children: [
                Icon(_kindIcon(k), size: 18, color: full ? Colors.white24 : Colors.white70),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(switch (k) {
                    ModKind.lfo => 'Novo LFO',
                    ModKind.follower => 'Novo seguidor de envelope',
                    ModKind.macro => 'Nova macro',
                  }),
                ),
              ],
            ),
          ),
        if (full)
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 4, 24, 4),
            child: Text('A faixa já tem $maxModSources moduladores: escolha um deles.', style: TextStyle(fontSize: 12, color: Colors.white54)),
          ),
      ],
    );
  }
}

/// O painel "Modulação" do dock: os moduladores da faixa (ou do master) que o rack de efeitos
/// mostra, cada um com o que ele gera e para onde vai.
class ModulationPanel extends StatefulWidget {
  final DawController c;
  const ModulationPanel({super.key, required this.c});

  @override
  State<ModulationPanel> createState() => _ModulationPanelState();
}

class _ModulationPanelState extends State<ModulationPanel> {
  String? _error;

  DawController get c => widget.c;

  void _run(String? err) => setState(() => _error = err);

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      var track = c.effectsTrack;
      if (track < 0 || track >= c.doc.tracks.length) track = -1;
      final m = c.modulation(track);
      final full = m.sources.length >= maxModSources;
      final name = track < 0 ? 'Master' : c.doc.tracks[track].name;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('$name · ${m.sources.length}/$maxModSources moduladores', style: const TextStyle(fontSize: 12, color: Colors.white70)),
                PopupMenuButton<ModKind>(
                  key: const ValueKey('mod-add'),
                  enabled: !full,
                  tooltip: full ? 'A faixa já tem $maxModSources moduladores' : 'Adicionar um modulador',
                  onSelected: (k) => _run(c.modAddSource(track, k) == null ? 'A faixa já tem $maxModSources moduladores.' : null),
                  itemBuilder: (_) => [
                    for (final k in ModKind.values)
                      PopupMenuItem(
                        value: k,
                        child: Row(
                          children: [
                            Icon(_kindIcon(k), size: 18),
                            const SizedBox(width: 10),
                            Flexible(child: Text(k.label, maxLines: 1, overflow: TextOverflow.ellipsis)),
                          ],
                        ),
                      ),
                  ],
                  child: _MenuChip(icon: Icons.add, label: 'Adicionar', enabled: !full),
                ),
                PopupMenuButton<ModPreset>(
                  key: const ValueKey('mod-presets'),
                  enabled: !full,
                  tooltip: 'Modulações prontas',
                  onSelected: (p) => _run(c.modApplyPreset(track, p)),
                  itemBuilder: (_) => [
                    for (final p in modPresets.where(
                      (p) => !p.hideWithoutTarget || p.availableFor(ModTrackView(track < 0 ? null : c.doc.tracks[track], c.effectsOf(track))),
                    ))
                      PopupMenuItem(
                        value: p,
                        child: SizedBox(
                          width: 240,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(p.name),
                              Text(
                                p.description,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11, color: Colors.white54),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                  child: _MenuChip(icon: Icons.auto_awesome, label: 'Presets', enabled: !full),
                ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: InlineNotice(_error!, onClose: () => setState(() => _error = null)),
            ),
          Expanded(
            child: m.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                        'Nenhum modulador. Adicione um LFO, um seguidor de envelope ou uma macro (ou use um preset) e ligue a controles: '
                        'botão direito (ou toque longo) num knob ou fader, "Modular…".',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white54, fontSize: 13),
                      ),
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, box) {
                      final width = (box.maxWidth - 24).clamp(200.0, 340.0);
                      return SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                        child: Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            for (var i = 0; i < m.sources.length; i++)
                              SizedBox(
                                width: width,
                                child: _SourceCard(key: ValueKey('mod-${m.sources[i].id}'), c: c, track: track, index: i, source: m.sources[i]),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      );
    },
  );
}

class _MenuChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool enabled;
  const _MenuChip({required this.icon, required this.label, required this.enabled});

  @override
  Widget build(BuildContext context) {
    final color = enabled ? Colors.white70 : Colors.white24;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        border: Border.all(color: Palette.hairlineStrong),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(fontSize: 12, color: color)),
        ],
      ),
    );
  }
}

class _SourceCard extends StatelessWidget {
  final DawController c;
  final int track, index;
  final ModSource source;
  const _SourceCard({super.key, required this.c, required this.track, required this.index, required this.source});

  /// Uma mudança no modulador (achado de novo pelo id: o documento pode ter sido trocado por um
  /// desfazer). Sem [undoable] é um passo de arraste.
  void _edit(void Function(ModSource s) f, {bool undoable = true}) => c.editModulation(track, (m) {
    final s = m.byId(source.id);
    if (s != null) f(s);
  }, undoable: undoable);

  Widget _knob(ParamSpec spec, double value, void Function(ModSource s, double v) set, {String Function(double)? format, double size = 34}) => Knob(
    spec: spec,
    value: value,
    size: size,
    color: modulationColor,
    format: format,
    onChangeStart: (_) => c.checkpoint(),
    onChanged: (v) => _edit((s) => set(s, v), undoable: false),
  );

  @override
  Widget build(BuildContext context) {
    final s = source;
    final controls = <Widget>[];
    switch (s.kind) {
      case ModKind.lfo:
        controls.addAll([
          _Drop<LfoShape>(
            key: ValueKey('mod-shape-${s.id}'),
            value: s.shape,
            items: {for (final v in LfoShape.values) v: v.label},
            onChanged: (v) => _edit((x) => x.shape = v),
          ),
          _Toggle(label: 'Livre', on: !s.sync, onTap: () => _edit((x) => x.sync = false)),
          _Toggle(label: 'Andamento', on: s.sync, onTap: () => _edit((x) => x.sync = true)),
          if (s.sync)
            _Drop<int>(
              key: ValueKey('mod-division-${s.id}'),
              value: s.division,
              items: {for (var i = 0; i < modDivisionCount; i++) i: modDivisionLabel(i)},
              onChanged: (v) => _edit((x) => x.division = v),
            )
          else
            _knob(_rateSpec, s.rate, (x, v) => x.rate = v),
          _knob(_depthSpec, s.depth, (x, v) => x.depth = v),
          _knob(_phaseSpec, s.phase, (x, v) => x.phase = v, format: (v) => '${(v * 360).round()}°'),
          _Toggle(label: 'Bipolar', on: s.bipolar, onTap: () => _edit((x) => x.bipolar = true)),
          _Toggle(label: 'Unipolar', on: !s.bipolar, onTap: () => _edit((x) => x.bipolar = false)),
        ]);
      case ModKind.follower:
        controls.addAll([
          _knob(_gainSpec, s.depth, (x, v) => x.depth = v),
          _knob(_attackSpec, s.attack, (x, v) => x.attack = v, format: _ms),
          _knob(_releaseSpec, s.release, (x, v) => x.release = v, format: _ms),
          _Toggle(label: 'Bipolar', on: s.bipolar, onTap: () => _edit((x) => x.bipolar = true)),
          _Toggle(label: 'Unipolar', on: !s.bipolar, onTap: () => _edit((x) => x.bipolar = false)),
        ]);
      case ModKind.macro:
        controls.addAll([
          _knob(_valueSpec, s.value, (x, v) => x.value = v),
          _Toggle(label: 'Bipolar', on: s.bipolar, onTap: () => _edit((x) => x.bipolar = true)),
          _Toggle(label: 'Unipolar', on: !s.bipolar, onTap: () => _edit((x) => x.bipolar = false)),
        ]);
    }
    final used = {for (final d in s.dests) d.target};
    final options = [
      for (final (t, label) in c.automatable(track))
        if (!used.contains(t) && c.canModulate(track, t)) (t, label),
    ];
    final canAdd = s.dests.length < maxModDests && options.isNotEmpty;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 10),
      decoration: BoxDecoration(
        color: Palette.raised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Palette.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_kindIcon(s.kind), size: 18, color: modulationColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${index + 1} · ${s.summary}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
              IconButton(
                key: ValueKey('mod-remove-${s.id}'),
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                tooltip: 'Apagar o modulador',
                onPressed: () => c.modRemoveSource(track, s.id),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: controls),
          ),
          const SizedBox(height: 6),
          for (var i = 0; i < s.dests.length; i++) _DestRow(c: c, track: track, sourceId: s.id, index: i, dest: s.dests[i]),
          PopupMenuButton<AutoTarget>(
            key: ValueKey('mod-add-dest-${s.id}'),
            enabled: canAdd,
            tooltip: s.dests.length >= maxModDests ? 'Cada modulador tem no máximo $maxModDests destinos' : 'Ligar a um controle',
            onSelected: (t) => c.modAssign(track, t, sourceId: s.id),
            itemBuilder: (_) => [
              for (final (t, label) in options)
                PopupMenuItem(
                  value: t,
                  child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
            ],
            child: Padding(
              padding: const EdgeInsets.only(top: 4, right: 6),
              child: _MenuChip(icon: Icons.add_link, label: 'Destino', enabled: canAdd),
            ),
          ),
        ],
      ),
    );
  }
}

class _DestRow extends StatelessWidget {
  final DawController c;
  final int track, index;
  final String sourceId;
  final ModDest dest;
  const _DestRow({required this.c, required this.track, required this.sourceId, required this.index, required this.dest});

  @override
  Widget build(BuildContext context) {
    final pct = (dest.amount * 100).round();
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  modTargetLabel(c, track, dest.target),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ),
              Text('${pct > 0 ? '+' : ''}$pct%', style: const TextStyle(fontSize: 12, fontFeatures: [FontFeature.tabularFigures()])),
              IconButton(
                key: ValueKey('mod-dest-remove-$sourceId-$index'),
                visualDensity: VisualDensity.compact,
                iconSize: 16,
                tooltip: 'Tirar este destino',
                onPressed: () => c.modRemoveDest(track, sourceId, index),
                icon: const Icon(Icons.link_off),
              ),
            ],
          ),
          SizedBox(
            height: 24,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              ),
              child: Slider(
                key: ValueKey('mod-amount-$sourceId-$index'),
                value: dest.amount.clamp(-1.0, 1.0),
                min: -1,
                max: 1,
                activeColor: modulationColor,
                onChangeStart: (_) => c.checkpoint(),
                onChanged: (v) => c.editModulation(track, (m) {
                  final d = m.byId(sourceId)?.dests;
                  if (d != null && index < d.length) d[index].amount = v;
                }, undoable: false),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  final String label;
  final bool on;
  final VoidCallback onTap;
  const _Toggle({required this.label, required this.on, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: on ? null : onTap,
    borderRadius: BorderRadius.circular(14),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: on ? modulationColor.withValues(alpha: 0.18) : null,
        border: Border.all(color: on ? modulationColor : Palette.hairlineStrong),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(label, style: TextStyle(fontSize: 11.5, color: on ? Colors.white : Colors.white60)),
    ),
  );
}

class _Drop<T> extends StatelessWidget {
  final T value;
  final Map<T, String> items;
  final ValueChanged<T> onChanged;
  const _Drop({super.key, required this.value, required this.items, required this.onChanged});

  @override
  Widget build(BuildContext context) => DropdownButtonHideUnderline(
    child: DropdownButton<T>(
      value: value,
      isDense: true,
      style: const TextStyle(fontSize: 12, color: Colors.white),
      dropdownColor: Palette.overlay,
      items: [for (final e in items.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    ),
  );
}
