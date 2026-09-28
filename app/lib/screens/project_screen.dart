import 'package:flutter/material.dart';

import '../api/client.dart';
import '../models/project.dart';
import '../widgets/api_state.dart';
import '../widgets/feedback.dart';
import '../widgets/page.dart';
import '../widgets/responsive_scaffold.dart';
import '../widgets/theme.dart';

/// Um projeto aberto. Por enquanto só o esqueleto do arranjo: a barra de transporte, a coluna das
/// faixas e a régua; o motor de áudio e a edição entram depois.
class ProjectScreen extends StatefulWidget {
  final String projectId;
  const ProjectScreen({super.key, required this.projectId});
  @override
  State<ProjectScreen> createState() => _ProjectScreenState();
}

class _ProjectScreenState extends State<ProjectScreen> with ApiState {
  Project? _project;

  @override
  void initState() {
    super.initState();
    reload();
  }

  @override
  Future<void> reload() => fetch(ApiClient.instance.project(widget.projectId), (v) => _project = v);

  @override
  Widget build(BuildContext context) {
    final p = _project;
    return PageScaffold(
      icon: Icons.graphic_eq,
      title: p?.name ?? 'Projeto',
      subtitle: p == null ? null : '${p.bpm} BPM · ${p.meter}',
      showBack: true,
      body: p == null ? (error != null ? ErrorState(error: error!, onRetry: reload) : const LoadingState()) : _Arrangement(project: p),
    );
  }
}

/// Transporte em cima, faixas à esquerda e a área do arranjo. No celular a coluna das faixas
/// estreita e o transporte fica embaixo, perto do polegar.
class _Arrangement extends StatelessWidget {
  final Project project;
  const _Arrangement({required this.project});

  @override
  Widget build(BuildContext context) {
    final desktop = isDesktop(context);
    final transport = const _Transport();
    final tracks = Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: desktop ? 220 : 120,
          decoration: const BoxDecoration(
            color: Palette.bar,
            border: Border(right: BorderSide(color: Palette.hairline)),
          ),
          child: ListView(
            children: [
              for (var i = 0; i < 4; i++)
                Container(
                  height: 64,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    border: const Border(bottom: BorderSide(color: Palette.hairline)),
                    gradient: LinearGradient(colors: [trackColorAt(i).withValues(alpha: 0.18), Colors.transparent], stops: const [0, 0.04]),
                  ),
                  alignment: Alignment.centerLeft,
                  child: Text('Faixa ${i + 1}', maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            color: Palette.ink,
            alignment: Alignment.center,
            child: const EmptyState(icon: Icons.multitrack_audio, title: 'Arranjo', message: 'Aqui entram os clipes de áudio e MIDI.'),
          ),
        ),
      ],
    );
    return Column(
      children: desktop ? [transport, Expanded(child: tracks)] : [Expanded(child: tracks), transport],
    );
  }
}

class _Transport extends StatelessWidget {
  const _Transport();

  @override
  Widget build(BuildContext context) => Container(
    height: 56,
    decoration: const BoxDecoration(
      color: Palette.bar,
      border: Border.symmetric(horizontal: BorderSide(color: Palette.hairline)),
    ),
    child: SafeArea(
      top: false,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(tooltip: 'Voltar ao início', onPressed: null, icon: const Icon(Icons.skip_previous)),
          IconButton(tooltip: 'Tocar', onPressed: null, icon: const Icon(Icons.play_arrow)),
          IconButton(tooltip: 'Parar', onPressed: null, icon: const Icon(Icons.stop)),
          IconButton(
            tooltip: 'Gravar',
            onPressed: null,
            icon: Icon(Icons.fiber_manual_record, color: Palette.danger.withValues(alpha: 0.5)),
          ),
          const SizedBox(width: 16),
          Text(
            '1.1.1',
            style: TextStyle(fontFeatures: const [FontFeature.tabularFigures()], color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    ),
  );
}
