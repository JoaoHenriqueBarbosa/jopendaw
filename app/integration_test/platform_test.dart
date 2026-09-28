/// A ponte com o Android do lado do app (MainActivity.kt ↔ lib/platform/platform_native.dart), no
/// emulador ou no aparelho: tela acesa, permissão do microfone e os avisos de áudio (sair da tela,
/// fone saindo, aparelho de áudio entrando). Não depende do motor nativo.
///
///     cd app && flutter test integration_test/platform_test.dart -d emulator-5554
library;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:jopendaw_app/platform/platform_native.dart';

const _apps = MethodChannel('jopendaw/apps');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// Um aviso do MainActivity.kt ao Dart, como se tivesse vindo do Android.
  Future<void> fromAndroid(String method) async {
    await binding.defaultBinaryMessenger.handlePlatformMessage(_apps.name, const StandardMethodCodec().encodeMethodCall(MethodCall(method)), (_) {});
  }

  void lifecycle(List<AppLifecycleState> states) {
    for (final s in states) {
      binding.handleAppLifecycleStateChanged(s);
    }
  }

  testWidgets('keepScreenOn chega ao Android e pode repetir o valor', (tester) async {
    // direto pelo canal: sem o método no MainActivity.kt isto dá MissingPluginException
    await _apps.invokeMethod<void>('keepScreenOn', true);
    await _apps.invokeMethod<void>('keepScreenOn', false);
    keepScreenOn(true);
    keepScreenOn(true);
    keepScreenOn(false);
  });

  testWidgets('a permissão do microfone é consultada sem perguntar nada', (tester) async {
    final direct = await _apps.invokeMethod<bool>('microphone');
    expect(direct, isNotNull);
    expect(await microphoneAllowed(), direct);
  });

  testWidgets('sair da tela e voltar avisam uma vez cada; um diálogo por cima não conta', (tester) async {
    var leaves = 0, returns = 0;
    final off = watchAudioSession(onLeave: () => leaves++, onReturn: () => returns++);
    try {
      // o pedido de permissão por cima: o app perde o foco mas segue à mostra
      lifecycle([AppLifecycleState.inactive, AppLifecycleState.resumed]);
      expect((leaves, returns), (0, 0));
      // botão de início: inativo, escondido, pausado
      lifecycle([AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]);
      expect((leaves, returns), (1, 0));
      // de volta
      lifecycle([AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]);
      expect((leaves, returns), (1, 1));
    } finally {
      off();
    }
    // desligado, não avisa mais
    lifecycle([AppLifecycleState.inactive, AppLifecycleState.hidden]);
    lifecycle([AppLifecycleState.inactive, AppLifecycleState.resumed]);
    expect((leaves, returns), (1, 1));
  });

  testWidgets('fone saindo e aparelho de áudio entrando chegam a cada inscrito', (tester) async {
    var noisyA = 0, noisyB = 0, devices = 0;
    final offA = watchAudioSession(onNoisy: () => noisyA++, onDevices: () => devices++);
    final offB = watchAudioSession(onNoisy: () => noisyB++);
    await fromAndroid('audioNoisy');
    await fromAndroid('audioDevices');
    expect((noisyA, noisyB, devices), (1, 1, 1));
    offA();
    await fromAndroid('audioNoisy');
    expect((noisyA, noisyB), (1, 2));
    offB();
    await fromAndroid('audioNoisy');
    expect((noisyA, noisyB), (1, 2));
  });
}
