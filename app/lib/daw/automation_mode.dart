/// Modos de gravação da automação (Ler, Escrever, Toque, Trava) e os seletores deles: o botão da
/// barra do transporte (vale para todas as raias) e o botão pequeno no cabeçalho de cada raia
/// (vale só para ela e sobrepõe o da barra). A gravação em si está em `automation_record.dart`.
library;

import 'package:flutter/material.dart';

import '../widgets/theme.dart';
import 'controller.dart';
import 'model.dart';

enum AutoMode {
  /// Só toca a automação (padrão): mexer no controle muda o valor fixo, como sempre foi.
  read('Ler', 'L', 'Só toca a automação; mexer no controle não grava.'),

  /// Depois da primeira mudança de valor no controle grava o tempo todo enquanto toca, sobrescrevendo (na barra
  /// ou no modo próprio da raia: sem mexer no controle não se apaga a curva antiga).
  write('Escrever', 'E', 'Começa ao mexer no controle (só agarrar não basta): grava até parar, sobrescrevendo o que já havia.'),

  /// Grava só enquanto o controle está seguro; ao soltar, volta ao valor automatizado com uma rampa curta.
  touch('Toque', 'T', 'Começa ao mexer no controle (só agarrar não basta) e grava enquanto você o segura; ao soltar, volta ao valor automatizado.'),

  /// Grava enquanto o controle está seguro e mantém o último valor até parar.
  latch('Trava', 'V', 'Começa ao mexer no controle (só agarrar não basta) e grava enquanto você o segura; mantém o último valor até parar.');

  final String label, short, hint;
  const AutoMode(this.label, this.short, this.hint);

  /// Este modo grava (todos menos Ler).
  bool get records => this != read;
}

/// Botão da barra do transporte: "Automação: Ler/Escrever/Toque/Trava". Aceso (vermelho) fora do
/// Ler. Mostra também o aviso da gravação (controle sem automação, gravação de áudio em curso).
class AutoModeMenu extends StatelessWidget {
  final DawController c;
  final bool compact;
  const AutoModeMenu({super.key, required this.c, required this.compact});

  @override
  Widget build(BuildContext context) {
    final rec = c.autoRec;
    return ListenableBuilder(
      listenable: rec,
      builder: (context, _) {
        final m = rec.mode;
        final on = m.records;
        final color = on ? automationRecordColor : Colors.white70;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PopupMenuButton<AutoMode>(
              tooltip: 'Automação: ${m.label}. ${m.hint}',
              initialValue: m,
              onSelected: rec.setMode,
              itemBuilder: (_) => [
                for (final x in AutoMode.values)
                  PopupMenuItem(
                    value: x,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(x.label),
                        Text(x.hint, style: const TextStyle(fontSize: 11, color: Colors.white54)),
                      ],
                    ),
                  ),
              ],
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(color: on ? automationRecordColor.withValues(alpha: 0.12) : null, borderRadius: BorderRadius.circular(6)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.show_chart, size: 18, color: color),
                    // só o ícone em Ler (o padrão): com o rótulo a barra passava de 1500 px e a nuvem e os
                    // atalhos saíam da tela; gravando, o modo aparece em vermelho com o nome
                    if (on) ...[
                      const SizedBox(width: 4),
                      Text(
                        compact ? m.short : m.label,
                        style: TextStyle(fontWeight: FontWeight.w700, color: color),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (rec.notice != null)
              Flexible(
                child: Text(
                  rec.notice!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Palette.danger),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Cor do que está gravando automação (vermelho de gravação).
const automationRecordColor = Color(0xFFF2433A);

/// Seletor pequeno no cabeçalho da raia: o modo dela ("Barra" segue o da barra do transporte).
class AutoLaneModeButton extends StatelessWidget {
  final DawController c;
  final AutoLane lane;
  const AutoLaneModeButton({super.key, required this.c, required this.lane});

  @override
  Widget build(BuildContext context) {
    final rec = c.autoRec;
    return ListenableBuilder(
      listenable: rec,
      builder: (context, _) {
        final own = rec.laneModes[lane.id];
        final m = own ?? rec.mode;
        final on = m.records;
        return PopupMenuButton<AutoMode?>(
          tooltip: 'Modo de automação desta raia: ${m.label}${own == null ? ' (o da barra)' : ''}',
          padding: EdgeInsets.zero,
          onSelected: (v) => rec.setLaneMode(lane.id, v),
          itemBuilder: (_) => [
            PopupMenuItem<AutoMode?>(value: null, child: Text('Seguir a barra (${rec.mode.label})')),
            for (final x in AutoMode.values) PopupMenuItem<AutoMode?>(value: x, child: Text(x.label)),
          ],
          child: Container(
            width: 24,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? automationRecordColor.withValues(alpha: 0.18) : null,
              border: Border.all(color: own == null ? Colors.white12 : (on ? automationRecordColor : Colors.white38)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              m.short,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: on ? automationRecordColor : Colors.white60),
            ),
          ),
        );
      },
    );
  }
}
