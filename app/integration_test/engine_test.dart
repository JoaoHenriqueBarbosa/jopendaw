/// O motor nativo de verdade, no emulador ou no aparelho Android: sobe a saída, toca um projeto
/// pelo controlador e confere pelos picos que o som sai; decodifica, renderiza fora de tempo real,
/// registra notas ao vivo e guarda arquivos como o app faz. Nada aqui usa o motor de mentira dos
/// testes de unidade.
///
///     ~/Library/Android/sdk/emulator/emulator -avd Galaxy_S24_Plus_API36 &   # arm64, API 36
///     cd app && flutter test integration_test/engine_test.dart -d emulator-5554
///
/// Os .so do motor precisam estar em android/app/src/main/jniLibs/ (engine/build-android.sh);
/// sem eles o primeiro teste falha dizendo isso, em vez de o resto falhar sem explicação.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:jopendaw_app/audio/engine.dart';
import 'package:jopendaw_app/daw/controller.dart';
import 'package:jopendaw_app/daw/export_options.dart';
import 'package:jopendaw_app/daw/instruments.dart';
import 'package:jopendaw_app/daw/model.dart';
import 'package:jopendaw_app/daw/wav.dart';
import 'package:jopendaw_app/models/project.dart';

const _wavRate = 44100;
const _wavSeconds = 0.25;
const _sineAmp = 0.5;

/// WAV estéreo de 16 bits a 44,1 kHz: um lá (440 Hz) na esquerda e silêncio na direita, para ver
/// que os canais não trocam de lado nem se misturam na decodificação.
Uint8List _stereoWav() {
  final n = (_wavRate * _wavSeconds).round();
  final left = Float32List(n), right = Float32List(n);
  for (var i = 0; i < n; i++) {
    left[i] = _sineAmp * math.sin(2 * math.pi * 440 * i / _wavRate);
  }
  return encodeWav([left, right], _wavRate, ExportFormat.wav16, dither: false);
}

/// WAV mono de 24 bits a 48 kHz, meio segundo de um mi (330 Hz).
Uint8List _monoWav() {
  const rate = 48000;
  final n = rate ~/ 2;
  final c = Float32List(n);
  for (var i = 0; i < n; i++) {
    c[i] = 0.3 * math.sin(2 * math.pi * 330 * i / rate);
  }
  return encodeWav([c], rate, ExportFormat.wav24, dither: false);
}

/// Maior valor absoluto de [c] entre os quadros [from] e [to] (fim exclusivo).
double _peak(Float32List c, [int from = 0, int? to]) {
  var p = 0.0;
  final end = math.min(to ?? c.length, c.length);
  for (var i = math.max(0, from); i < end; i++) {
    final v = c[i].abs();
    if (v > p) p = v;
  }
  return p;
}

bool _allFinite(Float32List c) => c.every((v) => v.isFinite);

Future<void> _wait(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final engine = AudioEngine.instance;
  final store = LocalStore.instance;
  final project = Project.fromJson({
    'id': 'teste-integracao-${DateTime.now().microsecondsSinceEpoch}',
    'name': 'Teste de integração',
    'bpm': 120,
    'beats_per_bar': 4,
    'beat_unit': 4,
    'sample_rate': 48000,
    'created_at': '2026-01-01T00:00:00Z',
    'updated_at': '2026-01-01T00:00:00Z',
  });

  var rate = 0.0;
  late DawController c;
  late int synth;
  String? sampleHash;

  setUpAll(() async {
    expect(
      engine.supported,
      isTrue,
      reason: 'o motor nativo não está neste build: confira os .so em android/app/src/main/jniLibs/ (engine/build-android.sh) e o engine_io.dart',
    );
    rate = await engine.start();
  });

  tearDownAll(() async {
    // o documento é salvo no dispose do controlador; o teste não deixa rastro no guardado do app
    await store.delete('doc:${project.id}');
    if (sampleHash != null) await store.delete('sample:$sampleHash');
  });

  test('a saída sobe na taxa nativa do aparelho, com latência plausível', () async {
    expect(rate, inInclusiveRange(8000, 192000));
    // de novo não reabre nada: a mesma taxa (o controlador chama start a cada projeto aberto)
    expect(await engine.start(), rate);
    final latency = engine.latency;
    expect(latency.isFinite, isTrue);
    expect(latency, inInclusiveRange(0, 1));
  });

  test('o controlador abre um projeto e toca um sintetizador com notas e um áudio; o master mede picos', () async {
    c = DawController(project);
    await c.open();
    expect(c.error, isNull);
    expect(c.ready, isTrue);
    expect(c.engineRate, rate);

    // o projeto novo começa com uma faixa de áudio (índice 0); o WAV entra nela, no começo
    final wav = _stereoWav();
    sampleHash = await engine.sha256Hex(wav);
    await c.importBytes([('la.wav', wav)], at: 0, track: 0);
    expect(c.error, isNull);
    expect(c.doc.tracks[0].clips, hasLength(1));

    c.addInstrumentTrack(TrackKind.synth);
    synth = c.doc.tracks.length - 1;
    final clip = c.createMidiClip(synth, 0, length: 4);
    c.edit((d) {
      clip.notes.addAll([
        MidiNote(pitch: 60, start: 0, length: 1),
        MidiNote(pitch: 64, start: 0, length: 1),
        MidiNote(pitch: 67, start: 1, length: 1),
        MidiNote(pitch: 72, start: 2, length: 1.5),
      ]);
    });

    // os estados continuam indo ao controlador; o teste só olha junto
    final forward = engine.onState;
    expect(forward, isNotNull, reason: 'o open liga o controlador ao estado do motor');
    var states = 0;
    var sawPlaying = false;
    var lastBeat = 0.0;
    var master = 0.0, audio = 0.0, synthPeak = 0.0;
    engine.onState = (s) {
      forward?.call(s);
      states++;
      if (s.playing) sawPlaying = true;
      lastBeat = s.beat;
      final p = s.peaks;
      // picos (esq, dir) de cada faixa e, por último, do master
      if (p.length >= 2 * (c.doc.tracks.length + 1)) {
        audio = math.max(audio, math.max(p[0], p[1]));
        synthPeak = math.max(synthPeak, math.max(p[2 * synth], p[2 * synth + 1]));
        master = math.max(master, math.max(p[p.length - 2], p[p.length - 1]));
      }
    };
    try {
      await c.togglePlay();
      await _wait(1200);
      await c.togglePlay();
      await _wait(250);
    } finally {
      engine.onState = forward;
    }

    expect(states, greaterThan(20), reason: 'o estado chega ~60 vezes por segundo');
    expect(sawPlaying, isTrue);
    expect(c.playing.value, isFalse);
    // 1,2 s a 120 bpm são 2,4 batidas; a folga cobre a subida do stream no emulador
    expect(lastBeat, greaterThan(1.0));
    expect(audio, greaterThan(0.05), reason: 'o clipe de áudio (lá a −6 dB) soou na faixa 0');
    expect(synthPeak, greaterThan(0.01), reason: 'o sintetizador soou');
    expect(master, greaterThan(0.01), reason: 'o master soou');
  });

  test('captura: as notas tocadas ao vivo voltam no fim, sem precisar de microfone', () async {
    final end = Completer<List<RecordedNote>>();
    engine.onCaptureEnd = (notes) {
      if (!end.isCompleted) end.complete(notes);
    };
    try {
      c.seek(0);
      await c.togglePlay();
      await _wait(300);
      engine.setCapture(true);
      await _wait(200);
      c.noteOn(69, track: synth, velocity: 0.9);
      await _wait(400);
      c.noteOff(69, track: synth);
      await _wait(200);
      engine.setCapture(false);
      final notes = await end.future.timeout(const Duration(seconds: 3));
      final n = notes.where((n) => n.pitch == 69).toList();
      expect(n, hasLength(1), reason: 'a nota tocada ao vivo: $notes');
      expect(n.single.track, synth);
      expect(n.single.velocity, closeTo(0.9, 0.02));
      expect(n.single.start, greaterThan(0));
      // 400 ms a 120 bpm são 0,8 batida
      expect(n.single.end - n.single.start, closeTo(0.8, 0.3));
    } finally {
      engine.onCaptureEnd = null;
      if (c.playing.value) await c.togglePlay();
    }
  });

  test('decodifica um WAV estéreo gerado em memória, sem trocar os canais', () async {
    final audio = await engine.decode(_stereoWav());
    expect(audio.channels, hasLength(2));
    expect(audio.rate, greaterThan(0));
    expect(audio.duration, closeTo(_wavSeconds, 0.005));
    expect(audio.channels[0].length, audio.channels[1].length);
    // com ou sem conversão de taxa, o pico do seno fica perto do original
    expect(_peak(audio.channels[0]), closeTo(_sineAmp, 0.03));
    expect(_peak(audio.channels[1]), lessThan(0.01));
  });

  test('decodifica um WAV mono de 24 bits', () async {
    final audio = await engine.decode(_monoWav());
    expect(audio.channels.length, inInclusiveRange(1, 2));
    expect(audio.duration, closeTo(0.5, 0.005));
    expect(_peak(audio.channels.first), closeTo(0.3, 0.02));
    if (audio.channels.length == 2) expect(_peak(audio.channels[1]), closeTo(0.3, 0.02));
  });

  test('arquivo que não é áudio falha com erro, e o motor segue decodificando', () async {
    final junk = Uint8List.fromList(List.generate(8192, (i) => (i * 37 + 11) & 0xff));
    await expectLater(engine.decode(junk), throwsA(anything));
    await expectLater(engine.decode(Uint8List(0)), throwsA(anything));
    // cabeçalho de WAV cortado no meio
    await expectLater(engine.decode(Uint8List.sublistView(_stereoWav(), 0, 30)), throwsA(anything));
    final ok = await engine.decode(_stereoWav());
    expect(ok.duration, closeTo(_wavSeconds, 0.005));
  });

  test('renderOffline curto: master, faixa de áudio e sintetizador com amostras não nulas', () async {
    final sine = await engine.decode(_stereoWav());
    final calls = <List<Object>>[
      ['tempo', 120.0, 4],
      ['tracks', 2],
      ['master', 1.0, 0.0],
      ['loop_set', false, 0.0, 0.0],
      ['metronome', false, 0.5],
      ['clips_clear'],
      ['track', 0, 1.0, 0.0, false, false],
      ['clip_add', 0, 1, 0.0, 0.0, sine.duration, 1.0, 0.0, 0.0],
      ['track', 1, 1.0, 0.0, false, false],
      ['track_kind', 0, TrackKind.audio.index],
      ['track_kind', 1, TrackKind.synth.index],
      for (final e in defaultParams(TrackKind.synth).entries) ['param', 1, e.key, e.value],
      ['notes_clear'],
      ['note_add', 1, 0.0, 1.0, 60, 0.8],
      ['note_add', 1, 1.0, 1.0, 67, 0.8],
    ];
    final progress = <double>[];
    final out = await engine.renderOffline(
      calls: calls,
      samples: {1: sine},
      fromBeat: 0,
      toBeat: 2,
      tailSeconds: 0.25,
      outputs: const [-1, 0, 1],
      rate: rate,
      onProgress: progress.add,
    );
    expect(out, hasLength(3));
    // 2 batidas a 120 bpm (1 s) mais a cauda
    final frames = (rate * 1.0).round() + (rate * 0.25).round();
    for (final o in out) {
      expect(o, hasLength(2));
      for (final ch in o) {
        expect(ch.length, closeTo(frames, 2));
        expect(_allFinite(ch), isTrue);
      }
    }
    final second = rate.round();
    final master = out[0], audio = out[1], synthOut = out[2];
    expect(math.max(_peak(master[0], 0, second), _peak(master[1], 0, second)), greaterThan(0.01));
    // o clipe dura 0,25 s: soa no começo e some depois
    expect(_peak(audio[0], 0, (rate * 0.2).round()), greaterThan(0.1));
    expect(_peak(audio[0], (rate * 0.35).round(), second), lessThan(1e-3));
    expect(_peak(audio[1], 0, second), lessThan(0.01), reason: 'o lado direito do WAV é silêncio');
    expect(math.max(_peak(synthOut[0], 0, second), _peak(synthOut[1], 0, second)), greaterThan(0.01));
    for (final p in progress) {
      expect(p, inInclusiveRange(0, 1));
    }
  });

  test('cancelRender interrompe o render em andamento com RenderCanceled', () async {
    final job = engine.renderOffline(
      calls: [
        ['tempo', 120.0, 4],
        ['tracks', 1],
        ['track_kind', 0, TrackKind.synth.index],
        ['note_add', 0, 0.0, 100.0, 60, 0.8],
      ],
      samples: const {},
      fromBeat: 0,
      toBeat: 120,
      tailSeconds: 0,
      outputs: const [-1],
      rate: rate,
    );
    // um minuto de áudio leva bem mais que isso para renderizar, mesmo num aparelho rápido; a
    // folga deixa o render começar de fato antes do cancelamento
    await _wait(50);
    engine.cancelRender();
    await expectLater(job, throwsA(isA<RenderCanceled>()));
  });

  test('o guardado local em arquivos devolve texto e bytes e apaga', () async {
    const text = 'teste-integracao:texto';
    const bytesKey = 'teste-integracao:bytes/com barra';
    try {
      await store.put(text, 'olá, ação: ♪');
      expect(await store.get(text), 'olá, ação: ♪');
      final bytes = Uint8List.fromList(List.generate(70000, (i) => (i * 7) & 0xff));
      await store.put(bytesKey, bytes);
      final back = await store.get(bytesKey);
      expect(back, isA<Uint8List>());
      expect(back, bytes);
      // regravar troca o valor, inclusive de tipo
      await store.put(text, Uint8List.fromList([1, 2, 3]));
      expect(await store.get(text), Uint8List.fromList([1, 2, 3]));
      await store.delete(text);
      expect(await store.get(text), isNull);
      // apagar o que não existe não é erro
      await store.delete('teste-integracao:nunca-existiu');
    } finally {
      await store.delete(text);
      await store.delete(bytesKey);
    }
  });

  test('fechar o projeto solta o motor e salva o documento', () async {
    c.dispose();
    expect(engine.onState, isNull, reason: 'o controlador fechado não recebe mais estado');
    // o dispose salva sem esperar a escrita terminar
    Object? saved;
    for (var i = 0; i < 20 && saved is! String; i++) {
      saved = await store.get('doc:${project.id}');
      if (saved is! String) await _wait(100);
    }
    expect(saved, isA<String>());
    expect(saved as String, contains('Sintetizador'));
  });
}
