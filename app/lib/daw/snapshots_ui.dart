/// As telas das versões nomeadas: "Salvar versão…", a lista "Versões…" (restaurar, comparar, renomear, duplicar como
/// projeto novo, apagar) e as opções das versões automáticas. A lógica e o guardado estão em `snapshots.dart`.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../api/client.dart';
import '../audio/engine.dart' show LocalStore;
import '../models/project.dart';
import '../widgets/feedback.dart';
import '../widgets/format.dart';
import '../widgets/theme.dart';
import 'controller.dart';
import 'snapshots.dart';

/// Cria o projeto novo a partir do documento de uma versão (trocável nos testes).
typedef DuplicateVersion = Future<Project> Function(Map<String, dynamic> doc, String name);

/// Abre um projeto pelo id (trocável nos testes; o padrão navega pelo roteador).
typedef OpenProject = void Function(BuildContext context, String id);

Future<Project> _duplicateWithApi(Map<String, dynamic> doc, String name) async {
  final api = ApiClient.instance;
  final existing = [for (final p in await api.projects()) p.name];
  return duplicateVersionAsProject(
    doc: doc,
    name: name,
    existingNames: existing,
    createProject: api.createProject,
    patchProject: api.patchProject,
    deleteProject: api.deleteProject,
    store: LocalStore.instance,
  );
}

void _openWithRouter(BuildContext context, String id) => GoRouter.maybeOf(context)?.go('/projetos/$id');

Future<void> showVersionsDialog(BuildContext context, DawController c, {DuplicateVersion? duplicate, OpenProject? open}) => showDialog<void>(
  context: context,
  builder: (_) => VersionsDialog(c: c, duplicate: duplicate ?? _duplicateWithApi, open: open ?? _openWithRouter),
);

/// Pede o nome (e a nota) de uma versão. null: cancelou.
Future<({String name, String note})?> promptVersion(
  BuildContext context, {
  required String title,
  required String action,
  String initialName = '',
  String initialNote = '',
  bool askNote = true,
}) => showDialog<({String name, String note})>(
  context: context,
  builder: (_) => _VersionNameDialog(title: title, action: action, initialName: initialName, initialNote: initialNote, askNote: askNote),
);

class _VersionNameDialog extends StatefulWidget {
  final String title, action, initialName, initialNote;
  final bool askNote;
  const _VersionNameDialog({required this.title, required this.action, required this.initialName, required this.initialNote, required this.askNote});

  @override
  State<_VersionNameDialog> createState() => _VersionNameDialogState();
}

class _VersionNameDialogState extends State<_VersionNameDialog> {
  late final _name = TextEditingController(text: widget.initialName);
  late final _note = TextEditingController(text: widget.initialNote);
  String? _error;

  @override
  void initState() {
    super.initState();
    // o nome padrão já vem selecionado: digitar substitui em vez de emendar
    _name.selection = TextSelection(baseOffset: 0, extentOffset: _name.text.length);
  }

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Dê um nome à versão.');
      return;
    }
    Navigator.pop(context, (name: name, note: _note.text.trim()));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text(widget.title),
    content: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const ValueKey('version-name'),
            controller: _name,
            autofocus: true,
            maxLength: 80,
            decoration: InputDecoration(labelText: 'Nome', errorText: _error),
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) => widget.askNote ? null : _submit(),
          ),
          if (widget.askNote) ...[
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('version-note'),
              controller: _note,
              maxLength: 300,
              maxLines: 3,
              minLines: 1,
              decoration: const InputDecoration(labelText: 'Nota (opcional)'),
            ),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
      FilledButton(key: const ValueKey('version-confirm'), onPressed: _submit, child: Text(widget.action)),
    ],
  );
}

/// "Salvar versão…" pelo menu: pede o nome e guarda. Devolve a mensagem para mostrar (ou null se cancelou).
Future<String?> saveVersionFlow(BuildContext context, DawController c, {void Function(String message)? onMessage}) async {
  final r = await promptVersion(context, title: 'Salvar versão', action: 'Salvar', initialName: 'Versão ${formatStamp(c.clock())}');
  if (r == null) return null;
  final message = await saveVersionNow(c, r.name, r.note);
  onMessage?.call(message);
  if (context.mounted && onMessage == null) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(message)));
  }
  return message;
}

/// Guarda a versão e conta o que aconteceu (igual à mais nova: não guarda outra).
Future<String> saveVersionNow(DawController c, String name, String note) async {
  try {
    final s = await c.versions.save(name: name, note: note);
    if (s == null) return 'O projeto está igual à versão mais nova: não guardei outra cópia idêntica.';
    return 'Versão “${s.name}” salva neste aparelho.';
  } catch (e) {
    return 'Não deu para salvar a versão: ${describeError(e)}';
  }
}

class VersionsDialog extends StatefulWidget {
  final DawController c;
  final DuplicateVersion duplicate;
  final OpenProject open;
  const VersionsDialog({super.key, required this.c, required this.duplicate, required this.open});

  @override
  State<VersionsDialog> createState() => _VersionsDialogState();
}

class _VersionsDialogState extends State<VersionsDialog> {
  DawController get c => widget.c;
  VersionKeeper get keeper => c.versions;

  VersionList? _list;
  VersionsPrefs _prefs = const VersionsPrefs();
  String? _info, _error;
  bool _busy = false;
  StreamSubscription<void>? _sub;

  /// O resumo da comparação aberto, por id da versão.
  final _diffs = <String, DocDiff?>{};
  Project? _created;

  @override
  void initState() {
    super.initState();
    _sub = keeper.changes.stream.listen((_) => _reload());
    unawaited(_reload());
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _reload() async {
    final prefs = await keeper.prefs();
    final list = await keeper.list();
    if (!mounted) return;
    setState(() {
      _prefs = prefs;
      _list = list;
    });
  }

  Future<void> _run(Future<void> Function() body) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
      _created = null;
    });
    try {
      await body();
    } catch (e) {
      if (mounted) setState(() => _error = 'Não deu certo: ${describeError(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final r = await promptVersion(context, title: 'Salvar versão', action: 'Salvar', initialName: 'Versão ${formatStamp(c.clock())}');
    if (r == null) return;
    await _run(() async {
      final m = await saveVersionNow(c, r.name, r.note);
      if (mounted) setState(() => _info = m);
    });
  }

  Future<void> _restore(Snapshot s) async {
    if (c.recording) {
      setState(() => _error = 'Pare a gravação antes de restaurar uma versão.');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        title: Text('Restaurar “${s.name}”?'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Text(
            'O projeto volta ao estado de ${formatStamp(s.createdAt)}. Antes disso, guardo uma versão “Antes de restaurar ${s.name}” com o que está agora, '
            'e o Desfazer também volta.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(key: const ValueKey('restore-confirm'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Restaurar')),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() async {
      final doc = await keeper.load(s.id);
      if (doc == null) {
        setState(() => _error = 'O arquivo desta versão está ilegível ou sumiu: não dá para restaurar.');
        await _reload();
        return;
      }
      await keeper.save(name: 'Antes de restaurar ${s.name}');
      final done = await c.restoreDocument(doc, label: 'Restaurar versão “${s.name}”');
      if (!mounted) return;
      setState(() {
        if (done) {
          _info = 'Versão “${s.name}” restaurada. Desfazer volta ao que era antes.';
        } else {
          _error = 'Não deu para restaurar esta versão.';
        }
      });
    });
  }

  Future<void> _compare(Snapshot s) async {
    if (_diffs.containsKey(s.id)) {
      setState(() => _diffs.remove(s.id));
      return;
    }
    await _run(() async {
      final doc = await keeper.load(s.id);
      if (doc == null) {
        setState(() => _error = 'O arquivo desta versão está ilegível ou sumiu.');
        return;
      }
      final now = c.doc.toJson();
      if (!mounted) return;
      setState(() => _diffs[s.id] = diffDocs(doc, now));
    });
  }

  Future<void> _rename(Snapshot s) async {
    final r = await promptVersion(context, title: 'Renomear versão', action: 'Salvar', initialName: s.name, initialNote: s.note);
    if (r == null) return;
    await _run(() async {
      final ok = await keeper.rename(s.id, r.name, note: r.note);
      if (!ok && mounted) setState(() => _error = 'Não deu para renomear: o arquivo da versão sumiu ou está ilegível.');
    });
  }

  Future<void> _delete(Snapshot s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        title: Text('Apagar “${s.name}”?'),
        content: const Text('Esta versão some do aparelho e não dá para recuperar. O projeto de agora não muda.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            key: const ValueKey('delete-confirm'),
            style: FilledButton.styleFrom(backgroundColor: Palette.danger, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Apagar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() async {
      await keeper.delete(s.id);
      _diffs.remove(s.id);
    });
  }

  Future<void> _duplicate(Snapshot s) async {
    final r = await promptVersion(
      context,
      title: 'Duplicar como projeto novo',
      action: 'Criar projeto',
      initialName: '${c.project.name} — ${s.name}',
      askNote: false,
    );
    if (r == null) return;
    await _run(() async {
      final doc = await keeper.load(s.id);
      if (doc == null) {
        setState(() => _error = 'O arquivo desta versão está ilegível ou sumiu.');
        return;
      }
      final p = await widget.duplicate(doc, r.name);
      if (mounted) {
        setState(() {
          _created = p;
          _info = 'Criei o projeto “${p.name}” com esta versão. Ele já está na sua lista de projetos.';
        });
      }
    });
  }

  Future<void> _setPrefs(VersionsPrefs p) async {
    setState(() => _prefs = p);
    await keeper.setPrefs(p);
  }

  @override
  Widget build(BuildContext context) {
    final list = _list;
    return Dialog(
      backgroundColor: Palette.overlay,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 700),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.bookmarks_outlined),
                  const SizedBox(width: 10),
                  Expanded(child: Text('Versões', style: Theme.of(context).textTheme.titleLarge)),
                  if (list != null)
                    Flexible(
                      child: Text(
                        '${plural(list.items.length, 'versão', 'versões')} · ${formatSize(list.totalBytes)}',
                        key: const ValueKey('versions-count'),
                        style: Theme.of(context).textTheme.labelMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Cópias do projeto inteiro (sem os áudios, que já ficam guardados à parte). Ficam só neste aparelho.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 10),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_error != null) ...[InlineNotice(_error!, onClose: () => setState(() => _error = null)), const SizedBox(height: 8)],
                      if (_info != null) ...[
                        InlineNotice(
                          _info!,
                          error: false,
                          onClose: () => setState(() => _info = null),
                          actionLabel: _created == null ? null : 'Abrir',
                          onAction: _created == null ? null : () => widget.open(context, _created!.id),
                        ),
                        const SizedBox(height: 8),
                      ],
                      if (list != null && list.overLimit) ...[
                        InlineNotice(
                          'As versões deste projeto já ocupam ${formatSize(list.totalBytes)} (mais de ${formatSize(list.warnBytes)}). '
                          'Apague as que não precisa mais para liberar espaço.',
                          key: const ValueKey('versions-overlimit'),
                        ),
                        const SizedBox(height: 8),
                      ],
                      if (list != null && list.corruptKeys.isNotEmpty) ...[
                        InlineNotice(
                          plural(list.corruptKeys.length, 'arquivo de versão está ilegível', 'arquivos de versão estão ilegíveis'),
                          key: const ValueKey('versions-corrupt'),
                          actionLabel: 'Limpar',
                          onAction: _busy ? null : () => _run(() => keeper.deleteCorrupt(list.corruptKeys)),
                        ),
                        const SizedBox(height: 8),
                      ],
                      Wrap(
                        spacing: 12,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          FilledButton.icon(
                            key: const ValueKey('versions-save'),
                            onPressed: _busy ? null : _save,
                            icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                            label: const Text('Salvar versão…'),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Switch(
                                key: const ValueKey('versions-auto'),
                                value: _prefs.auto,
                                onChanged: (v) => _setPrefs(VersionsPrefs(auto: v, minutes: _prefs.minutes)),
                              ),
                              const SizedBox(width: 4),
                              const Flexible(child: Text('Salvar automaticamente')),
                            ],
                          ),
                          if (_prefs.auto)
                            DropdownButton<int>(
                              key: const ValueKey('versions-minutes'),
                              value: autoMinuteChoices.contains(_prefs.minutes) ? _prefs.minutes : null,
                              hint: Text('a cada ${_prefs.minutes} min'),
                              items: [for (final m in autoMinuteChoices) DropdownMenuItem(value: m, child: Text('a cada $m min'))],
                              onChanged: (m) => m == null ? null : _setPrefs(VersionsPrefs(auto: true, minutes: m)),
                            ),
                        ],
                      ),
                      if (_prefs.auto)
                        Padding(
                          padding: const EdgeInsets.only(top: 2, bottom: 4),
                          child: Text(
                            'Guardo as últimas $autoKeep automáticas (também ao abrir o projeto depois de mais de 1 h). As que você salva nunca saem sozinhas.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      const Divider(height: 16),
                      if (list == null)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (list.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Text(noVersionsMessage, key: ValueKey('versions-empty')),
                        )
                      else
                        for (final s in list.items) _tile(context, s),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Fechar')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tile(BuildContext context, Snapshot s) {
    final theme = Theme.of(context);
    final diff = _diffs[s.id];
    return Card(
      key: ValueKey('version-${s.id}'),
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: Palette.raised,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (s.auto) const Padding(padding: EdgeInsets.only(right: 6), child: Icon(Icons.autorenew, size: 16)),
                Expanded(
                  child: Text(s.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
                ),
                PopupMenuButton<String>(
                  key: ValueKey('version-menu-${s.id}'),
                  tooltip: 'Mais ações',
                  enabled: !_busy,
                  onSelected: (v) {
                    switch (v) {
                      case 'rename':
                        _rename(s);
                      case 'duplicate':
                        _duplicate(s);
                      case 'delete':
                        _delete(s);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'rename', child: Text('Renomear…')),
                    PopupMenuItem(value: 'duplicate', child: Text('Duplicar como novo projeto…')),
                    PopupMenuItem(value: 'delete', child: Text('Apagar…')),
                  ],
                ),
              ],
            ),
            Text(
              '${formatStamp(s.createdAt)} · ${plural(s.tracks, 'faixa')} · ${plural(s.clips, 'clipe')} · ${formatSize(s.bytes)}${s.auto ? ' · automática' : ''}',
              style: theme.textTheme.bodySmall,
            ),
            if (s.note.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(s.note, style: theme.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic)),
              ),
            if (diff != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Container(
                  key: ValueKey('version-diff-${s.id}'),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Palette.ink, borderRadius: BorderRadius.circular(8)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Do projeto desta versão para o de agora:', style: theme.textTheme.labelSmall),
                      const SizedBox(height: 4),
                      Text(describeDiff(diff)),
                    ],
                  ),
                ),
              ),
            Wrap(
              spacing: 4,
              children: [
                TextButton(key: ValueKey('version-restore-${s.id}'), onPressed: _busy ? null : () => _restore(s), child: const Text('Restaurar')),
                TextButton(
                  key: ValueKey('version-compare-${s.id}'),
                  onPressed: _busy ? null : () => _compare(s),
                  child: Text(diff == null ? 'Comparar' : 'Fechar comparação'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
