/// Exportar: a janela das opções ([ExportDialog]) e a do andamento do render ([ExportProgressDialog]).
/// O render é do controlador ([DawController.exportAudio]), fora de tempo real e no aparelho; aqui
/// fica só escolher, acompanhar e contar o resultado, com o erro dentro da própria janela.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../widgets/feedback.dart';
import '../widgets/responsive_scaffold.dart';
import 'controller.dart';
import 'export_options.dart';
import 'model.dart';
import 'transport_bar.dart' show describeActionError;

/// As últimas opções usadas, para a próxima exportação da sessão começar de onde a pessoa parou
/// (exportar de novo depois de um ajuste na mixagem é o caso comum).
ExportOptions? _lastOptions;

/// Taxas oferecidas além da do aparelho (a do motor).
const _rates = [44100, 48000, 88200, 96000];

/// Abaixo disto (em batidas) não há região de loop marcada.
const _minLoop = 0.01;

bool _hasLoopRegion(DawDoc d) => d.loopEnd - d.loopStart > _minLoop;

/// Abre as opções e, confirmadas, o render com progresso. Se o render falha, a pessoa pode voltar às
/// opções (com as mesmas escolhas) e tentar de novo.
Future<void> showExportDialog(BuildContext context, DawController c) async {
  var options = _lastOptions ?? const ExportOptions();
  while (true) {
    if (!context.mounted) return;
    final chosen = await showDialog<ExportOptions>(
      context: context,
      builder: (_) => ExportDialog(c: c, initial: options),
    );
    if (chosen == null || !context.mounted) return;
    options = _lastOptions = chosen;
    final retry = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ExportProgressDialog(c: c, options: chosen),
    );
    if (retry != true) return;
  }
}

String _clock(double seconds) {
  final s = seconds.isFinite ? seconds.clamp(0, 359999).round() : 0;
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, r = s % 60;
  final mm = h > 0 ? '$h:${'$m'.padLeft(2, '0')}' : '$m';
  return '$mm:${'$r'.padLeft(2, '0')}';
}

String _seconds(double s) => '${s.toStringAsFixed(s == s.roundToDouble() ? 0 : 1).replaceAll('.', ',')} s';

String _khz(int rate) => '${(rate / 1000).toStringAsFixed(rate % 1000 == 0 ? 0 : 1).replaceAll('.', ',')} kHz';

/// Para que serve cada formato, na língua de quem vai escolher.
String _formatHint(ExportFormat f) => switch (f) {
  ExportFormat.wav16 => 'Qualidade de CD, o menor arquivo. Para ouvir e publicar.',
  ExportFormat.wav24 => 'O padrão de estúdio: folga para masterizar depois.',
  ExportFormat.wav32f => 'Sem perda nenhuma, nem acima de 0 dB. Para levar a outro programa.',
};

/// As opções da exportação: formato, taxa, intervalo, stems, normalizar e cauda. Devolve as
/// [ExportOptions] escolhidas (null ao cancelar).
class ExportDialog extends StatefulWidget {
  final DawController c;
  final ExportOptions initial;
  const ExportDialog({super.key, required this.c, this.initial = const ExportOptions()});

  @override
  State<ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<ExportDialog> {
  DawDoc get _doc => widget.c.doc;

  late ExportFormat _format = widget.initial.format;
  // a região pode ter sumido desde a última exportação: aí volta para a música inteira
  late ExportRange _range = widget.initial.range == ExportRange.loop && !_hasLoopRegion(_doc) ? ExportRange.song : widget.initial.range;
  late bool _stems = widget.initial.stems;
  late bool _normalize = widget.initial.normalize;
  late double _tail = widget.initial.tail.clamp(0, 10).toDouble();
  // só taxas que a lista oferece; a do aparelho é o null (ela pode ter mudado desde a última vez)
  late int? _rate = _rates.contains(widget.initial.sampleRate) && widget.initial.sampleRate != widget.c.engineRate.round() ? widget.initial.sampleRate : null;

  /// Início e fim do intervalo escolhido, em batidas.
  (double, double) get _span => switch (_range) {
    ExportRange.song => (0, _doc.contentEnd),
    ExportRange.loop => (_doc.loopStart, _doc.loopEnd),
  };

  double get _spanSeconds => (_span.$2 - _span.$1) * 60 / _doc.bpm;

  bool get _empty => _span.$2 - _span.$1 <= _minLoop;

  String _bars(double from, double to) {
    final bpb = _doc.beatsPerBar;
    final a = from ~/ bpb + 1;
    // o fim cai no começo do compasso seguinte: o último compasso inteiro é o anterior
    final b = ((to - 1e-6) ~/ bpb + 1).clamp(a, 1 << 30);
    return a == b ? 'Compasso $a' : 'Compassos $a a $b';
  }

  void _submit() => Navigator.pop(context, ExportOptions(format: _format, range: _range, stems: _stems, normalize: _normalize, tail: _tail, sampleRate: _rate));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall!.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final loop = _hasLoopRegion(_doc);
    final engineRate = widget.c.engineRate.round();
    final tracks = _doc.tracks.where((t) => t.kind.hasClips).length;
    return AlertDialog(
      scrollable: true,
      insetPadding: isDesktop(context) ? const EdgeInsets.symmetric(horizontal: 40, vertical: 24) : const EdgeInsets.all(16),
      title: const Text('Exportar áudio'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Label('Intervalo', style: muted),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: Text(ExportRange.song.label),
                  selected: _range == ExportRange.song,
                  onSelected: (_) => setState(() => _range = ExportRange.song),
                ),
                Tooltip(
                  message: loop ? _bars(_doc.loopStart, _doc.loopEnd) : 'Marque uma região arrastando na régua para exportar só ela',
                  child: ChoiceChip(
                    label: Text(ExportRange.loop.label),
                    selected: _range == ExportRange.loop,
                    onSelected: loop ? (_) => setState(() => _range = ExportRange.loop) : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              _empty
                  ? (_range == ExportRange.song ? 'O projeto ainda não tem clipes.' : 'A região do loop está vazia.')
                  : '${_bars(_span.$1, _span.$2)} · ${_clock(_spanSeconds)}${_tail > 0 ? ' + ${_seconds(_tail)} de cauda' : ''}',
              style: muted,
            ),
            const SizedBox(height: 16),
            _Label('Formato', style: muted),
            DropdownButtonFormField<ExportFormat>(
              initialValue: _format,
              isExpanded: true,
              items: [for (final f in ExportFormat.values) DropdownMenuItem(value: f, child: Text(f.label))],
              onChanged: (v) => setState(() => _format = v ?? _format),
            ),
            const SizedBox(height: 4),
            Text(_formatHint(_format), style: muted),
            const SizedBox(height: 16),
            _Label('Taxa de amostragem', style: muted),
            DropdownButtonFormField<int?>(
              initialValue: _rate,
              isExpanded: true,
              items: [
                DropdownMenuItem(value: null, child: Text('A do aparelho (${_khz(engineRate)})')),
                for (final r in _rates)
                  if (r != engineRate) DropdownMenuItem(value: r, child: Text(_khz(r))),
              ],
              onChanged: (v) => setState(() => _rate = v),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Stems'),
              subtitle: Text(tracks == 1 ? 'Um arquivo da faixa, além da mixagem' : 'Um arquivo por faixa, além da mixagem'),
              value: _stems,
              onChanged: (v) => setState(() => _stems = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Normalizar'),
              subtitle: const Text('Sobe (ou desce) tudo até o pico ficar em −1 dBFS'),
              value: _normalize,
              onChanged: (v) => setState(() => _normalize = v),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: Text('Cauda', style: theme.textTheme.bodyLarge)),
                Text(_seconds(_tail), style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()])),
              ],
            ),
            Slider(value: _tail, max: 10, divisions: 20, label: _seconds(_tail), onChanged: (v) => setState(() => _tail = v)),
            Text('Tempo depois do fim para o reverb, o delay e a soltura das notas terminarem.', style: muted),
            if (_empty) ...[
              const SizedBox(height: 12),
              InlineNotice(
                _range == ExportRange.song
                    ? 'Não há o que exportar: grave, importe ou desenhe um clipe primeiro.'
                    : 'Não há o que exportar: a região do loop não tem duração.',
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton.icon(onPressed: _empty ? null : _submit, icon: const Icon(Icons.save_alt), label: const Text('Exportar')),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  final TextStyle style;
  const _Label(this.text, {required this.style});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(text.toUpperCase(), style: style.copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.8, fontSize: 11)),
  );
}

/// O render em andamento: barra de progresso enquanto o controlador trabalha, depois o resultado
/// ou o erro. Não fecha por fora no meio (só esconderia o trabalho): "Cancelar" interrompe o render
/// e fecha. Devolve true quando a pessoa quer voltar às opções depois de um erro.
class ExportProgressDialog extends StatefulWidget {
  final DawController c;
  final ExportOptions options;
  const ExportProgressDialog({super.key, required this.c, required this.options});

  @override
  State<ExportProgressDialog> createState() => _ExportProgressDialogState();
}

class _ExportProgressDialogState extends State<ExportProgressDialog> {
  /// 0..1 depois do primeiro aviso do controlador; antes, a barra corre sem valor.
  double? _progress;
  bool _done = false;
  String? _error;

  /// Aviso de uma exportação que terminou (um áudio que faltava, por exemplo).
  String? _warning;

  /// O render chegou ao fim (o controlador avisou 100%): o que vier depois é aviso, não falha.
  bool _rendered = false;
  bool _canceled = false;
  final _elapsed = Stopwatch();

  @override
  void initState() {
    super.initState();
    // logo depois do initState: uma falha síncrona do controlador faria setState ainda dentro dele
    scheduleMicrotask(_run);
  }

  Future<void> _run() async {
    _elapsed.start();
    final c = widget.c;
    // o controlador não lança: falha e aviso chegam no error dele, que começa limpo
    c.clearError();
    String? error;
    try {
      await c.exportAudio(
        widget.options,
        onProgress: (p) {
          if (!mounted || !p.isFinite) return;
          final v = p.clamp(0.0, 1.0);
          if (v >= 1) _rendered = true;
          // um aviso por quadro basta: o render manda muitos
          if (_progress != null && (v - _progress!).abs() < 0.002 && v < 1) return;
          setState(() => _progress = v);
        },
      );
    } catch (e) {
      error = describeActionError(e);
    }
    _elapsed.stop();
    if (!mounted) return;
    if (_canceled) {
      Navigator.pop(context, false);
      return;
    }
    final said = c.error;
    String? warning;
    if (said != null) {
      // mostrado aqui, sai da tela de trás
      c.clearError();
      if (_rendered && error == null) {
        warning = said;
      } else {
        error ??= said;
      }
    }
    setState(() {
      _done = error == null;
      _error = error;
      _warning = warning;
    });
  }

  void _cancel() {
    setState(() => _canceled = true);
    widget.c.cancelRender();
  }

  bool get _running => !_done && _error == null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall!.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final p = _progress;
    final Widget body;
    if (_running) {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LinearProgressIndicator(value: p, minHeight: 6, borderRadius: BorderRadius.circular(3)),
          const SizedBox(height: 10),
          Text(
            // o render termina antes do arquivo: no fim ainda falta converter e entregar os bytes
            p == null ? 'Preparando…' : (p >= 1 ? 'Salvando o arquivo…' : 'Renderizando ${(p * 100).floor()}%'),
            style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
          ),
          const SizedBox(height: 6),
          Text('O render roda mais rápido que tocar, no próprio aparelho. Deixe esta aba aberta até terminar.', style: muted),
        ],
      );
    } else if (_done) {
      final format = widget.options.format.label;
      final secs = math.max(1, (_elapsed.elapsedMilliseconds / 1000).ceil());
      final warning = _warning;
      body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.check_circle_outline, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.options.stems
                      ? 'A mixagem e os stems foram salvos ($format) em $secs s. No navegador, os arquivos ficam nos downloads.'
                      : 'A mixagem foi salva ($format) em $secs s. No navegador, o arquivo fica nos downloads.',
                ),
              ),
            ],
          ),
          if (warning != null) ...[const SizedBox(height: 12), InlineNotice(warning)],
        ],
      );
    } else {
      body = InlineNotice(_error!);
    }
    return PopScope(
      canPop: !_running,
      child: AlertDialog(
        scrollable: true,
        insetPadding: isDesktop(context) ? const EdgeInsets.symmetric(horizontal: 40, vertical: 24) : const EdgeInsets.all(16),
        title: Text(_running ? 'Exportando…' : (_done ? 'Exportação concluída' : 'A exportação falhou')),
        content: SizedBox(width: 400, child: body),
        actions: [
          if (_running)
            TextButton(onPressed: _canceled || (p ?? 0) >= 1 ? null : _cancel, child: Text(_canceled ? 'Cancelando…' : 'Cancelar'))
          else if (_error != null) ...[
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Fechar')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Voltar às opções')),
          ] else if (_done)
            FilledButton(onPressed: () => Navigator.pop(context, false), child: const Text('Fechar')),
        ],
      ),
    );
  }
}
