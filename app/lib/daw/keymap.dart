/// Atalhos de teclado personalizáveis: o catálogo único das ações do estúdio (id estável, rótulo, categoria,
/// contexto e atalhos padrão) e o [Keymap], que resolve (tecla + modificadores + contexto) → ação com as
/// personalizações da pessoa por cima dos padrões.
///
/// O que a pessoa muda fica no `LocalStore` do aparelho (chave `keymap`, JSON com versão, só as diferenças dos
/// padrões) e viaja num arquivo `.jokeys`. Arquivo local ilegível ganha uma cópia (`keymap.bak`) e a lista volta
/// aos padrões; de versão mais nova, fica só para leitura: nada é gravado por cima (o mesmo cuidado dos presets).
///
/// Uma tecla é um "token" de texto estável (`Z`, `Space`, `[`, `Up`, `F2`), não o `keyId` do Flutter: o arquivo
/// não depende da plataforma e é legível. Sem bit a bit: roda igual no dart2js.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../audio/engine.dart' show LocalStore;
import '../widgets/format.dart';

/// Onde a ação vale. Geral e arranjo são a mesma camada de teclas (a tela do projeto); o piano roll tem a
/// dele, que vem antes quando está ativo; o teclado tocando (notas) vem antes de tudo e tem teclas por posição.
enum KeyContext {
  global('Geral'),
  arrangement('Arranjo'),
  pianoRoll('Piano roll'),
  playing('Teclado tocando');

  final String label;
  const KeyContext(this.label);
}

enum KeyCategory {
  transport('Transporte'),
  markers('Marcadores e loop'),
  view('Visão'),
  edit('Edição'),
  panels('Painéis'),
  midiLearn('Aprender MIDI'),
  keyboard('Teclado do computador'),
  pianoRoll('Piano roll');

  final String title;
  const KeyCategory(this.title);
}

/// Uma ação nomeada do estúdio.
class KeyAction {
  /// Estável: vai para o arquivo. Nunca renomear; ação nova ganha id novo.
  final String id;
  final String label;

  /// Texto mais longo da janela de atalhos (o [label] se não houver).
  final String? help;
  final KeyCategory category;
  final KeyContext context;

  /// Atalhos padrão, no formato de [KeyCombo.parse].
  final List<String> defaults;

  /// Fixa (Esc): aparece, mas não se muda nem se conflita com ela.
  final bool fixed;

  /// Com o Shift a mais a tecla não vale (K sozinho divide, Shift+K é outra coisa). As outras ações ignoram o
  /// Shift e o Alt que sobrarem quando nenhuma combinação exata casa (ver [Keymap.resolve]).
  final bool exactShift;
  KeyAction(this.id, this.label, this.category, this.context, this.defaults, {this.help, this.fixed = false, this.exactShift = false});

  late final List<KeyCombo> defaultCombos = [for (final d in defaults) KeyCombo.parse(d)!];

  String get helpText => help ?? label;
}

/// O catálogo. A ordem é a da janela de atalhos e desempata conflitos na importação.
final List<KeyAction> keyCatalog = [
  KeyAction('transport.play', 'Tocar / pausar', KeyCategory.transport, KeyContext.global, ['Space']),
  KeyAction('transport.stop', 'Parar', KeyCategory.transport, KeyContext.global, ['Enter', 'Home'], help: 'Parar e voltar ao começo (ou ao início do loop)'),
  KeyAction('transport.record', 'Gravar', KeyCategory.transport, KeyContext.global, ['R'], help: 'Gravar (com faixas armadas)'),
  KeyAction('transport.loop', 'Loop liga/desliga', KeyCategory.transport, KeyContext.global, [
    'L',
  ], help: 'Loop liga/desliga (arraste na régua para marcar a região)'),
  KeyAction('transport.metronome', 'Metrônomo', KeyCategory.transport, KeyContext.global, ['C']),
  KeyAction('transport.punch', 'Punch liga/desliga', KeyCategory.transport, KeyContext.global, [
    'P',
  ], help: 'Punch liga/desliga: com ele, a gravação só vale na região marcada na régua'),
  KeyAction('transport.tap', 'Tap tempo', KeyCategory.transport, KeyContext.global, [
    'T',
  ], help: 'Tap tempo: bata no ritmo; o andamento vale quando você para de bater'),
  KeyAction('marker.add', 'Marcador no cursor', KeyCategory.markers, KeyContext.global, ['M']),
  KeyAction('marker.rename', 'Marcador no cursor, pedindo o nome', KeyCategory.markers, KeyContext.global, ['Shift+M']),
  KeyAction('marker.prev', 'Cursor no marcador anterior', KeyCategory.markers, KeyContext.global, ['[']),
  KeyAction('marker.next', 'Cursor no marcador seguinte', KeyCategory.markers, KeyContext.global, [']']),
  KeyAction('loop.clip', 'Loop no clipe selecionado', KeyCategory.markers, KeyContext.arrangement, [
    'Shift+L',
  ], help: 'Loop no clipe selecionado (ou na seção do cursor)'),
  KeyAction('view.fitAll', 'Enquadrar o projeto inteiro', KeyCategory.view, KeyContext.global, ['Z']),
  KeyAction('view.fitClip', 'Enquadrar o clipe selecionado', KeyCategory.view, KeyContext.arrangement, ['Shift+Z']),
  KeyAction('view.zoomIn', 'Aproximar', KeyCategory.view, KeyContext.global, ['+', '=']),
  KeyAction('view.zoomOut', 'Afastar', KeyCategory.view, KeyContext.global, ['-']),
  KeyAction('view.follow', 'Seguir o cursor', KeyCategory.view, KeyContext.global, []),
  KeyAction('edit.undo', 'Desfazer', KeyCategory.edit, KeyContext.global, ['Mod+Z']),
  KeyAction('edit.redo', 'Refazer', KeyCategory.edit, KeyContext.global, ['Mod+Shift+Z', 'Mod+Y']),
  KeyAction('edit.duplicate', 'Duplicar o clipe', KeyCategory.edit, KeyContext.arrangement, ['Mod+D']),
  KeyAction('edit.split', 'Cortar no cursor', KeyCategory.edit, KeyContext.arrangement, ['S']),
  KeyAction('edit.delete', 'Apagar o clipe', KeyCategory.edit, KeyContext.arrangement, ['Delete', 'Backspace']),
  KeyAction('edit.import', 'Importar áudio ou MIDI', KeyCategory.edit, KeyContext.global, ['Mod+I']),
  KeyAction('panel.mixer', 'Mixer', KeyCategory.panels, KeyContext.global, ['X']),
  KeyAction('panel.editor', 'Editor de notas (piano roll)', KeyCategory.panels, KeyContext.global, ['E']),
  KeyAction('panel.instrument', 'Instrumento da faixa', KeyCategory.panels, KeyContext.global, ['I']),
  KeyAction('panel.effects', 'Efeitos da faixa', KeyCategory.panels, KeyContext.global, ['F']),
  // antes do panel.close: com o modo ligado e um painel aberto, o Esc cancela primeiro o controle armado
  KeyAction(
    'midilearn.cancel',
    'Cancelar o controle armado',
    KeyCategory.midiLearn,
    KeyContext.global,
    ['Escape'],
    fixed: true,
    help: 'Cancela o controle armado; de novo, sai do modo',
  ),
  KeyAction('panel.close', 'Fechar o painel', KeyCategory.panels, KeyContext.global, ['Escape'], fixed: true),
  KeyAction('help.shortcuts', 'Janela de atalhos', KeyCategory.panels, KeyContext.global, ['?'], help: 'Esta janela'),
  KeyAction('midilearn.toggle', 'Aprender MIDI liga/desliga', KeyCategory.midiLearn, KeyContext.global, [
    'Shift+K',
  ], help: 'Liga o modo: os controles ganham contorno; clique num e mexa no botão do teclado'),
  KeyAction('kbd.toggle', 'Teclado do computador liga/desliga', KeyCategory.keyboard, KeyContext.global, ['Mod+K']),
  KeyAction('kbd.octaveDown', 'Oitava abaixo', KeyCategory.keyboard, KeyContext.playing, [
    'Z',
  ], help: 'Oitava abaixo (só da faixa que está tocando: a bateria começa no C2)'),
  KeyAction('kbd.octaveUp', 'Oitava acima', KeyCategory.keyboard, KeyContext.playing, ['X']),
  KeyAction('kbd.velocityDown', 'Velocidade menor', KeyCategory.keyboard, KeyContext.playing, ['C']),
  KeyAction('kbd.velocityUp', 'Velocidade maior', KeyCategory.keyboard, KeyContext.playing, ['V']),
  KeyAction('pr.selectAll', 'Selecionar tudo', KeyCategory.pianoRoll, KeyContext.pianoRoll, ['Mod+A']),
  KeyAction('pr.copy', 'Copiar', KeyCategory.pianoRoll, KeyContext.pianoRoll, ['Mod+C']),
  KeyAction('pr.cut', 'Recortar', KeyCategory.pianoRoll, KeyContext.pianoRoll, ['Mod+X']),
  KeyAction('pr.paste', 'Colar no cursor', KeyCategory.pianoRoll, KeyContext.pianoRoll, ['Mod+V']),
  KeyAction('pr.duplicate', 'Duplicar as notas', KeyCategory.pianoRoll, KeyContext.pianoRoll, ['Mod+D']),
  KeyAction('pr.delete', 'Apagar as notas', KeyCategory.pianoRoll, KeyContext.pianoRoll, ['Delete', 'Backspace']),
  KeyAction('pr.deselect', 'Limpar a seleção', KeyCategory.pianoRoll, KeyContext.pianoRoll, ['Escape'], fixed: true),
  KeyAction('pr.quantize', 'Quantizar', KeyCategory.pianoRoll, KeyContext.pianoRoll, ['Q'], exactShift: true),
  KeyAction(
    'pr.split',
    'Dividir as notas no cursor',
    KeyCategory.pianoRoll,
    KeyContext.pianoRoll,
    ['K'],
    exactShift: true,
    help: 'Dividir as notas no cursor (a seleção, ou todas)',
  ),
  KeyAction('pr.join', 'Unir notas iguais adjacentes', KeyCategory.pianoRoll, KeyContext.pianoRoll, ['J'], exactShift: true),
  KeyAction('pr.humanize', 'Humanizar', KeyCategory.pianoRoll, KeyContext.pianoRoll, ['Shift+H'], help: 'Humanizar com os últimos ajustes'),
  KeyAction('pr.legato', 'Legato', KeyCategory.pianoRoll, KeyContext.pianoRoll, ['Shift+L'], help: 'Legato: cada nota vai até a próxima'),
  KeyAction('pr.up', 'Transpor um semitom acima', KeyCategory.pianoRoll, KeyContext.pianoRoll, ['Up']),
  KeyAction('pr.down', 'Transpor um semitom abaixo', KeyCategory.pianoRoll, KeyContext.pianoRoll, ['Down']),
  KeyAction('pr.octaveUp', 'Transpor uma oitava acima', KeyCategory.pianoRoll, KeyContext.pianoRoll, ['Shift+Up']),
  KeyAction('pr.octaveDown', 'Transpor uma oitava abaixo', KeyCategory.pianoRoll, KeyContext.pianoRoll, ['Shift+Down']),
  KeyAction('pr.left', 'Mover para a esquerda (grade)', KeyCategory.pianoRoll, KeyContext.pianoRoll, ['Left']),
  KeyAction('pr.right', 'Mover para a direita (grade)', KeyCategory.pianoRoll, KeyContext.pianoRoll, ['Right']),
  KeyAction('pr.barLeft', 'Mover um compasso para a esquerda', KeyCategory.pianoRoll, KeyContext.pianoRoll, ['Shift+Left']),
  KeyAction('pr.barRight', 'Mover um compasso para a direita', KeyCategory.pianoRoll, KeyContext.pianoRoll, ['Shift+Right']),
];

final Map<String, KeyAction> _byId = {for (final a in keyCatalog) a.id: a};

/// A ação pelo id, ou null.
KeyAction? keyActionById(String id) => _byId[id];

// ------------------------------------------------------------------------------- teclas

final List<LogicalKeyboardKey> _letterKeys = [
  LogicalKeyboardKey.keyA, LogicalKeyboardKey.keyB, LogicalKeyboardKey.keyC, LogicalKeyboardKey.keyD, LogicalKeyboardKey.keyE, //
  LogicalKeyboardKey.keyF, LogicalKeyboardKey.keyG, LogicalKeyboardKey.keyH, LogicalKeyboardKey.keyI, LogicalKeyboardKey.keyJ,
  LogicalKeyboardKey.keyK, LogicalKeyboardKey.keyL, LogicalKeyboardKey.keyM, LogicalKeyboardKey.keyN, LogicalKeyboardKey.keyO,
  LogicalKeyboardKey.keyP, LogicalKeyboardKey.keyQ, LogicalKeyboardKey.keyR, LogicalKeyboardKey.keyS, LogicalKeyboardKey.keyT,
  LogicalKeyboardKey.keyU, LogicalKeyboardKey.keyV, LogicalKeyboardKey.keyW, LogicalKeyboardKey.keyX, LogicalKeyboardKey.keyY,
  LogicalKeyboardKey.keyZ,
];
final List<LogicalKeyboardKey> _digitKeys = [
  LogicalKeyboardKey.digit0, LogicalKeyboardKey.digit1, LogicalKeyboardKey.digit2, LogicalKeyboardKey.digit3, LogicalKeyboardKey.digit4, //
  LogicalKeyboardKey.digit5, LogicalKeyboardKey.digit6, LogicalKeyboardKey.digit7, LogicalKeyboardKey.digit8, LogicalKeyboardKey.digit9,
];
final List<PhysicalKeyboardKey> _physicalLetters = [
  PhysicalKeyboardKey.keyA, PhysicalKeyboardKey.keyB, PhysicalKeyboardKey.keyC, PhysicalKeyboardKey.keyD, PhysicalKeyboardKey.keyE, //
  PhysicalKeyboardKey.keyF, PhysicalKeyboardKey.keyG, PhysicalKeyboardKey.keyH, PhysicalKeyboardKey.keyI, PhysicalKeyboardKey.keyJ,
  PhysicalKeyboardKey.keyK, PhysicalKeyboardKey.keyL, PhysicalKeyboardKey.keyM, PhysicalKeyboardKey.keyN, PhysicalKeyboardKey.keyO,
  PhysicalKeyboardKey.keyP, PhysicalKeyboardKey.keyQ, PhysicalKeyboardKey.keyR, PhysicalKeyboardKey.keyS, PhysicalKeyboardKey.keyT,
  PhysicalKeyboardKey.keyU, PhysicalKeyboardKey.keyV, PhysicalKeyboardKey.keyW, PhysicalKeyboardKey.keyX, PhysicalKeyboardKey.keyY,
  PhysicalKeyboardKey.keyZ,
];
final List<PhysicalKeyboardKey> _physicalDigits = [
  PhysicalKeyboardKey.digit0, PhysicalKeyboardKey.digit1, PhysicalKeyboardKey.digit2, PhysicalKeyboardKey.digit3, PhysicalKeyboardKey.digit4, //
  PhysicalKeyboardKey.digit5, PhysicalKeyboardKey.digit6, PhysicalKeyboardKey.digit7, PhysicalKeyboardKey.digit8, PhysicalKeyboardKey.digit9,
];

/// Tecla lógica → token.
final Map<LogicalKeyboardKey, String> _logicalToToken = {
  for (var i = 0; i < 26; i++) _letterKeys[i]: String.fromCharCode(0x41 + i),
  for (var i = 0; i < 10; i++) _digitKeys[i]: '$i',
  LogicalKeyboardKey.space: 'Space',
  LogicalKeyboardKey.enter: 'Enter',
  LogicalKeyboardKey.home: 'Home',
  LogicalKeyboardKey.end: 'End',
  LogicalKeyboardKey.pageUp: 'PageUp',
  LogicalKeyboardKey.pageDown: 'PageDown',
  LogicalKeyboardKey.delete: 'Delete',
  LogicalKeyboardKey.backspace: 'Backspace',
  LogicalKeyboardKey.escape: 'Escape',
  LogicalKeyboardKey.tab: 'Tab',
  LogicalKeyboardKey.arrowUp: 'Up',
  LogicalKeyboardKey.arrowDown: 'Down',
  LogicalKeyboardKey.arrowLeft: 'Left',
  LogicalKeyboardKey.arrowRight: 'Right',
  LogicalKeyboardKey.f1: 'F1',
  LogicalKeyboardKey.f2: 'F2',
  LogicalKeyboardKey.f3: 'F3',
  LogicalKeyboardKey.f4: 'F4',
  LogicalKeyboardKey.f5: 'F5',
  LogicalKeyboardKey.f6: 'F6',
  LogicalKeyboardKey.f7: 'F7',
  LogicalKeyboardKey.f8: 'F8',
  LogicalKeyboardKey.f9: 'F9',
  LogicalKeyboardKey.f10: 'F10',
  LogicalKeyboardKey.f11: 'F11',
  LogicalKeyboardKey.f12: 'F12',
  LogicalKeyboardKey.bracketLeft: '[',
  LogicalKeyboardKey.bracketRight: ']',
  LogicalKeyboardKey.equal: '=',
  LogicalKeyboardKey.minus: '-',
  LogicalKeyboardKey.numpadSubtract: '-',
  LogicalKeyboardKey.add: '+',
  LogicalKeyboardKey.numpadAdd: '+',
  LogicalKeyboardKey.question: '?',
  LogicalKeyboardKey.slash: '/',
  LogicalKeyboardKey.comma: ',',
  LogicalKeyboardKey.period: '.',
  LogicalKeyboardKey.semicolon: ';',
  LogicalKeyboardKey.quote: "'",
  LogicalKeyboardKey.backslash: r'\',
  LogicalKeyboardKey.backquote: '`',
};

/// Todo token válido.
final Set<String> keyTokens = {..._logicalToToken.values};

/// Teclas físicas do teclado tocando (letras e dígitos), por token. O teclado de notas é por posição, não
/// pelo layout; as ações dele ficam presas a estas.
final Map<PhysicalKeyboardKey, String> _physicalToToken = {
  for (var i = 0; i < 26; i++) _physicalLetters[i]: String.fromCharCode(0x41 + i),
  for (var i = 0; i < 10; i++) _physicalDigits[i]: '$i',
};

/// O token de uma tecla física do teclado tocando, ou null se ela não serve para ações dele.
String? physicalKeyToken(PhysicalKeyboardKey k) => _physicalToToken[k];

/// Tokens que não pedem o Shift (o caractere já o traz: `?`, `+`).
const _shiftFree = {'?', '+'};

/// Teclas que valiam com qualquer modificador antes da personalização (Ctrl+Espaço também toca, Ctrl+Delete
/// também apaga, Ctrl+= também aproxima): se nada casa exato, a versão sem Ctrl/Cmd casa.
const _modifierAgnostic = {'Space', 'Enter', 'Home', 'Delete', 'Backspace', 'Escape', '=', '+', '-', '?'};

/// Teclas de modificador sozinhas: não formam atalho.
bool isModifierKey(LogicalKeyboardKey k) => _modifierKeys.contains(k);

final Set<LogicalKeyboardKey> _modifierKeys = {
  LogicalKeyboardKey.shift, LogicalKeyboardKey.shiftLeft, LogicalKeyboardKey.shiftRight, LogicalKeyboardKey.control, //
  LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.controlRight, LogicalKeyboardKey.alt, LogicalKeyboardKey.altLeft,
  LogicalKeyboardKey.altRight, LogicalKeyboardKey.meta, LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.metaRight,
  LogicalKeyboardKey.capsLock, LogicalKeyboardKey.altGraph, LogicalKeyboardKey.fn,
};

/// Uma tecla com modificadores. [mod] é Ctrl ou Cmd (valem os dois, em qualquer sistema).
@immutable
class KeyCombo {
  final String token;
  final bool mod, shift, alt;
  const KeyCombo(this.token, {this.mod = false, this.shift = false, this.alt = false});

  /// O que o teclado mandou: normaliza o Shift dos tokens que o caractere já traz (`?`, `+`) e vê `Shift+/` como `?`.
  /// Null se a tecla não é uma que o app conhece.
  static KeyCombo? fromKey(LogicalKeyboardKey key, {String? character, bool mod = false, bool shift = false, bool alt = false}) {
    String? token;
    if (character == '?' || character == '+' || character == '-') {
      token = character;
    } else {
      token = _logicalToToken[key];
      if (token == '/' && shift) token = '?';
    }
    if (token == null) return null;
    return KeyCombo(token, mod: mod, shift: shift && !_shiftFree.contains(token), alt: alt);
  }

  /// `Mod+Shift+Z`, `Space`, `+`, `Alt+F2`; null se não é um atalho válido. Sem nada de "só modificador".
  static KeyCombo? parse(Object? s) {
    if (s is! String) return null;
    var rest = s.trim();
    var mod = false, shift = false, alt = false;
    while (true) {
      if (rest.startsWith('Mod+') && rest.length > 4 && !mod) {
        mod = true;
        rest = rest.substring(4);
      } else if (rest.startsWith('Shift+') && rest.length > 6 && !shift) {
        shift = true;
        rest = rest.substring(6);
      } else if (rest.startsWith('Alt+') && rest.length > 4 && !alt) {
        alt = true;
        rest = rest.substring(4);
      } else {
        break;
      }
    }
    if (!keyTokens.contains(rest)) return null;
    if (shift && _shiftFree.contains(rest)) return null;
    return KeyCombo(rest, mod: mod, shift: shift, alt: alt);
  }

  bool get hasModifier => mod || shift || alt;

  /// Como vai para o arquivo (aceito por [parse]).
  @override
  String toString() => '${mod ? 'Mod+' : ''}${shift ? 'Shift+' : ''}${alt ? 'Alt+' : ''}$token';

  /// Como aparece na tela: Ctrl ou ⌘ conforme o sistema.
  String get label => '${mod ? '$modKey+' : ''}${shift ? 'Shift+' : ''}${alt ? 'Alt+' : ''}${tokenLabel(token)}';

  @override
  bool operator ==(Object other) => other is KeyCombo && other.token == token && other.mod == mod && other.shift == shift && other.alt == alt;

  @override
  int get hashCode => Object.hash(token, mod, shift, alt);
}

/// O nome de um token na tela.
String tokenLabel(String token) => switch (token) {
  'Space' => 'Espaço',
  'Escape' => 'Esc',
  'Up' => '↑',
  'Down' => '↓',
  'Left' => '←',
  'Right' => '→',
  '-' => '−',
  _ => token,
};

// ------------------------------------------------------------------------------- regras

/// Por que o atalho não pode ser atribuído a uma ação de [context], ou null se pode. Reservados: Esc; as teclas
/// do navegador e do sistema que o app não consegue capturar (recarregar, fechar, abas, tela cheia, ferramentas);
/// no teclado tocando, as teclas de nota e qualquer modificador.
String? reservedReason(KeyCombo c, KeyContext context) {
  if (c.token == 'Escape') return 'Esc é reservado: cancela e fecha painéis.';
  if (c.token == 'Tab') return 'Tab é reservado para a navegação por foco.';
  if (c.token == 'F5' || c.token == 'F11' || c.token == 'F12') {
    return '${c.token} é do navegador (recarregar, tela cheia, ferramentas) e o app não consegue capturá-la.';
  }
  if (c.alt && c.token == 'F4') return 'Alt+F4 fecha a janela: o sistema não deixa o app usá-lo.';
  if (c.mod && !c.alt && const {'R', 'W', 'T', 'N', 'Q'}.contains(c.token)) {
    return '${c.label} é do navegador ou do sistema (recarregar, fechar, nova aba ou janela, sair) e o app não consegue capturá-la.';
  }
  if (c.mod && RegExp(r'^[1-9]$').hasMatch(c.token)) return '${c.label} troca de aba no navegador.';
  if (context == KeyContext.playing) {
    if (c.hasModifier) return 'No teclado tocando a tecla vale sozinha, sem Ctrl, Shift nem Alt.';
    if (!_physicalToToken.containsValue(c.token)) return 'O teclado tocando só usa letras e dígitos.';
    for (final k in noteKeyLetters) {
      if (k == c.token) return '${c.token} já toca uma nota no teclado do computador.';
    }
  }
  return null;
}

/// As letras que tocam nota (o `noteKeys` do controlador, em texto: um teste confere).
const noteKeyLetters = ['A', 'W', 'S', 'E', 'D', 'F', 'T', 'G', 'Y', 'H', 'U', 'J', 'K', 'O', 'L', 'P'];

/// Camada de teclas: geral e arranjo dividem uma, então conflitam entre si.
int _scope(KeyContext c) => switch (c) {
  KeyContext.global || KeyContext.arrangement => 0,
  KeyContext.pianoRoll => 1,
  KeyContext.playing => 2,
};

/// Máximo de atalhos por ação.
const maxBindingsPerAction = 3;

enum AssignStatus { ok, already, reserved, conflict, notEditable }

class AssignCheck {
  final AssignStatus status;

  /// O motivo (reservado) em português.
  final String? reason;

  /// A ação que já usa a combinação (conflito).
  final KeyAction? other;
  const AssignCheck(this.status, {this.reason, this.other});
}

class KeymapFormatException implements Exception {
  final String message;
  KeymapFormatException(this.message);
  @override
  String toString() => message;
}

/// Resultado de [Keymap.importBytes].
class KeymapImport {
  /// O que foi ignorado, descartado ou mudado.
  final List<String> warnings;
  final int applied;
  KeymapImport(this.warnings, this.applied);
}

// ------------------------------------------------------------------------------- guardado

abstract class KeymapStorage {
  Future<String?> read();
  Future<void> write(String json);

  /// Cópia do conteúdo ilegível, antes de qualquer gravação por cima.
  Future<void> writeBackup(String raw) async {}
  Future<String?> readBackup() async => null;
}

/// No `LocalStore` do aparelho (web: IndexedDB; Android: arquivo).
class LocalKeymapStorage implements KeymapStorage {
  static const key = 'keymap';
  static const backupKey = 'keymap.bak';
  final LocalStore _store;
  LocalKeymapStorage([LocalStore? store]) : _store = store ?? LocalStore.instance;

  @override
  Future<String?> read() async {
    final v = await _store.get(key);
    return v is String ? v : null;
  }

  @override
  Future<void> write(String json) => _store.put(key, json);

  @override
  Future<String?> readBackup() async {
    final v = await _store.get(backupKey);
    return v is String ? v : null;
  }

  @override
  Future<void> writeBackup(String raw) async {
    final old = await readBackup();
    if (old == raw) return;
    await _store.put(old == null ? backupKey : '$backupKey.${DateTime.now().millisecondsSinceEpoch}', raw);
  }
}

class MemoryKeymapStorage implements KeymapStorage {
  String? data;
  String? backup;
  @override
  Future<String?> read() async => data;
  @override
  Future<void> write(String json) async => data = json;
  @override
  Future<void> writeBackup(String raw) async => backup ??= raw;
  @override
  Future<String?> readBackup() async => backup;
}

const keymapFormatVersion = 1;
const _localFormat = 'jopendaw-keymap';
const _fileFormat = 'jopendaw-keymap-file';

/// Extensão do arquivo exportado.
const keymapExtension = 'jokeys';
const maxKeymapFileBytes = 256 * 1024;

// ------------------------------------------------------------------------------- Keymap

class Keymap extends ChangeNotifier {
  Keymap(this._storage);

  /// O do app; os testes trocam por um em memória.
  static Keymap instance = Keymap(LocalKeymapStorage());

  final KeymapStorage _storage;

  /// Só o que difere dos padrões (uma lista vazia é "sem atalho").
  final Map<String, List<KeyCombo>> _custom = {};
  Future<void>? _loading;
  Future<void> _writes = Future.value();
  bool _readOnly = false;

  /// Falha da última gravação: as mudanças seguem valendo até fechar o app.
  String? saveError;

  /// Aviso do carregamento (arquivo ilegível ou de versão mais nova).
  String? loadNotice;

  String? get problem => saveError ?? loadNotice;

  /// Índice combinação → ações, por camada; refeito a cada mudança.
  final Map<int, Map<KeyCombo, List<KeyAction>>> _index = {};

  bool get hasCustom => _custom.isNotEmpty;
  bool isCustomized(String id) => _custom.containsKey(id);

  /// Os atalhos atuais da ação (os do usuário, ou os padrões).
  List<KeyCombo> bindingsOf(String id) {
    final a = _byId[id];
    if (a == null) return const [];
    return _custom[id] ?? a.defaultCombos;
  }

  /// O texto dos atalhos da ação na tela ("Enter · Home"), ou "Sem atalho".
  String labelOf(String id, {String none = 'Sem atalho'}) {
    final b = bindingsOf(id);
    return b.isEmpty ? none : b.map((c) => c.label).join(' · ');
  }

  // ------------------------------------------------------------------ resolver

  Map<KeyCombo, List<KeyAction>> _indexFor(int scope) => _index.putIfAbsent(scope, () {
    final m = <KeyCombo, List<KeyAction>>{};
    for (final a in keyCatalog) {
      if (_scope(a.context) != scope) continue;
      for (final c in bindingsOf(a.id)) {
        (m[c] ??= []).add(a);
      }
    }
    return m;
  });

  /// As ações da camada de [layer] (geral/arranjo, piano roll) que a combinação dispara, na ordem do catálogo.
  /// Quase sempre uma; só o Esc (fixo) tem mais, e quem chama vê qual se aplica ao estado.
  List<KeyAction> resolve(KeyCombo stroke, KeyContext layer) {
    final idx = _indexFor(_scope(layer));
    final hit = idx[stroke];
    if (hit != null) return hit;
    // sem combinação exata: o que sobrou de Shift e Alt não conta (como era antes da personalização: Shift+R também
    // gravava). Tira primeiro o Shift, depois o Alt, depois os dois; as teclas de [_modifierAgnostic] tiram também o
    // Ctrl/Cmd. Uma combinação exata de outra ação sempre vence, porque a busca exata vem antes.
    for (final mod in stroke.mod && _modifierAgnostic.contains(stroke.token) ? [true, false] : [stroke.mod]) {
      for (final (shift, alt) in [(stroke.shift, false), (false, stroke.alt), (false, false)]) {
        final v = KeyCombo(stroke.token, mod: mod, shift: shift, alt: alt);
        if (v == stroke) continue;
        var r = idx[v];
        if (r != null && stroke.shift && !v.shift) {
          r = [
            for (final a in r)
              if (!a.exactShift) a,
          ];
        }
        if (r != null && r.isNotEmpty) return r;
      }
    }
    return const [];
  }

  /// A ação do teclado tocando presa à tecla física, ou null.
  KeyAction? playingAction(PhysicalKeyboardKey key) {
    final token = _physicalToToken[key];
    if (token == null) return null;
    final hit = _indexFor(_scope(KeyContext.playing))[KeyCombo(token)];
    return hit == null || hit.isEmpty ? null : hit.first;
  }

  // ------------------------------------------------------------------ mudar

  /// Vê o que aconteceria ao pôr [combo] em [id].
  AssignCheck check(String id, KeyCombo combo) {
    final a = _byId[id];
    if (a == null || a.fixed) return const AssignCheck(AssignStatus.notEditable);
    final why = reservedReason(combo, a.context);
    if (why != null) return AssignCheck(AssignStatus.reserved, reason: why);
    if (bindingsOf(id).contains(combo)) return const AssignCheck(AssignStatus.already);
    final other = conflictOf(id, combo);
    if (other != null) return AssignCheck(AssignStatus.conflict, other: other);
    return const AssignCheck(AssignStatus.ok);
  }

  /// A outra ação (editável) da mesma camada que já usa [combo], ou null.
  KeyAction? conflictOf(String id, KeyCombo combo) {
    final a = _byId[id];
    if (a == null) return null;
    final scope = _scope(a.context);
    for (final o in keyCatalog) {
      if (o.id == id || o.fixed || _scope(o.context) != scope) continue;
      if (bindingsOf(o.id).contains(combo)) return o;
    }
    return null;
  }

  /// Põe [combo] em [id]: no lugar do atalho de índice [slot], ou acrescentado (sem [slot], ou fora da lista).
  /// Com conflito, só grava se [swap]: a outra ação recebe o atalho que esta tinha no [slot] (ou fica sem, se
  /// não tinha). Devolve se gravou.
  bool assign(String id, KeyCombo combo, {int? slot, bool swap = false}) {
    final c = check(id, combo);
    if (c.status == AssignStatus.already) return true;
    if (c.status == AssignStatus.reserved || c.status == AssignStatus.notEditable) return false;
    final list = [...bindingsOf(id)];
    KeyCombo? old;
    if (slot != null && slot >= 0 && slot < list.length) {
      old = list[slot];
      list[slot] = combo;
    } else {
      if (list.length >= maxBindingsPerAction) return false;
      list.add(combo);
    }
    if (c.status == AssignStatus.conflict) {
      if (!swap) return false;
      final other = c.other!;
      final theirs = [...bindingsOf(other.id)];
      final i = theirs.indexOf(combo);
      if (old != null && !theirs.contains(old)) {
        theirs[i] = old;
      } else {
        theirs.removeAt(i);
      }
      _setCustom(other.id, theirs);
    }
    _setCustom(id, list);
    _changed();
    return true;
  }

  /// Tira o atalho de índice [slot] da ação.
  bool removeBinding(String id, int slot) {
    final a = _byId[id];
    if (a == null || a.fixed) return false;
    final list = [...bindingsOf(id)];
    if (slot < 0 || slot >= list.length) return false;
    list.removeAt(slot);
    _setCustom(id, list);
    _changed();
    return true;
  }

  /// Volta a ação ao padrão. Se o padrão dela conflita com outra ação que o tomou, o padrão volta e a outra perde
  /// esse atalho (o padrão restaurado é o que a pessoa pediu agora).
  void reset(String id) {
    final a = _byId[id];
    if (a == null || a.fixed || !_custom.containsKey(id)) return;
    _custom.remove(id);
    for (final c in a.defaultCombos) {
      final other = conflictOf(id, c);
      if (other != null) _setCustom(other.id, [...bindingsOf(other.id)]..remove(c));
    }
    _changed();
  }

  void resetAll() {
    if (_custom.isEmpty) return;
    _custom.clear();
    _changed();
  }

  void _setCustom(String id, List<KeyCombo> list) {
    if (listEquals(list, _byId[id]!.defaultCombos)) {
      _custom.remove(id);
    } else {
      _custom[id] = list;
    }
  }

  void _changed() {
    _index.clear();
    notifyListeners();
    _persist();
  }

  // ------------------------------------------------------------------ guardado

  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    String? raw;
    try {
      raw = await _storage.read();
    } catch (_) {
      _readOnly = true;
      loadNotice = 'Não deu para ler seus atalhos guardados neste aparelho. O que você mudar agora vale só até fechar o app.';
      notifyListeners();
      return;
    }
    if (raw != null && raw.trim().isNotEmpty) {
      final r = _inspect(raw);
      switch (r.state) {
        case _Stored.ok:
          break;
        case _Stored.future:
          _readOnly = true;
          loadNotice =
              'Seus atalhos foram guardados por uma versão mais nova do app. Aqui eles ficam só para leitura: o que você mudar vale só até fechar o app.';
        case _Stored.unreadable:
          try {
            await _storage.writeBackup(raw);
            loadNotice = 'O arquivo dos seus atalhos estava ilegível. Guardei uma cópia dele (keymap.bak) e voltei aos atalhos padrão.';
          } catch (_) {
            _readOnly = true;
            loadNotice = 'O arquivo dos seus atalhos está ilegível e não deu para guardar uma cópia dele. Nada será gravado por cima; o que você mudar vale só até fechar o app.';
          }
      }
      // o que já foi mudado nesta sessão antes de o carregamento acabar vale mais
      for (final e in r.custom.entries) {
        _custom.putIfAbsent(e.key, () => e.value);
      }
      _index.clear();
    }
    notifyListeners();
  }

  /// Espera as gravações pendentes (testes).
  Future<void> flush() => _writes;

  void _persist() {
    if (_readOnly) return;
    final json = _encode(_localFormat);
    _writes = _writes.then((_) async {
      try {
        await _storage.write(json);
        if (saveError != null) {
          saveError = null;
          notifyListeners();
        }
      } catch (e) {
        saveError = 'Não deu para guardar seus atalhos neste aparelho. Eles valem só até fechar o app.';
        notifyListeners();
      }
    });
  }

  String _encode(String format, {bool pretty = false}) {
    final map = {
      'format': format,
      'version': keymapFormatVersion,
      'bindings': {
        for (final a in keyCatalog)
          if (_custom.containsKey(a.id)) a.id: [for (final c in _custom[a.id]!) c.toString()],
      },
    };
    return pretty ? const JsonEncoder.withIndent('  ').convert(map) : jsonEncode(map);
  }

  /// As personalizações de um arquivo local, ou null se ele está ilegível ou é de versão mais nova.
  @visibleForTesting
  static Map<String, List<KeyCombo>>? parseStored(String raw) {
    final r = _inspect(raw);
    return r.state == _Stored.ok ? r.custom : null;
  }

  static ({_Stored state, Map<String, List<KeyCombo>> custom}) _inspect(String raw) {
    Object? j;
    try {
      j = jsonDecode(raw);
    } catch (_) {
      return (state: _Stored.unreadable, custom: const {});
    }
    if (j is! Map || j['format'] != _localFormat) return (state: _Stored.unreadable, custom: const {});
    final v = j['version'];
    if (v is! int || v < 1) return (state: _Stored.unreadable, custom: const {});
    if (j['bindings'] is! Map) return (state: _Stored.unreadable, custom: const {});
    final custom = _sanitize(_parseBindings(j['bindings'] as Map, <String>[]), <String>[]);
    return (state: v > keymapFormatVersion ? _Stored.future : _Stored.ok, custom: custom);
  }

  // ------------------------------------------------------------------ arquivo .jokeys

  /// Os bytes do `.jokeys` (JSON UTF-8): só o que difere dos padrões.
  Uint8List exportBytes() => Uint8List.fromList(utf8.encode(_encode(_fileFormat, pretty: true)));

  /// Valida e aplica um `.jokeys`, no lugar das personalizações de agora. Recusa (lança [KeymapFormatException])
  /// arquivo grande demais, que não é JSON, de outro formato ou de versão mais nova. Ação desconhecida, tecla
  /// inválida ou reservada e conflito são descartados, cada um com um aviso.
  KeymapImport importBytes(Uint8List bytes) {
    if (bytes.length > maxKeymapFileBytes) throw KeymapFormatException('O arquivo é grande demais para ser de atalhos.');
    Object? j;
    try {
      j = jsonDecode(utf8.decode(bytes));
    } catch (_) {
      throw KeymapFormatException('O arquivo não é de atalhos do jopendaw (não é um JSON válido).');
    }
    if (j is! Map || j['format'] != _fileFormat) throw KeymapFormatException('O arquivo não é de atalhos do jopendaw.');
    final v = j['version'];
    if (v is! int || v < 1) throw KeymapFormatException('O arquivo tem uma versão de formato inválida.');
    if (v > keymapFormatVersion) throw KeymapFormatException('Os atalhos são de uma versão mais nova do jopendaw. Atualize o app para importá-los.');
    if (j['bindings'] is! Map) throw KeymapFormatException('O arquivo não tem a lista de atalhos.');
    final warnings = <String>[];
    final parsed = _parseBindings(j['bindings'] as Map, warnings);
    final clean = _sanitize(parsed, warnings);
    _custom
      ..clear()
      ..addAll(clean);
    _changed();
    return KeymapImport(warnings, clean.length);
  }

  /// Lê o mapa `id → [teclas]`, descartando o que não presta (com aviso em [warnings]).
  static Map<String, List<KeyCombo>> _parseBindings(Map raw, List<String> warnings) {
    final out = <String, List<KeyCombo>>{};
    for (final e in raw.entries) {
      final id = '${e.key}';
      final a = _byId[id];
      if (a == null) {
        warnings.add('Ação desconhecida "$id" ignorada.');
        continue;
      }
      if (a.fixed) {
        warnings.add('"${a.label}" tem tecla fixa e não muda; ignorada.');
        continue;
      }
      if (e.value is! List) {
        warnings.add('Os atalhos de "${a.label}" não são uma lista; ignorados.');
        continue;
      }
      final list = <KeyCombo>[];
      for (final item in e.value as List) {
        final c = KeyCombo.parse(item);
        if (c == null) {
          warnings.add('Tecla inválida "$item" em "${a.label}" descartada.');
          continue;
        }
        final why = reservedReason(c, a.context);
        if (why != null) {
          warnings.add('${c.label} em "${a.label}" descartada: $why');
          continue;
        }
        if (list.contains(c)) continue;
        if (list.length >= maxBindingsPerAction) {
          warnings.add('"${a.label}" aceita até $maxBindingsPerAction atalhos; ${c.label} descartado.');
          continue;
        }
        list.add(c);
      }
      if (!listEquals(list, a.defaultCombos)) out[id] = list;
    }
    return out;
  }

  /// Tira conflitos de um mapa importado: entre ações personalizadas vale a primeira do catálogo; sobre um padrão
  /// de ação não personalizada vale o importado (a outra perde o atalho).
  static Map<String, List<KeyCombo>> _sanitize(Map<String, List<KeyCombo>> custom, List<String> warnings) {
    final out = <String, List<KeyCombo>>{};
    final claimed = <int, Map<KeyCombo, KeyAction>>{};
    for (final a in keyCatalog) {
      final list = custom[a.id];
      if (list == null) continue;
      final owned = claimed.putIfAbsent(_scope(a.context), () => {});
      final kept = <KeyCombo>[];
      for (final c in list) {
        final holder = owned[c];
        if (holder != null) {
          warnings.add('${c.label} já é de "${holder.label}"; descartada em "${a.label}".');
          continue;
        }
        owned[c] = a;
        kept.add(c);
      }
      out[a.id] = kept;
    }
    for (final a in keyCatalog) {
      if (a.fixed || custom.containsKey(a.id)) continue;
      final owned = claimed[_scope(a.context)];
      if (owned == null) continue;
      final kept = [
        for (final c in a.defaultCombos)
          if (owned[c] == null) c,
      ];
      if (kept.length != a.defaultCombos.length) {
        for (final c in a.defaultCombos) {
          if (owned[c] != null) warnings.add('"${a.label}" perdeu ${c.label}, que agora é de "${owned[c]!.label}".');
        }
        out[a.id] = kept;
      }
    }
    return out;
  }
}

enum _Stored { ok, unreadable, future }

/// A tecla lógica de um token (a primeira que o produz), ou null se o token não existe. Para os testes e a tela.
LogicalKeyboardKey? logicalKeyForToken(String token) {
  for (final e in _logicalToToken.entries) {
    if (e.value == token) return e.key;
  }
  return null;
}
