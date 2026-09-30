part of 'piano_roll.dart';

const _whiteRow = Color(0xFF15181D);
const _blackRow = Color(0xFF0F1115);
const _whiteKey = Color(0xFFC5CAD1);
const _blackKey = Color(0xFF1B1E24);

final _texts = <String, TextPainter>{};

/// Texto já medido, na fonte do tema ([font]). Rótulos que se repetem (nomes de nota, números de
/// compasso) ficam guardados: medir texto a cada quadro de rolagem pesa mais do que pintar as notas.
TextPainter _text(TextStyle font, String s, double size, Color color, {bool bold = false, double maxWidth = double.infinity, bool cache = true}) {
  TextPainter make() => TextPainter(
    text: TextSpan(
      text: s,
      style: font.copyWith(fontSize: size, color: color, fontWeight: bold ? FontWeight.w700 : FontWeight.w500, height: 1.15, letterSpacing: 0),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 1,
    ellipsis: '…',
  )..layout(maxWidth: maxWidth);
  if (!cache) return make();
  if (_texts.length > 800) {
    for (final t in _texts.values) {
      t.dispose();
    }
    _texts.clear();
  }
  return _texts.putIfAbsent('${font.fontFamily}|$s|$size|${color.toARGB32()}|$bold|$maxWidth', make);
}

/// Um compasso visível na grade ou na régua: onde começa (em batidas do clipe), quanto dura, o número
/// e as batidas dele (a unidade do compasso, `MeterChange.unit` = 4/denominador: 1 num n/4, 0,5 num 6/8 ou 7/8).
class _Bar {
  final double start, len, unit;
  final int number;
  const _Bar(this.start, this.len, this.unit, this.number);
}

/// Os compassos que cruzam [x0, x1] (batidas do clipe). Sem mapa de compassos (só `n/4`) eles contam do
/// começo do clipe, como a grade de encaixe, e os números seguem os do arranjo quando o clipe começa num
/// compasso; com mapa (6/8, mudanças), são os compassos do arranjo.
List<_Bar> _barsIn(MeterMap? meter, double clipStart, int bpb, double x0, double x1) {
  final out = <_Bar>[];
  if (meter == null || meter.isSingle) {
    final len = bpb.toDouble();
    final off = clipStart / len;
    final aligned = _near(off);
    for (var b = (x0 / len).floor(); b <= (x1 / len).ceil(); b++) {
      out.add(_Bar(b * len, len, 1, aligned ? off.round() + b + 1 : b + 1));
    }
    return out;
  }
  var (bar, _) = meter.barOf(math.max(0.0, clipStart + x0));
  for (var n = 0; n < 4096; n++, bar++) {
    final s = meter.barStart(bar) - clipStart;
    if (s > x1) break;
    out.add(_Bar(s, meter.barBeats(bar), meter.changeAt(bar).unit, bar));
  }
  return out;
}

/// Linhas das teclas (pretas sombreadas), compassos alternados e as linhas de compasso, tempo e
/// subdivisão da grade, que somem quando ficariam apertadas demais.
class _GridPainter extends CustomPainter {
  final _Geo g;
  final bool drums;
  final int bpb;
  final MeterMap? meter;
  final double clipStart, step;

  /// Escala do clipe: as linhas dela ficam realçadas (a tônica mais) e as de fora, escurecidas.
  final ClipScale? scale;
  _GridPainter({required this.g, required this.drums, required this.bpb, this.meter, this.clipStart = 0, required this.step, this.scale});

  @override
  void paint(Canvas canvas, Size size) {
    final rows = g.rows;
    canvas.drawRect(Offset.zero & size, Paint()..color = Palette.ink);
    final bottom = math.min(size.height, g.bottom);
    if (bottom <= 0) return;
    final r0 = math.max(0, (g.scrollY / g.rowH).floor());
    final r1 = math.min(rows.length - 1, ((g.scrollY + size.height) / g.rowH).floor());
    final white = Paint()..color = _whiteRow;
    final black = Paint()..color = _blackRow;
    final thin = Paint()..color = drums ? const Color(0x12FFFFFF) : const Color(0x0AFFFFFF);
    final octave = Paint()..color = const Color(0x24FFFFFF);
    final inKey = Paint()..color = Palette.accent.withValues(alpha: .10);
    final tonic = Paint()..color = Palette.accent.withValues(alpha: .22);
    final outKey = Paint()..color = const Color(0x4D000000);
    final sc = drums ? null : scale;
    for (var r = r0; r <= r1; r++) {
      final p = rows.pitches[r], y = g.y(r);
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, g.rowH), (drums ? r.isOdd : isBlackKey(p)) ? black : white);
      if (sc != null) canvas.drawRect(Rect.fromLTWH(0, y, size.width, g.rowH), sc.isRoot(p) ? tonic : (sc.contains(p) ? inKey : outKey));
      // divisa embaixo da linha: marcada entre oitavas (abaixo do C), discreta nas outras
      final strong = !drums && p % 12 == 0;
      if (strong || g.rowH >= 7) canvas.drawRect(Rect.fromLTWH(0, (y + g.rowH).roundToDouble() - 1, size.width, 1), strong ? octave : thin);
    }

    final x0 = g.scrollX, x1 = g.beatAt(size.width);
    final bars = _barsIn(meter, clipStart, bpb, x0, x1);
    final alt = Paint()..color = const Color(0x06FFFFFF);
    for (final b in bars) {
      if (b.number.isEven) canvas.drawRect(Rect.fromLTWH(g.x(b.start), 0, b.len * g.ppb, bottom), alt);
    }

    final barLine = Paint()..color = const Color(0x33FFFFFF);
    final beatLine = Paint()..color = const Color(0x16FFFFFF);
    final subLine = Paint()..color = const Color(0x09FFFFFF);
    final barBeats = bars.isEmpty ? bpb.toDouble() : bars.first.len;
    final every = _barStep(barBeats * g.ppb, 24);
    // as linhas de tempo e de subdivisão andam em passos fixos a partir do começo do clipe; as de
    // compasso vêm do mapa e por cima (num 7/8 o compasso cai no meio de um tempo)
    bool atBar(double beat) => bars.any((b) => (b.start - beat).abs() < 1e-6);
    void line(double beat) {
      if (atBar(beat)) return;
      canvas.drawRect(Rect.fromLTWH(g.x(beat).roundToDouble(), 0, 1, bottom), _near(beat) ? beatLine : subLine);
    }

    final sub = step > 0 ? step : .25;
    final unit = sub * g.ppb >= 7 ? sub : (g.ppb >= 7 ? 1.0 : barBeats);
    for (var k = (x0 / unit).floor(); k <= (x1 / unit).ceil(); k++) {
      line(k * unit);
    }
    for (final b in bars) {
      canvas.drawRect(Rect.fromLTWH(g.x(b.start).roundToDouble(), 0, 1, bottom), (b.number - 1) % every == 0 ? barLine : beatLine);
    }
  }

  @override
  bool shouldRepaint(_GridPainter o) =>
      !g.same(o.g) ||
      drums != o.drums ||
      bpb != o.bpb ||
      !identical(meter, o.meter) ||
      clipStart != o.clipStart ||
      step != o.step ||
      scale?.encode() != o.scale?.encode();
}

/// As notas, o que fica fora do clipe (escurecido), o fim do clipe, o retângulo de seleção e a
/// leitura do arraste. Só o que está na tela é pintado.
class _NotesPainter extends CustomPainter {
  final _Geo g;
  final List<MidiNote> notes;

  /// Notas de outros clipes, em cinza e sem edição: cada lista com o deslocamento que leva o tempo
  /// do clipe dela ao deste.
  final List<(double, List<MidiNote>)> ghosts;
  final Set<MidiNote> sel;
  final MidiNote? hover;
  final List<Color> colors;
  final Color accent;
  final double clipLength;
  final bool drums;

  /// Retângulo de seleção em batidas × linhas.
  final Rect? marquee;
  final String? label;

  /// Onde a leitura aparece: batida e linha (null = no alto da tela).
  final (double, int?)? labelAt;
  final TextStyle font;

  _NotesPainter({
    required this.g,
    required this.notes,
    this.ghosts = const [],
    required this.sel,
    required this.hover,
    required this.colors,
    required this.accent,
    required this.clipLength,
    required this.drums,
    required this.marquee,
    required this.label,
    required this.labelAt,
    required this.font,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final x0 = g.scrollX, x1 = g.beatAt(size.width);
    final fill = Paint();
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0x73000000);
    final selEdge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Colors.white;
    final radius = Radius.circular(math.min(3.0, g.rowH / 4));
    final text = g.rowH >= 12;
    if (ghosts.isNotEmpty) {
      final ghost = Paint()..color = const Color(0x2EFFFFFF);
      for (final (shift, list) in ghosts) {
        for (final n in list) {
          final start = n.start + shift;
          if (start + n.length < x0 || start > x1) continue;
          final row = g.rows.rowOf(n.pitch);
          if (row == null) continue;
          final y = g.y(row);
          if (y + g.rowH < 0 || y > size.height) continue;
          canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(g.x(start) + .5, y + 1, math.max(3.0, n.length * g.ppb) - 1, g.rowH - 2), radius), ghost);
        }
      }
    }
    for (final selectedPass in const [false, true]) {
      if (selectedPass && sel.isEmpty) break;
      for (final n in notes) {
        if (n.end < x0 || n.start > x1) continue;
        final selected = sel.contains(n);
        if (selected != selectedPass) continue;
        final row = g.rows.rowOf(n.pitch);
        if (row == null) continue;
        final y = g.y(row);
        if (y + g.rowH < 0 || y > size.height) continue;
        final x = g.x(n.start);
        final w = math.max(3.0, n.length * g.ppb);
        final r = RRect.fromRectAndRadius(Rect.fromLTWH(x + .5, y + 1, w - 1, g.rowH - 2), radius);
        var color = _velColor(colors, n.velocity);
        if (selected) {
          color = Color.lerp(color, Colors.white, .12)!;
        } else if (identical(n, hover)) {
          color = Color.lerp(color, Colors.white, .2)!;
        }
        fill.color = color;
        canvas.drawRRect(r, fill);
        canvas.drawRRect(r.deflate(selected ? .75 : .5), selected ? selEdge : edge);
        if (text && w > 26 && !drums) {
          // texto escuro nas notas claras (fortes), claro nas escuras
          final tp = _text(font, noteName(n.pitch), 10, n.velocity > .62 ? const Color(0xCC000000) : const Color(0xD9FFFFFF));
          if (tp.width < w - 6) tp.paint(canvas, Offset(x + 4, y + (g.rowH - tp.height) / 2));
        }
      }
    }

    // o que fica antes do início ou depois do fim do clipe não toca
    final shade = Paint()..color = const Color(0x8C000000);
    final xs = g.x(0), xe = g.x(clipLength);
    if (xs > 0) canvas.drawRect(Rect.fromLTRB(0, 0, math.min(xs, size.width), size.height), shade);
    if (xe < size.width) canvas.drawRect(Rect.fromLTRB(math.max(0, xe), 0, size.width, size.height), shade);
    if (xe > -2 && xe < size.width + 2) canvas.drawRect(Rect.fromLTWH(xe.roundToDouble() - 1, 0, 2, size.height), Paint()..color = accent);

    final m = marquee;
    if (m != null) {
      final r = Rect.fromLTRB(g.x(m.left), m.top * g.rowH - g.scrollY, g.x(m.right), m.bottom * g.rowH - g.scrollY);
      canvas.drawRect(r, Paint()..color = Palette.accent.withValues(alpha: .1));
      canvas.drawRect(
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = Palette.accent.withValues(alpha: .7),
      );
    }

    final l = label, at = labelAt;
    if (l != null && at != null) {
      final tp = _text(font, l, 11, Colors.white, bold: true, cache: false);
      final (beat, row) = at;
      var y = row == null ? 4.0 : g.y(row) - tp.height - 10;
      // sem espaço em cima da nota, vai para baixo dela
      if (y < 2 && row != null) y = g.y(row) + g.rowH + 4;
      final x = g.x(beat).clamp(2.0, math.max<double>(2, size.width - tp.width - 14));
      final box = RRect.fromRectAndRadius(Rect.fromLTWH(x, y, tp.width + 10, tp.height + 6), const Radius.circular(4));
      canvas.drawRRect(box, Paint()..color = const Color(0xEE242932));
      canvas.drawRRect(
        box,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = Palette.hairlineStrong,
      );
      tp.paint(canvas, Offset(x + 5, y + 3));
      tp.dispose();
    }
  }

  // as notas mudam no lugar (os objetos são os mesmos): repinta a cada build, que só acontece
  // quando algo mudou
  @override
  bool shouldRepaint(_NotesPainter o) => true;
}

/// O teclado à esquerda (ou os nomes das peças, na bateria), com a tecla tocando acesa.
class _KeysPainter extends CustomPainter {
  final _Geo g;
  final bool drums;
  final Set<int> pressed;
  final Color accent;
  final TextStyle font;

  /// Escala do clipe: uma marca nas teclas dela (maior na tônica).
  final ClipScale? scale;
  _KeysPainter({required this.g, required this.drums, required this.pressed, required this.accent, required this.font, this.scale});

  @override
  void paint(Canvas canvas, Size size) {
    final rows = g.rows;
    final w = size.width;
    final r0 = math.max(0, (g.scrollY / g.rowH).floor());
    final r1 = math.min(rows.length - 1, ((g.scrollY + size.height) / g.rowH).floor());
    canvas.drawRect(Offset.zero & size, Paint()..color = drums ? Palette.bar : Palette.ink);
    if (drums) {
      final odd = Paint()..color = Palette.raised;
      final line = Paint()..color = const Color(0x14FFFFFF);
      final on = Paint()..color = accent.withValues(alpha: .28);
      final bar = Paint()..color = accent;
      for (var r = r0; r <= r1; r++) {
        final p = rows.pitches[r], y = g.y(r);
        if (r.isOdd) canvas.drawRect(Rect.fromLTWH(0, y, w, g.rowH), odd);
        if (pressed.contains(p)) {
          canvas.drawRect(Rect.fromLTWH(0, y, w, g.rowH), on);
          canvas.drawRect(Rect.fromLTWH(0, y, 3, g.rowH), bar);
        }
        if (g.rowH >= 11) {
          // peça do kit em branco; nota vizinha que aciona uma peça, apagada; sem peça, mais ainda
          final (label, kind) = _drumLabel(p);
          final color = switch (kind) {
            _DrumRow.piece => const Color(0xE6FFFFFF),
            _DrumRow.alias => Colors.white60,
            _DrumRow.silent => Colors.white38,
          };
          final note = _text(font, noteName(p), 9, Colors.white38);
          final name = _text(font, label, g.rowH >= 20 ? 12 : 10, color, maxWidth: w - note.width - 20);
          name.paint(canvas, Offset(8, y + (g.rowH - name.height) / 2));
          note.paint(canvas, Offset(w - note.width - 6, y + (g.rowH - note.height) / 2));
        }
        canvas.drawRect(Rect.fromLTWH(0, (y + g.rowH).roundToDouble() - 1, w, 1), line);
      }
    } else {
      final top = math.max(0.0, g.y(0)), bottom = math.min(size.height, g.bottom);
      canvas.drawRect(Rect.fromLTRB(0, top, w, bottom), Paint()..color = _whiteKey);
      final blackW = (w * .6).roundToDouble();
      final edge = Paint()..color = const Color(0x40000000);
      final black = Paint()..color = _blackKey;
      final blackOn = Paint()..color = Color.lerp(_blackKey, accent, .75)!;
      final whiteOn = Paint()..color = accent;
      for (var r = r0; r <= r1; r++) {
        final p = rows.pitches[r], y = g.y(r);
        final on = pressed.contains(p);
        if (isBlackKey(p)) {
          canvas.drawRect(Rect.fromLTWH(0, y, blackW, g.rowH), on ? blackOn : black);
          // a divisa entre as duas brancas vizinhas passa no meio da preta
          canvas.drawRect(Rect.fromLTWH(blackW, (y + g.rowH / 2).roundToDouble(), w - blackW, 1), edge);
        } else {
          if (on) canvas.drawRect(Rect.fromLTWH(0, y, w, g.rowH), whiteOn);
          // C e F têm outra branca logo abaixo (B e E): a divisa é a borda da linha
          if (p % 12 == 0 || p % 12 == 5) canvas.drawRect(Rect.fromLTWH(0, (y + g.rowH).roundToDouble() - 1, w, 1), edge);
          if (p % 12 == 0 && g.rowH >= 9) {
            final tp = _text(font, noteName(p), math.min(10.0, g.rowH - 2), p == 60 ? const Color(0xFF16191E) : const Color(0xFF4A5059), bold: p == 60);
            tp.paint(canvas, Offset(w - tp.width - 4, y + (g.rowH - tp.height) / 2));
          }
        }
        if (scale != null && scale!.contains(p) && g.rowH >= 6) {
          final root = scale!.isRoot(p);
          canvas.drawCircle(
            Offset(6, y + g.rowH / 2),
            math.min(root ? 3.0 : 2.0, g.rowH / 3),
            Paint()..color = Palette.accent.withValues(alpha: root ? 1 : .7),
          );
        }
      }
    }
    canvas.drawRect(Rect.fromLTWH(w - 1, 0, 1, size.height), Paint()..color = Palette.hairlineStrong);
  }

  @override
  bool shouldRepaint(_KeysPainter o) =>
      !g.same(o.g) || drums != o.drums || accent != o.accent || font != o.font || !setEquals(pressed, o.pressed) || scale?.encode() != o.scale?.encode();
}

/// Régua: números de compasso, marcas de tempo e subdivisão, e a alça do fim do clipe.
class _RulerPainter extends CustomPainter {
  final _Geo g;
  final int bpb;
  final MeterMap? meter;
  final double clipStart, clipLength, step;
  final Color accent;
  final TextStyle font;
  _RulerPainter({
    required this.g,
    required this.bpb,
    this.meter,
    required this.clipStart,
    required this.clipLength,
    required this.step,
    required this.accent,
    required this.font,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Palette.bar);
    final shade = Paint()..color = const Color(0x59000000);
    final xs = g.x(0), xe = g.x(clipLength);
    if (xs > 0) canvas.drawRect(Rect.fromLTRB(0, 0, xs, size.height), shade);
    if (xe < size.width) canvas.drawRect(Rect.fromLTRB(math.max(0, xe), 0, size.width, size.height), shade);

    // o clipe começando num compasso do arranjo, os números seguem os do arranjo
    final tick = Paint()..color = Colors.white24;
    final faint = Paint()..color = Colors.white12;
    final sub = step > 0 ? step : .25;
    final h = size.height;
    final bars = _barsIn(meter, clipStart, bpb, math.max(0.0, g.scrollX), g.beatAt(size.width));
    final every = _barStep((bars.isEmpty ? bpb.toDouble() : bars.first.len) * g.ppb, 40);
    for (final bar in bars) {
      if (bar.start < -1e-9 && (meter == null || meter!.isSingle)) continue;
      final x = g.x(bar.start).roundToDouble();
      if ((bar.number - 1) % every == 0) {
        canvas.drawRect(Rect.fromLTWH(x, 6, 1, h - 6), tick);
        final tp = _text(font, '${bar.number}', 11, Colors.white70);
        tp.paint(canvas, Offset(x + 4, 3));
      } else {
        canvas.drawRect(Rect.fromLTWH(x, h - 8, 1, 8), faint);
      }
      if (g.ppb >= 10) {
        // um risco por tempo do compasso (a unidade dele: 0,5 batida, uma colcheia, num 6/8)
        for (var t = bar.unit; t < bar.len - 1e-6; t += bar.unit) {
          canvas.drawRect(Rect.fromLTWH((x + t * g.ppb).roundToDouble(), h - 6, 1, 6), faint);
        }
      }
      if (sub * g.ppb >= 9 && sub < 1) {
        final n = (bar.len / sub).round();
        for (var i = 1; i < n; i++) {
          final beat = i * sub;
          if (_near(beat)) continue;
          canvas.drawRect(Rect.fromLTWH((x + beat * g.ppb).roundToDouble(), h - 3, 1, 3), faint);
        }
      }
    }

    // alça do fim do clipe: uma bandeira apontando para dentro
    if (xe > -12 && xe < size.width + 12) {
      final p = Paint()..color = accent;
      canvas.drawRect(Rect.fromLTWH(xe.roundToDouble() - 2, 0, 2, h), p);
      canvas.drawPath(
        Path()
          ..moveTo(xe, 0)
          ..lineTo(xe - 11, 0)
          ..lineTo(xe - 11, 7)
          ..lineTo(xe, 14)
          ..close(),
        p,
      );
    }
    canvas.drawRect(Rect.fromLTWH(0, h - 1, size.width, 1), Paint()..color = Palette.hairline);
  }

  @override
  bool shouldRepaint(_RulerPainter o) =>
      !g.same(o.g) ||
      bpb != o.bpb ||
      !identical(meter, o.meter) ||
      clipStart != o.clipStart ||
      clipLength != o.clipLength ||
      step != o.step ||
      accent != o.accent ||
      font != o.font;
}

/// Faixa de velocidade: um pirulito por nota (haste no início, cabeça na altura da velocidade e
/// um rastro pela duração).
class _VelocityPainter extends CustomPainter {
  final _Geo g;
  final List<MidiNote> notes;
  final Set<MidiNote> sel;
  final List<Color> colors;
  final double clipLength;
  final MidiNote? labelNote;
  final TextStyle font;
  _VelocityPainter({
    required this.g,
    required this.notes,
    required this.sel,
    required this.colors,
    required this.clipLength,
    required this.labelNote,
    required this.font,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    canvas.drawRect(Offset.zero & size, Paint()..color = Palette.canvas);
    final guide = Paint()..color = const Color(0x0BFFFFFF);
    for (final v in const [.25, .5, .75, 1.0]) {
      canvas.drawRect(Rect.fromLTWH(0, _velY(v, h).roundToDouble(), size.width, 1), guide);
    }
    final x0 = g.scrollX, x1 = g.beatAt(size.width);
    final stem = Paint();
    final cap = Paint();
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final selectedPass in const [false, true]) {
      if (selectedPass && sel.isEmpty) break;
      for (final n in notes) {
        if (n.end < x0 || n.start > x1) continue;
        final selected = sel.contains(n);
        if (selected != selectedPass) continue;
        final x = g.x(n.start).roundToDouble();
        final top = _velY(n.velocity, h);
        final color = _velColor(colors, n.velocity);
        stem.color = selected ? Colors.white.withValues(alpha: .85) : color.withValues(alpha: .9);
        canvas.drawRect(Rect.fromLTRB(x, top, x + 2, h), stem);
        final len = n.length * g.ppb;
        if (len > 8) {
          canvas.drawRect(Rect.fromLTWH(x + 2, top - .5, len - 4, 1), Paint()..color = (selected ? Colors.white : color).withValues(alpha: .35));
        }
        if (selected) {
          cap.color = Colors.white;
          ring.color = color;
          canvas.drawCircle(Offset(x + 1, top), 4, cap);
          canvas.drawCircle(Offset(x + 1, top), 4, ring);
        } else {
          cap.color = color;
          canvas.drawCircle(Offset(x + 1, top), 3.5, cap);
        }
      }
    }
    final shade = Paint()..color = const Color(0x8C000000);
    final xs = g.x(0), xe = g.x(clipLength);
    if (xs > 0) canvas.drawRect(Rect.fromLTRB(0, 0, xs, h), shade);
    if (xe < size.width) canvas.drawRect(Rect.fromLTRB(math.max(0, xe), 0, size.width, h), shade);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, 1), Paint()..color = Palette.hairlineStrong);

    final n = labelNote;
    if (n != null) {
      final tp = _text(font, '${(n.velocity * 127).round()}', 11, Colors.white, bold: true, cache: false);
      final top = _velY(n.velocity, h);
      final x = (g.x(n.start) + 8).clamp(2.0, math.max<double>(2, size.width - tp.width - 12));
      final y = (top - tp.height / 2 - 3).clamp(2.0, math.max<double>(2, h - tp.height - 8));
      final box = RRect.fromRectAndRadius(Rect.fromLTWH(x, y, tp.width + 8, tp.height + 4), const Radius.circular(4));
      canvas.drawRRect(box, Paint()..color = const Color(0xEE242932));
      tp.paint(canvas, Offset(x + 4, y + 2));
      tp.dispose();
    }
  }

  @override
  bool shouldRepaint(_VelocityPainter o) => true;
}

/// O cursor de reprodução por cima de régua, grade e velocidade. Escuta a posição direto do
/// motor: repinta sozinho, sem reconstruir o editor.
class _PlayheadPainter extends CustomPainter {
  final ValueListenable<double> beat;
  final double clipStart, scrollX, ppb, ruler;
  _PlayheadPainter({required this.beat, required this.clipStart, required this.scrollX, required this.ppb, required this.ruler}) : super(repaint: beat);

  @override
  void paint(Canvas canvas, Size size) {
    final x = (beat.value - clipStart - scrollX) * ppb;
    if (x < -6 || x > size.width + 6) return;
    final p = Paint()..color = Colors.white;
    canvas.drawRect(Rect.fromLTWH(x - .5, 0, 1, size.height), p);
    canvas.drawPath(
      Path()
        ..moveTo(x - 6, 0)
        ..lineTo(x + 6, 0)
        ..lineTo(x, math.min(8.0, ruler / 2))
        ..close(),
      p,
    );
  }

  @override
  bool shouldRepaint(_PlayheadPainter o) => o.beat != beat || o.clipStart != clipStart || o.scrollX != scrollX || o.ppb != ppb || o.ruler != ruler;
}

/// Barra de rolagem fina por cima da grade. Só o polegar recebe o ponteiro: clicar fora dele
/// continua sendo clicar na grade.
class _Scrollbar extends StatefulWidget {
  final Axis axis;

  /// Tamanho visível, tamanho total e posição, na mesma unidade.
  final double viewport, content, position;
  final ValueChanged<double> onChanged;
  const _Scrollbar({required this.axis, required this.viewport, required this.content, required this.position, required this.onChanged});

  @override
  State<_Scrollbar> createState() => _ScrollbarState();
}

class _ScrollbarState extends State<_Scrollbar> {
  bool _hover = false, _dragging = false;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final vertical = widget.axis == Axis.vertical;
      final track = vertical ? box.maxHeight : box.maxWidth;
      final range = widget.content - widget.viewport;
      if (range <= 1e-6 || track <= 0 || widget.content <= 0) return const SizedBox();
      final len = math.max(28.0, track * widget.viewport / widget.content).clamp(0.0, track);
      final free = math.max(1.0, track - len);
      final at = (widget.position / range).clamp(0.0, 1.0) * (track - len);
      void drag(double delta) => widget.onChanged(widget.position + delta * range / free);
      final lit = _hover || _dragging;
      final thumb = MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragStart: vertical ? (_) => setState(() => _dragging = true) : null,
          onVerticalDragUpdate: vertical ? (d) => drag(d.delta.dy) : null,
          onVerticalDragEnd: vertical ? (_) => setState(() => _dragging = false) : null,
          onHorizontalDragStart: vertical ? null : (_) => setState(() => _dragging = true),
          onHorizontalDragUpdate: vertical ? null : (d) => drag(d.delta.dx),
          onHorizontalDragEnd: vertical ? null : (_) => setState(() => _dragging = false),
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: lit ? .34 : .16),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ),
      );
      return Stack(
        children: [
          vertical ? Positioned(top: at, height: len, left: 0, right: 0, child: thumb) : Positioned(left: at, width: len, top: 0, bottom: 0, child: thumb),
        ],
      );
    },
  );
}
