/// Configurações de gravação do projeto: de onde vem o áudio (a entrada), a compensação de
/// latência e a contagem. A entrada é do aparelho (fica no controlador); latência e contagem moram
/// no documento e valem para este projeto.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/feedback.dart';
import '../widgets/responsive_scaffold.dart';
import '../widgets/theme.dart';
import 'controller.dart';
import 'mixer_panel.dart' show InputLevelMeter;
import 'keymap.dart';
import 'model.dart';
import 'shortcuts_dialog.dart' show showShortcuts;
import 'transport_bar.dart' show describeActionError;

/// Curso do ajuste de latência (ms). Negativo cobre o navegador que informa latência a mais.
const minLatencyMs = -200.0, maxLatencyMs = 500.0;

/// Valor do item "padrão do sistema" na lista de entradas (ids de aparelho nunca são vazios).
const _systemDefault = '';

/// O id que o Chrome dá à entrada padrão do sistema: ela vira o item "padrão" em vez de aparecer
/// duas vezes.
const _browserDefault = 'default';

Future<void> showSettingsDialog(BuildContext context, DawController c) => showDialog<void>(
  context: context,
  builder: (_) => SettingsDialog(c: c),
);

class SettingsDialog extends StatefulWidget {
  final DawController c;
  const SettingsDialog({super.key, required this.c});

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  DawController get c => widget.c;

  /// Procurando as entradas (pede o microfone na primeira vez) e trocando de entrada.
  bool _loading = true, _switching = false;
  String? _error;

  /// O aviso do controlador de quando a janela abriu: um aviso novo dele (sem permissão do
  /// microfone, por exemplo) aparece aqui também, senão ficaria escondido atrás da janela.
  String? _errorAtOpen;

  late double _latency = c.doc.recLatencyMs.clamp(minLatencyMs, maxLatencyMs);
  late final _latencyText = TextEditingController(text: _ms(_latency));
  final _latencyFocus = FocusNode();
  String? _latencyError;

  static String _ms(double v) => '${v.round()}';

  /// A região de punch em compassos (ou o que fazer para ela existir).
  static String _punchText(DawDoc d) {
    final r = d.punchRegion;
    if (r == null) return 'Ligue para marcar a região na régua (arraste as pontas vermelhas)';
    return 'Da posição ${formatPosition(r.$1, d.beatsPerBar, meter: d.meter)} à ${formatPosition(r.$2, d.beatsPerBar, meter: d.meter)}: só isso é gravado';
  }

  @override
  void initState() {
    super.initState();
    _errorAtOpen = c.error;
    _latencyFocus.addListener(() {
      if (!_latencyFocus.hasFocus) _commitText();
    });
    // logo depois do initState: uma falha síncrona do controlador faria setState dentro dele
    scheduleMicrotask(_refresh);
  }

  @override
  void dispose() {
    _latencyText.dispose();
    _latencyFocus.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    String? error;
    try {
      await c.refreshInputDevices();
    } catch (e) {
      error = describeActionError(e);
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = error;
    });
  }

  Future<void> _choose(String? value) async {
    final id = value == null || value == _systemDefault ? null : value;
    if (id == c.inputDevice || _switching) return;
    setState(() {
      _switching = true;
      _error = null;
    });
    String? error;
    try {
      await c.setInputDevice(id);
    } catch (e) {
      error = describeActionError(e);
    }
    if (!mounted) return;
    setState(() {
      _switching = false;
      _error = error;
    });
  }

  void _setLatency(double v, {bool fromText = false}) {
    v = v.roundToDouble().clamp(minLatencyMs, maxLatencyMs);
    setState(() {
      _latency = v;
      _latencyError = null;
      if (!fromText) _latencyText.text = _ms(v);
    });
    // não entra no desfazer: é calibragem do aparelho, não edição da música
    c.setRecLatency(v);
  }

  /// Aplica o que foi digitado; devolve false (e mostra o motivo) quando não é um número no curso.
  bool _commitText() {
    if (!mounted) return false;
    final t = _latencyText.text.trim().replaceAll('−', '-');
    final v = double.tryParse(t.replaceAll(',', '.'));
    if (v == null || v < minLatencyMs || v > maxLatencyMs) {
      setState(() => _latencyError = 'De ${minLatencyMs.round()} a ${maxLatencyMs.round()} ms');
      return false;
    }
    _setLatency(v, fromText: true);
    _latencyText.text = _ms(_latency);
    return true;
  }

  /// Fechar leva junto o número digitado e ainda não confirmado (quem digita e fecha espera que
  /// valha); um número inválido segura a janela aberta com o motivo à vista.
  void _close() {
    if (_latencyText.text.trim() != _ms(_latency) && !_commitText()) return;
    Navigator.pop(context);
  }

  /// A lista para o seletor: o padrão do sistema primeiro (com o nome do aparelho, quando o
  /// navegador conta qual é), as entradas, e a escolhida que sumiu (desconectada), para a escolha
  /// não trocar calada.
  List<DropdownMenuItem<String>> _items() {
    String? defaultName;
    final items = <DropdownMenuItem<String>>[];
    var n = 0;
    final seen = <String>{_systemDefault};
    for (final (id, name) in c.inputDevices) {
      // um id repetido derrubaria o seletor (cada valor tem que ser único)
      if (!seen.add(id)) continue;
      if (id == _browserDefault) {
        defaultName = name.isEmpty ? null : name;
        continue;
      }
      n++;
      // sem permissão o navegador esconde os nomes: numera em vez de deixar o item em branco
      items.add(
        DropdownMenuItem(
          value: id,
          child: Text(name.isEmpty ? 'Entrada $n' : name, overflow: TextOverflow.ellipsis),
        ),
      );
    }
    final chosen = c.inputDevice;
    if (chosen != null && chosen != _browserDefault && !c.inputDevices.any((d) => d.$1 == chosen)) {
      items.add(
        DropdownMenuItem(
          value: chosen,
          child: const Text('Entrada desconectada', overflow: TextOverflow.ellipsis),
        ),
      );
    }
    return [
      DropdownMenuItem(
        value: _systemDefault,
        child: Text(defaultName == null ? 'Padrão do sistema' : 'Padrão ($defaultName)', overflow: TextOverflow.ellipsis),
      ),
      ...items,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall!.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final section = theme.textTheme.labelSmall!.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.w700, letterSpacing: 0.9);
    return AlertDialog(
      scrollable: true,
      insetPadding: isDesktop(context) ? const EdgeInsets.symmetric(horizontal: 40, vertical: 24) : const EdgeInsets.all(16),
      title: const Text('Configurações'),
      content: SizedBox(
        width: 460,
        child: ListenableBuilder(
          listenable: c,
          builder: (context, _) {
            final chosen = c.inputDevice;
            final value = chosen == null || chosen == _browserDefault ? _systemDefault : chosen;
            final lostDevice = chosen != null && chosen != _browserDefault && !_loading && !c.inputDevices.any((d) => d.$1 == chosen);
            final controllerError = c.error != null && c.error != _errorAtOpen ? c.error : null;
            final busy = _loading || _switching;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('ENTRADA DE ÁUDIO', style: section),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: InputDecorator(
                        decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4)),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: value,
                            isExpanded: true,
                            isDense: true,
                            items: _items(),
                            // trocar a entrada no meio da gravação cortaria a tomada ao meio
                            onChanged: busy || c.recording ? null : _choose,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    SizedBox(
                      width: 40,
                      height: 40,
                      child: busy
                          ? const Center(child: ButtonSpinner())
                          : IconButton(
                              tooltip: 'Procurar as entradas de novo (depois de conectar um microfone ou interface)',
                              onPressed: _refresh,
                              icon: const Icon(Icons.refresh),
                            ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                if (c.recording)
                  Text('Pare a gravação para trocar de entrada.', style: muted)
                else if (lostDevice)
                  Text('A entrada escolhida não está conectada. Conecte de novo ou escolha outra.', style: muted.copyWith(color: Palette.danger))
                else if (!_loading && _error == null && c.inputDevices.isEmpty)
                  Text('Nenhuma entrada encontrada. Conecte um microfone ou interface e toque em procurar.', style: muted)
                else
                  Text(
                    kIsWeb ? 'O navegador pede permissão para o microfone na primeira vez.' : 'O Android pede permissão para o microfone na primeira vez.',
                    style: muted,
                  ),
                if (_error != null || controllerError != null) ...[const SizedBox(height: 8), InlineNotice(_error ?? controllerError!)],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text('Nível', style: muted),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SizedBox(height: 8, child: InputLevelMeter(level: c.inputLevel, horizontal: true)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text('Mexe enquanto a entrada está aberta: com uma faixa de áudio armada ou monitorando.', style: muted),
                const SizedBox(height: 20),
                Text('GRAVAÇÃO', style: section),
                const SizedBox(height: 4),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Contagem de um compasso'),
                  subtitle: const Text('O metrônomo conta um compasso antes de a gravação começar'),
                  value: c.doc.countIn,
                  onChanged: (v) {
                    if (v != c.doc.countIn) c.toggleCountIn();
                  },
                ),
                const SizedBox(height: 8),
                Text('Pré-roll', style: theme.textTheme.bodyLarge),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  children: [
                    for (var n = 0; n <= DawDoc.maxPreRollBars; n++)
                      ChoiceChip(label: Text(n == 0 ? 'Não' : '$n'), selected: c.doc.preRollBars == n, onSelected: (_) => c.setPreRoll(n)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Compassos que tocam a música antes de a gravação valer (com punch, antes do punch in). É independente da contagem: '
                  'a contagem são os cliques, o pré-roll é o arranjo tocando.',
                  style: muted,
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Punch in/out'),
                  subtitle: Text(_punchText(c.doc), style: muted),
                  value: c.doc.punchOn,
                  onChanged: (v) {
                    if (v != c.doc.punchOn) c.togglePunch();
                  },
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: c.recording || !c.loopRegionUsable ? null : () => c.setPunchRegion(c.doc.loopStart, c.doc.loopEnd),
                    child: const Text('Usar a região do loop'),
                  ),
                ),
                const SizedBox(height: 8),
                Text('Compensação de latência', style: theme.textTheme.bodyLarge),
                Row(
                  children: [
                    Expanded(
                      child: Slider(
                        value: _latency,
                        min: minLatencyMs,
                        max: maxLatencyMs,
                        divisions: (maxLatencyMs - minLatencyMs).round(),
                        label: '${_ms(_latency)} ms',
                        onChanged: (v) => setState(() {
                          _latency = v.roundToDouble();
                          _latencyText.text = _ms(_latency);
                          _latencyError = null;
                        }),
                        // o documento muda ao soltar: arrastar não precisa salvar a cada passo
                        onChangeEnd: _setLatency,
                      ),
                    ),
                    SizedBox(
                      width: 92,
                      child: TextField(
                        controller: _latencyText,
                        focusNode: _latencyFocus,
                        textAlign: TextAlign.end,
                        keyboardType: const TextInputType.numberWithOptions(signed: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[-−0-9]'))],
                        decoration: const InputDecoration(suffixText: 'ms'),
                        onSubmitted: (_) => _commitText(),
                      ),
                    ),
                  ],
                ),
                if (_latencyError != null) Text(_latencyError!, style: muted.copyWith(color: Palette.danger)),
                const SizedBox(height: 4),
                Text(
                  'Quanto o áudio gravado chega atrasado, além do que já é medido sozinho (a latência do motor, com os efeitos e o limitador, e a que ${kIsWeb ? 'o navegador' : 'o sistema'} '
                  'informa para a entrada e a saída): positivo adianta o que for gravado, negativo atrasa. '
                  'Para medir, grave o metrônomo pelo microfone e ajuste até a batida gravada cair na grade.',
                  style: muted,
                ),
                const SizedBox(height: 8),
                Text(
                  'Ida e volta do monitoramento: ${_ms(c.monitorLatency * 1000)} ms'
                  '${c.inputOpen ? '' : ' (sem a entrada: ela só é medida com o microfone aberto)'}',
                  style: theme.textTheme.bodyMedium,
                ),
                Text(
                  'Entrada do aparelho, motor com a compensação dos efeitos e saída, somados: o atraso que quem toca ouve entre o gesto e o som.',
                  style: muted,
                ),
                const SizedBox(height: 20),
                Text('METRÔNOMO', style: section),
                const SizedBox(height: 8),
                _MetronomeSection(c: c, muted: muted),
              ],
            );
          },
        ),
      ),
      actions: [
        // em janelas estreitas a barra do transporte não tem o botão dos atalhos
        TextButton.icon(
          onPressed: () => showShortcuts(context),
          icon: const Icon(Icons.keyboard_command_key, size: 18),
          label: const Text('Atalhos do teclado'),
        ),
        FilledButton(onPressed: _close, child: const Text('Fechar')),
      ],
    );
  }
}

/// As opções do metrônomo: timbre, subdivisão, quando soa e os volumes. Cada mudança vai ao documento
/// (fora do desfazer) e ao motor uma vez.
class _MetronomeSection extends StatelessWidget {
  final DawController c;
  final TextStyle muted;
  const _MetronomeSection({required this.c, required this.muted});

  Widget _dropdown<T>(String label, T value, List<T> values, String Function(T) name, void Function(T) onChanged) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: InputDecorator(
      decoration: InputDecoration(labelText: label, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          isDense: true,
          items: [
            for (final v in values)
              DropdownMenuItem(
                value: v,
                child: Text(name(v), overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final o = c.doc.metronomeOptions;
    String pct(double v) => '${(v * 100).round()}%';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _dropdown<MetronomeTimbre>('Timbre', o.timbre, MetronomeTimbre.values, (v) => v.label, (v) => c.setMetronomeOptions((o) => o.timbre = v)),
        _dropdown<MetronomeSubdivision>(
          'Subdivisão',
          o.subdivision,
          MetronomeSubdivision.values,
          (v) => v.label,
          (v) => c.setMetronomeOptions((o) => o.subdivision = v),
        ),
        _dropdown<MetronomeMode>('Quando soa', o.mode, MetronomeMode.values, (v) => v.label, (v) => c.setMetronomeOptions((o) => o.mode = v)),
        OptionSlider(label: 'Volume', value: o.volume, min: 0, max: 1, format: pct, onCommit: (v) => c.setMetronomeOptions((o) => o.volume = v)),
        OptionSlider(
          label: 'Acento do primeiro tempo',
          value: o.accentLevel,
          min: 0,
          max: 2,
          format: pct,
          onCommit: (v) => c.setMetronomeOptions((o) => o.accentLevel = v),
        ),
        OptionSlider(
          label: 'Altura do acento',
          value: o.accentPitch,
          min: 0.5,
          max: 4,
          format: (v) => '×${v.toStringAsFixed(2).replaceAll('.', ',')}',
          onCommit: (v) => c.setMetronomeOptions((o) => o.accentPitch = v),
        ),
        if (o.subdivision != MetronomeSubdivision.beat && o.subdivision != MetronomeSubdivision.accentOnly)
          OptionSlider(
            label: 'Volume das subdivisões',
            value: o.subLevel,
            min: 0,
            max: 2,
            format: pct,
            onCommit: (v) => c.setMetronomeOptions((o) => o.subLevel = v),
          ),
        Text(
          o.mode == MetronomeMode.recording
              ? 'Liga e desliga pelo botão do metrônomo${shortcutHint('transport.metronome')}; nesse modo ele só soa gravando, na contagem e no pré-roll.'
              : 'Liga e desliga pelo botão do metrônomo${shortcutHint('transport.metronome')}. O clique acompanha o compasso e o andamento do projeto.',
          style: muted,
        ),
      ],
    );
  }
}

/// Um controle deslizante com o valor à direita; só entrega o valor ao soltar (arrastar não manda uma
/// mudança de estilo ao motor a cada passo).
class OptionSlider extends StatefulWidget {
  final String label;
  final double value, min, max;
  final String Function(double) format;
  final void Function(double) onCommit;
  const OptionSlider({super.key, required this.label, required this.value, required this.min, required this.max, required this.format, required this.onCommit});

  @override
  State<OptionSlider> createState() => _OptionSliderState();
}

class _OptionSliderState extends State<OptionSlider> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final v = (_drag ?? widget.value).clamp(widget.min, widget.max).toDouble();
    return Row(
      children: [
        Expanded(flex: 5, child: Text(widget.label, overflow: TextOverflow.ellipsis)),
        Expanded(
          flex: 6,
          child: Slider(
            value: v,
            min: widget.min,
            max: widget.max,
            onChanged: (x) => setState(() => _drag = x),
            onChangeEnd: (x) {
              setState(() => _drag = null);
              widget.onCommit(x);
            },
          ),
        ),
        SizedBox(width: 44, child: Text(widget.format(v), textAlign: TextAlign.end)),
      ],
    );
  }
}
