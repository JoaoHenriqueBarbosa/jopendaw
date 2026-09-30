/// Menus da barra para navegar e enquadrar o projeto: Seções (marcadores e loops), Visão (zoom,
/// altura das faixas, seguir o cursor, régua) e a duração do projeto.
library;

import 'package:flutter/material.dart';

import '../widgets/dialogs.dart';
import '../widgets/theme.dart';
import 'controller.dart';
import 'model.dart';
import 'keymap.dart';

Widget _row(IconData icon, String text, {Color? color}) => Row(
  children: [
    Icon(icon, size: 18, color: color),
    const SizedBox(width: 12),
    Flexible(child: Text(text, overflow: TextOverflow.ellipsis)),
  ],
);

/// Marcadores do projeto: clicar num leva o cursor até lá; embaixo, criar marcador e os loops.
class SectionsMenu extends StatelessWidget {
  final DawController c;
  const SectionsMenu({super.key, required this.c});

  void _pick(String v) {
    if (v.startsWith('m:')) {
      final m = c.markerById(v.substring(2));
      if (m == null) return;
      c.selectedMarker = m.id;
      c.goTo(m.beat);
      return;
    }
    switch (v) {
      case 'add':
        c.addMarker();
      case 'between':
        c.loopBetweenMarkers();
      case 'section':
        c.loopSection();
      case 'selection':
        c.loopSelection();
    }
  }

  @override
  Widget build(BuildContext context) {
    final markers = c.doc.markers;
    return PopupMenuButton<String>(
      tooltip: 'Seções e marcadores (M cria um no cursor)',
      icon: Icon(Icons.flag_outlined, color: markers.isEmpty ? null : Palette.accent),
      onSelected: _pick,
      itemBuilder: (_) => [
        if (markers.isEmpty) const PopupMenuItem<String>(enabled: false, child: Text('Nenhum marcador ainda')),
        for (final m in markers)
          PopupMenuItem(
            value: 'm:${m.id}',
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: Color(m.color), shape: BoxShape.circle),
                ),
                const SizedBox(width: 10),
                Flexible(child: Text(m.name.isEmpty ? 'Marcador' : m.name, overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 12),
                Text(formatPosition(m.beat, c.doc.beatsPerBar, meter: c.doc.meter), style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
          ),
        const PopupMenuDivider(),
        PopupMenuItem(value: 'add', child: _row(Icons.add, 'Marcador no cursor${shortcutHint('marker.add')}')),
        PopupMenuItem(enabled: c.canLoopBetweenMarkers, value: 'between', child: _row(Icons.repeat, 'Loop entre marcadores')),
        PopupMenuItem(enabled: c.canLoopSection, value: 'section', child: _row(Icons.repeat_on, 'Loop desta seção')),
        PopupMenuItem(enabled: c.canLoopSelection, value: 'selection', child: _row(Icons.repeat_one, 'Loop no clipe selecionado${shortcutHint('loop.clip')}')),
      ],
    );
  }
}

/// O plural que o menu Visão usa (P/M/G não são atalhos, então a letra não aparece).
const _laneScalePlural = {LaneScale.small: 'pequenas', LaneScale.medium: 'médias', LaneScale.large: 'grandes'};

/// Zoom e visão: enquadrar, altura das faixas, seguir o cursor e a régua em tempo.
class ViewMenu extends StatelessWidget {
  final DawController c;
  const ViewMenu({super.key, required this.c});

  void _pick(String v) {
    switch (v) {
      case 'all':
        c.fitAll();
      case 'sel':
        c.fitSelection();
      case 'follow':
        c.toggleFollow();
      case 'time':
        c.toggleRulerTime();
      default:
        if (v.startsWith('h:')) c.setLaneScale(LaneScale.values.byName(v.substring(2)));
    }
  }

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: 'Visão: enquadrar, altura das faixas, seguir o cursor',
    icon: Icon(Icons.zoom_out_map, color: c.follow ? null : Colors.white54),
    onSelected: _pick,
    itemBuilder: (_) => [
      PopupMenuItem(value: 'all', child: _row(Icons.fit_screen, 'Enquadrar tudo${shortcutHint('view.fitAll')}')),
      PopupMenuItem(value: 'sel', child: _row(Icons.center_focus_strong_outlined, 'Enquadrar a seleção${shortcutHint('view.fitClip')}')),
      const PopupMenuDivider(),
      for (final s in LaneScale.values) CheckedPopupMenuItem(value: 'h:${s.name}', checked: c.laneScale == s, child: Text('Faixas ${_laneScalePlural[s]}')),
      const PopupMenuDivider(),
      CheckedPopupMenuItem(value: 'follow', checked: c.follow, child: const Text('Seguir o cursor')),
      CheckedPopupMenuItem(value: 'time', checked: c.rulerTime, child: const Text('Régua em minutos e segundos')),
    ],
  );
}

/// Duração do projeto (fim do último clipe), discreta ao lado do transporte.
class DurationLabel extends StatelessWidget {
  final DawController c;
  const DurationLabel({super.key, required this.c});

  @override
  Widget build(BuildContext context) {
    final d = c.doc;
    // compassos que o projeto ocupa, contados pelo mapa de compassos
    final (lastBar, into) = d.meter.barOf(d.contentEnd);
    final bars = d.contentEnd <= 0 ? 0 : (into <= 1e-9 ? lastBar - 1 : lastBar);
    return Tooltip(
      message: 'Duração do projeto: ${formatClock(d.durationSeconds)} ($bars ${bars == 1 ? 'compasso' : 'compassos'})',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Text(
          formatClock(d.durationSeconds),
          style: Theme.of(context).textTheme.labelSmall!.copyWith(color: Colors.white54, fontFeatures: const [FontFeature.tabularFigures()]),
        ),
      ),
    );
  }
}

/// Pergunta antes de uma troca de saída por entrar ou sair de uma pasta, listando [lines]; o texto
/// é o das pastas (não o do barramento). Vale para "Tirar da pasta", "Mover para a pasta",
/// "Agrupar" e a saída do mixer. Devolve se o usuário confirmou.
Future<bool> confirmGroupRoute(BuildContext context, {required String title, required List<String> lines, required String action, String? intro}) =>
    confirmAction(
      context,
      title: title,
      message:
          '${intro ?? 'A pasta é um barramento: a faixa que entra ou sai dela troca de saída. Isto muda:'}\n'
          '${lines.map((b) => '• $b').join('\n')}\n\n${'Desfazer${shortcutHint('edit.undo')}'} traz de volta.',
      action: action,
      destructive: true,
    );

/// Move a faixa [from] para [to]. Se o movimento desfaria rotas entre barramentos (a ordem das
/// faixas é a ordem do sinal), ou trocaria a saída da faixa por entrar ou sair de uma pasta,
/// pergunta antes, listando o que muda; desfazer traz tudo de volta. O texto acompanha o motivo:
/// só o de barramento, só o de pasta ou os dois.
Future<void> moveTrackAsking(BuildContext context, DawController c, int from, int to) async {
  final broken = c.routesBrokenByMove(from, to, groups: false);
  final folder = c.groupNotesForMove(from, to);
  if (broken.isNotEmpty || folder.isNotEmpty) {
    final parts = [
      if (broken.isNotEmpty)
        'Barramento só manda sinal para um barramento que vem depois dele na lista. Mover a faixa para lá desfaz:\n'
            '${broken.map((b) => '• $b').join('\n')}',
      if (folder.isNotEmpty)
        '${broken.isEmpty ? 'A pasta é um barramento: a faixa que entra ou sai dela troca de saída. Isto muda' : 'Entrar ou sair de uma pasta também troca a saída. Muda'}:\n'
            '${folder.map((b) => '• $b').join('\n')}',
    ];
    final ok = await confirmAction(
      context,
      title: 'Mover a faixa?',
      message: '${parts.join('\n\n')}\n\n${'Desfazer${shortcutHint('edit.undo')}'} traz de volta.',
      action: 'Mover mesmo assim',
      destructive: true,
    );
    if (!ok) return;
  }
  c.moveTrack(from, to);
}
