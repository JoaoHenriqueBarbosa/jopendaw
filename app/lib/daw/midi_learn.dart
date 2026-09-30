/// MIDI learn: mapeia os controles de um teclado ou controlador (CC, pitch bend, pressão do canal)
/// aos parâmetros do app (knobs de instrumento e de efeito, volume, pan e envios).
///
/// O mapa mora no documento ([DawDoc.midiMap], JSON `midi_map`), então viaja com o projeto, e a
/// conta é a da automação (`automation_math.dart`): o valor 0..1 do controlador anda na escala do
/// controle do alvo (curva do fader no volume, logarítmica em Hz e segundos, reta no pan) e o
/// setter que recebe é o mesmo dos gestos na tela, o que também grava automação quando o modo de
/// gravação está armado.
///
/// Sem `dart:io` e sem bit a bit acima de 32 bits: roda igual no dart2js.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../audio/engine.dart' show LocalStore;
import 'automation_record.dart' show AutoInfo, autoNorm;
import 'controller.dart';
import 'midi_map.dart';
import 'model.dart';

/// O valor do alvo para a posição 0..1 do controle, na escala dele (a mesma da raia de automação).
double midiTargetValue(AutoInfo info, double norm) {
  final n = norm.clamp(0.0, 1.0);
  final w = info.warp;
  final v = w != null ? w.fromNorm(n) : info.min + (info.max - info.min) * n;
  return v.isFinite ? v.clamp(info.min, info.max).toDouble() : info.fixed;
}

// ------------------------------------------------------------------------- motor do aprender

/// O alvo armado à espera do próximo controle do teclado.
typedef MidiArmed = ({int track, AutoTarget target});

/// Depois deste tempo sem mensagens o gesto do controlador acaba (solta a gravação de automação).
const midiIdleRelease = Duration(milliseconds: 700);

class MidiLearn extends ChangeNotifier {
  MidiLearn(this.c);
  final DawController c;

  /// Modo "Aprender MIDI" ligado (os controles ficam com contorno e clicar arma).
  bool learning = false;

  /// O controle armado ("mexa no controle do seu teclado"), ou null.
  MidiArmed? armed;

  /// O último mapeamento criado (a interface mostra o que foi aprendido).
  MidiMapping? lastLearned;

  final _pickups = <String, MidiPickup>{};
  final _runs = <String, ({Timer idle, int track, AutoTarget target})>{};
  var _seq = 0;
  bool _disposed = false;

  MidiMap get map => c.doc.midiMap;

  // ---- estado e consulta

  void setLearning(bool on) {
    if (learning == on && (on || armed == null)) return;
    learning = on;
    if (!on) {
      armed = null;
      lastLearned = null;
    }
    notifyListeners();
  }

  void toggle() => setLearning(!learning);

  /// Esc: desarma; sem nada armado, sai do modo.
  void escape() {
    if (armed != null) {
      armed = null;
      notifyListeners();
    } else {
      setLearning(false);
    }
  }

  String? _trackId(int track) => track < 0 ? null : (track < c.doc.tracks.length ? c.doc.tracks[track].id : null);

  /// Arma o controle: o próximo CC, pitch bend ou pressão vira o mapeamento dele. Liga o modo.
  /// Recusa (false) alvo que não existe.
  bool arm(int track, AutoTarget target) {
    if (c.autoInfo(track, target) == null) return false;
    learning = true;
    armed = (track: track, target: target);
    notifyListeners();
    return true;
  }

  void disarm() {
    if (armed == null) return;
    armed = null;
    notifyListeners();
  }

  MidiMapping? mappingFor(int track, AutoTarget target) {
    if (track >= c.doc.tracks.length) return null;
    final id = _trackId(track);
    if (track >= 0 && id == null) return null;
    for (final m in map.items) {
      if (m.sameTarget(id, target)) return m;
    }
    return null;
  }

  /// A faixa (índice; −1 = master) do mapeamento, ou null se a faixa foi apagada.
  int? trackOf(MidiMapping m) {
    if (m.trackId == null) return -1;
    final i = c.doc.tracks.indexWhere((t) => t.id == m.trackId);
    return i < 0 ? null : i;
  }

  /// O alvo existe (faixa, instrumento, efeito ou envio ainda estão no projeto).
  bool alive(MidiMapping m) {
    final t = trackOf(m);
    return t != null && c.autoInfo(t, m.target) != null;
  }

  /// "Faixa · Controle" para a lista, ou o texto de alvo removido.
  String targetLabel(MidiMapping m) {
    final t = trackOf(m);
    if (t == null) return 'Faixa removida';
    final name = c.targetName(t, m.target);
    if (name == null) return '${t < 0 ? 'Master' : c.doc.tracks[t].name} · alvo removido';
    return '${t < 0 ? 'Master' : c.doc.tracks[t].name} · $name';
  }

  // ---- edição do mapa (guardada no documento, salva junto)

  void _edit(void Function(MidiMap m) fn) {
    c.mutate((d) => fn(d.midiMap));
    notifyListeners();
  }

  String _newId() => 'mm${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${(_seq++).toRadixString(36)}';

  MidiMapping _learn(MidiSource src, int track, AutoTarget target) {
    final m = MidiMapping(id: _newId(), source: src, trackId: _trackId(track), target: target);
    // um controle tem uma origem só: aprender de novo substitui o mapeamento dele
    _edit((mm) {
      mm.items.removeWhere((x) => x.sameTarget(m.trackId, m.target));
      mm.items.add(m);
    });
    return m;
  }

  void remove(String id) {
    _cancelRun(id);
    _pickups.remove(id);
    _edit((mm) => mm.items.removeWhere((m) => m.id == id));
  }

  /// Tira o mapeamento do controle; false se não havia.
  bool removeFor(int track, AutoTarget target) {
    final m = mappingFor(track, target);
    if (m == null) return false;
    remove(m.id);
    return true;
  }

  void clear() {
    for (final id in _runs.keys.toList()) {
      _cancelRun(id);
    }
    _pickups.clear();
    _edit((mm) => mm.items.clear());
  }

  /// Muda o que o painel edita: faixa min/max, curva e inversão.
  void update(String id, {double? min, double? max, MidiCurve? curve, bool? inverted}) {
    final m = map.items.where((x) => x.id == id).firstOrNull;
    if (m == null) return;
    _edit((_) {
      if (min != null) m.min = min.clamp(0.0, 1.0);
      if (max != null) m.max = max.clamp(0.0, 1.0);
      if (curve != null) m.curve = curve;
      if (inverted != null) m.inverted = inverted;
    });
    _pickups[id]?.picked = false;
  }

  void setSoft(bool v) {
    if (map.soft == v) return;
    _edit((mm) => mm.soft = v);
  }

  // ---- entrada MIDI

  /// Trata uma mensagem MIDI; true = foi consumida (aprendeu um mapeamento ou moveu um alvo) e
  /// não deve virar expressão do instrumento. Só CC (0..119), pitch bend e pressão do canal
  /// participam: notas passam, e os CC 120..127 (panic, reset, all notes off) nunca são mapeados
  /// nem consumidos.
  bool handle(int status, int d1, int d2) {
    final type = status & 0xF0;
    final MidiSourceKind kind;
    switch (type) {
      case 0xB0:
        if ((d1 & 0x7F) >= 120) return false;
        kind = MidiSourceKind.cc;
      case 0xE0:
        kind = MidiSourceKind.bend;
      case 0xD0:
        kind = MidiSourceKind.pressure;
      default:
        return false;
    }
    final src = MidiSource(kind, status & 0x0F, kind == MidiSourceKind.cc ? d1 & 0x7F : 0);
    final raw = midiRaw(kind, d1, d2);
    final a = armed;
    if (a != null) {
      armed = null;
      if (c.autoInfo(a.track, a.target) == null) {
        notifyListeners();
        return false;
      }
      final m = _learn(src, a.track, a.target);
      lastLearned = m;
      // o valor de agora é a posição de partida do takeover: só assume ao cruzar o valor do controle
      _pickups[m.id] = MidiPickup()..lastIn = midiMappingNorm(m, raw);
      notifyListeners();
      return true;
    }
    var used = false;
    // uma cópia da lista: mudar o valor pode mexer no documento
    for (final m in map.items.toList()) {
      if (m.source != src) continue;
      // o mapeamento consome a mensagem mesmo quando o alvo sumiu ou o takeover a segura: o
      // controlador mapeado não vira expressão às escondidas
      used = true;
      _drive(m, raw);
    }
    return used;
  }

  void _drive(MidiMapping m, double raw) {
    final track = trackOf(m);
    if (track == null) return;
    final info = c.autoInfo(track, m.target);
    if (info == null) return;
    final incoming = midiMappingNorm(m, raw);
    if (!incoming.isFinite) return;
    final pick = _pickups.putIfAbsent(m.id, MidiPickup.new);
    if (map.soft && !pick.accept(incoming, autoNorm(info.fixed, info), m.min, m.max)) return;
    pick.picked = true;
    final v = midiTargetValue(info, incoming);
    if (v == info.fixed) {
      pick.lastOut = autoNorm(info.fixed, info);
      _keepRun(m.id, track, m.target);
      return;
    }
    if (!_runs.containsKey(m.id)) {
      // começo do gesto: como o knob, anuncia à gravação de automação antes do ponto de desfazer
      c.autoRec.touch(track, m.target);
      c.checkpoint();
    }
    _keepRun(m.id, track, m.target);
    _set(track, m.target, v);
    final after = c.autoInfo(track, m.target);
    pick.lastOut = after == null ? incoming : autoNorm(after.fixed, after);
  }

  void _keepRun(String id, int track, AutoTarget target) {
    _runs[id]?.idle.cancel();
    _runs[id] = (idle: Timer(midiIdleRelease, () => _endRun(id)), track: track, target: target);
  }

  void _endRun(String id) {
    final r = _runs.remove(id);
    if (r == null || _disposed) return;
    c.autoRec.release(r.track, r.target);
  }

  void _cancelRun(String id) {
    final r = _runs.remove(id);
    if (r == null) return;
    r.idle.cancel();
    c.autoRec.release(r.track, r.target);
  }

  /// Aplica o valor pelo mesmo caminho dos gestos na tela (setters que alimentam a automação).
  void _set(int track, AutoTarget target, double v) {
    switch (target.kind) {
      case AutoKind.volume:
        c.autoRec.value(track, target, v);
        c.mutate((d) => track < 0 ? d.masterGain = v : d.tracks[track].gain = v);
      case AutoKind.pan:
        c.autoRec.value(track, target, v);
        c.mutate((d) => track < 0 ? d.masterPan = v : d.tracks[track].pan = v);
      case AutoKind.instrument:
        c.setParam(track, target.param, v);
      case AutoKind.effect:
        c.setEffectParam(track, target.ref ?? '', target.param, v);
      case AutoKind.send:
        c.setSend(track, target.ref ?? '', level: v);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    for (final r in _runs.values) {
      r.idle.cancel();
    }
    _runs.clear();
    super.dispose();
  }

  @visibleForTesting
  int get openRuns => _runs.length;
}

// ------------------------------------------------------------------------- padrão para novos projetos

/// Chave do guardado local do mapa padrão.
const midiDefaultKey = 'midimap:default';

/// O que o padrão leva: volume e pan (do master e das faixas), e parâmetros de instrumento; as
/// faixas vão pela POSIÇÃO (as de um projeto novo têm outros ids). Efeitos e envios ficam de fora:
/// dependem de ids que só existem no projeto onde foram criados.
Map<String, dynamic> midiDefaultToJson(MidiMap map, List<DawTrack> tracks) {
  final items = <Map<String, dynamic>>[];
  for (final m in map.items) {
    if (m.target.kind == AutoKind.effect || m.target.kind == AutoKind.send) continue;
    int? index;
    if (m.trackId != null) {
      index = tracks.indexWhere((t) => t.id == m.trackId);
      if (index < 0) continue;
    }
    items.add({...m.toJson()..remove('track'), 'index': index});
  }
  return {'soft': map.soft, 'items': items};
}

/// O mapa padrão aplicado às faixas de um projeto novo: cada mapeamento pega a faixa da mesma
/// posição; o que aponta para faixa que não existe é descartado.
MidiMap midiDefaultFrom(Object? json, List<DawTrack> tracks, String Function() newId) {
  if (json is! Map) return MidiMap();
  final out = MidiMap(soft: json['soft'] != false);
  final list = json['items'];
  if (list is! List) return out;
  for (final x in list) {
    if (x is! Map) continue;
    try {
      final j = x.cast<String, dynamic>();
      final idx = j['index'];
      String? trackId;
      if (idx is num) {
        final i = idx.toInt();
        if (i < 0 || i >= tracks.length) continue;
        trackId = tracks[i].id;
      }
      final m = MidiMapping.fromJson({...j, 'id': newId(), 'track': trackId});
      out.items.add(m);
    } on Object {
      continue;
    }
  }
  return out;
}

/// Guarda o mapa do projeto como padrão dos novos (só neste aparelho).
Future<void> saveMidiDefault(LocalStore store, MidiMap map, List<DawTrack> tracks) => store.put(midiDefaultKey, jsonEncode(midiDefaultToJson(map, tracks)));

Future<void> clearMidiDefault(LocalStore store) => store.delete(midiDefaultKey);

/// Lê o padrão guardado; vazio se não há ou se está corrompido.
Future<Object?> loadMidiDefault(LocalStore store) async {
  final v = await store.get(midiDefaultKey);
  if (v is! String) return null;
  try {
    return jsonDecode(v);
  } on FormatException {
    return null;
  }
}
