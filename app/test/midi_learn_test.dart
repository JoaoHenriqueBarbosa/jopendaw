// Fase 13, item C: MIDI learn. Ida e volta do JSON `midi_map`, a conta (linear, log, invertido,
// faixa), aprender por CC/bend/pressão, takeover suave, conflito com a expressão do instrumento,
// alvos removidos e a gravação de automação pelo controlador.
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:jopendaw_app/daw/automation_mode.dart';
import 'package:jopendaw_app/daw/automation_record.dart' show AutoInfo;
import 'package:jopendaw_app/daw/controller.dart';
import 'package:jopendaw_app/daw/effects.dart';
import 'package:jopendaw_app/daw/instruments.dart';
import 'package:jopendaw_app/daw/midi_learn.dart';
import 'package:jopendaw_app/daw/midi_map.dart';
import 'package:jopendaw_app/daw/model.dart';

import 'fake_engine.dart';

const volume = AutoTarget(AutoKind.volume);
const pan = AutoTarget(AutoKind.pan);
const cutoff = AutoTarget(AutoKind.instrument, param: 13); // Hz, logarítmico
const unison = AutoTarget(AutoKind.instrument, param: 9); // inteiro 1..7
const cc74 = MidiSource(MidiSourceKind.cc, 0, 74);

/// Áudio 1 (0) e um sintetizador (1), com o MIDI ligado.
Future<(DawController, FakeEngine)> rig() async {
  final e = FakeEngine();
  final c = fakeController(e);
  c.addInstrumentTrack(TrackKind.synth);
  await c.enableMidiInput();
  e.log = [];
  addTearDown(() => c.midiLearn.dispose());
  return (c, e);
}

/// Aprende [target] da faixa [track] mexendo o CC [cc] do canal 1 uma vez.
MidiMapping learn(DawController c, FakeEngine e, int track, AutoTarget target, {int status = 0xB0, int d1 = 74, int d2 = 64}) {
  expect(c.midiLearn.arm(track, target), isTrue);
  e.onMidi!(status, d1, d2);
  return c.midiLearn.lastLearned!;
}

void main() {
  group('modelo e JSON', () {
    test('ida e volta do midiMap no documento, com faixa, master, efeito e envio', () {
      final m = MidiMap(soft: false)
        ..items.addAll([
          MidiMapping(id: 'a', source: cc74, trackId: 't1', target: cutoff, min: 0.2, max: 0.8, curve: MidiCurve.log, inverted: true),
          MidiMapping(id: 'b', source: const MidiSource(MidiSourceKind.bend, 3), trackId: null, target: pan),
          MidiMapping(
            id: 'c',
            source: const MidiSource(MidiSourceKind.pressure, 15),
            trackId: 't2',
            target: const AutoTarget(AutoKind.effect, ref: 'fx1', param: 4),
          ),
          MidiMapping(
            id: 'd',
            source: const MidiSource(MidiSourceKind.cc, 9, 7),
            trackId: 't2',
            target: const AutoTarget(AutoKind.send, ref: 'bus'),
          ),
        ]);
      final doc = DawDoc(
        bpm: 120,
        beatsPerBar: 4,
        tracks: [DawTrack(id: 't1', name: 'x', color: 0)],
        midiMap: m,
      );
      final back = DawDoc.fromJson(jsonDecode(jsonEncode(doc.toJson())) as Map<String, dynamic>);
      expect(back.midiMap.soft, isFalse);
      expect(back.midiMap.items.length, 4);
      for (var i = 0; i < 4; i++) {
        final a = m.items[i], b = back.midiMap.items[i];
        expect(b.id, a.id);
        expect(b.source, a.source);
        expect(b.trackId, a.trackId);
        expect(b.target, a.target);
        expect(b.min, a.min);
        expect(b.max, a.max);
        expect(b.curve, a.curve);
        expect(b.inverted, a.inverted);
      }
      expect(jsonEncode(back.toJson()), jsonEncode(doc.toJson()), reason: 'salvar de novo dá o mesmo JSON');
    });

    test('compatível para trás: sem o campo o documento abre e salva igual (sem a chave)', () {
      final doc = DawDoc(
        bpm: 100,
        beatsPerBar: 3,
        tracks: [DawTrack(id: 't', name: 'x', color: 0)],
      );
      final json = doc.toJson();
      expect(json.containsKey('midi_map'), isFalse);
      final back = DawDoc.fromJson(jsonDecode(jsonEncode(json)) as Map<String, dynamic>);
      expect(back.midiMap.isEmpty, isTrue);
      expect(back.midiMap.soft, isTrue, reason: 'takeover suave é o padrão');
      expect(jsonEncode(back.toJson()), jsonEncode(json));
    });

    test('entradas inválidas são descartadas e valores fora de faixa vão para dentro dela', () {
      final map = MidiMap.fromJson({
        'soft': true,
        'items': [
          'lixo',
          {'id': 'x'},
          {
            'id': 'ok',
            'src': {'k': 'cc', 'ch': 40, 'cc': 300},
            'track': 't',
            'target': {'kind': 'volume'},
            'min': -3,
            'max': 9,
            'curve': 'estranha',
          },
          {'id': 'ok', 'src': cc74.toJson(), 'track': 't', 'target': pan.toJson()},
          {
            'id': 'sem-tipo',
            'src': {'k': 'nrpn'},
            'target': {'kind': 'volume'},
          },
          {
            'id': 'alvo-novo',
            'src': cc74.toJson(),
            'target': {'kind': 'osc_do_futuro'},
          },
        ],
      });
      expect(map.items.length, 1, reason: 'id repetido, origem e alvo desconhecidos saem');
      final m = map.items.single;
      expect((m.source.channel, m.source.cc), (15, 127));
      expect((m.min, m.max, m.curve), (0.0, 1.0, MidiCurve.linear));
      expect(MidiMap.fromJson(42).isEmpty, isTrue);
      expect(MidiMap.fromJson(null).isEmpty, isTrue);
      expect(MidiMap.fromJson({'items': 'x'}).isEmpty, isTrue);
    });

    test('o mapa entra no JSON do controlador e sobrevive a um desfazer de outra edição', () async {
      final (c, e) = await rig();
      learn(c, e, 1, cutoff);
      expect(c.doc.toJson().containsKey('midi_map'), isTrue);
      c.edit((d) => d.tracks[1].name = 'Outro nome');
      c.undo();
      expect(c.doc.tracks[1].name, isNot('Outro nome'));
      expect(c.doc.midiMap.items.length, 1, reason: 'desfazer não leva os mapeamentos junto');
    });
  });

  group('a conta', () {
    test('CC, pressão e pitch bend de 14 bits em 0..1', () {
      expect(midiRaw(MidiSourceKind.cc, 0, 0), 0);
      expect(midiRaw(MidiSourceKind.cc, 0, 127), 1);
      expect(midiRaw(MidiSourceKind.cc, 0, 64), closeTo(64 / 127, 1e-12));
      expect(midiRaw(MidiSourceKind.pressure, 127, 0), 1);
      expect(midiRaw(MidiSourceKind.bend, 0, 0), 0);
      expect(midiRaw(MidiSourceKind.bend, 127, 127), 1);
      expect(midiRaw(MidiSourceKind.bend, 0, 64), closeTo(8192 / 16383, 1e-12));
      // bits acima de 7 dos bytes são ignorados (um byte de status não vaza para o valor)
      expect(midiRaw(MidiSourceKind.cc, 0, 0x80 | 10), closeTo(10 / 127, 1e-12));
    });

    test('linear, logarítmica, invertida e com faixa', () {
      MidiMapping m({MidiCurve curve = MidiCurve.linear, bool inv = false, double min = 0, double max = 1}) =>
          MidiMapping(id: 'm', source: cc74, trackId: null, target: volume, curve: curve, inverted: inv, min: min, max: max);
      expect(midiMappingNorm(m(), 0.25), 0.25);
      expect(midiMappingNorm(m(inv: true), 0.25), 0.75);
      final log = m(curve: MidiCurve.log);
      expect(midiMappingNorm(log, 0), 0);
      expect(midiMappingNorm(log, 1), closeTo(1, 1e-12));
      expect(midiMappingNorm(log, 0.5), greaterThan(0.5), reason: 'sobe depressa no começo');
      expect(midiMappingNorm(m(min: 0.2, max: 0.6), 0), closeTo(0.2, 1e-12));
      expect(midiMappingNorm(m(min: 0.2, max: 0.6), 1), closeTo(0.6, 1e-12));
      expect(midiMappingNorm(m(min: 0.2, max: 0.6, inv: true), 0), closeTo(0.6, 1e-12));
      // faixa "ao contrário" (max < min) também vale
      expect(midiMappingNorm(m(min: 0.8, max: 0.2), 1), closeTo(0.2, 1e-12));
    });

    test('o valor anda na escala do controle: Hz em log, volume na curva do fader, pan reto, inteiro em degraus', () async {
      final (c, _) = await rig();
      final hz = c.autoInfo(1, cutoff)!;
      expect(midiTargetValue(hz, 0), closeTo(20, 1e-6));
      expect(midiTargetValue(hz, 1), closeTo(20000, 1e-3));
      expect(midiTargetValue(hz, 0.5), closeTo(632.455, 0.01), reason: 'meio do curso logarítmico: raiz de 20 × 20000');
      final vol = c.autoInfo(0, volume)!;
      expect(midiTargetValue(vol, 0), 0);
      expect(midiTargetValue(vol, 1), closeTo(vol.max, 1e-9));
      expect(gainToFaderRoundTrip(vol, midiTargetValue(vol, 0.5)), closeTo(0.5, 1e-9));
      final p = c.autoInfo(0, pan)!;
      expect(midiTargetValue(p, 0), -1);
      expect(midiTargetValue(p, 0.5), 0);
      expect(midiTargetValue(p, 1), 1);
      expect(midiTargetValue(p, 7), 1, reason: 'fora de faixa vai para o limite');
    });

    test('pelo controlador: CC 0 e 127 nos extremos do parâmetro, invertido e logarítmico', () async {
      final (c, e) = await rig();
      final m = learn(c, e, 1, cutoff);
      c.midiLearn.setSoft(false);
      e.onMidi!(0xB0, 74, 0);
      expect(c.doc.tracks[1].param(13), closeTo(20, 1e-6));
      e.onMidi!(0xB0, 74, 127);
      expect(c.doc.tracks[1].param(13), closeTo(20000, 1e-3));
      c.midiLearn.update(m.id, inverted: true);
      e.onMidi!(0xB0, 74, 127);
      expect(c.doc.tracks[1].param(13), closeTo(20, 1e-6));
      c.midiLearn.update(m.id, inverted: false, min: 0.25, max: 0.75);
      e.onMidi!(0xB0, 74, 0);
      final lo = c.doc.tracks[1].param(13);
      e.onMidi!(0xB0, 74, 127);
      final hi = c.doc.tracks[1].param(13);
      expect(lo, closeTo(20 * math.pow(1000, 0.25), 0.01), reason: '25% do curso em log: 20 × 1000^0,25');
      expect(hi, closeTo(20 * math.pow(1000, 0.75), 0.05));
      // o valor chega ao motor pelo caminho rápido do parâmetro
      expect(e.sent('param').last, ['param', 1, 13, hi]);
    });

    test('parâmetro inteiro anda em degraus e volume, pan e master pelo mesmo caminho', () async {
      final (c, e) = await rig();
      c.midiLearn.setSoft(false);
      learn(c, e, 1, unison, d1: 1);
      e.onMidi!(0xB0, 1, 127);
      expect(c.doc.tracks[1].param(9), 7);
      e.onMidi!(0xB0, 1, 0);
      expect(c.doc.tracks[1].param(9), 1);
      e.onMidi!(0xB0, 1, 64);
      expect(c.doc.tracks[1].param(9), 4);
      learn(c, e, 1, pan, d1: 10);
      e.onMidi!(0xB0, 10, 0);
      expect(c.doc.tracks[1].pan, -1);
      learn(c, e, -1, volume, d1: 7);
      e.onMidi!(0xB0, 7, 127);
      expect(c.doc.masterGain, closeTo(c.autoInfo(-1, volume)!.max, 1e-9));
      learn(c, e, -1, pan, d1: 8);
      e.onMidi!(0xB0, 8, 64);
      expect(c.doc.masterPan, closeTo(64 / 127 * 2 - 1, 1e-9));
    });

    test('efeito e envio: a mesma conta, pelos setters deles', () async {
      final (c, e) = await rig();
      c.midiLearn.setSoft(false);
      final slot = c.addEffect(1, EffectKind.reverb);
      final spec = slot.kind.params.first;
      final fx = AutoTarget(AutoKind.effect, ref: slot.id, param: spec.id);
      learn(c, e, 1, fx, d1: 20);
      e.onMidi!(0xB0, 20, 127);
      expect(c.doc.tracks[1].effects.single.param(spec.id), closeTo(spec.max, 1e-9));
      e.onMidi!(0xB0, 20, 0);
      expect(c.doc.tracks[1].effects.single.param(spec.id), closeTo(spec.min, 1e-9));
      final bus = c.addBusTrack();
      expect(c.setSend(1, bus.id, level: 0.5), isTrue);
      final send = AutoTarget(AutoKind.send, ref: bus.id);
      learn(c, e, 1, send, d1: 21);
      e.onMidi!(0xB0, 21, 0);
      expect(c.doc.tracks[1].sends.single.level, 0);
      e.onMidi!(0xB0, 21, 127);
      expect(c.doc.tracks[1].sends.single.level, closeTo(c.autoInfo(1, send)!.max, 1e-9));
    });
  });

  group('aprender', () {
    test('armar e mexer o CC cria o mapeamento com canal e controle, e consome a mensagem', () async {
      final (c, e) = await rig();
      expect(c.midiLearn.arm(1, cutoff), isTrue);
      expect(c.midiLearn.learning, isTrue);
      expect(c.midiLearn.armed, isNotNull);
      e.onMidi!(0xB2, 74, 90); // canal 3
      expect(c.midiLearn.armed, isNull);
      final m = c.doc.midiMap.items.single;
      expect(m.source, const MidiSource(MidiSourceKind.cc, 2, 74));
      expect((m.trackId, m.target), (c.doc.tracks[1].id, cutoff));
      expect(m.source.label, 'Canal 3 · CC 74');
      expect(e.sent('live_cc'), isEmpty);
      expect(c.midiLearn.mappingFor(1, cutoff)?.id, m.id);
      expect(c.midiLearn.mappingFor(1, unison), isNull);
    });

    test('pitch bend e pressão do canal também aprendem (e mapeados não viram expressão)', () async {
      final (c, e) = await rig();
      learn(c, e, 1, cutoff, status: 0xE0, d1: 0, d2: 64);
      expect(c.doc.midiMap.items.single.source.kind, MidiSourceKind.bend);
      learn(c, e, 1, unison, status: 0xD1, d1: 50, d2: 0);
      expect(c.doc.midiMap.items.last.source, const MidiSource(MidiSourceKind.pressure, 1));
      e.onMidi!(0xE0, 127, 127);
      e.onMidi!(0xD1, 127, 0);
      expect(e.sent('live_bend'), isEmpty);
    });

    test('CC 120..127 nunca são aprendidos nem consumidos: continuam panic e reset', () async {
      final (c, e) = await rig();
      expect(c.midiLearn.arm(1, cutoff), isTrue);
      e.onMidi!(0xB0, 120, 0);
      e.onMidi!(0xB0, 121, 0);
      e.onMidi!(0xB0, 123, 0);
      expect(c.midiLearn.armed, isNotNull, reason: 'segue esperando um controle de verdade');
      expect(c.doc.midiMap.isEmpty, isTrue);
      expect(e.sent('panic'), isNotEmpty);
      e.onMidi!(0xB0, 5, 10);
      expect(c.doc.midiMap.items.length, 1);
    });

    test('notas passam pelo aprender sem desarmar', () async {
      final (c, e) = await rig();
      expect(c.midiLearn.arm(1, cutoff), isTrue);
      e.onMidi!(0x90, 60, 100);
      e.onMidi!(0x80, 60, 0);
      expect(c.midiLearn.armed, isNotNull);
      expect(e.sent('live_on'), isNotEmpty);
    });

    test('aprender de novo o mesmo controle substitui; outro controle no mesmo CC convive; remover e limpar', () async {
      final (c, e) = await rig();
      learn(c, e, 1, cutoff, d1: 74);
      learn(c, e, 1, cutoff, d1: 75);
      expect(c.doc.midiMap.items.length, 1);
      expect(c.doc.midiMap.items.single.source.cc, 75);
      learn(c, e, 1, unison, d1: 75);
      expect(c.doc.midiMap.items.length, 2, reason: 'um CC pode comandar dois controles');
      expect(c.midiLearn.removeFor(1, cutoff), isTrue);
      expect(c.midiLearn.removeFor(1, cutoff), isFalse);
      expect(c.doc.midiMap.items.length, 1);
      c.midiLearn.clear();
      expect(c.doc.midiMap.isEmpty, isTrue);
    });

    test('recusa armar alvo que não existe e Esc desarma antes de sair do modo', () async {
      final (c, _) = await rig();
      expect(c.midiLearn.arm(0, cutoff), isFalse, reason: 'faixa de áudio não tem parâmetro de instrumento');
      expect(c.midiLearn.arm(1, const AutoTarget(AutoKind.effect, ref: 'nada', param: 1)), isFalse);
      expect(c.midiLearn.learning, isFalse);
      c.midiLearn.arm(1, cutoff);
      c.midiLearn.escape();
      expect(c.midiLearn.armed, isNull);
      expect(c.midiLearn.learning, isTrue);
      c.midiLearn.escape();
      expect(c.midiLearn.learning, isFalse);
    });

    test('sem o modo ligado, um CC não mapeado segue sendo expressão (CC 1 e pedal)', () async {
      final (c, e) = await rig();
      e.onMidi!(0xB0, 1, 127);
      e.onMidi!(0xB0, 64, 127);
      expect(e.sent('live_cc').length, 2);
      expect(c.doc.midiMap.isEmpty, isTrue);
    });
  });

  group('conflito com a expressão', () {
    test('CC 1, pedal e bend mapeados de propósito vão ao parâmetro e não ao instrumento', () async {
      final (c, e) = await rig();
      c.midiLearn.setSoft(false);
      learn(c, e, 1, cutoff, d1: 1);
      learn(c, e, 1, unison, d1: 64);
      e.log = [];
      e.onMidi!(0xB0, 1, 127);
      e.onMidi!(0xB0, 64, 127);
      expect(e.sent('live_cc'), isEmpty);
      expect(c.doc.tracks[1].param(13), closeTo(20000, 1e-3));
      expect(c.doc.tracks[1].param(9), 7);
      // outro canal do mesmo CC não está mapeado: continua expressão
      e.onMidi!(0xB1, 1, 127);
      expect(e.sent('live_cc').length, 1);
      // e tirar o mapeamento devolve o CC 1 ao instrumento
      c.midiLearn.removeFor(1, cutoff);
      e.onMidi!(0xB0, 1, 127);
      expect(e.sent('live_cc').length, 2);
    });
  });

  group('takeover suave', () {
    test('o controle que já tem valor não salta: só assume ao cruzar o valor atual', () async {
      final (c, e) = await rig();
      final info = c.autoInfo(1, const AutoTarget(AutoKind.instrument, param: 1))!;
      expect(info.fixed, 0.8);
      const level = AutoTarget(AutoKind.instrument, param: 1); // 0..1, padrão 0,8
      learn(c, e, 1, level, d1: 30, d2: 10);
      expect(c.midiLearn.map.soft, isTrue);
      e.onMidi!(0xB0, 30, 20);
      e.onMidi!(0xB0, 30, 60);
      expect(c.doc.tracks[1].param(1), 0.8, reason: 'ainda longe (o controlador está em 47%)');
      e.onMidi!(0xB0, 30, 90); // 71%: ainda abaixo de 80%
      expect(c.doc.tracks[1].param(1), 0.8);
      e.onMidi!(0xB0, 30, 110); // 87%: cruzou 80%
      expect(c.doc.tracks[1].param(1), closeTo(110 / 127, 1e-9));
      e.onMidi!(0xB0, 30, 40); // já assumiu: segue para baixo sem prender
      expect(c.doc.tracks[1].param(1), closeTo(40 / 127, 1e-9));
    });

    test('chegar perto (2%) também assume, e cruzar vindo de cima', () async {
      final (c, e) = await rig();
      const level = AutoTarget(AutoKind.instrument, param: 1);
      learn(c, e, 1, level, d1: 30, d2: 127);
      e.onMidi!(0xB0, 30, 120);
      expect(c.doc.tracks[1].param(1), 0.8);
      e.onMidi!(0xB0, 30, 100); // 78,7%: a 1,3% de 80%: pega
      expect(c.doc.tracks[1].param(1), closeTo(100 / 127, 1e-9));
    });

    test('mexer no controle com o mouse depois o solta do controlador até ele cruzar de novo', () async {
      final (c, e) = await rig();
      const level = AutoTarget(AutoKind.instrument, param: 1);
      learn(c, e, 1, level, d1: 30, d2: 100);
      e.onMidi!(0xB0, 30, 102); // perto de 80%: assume
      expect(c.doc.tracks[1].param(1), closeTo(102 / 127, 1e-9));
      c.setParam(1, 1, 0.2); // a mão foi ao mouse
      e.onMidi!(0xB0, 30, 105);
      expect(c.doc.tracks[1].param(1), 0.2, reason: 'o controlador está longe do 0,2: não salta');
      e.onMidi!(0xB0, 30, 40); // 31%: ainda acima do 0,2
      expect(c.doc.tracks[1].param(1), 0.2);
      e.onMidi!(0xB0, 30, 20); // 15,7%: cruzou 20%
      expect(c.doc.tracks[1].param(1), closeTo(20 / 127, 1e-9));
    });

    test('desligado, o controle salta direto para o valor do controlador', () async {
      final (c, e) = await rig();
      const level = AutoTarget(AutoKind.instrument, param: 1);
      learn(c, e, 1, level, d1: 30, d2: 10);
      c.midiLearn.setSoft(false);
      e.onMidi!(0xB0, 30, 20);
      expect(c.doc.tracks[1].param(1), closeTo(20 / 127, 1e-9));
    });

    test('com faixa estreita, um controle fora dela é alcançado pela borda', () async {
      final (c, e) = await rig();
      const level = AutoTarget(AutoKind.instrument, param: 1); // está em 0,8
      final m = learn(c, e, 1, level, d1: 30, d2: 0);
      c.midiLearn.update(m.id, min: 0.1, max: 0.5);
      e.onMidi!(0xB0, 30, 0);
      expect(c.doc.tracks[1].param(1), 0.8, reason: 'controlador em 10%, controle em 80% fora da faixa');
      e.onMidi!(0xB0, 30, 127);
      expect(c.doc.tracks[1].param(1), closeTo(0.5, 1e-9), reason: 'chegou ao teto da faixa (50%)');
    });
  });

  group('alvos que não existem mais', () {
    test('efeito removido, faixa apagada e tipo trocado são ignorados sem quebrar', () async {
      final (c, e) = await rig();
      c.midiLearn.setSoft(false);
      final slot = c.addEffect(1, EffectKind.reverb);
      final fx = AutoTarget(AutoKind.effect, ref: slot.id, param: slot.kind.params.first.id);
      final mFx = learn(c, e, 1, fx, d1: 20);
      final mCut = learn(c, e, 1, cutoff, d1: 21);
      expect(c.midiLearn.alive(mFx), isTrue);
      expect(c.midiLearn.targetLabel(mFx), startsWith('Sintetizador 1 · Reverb'));
      c.removeEffect(1, slot.id);
      e.log = [];
      e.onMidi!(0xB0, 20, 100);
      expect(e.sent('fx_param'), isEmpty);
      expect(c.midiLearn.alive(mFx), isFalse);
      expect(c.midiLearn.targetLabel(mFx), contains('alvo removido'));
      expect(c.doc.midiMap.items.length, 2, reason: 'o mapeamento fica na lista para o usuário remover');
      // faixa apagada
      c.removeTrack(1);
      e.onMidi!(0xB0, 21, 100);
      expect(c.midiLearn.alive(mCut), isFalse);
      expect(c.midiLearn.targetLabel(mCut), 'Faixa removida');
      expect(c.doc.tracks.length, 1);
      // e o id de faixa que sumiu nunca cai no master (índice −1)
      expect(c.doc.masterGain, 1);
      expect(c.doc.masterPan, 0);
    });

    test('mapeamento da faixa apagada não vira o do master', () async {
      final (c, e) = await rig();
      c.midiLearn.setSoft(false);
      learn(c, e, 1, volume, d1: 7);
      c.removeTrack(1);
      e.onMidi!(0xB0, 7, 0);
      expect(c.doc.masterGain, 1);
    });

    test('um CC mapeado a alvo morto ainda é consumido: não vira expressão às escondidas', () async {
      final (c, e) = await rig();
      final slot = c.addEffect(1, EffectKind.reverb);
      learn(c, e, 1, AutoTarget(AutoKind.effect, ref: slot.id, param: slot.kind.params.first.id), d1: 1);
      c.removeEffect(1, slot.id);
      e.log = [];
      e.onMidi!(0xB0, 1, 127);
      expect(e.sent('live_cc'), isEmpty);
    });
  });

  group('efeitos no documento e no histórico', () {
    test('um gesto do controlador é um passo de desfazer; parado por 700 ms ele acaba', () async {
      final (c, e) = await rig();
      c.midiLearn.setSoft(false);
      learn(c, e, 1, cutoff, d1: 74);
      final before = c.doc.tracks[1].param(13);
      for (final v in [10, 20, 30, 40, 50]) {
        e.onMidi!(0xB0, 74, v);
      }
      expect(c.midiLearn.openRuns, 1);
      expect(c.doc.tracks[1].param(13), isNot(before));
      c.undo();
      expect(c.doc.tracks[1].param(13), before, reason: 'a rajada inteira volta num desfazer só');
      await Future<void>.delayed(midiIdleRelease + const Duration(milliseconds: 150));
      expect(c.midiLearn.openRuns, 0);
    });

    test('grava automação pelo caminho dos setters quando o modo está armado', () async {
      final (c, e) = await rig();
      c.midiLearn.setSoft(false);
      learn(c, e, 1, cutoff, d1: 74);
      c.autoRec.setMode(AutoMode.latch);
      c.beat.value = 1;
      c.playing.value = true;
      c.beat.value = 2;
      e.onMidi!(0xB0, 74, 20);
      c.beat.value = 3;
      e.onMidi!(0xB0, 74, 80);
      c.beat.value = 4;
      e.onMidi!(0xB0, 74, 127);
      c.playing.value = false;
      final lane = c.doc.tracks[1].lanes.firstWhere((l) => l.target == cutoff);
      expect(lane.points, isNotEmpty);
      expect(lane.points.map((p) => p.beat), containsAll([2.0, 4.0]));
      expect(lane.points.last.value, closeTo(20000, 1e-3));
    });

    test('mapa padrão: só volume, pan e instrumento, faixas por posição; some o que não cabe', () async {
      final (c, e) = await rig();
      final slot = c.addEffect(1, EffectKind.reverb);
      learn(c, e, 1, cutoff, d1: 74);
      learn(c, e, 0, volume, d1: 7);
      learn(c, e, -1, pan, d1: 10);
      learn(c, e, 1, AutoTarget(AutoKind.effect, ref: slot.id, param: slot.kind.params.first.id), d1: 20);
      final json = jsonDecode(jsonEncode(midiDefaultToJson(c.doc.midiMap, c.doc.tracks)));
      final newTracks = [DawTrack(id: 'n0', name: 'A', color: 0), DawTrack(id: 'n1', name: 'S', color: 0, kind: TrackKind.synth)];
      var k = 0;
      final map = midiDefaultFrom(json, newTracks, () => 'id${k++}');
      expect(map.items.length, 3, reason: 'o efeito não vai no padrão');
      expect(map.items.map((m) => (m.trackId, m.target)).toSet(), {('n1', cutoff), ('n0', volume), (null, pan)});
      // projeto novo com uma faixa só: o mapeamento da faixa 1 é descartado
      final small = midiDefaultFrom(json, [newTracks.first], () => 'z${k++}');
      expect(small.items.length, 2);
      expect(midiDefaultFrom('lixo', newTracks, () => 'x').isEmpty, isTrue);
    });

    test('abrir um projeto novo aplica o padrão guardado; um projeto que já tem documento não é tocado', () async {
      final store = MemoryStore();
      final e = FakeEngine();
      final src = fakeController(e, store: store);
      src.addInstrumentTrack(TrackKind.synth);
      await src.enableMidiInput();
      learn(src, e, 0, volume, d1: 7);
      learn(src, e, -1, pan, d1: 10);
      await saveMidiDefault(store, src.doc.midiMap, src.doc.tracks);

      final fresh = fakeController(FakeEngine(), store: store);
      await fresh.open();
      expect(fresh.doc.midiMap.items.map((m) => (m.source.cc, m.target.kind, m.trackId)).toSet(), {
        (7, AutoKind.volume, fresh.doc.tracks.first.id),
        (10, AutoKind.pan, null),
      });
      expect(fresh.doc.midiMap.items.map((m) => m.id).toSet().length, 2, reason: 'ids novos, não os do projeto de origem');

      // o mesmo projeto reaberto lê o documento salvo, sem reaplicar o padrão por cima
      store.data['doc:p'] = jsonEncode(
        (DawDoc(
          bpm: 100,
          beatsPerBar: 4,
          tracks: [DawTrack(id: 'z', name: 'Z', color: 0)],
        )).toJson(),
      );
      final reopened = fakeController(FakeEngine(), store: store);
      await reopened.open();
      expect(reopened.doc.bpm, 100);
      expect(reopened.doc.midiMap.isEmpty, isTrue);
    });

    test('padrão guardado localmente entra num projeto novo', () async {
      final store = MemoryStore();
      final e = FakeEngine();
      final src = fakeController(e, store: store);
      src.addInstrumentTrack(TrackKind.synth);
      await src.enableMidiInput();
      learn(src, e, 1, cutoff);
      await saveMidiDefault(store, src.doc.midiMap, src.doc.tracks);
      final json = await loadMidiDefault(store);
      expect(json, isA<Map>());
      await clearMidiDefault(store);
      expect(await loadMidiDefault(store), isNull);
      await store.put(midiDefaultKey, '{quebrado');
      expect(await loadMidiDefault(store), isNull, reason: 'guardado corrompido não derruba a abertura');
    });
  });
}

double gainToFaderRoundTrip(AutoInfo info, double gain) => info.warp!.toNorm(gain);
