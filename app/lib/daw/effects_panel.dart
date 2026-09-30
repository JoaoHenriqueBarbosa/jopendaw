/// Rack de efeitos da faixa escolhida (`c.effectsTrack`; −1 = master): a cadeia de inserts na ordem
/// do sinal, um cartão por efeito (título, liga/desliga, menu com presets e o editor dele).
///
/// No computador a cadeia corre na horizontal, como o sinal, e cada cartão enche a altura do
/// painel; no celular os cartões vão um embaixo do outro. Arrastar pelo título muda a ordem.
library;

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Curve;

import '../widgets/responsive_scaffold.dart';
import '../widgets/theme.dart';
import 'controller.dart';
import 'effects.dart';
import 'fx_editors.dart';
import 'fx_presets.dart';
import 'instruments.dart';
import 'model.dart';
import 'user_presets.dart';
import 'user_presets_ui.dart';

class EffectsPanel extends StatefulWidget {
  final DawController c;
  const EffectsPanel({super.key, required this.c});

  @override
  State<EffectsPanel> createState() => _EffectsPanelState();
}

const _headerHeight = 44.0;
const _cardHead = 36.0;
const _cardPad = 10.0;
const _listPad = 10.0;

/// Cabe o título, o liga/desliga e o menu.
const _minCardWidth = 220.0;

enum _Action { reset, bypass, left, right, remove }

class _EffectsPanelState extends State<EffectsPanel> {
  final _scroll = ScrollController();

  /// Último preset aplicado em cada slot (pelo id), para o título dizer "Sala (editado)".
  final _lastPreset = <String, ({String name, String? userId})>{};

  /// Faixa mostrada no último build: trocou, a cadeia volta ao começo.
  int? _shownTrack;

  /// Chave de cada cartão (pelo id do slot), para a lista rolar até o recém-adicionado.
  final _cardKeys = <String, GlobalKey>{};

  GlobalKey _cardKey(String id) => _cardKeys.putIfAbsent(id, GlobalKey.new);

  DawController get c => widget.c;

  /// A faixa do rack: a escolhida, ou o master se ela não existe mais.
  int get _track {
    final i = c.effectsTrack;
    return i >= 0 && i < c.doc.tracks.length ? i : -1;
  }

  final _userPresets = UserPresets.instance;

  @override
  void initState() {
    super.initState();
    _userPresets
      ..addListener(_onUserPresets)
      ..load();
  }

  void _onUserPresets() {
    // preset apagado ou renomeado: o "(editado)" não pode citar o que não existe nem o nome antigo
    for (final k in _lastPreset.keys.toList()) {
      final id = _lastPreset[k]!.userId;
      if (id == null) continue;
      final p = _userPresets.byId(id);
      if (p == null) {
        _lastPreset.remove(k);
      } else if (p.name != _lastPreset[k]!.name) {
        _lastPreset[k] = (name: p.name, userId: id);
      }
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _userPresets.removeListener(_onUserPresets);
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final desktop = isDesktop(context);
    return LayoutBuilder(
      builder: (context, box) {
        // sem altura imposta (numa Column), o painel escolhe a própria, como o do instrumento
        final height = box.hasBoundedHeight ? box.maxHeight : math.min(420.0, MediaQuery.sizeOf(context).height * 0.5);
        return SizedBox(
          height: height,
          child: ColoredBox(
            color: Palette.bar,
            child: ListenableBuilder(listenable: c, builder: (context, _) => _content(context, desktop)),
          ),
        );
      },
    );
  }

  Widget _content(BuildContext context, bool desktop) {
    if (!c.ready) return const SizedBox.shrink();
    final track = _track;
    if (_shownTrack != track) {
      final had = _shownTrack != null;
      _shownTrack = track;
      if (had) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _scroll.positions.length == 1) _scroll.jumpTo(0);
        });
      }
    }
    final chain = c.effectsOf(track);
    _cardKeys.removeWhere((id, _) => !chain.any((s) => s.id == id));
    final color = track < 0 ? Palette.accent : trackColorAt(c.doc.tracks[track].color);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: _headerHeight, child: _header(context, track, chain, color, desktop)),
        Expanded(child: chain.isEmpty ? _empty(track, color, desktop) : (desktop ? _strip(track, chain, color) : _column(track, chain, color))),
      ],
    );
  }

  // ---------------------------------------------------------------------- ações

  void _add(int track, EffectKind kind) {
    final slot = c.addEffect(track, kind);
    final desktop = isDesktop(context);
    // o novo entra no fim da cadeia: a lista vai até ele. No celular o cartão é mais alto que a
    // tela: o começo dele (título e gráfico) fica à vista, não o fim.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _scroll.positions.length != 1) return;
      const duration = Duration(milliseconds: 260);
      final target = _cardKeys[slot.id]?.currentContext;
      if (!desktop && target != null) {
        Scrollable.ensureVisible(target, duration: duration, curve: Curves.easeOutCubic);
      } else {
        _scroll.animateTo(_scroll.position.maxScrollExtent, duration: duration, curve: Curves.easeOutCubic);
      }
    });
  }

  /// Aplica um preset com todos os valores (o que ele não diz vai ao padrão); a faixa-chave do
  /// sidechain fica: é roteamento do projeto, não timbre.
  void _applyPreset(int track, EffectSlot s, EffectPreset p) {
    final values = {for (final spec in s.kind.params) spec.id: p.valueOf(s.kind, spec.id)};
    final sidechain = switch (s.kind) {
      EffectKind.compressor => 10,
      EffectKind.gate => 6,
      _ => null,
    };
    if (sidechain != null) values[sidechain] = s.param(sidechain);
    _lastPreset[s.id] = (name: p.name, userId: null);
    c.applyEffectPreset(track, s.id, values);
  }

  void _applyUserPreset(int track, EffectSlot s, UserPreset p) {
    _lastPreset[s.id] = (name: p.name, userId: p.id);
    c.applyEffectPreset(track, s.id, UserPresets.paramsForEffect(p, s));
  }

  void _act(int track, List<EffectSlot> chain, int index, _Action a) {
    final s = chain[index];
    switch (a) {
      case _Action.reset:
        _lastPreset.remove(s.id);
        c.applyEffectPreset(track, s.id, defaultEffectParams(s.kind));
      case _Action.bypass:
        c.setEffectBypass(track, s.id, !s.bypass);
      case _Action.left:
        if (index > 0) c.moveEffect(track, s.id, index - 1);
      case _Action.right:
        if (index < chain.length - 1) c.moveEffect(track, s.id, index + 1);
      case _Action.remove:
        _lastPreset.remove(s.id);
        c.removeEffect(track, s.id);
    }
  }

  /// Menu de adicionar, agrupado por família, aberto embaixo de [anchor].
  Future<void> _addMenu(BuildContext anchor, int track, Color color) async {
    final box = anchor.findRenderObject() as RenderBox?;
    final overlay = Overlay.of(anchor).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    final rect = box.localToGlobal(Offset.zero, ancestor: overlay) & box.size;
    final families = <String, List<EffectKind>>{};
    for (final k in EffectKind.values) {
      (families[k.family] ??= []).add(k);
    }
    final items = <PopupMenuEntry<EffectKind>>[];
    for (final MapEntry(key: family, value: kinds) in families.entries) {
      if (items.isNotEmpty) items.add(const PopupMenuDivider(height: 8));
      items.add(
        PopupMenuItem<EffectKind>(
          enabled: false,
          height: 26,
          child: Text(
            family.toUpperCase(),
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.9, color: color),
          ),
        ),
      );
      for (final k in kinds) {
        items.add(
          PopupMenuItem<EffectKind>(
            value: k,
            height: 48,
            child: Row(
              children: [
                Icon(k.icon, size: 20, color: color),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(k.label, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                      Text(
                        k.description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11.5, color: Colors.white54),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }
    final kind = await showMenu<EffectKind>(
      context: anchor,
      position: RelativeRect.fromRect(Rect.fromLTWH(rect.left, rect.bottom + 4, rect.width, 0), Offset.zero & overlay.size),
      constraints: const BoxConstraints(minWidth: 300, maxWidth: 360, maxHeight: 520),
      items: items,
    );
    if (kind != null && mounted) _add(track, kind);
  }

  /// Com a cadeia cheia (o motor comporta [DawController.maxEffectsPerChain] efeitos), o botão de
  /// adicionar fica desabilitado e a dica explica o limite.
  Widget _limitHint(bool full, Widget child) => full ? Tooltip(message: DawController.effectLimitHint, child: child) : child;

  // ---------------------------------------------------------------------- cabeçalho

  Widget _header(BuildContext context, int track, List<EffectSlot> chain, Color color, bool desktop) {
    final off = chain.where((s) => s.bypass).length;
    final summary = chain.isEmpty
        ? 'nenhum efeito'
        : '${chain.length} ${chain.length == 1 ? 'efeito' : 'efeitos'}${off > 0 ? ' · $off desligado${off == 1 ? '' : 's'}' : ''}';
    final picker = _TrackPicker(c: c, track: track, color: color);
    final full = !c.canAddEffect(track);
    final add = Builder(
      builder: (ctx) => _limitHint(
        full,
        FilledButton.tonalIcon(
          onPressed: full ? null : () => _addMenu(ctx, track, color),
          style: desktop ? null : FilledButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 12)),
          icon: const Icon(Icons.add, size: 18),
          label: Text(desktop ? 'Adicionar efeito' : 'Efeito'),
        ),
      ),
    );
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Palette.hairline)),
      ),
      child: Row(
        children: [
          Container(width: 4, color: color),
          SizedBox(width: desktop ? 12 : 8),
          if (desktop) ...[
            ConstrainedBox(constraints: const BoxConstraints(maxWidth: 280), child: picker),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                summary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: Colors.white54),
              ),
            ),
          ] else
            Expanded(
              child: Align(alignment: Alignment.centerLeft, child: picker),
            ),
          const SizedBox(width: 8),
          add,
          SizedBox(width: desktop ? 10 : 8),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------- cadeia

  /// Computador: fileira horizontal, cada cartão na altura toda. A roda vertical rola a fileira
  /// quando não está em cima de um controle (que fica com ela).
  Widget _strip(int track, List<EffectSlot> chain, Color color) => LayoutBuilder(
    builder: (context, box) {
      final cardH = math.max(0.0, box.maxHeight - 2 * _listPad);
      // cabeçalho do cartão, a margem de baixo e as bordas
      final editorH = math.max(40.0, cardH - _cardHead - _cardPad - 2);
      return Listener(
        onPointerSignal: (e) {
          if (e is! PointerScrollEvent || e.scrollDelta.dy == 0 || e.scrollDelta.dx != 0) return;
          if (_scroll.positions.length != 1 || _scroll.position.maxScrollExtent <= 0) return;
          GestureBinding.instance.pointerSignalResolver.register(e, (ev) {
            final p = _scroll.position;
            p.jumpTo((p.pixels + (ev as PointerScrollEvent).scrollDelta.dy).clamp(p.minScrollExtent, p.maxScrollExtent));
          });
        },
        child: ReorderableListView(
          scrollDirection: Axis.horizontal,
          scrollController: _scroll,
          buildDefaultDragHandles: false,
          padding: const EdgeInsets.all(_listPad),
          proxyDecorator: _proxy,
          onReorderItem: (from, to) => c.moveEffect(track, chain[from].id, to),
          footer: Builder(
            builder: (ctx) =>
                _limitHint(!c.canAddEffect(track), _AddTile(color: color, onTap: c.canAddEffect(track) ? () => _addMenu(ctx, track, color) : null)),
          ),
          children: [
            for (var i = 0; i < chain.length; i++)
              Row(
                key: ValueKey(chain[i].id),
                mainAxisSize: MainAxisSize.min,
                children: [
                  _card(context, track, chain, i, color, true, editorH),
                  // o sinal corre para a direita
                  const SizedBox(width: 16, child: Icon(Icons.chevron_right, size: 16, color: Colors.white24)),
                ],
              ),
          ],
        ),
      );
    },
  );

  /// Celular: os cartões um embaixo do outro, na largura toda.
  Widget _column(int track, List<EffectSlot> chain, Color color) => ReorderableListView(
    scrollController: _scroll,
    buildDefaultDragHandles: false,
    padding: const EdgeInsets.fromLTRB(_listPad, _listPad, _listPad, 16),
    proxyDecorator: _proxy,
    onReorderItem: (from, to) => c.moveEffect(track, chain[from].id, to),
    footer: Builder(
      builder: (ctx) => Padding(
        padding: const EdgeInsets.only(top: 2),
        child: _limitHint(
          !c.canAddEffect(track),
          OutlinedButton.icon(
            onPressed: c.canAddEffect(track) ? () => _addMenu(ctx, track, color) : null,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Adicionar efeito'),
          ),
        ),
      ),
    ),
    children: [
      for (var i = 0; i < chain.length; i++)
        Padding(
          key: ValueKey(chain[i].id),
          padding: const EdgeInsets.only(bottom: 10),
          child: KeyedSubtree(key: _cardKey(chain[i].id), child: _card(context, track, chain, i, color, false, 0)),
        ),
    ],
  );

  Widget _proxy(Widget child, int index, Animation<double> animation) => AnimatedBuilder(
    animation: animation,
    builder: (context, child) => Material(
      color: Colors.transparent,
      elevation: 12 * Curves.easeOut.transform(animation.value),
      shadowColor: Colors.black,
      borderRadius: BorderRadius.circular(10),
      child: child,
    ),
    child: child,
  );

  Widget _card(BuildContext context, int track, List<EffectSlot> chain, int index, Color color, bool desktop, double editorH) {
    final s = chain[index];
    final editor = EffectEditor(key: ValueKey('$track/${s.id}'), c: c, track: track, slot: s, color: color, desktop: desktop, height: editorH);
    final body = AnimatedOpacity(opacity: s.bypass ? 0.42 : 1, duration: const Duration(milliseconds: 150), child: editor);
    final decoration = BoxDecoration(
      color: Palette.raised,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: s.bypass ? Palette.hairline : color.withValues(alpha: 0.3)),
    );
    final head = SizedBox(height: _cardHead, child: _cardHeader(track, chain, index, color, desktop));
    if (!desktop) {
      return Container(
        decoration: decoration,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            head,
            Padding(padding: const EdgeInsets.fromLTRB(_cardPad, 0, _cardPad, _cardPad), child: body),
          ],
        ),
      );
    }
    final width = math.max(_minCardWidth, EffectEditor.widthFor(context, c, track, s, editorH) + 2 * _cardPad + 2);
    return Container(
      width: width,
      decoration: decoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          head,
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(_cardPad, 0, _cardPad, _cardPad),
              child: ClipRect(
                child: Align(alignment: Alignment.topLeft, child: body),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cardHeader(int track, List<EffectSlot> chain, int index, Color color, bool desktop) {
    final s = chain[index];
    final userPreset = _userPresets.matchingEffect(s);
    final preset = userPreset == null ? matchingEffectPreset(s) : null;
    final last = _lastPreset[s.id];
    final sub = preset?.name ?? userPreset?.name ?? (last != null ? '${last.name} (editado)' : null);
    final title = Row(
      children: [
        Icon(s.kind.icon, size: 16, color: s.bypass ? Colors.white38 : color),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            s.kind.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: s.bypass ? Colors.white54 : Colors.white),
          ),
        ),
        if (sub != null) ...[
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              sub,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11.5, color: Colors.white54),
            ),
          ),
        ],
        if (s.bypass) ...[const SizedBox(width: 7), const Text('desligado', style: TextStyle(fontSize: 10.5, color: Colors.white38))],
        if (effectMonitoringNote(s.kind, s.params, bypass: s.bypass) case final note?) ...[
          const SizedBox(width: 7),
          Tooltip(
            message: 'Este efeito está em $note: o áudio muda de verdade, inclusive na exportação',
            child: Container(
              key: const ValueKey('fx-monitor-badge'),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(color: Palette.danger.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(3)),
              child: Text(
                note.toUpperCase(),
                style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: Colors.white),
              ),
            ),
          ),
        ],
      ],
    );
    // o título também arrasta: no computador na hora, no celular com toque longo (a rolagem vem antes)
    final handle = desktop
        ? ReorderableDragStartListener(
            index: index,
            child: MouseRegion(cursor: SystemMouseCursors.grab, child: title),
          )
        : ReorderableDelayedDragStartListener(index: index, child: title);
    return Row(
      children: [
        ReorderableDragStartListener(
          index: index,
          child: MouseRegion(
            cursor: SystemMouseCursors.grab,
            child: Tooltip(
              message: 'Arraste para mudar a ordem',
              waitDuration: const Duration(milliseconds: 700),
              child: SizedBox(
                width: desktop ? 26 : 34,
                height: _cardHead,
                child: const Icon(Icons.drag_indicator, size: 16, color: Colors.white30),
              ),
            ),
          ),
        ),
        Expanded(child: handle),
        IconButton(
          tooltip: s.bypass ? 'Ligar o efeito' : 'Desligar o efeito (bypass)',
          isSelected: !s.bypass,
          onPressed: () => c.setEffectBypass(track, s.id, !s.bypass),
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          icon: const Icon(Icons.power_settings_new, size: 18, color: Colors.white38),
          selectedIcon: Icon(Icons.power_settings_new, size: 18, color: color),
        ),
        _cardMenu(track, chain, index, color, desktop),
        const SizedBox(width: 2),
      ],
    );
  }

  Widget _cardMenu(int track, List<EffectSlot> chain, int index, Color color, bool desktop) {
    final s = chain[index];
    final presets = effectPresetsFor(s.kind);
    final userList = _userPresets.ofEffect(s.kind);
    final userCurrent = _userPresets.matchingEffect(s);
    final current = userCurrent == null ? matchingEffectPreset(s) : null;
    PopupMenuItem<Object> item(Object value, IconData icon, String text, {bool enabled = true, Color? tint}) => PopupMenuItem<Object>(
      value: value,
      enabled: enabled,
      height: 38,
      child: Row(
        children: [
          Icon(icon, size: 18, color: enabled ? (tint ?? Colors.white70) : Colors.white24),
          const SizedBox(width: 12),
          Text(text, style: TextStyle(color: tint)),
        ],
      ),
    );
    return PopupMenuButton<Object>(
      tooltip: 'Presets e mais',
      position: PopupMenuPosition.under,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 230, maxHeight: 680),
      icon: const Icon(Icons.more_vert, size: 18),
      iconSize: 18,
      style: IconButton.styleFrom(visualDensity: VisualDensity.compact, minimumSize: const Size(32, 32), padding: EdgeInsets.zero),
      onSelected: (v) {
        if (v is EffectPreset) {
          _applyPreset(track, s, v);
        } else if (v is ApplyUserPreset) {
          _applyUserPreset(track, s, v.preset);
        } else if (v is UserPresetChoice) {
          handleUserPresetChoice(
            context,
            v,
            family: PresetFamily.effect,
            kind: s.kind.name,
            capture: () => UserPresets.capture(PresetFamily.effect, s.kind.name, s.param),
          );
        } else if (v is _Action) {
          _act(track, chain, index, v);
        }
      },
      itemBuilder: (_) => [
        // "Meus presets" e salvar/importar no topo, acima dos de fábrica
        ...userPresetEntries(
          presets: userList,
          current: userCurrent,
          color: color,
          checkWidth: 30,
          problem: _userPresets.problem,
          notice: _userPresets.infoNotice,
          hasBackup: _userPresets.hasBackup,
        ),
        if (presets.isNotEmpty) ...[
          PopupMenuItem<Object>(
            enabled: false,
            height: 26,
            child: Text(
              'PRESETS',
              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.9, color: color),
            ),
          ),
          for (final p in presets)
            PopupMenuItem<Object>(
              value: p,
              height: 36,
              child: Row(
                children: [
                  SizedBox(width: 30, child: identical(p, current) ? Icon(Icons.check, size: 16, color: color) : null),
                  Text(p.name),
                ],
              ),
            ),
          const PopupMenuDivider(),
        ],
        item(_Action.reset, Icons.restart_alt, 'Reiniciar (valores padrão)', enabled: !isDefaultEffect(s)),
        item(_Action.bypass, Icons.power_settings_new, s.bypass ? 'Ligar' : 'Desligar (bypass)'),
        item(_Action.left, desktop ? Icons.arrow_back : Icons.arrow_upward, desktop ? 'Mover para a esquerda' : 'Mover para cima', enabled: index > 0),
        item(
          _Action.right,
          desktop ? Icons.arrow_forward : Icons.arrow_downward,
          desktop ? 'Mover para a direita' : 'Mover para baixo',
          enabled: index < chain.length - 1,
        ),
        const PopupMenuDivider(),
        item(_Action.remove, Icons.delete_outline, 'Remover', tint: Palette.danger),
      ],
    );
  }

  // ---------------------------------------------------------------------- vazio

  Widget _empty(int track, Color color, bool desktop) {
    final master = track < 0;
    final t = master ? null : c.doc.tracks[track];
    final source = t == null
        ? ''
        : t.kind.isInstrument
        ? 'do instrumento'
        : (t.kind == TrackKind.bus ? 'do que chega pelos envios e saídas' : 'dos clipes');
    final message = master
        ? 'Os inserts do master processam a mistura inteira, em série, antes do volume final e do limitador de segurança. Um bom começo:'
        : 'Inserts processam o som desta faixa em série, ${desktop ? 'da esquerda para a direita' : 'de cima para baixo'}: '
              'depois $source e antes do volume e do pan. Um bom começo:';
    final picks = master ? const [EffectKind.eq, EffectKind.compressor, EffectKind.limiter] : const [EffectKind.eq, EffectKind.compressor, EffectKind.reverb];
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [color.withValues(alpha: 0.26), color.withValues(alpha: 0.02)]),
                  border: Border.all(color: color.withValues(alpha: 0.35)),
                ),
                child: Icon(Icons.linear_scale, size: 24, color: color),
              ),
              const SizedBox(height: 10),
              Text(
                master ? 'Nenhum efeito no master' : 'Nenhum efeito em ${t!.name}',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.4),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  for (final k in picks)
                    Tooltip(
                      message: k.description,
                      child: FilledButton.tonalIcon(onPressed: () => _add(track, k), icon: Icon(k.icon, size: 18), label: Text(k.label)),
                    ),
                  Builder(
                    builder: (ctx) => OutlinedButton.icon(
                      onPressed: () => _addMenu(ctx, track, color),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Todos os efeitos'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Escolhe de quem é o rack: o master ou uma das faixas (com a contagem de efeitos de cada uma).
class _TrackPicker extends StatelessWidget {
  final DawController c;
  final int track;
  final Color color;
  const _TrackPicker({required this.c, required this.track, required this.color});

  @override
  Widget build(BuildContext context) {
    final tracks = c.doc.tracks;
    final name = track < 0 ? 'Master' : tracks[track].name;
    final icon = track < 0 ? Icons.speaker_outlined : tracks[track].kind.icon;

    PopupMenuItem<int> entry(int i, String label, IconData icon, Color tint, int count) => PopupMenuItem<int>(
      value: i,
      height: 38,
      child: Row(
        children: [
          SizedBox(width: 24, child: i == track ? Icon(Icons.check, size: 16, color: tint) : null),
          Icon(icon, size: 17, color: tint),
          const SizedBox(width: 10),
          Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
          if (count > 0) ...[
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(color: tint.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(8)),
              child: Text(
                '$count',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: tint),
              ),
            ),
          ],
        ],
      ),
    );

    return PopupMenuButton<int>(
      tooltip: 'De qual faixa são os efeitos',
      position: PopupMenuPosition.under,
      constraints: const BoxConstraints(minWidth: 240, maxWidth: 320, maxHeight: 460),
      onSelected: (i) {
        if (i != track) c.showEffects(i);
      },
      itemBuilder: (_) => [
        entry(-1, 'Master', Icons.speaker_outlined, Palette.accent, c.doc.masterEffects.length),
        if (tracks.isNotEmpty) const PopupMenuDivider(height: 8),
        for (var i = 0; i < tracks.length; i++) entry(i, tracks[i].name, tracks[i].kind.icon, trackColorAt(tracks[i].color), tracks[i].effects.length),
      ],
      child: Container(
        height: 32,
        padding: const EdgeInsets.only(left: 10, right: 2),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Palette.hairlineStrong),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ),
            const Icon(Icons.arrow_drop_down, size: 18, color: Colors.white54),
          ],
        ),
      ),
    );
  }
}

/// O fim da cadeia no computador: um lugar para o próximo efeito.
class _AddTile extends StatefulWidget {
  final Color color;

  /// Null: o botão está desabilitado (limite de efeitos).
  final VoidCallback? onTap;
  const _AddTile({required this.color, required this.onTap});

  @override
  State<_AddTile> createState() => _AddTileState();
}

class _AddTileState extends State<_AddTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: widget.onTap == null ? SystemMouseCursors.forbidden : SystemMouseCursors.click,
    onEnter: (_) => setState(() => _hover = widget.onTap != null),
    onExit: (_) => setState(() => _hover = false),
    child: GestureDetector(
      onTap: widget.onTap,
      child: Opacity(
        opacity: widget.onTap == null ? 0.4 : 1,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 118,
          decoration: BoxDecoration(
            color: _hover ? widget.color.withValues(alpha: 0.08) : Colors.white.withValues(alpha: 0.02),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _hover ? widget.color.withValues(alpha: 0.5) : Palette.hairlineStrong),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_circle_outline, size: 26, color: _hover ? widget.color : Colors.white38),
              const SizedBox(height: 6),
              Text(
                'Adicionar\nefeito',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, height: 1.3, color: _hover ? Colors.white : Colors.white54),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
