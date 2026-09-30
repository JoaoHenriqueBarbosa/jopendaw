/// Presets do usuário: o timbre de um instrumento ou de um efeito guardado com nome, para carregar
/// depois em qualquer faixa, renomear, apagar e levar de um aparelho a outro (`.jopreset`).
///
/// Ficam num arquivo só no guardado local do aparelho (`userpresets`, o mesmo `LocalStore` do
/// documento e dos áudios). Por enquanto não sincronizam com a conta: o `.jopreset` é o caminho
/// para levar de um aparelho a outro.
///
/// O que entra no preset:
/// * instrumento: todos os parâmetros do tipo, menos, no sampler, a nota base e a afinação, que
///   pertencem ao áudio escolhido; o preset do sampler NÃO leva áudio nem zonas, só timbre e envelope;
/// * efeito: todos os parâmetros do tipo (o EQ leva as 8 bandas), menos a faixa-chave do sidechain,
///   que é roteamento do projeto.
///
/// Sem `dart:io` e sem bit a bit acima de 32 bits: roda igual no dart2js.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../audio/engine.dart';
import 'effects.dart';
import 'instruments.dart';
import 'model.dart';
import 'presets.dart';

/// Se o preset é de instrumento ou de efeito (o nome do tipo sozinho seria ambíguo no futuro).
enum PresetFamily {
  instrument,
  effect;

  static PresetFamily? parse(Object? s) {
    for (final f in values) {
      if (f.name == s) return f;
    }
    return null;
  }
}

/// Versão do formato gravado (arquivo local e `.jopreset`). Versão maior que esta é recusada.
const userPresetFormatVersion = 1;
const _localFormat = 'jopendaw-user-presets';
const _fileFormat = 'jopendaw-preset';

/// Extensão do arquivo exportado.
const userPresetExtension = 'jopreset';

/// Limites: nome, quantidade por tipo e tamanho do arquivo importado.
const maxUserPresetName = 60;
const maxUserPresetsPerKind = 300;
const maxUserPresetFileBytes = 256 * 1024;

/// Ids que um preset não leva (ver o cabeçalho).
const _samplerSkip = {SamplerId.root, SamplerId.tune};

/// A tabela de parâmetros de um tipo, ou null se o tipo não tem presets (áudio, bus, desconhecido).
List<ParamSpec>? presetSpecs(PresetFamily family, String kind) {
  switch (family) {
    case PresetFamily.instrument:
      final k = TrackKind.values.where((k) => k.name == kind);
      if (k.isEmpty || !k.first.isInstrument) return null;
      final specs = k.first.params;
      return specs.isEmpty ? null : specs;
    case PresetFamily.effect:
      final k = EffectKind.parse(kind);
      return k?.params;
  }
}

/// Ids fora do preset para o tipo.
Set<int> presetSkipIds(PresetFamily family, String kind) => switch ((family, kind)) {
  (PresetFamily.instrument, 'sampler') => _samplerSkip,
  (PresetFamily.effect, 'compressor') => const {10},
  (PresetFamily.effect, 'gate') => const {6},
  _ => const {},
};

/// O nome como pode ser guardado: sem caracteres de controle, espaços colapsados, sem pontas em
/// branco e com no máximo [maxUserPresetName] caracteres (sem cortar um par substituto ao meio).
/// Vazio se sobrar nada.
String cleanPresetName(String raw) {
  final b = StringBuffer();
  for (final r in raw.runes) {
    // controle C0/C1, separadores de linha e parágrafo, marcas de direção e zero-width
    final bad =
        r < 0x20 || (r >= 0x7f && r <= 0x9f) || r == 0x2028 || r == 0x2029 || (r >= 0x200b && r <= 0x200f) || (r >= 0x202a && r <= 0x202e) || r == 0xfeff;
    b.writeCharCode(bad ? 0x20 : r);
  }
  var s = b.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  final runes = s.runes.toList();
  if (runes.length > maxUserPresetName) s = String.fromCharCodes(runes.take(maxUserPresetName)).trim();
  return s;
}

/// O nome vira nome de arquivo: só o que qualquer sistema aceita.
String presetFileName(String name) {
  var s = cleanPresetName(name).replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').replaceAll(RegExp(r'^\.+'), '');
  if (s.isEmpty) s = 'preset';
  return '$s.$userPresetExtension';
}

class UserPreset {
  final String id;
  final PresetFamily family;

  /// `TrackKind.name` ou `EffectKind.name`.
  final String kind;
  final String name;

  /// Parâmetro → valor, na unidade da tabela.
  final Map<int, double> values;
  final DateTime created;
  final int version;

  UserPreset({
    required this.id,
    required this.family,
    required this.kind,
    required this.name,
    required Map<int, double> values,
    DateTime? created,
    this.version = userPresetFormatVersion,
  }) : values = Map.unmodifiable(values),
       created = created ?? DateTime.now();

  UserPreset copyWith({String? name, Map<int, double>? values}) =>
      UserPreset(id: id, family: family, kind: kind, name: name ?? this.name, values: values ?? this.values, created: created, version: version);

  Map<String, dynamic> toJson() => {
    'id': id,
    'family': family.name,
    'kind': kind,
    'name': name,
    'version': version,
    'created': created.toUtc().toIso8601String(),
    'params': {for (final e in values.entries) '${e.key}': e.value},
  };
}

/// Recusa de importação (arquivo que não é um preset utilizável); a mensagem vai para a tela.
class PresetFormatException implements Exception {
  final String message;
  PresetFormatException(this.message);
  @override
  String toString() => message;
}

/// Resultado de [UserPresets.importBytes].
class PresetImport {
  final UserPreset preset;

  /// O que foi limitado, ignorado ou renomeado.
  final List<String> warnings;
  PresetImport(this.preset, this.warnings);
}

/// Onde o arquivo dos presets fica.
abstract class UserPresetStorage {
  Future<String?> read();
  Future<void> write(String json);
}

/// No `LocalStore` do aparelho (web: IndexedDB; Android: arquivo; outros sistemas: nada guardado, e
/// então os presets valem só até fechar o app).
class LocalUserPresetStorage implements UserPresetStorage {
  static const key = 'userpresets';
  final LocalStore _store;
  LocalUserPresetStorage([LocalStore? store]) : _store = store ?? LocalStore.instance;

  @override
  Future<String?> read() async {
    final v = await _store.get(key);
    return v is String ? v : null;
  }

  @override
  Future<void> write(String json) => _store.put(key, json);
}

/// Guardado só na memória (testes e sistemas sem guardado).
class MemoryUserPresetStorage implements UserPresetStorage {
  String? data;
  @override
  Future<String?> read() async => data;
  @override
  Future<void> write(String json) async => data = json;
}

class UserPresets extends ChangeNotifier {
  UserPresets(this._storage);

  /// O do app; os testes trocam por um em memória.
  static UserPresets instance = UserPresets(LocalUserPresetStorage());

  final UserPresetStorage _storage;
  final _items = <UserPreset>[];
  Future<void>? _loading;
  Future<void> _writes = Future.value();
  var _seq = 0;

  /// Falha da última gravação (o guardado recusou): a tela pode avisar; os presets seguem na memória.
  String? saveError;

  /// Carrega uma vez (chamar de novo devolve o mesmo futuro).
  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final raw = await _storage.read();
      if (raw != null) {
        // se algo já foi salvo nesta sessão antes do carregamento acabar, não duplica
        final have = {for (final p in _items) p.id};
        _items.insertAll(0, parseStored(raw).where((p) => !have.contains(p.id) && !exists(p.family, p.kind, p.name)));
      }
    } catch (_) {
      // guardado ilegível: começa vazio (a próxima gravação o substitui)
    }
    notifyListeners();
  }

  /// Os presets de um tipo, na ordem em que foram criados.
  List<UserPreset> of(PresetFamily family, String kind) => [
    for (final p in _items)
      if (p.family == family && p.kind == kind) p,
  ];

  List<UserPreset> ofTrack(TrackKind kind) => of(PresetFamily.instrument, kind.name);
  List<UserPreset> ofEffect(EffectKind kind) => of(PresetFamily.effect, kind.name);

  UserPreset? byName(PresetFamily family, String kind, String name) {
    final n = cleanPresetName(name).toLowerCase();
    for (final p in _items) {
      if (p.family == family && p.kind == kind && p.name.toLowerCase() == n) return p;
    }
    return null;
  }

  /// Já existe preset com esse nome (sem diferenciar maiúsculas) neste tipo?
  bool exists(PresetFamily family, String kind, String name) => byName(family, kind, name) != null;

  String _newId() => 'u${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${(_seq++).toRadixString(36)}';

  /// Extrai [current] (parâmetro → valor atual) para o que o preset guarda: todos os ids do tipo,
  /// limitados à faixa, menos os que ficam fora.
  static Map<int, double> capture(PresetFamily family, String kind, double Function(int id) current) {
    final specs = presetSpecs(family, kind) ?? const <ParamSpec>[];
    final skip = presetSkipIds(family, kind);
    return {
      for (final s in specs)
        if (!skip.contains(s.id)) s.id: _fit(s, current(s.id)),
    };
  }

  static double _fit(ParamSpec s, double v) {
    if (!v.isFinite) return s.def;
    final c = s.clamp(v);
    return s.curve == Curve.choice ? c.roundToDouble() : c;
  }

  /// Salva. Com o nome já em uso: sem [replace] devolve null (quem chama pergunta); com [replace],
  /// troca os valores do existente (mantém id e data). Nome inválido lança [PresetFormatException];
  /// o limite por tipo também.
  UserPreset? save(PresetFamily family, String kind, String name, Map<int, double> values, {bool replace = false}) {
    if (presetSpecs(family, kind) == null) throw PresetFormatException('Este tipo não tem presets.');
    final clean = cleanPresetName(name);
    if (clean.isEmpty) throw PresetFormatException('Dê um nome ao preset.');
    final old = byName(family, kind, clean);
    if (old != null) {
      if (!replace) return null;
      final p = old.copyWith(values: values);
      _items[_items.indexOf(old)] = p;
      _changed();
      return p;
    }
    if (of(family, kind).length >= maxUserPresetsPerKind) {
      throw PresetFormatException('Limite de $maxUserPresetsPerKind presets para este tipo. Apague algum antes.');
    }
    final p = UserPreset(id: _newId(), family: family, kind: kind, name: clean, values: values);
    _items.add(p);
    _changed();
    return p;
  }

  /// Renomeia. Devolve false se outro preset do tipo já tem o nome; nome vazio lança.
  bool rename(String id, String name) {
    final i = _items.indexWhere((p) => p.id == id);
    if (i < 0) return false;
    final clean = cleanPresetName(name);
    if (clean.isEmpty) throw PresetFormatException('Dê um nome ao preset.');
    final old = _items[i];
    final other = byName(old.family, old.kind, clean);
    if (other != null && other.id != id) return false;
    _items[i] = old.copyWith(name: clean);
    _changed();
    return true;
  }

  bool delete(String id) {
    final n = _items.length;
    _items.removeWhere((p) => p.id == id);
    if (_items.length == n) return false;
    _changed();
    return true;
  }

  void _changed() {
    notifyListeners();
    final json = jsonEncode({
      'format': _localFormat,
      'version': userPresetFormatVersion,
      'presets': [for (final p in _items) p.toJson()],
    });
    // uma gravação de cada vez, na ordem: a última vence
    _writes = _writes.then((_) async {
      try {
        await _storage.write(json);
        saveError = null;
      } catch (e) {
        saveError = 'Não deu para guardar os presets neste aparelho.';
      }
    });
  }

  /// Espera as gravações pendentes (testes).
  Future<void> flush() => _writes;

  // ------------------------------------------------------------------------ arquivo local

  /// Lê o arquivo local; entrada inválida é pulada, nunca lança por causa de um preset ruim.
  @visibleForTesting
  static List<UserPreset> parseStored(String raw) {
    final j = jsonDecode(raw);
    if (j is! Map || j['format'] != _localFormat) return const [];
    final v = j['version'];
    if (v is! int || v > userPresetFormatVersion) return const [];
    final out = <UserPreset>[];
    final ids = <String>{};
    for (final e in (j['presets'] is List ? j['presets'] as List : const [])) {
      try {
        final p = _fromMap(e, strict: false)?.$1;
        if (p == null || !ids.add(p.id)) continue;
        out.add(p);
      } catch (_) {}
    }
    return out;
  }

  // ------------------------------------------------------------------------ arquivo .jopreset

  /// Os bytes do `.jopreset` (JSON UTF-8).
  Uint8List exportBytes(UserPreset p) => Uint8List.fromList(
    utf8.encode(
      const JsonEncoder.withIndent('  ').convert({
        'format': _fileFormat,
        'version': userPresetFormatVersion,
        'family': p.family.name,
        'kind': p.kind,
        'name': p.name,
        'created': p.created.toUtc().toIso8601String(),
        'params': {for (final e in p.values.entries) '${e.key}': e.value},
      }),
    ),
  );

  /// Valida e adiciona um `.jopreset`. Recusa (lança [PresetFormatException]) arquivo grande demais,
  /// que não é JSON, de outro formato, de versão futura, de tipo desconhecido ou sem nenhum valor
  /// aproveitável. Ids que o tipo não tem e valores que não são número são ignorados; valores fora
  /// da faixa são limitados; tudo vira aviso. Nome em uso ganha " (2)", " (3)"...
  PresetImport importBytes(Uint8List bytes) {
    if (bytes.length > maxUserPresetFileBytes) throw PresetFormatException('O arquivo é grande demais para ser um preset.');
    Object? j;
    try {
      j = jsonDecode(utf8.decode(bytes));
    } catch (_) {
      throw PresetFormatException('O arquivo não é um preset do jopendaw (não é um JSON válido).');
    }
    if (j is! Map || j['format'] != _fileFormat) throw PresetFormatException('O arquivo não é um preset do jopendaw.');
    final v = j['version'];
    if (v is! int || v < 1) throw PresetFormatException('O arquivo tem uma versão de formato inválida.');
    if (v > userPresetFormatVersion) throw PresetFormatException('O preset é de uma versão mais nova do jopendaw. Atualize o app para importá-lo.');
    final parsed = _fromMap(j, strict: true)!;
    final warnings = [...parsed.$2];
    final base = parsed.$1;
    if (of(base.family, base.kind).length >= maxUserPresetsPerKind) {
      throw PresetFormatException('Limite de $maxUserPresetsPerKind presets para este tipo. Apague algum antes.');
    }
    var name = base.name;
    if (exists(base.family, base.kind, name)) {
      var n = 2;
      String candidate() {
        final suffix = ' ($n)';
        final room = maxUserPresetName - suffix.length;
        final stem = String.fromCharCodes(base.name.runes.take(room)).trimRight();
        return '$stem$suffix';
      }

      while (exists(base.family, base.kind, candidate())) {
        n++;
      }
      name = candidate();
      warnings.add('Já havia um preset chamado "${base.name}": este entrou como "$name".');
    }
    final p = UserPreset(id: _newId(), family: base.family, kind: base.kind, name: name, values: base.values, created: base.created);
    _items.add(p);
    _changed();
    return PresetImport(p, warnings);
  }

  /// Monta o preset de um mapa (arquivo local ou `.jopreset`). No [strict], as anomalias viram
  /// avisos e o vazio lança; fora dele, o que não serve é silenciosamente ajustado.
  static (UserPreset, List<String>)? _fromMap(Object? e, {required bool strict}) {
    if (e is! Map) {
      if (strict) throw PresetFormatException('O arquivo não é um preset do jopendaw.');
      return null;
    }
    final family = PresetFamily.parse(e['family']);
    final kind = e['kind'];
    final specs = family != null && kind is String ? presetSpecs(family, kind) : null;
    if (family == null || kind is! String || specs == null) {
      if (strict) throw PresetFormatException('Tipo de preset desconhecido ("${e['family']}/${e['kind']}"). Ele pode ser de uma versão mais nova do jopendaw.');
      return null;
    }
    final skip = presetSkipIds(family, kind);
    final byId = {for (final s in specs) s.id: s};
    final params = e['params'];
    if (params is! Map) {
      if (strict) throw PresetFormatException('O preset não traz parâmetros.');
      return null;
    }
    final warnings = <String>[];
    final values = <int, double>{};
    var unknown = 0, invalid = 0, clamped = 0;
    for (final entry in params.entries) {
      final id = entry.key is String ? int.tryParse(entry.key as String) : null;
      final spec = id == null ? null : byId[id];
      if (spec == null) {
        unknown++;
        continue;
      }
      if (skip.contains(id)) continue;
      final raw = entry.value;
      if (raw is! num || !raw.isFinite) {
        invalid++;
        continue;
      }
      final d = raw.toDouble();
      final fit = _fit(spec, d);
      if ((fit - d).abs() > 1e-9 * math.max(1, d.abs())) clamped++;
      values[id!] = fit;
    }
    if (strict && values.isEmpty) throw PresetFormatException('O preset não tem nenhum valor utilizável para este tipo.');
    if (unknown > 0) warnings.add('$unknown parâmetro${unknown == 1 ? '' : 's'} desconhecido${unknown == 1 ? '' : 's'} ignorado${unknown == 1 ? '' : 's'}.');
    if (invalid > 0) {
      warnings.add(
        '$invalid valor${invalid == 1 ? '' : 'es'} inválido${invalid == 1 ? '' : 's'} (não numérico ou infinito) ignorado${invalid == 1 ? '' : 's'}.',
      );
    }
    if (clamped > 0) {
      warnings.add('$clamped valor${clamped == 1 ? '' : 'es'} fora da faixa foi${clamped == 1 ? '' : 'ram'} limitado${clamped == 1 ? '' : 's'}.');
    }
    // o que o arquivo não diz volta ao padrão do tipo
    for (final s in specs) {
      if (!skip.contains(s.id)) values.putIfAbsent(s.id, () => s.def);
    }
    var name = cleanPresetName(e['name'] is String ? e['name'] as String : '');
    if (name.isEmpty) {
      name = 'Preset importado';
      if (strict) warnings.add('O arquivo não tinha um nome válido: entrou como "$name".');
    } else if (strict && e['name'] != name) {
      warnings.add('O nome foi ajustado (caracteres de controle e espaços) para "$name".');
    }
    var created = DateTime.now();
    if (e['created'] is String) created = DateTime.tryParse(e['created'] as String) ?? created;
    final id = e['id'] is String && (e['id'] as String).isNotEmpty && (e['id'] as String).length <= 64
        ? e['id'] as String
        : 'u${created.microsecondsSinceEpoch.toRadixString(36)}';
    return (UserPreset(id: id, family: family, kind: kind, name: name, values: values, created: created), warnings);
  }

  // ------------------------------------------------------------------------ aplicar e casar

  /// Os parâmetros completos que o preset põe na faixa (tipo padrão + preset; no sampler, nota
  /// base e afinação continuam as da faixa).
  static Map<int, double> paramsFor(UserPreset p, DawTrack t) => {
    ...defaultParams(t.kind),
    ...p.values,
    if (t.kind == TrackKind.sampler)
      for (final id in _samplerSkip) id: t.param(id),
  };

  /// Idem para um slot de efeito (o sidechain continua o do slot).
  static Map<int, double> paramsForEffect(UserPreset p, EffectSlot s) {
    final skip = presetSkipIds(PresetFamily.effect, s.kind.name);
    return {for (final spec in s.kind.params) spec.id: skip.contains(spec.id) ? s.param(spec.id) : (p.values[spec.id] ?? spec.def)};
  }

  UserPreset? _match(PresetFamily family, String kind, double Function(int) current) {
    final specs = presetSpecs(family, kind);
    if (specs == null) return null;
    final skip = presetSkipIds(family, kind);
    for (final p in of(family, kind)) {
      var same = true;
      for (final s in specs) {
        if (skip.contains(s.id)) continue;
        final want = p.values[s.id] ?? s.def;
        if ((current(s.id) - want).abs() > 1e-6 * math.max(1, want.abs())) {
          same = false;
          break;
        }
      }
      if (same) return p;
    }
    return null;
  }

  /// O preset do usuário cujos valores batem com os da faixa agora.
  UserPreset? matchingTrack(DawTrack t) => t.kind.isInstrument ? _match(PresetFamily.instrument, t.kind.name, t.param) : null;

  /// Idem para o slot de efeito.
  UserPreset? matchingEffect(EffectSlot s) => _match(PresetFamily.effect, s.kind.name, s.param);
}
