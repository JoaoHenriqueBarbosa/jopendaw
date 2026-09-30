/// O cérebro da tela do projeto: guarda o documento, o histórico de desfazer, a seleção e a visão
/// (zoom e rolagem), e mantém o motor de áudio e o guardado local em dia com cada edição.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart'
    show
        GestureBinding,
        PointerCancelEvent,
        PointerDeviceKind,
        PointerDownEvent,
        PointerEvent,
        PointerHoverEvent,
        PointerMoveEvent,
        PointerUpEvent,
        kPrimaryButton;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show EditableText, FocusManager;

import '../api/client.dart';
import '../api/sync_api.dart';
import '../auth/session.dart';
import '../audio/engine.dart';
import '../models/project.dart';
import '../platform/platform.dart' show keepScreenOn, watchAudioSession;
import '../widgets/theme.dart';
import 'audio_to_midi.dart';
import 'automation_math.dart';
import 'automation_record.dart';
import 'effects.dart';
import 'export_options.dart';
import 'instruments.dart';
import 'keymap.dart' show Keymap;
import 'loudness.dart';
import 'midi_cc.dart';
import 'midi_file.dart';
import 'midi_learn.dart';
import 'model.dart';
import 'modulation.dart';
import 'sync.dart';
import 'tempo_map.dart';
import 'templates.dart';
import 'track_groups.dart' show DawGroupsController, planTrackMove;
import 'warp.dart';
import 'wav.dart';

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
enum Dock { none, mixer, editor, instrument, effects, modulation }

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

/// Altura das faixas na linha do tempo (P/M/G no menu Visão).
enum LaneScale {
  small('Pequena', 'P', 0.7),
  medium('Média', 'M', 1),
  large('Grande', 'G', 1.5);

  final String label, letter;
  final double factor;
  const LaneScale(this.label, this.letter, this.factor);
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
  // os eventos de controle se dividem junto: o pedal que estava embaixo no corte começa o clipe da
  // direita embaixo
  final (leftCc, rightCc) = splitControls(clip.controls, cut);
  final r = MidiClip(id: newId(), name: clip.name, start: at, length: clip.length - cut, notes: right, controls: rightCc);
  clip
    ..length = cut
    ..notes = left
    ..controls = leftCc;
  return r;
}

// ------------------------------------------------------------------ gravação (funções puras)

/// Onde cada passada de uma gravação começa: a batida na linha do tempo e o quadro da gravação
/// (contado do início dela). Sem loop (ou começando depois do fim dele) é uma passada só; com
/// loop, uma a cada volta, até [frames].
///
/// Simula o transporte do motor quadro a quadro: ele anda em quadros inteiros e volta ao início do
/// loop no primeiro quadro em que a posição alcança o fim, levando a fração que passou. Assim a
/// divisão cai no mesmo quadro da volta que se ouviu, sem deriva ao longo de muitas passadas.
List<({double beat, int frame})> recordingPasses({
  required double start,
  required int frames,
  required double bpm,
  required double rate,
  bool loopOn = false,
  double loopStart = 0,
  double loopEnd = 0,
  TempoMap? tempo,
}) {
  final passes = [(beat: start, frame: 0)];
  final fpb = rate * 60 / bpm;
  // com mapa de andamento as batidas viram quadros pelo mapa (a mesma conta do motor)
  final map = tempo != null && !tempo.isSingle ? tempo : null;
  double frames_(double beat) => map == null ? beat * fpb : map.secondsAt(beat) * rate;
  final ls = frames_(math.max(0.0, loopStart)), le = frames_(math.max(0.0, loopEnd));
  var pos = frames_(math.max(0.0, start));
  var k = 0;
  // o motor só volta quando a posição está antes do fim (depois dele o loop segue reto)
  if (!loopOn || le <= ls || pos >= le || le - ls < 1) return passes;
  while (true) {
    final until = math.max(1, (le - pos).ceil());
    if (k + until >= frames) break;
    k += until;
    pos = ls + (pos + until - le);
    passes.add((beat: loopStart, frame: k));
  }
  return passes;
}

/// Os quadros [from, to) de uma sequência de blocos, copiados em [out] a partir de [at]. O que cai
/// antes do começo ou depois do fim dos blocos fica em silêncio.
void gatherFrames(List<Float32List> blocks, int from, int to, Float32List out, [int at = 0]) {
  var pos = 0;
  for (final b in blocks) {
    final end = pos + b.length;
    final s = math.max(from, pos), e = math.min(to, end);
    if (s < e) out.setRange(at + s - from, at + e - from, b, s - pos);
    pos = end;
    if (pos >= to) break;
  }
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

/// Oitava abaixo/acima e velocidade menor/maior são ações do `Keymap` (contexto "teclado tocando"; padrão Z X C V).

/// Nota MIDI que uma tecla toca com o teclado na oitava [octave] (4 = dó central na tecla A), ou
/// null se a tecla não é de nota.
int? keyboardNote(PhysicalKeyboardKey key, int octave) {
  final i = noteKeys.indexOf(key);
  if (i < 0) return null;
  final pitch = (octave + 1) * 12 + i;
  return pitch >= 0 && pitch <= 127 ? pitch : null;
}

bool _isKeyboardKey(PhysicalKeyboardKey k) => noteKeys.contains(k) || Keymap.instance.playingAction(k) != null;

/// O que o motor já recebeu de uma faixa (tipo, parâmetros, áudio do sampler, efeitos, envios,
/// saída): o sync só manda o que mudou, senão um arraste mandaria centenas de parâmetros por quadro.
class _SentTrack {
  final TrackKind kind;
  final params = <int, double>{};
  int sample = 0;

  /// As chamadas de zonas do sampler que o motor já recebeu (só o sampler tem).
  List<List<Object>> zones = const [];
  final fx = _SentChain();

  /// Envios como o motor os conhece: (índice do barramento, nível, pré-fader), só os válidos.
  final sends = <(int, double, bool)>[];
  int sendCount = -1;

  /// Índice do barramento de saída (−1 master); null: ainda não foi.
  int? output;
  _SentTrack(this.kind);
}

/// O que um motor já recebeu do documento. O ao vivo guarda o dele (o sync só manda a diferença);
/// o render fora de tempo real parte de um vazio e recebe a lista completa.
class _SyncCache {
  final tracks = <_SentTrack>[];
  List<String> ids = const [];
  List<EngineNote>? notes;

  /// Eventos de controle (bend, modulação, pedal) que o motor tem; vazio até o primeiro clipe com
  /// controles (documentos sem eles nunca mandam `cc_clear`). Null: o motor pode ter eventos velhos.
  List<EngineCc>? ccs = const [];
  final master = _SentChain();
  List<List<Object>>? auto;

  /// A modulação como chamadas (`mod_source` e `mod_dest`) que o motor tem; vazia até a primeira.
  List<List<Object>> mod = const [];

  /// O mapa de andamento e o de compassos que o motor tem, como texto ('' = um andamento e um
  /// compasso só): só reenvia quando muda.
  String tempoSig = '', meterSig = '';
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

/// Uma gravação em andamento: o que foi armado, onde ela vale e o que a entrada mandou.
class _Recording {
  _Recording({
    required this.start,
    required this.bpm,
    required this.rate,
    required this.loopOn,
    required this.loopStart,
    required this.loopEnd,
    required this.trackIds,
    required this.audioIds,
    required this.midiIds,
    required this.audio,
    required this.countBeats,
    required this.zone,
    required this.latency,
    this.midiLatency = 0,
    required this.skip,
    required this.metronomeTemp,
    this.startFromCapture = false,
    TempoMap? tempo,
  }) : stopBeat = start,
       tempo = tempo ?? TempoMap.constant(bpm);

  /// Batida onde a gravação vale (o cursor quando ela começou).
  double start;

  /// Começou com o transporte andando: [start] é só uma estimativa (a posição que a tela tinha)
  /// até o primeiro bloco da captura chegar com a batida exata do primeiro quadro dele.
  bool startFromCapture;
  final double bpm, rate;

  /// O mapa de andamento quando a gravação começou (o de um andamento só, sem mapa).
  final TempoMap tempo;

  /// Quadros entre duas batidas pelo andamento da gravação (exato como antes quando não há mapa).
  double framesBetween(double from, double to) => tempo.isSingle ? (to - from) * rate * 60 / bpm : (tempo.secondsAt(to) - tempo.secondsAt(from)) * rate;

  /// O loop no começo: a volta dele divide as passadas.
  final bool loopOn;
  final double loopStart, loopEnd;

  /// Ids das faixas na ordem do motor no começo: as notas gravadas vêm com o índice.
  final List<String> trackIds;
  final Set<String> audioIds, midiIds;

  /// A entrada estava aberta: há áudio para juntar.
  final bool audio;

  /// Batidas de contagem antes de [start] (0: sem contagem).
  final double countBeats;

  /// Contagem fora do lugar (cursor antes do fim do primeiro compasso, ou o fim do loop dentro do
  /// compasso da contagem): a batida do motor onde ela começa, numa região vazia bem depois do fim
  /// de tudo; null quando ela toca antes do cursor.
  final double? zone;

  /// Latência total da gravação (s): a do motor (PDC, cadeia do master, limitador), a do aparelho
  /// (contexto e entrada) e a compensação manual.
  final double latency;

  /// Quanto o som sai depois do transporte (s): a latência do motor mais a de saída do aparelho. As
  /// notas tocadas ouvindo o que soa chegam esse tanto atrasadas e voltam para antes.
  final double midiLatency;

  /// A batida [b] adiantada de [midiLatency] (pelo mapa de andamento da gravação).
  double shiftBeat(double b) {
    if (!(midiLatency > 0) || !b.isFinite) return b;
    return math.max(0.0, tempo.beatAt(tempo.secondsAt(b) - midiLatency));
  }

  /// Quadros descartados do começo do que a entrada mandou: a contagem e a latência (negativo:
  /// silêncio acrescentado).
  final int skip;

  /// O metrônomo liga só para a contagem (estava desligado).
  final bool metronomeTemp;

  /// Blocos da entrada (esq, dir), do mesmo tamanho aos pares, e quantos quadros somam.
  final left = <Float32List>[], right = <Float32List>[];
  int frames = 0;

  /// A captura está ligada no motor.
  bool captureOn = false;

  /// Não aceita mais blocos (cancelada ou já juntada).
  bool closed = false;

  /// O metrônomo provisório e a automação já voltaram.
  bool preRollDone = false;

  /// Onde o transporte estava ao parar (estimado).
  double stopBeat;

  final clock = Stopwatch()..start();

  /// Quanto durou, do começo ao stop (nos testes, dado no lugar do relógio).
  Duration? elapsed;

  /// Batidas gravadas depois da contagem, pelo relógio: as notas não dizem em que passada caíram.
  double get recordedBeats {
    final secs = (elapsed ?? clock.elapsed).inMicroseconds / 1e6;
    if (tempo.isSingle) return secs * bpm / 60 - countBeats;
    // a contagem toca no andamento de onde estiver; aqui basta o do começo da gravação
    return tempo.beatAt(tempo.secondsAt(start) + secs - countBeats * 60 / tempo.bpmAt(start)) - start;
  }
}

/// Um pedaço de áudio gravado que vira sample: quadros [from, to) da gravação, com [pad] quadros de
/// silêncio antes (a tomada que começou no meio do loop).
typedef _Piece = ({int from, int to, int pad});

/// Um clipe da gravação: começa em [start] (batidas) e dura [seconds]; uma peça é um clipe comum,
/// várias são as tomadas dele, e [active] é a que toca (a última passada completa).
typedef _ClipPlan = ({double start, double seconds, List<_Piece> pieces, int active});

/// Uma nota gravada, em batidas absolutas.
typedef _RecNote = ({int pitch, double start, double end, double velocity});

/// Um evento de controle gravado (bend, modulação, pedal), em batidas absolutas.
typedef _RecCc = ({int cc, double beat, double value});

/// Ganho máximo do clipe de áudio: +12 dB.
final maxClipGain = math.pow(10, 12 / 20).toDouble();

/// Ganho máximo do volume e dos envios: o topo do fader (+6 dB).
const maxGain = 2.0;

/// Nível de um envio novo: −6 dB.
const defaultSendLevel = 0.5;

/// A ponta do controlador que o serviço de sincronização enxerga.
class _SyncBridge implements SyncHost {
  _SyncBridge(this.c);
  final DawController c;

  @override
  Map<String, dynamic> docJson() => c.doc.toJson();

  @override
  Set<String> sampleHashes() => DawController._hashesOf(c.doc);

  @override
  Future<bool> applyRemote(Map<String, dynamic> doc, {required void Function(int done, int total) progress, required bool Function() canSwap}) =>
      c._applyRemote(doc, progress, canSwap);

  @override
  Future<void> fetchMissing() => c._fetchMissing();

  @override
  bool get busyEditing => c.recording || c.playing.value || c._gestureInProgress;
}

class DawController extends ChangeNotifier {
  final Project project;

  /// [engine] e [store] trocam o motor e o guardado local nos testes (padrão: os do aparelho);
  /// [api] e [canSync] trocam o servidor e a checagem de sessão da sincronização e dos jobs, e
  /// [syncTimeScale] encurta as esperas dela.
  DawController(
    this.project, {
    AudioEngine? engine,
    LocalStore? store,
    SyncApi? api,
    bool Function()? canSync,
    this.syncTimeScale = 1,
    Future<void> Function(String id, Map<String, dynamic> patch)? patchProject,
  }) : _engine = engine ?? AudioEngine.instance,
       _patchProject = patchProject ?? ((id, patch) => ApiClient.instance.patchProject(id, patch)),
       _store = store ?? LocalStore.instance,
       _api = api ?? ApiClient.instance,
       _canSync = canSync ?? (() => Session.instance.signedIn) {
    autoRec = AutoRecorder(this);
  }

  /// Gravação de automação (Escrever, Toque, Trava) ao mexer nos controles tocando.
  late final AutoRecorder autoRec;

  /// MIDI learn: controles do teclado mapeados a parâmetros (o mapa mora em [DawDoc.midiMap]).
  MidiLearn? _learn;
  MidiLearn get midiLearn => _learn ??= MidiLearn(this);

  final Future<void> Function(String id, Map<String, dynamic> patch) _patchProject;
  final AudioEngine _engine;
  final LocalStore _store;

  /// O guardado local do aparelho (o padrão do MIDI learn para novos projetos mora nele).
  LocalStore get localStore => _store;
  final SyncApi _api;
  final bool Function() _canSync;
  final double syncTimeScale;

  SyncService? _syncService;

  /// Sincronização deste projeto com o servidor (estado na barra do transporte).
  SyncService get sync =>
      _syncService ??= SyncService(projectId: project.id, api: _api, store: _store, host: _SyncBridge(this), canSync: _canSync, timeScale: syncTimeScale);

  /// O documento desta abertura veio de um modelo escolhido ao criar o projeto.
  bool _templated = false;

  /// O último documento gravado no aparelho: só o que difere dele conta como mudança a enviar.
  String? _lastSaved;

  late DawDoc doc;
  bool ready = false;
  String? error;

  /// Aviso informativo de uma ação que terminou (não é erro): "2 crossfades aplicados". A tela o
  /// mostra em destaque até ser dispensado ([clearNotice]).
  String? notice;

  /// Mensagem de trabalho em andamento (importação), na barra do transporte.
  String? status;

  // estado ao vivo do motor: notifiers próprios para não redesenhar a tela inteira a 60 Hz
  final beat = ValueNotifier<double>(0);
  final playing = ValueNotifier<bool>(false);
  final peaks = ValueNotifier<Float32List>(Float32List(0));

  /// Notas tocando ao vivo agora (teclado, MIDI, prévia), em qualquer faixa: o teclado do piano
  /// roll acende as teclas por aqui.
  final liveNotes = ValueNotifier<Set<int>>(const {});

  /// Sobe a cada vez que o app devolve ao repouso o bend, a roda e o pedal ao vivo (parar, reset
  /// do MIDI…): as rodas da tela escutam e voltam ao zero, sem mandar valor de novo.
  final liveReset = ValueNotifier<int>(0);

  final waveforms = <String, Waveform>{};
  final _sampleIds = <String, int>{};

  /// Os sons derivados do warp (esticados, transpostos, invertidos) dos clipes.
  late final WarpCache _warp = WarpCache(
    engine: _engine,
    store: _store,
    source: (sha) {
      final id = _sampleIds[sha];
      return id == null ? null : _decoded[id];
    },
    register: (key, audio) {
      // mesmo caminho do `_register`, sem forma de onda nem `missing`: o derivado não é um áudio do projeto
      final id = _sampleIds['warp:$key'] ??= _sampleIds.length + 1;
      _engine.loadSample(id, audio);
      _decoded[id] = audio;
      return id;
    },
    drop: (key, id) {
      _engine.calls([
        ['sample_drop', id],
      ]);
      _decoded.remove(id);
    },
    onChange: () {
      if (_disposed) return;
      _sync();
      notifyListeners();
    },
    debounce: warpDebounce,
  );

  /// Espera antes de refazer os sons do warp depois de uma mudança (os testes zeram).
  Duration warpDebounce = const Duration(milliseconds: 400);

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

  /// Altura das faixas e o modo da régua (compassos ou mm:ss): só visão, fora do documento.
  LaneScale laneScale = LaneScale.medium;
  bool rulerTime = false;

  /// Marcador selecionado na régua (para "loop entre marcadores").
  String? selectedMarker;

  /// Largura visível das raias em pixels (a linha do tempo informa a cada layout).
  double viewWidth = 800;

  /// Painel de baixo: nenhum, mixer, editor de notas (piano roll) ou instrumento da faixa.
  Dock dock = Dock.none;
  bool get mixerOpen => dock == Dock.mixer;

  /// Clipe MIDI aberto no piano roll.
  String? editingClip;

  /// Teclado do computador tocando notas na faixa selecionada (e oitava base dele).
  bool keyboardOn = false;
  final _keyboardOctaves = <TrackKind, int>{TrackKind.drums: 2};

  /// Oitava base do teclado do computador na faixa que ele toca. É uma por tipo de faixa, como no
  /// teclado da tela: a bateria só responde a notas 35–59, então nela a tecla A cai em C2 (36).
  int get keyboardOctave => _keyboardOctaves[_keyboardKind] ?? 4;

  TrackKind get _keyboardKind {
    final t = doc.tracks;
    final i = _inputTrack;
    return i >= 0 && i < t.length ? t[i].kind : TrackKind.synth;
  }

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
  final _cache = _SyncCache();
  List<_SentTrack> get _sent => _cache.tracks;
  _SentChain get _sentMaster => _cache.master;
  (int, int)? _sentWatchFx;
  int? _sentWatchAnalyzer;

  /// Notas ao vivo soando no motor, como (faixa, nota), para soltar tudo quando preciso.
  final _live = <(int, int)>{};

  /// Nota que cada tecla física está tocando: solta a certa mesmo se a oitava mudou no meio.
  final _keyNotes = <PhysicalKeyboardKey, (int, int)>{};

  /// Notas do MIDI soando (nota → faixa). O pedal não segura nada aqui: vai ao motor como controle
  /// (`live_cc` 64), que segura as notas soltas e grava o pedal como evento do clipe.
  final _midiNotes = <int, int>{};
  bool _sustain = false;

  /// Faixa que recebeu o último valor de cada controle ao vivo, por (controle, origem) com a chave
  /// `controle << 1 | (roda da tela ? 1 : 0)`: se a entrada muda de faixa com a roda ou o pedal fora
  /// do repouso, a antiga volta ao repouso, sem tocar no que a outra origem deixou.
  final _ccTrack = <int, int>{};

  String get _docKey => 'doc:${project.id}';

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  // ------------------------------------------------------------------ abrir

  Future<void> open() async {
    try {
      if (!_engine.supported) throw UnsupportedError('O motor de áudio não roda neste sistema: use o jopendaw no navegador ou no Android.');
      engineRate = await _engine.start();
      _engine.onState = _onEngineState;
      _engine.onLoudness = _onLoudness;
      _engine.onEngineFailed = _onEngineFailed;
      try {
        GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
        _pointerRouted = true;
      } on Object {
        // sem binding (teste de unidade): não acompanha o ponteiro
      }
      try {
        _unwatchAudio = watchAudioSession(onLeave: _onAppLeave, onReturn: _onAppReturn, onNoisy: _onAudioNoisy, onDevices: _onAudioDevices);
      } on Object catch (e) {
        // fora de um app Flutter (um teste sem binding): sem os avisos do aparelho
        debugPrint('sessão de áudio do aparelho: $e');
      }
      final saved = await _store.get(_docKey);
      // o andamento e o compasso são do documento (o servidor só os espelha, ver [_mirrorTempo]):
      // só um documento novo parte dos do projeto
      doc = saved is String ? DawDoc.fromJson(jsonDecode(saved)) : await _fromTemplate();
      for (final hash in doc.samples.keys.toList()) {
        await _loadSample(hash);
      }
      try {
        final device = await _store.get(_inputKey);
        if (device is String && device.isNotEmpty) inputDevice = device;
      } catch (_) {
        // sem a escolha guardada, vale a entrada padrão
      }
      if (_disposed) return;
      // Sem documento local e sem modelo escolhido, o projeto pode existir só no servidor (criado
      // em outro aparelho): espera a primeira conversa com ele, documento e áudios, antes de
      // mostrar o estúdio. Senão aparece uma faixa vazia que depois troca por tudo de uma vez.
      // Offline ou lento, segue com o vazio depois de um tempo e a sincronização continua atrás.
      final waitServer = saved is! String && !_templated && _canSync();
      final started = sync.start(localExisted: saved is String || _templated, holdFirstPull: waitServer);
      if (waitServer) {
        _lastSaved = jsonEncode(doc.toJson());
        _blankJson = _lastSaved;
        try {
          await started.timeout(const Duration(seconds: 25));
        } catch (_) {
          // a sincronização segue em segundo plano e mostra o próprio estado
        }
        if (_disposed) return;
      } else {
        unawaited(started);
      }
      ready = true;
      _sync();
      _lastSaved = jsonEncode(doc.toJson());
      sync.addListener(_onSyncPhase);
      unawaited(_mirrorTempo());
      // faixa de áudio que ficou armada ou monitorando: a entrada volta aberta, como estava
      if (doc.tracks.any((t) => t.kind == TrackKind.audio && (t.armed || t.monitor))) unawaited(_restoreInput());
    } catch (e) {
      error = e is UnsupportedError ? e.message : '$e';
    }
    if (!_disposed) notifyListeners();
  }

  /// O motor de áudio caiu (trap do wasm, thread de áudio morta): o som ficou mudo e o projeto
  /// segue intacto. A tela mostra o aviso com "Reiniciar o áudio" ([restartAudio]).
  String? audioFailure;

  /// [restartAudio] em andamento.
  bool audioRestarting = false;

  /// Aviso discreto de que o projeto foi trocado pelo de outro aparelho (a tela mostra e a pessoa
  /// dispensa com [clearRemoteNotice]).
  String? remoteNotice;

  /// O documento vazio de um projeto aberto sem cópia local (aparelho novo): o que vem do servidor por cima dele não é
  /// "atualização de outro aparelho", então não leva o [remoteNotice].
  String? _blankJson;

  void clearRemoteNotice() {
    if (remoteNotice == null) return;
    remoteNotice = null;
    notifyListeners();
  }

  /// Quantos dedos/botões do ponteiro estão apertados: um gesto (arraste) em andamento não pode
  /// ver o documento trocado debaixo dele.
  int _pointersDown = 0;
  bool _pointerRouted = false;
  final _pointerIds = <int>{};

  /// Quando o último ponteiro apertado se mexeu (ou apertou). Um ponteiro que nunca recebe PointerUp/PointerCancel
  /// (a janela perdeu o foco no meio do gesto, por exemplo) deixaria [_pointersDown] acima de 0 para sempre e o pull
  /// da sincronização esperando: passado [pointerStaleAfter] sem movimento, o contador é ignorado.
  DateTime _pointerActiveAt = DateTime.now();

  /// Depois de quanto tempo parado um gesto "em andamento" deixa de contar (ver [_pointerActiveAt]).
  @visibleForTesting
  Duration pointerStaleAfter = const Duration(seconds: 30);

  /// Mouses com o botão principal apertado segundo o último evento deles. Um botão segurado parado
  /// não manda evento nenhum, então o tempo sem movimento não prova que o gesto acabou: o estado
  /// do botão (o `buttons` dos eventos, que vem 0 no primeiro evento depois de soltar) é quem decide.
  final _mouseHeld = <int>{};

  /// Há um gesto (arraste) em andamento que valha esperar: ponteiro apertado e mexendo há menos que
  /// [pointerStaleAfter], ou um mouse com o botão principal ainda apertado.
  bool get _gestureInProgress {
    if (_pointerIds.isEmpty) return false;
    if (_mouseHeld.any(_pointerIds.contains)) return true;
    if (DateTime.now().difference(_pointerActiveAt) <= pointerStaleAfter) return true;
    _pointerIds.clear();
    _pointersDown = 0;
    return false;
  }

  /// O app perdeu ou voltou o foco: nenhum PointerUp que ainda não chegou vale esperar.
  void _dropPointers() {
    _pointerIds.clear();
    _mouseHeld.clear();
    _pointersDown = 0;
  }

  @visibleForTesting
  void debugPointer(PointerEvent e) => _onPointer(e);

  void _onPointer(PointerEvent e) {
    if (e is PointerDownEvent) {
      _pointerIds.add(e.pointer);
    } else if (e is PointerUpEvent || e is PointerCancelEvent) {
      _pointerIds.remove(e.pointer);
      _mouseHeld.remove(e.pointer);
    }
    if (e.kind == PointerDeviceKind.mouse) {
      if ((e is PointerDownEvent || e is PointerMoveEvent) && e.buttons & kPrimaryButton != 0) {
        _mouseHeld.add(e.pointer);
      } else if (e is PointerMoveEvent || e is PointerHoverEvent) {
        // o botão já foi solto e o PointerUp se perdeu: o gesto acabou (os ids de um aperto e do
        // passeio seguinte do mesmo mouse diferem, então vale para todos os apertos do mouse)
        _pointerIds.removeAll(_mouseHeld);
        _mouseHeld.clear();
      }
    }
    if (e is PointerDownEvent || e is PointerMoveEvent) _pointerActiveAt = DateTime.now();
    _pointersDown = _pointerIds.length;
    // o último dedo levantou: o Toque acaba, o controle volta ao valor automatizado. Só Up/Cancel contam: movimento do
    // mouse sem botão (ou a roda) também chega aqui com nenhum ponteiro apertado e não pode fechar o trecho
    if (_pointersDown == 0 && (e is PointerUpEvent || e is PointerCancelEvent)) autoRec.releaseAll();
  }

  void _onEngineFailed(String message) {
    if (_disposed) return;
    debugPrint('motor de áudio caiu: $message');
    final detail = message.trim();
    audioFailure =
        'O motor de áudio parou de responder e o som ficou mudo. O projeto não foi perdido: reinicie o áudio para continuar.'
        '${detail.isEmpty ? '' : '\nDetalhe: ${detail.length > 240 ? '${detail.substring(0, 240)}…' : detail}'}';
    playing.value = false;
    notifyListeners();
  }

  /// Recria o motor de áudio depois de uma falha: manda de novo os áudios e o documento (o motor
  /// novo é vazio) e reabre a entrada de áudio, se alguma faixa a usa. Chamar de um gesto do
  /// usuário (o navegador só deixa o áudio sair depois dele).
  Future<void> restartAudio() async {
    if (_disposed || audioRestarting) return;
    audioRestarting = true;
    notifyListeners();
    try {
      engineRate = await _engine.restart();
      if (_disposed) return;
      for (final e in _decoded.entries) {
        _engine.loadSample(e.key, e.value);
      }
      _cache.tracks.clear();
      _cache.ids = const [];
      _cache.notes = null;
      _cache.ccs = const [];
      _cache.auto = null;
      // o motor novo tem um andamento e um compasso só
      _cache
        ..tempoSig = ''
        ..meterSig = '';
      _cache.master
        ..count = -1
        ..slots.clear();
      _sentWatchFx = null;
      _sentWatchAnalyzer = null;
      _live.clear();
      _keyNotes.clear();
      _midiNotes.clear();
      _inputOpen = false;
      inputLevel.value = 0;
      playing.value = false;
      audioFailure = null;
      _sync();
      if (doc.tracks.any((t) => t.kind == TrackKind.audio && (t.armed || t.monitor))) unawaited(_restoreInput());
    } catch (e) {
      audioFailure = 'Não deu para reiniciar o áudio: ${e is UnsupportedError ? e.message : e}';
    } finally {
      audioRestarting = false;
      if (!_disposed) notifyListeners();
    }
  }

  // ------------------------------------------------------------------ o aparelho (Android)
  // Na web nada disto dispara (a aba resolve sozinha): as funções de `platform` são vazias.

  void Function()? _unwatchAudio;
  bool _awake = false;

  /// Tela acesa enquanto toca ou grava, e solta ao parar; só vai ao sistema quando muda.
  void _keepAwake(bool on) {
    if (_awake == on) return;
    _awake = on;
    keepScreenOn(on);
  }

  /// O app saiu da tela (ou a tela apagou): sem um serviço em primeiro plano o Android pode matar o
  /// processo a qualquer momento, e o microfone aberto acende o aviso de privacidade. Para o
  /// transporte (gravando, encerra a gravação, que fica salva), solta as notas ao vivo e fecha a
  /// entrada.
  void _onAppLeave() {
    if (_disposed) return;
    _dropPointers();
    _pauseForSystem();
    // Gravando, o `_finishRecording` (já em andamento) ainda espera a latência da entrada e recolhe o
    // que ela tem: fechar a entrada agora cortaria o fim da gravação. Ele fecha depois.
    if (_rec != null) {
      _closeInputAfterRecording = true;
    } else {
      _closeInputForLeave();
    }
  }

  /// O app saiu da tela durante o fim de uma gravação: a entrada fecha quando ela termina.
  bool _closeInputAfterRecording = false;

  void _closeInputForLeave() {
    _closeInputAfterRecording = false;
    if (!_inputOpen || recording) return;
    _inputOpen = false;
    inputLevel.value = 0;
    _quietly(_engine.stopInput);
  }

  /// Voltou para a tela: garante a saída tocando (reabre se o Android a derrubou) e reabre a
  /// entrada se alguma faixa de áudio ficou armada ou monitorando, como o `open`.
  void _onAppReturn() {
    _dropPointers();
    if (_disposed || !ready) return;
    _closeInputAfterRecording = false;
    unawaited(_engine.resume());
    if (!_inputOpen && doc.tracks.any((t) => t.kind == TrackKind.audio && (t.armed || t.monitor))) unawaited(_restoreInput());
  }

  /// O fone (com fio ou Bluetooth) saiu e o som passaria para o alto-falante: para o transporte,
  /// como todo app de mídia.
  void _onAudioNoisy() {
    if (_disposed) return;
    _pauseForSystem();
  }

  /// Um aparelho de áudio entrou ou saiu (fone plugado, interface USB): a saída pode ter trocado
  /// de rota: garante a saída aberta ([AudioEngine.resume]) e relê a lista de entradas (sem abrir
  /// o microfone, que só abre para armar ou gravar; o [refreshInputDevices] abre e por isso não é
  /// chamado daqui). Se a entrada escolhida sumiu, a lista já volta para a padrão e avisa.
  void _onAudioDevices() {
    if (_disposed || !ready) return;
    unawaited(_engine.resume());
    unawaited(_listInputs());
  }

  /// Pausa (sem voltar o cursor) por causa do sistema. Gravando, encerra a gravação.
  void _pauseForSystem() {
    if (recording) {
      unawaited(_finishRecording());
      return;
    }
    if (playing.value || _live.isNotEmpty || _keyNotes.isNotEmpty || _midiNotes.isNotEmpty) {
      _engine.calls([
        ['stop'],
        ..._releaseLive(),
      ]);
    }
    playing.value = false;
  }

  void _onEngineState(EngineState s) {
    _keepAwake(s.playing || recording);
    _stateClock
      ..reset()
      ..start();
    final r = _rec;
    if (r != null && countingIn) _countInState(r, s);
    // na contagem fora do lugar o motor está longe, na região vazia: o cursor anda o compasso antes
    // do começo da gravação, como na contagem no lugar (antes do zero, a barra mostra as batidas
    // que faltam), em vez de pular para lá (e a janela não o segue)
    final away = r != null && countingIn && r.zone != null;
    if (away) {
      final zone = r.zone!;
      beat.value = s.playing && s.beat >= zone - 1e-6 ? r.start - math.max(0.0, zone + r.countBeats - s.beat) : r.start - r.countBeats;
    } else {
      beat.value = s.beat;
    }
    playing.value = s.playing;
    peaks.value = s.peaks;
    // um estado que chega depois de desligar a observação (já estava a caminho) não acende nada
    fxMeter.value = _sentWatchFx == null || _sentWatchFx!.$2 < 0 || !s.fxMeter.isFinite ? 0 : s.fxMeter;
    spectrum.value = _sentWatchAnalyzer == null || _sentWatchAnalyzer! < -1 ? null : s.spectrum;
    if (!away) _follow(s);
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

  /// Primeira abertura: o modelo escolhido ao criar o projeto (guardado no aparelho), ou o vazio.
  Future<DawDoc> _fromTemplate() async {
    final key = 'template:${project.id}';
    final chosen = await _store.get(key);
    final DawDoc d;
    if (chosen is! String) {
      d = _fresh();
    } else {
      _templated = true;
      await _store.delete(key);
      d = ProjectTemplate.parse(chosen).build(bpm: project.bpm.toDouble(), beatsPerBar: _quarterBeatsPerBar);
      d.meterMap = _projectMeterMap;
    }
    // projeto novo: o mapa de MIDI learn padrão do aparelho (se o usuário salvou um)
    d.midiMap = midiDefaultFrom(await loadMidiDefault(_store), d.tracks, newId);
    return d;
  }

  /// Batidas de semínima do compasso do projeto: o `beatsPerBar` do documento conta semínimas, e o do projeto no servidor é
  /// o numerador (um 6/8 é 6 lá e 3 aqui; um 7/8, 3,5 arredondado para 4, com o mapa de compassos guardando o 7/8 exato).
  int get _quarterBeatsPerBar => (project.beatsPerBar * 4 / project.beatUnit).round().clamp(1, 32);

  /// O mapa de compassos de um projeto sem documento: vazio no n/4 (o `beatsPerBar` basta), o compasso exato nos outros.
  List<MeterChange> get _projectMeterMap => project.beatUnit == 4 ? const [] : [MeterChange(1, project.beatsPerBar, project.beatUnit)];

  DawDoc _fresh() => DawDoc(
    bpm: project.bpm.toDouble(),
    beatsPerBar: _quarterBeatsPerBar,
    meterMap: _projectMeterMap,
    tracks: [DawTrack(id: newId(), name: 'Áudio 1', color: 0)],
    loopEnd: project.beatsPerBar * 4.0 * 4 / project.beatUnit,
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
    // o render fora de tempo real roda num motor separado, que precisa receber os áudios de novo
    _decoded[id] = audio;
    waveforms[hash] = Waveform.of(audio);
    missing.remove(hash);
  }

  /// Os áudios decodificados, pelo id do motor.
  final _decoded = <int, DecodedAudio>{};

  /// O áudio decodificado de um sample do projeto (null se não está neste aparelho).
  DecodedAudio? decodedAudio(String hash) {
    final id = _sampleIds[hash];
    return id == null ? null : _decoded[id];
  }

  /// Importa um áudio para o projeto sem pôr clipe no arranjo nem escolhê-lo como áudio de
  /// faixa (as zonas do sampler o citam); devolve o sha-256, ou null se não abriu (o erro fica em
  /// [error]).
  Future<String?> importSampleFile(String name, Uint8List bytes) async {
    status = 'Importando $name…';
    notifyListeners();
    try {
      final hash = await _ingest(name, bytes);
      if (_disposed) return null;
      status = null;
      _scheduleSave();
      notifyListeners();
      return hash;
    } catch (e) {
      if (_disposed) return null;
      status = null;
      error = 'Não deu para abrir $name: é um formato de áudio que $_thisHost decodifica?';
      notifyListeners();
      return null;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    autoRec.dispose();
    _learn?.dispose();
    // o motor sobrevive à tela: nada pode ficar soando nem preso para o próximo projeto, nem
    // medindo o que ninguém mais olha
    _engine.calls([
      ['stop'],
      ['panic'],
      ['watch_fx', -1, -1],
      ['watch_analyzer', -2],
    ]);
    if (_engine.onState == _onEngineState) _engine.onState = null;
    if (_engine.onLoudness == _onLoudness) _engine.onLoudness = null;
    if (_engine.onEngineFailed == _onEngineFailed) _engine.onEngineFailed = null;
    if (_pointerRouted) GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
    _unwatchAudio?.call();
    _unwatchAudio = null;
    _keepAwake(false);
    if (_engine.onMidi == _onMidi) _engine.onMidi = null;
    if (_engine.onMidiInputs == _onMidiInputs) _engine.onMidiInputs = null;
    // gravação pela metade some com a tela; a entrada fecha (o navegador apaga o aviso de microfone)
    if (_rec?.captureOn ?? false) _captureOff(null);
    _rec = null;
    if (_engine.onRecord == _onRecordBlock) _engine.onRecord = null;
    if (_engine.onInputLevel == _onInputLevel) _engine.onInputLevel = null;
    if (_engine.onCaptureEnd == _onCaptureEnd) _engine.onCaptureEnd = null;
    if (_engine.onInputLost == _onInputLost) _engine.onInputLost = null;
    if (_inputOpen) {
      _inputOpen = false;
      _quietly(_engine.stopInput);
    }
    editorKeyHandler = null;
    _saveTimer?.cancel();
    _warp.dispose();
    _save();
    _syncService?.dispose();
    beat.dispose();
    playing.dispose();
    peaks.dispose();
    liveNotes.dispose();
    liveReset.dispose();
    fxMeter.dispose();
    loudness.dispose();
    spectrum.dispose();
    inputLevel.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------ motor

  /// Manda o documento ao motor. É barato: dezenas de chamadas numa mensagem. Instrumentos,
  /// efeitos, roteamento, automação e notas vão só no que mudou desde o último envio.
  ///
  /// Ordem: áudio → instrumentos → efeitos → roteamento → automação → observação → notas →
  /// monitoração da entrada.
  ///
  /// Gravando, o loop, o metrônomo e a automação podem estar trocados pela contagem (ver
  /// [_startRecording]): o sync manda o que vale agora, não o do documento.
  void _sync() {
    _warp.want(_warpSpecs());
    final ids = [for (final t in doc.tracks) t.id];
    var release = const <List<Object>>[];
    if (!_isPrefix(_cache.ids, ids)) {
      // faixas saíram ou mudaram de lugar: o índice de cada instrumento no motor agora é de outra
      // faixa, e o que soa ao vivo ficaria preso no índice velho. Efeitos, envios, automação e a
      // monitoração da entrada também eram de outra faixa: vai tudo de novo.
      release = _releaseLive();
      _cache.tracks.clear();
      _cache.notes = null;
      _cache.ccs = _cache.ccs == null || _cache.ccs!.isEmpty ? const [] : null;
      _cache.auto = null;
    }
    final loop = _loopOverride ?? (doc.loopOn, doc.loopStart, doc.loopEnd);
    final calls = _docCalls(
      _cache,
      loop: loop,
      metronome: doc.metronome || _countMetronome,
      automation: !_autoSuppressed,
      release: release,
      observe: _watchCalls(),
    );
    // por último: um motor que ainda não conheça a entrada para aqui sem perder o resto
    calls.addAll(_monitorCalls());
    _engine.calls(calls);
  }

  // ------------------------------------------------------------------ warp

  Iterable<WarpSpec> _warpSpecs() sync* {
    for (final t in doc.tracks) {
      if (t.kind != TrackKind.audio) continue;
      for (final c in t.clips) {
        final s = WarpSpec.of(c, doc.bpm);
        if (s != null) yield s;
      }
    }
  }

  /// O som que o motor toca para o clipe e onde ele corta: o derivado do warp quando está pronto
  /// (offset, duração e fades passam dos segundos da origem para os do derivado), senão o
  /// original. Null se o áudio não está neste aparelho.
  ({int id, double offset, double length, double fadeIn, double fadeOut})? _clipSound(AudioClip c, double bpm) {
    final orig = _sampleIds[c.sample];
    if (orig == null) return null;
    final spec = WarpSpec.of(c, bpm);
    final id = spec == null ? null : _warp.idOf(spec);
    if (spec == null || id == null) return (id: orig, offset: c.offset, length: c.length, fadeIn: c.fadeIn, fadeOut: c.fadeOut);
    final k = spec.ratio;
    // invertido, o que era o fim do trecho passa a ser o começo
    final total = _decoded[orig]?.duration ?? (c.offset + c.length);
    final offset = spec.reverse ? math.max(0.0, total - c.offset - c.length) : c.offset;
    return (id: id, offset: offset * k, length: c.length * k, fadeIn: c.fadeIn * k, fadeOut: c.fadeOut * k);
  }

  /// O clipe de áudio pelo id (null se sumiu).
  AudioClip? audioClip(String id) => _findClip(id)?.$2;

  /// O clipe está esperando o som do warp ("processando…"); ele toca o original até ficar pronto.
  bool warpPending(AudioClip c) {
    final s = WarpSpec.of(c, doc.bpm);
    return s != null && _warp.isPending(s);
  }

  /// Por que o warp do clipe não ficou pronto (ele toca o original), se falhou.
  String? warpFailure(AudioClip c) {
    final s = WarpSpec.of(c, doc.bpm);
    return s == null ? null : _warp.failure(s);
  }

  /// Estima o andamento do áudio do clipe (o original, sem warp). Null se o áudio não está aqui.
  Future<({double bpm, double confidence})?> detectClipBpm(String clipId) async {
    final f = _findClip(clipId);
    final id = f == null ? null : _sampleIds[f.$2.sample];
    final audio = id == null ? null : _decoded[id];
    if (audio == null) return null;
    return _engine.detectBpm(audio);
  }

  /// Muda o warp do clipe (uma edição desfazível); o som novo vem assíncrono.
  void setClipWarp(String clipId, {bool? warp, double? sourceBpm, bool clearSourceBpm = false, double? pitch, bool? reverse}) {
    final f = _findClip(clipId);
    if (f == null || _blockedByRecording('mudar o warp')) return;
    edit((_) {
      final c = f.$2;
      if (warp != null) c.warp = warp;
      if (clearSourceBpm) c.sourceBpm = null;
      if (sourceBpm != null) c.sourceBpm = sourceBpm.clamp(20.0, 999.0);
      if (pitch != null) c.pitch = pitch.clamp(-24.0, 24.0);
      if (reverse != null) c.reverse = reverse;
    });
  }

  /// Ganho do clipe de áudio (linear, 0..[maxClipGain]). Sem [undoable] é um passo de arraste: quem
  /// chama guarda o estado antes com [checkpoint].
  void setClipGain(String clipId, double gain, {bool undoable = true}) {
    final f = _findClip(clipId);
    if (f == null) return;
    final g = gain.isFinite ? gain.clamp(0.0, maxClipGain) : 1.0;
    if (f.$2.gain == g) return;
    edit((_) => f.$2.gain = g, undoable: undoable);
  }

  /// Nos testes: espera os sons do warp que o documento pede.
  @visibleForTesting
  Future<void> debugSettleWarp() => _warp.settle();

  /// Termina os sons do warp pendentes antes de renderizar: o que soa é o que exporta.
  Future<void> _settleWarp() async {
    if (!_warp.busy) return;
    final before = status;
    status = 'Processando o warp…';
    notifyListeners();
    await _warp.settle();
    if (!_disposed) status = before;
  }

  /// O documento inteiro como chamadas, para um motor novo (o render fora de tempo real, que roda
  /// as mesmas chamadas num motor separado): sem loop nem metrônomo, que não entram no arquivo,
  /// sem observação e sem entrada.
  List<List<Object>> _fullSyncCalls() => _docCalls(_SyncCache(), loop: (false, 0.0, 0.0), metronome: false);

  /// Nos testes: as chamadas que um motor novo recebe (o render).
  @visibleForTesting
  List<List<Object>> debugFullSyncCalls() => _fullSyncCalls();

  /// As chamadas que levam o documento a um motor que já recebeu o que [c] registra (vazio: um
  /// motor novo, a lista completa), atualizando [c]. [release] solta o que soa ao vivo antes de os
  /// índices trocarem de instrumento; [observe] entra antes das notas.
  List<List<Object>> _docCalls(
    _SyncCache c, {
    required (bool, double, double) loop,
    required bool metronome,
    bool automation = true,
    List<List<Object>> release = const [],
    List<List<Object>> observe = const [],
  }) {
    final d = doc;
    c.ids = [for (final t in d.tracks) t.id];
    final calls = <List<Object>>[
      ['tempo', d.bpm, d.beatsPerBar],
      ['tracks', d.tracks.length],
      ['master', d.masterGain, d.masterPan],
      ['loop_set', loop.$1, loop.$2, loop.$3],
      ['metronome', metronome, 0.5],
      ['clips_clear'],
    ];
    // o mapa de andamento e o de compassos vêm logo depois do `tempo` (as posições em batidas do
    // resto convertem por eles); só quando mudam
    calls.insertAll(1, _tempoMapCalls(c));
    for (var i = 0; i < d.tracks.length; i++) {
      final t = d.tracks[i];
      calls.add(['track', i, t.gain, t.pan, t.mute, t.solo]);
      if (t.kind != TrackKind.audio) continue;
      for (final c in t.clips) {
        final r = _clipSound(c, d.bpm);
        if (r == null) continue;
        calls.add(['clip_add', i, r.id, c.start, r.offset, r.length, c.gain, r.fadeIn, r.fadeOut]);
        // as curvas dos fades valem para o último `clip_add`; só as que fogem do padrão (motor sem a chamada ignora)
        if (c.fadeInShape != FadeShape.linear || c.fadeOutShape != FadeShape.linear) {
          calls.add(['clip_fade_shape', c.fadeInShape.index, c.fadeOutShape.index]);
        }
      }
    }
    // instrumentos e notas depois do áudio: um motor que ainda não conheça estas funções para na
    // primeira que falta, e o arranjo de áudio já foi inteiro. O que soava ao vivo solta antes de
    // o índice trocar de instrumento.
    calls.addAll(release);
    final sent = c.tracks;
    for (var i = 0; i < d.tracks.length; i++) {
      final t = d.tracks[i];
      var s = i < sent.length ? sent[i] : null;
      final fresh = s == null || s.kind != t.kind;
      if (s == null || fresh) {
        s = _SentTrack(t.kind);
        if (i < sent.length) {
          sent[i] = s;
        } else {
          sent.add(s);
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
        _syncZones(calls, i, t, s);
      }
    }
    if (sent.length > d.tracks.length) sent.length = d.tracks.length;
    for (var i = 0; i < d.tracks.length; i++) {
      _syncChain(calls, i, d.tracks[i].effects, sent[i].fx);
    }
    _syncChain(calls, -1, d.masterEffects, c.master);
    final index = _trackIndex();
    final sends = [for (var i = 0; i < d.tracks.length; i++) _validSends(i, index)];
    for (var i = 0; i < d.tracks.length; i++) {
      _syncRouting(calls, i, sent[i], sends[i], index);
    }
    final auto = automation ? _automationCalls(sends) : const <List<Object>>[];
    if (c.auto == null || !_sameCalls(auto, c.auto!)) {
      calls.add(['auto_clear']);
      calls.addAll(auto);
      c.auto = auto;
    }
    final mod = _modulationCalls(sends);
    if (!_sameCalls(mod, c.mod)) {
      calls.add(['mod_clear']);
      calls.addAll(mod);
      c.mod = mod;
    }
    calls.addAll(observe);
    final notes = flattenNotes(d.tracks);
    if (c.notes == null || !listEquals(notes, c.notes)) {
      calls.add(['notes_clear']);
      for (final n in notes) {
        calls.add(['note_add', n.track, n.start, n.length, n.pitch, n.velocity]);
      }
      c.notes = notes;
    }
    final ccs = flattenControls(d.tracks);
    if (c.ccs == null || !listEquals(ccs, c.ccs)) {
      calls.add(['cc_clear']);
      for (final e in ccs) {
        calls.add(['cc_add', e.track, e.cc, e.beat, e.value]);
      }
      c.ccs = ccs;
    }
    return calls;
  }

  /// Zonas do sampler no motor: mandadas de novo por inteiro (limpar e acrescentar) sempre que a
  /// lista de chamadas muda (uma zona editada, o áudio de uma zona que acabou de carregar).
  void _syncZones(List<List<Object>> calls, int i, DawTrack t, _SentTrack s) {
    final zc = [for (final z in t.zones) z.engineCall(i, _sampleIds[z.sample] ?? 0)];
    if (_sameCalls(zc, s.zones)) return;
    calls.add(['zones_clear', i]);
    calls.addAll(zc);
    s.zones = zc;
  }

  /// A entrada soa nas faixas de áudio que monitoram. Só vai o que mudou em cada índice do motor:
  /// o estado é do índice (não da faixa), então reordenar manda só onde a monitoração trocou.
  List<List<Object>> _monitorCalls() {
    final calls = <List<Object>>[];
    final n = doc.tracks.length;
    // faixas que saíram levam o estado junto (o motor recria o canal no padrão, desligado)
    if (_engineMonitor.length > n) _engineMonitor.length = n;
    for (var i = 0; i < n; i++) {
      final t = doc.tracks[i];
      final on = t.kind == TrackKind.audio && t.monitor;
      if (i >= _engineMonitor.length) _engineMonitor.add(false);
      if (_engineMonitor[i] == on) continue;
      calls.add(['input_monitor', i, on]);
      _engineMonitor[i] = on;
    }
    return calls;
  }

  /// Monitoração da entrada como o motor a conhece, por índice.
  final _engineMonitor = <bool>[];

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

  void _syncRouting(List<List<Object>> calls, int i, _SentTrack s, List<(Send, int)> sends, Map<String, int> index) {
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
        if (l.points.isEmpty || autoRec.isRecording(track, l.target)) continue;
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

  /// A modulação inteira como chamadas (`mod_source` + `mod_dest`), das faixas e do master. Só vão
  /// os moduladores com algum destino que existe; o índice do modulador e o do destino são os da
  /// lista do documento (a que o motor limita a [maxModSources] e [maxModDests]).
  List<List<Object>> _modulationCalls(List<List<(Send, int)>> sends) {
    final out = <List<Object>>[];
    void add(int track, TrackModulation m) {
      for (var si = 0; si < m.sources.length && si < maxModSources; si++) {
        final src = m.sources[si];
        final dests = <List<Object>>[];
        for (var di = 0; di < src.dests.length && di < maxModDests; di++) {
          final d = src.dests[di];
          final r = _resolve(track, d.target, sends: track >= 0 ? sends[track] : const []);
          if (r == null || r.spec?.curve == Curve.choice || r.spec?.curve == Curve.integer) continue;
          final scale = r.code == 0 || r.code == 4 ? 2 : (r.spec?.curve == Curve.log ? 1 : 0);
          dests.add(['mod_dest', track, si, di, r.code, r.slot, r.id, d.amount.clamp(-1.0, 1.0).toDouble(), r.min, r.max, scale]);
        }
        if (dests.isEmpty) continue;
        out.add([
          'mod_source',
          track,
          si,
          src.kind.index,
          src.sync ? src.division : src.rate,
          src.sync,
          src.depth,
          src.phase,
          src.bipolar,
          src.shape.index,
          src.attack,
          src.release,
          src.value,
        ]);
        out.addAll(dests);
      }
    }

    for (var i = 0; i < doc.tracks.length; i++) {
      add(i, doc.tracks[i].modulation);
    }
    add(-1, doc.masterModulation);
    return out;
  }

  /// O alvo existe e a modulação sabe movê-lo (opções e inteiros não se modulam).
  bool _modTargetOk(int track, AutoTarget target) {
    if (target.kind == AutoKind.send) return track >= 0 && track < doc.tracks.length && doc.tracks[track].sends.any((s) => s.target == target.ref);
    final r = _resolve(track, target);
    return r != null && r.spec?.curve != Curve.choice && r.spec?.curve != Curve.integer;
  }

  /// A modulação de uma faixa ou do master (−1), só leitura na prática (null se a faixa não existe).
  /// Para mudar, [editModulation].
  TrackModulation? modulationOf(int track) =>
      track == -1 ? doc.masterModulation : (track >= 0 && track < doc.tracks.length ? doc.tracks[track].modulation : null);

  /// Muda a modulação da faixa (ou do master) e manda ao motor. Sem [undoable] é um passo de
  /// arraste (quem chama guarda o estado antes com [checkpoint]).
  void editModulation(int track, void Function(TrackModulation m) fn, {bool undoable = true}) {
    final m = modulationOf(track);
    if (m == null) return;
    edit((_) => fn(m), undoable: undoable);
  }

  /// Faixa de valores, escala e valor fixo do alvo, na unidade dele, para a gravação de automação;
  /// null se o alvo não existe. [stepped]: opções e inteiros (a automação anda em degraus).
  AutoInfo? autoInfo(int track, AutoTarget target) {
    final r = _resolve(track, target);
    if (r == null) return null;
    final curve = r.spec?.curve;
    return (min: r.min, max: r.max, fixed: r.value, warp: _warpOf(r), stepped: curve == Curve.choice || curve == Curve.integer);
  }

  /// A raia do alvo (mesmo vazia), ou null.
  AutoLane? autoLaneOf(int track, AutoTarget target) => _lanes(track)?.where((l) => l.target == target).firstOrNull;

  /// O documento de agora, como o histórico o guarda.
  String autoSnapshot() => jsonEncode(doc.toJson());

  /// O ponto de desfazer que o gesto de agora acabou de guardar (mesmo turno), tirado do
  /// histórico para a gravação de automação guardar a passada inteira num só; null se não há.
  String? autoTakeCheckpoint() {
    if (!_ckptTurn || _undo.isEmpty) return null;
    _ckptTurn = false;
    return _undo.removeLast();
  }

  /// Guarda [snapshot] (o documento de antes da passada) como um passo do histórico.
  void autoCommitUndo(String snapshot) {
    _undo.add(snapshot);
    if (_undo.length > 200) _undo.removeAt(0);
    _redo.clear();
    notifyListeners();
  }

  /// Devolve o valor fixo do alvo (o que o controle mostra parado) sem passar pela gravação nem pelo histórico:
  /// o Toque, ao acabar, tira o valor fixo do último ponto da mão.
  void autoSetFixed(int track, AutoTarget target, double value) {
    if (!value.isFinite) return;
    final r = _resolve(track, target);
    if (r == null) return;
    final v = r.spec != null ? _fit(r.spec!, value) : value.clamp(r.min, r.max).toDouble();
    if (v == r.value) return;
    final t = track < 0 ? null : doc.tracks[track];
    mutate((d) {
      switch (target.kind) {
        case AutoKind.volume:
          t != null ? t.gain = v : d.masterGain = v;
        case AutoKind.pan:
          t != null ? t.pan = v : d.masterPan = v;
        case AutoKind.instrument:
          t?.params[target.param] = v;
        case AutoKind.effect:
          _findSlot(track, target.ref ?? '')?.$2.params[target.param] = v;
        case AutoKind.send:
          t?.sends.where((s) => s.target == target.ref).firstOrNull?.level = v;
      }
    });
  }

  /// Reenvia a automação ao motor (a raia que começou a ser gravada sai dele).
  void autoSyncNow() => _sync();

  /// Troca os pontos da raia do alvo (criando a raia se falta) sem entrar no histórico: a passada
  /// guarda o passo dela ao terminar. [fn] recebe os pontos em ordem e devolve os novos.
  void autoApply(int track, AutoTarget target, List<AutoPoint> Function(List<AutoPoint> existing) fn) {
    final lanes = _lanes(track);
    if (lanes == null) return;
    var lane = lanes.where((l) => l.target == target).firstOrNull;
    mutate((_) {
      if (lane == null) {
        lane = AutoLane(id: newId(), target: target);
        lanes.add(lane!);
      }
      lane!.points = fn(_sortedPoints(lane!.points));
    });
  }

  /// A faixa (ou o master, −1) tem automação com pontos para volume/pan.
  bool automated(int track, AutoKind kind) => automatedTarget(track, AutoTarget(kind));

  /// O volume ou pan que a faixa tem agora (ver [liveTargetValue]). Para o fader e o pan
  /// acompanharem a automação.
  double liveValue(int track, AutoKind kind) {
    if (track >= doc.tracks.length) return 0;
    final t = track < 0 ? null : doc.tracks[track];
    final fixed = kind == AutoKind.pan ? (t?.pan ?? doc.masterPan) : (t?.gain ?? doc.masterGain);
    return liveTargetValue(track, AutoTarget(kind), fixed);
  }

  /// Automação com pontos para o alvo. Volume e pan valem pelo tipo; parâmetro de instrumento e
  /// de efeito, pelo parâmetro (e pelo slot).
  bool automatedTarget(int track, AutoTarget target) => _laneFor(track, target) != null;

  AutoLane? _laneFor(int track, AutoTarget target) {
    if (track >= doc.tracks.length) return null;
    final lanes = track < 0 ? doc.masterLanes : doc.tracks[track].lanes;
    for (final l in lanes) {
      if (l.points.isEmpty || l.target.kind != target.kind) continue;
      final same = switch (target.kind) {
        AutoKind.volume || AutoKind.pan => true,
        AutoKind.instrument => l.target.param == target.param,
        AutoKind.effect => l.target.ref == target.ref && l.target.param == target.param,
        AutoKind.send => l.target.ref == target.ref,
      };
      if (same) return l;
    }
    return null;
  }

  /// O valor que o alvo tem agora: tocando e com automação, o da curva no cursor (a mesma conta
  /// do motor); parado, [fixed], como no motor. Para os controles acompanharem a automação.
  double liveTargetValue(int track, AutoTarget target, double fixed) {
    if (!playing.value) return fixed;
    // gravando o alvo, o controle vale o que a mão pôs
    if (autoRec.isRecording(track, target)) return fixed;
    final l = _laneFor(track, target);
    if (l == null) return fixed;
    final r = _resolve(track, l.target);
    if (r == null) return fixed;
    return autoValueAt(_sortedPoints(l.points), beat.value, fixed, warp: _warpOf(r)).clamp(r.min, r.max).toDouble();
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

  /// Gravando, parar pelo transporte encerra a gravação (e o cursor volta ao começo dela).
  Future<void> togglePlay() async {
    if (recording) return _finishRecording();
    if (_recBusy) return;
    await _engine.resume();
    final stopping = playing.value;
    _engine.calls([
      [stopping ? 'stop' : 'play'],
      // parar também devolve ao repouso o que se tocou ao vivo (o motor só zera o que o clipe dirigia)
      if (stopping) ..._releaseControls(),
    ]);
    playing.value = !playing.value;
  }

  /// Para e volta ao começo (ou ao início do loop, se ligado). Gravando, encerra a gravação.
  Future<void> stop() async {
    if (recording) return _finishRecording();
    final to = playing.value ? (doc.loopOn ? doc.loopStart : 0.0) : 0.0;
    _engine.calls([
      ['stop'],
      ['seek', to],
      // pedal solto, bend e roda ao centro: o motor só devolve ao repouso o que o clipe dirigia
      ..._releaseControls(),
    ]);
    playing.value = false;
    beat.value = to;
    scrollBeat = math.max(0, to - 2);
    notifyListeners();
  }

  /// Gravando, o cursor não pula: a gravação sabe onde cada quadro cai pela posição em que ela
  /// começou e pelo loop, e um salto no meio deslocaria o resto.
  void seek(double b) {
    if (recording) return;
    b = math.max(0, b);
    _engine.calls([
      ['seek', b],
    ]);
    beat.value = b;
  }

  void toggleLoop() {
    if (_blockedByRecording('ligar ou desligar o loop')) return;
    edit((d) => d.loopOn = !d.loopOn, undoable: false);
  }

  void toggleMetronome() => edit((d) => d.metronome = !d.metronome, undoable: false);

  /// Contagem de um compasso antes de gravar; preferência do projeto, fora do desfazer.
  void toggleCountIn() => edit((d) => d.countIn = !d.countIn, undoable: false);

  /// Compensação manual da latência de gravação (ms, −500..500), fora do desfazer.
  void setRecLatency(double ms) {
    final v = ms.isFinite ? ms.clamp(-500.0, 500.0).toDouble() : 0.0;
    if (v == doc.recLatencyMs) return;
    edit((d) => d.recLatencyMs = v, undoable: false);
  }

  void setLoop(double start, double end) {
    // arrastar a região no meio de uma gravação mudaria onde as passadas se dividem
    if (recording) return;
    mutate((d) {
      d.loopStart = math.max(0, math.min(start, end));
      d.loopEnd = math.max(start, end);
      d.loopOn = d.loopEnd - d.loopStart > 0.01;
    });
  }

  /// Muda o andamento inicial (com decimais) e os tempos por compasso do compasso INICIAL. Se o
  /// compasso inicial não é n/4 (6/8, 7/8…), só trocar os tempos por compasso o substitui por
  /// `n/4`, senão o compasso mostrado e o do motor ficariam como estavam.
  Future<void> setTempo(num bpm, int beatsPerBar, {bool keepMeter = false}) async {
    if (_blockedByRecording('mudar o andamento')) return;
    final v = bpm.isFinite ? bpm.toDouble().clamp(minBpm, maxBpm).toDouble() : doc.bpm;
    final bpb = beatsPerBar.clamp(1, 32);
    edit((d) {
      d.bpm = v;
      // o ponto da batida 0 do mapa é o andamento inicial
      if (d.tempoMap.isNotEmpty) d.tempoMap = [d.tempoMap.first.copyWith(bpm: d.bpm), ...d.tempoMap.skip(1)];
      // [keepMeter]: o compasso inicial (6/8, 7/8…) fica como está; senão os tempos escolhidos o
      // substituem por n/4 mesmo quando n é igual ao `beatsPerBar` (um 6/8 guarda 3, um 7/8 guarda 4)
      if (keepMeter) return;
      d.beatsPerBar = bpb;
      if (d.meterMap.isNotEmpty) d.meterMap = [MeterChange(1, bpb, 4), ...d.meterMap.skip(1)];
    });
    await _mirrorTempo();
  }

  // ------------------------------------------------------------------ mapa de andamento e de compassos

  /// Segundos da batida 0 até [beat] pelo mapa de andamento (o relógio em segundos usa isto).
  double secondsAt(double beat) => doc.secondsAt(beat);

  /// O andamento (bpm) na batida, pelo mapa.
  double bpmAt(double beat) => doc.bpmAt(beat);

  /// As chamadas do mapa de andamento e do de compassos para o motor: vazio enquanto os dois são
  /// simples e o motor também (o `tempo` já basta); mudou, `tempo_clear`/`meter_clear` e os pontos.
  List<List<Object>> _tempoMapCalls(_SyncCache c) {
    final t = doc.tempo, m = doc.meter;
    final sigT = t.isSingle ? '' : jsonEncode([for (final p in t.points) p.toJson()]);
    final sigM = m.isSingle ? '' : jsonEncode([for (final x in m.changes) x.toJson()]);
    final out = <List<Object>>[];
    if (sigT != c.tempoSig) {
      c.tempoSig = sigT;
      out.addAll([
        ['tempo_clear'],
        for (final p in t.isSingle ? const <TempoPoint>[] : t.points) ['tempo_point', p.beat, p.bpm, p.ramp ? 1 : 0],
      ]);
    }
    if (sigM != c.meterSig) {
      c.meterSig = sigM;
      out.addAll([
        ['meter_clear'],
        for (final x in m.isSingle ? const <MeterChange>[] : m.changes) ['meter_point', x.bar, x.numerator, x.denominator],
      ]);
    }
    return out;
  }

  /// Troca o mapa de andamento inteiro: [points] em qualquer ordem (o ponto da batida 0 é o
  /// andamento inicial e passa a ser o [DawDoc.bpm]; sem ele, o andamento atual fica). Um ponto só
  /// (ou lista vazia) apaga as mudanças. É o gancho para o importador de MIDI aplicar o andamento
  /// do arquivo; é uma edição desfazível e vai ao motor e ao servidor (o espelho do andamento
  /// inicial).
  void setTempoMap(List<TempoPoint> points, {bool undoable = true}) {
    if (_blockedByRecording('mudar o andamento')) return;
    final norm = normalizeTempoPoints(points, doc.bpm);
    final distinct = {
      for (final p in points)
        if (p.beat.isFinite && p.bpm.isFinite) math.max(0.0, p.beat),
    };
    if (distinct.length > maxTempoPoints) {
      error = '$tempoPointsFullMessage Os pontos além dele foram ignorados.';
    }
    // o ponto dado na batida 0 manda no andamento inicial
    final given = points.where((p) => p.beat <= 0 && p.bpm.isFinite).lastOrNull;
    edit((d) {
      if (given != null) d.bpm = given.bpm.clamp(minBpm, maxBpm).toDouble();
      d.tempoMap = norm.isEmpty ? const [] : [norm.first.copyWith(bpm: d.bpm), ...norm.skip(1)];
    }, undoable: undoable);
    unawaited(_mirrorTempo());
  }

  /// Troca o mapa de compassos inteiro: as mudanças `{compasso, num, den}` em qualquer ordem (a do
  /// compasso 1 é o compasso inicial). Uma só n/4 (ou lista vazia) apaga as mudanças. É o gancho
  /// para o importador de MIDI aplicar as fórmulas de compasso do arquivo.
  void setMeterMap(List<MeterChange> changes, {bool undoable = true}) {
    if (_blockedByRecording('mudar o compasso')) return;
    final norm = normalizeMeterChanges(changes, doc.beatsPerBar);
    if ({for (final m in changes) math.max(1, m.bar)}.length > maxMeterChanges) {
      error = '$meterChangesFullMessage As mudanças além dele foram ignoradas.';
    }
    final first = changes.where((m) => m.bar <= 1).lastOrNull;
    edit((d) {
      if (norm.isNotEmpty) {
        // o campo `beatsPerBar` acompanha o primeiro compasso (em batidas de semínima)
        d.beatsPerBar = norm.first.barBeats.round().clamp(1, 32);
      } else if (first != null) {
        // só o compasso n/4 do início sobrou: é o `beatsPerBar`
        d.beatsPerBar = first.numerator.clamp(1, 32);
      }
      d.meterMap = norm;
    }, undoable: undoable);
    unawaited(_mirrorTempo());
  }

  /// Põe um ponto de andamento na batida (no andamento vigente ali, salvo [bpm]). Na batida de um
  /// ponto existente, só troca o andamento dele. Devolve a batida do ponto.
  double addTempoPoint(double beat, {double? bpm, bool ramp = false}) {
    final b = math.max(0.0, beat);
    final v = (bpm ?? doc.bpmAt(b)).clamp(minBpm, maxBpm).toDouble();
    final pts = [...doc.tempo.points];
    final at = pts.indexWhere((p) => (p.beat - b).abs() < 1e-9);
    if (at >= 0) {
      pts[at] = pts[at].copyWith(bpm: v);
    } else {
      if (pts.length >= maxTempoPoints) {
        error = tempoPointsFullMessage;
        notifyListeners();
        return b;
      }
      pts.add(TempoPoint(b, v, ramp: ramp));
    }
    setTempoMap(pts);
    return b;
  }

  /// Muda o andamento e/ou a batida do ponto [index] do mapa (o da batida 0 não sai do lugar).
  /// Sem [undoable] é um passo de arraste: quem chama guarda o estado antes com [checkpoint].
  void moveTempoPoint(int index, {double? beat, double? bpm, bool undoable = true}) {
    final pts = [...doc.tempo.points];
    if (index < 0 || index >= pts.length) return;
    final p = pts[index];
    var b = index == 0 ? 0.0 : (beat ?? p.beat);
    if (index > 0) {
      // não passa por cima dos vizinhos (dois pontos na mesma batida viram um)
      final lo = pts[index - 1].beat + 1e-3;
      final hi = index + 1 < pts.length ? pts[index + 1].beat - 1e-3 : double.infinity;
      b = b.clamp(lo, math.max(lo, hi)).toDouble();
    }
    final v = (bpm ?? p.bpm).clamp(minBpm, maxBpm).toDouble();
    if (b == p.beat && v == p.bpm) return;
    pts[index] = p.copyWith(beat: b, bpm: v);
    setTempoMap(pts, undoable: undoable);
  }

  /// Apaga o ponto de andamento [index] (o da batida 0 é o andamento inicial e fica).
  void removeTempoPoint(int index) {
    final pts = [...doc.tempo.points];
    if (index <= 0 || index >= pts.length) return;
    pts.removeAt(index);
    setTempoMap(pts);
  }

  /// Salto (false) ou rampa linear até o ponto seguinte (true) a partir do ponto [index].
  void setTempoPointRamp(int index, bool ramp) {
    final pts = [...doc.tempo.points];
    if (index < 0 || index >= pts.length || pts[index].ramp == ramp) return;
    pts[index] = pts[index].copyWith(ramp: ramp);
    setTempoMap(pts);
  }

  /// A partir do compasso [bar] (1 = o primeiro) o compasso passa a ser [num]/[den]. Mudar para o
  /// que já vale ali não faz nada.
  void setMeterAt(int bar, int num, int den) {
    final m = doc.meter;
    final b = math.max(1, bar);
    final list = [...m.changes];
    final at = list.indexWhere((x) => x.bar == b);
    final here = at >= 0 ? list[at] : m.changeAt(b);
    if (here.numerator == num && here.denominator == den) return;
    if (at >= 0) {
      list[at] = MeterChange(b, num, den);
    } else {
      if (list.length >= maxMeterChanges) {
        error = meterChangesFullMessage;
        notifyListeners();
        return;
      }
      list.add(MeterChange(b, num, den));
    }
    setMeterMap(list);
  }

  /// Desfaz a mudança de compasso que começa no compasso [bar] (a do compasso 1 é a inicial).
  void removeMeterChange(int bar) {
    final list = [...doc.meter.changes];
    if (bar <= 1 || !list.any((x) => x.bar == bar)) return;
    list.removeWhere((x) => x.bar == bar);
    setMeterMap(list);
  }

  // andamento e compasso que o servidor conhece (o projeto carregado, até um PATCH dar certo)
  late (int, int, int) _mirroredTempo = (project.bpm, project.beatsPerBar, project.beatUnit);
  bool _mirroring = false, _mirrorAgain = false;

  /// O andamento e o compasso do documento são a verdade; o servidor guarda um espelho para a lista
  /// de projetos. O PATCH é o melhor esforço: sem rede ele não falha para quem chamou, fica
  /// pendente e sai de novo no próximo salvamento (desfazer e refazer incluídos), na abertura, ao
  /// aplicar uma versão do servidor e quando a sincronização volta a dar certo.
  Future<void> _mirrorTempo() async {
    if (_mirroring) {
      _mirrorAgain = true;
      return;
    }
    _mirroring = true;
    try {
      do {
        _mirrorAgain = false;
        if (_disposed || !ready || !_canSync()) return;
        final want = _wantedTempo;
        if (want == _mirroredTempo) return;
        try {
          // a figura do tempo só vai quando muda (o servidor a aceita e valida): sem ela um 6/8 apareceria 6/4 na lista
          await _patchProject(project.id, {'bpm': want.$1, 'beats_per_bar': want.$2, if (want.$3 != _mirroredTempo.$3) 'beat_unit': want.$3});
          _mirroredTempo = want;
        } catch (_) {
          return;
        }
      } while (_mirrorAgain);
    } finally {
      _mirroring = false;
    }
  }

  void _onSyncPhase() {
    if (sync.phase == SyncPhase.synced) unawaited(_mirrorTempo());
  }

  /// O andamento espelhado ainda não chegou ao servidor (nos testes).
  @visibleForTesting
  bool get tempoPending => _wantedTempo != _mirroredTempo;

  /// O que o espelho do servidor deve ter: andamento, tempos por compasso e figura do compasso inicial.
  (int, int, int) get _wantedTempo {
    // o compasso inicial de verdade (um 6/8 guarda 3 em `beatsPerBar`): é o que o cabeçalho do projeto mostra
    final m = doc.meter.changeAt(1);
    // o teto é o do servidor (`beats_per_bar` 1..32, também no CHECK do banco) e o da tela do mapa de compassos; o mapa
    // aceita até 64 no JSON, mas um PATCH com mais de 32 seria recusado e o espelho ficaria pendente para sempre
    return (doc.bpm.round().clamp(minBpmInt, maxBpmInt), m.numerator.clamp(1, 32), const {1, 2, 4, 8, 16, 32}.contains(m.denominator) ? m.denominator : 4);
  }

  // ------------------------------------------------------------------ edição

  /// Uma edição desfazível: guarda o estado de antes, aplica, manda ao motor e salva.
  void edit(void Function(DawDoc d) fn, {bool undoable = true}) {
    if (undoable) checkpoint();
    mutate(fn);
  }

  /// Guarda o estado atual no histórico (início de um arraste, que depois só faz [mutate]).
  void checkpoint() {
    // o gesto que a gravação de automação anunciou não guarda ponto próprio: a passada inteira
    // entra no histórico como um passo só quando o transporte para
    if (autoRec.consumeSwallow()) return;
    _undo.add(jsonEncode(doc.toJson()));
    _ckptTurn = true;
    scheduleMicrotask(() => _ckptTurn = false);
    if (_undo.length > 200) _undo.removeAt(0);
    _redo.clear();
  }

  bool _ckptTurn = false;

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
    // As preferências de gravação e o armar/monitorar das faixas também ficam como estão.
    final before = doc;
    doc = DawDoc.fromJson(jsonDecode(from.removeLast()))
      ..metronome = before.metronome
      ..countIn = before.countIn
      ..recLatencyMs = before.recLatencyMs
      // mapear não entra no histórico: desfazer uma nota não desfaz os mapeamentos
      ..midiMap = before.midiMap;
    if (doc.loopStart == before.loopStart && doc.loopEnd == before.loopEnd) doc.loopOn = before.loopOn;
    final live = {for (final t in before.tracks) t.id: t};
    for (final t in doc.tracks) {
      final now = live[t.id];
      if (now == null) continue;
      t
        ..armed = now.armed
        ..monitor = now.monitor
        // recolher/expandir é estado de arranjo: desfazer uma edição não mexe nele
        ..collapsed = now.collapsed;
    }
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
    // destinos de modulação cujo alvo sumiu (efeito ou envio apagado, faixa que mudou de tipo)
    for (var i = -1; i < doc.tracks.length; i++) {
      final m = modulationOf(i);
      if (m != null && !m.isEmpty) m.prune((t) => _modTargetOk(i, t));
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
    final text = jsonEncode(doc.toJson());
    if (text != _lastSaved) {
      _lastSaved = text;
      // o pendente é marcado antes do documento: se o app morrer entre os dois, sobra um
      // pendente a mais (inofensivo), nunca uma mudança que ninguém vai enviar
      await sync.markDirty();
      unawaited(_mirrorTempo());
    }
    await _store.put(_docKey, text);
  }

  // ------------------------------------------------------------------ sincronização

  /// Todos os áudios que o documento cita (a lista do documento, mais o que clipes e sampler
  /// apontam, por garantia).
  static Set<String> hashesOf(DawDoc d) => _hashesOf(d);

  static Set<String> _hashesOf(DawDoc d) => {
    ...d.samples.keys,
    for (final t in d.tracks) ...[
      ?t.sample,
      for (final z in t.zones) z.sample,
      for (final c in t.clips) ...[c.sample, ...c.takes],
    ],
  };

  /// Pega o áudio no aparelho ou, se não há, no servidor; decodifica e registra. Sem o arquivo em
  /// lugar nenhum fica em [missing]. Falha de rede lança (quem chama tenta de novo depois).
  Future<void> _obtainSample(String hash) async {
    final local = await _store.get('sample:$hash');
    var bytes = local is Uint8List ? local : null;
    if (bytes == null) {
      bytes = await _api.getSample(hash);
      if (bytes == null) {
        missing.add(hash);
        return;
      }
      await _store.put('sample:$hash', bytes);
    }
    try {
      _register(hash, await _engine.decode(bytes));
    } catch (_) {
      missing.add(hash);
    }
  }

  Future<void> _fetchMissing() async {
    for (final hash in missing.toList()) {
      if (_disposed) return;
      await _obtainSample(hash);
    }
    if (!_disposed) notifyListeners();
  }

  /// Troca o documento pelo do servidor, baixando antes os áudios (o documento só muda quando está
  /// tudo à mão). Andamento e compasso vêm com o documento; o que é preferência deste aparelho
  /// (metrônomo, contagem, latência, armar e monitorar) também. Devolve false se o usuário
  /// editou no meio do caminho: aí os dois lados mudaram e quem decide é a pessoa.
  Future<bool> _applyRemote(Map<String, dynamic> json, void Function(int done, int total) progress, bool Function() canSwap) async {
    final DawDoc next;
    try {
      next = DawDoc.fromJson(json);
    } catch (_) {
      throw SyncFailure('A versão do servidor não abre nesta versão do app. Atualize o jopendaw.');
    }
    final need = [
      for (final h in _hashesOf(next))
        if (!waveforms.containsKey(h)) h,
    ];
    progress(0, need.length);
    for (final (i, hash) in need.indexed) {
      await _obtainSample(hash);
      progress(i + 1, need.length);
    }
    if (_disposed) return false;
    if (!canSwap() || _saveTimer?.isActive == true) return false;
    // (gravar, tocar e gesto em andamento já vêm em [canSwap]; isto só guarda o que muda entre a checagem e a troca)
    if (recording) return false;
    final old = doc;
    final wasBlank = _blankJson != null && jsonEncode(old.toJson()) == _blankJson;
    _blankJson = null;
    next
      ..metronome = old.metronome
      ..countIn = old.countIn
      ..recLatencyMs = old.recLatencyMs;
    final live = {for (final t in old.tracks) t.id: t};
    for (final t in next.tracks) {
      final now = live[t.id];
      t
        ..armed = now?.armed ?? false
        ..monitor = now?.monitor ?? false;
    }
    // o servidor tem o mesmo projeto deste aparelho (a versão só subiu): nada a trocar, e o
    // desfazer fica
    if (jsonEquals(jsonDecode(jsonEncode(next.toJson())), jsonDecode(jsonEncode(old.toJson())))) return true;
    doc = next;
    _undo.clear();
    _redo.clear();
    if (!wasBlank) remoteNotice = 'Projeto atualizado de outro aparelho. Desfazer não disponível para o que veio de lá.';
    if (selectedTrack >= doc.tracks.length) selectedTrack = math.max(0, doc.tracks.length - 1);
    _prune();
    _sync();
    final text = jsonEncode(doc.toJson());
    _lastSaved = text;
    await _store.put(_docKey, text);
    if (!_disposed) notifyListeners();
    unawaited(_mirrorTempo());
    return true;
  }

  /// Converte o clipe de áudio em notas MIDI pelo servidor e põe uma faixa de sintetizador nova
  /// com o clipe MIDI sobre o de áudio, num passo do desfazer. Devolve quantas notas entraram.
  /// Lança [ConversionCancelled] se [isCancelled] disser que sim, e [StateError] ou erro de API
  /// (com mensagem legível) nos outros problemas.
  Future<int> convertToMidi(
    String clipId, {
    void Function(String stage, double? progress)? onProgress,
    bool Function()? isCancelled,
    Duration pollEvery = const Duration(seconds: 1),
    MidiConvertOptions options = const MidiConvertOptions(),
  }) async {
    final f = _findClip(clipId);
    if (f == null) throw StateError('O clipe não existe mais.');
    if (!_canSync()) throw StateError('Entre na sua conta para converter áudio em notas.');
    final clip = f.$2;
    onProgress?.call('Enviando o áudio…', null);
    await sync.uploadSamples([clip.sample]);
    final r = await runAudioToMidi(
      _api,
      clip.sample,
      onProgress: onProgress,
      isCancelled: isCancelled,
      pollEvery: pollEvery,
      options: options,
      span: spanForClip(clip),
    );
    if (_disposed) throw ConversionCancelled();
    // o clipe pode ter mudado de lugar, de corte ou sumido enquanto o servidor trabalhava
    final now = _findClip(clipId);
    if (now == null) throw StateError('O clipe foi apagado durante a conversão.');
    final audio = now.$2;
    final notes = notesForClip(r, audio, doc.bpmAt(audio.start));
    if (notes.isEmpty) throw StateError('Não encontrei notas neste áudio.');
    edit((d) {
      final n = d.tracks.length;
      final name = _nextTrackName(d, TrackKind.synth);
      final midi = MidiClip(id: newId(), name: name, start: audio.start, length: math.max(d.clipBeats(audio), 0.01), notes: notes);
      d.tracks.add(DawTrack(id: newId(), name: name, color: n % Palette.tracks.length, kind: TrackKind.synth, midi: [midi]));
      selectedClip = midi.id;
      _select(n);
    });
    return notes.length;
  }

  /// Encaixa na grade atual.
  double snapBeat(double b) {
    if (snap == Snap.bar && !doc.meter.isSingle) return math.max(0.0, doc.meter.nearestBarStart(b));
    final g = snap == Snap.bar ? doc.meter.barBeatsAt(math.max(0.0, b)) : snap.beats;
    if (g <= 0) return b;
    return (b / g).round() * g;
  }

  // ------------------------------------------------------------------ faixas

  void addTrack() => edit((d) {
    final n = d.tracks.length;
    d.tracks.add(DawTrack(id: newId(), name: _nextTrackName(d, TrackKind.audio), color: n % Palette.tracks.length));
    _select(n);
  });

  /// `<Tipo> N` com o próximo N livre entre as faixas do mesmo tipo (Áudio 2 depois de Áudio 1,
  /// não Áudio 6 só porque há outras cinco faixas de outros tipos).
  static String _nextTrackName(DawDoc d, TrackKind kind) {
    final names = {for (final t in d.tracks) t.name};
    var k = d.tracks.where((t) => t.kind == kind).length + 1;
    while (names.contains('${kind.label} $k')) {
      k++;
    }
    return '${kind.label} $k';
  }

  /// Apaga a faixa. Se era um barramento, o que mandava para ele (envios, saídas e a automação
  /// desses envios) sai junto; os sidechains que apontavam para faixas depois dela acompanham a
  /// mudança de índice.
  void removeTrack(int i) {
    if (i < 0 || i >= doc.tracks.length) return;
    edit((d) {
      final gone = d.tracks.removeAt(i);
      _dropRoutesTo(gone.id);
      // apagar a pasta solta as filhas (seguem como faixas comuns, com a saída no master)
      if (gone.isGroup) {
        for (final t in d.tracks) {
          if (t.groupId == gone.id) t.groupId = null;
        }
      }
      _remapSidechains((old) => old == i ? -1 : (old > i ? old - 1 : old));
      selectedTrack = math.max(0, math.min(selectedTrack, d.tracks.length - 1));
    });
  }

  /// Duplica a faixa logo abaixo dela: clipes, instrumento, efeitos, envios e automação, com ids
  /// novos (e as automações de efeito apontando para os efeitos da cópia).
  ///
  /// Uma filha duplicada fica na mesma pasta (a cópia entra logo abaixo dela, dentro do bloco).
  /// Pasta não se duplica (a cópia do barramento ficaria sem as filhas e quebraria o bloco): nada
  /// acontece; duplique as faixas dela.
  void duplicateTrack(int i) {
    if (i < 0 || i >= doc.tracks.length || doc.tracks[i].isGroup) return;
    edit((d) {
      final src = d.tracks[i];
      // a cópia não sai armada nem monitorando: gravaria (e dobraria a entrada) sem pedir
      final copy = DawTrack.fromJson(jsonDecode(jsonEncode(src.toJson())))
        ..id = newId()
        ..name = _copyName(src.name)
        ..armed = false
        ..monitor = false;
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
      // a modulação leva junto: moduladores com ids novos e os efeitos da cópia como alvo
      copy.modulation = src.modulation.copy();
      for (final s in copy.modulation.sources) {
        s.id = newId();
      }
      copy.modulation.remapTargets(
        (t) => t.kind != AutoKind.effect ? t : (slotIds[t.ref] == null ? null : AutoTarget(AutoKind.effect, ref: slotIds[t.ref], param: t.param)),
      );
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
    // pasta: mover leva as filhas junto; largar dentro de uma pasta põe a faixa nela (ver
    // `planTrackMove` em track_groups.dart)
    final plan = planTrackMove(doc.tracks, from, to);
    if (plan == null) return;
    edit((d) {
      plan.applyGroups();
      setTrackOrder(plan.order);
    });
  }

  /// Troca a lista de faixas por [order] (o mesmo conjunto reordenado, mais faixas novas ou menos
  /// faixas apagadas); chamar dentro de um [edit]. Sidechains seguem as faixas, o que mandava para
  /// uma faixa que saiu é desligado, o roteamento de barramento que ficou apontando para trás é
  /// desfeito e a seleção acompanha a faixa.
  void setTrackOrder(List<DawTrack> order) {
    final d = doc;
    final selectedId = selectedTrack >= 0 && selectedTrack < d.tracks.length ? d.tracks[selectedTrack].id : null;
    final before = [for (final t in d.tracks) t.id];
    final kept = {for (final t in order) t.id};
    final gone = [
      for (final id in before)
        if (!kept.contains(id)) id,
    ];
    d.tracks
      ..clear()
      ..addAll(order);
    for (final id in gone) {
      _dropRoutesTo(id);
    }
    final after = _trackIndex();
    _remapSidechains((old) => old < before.length ? after[before[old]] ?? -1 : -1);
    _dropBackwardRoutes();
    if (selectedId != null) selectedTrack = after[selectedId] ?? math.max(0, math.min(selectedTrack, d.tracks.length - 1));
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
    if ((dock == Dock.effects || dock == Dock.modulation) && i >= 0 && i < doc.tracks.length) _effectsId = doc.tracks[i].id;
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
      edit((_) {
        a.$1.clips.remove(a.$2);
        // o outro clipe de um crossfade perde o par: o fade automático dele volta ao de antes
        reconcileAutoFades();
      });
    } else if (m != null) {
      edit((_) => m.$1.midi.remove(m.$2));
    }
  }

  /// O clipe [id] fica por cima: o que ele cobre dos outros clipes da mesma faixa sai (encurta,
  /// apara o começo, parte em dois ou some), como nos DAWs. Sem isso, clipes sobrepostos tocavam
  /// somados (áudio dobrado). Não faz checkpoint: vai junto da edição que o chamou.
  ///
  /// Com [crossfade], a travessia de borda (o de cima entra na cauda ou na cabeça do outro, sem
  /// engoli-lo) vira crossfade em vez de aparo: o de baixo mantém o pedaço coberto, com fade de
  /// potência constante do tamanho da sobreposição ([_tryCrossfade]). Sempre reconcilia os fades
  /// automáticos que perderam a sobreposição ([reconcileAutoFades]).
  void placeOnTop(String id, {bool crossfade = false}) {
    final d = doc;
    final a = _findClip(id);
    if (a != null) {
      final (t, top) = a;
      final s = top.start, e = d.clipEnd(top);
      for (final o in t.clips.toList()) {
        if (identical(o, top) || d.clipEnd(o) <= s + 1e-9 || o.start >= e - 1e-9) continue;
        final oEnd = d.clipEnd(o);
        if (crossfade && _tryCrossfade(o, top, oEnd: oEnd, topEnd: e)) continue;
        // segundos da origem entre as batidas (com warp, o andamento do áudio, não o do projeto;
        // com mapa de andamento, o tempo real entre elas)
        if (o.start >= s - 1e-9 && oEnd <= e + 1e-9) {
          t.clips.remove(o);
        } else if (o.start < s && oEnd > e) {
          final cut = d.sourceSeconds(o, o.start, e);
          t.clips.add(
            AudioClip.fromJson(o.toJson())
              ..id = newId()
              ..start = e
              ..offset = o.offset + cut
              ..length = o.length - cut
              ..fadeIn = 0
              // o fade zerado não é mais o do crossfade: sem a marca, o reconcile não o "devolve"
              ..autoFadeIn = null,
          );
          o
            ..length = d.sourceSeconds(o, o.start, s)
            ..fadeOut = 0
            ..autoFadeOut = null;
        } else if (o.start < s) {
          final keep = d.sourceSeconds(o, o.start, s);
          o
            ..length = keep
            ..fadeOut = math.min(o.fadeOut, keep);
        } else {
          final cut = d.sourceSeconds(o, o.start, e);
          o
            ..start = e
            ..offset = o.offset + cut
            ..length = o.length - cut
            ..fadeIn = 0
            ..autoFadeIn = null;
        }
      }
      reconcileAutoFades();
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
            ..notes = [for (final n in o.notes) n.copy()..start = n.start - d]
            ..controls = splitControls(o.controls, d).$2,
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
        shiftControls(o.controls, -d);
        // o pedal (bend, roda) que valia no novo começo segue valendo
        carryControls(o.controls, 0);
      }
    }
    if (editingClip == null && dock == Dock.editor) dock = Dock.none;
  }

  static const _fadeEps = 1e-9;

  /// A sobreposição de [early] e [late] (mesma faixa) quando é uma travessia de borda: [late]
  /// começa dentro de [early] e termina depois dele. Em batidas; nulo se um contém o outro ou não
  /// se tocam.
  double? _crossing(AudioClip early, AudioClip late) {
    final eEnd = doc.clipEnd(early), lEnd = doc.clipEnd(late);
    if (late.start <= early.start + _fadeEps || late.start >= eEnd - _fadeEps || lEnd <= eEnd + _fadeEps) return null;
    return eEnd - late.start;
  }

  /// Tenta transformar a sobreposição de [o] (já na faixa) com [top] em crossfade; devolve se
  /// conseguiu. Exige travessia de borda com o pedaço coberto de no máximo metade do menor dos dois
  /// (sem esse teto no comando do menu) e cabendo nos fades que já existem; senão o chamador apara como sempre. Com [force] (o comando
  /// do menu) sobrepõe também os fades do usuário, que a marca guarda para o desfazer da sobreposição.
  bool _tryCrossfade(AudioClip o, AudioClip top, {required double oEnd, required double topEnd, bool force = false}) {
    final oFirst = o.start < top.start;
    final early = oFirst ? o : top, late = oFirst ? top : o;
    final overlap = _crossing(early, late);
    if (overlap == null) return false;
    final eBeats = oFirst ? oEnd - o.start : topEnd - top.start, lBeats = oFirst ? topEnd - top.start : oEnd - o.start;
    if (!force && overlap > math.min(eBeats, lBeats) / 2 + _fadeEps) return false;
    // segundos da origem de cada lado (com warp e mapa de andamento, o vigente na borda)
    final outSecs = doc.sourceSeconds(early, late.start, late.start + overlap);
    final inSecs = doc.sourceSeconds(late, late.start, late.start + overlap);
    // o fade que sai/entra no lado que não é do crossfade (o do usuário) segue como está
    if (!force && ((early.fadeOut > 0 && early.autoFadeOut == null) || (late.fadeIn > 0 && late.autoFadeIn == null))) return false;
    if (early.fadeIn + outSecs > early.length + _fadeEps || inSecs + late.fadeOut > late.length + _fadeEps) return false;
    early
      ..autoFadeOut = early.autoFadeOut ?? AutoFade(early.fadeOut, early.fadeOutShape)
      ..fadeOut = outSecs
      ..fadeOutShape = FadeShape.equalPower;
    late
      ..autoFadeIn = late.autoFadeIn ?? AutoFade(late.fadeIn, late.fadeInShape)
      ..fadeIn = inSecs
      ..fadeInShape = FadeShape.equalPower;
    return true;
  }

  /// Ajusta os fades que o crossfade automático gerou ao estado atual das sobreposições: o que
  /// ainda cruza outro clipe da faixa acompanha o novo tamanho; o que perdeu a sobreposição (ou
  /// não cabe mais) volta ao fade de antes. Fade sem marca (do usuário) nunca é tocado. Não faz
  /// checkpoint: vai junto da edição que o chamou.
  void reconcileAutoFades() {
    for (final t in doc.tracks) {
      for (final c in t.clips) {
        final ai = c.autoFadeIn, ao = c.autoFadeOut;
        if (ai != null) {
          double? best;
          for (final p in t.clips) {
            if (identical(p, c)) continue;
            final ov = _crossing(p, c);
            if (ov != null && (best == null || ov > best)) best = ov;
          }
          final secs = best == null ? null : doc.sourceSeconds(c, c.start, c.start + best);
          if (secs == null || secs + c.fadeOut > c.length + _fadeEps) {
            c
              ..fadeIn = math.min(ai.prevLength, math.max(0.0, c.length - c.fadeOut))
              ..fadeInShape = ai.prevShape
              ..autoFadeIn = null;
          } else {
            c.fadeIn = secs;
          }
        }
        if (ao != null) {
          double? best;
          for (final p in t.clips) {
            if (identical(p, c)) continue;
            final ov = _crossing(c, p);
            if (ov != null && (best == null || ov > best)) best = ov;
          }
          final secs = best == null ? null : doc.sourceSeconds(c, doc.clipEnd(c) - best, doc.clipEnd(c));
          if (secs == null || secs + c.fadeIn > c.length + _fadeEps) {
            c
              ..fadeOut = math.min(ao.prevLength, math.max(0.0, c.length - c.fadeIn))
              ..fadeOutShape = ao.prevShape
              ..autoFadeOut = null;
          } else {
            c.fadeOut = secs;
          }
        }
      }
    }
  }

  /// Crossfade nas sobreposições do clipe [id] (o comando do menu, para clipes que já se
  /// sobrepõem): cada travessia de borda dele com outro clipe da faixa ganha fade de saída no
  /// anterior e de entrada no posterior, com o tamanho da sobreposição e potência constante, em um
  /// passo de desfazer. Com [wholeTrack], vale para todos os pares da faixa do clipe. Devolve
  /// quantas sobreposições viraram crossfade e diz o resultado em [notice] (também quando não há
  /// nada a fazer).
  int crossfadeOverlaps(String id, {bool wholeTrack = false}) {
    final a = _findClip(id);
    if (a == null) return 0;
    final (t, clicked) = a;
    final pairs = <(AudioClip, AudioClip)>[];
    for (final x in t.clips) {
      for (final y in t.clips) {
        if (identical(x, y) || _crossing(x, y) == null) continue;
        if (wholeTrack || identical(x, clicked) || identical(y, clicked)) pairs.add((x, y));
      }
    }
    if (pairs.isEmpty) {
      notice = wholeTrack
          ? 'Nenhum clipe desta faixa cruza a borda de outro: não há crossfade a aplicar.'
          : 'Este clipe não cruza a borda de outro clipe da faixa: não há crossfade a aplicar.';
      notifyListeners();
      return 0;
    }
    var done = 0;
    checkpoint();
    mutate((d) {
      for (final (early, late) in pairs) {
        if (_tryCrossfade(early, late, oEnd: d.clipEnd(early), topEnd: d.clipEnd(late), force: true)) done++;
      }
    });
    final skipped = pairs.length - done;
    notice = '${done == 1 ? '1 crossfade aplicado' : '$done crossfades aplicados'}${skipped > 0 ? ' ($skipped não coube nos fades dos clipes)' : ''}.';
    notifyListeners();
    return done;
  }

  /// Tamanho, em segundos do áudio, dos fades do clipe [id] (nulo deixa o lado como está);
  /// desfazível. Cada lado cabe no que sobra do clipe depois do outro fade (o valor é limitado a
  /// isso). Digitar o tamanho é decisão do usuário: o fade deixa de ser automático.
  void setFadeLength(String id, {double? fadeIn, double? fadeOut}) {
    final f = _findClip(id);
    if (f == null) return;
    final c = f.$2;
    double fit(double v, double other) => (v.isFinite ? v : 0.0).clamp(0.0, math.max(0.0, c.length - other)).toDouble();
    final newIn = fadeIn == null ? c.fadeIn : fit(fadeIn, c.fadeOut);
    final newOut = fadeOut == null ? c.fadeOut : fit(fadeOut, newIn);
    if ((newIn - c.fadeIn).abs() < 1e-9 && (newOut - c.fadeOut).abs() < 1e-9) return;
    edit((_) {
      if (fadeIn != null) {
        c.fadeIn = newIn;
        c.autoFadeIn = null;
      }
      if (fadeOut != null) {
        c.fadeOut = newOut;
        c.autoFadeOut = null;
      }
    });
  }

  /// Curva dos fades do clipe [id] (nulo deixa o lado como está); desfazível. Escolher a curva é
  /// decisão do usuário: o fade deixa de ser automático (a sobreposição não o reverte mais).
  void setFadeShapes(String id, {FadeShape? fadeIn, FadeShape? fadeOut}) {
    final f = _findClip(id);
    if (f == null) return;
    final c = f.$2;
    if ((fadeIn == null || fadeIn == c.fadeInShape) && (fadeOut == null || fadeOut == c.fadeOutShape)) return;
    edit((_) {
      if (fadeIn != null) {
        c.fadeInShape = fadeIn;
        c.autoFadeIn = null;
      }
      if (fadeOut != null) {
        c.fadeOutShape = fadeOut;
        c.autoFadeOut = null;
      }
    });
  }

  void duplicateSelected() {
    final a = selection;
    if (a != null) {
      final (t, c) = a;
      final copy = AudioClip.fromJson(c.toJson())
        ..id = newId()
        ..start = doc.clipEnd(c);
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
    final audioCuts = audio.where((f) => f.$2.start < at && doc.clipEnd(f.$2) > at).toList();
    final midiCuts = midi.where((f) => f.$2.start < at && f.$2.end > at).toList();
    if (audioCuts.isEmpty && midiCuts.isEmpty) return;
    edit((d) {
      for (final (t, c) in audioCuts) {
        final secs = d.sourceSeconds(c, c.start, at);
        final right = AudioClip.fromJson(c.toJson())
          ..id = newId()
          ..start = at
          ..offset = c.offset + secs
          ..length = c.length - secs
          ..fadeIn = 0
          ..autoFadeIn = null;
        c
          ..length = secs
          ..fadeOut = 0
          ..autoFadeOut = null;
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
            _occupied(doc.tracks[ti], start, doc.beatAtSeconds(doc.secondsAt(start) + info.duration))) {
          ti = doc.tracks.length;
          doc.tracks.add(DawTrack(id: newId(), name: _baseName(name), color: ti % Palette.tracks.length));
        }
        final clip = AudioClip(id: newId(), sample: hash, start: start, length: info.duration);
        doc.tracks[ti].clips.add(clip);
        selectedClip = clip.id;
        selectedTrack = ti;
      } catch (e) {
        error = 'Não deu para abrir $name: é um formato de áudio que $_thisHost decodifica?';
      }
    }
    status = null;
    _prune();
    _sync();
    _scheduleSave();
    notifyListeners();
  }

  /// O instrumento em que as faixas melódicas de um .mid entram (a bateria do canal 10 é sempre
  /// bateria); a última escolha de "Importar como", que fica valendo na sessão.
  TrackKind midiImportKind = TrackKind.synth;

  /// Importa um arquivo MIDI (.mid): uma faixa por faixa do arquivo (do tipo [midiImportKind], ou o
  /// que [chooseKind] escolher; bateria no canal 10), cada uma com um clipe (com o nome da trilha) a
  /// partir de [at] (padrão: o cursor), tudo num passo do desfazer. [chooseKind] só é chamado se o
  /// arquivo tem faixas melódicas; devolver null cancela a importação. Se o arquivo traz andamento
  /// ou compasso diferentes dos do projeto, [confirmTempo] decide se eles passam para o projeto.
  /// Erro de arquivo vai para [error] (mensagem legível) e devolve null; sucesso devolve o
  /// [MidiImportReport], com os avisos. A lógica está em `midi_file.dart`.
  Future<MidiImportReport?> importMidiBytes(
    String name,
    Uint8List bytes, {
    Future<bool> Function(MidiFileData data)? confirmTempo,
    Future<TrackKind?> Function(MidiFileData data)? chooseKind,
    TrackKind? kind,
    double? at,
  }) async {
    if (_blockedByRecording('importar MIDI')) return null;
    status = 'Lendo $name…';
    notifyListeners();
    final MidiFileData data;
    try {
      data = await parseMidiFile(bytes);
    } on MidiFormatException catch (e) {
      status = null;
      error = 'Não deu para importar $name: ${e.message}';
      notifyListeners();
      return null;
    } catch (_) {
      status = null;
      error = 'Não deu para importar $name: o arquivo MIDI está corrompido.';
      notifyListeners();
      return null;
    }
    status = null;
    if (_disposed) return null;
    var melodic = kind ?? midiImportKind;
    if (chooseKind != null && kind == null && data.tracks.any((t) => !t.drums)) {
      final k = await chooseKind(data);
      if (k == null || _disposed) return null;
      melodic = k;
    }
    var useTempo = false;
    if (confirmTempo != null && midiTempoDiffers(data, doc)) useTempo = await confirmTempo(data);
    if (_disposed) return null;
    final bar = useTempo ? (data.beatsPerBar ?? doc.beatsPerBar) : doc.beatsPerBar;
    // o clipe fecha no compasso do mapa que o projeto terá (o do arquivo, se ele vai para o projeto)
    final importedMap = useTempo ? importedMeter(data) : null;
    final meter = importedMap != null ? MeterMap(importedMap.beatsPerBar, importedMap.changes) : doc.meter;
    final items = midiImportTracks(data, beatsPerBar: bar, start: at ?? snapBeat(beat.value), newId: newId, melodic: melodic, meter: meter);
    edit((d) {
      if (useTempo) applyImportedTempo(d, data);
      final first = d.tracks.length;
      for (final it in items) {
        final n = d.tracks.length;
        final trackName = it.name.isNotEmpty ? it.name : _nextTrackName(d, it.kind);
        // o clipe leva o nome da trilha (um arquivo sem nome de trilha usa o da faixa nova)
        if (it.clip.name.isEmpty) it.clip.name = trackName;
        d.tracks.add(DawTrack(id: newId(), name: trackName, color: n % Palette.tracks.length, kind: it.kind, midi: [it.clip]));
      }
      selectedClip = items.first.clip.id;
      _select(first);
    });
    if (useTempo) await _mirrorTempo();
    final warnings = [...data.warnings];
    final bpms = [for (final p in data.tempoMap) p.bpm];
    if (useTempo && data.tempoPoints.length < data.tempoMap.length) {
      final total = data.tempoMap.length - 1, kept = data.tempoPoints.length - 1;
      warnings.add(
        'O arquivo tem $total ${total == 1 ? 'mudança' : 'mudanças'} de andamento; fundi as que diferem menos de '
        '${midiTempoEpsilon.toString().replaceAll('.', ',')} BPM e $kept ${kept == 1 ? 'ficou' : 'ficaram'} no mapa '
        '(o limite é $midiMaxTempoPoints pontos).',
      );
    } else if (!useTempo && data.hasTempoChanges) {
      warnings.add('O arquivo muda de andamento no meio (de ${bpms.reduce(math.min).round()} a ${bpms.reduce(math.max).round()} BPM); mantive o do projeto.');
    }
    return MidiImportReport(tracks: items.length, notes: data.noteCount, tempoApplied: useTempo, warnings: warnings);
  }

  /// Leva o mapa de andamento e o de compassos do arquivo para o documento (substituem os do
  /// projeto; as notas continuam nas mesmas batidas). Sem andamento ou sem compasso no arquivo, o
  /// respectivo do projeto fica como está.
  void applyImportedTempo(DawDoc d, MidiFileData data) {
    final t = importedTempo(data);
    if (t != null) {
      d.bpm = t.bpm;
      d.tempoMap = t.points;
    }
    final m = importedMeter(data);
    if (m != null) {
      d.beatsPerBar = m.beatsPerBar;
      d.meterMap = m.changes;
    }
  }

  /// Decodifica, guarda no aparelho e registra no motor e no documento (se ainda não estiver);
  /// devolve o sha-256.
  Future<String> _ingest(String name, Uint8List bytes) async {
    final hash = await _engine.sha256Hex(bytes);
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
      error = 'Não deu para abrir $name: é um formato de áudio que $_thisHost decodifica?';
    }
    notifyListeners();
  }

  bool _occupied(DawTrack t, double from, double to) => t.clips.any((c) => c.start < to && doc.clipEnd(c) > from);

  static String _baseName(String file) {
    final dot = file.lastIndexOf('.');
    final n = dot > 0 ? file.substring(0, dot) : file;
    return n.length > 40 ? n.substring(0, 40) : n;
  }

  void clearError() {
    error = null;
    notifyListeners();
  }

  void clearNotice() {
    notice = null;
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
      d.tracks.add(DawTrack(id: newId(), name: _nextTrackName(d, kind), color: n % Palette.tracks.length, kind: kind));
      _select(n);
    });
  }

  /// Clipe MIDI vazio na faixa, começando em [start] (batidas); padrão: um compasso. Fica
  /// selecionado e é devolvido.
  MidiClip createMidiClip(int track, double start, {double? length}) {
    if (!_isInstrument(track)) throw ArgumentError.value(track, 'track', 'clipe MIDI só entra em faixa de instrumento');
    final t = doc.tracks[track];
    final len = length != null && length > 0 ? length : doc.meter.barBeatsAt(math.max(0.0, start));
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
    calls.addAll(_releaseControls());
    _publishLive();
    return calls;
  }

  /// Volta ao repouso o bend, a roda e o pedal ao vivo, onde estiverem.
  List<List<Object>> _releaseControls() {
    final calls = <List<Object>>[
      for (final e in _ccTrack.entries)
        if (_isInstrument(e.value)) _liveControlCall(e.value, e.key >> 1, MidiCc.neutral),
    ];
    _ccTrack.clear();
    _sustain = false;
    liveReset.value++;
    return calls;
  }

  static List<Object> _liveControlCall(int track, int cc, double value) => cc == ccBend ? ['live_bend', track, value] : ['live_cc', track, cc, value];

  /// Manda um valor de controle ao vivo (bend −1..1, modulação e pedal 0..1) para a faixa de
  /// entrada (ou [track]). O motor grava o que chega junto das notas quando está gravando.
  ///
  /// O valor tem a mesma resolução seja qual for a origem ([quantizeControl]). O que está fora do
  /// repouso é rastreado por (controle, origem): o controlador MIDI segue a faixa de entrada e volta
  /// ao repouso na faixa que deixou; a roda da tela ([screen]) tem a sua própria, e as duas não
  /// devolvem ao repouso o valor uma da outra. Bateria ignora (não há o que soar nem gravar).
  void liveControl(int cc, double value, {int? track, bool screen = false}) {
    if (!ready || !ccKinds.contains(cc) || !value.isFinite) return;
    final t = track ?? _inputTrack;
    if (!_isInstrument(t) || doc.tracks[t].kind == TrackKind.drums) return;
    final v = quantizeControl(cc, value);
    final key = cc << 1 | (screen ? 1 : 0);
    final calls = <List<Object>>[];
    final before = _ccTrack[key];
    // a origem deixou a faixa antiga fora do repouso e agora fala com outra: a antiga volta ao
    // repouso seja qual for o valor novo (soltar o pedal já na faixa nova não pode deixar a antiga presa)
    if (before != null && before != t && _isInstrument(before)) calls.add(_liveControlCall(before, cc, MidiCc.neutral));
    calls.add(_liveControlCall(t, cc, v));
    if (v == MidiCc.neutral) {
      _ccTrack.remove(key);
    } else {
      _ccTrack[key] = t;
    }
    _wake();
    _engine.calls(calls);
  }

  /// Pitch bend ao vivo, −1..1 (a roda do teclado da tela, o controlador MIDI).
  void pitchBend(double value, {int? track, bool screen = false}) => liveControl(ccBend, value, track: track, screen: screen);

  /// Roda de modulação ao vivo, 0..1.
  void modWheel(double value, {int? track, bool screen = false}) => liveControl(ccMod, value, track: track, screen: screen);

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
    autoRec.value(track, AutoTarget(AutoKind.instrument, param: id), v);
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
    _keyboardOctaves[_keyboardKind] = o;
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

  /// Faixa que o teclado do computador e o MIDI tocam: a selecionada, a não ser que haja faixa de
  /// instrumento armada e a selecionada não seja uma delas; aí a primeira armada. Como nos DAWs,
  /// armar leva a entrada para a faixa, e o que se toca é o que ela grava.
  int get _inputTrack {
    final sel = selectedTrack;
    if (_isInstrument(sel) && doc.tracks[sel].armed) return sel;
    for (var i = 0; i < doc.tracks.length; i++) {
      if (doc.tracks[i].armed && doc.tracks[i].kind.isInstrument) return i;
    }
    return sel;
  }

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
      final t = _inputTrack;
      noteOn(pitch, velocity: keyboardVelocity, track: t);
      if (_live.contains((t, pitch))) _keyNotes[key] = (t, pitch);
    } else {
      switch (Keymap.instance.playingAction(key)?.id) {
        case 'kbd.octaveDown':
          setKeyboardOctave(keyboardOctave - 1);
        case 'kbd.octaveUp':
          setKeyboardOctave(keyboardOctave + 1);
        case 'kbd.velocityDown':
          setKeyboardVelocity(keyboardVelocity - 0.1);
        case 'kbd.velocityUp':
          setKeyboardVelocity(keyboardVelocity + 0.1);
      }
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
      error = e.message ?? '${_thisHost[0].toUpperCase()}${_thisHost.substring(1)} não dá acesso a MIDI.';
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
    // MIDI learn: um CC, bend ou pressão mapeado (ou o que aprende agora) é do mapeamento, não
    // expressão do instrumento; o painel de CC 120..127 nunca passa por aqui
    if ((type == 0xB0 || type == 0xE0 || type == 0xD0) && (_learn != null || !doc.midiMap.isEmpty) && midiLearn.handle(status, data1, data2)) return;
    if (type == 0x90 && data2 > 0) {
      _midiNoteOn(data1, data2 / 127);
    } else if (type == 0x80 || type == 0x90) {
      // note on com velocidade 0 é note off (running status dos teclados)
      _midiNoteOff(data1);
    } else if (type == 0xE0) {
      // pitch bend: 14 bits (LSB, MSB), 8192 no centro
      pitchBend((((data2 & 0x7F) << 7 | (data1 & 0x7F)) - 8192) / 8192);
    } else if (type == 0xB0) {
      switch (data1) {
        case 1:
          modWheel((data2 & 0x7F) / 127);
        case 64:
          _setSustain(data2 >= 64);
        case 121: // reset dos controles: bend, roda e pedal em repouso
          _engine.calls(_releaseControls());
        case 120: // all sound off: corta na hora, inclusive caudas
          _midiAllOff();
          _ccTrack.clear();
          _sustain = false;
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
    final t = _inputTrack;
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
    _midiNotes.remove(pitch);
    _liveOff([(t, pitch)]);
  }

  /// O pedal vai ao motor, que segura as notas soltas até ele subir (e grava o pedal ao gravar).
  void _setSustain(bool on) {
    if (on == _sustain) return;
    _sustain = on;
    liveControl(ccSustain, on ? 1.0 : 0.0);
  }

  void _midiAllOff() {
    _liveOff([for (final e in _midiNotes.entries) (e.value, e.key)]);
    _midiNotes.clear();
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

  /// Efeitos por cadeia e envios por faixa que o motor comporta (`MAX_SLOTS` e `MAX_SENDS` em
  /// engine/src/mixer.rs): o 17º seria descartado em silêncio (o cartão aparece e não soa).
  static const maxEffectsPerChain = 16;
  static const maxSendsPerTrack = 16;

  /// Dica dos botões de adicionar quando a cadeia (ou a lista de envios) já está cheia.
  static const effectLimitHint = 'Limite de $maxEffectsPerChain efeitos por faixa';
  static const sendLimitHint = 'Limite de $maxSendsPerTrack envios por faixa';

  /// A cadeia de [track] (−1 = master) ainda tem lugar para mais um efeito.
  bool canAddEffect(int track) => (_chain(track)?.length ?? maxEffectsPerChain) < maxEffectsPerChain;

  /// A faixa ainda tem lugar para mais um envio.
  bool canAddSend(int track) => track >= 0 && track < doc.tracks.length && doc.tracks[track].sends.length < maxSendsPerTrack;

  /// Adiciona um efeito no padrão no fim da cadeia (ou na posição [at]); desfazível. Cadeia cheia
  /// ([maxEffectsPerChain]): [StateError] (a interface desabilita o botão antes).
  EffectSlot addEffect(int track, EffectKind kind, {int? at}) {
    final chain = _chain(track);
    if (chain == null) throw ArgumentError.value(track, 'track', 'faixa inexistente');
    if (chain.length >= maxEffectsPerChain) throw StateError('$effectLimitHint: o motor não toca mais que isso.');
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
    var v = _fit(spec, value);
    // cruzamentos: a mesma regra do motor (o alto 1,5× acima do baixo); o valor efetivo é o que fica
    if ((slot.kind == EffectKind.multiband || slot.kind == EffectKind.imager) && (id == 0 || id == 1)) {
      v = _fit(spec, id == 0 ? math.min(v, slot.param(1) / 1.5) : math.max(v, slot.param(0) * 1.5));
    }
    if (slot.params.containsKey(id) && slot.params[id] == v) return;
    if (undoable) checkpoint();
    autoRec.value(track, AutoTarget(AutoKind.effect, ref: slotId, param: id), v);
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
      // o motor só comporta [maxSendsPerTrack] envios por faixa: o seguinte não soaria
      if (t.sends.length >= maxSendsPerTrack) return false;
      edit((_) => t.sends.add(Send(target: busId, level: lv ?? defaultSendLevel, pre: pre ?? false)));
      return true;
    }
    final newLevel = lv ?? send.level, newPre = pre ?? send.pre;
    if (newLevel == send.level && newPre == send.pre) return true;
    if (undoable) checkpoint();
    if (newLevel != send.level) autoRec.value(track, AutoTarget(AutoKind.send, ref: busId), newLevel);
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
  ///
  /// Uma filha de pasta que passa a sair para outro destino que não a pasta deixa de passar por ela:
  /// sai da pasta junto (desce para depois do bloco), senão ficaria recuada e contada na pasta sem
  /// ser afetada por ela. A interface avisa antes ([DawGroupsController.folderLeftByOutput]).
  bool setOutput(int track, String? busId) {
    if (track < 0 || track >= doc.tracks.length) return false;
    if (busId != null && !busTargets(track).any((b) => b.id == busId)) return false;
    final t = doc.tracks[track];
    if (t.output == busId && folderLeftByOutput(track, busId) == null) return true;
    final folder = folderLeftByOutput(track, busId);
    edit((_) {
      if (folder != null) takeOutOfFolder(t, folder);
      t.output = busId;
    });
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

  /// Efeito cujo indicador (ver [fxMeter]) o motor manda em [fxMeter]; null desliga. Segue o
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

  /// Indicador do efeito observado e espectro da faixa observada
  /// (dB por faixa linear de frequência, de 0 à metade da taxa), ao vivo.
  /// A convenção é do efeito: dB de redução (≥ 0) no compressor, gate, limitador e de-esser; as reduções
  /// das 3 bandas em décimos de dB, 8 bits cada, no multibanda; a correlação (−1 a 1) na imagem estéreo.
  final fxMeter = ValueNotifier<double>(0);
  final spectrum = ValueNotifier<Float32List?>(null);

  /// Loudness do master ao vivo (BS.1770-4, depois do limitador): momentâneo, curto prazo,
  /// integrado, true peak e faixa. "Sem medida" (−200) enquanto nada soou.
  final loudness = ValueNotifier<LoudnessReading>(const LoudnessReading());

  void _onLoudness(LoudnessReading r) {
    if (!_disposed) loudness.value = r;
  }

  /// Zera a medida de loudness do master (integrado, faixa, máximos e true peak): a medição
  /// recomeça do que soar daqui em diante.
  void resetLoudness() {
    _engine.calls([
      ['loudness_reset'],
    ]);
    loudness.value = const LoudnessReading();
  }

  /// O que a última exportação com normalização de loudness fez (null se a última não pediu, ou
  /// ainda não terminou).
  LoudnessReport? exportReport;

  /// Taxa de amostragem do motor (a do contexto de áudio do aparelho: 44,1 ou 48 kHz, em geral):
  /// o espectro vai de 0 à metade dela.
  double engineRate = 48000;

  // ------------------------------------------------------------------ gravação, exportação, bounce

  /// Gravando agora (inclusive durante a contagem) e em que fase.
  bool recording = false;
  bool countingIn = false;

  /// Batida onde a gravação em andamento vale (o cursor quando ela começou); null sem gravação.
  double? get recordStart => _rec?.start;

  /// Nível de pico da entrada (0..1), ao vivo, para o medidor das faixas armadas.
  final inputLevel = ValueNotifier<double>(0);

  /// Entradas de áudio disponíveis (id, nome) e a escolhida (null = a padrão do sistema).
  List<(String, String)> inputDevices = const [];
  String? inputDevice;

  /// Um render fora de tempo real (exportação ou congelamento) em andamento: um por vez.
  bool get rendering => _rendering;
  bool _rendering = false;

  /// A entrada de áudio está aberta (o navegador mostra o aviso de microfone).
  bool get inputOpen => _inputOpen;
  bool _inputOpen = false;
  Future<bool>? _opening;

  /// Latência de entrada que o navegador informou ao abrir (s).
  double _inputLatency = 0;

  /// Quanto o som sai depois do transporte (s): a latência de saída do aparelho mais a do próprio
  /// motor (PDC dos efeitos, cadeia do master e limitador de segurança).
  double get _outputLatency {
    final v = _engine.latency + _engine.engineLatency;
    return v.isFinite && v > 0 ? v : 0;
  }

  /// Latência de ida e volta de uma faixa monitorada (s): a entrada do aparelho, o motor com a PDC
  /// e a saída do aparelho. É o que o músico ouve de atraso entre tocar e escutar.
  double get monitorLatency => _outputLatency + (_inputLatency.isFinite && _inputLatency > 0 ? _inputLatency : 0);

  /// A entrada escolhida fica no aparelho (é do hardware, não do projeto).
  static const _inputKey = 'rec:input';

  _Recording? _rec;

  /// Começando (abrindo a entrada) ou salvando uma gravação: outro gravar espera.
  bool _recBusy = false;

  /// Quem espera as notas de cada captura desligada, na ordem (null: ninguém, a captura foi
  /// cancelada). O motor manda uma mensagem de notas por captura desligada.
  final _notesWaiting = Queue<Completer<List<RecordedNote>>?>();

  /// Tempo desde o último estado do motor: estima a posição entre um estado e outro.
  final _stateClock = Stopwatch();

  // o que a contagem troca no motor enquanto dura (o sync manda estes no lugar do documento)
  (bool, double, double)? _loopOverride;
  bool _countMetronome = false;
  bool _autoSuppressed = false;

  /// Arma a faixa para gravar: a de áudio grava a entrada; a de instrumento, as notas tocadas nela
  /// (o teclado e o MIDI passam a tocá-la). Armar a primeira faixa de áudio abre a entrada (o
  /// navegador pede o microfone; negado, a faixa desarma e o motivo fica em [error]); desarmar a
  /// última que precisava dela fecha. Barramento não grava. Fica no documento, fora do desfazer.
  void setArmed(int track, bool on) {
    if (track < 0 || track >= doc.tracks.length) return;
    final t = doc.tracks[track];
    if (t.kind == TrackKind.bus || t.armed == on) return;
    edit((_) => t.armed = on, undoable: false);
    if (t.kind != TrackKind.audio) return;
    if (on) {
      unawaited(_needInput(t.id, (t) => t.armed = false));
    } else {
      _releaseInputIfIdle();
    }
  }

  /// A entrada passa pela cadeia da faixa de áudio ao vivo (antes dos inserts e do fader). Abre a
  /// entrada como [setArmed]. Só faixas de áudio; fora do desfazer.
  void setMonitor(int track, bool on) {
    if (track < 0 || track >= doc.tracks.length) return;
    final t = doc.tracks[track];
    if (t.kind != TrackKind.audio || t.monitor == on) return;
    edit((_) => t.monitor = on, undoable: false);
    if (on) {
      unawaited(_needInput(t.id, (t) => t.monitor = false));
    } else {
      _releaseInputIfIdle();
    }
  }

  /// Abre a entrada para a faixa [id]; sem ela, desfaz com [undo] o que a pediu.
  Future<void> _needInput(String id, void Function(DawTrack t) undo) async {
    final ok = await _ensureInput();
    if (_disposed) return;
    if (ok) {
      // desarmada enquanto o navegador perguntava
      _releaseInputIfIdle();
      return;
    }
    final t = doc.tracks.where((t) => t.id == id).firstOrNull;
    if (t != null) mutate((_) => undo(t));
  }

  /// Ao abrir o projeto com faixa armada ou monitorando: a entrada volta; sem ela, as faixas
  /// desarmam (senão pareceriam prontas para gravar).
  Future<void> _restoreInput() async {
    if (await _ensureInput() || _disposed) return;
    mutate((d) {
      for (final t in d.tracks) {
        if (t.kind != TrackKind.audio) continue;
        t
          ..armed = false
          ..monitor = false;
      }
    });
  }

  Future<bool> _ensureInput() {
    if (_inputOpen) return Future.value(true);
    return _opening ??= _openInput().whenComplete(() => _opening = null);
  }

  Future<bool> _openInput() async {
    _hookCapture();
    Object? failure;
    for (final device in {inputDevice, null}) {
      try {
        final latency = await _engine.startInput(device);
        if (_disposed) {
          _quietly(_engine.stopInput);
          return false;
        }
        _inputLatency = latency.isFinite ? latency.clamp(0.0, 1.0).toDouble() : 0;
        _inputOpen = true;
        if (device != inputDevice) {
          // a escolhida não abriu (desconectada) e a padrão sim
          error = 'A entrada de áudio escolhida não abriu (foi desconectada?): usando a entrada padrão.';
          _chooseInput(null);
        }
        notifyListeners();
        // com a permissão dada, a lista já vem com os nomes
        unawaited(_listInputs());
        return true;
      } catch (e) {
        failure ??= e;
        // permissão negada não muda com outra entrada
        if (_denied(e)) break;
      }
    }
    if (!_disposed) {
      error = _inputError(failure!);
      notifyListeners();
    }
    return false;
  }

  void _hookCapture() {
    _engine.onRecord = _onRecordBlock;
    _engine.onInputLevel = _onInputLevel;
    _engine.onCaptureEnd = _onCaptureEnd;
    _engine.onInputLost = _onInputLost;
  }

  /// A entrada caiu sozinha (cabo, interface desligada, permissão revogada): a ponte já fechou.
  /// As faixas seguem armadas (armar de novo, ou gravar, tenta reabrir); uma gravação em andamento
  /// segue com silêncio no lugar do que viria.
  void _onInputLost(String message) {
    if (_disposed) return;
    _inputOpen = false;
    inputLevel.value = 0;
    error = message;
    notifyListeners();
  }

  void _onInputLevel(double peak) {
    if (_disposed) return;
    inputLevel.value = peak.isFinite ? peak.clamp(0.0, 1.0).toDouble() : 0;
  }

  /// Fecha a entrada quando nada precisa dela (o aviso de microfone do navegador apaga).
  void _releaseInputIfIdle() {
    if (!_inputOpen || recording || _recBusy || _opening != null) return;
    if (doc.tracks.any((t) => t.kind == TrackKind.audio && (t.armed || t.monitor))) return;
    _inputOpen = false;
    inputLevel.value = 0;
    _quietly(_engine.stopInput);
    notifyListeners();
  }

  /// Chama o motor sem deixar escapar um erro dele (entrada que já fechou, motor sem gravação).
  static void _quietly(Future<void> Function() f) {
    try {
      unawaited(f().catchError((Object _) {}));
    } catch (_) {}
  }

  static bool _denied(Object e) {
    final s = e is StateError ? e.message : '$e';
    return s.contains('NotAllowed') || s.contains('Permission') || s.contains('permiss') || s.contains('negou') || s.contains('denied');
  }

  /// "este navegador" na web, "este aparelho" no app: as mensagens ao usuário falam de onde ele está.
  static String get _thisHost => kIsWeb ? 'este navegador' : 'este aparelho';

  /// O motivo de a entrada não abrir, para o usuário.
  static String _inputError(Object e) {
    if (e is UnsupportedError) return e.message ?? '${_thisHost[0].toUpperCase()}${_thisHost.substring(1)} não dá acesso ao microfone.';
    if (e is UnimplementedError) return 'A gravação de áudio ainda não funciona neste aparelho.';
    if (e is StateError) return e.message;
    final s = '$e';
    if (_denied(e)) {
      return kIsWeb
          ? 'O navegador negou o acesso ao microfone. Libere o microfone nas permissões do site e tente de novo.'
          : 'O Android negou o acesso ao microfone. Libere o microfone nas permissões do app (Configurações › Apps › jopendaw › Permissões) e tente de novo.';
    }
    if (s.contains('NotFound') || s.contains('Overconstrained')) return 'Nenhuma entrada de áudio encontrada: conecte um microfone ou escolha outra entrada.';
    if (s.contains('NotReadable')) return 'A entrada de áudio está ocupada por outro programa ou foi desconectada.';
    return 'Não deu para abrir a entrada de áudio: $s';
  }

  /// Pede acesso ao microfone (se ainda não tem) e lista as entradas. Se ninguém precisava da
  /// entrada, ela fecha de novo depois.
  Future<void> refreshInputDevices() async {
    final wasOpen = _inputOpen;
    await _ensureInput();
    if (_disposed) return;
    await _listInputs();
    if (!wasOpen) _releaseInputIfIdle();
  }

  Future<void> _listInputs() async {
    final List<(String, String)> list;
    try {
      list = await _engine.inputDevices();
    } catch (_) {
      return;
    }
    if (_disposed) return;
    inputDevices = list;
    final chosen = inputDevice;
    // lista vazia é falta de permissão, não entrada que saiu
    if (chosen != null && list.isNotEmpty && !list.any((d) => d.$1 == chosen)) {
      _chooseInput(null);
      error = 'A entrada de áudio escolhida foi desconectada: usando a entrada padrão.';
      if (_inputOpen && !recording && !_recBusy) unawaited(_reopenInput());
    }
    notifyListeners();
  }

  /// Troca a entrada (null = a padrão do sistema); aberta, ela reabre na nova. Não troca no meio
  /// de uma gravação.
  Future<void> setInputDevice(String? id) async {
    if (id == inputDevice) return;
    if (recording || _recBusy) {
      error = 'Pare a gravação antes de trocar a entrada.';
      notifyListeners();
      return;
    }
    _chooseInput(id);
    notifyListeners();
    if (_inputOpen) await _reopenInput();
  }

  void _chooseInput(String? id) {
    inputDevice = id;
    unawaited(_store.put(_inputKey, id ?? '').catchError((Object _) {}));
  }

  Future<void> _reopenInput() async {
    _inputOpen = false;
    inputLevel.value = 0;
    try {
      await _engine.stopInput();
    } catch (_) {}
    if (_disposed) return;
    await _ensureInput();
    // quem pediu a entrada pode ter desistido enquanto ela reabria
    if (!_disposed) _releaseInputIfIdle();
  }

  /// Liga/desliga a gravação: com faixas armadas, conta um compasso (se [DawDoc.countIn]) e grava
  /// a partir do cursor; parar gera os clipes (áudio nas de áudio, notas nas de instrumento), num
  /// passo só do desfazer. Tocando, grava dali na hora (sem contagem). Parar na contagem não grava
  /// nada.
  Future<void> toggleRecord() async {
    if (!ready || _recBusy) return;
    if (recording) return _finishRecording();
    return _startRecording();
  }

  Future<void> _startRecording() async {
    final audioIds = {
      for (final t in doc.tracks)
        if (t.armed && t.kind == TrackKind.audio) t.id,
    };
    final midiIds = {
      for (final t in doc.tracks)
        if (t.armed && t.kind.isInstrument) t.id,
    };
    if (audioIds.isEmpty && midiIds.isEmpty) {
      error = 'Arme uma faixa para gravar (o botão de gravação dela): a de áudio grava a entrada; a de instrumento, as notas tocadas.';
      notifyListeners();
      return;
    }
    _recBusy = true;
    try {
      // o clique no gravar é o gesto que destrava o áudio
      _wake();
      var audio = false;
      if (audioIds.isNotEmpty) {
        audio = await _ensureInput();
        if (_disposed) return;
        // sem entrada e sem instrumento armado não há o que gravar (o motivo já está em error)
        if (!audio && midiIds.isEmpty) return;
      }
      _hookCapture();
      _beginRecording(audioIds: audio ? audioIds : const {}, midiIds: midiIds, audio: audio);
    } finally {
      _recBusy = false;
    }
  }

  /// Quadros da contagem de [bar] batidas que começa em [from].
  static int _countFrames(TempoMap tempo, double bpm, double rate, double bar, double from) =>
      tempo.isSingle ? (bar * (rate * 60 / bpm)).round() : ((tempo.secondsAt(from + bar) - tempo.secondsAt(math.max(0.0, from))) * rate).round();

  void _beginRecording({required Set<String> audioIds, required Set<String> midiIds, required bool audio}) {
    final d = doc;
    final wasPlaying = playing.value;
    final start = wasPlaying ? _estimatedBeat() : math.max(0.0, beat.value);
    // a contagem tem o tamanho do compasso do cursor (com mapa de compassos, o dele)
    final bar = d.meter.isSingle ? d.beatsPerBar.toDouble() : d.meter.barBeatsAt(start);
    final count = !wasPlaying && d.countIn;
    double? zone;
    var from = start;
    if (count) {
      final before = start - bar;
      // o fim do loop no compasso da contagem: o transporte voltaria ao começo do loop e nunca
      // chegaria ao cursor
      final loopInside = d.loopOn && d.loopEnd > d.loopStart && d.loopEnd > before + 1e-9 && d.loopEnd <= start + 1e-9;
      if (before >= -1e-9 && !loopInside) {
        from = math.max(0.0, before);
      } else {
        // antes do fim do primeiro compasso não há onde contar (o transporte não vai abaixo de
        // zero): a contagem toca numa região vazia bem depois do fim de tudo, e um loop provisório
        // do fim dela até o cursor faz a volta no quadro exato
        zone = math.max(_countZoneBars * bar, ((d.contentEnd / bar).ceil() + 2) * bar);
        from = zone;
      }
    }
    final rate = engineRate;
    // o som sai do motor com a latência dele (PDC, cadeia do master, limitador de segurança) além da do aparelho
    final outLatency = _outputLatency;
    final latency = audio ? outLatency + _inputLatency + d.recLatencyMs / 1000 : 0.0;
    final r = _Recording(
      start: start,
      bpm: d.bpm,
      rate: rate,
      loopOn: d.loopOn && d.loopEnd > d.loopStart,
      loopStart: d.loopStart,
      loopEnd: d.loopEnd,
      trackIds: [for (final t in d.tracks) t.id],
      audioIds: audioIds,
      midiIds: midiIds,
      audio: audio,
      countBeats: count ? bar : 0,
      zone: zone,
      latency: latency.isFinite ? latency : 0,
      midiLatency: outLatency,
      // a contagem e a latência saem do começo do que a entrada mandou (latência negativa, da
      // compensação manual, acrescenta silêncio)
      skip: (count ? _countFrames(d.tempo, d.bpm, rate, bar, zone ?? start - bar) : 0) + (latency.isFinite ? (latency * rate).round() : 0),
      metronomeTemp: count && !d.metronome,
      startFromCapture: wasPlaying,
      tempo: d.tempo,
    );
    _rec = r;
    recording = true;
    countingIn = count;
    _countMetronome = r.metronomeTemp;
    if (zone != null) {
      _loopOverride = (true, start, zone + bar);
      // a automação do master vale para o clique, e lá no fim de tudo ela pode estar num fade que o
      // calaria: fica de fora até meio tempo antes da volta
      _autoSuppressed = true;
    }
    void captureOn() {
      _engine.setCapture(true);
      r.captureOn = true;
    }

    try {
      // parado, a captura liga antes do play: ela só junta com o transporte andando, e assim o
      // primeiro quadro é o do play mesmo que ele caia num bloco de áudio depois dela. Tocando, liga
      // depois do salto (senão levaria um pedaço de antes dele).
      if (!wasPlaying) captureOn();
      _sync();
      // `rec_notes_start` também vai pela captura (a ponte liga as duas juntas); mandar aqui não
      // custa nada e não depende dela. Por último: um motor que não a conheça para depois do play.
      _engine.calls([
        ['seek', from],
        ['play'],
        ['rec_notes_start'],
      ]);
      if (wasPlaying) captureOn();
    } catch (e) {
      // motor sem captura: não finge que grava
      _rec = null;
      recording = false;
      countingIn = false;
      _restoreCountIn();
      _engine.calls([
        ['stop'],
        ['seek', start],
      ]);
      playing.value = false;
      beat.value = start;
      error = e is UnimplementedError ? 'A gravação ainda não funciona neste aparelho.' : 'Não deu para começar a gravação: $e';
      notifyListeners();
      return;
    }
    playing.value = true;
    beat.value = zone != null ? start - bar : from;
    notifyListeners();
  }

  /// Compassos até a região da contagem fora do lugar: longe o bastante para nenhuma gravação
  /// chegar lá, perto o bastante para a posição em quadros ser exata no motor (f64).
  static const _countZoneBars = 1 << 16;

  /// Estado do motor durante a contagem: meio tempo antes do fim, o que ela trocou volta; no fim
  /// (o cursor chegou, ou a contagem fora do lugar deu a volta), a gravação está valendo.
  void _countInState(_Recording r, EngineState s) {
    // estado ainda de antes do play (a caminho quando a gravação começou)
    if (!s.playing) return;
    final zone = r.zone;
    final done = zone != null ? s.beat < zone - 1e-6 : s.beat >= r.start - 1e-6;
    final end = zone != null ? zone + r.countBeats : r.start;
    if (done || s.beat >= end - 0.5) _endPreRoll(r);
    if (!done) return;
    countingIn = false;
    if (zone != null) {
      _loopOverride = null;
      _sync();
    }
    notifyListeners();
  }

  /// Meio tempo antes do primeiro tempo da gravação: o metrônomo provisório cala (não clica no
  /// primeiro tempo) e a automação volta a tempo da volta.
  void _endPreRoll(_Recording r) {
    if (r.preRollDone) return;
    r.preRollDone = true;
    if (!_countMetronome && !_autoSuppressed) return;
    _countMetronome = false;
    _autoSuppressed = false;
    _sync();
  }

  /// Desfaz as trocas da contagem (loop, metrônomo e automação voltam ao documento).
  void _restoreCountIn() {
    if (_loopOverride == null && !_countMetronome && !_autoSuppressed) return;
    _loopOverride = null;
    _countMetronome = false;
    _autoSuppressed = false;
    _sync();
  }

  /// A posição do motor agora: a do último estado mais o que andou desde ele (tocando), com a
  /// volta do loop.
  double _estimatedBeat() {
    final b = beat.value;
    if (!playing.value || !_stateClock.isRunning) return math.max(0.0, b);
    // estados parados de chegar (aba em segundo plano) não viram um salto grande
    final secs = math.min(_stateClock.elapsedMicroseconds / 1e6, 0.25);
    var e = doc.tempo.isSingle ? b + secs * doc.bpm / 60 : doc.beatAtSeconds(doc.secondsAt(b) + secs);
    final ls = doc.loopStart, le = doc.loopEnd;
    if (doc.loopOn && le > ls && b < le && e >= le) e = ls + (e - le) % (le - ls);
    return math.max(0.0, e);
  }

  Future<void> _finishRecording() async {
    final r = _rec;
    if (r == null || !recording || _recBusy) return;
    _recBusy = true;
    final cancel = countingIn;
    r
      ..stopBeat = _estimatedBeat()
      ..elapsed ??= r.clock.elapsed;
    recording = false;
    countingIn = false;
    void stopTransport() {
      _engine.calls([
        ['stop'],
        ..._releaseControls(),
      ]);
      playing.value = false;
      _restoreCountIn();
    }

    try {
      if (cancel) {
        // parou na contagem: nada foi gravado
        stopTransport();
        r.closed = true;
        _captureOff(null);
        _backTo(r.start);
        return;
      }
      status = 'Salvando a gravação…';
      notifyListeners();
      // a entrada chega atrasada: o transporte (e a captura, que só junta com ele andando) segue o
      // tanto da latência, para o arquivo ter o que se tocou até o stop
      if (r.audio && r.latency > 0) {
        // o pedal, o bend e a roda voltam ao repouso já: o parar foi pedido, e sem isso o que se
        // tocar ao vivo nesses ms seguiria valendo (o transporte ainda anda até a espera acabar)
        _engine.calls(_releaseControls());
        await Future<void>.delayed(Duration(milliseconds: (r.latency * 1000).ceil() + 20));
      }
      // a tela fechou no meio: o dispose já parou tudo
      if (_disposed) return;
      stopTransport();
      final wait = Completer<List<RecordedNote>>();
      _captureOff(wait);
      // as notas vêm depois do último bloco da entrada (a mesma porta, em ordem): chegaram, o
      // áudio está inteiro
      List<RecordedNote>? notes;
      try {
        notes = await wait.future.timeout(Duration(milliseconds: r.midiIds.isEmpty ? 400 : 2000));
      } on TimeoutException {
        notes = null;
      }
      r.closed = true;
      if (_disposed) return;
      _backTo(r.start);
      await _commitRecording(r, notes);
    } finally {
      if (identical(_rec, r)) _rec = null;
      _recBusy = false;
      status = null;
      if (!_disposed) {
        if (_closeInputAfterRecording) {
          _closeInputForLeave();
        } else {
          _releaseInputIfIdle();
        }
        notifyListeners();
      }
    }
  }

  /// O cursor volta ao começo da gravação (para ouvir o que entrou), e a janela vai junto se ele
  /// ficou fora dela.
  void _backTo(double b) {
    _engine.calls([
      ['seek', b],
    ]);
    beat.value = b;
    if (b < scrollBeat || b > scrollBeat + viewWidth / pxPerBeat) scrollBeat = math.max(0, b - 2);
  }

  /// Desliga a captura no motor; [wait] recebe as notas que ele manda de volta.
  void _captureOff(Completer<List<RecordedNote>>? wait) {
    final r = _rec;
    if (r == null || !r.captureOn) {
      wait?.complete(const []);
      return;
    }
    r.captureOn = false;
    _notesWaiting.add(wait);
    try {
      _engine.setCapture(false);
    } catch (_) {
      _notesWaiting.removeLast();
      if (wait != null && !wait.isCompleted) wait.complete(const []);
    }
  }

  void _onCaptureEnd(List<RecordedNote> data) {
    if (_notesWaiting.isEmpty) return;
    final c = _notesWaiting.removeFirst();
    if (c != null && !c.isCompleted) c.complete(data);
  }

  void _onRecordBlock(Float32List left, Float32List right) {
    final r = _rec;
    if (r == null || r.closed) return;
    // entrada mono que venha sem o lado direito: os dois lados iguais
    final rr = right.isEmpty ? left : right;
    final n = math.min(left.length, rr.length);
    if (n == 0) return;
    if (r.frames == 0 && r.startFromCapture) {
      // gravando com o transporte andando: o primeiro quadro capturado diz onde a gravação começou
      // de verdade (a posição da tela no clique chegava até um bloco de áudio atrasada)
      final b = _engine.recordBeat;
      if (b.isFinite && (b - r.start).abs() < 1) r.start = r.stopBeat = b;
      r.startFromCapture = false;
    }
    r.left.add(n == left.length ? left : Float32List.sublistView(left, 0, n));
    r.right.add(n == rr.length ? rr : Float32List.sublistView(rr, 0, n));
    r.frames += n;
  }

  /// Nos testes: quanto tempo a gravação atual durou (em vez do relógio).
  @visibleForTesting
  void debugRecordingElapsed(Duration d) => _rec?.elapsed = d;

  /// Os clipes da gravação: o áudio vira sample (sha-256 do WAV 32f, guardado e registrado como no
  /// importar) nas faixas de áudio armadas; as notas, clipe MIDI nas de instrumento. Um passo só
  /// do desfazer.
  Future<void> _commitRecording(_Recording r, List<RecordedNote>? notesData) async {
    final plans = r.audio ? _planAudio(r) : const <_ClipPlan>[];
    final name = _nextRecordingName();
    final hashes = <List<String>>[];
    final infos = <String, SampleInfo>{};
    for (var p = 0; p < plans.length; p++) {
      final plan = plans[p];
      final list = <String>[];
      for (var k = 0; k < plan.pieces.length; k++) {
        final piece = plan.pieces[k];
        final len = piece.pad + piece.to - piece.from;
        final l = Float32List(len), rr = Float32List(len);
        gatherFrames(r.left, piece.from + r.skip, piece.to + r.skip, l, piece.pad);
        gatherFrames(r.right, piece.from + r.skip, piece.to + r.skip, rr, piece.pad);
        final channels = _inputChannels(l, rr);
        final bytes = encodeWav(channels, r.rate.round(), ExportFormat.wav32f);
        final hash = await _engine.sha256Hex(bytes);
        if (!waveforms.containsKey(hash)) {
          await _store.put('sample:$hash', bytes);
          if (_disposed) return;
          _register(hash, DecodedAudio(channels, r.rate));
        }
        final label = plan.pieces.length > 1 ? '$name - tomada ${k + 1}' : name;
        // o mesmo áudio já no projeto (gravação idêntica, silêncio) fica com o nome que tinha
        infos[hash] = doc.samples[hash] ?? SampleInfo('$label.wav', len / r.rate);
        list.add(hash);
      }
      hashes.add(list);
    }
    final (notes, wrapped) = _recordedNotes(r, notesData);
    final ccs = _recordedControls(r, notesData, wrapped);
    if (plans.isEmpty && notes.isEmpty && ccs.isEmpty) {
      if (r.audio && r.frames == 0) {
        error = 'A entrada não mandou áudio durante a gravação: confira o microfone e a entrada escolhida.';
      } else if (!r.audio && r.midiIds.isNotEmpty) {
        error = 'Nenhuma nota foi tocada na faixa armada durante a gravação.';
      }
      return;
    }
    checkpoint();
    mutate((d) {
      d.samples.addAll(infos);
      for (final id in r.audioIds) {
        final t = d.tracks.where((t) => t.id == id && t.kind == TrackKind.audio).firstOrNull;
        if (t == null) continue;
        for (var p = 0; p < plans.length; p++) {
          final takes = hashes[p];
          final clip = AudioClip(
            id: newId(),
            sample: takes[plans[p].active],
            start: plans[p].start,
            length: plans[p].seconds,
            takes: takes.length > 1 ? List.of(takes) : null,
          );
          t.clips.add(clip);
          // gravar por cima substitui o que estava embaixo, como nos DAWs
          placeOnTop(clip.id);
        }
      }
      for (final id in {...notes.keys, ...ccs.keys}) {
        final t = d.tracks.where((t) => t.id == id && t.kind.isInstrument).firstOrNull;
        if (t != null) _placeRecordedNotes(t, notes[id] ?? const [], r, wrapped, ccs[id] ?? const []);
      }
    });
  }

  /// Onde cada pedaço de áudio da gravação vai. Sem volta de loop, um clipe do cursor até onde
  /// parou. Com voltas, cada passada é uma tomada de um clipe que cobre o loop (a ativa é a
  /// última); a primeira começa no cursor (silêncio antes, se ele estava no meio do loop) e o que
  /// veio antes do loop, se começou antes dele, fica num clipe comum.
  static List<_ClipPlan> _planAudio(_Recording r) {
    final frames = r.frames - r.skip;
    // menos de 50 ms depois da latência: um toque no gravar e parar, não uma gravação
    if (frames < r.rate * 0.05) return const [];
    final fpb = r.rate * 60 / r.bpm;
    final passes = recordingPasses(
      start: r.start,
      frames: frames,
      bpm: r.bpm,
      rate: r.rate,
      loopOn: r.loopOn,
      loopStart: r.loopStart,
      loopEnd: r.loopEnd,
      tempo: r.tempo,
    );
    int endOf(int p) => p + 1 < passes.length ? passes[p + 1].frame : frames;
    var kept = passes.length;
    // a última passada com menos de uma batida é o passo além da volta de quem parou
    if (kept > 1 && frames - passes.last.frame < fpb) kept--;
    if (kept == 1) {
      final end = endOf(0);
      return [
        (start: r.start, seconds: end / r.rate, pieces: [(from: 0, to: end, pad: 0)], active: 0),
      ];
    }
    final plans = <_ClipPlan>[];
    final _Piece first;
    if (r.start < r.loopStart) {
      final head = r.framesBetween(r.start, r.loopStart).round();
      plans.add((start: r.start, seconds: head / r.rate, pieces: [(from: 0, to: head, pad: 0)], active: 0));
      first = (from: head, to: endOf(0), pad: 0);
    } else {
      first = (from: 0, to: endOf(0), pad: r.framesBetween(r.loopStart, r.start).round());
    }
    final pieces = [first, for (var p = 1; p < kept; p++) (from: passes[p].frame, to: endOf(p), pad: 0)];
    // toca a última passada completa: a de quem parou no meio (ou a primeira, que começou no meio
    // do loop) fica guardada como tomada, mas não é a que se quer ouvir de primeira
    final loopFrames = r.framesBetween(r.loopStart, r.loopEnd);
    bool complete(_Piece x) => x.pad == 0 && x.to - x.from >= loopFrames * 0.98;
    var active = pieces.length - 1;
    while (active > 0 && !complete(pieces[active])) {
      active--;
    }
    if (!complete(pieces[active])) active = pieces.length - 1;
    plans.add((
      start: r.loopStart,
      seconds: r.tempo.isSingle ? (r.loopEnd - r.loopStart) * 60 / r.bpm : r.tempo.secondsAt(r.loopEnd) - r.tempo.secondsAt(r.loopStart),
      pieces: pieces,
      active: active,
    ));
    return plans;
  }

  /// A entrada vira um canal só quando é mono de fato: os dois lados iguais (o navegador duplica o
  /// microfone mono) ou um deles em silêncio absoluto (microfone numa entrada de uma interface
  /// estéreo, que soaria só de um lado).
  static List<Float32List> _inputChannels(Float32List l, Float32List r) {
    var same = true, lSilent = true, rSilent = true;
    for (var i = 0; i < l.length; i++) {
      final a = l[i], b = r[i];
      if (a != b) same = false;
      if (a != 0) lSilent = false;
      if (b != 0) rSilent = false;
      if (!same && !lSilent && !rSilent) return [l, r];
    }
    return same || rSilent ? [l] : [r];
  }

  /// "Gravação N" com o próximo N dos samples do projeto.
  String _nextRecordingName() {
    var n = 0;
    final re = RegExp(r'^Gravação (\d+)');
    for (final s in doc.samples.values) {
      final m = re.firstMatch(s.name);
      if (m != null) n = math.max(n, int.parse(m.group(1)!));
    }
    return 'Gravação ${n + 1}';
  }

  /// As notas gravadas por faixa armada, em batidas absolutas, e se a gravação deu a volta no loop.
  ///
  /// O motor manda as notas com a posição do transporte. O que se tocou na contagem fica de fora,
  /// menos a nota adiantada (até um quarto de tempo antes do primeiro, que entra nele) e a que
  /// ainda soava no primeiro tempo (começa nele). A nota segurada na volta do loop vira duas: até
  /// o fim dele e do começo até a soltura.
  (Map<String, List<_RecNote>>, bool) _recordedNotes(_Recording r, List<RecordedNote>? data) {
    final out = <String, List<_RecNote>>{};
    final ls = r.loopStart, le = r.loopEnd;
    final raw = <(int, int, double, double, double)>[
      for (final n in data ?? const <RecordedNote>[])
        if (n.start.isFinite && n.end.isFinite && n.pitch < ccPitchBase) (n.track, n.pitch, n.start, n.end, n.velocity),
    ];
    final zone = r.zone;
    // o motor parte a nota segurada num salto do transporte: ela termina no ponto do salto e
    // recomeça do outro lado. A volta da contagem fora do lugar (do fim dela ao cursor) não é
    // passada nenhuma: ali a nota segurada volta a ser uma só
    if (zone != null) _joinAcross(raw, zone + r.countBeats, r.start);
    // a volta do loop na contagem fora do lugar é a da contagem, não uma passada. A nota segurada
    // na volta do loop chega partida nele (de um motor que não parte, com o fim antes do começo)
    final heldAcross =
        raw.any((n) => n.$4 < n.$3 - 1e-9 && (zone == null || n.$3 < zone - 1e-9)) ||
        (r.loopOn && raw.any((a) => _nearBeat(a.$4, le) && raw.any((b) => b.$1 == a.$1 && b.$2 == a.$2 && _nearBeat(b.$3, ls))));
    final wrapped = r.loopOn && r.start < le && (r.recordedBeats >= le - r.start || heldAcross);
    if (r.midiIds.isEmpty) return (out, wrapped);
    const early = 0.25, minLength = 1 / 64;
    // o músico toca ouvindo o som com a latência do motor e do aparelho: as notas voltam para antes
    // dela (sem passar do começo da gravação nem do loop)
    final floor = math.min(r.start, r.loopOn ? ls : r.start);
    void add(String id, int pitch, double s, double e, double v) {
      if (r.midiLatency > 0) {
        s = math.max(r.shiftBeat(s), math.min(s, floor));
        e = math.max(r.shiftBeat(e), s);
      }
      if (e - s < minLength) e = s + minLength;
      out.putIfAbsent(id, () => []).add((pitch: pitch, start: math.max(0.0, s), end: e, velocity: v.isFinite ? v.clamp(0.0, 1.0).toDouble() : 0.8));
    }

    for (final (ti, pitch, s0, e0, v) in raw) {
      // velocidade zero é soltura no MIDI: não é nota
      if (ti < 0 || ti >= r.trackIds.length || pitch < 0 || pitch > 127 || !(v > 0)) continue;
      final id = r.trackIds[ti];
      if (!r.midiIds.contains(id)) continue;
      var s = s0, e = e0;
      var counted = false;
      if (zone != null) {
        // tocada na contagem, lá longe: vem para antes do cursor
        if (s >= zone - 1e-9) {
          s = s - (zone + r.countBeats) + r.start;
          counted = true;
        }
        if (e >= zone - 1e-9) e = e - (zone + r.countBeats) + r.start;
      } else if (r.countBeats > 0 && s < r.start - 1e-9 && !(wrapped && s >= ls - 1e-9)) {
        counted = true;
      }
      if (!counted && wrapped && e < s - 1e-9) {
        add(id, pitch, s, le, v);
        if (e > ls + minLength) add(id, pitch, ls, e, v);
        continue;
      }
      if (counted) {
        if (s >= r.start - early) {
          final len = e - s;
          s = r.start;
          e = s + len;
        } else if (e > r.start + minLength) {
          s = r.start;
        } else {
          continue;
        }
      }
      add(id, pitch, s, e, v);
    }
    return (out, wrapped);
  }

  /// Os eventos de controle (bend, modulação, pedal) que o motor registrou junto das notas, por id
  /// de faixa, em batidas absolutas. O que se tocou na contagem fica de fora. Com loop, só vale a
  /// última passada (as passadas anteriores cobriam as mesmas batidas com outra curva, e as
  /// curvas intercaladas dariam um tremor); as notas de todas as passadas continuam entrando.
  Map<String, List<_RecCc>> _recordedControls(_Recording r, List<RecordedNote>? data, bool wrapped) {
    final out = <String, List<_RecCc>>{};
    if (r.midiIds.isEmpty) return out;
    final byTrack = <int, List<_RecCc>>{};
    // como nas notas: o recuo da latência não passa do começo da gravação (nem do loop), senão um
    // CC tocado nos primeiros ms cairia antes do início e o filtro da contagem, adiante, o jogaria fora
    final floor = math.min(r.start, r.loopOn ? r.loopStart : r.start);
    for (final n in data ?? const <RecordedNote>[]) {
      if (n.pitch < ccPitchBase || !n.start.isFinite || !n.velocity.isFinite) continue;
      final cc = n.pitch - ccPitchBase;
      if (!ccKinds.contains(cc)) continue;
      final beat = r.midiLatency > 0 ? math.max(r.shiftBeat(n.start), math.min(n.start, floor)) : n.start;
      byTrack.putIfAbsent(n.track, () => []).add((cc: cc, beat: beat, value: MidiCc.clampValue(cc, n.velocity)));
    }
    final zone = r.zone, ls = r.loopStart;
    for (final e in byTrack.entries) {
      if (e.key < 0 || e.key >= r.trackIds.length) continue;
      final id = r.trackIds[e.key];
      if (!r.midiIds.contains(id)) continue;
      // a bateria ignora bend, modulação e pedal: gravar pontos nela seria só lixo no clipe
      if (doc.tracks.where((t) => t.id == id).firstOrNull?.kind == TrackKind.drums) continue;
      var list = e.value;
      if (wrapped) {
        // a batida volta para trás na volta do loop: a última passada começa no último recuo
        var from = 0;
        for (var i = 1; i < list.length; i++) {
          if (list[i].beat < list[i - 1].beat - 1e-9) from = i;
        }
        list = list.sublist(from);
      }
      for (final ev in list) {
        if (zone != null) {
          if (ev.beat >= zone - 1e-9) continue;
        } else if (r.countBeats > 0 && ev.beat < r.start - 1e-9 && !(wrapped && ev.beat >= ls - 1e-9)) {
          continue;
        }
        out.putIfAbsent(id, () => []).add((cc: ev.cc, beat: math.max(0.0, ev.beat), value: ev.value));
      }
    }
    return out;
  }

  /// Junta os controles gravados ([ccs], batidas absolutas) ao [clip], que começa em [origin]:
  /// afina o que veio em rajada, solta o pedal que ficou embaixo no fim da gravação e, por
  /// controle, o que foi tocado substitui o que o clipe já tinha no trecho da passada.
  void _mergeControls(MidiClip clip, List<_RecCc> ccs, double origin, double stopBeat) {
    if (ccs.isEmpty) return;
    final rel = [for (final e in ccs) MidiCc(cc: e.cc, beat: e.beat - origin, value: e.value)];
    final last = rel.map((e) => e.beat).reduce(math.max);
    // o pedal ainda embaixo quando a gravação parou sobe ali (nunca antes de uma pausa mínima: um
    // pedal de duração zero não segura nada)
    final fresh = thinControls(closeControls(rel, math.max(last + 1 / 16, stopBeat - origin)));
    for (final cc in ccKinds) {
      final mine = fresh.where((e) => e.cc == cc).toList();
      if (mine.isEmpty) continue;
      final lo = mine.map((e) => e.beat).reduce(math.min), hi = mine.map((e) => e.beat).reduce(math.max);
      clip.controls.removeWhere((e) => e.cc == cc && e.beat >= lo - 1e-9 && e.beat <= hi + 1e-9);
      clip.controls.addAll(mine);
    }
    clip.controls.sort((a, b) => a.beat.compareTo(b.beat));
  }

  /// A mesma batida, com a folga do float de 32 bits em que as notas chegam do motor (lá na região
  /// da contagem fora do lugar, centenas de milhares de batidas adiante, um passo dele é 1/32).
  static bool _nearBeat(double a, double b) => (a - b).abs() <= 1e-4 + b.abs() * 2.4e-7;

  /// Junta de volta as notas que o motor partiu num salto de [cut] para [restart]: a que termina
  /// em [cut] com a da mesma faixa e altura que começa em [restart].
  static void _joinAcross(List<(int, int, double, double, double)> raw, double cut, double restart) {
    for (var i = 0; i < raw.length; i++) {
      final a = raw[i];
      if (!_nearBeat(a.$4, cut)) continue;
      final j = raw.indexWhere((b) => b.$1 == a.$1 && b.$2 == a.$2 && _nearBeat(b.$3, restart));
      if (j < 0) continue;
      raw[i] = (a.$1, a.$2, a.$3, raw[j].$4, a.$5);
      raw.removeAt(j);
      if (j < i) i--;
    }
  }

  /// As notas gravadas numa faixa de instrumento: vão para o clipe que já estava sob o cursor
  /// (overdub, esticando o clipe em compassos inteiros se passarem dele) ou para um clipe novo que
  /// cobre os compassos gravados.
  void _placeRecordedNotes(DawTrack t, List<_RecNote> notes, _Recording r, bool wrapped, [List<_RecCc> ccs = const []]) {
    // os compassos são os do mapa de compassos (6/8, 7/8, mudanças no meio)
    final meter = doc.meter;
    double floorBar(double b) => math.max(0.0, meter.floorBarStart(math.max(0.0, b)));
    double ceilBar(double b) => meter.ceilBarStart(math.max(0.0, b));
    // só controles, sem nota nenhuma (overdub do pedal ou do bend): entram no clipe que estava sob o
    // cursor, ou criam um clipe vazio que cobre o que foi gravado, como a gravação de notas faz
    final starts = [...notes.map((n) => n.start), ...ccs.map((e) => e.beat)];
    final ends = [...notes.map((n) => n.end), ...ccs.map((e) => e.beat)];
    if (starts.isEmpty) return;
    final minStart = starts.reduce(math.min);
    final maxEnd = ends.reduce(math.max);
    MidiNote rel(_RecNote n, double origin) => MidiNote(pitch: n.pitch, start: n.start - origin, length: n.end - n.start, velocity: n.velocity);
    final target = t.midi.where((c) => c.start <= r.start + 1e-9 && c.end > r.start + 1e-9).firstOrNull;
    if (target != null) {
      var start = target.start, end = target.end;
      if (minStart < start - 1e-9) start = floorBar(minStart);
      if (maxEnd > end + 1e-9) end = ceilBar(maxEnd);
      final grew = start != target.start || end != target.end;
      if (start != target.start) {
        final shift = target.start - start;
        for (final n in target.notes) {
          n.start += shift;
        }
        shiftControls(target.controls, shift);
        target.start = start;
      }
      target
        ..length = end - start
        ..notes.addAll([for (final n in notes) rel(n, start)]);
      _mergeControls(target, ccs, start, r.stopBeat);
      if (grew) placeOnTop(target.id);
      return;
    }
    final from = wrapped ? math.min(r.start, r.loopStart) : r.start;
    final to = wrapped ? r.loopEnd : math.max(r.stopBeat, maxEnd);
    final start = floorBar(math.min(from, minStart));
    final end = math.max(ceilBar(math.max(to, maxEnd)), start + meter.barBeatsAt(start));
    final clip = MidiClip(id: newId(), name: t.name, start: start, length: end - start, notes: [for (final n in notes) rel(n, start)]);
    _mergeControls(clip, ccs, start, r.stopBeat);
    t.midi.add(clip);
    placeOnTop(clip.id);
  }

  /// Troca a tomada ativa de um clipe gravado em loop (desfazível).
  void switchTake(String clipId, String sampleHash) {
    final f = _findClip(clipId);
    if (f == null) return;
    final clip = f.$2;
    if (clip.sample == sampleHash || !clip.takes.contains(sampleHash)) return;
    edit((_) => clip.sample = sampleHash);
  }

  /// Não deixa [what] no meio de uma gravação (avisa em [error]).
  bool _blockedByRecording(String what) {
    if (!recording) return false;
    error = 'Pare a gravação para $what.';
    notifyListeners();
    return true;
  }

  /// Gravando ou renderizando, outro render espera (avisa em [error]).
  bool _busyFor(String what) {
    final why = recording || _recBusy
        ? 'Pare a gravação antes de $what.'
        : _rendering
        ? 'Espere o render em andamento terminar antes de $what.'
        : null;
    if (why == null) return false;
    error = why;
    notifyListeners();
    return true;
  }

  /// Memória de áudio (float) por render: projeto longo com muitos stems vai em vários renders,
  /// cada um com as saídas que cabem, em vez de todas de uma vez.
  static const _renderBudget = 384 * 1024 * 1024;

  /// Renderiza fora de tempo real (mais rápido que tocando) e salva os arquivos: a mixagem
  /// (`<projeto>.wav`, pós-limitador) e, com stems, uma por faixa (`<projeto> - <faixa>.wav`,
  /// pós-fader; as que não soam nada no trecho ficam de fora). Normalizar leva o pico de cada
  /// arquivo a −1 dBFS. Falha ou aviso ficam em [error].
  ///
  /// [sink] recebe cada WAV renderizado (nome com `.wav`) no lugar do salvamento direto: é por onde o FLAC e o MP3
  /// passam pelo servidor (`export_compressed.dart`). Sem ele, o arquivo é salvo como WAV.
  Future<void> exportAudio(ExportOptions options, {void Function(double progress)? onProgress, Future<void> Function(String name, Uint8List wav)? sink}) async {
    if (!ready || _busyFor('exportar')) return;
    final d = doc;
    final loop = options.range == ExportRange.loop;
    final from = loop ? d.loopStart : 0.0;
    final to = loop ? d.loopEnd : d.contentEnd;
    if (!(to > from + 1e-9)) {
      error = loop ? 'A região do loop está vazia: marque o loop antes de exportar.' : 'O projeto está vazio: não há nada para exportar.';
      notifyListeners();
      return;
    }
    final rate = (options.sampleRate ?? engineRate).toDouble();
    final tail = options.tail.isFinite ? options.tail.clamp(0.0, 60.0).toDouble() : 0.0;
    final outputs = [
      -1,
      if (options.stems)
        for (var i = 0; i < d.tracks.length; i++) i,
    ];
    final base = _fileName(project.name, 'jopendaw');
    final names = <int, String>{-1: '$base.wav'};
    final taken = {'$base.wav'.toLowerCase()};
    for (final i in outputs.skip(1)) {
      final stem = _fileName(d.tracks[i].name, 'Faixa ${i + 1}');
      var name = '$base - $stem.wav';
      for (var k = 2; taken.contains(name.toLowerCase()); k++) {
        name = '$base - $stem ($k).wav';
      }
      taken.add(name.toLowerCase());
      names[i] = name;
    }
    await _settleWarp();
    if (_disposed) return;
    final used = _usedHashes();
    final lost = used.where((h) => !_sampleIds.containsKey(h)).length;
    final calls = _fullSyncCalls();
    final samples = _samplesFor(used);
    _rendering = true;
    _exportCanceled = false;
    exportReport = null;
    status = 'Exportando…';
    notifyListeners();
    // ganho da mixagem em dB, para os stems quando pedirem o mesmo (a mixagem é a primeira saída)
    double? mixGainDb;
    try {
      final perOutput = ((d.secondsAt(to) - d.secondsAt(from)) + tail) * rate * 2 * 4;
      final size = math.max(1, (_renderBudget / perOutput).floor());
      final batches = [for (var i = 0; i < outputs.length; i += size) outputs.sublist(i, math.min(outputs.length, i + size))];
      for (var b = 0; b < batches.length; b++) {
        final batch = batches[b];
        final result = await _engine.renderOffline(
          calls: calls,
          samples: samples,
          fromBeat: from,
          toBeat: to,
          tailSeconds: tail,
          outputs: batch,
          rate: rate,
          onProgress: onProgress == null ? null : (p) => onProgress(((b + (p.isFinite ? p.clamp(0.0, 1.0) : 0.0)) / batches.length) * 0.95),
        );
        if (_disposed) return;
        for (var k = 0; k < batch.length && k < result.length; k++) {
          final channels = result[k];
          if (channels.isEmpty) continue;
          final peak = _peak(channels);
          // stem que não soa (vazia, muda, calada pelo solo): um arquivo de silêncio não serve
          if (batch[k] >= 0 && peak == 0) continue;
          final target = options.targetLufs;
          if (target != null) {
            if (batch[k] == -1) {
              final r = await normalizeLoudness(
                channels,
                rate,
                targetLufs: target.clamp(kMinTargetLufs, kMaxTargetLufs).toDouble(),
                ceilingDb: options.ceilingDbtp.clamp(kMinCeiling, kMaxCeiling).toDouble(),
                onProgress: onProgress == null ? null : (p) => onProgress(0.95 + 0.04 * p),
                isCanceled: () => _exportCanceled || _disposed,
              );
              if (_exportCanceled) throw const RenderCanceled();
              exportReport = r.report;
              if (!r.report.unmeasurable) mixGainDb = r.gainDb;
            } else if (options.normalizeStems && mixGainDb != null && mixGainDb != 0) {
              scaleChannels(channels, dbToGain(mixGainDb));
            }
          } else if (options.normalize && peak > 0) {
            _scale(channels, dbToGain(-1) / peak);
          }
          final bytes = encodeWav(channels, rate.round(), options.renderFormat);
          if (sink != null) {
            await sink(names[batch[k]]!, bytes);
          } else {
            await _engine.saveFile(names[batch[k]]!, bytes, 'audio/wav');
          }
          if (_disposed) return;
        }
      }
      onProgress?.call(1);
      if (lost > 0) error = 'Exportado sem ${lost == 1 ? 'um áudio que não está' : '$lost áudios que não estão'} neste aparelho.';
    } on RenderCanceled {
      // quem cancelou já sabe: não é falha
    } catch (e) {
      if (!_disposed) error = 'A exportação não terminou: ${_renderError(e)}';
    } finally {
      _rendering = false;
      status = null;
      if (!_disposed) notifyListeners();
    }
  }

  /// Salva um arquivo exportado pelo mesmo caminho dos WAV (seletor do aparelho, downloads no navegador).
  Future<bool> saveExportedFile(String name, Uint8List bytes, String mime) => _engine.saveFile(name, bytes, mime);

  /// Interrompe o render em andamento (exportação ou congelamento): ele termina sem salvar nada e
  /// sem aviso.
  void cancelRender() {
    if (_rendering) {
      _exportCanceled = true;
      _engine.cancelRender();
    }
  }

  bool _exportCanceled = false;

  /// Cauda do congelamento (s): o que soar depois dela está abaixo de −100 dB e é aparado.
  static const _bounceTail = 8.0;

  /// Congela a faixa em áudio: renderiza ela (instrumento, clipes, efeitos e a automação deles)
  /// do começo ao fim do conteúdo dela, mais a cauda, numa faixa de áudio nova logo abaixo, e muda
  /// a original. Um passo só do desfazer.
  ///
  /// O render pega a saída da faixa depois dos inserts com o fader em 0 dB e o pan no centro (sem
  /// a automação deles, sem mudo e sem solo em nenhuma faixa): volume, pan, a automação deles, a
  /// saída e os envios passam para a faixa nova, que soa na mixagem como a original soava e segue
  /// com o fader mexível. Os envios pré-fader saem da original (eles seguiriam soando com ela
  /// muda, e dobrariam); os pós-fader ficam nela também (calam com o mudo). O sidechain que a
  /// original alimenta continua (a chave é pós-inserts, antes do mudo).
  Future<void> bounceTrack(int track, {void Function(double progress)? onProgress}) async {
    if (!ready || track < 0 || track >= doc.tracks.length || _busyFor('congelar')) return;
    final src = doc.tracks[track];
    final id = src.id, label = src.name;
    final (from, to) = _bounceRange(src);
    if (!(to > from + 1e-9)) {
      error = 'A faixa "$label" está vazia: nada para congelar.';
      notifyListeners();
      return;
    }
    final rate = engineRate;
    await _settleWarp();
    if (_disposed) return;
    final calls = _callsFor(_bounceDoc(track));
    final samples = _samplesFor(_usedHashes());
    _rendering = true;
    status = 'Congelando $label…';
    notifyListeners();
    try {
      final result = await _engine.renderOffline(
        calls: calls,
        samples: samples,
        fromBeat: from,
        toBeat: to,
        tailSeconds: _bounceTail,
        outputs: [track],
        rate: rate,
        onProgress: onProgress == null ? null : (p) => onProgress((p.isFinite ? p.clamp(0.0, 1.0) : 0.0) * 0.95),
      );
      if (_disposed) return;
      var channels = result.isEmpty ? const <Float32List>[] : result.first;
      if (channels.isEmpty || _peak(channels) == 0) {
        error = 'A faixa "$label" não soou nada: nada para congelar.';
        return;
      }
      channels = _trimTail(channels, ((doc.secondsAt(to) - doc.secondsAt(from)) * rate).ceil());
      if (channels.length == 2 && _same(channels[0], channels[1])) channels = [channels[0]];
      final bytes = encodeWav(channels, rate.round(), ExportFormat.wav32f);
      final hash = await _engine.sha256Hex(bytes);
      if (!waveforms.containsKey(hash)) {
        await _store.put('sample:$hash', bytes);
        if (_disposed) return;
        _register(hash, DecodedAudio(channels, rate));
      }
      final i = doc.tracks.indexWhere((t) => t.id == id);
      if (i < 0) {
        error = 'A faixa "$label" foi apagada enquanto congelava.';
        return;
      }
      final seconds = channels.first.length / rate;
      checkpoint();
      mutate((d) {
        final src = d.tracks[i];
        const moves = {AutoKind.volume, AutoKind.pan, AutoKind.send};
        final frozen = DawTrack(
          id: newId(),
          name: '${src.name} (áudio)',
          color: src.color,
          gain: src.gain,
          pan: src.pan,
          // já muda, a original não soava: a congelada também não
          mute: src.mute,
          solo: src.solo,
          output: src.output,
          // logo abaixo da original: numa pasta, a cópia entra nela (o bloco segue contíguo); o
          // "recolhida" é da pasta, não da faixa
          groupId: src.groupId,
          sends: [for (final s in src.sends) Send(target: s.target, level: s.level, pre: s.pre)],
          lanes: [
            for (final l in src.lanes)
              if (moves.contains(l.target.kind))
                AutoLane(
                  id: newId(),
                  target: l.target,
                  open: l.open,
                  points: [for (final p in l.points) AutoPoint(beat: p.beat, value: p.value, curve: p.curve)],
                ),
          ],
          clips: [AudioClip(id: newId(), sample: hash, start: from, length: seconds)],
          // a modulação de volume, pan e envios vai junto (a do instrumento e dos efeitos já está no áudio)
          modulation: TrackModulation([
            for (final m in src.modulation.sources)
              if (m.dests.any((x) => moves.contains(x.target.kind))) m.copy(id: newId())..dests.removeWhere((x) => !moves.contains(x.target.kind)),
          ]),
        );
        d.samples[hash] = SampleInfo('${src.name} (congelada).wav', seconds);
        final pre = {
          for (final s in src.sends)
            if (s.pre) s.target,
        };
        src
          ..mute = true
          ..sends.removeWhere((s) => s.pre)
          ..lanes.removeWhere((l) => l.target.kind == AutoKind.send && pre.contains(l.target.ref));
        d.tracks.insert(i + 1, frozen);
        // as faixas depois da nova desceram uma posição: sidechains acompanham
        _remapSidechains((old) => old > i ? old + 1 : old);
        _select(i + 1);
        selectedClip = frozen.clips.first.id;
      });
      onProgress?.call(1);
    } on RenderCanceled {
      // quem cancelou já sabe: não é falha
    } catch (e) {
      if (!_disposed) error = 'O congelamento não terminou: ${_renderError(e)}';
    } finally {
      _rendering = false;
      status = null;
      if (!_disposed) notifyListeners();
    }
  }

  /// De onde até onde a faixa tem conteúdo (batidas). Barramento soa o que recebe: a música toda.
  (double, double) _bounceRange(DawTrack t) {
    if (t.kind == TrackKind.bus) return (0.0, doc.contentEnd);
    var from = double.infinity, to = 0.0;
    if (t.kind == TrackKind.audio) {
      for (final c in t.clips) {
        from = math.min(from, c.start);
        to = math.max(to, doc.clipEnd(c));
      }
    } else {
      for (final c in t.midi) {
        from = math.min(from, c.start);
        to = math.max(to, c.end);
      }
    }
    return from.isFinite ? (math.max(0.0, from), to) : (0.0, 0.0);
  }

  /// O documento que o congelamento renderiza: a faixa com fader em 0 dB, pan no centro, sem mudo
  /// e sem a automação de volume e pan; nenhuma faixa em solo (o solo de outra calaria esta).
  DawDoc _bounceDoc(int track) {
    final copy = DawDoc.fromJson(jsonDecode(jsonEncode(doc.toJson())));
    for (final t in copy.tracks) {
      t.solo = false;
    }
    copy.tracks[track]
      ..gain = 1
      ..pan = 0
      ..mute = false
      ..lanes.removeWhere((l) => l.target.kind == AutoKind.volume || l.target.kind == AutoKind.pan);
    // a modulação de volume e pan também fica fora do áudio (a faixa congelada a leva)
    copy.tracks[track].modulation.prune((t) => t.kind != AutoKind.volume && t.kind != AutoKind.pan);
    return copy;
  }

  /// As chamadas completas de outro documento. As funções que resolvem roteamento e automação
  /// leem [doc]: ele é trocado só durante a montagem, que é síncrona.
  List<List<Object>> _callsFor(DawDoc other) {
    final live = doc;
    doc = other;
    try {
      return _fullSyncCalls();
    } finally {
      doc = live;
    }
  }

  /// Os áudios que o documento toca (clipes das faixas de áudio e o áudio dos samplers).
  Set<String> _usedHashes() => {
    for (final t in doc.tracks) ...[
      if (t.kind == TrackKind.audio)
        for (final c in t.clips) c.sample,
      if (t.kind == TrackKind.sampler && t.sample != null) t.sample!,
      if (t.kind == TrackKind.sampler)
        for (final z in t.zones) z.sample,
    ],
  };

  /// Os áudios decodificados pelo id do motor, para o render fora de tempo real.
  Map<int, DecodedAudio> _samplesFor(Set<String> hashes) {
    final out = <int, DecodedAudio>{};
    for (final h in hashes) {
      final id = _sampleIds[h];
      final audio = id == null ? null : _decoded[id];
      if (audio != null) out[id!] = audio;
    }
    // os derivados do warp que os clipes tocam agora
    for (final t in doc.tracks) {
      if (t.kind != TrackKind.audio) continue;
      for (final c in t.clips) {
        final s = WarpSpec.of(c, doc.bpm);
        final id = s == null ? null : _warp.idOf(s);
        final audio = id == null ? null : _decoded[id];
        if (audio != null) out[id!] = audio;
      }
    }
    return out;
  }

  static String _renderError(Object e) => switch (e) {
    UnimplementedError() => 'o render fora de tempo real ainda não funciona neste aparelho.',
    StateError(:final message) => message,
    UnsupportedError(:final message) => message ?? '$e',
    _ => '$e',
  };

  /// Nome de arquivo sem os caracteres que os sistemas recusam; vazio vira [fallback].
  static String _fileName(String name, String fallback) {
    var s = name.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_').replaceAll(RegExp(r'\s+'), ' ').trim();
    s = s.replaceAll(RegExp(r'[. ]+$'), '');
    if (s.length > 80) s = s.substring(0, 80).trim();
    return s.isEmpty ? fallback : s;
  }

  static double _peak(List<Float32List> channels) {
    var peak = 0.0;
    for (final c in channels) {
      for (final v in c) {
        final a = v.abs();
        if (a > peak && a.isFinite) peak = a;
      }
    }
    return peak;
  }

  static void _scale(List<Float32List> channels, double gain) {
    for (final c in channels) {
      for (var i = 0; i < c.length; i++) {
        c[i] *= gain;
      }
    }
  }

  static bool _same(Float32List a, Float32List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Apara o silêncio (abaixo de −100 dB) depois de [keep] quadros.
  static List<Float32List> _trimTail(List<Float32List> channels, int keep) {
    final n = channels.map((c) => c.length).reduce(math.min);
    var end = math.min(keep, n);
    for (var i = n - 1; i >= end; i--) {
      if (channels.any((c) => c[i].abs() > 1e-5)) {
        end = i + 1;
        break;
      }
    }
    return [for (final c in channels) end == c.length ? c : (Float32List(end)..setRange(0, end, c))];
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

  void scrollTo(double beat) {
    scrollBeat = math.max(0, beat);
    notifyListeners();
  }

  void toggleFollow() {
    follow = !follow;
    notifyListeners();
  }

  void setLaneScale(LaneScale s) {
    laneScale = s;
    notifyListeners();
  }

  void toggleRulerTime() {
    rulerTime = !rulerTime;
    notifyListeners();
  }

  /// Ligado pelo usuário (null: automático, aparece quando o documento tem mudanças de andamento).
  bool? _tempoLane;

  /// A faixa de andamento sob a régua está à mostra.
  bool get tempoLaneVisible => _tempoLane ?? !doc.tempo.isSingle;

  void toggleTempoLane() {
    _tempoLane = !tempoLaneVisible;
    notifyListeners();
  }

  /// Enquadra o trecho [from, to] (em batidas) na janela, com uma folga nas pontas.
  void fitRange(double from, double to) {
    final span = math.max(to - from, doc.meter.barBeatsAt(math.max(0.0, from)));
    final pad = span * 0.04;
    pxPerBeat = (viewWidth / (span + 2 * pad)).clamp(4.0, 800.0);
    scrollBeat = math.max(0, from - pad);
    notifyListeners();
  }

  /// Fim do arranjo para o zoom e o minimapa: o último clipe, marcador ou o fim do loop ligado.
  double get arrangementEnd => math.max(math.max(doc.contentEnd, doc.markers.isEmpty ? 0.0 : doc.markers.last.beat), doc.loopOn ? doc.loopEnd : 0.0);

  /// Enquadra o projeto inteiro.
  void fitAll() => fitRange(0, arrangementEnd);

  /// Intervalo do clipe selecionado (batidas), ou null sem seleção.
  (double, double)? get selectedRange {
    final a = selection;
    if (a != null) return (a.$2.start, doc.clipEnd(a.$2));
    final m = midiSelection;
    if (m != null) return (m.$2.start, m.$2.end);
    return null;
  }

  /// Enquadra o clipe selecionado; sem seleção, o projeto inteiro.
  void fitSelection() {
    final r = selectedRange;
    if (r == null) return fitAll();
    fitRange(r.$1, r.$2);
  }

  // ------------------------------------------------------------------ marcadores e seções

  static const markerColors = [0xFFE3B341, 0xFFF0464B, 0xFF6BA8F0, 0xFF56D364, 0xFFBC8CFF, 0xFFFF8FB1];

  Marker? markerById(String id) {
    for (final m in doc.markers) {
      if (m.id == id) return m;
    }
    return null;
  }

  /// O marcador nesta batida (tolerância de 1/1000), se houver.
  Marker? markerAt(double beat) {
    for (final m in doc.markers) {
      if ((m.beat - beat).abs() < 0.001) return m;
    }
    return null;
  }

  /// Cria um marcador em [beat] (o cursor, por padrão); onde já há um, devolve o que existe.
  Marker addMarker({double? beat, String? name}) {
    final b = ((beat ?? this.beat.value).clamp(0.0, double.infinity) * 1000).round() / 1000;
    final have = markerAt(b);
    if (have != null) {
      if (name != null && name.isNotEmpty && name != have.name) renameMarker(have.id, name);
      return have;
    }
    final m = Marker(id: newId(), beat: b, name: name == null || name.isEmpty ? 'Marcador ${doc.markers.length + 1}' : name);
    edit((d) => d.markers = [...d.markers, m]..sort((a, b) => a.beat.compareTo(b.beat)));
    selectedMarker = m.id;
    notifyListeners();
    return m;
  }

  /// Move um marcador. Num arraste, [undoable] é false nos passos (o [checkpoint] é do começo).
  void moveMarker(String id, double beat, {bool undoable = true}) {
    final m = markerById(id);
    if (m == null) return;
    final b = math.max(0.0, beat);
    if (b == m.beat) return;
    void apply(DawDoc d) {
      m.beat = b;
      d.markers.sort((x, y) => x.beat.compareTo(y.beat));
    }

    undoable ? edit(apply) : mutate(apply);
  }

  void renameMarker(String id, String name) {
    final m = markerById(id);
    if (m == null || m.name == name) return;
    edit((_) => m.name = name);
  }

  void recolorMarker(String id, int color) {
    final m = markerById(id);
    if (m == null || m.color == color) return;
    edit((_) => m.color = color);
  }

  void removeMarker(String id) {
    if (markerById(id) == null) return;
    edit((d) => d.markers.removeWhere((m) => m.id == id));
    if (selectedMarker == id) selectedMarker = null;
    notifyListeners();
  }

  /// Marcador estritamente antes / depois de [beat] (com meio milésimo de folga, para o cursor
  /// parado num marcador ir ao vizinho e não a ele mesmo).
  Marker? markerBefore(double beat) => doc.markers.where((m) => m.beat < beat - 0.001).lastOrNull;
  Marker? markerAfter(double beat) => doc.markers.where((m) => m.beat > beat + 0.001).firstOrNull;

  /// Leva o cursor (e a janela, se ele sair dela) para [b].
  void goTo(double b) {
    if (recording) return;
    seek(b);
    if (b < scrollBeat || b > scrollBeat + viewWidth / pxPerBeat) scrollBeat = math.max(0, b - 2);
    notifyListeners();
  }

  /// Vai ao marcador anterior; sem ele, ao começo. Devolve se o cursor andou.
  bool jumpToPreviousMarker() {
    final cur = beat.value;
    final m = markerBefore(cur);
    if (m == null && cur <= 0.001) return false;
    goTo(m?.beat ?? 0);
    return true;
  }

  bool jumpToNextMarker() {
    final m = markerAfter(beat.value);
    if (m == null) return false;
    goTo(m.beat);
    return true;
  }

  /// A seção que contém [beat]: do marcador anterior (ou igual) ao seguinte; a última seção vai até
  /// o fim do arranjo. Null antes do primeiro marcador ou sem marcadores.
  (double, double)? sectionAt(double beat) {
    Marker? from;
    for (final m in doc.markers) {
      if (m.beat <= beat + 0.001) from = m;
    }
    if (from == null) return null;
    final next = doc.markers.where((m) => m.beat > from!.beat + 0.001).firstOrNull;
    final end = next?.beat ?? arrangementEnd;
    return end - from.beat > 0.01 ? (from.beat, end) : null;
  }

  bool get canLoopSection => sectionAt(beat.value) != null;
  bool get canLoopBetweenMarkers => doc.markers.length >= 2;
  bool get canLoopSelection => selectedRange != null;

  void _loopTo(double a, double b) {
    if (_blockedByRecording('mudar o loop')) return;
    edit((d) {
      d.loopStart = a;
      d.loopEnd = b;
      d.loopOn = true;
    });
  }

  /// Loop da seção onde o cursor está.
  bool loopSection() {
    final s = sectionAt(beat.value);
    if (s == null) return false;
    _loopTo(s.$1, s.$2);
    return true;
  }

  /// Loop entre o marcador selecionado e o próximo (o anterior, se for o último); sem seleção,
  /// do primeiro ao último marcador.
  bool loopBetweenMarkers() {
    final ms = doc.markers;
    if (ms.length < 2) return false;
    final sel = selectedMarker == null ? null : markerById(selectedMarker!);
    if (sel == null) {
      _loopTo(ms.first.beat, ms.last.beat);
      return true;
    }
    final i = ms.indexOf(sel);
    final (a, b) = i + 1 < ms.length ? (sel.beat, ms[i + 1].beat) : (ms[i - 1].beat, sel.beat);
    _loopTo(a, b);
    return true;
  }

  /// Loop do clipe selecionado.
  bool loopSelection() {
    final r = selectedRange;
    if (r == null || r.$2 - r.$1 < 0.01) return false;
    _loopTo(r.$1, r.$2);
    return true;
  }

  /// O que [moveTrack] desfaria em silêncio ao mover a faixa [from] para [to]: envios e saídas de
  /// barramento para barramento que passariam a apontar para trás (e a automação desses envios).
  /// Uma frase por rota; vazio se o movimento não quebra nada. Com [groups] (o padrão), vêm também
  /// as trocas de saída por entrar ou sair de uma pasta ([groupNotesForMove]).
  List<String> routesBrokenByMove(int from, int to, {bool groups = true}) {
    final plan = planTrackMove(doc.tracks, from, to);
    if (plan == null) return const [];
    final order = plan.order;
    final index = {for (var i = 0; i < order.length; i++) order[i].id: i};
    final out = <String>[];
    for (var i = 0; i < order.length; i++) {
      final t = order[i];
      if (t.kind != TrackKind.bus) continue;
      for (final s in t.sends) {
        final j = index[s.target];
        if (j == null || j > i || order[j].kind != TrackKind.bus) continue;
        final auto = t.lanes.any((l) => l.target.kind == AutoKind.send && l.target.ref == s.target);
        out.add('o envio de "${t.name}" para "${order[j].name}"${auto ? ' e a automação dele' : ''}');
      }
      final o = t.output == null ? null : index[t.output];
      if (o != null && o <= i && order[o].kind == TrackKind.bus) out.add('a saída de "${t.name}" para "${order[o].name}" (volta ao master)');
    }
    if (groups) out.addAll(groupNotesForMove(from, to));
    return out;
  }

  /// O que mover a faixa [from] para [to] muda na saída dela por entrar ou sair de uma pasta.
  List<String> groupNotesForMove(int from, int to) {
    final plan = planTrackMove(doc.tracks, from, to);
    if (plan == null) return const [];
    return [
      for (final c in plan.changes)
        if (c.warning != null) c.warning!,
    ];
  }
}
