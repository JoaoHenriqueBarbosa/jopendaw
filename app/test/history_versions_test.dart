// Fase 18 (C): histórico de desfazer com nomes e versões nomeadas do projeto (instantâneos locais).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jopendaw_app/daw/controller.dart';
import 'package:jopendaw_app/daw/effects.dart';
import 'package:jopendaw_app/daw/history.dart';
import 'package:jopendaw_app/daw/history_ui.dart';
import 'package:jopendaw_app/daw/instruments.dart';
import 'package:jopendaw_app/daw/keymap.dart';
import 'package:jopendaw_app/daw/local_purge.dart';
import 'package:jopendaw_app/daw/model.dart';
import 'package:jopendaw_app/daw/snapshots.dart';
import 'package:jopendaw_app/daw/snapshots_ui.dart';
import 'package:jopendaw_app/daw/tempo_map.dart';
import 'package:jopendaw_app/models/project.dart';

import 'fake_engine.dart';

Project _project(String id, String name) => Project.fromJson({
  'id': id,
  'name': name,
  'bpm': 120,
  'beats_per_bar': 4,
  'beat_unit': 4,
  'sample_rate': 48000,
  'created_at': '2026-01-01T00:00:00Z',
  'updated_at': '2026-01-01T00:00:00Z',
});

/// Toca num widget que pode estar fora da janela de rolagem do diálogo (a tela é estreita): rola até ele antes.
Future<void> tapV(WidgetTester t, Finder f) async {
  await t.scrollUntilVisible(f, 80, scrollable: find.byType(Scrollable).hitTestable().first, maxScrolls: 200);
  await t.pumpAndSettle();
  await t.tap(f);
}

void main() {
  late FakeEngine e;
  late MemoryStore store;
  late DawController c;
  var now = DateTime.utc(2026, 9, 30, 10);

  setUp(() {
    e = FakeEngine();
    store = MemoryStore();
    now = DateTime.utc(2026, 9, 30, 10);
    c = fakeController(e, store: store)..clock = () => now;
  });

  tearDown(() => c.dispose());

  group('histórico com nomes', () {
    test('rótulos, hora e ordem (mais recente primeiro, início por último, passo atual marcado)', () {
      c.addTrack();
      now = now.add(const Duration(minutes: 5));
      c.addMarker(beat: 2);
      now = now.add(const Duration(minutes: 5));
      c.edit((d) => d.masterGain = 0.5); // sem rótulo
      final rows = c.historyRows;
      expect(rows.map((r) => r.title), ['Edição', 'Adicionar marcador', 'Adicionar faixa', 'Início do histórico']);
      expect(rows.map((r) => r.position), [3, 2, 1, 0]);
      expect(rows.map((r) => r.current), [true, false, false, false]);
      expect(rows.first.labeled, isFalse);
      expect(stepText(rows.first), 'Edição (${formatClock24(now)})');
      expect(stepText(rows[1]), 'Adicionar marcador');
      expect(rows.last.isStart, isTrue);
      expect(c.historyCount, 3);
      expect(c.nextUndo!.title, 'Edição');
      expect(c.nextUndo!.time, now);
      expect(c.historyRows[2].time, DateTime.utc(2026, 9, 30, 10));
    });

    test('desfazer e refazer guardam o rótulo dos dois lados; o passo refazível aparece como futuro', () {
      c.addTrack();
      c.removeTrack(1);
      expect(c.nextUndo!.title, 'Apagar faixa');
      c.undo();
      expect(c.nextRedo!.title, 'Apagar faixa');
      expect(c.nextUndo!.title, 'Adicionar faixa');
      final rows = c.historyRows;
      expect(rows.map((r) => r.title), ['Apagar faixa', 'Adicionar faixa', 'Início do histórico']);
      expect(rows.map((r) => r.future), [true, false, false]);
      expect(rows.map((r) => r.current), [false, true, false]);
      expect(undoTooltipText(c), contains('Desfazer: Adicionar faixa'));
      expect(redoTooltipText(c), contains('Refazer: Apagar faixa'));
      c.redo();
      expect(c.nextUndo!.title, 'Apagar faixa');
      expect(c.canRedo, isFalse);
    });

    test('tooltips sem passo: só a palavra', () {
      expect(undoTooltipText(c), isNot(contains(':')));
      expect(redoTooltipText(c), isNot(contains(':')));
    });

    test('ir até um passo: desfaz e refaz vários numa operação só', () {
      c.addTrack(); // 1
      c.addTrack(); // 2
      c.addTrack(); // 3
      c.addMarker(beat: 1); // 4
      expect(c.doc.tracks.length, 4);
      var notified = 0;
      c.addListener(() => notified++);
      c.jumpToHistory(1);
      expect(c.doc.tracks.length, 2);
      expect(c.doc.markers, isEmpty);
      expect(notified, 1, reason: 'uma notificação só, não uma por passo');
      expect(c.historyCount, 4);
      expect(c.historyRows.firstWhere((r) => r.current).position, 1);
      c.jumpToHistory(4);
      expect(c.doc.tracks.length, 4);
      expect(c.doc.markers.length, 1);
      c.jumpToHistory(0);
      expect(c.doc.tracks.length, 1);
      expect(c.canUndo, isFalse);
      expect(c.canRedo, isTrue);
      c.jumpToHistory(99); // acima do máximo: vai até o fim
      expect(c.doc.tracks.length, 4);
      c.jumpToHistory(-3);
      expect(c.doc.tracks.length, 1);
    });

    test('uma edição nova depois de voltar apaga os passos refazíveis', () {
      c.addTrack();
      c.addTrack();
      c.jumpToHistory(1);
      c.addMarker(beat: 3);
      expect(c.canRedo, isFalse);
      expect(c.historyRows.map((r) => r.title), ['Adicionar marcador', 'Adicionar faixa', 'Início do histórico']);
    });

    test('limpar o histórico mantém o documento', () {
      c.addTrack();
      c.addTrack();
      c.undo();
      c.clearHistory();
      expect(c.historyCount, 0);
      expect(c.canUndo, isFalse);
      expect(c.canRedo, isFalse);
      expect(c.doc.tracks.length, 2);
      expect(c.historyRows.single.isStart, isTrue);
      expect(c.historyRows.single.current, isTrue);
    });

    test('o limite da pilha (200) não muda: os mais antigos saem primeiro', () {
      expect(historyLimit, 200);
      for (var i = 0; i < 205; i++) {
        c.edit((d) => d.masterGain = 0.5 + i / 1000, label: 'Passo $i');
      }
      expect(c.historyCount, 200);
      expect(c.historyRows.first.title, 'Passo 204');
      expect(c.historyRows[199].title, 'Passo 5');
    });

    test('passo sem desfazer (arraste, undoable false) não entra; o checkpoint de arraste leva o rótulo', () {
      c.checkpoint('Mover clipe');
      c.mutate((d) => d.masterGain = 0.7);
      c.mutate((d) => d.masterGain = 0.8);
      c.edit((d) => d.masterGain = 0.9, undoable: false);
      expect(c.historyCount, 1);
      expect(c.nextUndo!.title, 'Mover clipe');
    });

    test('rótulo em branco vira Edição', () {
      c.edit((d) => d.masterGain = 0.6, label: '   ');
      expect(c.nextUndo!.title, 'Edição');
      expect(c.nextUndo!.labeled, isFalse);
    });

    test('rótulos dos caminhos principais', () {
      c.addInstrumentTrack(TrackKind.synth);
      expect(c.nextUndo!.title, 'Adicionar faixa de instrumento');
      c.createMidiClip(1, 0);
      expect(c.nextUndo!.title, 'Criar clipe MIDI');
      c.setTempoMap([TempoPoint(0, 130)]);
      expect(c.nextUndo!.title, 'Mudar andamento');
      c.moveTrack(1, 0);
      expect(c.nextUndo!.title, 'Mover faixa');
      c.removeTrack(0);
      expect(c.nextUndo!.title, 'Apagar faixa');
    });

    test('gravar automação vira um passo "Gravar automação"', () {
      c.autoCommitUndo(jsonEncode(c.doc.toJson()));
      expect(c.nextUndo!.title, 'Gravar automação');
    });

    test('o atalho "Abrir o histórico" está no catálogo', () {
      final a = keyActionById('history.open');
      expect(a, isNotNull);
      expect(a!.label, 'Abrir o histórico');
      expect(a.defaults, isNotEmpty);
    });
  });

  group('versões (instantâneos)', () {
    Future<Snapshot> save(String name, {String note = '', bool auto = false}) async {
      final s = await c.versions.save(name: name, note: note, auto: auto);
      expect(s, isNotNull, reason: name);
      return s!;
    }

    void change() {
      c.addMarker(beat: (c.doc.markers.length + 1).toDouble());
    }

    test('salvar, listar (mais nova primeiro), carregar e apagar; as chaves são snapshots:<projeto>:<id>', () async {
      c.addInstrumentTrack(TrackKind.synth);
      c.createMidiClip(1, 0);
      final a = await save('Primeira', note: 'com o baixo');
      now = now.add(const Duration(minutes: 1));
      change();
      final b = await save('Segunda');
      expect(store.data.keys.where((k) => k.startsWith('snapshots:p:')).length, 2);
      expect(store.data.containsKey('snapshots:p:${a.id}'), isTrue);
      final list = await c.versions.list();
      expect(list.items.map((s) => s.name), ['Segunda', 'Primeira']);
      expect(list.items.last.note, 'com o baixo');
      expect(list.items.last.tracks, 2);
      expect(list.items.last.clips, 1);
      expect(list.items.last.auto, isFalse);
      expect(list.corruptKeys, isEmpty);
      expect(list.totalBytes, greaterThan(100));
      final doc = await c.versions.load(a.id);
      expect(doc!['markers'], isEmpty);
      expect((await c.versions.load(b.id))!['markers'], hasLength(1));
      await c.versions.delete(a.id);
      expect((await c.versions.list()).items.map((s) => s.name), ['Segunda']);
      expect(await c.versions.load(a.id), isNull);
    });

    test('o instantâneo não leva áudio: só o documento (JSON)', () async {
      final s = await save('X');
      final raw = jsonDecode(store.data['snapshots:p:${s.id}']! as String) as Map;
      expect(raw['format'], 'jopendaw-version');
      expect(raw['version'], 1);
      expect((raw['doc'] as Map).containsKey('tracks'), isTrue);
      expect(store.data.keys.any((k) => k.startsWith('sample:')), isFalse);
    });

    test('nunca guarda dois instantâneos idênticos seguidos', () async {
      await save('A');
      expect(await c.versions.save(name: 'B'), isNull);
      expect((await c.versions.list()).items, hasLength(1));
      change();
      await save('C');
      expect(await c.versions.save(name: 'D'), isNull);
      expect((await c.versions.list()).items, hasLength(2));
      // depois de voltar ao estado da primeira, o "seguido" é a mais nova: guarda
      c.jumpToHistory(0);
      await save('E');
      expect((await c.versions.list()).items, hasLength(3));
    });

    test('igual à automática mais nova: salvar à mão a promove a manual com o nome pedido', () async {
      final auto = await save('Versão automática', auto: true);
      final manual = await c.versions.save(name: 'Meu marco', note: 'n');
      expect(manual, isNotNull);
      expect(manual!.id, auto.id);
      final list = (await c.versions.list()).items;
      expect(list, hasLength(1));
      expect(list.single.name, 'Meu marco');
      expect(list.single.auto, isFalse);
    });

    test('renomear muda nome e nota e tira a versão da limpeza das automáticas', () async {
      final s = await save('Versão automática', auto: true);
      expect(await c.versions.rename(s.id, 'Bom', note: 'guardar'), isTrue);
      final l = (await c.versions.list()).items.single;
      expect(l.name, 'Bom');
      expect(l.note, 'guardar');
      expect(l.auto, isFalse);
      expect(await c.versions.rename('nao-existe', 'x'), isFalse);
    });

    test('restaurar é um passo de desfazer: voltar ao que era antes', () async {
      c.addTrack();
      final v = await save('Duas faixas');
      c.addTrack();
      c.addMarker(beat: 1);
      final before = jsonEncode(c.doc.toJson());
      expect(c.doc.tracks.length, 3);
      final ok = await c.restoreDocument((await c.versions.load(v.id))!, label: 'Restaurar versão “Duas faixas”');
      expect(ok, isTrue);
      expect(c.doc.tracks.length, 2);
      expect(c.doc.markers, isEmpty);
      expect(c.nextUndo!.title, 'Restaurar versão “Duas faixas”');
      c.undo();
      expect(jsonEncode(c.doc.toJson()), before);
      c.redo();
      expect(c.doc.tracks.length, 2);
    });

    test('restaurar não desliga o metrônomo nem mexe nas preferências do aparelho', () async {
      final v = await save('A');
      c.doc.metronome = true;
      change();
      await c.restoreDocument((await c.versions.load(v.id))!, label: 'Restaurar');
      expect(c.doc.metronome, isTrue);
      expect(c.doc.markers, isEmpty);
    });

    test('restaurar um documento inválido devolve false e não mexe em nada', () async {
      change();
      final before = jsonEncode(c.doc.toJson());
      final count = c.historyCount;
      expect(await c.restoreDocument({'tracks': 3}, label: 'x'), isFalse);
      expect(jsonEncode(c.doc.toJson()), before);
      expect(c.historyCount, count);
    });

    test('comparar: contagens por tipo (faixas, clipes, notas, efeitos, marcadores, andamento)', () async {
      c.addInstrumentTrack(TrackKind.synth);
      final clip = c.createMidiClip(1, 0);
      clip.notes.add(MidiNote(pitch: 60, start: 0, length: 1, velocity: 0.8));
      c.addEffect(1, EffectKind.values.first);
      final base = await save('Base');
      // agora: uma faixa a mais, uma a menos de efeito, clipe mudado, marcador novo, andamento
      c.addTrack();
      c.removeEffect(1, c.doc.tracks[1].effects.first.id);
      clip.notes.add(MidiNote(pitch: 64, start: 1, length: 1, velocity: 0.8));
      clip.name = 'Renomeado';
      c.addMarker(beat: 4);
      c.setTempoMap([TempoPoint(0, 140)]);
      final diff = diffDocs((await c.versions.load(base.id))!, c.doc.toJson());
      DiffRow row(String what) => diff.rows.firstWhere((r) => r.what == what);
      expect((row('Faixas').added, row('Faixas').removed), (1, 0));
      expect((row('Clipes MIDI').added, row('Clipes MIDI').removed, row('Clipes MIDI').changed), (0, 0, 1));
      expect((row('Notas MIDI').added, row('Notas MIDI').removed), (1, 0));
      expect((row('Efeitos').added, row('Efeitos').removed, row('Efeitos').changed), (0, 1, 0));
      expect((row('Marcadores').added, row('Marcadores').removed), (1, 0));
      expect(row('Clipes de áudio').isZero, isTrue);
      expect(diff.notes.single, 'Andamento: 120 → 140');
      expect(diff.isSame, isFalse);
      expect(describeDiff(diff), contains('Faixas: +1'));
      expect(describeDiff(diff), contains('Efeitos: −1'));
      expect(describeDiff(diff), contains('1 mudado'));
    });

    test('comparar duas cópias iguais: sem diferença', () async {
      c.addTrack();
      final s = await save('A');
      final d = diffDocs((await c.versions.load(s.id))!, c.doc.toJson());
      expect(d.isSame, isTrue);
      expect(describeDiff(d), 'Igual ao projeto de agora.');
    });

    test('versão automática a cada N minutos de edição (relógio falso; padrão 15)', () async {
      c.addTrack(); // 1ª edição do período (a linha de base)
      await settle();
      expect((await c.versions.list()).items, isEmpty);
      now = now.add(const Duration(minutes: 14));
      change();
      await settle();
      expect((await c.versions.list()).items, isEmpty, reason: '14 min: cedo demais');
      now = now.add(const Duration(minutes: 2));
      change();
      await settle();
      await settle();
      final items = (await c.versions.list()).items;
      expect(items, hasLength(1));
      expect(items.single.auto, isTrue);
      expect(items.single.name, 'Versão automática');
      expect((await c.versions.load(items.single.id))!['markers'], hasLength(2));
      // o período reinicia: mais 10 min não bastam
      now = now.add(const Duration(minutes: 10));
      change();
      await settle();
      expect((await c.versions.list()).items, hasLength(1));
    });

    test('automáticas desligadas ou com outro intervalo', () async {
      await c.versions.setPrefs(const VersionsPrefs(auto: false));
      c.addTrack();
      now = now.add(const Duration(hours: 3));
      change();
      await settle();
      expect((await c.versions.list()).items, isEmpty);
      await c.versions.setPrefs(const VersionsPrefs(minutes: 5));
      now = now.add(const Duration(minutes: 1));
      change(); // baseline
      now = now.add(const Duration(minutes: 6));
      change();
      await settle();
      await settle();
      expect((await c.versions.list()).items, hasLength(1));
      // as preferências vivem no guardado do aparelho
      expect(VersionsPrefs.fromJson(jsonDecode(store.data['versions-prefs']! as String)).minutes, 5);
    });

    test('só as últimas 20 automáticas ficam; as manuais nunca saem', () async {
      final manual = await save('Marco');
      for (var i = 0; i < 25; i++) {
        now = now.add(const Duration(minutes: 1));
        change();
        await save('auto $i', auto: true);
      }
      final items = (await c.versions.list()).items;
      expect(items.where((s) => s.auto), hasLength(autoKeep));
      expect(items.where((s) => !s.auto).single.id, manual.id);
      expect(items.where((s) => s.auto).first.name, 'auto 24');
      expect(items.where((s) => s.auto).last.name, 'auto 5');
    });

    test('ao abrir: guarda uma automática se a última versão tem mais de 1 h (ou não há), só com conteúdo', () async {
      // sem conteúdo (faixa vazia): nada
      await c.versions.onOpen();
      expect((await c.versions.list()).items, isEmpty);
      c.addInstrumentTrack(TrackKind.synth);
      c.createMidiClip(1, 0);
      await c.versions.onOpen();
      var items = (await c.versions.list()).items;
      expect(items, hasLength(1));
      expect(items.single.name, 'Ao abrir o projeto');
      // 30 min depois: nada novo
      now = now.add(const Duration(minutes: 30));
      change();
      await c.versions.onOpen();
      expect((await c.versions.list()).items, hasLength(1));
      // mais de 1 h da última: guarda
      now = now.add(const Duration(minutes: 40));
      await c.versions.onOpen();
      items = (await c.versions.list()).items;
      expect(items, hasLength(2));
      // idêntico à mais nova: o dedupe segura
      now = now.add(const Duration(hours: 2));
      await c.versions.onOpen();
      expect((await c.versions.list()).items, hasLength(2));
    });

    test('ao abrir com as automáticas desligadas: nada', () async {
      await c.versions.setPrefs(const VersionsPrefs(auto: false));
      c.addInstrumentTrack(TrackKind.synth);
      c.createMidiClip(1, 0);
      await c.versions.onOpen();
      expect((await c.versions.list()).items, isEmpty);
    });

    test('arquivo de versão corrompido não derruba: a lista pula, conta e limpa', () async {
      final ok = await save('Boa');
      store.data['snapshots:p:lixo1'] = 'isto não é json';
      store.data['snapshots:p:lixo2'] = '{"format":"jopendaw-version","version":1,"id":"lixo2","created_at":"ontem","doc":{"tracks":[]}}';
      store.data['snapshots:p:lixo3'] = '{"format":"outro"}';
      store.data['snapshots:p:lixo4'] = {'não': 'texto'};
      store.data['snapshots:p:copiado'] = store.data['snapshots:p:${ok.id}']!; // envelope sob outro nome
      final list = await c.versions.list();
      expect(list.items.map((s) => s.name), ['Boa']);
      expect(list.corruptKeys.toSet(), {'snapshots:p:lixo1', 'snapshots:p:lixo2', 'snapshots:p:lixo3', 'snapshots:p:lixo4', 'snapshots:p:copiado'});
      expect(await c.versions.load('lixo1'), isNull);
      expect(await c.versions.load('lixo2'), isNull);
      expect(await c.versions.rename('lixo1', 'x'), isFalse);
      await c.versions.deleteCorrupt(list.corruptKeys);
      expect((await c.versions.list()).corruptKeys, isEmpty);
      expect((await c.versions.list()).items, hasLength(1));
      // salvar de novo funciona com lixo por perto
      store.data['snapshots:p:lixo5'] = '{';
      change();
      await save('Outra');
      expect((await c.versions.list()).items, hasLength(2));
    });

    test('envelope inválido: formatos e versões que não conhecemos viram null', () {
      for (final bad in [
        '',
        '[]',
        '{"format":"jopendaw-version"}',
        '{"format":"jopendaw-version","version":99,"id":"a","created_at":"2026-01-01T00:00:00Z","doc":{"tracks":[]}}',
        '{"format":"jopendaw-version","version":1,"id":"","created_at":"2026-01-01T00:00:00Z","doc":{"tracks":[]}}',
        '{"format":"jopendaw-version","version":1,"id":"a","created_at":"2026-01-01T00:00:00Z","doc":{"tracks":3}}',
      ]) {
        expect(parseSnapshotEnvelope(bad), isNull, reason: bad);
      }
      final good = parseSnapshotEnvelope(
        '{"format":"jopendaw-version","version":1,"id":"a","name":"n","created_at":"2026-01-01T00:00:00Z","doc":{"tracks":[]}}',
      );
      expect(good!.meta.tracks, 0);
    });

    test('alerta quando as versões passam do limite de espaço', () async {
      await save('A');
      change();
      await save('B');
      var list = await c.versions.list();
      expect(list.overLimit, isFalse);
      expect(snapshotWarnBytes, 50 * 1024 * 1024);
      c.versions.warnBytes = list.totalBytes - 1;
      list = await c.versions.list();
      expect(list.overLimit, isTrue);
    });

    test('duplicar como projeto novo: cria pela importação, com o documento da versão e sem tocar no original', () async {
      c.addInstrumentTrack(TrackKind.synth);
      final s = await save('Bom');
      final created = <String>[];
      final p = await duplicateVersionAsProject(
        doc: (await c.versions.load(s.id))!,
        name: 'Teste — Bom',
        existingNames: const ['Teste'],
        createProject: (name) async {
          created.add(name);
          return _project('novo', name);
        },
        patchProject: (id, patch) async => _project(id, 'Teste — Bom'),
        deleteProject: (id) async => fail('não devia apagar'),
        store: store,
      );
      expect(created, ['Teste — Bom']);
      expect(p.id, 'novo');
      final copy = DawDoc.fromJson(jsonDecode(store.data['doc:novo']! as String) as Map<String, dynamic>);
      expect(copy.tracks.map((t) => t.name), c.doc.tracks.map((t) => t.name));
      expect(store.data.containsKey('snapshots:novo:${s.id}'), isFalse, reason: 'o projeto novo começa sem versões');
      expect(store.data.containsKey('snapshots:p:${s.id}'), isTrue);
    });

    test('purgeLocalProject leva as versões (e só as do projeto apagado)', () async {
      await save('A');
      change();
      await save('B');
      store.data['snapshots:outro:z'] = 'x';
      store.data['snapshots:pp:z'] = 'x';
      store.data['doc:p'] = jsonEncode(c.doc.toJson());
      await purgeLocalProject(store, 'p', const []);
      expect(store.data.keys.where((k) => k.startsWith('snapshots:p:')), isEmpty);
      expect(store.data.containsKey('snapshots:outro:z'), isTrue);
      expect(store.data.containsKey('snapshots:pp:z'), isTrue, reason: 'prefixo com ":" não pega o projeto "pp"');
      expect(store.data.containsKey('doc:p'), isFalse);
    });

    test('aparelho novo: sem versões (a mensagem diz que elas são locais)', () async {
      expect((await c.versions.list()).isEmpty, isTrue);
      expect(noVersionsMessage, contains('só no aparelho'));
    });

    test('exportEnvelope devolve o texto guardado (gancho para enviar ao servidor)', () async {
      final s = await save('A');
      expect(await c.versions.exportEnvelope(s.id), store.data['snapshots:p:${s.id}']);
      expect(parseSnapshotEnvelope((await c.versions.exportEnvelope(s.id))!)!.meta.name, 'A');
    });
  });

  group('telas', () {
    Future<void> open(WidgetTester t, Size size, Widget Function(BuildContext) launch) async {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Builder(
            builder: (ctx) => Scaffold(
              body: Center(
                child: FilledButton(onPressed: () => launch(ctx), child: const Text('abrir')),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('abrir'));
      await t.pumpAndSettle();
    }

    for (final size in const [Size(360, 780), Size(1512, 900)]) {
      testWidgets('histórico ${size.width.toInt()} px: lista, destaque, ir até o passo, limpar; sem overflow', (t) async {
        c.addTrack();
        c.addMarker(beat: 1);
        c.edit((d) => d.masterGain = 0.4);
        c.edit((d) => d.masterGain = 0.3, label: 'Um passo com um rótulo bem comprido para conferir que a linha quebra em vez de estourar a largura do painel');
        await open(t, size, (ctx) {
          showHistoryDialog(ctx, c);
          return const SizedBox();
        });
        expect(find.text('Histórico'), findsOneWidget);
        expect(find.byKey(const ValueKey('history-count')), findsOneWidget);
        expect(find.textContaining('4 passos'), findsOneWidget);
        expect(find.text('Estado de agora'), findsOneWidget);
        await t.scrollUntilVisible(find.text('Adicionar faixa'), 80, scrollable: find.byType(Scrollable).first);
        expect(find.text('Adicionar faixa'), findsOneWidget);
        await t.scrollUntilVisible(find.textContaining('Edição ('), -80, scrollable: find.byType(Scrollable).first);
        expect(find.textContaining('Edição ('), findsOneWidget);
        expect(t.takeException(), isNull);
        // tocar no segundo passo: volta até ele numa operação
        await tapV(t, find.byKey(const ValueKey('history-step-2')));
        await t.pumpAndSettle();
        expect(c.doc.tracks.length, 2);
        expect(c.doc.markers.length, 1);
        expect(c.doc.masterGain, 1.0);
        expect(c.canRedo, isTrue);
        await tapV(t, find.byKey(const ValueKey('history-step-4')));
        await t.pumpAndSettle();
        expect(c.doc.masterGain, 0.3);
        // limpar pede confirmação
        await t.tap(find.byKey(const ValueKey('history-clear')));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const ValueKey('history-clear-confirm')));
        await t.pumpAndSettle();
        expect(c.historyCount, 0);
        expect(find.byKey(const ValueKey('history-empty')), findsOneWidget);
        expect(t.takeException(), isNull);
      });

      testWidgets('versões ${size.width.toInt()} px: salvar, comparar, restaurar (com "Antes de restaurar"), renomear, apagar; sem overflow', (t) async {
        c.addTrack();
        await open(t, size, (ctx) {
          showVersionsDialog(ctx, c, duplicate: (doc, name) async => _project('dup', name), open: (_, _) {});
          return const SizedBox();
        });
        expect(find.byKey(const ValueKey('versions-empty')), findsOneWidget);
        // salvar
        await t.tap(find.byKey(const ValueKey('versions-save')));
        await t.pumpAndSettle();
        await t.enterText(find.byKey(const ValueKey('version-name')), 'Marco 1');
        await t.enterText(find.byKey(const ValueKey('version-note')), 'antes do refrão');
        await t.tap(find.byKey(const ValueKey('version-confirm')));
        await t.pumpAndSettle();
        expect(find.text('Marco 1'), findsOneWidget);
        expect(find.text('antes do refrão'), findsOneWidget);
        expect(find.textContaining('1 versão'), findsWidgets);
        expect(t.takeException(), isNull);
        // salvar sem mudança não duplica
        await t.tap(find.byKey(const ValueKey('versions-save')));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const ValueKey('version-confirm')));
        await t.pumpAndSettle();
        expect((await c.versions.list()).items, hasLength(1));
        expect(find.textContaining('igual à versão mais nova'), findsOneWidget);
        // mexe no projeto e compara
        c.addTrack();
        c.addMarker(beat: 2);
        final id = (await c.versions.list()).items.single.id;
        await tapV(t, find.byKey(ValueKey('version-compare-$id')));
        await t.pumpAndSettle();
        expect(find.textContaining('Faixas: +1'), findsOneWidget);
        expect(find.textContaining('Marcadores: +1'), findsOneWidget);
        // restaurar pede confirmação e guarda "Antes de restaurar"
        await tapV(t, find.byKey(ValueKey('version-restore-$id')));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const ValueKey('restore-confirm')));
        await t.pumpAndSettle();
        expect(c.doc.tracks.length, 2);
        expect(c.doc.markers, isEmpty);
        expect(c.nextUndo!.title, 'Restaurar versão “Marco 1”');
        final names = (await c.versions.list()).items.map((s) => s.name).toList();
        expect(names, ['Antes de restaurar Marco 1', 'Marco 1']);
        expect(find.textContaining('Desfazer volta'), findsOneWidget);
        c.undo();
        expect(c.doc.tracks.length, 3);
        expect(t.takeException(), isNull);
        // renomear
        await tapV(t, find.byKey(ValueKey('version-menu-$id')));
        await t.pumpAndSettle();
        await t.tap(find.text('Renomear…'));
        await t.pumpAndSettle();
        await t.enterText(find.byKey(const ValueKey('version-name')), 'Marco final');
        await t.tap(find.byKey(const ValueKey('version-confirm')));
        await t.pumpAndSettle();
        expect(find.text('Marco final'), findsOneWidget);
        // duplicar como projeto novo
        await tapV(t, find.byKey(ValueKey('version-menu-$id')));
        await t.pumpAndSettle();
        await t.tap(find.text('Duplicar como novo projeto…'));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const ValueKey('version-confirm')));
        await t.pumpAndSettle();
        expect(find.textContaining('Criei o projeto'), findsOneWidget);
        // apagar
        await tapV(t, find.byKey(ValueKey('version-menu-$id')));
        await t.pumpAndSettle();
        await t.tap(find.text('Apagar…'));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const ValueKey('delete-confirm')));
        await t.pumpAndSettle();
        expect((await c.versions.list()).items.map((s) => s.name), ['Antes de restaurar Marco 1']);
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('versões: avisos de espaço e de arquivo ilegível, e o interruptor das automáticas', (t) async {
      c.addTrack();
      await c.versions.save(name: 'A');
      store.data['snapshots:p:lixo'] = 'x';
      c.versions.warnBytes = 10;
      await open(t, const Size(360, 780), (ctx) {
        showVersionsDialog(ctx, c, duplicate: (doc, name) async => _project('dup', name), open: (_, _) {});
        return const SizedBox();
      });
      expect(find.byKey(const ValueKey('versions-overlimit')), findsOneWidget);
      expect(find.byKey(const ValueKey('versions-corrupt')), findsOneWidget);
      expect(t.takeException(), isNull);
      await tapV(t, find.byKey(const ValueKey('versions-auto')));
      await t.pumpAndSettle();
      expect((await c.versions.prefs()).auto, isFalse);
      expect(find.byKey(const ValueKey('versions-minutes')), findsNothing);
      await tapV(t, find.text('Limpar'));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('versions-corrupt')), findsNothing);
      expect(store.data.containsKey('snapshots:p:lixo'), isFalse);
    });

    testWidgets('botões desfazer/refazer: tooltip com o rótulo e menu de pressão longa com Histórico e Versões', (t) async {
      c.addTrack();
      t.view.physicalSize = const Size(800, 600);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: ListenableBuilder(
              listenable: c,
              builder: (_, _) => Row(
                children: [
                  HistoryStepButton(c: c, redo: false),
                  HistoryStepButton(c: c, redo: true),
                ],
              ),
            ),
          ),
        ),
      );
      final tip = t.widget<Tooltip>(find.byType(Tooltip).first);
      expect(tip.message, contains('Desfazer: Adicionar faixa'));
      await t.longPress(find.byKey(const ValueKey('undo-button')));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull, reason: 'menu');
      expect(find.textContaining('Histórico…'), findsOneWidget);
      expect(find.text('Versões…'), findsOneWidget);
      expect(find.text('Salvar versão…'), findsOneWidget);
      await t.tap(find.textContaining('Histórico…'));
      await t.pumpAndSettle();
      expect(find.text('Histórico'), findsOneWidget);
      final ex = t.takeException();
      if (ex != null) fail(ex.toString() + (ex is FlutterError ? ex.diagnostics.map((d) => d.toDescription()).join('\n') : ''));
    });
  });
}
