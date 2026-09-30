import 'package:flutter_test/flutter_test.dart';
import 'package:jopendaw_app/daw/controller.dart';
import 'package:jopendaw_app/daw/effects.dart';
import 'package:jopendaw_app/daw/midi_map.dart';
import 'package:jopendaw_app/daw/modulation.dart';
import 'package:jopendaw_app/daw/model.dart';
import 'package:jopendaw_app/daw/project_file.dart';
import 'package:jopendaw_app/models/project.dart';

import 'fake_engine.dart';

Project _project(int num, int den) => Project.fromJson({
  'id': 'p',
  'name': 'Teste',
  'bpm': 120,
  'beats_per_bar': num,
  'beat_unit': den,
  'sample_rate': 48000,
  'created_at': '2026-01-01T00:00:00Z',
  'updated_at': '2026-01-01T00:00:00Z',
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('fase 17 (A): efeitos', () {
    test('cruzamentos: a mesma regra do motor (o alto 1,5× acima do baixo) e o valor efetivo é o que fica', () {
      expect(effectiveCrossovers(150, 3000), (150.0, 3000.0));
      expect(effectiveCrossovers(800, 1000), (800.0, 1200.0));
      final c = fakeController(FakeEngine());
      c.addEffect(0, EffectKind.multiband);
      final slot = c.doc.tracks[0].effects.single;
      c.setEffectParam(0, slot.id, 1, 1000);
      // subir o baixo até o máximo do knob: fica em 1000 / 1,5
      c.setEffectParam(0, slot.id, 0, 800);
      expect(slot.param(0), closeTo(1000 / 1.5, 1e-6));
      // descer o alto abaixo de 1,5× o baixo: sobe até lá
      c.setEffectParam(0, slot.id, 1, 5000);
      c.setEffectParam(0, slot.id, 0, 700);
      c.setEffectParam(0, slot.id, 1, 1000);
      expect(slot.param(1), closeTo(1050, 1e-6));
      // longe dos extremos nada muda
      c.setEffectParam(0, slot.id, 1, 5000);
      c.setEffectParam(0, slot.id, 0, 200);
      expect((slot.param(0), slot.param(1)), (200.0, 5000.0));
      // a imagem estéreo tem a mesma regra (o baixo vai a 1000 Hz, o alto começa em 1000)
      c.addEffect(0, EffectKind.imager);
      final img = c.doc.tracks[0].effects.last;
      c.setEffectParam(0, img.id, 1, 1000);
      c.setEffectParam(0, img.id, 0, 1000);
      expect(img.param(0), closeTo(1000 / 1.5, 1e-6));
    });

    test('aviso de solo e de "Ouvir banda": só com o efeito ligado', () {
      expect(effectMonitoringNote(EffectKind.multiband, {}), isNull);
      expect(effectMonitoringNote(EffectKind.multiband, {multibandBase + 2 * multibandStride + 5: 1}), 'solo');
      expect(effectMonitoringNote(EffectKind.multiband, {multibandBase + 5: 1}, bypass: true), isNull);
      expect(effectMonitoringNote(EffectKind.deesser, {7: 1}), 'ouvindo a banda');
      expect(effectMonitoringNote(EffectKind.deesser, {7: 0}), isNull);
      expect(effectMonitoringNote(EffectKind.compressor, {7: 1}), isNull);
    });

    test('os padrões de banda do multibanda são os do app', () {
      final p = {for (final s in multibandParams) s.id: s.def};
      expect([for (var b = 0; b < 3; b++) p[multibandBase + b * multibandStride]], [-24.0, -22.0, -20.0]);
      expect([for (var b = 0; b < 3; b++) p[multibandBase + b * multibandStride + 1]], [3.0, 3.0, 3.0]);
    });
  });

  group('fase 17 (A): tempo e compasso', () {
    test('_fresh: um projeto sem documento converte o compasso em semínimas e o mapa guarda o compasso exato', () async {
      for (final (num, den, quarters) in [(6, 8, 3), (7, 8, 4), (3, 4, 3), (4, 4, 4), (2, 2, 4)]) {
        final c = DawController(_project(num, den), engine: FakeEngine(), store: MemoryStore());
        await c.open();
        expect(c.doc.beatsPerBar, quarters, reason: '$num/$den');
        final m = c.doc.meter.changeAt(1);
        expect((m.numerator, m.denominator), (num, den), reason: '$num/$den');
        expect(c.doc.loopEnd, num * 4.0 * 4 / den, reason: '$num/$den');
        c.dispose();
      }
    });

    test('o documento novo de um 6/8 reproduz o do projeto: nada a espelhar no servidor', () async {
      final c = DawController(_project(6, 8), engine: FakeEngine(), store: MemoryStore());
      await c.open();
      expect(c.tempoPending, isFalse);
      c.dispose();
    });
  });

  group('fase 17 (A): remapDocIds', () {
    test('refaz os ids dos mapeamentos MIDI e dos moduladores (o que repete ou é inseguro)', () {
      final doc = DawDoc(
        bpm: 120,
        beatsPerBar: 4,
        tracks: [
          DawTrack(id: 'a', name: 'A', color: 0)..modulation = TrackModulation([ModSource(id: 'lfo 1')]),
          DawTrack(id: 'b', name: 'B', color: 0)..modulation = TrackModulation([ModSource(id: 'lfo 1')]),
        ],
      );
      doc.masterModulation = TrackModulation([ModSource(id: 'a')]);
      const cc = MidiSource(MidiSourceKind.cc, 0, 1);
      doc.midiMap.items.addAll([
        MidiMapping(id: 'a', source: cc, trackId: 'a', target: const AutoTarget(AutoKind.volume)),
        MidiMapping(id: 'a', source: cc, trackId: 'b', target: const AutoTarget(AutoKind.volume)),
      ]);
      remapDocIds(doc);
      final ids = [
        for (final t in doc.tracks) t.id,
        for (final t in doc.tracks)
          for (final s in t.modulation.sources) s.id,
        for (final s in doc.masterModulation.sources) s.id,
        for (final m in doc.midiMap.items) m.id,
      ];
      expect(ids.toSet().length, ids.length, reason: 'nenhum id repetido: $ids');
      expect(doc.midiMap.items[0].trackId, doc.tracks[0].id);
      expect(doc.midiMap.items[1].trackId, doc.tracks[1].id);
    });
  });
}
