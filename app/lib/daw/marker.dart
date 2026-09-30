/// Marcadores na régua: as bandeirinhas (arrastar move, duplo clique renomeia, botão direito ou
/// toque longo abre o menu) e as ações de criar e renomear que a barra e o teclado compartilham.
/// A lógica (criar, mover, pular, seções) mora no controlador; aqui só a parte de tela.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/dialogs.dart';
import 'controller.dart';
import 'export.dart' show showExportDialog;
import 'export_options.dart';
import 'model.dart';

/// M: marcador no cursor. Já havendo um ali, ele só fica selecionado.
void addMarkerAtPlayhead(DawController c) => c.addMarker();

/// Shift+M: pede o nome do marcador do cursor (criando-o se não houver). Cancelar não cria nada:
/// por isso o marcador só nasce depois que o nome vem.
Future<void> renameMarkerAtPlayhead(BuildContext context, DawController c) async {
  final have = c.markerAt(c.beat.value);
  final beat = c.beat.value;
  final name = await promptText(context, title: 'Nome do marcador', label: 'Nome', initial: have?.name ?? '', action: 'Salvar', maxLength: 40);
  if (name == null || name.trim().isEmpty) return;
  if (have != null) {
    c.renameMarker(have.id, name.trim());
  } else {
    c.addMarker(beat: beat, name: name.trim());
  }
}

Future<void> renameMarkerDialog(BuildContext context, DawController c, Marker m) async {
  final name = await promptText(context, title: 'Nome do marcador', label: 'Nome', initial: m.name, action: 'Salvar', maxLength: 40);
  if (name == null || name.trim().isEmpty) return;
  c.renameMarker(m.id, name.trim());
}

/// Menu de um marcador: renomear, loop da seção, cor e apagar.
Future<void> showMarkerMenu(BuildContext context, DawController c, Marker m, Offset at) async {
  final size = MediaQuery.sizeOf(context);
  final v = await showMenu<String>(
    context: context,
    position: RelativeRect.fromLTRB(at.dx, at.dy, size.width - at.dx, size.height - at.dy),
    items: [
      const PopupMenuItem(value: 'rename', child: Text('Renomear')),
      const PopupMenuItem(value: 'loop', child: Text('Loop desta seção')),
      const PopupMenuItem(value: 'export', child: Text('Exportar esta seção…')),
      PopupMenuItem(
        enabled: false,
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final col in DawController.markerColors)
              Builder(
                builder: (ctx) => Semantics(
                  button: true,
                  label: 'Cor do marcador',
                  child: GestureDetector(
                    onTap: () => Navigator.pop(ctx, 'c$col'),
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: Color(col),
                        shape: BoxShape.circle,
                        border: Border.all(color: m.color == col ? Colors.white : Colors.transparent, width: 2),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      const PopupMenuDivider(),
      const PopupMenuItem(value: 'delete', child: Text('Apagar o marcador')),
    ],
  );
  if (v == null || !context.mounted) return;
  switch (v) {
    case 'rename':
      await renameMarkerDialog(context, c, m);
    case 'loop':
      c.seek(m.beat);
      c.loopSection();
    case 'export':
      // do marcador até o próximo (ou o fim da música): o diálogo de exportação já abre com esse trecho
      final next = ([...c.doc.markers]..sort((a, b) => a.beat.compareTo(b.beat))).where((x) => x.beat > m.beat + 1e-6).firstOrNull;
      await showExportDialog(
        context,
        c,
        preset: ExportOptions(range: ExportRange.markers, fromMarker: m.id, toMarker: next?.id),
      );
    case 'delete':
      c.removeMarker(m.id);
    default:
      if (v.startsWith('c')) c.recolorMarker(m.id, int.parse(v.substring(1)));
  }
}

/// As bandeirinhas sobre a régua. Cada uma é uma haste de 1 px com uma etiqueta no topo; a haste
/// cruza a régua inteira para se ler o lugar exato.
class MarkerFlags extends StatelessWidget {
  final DawController c;
  const MarkerFlags({super.key, required this.c});

  static const flagHeight = 15.0;
  static const maxFlagWidth = 96.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) => Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          for (final m in c.doc.markers)
            if ((m.beat - c.scrollBeat) * c.pxPerBeat > -maxFlagWidth && (m.beat - c.scrollBeat) * c.pxPerBeat < box.maxWidth)
              Positioned(
                key: ValueKey('marker:${m.id}'),
                left: (m.beat - c.scrollBeat) * c.pxPerBeat,
                top: 0,
                bottom: 0,
                child: _Flag(c: c, marker: m),
              ),
        ],
      ),
    );
  }
}

class _Flag extends StatefulWidget {
  final DawController c;
  final Marker marker;
  const _Flag({required this.c, required this.marker});
  @override
  State<_Flag> createState() => _FlagState();
}

class _FlagState extends State<_Flag> {
  double _from = 0, _dx = 0;
  bool _moved = false;

  DawController get c => widget.c;
  Marker get m => widget.marker;

  double _target() {
    final raw = _from + _dx / c.pxPerBeat;
    return HardwareKeyboard.instance.isAltPressed ? raw : c.snapBeat(raw);
  }

  @override
  Widget build(BuildContext context) {
    final color = Color(m.color);
    final selected = c.selectedMarker == m.id;
    final label = m.name.isEmpty ? '·' : m.name;
    final chip = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        c.selectedMarker = m.id;
        c.goTo(m.beat);
      },
      onDoubleTap: () => renameMarkerDialog(context, c, m),
      onSecondaryTapUp: (d) => showMarkerMenu(context, c, m, d.globalPosition),
      onLongPressStart: (d) => showMarkerMenu(context, c, m, d.globalPosition),
      onHorizontalDragStart: (_) {
        _from = m.beat;
        _dx = 0;
        _moved = false;
        c.selectedMarker = m.id;
      },
      onHorizontalDragUpdate: (d) {
        _dx += d.delta.dx;
        final b = math.max(0.0, _target());
        if (b == m.beat) return;
        // um checkpoint só, no primeiro passo que anda de verdade: tocar sem mover não suja o histórico
        if (!_moved) {
          c.checkpoint('Mover marcador');
          _moved = true;
        }
        c.moveMarker(m.id, b, undoable: false);
      },
      child: Tooltip(
        message:
            '${m.name.isEmpty ? 'Marcador' : m.name} · ${formatPosition(m.beat, c.doc.beatsPerBar, meter: c.doc.meter)}\nArraste para mover · duplo clique renomeia · botão direito: menu',
        waitDuration: const Duration(milliseconds: 600),
        child: Container(
          height: MarkerFlags.flagHeight,
          constraints: const BoxConstraints(maxWidth: MarkerFlags.maxFlagWidth),
          padding: const EdgeInsets.symmetric(horizontal: 5),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: color,
            borderRadius: const BorderRadius.only(topRight: Radius.circular(3), bottomRight: Radius.circular(3)),
            border: selected ? Border.all(color: Colors.white, width: 1) : null,
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10, height: 1, fontWeight: FontWeight.w700, color: Color(0xFF10141A)),
          ),
        ),
      ),
    );
    // só a etiqueta pega o toque: o resto da régua, embaixo da haste, continua sendo da régua
    return SizedBox(
      width: MarkerFlags.maxFlagWidth,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 1.5,
            child: IgnorePointer(child: ColoredBox(color: color)),
          ),
          Positioned(left: 0, top: 0, child: chip),
        ],
      ),
    );
  }
}
