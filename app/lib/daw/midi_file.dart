/// Arquivos MIDI padrão (.mid): leitura (SMF tipo 0, 1 e 2) e escrita (tipo 1, 480 PPQ). Só Dart
/// puro, sem tela nem motor: o controlador e `midi_file_ui.dart` chamam daqui.
///
/// Cuidado com o dart2js: os inteiros do navegador têm 32 bits nas operações de bit. Aqui nada
/// desloca bits (VLQ e tempos usam multiplicação, `%` e `~/`).
///
/// O que a leitura entende: nota ligada/desligada (ligada com velocidade 0 desliga), andamento
/// (FF 51), compasso (FF 58), nome da faixa (FF 03), pitch bend, CC 1 (modulação) e CC 64 (pedal),
/// que são os controles do app ([MidiClip.controls]). O resto (program change, volume, pan,
/// letras…) é ignorado sem falhar. O canal 10 é bateria (GM) e as notas vão para as peças do app.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'instruments.dart';
import 'midi_cc.dart' show bendRangeOf, bendRangeParamId;
import 'model.dart';
import 'presets.dart' show Preset, presetsFor;
import 'tempo_map.dart';

/// Problema no arquivo, com a mensagem pronta para a tela (português).
class MidiFormatException implements Exception {
  final String message;
  const MidiFormatException(this.message);
  @override
  String toString() => message;
}

/// Pulsos por semínima usados na escrita.
const midiExportPpq = 480;

/// Duração mínima de uma nota (em batidas) quando o arquivo traz nota de duração zero.
const midiMinNoteBeats = 1 / 32;

/// Um ponto do mapa de andamento do arquivo: a batida (semínimas) e o BPM dali em diante. A
/// importação leva a lista inteira ([MidiFileData.tempoMap], simplificada por [simplifyTempo]) para o
/// mapa de andamento do projeto (`DawController.applyImportedTempo`).
class MidiTempoPoint {
  final double beat, bpm;
  const MidiTempoPoint(this.beat, this.bpm);
}

/// Uma faixa de notas do arquivo: um canal de uma trilha.
class MidiFileTrack {
  String name;

  /// Canal 0..15 (o "canal 10" dos músicos é o 9).
  final int channel;
  bool get drums => channel == 9;

  /// Início e duração em batidas (semínimas), ordenadas por início.
  final List<MidiNote> notes;

  /// Bend, modulação e pedal, batida contada do início do arquivo.
  final List<MidiCc> controls;

  MidiFileTrack({required this.name, required this.channel, required this.notes, required this.controls});

  /// Fim da última nota ou controle, em batidas.
  double get endBeat {
    var e = 0.0;
    for (final n in notes) {
      e = math.max(e, n.end);
    }
    for (final c in controls) {
      e = math.max(e, c.beat);
    }
    return e;
  }
}

/// O que foi lido de um arquivo .mid.
class MidiFileData {
  final int format, ppq;
  final List<MidiFileTrack> tracks;

  /// Ordenado por batida; vazio quando o arquivo não traz andamento (vale 120 BPM pelo padrão MIDI).
  final List<MidiTempoPoint> tempoMap;

  /// Tempos por compasso (semínimas) do primeiro compasso do arquivo, ou null.
  final int? beatsPerBar;

  /// As fórmulas de compasso do arquivo como mudanças do app (compasso 1 = o primeiro); vazio quando
  /// o arquivo não traz nenhuma. O tempo do compasso 4/4 padrão vale até a primeira, se ela vier depois do início.
  final List<MeterChange> meterMap;

  /// Avisos para a pessoa (arquivo cortado, notas presas, peças de bateria que não existem…).
  final List<String> warnings;

  MidiFileData({
    required this.format,
    required this.ppq,
    required this.tracks,
    required this.tempoMap,
    required this.beatsPerBar,
    required this.warnings,
    this.meterMap = const [],
  });

  int get noteCount => tracks.fold(0, (a, t) => a + t.notes.length);

  /// O primeiro andamento (BPM real, sem arredondar), ou null.
  double? get firstBpm => tempoMap.isEmpty ? null : tempoMap.first.bpm;

  /// O andamento do arquivo como vai para o projeto: os pontos sem os de diferença desprezível e em
  /// no máximo [midiMaxTempoPoints]. Vazio se o arquivo não traz andamento.
  late final List<TempoPoint> tempoPoints = simplifyTempo(tempoMap);

  /// O andamento muda no meio do arquivo.
  bool get hasTempoChanges => tempoMap.any((p) => (p.bpm - tempoMap.first.bpm).abs() > 0.5);
}

/// Pontos de andamento que a importação leva para o projeto (o motor reserva 256 sem realocar).
const midiMaxTempoPoints = 256;

/// Diferença de BPM abaixo da qual um ponto é fundido no anterior (um arquivo com rampa gravada em
/// dezenas de milhares de eventos vira poucas centenas de pontos).
const midiTempoEpsilon = 0.05;

/// Simplifica o andamento do arquivo: funde os pontos que diferem menos de [epsilon] BPM do último
/// mantido e, se ainda passar de [maxPoints], dobra o [epsilon] até caber. O primeiro ponto fica
/// sempre; se ele não estiver na batida 0, o andamento inicial é 120 BPM (padrão MIDI).
List<TempoPoint> simplifyTempo(List<MidiTempoPoint> input, {int maxPoints = midiMaxTempoPoints, double epsilon = midiTempoEpsilon}) {
  if (input.isEmpty) return const [];
  final src = input.first.beat > 0 ? [const MidiTempoPoint(0, 120), ...input] : input;
  var eps = epsilon;
  while (true) {
    final out = <TempoPoint>[TempoPoint(0, src.first.bpm.clamp(minBpm, maxBpm).toDouble())];
    for (final p in src.skip(1)) {
      final bpm = p.bpm.clamp(minBpm, maxBpm).toDouble();
      if ((bpm - out.last.bpm).abs() < eps) continue;
      out.add(TempoPoint(p.beat, bpm));
    }
    if (out.length <= maxPoints || eps > maxBpm) return out;
    eps *= 2;
  }
}

/// O andamento que a importação deixa no documento: o BPM inicial e o mapa (vazio com um andamento
/// só, caso em que o BPM é inteiro como o app sempre guardou). Null se o arquivo não traz andamento.
({double bpm, List<TempoPoint> points})? importedTempo(MidiFileData d) {
  final pts = d.tempoPoints;
  if (pts.isEmpty) return null;
  if (pts.length == 1) return (bpm: appBpmFor(pts.first.bpm).toDouble(), points: const []);
  final bpm = pts.first.bpm;
  return (bpm: bpm, points: normalizeTempoPoints([pts.first.copyWith(bpm: bpm), ...pts.skip(1)], bpm));
}

/// O compasso que a importação deixa no documento (`beatsPerBar` do primeiro compasso e as mudanças
/// do mapa, vazias quando só sobra um n/4). Null se o arquivo não traz compasso.
({int beatsPerBar, List<MeterChange> changes})? importedMeter(MidiFileData d) {
  if (d.meterMap.isEmpty) {
    final bpb = d.beatsPerBar;
    return bpb == null ? null : (beatsPerBar: bpb, changes: const []);
  }
  final first = d.meterMap.first;
  final bpb = (first.denominator == 4 ? first.numerator : first.barBeats.round()).clamp(1, 32);
  return (beatsPerBar: bpb, changes: normalizeMeterChanges(d.meterMap, bpb));
}

/// O andamento ou o compasso do arquivo diferem dos do documento (então vale perguntar).
bool midiTempoDiffers(MidiFileData d, DawDoc doc) {
  final t = importedTempo(d);
  if (t != null) {
    if (t.bpm.round() != doc.bpm.round() || t.points.length != doc.tempoMap.length) return true;
    for (var i = 0; i < t.points.length; i++) {
      if (t.points[i] != doc.tempoMap[i]) return true;
    }
  }
  final m = importedMeter(d);
  if (m != null) {
    if (m.beatsPerBar != doc.beatsPerBar || m.changes.length != doc.meterMap.length) return true;
    for (var i = 0; i < m.changes.length; i++) {
      if (m.changes[i] != doc.meterMap[i]) return true;
    }
  }
  return false;
}

// ------------------------------------------------------------------ bateria GM

/// Notas GM de percussão (35–59) que o app não tem, mas têm uma peça equivalente: vão para ela.
const _gmDrumAlias = <int, int>{
  35: 36, // bumbo acústico → bumbo
  40: 38, // caixa elétrica → caixa
  43: 41, // tom grave (baixo) → tom grave
  44: 42, // chimbal de pedal → chimbal fechado
  47: 45, // tom médio-grave → tom médio
  50: 48, // tom agudo (alto) → tom agudo
  52: 49, // prato chinês → prato de ataque
  53: 51, // sino do prato → condução
  55: 49, // splash → ataque
  57: 49, // crash 2 → ataque
  59: 51, // condução 2 → condução
};

const _gmDrumNames = <int, String>{
  35: 'Bumbo acústico',
  36: 'Bumbo',
  37: 'Aro',
  38: 'Caixa',
  39: 'Palmas',
  40: 'Caixa elétrica',
  41: 'Tom grave',
  42: 'Chimbal fechado',
  43: 'Tom grave (baixo)',
  44: 'Chimbal de pedal',
  45: 'Tom médio',
  46: 'Chimbal aberto',
  47: 'Tom médio-grave',
  48: 'Tom agudo',
  49: 'Prato de ataque',
  50: 'Tom agudo (alto)',
  51: 'Prato de condução',
  52: 'Prato chinês',
  53: 'Sino do prato',
  54: 'Pandeiro',
  55: 'Splash',
  56: 'Cowbell',
  57: 'Crash 2',
  58: 'Vibraslap',
  59: 'Condução 2',
};

/// Nome GM da nota de percussão, para os avisos.
String gmDrumName(int pitch) => _gmDrumNames[pitch] ?? 'nota $pitch';

/// A peça do app (nota do `drumPieces`) para a nota GM, ou null se o app não tem nada parecido.
int? drumPitchForGm(int pitch) {
  if (drumNameFor(pitch) != null) return pitch;
  return _gmDrumAlias[pitch];
}

// ------------------------------------------------------------------ leitura

class _Eof implements Exception {
  const _Eof();
}

class _Bad implements Exception {
  const _Bad();
}

class _Open {
  final int tick, vel;
  _Open(this.tick, this.vel);
}

class _Group {
  final int channel;
  String name = '';
  final notes = <MidiNote>[];
  final controls = <MidiCc>[];
  final lastValue = <int, double>{};
  _Group(this.channel);
}

class _Reader {
  final Uint8List b;
  int pos;
  final int end;
  _Reader(this.b, this.pos, this.end);

  int u8() {
    if (pos >= end) throw const _Eof();
    return b[pos++];
  }

  /// Quantidade de variável (VLQ), até 4 bytes; multiplicação em vez de deslocamento.
  int vlq() {
    var v = 0;
    for (var i = 0; i < 4; i++) {
      final x = u8();
      v = v * 128 + x % 128;
      if (x < 128) return v;
    }
    throw const _Bad();
  }

  Uint8List take(int n) {
    if (n < 0 || pos + n > end) throw const _Eof();
    final r = Uint8List.sublistView(b, pos, pos + n);
    pos += n;
    return r;
  }
}

int _u16(Uint8List b, int p) => b[p] * 256 + b[p + 1];
int _u32(Uint8List b, int p) => ((b[p] * 256 + b[p + 1]) * 256 + b[p + 2]) * 256 + b[p + 3];
bool _tag(Uint8List b, int p, String t) =>
    p + 4 <= b.length && b[p] == t.codeUnitAt(0) && b[p + 1] == t.codeUnitAt(1) && b[p + 2] == t.codeUnitAt(2) && b[p + 3] == t.codeUnitAt(3);

/// Lê um arquivo .mid. Lança [MidiFormatException] (mensagem em português) para arquivo vazio, que
/// não é MIDI, SMPTE, cabeçalho cortado ou sem nenhuma nota; arquivo cortado no meio devolve o que
/// deu para ler, com aviso. A cada [yieldEvery] eventos devolve o controle ao laço de eventos para
/// não travar a tela num arquivo enorme.
Future<MidiFileData> parseMidiFile(Uint8List bytes, {int yieldEvery = 20000}) async {
  final warnings = <String>[];
  if (bytes.isEmpty) throw const MidiFormatException('O arquivo está vazio.');
  var base = 0;
  if (_tag(bytes, 0, 'RIFF') && bytes.length >= 20 && _tag(bytes, 8, 'RMID') && _tag(bytes, 12, 'data')) base = 20;
  if (!_tag(bytes, base, 'MThd')) {
    throw const MidiFormatException('Este arquivo não é um MIDI padrão (.mid): falta o cabeçalho "MThd".');
  }
  if (bytes.length < base + 14) throw const MidiFormatException('O arquivo MIDI está cortado logo no começo (cabeçalho incompleto).');
  final headerLen = _u32(bytes, base + 4);
  if (headerLen < 6) throw const MidiFormatException('O cabeçalho do arquivo MIDI está corrompido.');
  final format = _u16(bytes, base + 8);
  final division = _u16(bytes, base + 12);
  if (format > 2) throw MidiFormatException('Formato MIDI $format desconhecido: só leio os tipos 0, 1 e 2.');
  if (division >= 0x8000) {
    throw const MidiFormatException('Este arquivo usa tempo em quadros SMPTE, que o app não lê. Salve-o de novo com tempo em pulsos por semínima (PPQ).');
  }
  if (division == 0) throw const MidiFormatException('O arquivo MIDI diz que tem 0 pulsos por semínima: está corrompido.');
  final ppq = division;
  if (format == 2) warnings.add('Este é um MIDI tipo 2 (sequências independentes): todas as sequências entraram juntas, começando do início.');

  final tempos = <(int, int)>[]; // (tick, µs por semínima)
  final sigs = <(int, int, int)>[]; // (tick, nn, dd)
  final groups = <(int, _Group)>[]; // (índice da trilha, grupo)
  final ctx = _ParseCtx(ppq, yieldEvery);
  var pos = base + 8 + headerLen;
  var trackIndex = 0;
  var truncated = false;
  while (pos + 8 <= bytes.length) {
    final len = _u32(bytes, pos + 4);
    final bodyEnd = math.min(pos + 8 + len, bytes.length);
    if (pos + 8 + len > bytes.length) truncated = true;
    if (_tag(bytes, pos, 'MTrk')) {
      final r = _Reader(bytes, pos + 8, bodyEnd);
      final out = <_Group>[];
      final ok = await _parseTrack(r, ctx, out, tempos, sigs);
      if (!ok) truncated = true;
      for (final g in out) {
        groups.add((trackIndex, g));
      }
      trackIndex++;
    }
    pos += 8 + len;
  }
  if (truncated) warnings.add('O arquivo está cortado ou tem trechos corrompidos: usei só o que deu para ler.');
  if (trackIndex == 0) throw const MidiFormatException('O arquivo MIDI não tem nenhuma faixa (está cortado ou corrompido).');

  // só grupos com nota viram faixa; vários canais numa trilha ganham o número do canal no nome
  final withNotes = [
    for (final (t, g) in groups)
      if (g.notes.isNotEmpty) (t, g),
  ];
  if (withNotes.isEmpty) throw const MidiFormatException('O arquivo MIDI não tem nenhuma nota.');
  final perTrack = <int, int>{};
  for (final (t, _) in withNotes) {
    perTrack[t] = (perTrack[t] ?? 0) + 1;
  }
  final tracks = <MidiFileTrack>[];
  final unmapped = <int, int>{};
  var approximated = 0;
  for (final (t, g) in withNotes) {
    if (g.channel == 9) {
      for (final n in g.notes) {
        final p = drumPitchForGm(n.pitch);
        if (p == null) {
          unmapped[n.pitch] = (unmapped[n.pitch] ?? 0) + 1;
        } else {
          if (p != n.pitch) approximated++;
          n.pitch = p;
        }
      }
    }
    g.notes.sort((a, b) => a.start != b.start ? a.start.compareTo(b.start) : a.pitch.compareTo(b.pitch));
    var name = g.name;
    if ((perTrack[t] ?? 1) > 1) name = name.isEmpty ? 'Canal ${g.channel + 1}' : '$name (canal ${g.channel + 1})';
    tracks.add(MidiFileTrack(name: name, channel: g.channel, notes: g.notes, controls: g.controls));
  }
  if (ctx.stuck > 0) warnings.add('${ctx.stuck} nota${ctx.stuck == 1 ? '' : 's'} sem desligar: fechei no fim da faixa.');
  if (ctx.ignoredControls > 0) {
    warnings.add('Ignorei ${ctx.ignoredControls} evento${ctx.ignoredControls == 1 ? '' : 's'} de controle que o app não usa (volume, pan, expressão…).');
  }
  if (approximated > 0) {
    warnings.add(
      '$approximated nota${approximated == 1 ? '' : 's'} de bateria foram para a peça mais parecida do app (por exemplo, crash 2 no prato de ataque).',
    );
  }
  if (unmapped.isNotEmpty) {
    final list = (unmapped.entries.toList()..sort((a, b) => a.key.compareTo(b.key))).map((e) => '${gmDrumName(e.key)} (${e.value})').join(', ');
    warnings.add('A bateria do app não tem: $list. Essas notas entraram, mas ficam sem som.');
  }

  // andamento e compasso: o primeiro de cada; as mudanças ficam no mapa
  tempos.sort((a, b) => a.$1.compareTo(b.$1));
  final tempoMap = <MidiTempoPoint>[];
  for (final (tick, us) in tempos) {
    if (us <= 0) continue;
    final p = MidiTempoPoint(tick / ppq, 60000000 / us);
    if (tempoMap.isNotEmpty && tempoMap.last.beat == p.beat) tempoMap.removeLast();
    tempoMap.add(p);
  }
  sigs.sort((a, b) => a.$1.compareTo(b.$1));
  int? bpb;
  final meters = <MeterChange>[];
  if (sigs.isNotEmpty) {
    // uma fórmula por instante (a última vale); antes da primeira, se ela vier depois do início, vale 4/4
    final bySig = <int, (int, int)>{};
    var meterApprox = false, misaligned = false;
    for (final (tick, nn, dd) in sigs) {
      if (nn <= 0) continue;
      var num = nn, den = 1;
      var e = dd;
      while (e > 0 && den < 32) {
        den *= 2;
        e--;
      }
      // denominador acima de 32: mesma duração com fusas
      if (e > 0) {
        var f = 1.0;
        for (var i = 0; i < e; i++) {
          f *= 2;
        }
        num = math.max(1, (nn / f).round());
        meterApprox = true;
      }
      if (num > 64) {
        num = 64;
        meterApprox = true;
      }
      bySig[tick] = (num, den);
    }
    final ticks = bySig.keys.toList()..sort();
    var curStart = 0.0; // batida em que começa o compasso da última mudança
    if (ticks.isNotEmpty && ticks.first > 0) meters.add(const MeterChange(1, 4, 4));
    for (final tk in ticks) {
      final (num, den) = bySig[tk]!;
      if (meters.isEmpty) {
        meters.add(MeterChange(1, num, den));
        continue;
      }
      final cur = meters.last;
      final elapsed = (tk / ppq - curStart) / cur.barBeats;
      final k = elapsed.round();
      if ((elapsed - k).abs() > 1e-6) misaligned = true;
      if (num == cur.numerator && den == cur.denominator) continue;
      if (k < 1) {
        // antes do fim do compasso vigente: a fórmula nova o substitui
        meters.removeLast();
        meters.add(MeterChange(cur.bar, num, den));
      } else {
        curStart += k * cur.barBeats;
        meters.add(MeterChange(cur.bar + k, num, den));
      }
    }
    if (meters.isNotEmpty) bpb = importedMeterBeats(meters.first);
    if (meterApprox) warnings.add('Uma fórmula de compasso do arquivo passa dos limites do app (denominador até 32, numerador até 64) e foi aproximada.');
    if (misaligned) warnings.add('Uma mudança de compasso caiu no meio de um compasso: alinhei ao compasso mais próximo.');
  }
  return MidiFileData(format: format, ppq: ppq, tracks: tracks, tempoMap: tempoMap, beatsPerBar: bpb, warnings: warnings, meterMap: meters);
}

/// Tempos (semínimas) do primeiro compasso do arquivo, do jeito que o app guarda no `beatsPerBar`.
int importedMeterBeats(MeterChange first) => first.barBeats.round().clamp(1, 12);

class _ParseCtx {
  final int ppq, yieldEvery;
  int events = 0, stuck = 0, ignoredControls = 0;
  _ParseCtx(this.ppq, this.yieldEvery);
}

/// Lê uma trilha. Devolve false se ela terminou cortada ou corrompida (o que veio antes vale).
Future<bool> _parseTrack(_Reader r, _ParseCtx ctx, List<_Group> out, List<(int, int)> tempos, List<(int, int, int)> sigs) async {
  final byChannel = <int, _Group>{};
  final open = <int, List<_Open>>{};
  final ppq = ctx.ppq;
  String? name;
  var tick = 0, status = 0;
  var ok = true;
  _Group group(int ch) => byChannel.putIfAbsent(ch, () {
    final g = _Group(ch);
    out.add(g);
    return g;
  });

  void closeNote(int ch, int pitch, int at) {
    final list = open[ch * 128 + pitch];
    if (list == null || list.isEmpty) return;
    final o = list.removeAt(0);
    // só a duração zero ganha o mínimo: notas curtíssimas de verdade voltam como foram escritas
    final len = at > o.tick ? (at - o.tick) / ppq : midiMinNoteBeats;
    group(ch).notes.add(MidiNote(pitch: pitch, start: o.tick / ppq, length: len, velocity: o.vel / 127));
  }

  void control(int ch, int cc, int at, double value) {
    final g = group(ch);
    if (g.lastValue[cc] == value) return;
    g.lastValue[cc] = value;
    g.controls.add(MidiCc(cc: cc, beat: at / ppq, value: value));
  }

  try {
    while (r.pos < r.end) {
      tick += r.vlq();
      if (++ctx.events % ctx.yieldEvery == 0) await Future<void>.delayed(Duration.zero);
      var first = r.u8();
      if (first >= 0x80) {
        if (first == 0xFF) {
          final type = r.u8();
          final data = r.take(r.vlq());
          status = 0;
          if (type == 0x2F) break;
          if (type == 0x51 && data.length == 3) {
            tempos.add((tick, (data[0] * 256 + data[1]) * 256 + data[2]));
          } else if (type == 0x58 && data.length >= 2) {
            sigs.add((tick, data[0], data[1]));
          } else if (type == 0x03 && name == null) {
            name = utf8.decode(data, allowMalformed: true).replaceAll(RegExp(r'[\u0000-\u001f\u007f�]'), '').trim();
          }
          continue;
        }
        if (first == 0xF0 || first == 0xF7) {
          r.take(r.vlq());
          status = 0;
          continue;
        }
        if (first >= 0xF0) {
          // mensagens de sistema (F1 a F6, F8 a FE): sem canal, poucos dados
          status = 0;
          if (first == 0xF1 || first == 0xF3) r.u8();
          if (first == 0xF2) r.take(2);
          continue;
        }
        status = first;
        first = r.u8();
      } else if (status == 0) {
        // dado sem nenhum status antes (nem running status): corrompido
        throw const _Bad();
      }
      final kind = status ~/ 16, ch = status % 16;
      if (first >= 0x80) throw const _Bad();
      if (kind == 0xC || kind == 0xD) continue; // program change e pressão do canal: ignorados
      final d2 = r.u8();
      if (d2 >= 0x80) throw const _Bad();
      switch (kind) {
        case 0x9 when d2 > 0:
          (open[ch * 128 + first] ??= []).add(_Open(tick, d2));
          group(ch);
        case 0x8 || 0x9:
          closeNote(ch, first, tick);
        case 0xE:
          control(ch, ccBend, tick, math.min(1.0, (first + d2 * 128 - 8192) / 8192));
        case 0xB when first == 1:
          control(ch, ccMod, tick, d2 / 127);
        case 0xB when first == 64:
          control(ch, ccSustain, tick, d2 >= 64 ? 1.0 : 0.0);
        case 0xB when first >= 120:
          break; // all notes off e afins
        case 0xB when first == 6 || first == 38 || (first >= 98 && first <= 101):
          break; // RPN/NRPN (o alcance do bend que a exportação escreve): não é um controle perdido
        case 0xB:
          ctx.ignoredControls++;
        default:
          break;
      }
    }
  } on _Eof {
    ok = false;
  } on _Bad {
    ok = false;
  }
  // notas presas: fecham no fim da trilha
  for (final e in open.entries.toList()) {
    final ch = e.key ~/ 128, pitch = e.key % 128;
    while (e.value.isNotEmpty) {
      ctx.stuck++;
      closeNote(ch, pitch, tick);
    }
  }
  final trackName = name;
  if (trackName != null && trackName.isNotEmpty) {
    for (final g in out) {
      if (g.name.isEmpty) g.name = trackName;
    }
  }
  return ok;
}

// ------------------------------------------------------------------ escrita

/// Faixa a escrever: nome, canal 0..15 e os clipes (a batida de cada clipe soma [offset]).
class _OutTrack {
  final String name;
  final int channel;
  final List<MidiClip> clips;
  final double offset;

  /// A faixa do documento (para o programa e o alcance do bend); null num clipe avulso sem faixa.
  final DawTrack? track;
  _OutTrack(this.name, this.channel, this.clips, this.offset, [this.track]);
}

/// O arquivo pronto e o que entrou nele.
class MidiExport {
  final Uint8List bytes;
  final int tracks, notes;

  /// Notas que ficaram de fora (fora de 0–127 ou fora do trecho do clipe).
  final int skipped;

  /// Pontos de controle (bend, modulação, pedal) que ficaram de fora por cair fora do trecho do clipe.
  final int skippedControls;

  /// Faixas com notas que não entraram no arquivo porque estão mudas (ou porque há outra em solo).
  final List<String> silenced;
  const MidiExport(this.bytes, this.tracks, this.notes, this.skipped, {this.skippedControls = 0, this.silenced = const []});
}

/// Faixas do documento que têm notas ou controles, na ordem da mesa (mudas e solos incluídos).
List<DawTrack> exportableTracks(DawDoc doc) => [
  for (final t in doc.tracks)
    if (t.kind.isInstrument && t.midi.any((c) => c.notes.isNotEmpty || c.controls.isNotEmpty)) t,
];

/// As faixas que [buildMidiFile] escreve quando o arquivo é do projeto todo: as de [exportableTracks]
/// que se ouviriam (com alguma faixa em solo só as em solo; senão todas menos as mudas), como o
/// render de áudio.
List<DawTrack> audibleExportTracks(DawDoc doc) {
  final soloed = doc.tracks.any((t) => t.solo);
  return [
    for (final t in exportableTracks(doc))
      if (soloed ? t.solo : !t.mute) t,
  ];
}

/// O preset (dos de fábrica) que mais se parece com o timbre da faixa agora: o de menos parâmetros
/// diferentes, ignorando o alcance do bend e a afinação/nota base do sampler. Quem mexeu num botão
/// depois de escolher o preset ainda cai nele; passando de [_presetMaxDiff] parâmetros diferentes,
/// nenhum. Em empate vale o primeiro da lista (o "Inicial").
Preset? _nearestPreset(DawTrack t) {
  final skip = {
    bendRangeParamId(t.kind),
    if (t.kind == TrackKind.sampler) ...[0, 7],
  };
  Preset? best;
  var bestDiff = 1 << 30;
  for (final p in presetsFor(t.kind)) {
    var diff = 0;
    for (final spec in t.kind.params) {
      if (skip.contains(spec.id)) continue;
      final want = p.values[spec.id] ?? spec.def;
      if ((t.param(spec.id) - want).abs() > 1e-6 * math.max(1, want.abs())) diff++;
    }
    if (diff < bestDiff) {
      best = p;
      bestDiff = diff;
    }
  }
  return bestDiff <= _presetMaxDiff ? best : null;
}

const _presetMaxDiff = 6;

/// O programa GM (0..127) que o arquivo pede para a faixa, pela categoria do preset (de fábrica) que mais se parece com o timbre dela
/// agora (Baixos → Synth Bass, Leads → Lead, Pads → Pad, Teclas → piano elétrico…); sem preset
/// reconhecido, um lead (sintetizador, FM e wavetable) ou o piano (sampler). A bateria vai no canal
/// 10, onde o programa 0 é o kit padrão.
int midiProgramFor(DawTrack t) {
  if (t.kind == TrackKind.drums) return 0;
  final cat = _nearestPreset(t)?.category ?? '';
  if (cat.startsWith('Plucks')) return 45; // Pizzicato Strings
  return switch (cat) {
    'Baixos' => 38, // Synth Bass 1
    'Leads' => 80, // Lead 1 (square)
    'Pads' => 89, // Pad 2 (warm)
    'Teclas' => 4, // Electric Piano 1
    'Vocais' => 54, // Synth Voice
    'Efeitos' => 98, // FX 3 (crystal)
    'Texturas' => 88, // Pad 1 (new age)
    'Básico' => 80,
    _ => t.kind == TrackKind.sampler ? 0 : 80,
  };
}

/// O que abre a trilha de uma faixa, no instante 0: o alcance do bend (RPN 0, igual ao "Alcance do
/// bend" do instrumento; sem isso o outro programa usaria 2 semitons e o bend sairia errado) e o
/// Program Change. A bateria só leva o Program Change.
List<List<int>> _channelSetup(DawTrack t, int ch) {
  final program = [0xC0 + ch, midiProgramFor(t)];
  if (t.kind == TrackKind.drums) return [program];
  final range = bendRangeOf(t).clamp(0.0, 24.0);
  final semis = range.floor();
  final cents = ((range - semis) * 100).round().clamp(0, 99);
  return [
    [0xB0 + ch, 101, 0],
    [0xB0 + ch, 100, 0],
    [0xB0 + ch, 6, semis],
    [0xB0 + ch, 38, cents],
    // RPN nulo: os controles de dados seguintes não mexem mais no alcance
    [0xB0 + ch, 101, 127],
    [0xB0 + ch, 100, 127],
    program,
  ];
}

/// Monta o .mid (tipo 1, 480 PPQ): uma trilha de andamento e compasso e uma por faixa, cada uma no
/// seu canal (bateria no 10). Com [only] escreve só esse clipe, movido para o começo do arquivo;
/// sem ele, todas as [exportableTracks] na posição em que estão. Notas fora de 0–127, fora do
/// trecho do clipe ou com valores inválidos ficam de fora ([MidiExport.skipped]). Lança
/// [MidiFormatException] se não há nada para escrever.
MidiExport buildMidiFile(DawDoc doc, {MidiClip? only, DawTrack? onlyTrack, String title = ''}) {
  final outs = <_OutTrack>[];
  final silenced = <String>[];
  if (only != null) {
    final drums = onlyTrack?.kind == TrackKind.drums;
    outs.add(_OutTrack(only.name.isNotEmpty ? only.name : (onlyTrack?.name ?? ''), drums ? 9 : 0, [only], -only.start, onlyTrack));
  } else {
    var k = 0;
    final audible = audibleExportTracks(doc);
    silenced.addAll([
      for (final t in exportableTracks(doc))
        if (!audible.contains(t)) t.name,
    ]);
    for (final t in audible) {
      final drums = t.kind == TrackKind.drums;
      var ch = 9;
      if (!drums) {
        ch = k % 15;
        if (ch >= 9) ch++;
        k++;
      }
      outs.add(_OutTrack(t.name, ch, t.midi, 0, t));
    }
  }
  if (outs.isEmpty && silenced.isNotEmpty) {
    throw const MidiFormatException('As faixas com notas estão mudas (ou há outra em solo): tire o mudo, ou exporte só o clipe selecionado.');
  }
  if (outs.isEmpty || outs.every((o) => o.clips.every((c) => c.notes.isEmpty && c.controls.isEmpty))) {
    throw const MidiFormatException('Não há notas para exportar: desenhe ou grave um clipe de notas primeiro.');
  }
  final file = <int>[];
  void u16(int v) => file.addAll([v ~/ 256 % 256, v % 256]);
  void u32(int v) => file.addAll([v ~/ 16777216 % 256, v ~/ 65536 % 256, v ~/ 256 % 256, v % 256]);
  void chunk(List<int> body) {
    file.addAll('MTrk'.codeUnits);
    u32(body.length);
    file.addAll(body);
  }

  file.addAll('MThd'.codeUnits);
  u32(6);
  u16(1);
  u16(outs.length + 1);
  u16(midiExportPpq);

  // trilha de andamento e compasso: todo o mapa do projeto (no clipe avulso, a partir do começo dele)
  final head = <int>[];
  _meta(head, 0x03, utf8.encode(title));
  var prevHead = 0;
  for (final e in _tempoMeterEvents(doc, only != null ? -only.start : 0)) {
    _vlq(head, e.tick - prevHead);
    prevHead = e.tick;
    head.addAll([0xFF, e.type]);
    _vlq(head, e.data.length);
    head.addAll(e.data);
  }
  _meta(head, 0x2F, const []);
  chunk(head);

  var notes = 0, skipped = 0, skippedControls = 0;
  for (final o in outs) {
    // desligar vem antes de controlar, que vem antes de ligar, no mesmo instante
    final ev = <({int tick, int order, int seq, List<int> data})>[];
    var seq = 0;
    final ch = o.channel;
    final t0 = o.track;
    if (t0 != null) {
      for (final data in _channelSetup(t0, ch)) {
        ev.add((tick: 0, order: -1, seq: seq++, data: data));
      }
    }
    for (final c in o.clips) {
      final at = c.start + o.offset;
      for (final n in c.notes) {
        if (n.pitch < 0 || n.pitch > 127 || !n.start.isFinite || !n.length.isFinite || n.start < 0 || n.start >= c.length) {
          skipped++;
          continue;
        }
        final on = ((at + n.start) * midiExportPpq).round();
        final int off = on + math.max(1, (n.length * midiExportPpq).round());
        final v = (n.velocity.isFinite ? (n.velocity * 127).round() : 100).clamp(1, 127);
        ev.add((tick: on, order: 2, seq: seq++, data: [0x90 + ch, n.pitch, v]));
        ev.add((tick: off, order: 0, seq: seq++, data: [0x80 + ch, n.pitch, 0]));
        notes++;
      }
      for (final e in c.controls) {
        if (!e.beat.isFinite || !e.value.isFinite || e.beat < 0 || e.beat > c.length) {
          skippedControls++;
          continue;
        }
        final t = ((at + e.beat) * midiExportPpq).round();
        if (e.cc == ccBend) {
          final w = ((e.value.clamp(-1.0, 1.0) * 8192).round() + 8192).clamp(0, 16383);
          ev.add((tick: t, order: 1, seq: seq++, data: [0xE0 + ch, w % 128, w ~/ 128]));
        } else if (e.cc == ccMod) {
          ev.add((tick: t, order: 1, seq: seq++, data: [0xB0 + ch, 1, (e.value.clamp(0.0, 1.0) * 127).round()]));
        } else if (e.cc == ccSustain) {
          ev.add((tick: t, order: 1, seq: seq++, data: [0xB0 + ch, 64, e.value >= 0.5 ? 127 : 0]));
        }
      }
    }
    ev.sort((a, b) {
      if (a.tick != b.tick) return a.tick.compareTo(b.tick);
      if (a.order != b.order) return a.order.compareTo(b.order);
      return a.seq.compareTo(b.seq);
    });
    final body = <int>[];
    _meta(body, 0x03, utf8.encode(o.name));
    var prev = 0;
    for (final e in ev) {
      _vlq(body, e.tick - prev);
      prev = e.tick;
      body.addAll(e.data);
    }
    _meta(body, 0x2F, const []);
    chunk(body);
  }
  return MidiExport(Uint8List.fromList(file), outs.length, notes, skipped, skippedControls: skippedControls, silenced: silenced);
}

/// Passos de uma rampa de andamento no arquivo: 1/16 de batida (o SMF só tem degraus).
const _rampStepsPerBeat = 16;

/// Os eventos de andamento (FF 51) e compasso (FF 58) do mapa do projeto, em ticks, ordenados
/// (andamento antes de compasso no mesmo instante). [shift] soma-se às batidas (o clipe avulso vai
/// para o começo do arquivo: vale o andamento e o compasso que havia no começo dele). Rampas viram
/// degraus de 1/16 de batida; eventos no mesmo tick ficam com o último e valores repetidos somem.
List<({int tick, int type, List<int> data})> _tempoMeterEvents(DawDoc doc, double shift) {
  final start = -shift;
  final out = <({int tick, int type, List<int> data})>[];
  int tickOf(double beat) => math.max(0, ((beat + shift) * midiExportPpq).round());

  // andamento: degraus (batida, bpm) de todo o mapa
  final pts = doc.tempo.points;
  final steps = <(double, double)>[];
  for (var i = 0; i < pts.length; i++) {
    final p = pts[i];
    final next = i + 1 < pts.length ? pts[i + 1] : null;
    if (next != null && p.ramp && (next.bpm - p.bpm).abs() > 1e-9) {
      final len = next.beat - p.beat;
      final n = math.min(4096, math.max(1, (len * _rampStepsPerBeat).ceil()));
      for (var k = 0; k < n; k++) {
        final beat = p.beat + k * len / n;
        steps.add((beat, p.bpm + (next.bpm - p.bpm) * k / n));
      }
    } else {
      steps.add((p.beat, p.bpm));
    }
  }
  var inEffect = steps.first.$2;
  final later = <(double, double)>[];
  for (final (beat, bpm) in steps) {
    if (beat <= start + 1e-9) {
      inEffect = bpm;
    } else {
      later.add((beat, bpm));
    }
  }
  final tempos = <int, int>{}; // tick → µs por semínima, em ordem de inserção
  int usOf(double bpm) => (60000000 / (bpm.isFinite && bpm > 0 ? bpm : 120)).round().clamp(1, 16777215);
  tempos[0] = usOf(start > 0 && !doc.tempo.isSingle ? doc.tempo.bpmAt(start) : inEffect);
  int? last = tempos[0];
  for (final (beat, bpm) in later) {
    final us = usOf(bpm);
    final tk = tickOf(beat);
    if (us == last && !tempos.containsKey(tk)) continue;
    tempos.remove(tk);
    tempos[tk] = us;
    last = us;
  }
  final ticks = tempos.keys.toList()..sort();
  for (final tk in ticks) {
    final us = tempos[tk]!;
    out.add((tick: tk, type: 0x51, data: [us ~/ 65536 % 256, us ~/ 256 % 256, us % 256]));
  }

  // compasso
  final meter = doc.meter;
  List<int> sig(MeterChange m) => [m.numerator.clamp(1, 255), math.max(0, meterDenominators.indexOf(m.denominator)), 24, 8];
  final (bar0, _) = meter.barOf(math.max(0.0, start));
  out.add((tick: 0, type: 0x58, data: sig(meter.changeAt(bar0))));
  for (final m in meter.changes) {
    final at = meter.barStart(m.bar);
    if (at > start + 1e-9) out.add((tick: tickOf(at), type: 0x58, data: sig(m)));
  }
  // estável: andamento antes de compasso no mesmo tick, que já é a ordem de inserção
  final indexed = [for (var i = 0; i < out.length; i++) (i, out[i])];
  indexed.sort((a, b) {
    final c = a.$2.tick.compareTo(b.$2.tick);
    if (c != 0) return c;
    final t = a.$2.type.compareTo(b.$2.type);
    return t != 0 ? t : a.$1.compareTo(b.$1);
  });
  return [for (final e in indexed) e.$2];
}

void _vlq(List<int> out, int v) {
  final parts = <int>[v % 128];
  var rest = v ~/ 128;
  while (rest > 0) {
    parts.add(rest % 128 + 128);
    rest ~/= 128;
  }
  out.addAll(parts.reversed);
}

/// Meta-evento no tempo 0 (delta zero).
void _meta(List<int> out, int type, List<int> data) {
  out.add(0);
  out.addAll([0xFF, type]);
  _vlq(out, data.length);
  out.addAll(data);
}

/// Nome do arquivo `.mid` para um título, sem caracteres que os sistemas de arquivo recusam.
String midiFileName(String title) {
  var n = title.replaceAll(RegExp(r'[\u0000-\u001f\u007f/\\:*?"<>|]'), '_').trim().replaceAll(RegExp(r'^\.+'), '').trim();
  if (n.runes.length > 80) n = String.fromCharCodes(n.runes.take(80)).trim();
  if (n.isEmpty) n = 'notas';
  return '$n.mid';
}

/// O que a importação fez, para a tela contar.
class MidiImportReport {
  final int tracks, notes;

  /// O andamento (e compasso) do arquivo foram para o projeto.
  final bool tempoApplied;
  final List<String> warnings;
  const MidiImportReport({required this.tracks, required this.notes, required this.tempoApplied, required this.warnings});
}

/// O andamento como o app o guarda: BPM inteiro na janela do servidor (20 a 999).
int appBpmFor(double bpm) => bpm.isFinite ? bpm.round().clamp(minBpmInt, maxBpmInt) : 120;

// ------------------------------------------------------------------ montar faixas para o documento

/// Uma faixa pronta para entrar no documento: o tipo (o instrumento melódico escolhido ou a bateria) e o clipe.
typedef MidiImportTrack = ({String name, TrackKind kind, MidiClip clip});

/// Transforma o que foi lido em faixas e clipes (um por faixa do arquivo, começando em [start]).
/// O tamanho de cada clipe fecha no compasso seguinte ao fim das notas (pelo [meter], o mapa de
/// compassos que o projeto terá depois da importação; sem ele, [beatsPerBar] fixo). As faixas
/// melódicas viram [melodic] (sintetizador, FM, wavetable ou sampler); o canal 10 é sempre bateria.
List<MidiImportTrack> midiImportTracks(
  MidiFileData data, {
  required int beatsPerBar,
  double start = 0,
  required String Function() newId,
  TrackKind melodic = TrackKind.synth,
  MeterMap? meter,
}) {
  final bar = beatsPerBar < 1 ? 4 : beatsPerBar;
  double lengthFor(double end) {
    if (meter == null || meter.isSingle) return math.max(bar, (end / bar).ceil() * bar).toDouble();
    // o clipe cobre os compassos do mapa a partir de [start] até o fim das notas
    final to = meter.ceilBarStart(start + end);
    return math.max(meter.barBeatsAt(start), to - start);
  }

  return [
    for (final t in data.tracks)
      (
        name: t.name,
        kind: t.drums ? TrackKind.drums : melodic,
        clip: MidiClip(id: newId(), name: t.name, start: start, length: lengthFor(t.endBeat), notes: t.notes, controls: t.controls),
      ),
  ];
}
