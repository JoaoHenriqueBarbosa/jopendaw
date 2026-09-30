package tech.johnenrique.jopendaw

import android.content.ActivityNotFoundException
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * A tela única do app. Além do Flutter, cuida do que só o Android sabe fazer e o Dart pede pelo
 * canal `jopendaw/apps` (lib/platform/platform_native.dart):
 *
 * - `openIn(url, package)`: abre um link num app específico (o do Discord, para entrar);
 * - `keepScreenOn(bool)`: tela acesa enquanto toca ou grava;
 *
 * (a permissão do microfone é pedida pelo `permission_handler` em `startInput` do engine_ffi.dart)
 * e avisa o Dart, pelo mesmo canal, de `audioNoisy` (o fone saiu: o som ia para o alto-falante) e
 * de `audioDevices` (um aparelho de áudio entrou ou saiu).
 */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null

    /** Aparelhos de áudio da última vez que olhamos (null antes da primeira). */
    private var knownDevices: Set<Int>? = null

    private val audio: AudioManager by lazy { getSystemService(AudioManager::class.java) }

    // O Android manda este aviso antes de trocar a saída para o alto-falante quando o fone (com fio
    // ou Bluetooth) sai: todo app de mídia para aqui, senão a música estoura na sala.
    private val noisy =
        object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                if (intent.action == AudioManager.ACTION_AUDIO_BECOMING_NOISY) channel?.invokeMethod("audioNoisy", null)
            }
        }

    // Fone plugado, interface USB ligada: a lista de entradas muda e a saída troca de rota (o
    // AAudio desconecta o stream, e o motor precisa reabrir no aparelho novo).
    private val devices =
        object : AudioDeviceCallback() {
            override fun onAudioDevicesAdded(added: Array<out AudioDeviceInfo>) = devicesChanged()

            override fun onAudioDevicesRemoved(removed: Array<out AudioDeviceInfo>) = devicesChanged()
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        loadEngine()
        super.onCreate(savedInstanceState)
        // Os botões de volume mexem no volume de mídia (o do motor) mesmo com o transporte parado;
        // sem isso, parado, eles mexem na campainha.
        volumeControlStream = AudioManager.STREAM_MUSIC
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "jopendaw/apps")
        channel = ch
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "openIn" -> openIn(call, result)
                "keepScreenOn" -> keepScreenOn(call.arguments == true, result)
                else -> result.notImplemented()
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        channel?.setMethodCallHandler(null)
        channel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onStart() {
        super.onStart()
        // Só enquanto a tela está à mostra: fora dela o Dart já parou o transporte e fechou a
        // entrada. O aviso vem do sistema, que entrega mesmo a um receptor não exportado; outro app
        // não tem por que parar o nosso transporte.
        val filter = IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(noisy, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(noisy, filter)
        }
        // O registro chama onAudioDevicesAdded na hora com os aparelhos atuais: comparado com os de
        // antes de sair, avisa do fone plugado enquanto o app estava fora.
        audio.registerAudioDeviceCallback(devices, Handler(Looper.getMainLooper()))
    }

    override fun onStop() {
        unregisterReceiver(noisy)
        audio.unregisterAudioDeviceCallback(devices)
        super.onStop()
    }

    /**
     * Abre um link num app específico (o do Discord, para autorizar a entrada), sem depender de o app
     * estar marcado para abrir os links dele: com o pacote no intent, o Android entrega direto.
     * `false` quando o app não está instalado.
     */
    private fun openIn(call: MethodCall, result: MethodChannel.Result) {
        val url = call.argument<String>("url")
        val pkg = call.argument<String>("package")
        if (url == null || pkg == null) return result.success(false)
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).setPackage(pkg).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        try {
            startActivity(intent)
            result.success(true)
        } catch (e: ActivityNotFoundException) {
            result.success(false)
        }
    }

    /** Vale só com a janela à mostra: em segundo plano o Android apaga a tela de qualquer jeito. */
    private fun keepScreenOn(on: Boolean, result: MethodChannel.Result) {
        if (on) {
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
        result.success(null)
    }

    private fun devicesChanged() {
        val now = audio.getDevices(AudioManager.GET_DEVICES_ALL).map { it.id }.toSet()
        val before = knownDevices
        knownDevices = now
        if (before != null && before != now) channel?.invokeMethod("audioDevices", null)
    }

    companion object {
        /**
         * Carrega o motor nativo pelo System.loadLibrary antes de o Dart abri-lo (o DynamicLibrary.open
         * do engine_ffi.dart acha a mesma cópia, já carregada). Só por este caminho o Android chama o
         * JNI_OnLoad da biblioteca com a JavaVM, que é por onde o motor pega o contexto do app para
         * o motor consultar o AudioManager pela JNI (listar entradas, taxa nativa). Sem os .so
         * (build sem o motor), o app abre igual e a tela do projeto avisa que o motor não carregou.
         */
        private val engineLoaded: Boolean by lazy {
            try {
                System.loadLibrary("jopendaw_engine")
                true
            } catch (e: UnsatisfiedLinkError) {
                Log.w("jopendaw", "o motor nativo não carregou: ${e.message}")
                false
            }
        }

        private fun loadEngine() = engineLoaded
    }
}
