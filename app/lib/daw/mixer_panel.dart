/// O mixer: um canal por faixa (fader, pan, mudo, solo, medidor) e o master no fim.
library;

import 'package:flutter/material.dart';

import '../widgets/theme.dart';
import 'controller.dart';
import 'meter.dart';
import 'model.dart';
import 'timeline.dart' show ToggleChip;

class MixerPanel extends StatelessWidget {
  final DawController c;
  const MixerPanel({super.key, required this.c});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) => Container(
      height: 300,
      decoration: const BoxDecoration(
        color: Palette.bar,
        border: Border(top: BorderSide(color: Palette.hairlineStrong)),
      ),
      child: Row(
        children: [
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(8),
              children: [
                for (var i = 0; i < c.doc.tracks.length; i++)
                  _Strip(
                    c: c,
                    name: c.doc.tracks[i].name,
                    color: trackColorAt(c.doc.tracks[i].color),
                    meterIndex: i,
                    gain: c.doc.tracks[i].gain,
                    pan: c.doc.tracks[i].pan,
                    selected: c.selectedTrack == i,
                    onSelect: () => c.selectTrack(i),
                    onGain: (g) => c.mutate((_) => c.doc.tracks[i].gain = g),
                    onPan: (p) => c.mutate((_) => c.doc.tracks[i].pan = p),
                    mute: c.doc.tracks[i].mute,
                    solo: c.doc.tracks[i].solo,
                    onMute: () => c.edit((d) => d.tracks[i].mute = !d.tracks[i].mute),
                    onSolo: () => c.edit((d) => d.tracks[i].solo = !d.tracks[i].solo),
                  ),
              ],
            ),
          ),
          Container(width: 1, color: Palette.hairlineStrong),
          Padding(
            padding: const EdgeInsets.all(8),
            child: _Strip(
              c: c,
              name: 'Master',
              color: Colors.white,
              meterIndex: -1,
              gain: c.doc.masterGain,
              pan: c.doc.masterPan,
              onGain: (g) => c.mutate((d) => d.masterGain = g),
              onPan: (p) => c.mutate((d) => d.masterPan = p),
            ),
          ),
        ],
      ),
    ),
  );
}

class _Strip extends StatelessWidget {
  final DawController c;
  final String name;
  final Color color;
  final int meterIndex;
  final double gain, pan;
  final bool selected;
  final bool? mute, solo;
  final VoidCallback? onSelect, onMute, onSolo;
  final ValueChanged<double> onGain, onPan;

  const _Strip({
    required this.c,
    required this.name,
    required this.color,
    required this.meterIndex,
    required this.gain,
    required this.pan,
    required this.onGain,
    required this.onPan,
    this.selected = false,
    this.mute,
    this.solo,
    this.onSelect,
    this.onMute,
    this.onSolo,
  });

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.labelSmall!;
    final thin = SliderTheme.of(
      context,
    ).copyWith(trackHeight: 3, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7), overlayShape: const RoundSliderOverlayShape(overlayRadius: 12));
    return GestureDetector(
      onTap: onSelect,
      child: Container(
        width: 88,
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: selected ? Palette.overlay : Palette.raised,
          borderRadius: BorderRadius.circular(8),
          border: Border(top: BorderSide(color: color, width: 3)),
        ),
        child: Column(
          children: [
            // pan
            SliderTheme(
              data: thin.copyWith(trackHeight: 2, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5)),
              child: SizedBox(
                height: 24,
                child: Slider(value: pan, min: -1, max: 1, onChangeStart: (_) => c.checkpoint(), onChanged: (v) => onPan((v.abs() < 0.04) ? 0 : v)),
              ),
            ),
            Text(_panLabel(pan), style: small),
            const SizedBox(height: 4),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SliderTheme(
                    data: thin,
                    child: RotatedBox(
                      quarterTurns: 3,
                      child: Slider(value: gainToFader(gain).clamp(0, 1), onChangeStart: (_) => c.checkpoint(), onChanged: (v) => onGain(faderToGain(v))),
                    ),
                  ),
                  Meter(peaks: c.peaks, index: meterIndex, width: 9),
                ],
              ),
            ),
            GestureDetector(
              onDoubleTap: () {
                c.checkpoint();
                onGain(1);
              },
              child: Text('${formatDb(gain)} dB', style: small.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
            ),
            const SizedBox(height: 4),
            if (mute != null)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ToggleChip(label: 'M', on: mute!, color: Palette.danger, tooltip: 'Mudo', onTap: onMute!),
                  const SizedBox(width: 4),
                  ToggleChip(label: 'S', on: solo!, color: const Color(0xFFE3B341), tooltip: 'Solo', onTap: onSolo!),
                ],
              )
            else
              const SizedBox(height: 20),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: small.copyWith(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _panLabel(double p) {
    if (p.abs() < 0.01) return 'C';
    final v = (p.abs() * 100).round();
    return p < 0 ? 'E$v' : 'D$v';
  }
}
