/// Exportar: a janela das opções ([ExportDialog]) e a do andamento do render ([ExportProgressDialog]).
/// O render é do controlador ([DawController.exportAudio]), fora de tempo real e no aparelho; aqui
/// fica só escolher, acompanhar e contar o resultado, com o erro dentro da própria janela.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../api/client.dart';
import '../api/export_api.dart';
import '../auth/session.dart';
import '../widgets/feedback.dart';
import '../widgets/format.dart' show sentence;
import '../widgets/responsive_scaffold.dart';
import 'controller.dart';
import 'effects.dart' show effectMonitoringNote;
import 'export_compressed.dart';
import 'export_options.dart';
import 'loudness.dart';
import 'loudness_panel.dart';
import 'midi_file_ui.dart';
import 'model.dart';
import 'project_file_ui.dart';
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
    var wholeProject = false, midi = false;
    final chosen = await showDialog<ExportOptions>(
      context: context,
      builder: (_) => ExportDialog(c: c, initial: options, onWholeProject: () => wholeProject = true, onMidi: () => midi = true),
    );
    if (midi && context.mounted) {
      await showExportMidiDialog(context, c);
      return;
    }
    if (wholeProject && context.mounted) {
      await showExportProjectDialog(context, name: c.project.name, loadDoc: () async => c.doc, loadSample: loadSampleLocalOrServer);
      return;
    }
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
  ExportFormat.flac => 'Sem perda, com bem menos espaço que o WAV. Convertido no servidor: precisa de conta e de rede.',
  ExportFormat.mp3 => 'Leve, para compartilhar e ouvir em qualquer lugar (com perda). Convertido no servidor: precisa de conta e de rede.',
};

/// MP3 só nas taxas que o servidor aceita.
bool _mp3Rate(int rate) => rate == 44100 || rate == 48000;

/// As opções da exportação: formato, taxa, intervalo, stems, normalizar e cauda. Devolve as
/// [ExportOptions] escolhidas (null ao cancelar).
class ExportDialog extends StatefulWidget {
  final DawController c;
  final ExportOptions initial;

  /// Chamado quando a pessoa prefere levar o projeto inteiro (.jopendaw) em vez da música em WAV.
  final VoidCallback? onWholeProject;

  /// Chamado quando a pessoa prefere as notas em MIDI (.mid) (ver `midi_file_ui.dart`).
  final VoidCallback? onMidi;
  const ExportDialog({super.key, required this.c, this.initial = const ExportOptions(), this.onWholeProject, this.onMidi});

  @override
  State<ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<ExportDialog> {
  DawDoc get _doc => widget.c.doc;

  late ExportFormat _format = widget.initial.format;
  // a região pode ter sumido desde a última exportação: aí volta para a música inteira
  late ExportRange _range = widget.initial.range == ExportRange.loop && !_hasLoopRegion(_doc) ? ExportRange.song : widget.initial.range;
  late bool _stems = widget.initial.stems;
  late bool _normalize = widget.initial.normalize && !widget.initial.normalizesLoudness;
  // normalização de loudness: o alvo volta ao pré-definido que tem o mesmo valor (senão, personalizado)
  late bool _loud = widget.initial.normalizesLoudness;
  late LoudnessTarget _target = LoudnessTarget.values.firstWhere(
    (t) => t != LoudnessTarget.custom && t.lufs == widget.initial.targetLufs,
    orElse: () => widget.initial.normalizesLoudness ? LoudnessTarget.custom : LoudnessTarget.streaming,
  );
  late double _customLufs = (widget.initial.targetLufs ?? LoudnessTarget.streaming.lufs).clamp(kMinTargetLufs, kMaxTargetLufs).toDouble();
  late double _ceiling = widget.initial.ceilingDbtp.clamp(kMinCeiling, kMaxCeiling).toDouble();
  late bool _loudStems = widget.initial.normalizeStems;
  late double _tail = widget.initial.tail.clamp(0, 10).toDouble();
  late int _flacBits = widget.initial.flacBits == 16 ? 16 : 24;
  late FlacLevel _flacLevel = widget.initial.flacLevel;
  late Mp3Quality _mp3 = widget.initial.mp3Quality;
  late final _artist = TextEditingController(text: widget.initial.artist);
  // só taxas que a lista oferece; a do aparelho é o null (ela pode ter mudado desde a última vez)
  late int? _rate = _rates.contains(widget.initial.sampleRate) && widget.initial.sampleRate != widget.c.engineRate.round() ? widget.initial.sampleRate : null;

  /// Início e fim do intervalo escolhido, em batidas.
  (double, double) get _span => switch (_range) {
    ExportRange.song => (0, _doc.contentEnd),
    ExportRange.loop => (_doc.loopStart, _doc.loopEnd),
  };

  double get _spanSeconds => _doc.tempo.isSingle ? (_span.$2 - _span.$1) * 60 / _doc.bpm : _doc.secondsAt(_span.$2) - _doc.secondsAt(_span.$1);

  bool get _empty => _span.$2 - _span.$1 <= _minLoop;

  int get _effectiveRate => _rate ?? widget.c.engineRate.round();

  /// O servidor recusa arquivo com mais de 30 minutos (a duração já inclui a cauda).
  bool get _tooLongForServer => _format.compressed && !_empty && _spanSeconds + _tail > kEncodeMaxSeconds;

  @override
  void dispose() {
    _artist.dispose();
    super.dispose();
  }

  /// Profundidade do WAV que sobe ao servidor (a mesma de [ExportOptions.renderFormat]).
  int get _uploadBits => _format == ExportFormat.mp3 ? 16 : (_flacBits == 16 ? 16 : 24);

  /// Tamanho do WAV da mixagem (cada stem tem o mesmo): sobe inteiro e o servidor recusa mais que 512 MB, o que em taxa
  /// e profundidade altas acontece antes dos 30 minutos.
  int get _uploadBytes => estimatedWavBytes(_spanSeconds + _tail, _effectiveRate, _uploadBits);

  bool get _tooBigToUpload => _format.compressed && !_empty && _uploadBytes > kEncodeMaxUploadBytes;

  /// Efeitos (das faixas e do master) em solo ou ouvindo a banda: o áudio sai assim na exportação.
  List<String> get _monitoring {
    final out = <String>[];
    void scan(String where, List<EffectSlot> chain) {
      for (final s in chain) {
        final note = effectMonitoringNote(s.kind, s.params, bypass: s.bypass);
        if (note != null) out.add('${s.kind.label} ($where)');
      }
    }

    for (final t in _doc.tracks) {
      // congelada: os efeitos já estão no áudio renderizado e não soam mais
      if (t.frozen != null) continue;
      scan(t.name, t.effects);
    }
    scan('master', _doc.masterEffects);
    return out;
  }

  /// Ao escolher MP3 numa taxa que ele não aceita, passa para 44,1 kHz.
  void _pickFormat(ExportFormat f) {
    _format = f;
    if (f == ExportFormat.mp3 && !_mp3Rate(_effectiveRate)) _rate = 44100;
  }

  String _bars(double from, double to) {
    final bpb = _doc.beatsPerBar;
    final m = _doc.meter;
    final a = m.isSingle ? from ~/ bpb + 1 : m.barOf(from).$1;
    // o fim cai no começo do compasso seguinte: o último compasso inteiro é o anterior
    final b = (m.isSingle ? (to - 1e-6) ~/ bpb + 1 : m.barOf(to - 1e-6).$1).clamp(a, 1 << 30);
    return a == b ? 'Compasso $a' : 'Compassos $a a $b';
  }

  void _submit() => Navigator.pop(
    context,
    ExportOptions(
      format: _format,
      range: _range,
      stems: _stems,
      normalize: _normalize && !_loud,
      targetLufs: _loud ? (_target == LoudnessTarget.custom ? _customLufs : _target.lufs) : null,
      ceilingDbtp: _ceiling,
      normalizeStems: _loud && _stems && _loudStems,
      tail: _tail,
      sampleRate: _rate,
      flacBits: _flacBits,
      flacLevel: _flacLevel,
      mp3Quality: _mp3,
      artist: _artist.text.trim(),
    ),
  );

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
              onChanged: (v) => setState(() => _pickFormat(v ?? _format)),
            ),
            const SizedBox(height: 4),
            Text(_formatHint(_format), style: muted),
            if (_format == ExportFormat.flac) ...[
              const SizedBox(height: 12),
              _Label('Profundidade e compressão', style: muted),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final b in const [16, 24])
                    ChoiceChip(key: Key('flac-bits-$b'), label: Text('$b bits'), selected: _flacBits == b, onSelected: (_) => setState(() => _flacBits = b)),
                ],
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<FlacLevel>(
                key: const Key('flac-level'),
                initialValue: _flacLevel,
                isExpanded: true,
                items: [for (final l in FlacLevel.values) DropdownMenuItem(value: l, child: Text(l.label))],
                onChanged: (v) => setState(() => _flacLevel = v ?? _flacLevel),
              ),
            ],
            if (_format == ExportFormat.mp3) ...[
              const SizedBox(height: 12),
              _Label('Qualidade do MP3', style: muted),
              DropdownButtonFormField<Mp3Quality>(
                key: const Key('mp3-quality'),
                initialValue: _mp3,
                isExpanded: true,
                items: [for (final q in Mp3Quality.values) DropdownMenuItem(value: q, child: Text(q.label))],
                onChanged: (v) => setState(() => _mp3 = v ?? _mp3),
              ),
            ],
            if (_format.compressed) ...[
              const SizedBox(height: 12),
              _Label('Artista (opcional)', style: muted),
              TextField(
                key: const Key('export-artist'),
                controller: _artist,
                maxLength: 200,
                decoration: const InputDecoration(hintText: 'Vai nos metadados e no nome do arquivo', counterText: ''),
              ),
            ],
            const SizedBox(height: 16),
            _Label('Taxa de amostragem', style: muted),
            DropdownButtonFormField<int?>(
              initialValue: _rate,
              isExpanded: true,
              items: [
                if (_format != ExportFormat.mp3 || _mp3Rate(engineRate)) DropdownMenuItem(value: null, child: Text('A do aparelho (${_khz(engineRate)})')),
                for (final r in _rates)
                  if (r != engineRate && (_format != ExportFormat.mp3 || _mp3Rate(r))) DropdownMenuItem(value: r, child: Text(_khz(r))),
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
              // pico e loudness são pedidos contrários: ligar um desliga o outro
              onChanged: (v) => setState(() {
                _normalize = v;
                if (v) _loud = false;
              }),
            ),
            LoudnessNormalizeOptions(
              enabled: _loud,
              target: _target,
              customLufs: _customLufs,
              ceiling: _ceiling,
              hasStems: _stems,
              normalizeStems: _loudStems,
              onEnabled: (v) => setState(() {
                _loud = v;
                if (v) _normalize = false;
              }),
              onTarget: (t) => setState(() => _target = t),
              onCustom: (v) => setState(() => _customLufs = (v * 2).round() / 2),
              onCeiling: (v) => setState(() => _ceiling = (v * 2).round() / 2),
              onNormalizeStems: (v) => setState(() => _loudStems = v),
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
            if (_tooLongForServer) ...[
              const SizedBox(height: 12),
              const InlineNotice('O servidor converte até 30 minutos por arquivo: escolha um trecho menor, diminua a cauda ou exporte em WAV.'),
            ],
            if (_tooBigToUpload) ...[
              const SizedBox(height: 12),
              InlineNotice(
                'O WAV desta música passa de 512 MB (${(_uploadBytes / (1 << 20)).round()} MB), o limite do servidor para converter: '
                'exporte em WAV, ou reduza a taxa de amostragem, o trecho ou a cauda.',
              ),
            ],
            if (_monitoring.isNotEmpty) ...[
              const SizedBox(height: 12),
              InlineNotice(
                key: const Key('export-monitoring-warning'),
                'Um efeito está em solo ou ouvindo a banda: a exportação sairá assim (${_monitoring.join(', ')}). Desligue o solo ou o "Ouvir banda" antes, se não era a intenção.',
              ),
            ],
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
        if (widget.onWholeProject != null)
          TextButton.icon(
            onPressed: () {
              widget.onWholeProject!();
              Navigator.pop(context);
            },
            icon: const Icon(Icons.inventory_2_outlined, size: 18),
            label: const Text('Projeto inteiro (.jopendaw)…'),
          ),
        if (widget.onMidi != null)
          TextButton.icon(
            key: const Key('export-midi-link'),
            onPressed: () {
              widget.onMidi!();
              Navigator.pop(context);
            },
            icon: const Icon(Icons.piano, size: 18),
            label: const Text('Notas em MIDI (.mid)…'),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton.icon(
          onPressed: _empty || _tooLongForServer || _tooBigToUpload ? null : _submit,
          icon: const Icon(Icons.save_alt),
          label: const Text('Exportar'),
        ),
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

  /// O servidor (FLAC e MP3) e a sessão; os testes trocam por falsos.
  final ExportApi? api;
  final bool Function()? signedIn;
  const ExportProgressDialog({super.key, required this.c, required this.options, this.api, this.signedIn});

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

  /// FLAC e MP3: a conversão no servidor, arquivo por arquivo, e o WAV guardado se ela falhar.
  CompressedExport? _cx;

  /// A compactação falhou e há WAV renderizado esperando a pessoa decidir.
  bool _fallback = false;
  bool _savingWav = false;
  int _wavSaved = 0;

  /// A pessoa fechou a janela "Salvar" do aparelho (na conversão ou no "WAV mesmo assim"): exportação cancelada.
  bool _saveCanceled = false;

  /// O maior progresso já mostrado: a barra de FLAC e MP3 soma o render e a conversão e nunca recua.
  double _shown = 0;

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
    final options = widget.options;
    if (options.format.compressed) {
      _cx = CompressedExport(
        api: widget.api ?? ApiClient.instance,
        options: options,
        album: c.project.name,
        expectedFiles: options.stems ? c.doc.tracks.length + 1 : 1,
        save: c.saveExportedFile,
        signedIn: widget.signedIn ?? () => Session.instance.signedIn,
      )..addListener(() => mounted ? setState(() {}) : null);
    }
    try {
      await c.exportAudio(
        options,
        sink: _cx?.deliver,
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
    final pending = _cx?.fallbacks.isNotEmpty ?? false;
    // WAV direto: o controlador avisa que o "Salvar" foi cancelado; compactado: o CompressedExport
    final saveCanceled = (_cx?.saveCanceled ?? false) || c.exportSaveCanceledName != null;
    setState(() {
      _saveCanceled = error == null && saveCanceled;
      _fallback = error == null && pending && !saveCanceled;
      _done = error == null && !pending && !saveCanceled;
      _error = error;
      _warning = warning;
    });
  }

  void _cancel() {
    setState(() => _canceled = true);
    _cx?.cancel();
    widget.c.cancelRender();
  }

  /// "Exportar em WAV mesmo assim": salva os WAV que já estavam renderizados.
  Future<void> _saveWavs() async {
    setState(() => _savingWav = true);
    try {
      final n = await _cx!.saveWavs();
      if (!mounted) return;
      final left = _cx!.fallbacks.isNotEmpty;
      setState(() {
        _wavSaved += n;
        // sobrou WAV sem salvar: a janela "Salvar" foi fechada no meio
        _saveCanceled = left;
        _fallback = left;
        _done = !left;
        _savingWav = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = describeActionError(e);
        _fallback = false;
        _savingWav = false;
      });
    }
  }

  bool get _running => !_done && _error == null && !_fallback && !_saveCanceled;

  /// Em que formatos saiu o que foi salvo: "MP3", "WAV" (a queda) ou "2 em FLAC, 1 em WAV" quando misturou.
  String get _savedFormats {
    final cx = _cx;
    final compressed = cx?.compressed ?? 0;
    if (_wavSaved == 0) return widget.options.format.shortLabel;
    if (compressed == 0) return 'WAV';
    return '$compressed em ${widget.options.format.shortLabel}, $_wavSaved em WAV';
  }

  /// Progresso da barra. FLAC e MP3 têm duas fases (0 a 50% o render, 50 a 100% a conversão) e o valor nunca recua,
  /// mesmo que o render do lote seguinte recomece de baixo.
  double? _barValue() {
    final cx = _cx;
    if (cx == null) return _progress;
    final render = _progress;
    if (render == null && cx.stage == null) return null;
    final v = 0.5 * (render ?? 0) + 0.5 * cx.fraction;
    if (v > _shown) _shown = v;
    return _shown.clamp(0.0, 0.999).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall!.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final cx = _cx;
    // compactado: o CompressedExport sabe o nome e quantos já saíram; WAV direto: o controlador
    final canceledName = cx?.canceledName ?? widget.c.exportSaveCanceledName;
    final savedBefore = cx != null ? cx.compressed : widget.c.exportSavedCount;
    final stage = cx?.stage;
    final p = _barValue();
    // o texto do render fala do render, não da barra somada
    final render = _progress;
    final Widget body;
    if (_saveCanceled && !_fallback) {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InlineNotice(
            key: const Key('export-save-canceled'),
            'Exportação cancelada: você não escolheu onde salvar${canceledName != null ? ' "$canceledName"' : ''}.'
            '${savedBefore > 0 ? (savedBefore == 1 ? ' O arquivo anterior já tinha sido salvo.' : ' Os $savedBefore arquivos anteriores já tinham sido salvos.') : ''}',
          ),
        ],
      );
    } else if (_fallback) {
      final n = cx!.fallbacks.length;
      body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_saveCanceled)
            InlineNotice(key: const Key('export-save-canceled'), 'Exportação cancelada: $n ${n == 1 ? 'arquivo ficou' : 'arquivos ficaram'} sem salvar.')
          else
            InlineNotice(
              'Não deu para exportar em ${widget.options.format == ExportFormat.mp3 ? 'MP3' : 'FLAC'}: ${cx.failure ?? 'o servidor não respondeu.'}',
            ),
          const SizedBox(height: 12),
          Text(
            cx.compressed > 0
                ? '${cx.compressed} ${cx.compressed == 1 ? 'arquivo foi salvo compactado' : 'arquivos foram salvos compactados'}. '
                      '${n == 1 ? 'O outro já está renderizado' : 'Os outros $n já estão renderizados'} em WAV: dá para salvar assim, sem renderizar de novo.'
                : 'O ${n == 1 ? 'arquivo já está renderizado' : 'áudio já está renderizado ($n arquivos)'} em WAV: dá para salvar assim, sem renderizar de novo.',
          ),
        ],
      );
    } else if (_running) {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LinearProgressIndicator(value: p, minHeight: 6, borderRadius: BorderRadius.circular(3)),
          const SizedBox(height: 10),
          Text(
            // o render termina antes do arquivo: no fim ainda falta converter e entregar os bytes
            stage ??
                (render == null
                    ? 'Preparando…'
                    : render >= 1
                    ? 'Salvando o arquivo…'
                    // depois dos 95% o render acabou e a mixagem está sendo medida e normalizada
                    : (render >= 0.95 && widget.options.normalizesLoudness ? 'Medindo o loudness…' : 'Renderizando ${(render * 100).floor()}%')),
            style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
          ),
          const SizedBox(height: 6),
          Text('O render roda mais rápido que tocar, no próprio aparelho. Deixe esta aba aberta até terminar.', style: muted),
        ],
      );
    } else if (_done) {
      final format = _savedFormats;
      final secs = math.max(1, (_elapsed.elapsedMilliseconds / 1000).ceil());
      final warning = _warning;
      final report = widget.options.normalizesLoudness ? widget.c.exportReport : null;
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
          if (report != null) ...[
            const SizedBox(height: 12),
            // o que a normalização fez: quando o teto segurou o ganho ou não deu para medir, em aviso
            if (report.limitedByCeiling || report.unmeasurable) InlineNotice(report.describe()) else Text(report.describe()),
          ],
          if (warning != null) ...[const SizedBox(height: 12), InlineNotice(warning)],
          for (final w in cx?.warnings ?? const <String>[]) ...[const SizedBox(height: 12), InlineNotice(sentence(w))],
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
        title: Text(
          _running
              ? 'Exportando…'
              : (_saveCanceled ? 'Exportação cancelada' : (_fallback ? 'Não deu para compactar' : (_done ? 'Exportação concluída' : 'A exportação falhou'))),
        ),
        content: SizedBox(width: 400, child: body),
        actions: [
          if (_running)
            TextButton(onPressed: _canceled || (render ?? 0) >= 1 && cx == null ? null : _cancel, child: Text(_canceled ? 'Cancelando…' : 'Cancelar'))
          else if (_saveCanceled && !_fallback) ...[
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Fechar')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Voltar às opções')),
          ] else if (_fallback) ...[
            TextButton(onPressed: _savingWav ? null : () => Navigator.pop(context, false), child: const Text('Fechar')),
            TextButton(onPressed: _savingWav ? null : () => Navigator.pop(context, true), child: const Text('Voltar às opções')),
            FilledButton.icon(
              key: const Key('export-wav-anyway'),
              onPressed: _savingWav ? null : _saveWavs,
              icon: const Icon(Icons.save_alt),
              label: const Text('Exportar em WAV mesmo assim'),
            ),
          ] else if (_error != null) ...[
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Fechar')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Voltar às opções')),
          ] else if (_done)
            FilledButton(onPressed: () => Navigator.pop(context, false), child: const Text('Fechar')),
        ],
      ),
    );
  }
}
