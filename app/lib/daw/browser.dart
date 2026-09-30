/// O navegador de áudios: a lista dos áudios do projeto e da conta, a pré-escuta e a inserção no arranjo ou numa
/// zona do sampler. Este arquivo é o modelo (sem widgets); o painel está em `browser_panel.dart`.
///
/// A pré-escuta é uma voz à parte no motor (`preview_play` / `preview_stop`, ver `engine/src/preview.rs`): não passa
/// pelo transporte, pelas faixas nem pelo documento, então não entra no desfazer nem no que sincroniza, e toca com o
/// projeto parado ou tocando. "No andamento do projeto" estica o áudio (o mesmo warp dos clipes) para o andamento do
/// projeto antes de tocar, a partir do andamento estimado do próprio áudio.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/client.dart';
import '../api/storage.dart';
import '../audio/engine_types.dart';
import '../widgets/feedback.dart';
import 'controller.dart';
import 'instruments.dart' show TrackKind;
import 'model.dart';
import 'sampler_zones_controller.dart';

/// Um áudio da lista: do projeto, da conta no servidor, ou dos dois.
class BrowserEntry {
  final String hash;
  final String name;

  /// Segundos; null quando nenhum lado sabe (áudio só da conta que nunca passou por este aparelho).
  final double? duration;

  /// Bytes; null quando só o projeto conhece o áudio (o servidor é quem guarda o tamanho).
  final int? size;

  /// Está no documento deste projeto.
  final bool inProject;

  /// Está na conta do servidor.
  final bool onServer;

  /// Está neste aparelho (decodificado pelo motor ou guardado no disco local). Falso: "fora deste aparelho".
  final bool onDevice;

  /// Os outros projetos que o usam (só a conta sabe).
  final List<String> projects;

  const BrowserEntry({
    required this.hash,
    required this.name,
    this.duration,
    this.size,
    this.inProject = false,
    this.onServer = false,
    this.onDevice = true,
    this.projects = const [],
  });
}

/// De onde a lista mostra áudios.
enum BrowserScope {
  all('Todos'),
  project('Projeto'),
  account('Conta');

  final String label;
  const BrowserScope(this.label);
}

const _accents = {
  'á': 'a',
  'à': 'a',
  'â': 'a',
  'ã': 'a',
  'ä': 'a',
  'é': 'e',
  'è': 'e',
  'ê': 'e',
  'ë': 'e',
  'í': 'i',
  'ì': 'i',
  'î': 'i',
  'ï': 'i', //
  'ó': 'o',
  'ò': 'o',
  'ô': 'o',
  'õ': 'o',
  'ö': 'o',
  'ú': 'u',
  'ù': 'u',
  'û': 'u',
  'ü': 'u',
  'ç': 'c',
  'ñ': 'n',
};

/// Minúsculas e sem acento: "Bumbo" acha "bumbô".
String foldText(String s) {
  final b = StringBuffer();
  for (final r in s.toLowerCase().runes) {
    final ch = String.fromCharCode(r);
    b.write(_accents[ch] ?? ch);
  }
  return b.toString();
}

/// Os áudios que [query] e [scope] deixam passar: todas as palavras da busca têm de aparecer no nome (em qualquer ordem).
/// Sem busca, a ordem é: os do projeto primeiro, depois por nome.
List<BrowserEntry> filterEntries(List<BrowserEntry> all, String query, BrowserScope scope) {
  final words = foldText(query).split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  final out = [
    for (final e in all)
      if ((scope == BrowserScope.all || (scope == BrowserScope.project ? e.inProject : e.onServer)) && _matches(foldText(e.name), words)) e,
  ];
  out.sort((a, b) {
    if (a.inProject != b.inProject) return a.inProject ? -1 : 1;
    final n = foldText(a.name).compareTo(foldText(b.name));
    return n != 0 ? n : a.hash.compareTo(b.hash);
  });
  return out;
}

bool _matches(String folded, List<String> words) => words.every(folded.contains);

/// Duração como a pessoa lê: "0,4 s", "7 s", "1:05", "12:03:09" não existe aqui (passa de 99 min vira "99:59+").
String fmtDuration(double seconds) {
  if (!seconds.isFinite || seconds < 0) return '0:00';
  if (seconds < 1) return '${seconds.toStringAsFixed(1).replaceAll('.', ',')} s';
  final total = seconds.round();
  if (total >= 6000) return '99:59+';
  return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
}

/// Em que passo a pré-escuta está.
enum PreviewPhase { idle, loading, playing }

/// Os ids de áudio que a pré-escuta usa no motor quando o áudio não é do projeto ou foi esticado: bem acima dos ids
/// sequenciais do controlador, para nunca bater com eles.
const previewIdBase = 0x40000000;

/// Ganho da pré-escuta (1 = o áudio como está; sem controle na tela de propósito: o volume do aparelho resolve).
const previewGain = 1.0;

/// O andamento que serve para esticar: confiança mínima da estimativa.
const _minTempoConfidence = 0.2;

class AudioBrowser extends ChangeNotifier {
  final DawController c;
  final Future<StorageUsage> Function() _loadUsage;
  final Future<Uint8List?> Function(String hash) _fetchBytes;

  /// Relógio da barra de progresso (troca nos testes).
  final Duration Function() _now;

  AudioBrowser(this.c, {Future<StorageUsage> Function()? loadUsage, Future<Uint8List?> Function(String hash)? fetchBytes, Duration Function()? now})
    : _loadUsage = loadUsage ?? (() => ApiClient.instance.storageUsage()),
      _fetchBytes = fetchBytes ?? ((h) => ApiClient.instance.getSample(h)),
      _now = now ?? _wallClock;

  static final _wall = Stopwatch()..start();
  static Duration _wallClock() => _wall.elapsed;

  static final _shared = Expando<AudioBrowser>();

  /// O navegador do controlador (um por projeto aberto; a pré-escuta e a busca sobrevivem a fechar e abrir o painel).
  static AudioBrowser of(DawController c) => _shared[c] ??= AudioBrowser(c);

  /// Nos testes: o modelo que o painel usa para o controlador [c] (com o servidor de mentira).
  @visibleForTesting
  static void use(DawController c, AudioBrowser b) => _shared[c] = b;

  // ------------------------------------------------------------------ lista

  StorageUsage? usage;
  String? usageError;
  bool loading = false;
  Set<String> _device = {};

  String query = '';
  BrowserScope scope = BrowserScope.all;

  /// Toca a pré-escuta esticada para o andamento do projeto (estimando o do áudio).
  bool atProjectTempo = false;

  /// Aviso inline do painel: o que a última ação fez, ou por que não deu.
  String? notice;
  bool noticeIsError = false;

  bool _disposed = false;

  void _say(String text, {bool error = false}) {
    notice = text;
    noticeIsError = error;
    _notify();
  }

  void clearNotice() {
    notice = null;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Relê a conta (o servidor) e o que está guardado neste aparelho. Sem conta (offline, sessão acabada) a lista segue só
  /// com os áudios do projeto e [usageError] diz o que houve.
  Future<void> refresh() async {
    loading = true;
    _notify();
    try {
      _device = {for (final k in await c.localStore.keys('sample:')) k.substring('sample:'.length)};
    } catch (_) {
      // sem ler o guardado, vale o que o motor já carregou
    }
    try {
      usage = await _loadUsage();
      usageError = null;
    } catch (e) {
      usageError = 'Não deu para ler os áudios da conta. ${describeError(e)}';
    }
    loading = false;
    _notify();
  }

  /// Todos os áudios conhecidos (projeto e conta), sem filtro.
  List<BrowserEntry> get entries {
    final server = {for (final s in usage?.samples ?? const <StoredSample>[]) s.hash: s};
    final out = <BrowserEntry>[];
    bool onDevice(String h) => c.decodedAudio(h) != null || (_device.contains(h) && !c.missing.contains(h));
    for (final MapEntry(key: hash, value: info) in c.doc.samples.entries) {
      final s = server.remove(hash);
      out.add(
        BrowserEntry(
          hash: hash,
          name: info.name.isNotEmpty ? info.name : (s?.name ?? _fallbackName(hash)),
          duration: info.duration > 0 ? info.duration : c.decodedAudio(hash)?.duration,
          size: s?.size,
          inProject: true,
          onServer: s != null,
          onDevice: onDevice(hash),
          projects: s?.projects ?? const [],
        ),
      );
    }
    for (final s in server.values) {
      out.add(
        BrowserEntry(
          hash: s.hash,
          name: s.name ?? _fallbackName(s.hash),
          size: s.size,
          onServer: true,
          onDevice: _device.contains(s.hash),
          projects: s.projects,
        ),
      );
    }
    return out;
  }

  static String _fallbackName(String hash) => 'Áudio ${hash.substring(0, hash.length < 8 ? hash.length : 8)}';

  /// A lista na tela: [entries] com a busca e a origem.
  List<BrowserEntry> get visible => filterEntries(entries, query, scope);

  void setQuery(String q) {
    query = q;
    _notify();
  }

  void setScope(BrowserScope s) {
    scope = s;
    _notify();
  }

  void setAtProjectTempo(bool on) {
    atProjectTempo = on;
    _notify();
  }

  // ------------------------------------------------------------------ bytes e download

  final _downloading = <String>{};

  /// Está baixando do servidor agora.
  bool isDownloading(String hash) => _downloading.contains(hash);

  Future<Uint8List?> _localBytes(String hash) async {
    final v = await c.localStore.get('sample:$hash');
    return v is Uint8List ? v : null;
  }

  /// Os bytes do áudio: do aparelho ou, se não há, do servidor (guardando no aparelho). Null se nenhum dos dois tem.
  Future<Uint8List?> _bytesOf(String hash) async {
    final local = await _localBytes(hash);
    if (local != null) return local;
    if (!_downloading.add(hash)) return null;
    _notify();
    try {
      final bytes = await _fetchBytes(hash);
      if (bytes == null) return null;
      await c.localStore.put('sample:$hash', bytes);
      _device.add(hash);
      return bytes;
    } finally {
      _downloading.remove(hash);
      _notify();
    }
  }

  /// Baixa o áudio do servidor para este aparelho; se é do projeto e estava faltando, registra no projeto (os clipes que o
  /// citam voltam a soar). Devolve se deu certo.
  Future<bool> download(BrowserEntry e) async {
    try {
      final bytes = await _bytesOf(e.hash);
      if (bytes == null) {
        _say('${e.name}: o servidor não tem este áudio e ele não está neste aparelho.', error: true);
        return false;
      }
      if (e.inProject && c.decodedAudio(e.hash) == null) await c.importSampleFile(e.name, bytes);
      _say('${e.name} agora está neste aparelho.');
      return true;
    } catch (err) {
      _say('Não deu para baixar ${e.name}. ${describeError(err)}', error: true);
      return false;
    }
  }

  // ------------------------------------------------------------------ pré-escuta

  PreviewPhase phase = PreviewPhase.idle;
  String? previewHash;

  /// Posição e duração do que toca, em segundos do áudio tocado (esticado, se for o caso).
  double previewPosition = 0, previewDuration = 0;

  /// Razão de esticar do que está tocando (1 = original) e o andamento estimado do áudio (null: não deu para estimar).
  double previewRatio = 1;
  final _tempos = <String, double?>{};

  Timer? _timer;
  int _token = 0;
  Duration _startedAt = Duration.zero;
  double _startOffset = 0;

  /// O que o motor guarda em nome da pré-escuta (chave → id): soltos quando o áudio seguinte entra.
  final _owned = <String, int>{};
  int _nextId = previewIdBase;
  DecodedAudio? _offProjectAudio;
  String? _offProjectHash;

  bool isPreviewing(String hash) => previewHash == hash && phase != PreviewPhase.idle;

  /// Toca; se este áudio já toca (ou carrega), para.
  Future<void> togglePreview(BrowserEntry e) async {
    if (isPreviewing(e.hash)) {
      stopPreview();
    } else {
      await playPreview(e);
    }
  }

  /// Toca [e] a partir de [fraction] (0..1) da duração. Áudio fora do aparelho é baixado antes.
  Future<void> playPreview(BrowserEntry e, {double fraction = 0}) async {
    final token = ++_token;
    _timer?.cancel();
    previewHash = e.hash;
    phase = PreviewPhase.loading;
    previewPosition = 0;
    previewDuration = e.duration ?? 0;
    previewRatio = 1;
    _notify();
    try {
      // o navegador segura o áudio até um gesto: o toque que chegou aqui vale
      unawaited(c.engine.resume().catchError((Object _) {}));
      final audio = await _audioOf(e);
      if (token != _token) return;
      if (audio == null) {
        _end(token);
        _say('${e.name}: o servidor não tem este áudio e ele não está neste aparelho.', error: true);
        return;
      }
      var id = c.sampleEngineId(e.hash);
      var ratio = 1.0;
      var shown = audio;
      if (atProjectTempo) {
        final bpm = await _tempoOf(e.hash, audio);
        if (token != _token) return;
        if (bpm == null) {
          _say('Não deu para estimar o andamento de ${e.name}; toquei no original.');
        } else {
          ratio = ((bpm / c.doc.bpm).clamp(0.25, 4.0) * 10000).round() / 10000;
        }
      }
      if (ratio != 1) {
        shown = await c.engine.stretch(audio, ratio: ratio);
        if (token != _token) return;
        id = _load('${e.hash}|$ratio', shown);
      } else {
        id ??= _load(e.hash, audio);
      }
      _dropUnused({id});
      previewRatio = ratio;
      previewDuration = shown.duration;
      _startOffset = (previewDuration * fraction.clamp(0.0, 1.0)).toDouble();
      previewPosition = _startOffset;
      c.engine.calls([
        ['preview_play', id, _startOffset, previewGain],
      ]);
      _startedAt = _now();
      phase = PreviewPhase.playing;
      _timer = Timer.periodic(const Duration(milliseconds: 50), (_) => tick());
      _notify();
    } catch (err) {
      if (token != _token) return;
      _end(token);
      _say(
        'Não deu para tocar ${e.name}. ${err is ApiException || err is TimeoutException ? describeError(err) : 'É um formato que este aparelho decodifica?'}',
        error: true,
      );
    }
  }

  /// Anda a barra de progresso; ao chegar ao fim do áudio a pré-escuta termina sozinha (a voz do motor também).
  @visibleForTesting
  void tick() {
    if (phase != PreviewPhase.playing) return;
    previewPosition = _startOffset + (_now() - _startedAt).inMicroseconds / 1e6;
    if (previewPosition >= previewDuration) {
      _end(_token);
      return;
    }
    _notify();
  }

  /// Para a pré-escuta (o motor faz um fade curto).
  void stopPreview() {
    if (phase == PreviewPhase.idle) return;
    _token++;
    c.engine.calls([
      ['preview_stop'],
    ]);
    _end(_token);
  }

  void _end(int token) {
    if (token != _token) return;
    _timer?.cancel();
    _timer = null;
    phase = PreviewPhase.idle;
    previewPosition = 0;
    _notify();
  }

  /// O áudio decodificado: o do projeto, o que já está guardado neste aparelho ou baixado agora.
  Future<DecodedAudio?> _audioOf(BrowserEntry e) async {
    final inProject = c.decodedAudio(e.hash);
    if (inProject != null) return inProject;
    if (_offProjectHash == e.hash) return _offProjectAudio;
    final bytes = await _bytesOf(e.hash);
    if (bytes == null) return null;
    final audio = await c.engine.decode(bytes);
    _offProjectHash = e.hash;
    _offProjectAudio = audio;
    return audio;
  }

  Future<double?> _tempoOf(String hash, DecodedAudio audio) async {
    if (_tempos.containsKey(hash)) return _tempos[hash];
    final r = await c.engine.detectBpm(audio);
    return _tempos[hash] = r.bpm > 0 && r.confidence >= _minTempoConfidence ? r.bpm : null;
  }

  int _load(String key, DecodedAudio audio) {
    final existing = _owned[key];
    if (existing != null) return existing;
    final id = _nextId++;
    c.engine.loadSample(id, audio);
    _owned[key] = id;
    return id;
  }

  /// Solta do motor o que a pré-escuta carregou e não é mais o que toca.
  void _dropUnused(Set<int> keep) {
    final drop = [
      for (final MapEntry(:key, :value) in _owned.entries)
        if (!keep.contains(value)) (key, value),
    ];
    if (drop.isEmpty) return;
    c.engine.calls([
      for (final (_, id) in drop) ['sample_drop', id],
    ]);
    for (final (key, _) in drop) {
      _owned.remove(key);
    }
  }

  // ------------------------------------------------------------------ inserir

  bool _isSampler(int track) => track >= 0 && track < c.doc.tracks.length && c.doc.tracks[track].kind == TrackKind.sampler;

  /// A faixa selecionada, se existe.
  DawTrack? get selectedTrack => c.selectedTrack >= 0 && c.selectedTrack < c.doc.tracks.length ? c.doc.tracks[c.selectedTrack] : null;

  /// "Inserir na faixa selecionada, no cursor": uma faixa de áudio recebe o clipe no cursor (vazia no ponto; senão uma
  /// faixa nova); um sampler recebe uma zona; qualquer outra faixa (ou nenhuma) faz o clipe ir para uma faixa nova.
  Future<bool> insertAtCursor(BrowserEntry e) async {
    final t = c.selectedTrack;
    if (_isSampler(t)) return addAsZone(e, t);
    return _place(e, at: null, track: null);
  }

  /// Soltar na linha da faixa [track] (null: abaixo das faixas, vira faixa nova) no ponto [beat] da régua.
  Future<bool> dropOnTimeline(BrowserEntry e, {required double beat, int? track}) {
    if (track != null && _isSampler(track)) return addAsZone(e, track);
    return _place(e, at: c.snapBeat(beat < 0 ? 0 : beat), track: track ?? c.doc.tracks.length);
  }

  Future<bool> _place(BrowserEntry e, {required double? at, required int? track}) async {
    try {
      final bytes = await _bytesOf(e.hash);
      if (bytes == null) {
        _say('${e.name}: o servidor não tem este áudio e ele não está neste aparelho.', error: true);
        return false;
      }
      final before = c.error;
      await c.importBytes([(e.name, bytes)], at: at, track: track);
      if (c.error != null && c.error != before) return false;
      _say('${e.name} entrou no arranjo.');
      return true;
    } catch (err) {
      _say('Não deu para inserir ${e.name}. ${describeError(err)}', error: true);
      return false;
    }
  }

  /// Faz de [e] uma zona do sampler da faixa [track].
  Future<bool> addAsZone(BrowserEntry e, int track) async {
    if (!_isSampler(track)) {
      _say('Escolha uma faixa de sampler para criar a zona.', error: true);
      return false;
    }
    try {
      final bytes = await _bytesOf(e.hash);
      if (bytes == null) {
        _say('${e.name}: o servidor não tem este áudio e ele não está neste aparelho.', error: true);
        return false;
      }
      final hash = await c.importSampleFile(e.name, bytes);
      if (hash == null) {
        _say('Não deu para abrir ${e.name}.', error: true);
        return false;
      }
      final trackName = c.doc.tracks[track].name;
      String? blocked;
      final z = c.addZone(track, hash, onNotice: (n) => blocked = n);
      if (z == null) {
        _say(blocked ?? 'Não deu para criar a zona.', error: true);
        return false;
      }
      _say('${e.name} virou uma zona do sampler "$trackName". ${blocked ?? ''}'.trim());
      return true;
    } catch (err) {
      _say('Não deu para criar a zona. ${describeError(err)}', error: true);
      return false;
    }
  }

  /// O painel fechou: para a pré-escuta e devolve ao motor a memória do que ela carregou.
  void release() {
    stopPreview();
    _dropUnused(const {});
    _offProjectAudio = null;
    _offProjectHash = null;
  }

  @override
  void dispose() {
    release();
    _disposed = true;
    super.dispose();
  }
}
