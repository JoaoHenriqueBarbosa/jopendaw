/// Telas do arquivo MIDI (.mid): o importar (áudio e MIDI pelo mesmo seletor, com a pergunta do
/// andamento e os avisos) e a janela de exportar. A lógica está em `midi_file.dart`.
library;

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../audio/engine.dart';
import 'controller.dart';
import 'instruments.dart' show TrackKind;
import 'midi_file.dart';
import 'model.dart';
import 'tempo_format.dart' show formatBpm, formatDocMeter, formatMeter;

/// Extensões do MIDI no seletor de arquivos.
const midiExtensions = ['mid', 'midi'];

bool isMidiName(String name) {
  final n = name.toLowerCase();
  return midiExtensions.any((e) => n.endsWith('.$e'));
}

/// O "Importar" da barra: um seletor só para áudio e MIDI. Cada áudio vai para uma faixa (como
/// [DawController.importAudio]) e cada .mid vira faixas de notas, com a pergunta do andamento.
Future<void> importFiles(BuildContext context, DawController c) async {
  final files = await FilePicker.pickFiles(
    dialogTitle: 'Importar áudio ou MIDI',
    type: FileType.custom,
    allowedExtensions: [...DawController.audioExtensions, ...midiExtensions],
  );
  if (files.isEmpty) return;
  final audio = <(String, Uint8List)>[];
  final midi = <(String, Uint8List)>[];
  for (final f in files) {
    (isMidiName(f.name) ? midi : audio).add((f.name, await f.readAsBytes()));
  }
  if (audio.isNotEmpty) await c.importBytes(audio);
  for (final (name, bytes) in midi) {
    if (!context.mounted) return;
    await importMidiFlow(context, c, name, bytes);
  }
}

/// Importa um .mid: lê, pergunta pelo andamento se ele difere do projeto e mostra os avisos.
Future<void> importMidiFlow(BuildContext context, DawController c, String name, Uint8List bytes) async {
  final report = await c.importMidiBytes(name, bytes, confirmTempo: (d) => askUseFileTempo(context, d, c), chooseKind: (d) => askImportKind(context, c));
  if (report == null || report.warnings.isEmpty || !context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text('$name importado, com avisos'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${report.tracks} faixa${report.tracks == 1 ? '' : 's'}, ${report.notes} nota${report.notes == 1 ? '' : 's'}.'),
              for (final w in report.warnings) Padding(padding: const EdgeInsets.only(top: 8), child: Text('• $w')),
            ],
          ),
        ),
      ),
      actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Entendi'))],
    ),
  );
}

/// "Importar como": o instrumento das faixas melódicas do arquivo (a bateria do canal 10 é sempre
/// bateria). Devolve null se a pessoa cancelar. Lembra a última escolha ([DawController.midiImportKind]).
Future<TrackKind?> askImportKind(BuildContext context, DawController c) async {
  var kind = c.midiImportKind;
  final r = await showDialog<TrackKind>(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Importar como'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RadioGroup<TrackKind>(
                groupValue: kind,
                onChanged: (v) => setState(() => kind = v ?? kind),
                child: Column(
                  children: [
                    for (final k in midiImportKinds) RadioListTile<TrackKind>(key: Key('midi-import-${k.name}'), value: k, dense: true, title: Text(k.label)),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Vale para as faixas de notas do arquivo; o canal 10 vira Bateria. O Sampler fica mudo até você dar um áudio a ele.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(key: const Key('midi-import-go'), onPressed: () => Navigator.pop(context, kind), child: const Text('Importar')),
        ],
      ),
    ),
  );
  if (r != null) c.midiImportKind = r;
  return r;
}

/// Os instrumentos em que uma faixa melódica do .mid pode entrar.
const midiImportKinds = [TrackKind.synth, TrackKind.fm, TrackKind.wavetable, TrackKind.sampler];

/// "Usar os andamentos do arquivo (N mudanças, a partir de X BPM)?" — true para levar o mapa de
/// andamento e de compassos do arquivo para o projeto.
Future<bool> askUseFileTempo(BuildContext context, MidiFileData d, DawController c) async {
  final pts = d.tempoPoints;
  final bpm = pts.isEmpty ? null : pts.first.bpm;
  final changes = pts.length - 1;
  final meterChanges = d.meterMap.length - 1;
  final title = changes > 0
      ? 'Usar os andamentos do arquivo ($changes ${changes == 1 ? 'mudança' : 'mudanças'}, a partir de ${_bpmText(bpm!)} BPM)?'
      : bpm != null
      ? 'Usar o andamento do arquivo (${_bpmText(bpm)} BPM)?'
      : meterChanges > 0
      ? 'Usar os compassos do arquivo ($meterChanges ${meterChanges == 1 ? 'mudança' : 'mudanças'})?'
      : 'Usar o compasso do arquivo?';
  final meter = d.meterMap.isNotEmpty ? d.meterMap.first : null;
  final parts = <String>[
    if (bpm != null) changes > 0 ? '${_bpmText(bpm)} BPM e $changes mudança${changes == 1 ? '' : 's'} de andamento' : '${_bpmText(bpm)} BPM',
    if (meter != null)
      'compasso ${meter.numerator}/${meter.denominator}${meterChanges > 0 ? ' e $meterChanges mudança${meterChanges == 1 ? '' : 's'} de compasso' : ''}'
    else if (d.beatsPerBar != null)
      'compasso ${formatMeter(d.beatsPerBar!, 4)}',
  ];
  final nc = c.doc.tempoMap.length - 1;
  final now = '${_bpmText(c.doc.bpm)} BPM${nc > 0 ? ' e $nc mudança${nc == 1 ? '' : 's'} de andamento' : ''}, ${formatDocMeter(c.doc)}';
  final r = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: Text('O arquivo traz ${parts.join(' e ')}; o projeto está em $now. As notas ficam nas mesmas batidas, só a velocidade muda.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Manter o do projeto')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Usar o do arquivo')),
      ],
    ),
  );
  return r ?? false;
}

String _bpmText(double bpm) => formatBpm(bpm);

/// O texto de "salvo" com o que ficou de fora: notas e pontos de controle fora do trecho do clipe e
/// faixas mudas.
String exportSummary(String name, MidiExport out) {
  String n(int v, String one, String many) => '$v ${v == 1 ? one : many}';
  return '$name salvo: ${n(out.tracks, 'faixa', 'faixas')}, ${n(out.notes, 'nota', 'notas')}.'
      '${out.skipped > 0 ? ' ${n(out.skipped, 'nota', 'notas')} fora do clipe ou de 0–127 ficaram de fora.' : ''}'
      '${out.skippedControls > 0 ? ' ${n(out.skippedControls, 'ponto de controle', 'pontos de controle')} (bend, modulação ou pedal) fora do clipe ficaram de fora.' : ''}'
      '${out.silenced.isNotEmpty ? ' Faixas mudas não entraram: ${out.silenced.join(', ')}.' : ''}';
}

/// Abre a janela de exportar MIDI (.mid): o clipe selecionado ou todas as faixas de notas.
Future<void> showExportMidiDialog(BuildContext context, DawController c, {Future<bool?> Function(String name, Uint8List bytes, String mime)? save}) =>
    showDialog<void>(
      context: context,
      builder: (_) => ExportMidiDialog(c: c, save: save),
    );

class ExportMidiDialog extends StatefulWidget {
  final DawController c;

  /// Devolve `false` quando a pessoa cancelou o "salvar como" (só o Android sabe dizer).
  final Future<bool?> Function(String name, Uint8List bytes, String mime)? save;
  const ExportMidiDialog({super.key, required this.c, this.save});

  @override
  State<ExportMidiDialog> createState() => _ExportMidiDialogState();
}

class _ExportMidiDialogState extends State<ExportMidiDialog> {
  late bool _all;
  String? _error, _done;
  bool _busy = false;

  (DawTrack, MidiClip)? get _clip {
    final id = widget.c.selectedClip;
    return id == null ? null : widget.c.findMidiClip(id);
  }

  @override
  void initState() {
    super.initState();
    _all = _clip == null;
  }

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _error = null;
      _done = null;
    });
    try {
      final c = widget.c;
      final sel = _clip;
      final title = c.project.name;
      final one = _all ? null : sel;
      final out = one == null ? buildMidiFile(c.doc, title: title) : buildMidiFile(c.doc, only: one.$2, onlyTrack: one.$1, title: title);
      final name = midiFileName(one == null || one.$2.name.isEmpty ? title : one.$2.name);
      // octet-stream como no .jopendaw: com "audio/midi" alguns seletores do Android acrescentam outra extensão
      final saved = await (widget.save ?? AudioEngine.instance.saveFile)(name, out.bytes, 'application/octet-stream');
      if (!mounted) return;
      if (saved == false) {
        // cancelou o "salvar como": nada foi gravado, então nada de "salvo"
        setState(() => _done = null);
        return;
      }
      setState(() => _done = exportSummary(name, out));
    } on MidiFormatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Não deu para salvar o arquivo MIDI.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final sel = _clip;
    final tracks = audibleExportTracks(c.doc).length;
    final silent = exportableTracks(c.doc).length - tracks;
    final clipName = sel?.$2.name ?? '';
    return AlertDialog(
      title: const Text('Exportar MIDI (.mid)'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RadioGroup<bool>(
              groupValue: _all,
              onChanged: (v) => setState(() => _all = v ?? _all),
              child: Column(
                children: [
                  RadioListTile<bool>(
                    key: const Key('midi-export-clip'),
                    value: false,
                    enabled: sel != null && !_busy,
                    title: const Text('Clipe selecionado'),
                    subtitle: Text(
                      sel == null
                          ? 'Selecione um clipe de notas na linha do tempo.'
                          : (clipName.isEmpty ? 'Começa no início do arquivo.' : '$clipName, começa no início do arquivo.'),
                    ),
                  ),
                  RadioListTile<bool>(
                    key: const Key('midi-export-all'),
                    value: true,
                    enabled: tracks > 0 && !_busy,
                    title: const Text('Todas as faixas de notas'),
                    subtitle: Text(
                      tracks == 0
                          ? (silent > 0 ? 'As faixas com notas estão mudas (ou há outra em solo).' : 'Não há faixas com notas.')
                          : '$tracks faixa${tracks == 1 ? '' : 's'}, uma por canal (bateria no canal 10), nas posições do projeto.'
                                '${silent > 0 ? ' $silent muda${silent == 1 ? '' : 's'} (ou fora do solo) não entra${silent == 1 ? '' : 'm'}.' : ''}',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Leva os andamentos e compassos do projeto, as notas, o pitch bend, a modulação e o pedal, o programa de cada faixa e o alcance do bend.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            if (_done != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_done!)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: Text(_done != null ? 'Fechar' : 'Cancelar')),
        FilledButton.icon(
          key: const Key('midi-export-go'),
          onPressed: _busy || (tracks == 0 && sel == null) ? null : _run,
          icon: const Icon(Icons.save_alt),
          label: Text(_done != null ? 'Exportar de novo' : 'Exportar'),
        ),
      ],
    );
  }
}
