/// Telas do arquivo MIDI (.mid): o importar (áudio e MIDI pelo mesmo seletor, com a pergunta do
/// andamento e os avisos) e a janela de exportar. A lógica está em `midi_file.dart`.
library;

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../audio/engine.dart';
import 'controller.dart';
import 'midi_file.dart';
import 'model.dart';

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
  final report = await c.importMidiBytes(name, bytes, confirmTempo: (d) => askUseFileTempo(context, d, c));
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
      ? 'Usar o andamento do arquivo (${appBpmFor(bpm)} BPM)?'
      : meterChanges > 0
      ? 'Usar os compassos do arquivo ($meterChanges ${meterChanges == 1 ? 'mudança' : 'mudanças'})?'
      : 'Usar o compasso do arquivo?';
  final meter = d.meterMap.isNotEmpty ? d.meterMap.first : null;
  final parts = <String>[
    if (bpm != null) changes > 0 ? '${_bpmText(bpm)} BPM e $changes mudança${changes == 1 ? '' : 's'} de andamento' : '${appBpmFor(bpm)} BPM',
    if (meter != null)
      'compasso ${meter.numerator}/${meter.denominator}${meterChanges > 0 ? ' e $meterChanges mudança${meterChanges == 1 ? '' : 's'} de compasso' : ''}'
    else if (d.beatsPerBar != null)
      'compasso ${d.beatsPerBar}/4',
  ];
  final nc = c.doc.tempoMap.length - 1;
  final now = '${c.doc.bpm.round()} BPM${nc > 0 ? ' e $nc mudança${nc == 1 ? '' : 's'} de andamento' : ''}, ${c.doc.beatsPerBar}/4';
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

String _bpmText(double bpm) {
  final r = bpm.round();
  return (bpm - r).abs() < 0.05 ? '$r' : bpm.toStringAsFixed(1).replaceAll('.', ',');
}

/// Abre a janela de exportar MIDI (.mid): o clipe selecionado ou todas as faixas de notas.
Future<void> showExportMidiDialog(BuildContext context, DawController c, {Future<void> Function(String name, Uint8List bytes, String mime)? save}) =>
    showDialog<void>(
      context: context,
      builder: (_) => ExportMidiDialog(c: c, save: save),
    );

class ExportMidiDialog extends StatefulWidget {
  final DawController c;
  final Future<void> Function(String name, Uint8List bytes, String mime)? save;
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
      await (widget.save ?? AudioEngine.instance.saveFile)(name, out.bytes, 'application/octet-stream');
      if (!mounted) return;
      setState(
        () => _done =
            '$name salvo: ${out.tracks} faixa${out.tracks == 1 ? '' : 's'}, ${out.notes} nota${out.notes == 1 ? '' : 's'}.'
            '${out.skipped > 0 ? ' ${out.skipped} nota${out.skipped == 1 ? '' : 's'} fora do clipe ou de 0–127 ficaram de fora.' : ''}',
      );
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
    final tracks = exportableTracks(c.doc).length;
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
                          ? 'Não há faixas com notas.'
                          : '$tracks faixa${tracks == 1 ? '' : 's'}, uma por canal (bateria no canal 10), nas posições do projeto.',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text('Leva os andamentos e compassos do projeto, as notas e o pitch bend, a modulação e o pedal.', style: Theme.of(context).textTheme.bodySmall),
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
