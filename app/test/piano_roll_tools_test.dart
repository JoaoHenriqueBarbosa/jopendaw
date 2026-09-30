// Menu Ferramentas do piano roll (escala, acordes, arpejo e transformações) contra o controlador
// de verdade: cada ferramenta é uma edição só no histórico.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jopendaw_app/daw/instruments.dart';
import 'package:jopendaw_app/daw/model.dart';

import 'piano_roll_test.dart' show TestDaw, click, geoFor, host, key, mac, riff, settle;

void main() {
  Future<void> sized(WidgetTester t) async {
    t.view.physicalSize = const Size(1200, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
  }

  Future<void> open(WidgetTester t, List<String> path) async {
    await t.tap(find.text('Ferramentas'));
    await t.pumpAndSettle();
    for (final label in path) {
      await t.tap(find.text(label).last);
      await t.pumpAndSettle();
    }
  }

  List<double> lens(TestDaw c) => [for (final n in c.clip.notes) n.length];

  mac('o menu Ferramentas agrupa tudo', (t) async {
    await sized(t);
    final c = TestDaw(notes: riff());
    await t.pumpWidget(host(c, height: 500));
    await t.pump();
    expect(find.text('Ferramentas'), findsOneWidget);
    expect(find.text('Escala'), findsOneWidget);
    await t.tap(find.text('Ferramentas'));
    await t.pumpAndSettle();
    for (final g in ['Escala e acordes', 'Seleção', 'Escalar o tempo', 'Cortar e limpar', 'Fantasmas']) {
      expect(find.text(g), findsOneWidget, reason: g);
    }
    await t.tap(find.text('Seleção'));
    await t.pumpAndSettle();
    for (final i in ['Humanizar…', 'Rampa de velocidade', 'Legato', 'Staccato…', 'Inverter no tempo', 'Inverter na altura', 'Reverter a ordem das notas']) {
      expect(find.text(i), findsOneWidget, reason: i);
    }
    await settle(t);
  });

  mac('bateria não mostra escala nem acordes', (t) async {
    await sized(t);
    final c = TestDaw(kind: TrackKind.drums, notes: [MidiNote(pitch: 36, start: 0, length: .25)]);
    await t.pumpWidget(host(c, height: 500));
    await t.pump();
    expect(find.text('Escala'), findsNothing);
    await open(t, ['Escala e acordes']);
    expect(find.text('Escala…'), findsNothing);
    expect(find.text('Inserir acorde…'), findsNothing);
    await settle(t);
  });

  mac('legato pelo menu: um passo de desfazer, e nada muda sem mudar de fato', (t) async {
    await sized(t);
    final c = TestDaw(notes: riff());
    await t.pumpWidget(host(c, height: 500));
    await t.pump();
    final before = lens(c);
    await open(t, ['Seleção', 'Legato']);
    // tudo o que não estava selecionado entra: cada nota vai até o início da próxima
    expect(c.clip.notes[0].length, 1); // 60: 0 -> 1
    expect(c.clip.notes[2].length, .5); // 67: 1.5 -> 2
    expect(c.clip.notes[3].length, 2); // 72: 2 -> 4
    expect(lens(c), isNot(before));
    c.undo();
    await t.pump();
    expect(lens(c), before);
    // legato de novo em notas que já são legato não grava histórico
    await open(t, ['Seleção', 'Legato']);
    final after = lens(c);
    final undos = c.canUndo;
    await open(t, ['Seleção', 'Legato']);
    expect(lens(c), after);
    expect(c.canUndo, undos);
    await settle(t);
  });

  mac('staccato e escalar o tempo por diálogo', (t) async {
    await sized(t);
    final c = TestDaw(notes: [MidiNote(pitch: 60, start: 0, length: 1), MidiNote(pitch: 62, start: 2, length: 1)]);
    await t.pumpWidget(host(c, height: 500));
    await t.pump();
    await open(t, ['Escalar o tempo', '×2 (dobro)']);
    expect([for (final n in c.clip.notes) n.start], [0, 4]);
    expect(lens(c), [2, 2]);
    await open(t, ['Escalar o tempo', '×0,5 (metade)']);
    expect([for (final n in c.clip.notes) n.start], [0, 2]);
    await open(t, ['Seleção', 'Staccato…']);
    expect(find.text('Staccato'), findsWidgets);
    await t.tap(find.text('Encurtar'));
    await t.pumpAndSettle();
    expect(lens(c), [.5, .5]);
    await settle(t);
  });

  mac('escala do clipe: escolhida no diálogo e guardada no clipe', (t) async {
    await sized(t);
    final c = TestDaw(notes: riff());
    await t.pumpWidget(host(c, height: 500));
    await t.pump();
    expect(c.clip.scale, isNull);
    await t.tap(find.text('Escala'));
    await t.pumpAndSettle();
    expect(find.text('Escala do clipe'), findsOneWidget);
    await t.tap(find.text('A'));
    await t.tap(find.text('Menor natural'));
    await t.pump();
    await t.tap(find.text('Aplicar'));
    await t.pumpAndSettle();
    expect(c.clip.scale, '9:minor');
    expect(find.text('A menor natural'), findsOneWidget);
    // a escala vai no JSON do clipe
    expect(c.clip.toJson()['scale'], '9:minor');
    // desfazer tira a escala
    c.undo();
    await t.pump();
    expect(c.clip.scale, isNull);
    // e dá para tirar pelo diálogo
    c.clip.scale = '0:major';
    c.notifyListeners();
    await t.pump();
    await t.tap(find.text('C maior'));
    await t.pumpAndSettle();
    await t.tap(find.text('Sem escala'));
    await t.pumpAndSettle();
    expect(c.clip.scale, isNull);
    await settle(t);
  });

  mac('prender na escala: nota desenhada fora dela encaixa na mais próxima', (t) async {
    await sized(t);
    final c = TestDaw(notes: riff());
    c.clip.scale = '0:major';
    await t.pumpWidget(host(c, height: 500));
    await t.pump();
    final g = geoFor(c, height: 500);
    // sem prender, C# (61) fica onde foi clicado
    await click(t, g.at(1, 61));
    expect(c.clip.notes.last.pitch, 61);
    c.undo();
    await t.pump();
    // ligando o "Prender na escala" no menu, cai em C (60)
    await open(t, ['Escala e acordes', 'Prender na escala']);
    await click(t, g.at(1, 61));
    expect(c.clip.notes.last.pitch, 60);
    // desligar de novo (as preferências valem para a sessão)
    await open(t, ['Escala e acordes', 'Prender na escala']);
    await click(t, g.at(1, 61));
    expect(c.clip.notes.last.pitch, 61);
    await settle(t);
  });

  mac('inserir acorde: a nota vira o acorde escolhido, num passo só', (t) async {
    await sized(t);
    final c = TestDaw(notes: [MidiNote(pitch: 60, start: 0, length: 2, velocity: .6)]);
    await t.pumpWidget(host(c, height: 500));
    await t.pump();
    final g = geoFor(c, height: 500);
    await click(t, g.at(1, 60));
    await open(t, ['Escala e acordes', 'Inserir acorde…']);
    expect(find.text('Acorde'), findsOneWidget);
    await t.tap(find.text('Menor'));
    await t.tap(find.text('Fundamental'));
    await t.pump();
    await t.tap(find.text('Inserir nas notas'));
    await t.pumpAndSettle();
    expect([for (final n in c.clip.notes) n.pitch]..sort(), [60, 63, 67]);
    for (final n in c.clip.notes) {
      expect(n.length, 2);
      expect(n.velocity, .6);
    }
    c.undo();
    await t.pump();
    expect(c.clip.notes.length, 1);
    await settle(t);
  });

  mac('acorde com inversão e desdobrar em arpejo', (t) async {
    await sized(t);
    final c = TestDaw(notes: [MidiNote(pitch: 60, start: 0, length: 3)]);
    await t.pumpWidget(host(c, height: 500));
    await t.pump();
    final g = geoFor(c, height: 500);
    await click(t, g.at(1, 60));
    await open(t, ['Escala e acordes', 'Inserir acorde…']);
    await t.tap(find.text('Maior'));
    await t.tap(find.text('1ª'));
    await t.pump();
    await t.tap(find.text('Inserir nas notas'));
    await t.pumpAndSettle();
    // a inversão troca a nota original: mi, sol, dó de cima
    expect([for (final n in c.clip.notes) n.pitch]..sort(), [64, 67, 72]);
    // as três continuam selecionadas: desdobrar em arpejo divide os 3 tempos
    await open(t, ['Escala e acordes', 'Desdobrar acorde em arpejo']);
    expect([for (final n in c.clip.notes) n.start]..sort(), [0, 1, 2]);
    expect(lens(c), everyElement(1));
    await settle(t);
  });

  mac('acorde diatônico só aparece com escala e usa o grau', (t) async {
    await sized(t);
    final c = TestDaw(notes: [MidiNote(pitch: 62, start: 0, length: 1)]);
    c.clip.scale = '0:major';
    await t.pumpWidget(host(c, height: 500));
    await t.pump();
    final g = geoFor(c, height: 500);
    await click(t, g.at(.5, 62));
    await open(t, ['Escala e acordes', 'Inserir acorde…']);
    await t.tap(find.text('Diatônico: tríade'));
    await t.tap(find.text('Fundamental'));
    await t.pump();
    await t.tap(find.text('Inserir nas notas'));
    await t.pumpAndSettle();
    // ré menor (ii de dó maior): D F A
    expect([for (final n in c.clip.notes) n.pitch]..sort(), [62, 65, 69]);
    await settle(t);
  });

  mac('acorde no clique cria o acorde e o arraste dá a duração a todas', (t) async {
    await sized(t);
    final c = TestDaw(notes: riff());
    await t.pumpWidget(host(c, height: 500));
    await t.pump();
    final g = geoFor(c, height: 500);
    await open(t, ['Escala e acordes', 'Acorde no clique']);
    await t.tap(find.text('Maior'));
    await t.tap(find.text('Fundamental'));
    await t.tap(find.text('Usar no clique'));
    await t.pumpAndSettle();
    final n0 = c.clip.notes.length;
    await click(t, g.at(6, 55));
    expect(c.clip.notes.length, n0 + 3);
    expect([for (final n in c.clip.notes.skip(n0)) n.pitch], [55, 59, 62]);
    c.undo();
    await t.pump();
    expect(c.clip.notes.length, n0);
    // desligar pelo menu
    await open(t, ['Escala e acordes']);
    await t.tap(find.textContaining('Acorde no clique:'));
    await t.pumpAndSettle();
    await click(t, g.at(6, 55));
    expect(c.clip.notes.length, n0 + 1);
    await settle(t);
  });

  mac('arpejador aplica sobre a seleção', (t) async {
    await sized(t);
    final c = TestDaw(notes: [MidiNote(pitch: 60, start: 0, length: 1), MidiNote(pitch: 64, start: 0, length: 1), MidiNote(pitch: 67, start: 0, length: 1)]);
    await t.pumpWidget(host(c, height: 500));
    await t.pump();
    await key(t, LogicalKeyboardKey.keyA, ctrl: true);
    await open(t, ['Escala e acordes', 'Arpejador…']);
    expect(find.text('Arpejador'), findsOneWidget);
    await t.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('1/16')));
    await t.pump();
    await t.tap(find.text('Arpejar'));
    await t.pumpAndSettle();
    expect([for (final n in c.clip.notes) n.pitch], [60, 64, 67, 60]);
    expect([for (final n in c.clip.notes) n.start], [0, .25, .5, .75]);
    c.undo();
    await t.pump();
    expect(c.clip.notes.length, 3);
    await settle(t);
  });

  mac('humanizar é determinístico com a semente e desfaz num passo (Shift+H)', (t) async {
    await sized(t);
    List<double> starts(TestDaw c) => [for (final n in c.clip.notes) n.start];
    final c = TestDaw(notes: [for (var i = 1; i <= 8; i++) MidiNote(pitch: 60, start: i * .5, length: .25)]);
    await t.pumpWidget(host(c, height: 500));
    await t.pump();
    final before = starts(c);
    await open(t, ['Seleção', 'Humanizar…']);
    await t.tap(find.text('Humanizar').last);
    await t.pumpAndSettle();
    final once = starts(c);
    expect(once, isNot(before));
    c.undo();
    await t.pump();
    expect(starts(c), before);
    // Shift+H usa a próxima semente: outro resultado, também desfazível
    await key(t, LogicalKeyboardKey.keyH, shift: true);
    expect(starts(c), isNot(before));
    expect(starts(c), isNot(once));
    c.undo();
    await t.pump();
    expect(starts(c), before);
    await settle(t);
  });

  mac('K divide as notas no cursor e J une de volta', (t) async {
    await sized(t);
    final c = TestDaw(notes: [MidiNote(pitch: 72, start: 2, length: 2), MidiNote(pitch: 60, start: 0, length: 1)]);
    await t.pumpWidget(host(c, height: 500));
    await t.pump();
    // o clipe começa no compasso 2 (batida 4): cursor na batida 6.5 do arranjo = 2.5 do clipe
    c.seek(c.clip.start + 2.5);
    await t.pump();
    await key(t, LogicalKeyboardKey.keyK);
    final highs = c.clip.notes.where((n) => n.pitch == 72).toList();
    expect(highs.length, 2);
    expect([for (final n in highs) n.start]..sort(), [2, 2.5]);
    expect([for (final n in highs) n.length]..sort(), [.5, 1.5]);
    await key(t, LogicalKeyboardKey.keyJ);
    final joined = c.clip.notes.where((n) => n.pitch == 72).toList();
    expect(joined.length, 1);
    expect(joined.single.start, 2);
    expect(joined.single.length, 2);
    await settle(t);
  });

  mac('remover duplicadas e aparar sobrepostas', (t) async {
    await sized(t);
    final c = TestDaw(
      notes: [
        MidiNote(pitch: 60, start: 0, length: 1),
        MidiNote(pitch: 60, start: 0, length: 1),
        MidiNote(pitch: 62, start: 0, length: 3),
        MidiNote(pitch: 62, start: 1, length: 1),
      ],
    );
    await t.pumpWidget(host(c, height: 500));
    await t.pump();
    await open(t, ['Cortar e limpar', 'Remover duplicadas']);
    expect(c.clip.notes.length, 3);
    await open(t, ['Cortar e limpar', 'Aparar sobrepostas']);
    expect(c.clip.notes.where((n) => n.pitch == 62).map((n) => n.length).toList()..sort(), [1, 1]);
    await settle(t);
  });

  mac('fantasmas: notas de outro clipe da faixa aparecem sem serem editáveis', (t) async {
    await sized(t);
    final c = TestDaw(notes: riff());
    // outro clipe na mesma faixa, e uma segunda faixa de instrumento
    c.doc.tracks[0].midi.add(MidiClip(id: 'outro', name: 'Outro', start: 20, length: 4, notes: [MidiNote(pitch: 65, start: 0, length: 1)]));
    c.doc.tracks.add(
      DawTrack(
        id: 't2',
        name: 'Baixo',
        color: 1,
        kind: TrackKind.synth,
        midi: [
          MidiClip(id: 'b', start: 4, length: 8, notes: [MidiNote(pitch: 48, start: 0, length: 2)]),
        ],
      ),
    );
    await t.pumpWidget(host(c, height: 500));
    await t.pump();
    expect(t.takeException(), isNull);
    await open(t, ['Fantasmas', 'Outras faixas de instrumento']);
    expect(t.takeException(), isNull);
    // não entram no clipe aberto
    expect(c.clip.notes.length, riff().length);
    await open(t, ['Fantasmas', 'Outras faixas de instrumento']);
    await open(t, ['Fantasmas', 'Outros clipes da faixa']);
    await open(t, ['Fantasmas', 'Outros clipes da faixa']);
    expect(t.takeException(), isNull);
    await settle(t);
  });

  mac('colar prende na escala', (t) async {
    await sized(t);
    final c = TestDaw(notes: [MidiNote(pitch: 61, start: 0, length: 1), MidiNote(pitch: 63, start: 1, length: 1)]);
    c.clip.scale = '0:major';
    await t.pumpWidget(host(c, height: 500));
    await t.pump();
    await key(t, LogicalKeyboardKey.keyA, ctrl: true);
    await key(t, LogicalKeyboardKey.keyC, ctrl: true);
    await open(t, ['Escala e acordes', 'Prender na escala']);
    await key(t, LogicalKeyboardKey.keyV, ctrl: true);
    final pasted = c.clip.notes.skip(2).map((n) => n.pitch).toList();
    expect(pasted, [60, 62]);
    await open(t, ['Escala e acordes', 'Prender na escala']);
    await settle(t);
  });

  mac('escalar o tempo estica o clipe até o compasso onde as notas acabam; desfazer volta tudo', (t) async {
    await sized(t);
    final c = TestDaw(clipLength: 4, notes: [MidiNote(pitch: 60, start: 0, length: 1), MidiNote(pitch: 62, start: 2, length: 1)]);
    await t.pumpWidget(host(c, height: 500));
    await t.pump();
    await open(t, ['Escalar o tempo', '×2 (dobro)']);
    // a segunda nota agora vai de 4 a 6: sem esticar o clipe (4) ela ficaria muda
    expect([for (final n in c.clip.notes) n.start], [0, 4]);
    expect(c.clip.length, 8);
    c.undo();
    await t.pump();
    expect(c.clip.length, 4);
    expect([for (final n in c.clip.notes) n.start], [0, 2]);
    // encurtar de volta não encolhe o clipe
    await open(t, ['Escalar o tempo', '×2 (dobro)']);
    await open(t, ['Escalar o tempo', '×0,5 (metade)']);
    expect(c.clip.length, 8);
    await settle(t);
  });

  mac('legato estica o clipe quando a nota já passava do fim', (t) async {
    await sized(t);
    // duas notas começam dentro do clipe (4); a última já passa do fim e o legato não pode encolher nada
    final c = TestDaw(clipLength: 4, notes: [MidiNote(pitch: 60, start: 0, length: 1), MidiNote(pitch: 62, start: 3.5, length: 1)]);
    await t.pumpWidget(host(c, height: 500));
    await t.pump();
    await open(t, ['Seleção', 'Legato']);
    expect(c.clip.notes[0].length, 3.5);
    expect(c.clip.length, 4); // nada passou do que já passava: o clipe fica como está
    await settle(t);
  });

  mac('prender na escala como ação sobre a seleção', (t) async {
    await sized(t);
    final c = TestDaw(notes: [MidiNote(pitch: 61, start: 0, length: 1), MidiNote(pitch: 63, start: 1, length: 1), MidiNote(pitch: 64, start: 2, length: 1)]);
    c.clip.scale = '0:major';
    await t.pumpWidget(host(c, height: 500));
    await t.pump();
    await open(t, ['Escala e acordes', 'Prender seleção na escala']);
    // todas as notas (nada selecionado): 61 e 63 saem da escala de C maior
    for (final n in c.clip.notes) {
      expect(const {0, 2, 4, 5, 7, 9, 11}, contains(n.pitch % 12), reason: '${n.pitch}');
    }
    expect(c.clip.notes[2].pitch, 64);
    c.undo();
    await t.pump();
    expect([for (final n in c.clip.notes) n.pitch], [61, 63, 64]);
    await settle(t);
  });

  mac('encaixe ativo também ao transpor com as setas', (t) async {
    await sized(t);
    final c = TestDaw(notes: [MidiNote(pitch: 60, start: 0, length: 1)]);
    c.clip.scale = '0:major';
    await t.pumpWidget(host(c, height: 500));
    await t.pump();
    final g = geoFor(c, height: 500);
    await open(t, ['Escala e acordes', 'Prender na escala']);
    await click(t, g.at(.5, 60));
    // só "prender na escala" ligado: a seta ainda anda de semitom em semitom
    await key(t, LogicalKeyboardKey.arrowUp);
    expect(c.clip.notes[0].pitch, 61);
    await open(t, ['Escala e acordes', 'Manter o encaixe ao mudar a altura']);
    await key(t, LogicalKeyboardKey.arrowUp);
    expect(c.clip.notes[0].pitch, 62);
    await key(t, LogicalKeyboardKey.arrowDown);
    expect(c.clip.notes[0].pitch, 60);
    // limpa as preferências da sessão
    await open(t, ['Escala e acordes', 'Manter o encaixe ao mudar a altura']);
    await open(t, ['Escala e acordes', 'Prender na escala']);
    await settle(t);
  });
}
