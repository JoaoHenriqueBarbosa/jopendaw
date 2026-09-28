import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/client.dart';
import '../daw/controller.dart';
import '../daw/mixer_panel.dart';
import '../daw/timeline.dart';
import '../daw/transport_bar.dart';
import '../models/project.dart';
import '../widgets/api_state.dart';
import '../widgets/feedback.dart';
import '../widgets/page.dart';
import '../widgets/responsive_scaffold.dart';

/// Um projeto aberto no DAW: transporte, arranjo e mixer. O áudio roda no aparelho; do servidor
/// vêm só o nome, o andamento e a fórmula de compasso.
class ProjectScreen extends StatefulWidget {
  final String projectId;
  const ProjectScreen({super.key, required this.projectId});
  @override
  State<ProjectScreen> createState() => _ProjectScreenState();
}

class _ProjectScreenState extends State<ProjectScreen> with ApiState {
  Project? _project;
  DawController? _daw;

  @override
  void initState() {
    super.initState();
    reload();
  }

  @override
  Future<void> reload() => fetch(ApiClient.instance.project(widget.projectId), (v) {
    _project = v;
    _daw ??= DawController(v)..open();
  });

  @override
  void dispose() {
    _daw?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = _project;
    final daw = _daw;
    return PageScaffold(
      icon: Icons.graphic_eq,
      title: p?.name ?? 'Projeto',
      subtitle: p == null ? null : '${p.bpm} BPM · ${p.meter}',
      showBack: true,
      body: daw == null
          ? (error != null ? ErrorState(error: error!, onRetry: reload) : const LoadingState())
          : ListenableBuilder(
              listenable: daw,
              builder: (context, _) {
                if (!daw.ready) {
                  return daw.error != null ? InlineNotice(daw.error!) : const LoadingState();
                }
                return _Studio(c: daw);
              },
            ),
    );
  }
}

/// Transporte, arranjo e o mixer embaixo quando aberto. No celular o transporte fica embaixo,
/// perto do polegar.
class _Studio extends StatelessWidget {
  final DawController c;
  const _Studio({required this.c});

  bool _typing() {
    final f = FocusManager.instance.primaryFocus?.context?.widget;
    return f is EditableText;
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent || _typing()) return KeyEventResult.ignored;
    final keys = HardwareKeyboard.instance;
    final mod = keys.isControlPressed || keys.isMetaPressed;
    final k = e.logicalKey;
    void Function()? action;
    if (k == LogicalKeyboardKey.space) {
      action = c.togglePlay;
    } else if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.home) {
      action = c.stop;
    } else if (k == LogicalKeyboardKey.delete || k == LogicalKeyboardKey.backspace) {
      action = c.deleteSelected;
    } else if (mod && k == LogicalKeyboardKey.keyZ) {
      action = keys.isShiftPressed ? c.redo : c.undo;
    } else if (mod && k == LogicalKeyboardKey.keyY) {
      action = c.redo;
    } else if (mod && k == LogicalKeyboardKey.keyD) {
      action = c.duplicateSelected;
    } else if (mod && k == LogicalKeyboardKey.keyI) {
      action = c.importAudio;
    } else if (!mod && k == LogicalKeyboardKey.keyS) {
      action = c.splitAtPlayhead;
    } else if (!mod && k == LogicalKeyboardKey.keyL) {
      action = c.toggleLoop;
    } else if (!mod && k == LogicalKeyboardKey.keyC) {
      action = c.toggleMetronome;
    } else if (!mod && k == LogicalKeyboardKey.keyX) {
      action = c.toggleMixer;
    } else if (k == LogicalKeyboardKey.equal || k == LogicalKeyboardKey.numpadAdd) {
      action = () => c.zoom(1.25);
    } else if (k == LogicalKeyboardKey.minus || k == LogicalKeyboardKey.numpadSubtract) {
      action = () => c.zoom(0.8);
    }
    if (action == null) return KeyEventResult.ignored;
    action();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final desktop = isDesktop(context);
    final transport = TransportBar(c: c, compact: !desktop);
    // os botões e controles não pegam o foco: senão o espaço aciona o botão clicado por último em
    // vez de tocar/pausar
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: ExcludeFocus(
        child: ListenableBuilder(
          listenable: c,
          builder: (context, _) => Column(
            children: [
              if (desktop) transport,
              if (c.error != null)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: InlineNotice(c.error!, onClose: c.clearError),
                ),
              Expanded(
                child: Timeline(c: c, compact: !desktop),
              ),
              if (c.mixerOpen) MixerPanel(c: c),
              if (!desktop) transport,
            ],
          ),
        ),
      ),
    );
  }
}
