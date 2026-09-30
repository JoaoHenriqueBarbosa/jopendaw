import 'package:flutter/material.dart';

import '../api/client.dart';
import '../api/storage.dart';
import '../auth/session.dart';
import '../widgets/api_state.dart';
import '../widgets/dialogs.dart';
import '../widgets/format.dart';
import '../widgets/legal.dart';
import '../widgets/page.dart';

/// A conta: nome, sair deste aparelho ou de todos, e apagar a conta.
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});
  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> with ApiState {
  final _session = Session.instance;
  final _api = ApiClient.instance;

  StorageUsage? _usage;

  @override
  Future<void> reload() async {
    await _session.refreshMe();
    // o uso do armazenamento é um extra da tela: se falhar, o resto da conta continua valendo
    await fetch(_api.storageUsage(), (u) => _usage = u);
  }

  Future<void> _cleanup() async {
    final u = _usage;
    if (u == null || u.unusedCount == 0) return;
    if (!await confirmAction(
      context,
      title: 'Apagar áudios sem uso?',
      message:
          '${plural(u.unusedCount, 'áudio')} (${fmtBytes(u.unusedBytes)}) que nenhum projeto usa serão apagados do servidor. '
          'Os arquivos guardados neste aparelho não mudam. Não tem volta.',
      action: 'Apagar',
      destructive: true,
    )) {
      return;
    }
    String? result;
    await run(() async {
      final r = await _api.cleanupSamples();
      result = r.removed == 0 ? 'Nada para apagar.' : 'Liberei ${fmtBytes(r.freedBytes)} (${plural(r.removed, 'áudio')} apagados).';
      if (r.skippedRecent > 0) result = '$result ${plural(r.skippedRecent, 'áudio')} enviado na última hora ficou de fora.';
    });
    if (mounted && result != null) setState(() => info = result);
  }

  Future<void> _deleteSample(StoredSample smp) async {
    if (!await confirmAction(
      context,
      title: 'Apagar este áudio?',
      message: '${smp.name ?? 'Áudio sem nome'} (${fmtBytes(smp.size)}) some do servidor. Não tem volta.',
      action: 'Apagar',
      destructive: true,
    )) {
      return;
    }
    String? result;
    await run(() async => result = 'Liberei ${fmtBytes(await _api.deleteSample(smp.hash))}.');
    if (mounted && result != null) setState(() => info = result);
  }

  Widget _storageCard(ThemeData theme) {
    final u = _usage;
    if (u == null) return const SizedBox.shrink();
    final full = u.fraction >= 0.9;
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Armazenamento de áudios', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: u.fraction, color: full ? theme.colorScheme.error : null),
            const SizedBox(height: 8),
            Text('${fmtBytes(u.usedBytes)} de ${fmtBytes(u.quotaBytes)} usados'),
            if (u.unusedCount > 0) ...[
              const SizedBox(height: 4),
              Text('${plural(u.unusedCount, 'áudio')} sem uso em nenhum projeto (${fmtBytes(u.unusedBytes)}).', style: theme.textTheme.bodySmall),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: busy ? null : _cleanup,
                  icon: const Icon(Icons.cleaning_services_outlined),
                  label: const Text('Limpar áudios sem uso'),
                ),
              ),
            ],
            if (u.samples.isNotEmpty)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text('Ver ${plural(u.samples.length, 'áudio')}'),
                children: [
                  for (final smp in u.samples)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(smp.name ?? 'Áudio sem nome', maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        '${fmtBytes(smp.size)} · ${smp.unused ? 'sem uso' : 'em ${smp.projects.join(', ')}'}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: smp.unused
                          ? IconButton(tooltip: 'Apagar', icon: const Icon(Icons.delete_outline), onPressed: busy ? null : () => _deleteSample(smp))
                          : null,
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _rename() async {
    final name = await promptText(context, title: 'Seu nome', label: 'Nome', initial: _session.user?.name ?? '', action: 'Salvar', maxLength: 80);
    if (name == null) return;
    await run(() => _api.patchMe(name: name), done: 'Nome salvo.');
  }

  Future<void> _logoutAll() async {
    if (!await confirmAction(
      context,
      title: 'Sair de todos os aparelhos?',
      message: 'Todas as sessões desta conta são encerradas, inclusive esta.',
      action: 'Sair de todos',
      destructive: true,
    )) {
      return;
    }
    await run(() async {
      await _api.logoutAll();
      await _session.signOut(notifyServer: false);
    }, reloadAfter: false);
  }

  Future<void> _delete() async {
    if (!await confirmAction(
      context,
      title: 'Apagar a conta?',
      message: 'A conta e todos os projetos dela somem para sempre. Não tem volta.',
      action: 'Apagar a conta',
      destructive: true,
    )) {
      return;
    }
    await run(() async {
      await _api.deleteAccount();
      await _session.signOut(notifyServer: false);
    }, reloadAfter: false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final u = _session.user;
    return PageScaffold(
      icon: Icons.account_circle_outlined,
      title: 'Conta',
      subtitle: u?.email,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  notices(padding: const EdgeInsets.only(bottom: 12)),
                  Card(
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.badge_outlined),
                          title: Text(u?.name.isNotEmpty == true ? u!.name : 'Sem nome'),
                          subtitle: const Text('Nome'),
                          trailing: const Icon(Icons.edit_outlined),
                          onTap: busy ? null : _rename,
                        ),
                        const Divider(),
                        ListTile(leading: const Icon(Icons.alternate_email), title: Text(u?.email ?? ''), subtitle: const Text('Email')),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _storageCard(theme),
                  Card(
                    child: Column(
                      children: [
                        ListTile(leading: const Icon(Icons.logout), title: const Text('Sair'), onTap: busy ? null : () => _session.signOut()),
                        const Divider(),
                        ListTile(leading: const Icon(Icons.devices_other), title: const Text('Sair de todos os aparelhos'), onTap: busy ? null : _logoutAll),
                        const Divider(),
                        ListTile(
                          leading: Icon(Icons.delete_forever_outlined, color: theme.colorScheme.error),
                          title: Text('Apagar a conta', style: TextStyle(color: theme.colorScheme.error)),
                          onTap: busy ? null : _delete,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const LegalLinks(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
