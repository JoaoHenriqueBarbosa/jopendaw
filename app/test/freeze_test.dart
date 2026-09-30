// Fase 20 B: congelar faixa (no lugar, reversível) e converter em áudio. O render é o de mentira do
// `fake_engine.dart`: o teste decide o que ele "soou" e lê o que o controlador mandou ao motor.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jopendaw_app/audio/engine.dart';
import 'package:jopendaw_app/daw/controller.dart';
import 'package:jopendaw_app/daw/effects.dart';
import 'package:jopendaw_app/daw/freeze.dart';
import 'package:jopendaw_app/daw/instruments.dart';
import 'package:jopendaw_app/daw/model.dart';
import 'package:jopendaw_app/daw/project_file.dart';

import 'fake_engine.dart';

Float32List filled(int n, double v) => Float32List(n)..fillRange(0, n, v);

List<List<Object>> named(List<List<Object>> calls, String name) => [
  for (final c in calls)
    if (c.first == name) c,
];

void main() {
  late FakeEngine e;
  setUp(() => e = FakeEngine());

  /// Sintetizador (0) com clipe de 4 batidas e delay, barramento (1) e faixa de áudio vazia (2).
  DawController project() {
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

  Map<String, dynamic> trackJson(DawController c, int i) => jsonDecode(jsonEncode(c.doc.tracks[i].toJson())) as Map<String, dynamic>;

  group('congelar no lugar', () {
    test('renderiza com a cauda pedida, guarda o áudio e deixa o conteúdo intacto', () async {
      final c = project();
      final before = trackJson(c, 0);
      await c.freezeTrack(0, tail: 3);
      expect(c.error, isNull);
      final r = e.renders.single;
      expect(r.outputs, [0]);
      expect((r.fromBeat, r.toBeat, r.tailSeconds), (4.0, 8.0, 3.0));
      expect(c.doc.tracks, hasLength(3), reason: 'não cria faixa');
      final t = c.doc.tracks[0], f = t.frozen!;
      expect((f.start, f.tail), (4.0, 3.0));
      expect(f.length, 2.5, reason: '250 quadros a 100 Hz');
      expect(c.doc.samples[f.sample]!.name, 'Sintetizador 1 (congelada).wav');
      expect(c.waveforms.containsKey(f.sample), isTrue);
      // o conteúdo original segue no documento, byte a byte (fora o próprio estado de congelada)
      final after = trackJson(c, 0)..remove('frozen');
      expect(after, before);
      expect(t.midi.single.notes, hasLength(1));
      expect(t.effects, hasLength(1));
    });

    test('o motor recebe a faixa como áudio com o clipe congelado, sem efeitos nem notas', () async {
      final c = project();
      await c.freezeTrack(0);
      final full = c.debugFullSyncCalls();
      expect(named(full, 'track_kind').where((k) => k[1] == 0).map((k) => k[2]), [TrackKind.audio.index]);
      final clips = named(full, 'clip_add').where((k) => k[1] == 0);
      expect(clips, hasLength(1));
      expect(clips.single[3], 4.0, reason: 'começa onde o conteúdo começava');
      expect(named(full, 'fx_set').where((k) => k[1] == 0), isEmpty, reason: 'os efeitos já estão no áudio');
      expect(named(full, 'note_add'), isEmpty, reason: 'as notas não tocam por cima do áudio');
      // e o sync incremental mandou a troca ao motor já aberto
      expect(e.sent('track_kind').any((k) => k[1] == 0 && k[2] == TrackKind.audio.index), isTrue);
    });

    test('automação e modulação do instrumento e dos efeitos não vão ao motor; volume e pan continuam', () async {
      final c = project();
      final fx = c.doc.tracks[0].effects.single;
      c.edit((d) {
        d.tracks[0].lanes
          ..add(AutoLane(id: 'v', target: const AutoTarget(AutoKind.volume), points: [AutoPoint(beat: 0, value: 0.5), AutoPoint(beat: 4, value: 1)]))
          ..add(AutoLane(id: 'f', target: AutoTarget(AutoKind.effect, ref: fx.id, param: 0), points: [AutoPoint(beat: 0, value: 0.1), AutoPoint(beat: 4, value: 0.9)]));
      });
      expect(named(c.debugFullSyncCalls(), 'auto_lane').map((l) => l[2]).toSet(), {0, 3});
      await c.freezeTrack(0);
      expect(named(c.debugFullSyncCalls(), 'auto_lane').map((l) => l[2]).toSet(), {0});
      c.unfreezeTrack(0);
      expect(named(c.debugFullSyncCalls(), 'auto_lane').map((l) => l[2]).toSet(), {0, 3});
    });

    test('desfazer tira o congelamento; refazer volta; descongelar devolve a faixa idêntica', () async {
      final c = project();
      final before = jsonEncode(c.doc.toJson());
      await c.freezeTrack(0);
      final frozenJson = jsonEncode(c.doc.toJson());
      c.undo();
      expect(jsonEncode(c.doc.toJson()), before);
      expect(c.doc.tracks[0].frozen, isNull);
      c.redo();
      expect(jsonEncode(c.doc.toJson()), frozenJson);
      c.unfreezeTrack(0);
      expect(c.doc.tracks[0].frozen, isNull);
      expect(trackJson(c, 0), jsonDecode(before)['tracks'][0]);
      expect(named(c.debugFullSyncCalls(), 'track_kind').where((k) => k[1] == 0).map((k) => k[2]), [TrackKind.synth.index]);
      expect(named(c.debugFullSyncCalls(), 'note_add'), hasLength(1));
      // descongelar também desfaz
      c.undo();
      expect(c.doc.tracks[0].frozen, isNotNull);
    });

    test('durante a reprodução: congela sem parar o transporte e o motor troca a faixa', () async {
      final c = project();
      await c.togglePlay();
      expect(c.playing.value, isTrue);
      e.log!.clear();
      await c.freezeTrack(0);
      expect(c.error, isNull);
      expect(c.playing.value, isTrue);
      expect(c.doc.tracks[0].frozen, isNotNull);
      expect(e.sent('track_kind').any((k) => k[1] == 0 && k[2] == TrackKind.audio.index), isTrue);
      expect(e.sent('clip_add'), isNotEmpty);
      c.unfreezeTrack(0);
      expect(c.playing.value, isTrue);
      expect(e.sent('track_kind').last.sublist(1), [0, TrackKind.synth.index]);
      await c.togglePlay();
    });

    test('margem de cauda: limitada entre 0 e 60 s, valor torto vira o padrão', () async {
      final c = project();
      await c.freezeTrack(0, tail: 999);
      expect(e.renders.last.tailSeconds, kMaxFreezeTail);
      c.unfreezeTrack(0);
      await c.freezeTrack(0, tail: -5);
      expect(e.renders.last.tailSeconds, 0);
      c.unfreezeTrack(0);
      await c.freezeTrack(0, tail: double.nan);
      expect(e.renders.last.tailSeconds, kDefaultFreezeTail);
    });

    test('faixa vazia, barramento, já congelada e que não soa: recusa sem renderizar nem alterar', () async {
      final c = project();
      await c.freezeTrack(2);
      expect(c.error, contains('vazia'));
      c.clearError();
      await c.freezeTrack(1);
      expect(c.error, contains('Barramento'));
      c.clearError();
      expect(e.renders, isEmpty);
      e.renderResult = (outputs) => [
        [Float32List(100), Float32List(100)],
      ];
      await c.freezeTrack(0);
      expect(c.error, contains('não soou'));
      expect(c.doc.tracks[0].frozen, isNull);
      c.clearError();
      e.renderResult = (outputs) => [
        [filled(250, 0.3), filled(250, 0.3)],
      ];
      await c.freezeTrack(0);
      final n = e.renders.length;
      await c.freezeTrack(0);
      expect(c.error, contains('já está congelada'));
      expect(e.renders, hasLength(n));
    });

    test('sidechain de outra faixa impede congelar; o da própria faixa, não; quem é chave congela', () async {
      final c = project();
      final comp = c.addEffect(2, EffectKind.compressor);
      c.edit((d) => d.tracks[2].clips.add(AudioClip(id: 'x', sample: 's', start: 0, length: 1)));
      c.setEffectParam(2, comp.id, 10, 0, undoable: true);
      expect(freezeBlocker(c, 2), contains('sidechain'));
      expect(freezeBlocker(c, 2), contains('Sintetizador 1'));
      await c.freezeTrack(2);
      expect(c.error, contains('sidechain'));
      expect(e.renders, isEmpty);
      // a chave é a própria faixa: nada depende das outras
      c.setEffectParam(2, comp.id, 10, 2, undoable: true);
      expect(freezeBlocker(c, 2), isNull);
      // a faixa 0 é a chave de outra e congela normalmente
      c.setEffectParam(2, comp.id, 10, 0, undoable: true);
      expect(freezeBlocker(c, 0), isNull);
    });

    test('a faixa mudou ou foi apagada durante o render: nada é congelado e avisa', () async {
      final c = project();
      e.renderResult = (outputs) {
        c.edit((d) => d.tracks[0].midi.single.notes.add(MidiNote(pitch: 64, start: 1, length: 1)));
        return [
          [filled(250, 0.3)],
        ];
      };
      await c.freezeTrack(0);
      expect(c.error, contains('mudou durante o render'));
      expect(c.doc.tracks[0].frozen, isNull);
      c.clearError();
      e.renderResult = (outputs) {
        c.removeTrack(0);
        return [
          [filled(250, 0.3)],
        ];
      };
      await c.freezeTrack(0);
      expect(c.error, contains('apagada'));
      expect(c.doc.tracks.every((t) => t.frozen == null), isTrue);
    });

    test('mexer no fader durante o render não invalida o congelamento', () async {
      final c = project();
      e.renderResult = (outputs) {
        c.edit((d) => d.tracks[0].gain = 0.3);
        return [
          [filled(250, 0.3)],
        ];
      };
      await c.freezeTrack(0);
      expect(c.error, isNull);
      expect(c.doc.tracks[0].frozen, isNotNull);
      expect(c.doc.tracks[0].gain, 0.3);
    });

    test('cancelar: nada muda e não vira falha', () async {
      final c = project();
      e.renderResult = (outputs) {
        c.cancelRender();
        throw const RenderCanceled();
      };
      await c.freezeTrack(0);
      expect(e.cancels, 1);
      expect(c.error, isNull);
      expect(c.doc.tracks[0].frozen, isNull);
    });

    test('envios, fader e pan seguem vivos na congelada', () async {
      final c = project();
      c.edit((d) => d.tracks[0]
        ..gain = 0.5
        ..pan = -0.3
        ..sends.add(Send(target: d.tracks[1].id, level: 0.4)));
      await c.freezeTrack(0);
      final full = c.debugFullSyncCalls();
      expect(named(full, 'track').first, ['track', 0, 0.5, -0.3, false, false]);
      expect(named(full, 'send_set').isNotEmpty || named(full, 'send').isNotEmpty || full.any((k) => k.first.toString().contains('send')), isTrue);
    });

    test('duplicar a faixa congelada leva o congelamento junto', () async {
      final c = project();
      await c.freezeTrack(0);
      c.duplicateTrack(0);
      expect(c.doc.tracks[1].frozen!.sample, c.doc.tracks[0].frozen!.sample);
    });
  });

  group('converter em áudio', () {
    test('troca instrumento, notas e efeitos por um clipe de áudio e desfaz inteiro', () async {
      final c = project();
      c.edit((d) => d.tracks[0]
        ..gain = 0.5
        ..mute = true);
      final before = jsonEncode(c.doc.toJson());
      await c.convertToAudio(0, tail: 2);
      expect(c.error, isNull);
      final t = c.doc.tracks[0];
      expect(t.kind, TrackKind.audio);
      expect(t.midi, isEmpty);
      expect(t.effects, isEmpty);
      expect(t.frozen, isNull);
      expect((t.gain, t.mute), (0.5, true));
      final clip = t.clips.single;
      expect((clip.start, clip.length), (4.0, 2.5));
      expect(c.doc.samples.containsKey(clip.sample), isTrue);
      expect(e.renders.single.tailSeconds, 2);
      c.undo();
      expect(jsonEncode(c.doc.toJson()), before);
      expect(c.doc.tracks[0].kind, TrackKind.synth);
    });

    test('faixa congelada converte sem renderizar de novo, com o mesmo áudio', () async {
      final c = project();
      await c.freezeTrack(0);
      final f = c.doc.tracks[0].frozen!;
      await c.convertToAudio(0);
      expect(e.renders, hasLength(1));
      final t = c.doc.tracks[0];
      expect((t.kind, t.frozen), (TrackKind.audio, null));
      expect(t.midi, isEmpty);
      expect(t.effects, isEmpty);
      expect(t.clips.single.sample, f.sample);
      c.undo();
      expect(c.doc.tracks[0].frozen, isNotNull);
      expect(c.doc.tracks[0].kind, TrackKind.synth);
    });

    test('mesmas recusas: vazia, barramento e sidechain', () async {
      final c = project();
      await c.convertToAudio(2);
      expect(c.error, contains('vazia'));
      c.clearError();
      await c.convertToAudio(1);
      expect(c.error, contains('Barramento'));
      expect(e.renders, isEmpty);
    });
  });

  group('documento', () {
    test('ida e volta: só texto e números de ponto flutuante, e o antigo sem o campo abre normal', () async {
      final c = project();
      await c.freezeTrack(0, tail: 4);
      final json = jsonDecode(jsonEncode(c.doc.toJson())) as Map<String, dynamic>;
      final frozen = (json['tracks'] as List).first['frozen'] as Map<String, dynamic>;
      expect(frozen.keys.toSet(), {'sample', 'start', 'length', 'tail'});
      expect(frozen['sample'], isA<String>());
      final again = DawDoc.fromJson(json);
      expect(jsonEncode(again.toJson()), jsonEncode(json));
      expect(again.tracks[0].frozen!.tail, 4);
      // documento de antes: sem o campo nem a chave na saída
      (json['tracks'] as List).first.remove('frozen');
      final old = DawDoc.fromJson(json);
      expect(old.tracks[0].frozen, isNull);
      expect(jsonEncode(old.toJson()).contains('frozen'), isFalse);
      // campo torto: o conteúdo original está intacto, então vira "não congelada"
      for (final bad in <Object?>['x', <String, Object?>{}, {'sample': 'a', 'start': 'b', 'length': 1}, {'sample': 'a', 'start': 0, 'length': 0}]) {
        (json['tracks'] as List).first['frozen'] = bad;
        expect(DawDoc.fromJson(json).tracks[0].frozen, isNull, reason: '$bad');
      }
    });

    test('o áudio congelado entra nos áudios do projeto (sincronização e arquivo .jopendaw)', () async {
      final c = project();
      await c.freezeTrack(0);
      final hash = c.doc.tracks[0].frozen!.sample;
      expect(DawController.hashesOf(c.doc), contains(hash));
      expect(projectHashes(c.doc), contains(hash));
      // mesmo sem a entrada em `samples` (documento editado à mão), o controlador e o arquivo o acham
      c.doc.samples.remove(hash);
      expect(DawController.hashesOf(c.doc), contains(hash));
      expect(projectHashes(c.doc), contains(hash));
    });

    test('guarda o som do congelamento no guardado local (sobe por sha-256 como os outros)', () async {
      final store = MemoryStore();
      final c = fakeController(e, store: store, tracks: []);
      c.addInstrumentTrack(TrackKind.synth);
      c.createMidiClip(0, 4).notes.add(MidiNote(pitch: 60, start: 0, length: 4));
      e.renderResult = (outputs) => [
        [filled(250, 0.3)],
      ];
      await c.freezeTrack(0);
      final hash = c.doc.tracks[0].frozen!.sample;
      expect(store.data['sample:$hash'], isA<Uint8List>());
    });
  });
}
