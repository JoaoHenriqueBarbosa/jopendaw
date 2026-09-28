/// Projetos do DAW, espelhando `server/src/routes/projects.rs`.
library;

class Project {
  final String id, name;
  final int bpm;

  /// Fórmula de compasso: tempos por compasso e a figura do tempo (4/4, 6/8).
  final int beatsPerBar, beatUnit;
  final int sampleRate;
  final DateTime createdAt, updatedAt;

  Project.fromJson(Map<String, dynamic> j)
    : id = j['id'],
      name = j['name'],
      bpm = j['bpm'],
      beatsPerBar = j['beats_per_bar'],
      beatUnit = j['beat_unit'],
      sampleRate = j['sample_rate'],
      createdAt = DateTime.parse(j['created_at']),
      updatedAt = DateTime.parse(j['updated_at']);

  String get meter => '$beatsPerBar/$beatUnit';
}
