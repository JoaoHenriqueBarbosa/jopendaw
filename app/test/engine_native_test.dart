// O FfiEngine contra um motor nativo de mentira (test/native/fake_engine.c), compilado aqui com o
// cc do sistema: confere a fronteira do dart:ffi no computador (ponteiros, cópias, memória solta,
// isolates do render e da decodificação, polling do estado, da captura e da entrada). Sem
// compilador, os testes são pulados.
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jopendaw_app/audio/engine_ffi.dart';
import 'package:jopendaw_app/audio/engine_types.dart';
import 'package:permission_handler/permission_handler.dart';

class Events implements EngineEvents {
  final states = <EngineState>[];
  final levels = <double>[];
  final lost = <String>[];
  final failures = <String>[];
  final blocks = <(double, Float32List, Float32List)>[];
  final ends = <List<RecordedNote>>[];

  /// A ordem em que blocos e fim chegaram.
  final order = <String>[];

  @override
  void Function(EngineState state)? onState;

  @override
  void Function(int status, int data1, int data2)? onMidi;

  @override
  void Function(List<String> inputs)? onMidiInputs;

  @override
  void Function(Float32List left, Float32List right)? onRecord;

  @override
  void Function(double peak)? onInputLevel;

  @override
  void Function(List<RecordedNote> notes)? onCaptureEnd;

  @override
  void Function(String message)? onInputLost;

  @override
  void Function(String message)? onEngineFailed;

  @override
  double recordBeat = 0;

  Events() {
    onState = states.add;
    onInputLevel = levels.add;
    onInputLost = lost.add;
    onEngineFailed = failures.add;
    onRecord = (l, r) {
      blocks.add((recordBeat, l, r));
      order.add('bloco');
    };
    onCaptureEnd = (notes) {
      ends.add(notes);
      order.add('fim');
    };
  }
}

/// Compila o motor de mentira; null sem compilador.
String? compileFake() {
  try {
    final dir = Directory.systemTemp.createTempSync('jopendaw_fake');
    final ext = Platform.isMacOS
        ? 'dylib'
        : Platform.isWindows
        ? 'dll'
        : 'so';
    final out = '${dir.path}/libfake_engine.$ext';
    final r = Process.runSync('cc', ['-shared', '-fPIC', '-O1', '-o', out, 'test/native/fake_engine.c']);
    if (r.exitCode != 0) {
      // ignore: avoid_print
      print('motor de mentira não compilou: ${r.stderr}');
      return null;
    }
    return out;
  } on ProcessException {
    return null;
  }
}

/// Espera [ok] ficar verdadeiro (o polling é a ~60 Hz), no máximo [timeout].
Future<void> until(bool Function() ok, {Duration timeout = const Duration(seconds: 3)}) async {
  final clock = Stopwatch()..start();
  while (!ok()) {
    if (clock.elapsed > timeout) fail('não aconteceu em $timeout');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final path = compileFake();
  final skip = path == null ? 'sem compilador C para o motor de mentira' : false;
  late final DynamicLibrary fake = DynamicLibrary.open(path!);
  int live() => fake.lookupFunction<Int32 Function(), int Function()>('fake_live')();
  String lastCalls() {
    final read = fake.lookupFunction<IntPtr Function(Pointer<Uint8>, IntPtr), int Function(Pointer<Uint8>, int)>('fake_last_calls');
    final len = read(nullptr, 0);
    final p = malloc<Uint8>(len + 1);
    try {
      read(p, len);
      return utf8.decode(p.asTypedList(len));
    } finally {
      malloc.free(p);
    }
  }

  int callsCount() => fake.lookupFunction<Int32 Function(), int Function()>('fake_calls_count')();
  void setLevel(double v) => fake.lookupFunction<Void Function(Float), void Function(double)>('fake_set_level')(v);
  void setSlow(int us) => fake.lookupFunction<Void Function(Int32), void Function(int)>('fake_set_slow')(us);

  late Events events;
  late FfiEngine engine;
  var permission = PermissionStatus.granted;

  setUp(() {
    events = Events();
    permission = PermissionStatus.granted;
    engine = FfiEngine(events, library: path ?? 'sem-motor-de-mentira', microphonePermission: () async => permission);
  });

  tearDown(() {
    engine.stop();
    if (path == null) return;
    setLevel(0.25);
    setSlow(0);
  });

  test('biblioteca que não existe: UnsupportedError com a mensagem para o usuário', () async {
    final e = FfiEngine(Events(), library: '/nao/existe/libjopendaw_engine.so');
    await expectLater(e.start(), throwsA(isA<UnsupportedError>().having((x) => x.message, 'mensagem', contains('não carregou'))));
    // antes de ligar, as chamadas e os áudios não vão a lugar nenhum (nem quebram)
    e.calls([
      ['play'],
    ]);
    e.loadSample(1, DecodedAudio([Float32List(4)], 48000));
    expect(e.latency, 0);
  });

  test('start devolve a taxa, o estado chega por polling e a latência vem do motor', () async {
    expect(await engine.start(), 48000);
    expect(await engine.start(), 48000, reason: 'ligado, só devolve a taxa');
    expect(engine.latency, 0.02);
    await until(() => events.states.isNotEmpty);
    final s = events.states.first;
    expect((s.beat, s.playing, s.fxMeter), (2.5, true, -3));
    expect(s.peaks, [0.5, 1, 1.5, 2]);
    expect(s.spectrum, isNull, reason: 'sem ninguém observando, sem espectro');
  }, skip: skip);

  test('os retornos i32 vêm com o sinal certo (um −1 não vira 4294967295) e o estado é f64', () {
    final lib = EngineLib.open(path!);
    fake.lookupFunction<Void Function(Int32), void Function(int)>('fake_set_notes_pending')(1);
    final out = calloc<Float>(64);
    try {
      expect(lib.recNotes(out, 64), -1, reason: 'jd_rec_notes: o fim da captura ainda não chegou');
    } finally {
      fake.lookupFunction<Void Function(Int32), void Function(int)>('fake_set_notes_pending')(0);
      calloc.free(out);
    }
    final state = calloc<Double>(16);
    try {
      expect(lib.state(state, 16), 8);
      expect(state.asTypedList(8).sublist(0, 4), [2.5, 1, -3, 4]);
    } finally {
      calloc.free(state);
    }
  }, skip: skip);

  test('a thread de áudio que cai (ERR_PANIC) avisa uma vez; reiniciar traz o motor de volta', () async {
    void setStateError(int code) => fake.lookupFunction<Void Function(Int32), void Function(int)>('fake_set_state_error')(code);
    await engine.start();
    await until(() => events.states.isNotEmpty);
    setStateError(-5);
    try {
      await until(() => events.failures.isNotEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(events.failures, hasLength(1), reason: 'avisa uma vez, não a cada leitura');
      setStateError(0);
      events.states.clear();
      expect(await engine.restart(), 48000);
      await until(() => events.states.isNotEmpty);
      // e cai de novo: avisa de novo
      setStateError(-5);
      await until(() => events.failures.length == 2);
    } finally {
      setStateError(0);
    }
  }, skip: skip);

  test('a medida de loudness chega por polling, só quando muda', () async {
    final got = <LoudnessReading>[];
    engine.onLoudness = got.add;
    await engine.start();
    await until(() => got.isNotEmpty);
    expect(got.first, const LoudnessReading(momentary: -20, shortTerm: -21, integrated: -22, truePeak: -1.5, range: 6.5));
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(got, hasLength(1), reason: 'o valor não mudou: nada de repetir');
  }, skip: skip);

  test('com o analisador ligado o espectro vem junto; desligado, some', () async {
    await engine.start();
    engine.calls([
      ['watch_analyzer', 1],
    ]);
    await until(() => events.states.isNotEmpty && events.states.last.spectrum != null);
    expect(events.states.last.spectrum!.length, 1024);
    expect(events.states.last.spectrum!.first, -60);
    engine.calls([
      ['watch_analyzer', -2],
    ]);
    events.states.clear();
    await until(() => events.states.length > 3);
    expect(events.states.every((s) => s.spectrum == null), isTrue);
  }, skip: skip);

  test('chamadas vão em JSON como o worklet recebe; antes de ligar, nada vai', () async {
    final before = callsCount();
    engine.calls([
      ['play'],
    ]);
    expect(callsCount(), before, reason: 'motor parado');
    await engine.start();
    engine.calls([
      ['tempo', 128.5, 4],
      ['track', 0, 1.0, 0, false, true],
      ['seek', double.nan],
    ]);
    expect(lastCalls(), '[["tempo",128.5,4],["track",0,1.0,0,0,1]]');
    // um lote grande reaproveita (e aumenta) a memória do JSON
    final many = [
      for (var i = 0; i < 3000; i++) ['note_add', i % 8, i * 0.25, 0.25, 60 + i % 12, 0.8],
    ];
    engine.calls(many);
    expect((jsonDecode(lastCalls()) as List).length, 3000);
  }, skip: skip);

  test('loadSample copia os canais (estéreo e mono) para o motor', () async {
    await engine.start();
    int sampleId() => fake.lookupFunction<IntPtr Function(), int Function()>('fake_sample_id')();
    int frames() => fake.lookupFunction<IntPtr Function(), int Function()>('fake_sample_frames')();
    int stereo() => fake.lookupFunction<Int32 Function(), int Function()>('fake_sample_stereo')();
    double sum() => fake.lookupFunction<Double Function(), double Function()>('fake_sample_sum')();
    engine.loadSample(
      5,
      DecodedAudio([
        Float32List.fromList([0.5, 0.25, 0.25]),
        Float32List.fromList([1, 1]),
      ], 44100),
    );
    expect((sampleId(), frames(), stereo()), (5, 2, 1), reason: 'os quadros que os dois lados têm');
    expect(sum(), 2.75);
    engine.loadSample(
      6,
      DecodedAudio([
        Float32List.fromList([0.5, 0.5, 0.5, 0.5]),
      ], 48000),
    );
    expect((sampleId(), frames(), stereo(), sum()), (6, 4, 0, 2.0));
  }, skip: skip);

  test('decode num isolate: dois canais e a taxa do arquivo; o que não decodifica dá FormatException; nada vaza', () async {
    final a = await engine.decode(Uint8List.fromList([...ascii.encode('FAKE'), 10, 20, 30]));
    expect(a.rate, 44100);
    expect(a.channels.length, 2, reason: 'o arquivo tem três canais: ficam os dois primeiros');
    expect(a.channels[0], [
      for (final v in [0.1, 0.2, 0.3]) closeTo(v, 1e-6),
    ]);
    expect(a.channels[1], [
      for (final v in [0.2, 0.4, 0.6]) closeTo(v, 1e-6),
    ]);
    await expectLater(engine.decode(Uint8List.fromList(ascii.encode('RIFF....'))), throwsFormatException);
    await expectLater(engine.decode(Uint8List(0)), throwsFormatException);
    expect(live(), 0);
  }, skip: skip);

  test('sha-256 de arquivo grande (num isolate) e pequeno dão o mesmo que o crypto', () async {
    final big = Uint8List(3 << 20);
    for (var i = 0; i < big.length; i++) {
      big[i] = i * 31;
    }
    final small = Uint8List.sublistView(big, 0, 1000);
    expect(await engine.sha256Hex(big), hasLength(64));
    expect(await engine.sha256Hex(big), isNot(await engine.sha256Hex(small)));
    expect(await engine.sha256Hex(Uint8List.fromList(utf8.encode('abc'))), 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
  }, skip: skip);

  group('render', () {
    test('os blocos de cada saída montados no lugar, com o progresso, e o motor solto no fim', () async {
      final progress = <double>[];
      // 4 batidas a 120 bpm (2 s) mais 0,25 s de cauda a 8 kHz: 18000 quadros, 18 blocos
      final out = await engine.renderOffline(
        calls: [
          ['tempo', 120, 4],
          ['play'],
        ],
        samples: {
          1: DecodedAudio([Float32List(10)], 8000),
        },
        fromBeat: 0,
        toBeat: 4,
        tailSeconds: 0.25,
        outputs: [-1, 2],
        rate: 8000,
        onProgress: progress.add,
      );
      expect(out.length, 2);
      for (final (k, track) in [(0, -1), (1, 2)]) {
        final [l, r] = out[k];
        expect(l.length, 18000);
        expect(l.every((v) => v == track), isTrue, reason: 'saída $k é a captura da faixa $track');
        for (final i in [0, 1023, 1024, 17999]) {
          expect(r[i], i, reason: 'quadro $i da saída $k');
        }
      }
      expect(progress, isNotEmpty);
      expect(progress.every((p) => p >= 0 && p <= 1), isTrue);
      expect(live(), 0);
    }, skip: skip);

    test('mais de 64 saídas vão em passadas, cada uma com as capturas dela', () async {
      final outputs = [for (var i = 0; i < 70; i++) i];
      final out = await engine.renderOffline(calls: const [], samples: const {}, fromBeat: 0, toBeat: 1, tailSeconds: 0, outputs: outputs, rate: 8000);
      expect(out.length, 70);
      for (final k in [0, 63, 64, 69]) {
        expect(out[k][0].every((v) => v == k), isTrue, reason: 'saída $k');
        expect(out[k][1][3999], 3999);
      }
      expect(live(), 0);
    }, skip: skip);

    test('cancelar termina com RenderCanceled e solta o motor', () async {
      setSlow(20000);
      final r = engine.renderOffline(calls: const [], samples: const {}, fromBeat: 0, toBeat: 400, tailSeconds: 0, outputs: const [-1], rate: 8000);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      engine.cancelRender();
      await expectLater(r, throwsA(isA<RenderCanceled>()));
      expect(live(), 0);
    }, skip: skip);

    test('trecho vazio e memória demais viram StateError com a mensagem', () async {
      await expectLater(
        engine.renderOffline(calls: const [], samples: const {}, fromBeat: 2, toBeat: 2, tailSeconds: 1, outputs: const [-1], rate: 8000),
        throwsA(isA<StateError>().having((e) => e.message, 'mensagem', contains('vazio'))),
      );
      // 10 horas a 384 kHz passam do teto antes de reservar qualquer coisa
      await expectLater(
        engine.renderOffline(calls: const [], samples: const {}, fromBeat: 0, toBeat: 72000, tailSeconds: 0, outputs: const [-1, 0], rate: 384000),
        throwsA(isA<StateError>().having((e) => e.message, 'mensagem', allOf(contains('memória'), contains('2 saídas')))),
      );
    }, skip: skip);
  });

  group('entrada e captura', () {
    test('permissão negada: StateError em português (e o controlador não tenta outra entrada)', () async {
      await engine.start();
      permission = PermissionStatus.denied;
      await expectLater(engine.startInput(null), throwsA(isA<StateError>().having((e) => e.message, 'mensagem', contains('negou'))));
      permission = PermissionStatus.permanentlyDenied;
      await expectLater(
        engine.startInput(null),
        throwsA(isA<StateError>().having((e) => e.message, 'mensagem', allOf(contains('negou'), contains('permissões')))),
      );
    }, skip: skip);

    test('lista as entradas; abre a padrão (−1) e a escolhida; a que sumiu ou não abre explica', () async {
      await engine.start();
      int device() => fake.lookupFunction<IntPtr Function(), int Function()>('fake_input_device')();
      expect(await engine.inputDevices(), [('3', 'Microfone'), ('7', 'USB')]);
      expect(await engine.startInput(null), 0.012);
      expect(device(), -1);
      expect(await engine.startInput('3'), 0.012, reason: 'abrir de novo troca a entrada');
      expect(device(), 3);
      await expectLater(engine.startInput('9'), throwsA(isA<StateError>().having((e) => e.message, 'mensagem', contains('não está mais conectada'))));
      await expectLater(engine.startInput('7'), throwsA(isA<StateError>().having((e) => e.message, 'mensagem', contains('Não deu para abrir'))));
    }, skip: skip);

    test('aberta, o pico chega; a entrada que cai avisa uma vez e fecha', () async {
      await engine.start();
      int open() => fake.lookupFunction<Int32 Function(), int Function()>('fake_input_open')();
      await engine.startInput(null);
      await until(() => events.levels.isNotEmpty);
      expect(events.levels.first, 0.25);
      setLevel(-1);
      await until(() => events.lost.isNotEmpty);
      expect(events.lost, ['A entrada de áudio foi desconectada.']);
      expect(events.levels.last, 0, reason: 'o medidor desce a zero');
      expect(open(), 0);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(events.lost.length, 1);
    }, skip: skip);

    test('fechar a entrada zera o medidor; sem entrada aberta, nada', () async {
      await engine.start();
      await engine.startInput(null);
      await engine.stopInput();
      expect(events.levels.last, 0);
      final n = events.levels.length;
      await engine.stopInput();
      expect(events.levels.length, n);
    }, skip: skip);

    test('captura: blocos com a batida de cada um e, depois do último, o fim com as notas', () async {
      await engine.start();
      engine.setCapture(true);
      await until(() => events.blocks.length == 3);
      expect([for (final b in events.blocks) b.$1], [4, 5, 6]);
      expect(events.blocks[1].$2.every((v) => v == 2), isTrue);
      expect(events.blocks[1].$3.every((v) => v == -2), isTrue);
      expect(events.blocks[1].$2.length, 100);
      engine.setCapture(false);
      await until(() => events.ends.isNotEmpty);
      expect(events.order, ['bloco', 'bloco', 'bloco', 'fim']);
      final note = events.ends.single.single;
      expect((note.track, note.pitch, note.start, note.end), (1, 60, 4.0, 5.5));
      expect(note.velocity, closeTo(0.8, 1e-6));
    }, skip: skip);

    test('desligar sem captura ligada devolve um fim vazio (quem espera não fica preso)', () async {
      await engine.start();
      engine.setCapture(false);
      await until(() => events.ends.isNotEmpty);
      expect(events.ends.single, isEmpty);
    }, skip: skip);

    test('ligar a captura com o motor parado é StateError', () {
      expect(() => engine.setCapture(true), throwsStateError);
    }, skip: skip);
  });
}
