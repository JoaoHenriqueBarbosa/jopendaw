import 'dart:js_interop';
import 'dart:typed_data';

import 'engine_types.dart';

@JS('jopendawEngine')
external _Host get _host;

extension type _Host._(JSObject _) implements JSObject {
  external JSPromise<JSNumber> start();
  external JSPromise<JSString> sha256(JSUint8Array bytes);
  external JSPromise<JSAny?> resume();
  external JSPromise<_Decoded> decode(JSUint8Array bytes);
  external void loadSample(int id, JSArray<JSFloat32Array> channels, double rate);
  external void calls(JSArray<JSArray<JSAny>> list);
  external void setOnState(JSFunction cb);
  external void setOnLoudness(JSFunction cb);
  external double latency();
  external JSPromise<JSAny?> idbGet(String key);
  external JSPromise<JSAny?> idbPut(String key, JSAny value);
  external JSPromise<JSAny?> idbDelete(String key);
  external JSPromise<_MidiAccess> enableMidi();
  external void setOnMidi(JSFunction cb);
  external void setOnMidiInputs(JSFunction cb);
  external JSPromise<_InputOpened> startInput(String? deviceId);
  external JSPromise<JSAny?> stopInput();
  external JSPromise<JSArray<_InputDevice>> inputDevices();
  external void setCapture(bool on);
  external void setOnRecord(JSFunction cb);
  external void setOnInputLevel(JSFunction cb);
  external void setOnCaptureEnd(JSFunction cb);
  external void setOnInputLost(JSFunction cb);
  external JSPromise<_RenderResult> renderOffline(_RenderJob job, JSFunction? onProgress);
  external void cancelRender();
  external JSPromise<_WarpResult> stretchAudio(_WarpJob job, JSFunction? onProgress);
  external JSPromise<_WarpResult> detectBpm(_WarpJob job);
  external JSPromise<JSAny?> saveFile(String name, JSUint8Array bytes, String mime);
}

/// Resposta do `startInput` do host: a latência de entrada (s), ou o código do erro
/// (`unsupported`, `denied`, `notfound`, `missing`, `busy`, `rate`, `aborted`, `failed`) com a
/// mensagem do navegador.
extension type _InputOpened._(JSObject _) implements JSObject {
  external double? get latency;
  external String? get error;
  external String? get message;

  /// Só no erro `rate`: a taxa da entrada e a do motor.
  external double? get inputRate;
  external double? get rate;
}

extension type _InputDevice._(JSObject _) implements JSObject {
  external String get id;
  external String get name;
}

/// Pedido de render para o host (vira um objeto literal no JS).
extension type _RenderJob._(JSObject _) implements JSObject {
  external factory _RenderJob({
    JSArray<JSArray<JSAny>> calls,
    JSArray<_RenderSample> samples,
    double fromBeat,
    double toBeat,
    double tail,
    JSArray<JSNumber> outputs,
    double rate,
  });
}

extension type _RenderSample._(JSObject _) implements JSObject {
  external factory _RenderSample({int id, JSArray<JSFloat32Array> channels, double rate});
}

/// Resposta do `renderOffline` do host: os canais (esq, dir) de cada saída, ou o código do erro
/// (`canceled`, `empty`, `memory`, `unsupported`, `failed`) com a mensagem já em português.
extension type _RenderResult._(JSObject _) implements JSObject {
  external JSArray<JSArray<JSFloat32Array>>? get outputs;
  external String? get error;
  external String? get message;
}

/// Pedido de warp para o host: os canais (copiados), a taxa e, no esticar, a razão e os semitons.
extension type _WarpJob._(JSObject _) implements JSObject {
  external factory _WarpJob({JSArray<JSFloat32Array> channels, double rate, double ratio, double semitones});
}

/// Resposta do warp: os canais novos ou o andamento e a confiança, ou o código do erro com a
/// mensagem já em português.
extension type _WarpResult._(JSObject _) implements JSObject {
  external JSArray<JSFloat32Array>? get channels;
  external double? get bpm;
  external double? get confidence;
  external String? get error;
  external String? get message;
}

/// Nota tocada ao vivo durante uma captura, como o motor registrou: faixa, altura MIDI, início e
/// fim em batidas (a posição do quadro em que o motor processou o note on e o note off) e
/// velocidade 0..1.
typedef RecordedNote = ({int track, int pitch, double start, double end, double velocity});

/// O render foi cancelado por [AudioEngine.cancelRender] (não é falha: não pede aviso).
class RenderCanceled implements Exception {
  const RenderCanceled();

  @override
  String toString() => 'A renderização foi cancelada.';
}

/// Resposta do `enableMidi` do host: as entradas, ou o código do erro (`unsupported`, `denied`,
/// `failed`) com a mensagem do navegador.
extension type _MidiAccess._(JSObject _) implements JSObject {
  external JSArray<JSString>? get inputs;
  external String? get error;
  external String? get message;
}

extension type _Decoded._(JSObject _) implements JSObject {
  external JSArray<JSFloat32Array> get channels;
  external double get rate;
}

/// O motor no AudioWorklet, por `web/engine/host.js`.
class AudioEngine {
  AudioEngine._();
  static final instance = AudioEngine._();

  bool get supported => true;
  void Function(EngineState state)? onState;
  bool _hooked = false;

  /// Sobe o contexto de áudio e o motor; devolve a taxa de amostragem.
  Future<double> start() async {
    _hookInput();
    if (!_hooked) {
      _hooked = true;
      // medidor do efeito e espectro: opcionais, porque o dart2js despacha a função pelo número de
      // argumentos da chamada (com 5 obrigatórios, um host que manda 3 quebra todo estado); null
      // ou undefined viram 0 e null
      _host.setOnState(
        ((JSNumber beat, JSBoolean playing, JSFloat32Array peaks, [JSNumber? fxMeter, JSFloat32Array? spectrum]) {
          final meter = fxMeter?.toDartDouble ?? 0;
          onState?.call(EngineState(beat.toDartDouble, playing.toDart, peaks.toDart, fxMeter: meter.isFinite ? meter : 0, spectrum: spectrum?.toDart));
        }).toJS,
      );
    }
    _hookLoudness();
    return (await _host.start().toDart).toDartDouble;
  }

  /// Loudness do master (~30 por segundo, só quando muda): momentâneo, curto prazo, integrado,
  /// true peak e faixa. Zerar a medida é a chamada `loudness_reset`.
  void Function(LoudnessReading reading)? onLoudness;
  bool _loudnessHooked = false;

  void _hookLoudness() {
    if (_loudnessHooked) return;
    _loudnessHooked = true;
    _host.setOnLoudness(
      ((JSNumber m, JSNumber s, JSNumber i, JSNumber tp, JSNumber r) {
        onLoudness?.call(LoudnessReading.fromList([m.toDartDouble, s.toDartDouble, i.toDartDouble, tp.toDartDouble, r.toDartDouble]));
      }).toJS,
    );
  }

  /// Precisa vir de um gesto do usuário (o navegador segura o áudio até lá).
  Future<void> resume() => _host.resume().toDart;

  Future<DecodedAudio> decode(Uint8List bytes) async {
    final d = await _host.decode(bytes.toJS).toDart;
    return DecodedAudio([for (final c in d.channels.toDart) c.toDart], d.rate);
  }

  _WarpJob _warpJob(DecodedAudio a, double ratio, double semitones) =>
      _WarpJob(channels: [for (final c in a.channels) c.toJS].toJS, rate: a.rate, ratio: ratio, semitones: semitones);

  /// Warp: esticar ([ratio] = duração final / original, 0,25..4) e transpor ([semitones],
  /// −24..24) sem mexer no que toca. Roda num Worker (nunca no worklet nem na tela). [onProgress]
  /// (0..1) é opcional e só marca o começo e o fim: o wasm é síncrono.
  Future<DecodedAudio> stretch(DecodedAudio a, {required double ratio, double semitones = 0, void Function(double progress)? onProgress}) async {
    final r = await _host
        .stretchAudio(_warpJob(a, ratio, semitones), onProgress == null ? null : ((JSNumber p) => onProgress(p.toDartDouble.clamp(0, 1).toDouble())).toJS)
        .toDart;
    final error = r.error;
    if (error != null) throw StateError(r.message ?? 'Não deu para processar este áudio.');
    return DecodedAudio([for (final c in r.channels!.toDart) c.toDart], a.rate);
  }

  /// Estima o andamento (60..200 BPM) e a confiança (0..1); bpm 0 = não deu para estimar.
  Future<({double bpm, double confidence})> detectBpm(DecodedAudio a) async {
    final r = await _host.detectBpm(_warpJob(a, 1, 0)).toDart;
    if (r.error != null) throw StateError(r.message ?? 'Não deu para analisar este áudio.');
    return (bpm: r.bpm ?? 0, confidence: r.confidence ?? 0);
  }

  void loadSample(int id, DecodedAudio audio) => _host.loadSample(id, [for (final c in audio.channels) c.toJS].toJS, audio.rate);

  void calls(List<List<Object>> list) {
    _host.calls(
      [
        for (final c in list) [for (final a in c) _js(a)].toJS,
      ].toJS,
    );
  }

  /// Mensagens MIDI de entrada (status, dado 1, dado 2). Só mensagens de canal: relógio e
  /// active sensing ficam no host.
  void Function(int status, int data1, int data2)? onMidi;

  /// Entradas MIDI conectadas, a cada aparelho que entra ou sai.
  void Function(List<String> inputs)? onMidiInputs;
  bool _midiHooked = false;

  /// Pede acesso ao MIDI do navegador (Web MIDI, sem sysex) e passa a ouvir todas as entradas;
  /// devolve os nomes delas. Sem suporte: [UnsupportedError]; permissão negada: [StateError].
  Future<List<String>> enableMidi() async {
    if (!_midiHooked) {
      _midiHooked = true;
      _host.setOnMidi(
        ((JSNumber status, JSNumber data1, JSNumber data2) {
          onMidi?.call(status.toDartInt, data1.toDartInt, data2.toDartInt);
        }).toJS,
      );
      _host.setOnMidiInputs(
        ((JSArray<JSString> names) {
          onMidiInputs?.call(_names(names));
        }).toJS,
      );
    }
    final r = await _host.enableMidi().toDart;
    switch (r.error) {
      case null:
        final inputs = r.inputs;
        return inputs == null ? const [] : _names(inputs);
      case 'unsupported':
        throw UnsupportedError('Este navegador não dá acesso a MIDI. Use o Chrome ou o Edge, com o jopendaw aberto em https.');
      case 'denied':
        throw StateError('O navegador negou o acesso ao MIDI. Libere o MIDI nas permissões do site e tente de novo.');
      default:
        throw StateError('Não deu para abrir o MIDI: ${r.message ?? r.error}.');
    }
  }

  static List<String> _names(JSArray<JSString> names) => [for (final n in names.toDart) n.toDart];

  /// Latência de saída em segundos (base + dispositivo).
  double get latency => _host.latency();

  static JSAny _js(Object v) => switch (v) {
    final String s => s.toJS,
    final bool b => (b ? 1 : 0).toJS,
    final int i => i.toJS,
    final double d => d.toJS,
    _ => throw ArgumentError('argumento do motor: $v'),
  };

  // ------------------------------------------------------------------ gravação e render (fase 4)

  /// Abre a entrada de áudio ([deviceId] null = padrão), sem cancelamento de eco, supressão de
  /// ruído nem ganho automático, e liga ela no worklet (o motor recebe cada bloco; o pico chega em
  /// [onInputLevel]). Devolve a latência de entrada que o navegador informa (s): a do aparelho,
  /// quando há, mais a base do contexto. Abrir de novo troca a entrada.
  ///
  /// Sem suporte no navegador: [UnsupportedError]; permissão negada, entrada inexistente, ocupada
  /// ou fechada durante a abertura: [StateError] com a mensagem para o usuário.
  Future<double> startInput(String? deviceId) async {
    _hookInput();
    final r = await _host.startInput(deviceId).toDart;
    switch (r.error) {
      case null:
        final latency = r.latency ?? 0;
        return latency.isFinite && latency > 0 ? latency : 0;
      case 'unsupported':
        throw UnsupportedError('Este navegador não dá acesso ao microfone. Use um navegador atual, com o jopendaw aberto em https.');
      case 'denied':
        throw StateError('O navegador negou o acesso ao microfone. Libere o microfone nas permissões do site e tente de novo.');
      case 'notfound':
        throw StateError('Nenhuma entrada de áudio encontrada. Conecte um microfone ou uma interface de áudio e tente de novo.');
      case 'missing':
        throw StateError('A entrada de áudio escolhida não está mais conectada. Escolha outra ou volte para a padrão.');
      case 'busy':
        throw StateError('A entrada de áudio está ocupada por outro programa ou não respondeu. Feche o que estiver usando ela e tente de novo.');
      case 'rate':
        final input = (r.inputRate ?? 0).round();
        final engine = (r.rate ?? 0).round();
        throw StateError(
          'A entrada de áudio está em ${input > 0 ? '$input Hz' : 'outra taxa'} e o motor em $engine Hz, e este navegador não converte. '
          'Ajuste a entrada para $engine Hz nas configurações de som do sistema.',
        );
      case 'aborted':
        throw StateError('A abertura da entrada de áudio foi cancelada.');
      default:
        throw StateError('Não deu para abrir a entrada de áudio: ${r.message ?? r.error}.');
    }
  }

  /// Fecha a entrada (o navegador solta o microfone) e zera o medidor. Sem entrada aberta, nada.
  Future<void> stopInput() => _host.stopInput().toDart;

  /// Entradas de áudio (id, nome), sem as pseudo-entradas do sistema (a padrão é o id null). Os
  /// nomes só aparecem depois de o site ganhar a permissão do microfone ([startInput]).
  Future<List<(String, String)>> inputDevices() async {
    final list = await _host.inputDevices().toDart;
    return [for (final d in list.toDart) (d.id, d.name)];
  }

  /// Liga/desliga a captura: enquanto o transporte toca, o que entra chega em blocos (~85 ms) em
  /// [onRecord], cada um com a batida do primeiro quadro em [recordBeat], e o motor registra as
  /// notas tocadas ao vivo. Desligar entrega o resto do áudio e depois [onCaptureEnd], nessa ordem.
  ///
  /// Os blocos de uma captura são contínuos no tempo do transporte a partir do [recordBeat] de
  /// cada um (com a volta do loop, quando ligado, no quadro exato do fim dele); um salto de
  /// posição ou uma parada fecha o bloco, e o seguinte vem com a batida nova. Com o transporte
  /// parado nada é capturado. Sem entrada aberta, só as notas (gravar numa faixa de instrumento
  /// não pede microfone); se a entrada cair no meio, a captura segue com silêncio para o resto
  /// continuar no lugar.
  void setCapture(bool on) {
    _hookInput();
    _host.setCapture(on);
  }

  /// Blocos capturados da entrada (esq, dir) e o pico dela. O pico chega ~30 vezes por segundo
  /// sempre que a entrada está aberta (o medidor das faixas armadas funciona antes de gravar),
  /// não só durante a captura.
  void Function(Float32List left, Float32List right)? onRecord;
  void Function(double peak)? onInputLevel;

  /// Batida do transporte no primeiro quadro do bloco que [onRecord] está entregando (vale durante
  /// a chamada). Sem compensação de latência: descontar a de entrada, a de saída e a do documento
  /// é do controlador.
  double recordBeat = 0;

  /// Fim de uma captura ([setCapture] false): chega depois do último bloco de [onRecord] e traz as
  /// notas ao vivo que o motor registrou (vazia quando ninguém tocou ou o motor não registra).
  void Function(List<RecordedNote> notes)? onCaptureEnd;

  /// A entrada aberta sumiu sozinha (cabo, interface desligada, permissão revogada): ela já foi
  /// fechada; vem a mensagem para o usuário.
  void Function(String message)? onInputLost;

  bool _inputHooked = false;

  void _hookInput() {
    if (_inputHooked) return;
    _inputHooked = true;
    // argumentos opcionais pelo mesmo motivo do setOnState: o dart2js despacha pelo número deles
    _host.setOnRecord(
      ((JSFloat32Array left, JSFloat32Array right, [JSNumber? beat]) {
        final b = beat?.toDartDouble ?? 0;
        recordBeat = b.isFinite ? b : 0;
        onRecord?.call(left.toDart, right.toDart);
      }).toJS,
    );
    _host.setOnInputLevel(
      ((JSNumber peak) {
        final p = peak.toDartDouble;
        onInputLevel?.call(p.isFinite ? p.clamp(0, 1).toDouble() : 0);
      }).toJS,
    );
    _host.setOnCaptureEnd(
      ([JSFloat32Array? notes]) {
        onCaptureEnd?.call(_recordedNotes(notes?.toDart));
      }.toJS,
    );
    _host.setOnInputLost(
      ([JSString? label]) {
        final name = label?.toDart ?? '';
        onInputLost?.call(name.isEmpty ? 'A entrada de áudio foi desconectada.' : 'A entrada de áudio "$name" foi desconectada.');
      }.toJS,
    );
  }

  /// Notas do registro do motor: grupos de 5 floats (faixa, altura, início, fim, velocidade).
  static List<RecordedNote> _recordedNotes(Float32List? flat) {
    if (flat == null) return const [];
    final notes = <RecordedNote>[];
    for (var i = 0; i + 5 <= flat.length; i += 5) {
      final start = flat[i + 2];
      final end = flat[i + 3];
      if (!start.isFinite || !end.isFinite || !flat[i].isFinite || !flat[i + 1].isFinite) continue;
      final velocity = flat[i + 4];
      notes.add((
        track: flat[i].round(),
        pitch: flat[i + 1].round().clamp(0, 127),
        start: start,
        end: end < start ? start : end,
        velocity: velocity.isFinite ? velocity.clamp(0, 1).toDouble() : 0.8,
      ));
    }
    return notes;
  }

  /// Renderiza fora de tempo real num motor separado (Worker, sem esperar o relógio e sem travar a
  /// interface): [calls] são as chamadas do documento (como o _sync manda), [samples] os áudios
  /// por id do motor; devolve os canais de cada saída pedida em [outputs] (−1 = master,
  /// pós-limitador; i = só a faixa i, pós-fader), com (toBeat − fromBeat) no andamento das
  /// chamadas mais [tailSeconds] de quadros.
  ///
  /// O render não tem metrônomo nem loop, e as chamadas de transporte e de notas ao vivo em
  /// [calls] são ignoradas. Na cauda o transporte segue (a automação continua valendo), mas nada
  /// começa depois de [toBeat]: clipes e notas que atravessam o fim terminam nele (clipe com um
  /// fade de 10 ms, nota com a soltura do instrumento); soam só as caudas do que já tocava.
  ///
  /// Cancelado por [cancelRender]: [RenderCanceled]. Trecho vazio, falta de memória ou falha do
  /// motor: [StateError] com a mensagem para o usuário.
  Future<List<List<Float32List>>> renderOffline({
    required List<List<Object>> calls,
    required Map<int, DecodedAudio> samples,
    required double fromBeat,
    required double toBeat,
    required double tailSeconds,
    required List<int> outputs,
    required double rate,
    void Function(double progress)? onProgress,
  }) async {
    final job = _RenderJob(
      calls: [
        for (final c in calls) [for (final a in c) _js(a)].toJS,
      ].toJS,
      samples: [
        for (final e in samples.entries) _RenderSample(id: e.key, channels: [for (final c in e.value.channels) c.toJS].toJS, rate: e.value.rate),
      ].toJS,
      fromBeat: fromBeat,
      toBeat: toBeat,
      tail: tailSeconds,
      outputs: [for (final o in outputs) o.toJS].toJS,
      rate: rate,
    );
    final progress = onProgress == null
        ? null
        : ((JSNumber p) {
            onProgress(p.toDartDouble.clamp(0, 1).toDouble());
          }).toJS;
    final r = await _host.renderOffline(job, progress).toDart;
    switch (r.error) {
      case null:
        final outs = r.outputs;
        if (outs == null) throw StateError('O render não devolveu áudio.');
        return [
          for (final o in outs.toDart) [for (final c in o.toDart) c.toDart],
        ];
      case 'canceled':
        throw const RenderCanceled();
      case 'unsupported':
        throw UnsupportedError(r.message ?? 'Este navegador não consegue renderizar em segundo plano.');
      default:
        throw StateError(r.message ?? 'O render falhou.');
    }
  }

  /// Interrompe os renders em andamento: cada [renderOffline] pendente termina com
  /// [RenderCanceled].
  void cancelRender() => _host.cancelRender();

  /// Oferece os bytes para salvar como arquivo (download no navegador).
  Future<void> saveFile(String name, Uint8List bytes, String mime) => _host.saveFile(name, bytes.toJS, mime).toDart;

  /// sha-256 em hexa (a chave dos áudios no guardado local), pelo WebCrypto do navegador.
  Future<String> sha256Hex(Uint8List bytes) async => (await _host.sha256(bytes.toJS).toDart).toDart;
}

/// Guardado local do DAW no IndexedDB: textos (o documento) e bytes (os áudios importados).
class LocalStore {
  LocalStore._();
  static final instance = LocalStore._();

  Future<Object?> get(String key) async {
    final v = await _host.idbGet(key).toDart;
    if (v == null) return null;
    if (v.isA<JSString>()) return (v as JSString).toDart;
    if (v.isA<JSUint8Array>()) return (v as JSUint8Array).toDart;
    return null;
  }

  Future<void> put(String key, Object value) async {
    final JSAny js = switch (value) {
      final String s => s.toJS,
      final Uint8List b => b.toJS,
      _ => throw ArgumentError('valor do guardado local: ${value.runtimeType}'),
    };
    await _host.idbPut(key, js).toDart;
  }

  Future<void> delete(String key) => _host.idbDelete(key).toDart;
}
