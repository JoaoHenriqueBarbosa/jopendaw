/// Pastas de faixa (grupos): organizam faixas em pastas recolhíveis com um barramento de grupo.
///
/// Modelo: a pasta é uma faixa `TrackKind.bus` com `isGroup`, e as filhas vêm logo abaixo dela na
/// lista, com `groupId` igual ao id da pasta e a saída (`output`) apontando para ela. Para o motor a
/// pasta é um barramento comum: o fader dela controla todas as filhas, um efeito nela vale para
/// todas, e as filhas seguem podendo ter envios para outros barramentos. Não existe tipo novo de
/// motor (o índice de `TrackKind` é o código do motor).
///
/// Invariantes (mantidas por tudo o que mexe na lista): as filhas são contíguas e ficam logo depois
/// da pasta; pasta não entra em pasta (esta versão) e barramento de retorno nunca é filho.
///
/// Mudo e solo da pasta são os do barramento. O mudo cala tudo o que passa por ele. O solo é o do
/// motor (`solo()`): solo na pasta deixa audível a pasta e tudo o que sai nela (todas as filhas) e
/// o que ela alimenta; solo numa filha deixa audível só ela e a pasta (o resto da pasta cala).
library;

import 'controller.dart';
import 'instruments.dart';
import 'model.dart';

extension DawGroups on DawDoc {
  /// Há alguma pasta no documento.
  bool get hasGroups => tracks.any((t) => t.isGroup);

  /// Índice da pasta da faixa [i], ou −1 (fora de pasta, ou a própria faixa é a pasta).
  int folderOf(int i) {
    final g = tracks[i].groupId;
    if (g == null) return -1;
    return tracks.indexWhere((t) => t.isGroup && t.id == g);
  }

  /// Índices das filhas da pasta [folder] (na ordem da lista).
  List<int> membersOf(int folder) {
    final id = tracks[folder].id;
    return [
      for (var i = 0; i < tracks.length; i++)
        if (i != folder && tracks[i].groupId == id) i,
    ];
  }

  /// A faixa [i] some da linha do tempo: é filha de uma pasta recolhida.
  bool hiddenByGroup(int i) {
    final f = folderOf(i);
    return f >= 0 && tracks[f].collapsed;
  }

  /// Quantas faixas há dentro da pasta.
  int groupSize(int folder) => membersOf(folder).length;
}

/// Uma faixa entra em pasta: áudio ou instrumento (barramento, inclusive pasta, não).
bool canJoinGroup(DawTrack t) => !t.isGroup && t.kind != TrackKind.bus;

/// O que mudar numa faixa depois de um movimento: a pasta nova (ou nenhuma) e a saída.
class GroupChange {
  final DawTrack track;
  final String? groupId;
  final String? output;

  /// Frase para o aviso de rota (vazia quando a saída não muda de um destino que já existia).
  final String? warning;
  const GroupChange(this.track, this.groupId, this.output, this.warning);

  void apply() {
    track.groupId = groupId;
    track.output = output;
  }
}

/// O resultado de mover uma faixa (ou uma pasta com as filhas) na lista.
class TrackMovePlan {
  final List<DawTrack> order;
  final List<GroupChange> changes;
  const TrackMovePlan(this.order, this.changes);

  void applyGroups() {
    for (final c in changes) {
      c.apply();
    }
  }
}

/// Onde a posição [at] de [rest] cai: o índice da pasta cujo bloco a contém (logo abaixo do
/// cabeçalho ou entre duas filhas), ou −1. Logo depois da última filha já é fora.
int _insideGroup(List<DawTrack> rest, int at) {
  if (at <= 0 || at > rest.length) return -1;
  final above = rest[at - 1];
  final gid = above.isGroup ? above.id : above.groupId;
  if (gid == null) return -1;
  final fi = rest.indexWhere((t) => t.isGroup && t.id == gid);
  if (fi < 0) return -1;
  if (above.isGroup) return fi;
  return at < rest.length && rest[at].groupId == gid ? fi : -1;
}

/// Fim (exclusivo) do bloco da pasta [fi] em [rest].
int _blockEnd(List<DawTrack> rest, int fi) {
  var e = fi + 1;
  while (e < rest.length && rest[e].groupId == rest[fi].id) {
    e++;
  }
  return e;
}

/// Planeja mover a faixa [from] para a posição [to] (a de depois do movimento, como
/// `List.insert`). Regras:
///
/// * mover uma pasta leva as filhas junto (o bloco inteiro), e ela nunca cai dentro de outra pasta:
///   se cair, o bloco pula para fora dela;
/// * uma faixa que cai dentro de uma pasta (logo abaixo do cabeçalho ou entre duas filhas) entra
///   nela (a saída passa a ser a pasta); saindo do bloco, deixa a pasta (a saída volta ao master
///   se era a pasta);
/// * pasta recolhida não recebe faixa por arraste: a faixa pula para depois do bloco (descendo) ou
///   para antes da pasta (subindo), para "Mover para baixo" não esconder a faixa sem querer;
/// * barramento de retorno também pula para fora de qualquer pasta.
///
/// Devolve null quando nada muda.
TrackMovePlan? planTrackMove(List<DawTrack> tracks, int from, int to) {
  final n = tracks.length;
  if (from < 0 || from >= n) return null;
  final moved = tracks[from];
  var end = from + 1;
  if (moved.isGroup) {
    while (end < n && tracks[end].groupId == moved.id) {
      end++;
    }
  }
  final block = tracks.sublist(from, end);
  to = to.clamp(0, n - block.length);
  if (to == from) return null;
  final rest = [...tracks.sublist(0, from), ...tracks.sublist(end)];
  var at = to;
  final gi = _insideGroup(rest, at);
  String? group;
  String? output = moved.output;
  String? warning;
  if (!moved.isGroup) {
    group = null;
    if (gi >= 0) {
      final folder = rest[gi];
      if (canJoinGroup(moved) && !folder.collapsed) {
        group = folder.id;
      } else {
        at = to > from ? _blockEnd(rest, gi) : gi;
      }
    }
  } else if (gi >= 0) {
    at = to > from ? _blockEnd(rest, gi) : gi;
  }
  final order = [...rest.sublist(0, at), ...block, ...rest.sublist(at)];
  final changes = <GroupChange>[];
  if (!moved.isGroup && group != moved.groupId) {
    String nameOf(String id) => tracks.firstWhere((t) => t.id == id).name;
    if (group != null) {
      output = group;
      if (moved.output != null && moved.output != group) {
        final was = tracks.where((t) => t.id == moved.output).firstOrNull;
        warning = 'a saída de "${moved.name}"${was == null ? '' : ' para "${was.name}"'} (passa a ir para a pasta "${nameOf(group)}")';
      }
    } else {
      final old = moved.groupId;
      if (old != null && moved.output == old) {
        output = null;
        warning = 'a saída de "${moved.name}" para a pasta "${nameOf(old)}" (volta ao master)';
      }
    }
    changes.add(GroupChange(moved, group, output, warning));
  }
  var same = order.length == tracks.length;
  for (var i = 0; same && i < order.length; i++) {
    same = identical(order[i], tracks[i]);
  }
  return same && changes.isEmpty ? null : TrackMovePlan(order, changes);
}

/// Resultado de [DawGroupsController.groupTracks].
typedef GroupResult = ({DawTrack? folder, String? error});

/// O que aconteceu com o barramento da pasta ao desagrupar.
enum UngroupResult {
  /// Nada a fazer (a pasta não existe).
  none,

  /// A pasta estava vazia de efeitos, automação e rotas: o barramento foi apagado.
  removed,

  /// O barramento tinha efeitos, automação ou recebia de outras faixas: ficou como barramento comum.
  keptAsBus,
}

/// As operações de pasta do controlador. Cada uma é uma edição só no desfazer.
extension DawGroupsController on DawController {
  /// Texto de por que a faixa [t] não entra em pasta (null quando entra).
  String? whyNotGroupable(DawTrack t) {
    if (t.isGroup) return 'Não há pasta dentro de pasta nesta versão: "${t.name}" é uma pasta.';
    if (t.kind == TrackKind.bus) return 'Só faixas de áudio e de instrumento entram numa pasta: "${t.name}" é um barramento.';
    final f = t.groupId == null ? null : doc.tracks.where((x) => x.isGroup && x.id == t.groupId).firstOrNull;
    if (f != null) return '"${t.name}" já está na pasta "${f.name}". Tire-a de lá antes.';
    return null;
  }

  /// Nome livre para uma pasta nova: "Pasta N".
  String nextGroupName() {
    final names = {for (final t in doc.tracks) t.name};
    var k = doc.tracks.where((t) => t.isGroup).length + 1;
    while (names.contains('Pasta $k')) {
      k++;
    }
    return 'Pasta $k';
  }

  /// Agrupa as faixas [ids] numa pasta nova [name] (vazio: "Pasta N"). O barramento da pasta nasce
  /// no lugar da primeira faixa escolhida (na ordem da lista) e as outras vêm para baixo dele,
  /// contíguas, mesmo que estivessem espalhadas (as faixas que ficavam no meio descem para depois
  /// do bloco). A saída de cada filha passa a ser a pasta (envios ficam como estavam). Uma faixa só
  /// vale (pasta de uma faixa). Recusa, com o motivo, barramento, pasta e faixa que já está em pasta.
  GroupResult groupTracks(Iterable<String> ids, {String name = ''}) {
    final want = ids.toSet();
    if (want.isEmpty) return (folder: null, error: 'Escolha ao menos uma faixa para a pasta.');
    final picked = [
      for (final t in doc.tracks)
        if (want.contains(t.id)) t,
    ];
    if (picked.length != want.length) return (folder: null, error: 'Alguma faixa escolhida não existe mais.');
    for (final t in picked) {
      final why = whyNotGroupable(t);
      if (why != null) return (folder: null, error: why);
    }
    final label = name.trim().isEmpty ? nextGroupName() : name.trim();
    final folder = DawTrack(id: newId(), name: label, color: picked.first.color, kind: TrackKind.bus, isGroup: true);
    edit((d) {
      final order = <DawTrack>[];
      for (final t in d.tracks) {
        if (identical(t, picked.first)) {
          order
            ..add(folder)
            ..addAll(picked);
        }
        if (!want.contains(t.id)) order.add(t);
      }
      for (final t in picked) {
        t.groupId = folder.id;
        t.output = folder.id;
      }
      setTrackOrder(order);
      selectedTrack = order.indexOf(folder);
    });
    return (folder: folder, error: null);
  }

  /// Desfaz a pasta: as filhas ficam como faixas comuns (a saída que ia para a pasta volta ao
  /// master) e o barramento é apagado se não tem efeitos, automação nem rota de outras faixas; se
  /// tem, ele fica como barramento comum (nada do que o usuário montou nele se perde).
  UngroupResult ungroup(String folderId) {
    final fi = doc.tracks.indexWhere((t) => t.isGroup && t.id == folderId);
    if (fi < 0) return UngroupResult.none;
    final folder = doc.tracks[fi];
    final kept =
        folder.effects.isNotEmpty ||
        folder.lanes.any((l) => l.points.isNotEmpty) ||
        folder.sends.isNotEmpty ||
        doc.tracks.any((t) => t.groupId != folderId && (t.output == folderId || t.sends.any((s) => s.target == folderId)));
    edit((d) {
      for (final t in d.tracks) {
        if (t.groupId != folderId) continue;
        t.groupId = null;
        if (t.output == folderId) t.output = null;
      }
      if (kept) {
        folder
          ..isGroup = false
          ..collapsed = false;
      } else {
        setTrackOrder([
          for (final t in d.tracks)
            if (!identical(t, folder)) t,
        ]);
        selectedTrack = selectedTrack.clamp(0, d.tracks.length - 1);
      }
    });
    return kept ? UngroupResult.keptAsBus : UngroupResult.removed;
  }

  /// Tira a faixa da pasta: ela desce para logo depois do bloco e a saída volta ao master (se era
  /// a pasta).
  bool leaveGroup(String trackId) {
    final i = doc.tracks.indexWhere((t) => t.id == trackId);
    if (i < 0 || doc.folderOf(i) < 0) return false;
    final t = doc.tracks[i];
    final folder = doc.tracks[doc.folderOf(i)];
    edit((d) {
      final order = [...d.tracks]..remove(t);
      var end = order.indexOf(folder) + 1;
      while (end < order.length && order[end].groupId == folder.id) {
        end++;
      }
      order.insert(end, t);
      t.groupId = null;
      if (t.output == folder.id) t.output = null;
      setTrackOrder(order);
    });
    return true;
  }

  /// Coloca a faixa no fim da pasta [folderId] (a saída passa a ser a pasta); uma faixa que estava
  /// em outra pasta sai dela. Recusa (false) barramento, pasta e faixa que já está nesta pasta. Vale
  /// também para pasta recolhida.
  bool joinGroup(String trackId, String folderId) {
    final i = doc.tracks.indexWhere((t) => t.id == trackId);
    final fi = doc.tracks.indexWhere((t) => t.isGroup && t.id == folderId);
    if (i < 0 || fi < 0 || !canJoinGroup(doc.tracks[i]) || doc.tracks[i].groupId == folderId) return false;
    final t = doc.tracks[i];
    final folder = doc.tracks[fi];
    edit((d) {
      final order = [...d.tracks]..remove(t);
      final f = order.indexOf(folder);
      var end = f + 1;
      while (end < order.length && order[end].groupId == folder.id) {
        end++;
      }
      order.insert(end, t);
      t
        ..groupId = folder.id
        ..output = folder.id;
      setTrackOrder(order);
    });
    return true;
  }

  /// Recolhe ou expande a pasta. É estado de arranjo: não entra no desfazer (e o desfazer o
  /// preserva), mas vai salvo no documento.
  void setGroupCollapsed(String folderId, bool collapsed) {
    final t = doc.tracks.where((x) => x.isGroup && x.id == folderId).firstOrNull;
    if (t == null || t.collapsed == collapsed) return;
    mutate((_) => t.collapsed = collapsed);
    // a faixa selecionada ficou escondida: a seleção passa para a pasta
    final sel = selectedTrack;
    if (collapsed && sel >= 0 && sel < doc.tracks.length && doc.hiddenByGroup(sel)) selectTrack(doc.folderOf(sel));
  }

  /// Recolhe (ou expande) todas as pastas.
  void setAllGroupsCollapsed(bool collapsed) {
    for (final t in doc.tracks.where((t) => t.isGroup).toList()) {
      setGroupCollapsed(t.id, collapsed);
    }
  }
}
