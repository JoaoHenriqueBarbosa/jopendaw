/// Indicador discreto da sincronização no cabeçalho do projeto (ao lado do título) e o diálogo de conflito.
///
/// Um ícone e uma dica por fase: synced `cloud_done_outlined` "Sincronizado"; syncing `cloud_sync_outlined`
/// "Sincronizando"; offline `cloud_off_outlined` (âmbar) "Offline (tentando de novo…)"; conflict
/// `sync_problem_outlined` (vermelho, abre o diálogo); error `error_outline` (vermelho). Off não mostra nada.
library;

import 'package:flutter/material.dart';

import '../widgets/format.dart';
import '../widgets/theme.dart';
import 'controller.dart';
import 'sync.dart';

class SyncIndicator extends StatefulWidget {
  final DawController c;
  const SyncIndicator({super.key, required this.c});

  @override
  State<SyncIndicator> createState() => _SyncIndicatorState();
}

class _SyncIndicatorState extends State<SyncIndicator> {
  bool _dialogOpen = false;
  bool _asked = false;

  SyncService get _sync => widget.c.sync;

  @override
  void initState() {
    super.initState();
    _sync.addListener(_onChange);
  }

  @override
  void dispose() {
    _sync.removeListener(_onChange);
    super.dispose();
  }

  /// O conflito aparece sozinho uma vez; depois só pelo clique no ícone (a pessoa pode estar
  /// no meio de uma edição e querer decidir depois).
  void _onChange() {
    if (_sync.phase != SyncPhase.conflict) {
      _asked = false;
    } else if (!_asked && !_dialogOpen) {
      _asked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _sync.phase == SyncPhase.conflict) _openDialog();
      });
    }
  }

  Future<void> _openDialog() async {
    if (_dialogOpen) return;
    _dialogOpen = true;
    await showSyncConflictDialog(context, _sync);
    _dialogOpen = false;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _sync,
      builder: (context, _) {
        final s = _sync;
        if (s.phase == SyncPhase.off) return const SizedBox.shrink();
        final (icon, color, tip) = switch (s.phase) {
          SyncPhase.synced => (Icons.cloud_done_outlined, Colors.white54, 'Sincronizado'),
          SyncPhase.syncing => (
            Icons.cloud_sync_outlined,
            Theme.of(context).colorScheme.primary,
            s.filesTotal > 0 ? 'Sincronizando (${s.filesDone}/${plural(s.filesTotal, 'arquivo')})' : 'Sincronizando',
          ),
          SyncPhase.offline => (
            Icons.cloud_off_outlined,
            Colors.amber,
            'Offline (tentando de novo${s.retryIn == null ? '' : ' em ${s.retryIn!.inSeconds} s'})',
          ),
          SyncPhase.conflict => (Icons.sync_problem_outlined, Palette.danger, s.message ?? 'Conflito: o projeto mudou em outro aparelho. Toque para resolver'),
          SyncPhase.error => (Icons.error_outline, Palette.danger, s.message ?? 'Não deu para sincronizar'),
          SyncPhase.off => (Icons.cloud_off_outlined, Colors.white24, ''),
        };
        return IconButton(
          tooltip: tip,
          onPressed: s.phase == SyncPhase.conflict ? _openDialog : null,
          icon: Icon(icon, size: 20, color: color),
        );
      },
    );
  }
}

/// Pergunta o que fazer quando o servidor e este aparelho mudaram o projeto. Nada é sobrescrito
/// antes da escolha; "Decidir depois" deixa o conflito de pé (o ícone reabre).
Future<void> showSyncConflictDialog(BuildContext context, SyncService sync) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      scrollable: true,
      title: const Text('O projeto mudou em outro aparelho'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: const Text(
          'Há uma versão mais nova no servidor e também mudanças feitas aqui que ainda não foram enviadas. '
          'Nada foi sobrescrito. Escolha qual vale:\n\n'
          '• Usar a versão do servidor: descarta as mudanças deste aparelho (não dá para desfazer).\n'
          '• Manter esta e enviar: a versão do servidor é substituída pela daqui.',
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Decidir depois')),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: Theme.of(ctx).colorScheme.error),
          onPressed: () {
            Navigator.pop(ctx);
            sync.useServer();
          },
          child: const Text('Usar a versão do servidor'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(ctx);
            sync.keepLocal();
          },
          child: const Text('Manter esta e enviar'),
        ),
      ],
    ),
  );
}
