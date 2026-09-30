part of 'piano_roll.dart';

/// Ferramentas de produtor do piano roll: o menu Ferramentas, a escala do clipe, os diálogos e a
/// aplicação das transformações de `midi_tools.dart` (cada uma vira uma edição só no histórico).
extension _Tools on _PianoRollState {
  ClipScale? get _scale => ClipScale.parse(_clip?.scale);

  /// Prender na escala vale só com escala escolhida e fora da bateria (lá a altura é a peça).
  bool get _snapping => _Prefs.snapScale && !_dims.drums && _scale != null;

  /// A altura encaixada na escala, se a linha existe no editor (senão fica como está).
  int _snapPitch(int pitch, {bool preferUp = false}) {
    if (!_snapping) return pitch;
    final s = _scale!.snap(pitch, preferUp: preferUp);
    return _rows?.rowOf(s) != null ? s : pitch;
  }

  /// A seleção na ordem do clipe, ou todas as notas quando nada está selecionado.
  List<MidiNote> get _targets {
    final notes = _clip!.notes;
    return _sel.isEmpty ? List.of(notes) : notes.where(_sel.contains).toList();
  }

  // ------------------------------------------------------------------ aplicar

  /// Troca [before] por [after] numa edição só. As novas ocupam o lugar da primeira antiga na lista
  /// e ficam selecionadas; se nada mudou de fato, não grava nada no histórico.
  void _replace(List<MidiNote> before, List<MidiNote> after) {
    final clip = _clip;
    if (clip == null || before.isEmpty || sameNotes(before, after)) return;
    final old = before.toSet();
    c.edit((_) {
      final at = clip.notes.indexWhere(old.contains);
      clip.notes.removeWhere(old.contains);
      clip.notes.insertAll(math.min(math.max(at, 0), clip.notes.length), after);
    });
    _sel
      ..clear()
      ..addAll(after);
    _hover = null;
    _justCreated = null;
    _active = true;
    _reveal(after);
    _refresh();
  }

  /// Aplica uma transformação à seleção (ou a todas as notas).
  void _transform(List<MidiNote> Function(List<MidiNote>) fn) {
    final before = _targets;
    if (before.isEmpty) return;
    _replace(before, fn(before));
  }

  // ------------------------------------------------------------------ escala

  void _setScale(ClipScale? s) {
    final clip = _clip;
    if (clip == null) return;
    c.edit((_) => clip.scale = s?.encode());
    _active = true;
    _refresh();
  }

  Future<void> _scaleDialog() async {
    final clip = _clip;
    if (clip == null) return;
    var root = _scale?.root ?? 0;
    var kind = _scale?.scale ?? scales.first;
    var snap = _Prefs.snapScale;
    final key = await _ask(
      'Escala do clipe',
      (set) => [
        const _Caption('Tônica'),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [for (var i = 0; i < 12; i++) ChoiceChip(label: Text(rootNames[i]), selected: root == i, onSelected: (_) => set(() => root = i))],
        ),
        const _Caption('Escala'),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [for (final s in scales) ChoiceChip(label: Text(s.name), selected: kind == s, onSelected: (_) => set(() => kind = s))],
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Prender na escala'),
          subtitle: const Text('Notas desenhadas, movidas e coladas encaixam na nota mais próxima da escala'),
          value: snap,
          onChanged: (v) => set(() => snap = v),
        ),
      ],
      actions: [if (_scale != null) ('none', 'Sem escala'), ('ok', 'Aplicar')],
    );
    if (key == null || !mounted) return;
    _Prefs.snapScale = snap;
    _setScale(key == 'none' ? null : ClipScale(root, kind));
  }

  // ------------------------------------------------------------------ acordes

  String _chordName(String type, int inversion) {
    final name = chordTypes.where((t) => t.id == type).firstOrNull?.name ?? diatonicChords.where((d) => d.$1 == type).firstOrNull?.$2 ?? type;
    return inversion == 0 ? name : '$name, $inversionª inversão';
  }

  Future<void> _chordDialog() async {
    if (_clip == null || _dims.drums) return;
    var type = _Prefs.chordType, inv = _Prefs.chordInversion;
    final scale = _scale;
    // acorde diatônico sem escala não existe: cai no maior
    if (scale == null && diatonicChords.any((d) => d.$1 == type)) type = 'maj';
    final key = await _ask(
      'Acorde',
      (set) => [
        const _Caption('Tipo'),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final t in chordTypes) ChoiceChip(label: Text(t.name), selected: type == t.id, onSelected: (_) => set(() => type = t.id)),
            if (scale != null)
              for (final d in diatonicChords) ChoiceChip(label: Text(d.$2), selected: type == d.$1, onSelected: (_) => set(() => type = d.$1)),
          ],
        ),
        const _Caption('Inversão'),
        Wrap(
          spacing: 6,
          children: [
            for (var i = 0; i < 4; i++) ChoiceChip(label: Text(i == 0 ? 'Fundamental' : '$iª'), selected: inv == i, onSelected: (_) => set(() => inv = i)),
          ],
        ),
        if (scale != null) const _Caption('Os acordes diatônicos usam o grau da escala em que a nota cai.'),
      ],
      actions: [('stamp', 'Usar no clique'), if (_sel.isNotEmpty) ('insert', 'Inserir nas notas')],
    );
    if (key == null || !mounted) return;
    _Prefs.chordType = type;
    _Prefs.chordInversion = inv;
    if (key == 'stamp') {
      _Prefs.chordStamp = _Stamp(type, inv);
      _active = true;
      _refresh();
    } else {
      _insertChord(type, inv);
    }
  }

  /// Cada nota selecionada vira o acorde (com a duração e a velocidade dela).
  void _insertChord(String type, int inversion) {
    if (_sel.isEmpty || _dims.drums) return;
    final before = _targets, scale = _scale;
    final after = <MidiNote>[for (final n in before) ...chordNotes(n, chordPitches(n.pitch, type, inversion: inversion, scale: scale))];
    _replace(before, after);
    _blip([for (final n in _sel.take(6)) n.pitch], _sel.first.velocity);
  }

  // ------------------------------------------------------------------ diálogos

  /// Diálogo simples com conteúdo que muda ao vivo; devolve a chave da ação escolhida (a última
  /// da lista é a principal) ou null se cancelou.
  Future<String?> _ask(String title, List<Widget> Function(StateSetter set) body, {required List<(String, String)> actions}) {
    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: body(set)),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            for (var i = 0; i < actions.length; i++)
              i == actions.length - 1
                  ? FilledButton(onPressed: () => Navigator.pop(ctx, actions[i].$1), child: Text(actions[i].$2))
                  : TextButton(onPressed: () => Navigator.pop(ctx, actions[i].$1), child: Text(actions[i].$2)),
          ],
        ),
      ),
    );
  }

  Widget _slider(String label, double value, double min, double max, int divisions, String Function(double) format, ValueChanged<double> onChanged) => Row(
    children: [
      SizedBox(width: 110, child: Text(label)),
      Expanded(
        child: Slider(value: value.clamp(min, max), min: min, max: max, divisions: divisions, label: format(value), onChanged: onChanged),
      ),
      SizedBox(width: 48, child: Text(format(value), textAlign: TextAlign.end)),
    ],
  );

  Future<void> _arpDialog() async {
    if (_sel.isEmpty) return;
    var pattern = _Prefs.arpPattern, rate = _Prefs.arpRate, octaves = _Prefs.arpOctaves, gate = _Prefs.arpGate;
    final key = await _ask(
      'Arpejador',
      (set) => [
        const _Caption('Padrão'),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [for (final p in ArpPattern.values) ChoiceChip(label: Text(p.label), selected: pattern == p, onSelected: (_) => set(() => pattern = p))],
        ),
        const _Caption('Taxa'),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (var i = 0; i < arpRates.length; i++) ChoiceChip(label: Text(arpRates[i].$1), selected: rate == i, onSelected: (_) => set(() => rate = i)),
          ],
        ),
        const _Caption('Oitavas'),
        Wrap(
          spacing: 6,
          children: [for (var o = 1; o <= 4; o++) ChoiceChip(label: Text('$o'), selected: octaves == o, onSelected: (_) => set(() => octaves = o))],
        ),
        _slider('Gate', gate, .1, 1, 9, (v) => '${(v * 100).round()}%', (v) => set(() => gate = v)),
        const _Caption('Cada grupo de notas que começam juntas vira um arpejo pela duração dele.'),
      ],
      actions: [('ok', 'Arpejar')],
    );
    if (key == null || !mounted) return;
    _Prefs.arpPattern = pattern;
    _Prefs.arpRate = rate;
    _Prefs.arpOctaves = octaves;
    _Prefs.arpGate = gate;
    final before = _targets, seed = _Prefs.seed++;
    _replace(before, arpeggiate(before, pattern: pattern, rate: arpRates[rate].$2, octaves: octaves, gate: gate, seed: seed));
  }

  Future<void> _humanizeDialog() async {
    if (_clip == null || _clip!.notes.isEmpty) return;
    var timing = _Prefs.humTiming, vel = _Prefs.humVelocity, seed = _Prefs.seed;
    String pct(double v) => '${(v * 100).round()}%';
    final key = await _ask(
      'Humanizar',
      (set) => [
        _slider('Tempo', timing, 0, 1, 20, pct, (v) => set(() => timing = v)),
        _slider('Velocidade', vel, 0, 1, 20, pct, (v) => set(() => vel = v)),
        _slider('Semente', seed.toDouble(), 1, 99, 98, (v) => '${v.round()}', (v) => set(() => seed = v.round())),
        const _Caption('Tempo 100% desloca até 1/32 de nota; velocidade 100%, até 30 de 127. A mesma semente dá sempre o mesmo resultado.'),
      ],
      actions: [('ok', 'Humanizar')],
    );
    if (key == null || !mounted) return;
    _Prefs.humTiming = timing;
    _Prefs.humVelocity = vel;
    _Prefs.seed = seed + 1;
    _humanize(seed: seed);
  }

  void _humanize({int? seed}) {
    final s = seed ?? _Prefs.seed++;
    _transform((n) => humanize(n, timing: .125 * _Prefs.humTiming, velocity: .3 * _Prefs.humVelocity, seed: s));
  }

  Future<void> _staccatoDialog() async {
    if (_clip == null || _clip!.notes.isEmpty) return;
    var f = _Prefs.staccato;
    final key = await _ask(
      'Staccato',
      (set) => [_slider('Duração', f, .1, .9, 8, (v) => '${(v * 100).round()}%', (v) => set(() => f = v))],
      actions: [('ok', 'Encurtar')],
    );
    if (key == null || !mounted) return;
    _Prefs.staccato = f;
    _transform((n) => staccato(n, factor: f));
  }

  Future<void> _scaleTimeDialog() async {
    if (_clip == null || _clip!.notes.isEmpty) return;
    var f = 1.5;
    var lengths = true;
    final key = await _ask(
      'Escalar o tempo',
      (set) => [
        _slider('Fator', f, .25, 4, 75, (v) => '×${v.toStringAsFixed(2).replaceAll('.', ',')}', (v) => set(() => f = v)),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text('Escalar as durações também'),
          value: lengths,
          onChanged: (v) => set(() => lengths = v ?? true),
        ),
      ],
      actions: [('ok', 'Aplicar')],
    );
    if (key == null || !mounted) return;
    _transform((n) => scaleTime(n, f, lengths: lengths));
  }

  // ------------------------------------------------------------------ comandos

  /// Corta as notas que o cursor de reprodução atravessa (as selecionadas, ou todas).
  void _splitAtCursor() {
    final clip = _clip;
    if (clip == null) return;
    final at = tidyBeats(c.beat.value - clip.start);
    if (at <= 0) return;
    _transform((n) => splitAt(n, at));
  }

  void _joinNotes() => _transform(joinAdjacent);

  /// Notas selecionadas de outras faixas de instrumento como fantasmas, cada lista com o
  /// deslocamento que leva o tempo do clipe dela ao deste.
  List<(double, List<MidiNote>)> _ghosts(DawTrack t, MidiClip clip) {
    if (!_Prefs.ghostSame && !_Prefs.ghostOthers) return const [];
    final out = <(double, List<MidiNote>)>[];
    for (final other in c.doc.tracks) {
      final same = identical(other, t);
      final skip = same
          ? !_Prefs.ghostSame
          : (!_Prefs.ghostOthers || !other.kind.isInstrument || (other.kind == TrackKind.drums) != (t.kind == TrackKind.drums));
      if (skip) continue;
      for (final m in other.midi) {
        if (identical(m, clip) || m.notes.isEmpty) continue;
        out.add((m.start - clip.start, m.notes));
      }
    }
    return out;
  }

  // ------------------------------------------------------------------ menu

  Widget _scaleButton(BuildContext context) {
    final s = _scale;
    return Tooltip(
      message: 'Escala do clipe: realça as notas dela e permite prender nelas',
      child: InkWell(
        onTap: _scaleDialog,
        borderRadius: BorderRadius.circular(6),
        child: _MenuLabel(icon: Icons.piano, text: s == null ? 'Escala' : s.label, on: s != null),
      ),
    );
  }

  Widget _toolsMenu(BuildContext context) {
    final has = _clip != null && _clip!.notes.isNotEmpty;
    final sel = _sel.isNotEmpty;
    final melodic = !_dims.drums;
    final stamp = _Prefs.chordStamp;
    Widget item(IconData icon, String label, VoidCallback? run, {String? hint, bool? checked}) => MenuItemButton(
      onPressed: run == null
          ? null
          : () {
              _activate();
              run();
            },
      leadingIcon: Icon(checked == null ? icon : (checked ? Icons.check_box : Icons.check_box_outline_blank), size: 18),
      trailingIcon: hint == null ? null : Text(hint, style: const TextStyle(color: Colors.white38, fontSize: 12)),
      child: Text(label),
    );
    Widget group(IconData icon, String label, List<Widget> items) => SubmenuButton(leadingIcon: Icon(icon, size: 18), menuChildren: items, child: Text(label));

    return MenuAnchor(
      builder: (context, controller, _) => Tooltip(
        message: 'Ferramentas de produtor: escala, acordes, arpejo, humanizar e transformações das notas',
        child: InkWell(
          onTap: () => controller.isOpen ? controller.close() : controller.open(),
          borderRadius: BorderRadius.circular(6),
          child: const _MenuLabel(icon: Icons.auto_fix_high, text: 'Ferramentas'),
        ),
      ),
      menuChildren: [
        group(Icons.music_note, 'Escala e acordes', [
          if (melodic) item(Icons.piano, 'Escala…', _scaleDialog),
          if (melodic)
            item(
              Icons.lock_outline,
              'Prender na escala',
              _scale == null
                  ? null
                  : () {
                      _Prefs.snapScale = !_Prefs.snapScale;
                      _refresh();
                    },
              checked: _Prefs.snapScale,
            ),
          if (melodic) item(Icons.library_music, 'Inserir acorde…', _chordDialog),
          if (melodic)
            item(
              Icons.touch_app,
              stamp == null ? 'Acorde no clique' : 'Acorde no clique: ${_chordName(stamp.type, stamp.inversion)}',
              stamp == null
                  ? _chordDialog
                  : () {
                      _Prefs.chordStamp = null;
                      _refresh();
                    },
              checked: stamp != null,
            ),
          item(Icons.stacked_line_chart, 'Desdobrar acorde em arpejo', sel ? () => _transform(spreadChords) : null),
          item(Icons.graphic_eq, 'Arpejador…', sel ? _arpDialog : null),
        ]),
        group(Icons.tune, 'Seleção', [
          item(Icons.shuffle, 'Humanizar…', has ? _humanizeDialog : null, hint: 'Shift+H'),
          item(Icons.trending_up, 'Rampa de velocidade', has ? () => _transform(velocityRamp) : null),
          item(Icons.link, 'Legato', has ? () => _transform(legato) : null, hint: 'Shift+L'),
          item(Icons.more_horiz, 'Staccato…', has ? _staccatoDialog : null),
          item(Icons.flip, 'Inverter no tempo', has ? () => _transform(mirrorTime) : null),
          item(Icons.swap_vert, 'Inverter na altura', has && melodic ? () => _transform(mirrorPitch) : null),
          item(Icons.history, 'Reverter a ordem das notas', has ? () => _transform(reverseOrder) : null),
          item(Icons.looks_3, 'Colcheias em tercinas', has ? () => _transform(tripletize) : null),
        ]),
        group(Icons.straighten, 'Escalar o tempo', [
          item(Icons.zoom_in, '×0,5 (metade)', has ? () => _transform((n) => scaleTime(n, .5)) : null),
          item(Icons.zoom_out, '×2 (dobro)', has ? () => _transform((n) => scaleTime(n, 2)) : null),
          item(Icons.tune, 'Personalizado…', has ? _scaleTimeDialog : null),
        ]),
        group(Icons.content_cut, 'Cortar e limpar', [
          item(Icons.content_cut, 'Dividir no cursor', has ? _splitAtCursor : null, hint: 'K'),
          item(Icons.merge_type, 'Unir notas iguais adjacentes', has ? _joinNotes : null, hint: 'J'),
          item(Icons.filter_none, 'Remover duplicadas', has ? () => _transform(removeDuplicates) : null),
          item(Icons.vertical_align_center, 'Aparar sobrepostas', has ? () => _transform(trimOverlaps) : null),
        ]),
        group(Icons.visibility, 'Fantasmas', [
          item(Icons.layers, 'Outros clipes da faixa', () {
            _Prefs.ghostSame = !_Prefs.ghostSame;
            _refresh();
          }, checked: _Prefs.ghostSame),
          item(Icons.layers_outlined, 'Outras faixas de instrumento', () {
            _Prefs.ghostOthers = !_Prefs.ghostOthers;
            _refresh();
          }, checked: _Prefs.ghostOthers),
        ]),
      ],
    );
  }
}

class _Caption extends StatelessWidget {
  final String text;
  const _Caption(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10, bottom: 6),
    child: Text(text, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white54)),
  );
}
