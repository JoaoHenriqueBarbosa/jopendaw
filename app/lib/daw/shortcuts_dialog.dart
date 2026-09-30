/// Janela com os atalhos do teclado do estúdio (tecla ? ou o botão de ajuda da barra).
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../widgets/theme.dart';

/// Tecla de modificador do sistema: Cmd no Mac, Ctrl nos outros.
String get _mod => defaultTargetPlatform == TargetPlatform.macOS || defaultTargetPlatform == TargetPlatform.iOS ? '⌘' : 'Ctrl';

List<(String, List<(String, String)>)> _groups() => [
  (
    'Transporte',
    [
      ('Espaço', 'Tocar / pausar'),
      ('Enter', 'Parar e voltar ao começo (ou ao início do loop)'),
      ('R', 'Gravar (com faixas armadas)'),
      ('L', 'Loop liga/desliga (arraste na régua para marcar a região)'),
      ('C', 'Metrônomo'),
    ],
  ),
  (
    'Marcadores e loop',
    [
      ('M', 'Marcador no cursor (Shift+M: pede o nome)'),
      ('[  /  ]', 'Cursor no marcador anterior / seguinte'),
      ('Shift+L', 'Loop no clipe selecionado (ou na seção do cursor)'),
      ('Arrastar · duplo clique', 'Move (com encaixe) · renomeia o marcador na régua'),
      ('Botão direito', 'Menu do marcador: cor, loop da seção, apagar'),
      ('Menu Seções', 'Lista de marcadores, loop entre marcadores e da seção'),
    ],
  ),
  (
    'Visão',
    [
      ('Z', 'Enquadrar o projeto inteiro'),
      ('Shift+Z', 'Enquadrar o clipe selecionado'),
      ('Menu Visão', 'Altura das faixas (P/M/G), seguir o cursor, régua em mm:ss'),
      ('Clique em "comp."/"mm:ss"', 'Alterna a régua entre compassos e tempo'),
      ('Visão geral (embaixo)', 'Clique ou arraste para rolar o projeto'),
    ],
  ),
  (
    'Edição',
    [
      ('$_mod+Z', 'Desfazer'),
      ('$_mod+Shift+Z  ou  $_mod+Y', 'Refazer'),
      ('$_mod+D', 'Duplicar o clipe'),
      ('S', 'Cortar no cursor'),
      ('Delete', 'Apagar o clipe'),
      ('$_mod+I', 'Importar áudio'),
      ('+  /  −', 'Aproximar / afastar'),
      ('$_mod + roda', 'Zoom no ponto do mouse'),
      ('Shift + roda', 'Rolar na horizontal'),
    ],
  ),
  (
    'Painéis',
    [
      ('X', 'Mixer'),
      ('E', 'Editor de notas (piano roll)'),
      ('I', 'Instrumento da faixa'),
      ('F', 'Efeitos da faixa'),
      ('Esc', 'Fechar o painel'),
      ('?', 'Esta janela'),
    ],
  ),
  (
    'Teclado do computador ($_mod+K liga)',
    [
      ('A W S E D F T G Y H U J K O L P', 'Notas: do dó até o ré# da oitava de cima'),
      ('Z  /  X', 'Oitava abaixo / acima (com o teclado ligado, o Z não enquadra)'),
      ('C  /  V', 'Velocidade menor / maior'),
    ],
  ),
  (
    'Piano roll',
    [
      ('Clique no vazio', 'Nova nota (arraste para a duração)'),
      ('Alt ao arrastar', 'Sem grade; no começo do arraste, duplica'),
      ('$_mod+A · $_mod+C/X/V · $_mod+D', 'Tudo · copiar/recortar/colar no cursor · duplicar'),
      ('↑ ↓  (Shift: oitava)', 'Transpor'),
      ('← →  (Shift: compasso)', 'Mover pela grade'),
      ('Q', 'Quantizar'),
    ],
  ),
];

Future<void> showShortcuts(BuildContext context) => showDialog<void>(context: context, builder: (_) => const _ShortcutsDialog());

class _ShortcutsDialog extends StatelessWidget {
  const _ShortcutsDialog();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final keyStyle = theme.textTheme.labelMedium!.copyWith(fontFeatures: const [FontFeature.tabularFigures()], color: Palette.accent);
    return AlertDialog(
      title: const Text('Atalhos do teclado'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (title, items) in _groups()) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 6),
                  child: Text(title.toUpperCase(), style: theme.textTheme.labelSmall!.copyWith(letterSpacing: 0.8, color: Colors.white54)),
                ),
                for (final (keys, what) in items)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
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
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fechar'))],
    );
  }
}
