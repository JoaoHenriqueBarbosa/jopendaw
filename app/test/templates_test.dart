import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:jopendaw_app/daw/instruments.dart';
import 'package:jopendaw_app/daw/model.dart';
import 'package:jopendaw_app/daw/templates.dart';

void main() {
  for (final t in ProjectTemplate.values) {
    test('modelo ${t.label}: documento válido, envios para barramentos que existem, JSON de ida e volta', () {
      final doc = t.build(bpm: 120, beatsPerBar: 4);
      expect(doc.tracks, isNotEmpty);
      final buses = {
        for (final x in doc.tracks)
          if (x.kind == TrackKind.bus) x.id,
      };
      for (final x in doc.tracks) {
        for (final s in x.sends) {
          expect(buses, contains(s.target));
        }
        if (!x.kind.hasClips) expect(x.midi.isEmpty && x.clips.isEmpty, isTrue);
      }
      final again = DawDoc.fromJson(jsonDecode(jsonEncode(doc.toJson())));
      expect(again.tracks.length, doc.tracks.length);
    });
  }

  test('batida eletrônica toca em loop de 4 compassos com bateria, baixo e pad', () {
    final doc = ProjectTemplate.beat.build(bpm: 128, beatsPerBar: 4);
    expect(doc.loopOn, isTrue);
    expect(doc.loopEnd, 16);
    final kinds = doc.tracks.map((t) => t.kind).toList();
    expect(kinds, [TrackKind.drums, TrackKind.synth, TrackKind.synth, TrackKind.bus]);
    for (final t in doc.tracks.where((t) => t.kind.isInstrument)) {
      expect(t.midi.single.notes, isNotEmpty);
      expect(t.midi.single.notes.every((n) => n.start >= 0 && n.end <= 16 + 1e-9), isTrue);
    }
  });

  test('nenhum envio dos modelos nasce mudo (nível 0): ou tem som ou nem existe', () {
    for (final t in ProjectTemplate.values) {
      final doc = t.build(bpm: 120, beatsPerBar: 4);
      for (final x in doc.tracks) {
        for (final s in x.sends) {
          expect(s.level, greaterThan(0), reason: '${t.label}: envio de ${x.name}');
        }
      }
    }
    final band = ProjectTemplate.values.firstWhere((t) => t.label.contains('banda')).build(bpm: 120, beatsPerBar: 4);
    expect(band.tracks.firstWhere((x) => x.name == 'Baixo').sends, isEmpty);
  });
}
