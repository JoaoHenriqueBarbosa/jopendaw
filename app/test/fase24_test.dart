// Fase 24: clipes em loop/mudo/fase, congelar faixa e achados da fase 21. Cada teste confirma o defeito e a correção.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jopendaw_app/daw/audio_edit.dart';
import 'package:jopendaw_app/daw/controller.dart';
import 'package:jopendaw_app/daw/effects.dart';
import 'package:jopendaw_app/daw/export_options.dart';
import 'package:jopendaw_app/daw/freeze.dart';
import 'package:jopendaw_app/daw/instruments.dart';
import 'package:jopendaw_app/daw/model.dart';
import 'package:jopendaw_app/daw/modulation.dart';
import 'package:jopendaw_app/daw/user_presets.dart';
import 'package:jopendaw_app/daw/wav.dart';

import 'fake_engine.dart';

/// Um clipe de 2 s (200 quadros a 100 Hz).
Float32List ramp() => Float32List.fromList([for (var i = 0; i < 200; i++) i / 199]);

Future<(DawController, AudioClip)> project(FakeEngine e) async {
  final c = fakeController(e);
  c.warpDebounce = Duration.zero;
  await c.importBytes([('a.wav', encodeWav([ramp()], 100, ExportFormat.wav32f))], at: 0, track: 0);
  return (c, c.doc.tracks[0].clips.single);
}

List<List<Object>> clipsOf(DawController c) => [
  for (final x in c.debugFullSyncCalls())
    if (x.first == 'clip_add') x,
];

Float32List filled(int n, double v) => Float32List(n)..fillRange(0, n, v);

void main() {
  late FakeEngine e;
  setUp(() => e = FakeEngine());

  group('clipe em loop', () {
    /// A posição da origem (s) que o clipe toca no instante [t] (s), olhando os clip_add do motor (bpm 120: 1 beat = 0,5 s).
    double? sourceAt(DawController c, double t) {
      for (final x in clipsOf(c)) {
        final start = (x[3] as double) * 0.5, len = x[5] as double;
        if (t >= start - 1e-9 && t < start + len - 1e-9) return (x[4] as double) + (t - start);
      }
      return null;
    }

    test('(1) aparar o começo de um clipe em loop coberto por outro respeita a fase do loop', () async {
      final (c, clip) = await project(e);
      c.edit((d) {
        d.bpm = 120;
        clip.length = 2.0;
        clip.loopLength = 0.5;
      });
      final before = [for (var i = 0; i < 24; i++) sourceAt(c, 0.8 + i * 0.05)];
      // um clipe por cima cobre os primeiros 0,75 s (1,5 batida): a fase do loop cai no meio de uma repetição
      c.edit((d) {
        d.tracks[0].clips.add(AudioClip(id: 'top', sample: clip.sample, start: 0, length: 0.75, offset: 1.0));
        c.placeOnTop('top');
      });
      final rest = c.doc.tracks[0].clips.where((x) => x.id != 'top').toList()..sort((a, b) => a.start.compareTo(b.start));
      expect(rest.first.start, 1.5);
      expect(rest.first.offset, closeTo(0.25, 1e-9), reason: 'offset módulo o trecho, não 0,75');
      expect(rest.first.length, closeTo(0.25, 1e-9));
      expect(rest.first.loopLength, isNull);
      expect(rest.last.offset, 0.0);
      expect(rest.last.loopLength, 0.5);
      expect(rest.fold<double>(0, (s, x) => s + x.length), closeTo(1.25, 1e-9));
      // o som depois do trecho coberto é o mesmo de antes (os clipes do motor da faixa 0 incluem o de cima, que termina em 0,75 s)
      for (var i = 0; i < before.length; i++) {
        final t = 0.8 + i * 0.05;
        expect(sourceAt(c, t), closeTo(before[i]!, 1e-6), reason: 't=$t');
      }
    });

    test('(1) o de baixo parte em dois: a direita mantém a fase e o loop recomeça do trecho inteiro', () async {
      final (c, clip) = await project(e);
      c.edit((d) {
        d.bpm = 120;
        clip.length = 2.0;
        clip.loopLength = 0.5;
      });
      c.edit((d) {
        d.tracks[0].clips.add(AudioClip(id: 'top', sample: clip.sample, start: 1.0, length: 0.75, offset: 1.0));
        c.placeOnTop('top');
      });
      // [0,5 s; 1,25 s) coberto: sobra 0..0,5 s, e depois 1,25 s (fase 0,25 da repetição)
      final pieces = c.doc.tracks[0].clips.where((x) => x.id != 'top').toList()..sort((a, b) => a.start.compareTo(b.start));
      expect(pieces.first.length, closeTo(0.5, 1e-9));
      expect(pieces[1].start, closeTo(2.5, 1e-9));
      expect(pieces[1].offset, closeTo(0.25, 1e-9));
      expect(pieces[1].length, closeTo(0.25, 1e-9));
      expect(pieces.last.offset, 0.0);
      expect(pieces.last.loopLength, 0.5);
      expect(pieces.last.length, closeTo(0.5, 1e-9));
    });

    test('(2) reverso com loop: a última repetição parcial toca o começo do trecho invertido', () async {
      final (c, clip) = await project(e);
      c.edit((d) {
        d.bpm = 120;
        clip.offset = 0.5;
        clip.length = 1.25;
        clip.loopLength = 0.5;
      });
      c.setClipWarp(clip.id, reverse: true);
      await c.debugSettleWarp();
      final calls = clipsOf(c);
      expect(calls, hasLength(3));
      expect([for (final x in calls) x[5]], [0.5, 0.5, 0.25]);
      // o trecho [0,5 s; 1 s) invertido começa em 2 - 1 = 1 s do derivado: a parcial também começa ali
      expect([for (final x in calls) x[4]], [1.0, 1.0, 1.0]);
    });

    test('(3) dividir, remover silêncio e quantizar recusam clipe em loop; converter em notas também', () async {
      final (c, clip) = await project(e);
      c.edit((_) {
        clip.length = 2.0;
        clip.loopLength = 0.5;
      });
      expect(sliceEditBlocker(clip), contains('loop'));
      expect(c.splitClipAt(clip.id, [0.3]).ok, isFalse);
      expect(c.splitClipAt(clip.id, [0.3]).message, contains('loop'));
      expect(c.stripClipSilence(clip.id, const SilenceSettings()).message, contains('loop'));
      expect(c.quantizeClipSlices(clip.id, const QuantizeSettings()).message, contains('loop'));
      await expectLater(c.convertToMidi(clip.id), throwsA(isA<StateError>().having((x) => x.message, 'message', contains('loop'))));
      // sem loop de fato (não passa do trecho) é um clipe comum
      c.edit((_) => clip.length = 0.5);
      expect(sliceEditBlocker(clip), isNull);
    });

    test('(4) fade maior que a repetição é limitado a ela (sem degrau na emenda)', () async {
      final (c, clip) = await project(e);
      c.edit((d) {
        d.bpm = 120;
        clip.length = 1.25;
        clip.loopLength = 0.5;
        clip.fadeIn = 1.2;
        clip.fadeOut = 0.9;
      });
      final calls = clipsOf(c);
      expect(calls.first[7], 0.5);
      expect(calls.last[8], 0.25, reason: 'a última repetição só tem 0,25 s');
      expect(calls[1][7], 0.0);
    });

    test('(5) mudo e fase valem gravando (não mudam som derivado nem clipes): documentado, sem bloqueio', () async {
      final (c, clip) = await project(e);
      c.setClipMuted(clip.id, true);
      c.setClipInvert(clip.id, true);
      expect((clip.muted, clip.invert), (true, true));
    });

    test('(7) o passo do histórico diz o que mudou no warp', () async {
      final (c, clip) = await project(e);
      c.setClipWarp(clip.id, reverse: true);
      expect(c.nextUndo!.label, 'Inverter o áudio do clipe');
      c.setClipWarp(clip.id, pitch: 3);
      expect(c.nextUndo!.label, 'Mudar a altura do clipe');
      c.setClipWarp(clip.id, warp: true, sourceBpm: 100);
      expect(c.nextUndo!.label, 'Esticar o clipe no tempo');
      c.setClipWarp(clip.id, sourceBpm: 90);
      expect(c.nextUndo!.label, 'Ajustar o andamento do clipe');
      c.setClipWarp(clip.id, warp: false);
      expect(c.nextUndo!.label, 'Desligar o warp do clipe');
    });

    test('(8) o teto de repetições avisa uma vez e volta a avisar depois de voltar ao limite', () async {
      final (c, clip) = await project(e);
      c.edit((_) => clip.length = 1.0);
      c.setClipLoop(clip.id, true);
      c.edit((_) => clip.loopLength = 0.0001);
      expect(clip.loopCapped, isTrue);
      expect(c.notice, contains('$maxLoopRepeats'));
      c.clearNotice();
      c.edit((_) => clip.fadeIn = 0.01);
      expect(c.notice, isNull, reason: 'não repete a cada edição');
      c.edit((_) => clip.loopLength = 0.5);
      expect(clip.loopCapped, isFalse);
    });
  });

  group('congelar', () {
    DawController frozenProject() {
      final c = fakeController(e, tracks: []);
      c.addInstrumentTrack(TrackKind.synth);
      c.addBusTrack();
      c.addTrack();
      c.createMidiClip(0, 4).notes.add(MidiNote(pitch: 60, start: 0, length: 4));
      c.addEffect(0, EffectKind.delay);
      e.renderResult = (outputs) => [
        [filled(250, 0.3), filled(250, 0.3)],
      ];
      return c;
    }

    test('(1) a impressão do som inclui a automação e a modulação de instrumento e efeitos, e não a de volume', () {
      final c = frozenProject();
      final t = c.doc.tracks[0];
      final base = soundFingerprint(t);
      final fx = t.effects.first;
      t.lanes.add(AutoLane(id: 'f', target: AutoTarget(AutoKind.effect, ref: fx.id, param: 0), points: [AutoPoint(beat: 0, value: 0.1)]));
      final withLane = soundFingerprint(t);
      expect(withLane, isNot(base));
      t.lanes.first.points.first.value = 0.7;
      expect(soundFingerprint(t), isNot(withLane));
      final v = soundFingerprint(t);
      t.lanes.add(AutoLane(id: 'v', target: const AutoTarget(AutoKind.volume), points: [AutoPoint(beat: 0, value: 0.5)]));
      expect(soundFingerprint(t), v, reason: 'volume não entra no áudio congelado');
      t.modulation.sources.add(ModSource(id: 'm', dests: [ModDest(AutoTarget(AutoKind.effect, ref: fx.id, param: 0))]));
      expect(soundFingerprint(t), isNot(v));
    });

    test('(2) renderizar em faixa nova respeita as recusas do congelar, inclusive o sidechain e clipes mudos', () async {
      final c = frozenProject();
      final comp = c.addEffect(2, EffectKind.compressor);
      c.edit((d) => d.tracks[2].clips.add(AudioClip(id: 'x', sample: 's', start: 0, length: 1)));
      c.setEffectParam(2, comp.id, 10, 0, undoable: true);
      await c.bounceTrack(2);
      expect(c.error, contains('sidechain'));
      expect(c.error, contains('renderizar'));
      expect(e.renders, isEmpty);
      c.clearError();
      c.setEffectParam(2, comp.id, 10, 2, undoable: true);
      c.edit((d) => d.tracks[2].clips.single.muted = true);
      await c.bounceTrack(2);
      expect(c.error, contains('só tem clipes mudos'));
      expect(e.renders, isEmpty);
    });

    test('(6 do loop) faixa só com clipes mudos não congela nem converte', () async {
      final c = frozenProject();
      c.edit((d) => d.tracks[2].clips.add(AudioClip(id: 'x', sample: 's', start: 0, length: 1, muted: true)));
      expect(freezeBlocker(c, 2), 'A faixa só tem clipes mudos');
      await c.freezeTrack(2);
      expect(c.error, contains('só tem clipes mudos'));
      c.clearError();
      await c.convertToAudio(2);
      expect(c.error, contains('só tem clipes mudos'));
      expect(e.renders, isEmpty);
    });

    test('(3) as mensagens da conversão dizem converter', () async {
      final c = frozenProject();
      final comp = c.addEffect(2, EffectKind.compressor);
      c.edit((d) => d.tracks[2].clips.add(AudioClip(id: 'x', sample: 's', start: 0, length: 1)));
      c.setEffectParam(2, comp.id, 10, 0, undoable: true);
      await c.convertToAudio(2);
      expect(c.error, contains('antes de converter'));
      c.clearError();
      e.renderResult = (outputs) => [
        [Float32List(100)],
      ];
      await c.convertToAudio(0);
      expect(c.error, contains('nada para converter'));
      expect(c.error, isNot(contains('congelar')));
    });

    test('(4) o fim do projeto inclui a faixa congelada e a cauda dela', () async {
      final c = frozenProject();
      c.edit((d) => d.tracks[0].midi.single.length = 1);
      await c.freezeTrack(0, tail: 3);
      final f = c.doc.tracks[0].frozen!;
      final end = c.doc.clipEnd(f.clip);
      expect(end, greaterThan(c.doc.tracks[0].midi.single.end));
      expect(c.doc.contentEnd, end);
    });

    test('(6) editar notas de faixa congelada avisa uma vez por congelamento', () async {
      final c = frozenProject();
      await c.freezeTrack(0);
      c.clearNotice();
      c.edit((d) => d.tracks[0].midi.single.notes.add(MidiNote(pitch: 64, start: 1, length: 1)));
      expect(c.notice, 'Faixa congelada: a alteração só soa ao descongelar.');
      c.clearNotice();
      c.edit((d) => d.tracks[0].midi.single.notes.add(MidiNote(pitch: 65, start: 2, length: 1)));
      expect(c.notice, isNull, reason: 'não repete a cada edição');
      c.unfreezeTrack(0);
      await c.freezeTrack(0);
      c.clearNotice();
      // mexer no fader não é o conteúdo
      c.edit((d) => d.tracks[0].gain = 0.5);
      expect(c.notice, isNull);
      c.edit((d) => d.tracks[0].midi.single.notes.add(MidiNote(pitch: 66, start: 3, length: 1)));
      expect(c.notice, isNotNull, reason: 'novo congelamento, avisa de novo');
    });

    test('(7) descongelar tira o áudio congelado da lista do projeto (se ninguém mais usa) e desfazer devolve', () async {
      final c = frozenProject();
      await c.freezeTrack(0);
      final h = c.doc.tracks[0].frozen!.sample;
      expect(c.doc.samples.containsKey(h), isTrue);
      c.unfreezeTrack(0);
      expect(c.doc.samples.containsKey(h), isFalse);
      c.undo();
      expect(c.doc.samples.containsKey(h), isTrue);
      expect(c.doc.tracks[0].frozen, isNotNull);
    });
  });

  group('fase 21', () {
    test('(1) restaurar depois de uma leitura que falhou só na abertura não sobrescreve o arquivo que agora abre', () async {
      final st = _FlakyRead()
        ..data = '{"format":"jopendaw-user-presets","version":1,"presets":[{"id":"z","family":"effect","kind":"gate","name":"Meu","params":{"0":0.5}}]}'
        ..backup = '{"format":"jopendaw-user-presets","version":1,"presets":[{"id":"p0","family":"effect","kind":"gate","name":"Copia","params":{"0":0.5}}]}';
      final s = UserPresets(st);
      await s.load();
      expect(s.problem, isNotNull);
      await expectLater(s.restoreFromBackup(), throwsA(isA<PresetFormatException>()));
      await s.flush();
      expect(st.data, contains('Meu'), reason: 'o arquivo principal segue como estava');
      expect(st.writes, 0);
    });

    test('(3) gridCuts devolve erro em vez de truncar em silêncio', () async {
      final (c, clip) = await project(e);
      c.edit((d) {
        d.bpm = 400;
        clip.length = 2000.0;
      });
      expect(() => gridCuts(clip, c.doc, EditGrid.thirtySecond.beats), throwsA(isA<CutLimitException>()));
      c.edit((_) => clip.length = 2.0);
      expect(gridCuts(clip, c.doc, EditGrid.quarter.beats), isNotEmpty);
    });
  });
}

class _FlakyRead extends MemoryUserPresetStorage {
  var _first = true;
  var writes = 0;
  @override
  Future<String?> read() async {
    if (_first) {
      _first = false;
      throw StateError('arquivo em uso');
    }
    return data;
  }

  @override
  Future<void> write(String json) async {
    writes++;
    await super.write(json);
  }
}
