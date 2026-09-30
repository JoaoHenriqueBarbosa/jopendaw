/// Histórico de desfazer com nome: cada passo guarda o estado de antes (JSON do documento), o rótulo
/// da ação e a hora. A pilha mora no [DawController]; aqui ficam os tipos e a leitura que o painel
/// "Histórico" (`history_ui.dart`) usa.
library;

/// Quantos passos o desfazer guarda (os mais antigos saem primeiro).
const historyLimit = 200;

/// O nome de um passo sem rótulo.
const unlabeledStep = 'Edição';

/// Um passo do histórico. Na pilha de desfazer, [json] é o documento de ANTES da ação; na de refazer, o de DEPOIS.
/// Em ambas [label] é o nome da ação (o mesmo dos dois lados).
class HistoryEntry {
  final String json;
  final String? label;
  final DateTime time;
  const HistoryEntry(this.json, this.label, this.time);

  /// O nome para mostrar: o rótulo, ou "Edição" (o painel acrescenta a hora).
  String get title => labeled ? label!.trim() : unlabeledStep;

  bool get labeled => label != null && label!.trim().isNotEmpty;
}

/// Uma linha do painel: uma ação (do mais recente ao mais antigo) ou o início (sem edições).
class HistoryStep {
  /// Quantas ações já valem depois deste passo (0 é o início). Tocar nele leva o projeto a este estado.
  final int position;
  final String title;
  final bool labeled;
  final DateTime? time;

  /// O estado de agora.
  final bool current;

  /// Passo que foi desfeito e ainda dá para refazer.
  final bool future;
  final bool isStart;
  const HistoryStep({
    required this.position,
    required this.title,
    required this.labeled,
    required this.time,
    required this.current,
    required this.future,
    required this.isStart,
  });
}

/// As linhas do painel, do mais recente ao mais antigo: os passos desfeitos (refazer), os feitos e, por último, o início.
/// [undo] e [redo] são as pilhas do controlador (o último de cada uma é o mais perto do estado de agora).
List<HistoryStep> historySteps(List<HistoryEntry> undo, List<HistoryEntry> redo) {
  final total = undo.length + redo.length;
  final rows = <HistoryStep>[];
  for (var i = total - 1; i >= 0; i--) {
    final e = i < undo.length ? undo[i] : redo[redo.length - 1 - (i - undo.length)];
    rows.add(
      HistoryStep(position: i + 1, title: e.title, labeled: e.labeled, time: e.time, current: i + 1 == undo.length, future: i >= undo.length, isStart: false),
    );
  }
  rows.add(HistoryStep(position: 0, title: 'Início do histórico', labeled: true, time: null, current: undo.isEmpty, future: false, isStart: true));
  return rows;
}

/// "14:05" (hora local, dois dígitos).
String formatClock24(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// A linha de um passo: "Mover clipe" ou "Edição (14:05)" quando não tem rótulo.
String stepText(HistoryStep s) => s.labeled || s.time == null ? s.title : '${s.title} (${formatClock24(s.time!)})';

/// O texto de "Desfazer: …" / "Refazer: …" para o tooltip (sem passo: só a palavra).
String undoTooltip(String verb, HistoryEntry? next) => next == null ? verb : '$verb: ${next.title}';
