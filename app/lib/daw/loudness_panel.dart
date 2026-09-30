/// Leitura de loudness do master: momentâneo (M, 400 ms), curto prazo (S, 3 s) e integrado (I) em
/// LUFS, e o true peak (TP) máximo em dBTP, com um botão para zerar o que foi medido. O true peak
/// acima do teto de [kTruePeakAlert] (−1 dBTP) acende em alerta: passar dele estoura nos codecs de
/// streaming. Cabe no canal do master (92 px de largura, em duas linhas) e, com mais largura, abre
/// numa linha só.
library;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../audio/engine_types.dart';
import '../widgets/theme.dart';
import 'loudness.dart';

/// True peak acima disto (dBTP) é alerta.
const double kTruePeakAlert = -1;

/// O true peak passou do teto de alerta.
bool truePeakAlert(double dbtp) => LoudnessReading.has(dbtp) && dbtp > kTruePeakAlert;

class LoudnessPanel extends StatelessWidget {
  final ValueListenable<LoudnessReading> reading;

  /// Zera a medida integrada (e a faixa, os máximos e o true peak).
  final VoidCallback onReset;

  const LoudnessPanel({super.key, required this.reading, required this.onReset});

  static const _tip =
      'Loudness do master (EBU R128)\n'
      'M: momentâneo, últimos 400 ms · S: curto prazo, 3 s · I: integrado desde que zerou · TP: true peak máximo.\n'
      'O true peak acima de −1 dBTP fica vermelho: pode estourar no MP3 e no streaming.';

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).textTheme.labelSmall!.copyWith(fontSize: 10, height: 1.25, fontFeatures: const [FontFeature.tabularFigures()]);
    return ValueListenableBuilder<LoudnessReading>(
      valueListenable: reading,
      builder: (context, r, _) {
        final alert = truePeakAlert(r.truePeak);
        Widget cell(String label, double v, {bool bold = false, Color? color}) => Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '$label ',
                style: const TextStyle(color: Colors.white54),
              ),
              TextSpan(
                text: formatLufs(v),
                style: TextStyle(color: color ?? Colors.white, fontWeight: bold ? FontWeight.w700 : null),
              ),
            ],
          ),
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.clip,
          style: base,
        );
        // duas colunas iguais: o texto encolhe em vez de estourar quando não cabe
        Widget fit(Widget w, Alignment align) => Expanded(
          child: FittedBox(fit: BoxFit.scaleDown, alignment: align, child: w),
        );
        final tp = cell('TP', r.truePeak, bold: alert, color: alert ? Palette.danger : null);
        final reset = Tooltip(
          message: 'Zerar a medida de loudness',
          waitDuration: const Duration(milliseconds: 500),
          child: InkWell(
            onTap: onReset,
            borderRadius: BorderRadius.circular(4),
            child: Semantics(
              button: true,
              label: 'Zerar a medida de loudness',
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text('Zerar', style: base.copyWith(color: Palette.accent)),
              ),
            ),
          ),
        );
        return Tooltip(
          message: _tip,
          waitDuration: const Duration(milliseconds: 800),
          child: LayoutBuilder(
            builder: (context, box) {
              final wide = box.maxWidth >= 250;
              if (wide) {
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    cell('M', r.momentary),
                    const SizedBox(width: 10),
                    cell('S', r.shortTerm),
                    const SizedBox(width: 10),
                    cell('I', r.integrated, bold: true),
                    const SizedBox(width: 10),
                    tp,
                    const SizedBox(width: 6),
                    reset,
                  ],
                );
              }
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [fit(cell('M', r.momentary), Alignment.centerLeft), fit(cell('S', r.shortTerm), Alignment.centerRight)]),
                  Row(children: [fit(cell('I', r.integrated, bold: true), Alignment.centerLeft), fit(tp, Alignment.centerRight)]),
                  Align(alignment: Alignment.centerRight, child: reset),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

/// As escolhas da normalização de loudness na exportação: o liga/desliga, o alvo (streaming,
/// podcast, broadcast ou um valor livre), o teto de true peak e, havendo stems, se eles levam o
/// mesmo ganho da mixagem. Só desenha: quem guarda os valores é a janela de exportação.
class LoudnessNormalizeOptions extends StatelessWidget {
  final bool enabled;
  final LoudnessTarget target;
  final double customLufs;
  final double ceiling;
  final bool hasStems;
  final bool normalizeStems;
  final ValueChanged<bool> onEnabled;
  final ValueChanged<LoudnessTarget> onTarget;
  final ValueChanged<double> onCustom;
  final ValueChanged<double> onCeiling;
  final ValueChanged<bool> onNormalizeStems;

  const LoudnessNormalizeOptions({
    super.key,
    required this.enabled,
    required this.target,
    required this.customLufs,
    required this.ceiling,
    required this.hasStems,
    required this.normalizeStems,
    required this.onEnabled,
    required this.onTarget,
    required this.onCustom,
    required this.onCeiling,
    required this.onNormalizeStems,
  });

  /// O alvo em LUFS que vale com as escolhas de agora.
  double get lufs => target == LoudnessTarget.custom ? customLufs : target.lufs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall!.copyWith(color: theme.colorScheme.onSurfaceVariant);
    const tabular = TextStyle(fontFeatures: [FontFeature.tabularFigures()]);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Normalizar o loudness'),
          subtitle: const Text('Leva a mixagem inteira ao volume percebido do alvo (LUFS), sem passar do teto de pico'),
          value: enabled,
          onChanged: onEnabled,
        ),
        if (enabled) ...[
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in LoudnessTarget.values)
                ChoiceChip(
                  label: Text(t == LoudnessTarget.custom ? t.label : '${t.label} ${formatLufs(t.lufs)}'),
                  selected: target == t,
                  onSelected: (_) => onTarget(t),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(target == LoudnessTarget.custom ? 'Alvo de ${formatLufs(customLufs)} LUFS integrado.' : '${target.hint}.', style: muted),
          if (target == LoudnessTarget.custom) ...[
            Row(
              children: [
                Expanded(child: Text('Alvo', style: theme.textTheme.bodyLarge)),
                Text('${formatLufs(customLufs)} LUFS', style: tabular),
              ],
            ),
            Slider(
              value: customLufs.clamp(kMinTargetLufs, kMaxTargetLufs).toDouble(),
              min: kMinTargetLufs,
              max: kMaxTargetLufs,
              divisions: ((kMaxTargetLufs - kMinTargetLufs) * 2).round(),
              label: '${formatLufs(customLufs)} LUFS',
              onChanged: onCustom,
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: Text('Teto de true peak', style: theme.textTheme.bodyLarge)),
              Text(formatDbtp(ceiling), style: tabular),
            ],
          ),
          Slider(
            value: ceiling.clamp(kMinCeiling, kMaxCeiling).toDouble(),
            min: kMinCeiling,
            max: kMaxCeiling,
            divisions: ((kMaxCeiling - kMinCeiling) * 2).round(),
            label: formatDbtp(ceiling),
            onChanged: onCeiling,
          ),
          Text('Se subir até o alvo passaria do teto, o ganho para no teto e o volume fica abaixo do alvo: a janela do resultado avisa.', style: muted),
          if (hasStems)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Stems com o mesmo ganho'),
              subtitle: const Text('Sem isto os stems saem como renderizados, sem normalização'),
              value: normalizeStems,
              onChanged: onNormalizeStems,
            ),
        ],
      ],
    );
  }
}
