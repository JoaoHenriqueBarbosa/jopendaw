/// Congelar faixa e converter em áudio: as regras puras (quem pode, o que o motor vê), sem controlador.
///
/// Congelar renderiza a faixa (clipes, instrumento, efeitos e a automação deles, sem fader, pan, mudo
/// nem master) pelo mesmo render fora de tempo real da exportação e guarda o resultado como áudio
/// (sha-256, como uma importação). A faixa passa a tocar esse áudio no lugar do conteúdo, que fica no
/// documento intacto para o "Descongelar". Converter em áudio é a versão sem volta (ainda desfazível)
/// que troca o conteúdo pelo clipe de áudio.
///
/// Decisões:
/// * Barramento não congela (só soa o que as outras faixas mandam, que seguem editáveis).
/// * Efeito com sidechain de OUTRA faixa impede congelar: o áudio ficaria preso ao que a faixa-chave
///   tocava no momento e envelheceria a cada edição dela. A pessoa tira a chave (ou converte a
///   faixa-chave antes) e congela.
/// * Envios, fader, pan, saída e a automação deles NÃO entram no áudio e seguem vivos na faixa
///   congelada: um envio para o reverb continua tendo o reverb do barramento, que não é da faixa.
/// * A faixa que serve de chave a outra continua servindo: a chave é o áudio dela depois dos inserts.
library;

import 'dart:convert';

import 'controller.dart' show DawController;
import 'effects.dart';
import 'instruments.dart';
import 'model.dart';

/// Margem de cauda padrão do congelamento (s): reverb e delay que passam do fim do último clipe.
const double kDefaultFreezeTail = 8;

/// A maior margem que se pode pedir (s).
const double kMaxFreezeTail = 60;

/// Margem pedida, limpa: número finito entre 0 e [kMaxFreezeTail].
double clampFreezeTail(double v) => v.isFinite ? v.clamp(0.0, kMaxFreezeTail).toDouble() : kDefaultFreezeTail;

/// O tipo da faixa como o motor a vê: congelada é de áudio (o instrumento fica calado).
TrackKind engineKindOf(DawTrack t) => t.frozen != null ? TrackKind.audio : t.kind;

/// As faixas como o motor as toca para as notas: a congelada vira uma de áudio vazia, na mesma posição
/// (o índice da faixa é o índice no motor). O que não muda é a mesma instância.
List<DawTrack> soundingTracks(List<DawTrack> tracks) => [for (final t in tracks) t.frozen == null ? t : DawTrack(id: t.id, name: t.name, color: t.color)];

/// O que faz a faixa soar diferente ao congelar: muda isto durante o render e o áudio já nasceu velho.
///
/// Entra também a automação e a modulação do instrumento e dos efeitos (elas mudam o áudio); as de volume, pan e
/// envio não (ficam fora do render e seguem vivas na faixa congelada).
String soundFingerprint(DawTrack t) {
  final j = t.toJson();
  bool shapes(AutoKind k) => k == AutoKind.instrument || k == AutoKind.effect;
  final lanes = [
    for (final l in t.lanes)
      if (shapes(l.target.kind))
        jsonEncode({
          'target': l.target.toJson(),
          'points': [for (final p in l.points) p.toJson()],
        }),
  ];
  final mods = [
    for (final m in t.modulation.sources)
      if (m.dests.any((d) => shapes(d.target.kind))) jsonEncode((m.copy()..dests.removeWhere((d) => !shapes(d.target.kind))).toJson()),
  ];
  return [
    for (final k in const ['kind', 'params', 'sample', 'zones', 'clips', 'midi', 'effects']) '$k=${j[k]}',
    'lanes=$lanes',
    'mods=$mods',
  ].join('|');
}

/// Id do parâmetro de sidechain do efeito, se ele tem.
int? sidechainParamOf(EffectKind k) => switch (k) {
  EffectKind.compressor => 10,
  EffectKind.gate => 6,
  _ => null,
};

/// A faixa não tem nada para soar (sem clipes, só clipes de notas vazios ou só clipes de áudio mudos: o mudo
/// de clipe não vai ao motor, então o render sairia em silêncio).
bool trackHasNothing(DawTrack t) => t.kind.isInstrument ? t.midi.every((m) => m.notes.isEmpty) : t.clips.every((c) => c.muted);

/// A faixa de áudio tem clipes, mas todos mudos.
bool trackOnlyMutedClips(DawTrack t) => !t.kind.isInstrument && t.clips.isNotEmpty && t.clips.every((c) => c.muted);

/// O efeito da faixa que usa o sidechain de outra faixa (o primeiro), ou null.
({EffectSlot slot, int source})? foreignSidechain(DawDoc d, int track) {
  for (final s in d.tracks[track].effects) {
    final id = sidechainParamOf(s.kind);
    if (id == null) continue;
    final source = s.param(id).round();
    if (source >= 0 && source != track) return (slot: s, source: source);
  }
  return null;
}

/// Por que a faixa não pode ser congelada ou convertida agora (null: pode). [needsRender] falso é a
/// conversão de uma faixa já congelada, que reaproveita o áudio e não precisa de conteúdo nem de chave.
/// [verb] é a ação nas mensagens ("congelar", "converter", "renderizar"). [allowBus]: o render em faixa nova do
/// controlador aceita barramento (soa a mixagem que ele recebe); congelar e converter, não.
String? freezeBlocker(DawController c, int track, {bool needsRender = true, String verb = 'congelar', bool allowBus = false}) {
  final d = c.doc;
  if (track < 0 || track >= d.tracks.length) return 'A faixa não existe';
  final t = d.tracks[track];
  if (t.kind == TrackKind.bus && !allowBus) return 'Barramento não tem som próprio';
  if (c.recording) return 'Pare a gravação antes';
  if (!needsRender) return null;
  if (t.frozen != null) return 'A faixa já está congelada';
  if (trackOnlyMutedClips(t)) return 'A faixa só tem clipes mudos';
  if (t.kind != TrackKind.bus && trackHasNothing(t)) return 'A faixa está vazia';
  final sc = foreignSidechain(d, track);
  if (sc != null) {
    final from = sc.source < d.tracks.length ? '"${d.tracks[sc.source].name}"' : 'outra faixa';
    return 'Um efeito usa o sidechain de $from: tire a chave antes de $verb';
  }
  return null;
}
