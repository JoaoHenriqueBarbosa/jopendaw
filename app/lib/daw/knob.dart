/// Os controles dos parâmetros de instrumento: o knob giratório e, para listas de opções, um
/// seletor compacto na mesma célula (valor em cima, controle, rótulo embaixo), para os dois se
/// alinharem lado a lado nos cartões.
///
/// Os valores entram e saem na unidade da tabela ([ParamSpec]: Hz, segundos, semitons); o arco
/// mostra `toNorm` e o gesto volta por `fromNorm`, o que dá curva logarítmica em frequência e tempo
/// e passos inteiros onde a tabela pede.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Curve;
import 'package:flutter/services.dart';

import '../widgets/theme.dart';
import 'instruments.dart';

/// Altura de cada linha de texto da célula (valor em cima, rótulo embaixo).
const _line = 14.0;

/// Altura da célula de um knob de diâmetro [size], para quem monta grades.
double knobCellHeight(double size) => size + 2 * _line + 4;

/// Largura da célula de um knob de diâmetro [size]: cabe "Sustentação" sem cortar.
double knobCellWidth(double size) => math.max(62, size + 18);

const _choiceText = TextStyle(fontSize: 11, fontWeight: FontWeight.w600);

/// Largura do texto mais longo de cada lista de opções (as listas são constantes da tabela).
final _optionsWidth = Expando<double>();

/// Largura da célula de um seletor de opções: cabe a opção mais longa ("Passa-banda") com o ícone.
/// [style] é o texto da caixa já com a fonte do tema (a medida vale para a fonte que desenha).
double choiceCellWidth(double size, {List<String> options = const [], bool icon = false, TextStyle style = _choiceText}) {
  final text = options.isEmpty ? 0.0 : (_optionsWidth[options] ??= _widest(options, style));
  // margem esquerda (7), ícone (18 + 5), a seta (16 + 2), borda e folga
  final box = 7 + (icon ? 23 : 0) + text + 18 + 8;
  return math.max(math.max(88.0, size * 2), box.ceilToDouble()).clamp(88.0, 150.0);
}

double _widest(List<String> options, TextStyle style) {
  var w = 0.0;
  for (final o in options) {
    final tp = TextPainter(
      text: TextSpan(text: o, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    w = math.max(w, tp.width);
    tp.dispose();
  }
  return w;
}

/// Uma entrada extra do menu de contexto do knob (botão direito ou toque longo), abaixo de
/// "Digitar o valor…" (o MIDI learn põe aqui "Aprender MIDI" e "Remover mapeamento").
class KnobMenuAction {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const KnobMenuAction(this.label, this.icon, this.onTap);
}

/// Knob de um parâmetro. Para [Curve.choice] vira um seletor compacto (menu).
///
/// Gestos: arrastar na vertical (Shift = ajuste fino), roda do mouse, duplo clique volta ao padrão,
/// botão direito (ou toque longo no celular) abre um campo para digitar o valor.
///
/// Callbacks, sempre na unidade da tabela: [onChangeStart] uma vez por gesto, logo antes da
/// primeira mudança de fato (clicar sem mexer não gera ponto de desfazer); [onChanged] a cada
/// passo; [onChangeEnd] no fim do gesto que mudou algo. No seletor de opções a escolha é um passo
/// discreto: só [onChanged], uma vez.
class Knob extends StatefulWidget {
  final ParamSpec spec;
  final double value;
  final ValueChanged<double>? onChangeStart;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;

  /// Diâmetro do knob.
  final double size;

  /// Cor do arco ativo (a da faixa).
  final Color color;

  /// Rótulo embaixo; o padrão é o nome da tabela.
  final String? label;

  /// Texto do valor; o padrão é `spec.format`.
  final String Function(double value)? format;

  /// Parâmetro que não faz efeito agora (pulso sem onda quadrada, por exemplo): fica apagado,
  /// mas continua mexível.
  final bool dimmed;

  /// Ícone de cada opção no seletor (formas de onda, tipos de filtro); null = só o texto.
  final Widget? Function(int option, Color color)? optionIcon;

  /// Entradas extras do menu de contexto; null = o botão direito abre direto o campo de digitar.
  final List<KnobMenuAction> Function()? extraActions;

  const Knob({
    super.key,
    required this.spec,
    required this.value,
    required this.onChanged,
    this.onChangeStart,
    this.onChangeEnd,
    this.size = 40,
    this.color = Palette.accent,
    this.label,
    this.format,
    this.dimmed = false,
    this.optionIcon,
    this.extraActions,
  });

  @override
  State<Knob> createState() => _KnobState();
}

class _KnobState extends State<Knob> {
  /// Um gesto em andamento (arraste, rajada da roda) e se ele já mudou o valor.
  bool _active = false, _changed = false;
  bool _hover = false;

  /// Posição 0..1 acumulada no gesto: contínua, para inteiros andarem um passo de cada vez em vez
  /// de ficarem presos no arredondamento.
  double _norm = 0;

  /// Último valor emitido no gesto (o pai pode demorar um quadro para devolver o novo).
  double _last = 0;
  double _wheelAcc = 0;
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
    _wheelAcc = 0;
    setState(() {});
  }

  void _emit(double v) {
    v = _spec.clamp(v);
    if (v == _last) return;
    if (!_changed) {
      _changed = true;
      widget.onChangeStart?.call(_last);
    }
    _last = v;
    widget.onChanged(v);
  }

  void _end() {
    _wheelIdle?.cancel();
    _wheelIdle = null;
    if (!_active) return;
    _active = false;
    if (_changed) widget.onChangeEnd?.call(_last);
    _changed = false;
    if (mounted) setState(() {});
  }

  /// Um valor de uma vez só (duplo clique, digitado, acessibilidade): um gesto completo.
  void _set(double v) {
    _end();
    _begin();
    _emit(v);
    _end();
  }

  void _dragStart(DragStartDetails _) {
    _end();
    _begin();
  }

  void _dragUpdate(DragUpdateDetails d) {
    // 200 px de curso para a faixa toda; com Shift, cinco vezes mais fino
    final travel = HardwareKeyboard.instance.isShiftPressed ? 1000.0 : 200.0;
    _norm = (_norm - d.delta.dy / travel).clamp(0.0, 1.0);
    _emit(_spec.fromNorm(_norm));
  }

  void _onSignal(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    // registrar no resolvedor tira a rolagem da lista em volta: a roda em cima do knob é dele
    GestureBinding.instance.pointerSignalResolver.register(e, (ev) => _wheel((ev as PointerScrollEvent).scrollDelta));
  }

  void _wheel(Offset delta) {
    // Shift + roda chega como rolagem horizontal em alguns sistemas
    final dy = delta.dy != 0 ? delta.dy : delta.dx;
    if (dy == 0) return;
    _begin();
    if (_spec.curve == Curve.integer) {
      // inteiros andam um passo por "dente" da roda; o trackpad acumula até dar um passo
      _wheelAcc -= dy;
      const notch = 50.0;
      final steps = (_wheelAcc / notch).truncate();
      if (steps != 0) {
        _wheelAcc -= steps * notch;
        _emit(_last + steps);
      }
    } else {
      final travel = HardwareKeyboard.instance.isShiftPressed ? 8000.0 : 1600.0;
      _norm = (_norm - dy / travel).clamp(0.0, 1.0);
      _emit(_spec.fromNorm(_norm));
    }
    _wheelIdle?.cancel();
    _wheelIdle = Timer(const Duration(milliseconds: 500), _end);
  }

  void _reset() {
    if (_spec.clamp(widget.value) == _spec.def) return;
    _set(_spec.def);
  }

  Future<void> _type() async {
    _end();
    final v = await showDialog<double>(
      context: context,
      builder: (_) => _ValueDialog(spec: _spec, value: widget.value, label: widget.label ?? _spec.name, format: _fmt),
    );
    if (v != null && mounted) _set(v);
  }

  /// Botão direito ou toque longo: o campo de digitar o valor, ou, se há [Knob.extraActions], um menu
  /// com ele e as entradas extras.
  Future<void> _context(Offset? at) async {
    final extra = widget.extraActions?.call();
    if (extra == null || extra.isEmpty) return _type();
    _end();
    final box = context.findRenderObject() as RenderBox;
    final origin = at ?? box.localToGlobal(box.size.center(Offset.zero));
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final pick = await showMenu<int>(
      context: context,
      position: RelativeRect.fromRect(origin & Size.zero, Offset.zero & overlay.size),
      items: [
        const PopupMenuItem(value: -1, child: Row(children: [Icon(Icons.keyboard_outlined, size: 18), SizedBox(width: 10), Text('Digitar o valor…')])),
        const PopupMenuDivider(),
        for (var i = 0; i < extra.length; i++)
          PopupMenuItem(
            value: i,
            child: Row(
              children: [
                Icon(extra[i].icon, size: 18),
                const SizedBox(width: 10),
                Flexible(child: Text(extra[i].label, maxLines: 1, overflow: TextOverflow.ellipsis)),
              ],
            ),
          ),
      ],
    );
    if (pick == null || !mounted) return;
    if (pick < 0) {
      await _type();
    } else {
      extra[pick].onTap();
    }
  }

  /// Um passo para teclado/leitor de tela: uma unidade em inteiros, 5% do curso no resto.
  double _stepped(int dir) {
    if (_spec.curve == Curve.integer) return _spec.clamp(widget.value + dir);
    return _spec.fromNorm(_spec.toNorm(widget.value) + dir * 0.05);
  }

  @override
  Widget build(BuildContext context) {
    if (_spec.curve == Curve.choice) {
      return _ChoiceCell(
        spec: _spec,
        value: widget.value,
        size: widget.size,
        color: widget.color,
        label: widget.label ?? _spec.name,
        dimmed: widget.dimmed,
        optionIcon: widget.optionIcon,
        onChanged: widget.onChanged,
      );
    }
    final label = widget.label ?? _spec.name;
    final value = _spec.clamp(widget.value);
    final dim = widget.dimmed && !_active;
    final bipolar = _spec.min < 0 && _spec.max > 0;
    final valueStyle = TextStyle(
      fontSize: 10.5,
      height: 1.2,
      fontFeatures: const [FontFeature.tabularFigures()],
      fontWeight: _active ? FontWeight.w700 : FontWeight.w500,
      color: _active ? widget.color : (dim ? Colors.white24 : (_hover ? Colors.white : Colors.white60)),
    );
    final labelStyle = TextStyle(fontSize: 10.5, height: 1.2, color: dim ? Colors.white30 : Colors.white70);
    return Semantics(
      slider: true,
      label: label,
      value: _fmt(value),
      increasedValue: _fmt(_stepped(1)),
      decreasedValue: _fmt(_stepped(-1)),
      onIncrease: () => _set(_stepped(1)),
      onDecrease: () => _set(_stepped(-1)),
      child: Tooltip(
        message: '$label: arraste ou use a roda (Shift: ajuste fino)\nDuplo clique: padrão (${_fmt(_spec.def)}) · botão direito: digitar o valor',
        waitDuration: const Duration(milliseconds: 900),
        // no toque o toque longo é para digitar o valor, não para a dica
        triggerMode: TooltipTriggerMode.manual,
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeUpDown,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: Listener(
            onPointerSignal: _onSignal,
            // toque longo (digitar o valor) só no toque: com mouse, o reconhecedor venceria o
            // arraste de quem segura parado um instante antes de mover
            child: GestureDetector(
              supportedDevices: const {PointerDeviceKind.touch, PointerDeviceKind.stylus, PointerDeviceKind.invertedStylus},
              onLongPress: () => _context(null),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragStart: _dragStart,
                onVerticalDragUpdate: _dragUpdate,
                onVerticalDragEnd: (_) => _end(),
                onVerticalDragCancel: _end,
                onDoubleTap: _reset,
                onSecondaryTapUp: (d) => _context(d.globalPosition),
                child: SizedBox(
                  width: knobCellWidth(widget.size),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        height: _line,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(_fmt(value), maxLines: 1, style: valueStyle),
                        ),
                      ),
                      const SizedBox(height: 1),
                      SizedBox.square(
                        dimension: widget.size,
                        child: CustomPaint(
                          painter: _KnobPainter(
                            norm: _spec.toNorm(value),
                            origin: bipolar ? _spec.toNorm(0) : 0,
                            defaultNorm: _spec.toNorm(_spec.def),
                            color: widget.color,
                            active: _active,
                            hover: _hover,
                            dimmed: dim,
                          ),
                        ),
                      ),
                      const SizedBox(height: 3),
                      SizedBox(
                        height: _line,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(label, maxLines: 1, style: labelStyle),
                        ),
                      ),
                    ],
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

class _KnobPainter extends CustomPainter {
  final double norm, origin, defaultNorm;
  final Color color;
  final bool active, hover, dimmed;

  _KnobPainter({
    required this.norm,
    required this.origin,
    required this.defaultNorm,
    required this.color,
    required this.active,
    required this.hover,
    required this.dimmed,
  });

  /// 270° de curso, do canto de baixo à esquerda ao de baixo à direita.
  static const _start = math.pi * 0.75, _sweep = math.pi * 1.5;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final stroke = math.max(2.5, r * 0.15);
    final arcR = r - stroke / 2 - 0.5;
    final rect = Rect.fromCircle(center: c, radius: arcR);
    final tint = dimmed ? color.withValues(alpha: 0.35) : color;

    canvas.drawArc(
      rect,
      _start,
      _sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: 0.08),
    );

    // marca discreta do valor padrão no trilho
    final dA = _start + _sweep * defaultNorm;
    canvas.drawCircle(c + Offset(math.cos(dA), math.sin(dA)) * (arcR + stroke * 0.5 + 1.5), 1.1, Paint()..color = Colors.white24);

    final a0 = _start + _sweep * origin, a1 = _start + _sweep * norm;
    final active = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = tint;
    if ((a1 - a0).abs() > 0.002) {
      final from = math.min(a0, a1), sweep = (a1 - a0).abs();
      if (this.active && !dimmed) {
        canvas.drawArc(
          rect,
          from,
          sweep,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = stroke * 2.2
            ..strokeCap = StrokeCap.round
            ..color = color.withValues(alpha: 0.28)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
        );
      }
      canvas.drawArc(rect, from, sweep, false, active);
    }

    // a tampa do knob, com luz vinda de cima
    final capR = arcR - stroke * 1.15;
    if (capR <= 2) return;
    final cap = Rect.fromCircle(center: c, radius: capR);
    canvas.drawCircle(
      c,
      capR,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.5),
          radius: 1.1,
          colors: hover || this.active ? const [Color(0xFF3A404B), Color(0xFF1E232A)] : const [Color(0xFF323741), Color(0xFF1B1F25)],
        ).createShader(cap),
    );
    canvas.drawCircle(
      c,
      capR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: this.active ? 0.22 : 0.1),
    );
    final dir = Offset(math.cos(a1), math.sin(a1));
    canvas.drawLine(
      c + dir * capR * 0.28,
      c + dir * capR * 0.9,
      Paint()
        ..color = dimmed ? Colors.white38 : Colors.white
        ..strokeWidth = math.max(1.6, r * 0.075)
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_KnobPainter o) =>
      o.norm != norm || o.origin != origin || o.defaultNorm != defaultNorm || o.color != color || o.active != active || o.hover != hover || o.dimmed != dimmed;
}

/// Seletor de opções no formato de célula do knob: caixa com a opção atual (e ícone), menu ao
/// tocar.
class _ChoiceCell extends StatelessWidget {
  final ParamSpec spec;
  final double value, size;
  final Color color;
  final String label;
  final bool dimmed;
  final Widget? Function(int option, Color color)? optionIcon;
  final ValueChanged<double> onChanged;

  const _ChoiceCell({
    required this.spec,
    required this.value,
    required this.size,
    required this.color,
    required this.label,
    required this.dimmed,
    required this.optionIcon,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final index = spec.clamp(value).round();
    final icon = optionIcon?.call(index, dimmed ? Colors.white38 : color);
    final boxHeight = math.min(size, 34.0);
    return SizedBox(
      width: choiceCellWidth(size, options: spec.options, icon: icon != null, style: DefaultTextStyle.of(context).style.merge(_choiceText)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: _line + 1),
          SizedBox(
            height: size,
            child: Center(
              child: PopupMenuButton<int>(
                tooltip: label,
                initialValue: index,
                position: PopupMenuPosition.under,
                onSelected: (i) {
                  if (i != index) onChanged(i.toDouble());
                },
                itemBuilder: (_) => [
                  for (var i = 0; i < spec.options.length; i++)
                    PopupMenuItem(
                      value: i,
                      height: 36,
                      child: Row(
                        children: [
                          SizedBox(width: 22, child: i == index ? Icon(Icons.check, size: 16, color: color) : null),
                          if (optionIcon?.call(i, color) case final w?) ...[SizedBox(width: 20, height: 12, child: w), const SizedBox(width: 8)],
                          Text(spec.options[i]),
                        ],
                      ),
                    ),
                ],
                child: Container(
                  height: boxHeight,
                  padding: const EdgeInsets.only(left: 7, right: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: Palette.hairlineStrong),
                  ),
                  child: Row(
                    children: [
                      if (icon != null) ...[SizedBox(width: 18, height: 12, child: icon), const SizedBox(width: 5)],
                      Expanded(
                        child: Text(
                          spec.options[index],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _choiceText.copyWith(color: dimmed ? Colors.white38 : Colors.white),
                        ),
                      ),
                      Icon(Icons.arrow_drop_down, size: 16, color: dimmed ? Colors.white24 : Colors.white54),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 3),
          SizedBox(
            height: _line,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(label, maxLines: 1, style: TextStyle(fontSize: 10.5, height: 1.2, color: dimmed ? Colors.white30 : Colors.white70)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Campo para digitar o valor exato, com a unidade ("440 Hz", "250 ms", "-3 st", "C4").
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
  Widget build(BuildContext context) {
    final s = widget.spec;
    return AlertDialog(
      title: Text(widget.label),
      content: SizedBox(
        width: 320,
        child: TextField(
          controller: _ctl,
          autofocus: true,
          decoration: InputDecoration(helperText: 'De ${widget.format(s.min)} a ${widget.format(s.max)}', errorText: _error),
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
}

const _noteSteps = {'c': 0, 'd': 2, 'e': 4, 'f': 5, 'g': 7, 'a': 9, 'b': 11};

/// Lê um valor digitado na unidade do parâmetro, aceitando o que `format` escreve: "2.40 kHz",
/// "250 ms", "70%", "+7 st", "×1.50", "1.5 oit" e, em parâmetros de nota MIDI, "C4" ou "F#3".
/// Vírgula vale como ponto. Sem unidade, segundos acima do máximo são lidos como milissegundos
/// ("300" num ataque de até 10 s é 300 ms). Devolve null se não entender; fora da faixa, limita.
double? parseParamValue(ParamSpec spec, String text) {
  final s = text.trim().toLowerCase().replaceAll(',', '.').replaceAll('−', '-').replaceAll('×', '').replaceAll(RegExp(r'\s+'), '');
  if (s.isEmpty) return null;
  if (spec.curve == Curve.integer && spec.min == 0 && spec.max == 127) {
    final m = RegExp(r'^([a-g])([#b]?)(-?\d)$').firstMatch(s);
    if (m != null) {
      final accidental = switch (m.group(2)) {
        '#' => 1,
        'b' => -1,
        _ => 0,
      };
      return spec.clamp(((int.parse(m.group(3)!) + 1) * 12 + _noteSteps[m.group(1)]! + accidental).toDouble());
    }
  }
  final m = RegExp(r'^x?([+-]?(?:\d+\.?\d*|\.\d+))([a-z%]*)$').firstMatch(s);
  if (m == null) return null;
  var v = double.parse(m.group(1)!);
  final unit = m.group(2)!;
  bool accepts(List<String> units) => unit.isEmpty || units.contains(unit);
  switch (spec.unit) {
    case 'Hz':
      if (unit == 'k' || unit == 'khz') {
        v *= 1000;
      } else if (!accepts(['hz'])) {
        return null;
      }
    case 's':
      if (unit == 'ms' || (unit.isEmpty && v > spec.max)) {
        v /= 1000;
      } else if (!accepts(['s'])) {
        return null;
      }
    case '%':
      if (!accepts(['%'])) return null;
      v /= 100;
    case 'st':
      if (!accepts(['st'])) return null;
    case 'ct':
      if (!accepts(['ct'])) return null;
    case 'x':
      if (!accepts(['x'])) return null;
    case 'oct':
      if (!accepts(['oit', 'oct'])) return null;
    default:
      if (unit.isNotEmpty) return null;
  }
  if (!v.isFinite) return null;
  return spec.clamp(spec.curve == Curve.integer ? v.roundToDouble() : v);
}
