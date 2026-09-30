/// O que exportar e como (contrato da fase 4; a janela e o render ficam em `export.dart`).
library;

enum ExportFormat {
  wav16('WAV 16 bits', 16),
  wav24('WAV 24 bits', 24),
  wav32f('WAV 32 bits float', 32),

  /// Compactado pelo servidor (o WAV é renderizado no aparelho e convertido lá; sem rede cai para WAV).
  flac('FLAC (sem perda, menor)', 24),
  mp3('MP3 (para compartilhar)', 16);

  /// O rótulo; [bits] é a profundidade do WAV renderizado antes de compactar (nos formatos compactados vale só como
  /// padrão: ver [ExportOptions.renderFormat]).
  final String label;
  final int bits;
  const ExportFormat(this.label, this.bits);

  /// O nome curto, para frases ("A mixagem foi salva (MP3)"): o [label] traz um complemento entre
  /// parênteses que, dentro de outros parênteses, ficava duplo.
  String get shortLabel => switch (this) {
    flac => 'FLAC',
    mp3 => 'MP3',
    _ => label,
  };

  /// Passa pelo servidor (FLAC ou MP3).
  bool get compressed => this == flac || this == mp3;

  String get extension => switch (this) {
    flac => 'flac',
    mp3 => 'mp3',
    _ => 'wav',
  };

  String get mime => switch (this) {
    flac => 'audio/flac',
    mp3 => 'audio/mpeg',
    _ => 'audio/wav',
  };
}

/// Nível de compressão do FLAC (o `level` de 0 a 8 do servidor): mais alto = arquivo menor e mais lento.
enum FlacLevel {
  fast('Rápido', 2),
  standard('Padrão', 5),
  smallest('Menor arquivo', 8);

  final String label;
  final int level;
  const FlacLevel(this.label, this.level);
}

/// Qualidade do MP3: taxa constante (CBR) ou variável (VBR, de V0 a V4), como no servidor.
enum Mp3Quality {
  cbr128('128 kbps (CBR)', bitrate: 128),
  cbr192('192 kbps (CBR)', bitrate: 192),
  cbr256('256 kbps (CBR)', bitrate: 256),
  cbr320('320 kbps (CBR)', bitrate: 320),
  vbr0('V0 (VBR, ~245 kbps, a melhor)', vbr: 0),
  vbr1('V1 (VBR, ~225 kbps)', vbr: 1),
  vbr2('V2 (VBR, ~190 kbps)', vbr: 2),
  vbr3('V3 (VBR, ~175 kbps)', vbr: 3),
  vbr4('V4 (VBR, ~165 kbps)', vbr: 4);

  final String label;
  final int? bitrate;
  final int? vbr;
  const Mp3Quality(this.label, {this.bitrate, this.vbr});

  /// Os parâmetros `bitrate` ou `vbr` da tarefa `encode_audio`.
  Map<String, dynamic> get params => {if (bitrate != null) 'bitrate': bitrate, if (vbr != null) 'vbr': vbr};
}

/// O servidor recusa mais que isto por arquivo (`ENCODE_MAX_SECONDS`).
const kEncodeMaxSeconds = 1800.0;

/// O servidor recusa um áudio enviado com mais que isto (`MAX_SAMPLE_BYTES`): o WAV renderizado sobe inteiro, então em
/// taxas e profundidades altas o teto de bytes chega antes dos 30 minutos (cerca de 15 min a 96 kHz e 24 bits).
const kEncodeMaxUploadBytes = 512 * 1024 * 1024;

/// Tamanho do WAV estéreo que o render entrega: cabeçalho de 44 bytes mais os quadros de [seconds] a [rate] Hz com [bits]
/// bits por amostra.
int estimatedWavBytes(double seconds, int rate, int bits) => 44 + (seconds * rate).ceil() * 2 * (bits ~/ 8);

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

  /// Normaliza o loudness integrado da mixagem até este alvo (LUFS, BS.1770-4 / EBU R128); null
  /// desliga. Vale no lugar de [normalize] (o pico): as duas juntas seriam pedidos contrários.
  final double? targetLufs;

  /// Teto de true peak (dBTP) que o ganho do loudness não pode ultrapassar: se subir até o alvo
  /// passaria dele, o ganho para no teto e o resultado fica abaixo do alvo.
  final double ceilingDbtp;

  /// Com [targetLufs], os stems recebem o mesmo ganho da mixagem (o equilíbrio entre eles se
  /// mantém). Sem isto os stems saem como renderizados, sem normalização.
  final bool normalizeStems;

  /// Segundos depois do fim para caudas (reverb, delay, soltura das notas).
  final double tail;

  /// Taxa de amostragem do arquivo (a do motor quando null).
  final int? sampleRate;

  /// FLAC: profundidade (16 ou 24 bits) e nível de compressão.
  final int flacBits;
  final FlacLevel flacLevel;

  /// MP3: taxa constante ou variável.
  final Mp3Quality mp3Quality;

  /// FLAC e MP3: artista nos metadados do arquivo (vazio: sem artista).
  final String artist;

  const ExportOptions({
    this.format = ExportFormat.wav24,
    this.range = ExportRange.song,
    this.stems = false,
    this.normalize = false,
    this.targetLufs,
    this.ceilingDbtp = -1,
    this.normalizeStems = false,
    this.tail = 2,
    this.sampleRate,
    this.flacBits = 24,
    this.flacLevel = FlacLevel.standard,
    this.mp3Quality = Mp3Quality.cbr192,
    this.artist = '',
  });

  /// O formato do WAV que o render entrega: o próprio [format] nos WAV; nos compactados, o que vai ao servidor (16
  /// bits para o MP3, [flacBits] para o FLAC).
  ExportFormat get renderFormat => switch (format) {
    ExportFormat.flac => flacBits == 16 ? ExportFormat.wav16 : ExportFormat.wav24,
    ExportFormat.mp3 => ExportFormat.wav16,
    _ => format,
  };

  /// Os parâmetros da tarefa `encode_audio` (sem os metadados).
  Map<String, dynamic> get encodeParams =>
      format == ExportFormat.mp3 ? {'format': 'mp3', ...mp3Quality.params} : {'format': 'flac', 'bits': flacBits == 16 ? 16 : 24, 'level': flacLevel.level};

  /// Vai normalizar o loudness (há alvo).
  bool get normalizesLoudness => targetLufs != null;
}
