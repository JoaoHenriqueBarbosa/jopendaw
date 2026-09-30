// Fase 15, item A: correções de MIDI learn, latência/gravação, sincronização e andamento/compasso.
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jopendaw_app/audio/engine.dart' show EngineState, ccPitchBase;
import 'package:jopendaw_app/daw/controller.dart';
import 'package:jopendaw_app/daw/instruments.dart';
import 'package:jopendaw_app/daw/midi_learn.dart';
import 'package:jopendaw_app/daw/midi_map.dart';
import 'package:jopendaw_app/daw/model.dart';
import 'package:jopendaw_app/daw/project_file.dart';
import 'package:jopendaw_app/daw/sync.dart';
import 'package:jopendaw_app/daw/tempo_format.dart';
import 'package:jopendaw_app/daw/tempo_map.dart';
import 'package:jopendaw_app/widgets/format.dart';

import 'fake_engine.dart';
import 'fake_sync_api.dart';

const unison = AutoTarget(AutoKind.instrument, param: 9); // inteiro 1..7, padrão 1
const cutoff = AutoTarget(AutoKind.instrument, param: 13);
const level = AutoTarget(AutoKind.instrument, param: 1); // 0..1, padrão 0,8

Future<(DawController, FakeEngine)> rig() async {
  final e = FakeEngine();
  final c = fakeController(e);
  c.addInstrumentTrack(TrackKind.synth);
  await c.enableMidiInput();
  e.log = [];
  addTearDown(() => c.midiLearn.dispose());
  return (c, e);
}

MidiMapping learn(DawController c, FakeEngine e, int track, AutoTarget target, {int d1 = 74, int d2 = 64}) {
  expect(c.midiLearn.arm(track, target), isTrue);
  e.onMidi!(0xB0, d1, d2);
  return c.midiLearn.lastLearned!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('MIDI learn', () {
    test('1: primeira mensagem no valor fixo não perde o passo de desfazer da mudança real', () async {
      final (c, e) = await rig();
      c.midiLearn.setSoft(false);
      learn(c, e, 1, unison, d2: 100);
      expect(c.doc.tracks[1].param(9), 1);
      final tracks = c.doc.tracks.length;
      e.onMidi!(0xB0, 74, 0); // 1: igual ao fixo
      expect(c.doc.tracks[1].param(9), 1);
      e.onMidi!(0xB0, 74, 127); // 7
      expect(c.doc.tracks[1].param(9), 7);
      c.undo();
      expect(c.doc.tracks.length, tracks, reason: 'o desfazer não pode levar a faixa embora: a mudança tem passo próprio');
      expect(c.doc.tracks[1].param(9), 1);
    });

    test('2: o padrão guarda o tipo do instrumento e só aplica na faixa do mesmo tipo', () async {
      final (c, e) = await rig();
      learn(c, e, 1, cutoff);
      final json = jsonDecode(jsonEncode(midiDefaultToJson(c.doc.midiMap, c.doc.tracks))) as Map;
      final fm = [DawTrack(id: 'a', name: 'A', color: 0), DawTrack(id: 'b', name: 'FM', color: 0, kind: TrackKind.fm)];
      expect(midiDefaultFrom(json, fm, () => 'x').items, isEmpty, reason: 'id 13 no FM é outro parâmetro');
      final synth = [DawTrack(id: 'a', name: 'A', color: 0), DawTrack(id: 'b', name: 'S', color: 0, kind: TrackKind.synth)];
      expect(midiDefaultFrom(json, synth, () => 'x').items.single.trackId, 'b');
      // padrão antigo, sem o tipo: aplica como antes
      for (final i in json['items'] as List) {
        (i as Map).remove('kind');
      }
      expect(midiDefaultFrom(json, fm, () => 'x').items.length, 1);
    });

    test('3: remapDocIds reescreve o midi_map (faixa, efeito, envio) e descarta o solto', () {
      final doc = DawDoc(
        bpm: 120,
        beatsPerBar: 4,
        tracks: [
          DawTrack(id: 'a b', name: 'A', color: 0), // id inseguro
          DawTrack(id: 'a b', name: 'B', color: 0),
          DawTrack(id: 'ok', name: 'C', color: 0),
        ],
      );
      const cc = MidiSource(MidiSourceKind.cc, 0, 1);
      doc.midiMap.items.addAll([
        MidiMapping(id: 'm1', source: cc, trackId: 'a b', target: const AutoTarget(AutoKind.volume)),
        MidiMapping(
          id: 'm2',
          source: cc,
          trackId: 'ok',
          target: const AutoTarget(AutoKind.send, ref: 'a b'),
        ),
        MidiMapping(id: 'm3', source: cc, trackId: 'sumiu', target: const AutoTarget(AutoKind.pan)),
        MidiMapping(id: 'm4', source: cc, trackId: null, target: const AutoTarget(AutoKind.pan)),
        MidiMapping(
          id: 'm5',
          source: cc,
          trackId: 'ok',
          target: const AutoTarget(AutoKind.effect, ref: 'fantasma', param: 1),
        ),
      ]);
      remapDocIds(doc);
      final byId = {for (final m in doc.midiMap.items) m.id: m};
      expect(byId.keys, {'m1', 'm2', 'm4'});
      expect(byId['m1']!.trackId, doc.tracks[0].id);
      expect(byId['m2']!.trackId, 'ok');
      expect(byId['m2']!.target.ref, doc.tracks[0].id);
      expect(byId['m4']!.trackId, isNull);
      expect(doc.tracks[0].id, isNot('a b'));
    });

    test('4: "Suave" desligado sem mapeamentos sobrevive ao salvar e reabrir', () {
      final doc = DawDoc(
        bpm: 120,
        beatsPerBar: 4,
        tracks: [DawTrack(id: 't', name: 'x', color: 0)],
        midiMap: MidiMap(soft: false),
      );
      final back = DawDoc.fromJson(jsonDecode(jsonEncode(doc.toJson())) as Map<String, dynamic>);
      expect(back.midiMap.soft, isFalse);
      expect(DawDoc(bpm: 120, beatsPerBar: 4, tracks: []).toJson().containsKey('midi_map'), isFalse);
    });

    test('5: track que não é texto nem nulo descarta o item em vez de virar o master', () {
      final src = {'k': 'cc', 'ch': 0, 'cc': 1};
      Map<String, dynamic> item(String id, Object? track) => {
        'id': id,
        'src': src,
        'track': track,
        'target': {'kind': 'pan'},
      };
      final map = MidiMap.fromJson({
        'items': [
          item('a', 7),
          item('b', {'x': 1}),
          item('c', null),
          item('d', 't'),
        ],
      });
      expect(map.items.map((m) => m.id), ['c', 'd']);
    });

    test('7: o takeover compara com o valor que o knob mostra (a curva, tocando), não com o fixo', () async {
      final (c, e) = await rig();
      c.addLane(1, level).points.addAll([AutoPoint(beat: 0, value: 0.2), AutoPoint(beat: 8, value: 0.2)]);
      learn(c, e, 1, level, d1: 30, d2: 127);
      c.beat.value = 2;
      c.playing.value = true;
      addTearDown(() => c.playing.value = false);
      expect(c.liveTargetValue(1, level, 0.8), closeTo(0.2, 1e-9));
      e.onMidi!(0xB0, 30, 102); // 80%: em cima do valor fixo, longe do 20% mostrado
      expect(c.doc.tracks[1].param(1), 0.8, reason: 'não pega: o knob mostra 20%');
      e.onMidi!(0xB0, 30, 20); // cruza o 20% mostrado
      expect(c.doc.tracks[1].param(1), closeTo(20 / 127, 1e-9));
    });
  });

  group('latência e gravação', () {
    test('3: CC tocado nos primeiros ms com contagem ligada não recua para antes do início', () async {
      final e = FakeEngine();
      final c = fakeController(e);
      c.addInstrumentTrack(TrackKind.synth);
      c.doc.countIn = true;
      e.latency = 0.05;
      e.engineLatency = 0.1; // 0,3 batida a 120 bpm
      c.setArmed(1, true);
      c.beat.value = 4;
      await c.toggleRecord();
      c.debugEngineState(EngineState(4.01, true, Float32List(0)));
      // uma nota e um CC (modulação) a 0,1 batida do início: o recuo levaria o CC a 3,8
      e.notes = Float32List.fromList([1, 60, 4.1, 5, 0.8, 1, ccPitchBase + ccMod.toDouble(), 4.1, 4.1, 0.5]);
      c.debugRecordingElapsed(const Duration(seconds: 2));
      await c.toggleRecord();
      final clip = c.doc.tracks[1].midi.single;
      expect(clip.controls.where((x) => x.cc == ccMod), isNotEmpty, reason: 'o CC entra, encostado no começo');
      expect(clip.controls.where((x) => x.cc == ccMod).first.beat, closeTo(0, 1e-9));
    });
  });

  group('sincronização', () {
    Map<String, dynamic> docJson({String track = 'Servidor', String? sample}) {
      final d = DawDoc(
        bpm: 90,
        beatsPerBar: 4,
        tracks: [
          DawTrack(
            id: 't1',
            name: track,
            color: 0,
            clips: sample == null ? [] : [AudioClip(id: 'c1', sample: sample, start: 0, length: 2)],
          ),
        ],
        samples: {?sample: SampleInfo('a.wav', 2)},
      );
      return jsonDecode(jsonEncode(d.toJson())) as Map<String, dynamic>;
    }

    MemoryStore storeWith({Map<String, dynamic>? local, int? version}) {
      final s = MemoryStore();
      if (local != null) s.data['doc:p'] = jsonEncode(local);
      if (version != null) s.data['sync:p'] = jsonEncode({'version': version, 'dirty': false});
      return s;
    }

    Future<void> idle(DawController c) async {
      while (c.sync.busy) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
    }

    test('2: mouse com o botão segurado parado não deixa o pull trocar o documento; soltar libera', () async {
      final api = FakeSyncApi()
        ..version = 2
        ..doc = docJson();
      final c = fakeController(
        FakeEngine(),
        store: storeWith(local: docJson(track: 'Local'), version: 1),
        api: api,
        canSync: () => true,
        syncTimeScale: 100,
      );
      c.pointerStaleAfter = const Duration(milliseconds: 5);
      c.debugPointer(const PointerDownEvent(pointer: 3, kind: PointerDeviceKind.mouse, buttons: kPrimaryButton));
      await c.open();
      await c.sync.starting;
      await idle(c);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await c.sync.syncNow();
      await idle(c);
      expect(c.doc.tracks.first.name, 'Local', reason: 'botão ainda apertado, mesmo sem mexer há mais que o limite');
      c.debugPointer(const PointerHoverEvent(pointer: 9, kind: PointerDeviceKind.mouse));
      await c.sync.syncNow();
      await idle(c);
      expect(c.doc.tracks.first.name, 'Servidor');
      c.dispose();
    });

    test('3: projeto só no servidor e ocupado na abertura: o estúdio espera o primeiro pull decidir', () async {
      final api = FakeSyncApi()
        ..version = 3
        ..doc = docJson();
      final c = fakeController(FakeEngine(), store: MemoryStore(), api: api, canSync: () => true, syncTimeScale: 0.01);
      c.debugPointer(const PointerDownEvent(pointer: 1));
      var opened = false;
      final opening = c.open().then((_) => opened = true);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(opened, isFalse, reason: 'ainda esperando: sem estúdio vazio para ser trocado depois');
      c.debugPointer(const PointerUpEvent(pointer: 1));
      await opening;
      expect(c.ready, isTrue);
      expect(c.doc.tracks.first.name, 'Servidor');
      c.dispose();
    });

    test('4: 422 com áudio que este aparelho não tem para na hora, com a mensagem certa', () async {
      final h = sha256.convert([1, 2, 3]).toString();
      final api = FakeSyncApi()..missingNext = {h};
      final store = storeWith(
        local: docJson(sample: h, track: 'Local'),
      );
      final c = fakeController(FakeEngine(), store: store, api: api, canSync: () => true, syncTimeScale: 0.01);
      await c.open();
      await c.sync.starting;
      await idle(c);
      expect(api.calls.where((x) => x.startsWith('put_doc')).length, 1);
      expect(c.sync.phase, SyncPhase.error);
      expect(c.sync.message, contains('Faltam áudios neste aparelho'));
      c.dispose();
    });
  });

  group('compasso e andamento', () {
    test('1: o espelho manda a figura do compasso (beat_unit) quando ela muda; 4/4 segue sem ela', () async {
      final sent = <Map<String, dynamic>>[];
      final c = fakeController(FakeEngine(), canSync: () => true, patchProject: (id, p) async => sent.add(p));
      c.doc.meterMap = [MeterChange(1, 6, 8)];
      c.doc.beatsPerBar = 3;
      await c.setTempo(121, 3, keepMeter: true);
      expect(sent, isNotEmpty);
      expect(sent.last['beat_unit'], 8);
      expect(sent.last['beats_per_bar'], 6);
      expect(c.tempoPending, isFalse);
      c.dispose();
    });

    test('2: formatador de altura mostra 0,04 st e não some com a fração', () {
      expect(formatPitch(0.04), '0,04');
      expect(formatPitch(2), '2');
      expect(formatPitch(-0.5), '-0,5');
      expect(formatPitch(-0.001), '0');
      expect(formatPitch(12.25), '12,25');
    });

    test('6: os textos citam o menu do knob e o Shift+K', () {
      expect(keyboardTooltip(on: true, octave: 4, velocityPercent: 80), contains('Shift+H/K/L'));
    });
  });
}
