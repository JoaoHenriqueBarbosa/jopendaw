/// Janela com os atalhos do teclado do estúdio (tecla ? ou o botão de ajuda da barra). O texto sai do catálogo
/// de ações e dos atalhos atuais (`keymap.dart`): uma só fonte da verdade, então o que a pessoa personalizar
/// aparece aqui. O botão "Personalizar" troca a lista pela tela de personalização (`keymap_ui.dart`).
library;

import 'package:flutter/material.dart';

import '../widgets/format.dart';
import '../widgets/theme.dart';
import 'keymap.dart';
import 'keymap_ui.dart';

/// O que não é tecla do catálogo (mouse, menus e gestos), por categoria, no fim de cada grupo.
Map<KeyCategory, List<(String, String)>> _extras() => {
  KeyCategory.markers: [
    ('Arrastar · duplo clique', 'Move (com encaixe) · renomeia o marcador na régua'),
    ('Botão direito', 'Menu do marcador: cor, loop da seção, apagar'),
    ('Menu Seções', 'Lista de marcadores, loop entre marcadores e da seção'),
  ],
  KeyCategory.view: [
    ('Menu Visão', 'Altura das faixas (pequena, média, grande), seguir o cursor, régua em mm:ss'),
    ('Clique em "comp."/"mm:ss"', 'Alterna a régua entre compassos e tempo'),
    ('Visão geral (embaixo)', 'Clique ou arraste para rolar o projeto'),
  ],
  KeyCategory.edit: [('$modKey + roda', 'Zoom no ponto do mouse'), ('Shift + roda', 'Rolar na horizontal')],
  KeyCategory.midiLearn: [('Botão direito · toque longo', 'Menu do controle: aprender ou remover o mapeamento')],
  KeyCategory.keyboard: [
    (noteKeyLetters.map(KeyboardLayoutHints.instance.labelFor).join(' '), 'Notas: do dó até o ré# da oitava de cima'),
    if (KeyboardLayoutHints.instance.differsFromQwerty)
      ('Por posição', 'As teclas de nota, oitava e velocidade seguem a posição no teclado (a fileira do A), não a letra: o seu layout não é QWERTY.'),
  ],
  KeyCategory.pianoRoll: [
    ('Clique no vazio', 'Nova nota (arraste para a duração)'),
    ('Alt ao arrastar', 'Sem grade; no começo do arraste, duplica'),
    ('Menu Ferramentas', 'Escala, acordes, arpejador, rampa de velocidade, inverter, escalar o tempo, fantasmas'),
  ],
};

/// As letras que viram outra coisa com o teclado do computador ligado: cada tecla sem Ctrl/Cmd nem Alt, de ação do
/// estúdio ou do piano roll, que é de nota ou de oitava/velocidade. Sai do catálogo e dos atalhos atuais.
List<(String, String)> suspendedShortcutsOf(Keymap km) {
  final noteLetters = noteKeyLetters.toSet();
  // token → rótulo da ação do teclado tocando que o usa (em minúsculas)
  final playing = <String, String>{};
  for (final a in keyCatalog) {
    if (a.context != KeyContext.playing) continue;
    for (final c in km.bindingsOf(a.id)) {
      playing[c.token] = a.label.toLowerCase();
    }
  }
  final out = <(String, String)>[];
  for (final a in keyCatalog) {
    if (a.context == KeyContext.playing) continue;
    final hit = [
      for (final c in km.bindingsOf(a.id))
        if (!c.mod && !c.alt && (noteLetters.contains(c.token) || playing.containsKey(c.token))) c,
    ];
    if (hit.isEmpty) continue;
    final first = hit.first.token;
    final becomes = playing[first] ?? 'nota';
    out.add((hit.map((c) => c.label).join('  ·  '), '${a.label} (vira $becomes)'));
  }
  return out;
}

/// Os grupos da janela: título e linhas (teclas, descrição).
List<(String, List<(String, String)>)> shortcutGroups(Keymap km) {
  final extras = _extras();
  final groups = <(String, List<(String, String)>)>[];
  for (final cat in KeyCategory.values) {
    final rows = <(String, String)>[];
    for (final a in keyCatalog) {
      if (a.category != cat) continue;
      // o teclado tocando fica no fim do grupo dele, com o texto próprio
      rows.add((km.labelOf(a.id, none: '—').replaceAll(' · ', '  ·  '), a.helpText));
    }
    rows.addAll(extras[cat] ?? const []);
    if (cat == KeyCategory.keyboard) {
      // sem atalho no liga/desliga, o título não diz "Sem atalho liga": só o botão da barra liga
      groups.add((km.bindingsOf('kbd.toggle').isEmpty ? cat.title : '${cat.title} (${km.labelOf('kbd.toggle')} liga)', rows));
    } else {
      groups.add((cat.title, rows));
    }
  }
  final suspended = suspendedShortcutsOf(km);
  if (suspended.isNotEmpty) {
    groups.add((
      'Suspensos enquanto o teclado do computador está ligado',
      [
        ...suspended,
        (
          'Com $modKey',
          km.bindingsOf('kbd.toggle').isEmpty
              ? 'Os atalhos com $modKey continuam valendo (desfazer, duplicar, importar); o teclado do computador desliga pelo botão da barra'
              : 'Os atalhos com $modKey continuam valendo (desfazer, duplicar, importar, ${km.labelOf('kbd.toggle')} desliga o teclado)',
        ),
        // decisão: o Shift não dá prioridade ao atalho; a tecla de nota vale com ou sem ele
        ('Com Shift', 'Não muda nada: Shift+L toca a nota L, como L. Os atalhos com Shift nessas letras ficam suspensos; desligue o teclado para usá-los'),
      ],
    ));
  }
  return groups;
}

/// O botão "Personalizar" aparece em todo aparelho: quem tem teclado físico ligado no celular ou no tablet (Android
/// com teclado Bluetooth, por exemplo) também personaliza. Sem nenhuma tecla vista, a tela de personalizar avisa que
/// precisa de um teclado físico ([shortcutsNeedKeyboardHint]).
bool get canCustomizeShortcuts => true;

Future<void> showShortcuts(BuildContext context, {bool? canCustomize, Keymap? keymap}) => showDialog<void>(
  context: context,
  builder: (_) => ShortcutsDialog(canCustomize: canCustomize ?? canCustomizeShortcuts, keymap: keymap ?? Keymap.instance),
);

class ShortcutsDialog extends StatefulWidget {
  final bool canCustomize;
  final Keymap keymap;
  const ShortcutsDialog({super.key, required this.canCustomize, required this.keymap});

  @override
  State<ShortcutsDialog> createState() => _ShortcutsDialogState();
}

class _ShortcutsDialogState extends State<ShortcutsDialog> {
  var _customizing = false;

  @override
  void initState() {
    super.initState();
    widget.keymap.load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final narrow = MediaQuery.sizeOf(context).width < 520;
    return AlertDialog(
      insetPadding: EdgeInsets.symmetric(horizontal: narrow ? 12 : 40, vertical: 24),
      contentPadding: EdgeInsets.fromLTRB(narrow ? 16 : 24, 16, narrow ? 16 : 24, 0),
      title: Text(_customizing ? 'Personalizar atalhos' : 'Atalhos do teclado'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(child: _customizing ? KeymapEditor(keymap: widget.keymap) : _list(theme, narrow)),
      ),
      actions: [
        if (widget.canCustomize)
          TextButton(
            key: const ValueKey('shortcuts-customize'),
            onPressed: () => setState(() => _customizing = !_customizing),
            child: Text(_customizing ? 'Voltar à lista' : 'Personalizar'),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fechar')),
      ],
    );
  }

  Widget _list(ThemeData theme, bool narrow) {
    final keyStyle = theme.textTheme.labelMedium!.copyWith(fontFeatures: const [FontFeature.tabularFigures()], color: Palette.accent);
    return ListenableBuilder(
      listenable: widget.keymap,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (title, items) in shortcutGroups(widget.keymap)) ...[
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 6),
              child: Text(title.toUpperCase(), style: theme.textTheme.labelSmall!.copyWith(letterSpacing: 0.8, color: Colors.white54)),
            ),
            for (final (keys, what) in items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: narrow
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(keys, style: keyStyle),
                          Text(what, style: theme.textTheme.bodyMedium),
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(width: 210, child: Text(keys, style: keyStyle)),
                          Expanded(child: Text(what, style: theme.textTheme.bodyMedium)),
                        ],
                      ),
              ),
          ],
        ],
      ),
    );
  }
}
