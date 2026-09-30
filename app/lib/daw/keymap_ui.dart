/// A tela de personalização dos atalhos (dentro da janela de atalhos): lista por categoria com o atalho atual de cada
/// ação, regravar por clique, conflito com trocar/cancelar, teclas reservadas, restaurar (por ação e tudo), busca e
/// exportar/importar `.jokeys`. A lógica e o guardado ficam em `keymap.dart`.
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../audio/engine.dart';
import '../widgets/feedback.dart';
import '../widgets/theme.dart';
import 'keymap.dart';

/// Guarda o `.jokeys` (download na web, "salvar como" no Android); devolve `false` se a pessoa cancelou.
typedef SaveKeymapFile = Future<Object?> Function(String name, Uint8List bytes, String mime);

/// Escolhe o arquivo a importar: nome e bytes, ou null se cancelou.
typedef PickKeymapFile = Future<(String, Uint8List)?> Function();

const keymapMime = 'application/octet-stream';

Future<(String, Uint8List)?> pickKeymapFile() async {
  final files = await FilePicker.pickFiles(dialogTitle: 'Importar atalhos', type: FileType.custom, allowedExtensions: const [keymapExtension, 'json']);
  if (files.isEmpty) return null;
  final f = files.first;
  return (f.name, await f.readAsBytes());
}

/// Sem acento e em minúsculas, para a busca.
String foldForSearch(String s) {
  const from = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
  const to = 'aaaaaeeeeiiiiooooouuuucn';
  final b = StringBuffer();
  for (final r in s.toLowerCase().runes) {
    final ch = String.fromCharCode(r);
    final i = from.indexOf(ch);
    b.write(i >= 0 ? to[i] : ch);
  }
  return b.toString();
}

class _Target {
  final String id;

  /// Índice do atalho que está sendo regravado; igual ao tamanho da lista para acrescentar.
  final int slot;
  const _Target(this.id, this.slot);
}

class _Conflict {
  final _Target target;
  final KeyCombo combo;
  final KeyAction other;
  const _Conflict(this.target, this.combo, this.other);
}

class KeymapEditor extends StatefulWidget {
  final Keymap keymap;

  /// Trocáveis nos testes.
  final SaveKeymapFile? save;
  final PickKeymapFile? pick;
  const KeymapEditor({super.key, required this.keymap, this.save, this.pick});

  @override
  State<KeymapEditor> createState() => _KeymapEditorState();
}

class _KeymapEditorState extends State<KeymapEditor> {
  Keymap get km => widget.keymap;
  final _focus = FocusNode(debugLabel: 'keymap-editor');
  final _search = TextEditingController();
  String _query = '';
  _Target? _rec;
  _Conflict? _conflict;

  /// Recusa da tecla apertada (reservada, sem suporte): inline, na linha regravada.
  String? _refusal;

  /// Resultado de exportar/importar.
  String? _note;
  bool _noteError = false;

  @override
  void dispose() {
    _focus.dispose();
    _search.dispose();
    super.dispose();
  }

  void _start(String id, int slot) {
    setState(() {
      _rec = _Target(id, slot);
      _conflict = null;
      _refusal = null;
    });
    _focus.requestFocus();
  }

  void _stop() => setState(() {
    _rec = null;
    _conflict = null;
    _refusal = null;
  });

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    final rec = _rec;
    if (rec == null) return KeyEventResult.ignored;
    if (e is KeyUpEvent) return KeyEventResult.handled;
    if (e is! KeyDownEvent) return KeyEventResult.handled;
    final k = e.logicalKey;
    if (isModifierKey(k)) return KeyEventResult.handled;
    final keys = HardwareKeyboard.instance;
    final mod = keys.isControlPressed || keys.isMetaPressed;
    if (k == LogicalKeyboardKey.escape) {
      _stop();
      return KeyEventResult.handled;
    }
    if ((k == LogicalKeyboardKey.backspace || k == LogicalKeyboardKey.delete) && !mod && !keys.isShiftPressed && !keys.isAltPressed) {
      if (_conflict == null) {
        km.removeBinding(rec.id, rec.slot);
        _stop();
      }
      return KeyEventResult.handled;
    }
    if (_conflict != null) return KeyEventResult.handled;
    final action = keyActionById(rec.id)!;
    KeyCombo? combo;
    if (action.context == KeyContext.playing) {
      // o teclado tocando é por posição: vale a tecla física
      final t = physicalKeyToken(e.physicalKey);
      combo = t == null ? null : KeyCombo(t, mod: mod, shift: keys.isShiftPressed, alt: keys.isAltPressed);
    } else {
      combo = KeyCombo.fromKey(k, character: e.character, mod: mod, shift: keys.isShiftPressed, alt: keys.isAltPressed);
    }
    if (combo == null) {
      setState(() => _refusal = 'Essa tecla não pode ser usada em atalhos. Tente outra.');
      return KeyEventResult.handled;
    }
    final check = km.check(rec.id, combo);
    switch (check.status) {
      case AssignStatus.reserved:
        setState(() => _refusal = check.reason);
      case AssignStatus.notEditable:
        _stop();
      case AssignStatus.conflict:
        setState(() {
          _conflict = _Conflict(rec, combo!, check.other!);
          _refusal = null;
        });
      case AssignStatus.ok || AssignStatus.already:
        km.assign(rec.id, combo, slot: rec.slot);
        _stop();
    }
    return KeyEventResult.handled;
  }

  void _swap() {
    final c = _conflict;
    if (c == null) return;
    km.assign(c.target.id, c.combo, slot: c.target.slot, swap: true);
    _stop();
  }

  Future<void> _resetAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restaurar todos os atalhos?'),
        content: const Text('Todas as suas personalizações serão descartadas e os atalhos padrão voltam.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(key: const ValueKey('keymap-reset-all-confirm'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Restaurar tudo')),
        ],
      ),
    );
    if (ok == true) {
      km.resetAll();
      if (mounted) setState(() => _note = null);
    }
  }

  Future<void> _export() async {
    try {
      final saved = await (widget.save ?? AudioEngine.instance.saveFile)('atalhos.$keymapExtension', km.exportBytes(), keymapMime);
      if (!mounted) return;
      setState(() {
        _noteError = saved == false;
        _note = saved == false ? 'Exportação cancelada: nada foi salvo.' : 'Atalhos exportados em atalhos.$keymapExtension.';
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _noteError = true;
          _note = 'Não foi possível exportar: $e';
        });
      }
    }
  }

  Future<void> _import() async {
    try {
      final f = await (widget.pick ?? pickKeymapFile)();
      if (f == null || !mounted) return;
      final r = km.importBytes(f.$2);
      if (!mounted) return;
      _stop();
      setState(() {
        _noteError = false;
        _note = r.warnings.isEmpty
            ? 'Atalhos importados de ${f.$1}.'
            : 'Atalhos importados de ${f.$1}, com avisos:\n${r.warnings.map((w) => '• $w').join('\n')}';
      });
    } on KeymapFormatException catch (e) {
      if (mounted) {
        setState(() {
          _noteError = true;
          _note = 'Não foi possível importar: ${e.message}';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _noteError = true;
          _note = 'Não foi possível importar: $e';
        });
      }
    }
  }

  bool _matches(KeyAction a) {
    final q = foldForSearch(_query.trim());
    if (q.isEmpty) return true;
    final hay = foldForSearch('${a.label} ${a.category.title} ${a.context.label} ${km.labelOf(a.id, none: '')}');
    return q.split(RegExp(r'\s+')).every(hay.contains);
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focus,
      onKeyEvent: _onKey,
      child: ListenableBuilder(
        listenable: km,
        builder: (context, _) => LayoutBuilder(builder: (context, box) => _body(context, box.maxWidth < 460)),
      ),
    );
  }

  Widget _body(BuildContext context, bool narrow) {
    final theme = Theme.of(context);
    final shown = [
      for (final a in keyCatalog)
        if (_matches(a)) a,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Clique num atalho para regravar. Esc cancela; Backspace ou Delete remove. Cada ação aceita até $maxBindingsPerAction atalhos.',
          style: theme.textTheme.bodySmall!.copyWith(color: Colors.white60),
        ),
        const SizedBox(height: 10),
        if (km.problem != null) ...[InlineNotice(km.problem!), const SizedBox(height: 8)],
        if (_note != null) ...[InlineNotice(_note!, error: _noteError, onClose: () => setState(() => _note = null)), const SizedBox(height: 8)],
        TextField(
          key: const ValueKey('keymap-search'),
          controller: _search,
          onChanged: (v) => setState(() => _query = v),
          decoration: InputDecoration(
            isDense: true,
            prefixIcon: const Icon(Icons.search, size: 18),
            hintText: 'Buscar ação ou tecla',
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Limpar a busca',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(() {
                      _search.clear();
                      _query = '';
                    }),
                  ),
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 4,
          children: [
            TextButton.icon(
              key: const ValueKey('keymap-reset-all'),
              onPressed: km.hasCustom ? _resetAll : null,
              icon: const Icon(Icons.restart_alt, size: 18),
              label: const Text('Restaurar tudo'),
            ),
            TextButton.icon(
              key: const ValueKey('keymap-export'),
              onPressed: _export,
              icon: const Icon(Icons.file_download_outlined, size: 18),
              label: const Text('Exportar atalhos…'),
            ),
            TextButton.icon(
              key: const ValueKey('keymap-import'),
              onPressed: _import,
              icon: const Icon(Icons.file_upload_outlined, size: 18),
              label: const Text('Importar atalhos…'),
            ),
          ],
        ),
        if (shown.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'Nenhuma ação encontrada para "${_query.trim()}".',
              key: const ValueKey('keymap-empty'),
              style: theme.textTheme.bodyMedium!.copyWith(color: Colors.white54),
            ),
          ),
        for (final cat in KeyCategory.values)
          if (shown.any((a) => a.category == cat)) ...[
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Text(cat.title.toUpperCase(), style: theme.textTheme.labelSmall!.copyWith(letterSpacing: 0.8, color: Colors.white54)),
            ),
            for (final a in shown)
              if (a.category == cat) _row(context, a, narrow),
          ],
      ],
    );
  }

  Widget _row(BuildContext context, KeyAction a, bool narrow) {
    final theme = Theme.of(context);
    final bindings = km.bindingsOf(a.id);
    final chips = Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (var i = 0; i < bindings.length; i++) _chip(a, i, bindings[i].label),
        if (bindings.isEmpty) _chip(a, 0, a.fixed ? '—' : 'Sem atalho'),
        if (!a.fixed && bindings.isNotEmpty && bindings.length < maxBindingsPerAction)
          Tooltip(
            message: 'Adicionar outro atalho',
            child: InkWell(
              key: ValueKey('add-${a.id}'),
              borderRadius: BorderRadius.circular(8),
              onTap: () => _start(a.id, bindings.length),
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(Icons.add, size: 16, color: Colors.white54),
              ),
            ),
          ),
        if (_rec?.id == a.id && _rec!.slot >= bindings.length && bindings.isNotEmpty) _chip(a, bindings.length, ''),
        if (a.fixed)
          const Tooltip(
            message: 'Tecla fixa: não pode ser mudada',
            child: Icon(Icons.lock_outline, size: 14, color: Colors.white38),
          ),
        if (km.isCustomized(a.id))
          IconButton(
            key: ValueKey('reset-${a.id}'),
            tooltip: 'Restaurar o padrão desta ação',
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            icon: const Icon(Icons.restart_alt, color: Colors.white54),
            onPressed: () {
              km.reset(a.id);
              if (_rec?.id == a.id) _stop();
            },
          ),
      ],
    );
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(a.label, style: theme.textTheme.bodyMedium),
        Text(a.context.label, style: theme.textTheme.labelSmall!.copyWith(color: Colors.white38)),
      ],
    );
    final here = _rec?.id == a.id;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          narrow
              ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [title, const SizedBox(height: 4), chips])
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(flex: 5, child: title),
                    Expanded(flex: 6, child: chips),
                  ],
                ),
          if (here && _refusal != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                _refusal!,
                key: ValueKey('refusal-${a.id}'),
                style: theme.textTheme.bodySmall!.copyWith(color: Palette.danger),
              ),
            ),
          if (_conflict != null && _conflict!.target.id == a.id) _conflictBox(theme, a),
        ],
      ),
    );
  }

  Widget _conflictBox(ThemeData theme, KeyAction a) {
    final c = _conflict!;
    final list = km.bindingsOf(a.id);
    final old = c.target.slot < list.length ? list[c.target.slot] : null;
    final swapText = old == null ? '"${c.other.label}" fica sem esse atalho.' : '"${c.other.label}" passa a usar ${old.label}.';
    return Container(
      key: ValueKey('conflict-${a.id}'),
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Palette.danger.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Palette.danger.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${c.combo.label} já é de "${c.other.label}" (${c.other.context.label}). Trocar? $swapText', style: theme.textTheme.bodySmall),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            children: [
              TextButton(key: const ValueKey('conflict-swap'), onPressed: _swap, child: const Text('Trocar')),
              TextButton(key: const ValueKey('conflict-cancel'), onPressed: _stop, child: const Text('Cancelar')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(KeyAction a, int slot, String text) {
    final rec = _rec != null && _rec!.id == a.id && _rec!.slot == slot;
    final theme = Theme.of(context);
    final label = rec ? 'Pressione a nova combinação…' : text;
    final child = Container(
      constraints: const BoxConstraints(minHeight: 30),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: rec ? Palette.accent.withValues(alpha: 0.16) : Palette.raised,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: rec ? Palette.accent : Palette.hairlineStrong),
      ),
      child: Text(
        label,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelMedium!.copyWith(
          color: rec ? Palette.accent : (a.fixed ? Colors.white54 : Colors.white),
          fontStyle: text == 'Sem atalho' && !rec ? FontStyle.italic : FontStyle.normal,
        ),
      ),
    );
    if (a.fixed) return child;
    return Semantics(
      button: true,
      label: 'Regravar o atalho de ${a.label}',
      child: InkWell(key: ValueKey('bind-${a.id}-$slot'), borderRadius: BorderRadius.circular(8), onTap: () => _start(a.id, slot), child: child),
    );
  }
}
