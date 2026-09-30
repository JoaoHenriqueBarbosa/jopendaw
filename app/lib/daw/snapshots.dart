/// Versões nomeadas do projeto (instantâneos do documento inteiro), guardadas SÓ NESTE APARELHO.
///
/// Cada versão é uma chave do [LocalStore], `snapshots:<projeto>:<id>`, com um JSON de envelope:
/// `{"format":"jopendaw-version","version":1,"id","seq","name","note","auto","created_at","tracks","clips","doc":{…}}`.
/// O `doc` é o mesmo JSON do `DawDoc.toJson()`, sem os áudios (eles são endereçados por sha-256 e já vivem no
/// guardado local `sample:<hash>` e no servidor, e uma versão só os cita).
///
/// As versões NÃO sobem ao servidor nesta fase. Gancho para a próxima: [VersionKeeper.exportEnvelope] devolve o
/// texto do envelope pronto para um `PUT /projects/:id/versions/:id`, e [parseSnapshotEnvelope] lê o de volta.
/// Um aparelho novo, portanto, abre o projeto sem nenhuma versão ([noVersionsMessage]).
///
/// Versões automáticas: a cada [VersionsPrefs.minutes] minutos de edição e ao abrir o projeto depois de mais de
/// [openGap]; guarda-se só as últimas [autoKeep]. As manuais nunca saem sozinhas. Duas versões idênticas seguidas
/// (JSON igual) não são guardadas.
library;

import 'dart:async';
import 'dart:convert';

import '../audio/engine.dart' show LocalStore;
import '../models/project.dart';
import 'model.dart';
import 'project_file.dart';

/// Quantas versões automáticas ficam (as mais velhas saem).
const autoKeep = 20;

/// Passado este espaço somado das versões do projeto, a tela avisa.
const snapshotWarnBytes = 50 * 1024 * 1024;

/// Abrir o projeto depois de mais que isso sem nenhuma versão nova guarda uma automática.
const openGap = Duration(hours: 1);

/// Intervalo padrão das versões automáticas (minutos) e as opções da tela.
const defaultAutoMinutes = 15;
const autoMinuteChoices = [5, 10, 15, 30, 60];

const noVersionsMessage = 'Este aparelho ainda não tem versões deste projeto. As versões ficam só no aparelho onde foram salvas e não vêm da nuvem.';

const _format = 'jopendaw-version';
const _formatVersion = 1;
const _prefsKey = 'versions-prefs';

String snapshotKey(String projectId, String id) => 'snapshots:$projectId:$id';
String snapshotPrefix(String projectId) => 'snapshots:$projectId:';

/// Uma versão sem o documento (para listar). O documento se carrega por [VersionKeeper.load].
class Snapshot {
  final String id;
  final int seq;
  final String name;
  final String note;
  final bool auto;
  final DateTime createdAt;
  final int tracks, clips;

  /// Tamanho do arquivo guardado (caracteres do texto).
  final int bytes;
  const Snapshot({
    required this.id,
    required this.seq,
    required this.name,
    required this.note,
    required this.auto,
    required this.createdAt,
    required this.tracks,
    required this.clips,
    required this.bytes,
  });

  Snapshot copyWith({String? name, String? note, bool? auto}) => Snapshot(
    id: id,
    seq: seq,
    name: name ?? this.name,
    note: note ?? this.note,
    auto: auto ?? this.auto,
    createdAt: createdAt,
    tracks: tracks,
    clips: clips,
    bytes: bytes,
  );
}

/// O resultado de ler as versões do guardado.
class VersionList {
  /// Da mais nova para a mais velha.
  final List<Snapshot> items;

  /// Chaves cujo conteúdo não deu para ler (arquivo cortado ou de outro formato): a tela avisa e oferece limpar.
  final List<String> corruptKeys;
  final int totalBytes;

  /// O espaço a partir do qual a tela avisa (o [snapshotWarnBytes]; os testes usam um menor).
  final int warnBytes;
  const VersionList(this.items, this.corruptKeys, this.totalBytes, {this.warnBytes = snapshotWarnBytes});

  bool get overLimit => totalBytes > warnBytes;
  bool get isEmpty => items.isEmpty;
}

/// Preferências das versões automáticas, do aparelho (valem para todos os projetos).
class VersionsPrefs {
  final bool auto;
  final int minutes;
  const VersionsPrefs({this.auto = true, this.minutes = defaultAutoMinutes});

  Map<String, dynamic> toJson() => {'auto': auto, 'minutes': minutes};

  static VersionsPrefs fromJson(Object? j) {
    if (j is! Map) return const VersionsPrefs();
    final m = j['minutes'];
    return VersionsPrefs(auto: j['auto'] is bool ? j['auto'] as bool : true, minutes: m is int && m >= 1 && m <= 24 * 60 ? m : defaultAutoMinutes);
  }
}

/// O envelope lido: metadados e o documento (JSON já decodificado); null se não é uma versão válida.
({Snapshot meta, Map<String, dynamic> doc, String docJson})? parseSnapshotEnvelope(String text) {
  try {
    final j = jsonDecode(text);
    if (j is! Map || j['format'] != _format) return null;
    final v = j['version'];
    if (v is! int || v > _formatVersion) return null;
    final doc = j['doc'];
    if (doc is! Map || doc['tracks'] is! List) return null;
    final created = DateTime.tryParse('${j['created_at']}');
    if (created == null) return null;
    final id = j['id'];
    if (id is! String || id.isEmpty) return null;
    final docMap = doc.cast<String, dynamic>();
    // conta pelo próprio documento se o resumo sumiu do envelope
    final counts = _countDoc(docMap);
    final meta = Snapshot(
      id: id,
      seq: j['seq'] is int ? j['seq'] as int : 0,
      name: '${j['name'] ?? ''}',
      note: '${j['note'] ?? ''}',
      auto: j['auto'] == true,
      createdAt: created,
      tracks: j['tracks'] is int ? j['tracks'] as int : counts.$1,
      clips: j['clips'] is int ? j['clips'] as int : counts.$2,
      bytes: text.length,
    );
    return (meta: meta, doc: docMap, docJson: jsonEncode(docMap));
  } catch (_) {
    return null;
  }
}

/// (faixas, clipes) de um documento em JSON: as pastas não contam como faixa; clipes são os de áudio e os MIDI.
(int, int) _countDoc(Map<String, dynamic> doc) {
  var tracks = 0, clips = 0;
  for (final t in (doc['tracks'] as List)) {
    if (t is! Map) continue;
    if (t['group'] != true) tracks++;
    clips += ((t['clips'] as List?)?.length ?? 0) + ((t['midi'] as List?)?.length ?? 0);
  }
  return (tracks, clips);
}

/// Guarda, lista, restaura e apaga as versões de UM projeto, e decide as automáticas.
class VersionKeeper {
  final LocalStore store;
  final String projectId;

  /// O documento vivo em JSON (o mesmo texto que o desfazer guarda).
  final String Function() currentJson;

  /// O relógio (os testes usam um falso).
  final DateTime Function() clock;

  /// O documento tem algo que valha guardar ao abrir (uma faixa vazia recém-criada não vale).
  final bool Function() hasContent;

  VersionKeeper({required this.store, required this.projectId, required this.currentJson, DateTime Function()? clock, bool Function()? hasContent})
    : clock = clock ?? DateTime.now,
      hasContent = hasContent ?? (() => true);

  /// O espaço somado a partir do qual [VersionList.overLimit] vale.
  int warnBytes = snapshotWarnBytes;

  /// Avisa a tela (a lista de versões mudou).
  final changes = StreamController<void>.broadcast();

  Future<void> _lock = Future.value();
  Future<T> _serial<T>(Future<T> Function() f) {
    final next = _lock.then((_) => f());
    _lock = next.then((_) {}, onError: (_) {});
    return next;
  }

  // ---------------------------------------------------------------------- ler

  /// Todas as versões legíveis (mais nova primeiro) e as chaves ilegíveis.
  Future<VersionList> list() async {
    final items = <Snapshot>[];
    final corrupt = <String>[];
    var total = 0;
    List<String> keys;
    try {
      keys = await store.keys(snapshotPrefix(projectId));
    } catch (_) {
      keys = const [];
    }
    for (final k in keys) {
      try {
        final raw = await store.get(k);
        final parsed = raw is String ? parseSnapshotEnvelope(raw) : null;
        // a chave manda: um envelope copiado para outro nome não vale
        if (parsed == null || snapshotKey(projectId, parsed.meta.id) != k) {
          corrupt.add(k);
          continue;
        }
        items.add(parsed.meta);
        total += parsed.meta.bytes;
      } catch (_) {
        corrupt.add(k);
      }
    }
    items.sort((a, b) {
      final c = b.createdAt.compareTo(a.createdAt);
      return c != 0 ? c : b.seq.compareTo(a.seq);
    });
    return VersionList(items, corrupt, total, warnBytes: warnBytes);
  }

  /// O documento de uma versão (JSON), ou null se sumiu ou está ilegível.
  Future<Map<String, dynamic>?> load(String id) async {
    try {
      final raw = await store.get(snapshotKey(projectId, id));
      return raw is String ? parseSnapshotEnvelope(raw)?.doc : null;
    } catch (_) {
      return null;
    }
  }

  /// O texto guardado da versão, pronto para enviar ao servidor no futuro (ver o topo do arquivo).
  Future<String?> exportEnvelope(String id) async {
    final raw = await store.get(snapshotKey(projectId, id));
    return raw is String ? raw : null;
  }

  // ------------------------------------------------------------------- gravar

  /// Guarda o documento de agora. Devolve a versão nova; `null` se o documento é igual ao da versão mais nova (nada
  /// a guardar), a menos que essa seja automática e [auto] seja falso: aí ela vira a manual com o nome pedido.
  /// [json] permite guardar um texto que não é o do documento vivo (o "Antes de restaurar").
  Future<Snapshot?> save({required String name, String note = '', bool auto = false, String? json}) => _serial(() async {
    final text = json ?? currentJson();
    final all = await list();
    final newest = all.items.isEmpty ? null : all.items.first;
    if (newest != null) {
      final same = await _sameAsCurrent(newest.id, text);
      if (same) {
        if (newest.auto && !auto) {
          final promoted = newest.copyWith(name: name, note: note, auto: false);
          await _rewrite(promoted);
          _ping();
          return promoted;
        }
        return null;
      }
    }
    final now = clock();
    final seq = all.items.fold<int>(0, (m, s) => s.seq > m ? s.seq : m) + 1;
    final id = '${seq.toRadixString(36)}-${now.millisecondsSinceEpoch.toRadixString(36)}';
    final doc = jsonDecode(text) as Map<String, dynamic>;
    final (tracks, clips) = _countDoc(doc);
    final envelope = jsonEncode({
      'format': _format,
      'version': _formatVersion,
      'id': id,
      'seq': seq,
      'name': name,
      'note': note,
      'auto': auto,
      'created_at': now.toUtc().toIso8601String(),
      'tracks': tracks,
      'clips': clips,
      'doc': doc,
    });
    await store.put(snapshotKey(projectId, id), envelope);
    _baseline = now;
    if (auto) await _pruneAuto();
    _ping();
    return Snapshot(id: id, seq: seq, name: name, note: note, auto: auto, createdAt: now.toUtc(), tracks: tracks, clips: clips, bytes: envelope.length);
  });

  Future<bool> _sameAsCurrent(String id, String text) async {
    final doc = await load(id);
    if (doc == null) return false;
    try {
      return jsonEncode(doc) == jsonEncode(jsonDecode(text));
    } catch (_) {
      return false;
    }
  }

  Future<void> _rewrite(Snapshot s) async {
    final raw = await store.get(snapshotKey(projectId, s.id));
    if (raw is! String) return;
    final j = jsonDecode(raw) as Map<String, dynamic>;
    j['name'] = s.name;
    j['note'] = s.note;
    j['auto'] = s.auto;
    await store.put(snapshotKey(projectId, s.id), jsonEncode(j));
  }

  /// Muda o nome e a nota. Devolve false se a versão sumiu ou está ilegível.
  Future<bool> rename(String id, String name, {String? note}) => _serial(() async {
    try {
      final raw = await store.get(snapshotKey(projectId, id));
      if (raw is! String || parseSnapshotEnvelope(raw) == null) return false;
      final j = jsonDecode(raw) as Map<String, dynamic>;
      j['name'] = name;
      if (note != null) j['note'] = note;
      // renomear é uma decisão da pessoa: a versão deixa de ser candidata à limpeza das automáticas
      j['auto'] = false;
      await store.put(snapshotKey(projectId, id), jsonEncode(j));
      _ping();
      return true;
    } catch (_) {
      return false;
    }
  });

  Future<void> delete(String id) => _serial(() async {
    await store.delete(snapshotKey(projectId, id));
    _ping();
  });

  /// Apaga as chaves ilegíveis que [list] apontou.
  Future<void> deleteCorrupt(List<String> keys) => _serial(() async {
    for (final k in keys) {
      if (!k.startsWith(snapshotPrefix(projectId))) continue;
      try {
        await store.delete(k);
      } catch (_) {}
    }
    _ping();
  });

  Future<void> _pruneAuto() async {
    final autos = (await list()).items.where((s) => s.auto).toList(); // mais nova primeiro
    for (final s in autos.skip(autoKeep)) {
      try {
        await store.delete(snapshotKey(projectId, s.id));
      } catch (_) {}
    }
  }

  void _ping() {
    if (!changes.isClosed) changes.add(null);
  }

  // ----------------------------------------------------------- automáticas

  VersionsPrefs _prefs = const VersionsPrefs();
  bool _prefsLoaded = false;

  Future<VersionsPrefs> prefs() async {
    if (!_prefsLoaded) {
      _prefsLoaded = true;
      try {
        final raw = await store.get(_prefsKey);
        if (raw is String) _prefs = VersionsPrefs.fromJson(jsonDecode(raw));
      } catch (_) {}
    }
    return _prefs;
  }

  Future<void> setPrefs(VersionsPrefs p) async {
    _prefs = p;
    _prefsLoaded = true;
    try {
      await store.put(_prefsKey, jsonEncode(p.toJson()));
    } catch (_) {}
    _ping();
  }

  /// Início do período de edição de agora (a primeira edição depois de uma versão ou da abertura).
  DateTime? _baseline;
  bool _autoBusy = false;

  /// Uma edição aconteceu (chamado a cada mudança do documento; barato). Passados os minutos configurados desde o
  /// começo da edição, guarda uma versão automática do estado de agora.
  void noteEdit() {
    if (!_prefs.auto) return;
    final now = clock();
    final base = _baseline ??= now;
    if (_autoBusy || now.difference(base) < Duration(minutes: _prefs.minutes)) return;
    _autoBusy = true;
    _baseline = now;
    unawaited(save(name: 'Versão automática', auto: true).then((_) {}, onError: (_) {}).whenComplete(() => _autoBusy = false));
  }

  /// Ao abrir o projeto: se a versão mais nova (ou a falta de qualquer uma) tem mais de [openGap], guarda uma automática do
  /// que foi aberto, para que a sessão que começa possa voltar ao ponto de partida.
  Future<void> onOpen() async {
    try {
      await prefs();
      if (!_prefs.auto || !hasContent()) return;
      final all = await list();
      final now = clock();
      if (all.items.isNotEmpty && now.difference(all.items.first.createdAt) <= openGap) return;
      await save(name: 'Ao abrir o projeto', auto: true);
    } catch (_) {
      // sem versões automáticas: o projeto abre do mesmo jeito
    }
  }

  void dispose() => changes.close();
}

// ============================================================================ comparar

/// Uma linha do resumo: o que apareceu, sumiu e mudou de um tipo de coisa.
class DiffRow {
  final String what;
  final int added, removed, changed;
  const DiffRow(this.what, this.added, this.removed, this.changed);

  bool get isZero => added == 0 && removed == 0 && changed == 0;

  String get text {
    final parts = <String>[if (added > 0) '+$added', if (removed > 0) '−$removed', if (changed > 0) '$changed ${changed == 1 ? 'mudado' : 'mudados'}'];
    return '$what: ${parts.join(', ')}';
  }
}

/// O resumo do que difere entre duas versões do documento.
class DocDiff {
  final List<DiffRow> rows;

  /// Frases soltas (andamento, compasso, ganho do master…).
  final List<String> notes;
  const DocDiff(this.rows, this.notes);

  bool get isSame => notes.isEmpty && rows.every((r) => r.isZero);
  List<DiffRow> get nonZero => [
    for (final r in rows)
      if (!r.isZero) r,
  ];
}

/// Compara [base] (a versão) com [now] (o projeto de agora), os dois JSON de documento: "adicionados" é o que está em
/// [now] e não em [base]; "removidos", o contrário; "mudados", o que tem o mesmo id e conteúdo diferente.
DocDiff diffDocs(Map<String, dynamic> base, Map<String, dynamic> now) {
  Map<String, Map<String, dynamic>> byId(Iterable<Object?> list, [String Function(Map<String, dynamic>)? key]) {
    final out = <String, Map<String, dynamic>>{};
    for (final e in list) {
      if (e is! Map) continue;
      final m = e.cast<String, dynamic>();
      final k = key != null ? key(m) : '${m['id']}';
      out[k] = m;
    }
    return out;
  }

  DiffRow row(String what, Map<String, Map<String, dynamic>> a, Map<String, Map<String, dynamic>> b) {
    var added = 0, removed = 0, changed = 0;
    for (final e in b.entries) {
      final o = a[e.key];
      if (o == null) {
        added++;
      } else if (jsonEncode(o) != jsonEncode(e.value)) {
        changed++;
      }
    }
    for (final k in a.keys) {
      if (!b.containsKey(k)) removed++;
    }
    return DiffRow(what, added, removed, changed);
  }

  List<Map<String, dynamic>> tracksOf(Map<String, dynamic> d) => [
    for (final t in (d['tracks'] as List? ?? const []))
      if (t is Map) t.cast<String, dynamic>(),
  ];

  // o que cada faixa carrega dentro de si é comparado à parte; a faixa "muda" só pelo que é dela
  const inner = {'clips', 'midi', 'effects', 'sends', 'lanes'};
  Map<String, Map<String, dynamic>> trackShells(Map<String, dynamic> d) => byId([
    for (final t in tracksOf(d))
      {
        for (final e in t.entries)
          if (!inner.contains(e.key)) e.key: e.value,
      },
  ]);

  Map<String, Map<String, dynamic>> inTracks(Map<String, dynamic> d, String field, {List<dynamic>? extra, String Function(Map<String, dynamic>)? key}) {
    final all = <Object?>[];
    for (final t in tracksOf(d)) {
      all.addAll((t[field] as List?) ?? const []);
    }
    if (extra != null) all.addAll(extra);
    return byId(all, key);
  }

  Map<String, Map<String, dynamic>> sends(Map<String, dynamic> d) {
    final out = <String, Map<String, dynamic>>{};
    for (final t in tracksOf(d)) {
      for (final s in (t['sends'] as List?) ?? const []) {
        if (s is Map) out['${t['id']}>${s['target']}'] = s.cast<String, dynamic>();
      }
    }
    return out;
  }

  // notas MIDI: cada nota é (clipe, altura, início, duração, velocidade); mover uma nota é uma removida e uma adicionada
  Map<String, int> notes(Map<String, dynamic> d) {
    final out = <String, int>{};
    for (final t in tracksOf(d)) {
      for (final c in (t['midi'] as List?) ?? const []) {
        if (c is! Map) continue;
        for (final n in (c['notes'] as List?) ?? const []) {
          final k = '${c['id']}|${jsonEncode(n)}';
          out[k] = (out[k] ?? 0) + 1;
        }
      }
    }
    return out;
  }

  final na = notes(base), nb = notes(now);
  var notesAdded = 0, notesRemoved = 0;
  for (final e in nb.entries) {
    final d = e.value - (na[e.key] ?? 0);
    if (d > 0) notesAdded += d;
  }
  for (final e in na.entries) {
    final d = e.value - (nb[e.key] ?? 0);
    if (d > 0) notesRemoved += d;
  }

  final rows = <DiffRow>[
    row('Faixas', trackShells(base), trackShells(now)),
    row('Clipes de áudio', inTracks(base, 'clips'), inTracks(now, 'clips')),
    row('Clipes MIDI', inTracks(base, 'midi'), inTracks(now, 'midi')),
    DiffRow('Notas MIDI', notesAdded, notesRemoved, 0),
    row('Efeitos', inTracks(base, 'effects', extra: base['master_effects'] as List?), inTracks(now, 'effects', extra: now['master_effects'] as List?)),
    row('Envios', sends(base), sends(now)),
    row('Raias de automação', inTracks(base, 'lanes', extra: base['master_lanes'] as List?), inTracks(now, 'lanes', extra: now['master_lanes'] as List?)),
    row('Marcadores', byId(base['markers'] as List? ?? const []), byId(now['markers'] as List? ?? const [])),
  ];

  final notes_ = <String>[];
  void scalar(String key, String label, {String Function(Object?)? fmt}) {
    if (jsonEncode(base[key]) != jsonEncode(now[key])) {
      String f(Object? v) => v == null ? 'nenhum' : (fmt != null ? fmt(v) : (v is num && v == v.roundToDouble() ? '${v.round()}' : '$v'));
      notes_.add('$label: ${f(base[key])} → ${f(now[key])}');
    }
  }

  scalar('bpm', 'Andamento');
  scalar('beats_per_bar', 'Batidas por compasso');
  scalar('tempo_map', 'Mapa de andamento', fmt: (v) => v is List ? _plural(v.length, 'ponto') : '$v');
  scalar('meter_map', 'Mapa de compassos', fmt: (v) => v is List ? _plural(v.length, 'mudança') : '$v');
  scalar('master_gain', 'Volume do master');
  scalar('master_pan', 'Pan do master');
  return DocDiff(rows, notes_);
}

String _plural(int n, String one) => '$n ${n == 1 ? one : (one.endsWith('m') ? '${one.substring(0, one.length - 1)}ns' : '${one}s')}';

/// O texto de várias linhas do resumo de uma comparação ("Igual ao projeto de agora" quando não difere).
String describeDiff(DocDiff d) {
  if (d.isSame) return 'Igual ao projeto de agora.';
  return [...d.nonZero.map((r) => r.text), ...d.notes].join('\n');
}

// ========================================================================= duplicar

/// Cria um projeto novo na conta com o documento de uma versão. Reusa a importação do `.jopendaw`: os áudios não
/// viajam (já estão no guardado local pelo sha-256 e o servidor os recebe na primeira sincronização).
Future<Project> duplicateVersionAsProject({
  required Map<String, dynamic> doc,
  required String name,
  required Iterable<String> existingNames,
  required Future<Project> Function(String name) createProject,
  required Future<Project> Function(String id, Map<String, dynamic> patch) patchProject,
  required Future<void> Function(String id) deleteProject,
  required LocalStore store,
}) {
  final bundle = ProjectBundle(
    name: name,
    format: 1,
    doc: DawDoc.fromJson(jsonDecode(jsonEncode(doc)) as Map<String, dynamic>),
    samples: const {},
    missing: const {},
  );
  return importProjectBundle(
    bundle,
    existingNames: existingNames,
    createProject: createProject,
    patchProject: patchProject,
    deleteProject: deleteProject,
    store: store,
  );
}

/// "17/09/2026 14:05".
String formatStamp(DateTime t) {
  final l = t.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(l.day)}/${two(l.month)}/${l.year} ${two(l.hour)}:${two(l.minute)}';
}

/// "12,4 MB" / "830 KB".
String formatSize(int bytes) => bytes >= 1024 * 1024 ? '${(bytes / 1024 / 1024).toStringAsFixed(1).replaceAll('.', ',')} MB' : '${(bytes / 1024).ceil()} KB';
