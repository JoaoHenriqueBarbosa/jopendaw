/// Diálogo do warp de um clipe de áudio: ajustar ao andamento do projeto (detecta o andamento do
/// áudio, mostra o resultado e a confiança, e deixa corrigir digitando ou dobrando/dividindo),
/// transposição em semitons, inverter e desligar. As mudanças valem na hora; o som novo é gerado
/// em segundo plano e o clipe mostra "processando…" até ficar pronto.
library;

import 'package:flutter/material.dart';

import '../widgets/feedback.dart';
import 'controller.dart';
import 'tempo_format.dart' show formatBpm, formatPitch;
import 'transport_bar.dart' show describeActionError;

export 'tempo_format.dart' show formatBpm;

Future<void> showWarpDialog(BuildContext context, DawController c, String clipId) => showDialog<void>(
  context: context,
  builder: (_) => _WarpDialog(c: c, clipId: clipId),
);

/// "120,5" ou "120.5" → 120.5; null se não for um andamento válido (20..999).
double? parseBpm(String text) {
  final v = double.tryParse(text.trim().replaceAll(',', '.'));
  if (v == null || !v.isFinite || v < 20 || v > 999) return null;
  return v;
}

class _WarpDialog extends StatefulWidget {
  final DawController c;
  final String clipId;
  const _WarpDialog({required this.c, required this.clipId});

  @override
  State<_WarpDialog> createState() => _WarpDialogState();
}

class _WarpDialogState extends State<_WarpDialog> {
  final _bpm = TextEditingController();
  bool _detecting = false;
  String? _error;
  String? _detected;

  @override
  void initState() {
    super.initState();
    final source = widget.c.audioClip(widget.clipId)?.sourceBpm;
    if (source != null) _bpm.text = formatBpm(source);
  }

  @override
  void dispose() {
    _bpm.dispose();
    super.dispose();
  }

  Future<void> _detect() async {
    setState(() {
      _detecting = true;
      _error = null;
      _detected = null;
    });
    try {
      final r = await widget.c.detectClipBpm(widget.clipId);
      if (!mounted) return;
      if (r == null) {
        setState(() => _error = 'O áudio deste clipe não está neste aparelho.');
      } else if (r.bpm <= 0) {
        setState(() => _error = 'Não deu para achar o andamento (pouca batida ou trecho curto). Digite o andamento do áudio.');
      } else {
        final bpm = (r.bpm * 10).round() / 10;
        _bpm.text = formatBpm(bpm);
        setState(
          () => _detected = '${formatBpm(bpm)} BPM, confiança ${(r.confidence * 100).round()}%${r.confidence < 0.35 ? ' (baixa: confira de ouvido)' : ''}',
        );
        widget.c.setClipWarp(widget.clipId, warp: true, sourceBpm: bpm);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e is StateError || e is UnsupportedError ? describeActionError(e) : describeError(e));
    } finally {
      if (mounted) setState(() => _detecting = false);
    }
  }

  /// Aplica o andamento digitado e liga o warp.
  void _apply() {
    final v = parseBpm(_bpm.text);
    if (v == null) {
      setState(() => _error = 'Digite um andamento entre 20 e 999 BPM.');
      return;
    }
    setState(() => _error = null);
    widget.c.setClipWarp(widget.clipId, warp: true, sourceBpm: v);
  }

  void _scale(double k) {
    final v = parseBpm(_bpm.text);
    if (v == null) return;
    final next = (v * k).clamp(20.0, 999.0);
    _bpm.text = formatBpm((next * 10).round() / 10);
    _apply();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.c,
    builder: (context, _) {
      final clip = widget.c.audioClip(widget.clipId);
      if (clip == null) return const AlertDialog(content: Text('O clipe não existe mais.'));
      final small = Theme.of(context).textTheme.labelSmall!.copyWith(color: Colors.white54, letterSpacing: 0.6);
      final pending = widget.c.warpPending(clip);
      final failure = widget.c.warpFailure(clip);
      return AlertDialog(
        title: const Text('Warp e altura'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ANDAMENTO', style: small),
                const SizedBox(height: 8),
                Row(
                  children: [
                    SizedBox(
                      width: 110,
                      child: TextField(
                        controller: _bpm,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'BPM do áudio', isDense: true),
                        onSubmitted: (_) => _apply(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(tooltip: 'Metade (÷2)', onPressed: () => _scale(0.5), icon: const Text('÷2')),
                    IconButton(tooltip: 'Dobro (×2)', onPressed: () => _scale(2), icon: const Text('×2')),
                    const Spacer(),
                    OutlinedButton(onPressed: _detecting ? null : _detect, child: Text(_detecting ? 'Analisando…' : 'Detectar')),
                  ],
                ),
                if (_detected != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('Detectado: $_detected', style: const TextStyle(fontSize: 12)),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    FilledButton(onPressed: _apply, child: const Text('Ajustar ao andamento')),
                    const SizedBox(width: 8),
                    if (clip.warp) TextButton(onPressed: () => widget.c.setClipWarp(widget.clipId, warp: false), child: const Text('Desligar o warp')),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  clip.stretches
                      ? (widget.c.doc.tempo.isSingle
                            ? 'Segue o andamento do projeto (${formatBpm(widget.c.doc.bpm)} BPM): o áudio é esticado sem mudar a altura.'
                            : 'O projeto tem mudanças de andamento: o warp estica o áudio para o andamento INICIAL (${formatBpm(widget.c.doc.bpm)} BPM) e ele '
                                  'toca em velocidade constante, sem acompanhar as mudanças.')
                      : 'Sem warp: o clipe toca na velocidade original.',
                  style: const TextStyle(fontSize: 12, color: Colors.white60),
                ),
                const SizedBox(height: 16),
                Text('ALTURA', style: small),
                const SizedBox(height: 4),
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Um semitom abaixo',
                      onPressed: clip.pitch > -24 ? () => widget.c.setClipWarp(widget.clipId, pitch: clip.pitch - 1) : null,
                      icon: const Icon(Icons.remove),
                    ),
                    SizedBox(
                      width: 96,
                      child: Text(
                        '${clip.pitch > 0 ? '+' : ''}${formatPitch(clip.pitch)} st',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Um semitom acima',
                      onPressed: clip.pitch < 24 ? () => widget.c.setClipWarp(widget.clipId, pitch: clip.pitch + 1) : null,
                      icon: const Icon(Icons.add),
                    ),
                    const Spacer(),
                    TextButton(onPressed: clip.pitch == 0 ? null : () => widget.c.setClipWarp(widget.clipId, pitch: 0), child: const Text('Zerar')),
                  ],
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Inverter o áudio'),
                  value: clip.reverse,
                  onChanged: (v) => widget.c.setClipWarp(widget.clipId, reverse: v),
                ),
                if (pending) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
                if (pending)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text('processando…', style: TextStyle(fontSize: 12, color: Colors.white60)),
                  ),
                if (failure != null)
                  Padding(padding: const EdgeInsets.only(top: 8), child: InlineNotice('O warp não ficou pronto ($failure): o clipe toca o original.')),
                if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: InlineNotice(_error!)),
              ],
            ),
          ),
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Fechar'))],
      );
    },
  );
}
