// Arquivos MIDI (.mid): midi_file.dart (leitura, escrita, ida e volta) e a importação no controlador.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jopendaw_app/daw/instruments.dart';
import 'package:jopendaw_app/daw/midi_file.dart';
import 'package:jopendaw_app/daw/model.dart';
import 'package:jopendaw_app/daw/tempo_map.dart';

import 'fake_engine.dart';

List<int> u32(int v) => [v ~/ 16777216 % 256, v ~/ 65536 % 256, v ~/ 256 % 256, v % 256];
List<int> u16(int v) => [v ~/ 256 % 256, v % 256];

Uint8List smf(int format, int ppq, List<List<int>> tracks, {int? declared}) => Uint8List.fromList([
  ...'MThd'.codeUnits,
  ...u32(6),
  ...u16(format),
  ...u16(declared ?? tracks.length),
  ...u16(ppq),
  for (final t in tracks) ...['MTrk'.codeUnits, u32(t.length), t].expand((e) => e),
]);

const eot = [0, 0xFF, 0x2F, 0];

List<int> vlq(int v) {
  final parts = <int>[v % 128];
  var r = v ~/ 128;
  while (r > 0) {
    parts.add(r % 128 + 128);
    r ~/= 128;
  }
  return parts.reversed.toList();
}

MidiNote note(int pitch, double start, double length, [double velocity = 100 / 127]) =>
    MidiNote(pitch: pitch, start: start, length: length, velocity: velocity);

DawDoc docWith(List<DawTrack> tracks, {double bpm = 120, int bpb = 4}) => DawDoc(bpm: bpm, beatsPerBar: bpb, tracks: tracks);

DawTrack synth(String name, List<MidiClip> clips, {TrackKind kind = TrackKind.synth}) => DawTrack(id: name, name: name, color: 0, kind: kind, midi: clips);

Future<void> expectFails(Uint8List bytes, Pattern message) async {
  try {
    await parseMidiFile(bytes);
    fail('devia falhar');
  } on MidiFormatException catch (e) {
    expect(e.message, matches(message is RegExp ? message : RegExp(RegExp.escape(message as String))));
  }
}

void main() {
  group('leitura à mão', () {
    test('tipo 0: tempo, compasso, nome, running status e note-on velocidade 0', () async {
      final track = [
        0, 0xFF, 0x03, 4, ...'Lead'.codeUnits,
        0, 0xFF, 0x51, 3, 0x07, 0xA1, 0x20, // 500000 µs = 120 BPM
        0, 0xFF, 0x58, 4, 3, 2, 24, 8, // 3/4
        0, 0x90, 60, 100,
        ...vlq(96), 62, 90, // running status: outra nota ligada
        ...vlq(96), 60, 0, // note-on vel 0 = desliga o dó
        ...vlq(96), 62, 0, // e o ré
        ...eot,
      ];
      final d = await parseMidiFile(smf(0, 96, [track]));
      expect(d.format, 0);
      expect(d.ppq, 96);
      expect(d.firstBpm, closeTo(120, 1e-9));
      expect(d.beatsPerBar, 3);
      expect(d.tracks, hasLength(1));
      final t = d.tracks.single;
      expect(t.name, 'Lead');
      expect(t.channel, 0);
      expect(t.notes.map((n) => (n.pitch, n.start, n.length)), [(60, 0.0, 2.0), (62, 1.0, 2.0)]);
      expect(t.notes[0].velocity, 100 / 127);
      expect(d.warnings, isEmpty);
    });

    test('tipo 1: trilha de andamento separada e duas trilhas de notas em canais diferentes', () async {
      final conductor = [0, 0xFF, 0x51, 3, 0x06, 0x1A, 0x80, ...eot]; // 400000 µs = 150 BPM
      final a = [0, 0xFF, 0x03, 2, ...'Bx'.codeUnits, 0, 0x91, 40, 80, 60, 0x81, 40, 0, ...eot];
      final b = [0, 0xC2, 5, 0, 0x92, 72, 64, 30, 0x82, 72, 0, ...eot]; // program change ignorado
      final d = await parseMidiFile(smf(1, 480, [conductor, a, b]));
      expect(d.firstBpm, closeTo(150, 1e-9));
      expect(d.tracks.map((t) => (t.name, t.channel, t.notes.length)), [('Bx', 1, 1), ('', 2, 1)]);
      expect(d.tracks[0].notes.single.length, 60 / 480);
    });

    test('VLQ de 4 bytes (deltas gigantes) e meta de tamanho variável', () async {
      // delta 0x0FFFFFFF ticks = 268435455: chega em 32 bits sem passar do limite do dart2js
      final text = List.filled(200, 65);
      final track = [0, 0xFF, 0x01, ...vlq(200), ...text, 0, 0x90, 60, 64, 0xFF, 0xFF, 0xFF, 0x7F, 0x80, 60, 0, ...eot];
      final d = await parseMidiFile(smf(0, 480, [track]));
      expect(d.tracks.single.notes.single.length, closeTo(268435455 / 480, 1e-6));
    });

    test('sysex, mensagens de sistema e outros eventos são ignorados', () async {
      final track = [
        0, 0xF0, 3, 1, 2, 0xF7, // sysex
        0, 0xF7, 2, 9, 9, // continuação
        0, 0xB0, 7, 100, // volume: ignorado
        0, 0xD0, 50, // pressão do canal
        0, 0xA0, 60, 10, // pressão da nota
        0, 0x90, 60, 64,
        10, 0xF8, // clock: sem dados
        10, 0x80, 60, 0,
        ...eot,
      ];
      final d = await parseMidiFile(smf(0, 480, [track]));
      expect(d.tracks.single.notes.single.length, 20 / 480);
      expect(d.warnings.single, contains('Ignorei 1 evento'));
    });

    test('pitch bend, modulação e pedal viram controles do app', () async {
      final track = [
        0, 0x90, 60, 64,
        0, 0xE0, 0, 0x40, // centro (8192)
        10, 0xE0, 0x7F, 0x7F, // topo (16383)
        10, 0xB0, 1, 127,
        10, 0xB0, 64, 127,
        10, 0xB0, 64, 0,
        10, 0x80, 60, 0,
        ...eot,
      ];
      final t = (await parseMidiFile(smf(0, 480, [track]))).tracks.single;
      expect(t.controls.map((e) => (e.cc, e.beat * 480, e.value)), [
        (ccBend, 0.0, 0.0),
        (ccBend, 10.0, 8191 / 8192),
        (ccMod, 20.0, 1.0),
        (ccSustain, 30.0, 1.0),
        (ccSustain, 40.0, 0.0),
      ]);
    });

    test('notas presas fecham no fim; duração zero ganha um mínimo; fora de ordem não quebra', () async {
      final track = [
        0, 0x90, 60, 64, // nunca desliga
        0, 0x90, 62, 64,
        0, 0x80, 62, 0, // duração zero
        0, 0x80, 70, 0, // desliga nota que nunca ligou
        480 ~/ 128 % 128 + 128, 480 % 128, 0x90, 64, 64, // 480 ticks depois, e termina sem desligar (sem EOT)
      ];
      final d = await parseMidiFile(smf(0, 480, [track]));
      final t = d.tracks.single;
      expect(t.notes.map((n) => n.pitch), [60, 62, 64]);
      expect(t.notes[0].length, 1.0); // fechou no fim da trilha (tick 480)
      expect(t.notes[1].length, midiMinNoteBeats);
      expect(t.notes[2].length, midiMinNoteBeats);
      expect(d.warnings.any((w) => w.contains('2 notas sem desligar')), isTrue);
    });

    test('canal 10 é bateria: notas GM vão para as peças do app e as sem peça avisam', () async {
      final track = [
        0, 0x99, 35, 100, 10, 0x89, 35, 0, // bumbo acústico → bumbo (36)
        0, 0x99, 38, 100, 10, 0x89, 38, 0,
        0, 0x99, 54, 100, 10, 0x89, 54, 0, // pandeiro: o app não tem
        0, 0x99, 58, 100, 10, 0x89, 58, 0, // vibraslap
        ...eot,
      ];
      final d = await parseMidiFile(smf(0, 480, [track]));
      final t = d.tracks.single;
      expect(t.drums, isTrue);
      expect(t.notes.map((n) => n.pitch), [36, 38, 54, 58]);
      expect(d.warnings.any((w) => w.contains('Pandeiro (1)') && w.contains('Vibraslap (1)')), isTrue);
      expect(d.warnings.any((w) => w.contains('1 nota de bateria foram para a peça mais parecida')), isTrue);
      for (var p = 35; p <= 59; p++) {
        // toda nota GM 35–59 ou tem peça ou tem nome para o aviso
        expect(drumPitchForGm(p) != null || gmDrumName(p).isNotEmpty, isTrue);
        final m = drumPitchForGm(p);
        if (m != null) expect(drumNameFor(m), isNotNull);
      }
    });

    test('vários canais numa trilha viram faixas separadas com o canal no nome', () async {
      final track = [0, 0xFF, 3, 2, 80, 88, 0, 0x90, 60, 64, 0, 0x91, 50, 64, 10, 0x80, 60, 0, 0, 0x81, 50, 0, ...eot];
      final d = await parseMidiFile(smf(0, 480, [track]));
      expect(d.tracks.map((t) => t.name), ['PX (canal 1)', 'PX (canal 2)']);
    });

    test('tempo em várias mudanças fica no mapa; o primeiro é o firstBpm', () async {
      final track = [
        0, 0xFF, 0x51, 3, 0x07, 0xA1, 0x20, // 120
        ...vlq(960), 0xFF, 0x51, 3, 0x03, 0xD0, 0x90, // 250000 µs = 240 BPM, batida 2
        0, 0x90, 60, 64, 10, 0x80, 60, 0,
        ...eot,
      ];
      final d = await parseMidiFile(smf(0, 480, [track]));
      expect(d.tempoMap.map((p) => (p.beat, p.bpm)), [(0.0, 120.0), (2.0, 240.0)]);
      expect(d.hasTempoChanges, isTrue);
      expect(d.firstBpm, 120);
    });

    test('compasso 6/8 vira 3/4 no beatsPerBar; 7/8 fica exato no mapa, sem aviso', () async {
      final six = [0, 0xFF, 0x58, 4, 6, 3, 24, 8, 0, 0x90, 60, 64, 5, 0x80, 60, 0, ...eot];
      expect((await parseMidiFile(smf(0, 480, [six]))).beatsPerBar, 3);
      final seven = [0, 0xFF, 0x58, 4, 7, 3, 24, 8, 0, 0x90, 60, 64, 5, 0x80, 60, 0, ...eot];
      final d = await parseMidiFile(smf(0, 480, [seven]));
      expect(d.beatsPerBar, 4);
      expect(d.meterMap, [const MeterChange(1, 7, 8)]);
      expect(d.warnings, isEmpty);
    });

    test('PPQ diferentes: 1, 96, 960 e 32767', () async {
      for (final ppq in [1, 96, 960, 32767]) {
        final track = [0, 0x90, 60, 64, ...vlq(ppq), 0x80, 60, 0, ...eot];
        final d = await parseMidiFile(smf(0, ppq, [track]));
        expect(d.tracks.single.notes.single.length, 1.0, reason: 'ppq $ppq');
      }
    });
  });

  group('arquivos ruins', () {
    test('vazio, não-MIDI, texto e PNG', () async {
      await expectFails(Uint8List(0), 'vazio');
      await expectFails(Uint8List.fromList('Olá, isto não é MIDI, é só texto.'.codeUnits), 'não é um MIDI');
      await expectFails(Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 13, 10, 26, 10, 0, 0, 0, 13]), 'não é um MIDI');
    });

    test('SMPTE é recusado com mensagem', () async {
      final b = smf(0, 0xE728, [
        [0, 0x90, 60, 64, ...eot],
      ]);
      await expectFails(b, 'SMPTE');
    });

    test('PPQ zero, formato desconhecido, cabeçalho cortado, sem faixa, sem nota', () async {
      await expectFails(smf(0, 0, [eot]), '0 pulsos');
      await expectFails(
        Uint8List.fromList([
          ...smf(3, 480, [eot]),
        ]),
        'Formato MIDI 3',
      );
      await expectFails(Uint8List.fromList('MThd'.codeUnits + [0, 0, 0, 6, 0, 1]), 'cortado');
      await expectFails(smf(0, 480, []), 'nenhuma faixa');
      await expectFails(smf(1, 480, [eot]), 'nenhuma nota');
    });

    test('truncado no meio: devolve o que deu, com aviso', () async {
      final full = smf(0, 480, [
        [0, 0x90, 60, 64, 10, 0x80, 60, 0, 0, 0x90, 62, 64, 10, 0x80, 62, 0, ...eot],
      ]);
      final cut = Uint8List.sublistView(full, 0, full.length - 8); // perde metade da segunda nota
      final d = await parseMidiFile(cut);
      expect(d.tracks.single.notes.map((n) => n.pitch), [60, 62]); // a 62 ficou presa e fechou no fim
      expect(d.warnings.any((w) => w.contains('cortado')), isTrue);
    });

    test('lixo dentro da trilha (byte de dado sem status, dado maior que 127) para a trilha sem exceção', () async {
      final bad1 = smf(0, 480, [
        [0, 0x90, 60, 64, 10, 0x80, 60, 0, 5, 0x40, 0x40, 0x40, ...eot],
      ]);
      expect((await parseMidiFile(bad1)).tracks.single.notes, hasLength(1));
      final bad2 = smf(0, 480, [
        [0, 0x90, 60, 64, 10, 0x80, 60, 0, 5, 0x90, 60, 0x90, ...eot],
      ]);
      expect((await parseMidiFile(bad2)).warnings.any((w) => w.contains('cortado ou tem trechos corrompidos')), isTrue);
      // VLQ com 5 bytes de continuação
      final bad3 = smf(0, 480, [
        [0, 0x90, 60, 64, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x7F, 0x80, 60, 0],
      ]);
      expect((await parseMidiFile(bad3)).tracks.single.notes, hasLength(1));
    });

    test('bytes aleatórios depois de um cabeçalho válido nunca lançam exceção que não seja MidiFormatException', () async {
      var seed = 12345;
      int next() => seed = (seed * 1103515245 + 12345) % 2147483648;
      for (var i = 0; i < 300; i++) {
        final body = [for (var k = 0; k < 1 + next() % 60; k++) next() % 256];
        final b = smf(next() % 3, 1 + next() % 960, [body]);
        try {
          await parseMidiFile(b);
        } on MidiFormatException {
          // esperado
        }
      }
    });

    test('RMID (MIDI dentro de RIFF) também abre', () async {
      final inner = smf(0, 480, [
        [0, 0x90, 60, 64, 10, 0x80, 60, 0, ...eot],
      ]);
      final riff = Uint8List.fromList(
        [
          'RIFF'.codeUnits,
          [0, 0, 0, 0],
          'RMID'.codeUnits,
          'data'.codeUnits,
          [0, 0, 0, 0],
          inner,
        ].expand((e) => e).toList(),
      );
      expect((await parseMidiFile(riff)).noteCount, 1);
    });
  });

  group('escrita e ida e volta', () {
    DawDoc sample() {
      final drums = MidiClip(id: 'd', name: 'Kit', start: 4, length: 4, notes: [note(36, 0, 0.5), note(38, 1, 0.25, 1), note(42, 1.5, 0.25, 1 / 127)]);
      final lead = MidiClip(
        id: 'l',
        name: 'Melodia',
        start: 0,
        length: 8,
        notes: [note(60, 0, 1), note(64, 1, 1.5, 64 / 127), note(67, 2.5, 0.75, 127 / 127), note(60, 3.25, 480 / 480)],
        controls: [
          MidiCc(cc: ccBend, beat: 0, value: 0),
          MidiCc(cc: ccBend, beat: 1.5, value: 4096 / 8192),
          MidiCc(cc: ccBend, beat: 2, value: -1),
          MidiCc(cc: ccMod, beat: 0.5, value: 64 / 127),
          MidiCc(cc: ccSustain, beat: 1, value: 1),
          MidiCc(cc: ccSustain, beat: 2, value: 0),
        ],
      );
      return docWith(
        [
          synth('Lead', [lead]),
          synth('Bateria', [drums], kind: TrackKind.drums),
          synth('Vazia', [MidiClip(id: 'v', start: 0, length: 4)]),
        ],
        bpm: 97,
        bpb: 3,
      );
    }

    test('todas as faixas: notas, velocidades, controles, andamento, compasso e nomes voltam iguais', () async {
      final doc = sample();
      final out = buildMidiFile(doc, title: 'Meu projeto');
      expect(out.tracks, 2); // a faixa sem notas fica de fora
      expect(out.notes, 7);
      expect(out.skipped, 0);
      final d = await parseMidiFile(out.bytes);
      expect(d.format, 1);
      expect(d.ppq, 480);
      expect(d.firstBpm, closeTo(97, 0.001));
      expect(d.beatsPerBar, 3);
      expect(d.tracks.map((t) => (t.name, t.channel)), [('Lead', 0), ('Bateria', 9)]);
      final lead = doc.tracks[0].midi.single;
      final back = d.tracks[0];
      expect(back.notes.map((n) => (n.pitch, n.start, n.length, n.velocity)), [for (final n in lead.notes) (n.pitch, n.start, n.length, n.velocity)]);
      final sorted = [...lead.controls]..sort((a, b) => a.beat.compareTo(b.beat)); // a escrita ordena por instante
      expect(back.controls.map((e) => (e.cc, e.beat, e.value)), [for (final e in sorted) (e.cc, e.beat, e.value)]);
      // a bateria mantém a posição absoluta do clipe (começa na batida 4)
      final kit = d.tracks[1];
      expect(kit.notes.map((n) => (n.pitch, n.start, n.length)), [(36, 4.0, 0.5), (38, 5.0, 0.25), (42, 5.5, 0.25)]);
      expect(kit.notes.map((n) => n.velocity), [100 / 127, 1.0, 1 / 127]);
    });

    test('clipe selecionado sai do começo do arquivo, no canal da faixa', () async {
      final doc = sample();
      final out = buildMidiFile(doc, only: doc.tracks[1].midi.single, onlyTrack: doc.tracks[1]);
      final d = await parseMidiFile(out.bytes);
      expect(d.tracks.single.channel, 9);
      expect(d.tracks.single.name, 'Kit');
      expect(d.tracks.single.notes.first.start, 0);
    });

    test('canais: 15 melódicas pulam o 10 e a 16ª volta ao 1', () async {
      final tracks = [
        for (var i = 0; i < 16; i++)
          synth('T$i', [
            MidiClip(id: 'c$i', start: 0, length: 4, notes: [note(60, 0, 1)]),
          ]),
      ];
      final d = await parseMidiFile(buildMidiFile(docWith(tracks)).bytes);
      expect(d.tracks.map((t) => t.channel).toList(), [0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 11, 12, 13, 14, 15, 0]);
    });

    test('notas fora de 0–127 ou fora do clipe ficam de fora; nada para escrever lança mensagem', () async {
      final clip = MidiClip(
        id: 'c',
        start: 0,
        length: 2,
        notes: [note(200, 0, 1), note(-3, 0, 1), note(60, 5, 1), note(60, -1, 1), note(61, 0, 0), note(62, 1, 1)],
      );
      final out = buildMidiFile(
        docWith([
          synth('S', [clip]),
        ]),
      );
      expect(out.skipped, 4);
      final d = await parseMidiFile(out.bytes);
      expect(d.tracks.single.notes.map((n) => n.pitch), [61, 62]);
      expect(d.tracks.single.notes.first.length, 1 / 480);
      expect(() => buildMidiFile(docWith([synth('S', [])])), throwsA(isA<MidiFormatException>()));
    });

    test('notas na mesma nota emendadas (fim = início da próxima) não se fundem', () async {
      final clip = MidiClip(id: 'c', start: 0, length: 4, notes: [note(60, 0, 1), note(60, 1, 1)]);
      final d = await parseMidiFile(
        buildMidiFile(
          docWith([
            synth('S', [clip]),
          ]),
        ).bytes,
      );
      expect(d.tracks.single.notes.map((n) => (n.start, n.length)), [(0.0, 1.0), (1.0, 1.0)]);
    });

    test('nome de arquivo', () {
      expect(midiFileName('Minha/música: 1'), 'Minha_música_ 1.mid');
      expect(midiFileName('  '), 'notas.mid');
      expect(midiFileName('a' * 200).length, 84);
    });
  });

  group('mapa de andamento e de compassos', () {
    DawDoc mapDoc({List<TempoPoint>? tempo, List<MeterChange>? meter, double start = 0}) => DawDoc(
      bpm: 100,
      beatsPerBar: 4,
      tempoMap: tempo,
      meterMap: meter,
      tracks: [
        synth('Lead', [
          MidiClip(id: 'l', start: start, length: 32, notes: [note(60, 0, 1), note(62, 10.25, 0.5)]),
        ]),
      ],
    );

    test('salto, rampa e compassos voltam iguais', () async {
      final tempo = const [TempoPoint(0, 100), TempoPoint(4, 150), TempoPoint(8, 90, ramp: true), TempoPoint(16, 140)];
      final meter = const [MeterChange(1, 4, 4), MeterChange(3, 6, 8), MeterChange(5, 7, 8)];
      final doc = mapDoc(tempo: tempo, meter: meter);
      final out = buildMidiFile(doc);
      final d = await parseMidiFile(out.bytes);
      // a rampa 90 → 140 em 8 batidas vira degraus de 1/16 de batida
      expect(d.tempoMap.length, greaterThan(128));
      expect(d.tempoMap.length, lessThan(140));
      expect(d.meterMap, meter);
      expect(d.warnings, isEmpty);
      final back = TempoMap(d.tempoPoints.first.bpm, d.tempoPoints);
      for (final b in [0.0, 2.0, 4.0, 4.5, 8.0, 10.0, 12.5, 15.99, 16.0, 20.0, 40.0]) {
        expect(back.secondsAt(b), closeTo(doc.tempo.secondsAt(b), 0.015), reason: 'batida $b');
      }
      // e importar leva tudo para o projeto
      final c = fakeController(FakeEngine());
      await c.importMidiBytes('mapa.mid', out.bytes, confirmTempo: (_) async => true);
      expect(c.doc.meterMap, meter);
      expect(c.doc.bpm, 100);
      expect(c.doc.tempoMap.first, const TempoPoint(0, 100));
      expect(c.doc.tempoMap[1], const TempoPoint(4, 150));
    });

    test('um andamento e um compasso só: um evento de cada, como antes', () async {
      final d = await parseMidiFile(buildMidiFile(mapDoc()).bytes);
      expect(d.tempoMap.length, 1);
      expect(d.tempoMap.single.bpm, closeTo(100, 0.001));
      expect(d.meterMap, const [MeterChange(1, 4, 4)]);
    });

    test('clipe avulso leva o andamento e o compasso que valiam no começo dele', () async {
      final doc = mapDoc(
        start: 8,
        tempo: const [TempoPoint(0, 100), TempoPoint(4, 200), TempoPoint(12, 60)],
        meter: const [MeterChange(1, 4, 4), MeterChange(3, 3, 4), MeterChange(5, 6, 8)],
      );
      final clip = doc.tracks.single.midi.single;
      final d = await parseMidiFile(buildMidiFile(doc, only: clip, onlyTrack: doc.tracks.single).bytes);
      // o clipe começa na batida 8 (200 BPM, compasso 3/4 até o compasso 5 = batida 14)
      expect(d.tempoMap.map((p) => (p.beat, p.bpm.round())), [(0.0, 200), (4.0, 60)]);
      expect(d.meterMap, const [MeterChange(1, 3, 4), MeterChange(3, 6, 8)]);
    });

    test('sem dart2js quebrando: nenhum deslocamento de bits no arquivo MIDI', () {
      // o teste geral que varre o código cobre o resto; aqui só o VLQ de um andamento longo
      final doc = mapDoc(tempo: const [TempoPoint(0, 100), TempoPoint(100000, 200)]);
      expect(() => buildMidiFile(doc), returnsNormally);
    });
  });

  group('desempenho', () {
    test('100 mil notas: escrita e leitura rápidas, e a leitura cede o controle ao laço de eventos', () async {
      final notes = [for (var i = 0; i < 100000; i++) note(24 + i % 90, i * 0.25, 0.2, (1 + i % 127) / 127)];
      final doc = docWith([
        synth('Grande', [MidiClip(id: 'g', start: 0, length: 100000 * 0.25 + 1, notes: notes)]),
      ]);
      final sw = Stopwatch()..start();
      final out = buildMidiFile(doc);
      final wrote = sw.elapsedMilliseconds;
      var yields = 0;
      var running = true;
      // um cronômetro de microtarefas: só avança se a leitura ceder o controle
      final ticker = () async {
        while (running) {
          await Future<void>.delayed(Duration.zero);
          yields++;
        }
      }();
      final d = await parseMidiFile(out.bytes, yieldEvery: 2000);
      running = false;
      await ticker;
      expect(d.noteCount, 100000);
      expect(yields, greaterThan(50));
      expect(d.tracks.single.notes[99999].pitch, notes[99999].pitch);
      expect(wrote + sw.elapsedMilliseconds, lessThan(20000));
    });
  });

  group('importação no controlador', () {
    Future<Uint8List> file({int bpm = 90}) async {
      final us = 60000000 ~/ bpm;
      final conductor = [0, 0xFF, 0x51, 3, us ~/ 65536 % 256, us ~/ 256 % 256, us % 256, 0, 0xFF, 0x58, 4, 3, 2, 24, 8, ...eot];
      final a = [0, 0xFF, 3, 5, ...'Piano'.codeUnits, 0, 0x90, 60, 64, ...vlq(2000), 0x80, 60, 0, ...eot];
      final b = [0, 0x99, 36, 100, 10, 0x89, 36, 0, ...eot];
      return smf(1, 480, [conductor, a, b]);
    }

    test('cria faixa de sintetizador e de bateria com um clipe cada, e aceita o andamento', () async {
      final c = fakeController(FakeEngine());
      final before = c.doc.tracks.length;
      final r = await c.importMidiBytes('x.mid', await file(), confirmTempo: (_) async => true, at: 0);
      expect(r, isNotNull);
      expect(r!.tracks, 2);
      expect(r.notes, 2);
      expect(r.tempoApplied, isTrue);
      expect(c.doc.bpm, 90);
      expect(c.doc.beatsPerBar, 3);
      final added = c.doc.tracks.sublist(before);
      expect(added.map((t) => (t.name, t.kind)), [('Piano', TrackKind.synth), ('Bateria 1', TrackKind.drums)]);
      expect(added.every((t) => t.midi.length == 1 && t.midi.single.start == 0), isTrue);
      // 2000/480 = 4,17 batidas em compassos de 3: fecha em 6
      expect(added[0].midi.single.length, 6);
      expect(c.status, isNull);
      c.undo();
      expect(c.doc.tracks.length, before);
      expect(c.doc.bpm, 120); // desfazer volta o andamento junto
    });

    test('recusar o andamento deixa o do projeto; sem pergunta quando é igual', () async {
      final c = fakeController(FakeEngine());
      var asked = 0;
      final r = await c.importMidiBytes('x.mid', await file(), confirmTempo: (_) async => ++asked < 0);
      expect(r!.tempoApplied, isFalse);
      expect(c.doc.bpm, 120);
      expect(c.doc.beatsPerBar, 4);
      final c2 = fakeController(FakeEngine());
      await c2.importMidiBytes('y.mid', await file(bpm: 120), confirmTempo: (d) async => ++asked > 0 && d.beatsPerBar == 3);
      expect(asked, 2); // 3/4 ainda difere do projeto: pergunta
    });

    Uint8List midTempoFile() {
      final track = [0, 0xFF, 0x51, 3, 0x07, 0xA1, 0x20, 0, 0x90, 60, 64, ...vlq(480), 0xFF, 0x51, 3, 0x03, 0xD0, 0x90, ...vlq(10), 0x80, 60, 0, ...eot];
      return smf(0, 480, [track]);
    }

    test('andamento no meio do arquivo vira o mapa do projeto, sem o aviso antigo', () async {
      final c = fakeController(FakeEngine());
      var changes = -1;
      final r = await c.importMidiBytes(
        't.mid',
        midTempoFile(),
        confirmTempo: (d) async {
          changes = d.tempoPoints.length - 1;
          return true;
        },
      );
      expect(changes, 1);
      expect(r!.tempoApplied, isTrue);
      expect(c.doc.bpm, 120);
      expect(c.doc.tempoMap, const [TempoPoint(0, 120), TempoPoint(1, 240)]);
      expect(r.warnings.any((w) => w.contains('primeiro') || w.contains('ignoradas') || w.contains('muda de andamento')), isFalse);
      // 1 batida a 120 (0,5 s) e 1 a 240 (0,25 s)
      expect(c.doc.tempo.secondsAt(2), closeTo(0.75, 1e-9));
      c.undo();
      expect(c.doc.tempoMap, isEmpty);
    });

    test('recusar o mapa do arquivo avisa que ficou o andamento do projeto', () async {
      final c = fakeController(FakeEngine());
      final r = await c.importMidiBytes('t.mid', midTempoFile(), confirmTempo: (_) async => false);
      expect(r!.tempoApplied, isFalse);
      expect(c.doc.tempoMap, isEmpty);
      expect(r.warnings.any((w) => w.contains('mantive')), isTrue);
    });

    test('arquivo com dezenas de milhares de eventos de andamento é simplificado para caber', () async {
      final ev = <int>[];
      for (var i = 0; i < 30000; i++) {
        final bpm = 100 + 40 * i / 30000;
        final us = (60000000 / bpm).round();
        ev.addAll([...vlq(i == 0 ? 0 : 1), 0xFF, 0x51, 3, us ~/ 65536 % 256, us ~/ 256 % 256, us % 256]);
      }
      final track = [...ev, 0, 0x90, 60, 64, ...vlq(10), 0x80, 60, 0, ...eot];
      final bytes = smf(0, 480, [track]);
      final data = await parseMidiFile(bytes);
      expect(data.tempoMap.length, 30000);
      expect(data.tempoPoints.length, lessThanOrEqualTo(midiMaxTempoPoints));
      expect(data.tempoPoints.length, greaterThan(50));
      expect(data.tempoPoints.first.bpm, closeTo(100, 0.01));
      expect(data.tempoPoints.last.bpm, closeTo(140, 0.5));
      final c = fakeController(FakeEngine());
      final r = await c.importMidiBytes('rampa.mid', bytes, confirmTempo: (_) async => true);
      expect(c.doc.tempoMap.length, lessThanOrEqualTo(midiMaxTempoPoints));
      expect(r!.warnings.any((w) => w.contains('fundi')), isTrue);
    });

    test('poucos pontos com diferenças pequenas: funde só as menores que 0,05 BPM', () {
      final pts = simplifyTempo([
        const MidiTempoPoint(0, 120),
        const MidiTempoPoint(1, 120.02),
        const MidiTempoPoint(2, 120.04),
        const MidiTempoPoint(3, 120.06), // 0,06 acima do último mantido: fica
        const MidiTempoPoint(4, 90),
      ]);
      expect(pts.map((p) => p.beat), [0, 3, 4]);
      expect(simplifyTempo(const []), isEmpty);
      // primeiro andamento depois do começo: 120 antes dele
      expect(simplifyTempo(const [MidiTempoPoint(4, 90)]).map((p) => (p.beat, p.bpm)), [(0.0, 120.0), (4.0, 90.0)]);
    });

    test('compassos do arquivo (6/8 no compasso 3, 7/8 depois) entram no mapa do projeto', () async {
      final conductor = [
        0, 0xFF, 0x58, 4, 4, 2, 24, 8, //
        ...vlq(3840), 0xFF, 0x58, 4, 6, 3, 24, 8, // batida 8 = compasso 3
        ...vlq(2880), 0xFF, 0x58, 4, 7, 3, 24, 8, // + 6 batidas = compasso 5
        ...eot,
      ];
      final notes = [0, 0x90, 60, 64, 10, 0x80, 60, 0, ...eot];
      final c = fakeController(FakeEngine());
      final r = await c.importMidiBytes('m.mid', smf(1, 480, [conductor, notes]), confirmTempo: (_) async => true);
      expect(r!.warnings, isEmpty);
      expect(c.doc.meterMap, const [MeterChange(1, 4, 4), MeterChange(3, 6, 8), MeterChange(5, 7, 8)]);
      expect(c.doc.beatsPerBar, 4);
      expect(c.doc.meter.barStart(5), 14);
    });

    test('compasso no meio de um compasso alinha e avisa', () async {
      final conductor = [0, 0xFF, 0x58, 4, 4, 2, 24, 8, ...vlq(2400), 0xFF, 0x58, 4, 3, 2, 24, 8, ...eot]; // batida 5
      final d = await parseMidiFile(
        smf(1, 480, [
          conductor,
          [0, 0x90, 60, 64, 10, 0x80, 60, 0, ...eot],
        ]),
      );
      expect(d.meterMap.length, 2);
      expect(d.warnings.any((w) => w.contains('meio de um compasso')), isTrue);
    });

    test('arquivo ruim vira erro legível e não mexe no documento', () async {
      final c = fakeController(FakeEngine());
      final before = c.doc.tracks.length;
      final r = await c.importMidiBytes('lixo.mid', Uint8List.fromList([1, 2, 3, 4, 5]));
      expect(r, isNull);
      expect(c.error, contains('lixo.mid'));
      expect(c.error, contains('não é um MIDI'));
      expect(c.doc.tracks.length, before);
      expect(c.status, isNull);
    });
  });
}
