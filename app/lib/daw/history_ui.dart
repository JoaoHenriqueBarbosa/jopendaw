/// O painel "Histórico" (lista de passos do desfazer), os botões Desfazer/Refazer com o menu de
/// pressão longa e o item de menu que abre o painel e as versões. A pilha mora no controlador
/// (`history.dart`); as versões nomeadas ficam em `snapshots_ui.dart`.
library;

import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart';

import '../widgets/feedback.dart';
import '../widgets/format.dart';
import '../widgets/theme.dart';
import 'controller.dart';
import 'history.dart';
import 'snapshots_ui.dart';

/// Abre o painel do histórico.
Future<void> showHistoryDialog(BuildContext context, DawController c) => showDialog<void>(
  context: context,
  builder: (_) => HistoryDialog(c: c),
);

/// "Desfazer: Mover clipe", ou só "Desfazer (Ctrl+Z)" sem passo.
String undoTooltipText(DawController c) => withMod(c.nextUndo == null ? 'Desfazer (Ctrl+Z)' : '${undoTooltip('Desfazer', c.nextUndo)} (Ctrl+Z)');
String redoTooltipText(DawController c) => withMod(c.nextRedo == null ? 'Refazer (Ctrl+Shift+Z)' : '${undoTooltip('Refazer', c.nextRedo)} (Ctrl+Shift+Z)');

/// Valores do menu dos botões desfazer e refazer.
enum HistoryMenuChoice { history, versions, saveVersion }

/// Abre o menu de histórico e versões na posição dada (o botão direito e a pressão longa dos botões usam).
Future<void> showHistoryMenu(BuildContext context, DawController c, Offset at) async {
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  final choice = await showMenu<HistoryMenuChoice>(
    context: context,
    position: RelativeRect.fromRect(at & const Size(1, 1), Offset.zero & overlay.size),
    items: [
      PopupMenuItem(value: HistoryMenuChoice.history, child: _MenuRow(Icons.history, 'Histórico… (${c.historyCount})')),
      const PopupMenuItem(value: HistoryMenuChoice.versions, child: _MenuRow(Icons.bookmarks_outlined, 'Versões…')),
      const PopupMenuItem(value: HistoryMenuChoice.saveVersion, child: _MenuRow(Icons.bookmark_add_outlined, 'Salvar versão…')),
    ],
  );
  if (choice == null || !context.mounted) return;
  await runHistoryChoice(context, c, choice);
}

Future<void> runHistoryChoice(BuildContext context, DawController c, HistoryMenuChoice choice) {
  switch (choice) {
    case HistoryMenuChoice.history:
      return showHistoryDialog(context, c);
    case HistoryMenuChoice.versions:
      return showVersionsDialog(context, c);
    case HistoryMenuChoice.saveVersion:
      return saveVersionFlow(context, c);
  }
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _MenuRow(this.icon, this.text);

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 18),
      const SizedBox(width: 10),
      Flexible(child: Text(text)),
    ],
  );
}

/// Um botão da barra (desfazer ou refazer) com o tooltip do passo e o menu de histórico no botão direito e na pressão longa.
class HistoryStepButton extends StatelessWidget {
  final DawController c;
  final bool redo;

  /// Desligado durante a gravação (desfazer no meio dela poderia apagar a faixa que recebe o áudio).
  final bool blocked;
  const HistoryStepButton({super.key, required this.c, required this.redo, this.blocked = false});

  @override
  Widget build(BuildContext context) {
    final enabled = (redo ? c.canRedo : c.canUndo) && !blocked;
    return Listener(
      // botão direito do mouse (o de toque usa a pressão longa logo abaixo)
      onPointerDown: (e) {
        if (e.buttons == kSecondaryButton) showHistoryMenu(context, c, e.position);
      },
      child: GestureDetector(
        onLongPressStart: (d) => showHistoryMenu(context, c, d.globalPosition),
        // o tooltip só aparece com o mouse em cima: a pressão longa do toque é do menu
        child: Tooltip(
          message: redo ? redoTooltipText(c) : undoTooltipText(c),
          triggerMode: TooltipTriggerMode.manual,
          child: IconButton(
            key: ValueKey(redo ? 'redo-button' : 'undo-button'),
            onPressed: enabled ? (redo ? c.redo : c.undo) : null,
            icon: Icon(redo ? Icons.redo : Icons.undo),
          ),
        ),
      ),
    );
  }
}

/// O painel: passos do mais recente ao mais antigo, o de agora destacado; tocar num passo leva o projeto até ele.
class HistoryDialog extends StatelessWidget {
  final DawController c;
  const HistoryDialog({super.key, required this.c});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Dialog(
      backgroundColor: Palette.overlay,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 620),
        child: ListenableBuilder(
          listenable: c,
          builder: (context, _) {
            final rows = c.historyRows;
            final recording = c.recording;
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.history),
                      const SizedBox(width: 10),
                      Expanded(child: Text('Histórico', style: Theme.of(context).textTheme.titleLarge)),
                    ],
                  ),
                  Text(
                    '${plural(c.historyCount, 'passo')} (máx. $historyLimit)',
                    key: const ValueKey('history-count'),
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  const SizedBox(height: 4),
                  Flexible(
                    child: CustomScrollView(
                      shrinkWrap: true,
                      slivers: [
                        SliverToBoxAdapter(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Toque num passo para voltar (ou avançar) até ele de uma vez. Os passos em cinza foram desfeitos e ainda dá para refazer.',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              if (recording) ...[const SizedBox(height: 8), const InlineNotice('Parado durante a gravação.', error: false)],
                              const SizedBox(height: 8),
                              if (rows.length == 1)
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 24),
                                  child: Text('Nenhuma edição ainda: o que você fizer no projeto aparece aqui.', key: ValueKey('history-empty')),
                                ),
                            ],
                          ),
                        ),
                        if (rows.length > 1)
                          SliverList.builder(
                            itemCount: rows.length,
                            itemBuilder: (context, i) {
                              final s = rows[i];
                              final dim = s.future;
                              return ListTile(
                                key: ValueKey('history-step-${s.position}'),
                                dense: true,
                                selected: s.current,
                                selectedTileColor: scheme.primary.withValues(alpha: 0.16),
                                enabled: !recording,
                                leading: Icon(s.current ? Icons.radio_button_checked : (s.future ? Icons.redo : Icons.circle_outlined), size: 18),
                                title: Text(
                                  stepText(s),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: dim ? TextStyle(color: scheme.onSurface.withValues(alpha: 0.5), fontStyle: FontStyle.italic) : null,
                                ),
                                subtitle: s.current ? const Text('Estado de agora') : null,
                                trailing: s.labeled && s.time != null ? Text(formatClock24(s.time!), style: Theme.of(context).textTheme.labelSmall) : null,
                                onTap: s.current ? null : () => c.jumpToHistory(s.position),
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      TextButton.icon(
                        key: const ValueKey('history-clear'),
                        onPressed: c.historyCount == 0 ? null : () => _clear(context),
                        icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                        label: const Text('Limpar histórico'),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          Navigator.pop(context);
                          await showVersionsDialog(context, c);
                        },
                        icon: const Icon(Icons.bookmarks_outlined, size: 18),
                        label: const Text('Versões…'),
                      ),
                      FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Fechar')),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _clear(BuildContext context) async {
    final ok = await confirmClear(context);
    if (ok) c.clearHistory();
  }
}

/// "Limpar o histórico?": o documento fica como está, só some o desfazer.
Future<bool> confirmClear(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      scrollable: true,
      title: const Text('Limpar o histórico?'),
      content: const Text('O projeto fica como está, mas não dá mais para desfazer o que foi feito até aqui. As versões salvas não mudam.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
        FilledButton(key: const ValueKey('history-clear-confirm'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Limpar')),
      ],
    ),
  );
  return ok == true;
}
