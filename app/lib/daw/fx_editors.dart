/// Os editores de cada efeito no rack: o EQ (gráfico de resposta com os nós das bandas e o
/// espectro ao vivo por trás), a dinâmica (curva de transferência e medidor de redução de ganho) e
/// o genérico, com os knobs agrupados como na tabela de `effects.dart`.
///
/// Toda mexida vai ao controlador pelo caminho rápido (`setEffectParam`). Um arraste é um passo só
/// no desfazer: o ponto é guardado na primeira mudança de fato (`checkpoint`) e os passos seguintes
/// não entram no histórico; uma escolha discreta (menu, liga/desliga) entra sozinha
/// (`undoable: true`).
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/material.dart' hide Curve;
import 'package:flutter/services.dart';

import '../widgets/theme.dart';
import 'controller.dart';
import 'effects.dart';
import 'instruments.dart';
import 'knob.dart';
import 'midi_learn_ui.dart';
import 'model.dart';

part 'fx_editors_dyn.dart';

/// Taxa de amostragem suposta para desenhar: as curvas do EQ são as do filtro digital (o que muda
/// perto de Nyquist) e o espectro vem em faixas lineares até a metade da taxa. O motor roda na
/// taxa do aparelho (quase sempre 48 kHz); o controlador ainda não a expõe.
const fxDisplayRate = 48000.0;

/// Cor de cada banda do EQ (nós, lista e curva da banda escolhida).
const eqBandColors = <Color>[
  Color(0xFFEF7D6D),
  Color(0xFFF0A35E),
  Color(0xFFE3C341),
  Color(0xFF8BD17C),
  Color(0xFF35D0C0),
  Color(0xFF6BA8F0),
  Color(0xFFB58CF0),
  Color(0xFFF08CC8),
];

// ------------------------------------------------------------------------ EQ: as contas

/// Um biquad com os coeficientes já divididos por a0.
class Biquad {
  final double b0, b1, b2, a1, a2;
  const Biquad(this.b0, this.b1, this.b2, this.a1, this.a2);

  factory Biquad._norm(double b0, double b1, double b2, double a0, double a1, double a2) => Biquad(b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0);

  /// |H|² em ω (radianos por amostra), com cos/sen de ω e 2ω já calculados.
  double _mag2(double c1, double s1, double c2, double s2) {
    final nr = b0 + b1 * c1 + b2 * c2, ni = b1 * s1 + b2 * s2;
    final dr = 1 + a1 * c1 + a2 * c2, di = a1 * s1 + a2 * s2;
    return (nr * nr + ni * ni) / math.max(dr * dr + di * di, 1e-30);
  }

  /// Ganho em dB na frequência [f] (Hz).
  double db(double f, {double rate = fxDisplayRate}) {
    final w = 2 * math.pi * math.min(f, rate * 0.4999) / rate;
    return _toDb(_mag2(math.cos(w), math.sin(w), math.cos(2 * w), math.sin(2 * w)));
  }
}

double _toDb(double mag2) => 10 * math.log(math.max(mag2, 1e-30)) / math.ln10;

/// Coeficientes de uma banda do EQ pelas fórmulas do Audio EQ Cookbook (RBJ), as mesmas do motor:
/// [type] é o de `eq_param::TYPE` (0 passa-alta, 1 prateleira grave, 2 sino, 3 prateleira aguda,
/// 4 passa-baixa, 5 rejeita-faixa). O Q entra como `alpha = sen(ω0) / 2Q` em todos, prateleiras
/// inclusive.
Biquad eqBiquad(int type, double freq, double gainDb, double q, {double rate = fxDisplayRate}) {
  final f0 = freq.clamp(10.0, rate * 0.49);
  final w0 = 2 * math.pi * f0 / rate;
  final cw = math.cos(w0), sw = math.sin(w0);
  final alpha = sw / (2 * math.max(q, 0.01));
  final a = math.pow(10, gainDb / 40).toDouble();
  final sa = 2 * math.sqrt(a) * alpha;
  return switch (type) {
    0 => Biquad._norm((1 + cw) / 2, -(1 + cw), (1 + cw) / 2, 1 + alpha, -2 * cw, 1 - alpha),
    1 => Biquad._norm(
      a * ((a + 1) - (a - 1) * cw + sa),
      2 * a * ((a - 1) - (a + 1) * cw),
      a * ((a + 1) - (a - 1) * cw - sa),
      (a + 1) + (a - 1) * cw + sa,
      -2 * ((a - 1) + (a + 1) * cw),
      (a + 1) + (a - 1) * cw - sa,
    ),
    3 => Biquad._norm(
      a * ((a + 1) + (a - 1) * cw + sa),
      -2 * a * ((a - 1) + (a + 1) * cw),
      a * ((a + 1) + (a - 1) * cw - sa),
      (a + 1) - (a - 1) * cw + sa,
      2 * ((a - 1) - (a + 1) * cw),
      (a + 1) - (a - 1) * cw - sa,
    ),
    4 => Biquad._norm((1 - cw) / 2, 1 - cw, (1 - cw) / 2, 1 + alpha, -2 * cw, 1 - alpha),
    5 => Biquad._norm(1, -2 * cw, 1, 1 + alpha, -2 * cw, 1 - alpha),
    _ => Biquad._norm(1 + alpha * a, -2 * cw, 1 - alpha * a, 1 + alpha / a, -2 * cw, 1 - alpha / a),
  };
}

/// Q das seções de um Butterworth de ordem 2, 4 e 8 por inclinação (espelho de
/// `eq::BUTTERWORTH` do motor), em ordem crescente.
const eqButterworth = [
  [0.7071068],
  [0.5411961, 1.306563],
  [0.5097956, 0.6013449, 0.8999762, 2.5629154],
];

/// Quantas seções de 2ª ordem em cascata a banda usa: a inclinação só vale nos passa-alta/baixa
/// (12 dB/oit = 1, 24 = 2, 48 = 4).
int eqStages(int type, int slope) => type == 0 || type == 4 ? const [1, 2, 4][slope.clamp(0, 2)] : 1;

/// As seções de uma banda, como o motor as monta: nos passa-alta/baixa de 24 e 48 dB/oit, os Q de
/// um Butterworth de ordem 4 e 8, com o Q da banda escalando só a última (a de Q mais alto) por
/// Q/√½ (Q 0,71 é o Butterworth exato, −3 dB no corte); no resto, uma seção com o Q da banda.
List<Biquad> eqSections(int type, double freq, double gainDb, double q, int slope, {double rate = fxDisplayRate}) {
  if (eqStages(type, slope) == 1) return [eqBiquad(type, freq, gainDb, q, rate: rate)];
  final qs = eqButterworth[slope.clamp(0, 2)];
  return [for (var k = 0; k < qs.length; k++) eqBiquad(type, freq, gainDb, k == qs.length - 1 ? qs[k] * q / 0.7071068 : qs[k], rate: rate)];
}

/// Uma banda do EQ lida dos parâmetros (`b * 6 + k`).
class EqBand {
  final int index;
  final bool on;
  final int type, slope;
  final double freq, gain, q;
  final List<Biquad> sections;

  EqBand._(this.index, this.on, this.type, this.freq, this.gain, this.q, this.slope) : sections = eqSections(type, freq, gain, q, slope);

  factory EqBand.of(double Function(int id) v, int b) =>
      EqBand._(b, v(b * 6) >= 0.5, v(b * 6 + 1).round().clamp(0, 5), v(b * 6 + 2), v(b * 6 + 3), v(b * 6 + 4), v(b * 6 + 5).round().clamp(0, 2));

  bool get hasGain => type == 1 || type == 2 || type == 3;
  bool get isCut => type == 0 || type == 4;
  int get stages => eqStages(type, slope);

  /// Resposta só desta banda, em dB.
  double db(double f, {double rate = fxDisplayRate}) => sections.fold(0.0, (sum, s) => sum + s.db(f, rate: rate));

  /// Altura do nó no gráfico: o ganho nas que têm ganho; nos passa-alta/baixa, a resposta na
  /// própria frequência, que é onde a curva passa (|H(f0)| = Q por seção no RBJ, e o produto dos Q
  /// de um Butterworth é √½: dá o Q da banda em qualquer inclinação); no rejeita-faixa, 0 dB.
  double get nodeDb => hasGain ? gain : (isCut ? 20 * math.log(math.max(q, 1e-3)) / math.ln10 : 0);
}

/// As 8 bandas de um EQ.
List<EqBand> eqBands(double Function(int id) v) => [for (var b = 0; b < 8; b++) EqBand.of(v, b)];

/// Resposta somada das bandas ligadas, em dB (sem o ganho de saída).
double eqResponseDb(List<EqBand> bands, double f, {double rate = fxDisplayRate}) {
  final w = 2 * math.pi * math.min(f, rate * 0.4999) / rate;
  final c1 = math.cos(w), s1 = math.sin(w), c2 = math.cos(2 * w), s2 = math.sin(2 * w);
  var db = 0.0;
  for (final b in bands) {
    if (!b.on) continue;
    for (final s in b.sections) {
      db += _toDb(s._mag2(c1, s1, c2, s2));
    }
  }
  return db;
}

// ------------------------------------------------------------------------ dinâmica: as contas

/// Saída estática do compressor (dB) para uma entrada [x] (dB): joelho suave quadrático de largura
/// [knee] em volta do limiar (Giannoulis, Massberg e Reiss), sem o ganho de saída.
double compressorCurve(double x, double threshold, double ratio, double knee) {
  final over = x - threshold;
  if (knee > 0 && 2 * over.abs() <= knee) {
    final t = over + knee / 2;
    return x + (1 / ratio - 1) * t * t / (2 * knee);
  }
  return over <= 0 ? x : threshold + over / ratio;
}

/// Ganho de saída do compressor (dB) como o motor o aplica: o manual mais, com o ganho automático
/// ligado, metade do que falta a um sinal em 0 dBFS (`update_makeup` em `fx/compressor.rs`).
double compressorMakeupDb(double threshold, double ratio, double manual, bool auto) => manual + (auto ? -threshold * (1 - 1 / ratio) * 0.5 : 0);

/// O que não faz efeito com os ajustes de agora (fica apagado na tela, mas mexível). [v] lê o valor
/// atual do parâmetro pelo id.
bool effectParamDimmed(EffectKind kind, ParamSpec p, double Function(int id) v) => switch (kind) {
  // o ganho manual continua valendo com o automático ligado: os dois se somam
  EffectKind.distortion => ((p.id == 5 || p.id == 6 || p.id == 8) && v(1).round() != 5) || (p.id == 7 && v(1).round() == 5),
  EffectKind.filter => (p.id == 3 || p.id == 5 || p.id == 9 || p.id == 10) && v(4) <= 0,
  EffectKind.reverb => p.id == 3 && v(9) >= 0.5,
  EffectKind.delay => p.id == 6 && v(5) >= 0.5,
  // banda em bypass: só solo e bypass ainda mexem no som
  EffectKind.multiband =>
    p.id >= multibandBase &&
        (p.id - multibandBase) % multibandStride != 5 &&
        (p.id - multibandBase) % multibandStride != 6 &&
        v(p.id - (p.id - multibandBase) % multibandStride + 6) >= 0.5,
  EffectKind.imager => p.id == 7 && v(6) < 0.5,
  _ => false,
};

// ------------------------------------------------------------------------ quem o motor observa

/// Um editor que pede o indicador do motor (o motor mede um efeito por vez).
abstract interface class _MeterHost {
  int get meterTrack;
  String get meterSlot;
}

/// Coordena o que os editores montados pedem ao motor: um espectro (o da faixa do EQ montado mais
/// recente) e um indicador (o do efeito de dinâmica ativo). Montar e desmontar acontece no meio do
/// quadro (e a troca de faixa monta os novos antes de desmontar os velhos): as chamadas ao
/// controlador saem juntas numa microtarefa, com o estado final, fora do build.
class _Watch {
  _Watch(this.c);
  final DawController c;

  static final _all = Expando<_Watch>();
  static _Watch of(DawController c) => _all[c] ??= _Watch(c);

  final _eqs = <_EqEditorState>[];
  final _dynamics = <_MeterHost>[];

  /// O editor de dinâmica cujo indicador o motor manda.
  final active = ValueNotifier<_MeterHost?>(null);

  int? _sentAnalyzer;
  (int, String)? _sentFx;
  bool _scheduled = false, _eqDirty = false, _fxDirty = false;

  void addEq(_EqEditorState s) => _eqChanged(() => _eqs.add(s));
  void removeEq(_EqEditorState s) => _eqChanged(() => _eqs.remove(s));

  void _eqChanged(void Function() fn) {
    fn();
    _eqDirty = true;
    _schedule();
  }

  void addDynamics(_MeterHost s) {
    _dynamics.add(s);
    _fxDirty = true;
    _schedule();
  }

  void removeDynamics(_MeterHost s) {
    _dynamics.remove(s);
    _fxDirty = true;
    _schedule();
  }

  /// O usuário mexeu num efeito de dinâmica: o indicador passa a ser o dele.
  void activate(_MeterHost s) {
    if (active.value == s || !_dynamics.contains(s)) return;
    active.value = s;
    _fxDirty = true;
    _schedule();
  }

  void _schedule() {
    if (_scheduled) return;
    _scheduled = true;
    scheduleMicrotask(_flush);
  }

  void _flush() {
    _scheduled = false;
    if (_eqDirty) {
      _eqDirty = false;
      final want = _eqs.isEmpty ? null : _eqs.last.widget.track;
      if (want != null || _sentAnalyzer != null) _call(() => c.watchAnalyzer(want));
      _sentAnalyzer = want;
    }
    if (_fxDirty) {
      _fxDirty = false;
      var a = active.value;
      if (a == null || !_dynamics.contains(a)) a = _dynamics.isEmpty ? null : _dynamics.first;
      active.value = a;
      final want = a == null ? null : (a.meterTrack, a.meterSlot);
      final sent = _sentFx;
      if (want != null) {
        _call(() => c.watchEffect(want.$1, want.$2));
      } else if (sent != null) {
        _call(() => c.watchEffect(sent.$1, null));
      }
      _sentFx = want;
    }
  }

  void _call(void Function() fn) {
    try {
      fn();
    } on FlutterError {
      // controlador descartado junto com a tela: não há mais o que observar
    }
  }
}

// ------------------------------------------------------------------------ o editor

/// O editor de um slot. No computador ocupa a altura [height] (o cartão enche o painel) e tem a
/// largura de [widthFor]; no celular, a largura do cartão e a altura que precisar.
class EffectEditor extends StatelessWidget {
  final DawController c;
  final int track;
  final EffectSlot slot;
  final Color color;
  final bool desktop;
  final double height;

  const EffectEditor({super.key, required this.c, required this.track, required this.slot, required this.color, required this.desktop, this.height = 0});

  /// Largura do editor no computador para a altura dada.
  static double widthFor(BuildContext context, DawController c, int track, EffectSlot slot, double height) {
    final x = _Fx(c, track, slot, Palette.accent, DefaultTextStyle.of(context).style);
    return switch (slot.kind) {
      EffectKind.eq => _EqEditor.widthFor(height),
      EffectKind.compressor || EffectKind.gate || EffectKind.limiter => _DynamicsEditor.widthFor(x, height),
      EffectKind.multiband || EffectKind.deesser || EffectKind.imager => _VizEditor.widthFor(x, height),
      _ => _GenericEditor.widthFor(x, height),
    };
  }

  @override
  Widget build(BuildContext context) {
    final x = _Fx(c, track, slot, color, DefaultTextStyle.of(context).style);
    return switch (slot.kind) {
      EffectKind.eq => _EqEditor(x: x, track: track, slot: slot, desktop: desktop, height: height),
      EffectKind.compressor || EffectKind.gate || EffectKind.limiter => _DynamicsEditor(x: x, track: track, slot: slot, desktop: desktop, height: height),
      EffectKind.multiband || EffectKind.deesser || EffectKind.imager => _VizEditor(x: x, track: track, slot: slot, desktop: desktop, height: height),
      _ => _GenericEditor(x: x, desktop: desktop, height: height),
    };
  }
}

/// O que os controles de um slot precisam: onde mandar as mudanças e como montar cada célula.
class _Fx {
  final DawController c;
  final int track;
  final EffectSlot slot;
  final Color color;

  /// Texto base do tema, para medir as células de opções como o `Knob` mede.
  final TextStyle base;

  _Fx(this.c, this.track, this.slot, this.color, this.base);

  EffectKind get kind => slot.kind;
  double v(int id) => slot.param(id);
  ParamSpec spec(int id) => kind.params.firstWhere((p) => p.id == id);

  void begin() => c.checkpoint();
  void set(int id, double value, {bool undoable = false}) => c.setEffectParam(track, slot.id, id, value, undoable: undoable);

  /// Parâmetro de faixa-chave (vira um menu com as faixas).
  bool isSidechain(ParamSpec p) => (kind == EffectKind.compressor && p.id == 10) || (kind == EffectKind.gate && p.id == 6);

  /// Delay, tremolo e filtro mostram a nota ou o tempo livre, conforme o parâmetro de tempo.
  bool visible(ParamSpec p) => switch (kind) {
    EffectKind.delay => p.id == 2 ? v(1) < 0.5 : (p.id == 3 ? v(1) >= 0.5 : true),
    EffectKind.tremolo => p.id == 0 ? v(4) < 0.5 : (p.id == 5 ? v(4) >= 0.5 : true),
    EffectKind.filter => p.id == 3 ? v(9) < 0.5 : (p.id == 10 ? v(9) >= 0.5 : true),
    _ => true,
  };

  /// O que não faz efeito com os ajustes de agora fica apagado (mas mexível).
  bool dimmed(ParamSpec p) => effectParamDimmed(kind, p, v);

  /// Os grupos da tabela, na ordem, só com os parâmetros visíveis (menos os de [skip]).
  /// Um grupo que reaparece mais adiante na tabela (a sobreamostragem da distorção, em "Saída"
  /// depois do bitcrusher) junta-se ao primeiro.
  List<_Group> groups(double knob, {Set<int> skip = const {}}) {
    final out = <String, _Group>{};
    for (final p in kind.params) {
      if (skip.contains(p.id) || !visible(p)) continue;
      (out[p.group] ??= _Group(p.group, [], _titleWidth(p.group, base))).cells.add(cell(p, knob));
    }
    return out.values.toList();
  }

  static const _choiceText = TextStyle(fontSize: 11, fontWeight: FontWeight.w600);

  _Cell cell(ParamSpec p, double knob) {
    final dim = dimmed(p);
    if (isSidechain(p)) return _sidechain(p, knob, dim);
    if (p.curve == Curve.choice && p.options.length == 2 && p.options[0] == 'Não') {
      return _Cell(
        _ToggleCell.width,
        _ToggleCell(label: p.name, on: v(p.id) >= 0.5, color: color, size: knob, dimmed: dim, onChanged: (on) => set(p.id, on ? 1 : 0, undoable: true)),
      );
    }
    final width = p.curve == Curve.choice ? choiceCellWidth(knob, options: p.options, style: base.merge(_choiceText)) : knobCellWidth(knob);
    Knob build(double value, Color color) => Knob(
      spec: p,
      value: value,
      size: knob,
      color: color,
      dimmed: dim,
      onChangeStart: (_) {
        c.autoRec.touch(track, AutoTarget(AutoKind.effect, ref: slot.id, param: p.id));
        begin();
      },
      onChangeEnd: (_) => c.autoRec.release(track, AutoTarget(AutoKind.effect, ref: slot.id, param: p.id)),
      onChanged: (value) => set(p.id, value, undoable: p.curve == Curve.choice),
      extraActions: () => midiLearnActions(c, track, AutoTarget(AutoKind.effect, ref: slot.id, param: p.id)),
    );
    final target = AutoTarget(AutoKind.effect, ref: slot.id, param: p.id);
    return _Cell(
      width,
      MidiLearnControl(
        c: c,
        track: track,
        target: target,
        // com automação e tocando, o knob segue a curva, em laranja
        child: c.automatedTarget(track, target)
            ? ValueListenableBuilder<double>(
                valueListenable: c.beat,
                builder: (_, _, _) => build(c.liveTargetValue(track, target, v(p.id)), c.playing.value ? automationColor : color),
              )
            : build(v(p.id), color),
      ),
    );
  }

  /// As opções do menu de sidechain por conteúdo: a mesma lista (e a mesma medida) entre builds.
  static final _options = <String, List<String>>{};

  /// Faixa-chave: "Própria entrada" e as outras faixas pelo nome. O valor é o índice da faixa.
  _Cell _sidechain(ParamSpec p, double knob, bool dim) {
    final tracks = c.doc.tracks;
    final current = v(p.id).round();
    // a própria faixa não serve de chave dela mesma (é a "Própria entrada")
    final values = <int>[
      -1,
      for (var i = 0; i < tracks.length; i++)
        if (i != track) i,
    ];
    final labels = <String>['Própria entrada', for (final i in values.skip(1)) tracks[i].name];
    if (!values.contains(current)) {
      values.add(current);
      labels.add(current == track ? 'Esta faixa' : 'Faixa ${current + 1} (removida)');
    }
    final options = _options.putIfAbsent(labels.join('\u0000'), () {
      if (_options.length > 64) _options.clear();
      return List.unmodifiable(labels);
    });
    final spec = ParamSpec.choice(p.id, p.name, p.group, options);
    return _Cell(
      choiceCellWidth(knob, options: options, style: base.merge(_choiceText)),
      Knob(
        spec: spec,
        value: values.indexOf(current).toDouble(),
        size: knob,
        color: color,
        dimmed: dim,
        onChanged: (i) => set(p.id, values[i.round().clamp(0, values.length - 1)].toDouble(), undoable: true),
      ),
    );
  }
}

class _Cell {
  final double width;
  final Widget child;
  const _Cell(this.width, this.child);
}

class _Group {
  final String title;
  final List<_Cell> cells;

  /// Largura do título: o grupo nunca fica mais estreito que ele.
  final double titleWidth;
  _Group(this.title, this.cells, this.titleWidth);
}

const _groupTitleStyle = TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: Colors.white38);
final _titleWidths = <String, double>{};

double _titleWidth(String title, TextStyle base) => _titleWidths[title] ??= () {
  final tp = TextPainter(
    text: TextSpan(text: title.toUpperCase(), style: base.merge(_groupTitleStyle)),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();
  final w = tp.width.ceilToDouble() + 2;
  tp.dispose();
  return w;
}();

// ------------------------------------------------------------------------ grupos de knobs

const _groupTitle = 16.0;
const _rowGap = 6.0;

/// Divisória entre grupos: 1 px com 9 de cada lado.
const _groupSep = 19.0;

/// Knob e fileiras que cabem na altura (computador): até três fileiras de knobs de 34 px ou mais;
/// abaixo disso uma fileira só, com o knob do tamanho que der.
(double, int) _knobFit(double height) {
  final avail = height - _groupTitle;
  for (final rows in const [3, 2]) {
    final s = (avail - (rows - 1) * _rowGap) / rows - 32;
    if (s >= 34) return (math.min(s, 44.0), rows);
  }
  return ((avail - 32).clamp(22.0, 46.0), 1);
}

List<List<_Cell>> _chunk(List<_Cell> cells, int rows) {
  final per = (cells.length / rows).ceil();
  return [for (var i = 0; i < cells.length; i += per) cells.sublist(i, math.min(i + per, cells.length))];
}

double _groupWidth(_Group g, int rows) => _chunk(g.cells, rows).map((r) => r.fold(0.0, (w, c) => w + c.width)).fold(g.titleWidth, math.max);

double _groupsWidth(List<_Group> groups, int rows) {
  if (groups.isEmpty) return 0;
  return groups.fold(0.0, (w, g) => w + _groupWidth(g, rows)) + (groups.length - 1) * _groupSep;
}

class _GroupTitle extends StatelessWidget {
  final String text;
  const _GroupTitle(this.text);

  @override
  Widget build(BuildContext context) => SizedBox(
    height: _groupTitle,
    child: Text(text.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: _groupTitleStyle),
  );
}

/// Grupos lado a lado, cada um em até [rows] fileiras (computador).
class _GroupsRow extends StatelessWidget {
  final List<_Group> groups;
  final int rows;
  final double knob;
  const _GroupsRow({required this.groups, required this.rows, required this.knob});

  @override
  Widget build(BuildContext context) {
    final cellH = knobCellHeight(knob);
    final children = <Widget>[];
    for (final g in groups) {
      final lines = _chunk(g.cells, rows);
      if (children.isNotEmpty) {
        children.add(
          Container(
            width: 1,
            height: _groupTitle + lines.length * cellH + (lines.length - 1) * _rowGap,
            margin: const EdgeInsets.symmetric(horizontal: (_groupSep - 1) / 2),
            color: Palette.hairline,
          ),
        );
      }
      children.add(
        SizedBox(
          width: _groupWidth(g, rows),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _GroupTitle(g.title),
              for (var i = 0; i < lines.length; i++) ...[
                if (i > 0) const SizedBox(height: _rowGap),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [for (final c in lines[i]) SizedBox(width: c.width, child: c.child)],
                ),
              ],
            ],
          ),
        ),
      );
    }
    return Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }
}

/// Grupos um embaixo do outro, os controles quebrando linha (celular).
class _GroupsColumn extends StatelessWidget {
  final List<_Group> groups;
  const _GroupsColumn({required this.groups});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 0; i < groups.length; i++) ...[
        if (i > 0) const SizedBox(height: 10),
        _GroupTitle(groups[i].title),
        Wrap(
          runSpacing: _rowGap,
          children: [for (final c in groups[i].cells) SizedBox(width: c.width, child: c.child)],
        ),
      ],
    ],
  );
}

/// Liga/desliga no formato da célula do knob: a pílula no lugar do knob, o nome embaixo.
class _ToggleCell extends StatelessWidget {
  static const width = 64.0;
  final String label;
  final bool on, dimmed;
  final Color color;
  final double size;
  final ValueChanged<bool> onChanged;

  const _ToggleCell({required this.label, required this.on, required this.color, required this.size, required this.dimmed, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final tint = dimmed ? color.withValues(alpha: 0.4) : color;
    return Semantics(
      toggled: on,
      label: label,
      button: true,
      onTap: () => onChanged(!on),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onChanged(!on),
          child: SizedBox(
            width: width,
            height: knobCellHeight(size),
            child: Column(
              children: [
                SizedBox(
                  height: 15,
                  child: Text(
                    on ? 'Sim' : 'Não',
                    style: TextStyle(fontSize: 10.5, height: 1.2, color: on ? tint : Colors.white38, fontWeight: on ? FontWeight.w700 : FontWeight.w500),
                  ),
                ),
                SizedBox(
                  height: size,
                  child: Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      width: 34,
                      height: 18,
                      padding: const EdgeInsets.all(2),
                      alignment: on ? Alignment.centerRight : Alignment.centerLeft,
                      decoration: BoxDecoration(
                        color: on ? tint.withValues(alpha: 0.28) : Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(color: on ? tint.withValues(alpha: 0.7) : Palette.hairlineStrong),
                      ),
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: on ? tint : Colors.white38),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                SizedBox(
                  height: 14,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(label, maxLines: 1, style: TextStyle(fontSize: 10.5, height: 1.2, color: dimmed ? Colors.white30 : Colors.white70)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------------ genérico

class _GenericEditor extends StatelessWidget {
  final _Fx x;
  final bool desktop;
  final double height;
  const _GenericEditor({required this.x, required this.desktop, required this.height});

  static double widthFor(_Fx x, double height) {
    final (knob, rows) = _knobFit(height);
    return _groupsWidth(x.groups(knob), rows);
  }

  @override
  Widget build(BuildContext context) {
    if (!desktop) return _GroupsColumn(groups: x.groups(44));
    final (knob, rows) = _knobFit(height);
    return _GroupsRow(groups: x.groups(knob), rows: rows, knob: knob);
  }
}

// ------------------------------------------------------------------------ valor arrastável

/// Um valor em texto que se muda arrastando na vertical (Shift: fino) ou com a roda; duplo clique
/// volta ao padrão e o botão direito (toque longo no celular) abre um campo para digitar. As listas
/// compactas (bandas do EQ) usam no lugar do knob.
class ParamDrag extends StatefulWidget {
  final ParamSpec spec;
  final double value;
  final Color color;
  final bool dimmed;
  final VoidCallback onChangeStart;
  final ValueChanged<double> onChanged;
  final String Function(double v)? format;
  final String? label;
  final TextAlign align;
  final double fontSize;

  const ParamDrag({
    super.key,
    required this.spec,
    required this.value,
    required this.onChangeStart,
    required this.onChanged,
    this.color = Palette.accent,
    this.dimmed = false,
    this.format,
    this.label,
    this.align = TextAlign.right,
    this.fontSize = 11,
  });

  @override
  State<ParamDrag> createState() => _ParamDragState();
}

class _ParamDragState extends State<ParamDrag> {
  bool _active = false, _changed = false, _hover = false;
  double _norm = 0, _last = 0;
  Timer? _wheelIdle;

  ParamSpec get _spec => widget.spec;
  String _fmt(double v) => (widget.format ?? _spec.format)(v);

  @override
  void dispose() {
    _wheelIdle?.cancel();
    super.dispose();
  }

  void _begin() {
    if (_active) return;
    _active = true;
    _changed = false;
    _last = _spec.clamp(widget.value);
    _norm = _spec.toNorm(_last);
    setState(() {});
  }

  void _emit(double v) {
    v = _spec.clamp(v);
    if (v == _last) return;
    if (!_changed) {
      _changed = true;
      widget.onChangeStart();
    }
    _last = v;
    widget.onChanged(v);
  }

  void _end() {
    _wheelIdle?.cancel();
    _wheelIdle = null;
    if (!_active) return;
    _active = false;
    _changed = false;
    if (mounted) setState(() {});
  }

  void _set(double v) {
    _end();
    _begin();
    _emit(v);
    _end();
  }

  void _wheel(Offset delta) {
    final dy = delta.dy != 0 ? delta.dy : delta.dx;
    if (dy == 0) return;
    _begin();
    if (_spec.curve == Curve.integer) {
      _emit(_last - dy.sign);
    } else {
      final travel = HardwareKeyboard.instance.isShiftPressed ? 8000.0 : 1600.0;
      _norm = (_norm - dy / travel).clamp(0.0, 1.0);
      _emit(_spec.fromNorm(_norm));
    }
    _wheelIdle?.cancel();
    _wheelIdle = Timer(const Duration(milliseconds: 500), _end);
  }

  Future<void> _type() async {
    _end();
    final v = await askParamValue(context, _spec, widget.value, widget.label ?? _spec.name, _fmt);
    if (v != null && mounted) _set(v);
  }

  @override
  Widget build(BuildContext context) {
    final value = _spec.clamp(widget.value);
    final color = _active ? widget.color : (widget.dimmed ? Colors.white30 : (_hover ? Colors.white : Colors.white70));
    return Semantics(
      slider: true,
      label: widget.label ?? _spec.name,
      value: _fmt(value),
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeUpDown,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: Listener(
          onPointerSignal: (e) {
            if (e is PointerScrollEvent) GestureBinding.instance.pointerSignalResolver.register(e, (ev) => _wheel((ev as PointerScrollEvent).scrollDelta));
          },
          child: GestureDetector(
            supportedDevices: const {PointerDeviceKind.touch, PointerDeviceKind.stylus, PointerDeviceKind.invertedStylus},
            onLongPress: _type,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragStart: (_) {
                _end();
                _begin();
              },
              onVerticalDragUpdate: (d) {
                final travel = HardwareKeyboard.instance.isShiftPressed ? 1000.0 : 200.0;
                _norm = (_norm - d.delta.dy / travel).clamp(0.0, 1.0);
                _emit(_spec.fromNorm(_norm));
              },
              onVerticalDragEnd: (_) => _end(),
              onVerticalDragCancel: _end,
              onDoubleTap: () {
                if (_spec.clamp(widget.value) != _spec.def) _set(_spec.def);
              },
              onSecondaryTap: _type,
              child: Container(
                alignment: widget.align == TextAlign.right ? Alignment.centerRight : (widget.align == TextAlign.left ? Alignment.centerLeft : Alignment.center),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: _active ? widget.color.withValues(alpha: 0.14) : (_hover ? Colors.white.withValues(alpha: 0.06) : null),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    _fmt(value),
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: widget.fontSize,
                      color: color,
                      fontWeight: _active ? FontWeight.w700 : FontWeight.w500,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Pede um valor digitado ("800 Hz", "2,5 kHz", "-3 dB", "150 ms"); null se cancelar.
Future<double?> askParamValue(BuildContext context, ParamSpec spec, double value, String label, String Function(double) format) => showDialog<double>(
  context: context,
  builder: (_) => _ValueDialog(spec: spec, value: value, label: label, format: format),
);

class _ValueDialog extends StatefulWidget {
  final ParamSpec spec;
  final double value;
  final String label;
  final String Function(double) format;
  const _ValueDialog({required this.spec, required this.value, required this.label, required this.format});

  @override
  State<_ValueDialog> createState() => _ValueDialogState();
}

class _ValueDialogState extends State<_ValueDialog> {
  late final _ctl = TextEditingController(text: widget.format(widget.value))
    ..selection = TextSelection(baseOffset: 0, extentOffset: widget.format(widget.value).length);
  String? _error;

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _done() {
    final v = parseParamValue(widget.spec, _ctl.text);
    if (v == null) {
      setState(() => _error = 'Não entendi. Use um número, com a unidade se quiser.');
      return;
    }
    Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.label),
    content: SizedBox(
      width: 320,
      child: TextField(
        controller: _ctl,
        autofocus: true,
        decoration: InputDecoration(helperText: 'De ${widget.format(widget.spec.min)} a ${widget.format(widget.spec.max)}', errorText: _error),
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        onSubmitted: (_) => _done(),
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
      FilledButton(onPressed: _done, child: const Text('Aplicar')),
    ],
  );
}

// ------------------------------------------------------------------------ EQ: o editor

/// Toque ou clique que reivindica o gesto já no toque quando cai num nó (ou quando já há um nó
/// sendo arrastado, para a pinça): sem isso, a rolagem da lista em volta levaria o arraste.
class _ClaimScaleRecognizer extends ScaleGestureRecognizer {
  _ClaimScaleRecognizer({super.debugOwner});

  bool Function(PointerDownEvent e)? claims;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    if (claims?.call(event) ?? false) resolvePointer(event.pointer, GestureDisposition.accepted);
  }
}

/// Mapa entre o gráfico e os valores: frequência logarítmica de 20 Hz a 20 kHz, ±24 dB.
class _EqGeom {
  final Size size;
  const _EqGeom(this.size);

  static const padX = 8.0, padY = 10.0, range = 24.0;
  static final _span = math.log(1000);

  double get _w => math.max(1, size.width - 2 * padX);
  double get _h => math.max(1, size.height - 2 * padY);

  double xOf(double f) => padX + math.log(math.max(f, 1) / 20) / _span * _w;
  double fOf(double x) => 20 * math.exp((x - padX) / _w * _span);
  double yOf(double db) => padY + (range - db) / (2 * range) * _h;
  double dbOf(double y) => range - (y - padY) / _h * 2 * range;

  Offset node(EqBand b) => Offset(xOf(b.freq.clamp(20.0, 20000.0)), yOf(b.nodeDb.clamp(-range, range)));
}

/// Texto de uma banda para o rótulo do nó.
String eqBandLabel(EqBand b) {
  final parts = <String>['${b.index + 1} · ${eqBandTypes[b.type]}', eqParams[b.index * 6 + 2].format(b.freq)];
  if (b.hasGain) parts.add(eqParams[b.index * 6 + 3].format(b.gain));
  if (b.isCut) parts.add('${const ['12', '24', '48'][b.slope]} dB/oit');
  parts.add('Q ${b.q.toStringAsFixed(2)}');
  if (!b.on) parts.add('(desligada)');
  return parts.join('   ');
}

class _EqEditor extends StatefulWidget {
  final _Fx x;
  final int track;
  final EffectSlot slot;
  final bool desktop;
  final double height;
  const _EqEditor({required this.x, required this.track, required this.slot, required this.desktop, required this.height});

  static const _listWidth = 236.0;

  static double _graphWidth(double height) => (height * 1.7).clamp(300.0, 520.0);

  static double widthFor(double height) => _graphWidth(height) + 12 + _listWidth;

  @override
  State<_EqEditor> createState() => _EqEditorState();
}

class _EqEditorState extends State<_EqEditor> {
  /// Banda escolhida (nó realçado, linha da lista) e a que está sob o mouse.
  int _selected = -1, _hover = -1;

  /// Banda arrastada no gesto atual (null: nenhuma) e se o gesto já mudou algo.
  int? _drag;
  bool _changed = false, _moves = false, _suppress = false;

  /// Dedos (ou botões) no gráfico agora, e a banda sob o último toque.
  int _down = 0, _downHit = -1;

  /// Último ponto do dedo, onde o nó começou e onde ele está (sem limites: o valor é que é
  /// limitado). Anda por incrementos, para o Shift (fino) valer do meio do arraste em diante sem
  /// salto.
  Offset _lastFocal = Offset.zero, _nodeFrom = Offset.zero, _nodeAt = Offset.zero;
  int _pointers = 0;
  double _pinchQ = 1, _pinchScale = 1;

  Size _size = Size.zero;
  Duration? _lastTap;
  Offset _lastTapAt = Offset.zero;
  Timer? _wheelIdle;
  bool _wheelChanged = false;
  final _smoother = _SpectrumSmoother();
  late final _watch = _Watch.of(widget.x.c);

  _Fx get x => widget.x;
  _EqGeom get _geom => _EqGeom(_size);
  List<EqBand> get _bands => eqBands(x.v);

  @override
  void initState() {
    super.initState();
    _watch.addEq(this);
  }

  @override
  void dispose() {
    _wheelIdle?.cancel();
    _watch.removeEq(this);
    super.dispose();
  }

  // --------------------------------------------------------------- mudanças

  /// Um passo de um gesto contínuo: o ponto de desfazer vai na primeira mudança de fato.
  void _step(int id, double value) {
    final p = eqParams[id];
    final v = p.clamp(value);
    if ((x.v(id) - v).abs() < 1e-9) return;
    if (!_changed) {
      _changed = true;
      x.begin();
    }
    x.set(id, v);
  }

  void _select(int b) {
    if (_selected != b) setState(() => _selected = b);
  }

  // --------------------------------------------------------------- nós

  int _hit(Offset p, PointerDeviceKind kind) {
    final radius = kind == PointerDeviceKind.mouse ? 11.0 : 22.0;
    final g = _geom;
    var best = -1;
    var bestD = radius;
    for (final b in _bands) {
      final d = (g.node(b) - p).distance;
      // em empate, a banda ligada ganha da desligada
      if (d < bestD || (d == bestD && best >= 0 && b.on && !_bands[best].on)) {
        best = b.index;
        bestD = d;
      }
    }
    return best;
  }

  bool _claims(PointerDownEvent e) => _drag != null || _hit(e.localPosition, e.kind) >= 0;

  void _pointerDown(PointerDownEvent e) {
    final first = _down == 0;
    _down++;
    if (e.kind == PointerDeviceKind.mouse && e.buttons != kPrimaryMouseButton) return;
    final hit = _hit(e.localPosition, e.kind);
    _downHit = hit;
    final last = _lastTap;
    if (first && last != null && e.timeStamp - last < const Duration(milliseconds: 350) && (e.localPosition - _lastTapAt).distance < 16) {
      _lastTap = null;
      _suppress = true;
      _doubleTap(e.localPosition, hit);
      return;
    }
    _lastTap = e.timeStamp;
    _lastTapAt = e.localPosition;
    _suppress = false;
    if (hit >= 0) _select(hit);
  }

  /// Duplo clique: num nó liga/desliga a banda; no vazio acende uma banda livre ali (sino).
  void _doubleTap(Offset p, int hit) {
    if (hit >= 0) {
      _select(hit);
      x.set(hit * 6, x.v(hit * 6) >= 0.5 ? 0 : 1, undoable: true);
      return;
    }
    final bands = _bands;
    final free = bands.where((b) => !b.on).toList()..sort((a, b) => (a.hasGain ? 0 : 1).compareTo(b.hasGain ? 0 : 1));
    if (free.isEmpty) return;
    final b = free.first.index;
    final g = _geom;
    x.begin();
    x.set(b * 6 + 1, 2);
    x.set(b * 6 + 2, eqParams[b * 6 + 2].clamp(g.fOf(p.dx)));
    x.set(b * 6 + 3, eqParams[b * 6 + 3].clamp(g.dbOf(p.dy)));
    x.set(b * 6 + 4, 1);
    x.set(b * 6, 1);
    _select(b);
  }

  void _scaleStart(ScaleStartDetails d) {
    if (_suppress) return;
    final hit = d.pointerCount <= 1 ? _downHit : -1;
    _moves = hit >= 0;
    final b = hit >= 0 ? hit : (d.pointerCount >= 2 ? _selected : -1);
    if (b < 0) return;
    _select(b);
    setState(() => _drag = b);
    _changed = false;
    _pointers = d.pointerCount;
    _lastFocal = d.localFocalPoint;
    _nodeFrom = _nodeAt = _geom.node(_bands[b]);
    _pinchQ = x.v(b * 6 + 4);
    _pinchScale = 1;
  }

  void _scaleUpdate(ScaleUpdateDetails d) {
    final b = _drag;
    if (b == null) return;
    if (d.pointerCount != _pointers) {
      // dedo entrou ou saiu: o gesto recomeça do estado atual, sem salto
      _pointers = d.pointerCount;
      _lastFocal = d.localFocalPoint;
      _nodeFrom = _nodeAt = _geom.node(_bands[b]);
      _pinchQ = x.v(b * 6 + 4);
      _pinchScale = d.scale == 0 ? 1 : d.scale;
      return;
    }
    if (d.pointerCount >= 2) {
      // abrir os dedos alarga a banda (Q menor)
      if (d.scale > 0) _step(b * 6 + 4, _pinchQ * _pinchScale / d.scale);
      return;
    }
    if (!_moves) return;
    final fine = HardwareKeyboard.instance.isShiftPressed ? 0.2 : 1.0;
    _nodeAt += (d.localFocalPoint - _lastFocal) * fine;
    _lastFocal = d.localFocalPoint;
    final p = _nodeAt;
    final g = _geom;
    final band = _bands[b];
    _step(b * 6 + 2, g.fOf(p.dx));
    if (band.hasGain) {
      _step(b * 6 + 3, g.dbOf(p.dy));
    } else if (band.isCut) {
      // a altura do nó é a ressonância (|H(f0)| = Q em qualquer inclinação); relativa ao começo,
      // porque o nó de um Q alto fica preso no topo do gráfico e o absoluto daria um salto
      final db = g.dbOf(p.dy) - g.dbOf(_nodeFrom.dy);
      _step(b * 6 + 4, _pinchQ * math.pow(10, db / 20).toDouble());
    }
  }

  void _scaleEnd() {
    _pointers = 0;
    if (_drag == null) return;
    setState(() => _drag = null);
    _changed = false;
  }

  /// Roda do mouse: Q da banda sob o mouse (ou da escolhida). Pinça do trackpad também.
  void _signal(PointerSignalEvent e) {
    final b = _hover >= 0 ? _hover : _selected;
    if (b < 0) return;
    if (e is PointerScrollEvent) {
      GestureBinding.instance.pointerSignalResolver.register(e, (ev) {
        final dy = (ev as PointerScrollEvent).scrollDelta.dy;
        if (dy == 0) return;
        final speed = HardwareKeyboard.instance.isShiftPressed ? 2000.0 : 400.0;
        _wheelQ(b, x.v(b * 6 + 4) * math.exp(-dy / speed));
      });
    } else if (e is PointerScaleEvent) {
      GestureBinding.instance.pointerSignalResolver.register(e, (ev) {
        final s = (ev as PointerScaleEvent).scale;
        if (s > 0) _wheelQ(b, x.v(b * 6 + 4) / s);
      });
    }
  }

  void _wheelQ(int b, double q) {
    final p = eqParams[b * 6 + 4];
    final v = p.clamp(q);
    if ((x.v(b * 6 + 4) - v).abs() < 1e-9) return;
    if (!_wheelChanged) {
      _wheelChanged = true;
      x.begin();
    }
    x.set(b * 6 + 4, v);
    _select(b);
    _wheelIdle?.cancel();
    _wheelIdle = Timer(const Duration(milliseconds: 500), () => _wheelChanged = false);
  }

  // --------------------------------------------------------------- montagem

  @override
  Widget build(BuildContext context) {
    final graph = _graph(context);
    final list = _BandList(x: x, selected: _selected, onSelect: _select, compact: widget.desktop);
    if (!widget.desktop) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: 180, child: graph),
          const SizedBox(height: 10),
          list,
        ],
      );
    }
    return SizedBox(
      height: widget.height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(width: _EqEditor._graphWidth(widget.height), child: graph),
          const SizedBox(width: 12),
          SizedBox(
            width: _EqEditor._listWidth,
            child: SingleChildScrollView(child: list),
          ),
        ],
      ),
    );
  }

  Widget _graph(BuildContext context) {
    final bands = _bands;
    final active = _drag ?? (_hover >= 0 ? _hover : null);
    final font = DefaultTextStyle.of(context).style.fontFamily;
    return ClipRRect(
      key: const ValueKey('eq-graph'),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        color: Palette.ink,
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Palette.hairline),
        ),
        child: LayoutBuilder(
          builder: (context, box) {
            _size = box.biggest;
            return MouseRegion(
              cursor: _drag != null ? SystemMouseCursors.grabbing : (_hover >= 0 ? SystemMouseCursors.grab : SystemMouseCursors.basic),
              onHover: (e) {
                final h = _hit(e.localPosition, PointerDeviceKind.mouse);
                if (h != _hover) setState(() => _hover = h);
              },
              onExit: (_) {
                if (_hover >= 0) setState(() => _hover = -1);
              },
              child: Listener(
                onPointerDown: _pointerDown,
                onPointerUp: (_) => _down = math.max(0, _down - 1),
                onPointerCancel: (_) => _down = math.max(0, _down - 1),
                onPointerSignal: _signal,
                child: RawGestureDetector(
                  behavior: HitTestBehavior.opaque,
                  gestures: {
                    _ClaimScaleRecognizer: GestureRecognizerFactoryWithHandlers<_ClaimScaleRecognizer>(() => _ClaimScaleRecognizer(debugOwner: this), (r) {
                      r
                        ..claims = _claims
                        ..onStart = _scaleStart
                        ..onUpdate = _scaleUpdate
                        ..onEnd = (_) => _scaleEnd();
                    }),
                  },
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      RepaintBoundary(child: CustomPaint(painter: _SpectrumPainter(x.c.spectrum, _smoother, x.c.engineRate))),
                      CustomPaint(
                        painter: _EqPainter(
                          values: Float64List.fromList([for (var id = 0; id <= 48; id++) x.v(id)]),
                          selected: _selected,
                          active: active,
                          color: x.color,
                          bypassed: widget.slot.bypass,
                          fontFamily: font,
                        ),
                      ),
                      if (bands.every((b) => !b.on))
                        const Positioned(
                          left: 10,
                          right: 10,
                          bottom: 22,
                          child: Text(
                            'Todas as bandas desligadas. Duplo clique no gráfico acende uma banda ali.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 10.5, color: Colors.white54),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Espectro ao vivo com queda suave: sobe na hora e desce a 36 dB/s, como os analisadores de DAW
/// (o quadro a quadro cru pisca demais para ler).
class _SpectrumSmoother {
  Float32List? _display;
  final _clock = Stopwatch()..start();
  double _last = 0;

  static const _floor = -120.0, _fall = 36.0;

  Float32List? update(Float32List? fresh) {
    final t = _clock.elapsedMicroseconds / 1e6;
    final dt = (t - _last).clamp(0.0, 0.25);
    _last = t;
    var d = _display;
    if (fresh == null) {
      if (d == null) return null;
      var alive = false;
      for (var i = 0; i < d.length; i++) {
        d[i] = math.max(_floor, d[i] - _fall * dt);
        if (d[i] > _floor + 1) alive = true;
      }
      if (!alive) _display = null;
      return _display;
    }
    if (d == null || d.length != fresh.length) {
      d = _display = Float32List(fresh.length)..fillRange(0, fresh.length, _floor);
    }
    final fall = _fall * dt;
    for (var i = 0; i < d.length; i++) {
      final v = fresh[i].isFinite ? fresh[i] : _floor;
      final down = d[i] - fall;
      d[i] = v > down ? v : down;
    }
    return d;
  }
}

class _SpectrumPainter extends CustomPainter {
  final ValueNotifier<Float32List?> spectrum;
  final _SpectrumSmoother smoother;

  /// Taxa do motor: as faixas do espectro vão de 0 à metade dela.
  final double rate;
  _SpectrumPainter(this.spectrum, this.smoother, this.rate) : super(repaint: spectrum);

  /// Faixa desenhada (dB, depois da inclinação) e a inclinação de 3 dB por oitava em volta de
  /// 1 kHz: música tem menos energia por faixa linear nos agudos, e sem isso a metade de cima do
  /// gráfico ficaria vazia.
  static const _top = 0.0, _bottom = -90.0, _tilt = 3.0;

  @override
  void paint(Canvas canvas, Size size) {
    final data = smoother.update(spectrum.value);
    if (data == null || data.isEmpty || size.width < 4) return;
    final g = _EqGeom(size);
    final binHz = rate / 2 / data.length;
    double at(double pos) {
      final i = pos.floor().clamp(0, data.length - 1);
      final j = math.min(i + 1, data.length - 1);
      final t = (pos - i).clamp(0.0, 1.0);
      return data[i] + (data[j] - data[i]) * t;
    }

    final path = Path();
    final x0 = g.xOf(20), x1 = g.xOf(20000);
    path.moveTo(x0, size.height);
    const step = 2.0;
    for (var px = x0; px <= x1 + 0.01; px += step) {
      final f = g.fOf(px), f2 = g.fOf(px + step);
      final p = f / binHz, p2 = f2 / binHz;
      double db;
      if (p2 - p < 1) {
        db = at(p);
      } else {
        // várias faixas no mesmo pixel (agudos): o maior pico, que é o que o ouvido pega
        db = -200;
        for (var k = p.floor(); k <= math.min(p2.floor(), data.length - 1); k++) {
          if (data[k] > db) db = data[k];
        }
      }
      db += _tilt * math.log(f / 1000) / math.ln2;
      final t = ((db - _bottom) / (_top - _bottom)).clamp(0.0, 1.0);
      path.lineTo(px, size.height - t * size.height);
    }
    path
      ..lineTo(x1, size.height)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white.withValues(alpha: 0.13), Colors.white.withValues(alpha: 0.03)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.16),
    );
  }

  @override
  bool shouldRepaint(_SpectrumPainter o) => o.spectrum != spectrum || o.smoother != smoother || o.rate != rate;
}

final _labelCache = <String, TextPainter>{};

/// Rótulo pequeno de eixo (o texto se repete a cada quadro: fica guardado).
TextPainter _axisLabel(String text, String? font, {Color color = Colors.white30}) {
  final key = '$text|$font|${color.toARGB32()}';
  final hit = _labelCache[key];
  if (hit != null) return hit;
  // os números ao vivo (medidor, limiar) variam: o guardado não cresce sem fim
  if (_labelCache.length > 400) {
    for (final tp in _labelCache.values) {
      tp.dispose();
    }
    _labelCache.clear();
  }
  return _labelCache[key] = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(fontSize: 9, color: color, fontFamily: font, fontFeatures: const [FontFeature.tabularFigures()]),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
}

class _EqPainter extends CustomPainter {
  /// Os 49 parâmetros no momento da pintura: o slot muda no lugar, então a comparação é por cópia.
  final Float64List values;
  final int selected;
  final int? active;
  final Color color;
  final bool bypassed;
  final String? fontFamily;

  _EqPainter({required this.values, required this.selected, required this.active, required this.color, required this.bypassed, this.fontFamily});

  static final _grid = Paint()..color = Colors.white.withValues(alpha: 0.05);
  static final _gridStrong = Paint()..color = Colors.white.withValues(alpha: 0.1);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width < 8 || size.height < 8) return;
    final g = _EqGeom(size);
    final bands = eqBands((id) => values[id]);
    final w = size.width, h = size.height;

    for (final f in const [50.0, 100.0, 200.0, 500.0, 1000.0, 2000.0, 5000.0, 10000.0]) {
      final x = g.xOf(f);
      canvas.drawLine(Offset(x, 0), Offset(x, h), f == 100 || f == 1000 || f == 10000 ? _gridStrong : _grid);
    }
    for (final db in const [-18.0, -12.0, -6.0, 6.0, 12.0, 18.0]) {
      canvas.drawLine(Offset(0, g.yOf(db)), Offset(w, g.yOf(db)), _grid);
    }
    canvas.drawLine(Offset(0, g.yOf(0)), Offset(w, g.yOf(0)), _gridStrong);
    for (final (f, t) in const [(100.0, '100'), (1000.0, '1k'), (10000.0, '10k')]) {
      final tp = _axisLabel(t, fontFamily);
      tp.paint(canvas, Offset(g.xOf(f) + 3, h - tp.height - 2));
    }
    if (h > 90) {
      for (final (db, t) in const [(12.0, '+12'), (-12.0, '−12')]) {
        final tp = _axisLabel(t, fontFamily);
        tp.paint(canvas, Offset(w - tp.width - 4, g.yOf(db) - tp.height - 1));
      }
    }

    final x0 = g.xOf(20), x1 = g.xOf(20000);
    final n = math.max(8, ((x1 - x0) / 1.5).ceil());
    Path curve(double Function(double f) dbAt) {
      final p = Path();
      for (var i = 0; i <= n; i++) {
        final px = x0 + (x1 - x0) * i / n;
        final py = g.yOf(dbAt(g.fOf(px))).clamp(-4.0, h + 4);
        i == 0 ? p.moveTo(px, py) : p.lineTo(px, py);
      }
      return p;
    }

    Path area(Path p) => Path.from(p)
      ..lineTo(x1, g.yOf(0))
      ..lineTo(x0, g.yOf(0))
      ..close();

    final tint = bypassed ? Colors.white38 : color;

    // a banda em foco sozinha, por baixo da soma
    final focus = active ?? (selected >= 0 ? selected : null);
    if (focus != null && bands[focus].on) {
      final bc = eqBandColors[focus];
      final p = curve((f) => bands[focus].db(f));
      canvas.drawPath(area(p), Paint()..color = bc.withValues(alpha: 0.14));
      canvas.drawPath(
        p,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = bc.withValues(alpha: 0.55),
      );
    }

    final sum = curve((f) => eqResponseDb(bands, f));
    canvas.drawPath(
      area(sum),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [tint.withValues(alpha: 0.2), tint.withValues(alpha: 0.02), tint.withValues(alpha: 0.2)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      sum,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeJoin = StrokeJoin.round
        ..color = tint,
    );

    // nós: desligados vazados; o escolhido com anel
    for (final b in bands) {
      final c = g.node(b);
      final bc = bypassed ? Colors.white54 : eqBandColors[b.index];
      if (b.index == selected || b.index == active) {
        canvas.drawCircle(
          c,
          11,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = bc.withValues(alpha: b.index == selected ? 0.8 : 0.4),
        );
      }
      if (b.on) {
        canvas.drawCircle(c, 7, Paint()..color = bc);
      } else {
        canvas.drawCircle(c, 7, Paint()..color = Palette.ink.withValues(alpha: 0.85));
        canvas.drawCircle(
          c,
          7,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2
            ..color = bc.withValues(alpha: 0.5),
        );
      }
      final tp = _axisLabel('${b.index + 1}', fontFamily, color: b.on ? const Color(0xFF101318) : bc.withValues(alpha: 0.7));
      tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
    }

    // rótulo da banda arrastada ou sob o mouse
    final a = active;
    if (a != null) {
      final b = bands[a];
      final tp = TextPainter(
        text: TextSpan(
          text: eqBandLabel(b),
          style: TextStyle(fontSize: 10.5, color: Colors.white, fontFamily: fontFamily, fontFeatures: const [FontFeature.tabularFigures()]),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout(maxWidth: math.max(40.0, w - 12));
      final c = g.node(b);
      final bw = tp.width + 12, bh = tp.height + 6;
      final left = (c.dx - bw / 2).clamp(4.0, math.max(4.0, w - bw - 4)).toDouble();
      final top = c.dy - 16 - bh >= 2 ? c.dy - 16 - bh : math.min<double>(h - bh - 2, c.dy + 16);
      final r = RRect.fromRectAndRadius(Rect.fromLTWH(left, top, bw, bh), const Radius.circular(5));
      canvas.drawRRect(r, Paint()..color = const Color(0xE62A2F38));
      canvas.drawRRect(
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = eqBandColors[a].withValues(alpha: 0.6),
      );
      tp.paint(canvas, Offset(left + 6, top + 3));
      tp.dispose();
    }
  }

  @override
  bool shouldRepaint(_EqPainter o) {
    if (o.selected != selected || o.active != active || o.color != color || o.bypassed != bypassed || o.fontFamily != fontFamily) return true;
    for (var i = 0; i < values.length; i++) {
      if (o.values[i] != values[i]) return true;
    }
    return false;
  }
}

/// Lista das bandas: liga/desliga, tipo, frequência, ganho (ou inclinação nos passa-alta/baixa)
/// e Q, e o ganho de saída no pé.
class _BandList extends StatelessWidget {
  final _Fx x;
  final int selected;
  final ValueChanged<int> onSelect;

  /// Computador: linhas baixas e o tipo só pelo desenho; celular: linhas para o dedo.
  final bool compact;
  const _BandList({required this.x, required this.selected, required this.onSelect, required this.compact});

  static const _toggleW = 26.0, _typeW = 40.0, _valueW = 62.0, _qW = 46.0;

  @override
  Widget build(BuildContext context) {
    final rowH = compact ? 22.0 : 36.0;
    const head = TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: Colors.white38);
    Widget cells(List<Widget> c) => Row(children: c);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 16,
          child: cells([
            const SizedBox(
              width: _toggleW,
              child: Text('#', textAlign: TextAlign.center, style: head),
            ),
            if (compact)
              const SizedBox(
                width: _typeW,
                child: Text('TIPO', style: head),
              )
            else
              const Expanded(child: Text('TIPO', style: head)),
            const SizedBox(
              width: _valueW,
              child: Text('FREQ.', textAlign: TextAlign.right, style: head),
            ),
            const SizedBox(
              width: _valueW,
              child: Text('GANHO', textAlign: TextAlign.right, style: head),
            ),
            const SizedBox(
              width: _qW,
              child: Text('Q', textAlign: TextAlign.right, style: head),
            ),
          ]),
        ),
        for (var b = 0; b < 8; b++) _row(context, EqBand.of(x.v, b), rowH),
        const SizedBox(height: 4),
        SizedBox(
          height: rowH,
          child: Row(
            children: [
              const SizedBox(width: _toggleW),
              const Expanded(
                child: Text('Saída', style: TextStyle(fontSize: 11, color: Colors.white60)),
              ),
              SizedBox(
                width: _valueW + _qW,
                child: ParamDrag(spec: eqParams[48], value: x.v(48), color: x.color, onChangeStart: x.begin, onChanged: (v) => x.set(48, v)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _row(BuildContext context, EqBand b, double rowH) {
    final i = b.index;
    final bc = eqBandColors[i];
    final sel = i == selected;
    final dim = !b.on;
    ParamDrag drag(int k, {String Function(double)? format}) => ParamDrag(
      spec: eqParams[i * 6 + k],
      value: x.v(i * 6 + k),
      color: bc,
      dimmed: dim,
      format: format,
      label: 'Banda ${i + 1}: ${eqParams[i * 6 + k].name}',
      onChangeStart: x.begin,
      onChanged: (v) {
        onSelect(i);
        x.set(i * 6 + k, v);
      },
    );

    final gain = b.hasGain
        ? drag(3)
        : b.isCut
        ? _SlopeMenu(value: b.slope, color: bc, dimmed: dim, onChanged: (s) => x.set(i * 6 + 5, s.toDouble(), undoable: true))
        : const Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: EdgeInsets.only(right: 6),
              child: Text('—', style: TextStyle(fontSize: 11, color: Colors.white24)),
            ),
          );
    final type = _TypeMenu(value: b.type, color: bc, dimmed: dim, showName: !compact, onChanged: (t) => x.set(i * 6 + 1, t.toDouble(), undoable: true));
    return Listener(
      onPointerDown: (_) => onSelect(i),
      child: Container(
        height: rowH,
        margin: const EdgeInsets.only(bottom: 1),
        decoration: BoxDecoration(color: sel ? bc.withValues(alpha: 0.12) : Colors.transparent, borderRadius: BorderRadius.circular(5)),
        child: Row(
          children: [
            SizedBox(
              width: _toggleW,
              child: _BandToggle(index: i, on: b.on, color: bc, onChanged: (on) => x.set(i * 6, on ? 1 : 0, undoable: true)),
            ),
            if (compact) SizedBox(width: _typeW, child: type) else Expanded(child: type),
            SizedBox(width: _valueW, child: drag(2)),
            SizedBox(width: _valueW, child: gain),
            SizedBox(
              width: _qW,
              child: drag(4, format: (v) => v.toStringAsFixed(v < 10 ? 2 : 1)),
            ),
          ],
        ),
      ),
    );
  }
}

/// O número da banda num círculo: cheio quando ligada; tocar liga/desliga.
class _BandToggle extends StatelessWidget {
  final int index;
  final bool on;
  final Color color;
  final ValueChanged<bool> onChanged;
  const _BandToggle({required this.index, required this.on, required this.color, required this.onChanged});

  @override
  Widget build(BuildContext context) => Tooltip(
    message: on ? 'Desligar a banda ${index + 1}' : 'Ligar a banda ${index + 1}',
    waitDuration: const Duration(milliseconds: 700),
    child: InkResponse(
      onTap: () => onChanged(!on),
      radius: 14,
      child: Center(
        child: Container(
          width: 17,
          height: 17,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: on ? color : Colors.transparent,
            border: Border.all(color: on ? color : color.withValues(alpha: 0.5), width: 1.2),
          ),
          child: Text(
            '${index + 1}',
            style: TextStyle(fontSize: 9.5, height: 1, fontWeight: FontWeight.w800, color: on ? const Color(0xFF101318) : color.withValues(alpha: 0.8)),
          ),
        ),
      ),
    ),
  );
}

/// Nomes curtos dos tipos para a linha da banda no celular (o menu mostra os inteiros).
const _shortTypes = ['Passa-alta', 'Prat. grave', 'Sino', 'Prat. aguda', 'Passa-baixa', 'Rejeita'];

class _TypeMenu extends StatelessWidget {
  final int value;
  final Color color;
  final bool dimmed, showName;
  final ValueChanged<int> onChanged;
  const _TypeMenu({required this.value, required this.color, required this.dimmed, required this.showName, required this.onChanged});

  @override
  Widget build(BuildContext context) => PopupMenuButton<int>(
    tooltip: eqBandTypes[value],
    initialValue: value,
    position: PopupMenuPosition.under,
    onSelected: (t) {
      if (t != value) onChanged(t);
    },
    itemBuilder: (_) => [
      for (var t = 0; t < eqBandTypes.length; t++)
        PopupMenuItem(
          value: t,
          height: 36,
          child: Row(
            children: [
              SizedBox(width: 22, child: t == value ? Icon(Icons.check, size: 16, color: color) : null),
              SizedBox(
                width: 22,
                height: 14,
                child: EqTypeGlyph(type: t, color: color),
              ),
              const SizedBox(width: 10),
              Flexible(child: Text(eqBandTypes[t], maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
          ),
        ),
    ],
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            height: 12,
            child: EqTypeGlyph(type: value, color: dimmed ? Colors.white38 : color),
          ),
          if (showName) ...[
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _shortTypes[value],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: dimmed ? Colors.white38 : Colors.white70),
              ),
            ),
          ],
          Icon(Icons.arrow_drop_down, size: 14, color: dimmed ? Colors.white24 : Colors.white38),
        ],
      ),
    ),
  );
}

class _SlopeMenu extends StatelessWidget {
  final int value;
  final Color color;
  final bool dimmed;
  final ValueChanged<int> onChanged;
  const _SlopeMenu({required this.value, required this.color, required this.dimmed, required this.onChanged});

  static const _labels = ['12 dB/oit', '24 dB/oit', '48 dB/oit'];

  @override
  Widget build(BuildContext context) => PopupMenuButton<int>(
    tooltip: 'Inclinação',
    initialValue: value,
    position: PopupMenuPosition.under,
    onSelected: (s) {
      if (s != value) onChanged(s);
    },
    itemBuilder: (_) => [
      for (var s = 0; s < 3; s++)
        PopupMenuItem(
          value: s,
          height: 34,
          child: Row(
            children: [
              SizedBox(width: 22, child: s == value ? Icon(Icons.check, size: 16, color: color) : null),
              Text(_labels[s]),
            ],
          ),
        ),
    ],
    child: Padding(
      padding: const EdgeInsets.only(right: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '${const ['12', '24', '48'][value]} dB/o',
                style: TextStyle(fontSize: 11, color: dimmed ? Colors.white30 : Colors.white70, fontFeatures: const [FontFeature.tabularFigures()]),
              ),
            ),
          ),
          Icon(Icons.arrow_drop_down, size: 14, color: dimmed ? Colors.white24 : Colors.white38),
        ],
      ),
    ),
  );
}

/// Desenho do tipo de banda (passa-alta, prateleiras, sino, passa-baixa, rejeita-faixa).
class EqTypeGlyph extends StatelessWidget {
  final int type;
  final Color color;
  const EqTypeGlyph({super.key, required this.type, required this.color});

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _TypeGlyphPainter(type, color));
}

class _TypeGlyphPainter extends CustomPainter {
  final int type;
  final Color color;
  _TypeGlyphPainter(this.type, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final hi = h * 0.2, mid = h * 0.55, lo = h * 0.95;
    final p = Path();
    switch (type) {
      case 0:
        p
          ..moveTo(w * 0.05, lo)
          ..quadraticBezierTo(w * 0.3, hi, w * 0.5, hi)
          ..lineTo(w, hi);
      case 4:
        p
          ..moveTo(0, hi)
          ..lineTo(w * 0.5, hi)
          ..quadraticBezierTo(w * 0.7, hi, w * 0.95, lo);
      case 1:
        p
          ..moveTo(0, hi)
          ..lineTo(w * 0.3, hi)
          ..cubicTo(w * 0.5, hi, w * 0.5, mid + h * 0.15, w * 0.7, mid + h * 0.15)
          ..lineTo(w, mid + h * 0.15);
      case 3:
        p
          ..moveTo(0, mid + h * 0.15)
          ..lineTo(w * 0.3, mid + h * 0.15)
          ..cubicTo(w * 0.5, mid + h * 0.15, w * 0.5, hi, w * 0.7, hi)
          ..lineTo(w, hi);
      case 5:
        p
          ..moveTo(0, hi + h * 0.1)
          ..lineTo(w * 0.38, hi + h * 0.1)
          ..quadraticBezierTo(w * 0.5, lo * 1.3, w * 0.62, hi + h * 0.1)
          ..lineTo(w, hi + h * 0.1);
      default:
        p
          ..moveTo(0, mid + h * 0.1)
          ..lineTo(w * 0.2, mid + h * 0.1)
          ..cubicTo(w * 0.4, mid + h * 0.1, w * 0.4, 0, w * 0.5, 0)
          ..cubicTo(w * 0.6, 0, w * 0.6, mid + h * 0.1, w * 0.8, mid + h * 0.1)
          ..lineTo(w, mid + h * 0.1);
    }
    canvas.drawPath(
      p,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_TypeGlyphPainter o) => o.type != type || o.color != color;
}

// ------------------------------------------------------------------------ dinâmica: o editor

/// Compressor, gate e limitador: curva de transferência (arrastar muda o limiar; no limitador, o
/// ganho de entrada), o medidor de redução ao vivo e os knobs.
class _DynamicsEditor extends StatefulWidget {
  final _Fx x;
  final int track;
  final EffectSlot slot;
  final bool desktop;
  final double height;
  const _DynamicsEditor({required this.x, required this.track, required this.slot, required this.desktop, required this.height});

  static const _meterW = 36.0;

  static double _graphSide(double height) => height.clamp(70.0, 220.0);

  static double widthFor(_Fx x, double height) {
    final (knob, rows) = _knobFit(height);
    return _graphSide(height) + 8 + _meterW + 14 + _groupsWidth(x.groups(knob), rows);
  }

  @override
  State<_DynamicsEditor> createState() => _DynamicsEditorState();
}

class _DynamicsEditorState extends State<_DynamicsEditor> implements _MeterHost {
  @override
  int get meterTrack => widget.track;
  @override
  String get meterSlot => widget.slot.id;

  late final _watch = _Watch.of(widget.x.c);

  bool _changed = false;
  double _dragValue = 0;

  _Fx get x => widget.x;
  EffectKind get _kind => widget.slot.kind;

  @override
  void initState() {
    super.initState();
    _watch.addDynamics(this);
  }

  @override
  void dispose() {
    _watch.removeDynamics(this);
    super.dispose();
  }

  /// Entradas e saídas do gráfico (dB).
  (double, double) get _range => switch (_kind) {
    EffectKind.gate => (-80.0, 0.0),
    EffectKind.limiter => (-36.0, 0.0),
    _ => (-60.0, 0.0),
  };

  /// O que o arraste horizontal no gráfico mexe: o limiar (compressor e gate) ou o ganho de
  /// entrada (limitador); os três são o id 0 da tabela.
  static const _dragId = 0;

  void _dragStart(DragStartDetails _) {
    _changed = false;
    _dragValue = x.v(_dragId);
  }

  void _dragUpdate(DragUpdateDetails d, double width) {
    final (lo, hi) = _range;
    final fine = HardwareKeyboard.instance.isShiftPressed ? 0.2 : 1.0;
    final delta = d.delta.dx / math.max(1, width) * (hi - lo) * fine;
    // no limitador o joelho fica em teto − ganho: arrastar para a esquerda empurra mais ganho
    _dragValue += _kind == EffectKind.limiter ? -delta : delta;
    final spec = x.spec(_dragId);
    final v = spec.clamp(_dragValue);
    if ((x.v(_dragId) - v).abs() < 1e-9) return;
    if (!_changed) {
      _changed = true;
      x.begin();
    }
    x.set(_dragId, v);
  }

  @override
  Widget build(BuildContext context) {
    final values = Float64List.fromList([for (final p in _kind.params) x.v(p.id)]);
    final font = DefaultTextStyle.of(context).style.fontFamily;
    return ValueListenableBuilder<_MeterHost?>(
      valueListenable: _watch.active,
      builder: (context, active, _) {
        final live = active == this;
        Widget graph(double width) => MouseRegion(
          key: const ValueKey('fx-transfer'),
          cursor: SystemMouseCursors.resizeLeftRight,
          child: GestureDetector(
            onHorizontalDragStart: _dragStart,
            onHorizontalDragUpdate: (d) => _dragUpdate(d, width),
            onHorizontalDragEnd: (_) => _changed = false,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Container(
                color: Palette.ink,
                foregroundDecoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Palette.hairline),
                ),
                child: live
                    ? ValueListenableBuilder<double>(valueListenable: x.c.fxMeter, builder: (context, gr, _) => _transfer(values, gr, font))
                    : _transfer(values, 0, font),
              ),
            ),
          ),
        );
        final meterLive = live && !widget.slot.bypass;
        final meter = SizedBox(
          width: _DynamicsEditor._meterW,
          child: Tooltip(
            message: live
                ? (widget.slot.bypass ? 'Efeito desligado: nada a medir' : 'Redução de ganho agora (o traço segura o pico)')
                : 'O medidor mostra um efeito de dinâmica por vez: toque neste para medir',
            waitDuration: const Duration(milliseconds: 600),
            child: _GrMeter(source: meterLive ? x.c.fxMeter : null, max: _kind == EffectKind.gate ? 60 : 24, color: x.color, fontFamily: font),
          ),
        );
        final body = widget.desktop ? _desktop(graph, meter) : _mobile(graph, meter);
        // tocar num efeito de dinâmica faz dele o medido (o motor mede um por vez)
        return Listener(onPointerDown: (_) => _watch.activate(this), child: body);
      },
    );
  }

  Widget _transfer(Float64List values, double gr, String? font) => CustomPaint(
    painter: _TransferPainter(
      kind: _kind,
      values: values,
      gr: gr.isFinite ? math.max(0, gr) : 0,
      color: x.color,
      bypassed: widget.slot.bypass,
      fontFamily: font,
    ),
  );

  Widget _desktop(Widget Function(double) graph, Widget meter) {
    final (knob, rows) = _knobFit(widget.height);
    final side = _DynamicsEditor._graphSide(widget.height);
    return SizedBox(
      height: widget.height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: side, height: side, child: graph(side)),
          const SizedBox(width: 8),
          SizedBox(height: side, child: meter),
          const SizedBox(width: 14),
          _GroupsRow(groups: x.groups(knob), rows: rows, knob: knob),
        ],
      ),
    );
  }

  Widget _mobile(Widget Function(double) graph, Widget meter) => LayoutBuilder(
    builder: (context, box) {
      final gw = math.max(60.0, box.maxWidth - _DynamicsEditor._meterW - 8);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 150,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: graph(gw)),
                const SizedBox(width: 8),
                meter,
              ],
            ),
          ),
          const SizedBox(height: 10),
          _GroupsColumn(groups: x.groups(44)),
        ],
      );
    },
  );
}

class _TransferPainter extends CustomPainter {
  final EffectKind kind;

  /// Os parâmetros na ordem da tabela do tipo (cópia, como no EQ).
  final Float64List values;

  /// Redução de ganho agora (dB ≥ 0), para o ponto de operação.
  final double gr;
  final Color color;
  final bool bypassed;
  final String? fontFamily;

  _TransferPainter({required this.kind, required this.values, required this.gr, required this.color, required this.bypassed, this.fontFamily});

  double _v(int id) {
    final params = kind.params;
    for (var i = 0; i < params.length; i++) {
      if (params[i].id == id) return values[i];
    }
    return 0;
  }

  (double, double) get _range => switch (kind) {
    EffectKind.gate => (-80.0, 0.0),
    EffectKind.limiter => (-36.0, 0.0),
    _ => (-60.0, 0.0),
  };

  /// Saída estática para a entrada [x] (dB), com o ganho de saída do compressor (manual + automático).
  double _out(double x) => switch (kind) {
    EffectKind.gate => x >= _v(0) ? x : x + _v(4),
    EffectKind.limiter => math.min(x + _v(0), _v(1)),
    _ => compressorCurve(x, _v(0), _v(1), _v(4)) + compressorMakeupDb(_v(0), _v(1), _v(5), _v(9) >= 0.5),
  };

  /// Entrada que dá a redução [gr] na curva (compressor e limitador); null se não há.
  double? _operating(double gr) {
    if (gr < 0.05) return null;
    if (kind == EffectKind.limiter) return _v(1) - _v(0) + gr;
    if (kind != EffectKind.compressor) return null;
    final t = _v(0), r = _v(1), k = _v(4);
    double red(double x) => x - compressorCurve(x, t, r, k);
    var lo = t - k / 2, hi = 24.0;
    if (red(hi) < gr) return hi;
    for (var i = 0; i < 40; i++) {
      final mid = (lo + hi) / 2;
      if (red(mid) < gr) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return (lo + hi) / 2;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final (lo, hi) = _range;
    final w = size.width, h = size.height;
    if (w < 8 || h < 8) return;
    double xOf(double db) => (db - lo) / (hi - lo) * w;
    double yOf(double db) => h - (db - lo) / (hi - lo) * h;
    final grid = Paint()..color = Colors.white.withValues(alpha: 0.05);
    final step = kind == EffectKind.limiter ? 6.0 : 12.0;
    for (var d = lo + step; d < hi; d += step) {
      canvas.drawLine(Offset(xOf(d), 0), Offset(xOf(d), h), grid);
      canvas.drawLine(Offset(0, yOf(d)), Offset(w, yOf(d)), grid);
    }
    // 1:1 tracejado
    final diag = Paint()
      ..color = Colors.white.withValues(alpha: 0.14)
      ..strokeWidth = 1;
    for (var t = 0.0; t < 1; t += 0.04) {
      canvas.drawLine(Offset(t * w, h - t * h), Offset((t + 0.02) * w, h - (t + 0.02) * h), diag);
    }

    final tint = bypassed ? Colors.white38 : color;
    final knee = switch (kind) {
      EffectKind.compressor => _v(0),
      EffectKind.gate => _v(0),
      _ => _v(1) - _v(0),
    };
    if (kind == EffectKind.compressor && _v(4) > 0) {
      final k = _v(4);
      canvas.drawRect(Rect.fromLTRB(xOf(math.max(lo, knee - k / 2)), 0, xOf(math.min(hi, knee + k / 2)), h), Paint()..color = tint.withValues(alpha: 0.05));
    }
    final kx = xOf(knee.clamp(lo, hi));
    final dash = Paint()
      ..color = tint.withValues(alpha: 0.45)
      ..strokeWidth = 1;
    for (var y = 0.0; y < h; y += 6) {
      canvas.drawLine(Offset(kx, y), Offset(kx, y + 3), dash);
    }

    final path = Path();
    final n = math.max(8, (w / 1.5).ceil());
    for (var i = 0; i <= n; i++) {
      final xin = lo + (hi - lo) * i / n;
      final py = yOf(_out(xin)).clamp(-2.0, h + 2);
      i == 0 ? path.moveTo(xOf(xin), py) : path.lineTo(xOf(xin), py);
    }
    canvas.drawPath(
      Path.from(path)
        ..lineTo(w, h)
        ..lineTo(0, h)
        ..close(),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [tint.withValues(alpha: 0.22), tint.withValues(alpha: 0.02)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeJoin = StrokeJoin.round
        ..color = tint,
    );
    // alça do limiar em cima da curva
    final ky = yOf(_out(knee.clamp(lo, hi))).clamp(4.0, h - 4);
    canvas.drawCircle(Offset(kx, ky), 4, Paint()..color = Colors.white);

    final xin = _operating(gr);
    if (xin != null && !bypassed) {
      final p = Offset(xOf(xin.clamp(lo, hi)), yOf(_out(xin)).clamp(3.0, h - 3));
      canvas.drawCircle(p, 7, Paint()..color = color.withValues(alpha: 0.25));
      canvas.drawCircle(p, 3.5, Paint()..color = color);
    }

    final label = switch (kind) {
      EffectKind.limiter => 'teto ${_fmtDb(_v(1))}',
      EffectKind.gate => 'limiar ${_fmtDb(_v(0))}',
      _ => '${_fmtDb(_v(0))} · ${_v(1).toStringAsFixed(_v(1) < 10 ? 1 : 0)}:1${_v(9) >= 0.5 ? ' · auto' : ''}',
    };
    final tp = _axisLabel(label, fontFamily, color: Colors.white54);
    tp.paint(canvas, Offset(4, 3));
  }

  static String _fmtDb(double v) => '${v < -0.05 ? '−' : ''}${v.abs().toStringAsFixed(1)} dB';

  @override
  bool shouldRepaint(_TransferPainter o) {
    if (o.kind != kind || o.gr != gr || o.color != color || o.bypassed != bypassed || o.fontFamily != fontFamily || o.values.length != values.length) {
      return true;
    }
    for (var i = 0; i < values.length; i++) {
      if (o.values[i] != values[i]) return true;
    }
    return false;
  }
}

/// O medidor ao vivo: acompanha [source] e segura o pico 1,2 s antes de deixá-lo cair a 12 dB/s.
/// A queda anda num ticker próprio: o indicador do motor só notifica quando o valor muda, e
/// parado em 0 o traço ficaria preso no último pico.
class _GrMeter extends StatefulWidget {
  final ValueListenable<double>? source;
  final double max;
  final Color color;
  final String? fontFamily;
  const _GrMeter({required this.source, required this.max, required this.color, this.fontFamily});

  @override
  State<_GrMeter> createState() => _GrMeterState();
}

class _GrMeterState extends State<_GrMeter> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  double _value = 0, _hold = 0, _held = 0;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    widget.source?.addListener(_onValue);
    _onValue();
  }

  @override
  void didUpdateWidget(_GrMeter old) {
    super.didUpdateWidget(old);
    if (old.source != widget.source) {
      old.source?.removeListener(_onValue);
      widget.source?.addListener(_onValue);
      _value = _hold = 0;
      _onValue();
    }
  }

  @override
  void dispose() {
    widget.source?.removeListener(_onValue);
    _ticker.dispose();
    super.dispose();
  }

  void _onValue() {
    final v = widget.source?.value ?? 0;
    _value = v.isFinite ? math.max(0.0, v) : 0.0;
    if (_value >= _hold) {
      _hold = _value;
      _held = 0;
    }
    if (_hold > _value && !_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
    if (mounted) setState(() {});
  }

  void _tick(Duration elapsed) {
    final dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    _held += dt;
    if (_held > 1.2) _hold = math.max(_value, _hold - 12 * dt);
    if (_hold <= _value) _ticker.stop();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _GrMeterPainter(gr: _value, hold: _hold, live: widget.source != null, max: widget.max, color: widget.color, fontFamily: widget.fontFamily),
  );
}

/// Medidor vertical de redução de ganho: cresce de cima para baixo, em escala de raiz (os primeiros
/// dB, onde a compressão boa mora, ganham mais espaço), com o pico segurado e o número embaixo.
class _GrMeterPainter extends CustomPainter {
  final double gr, hold, max;
  final bool live;
  final Color color;
  final String? fontFamily;

  _GrMeterPainter({required this.gr, required this.hold, required this.live, required this.max, required this.color, this.fontFamily});

  @override
  void paint(Canvas canvas, Size size) {
    const textH = 14.0;
    final barX = size.width - 11, barW = 8.0;
    final top = 2.0, bottom = size.height - textH - 2;
    final h = bottom - top;
    if (h < 10) return;
    double yOf(double db) => top + math.sqrt((db / max).clamp(0.0, 1.0)) * h;
    final track = RRect.fromRectAndRadius(Rect.fromLTWH(barX, top, barW, h), const Radius.circular(3));
    canvas.drawRRect(track, Paint()..color = Colors.white.withValues(alpha: 0.06));
    var lastLabel = -100.0;
    for (final t in max > 30 ? const [3.0, 12.0, 30.0, 60.0] : const [1.0, 3.0, 6.0, 12.0, 24.0]) {
      final y = yOf(t);
      canvas.drawLine(Offset(barX - 3, y), Offset(barX, y), Paint()..color = Colors.white24);
      final tp = _axisLabel(t.toStringAsFixed(0), fontFamily);
      // medidor baixo: os números que se encostariam ficam só no traço
      if (y + tp.height / 2 < bottom && y - lastLabel >= tp.height) {
        tp.paint(canvas, Offset(barX - 5 - tp.width, y - tp.height / 2));
        lastLabel = y;
      }
    }
    if (live && gr > 0.01) {
      final y = yOf(gr);
      canvas.save();
      canvas.clipRRect(track);
      canvas.drawRect(
        Rect.fromLTRB(barX, top, barX + barW, y),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color, Color.lerp(color, Palette.danger, 0.6)!],
          ).createShader(Rect.fromLTWH(barX, top, barW, h)),
      );
      canvas.restore();
    }
    if (live && hold > 0.05) {
      final y = yOf(hold);
      canvas.drawLine(
        Offset(barX - 1, y),
        Offset(barX + barW + 1, y),
        Paint()
          ..color = Colors.white70
          ..strokeWidth = 1.5,
      );
    }
    final text = !live ? '—' : (hold < 0.05 ? '0.0' : '−${hold.toStringAsFixed(1)}');
    final tp = _axisLabel(text, fontFamily, color: live ? Colors.white70 : Colors.white30);
    tp.paint(canvas, Offset(size.width - tp.width - 1, size.height - tp.height));
  }

  @override
  bool shouldRepaint(_GrMeterPainter o) => o.gr != gr || o.hold != hold || o.live != live || o.max != max || o.color != color || o.fontFamily != fontFamily;
}
