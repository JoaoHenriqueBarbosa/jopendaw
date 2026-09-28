import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jopendaw_app/audio/engine.dart';
import 'package:jopendaw_app/daw/controller.dart';
import 'package:jopendaw_app/daw/effects.dart';
import 'package:jopendaw_app/daw/export_options.dart';
import 'package:jopendaw_app/daw/instruments.dart';
import 'package:jopendaw_app/daw/model.dart';
import 'package:jopendaw_app/daw/wav.dart';

import 'fake_engine.dart';

Float32List filled(int n, double v) => Float32List(n)..fillRange(0, n, v);

List<List<Object>> named(List<List<Object>> calls, String name) => [
  for (final c in calls)
    if (c.first == name) c,
];

/// Projeto com uma faixa de áudio (um clipe importado de 2 s em 0), um sintetizador com notas e
/// reverb, e um barramento; loop e metrônomo ligados (não podem ir para o arquivo).
Future<DawController> project(FakeEngine e) async {
  final c = fakeController(e);
  await c.importBytes(
    [
      ('voz.wav', encodeWav([filled(200, 0.25)], 100, ExportFormat.wav32f)),
    ],
    at: 0,
    track: 0,
  );
  c.addInstrumentTrack(TrackKind.synth);
  final clip = c.createMidiClip(1, 4);
  c.edit((_) => clip.notes.add(MidiNote(pitch: 60, start: 0, length: 2)));
  c.addEffect(1, EffectKind.reverb);
  c.addBusTrack();
  c.doc
    ..loopOn = true
    ..loopStart = 8
    ..loopEnd = 12
    ..metronome = true;
  return c;
}

void main() {
  late FakeEngine e;
  setUp(() => e = FakeEngine());

  group('exportar', () {
    test('cancelar: o render para, nada é salvo e não vira aviso de falha', () async {
      final c = await project(e);
      c.cancelRender();
      expect(e.cancels, 0, reason: 'sem render em andamento não há o que cancelar');
      e.renderResult = (outputs) {
        c.cancelRender();
        throw const RenderCanceled();
      };
      await c.exportAudio(const ExportOptions(stems: true));
      expect(e.cancels, 1);
      expect(e.saved, isEmpty);
      expect(c.error, isNull);
      expect(c.rendering, isFalse);
      await c.bounceTrack(1);
      expect(e.cancels, 2);
      expect(c.error, isNull);
      expect(c.doc.tracks, hasLength(3), reason: 'congelamento cancelado não cria faixa');
    });

    test('manda o documento inteiro ao render, sem loop nem metrônomo, e salva a mixagem', () async {
      final c = await project(e);
      e.renderResult = (outputs) => [
        for (final _ in outputs) [filled(300, 0.5), filled(300, -0.25)],
      ];
      final progress = <double>[];
      await c.exportAudio(const ExportOptions(format: ExportFormat.wav24, tail: 1.5), onProgress: progress.add);
      expect(c.error, isNull);
      final r = e.renders.single;
      expect(r.outputs, [-1]);
      expect((r.fromBeat, r.toBeat, r.tailSeconds, r.rate), (0.0, 8.0, 1.5, 100.0));
      final calls = r.calls;
      expect(calls.first, ['tempo', 120.0, 4]);
      expect(named(calls, 'tracks').single, ['tracks', 3]);
      expect(named(calls, 'loop_set').single, ['loop_set', false, 0.0, 0.0]);
      expect(named(calls, 'metronome').single, ['metronome', false, 0.5]);
      expect(named(calls, 'clip_add').single.sublist(0, 4), ['clip_add', 0, 1, 0.0]);
      expect(named(calls, 'track_kind').map((x) => x[2]), [TrackKind.audio.index, TrackKind.synth.index, TrackKind.bus.index]);
      expect(named(calls, 'param'), hasLength(TrackKind.synth.params.length));
      expect(named(calls, 'fx_set').single, ['fx_set', 1, 0, EffectKind.reverb.code]);
      expect(named(calls, 'note_add').single, ['note_add', 1, 4.0, 2.0, 60, 0.8]);
      // nada do que é só do motor ao vivo
      expect(named(calls, 'watch_fx'), isEmpty);
      expect(named(calls, 'watch_analyzer'), isEmpty);
      expect(named(calls, 'input_monitor'), isEmpty);
      expect(r.samples.keys, [1]);
      expect(r.samples[1]!.frames, 200);
      final (name, bytes, mime) = e.saved.single;
      expect((name, mime), ('Teste.wav', 'audio/wav'));
      final wav = decodeWav(bytes);
      expect((wav.bits, wav.sampleRate, wav.frames, wav.channels.length), (24, 100, 300, 2));
      expect(wav.channels[0][10], closeTo(0.5, 2e-6));
      expect(progress.first, closeTo(0.475, 1e-9));
      expect(progress.last, 1);
      // o motor ao vivo segue com o loop e o metrônomo do documento
      expect(c.doc.loopOn, isTrue);
      expect(c.rendering, isFalse);
      expect(c.status, isNull);
    });

    test('stems: uma saída por faixa, nomes pelo projeto e pela faixa, as mudas de fora; normalizar em −1 dBFS', () async {
      final c = await project(e);
      c.doc.tracks[1].name = 'Synth/Lead';
      c.doc.tracks[2].name = 'Synth/Lead';
      e.renderResult = (outputs) => [
        for (final o in outputs)
          switch (o) {
            -1 => [filled(100, 0.5), filled(100, 0.25)],
            0 => [filled(100, 0.1), filled(100, -0.2)],
            1 => [filled(100, 0.3), filled(100, 0.3)],
            // o barramento não recebe nada: silêncio
            _ => [Float32List(100), Float32List(100)],
          },
      ];
      await c.exportAudio(const ExportOptions(format: ExportFormat.wav32f, stems: true, normalize: true));
      expect(e.renders.single.outputs, [-1, 0, 1, 2]);
      expect(e.saved.map((s) => s.$1), ['Teste.wav', 'Teste - Áudio 1.wav', 'Teste - Synth_Lead.wav']);
      final target = dbToGain(-1);
      final mix = decodeWav(e.saved[0].$2);
      expect(mix.channels[0][0], closeTo(target, 1e-6));
      expect(mix.channels[1][0], closeTo(target / 2, 1e-6));
      final voice = decodeWav(e.saved[1].$2);
      expect(voice.channels[1][0], closeTo(-target, 1e-6));
      expect(voice.channels[0][0], closeTo(target / 2, 1e-6));
    });

    test('nomes repetidos ganham número', () async {
      final c = await project(e);
      for (final t in c.doc.tracks) {
        t.name = 'Faixa';
      }
      e.renderResult = (outputs) => [
        for (final _ in outputs) [filled(10, 0.1), filled(10, 0.1)],
      ];
      await c.exportAudio(const ExportOptions(stems: true));
      expect(e.saved.map((s) => s.$1), ['Teste.wav', 'Teste - Faixa.wav', 'Teste - Faixa (2).wav', 'Teste - Faixa (3).wav']);
    });

    test('região do loop e taxa pedida', () async {
      final c = await project(e);
      e.renderResult = (outputs) => [
        for (final _ in outputs) [filled(10, 0.1), filled(10, 0.1)],
      ];
      await c.exportAudio(const ExportOptions(range: ExportRange.loop, format: ExportFormat.wav16, sampleRate: 44100, tail: 0));
      final r = e.renders.single;
      expect((r.fromBeat, r.toBeat, r.tailSeconds, r.rate), (8.0, 12.0, 0.0, 44100.0));
      expect(decodeWav(e.saved.single.$2).sampleRate, 44100);
    });

    test('projeto longo: os stems vão em vários renders, cada um com o que cabe na memória', () async {
      final c = fakeController(e);
      c.addTrack();
      // dez minutos de clipe a 48 kHz: 230 MB por saída, uma por render
      c.doc.tracks[1].clips.add(AudioClip(id: 'x', sample: 'x', start: 0, length: 600));
      e.renderResult = (outputs) => [
        for (final _ in outputs) [filled(10, 0.1), filled(10, 0.1)],
      ];
      await c.exportAudio(const ExportOptions(stems: true, sampleRate: 48000));
      expect(e.renders.map((r) => r.outputs), [
        [-1],
        [0],
        [1],
      ]);
      expect(e.saved, hasLength(3));
      // o áudio do clipe não está neste aparelho: exporta e avisa
      expect(c.error, contains('um áudio que não está'));
    });

    test('vazio, loop sem região, gravando ou render que falha: avisa em error', () async {
      final c = fakeController(e);
      await c.exportAudio(const ExportOptions());
      expect(c.error, contains('vazio'));
      c.doc
        ..loopStart = 4
        ..loopEnd = 4;
      await c.exportAudio(const ExportOptions(range: ExportRange.loop));
      expect(c.error, contains('loop'));
      expect(e.renders, isEmpty);
      final p = await project(e);
      e.renderResult = (_) => throw StateError('o motor do render não carregou.');
      await p.exportAudio(const ExportOptions());
      expect(p.error, 'A exportação não terminou: o motor do render não carregou.');
      expect(p.rendering, isFalse);
      // gravando, nem exporta nem congela
      p.doc.countIn = false;
      p.setArmed(1, true);
      await p.toggleRecord();
      expect(p.recording, isTrue);
      await p.exportAudio(const ExportOptions());
      expect(p.error, contains('Pare a gravação'));
      await p.bounceTrack(1);
      expect(e.renders, hasLength(1));
    });
  });

  group('congelar', () {
    /// Sintetizador (0) com clipe em 4..8, volume 0,5, pan −0,3, automação de volume, envio
    /// pré e pós para o barramento (1); faixa de áudio (2) com compressor de sidechain no
    /// barramento.
    DawController frozenProject() {
      final c = fakeController(e, tracks: []);
      c.addInstrumentTrack(TrackKind.synth);
      final bus = c.addBusTrack();
      c.addTrack();
      final synth = c.doc.tracks[0];
      c.createMidiClip(0, 4).notes.add(MidiNote(pitch: 60, start: 0, length: 4));
      c.addEffect(0, EffectKind.delay);
      c.edit((_) {
        synth
          ..gain = 0.5
          ..pan = -0.3
          ..solo = true
          ..sends.addAll([Send(target: bus.id, level: 0.4, pre: true), Send(target: bus.id, level: 0.6)])
          ..lanes.add(AutoLane(id: 'v', target: const AutoTarget(AutoKind.volume), points: [AutoPoint(beat: 4, value: 0.2), AutoPoint(beat: 8, value: 1)]));
      });
      final comp = c.addEffect(2, EffectKind.compressor);
      c.setEffectParam(2, comp.id, 10, 1, undoable: true);
      return c;
    }

    test('renderiza a faixa com fader em 0 dB e sem solo, e cria a faixa de áudio abaixo', () async {
      final c = frozenProject();
      final base = c.doc.toJson();
      // 2,5 s soando (a cauda do delay passa do fim do clipe, em 2 s) e depois silêncio
      e.renderResult = (outputs) => [
        [Float32List(450)..fillRange(0, 250, 0.3), Float32List(450)..fillRange(0, 250, 0.3)],
      ];
      await c.bounceTrack(0);
      expect(c.error, isNull);
      final r = e.renders.single;
      expect(r.outputs, [0]);
      expect((r.fromBeat, r.toBeat, r.tailSeconds, r.rate), (4.0, 8.0, 8.0, 100.0));
      expect(named(r.calls, 'track').first, ['track', 0, 1.0, 0.0, false, false]);
      expect(named(r.calls, 'track').every((t) => t[5] == false), isTrue, reason: 'nenhuma faixa em solo');
      expect(named(r.calls, 'auto_lane').where((l) => l[1] == 0 && l[2] == 0), isEmpty, reason: 'sem a automação de volume');
      expect(named(r.calls, 'fx_set').first, ['fx_set', 0, 0, EffectKind.delay.code]);

      final tracks = c.doc.tracks;
      expect(tracks, hasLength(4));
      final src = tracks[0], frozen = tracks[1];
      expect(
        (frozen.kind, frozen.name, frozen.gain, frozen.pan, frozen.solo, frozen.color),
        (TrackKind.audio, 'Sintetizador 1 (áudio)', 0.5, -0.3, true, src.color),
      );
      expect(frozen.effects, isEmpty);
      expect(frozen.sends.map((s) => (s.target, s.level, s.pre)), [(tracks[2].id, 0.4, true), (tracks[2].id, 0.6, false)]);
      expect(frozen.lanes.single.target.kind, AutoKind.volume);
      final clip = frozen.clips.single;
      expect((clip.start, clip.length), (4.0, 2.5));
      expect(c.doc.samples[clip.sample]!.name, 'Sintetizador 1 (congelada).wav');
      // esquerda e direita iguais: um canal só
      final audio = e.loaded.values.last;
      expect((audio.channels.length, audio.frames), (1, 250));
      // a original fica muda, sem o envio pré-fader (que seguiria soando e dobraria)
      expect(src.mute, isTrue);
      expect(src.sends.map((s) => s.pre), [false]);
      expect(src.effects, hasLength(1));
      // o sidechain do compressor seguia o barramento, que desceu uma posição
      expect(tracks[3].effects.single.param(10), 2);
      expect(c.selectedTrack, 1);
      c.undo();
      expect(c.doc.toJson(), base);
    });

    test('faixa vazia ou que não soa: avisa e não cria nada', () async {
      final c = frozenProject();
      await c.bounceTrack(2);
      expect(c.error, contains('vazia'));
      expect(e.renders, isEmpty);
      e.renderResult = (outputs) => [
        [Float32List(100), Float32List(100)],
      ];
      await c.bounceTrack(0);
      expect(c.error, contains('não soou'));
      expect(c.doc.tracks, hasLength(3));
    });

    test('barramento congela a música toda', () async {
      final c = frozenProject();
      e.renderResult = (outputs) => [
        [filled(100, 0.2), filled(100, 0.1)],
      ];
      await c.bounceTrack(1);
      final r = e.renders.single;
      expect((r.fromBeat, r.toBeat), (0.0, 8.0));
      expect(r.outputs, [1]);
      expect(c.doc.tracks[2].kind, TrackKind.audio);
      expect(e.loaded.values.last.channels, hasLength(2));
    });
  });
}
