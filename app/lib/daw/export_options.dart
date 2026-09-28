/// O que exportar e como (contrato da fase 4; a janela e o render ficam em `export.dart`).
library;

enum ExportFormat {
  wav16('WAV 16 bits', 16),
  wav24('WAV 24 bits', 24),
  wav32f('WAV 32 bits float', 32);

  final String label;
  final int bits;
  const ExportFormat(this.label, this.bits);
}

enum ExportRange {
  /// Do começo até o fim do último clipe (mais a cauda).
  song('Música inteira'),

  /// A região do loop.
  loop('Região do loop');

  final String label;
  const ExportRange(this.label);
}

class ExportOptions {
  final ExportFormat format;
  final ExportRange range;

  /// Um arquivo por faixa (stems) além da mixagem.
  final bool stems;

  /// Normaliza o pico em −1 dBFS (sem passar do teto: o limitador do master continua valendo).
  final bool normalize;

  /// Segundos depois do fim para caudas (reverb, delay, soltura das notas).
  final double tail;

  /// Taxa de amostragem do arquivo (a do motor quando null).
  final int? sampleRate;

  const ExportOptions({
    this.format = ExportFormat.wav24,
    this.range = ExportRange.song,
    this.stems = false,
    this.normalize = false,
    this.tail = 2,
    this.sampleRate,
  });
}
