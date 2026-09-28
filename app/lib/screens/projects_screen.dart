import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../api/client.dart';
import '../models/project.dart';
import '../widgets/api_state.dart';
import '../widgets/dialogs.dart';
import '../widgets/feedback.dart';
import '../widgets/format.dart';
import '../widgets/page.dart';
import '../widgets/theme.dart';

/// Os projetos da conta: uma grade que se ajusta à largura (uma coluna no celular, várias no
/// computador), criar, renomear e apagar.
class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({super.key});
  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> with ApiState {
  final _api = ApiClient.instance;
  List<Project>? _projects;

  @override
  void initState() {
    super.initState();
    reload();
  }

  @override
  Future<void> reload() => fetch(_api.projects(), (v) => _projects = v);

  Future<void> _create() async {
    final name = await promptText(context, title: 'Novo projeto', label: 'Nome', action: 'Criar', maxLength: 120);
    if (name == null || name.isEmpty) return;
    Project? created;
    await run(() async => created = await _api.createProject(name), reloadAfter: false);
    if (created != null && mounted) context.go('/projetos/${created!.id}');
  }

  Future<void> _rename(Project p) async {
    final name = await promptText(context, title: 'Renomear projeto', label: 'Nome', initial: p.name, action: 'Salvar', maxLength: 120);
    if (name == null || name.isEmpty || name == p.name) return;
    await run(() => _api.patchProject(p.id, {'name': name}));
  }

  Future<void> _delete(Project p) async {
    if (!await confirmDelete(context, title: 'Apagar "${p.name}"?', content: 'O projeto some para sempre, com tudo o que estiver nele.')) return;
    await run(() => _api.deleteProject(p.id), done: 'Projeto apagado.');
  }

  @override
  Widget build(BuildContext context) {
    final list = _projects;
    return PageScaffold(
      icon: Icons.library_music_outlined,
      title: 'Projetos',
      subtitle: list == null ? null : plural(list.length, 'projeto'),
      primary: (icon: Icons.add, label: 'Novo projeto', onPressed: busy ? null : _create),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          notices(padding: const EdgeInsets.fromLTRB(16, 16, 16, 0)),
          Expanded(child: _body(list)),
        ],
      ),
    );
  }

  Widget _body(List<Project>? list) {
    if (list == null) return error != null ? ErrorState(error: error!, onRetry: reload) : const LoadingState();
    if (list.isEmpty) {
      return EmptyState(
        icon: Icons.graphic_eq,
        title: 'Nenhum projeto ainda',
        message: 'Um projeto guarda as faixas, os clipes e a mixagem de uma música.',
        action: FilledButton.icon(onPressed: _create, icon: const Icon(Icons.add), label: const Text('Criar o primeiro')),
      );
    }
    return RefreshIndicator(
      onRefresh: reload,
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 360, mainAxisExtent: 132, crossAxisSpacing: 12, mainAxisSpacing: 12),
        itemCount: list.length,
        itemBuilder: (_, i) => _ProjectCard(
          project: list[i],
          color: trackColorAt(i),
          onOpen: () => context.go('/projetos/${list[i].id}'),
          onRename: () => _rename(list[i]),
          onDelete: () => _delete(list[i]),
        ),
      ),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  final Project project;
  final Color color;
  final VoidCallback onOpen, onRename, onDelete;
  const _ProjectCard({required this.project, required this.color, required this.onOpen, required this.onRename, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SectionIcon(Icons.graphic_eq, color: color),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      project.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  PopupMenuButton<VoidCallback>(
                    tooltip: 'Mais',
                    onSelected: (f) => f(),
                    itemBuilder: (_) => [
                      PopupMenuItem(value: onRename, child: const Text('Renomear')),
                      PopupMenuItem(value: onDelete, child: const Text('Apagar')),
                    ],
                  ),
                ],
              ),
              const Spacer(),
              Text('${project.bpm} BPM · ${project.meter} · ${(project.sampleRate / 1000).toStringAsFixed(1)} kHz', style: muted),
              const SizedBox(height: 2),
              Text('Mexido ${timeAgo(project.updatedAt)}', style: muted),
            ],
          ),
        ),
      ),
    );
  }
}
