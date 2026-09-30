/// Warp de clipes de áudio: os sons derivados (esticados, transpostos, invertidos) e o cache deles.
///
/// O documento guarda só os parâmetros (`AudioClip.warp/sourceBpm/pitch/reverse`); o som derivado
/// é gerado aqui, de forma assíncrona e fora da thread de áudio ([AudioEngine.stretch]), guardado
/// no [LocalStore] sob `warp:<chave>` e carregado no motor como um sample interno. Ele nunca entra
/// em `doc.samples`, nem no sha-256 nem no que vai ao servidor: em outro aparelho o cache se
/// refaz a partir do original. Enquanto o derivado não fica pronto, o clipe toca o original.
library;

import 'dart:async';
import 'dart:typed_data';

import '../audio/engine.dart';
import 'export_options.dart';
import 'model.dart';
import 'wav.dart';

/// O que um clipe pede: de qual áudio, esticado por quanto, transposto quanto e se invertido.
class WarpSpec {
  /// sha-256 do áudio de origem.
  final String sample;

  /// Duração do derivado / duração da origem (0,25..4), arredondada a 4 casas: o andamento
  /// mudando de um tico não refaz o som.
  final double ratio;

  /// Semitons, arredondados a 2 casas.
  final double semitones;
  final bool reverse;

  const WarpSpec(this.sample, this.ratio, this.semitones, this.reverse);

  /// A especificação do clipe no andamento do projeto; null quando ele toca o original como é.
  static WarpSpec? of(AudioClip c, double projectBpm) {
    if (!c.processed) return null;
    var ratio = 1.0;
    if (c.stretches && projectBpm > 0) ratio = (c.sourceBpm! / projectBpm).clamp(0.25, 4.0);
    ratio = (ratio * 10000).round() / 10000;
    final semitones = (c.pitch.clamp(-24.0, 24.0) * 100).round() / 100;
    if (ratio == 1 && semitones == 0 && !c.reverse) return null;
    return WarpSpec(c.sample, ratio, semitones, c.reverse);
  }

  /// A chave do cache: a origem e os parâmetros já arredondados.
  String get key => '$sample|r${ratio.toStringAsFixed(4)}|p${semitones.toStringAsFixed(2)}|${reverse ? 'rev' : 'fwd'}';

  /// Precisa do processamento pesado (esticar ou transpor); só inverter é uma cópia.
  bool get needsStretch => ratio != 1 || semitones != 0;

  @override
  bool operator ==(Object other) => other is WarpSpec && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

/// Uma cópia do áudio de trás para a frente.
DecodedAudio reversedAudio(DecodedAudio a) => DecodedAudio([for (final c in a.channels) Float32List.fromList(c.reversed.toList())], a.rate);

/// Gera, guarda e lembra os sons derivados de um projeto.
class WarpCache {
  WarpCache({
    required this.engine,
    required this.store,
    required this.source,
    required this.register,
    required this.drop,
    required this.onChange,
    this.debounce = const Duration(milliseconds: 400),
  });

  final AudioEngine engine;
  final LocalStore store;

  /// O áudio decodificado de um sample do projeto (pelo sha-256).
  final DecodedAudio? Function(String sample) source;

  /// Carrega o derivado no motor e devolve o id dele.
  final int Function(String key, DecodedAudio audio) register;
  final void Function(String key, int id) drop;
  final void Function() onChange;

  /// Espera depois da última mudança de parâmetro antes de processar (arrastar o andamento pede
  /// dezenas de valores, e só o último interessa).
  final Duration debounce;

  final _ready = <String, int>{};
  final _pending = <String, Future<void>>{};
  final _failed = <String, String>{};
  var _wanted = <String, WarpSpec>{};
  Timer? _timer;
  bool _disposed = false;

  /// O id do derivado no motor, se já está pronto.
  int? idOf(WarpSpec spec) => _ready[spec.key];

  /// Ainda sendo gerado (ou esperando o debounce).
  bool isPending(WarpSpec spec) =>
      !_ready.containsKey(spec.key) && !_failed.containsKey(spec.key) && (_pending.containsKey(spec.key) || _wanted.containsKey(spec.key));

  /// Por que não deu para gerar, se falhou (o clipe toca o original).
  String? failure(WarpSpec spec) => _failed[spec.key];

  bool get busy => _pending.isNotEmpty || _timer != null;

  /// Declara o que os clipes pedem agora (chamado a cada envio do documento ao motor). O que já
  /// está pronto não faz nada; o que falta começa depois do [debounce].
  void want(Iterable<WarpSpec> specs) {
    final next = {for (final s in specs) s.key: s};
    final changed = next.length != _wanted.length || next.keys.any((k) => !_wanted.containsKey(k));
    _wanted = next;
    if (changed) _evict();
    if (_missing().isNotEmpty) {
      if (changed || _timer == null) {
        _timer?.cancel();
        _timer = Timer(debounce, _start);
      }
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  List<WarpSpec> _missing() => [
    for (final s in _wanted.values)
      if (!_ready.containsKey(s.key) && !_pending.containsKey(s.key) && !_failed.containsKey(s.key)) s,
  ];

  void _start() {
    _timer = null;
    if (_disposed) return;
    for (final s in _missing()) {
      _pending[s.key] = _run(s);
    }
    onChange();
  }

  /// Termina tudo o que o documento pede agora, sem esperar o debounce (exportar e congelar
  /// precisam do som final).
  Future<void> settle() async {
    if (_timer != null) {
      _timer!.cancel();
      _start();
    }
    while (_pending.isNotEmpty) {
      await Future.wait(_pending.values.toList());
      if (_missing().isNotEmpty) _start();
    }
  }

  Future<void> _run(WarpSpec spec) async {
    final key = spec.key;
    try {
      DecodedAudio? out;
      final stored = await store.get('warp:$key');
      if (stored is Uint8List) {
        try {
          out = await engine.decode(stored);
        } catch (_) {
          // cache ilegível: refaz
        }
      }
      if (out == null) {
        final src = source(spec.sample);
        if (src == null) throw StateError('O áudio original não está neste aparelho.');
        var a = spec.needsStretch ? await engine.stretch(src, ratio: spec.ratio, semitones: spec.semitones) : src;
        if (spec.reverse) a = reversedAudio(a);
        out = a;
        try {
          await store.put('warp:$key', encodeWav(a.channels, a.rate.round(), ExportFormat.wav32f));
        } catch (_) {
          // sem guardar, o som vale nesta sessão e se refaz na próxima
        }
      }
      if (_disposed) return;
      _ready[key] = register(key, out);
    } catch (e) {
      _failed[key] = e is StateError ? e.message : (e is UnsupportedError ? (e.message ?? '$e') : '$e');
    } finally {
      _pending.remove(key);
      if (!_disposed) {
        _evict();
        onChange();
      }
    }
  }

  /// Solta do motor o que nenhum clipe pede mais (o cache em disco fica).
  void _evict() {
    for (final k in _ready.keys.toList()) {
      if (_wanted.containsKey(k)) continue;
      drop(k, _ready.remove(k)!);
    }
    _failed.removeWhere((k, _) => !_wanted.containsKey(k));
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }
}
