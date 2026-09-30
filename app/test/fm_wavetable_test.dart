// Os instrumentos FM (tipo 5) e wavetable (tipo 6): a tabela de parâmetros, os presets, a faixa no
// documento e o painel de cada um montado de verdade, no computador e no celular.
//
// Que os ids e as faixas são os mesmos do motor quem confere é o teste do lado Rust
// (`faixas_iguais_as_do_app` em `engine/src/fm.rs` e `wavetable.rs`), que lê `instruments.dart`.
import 'dart:convert';

import 'package:flutter/material.dart' hide Curve;
import 'package:flutter_test/flutter_test.dart';
import 'package:jopendaw_app/audio/engine.dart';
import 'package:jopendaw_app/daw/controller.dart';
import 'package:jopendaw_app/daw/instruments.dart';
import 'package:jopendaw_app/daw/model.dart';
import 'package:jopendaw_app/daw/presets.dart';
import 'package:jopendaw_app/models/project.dart';
import 'package:jopendaw_app/screens/project_screen.dart';
import 'package:jopendaw_app/widgets/theme.dart';

DawController studio() {
  final c = DawController(
    Project.fromJson({
      'id': 'p',
      'name': 'Teste',
      'bpm': 120,
      'beats_per_bar': 4,
      'beat_unit': 4,
      'sample_rate': 48000,
      'created_at': '2026-01-01T00:00:00Z',
      'updated_at': '2026-01-01T00:00:00Z',
    }),
  );
  c.doc = DawDoc(
    bpm: 120,
    beatsPerBar: 4,
    tracks: [
      DawTrack(id: 'f', name: 'FM 1', color: 1, kind: TrackKind.fm),
      DawTrack(id: 'w', name: 'Wavetable 1', color: 2, kind: TrackKind.wavetable),
    ],
  );
  c.ready = true;
  return c;
}

Future<void> mount(WidgetTester t, DawController c, Size size) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      theme: buildTheme(),
      home: Scaffold(body: DawStudio(c: c)),
    ),
  );
  await t.pump();
}

void main() {
  setUp(() => AudioEngine.instance.log = []);

  group('tipos de faixa', () {
    test('o índice do enum é o código do motor', () {
      expect(TrackKind.bus.index, 4);
      expect(TrackKind.fm.index, 5);
      expect(TrackKind.wavetable.index, 6);
    });

    test('rótulos, ícones e o que os torna instrumento', () {
      expect(TrackKind.fm.label, 'FM');
      expect(TrackKind.wavetable.label, 'Wavetable');
      for (final k in [TrackKind.fm, TrackKind.wavetable]) {
        expect(k.isInstrument, isTrue);
        expect(k.hasClips, isTrue);
        expect(k.params, isNotEmpty);
        expect(presetsFor(k), isNotEmpty);
      }
    });

    test('persistem no documento pelo nome', () {
      final doc = studio().doc;
      final json = jsonDecode(jsonEncode(doc.toJson())) as Map<String, dynamic>;
      expect([for (final t in json['tracks'] as List) (t as Map)['kind']], ['fm', 'wavetable']);
      final again = DawDoc.fromJson(json);
      expect(again.tracks.map((t) => t.kind), [TrackKind.fm, TrackKind.wavetable]);
      expect(TrackKind.parse('fm'), TrackKind.fm);
      expect(TrackKind.parse('wavetable'), TrackKind.wavetable);
    });

    test('o menu de nova faixa cria as duas, com nome e parâmetros', () {
      final c = studio();
      c.doc.tracks.clear();
      c.addInstrumentTrack(TrackKind.fm);
      c.addInstrumentTrack(TrackKind.wavetable);
      c.addInstrumentTrack(TrackKind.fm);
      expect(c.doc.tracks.map((t) => t.name), ['FM 1', 'Wavetable 1', 'FM 2']);
      expect(c.doc.tracks.map((t) => t.kind), [TrackKind.fm, TrackKind.wavetable, TrackKind.fm]);
    });
  });

  group('tabelas de parâmetros', () {
    for (final (kind, count) in [(TrackKind.fm, 42), (TrackKind.wavetable, 39)]) {
      test('${kind.label}: ids de 0 a ${count - 1}, sem repetir, e o motor guarda até 64', () {
        final ids = [for (final p in kind.params) p.id]..sort();
        expect(ids, List.generate(count, (i) => i));
        expect(count, lessThanOrEqualTo(64));
      });

      test('${kind.label}: padrões dentro da faixa e opções coerentes', () {
        for (final p in kind.params) {
          expect(p.def, inInclusiveRange(p.min, p.max), reason: '${p.group} ${p.name}');
          if (p.curve == Curve.choice) {
            expect(p.options.length, greaterThan(1));
            expect(p.def, lessThan(p.options.length));
          }
        }
        expect(defaultParams(kind).length, count);
      });
    }

    test('FM: cada operador tem os 8 parâmetros na ordem que o motor espera', () {
      for (var n = 0; n < 4; n++) {
        final ps = [for (var k = 0; k < 8; k++) fmParams.firstWhere((p) => p.id == FmId.op(n, k))];
        expect(ps.map((p) => p.group).toSet(), {'Operador ${n + 1}'});
        expect(ps.map((p) => p.name), ['Razão', 'Fino', 'Nível', 'Ataque', 'Decaimento', 'Sustentação', 'Soltura', 'Velocidade']);
        expect(ps[0].min, 0.25);
        expect(ps[0].max, 16);
      }
    });

    test('FM: 8 algoritmos, cada portador sem modular ninguém acima dele', () {
      expect(fmAlgorithmNames.length, 8);
      expect(fmParams.first.options, fmAlgorithmNames);
      for (var a = 0; a < 8; a++) {
        expect(fmAlgorithmCarriers[a], isNonZero);
        for (var op = 0; op < 4; op++) {
          // só operadores de índice menor modulam (o motor calcula 1, 2, 3, 4)
          expect(fmAlgorithmMods[a][op] >> op, 0, reason: 'algoritmo ${a + 1} operador ${op + 1}');
        }
      }
    });

    test('wavetable: séries e posição', () {
      expect(wavetableParams.first.options, ['Clássica', 'Vozes', 'Digital']);
      final pos = wavetableParams.firstWhere((p) => p.id == WtId.osc1Pos);
      expect((pos.min, pos.max), (0, 1));
    });
  });

  group('presets', () {
    for (final (kind, presets) in [(TrackKind.fm, fmPresets), (TrackKind.wavetable, wavetablePresets)]) {
      test('${kind.label}: pelo menos 12, nomes únicos, ids e valores válidos', () {
        expect(presets.length, greaterThanOrEqualTo(12));
        expect({for (final p in presets) p.name}.length, presets.length);
        for (final p in presets) {
          for (final MapEntry(key: id, value: v) in p.values.entries) {
            final spec = kind.params.where((s) => s.id == id);
            expect(spec, hasLength(1), reason: '${p.name}: id $id não existe');
            final s = spec.single;
            expect(v, inInclusiveRange(s.min, s.max), reason: '${p.name}: ${s.group} ${s.name} = $v');
            if (s.curve == Curve.integer || s.curve == Curve.choice) expect(v, v.roundToDouble(), reason: '${p.name}: ${s.name}');
          }
        }
      });

      test('${kind.label}: aplicar um preset dá exatamente aquele preset, e cada um é distinto', () {
        final t = DawTrack(id: 't', name: 'x', color: 0, kind: kind);
        final seen = <String>{};
        for (final p in presets) {
          t.params = presetParams(p, t);
          expect(matchingPreset(t), same(p), reason: p.name);
          expect(seen.add(jsonEncode(t.params.map((k, v) => MapEntry('$k', v)))), isTrue, reason: '${p.name} igual a outro');
        }
      });

      test('${kind.label}: categorias e nomes em português', () {
        expect({for (final p in presets) p.category}.length, greaterThanOrEqualTo(4));
        expect(presets.every((p) => p.name.trim().isNotEmpty && p.category.trim().isNotEmpty), isTrue);
      });
    }

    test('FM: os presets mono têm 1 voz e os pads têm ataque lento', () {
      final bass = fmPresets.firstWhere((p) => p.name == 'Baixo DX');
      expect(bass.values[FmId.voices], 1);
      final strings = fmPresets.firstWhere((p) => p.name == 'Cordas FM');
      expect(strings.values[FmId.op(3, FmId.attack)]!, greaterThan(0.3));
    });

    test('FM: os portadores dos presets estão no nível audível', () {
      for (final p in fmPresets) {
        final alg = (p.values[FmId.algorithm] ?? 4).round();
        final loudest = [
          for (var n = 0; n < 4; n++)
            if (fmAlgorithmCarriers[alg] >> n & 1 == 1) p.values[FmId.op(n, FmId.opLevel)] ?? 0,
        ].fold<double>(0, (m, v) => v > m ? v : m);
        expect(loudest, greaterThanOrEqualTo(0.25), reason: p.name);
      }
    });
  });

  group('painel', () {
    for (final (label, size) in [('computador', const Size(1400, 900)), ('celular', const Size(400, 820))]) {
      testWidgets('$label: monta os dois painéis sem erro e o preset entra no motor', (t) async {
        final c = studio();
        await mount(t, c, size);
        for (final i in [0, 1]) {
          c.selectTrack(i);
          c.setDock(Dock.instrument);
          await t.pump();
          expect(t.takeException(), isNull, reason: 'faixa $i');
          // cada preset aplicado redesenha o painel sem erro
          for (final p in presetsFor(c.doc.tracks[i].kind).take(4)) {
            c.applyPreset(i, presetParams(p, c.doc.tracks[i]));
            await t.pump();
            expect(t.takeException(), isNull, reason: p.name);
          }
        }
        await t.pump(const Duration(seconds: 1));
      });
    }

    testWidgets('FM: tocar num diagrama troca o algoritmo e manda ao motor', (t) async {
      final c = studio();
      await mount(t, c, const Size(1400, 900));
      c.selectTrack(0);
      c.setDock(Dock.instrument);
      await t.pump();
      expect(c.doc.tracks[0].param(FmId.algorithm), 4);
      final tile = find.byTooltip('Algoritmo 6: 1→(2 + 3 + 4)');
      expect(tile, findsOneWidget);
      await t.tap(tile);
      await t.pump();
      expect(c.doc.tracks[0].param(FmId.algorithm), 5);
      final sent = [
        for (final call in AudioEngine.instance.log!)
          if (call.first == 'param') call,
      ];
      expect(sent, contains(equals(['param', 0, FmId.algorithm, 5.0])));
      await t.pump(const Duration(seconds: 1));
    });

    testWidgets('FM: os atalhos de razão mexem no operador certo', (t) async {
      final c = studio();
      await mount(t, c, const Size(1400, 900));
      c.selectTrack(0);
      c.setDock(Dock.instrument);
      await t.pump();
      // cada operador tem a sua fileira; o segundo "×7" é o do operador 2
      final chips = find.text('×7');
      expect(chips, findsNWidgets(4));
      await t.ensureVisible(chips.at(1));
      await t.tap(chips.at(1));
      await t.pump();
      expect(c.doc.tracks[0].param(FmId.op(1, FmId.ratio)), 7);
      expect(c.doc.tracks[0].param(FmId.op(0, FmId.ratio)), 1);
      await t.pump(const Duration(seconds: 1));
    });

    testWidgets('wavetable: o gráfico mostra a tabela da posição', (t) async {
      final c = studio();
      await mount(t, c, const Size(1400, 900));
      c.selectTrack(1);
      c.setDock(Dock.instrument);
      await t.pump();
      // posição padrão 0,3 do oscilador 1: 90% serra e 10% quadrada; o oscilador 2, em 0,5
      expect(find.text('Serra 90% + Quadrada 10%'), findsOneWidget);
      c.setParam(1, WtId.osc1Series, 1);
      c.setParam(1, WtId.osc1Pos, 0);
      await t.pump();
      expect(find.text('A'), findsWidgets);
      await t.pump(const Duration(seconds: 1));
    });
  });
}
