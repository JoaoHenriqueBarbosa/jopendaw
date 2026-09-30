// O que o controlador faz com o aparelho no Android: a tela fica acesa enquanto toca ou grava (e
// solta ao parar ou ao fechar a tela), e o transporte pausa quando o fone sai ou o app sai da tela.
// O canal `jopendaw/apps` é simulado dos dois lados: as chamadas que o Dart faz e os avisos que o
// MainActivity.kt manda.
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jopendaw_app/audio/engine.dart';

import 'fake_engine.dart';

const _channel = MethodChannel('jopendaw/apps');

/// O aviso que o Kotlin manda para o Dart.
Future<void> notify(String method) async {
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
    _channel.name,
    _channel.codec.encodeMethodCall(MethodCall(method)),
    (_) {},
  );
}

EngineState state({required bool playing}) => EngineState(1, playing, Float32List(0));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeEngine e;
  late List<bool> screen;

  setUp(() {
    e = FakeEngine();
    screen = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (call) async {
      if (call.method == 'keepScreenOn') screen.add(call.arguments as bool);
      return null;
    });
  });

  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, null));

  test('tela acesa enquanto toca, solta ao parar; repetir o estado não repete a chamada', () async {
    final c = fakeController(e);
    await c.open();
    e.onState!(state(playing: false));
    expect(screen, isEmpty, reason: 'parado desde o começo: nada a soltar');
    e.onState!(state(playing: true));
    e.onState!(state(playing: true));
    expect(screen, [true]);
    e.onState!(state(playing: false));
    expect(screen, [true, false]);
    c.dispose();
  });

  test('fechar a tela do projeto tocando solta a tela', () async {
    final c = fakeController(e);
    await c.open();
    e.onState!(state(playing: true));
    c.dispose();
    expect(screen, [true, false]);
  });

  test('o fone que sai pausa o transporte e solta as notas, sem voltar o cursor', () async {
    final c = fakeController(e);
    await c.open();
    e.onState!(state(playing: true));
    expect(c.playing.value, isTrue);
    e.log!.clear();
    await notify('audioNoisy');
    expect(c.playing.value, isFalse);
    expect(e.sent('stop'), hasLength(1));
    expect(e.sent('seek'), isEmpty, reason: 'pausa, não para: o cursor fica onde estava');
    // sem nada tocando, o aviso não manda nada ao motor
    e.log!.clear();
    await notify('audioNoisy');
    expect(e.log, isEmpty);
    c.dispose();
  });

  test('um aparelho de áudio que entra ou sai não pausa (só religa a saída); depois de fechada a tela, nada reage', () async {
    final c = fakeController(e);
    await c.open();
    e.onState!(state(playing: true));
    await notify('audioDevices');
    expect(c.playing.value, isTrue);
    c.dispose();
    e.log!.clear();
    await notify('audioNoisy');
    expect(e.log, isEmpty);
  });
}
