/// A parte de tela do MIDI learn: o contorno dos controles mapeáveis no modo "Aprender MIDI", o
/// menu de contexto (Aprender MIDI, Remover mapeamento), o botão da barra, a faixa de aviso e o
/// painel "Mapeamentos MIDI".
library;

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../widgets/theme.dart';
import 'controller.dart';
import 'knob.dart' show KnobMenuAction, modulationColor;
import 'midi_learn.dart';
import 'midi_map.dart';
import 'model.dart';
import 'modulation_ops.dart';
import 'modulation_ui.dart';
import 'keymap.dart';

/// Cor do contorno dos controles no modo aprender.
const midiLearnColor = Color(0xFFE3B341);

/// Contorna um controle mapeável. No modo "Aprender MIDI" ele fica com contorno: clicar arma
/// ("mexa no controle do seu teclado"), botão direito ou toque longo abre o menu. Fora do modo, um
/// controle já mapeado leva um pontinho; com [secondaryMenu], o botão direito abre o menu também
/// (controles que não têm menu próprio).
///
/// A árvore é a mesma nos dois estados (o filho não perde o gesto em andamento ao ligar o modo).
class MidiLearnControl extends StatelessWidget {
  final DawController c;

  /// Faixa (índice; −1 = master) e o alvo do controle.
  final int track;
  final AutoTarget target;
  final Widget child;
  final double radius;
  final bool secondaryMenu;
  const MidiLearnControl({
    super.key,
    required this.c,
    required this.track,
    required this.target,
    required this.child,
    this.radius = 8,
    this.secondaryMenu = false,
  });

  @override
  Widget build(BuildContext context) {
    final l = c.midiLearn;
    return ListenableBuilder(
      listenable: l,
      builder: (context, _) {
        final armed = l.armed;
        final isArmed = armed != null && armed.track == track && armed.target == target;
        final m = l.mappingFor(track, target);
        Widget body = child;
        if (secondaryMenu) {
          body = Listener(
            onPointerDown: (e) {
              if (!l.learning && e.kind == PointerDeviceKind.mouse && e.buttons == kSecondaryMouseButton) {
                showMidiLearnMenu(context, c, track, target, e.position);
              }
            },
            // no toque (sem botão direito) o toque longo abre o mesmo menu, com "Modular…"
            child: GestureDetector(
              supportedDevices: const {PointerDeviceKind.touch, PointerDeviceKind.stylus, PointerDeviceKind.invertedStylus},
              onLongPress: () {
                if (l.learning) return;
                final box = context.findRenderObject() as RenderBox;
                showMidiLearnMenu(context, c, track, target, box.localToGlobal(box.size.center(Offset.zero)));
              },
              child: body,
            ),
          );
        }
        return Stack(
          fit: StackFit.passthrough,
          clipBehavior: Clip.none,
          children: [
            body,
            if (l.learning)
              Positioned.fill(
                child: _LearnOverlay(c: c, track: track, target: target, armed: isArmed, mapping: m, radius: radius),
              )
            else if (m != null)
              const Positioned(top: 0, right: 0, child: IgnorePointer(child: _MappedDot())),
            // controle com modulação (o valor mostrado é a base): um pontinho ciano no canto
            if (c.modulationOf(track)?.modulates(target) ?? false) const Positioned(top: 0, left: 0, child: IgnorePointer(child: _ModDot())),
          ],
        );
      },
    );
  }
}

class _ModDot extends StatelessWidget {
  const _ModDot();
  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('mod-dot'),
    width: 6,
    height: 6,
    decoration: const BoxDecoration(color: modulationColor, shape: BoxShape.circle),
  );
}

class _MappedDot extends StatelessWidget {
  const _MappedDot();
  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('midi-mapped-dot'),
    width: 6,
    height: 6,
    decoration: const BoxDecoration(color: midiLearnColor, shape: BoxShape.circle),
  );
}

class _LearnOverlay extends StatelessWidget {
  final DawController c;
  final int track;
  final AutoTarget target;
  final bool armed;
  final MidiMapping? mapping;
  final double radius;
  const _LearnOverlay({required this.c, required this.track, required this.target, required this.armed, required this.mapping, required this.radius});

  @override
  Widget build(BuildContext context) {
    final m = mapping;
    final color = armed ? midiLearnColor : (m != null ? Palette.success : midiLearnColor.withValues(alpha: 0.55));
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        key: ValueKey('midi-learn-${track}_${target.kind.name}_${target.ref}_${target.param}'),
        behavior: HitTestBehavior.opaque,
        onTap: () => armed ? c.midiLearn.disarm() : c.midiLearn.arm(track, target),
        onSecondaryTapUp: (d) => showMidiLearnMenu(context, c, track, target, d.globalPosition),
        onLongPress: () {
          final box = context.findRenderObject() as RenderBox;
          showMidiLearnMenu(context, c, track, target, box.localToGlobal(box.size.center(Offset.zero)));
        },
        child: Tooltip(
          message: armed
              ? 'Mexa no controle do seu teclado…'
              : m != null
              ? 'Mapeado em ${m.source.label}. Clique para aprender outro; botão direito ou toque longo: remover'
              : 'Aprender MIDI: clique e mexa num controle do seu teclado',
          waitDuration: const Duration(milliseconds: 600),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: armed ? midiLearnColor.withValues(alpha: 0.22) : Colors.black.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: color, width: armed ? 2.5 : 1.5),
            ),
            child: m == null
                ? null
                : Align(
                    alignment: Alignment.topLeft,
                    child: Container(
                      margin: const EdgeInsets.all(1),
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(color: Palette.success.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(3)),
                      child: Text(
                        m.source.shortLabel,
                        style: const TextStyle(fontSize: 8, height: 1.2, fontWeight: FontWeight.w700, color: Colors.black),
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// "Aprender MIDI" e "Remover mapeamento" do controle, para o menu de contexto do knob.
List<KnobMenuAction> midiLearnActions(DawController c, int track, AutoTarget target) {
  final l = c.midiLearn;
  final m = l.mappingFor(track, target);
  return [
    KnobMenuAction('Aprender MIDI', Icons.settings_remote, () => l.arm(track, target)),
    if (m != null) KnobMenuAction('Remover mapeamento (${m.source.label})', Icons.link_off, () => l.removeFor(track, target)),
    if (c.canModulate(track, target)) modulateAction(c, track, target),
  ];
}

/// O menu de contexto do controle na posição [at] (coordenadas da tela).
Future<void> showMidiLearnMenu(BuildContext context, DawController c, int track, AutoTarget target, Offset at) async {
  final l = c.midiLearn;
  final m = l.mappingFor(track, target);
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final v = await showMenu<String>(
    context: context,
    position: RelativeRect.fromRect(at & Size.zero, Offset.zero & overlay.size),
    items: [
      const PopupMenuItem(
        value: 'learn',
        child: Row(children: [Icon(Icons.settings_remote, size: 18), SizedBox(width: 10), Text('Aprender MIDI')]),
      ),
      if (m != null)
        PopupMenuItem(
          value: 'remove',
          child: Row(
            children: [
              const Icon(Icons.link_off, size: 18),
              const SizedBox(width: 10),
              Flexible(child: Text('Remover mapeamento (${m.source.label})', maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
          ),
        ),
      if (c.canModulate(track, target))
        const PopupMenuItem(
          value: 'modulate',
          child: Row(children: [Icon(Icons.waves, size: 18), SizedBox(width: 10), Text('Modular…')]),
        ),
      const PopupMenuItem(
        value: 'panel',
        child: Row(children: [Icon(Icons.list_alt, size: 18), SizedBox(width: 10), Text('Mapeamentos MIDI…')]),
      ),
    ],
  );
  switch (v) {
    case 'learn':
      l.arm(track, target);
    case 'remove':
      l.removeFor(track, target);
    case 'modulate':
      if (context.mounted) unawaited(showModulateDialog(context, c, track, target));
    case 'panel':
      if (context.mounted) unawaited(showMidiMapPanel(context, c));
  }
}

/// Liga o modo aprender, pedindo o MIDI do navegador se ainda não estava ligado (o clique é o
/// gesto que o navegador exige).
void toggleMidiLearn(DawController c) {
  final on = !c.midiLearn.learning;
  c.midiLearn.setLearning(on);
  if (on && !c.midiEnabled) unawaited(c.enableMidiInput());
}

/// O botão "Aprender MIDI" da barra: ícone com dica; botão direito ou toque longo abre o painel.
class MidiLearnButton extends StatelessWidget {
  final DawController c;
  const MidiLearnButton({super.key, required this.c});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c.midiLearn,
    builder: (context, _) {
      final on = c.midiLearn.learning;
      final n = c.doc.midiMap.items.length;
      return GestureDetector(
        onSecondaryTap: () => unawaited(showMidiMapPanel(context, c)),
        onLongPress: () => unawaited(showMidiMapPanel(context, c)),
        child: IconButton(
          key: const ValueKey('midi-learn-button'),
          tooltip: on
              ? 'Sair do modo Aprender MIDI${shortcutHint('midilearn.toggle')}'
              : 'Aprender MIDI${shortcutHint('midilearn.toggle')}: clique num controle e mexa no botão do seu teclado${n > 0 ? '\n$n mapeamento${n == 1 ? '' : 's'} · botão direito: lista' : ''}',
          onPressed: () => toggleMidiLearn(c),
          isSelected: on,
          style: IconButton.styleFrom(foregroundColor: Colors.white70),
          selectedIcon: const Icon(Icons.settings_remote, color: midiLearnColor),
          icon: Badge(isLabelVisible: n > 0, smallSize: 6, child: const Icon(Icons.settings_remote)),
        ),
      );
    },
  );
}

/// Faixa que aparece enquanto o modo está ligado: diz o que fazer e dá acesso à lista.
class MidiLearnBanner extends StatelessWidget {
  final DawController c;
  const MidiLearnBanner({super.key, required this.c});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([c, c.midiLearn]),
    builder: (context, _) {
      final l = c.midiLearn;
      if (!l.learning) return const SizedBox.shrink();
      final a = l.armed;
      final learned = l.lastLearned;
      final String text;
      if (a != null) {
        final name = c.targetName(a.track, a.target) ?? 'o controle';
        text = 'Mexa no controle do seu teclado que vai comandar "$name"… (Esc cancela)';
      } else if (learned != null && l.alive(learned)) {
        text = 'Aprendido: ${learned.source.label} → ${l.targetLabel(learned)}. Clique noutro controle contornado ou Esc para sair.';
      } else if (!c.midiEnabled) {
        text = 'Aprender MIDI: ligue a entrada MIDI (botão do cabo) e clique num controle contornado.';
      } else if (c.midiInputs.isEmpty) {
        text = 'Aprender MIDI: nenhum aparelho conectado. Conecte o teclado; ele aparece sozinho.';
      } else {
        text = 'Aprender MIDI: clique num controle contornado e mexa no botão do seu teclado (Esc sai).';
      }
      return Container(
        key: const ValueKey('midi-learn-banner'),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        color: midiLearnColor.withValues(alpha: 0.14),
        child: Row(
          children: [
            const Icon(Icons.settings_remote, size: 18, color: midiLearnColor),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: Theme.of(context).textTheme.bodySmall)),
            TextButton(
              key: const ValueKey('midi-learn-list'),
              onPressed: () => unawaited(showMidiMapPanel(context, c)),
              child: Text('Mapeamentos (${c.doc.midiMap.items.length})'),
            ),
            TextButton(onPressed: () => l.setLearning(false), child: const Text('Sair')),
          ],
        ),
      );
    },
  );
}

// ------------------------------------------------------------------------- painel

Future<void> showMidiMapPanel(BuildContext context, DawController c) => showDialog<void>(
  context: context,
  builder: (_) => MidiMapPanel(c: c),
);

/// "Mapeamentos MIDI": a lista com origem, alvo, invertido, curva, faixa e remover, a opção do
/// takeover e o padrão para novos projetos.
class MidiMapPanel extends StatefulWidget {
  final DawController c;
  const MidiMapPanel({super.key, required this.c});

  @override
  State<MidiMapPanel> createState() => _MidiMapPanelState();
}

class _MidiMapPanelState extends State<MidiMapPanel> {
  DawController get c => widget.c;
  String? _note;

  Future<void> _saveDefault() async {
    try {
      await saveMidiDefault(c.localStore, c.doc.midiMap, c.doc.tracks);
      const saved = 'Guardado: os projetos novos começam com estes mapeamentos de volume, pan e instrumento (efeitos e envios ficam de fora).';
      if (mounted) setState(() => _note = saved);
    } catch (e) {
      if (mounted) setState(() => _note = 'Não deu para guardar o padrão: $e');
    }
  }

  Future<void> _clearDefault() async {
    try {
      await clearMidiDefault(c.localStore);
      if (mounted) setState(() => _note = 'Padrão apagado: projetos novos começam sem mapeamentos.');
    } catch (e) {
      if (mounted) setState(() => _note = 'Não deu para apagar o padrão: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = c.midiLearn;
    return ListenableBuilder(
      listenable: Listenable.merge([c, l]),
      builder: (context, _) {
        final items = c.doc.midiMap.items;
        return AlertDialog(
          title: const Text('Mapeamentos MIDI'),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                    key: const ValueKey('midi-soft'),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text('Suave (só assume ao cruzar o valor atual)'),
                    subtitle: const Text('O controle não salta: o botão do teclado só passa a mandar quando chega ao valor que o controle já tem'),
                    value: c.doc.midiMap.soft,
                    onChanged: l.setSoft,
                  ),
                  const Divider(),
                  if (items.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text('Nenhum mapeamento. Ligue "Aprender MIDI" na barra, clique num controle e mexa no botão do teclado.'),
                    ),
                  for (final m in items) _Row(key: ValueKey('midi-row-${m.id}'), c: c, m: m),
                  if (_note != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(_note!, key: const ValueKey('midi-note'), style: Theme.of(context).textTheme.bodySmall),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              key: const ValueKey('midi-default-save'),
              onPressed: items.isEmpty ? null : _saveDefault,
              child: const Text('Salvar como padrão para novos projetos'),
            ),
            TextButton(key: const ValueKey('midi-default-clear'), onPressed: _clearDefault, child: const Text('Apagar o padrão')),
            TextButton(key: const ValueKey('midi-clear'), onPressed: items.isEmpty ? null : l.clear, child: const Text('Remover todos')),
            FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Fechar')),
          ],
        );
      },
    );
  }
}

class _Row extends StatelessWidget {
  final DawController c;
  final MidiMapping m;
  const _Row({super.key, required this.c, required this.m});

  @override
  Widget build(BuildContext context) {
    final l = c.midiLearn;
    final alive = l.alive(m);
    final small = Theme.of(context).textTheme.bodySmall;
    String pct(double v) => '${(v * 100).round()}%';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: Palette.raised,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: alive ? Palette.hairline : Palette.danger.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                m.source.label,
                key: ValueKey('midi-source-${m.id}'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Icon(Icons.arrow_forward, size: 14, color: Colors.white54),
              ),
              Expanded(
                child: Text(
                  l.targetLabel(m),
                  key: ValueKey('midi-target-${m.id}'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: alive ? null : Palette.danger),
                ),
              ),
              IconButton(
                key: ValueKey('midi-remove-${m.id}'),
                tooltip: 'Remover mapeamento',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.delete_outline, size: 20),
                onPressed: () => l.remove(m.id),
              ),
            ],
          ),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            children: [
              FilterChip(
                key: ValueKey('midi-invert-${m.id}'),
                label: const Text('Invertido'),
                selected: m.inverted,
                onSelected: (v) => l.update(m.id, inverted: v),
              ),
              DropdownButton<MidiCurve>(
                key: ValueKey('midi-curve-${m.id}'),
                value: m.curve,
                isDense: true,
                underline: const SizedBox.shrink(),
                items: [for (final k in MidiCurve.values) DropdownMenuItem(value: k, child: Text(k.label))],
                onChanged: (v) => v == null ? null : l.update(m.id, curve: v),
              ),
              Text('Mín ${pct(m.min)}', style: small),
              SizedBox(
                width: 190,
                child: RangeSlider(
                  key: ValueKey('midi-range-${m.id}'),
                  values: RangeValues(m.min < m.max ? m.min : m.max, m.min < m.max ? m.max : m.min),
                  onChanged: (r) => l.update(m.id, min: r.start, max: r.end),
                ),
              ),
              Text('Máx ${pct(m.max)}', style: small),
            ],
          ),
        ],
      ),
    );
  }
}
