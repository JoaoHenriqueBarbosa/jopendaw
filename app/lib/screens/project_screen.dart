import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/client.dart';
import '../daw/sync_ui.dart';
import '../daw/controller.dart';
import '../daw/tempo_format.dart' show formatBpm, formatDocMeter, formatMeter;
import '../daw/shortcuts_dialog.dart';
import '../daw/dock.dart';
import '../daw/marker.dart';
import '../daw/midi_file_ui.dart' show importFiles;
import '../daw/midi_learn_ui.dart' show MidiLearnBanner, toggleMidiLearn;
import '../daw/model.dart' show DawDoc;
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
    // o subtítulo segue o documento vivo (o andamento muda no transporte e no desfazer); o do
    // servidor é só um espelho e pode estar atrasado
    return ListenableBuilder(
      listenable: Listenable.merge([?daw]),
      builder: (context, _) => PageScaffold(
        icon: Icons.graphic_eq,
        title: p?.name ?? 'Projeto',
        subtitle: p == null ? null : projectSubtitle(p, daw != null && daw.ready ? daw.doc : null),
        showBack: true,
        // a nuvem fica no cabeçalho: na barra do transporte ela saía da tela em janelas de 1500 px
        actions: [if (daw != null && daw.ready) SyncIndicator(c: daw)],
        body: daw == null
            ? (error != null ? ErrorState(error: error!, onRetry: reload) : const LoadingState())
            : !daw.ready
            ? (daw.error != null ? InlineNotice(daw.error!) : const LoadingState())
            : DawStudio(c: daw),
      ),
    );
  }
}

/// "120 BPM · 4/4": o andamento e o compasso do documento aberto, ou os do projeto no servidor
/// enquanto ele não abriu.
String projectSubtitle(Project p, DawDoc? doc) {
  final bpm = doc?.bpm ?? p.bpm.toDouble();
  return '${formatBpm(bpm)} BPM · ${doc == null ? formatMeter(p.beatsPerBar, p.beatUnit) : formatDocMeter(doc)}';
}

/// Transporte, arranjo e o painel de baixo quando aberto. No celular o transporte fica embaixo,
/// perto do polegar. Público para os testes montarem a tela sem a API.
class DawStudio extends StatefulWidget {
  final DawController c;
  const DawStudio({super.key, required this.c});

  @override
  State<DawStudio> createState() => _DawStudioState();
}

class _DawStudioState extends State<DawStudio> {
  DawController get c => widget.c;

  /// Falha de uma ação do transporte (gravar, parar a gravação) que o controlador não transformou
  /// em aviso: aparece junto dos avisos dele, em vez de sumir no console; some na próxima ação que
  /// dá certo.
  String? _actionError;

  void _onActionError(String? message) {
    if (mounted && message != _actionError) setState(() => _actionError = message);
  }

  bool _typing() {
    final f = FocusManager.instance.primaryFocus?.context?.widget;
    return f is EditableText;
  }

  /// Teclas da tela, em camadas: primeiro o teclado musical (quando ligado, as letras dele ganham
  /// dos atalhos), depois o editor aberto, depois os atalhos gerais.
  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
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
      action = () => playOrPause(c, _onActionError);
    } else if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.home) {
      action = () => stopTransport(c, _onActionError);
    } else if (!mod && k == LogicalKeyboardKey.keyR) {
      // R não é nota no teclado musical (A W S E D F T G Y H U J K O L P), então grava mesmo com
      // ele ligado; com Ctrl/Cmd fica para o navegador (recarregar)
      action = () => toggleRecording(c, _onActionError);
    } else if (k == LogicalKeyboardKey.delete || k == LogicalKeyboardKey.backspace) {
      action = () => deleteSelectedClip(c);
    } else if (mod && c.recording && (k == LogicalKeyboardKey.keyZ || k == LogicalKeyboardKey.keyY || k == LogicalKeyboardKey.keyI)) {
      // desfazer ou importar no meio da gravação poderia apagar ou deslocar a faixa que recebe o
      // áudio (os botões ficam desligados); a tecla é engolida para o navegador não usá-la
      action = () {};
    } else if (mod && k == LogicalKeyboardKey.keyZ) {
      action = keys.isShiftPressed ? c.redo : c.undo;
    } else if (mod && k == LogicalKeyboardKey.keyY) {
      action = c.redo;
    } else if (mod && k == LogicalKeyboardKey.keyD) {
      action = () => duplicateSelectedClip(c);
    } else if (mod && k == LogicalKeyboardKey.keyI) {
      final ctx = node.context;
      action = ctx != null ? () => importFiles(ctx, c) : c.importAudio;
    } else if (mod && k == LogicalKeyboardKey.keyK) {
      action = c.toggleKeyboard;
    } else if (!mod && keys.isShiftPressed && k == LogicalKeyboardKey.keyK) {
      action = () => toggleMidiLearn(c);
    } else if (!mod && k == LogicalKeyboardKey.keyS) {
      action = () => splitClipsAtPlayhead(c);
    } else if (!mod && keys.isShiftPressed && k == LogicalKeyboardKey.keyL) {
      // sem clipe selecionado cai na seção do cursor; sem nenhuma das duas, nada acontece
      action = () {
        if (!c.loopSelection()) c.loopSection();
      };
    } else if (!mod && k == LogicalKeyboardKey.keyL) {
      action = c.toggleLoop;
    } else if (!mod && k == LogicalKeyboardKey.keyM) {
      final ctx = node.context;
      action = keys.isShiftPressed && ctx != null ? () => renameMarkerAtPlayhead(ctx, c) : () => addMarkerAtPlayhead(c);
    } else if (!mod && k == LogicalKeyboardKey.bracketLeft) {
      action = c.jumpToPreviousMarker;
    } else if (!mod && k == LogicalKeyboardKey.bracketRight) {
      action = c.jumpToNextMarker;
    } else if (!mod && k == LogicalKeyboardKey.keyZ) {
      // no teclado musical o Z é oitava (já tratado antes, na camada dele)
      action = keys.isShiftPressed ? c.fitSelection : c.fitAll;
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
    } else if (e.character == '?' || (keys.isShiftPressed && k == LogicalKeyboardKey.slash)) {
      final ctx = node.context;
      if (ctx != null) action = () => showShortcuts(ctx);
    } else if (k == LogicalKeyboardKey.escape && c.midiLearn.learning) {
      action = c.midiLearn.escape;
    } else if (k == LogicalKeyboardKey.escape && c.dock != Dock.none) {
      action = () => c.setDock(Dock.none);
    } else if (k == LogicalKeyboardKey.equal || k == LogicalKeyboardKey.add || k == LogicalKeyboardKey.numpadAdd || e.character == '+') {
      action = () => c.zoom(1.25);
    } else if (k == LogicalKeyboardKey.minus || k == LogicalKeyboardKey.numpadSubtract || e.character == '-') {
      action = () => c.zoom(0.8);
    }
    if (action == null) return KeyEventResult.ignored;
    action();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final desktop = isDesktop(context);
    final transport = TransportBar(c: c, compact: !desktop, onError: _onActionError);
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
              MidiLearnBanner(c: c),
              if (c.audioFailure != null)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: InlineNotice(
                    c.audioFailure!,
                    actionLabel: c.audioRestarting ? 'Reiniciando…' : 'Reiniciar o áudio',
                    onAction: c.audioRestarting ? null : () => unawaited(c.restartAudio()),
                  ),
                ),
              if (c.remoteNotice != null)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: InlineNotice(c.remoteNotice!, error: false, onClose: c.clearRemoteNotice),
                ),
              if (c.error != null)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: InlineNotice(c.error!, onClose: c.clearError),
                ),
              if (c.notice != null)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: InlineNotice(c.notice!, error: false, onClose: c.clearNotice),
                ),
              if (_actionError != null)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: InlineNotice(_actionError!, onClose: () => setState(() => _actionError = null)),
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
