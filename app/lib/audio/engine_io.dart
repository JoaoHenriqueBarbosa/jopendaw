/// O motor de áudio fora do navegador. No Android, o motor nativo pelo dart:ffi
/// (`engine_ffi.dart`) e o guardado local em arquivos; nos outros sistemas (os testes no computador,
/// um build de desktop) ainda não há motor: a tela do projeto avisa em vez de tocar, e as chamadas
/// que iriam a ele ficam em [AudioEngine.log] quando um teste pede.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path_provider/path_provider.dart';

import 'engine_ffi.dart';
import 'engine_types.dart';

export 'engine_ffi.dart' show RecordedNote, RenderCanceled;

/// O motor de áudio, com a mesma interface do engine_web.dart (a documentação de cada coisa está
/// lá). Escolhe o backend em tempo de execução: o nativo no Android, nenhum no resto.
class AudioEngine implements EngineEvents {
  AudioEngine._();
  static final instance = AudioEngine._();

  late final FfiEngine? _native = Platform.isAndroid ? FfiEngine(this) : null;

  static const _noEngine = 'O motor de áudio não roda neste sistema: use o jopendaw no navegador ou no Android.';
  static const _noRecording = 'A gravação não funciona neste sistema: use o jopendaw no navegador ou no Android.';
  static const _noWarp = 'Ajustar o áudio ao andamento não funciona neste sistema: use o jopendaw no navegador ou no Android.';
  static const _noRender = 'Exportar e congelar faixas não funcionam neste sistema: use o jopendaw no navegador ou no Android.';

  bool get supported => _native != null;

  Future<double> start() => _native?.start() ?? Future.error(UnsupportedError(_noEngine));

  Future<void> resume() => _native?.resume() ?? Future.value();

  Future<DecodedAudio> decode(Uint8List bytes) => _native?.decode(bytes) ?? Future.error(UnsupportedError('Sem motor de áudio.'));

  void loadSample(int id, DecodedAudio audio) => _native?.loadSample(id, audio);

  /// Warp: esticar ([ratio] = duração final / original, 0,25..4) e transpor ([semitones],
  /// −24..24) sem mexer no que toca. Roda fora da thread de áudio. [onProgress] (0..1) é opcional:
  /// no Android só avisa o fim.
  Future<DecodedAudio> stretch(DecodedAudio a, {required double ratio, double semitones = 0, void Function(double progress)? onProgress}) async {
    final native = _native;
    if (native == null) throw UnsupportedError(_noWarp);
    final out = await native.stretch(a, ratio: ratio, semitones: semitones);
    onProgress?.call(1);
    return out;
  }

  /// Estima o andamento (60..200 BPM) e a confiança (0..1); bpm 0 = não deu para estimar.
  Future<({double bpm, double confidence})> detectBpm(DecodedAudio a) => _native?.detectBpm(a) ?? Future.error(UnsupportedError(_noWarp));

  void calls(List<List<Object>> list) {
    log?.addAll(list);
    _native?.calls(list);
  }

  @override
  void Function(EngineState state)? onState;

  /// O motor caiu; só [restart] o traz de volta (ver engine_web.dart).
  @override
  void Function(String message)? onEngineFailed;

  /// Recria o motor, vazio (quem chama manda de novo os áudios e o documento); devolve a taxa.
  Future<double> restart() => _native?.restart() ?? Future.error(UnsupportedError(_noEngine));

  /// Loudness do master (LUFS/dBTP), ~20 vezes por segundo quando muda (ver engine_web.dart).
  void Function(LoudnessReading reading)? get onLoudness => _onLoudness;
  set onLoudness(void Function(LoudnessReading reading)? cb) {
    _onLoudness = cb;
    _native?.onLoudness = cb;
  }

  void Function(LoudnessReading reading)? _onLoudness;

  double get latency => _native?.latency ?? 0;

  /// Nos testes: guarda aqui as chamadas que iriam ao motor (null não guarda).
  @visibleForTesting
  List<List<Object>>? log;

  /// Mensagens MIDI de entrada (status, dado 1, dado 2).
  @override
  void Function(int status, int data1, int data2)? onMidi;

  /// Entradas MIDI conectadas, a cada aparelho que entra ou sai.
  @override
  void Function(List<String> inputs)? onMidiInputs;

  /// Liga o MIDI e devolve os nomes das entradas. Sem MIDI neste sistema: [UnsupportedError].
  Future<List<String>> enableMidi() =>
      _native?.enableMidi() ?? Future.error(UnsupportedError('O MIDI não funciona neste sistema: use o jopendaw no navegador ou no Android.'));

  // ------------------------------------------------------------------ gravação e render
  // Sem motor, abrir, capturar, renderizar e salvar falham com [UnsupportedError]; fechar e
  // cancelar (limpeza) não têm o que fazer e só voltam.

  /// Abre a entrada de áudio ([deviceId] null = padrão) e devolve a latência de entrada (s).
  Future<double> startInput(String? deviceId) => _native?.startInput(deviceId) ?? Future.error(UnsupportedError(_noRecording));

  Future<void> stopInput() => _native?.stopInput() ?? Future.value();

  /// Entradas de áudio (id, nome), a padrão sendo o id null.
  Future<List<(String, String)>> inputDevices() => _native?.inputDevices() ?? Future.error(UnsupportedError(_noRecording));

  /// Liga/desliga a captura (o fim chega em [onCaptureEnd]). Sem motor, desligar não tem o que
  /// fazer e ligar dá [UnsupportedError].
  void setCapture(bool on) {
    final native = _native;
    if (native != null) return native.setCapture(on);
    if (on) throw UnsupportedError(_noRecording);
  }

  @override
  void Function(Float32List left, Float32List right)? onRecord;

  @override
  void Function(double peak)? onInputLevel;

  /// Batida do transporte no primeiro quadro do bloco que [onRecord] está entregando.
  @override
  double recordBeat = 0;

  @override
  void Function(List<RecordedNote> notes)? onCaptureEnd;

  @override
  void Function(String message)? onInputLost;

  /// Renderiza fora de tempo real os canais de cada saída em [outputs] (−1 = master, i = faixa i,
  /// pós-fader), de [fromBeat] a [toBeat] mais [tailSeconds].
  Future<List<List<Float32List>>> renderOffline({
    required List<List<Object>> calls,
    required Map<int, DecodedAudio> samples,
    required double fromBeat,
    required double toBeat,
    required double tailSeconds,
    required List<int> outputs,
    required double rate,
    void Function(double progress)? onProgress,
  }) =>
      _native?.renderOffline(
        calls: calls,
        samples: samples,
        fromBeat: fromBeat,
        toBeat: toBeat,
        tailSeconds: tailSeconds,
        outputs: outputs,
        rate: rate,
        onProgress: onProgress,
      ) ??
      Future.error(UnsupportedError(_noRender));

  /// Interrompe os renders em andamento ([RenderCanceled]).
  void cancelRender() => _native?.cancelRender();

  /// sha-256 em hexa (a chave dos áudios no guardado local).
  Future<String> sha256Hex(Uint8List bytes) => _native?.sha256Hex(bytes) ?? Future.value(sha256.convert(bytes).toString());

  /// Oferece os bytes para salvar como arquivo. `false`: a pessoa cancelou (só o Android sabe dizer).
  Future<bool> saveFile(String name, Uint8List bytes, String mime) =>
      _native?.saveFile(name, bytes, mime) ??
      Future.error(UnsupportedError('Salvar arquivos não funciona neste sistema: use o jopendaw no navegador ou no Android.'));
}

/// Guardado local do DAW (documento e áudios): no Android, arquivos no diretório de documentos do
/// app; nos outros sistemas, nada fica guardado.
class LocalStore {
  LocalStore._();
  static final instance = LocalStore._();

  late final FileStore? _files = Platform.isAndroid ? FileStore(_androidDir) : null;

  static Future<Directory> _androidDir() async => Directory('${(await getApplicationDocumentsDirectory()).path}/jopendaw');

  Future<Object?> get(String key) async => _files?.get(key);

  Future<void> put(String key, Object value) async {
    await _files?.put(key, value);
  }

  Future<void> delete(String key) async {
    await _files?.delete(key);
  }

  /// As chaves guardadas que começam com [prefix].
  Future<List<String>> keys(String prefix) async => await _files?.keys(prefix) ?? const [];
}

/// Guardado chave → valor em arquivos de um diretório: textos (`.txt`, UTF-8) e bytes (`.bin`).
/// Cada gravação vai para um arquivo temporário e troca de nome no fim, então um app morto no meio
/// deixa o valor anterior inteiro; gravações da mesma chave vão uma de cada vez, na ordem.
class FileStore {
  FileStore(this._root);

  final Future<Directory> Function() _root;
  Future<Directory>? _dir;

  /// A última operação de cada chave (a próxima espera ela).
  final _pending = <String, Future<void>>{};

  Future<Directory> get _directory => _dir ??= _open().catchError((Object e) {
    // um erro de abrir (disco cheio, sem permissão) não fica gravado: a próxima tenta de novo
    _dir = null;
    throw e;
  });

  Future<Directory> _open() async {
    final d = await _root();
    await d.create(recursive: true);
    // temporários de uma gravação interrompida (o valor de verdade está no arquivo final)
    await for (final f in d.list()) {
      if (f is File && f.path.endsWith('.tmp')) {
        try {
          await f.delete();
        } on FileSystemException {
          // outro processo mexendo: fica para a próxima
        }
      }
    }
    return d;
  }

  /// Nome de arquivo (sem extensão) para [key]: letras minúsculas, dígitos, `_` e `-` ficam; todo
  /// o resto vira `%XX` (bytes UTF-8, hexa maiúsculo). Assim dois nomes nunca diferem só por
  /// maiúsculas (vale num sistema de arquivos que não as distingue) nem viram `.`/`..`. Chave que
  /// passaria de 200 caracteres vira `%h-` e o sha-256 dela; a vazia vira `%`.
  static String fileName(String key) {
    if (key.isEmpty) return '%';
    final b = StringBuffer();
    for (final c in utf8.encode(key)) {
      final safe = (c >= 0x61 && c <= 0x7A) || (c >= 0x30 && c <= 0x39) || c == 0x5F || c == 0x2D;
      if (safe) {
        b.writeCharCode(c);
      } else {
        b
          ..write('%')
          ..write(c.toRadixString(16).toUpperCase().padLeft(2, '0'));
      }
    }
    final name = b.toString();
    return name.length <= 200 ? name : '%h-${sha256.convert(utf8.encode(key))}';
  }

  Future<Object?> get(String key) async {
    await _settled(key);
    final base = '${(await _directory).path}/${fileName(key)}';
    try {
      return await File('$base.txt').readAsString();
    } on PathNotFoundException {
      // não é texto: talvez bytes
    }
    try {
      return await File('$base.bin').readAsBytes();
    } on PathNotFoundException {
      return null;
    }
  }

  Future<void> put(String key, Object value) {
    final (ext, other) = switch (value) {
      String() => ('txt', 'bin'),
      Uint8List() => ('bin', 'txt'),
      _ => throw ArgumentError('valor do guardado local: ${value.runtimeType}'),
    };
    return _serial(key, () async {
      final base = '${(await _directory).path}/${fileName(key)}';
      final tmp = File('$base.$ext.tmp');
      if (value is String) {
        await tmp.writeAsString(value, flush: true);
      } else {
        await tmp.writeAsBytes(value as Uint8List, flush: true);
      }
      await tmp.rename('$base.$ext');
      // a chave mudou de tipo: o valor antigo não pode voltar num get
      await _deleteIfExists(File('$base.$other'));
    });
  }

  Future<void> delete(String key) => _serial(key, () async {
    final base = '${(await _directory).path}/${fileName(key)}';
    await _deleteIfExists(File('$base.txt'));
    await _deleteIfExists(File('$base.bin'));
  });

  /// Inverso de [fileName]: a chave de um nome de arquivo (sem extensão); null se o nome não vem de
  /// uma chave que dê para recuperar (chave longa demais, que virou hash).
  static String? keyOfFileName(String name) {
    if (name == '%') return '';
    if (name.startsWith('%h-')) return null;
    final bytes = <int>[];
    for (var i = 0; i < name.length; i++) {
      if (name[i] == '%') {
        final v = i + 3 <= name.length ? int.tryParse(name.substring(i + 1, i + 3), radix: 16) : null;
        if (v == null) return null;
        bytes.add(v);
        i += 2;
      } else {
        bytes.add(name.codeUnitAt(i));
      }
    }
    try {
      return utf8.decode(bytes);
    } on FormatException {
      return null;
    }
  }

  /// As chaves guardadas que começam com [prefix] (as de nome longo demais, que viram hash, não
  /// entram: as de documento são curtas).
  Future<List<String>> keys(String prefix) async {
    final d = await _directory;
    final found = <String>{};
    await for (final f in d.list()) {
      if (f is! File) continue;
      final name = f.uri.pathSegments.last;
      if (!name.endsWith('.txt') && !name.endsWith('.bin')) continue;
      final key = keyOfFileName(name.substring(0, name.length - 4));
      if (key != null && key.startsWith(prefix)) found.add(key);
    }
    return found.toList();
  }

  static Future<void> _deleteIfExists(File f) async {
    try {
      await f.delete();
    } on PathNotFoundException {
      // já não estava lá
    }
  }

  /// Espera a operação em andamento da chave (sem herdar o erro dela).
  Future<void> _settled(String key) async {
    final p = _pending[key];
    if (p == null) return;
    try {
      await p;
    } on Object {
      // quem pediu a operação já recebeu o erro
    }
  }

  Future<void> _serial(String key, Future<void> Function() op) {
    final prev = _pending[key];
    final next = prev == null ? op() : _settled(key).then((_) => op());
    _pending[key] = next;
    // a lista de pendentes não guarda operação terminada (nem deixa o erro dela sem dono)
    next.then<void>((_) {}, onError: (Object _) {}).whenComplete(() {
      if (identical(_pending[key], next)) _pending.remove(key);
    });
    return next;
  }
}
