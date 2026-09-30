/// Diálogo da conversão de áudio em notas: envia o áudio, acompanha o job do servidor com
/// progresso e pode ser cancelado. Erros aparecem aqui mesmo, em texto.
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

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      await widget.c.convertToMidi(
        widget.clipId,
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

  @override
  Widget build(BuildContext context) {
    final error = _error;
    return AlertDialog(
      title: const Text('Converter em notas (MIDI)'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: error != null
            ? Text(error)
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
        else
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
