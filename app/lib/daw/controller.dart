/// O cérebro da tela do projeto: guarda o documento, o histórico de desfazer, a seleção e a visão
/// (zoom e rolagem), e mantém o motor de áudio e o guardado local em dia com cada edição.
library;

import 'dart:async';
import 'dart:collection';
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
import 'automation_math.dart';
import 'effects.dart';
import 'export_options.dart';
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
enum Dock { none, mixer, editor, instrument, effects }

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

/// O que o motor já recebeu de uma faixa (tipo, parâmetros, áudio do sampler, efeitos, envios,
/// saída): o sync só manda o que mudou, senão um arraste mandaria centenas de parâmetros por quadro.
class _SentTrack {
  final TrackKind kind;
  final params = <int, double>{};
  int sample = 0;
  final fx = _SentChain();

  /// Envios como o motor os conhece: (índice do barramento, nível, pré-fader), só os válidos.
  final sends = <(int, double, bool)>[];
  int sendCount = -1;

  /// Índice do barramento de saída (−1 master); null: ainda não foi.
  int? output;
  _SentTrack(this.kind);
}

/// Um slot de efeito como o motor o conhece.
class _SentFx {
  final EffectKind kind;
  final params = <int, double>{};
  bool? bypass;
  _SentFx(this.kind);
}

/// A cadeia de efeitos de uma faixa (ou do master) como o motor a conhece.
class _SentChain {
  int count = -1;
  final slots = <_SentFx?>[];
}

/// Um alvo de automação resolvido para o motor: código de `auto_target`, slot (efeito ou envio,
/// no índice do motor), id do parâmetro, faixa de valores e o valor atual sem automação.
typedef _Resolved = ({int code, int slot, int id, double min, double max, double value, ParamSpec? spec});

/// Ganho máximo do volume e dos envios: o topo do fader (+6 dB).
const maxGain = 2.0;

/// Nível de um envio novo: −6 dB.
const defaultSendLevel = 0.5;

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
  final _sentMaster = _SentChain();
  List<List<Object>>? _sentAuto;
  (int, int)? _sentWatchFx;
  int? _sentWatchAnalyzer;

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
      engineRate = await _engine.start();
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
    // um estado que chega depois de desligar a observação (já estava a caminho) não acende nada
    fxMeter.value = _sentWatchFx == null || _sentWatchFx!.$2 < 0 || !s.fxMeter.isFinite ? 0 : s.fxMeter;
    spectrum.value = _sentWatchAnalyzer == null || _sentWatchAnalyzer! < -1 ? null : s.spectrum;
    _follow(s);
  }

  /// Nos testes: um estado do motor como se tivesse chegado dele.
  @visibleForTesting
  void debugEngineState(EngineState s) => _onEngineState(s);

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
    // o motor sobrevive à tela: nada pode ficar soando nem preso para o próximo projeto, nem
    // medindo o que ninguém mais olha
    _engine.calls([
      ['stop'],
      ['panic'],
      ['watch_fx', -1, -1],
      ['watch_analyzer', -2],
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
    fxMeter.dispose();
    spectrum.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------ motor

  /// Manda o documento ao motor. É barato: dezenas de chamadas numa mensagem. Instrumentos,
  /// efeitos, roteamento, automação e notas vão só no que mudou desde o último envio.
  ///
  /// Ordem: áudio → instrumentos → efeitos → roteamento → automação → observação → notas.
  void _sync() {
    final d = doc;
    final ids = [for (final t in d.tracks) t.id];
    var release = const <List<Object>>[];
    if (!_isPrefix(_sentIds, ids)) {
      // faixas saíram ou mudaram de lugar: o índice de cada instrumento no motor agora é de outra
      // faixa, e o que soa ao vivo ficaria preso no índice velho. Efeitos, envios e automação
      // também eram de outra faixa: vai tudo de novo.
      release = _releaseLive();
      _sent.clear();
      _sentNotes = null;
      _sentAuto = null;
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
      if (t.kind != TrackKind.audio) continue;
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
    for (var i = 0; i < d.tracks.length; i++) {
      _syncChain(calls, i, d.tracks[i].effects, _sent[i].fx);
    }
    _syncChain(calls, -1, d.masterEffects, _sentMaster);
    final index = _trackIndex();
    final sends = [for (var i = 0; i < d.tracks.length; i++) _validSends(i, index)];
    for (var i = 0; i < d.tracks.length; i++) {
      _syncRouting(calls, i, sends[i], index);
    }
    final auto = _automationCalls(sends);
    if (_sentAuto == null || !_sameCalls(auto, _sentAuto!)) {
      calls.add(['auto_clear']);
      calls.addAll(auto);
      _sentAuto = auto;
    }
    calls.addAll(_watchCalls());
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

  static bool _sameCalls(List<List<Object>> a, List<List<Object>> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!listEquals(a[i], b[i])) return false;
    }
    return true;
  }

  /// Cadeia de efeitos no motor: quantos slots, o tipo de cada um (só quando muda naquele índice)
  /// e os parâmetros e o bypass que mudaram. Tipo novo no slot é um efeito novo no motor, no
  /// padrão dele: vai tudo daquele slot.
  void _syncChain(List<List<Object>> calls, int track, List<EffectSlot> chain, _SentChain s) {
    if (s.count != chain.length) {
      calls.add(['fx_count', track, chain.length]);
      s.count = chain.length;
    }
    if (s.slots.length > chain.length) s.slots.length = chain.length;
    for (var k = 0; k < chain.length; k++) {
      final slot = chain[k];
      var f = k < s.slots.length ? s.slots[k] : null;
      final fresh = f == null || f.kind != slot.kind;
      if (f == null || fresh) {
        f = _SentFx(slot.kind);
        if (k < s.slots.length) {
          s.slots[k] = f;
        } else {
          s.slots.add(f);
        }
        calls.add(['fx_set', track, k, slot.kind.code]);
      }
      for (final p in slot.kind.params) {
        final v = slot.param(p.id);
        if (fresh || f.params[p.id] != v) {
          calls.add(['fx_param', track, k, p.id, v]);
          f.params[p.id] = v;
        }
      }
      if (fresh || f.bypass != slot.bypass) {
        calls.add(['fx_bypass', track, k, slot.bypass]);
        f.bypass = slot.bypass;
      }
    }
  }

  Map<String, int> _trackIndex() => {for (var i = 0; i < doc.tracks.length; i++) doc.tracks[i].id: i};

  /// Índice do barramento [busId] como destino (envio ou saída) da faixa [from], ou −1 se ele não
  /// serve: não existe, não é barramento, é a própria faixa ou fecharia um ciclo.
  ///
  /// A regra do fluxo: faixa comum manda para qualquer barramento (ela não recebe áudio, então não
  /// fecha ciclo); barramento só manda para barramento de índice MAIOR que o dele. Assim a ordem
  /// das faixas é a ordem do sinal entre barramentos, e o motor processa as faixas comuns e depois
  /// os barramentos em ordem, sem montar grafo. Reordenar faixas desfaz o que passar a violar isso.
  int _routeIndex(int from, String? busId, Map<String, int> index) {
    if (busId == null) return -1;
    final j = index[busId];
    if (j == null || j == from || doc.tracks[j].kind != TrackKind.bus) return -1;
    if (doc.tracks[from].kind == TrackKind.bus && j < from) return -1;
    return j;
  }

  /// Os envios da faixa que vão ao motor (destino válido, na ordem da lista), com o índice do
  /// barramento. A posição nesta lista é o índice do envio no motor (`send_set`, automação).
  List<(Send, int)> _validSends(int track, Map<String, int> index) {
    final out = <(Send, int)>[];
    for (final s in doc.tracks[track].sends) {
      final j = _routeIndex(track, s.target, index);
      if (j >= 0) out.add((s, j));
    }
    return out;
  }

  static double _sendLevel(double v) => v.isFinite ? v.clamp(0.0, maxGain).toDouble() : 0;

  void _syncRouting(List<List<Object>> calls, int i, List<(Send, int)> sends, Map<String, int> index) {
    final s = _sent[i];
    if (s.sendCount != sends.length) {
      calls.add(['sends_count', i, sends.length]);
      s.sendCount = sends.length;
    }
    if (s.sends.length > sends.length) s.sends.length = sends.length;
    for (var k = 0; k < sends.length; k++) {
      final (send, j) = sends[k];
      final v = (j, _sendLevel(send.level), send.pre);
      if (k < s.sends.length && s.sends[k] == v) continue;
      calls.add(['send_set', i, k, j, v.$2, v.$3]);
      if (k < s.sends.length) {
        s.sends[k] = v;
      } else {
        s.sends.add(v);
      }
    }
    final out = _routeIndex(i, doc.tracks[i].output, index);
    if (s.output != out) {
      calls.add(['track_output', i, out]);
      s.output = out;
    }
  }

  /// A automação inteira como chamadas (`auto_lane` + `auto_point`), das faixas e do master. Vão só
  /// as lanes com pontos e alvo que existe; o índice de cada lane no motor é a ordem de criação
  /// depois do `auto_clear` (o worklet não devolve o retorno de `auto_lane`).
  List<List<Object>> _automationCalls(List<List<(Send, int)>> sends) {
    final out = <List<Object>>[];
    var lane = 0;
    void add(int track, List<AutoLane> lanes) {
      for (final l in lanes) {
        if (l.points.isEmpty) continue;
        final r = _resolve(track, l.target, sends: track >= 0 ? sends[track] : const []);
        if (r == null) continue;
        final points = _sortedPoints(l.points);
        if (points.isEmpty) continue;
        out.add(['auto_lane', track, r.code, r.slot, r.id]);
        for (final (beat, value, curve) in autoEnginePoints(points, _warpOf(r))) {
          final c = curve.isFinite ? curve.clamp(-1.0, 1.0).toDouble() : 0.0;
          out.add(['auto_point', lane, math.max(0.0, beat), value.clamp(r.min, r.max).toDouble(), c]);
        }
        lane++;
      }
    }

    for (var i = 0; i < doc.tracks.length; i++) {
      add(i, doc.tracks[i].lanes);
    }
    add(-1, doc.masterLanes);
    return out;
  }

  /// A faixa (ou o master, −1) tem automação com pontos para volume/pan.
  bool automated(int track, AutoKind kind) {
    if (track >= doc.tracks.length) return false;
    final lanes = track < 0 ? doc.masterLanes : doc.tracks[track].lanes;
    return lanes.any((l) => l.target.kind == kind && l.points.isNotEmpty);
  }

  /// O volume ou pan que a faixa tem agora: tocando e com automação, o valor da curva no cursor
  /// (a mesma conta do motor); parado, o valor fixo, como no motor. Para o fader e o pan
  /// acompanharem a automação.
  double liveValue(int track, AutoKind kind) {
    final master = track < 0;
    if (!master && track >= doc.tracks.length) return 0;
    final t = master ? null : doc.tracks[track];
    final fixed = kind == AutoKind.pan ? (t?.pan ?? doc.masterPan) : (t?.gain ?? doc.masterGain);
    if (!playing.value) return fixed;
    final lanes = master ? doc.masterLanes : t!.lanes;
    for (final l in lanes) {
      if (l.target.kind != kind || l.points.isEmpty) continue;
      final r = _resolve(track, l.target);
      if (r == null) return fixed;
      return autoValueAt(_sortedPoints(l.points), beat.value, fixed, warp: _warpOf(r)).clamp(r.min, r.max).toDouble();
    }
    return fixed;
  }

  /// A escala em que a automação do alvo anda entre pontos (a mesma da raia): curva do fader no
  /// volume e nos envios, a do botão nos parâmetros não lineares; null = reta no valor.
  static AutoWarp? _warpOf(_Resolved r) {
    if (r.code == 0 || r.code == 4) return (toNorm: gainToFader, fromNorm: faderToGain);
    final spec = r.spec;
    if (spec == null || spec.curve == Curve.linear) return null;
    return (toNorm: spec.toNorm, fromNorm: spec.fromNorm);
  }

  /// Pontos válidos em ordem de batida. Estável: dois pontos na mesma batida são um degrau, e a
  /// ordem deles decide de onde para onde.
  static List<AutoPoint> _sortedPoints(List<AutoPoint> points) {
    final valid = [
      for (final p in points)
        if (p.beat.isFinite && p.value.isFinite) p,
    ];
    final order = List.generate(valid.length, (i) => i)
      ..sort((a, b) {
        final c = valid[a].beat.compareTo(valid[b].beat);
        return c != 0 ? c : a - b;
      });
    return [for (final i in order) valid[i]];
  }

  /// O alvo de automação para o motor, ou null se ele não existe nesta faixa. [sends] são os
  /// envios válidos da faixa (calculados se faltarem).
  _Resolved? _resolve(int track, AutoTarget target, {List<(Send, int)>? sends}) {
    final master = track == -1;
    if (!master && (track < 0 || track >= doc.tracks.length)) return null;
    final t = master ? null : doc.tracks[track];
    switch (target.kind) {
      case AutoKind.volume:
        return (code: 0, slot: 0, id: 0, min: 0.0, max: maxGain, value: t?.gain ?? doc.masterGain, spec: null);
      case AutoKind.pan:
        return (code: 1, slot: 0, id: 0, min: -1.0, max: 1.0, value: t?.pan ?? doc.masterPan, spec: null);
      case AutoKind.instrument:
        if (t == null || !t.kind.isInstrument) return null;
        final p = _spec(t.kind, target.param);
        if (p == null) return null;
        return (code: 2, slot: 0, id: p.id, min: p.min, max: p.max, value: t.param(p.id), spec: p);
      case AutoKind.effect:
        final chain = t?.effects ?? doc.masterEffects;
        final k = chain.indexWhere((s) => s.id == target.ref);
        if (k < 0) return null;
        final p = _fxSpec(chain[k].kind, target.param);
        if (p == null) return null;
        return (code: 3, slot: k, id: p.id, min: p.min, max: p.max, value: chain[k].param(p.id), spec: p);
      case AutoKind.send:
        if (t == null) return null;
        final list = sends ?? _validSends(track, _trackIndex());
        final k = list.indexWhere((e) => e.$1.target == target.ref);
        if (k < 0) return null;
        return (code: 4, slot: k, id: 0, min: 0.0, max: maxGain, value: list[k].$1.level, spec: null);
    }
  }

  /// Observação (medidor de efeito e analisador) resolvida pelos ids: segue o slot e a faixa
  /// quando mudam de lugar e desliga quando somem.
  List<List<Object>> _watchCalls() {
    final calls = <List<Object>>[];
    final fx = _watchFxTarget();
    if (fx != _sentWatchFx) {
      calls.add(['watch_fx', fx.$1, fx.$2]);
      _sentWatchFx = fx;
      if (fx.$2 < 0) fxMeter.value = 0;
    }
    final an = _watchAnalyzerTarget();
    if (an != _sentWatchAnalyzer) {
      calls.add(['watch_analyzer', an]);
      _sentWatchAnalyzer = an;
      if (an < -1) spectrum.value = null;
    }
    return calls;
  }

  (int, int) _watchFxTarget() {
    const off = (-1, -1);
    final slotId = _watchFxSlot;
    if (slotId == null) return off;
    final track = _watchFxTrack == null ? -1 : doc.tracks.indexWhere((t) => t.id == _watchFxTrack);
    // faixa apagada: não pode cair no −1, que é o master
    if (_watchFxTrack != null && track < 0) return off;
    final chain = _chain(track);
    if (chain == null) return off;
    final k = chain.indexWhere((s) => s.id == slotId);
    return k < 0 ? off : (track, k);
  }

  int _watchAnalyzerTarget() {
    if (!_watchingAnalyzer) return -2;
    final id = _watchAnalyzerTrack;
    if (id == null) return -1;
    final i = doc.tracks.indexWhere((t) => t.id == id);
    return i < 0 ? -2 : i;
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
    // ligar o metrônomo e o loop não entra no histórico: desfazer uma nota não pode mexer neles.
    // Só quando o passo desfeito foi desenhar a região do loop (que liga o loop) ele volta junto.
    final before = doc;
    doc = DawDoc.fromJson(jsonDecode(from.removeLast()))..metronome = before.metronome;
    if (doc.loopStart == before.loopStart && doc.loopEnd == before.loopEnd) doc.loopOn = before.loopOn;
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
    // a faixa do rack sumiu (apagada, desfeita): o rack passa para a selecionada, nunca cai
    // calado no master
    final fx = _effectsId;
    if (fx != null && !doc.tracks.any((t) => t.id == fx)) {
      _effectsId = selectedTrack < doc.tracks.length ? doc.tracks[selectedTrack].id : null;
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
    _select(n);
  });

  /// Apaga a faixa. Se era um barramento, o que mandava para ele (envios, saídas e a automação
  /// desses envios) sai junto; os sidechains que apontavam para faixas depois dela acompanham a
  /// mudança de índice.
  void removeTrack(int i) {
    if (i < 0 || i >= doc.tracks.length) return;
    edit((d) {
      final gone = d.tracks.removeAt(i);
      _dropRoutesTo(gone.id);
      _remapSidechains((old) => old == i ? -1 : (old > i ? old - 1 : old));
      selectedTrack = math.max(0, math.min(selectedTrack, d.tracks.length - 1));
    });
  }

  /// Duplica a faixa logo abaixo dela: clipes, instrumento, efeitos, envios e automação, com ids
  /// novos (e as automações de efeito apontando para os efeitos da cópia).
  void duplicateTrack(int i) {
    if (i < 0 || i >= doc.tracks.length) return;
    edit((d) {
      final src = d.tracks[i];
      final copy = DawTrack.fromJson(jsonDecode(jsonEncode(src.toJson())))
        ..id = newId()
        ..name = _copyName(src.name);
      final slotIds = <String, String>{};
      for (final e in copy.effects) {
        final old = e.id;
        e.id = newId();
        slotIds[old] = e.id;
      }
      for (final c in copy.clips) {
        c.id = newId();
      }
      for (final m in copy.midi) {
        m.id = newId();
      }
      copy.lanes = [
        for (final l in copy.lanes)
          AutoLane(
            id: newId(),
            target: l.target.kind == AutoKind.effect ? AutoTarget(AutoKind.effect, ref: slotIds[l.target.ref], param: l.target.param) : l.target,
            points: l.points,
            open: l.open,
          ),
      ];
      d.tracks.insert(i + 1, copy);
      // as faixas depois da cópia desceram uma posição: sidechains acompanham
      _remapSidechains((old) => old > i ? old + 1 : old);
      _dropBackwardRoutes();
      selectedTrack = i + 1;
    });
  }

  static String _copyName(String name) {
    final m = RegExp(r'^(.*) \((\d+)\)$').firstMatch(name);
    if (m != null) return '${m.group(1)} (${int.parse(m.group(2)!) + 1})';
    return '$name (2)';
  }

  /// Move a faixa [from] para a posição [to]. A ordem das faixas é a ordem do sinal entre
  /// barramentos: o roteamento de barramento que passar a apontar para trás é desfeito (a faixa
  /// volta ao master, o envio sai). Sidechains seguem as faixas.
  void moveTrack(int from, int to) {
    final n = doc.tracks.length;
    if (from < 0 || from >= n) return;
    to = to.clamp(0, n - 1);
    if (to == from) return;
    edit((d) {
      final selectedId = selectedTrack < n ? d.tracks[selectedTrack].id : null;
      final before = [for (final t in d.tracks) t.id];
      d.tracks.insert(to, d.tracks.removeAt(from));
      final after = _trackIndex();
      _remapSidechains((old) => old < before.length ? after[before[old]] ?? -1 : -1);
      _dropBackwardRoutes();
      if (selectedId != null) selectedTrack = after[selectedId] ?? selectedTrack;
    });
  }

  /// Tira do documento envios e saídas para [busId] e a automação desses envios.
  void _dropRoutesTo(String busId) {
    for (final t in doc.tracks) {
      t.sends.removeWhere((s) => s.target == busId);
      if (t.output == busId) t.output = null;
      t.lanes.removeWhere((l) => l.target.kind == AutoKind.send && l.target.ref == busId);
    }
  }

  /// Desfaz o roteamento de barramento para barramento que ficou contra a ordem das faixas.
  void _dropBackwardRoutes() {
    final index = _trackIndex();
    for (var i = 0; i < doc.tracks.length; i++) {
      final t = doc.tracks[i];
      if (t.kind != TrackKind.bus) continue;
      final bad = {
        for (final s in t.sends)
          if (index.containsKey(s.target) && _routeIndex(i, s.target, index) < 0) s.target,
      };
      t.sends.removeWhere((s) => bad.contains(s.target));
      t.lanes.removeWhere((l) => l.target.kind == AutoKind.send && bad.contains(l.target.ref));
      if (t.output != null && index.containsKey(t.output) && _routeIndex(i, t.output, index) < 0) t.output = null;
    }
  }

  /// Sidechain de compressor e gate é um índice de faixa (contrato da tabela): quando as faixas
  /// mudam de lugar, o índice acompanha a faixa ([map] do índice velho para o novo; −1 desliga).
  void _remapSidechains(int Function(int old) map) {
    for (final chain in [for (final t in doc.tracks) t.effects, doc.masterEffects]) {
      for (final s in chain) {
        final id = _sidechainParam(s.kind);
        if (id == null) continue;
        final old = s.param(id).round();
        if (old < 0) continue;
        final now = map(old);
        if (now != old) s.params[id] = now.toDouble();
      }
    }
  }

  /// Id do parâmetro de sidechain do efeito, se ele tem.
  static int? _sidechainParam(EffectKind k) => switch (k) {
    EffectKind.compressor => 10,
    EffectKind.gate => 6,
    _ => null,
  };

  void selectTrack(int i) {
    _select(i);
    notifyListeners();
  }

  void _select(int i) {
    selectedTrack = i;
    // com o rack aberto, escolher outra faixa mostra os efeitos dela (como o painel de instrumento)
    if (dock == Dock.effects && i >= 0 && i < doc.tracks.length) _effectsId = doc.tracks[i].id;
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
      if (t != null) _select(doc.tracks.indexOf(t));
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
      if (identical(from, to) || to.kind != TrackKind.audio) return;
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

  /// O clipe [id] fica por cima: o que ele cobre dos outros clipes da mesma faixa sai (encurta,
  /// apara o começo, parte em dois ou some), como nos DAWs. Sem isso, clipes sobrepostos tocavam
  /// somados (áudio dobrado). Não faz checkpoint: vai junto da edição que o chamou.
  void placeOnTop(String id) {
    final bpm = doc.bpm;
    final a = _findClip(id);
    if (a != null) {
      final (t, top) = a;
      final s = top.start, e = top.end(bpm);
      for (final o in t.clips.toList()) {
        if (identical(o, top) || o.end(bpm) <= s + 1e-9 || o.start >= e - 1e-9) continue;
        final oEnd = o.end(bpm);
        if (o.start >= s - 1e-9 && oEnd <= e + 1e-9) {
          t.clips.remove(o);
        } else if (o.start < s && oEnd > e) {
          final cut = (e - o.start) * 60 / bpm;
          t.clips.add(
            AudioClip.fromJson(o.toJson())
              ..id = newId()
              ..start = e
              ..offset = o.offset + cut
              ..length = o.length - cut
              ..fadeIn = 0,
          );
          o
            ..length = (s - o.start) * 60 / bpm
            ..fadeOut = 0;
        } else if (o.start < s) {
          o
            ..length = (s - o.start) * 60 / bpm
            ..fadeOut = math.min(o.fadeOut, (s - o.start) * 60 / bpm);
        } else {
          final cut = (e - o.start) * 60 / bpm;
          o
            ..start = e
            ..offset = o.offset + cut
            ..length = o.length - cut
            ..fadeIn = 0;
        }
      }
      return;
    }
    final m = findMidiClip(id);
    if (m == null) return;
    final (t, top) = m;
    final s = top.start, e = top.end;
    for (final o in t.midi.toList()) {
      if (identical(o, top) || o.end <= s + 1e-9 || o.start >= e - 1e-9) continue;
      if (o.start >= s - 1e-9 && o.end <= e + 1e-9) {
        t.midi.remove(o);
        if (editingClip == o.id) editingClip = null;
      } else if (o.start < s && o.end > e) {
        final d = e - o.start;
        t.midi.add(
          MidiClip.fromJson(o.toJson())
            ..id = newId()
            ..start = e
            ..length = o.end - e
            ..notes = [for (final n in o.notes) n.copy()..start = n.start - d],
        );
        o.length = s - o.start;
      } else if (o.start < s) {
        o.length = s - o.start;
      } else {
        // as notas ficam no mesmo lugar absoluto (as de antes do novo começo não tocam mais)
        final d = e - o.start;
        o
          ..start = e
          ..length = o.length - d;
        for (final n in o.notes) {
          n.start -= d;
        }
      }
    }
    if (editingClip == null && dock == Dock.editor) dock = Dock.none;
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
        placeOnTop(copy.id);
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
      placeOnTop(copy.id);
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
        if (ti >= doc.tracks.length ||
            doc.tracks[ti].kind != TrackKind.audio ||
            i > 0 ||
            _occupied(doc.tracks[ti], start, start + info.duration * doc.bpm / 60)) {
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
    if (kind == TrackKind.bus) {
      addBusTrack();
      return;
    }
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
      _select(n);
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
      _select(track);
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

  /// Troca o painel de baixo. O editor sem clipe aberto pega o clipe MIDI selecionado; o rack de
  /// efeitos aberto pela aba mostra a faixa selecionada (o master é escolha explícita, por
  /// [showEffects] ou [effectsTrack]).
  void setDock(Dock d) {
    if (d == Dock.editor && editing == null) {
      final m = midiSelection;
      if (m != null) editingClip = m.$2.id;
    }
    if (d == Dock.effects && dock != Dock.effects && selectedTrack < doc.tracks.length) _effectsId = doc.tracks[selectedTrack].id;
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

  // ------------------------------------------------------------------ efeitos, roteamento, automação
  // Faixa −1 é o master.

  /// Faixa do rack que o painel mostra, pelo id (null = master): segue a faixa se ela muda de lugar.
  String? _effectsId;

  /// Faixa cujo rack de efeitos o painel mostra (−1 = master).
  int get effectsTrack {
    final id = _effectsId;
    return id == null ? -1 : doc.tracks.indexWhere((t) => t.id == id);
  }

  set effectsTrack(int track) {
    final id = track >= 0 && track < doc.tracks.length ? doc.tracks[track].id : null;
    if (id == _effectsId) return;
    _effectsId = id;
    notifyListeners();
  }

  /// Mostra os efeitos de uma faixa (ou do master, −1) no painel de baixo; a faixa fica selecionada.
  void showEffects(int track) {
    final valid = track >= 0 && track < doc.tracks.length;
    _effectsId = valid ? doc.tracks[track].id : null;
    if (valid) selectedTrack = track;
    dock = Dock.effects;
    notifyListeners();
  }

  /// A cadeia de uma faixa ou do master, viva (null se a faixa não existe).
  List<EffectSlot>? _chain(int track) => track == -1 ? doc.masterEffects : (track >= 0 && track < doc.tracks.length ? doc.tracks[track].effects : null);

  List<AutoLane>? _lanes(int track) => track == -1 ? doc.masterLanes : (track >= 0 && track < doc.tracks.length ? doc.tracks[track].lanes : null);

  /// A cadeia de efeitos de uma faixa ou do master, só leitura (vazia se a faixa não existe). Para
  /// mudar, os métodos abaixo.
  List<EffectSlot> effectsOf(int track) {
    final chain = _chain(track);
    return chain == null ? const [] : UnmodifiableListView(chain);
  }

  (List<EffectSlot>, EffectSlot)? _findSlot(int track, String slotId) {
    final chain = _chain(track);
    if (chain == null) return null;
    for (final s in chain) {
      if (s.id == slotId) return (chain, s);
    }
    return null;
  }

  static ParamSpec? _fxSpec(EffectKind kind, int id) {
    for (final p in kind.params) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Adiciona um efeito no padrão no fim da cadeia (ou na posição [at]); desfazível.
  EffectSlot addEffect(int track, EffectKind kind, {int? at}) {
    final chain = _chain(track);
    if (chain == null) throw ArgumentError.value(track, 'track', 'faixa inexistente');
    final slot = EffectSlot(id: newId(), kind: kind);
    edit((_) => chain.insert((at ?? chain.length).clamp(0, chain.length), slot));
    return slot;
  }

  /// Tira o efeito da cadeia, com a automação que apontava para ele; desfazível.
  void removeEffect(int track, String slotId) {
    final f = _findSlot(track, slotId);
    if (f == null) return;
    edit((_) {
      f.$1.remove(f.$2);
      _lanes(track)!.removeWhere((l) => l.target.kind == AutoKind.effect && l.target.ref == slotId);
    });
  }

  /// Leva o efeito para a posição [to] da cadeia (índice final dele); desfazível.
  void moveEffect(int track, String slotId, int to) {
    final f = _findSlot(track, slotId);
    if (f == null) return;
    final (chain, slot) = f;
    final from = chain.indexOf(slot);
    final dest = to.clamp(0, chain.length - 1);
    if (dest == from) return;
    edit((_) => chain.insert(dest, chain.removeAt(from)));
  }

  /// Muda um parâmetro de efeito pelo caminho rápido (só a chamada `fx_param`). Para arrastes:
  /// [checkpoint] no começo e `undoable: false`.
  void setEffectParam(int track, String slotId, int id, double value, {bool undoable = false}) {
    final f = _findSlot(track, slotId);
    if (f == null) return;
    final (chain, slot) = f;
    final spec = _fxSpec(slot.kind, id);
    if (spec == null) return;
    final v = _fit(spec, value);
    if (slot.params.containsKey(id) && slot.params[id] == v) return;
    if (undoable) checkpoint();
    slot.params[id] = v;
    final k = chain.indexOf(slot);
    final sent = track == -1 ? _sentMaster : (track < _sent.length ? _sent[track].fx : null);
    final s = sent != null && k < sent.slots.length ? sent.slots[k] : null;
    if (s != null && s.kind == slot.kind) {
      _engine.calls([
        ['fx_param', track, k, id, v],
      ]);
      s.params[id] = v;
    } else {
      // o motor ainda não tem este efeito neste slot: um fx_param solto cairia noutro efeito
      _sync();
    }
    _scheduleSave();
    notifyListeners();
  }

  /// Liga ou desliga o bypass do efeito; desfazível.
  void setEffectBypass(int track, String slotId, bool bypass) {
    final f = _findSlot(track, slotId);
    if (f == null || f.$2.bypass == bypass) return;
    edit((_) => f.$2.bypass = bypass);
  }

  /// Aplica um preset ao efeito: o que falta volta ao padrão, menos o sidechain (é roteamento, não
  /// timbre: um preset não sabe das faixas deste projeto). Desfazível.
  void applyEffectPreset(int track, String slotId, Map<int, double> values) {
    final f = _findSlot(track, slotId);
    if (f == null) return;
    final slot = f.$2;
    final sc = _sidechainParam(slot.kind);
    edit((_) {
      slot.params = {for (final p in slot.kind.params) p.id: _fit(p, values[p.id] ?? (p.id == sc ? slot.param(p.id) : p.def))};
    });
  }

  /// Nova faixa barramento ("Barramento N") no fim, selecionada. No fim porque barramento só
  /// manda para barramento depois dele: assim todos os outros podem mandar para ela.
  DawTrack addBusTrack() {
    late DawTrack bus;
    edit((d) {
      final n = d.tracks.length;
      final names = {for (final t in d.tracks) t.name};
      var k = d.tracks.where((t) => t.kind == TrackKind.bus).length + 1;
      while (names.contains('${TrackKind.bus.label} $k')) {
        k++;
      }
      bus = DawTrack(id: newId(), name: '${TrackKind.bus.label} $k', color: n % Palette.tracks.length, kind: TrackKind.bus);
      d.tracks.add(bus);
      _select(n);
    });
    return bus;
  }

  /// Cria ou muda o envio da faixa para o barramento [busId]. Envio novo nasce em −6 dB
  /// pós-fader (e é sempre desfazível); mudar o nível de um que existe vai pelo caminho rápido,
  /// como um parâmetro (para arrastes: [checkpoint] no começo e `undoable: false`). Recusa (false)
  /// destino que não é barramento ou que fecharia um ciclo.
  bool setSend(int track, String busId, {double? level, bool? pre, bool undoable = false}) {
    if (!busTargets(track).any((b) => b.id == busId)) return false;
    final t = doc.tracks[track];
    final lv = level == null || level.isNaN ? null : _sendLevel(level);
    final send = t.sends.where((s) => s.target == busId).firstOrNull;
    if (send == null) {
      edit((_) => t.sends.add(Send(target: busId, level: lv ?? defaultSendLevel, pre: pre ?? false)));
      return true;
    }
    final newLevel = lv ?? send.level, newPre = pre ?? send.pre;
    if (newLevel == send.level && newPre == send.pre) return true;
    if (undoable) checkpoint();
    send
      ..level = newLevel
      ..pre = newPre;
    final valid = _validSends(track, _trackIndex());
    final k = valid.indexWhere((e) => identical(e.$1, send));
    final s = track < _sent.length ? _sent[track] : null;
    if (s != null && k >= 0 && k < s.sends.length) {
      final v = (valid[k].$2, _sendLevel(newLevel), newPre);
      _engine.calls([
        ['send_set', track, k, v.$1, v.$2, v.$3],
      ]);
      s.sends[k] = v;
    } else {
      _sync();
    }
    _scheduleSave();
    notifyListeners();
    return true;
  }

  /// Tira o envio (e a automação dele); desfazível.
  void removeSend(int track, String busId) {
    if (track < 0 || track >= doc.tracks.length) return;
    final t = doc.tracks[track];
    if (!t.sends.any((s) => s.target == busId)) return;
    edit((_) {
      t.sends.removeWhere((s) => s.target == busId);
      t.lanes.removeWhere((l) => l.target.kind == AutoKind.send && l.target.ref == busId);
    });
  }

  /// Barramentos para onde a faixa pode enviar ou sair sem criar ciclo: qualquer um para faixa
  /// comum; para um barramento, só os que vêm depois dele na lista (ver [_routeIndex]). O master
  /// não envia.
  List<DawTrack> busTargets(int track) {
    if (track < 0 || track >= doc.tracks.length) return const [];
    final index = _trackIndex();
    return [
      for (final t in doc.tracks)
        if (_routeIndex(track, t.id, index) >= 0) t,
    ];
  }

  /// Saída da faixa: um barramento (id) ou null para o master. Recusa (false) ciclo e destino que
  /// não é barramento; desfazível.
  bool setOutput(int track, String? busId) {
    if (track < 0 || track >= doc.tracks.length) return false;
    if (busId != null && !busTargets(track).any((b) => b.id == busId)) return false;
    final t = doc.tracks[track];
    if (t.output == busId) return true;
    edit((_) => t.output = busId);
    return true;
  }

  /// Alvos automatizáveis da faixa (ou do master), com o nome para o menu: volume, pan,
  /// parâmetros do instrumento, de cada efeito e o nível de cada envio. O sidechain fica de fora
  /// (é escolha de faixa, não um valor que anda).
  List<(AutoTarget, String)> automatable(int track) {
    final chain = _chain(track);
    if (chain == null) return const [];
    final out = <(AutoTarget, String)>[(const AutoTarget(AutoKind.volume), 'Volume'), (const AutoTarget(AutoKind.pan), 'Pan')];
    final t = track >= 0 ? doc.tracks[track] : null;
    if (t != null && t.kind.isInstrument) {
      for (final p in t.kind.params) {
        out.add((AutoTarget(AutoKind.instrument, param: p.id), 'Instrumento · ${_paramLabel(t.kind.params, p)}'));
      }
    }
    final count = <EffectKind, int>{};
    for (final s in chain) {
      count[s.kind] = (count[s.kind] ?? 0) + 1;
    }
    final seen = <EffectKind, int>{};
    for (final s in chain) {
      final n = seen[s.kind] = (seen[s.kind] ?? 0) + 1;
      // dois do mesmo tipo na cadeia: numerados, senão o menu teria nomes iguais
      final name = count[s.kind]! > 1 ? '${s.kind.label} $n' : s.kind.label;
      final sc = _sidechainParam(s.kind);
      for (final p in s.kind.params) {
        if (p.id == sc) continue;
        out.add((AutoTarget(AutoKind.effect, ref: s.id, param: p.id), '$name · ${_paramLabel(s.kind.params, p)}'));
      }
    }
    if (t != null) {
      for (final s in t.sends) {
        final bus = doc.tracks.where((b) => b.id == s.target).firstOrNull;
        if (bus != null) out.add((AutoTarget(AutoKind.send, ref: s.target), 'Envio → ${bus.name}'));
      }
    }
    return out;
  }

  /// Nome do parâmetro para o menu, com o grupo quando o nome se repete (as duas "Onda" do
  /// sintetizador, as bandas do EQ, as peças da bateria).
  static String _paramLabel(List<ParamSpec> params, ParamSpec p) {
    final repeated = params.any((q) => !identical(q, p) && q.name == p.name);
    return repeated ? '${p.name} (${p.group})' : p.name;
  }

  /// Nome de um alvo de automação da faixa (o mesmo do menu), ou null se ele não existe mais.
  String? targetName(int track, AutoTarget target) {
    for (final (t, name) in automatable(track)) {
      if (t == target) return name;
    }
    return null;
  }

  /// Nova faixa de automação para o alvo, vazia e aberta (a interface põe os pontos); se já
  /// existe uma para ele, só abre. Criar é desfazível.
  AutoLane addLane(int track, AutoTarget target) {
    final lanes = _lanes(track);
    if (lanes == null) throw ArgumentError.value(track, 'track', 'faixa inexistente');
    if (!automatable(track).any((e) => e.$1 == target)) throw ArgumentError.value(target.toJson(), 'target', 'a faixa não tem este alvo');
    final existing = lanes.where((l) => l.target == target).firstOrNull;
    if (existing != null) {
      if (!existing.open) {
        existing.open = true;
        _scheduleSave();
        notifyListeners();
      }
      return existing;
    }
    final lane = AutoLane(id: newId(), target: target);
    edit((_) => lanes.add(lane));
    return lane;
  }

  /// Apaga a faixa de automação (o parâmetro volta ao valor fixo); desfazível.
  void removeLane(int track, String laneId) {
    final lanes = _lanes(track);
    if (lanes == null || !lanes.any((l) => l.id == laneId)) return;
    edit((_) => lanes.removeWhere((l) => l.id == laneId));
  }

  /// Mínimo, máximo e valor atual (sem automação) de um alvo, na unidade dele (ganho linear no
  /// volume e nos envios, −1..1 no pan, a da tabela nos parâmetros), para desenhar e editar.
  /// Alvo que não existe mais: (0, 1, 0).
  (double, double, double) targetRange(int track, AutoTarget target) {
    final r = _resolve(track, target);
    return r == null ? (0.0, 1.0, 0.0) : (r.min, r.max, r.value);
  }

  // observação pedida pela interface, pelos ids (null = master)
  String? _watchFxTrack, _watchFxSlot;
  bool _watchingAnalyzer = false;
  String? _watchAnalyzerTrack;

  /// Efeito cujo indicador (redução de ganho) o motor manda em [fxMeter]; null desliga. Segue o
  /// slot se ele muda de lugar.
  void watchEffect(int track, String? slotId) {
    final valid = track == -1 || (track >= 0 && track < doc.tracks.length);
    _watchFxSlot = valid ? slotId : null;
    _watchFxTrack = valid && track >= 0 ? doc.tracks[track].id : null;
    final calls = _watchCalls();
    if (calls.isNotEmpty) _engine.calls(calls);
  }

  /// Faixa cujo espectro o motor manda em [spectrum] (−1 master); null desliga.
  void watchAnalyzer(int? track) {
    final valid = track == -1 || (track != null && track >= 0 && track < doc.tracks.length);
    _watchingAnalyzer = valid;
    _watchAnalyzerTrack = valid && track! >= 0 ? doc.tracks[track].id : null;
    final calls = _watchCalls();
    if (calls.isNotEmpty) _engine.calls(calls);
  }

  /// Indicador do efeito observado (redução de ganho em dB, ≥ 0) e espectro da faixa observada
  /// (dB por faixa linear de frequência, de 0 à metade da taxa), ao vivo.
  final fxMeter = ValueNotifier<double>(0);
  final spectrum = ValueNotifier<Float32List?>(null);

  /// Taxa de amostragem do motor (a do contexto de áudio do aparelho: 44,1 ou 48 kHz, em geral):
  /// o espectro vai de 0 à metade dela.
  double engineRate = 48000;

  // ------------------------------------------------------------------ gravação, exportação, bounce
  // (contrato da fase 4: corpos preenchidos na implementação)

  /// Gravando agora (inclusive durante a contagem) e em que fase.
  bool recording = false;
  bool countingIn = false;

  /// Nível de pico da entrada (0..1), ao vivo, para o medidor das faixas armadas.
  final inputLevel = ValueNotifier<double>(0);

  /// Entradas de áudio disponíveis (id, nome) e a escolhida (null = a padrão do sistema).
  List<(String, String)> inputDevices = const [];
  String? inputDevice;

  /// Liga/desliga a gravação: com faixas armadas, conta um compasso (se [DawDoc.countIn]) e grava
  /// a partir do cursor; parar gera os clipes (áudio nas de áudio, notas nas de instrumento).
  Future<void> toggleRecord() => throw UnimplementedError();

  void setArmed(int track, bool on) => throw UnimplementedError();
  void setMonitor(int track, bool on) => throw UnimplementedError();

  /// Pede acesso ao microfone (se ainda não tem) e lista as entradas.
  Future<void> refreshInputDevices() => throw UnimplementedError();
  Future<void> setInputDevice(String? id) => throw UnimplementedError();

  /// Troca a tomada ativa de um clipe gravado em loop.
  void switchTake(String clipId, String sampleHash) => throw UnimplementedError();

  /// Renderiza fora de tempo real (mais rápido que tocando) e salva os arquivos.
  Future<void> exportAudio(ExportOptions options, {void Function(double progress)? onProgress}) => throw UnimplementedError();

  /// Congela a faixa em áudio: renderiza ela (com instrumento e efeitos) numa faixa de áudio nova
  /// logo abaixo e muda a original.
  Future<void> bounceTrack(int track, {void Function(double progress)? onProgress}) => throw UnimplementedError();

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
