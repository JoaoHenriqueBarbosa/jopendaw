// Fase 12, item C: correções do mapa de andamento e de compassos (limites, compasso inicial, decimais,
// setas da rampa e compassos pelo mapa), do arquivo .mid e da expressão MIDI.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jopendaw_app/audio/engine.dart';
import 'package:jopendaw_app/daw/controller.dart';
import 'package:jopendaw_app/daw/instruments.dart';
import 'package:jopendaw_app/daw/midi_cc.dart';
import 'package:jopendaw_app/daw/midi_file.dart';
import 'package:jopendaw_app/daw/midi_file_ui.dart';
import 'package:jopendaw_app/daw/model.dart';
import 'package:jopendaw_app/daw/presets.dart';
import 'package:jopendaw_app/daw/tempo_map.dart';

import 'controller_test.dart' show newController;
import 'fake_engine.dart' show FakeEngine, fakeController;
import 'midi_file_test.dart' show eot, smf, vlq;
import 'piano_roll_test.dart' show TestDaw, host, key, mac, riff, settle;
import 'studio_test.dart' show studio, mount, flushSave;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => AudioEngine.instance.log = []);

  group('andamento e compasso', () {
    test('tempos por compasso troca o compasso inicial mesmo quando ele não era n/4', () async {
      final c = newController();
      c.setMeterMap(const [MeterChange(1, 6, 8)]);
      expect(c.doc.meter.first, const MeterChange(1, 6, 8));
      // sem mudar os tempos por compasso, o 6/8 fica
      await c.setTempo(100, c.doc.beatsPerBar);
      expect(c.doc.meter.first, const MeterChange(1, 6, 8));
      expect(c.doc.bpm, 100);
      // mudando, vira n/4 (o compasso mostrado e o do motor acompanham)
      await c.setTempo(100, 5);
      expect(c.doc.meter.first, const MeterChange(1, 5, 4));
      expect(c.doc.meter.barBeats(1), 5);
    });

    test('andamento com decimais chega ao documento e ao motor', () async {
      final c = newController();
      await c.setTempo(120.5, 4);
      expect(c.doc.bpm, 120.5);
      c.setTempoMap(const [TempoPoint(0, 120.5), TempoPoint(8, 90.3)]);
      await c.setTempo(133.7, 4);
      expect(c.doc.tempo.points.first.bpm, 133.7);
      expect(c.doc.bpmAt(0), 133.7);
    });

    test('limites: 4096 pontos de andamento e 1024 mudanças de compasso, com aviso em vez de descarte silencioso', () {
      final c = newController();
      c.setTempoMap([for (var i = 0; i < maxTempoPoints; i++) TempoPoint(i.toDouble(), 100.0 + i % 50)]);
      expect(c.doc.tempo.points.length, maxTempoPoints);
      expect(c.error, isNull);
      c.addTempoPoint(5000.5);
      expect(c.doc.tempo.points.length, maxTempoPoints, reason: 'o 4097º não entra');
      expect(c.error, tempoPointsFullMessage);
      c.error = null;
      // mais do que cabe de uma vez (importação): avisa
      c.setTempoMap([for (var i = 0; i < maxTempoPoints + 3; i++) TempoPoint(i.toDouble(), 100.0)]);
      expect(c.error, contains('limite'));
      expect(c.doc.tempo.points.length, maxTempoPoints);

      c.error = null;
      c.setMeterMap([for (var i = 0; i < maxMeterChanges; i++) MeterChange(i + 1, i.isEven ? 3 : 4, 4)]);
      expect(c.doc.meter.changes.length, maxMeterChanges);
      expect(c.error, isNull);
      c.setMeterAt(maxMeterChanges + 10, 7, 8);
      expect(c.doc.meter.changes.length, maxMeterChanges);
      expect(c.error, meterChangesFullMessage);
      // o 513º ponto não some mais (o limite antigo do app era 512)
      final d = newController();
      d.setTempoMap([for (var i = 0; i < 600; i++) TempoPoint(i.toDouble(), 100.0 + i % 7)]);
      expect(d.doc.tempo.points.length, 600);
    });

    test('a janela de BPM é a mesma do motor, do servidor e da importação (20 a 999)', () {
      final c = newController();
      c.setTempoMap([const TempoPoint(0, 700), const TempoPoint(4, 999)]);
      expect(c.doc.bpm, 700);
      expect(c.doc.tempo.points[1].bpm, 999);
      expect(minBpmInt, 20);
      expect(maxBpmInt, 999);
    });

    test('compasso pelo mapa: clipe novo, enquadrar, encaixe e duração em compassos', () {
      final c = newController();
      c.setMeterMap(const [MeterChange(1, 6, 8), MeterChange(3, 3, 4)]);
      // 6/8 = 3 batidas, 3/4 = 3 batidas; um mapa com 7/8 mostra a diferença
      c.setMeterMap(const [MeterChange(1, 7, 8), MeterChange(3, 5, 4)]);
      expect(c.doc.meter.barBeats(1), 3.5);
      c.doc.tracks.add(DawTrack(id: 'x', name: 'Synth', color: 1, kind: TrackKind.synth));
      final clip = c.createMidiClip(1, 0);
      expect(clip.length, 3.5, reason: 'um compasso 7/8');
      final later = c.createMidiClip(1, 7);
      expect(later.length, 5, reason: 'o compasso 3 é 5/4');
      c.snap = Snap.bar;
      expect(c.snapBeat(3.4), 3.5);
      expect(c.snapBeat(6.9), 7);
      c.viewWidth = 800;
      c.fitRange(0, 1);
      expect(c.pxPerBeat, lessThan(800 / 3.5 + 1), reason: 'o trecho mínimo é um compasso 7/8');
      // spanBars conta pelo mapa
      final m = c.doc.meter;
      expect(m.spanBars(0, 7), (2, 0.0));
      expect(m.spanBars(0, 9), (2, 2.0));
      expect(m.spanBars(7, 5), (1, 0.0));
      expect(m.ceilBarStart(7.1), 12);
      expect(m.ceilBarStart(7), 7);
      expect(m.floorBarStart(9), 7);
    });
  });

  group('interface do andamento', () {
    testWidgets('a seta da rampa desce quando o andamento cai', (t) async {
      final c = studio();
      c.setTempoMap(const [TempoPoint(0, 150, ramp: true), TempoPoint(8, 90)]);
      await mount(t, c, const Size(1400, 900));
      expect(find.text('150↘ BPM · 4/4'), findsOneWidget);
      c.setTempoMap(const [TempoPoint(0, 90, ramp: true), TempoPoint(8, 150)]);
      await t.pump();
      expect(find.text('90↗ BPM · 4/4'), findsOneWidget);
      expect(t.takeException(), isNull);
      await flushSave(t);
    });

    testWidgets('o diálogo aceita decimais e mostra o compasso inicial que não é n/4', (t) async {
      final c = studio();
      c.setMeterMap(const [MeterChange(1, 6, 8)]);
      await mount(t, c, const Size(1400, 900));
      await t.tap(find.text('120 BPM · 6/8'));
      await t.pumpAndSettle();
      expect(find.text('6/8 (atual)'), findsOneWidget);
      await t.enterText(find.byType(TextField).first, '97,5');
      await t.tap(find.text('Salvar'));
      await t.pumpAndSettle();
      expect(c.doc.bpm, 97.5);
      expect(c.doc.meter.first, const MeterChange(1, 6, 8), reason: 'não mexeu nos tempos por compasso');
      // reabre: a fração volta ao campo
      await t.tap(find.text('97,5 BPM · 6/8'));
      await t.pumpAndSettle();
      expect(find.widgetWithText(TextField, '97,5'), findsOneWidget);
      // fora da janela: erro
      await t.enterText(find.byType(TextField).first, '1200');
      await t.tap(find.text('Salvar'));
      await t.pump();
      expect(find.textContaining('Entre 20 e 999'), findsOneWidget);
      expect(t.takeException(), isNull);
      await flushSave(t);
    });
  });

  group('.mid: exportação', () {
    bool has(Uint8List b, List<int> seq) {
      outer:
      for (var i = 0; i + seq.length <= b.length; i++) {
        for (var k = 0; k < seq.length; k++) {
          if (b[i + k] != seq[k]) continue outer;
        }
        return true;
      }
      return false;
    }

    DawTrack track(String name, TrackKind kind, {List<MidiCc> controls = const [], bool mute = false, bool solo = false, double length = 4}) => DawTrack(
      id: name,
      name: name,
      color: 0,
      kind: kind,
      mute: mute,
      solo: solo,
      midi: [
        MidiClip(id: 'c$name', start: 0, length: length, notes: [MidiNote(pitch: 60, start: 0, length: 1, velocity: .8)], controls: [...controls]),
      ],
    );

    test('Program Change pela categoria do preset, RPN 0 com o alcance do bend do instrumento e bateria no canal 10', () {
      final bass = track('Baixo', TrackKind.synth)
        ..params = presetParams(synthPresets.firstWhere((p) => p.category == 'Baixos'), DawTrack(id: 'x', name: 'x', color: 0));
      bass.params[35] = 12; // alcance do bend: 12 semitons
      final lead = track('Lead', TrackKind.synth)
        ..params = presetParams(synthPresets.firstWhere((p) => p.category == 'Leads'), DawTrack(id: 'x', name: 'x', color: 0));
      lead.params[35] = 2.5;
      final kit = track('Bateria', TrackKind.drums);
      final doc = DawDoc(bpm: 120, beatsPerBar: 4, tracks: [bass, lead, kit]);
      expect(midiProgramFor(bass), 38);
      expect(midiProgramFor(lead), 80);
      final b = buildMidiFile(doc).bytes;
      // baixo no canal 1 (0): RPN 0 = 12 semitons e 0 centésimos, depois Program Change 38
      expect(has(b, [0xB0, 101, 0, 0, 0xB0, 100, 0, 0, 0xB0, 6, 12, 0, 0xB0, 38, 0]), isTrue);
      expect(has(b, [0xC0, 38]), isTrue);
      // lead no canal 2 (1): 2 semitons e 50 centésimos, Program Change 80
      expect(has(b, [0xB1, 6, 2, 0, 0xB1, 38, 50]), isTrue);
      expect(has(b, [0xC1, 80]), isTrue);
      // bateria no 10 (índice 9): só o Program Change 0, sem RPN
      expect(has(b, [0xC9, 0]), isTrue);
      expect(has(b, [0xB9, 101, 0]), isFalse);
      // volta pela leitura sem tropeçar nos controles novos
      expect(parseMidiFile(b), completes);
    });

    test('sem preset reconhecido: lead no sintetizador, piano no sampler; o clipe avulso leva a faixa dele', () {
      final synth = track('Synth', TrackKind.synth);
      expect(midiProgramFor(synth), 80);
      expect(midiProgramFor(track('Samp', TrackKind.sampler)), 0);
      final doc = DawDoc(bpm: 120, beatsPerBar: 4, tracks: [synth]);
      final one = buildMidiFile(doc, only: synth.midi.single, onlyTrack: synth).bytes;
      expect(has(one, [0xC0, 80]), isTrue);
      expect(has(one, [0xB0, 6, 2, 0, 0xB0, 38, 0]), isTrue, reason: 'alcance padrão de 2 semitons escrito mesmo assim');
    });

    test('faixa muda não vai para o arquivo (com solo, só as em solo), e a tela diz quais ficaram de fora', () {
      final a = track('A', TrackKind.synth);
      final b = track('B', TrackKind.synth, mute: true);
      final doc = DawDoc(bpm: 120, beatsPerBar: 4, tracks: [a, b]);
      final out = buildMidiFile(doc);
      expect(out.tracks, 1);
      expect(out.silenced, ['B']);
      expect(exportSummary('x.mid', out), contains('Faixas mudas não entraram: B'));
      // solo
      final c2 = track('C', TrackKind.synth);
      final doc2 = DawDoc(bpm: 120, beatsPerBar: 4, tracks: [a, c2..solo = true]);
      final out2 = buildMidiFile(doc2);
      expect(out2.tracks, 1);
      expect(out2.silenced, ['A']);
      // tudo mudo: erro claro
      a.mute = true;
      expect(() => buildMidiFile(DawDoc(bpm: 120, beatsPerBar: 4, tracks: [a])), throwsA(isA<MidiFormatException>()));
      // o clipe avulso ignora o mudo (a pessoa pediu aquele clipe)
      expect(buildMidiFile(doc, only: b.midi.single, onlyTrack: b).tracks, 1);
    });

    test('pontos de controle fora do clipe são contados e avisados', () {
      final t = track(
        'A',
        TrackKind.synth,
        controls: [
          MidiCc(cc: ccBend, beat: 1, value: .5),
          MidiCc(cc: ccBend, beat: 5, value: .5), // depois do fim (4)
          MidiCc(cc: ccSustain, beat: -1, value: 1), // antes do começo
          MidiCc(cc: ccMod, beat: double.nan, value: 1),
        ],
      );
      final out = buildMidiFile(DawDoc(bpm: 120, beatsPerBar: 4, tracks: [t]));
      expect(out.skippedControls, 3);
      expect(exportSummary('x.mid', out), contains('3 pontos de controle'));
    });

    testWidgets('a janela do "salvar como" cancelada não diz "salvo"', (tester) async {
      final c = fakeController(FakeEngine());
      c.doc.tracks.add(track('A', TrackKind.synth));
      var answer = false;
      final saved = <String>[];
      Future<bool?> save(String n, Uint8List b, String m) async {
        saved.add(n);
        return answer;
      }

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExportMidiDialog(c: c, save: save),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('midi-export-go')));
      await tester.pumpAndSettle();
      expect(saved, hasLength(1));
      expect(find.textContaining('salvo'), findsNothing, reason: 'cancelou');
      answer = true;
      await tester.tap(find.byKey(const Key('midi-export-go')));
      await tester.pumpAndSettle();
      expect(saved, hasLength(2));
      expect(find.textContaining('salvo'), findsOneWidget);
    });
  });

  group('.mid: importação', () {
    Uint8List file({bool unnamed = false}) {
      final a = [
        if (!unnamed) ...[0, 0xFF, 3, 5, ...'Piano'.codeUnits],
        0,
        0x90,
        60,
        64,
        ...vlq(480),
        0x80,
        60,
        0,
        ...eot,
      ];
      final b = [0, 0x99, 36, 100, 10, 0x89, 36, 0, ...eot];
      return smf(1, 480, [a, b]);
    }

    test('"Importar como": FM, wavetable ou sampler nas faixas melódicas; a bateria continua bateria', () async {
      for (final k in [TrackKind.synth, TrackKind.fm, TrackKind.wavetable, TrackKind.sampler]) {
        final c = fakeController(FakeEngine());
        final before = c.doc.tracks.length;
        final r = await c.importMidiBytes('x.mid', file(), kind: k, at: 0);
        expect(r, isNotNull);
        final added = c.doc.tracks.sublist(before);
        expect(added.map((t) => t.kind), [k, TrackKind.drums], reason: k.name);
        expect(added.first.midi.single.name, 'Piano', reason: 'o clipe leva o nome da trilha');
      }
    });

    test('o seletor só é chamado se há faixa melódica, lembra a escolha e cancelar não importa nada', () async {
      final c = fakeController(FakeEngine());
      final before = c.doc.tracks.length;
      var asked = 0;
      final r = await c.importMidiBytes('x.mid', file(), chooseKind: (_) async => ++asked > 0 ? TrackKind.wavetable : null, at: 0);
      expect(asked, 1);
      expect(r!.tracks, 2);
      expect(c.doc.tracks[before].kind, TrackKind.wavetable);
      // só bateria: não pergunta
      final drumsOnly = smf(1, 480, [
        [0, 0x99, 36, 100, 10, 0x89, 36, 0, ...eot],
      ]);
      await c.importMidiBytes('d.mid', drumsOnly, chooseKind: (_) async => ++asked > 0 ? TrackKind.fm : null, at: 0);
      expect(asked, 1);
      // cancelar
      final n = c.doc.tracks.length;
      expect(await c.importMidiBytes('x.mid', file(), chooseKind: (_) async => null, at: 0), isNull);
      expect(c.doc.tracks.length, n);
      expect(c.error, isNull);
    });

    test('trilha sem nome: faixa e clipe recebem o mesmo nome', () async {
      final c = fakeController(FakeEngine());
      final before = c.doc.tracks.length;
      await c.importMidiBytes('x.mid', file(unnamed: true), kind: TrackKind.fm, at: 0);
      final t = c.doc.tracks[before];
      expect(t.name, isNotEmpty);
      expect(t.midi.single.name, t.name);
    });

    test('importar um andamento decimal ou acima de 400 BPM mantém o valor (janela do motor)', () async {
      final us = 60000000 ~/ 640;
      final conductor = [0, 0xFF, 0x51, 3, us ~/ 65536 % 256, us ~/ 256 % 256, us % 256, ...eot];
      final c = fakeController(FakeEngine());
      await c.importMidiBytes(
        'x.mid',
        smf(1, 480, [
          conductor,
          [0, 0x90, 60, 64, 10, 0x80, 60, 0, ...eot],
        ]),
        confirmTempo: (_) async => true,
        at: 0,
      );
      expect(c.doc.bpm, closeTo(640, 0.5));
    });
  });

  group('expressão', () {
    Future<DawController> live(FakeEngine e) async {
      final c = fakeController(
        e,
        tracks: [DawTrack(id: 'a', name: 'Áudio', color: 0)],
      );
      c.addInstrumentTrack(TrackKind.synth);
      await c.enableMidiInput();
      e.log = [];
      return c;
    }

    test('soltar o pedal já na faixa nova devolve o repouso à antiga (não fica presa)', () async {
      final e = FakeEngine();
      final c = await live(e);
      c.addInstrumentTrack(TrackKind.synth);
      c.selectedTrack = 1;
      e.onMidi!(0xB0, 64, 127); // pedal embaixo na faixa 1
      c.selectedTrack = 2; // a entrada muda para a faixa 2
      e.log = [];
      e.onMidi!(0xB0, 64, 0); // e solta o pedal
      final sent = e.sent('live_cc');
      expect(sent.any((x) => x[1] == 1 && x[2] == 64 && x[3] == 0.0), isTrue, reason: 'a faixa 1 precisa voltar ao repouso: $sent');
      // nada mais fica fora do repouso: o reset não manda mais nada
      e.log = [];
      e.onMidi!(0xB0, 121, 0);
      expect(e.log, isEmpty);
    });

    test('mesma coisa com o bend', () async {
      final e = FakeEngine();
      final c = await live(e);
      c.addInstrumentTrack(TrackKind.synth);
      c.selectedTrack = 1;
      e.onMidi!(0xE0, 0, 96);
      c.selectedTrack = 2;
      e.log = [];
      e.onMidi!(0xE0, 0, 64); // centro
      expect(e.sent('live_bend'), [
        ['live_bend', 1, 0.0],
        ['live_bend', 2, 0.0],
      ]);
    });

    test('parar devolve ao repouso o que estava ao vivo (pedal, bend e roda)', () async {
      final e = FakeEngine();
      final c = await live(e);
      c.selectedTrack = 1;
      e.onMidi!(0xE0, 0, 96);
      e.onMidi!(0xB0, 1, 100);
      e.onMidi!(0xB0, 64, 127);
      e.log = [];
      final rested = c.liveReset.value;
      await c.stop();
      expect(e.sent('live_bend'), [
        ['live_bend', 1, 0.0],
      ]);
      expect(e.sent('live_cc').map((x) => (x[2], x[3])).toSet(), {(1, 0.0), (64, 0.0)});
      expect(c.liveReset.value, greaterThan(rested), reason: 'as rodas da tela escutam');
      // parar de novo não manda nada
      e.log = [];
      await c.stop();
      expect(e.sent('live_bend'), isEmpty);
      expect(e.sent('live_cc'), isEmpty);
    });

    test('a bateria não manda pontos de controle desenhados à mão ao motor', () {
      final drums = DawTrack(id: 'd', name: 'Kit', color: 0, kind: TrackKind.drums)
        ..midi.add(
          MidiClip(
            id: 'm',
            start: 0,
            length: 4,
            controls: [
              MidiCc(cc: ccBend, beat: 1, value: .5),
              MidiCc(cc: ccSustain, beat: 1, value: 1),
            ],
          ),
        );
      final synth = DawTrack(id: 's', name: 'S', color: 0, kind: TrackKind.synth)
        ..midi.add(
          MidiClip(
            id: 'n',
            start: 0,
            length: 4,
            controls: [MidiCc(cc: ccBend, beat: 1, value: .5)],
          ),
        );
      final out = flattenControls([drums, synth]);
      expect(out.every((x) => x.track == 1), isTrue);
      expect(out, isNotEmpty);
    });

    test('Ctrl+X: cutControls tira os pontos do trecho e não deixa o pedal preso depois dele', () {
      // pedal: embaixo em 0, solta em 1,5 (dentro do trecho 1..2), embaixo de novo em 3
      final ev = [
        MidiCc(cc: ccSustain, beat: 0, value: 1),
        MidiCc(cc: ccSustain, beat: 1.5, value: 0),
        MidiCc(cc: ccSustain, beat: 3, value: 1),
        MidiCc(cc: ccMod, beat: 1.2, value: .7),
      ];
      final out = cutControls(ev, 1, 2);
      // a roda que ficou em 0,7 no trecho continua em 0,7 depois dele (o ponto sai de 1,2 e volta em 2)
      expect(
        [
          for (final e in out)
            if (e.cc == ccMod) (e.beat, e.value),
        ],
        [(2.0, 0.7)],
      );
      // sem o "solta" de 1,5 o pedal seguiria embaixo até 3: entra um "solta" em 2
      expect(controlValueAt(out, ccSustain, 2.5), 0.0);
      expect(controlValueAt(out, ccSustain, 0.5), 1.0);
      // um controle que volta ao repouso dentro do trecho não deixa ponto nenhum
      final back = cutControls([MidiCc(cc: ccBend, beat: 1.2, value: .3), MidiCc(cc: ccBend, beat: 1.5, value: 0)], 1, 2);
      expect(back, isEmpty);
    });

    test('aparar a borda esquerda escreve o estado no começo do clipe', () {
      final orig = [MidiCc(cc: ccSustain, beat: 0.5, value: 1), MidiCc(cc: ccSustain, beat: 3, value: 0), MidiCc(cc: ccBend, beat: 2, value: .4)];
      // o começo anda 1 batida: o pedal (descido em 0,5) segue valendo em 0
      final out = trimControlsLeft(orig, 1);
      final atZero = [
        for (final e in out)
          if (e.beat == 0) (e.cc, e.value),
      ];
      expect(atZero, [(ccSustain, 1.0)]);
      expect(out.where((e) => e.beat < 0).map((e) => e.cc), [ccSustain], reason: 'o ponto de antes fica guardado, mudo');
      // arrastar de volta refaz a partir do original
      expect(trimControlsLeft(orig, 0).length, orig.length);
    });

    mac('Ctrl+X no piano roll leva os pontos de controle do trecho junto e desfaz numa edição só', (t) async {
      t.view.physicalSize = const Size(1200, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final c = TestDaw(notes: riff().take(3).toList());
      c.clip.controls.addAll([
        MidiCc(cc: ccSustain, beat: 0.5, value: 1),
        MidiCc(cc: ccSustain, beat: 1.5, value: 0),
        MidiCc(cc: ccBend, beat: 1, value: .5),
        MidiCc(cc: ccBend, beat: 1.6, value: 0),
        MidiCc(cc: ccMod, beat: 6, value: .9),
      ]);
      await t.pumpWidget(host(c));
      await key(t, LogicalKeyboardKey.keyA, ctrl: true);
      await key(t, LogicalKeyboardKey.keyX, ctrl: true);
      expect(c.clip.notes, isEmpty);
      expect([for (final e in c.clip.controls) e.cc], [ccMod], reason: 'só o que estava fora do trecho fica');
      c.undo();
      expect(c.clip.notes.length, 3);
      expect(c.clip.controls.length, 5, reason: 'recortar é uma edição só');
      await settle(t);
    });
  });
}
