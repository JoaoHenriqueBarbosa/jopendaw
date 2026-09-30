/// O cartão "Zonas" do sampler: um mapa de teclado com as zonas como blocos coloridos (notas na
/// horizontal, velocidade na vertical), a edição da zona selecionada (nota base, faixas, afinação,
/// ganho, pan, modo, grupo de round-robin, trecho e loop) e os atalhos para acrescentar um áudio
/// como zona e para fatiar um sample.
///
/// No mapa, arrastar a borda esquerda ou direita de um bloco muda a faixa de notas, a de cima ou
/// a de baixo muda a faixa de velocidade, e arrastar o corpo move o bloco só na horizontal (a faixa
/// de notas e a nota base vão juntas; a velocidade só muda pelas bordas de cima e de baixo ou pelos
/// campos).
/// Um arraste que começa fora de qualquer bloco rola o mapa. Cada arraste é um passo só no
/// desfazer. No celular o mapa rola na horizontal e os controles ficam em coluna.
library;

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../widgets/feedback.dart';
import 'controller.dart';
import 'instruments.dart';
import 'sampler_zones.dart';
import 'sampler_zones_controller.dart';
import 'slice_dialog.dart';

/// Cor de uma zona (pela posição na lista, para as vizinhas serem distintas).
Color zoneColor(int index) => HSLColor.fromAHSL(1, (index * 47 + 12) % 360, 0.62, 0.55).toColor();

/// Onde, no bloco de uma zona, o ponteiro pegou.
enum ZonePart { body, left, right, top, bottom }

/// A geometria do mapa: cada nota ocupa [noteW] de largura; a velocidade 127 fica no topo e a 1
/// embaixo. Pura, para os testes conferirem a conversão e o que cada ponto do bloco pega.
class ZoneMapGeometry {
  final double noteW, height;

  /// Largura da faixa em que uma borda pega o arraste.
  final double slop;
  const ZoneMapGeometry({required this.noteW, required this.height, this.slop = 7});

  double get width => noteW * 128;
  double get _velStep => height / 127;

  int noteAt(double x) => (x / noteW).floor().clamp(0, 127);
  int velAt(double y) => (127 - (y / _velStep).floor()).clamp(1, 127);

  Rect rectOf(SamplerZone z) => Rect.fromLTRB(z.lo * noteW, (127 - z.vhi) * _velStep, (z.hi + 1) * noteW, (128 - z.vlo) * _velStep);

  /// O bloco mais acima (o último da lista) sob [p] e a parte dele; null fora de todos. Um bloco
  /// estreito (menos de três larguras de borda) não tem borda: é só corpo (muda-se a faixa pelos
  /// controles).
  ({SamplerZone zone, ZonePart part})? hit(List<SamplerZone> zones, Offset p, {String? preferred}) {
    final order = [...zones.reversed];
    if (preferred != null) {
      final i = order.indexWhere((z) => z.id == preferred);
      // o selecionado ganha das camadas por cima dele, para dar para pegar suas bordas
      if (i > 0 && rectOf(order[i]).inflate(0).contains(p)) order.insert(0, order.removeAt(i));
    }
    for (final z in order) {
      final r = rectOf(z);
      if (!r.contains(p)) continue;
      var part = ZonePart.body;
      if (r.width >= slop * 3) {
        if (p.dx - r.left <= slop) {
          part = ZonePart.left;
        } else if (r.right - p.dx <= slop) {
          part = ZonePart.right;
        }
      }
      if (part == ZonePart.body && r.height >= slop * 3) {
        if (p.dy - r.top <= slop) {
          part = ZonePart.top;
        } else if (r.bottom - p.dy <= slop) {
          part = ZonePart.bottom;
        }
      }
      return (zone: z, part: part);
    }
    return null;
  }
}

/// Muda a faixa de [z] como o arraste de [part] até o ponteiro ([note], [vel]) pediria, partindo
/// da cópia [from] (a zona no começo do arraste) e do ponto onde ele começou ([n0]; [v0] não é usado:
/// arrastar o corpo não mexe na velocidade).
void dragZone(SamplerZone z, SamplerZone from, ZonePart part, {required int note, required int vel, required int n0, required int v0}) {
  switch (part) {
    case ZonePart.left:
      z.lo = math.min(note, from.hi);
    case ZonePart.right:
      z.hi = math.max(note, from.lo);
    case ZonePart.top:
      z.vhi = math.max(vel, from.vlo);
    case ZonePart.bottom:
      z.vlo = math.min(vel, from.vhi);
    case ZonePart.body:
      final dn = (note - n0).clamp(-from.lo, 127 - from.hi);
      z
        ..lo = from.lo + dn
        ..hi = from.hi + dn
        ..root = (from.root + dn).clamp(0, 127);
  }
}

class SamplerZonesPanel extends StatefulWidget {
  final DawController c;
  final int track;
  final Color color;
  final bool compact;
  const SamplerZonesPanel({super.key, required this.c, required this.track, required this.color, required this.compact});

  @override
  State<SamplerZonesPanel> createState() => _SamplerZonesPanelState();
}

class _SamplerZonesPanelState extends State<SamplerZonesPanel> {
  String? _selected;

  /// Aviso da última zona acrescentada (teclado dividido ou sobreposto).
  String? _notice;

  DawController get c => widget.c;
  List<SamplerZone> get _zones => c.zonesOf(widget.track);

  SamplerZone? get _zone {
    final id = _selected;
    return id == null ? null : _zones.where((z) => z.id == id).firstOrNull;
  }

  static const _importItem = 'importar';

  Future<void> _add(String value) async {
    String? notice;
    void say(String text) => notice = text;
    final z = value == _importItem ? await c.addZoneFromFile(widget.track, onNotice: say) : c.addZone(widget.track, value, onNotice: say);
    if (z != null && mounted) {
      setState(() {
        _selected = z.id;
        _notice = notice;
      });
    }
  }

  Widget _addButton() {
    final samples = c.doc.samples.entries.toList()..sort((a, b) => a.value.name.toLowerCase().compareTo(b.value.name.toLowerCase()));
    return PopupMenuButton<String>(
      tooltip: 'Acrescentar um áudio como zona',
      position: PopupMenuPosition.under,
      constraints: const BoxConstraints(minWidth: 240, maxWidth: 360, maxHeight: 420),
      onSelected: _add,
      itemBuilder: (_) => [
        for (final e in samples)
          PopupMenuItem(
            value: e.key,
            height: 38,
            child: Text(e.value.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        if (samples.isNotEmpty) const PopupMenuDivider(),
        const PopupMenuItem(
          value: _importItem,
          height: 38,
          child: Row(children: [Icon(Icons.upload_file, size: 16), SizedBox(width: 8), Text('Importar um arquivo…')]),
        ),
      ],
      child: _ChipButton(icon: Icons.add, label: 'Adicionar sample como zona', color: widget.color),
    );
  }

  @override
  Widget build(BuildContext context) {
    final zones = _zones;
    final sel = _zone;
    final t = c.doc.tracks[widget.track];
    final canFromTrack = zones.isEmpty && t.sample != null && c.doc.samples.containsKey(t.sample);
    final toolbar = Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _addButton(),
        GestureDetector(
          onTap: () => showSliceDialog(context, c, widget.track),
          child: _ChipButton(icon: Icons.content_cut, label: 'Fatiar sample…', color: widget.color),
        ),
        if (canFromTrack)
          GestureDetector(
            onTap: () => setState(() => _selected = c.zoneFromTrackSample(widget.track)?.id),
            child: _ChipButton(icon: Icons.input, label: 'Usar o áudio atual como zona', color: widget.color),
          ),
        if (zones.isNotEmpty) Text('${zones.length} ${zones.length == 1 ? 'zona' : 'zonas'}', style: const TextStyle(fontSize: 12, color: Colors.white54)),
        if (zones.isNotEmpty)
          GestureDetector(
            onTap: () {
              c.clearZones(widget.track);
              setState(() {
                _selected = null;
                _notice = null;
              });
            },
            child: const Text(
              'Apagar todas',
              style: TextStyle(fontSize: 12, color: Colors.white54, decoration: TextDecoration.underline),
            ),
          ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        toolbar,
        const SizedBox(height: 8),
        if (_notice != null && zones.isNotEmpty) ...[
          InlineNotice(_notice!, error: false, onClose: () => setState(() => _notice = null)),
          const SizedBox(height: 8),
        ],
        if (zones.isEmpty)
          const _EmptyHint()
        else ...[
          _ZoneMap(c: c, track: widget.track, zones: zones, selected: _selected, compact: widget.compact, onSelect: (id) => setState(() => _selected = id)),
          const SizedBox(height: 8),
          if (sel == null)
            const Text('Toque num bloco para editar a zona.', style: TextStyle(fontSize: 12, color: Colors.white54))
          else
            _ZoneEditor(
              key: ValueKey(sel.id),
              c: c,
              track: widget.track,
              zone: sel,
              color: zoneColor(zones.indexOf(sel)),
              compact: widget.compact,
              onGone: () => setState(() => _selected = null),
              onDuplicate: () => setState(() => _selected = c.duplicateZone(widget.track, sel.id)?.id ?? _selected),
              onLayers: (n) {
                final made = c.splitZoneLayers(widget.track, sel.id, n);
                setState(
                  () => _notice = made.isEmpty
                      ? 'Não coube: as zonas já estão no limite de $maxZones.'
                      : '${made.length} ${made.length == 1 ? 'cópia criada' : 'cópias criadas'} logo depois desta zona, cada uma com a sua faixa de velocidade. Selecione cada uma e troque o áudio.',
                );
              },
            ),
        ],
      ],
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 8),
    child: Text(
      'Sem zonas o sampler toca um áudio só, afinado pelas notas. Acrescente samples como zonas para espalhá-los pelo teclado '
      '(e por camadas de velocidade), ou fatie um loop: cada fatia vira uma nota, a partir do C1. '
      'Com zonas, o áudio único e a nota base do cartão Áudio deixam de valer.',
      style: TextStyle(fontSize: 12, color: Colors.white60, height: 1.35),
    ),
  );
}

class _ChipButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _ChipButton({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    height: 28,
    padding: const EdgeInsets.symmetric(horizontal: 9),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: color.withValues(alpha: 0.6)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

// ------------------------------------------------------------------------------------ o mapa

/// Só aceita o ponteiro que cai sobre um bloco: o resto do mapa fica para a rolagem.
class _ZonePan extends PanGestureRecognizer {
  /// Recebe a posição global do ponteiro.
  bool Function(Offset global) allow;
  _ZonePan(this.allow);

  @override
  bool isPointerAllowed(PointerEvent event) => allow(event.position) && super.isPointerAllowed(event);
}

class _ZoneMap extends StatefulWidget {
  final DawController c;
  final int track;
  final List<SamplerZone> zones;
  final String? selected;
  final bool compact;
  final void Function(String? id) onSelect;
  const _ZoneMap({required this.c, required this.track, required this.zones, required this.selected, required this.compact, required this.onSelect});

  @override
  State<_ZoneMap> createState() => _ZoneMapState();
}

class _ZoneMapState extends State<_ZoneMap> {
  ({String id, ZonePart part, SamplerZone from, int n0, int v0})? _drag;
  final _scroll = ScrollController();

  /// Teclas do teclado embaixo do mapa que estão tocando (prévia).
  final _held = <int, int>{};

  static const _keysHeight = 30.0;

  @override
  void dispose() {
    _scroll.dispose();
    for (final p in _held.keys.toList()) {
      widget.c.noteOff(p, track: widget.track);
    }
    super.dispose();
  }

  ZoneMapGeometry _geo(double avail) {
    final h = widget.compact ? 96.0 : 120.0;
    // cada nota tem no mínimo 8 px: o mapa rola quando não cabe
    return ZoneMapGeometry(noteW: math.max(8, avail / 128), height: h);
  }

  /// Pinta o mapa: serve para passar a posição global do ponteiro para as coordenadas dele.
  final _mapKey = GlobalKey();

  bool _allow(ZoneMapGeometry g, Offset global) {
    final box = _mapKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached) return false;
    return g.hit(widget.zones, box.globalToLocal(global), preferred: widget.selected) != null;
  }

  void _start(ZoneMapGeometry g, Offset p) {
    final h = g.hit(widget.zones, p, preferred: widget.selected);
    if (h == null) return;
    widget.onSelect(h.zone.id);
    widget.c.checkpoint();
    _drag = (id: h.zone.id, part: h.part, from: h.zone.copy(), n0: g.noteAt(p.dx), v0: g.velAt(p.dy));
  }

  void _update(ZoneMapGeometry g, Offset p) {
    final d = _drag;
    if (d == null) return;
    final note = g.noteAt(p.dx), vel = g.velAt(p.dy);
    widget.c.editZone(widget.track, d.id, (z) => dragZone(z, d.from, d.part, note: note, vel: vel, n0: d.n0, v0: d.v0), undoable: false);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final g = _geo(box.maxWidth);
      return SizedBox(
        height: g.height + _keysHeight,
        child: Scrollbar(
          controller: _scroll,
          child: SingleChildScrollView(
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: g.width,
              child: Column(
                children: [
                  SizedBox(
                    key: const ValueKey('zone-map'),
                    height: g.height,
                    child: RawGestureDetector(
                      behavior: HitTestBehavior.opaque,
                      gestures: {
                        TapGestureRecognizer: GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(TapGestureRecognizer.new, (t) {
                          t.onTapUp = (e) => widget.onSelect(g.hit(widget.zones, e.localPosition, preferred: widget.selected)?.zone.id);
                        }),
                        _ZonePan: GestureRecognizerFactoryWithHandlers<_ZonePan>(() => _ZonePan((p) => _allow(g, p)), (r) {
                          // o arraste parte de onde o dedo desceu (e não de onde passou da folga do gesto)
                          r.dragStartBehavior = DragStartBehavior.down;
                          r.allow = (p) => _allow(g, p);
                          r.onStart = (e) => _start(g, e.localPosition);
                          r.onUpdate = (e) => _update(g, e.localPosition);
                          r.onEnd = (_) => _drag = null;
                          r.onCancel = () => _drag = null;
                        }),
                      },
                      child: CustomPaint(key: _mapKey, size: Size(g.width, g.height), painter: _MapPainter(g, widget.zones, widget.selected)),
                    ),
                  ),
                  SizedBox(
                    height: _keysHeight,
                    child: Listener(
                      onPointerDown: (e) {
                        final n = g.noteAt(e.localPosition.dx);
                        _held[e.pointer] = n;
                        widget.c.noteOn(n, velocity: 0.8, track: widget.track);
                      },
                      onPointerUp: _release,
                      onPointerCancel: _release,
                      child: CustomPaint(size: Size(g.width, _keysHeight), painter: _KeysPainter(g.noteW, widget.zones)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );

  void _release(PointerEvent e) {
    final n = _held.remove(e.pointer);
    if (n != null) widget.c.noteOff(n, track: widget.track);
  }
}

class _MapPainter extends CustomPainter {
  final ZoneMapGeometry g;
  final List<SamplerZone> zones;
  final String? selected;
  _MapPainter(this.g, this.zones, this.selected);

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = const Color(0xFF15171C);
    canvas.drawRect(Offset.zero & size, bg);
    final grid = Paint()..strokeWidth = 1;
    for (var n = 0; n < 128; n += 12) {
      grid.color = Colors.white.withValues(alpha: 0.10);
      canvas.drawLine(Offset(n * g.noteW, 0), Offset(n * g.noteW, size.height), grid);
    }
    grid.color = Colors.white.withValues(alpha: 0.05);
    for (var v = 32; v < 128; v += 32) {
      final y = (127 - v) * g.height / 127;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    for (var i = 0; i < zones.length; i++) {
      final z = zones[i];
      final r = g.rectOf(z).deflate(0.5);
      final col = zoneColor(i);
      final on = z.id == selected;
      final rr = RRect.fromRectAndRadius(r, const Radius.circular(3));
      canvas.drawRRect(rr, Paint()..color = col.withValues(alpha: on ? 0.75 : 0.5));
      canvas.drawRRect(
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = on ? 2 : 1
          ..color = on ? Colors.white : col,
      );
      // a nota base
      final rx = (z.root + 0.5) * g.noteW;
      if (rx > r.left && rx < r.right) {
        canvas.drawLine(Offset(rx, r.top + 2), Offset(rx, math.min(r.bottom - 2, r.top + 10)), Paint()..color = Colors.white.withValues(alpha: 0.9));
      }
      if (r.width >= 34 && r.height >= 14) {
        final tp = TextPainter(
          text: TextSpan(
            text: zoneNoteName(z.root),
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white),
          ),
          textDirection: TextDirection.ltr,
          maxLines: 1,
        )..layout(maxWidth: r.width - 6);
        tp.paint(canvas, Offset(r.left + 3, r.bottom - tp.height - 2));
      }
    }
  }

  @override
  bool shouldRepaint(_MapPainter o) => true;
}

/// O teclado embaixo do mapa: as notas cobertas por alguma zona ficam marcadas.
class _KeysPainter extends CustomPainter {
  final double noteW;
  final List<SamplerZone> zones;
  _KeysPainter(this.noteW, this.zones);

  @override
  void paint(Canvas canvas, Size size) {
    final covered = List<bool>.filled(128, false);
    for (final z in zones) {
      for (var n = z.lo; n <= z.hi; n++) {
        covered[n] = true;
      }
    }
    for (var n = 0; n < 128; n++) {
      final black = isBlackKey(n);
      final r = Rect.fromLTWH(n * noteW, 0, noteW, size.height * (black ? 0.62 : 1));
      canvas.drawRect(
        r.deflate(0.4),
        Paint()
          ..color = black ? (covered[n] ? const Color(0xFF6C7A99) : const Color(0xFF23262E)) : (covered[n] ? const Color(0xFFDCE3F5) : const Color(0xFFB9BCC4)),
      );
      if (n % 12 == 0) {
        final tp = TextPainter(
          text: TextSpan(
            text: 'C${n ~/ 12 - 1}',
            style: const TextStyle(fontSize: 9, color: Color(0xFF30333B), fontWeight: FontWeight.w700),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(n * noteW + 1, size.height - tp.height - 1));
      }
    }
  }

  @override
  bool shouldRepaint(_KeysPainter o) => true;
}

// ------------------------------------------------------------------------------------ a edição

class _ZoneEditor extends StatelessWidget {
  final DawController c;
  final int track;
  final SamplerZone zone;
  final Color color;
  final bool compact;
  final VoidCallback onGone, onDuplicate;

  /// Divide a zona em N camadas de velocidade.
  final void Function(int n) onLayers;
  const _ZoneEditor({
    super.key,
    required this.c,
    required this.track,
    required this.zone,
    required this.color,
    required this.compact,
    required this.onGone,
    required this.onDuplicate,
    required this.onLayers,
  });

  void _edit(void Function(SamplerZone z) fn, {bool undoable = true}) => c.editZone(track, zone.id, fn, undoable: undoable);

  Widget _slider(BuildContext context, String label, double value, double min, double max, String text, void Function(double) apply, {int? divisions}) =>
      SizedBox(
        width: compact ? double.infinity : 200,
        child: Row(
          children: [
            SizedBox(
              width: 56,
              child: Text(label, style: const TextStyle(fontSize: 11.5, color: Colors.white60)),
            ),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context)
                    .copyWith(trackHeight: 2, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6), overlayShape: SliderComponentShape.noOverlay),
                child: Slider(
                  value: value.clamp(min, max),
                  min: min,
                  max: max,
                  divisions: divisions,
                  activeColor: color,
                  onChangeStart: (_) => c.checkpoint(),
                  onChanged: apply,
                ),
              ),
            ),
            SizedBox(
              width: 52,
              child: Text(
                text,
                textAlign: TextAlign.end,
                style: const TextStyle(fontSize: 11.5, fontFeatures: [FontFeature.tabularFigures()]),
              ),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final z = zone;
    final info = c.doc.samples[z.sample];
    final samples = c.doc.samples.entries.toList()..sort((a, b) => a.value.name.toLowerCase().compareTo(b.value.name.toLowerCase()));
    final dur = info?.duration ?? 0;
    final wave = c.waveforms[z.sample];
    final has = wave != null && !c.missing.contains(z.sample);
    final end = z.end > 0 ? z.end : dur;
    final controls = <Widget>[
      _Stepper(label: 'Nota base', value: noteName(z.root), parse: parseNoteInput, hint: 'C4 ou 60', onSet: (n) => _edit((z) => z.root = n)),
      _Stepper(label: 'Notas de', value: noteName(z.lo), parse: parseNoteInput, hint: 'C4 ou 60', onSet: (n) => _edit((z) => z.lo = n)),
      _Stepper(label: 'até', value: noteName(z.hi), parse: parseNoteInput, hint: 'C4 ou 60', onSet: (n) => _edit((z) => z.hi = n)),
      _Stepper(label: 'Velocidade de', value: '${z.vlo}', parse: _parseVelocity, hint: '1 a 127', onSet: (n) => _edit((z) => z.vlo = n)),
      _Stepper(label: 'até', value: '${z.vhi}', parse: _parseVelocity, hint: '1 a 127', onSet: (n) => _edit((z) => z.vhi = n)),
      _slider(context, 'Afinação', z.cents, -100, 100, '${z.cents.round()} ct', (v) => _edit((z) => z.cents = v.roundToDouble(), undoable: false)),
      _slider(context, 'Ganho', z.gainDb, -24, 12, '${z.gainDb.toStringAsFixed(1)} dB', (v) => _edit((z) => z.gainDb = (v * 2).round() / 2, undoable: false)),
      _slider(
        context,
        'Pan',
        z.pan,
        -1,
        1,
        z.pan.abs() < 0.005 ? 'C' : '${z.pan < 0 ? 'E' : 'D'}${(z.pan.abs() * 100).round()}',
        (v) => _edit((z) => z.pan = (v * 100).round() / 100, undoable: false),
      ),
    ];
    final mode = SegmentedButton<bool>(
      showSelectedIcon: false,
      style: const ButtonStyle(visualDensity: VisualDensity(horizontal: -3, vertical: -3), textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 11.5))),
      segments: const [
        ButtonSegment(value: false, label: Text('Sustentado')),
        ButtonSegment(value: true, label: Text('Até o fim')),
      ],
      selected: {z.oneShot},
      onSelectionChanged: (s) => _edit((z) => z.oneShot = s.first),
    );
    final layers = PopupMenuButton<int>(
      tooltip: 'Divide esta zona em camadas de velocidade iguais: ela fica com a primeira e as outras são cópias para trocar o áudio',
      position: PopupMenuPosition.under,
      onSelected: (n) => onLayers(n),
      itemBuilder: (_) => [
        for (final n in const [2, 3, 4]) PopupMenuItem(value: n, height: 38, child: Text('Dividir em $n camadas iguais')),
      ],
      child: _ChipButton(icon: Icons.layers_outlined, label: 'Camadas de velocidade', color: color),
    );
    final group = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Round-robin ', style: TextStyle(fontSize: 11.5, color: Colors.white60)),
        DropdownButton<int>(
          value: z.group.clamp(0, maxZoneGroup),
          isDense: true,
          underline: const SizedBox.shrink(),
          style: const TextStyle(fontSize: 12, color: Colors.white),
          items: [for (var i = 0; i <= maxZoneGroup; i++) DropdownMenuItem(value: i, child: Text(i == 0 ? 'nenhum' : 'grupo $i'))],
          onChanged: (v) => _edit((z) => z.group = v ?? 0),
        ),
      ],
    );
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: PopupMenuButton<String>(
                  tooltip: 'Trocar o áudio da zona',
                  position: PopupMenuPosition.under,
                  constraints: const BoxConstraints(minWidth: 240, maxWidth: 360, maxHeight: 420),
                  onSelected: (h) => _edit((z) => z.sample = h),
                  itemBuilder: (_) => [
                    for (final e in samples)
                      PopupMenuItem(
                        value: e.key,
                        height: 38,
                        child: Text(e.value.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  child: Text(
                    info?.name ?? 'Áudio fora do projeto',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Duplicar a zona',
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                onPressed: onDuplicate,
                icon: const Icon(Icons.copy_outlined),
              ),
              IconButton(
                tooltip: 'Apagar a zona',
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                onPressed: () {
                  c.removeZone(track, zone.id);
                  onGone();
                },
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(spacing: 14, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: controls),
          const SizedBox(height: 6),
          Wrap(spacing: 14, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [mode, group, layers]),
          const SizedBox(height: 8),
          if (!has || dur <= 0)
            const Text(
              'Este áudio não está neste aparelho: o trecho e o loop ficam para quando ele voltar.',
              style: TextStyle(fontSize: 12, color: Colors.white54),
            )
          else ...[
            SizedBox(
              height: 52,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: CustomPaint(
                  size: Size.infinite,
                  painter: _RegionPainter(wave, dur, z.start, end, z.hasLoop ? z.loopStart : null, z.hasLoop ? z.loopEnd : null, color),
                ),
              ),
            ),
            _range(
              'Trecho',
              RangeValues(z.start.clamp(0, dur), end.clamp(0, dur)),
              dur,
              (r) => _edit((z) {
                z.start = r.start;
                // o fim no fim do áudio é "até o fim" (0)
                z.end = r.end >= dur - 1e-6 ? 0 : r.end;
              }, undoable: false),
            ),
            if (!z.oneShot) ...[
              Row(
                children: [
                  Checkbox(
                    value: z.hasLoop,
                    visualDensity: VisualDensity.compact,
                    onChanged: (on) => _edit((z) {
                      if (on ?? false) {
                        final len = math.max(end - z.start, 0);
                        z.loopStart = z.start + len * 0.25;
                        z.loopEnd = z.start + len * 0.75;
                      } else {
                        z.loopStart = z.loopEnd = 0;
                      }
                    }),
                  ),
                  const Flexible(
                    child: Text('Loop enquanto a nota está presa', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
              if (z.hasLoop)
                _range(
                  'Loop',
                  RangeValues(z.loopStart.clamp(z.start, end), z.loopEnd.clamp(z.start, end)),
                  dur,
                  (r) => _edit((z) {
                    z.loopStart = r.start;
                    z.loopEnd = r.end;
                  }, undoable: false),
                  min: z.start,
                  max: end,
                ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _range(String label, RangeValues v, double dur, void Function(RangeValues) apply, {double min = 0, double? max}) => Row(
    children: [
      SizedBox(
        width: 44,
        child: Text(label, style: const TextStyle(fontSize: 11.5, color: Colors.white60)),
      ),
      Expanded(
        child: RangeSlider(
          values: v,
          min: min,
          max: math.max(max ?? dur, min + 1e-6),
          activeColor: color,
          onChangeStart: (_) => c.checkpoint(),
          onChanged: apply,
        ),
      ),
      SizedBox(
        width: 92,
        child: Text(
          '${v.start.toStringAsFixed(3)}–${v.end.toStringAsFixed(3)} s',
          textAlign: TextAlign.end,
          style: const TextStyle(fontSize: 10.5, color: Colors.white60),
        ),
      ),
    ],
  );
}

int? _parseVelocity(String text) {
  final n = int.tryParse(text.trim());
  return n != null && n >= 1 && n <= 127 ? n : null;
}

/// Um valor inteiro com Menos/Mais de 1 em 1 e, tocando no número, digitação (o [parse] devolve null
/// para o que não entendeu: o campo volta ao valor de antes).
class _Stepper extends StatefulWidget {
  final String label, value, hint;
  final int? Function(String text) parse;
  final void Function(int n) onSet;
  const _Stepper({required this.label, required this.value, required this.parse, required this.onSet, required this.hint});

  @override
  State<_Stepper> createState() => _StepperState();
}

class _StepperState extends State<_Stepper> {
  late final TextEditingController _text = TextEditingController(text: widget.value);
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  @override
  void didUpdateWidget(_Stepper old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && _text.text != widget.value) _text.text = widget.value;
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _commit() {
    final n = widget.parse(_text.text);
    if (n != null && n != widget.parse(widget.value)) widget.onSet(n);
    // o que não valeu, ou o valor já normalizado pelo modelo, volta a aparecer na próxima montagem
    _text.text = widget.value;
  }

  /// Passo de 1 sobre o valor atual (lido do texto mostrado).
  void _bump(int d) {
    final cur = widget.parse(widget.value);
    if (cur != null) widget.onSet(cur + d);
  }

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(widget.label, style: const TextStyle(fontSize: 11.5, color: Colors.white60)),
      IconButton(
        tooltip: 'Menos',
        visualDensity: VisualDensity.compact,
        iconSize: 16,
        constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
        onPressed: () => _bump(-1),
        icon: const Icon(Icons.remove),
      ),
      SizedBox(
        width: 46,
        child: TextField(
          controller: _text,
          focusNode: _focus,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          decoration: InputDecoration(isDense: true, hintText: widget.hint, contentPadding: const EdgeInsets.symmetric(vertical: 6)),
          onSubmitted: (_) => _commit(),
        ),
      ),
      IconButton(
        tooltip: 'Mais',
        visualDensity: VisualDensity.compact,
        iconSize: 16,
        constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
        onPressed: () => _bump(1),
        icon: const Icon(Icons.add),
      ),
    ],
  );
}

/// A forma de onda do áudio com o trecho da zona claro, o resto apagado, e o loop marcado.
class _RegionPainter extends CustomPainter {
  final Waveform wave;
  final double duration, start, end;
  final double? loopStart, loopEnd;
  final Color color;
  _RegionPainter(this.wave, this.duration, this.start, this.end, this.loopStart, this.loopEnd, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF15171C));
    final n = wave.mins.length;
    if (n == 0 || size.width <= 0 || duration <= 0) return;
    var peak = 0.0;
    for (var i = 0; i < n; i++) {
      peak = math.max(peak, math.max(-wave.mins[i], wave.maxs[i]));
    }
    final mid = size.height / 2;
    final amp = (size.height / 2 - 2) / (peak > 1e-4 ? peak : 1);
    double x(double t) => (t / duration).clamp(0.0, 1.0) * size.width;
    if (loopStart != null && loopEnd != null) {
      canvas.drawRect(Rect.fromLTRB(x(loopStart!), 0, x(loopEnd!), size.height), Paint()..color = color.withValues(alpha: 0.22));
    }
    final on = Paint()..color = color.withValues(alpha: 0.95);
    final off = Paint()..color = Colors.white24;
    final cols = size.width.floor();
    for (var px = 0; px < cols; px++) {
      final a = (px * n / cols).floor();
      final b = math.max(a + 1, ((px + 1) * n / cols).floor());
      var lo = 0.0, hi = 0.0;
      for (var i = a; i < b && i < n; i++) {
        if (wave.mins[i] < lo) lo = wave.mins[i];
        if (wave.maxs[i] > hi) hi = wave.maxs[i];
      }
      final inside = px + 0.5 >= x(start) && px + 0.5 <= x(end);
      canvas.drawLine(Offset(px + 0.5, mid - hi * amp), Offset(px + 0.5, mid - lo * amp + 0.5), inside ? on : off);
    }
  }

  @override
  bool shouldRepaint(_RegionPainter o) => true;
}
