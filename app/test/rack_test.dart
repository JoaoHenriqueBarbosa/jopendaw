// Rack de efeitos contra um controlador que implementa as operações de efeito no documento (o
// motor é o stub): estado vazio, adicionar pelo menu, presets, liga/desliga, ordem, o EQ (arrastar
// nós, duplo clique, analisador), a dinâmica (medidor), o genérico (nota × tempo livre, sidechain),
// sem estouro no celular nem em painel baixo, e as contas (RBJ, curva do compressor, presets).
// Com `--dart-define=SHOTS=<pasta>` grava capturas PNG.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Curve;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jopendaw_app/daw/controller.dart';
import 'package:jopendaw_app/daw/effects.dart';
import 'package:jopendaw_app/daw/effects_panel.dart';
import 'package:jopendaw_app/daw/fx_editors.dart';
import 'package:jopendaw_app/daw/fx_presets.dart';
import 'package:jopendaw_app/daw/instruments.dart';
import 'package:jopendaw_app/daw/model.dart';
import 'package:jopendaw_app/models/project.dart';
import 'package:jopendaw_app/widgets/theme.dart';

const shots = String.fromEnvironment('SHOTS');

/// O controlador de verdade com as operações de efeito feitas no documento, registrando o que o
/// painel pede (observações do motor, parâmetros, pontos de desfazer).
class RackDaw extends DawController {
  RackDaw()
    : super(
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
      ) {
    doc = DawDoc(
      bpm: 120,
      beatsPerBar: 4,
      tracks: [
        DawTrack(id: 'a', name: 'Vocal', color: 0),
        DawTrack(id: 's', name: 'Baixo synth', color: 1, kind: TrackKind.synth),
        DawTrack(id: 'b', name: 'Reverb bus', color: 2, kind: TrackKind.bus),
      ],
    );
    ready = true;
    dock = Dock.effects;
  }

  final log = <String>[];
  int checkpoints = 0;

  @override
  void checkpoint() {
    checkpoints++;
    super.checkpoint();
  }

  @override
  void showEffects(int track) {
    effectsTrack = track;
    dock = Dock.effects;
    notifyListeners();
  }

  @override
  List<EffectSlot> effectsOf(int track) => track < 0 || track >= doc.tracks.length ? doc.masterEffects : doc.tracks[track].effects;

  EffectSlot slot(int track, String id) => effectsOf(track).firstWhere((s) => s.id == id);

  var _ids = 0;

  @override
  EffectSlot addEffect(int track, EffectKind kind, {int? at}) {
    final s = EffectSlot(id: 'fx${++_ids}', kind: kind);
    edit((_) => effectsOf(track).insert(at ?? effectsOf(track).length, s));
    return s;
  }

  @override
  void removeEffect(int track, String slotId) => edit((_) => effectsOf(track).removeWhere((s) => s.id == slotId));

  @override
  void moveEffect(int track, String slotId, int to) => edit((_) {
    final list = effectsOf(track);
    final s = slot(track, slotId);
    list.remove(s);
    list.insert(to.clamp(0, list.length), s);
  });

  @override
  void setEffectParam(int track, String slotId, int id, double value, {bool undoable = false}) {
    final s = slot(track, slotId);
    final spec = s.kind.params.firstWhere((p) => p.id == id);
    final v = spec.clamp(value);
    log.add('param $id ${v.toStringAsFixed(3)}${undoable ? ' u' : ''}');
    if (undoable) checkpoint();
    s.params[id] = v;
    notifyListeners();
  }

  @override
  void setEffectBypass(int track, String slotId, bool bypass) => edit((_) => slot(track, slotId).bypass = bypass);

  @override
  void applyEffectPreset(int track, String slotId, Map<int, double> values) =>
      edit((_) => slot(track, slotId).params = {...defaultEffectParams(slot(track, slotId).kind), ...values});

  @override
  void watchEffect(int track, String? slotId) => log.add('watchEffect $track $slotId');

  @override
  void watchAnalyzer(int? track) => log.add('watchAnalyzer $track');
}

Future<void> loadFonts() async {
  final dir = '${Platform.environment['FLUTTER_ROOT'] ?? ''}/bin/cache/artifacts/material_fonts';
  if (shots.isEmpty || !Directory(dir).existsSync()) return;
  Future<void> load(String family, List<String> files) async {
    final l = FontLoader(family);
    for (final f in files) {
      l.addFont(Future.value(ByteData.view(File('$dir/$f').readAsBytesSync().buffer)));
    }
    await l.load();
  }

  for (final fam in ['Roboto', '.AppleSystemUIFont', 'CupertinoSystemText', 'CupertinoSystemDisplay', 'FlutterTest']) {
    await load(fam, ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf']);
  }
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
}

final shotKey = GlobalKey();

Future<void> mount(WidgetTester t, RackDaw c, {double width = 1280, double height = 360}) async {
  t.view.physicalSize = Size(width, math.max(height, 700));
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      theme: buildTheme(),
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: RepaintBoundary(
            key: shotKey,
            child: SizedBox(
              width: width,
              height: height,
              child: EffectsPanel(c: c),
            ),
          ),
        ),
      ),
    ),
  );
  await t.pump();
}

Future<void> shot(WidgetTester t, String name) async {
  if (shots.isEmpty) return;
  final boundary = shotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await t.runAsync(() async {
    final img = await boundary.toImage(pixelRatio: 1.5);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    File('$shots/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

var _now = Duration.zero;

Future<TestGesture> mouseDown(WidgetTester t, Offset p, {int gapMs = 600}) async {
  _now += Duration(milliseconds: gapMs);
  final g = await t.createGesture(kind: PointerDeviceKind.mouse);
  await g.down(p, timeStamp: _now);
  return g;
}

Future<void> click(WidgetTester t, Offset p, {int gapMs = 600}) async {
  final g = await mouseDown(t, p, gapMs: gapMs);
  await g.up(timeStamp: _now);
  await g.removePointer(timeStamp: _now);
  await t.pump();
}

Future<void> drag(WidgetTester t, Offset from, Offset to, {int steps = 8}) async {
  final g = await mouseDown(t, from);
  for (var i = 1; i <= steps; i++) {
    _now += const Duration(milliseconds: 16);
    await g.moveTo(Offset.lerp(from, to, i / steps)!, timeStamp: _now);
    await t.pump();
  }
  await g.up(timeStamp: _now);
  await g.removePointer(timeStamp: _now);
  await t.pump();
}

/// Deixa o salvamento adiado do controlador acontecer (não fica timer pendente no fim).
Future<void> settle(WidgetTester t) => t.pump(const Duration(seconds: 1));

/// Posição de um ponto (frequência, dB) no gráfico do EQ, com as mesmas margens do editor.
Offset eqPoint(WidgetTester t, double f, double db, {int index = 0}) {
  final r = t.getRect(find.byKey(const ValueKey('eq-graph')).at(index));
  const padX = 8.0, padY = 10.0;
  final x = r.left + padX + math.log(f / 20) / math.log(1000) * (r.width - 2 * padX);
  final y = r.top + padY + (24 - db) / 48 * (r.height - 2 * padY);
  return Offset(x, y);
}

/// Um teste de widget que termina deixando o salvamento adiado acontecer.
void rack(String name, Future<void> Function(WidgetTester t) body) => testWidgets(name, (t) async {
  await body(t);
  await settle(t);
});

Future<void> openMenu(WidgetTester t, Finder f) async {
  await t.tap(f);
  await t.pumpAndSettle();
}

void main() {
  setUpAll(loadFonts);

  group('contas', () {
    test('sino e prateleiras dão o ganho pedido; passa-alta/baixa seguem o Q e a inclinação', () {
      final bell = eqBiquad(2, 1000, 6, 1);
      expect(bell.db(1000), closeTo(6, 1e-6));
      expect(bell.db(20), closeTo(0, 0.05));
      final low = eqBiquad(1, 200, -9, 0.71);
      expect(low.db(20), closeTo(-9, 0.2));
      expect(low.db(10000), closeTo(0, 0.05));
      final high = eqBiquad(3, 5000, 4, 0.71);
      expect(high.db(20000), closeTo(4, 0.3));
      expect(high.db(50), closeTo(0, 0.01));
      // Butterworth (como o motor): −3 dB no corte em 12, 24 e 48 dB/oit com Q 0,71, e a
      // inclinação de verdade longe dele
      final hp = eqBiquad(0, 100, 0, 1 / math.sqrt2);
      expect(hp.db(100), closeTo(-3.01, 0.02));
      double band(Map<int, double> m, double f) => EqBand.of((id) => m[id] ?? 0, 0).db(f);
      final m = {0: 1.0, 1: 0.0, 2: 100.0, 3: 0.0, 4: 1 / math.sqrt2, 5: 1.0};
      expect(band(m, 100), closeTo(-3.01, 0.03));
      expect(band({...m, 5: 2}, 100), closeTo(-3.01, 0.05));
      expect(band(m, 12.5) - band(m, 25), closeTo(-24, 0.5));
      expect(band({...m, 5: 2}, 12.5) - band({...m, 5: 2}, 25), closeTo(-48, 1));
      // o Q da banda põe ressonância no corte em qualquer inclinação: |H(f0)| = Q, a altura do nó
      final res = {...m, 4: 4.0};
      expect(band(res, 100), closeTo(20 * math.log(4) / math.ln10, 0.05));
      expect(band({...res, 5: 2}, 100), closeTo(20 * math.log(4) / math.ln10, 0.05));
      expect(EqBand.of((id) => res[id] ?? 0, 0).nodeDb, closeTo(20 * math.log(4) / math.ln10, 1e-9));
      // uma oitava abaixo: 12 dB/oit de fato na inclinação de 12 (longe do corte)
      expect(eqBiquad(4, 1000, 0, 0.71).db(8000) - eqBiquad(4, 1000, 0, 0.71).db(4000), closeTo(-12, 1.5));
      // passa-alta e passa-baixa: |H(f0)| = Q, a altura do nó
      expect(eqBiquad(4, 2000, 0, 4).db(2000), closeTo(20 * math.log(4) / math.ln10, 1e-6));
      expect(eqBiquad(5, 1000, 0, 2).db(1000), lessThan(-60));
    });

    test('resposta somada ignora bandas desligadas', () {
      final values = defaultEffectParams(EffectKind.eq);
      values[2 * 6 + 3] = 5; // banda 3 (250 Hz) +5 dB
      final bands = eqBands((id) => values[id]!);
      expect(eqResponseDb(bands, 250), closeTo(5, 0.2));
      values[2 * 6] = 0;
      expect(eqResponseDb(eqBands((id) => values[id]!), 250), closeTo(0, 1e-6));
    });

    test('curva do compressor: reta abaixo, razão acima, joelho contínuo', () {
      expect(compressorCurve(-40, -20, 4, 0), -40);
      expect(compressorCurve(0, -20, 4, 0), closeTo(-15, 1e-9));
      expect(compressorCurve(-20, -20, 4, 6), closeTo(-20 + (0.25 - 1) * 9 / 12, 1e-9));
      for (final x in [-23.0 - 1e-6, -17.0 + 1e-6]) {
        final hard = x < -20 ? x : -20 + (x + 20) / 4;
        expect(compressorCurve(x, -20, 4, 6), closeTo(hard, 1e-4));
      }
    });

    test('ganho do compressor: o manual soma ao automático (como no motor) e o knob não apaga', () {
      // motor: auto = −limiar · (1 − 1/razão) · 0,5, somado ao ganho manual
      expect(compressorMakeupDb(-20, 4, 0, false), 0);
      expect(compressorMakeupDb(-20, 4, 3, false), 3);
      expect(compressorMakeupDb(-20, 4, 0, true), closeTo(7.5, 1e-9));
      expect(compressorMakeupDb(-20, 4, 3, true), closeTo(10.5, 1e-9));
      double v(int id) => {9: 1.0, 5: 3.0, 1: 4.0}[id] ?? 0;
      final makeup = compressorParams.firstWhere((p) => p.id == 5);
      expect(effectParamDimmed(EffectKind.compressor, makeup, v), isFalse);
    });

    test('distorção: o que o tipo escolhido ignora fica apagado (sobreamostragem no bitcrusher, bits e dither fora dele)', () {
      ParamSpec p(int id) => distortionParams.firstWhere((s) => s.id == id);
      expect(p(8).name, 'Dither');
      double crush(int id) => id == 1 ? 5 : 0;
      double soft(int id) => 0;
      expect(effectParamDimmed(EffectKind.distortion, p(7), crush), isTrue);
      expect(effectParamDimmed(EffectKind.distortion, p(8), crush), isFalse);
      expect(effectParamDimmed(EffectKind.distortion, p(5), crush), isFalse);
      expect(effectParamDimmed(EffectKind.distortion, p(7), soft), isFalse);
      expect(effectParamDimmed(EffectKind.distortion, p(8), soft), isTrue);
      expect(effectParamDimmed(EffectKind.distortion, p(5), soft), isTrue);
    });

    test('presets: ids da tabela, valores na faixa e reconhecidos depois de aplicados', () {
      for (final kind in EffectKind.values) {
        final list = effectPresetsFor(kind);
        expect(list, isNotEmpty, reason: kind.name);
        for (final p in list) {
          for (final e in p.values.entries) {
            final spec = kind.params.where((s) => s.id == e.key);
            expect(spec, hasLength(1), reason: '${kind.name}/${p.name}: id ${e.key}');
            expect(spec.first.clamp(e.value), e.value, reason: '${kind.name}/${p.name}: ${spec.first.name} = ${e.value}');
          }
          final slot = EffectSlot(id: 'x', kind: kind, params: {...defaultEffectParams(kind), ...p.values});
          expect(matchingEffectPreset(slot)?.name, p.name);
          // um efeito recém-adicionado não pode aparecer com nome de preset
          expect(isDefaultEffect(slot), isFalse, reason: '${kind.name}/${p.name} é igual ao padrão');
        }
      }
      final names = {for (final k in EffectKind.values) k: effectPresetsFor(k).map((p) => p.name).toSet()};
      expect(names[EffectKind.eq], containsAll(['Corte de graves', 'Voz presente', 'Bumbo', 'Brilho']));
      expect(names[EffectKind.compressor], containsAll(['Voz', 'Bateria cola', 'Baixo', 'Paralelo pesado']));
      expect(names[EffectKind.reverb], containsAll(['Quarto', 'Sala', 'Salão', 'Placa', 'Catedral', 'Shimmer congelado']));
      expect(names[EffectKind.delay], containsAll(['1/8 pontilhado', 'Ping-pong 1/4', 'Slapback', 'Dub']));
      expect(names[EffectKind.chorus], containsAll(['Chorus leve', 'Flanger jato']));
      expect(names[EffectKind.phaser], containsAll(['Lento', 'Rápido']));
      expect(names[EffectKind.distortion], containsAll(['Saturação de fita', 'Válvula quente', 'Fuzz', 'Lo-fi 8 bits']));
      expect(names[EffectKind.filter], containsAll(['Varredura lenta', 'Wobble 1/8']));
      expect(names[EffectKind.limiter], contains('Master −1 dB'));
    });
  });

  rack('vazio: explica e adiciona pelos atalhos e pelo menu agrupado', (t) async {
    final c = RackDaw();
    await mount(t, c);
    expect(find.text('Nenhum efeito no master'), findsOneWidget);
    // no master o terceiro atalho é o limitador
    expect(find.widgetWithText(FilledButton, 'Limitador'), findsOneWidget);
    await shot(t, 'rack_empty');
    await t.tap(find.widgetWithText(FilledButton, 'EQ'));
    await t.pumpAndSettle();
    expect(c.doc.masterEffects.single.kind, EffectKind.eq);
    expect(c.log, contains('watchAnalyzer -1'));

    await openMenu(t, find.text('Adicionar efeito').first);
    for (final family in ['TIMBRE', 'DINÂMICA E UTILIDADE', 'ESPAÇO', 'MODULAÇÃO', 'SATURAÇÃO']) {
      expect(find.text(family), findsOneWidget);
    }
    expect(find.text(EffectKind.reverb.description), findsOneWidget);
    await t.tap(find.text('Reverb'));
    await t.pumpAndSettle();
    expect(c.doc.masterEffects.map((s) => s.kind), [EffectKind.eq, EffectKind.reverb]);
  });

  rack('seletor de faixa, liga/desliga, presets (editado), ordem e remover', (t) async {
    final c = RackDaw();
    await mount(t, c);
    await openMenu(t, find.text('Master'));
    await t.tap(find.text('Vocal').last);
    await t.pumpAndSettle();
    expect(c.effectsTrack, 0);
    expect(find.text('Nenhum efeito em Vocal'), findsOneWidget);
    c.addEffect(0, EffectKind.reverb);
    c.addEffect(0, EffectKind.delay);
    await t.pumpAndSettle();
    final reverb = c.doc.tracks[0].effects[0];

    await t.tap(find.byTooltip('Desligar o efeito (bypass)').first);
    await t.pump();
    expect(reverb.bypass, isTrue);
    expect(find.text('desligado'), findsOneWidget);
    await t.tap(find.byTooltip('Ligar o efeito').first);
    await t.pump();
    expect(reverb.bypass, isFalse);

    await openMenu(t, find.byTooltip('Presets e mais').first);
    await t.tap(find.text('Sala'));
    await t.pumpAndSettle();
    expect(reverb.param(3), 1.4);
    expect(find.text('Sala'), findsOneWidget);
    c.setEffectParam(0, reverb.id, 0, 0.5);
    await t.pump();
    expect(find.text('Sala (editado)'), findsOneWidget);

    await openMenu(t, find.byTooltip('Presets e mais').first);
    await t.tap(find.text('Mover para a direita'));
    await t.pumpAndSettle();
    expect(c.doc.tracks[0].effects.map((s) => s.kind), [EffectKind.delay, EffectKind.reverb]);

    await openMenu(t, find.byTooltip('Presets e mais').last);
    await t.tap(find.text('Reiniciar (valores padrão)'));
    await t.pumpAndSettle();
    expect(isDefaultEffect(reverb), isTrue);

    await openMenu(t, find.byTooltip('Presets e mais').last);
    await t.tap(find.text('Remover'));
    await t.pumpAndSettle();
    expect(c.doc.tracks[0].effects.map((s) => s.kind), [EffectKind.delay]);
    c.undo();
    await t.pumpAndSettle();
    expect(c.doc.tracks[0].effects, hasLength(2));
  });

  rack('arrastar pela alça muda a ordem', (t) async {
    final c = RackDaw()..effectsTrack = 1;
    c.addEffect(1, EffectKind.chorus);
    c.addEffect(1, EffectKind.phaser);
    await mount(t, c);
    final handles = find.byIcon(Icons.drag_indicator);
    final from = t.getCenter(handles.first);
    final to = t.getCenter(handles.last) + const Offset(260, 0);
    final g = await t.startGesture(from, kind: PointerDeviceKind.mouse);
    for (var i = 1; i <= 20; i++) {
      await g.moveTo(Offset.lerp(from, to, i / 20)!);
      await t.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await t.pumpAndSettle();
    expect(c.doc.tracks[1].effects.map((s) => s.kind), [EffectKind.phaser, EffectKind.chorus]);
  });

  rack('EQ: arrastar o nó muda frequência e ganho num passo só de desfazer', (t) async {
    final c = RackDaw();
    final eq = c.addEffect(-1, EffectKind.eq);
    c.checkpoints = 0;
    await mount(t, c);
    // banda 3: sino em 250 Hz, 0 dB
    final from = eqPoint(t, 250, 0);
    final to = eqPoint(t, 1000, 9);
    await drag(t, from, to);
    expect(eq.param(2 * 6 + 2), closeTo(1000, 30));
    expect(eq.param(2 * 6 + 3), closeTo(9, 0.5));
    expect(c.checkpoints, 1);
    await shot(t, 'rack_eq');

    // roda do mouse em cima do nó: Q
    final q0 = eq.param(2 * 6 + 4);
    final at = eqPoint(t, eq.param(2 * 6 + 2), eq.param(2 * 6 + 3));
    final hover = await t.createGesture(kind: PointerDeviceKind.mouse);
    await hover.addPointer(location: at);
    await hover.moveTo(at);
    await t.pump();
    await t.sendEventToBinding(PointerScrollEvent(position: at, scrollDelta: const Offset(0, -200), kind: PointerDeviceKind.mouse));
    await t.pump();
    expect(eq.param(2 * 6 + 4), greaterThan(q0));
    await hover.removePointer();
    await t.pump(const Duration(seconds: 1));

    // passa-alta (banda 1, desligada): duplo clique no nó liga
    final hp = eqPoint(t, 30, 20 * math.log(0.71) / math.ln10);
    await click(t, hp);
    await click(t, hp, gapMs: 120);
    expect(eq.param(0), 1);
    expect(c.log.last, 'param 0 1.000 u');

    // duplo clique no vazio acende a banda 8 (a única desligada) como sino ali
    final empty = eqPoint(t, 5000, -6);
    await click(t, empty);
    await click(t, empty, gapMs: 120);
    expect(eq.param(7 * 6), 1);
    expect(eq.param(7 * 6 + 1), 2);
    expect(eq.param(7 * 6 + 2), closeTo(5000, 150));
    expect(eq.param(7 * 6 + 3), closeTo(-6, 0.5));
  });

  rack('EQ: a lista das bandas liga, troca tipo e mostra inclinação nos cortes', (t) async {
    final c = RackDaw();
    final eq = c.addEffect(-1, EffectKind.eq);
    await mount(t, c);
    await t.tap(find.byTooltip('Ligar a banda 1'));
    await t.pump();
    expect(eq.param(0), 1);
    // banda 1 é passa-alta: no lugar do ganho, a inclinação
    expect(find.text('24 dB/o'), findsNWidgets(2));
    await openMenu(t, find.text('24 dB/o').first);
    await t.tap(find.text('48 dB/oit'));
    await t.pumpAndSettle();
    expect(eq.param(5), 2);
    await openMenu(t, find.byTooltip('Sino').first);
    await t.tap(find.text('Rejeita-faixa').last);
    await t.pumpAndSettle();
    expect(eq.param(1 * 6 + 1) == 5 || eq.param(2 * 6 + 1) == 5, isTrue);
  });

  rack('analisador: liga ao montar o EQ, desliga ao tirar, segue a troca de faixa', (t) async {
    final c = RackDaw()..effectsTrack = 0;
    final eq = c.addEffect(0, EffectKind.eq);
    c.addEffect(1, EffectKind.eq);
    await mount(t, c);
    expect(c.log.where((l) => l.startsWith('watchAnalyzer')), ['watchAnalyzer 0']);
    c.spectrum.value = Float32List.fromList([for (var i = 0; i < 1024; i++) -30 - i * 0.05]);
    await t.pump();
    c.showEffects(1);
    await t.pump();
    await t.pump();
    // a troca monta o novo antes de desmontar o velho: a observação fica na faixa nova
    expect(c.log.where((l) => l.startsWith('watchAnalyzer')).last, 'watchAnalyzer 1');
    c.showEffects(0);
    await t.pump();
    c.removeEffect(0, eq.id);
    await t.pump();
    await t.pump();
    expect(c.log.where((l) => l.startsWith('watchAnalyzer')).last, 'watchAnalyzer null');
  });

  rack('dinâmica: observa o efeito, mostra a redução e passa a medir o que o usuário toca', (t) async {
    final c = RackDaw();
    final comp = c.addEffect(-1, EffectKind.compressor);
    final lim = c.addEffect(-1, EffectKind.limiter);
    await mount(t, c, width: 1800);
    expect(c.log, contains('watchEffect -1 ${comp.id}'));
    c.fxMeter.value = 4.2;
    await t.pump();
    await shot(t, 'rack_dynamics');
    final transfer = find.byKey(const ValueKey('fx-transfer'));
    await click(t, t.getCenter(transfer.last));
    await t.pump();
    expect(c.log.last, 'watchEffect -1 ${lim.id}');
    // arrastar na curva muda o limiar (compressor), num passo de desfazer
    c.checkpoints = 0;
    final r = t.getRect(transfer.first);
    await drag(t, r.center, r.center + Offset(r.width / 6, 0));
    expect(comp.param(0), closeTo(-18 + 10, 0.8));
    expect(c.checkpoints, 1);
    c.removeEffect(-1, lim.id);
    await t.pump();
    await t.pump();
    expect(c.log.last, 'watchEffect -1 ${comp.id}');
    c.removeEffect(-1, comp.id);
    await t.pump();
    await t.pump();
    expect(c.log.last, 'watchEffect -1 null');
  });

  rack('genérico: nota ou tempo livre conforme o Tempo; sidechain lista as faixas', (t) async {
    final c = RackDaw()..effectsTrack = 0;
    final delay = c.addEffect(0, EffectKind.delay);
    c.addEffect(0, EffectKind.compressor);
    await mount(t, c, width: 1800);
    expect(find.text('Nota'), findsOneWidget);
    expect(find.text('Tempo livre'), findsNothing);
    c.setEffectParam(0, delay.id, 1, 0, undoable: true);
    await t.pump();
    expect(find.text('Nota'), findsNothing);
    expect(find.text('Tempo livre'), findsOneWidget);

    await openMenu(t, find.byTooltip('Sidechain'));
    expect(find.text('Baixo synth'), findsWidgets);
    expect(find.text('Reverb bus'), findsWidgets);
    await t.tap(find.text('Baixo synth').last);
    await t.pumpAndSettle();
    expect(c.doc.tracks[0].effects[1].param(10), 1);
    expect(find.text('Baixo synth'), findsOneWidget);
  });

  rack('um de cada no computador, em painel normal e baixo, sem estouro', (t) async {
    final c = RackDaw();
    for (final k in EffectKind.values) {
      c.addEffect(-1, k);
    }
    await mount(t, c, width: 1400, height: 420);
    await shot(t, 'rack_all_desktop');
    await mount(t, c, width: 1000, height: 190);
    await shot(t, 'rack_all_short');
    // passar por todos (a fileira rola)
    final list = find.byType(Scrollable).first;
    for (var i = 0; i < 12; i++) {
      await t.drag(list, const Offset(-600, 0), kind: PointerDeviceKind.trackpad);
      await t.pump();
    }
  });

  rack('celular 360 px: um de cada, empilhados, sem estouro', (t) async {
    final c = RackDaw()..effectsTrack = 1;
    for (final k in EffectKind.values) {
      c.addEffect(1, k);
    }
    await mount(t, c, width: 360, height: 640);
    await shot(t, 'rack_mobile');
    // um dedo em cima de um knob mexe o knob (não rola): a lista vai pela posição
    final list = t.state<ScrollableState>(find.byType(Scrollable).first).position;
    for (var y = 0.0; y < list.maxScrollExtent; y += 250) {
      list.jumpTo(y);
      await t.pump();
    }
    list.jumpTo(list.maxScrollExtent);
    await t.pump();
    await shot(t, 'rack_mobile_end');
    expect(find.text('Adicionar efeito'), findsOneWidget);
    // cabeçalho do celular: botão curto
    expect(find.text('Efeito'), findsOneWidget);
  });

  rack('celular: arrastar um nó do EQ não rola a lista', (t) async {
    final c = RackDaw();
    c.addEffect(-1, EffectKind.compressor);
    final eq = c.addEffect(-1, EffectKind.eq);
    c.addEffect(-1, EffectKind.reverb);
    await mount(t, c, width: 380, height: 640);
    await t.ensureVisible(find.byKey(const ValueKey('eq-graph')));
    await t.pumpAndSettle();
    final offset = t.state<ScrollableState>(find.byType(Scrollable).first).position.pixels;
    final from = eqPoint(t, 800, 0);
    final to = eqPoint(t, 800, 12);
    final g = await t.startGesture(from);
    for (var i = 1; i <= 10; i++) {
      await g.moveTo(Offset.lerp(from, to, i / 10)!);
      await t.pump();
    }
    await g.up();
    await t.pumpAndSettle();
    expect(eq.param(3 * 6 + 3), greaterThan(8));
    expect(t.state<ScrollableState>(find.byType(Scrollable).first).position.pixels, offset);
    // fora dos nós o dedo rola a lista normalmente
    final empty = eqPoint(t, 60, -18);
    await t.dragFrom(empty, const Offset(0, -120));
    await t.pumpAndSettle();
    expect(t.state<ScrollableState>(find.byType(Scrollable).first).position.pixels, greaterThan(offset + 50));
  });

  rack('multibanda: arrastar perto do cruzamento o move (num passo de desfazer) e o indicador chega empacotado', (t) async {
    final c = RackDaw();
    final mb = c.addEffect(-1, EffectKind.multiband);
    await mount(t, c, width: 1800);
    expect(c.log, contains('watchEffect -1 ${mb.id}'));
    c.fxMeter.value = 15 + 256 * 60 + 65536 * 0;
    await t.pump();
    final r = t.getRect(find.byKey(const ValueKey('fx-viz')));
    double xOf(double f) => r.left + math.log(f / 20) / math.log(1000) * r.width;
    c.checkpoints = 0;
    await drag(t, Offset(xOf(150) + 3, r.center.dy), Offset(xOf(400), r.center.dy));
    expect(mb.param(0), closeTo(400, 30));
    expect(mb.param(1), 3000);
    expect(c.checkpoints, 1);
    // o cruzamento alto não passa do teto da tabela
    await drag(t, Offset(xOf(3000), r.center.dy), Offset(r.right + 200, r.center.dy));
    expect(mb.param(1), lessThanOrEqualTo(12000));
    // banda em bypass apaga os controles dela, mas solo e bypass seguem mexíveis
    c.setEffectParam(-1, mb.id, multibandBase + 6, 1, undoable: true);
    await t.pump();
    expect(find.text('Bypass'), findsNWidgets(3));
  });

  rack('de-esser: arrastar muda a frequência (e o Q na vertical); imagem mostra as três larguras', (t) async {
    final c = RackDaw();
    final ds = c.addEffect(-1, EffectKind.deesser);
    await mount(t, c, width: 1800);
    final r = t.getRect(find.byKey(const ValueKey('fx-viz')));
    await drag(t, r.center, r.center + Offset(r.width / 4, 0));
    expect(ds.param(0), greaterThan(7000));
    c.removeEffect(-1, ds.id);
    final im = c.addEffect(-1, EffectKind.imager);
    await t.pump();
    c.fxMeter.value = -0.4;
    await t.pump();
    expect(find.text('LARGURA'), findsOneWidget);
    expect(find.text('Baixa'), findsOneWidget);
    expect(im.param(3), 1);
  });

  rack('multibanda, de-esser e imagem: celular de 360 px sem estouro', (t) async {
    final c = RackDaw()..effectsTrack = 1;
    for (final k in [EffectKind.multiband, EffectKind.deesser, EffectKind.imager]) {
      c.addEffect(1, k);
    }
    await mount(t, c, width: 360, height: 640);
    final list = t.state<ScrollableState>(find.byType(Scrollable).first).position;
    for (var y = 0.0; y < list.maxScrollExtent; y += 200) {
      list.jumpTo(y);
      await t.pump();
    }
    expect(t.takeException(), isNull);
  });
}
