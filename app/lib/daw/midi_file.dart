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
import 'model.dart';

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

/// Um ponto do mapa de andamento do arquivo: a batida (semínimas) e o BPM dali em diante.
///
/// GANCHO do mapa de andamento: hoje o app usa só o primeiro ponto (`DawController.importMidiBytes`
/// em `controller.dart`, que chama `applyImportedTempo`); quando o documento tiver mapa de
/// andamento, é lá que se passa a lista inteira ([MidiFileData.tempoMap]) em vez do primeiro BPM.
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

  /// Avisos para a pessoa (arquivo cortado, notas presas, peças de bateria que não existem…).
  final List<String> warnings;

  MidiFileData({required this.format, required this.ppq, required this.tracks, required this.tempoMap, required this.beatsPerBar, required this.warnings});

  int get noteCount => tracks.fold(0, (a, t) => a + t.notes.length);

  /// O primeiro andamento (BPM real, sem arredondar), ou null.
  double? get firstBpm => tempoMap.isEmpty ? null : tempoMap.first.bpm;

  /// O andamento muda no meio do arquivo.
  bool get hasTempoChanges => tempoMap.any((p) => (p.bpm - tempoMap.first.bpm).abs() > 0.5);
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
  if (sigs.isNotEmpty) {
    final (_, nn, dd) = sigs.first;
    var den = 1;
    for (var i = 0; i < math.min(dd, 6); i++) {
      den *= 2;
    }
    if (nn > 0) {
      final exact = nn * 4 / den;
      bpb = exact.round().clamp(1, 12);
      if (exact != bpb) warnings.add('O compasso $nn/$den foi aproximado para $bpb/4, o mais próximo que o app tem.');
    }
    if (sigs.any((s) => s.$2 != nn || s.$3 != dd)) warnings.add('O arquivo muda de compasso no meio: o app usa só o primeiro ($nn/$den).');
  }
  return MidiFileData(format: format, ppq: ppq, tracks: tracks, tempoMap: tempoMap, beatsPerBar: bpb, warnings: warnings);
}

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
  _OutTrack(this.name, this.channel, this.clips, this.offset);
}

/// O arquivo pronto e o que entrou nele.
class MidiExport {
  final Uint8List bytes;
  final int tracks, notes;

  /// Notas que ficaram de fora (fora de 0–127 ou fora do trecho do clipe).
  final int skipped;
  const MidiExport(this.bytes, this.tracks, this.notes, this.skipped);
}

/// Faixas do documento que têm notas ou controles, na ordem da mesa.
List<DawTrack> exportableTracks(DawDoc doc) => [
  for (final t in doc.tracks)
    if (t.kind.isInstrument && t.midi.any((c) => c.notes.isNotEmpty || c.controls.isNotEmpty)) t,
];

/// Monta o .mid (tipo 1, 480 PPQ): uma trilha de andamento e compasso e uma por faixa, cada uma no
/// seu canal (bateria no 10). Com [only] escreve só esse clipe, movido para o começo do arquivo;
/// sem ele, todas as [exportableTracks] na posição em que estão. Notas fora de 0–127, fora do
/// trecho do clipe ou com valores inválidos ficam de fora ([MidiExport.skipped]). Lança
/// [MidiFormatException] se não há nada para escrever.
MidiExport buildMidiFile(DawDoc doc, {MidiClip? only, DawTrack? onlyTrack, String title = ''}) {
  final outs = <_OutTrack>[];
  if (only != null) {
    final drums = onlyTrack?.kind == TrackKind.drums;
    outs.add(_OutTrack(only.name.isNotEmpty ? only.name : (onlyTrack?.name ?? ''), drums ? 9 : 0, [only], -only.start));
  } else {
    var k = 0;
    for (final t in exportableTracks(doc)) {
      final drums = t.kind == TrackKind.drums;
      var ch = 9;
      if (!drums) {
        ch = k % 15;
        if (ch >= 9) ch++;
        k++;
      }
      outs.add(_OutTrack(t.name, ch, t.midi, 0));
    }
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

  // trilha de andamento e compasso
  final head = <int>[];
  _meta(head, 0x03, utf8.encode(title));
  final us = (60000000 / (doc.bpm.isFinite && doc.bpm > 0 ? doc.bpm : 120)).round().clamp(1, 16777215);
  _meta(head, 0x51, [us ~/ 65536 % 256, us ~/ 256 % 256, us % 256]);
  _meta(head, 0x58, [doc.beatsPerBar.clamp(1, 255), 2, 24, 8]);
  _meta(head, 0x2F, const []);
  chunk(head);

  var notes = 0, skipped = 0;
  for (final o in outs) {
    // desligar vem antes de controlar, que vem antes de ligar, no mesmo instante
    final ev = <({int tick, int order, int seq, List<int> data})>[];
    var seq = 0;
    final ch = o.channel;
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
        if (!e.beat.isFinite || !e.value.isFinite || e.beat < 0 || e.beat > c.length) continue;
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
  return MidiExport(Uint8List.fromList(file), outs.length, notes, skipped);
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

/// O andamento como o app o guarda: BPM inteiro entre 20 e 400.
int appBpmFor(double bpm) => bpm.isFinite ? bpm.round().clamp(20, 400) : 120;

// ------------------------------------------------------------------ montar faixas para o documento

/// Uma faixa pronta para entrar no documento: o tipo (sintetizador ou bateria) e o clipe.
typedef MidiImportTrack = ({String name, TrackKind kind, MidiClip clip});

/// Transforma o que foi lido em faixas e clipes (um por faixa do arquivo, começando em [start]).
/// O tamanho de cada clipe fecha no compasso seguinte ao fim das notas.
List<MidiImportTrack> midiImportTracks(MidiFileData data, {required int beatsPerBar, double start = 0, required String Function() newId}) {
  final bar = beatsPerBar < 1 ? 4 : beatsPerBar;
  return [
    for (final t in data.tracks)
      (
        name: t.name,
        kind: t.drums ? TrackKind.drums : TrackKind.synth,
        clip: MidiClip(
          id: newId(),
          name: t.name,
          start: start,
          length: math.max(bar, (t.endBeat / bar).ceil() * bar).toDouble(),
          notes: t.notes,
          controls: t.controls,
        ),
      ),
  ];
}
