/// O mixer: um canal por faixa e o master fixo à direita. Em cada canal, de cima para baixo: os
/// inserts (efeitos na ordem do sinal), os envios para barramentos, pan, fader com medidor,
/// mudo/solo, a saída e o nome com o ícone do tipo. Ocupa a altura que o painel de baixo der;
/// abaixo do mínimo rola na vertical em vez de espremer.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/theme.dart';
import 'controller.dart';
import 'effects.dart';
import 'instruments.dart';
import 'meter.dart';
import 'model.dart';
import 'timeline.dart' show ToggleChip;

/// Altura de uma linha das listas de inserts e de envios.
const _row = 18.0;
const _stripWidth = 92.0;

/// Folga entre as duas listas.
const _listGap = 3.0;

/// O que o canal tem de altura fixa abaixo das listas: folga, pan, dB, M/S, saída e nome, com as
/// folgas entre eles (tem que bater com [_Strip.build]).
const _fixed = 5 + 20 + 3 + 14 + 3 + 20 + 3 + 20 + 3 + 16.0;

/// A moldura do canal: o respiro da lista (6 + 6), o do canal (5 + 5) e a borda de cor (3).
const _frame = 12 + 10 + 3.0;

/// Abaixo disto o fader deixa de ser usável.
const _minFader = 72.0;

/// Fundo dos barramentos: um violeta discreto, para retorno e grupo não se confundirem com fonte.
const _busTint = Color(0xFF8C7CF0);

const _slotText = TextStyle(fontSize: 10.5, height: 1.2);
const _preColor = Color(0xFFE3B341);

/// Quantas linhas cabem nas listas de inserts e de envios. É do painel, não do canal: todos os
/// canais usam as mesmas medidas, e pan, faders e botões ficam alinhados de ponta a ponta.
class _Layout {
  final int inserts, sends;
  const _Layout(this.inserts, this.sends);

  static const smallest = _Layout(2, 1);

  double get insertsHeight => inserts * _row + 2;
  double get sendsHeight => sends * _row + 2;

  /// A caixa do master ocupa o lugar das duas (ele não tem envios).
  double get masterHeight => insertsHeight + _listGap + sendsHeight;

  double _height(double fader) => _frame + _fixed + fader + masterHeight;

  /// Altura mínima do painel: as listas no menor tamanho e o fader no mínimo.
  static double get minHeight => smallest._height(_minFader);

  static _Layout of(DawController c, double height) {
    var effects = 0, targets = 0;
    for (var i = 0; i < c.doc.tracks.length; i++) {
      effects = math.max(effects, c.effectsOf(i).length);
      targets = math.max(targets, c.busTargets(i).length);
    }
    // o fader fica com uns 35% do canal, mesmo que as listas quisessem mais
    final fader = math.max(_minFader, (height - _frame) * 0.35);
    var spare = ((height - smallest._height(fader)) / _row).floor();
    int grow(int have, int want) {
      final n = math.max(0, math.min(want - have, spare));
      spare -= n;
      return have + n;
    }

    // ao menos três linhas de inserts, para a lista não pular a cada efeito novo; depois os envios
    // (poucos); depois os inserts longos: uma linha além dos efeitos para o "+ Efeito". O master
    // usa também o lugar dos envios, então os efeitos dele pedem menos linhas.
    var ins = grow(smallest.inserts, 3);
    final snd = grow(smallest.sends, math.max(1, targets));
    ins = grow(ins, math.max(effects + 1, c.effectsOf(-1).length + 1 - snd));
    return _Layout(ins, snd);
  }
}

class MixerPanel extends StatelessWidget {
  final DawController c;
  const MixerPanel({super.key, required this.c});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) => LayoutBuilder(
      builder: (context, box) {
        final available = box.hasBoundedHeight ? box.maxHeight : 360.0;
        final height = math.max(available, _Layout.minHeight);
        final strips = SizedBox(
          height: height,
          child: ColoredBox(color: Palette.bar, child: _strips(_Layout.of(c, height))),
        );
        if (available >= height) return strips;
        return SingleChildScrollView(child: strips);
      },
    ),
  );

  Widget _strips(_Layout layout) => Row(
    children: [
      Expanded(
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          children: [
            for (var i = 0; i < c.doc.tracks.length; i++) _Strip(key: ValueKey(c.doc.tracks[i].id), c: c, index: i, layout: layout),
            _AddStrip(c: c),
          ],
        ),
      ),
      Container(width: 1, color: Palette.hairlineStrong),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: _Strip(c: c, index: -1, layout: layout),
      ),
    ],
  );
}

// ---------------------------------------------------------------------- canal

class _Strip extends StatelessWidget {
  final DawController c;

  /// Faixa; −1 é o master.
  final int index;
  final _Layout layout;
  const _Strip({super.key, required this.c, required this.index, required this.layout});

  bool get _master => index < 0;

  void _setGain(double g) => c.mutate((d) => _master ? d.masterGain = g : d.tracks[index].gain = g);

  @override
  Widget build(BuildContext context) {
    final t = _master ? null : c.doc.tracks[index];
    final bus = t?.kind == TrackKind.bus;
    final color = t == null ? Colors.white : trackColorAt(t.color);
    final selected = t != null && c.selectedTrack == index;
    final gain = t?.gain ?? c.doc.masterGain;
    final small = Theme.of(context).textTheme.labelSmall!.copyWith(fontSize: 10.5, height: 1.2);
    final base = selected ? Palette.overlay : Palette.raised;
    final background = bus ? Color.alphaBlend(_busTint.withValues(alpha: selected ? 0.16 : 0.09), base) : base;
    return GestureDetector(
      onTap: t == null ? null : () => c.selectTrack(index),
      child: Container(
        width: _stripWidth,
        margin: EdgeInsets.only(right: _master ? 0 : 6),
        padding: const EdgeInsets.symmetric(vertical: 5),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(8),
          border: Border(top: BorderSide(color: color, width: 3)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: _Inserts(c: c, track: index, color: color, height: _master ? layout.masterHeight : layout.insertsHeight),
            ),
            if (!_master) ...[
              const SizedBox(height: _listGap),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: _Sends(c: c, track: index, height: layout.sendsHeight),
              ),
            ],
            const SizedBox(height: 5),
            SizedBox(
              height: 20,
              child: _PanKnob(c: c, track: index, color: color),
            ),
            const SizedBox(height: 3),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _Fader(c: c, track: index, color: _master ? Palette.accent : color),
                  const SizedBox(width: 4),
                  Padding(
                    // o medidor acompanha o curso do fader (a tampa sobra meia altura em cima e embaixo)
                    padding: const EdgeInsets.symmetric(vertical: _Fader.capHalf),
                    child: Meter(peaks: c.peaks, index: index, width: 9),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 14,
              child: GestureDetector(
                onDoubleTap: () {
                  if (gain == 1) return;
                  c.checkpoint();
                  _setGain(1);
                },
                child: Tooltip(
                  message: 'Volume (duplo clique: 0 dB)',
                  waitDuration: const Duration(milliseconds: 800),
                  child: c.automated(index, AutoKind.volume)
                      ? ValueListenableBuilder<double>(
                          valueListenable: c.beat,
                          builder: (_, _, _) => Text(
                            '${formatDb(c.liveValue(index, AutoKind.volume))} dB',
                            style: small.copyWith(fontFeatures: const [FontFeature.tabularFigures()], color: c.playing.value ? automationColor : null),
                          ),
                        )
                      : Text('${formatDb(gain)} dB', style: small.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                ),
              ),
            ),
            const SizedBox(height: 3),
            SizedBox(
              height: 20,
              child: t == null
                  ? null
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ToggleChip(label: 'M', on: t.mute, color: Palette.danger, tooltip: 'Mudo', onTap: () => c.edit((d) => d.tracks[index].mute = !t.mute)),
                        const SizedBox(width: 4),
                        ToggleChip(
                          label: 'S',
                          on: t.solo,
                          color: const Color(0xFFE3B341),
                          tooltip: 'Solo',
                          onTap: () => c.edit((d) => d.tracks[index].solo = !t.solo),
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 3),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: SizedBox(
                height: 20,
                child: t == null ? const _DeviceOutput() : _OutputButton(c: c, track: index),
              ),
            ),
            const SizedBox(height: 3),
            SizedBox(
              height: 16,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (t != null) ...[_KindIcon(c: c, track: index, color: color), const SizedBox(width: 4)],
                    Flexible(
                      child: Tooltip(
                        message: t?.name ?? 'Master',
                        waitDuration: const Duration(milliseconds: 800),
                        child: Text(
                          t?.name ?? 'Master',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: small.copyWith(color: Colors.white, fontWeight: t == null ? FontWeight.w700 : null),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Gesto dos controles do canal (fader, pan, envios): arrastar na vertical (Shift: fino) ou a roda
/// em cima dele; um ponto de desfazer por gesto, marcado só quando o valor muda de fato.
mixin _DragValue<T extends StatefulWidget> on State<T> {
  bool active = false;
  bool _changed = false;

  /// Posição 0..1 acumulada no gesto: contínua entre os passos, mesmo onde o valor tem detenção.
  double norm = 0;
  Timer? _wheelIdle;

  DawController get c;

  /// Posição 0..1 do valor atual.
  double get valueNorm;

  /// A posição muda o valor (senão não se marca ponto de desfazer nem se manda nada).
  bool changes(double n);

  /// Aplica a posição, sem ponto de desfazer.
  void apply(double n);

  /// Pixels de arraste para o curso todo (Shift: cinco vezes mais).
  double get travel => 150;

  @override
  void dispose() {
    _wheelIdle?.cancel();
    super.dispose();
  }

  void _begin() {
    if (active) return;
    active = true;
    _changed = false;
    norm = valueNorm;
    setState(() {});
  }

  void _emit(double n) {
    norm = n.clamp(0.0, 1.0);
    if (!changes(norm)) return;
    if (!_changed) {
      _changed = true;
      c.checkpoint();
    }
    apply(norm);
  }

  void end() {
    _wheelIdle?.cancel();
    _wheelIdle = null;
    if (!active) return;
    active = false;
    _changed = false;
    if (mounted) setState(() {});
  }

  void dragStart(DragStartDetails _) {
    end();
    _begin();
  }

  void dragUpdate(DragUpdateDetails d) {
    final t = HardwareKeyboard.instance.isShiftPressed ? travel * 5 : travel;
    _emit(norm - d.delta.dy / t);
  }

  void onSignal(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    // a roda em cima do controle é dele, não da lista em volta
    GestureBinding.instance.pointerSignalResolver.register(e, (ev) {
      final delta = (ev as PointerScrollEvent).scrollDelta;
      final dy = delta.dy != 0 ? delta.dy : delta.dx;
      if (dy == 0) return;
      _begin();
      final travel = HardwareKeyboard.instance.isShiftPressed ? 6000.0 : 1200.0;
      _emit(norm - dy / travel);
      _wheelIdle?.cancel();
      _wheelIdle = Timer(const Duration(milliseconds: 500), end);
    });
  }
}

/// O fader de volume: arrastar move a partir de onde está (clicar no trilho não pula o volume, como
/// numa mesa), 1:1 com o ponteiro; Shift é ajuste fino, a roda também mexe e o duplo clique volta a
/// 0 dB. A escala em dB fica ao lado do trilho, na curva do fader ([gainToFader]).
class _Fader extends StatefulWidget {
  final DawController c;
  final int track;
  final Color color;
  const _Fader({required this.c, required this.track, required this.color});

  /// Meia altura da tampa: o trilho começa e termina a esta distância das bordas.
  static const capHalf = 6.0;

  @override
  State<_Fader> createState() => _FaderState();
}

class _FaderState extends State<_Fader> with _DragValue {
  double _track = 100;

  @override
  DawController get c => widget.c;

  double get _gain => widget.track < 0 ? c.doc.masterGain : c.doc.tracks[widget.track].gain;

  void _set(double g) => c.mutate((d) => widget.track < 0 ? d.masterGain = g : d.tracks[widget.track].gain = g);

  @override
  double get travel => _track;

  @override
  double get valueNorm => gainToFader(_gain).clamp(0.0, 1.0);

  @override
  bool changes(double n) => faderToGain(n) != _gain;

  @override
  void apply(double n) => _set(faderToGain(n));

  void _unity() {
    if (_gain == 1) return;
    c.checkpoint();
    _set(1);
  }

  /// Um passo para teclado/leitor de tela: 2% do curso.
  double _stepped(int dir) => faderToGain((valueNorm + dir * 0.02).clamp(0.0, 1.0));

  void _step(int dir) {
    c.checkpoint();
    _set(_stepped(dir));
  }

  @override
  Widget build(BuildContext context) {
    final gain = _gain;
    return Semantics(
      slider: true,
      label: 'Volume',
      value: '${formatDb(gain)} dB',
      increasedValue: '${formatDb(_stepped(1))} dB',
      decreasedValue: '${formatDb(_stepped(-1))} dB',
      onIncrease: () => _step(1),
      onDecrease: () => _step(-1),
      child: Tooltip(
        message: 'Volume: ${formatDb(gain)} dB\nArraste (Shift: fino) ou use a roda · duplo clique: 0 dB',
        waitDuration: const Duration(milliseconds: 900),
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeUpDown,
          child: Listener(
            onPointerSignal: onSignal,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onDoubleTap: _unity,
              onVerticalDragStart: dragStart,
              onVerticalDragUpdate: dragUpdate,
              onVerticalDragEnd: (_) => end(),
              onVerticalDragCancel: end,
              child: LayoutBuilder(
                builder: (context, box) {
                  _track = math.max(1, box.maxHeight - 2 * _Fader.capHalf);
                  // com automação e tocando, a tampa segue a curva (arrastar mexe no valor fixo, que
                  // volta a valer quando para)
                  if (!active && c.automated(widget.track, AutoKind.volume)) {
                    return ValueListenableBuilder<double>(
                      valueListenable: c.beat,
                      builder: (_, _, _) => SizedBox(
                        width: 40,
                        height: box.maxHeight,
                        child: CustomPaint(
                          painter: _FaderPainter(
                            norm: gainToFader(c.liveValue(widget.track, AutoKind.volume)).clamp(0.0, 1.0),
                            color: c.playing.value ? automationColor : widget.color,
                            active: false,
                          ),
                        ),
                      ),
                    );
                  }
                  return SizedBox(
                    width: 40,
                    height: box.maxHeight,
                    child: CustomPaint(
                      painter: _FaderPainter(norm: active ? norm : valueNorm, color: widget.color, active: active),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Trilho com a parte de baixo acesa até a tampa, escala em dB à esquerda e a tampa com um risco.
class _FaderPainter extends CustomPainter {
  final double norm;
  final Color color;
  final bool active;
  _FaderPainter({required this.norm, required this.color, required this.active});

  static const _marks = [6.0, 0.0, -6.0, -12.0, -24.0, -48.0];
  static const _trackX = 27.0;
  static final _labels = <double, TextPainter>{};

  static TextPainter _label(double db) => _labels[db] ??= TextPainter(
    text: TextSpan(
      text: db > 0 ? '+${db.round()}' : '${db.abs().round()}',
      style: const TextStyle(fontSize: 8, height: 1, color: Colors.white38, fontFeatures: [FontFeature.tabularFigures()]),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  @override
  void paint(Canvas canvas, Size size) {
    const top = _Fader.capHalf;
    final h = size.height - 2 * top;
    double y(double n) => top + (1 - n) * h;
    // escala: as marcas de dB, sem amontoar rótulos quando o fader é baixo
    final tick = Paint()
      ..color = Colors.white24
      ..strokeWidth = 1;
    var lastLabel = double.negativeInfinity;
    for (final db in _marks) {
      final my = y(gainToFader(dbToGain(db)).clamp(0.0, 1.0));
      canvas.drawLine(Offset(_trackX - 7, my), Offset(_trackX - 4, my), tick);
      if (my - lastLabel >= 10) {
        final tp = _label(db);
        tp.paint(canvas, Offset(_trackX - 9 - tp.width, my - tp.height / 2));
        lastLabel = my;
      }
    }
    final rail = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(_trackX, top), Offset(_trackX, top + h), rail);
    final capY = y(norm);
    canvas.drawLine(Offset(_trackX, capY), Offset(_trackX, top + h), rail..color = color.withValues(alpha: active ? 0.9 : 0.7));
    // a tampa: um bloco com o risco no meio, como numa mesa
    final cap = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(_trackX, capY), width: 22, height: 2 * _Fader.capHalf), const Radius.circular(3));
    canvas.drawRRect(cap, Paint()..color = active ? Colors.white : const Color(0xFFD5DAE1));
    canvas.drawLine(
      Offset(_trackX - 8, capY),
      Offset(_trackX + 8, capY),
      Paint()
        ..color = Colors.black54
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_FaderPainter o) => o.norm != norm || o.color != color || o.active != active;
}

/// Pan do canal: knob bipolar com o valor ao lado (C, E30, D100).
class _PanKnob extends StatefulWidget {
  final DawController c;
  final int track;
  final Color color;
  const _PanKnob({required this.c, required this.track, required this.color});

  @override
  State<_PanKnob> createState() => _PanKnobState();
}

class _PanKnobState extends State<_PanKnob> with _DragValue {
  @override
  DawController get c => widget.c;

  double get _pan => widget.track < 0 ? c.doc.masterPan : c.doc.tracks[widget.track].pan;

  void _set(double p) => c.mutate((d) => widget.track < 0 ? d.masterPan = p : d.tracks[widget.track].pan = p);

  @override
  double get valueNorm => (_pan + 1) / 2;

  /// Detenção no centro: passar por ele no arraste para ali um instante.
  static double _snap(double n) {
    final p = n * 2 - 1;
    return p.abs() < 0.03 ? 0 : p;
  }

  @override
  bool changes(double n) => _snap(n) != _pan;

  @override
  void apply(double n) => _set(_snap(n));

  void _center() {
    if (_pan == 0) return;
    c.checkpoint();
    _set(0);
  }

  static String _label(double p) {
    if (p.abs() < 0.005) return 'C';
    final v = (p.abs() * 100).round();
    return p < 0 ? 'E$v' : 'D$v';
  }

  @override
  Widget build(BuildContext context) {
    final pan = _pan;
    return Tooltip(
      message: 'Pan: ${_label(pan)}\nArraste na vertical ou use a roda · duplo clique: centro',
      waitDuration: const Duration(milliseconds: 800),
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeUpDown,
        child: Listener(
          onPointerSignal: onSignal,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onDoubleTap: _center,
            onVerticalDragStart: dragStart,
            onVerticalDragUpdate: dragUpdate,
            onVerticalDragEnd: (_) => end(),
            onVerticalDragCancel: end,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox.square(
                  dimension: 18,
                  child: !active && c.automated(widget.track, AutoKind.pan)
                      ? ValueListenableBuilder<double>(
                          valueListenable: c.beat,
                          builder: (_, _, _) => CustomPaint(
                            painter: _MiniKnobPainter(
                              norm: (c.liveValue(widget.track, AutoKind.pan) + 1) / 2,
                              origin: 0.5,
                              color: c.playing.value ? automationColor : widget.color,
                              active: false,
                            ),
                          ),
                        )
                      : CustomPaint(
                          painter: _MiniKnobPainter(norm: active ? norm : valueNorm, origin: 0.5, color: widget.color, active: active),
                        ),
                ),
                const SizedBox(width: 5),
                SizedBox(
                  width: 30,
                  child: Text(
                    _label(pan),
                    style: _slotText.copyWith(fontSize: 10, color: active ? widget.color : Colors.white70, fontFeatures: const [FontFeature.tabularFigures()]),
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

/// Ícone do tipo ao lado do nome. Nas faixas de instrumento abre o instrumento; nos barramentos,
/// os efeitos (é neles que um barramento trabalha).
class _KindIcon extends StatelessWidget {
  final DawController c;
  final int track;
  final Color color;
  const _KindIcon({required this.c, required this.track, required this.color});

  @override
  Widget build(BuildContext context) {
    final kind = c.doc.tracks[track].kind;
    VoidCallback? open;
    var tip = kind.label;
    if (kind.isInstrument) {
      tip = '${kind.label}: abrir o instrumento';
      open = () {
        c.selectTrack(track);
        c.setDock(Dock.instrument);
      };
    } else if (kind == TrackKind.bus) {
      tip = '${kind.label}: abrir os efeitos';
      open = () {
        c.selectTrack(track);
        c.showEffects(track);
      };
    }
    return Tooltip(
      message: tip,
      child: InkWell(
        onTap: open,
        borderRadius: BorderRadius.circular(4),
        child: Icon(kind.icon, size: 13, color: color),
      ),
    );
  }
}

/// Coluna fantasma no fim dos canais: cria uma faixa de qualquer tipo sem sair do mixer.
class _AddStrip extends StatelessWidget {
  final DawController c;
  const _AddStrip({required this.c});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return PopupMenuButton<TrackKind>(
      tooltip: 'Nova faixa ou barramento',
      onSelected: (k) => switch (k) {
        TrackKind.audio => c.addTrack(),
        TrackKind.bus => c.addBusTrack(),
        _ => c.addInstrumentTrack(k),
      },
      itemBuilder: (_) => [
        for (final k in TrackKind.values)
          PopupMenuItem(
            value: k,
            child: Row(children: [Icon(k.icon, size: 18), const SizedBox(width: 12), Text(k.label)]),
          ),
      ],
      child: Container(
        width: 52,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Palette.hairlineStrong),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add, size: 20, color: accent),
            const SizedBox(height: 4),
            Text('Faixa', style: _slotText.copyWith(color: accent)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------- inserts

/// Lista de linhas de [_row] numa caixa pequena. Quando passa do que cabe, um trilho fino fica
/// sempre à vista: sem ele não haveria sinal de que há mais efeitos ou envios rolando.
class _SlotList extends StatefulWidget {
  final List<Widget> children;
  const _SlotList({required this.children});

  @override
  State<_SlotList> createState() => _SlotListState();
}

class _SlotListState extends State<_SlotList> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScrollConfiguration(
    // a barra padrão do computador cobriria o texto das linhas; esta é fina e fica na borda
    behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
    child: RawScrollbar(
      controller: _scroll,
      thumbVisibility: true,
      thickness: 2,
      radius: const Radius.circular(1),
      crossAxisMargin: 1,
      mainAxisMargin: 2,
      thumbColor: Colors.white38,
      child: ListView(controller: _scroll, padding: EdgeInsets.zero, itemExtent: _row, children: widget.children),
    ),
  );
}

const _box = BoxDecoration(
  color: Palette.ink,
  borderRadius: BorderRadius.all(Radius.circular(4)),
  border: Border.fromBorderSide(BorderSide(color: Palette.hairline)),
);

class _Inserts extends StatelessWidget {
  final DawController c;
  final int track;
  final Color color;
  final double height;
  const _Inserts({required this.c, required this.track, required this.color, required this.height});

  @override
  Widget build(BuildContext context) {
    final slots = c.effectsOf(track);
    return Container(
      height: height,
      decoration: _box,
      child: Column(
        children: [
          Expanded(
            child: _SlotList(
              children: [
                for (var j = 0; j < slots.length; j++)
                  _InsertRow(key: ValueKey(slots[j].id), c: c, track: track, slot: slots[j], position: j, count: slots.length, color: color),
              ],
            ),
          ),
          _AddEffectRow(c: c, track: track, empty: slots.isEmpty),
        ],
      ),
    );
  }
}

class _InsertRow extends StatelessWidget {
  final DawController c;
  final int track;
  final EffectSlot slot;
  final int position, count;
  final Color color;
  const _InsertRow({super.key, required this.c, required this.track, required this.slot, required this.position, required this.count, required this.color});

  void _open() {
    if (track >= 0) c.selectTrack(track);
    c.showEffects(track);
  }

  Future<void> _menu(BuildContext context, Offset? at) async {
    final id = slot.id;
    final v = await _showMenu<String>(context, at, [
      _item('open', 'Abrir nos efeitos', icon: Icons.open_in_new),
      _item('bypass', slot.bypass ? 'Ligar' : 'Desligar (bypass)', icon: Icons.power_settings_new),
      if (position > 0) _item('up', 'Mover para cima', icon: Icons.arrow_upward),
      if (position < count - 1) _item('down', 'Mover para baixo', icon: Icons.arrow_downward),
      const PopupMenuDivider(),
      _item('remove', 'Remover', icon: Icons.delete_outline),
    ]);
    switch (v) {
      case 'open':
        _open();
      case 'bypass':
        c.setEffectBypass(track, id, !slot.bypass);
      case 'up':
        c.moveEffect(track, id, position - 1);
      case 'down':
        c.moveEffect(track, id, position + 1);
      case 'remove':
        c.removeEffect(track, id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final off = slot.bypass;
    return Tooltip(
      message: '${slot.kind.label}${off ? ' (desligado)' : ''}: toque para abrir\nBotão direito ou toque longo: ligar, mover, remover',
      waitDuration: const Duration(milliseconds: 800),
      child: _TouchLongPress(
        onLongPress: () => _menu(context, null),
        child: InkWell(
          onTap: _open,
          onSecondaryTapUp: (d) => _menu(context, d.globalPosition),
          child: Row(
            children: [
              // a luz liga e desliga o efeito sem abrir o painel
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => c.setEffectBypass(track, slot.id, !off),
                child: SizedBox(
                  width: 16,
                  height: _row,
                  child: Center(
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: off ? null : color,
                        border: off ? Border.all(color: Colors.white30) : null,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  slot.kind.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _slotText.copyWith(color: off ? Colors.white38 : Colors.white.withValues(alpha: 0.9)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddEffectRow extends StatelessWidget {
  final DawController c;
  final int track;
  final bool empty;
  const _AddEffectRow({required this.c, required this.track, required this.empty});

  Future<void> _pick(BuildContext context) async {
    final kind = await pickEffectKind(context);
    if (kind != null) c.addEffect(track, kind);
  }

  @override
  Widget build(BuildContext context) => Container(
    height: _row,
    decoration: BoxDecoration(
      border: empty ? null : const Border(top: BorderSide(color: Palette.hairline)),
    ),
    child: Builder(
      builder: (context) => InkWell(
        onTap: () => _pick(context),
        child: Tooltip(
          message: track < 0 ? 'Adicionar efeito no master' : 'Adicionar efeito',
          waitDuration: const Duration(milliseconds: 800),
          child: const Row(
            children: [
              SizedBox(width: 16, child: Icon(Icons.add, size: 12, color: Colors.white54)),
              Expanded(
                child: Text(
                  'Efeito',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10.5, height: 1.2, color: Colors.white54),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// O menu de adicionar efeito, agrupado por família (`EffectKind.family`), aberto logo abaixo de
/// [context] (ou em [at], posição global). Devolve o tipo escolhido, ou null.
Future<EffectKind?> pickEffectKind(BuildContext context, {Offset? at}) {
  final families = <String, List<EffectKind>>{};
  for (final k in EffectKind.values) {
    (families[k.family] ??= []).add(k);
  }
  final accent = Theme.of(context).colorScheme.primary;
  final entries = <PopupMenuEntry<EffectKind>>[];
  for (final MapEntry(key: family, value: kinds) in families.entries) {
    if (entries.isNotEmpty) entries.add(const PopupMenuDivider(height: 8));
    entries.add(
      PopupMenuItem<EffectKind>(
        enabled: false,
        height: 24,
        child: Text(
          family.toUpperCase(),
          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.9, color: accent),
        ),
      ),
    );
    for (final k in kinds) {
      entries.add(
        PopupMenuItem<EffectKind>(
          value: k,
          height: 40,
          child: Row(
            children: [
              Icon(k.icon, size: 18),
              const SizedBox(width: 12),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(k.label),
                    Text(
                      k.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: Colors.white54),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
  }
  return _showMenu(context, at, entries);
}

// ---------------------------------------------------------------------- envios

Send? _sendTo(DawTrack t, String busId) {
  for (final s in t.sends) {
    if (s.target == busId) return s;
  }
  return null;
}

class _Sends extends StatelessWidget {
  final DawController c;
  final int track;
  final double height;
  const _Sends({required this.c, required this.track, required this.height});

  @override
  Widget build(BuildContext context) {
    final t = c.doc.tracks[track];
    final targets = c.busTargets(track);
    return Container(
      height: height,
      decoration: _box,
      child: targets.isEmpty
          ? Align(
              alignment: Alignment.topCenter,
              child: _NewSendRow(c: c, track: track),
            )
          : _SlotList(
              children: [for (final b in targets) _SendRow(key: ValueKey(b.id), c: c, track: track, bus: b, send: _sendTo(t, b.id))],
            ),
    );
  }
}

/// Nenhum barramento para onde enviar: cria um e já manda a faixa para ele (o caso de sempre é o
/// retorno de reverb ou delay).
class _NewSendRow extends StatelessWidget {
  final DawController c;
  final int track;
  const _NewSendRow({required this.c, required this.track});

  void _create() {
    final id = c.doc.tracks[track].id;
    c.addBusTrack();
    final bus = c.selectedTrack < c.doc.tracks.length ? c.doc.tracks[c.selectedTrack] : null;
    final from = c.doc.tracks.indexWhere((t) => t.id == id);
    if (bus == null || bus.kind != TrackKind.bus || from < 0) return;
    c.setSend(from, bus.id, undoable: true);
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: _row,
    child: Tooltip(
      message: 'Criar um barramento e enviar esta faixa para ele (retorno de reverb, delay...)',
      waitDuration: const Duration(milliseconds: 800),
      child: InkWell(
        onTap: _create,
        child: const Row(
          children: [
            SizedBox(width: 18, child: Icon(Icons.add, size: 12, color: Colors.white54)),
            Expanded(
              child: Text(
                'Envio',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10.5, height: 1.2, color: Colors.white54),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Um envio possível: knob pequeno com o nível e o nome do barramento. Sem envio o knob fica vazio
/// e tocar cria um (pós-fader, no nível padrão); arrastar na vertical (ou a roda no knob) dosa e
/// cria se preciso; botão direito ou toque longo: pré/pós, 0 dB e remover.
class _SendRow extends StatefulWidget {
  final DawController c;
  final int track;
  final DawTrack bus;
  final Send? send;
  const _SendRow({super.key, required this.c, required this.track, required this.bus, required this.send});

  @override
  State<_SendRow> createState() => _SendRowState();
}

class _SendRowState extends State<_SendRow> with _DragValue {
  bool _hover = false;

  @override
  DawController get c => widget.c;
  Send? get _send => widget.send;

  @override
  double get valueNorm => _send == null ? 0 : gainToFader(_send!.level).clamp(0.0, 1.0);

  @override
  bool changes(double n) {
    final level = faderToGain(n);
    final current = _send?.level;
    // sem envio, ficar no zero não cria nada; com envio, só o que mudou
    return current == null ? level > 0 : (level - current).abs() > 1e-9;
  }

  @override
  void apply(double n) => c.setSend(widget.track, widget.bus.id, level: faderToGain(n));

  void _create({bool pre = false}) => c.setSend(widget.track, widget.bus.id, pre: pre, undoable: true);

  Future<void> _menu(Offset? at) async {
    final s = _send;
    final bus = widget.bus.id;
    final v = await _showMenu<String>(context, at, [
      if (s == null) ...[
        _item('post', 'Criar envio pós-fader', icon: Icons.add),
        _item('pre', 'Criar envio pré-fader', icon: Icons.add),
      ] else ...[
        _item('post', 'Pós-fader', checked: !s.pre),
        _item('pre', 'Pré-fader', checked: s.pre),
        const PopupMenuDivider(),
        _item('unity', 'Nível em 0 dB', icon: Icons.exposure_zero),
        _item('remove', 'Remover envio', icon: Icons.delete_outline),
      ],
    ]);
    if (!mounted) return;
    switch (v) {
      case 'post' || 'pre':
        c.setSend(widget.track, bus, pre: v == 'pre', undoable: true);
      case 'unity':
        c.setSend(widget.track, bus, level: 1, undoable: true);
      case 'remove':
        c.removeSend(widget.track, bus);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _send;
    final color = trackColorAt(widget.bus.color);
    final name = widget.bus.name;
    final showLevel = s != null && (active || _hover);
    final tip = s == null
        ? 'Enviar para $name: toque para criar (pós-fader) ou arraste para dosar'
        : 'Envio para $name: ${formatDb(s.level)} dB, ${s.pre ? 'pré' : 'pós'}-fader\n'
              'Arraste ou use a roda · duplo clique: 0 dB · botão direito: pré/pós e remover';
    return Tooltip(
      message: tip,
      waitDuration: const Duration(milliseconds: 800),
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeUpDown,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: _TouchLongPress(
          onLongPress: () => _menu(null),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: s == null ? _create : null,
            onDoubleTap: s == null || s.level == 1 ? null : () => c.setSend(widget.track, widget.bus.id, level: 1, undoable: true),
            onSecondaryTapUp: (d) => _menu(d.globalPosition),
            onVerticalDragStart: dragStart,
            onVerticalDragUpdate: dragUpdate,
            onVerticalDragEnd: (_) => end(),
            onVerticalDragCancel: end,
            child: Row(
              children: [
                Listener(
                  onPointerSignal: onSignal,
                  child: SizedBox(
                    width: 18,
                    height: _row,
                    child: Center(
                      child: SizedBox.square(
                        dimension: 14,
                        child: CustomPaint(
                          painter: _MiniKnobPainter(norm: s == null ? null : (active ? norm : valueNorm), color: color, active: active),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    showLevel ? '${formatDb(s.level)} dB' : name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _slotText.copyWith(
                      color: s == null ? Colors.white38 : (showLevel ? color : Colors.white.withValues(alpha: 0.85)),
                      fontFeatures: showLevel ? const [FontFeature.tabularFigures()] : null,
                    ),
                  ),
                ),
                if (s != null && s.pre)
                  const Padding(
                    padding: EdgeInsets.only(left: 2, right: 3),
                    child: Text(
                      'PRÉ',
                      style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: _preColor),
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

/// Knob pequeno (envio, pan): arco de 270° do [origin] até o valor; sem valor (envio que não
/// existe), só o contorno e um "+".
class _MiniKnobPainter extends CustomPainter {
  final double? norm;
  final double origin;
  final Color color;
  final bool active;
  _MiniKnobPainter({required this.norm, required this.color, required this.active, this.origin = 0});

  static const _start = math.pi * 0.75, _sweep = math.pi * 1.5;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 1.5;
    final rect = Rect.fromCircle(center: center, radius: r);
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: norm == null ? 0.12 : 0.18);
    canvas.drawArc(rect, _start, _sweep, false, track);
    final n = norm;
    if (n == null) {
      final plus = Paint()
        ..strokeWidth = 1.2
        ..color = Colors.white38;
      canvas.drawLine(center.translate(-2.5, 0), center.translate(2.5, 0), plus);
      canvas.drawLine(center.translate(0, -2.5), center.translate(0, 2.5), plus);
      return;
    }
    final value = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = active ? 2.6 : 2.2
      ..strokeCap = StrokeCap.round
      ..color = color;
    if ((n - origin).abs() > 0.001) canvas.drawArc(rect, _start + _sweep * origin, _sweep * (n - origin), false, value);
    final a = _start + _sweep * n;
    canvas.drawLine(center, center + Offset(math.cos(a), math.sin(a)) * (r - 1), value..strokeWidth = 1.4);
  }

  @override
  bool shouldRepaint(_MiniKnobPainter o) => o.norm != norm || o.origin != origin || o.color != color || o.active != active;
}

// ---------------------------------------------------------------------- saída

/// Para onde a faixa sai: o master ou um barramento que não crie ciclo; ou um barramento novo.
class _OutputButton extends StatelessWidget {
  final DawController c;
  final int track;
  const _OutputButton({required this.c, required this.track});

  /// Valor do item "Novo barramento" (ids de faixa são só letras e números).
  static const _newBus = '+';

  void _choose(String v) {
    if (v != _newBus) {
      c.setOutput(track, v.isEmpty ? null : v);
      return;
    }
    // barramento novo como grupo: cria e já liga a saída nele (a faixa pode ter mudado de lugar)
    final id = c.doc.tracks[track].id;
    c.addBusTrack();
    final bus = c.selectedTrack < c.doc.tracks.length ? c.doc.tracks[c.selectedTrack] : null;
    final from = c.doc.tracks.indexWhere((t) => t.id == id);
    if (bus != null && bus.kind == TrackKind.bus && from >= 0) c.setOutput(from, bus.id);
  }

  @override
  Widget build(BuildContext context) {
    final t = c.doc.tracks[track];
    DawTrack? current;
    for (final x in c.doc.tracks) {
      if (x.id == t.output && x.kind == TrackKind.bus) current = x;
    }
    final label = current?.name ?? 'Master';
    final targets = c.busTargets(track);
    return PopupMenuButton<String>(
      tooltip: 'Saída: $label',
      padding: EdgeInsets.zero,
      position: PopupMenuPosition.under,
      onSelected: _choose,
      itemBuilder: (_) => [
        _item('', 'Master', icon: Icons.speaker_outlined, checked: current == null),
        for (final b in targets) _item(b.id, b.name, icon: TrackKind.bus.icon, checked: current?.id == b.id, color: trackColorAt(b.color)),
        const PopupMenuDivider(),
        _item(_newBus, 'Novo barramento', icon: Icons.add),
      ],
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Palette.hairlineStrong),
        ),
        padding: const EdgeInsets.only(left: 4),
        child: Row(
          children: [
            Icon(
              current == null ? Icons.speaker_outlined : TrackKind.bus.icon,
              size: 11,
              color: current == null ? Colors.white54 : trackColorAt(current.color),
            ),
            const SizedBox(width: 3),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10, height: 1.2, color: Colors.white70),
              ),
            ),
            const Icon(Icons.arrow_drop_down, size: 14, color: Colors.white54),
          ],
        ),
      ),
    );
  }
}

/// O lugar da saída no master: ele vai para o aparelho.
class _DeviceOutput extends StatelessWidget {
  const _DeviceOutput();

  @override
  Widget build(BuildContext context) => const Tooltip(
    message: 'O master sai no áudio do aparelho, depois do limitador de segurança',
    waitDuration: Duration(milliseconds: 800),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.volume_up_outlined, size: 11, color: Colors.white38),
        SizedBox(width: 3),
        Flexible(
          child: Text(
            'Saída',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10, height: 1.2, color: Colors.white38),
          ),
        ),
      ],
    ),
  );
}

// ---------------------------------------------------------------------- menus

/// Toque longo só no toque: com mouse, o reconhecedor venceria o arraste (ou o clique) de quem
/// segura parado um instante; lá o menu é do botão direito.
class _TouchLongPress extends StatelessWidget {
  final VoidCallback onLongPress;
  final Widget child;
  const _TouchLongPress({required this.onLongPress, required this.child});

  @override
  Widget build(BuildContext context) => GestureDetector(
    supportedDevices: const {PointerDeviceKind.touch, PointerDeviceKind.stylus, PointerDeviceKind.invertedStylus},
    onLongPress: onLongPress,
    child: child,
  );
}

/// Item de menu com ícone; com [checked], uma coluna de marca antes (escolha entre opções) e o
/// ícone pequeno, na [color] dada, junto do texto.
PopupMenuItem<String> _item(String value, String label, {IconData? icon, bool? checked, Color? color}) => PopupMenuItem(
  value: value,
  height: 38,
  child: Row(
    children: [
      SizedBox(width: 22, child: checked == null ? Icon(icon, size: 18, color: color) : (checked ? const Icon(Icons.check, size: 16) : null)),
      const SizedBox(width: 10),
      if (checked != null && icon != null) ...[Icon(icon, size: 14, color: color ?? Colors.white54), const SizedBox(width: 6)],
      Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
    ],
  ),
);

/// Abre um menu em [at] (posição global, a do clique) ou, sem ela, logo abaixo de [context].
Future<T?> _showMenu<T>(BuildContext context, Offset? at, List<PopupMenuEntry<T>> items) {
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  final Rect anchor;
  if (at != null) {
    anchor = overlay.globalToLocal(at) & Size.zero;
  } else {
    final box = context.findRenderObject()! as RenderBox;
    final topLeft = box.localToGlobal(Offset(0, box.size.height), ancestor: overlay);
    anchor = topLeft & Size(box.size.width, 0);
  }
  return showMenu<T>(context: context, position: RelativeRect.fromRect(anchor, Offset.zero & overlay.size), items: items);
}
