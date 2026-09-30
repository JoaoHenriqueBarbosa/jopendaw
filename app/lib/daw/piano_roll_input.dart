part of 'piano_roll.dart';

enum _Area { grid, keys, ruler, velocity }

enum _Zone { body, start, end }

enum _Op { pending, draw, move, resizeEnd, resizeStart, rect, erase, clipEnd, pan, seek, velocity, velocityPaint }

class _Hit {
  final MidiNote note;
  final _Zone zone;
  const _Hit(this.note, this.zone);
}

/// Estado de uma nota no começo do arraste: cada passo parte dele (o encaixe não acumula erro) e,
/// no fim, dá para saber se algo mudou de fato.
class _Orig {
  final double start, length, velocity;
  final int pitch;
  _Orig(MidiNote n) : start = n.start, length = n.length, velocity = n.velocity, pitch = n.pitch;

  bool same(MidiNote n) => n.start == start && n.length == length && n.velocity == velocity && n.pitch == pitch;
}

/// Um gesto de um ponteiro, do toque ao soltar.
class _Drag {
  _Drag({required this.pointer, required this.touch, required this.down, required this.downBeat, required this.downRow}) : last = down;

  _Op op = _Op.pending;
  final int pointer;
  final bool touch;

  /// Onde desceu, na tela e no conteúdo (batida e linha, que não mudam com a rolagem).
  final Offset down;
  final double downBeat, downRow;
  Offset last;

  /// Passou da folga de movimento (antes disso é um clique).
  bool started = false;
  bool checkpointed = false;

  /// Criou ou apagou notas: o checkpoint nunca está vazio.
  bool structural = false;
  bool duplicate = false;
  bool additive = false;
  MidiNote? anchor, deselectOnUp, soleOnUp;

  /// Ao desenhar com o acorde no clique: todas as notas do acorde (a duração vale para todas).
  List<MidiNote> mates = const [];

  /// No toque, o que estava sob o dedo ao descer (a decisão espera o dedo mexer ou soltar).
  _Hit? hit;
  Map<MidiNote, _Orig> orig = const {};
  Set<MidiNote> base = const {};
  Rect? marquee;
  int? sounding;
  double origLength = 0, lastX = 0, lastY = 0;
  Timer? longPress;
}

/// Pinça de dois dedos: o ponto do conteúdo sob o centro dos dedos fica sob ele.
class _Pinch {
  final double spanX, spanY, ppb, rowH, beat, row;
  const _Pinch({required this.spanX, required this.spanY, required this.ppb, required this.rowH, required this.beat, required this.row});
}

extension _Input on _PianoRollState {
  _Geo get _g => _Geo(_view!, _rows!);

  double get _step => _Prefs.grid.beats;

  /// Passo para durações e setas; com a grade livre, 1/16.
  double get _unit => _step > 0 ? _step : .25;

  /// Alt segurado desliga o encaixe durante o arraste.
  bool get _snapOff => _step <= 0 || HardwareKeyboard.instance.isAltPressed;

  double _snapRound(double b) => _snapOff ? b : _tidy((b / _step).round() * _step);
  double _snapFloor(double b) => _snapOff ? b : _tidy((b / _step + 1e-9).floor() * _step);
  double _snapCeil(double b) => _snapOff ? b : _tidy((b / _step - 1e-9).ceil() * _step);

  /// Batidas do compasso que vale no ponto [rel] (relativo ao começo do clipe), pelo mapa de compassos.
  double _barLen(double rel) => c.doc.meter.barBeatsAt(math.max(0.0, (_clip?.start ?? 0) + rel));

  /// Próximo começo de compasso a partir de [rel] (a própria posição, se já é um começo). Sem mudança
  /// de compasso conta do começo do clipe, como a grade; com mapa, pelos compassos do arranjo.
  double _ceilBar(double rel) {
    final m = c.doc.meter;
    if (m.isSingle) {
      final bar = c.doc.beatsPerBar.toDouble();
      return _tidy((rel / bar - 1e-9).ceil() * bar);
    }
    final start = _clip?.start ?? 0;
    return _tidy(m.ceilBarStart(math.max(0.0, start + rel)) - start);
  }

  double get _newLength {
    final l = _lengths[_Prefs.length].beats;
    if (l > 0) return l;
    if (l < 0) return _Prefs.lastLength;
    return _unit;
  }

  String _pitchLabel(int pitch) {
    if (!_dims.drums) return noteName(pitch);
    final (label, kind) = _drumLabel(pitch);
    return kind == _DrumRow.piece ? label : '$label (${noteName(pitch)})';
  }

  // ------------------------------------------------------------------ visão

  (double, double) _xRange() {
    final clip = _clip!;
    var lo = 0.0, hi = clip.length;
    for (final n in clip.notes) {
      if (n.start < lo) lo = n.start;
      if (n.end > hi) hi = n.end;
    }
    // espaço depois do fim para esticar o clipe ou escrever além dele
    return (lo, hi + _barLen(hi) * 2);
  }

  void _clampView() {
    final v = _view, rows = _rows;
    if (v == null || rows == null || _clip == null) return;
    v.ppb = v.ppb.clamp(6.0, 1600.0);
    v.rowH = v.rowH.clamp(_dims.rowMin, _dims.rowMax);
    v.scrollY = v.scrollY.clamp(0.0, math.max(0.0, rows.length * v.rowH - _gridSize.height));
    final (lo, hi) = _xRange();
    v.scrollX = v.scrollX.clamp(lo, math.max(lo, hi - _gridSize.width / v.ppb));
  }

  /// Enquadra o clipe (e as notas fora dele) na largura e centraliza as notas na altura. Ao abrir
  /// mantém a altura das linhas; o botão Enquadrar também ajusta a altura para caber tudo.
  void _fit({bool open = false}) {
    final clip = _clip, v = _view, rows = _rows;
    final s = _gridSize;
    if (clip == null || v == null || rows == null || s.width <= 0 || s.height <= 0) return;
    var s0 = 0.0, s1 = clip.length;
    int? r0, r1;
    for (final n in clip.notes) {
      s0 = math.min(s0, n.start);
      s1 = math.max(s1, n.end);
      final r = rows.rowOf(n.pitch);
      if (r == null) continue;
      r0 = math.min(r0 ?? r, r);
      r1 = math.max(r1 ?? r, r);
    }
    if (s1 - s0 <= 0) s1 = s0 + _barLen(0);
    // clipe comprido não vira um risco: no toque uma semicolcheia continua do tamanho de um dedo
    v.ppb = ((s.width - 16) / (s1 - s0)).clamp(_dims.coarse ? 64.0 : 24.0, 320.0);
    v.scrollX = s0;
    if (r0 == null || r1 == null) {
      if (rows.drums) {
        // clipe de bateria vazio abre embaixo: bumbo, caixa e chimbais (as notas graves) à vista
        if (!open) v.rowH = (s.height / (rows.length + 1)).clamp(_dims.rowMin, _dims.rowMax);
        v.scrollY = rows.length * v.rowH - s.height;
        _clampView();
        return;
      } else {
        r0 = r1 = rows.rowOf(60) ?? rows.length ~/ 2;
      }
    }
    if (!open) v.rowH = (s.height / (r1 - r0 + 3)).clamp(_dims.rowMin, _dims.rowMax);
    v.scrollY = (r0 + r1 + 1) / 2 * v.rowH - s.height / 2;
    _clampView();
  }

  /// Rola até as notas, se estão fora da tela.
  void _reveal(Iterable<MidiNote> notes) {
    final v = _view, rows = _rows;
    if (v == null || rows == null || notes.isEmpty) return;
    var s0 = double.infinity;
    var r0 = rows.length, r1 = -1;
    for (final n in notes) {
      s0 = math.min(s0, n.start);
      final r = rows.rowOf(n.pitch);
      if (r == null) continue;
      r0 = math.min(r0, r);
      r1 = math.max(r1, r);
    }
    final visible = _gridSize.width / v.ppb;
    if (s0 < v.scrollX || s0 > v.scrollX + visible * .9) v.scrollX = s0 - visible * .1;
    if (r1 >= 0) {
      final top = r0 * v.rowH, bottom = (r1 + 1) * v.rowH;
      if (top < v.scrollY) {
        v.scrollY = top - v.rowH;
      } else if (bottom > v.scrollY + _gridSize.height) {
        v.scrollY = bottom - _gridSize.height + v.rowH;
      }
    }
    _clampView();
  }

  void _scrollBy(double dx, double dy) {
    final v = _view;
    if (v == null) return;
    v.scrollX += dx / v.ppb;
    v.scrollY += dy;
    _clampView();
    _refresh();
  }

  void _zoomX(double factor, double anchorX) {
    final v = _view;
    if (v == null || _rows == null) return;
    final beat = _g.beatAt(anchorX);
    v.ppb = (v.ppb * factor).clamp(6.0, 1600.0);
    v.scrollX = beat - anchorX / v.ppb;
    _clampView();
    _refresh();
  }

  void _zoomY(double factor, double anchorY) {
    final v = _view;
    if (v == null || _rows == null) return;
    final row = _g.rowAtF(anchorY);
    v.rowH = (v.rowH * factor).clamp(_dims.rowMin, _dims.rowMax);
    v.scrollY = row * v.rowH - anchorY;
    _clampView();
    _refresh();
  }

  void _onSignal(PointerSignalEvent e, _Area area) {
    if (_clip == null) return;
    if (e is PointerScrollEvent) {
      GestureBinding.instance.pointerSignalResolver.register(e, (ev) => _wheel(ev as PointerScrollEvent, area));
    } else if (e is PointerScaleEvent) {
      GestureBinding.instance.pointerSignalResolver.register(e, (ev) {
        final s = ev as PointerScaleEvent;
        if (area == _Area.keys) {
          _zoomY(s.scale, s.localPosition.dy);
        } else {
          _zoomX(s.scale, s.localPosition.dx);
        }
      });
    }
  }

  /// Roda: rola na vertical (na régua e na velocidade, na horizontal); Shift rola na horizontal,
  /// Ctrl/Cmd dá zoom horizontal no ponteiro e Alt muda a altura das linhas.
  void _wheel(PointerScrollEvent e, _Area area) {
    final keys = HardwareKeyboard.instance;
    final dx = e.scrollDelta.dx, dy = e.scrollDelta.dy;
    final main = dy != 0 ? dy : dx;
    final factor = math.pow(1.0015, -main).toDouble();
    if (keys.isControlPressed || keys.isMetaPressed) {
      if (area == _Area.keys) {
        _zoomY(factor, e.localPosition.dy);
      } else {
        _zoomX(factor, e.localPosition.dx);
      }
    } else if (keys.isAltPressed) {
      _zoomY(factor, area == _Area.grid || area == _Area.keys ? e.localPosition.dy : _gridSize.height / 2);
    } else if (area == _Area.keys) {
      _scrollBy(0, main);
    } else if (keys.isShiftPressed || area != _Area.grid) {
      _scrollBy(main, 0);
    } else {
      _scrollBy(dx, dy);
    }
  }

  // trackpad nos apps de desktop: pan nos dois eixos e pinça para o zoom horizontal
  void _panZoomStart(PointerPanZoomStartEvent e) => _panScale = 1;

  void _panZoomUpdate(PointerPanZoomUpdateEvent e, _Area area) {
    if (_clip == null) return;
    if ((e.scale - _panScale).abs() > 1e-4) {
      final f = e.scale / _panScale;
      _panScale = e.scale;
      if (area == _Area.keys) {
        _zoomY(f, e.localPosition.dy);
      } else {
        _zoomX(f, e.localPosition.dx);
      }
    }
    _scrollBy(area == _Area.keys ? 0 : -e.panDelta.dx, area == _Area.ruler || area == _Area.velocity ? 0 : -e.panDelta.dy);
  }

  // ------------------------------------------------------------------ prévia sonora

  void _noteOn(int pitch, double velocity, {bool force = false}) {
    if (!force && !_Prefs.preview) return;
    if (_sounding.add(pitch)) c.noteOn(pitch, velocity: velocity, track: _trackIndex);
  }

  void _noteOff(int pitch) {
    if (_sounding.remove(pitch)) c.noteOff(pitch, track: _trackIndex);
  }

  void _silenceAll() {
    for (final p in _sounding.toList()) {
      _noteOff(p);
    }
  }

  /// A nota que o gesto está fazendo soar; trocar de altura troca o som.
  void _sound(_Drag d, int pitch, double velocity) {
    if (d.sounding == pitch) return;
    final prev = d.sounding;
    if (prev != null) _noteOff(prev);
    d.sounding = pitch;
    _noteOn(pitch, velocity);
  }

  void _silence(_Drag d) {
    final p = d.sounding;
    if (p == null) return;
    d.sounding = null;
    _noteOff(p);
  }

  /// Um toque curto das notas (transpor pelo teclado, criar no toque).
  void _blip(List<int> pitches, double velocity) {
    if (!_Prefs.preview || pitches.isEmpty) return;
    for (final p in pitches) {
      _noteOn(p, velocity);
    }
    late final Timer t;
    t = Timer(const Duration(milliseconds: 220), () {
      _blips.remove(t);
      for (final p in pitches) {
        _noteOff(p);
      }
      _refresh();
    });
    _blips.add(t);
  }

  // ------------------------------------------------------------------ hit-test

  _Hit? _hitNote(Offset p, {bool touch = false}) {
    final clip = _clip;
    if (clip == null) return null;
    final g = _g;
    final pitch = g.rows.pitchAt(g.rowAt(p.dy));
    if (pitch == null) return null;
    final slack = touch ? 6.0 : 2.0;
    _Hit? best;
    var bestSelected = false;
    final notes = clip.notes;
    // de trás para frente: a última pintada fica por cima; selecionadas ganham das outras
    for (var i = notes.length - 1; i >= 0; i--) {
      final n = notes[i];
      if (n.pitch != pitch) continue;
      final x0 = g.x(n.start), x1 = x0 + math.max(3.0, n.length * g.ppb);
      if (p.dx < x0 - slack || p.dx > x1 + slack) continue;
      final selected = _sel.contains(n);
      if (best != null && (bestSelected || !selected)) continue;
      final w = x1 - x0;
      final e = math.min(touch ? 12.0 : 6.0, w / 3);
      final zone = p.dx >= x1 - e ? _Zone.end : (p.dx <= x0 + e && w >= 12 ? _Zone.start : _Zone.body);
      best = _Hit(n, zone);
      bestSelected = selected;
      if (selected) break;
    }
    return best;
  }

  bool _nearClipEnd(double x, bool touch, {bool ruler = false}) {
    final clip = _clip;
    if (clip == null || _rows == null) return false;
    final tolerance = ruler ? (touch ? 16.0 : 8.0) : (touch ? 10.0 : 4.0);
    return (x - _g.x(clip.length)).abs() <= tolerance;
  }

  // ------------------------------------------------------------------ grade: ponteiro

  void _gridDown(PointerDownEvent e) {
    _activate();
    if (_clip == null) return;
    if (e.kind == PointerDeviceKind.touch) {
      _touchDown(e);
      return;
    }
    if (_drag != null) return;
    final p = e.localPosition;
    final g = _g;
    final d = _Drag(pointer: e.pointer, touch: false, down: p, downBeat: g.beatAt(p.dx), downRow: g.rowAtF(p.dy));
    if (e.buttons & kMiddleMouseButton != 0) {
      _drag = d
        ..op = _Op.pan
        ..started = true;
      _cursor = SystemMouseCursors.grabbing;
      _refresh();
      return;
    }
    if (e.buttons & kSecondaryMouseButton != 0) {
      _drag = d
        ..op = _Op.erase
        ..started = true;
      _frozenRows = _rows;
      _eraseAt(d, p);
      return;
    }
    if (e.buttons & kPrimaryButton == 0) return;
    final keys = HardwareKeyboard.instance;
    final shift = keys.isShiftPressed, mod = keys.isControlPressed || keys.isMetaPressed;
    final hit = _hitNote(p);
    final dbl = _gridClicks.hit(e.timeStamp, p);
    if (dbl && hit != null && !identical(hit.note, _justCreated)) {
      _deleteNotes([hit.note]);
      return;
    }
    _justCreated = null;
    _drag = d;
    _frozenRows = _rows;
    if (hit != null) {
      _grab(d, hit, shift: shift);
    } else if (_nearClipEnd(p.dx, false)) {
      _beginClipEnd(d);
    } else if (_Prefs.tool == _Tool.select && dbl) {
      _create(d, p);
    } else if (_Prefs.tool == _Tool.select || shift || mod) {
      _beginRect(d, additive: shift);
    } else {
      _create(d, p);
    }
  }

  void _touchDown(PointerDownEvent e) {
    _touches[e.pointer] = e.localPosition;
    if (_touches.length == 2) {
      final d = _drag;
      if (d != null) {
        _drag = null;
        d.longPress?.cancel();
        _silence(d);
        _stopAutoScroll();
        _frozenRows = null;
        _label = null;
        // o primeiro dedo já tinha começado a editar: era o começo da pinça, não uma edição
        if (d.checkpointed) c.undo();
      }
      _pinchStart();
      return;
    }
    if (_touches.length > 2 || _drag != null) return;
    final p = e.localPosition, g = _g;
    final d = _Drag(pointer: e.pointer, touch: true, down: p, downBeat: g.beatAt(p.dx), downRow: g.rowAtF(p.dy))..hit = _hitNote(p, touch: true);
    d.longPress = Timer(const Duration(milliseconds: 450), () => _longPress(d));
    _drag = d;
    _frozenRows = _rows;
  }

  /// No toque, a decisão espera: dedo que mexe arrasta, dedo parado apaga (sobre nota) ou começa
  /// a seleção (no vazio), toque curto seleciona ou cria.
  void _resolvePending(_Drag d) {
    final h = d.hit;
    if (h != null) {
      _grab(d, h, shift: false);
    } else if (_nearClipEnd(d.down.dx, true)) {
      _beginClipEnd(d);
    } else if (_Prefs.tool == _Tool.select) {
      _beginRect(d, additive: false);
    } else {
      _create(d, d.down);
    }
  }

  void _longPress(_Drag d) {
    if (!mounted || !identical(_drag, d) || d.started) return;
    HapticFeedback.mediumImpact();
    final h = d.hit;
    if (h != null) {
      _drag = null;
      _frozenRows = null;
      _deleteNotes([h.note]);
    } else {
      d.started = true;
      _beginRect(d, additive: false);
      _applyRect(d);
    }
  }

  void _grab(_Drag d, _Hit hit, {required bool shift}) {
    final n = hit.note;
    _Prefs.lastLength = n.length;
    _Prefs.lastVelocity = n.velocity;
    if (shift) {
      if (_sel.contains(n)) {
        d.deselectOnUp = n;
      } else {
        _sel.add(n);
      }
    } else if (_sel.contains(n)) {
      d.soleOnUp = n;
    } else {
      _sel
        ..clear()
        ..add(n);
    }
    d.anchor = n;
    d.op = switch (hit.zone) {
      _Zone.end => _Op.resizeEnd,
      _Zone.start => _Op.resizeStart,
      _Zone.body => _Op.move,
    };
    d.duplicate = d.op == _Op.move && HardwareKeyboard.instance.isAltPressed;
    _sound(d, n.pitch, n.velocity);
    _cursor = d.op == _Op.move ? SystemMouseCursors.grabbing : SystemMouseCursors.resizeLeftRight;
    _refresh();
  }

  /// Nota nova no ponto, com a duração escolhida e a última velocidade usada; fica selecionada.
  MidiNote? _createNote(Offset p) {
    final clip = _clip!, g = _g;
    final row = g.rows.pitchAt(g.rowAt(p.dy));
    if (row == null) return null;
    final pitch = _snapPitch(row);
    final base = MidiNote(pitch: pitch, start: math.max(0.0, _snapFloor(g.beatAt(p.dx))), length: _tidy(_newLength), velocity: _Prefs.lastVelocity);
    // com o acorde no clique, a nota vira o acorde inteiro (o arraste dá a duração a todas)
    final stamp = _Prefs.chordStamp;
    final made = stamp == null || _dims.drums ? [base] : chordNotes(base, chordPitches(pitch, stamp.type, inversion: stamp.inversion, scale: _scale));
    final n = made.firstWhere((m) => m.pitch == pitch, orElse: () => made.first);
    c.edit((_) => clip.notes.addAll(made));
    _sel
      ..clear()
      ..addAll(made);
    _mates = made;
    _justCreated = n;
    return n;
  }

  void _create(_Drag d, Offset p) {
    final n = _createNote(p);
    if (n == null) {
      _drag = null;
      _frozenRows = null;
      return;
    }
    d
      ..op = _Op.draw
      ..anchor = n
      ..mates = _mates
      ..checkpointed = true
      ..structural = true;
    _sound(d, n.pitch, n.velocity);
  }

  void _beginRect(_Drag d, {required bool additive}) {
    d
      ..op = _Op.rect
      ..additive = additive
      ..base = additive ? {..._sel} : const {};
    if (!additive) _sel.clear();
    _refresh();
  }

  void _beginClipEnd(_Drag d) {
    d
      ..op = _Op.clipEnd
      ..origLength = _clip!.length;
    _cursor = SystemMouseCursors.resizeColumn;
  }

  void _gridMove(PointerMoveEvent e) {
    if (_touches.containsKey(e.pointer)) {
      _touches[e.pointer] = e.localPosition;
      if (_pinch != null) {
        _pinchUpdate();
        return;
      }
    }
    final d = _drag;
    if (d == null || d.pointer != e.pointer) return;
    if (d.op == _Op.pan) {
      _scrollBy(-e.localDelta.dx, -e.localDelta.dy);
      return;
    }
    d.last = e.localPosition;
    if (!d.started) {
      if ((d.last - d.down).distance < (d.touch ? 10 : 3)) return;
      d.started = true;
      d.longPress?.cancel();
      if (d.op == _Op.pending) {
        _resolvePending(d);
        if (!identical(_drag, d)) return;
      }
      _startOp(d);
    }
    _apply(d);
    _autoScroll();
  }

  /// O arraste começou de fato: guarda o estado de partida (e cria as cópias, com Alt).
  void _startOp(_Drag d) {
    switch (d.op) {
      case _Op.move:
        if (d.duplicate) {
          final clip = _clip!;
          final copies = {for (final n in _sel) n: n.copy()};
          _change(d, () => clip.notes.addAll(copies.values));
          d.structural = true;
          d.anchor = copies[d.anchor] ?? d.anchor;
          _sel
            ..clear()
            ..addAll(copies.values);
        }
        d.orig = {for (final n in _sel) n: _Orig(n)};
      case _Op.resizeEnd || _Op.resizeStart:
        d.orig = {for (final n in _sel) n: _Orig(n)};
      default:
    }
  }

  void _apply(_Drag d) {
    switch (d.op) {
      case _Op.move:
        _applyMove(d);
      case _Op.draw:
        _applyDraw(d);
      case _Op.resizeEnd:
        _applyResize(d, end: true);
      case _Op.resizeStart:
        _applyResize(d, end: false);
      case _Op.rect:
        _applyRect(d);
      case _Op.erase:
        _eraseAt(d, d.last);
      case _Op.clipEnd:
        _applyClipEnd(d);
      case _Op.seek:
        _seekAt(d.last.dx);
      default:
    }
  }

  /// Primeiro passo que muda algo faz o checkpoint; os seguintes só mudam.
  void _change(_Drag d, VoidCallback fn) {
    if (!d.checkpointed) {
      c.checkpoint();
      d.checkpointed = true;
    }
    c.mutate((_) => fn());
  }

  void _applyMove(_Drag d) {
    final clip = _clip!, g = _g, a = d.anchor!, ao = d.orig[a];
    if (ao == null) return;
    // a nota agarrada encaixa na grade; as outras andam o mesmo tanto
    var delta = _snapRound(ao.start + g.beatAt(d.last.dx) - d.downBeat) - ao.start;
    var lo = double.infinity;
    var r0 = g.rows.length, r1 = -1;
    for (final o in d.orig.values) {
      lo = math.min(lo, o.start);
      final r = g.rows.rowOf(o.pitch) ?? 0;
      r0 = math.min(r0, r);
      r1 = math.max(r1, r);
    }
    // ninguém passa para antes do início do clipe (quem já estava antes não vai mais para lá)
    final floor = math.min(0.0, lo);
    if (lo + delta < floor) delta = floor - lo;
    final dRow = math.max(-r0, math.min(g.rows.length - 1 - r1, g.rowAt(d.last.dy) - d.downRow.floor()));
    if (!d.checkpointed && delta.abs() < 1e-9 && dRow == 0) return;
    _change(d, () {
      for (final e in d.orig.entries) {
        var pitch = g.rows.pitchAt(g.rows.rowOf(e.value.pitch)! + dRow)!;
        // prender na escala só quando a altura muda: mover na horizontal não mexe em nota fora dela
        if (dRow != 0) pitch = _snapPitch(pitch, preferUp: dRow < 0);
        e.key
          ..start = _tidy(e.value.start + delta)
          ..pitch = pitch;
      }
    });
    _sound(d, a.pitch, a.velocity);
    _label = '${_pitchLabel(a.pitch)} · ${formatPosition(clip.start + a.start, c.doc.beatsPerBar, meter: c.doc.meter)}';
    _labelAt = (a.start, g.rows.rowOf(a.pitch));
  }

  void _applyDraw(_Drag d) {
    final a = d.anchor!, g = _g;
    final shortest = _snapOff ? 1 / 64 : _step;
    final len = _tidy(math.max(shortest, _snapCeil(g.beatAt(d.last.dx)) - a.start));
    if (len != a.length) {
      c.mutate((_) {
        a.length = len;
        for (final m in d.mates) {
          m.length = len;
        }
      });
    }
    _label = '${_pitchLabel(a.pitch)} · ${_formatLength(a.length)}';
    _labelAt = (a.start, g.rows.rowOf(a.pitch));
  }

  void _applyResize(_Drag d, {required bool end}) {
    final a = d.anchor!, ao = d.orig[a];
    if (ao == null) return;
    final g = _g, move = g.beatAt(d.last.dx) - d.downBeat;
    final free = _snapOff;
    // não encolhe abaixo de um passo da grade (nem de quanto a nota já tinha, se era menor)
    double shortest(_Orig o) => free ? math.min(1 / 64, o.length) : math.min(_step, o.length);
    final next = <MidiNote, (double, double)>{};
    if (end) {
      final delta = _snapRound(ao.start + ao.length + move) - (ao.start + ao.length);
      for (final e in d.orig.entries) {
        next[e.key] = (e.value.start, _tidy(math.max(shortest(e.value), e.value.length + delta)));
      }
    } else {
      final delta = _snapRound(ao.start + move) - ao.start;
      for (final e in d.orig.entries) {
        final o = e.value, stop = o.start + o.length;
        final s = _tidy(math.max(math.min(0.0, o.start), math.min(stop - shortest(o), o.start + delta)));
        next[e.key] = (s, _tidy(stop - s));
      }
    }
    if (!d.checkpointed && next.entries.every((e) => e.key.start == e.value.$1 && e.key.length == e.value.$2)) return;
    _change(d, () {
      for (final e in next.entries) {
        e.key
          ..start = e.value.$1
          ..length = e.value.$2;
      }
    });
    _label = '${_pitchLabel(a.pitch)} · ${_formatLength(a.length)}';
    _labelAt = (a.start, g.rows.rowOf(a.pitch));
  }

  void _applyRect(_Drag d) {
    final g = _g, clip = _clip!;
    final beat = g.beatAt(d.last.dx), row = g.rowAtF(d.last.dy);
    final b0 = math.min(d.downBeat, beat), b1 = math.max(d.downBeat, beat);
    final r0 = math.min(d.downRow, row), r1 = math.max(d.downRow, row);
    d.marquee = Rect.fromLTRB(b0, r0, b1, r1);
    _sel
      ..clear()
      ..addAll(d.base);
    for (final n in clip.notes) {
      final r = g.rows.rowOf(n.pitch);
      if (r != null && n.start < b1 && n.end > b0 && r + 1 > r0 && r < r1) _sel.add(n);
    }
    _refresh();
  }

  void _eraseAt(_Drag d, Offset p) {
    final hit = _hitNote(p);
    if (hit == null) return;
    final clip = _clip!;
    _change(d, () => clip.notes.remove(hit.note));
    d.structural = true;
    _sel.remove(hit.note);
    if (identical(_hover, hit.note)) _hover = null;
  }

  void _applyClipEnd(_Drag d) {
    final clip = _clip!, g = _g;
    final shortest = _snapOff ? 1 / 16 : _step;
    final len = _tidy(math.max(shortest, _snapRound(d.origLength + g.beatAt(d.last.dx) - d.downBeat)));
    _label = 'Fim do clipe · ${_formatSpan(len, c.doc.beatsPerBar, meter: c.doc.meter, from: clip.start)}';
    _labelAt = (len, null);
    if (len == clip.length) {
      _refresh();
      return;
    }
    _change(d, () => clip.length = len);
  }

  void _seekAt(double x) => c.seek(_clip!.start + math.max(0.0, _snapRound(_g.beatAt(x))));

  void _release(PointerEvent e, {required bool cancelled}) {
    if (_touches.remove(e.pointer) != null && _pinch != null) {
      if (_touches.length < 2) _pinch = null;
      return;
    }
    final d = _drag;
    if (d == null || d.pointer != e.pointer) return;
    d.longPress?.cancel();
    _drag = null;
    _stopAutoScroll();
    if (!cancelled) _finish(d, e.timeStamp);
    _silence(d);
    _frozenRows = null;
    _label = null;
    _labelAt = null;
    if (e.kind == PointerDeviceKind.mouse) {
      _cursor = MouseCursor.defer;
      _refresh();
      // o cursor volta a ser o do que está sob o ponteiro
      if (_clip != null && _rows != null) _updateHover(e.localPosition);
    }
    _refresh();
  }

  void _finish(_Drag d, Duration time) {
    switch (d.op) {
      case _Op.pending:
        _tap(d, time);
      case _Op.move || _Op.resizeEnd || _Op.resizeStart:
        if (!d.started) {
          if (d.deselectOnUp case final n?) _sel.remove(n);
          if (d.soleOnUp case final n?) {
            _sel
              ..clear()
              ..add(n);
          }
          return;
        }
        if (d.op != _Op.move) _Prefs.lastLength = d.anchor!.length;
        _dropIfUnchanged(d);
      case _Op.draw:
        if (d.started) _Prefs.lastLength = d.anchor!.length;
      case _Op.clipEnd:
        if (d.checkpointed && _clip?.length == d.origLength) c.undo();
      case _Op.velocity:
        _Prefs.lastVelocity = d.anchor!.velocity;
        _dropIfUnchanged(d);
      default:
    }
  }

  /// Arraste que voltou ao ponto de partida: tira o checkpoint que ficaria vazio no histórico.
  void _dropIfUnchanged(_Drag d) {
    if (!d.checkpointed || d.structural) return;
    for (final e in d.orig.entries) {
      if (!e.value.same(e.key)) return;
    }
    c.undo();
  }

  /// Toque curto (sem arrastar) na grade.
  void _tap(_Drag d, Duration time) {
    final dbl = _gridClicks.hit(time, d.down);
    final h = d.hit;
    if (h != null) {
      if (dbl && !identical(h.note, _justCreated)) {
        _deleteNotes([h.note]);
        return;
      }
      _justCreated = null;
      _sel
        ..clear()
        ..add(h.note);
      _Prefs.lastLength = h.note.length;
      _Prefs.lastVelocity = h.note.velocity;
      _blip([h.note.pitch], h.note.velocity);
      return;
    }
    if (_nearClipEnd(d.down.dx, true)) return;
    if (_Prefs.tool == _Tool.draw || dbl) {
      final n = _createNote(d.down);
      if (n != null) _blip([n.pitch], n.velocity);
    } else {
      _sel.clear();
    }
  }

  void _pinchStart() {
    final v = _view;
    if (v == null || _rows == null) return;
    final pts = _touches.values.take(2).toList();
    final f = (pts[0] + pts[1]) / 2;
    final g = _g;
    _pinch = _Pinch(
      spanX: (pts[0].dx - pts[1].dx).abs(),
      spanY: (pts[0].dy - pts[1].dy).abs(),
      ppb: v.ppb,
      rowH: v.rowH,
      beat: g.beatAt(f.dx),
      row: g.rowAtF(f.dy),
    );
  }

  void _pinchUpdate() {
    final p = _pinch, v = _view;
    if (p == null || v == null || _touches.length < 2) return;
    final pts = _touches.values.take(2).toList();
    final f = (pts[0] + pts[1]) / 2;
    // só dá zoom no eixo em que os dedos começaram afastados: dedos lado a lado não mexem na
    // altura das linhas
    if (p.spanX > 48) v.ppb = (p.ppb * (pts[0].dx - pts[1].dx).abs() / p.spanX).clamp(6.0, 1600.0);
    if (p.spanY > 48) v.rowH = (p.rowH * (pts[0].dy - pts[1].dy).abs() / p.spanY).clamp(_dims.rowMin, _dims.rowMax);
    v.scrollX = p.beat - f.dx / v.ppb;
    v.scrollY = p.row * v.rowH - f.dy;
    _clampView();
    _refresh();
  }

  // ------------------------------------------------------------------ rolagem automática

  bool _autoScrolls(_Drag d) =>
      d.started && (d.op == _Op.move || d.op == _Op.draw || d.op == _Op.resizeEnd || d.op == _Op.resizeStart || d.op == _Op.rect || d.op == _Op.clipEnd);

  /// Velocidade da rolagem quando o arraste encosta na borda da grade.
  Offset _edgeSpeed(_Drag d) {
    const margin = 12.0;
    double speed(double v, double max) {
      final over = v < margin ? v - margin : (v > max - margin ? v - (max - margin) : 0.0);
      return over.clamp(-60.0, 60.0) * .45;
    }

    final vertical = d.op == _Op.move || d.op == _Op.rect;
    return Offset(speed(d.last.dx, _gridSize.width), vertical ? speed(d.last.dy, _gridSize.height) : 0);
  }

  void _autoScroll() {
    final d = _drag;
    if (d != null && _autoScrolls(d) && _edgeSpeed(d) != Offset.zero) {
      _autoTimer ??= Timer.periodic(const Duration(milliseconds: 16), (_) => _autoTick());
    } else {
      _stopAutoScroll();
    }
  }

  void _stopAutoScroll() {
    _autoTimer?.cancel();
    _autoTimer = null;
  }

  void _autoTick() {
    final d = _drag, v = _view;
    if (!mounted || d == null || v == null || _clip == null) {
      _stopAutoScroll();
      return;
    }
    final s = _edgeSpeed(d);
    if (s == Offset.zero) {
      _stopAutoScroll();
      return;
    }
    v.scrollX += s.dx / v.ppb;
    v.scrollY += s.dy;
    _clampView();
    _apply(d);
    _refresh();
  }

  // ------------------------------------------------------------------ passar o mouse

  void _gridHover(PointerHoverEvent e) {
    if (_drag != null || _clip == null || _rows == null) return;
    _updateHover(e.localPosition);
  }

  void _updateHover(Offset p) {
    final h = _hitNote(p);
    final MouseCursor cursor;
    if (h != null) {
      cursor = h.zone == _Zone.body ? SystemMouseCursors.grab : SystemMouseCursors.resizeLeftRight;
    } else if (_nearClipEnd(p.dx, false)) {
      cursor = SystemMouseCursors.resizeColumn;
    } else {
      cursor = _Prefs.tool == _Tool.draw ? SystemMouseCursors.precise : SystemMouseCursors.basic;
    }
    if (cursor != _cursor || !identical(h?.note, _hover)) {
      _cursor = cursor;
      _hover = h?.note;
      _refresh();
    }
  }

  void _clearHover() {
    if (_hover == null) return;
    _hover = null;
    _refresh();
  }

  // ------------------------------------------------------------------ teclado (as teclas)

  void _keysDown(PointerDownEvent e) {
    _activate();
    if (_clip == null || _rows == null || _keyPointer != null) return;
    final pitch = _g.rows.pitchAt(_g.rowAt(e.localPosition.dy));
    if (pitch == null) return;
    if (_keyClicks.hit(e.timeStamp, e.localPosition)) _selectPitch(pitch, add: HardwareKeyboard.instance.isShiftPressed);
    _keyPointer = e.pointer;
    _keyPitch = pitch;
    _noteOn(pitch, _keyVelocity(e.localPosition.dx), force: true);
    _refresh();
  }

  void _keysMove(PointerMoveEvent e) {
    if (e.pointer != _keyPointer || _rows == null) return;
    final pitch = _g.rows.pitchAt(_g.rowAt(e.localPosition.dy));
    if (pitch == null || pitch == _keyPitch) return;
    final prev = _keyPitch;
    if (prev != null) _noteOff(prev);
    _keyPitch = pitch;
    _noteOn(pitch, _keyVelocity(e.localPosition.dx), force: true);
    _refresh();
  }

  void _keysUp(PointerEvent e) {
    if (e.pointer != _keyPointer) return;
    final prev = _keyPitch;
    if (prev != null) _noteOff(prev);
    _keyPointer = null;
    _keyPitch = null;
    _refresh();
  }

  /// Como num piano de rolo: mais à direita na tecla, mais forte.
  double _keyVelocity(double x) => (.35 + .65 * x / _dims.keys).clamp(.1, 1.0);

  // ------------------------------------------------------------------ régua

  void _rulerDown(PointerDownEvent e) {
    _activate();
    if (_clip == null || _rows == null || _drag != null) return;
    final p = e.localPosition;
    final d = _Drag(pointer: e.pointer, touch: e.kind == PointerDeviceKind.touch, down: p, downBeat: _g.beatAt(p.dx), downRow: 0)..started = true;
    _drag = d;
    if (_nearClipEnd(p.dx, d.touch, ruler: true)) {
      _beginClipEnd(d);
    } else {
      d.op = _Op.seek;
      _seekAt(p.dx);
    }
    _refresh();
  }

  void _rulerMove(PointerMoveEvent e) {
    final d = _drag;
    if (d == null || d.pointer != e.pointer) return;
    d.last = e.localPosition;
    _apply(d);
    _autoScroll();
  }

  void _rulerHover(PointerHoverEvent e) {
    final cursor = _nearClipEnd(e.localPosition.dx, false, ruler: true) ? SystemMouseCursors.resizeColumn : SystemMouseCursors.click;
    if (cursor == _rulerCursor) return;
    _rulerCursor = cursor;
    _refresh();
  }

  // ------------------------------------------------------------------ faixa de velocidade

  void _velDown(PointerDownEvent e) {
    _activate();
    final clip = _clip;
    if (clip == null || _rows == null || _drag != null) return;
    final p = e.localPosition;
    final touch = e.kind == PointerDeviceKind.touch;
    final d = _Drag(pointer: e.pointer, touch: touch, down: p, downBeat: _g.beatAt(p.dx), downRow: 0)..started = true;
    _drag = d;
    final n = _hitStem(p, touch);
    if (n != null) {
      // a haste de uma nota selecionada leva a seleção junto; a de outra nota, só ela
      d
        ..op = _Op.velocity
        ..anchor = n
        ..orig = {
          for (final m in _sel.contains(n) ? _sel : {n}) m: _Orig(m),
        };
    } else {
      d
        ..op = _Op.velocityPaint
        ..lastX = p.dx
        ..lastY = p.dy;
      _paintVelocity(d, p);
    }
    _refresh();
  }

  MidiNote? _hitStem(Offset p, bool touch) {
    final g = _g, h = _dims.velocity;
    final tolerance = touch ? 12.0 : 6.0;
    MidiNote? best;
    var bestD = double.infinity;
    for (final n in _clip!.notes) {
      final dx = (g.x(n.start) + 1 - p.dx).abs();
      if (dx > tolerance) continue;
      // num acorde as hastes se sobrepõem: vale a cabeça mais perto do ponteiro
      final dist = dx + (_velY(n.velocity, h) - p.dy).abs() * .5 - (_sel.contains(n) ? 2 : 0);
      if (dist < bestD) {
        bestD = dist;
        best = n;
      }
    }
    return best;
  }

  void _velMove(PointerMoveEvent e) {
    final d = _drag;
    if (d == null || d.pointer != e.pointer) return;
    d.last = e.localPosition;
    if (d.op == _Op.velocity) {
      final dv = (d.down.dy - d.last.dy) / math.max(1.0, _dims.velocity - 2 * _velPad);
      final next = {for (final o in d.orig.entries) o.key: _vel127((o.value.velocity + dv).clamp(0.0, 1.0))};
      if (!d.checkpointed && next.entries.every((o) => o.key.velocity == o.value)) return;
      _change(d, () {
        for (final o in next.entries) {
          o.key.velocity = o.value;
        }
      });
    } else if (d.op == _Op.velocityPaint) {
      _paintVelocity(d, d.last);
    }
  }

  /// Arrastar no vazio da faixa desenha as velocidades (das selecionadas, ou de todas) por onde
  /// passa, interpolando entre um evento e o outro: um arraste rápido faz uma rampa sem falhas.
  void _paintVelocity(_Drag d, Offset p) {
    final g = _g, h = _dims.velocity;
    final x0 = math.min(d.lastX, p.dx) - 1, x1 = math.max(d.lastX, p.dx) + 1;
    final targets = _sel.isEmpty ? _clip!.notes : _sel;
    final hits = <MidiNote, double>{};
    for (final n in targets) {
      final x = g.x(n.start) + 1;
      if (x < x0 || x > x1) continue;
      final t = p.dx == d.lastX ? 1.0 : ((x - d.lastX) / (p.dx - d.lastX)).clamp(0.0, 1.0);
      hits[n] = _velAt(d.lastY + (p.dy - d.lastY) * t, h);
    }
    d
      ..lastX = p.dx
      ..lastY = p.dy;
    if (hits.isEmpty || hits.entries.every((e) => e.key.velocity == e.value)) return;
    _change(d, () {
      for (final e in hits.entries) {
        e.key.velocity = e.value;
      }
    });
    d.anchor = hits.keys.last;
    _Prefs.lastVelocity = d.anchor!.velocity;
  }

  // ------------------------------------------------------------------ teclas

  /// Teclas do editor. Só consome o que usa, e só enquanto o editor foi o último lugar clicado:
  /// senão Delete e Ctrl+D continuam sendo do arranjo.
  bool _handleKey(KeyEvent e) {
    if (!mounted || _clip == null || _rows == null || !_active || e is KeyUpEvent || _drag != null) return false;
    if (FocusManager.instance.primaryFocus?.context?.widget is EditableText) return false;
    final keys = HardwareKeyboard.instance;
    final mod = keys.isControlPressed || keys.isMetaPressed;
    final shift = keys.isShiftPressed;
    final k = e.logicalKey;
    final repeat = e is KeyRepeatEvent;
    if (k == LogicalKeyboardKey.delete || k == LogicalKeyboardKey.backspace) {
      if (!repeat) _deleteNotes(_sel.toList());
      return true;
    }
    if (k == LogicalKeyboardKey.escape) {
      if (_sel.isEmpty) return false;
      _sel.clear();
      _refresh();
      return true;
    }
    if (mod) {
      if (k == LogicalKeyboardKey.keyA) {
        _selectAll();
      } else if (k == LogicalKeyboardKey.keyC) {
        _copy();
      } else if (k == LogicalKeyboardKey.keyX) {
        if (!repeat) _cut();
      } else if (k == LogicalKeyboardKey.keyV) {
        if (!repeat) _paste();
      } else if (k == LogicalKeyboardKey.keyD) {
        if (!repeat) _duplicate();
      } else {
        return false;
      }
      return true;
    }
    if (k == LogicalKeyboardKey.keyQ && !shift) {
      if (!repeat) _quantize();
      return true;
    }
    if (!shift && k == LogicalKeyboardKey.keyK) {
      if (!repeat) _splitAtCursor();
      return true;
    }
    if (!shift && k == LogicalKeyboardKey.keyJ) {
      if (!repeat) _joinNotes();
      return true;
    }
    if (shift && k == LogicalKeyboardKey.keyH) {
      if (!repeat) _humanize();
      return true;
    }
    if (shift && k == LogicalKeyboardKey.keyL) {
      if (!repeat) _transform(legato);
      return true;
    }
    if (_sel.isEmpty) return false;
    if (k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.arrowDown) {
      final steps = shift && !_dims.drums ? 12 : 1;
      _transpose(k == LogicalKeyboardKey.arrowUp ? steps : -steps, repeat: repeat);
      return true;
    }
    if (k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.arrowRight) {
      final step = shift ? _barLen(_sel.map((n) => n.start).reduce(math.min)) : _unit;
      _nudge(k == LogicalKeyboardKey.arrowRight ? step : -step, repeat: repeat);
      return true;
    }
    return false;
  }

  // ------------------------------------------------------------------ comandos

  void _deleteNotes(List<MidiNote> doomed, {List<MidiCc> Function(List<MidiCc>)? controls}) {
    final clip = _clip;
    if (clip == null || doomed.isEmpty) return;
    final set = doomed.toSet();
    c.edit((_) {
      clip.notes.removeWhere(set.contains);
      if (controls != null) clip.controls = controls(clip.controls);
    });
    _sel.removeAll(set);
    if (set.contains(_hover)) _hover = null;
    _justCreated = null;
    _refresh();
  }

  void _selectAll() {
    _sel
      ..clear()
      ..addAll(_clip!.notes);
    _refresh();
  }

  void _selectPitch(int pitch, {bool add = false}) {
    if (!add) _sel.clear();
    _sel.addAll(_clip!.notes.where((n) => n.pitch == pitch));
    _refresh();
  }

  void _copy() {
    if (_sel.isEmpty) return;
    final start = _sel.map((n) => n.start).reduce(math.min);
    final list = _sel.toList()..sort((a, b) => a.start.compareTo(b.start));
    _Prefs.clipboard = [for (final n in list) n.copy()..start = _tidy(n.start - start)];
    // os pontos de bend, modulação e pedal do trecho das notas vão junto
    _Prefs.clipboardCc = copyControls(_clip?.controls ?? const [], start, _sel.map((n) => n.end).reduce(math.max));
    _pasteBase = null;
  }

  void _cut() {
    if (_sel.isEmpty) return;
    _copy();
    // o recortar leva junto o bend, a modulação e o pedal do trecho, como o copiar leva
    final lo = _sel.map((n) => n.start).reduce(math.min), hi = _sel.map((n) => n.end).reduce(math.max);
    _deleteNotes(_sel.toList(), controls: (list) => cutControls(list, lo, hi));
  }

  /// De quanto em quanto repetir um trecho de notas (posições contadas da primeira): em compassos
  /// se passa de meio compasso, em tempos se passa de um tempo, senão pela grade. Uma última nota
  /// que só invade um pouco o compasso seguinte (uma ligadura) não empurra a cópia um compasso
  /// inteiro, desde que nenhuma nota comece lá.
  double _spanStep(Iterable<MidiNote> notes) {
    final first = notes.map((n) => n.start).reduce(math.min);
    final lastStart = notes.map((n) => n.start).reduce(math.max) - first;
    final end = notes.map((n) => n.end).reduce(math.max) - first;
    final bar = _barLen(first);
    if (end > bar / 2) {
      final bars = (end / bar - 1e-9).ceil();
      if (bars > 1 && end - (bars - 1) * bar <= bar / 2 && lastStart < (bars - 1) * bar - 1e-9) return (bars - 1) * bar;
      return bars * bar;
    }
    final unit = end > 1 ? 1.0 : _unit;
    return math.max(unit, (end / unit - 1e-9).ceil() * unit);
  }

  /// Põe notas novas no clipe numa edição só; se alguma começa depois do fim, o clipe cresce até
  /// o compasso que a contém (duplicar e colar são para continuar a música, não para notas mudas).
  void _addNotes(List<MidiNote> notes, {List<MidiCc> region = const [], double regionAt = 0}) {
    final clip = _clip!;
    final lastStart = notes.map((n) => n.start).reduce(math.max);
    final bar = _barLen(lastStart);
    final target = _ceilBar(lastStart + 1e-6);
    // colar muito longe do fim (a tela rolada lá adiante) não estica o clipe até lá
    final grow = target > clip.length + 1e-9 && lastStart < clip.length + bar * 8;
    c.edit((_) {
      clip.notes.addAll(notes);
      if (region.isNotEmpty) clip.controls = pasteControls(clip.controls, region, regionAt);
      if (grow) clip.length = target;
    });
    _sel
      ..clear()
      ..addAll(notes);
    _reveal(notes);
    _refresh();
  }

  void _paste() {
    final clip = _clip, board = _Prefs.clipboard;
    if (clip == null || board.isEmpty) return;
    // no cursor de reprodução, se ele está dentro do clipe; senão no começo da tela
    final rel = c.beat.value - clip.start;
    final base = rel >= 0 && rel < clip.length ? _snapFloor(rel) : math.max(0.0, _snapFloor(_view!.scrollX));
    // colar de novo no mesmo ponto põe a cópia logo depois da anterior
    var at = base;
    if (_pasteBase == base && _pasteNext != null) at = _pasteNext!;
    // cópia exatamente em cima de notas iguais seria invisível (colar logo depois de copiar, com o
    // cursor fora do clipe): anda um trecho por vez até achar lugar livre
    final step = _spanStep(board);
    bool stacked(double at) => board.any((b) => clip.notes.any((n) => n.pitch == b.pitch && (n.start - (b.start + at)).abs() < 1e-6));
    for (var i = 0; i < 64 && stacked(at); i++) {
      at += step;
    }
    _pasteBase = base;
    _pasteNext = at + step;
    _addNotes(
      [
        for (final n in board)
          n.copy()
            ..start = _tidy(n.start + at)
            ..pitch = _snapPitch(n.pitch),
      ],
      region: _Prefs.clipboardCc,
      regionAt: at,
    );
  }

  void _duplicate() {
    if (_clip == null || _sel.isEmpty) return;
    final offset = _spanStep(_sel);
    final lo = _sel.map((n) => n.start).reduce(math.min), hi = _sel.map((n) => n.end).reduce(math.max);
    _addNotes([for (final n in _sel) n.copy()..start = _tidy(n.start + offset)], region: copyControls(_clip!.controls, lo, hi), regionAt: _tidy(lo + offset));
  }

  void _transpose(int up, {required bool repeat}) {
    final rows = _rows!;
    var r0 = rows.length, r1 = -1;
    for (final n in _sel) {
      final r = rows.rowOf(n.pitch) ?? 0;
      r0 = math.min(r0, r);
      r1 = math.max(r1, r);
    }
    final dRow = math.max(-r0, math.min(rows.length - 1 - r1, -up));
    if (dRow == 0) return;
    var next = {for (final n in _sel) n: rows.pitchAt((rows.rowOf(n.pitch) ?? 0) + dRow)!};
    if (_snapping && _Prefs.snapEdits && !_dims.drums) {
      // a seta anda de nota da escala em nota da escala, no sentido em que vai
      final scale = _scale!;
      next = {
        for (final e in next.entries)
          e.key: () {
            final p = scale.snap(e.value, preferUp: up > 0);
            return rows.rowOf(p) != null ? p : e.value;
          }(),
      };
      if (next.entries.every((e) => e.key.pitch == e.value)) return;
    }
    void apply(DawDoc _) {
      for (final e in next.entries) {
        e.key.pitch = e.value;
      }
    }

    // segurar a tecla é uma edição só no histórico
    if (repeat) {
      c.mutate(apply);
    } else {
      c.edit(apply);
    }
    _reveal(_sel);
    _blip([for (final n in _sel.take(6)) n.pitch], _sel.first.velocity);
    _refresh();
  }

  void _nudge(double by, {required bool repeat}) {
    final lo = _sel.map((n) => n.start).reduce(math.min);
    final floor = math.min(0.0, lo);
    final delta = lo + by < floor ? floor - lo : by;
    if (delta.abs() < 1e-9) return;
    void apply(DawDoc _) {
      for (final n in _sel) {
        n.start = _tidy(n.start + delta);
      }
    }

    if (repeat) {
      c.mutate(apply);
    } else {
      c.edit(apply);
    }
    _reveal(_sel);
    _refresh();
  }

  /// Quantiza a seleção (ou tudo) na grade do editor; com a grade livre, em 1/16.
  void _quantize() {
    final clip = _clip;
    if (clip == null || clip.notes.isEmpty) return;
    final notes = _sel.isNotEmpty ? _sel.toList() : List.of(clip.notes);
    c.quantizeNotes(clip, notes, _unit, strength: _Prefs.strength, ends: _Prefs.ends);
    _active = true;
    _refresh();
  }
}
