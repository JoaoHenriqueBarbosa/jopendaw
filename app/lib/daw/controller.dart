/// O cérebro da tela do projeto: guarda o documento, o histórico de desfazer, a seleção e a visão
/// (zoom e rolagem), e mantém o motor de áudio e o guardado local em dia com cada edição.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show EditableText, FocusManager;

import '../api/client.dart';
import '../audio/engine.dart';
import '../models/project.dart';
import '../widgets/theme.dart';
import 'instruments.dart';
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

/// O que ocupa o painel de baixo.
enum Dock { none, mixer, editor, instrument }

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

// ------------------------------------------------------------------ notas (funções puras)

/// Uma nota pronta para o motor: faixa, início absoluto e duração em batidas.
typedef EngineNote = ({int track, double start, double length, int pitch, double velocity});

/// Menor pedaço de nota que ainda vale tocar: sobra de corte em ponto flutuante não vira clique.
const _minNoteBeats = 1e-6;

/// Achata os clipes MIDI das faixas de instrumento em notas na linha do tempo, em ordem de início.
///
/// Cada nota é cortada ao trecho do clipe ([0, duração]): o que foi aparado fica guardado no
/// clipe, mas não toca; nota totalmente fora não vai.
List<EngineNote> flattenNotes(List<DawTrack> tracks) {
  final out = <EngineNote>[];
  for (var i = 0; i < tracks.length; i++) {
    final t = tracks[i];
    if (!t.kind.isInstrument) continue;
    for (final c in t.midi) {
      for (final n in c.notes) {
        if (n.pitch < 0 || n.pitch > 127) continue;
        final from = math.max(n.start, 0.0);
        final to = math.min(n.end, c.length);
        if (to - from < _minNoteBeats) continue;
        out.add((track: i, start: c.start + from, length: to - from, pitch: n.pitch, velocity: n.velocity.clamp(0.0, 1.0).toDouble()));
      }
    }
  }
  out.sort((a, b) {
    final s = a.start.compareTo(b.start);
    if (s != 0) return s;
    final t = a.track.compareTo(b.track);
    return t != 0 ? t : a.pitch.compareTo(b.pitch);
  });
  return out;
}

/// Quantiza notas na grade [grid] (batidas) da linha do tempo, com o clipe começando em [offset]:
/// assim as notas caem na grade da música mesmo num clipe fora dela. [strength] 0..1 é quanto do
/// caminho até a linha da grade cada nota anda; com [ends], o fim também vai para a grade. A
/// duração nunca fica abaixo de um quarto da grade (nem zero).
void quantizeNoteList(Iterable<MidiNote> notes, double grid, {double offset = 0, double strength = 1, bool ends = false}) {
  if (!(grid > 0)) return;
  final s = strength.clamp(0.0, 1.0).toDouble();
  if (s == 0) return;
  final minLength = grid / 4;
  double toward(double from, double to) => s == 1 ? to : from + (to - from) * s;
  for (final n in notes) {
    final start = offset + n.start;
    final gridStart = (start / grid).round() * grid;
    final newStart = toward(start, gridStart);
    var length = n.length;
    if (ends) {
      final end = start + n.length;
      var gridEnd = (end / grid).round() * grid;
      // nota menor que meia grade encolheria até sumir: ocupa uma grade inteira
      if (gridEnd <= gridStart) gridEnd = gridStart + grid;
      length = math.max(toward(end, gridEnd) - newStart, minLength);
    } else if (!(length > 0)) {
      length = minLength;
    }
    n
      ..start = newStart - offset
      ..length = length;
  }
}

/// Corta um clipe MIDI em [at] (batida da linha do tempo). O clipe fica com a parte da esquerda;
/// a da direita volta como clipe novo, com as notas que começam depois do corte (e o início
/// rebaixado). Nota que cruza o corte vira duas. Null se [at] não cai dentro do clipe.
MidiClip? splitMidiClip(MidiClip clip, double at) {
  const eps = 1e-9;
  final cut = at - clip.start;
  if (cut <= eps || cut >= clip.length - eps) return null;
  final left = <MidiNote>[], right = <MidiNote>[];
  for (final n in clip.notes) {
    if (n.start >= cut - eps) {
      right.add(n..start = math.max(0.0, n.start - cut));
    } else if (n.end > cut + eps) {
      right.add(MidiNote(pitch: n.pitch, start: 0, length: n.end - cut, velocity: n.velocity));
      left.add(n..length = cut - n.start);
    } else {
      left.add(n);
    }
  }
  final r = MidiClip(id: newId(), name: clip.name, start: at, length: clip.length - cut, notes: right);
  clip
    ..length = cut
    ..notes = left;
  return r;
}

// ------------------------------------------------------------------ teclado do computador

/// Teclas que tocam notas, pela posição (independe do layout): a fileira do meio são as brancas,
/// a de cima as pretas, de dó até o ré# da oitava seguinte.
const noteKeys = <PhysicalKeyboardKey>[
  PhysicalKeyboardKey.keyA, // C
  PhysicalKeyboardKey.keyW, // C#
  PhysicalKeyboardKey.keyS, // D
  PhysicalKeyboardKey.keyE, // D#
  PhysicalKeyboardKey.keyD, // E
  PhysicalKeyboardKey.keyF, // F
  PhysicalKeyboardKey.keyT, // F#
  PhysicalKeyboardKey.keyG, // G
  PhysicalKeyboardKey.keyY, // G#
  PhysicalKeyboardKey.keyH, // A
  PhysicalKeyboardKey.keyU, // A#
  PhysicalKeyboardKey.keyJ, // B
  PhysicalKeyboardKey.keyK, // C
  PhysicalKeyboardKey.keyO, // C#
  PhysicalKeyboardKey.keyL, // D
  PhysicalKeyboardKey.keyP, // D#
];

/// Oitava abaixo/acima e velocidade menor/maior.
const _octaveDown = PhysicalKeyboardKey.keyZ, _octaveUp = PhysicalKeyboardKey.keyX;
const _velocityDown = PhysicalKeyboardKey.keyC, _velocityUp = PhysicalKeyboardKey.keyV;

/// Nota MIDI que uma tecla toca com o teclado na oitava [octave] (4 = dó central na tecla A), ou
/// null se a tecla não é de nota.
int? keyboardNote(PhysicalKeyboardKey key, int octave) {
  final i = noteKeys.indexOf(key);
  if (i < 0) return null;
  final pitch = (octave + 1) * 12 + i;
  return pitch >= 0 && pitch <= 127 ? pitch : null;
}

bool _isKeyboardKey(PhysicalKeyboardKey k) => noteKeys.contains(k) || k == _octaveDown || k == _octaveUp || k == _velocityDown || k == _velocityUp;

/// O que o motor já recebeu de uma faixa (tipo, parâmetros, áudio do sampler): o sync só manda o
/// que mudou, senão um arraste mandaria centenas de parâmetros por quadro.
class _SentTrack {
  final TrackKind kind;
  final params = <int, double>{};
  int sample = 0;
  _SentTrack(this.kind);
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

  /// Notas tocando ao vivo agora (teclado, MIDI, prévia), em qualquer faixa: o teclado do piano
  /// roll acende as teclas por aqui.
  final liveNotes = ValueNotifier<Set<int>>(const {});

  final waveforms = <String, Waveform>{};
  final _sampleIds = <String, int>{};

  /// Áudios citados no documento que não estão neste aparelho.
  final missing = <String>{};

  /// Clipe selecionado, de áudio ou MIDI.
  String? selectedClip;
  int selectedTrack = 0;
  Snap snap = Snap.beat;

  /// Zoom (pixels por batida) e o começo da janela visível, em batidas.
  double pxPerBeat = 48;
  double scrollBeat = 0;
  bool follow = true;

  /// Largura visível das raias em pixels (a linha do tempo informa a cada layout).
  double viewWidth = 800;

  /// Painel de baixo: nenhum, mixer, editor de notas (piano roll) ou instrumento da faixa.
  Dock dock = Dock.none;
  bool get mixerOpen => dock == Dock.mixer;

  /// Clipe MIDI aberto no piano roll.
  String? editingClip;

  /// Teclado do computador tocando notas na faixa selecionada (e oitava base dele).
  bool keyboardOn = false;
  int keyboardOctave = 4;
  double keyboardVelocity = 0.8;

  /// Teclas do editor aberto (o piano roll registra ao montar e limpa ao desmontar). O atalho
  /// global da tela chama primeiro as notas do teclado, depois este, depois os atalhos gerais.
  bool Function(KeyEvent e)? editorKeyHandler;

  /// Nomes das entradas MIDI conectadas (Web MIDI); vazio quando não há ou não há permissão.
  List<String> midiInputs = const [];

  /// O MIDI do navegador foi liberado e está tocando a faixa selecionada.
  bool midiEnabled = false;

  final _undo = <String>[];
  final _redo = <String>[];
  Timer? _saveTimer;
  bool _disposed = false;

  // o que já foi ao motor (ver [_sync])
  final _sent = <_SentTrack>[];
  List<String> _sentIds = const [];
  List<EngineNote>? _sentNotes;

  /// Notas ao vivo soando no motor, como (faixa, nota), para soltar tudo quando preciso.
  final _live = <(int, int)>{};

  /// Nota que cada tecla física está tocando: solta a certa mesmo se a oitava mudou no meio.
  final _keyNotes = <PhysicalKeyboardKey, (int, int)>{};

  /// Notas do MIDI soando (nota → faixa) e as que o pedal está segurando depois de soltas.
  final _midiNotes = <int, int>{};
  final _sustained = <int>{};
  bool _sustain = false;

  String get _docKey => 'doc:${project.id}';

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  // ------------------------------------------------------------------ abrir

  Future<void> open() async {
    try {
      if (!_engine.supported) throw UnsupportedError('O motor de áudio ainda não roda neste aparelho: use o jopendaw no navegador por enquanto.');
      await _engine.start();
      _engine.onState = _onEngineState;
      final saved = await _store.get(_docKey);
      doc = saved is String ? DawDoc.fromJson(jsonDecode(saved)) : _fresh();
      // o andamento e a fórmula de compasso moram no servidor; o local segue
      doc.bpm = project.bpm.toDouble();
      doc.beatsPerBar = project.beatsPerBar;
      for (final hash in doc.samples.keys.toList()) {
        await _loadSample(hash);
      }
      if (_disposed) return;
      ready = true;
      _sync();
    } catch (e) {
      error = e is UnsupportedError ? e.message : '$e';
    }
    if (!_disposed) notifyListeners();
  }

  void _onEngineState(EngineState s) {
    beat.value = s.beat;
    playing.value = s.playing;
    peaks.value = s.peaks;
    _follow(s);
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
    _disposed = true;
    // o motor sobrevive à tela: nada pode ficar soando nem preso para o próximo projeto
    _engine.calls([
      ['stop'],
      ['panic'],
    ]);
    if (_engine.onState == _onEngineState) _engine.onState = null;
    if (_engine.onMidi == _onMidi) _engine.onMidi = null;
    if (_engine.onMidiInputs == _onMidiInputs) _engine.onMidiInputs = null;
    editorKeyHandler = null;
    _saveTimer?.cancel();
    _save();
    beat.dispose();
    playing.dispose();
    peaks.dispose();
    liveNotes.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------ motor

  /// Manda o documento ao motor. É barato: dezenas de chamadas numa mensagem. Instrumentos e
  /// notas vão só no que mudou desde o último envio.
  void _sync() {
    final d = doc;
    final ids = [for (final t in d.tracks) t.id];
    var release = const <List<Object>>[];
    if (!_isPrefix(_sentIds, ids)) {
      // faixas saíram ou mudaram de lugar: o índice de cada instrumento no motor agora é de outra
      // faixa, e o que soa ao vivo ficaria preso no índice velho
      release = _releaseLive();
      _sent.clear();
      _sentNotes = null;
    }
    _sentIds = ids;
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
    // instrumentos e notas depois do áudio: um motor que ainda não conheça estas funções para na
    // primeira que falta, e o arranjo de áudio já foi inteiro. O que soava ao vivo solta antes de
    // o índice trocar de instrumento.
    calls.addAll(release);
    for (var i = 0; i < d.tracks.length; i++) {
      final t = d.tracks[i];
      var s = i < _sent.length ? _sent[i] : null;
      final fresh = s == null || s.kind != t.kind;
      if (s == null || fresh) {
        s = _SentTrack(t.kind);
        if (i < _sent.length) {
          _sent[i] = s;
        } else {
          _sent.add(s);
        }
        calls.add(['track_kind', i, t.kind.index]);
      }
      for (final p in t.kind.params) {
        final v = t.param(p.id);
        if (fresh || s.params[p.id] != v) {
          calls.add(['param', i, p.id, v]);
          s.params[p.id] = v;
        }
      }
      if (t.kind == TrackKind.sampler) {
        final sample = _sampleIds[t.sample] ?? 0;
        if (fresh || s.sample != sample) {
          calls.add(['instrument_sample', i, sample]);
          s.sample = sample;
        }
      }
    }
    if (_sent.length > d.tracks.length) _sent.length = d.tracks.length;
    final notes = flattenNotes(d.tracks);
    if (_sentNotes == null || !listEquals(notes, _sentNotes)) {
      calls.add(['notes_clear']);
      for (final n in notes) {
        calls.add(['note_add', n.track, n.start, n.length, n.pitch, n.velocity]);
      }
      _sentNotes = notes;
    }
    _engine.calls(calls);
  }

  static bool _isPrefix(List<String> a, List<String> b) {
    if (a.length > b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
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
    _prune();
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
    _prune();
    _sync();
    _scheduleSave();
    notifyListeners();
  }

  /// Esquece a seleção e o clipe do editor que não existem mais (apagados, desfeitos).
  void _prune() {
    final sel = selectedClip;
    if (sel != null && _findClip(sel) == null && findMidiClip(sel) == null) selectedClip = null;
    final ed = editingClip;
    if (ed != null && findMidiClip(ed) == null) {
      editingClip = null;
      if (dock == Dock.editor) dock = Dock.none;
    }
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

  /// O clipe de áudio selecionado (com a faixa), se a seleção for de áudio.
  (DawTrack, AudioClip)? get selection => selectedClip == null ? null : _findClip(selectedClip!);

  /// O clipe MIDI selecionado (com a faixa), se a seleção for MIDI.
  (DawTrack, MidiClip)? get midiSelection => selectedClip == null ? null : findMidiClip(selectedClip!);

  void selectClip(String? id) {
    selectedClip = id;
    if (id != null) {
      final t = _findClip(id)?.$1 ?? findMidiClip(id)?.$1;
      if (t != null) selectedTrack = doc.tracks.indexOf(t);
    }
    notifyListeners();
  }

  /// Move um clipe para outra faixa (arraste vertical). Áudio só entra em faixa de áudio e MIDI só
  /// em faixa de instrumento: nas outras o clipe fica onde está.
  void moveClipToTrack(String id, int track) {
    if (track < 0 || track >= doc.tracks.length) return;
    final to = doc.tracks[track];
    final a = _findClip(id);
    if (a != null) {
      final (from, clip) = a;
      if (identical(from, to) || to.kind.isInstrument) return;
      mutate((_) {
        from.clips.remove(clip);
        to.clips.add(clip);
        selectedTrack = track;
      });
      return;
    }
    final m = findMidiClip(id);
    if (m == null) return;
    final (from, clip) = m;
    if (identical(from, to) || !to.kind.isInstrument) return;
    mutate((_) {
      from.midi.remove(clip);
      to.midi.add(clip);
      selectedTrack = track;
    });
  }

  void deleteSelected() {
    final a = selection;
    final m = midiSelection;
    if (a != null) {
      edit((_) => a.$1.clips.remove(a.$2));
    } else if (m != null) {
      edit((_) => m.$1.midi.remove(m.$2));
    }
  }

  void duplicateSelected() {
    final a = selection;
    if (a != null) {
      final (t, c) = a;
      final copy = AudioClip.fromJson(c.toJson())
        ..id = newId()
        ..start = c.end(doc.bpm);
      edit((_) {
        t.clips.add(copy);
        selectedClip = copy.id;
      });
      return;
    }
    final m = midiSelection;
    if (m == null) return;
    final (t, c) = m;
    final copy = MidiClip.fromJson(c.toJson())
      ..id = newId()
      ..start = c.end;
    edit((_) {
      t.midi.add(copy);
      selectedClip = copy.id;
    });
  }

  /// Corta no cursor de reprodução: o clipe selecionado, ou tudo o que ele cruza na faixa atual.
  void splitAtPlayhead() {
    final at = beat.value;
    final audio = <(DawTrack, AudioClip)>[];
    final midi = <(DawTrack, MidiClip)>[];
    final a = selection, m = midiSelection;
    if (a != null) {
      audio.add(a);
    } else if (m != null) {
      midi.add(m);
    } else if (selectedTrack < doc.tracks.length) {
      final t = doc.tracks[selectedTrack];
      audio.addAll(t.clips.map((c) => (t, c)));
      midi.addAll(t.midi.map((c) => (t, c)));
    }
    final audioCuts = audio.where((f) => f.$2.start < at && f.$2.end(doc.bpm) > at).toList();
    final midiCuts = midi.where((f) => f.$2.start < at && f.$2.end > at).toList();
    if (audioCuts.isEmpty && midiCuts.isEmpty) return;
    edit((d) {
      for (final (t, c) in audioCuts) {
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
      for (final (t, c) in midiCuts) {
        final right = splitMidiClip(c, at);
        if (right != null) t.midi.add(right);
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

  /// Importa áudios já lidos: o primeiro vai na faixa selecionada (se for de áudio e estiver vazia
  /// no ponto), os outros em faixas de áudio novas.
  Future<void> importBytes(List<(String, Uint8List)> files, {double? at, int? track}) async {
    final start = at ?? snapBeat(beat.value);
    var ti = track ?? selectedTrack;
    checkpoint();
    for (var i = 0; i < files.length; i++) {
      final (name, bytes) = files[i];
      status = 'Importando $name…';
      notifyListeners();
      try {
        final hash = await _ingest(name, bytes);
        if (_disposed) return;
        final info = doc.samples[hash]!;
        if (ti >= doc.tracks.length || doc.tracks[ti].kind.isInstrument || i > 0 || _occupied(doc.tracks[ti], start, start + info.duration * doc.bpm / 60)) {
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
    _prune();
    _sync();
    _scheduleSave();
    notifyListeners();
  }

  /// Decodifica, guarda no aparelho e registra no motor e no documento (se ainda não estiver);
  /// devolve o sha-256.
  Future<String> _ingest(String name, Uint8List bytes) async {
    final hash = sha256.convert(bytes).toString();
    if (!waveforms.containsKey(hash)) {
      final audio = await _engine.decode(bytes);
      await _store.put('sample:$hash', bytes);
      _register(hash, audio);
      doc.samples[hash] = SampleInfo(name, audio.duration);
    }
    doc.samples[hash] ??= SampleInfo(name, 0);
    return hash;
  }

  /// Escolhe um arquivo e faz dele o áudio do sampler da faixa.
  Future<void> importSamplerAudio(int track) async {
    final files = await FilePicker.pickFiles(dialogTitle: 'Áudio do sampler', type: FileType.custom, allowedExtensions: audioExtensions);
    if (files.isEmpty || _disposed) return;
    final f = files.first;
    await importSamplerBytes(track, f.name, await f.readAsBytes());
  }

  /// Faz de um áudio já lido o áudio do sampler da faixa (sem pôr clipe no arranjo).
  Future<void> importSamplerBytes(int track, String name, Uint8List bytes) async {
    if (!_isKind(track, TrackKind.sampler)) return;
    // a faixa pode mudar de lugar enquanto o áudio decodifica
    final id = doc.tracks[track].id;
    status = 'Importando $name…';
    notifyListeners();
    try {
      final hash = await _ingest(name, bytes);
      if (_disposed) return;
      status = null;
      final i = doc.tracks.indexWhere((t) => t.id == id);
      if (i >= 0 && doc.tracks[i].sample != hash) {
        setInstrumentSample(i, hash);
        return;
      }
      _sync();
      _scheduleSave();
    } catch (e) {
      if (_disposed) return;
      status = null;
      error = 'Não deu para abrir $name: é um formato de áudio que este navegador decodifica?';
    }
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

  // ------------------------------------------------------------------ instrumentos e MIDI

  bool _isKind(int track, TrackKind kind) => track >= 0 && track < doc.tracks.length && doc.tracks[track].kind == kind;

  bool _isInstrument(int track) => track >= 0 && track < doc.tracks.length && doc.tracks[track].kind.isInstrument;

  /// Nova faixa de instrumento com o instrumento no padrão; fica selecionada.
  void addInstrumentTrack(TrackKind kind) {
    if (!kind.isInstrument) {
      addTrack();
      return;
    }
    edit((d) {
      final n = d.tracks.length;
      final names = {for (final t in d.tracks) t.name};
      var k = d.tracks.where((t) => t.kind == kind).length + 1;
      while (names.contains('${kind.label} $k')) {
        k++;
      }
      d.tracks.add(DawTrack(id: newId(), name: '${kind.label} $k', color: n % Palette.tracks.length, kind: kind));
      selectedTrack = n;
    });
  }

  /// Clipe MIDI vazio na faixa, começando em [start] (batidas); padrão: um compasso. Fica
  /// selecionado e é devolvido.
  MidiClip createMidiClip(int track, double start, {double? length}) {
    if (!_isInstrument(track)) throw ArgumentError.value(track, 'track', 'clipe MIDI só entra em faixa de instrumento');
    final t = doc.tracks[track];
    final bar = doc.beatsPerBar.toDouble();
    final len = length != null && length > 0 ? length : bar;
    final clip = MidiClip(id: newId(), name: t.name, start: math.max(0.0, start), length: len);
    edit((_) {
      t.midi.add(clip);
      selectedClip = clip.id;
      selectedTrack = track;
    });
    return clip;
  }

  /// O clipe MIDI (com a faixa) de um id, ou null.
  (DawTrack, MidiClip)? findMidiClip(String id) {
    for (final t in doc.tracks) {
      for (final c in t.midi) {
        if (c.id == id) return (t, c);
      }
    }
    return null;
  }

  /// O clipe aberto no piano roll.
  (DawTrack, MidiClip)? get editing => editingClip == null ? null : findMidiClip(editingClip!);

  /// Abre o clipe no piano roll (painel de baixo).
  void openPianoRoll(String clipId) {
    final f = findMidiClip(clipId);
    if (f == null) return;
    editingClip = clipId;
    selectedClip = clipId;
    selectedTrack = doc.tracks.indexOf(f.$1);
    dock = Dock.editor;
    notifyListeners();
  }

  /// Troca o painel de baixo. O editor sem clipe aberto pega o clipe MIDI selecionado.
  void setDock(Dock d) {
    if (d == Dock.editor && editing == null) {
      final m = midiSelection;
      if (m != null) editingClip = m.$2.id;
    }
    dock = d;
    notifyListeners();
  }

  void toggleMixer() => setDock(dock == Dock.mixer ? Dock.none : Dock.mixer);

  /// O navegador segura o áudio até um gesto do usuário; quando já está rodando, não custa nada.
  void _wake() => unawaited(_engine.resume());

  /// Toca uma nota na hora (prévia do piano roll, teclado, MIDI), na faixa dada ou na selecionada.
  void noteOn(int pitch, {double velocity = 0.8, int? track}) {
    if (!ready) return;
    final i = track ?? selectedTrack;
    if (!_isInstrument(i) || pitch < 0 || pitch > 127) return;
    _wake();
    final v = velocity.isNaN ? 0.8 : velocity.clamp(0.0, 1.0).toDouble();
    _engine.calls([
      ['live_on', i, pitch, v],
    ]);
    _live.add((i, pitch));
    _publishLive();
  }

  /// Solta a nota na faixa dada; sem faixa, onde ela estiver soando (a seleção pode ter mudado
  /// desde o note on).
  void noteOff(int pitch, {int? track}) {
    if (!ready) return;
    final targets = track != null
        ? [track]
        : [
            for (final (t, p) in _live)
              if (p == pitch) t,
          ];
    if (targets.isEmpty) targets.add(selectedTrack);
    _liveOff([for (final t in targets) (t, pitch)]);
  }

  void _liveOff(Iterable<(int, int)> notes) {
    final calls = <List<Object>>[];
    for (final n in notes) {
      _live.remove(n);
      if (_isInstrument(n.$1)) calls.add(['live_off', n.$1, n.$2]);
    }
    if (calls.isNotEmpty) _engine.calls(calls);
    _publishLive();
  }

  /// Chamadas que soltam tudo o que está soando ao vivo; esquece teclas, MIDI e pedal.
  List<List<Object>> _releaseLive() {
    final calls = [
      for (final (t, p) in _live) <Object>['live_off', t, p],
    ];
    _live.clear();
    _keyNotes.clear();
    _midiNotes.clear();
    _sustained.clear();
    _publishLive();
    return calls;
  }

  void _publishLive() {
    final pitches = {for (final (_, p) in _live) p};
    if (!setEquals(pitches, liveNotes.value)) liveNotes.value = pitches;
  }

  static ParamSpec? _spec(TrackKind kind, int id) {
    for (final p in kind.params) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Valor dentro da faixa do parâmetro, inteiro quando o parâmetro é inteiro ou opção.
  static double _fit(ParamSpec p, double v) {
    if (v.isNaN) return p.def;
    final c = p.clamp(v);
    return p.curve == Curve.integer || p.curve == Curve.choice ? c.roundToDouble() : c;
  }

  /// Muda um parâmetro do instrumento. Para arrastes: [checkpoint] no começo e `undoable: false`.
  ///
  /// Caminho rápido: só este parâmetro vai ao motor, sem o sync do documento inteiro.
  void setParam(int track, int id, double value, {bool undoable = false}) {
    if (!_isInstrument(track)) return;
    final t = doc.tracks[track];
    final spec = _spec(t.kind, id);
    if (spec == null) return;
    final v = _fit(spec, value);
    if (t.params.containsKey(id) && t.params[id] == v) return;
    if (undoable) checkpoint();
    t.params[id] = v;
    _engine.calls([
      ['param', track, id, v],
    ]);
    if (track < _sent.length && _sent[track].kind == t.kind) _sent[track].params[id] = v;
    _scheduleSave();
    notifyListeners();
  }

  /// Aplica um preset (valores que faltam voltam ao padrão).
  void applyPreset(int track, Map<int, double> values) {
    if (!_isInstrument(track)) return;
    final t = doc.tracks[track];
    edit((_) => t.params = {for (final p in t.kind.params) p.id: _fit(p, values[p.id] ?? p.def)});
  }

  /// Escolhe o áudio (sha-256 de um sample do projeto) que o sampler da faixa toca.
  void setInstrumentSample(int track, String? hash) {
    if (!_isKind(track, TrackKind.sampler)) return;
    final t = doc.tracks[track];
    if (t.sample == hash || (hash != null && !doc.samples.containsKey(hash))) return;
    edit((_) => t.sample = hash);
  }

  /// Quantiza notas de um clipe na grade (batidas). [strength] 0..1; [ends] também as durações.
  void quantizeNotes(MidiClip clip, Iterable<MidiNote> notes, double grid, {double strength = 1, bool ends = false}) {
    final list = notes.toList();
    if (list.isEmpty || !(grid > 0) || !(strength > 0)) return;
    edit((_) => quantizeNoteList(list, grid, offset: clip.start, strength: strength, ends: ends));
  }

  // ------------------------------------------------------------------ teclado do computador

  void toggleKeyboard() {
    keyboardOn = !keyboardOn;
    if (keyboardOn) {
      _wake();
    } else {
      _liveOff(_keyNotes.values.toList());
      _keyNotes.clear();
    }
    notifyListeners();
  }

  /// Oitava da tecla A (0..8).
  void setKeyboardOctave(int octave) {
    final o = octave.clamp(0, 8);
    if (o == keyboardOctave) return;
    keyboardOctave = o;
    notifyListeners();
  }

  /// Velocidade das notas do teclado, em passos de 0,1 (0,1..1).
  void setKeyboardVelocity(double velocity) {
    final v = ((velocity * 10).round() / 10).clamp(0.1, 1.0).toDouble();
    if (v == keyboardVelocity) return;
    keyboardVelocity = v;
    notifyListeners();
  }

  static bool _typing() => FocusManager.instance.primaryFocus?.context?.widget is EditableText;

  /// Com o teclado do computador ligado, trata a tecla como nota (A W S E D F T G Y H U J K O L P;
  /// Z/X oitava, C/V velocidade). Devolve true se consumiu a tecla.
  bool handleNoteKey(KeyEvent e) {
    if (!keyboardOn || !ready) return false;
    final key = e.physicalKey;
    if (e is KeyUpEvent) {
      // solta mesmo com modificador apertado no meio: senão a nota fica presa
      final held = _keyNotes.remove(key);
      if (held != null) _liveOff([held]);
      return held != null || _isKeyboardKey(key);
    }
    final keys = HardwareKeyboard.instance;
    if (keys.isControlPressed || keys.isMetaPressed || keys.isAltPressed) return false;
    if (!_isKeyboardKey(key) || _typing()) return false;
    // segurar a tecla não reataca a nota nem dispara oitava/velocidade em rajada
    if (e is KeyRepeatEvent) return true;
    final pitch = keyboardNote(key, keyboardOctave);
    if (pitch != null) {
      if (_keyNotes.containsKey(key)) return true;
      final t = selectedTrack;
      noteOn(pitch, velocity: keyboardVelocity, track: t);
      if (_live.contains((t, pitch))) _keyNotes[key] = (t, pitch);
    } else if (key == _octaveDown) {
      setKeyboardOctave(keyboardOctave - 1);
    } else if (key == _octaveUp) {
      setKeyboardOctave(keyboardOctave + 1);
    } else if (key == _velocityDown) {
      setKeyboardVelocity(keyboardVelocity - 0.1);
    } else if (key == _velocityUp) {
      setKeyboardVelocity(keyboardVelocity + 0.1);
    }
    return true;
  }

  // ------------------------------------------------------------------ MIDI

  /// Pede acesso ao MIDI do navegador e passa a tocar a faixa selecionada com ele.
  Future<void> enableMidiInput() async {
    // o clique que liga o MIDI é o gesto que destrava o áudio (mensagem MIDI não conta como gesto)
    _wake();
    _engine.onMidi = _onMidi;
    _engine.onMidiInputs = _onMidiInputs;
    try {
      final inputs = await _engine.enableMidi();
      if (_disposed) return;
      midiInputs = inputs;
      midiEnabled = true;
    } on UnsupportedError catch (e) {
      error = e.message ?? 'Este navegador não dá acesso a MIDI.';
    } on StateError catch (e) {
      error = e.message;
    } catch (e) {
      error = 'Não deu para ligar o MIDI: $e';
    }
    if (!_disposed) notifyListeners();
  }

  void _onMidiInputs(List<String> inputs) {
    if (_disposed || listEquals(inputs, midiInputs)) return;
    midiInputs = inputs;
    notifyListeners();
  }

  void _onMidi(int status, int data1, int data2) {
    if (!ready || _disposed) return;
    final type = status & 0xF0;
    if (type == 0x90 && data2 > 0) {
      _midiNoteOn(data1, data2 / 127);
    } else if (type == 0x80 || type == 0x90) {
      // note on com velocidade 0 é note off (running status dos teclados)
      _midiNoteOff(data1);
    } else if (type == 0xB0) {
      switch (data1) {
        case 64:
          _setSustain(data2 >= 64);
        case 121: // reset dos controles: pedal solto
          _setSustain(false);
        case 120: // all sound off: corta na hora, inclusive caudas
          _midiAllOff();
          _engine.calls([
            ['panic'],
          ]);
        case 123: // all notes off
          _midiAllOff();
      }
    }
  }

  void _midiNoteOn(int pitch, double velocity) {
    if (pitch < 0 || pitch > 127) return;
    _sustained.remove(pitch);
    final t = selectedTrack;
    final before = _midiNotes[pitch];
    if (before != null && before != t) _liveOff([(before, pitch)]);
    noteOn(pitch, velocity: velocity, track: t);
    if (_live.contains((t, pitch))) {
      _midiNotes[pitch] = t;
    } else {
      _midiNotes.remove(pitch);
    }
  }

  void _midiNoteOff(int pitch) {
    final t = _midiNotes[pitch];
    if (t == null) return;
    if (_sustain) {
      _sustained.add(pitch);
      return;
    }
    _midiNotes.remove(pitch);
    _liveOff([(t, pitch)]);
  }

  void _setSustain(bool on) {
    if (on == _sustain) return;
    _sustain = on;
    if (on) return;
    final off = <(int, int)>[];
    for (final p in _sustained) {
      final t = _midiNotes.remove(p);
      if (t != null) off.add((t, p));
    }
    _sustained.clear();
    _liveOff(off);
  }

  void _midiAllOff() {
    _liveOff([for (final e in _midiNotes.entries) (e.value, e.key)]);
    _midiNotes.clear();
    _sustained.clear();
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
}
