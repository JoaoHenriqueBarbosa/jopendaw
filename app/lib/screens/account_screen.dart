import 'package:flutter/material.dart';

import '../api/client.dart';
import '../api/storage.dart';
import '../auth/session.dart';
import '../widgets/api_state.dart';
import '../widgets/dialogs.dart';
import '../widgets/format.dart';
import '../widgets/legal.dart';
import '../widgets/page.dart';

/// O aviso depois da limpeza de áudios sem uso, com o plural e o verbo concordando ("1 áudio apagado", "3 áudios apagados").
@visibleForTesting
String cleanupSummary(CleanupResult r) {
  if (r.removed == 0 && r.skippedRecent == 0) return 'Nada para apagar.';
  final n = r.skippedRecent;
  return [
    if (r.removed == 0)
      'Nada para apagar.'
    else
      'Liberei ${fmtBytes(r.freedBytes)} (${plural(r.removed, 'áudio')} ${r.removed == 1 ? 'apagado' : 'apagados'}).',
    if (n > 0) '${plural(n, 'áudio')} enviado${n == 1 ? '' : 's'} na última hora ${n == 1 ? 'ficou' : 'ficaram'} de fora.',
  ].join(' ');
}

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

  /// A última atualização da tela (`reload`) falhou depois de a ação já ter dado certo.
  bool _reloadFailed = false;

  static const _reloadWarning = 'Não deu para atualizar a tela; recarregue a página para ver o estado atual.';

  @override
  void initState() {
    super.initState();
    _loadUsage();
  }

  /// O uso do armazenamento é um extra da tela: se falhar, o resto da conta continua valendo (sem
  /// erro na frente da pessoa) e o cartão simplesmente não aparece.
  Future<void> _loadUsage() async {
    try {
      final u = await _api.storageUsage();
      if (mounted) setState(() => _usage = u);
    } catch (_) {}
  }

  /// Roda depois de uma ação que deu certo. Se atualizar a tela falha, a ação NÃO falhou: o `run` não pode mostrar
  /// isso como erro dela, então a falha vira só um aviso (ver [_finish]).
  @override
  Future<void> reload() async {
    _reloadFailed = false;
    try {
      await _session.refreshMe();
      final u = await _api.storageUsage();
      if (mounted) setState(() => _usage = u);
    } catch (_) {
      _reloadFailed = true;
    }
  }

  /// O aviso final de uma ação que deu certo: o texto do que foi feito e, se a tela não atualizou, o aviso disso.
  void _finish(String? result) {
    if (!mounted) return;
    final done = result ?? info;
    final text = [?done, if (_reloadFailed) _reloadWarning].join(' ');
    setState(() => info = text.isEmpty ? null : text);
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
    if (await run(() async => result = cleanupSummary(await _api.cleanupSamples()))) _finish(result);
  }

  Future<void> _deleteSample(StoredSample smp) async {
    // enviado na última hora: o projeto que o usa pode ainda não ter sincronizado, então a confirmação já avisa
    var force = smp.recent;
    for (;;) {
      if (!await confirmAction(
        context,
        title: force ? 'Áudio enviado há pouco' : 'Apagar este áudio?',
        message: force
            ? '${smp.name ?? 'Este áudio'} (${fmtBytes(smp.size)}) foi enviado na última hora e o projeto que o usa pode ainda não ter '
                  'sincronizado. Se ele estiver em uso, o projeto perde o som. Apagar mesmo assim? Não tem volta.'
            : '${smp.name ?? 'Áudio sem nome'} (${fmtBytes(smp.size)}) some do servidor. Não tem volta.',
        action: force ? 'Apagar mesmo assim' : 'Apagar',
        destructive: true,
      )) {
        return;
      }
      String? result;
      var refused = false;
      final ok = await run(() async {
        try {
          result = 'Liberei ${fmtBytes(await _api.deleteSample(smp.hash, force: force))}.';
        } on SampleRecent {
          refused = true;
        }
      });
      if (!mounted) return;
      if (ok && !refused) return _finish(result);
      // o servidor achou recente o que a tela não sabia: pergunta de novo, agora com o aviso
      if (!refused || force) return;
      force = true;
    }
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
                        '${fmtBytes(smp.size)} · ${smp.unused ? (smp.recent ? 'sem uso · recém-enviado' : 'sem uso') : 'em ${smp.projects.join(', ')}'}',
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
