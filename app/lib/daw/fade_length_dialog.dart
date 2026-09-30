/// Diálogo do tamanho do fade de um clipe de áudio: um campo numérico em milissegundos ou em
/// batidas (o arraste da ponta do clipe continua, mas não dá para digitar um valor exato).
library;

import 'package:flutter/material.dart';

import '../widgets/feedback.dart';
import 'controller.dart';

/// Lê um número digitado com vírgula ou ponto; null se não for um número finito.
double? parseFadeNumber(String text) {
  final v = double.tryParse(text.trim().replaceAll(',', '.'));
  return v != null && v.isFinite ? v : null;
}

String _fmt(double v) {
  final t = v >= 100 ? v.round().toString() : v.toStringAsFixed(v >= 10 ? 1 : 2);
  return t.contains('.') ? t.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '').replaceAll('.', ',') : t;
}

Future<void> showFadeLengthDialog(BuildContext context, DawController c, String clipId, {required bool fadeIn}) => showDialog<void>(
  context: context,
  builder: (_) => FadeLengthDialog(c: c, clipId: clipId, fadeIn: fadeIn),
);

class FadeLengthDialog extends StatefulWidget {
  final DawController c;
  final String clipId;
  final bool fadeIn;
  const FadeLengthDialog({super.key, required this.c, required this.clipId, required this.fadeIn});

  @override
  State<FadeLengthDialog> createState() => _FadeLengthDialogState();
}

class _FadeLengthDialogState extends State<FadeLengthDialog> {
  late final TextEditingController _text;
  bool _beats = false;
  String? _error;

  DawController get c => widget.c;

  /// Batidas por segundo do áudio na ponta do fade (com warp ou mapa de andamento, o vigente ali).
  double get _beatsPerSecond {
    final clip = c.audioClip(widget.clipId);
    if (clip == null) return 2;
    final at = widget.fadeIn ? clip.start : c.doc.clipEnd(clip);
    return c.doc.sourceTempoAt(clip, at) / 60;
  }

  double get _seconds {
    final clip = c.audioClip(widget.clipId);
    return clip == null ? 0 : (widget.fadeIn ? clip.fadeIn : clip.fadeOut);
  }

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: _fmt(_seconds * 1000));
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _unit(bool beats) {
    if (beats == _beats) return;
    final v = parseFadeNumber(_text.text);
    setState(() {
      if (v != null) {
        final secs = _beats ? v / _beatsPerSecond : v / 1000;
        _text.text = _fmt(beats ? secs * _beatsPerSecond : secs * 1000);
      }
      _beats = beats;
      _error = null;
    });
  }

  void _apply() {
    final v = parseFadeNumber(_text.text);
    if (v == null || v < 0) {
      setState(() => _error = 'Digite um número, em ${_beats ? 'batidas' : 'milissegundos'} (0 tira o fade).');
      return;
    }
    final secs = _beats ? v / _beatsPerSecond : v / 1000;
    c.setFadeLength(widget.clipId, fadeIn: widget.fadeIn ? secs : null, fadeOut: widget.fadeIn ? null : secs);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final clip = c.audioClip(widget.clipId);
    final other = clip == null ? 0.0 : (widget.fadeIn ? clip.fadeOut : clip.fadeIn);
    final max = clip == null ? 0.0 : (clip.length - other).clamp(0.0, double.infinity);
    return AlertDialog(
      title: Text(widget.fadeIn ? 'Fade de entrada' : 'Fade de saída'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('fade-length-field'),
                    controller: _text,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: 'Tamanho', suffixText: _beats ? 'batidas' : 'ms'),
                    onSubmitted: (_) => _apply(),
                  ),
                ),
                const SizedBox(width: 12),
                SegmentedButton<bool>(
                  key: const ValueKey('fade-length-unit'),
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: false, label: Text('ms')),
                    ButtonSegment(value: true, label: Text('batidas')),
                  ],
                  selected: {_beats},
                  onSelectionChanged: (s) => _unit(s.first),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'No máximo ${_fmt(max * 1000)} ms (o que sobra do clipe depois do outro fade). 0 tira o fade. '
              'Mudar o tamanho aqui faz o fade deixar de ser o automático do crossfade.',
              style: Theme.of(context).textTheme.bodySmall!.copyWith(color: Colors.white60),
            ),
            if (_error != null) ...[const SizedBox(height: 8), InlineNotice(_error!)],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(key: const ValueKey('fade-length-apply'), onPressed: _apply, child: const Text('Aplicar')),
      ],
    );
  }
}
