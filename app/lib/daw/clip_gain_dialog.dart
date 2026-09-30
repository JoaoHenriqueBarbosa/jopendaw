/// Diálogo do ganho de um clipe de áudio: slider em dB (−40 a +12; no piso o clipe fica mudo).
/// A mudança vale na hora (som e onda) e cada arraste é um passo do desfazer.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'controller.dart';

const clipGainMinDb = -40.0;
const clipGainMaxDb = 12.0;

/// dB → ganho linear; o piso do slider é silêncio.
double clipGainFromDb(double db) => db <= clipGainMinDb ? 0 : math.pow(10, db / 20).toDouble();

/// Ganho linear → dB dentro do slider (silêncio fica no piso).
double clipGainToDb(double gain) => gain <= 0 ? clipGainMinDb : (20 * math.log(gain) / math.ln10).clamp(clipGainMinDb, clipGainMaxDb).toDouble();

String formatClipGainDb(double gain) {
  final db = clipGainToDb(gain);
  if (db <= clipGainMinDb) return '−∞ dB (mudo)';
  final t = db.abs() < 0.05 ? '0,0' : db.abs().toStringAsFixed(1).replaceAll('.', ',');
  final sign = db > 0.05 ? '+' : (db < -0.05 ? '−' : '');
  return '$sign$t dB';
}

Future<void> showClipGainDialog(BuildContext context, DawController c, String clipId) => showDialog<void>(
  context: context,
  builder: (_) => ClipGainDialog(c: c, clipId: clipId),
);

class ClipGainDialog extends StatefulWidget {
  final DawController c;
  final String clipId;
  const ClipGainDialog({super.key, required this.c, required this.clipId});

  @override
  State<ClipGainDialog> createState() => _ClipGainDialogState();
}

class _ClipGainDialogState extends State<ClipGainDialog> {
  late double _db = clipGainToDb(widget.c.audioClip(widget.clipId)?.gain ?? 1);

  void _apply(double db) {
    setState(() => _db = db);
    widget.c.setClipGain(widget.clipId, clipGainFromDb(db), undoable: false);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Ganho do clipe'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(formatClipGainDb(clipGainFromDb(_db)), style: Theme.of(context).textTheme.titleMedium),
            Slider(
              key: const Key('clip-gain-slider'),
              min: clipGainMinDb,
              max: clipGainMaxDb,
              divisions: ((clipGainMaxDb - clipGainMinDb) * 2).round(),
              value: _db,
              onChangeStart: (_) => widget.c.checkpoint('Ganho do clipe'),
              onChanged: _apply,
            ),
            const Text('Só este clipe; o volume da faixa continua à parte.', style: TextStyle(fontSize: 12, color: Colors.white54)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _db == 0
              ? null
              : () {
                  widget.c.setClipGain(widget.clipId, 1);
                  setState(() => _db = 0);
                },
          child: const Text('Zerar (0 dB)'),
        ),
        FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Fechar')),
      ],
    );
  }
}
