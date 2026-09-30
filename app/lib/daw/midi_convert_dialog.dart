/// Diálogo da conversão de áudio em notas: primeiro os dois ajustes da análise (nota mínima e nível
/// de silêncio), depois envia o áudio, acompanha o job do servidor com progresso e pode ser cancelado.
/// Erros aparecem aqui mesmo, em texto.
library;

import 'package:flutter/material.dart';

import '../widgets/feedback.dart';
import 'audio_to_midi.dart';
import 'controller.dart';
import 'transport_bar.dart' show describeActionError;

Future<void> showConvertToMidi(BuildContext context, DawController c, String clipId) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _ConvertDialog(c: c, clipId: clipId),
);

class _ConvertDialog extends StatefulWidget {
  final DawController c;
  final String clipId;
  const _ConvertDialog({required this.c, required this.clipId});

  @override
  State<_ConvertDialog> createState() => _ConvertDialogState();
}

class _ConvertDialogState extends State<_ConvertDialog> {
  var _stage = 'Enviando o áudio…';
  double? _progress;
  String? _error;
  bool _cancelled = false;
  bool _started = false;
  var _options = const MidiConvertOptions();

  Future<void> _run() async {
    setState(() => _started = true);
    try {
      await widget.c.convertToMidi(
        widget.clipId,
        options: _options,
        isCancelled: () => _cancelled || !mounted,
        onProgress: (stage, progress) {
          if (!mounted) return;
          setState(() {
            _stage = stage;
            _progress = progress;
          });
        },
      );
      if (mounted) Navigator.pop(context);
    } on ConversionCancelled {
      if (mounted && !_cancelled) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e is StateError ? describeActionError(e) : describeError(e));
    }
  }

  Widget _optionsForm() {
    final (noteLo, noteHi) = MidiConvertOptions.minNoteMsRange;
    final (floorLo, floorHi) = MidiConvertOptions.rmsFloorDbRange;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Funciona melhor com uma voz ou instrumento por vez (monofônico).'),
        const SizedBox(height: 16),
        Text('Nota mínima: ${_options.minNoteMs.round()} ms'),
        Slider(
          key: const Key('convert-min-note'),
          min: noteLo,
          max: noteHi,
          value: _options.minNoteMs.clamp(noteLo, noteHi),
          onChanged: (v) => setState(() => _options = _options.copyWith(minNoteMs: v.roundToDouble())),
        ),
        const Text('Notas mais curtas que isto são descartadas.', style: TextStyle(fontSize: 12, color: Colors.white54)),
        const SizedBox(height: 12),
        Text('Nível de silêncio: ${_options.rmsFloorDb.round()} dB'),
        Slider(
          key: const Key('convert-rms-floor'),
          min: floorLo,
          max: floorHi,
          value: _options.rmsFloorDb.clamp(floorLo, floorHi),
          onChanged: (v) => setState(() => _options = _options.copyWith(rmsFloorDb: v.roundToDouble())),
        ),
        const Text('Trechos abaixo deste nível não viram nota. Suba para ignorar ruído de fundo.', style: TextStyle(fontSize: 12, color: Colors.white54)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    return AlertDialog(
      title: const Text('Converter em notas (MIDI)'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: error != null
            ? Text(error)
            : !_started
            ? _optionsForm()
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_stage),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(value: _progress),
                ],
              ),
      ),
      actions: [
        if (error != null)
          FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Fechar'))
        else if (!_started) ...[
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(onPressed: _run, child: const Text('Converter')),
        ] else
          TextButton(
            onPressed: () {
              _cancelled = true;
              Navigator.pop(context);
            },
            child: const Text('Cancelar'),
          ),
      ],
    );
  }
}
