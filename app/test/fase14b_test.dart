// Fase 14, item B: tempos por compasso contra o compasso real, .mid (andamento fracionado, limites),
// controles ao vivo no fim da gravação, duplicar zona no limite e a unidade da grade em 6/8 e 7/8.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jopendaw_app/daw/controller.dart';
import 'package:jopendaw_app/daw/instruments.dart';
import 'package:jopendaw_app/daw/midi_file.dart';
import 'package:jopendaw_app/daw/sampler_zones.dart';
import 'package:jopendaw_app/daw/sampler_zones_panel.dart';
import 'package:jopendaw_app/daw/tempo_format.dart';
import 'package:jopendaw_app/daw/tempo_map.dart';

import 'controller_test.dart' show newController;
import 'fake_engine.dart';
import 'midi_file_test.dart' show eot, smf, vlq;
import 'sampler_zones_test.dart' show panelTest, sampler;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('tempos por compasso', () {
    test('em 6/8 escolher 3/4 troca o compasso (3 é o beatsPerBar guardado)', () async {
      final c = newController();
      c.setMeterMap(const [MeterChange(1, 6, 8)]);
      expect(c.doc.beatsPerBar, 3);
      await c.setTempo(100, 3);
      expect(c.doc.meter.first, const MeterChange(1, 3, 4));
    });

    test('em 7/8 escolher 4/4 troca o compasso (3,5 guardado como 4)', () async {
      final c = newController();
      c.setMeterMap(const [MeterChange(1, 7, 8)]);
      expect(c.doc.beatsPerBar, 4);
      await c.setTempo(100, 4);
      expect(c.doc.meter.first, const MeterChange(1, 4, 4));
    });

    test('keepMeter deixa o 6/8 como está e só muda o andamento', () async {
      final c = newController();
      c.setMeterMap(const [MeterChange(1, 6, 8)]);
      await c.setTempo(90, c.doc.beatsPerBar, keepMeter: true);
      expect(c.doc.meter.first, const MeterChange(1, 6, 8));
      expect(c.doc.bpm, 90);
    });
  });

  group('.mid', () {
    test('um andamento só mantém a fração (97,5), e o mapa fica vazio', () {
      final d = MidiFileData(
        format: 0,
        ppq: 480,
        tracks: const [],
        tempoMap: const [MidiTempoPoint(0, 97.5)],
        beatsPerBar: null,
        warnings: [],
        meterMap: const [],
      );
      final t = importedTempo(d)!;
      expect(t.bpm, 97.5);
      expect(t.points, isEmpty);
    });

    test('o compasso do projeto na pergunta é o real (6/8 aparece como 6/8)', () {
      final c = newController();
      c.setMeterMap(const [MeterChange(1, 6, 8)]);
      expect(formatDocMeter(c.doc), '6/8');
    });

    test('limite de fusão em 1024 e primeiro compasso do clipe de 1 a 32', () {
      expect(midiMaxTempoPoints, 1024);
      expect(importedMeterBeats(const MeterChange(1, 13, 4)), 13);
      expect(importedMeterBeats(const MeterChange(1, 64, 4)), 32);
      expect(importedMeterBeats(const MeterChange(1, 1, 32)), 1);
    });

    test('1500 andamentos distintos passam de 256 e cabem até o limite', () {
      final pts = [for (var i = 0; i < 1500; i++) MidiTempoPoint(i.toDouble(), 60 + (i % 100).toDouble() + (i.isEven ? 0 : 3))];
      final out = simplifyTempo(pts);
      expect(out.length, greaterThan(256));
      expect(out.length, lessThanOrEqualTo(midiMaxTempoPoints));
    });

    test('mudanças de compasso além do limite são cortadas com aviso', () async {
      final ev = <int>[0, 0xFF, 0x58, 4, 4, 2, 24, 8];
      for (var i = 1; i <= 1100; i++) {
        ev.addAll([...vlq(60), 0xFF, 0x58, 4, i.isEven ? 4 : 3, 2, 24, 8]);
      }
      ev.addAll([0, 0x90, 60, 64, 5, 0x80, 60, 0, ...eot]);
      final d = await parseMidiFile(smf(1, 1, [ev]));
      expect(d.meterMap.length, maxMeterChanges);
      expect(d.warnings.any((w) => w.contains('mudanças de compasso')), isTrue, reason: d.warnings.join('|'));
    });
  });

  group('gravação', () {
    test('encerrar a gravação devolve pedal, bend e roda ao repouso', () async {
      final e = FakeEngine();
      final c = fakeController(e);
      c.addInstrumentTrack(TrackKind.synth);
      await c.enableMidiInput();
      c.doc.countIn = false;
      c.selectTrack(1);
      c.setArmed(1, true);
      await settle();
      await c.toggleRecord();
      expect(c.recording, isTrue);
      e.onMidi!(0xB0, 64, 127);
      final before = e.sent('live_cc').length;
      await c.toggleRecord();
      expect(c.recording, isFalse);
      final after = e.sent('live_cc');
      expect(after.length, greaterThan(before));
      expect(after.last, ['live_cc', 1, 64, 0.0]);
    });
  });

  group('zonas', () {
    panelTest('duplicar fica desabilitado com 128 zonas, com a dica', (tester) async {
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      late DawController c;
      await tester.runAsync(() async {
        final (cc, _, hash) = await sampler();
        c = cc;
        for (var i = 0; i < maxZones; i++) {
          c.doc.tracks[1].zones.add(SamplerZone(id: 'z$i', sample: hash, root: i % 128, lo: i % 128, hi: i % 128));
        }
        c.mutate((_) {});
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: ListenableBuilder(
                listenable: c,
                builder: (_, _) => SamplerZonesPanel(c: c, track: 1, color: Colors.orange, compact: false),
              ),
            ),
          ),
        ),
      );
      final map = find.byKey(const ValueKey('zone-map'));
      await tester.tapAt(tester.getTopLeft(map) + const Offset(3, 3));
      await tester.pump();
      final btn = find.byWidgetPredicate((w) => w is IconButton && w.icon is Icon && (w.icon as Icon).icon == Icons.copy_outlined);
      expect(btn, findsOneWidget);
      expect(tester.widget<IconButton>(btn).onPressed, isNull);
      expect(tester.widget<IconButton>(btn).tooltip, contains('limite de $maxZones'));
    });
  });

  group('grade', () {
    test('a unidade do compasso é 4/denominador: 0,5 em 6/8 e em 7/8', () {
      expect(const MeterChange(1, 6, 8).unit, 0.5);
      expect(const MeterChange(1, 7, 8).unit, 0.5);
      expect(const MeterChange(1, 6, 8).barBeats, 3);
      expect(const MeterChange(1, 7, 8).barBeats, 3.5);
    });
  });
}
