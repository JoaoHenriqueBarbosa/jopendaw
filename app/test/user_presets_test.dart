// Presets do usuário: modelo e guardado (ida e volta, substituir, renomear, apagar, nomes hostis,
// isolamento por tipo), o `.jopreset` (exportar e importar arquivo bom e ruim) e o menu dos
// painéis de instrumento e de efeitos com um preset do usuário.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart' hide Curve;
import 'package:flutter_test/flutter_test.dart';
import 'package:jopendaw_app/daw/effects.dart';
import 'package:jopendaw_app/daw/effects_panel.dart';
import 'package:jopendaw_app/daw/instrument_panel.dart';
import 'package:jopendaw_app/daw/instruments.dart';
import 'package:jopendaw_app/daw/model.dart';
import 'package:jopendaw_app/daw/presets.dart';
import 'package:jopendaw_app/daw/user_presets.dart';
import 'package:jopendaw_app/daw/user_presets_ui.dart';
import 'package:jopendaw_app/widgets/theme.dart';

import 'fake_engine.dart';
import 'rack_test.dart' show RackDaw;

Uint8List file(Map<String, dynamic> j) => Uint8List.fromList(utf8.encode(jsonEncode(j)));

Map<String, dynamic> good({Object? name = 'Meu som', String kind = 'synth', String family = 'instrument', Map<String, dynamic>? params, Object? version = 1}) =>
    {
      'format': 'jopendaw-preset',
      'version': version,
      'family': family,
      'kind': kind,
      'name': name,
      'params': params ?? {'${SynthId.cutoff}': 900.0, '${SynthId.resonance}': 0.4},
    };

UserPresets fresh() => UserPresets(MemoryUserPresetStorage());

double _round(ParamSpec spec, double v) => spec.curve == Curve.choice ? spec.clamp(v).roundToDouble() : v;

void main() {
  group('nomes', () {
    test('controle, espaços e tamanho', () {
      expect(cleanPresetName('  a\u0000b\n\tc  '), 'a b c');
      expect(cleanPresetName('\u0007\u202e​ '), '');
      expect(cleanPresetName('x' * 500).length, maxUserPresetName);
      // não corta um par substituto (emoji) ao meio
      final cut = cleanPresetName('${'a' * 59}😀😀');
      expect(cut.runes.length, 60);
      expect(cut.endsWith('😀'), isTrue);
      expect(presetFileName('../../x').contains('/'), isFalse);
      expect(presetFileName('a:b*c'), 'a_b_c.jopreset');
      expect(presetFileName('  '), 'preset.jopreset');
      expect(presetFileName('...oculto'), 'oculto.jopreset');
    });

    test('nome vazio ou só controle é recusado; hostil vira texto inofensivo', () {
      final s = fresh();
      final v = UserPresets.capture(PresetFamily.instrument, 'synth', (id) => 0);
      expect(() => s.save(PresetFamily.instrument, 'synth', '   ', v), throwsA(isA<PresetFormatException>()));
      expect(() => s.save(PresetFamily.instrument, 'synth', '\u0000\n', v), throwsA(isA<PresetFormatException>()));
      final p = s.save(PresetFamily.instrument, 'synth', '<script>alert(1)</script>\u0000${'z' * 200}', v)!;
      expect(p.name.length, maxUserPresetName);
      expect(p.name.contains('\u0000'), isFalse);
    });
  });

  group('guardado', () {
    test('ida e volta: salvar, reabrir do arquivo e carregar dá os mesmos parâmetros', () async {
      final storage = MemoryUserPresetStorage();
      final s = UserPresets(storage);
      final t = DawTrack(id: 't', name: 'S', color: 0, kind: TrackKind.synth);
      t.params[SynthId.cutoff] = 1234.5;
      t.params[SynthId.osc1Wave] = 2;
      final v = UserPresets.capture(PresetFamily.instrument, 'synth', t.param);
      expect(v.length, synthParams.length);
      s.save(PresetFamily.instrument, 'synth', 'Pad meu', v);
      await s.flush();

      final s2 = UserPresets(storage);
      await s2.load();
      final p = s2.ofTrack(TrackKind.synth).single;
      expect(p.name, 'Pad meu');
      final other = DawTrack(id: 'o', name: 'O', color: 0, kind: TrackKind.synth);
      expect(UserPresets.paramsFor(p, other), {for (final spec in synthParams) spec.id: t.param(spec.id)});
      // e o rótulo: a faixa que recebeu o preset casa com ele
      other.params = UserPresets.paramsFor(p, other);
      expect(s2.matchingTrack(other)?.name, 'Pad meu');
      other.params[SynthId.cutoff] = 100;
      expect(s2.matchingTrack(other), isNull);
    });

    test('todos os instrumentos e os 12 efeitos: capturar → aplicar é identidade', () {
      final s = fresh();
      for (final k in TrackKind.values.where((k) => k.isInstrument)) {
        final t = DawTrack(id: 't', name: 'x', color: 0, kind: k);
        for (final spec in k.params) {
          t.params[spec.id] = _round(spec, spec.clamp(spec.min + (spec.max - spec.min) * 0.37));
        }
        final p = s.save(PresetFamily.instrument, k.name, 'p', UserPresets.capture(PresetFamily.instrument, k.name, t.param))!;
        final back = UserPresets.paramsFor(p, DawTrack(id: 'u', name: 'y', color: 0, kind: k));
        for (final spec in k.params) {
          if (k == TrackKind.sampler && (spec.id == SamplerId.root || spec.id == SamplerId.tune)) continue;
          expect(back[spec.id], closeTo(t.param(spec.id), 1e-9), reason: '${k.name} ${spec.id}');
        }
        expect(s.matchingTrack(DawTrack(id: 'm', name: 'm', color: 0, kind: k)..params = back)?.id, p.id);
      }
      for (final k in EffectKind.values) {
        final slot = EffectSlot(id: 'e', kind: k);
        for (final spec in k.params) {
          slot.params[spec.id] = _round(spec, spec.clamp(spec.min + (spec.max - spec.min) * 0.61));
        }
        final p = s.save(PresetFamily.effect, k.name, 'p', UserPresets.capture(PresetFamily.effect, k.name, slot.param))!;
        final back = UserPresets.paramsForEffect(p, EffectSlot(id: 'f', kind: k));
        expect(back.length, k.params.length);
        for (final spec in k.params) {
          if ((k == EffectKind.compressor && spec.id == 10) || (k == EffectKind.gate && spec.id == 6)) continue;
          expect(back[spec.id]!, closeTo(slot.param(spec.id), 1e-9), reason: '${k.name} ${spec.id}');
        }
        expect(
          s.matchingEffect(EffectSlot(id: 'm', kind: k, params: back))?.id,
          p.id,
          reason: k.name,
        );
      }
    });

    test('EQ guarda as 8 bandas; sidechain fica o do slot; sampler não leva nota base nem afinação', () {
      final s = fresh();
      final eq = EffectSlot(id: 'e', kind: EffectKind.eq);
      eq.params[7 * 6 + 2] = 9999;
      final p = s.save(PresetFamily.effect, 'eq', 'oito', UserPresets.capture(PresetFamily.effect, 'eq', eq.param))!;
      expect(p.values.length, eqParams.length);
      expect(p.values[7 * 6 + 2], 9999);

      final comp = EffectSlot(id: 'c', kind: EffectKind.compressor);
      comp.params[10] = 3;
      final pc = s.save(PresetFamily.effect, 'compressor', 'c', UserPresets.capture(PresetFamily.effect, 'compressor', comp.param))!;
      expect(pc.values.containsKey(10), isFalse);
      final other = EffectSlot(id: 'd', kind: EffectKind.compressor)..params[10] = 5;
      expect(UserPresets.paramsForEffect(pc, other)[10], 5);
      expect(s.matchingEffect(other..params[10] = 7), isNotNull, reason: 'o sidechain não conta no rótulo');

      final smp = DawTrack(id: 's', name: 's', color: 0, kind: TrackKind.sampler);
      smp.params[SamplerId.attack] = 0.7;
      smp.params[SamplerId.root] = 40;
      final ps = s.save(PresetFamily.instrument, 'sampler', 'env', UserPresets.capture(PresetFamily.instrument, 'sampler', smp.param))!;
      expect(ps.values.containsKey(SamplerId.root), isFalse);
      expect(ps.values.containsKey(SamplerId.tune), isFalse);
      final dest = DawTrack(id: 'd', name: 'd', color: 0, kind: TrackKind.sampler);
      dest.params[SamplerId.root] = 72;
      dest.params[SamplerId.tune] = 3;
      final applied = UserPresets.paramsFor(ps, dest);
      expect(applied[SamplerId.attack], 0.7);
      expect(applied[SamplerId.root], 72);
      expect(applied[SamplerId.tune], 3);
    });

    test('substituir, renomear, apagar; nome único por tipo sem diferenciar maiúsculas', () {
      final s = fresh();
      final v = UserPresets.capture(PresetFamily.instrument, 'synth', (id) => 0);
      final a = s.save(PresetFamily.instrument, 'synth', 'Um', v)!;
      expect(s.save(PresetFamily.instrument, 'synth', 'um', v), isNull, reason: 'existe: quem chama pergunta');
      final v2 = UserPresets.capture(PresetFamily.instrument, 'synth', (id) => 1);
      final again = s.save(PresetFamily.instrument, 'synth', 'UM', v2, replace: true)!;
      expect(again.id, a.id);
      expect(s.ofTrack(TrackKind.synth), hasLength(1));
      expect(s.ofTrack(TrackKind.synth).single.values, v2);

      final b = s.save(PresetFamily.instrument, 'synth', 'Dois', v)!;
      expect(s.rename(b.id, 'um'), isFalse, reason: 'nome em uso');
      expect(s.rename(b.id, '  Três  '), isTrue);
      expect(s.ofTrack(TrackKind.synth).map((p) => p.name), ['Um', 'Três']);
      expect(s.rename(b.id, 'três'), isTrue, reason: 'renomear para o próprio nome (outra caixa) vale');
      expect(() => s.rename(b.id, ' '), throwsA(isA<PresetFormatException>()));
      expect(s.rename('nao-existe', 'x'), isFalse);

      expect(s.delete(a.id), isTrue);
      expect(s.delete(a.id), isFalse);
      expect(s.ofTrack(TrackKind.synth).map((p) => p.name), ['três']);
      // o mesmo nome em outro tipo não conflita
      expect(s.save(PresetFamily.instrument, 'fm', 'três', UserPresets.capture(PresetFamily.instrument, 'fm', (id) => 0)), isNotNull);
    });

    test('preset de um tipo não aparece nos outros; áudio e bus não têm presets', () {
      final s = fresh();
      s.save(PresetFamily.instrument, 'synth', 'S', UserPresets.capture(PresetFamily.instrument, 'synth', (i) => 0));
      s.save(PresetFamily.effect, 'reverb', 'R', UserPresets.capture(PresetFamily.effect, 'reverb', (i) => 0));
      expect(s.ofTrack(TrackKind.fm), isEmpty);
      expect(s.ofTrack(TrackKind.synth), hasLength(1));
      expect(s.ofEffect(EffectKind.delay), isEmpty);
      expect(s.ofEffect(EffectKind.reverb), hasLength(1));
      expect(s.of(PresetFamily.effect, 'synth'), isEmpty);
      expect(() => s.save(PresetFamily.instrument, 'audio', 'x', {1: 1}), throwsA(isA<PresetFormatException>()));
      expect(() => s.save(PresetFamily.effect, 'inexistente', 'x', {1: 1}), throwsA(isA<PresetFormatException>()));
      expect(s.matchingTrack(DawTrack(id: 'a', name: 'a', color: 0)), isNull);
    });

    test('limite por tipo', () {
      final s = fresh();
      final v = UserPresets.capture(PresetFamily.effect, 'gate', (i) => 0);
      for (var i = 0; i < maxUserPresetsPerKind; i++) {
        s.save(PresetFamily.effect, 'gate', 'g$i', v);
      }
      expect(() => s.save(PresetFamily.effect, 'gate', 'a mais', v), throwsA(isA<PresetFormatException>()));
      expect(s.save(PresetFamily.effect, 'gate', 'g1', v), isNull);
    });

    test('arquivo local corrompido, de versão futura ou com entradas ruins não derruba o app', () async {
      for (final raw in [
        '',
        'nao json',
        '[]',
        '{"format":"outro"}',
        jsonEncode({'format': 'jopendaw-user-presets', 'version': 99, 'presets': []}),
      ]) {
        final st = MemoryUserPresetStorage()..data = raw;
        final s = UserPresets(st);
        await s.load();
        expect(s.ofTrack(TrackKind.synth), isEmpty, reason: raw);
      }
      final st = MemoryUserPresetStorage()
        ..data = jsonEncode({
          'format': 'jopendaw-user-presets',
          'version': 1,
          'presets': [
            42,
            {
              'id': 'a',
              'family': 'instrument',
              'kind': 'synth',
              'name': 'ok',
              'params': {'13': 500},
            },
            {'id': 'b', 'family': 'instrument', 'kind': 'holograma', 'name': 'x', 'params': {}},
            {'id': 'a', 'family': 'instrument', 'kind': 'synth', 'name': 'id repetido', 'params': {}},
            {'id': 'c', 'family': 'instrument', 'kind': 'synth', 'name': 'sem params'},
          ],
        });
      final s = UserPresets(st);
      await s.load();
      expect(s.ofTrack(TrackKind.synth).map((p) => p.name), ['ok']);
    });

    test('guardado que falha não perde o preset da sessão e avisa', () async {
      final s = UserPresets(_Failing());
      s.save(PresetFamily.effect, 'gate', 'g', UserPresets.capture(PresetFamily.effect, 'gate', (i) => 0));
      await s.flush();
      expect(s.ofEffect(EffectKind.gate), hasLength(1));
      expect(s.saveError, isNotNull);
    });
  });

  group('.jopreset', () {
    test('exportar e importar em outro guardado dá o mesmo preset', () {
      final a = fresh();
      final v = UserPresets.capture(PresetFamily.effect, 'reverb', (i) => reverbParams.firstWhere((p) => p.id == i).clamp(0.3 * (i + 1)));
      final p = a.save(PresetFamily.effect, 'reverb', 'Câmara ✨', v)!;
      final bytes = a.exportBytes(p);
      final b = fresh();
      final r = b.importBytes(bytes);
      expect(r.warnings, isEmpty);
      expect(r.preset.name, 'Câmara ✨');
      expect(r.preset.values, p.values);
      expect(b.ofEffect(EffectKind.reverb), hasLength(1));
    });

    test('nome em uso ganha sufixo, com aviso', () {
      final s = fresh();
      s.importBytes(file(good()));
      final r = s.importBytes(file(good()));
      expect(r.preset.name, 'Meu som (2)');
      expect(r.warnings.single, contains('Meu som (2)'));
      expect(s.importBytes(file(good())).preset.name, 'Meu som (3)');
    });

    test('arquivo ruim é recusado com mensagem', () {
      void bad(Uint8List b, String part) {
        final s = fresh();
        expect(() => s.importBytes(b), throwsA(isA<PresetFormatException>().having((e) => e.message, 'mensagem', contains(part))));
        expect(s.ofTrack(TrackKind.synth), isEmpty);
      }

      bad(Uint8List.fromList([0xff, 0xfe, 0x00]), 'JSON');
      bad(Uint8List.fromList(utf8.encode('{ nao é json')), 'JSON');
      bad(Uint8List.fromList(utf8.encode('[1,2]')), 'não é um preset');
      bad(file({'format': 'outra-coisa'}), 'não é um preset');
      bad(file(good(kind: 'holograma')), 'desconhecido');
      bad(file(good(family: 'efeito')), 'desconhecido');
      bad(file(good(kind: 'audio')), 'desconhecido');
      bad(file(good(version: 2)), 'mais nova');
      bad(file(good(version: 'x')), 'versão');
      bad(file(good(version: 0)), 'versão');
      bad(file({...good(), 'params': 'nada'}), 'parâmetros');
      bad(file(good(params: {})), 'nenhum valor');
      bad(file(good(params: {'9999': 1, 'abc': 2, '-1': 3})), 'nenhum valor');
      bad(file(good(params: {'${SynthId.cutoff}': 'NaN'})), 'nenhum valor');
      bad(Uint8List(maxUserPresetFileBytes + 1), 'grande');
    });

    test('valores NaN, infinitos e enormes: ignorados ou limitados, com aviso', () {
      final s = fresh();
      // jsonEncode não escreve NaN: monta o texto na mão, como um arquivo editado
      final raw =
          '{"format":"jopendaw-preset","version":1,"family":"instrument","kind":"synth","name":"x","params":'
          '{"${SynthId.cutoff}":1e999,"${SynthId.resonance}":"NaN","${SynthId.drive}":1e300,"${SynthId.osc1Wave}":2.6,"${SynthId.level}":-5,"7777":1,"lixo":1,"${SynthId.sub}":null}}';
      final r = s.importBytes(Uint8List.fromList(utf8.encode(raw)));
      final vals = r.preset.values;
      final spec = {for (final p in synthParams) p.id: p};
      expect(vals[SynthId.cutoff], spec[SynthId.cutoff]!.def, reason: 'infinito ignorado: volta ao padrão');
      expect(vals[SynthId.resonance], spec[SynthId.resonance]!.def);
      expect(vals[SynthId.sub], spec[SynthId.sub]!.def);
      expect(vals[SynthId.drive], spec[SynthId.drive]!.max);
      expect(vals[SynthId.level], spec[SynthId.level]!.min);
      expect(vals[SynthId.osc1Wave], 3, reason: 'opção arredondada e dentro da lista');
      for (final e in vals.entries) {
        expect(e.value.isFinite, isTrue);
        expect(e.value, inInclusiveRange(spec[e.key]!.min, spec[e.key]!.max));
      }
      expect(vals.length, synthParams.length, reason: 'o que faltou vem do padrão; ids desconhecidos não entram');
      expect(r.warnings.join(' '), allOf(contains('desconhecido'), contains('inválido'), contains('limitado')));
    });

    test('nome ausente, gigante ou hostil no arquivo', () {
      final s = fresh();
      expect(s.importBytes(file(good(name: null))).preset.name, 'Preset importado');
      expect(s.importBytes(file(good(name: 42))).preset.name, 'Preset importado (2)');
      final r = s.importBytes(file(good(name: '\u0000\u202e${'k' * 1000}')));
      expect(r.preset.name.length, lessThanOrEqualTo(maxUserPresetName));
      expect(r.preset.name.contains('\u0000'), isFalse);
      expect(r.warnings, isNotEmpty);
    });

    test('importar sampler ignora nota base e afinação do arquivo', () {
      final s = fresh();
      final r = s.importBytes(file(good(kind: 'sampler', params: {'${SamplerId.attack}': 0.5, '${SamplerId.root}': 1, '${SamplerId.tune}': 1})));
      expect(r.preset.values.containsKey(SamplerId.root), isFalse);
      expect(r.preset.values[SamplerId.attack], 0.5);
    });
  });

  group('menu (widget)', () {
    Future<void> openPresets(WidgetTester t, String tooltip) async {
      await t.tap(find.byTooltip(tooltip).first);
      await t.pumpAndSettle();
    }

    Future<void> tapVisible(WidgetTester t, Finder f) async {
      await t.ensureVisible(f);
      await t.pumpAndSettle();
      await t.tap(f);
      await t.pumpAndSettle();
    }

    Widget host(Widget child) => MaterialApp(
      theme: buildTheme(),
      home: Scaffold(body: child),
    );

    testWidgets('instrumento: aplicar, salvar (com substituir), renomear, apagar e o rótulo', (t) async {
      t.view.physicalSize = const Size(1400, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final store = fresh();
      UserPresets.instance = store;
      final c = fakeController(FakeEngine());
      addTearDown(c.dispose);
      c.addInstrumentTrack(TrackKind.synth);
      final tr = c.doc.tracks[1];
      c.setParam(1, SynthId.cutoff, 777);
      store.save(PresetFamily.instrument, 'synth', 'Meu lead', UserPresets.capture(PresetFamily.instrument, 'synth', tr.param));
      store.save(PresetFamily.instrument, 'fm', 'Só do FM', UserPresets.capture(PresetFamily.instrument, 'fm', (i) => 0));
      c.setParam(1, SynthId.cutoff, 5000);

      await t.pumpWidget(
        host(
          ListenableBuilder(
            listenable: c,
            builder: (_, _) => InstrumentPanel(c: c),
          ),
        ),
      );
      await openPresets(t, 'Presets');
      await t.ensureVisible(find.text('MEUS PRESETS'));
      expect(find.text('MEUS PRESETS'), findsOneWidget);
      expect(find.text('Meu lead'), findsOneWidget);
      expect(find.text('Só do FM'), findsNothing, reason: 'preset de outro tipo não aparece');
      await tapVisible(t, find.text('Meu lead'));
      expect(tr.param(SynthId.cutoff), 777);
      expect(find.text('Meu lead'), findsOneWidget, reason: 'rótulo do botão');

      // mexeu: vira "(editado)"
      c.setParam(1, SynthId.cutoff, 800);
      await t.pump();
      expect(find.text('Meu lead (editado)'), findsOneWidget);

      // salvar com o mesmo nome pergunta se substitui
      await openPresets(t, 'Presets');
      await tapVisible(t, find.text('Salvar como preset…'));
      await t.enterText(find.byKey(const ValueKey('user-preset-name')), 'meu LEAD');
      await t.pump();
      await t.tap(find.byKey(const ValueKey('user-preset-name-ok')));
      await t.pumpAndSettle();
      expect(find.text('Substituir o preset?'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('user-preset-confirm')));
      await t.pumpAndSettle();
      expect(store.ofTrack(TrackKind.synth), hasLength(1));
      expect(store.ofTrack(TrackKind.synth).single.values[SynthId.cutoff], 800);
      expect(find.text('Meu lead'), findsOneWidget, reason: 'de novo casa com o preset: sem (editado)');

      // salvar novo; nome vazio não habilita o botão
      await openPresets(t, 'Presets');
      await tapVisible(t, find.text('Salvar como preset…'));
      expect(t.widget<FilledButton>(find.byKey(const ValueKey('user-preset-name-ok'))).onPressed, isNull);
      await t.enterText(find.byKey(const ValueKey('user-preset-name')), 'Segundo');
      await t.pump();
      await t.tap(find.byKey(const ValueKey('user-preset-name-ok')));
      await t.pumpAndSettle();
      expect(store.ofTrack(TrackKind.synth).map((p) => p.name), ['Meu lead', 'Segundo']);

      // renomear pelo ícone do item
      final second = store.ofTrack(TrackKind.synth).last;
      await openPresets(t, 'Presets');
      await tapVisible(t, find.byKey(ValueKey('user-preset-more-${second.id}')));
      await t.tap(find.byKey(const ValueKey('user-preset-rename')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const ValueKey('user-preset-name')), 'Renomeado');
      await t.pump();
      await t.tap(find.byKey(const ValueKey('user-preset-name-ok')));
      await t.pumpAndSettle();
      expect(store.ofTrack(TrackKind.synth).map((p) => p.name), ['Meu lead', 'Renomeado']);

      // apagar: cancelar não apaga; confirmar apaga
      await openPresets(t, 'Presets');
      await tapVisible(t, find.byKey(ValueKey('user-preset-more-${second.id}')));
      expect(find.text('Exportar preset…'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('user-preset-delete')));
      await t.pumpAndSettle();
      expect(find.text('Apagar o preset?'), findsOneWidget);
      await t.tap(find.text('Cancelar'));
      await t.pumpAndSettle();
      expect(store.ofTrack(TrackKind.synth), hasLength(2));
      await openPresets(t, 'Presets');
      await tapVisible(t, find.byKey(ValueKey('user-preset-more-${second.id}')));
      await t.tap(find.byKey(const ValueKey('user-preset-delete')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('user-preset-confirm')));
      await t.pumpAndSettle();
      expect(store.ofTrack(TrackKind.synth).map((p) => p.name), ['Meu lead']);
      expect(t.takeException(), isNull);
    });

    testWidgets('efeito: menu com preset do usuário, aplicar, rótulo e outro tipo escondido', (t) async {
      t.view.physicalSize = const Size(1280, 700);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final store = fresh();
      UserPresets.instance = store;
      final c = RackDaw();
      addTearDown(c.dispose);
      final reverb = c.addEffect(0, EffectKind.reverb);
      c.addEffect(0, EffectKind.delay);
      c.showEffects(0);
      final probe = EffectSlot(id: 'p', kind: EffectKind.reverb)..params[3] = 4.5;
      store.save(PresetFamily.effect, 'reverb', 'Minha sala', UserPresets.capture(PresetFamily.effect, 'reverb', probe.param));

      await t.pumpWidget(
        host(
          ListenableBuilder(
            listenable: c,
            builder: (_, _) => EffectsPanel(c: c),
          ),
        ),
      );
      await t.pump();
      await openPresets(t, 'Presets e mais');
      expect(find.text('Minha sala'), findsOneWidget);
      await t.tap(find.text('Minha sala'));
      await t.pumpAndSettle();
      expect(reverb.param(3), 4.5);
      expect(find.text('Minha sala'), findsOneWidget, reason: 'subtítulo do cartão');
      c.setEffectParam(0, reverb.id, 0, 0.9);
      await t.pump();
      expect(find.text('Minha sala (editado)'), findsOneWidget);

      // o delay (segundo cartão) não vê o preset do reverb
      await t.tap(find.byTooltip('Presets e mais').last);
      await t.pumpAndSettle();
      expect(find.text('MEUS PRESETS'), findsOneWidget);
      expect(find.text('Nenhum ainda'), findsOneWidget, reason: 'delay não tem preset do usuário');
      expect(find.text('Minha sala'), findsNothing);
      expect(find.text('Importar preset…'), findsOneWidget);
    });

    testWidgets('celular estreito: a seção com nome comprido não estoura', (t) async {
      t.view.physicalSize = const Size(360, 780);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final store = fresh();
      final p = store.save(PresetFamily.effect, 'reverb', 'Um nome de preset bem comprido para caber em tela de celular', {3: 2})!;
      // a fonte dos testes (Ahem) tem 1 em por letra, quase o dobro de uma real: escala para compensar
      await t.pumpWidget(
        MaterialApp(
          theme: buildTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(0.55)),
            child: child!,
          ),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topRight,
              child: PopupMenuButton<Object>(
                tooltip: 'menu',
                itemBuilder: (_) => userPresetEntries(presets: store.ofEffect(EffectKind.reverb), current: p, color: Colors.blue),
              ),
            ),
          ),
        ),
      );
      await openPresets(t, 'menu');
      expect(find.textContaining('Um nome de preset'), findsOneWidget);
      expect(find.byKey(ValueKey('user-preset-more-${p.id}')), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('importar pelo menu: arquivo bom entra, ruim mostra o motivo, cancelar não muda nada', (t) async {
      final store = fresh();
      final files = <(String, Uint8List)?>[
        ('a.jopreset', file(good(kind: 'reverb', family: 'effect', params: {'3': 2}))),
        ('b.jopreset', file(good(version: 9))),
        null,
      ];
      var i = 0;
      await t.pumpWidget(
        host(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => handleUserPresetChoice(
                context,
                const ImportUserPreset(),
                family: PresetFamily.effect,
                kind: 'reverb',
                capture: () => {},
                presets: store,
                pick: () async => files[i++],
              ),
              child: const Text('go'),
            ),
          ),
        ),
      );
      await t.tap(find.text('go'));
      await t.pumpAndSettle();
      expect(store.ofEffect(EffectKind.reverb).single.values[3], 2);
      expect(find.byType(AlertDialog), findsNothing, reason: 'sem avisos: silencioso');
      await t.tap(find.text('go'));
      await t.pumpAndSettle();
      expect(find.textContaining('mais nova'), findsOneWidget);
      await t.tap(find.text('Ok'));
      await t.pumpAndSettle();
      await t.tap(find.text('go'));
      await t.pumpAndSettle();
      expect(store.ofEffect(EffectKind.reverb), hasLength(1));
    });

    testWidgets('exportar entrega o .jopreset pelo saveFile injetado', (t) async {
      final store = fresh();
      final p = store.save(PresetFamily.effect, 'reverb', 'Sala/Boa', {3: 2})!;
      final saved = <(String, Uint8List)>[];
      await t.pumpWidget(
        host(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => handleUserPresetChoice(
                context,
                UserPresetMore(p),
                family: PresetFamily.effect,
                kind: 'reverb',
                capture: () => {},
                presets: store,
                save: (n, b, m) async => saved.add((n, b)),
              ),
              child: const Text('go'),
            ),
          ),
        ),
      );
      await t.tap(find.text('go'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('user-preset-export')));
      await t.pumpAndSettle();
      expect(saved.single.$1, 'Sala_Boa.jopreset');
      expect(jsonDecode(utf8.decode(saved.single.$2))['name'], 'Sala/Boa');
    });
  });
}

class _Failing implements UserPresetStorage {
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String json) => Future.error('sem espaço');
  @override
  Future<void> writeBackup(String raw) async {}
  @override
  Future<String?> readBackup() async => null;
}
