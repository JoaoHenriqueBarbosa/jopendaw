/// A interface das pastas de faixa: a linha de cabeçalho da pasta no arranjo, o diálogo "Agrupar em
/// pasta", os itens de menu das faixas, a miniatura dos clipes da pasta recolhida e a barra de grupo
/// do mixer. A lógica (modelo, agrupar, desagrupar, mover) está em `track_groups.dart`.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../widgets/dialogs.dart';
import '../widgets/feedback.dart';
import '../widgets/format.dart';
import '../widgets/theme.dart';
import 'controller.dart';
import 'instruments.dart' show TrackKind;
import 'meter.dart';
import 'model.dart';
import 'structure_menu.dart' show confirmGroupRoute, moveTrackAsking;
import 'timeline.dart' show ToggleChip;
import 'track_groups.dart';

/// Altura da barra que marca o grupo em cima dos canais do mixer.
const groupBarHeight = 14.0;

// ---------------------------------------------------------------------- diálogos e ações

/// "Agrupar em pasta": nome e as faixas que entram ([preselect] já marcada). Só listam as faixas
/// que podem entrar (áudio e instrumento fora de pasta).
Future<void> showGroupDialog(BuildContext context, DawController c, {String? preselect}) => showDialog<void>(
  context: context,
  builder: (_) => _GroupDialog(c: c, preselect: preselect),
);

class _GroupDialog extends StatefulWidget {
  final DawController c;
  final String? preselect;
  const _GroupDialog({required this.c, this.preselect});

  @override
  State<_GroupDialog> createState() => _GroupDialogState();
}

class _GroupDialogState extends State<_GroupDialog> {
  late final TextEditingController _name;
  late final Set<String> _picked;
  String? _error;

  DawController get c => widget.c;

  List<DawTrack> get _eligible => [
    for (final t in c.doc.tracks)
      if (c.whyNotGroupable(t) == null) t,
  ];

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: c.nextGroupName());
    _picked = {if (widget.preselect != null) widget.preselect!};
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    // faixa que já saía para outro barramento passa a sair na pasta: avisa antes de trocar
    final notes = c.groupNotes(_picked);
    if (notes.isNotEmpty && !await confirmGroupRoute(context, title: 'Agrupar as faixas?', lines: notes, action: 'Agrupar')) return;
    if (!mounted) return;
    final r = c.groupTracks(_picked, name: _name.text);
    if (r.error != null) {
      setState(() => _error = r.error);
      return;
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final tracks = _eligible;
    final all = tracks.isNotEmpty && tracks.every((t) => _picked.contains(t.id));
    final caption = Theme.of(context).textTheme.bodySmall!.copyWith(color: Colors.white60);
    return AlertDialog(
      scrollable: true,
      title: const Text('Agrupar em pasta'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const ValueKey('group-name'),
              controller: _name,
              maxLength: 60,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Nome da pasta'),
              onSubmitted: (_) => _picked.isEmpty ? null : _submit(),
            ),
            Row(
              children: [
                Expanded(child: Text('Faixas da pasta (${_picked.length} de ${tracks.length})', style: Theme.of(context).textTheme.labelLarge)),
                TextButton(
                  onPressed: tracks.isEmpty
                      ? null
                      : () => setState(() {
                          if (all) {
                            _picked.clear();
                          } else {
                            _picked.addAll(tracks.map((t) => t.id));
                          }
                        }),
                  child: Text(all ? 'Nenhuma' : 'Todas'),
                ),
              ],
            ),
            if (tracks.isEmpty)
              Text('Não há faixa livre para agrupar: só faixas de áudio e de instrumento fora de pasta entram.', style: caption)
            else
              for (final t in tracks)
                CheckboxListTile(
                  key: ValueKey('group-pick:${t.id}'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _picked.contains(t.id),
                  onChanged: (v) => setState(() => v == true ? _picked.add(t.id) : _picked.remove(t.id)),
                  secondary: Icon(t.kind.icon, size: 16, color: trackColorAt(t.color)),
                  title: Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
            const SizedBox(height: 8),
            Text(
              'A pasta é um barramento: o volume, o mudo, o solo e os efeitos dela valem para todas as faixas. '
              'A saída de cada faixa passa a ir para ela (os envios ficam como estão) e as faixas escolhidas '
              'ficam juntas, logo abaixo da pasta.',
              style: caption,
            ),
            if (_error != null) ...[const SizedBox(height: 8), InlineNotice(_error!)],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(key: const ValueKey('group-confirm'), onPressed: _picked.isEmpty ? null : _submit, child: const Text('Agrupar')),
      ],
    );
  }
}

/// Um aviso simples de "não dá" (pasta dentro de pasta, barramento em pasta).
Future<void> _notice(BuildContext context, String title, String message) => showDialog<void>(
  context: context,
  builder: (ctx) => AlertDialog(
    title: Text(title),
    content: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: Text(message)),
    actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Entendi'))],
  ),
);

/// Desagrupar com confirmação.
Future<void> confirmUngroup(BuildContext context, DawController c, String folderId) async {
  final i = c.doc.tracks.indexWhere((t) => t.isGroup && t.id == folderId);
  if (i < 0) return;
  final t = c.doc.tracks[i];
  final n = c.doc.groupSize(i);
  final ok = await confirmAction(
    context,
    title: 'Desagrupar "${t.name}"?',
    message: c.ungroupKeepsRoutes(t)
        ? '${plural(n, 'faixa')} da pasta continuam no projeto. Como a pasta tem efeitos, automação ou envios, ela fica como um barramento comum e '
              'as faixas seguem saindo nele (mandá-las ao Master deixaria o efeito sem entrada). Dá para desfazer.'
        : '${plural(n, 'faixa')} da pasta continuam no projeto e voltam a sair direto no Master. O barramento da pasta some; '
              'se ele receber de outras faixas, fica como um barramento comum. Dá para desfazer.',
    action: 'Desagrupar',
    destructive: true,
  );
  if (ok) c.ungroup(folderId);
}

/// "Apagar a pasta (as faixas ficam)": some o barramento da pasta com o que há nele (efeitos,
/// automação, envios); as faixas dela continuam, soltas, saindo no Master.
Future<void> confirmDeleteGroup(BuildContext context, DawController c, String folderId) async {
  final i = c.doc.tracks.indexWhere((t) => t.isGroup && t.id == folderId);
  if (i < 0) return;
  final t = c.doc.tracks[i];
  final n = c.doc.groupSize(i);
  final ok = await confirmAction(
    context,
    title: 'Apagar a pasta "${t.name}"?',
    message:
        '${plural(n, 'faixa')} da pasta ficam no projeto, soltas e saindo no Master. O barramento da pasta, com os efeitos, a automação e '
        'os envios dele, é apagado (e o que outras faixas mandavam para ele). Dá para desfazer.',
    action: 'Apagar a pasta',
    destructive: true,
  );
  if (ok) c.removeTrack(c.doc.tracks.indexWhere((x) => x.id == folderId));
}

/// Itens do menu da faixa para pastas (agrupar, tirar da pasta, mover para outra pasta). Vazio para
/// pasta (que tem o menu próprio).
List<PopupMenuEntry<String>> groupMenuItems(DawController c, int index) {
  final t = c.doc.tracks[index];
  if (t.isGroup) return const [];
  final out = <PopupMenuEntry<String>>[];
  final inGroup = c.doc.folderOf(index) >= 0;
  if (inGroup) {
    out.add(const PopupMenuItem(value: 'grp:leave', child: Text('Tirar da pasta')));
  } else {
    out.add(const PopupMenuItem(value: 'grp:new', child: Text('Agrupar em pasta…')));
  }
  if (t.kind != TrackKind.bus) {
    for (final f in c.doc.tracks) {
      if (f.isGroup && f.id != t.groupId) out.add(PopupMenuItem(value: 'grp:join:${f.id}', child: Text('Mover para a pasta "${f.name}"')));
    }
  }
  return out;
}

/// Trata um item de [groupMenuItems] (`grp:...`).
Future<void> onGroupMenu(BuildContext context, DawController c, int index, String value) async {
  if (index < 0 || index >= c.doc.tracks.length) return;
  final t = c.doc.tracks[index];
  switch (value) {
    case 'grp:new':
      final why = c.whyNotGroupable(t);
      if (why != null) {
        await _notice(context, 'Não dá para agrupar', why);
        return;
      }
      if (context.mounted) await showGroupDialog(context, c, preselect: t.id);
    case 'grp:leave':
      final notes = c.leaveGroupNotes(t.id);
      if (notes.isNotEmpty && !await confirmGroupRoute(context, title: 'Tirar "${t.name}" da pasta?', lines: notes, action: 'Tirar da pasta')) return;
      c.leaveGroup(t.id);
    default:
      if (value.startsWith('grp:join:')) {
        final why = t.kind == TrackKind.bus ? 'Só faixas de áudio e de instrumento entram numa pasta: "${t.name}" é um barramento.' : null;
        if (why != null) {
          await _notice(context, 'Não dá para agrupar', why);
          return;
        }
        final folderId = value.substring('grp:join:'.length);
        final notes = c.joinGroupNotes(t.id, folderId);
        final fname = c.doc.tracks.where((x) => x.id == folderId).firstOrNull?.name ?? '';
        if (notes.isNotEmpty &&
            !await confirmGroupRoute(context, title: 'Mover "${t.name}" para a pasta "$fname"?', lines: notes, action: 'Mover para a pasta')) {
          return;
        }
        c.joinGroup(t.id, folderId);
      }
  }
}

// ---------------------------------------------------------------------- cabeçalho da pasta

/// A linha da pasta no arranjo: seta de recolher/expandir, nome, M/S, volume do grupo e medidor.
class GroupHeader extends StatelessWidget {
  final DawController c;
  final int index;
  final double height;
  final bool compact;
  const GroupHeader({super.key, required this.c, required this.index, required this.height, required this.compact});

  Future<void> _rename(BuildContext context, DawTrack t) async {
    final name = await promptText(context, title: 'Nome da pasta', label: 'Nome', initial: t.name, action: 'Salvar', maxLength: 60);
    if (name == null || name.trim().isEmpty) return;
    c.edit((_) => t.name = name.trim());
  }

  void _toggleEffects() {
    if (c.dock == Dock.effects && c.effectsTrack == index) {
      c.setDock(Dock.none);
      return;
    }
    c.selectTrack(index);
    c.showEffects(index);
  }

  @override
  Widget build(BuildContext context) {
    final t = c.doc.tracks[index];
    final color = trackColorAt(t.color);
    final selected = c.selectedTrack == index;
    final n = c.doc.groupSize(index);
    final chip = compact ? 20.0 : 24.0;
    final gap = compact ? 2.0 : 4.0;
    const volume = AutoTarget(AutoKind.volume);
    return GestureDetector(
      onTap: () => c.selectTrack(index),
      child: Container(
        key: ValueKey('group-header:${t.id}'),
        height: height,
        decoration: BoxDecoration(
          color: Color.alphaBlend(color.withValues(alpha: selected ? 0.16 : 0.09), selected ? Palette.overlay : Palette.bar),
          border: const Border(
            right: BorderSide(color: Palette.hairline),
            bottom: BorderSide(color: Palette.hairline),
          ),
        ),
        child: Row(
          children: [
            Container(width: 4, color: color),
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(compact ? 2 : 4, 6, compact ? 2 : 4, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: IconButton(
                            key: ValueKey('group-toggle:${t.id}'),
                            padding: EdgeInsets.zero,
                            iconSize: 20,
                            tooltip: t.collapsed ? 'Expandir a pasta' : 'Recolher a pasta',
                            onPressed: () => c.setGroupCollapsed(t.id, !t.collapsed),
                            icon: Icon(t.collapsed ? Icons.chevron_right : Icons.expand_more),
                          ),
                        ),
                        Icon(t.collapsed ? Icons.folder : Icons.folder_open, size: 16, color: color),
                        const SizedBox(width: 4),
                        Expanded(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onDoubleTap: () => _rename(context, t),
                            child: Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelLarge),
                          ),
                        ),
                        _GroupMenu(c: c, index: index, onRename: () => _rename(context, t)),
                      ],
                    ),
                    Row(
                      children: [
                        SizedBox(width: compact ? 2 : 4),
                        ToggleChip(
                          label: 'M',
                          width: chip,
                          on: t.mute,
                          color: Palette.danger,
                          tooltip: 'Mudo da pasta (cala todas as faixas dela)',
                          onTap: () => c.edit((_) => t.mute = !t.mute),
                        ),
                        SizedBox(width: gap),
                        ToggleChip(
                          label: 'S',
                          width: chip,
                          on: t.solo,
                          color: const Color(0xFFE3B341),
                          tooltip: 'Solo da pasta (deixa soar só as faixas dela)',
                          onTap: () => c.edit((_) => t.solo = !t.solo),
                        ),
                        SizedBox(width: gap),
                        SizedBox(
                          width: chip,
                          height: 24,
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            iconSize: 16,
                            tooltip: 'Efeitos da pasta',
                            style: IconButton.styleFrom(
                              backgroundColor: c.dock == Dock.effects && c.effectsTrack == index ? color.withValues(alpha: 0.22) : null,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                            ),
                            onPressed: _toggleEffects,
                            icon: Icon(Icons.tune, color: t.effects.isEmpty ? null : color),
                          ),
                        ),
                        if (compact)
                          Expanded(
                            child: Text(
                              '$n',
                              textAlign: TextAlign.end,
                              style: Theme.of(context).textTheme.labelSmall!.copyWith(color: Colors.white54),
                            ),
                          )
                        else ...[
                          const SizedBox(width: 4),
                          Text(plural(n, 'faixa'), style: Theme.of(context).textTheme.labelSmall!.copyWith(color: Colors.white54)),
                          Expanded(
                            child: ListenableBuilder(
                              listenable: Listenable.merge([c.beat, c.autoRec]),
                              builder: (_, _) {
                                final hand = c.autoRec.isRecording(index, volume);
                                final follows = c.automated(index, AutoKind.volume) && !hand;
                                final gain = follows ? c.liveValue(index, AutoKind.volume) : t.gain;
                                final automated = follows && c.playing.value;
                                return Tooltip(
                                  message: 'Volume da pasta: ${formatDb(gain)} dB',
                                  child: SliderTheme(
                                    data: SliderTheme.of(context).copyWith(
                                      activeTrackColor: automated ? automationColor : null,
                                      thumbColor: automated ? automationColor : null,
                                      trackHeight: 2,
                                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                                    ),
                                    child: SizedBox(
                                      height: 22,
                                      child: Slider(
                                        key: ValueKey('group-fader:${t.id}'),
                                        value: gainToFader(gain).clamp(0, 1),
                                        onChangeStart: (_) {
                                          c.autoRec.touch(index, volume);
                                          c.checkpoint();
                                        },
                                        onChanged: (v) {
                                          final g = faderToGain(v);
                                          c.autoRec.value(index, volume, g);
                                          c.mutate((d) => d.tracks[index].gain = g);
                                        },
                                        onChangeEnd: (_) => c.autoRec.release(index, volume),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Meter(peaks: c.peaks, index: index, width: 6),
            ),
            SizedBox(width: compact ? 4 : 6),
          ],
        ),
      ),
    );
  }
}

class _GroupMenu extends StatelessWidget {
  final DawController c;
  final int index;
  final VoidCallback onRename;
  const _GroupMenu({required this.c, required this.index, required this.onRename});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 28,
    height: 24,
    child: PopupMenuButton<String>(
      key: const ValueKey('group-menu'),
      padding: EdgeInsets.zero,
      iconSize: 18,
      tooltip: 'Opções da pasta',
      icon: const Icon(Icons.more_vert),
      onSelected: (v) async {
        final t = c.doc.tracks[index];
        switch (v) {
          case 'toggle':
            c.setGroupCollapsed(t.id, !t.collapsed);
          case 'all-collapse':
            c.setAllGroupsCollapsed(true);
          case 'all-expand':
            c.setAllGroupsCollapsed(false);
          case 'rename':
            onRename();
          case 'color':
            c.edit((_) => t.color = (t.color + 1) % Palette.tracks.length);
          case 'up':
            await moveTrackAsking(context, c, index, index - 1);
          case 'down':
            await moveTrackAsking(context, c, index, index + 1);
          case 'ungroup':
            await confirmUngroup(context, c, t.id);
          case 'delete':
            await confirmDeleteGroup(context, c, t.id);
        }
      },
      itemBuilder: (_) {
        final t = c.doc.tracks[index];
        final many = c.doc.tracks.where((x) => x.isGroup).length > 1;
        return [
          PopupMenuItem(value: 'toggle', child: Text(t.collapsed ? 'Expandir a pasta' : 'Recolher a pasta')),
          if (many) const PopupMenuItem(value: 'all-collapse', child: Text('Recolher todas as pastas')),
          if (many) const PopupMenuItem(value: 'all-expand', child: Text('Expandir todas as pastas')),
          const PopupMenuItem(value: 'rename', child: Text('Renomear')),
          const PopupMenuItem(value: 'color', child: Text('Trocar a cor')),
          PopupMenuItem(value: 'up', enabled: index > 0, child: const Text('Mover para cima')),
          PopupMenuItem(value: 'down', enabled: index < c.doc.tracks.length - 1, child: const Text('Mover para baixo')),
          const PopupMenuItem(value: 'ungroup', child: Text('Desagrupar…')),
          const PopupMenuItem(value: 'delete', child: Text('Apagar a pasta (as faixas ficam)…')),
        ];
      },
    ),
  );
}

/// A tira colorida na esquerda do cabeçalho de uma faixa que está numa pasta.
class GroupIndent extends StatelessWidget {
  final Color color;
  const GroupIndent({super.key, required this.color});

  @override
  Widget build(BuildContext context) => Container(width: 8, color: color.withValues(alpha: 0.35));
}

// ---------------------------------------------------------------------- raia da pasta

/// Miniatura dos clipes das filhas na linha da pasta recolhida: uma faixinha por filha, com a cor
/// dela. Fica por cima da raia da pasta e não pega toques.
class GroupMiniLane extends StatelessWidget {
  final DawController c;
  final int index;
  final double scrollBeat, pxPerBeat;
  const GroupMiniLane({super.key, required this.c, required this.index, required this.scrollBeat, required this.pxPerBeat});

  @override
  Widget build(BuildContext context) {
    final doc = c.doc;
    final bands = <(Color, List<(double, double)>)>[
      for (final i in doc.membersOf(index))
        (
          trackColorAt(doc.tracks[i].color),
          [for (final clip in doc.tracks[i].clips) (clip.start, doc.clipEnd(clip)), for (final clip in doc.tracks[i].midi) (clip.start, clip.end)],
        ),
    ];
    return IgnorePointer(
      child: CustomPaint(painter: _MiniLanePainter(bands, scrollBeat, pxPerBeat), size: Size.infinite),
    );
  }
}

class _MiniLanePainter extends CustomPainter {
  final List<(Color, List<(double, double)>)> bands;
  final double scroll, ppb;
  const _MiniLanePainter(this.bands, this.scroll, this.ppb);

  @override
  void paint(Canvas canvas, Size size) {
    if (bands.isEmpty) return;
    const pad = 6.0;
    final band = math.max(1.5, (size.height - 2 * pad) / bands.length);
    final h = math.max(1.0, math.min(band - 1, 8.0));
    for (var i = 0; i < bands.length; i++) {
      final y = pad + i * band;
      if (y + h > size.height) break;
      final paint = Paint()..color = bands[i].$1.withValues(alpha: 0.75);
      for (final (s, e) in bands[i].$2) {
        final x0 = (s - scroll) * ppb, x1 = math.max(x0 + 2, (e - scroll) * ppb);
        if (x1 < 0 || x0 > size.width) continue;
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTRB(math.max(0, x0), y, math.min(size.width, x1), y + h), const Radius.circular(1.5)), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_MiniLanePainter old) => true;
}

// ---------------------------------------------------------------------- mixer

/// A barra em cima dos canais do mixer: sobre o canal da pasta, o rótulo "Grupo"; sobre as filhas,
/// a mesma cor mais fraca, ligando tudo numa peça. Fora de pasta é só o vão (para os canais ficarem
/// alinhados). [stripWidth] é a largura do canal; [gap] a folga entre canais.
class GroupBar extends StatelessWidget {
  final DawDoc doc;
  final int index;
  final double stripWidth, gap;
  const GroupBar({super.key, required this.doc, required this.index, required this.stripWidth, required this.gap});

  @override
  Widget build(BuildContext context) {
    final t = doc.tracks[index];
    final folder = t.isGroup ? index : doc.folderOf(index);
    if (folder < 0) return SizedBox(height: groupBarHeight, width: stripWidth + gap);
    final color = trackColorAt(doc.tracks[folder].color);
    final last = index == folder ? doc.groupSize(folder) == 0 : doc.membersOf(folder).last == index;
    final first = index == folder;
    return SizedBox(
      height: groupBarHeight,
      width: stripWidth + gap,
      child: Padding(
        padding: EdgeInsets.only(right: last ? gap : 0, bottom: 2),
        child: Container(
          key: ValueKey(first ? 'group-bar:${t.id}' : 'group-member:${t.id}'),
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: first ? 0.85 : 0.35),
            borderRadius: BorderRadius.horizontal(left: Radius.circular(first ? 5 : 0), right: Radius.circular(last ? 5 : 0)),
          ),
          child: first
              ? const Text(
                  'Grupo',
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: TextStyle(fontSize: 10, height: 1.1, fontWeight: FontWeight.w700, color: Colors.black87),
                )
              : null,
        ),
      ),
    );
  }
}
