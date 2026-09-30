/// As operações de edição da modulação sobre o controlador: atribuir um controle a um modulador
/// (o "Modular…" do menu de contexto), criar e apagar moduladores e destinos, aplicar os presets.
/// Cada operação é um passo só do histórico (desfaz e refaz como qualquer edição).
library;

import 'controller.dart';
import 'modulation.dart';
import 'model.dart';

/// O rótulo do alvo para as listas, como o menu de automação o mostra ("Volume", "Corte"…);
/// [fallback] se o alvo não existe mais.
String modTargetLabel(DawController c, int track, AutoTarget target, {String fallback = 'Destino removido'}) {
  for (final (t, label) in c.automatable(track)) {
    if (t == target) return label;
  }
  return fallback;
}

extension ModulationOps on DawController {
  /// A modulação da faixa, sempre uma (vazia se a faixa não existe).
  TrackModulation modulation(int track) => modulationOf(track) ?? TrackModulation();

  /// O alvo se modula (existe e não é uma lista de opções nem um inteiro)?
  bool canModulate(int track, AutoTarget target) {
    final info = autoInfo(track, target);
    return info != null && !info.stepped;
  }

  /// O intervalo, em fração do curso do controle, em que o valor efetivo do alvo se move em volta
  /// da base (null sem modulação): para o anel do knob.
  (double, double)? modRangeOf(int track, AutoTarget target) => modulationOf(track)?.deltaRange(target);

  /// Cria um modulador do tipo [kind] na faixa (sem destino). Null se a faixa já tem
  /// [maxModSources].
  ModSource? modAddSource(int track, ModKind kind) {
    final m = modulationOf(track);
    if (m == null || m.sources.length >= maxModSources) return null;
    final s = ModSource(id: newId(), kind: kind);
    edit((_) => m.sources.add(s));
    return s;
  }

  /// Tira o modulador e os destinos dele.
  void modRemoveSource(int track, String id) {
    final m = modulationOf(track);
    if (m == null || m.byId(id) == null) return;
    edit((_) => m.sources.removeWhere((s) => s.id == id));
  }

  /// Tira o destino [index] do modulador.
  void modRemoveDest(int track, String id, int index) {
    final s = modulationOf(track)?.byId(id);
    if (s == null || index < 0 || index >= s.dests.length) return;
    edit((_) => s.dests.removeAt(index));
  }

  /// Liga o alvo a um modulador com a quantidade padrão (25%): o [sourceId] dado ou, sem ele, um
  /// modulador novo de [kind]. Devolve o motivo da recusa (para mostrar no lugar), ou null se
  /// deu certo (também quando o modulador já modulava o alvo: nada muda).
  String? modAssign(int track, AutoTarget target, {String? sourceId, ModKind kind = ModKind.lfo, double amount = defaultModAmount}) {
    final m = modulationOf(track);
    if (m == null) return 'Esta faixa não existe.';
    if (!canModulate(track, target)) return 'Este controle não pode ser modulado.';
    var src = sourceId == null ? null : m.byId(sourceId);
    if (sourceId != null && src == null) return 'O modulador não existe mais.';
    if (src != null && src.dests.any((d) => d.target == target)) return null;
    if (src != null && src.dests.length >= maxModDests) return 'Cada modulador tem no máximo $maxModDests destinos.';
    if (src == null && m.sources.length >= maxModSources) return 'A faixa já tem $maxModSources moduladores.';
    edit((_) {
      final s = src ??= ModSource(id: newId(), kind: kind);
      if (!m.sources.contains(s)) m.sources.add(s);
      s.dests.add(ModDest(target, amount: amount.clamp(-1.0, 1.0)));
    });
    return null;
  }

  /// Aplica um preset de fábrica: cria o modulador já com o destino que o preset acha na faixa.
  /// Devolve o motivo da recusa (a faixa não tem o alvo, ou não cabe outro modulador), ou null.
  String? modApplyPreset(int track, ModPreset preset) {
    final m = modulationOf(track);
    if (m == null) return 'Esta faixa não existe.';
    if (m.sources.length >= maxModSources) return 'A faixa já tem $maxModSources moduladores.';
    final view = ModTrackView(track >= 0 ? doc.tracks[track] : null, effectsOf(track));
    final found = preset.target(view);
    if (found == null) return '${preset.name}: esta faixa não tem o controle que o preset move.';
    final (target, amount) = found;
    if (!canModulate(track, target)) return '${preset.name}: esta faixa não tem o controle que o preset move.';
    edit((_) {
      final s = preset.build(newId());
      s.dests.add(ModDest(target, amount: amount));
      m.sources.add(s);
    });
    return null;
  }
}
