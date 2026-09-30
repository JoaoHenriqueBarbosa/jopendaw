import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jopendaw_app/daw/export_options.dart';
import 'package:jopendaw_app/daw/wav.dart';

String tag(Uint8List b, int o) => String.fromCharCodes(b, o, o + 4);
int u32(Uint8List b, int o) => ByteData.sublistView(b).getUint32(o, Endian.little);
int u16(Uint8List b, int o) => ByteData.sublistView(b).getUint16(o, Endian.little);
int i16(Uint8List b, int o) => ByteData.sublistView(b).getInt16(o, Endian.little);
int i24(Uint8List b, int o) {
  final x = b[o] | (b[o + 1] << 8) | (b[o + 2] << 16);
  return x & 0x800000 != 0 ? x - 0x1000000 : x;
}

Float32List f32(List<double> v) => Float32List.fromList(v);

void main() {
  group('codificar', () {
    test('16 bits: cabeçalho PCM e amostras intercaladas, com teto em ±1', () {
      final l = f32([0, 0.5, 1, 2, double.nan]);
      final r = f32([-0.5, -1, -2, 0.25, 0]);
      final b = encodeWav([l, r], 44100, ExportFormat.wav16, dither: false);
      expect(b.length, 44 + 5 * 4);
      expect(tag(b, 0), 'RIFF');
      expect(u32(b, 4), b.length - 8);
      expect(tag(b, 8), 'WAVE');
      expect(tag(b, 12), 'fmt ');
      expect(u32(b, 16), 16);
      expect(u16(b, 20), 1); // PCM
      expect(u16(b, 22), 2);
      expect(u32(b, 24), 44100);
      expect(u32(b, 28), 44100 * 4);
      expect(u16(b, 32), 4);
      expect(u16(b, 34), 16);
      expect(tag(b, 36), 'data');
      expect(u32(b, 40), 20);
      final samples = [for (var i = 0; i < 10; i++) i16(b, 44 + i * 2)];
      expect(samples, [0, -16384, 16384, -32767, 32767, -32767, 32767, 8192, 0, 0]);
    });

    test('24 bits: três bytes por amostra com sinal, e o byte de enchimento no tamanho ímpar', () {
      final b = encodeWav(
        [
          f32(
            List.filled(3, 0)
              ..[0] = -1
              ..[1] = 0.5,
          ),
        ],
        48000,
        ExportFormat.wav24,
        dither: false,
      );
      // 3 quadros mono de 3 bytes: 9 bytes de dados, mais um de enchimento
      expect(u32(b, 40), 9);
      expect(b.length, 44 + 9 + 1);
      expect(u32(b, 4), b.length - 8);
      expect(u16(b, 32), 3);
      expect(u16(b, 34), 24);
      expect(u32(b, 28), 48000 * 3);
      expect([i24(b, 44), i24(b, 47), i24(b, 50)], [-8388607, 4194304, 0]);
      expect(b.last, 0);
    });

    test('32 bits float: fmt estendido, chunk fact com os quadros e a amostra exata', () {
      final l = f32([0.123456, -1.5, double.infinity]);
      final b = encodeWav([l], 96000, ExportFormat.wav32f);
      expect(u32(b, 16), 18);
      expect(u16(b, 20), 3); // IEEE float
      expect(u16(b, 34), 32);
      expect(u16(b, 36), 0); // cbSize
      expect(tag(b, 38), 'fact');
      expect(u32(b, 42), 4);
      expect(u32(b, 46), 3);
      expect(tag(b, 50), 'data');
      expect(u32(b, 54), 12);
      final data = ByteData.sublistView(b, 58);
      expect(data.getFloat32(0, Endian.little), l[0]);
      // sem teto no float (o motor pode passar de 1 antes do limitador); infinito vira silêncio
      expect(data.getFloat32(4, Endian.little), -1.5);
      expect(data.getFloat32(8, Endian.little), 0);
    });

    test('o dither TPDF fica em ±1 LSB, centrado, e segue a semente', () {
      final n = 20000;
      final x = Float32List(n);
      for (var i = 0; i < n; i++) {
        x[i] = 0.3 * math.sin(i / 7);
      }
      final plain = encodeWav([x], 44100, ExportFormat.wav16, dither: false);
      final a = encodeWav([x], 44100, ExportFormat.wav16, random: math.Random(1));
      final b = encodeWav([x], 44100, ExportFormat.wav16, random: math.Random(1));
      expect(a, b);
      var sum = 0, changed = 0;
      for (var i = 0; i < n; i++) {
        final d = i16(a, 44 + i * 2) - i16(plain, 44 + i * 2);
        expect(d.abs(), lessThanOrEqualTo(1));
        sum += d;
        if (d != 0) changed++;
      }
      expect(sum.abs() / n, lessThan(0.02));
      expect(changed, greaterThan(n ~/ 10));
      // no silêncio o ruído é de um LSB, no máximo
      final quiet = encodeWav([Float32List(1000)], 44100, ExportFormat.wav24, random: math.Random(2));
      for (var i = 0; i < 1000; i++) {
        expect(i24(quiet, 44 + i * 3).abs(), lessThanOrEqualTo(1));
      }
    });

    test('canal a mais ou a menos é erro', () {
      expect(() => encodeWav([], 44100, ExportFormat.wav16), throwsArgumentError);
      expect(() => encodeWav(List.generate(9, (_) => Float32List(1)), 44100, ExportFormat.wav16), throwsArgumentError);
    });
  });

  group('ler', () {
    test('ida e volta em 16, 24 e 32 float', () {
      final l = f32([0, 0.25, -0.75, 0.999]);
      final r = f32([0.5, -0.5, 0.125, -1]);
      for (final f in ExportFormat.values.where((f) => !f.compressed)) {
        final w = decodeWav(encodeWav([l, r], 22050, f, dither: false));
        expect(w.sampleRate, 22050);
        expect(w.bits, f.bits);
        expect(w.float, f == ExportFormat.wav32f);
        expect(w.channels, hasLength(2));
        expect(w.frames, 4);
        // codifica ×32767 e lê ÷32768 (como a libsndfile e o navegador): até 1,5 LSB de diferença
        final lsb = f == ExportFormat.wav32f ? 0.0 : 2 / (f == ExportFormat.wav16 ? 32767 : 8388607);
        for (var i = 0; i < 4; i++) {
          expect(w.channels[0][i], closeTo(l[i], lsb + 1e-7));
          expect(w.channels[1][i], closeTo(r[i], lsb + 1e-7));
        }
      }
    });

    test('pula chunks desconhecidos (com enchimento) e entende o formato extensível', () {
      final pcm = encodeWav(
        [
          f32([0.5, -0.5]),
        ],
        8000,
        ExportFormat.wav16,
        dither: false,
      );
      // um LIST de tamanho ímpar entre o fmt e o data; o fmt vira extensível (subformato PCM)
      final fmt = ByteData(40)
        ..setUint16(0, 0xFFFE, Endian.little)
        ..setUint16(2, 1, Endian.little)
        ..setUint32(4, 8000, Endian.little)
        ..setUint32(8, 16000, Endian.little)
        ..setUint16(12, 2, Endian.little)
        ..setUint16(14, 16, Endian.little)
        ..setUint16(16, 22, Endian.little)
        ..setUint16(18, 16, Endian.little)
        ..setUint32(20, 4, Endian.little)
        ..setUint16(24, 1, Endian.little);
      final body = <int>[
        ...'WAVE'.codeUnits,
        ...'fmt '.codeUnits,
        40,
        0,
        0,
        0,
        ...fmt.buffer.asUint8List(),
        ...'LIST'.codeUnits,
        3,
        0,
        0,
        0,
        1,
        2,
        3,
        0,
        ...pcm.sublist(36),
      ];
      final bytes = Uint8List.fromList([...'RIFF'.codeUnits, ...(ByteData(4)..setUint32(0, body.length, Endian.little)).buffer.asUint8List(), ...body]);
      final w = decodeWav(bytes);
      expect(w.sampleRate, 8000);
      expect(w.channels.single[0], closeTo(0.5, 1e-4));
      expect(w.channels.single[1], closeTo(-0.5, 1e-4));
    });

    test('o que não é WAV simples é FormatException', () {
      expect(() => decodeWav(Uint8List.fromList('não é wav'.codeUnits)), throwsFormatException);
      final adpcm = encodeWav(
        [
          f32([0]),
        ],
        8000,
        ExportFormat.wav16,
        dither: false,
      );
      ByteData.sublistView(adpcm).setUint16(20, 2, Endian.little);
      expect(() => decodeWav(adpcm), throwsFormatException);
    });
  });
}
