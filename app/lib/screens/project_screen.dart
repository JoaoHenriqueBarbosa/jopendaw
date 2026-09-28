import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/client.dart';
import '../daw/controller.dart';
import '../daw/dock.dart';
import '../daw/timeline.dart';
import '../daw/transport_bar.dart';
import '../models/project.dart';
import '../widgets/api_state.dart';
import '../widgets/feedback.dart';
import '../widgets/page.dart';
import '../widgets/responsive_scaffold.dart';

/// Um projeto aberto no DAW: transporte, arranjo e o painel de baixo (mixer, editor de notas,
/// instrumento, efeitos). O áudio roda no aparelho; do servidor vêm só o nome, o andamento e a fórmula de
/// compasso.
class ProjectScreen extends StatefulWidget {
  final String projectId;
  const ProjectScreen({super.key, required this.projectId});
  @override
  State<ProjectScreen> createState() => _ProjectScreenState();
}

class _ProjectScreenState extends State<ProjectScreen> with ApiState {
  /// Telas de projeto montadas: na troca direta de um projeto para outro, a nova monta antes de a
  /// velha desmontar, e o menu do navegador só volta quando não sobra nenhuma.
  static var _screens = 0;

  Project? _project;
  DawController? _daw;

  @override
  void initState() {
    super.initState();
    // no navegador, o botão direito é o menu dos clipes, não o do navegador
    if (kIsWeb && _screens++ == 0) BrowserContextMenu.disableContextMenu();
    reload();
  }

  @override
  Future<void> reload() => fetch(ApiClient.instance.project(widget.projectId), (v) {
    _project = v;
    _daw ??= DawController(v)..open();
  });

  @override
  void dispose() {
    if (kIsWeb && --_screens == 0) BrowserContextMenu.enableContextMenu();
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
                return DawStudio(c: daw);
              },
            ),
    );
  }
}

/// Transporte, arranjo e o painel de baixo quando aberto. No celular o transporte fica embaixo,
/// perto do polegar. Público para os testes montarem a tela sem a API.
class DawStudio extends StatelessWidget {
  final DawController c;
  const DawStudio({super.key, required this.c});

  bool _typing() {
    final f = FocusManager.instance.primaryFocus?.context?.widget;
    return f is EditableText;
  }

  /// Teclas da tela, em camadas: primeiro o teclado musical (quando ligado, as letras dele ganham
  /// dos atalhos), depois o editor aberto, depois os atalhos gerais.
  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (_typing()) return KeyEventResult.ignored;
    final keys = HardwareKeyboard.instance;
    final mod = keys.isControlPressed || keys.isMetaPressed;
    // com Ctrl/Cmd a tecla é atalho (Ctrl+Z, Ctrl+K...), não nota; o soltar passa sempre, senão
    // uma nota apertada antes do Ctrl ficaria presa
    if (c.keyboardOn && (e is KeyUpEvent || !mod) && c.handleNoteKey(e)) return KeyEventResult.handled;
    if (c.editorKeyHandler?.call(e) ?? false) return KeyEventResult.handled;
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    void Function()? action;
    if (k == LogicalKeyboardKey.space) {
      action = c.togglePlay;
    } else if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.home) {
      action = c.stop;
    } else if (k == LogicalKeyboardKey.delete || k == LogicalKeyboardKey.backspace) {
      action = () => deleteSelectedClip(c);
    } else if (mod && k == LogicalKeyboardKey.keyZ) {
      action = keys.isShiftPressed ? c.redo : c.undo;
    } else if (mod && k == LogicalKeyboardKey.keyY) {
      action = c.redo;
    } else if (mod && k == LogicalKeyboardKey.keyD) {
      action = () => duplicateSelectedClip(c);
    } else if (mod && k == LogicalKeyboardKey.keyI) {
      action = c.importAudio;
    } else if (mod && k == LogicalKeyboardKey.keyK) {
      action = c.toggleKeyboard;
    } else if (!mod && k == LogicalKeyboardKey.keyS) {
      action = () => splitClipsAtPlayhead(c);
    } else if (!mod && k == LogicalKeyboardKey.keyL) {
      action = c.toggleLoop;
    } else if (!mod && k == LogicalKeyboardKey.keyC) {
      action = c.toggleMetronome;
    } else if (!mod && k == LogicalKeyboardKey.keyX) {
      action = () => toggleDock(c, Dock.mixer);
    } else if (!mod && k == LogicalKeyboardKey.keyE) {
      action = () => toggleDock(c, Dock.editor);
    } else if (!mod && k == LogicalKeyboardKey.keyI) {
      action = () => toggleDock(c, Dock.instrument);
    } else if (!mod && k == LogicalKeyboardKey.keyF) {
      action = () => toggleDock(c, Dock.effects);
    } else if (k == LogicalKeyboardKey.escape && c.dock != Dock.none) {
      action = () => c.setDock(Dock.none);
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
    // vez de tocar/pausar, e as teclas do teclado musical e do editor não chegariam aqui
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
                // o painel de baixo divide este espaço com o arranjo e precisa saber o tamanho dele
                child: LayoutBuilder(
                  builder: (context, box) => Column(
                    children: [
                      Expanded(
                        child: Timeline(c: c, compact: !desktop),
                      ),
                      DockPanel(c: c, available: box.maxHeight, compact: !desktop),
                    ],
                  ),
                ),
              ),
              if (!desktop) transport,
            ],
          ),
        ),
      ),
    );
  }
}
