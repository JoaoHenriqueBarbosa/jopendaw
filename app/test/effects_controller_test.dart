// Controlador da fase 3: efeitos, barramentos, envios, saídas, automação e observação, conferidos
// pelas chamadas que iriam ao motor (o stub guarda em `engine.log`).
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jopendaw_app/audio/engine.dart';
import 'package:jopendaw_app/daw/controller.dart';
import 'package:jopendaw_app/daw/effects.dart';
import 'package:jopendaw_app/daw/instruments.dart';
import 'package:jopendaw_app/daw/model.dart';
import 'package:jopendaw_app/models/project.dart';

final engine = AudioEngine.instance;

Project _project() => Project.fromJson({
  'id': 'p',
  'name': 'Teste',
  'bpm': 120,
  'beats_per_bar': 4,
  'beat_unit': 4,
  'sample_rate': 48000,
  'created_at': '2026-01-01T00:00:00Z',
  'updated_at': '2026-01-01T00:00:00Z',
});

/// Controlador com uma faixa de áudio ('a') e um sintetizador ('s'), já sincronizado uma vez.
DawController newController() {
  final c = DawController(_project());
  c.doc = DawDoc(
    bpm: 120,
    beatsPerBar: 4,
    tracks: [
      DawTrack(id: 'a', name: 'Áudio 1', color: 0),
      DawTrack(id: 's', name: 'Sintetizador 1', color: 1, kind: TrackKind.synth),
    ],
  );
  c.ready = true;
  c.mutate((_) {});
  engine.log = [];
  return c;
}

List<List<Object>> sent(String name) => [
  for (final c in engine.log!)
    if (c.first == name) c,
];

int firstIndex(String name) => engine.log!.indexWhere((c) => c.first == name);
int lastIndex(String name) => engine.log!.lastIndexWhere((c) => c.first == name);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => engine.log = []);

  group('efeitos', () {
    test('adicionar manda contagem, tipo, todos os parâmetros e o bypass, depois dos instrumentos e antes das notas', () {
      final c = newController();
      c.createMidiClip(1, 0);
      engine.log = [];
      final slot = c.addEffect(1, EffectKind.reverb);
      expect(c.effectsOf(1), [slot]);
      expect(slot.params, defaultEffectParams(EffectKind.reverb));
      expect(sent('fx_count'), [
        ['fx_count', 1, 1],
      ]);
      expect(sent('fx_set'), [
        ['fx_set', 1, 0, EffectKind.reverb.code],
      ]);
      expect(sent('fx_param'), hasLength(reverbParams.length));
      expect(sent('fx_param'), contains(equals(['fx_param', 1, 0, 3, 2.2])));
      expect(sent('fx_bypass'), [
        ['fx_bypass', 1, 0, false],
      ]);
      // notas mudando sozinhas não reenviam efeito; quando os dois mudam, as notas vão depois
      engine.log = [];
      c.edit((d) => d.tracks[1].midi.first.notes.add(MidiNote(pitch: 60, start: 0, length: 1)));
      expect(lastIndex('fx_param'), -1); // nada de efeito mudou
      engine.log = [];
      c.edit((d) {
        d.tracks[1].midi.first.notes.add(MidiNote(pitch: 62, start: 1, length: 1));
        d.tracks[1].effects.first.params[0] = 0.5;
      });
      expect(firstIndex('fx_param'), lessThan(firstIndex('notes_clear')));
      expect(firstIndex('auto_clear'), -1); // automação igual: não reenvia
      // desfazer tira o efeito do motor
      engine.log = [];
      c.undo();
      c.undo();
      c.undo();
      expect(c.effectsOf(1), isEmpty);
      expect(sent('fx_count').last, ['fx_count', 1, 0]);
    });

    test('cadeia fora da faixa: efeitos em posição, master em −1 e faixa inexistente recusada', () {
      final c = newController();
      final eq = c.addEffect(-1, EffectKind.eq);
      final lim = c.addEffect(-1, EffectKind.limiter);
      final comp = c.addEffect(-1, EffectKind.compressor, at: 0);
      expect(c.effectsOf(-1).map((s) => s.id), [comp.id, eq.id, lim.id]);
      expect(sent('fx_count').last, ['fx_count', -1, 3]);
      expect(sent('fx_set').last, ['fx_set', -1, 2, EffectKind.limiter.code]);
      expect(() => c.addEffect(5, EffectKind.eq), throwsArgumentError);
      expect(c.effectsOf(9), isEmpty);
      expect(() => (c.effectsOf(-1) as List).add(eq), throwsUnsupportedError);
    });

    test('bypass manda só o bypass daquele slot; desfazível', () {
      final c = newController();
      final slot = c.addEffect(0, EffectKind.delay);
      engine.log = [];
      c.setEffectBypass(0, slot.id, true);
      expect(sent('fx_bypass'), [
        ['fx_bypass', 0, 0, true],
      ]);
      expect(sent('fx_param'), isEmpty);
      expect(sent('fx_set'), isEmpty);
      expect(sent('fx_count'), isEmpty);
      engine.log = [];
      c.setEffectBypass(0, slot.id, true); // já está
      expect(engine.log, isEmpty);
      c.undo();
      expect(c.effectsOf(0).single.bypass, isFalse);
      expect(sent('fx_bypass'), [
        ['fx_bypass', 0, 0, false],
      ]);
    });

    test('setEffectParam manda só o fx_param, limitado e arredondado; undoable entra no histórico', () {
      final c = newController();
      c.addEffect(1, EffectKind.eq);
      final comp = c.addEffect(1, EffectKind.compressor);
      engine.log = [];
      c.setEffectParam(1, comp.id, 0, -100); // limiar: −60..0
      expect(engine.log, [
        ['fx_param', 1, 1, 0, -60.0],
      ]);
      engine.log = [];
      c.setEffectParam(1, comp.id, 7, 0.4); // detector é opção
      expect(engine.log, [
        ['fx_param', 1, 1, 7, 0.0],
      ]);
      engine.log = [];
      c.setEffectParam(1, comp.id, 7, 0); // igual: nada
      c.setEffectParam(1, comp.id, 999, 1); // id desconhecido
      c.setEffectParam(1, 'nenhum', 0, -10);
      expect(engine.log, isEmpty);
      // o sync seguinte sabe que o parâmetro já foi
      c.toggleLoop();
      expect(sent('fx_param'), isEmpty);
      engine.log = [];
      c.setEffectParam(1, comp.id, 1, 8, undoable: true);
      expect(engine.log, [
        ['fx_param', 1, 1, 1, 8.0],
      ]);
      engine.log = [];
      c.undo();
      expect(c.effectsOf(1)[1].param(1), 4);
      expect(sent('fx_param'), [
        ['fx_param', 1, 1, 1, 4.0],
      ]);
    });

    test('tipo que muda no slot reenvia fx_set e tudo do slot; o mesmo tipo manda só a diferença', () {
      final c = newController();
      final rev = c.addEffect(0, EffectKind.reverb);
      final dly = c.addEffect(0, EffectKind.delay);
      engine.log = [];
      c.moveEffect(0, dly.id, 0);
      expect(c.effectsOf(0).map((s) => s.kind), [EffectKind.delay, EffectKind.reverb]);
      expect(sent('fx_set'), [
        ['fx_set', 0, 0, EffectKind.delay.code],
        ['fx_set', 0, 1, EffectKind.reverb.code],
      ]);
      expect(sent('fx_param'), hasLength(delayParams.length + reverbParams.length));
      expect(sent('fx_count'), isEmpty);
      engine.log = [];
      c.removeEffect(0, dly.id);
      expect(sent('fx_count'), [
        ['fx_count', 0, 1],
      ]);
      expect(sent('fx_set'), [
        ['fx_set', 0, 0, EffectKind.reverb.code],
      ]);
      // dois reverbs trocando de lugar: o motor fica com os dois, só os parâmetros diferentes vão
      final rev2 = c.addEffect(0, EffectKind.reverb);
      c.setEffectParam(0, rev2.id, 0, 0.9);
      engine.log = [];
      c.moveEffect(0, rev.id, 1);
      expect(sent('fx_set'), isEmpty);
      expect(sent('fx_param'), [
        ['fx_param', 0, 0, 0, 0.9],
        ['fx_param', 0, 1, 0, 0.25],
      ]);
      c.moveEffect(0, rev.id, 1); // já está lá
      c.moveEffect(0, 'nenhum', 0);
    });

    test('preset: o que falta volta ao padrão, o sidechain fica', () {
      final c = newController();
      final comp = c.addEffect(0, EffectKind.compressor);
      c.setEffectParam(0, comp.id, 10, 1);
      c.setEffectParam(0, comp.id, 4, 12);
      c.applyEffectPreset(0, comp.id, {0: -30, 1: 50});
      final s = c.effectsOf(0).single;
      expect(s.param(0), -30);
      expect(s.param(1), 20); // limitado
      expect(s.param(4), 6); // padrão
      expect(s.param(10), 1); // sidechain ficou
      c.undo();
      expect(c.effectsOf(0).single.param(4), 12);
    });

    test('apagar ou mover faixa leva junto o índice do sidechain', () {
      final c = newController();
      c.addInstrumentTrack(TrackKind.drums); // 2
      final comp = c.addEffect(1, EffectKind.compressor);
      final gate = c.addEffect(-1, EffectKind.gate);
      c.setEffectParam(1, comp.id, 10, 2); // chave: a bateria
      c.setEffectParam(-1, gate.id, 6, 0); // chave: o áudio
      c.removeTrack(0);
      expect(c.effectsOf(0).single.param(10), 1);
      expect(c.effectsOf(-1).single.param(6), -1); // a faixa-chave sumiu
      c.moveTrack(1, 0); // bateria vai para cima
      expect(c.doc.tracks.map((t) => t.id).first, isNot('s'));
      expect(c.effectsOf(1).single.param(10), 0);
    });

    test('documento da fase 2 abre sem efeitos, envios nem automação e zera o motor', () {
      final c = DawController(_project());
      final old = {
        'version': 1,
        'bpm': 120,
        'beats_per_bar': 4,
        'tracks': [
          {'id': 'a', 'name': 'Áudio 1', 'color': 0, 'gain': 1, 'pan': 0, 'mute': false, 'solo': false, 'clips': []},
          {'id': 's', 'name': 'Synth', 'color': 1, 'gain': 1, 'pan': 0, 'mute': false, 'solo': false, 'kind': 'synth', 'params': {}, 'clips': [], 'midi': []},
        ],
        'samples': {},
        'loop_on': false,
        'loop_start': 0,
        'loop_end': 16,
        'metronome': false,
        'master_gain': 1,
        'master_pan': 0,
      };
      c.doc = DawDoc.fromJson(jsonDecode(jsonEncode(old)));
      c.mutate((_) {});
      expect(c.effectsOf(0), isEmpty);
      expect(c.effectsOf(-1), isEmpty);
      expect(c.automatable(1).length, 2 + synthParams.length);
      expect(sent('fx_count'), [
        ['fx_count', 0, 0],
        ['fx_count', 1, 0],
        ['fx_count', -1, 0],
      ]);
      expect(sent('sends_count'), [
        ['sends_count', 0, 0],
        ['sends_count', 1, 0],
      ]);
      expect(sent('track_output'), [
        ['track_output', 0, -1],
        ['track_output', 1, -1],
      ]);
      expect(sent('auto_clear'), hasLength(1));
      expect(sent('auto_lane'), isEmpty);
      expect(sent('watch_fx'), [
        ['watch_fx', -1, -1],
      ]);
      expect(sent('watch_analyzer'), [
        ['watch_analyzer', -2],
      ]);
      // o formato novo volta igual
      final again = DawDoc.fromJson(jsonDecode(jsonEncode(c.doc.toJson())));
      expect(again.toJson(), c.doc.toJson());
    });
  });

  group('barramentos e envios', () {
    test('barramento novo no fim, numerado, selecionado; o motor recebe o tipo 4', () {
      final c = newController();
      final b1 = c.addBusTrack();
      final b2 = c.addBusTrack();
      expect(c.doc.tracks.map((t) => t.name), ['Áudio 1', 'Sintetizador 1', 'Barramento 1', 'Barramento 2']);
      expect(b1.kind, TrackKind.bus);
      expect(c.selectedTrack, 3);
      expect(b1.color, isNot(b2.color));
      expect(sent('track_kind'), [
        ['track_kind', 2, 4],
        ['track_kind', 3, 4],
      ]);
      c.addInstrumentTrack(TrackKind.bus);
      expect(c.doc.tracks.last.name, 'Barramento 3');
      // barramento não recebe clipe
      c.doc.samples['h'] = const SampleInfo('x.wav', 1);
      c.edit((d) => d.tracks[0].clips.add(AudioClip(id: 'c1', sample: 'h', start: 0, length: 1)));
      c.moveClipToTrack('c1', 2);
      expect(c.doc.tracks[0].clips.single.id, 'c1');
    });

    test('envio resolve o índice do barramento, nasce em −6 dB pós-fader e ignora destino que não existe', () {
      final c = newController();
      final bus = c.addBusTrack(); // 2
      engine.log = [];
      expect(c.setSend(0, bus.id), isTrue);
      expect(c.doc.tracks[0].sends.single.level, 0.5);
      expect(sent('sends_count'), [
        ['sends_count', 0, 1],
      ]);
      expect(sent('send_set'), [
        ['send_set', 0, 0, 2, 0.5, false],
      ]);
      // um envio para barramento que não existe (documento de outra versão, desfeito): fica no
      // documento, mas não vai ao motor, e os índices dos outros não andam
      c.edit((d) => d.tracks[1].sends.addAll([Send(target: 'fantasma'), Send(target: bus.id, level: 1, pre: true)]));
      expect(sent('sends_count').last, ['sends_count', 1, 1]);
      expect(sent('send_set').last, ['send_set', 1, 0, 2, 1.0, true]);
      expect(c.setSend(0, 'fantasma'), isFalse);
      expect(c.setSend(0, 's'), isFalse); // não é barramento
      expect(c.setSend(2, bus.id), isFalse); // ele mesmo
      expect(c.setSend(-1, bus.id), isFalse); // o master não envia
    });

    test('nível do envio vai pelo caminho rápido; undoable entra no histórico', () {
      final c = newController();
      final bus = c.addBusTrack();
      c.setSend(1, bus.id);
      engine.log = [];
      c.setSend(1, bus.id, level: 5); // limitado a +6 dB
      expect(engine.log, [
        ['send_set', 1, 0, 2, 2.0, false],
      ]);
      engine.log = [];
      c.setSend(1, bus.id, pre: true, undoable: true);
      expect(engine.log, [
        ['send_set', 1, 0, 2, 2.0, true],
      ]);
      c.undo();
      expect(c.doc.tracks[1].sends.single.pre, isFalse);
      c.undo();
      c.undo(); // antes do envio
      expect(c.doc.tracks[1].sends, isEmpty);
      expect(sent('sends_count').last, ['sends_count', 1, 0]);
    });

    test('busTargets impede ciclo: barramento só manda para barramento depois dele', () {
      final c = newController();
      final b1 = c.addBusTrack(); // 2
      final b2 = c.addBusTrack(); // 3
      final b3 = c.addBusTrack(); // 4
      expect(c.busTargets(0).map((t) => t.id), [b1.id, b2.id, b3.id]);
      expect(c.busTargets(2).map((t) => t.id), [b2.id, b3.id]);
      expect(c.busTargets(3).map((t) => t.id), [b3.id]);
      expect(c.busTargets(4), isEmpty);
      expect(c.busTargets(-1), isEmpty);
      expect(c.setSend(3, b2.id), isFalse);
      expect(c.setSend(4, b1.id), isFalse); // b1 → … → b3 → b1 seria ciclo
      expect(c.setSend(2, b3.id), isTrue);
    });

    test('setOutput recusa ciclo; saída vai como índice do barramento ou −1', () {
      final c = newController();
      final b1 = c.addBusTrack(); // 2
      final b2 = c.addBusTrack(); // 3
      engine.log = [];
      expect(c.setOutput(2, b2.id), isTrue);
      expect(sent('track_output'), [
        ['track_output', 2, 3],
      ]);
      expect(c.setOutput(3, b1.id), isFalse);
      expect(c.setOutput(2, b1.id), isFalse); // ela mesma
      expect(c.setOutput(1, 'a'), isFalse); // não é barramento
      expect(c.doc.tracks[3].output, isNull);
      expect(c.setOutput(1, b1.id), isTrue);
      engine.log = [];
      expect(c.setOutput(1, null), isTrue);
      expect(sent('track_output'), [
        ['track_output', 1, -1],
      ]);
      c.undo();
      expect(c.doc.tracks[1].output, b1.id);
    });

    test('mover faixa avisa antes o que desfaria entre barramentos', () {
      final c = newController();
      final b1 = c.addBusTrack(); // 2
      final b2 = c.addBusTrack(); // 3
      c.setOutput(2, b2.id);
      c.setSend(2, b2.id);
      c.addLane(2, AutoTarget(AutoKind.send, ref: b2.id));
      // faixa comum e barramentos na ordem certa: nada quebra
      expect(c.routesBrokenByMove(0, 1), isEmpty);
      expect(c.routesBrokenByMove(3, 3), isEmpty);
      // b2 antes de b1: o envio (com a automação) e a saída de b1 apontariam para trás
      final warn = c.routesBrokenByMove(3, 2);
      expect(warn, hasLength(2));
      expect(warn.join(' '), allOf(contains(b1.name), contains(b2.name), contains('automação'), contains('master')));
      // o aviso não mexe em nada; mover de fato desfaz, e desfazer volta
      expect(c.doc.tracks[2].output, b2.id);
      c.moveTrack(3, 2);
      expect(c.doc.tracks[3].output, isNull);
      c.undo();
      expect(c.doc.tracks[2].output, b2.id);
      expect(c.doc.tracks[2].sends, hasLength(1));
    });

    test('apagar um barramento limpa envios, saídas e a automação desses envios', () {
      final c = newController();
      final b1 = c.addBusTrack(); // 2
      final b2 = c.addBusTrack(); // 3
      c.setSend(0, b1.id);
      c.setSend(0, b2.id);
      c.setOutput(1, b1.id);
      c.setOutput(2, b2.id);
      final lane = c.addLane(0, AutoTarget(AutoKind.send, ref: b2.id));
      c.edit((_) => lane.points.add(AutoPoint(beat: 0, value: 1)));
      c.addLane(0, AutoTarget(AutoKind.send, ref: b1.id));
      engine.log = [];
      c.removeTrack(2);
      final a = c.doc.tracks[0];
      expect(a.sends.map((s) => s.target), [b2.id]);
      expect(a.lanes.map((l) => l.target.ref), [b2.id]);
      expect(c.doc.tracks[1].output, isNull);
      // os índices mudaram: tudo de novo, com o barramento 2 agora no índice 2
      expect(sent('send_set'), [
        ['send_set', 0, 0, 2, 0.5, false],
      ]);
      expect(
        sent('track_output'),
        containsAll([
          ['track_output', 1, -1],
          ['track_output', 2, -1],
        ]),
      );
      expect(sent('auto_lane'), [
        ['auto_lane', 0, 4, 0, 0],
      ]);
      c.undo();
      expect(c.doc.tracks[0].sends, hasLength(2));
      expect(c.doc.tracks[1].output, b1.id);
    });

    test('mover faixa desfaz o roteamento de barramento que passa a apontar para trás', () {
      final c = newController();
      final b1 = c.addBusTrack(); // 2
      final b2 = c.addBusTrack(); // 3
      c.setSend(2, b2.id);
      c.setOutput(2, b2.id);
      c.setSend(0, b1.id);
      c.selectTrack(0);
      c.moveTrack(3, 0); // b2 vai para o topo: b1 (agora 3) não pode mais mandar para ele (0)
      expect(c.doc.tracks.map((t) => t.id), [b2.id, 'a', 's', b1.id]);
      expect(c.doc.tracks[3].sends, isEmpty);
      expect(c.doc.tracks[3].output, isNull);
      expect(c.doc.tracks[1].sends.single.target, b1.id); // faixa comum manda para qualquer um
      expect(c.selectedTrack, 1);
      c.undo();
      expect(c.doc.tracks[2].output, b2.id);
    });
  });

  group('automação', () {
    test('auto_lane/auto_point com slot do efeito e índice do envio resolvidos, na unidade do alvo', () {
      final c = newController();
      final bus = c.addBusTrack(); // 2
      c.addEffect(1, EffectKind.eq);
      final flt = c.addEffect(1, EffectKind.filter);
      c.edit((d) => d.tracks[1].sends.addAll([Send(target: 'fantasma'), Send(target: bus.id)]));
      final cutoff = c.addLane(1, AutoTarget(AutoKind.effect, ref: flt.id, param: 1));
      final send = c.addLane(1, AutoTarget(AutoKind.send, ref: bus.id));
      final empty = c.addLane(1, const AutoTarget(AutoKind.pan));
      final master = c.addLane(-1, const AutoTarget(AutoKind.volume));
      engine.log = [];
      c.edit((_) {
        // fora de ordem e fora da faixa: vão ordenados e limitados
        cutoff.points.addAll([AutoPoint(beat: 4, value: 50000, curve: 3), AutoPoint(beat: 0, value: 200)]);
        send.points.add(AutoPoint(beat: 2, value: 0.25));
        master.points.addAll([AutoPoint(beat: 8, value: 1), AutoPoint(beat: 8, value: 0.5)]);
      });
      expect(empty.points, isEmpty);
      expect(sent('auto_clear'), hasLength(1));
      expect(firstIndex('auto_clear'), lessThan(firstIndex('auto_lane')));
      final auto = engine.log!.where((x) => x.first == 'auto_lane' || x.first == 'auto_point').toList();
      // o corte (Hz, escala logarítmica) anda na escala do botão: vai ao motor como pontos retos a
      // cada 1/8 de batida (32 no segmento de 4 batidas, mais o último), limitados à faixa
      final cut = auto.takeWhile((x) => x.first != 'auto_lane' || identical(x, auto.first)).toList();
      expect(cut.first, ['auto_lane', 1, 3, 1, 1]);
      expect(cut.skip(1), hasLength(33));
      expect(cut[1], ['auto_point', 0, 0.0, 200.0, 0.0]);
      expect(cut.last, ['auto_point', 0, 4.0, 20000.0, 0.0]);
      final hz = [for (final x in cut.skip(1)) x[3] as double];
      for (var i = 1; i < hz.length; i++) {
        expect(hz[i], greaterThanOrEqualTo(hz[i - 1]));
      }
      expect(auto.skip(cut.length).toList(), [
        ['auto_lane', 1, 4, 0, 0], // o envio fantasma não conta
        ['auto_point', 1, 2.0, 0.25, 0.0],
        ['auto_lane', -1, 0, 0, 0],
        ['auto_point', 2, 8.0, 1.0, 0.0], // degrau: a ordem de entrada fica
        ['auto_point', 2, 8.0, 0.5, 0.0],
      ]);
      // o efeito muda de lugar: o slot da lane acompanha
      engine.log = [];
      c.moveEffect(1, flt.id, 0);
      expect(sent('auto_lane').first, ['auto_lane', 1, 3, 0, 1]);
      // edição que não mexe na automação não a reenvia
      engine.log = [];
      c.toggleLoop();
      expect(sent('auto_clear'), isEmpty);
      // sem pontos em lugar nenhum: só limpa
      engine.log = [];
      c.edit((d) {
        for (final t in d.tracks) {
          t.lanes.clear();
        }
        d.masterLanes.clear();
      });
      expect(sent('auto_clear'), hasLength(1));
      expect(sent('auto_lane'), isEmpty);
    });

    test('instrumento e volume: alvo e valor; lane de parâmetro que o tipo não tem não vai', () {
      final c = newController();
      final lane = c.addLane(1, const AutoTarget(AutoKind.instrument, param: 13));
      final vol = c.addLane(0, const AutoTarget(AutoKind.volume));
      engine.log = [];
      c.edit((d) {
        lane.points.add(AutoPoint(beat: 0, value: 800, curve: -0.5));
        vol.points.add(AutoPoint(beat: 1, value: 3));
        d.tracks[0].lanes.add(AutoLane(id: 'x', target: const AutoTarget(AutoKind.instrument, param: 13), points: [AutoPoint(beat: 0, value: 1)]));
      });
      expect(engine.log!.where((x) => x.first == 'auto_lane' || x.first == 'auto_point').toList(), [
        ['auto_lane', 0, 0, 0, 0],
        ['auto_point', 0, 1.0, 2.0, 0.0],
        ['auto_lane', 1, 2, 0, 13],
        // parâmetro em escala logarítmica: a curva vira pontos retos (num ponto só, nada a dividir)
        ['auto_point', 1, 0.0, 800.0, 0.0],
      ]);
    });

    test('apagar o efeito apaga as lanes dele (e desfazer traz de volta)', () {
      final c = newController();
      final dly = c.addEffect(0, EffectKind.delay);
      final rev = c.addEffect(0, EffectKind.reverb);
      c.addLane(0, AutoTarget(AutoKind.effect, ref: dly.id, param: 0));
      final keep = c.addLane(0, AutoTarget(AutoKind.effect, ref: rev.id, param: 0));
      c.addLane(0, const AutoTarget(AutoKind.volume));
      c.removeEffect(0, dly.id);
      expect(c.doc.tracks[0].lanes.map((l) => l.target), [keep.target, const AutoTarget(AutoKind.volume)]);
      c.undo();
      expect(c.doc.tracks[0].lanes, hasLength(3));
      // no master também
      final m = c.addEffect(-1, EffectKind.limiter);
      c.addLane(-1, AutoTarget(AutoKind.effect, ref: m.id, param: 1));
      c.removeEffect(-1, m.id);
      expect(c.doc.masterLanes, isEmpty);
    });

    test('alvos automatizáveis: nomes para o menu, sem sidechain; o master só volume, pan e efeitos', () {
      final c = newController();
      final bus = c.addBusTrack();
      c.addEffect(1, EffectKind.compressor);
      c.addEffect(1, EffectKind.eq);
      c.addEffect(1, EffectKind.eq);
      c.setSend(1, bus.id);
      c.addEffect(-1, EffectKind.limiter);
      final names = [for (final (_, n) in c.automatable(1)) n];
      expect(names.take(2), ['Volume', 'Pan']);
      expect(names, contains('Instrumento · Corte'));
      expect(names, contains('Instrumento · Onda (Oscilador 2)'));
      expect(names, contains('Compressor · Limiar'));
      expect(names, isNot(contains('Compressor · Sidechain')));
      expect(names, contains('EQ 1 · Frequência (Banda 3)'));
      expect(names, contains('EQ 2 · Saída'));
      expect(names.last, 'Envio → Barramento 1');
      expect(names.toSet(), hasLength(names.length));
      expect(c.targetName(1, AutoTarget(AutoKind.send, ref: bus.id)), 'Envio → Barramento 1');
      final audio = [for (final (_, n) in c.automatable(0)) n];
      expect(audio, ['Volume', 'Pan']);
      final master = c.automatable(-1);
      expect(master.map((e) => e.$1.kind).toSet(), {AutoKind.volume, AutoKind.pan, AutoKind.effect});
      expect(master.length, 2 + limiterParams.length);
      expect(c.automatable(7), isEmpty);
    });

    test('addLane cria vazia e aberta, ou abre a que existe; alvo que a faixa não tem é recusado', () {
      final c = newController();
      final lane = c.addLane(1, const AutoTarget(AutoKind.pan));
      expect(lane.points, isEmpty);
      expect(lane.open, isTrue);
      c.edit((_) => lane.open = false);
      final again = c.addLane(1, const AutoTarget(AutoKind.pan));
      expect(again, same(lane));
      expect(lane.open, isTrue);
      expect(c.doc.tracks[1].lanes, hasLength(1));
      expect(() => c.addLane(0, const AutoTarget(AutoKind.instrument, param: 13)), throwsArgumentError);
      expect(() => c.addLane(-1, const AutoTarget(AutoKind.send, ref: 'x')), throwsArgumentError);
      expect(() => c.addLane(9, const AutoTarget(AutoKind.volume)), throwsArgumentError);
      c.removeLane(1, lane.id);
      expect(c.doc.tracks[1].lanes, isEmpty);
      c.undo();
      expect(c.doc.tracks[1].lanes, hasLength(1));
    });

    test('targetRange usa as tabelas e o valor atual', () {
      final c = newController();
      c.edit((d) {
        d.tracks[0].gain = 0.7;
        d.tracks[0].pan = -0.25;
        d.masterGain = 1.5;
      });
      expect(c.targetRange(0, const AutoTarget(AutoKind.volume)), (0.0, 2.0, 0.7));
      expect(c.targetRange(0, const AutoTarget(AutoKind.pan)), (-1.0, 1.0, -0.25));
      expect(c.targetRange(-1, const AutoTarget(AutoKind.volume)), (0.0, 2.0, 1.5));
      expect(c.targetRange(1, const AutoTarget(AutoKind.instrument, param: 13)), (20.0, 20000.0, 2400.0));
      final d = c.addEffect(1, EffectKind.delay);
      expect(c.targetRange(1, AutoTarget(AutoKind.effect, ref: d.id, param: 3)), (0.0, 11.0, 6.0));
      final bus = c.addBusTrack();
      c.setSend(0, bus.id, level: 0.3);
      expect(c.targetRange(0, AutoTarget(AutoKind.send, ref: bus.id)), (0.0, 2.0, 0.3));
      expect(c.targetRange(0, const AutoTarget(AutoKind.effect, ref: 'nada')), (0.0, 1.0, 0.0));
    });
  });

  group('painel e observação', () {
    test('showEffects abre o rack da faixa (e ele segue a faixa e a seleção)', () {
      final c = newController();
      c.showEffects(1);
      expect(c.dock, Dock.effects);
      expect(c.effectsTrack, 1);
      expect(c.selectedTrack, 1);
      c.selectTrack(0);
      expect(c.effectsTrack, 0);
      c.showEffects(-1);
      expect(c.effectsTrack, -1);
      c.showEffects(1);
      c.moveTrack(1, 0);
      expect(c.effectsTrack, 0);
      c.removeTrack(0); // a faixa do rack sumiu: vai para a selecionada, não para o master
      expect(c.effectsTrack, 0);
      c.effectsTrack = -1;
      expect(c.effectsTrack, -1);
      // a aba abre na faixa selecionada; o master é escolha explícita
      c.setDock(Dock.mixer);
      c.selectTrack(0);
      c.setDock(Dock.effects);
      expect(c.effectsTrack, 0);
    });

    test('com o rack aberto, faixa nova (e clipe novo) leva o rack junto, como a seleção', () {
      final c = newController();
      c.showEffects(0);
      c.addTrack();
      expect(c.effectsTrack, c.doc.tracks.length - 1);
      c.addInstrumentTrack(TrackKind.synth);
      expect(c.effectsTrack, c.doc.tracks.length - 1);
      final bus = c.addBusTrack();
      expect(c.effectsTrack, c.doc.tracks.indexOf(bus));
      c.createMidiClip(1, 0);
      expect(c.effectsTrack, 1);
      // com outro painel aberto, o rack guarda a faixa dele
      c.setDock(Dock.mixer);
      c.addTrack();
      expect(c.effectsTrack, 1);
    });

    test('parâmetro de um efeito que o motor ainda não tem vai pelo sync inteiro, não solto', () {
      final c = newController();
      final slot = EffectSlot(id: 'x', kind: EffectKind.chorus);
      c.doc.tracks[0].effects.add(slot); // sem passar pelo controlador
      c.setEffectParam(0, 'x', 0, 0.8);
      expect(sent('fx_set'), [
        ['fx_set', 0, 0, EffectKind.chorus.code],
      ]);
      expect(sent('fx_param'), contains(equals(['fx_param', 0, 0, 0, 0.8])));
      expect(firstIndex('fx_set'), lessThan(firstIndex('fx_param')));
    });

    test('watchEffect segue o slot, desliga quando ele some; o medidor chega do motor', () {
      final c = newController();
      final eq = c.addEffect(1, EffectKind.eq);
      final comp = c.addEffect(1, EffectKind.compressor);
      engine.log = [];
      c.watchEffect(1, comp.id);
      expect(engine.log, [
        ['watch_fx', 1, 1],
      ]);
      c.debugEngineState(EngineState(0, false, Float32List(0), fxMeter: 4.5));
      expect(c.fxMeter.value, 4.5);
      engine.log = [];
      c.moveEffect(1, eq.id, 1);
      expect(sent('watch_fx'), [
        ['watch_fx', 1, 0],
      ]);
      engine.log = [];
      c.removeEffect(1, comp.id);
      expect(sent('watch_fx'), [
        ['watch_fx', -1, -1],
      ]);
      expect(c.fxMeter.value, 0);
      // um estado atrasado não acende o medidor desligado
      c.debugEngineState(EngineState(0, false, Float32List(0), fxMeter: 3));
      expect(c.fxMeter.value, 0);
      engine.log = [];
      c.undo(); // o compressor volta (no lugar 0, depois da troca) e a observação com ele
      expect(sent('watch_fx'), [
        ['watch_fx', 1, 0],
      ]);
      engine.log = [];
      c.watchEffect(1, null);
      expect(engine.log, [
        ['watch_fx', -1, -1],
      ]);
    });

    test('watchAnalyzer: master, faixa, desliga; o espectro chega do motor', () {
      final c = newController();
      c.watchAnalyzer(-1);
      expect(engine.log, [
        ['watch_analyzer', -1],
      ]);
      final spec = Float32List(1024)..fillRange(0, 1024, -60);
      c.debugEngineState(EngineState(1, true, Float32List(0), spectrum: spec));
      expect(c.spectrum.value, same(spec));
      engine.log = [];
      c.watchAnalyzer(1);
      c.watchAnalyzer(1);
      expect(engine.log, [
        ['watch_analyzer', 1],
      ]);
      engine.log = [];
      c.moveTrack(1, 0); // a faixa observada muda de índice
      expect(sent('watch_analyzer'), [
        ['watch_analyzer', 0],
      ]);
      engine.log = [];
      c.watchAnalyzer(null);
      expect(engine.log, [
        ['watch_analyzer', -2],
      ]);
      expect(c.spectrum.value, isNull);
      c.debugEngineState(EngineState(1, true, Float32List(0), spectrum: spec));
      expect(c.spectrum.value, isNull);
    });
  });

  test('as chamadas novas saem com o número de argumentos do contrato', () {
    const arity = {
      'fx_set': 3,
      'fx_count': 2,
      'fx_param': 4,
      'fx_bypass': 3,
      'sends_count': 2,
      'send_set': 5,
      'track_output': 2,
      'auto_clear': 0,
      'auto_lane': 4,
      'auto_point': 4,
      'watch_fx': 2,
      'watch_analyzer': 1,
    };
    final c = newController();
    final bus = c.addBusTrack();
    final comp = c.addEffect(0, EffectKind.compressor);
    c.addEffect(-1, EffectKind.limiter);
    c.setSend(0, bus.id);
    c.setSend(0, bus.id, level: 0.2);
    c.setOutput(1, bus.id);
    c.setEffectParam(0, comp.id, 0, -20);
    c.setEffectBypass(0, comp.id, true);
    final lane = c.addLane(0, AutoTarget(AutoKind.effect, ref: comp.id, param: 0));
    c.edit((_) => lane.points.add(AutoPoint(beat: 0, value: -10)));
    c.watchEffect(0, comp.id);
    c.watchAnalyzer(-1);
    c.dispose();
    final seen = <String>{};
    for (final call in engine.log!) {
      final name = call.first as String;
      final n = arity[name];
      if (n == null) continue;
      seen.add(name);
      expect(call.length - 1, n, reason: 'argumentos de $name: $call');
      for (final a in call.skip(1)) {
        expect(a is num || a is bool, isTrue, reason: 'só números vão ao motor: $call');
      }
    }
    expect(seen, arity.keys.toSet());
  });
}
