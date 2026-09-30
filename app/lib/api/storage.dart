/// A conta de áudios no servidor (`GET /api/samples`): cota, uso e cada áudio com os projetos que o
/// citam. Um áudio sem projeto nenhum é "sem uso" e pode ser apagado para liberar a cota.
library;

class StoredSample {
  final String hash;

  /// Nome do arquivo, quando algum documento o guarda.
  final String? name;
  final int size;
  final DateTime? createdAt;
  final List<String> projects;

  /// Enviado na última hora: o projeto que o usa pode ainda não ter sincronizado, então "sem uso" pode ser só
  /// aparência.
  final bool recent;

  const StoredSample({required this.hash, required this.size, this.name, this.createdAt, this.projects = const [], this.recent = false});

  bool get unused => projects.isEmpty;

  factory StoredSample.fromJson(Map<String, dynamic> j) => StoredSample(
    hash: j['hash'] as String,
    name: j['name'] as String?,
    size: (j['size'] as num).toInt(),
    createdAt: DateTime.tryParse('${j['created_at']}'),
    projects: [for (final p in (j['projects'] as List? ?? const [])) (p as Map)['name'] as String? ?? ''],
    recent: j['recent'] == true,
  );
}

class StorageUsage {
  final int quotaBytes, usedBytes, unusedBytes, unusedCount;
  final List<StoredSample> samples;

  const StorageUsage({required this.quotaBytes, required this.usedBytes, required this.unusedBytes, required this.unusedCount, this.samples = const []});

  /// 0..1 da cota gasta.
  double get fraction => quotaBytes <= 0 ? 0 : (usedBytes / quotaBytes).clamp(0.0, 1.0);

  factory StorageUsage.fromJson(Map<String, dynamic> j) => StorageUsage(
    quotaBytes: (j['quota_bytes'] as num).toInt(),
    usedBytes: (j['used_bytes'] as num).toInt(),
    unusedBytes: (j['unused_bytes'] as num? ?? 0).toInt(),
    unusedCount: (j['unused_count'] as num? ?? 0).toInt(),
    samples: [for (final s in (j['samples'] as List? ?? const [])) StoredSample.fromJson(s as Map<String, dynamic>)],
  );
}

/// O que a limpeza de áudios sem uso fez. Além dos apagados: os poupados por terem sido enviados na última hora
/// ([skippedRecent]), os que ganharam uso num projeto entre a lista e a conferência ([skippedInUse]) e os com tarefa em
/// andamento ([skippedJob]).
class CleanupResult {
  final int removed, freedBytes, skippedRecent, skippedInUse, skippedJob;
  const CleanupResult(this.removed, this.freedBytes, this.skippedRecent, [this.skippedInUse = 0, this.skippedJob = 0]);

  factory CleanupResult.fromJson(Map<String, dynamic> j) => CleanupResult(
    (j['removed'] as num).toInt(),
    (j['freed_bytes'] as num).toInt(),
    (j['skipped_recent'] as num? ?? 0).toInt(),
    (j['skipped_in_use'] as num? ?? 0).toInt(),
    (j['skipped_job'] as num? ?? 0).toInt(),
  );
}
