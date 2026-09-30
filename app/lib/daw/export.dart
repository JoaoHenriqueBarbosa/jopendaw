/// Exportar: a janela das opções ([ExportDialog]) e a do andamento do render ([ExportProgressDialog]).
/// O render é do controlador ([DawController.exportAudio]), fora de tempo real e no aparelho; aqui
/// fica só escolher, acompanhar e contar o resultado, com o erro dentro da própria janela.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

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
import 'export_plan.dart';
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
Future<void> showExportDialog(BuildContext context, DawController c, {ExportOptions? preset}) async {
  var options = preset ?? _lastOptions ?? const ExportOptions();
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
  // a região (ou os marcadores) pode ter sumido desde a última exportação: aí volta para a música inteira
  late ExportRange _range = _validRange(widget.initial);
  late bool _stems = widget.initial.stems;
  late String? _fromMarker = _markerOr(widget.initial.fromMarker);
  late String? _toMarker = _markerOr(widget.initial.toMarker);
  late final Set<String> _sectionIds = {
    for (final s in exportSections(_doc))
      if (widget.initial.sectionIds == null || widget.initial.sectionIds!.contains(s.id)) s.id,
  };
  late final Set<String> _trackIds = _initialTracks();
  late final _template = TextEditingController(text: widget.initial.nameTemplate);
  late bool _zip = widget.initial.zip;
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

  /// O id do marcador se ele ainda existe (senão, null: o começo ou o fim).
  String? _markerOr(String? id) => id != null && _doc.markers.any((m) => m.id == id) ? id : null;

  ExportRange _validRange(ExportOptions o) {
    switch (o.range) {
      case ExportRange.loop:
        return _hasLoopRegion(_doc) ? o.range : ExportRange.song;
      case ExportRange.markers:
        final stale = (o.fromMarker != null && _markerOr(o.fromMarker) == null) || (o.toMarker != null && _markerOr(o.toMarker) == null);
        return stale || _doc.markers.isEmpty ? ExportRange.song : o.range;
      case ExportRange.sections:
        return exportSections(_doc).isEmpty ? ExportRange.song : o.range;
      case ExportRange.song:
        return o.range;
    }
  }

  /// As faixas marcadas: as da última exportação que ainda existem (todas se não sobrou nenhuma).
  Set<String> _initialTracks() {
    final all = [for (final t in _doc.tracks) t.id];
    final want = widget.initial.trackIds;
    if (want == null) return all.toSet();
    final kept = all.where(want.contains).toSet();
    return kept.isEmpty ? all.toSet() : kept;
  }

  bool get _allTracks => _trackIds.length == _doc.tracks.length;

  /// As opções como estão na janela agora (a prévia e o botão Exportar usam as mesmas).
  ExportOptions _current() => ExportOptions(
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
    fromMarker: _fromMarker,
    toMarker: _toMarker,
    sectionIds: exportSections(_doc).every((s) => _sectionIds.contains(s.id)) ? null : _sectionIds.toList(),
    trackIds: _allTracks ? null : _trackIds.toList(),
    nameTemplate: _template.text.trim().isEmpty ? kDefaultNameTemplate : _template.text,
    zip: _zip,
  );

  late ExportPlan _plan = planExport(_doc, _current(), project: widget.c.project.name);

  double _spanLen(ExportSpan s) => _doc.tempo.isSingle ? (s.to - s.from) * 60 / _doc.bpm : _doc.secondsAt(s.to) - _doc.secondsAt(s.from);

  /// A duração do maior arquivo (é ele que o servidor e o tamanho do upload limitam).
  double get _spanSeconds => _plan.spans.fold(0.0, (m, s) => math.max(m, _spanLen(s)));

  bool get _empty => _plan.problem != null;

  int get _fileCount => expectedExportFiles(_doc, _current(), _plan);

  int get _effectiveRate => _rate ?? widget.c.engineRate.round();

  /// O servidor recusa arquivo com mais de 30 minutos (a duração já inclui a cauda).
  bool get _tooLongForServer => _format.compressed && !_empty && _spanSeconds + _tail > kEncodeMaxSeconds;

  @override
  void dispose() {
    _artist.dispose();
    _template.dispose();
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

  void _submit() => Navigator.pop(context, _current());

  String _barAt(double beat) {
    final m = _doc.meter;
    return '${m.isSingle ? beat ~/ _doc.beatsPerBar + 1 : m.barOf(beat).$1}';
  }

  String _markerName(Marker m) => '${m.name.trim().isEmpty ? 'Marcador' : m.name.trim()} · compasso ${_barAt(m.beat)}';

  List<Marker> get _sortedMarkers => [..._doc.markers]..sort((a, b) => a.beat.compareTo(b.beat));

  /// A escolha do trecho entre dois marcadores: de onde e até onde (os extremos são o começo e o fim da música).
  List<Widget> _markerPickers(TextStyle muted) {
    final markers = _sortedMarkers;
    DropdownButtonFormField<String?> picker(Key key, String label, String? value, String none, ValueChanged<String?> on) => DropdownButtonFormField<String?>(
      key: key,
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        DropdownMenuItem<String?>(value: null, child: Text(none)),
        for (final m in markers)
          DropdownMenuItem<String?>(
            value: m.id,
            child: Text(_markerName(m), overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (v) => setState(() => on(v)),
    );
    return [
      const SizedBox(height: 12),
      picker(const Key('export-from-marker'), 'De', _fromMarker, 'Início do projeto', (v) => _fromMarker = v),
      const SizedBox(height: 12),
      picker(const Key('export-to-marker'), 'Até', _toMarker, 'Fim da música', (v) => _toMarker = v),
    ];
  }

  /// A lista de seções com uma caixa cada (todas marcadas de início).
  List<Widget> _sectionPickers(TextStyle muted) {
    final sections = exportSections(_doc);
    return [
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(child: Text('${_sectionIds.length} de ${sections.length} seções', style: muted)),
          TextButton(
            key: const Key('export-sections-all'),
            onPressed: () => setState(() => _sectionIds.addAll([for (final s in sections) s.id])),
            child: const Text('Todas'),
          ),
          TextButton(key: const Key('export-sections-none'), onPressed: () => setState(_sectionIds.clear), child: const Text('Nenhuma')),
        ],
      ),
      ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 220),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final s in sections)
                CheckboxListTile(
                  key: Key('export-section-${s.id}'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(s.name, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${_bars(s.from, s.to)} · ${_clock(_spanLen(ExportSpan(from: s.from, to: s.to, label: '', n: 0, base: '')))}'),
                  value: _sectionIds.contains(s.id),
                  onChanged: (v) => setState(() => v == true ? _sectionIds.add(s.id) : _sectionIds.remove(s.id)),
                ),
            ],
          ),
        ),
      ),
    ];
  }

  /// Quais faixas entram: a mixagem é só delas (e os stems também).
  Widget _trackPicker(TextStyle muted) {
    final tracks = _doc.tracks;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: const Key('export-tracks'),
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        title: const Text('Faixas'),
        subtitle: Text(_allTracks ? 'Todas (${tracks.length})' : '${_trackIds.length} de ${tracks.length}', style: muted),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              TextButton(
                key: const Key('export-tracks-all'),
                onPressed: () => setState(() => _trackIds.addAll([for (final t in tracks) t.id])),
                child: const Text('Todas'),
              ),
              if (widget.c.selectedTrack >= 0 && widget.c.selectedTrack < tracks.length)
                TextButton(
                  key: const Key('export-tracks-selected'),
                  onPressed: () => setState(() {
                    _trackIds
                      ..clear()
                      ..add(tracks[widget.c.selectedTrack].id);
                  }),
                  child: const Text('Só a selecionada'),
                ),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in tracks)
                FilterChip(
                  key: Key('export-track-${t.id}'),
                  label: Text(t.name, overflow: TextOverflow.ellipsis),
                  selected: _trackIds.contains(t.id),
                  onSelected: (v) => setState(() => v ? _trackIds.add(t.id) : _trackIds.remove(t.id)),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text('A mixagem leva só as faixas marcadas (o mudo do projeto continua valendo) e os stems também.', style: muted),
        ],
      ),
    );
  }

  /// O modelo do nome dos arquivos e a prévia dos nomes que vão sair.
  List<Widget> _nameFields(TextStyle muted) {
    final spans = _plan.spans;
    final shown = spans.take(3).map((s) => '${s.base}.${_format.extension}').toList();
    return [
      const SizedBox(height: 12),
      _Label('Nome dos arquivos', style: muted),
      TextField(
        key: const Key('export-name-template'),
        controller: _template,
        maxLength: 120,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(helperText: 'Use {projeto}, {marcador} e {n}', helperMaxLines: 2, counterText: ''),
      ),
      if (shown.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            key: const Key('export-name-preview'),
            '${shown.join(', ')}${spans.length > shown.length ? ' e mais ${spans.length - shown.length}' : ''}',
            style: muted,
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall!.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final loop = _hasLoopRegion(_doc);
    _plan = planExport(_doc, _current(), project: widget.c.project.name);
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
                Tooltip(
                  message: _doc.markers.isEmpty ? 'Ponha marcadores na régua para exportar o trecho entre eles' : 'Um trecho entre dois marcadores',
                  child: ChoiceChip(
                    key: const Key('export-range-markers'),
                    label: Text(ExportRange.markers.label),
                    selected: _range == ExportRange.markers,
                    onSelected: _doc.markers.isEmpty ? null : (_) => setState(() => _range = ExportRange.markers),
                  ),
                ),
                Tooltip(
                  message: _doc.markers.isEmpty
                      ? 'Ponha marcadores na régua para dividir a música em seções'
                      : 'Um arquivo por seção, com o nome do marcador',
                  child: ChoiceChip(
                    key: const Key('export-range-sections'),
                    label: Text(ExportRange.sections.label),
                    selected: _range == ExportRange.sections,
                    onSelected: exportSections(_doc).isEmpty
                        ? null
                        : (_) => setState(() {
                            _range = ExportRange.sections;
                            // vários arquivos: o zip é o padrão, mas só até a pessoa mexer nele
                            if (_sectionIds.length > 1) _zip = true;
                          }),
                  ),
                ),
              ],
            ),
            if (_range == ExportRange.markers) ..._markerPickers(muted),
            if (_range == ExportRange.sections) ..._sectionPickers(muted),
            if (_range == ExportRange.markers || _range == ExportRange.sections) ..._nameFields(muted),
            const SizedBox(height: 6),
            Text(
              _empty
                  ? (_trackIds.isEmpty
                        ? _plan.problem!
                        : (_range == ExportRange.song
                              ? 'O projeto ainda não tem clipes.'
                              : (_range == ExportRange.loop ? 'A região do loop está vazia.' : 'Escolha o trecho.')))
                  : _plan.spans.length == 1
                  ? '${_bars(_plan.spans.first.from, _plan.spans.first.to)} · ${_clock(_spanSeconds)}${_tail > 0 ? ' + ${_seconds(_tail)} de cauda' : ''}'
                  : '${_plan.spans.length} arquivos · o maior com ${_clock(_spanSeconds)}${_tail > 0 ? ' + ${_seconds(_tail)} de cauda' : ''}',
              key: const Key('export-span-summary'),
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
            _trackPicker(muted),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Stems'),
              subtitle: Text(tracks == 1 ? 'Um arquivo da faixa, além da mixagem' : 'Um arquivo por faixa, além da mixagem'),
              value: _stems,
              onChanged: (v) => setState(() => _stems = v),
            ),
            if (_fileCount > 1)
              SwitchListTile(
                key: const Key('export-zip'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Reunir num .zip'),
                subtitle: Text('Um arquivo só com os $_fileCount${_stems ? ' (no máximo: faixa sem som não gera stem)' : ''}'),
                value: _zip,
                onChanged: (v) => setState(() => _zip = v),
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
                _trackIds.isEmpty
                    ? 'Não há o que exportar: ${_plan.problem}'
                    : _range == ExportRange.song
                    ? 'Não há o que exportar: grave, importe ou desenhe um clipe primeiro.'
                    : _range == ExportRange.loop
                    ? 'Não há o que exportar: a região do loop não tem duração.'
                    : 'Não há o que exportar: ${_plan.problem}',
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

  /// Com "Reunir num .zip": os arquivos esperam aqui e saem juntos no fim.
  ExportZip? _zip;
  String? _zipName;

  /// Quantos intervalos a exportação tem e qual está no render ("Intervalo 2 de 5: Refrão").
  int _spanCount = 1, _spanIndex = 0;
  String _spanLabel = '';

  /// A pessoa cancelou no meio, sem zip: quantos arquivos já tinham sido salvos.
  int _canceledSaved = 0;

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
    final plan = planExport(c.doc, options, project: c.project.name);
    final expected = plan.problem == null ? expectedExportFiles(c.doc, options, plan) : 1;
    _spanCount = math.max(1, plan.spans.length);
    if (options.zip && expected > 1) {
      _zip = ExportZip();
      _zipName = '${sanitizeExportName(c.project.name)}.zip';
    }
    final zip = _zip;
    Future<bool> zipSave(String name, Uint8List bytes, String mime) async {
      zip!.add(name, bytes);
      return true;
    }

    if (options.format.compressed) {
      _cx = CompressedExport(
        api: widget.api ?? ApiClient.instance,
        options: options,
        album: c.project.name,
        expectedFiles: expected,
        save: zip != null ? zipSave : c.saveExportedFile,
        signedIn: widget.signedIn ?? () => Session.instance.signedIn,
      )..addListener(() => mounted ? setState(() {}) : null);
    }
    try {
      await c.exportAudio(
        options,
        sink: _cx?.deliver ?? (zip == null ? null : (n, b) async => zip.add(n, b)),
        onSpan: (i, n, label) {
          if (!mounted) return;
          setState(() {
            _spanIndex = i;
            _spanCount = n;
            _spanLabel = label;
          });
        },
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
      // vários arquivos soltos: o que já foi salvo antes do cancelamento fica, e a pessoa precisa saber
      final saved = zip != null ? 0 : (_cx?.compressed ?? c.exportSavedCount);
      if (saved == 0) {
        Navigator.pop(context, false);
        return;
      }
      setState(() => _canceledSaved = saved);
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
    // o zip sai quando tudo está pronto; com WAV caído por falta de servidor, espera a pessoa decidir
    var zipCanceled = false;
    if (zip != null && error == null && !pending && !(_cx?.saveCanceled ?? false) && c.exportSaveCanceledName == null) {
      zipCanceled = !await _saveZip();
      if (!mounted) return;
    }
    // WAV direto: o controlador avisa que o "Salvar" foi cancelado; compactado: o CompressedExport
    final saveCanceled = (_cx?.saveCanceled ?? false) || c.exportSaveCanceledName != null || zipCanceled;
    setState(() {
      _saveCanceled = error == null && saveCanceled;
      _fallback = error == null && pending && !saveCanceled;
      _done = error == null && !pending && !saveCanceled;
      _error = error;
      _warning = warning;
    });
  }

  /// Fecha o zip e o entrega pelo caminho do "Salvar" (false se a pessoa fechou a janela do aparelho).
  Future<bool> _saveZip() async {
    final zip = _zip!;
    if (zip.count == 0) return true;
    final ok = await widget.c.saveExportedFile(_zipName!, zip.build(), 'application/zip');
    if (!ok) _zipCanceledName = _zipName;
    return ok;
  }

  String? _zipCanceledName;

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
      var left = _cx!.fallbacks.isNotEmpty;
      if (!left && _zip != null) {
        // os WAV que caíram entram no zip junto dos compactados
        final ok = await _saveZip();
        if (!mounted) return;
        left = !ok;
      }
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

  bool get _running => !_done && _error == null && !_fallback && !_saveCanceled && _canceledSaved == 0;

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
    final canceledName = _zipCanceledName ?? cx?.canceledName ?? widget.c.exportSaveCanceledName;
    final savedBefore = _zip != null ? 0 : (cx != null ? cx.compressed : widget.c.exportSavedCount);
    final stage = cx?.stage;
    final p = _barValue();
    // o texto do render fala do render, não da barra somada
    final render = _progress;
    final Widget body;
    if (_canceledSaved > 0) {
      body = InlineNotice(
        key: const Key('export-canceled-partial'),
        'Exportação cancelada no meio: ${_canceledSaved == 1 ? 'um arquivo já tinha sido salvo e continua' : '$_canceledSaved arquivos já tinham sido salvos e continuam'} '
        'nos downloads ou onde você escolheu. Os outros não foram gerados.',
      );
    } else if (_saveCanceled && !_fallback) {
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
            _zip != null
                ? 'Nada foi salvo ainda: os arquivos ficam prontos para o .zip. Dá para exportar tudo em WAV (os $n que falharam vão em WAV, o resto já compactado) sem renderizar de novo.'
                : cx.compressed > 0
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
          if (_spanCount > 1) ...[
            Text(
              key: const Key('export-span-progress'),
              'Intervalo ${_spanIndex + 1} de $_spanCount${_spanLabel.isEmpty ? '' : ': $_spanLabel'}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
          ],
          Text(
            // o render termina antes do arquivo: no fim ainda falta converter e entregar os bytes
            stage ??
                (render == null
                    ? 'Preparando…'
                    : render >= 1
                    ? 'Salvando o arquivo…'
                    // depois dos 95% o render acabou e a mixagem está sendo medida e normalizada
                    : (render >= 0.95 && widget.options.normalizesLoudness && _spanCount == 1
                          ? 'Medindo o loudness…'
                          : 'Renderizando ${(render * 100).floor()}%')),
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
                  _zip != null
                      ? 'Os ${_zip!.count} arquivos ($format) foram reunidos em "$_zipName" em $secs s. No navegador, o arquivo fica nos downloads.'
                      : _spanCount > 1
                      ? 'Os arquivos de $_spanCount intervalos foram salvos ($format) em $secs s. No navegador, eles ficam nos downloads.'
                      : widget.options.stems
                      ? 'A mixagem e os stems foram salvos ($format) em $secs s. No navegador, os arquivos ficam nos downloads.'
                      : 'A mixagem foi salva ($format) em $secs s. No navegador, o arquivo fica nos downloads.',
                ),
              ),
            ],
          ),
          if (report != null && widget.c.exportReports.length <= 1) ...[
            const SizedBox(height: 12),
            // o que a normalização fez: quando o teto segurou o ganho ou não deu para medir, em aviso
            if (report.limitedByCeiling || report.unmeasurable) InlineNotice(report.describe()) else Text(report.describe()),
          ] else if (report != null) ...[
            const SizedBox(height: 12),
            Text('O loudness foi normalizado em cada um dos ${widget.c.exportReports.length} arquivos.'),
            for (final r in widget.c.exportReports)
              if (r.report.limitedByCeiling || r.report.unmeasurable) ...[const SizedBox(height: 8), InlineNotice('${r.name}: ${r.report.describe()}')],
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
              : _canceledSaved > 0
              ? 'Exportação cancelada'
              : (_saveCanceled ? 'Exportação cancelada' : (_fallback ? 'Não deu para compactar' : (_done ? 'Exportação concluída' : 'A exportação falhou'))),
        ),
        content: SizedBox(width: 400, child: body),
        actions: [
          if (_running)
            TextButton(onPressed: _canceled || (render ?? 0) >= 1 && cx == null ? null : _cancel, child: Text(_canceled ? 'Cancelando…' : 'Cancelar'))
          else if (_canceledSaved > 0)
            FilledButton(onPressed: () => Navigator.pop(context, false), child: const Text('Fechar'))
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
