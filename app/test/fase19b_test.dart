// Fase 19 (B): achados de punch, pré-roll, contagem, metrônomo, tap tempo e exportação. O motor é o
// FakeEngine (100 Hz, 120 BPM: 50 quadros por batida).
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jopendaw_app/audio/engine.dart';
import 'package:jopendaw_app/daw/controller.dart';
import 'package:jopendaw_app/daw/effects_panel.dart';
import 'package:jopendaw_app/daw/export_options.dart';
import 'package:jopendaw_app/daw/instruments.dart';
import 'package:jopendaw_app/daw/model.dart';
import 'package:jopendaw_app/daw/modulation_ops.dart';
import 'package:jopendaw_app/daw/wav.dart';

import 'fake_engine.dart';

EngineState state(double beat) => EngineState(beat, true, Float32List(0));

void main() {
  late FakeEngine e;
  setUp(() => e = FakeEngine());

  Future<DawController> armed({int preRoll = 0, bool countIn = false, double cursor = 8, bool metronome = false}) async {
    final c = fakeController(e);
    c.doc
      ..countIn = countIn
      ..metronome = metronome
      ..preRollBars = preRoll;
    c.beat.value = cursor;
    c.setArmed(0, true);
    await settle();
    return c;
  }

  group('contagem e pré-roll', () {
    test('(1) contagem com metrônomo desligado: o clique é só da contagem, o pré-roll toca sem clicar', () async {
      final c = await armed(preRoll: 1, countIn: true, cursor: 12);
      await c.toggleRecord();
      expect(e.sent('seek').last, ['seek', 4.0]);
      expect(e.sent('metronome').last[1], true, reason: 'a contagem pede o clique');
      c.debugEngineState(state(7.2));
      expect(e.sent('metronome').last[1], true);
      c.debugEngineState(state(7.6));
      expect(e.sent('metronome').last[1], false, reason: 'a contagem acabou (4 a 8): o pré-roll (8 a 12) não clica');
      expect(c.countingIn, isTrue);
      c.debugEngineState(state(10));
      expect(e.sent('metronome').last[1], false);
      c.debugEngineState(state(12.02));
      expect(c.countingIn, isFalse);
      e.feed(0, 450, (i) => 0.5);
      await c.toggleRecord();
      expect(c.doc.tracks[0].clips, isNotEmpty);
    });

    test('(1) com o metrônomo ligado os cliques seguem pelo pré-roll', () async {
      final c = await armed(preRoll: 1, countIn: true, cursor: 12, metronome: true);
      await c.toggleRecord();
      c.debugEngineState(state(10));
      expect(e.sent('metronome').last[1], true);
      await c.toggleRecord();
    });

    test('(1) parar no pré-roll cancela a gravação, com aviso (não some em silêncio)', () async {
      final c = await armed(preRoll: 1);
      await c.toggleRecord();
      c.debugEngineState(state(5));
      await c.toggleRecord();
      expect(c.recording, isFalse);
      expect(c.doc.tracks[0].clips, isEmpty);
      expect(c.notice, contains('cancelada'));
      expect(c.beat.value, 8, reason: 'o cursor volta ao ponto de gravar');
    });

    test('(1) depois de chegar ao ponto de gravar, parar guarda o que entrou', () async {
      final c = await armed(preRoll: 1);
      await c.toggleRecord();
      c.debugEngineState(state(8.5));
      e.feed(0, 225, (i) => 0.5);
      await c.toggleRecord();
      expect(c.doc.tracks[0].clips, hasLength(1));
      expect(c.notice, isNull);
    });
  });

  group('restartAudio', () {
    test('(2) reenvia o estilo do metrônomo e a modulação ao motor novo', () async {
      final c = fakeController(
        e,
        tracks: [DawTrack(id: 's', name: 'Sint', color: 1, kind: TrackKind.synth)],
      );
      c.setMetronomeOptions((o) => o.timbre = MetronomeTimbre.values[1]);
      expect(c.modAssign(0, const AutoTarget(AutoKind.instrument, param: 13)), isNull);
      c.mutate((_) {});
      expect(e.sent('metronome_style'), isNotEmpty);
      e.log!.clear();
      await c.restartAudio();
      expect(e.sent('metronome_style'), hasLength(1), reason: 'o motor novo voltou ao estilo padrão');
      expect(e.sent('mod_source'), hasLength(1));
      expect(e.sent('mod_dest'), hasLength(1));
      c.dispose();
    });
  });

  group('punch', () {
    test('(3) o loop desligado não é copiado nem pelo toggle nem pelo botão (mesmo critério)', () {
      final c = fakeController(e);
      c.beat.value = 8;
      expect(c.doc.loopOn, isFalse);
      expect(c.loopRegionUsable, isFalse);
      c.togglePunch();
      expect(c.doc.punchRegion, (8.0, 16.0), reason: 'dois compassos do cursor, não o 0 a 16 do loop apagado');
      c.setLoop(4, 12);
      expect(c.loopRegionUsable, isTrue);
      c.setPunchRegion(0, 0);
      c.togglePunch();
      c.togglePunch();
      expect(c.doc.punchRegion, (4.0, 12.0));
    });

    test('(6) sem loop, a gravação para sozinha no punch out e guarda só a região', () async {
      final c = fakeController(e);
      c.doc
        ..countIn = false
        ..punchIn = 2
        ..punchOut = 4
        ..punchOn = true;
      c.beat.value = 0;
      c.setArmed(0, true);
      await settle();
      await c.toggleRecord();
      e.feed(0, 100, (i) => 0.5);
      c.debugEngineState(state(2));
      expect(c.recording, isTrue);
      e.feed(100, 100, (i) => 0.5);
      c.debugEngineState(state(3.99));
      expect(c.recording, isTrue);
      c.debugEngineState(state(4.0));
      expect(c.recording, isFalse, reason: 'punch out: parou');
      for (var i = 0; i < 10 && c.doc.tracks[0].clips.isEmpty; i++) {
        await settle();
      }
      expect(c.doc.tracks[0].clips, isNotEmpty);
      expect(c.notice, contains('punch out'));
    });

    test('(6) com loop ligado a gravação segue (tomadas) até a pessoa parar', () async {
      final c = fakeController(e);
      c.doc
        ..countIn = false
        ..loopOn = true
        ..loopStart = 0
        ..loopEnd = 8
        ..punchIn = 2
        ..punchOut = 4
        ..punchOn = true;
      c.beat.value = 0;
      c.setArmed(0, true);
      await settle();
      await c.toggleRecord();
      c.debugEngineState(state(4.5));
      expect(c.recording, isTrue);
      await c.toggleRecord();
    });
  });

  group('tap tempo', () {
    test('(4) abaixo de 40 BPM duas batidas não aplicam; três sim', () {
      final c = fakeController(e);
      var now = 0.0;
      c.debugTapClock = () => now;
      c.tapTempo();
      now = 2.0;
      expect(c.tapTempo(), 30.0);
      expect(c.commitTap(), isNull);
      expect(c.doc.bpm, 120);
      expect(c.notice, contains('bata ao menos 3'));
      now = 10;
      c.tapTempo();
      now = 12;
      c.tapTempo();
      now = 14;
      c.tapTempo();
      expect(c.commitTap(), 30.0);
      c.dispose();
    });

    test('(4) com duas batidas a andamento normal continua valendo', () {
      final c = fakeController(e);
      var now = 0.0;
      c.debugTapClock = () => now;
      c.tapTempo();
      now = 0.5;
      c.tapTempo();
      expect(c.commitTap(), 120.0);
      c.dispose();
    });
  });

  group('metrônomo', () {
    test('(5) o volume padrão do app é o do motor (0,6)', () {
      expect(MetronomeOptions.defaultVolume, 0.6);
      expect(MetronomeOptions().isDefault, isTrue);
    });

    test('(5) volume 100% com acento 200% não passa de pico 1,0 no que vai ao motor', () {
      final o = MetronomeOptions(volume: 1, accentLevel: 2, subLevel: 2);
      expect(o.styleCall[3], 1.0);
      expect(o.styleCall[5], 1.0);
      expect(o.accentLevel, 2, reason: 'o documento guarda o que a pessoa pôs');
      final m = MetronomeOptions(volume: 0.6, accentLevel: 2);
      expect(m.styleCall[3] as double, closeTo(1 / 0.6, 1e-9));
      expect((m.styleCall[3] as double) * m.volume, lessThanOrEqualTo(1.0 + 1e-9));
      expect(MetronomeOptions(volume: 0.25, accentLevel: 2).styleCall[3], 2.0);
    });
  });

  group('exportação', () {
    Future<DawController> project() async {
      final c = fakeController(e);
      await c.importBytes(
        [
          ('voz.wav', encodeWav([Float32List(200)..fillRange(0, 200, 0.25)], 100, ExportFormat.wav32f)),
        ],
        at: 0,
        track: 0,
      );
      e.renderResult = (outputs) => [
        for (final _ in outputs) [Float32List(300)..fillRange(0, 300, 0.5)],
      ];
      return c;
    }

    test('(7) "Salvar" cancelado no WAV direto é avisado e para nos arquivos seguintes', () async {
      final c = await project();
      e.saveResult = false;
      await c.exportAudio(const ExportOptions(stems: true));
      expect(c.exportSaveCanceledName, endsWith('.wav'));
      expect(e.saved, hasLength(1));
      expect(c.error, isNull);
    });

    test('(7) salvo normalmente, não há cancelamento', () async {
      final c = await project();
      await c.exportAudio(const ExportOptions());
      expect(c.exportSaveCanceledName, isNull);
      expect(e.saved, hasLength(1));
    });
  });

  group('textos', () {
    test('(9) o selo do de-esser diz "está ouvindo a banda" e o do multibanda "está em solo"', () {
      expect(effectMonitoringTooltip('ouvindo a banda'), startsWith('Este efeito está ouvindo a banda'));
      expect(effectMonitoringTooltip('solo'), startsWith('Este efeito está em solo'));
    });
  });
}
