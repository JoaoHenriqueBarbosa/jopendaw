/// Janela com os atalhos do teclado do estúdio (tecla ? ou o botão de ajuda da barra).
library;

import 'package:flutter/material.dart';

import '../widgets/format.dart';
import '../widgets/theme.dart';

String get _mod => modKey;

/// Atalhos de letra que viram nota, oitava ou velocidade com o teclado do computador ligado (a
/// camada dele vem antes; só o que tem $_mod escapa). Cada tecla daqui está em `noteKeys` ou é Z/X/C/V.
const suspendedShortcuts = <(String, String)>[
  ('C', 'Metrônomo (vira velocidade menor)'),
  ('L', 'Loop liga/desliga (vira nota)'),
  ('S', 'Cortar no cursor (vira nota)'),
  ('X', 'Mixer (vira oitava acima)'),
  ('Z  ·  Shift+Z', 'Enquadrar projeto / clipe (vira oitava abaixo)'),
  ('E', 'Editor de notas (vira nota)'),
  ('F', 'Efeitos da faixa (vira nota)'),
  ('K  ·  J', 'Dividir / unir notas no piano roll (viram nota)'),
  ('Shift+K', 'Aprender MIDI liga/desliga (vira nota)'),
  ('Shift+H  ·  Shift+L', 'Humanizar e legato no piano roll; Shift+L também faz o loop no clipe (viram nota)'),
];

List<(String, List<(String, String)>)> _groups() => [
  (
    'Transporte',
    [
      ('Espaço', 'Tocar / pausar'),
      ('Enter · Home', 'Parar e voltar ao começo (ou ao início do loop)'),
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
      ('Menu Visão', 'Altura das faixas (pequena, média, grande), seguir o cursor, régua em mm:ss'),
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
      ('Delete · Backspace', 'Apagar o clipe'),
      ('$_mod+I', 'Importar áudio ou MIDI'),
      ('+  (ou  =)  /  −', 'Aproximar / afastar'),
      ('$_mod + roda', 'Zoom no ponto do mouse'),
      ('Shift + roda', 'Rolar na horizontal'),
    ],
  ),
  (
    'Aprender MIDI',
    [
      ('Shift+K', 'Liga o modo: os controles ganham contorno; clique num e mexa no botão do teclado'),
      ('Botão direito · toque longo', 'Menu do controle: aprender ou remover o mapeamento'),
      ('Esc', 'Cancela o controle armado; de novo, sai do modo'),
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
      ('Z  /  X', 'Oitava abaixo / acima (só da faixa que está tocando: a bateria começa no C2)'),
      ('C  /  V', 'Velocidade menor / maior'),
    ],
  ),
  (
    'Suspensos enquanto o teclado do computador está ligado',
    [
      for (final (keys, what) in suspendedShortcuts) (keys, what),
      ('Com $_mod', 'Os atalhos com $_mod continuam valendo (desfazer, duplicar, importar, $_mod+K desliga o teclado)'),
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
      ('K', 'Dividir as notas no cursor (a seleção, ou todas)'),
      ('J', 'Unir notas iguais adjacentes'),
      ('Shift+H', 'Humanizar com os últimos ajustes'),
      ('Shift+L', 'Legato: cada nota vai até a próxima'),
      ('Menu Ferramentas', 'Escala, acordes, arpejador, rampa de velocidade, inverter, escalar o tempo, fantasmas'),
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
