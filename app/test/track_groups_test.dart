// Pastas de faixa (fase 14 C): modelo e JSON, agrupar e desagrupar, mover entre pastas, recolher,
// o mixer e o roteamento que vai ao motor.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jopendaw_app/audio/engine.dart';
import 'package:jopendaw_app/daw/controller.dart';
import 'package:jopendaw_app/daw/effects.dart';
import 'package:jopendaw_app/daw/instruments.dart';
import 'package:jopendaw_app/daw/model.dart';
import 'package:jopendaw_app/daw/structure_menu.dart';
import 'package:jopendaw_app/daw/track_groups.dart';
import 'package:jopendaw_app/models/project.dart';
import 'package:jopendaw_app/widgets/theme.dart';

import 'studio_test.dart' show studio, mount, flushSave;

final engine = AudioEngine.instance;

Project _project() => Project.fromJson({
  'id': 'p',
  'name': 'Teste',
  'bpm': 120,
  'beats_per_bar': 4,
  'beat_unit': 4,
  'sample_rate': 48000,
  'created_at': '2026-01-01T00:00:00Z',
  'updated_at': '2026-01-01T00:00:00Z',
});

/// Áudio 1 (a1), Áudio 2 (a2), Synth (s), Bateria (d), Sampler (p) e o retorno "Reverb" (r).
DawController newController() {
  final c = DawController(_project());
  c.doc = DawDoc(
    bpm: 120,
    beatsPerBar: 4,
    tracks: [
      DawTrack(id: 'a1', name: 'Áudio 1', color: 0),
      DawTrack(id: 'a2', name: 'Áudio 2', color: 1),
      DawTrack(id: 's', name: 'Synth', color: 2, kind: TrackKind.synth),
      DawTrack(id: 'd', name: 'Bateria', color: 3, kind: TrackKind.drums),
      DawTrack(id: 'p', name: 'Sampler', color: 4, kind: TrackKind.sampler),
      DawTrack(id: 'r', name: 'Reverb', color: 5, kind: TrackKind.bus),
    ],
  );
  c.ready = true;
  c.mutate((_) {});
  engine.log = [];
  return c;
}

List<List<Object>> sent(String name) => [
  for (final c in engine.log!)
    if (c.first == name) c,
];

List<String> names(DawController c) => [for (final t in c.doc.tracks) t.name];
List<String> ids(DawController c) => [for (final t in c.doc.tracks) t.id];
String snap(DawController c) => jsonEncode(c.doc.toJson());
DawTrack track(DawController c, String id) => c.doc.tracks.firstWhere((t) => t.id == id);

/// Como o motor ficou depois da última sincronização: a saída de cada faixa (índice) que o
/// controlador mandou por último.
Map<int, int> lastOutputs() => {for (final call in sent('track_output')) call[1] as int: call[2] as int};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => engine.log = []);

  group('modelo e JSON', () {
    test('documento antigo, sem os campos, abre igual e volta igual', () {
      final old = jsonDecode(jsonEncode(newController().doc.toJson())) as Map<String, dynamic>;
      for (final t in old['tracks'] as List) {
        expect((t as Map).containsKey('group'), isFalse);
        expect(t.containsKey('group_id'), isFalse);
        expect(t.containsKey('collapsed'), isFalse);
      }
      final doc = DawDoc.fromJson(old);
      expect(doc.hasGroups, isFalse);
      expect(doc.tracks.every((t) => !t.isGroup && t.groupId == null && !t.collapsed), isTrue);
      expect(jsonEncode(doc.toJson()), jsonEncode(old));
    });

    test('pasta e filhas vão e voltam pelo JSON', () {
      final c = newController();
      final f = c.groupTracks(['a1', 'a2'], name: 'Vozes').folder!;
      c.setGroupCollapsed(f.id, true);
      final j = jsonDecode(snap(c)) as Map<String, dynamic>;
      final folder = (j['tracks'] as List).firstWhere((t) => t['id'] == f.id);
      expect(folder['group'], true);
      expect(folder['collapsed'], true);
      expect(folder['kind'], 'bus');
      final child = (j['tracks'] as List).firstWhere((t) => t['id'] == 'a1');
      expect(child['group_id'], f.id);
      expect(child['output'], f.id);
      final again = DawDoc.fromJson(j);
      expect(jsonEncode(again.toJson()), jsonEncode(j));
      expect(again.tracks.first.isGroup, isTrue);
      expect(again.tracks.first.collapsed, isTrue);
    });

    test('filha órfã ou barramento marcado como filho é solto ao abrir; "group" fora de barramento é ignorado', () {
      final j = jsonDecode(snap(newController())) as Map<String, dynamic>;
      final tracks = j['tracks'] as List;
      tracks[0]['group_id'] = 'nao-existe';
      tracks[1]['group'] = true; // faixa de áudio: não vira pasta
      tracks[5]['group_id'] = 'a1'; // barramento nunca é filho
      final doc = DawDoc.fromJson(j);
      expect(doc.tracks[0].groupId, isNull);
      expect(doc.tracks[1].isGroup, isFalse);
      expect(doc.tracks[5].groupId, isNull);
    });
  });

  group('agrupar', () {
    test('cria o barramento no lugar da primeira, filhas abaixo, saídas apontando para ele; o motor recebe o roteamento', () {
      final c = newController();
      final before = snap(c);
      final r = c.groupTracks(['a1', 'a2'], name: '  Vozes ');
      expect(r.error, isNull);
      final f = r.folder!;
      expect(names(c), ['Vozes', 'Áudio 1', 'Áudio 2', 'Synth', 'Bateria', 'Sampler', 'Reverb']);
      expect(f.kind, TrackKind.bus);
      expect(f.isGroup, isTrue);
      expect(f.output, isNull);
      expect(track(c, 'a1').groupId, f.id);
      expect(track(c, 'a1').output, f.id);
      expect(track(c, 'a2').output, f.id);
      expect(track(c, 's').output, isNull);
      expect(c.selectedTrack, 0);
      // no motor: a pasta é o barramento 0 (tipo 4) e as filhas (1 e 2) saem nele
      expect(sent('track_kind').any((k) => k[1] == 0 && k[2] == 4), isTrue, reason: '${sent('track_kind')}');
      final out = lastOutputs();
      expect(out[0], -1);
      expect(out[1], 0);
      expect(out[2], 0);
      expect(out[3], -1);
      expect(out[6], -1);
      // uma edição só: um desfazer volta tudo, refazer aplica de novo
      c.undo();
      expect(snap(c), before);
      expect(lastOutputs()[1], -1);
      c.redo();
      expect(names(c).first, 'Vozes');
      expect(lastOutputs()[1], 0);
    });

    test('nome vazio vira "Pasta N" sem repetir', () {
      final c = newController();
      expect(c.groupTracks(['a1']).folder!.name, 'Pasta 1');
      expect(c.groupTracks(['s']).folder!.name, 'Pasta 2');
    });

    test('faixas não contíguas ficam contíguas: as do meio descem para depois do bloco', () {
      final c = newController();
      c.groupTracks(['a1', 's', 'p'], name: 'G');
      expect(names(c), ['G', 'Áudio 1', 'Synth', 'Sampler', 'Áudio 2', 'Bateria', 'Reverb']);
      expect(c.doc.membersOf(0), [1, 2, 3]);
      // a ordem escolhida não importa: vale a da lista
      final d = newController();
      d.groupTracks(['p', 'a2'], name: 'X');
      expect(names(d), ['Áudio 1', 'X', 'Áudio 2', 'Sampler', 'Synth', 'Bateria', 'Reverb']);
      expect(d.doc.folderOf(2), 1);
    });

    test('a pasta nasce onde está a primeira faixa escolhida, mesmo no meio da lista', () {
      final c = newController();
      c.groupTracks(['d', 's'], name: 'M');
      expect(names(c), ['Áudio 1', 'Áudio 2', 'M', 'Synth', 'Bateria', 'Sampler', 'Reverb']);
    });

    test('uma faixa só vale; agrupar tudo também (o retorno de fora fica onde está)', () {
      final c = newController();
      expect(c.groupTracks(['s']).folder, isNotNull);
      expect(c.doc.groupSize(c.doc.tracks.indexWhere((t) => t.isGroup)), 1);
      final d = newController();
      final all = ['a1', 'a2', 's', 'd', 'p'];
      d.groupTracks(all, name: 'Tudo');
      expect(names(d), ['Tudo', 'Áudio 1', 'Áudio 2', 'Synth', 'Bateria', 'Sampler', 'Reverb']);
      expect(d.doc.groupSize(0), 5);
      expect(lastOutputs()[5], 0);
      expect(d.doc.tracks.last.groupId, isNull);
    });

    test('recusas: nada, barramento, pasta dentro de pasta, faixa que já está em pasta, id que não existe; o documento não muda', () {
      final c = newController();
      final f = c.groupTracks(['a1', 'a2'], name: 'G').folder!;
      final before = snap(c);
      expect(c.groupTracks([]).error, contains('ao menos uma faixa'));
      expect(c.groupTracks(['r']).error, contains('é um barramento'));
      expect(c.groupTracks([f.id]).error, contains('pasta dentro de pasta'));
      expect(c.groupTracks(['s', 'a1']).error, contains('já está na pasta "G"'));
      expect(c.groupTracks(['s', 'zzz']).error, contains('não existe'));
      expect(snap(c), before);
      c.undo();
      expect(names(c), ['Áudio 1', 'Áudio 2', 'Synth', 'Bateria', 'Sampler', 'Reverb'], reason: 'as recusas não entraram no desfazer');
    });

    test('envios das filhas ficam como estavam; a pasta pode ter efeito e sair para outro barramento', () {
      final c = newController();
      c.setSend(0, 'r', level: 0.7);
      final f = c.groupTracks(['a1', 'a2'], name: 'G').folder!;
      expect(track(c, 'a1').sends.single.target, 'r');
      expect(track(c, 'a1').sends.single.level, 0.7);
      c.addEffect(0, EffectKind.compressor);
      expect(f.effects, hasLength(1));
      // a pasta (índice 0) manda para o retorno (índice 6, depois dela)
      expect(c.setOutput(0, 'r'), isTrue);
      expect(lastOutputs()[0], 6);
      expect(lastOutputs()[1], 0, reason: 'a filha continua saindo na pasta');
    });
  });

  group('desagrupar', () {
    test('devolve as saídas ao master e apaga o barramento vazio; desfazer restaura tudo', () {
      final c = newController();
      final f = c.groupTracks(['a1', 's'], name: 'G').folder!;
      final grouped = snap(c);
      expect(c.ungroup(f.id), UngroupResult.removed);
      // as filhas ficam onde o agrupar as pôs (contíguas); só a pasta some
      expect(names(c), ['Áudio 1', 'Synth', 'Áudio 2', 'Bateria', 'Sampler', 'Reverb']);
      expect(c.doc.hasGroups, isFalse);
      expect(track(c, 'a1').groupId, isNull);
      expect(track(c, 'a1').output, isNull);
      expect(lastOutputs()[0], -1);
      expect(lastOutputs()[1], -1);
      c.undo();
      expect(snap(c), grouped);
      expect(lastOutputs()[1], 0);
    });

    test('com efeito, o barramento fica como barramento comum (nada montado se perde)', () {
      final c = newController();
      final f = c.groupTracks(['a1', 'a2'], name: 'G').folder!;
      c.addEffect(0, EffectKind.compressor);
      expect(c.ungroup(f.id), UngroupResult.keptAsBus);
      expect(names(c).first, 'G');
      expect(f.isGroup, isFalse);
      expect(f.kind, TrackKind.bus);
      expect(f.effects, hasLength(1));
      expect(track(c, 'a1').output, f.id, reason: 'as filhas seguem no barramento: o efeito da pasta não fica sem entrada');
      expect(c.doc.hasGroups, isFalse);
    });

    test('quem recebe envio de outra faixa também mantém o barramento', () {
      final c = newController();
      final f = c.groupTracks(['a1', 'a2'], name: 'G').folder!;
      c.setSend(c.doc.tracks.indexWhere((t) => t.id == 's'), f.id);
      expect(c.ungroup(f.id), UngroupResult.keptAsBus);
      expect(track(c, 's').sends.single.target, f.id);
    });

    test('pasta que não existe não faz nada; apagar a pasta solta as filhas', () {
      final c = newController();
      expect(c.ungroup('nada'), UngroupResult.none);
      final f = c.groupTracks(['a1', 'a2'], name: 'G').folder!;
      c.removeTrack(0);
      expect(c.doc.hasGroups, isFalse);
      expect(track(c, 'a1').groupId, isNull);
      expect(track(c, 'a1').output, isNull);
      expect(f.id, isNotEmpty);
    });
  });

  group('recolher', () {
    test('estado no documento; esconde as filhas; desfazer de outra edição não o desfaz', () {
      final c = newController();
      final f = c.groupTracks(['a1', 'a2'], name: 'G').folder!;
      expect(c.doc.hiddenByGroup(1), isFalse);
      c.setGroupCollapsed(f.id, true);
      expect(c.doc.hiddenByGroup(1), isTrue);
      expect(c.doc.hiddenByGroup(2), isTrue);
      expect(c.doc.hiddenByGroup(3), isFalse);
      expect(jsonDecode(snap(c))['tracks'][0]['collapsed'], true);
      // uma edição qualquer e o desfazer: a pasta continua recolhida
      c.edit((d) => d.tracks[3].gain = 0.5);
      c.undo();
      expect(f.collapsed || c.doc.tracks[0].collapsed, isTrue);
      // desfazer o agrupar com a pasta recolhida some com a pasta sem erro
      c.undo();
      expect(c.doc.hasGroups, isFalse);
    });

    test('recolher com a filha selecionada passa a seleção para a pasta', () {
      final c = newController();
      final f = c.groupTracks(['a1', 'a2'], name: 'G').folder!;
      c.selectTrack(2);
      c.setGroupCollapsed(f.id, true);
      expect(c.selectedTrack, 0);
    });

    test('recolher todas e expandir todas', () {
      final c = newController();
      c.groupTracks(['a1'], name: 'G1');
      c.groupTracks(['s'], name: 'G2');
      c.setAllGroupsCollapsed(true);
      expect(c.doc.tracks.where((t) => t.isGroup).every((t) => t.collapsed), isTrue);
      c.setAllGroupsCollapsed(false);
      expect(c.doc.tracks.where((t) => t.isGroup).any((t) => t.collapsed), isFalse);
    });
  });

  group('mudo e solo da pasta', () {
    test('o mudo e o solo do barramento vão ao motor no índice da pasta', () {
      final c = newController();
      final f = c.groupTracks(['a1', 'a2'], name: 'G').folder!;
      engine.log = [];
      c.edit((_) => f.mute = true);
      expect(sent('track').any((t) => t[1] == 0 && t[4] == true), isTrue, reason: '${sent('track')}');
      engine.log = [];
      c.edit((_) => f.solo = true);
      expect(sent('track').any((t) => t[1] == 0 && t[5] == true), isTrue);
    });
  });

  group('mover', () {
    test('largar uma faixa dentro da pasta a coloca nela, com a saída; o aviso de rota diz o que muda', () {
      final c = newController();
      c.groupTracks(['a1', 'a2'], name: 'G'); // G a1 a2 s d p r
      // a saída da Bateria já ia para um barramento (o Reverb): entrar na pasta a troca
      expect(c.setOutput(4, 'r'), isTrue);
      final warn = c.routesBrokenByMove(4, 2);
      expect(warn, ['a saída de "Bateria" para "Reverb" (passa a ir para a pasta "G")']);
      c.moveTrack(4, 2); // entre a1 e a2
      expect(names(c), ['G', 'Áudio 1', 'Bateria', 'Áudio 2', 'Synth', 'Sampler', 'Reverb']);
      expect(track(c, 'd').groupId, track(c, 'a1').groupId);
      expect(track(c, 'd').output, c.doc.tracks[0].id);
      expect(c.doc.membersOf(0), [1, 2, 3]);
      expect(lastOutputs()[2], 0);
      c.undo();
      expect(track(c, 'd').groupId, isNull);
      expect(track(c, 'd').output, 'r');
      expect(names(c), ['G', 'Áudio 1', 'Áudio 2', 'Synth', 'Bateria', 'Sampler', 'Reverb']);
    });

    test('sem saída anterior não há aviso ao entrar; sair da pasta avisa que a saída volta ao master', () {
      final c = newController();
      c.groupTracks(['a1', 'a2'], name: 'G');
      expect(c.routesBrokenByMove(3, 1), isEmpty, reason: 'Synth entrando logo abaixo do cabeçalho');
      c.moveTrack(3, 1);
      expect(track(c, 's').groupId, c.doc.tracks[0].id);
      expect(c.routesBrokenByMove(1, 5), ['a saída de "Synth" para a pasta "G" (volta ao master)']);
      c.moveTrack(1, 5);
      expect(track(c, 's').groupId, isNull);
      expect(track(c, 's').output, isNull);
      expect(c.doc.membersOf(0), [1, 2]);
      expect(lastOutputs()[c.doc.tracks.indexWhere((t) => t.id == 's')], -1);
    });

    test('logo depois da última filha já é fora; entre as filhas é dentro', () {
      final c = newController();
      c.groupTracks(['a1', 'a2'], name: 'G'); // G a1 a2 s d p r
      c.moveTrack(3, 3); // no lugar: nada
      expect(names(c), ['G', 'Áudio 1', 'Áudio 2', 'Synth', 'Bateria', 'Sampler', 'Reverb']);
      c.moveTrack(2, 3); // a2 desce uma: passa do bloco, sai
      expect(track(c, 'a2').groupId, isNull);
      expect(names(c), ['G', 'Áudio 1', 'Synth', 'Áudio 2', 'Bateria', 'Sampler', 'Reverb']);
      expect(track(c, 's').groupId, isNull, reason: 'Synth estava fora e continua fora');
      expect(c.doc.membersOf(0), [1]);
    });

    test('mover a pasta leva as filhas junto; cair dentro de outra pasta pula para fora dela', () {
      final c = newController();
      c.groupTracks(['a1', 'a2'], name: 'G1'); // G1 a1 a2 s d p r
      c.groupTracks(['d', 'p'], name: 'G2'); // G1 a1 a2 s G2 d p r
      expect(names(c), ['G1', 'Áudio 1', 'Áudio 2', 'Synth', 'G2', 'Bateria', 'Sampler', 'Reverb']);
      c.moveTrack(4, 0); // G2 (bloco de 3) para o topo
      expect(names(c), ['G2', 'Bateria', 'Sampler', 'G1', 'Áudio 1', 'Áudio 2', 'Synth', 'Reverb']);
      expect(c.doc.membersOf(0), [1, 2]);
      expect(c.doc.membersOf(3), [4, 5]);
      // G2 para o meio de G1 (entre a1 e a2): pula para depois do bloco de G1
      c.moveTrack(0, 2); // no rest [G1 a1 a2 Synth Reverb] seria entre a1 e a2
      expect(names(c), ['G1', 'Áudio 1', 'Áudio 2', 'G2', 'Bateria', 'Sampler', 'Synth', 'Reverb']);
      expect(c.doc.membersOf(0), [1, 2]);
      expect(c.doc.membersOf(3), [4, 5]);
    });

    test('pasta recolhida não engole a faixa: "mover para baixo" pula o bloco inteiro', () {
      final c = newController();
      final f = c.groupTracks(['s', 'd'], name: 'G').folder!; // a1 a2 G s d p r
      c.setGroupCollapsed(f.id, true);
      c.moveTrack(1, 2); // a2 desce uma: cairia entre G e s
      expect(names(c), ['Áudio 1', 'G', 'Synth', 'Bateria', 'Áudio 2', 'Sampler', 'Reverb']);
      expect(track(c, 'a2').groupId, isNull);
      c.moveTrack(4, 3); // e volta subindo: pula para antes da pasta
      expect(names(c), ['Áudio 1', 'Áudio 2', 'G', 'Synth', 'Bateria', 'Sampler', 'Reverb']);
      expect(track(c, 'a2').groupId, isNull);
    });

    test('barramento de retorno não entra em pasta ao ser largado nela', () {
      final c = newController();
      c.groupTracks(['a1', 'a2'], name: 'G'); // G a1 a2 s d p r
      c.moveTrack(6, 2); // subindo: pula para antes da pasta
      expect(track(c, 'r').groupId, isNull);
      expect(names(c), ['Reverb', 'G', 'Áudio 1', 'Áudio 2', 'Synth', 'Bateria', 'Sampler']);
      expect(c.doc.membersOf(1), [2, 3]);
      c.moveTrack(0, 3); // descendo: pula para depois do bloco
      expect(names(c), ['G', 'Áudio 1', 'Áudio 2', 'Reverb', 'Synth', 'Bateria', 'Sampler']);
      expect(track(c, 'r').groupId, isNull);
    });

    test('joinGroup e leaveGroup (o menu): também com a pasta recolhida e com uma filha só', () {
      final c = newController();
      final f = c.groupTracks(['a1'], name: 'G').folder!; // G a1 a2 s d p r
      c.setGroupCollapsed(f.id, true);
      expect(c.joinGroup('p', f.id), isTrue);
      expect(names(c), ['G', 'Áudio 1', 'Sampler', 'Áudio 2', 'Synth', 'Bateria', 'Reverb']);
      expect(track(c, 'p').output, f.id);
      expect(c.joinGroup('p', f.id), isFalse, reason: 'já está nela');
      expect(c.joinGroup('r', f.id), isFalse, reason: 'barramento não entra');
      expect(c.leaveGroup('a1'), isTrue);
      expect(c.leaveGroup('a1'), isFalse);
      expect(names(c), ['G', 'Sampler', 'Áudio 1', 'Áudio 2', 'Synth', 'Bateria', 'Reverb']);
      expect(track(c, 'a1').output, isNull);
      expect(c.leaveGroup('p'), isTrue, reason: 'a única filha também sai');
      expect(c.doc.groupSize(0), 0);
      // mover uma faixa de uma pasta para outra
      final g = c.groupTracks(['s'], name: 'H').folder!;
      c.joinGroup('a1', f.id);
      c.joinGroup('a1', g.id);
      expect(track(c, 'a1').groupId, g.id);
      expect(track(c, 'a1').output, g.id);
      expect(c.doc.groupSize(c.doc.tracks.indexOf(f)), 0);
    });

    test('sidechain acompanha a faixa quando agrupar e mover reordenam a lista', () {
      final c = newController();
      c.addEffect(3, EffectKind.compressor); // na Bateria (índice 3)
      final comp = track(c, 'd').effects.first;
      comp.params[10] = 1; // sidechain: Áudio 2
      c.groupTracks(['a1', 'a2'], name: 'G'); // Áudio 2 vai para o índice 2
      expect(comp.params[10], 2);
      c.moveTrack(2, 0); // a pasta é o índice 0 e a2 o 2; a2 sobe para o topo (sai da pasta)
      final now = c.doc.tracks.indexWhere((t) => t.id == 'a2');
      expect(comp.params[10], now);
    });
  });

  group('apagar e duplicar', () {
    test('apagar uma filha tira só ela; a pasta continua (mesmo vazia)', () {
      final c = newController();
      c.groupTracks(['a1', 'a2'], name: 'G');
      c.removeTrack(1);
      expect(names(c).take(3), ['G', 'Áudio 2', 'Synth']);
      expect(c.doc.membersOf(0), [1]);
      c.removeTrack(1);
      expect(c.doc.groupSize(0), 0);
      expect(c.doc.tracks.first.isGroup, isTrue);
    });

    test('duplicar uma filha põe a cópia na mesma pasta, logo abaixo, com a mesma saída; pasta não duplica', () {
      final c = newController();
      final f = c.groupTracks(['a1', 'a2'], name: 'G').folder!;
      c.duplicateTrack(2); // Áudio 2, a última filha
      expect(names(c).take(5), ['G', 'Áudio 1', 'Áudio 2', 'Áudio 2 (2)', 'Synth']);
      expect(c.doc.tracks[3].groupId, f.id);
      expect(c.doc.tracks[3].output, f.id);
      expect(c.doc.membersOf(0), [1, 2, 3]);
      final n = c.doc.tracks.length;
      c.duplicateTrack(0);
      expect(c.doc.tracks.length, n, reason: 'duplicar a pasta não faz nada');
    });
  });

  group('interface', () {
    testWidgets('menu da faixa: Agrupar em pasta… abre o diálogo com a faixa marcada e cria a pasta', (t) async {
      final c = studio();
      await mount(t, c, const Size(1400, 900));
      await t.tap(find.byTooltip('Opções da faixa').first);
      await t.pumpAndSettle();
      await t.tap(find.text('Agrupar em pasta…'));
      await t.pumpAndSettle();
      expect(find.text('Agrupar em pasta'), findsOneWidget);
      // só a Áudio 1 marcada; marca também a Bateria (não contígua)
      await t.tap(find.byKey(const ValueKey('group-pick:d')));
      await t.pump();
      await t.enterText(find.byKey(const ValueKey('group-name')), 'Base');
      await t.tap(find.byKey(const ValueKey('group-confirm')));
      await t.pumpAndSettle();
      expect(c.doc.tracks.map((x) => x.name).toList(), ['Base', 'Áudio 1', 'Bateria 1', 'Sintetizador 1', 'Sampler 1']);
      final folder = c.doc.tracks.first;
      expect(find.byKey(ValueKey('group-header:${folder.id}')), findsOneWidget);
      // recolher pela seta: as filhas somem, a miniatura aparece; expandir traz de volta
      expect(find.byKey(const ValueKey('t:a')), findsOneWidget);
      await t.tap(find.byKey(ValueKey('group-toggle:${folder.id}')));
      await t.pump();
      expect(find.byKey(const ValueKey('t:a')), findsNothing);
      expect(find.byKey(const ValueKey('t:d')), findsNothing);
      expect(find.byKey(const ValueKey('t:s')), findsOneWidget);
      expect(find.byKey(ValueKey('group-mini:${folder.id}')), findsOneWidget);
      expect(c.doc.tracks.first.collapsed, isTrue);
      await t.tap(find.byKey(ValueKey('group-toggle:${folder.id}')));
      await t.pump();
      expect(find.byKey(const ValueKey('t:a')), findsOneWidget);
      expect(find.byKey(ValueKey('group-mini:${folder.id}')), findsNothing);
      await flushSave(t);
    });

    testWidgets('menu de uma pasta ou de um barramento avisa que não dá para agrupar', (t) async {
      final c = studio();
      c.addBusTrack();
      await mount(t, c, const Size(1400, 900));
      final bus = c.doc.tracks.length - 1;
      c.selectTrack(bus);
      await t.pump();
      // menu da última faixa (o barramento)
      await t.tap(find.byTooltip('Opções da faixa').last);
      await t.pumpAndSettle();
      await t.tap(find.text('Agrupar em pasta…'));
      await t.pumpAndSettle();
      expect(find.textContaining('é um barramento'), findsOneWidget);
      await t.tap(find.text('Entendi'));
      await t.pumpAndSettle();
      expect(c.doc.hasGroups, isFalse);
      await flushSave(t);
    });

    testWidgets('a pasta mostra M/S que agem no barramento e o Desagrupar pede confirmação', (t) async {
      final c = studio();
      final f = c.groupTracks(['a', 's'], name: 'G').folder!;
      await mount(t, c, const Size(1400, 900));
      final header = find.byKey(ValueKey('group-header:${f.id}'));
      await t.tap(find.descendant(of: header, matching: find.text('M')));
      await t.pump();
      expect(f.mute, isTrue);
      expect(track(c, 'a').mute, isFalse, reason: 'o mudo é o do barramento, as filhas não mudam');
      await t.tap(find.descendant(of: header, matching: find.text('S')));
      await t.pump();
      expect(f.solo, isTrue);
      await t.tap(find.byKey(const ValueKey('group-menu')));
      await t.pumpAndSettle();
      await t.tap(find.text('Desagrupar…'));
      await t.pumpAndSettle();
      expect(find.textContaining('Desagrupar "G"?'), findsOneWidget);
      await t.tap(find.text('Cancelar'));
      await t.pumpAndSettle();
      expect(c.doc.hasGroups, isTrue, reason: 'cancelar não desagrupa');
      await t.tap(find.byKey(const ValueKey('group-menu')));
      await t.pumpAndSettle();
      await t.tap(find.text('Desagrupar…'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, 'Desagrupar'));
      await t.pumpAndSettle();
      expect(c.doc.hasGroups, isFalse);
      expect(c.doc.tracks.length, 4);
      await flushSave(t);
    });

    testWidgets('mover entre pastas pelo diálogo de aviso: cancelar deixa tudo, "Mover mesmo assim" move', (t) async {
      final c = newController();
      c.groupTracks(['a1', 'a2'], name: 'G');
      c.setOutput(4, 'r'); // Bateria → Reverb
      late BuildContext ctx;
      await t.pumpWidget(
        MaterialApp(
          theme: buildTheme(),
          home: Scaffold(
            body: Builder(
              builder: (context) {
                ctx = context;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      final before = snap(c);
      unawaited(moveTrackAsking(ctx, c, 4, 2));
      await t.pumpAndSettle();
      expect(find.text('Mover a faixa?'), findsOneWidget);
      expect(find.textContaining('passa a ir para a pasta "G"'), findsOneWidget);
      await t.tap(find.text('Cancelar'));
      await t.pumpAndSettle();
      expect(snap(c), before);
      unawaited(moveTrackAsking(ctx, c, 4, 2));
      await t.pumpAndSettle();
      await t.tap(find.text('Mover mesmo assim'));
      await t.pumpAndSettle();
      expect(track(c, 'd').groupId, c.doc.tracks[0].id);
      c.undo();
      expect(snap(c), before);
      await flushSave(t);
    });

    testWidgets('mixer: barra "Grupo" no canal da pasta, marca nas filhas e nenhuma sem pastas', (t) async {
      final c = studio();
      await mount(t, c, const Size(1400, 900));
      c.setDock(Dock.mixer);
      await t.pump();
      expect(find.text('Grupo'), findsNothing);
      final f = c.groupTracks(['a', 's'], name: 'G').folder!;
      await t.pump();
      expect(find.byKey(ValueKey('group-bar:${f.id}')), findsOneWidget);
      expect(find.text('Grupo'), findsOneWidget);
      expect(find.byKey(const ValueKey('group-member:a')), findsOneWidget);
      expect(find.byKey(const ValueKey('group-member:s')), findsOneWidget);
      expect(find.byKey(const ValueKey('group-member:d')), findsNothing, reason: 'fora da pasta');
      // recolher no arranjo não tira as filhas do mixer
      c.setGroupCollapsed(f.id, true);
      await t.pump();
      expect(find.byKey(const ValueKey('group-member:a')), findsOneWidget);
      // o canal da pasta e as filhas seguem na ordem: pasta, a, s
      final x = [
        for (final k in ['group-bar:${f.id}', 'group-member:a', 'group-member:s']) t.getTopLeft(find.byKey(ValueKey(k))).dx,
      ];
      expect(x[0] < x[1] && x[1] < x[2], isTrue, reason: '$x');
      c.undo();
      await t.pump();
      expect(find.text('Grupo'), findsNothing);
      await flushSave(t);
    });

    testWidgets('celular: pasta com filhas recolhida e expandida monta sem erro', (t) async {
      final c = studio();
      c.groupTracks(['a', 's', 'd'], name: 'Grupo com nome bem comprido para estourar a linha');
      await mount(t, c, const Size(400, 820));
      expect(t.takeException(), isNull);
      c.setAllGroupsCollapsed(true);
      await t.pump();
      c.setDock(Dock.mixer);
      await t.pump();
      expect(t.takeException(), isNull);
      await flushSave(t);
    });
  });
}
