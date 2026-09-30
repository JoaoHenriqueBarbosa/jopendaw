import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jopendaw_app/audio/engine.dart';
import 'package:jopendaw_app/daw/controller.dart';
import 'package:jopendaw_app/daw/instruments.dart';
import 'package:jopendaw_app/daw/model.dart';
import 'package:jopendaw_app/daw/wav.dart';

import 'fake_engine.dart';

EngineState state(double beat, {bool playing = true}) => EngineState(beat, playing, Float32List(0));

/// O áudio que o motor recebeu para o sample [hash] (os ids do motor vão na ordem de registro).
DecodedAudio loadedFor(FakeEngine e, DawController c, String hash) {
  final i = c.waveforms.keys.toList().indexOf(hash);
  expect(i, greaterThanOrEqualTo(0));
  return e.loaded[i + 1]!;
}

/// Grava com a entrada: arma a faixa de áudio 0, grava, manda [frames] quadros (valor pelo índice)
/// e para. Latência zero (sem espera).
Future<void> recordAudio(DawController c, FakeEngine e, int frames, double Function(int i) value, {double Function(int i)? right}) async {
  c.setArmed(0, true);
  await settle();
  await c.toggleRecord();
  expect(c.recording, isTrue);
  e.feed(0, frames, value, right);
  await c.toggleRecord();
}

void main() {
  late FakeEngine e;
  setUp(() => e = FakeEngine());

  group('armar, monitorar e entrada', () {
    test('armar a primeira faixa de áudio abre a entrada uma vez; desarmar a última fecha', () async {
      final c = fakeController(
        e,
        tracks: [
          DawTrack(id: 'a', name: 'A', color: 0),
          DawTrack(id: 'b', name: 'B', color: 1),
        ],
      );
      c.setArmed(0, true);
      c.setArmed(1, true);
      await settle();
      expect(e.opened, [null]);
      expect(c.inputOpen, isTrue);
      expect(c.doc.tracks.map((t) => t.armed), [true, true]);
      c.setArmed(0, false);
      expect(e.stopped, 0);
      c.setArmed(1, false);
      expect(e.stopped, 1);
      expect(c.inputOpen, isFalse);
      expect(c.canUndo, isFalse, reason: 'armar não entra no desfazer');
    });

    test('entrada que cai sozinha: aviso em error, entrada fechada, medidor zerado e a faixa segue armada', () async {
      final c = fakeController(e);
      c.setArmed(0, true);
      await settle();
      e.onInputLevel!(0.5);
      expect(c.inputLevel.value, 0.5);
      e.onInputLost!('A entrada de áudio "USB" foi desconectada.');
      expect(c.inputOpen, isFalse);
      expect(c.inputLevel.value, 0);
      expect(c.error, contains('desconectada'));
      expect(c.doc.tracks[0].armed, isTrue);
      // gravar tenta abrir de novo
      await c.toggleRecord();
      expect(e.opened, [null, null]);
      expect(c.recording, isTrue);
    });

    test('permissão negada: a mensagem fica em error e a faixa desarma', () async {
      e.inputFailure = (_) => StateError('O navegador negou o acesso ao microfone.');
      final c = fakeController(e);
      c.setArmed(0, true);
      await settle();
      expect(c.error, contains('negou'));
      expect(c.doc.tracks[0].armed, isFalse);
      expect(c.inputOpen, isFalse);
    });

    test('entrada escolhida que não abre cai na padrão, com aviso', () async {
      e.inputFailure = (d) => d == 'usb' ? Exception('OverconstrainedError') : null;
      final store = MemoryStore();
      final c = fakeController(e, store: store);
      await c.setInputDevice('usb');
      c.setArmed(0, true);
      await settle();
      expect(e.opened, ['usb', null]);
      expect(c.inputOpen, isTrue);
      expect(c.inputDevice, isNull);
      expect(c.error, contains('entrada padrão'));
      expect(store.data['rec:input'], '');
    });

    test('barramento não arma; instrumento arma sem abrir a entrada', () async {
      final c = fakeController(e);
      c.addBusTrack();
      c.addInstrumentTrack(TrackKind.synth);
      c.setArmed(1, true);
      c.setArmed(2, true);
      await settle();
      expect(c.doc.tracks[1].armed, isFalse);
      expect(c.doc.tracks[2].armed, isTrue);
      expect(e.opened, isEmpty);
    });

    test('monitorar manda input_monitor pelo índice e abre a entrada; só faixa de áudio', () async {
      final c = fakeController(e);
      c.addInstrumentTrack(TrackKind.synth);
      e.log!.clear();
      c.setMonitor(0, true);
      c.setMonitor(1, true);
      await settle();
      expect(e.sent('input_monitor'), [
        ['input_monitor', 0, true],
      ]);
      expect(c.doc.tracks[1].monitor, isFalse);
      expect(c.inputOpen, isTrue);
      // reordenar: o estado é do índice do motor, então só troca onde mudou
      e.log!.clear();
      c.moveTrack(0, 1);
      expect(e.sent('input_monitor'), [
        ['input_monitor', 0, false],
        ['input_monitor', 1, true],
      ]);
      c.setMonitor(1, false);
      expect(e.sent('input_monitor').last, ['input_monitor', 1, false]);
      expect(c.inputOpen, isFalse);
    });

    test('desfazer não mexe no armar nem no monitorar', () async {
      final c = fakeController(e);
      c.addTrack();
      c.setArmed(0, true);
      c.setMonitor(1, true);
      await settle();
      c.undo();
      expect(c.doc.tracks, hasLength(1));
      expect(c.doc.tracks[0].armed, isTrue);
      c.redo();
      expect(c.doc.tracks[1].monitor, isTrue);
    });

    test('lista de entradas: a escolhida que saiu volta para a padrão', () async {
      final c = fakeController(e);
      e.devices = [('mic', 'Microfone'), ('usb', 'Interface USB')];
      await c.refreshInputDevices();
      expect(c.inputDevices, e.devices);
      // ninguém precisava da entrada: abriu para revelar os nomes e fechou
      expect(e.opened, [null]);
      expect(c.inputOpen, isFalse);
      await c.setInputDevice('usb');
      e.devices = [('mic', 'Microfone')];
      await c.refreshInputDevices();
      expect(c.inputDevice, isNull);
      expect(c.error, contains('desconectada'));
    });

    test('faixa de instrumento armada recebe o MIDI mesmo com outra selecionada', () async {
      final c = fakeController(e);
      c.addInstrumentTrack(TrackKind.synth);
      await c.enableMidiInput();
      c.selectTrack(0);
      c.setArmed(1, true);
      e.onMidi!(0x90, 60, 100);
      expect(e.sent('live_on').single.sublist(0, 3), ['live_on', 1, 60]);
    });
  });

  group('gravar áudio', () {
    test('sem faixa armada: pede para armar e não grava', () async {
      final c = fakeController(e);
      await c.toggleRecord();
      expect(c.recording, isFalse);
      expect(c.error, contains('Arme uma faixa'));
      expect(e.captures, isEmpty);
    });

    test('grava do cursor, descarta a latência e cria o clipe WAV 32f num passo de desfazer', () async {
      final store = MemoryStore();
      final c = fakeController(e, store: store);
      c.doc.countIn = false;
      // 50 ms do contexto + 100 ms da entrada + 50 ms da compensação manual = 20 quadros a 100 Hz
      e.latency = 0.05;
      e.inputLatency = 0.1;
      c.doc.recLatencyMs = 50;
      c.beat.value = 4;
      c.setArmed(0, true);
      await settle();
      await c.toggleRecord();
      expect(e.sent('seek').last, ['seek', 4.0]);
      expect(e.sent('play'), hasLength(1));
      expect(e.captures, [true]);
      expect(c.playing.value, isTrue);
      e.feed(0, 320, (i) => i / 1000, (i) => -i / 1000);
      await c.toggleRecord();
      expect(e.captures, [true, false]);
      expect(c.recording, isFalse);
      expect(c.playing.value, isFalse);
      expect(c.beat.value, 4, reason: 'o cursor volta ao começo da gravação');
      final clip = c.doc.tracks[0].clips.single;
      expect(clip.start, 4);
      expect(clip.length, closeTo(3.0, 1e-9));
      expect(clip.takes, isEmpty);
      expect(c.doc.samples[clip.sample]!.name, 'Gravação 1.wav');
      final audio = loadedFor(e, c, clip.sample);
      expect(audio.channels, hasLength(2));
      expect(audio.frames, 300);
      expect(audio.channels[0][0], closeTo(0.020, 1e-6));
      expect(audio.channels[1][299], closeTo(-0.319, 1e-6));
      final wav = decodeWav(store.data['sample:${clip.sample}'] as Uint8List);
      expect(wav.float, isTrue);
      expect(wav.bits, 32);
      expect(wav.sampleRate, 100);
      expect(wav.channels[0], audio.channels[0]);
      c.undo();
      expect(c.doc.tracks[0].clips, isEmpty);
      expect(c.doc.tracks[0].armed, isTrue);
      expect(c.canUndo, isFalse);
    });

    test('entrada mono (lados iguais ou um mudo) vira sample de um canal', () async {
      final c = fakeController(e);
      c.doc.countIn = false;
      await recordAudio(c, e, 100, (i) => 0.1, right: (i) => 0);
      final clip = c.doc.tracks[0].clips.single;
      expect(loadedFor(e, c, clip.sample).channels, hasLength(1));
    });

    test('gravar por cima substitui o clipe que estava embaixo', () async {
      final c = fakeController(e);
      c.doc.countIn = false;
      c.doc.tracks[0].clips.add(AudioClip(id: 'old', sample: 'x', start: 0, length: 4));
      c.beat.value = 4;
      await recordAudio(c, e, 100, (i) => 0.2);
      final clips = c.doc.tracks[0].clips;
      expect(clips.map((x) => (x.start, x.length)), containsAll([(0.0, 2.0), (4.0, 1.0), (6.0, 1.0)]));
    });

    test('contagem antes do cursor: metrônomo só na contagem e o compasso dela fora do áudio', () async {
      final c = fakeController(e);
      c.beat.value = 8;
      c.setArmed(0, true);
      await settle();
      e.log!.clear();
      await c.toggleRecord();
      expect(c.countingIn, isTrue);
      expect(e.sent('metronome').last, ['metronome', true, 0.6]);
      expect(e.sent('seek').last, ['seek', 4.0]);
      c.debugEngineState(state(7.2));
      expect(e.sent('metronome').last, ['metronome', true, 0.6]);
      c.debugEngineState(state(7.6));
      expect(e.sent('metronome').last, ['metronome', false, 0.6], reason: 'meio tempo antes, para não clicar no primeiro tempo');
      expect(c.countingIn, isTrue);
      c.debugEngineState(state(8.02));
      expect(c.countingIn, isFalse);
      expect(c.recording, isTrue);
      // o compasso da contagem (200 quadros) é descartado
      e.feed(0, 200, (i) => 9);
      e.feed(200, 100, (i) => (i - 199) / 1000);
      await c.toggleRecord();
      final clip = c.doc.tracks[0].clips.single;
      expect(clip.start, 8);
      final audio = loadedFor(e, c, clip.sample);
      expect(audio.frames, 100);
      expect(audio.channels[0][0], closeTo(0.001, 1e-6));
      expect(c.doc.metronome, isFalse);
    });

    test('contagem no primeiro compasso: toca numa região vazia e volta ao cursor por um loop provisório', () async {
      final c = fakeController(e);
      c.doc.loopOn = true;
      c.doc.loopStart = 8;
      c.doc.loopEnd = 16;
      c.doc.masterLanes.add(AutoLane(id: 'l', target: const AutoTarget(AutoKind.volume), points: [AutoPoint(beat: 0, value: 1), AutoPoint(beat: 4, value: 0)]));
      c.setArmed(0, true);
      await settle();
      e.log!.clear();
      await c.toggleRecord();
      const zone = 65536 * 4.0;
      expect(e.sent('loop_set').last, ['loop_set', true, 0.0, zone + 4]);
      expect(e.sent('seek').last, ['seek', zone]);
      // o fade do master lá no fim calaria o clique: a automação sai durante a contagem
      expect(e.sent('auto_lane'), isEmpty);
      c.debugEngineState(state(zone + 1));
      expect(c.beat.value, -3, reason: 'o cursor conta o compasso antes do começo da gravação');
      c.debugEngineState(state(zone + 3.6));
      expect(e.sent('auto_lane'), isNotEmpty);
      expect(e.sent('metronome').last, ['metronome', false, 0.6]);
      c.debugEngineState(state(0.05));
      expect(c.countingIn, isFalse);
      expect(e.sent('loop_set').last, ['loop_set', true, 8.0, 16.0]);
      expect(c.beat.value, 0.05);
      e.feed(0, 200, (i) => 9);
      e.feed(200, 150, (i) => 0.5);
      await c.toggleRecord();
      final clip = c.doc.tracks[0].clips.single;
      expect(clip.start, 0);
      final audio = loadedFor(e, c, clip.sample);
      expect(audio.frames, 150);
      expect(audio.channels[0].every((v) => v == 0.5), isTrue);
    });

    test('fim do loop dentro do compasso da contagem: conta fora do lugar (senão voltaria ao loop)', () async {
      final c = fakeController(e);
      c.doc
        ..loopOn = true
        ..loopStart = 0
        ..loopEnd = 4;
      c.beat.value = 6;
      c.setArmed(0, true);
      await settle();
      await c.toggleRecord();
      const zone = 65536 * 4.0;
      expect(e.sent('seek').last, ['seek', zone]);
      expect(e.sent('loop_set').last, ['loop_set', true, 6.0, zone + 4]);
      c.debugEngineState(state(6.01));
      expect(c.countingIn, isFalse);
      // depois do fim do loop o transporte segue reto: a gravação é uma passada só
      expect(e.sent('loop_set').last, ['loop_set', true, 0.0, 4.0]);
      e.feed(0, 200, (i) => 9);
      e.feed(200, 300, (i) => 0.5);
      await c.toggleRecord();
      final clip = c.doc.tracks[0].clips.single;
      expect((clip.start, clip.length, clip.takes.length), (6.0, 3.0, 0));
    });

    test('parar durante a contagem não grava nada e devolve loop e metrônomo', () async {
      final c = fakeController(e);
      c.setArmed(0, true);
      await settle();
      await c.toggleRecord();
      expect(c.countingIn, isTrue);
      e.feed(0, 100, (i) => 1);
      await c.toggleRecord();
      expect(c.recording, isFalse);
      expect(c.countingIn, isFalse);
      expect(e.captures, [true, false]);
      expect(c.doc.tracks[0].clips, isEmpty);
      expect(c.canUndo, isFalse);
      expect(e.sent('loop_set').last, ['loop_set', false, 0.0, 16.0]);
      expect(e.sent('metronome').last, ['metronome', false, 0.6]);
      expect(e.sent('stop'), isNotEmpty);
      expect(e.sent('seek').last, ['seek', 0.0]);
    });

    test('o botão de parar do transporte encerra a gravação; seek e loop ficam travados nela', () async {
      final c = fakeController(e);
      c.doc.countIn = false;
      c.beat.value = 2;
      c.setArmed(0, true);
      await settle();
      await c.toggleRecord();
      c.seek(10);
      expect(e.sent('seek').last, ['seek', 2.0]);
      c.toggleLoop();
      expect(c.doc.loopOn, isFalse);
      expect(c.error, contains('Pare a gravação'));
      e.feed(0, 100, (i) => 0.3);
      await c.stop();
      expect(c.recording, isFalse);
      expect(c.doc.tracks[0].clips.single.start, 2);
    });

    test('fechar a tela no meio da gravação desliga a captura e a entrada, sem erro', () async {
      final c = fakeController(e);
      c.doc.countIn = false;
      e.inputLatency = 0.05;
      c.setArmed(0, true);
      await settle();
      await c.toggleRecord();
      e.feed(0, 100, (i) => 0.1);
      final finishing = c.toggleRecord();
      c.dispose();
      await finishing;
      expect(e.captures, [true, false]);
      expect(e.stopped, 1);
      expect(e.onRecord, isNull);
      expect(e.onCaptureEnd, isNull);
    });

    test('sem a entrada mandar nada: avisa em vez de criar clipe vazio', () async {
      final c = fakeController(e);
      c.doc.countIn = false;
      await recordAudio(c, e, 0, (i) => 0);
      expect(c.doc.tracks[0].clips, isEmpty);
      expect(c.error, contains('não mandou áudio'));
    });
  });

  group('tomadas em loop', () {
    test('gravando com o transporte andando, o clipe começa na batida do primeiro quadro capturado', () async {
      final c = fakeController(e);
      c.doc.countIn = true; // tocando não conta, mesmo ligada
      c.playing.value = true;
      c.beat.value = 3.0; // a tela estava um bloco atrás
      c.setArmed(0, true);
      await settle();
      await c.toggleRecord();
      e.recordBeat = 3.125;
      e.feed(0, 200, (i) => 0.5);
      await c.toggleRecord();
      expect(c.doc.tracks[0].clips.single.start, 3.125);
    });

    Future<DawController> loopRecording(double start, double loopStart, double loopEnd, int frames) async {
      final c = fakeController(e);
      c.doc
        ..countIn = false
        ..loopOn = true
        ..loopStart = loopStart
        ..loopEnd = loopEnd;
      c.beat.value = start;
      // o valor de cada quadro é o índice: dá para ver de onde veio cada pedaço
      await recordAudio(c, e, frames, (i) => i.toDouble());
      return c;
    }

    test('cada passada vira uma tomada do clipe que cobre o loop; a ativa é a última completa', () async {
      final c = await loopRecording(0, 0, 4, 500);
      final clip = c.doc.tracks[0].clips.single;
      expect(clip.start, 0);
      expect(clip.length, closeTo(2.0, 1e-9));
      expect(clip.takes, hasLength(3));
      // a terceira passada parou no meio: fica guardada, mas toca a segunda
      expect(clip.sample, clip.takes[1]);
      expect(c.doc.samples[clip.takes[1]]!.name, 'Gravação 1 - tomada 2.wav');
      final firsts = [for (final h in clip.takes) loadedFor(e, c, h).channels[0]];
      expect(firsts.map((a) => (a.first, a.length)), [(0.0, 200), (200.0, 200), (400.0, 100)]);
    });

    test('a última passada com menos de uma batida (o passo além de quem parou) fica de fora', () async {
      final c = await loopRecording(0, 0, 4, 420);
      expect(c.doc.tracks[0].clips.single.takes, hasLength(2));
    });

    test('começando no meio do loop, a primeira tomada ganha silêncio até o cursor', () async {
      final c = await loopRecording(2, 0, 4, 350);
      final clip = c.doc.tracks[0].clips.single;
      expect(clip.takes, hasLength(3));
      final first = loadedFor(e, c, clip.takes[0]).channels[0];
      expect(first.length, 200);
      expect(first[99], 0);
      expect(first[100], 0);
      expect(first[101], 1);
      final second = loadedFor(e, c, clip.takes[1]).channels[0];
      expect(second.first, 100);
    });

    test('começando antes do loop, o trecho de antes fica num clipe comum', () async {
      final c = await loopRecording(0, 4, 8, 600);
      final clips = c.doc.tracks[0].clips..sort((a, b) => a.start.compareTo(b.start));
      expect(clips, hasLength(2));
      expect((clips[0].start, clips[0].length, clips[0].takes.length), (0.0, 2.0, 0));
      expect((clips[1].start, clips[1].takes.length), (4.0, 2));
      final takes = [for (final h in clips[1].takes) loadedFor(e, c, h).channels[0].first];
      expect(takes, [200, 400]);
    });

    test('trocar a tomada ativa é desfazível; hash que não é tomada do clipe é ignorado', () async {
      final c = await loopRecording(0, 0, 4, 500);
      final clip = c.doc.tracks[0].clips.single;
      c.switchTake(clip.id, clip.takes.first);
      expect(c.doc.tracks[0].clips.single.sample, clip.takes.first);
      c.switchTake(clip.id, 'outro');
      expect(c.doc.tracks[0].clips.single.sample, clip.takes.first);
      c.undo();
      expect(c.doc.tracks[0].clips.single.sample, clip.takes[1]);
    });

    test('começando no meio do loop, toca a primeira passada completa', () async {
      final c = await loopRecording(2, 0, 4, 350);
      final clip = c.doc.tracks[0].clips.single;
      // a primeira começou no meio (com silêncio antes) e a terceira parou no meio: a segunda é a
      // única completa
      expect(clip.sample, clip.takes[1]);
    });

    test('passadas: divisão no quadro exato da volta do motor, sem deriva', () {
      // 128 quadros por batida; o loop tem 128,25 quadros: a volta anda um quadro a mais a cada
      // quatro passadas, e a enésima cai sempre no teto de n × 128,25
      final passes = recordingPasses(start: 0, frames: 2000, bpm: 120, rate: 128, loopOn: true, loopStart: 0, loopEnd: 2 + 1 / 256);
      expect(passes, hasLength(16));
      for (var n = 0; n < passes.length; n++) {
        expect(passes[n].frame, (n * 128.25).ceil());
      }
      // começando depois do fim do loop o transporte segue reto: uma passada só
      expect(recordingPasses(start: 5, frames: 1000, bpm: 120, rate: 100, loopOn: true, loopStart: 0, loopEnd: 4), hasLength(1));
      expect(recordingPasses(start: 0, frames: 1000, bpm: 120, rate: 100), hasLength(1));
    });
  });

  group('latência do motor na gravação', () {
    test('o áudio descarta também a latência do motor (PDC), somada à do aparelho e à manual', () async {
      final c = fakeController(e);
      c.doc.countIn = false;
      // 50 ms do contexto + 30 ms do motor + 100 ms da entrada + 50 ms manuais = 23 quadros a 100 Hz
      e.latency = 0.05;
      e.engineLatency = 0.03;
      e.inputLatency = 0.1;
      c.doc.recLatencyMs = 50;
      c.beat.value = 4;
      c.setArmed(0, true);
      await settle();
      expect(c.monitorLatency, closeTo(0.18, 1e-9), reason: 'ida e volta monitorada: entrada, motor e saída');
      await c.toggleRecord();
      e.feed(0, 320, (i) => i / 1000);
      await c.toggleRecord();
      final audio = loadedFor(e, c, c.doc.tracks[0].clips.single.sample);
      expect(audio.frames, 320 - 23);
      expect(audio.channels[0][0], closeTo(0.023, 1e-6));
    });

    test('as notas voltam para antes da latência do motor e do aparelho, sem passar do começo', () async {
      final c = fakeController(e);
      c.addInstrumentTrack(TrackKind.synth);
      c.doc.countIn = false;
      // 0,1 s do motor + 0,05 s do aparelho = 0,15 s = 0,3 batida a 120 bpm
      e.latency = 0.05;
      e.engineLatency = 0.1;
      c.setArmed(1, true);
      c.beat.value = 4;
      await c.toggleRecord();
      e.notes = Float32List.fromList([1, 60, 5, 6, 0.8, 1, 62, 4, 4.5, 0.8]);
      c.debugRecordingElapsed(const Duration(seconds: 2));
      await c.toggleRecord();
      final clip = c.doc.tracks[1].midi.single;
      final notes = [for (final n in clip.notes) (n.pitch, double.parse(n.start.toStringAsFixed(6)), double.parse(n.length.toStringAsFixed(6)))]
        ..sort((a, b) => a.$1 - b.$1);
      expect(notes, [(60, 0.7, 1.0), (62, 0.0, 0.2)]);
    });
  });

  group('gravar notas', () {
    Future<DawController> recordNotes(
      List<double> notes, {
      double start = 4,
      bool countIn = false,
      Duration elapsed = const Duration(seconds: 2),
      void Function(DawController c)? setup,
    }) async {
      final c = fakeController(e);
      c.addInstrumentTrack(TrackKind.synth);
      c.doc.countIn = countIn;
      setup?.call(c);
      c.setArmed(1, true);
      c.beat.value = start;
      await c.toggleRecord();
      if (countIn) c.debugEngineState(state(start + 0.01));
      e.notes = Float32List.fromList(notes);
      c.debugRecordingElapsed(elapsed);
      await c.toggleRecord();
      return c;
    }

    test('viram um clipe novo cobrindo os compassos gravados', () async {
      final c = await recordNotes([1, 60, 4.5, 5, 0.8, 1, 64, 6, 7.5, 0.5, 0, 67, 5, 6, 1]);
      final clip = c.doc.tracks[1].midi.single;
      expect((clip.start, clip.length, clip.name), (4.0, 4.0, 'Sintetizador 1'));
      expect([for (final n in clip.notes) (n.pitch, n.start, n.length, (n.velocity * 100).round())], [(60, 0.5, 0.5, 80), (64, 2.0, 1.5, 50)]);
      // a nota da faixa que não estava armada não entra
      expect(c.doc.tracks[0].clips, isEmpty);
      c.undo();
      expect(c.doc.tracks[1].midi, isEmpty);
    });

    test('overdub: vão para o clipe sob o cursor, que estica em compassos se passarem dele', () async {
      late MidiClip existing;
      final c = await recordNotes(
        [1, 62, 5.5, 6, 0.7, 1, 65, 9, 9.5, 0.7],
        start: 5,
        setup: (c) {
          existing = MidiClip(id: 'm', start: 4, length: 4, notes: [MidiNote(pitch: 60, start: 0, length: 1)]);
          c.doc.tracks[1].midi.add(existing);
        },
      );
      final clip = c.doc.tracks[1].midi.single;
      expect(clip.id, 'm');
      expect((clip.start, clip.length), (4.0, 8.0));
      expect([for (final n in clip.notes) (n.pitch, n.start)], [(60, 0.0), (62, 1.5), (65, 5.0)]);
    });

    test('em loop as passadas se somam, e a nota segurada na volta vira duas', () async {
      final c = await recordNotes(
        [1, 60, 1, 1.5, 0.8, 1, 62, 1, 1.5, 0.8, 1, 64, 3.5, 0.5, 0.8],
        start: 0,
        elapsed: const Duration(seconds: 5),
        setup: (c) => c.doc
          ..loopOn = true
          ..loopStart = 0
          ..loopEnd = 4,
      );
      final clip = c.doc.tracks[1].midi.single;
      expect((clip.start, clip.length), (0.0, 4.0));
      final notes = [for (final n in clip.notes) (n.pitch, n.start, n.length)]..sort((a, b) => a.$2 != b.$2 ? a.$2.compareTo(b.$2) : a.$1 - b.$1);
      expect(notes, [(64, 0.0, 0.5), (60, 1.0, 0.5), (62, 1.0, 0.5), (64, 3.5, 0.5)]);
    });

    test('contagem: fica de fora, menos a nota adiantada e a que ainda soava no primeiro tempo', () async {
      final c = await recordNotes([1, 60, 1, 2, 0.8, 1, 62, 3.9, 4.2, 0.8, 1, 64, 3, 5, 0.8, 1, 65, 4.5, 4.6, 0.8], countIn: true);
      final clip = c.doc.tracks[1].midi.single;
      final notes = [for (final n in clip.notes) (n.pitch, n.start, double.parse(n.length.toStringAsFixed(6)))];
      expect(notes, [(62, 0.0, 0.3), (64, 0.0, 1.0), (65, 0.5, 0.1)]);
    });

    test('a nota que o motor parte na volta do loop conta como volta: a metade do começo do loop fica', () async {
      // contagem de 2 a 6, grava de 6 a 8 e volta a 4: o motor termina a nota segurada em 8 e
      // recomeça em 4 (sem o fim antes do começo); pelo relógio ainda nem teria dado a volta
      final c = await recordNotes(
        [1, 64, 7.5, 8, 0.8, 1, 64, 4, 4.5, 0.8],
        start: 6,
        countIn: true,
        elapsed: const Duration(milliseconds: 500),
        setup: (c) => c.doc
          ..loopOn = true
          ..loopStart = 4
          ..loopEnd = 8,
      );
      final clip = c.doc.tracks[1].midi.single;
      expect((clip.start, clip.length), (4.0, 4.0));
      expect([for (final n in clip.notes) (n.pitch, n.start, n.length)]..sort((a, b) => a.$2.compareTo(b.$2)), [(64, 0.0, 0.5), (64, 3.5, 0.5)]);
    });

    test('contagem fora do lugar: a nota segurada na volta dela (que o motor parte) volta a ser uma só', () async {
      const zone = 65536 * 4.0;
      // apertada 0,1 batida antes do fim da contagem, solta 1 batida depois do começo
      final c = await recordNotes([1, 60, zone + 3.9, zone + 4, 0.8, 1, 60, 0, 1, 0.8], start: 0, countIn: true);
      final note = c.doc.tracks[1].midi.single.notes.single;
      expect((note.pitch, note.start), (60, 0.0));
      // o float de 32 bits do motor lá longe anda de 1/32 em 1/32 de batida
      expect(note.length, closeTo(1.1, 0.04));
    });

    test('nenhuma nota tocada: avisa e não cria clipe', () async {
      final c = await recordNotes([]);
      expect(c.doc.tracks[1].midi, isEmpty);
      expect(c.error, contains('Nenhuma nota'));
    });

    test('áudio e notas juntos: um passo só do desfazer', () async {
      final c = fakeController(e);
      c.addInstrumentTrack(TrackKind.synth);
      c.doc.countIn = false;
      c.setArmed(0, true);
      c.setArmed(1, true);
      await settle();
      await c.toggleRecord();
      e.feed(0, 100, (i) => 0.1);
      e.notes = Float32List.fromList([1, 60, 0, 1, 0.8]);
      await c.toggleRecord();
      expect(c.doc.tracks[0].clips, hasLength(1));
      expect(c.doc.tracks[1].midi, hasLength(1));
      c.undo();
      expect(c.doc.tracks[0].clips, isEmpty);
      expect(c.doc.tracks[1].midi, isEmpty);
    });
  });
}
