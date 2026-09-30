// Atalhos personalizáveis: o catálogo (sem duplicados nos padrões), a equivalência com o tratamento de teclas de
// antes (um oráculo escrito aqui com a lógica antiga), regravar/conflito/restaurar, o JSON local e o `.jokeys`
// (ida e volta e arquivos ruins), a tela de personalização (360 e 1512 px) e a janela de atalhos gerada do catálogo.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jopendaw_app/daw/controller.dart' show noteKeys;
import 'package:jopendaw_app/daw/keymap.dart';
import 'package:jopendaw_app/daw/keymap_ui.dart';
import 'package:jopendaw_app/daw/shortcuts_dialog.dart';
import 'package:jopendaw_app/widgets/theme.dart';

import 'studio_test.dart' show mount, studio, flushSave;

Keymap fresh() => Keymap(MemoryKeymapStorage());

KeyCombo k(String s) => KeyCombo.parse(s)!;

/// A combinação como o teclado a manda para [KeyCombo.fromKey], para um token (com o caractere que a produz).
KeyCombo? stroke(String token, {bool mod = false, bool shift = false, bool alt = false}) {
  if (token == '?') return KeyCombo.fromKey(LogicalKeyboardKey.slash, character: '?', shift: true, mod: mod, alt: alt);
  final key = logicalKeyForToken(token)!;
  final ch = token == '+' || token == '-' ? token : null;
  return KeyCombo.fromKey(key, character: ch, mod: mod, shift: shift, alt: alt);
}

/// O tratamento de teclas da tela do projeto ANTES da personalização (project_screen.dart), copiado como estava:
/// devolve o id da ação do catálogo que ele disparava, ou null.
String? legacyGlobal(
  LogicalKeyboardKey k, {
  String? ch,
  bool mod = false,
  bool shift = false,
  bool recording = false,
  bool learning = false,
  bool dock = false,
}) {
  if (k == LogicalKeyboardKey.space) return 'transport.play';
  if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.home) return 'transport.stop';
  if (!mod && k == LogicalKeyboardKey.keyR) return 'transport.record';
  if (k == LogicalKeyboardKey.delete || k == LogicalKeyboardKey.backspace) return 'edit.delete';
  if (mod && recording && (k == LogicalKeyboardKey.keyZ || k == LogicalKeyboardKey.keyY || k == LogicalKeyboardKey.keyI)) return 'noop';
  if (mod && k == LogicalKeyboardKey.keyZ) return shift ? 'edit.redo' : 'edit.undo';
  if (mod && k == LogicalKeyboardKey.keyY) return 'edit.redo';
  if (mod && k == LogicalKeyboardKey.keyD) return 'edit.duplicate';
  if (mod && k == LogicalKeyboardKey.keyI) return 'edit.import';
  if (mod && k == LogicalKeyboardKey.keyK) return 'kbd.toggle';
  if (!mod && shift && k == LogicalKeyboardKey.keyK) return 'midilearn.toggle';
  if (!mod && k == LogicalKeyboardKey.keyS) return 'edit.split';
  if (!mod && shift && k == LogicalKeyboardKey.keyL) return 'loop.clip';
  if (!mod && k == LogicalKeyboardKey.keyL) return 'transport.loop';
  if (!mod && k == LogicalKeyboardKey.keyM) return shift ? 'marker.rename' : 'marker.add';
  if (!mod && k == LogicalKeyboardKey.bracketLeft) return 'marker.prev';
  if (!mod && k == LogicalKeyboardKey.bracketRight) return 'marker.next';
  if (!mod && k == LogicalKeyboardKey.keyZ) return shift ? 'view.fitClip' : 'view.fitAll';
  if (!mod && k == LogicalKeyboardKey.keyC) return 'transport.metronome';
  // da fase 17 (punch e tap tempo): teclas que antes não faziam nada
  if (!mod && k == LogicalKeyboardKey.keyP) return 'transport.punch';
  if (!mod && k == LogicalKeyboardKey.keyT) return 'transport.tap';
  if (!mod && k == LogicalKeyboardKey.keyX) return 'panel.mixer';
  if (!mod && k == LogicalKeyboardKey.keyE) return 'panel.editor';
  if (!mod && k == LogicalKeyboardKey.keyI) return 'panel.instrument';
  if (!mod && k == LogicalKeyboardKey.keyF) return 'panel.effects';
  if (ch == '?' || (shift && k == LogicalKeyboardKey.slash)) return 'help.shortcuts';
  if (k == LogicalKeyboardKey.escape && learning) return 'midilearn.cancel';
  if (k == LogicalKeyboardKey.escape && dock) return 'panel.close';
  if (k == LogicalKeyboardKey.equal || k == LogicalKeyboardKey.add || k == LogicalKeyboardKey.numpadAdd || ch == '+') return 'view.zoomIn';
  if (k == LogicalKeyboardKey.minus || k == LogicalKeyboardKey.numpadSubtract || ch == '-') return 'view.zoomOut';
  return null;
}

/// O de agora: o que a tela faz com a combinação (a primeira ação que se aplica ao estado).
String? nowGlobal(Keymap km, KeyCombo s, {bool recording = false, bool learning = false, bool dock = false}) {
  for (final a in km.resolve(s, KeyContext.global)) {
    if (recording && (a.id == 'edit.undo' || a.id == 'edit.redo' || a.id == 'edit.import')) return 'noop';
    if (a.id == 'midilearn.cancel' && !learning) continue;
    if (a.id == 'panel.close' && !dock) continue;
    if (a.id == 'view.follow') return a.id;
    return a.id;
  }
  return null;
}

/// O tratamento de teclas do piano roll de antes (piano_roll_input.dart), copiado como estava.
String? legacyRoll(LogicalKeyboardKey k, {bool mod = false, bool shift = false, bool selEmpty = false, bool drums = false}) {
  if (k == LogicalKeyboardKey.delete || k == LogicalKeyboardKey.backspace) return 'pr.delete';
  if (k == LogicalKeyboardKey.escape) return selEmpty ? null : 'pr.deselect';
  if (mod) {
    if (k == LogicalKeyboardKey.keyA) return 'pr.selectAll';
    if (k == LogicalKeyboardKey.keyC) return 'pr.copy';
    if (k == LogicalKeyboardKey.keyX) return 'pr.cut';
    if (k == LogicalKeyboardKey.keyV) return 'pr.paste';
    if (k == LogicalKeyboardKey.keyD) return 'pr.duplicate';
    return null;
  }
  if (k == LogicalKeyboardKey.keyQ && !shift) return 'pr.quantize';
  if (!shift && k == LogicalKeyboardKey.keyK) return 'pr.split';
  if (!shift && k == LogicalKeyboardKey.keyJ) return 'pr.join';
  if (shift && k == LogicalKeyboardKey.keyH) return 'pr.humanize';
  if (shift && k == LogicalKeyboardKey.keyL) return 'pr.legato';
  if (selEmpty) return null;
  if (k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.arrowDown) {
    final octave = shift && !drums;
    return k == LogicalKeyboardKey.arrowUp ? (octave ? 'pr.octaveUp' : 'pr.up') : (octave ? 'pr.octaveDown' : 'pr.down');
  }
  if (k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.arrowRight) {
    return k == LogicalKeyboardKey.arrowRight ? (shift ? 'pr.barRight' : 'pr.right') : (shift ? 'pr.barLeft' : 'pr.left');
  }
  return null;
}

/// O de agora no piano roll, com as regras que o `_handleKey` aplica em cima da ação.
String? nowRoll(Keymap km, KeyCombo s, {bool selEmpty = false, bool drums = false}) {
  final hits = km.resolve(s, KeyContext.pianoRoll);
  if (hits.isEmpty) return null;
  final id = hits.first.id;
  if (id == 'pr.deselect' && selEmpty) return null;
  const needSel = {'pr.up', 'pr.down', 'pr.octaveUp', 'pr.octaveDown', 'pr.left', 'pr.right', 'pr.barLeft', 'pr.barRight'};
  if (needSel.contains(id) && selEmpty) return null;
  if (drums && id == 'pr.octaveUp') return 'pr.up';
  if (drums && id == 'pr.octaveDown') return 'pr.down';
  return id;
}

void main() {
  group('catálogo', () {
    test('ids únicos, rótulo e categoria; padrões válidos e sem duplicados no mesmo contexto', () {
      final ids = <String>{};
      for (final a in keyCatalog) {
        expect(ids.add(a.id), isTrue, reason: 'id repetido ${a.id}');
        expect(a.label, isNotEmpty);
        for (final d in a.defaults) {
          final c = KeyCombo.parse(d);
          expect(c, isNotNull, reason: '${a.id}: $d');
          expect(c.toString(), d, reason: 'forma canônica de $d');
          if (!a.fixed) expect(reservedReason(c!, a.context), isNull, reason: '${a.id} usa uma tecla reservada por padrão: $d');
        }
        expect(a.defaults.length, lessThanOrEqualTo(maxBindingsPerAction));
      }
      // duplicado: mesma combinação em duas ações editáveis da mesma camada (geral e arranjo dividem uma)
      String scope(KeyContext c) => c == KeyContext.arrangement ? KeyContext.global.name : c.name;
      final seen = <String, String>{};
      for (final a in keyCatalog.where((a) => !a.fixed)) {
        for (final d in a.defaults) {
          final key = '${scope(a.context)}|$d';
          expect(seen.containsKey(key), isFalse, reason: '$d em ${a.id} e ${seen[key]}');
          seen[key] = a.id;
        }
      }
    });

    test('cobre as teclas que o estúdio tratava e as letras de nota do controlador', () {
      for (final id in [
        'transport.play', 'transport.stop', 'transport.record', 'transport.loop', 'transport.metronome', 'marker.add', 'marker.rename', //
        'marker.prev', 'marker.next', 'loop.clip', 'view.fitAll', 'view.fitClip', 'view.zoomIn', 'view.zoomOut', 'view.follow', 'edit.undo',
        'edit.redo', 'edit.duplicate', 'edit.split', 'edit.delete', 'edit.import', 'panel.mixer', 'panel.editor', 'panel.instrument',
        'panel.effects', 'panel.close', 'help.shortcuts', 'midilearn.toggle', 'midilearn.cancel', 'kbd.toggle', 'kbd.octaveDown',
        'kbd.octaveUp', 'kbd.velocityDown', 'kbd.velocityUp', 'pr.quantize', 'pr.split', 'pr.join', 'pr.humanize', 'pr.legato',
      ]) {
        expect(keyActionById(id), isNotNull, reason: id);
      }
      expect(noteKeyLetters, [for (final n in noteKeys) n.debugName!.replaceAll('Key ', '')]);
    });

    test('formato: parse ↔ toString, tokens inválidos, rótulos por sistema', () {
      for (final s in ['Space', 'Mod+Z', 'Mod+Shift+Z', 'Shift+K', '[', ']', '+', '=', '-', '?', 'Up', 'Shift+Left', 'F2', 'Alt+F2', 'Mod+Shift+Alt+Q']) {
        expect(KeyCombo.parse(s).toString(), s);
      }
      for (final bad in ['', 'Mod+', 'Mod', 'Shift+', 'Foo', 'Mod+Mod+Z', 'Shift+?', 'Shift++', 'ctrl+z', 'Z+Z', null, 3]) {
        expect(KeyCombo.parse(bad), isNull, reason: '$bad');
      }
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      expect(k('Mod+Shift+Z').label, '⌘+Shift+Z');
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      expect(k('Mod+Shift+Z').label, 'Ctrl+Shift+Z');
      expect(k('Space').label, 'Espaço');
      expect(k('Shift+Up').label, 'Shift+↑');
      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('equivalência com o tratamento de teclas de antes', () {
    test('para cada ação, a tecla padrão dispara a mesma ação que antes', () {
      final km = fresh();
      var checked = 0;
      for (final a in keyCatalog) {
        if (a.context == KeyContext.playing) continue;
        for (final d in a.defaultCombos) {
          final s = d.token == '?' ? stroke('?')! : KeyCombo(d.token, mod: d.mod, shift: d.shift, alt: d.alt);
          final key = d.token == '?' ? LogicalKeyboardKey.slash : logicalKeyForToken(d.token)!;
          final ch = d.token == '?' ? '?' : null;
          if (a.context == KeyContext.pianoRoll) {
            if (a.id == 'pr.deselect') continue; // Esc: coberto abaixo
            expect(
              nowRoll(km, s),
              legacyRoll(key, mod: d.mod, shift: d.shift),
              reason: '${a.id} ${d.label}',
            );
          } else {
            // Esc: só a ação que se aplica ao estado
            final learning = a.id == 'midilearn.cancel';
            final dock = a.id == 'panel.close';
            expect(
              nowGlobal(km, s, learning: learning, dock: dock),
              legacyGlobal(key, ch: ch, mod: d.mod, shift: d.shift, learning: learning, dock: dock),
              reason: '${a.id} ${d.label}',
            );
            expect(
              nowGlobal(km, s, learning: learning, dock: dock),
              a.id,
              reason: a.id,
            );
          }
          checked++;
        }
      }
      expect(checked, greaterThan(50));
    });

    test('teclas com modificador de sempre: Shift+= é +, Shift+/ é ?, o - do numérico, o + do numérico', () {
      final km = fresh();
      String? now(LogicalKeyboardKey key, {String? ch, bool shift = false, bool mod = false}) {
        final s = KeyCombo.fromKey(key, character: ch, shift: shift, mod: mod);
        return s == null ? null : nowGlobal(km, s);
      }

      expect(now(LogicalKeyboardKey.equal), 'view.zoomIn');
      expect(now(LogicalKeyboardKey.equal, shift: true, ch: '+'), 'view.zoomIn');
      expect(now(LogicalKeyboardKey.add, shift: true), 'view.zoomIn');
      expect(now(LogicalKeyboardKey.numpadAdd), 'view.zoomIn');
      expect(now(LogicalKeyboardKey.numpadSubtract), 'view.zoomOut');
      expect(now(LogicalKeyboardKey.minus), 'view.zoomOut');
      expect(now(LogicalKeyboardKey.slash, shift: true, ch: '?'), 'help.shortcuts');
      expect(now(LogicalKeyboardKey.slash, shift: true), 'help.shortcuts');
      expect(now(LogicalKeyboardKey.slash), isNull);
    });

    test('varredura de todas as teclas x Ctrl x Shift x Alt x estado: o tratamento é idêntico ao de antes', () {
      final km = fresh();
      var n = 0;
      for (final token in keyTokens) {
        if (token == '?') continue;
        final key = logicalKeyForToken(token)!;
        for (final mod in [false, true]) {
          for (final shift in [false, true]) {
            for (final alt in [false, true]) {
              for (final rec in [false, true]) {
                for (final learn in [false, true]) {
                  for (final dock in [false, true]) {
                    final ch = token == '+' || token == '-' ? token : null;
                    final old = legacyGlobal(key, ch: ch, mod: mod, shift: shift, recording: rec, learning: learn, dock: dock);
                    final s = KeyCombo.fromKey(key, character: ch, mod: mod, shift: shift, alt: alt)!;
                    expect(
                      nowGlobal(km, s, recording: rec, learning: learn, dock: dock),
                      old,
                      reason: '$token mod=$mod shift=$shift alt=$alt rec=$rec learn=$learn dock=$dock',
                    );
                    n++;
                  }
                }
              }
            }
          }
        }
      }
      expect(n, greaterThan(3000));
      // o ? (Shift+/ com o caractere), com e sem Ctrl/Alt
      for (final mod in [false, true]) {
        for (final alt in [false, true]) {
          final s = KeyCombo.fromKey(LogicalKeyboardKey.slash, character: '?', shift: true, mod: mod, alt: alt)!;
          expect(nowGlobal(km, s), legacyGlobal(LogicalKeyboardKey.slash, ch: '?', mod: mod, shift: true));
        }
      }
    });

    test('piano roll: varredura de todas as teclas x Ctrl x Shift x seleção vazia x bateria é idêntica', () {
      final km = fresh();
      for (final token in keyTokens) {
        if (token == '?') continue;
        final key = logicalKeyForToken(token)!;
        for (final mod in [false, true]) {
          for (final shift in [false, true]) {
            for (final selEmpty in [false, true]) {
              for (final drums in [false, true]) {
                for (final alt in [false, true]) {
                  final s = KeyCombo.fromKey(key, mod: mod, shift: shift, alt: alt)!;
                  expect(
                    nowRoll(km, s, selEmpty: selEmpty, drums: drums),
                    legacyRoll(key, mod: mod, shift: shift, selEmpty: selEmpty, drums: drums),
                    reason: '$token mod=$mod shift=$shift alt=$alt vazia=$selEmpty bateria=$drums',
                  );
                }
              }
            }
          }
        }
      }
    });

    test('teclado tocando: Z X C V por posição são oitava e velocidade; as teclas de nota não são ação', () {
      final km = fresh();
      expect(km.playingAction(PhysicalKeyboardKey.keyZ)?.id, 'kbd.octaveDown');
      expect(km.playingAction(PhysicalKeyboardKey.keyX)?.id, 'kbd.octaveUp');
      expect(km.playingAction(PhysicalKeyboardKey.keyC)?.id, 'kbd.velocityDown');
      expect(km.playingAction(PhysicalKeyboardKey.keyV)?.id, 'kbd.velocityUp');
      for (final n in noteKeys) {
        expect(km.playingAction(n), isNull, reason: n.debugName);
      }
      expect(km.playingAction(PhysicalKeyboardKey.keyR), isNull);
      // e a camada geral não vê as do teclado tocando
      expect(km.resolve(stroke('Z')!, KeyContext.global).map((a) => a.id), ['view.fitAll']);
    });

    test('Espaço, Enter, Home, Delete, Backspace e Esc continuam valendo com qualquer modificador', () {
      final km = fresh();
      for (final t in ['Space', 'Enter', 'Home', 'Delete', 'Backspace']) {
        for (final (mod, shift, alt) in [(true, false, false), (false, true, false), (true, true, true)]) {
          expect(
            km.resolve(KeyCombo(t, mod: mod, shift: shift, alt: alt), KeyContext.global),
            isNotEmpty,
            reason: '$t $mod $shift $alt',
          );
        }
      }
      // mas uma combinação própria vence
      km.assign('edit.undo', k('Mod+Space'), slot: 0);
      expect(km.resolve(k('Mod+Space'), KeyContext.global).single.id, 'edit.undo');
      expect(km.resolve(k('Space'), KeyContext.global).single.id, 'transport.play');
    });
  });

  group('regravar, conflito, restaurar', () {
    test('regravar troca só aquele atalho; restaurar volta ao padrão', () {
      final km = fresh();
      expect(km.assign('transport.metronome', k('B'), slot: 0), isTrue);
      expect(km.bindingsOf('transport.metronome'), [k('B')]);
      expect(km.resolve(k('B'), KeyContext.global).single.id, 'transport.metronome');
      expect(km.resolve(k('C'), KeyContext.global), isEmpty);
      expect(km.isCustomized('transport.metronome'), isTrue);
      km.reset('transport.metronome');
      expect(km.bindingsOf('transport.metronome'), [k('C')]);
      expect(km.hasCustom, isFalse);
      // mexer no segundo atalho de uma ação de dois
      expect(km.assign('transport.stop', k('B'), slot: 1), isTrue);
      expect(km.bindingsOf('transport.stop'), [k('Enter'), k('B')]);
      // voltar ao padrão por regravar também tira a personalização
      expect(km.assign('transport.stop', k('Home'), slot: 1), isTrue);
      expect(km.hasCustom, isFalse);
    });

    test('acrescentar até o limite; remover deixa sem atalho; a ação sem tecla ganha uma', () {
      final km = fresh();
      expect(km.bindingsOf('view.follow'), isEmpty);
      expect(km.assign('view.follow', k('G')), isTrue);
      expect(km.assign('view.follow', k('H')), isTrue);
      expect(km.assign('view.follow', k('J')), isTrue);
      expect(km.assign('view.follow', k('N')), isFalse, reason: 'passou do limite');
      expect(km.bindingsOf('view.follow').length, maxBindingsPerAction);
      expect(km.removeBinding('edit.delete', 0), isTrue);
      expect(km.bindingsOf('edit.delete'), [k('Backspace')]);
      expect(km.removeBinding('edit.delete', 0), isTrue);
      expect(km.bindingsOf('edit.delete'), isEmpty);
      expect(km.resolve(k('Delete'), KeyContext.global), isEmpty);
      km.reset('edit.delete');
      expect(km.bindingsOf('edit.delete'), [k('Delete'), k('Backspace')]);
      km.resetAll();
      expect(km.hasCustom, isFalse);
    });

    test('conflito no mesmo contexto: recusa sem trocar; trocar dá o atalho e a outra recebe o antigo', () {
      final km = fresh();
      // S (cortar) já é do arranjo; M (marcador) é geral: mesma camada
      final c = km.check('marker.add', k('S'));
      expect(c.status, AssignStatus.conflict);
      expect(c.other!.id, 'edit.split');
      expect(km.assign('marker.add', k('S'), slot: 0), isFalse);
      expect(km.bindingsOf('marker.add'), [k('M')]);
      expect(km.assign('marker.add', k('S'), slot: 0, swap: true), isTrue);
      expect(km.bindingsOf('marker.add'), [k('S')]);
      expect(km.bindingsOf('edit.split'), [k('M')]);
      expect(km.resolve(k('S'), KeyContext.global).single.id, 'marker.add');
      expect(km.resolve(k('M'), KeyContext.global).single.id, 'edit.split');
      // acrescentando (sem atalho antigo): a outra fica sem
      expect(km.assign('view.follow', k('E'), swap: true), isTrue);
      expect(km.bindingsOf('panel.editor'), isEmpty);
      expect(km.bindingsOf('view.follow'), [k('E')]);
    });

    test('contextos diferentes não conflitam (Ctrl+D é do arranjo e do piano roll); geral e arranjo conflitam', () {
      final km = fresh();
      expect(km.conflictOf('pr.duplicate', k('Mod+D')), isNull, reason: 'o piano roll só usa a dele: já é o padrão');
      expect(km.check('pr.split', k('Z')).status, AssignStatus.ok, reason: 'Z é do arranjo, não do piano roll');
      expect(km.check('view.fitAll', k('S')).status, AssignStatus.conflict);
      expect(km.check('kbd.octaveDown', k('Q')).status, AssignStatus.ok);
    });

    test('teclas reservadas não são atribuídas: Esc, navegador e sistema, e as de nota no teclado tocando', () {
      final km = fresh();
      for (final s in ['Escape', 'Mod+R', 'Mod+W', 'Mod+T', 'Mod+N', 'Mod+Shift+T', 'Mod+Q', 'F5', 'F11', 'F12', 'Alt+F4', 'Mod+1', 'Tab', 'Mod+F5']) {
        final c = km.check('marker.add', k(s));
        expect(c.status, AssignStatus.reserved, reason: s);
        expect(c.reason, isNotEmpty);
        expect(km.assign('marker.add', k(s)), isFalse);
      }
      expect(km.bindingsOf('marker.add'), [k('M')]);
      expect(km.check('marker.add', k('F2')).status, AssignStatus.ok);
      expect(km.check('marker.add', k('Mod+K')).status, AssignStatus.conflict);
      // teclado tocando: nota, modificadores e o que não é letra/dígito
      expect(km.check('kbd.octaveUp', k('A')).status, AssignStatus.reserved);
      expect(km.check('kbd.octaveUp', k('Shift+B')).status, AssignStatus.reserved);
      expect(km.check('kbd.octaveUp', k('Space')).status, AssignStatus.reserved);
      expect(km.check('kbd.octaveUp', k('B')).status, AssignStatus.ok);
      expect(km.check('kbd.octaveUp', k('V')).status, AssignStatus.conflict);
      // ação fixa não muda
      expect(km.check('panel.close', k('Q')).status, AssignStatus.notEditable);
      expect(km.assign('panel.close', k('Q')), isFalse);
      expect(km.removeBinding('panel.close', 0), isFalse);
    });

    test('restaurar uma ação cujo padrão outra tomou devolve o padrão e tira da outra', () {
      final km = fresh();
      km.assign('marker.add', k('S'), slot: 0, swap: true); // M ↔ S
      km.reset('edit.split'); // volta o S
      expect(km.bindingsOf('edit.split'), [k('S')]);
      expect(km.bindingsOf('marker.add'), isEmpty);
      // e nunca sobram duas ações com a mesma combinação na mesma camada
      final seen = <String>{};
      for (final a in keyCatalog.where((a) => !a.fixed && a.context != KeyContext.pianoRoll && a.context != KeyContext.playing)) {
        for (final c in km.bindingsOf(a.id)) {
          expect(seen.add('$c'), isTrue, reason: '$c repetida');
        }
      }
    });

    test('a personalização vale no resolver: a tecla nova dispara a ação, a antiga não', () {
      final km = fresh();
      km.assign('panel.mixer', k('B'), slot: 0);
      km.assign('kbd.octaveUp', k('B'), slot: 0);
      expect(km.resolve(k('B'), KeyContext.global).single.id, 'panel.mixer');
      expect(km.resolve(k('X'), KeyContext.global), isEmpty);
      expect(km.playingAction(PhysicalKeyboardKey.keyB)?.id, 'kbd.octaveUp');
      expect(km.playingAction(PhysicalKeyboardKey.keyX), isNull);
      km.assign('pr.quantize', k('Shift+Q'), slot: 0);
      expect(km.resolve(k('Shift+Q'), KeyContext.pianoRoll).single.id, 'pr.quantize');
      expect(km.resolve(k('Q'), KeyContext.pianoRoll), isEmpty);
    });
  });

  group('guardado local e .jokeys', () {
    test('ida e volta pelo guardado local', () async {
      final st = MemoryKeymapStorage();
      final km = Keymap(st);
      km.assign('panel.mixer', k('B'), slot: 0);
      km.assign('edit.delete', k('Shift+Delete'), slot: 0);
      km.removeBinding('transport.stop', 1);
      await km.flush();
      final j = jsonDecode(st.data!) as Map;
      expect(j['format'], 'jopendaw-keymap');
      expect(j['version'], 1);
      expect((j['bindings'] as Map).keys.toSet(), {'panel.mixer', 'edit.delete', 'transport.stop'}, reason: 'só o que difere dos padrões');

      final again = Keymap(st);
      await again.load();
      expect(again.loadNotice, isNull);
      for (final a in keyCatalog) {
        expect(again.bindingsOf(a.id), km.bindingsOf(a.id), reason: a.id);
      }
      // sem nenhuma personalização: nada além do envelope
      again.resetAll();
      await again.flush();
      expect((jsonDecode(st.data!) as Map)['bindings'], isEmpty);
    });

    test('arquivo local ilegível: cópia, padrões, e a próxima gravação vale', () async {
      for (final bad in [
        '{{{',
        '[]',
        '{"format":"outro","version":1,"bindings":{}}',
        '{"format":"jopendaw-keymap","version":"x","bindings":{}}',
        '{"format":"jopendaw-keymap","version":1,"bindings":3}',
      ]) {
        final st = MemoryKeymapStorage()..data = bad;
        final km = Keymap(st);
        await km.load();
        expect(st.backup, bad, reason: bad);
        expect(km.loadNotice, contains('ilegível'));
        expect(km.hasCustom, isFalse);
        km.assign('panel.mixer', k('B'), slot: 0);
        await km.flush();
        expect(jsonDecode(st.data!)['bindings'], {
          'panel.mixer': ['B'],
        });
        expect(st.backup, bad, reason: 'a cópia não é sobrescrita');
      }
    });

    test('versão futura: mostra o que dá para ler e não grava por cima', () async {
      final st = MemoryKeymapStorage()
        ..data = jsonEncode({
          'format': 'jopendaw-keymap',
          'version': 99,
          'bindings': {
            'panel.mixer': ['B'],
            'acao.nova': ['Q'],
          },
          'extra': true,
        });
      final original = st.data;
      final km = Keymap(st);
      await km.load();
      expect(km.loadNotice, contains('mais nova'));
      expect(km.bindingsOf('panel.mixer'), [k('B')]);
      km.assign('panel.effects', k('G'), slot: 0);
      await km.flush();
      expect(st.data, original, reason: 'nada gravado por cima');
      expect(st.backup, isNull);
      expect(km.bindingsOf('panel.effects'), [k('G')], reason: 'vale até fechar o app');
    });

    test('guardado que falha ao ler ou gravar: aviso inline e o app segue', () async {
      final km = Keymap(_Failing(failRead: true));
      await km.load();
      expect(km.problem, isNotNull);
      km.assign('panel.mixer', k('B'), slot: 0);
      await km.flush();
      expect(km.bindingsOf('panel.mixer'), [k('B')]);

      final w = Keymap(_Failing(failWrite: true));
      await w.load();
      w.assign('panel.mixer', k('B'), slot: 0);
      await w.flush();
      expect(w.saveError, contains('valem só até fechar'));
      expect(w.bindingsOf('panel.mixer'), [k('B')]);
    });

    test('.jokeys: exportar e importar em outro Keymap dá os mesmos atalhos', () {
      final a = fresh();
      a.assign('panel.mixer', k('B'), slot: 0);
      a.assign('view.follow', k('G'));
      a.removeBinding('edit.redo', 1);
      a.assign('kbd.octaveUp', k('B'), slot: 0);
      final bytes = a.exportBytes();
      final b = fresh();
      final r = b.importBytes(bytes);
      expect(r.warnings, isEmpty);
      for (final act in keyCatalog) {
        expect(b.bindingsOf(act.id), a.bindingsOf(act.id), reason: act.id);
      }
      expect((jsonDecode(utf8.decode(bytes)) as Map)['format'], 'jopendaw-keymap-file');
    });

    Uint8List file(Object? j) => Uint8List.fromList(utf8.encode(jsonEncode(j)));

    test('.jokeys ruim: recusa o que não é do formato', () {
      final km = fresh();
      km.assign('panel.mixer', k('B'), slot: 0);
      for (final bad in [
        Uint8List.fromList([0xff, 0xfe, 1]),
        Uint8List.fromList(utf8.encode('não é json')),
        file([]),
        file({'format': 'jopendaw-preset', 'version': 1, 'bindings': {}}),
        file({'format': 'jopendaw-keymap-file', 'version': 0, 'bindings': {}}),
        file({'format': 'jopendaw-keymap-file', 'version': '1', 'bindings': {}}),
        file({'format': 'jopendaw-keymap-file', 'version': 1}),
        file({'format': 'jopendaw-keymap-file', 'version': 1, 'bindings': []}),
        Uint8List(maxKeymapFileBytes + 1),
      ]) {
        expect(() => km.importBytes(bad), throwsA(isA<KeymapFormatException>()));
      }
      expect(
        () => km.importBytes(file({'format': 'jopendaw-keymap-file', 'version': 2, 'bindings': {}})),
        throwsA(predicate((e) => '$e'.contains('mais nova'))),
      );
      expect(km.bindingsOf('panel.mixer'), [k('B')], reason: 'nada mudou');
    });

    test('.jokeys com defeitos: ignora ações desconhecidas, descarta teclas inválidas e reservadas, com avisos', () {
      final km = fresh();
      final r = km.importBytes(
        file({
          'format': 'jopendaw-keymap-file',
          'version': 1,
          'bindings': {
            'acao.que.nao.existe': ['Q'],
            'panel.mixer': ['B', 'Tecla Estranha', 3, 'Mod+R', 'B'],
            'panel.close': ['Q'],
            'panel.effects': 'G',
            'view.follow': ['G', 'H', 'J', 'N', 'O'],
            'kbd.octaveUp': ['A', 'Mod+B', 'B'],
          },
        }),
      );
      expect(r.warnings.any((w) => w.contains('acao.que.nao.existe')), isTrue);
      expect(r.warnings.any((w) => w.contains('Tecla Estranha')), isTrue);
      expect(r.warnings.any((w) => w.contains('3')), isTrue);
      expect(r.warnings.any((w) => w.contains('+R')), isTrue);
      expect(r.warnings.any((w) => w.contains('fixa')), isTrue);
      expect(r.warnings.any((w) => w.contains('não são uma lista')), isTrue);
      expect(km.bindingsOf('panel.mixer'), [k('B')]);
      expect(km.bindingsOf('panel.close'), [k('Escape')]);
      expect(km.bindingsOf('panel.effects'), [k('F')]);
      expect(km.bindingsOf('view.follow'), [k('G'), k('H'), k('J')]);
      expect(km.bindingsOf('kbd.octaveUp'), [k('B')]);
    });

    test('.jokeys com conflitos: o importado vence o padrão; entre importados vale o primeiro do catálogo', () {
      final km = fresh();
      final r = km.importBytes(
        file({
          'format': 'jopendaw-keymap-file',
          'version': 1,
          'bindings': {
            'view.follow': ['S'], // S era de "Cortar no cursor", que não está no arquivo
            'transport.metronome': ['B'],
            'panel.mixer': ['B'], // repete o B: fica com quem vem antes no catálogo (metrônomo)
          },
        }),
      );
      expect(km.bindingsOf('view.follow'), [k('S')]);
      expect(km.bindingsOf('edit.split'), isEmpty);
      expect(km.bindingsOf('transport.metronome'), [k('B')]);
      expect(km.bindingsOf('panel.mixer'), isEmpty);
      expect(r.warnings.any((w) => w.contains('perdeu')), isTrue);
      expect(r.warnings.any((w) => w.contains('já é de')), isTrue);
      // nenhuma combinação repetida na mesma camada
      final seen = <String>{};
      for (final a in keyCatalog.where((a) => !a.fixed && (a.context == KeyContext.global || a.context == KeyContext.arrangement))) {
        for (final c in km.bindingsOf(a.id)) {
          expect(seen.add('$c'), isTrue, reason: '$c');
        }
      }
    });

    test('importar substitui as personalizações de antes e grava no guardado local', () async {
      final st = MemoryKeymapStorage();
      final km = Keymap(st);
      km.assign('panel.effects', k('G'), slot: 0);
      km.importBytes(
        file({
          'format': 'jopendaw-keymap-file',
          'version': 1,
          'bindings': {
            'panel.mixer': ['B'],
          },
        }),
      );
      await km.flush();
      expect(km.bindingsOf('panel.effects'), [k('F')]);
      expect(jsonDecode(st.data!)['bindings'], {
        'panel.mixer': ['B'],
      });
    });
  });

  group('janela de atalhos gerada do catálogo', () {
    test('todo atalho de ação aparece com o texto do catálogo; a personalização muda o texto', () {
      final km = fresh();
      String textOf() => shortcutGroups(km).expand((g) => g.$2.map((r) => '${r.$1} | ${r.$2}')).join('\n');
      var t = textOf();
      for (final a in keyCatalog) {
        expect(t, contains(a.helpText), reason: a.id);
        for (final c in a.defaultCombos) {
          expect(t, contains(c.label), reason: '${a.id} ${c.label}');
        }
      }
      km.assign('panel.mixer', k('Mod+B'), slot: 0);
      t = textOf();
      expect(t, contains('${k('Mod+B').label} | Mixer'));
      expect(t, isNot(contains('X | Mixer\n')));
      // seções
      final titles = shortcutGroups(km).map((g) => g.$1).toList();
      expect(titles, containsAll(['Transporte', 'Piano roll', 'Aprender MIDI']));
      expect(titles.any((s) => s.startsWith('Teclado do computador (') && s.contains('liga)')), isTrue);
      expect(titles.last, startsWith('Suspensos'));
    });

    test('os suspensos com o teclado ligado saem do catálogo: cada um é nota ou oitava/velocidade', () {
      final km = fresh();
      final list = suspendedShortcutsOf(km);
      final keys = list.map((e) => e.$1).join(' ');
      for (final letter in ['S', 'E', 'F', 'L', 'C', 'X', 'Z', 'K', 'J', 'H']) {
        expect(RegExp('(^|[^A-Za-z])$letter([^A-Za-z]|\$)').hasMatch(keys), isTrue, reason: letter);
      }
      expect(list.firstWhere((e) => e.$2.startsWith('Metrônomo')).$2, contains('velocidade menor'));
      expect(list.firstWhere((e) => e.$2.startsWith('Mixer')).$2, contains('oitava acima'));
      expect(list.firstWhere((e) => e.$2.startsWith('Cortar no cursor')).$2, contains('vira nota'));
      // R (gravar) não é nota: fica de fora; Mod+ e Espaço também
      expect(list.any((e) => e.$2.startsWith('Gravar')), isFalse);
      expect(list.any((e) => e.$2.startsWith('Desfazer')), isFalse);
      // personalizar muda: gravar em Y (nota) entra na lista; o mixer em B (livre) sai
      km.assign('transport.record', k('Y'), slot: 0);
      km.assign('panel.mixer', k('B'), slot: 0);
      final again = suspendedShortcutsOf(km);
      expect(again.any((e) => e.$2.startsWith('Gravar')), isTrue);
      expect(again.any((e) => e.$2.startsWith('Mixer')), isFalse);
    });
  });

  group('tela de personalização', () {
    Future<Keymap> pump(WidgetTester t, Size size, {Keymap? km, SaveKeymapFile? save, PickKeymapFile? pick}) async {
      km ??= fresh();
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        MaterialApp(
          theme: buildTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: KeymapEditor(keymap: km, save: save, pick: pick),
            ),
          ),
        ),
      );
      await t.pump();
      return km;
    }

    for (final size in [const Size(360, 780), const Size(1512, 900)]) {
      testWidgets('${size.width.toInt()} px: lista, regravar, conflito, restaurar e busca sem overflow', (t) async {
        final km = await pump(t, size);
        expect(t.takeException(), isNull);
        expect(find.text('TRANSPORTE'), findsOneWidget);
        expect(find.text('Metrônomo'), findsOneWidget);
        expect(find.byKey(const ValueKey('bind-transport.metronome-0')), findsOneWidget);

        // regravar: clica, mostra o aviso, aperta uma tecla
        await t.ensureVisible(find.byKey(const ValueKey('bind-transport.metronome-0')));
        await t.tap(find.byKey(const ValueKey('bind-transport.metronome-0')));
        await t.pump();
        expect(find.text('Pressione a nova combinação…'), findsOneWidget);
        expect(t.takeException(), isNull);
        await t.sendKeyEvent(LogicalKeyboardKey.keyB);
        await t.pump();
        expect(km.bindingsOf('transport.metronome'), [k('B')]);
        expect(find.text('Pressione a nova combinação…'), findsNothing);
        expect(find.byKey(const ValueKey('reset-transport.metronome')), findsOneWidget);

        // reservada: mostra o motivo e continua gravando
        await t.tap(find.byKey(const ValueKey('bind-transport.metronome-0')));
        await t.pump();
        await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await t.sendKeyEvent(LogicalKeyboardKey.keyR);
        await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await t.pump();
        expect(find.byKey(const ValueKey('refusal-transport.metronome')), findsOneWidget);
        expect(km.bindingsOf('transport.metronome'), [k('B')]);
        // modificador sozinho não conta; Esc cancela sem mudar
        await t.sendKeyEvent(LogicalKeyboardKey.shiftLeft);
        await t.sendKeyEvent(LogicalKeyboardKey.escape);
        await t.pump();
        expect(find.text('Pressione a nova combinação…'), findsNothing);
        expect(km.bindingsOf('transport.metronome'), [k('B')]);

        // conflito: S é de "Cortar no cursor"
        await t.tap(find.byKey(const ValueKey('bind-transport.metronome-0')));
        await t.pump();
        await t.sendKeyEvent(LogicalKeyboardKey.keyS);
        await t.pump();
        expect(find.byKey(const ValueKey('conflict-transport.metronome')), findsOneWidget);
        expect(find.textContaining('já é de "Cortar no cursor"'), findsOneWidget);
        expect(km.bindingsOf('transport.metronome'), [k('B')]);
        expect(t.takeException(), isNull);
        await t.tap(find.byKey(const ValueKey('conflict-cancel')));
        await t.pump();
        expect(find.byKey(const ValueKey('conflict-transport.metronome')), findsNothing);
        expect(km.bindingsOf('edit.split'), [k('S')]);
        await t.tap(find.byKey(const ValueKey('bind-transport.metronome-0')));
        await t.pump();
        await t.sendKeyEvent(LogicalKeyboardKey.keyS);
        await t.pump();
        await t.tap(find.byKey(const ValueKey('conflict-swap')));
        await t.pump();
        expect(km.bindingsOf('transport.metronome'), [k('S')]);
        expect(km.bindingsOf('edit.split'), [k('B')]);

        // Backspace remove; o atalho da ação vira "Sem atalho"
        await t.tap(find.byKey(const ValueKey('bind-transport.metronome-0')));
        await t.pump();
        await t.sendKeyEvent(LogicalKeyboardKey.backspace);
        await t.pump();
        expect(km.bindingsOf('transport.metronome'), isEmpty);
        expect(find.text('Sem atalho'), findsWidgets);

        // restaurar a ação
        await t.tap(find.byKey(const ValueKey('reset-transport.metronome')));
        await t.pump();
        expect(km.bindingsOf('transport.metronome'), [k('C')]);
        expect(km.bindingsOf('edit.split'), [k('B')], reason: 'a troca deu o B à outra ação; restaurar uma não mexe na outra');
        km.reset('edit.split');
        expect(km.bindingsOf('edit.split'), [k('S')]);
        await t.pump();

        // acrescentar um segundo atalho
        await t.tap(find.byKey(const ValueKey('add-transport.metronome')));
        await t.pump();
        await t.sendKeyEvent(LogicalKeyboardKey.keyB);
        await t.pump();
        expect(km.bindingsOf('transport.metronome'), [k('C'), k('B')]);

        // busca por nome (sem acento), por categoria e por tecla; sem resultado
        await t.enterText(find.byKey(const ValueKey('keymap-search')), 'metronomo');
        await t.pump();
        expect(find.text('Metrônomo'), findsOneWidget);
        expect(find.text('Mixer'), findsNothing);
        await t.enterText(find.byKey(const ValueKey('keymap-search')), 'piano roll');
        await t.pump();
        expect(find.text('Quantizar'), findsOneWidget);
        expect(find.text('Mixer'), findsNothing);
        await t.enterText(find.byKey(const ValueKey('keymap-search')), 'zzzz');
        await t.pump();
        expect(find.byKey(const ValueKey('keymap-empty')), findsOneWidget);
        await t.enterText(find.byKey(const ValueKey('keymap-search')), '');
        await t.pump();

        // restaurar tudo, com confirmação
        await t.ensureVisible(find.byKey(const ValueKey('keymap-reset-all')));
        await t.tap(find.byKey(const ValueKey('keymap-reset-all')));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const ValueKey('keymap-reset-all-confirm')));
        await t.pumpAndSettle();
        expect(km.hasCustom, isFalse);
        expect(t.takeException(), isNull);
      });

      testWidgets('${size.width.toInt()} px: todas as categorias com atalho longo e a ação fixa (Esc) sem overflow', (t) async {
        final km = fresh();
        km.assign('view.follow', k('Mod+Shift+Alt+F2'));
        km.assign('view.zoomIn', k('Mod+Shift+Alt+F3'), slot: 0);
        await pump(t, size, km: km);
        await t.pump();
        expect(t.takeException(), isNull);
        // a ação fixa não é regravável
        expect(find.byKey(const ValueKey('bind-panel.close-0')), findsNothing);
        expect(find.byIcon(Icons.lock_outline), findsWidgets);
        // desce a lista inteira: cada linha monta sem erro
        for (final a in keyCatalog) {
          final f = find.text(a.label);
          expect(f, findsWidgets, reason: a.id);
        }
      });
    }

    testWidgets('teclado tocando: grava pela tecla física e recusa tecla de nota', (t) async {
      final km = await pump(t, const Size(1512, 900));
      await t.ensureVisible(find.byKey(const ValueKey('bind-kbd.octaveUp-0')));
      await t.tap(find.byKey(const ValueKey('bind-kbd.octaveUp-0')));
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.keyA, physicalKey: PhysicalKeyboardKey.keyA);
      await t.pump();
      expect(find.byKey(const ValueKey('refusal-kbd.octaveUp')), findsOneWidget);
      expect(km.bindingsOf('kbd.octaveUp'), [k('X')]);
      await t.sendKeyEvent(LogicalKeyboardKey.keyB, physicalKey: PhysicalKeyboardKey.keyB);
      await t.pump();
      expect(km.bindingsOf('kbd.octaveUp'), [k('B')]);
      expect(km.playingAction(PhysicalKeyboardKey.keyB)?.id, 'kbd.octaveUp');
    });

    testWidgets('exportar entrega o .jokeys; cancelar avisa; importar aplica e mostra os avisos; arquivo ruim é recusado', (t) async {
      String? savedName;
      Uint8List? savedBytes;
      var saveResult = true;
      Uint8List? next;
      final km = await pump(
        t,
        const Size(1512, 900),
        save: (name, bytes, mime) async {
          savedName = name;
          savedBytes = bytes;
          return saveResult;
        },
        pick: () async => next == null ? null : ('meus.jokeys', next),
      );
      km.assign('panel.mixer', k('B'), slot: 0);
      await t.ensureVisible(find.byKey(const ValueKey('keymap-export')));
      await t.tap(find.byKey(const ValueKey('keymap-export')));
      await t.pump();
      expect(savedName, 'atalhos.jokeys');
      expect(jsonDecode(utf8.decode(savedBytes!))['bindings'], {
        'panel.mixer': ['B'],
      });
      expect(find.textContaining('exportados'), findsOneWidget);
      saveResult = false;
      await t.tap(find.byKey(const ValueKey('keymap-export')));
      await t.pump();
      expect(find.textContaining('cancelada'), findsOneWidget);

      // importar arquivo ruim
      next = Uint8List.fromList(utf8.encode('lixo'));
      await t.tap(find.byKey(const ValueKey('keymap-import')));
      await t.pump();
      expect(find.textContaining('Não foi possível importar'), findsOneWidget);
      expect(km.bindingsOf('panel.mixer'), [k('B')]);

      // importar arquivo com defeitos: aplica o que presta e lista os avisos
      next = Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'format': 'jopendaw-keymap-file',
            'version': 1,
            'bindings': {
              'panel.effects': ['G'],
              'nada': ['Q'],
            },
          }),
        ),
      );
      await t.tap(find.byKey(const ValueKey('keymap-import')));
      await t.pump();
      expect(km.bindingsOf('panel.effects'), [k('G')]);
      expect(km.bindingsOf('panel.mixer'), [k('X')]);
      expect(find.textContaining('com avisos'), findsOneWidget);
      expect(find.textContaining('nada'), findsWidgets);
      expect(t.takeException(), isNull);
    });
  });

  group('janela de atalhos', () {
    Future<void> open(WidgetTester t, Size size, {required bool canCustomize, Keymap? km}) async {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        MaterialApp(
          theme: buildTheme(),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showShortcuts(context, canCustomize: canCustomize, keymap: km ?? fresh()),
              child: const Text('abrir'),
            ),
          ),
        ),
      );
      await t.tap(find.text('abrir'));
      await t.pumpAndSettle();
    }

    for (final size in [const Size(360, 780), const Size(1512, 900)]) {
      testWidgets('${size.width.toInt()} px: lista gerada, Personalizar troca para a tela e volta', (t) async {
        final km = fresh();
        await open(t, size, canCustomize: true, km: km);
        expect(t.takeException(), isNull);
        expect(find.text('Atalhos do teclado'), findsOneWidget);
        expect(find.text('Tocar / pausar'), findsOneWidget);
        await t.tap(find.byKey(const ValueKey('shortcuts-customize')));
        await t.pumpAndSettle();
        expect(find.text('Personalizar atalhos'), findsOneWidget);
        expect(find.byKey(const ValueKey('keymap-search')), findsOneWidget);
        expect(t.takeException(), isNull);
        // regrava dentro da janela e a lista reflete
        await t.ensureVisible(find.byKey(const ValueKey('bind-panel.mixer-0')));
        await t.tap(find.byKey(const ValueKey('bind-panel.mixer-0')));
        await t.pump();
        await t.sendKeyEvent(LogicalKeyboardKey.keyB);
        await t.pump();
        expect(km.bindingsOf('panel.mixer'), [k('B')]);
        await t.tap(find.byKey(const ValueKey('shortcuts-customize')));
        await t.pumpAndSettle();
        expect(find.text('Atalhos do teclado'), findsOneWidget);
        expect(find.text('B'), findsWidgets);
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('celular sem teclado físico: só leitura, sem o botão Personalizar', (t) async {
      await open(t, const Size(360, 780), canCustomize: false);
      expect(find.text('Tocar / pausar'), findsOneWidget);
      expect(find.byKey(const ValueKey('shortcuts-customize')), findsNothing);
      expect(t.takeException(), isNull);
    });

    test('canCustomizeShortcuts: web e computador sim; Android e iOS nativos não', () {
      if (kIsWeb) return;
      for (final p in [TargetPlatform.android, TargetPlatform.iOS]) {
        debugDefaultTargetPlatformOverride = p;
        expect(canCustomizeShortcuts, isFalse, reason: '$p');
      }
      for (final p in [TargetPlatform.macOS, TargetPlatform.windows, TargetPlatform.linux]) {
        debugDefaultTargetPlatformOverride = p;
        expect(canCustomizeShortcuts, isTrue, reason: '$p');
      }
      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('na tela do projeto', () {
    testWidgets('a tecla personalizada dispara a ação e a padrão deixa de disparar; Esc e a gravação continuam', (t) async {
      final saved = Keymap.instance;
      Keymap.instance = fresh();
      addTearDown(() => Keymap.instance = saved);
      final c = studio();
      await mount(t, c, const Size(1400, 900));
      expect(c.doc.metronome, isFalse);
      Keymap.instance.assign('transport.metronome', k('B'), slot: 0);
      await t.sendKeyEvent(LogicalKeyboardKey.keyC);
      expect(c.doc.metronome, isFalse, reason: 'o C deixou de ser metrônomo');
      await t.sendKeyEvent(LogicalKeyboardKey.keyB);
      expect(c.doc.metronome, isTrue);

      // o painel: X deixa de abrir o mixer; o Mixer vai para Shift+B... aqui, Ctrl+B
      Keymap.instance.assign('panel.mixer', k('Mod+B'), slot: 0);
      await t.sendKeyEvent(LogicalKeyboardKey.keyX);
      await t.pump();
      expect(c.dock.name, 'none');
      await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await t.sendKeyEvent(LogicalKeyboardKey.keyB);
      await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await t.pump();
      expect(c.dock.name, 'mixer');
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pump();
      expect(c.dock.name, 'none');

      // teclado tocando: a oitava acima passa a ser B (por posição) e o X vira nada
      Keymap.instance.assign('kbd.octaveUp', k('N'), slot: 0);
      c.selectTrack(1);
      await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await t.sendKeyEvent(LogicalKeyboardKey.keyK);
      await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(c.keyboardOn, isTrue);
      final oct = c.keyboardOctave;
      await t.sendKeyEvent(LogicalKeyboardKey.keyX, physicalKey: PhysicalKeyboardKey.keyX);
      expect(c.keyboardOctave, oct, reason: 'X deixou de ser oitava acima');
      await t.sendKeyEvent(LogicalKeyboardKey.keyN, physicalKey: PhysicalKeyboardKey.keyN);
      expect(c.keyboardOctave, oct + 1);
      await flushSave(t);
    });
  });
}

class _Failing implements KeymapStorage {
  final bool failRead, failWrite;
  _Failing({this.failRead = false, this.failWrite = false});
  @override
  Future<String?> read() async => failRead ? throw StateError('sem leitura') : null;
  @override
  Future<void> write(String json) async => failWrite ? throw StateError('sem gravação') : null;
  @override
  Future<void> writeBackup(String raw) async {}
  @override
  Future<String?> readBackup() async => null;
}
