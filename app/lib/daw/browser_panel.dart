/// A aba "Áudios" do painel de baixo: o navegador de áudios (projeto e conta) com busca, pré-escuta e inserção no arranjo
/// ou numa zona do sampler; e a zona de soltar do arranjo que recebe o que for arrastado dali. O modelo está em
/// `browser.dart`.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;

import '../widgets/feedback.dart';
import '../widgets/format.dart';
import '../widgets/theme.dart';
import 'browser.dart';
import 'controller.dart';
import 'instruments.dart' show TrackKind;
import 'keymap.dart';
import 'tempo_format.dart';

class BrowserPanel extends StatefulWidget {
  final DawController c;

  /// Os testes põem um modelo com o servidor de mentira; o padrão é o do controlador.
  final AudioBrowser? browser;
  const BrowserPanel({super.key, required this.c, this.browser});

  @override
  State<BrowserPanel> createState() => _BrowserPanelState();
}

class _BrowserPanelState extends State<BrowserPanel> {
  late final AudioBrowser _b = widget.browser ?? AudioBrowser.of(widget.c);
  final _search = TextEditingController();
  final _focus = FocusNode(debugLabel: 'browser-search');

  /// Quem tinha o foco quando o campo o pegou (a tela do estúdio, que recebe as teclas de atalho): ele volta para lá
  /// quando a pessoa larga o campo.
  FocusNode? _back;

  void _grab() {
    final p = FocusManager.instance.primaryFocus;
    if (p != null && p != _focus) _back = p;
  }

  void _leave() {
    if (!_focus.hasFocus) return;
    _focus.unfocus();
    final b = _back;
    if (b != null && b.context != null && b.canRequestFocus) b.requestFocus();
  }

  @override
  void initState() {
    super.initState();
    _search.text = _b.query;
    unawaited(_b.refresh());
  }

  @override
  void dispose() {
    // fechar o painel cala a pré-escuta: ninguém a ouve mais e a voz não tem botão para parar
    _b.release();
    _leave();
    _focus.dispose();
    _search.dispose();
    super.dispose();
  }

  DawController get c => widget.c;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_b, c]),
    builder: (context, _) {
      final list = _b.visible;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _controls(context),
          if (_b.usageError != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
              child: InlineNotice(_b.usageError!, actionLabel: 'Tentar de novo', onAction: _b.loading ? null : () => unawaited(_b.refresh())),
            ),
          if (_b.notice != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
              child: InlineNotice(_b.notice!, error: _b.noticeIsError, onClose: _b.clearNotice),
            ),
          Expanded(
            child: list.isEmpty
                ? _empty(context)
                : ListView.builder(
                    key: const ValueKey('browser-list'),
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    itemCount: list.length,
                    itemBuilder: (context, i) => _EntryTile(key: ValueKey(list[i].hash), b: _b, entry: list[i]),
                  ),
          ),
        ],
      );
    },
  );

  Widget _controls(BuildContext context) {
    final bpm = c.doc.bpm;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                // o estúdio exclui o foco dos botões e controles (ExcludeFocus em project_screen.dart), e isso vale para
                // tudo que está embaixo dele: o campo de busca se pendura na raiz do foco para poder receber a digitação
                child: Focus(
                  parentNode: FocusManager.instance.rootScope,
                  canRequestFocus: false,
                  skipTraversal: true,
                  child: Listener(
                    onPointerDown: (_) => _grab(),
                    child: CallbackShortcuts(
                      bindings: {const SingleActivator(LogicalKeyboardKey.escape): _leave},
                      child: TextField(
                        key: const ValueKey('browser-search'),
                        controller: _search,
                        focusNode: _focus,
                        style: const TextStyle(fontSize: 13.5),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: 'Buscar áudio pelo nome',
                          prefixIcon: const Icon(Icons.search, size: 18),
                          prefixIconConstraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                          suffixIcon: _b.query.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Limpar a busca',
                                  iconSize: 16,
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () {
                                    _search.clear();
                                    _b.setQuery('');
                                  },
                                  icon: const Icon(Icons.close),
                                ),
                        ),
                        onChanged: _b.setQuery,
                        // sem isto o campo segura as teclas (Espaço, atalhos) depois de a pessoa clicar em outro lugar
                        onTapOutside: (_) => _leave(),
                        onSubmitted: (_) => _leave(),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              SizedBox(
                width: 36,
                height: 36,
                child: _b.loading
                    ? const Padding(padding: EdgeInsets.all(10), child: CircularProgressIndicator(strokeWidth: 2))
                    : IconButton(
                        tooltip: 'Atualizar a lista',
                        iconSize: 19,
                        padding: EdgeInsets.zero,
                        onPressed: () => unawaited(_b.refresh()),
                        icon: const Icon(Icons.refresh),
                      ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final s in BrowserScope.values)
                ChoiceChip(
                  key: ValueKey('browser-scope-${s.name}'),
                  label: Text(s.label),
                  selected: _b.scope == s,
                  visualDensity: VisualDensity.compact,
                  labelStyle: const TextStyle(fontSize: 12),
                  onSelected: (_) => _b.setScope(s),
                ),
              Tooltip(
                message:
                    'Estica a pré-escuta para o andamento do projeto (${formatBpm(bpm)} BPM), estimando o andamento do áudio. O áudio do projeto não muda.',
                child: FilterChip(
                  key: const ValueKey('browser-tempo'),
                  label: const Text('No andamento do projeto'),
                  selected: _b.atProjectTempo,
                  visualDensity: VisualDensity.compact,
                  labelStyle: const TextStyle(fontSize: 12),
                  onSelected: _b.setAtProjectTempo,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _empty(BuildContext context) {
    final String text;
    if (_b.query.trim().isNotEmpty) {
      text = 'Nenhum áudio com "${_b.query.trim()}" no nome.';
    } else if (_b.scope == BrowserScope.account && _b.usageError == null) {
      text = 'A conta ainda não tem áudios no servidor. Eles aparecem aqui depois que um projeto sincroniza.';
    } else if (_b.scope == BrowserScope.project) {
      text = 'Este projeto ainda não tem áudios. Importe um arquivo${shortcutHint('edit.import')} ou escolha um da conta.';
    } else if (_b.loading) {
      text = 'Carregando os áudios…';
    } else {
      text = 'Nenhum áudio ainda. Importe um arquivo${shortcutHint('edit.import')} para ele aparecer aqui.';
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall!.copyWith(color: Colors.white60),
        ),
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  final AudioBrowser b;
  final BrowserEntry entry;
  const _EntryTile({super.key, required this.b, required this.entry});

  static const _zoneItem = 'zone', _downloadItem = 'download';

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final playing = b.isPreviewing(e.hash);
    final sampler = b.selectedTrack?.kind == TrackKind.sampler;
    final text = Theme.of(context).textTheme;
    final meta = <String>[
      if (e.duration != null) fmtDuration(e.duration!),
      if (e.size != null) fmtBytes(e.size!),
      if (e.inProject) 'no projeto' else 'só na conta',
    ];
    final row = Row(
      children: [
        Expanded(
          child: Tooltip(
            message: e.projects.isEmpty ? e.name : '${e.name}\nUsado em: ${e.projects.where((p) => p.isNotEmpty).join(', ')}',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodyMedium!.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Wrap(
                  spacing: 8,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(meta.join(' · '), style: text.labelSmall!.copyWith(color: Colors.white54)),
                    if (b.isDownloading(e.hash))
                      Text(
                        'baixando…',
                        key: ValueKey('browser-downloading-${e.hash}'),
                        style: text.labelSmall!.copyWith(color: Palette.accent),
                      )
                    else if (!e.onDevice)
                      Row(
                        key: ValueKey('browser-off-${e.hash}'),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.cloud_off, size: 12, color: Color(0xFFE3B341)),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(
                              'fora deste aparelho',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text.labelSmall!.copyWith(color: const Color(0xFFE3B341)),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        _Action(
          key: ValueKey('browser-play-${e.hash}'),
          icon: playing ? Icons.stop_circle_outlined : Icons.play_circle_outline,
          tooltip: playing ? 'Parar a pré-escuta' : (e.onDevice ? 'Ouvir (não mexe no projeto)' : 'Ouvir: baixa o áudio deste aparelho antes'),
          color: playing ? Palette.accent : null,
          onTap: () => unawaited(b.togglePreview(e)),
        ),
        _Action(
          key: ValueKey('browser-insert-${e.hash}'),
          icon: Icons.add_circle_outline,
          tooltip: sampler ? 'Criar uma zona no sampler selecionado' : 'Inserir na faixa selecionada, no cursor',
          onTap: () => unawaited(b.insertAtCursor(e)),
        ),
        PopupMenuButton<String>(
          key: ValueKey('browser-menu-${e.hash}'),
          tooltip: 'Mais ações',
          iconSize: 19,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          icon: const Icon(Icons.more_vert),
          onSelected: (v) {
            switch (v) {
              case _zoneItem:
                unawaited(b.addAsZone(e, b.c.selectedTrack));
              case _downloadItem:
                unawaited(b.download(e));
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(value: _zoneItem, enabled: sampler, child: const Text('Criar zona no sampler selecionado')),
            if (!e.onDevice) const PopupMenuItem(value: _downloadItem, child: Text('Baixar para este aparelho')),
          ],
        ),
      ],
    );
    final handle = Draggable<BrowserEntry>(
      data: e,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: _DragFeedback(entry: e),
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: Tooltip(
          message: 'Arraste para o arranjo (clipe) ou para uma faixa de sampler (zona)',
          child: const SizedBox(width: 26, height: 40, child: Icon(Icons.drag_indicator, size: 18, color: Colors.white38)),
        ),
      ),
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.fromLTRB(2, 4, 0, 4),
      decoration: BoxDecoration(
        color: playing ? Palette.accent.withValues(alpha: 0.08) : Palette.raised,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: playing ? Palette.accent.withValues(alpha: 0.4) : Palette.hairline),
      ),
      child: Column(
        children: [
          // no toque, arrastar a linha rola a lista: o toque longo é que pega o áudio
          LongPressDraggable<BrowserEntry>(
            data: e,
            dragAnchorStrategy: pointerDragAnchorStrategy,
            feedback: _DragFeedback(entry: e),
            child: Row(
              children: [
                handle,
                Expanded(child: row),
              ],
            ),
          ),
          if (playing) _Progress(b: b, entry: e),
        ],
      ),
    );
  }
}

class _Action extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color? color;
  final VoidCallback onTap;
  const _Action({super.key, required this.icon, required this.tooltip, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 36,
    height: 36,
    child: IconButton(tooltip: tooltip, iconSize: 22, padding: EdgeInsets.zero, color: color, onPressed: onTap, icon: Icon(icon)),
  );
}

class _DragFeedback extends StatelessWidget {
  final BrowserEntry entry;
  const _DragFeedback({required this.entry});

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: Container(
      constraints: const BoxConstraints(maxWidth: 220),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Palette.overlay,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Palette.accent),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.audiotrack, size: 16, color: Palette.accent),
          const SizedBox(width: 6),
          Flexible(
            child: Text(entry.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5)),
          ),
        ],
      ),
    ),
  );
}

/// A barra de progresso da pré-escuta: toque ou arraste para ouvir daquele ponto.
class _Progress extends StatefulWidget {
  final AudioBrowser b;
  final BrowserEntry entry;
  const _Progress({required this.b, required this.entry});

  @override
  State<_Progress> createState() => _ProgressState();
}

class _ProgressState extends State<_Progress> {
  /// Onde o dedo está arrastando (0..1); null fora do arrasto.
  double? _drag;

  void _seek(double fraction) {
    setState(() => _drag = null);
    unawaited(widget.b.playPreview(widget.entry, fraction: fraction.clamp(0.0, 1.0)));
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.b;
    if (b.phase == PreviewPhase.loading) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(26, 4, 10, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const LinearProgressIndicator(minHeight: 3),
            const SizedBox(height: 3),
            Text(
              b.isDownloading(widget.entry.hash) ? 'Baixando o áudio do servidor…' : (b.atProjectTempo ? 'Ajustando ao andamento…' : 'Preparando…'),
              style: Theme.of(context).textTheme.labelSmall!.copyWith(color: Colors.white54),
            ),
          ],
        ),
      );
    }
    final total = b.previewDuration <= 0 ? 1.0 : b.previewDuration;
    final shown = _drag ?? (b.previewPosition / total).clamp(0.0, 1.0);
    final label =
        '${fmtDuration(shown * total)} / ${fmtDuration(b.previewDuration)}'
        '${b.previewRatio != 1 ? ' · esticado ×${b.previewRatio.toStringAsFixed(2).replaceAll('.', ',')}' : ''}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 2, 10, 2),
      child: LayoutBuilder(
        builder: (context, box) => GestureDetector(
          key: const ValueKey('browser-seek'),
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) => _seek(d.localPosition.dx / box.maxWidth),
          onHorizontalDragUpdate: (d) => setState(() => _drag = (d.localPosition.dx / box.maxWidth).clamp(0.0, 1.0)),
          onHorizontalDragEnd: (_) => _seek(_drag ?? shown),
          onHorizontalDragCancel: () => setState(() => _drag = null),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 14,
                child: Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(value: shown, minHeight: 4, backgroundColor: Colors.white12),
                  ),
                ),
              ),
              Text(label, style: Theme.of(context).textTheme.labelSmall!.copyWith(color: Colors.white54)),
            ],
          ),
        ),
      ),
    );
  }
}

/// A linha do arranjo sob o ponteiro: a faixa, e onde ela fica na vertical.
typedef BrowserDropRow = ({int track, double top, double height});

/// Envolve as raias do arranjo para receber um áudio arrastado do navegador: solta numa faixa de áudio vira clipe no
/// ponto (na grade), numa faixa de sampler vira zona, e fora das faixas vira uma faixa nova.
class BrowserDropZone extends StatefulWidget {
  final DawController c;

  /// A linha de faixa em [y] (coordenada local das raias); null onde não há faixa.
  final BrowserDropRow? Function(double y) rowAt;
  final Widget child;
  const BrowserDropZone({super.key, required this.c, required this.rowAt, required this.child});

  @override
  State<BrowserDropZone> createState() => _BrowserDropZoneState();
}

class _BrowserDropZoneState extends State<BrowserDropZone> {
  Offset? _at;

  Offset _local(Offset global) => (context.findRenderObject() as RenderBox).globalToLocal(global);

  @override
  Widget build(BuildContext context) => DragTarget<BrowserEntry>(
    onMove: (d) => setState(() => _at = _local(d.offset)),
    onLeave: (_) => setState(() => _at = null),
    onAcceptWithDetails: (d) {
      final p = _local(d.offset);
      setState(() => _at = null);
      final beat = widget.c.scrollBeat + p.dx / widget.c.pxPerBeat;
      unawaited(AudioBrowser.of(widget.c).dropOnTimeline(d.data, beat: beat, track: widget.rowAt(p.dy)?.track));
    },
    builder: (context, candidates, _) {
      final at = _at;
      final row = at == null || candidates.isEmpty ? null : widget.rowAt(at.dy);
      return Stack(
        children: [
          widget.child,
          if (at != null && candidates.isNotEmpty)
            Positioned.fill(
              child: IgnorePointer(child: CustomPaint(painter: _DropPainter(at.dx, row))),
            ),
        ],
      );
    },
  );
}

class _DropPainter extends CustomPainter {
  final double x;
  final BrowserDropRow? row;
  _DropPainter(this.x, this.row);

  @override
  void paint(Canvas canvas, Size size) {
    final r = row;
    if (r != null) {
      canvas.drawRect(Rect.fromLTWH(0, r.top, size.width, r.height), Paint()..color = Palette.accent.withValues(alpha: 0.12));
    }
    canvas.drawLine(
      Offset(x, r?.top ?? 0),
      Offset(x, r == null ? size.height : r.top + r.height),
      Paint()
        ..color = Palette.accent
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_DropPainter o) => o.x != x || o.row != row;
}
