/// O arquivo `.jopendaw`: o projeto inteiro (documento e áudios) num zip, para backup, para mover
/// entre contas e aparelhos e para abrir sem servidor.
///
/// Conteúdo do zip:
/// - `project.json`: `{format, name, app_version, exported_at, doc}`, com `doc` no formato de
///   [DawDoc.toJson];
/// - `manifest.json`: `{format, samples: [{hash, size, name, file}], missing: [hash]}`;
/// - `samples/<sha-256>.<ext>`: os áudios usados, um por sha-256 (sem repetição).
///
/// Este arquivo só tem lógica pura (montar, ler, validar, refazer ids); as telas ficam em
/// `project_file_ui.dart`. Nada aqui grava no disco a partir de um nome de dentro do zip: os áudios
/// são procurados pelo nome exato que o manifesto declara e que segue `samples/<64 hexa>.<ext>`.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

import '../audio/engine.dart' show LocalStore;
import '../models/project.dart';
import 'model.dart';

/// Versão do formato do arquivo que este app escreve e sabe ler.
const projectFileFormat = 1;

/// Versão do app gravada no arquivo (informativa).
const projectFileAppVersion = '0.1.0';

const projectFileExtension = 'jopendaw';

/// Limites de leitura (contra arquivos malucos e zip bombs).
class ProjectFileLimits {
  /// Tamanho do arquivo inteiro.
  final int maxFileBytes;

  /// Soma dos tamanhos descomprimidos.
  final int maxTotalBytes;

  /// Um áudio.
  final int maxSampleBytes;

  /// `project.json` e `manifest.json`.
  final int maxJsonBytes;
  final int maxEntries;

  const ProjectFileLimits({
    this.maxFileBytes = 1 << 30,
    this.maxTotalBytes = 2 << 30,
    this.maxSampleBytes = 512 << 20,
    this.maxJsonBytes = 64 << 20,
    this.maxEntries = 20000,
  });
}

/// Problema num arquivo de projeto, com a mensagem pronta para a tela.
class ProjectFileException implements Exception {
  final String message;
  const ProjectFileException(this.message);
  @override
  String toString() => message;
}

/// Um projeto lido de um arquivo, já validado.
class ProjectBundle {
  final String name;
  final int format;
  final String? appVersion;
  final DateTime? exportedAt;
  final DawDoc doc;

  /// sha-256 → bytes, já conferidos.
  final Map<String, Uint8List> samples;

  /// Áudios que o documento cita e o arquivo não traz (o exportador não os tinha).
  final Set<String> missing;

  ProjectBundle({required this.name, required this.format, this.appVersion, this.exportedAt, required this.doc, required this.samples, required this.missing});
}

final _hashRe = RegExp(r'^[0-9a-f]{64}$');
final _sampleFileRe = RegExp(r'^samples/([0-9a-f]{64})\.([a-z0-9]{1,8})$');
const _compressedExts = {'mp3', 'ogg', 'oga', 'flac', 'm4a', 'aac', 'opus', 'webm'};
const _knownExts = {'wav', 'mp3', 'ogg', 'oga', 'flac', 'm4a', 'aac', 'opus', 'webm', 'aif', 'aiff'};

/// Todos os áudios que o documento cita (a lista dele, o sampler e os clipes com suas tomadas).
Set<String> projectHashes(DawDoc d) => {
  ...d.samples.keys,
  for (final t in d.tracks) ...[
    ?t.sample,
    for (final c in t.clips) ...[c.sample, ...c.takes],
  ],
};

String _extFor(String? original) {
  if (original == null) return 'bin';
  final dot = original.lastIndexOf('.');
  if (dot < 0 || dot == original.length - 1) return 'bin';
  final ext = original.substring(dot + 1).toLowerCase();
  return _knownExts.contains(ext) ? ext : 'bin';
}

/// Nome de arquivo seguro para o projeto: sem separadores de caminho nem caracteres que os
/// sistemas de arquivos recusam, com a extensão `.jopendaw`.
String projectFileName(String projectName) {
  var n = projectName.replaceAll(RegExp(r'[\u0000-\u001f\u007f/\\:*?"<>|]'), '_').trim();
  n = n.replaceAll(RegExp(r'^\.+'), '').trim();
  if (n.runes.length > 80) n = String.fromCharCodes(n.runes.take(80)).trim();
  if (n.isEmpty) n = 'projeto';
  return '$n.$projectFileExtension';
}

/// Resultado de [buildProjectFile].
class BuiltProjectFile {
  final Uint8List bytes;

  /// Áudios do documento que [loadSample] não achou: ficaram de fora do arquivo.
  final List<String> missing;

  /// Quantos áudios entraram.
  final int sampleCount;
  const BuiltProjectFile(this.bytes, this.missing, this.sampleCount);
}

/// Monta o zip do projeto. [loadSample] devolve os bytes de um áudio (null se não há em lugar
/// nenhum). O documento é copiado no começo: mexer nele durante a montagem não muda o arquivo.
Future<BuiltProjectFile> buildProjectFile({
  required String name,
  required DawDoc doc,
  required Future<Uint8List?> Function(String hash) loadSample,
  void Function(int done, int total)? onProgress,
  DateTime? now,
}) async {
  final docJson = doc.toJson();
  final hashes = projectHashes(doc).toList()..sort();
  final archive = Archive();
  final entries = <Map<String, Object?>>[];
  final missing = <String>[];
  var done = 0;
  onProgress?.call(0, hashes.length);
  for (final hash in hashes) {
    Uint8List? bytes;
    if (_hashRe.hasMatch(hash)) bytes = await loadSample(hash);
    if (bytes == null) {
      missing.add(hash);
    } else {
      final original = doc.samples[hash]?.name;
      final ext = _extFor(original);
      final file = 'samples/$hash.$ext';
      // áudio comprimido não encolhe: guardar sem gastar tempo
      archive.add(_compressedExts.contains(ext) ? ArchiveFile.noCompress(file, bytes.length, bytes) : ArchiveFile.bytes(file, bytes));
      entries.add({'hash': hash, 'size': bytes.length, 'name': original ?? '', 'file': file});
    }
    onProgress?.call(++done, hashes.length);
    // deixa a tela respirar entre um áudio e outro
    await Future<void>.delayed(Duration.zero);
  }
  final project = {
    'format': projectFileFormat,
    'name': name,
    'app_version': projectFileAppVersion,
    'exported_at': (now ?? DateTime.now()).toUtc().toIso8601String(),
    'doc': docJson,
  };
  final manifest = {'format': projectFileFormat, 'samples': entries, 'missing': missing};
  archive.addFile(ArchiveFile.string('project.json', jsonEncode(project)));
  archive.addFile(ArchiveFile.string('manifest.json', jsonEncode(manifest)));
  return BuiltProjectFile(ZipEncoder().encodeBytes(archive), missing, entries.length);
}

/// Descomprime uma entrada com teto: a leitura para no instante em que passa de [limit] bytes,
/// mesmo que o cabeçalho do zip minta o tamanho.
Uint8List _inflate(ArchiveFile f, int limit, String what) {
  final out = _BoundedOutput(limit);
  try {
    f.writeContent(out, freeMemory: true);
  } on _TooBig {
    throw ProjectFileException('O arquivo é grande demais para abrir ($what passa do limite). Se ele é seu, confira se não está corrompido.');
  }
  return out.getBytes();
}

class _TooBig implements Exception {}

class _BoundedOutput extends OutputMemoryStream {
  final int limit;
  _BoundedOutput(this.limit) : super(size: 1024);

  void _check(int extra) {
    if (length + extra > limit) throw _TooBig();
  }

  @override
  void writeByte(int value) {
    _check(1);
    super.writeByte(value);
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    _check(length ?? bytes.length);
    super.writeBytes(bytes, length: length);
  }

  @override
  void writeStream(InputStream stream) {
    _check(stream.length);
    super.writeStream(stream);
  }
}

bool _hostileName(String n) =>
    n.isEmpty || n.startsWith('/') || n.contains('\\') || n.contains('\u0000') || RegExp(r'^[A-Za-z]:').hasMatch(n) || n.split('/').any((s) => s == '..');

Map<String, dynamic> _jsonObject(Uint8List bytes, String what) {
  try {
    final v = jsonDecode(utf8.decode(bytes));
    if (v is Map<String, dynamic>) return v;
  } catch (_) {
    // cai na mensagem abaixo
  }
  throw ProjectFileException('O arquivo está corrompido: $what não é legível.');
}

/// Lê e valida um arquivo de projeto. Só devolve se tudo confere (formato, nomes, tamanhos, sha-256
/// de cada áudio e o documento); senão lança [ProjectFileException] com a razão em português.
ProjectBundle parseProjectFile(Uint8List bytes, {ProjectFileLimits limits = const ProjectFileLimits()}) {
  if (bytes.isEmpty) throw const ProjectFileException('O arquivo está vazio.');
  if (bytes.length > limits.maxFileBytes) throw const ProjectFileException('O arquivo é grande demais para abrir aqui.');
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    throw const ProjectFileException('Isto não parece um arquivo de projeto do jopendaw (ou ele está truncado ou corrompido).');
  }
  if (archive.length > limits.maxEntries) throw const ProjectFileException('O arquivo tem entradas demais para ser um projeto.');

  final byName = <String, ArchiveFile>{};
  var declared = 0;
  for (final f in archive) {
    if (_hostileName(f.name)) throw const ProjectFileException('O arquivo tem nomes de caminho suspeitos e foi recusado por segurança.');
    if (f.isSymbolicLink) throw const ProjectFileException('O arquivo tem atalhos (links) dentro dele e foi recusado por segurança.');
    if (f.isDirectory) continue;
    if (byName.containsKey(f.name)) throw const ProjectFileException('O arquivo está corrompido: há duas entradas com o mesmo nome.');
    byName[f.name] = f;
    declared += f.size;
    if (declared > limits.maxTotalBytes) throw const ProjectFileException('O conteúdo do arquivo é grande demais para abrir (possível bomba de compressão).');
  }

  final projectEntry = byName['project.json'];
  if (projectEntry == null) throw const ProjectFileException('Isto não parece um arquivo de projeto do jopendaw: falta o project.json.');
  if (projectEntry.size > limits.maxJsonBytes) throw const ProjectFileException('O project.json é grande demais.');
  final project = _jsonObject(_inflate(projectEntry, limits.maxJsonBytes, 'project.json'), 'project.json');

  final format = project['format'];
  if (format is! int || format < 1) throw const ProjectFileException('O arquivo está corrompido: o campo "format" do project.json é inválido.');
  if (format > projectFileFormat) {
    throw ProjectFileException(
      'Este arquivo foi criado por uma versão mais nova do jopendaw (formato $format; esta versão lê até o $projectFileFormat). Atualize o app para abri-lo.',
    );
  }

  final docJson = project['doc'];
  if (docJson is! Map<String, dynamic>) throw const ProjectFileException('O arquivo está corrompido: o project.json não traz o documento.');
  final docVersion = docJson['version'];
  if (docVersion is int && docVersion > DawDoc.version) {
    throw ProjectFileException(
      'O documento do projeto é de uma versão mais nova do jopendaw (documento $docVersion; esta versão lê até o ${DawDoc.version}). Atualize o app.',
    );
  }
  final DawDoc doc;
  try {
    doc = DawDoc.fromJson(docJson);
  } catch (_) {
    throw const ProjectFileException('O arquivo está corrompido: o documento do projeto não pôde ser lido.');
  }

  final manifestEntry = byName['manifest.json'];
  if (manifestEntry == null) throw const ProjectFileException('Isto não parece um arquivo de projeto do jopendaw: falta o manifest.json.');
  if (manifestEntry.size > limits.maxJsonBytes) throw const ProjectFileException('O manifest.json é grande demais.');
  final manifest = _jsonObject(_inflate(manifestEntry, limits.maxJsonBytes, 'manifest.json'), 'manifest.json');

  final samples = <String, Uint8List>{};
  final list = manifest['samples'];
  if (list is! List) throw const ProjectFileException('O arquivo está corrompido: o manifest.json não lista os áudios.');
  var total = 0;
  for (final e in list) {
    if (e is! Map<String, dynamic>) throw const ProjectFileException('O arquivo está corrompido: o manifest.json tem um áudio ilegível.');
    final hash = e['hash'], file = e['file'], size = e['size'];
    if (hash is! String || !_hashRe.hasMatch(hash) || file is! String || size is! int || size < 0) {
      throw const ProjectFileException('O arquivo está corrompido: o manifest.json tem um áudio com dados inválidos.');
    }
    final m = _sampleFileRe.firstMatch(file);
    if (m == null || m.group(1) != hash) {
      throw const ProjectFileException('O arquivo está corrompido: o manifest.json aponta para um caminho de áudio inválido.');
    }
    if (samples.containsKey(hash)) continue;
    final entry = byName[file];
    if (entry == null) throw ProjectFileException('O arquivo está truncado ou incompleto: falta o áudio ${hash.substring(0, 8)}….');
    if (size > limits.maxSampleBytes) throw const ProjectFileException('Um áudio do projeto é grande demais para abrir.');
    final data = _inflate(entry, limits.maxSampleBytes, 'um áudio');
    total += data.length;
    if (total > limits.maxTotalBytes) throw const ProjectFileException('O conteúdo do arquivo é grande demais para abrir (possível bomba de compressão).');
    if (data.length != size) throw ProjectFileException('O arquivo está corrompido: o áudio ${hash.substring(0, 8)}… tem tamanho diferente do declarado.');
    if (sha256.convert(data).toString() != hash) {
      throw ProjectFileException('O arquivo está corrompido: o áudio ${hash.substring(0, 8)}… não confere com o sha-256 dele.');
    }
    samples[hash] = data;
  }

  // o que o documento cita e o arquivo não traz vira "ausente" (o exportador já não o tinha)
  final missing = {
    for (final h in projectHashes(doc))
      if (!samples.containsKey(h)) h,
  };

  final rawName = project['name'];
  final name = rawName is String ? rawName.trim() : '';
  DateTime? at;
  if (project['exported_at'] is String) at = DateTime.tryParse(project['exported_at'] as String);
  return ProjectBundle(
    name: name,
    format: format,
    appVersion: project['app_version'] is String ? project['app_version'] as String : null,
    exportedAt: at,
    doc: doc,
    samples: samples,
    missing: missing,
  );
}

// ------------------------------------------------------------------ ids

final _safeId = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

/// Refaz os ids do documento importado para valer como novo projeto: mantém o id quando ele é
/// seguro (não vazio, só letras, dígitos, `_` e `-`, até 64 caracteres) e único; senão gera um novo.
/// Envios, saídas e automações são reapontados juntos; o que aponta para o que não existe é
/// descartado (envio) ou zerado (saída → master), em vez de sobrar uma referência solta.
void remapDocIds(DawDoc doc) {
  final used = <String>{};
  String fresh() {
    String id;
    do {
      id = newId();
    } while (used.contains(id));
    used.add(id);
    return id;
  }

  String keep(Object? id) {
    if (id is String && _safeId.hasMatch(id) && !used.contains(id)) {
      used.add(id);
      return id;
    }
    return fresh();
  }

  final trackIds = <String, String>{};
  final slotIds = <String, String>{};
  for (final t in doc.tracks) {
    final old = t.id;
    t.id = keep(old);
    trackIds.putIfAbsent(old, () => t.id);
  }
  void slots(List<EffectSlot> list) {
    for (final s in list) {
      final old = s.id;
      s.id = keep(old);
      slotIds.putIfAbsent(old, () => s.id);
    }
  }

  for (final t in doc.tracks) {
    for (final c in t.clips) {
      c.id = keep(c.id);
    }
    for (final c in t.midi) {
      c.id = keep(c.id);
    }
    slots(t.effects);
  }
  slots(doc.masterEffects);
  for (final m in doc.markers) {
    m.id = keep(m.id);
  }

  List<AutoLane> lanes(List<AutoLane> list) {
    final out = <AutoLane>[];
    for (final l in list) {
      final ref = l.target.ref;
      String? newRef = ref;
      if (l.target.kind == AutoKind.effect) {
        newRef = slotIds[ref];
        if (newRef == null) continue;
      } else if (l.target.kind == AutoKind.send) {
        newRef = trackIds[ref];
        if (newRef == null) continue;
      }
      l.id = keep(l.id);
      out.add(
        AutoLane(
          id: l.id,
          target: AutoTarget(l.target.kind, ref: newRef, param: l.target.param),
          points: l.points,
          open: l.open,
        ),
      );
    }
    return out;
  }

  for (final t in doc.tracks) {
    t.sends = [
      for (final s in t.sends)
        if (trackIds.containsKey(s.target)) Send(target: trackIds[s.target]!, level: s.level, pre: s.pre),
    ];
    t.output = t.output == null ? null : trackIds[t.output];
    t.lanes = lanes(t.lanes);
  }
  doc.masterLanes = lanes(doc.masterLanes);
}

// ------------------------------------------------------------------ importar

/// Nome livre para o projeto importado: o do arquivo; com " (importado)" (e um número, se preciso)
/// quando já existe um projeto com esse nome. Sem nome no arquivo vale "Projeto importado".
String importedProjectName(String name, Iterable<String> existing) {
  final taken = {for (final n in existing) n.trim().toLowerCase()};
  var base = name.trim();
  if (base.isEmpty) base = 'Projeto importado';
  String cut(String s) => s.runes.length > 120 ? String.fromCharCodes(s.runes.take(120)) : s;
  base = cut(base);
  if (!taken.contains(base.toLowerCase())) return base;
  for (var i = 1; ; i++) {
    final suffix = i == 1 ? ' (importado)' : ' (importado $i)';
    final room = 120 - suffix.length;
    final stem = base.runes.length > room ? String.fromCharCodes(base.runes.take(room)) : base;
    final candidate = '$stem$suffix';
    if (!taken.contains(candidate.toLowerCase())) return candidate;
  }
}

/// Cria o projeto novo a partir do [bundle] e devolve-o. Nunca mexe num projeto existente. A ordem
/// é a que deixa o pior caso inofensivo: cria o projeto, grava os áudios e só por último o documento
/// (que é o que faz o projeto "existir" para o editor); se algo falha no meio, o projeto criado é
/// apagado (melhor esforço). O envio para o servidor segue o fluxo normal de sincronização na
/// primeira abertura (documento local sem estado de sincronização conta como pendente).
Future<Project> importProjectBundle(
  ProjectBundle bundle, {
  required Iterable<String> existingNames,
  required Future<Project> Function(String name) createProject,
  required Future<Project> Function(String id, Map<String, dynamic> patch) patchProject,
  required Future<void> Function(String id) deleteProject,
  required LocalStore store,
  void Function(int done, int total)? onProgress,
}) async {
  final doc = bundle.doc;
  remapDocIds(doc);
  var project = await createProject(importedProjectName(bundle.name, existingNames));
  try {
    final bpm = doc.bpm.isFinite ? doc.bpm.round().clamp(20, 400) : 120;
    final bpb = doc.beatsPerBar.clamp(1, 32);
    if (bpm != project.bpm || bpb != project.beatsPerBar) {
      project = await patchProject(project.id, {'bpm': bpm, 'beats_per_bar': bpb});
    }
    doc.bpm = project.bpm.toDouble();
    doc.beatsPerBar = project.beatsPerBar;
    final total = bundle.samples.length;
    var done = 0;
    onProgress?.call(0, total);
    for (final e in bundle.samples.entries) {
      final have = await store.get('sample:${e.key}');
      if (have is! Uint8List) await store.put('sample:${e.key}', e.value);
      onProgress?.call(++done, total);
      await Future<void>.delayed(Duration.zero);
    }
    await store.put('doc:${project.id}', jsonEncode(doc.toJson()));
    return project;
  } catch (_) {
    try {
      await deleteProject(project.id);
    } catch (_) {
      // sem como desfazer: o projeto vazio fica na lista e a pessoa apaga
    }
    rethrow;
  }
}
