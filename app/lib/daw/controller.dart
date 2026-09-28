/// O cérebro da tela do projeto: guarda o documento, o histórico de desfazer, a seleção e a visão
/// (zoom e rolagem), e mantém o motor de áudio e o guardado local em dia com cada edição.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../api/client.dart';
import '../audio/engine.dart';
import '../models/project.dart';
import '../widgets/theme.dart';
import 'model.dart';

/// Resumo de um áudio para desenhar a onda: mínimo e máximo a cada [bucket] quadros.
class Waveform {
  static const bucket = 256;
  final Float32List mins, maxs;
  final double rate;
  Waveform(this.mins, this.maxs, this.rate);

  factory Waveform.of(DecodedAudio a) {
    final n = (a.frames / bucket).ceil();
    final mins = Float32List(n), maxs = Float32List(n);
    final chs = a.channels;
    for (var b = 0; b < n; b++) {
      var lo = 0.0, hi = 0.0;
      final end = math.min((b + 1) * bucket, a.frames);
      for (final c in chs) {
        for (var i = b * bucket; i < end; i++) {
          final s = c[i];
          if (s < lo) lo = s;
          if (s > hi) hi = s;
        }
      }
      mins[b] = lo;
      maxs[b] = hi;
    }
    return Waveform(mins, maxs, a.rate);
  }

  /// Buckets por segundo.
  double get perSecond => rate / bucket;
}

/// Grade de encaixe, em batidas (0 = livre).
enum Snap {
  off('Livre', 0),
  bar('Compasso', -1),
  beat('1/4', 1),
  half('1/8', .5),
  quarter('1/16', .25);

  final String label;
  final double beats;
  const Snap(this.label, this.beats);
}

class DawController extends ChangeNotifier {
  final Project project;
  DawController(this.project);

  final _engine = AudioEngine.instance;
  final _store = LocalStore.instance;

  late DawDoc doc;
  bool ready = false;
  String? error;

  /// Mensagem de trabalho em andamento (importação), na barra do transporte.
  String? status;

  // estado ao vivo do motor: notifiers próprios para não redesenhar a tela inteira a 60 Hz
  final beat = ValueNotifier<double>(0);
  final playing = ValueNotifier<bool>(false);
  final peaks = ValueNotifier<Float32List>(Float32List(0));

  final waveforms = <String, Waveform>{};
  final _sampleIds = <String, int>{};

  /// Áudios citados no documento que não estão neste aparelho.
  final missing = <String>{};

  String? selectedClip;
  int selectedTrack = 0;
  Snap snap = Snap.beat;

  /// Zoom (pixels por batida) e o começo da janela visível, em batidas.
  double pxPerBeat = 48;
  double scrollBeat = 0;
  bool follow = true;

  /// Largura visível das raias em pixels (a linha do tempo informa a cada layout).
  double viewWidth = 800;
  bool mixerOpen = false;

  final _undo = <String>[];
  final _redo = <String>[];
  Timer? _saveTimer;

  String get _docKey => 'doc:${project.id}';

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  // ------------------------------------------------------------------ abrir

  Future<void> open() async {
    try {
      if (!_engine.supported) throw UnsupportedError('O motor de áudio ainda não roda neste aparelho: use o jopendaw no navegador por enquanto.');
      await _engine.start();
      _engine.onState = (s) {
        beat.value = s.beat;
        playing.value = s.playing;
        peaks.value = s.peaks;
        _follow(s);
      };
      final saved = await _store.get(_docKey);
      doc = saved is String ? DawDoc.fromJson(jsonDecode(saved)) : _fresh();
      // o andamento e a fórmula de compasso moram no servidor; o local segue
      doc.bpm = project.bpm.toDouble();
      doc.beatsPerBar = project.beatsPerBar;
      for (final hash in doc.samples.keys.toList()) {
        await _loadSample(hash);
      }
      ready = true;
      _sync();
    } catch (e) {
      error = e is UnsupportedError ? e.message : '$e';
    }
    notifyListeners();
  }

  /// Tocando, a janela acompanha o cursor quando ele sai dela.
  void _follow(EngineState s) {
    if (!follow || !s.playing) return;
    final visible = viewWidth / pxPerBeat;
    if (s.beat > scrollBeat + visible * 0.92 || s.beat < scrollBeat) {
      scrollBeat = math.max(0, s.beat - visible * 0.05);
      notifyListeners();
    }
  }

  DawDoc _fresh() => DawDoc(
    bpm: project.bpm.toDouble(),
    beatsPerBar: project.beatsPerBar,
    tracks: [DawTrack(id: newId(), name: 'Áudio 1', color: 0)],
    loopEnd: project.beatsPerBar * 4.0,
  );

  Future<void> _loadSample(String hash) async {
    final bytes = await _store.get('sample:$hash');
    if (bytes is! Uint8List) {
      missing.add(hash);
      return;
    }
    final audio = await _engine.decode(bytes);
    _register(hash, audio);
  }

  void _register(String hash, DecodedAudio audio) {
    final id = _sampleIds[hash] ??= _sampleIds.length + 1;
    _engine.loadSample(id, audio);
    waveforms[hash] = Waveform.of(audio);
    missing.remove(hash);
  }

  @override
  void dispose() {
    _engine.calls([
      ['stop'],
    ]);
    _engine.onState = null;
    _saveTimer?.cancel();
    _save();
    beat.dispose();
    playing.dispose();
    peaks.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------ motor

  /// Manda o documento inteiro ao motor. É barato: são dezenas de chamadas numa mensagem.
  void _sync() {
    final d = doc;
    final calls = <List<Object>>[
      ['tempo', d.bpm, d.beatsPerBar],
      ['tracks', d.tracks.length],
      ['master', d.masterGain, d.masterPan],
      ['loop_set', d.loopOn, d.loopStart, d.loopEnd],
      ['metronome', d.metronome, 0.5],
      ['clips_clear'],
    ];
    for (var i = 0; i < d.tracks.length; i++) {
      final t = d.tracks[i];
      calls.add(['track', i, t.gain, t.pan, t.mute, t.solo]);
      for (final c in t.clips) {
        final id = _sampleIds[c.sample];
        if (id == null) continue;
        calls.add(['clip_add', i, id, c.start, c.offset, c.length, c.gain, c.fadeIn, c.fadeOut]);
      }
    }
    _engine.calls(calls);
  }

  // ------------------------------------------------------------------ transporte

  Future<void> togglePlay() async {
    await _engine.resume();
    _engine.calls([
      [playing.value ? 'stop' : 'play'],
    ]);
    playing.value = !playing.value;
  }

  /// Para e volta ao começo (ou ao início do loop, se ligado).
  Future<void> stop() async {
    final to = playing.value ? (doc.loopOn ? doc.loopStart : 0.0) : 0.0;
    _engine.calls([
      ['stop'],
      ['seek', to],
    ]);
    playing.value = false;
    beat.value = to;
    scrollBeat = math.max(0, to - 2);
    notifyListeners();
  }

  void seek(double b) {
    b = math.max(0, b);
    _engine.calls([
      ['seek', b],
    ]);
    beat.value = b;
  }

  void toggleLoop() => edit((d) => d.loopOn = !d.loopOn, undoable: false);
  void toggleMetronome() => edit((d) => d.metronome = !d.metronome, undoable: false);

  void setLoop(double start, double end) => mutate((d) {
    d.loopStart = math.max(0, math.min(start, end));
    d.loopEnd = math.max(start, end);
    d.loopOn = d.loopEnd - d.loopStart > 0.01;
  });

  Future<void> setTempo(int bpm, int beatsPerBar) async {
    edit((d) {
      d.bpm = bpm.toDouble();
      d.beatsPerBar = beatsPerBar;
    });
    await ApiClient.instance.patchProject(project.id, {'bpm': bpm, 'beats_per_bar': beatsPerBar});
  }

  // ------------------------------------------------------------------ edição

  /// Uma edição desfazível: guarda o estado de antes, aplica, manda ao motor e salva.
  void edit(void Function(DawDoc d) fn, {bool undoable = true}) {
    if (undoable) checkpoint();
    mutate(fn);
  }

  /// Guarda o estado atual no histórico (início de um arraste, que depois só faz [mutate]).
  void checkpoint() {
    _undo.add(jsonEncode(doc.toJson()));
    if (_undo.length > 200) _undo.removeAt(0);
    _redo.clear();
  }

  /// Muda sem entrar no histórico (os passos de um arraste).
  void mutate(void Function(DawDoc d) fn) {
    fn(doc);
    _sync();
    _scheduleSave();
    notifyListeners();
  }

  void undo() => _travel(_undo, _redo);
  void redo() => _travel(_redo, _undo);

  void _travel(List<String> from, List<String> to) {
    if (from.isEmpty) return;
    to.add(jsonEncode(doc.toJson()));
    doc = DawDoc.fromJson(jsonDecode(from.removeLast()));
    if (selectedTrack >= doc.tracks.length) selectedTrack = math.max(0, doc.tracks.length - 1);
    if (selectedClip != null && _findClip(selectedClip!) == null) selectedClip = null;
    _sync();
    _scheduleSave();
    notifyListeners();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), _save);
  }

  Future<void> _save() async {
    if (!ready) return;
    await _store.put(_docKey, jsonEncode(doc.toJson()));
  }

  /// Encaixa na grade atual.
  double snapBeat(double b) {
    final g = snap == Snap.bar ? doc.beatsPerBar.toDouble() : snap.beats;
    if (g <= 0) return b;
    return (b / g).round() * g;
  }

  // ------------------------------------------------------------------ faixas

  void addTrack() => edit((d) {
    final n = d.tracks.length;
    d.tracks.add(DawTrack(id: newId(), name: 'Áudio ${n + 1}', color: n % Palette.tracks.length));
    selectedTrack = n;
  });

  void removeTrack(int i) => edit((d) {
    d.tracks.removeAt(i);
    selectedTrack = math.max(0, math.min(selectedTrack, d.tracks.length - 1));
  });

  void selectTrack(int i) {
    selectedTrack = i;
    notifyListeners();
  }

  // ------------------------------------------------------------------ clipes

  (DawTrack, AudioClip)? _findClip(String id) {
    for (final t in doc.tracks) {
      for (final c in t.clips) {
        if (c.id == id) return (t, c);
      }
    }
    return null;
  }

  (DawTrack, AudioClip)? get selection => selectedClip == null ? null : _findClip(selectedClip!);

  void selectClip(String? id) {
    selectedClip = id;
    if (id != null) {
      final f = _findClip(id);
      if (f != null) selectedTrack = doc.tracks.indexOf(f.$1);
    }
    notifyListeners();
  }

  /// Move um clipe para outra faixa (arraste vertical).
  void moveClipToTrack(String id, int track) {
    final f = _findClip(id);
    if (f == null || track < 0 || track >= doc.tracks.length) return;
    final (from, clip) = f;
    final to = doc.tracks[track];
    if (identical(from, to)) return;
    mutate((_) {
      from.clips.remove(clip);
      to.clips.add(clip);
      selectedTrack = track;
    });
  }

  void deleteSelected() {
    final f = selection;
    if (f == null) return;
    edit((_) => f.$1.clips.remove(f.$2));
    selectedClip = null;
  }

  void duplicateSelected() {
    final f = selection;
    if (f == null) return;
    final (t, c) = f;
    final copy = AudioClip.fromJson(c.toJson())
      ..id = newId()
      ..start = c.end(doc.bpm);
    edit((_) => t.clips.add(copy));
    selectedClip = copy.id;
  }

  /// Corta no cursor de reprodução: o clipe selecionado, ou tudo o que ele cruza na faixa atual.
  void splitAtPlayhead() {
    final at = beat.value;
    final targets = <(DawTrack, AudioClip)>[];
    final sel = selection;
    if (sel != null) {
      targets.add(sel);
    } else if (selectedTrack < doc.tracks.length) {
      final t = doc.tracks[selectedTrack];
      targets.addAll(t.clips.map((c) => (t, c)));
    }
    final cuts = targets.where((f) => f.$2.start < at && f.$2.end(doc.bpm) > at).toList();
    if (cuts.isEmpty) return;
    edit((d) {
      for (final (t, c) in cuts) {
        final secs = (at - c.start) * 60 / d.bpm;
        final right = AudioClip.fromJson(c.toJson())
          ..id = newId()
          ..start = at
          ..offset = c.offset + secs
          ..length = c.length - secs
          ..fadeIn = 0;
        c
          ..length = secs
          ..fadeOut = 0;
        t.clips.add(right);
      }
    });
  }

  // ------------------------------------------------------------------ importar

  static const audioExtensions = ['wav', 'mp3', 'ogg', 'oga', 'flac', 'm4a', 'aac', 'opus', 'webm', 'aif', 'aiff'];

  /// Escolhe arquivos de áudio e põe cada um numa faixa, a partir do cursor.
  Future<void> importAudio() async {
    final files = await FilePicker.pickFiles(dialogTitle: 'Importar áudio', type: FileType.custom, allowedExtensions: audioExtensions);
    if (files.isEmpty) return;
    final list = <(String, Uint8List)>[];
    for (final f in files) {
      list.add((f.name, await f.readAsBytes()));
    }
    await importBytes(list);
  }

  /// Importa áudios já lidos: o primeiro vai na faixa selecionada (se vazia no ponto), os
  /// outros em faixas novas logo abaixo.
  Future<void> importBytes(List<(String, Uint8List)> files, {double? at, int? track}) async {
    final start = at ?? snapBeat(beat.value);
    var ti = track ?? selectedTrack;
    checkpoint();
    for (var i = 0; i < files.length; i++) {
      final (name, bytes) = files[i];
      status = 'Importando $name…';
      notifyListeners();
      try {
        final hash = sha256.convert(bytes).toString();
        if (!waveforms.containsKey(hash)) {
          final audio = await _engine.decode(bytes);
          await _store.put('sample:$hash', bytes);
          _register(hash, audio);
          doc.samples[hash] = SampleInfo(name, audio.duration);
        }
        final info = doc.samples[hash] ??= SampleInfo(name, 0);
        if (ti >= doc.tracks.length || (i > 0 || _occupied(doc.tracks[ti], start, start + info.duration * doc.bpm / 60))) {
          ti = doc.tracks.length;
          doc.tracks.add(DawTrack(id: newId(), name: _baseName(name), color: ti % Palette.tracks.length));
        }
        final clip = AudioClip(id: newId(), sample: hash, start: start, length: info.duration);
        doc.tracks[ti].clips.add(clip);
        selectedClip = clip.id;
        selectedTrack = ti;
      } catch (e) {
        error = 'Não deu para abrir $name: é um formato de áudio que este navegador decodifica?';
      }
    }
    status = null;
    _sync();
    _scheduleSave();
    notifyListeners();
  }

  bool _occupied(DawTrack t, double from, double to) => t.clips.any((c) => c.start < to && c.end(doc.bpm) > from);

  static String _baseName(String file) {
    final dot = file.lastIndexOf('.');
    final n = dot > 0 ? file.substring(0, dot) : file;
    return n.length > 40 ? n.substring(0, 40) : n;
  }

  void clearError() {
    error = null;
    notifyListeners();
  }

  // ------------------------------------------------------------------ visão

  void zoom(double factor, {double? anchorBeat}) {
    final anchor = anchorBeat ?? beat.value;
    final before = (anchor - scrollBeat) * pxPerBeat;
    pxPerBeat = (pxPerBeat * factor).clamp(4.0, 800.0);
    scrollBeat = math.max(0, anchor - before / pxPerBeat);
    notifyListeners();
  }

  void scrollBy(double px) {
    scrollBeat = math.max(0, scrollBeat + px / pxPerBeat);
    notifyListeners();
  }

  void setSnap(Snap s) {
    snap = s;
    notifyListeners();
  }

  void toggleMixer() {
    mixerOpen = !mixerOpen;
    notifyListeners();
  }
}
