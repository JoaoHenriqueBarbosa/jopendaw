import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

SharedPreferences? _prefs;
bool _fullscreen = false;

/// Carrega as preferências antes do primeiro quadro, para o guardado local ser síncrono.
Future<void> initPlatform() async {
  _prefs = await SharedPreferences.getInstance();
}

/// O app está em primeiro plano (antes do primeiro aviso do sistema, vale à mostra).
bool get pageVisible {
  final state = WidgetsBinding.instance.lifecycleState;
  return state == null || state == AppLifecycleState.resumed;
}

/// Chama [onChange] quando o app vai para o primeiro plano ou sai dele; devolve o que desliga.
void Function() onVisibilityChange(void Function() onChange) {
  var visible = pageVisible;
  final listener = AppLifecycleListener(
    onStateChange: (_) {
      if (pageVisible == visible) return;
      visible = pageVisible;
      onChange();
    },
  );
  return listener.dispose;
}

bool get isFullscreen => _fullscreen;

/// Devolve as barras do sistema, se estiverem escondidas.
void exitFullscreen() {
  if (_fullscreen) toggleFullscreen();
}

/// Esconde (ou devolve) as barras do sistema. Os recuos do [SafeArea] seguem: sem a barra de
/// navegação, o espaço dela some (o da câmera fica).
void toggleFullscreen() {
  _fullscreen = !_fullscreen;
  SystemChrome.setEnabledSystemUIMode(_fullscreen ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
}

/// Entrar pelo Google ou pelo Discord: uma aba do Chrome sobre o app, que fecha sozinha quando o
/// servidor devolve o app pelo esquema dele (`tech.johnenrique.jopendaw://oauth?…`). Devolve esse
/// endereço, ou `null` se a pessoa fechou a aba.
Future<String?> openSignIn(String url) async {
  try {
    return await FlutterWebAuth2.authenticate(url: url, callbackUrlScheme: 'tech.johnenrique.jopendaw');
  } on PlatformException catch (e) {
    if (e.code == 'CANCELED') return null;
    rethrow;
  }
}

const _apps = MethodChannel('jopendaw/apps');

/// Abre o link no app do pacote `package` (o do Discord, para autorizar a entrada), mesmo que ele
/// não esteja marcado para abrir os links dele; `false` se o app não está instalado.
Future<bool> openInOtherApp(String url, {required String package}) async {
  try {
    return await _apps.invokeMethod<bool>('openIn', {'url': url, 'package': package}) ?? false;
  } catch (_) {
    return false;
  }
}

/// Abre o link no navegador do aparelho.
void openExternal(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

String? localRead(String key) => _prefs?.getString(key);

void localWrite(String key, String value) => _prefs?.setString(key, value);

// ------------------------------------------------------------------ áudio no Android (fase 5)
//
// O motor toca no próprio aparelho (lib/audio/engine_io.dart), e o que a aba do navegador resolve
// sozinha aqui é do app: tela acesa, o que fazer ao sair da tela, fone que sai ou entra e a
// permissão do microfone. O lado do Android está em MainActivity.kt, pelo mesmo canal `_apps`.

bool? _screenOn;

/// Mantém a tela acesa enquanto [on]: ninguém quer a tela apagando no meio de uma tomada, nem
/// tocar nela a cada meio minuto só para ver o cursor andar. Repetir o valor não vai ao Android,
/// então dá para chamar a cada estado do motor. Na web não faz nada (platform_web.dart).
///
/// O controlador (lib/daw/controller.dart) chama com `s.playing || recording` em
/// `_onEngineState` e com `false` no `dispose` (a tela do projeto fechando não pode deixar o
/// aparelho sem apagar).
void keepScreenOn(bool on) {
  if (_screenOn == on) return;
  _screenOn = on;
  // fora do Android (testes, desktop) não há quem responda; a próxima chamada tenta de novo
  void failed(Object _) => _screenOn = null;
  try {
    _apps.invokeMethod<void>('keepScreenOn', on).catchError(failed);
  } catch (e) {
    failed(e);
  }
}

/// Um inscrito nos avisos de áudio do Android (identidade própria: dois inscritos com as mesmas
/// funções são dois).
class _AudioWatcher {
  final void Function()? noisy, devices;
  _AudioWatcher(this.noisy, this.devices);
}

final _audioWatchers = <_AudioWatcher>[];
bool _appsListening = false;

/// Avisos do aparelho sobre o áudio do DAW; devolve o que desliga. Na web não há nenhum (a aba
/// segue tocando em segundo plano, como qualquer player do navegador): lá devolve um desligar vazio.
///
/// - [onLeave]: o app saiu da tela (outro app na frente, botão de início, tela desligada). Sem um
///   serviço em primeiro plano o Android pode matar o processo a qualquer momento depois disso, e
///   o microfone aberto em segundo plano deixa o aviso de privacidade aceso: o controlador para o
///   transporte (encerrando a gravação em andamento, que fica salva, como o `stop`), solta as
///   notas ao vivo e fecha a entrada.
/// - [onReturn]: voltou para a tela. O controlador chama `AudioEngine.resume()`, que garante a
///   saída tocando (reabre se o Android a derrubou enquanto o app estava fora), e reabre a entrada
///   se alguma faixa de áudio ficou armada ou monitorando, como o `open` faz (`_restoreInput`).
/// - [onNoisy]: o fone (com fio ou Bluetooth) saiu e o som ia passar para o alto-falante: o
///   controlador para o transporte, como todo app de mídia faz.
/// - [onDevices]: um aparelho de áudio entrou ou saiu (fone plugado, interface USB). A saída pode
///   ter trocado de rota e a lista de entradas mudou: o controlador chama `AudioEngine.resume()` e
///   relê a lista de entradas (sem abrir o microfone).
///
/// Um diálogo por cima (o pedido de permissão do microfone, a cortina de notificações, a tela
/// dividida com outro app) não conta como sair: o app segue à mostra, só sem o foco.
void Function() watchAudioSession({void Function()? onLeave, void Function()? onReturn, void Function()? onNoisy, void Function()? onDevices}) {
  bool hidden(AppLifecycleState? s) => s == AppLifecycleState.hidden || s == AppLifecycleState.paused || s == AppLifecycleState.detached;
  var away = hidden(WidgetsBinding.instance.lifecycleState);
  final listener = AppLifecycleListener(
    onStateChange: (s) {
      final now = hidden(s);
      if (now == away) return;
      away = now;
      (away ? onLeave : onReturn)?.call();
    },
  );
  final watcher = _AudioWatcher(onNoisy, onDevices);
  _audioWatchers.add(watcher);
  _listenApps();
  return () {
    listener.dispose();
    _audioWatchers.remove(watcher);
  };
}

/// Os avisos que o MainActivity.kt manda pelo canal `_apps`, repassados a cada inscrito.
void _listenApps() {
  if (_appsListening) return;
  _appsListening = true;
  _apps.setMethodCallHandler((call) async {
    // cópia: um inscrito pode se desligar no meio do aviso
    final watchers = List.of(_audioWatchers);
    switch (call.method) {
      case 'audioNoisy':
        for (final w in watchers) {
          w.noisy?.call();
        }
      case 'audioDevices':
        for (final w in watchers) {
          w.devices?.call();
        }
      default:
        throw MissingPluginException('jopendaw/apps: ${call.method}');
    }
  });
}
