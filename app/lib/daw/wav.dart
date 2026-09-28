/// WAV: codifica a mixagem, os stems, as gravações e as faixas congeladas, e lê de volta os
/// arquivos simples (PCM de 8 a 32 bits e float de 32 ou 64).
///
/// Tudo little-endian, amostras intercaladas. 16 e 24 bits levam dither TPDF (ruído triangular de
/// ±1 LSB): sem ele, o arredondamento vira distorção correlacionada com o sinal nos trechos
/// baixos (caudas, fades); com ele, vira um chiado constante e inaudível. O float de 32 bits guarda
/// a amostra do motor como ela é, sem dither nem teto.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'export_options.dart';

const _pcm = 1, _float = 3, _extensible = 0xFFFE;

/// Codifica [channels] (o menor define a duração) num WAV a [sampleRate] no formato dado.
///
/// PCM: a amostra é limitada a ±1 antes de virar inteiro (+1 vira o maior positivo, simétrico ao
/// negativo); NaN e infinito viram silêncio. [dither] desliga o TPDF (testes, material que já é
/// inteiro); [random] fixa a semente.
Uint8List encodeWav(List<Float32List> channels, int sampleRate, ExportFormat format, {bool dither = true, math.Random? random}) {
  if (channels.isEmpty || channels.length > 8) throw ArgumentError.value(channels.length, 'channels', 'de 1 a 8 canais');
  if (sampleRate <= 0) throw ArgumentError.value(sampleRate, 'sampleRate');
  final nch = channels.length;
  final frames = channels.map((c) => c.length).reduce(math.min);
  final isFloat = format == ExportFormat.wav32f;
  final bytes = format.bits ~/ 8;
  final blockAlign = nch * bytes;
  final dataSize = frames * blockAlign;
  // um chunk de tamanho ímpar leva um byte de enchimento (24 bits mono, quadros ímpares)
  final pad = dataSize.isOdd ? 1 : 0;
  // formato não PCM pede o cbSize no fmt e o chunk fact (quadros), pela especificação
  final fmtSize = isFloat ? 18 : 16;
  final header = 12 + 8 + fmtSize + (isFloat ? 12 : 0) + 8;
  final total = header + dataSize + pad;
  if (total - 8 > 0xFFFFFFFF) throw StateError('O arquivo passaria de 4 GB, o limite do WAV: exporte um trecho menor ou em 16 bits.');

  final out = Uint8List(total);
  final b = ByteData.sublistView(out);
  var o = 0;
  void tag(String s) {
    for (var i = 0; i < 4; i++) {
      out[o++] = s.codeUnitAt(i);
    }
  }

  void u32(int v) {
    b.setUint32(o, v, Endian.little);
    o += 4;
  }

  void u16(int v) {
    b.setUint16(o, v, Endian.little);
    o += 2;
  }

  tag('RIFF');
  u32(total - 8);
  tag('WAVE');
  tag('fmt ');
  u32(fmtSize);
  u16(isFloat ? _float : _pcm);
  u16(nch);
  u32(sampleRate);
  u32(sampleRate * blockAlign);
  u16(blockAlign);
  u16(format.bits);
  if (isFloat) {
    u16(0);
    tag('fact');
    u32(4);
    u32(frames);
  }
  tag('data');
  u32(dataSize);

  if (isFloat) {
    for (var i = 0; i < frames; i++) {
      for (var c = 0; c < nch; c++) {
        final v = channels[c][i];
        b.setFloat32(o, v.isFinite ? v : 0, Endian.little);
        o += 4;
      }
    }
    return out;
  }

  final rng = random ?? math.Random();
  final max = format == ExportFormat.wav16 ? 32767 : 8388607;
  final scale = max.toDouble();
  for (var i = 0; i < frames; i++) {
    for (var c = 0; c < nch; c++) {
      var v = channels[c][i].toDouble();
      v = v.isNaN ? 0.0 : v.clamp(-1.0, 1.0);
      var x = v * scale;
      // TPDF: diferença de duas uniformes, triangular em (−1, 1) LSB
      if (dither) x += rng.nextDouble() - rng.nextDouble();
      final q = x.round().clamp(-max - 1, max);
      if (bytes == 2) {
        b.setInt16(o, q, Endian.little);
        o += 2;
      } else {
        out[o++] = q & 0xFF;
        out[o++] = (q >> 8) & 0xFF;
        out[o++] = (q >> 16) & 0xFF;
      }
    }
  }
  return out;
}

/// Um WAV lido: canais em float (−1..1), taxa e o formato de origem.
class WavData {
  final List<Float32List> channels;
  final int sampleRate;
  final int bits;
  final bool float;
  const WavData(this.channels, this.sampleRate, this.bits, {this.float = false});

  int get frames => channels.isEmpty ? 0 : channels.first.length;
}

/// Lê um WAV simples: PCM 8/16/24/32 bits ou float 32/64 (também no formato extensível), pulando
/// os chunks que não interessam. Formato que não é esse: [FormatException].
WavData decodeWav(Uint8List bytes) {
  final b = ByteData.sublistView(bytes);
  String tagAt(int o) => String.fromCharCodes(bytes, o, o + 4);
  if (bytes.length < 12 || tagAt(0) != 'RIFF' || tagAt(8) != 'WAVE') throw const FormatException('Não é um arquivo WAV.');
  int? format, nch, rate, bits;
  int? dataAt, dataSize;
  var o = 12;
  while (o + 8 <= bytes.length) {
    final id = tagAt(o);
    final size = b.getUint32(o + 4, Endian.little);
    final body = o + 8;
    if (id == 'fmt ' && size >= 16 && body + 16 <= bytes.length) {
      format = b.getUint16(body, Endian.little);
      nch = b.getUint16(body + 2, Endian.little);
      rate = b.getUint32(body + 4, Endian.little);
      bits = b.getUint16(body + 14, Endian.little);
      // extensível: o formato de verdade são os dois primeiros bytes do GUID do subformato
      if (format == _extensible && size >= 26 && body + 26 <= bytes.length) format = b.getUint16(body + 24, Endian.little);
    } else if (id == 'data') {
      dataAt = body;
      // arquivo cortado (gravação interrompida): lê o que tem
      dataSize = math.min(size, bytes.length - body);
      break;
    }
    o = body + size + (size.isOdd ? 1 : 0);
  }
  if (format == null || nch == null || rate == null || bits == null || nch == 0) throw const FormatException('WAV sem o chunk fmt.');
  if (dataAt == null || dataSize == null) throw const FormatException('WAV sem o chunk data.');
  final isFloat = format == _float;
  if (!(format == _pcm && (bits == 8 || bits == 16 || bits == 24 || bits == 32)) && !(isFloat && (bits == 32 || bits == 64))) {
    throw FormatException('Formato de WAV não suportado (código $format, $bits bits).');
  }
  final step = bits ~/ 8;
  final frames = dataSize ~/ (step * nch);
  final channels = List.generate(nch, (_) => Float32List(frames));
  var p = dataAt;
  for (var i = 0; i < frames; i++) {
    for (var c = 0; c < nch; c++) {
      final double v;
      if (isFloat) {
        v = bits == 32 ? b.getFloat32(p, Endian.little) : b.getFloat64(p, Endian.little);
      } else {
        v = switch (bits) {
          8 => (bytes[p] - 128) / 128,
          16 => b.getInt16(p, Endian.little) / 32768,
          24 => _int24(bytes, p) / 8388608,
          _ => b.getInt32(p, Endian.little) / 2147483648,
        };
      }
      channels[c][i] = v;
      p += step;
    }
  }
  return WavData(channels, rate, bits, float: isFloat);
}

/// Inteiro de 24 bits com sinal (complemento de dois), sem depender da largura dos inteiros da
/// plataforma (64 bits na VM, 32 nas operações de bits da web).
int _int24(Uint8List bytes, int p) {
  final x = bytes[p] | (bytes[p + 1] << 8) | (bytes[p + 2] << 16);
  return x & 0x800000 != 0 ? x - 0x1000000 : x;
}
