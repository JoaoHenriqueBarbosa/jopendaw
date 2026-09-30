/// Painel do instrumento da faixa selecionada: cabeçalho com presets e um teclado para tocar, e os
/// controles em cartões (sintetizador), colunas por peça (bateria) ou o áudio escolhido com o
/// envelope (sampler).
///
/// Cada mexida vai ao motor na hora pelo controlador (`setParam`). O arraste de um knob é um passo
/// só no desfazer: o ponto é guardado na primeira mudança e os passos seguintes não entram no
/// histórico; cada escolha de menu entra sozinha.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Curve;

import '../widgets/format.dart';
import '../widgets/responsive_scaffold.dart';
import '../widgets/theme.dart';
import 'controller.dart';
import 'expression_wheels.dart';
import 'instruments.dart';
import 'knob.dart';
import 'model.dart';
import 'presets.dart';
import 'sampler_zones.dart' show zoneCoveredNotes;
import 'sampler_zones_panel.dart';
import 'wavetable_shape.dart';

class InstrumentPanel extends StatefulWidget {
  final DawController c;
  const InstrumentPanel({super.key, required this.c});

  @override
  State<InstrumentPanel> createState() => _InstrumentPanelState();
}

/// Alturas fixas do painel: cabeçalho e a faixa do teclado (quando ele fica embaixo).
const _headerHeight = 48.0;
const _keysHeightDesktop = 56.0;
const _keysHeightMobile = 68.0;

/// Teclas do teclado da tela: duas oitavas e o dó de cima.
const _keyCount = 25;

class _InstrumentPanelState extends State<InstrumentPanel> {
  /// Oitava do teclado da tela por tipo: a bateria começa no C2 (36), onde o General MIDI põe as
  /// peças; os outros no C3.
  final _octave = <TrackKind, int>{TrackKind.synth: 3, TrackKind.drums: 2, TrackKind.sampler: 3, TrackKind.fm: 3, TrackKind.wavetable: 3};

  /// Último preset aplicado em cada faixa (pelo id), para o menu dizer "Pad quente (editado)".
  final _lastPreset = <String, String>{};

  /// Celular: o teclado da tela aparece embaixo; dá para escondê-lo e ganhar altura.
  bool _keysVisible = true;

  /// Nota tocada pela tela → faixa em que tocou: solta na mesma faixa mesmo que a seleção mude com
  /// o dedo ainda na tecla.
  final _held = <int, int>{};

  final _scrolls = <String, ScrollController>{};

  DawController get c => widget.c;

  ScrollController _scroll(String key) => _scrolls.putIfAbsent(key, ScrollController.new);

  @override
  void dispose() {
    for (final s in _scrolls.values) {
      s.dispose();
    }
    super.dispose();
  }

  void _noteOn(int track, int pitch, double velocity) {
    _held[pitch] = track;
    c.noteOn(pitch, velocity: velocity, track: track);
  }

  void _noteOff(int pitch) {
    final track = _held.remove(pitch);
    if (track != null && track < c.doc.tracks.length) c.noteOff(pitch, track: track);
  }

  @override
  Widget build(BuildContext context) {
    final desktop = isDesktop(context);
    return LayoutBuilder(
      builder: (context, box) {
        // sem altura imposta (numa Column, como o mixer), o painel escolhe a própria
        final screen = MediaQuery.sizeOf(context).height;
        final height = box.hasBoundedHeight ? box.maxHeight : (desktop ? math.max(220.0, math.min(300.0, screen * 0.42)) : (screen * 0.5).clamp(240.0, 420.0));
        return Container(
          height: height,
          decoration: const BoxDecoration(
            color: Palette.bar,
            border: Border(top: BorderSide(color: Palette.hairlineStrong)),
          ),
          child: ListenableBuilder(listenable: c, builder: (context, _) => _content(context, desktop, box.maxWidth, math.max(0, height - 1))),
        );
      },
    );
  }

  Widget _content(BuildContext context, bool desktop, double width, double height) {
    if (!c.ready) return const SizedBox.shrink();
    final tracks = c.doc.tracks;
    if (tracks.isEmpty) {
      return _Empty(
        icon: Icons.piano_outlined,
        title: 'Nenhuma faixa no projeto',
        message: 'Crie uma faixa de instrumento para tocar e programar notas.',
        actions: _createButtons(),
      );
    }
    final ti = math.min(math.max(c.selectedTrack, 0), tracks.length - 1);
    final t = tracks[ti];
    final color = trackColorAt(t.color);
    final instrument = t.kind.isInstrument;
    final keysH = desktop ? _keysHeightDesktop : _keysHeightMobile;
    final keysInHeader = instrument && desktop && width >= 1000;
    // painel baixo demais: o teclado sai para os controles caberem
    final keysBelow = instrument && !keysInHeader && (desktop || _keysVisible) && height >= _headerHeight + keysH + 120;
    final bodyH = math.max(0.0, height - _headerHeight - (keysBelow ? keysH : 0));
    final x = _Ctx.of(this, ti, t, color, desktop, bodyH);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: _headerHeight, child: _header(x, keysInHeader, width)),
        Expanded(child: ClipRect(child: _body(x, width))),
        if (keysBelow) SizedBox(height: keysH, child: _keysStrip(x)),
      ],
    );
  }

  List<Widget> _createButtons() => [
    for (final k in [TrackKind.synth, TrackKind.drums, TrackKind.sampler, TrackKind.fm, TrackKind.wavetable])
      FilledButton.tonalIcon(onPressed: () => c.addInstrumentTrack(k), icon: Icon(k.icon, size: 18), label: Text(k.label)),
  ];

  // ---------------------------------------------------------------------- cabeçalho

  Widget _header(_Ctx x, bool keysInHeader, double width) {
    final t = x.t;
    final theme = Theme.of(context);
    final name = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        Text(t.kind.label, maxLines: 1, style: theme.textTheme.labelSmall?.copyWith(color: Colors.white54)),
      ],
    );
    final instrument = t.kind.isInstrument;
    final midiOn = c.midiInputs.isNotEmpty;
    final midi = IconButton(
      tooltip: midiOn ? 'MIDI: ${c.midiInputs.join(', ')}' : 'Tocar com um teclado MIDI',
      isSelected: midiOn,
      onPressed: c.enableMidiInput,
      visualDensity: x.desktop ? null : VisualDensity.compact,
      icon: const Icon(Icons.usb, size: 20),
      selectedIcon: Icon(Icons.usb, size: 20, color: x.color),
    );
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Palette.hairline)),
      ),
      child: Row(
        children: [
          Container(width: 4, color: x.color),
          SizedBox(width: x.desktop ? 12 : 10),
          Icon(t.kind.icon, size: 20, color: x.color),
          const SizedBox(width: 10),
          if (x.desktop) ...[
            Flexible(
              child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 220), child: name),
            ),
            if (instrument) ...[const SizedBox(width: 14), ..._presetControls(x, maxWidth: 200, arrows: true)],
            const Spacer(),
            if (instrument) ...[
              IconButton(
                tooltip: c.keyboardOn
                    ? 'Teclado tocando: atalhos suspensos (A a P tocam; Z/X mudam a oitava; C/V a intensidade)'
                    : withMod('Tocar com o teclado do computador (Ctrl+K)'),
                isSelected: c.keyboardOn,
                onPressed: c.toggleKeyboard,
                icon: const Icon(Icons.keyboard_outlined, size: 20),
                selectedIcon: Icon(Icons.keyboard, size: 20, color: x.color),
              ),
              midi,
            ],
            if (keysInHeader) ...[
              const SizedBox(width: 6),
              ..._wheels(x, 38),
              _octaveButton(x, -1),
              SizedBox(width: 17.0 * _keyCount * 7 / 12, height: 38, child: _keys(x)),
              _octaveButton(x, 1),
            ],
            const SizedBox(width: 8),
          ] else ...[
            Expanded(child: name),
            if (instrument) ...[
              const SizedBox(width: 8),
              // o preset tem prioridade sobre o nome da faixa, que já aparece no arranjo
              ..._presetControls(x, maxWidth: math.min(180, width * 0.42), arrows: false),
              midi,
              IconButton(
                tooltip: _keysVisible ? 'Esconder o teclado' : 'Mostrar o teclado',
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() => _keysVisible = !_keysVisible),
                icon: Icon(_keysVisible ? Icons.piano : Icons.piano_off, size: 20),
              ),
            ],
            const SizedBox(width: 4),
          ],
        ],
      ),
    );
  }

  /// Menu de presets (com setas para ir ao anterior e ao próximo no computador).
  List<Widget> _presetControls(_Ctx x, {required double maxWidth, required bool arrows}) {
    final t = x.t;
    final list = presetsFor(t.kind);
    if (list.isEmpty) return const [];
    final current = matchingPreset(t);
    final last = _lastPreset[t.id];
    // a faixa recém-criada traz o padrão do tipo, que não é um "personalizado" de ninguém
    final pristine = t.kind.params.every((s) => (t.param(s.id) - s.def).abs() <= 1e-6 * math.max(1, s.def.abs()));
    final label = current?.name ?? (last != null ? '$last (editado)' : (pristine ? 'Inicial' : 'Personalizado'));
    final what = t.kind == TrackKind.drums ? 'kit' : 'preset';

    void apply(Preset p) {
      setState(() => _lastPreset[t.id] = p.name);
      c.applyPreset(x.ti, presetParams(p, t));
    }

    void step(int dir) {
      var i = current != null ? list.indexOf(current) : list.indexWhere((p) => p.name == last);
      i = i < 0 ? (dir > 0 ? 0 : list.length - 1) : (i + dir) % list.length;
      apply(list[i]);
    }

    final entries = <PopupMenuEntry<Preset>>[];
    String? section;
    for (final p in list) {
      if (p.category != section) {
        if (section != null) entries.add(const PopupMenuDivider(height: 8));
        section = p.category;
        entries.add(
          PopupMenuItem<Preset>(
            enabled: false,
            height: 26,
            child: Text(
              p.category.toUpperCase(),
              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.9, color: x.color),
            ),
          ),
        );
      }
      entries.add(
        PopupMenuItem<Preset>(
          value: p,
          height: 36,
          child: Row(
            children: [
              SizedBox(width: 24, child: identical(p, current) ? Icon(Icons.check, size: 16, color: x.color) : null),
              Text(p.name),
            ],
          ),
        ),
      );
    }

    final menu = PopupMenuButton<Preset>(
      tooltip: t.kind == TrackKind.drums ? 'Kits de bateria' : 'Presets',
      position: PopupMenuPosition.under,
      constraints: const BoxConstraints(minWidth: 220, maxHeight: 460),
      onSelected: apply,
      itemBuilder: (_) => entries,
      child: Container(
        height: 32,
        // com as setas a largura é fixa: senão o "próximo" anda a cada nome e o clique seguinte erra
        width: arrows ? maxWidth : null,
        constraints: arrows ? null : BoxConstraints(maxWidth: maxWidth),
        padding: const EdgeInsets.only(left: 10, right: 2),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Palette.hairlineStrong),
        ),
        child: Row(
          mainAxisSize: arrows ? MainAxisSize.max : MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome_outlined, size: 15, color: x.color),
            const SizedBox(width: 7),
            Flexible(
              fit: arrows ? FlexFit.tight : FlexFit.loose,
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
            ),
            const Icon(Icons.arrow_drop_down, size: 18, color: Colors.white54),
          ],
        ),
      ),
    );
    if (!arrows) return [menu];
    return [
      _SmallIcon(icon: Icons.chevron_left, tooltip: 'Anterior ($what)', onTap: () => step(-1)),
      Flexible(child: menu),
      _SmallIcon(icon: Icons.chevron_right, tooltip: 'Próximo ($what)', onTap: () => step(1)),
    ];
  }

  // ---------------------------------------------------------------------- teclado da tela

  int _first(TrackKind k) => 12 * (_octave[k]! + 1);

  Widget _octaveButton(_Ctx x, int dir) {
    final o = _octave[x.t.kind]!;
    final next = o + dir;
    // o dó de cima (primeira + 24) não passa do 127
    final ok = next >= -1 && 12 * (next + 1) + _keyCount - 1 <= 127;
    return _SmallIcon(
      icon: dir < 0 ? Icons.chevron_left : Icons.chevron_right,
      tooltip: dir < 0 ? 'Oitava abaixo' : 'Oitava acima',
      onTap: ok ? () => setState(() => _octave[x.t.kind] = next) : null,
    );
  }

  Widget _keys(_Ctx x) {
    final t = x.t;
    return _PianoKeys(
      first: _first(t.kind),
      count: _keyCount,
      color: x.color,
      marks: switch (t.kind) {
        TrackKind.drums => {for (final p in drumPieces) p.pitch},
        // com zonas quem manda são elas: marca as notas que alguma cobre; sem zonas, a nota base do cartão
        TrackKind.sampler => t.zones.isEmpty ? {t.param(SamplerId.root).round()} : zoneCoveredNotes(t.zones),
        _ => const <int>{},
      },
      labels: t.kind == TrackKind.drums ? {for (final p in drumPieces) p.pitch: p.name} : const {},
      onDown: (pitch, velocity) => _noteOn(x.ti, pitch, velocity),
      onUp: _noteOff,
    );
  }

  Widget _keysStrip(_Ctx x) => Container(
    decoration: const BoxDecoration(
      color: Palette.ink,
      border: Border(top: BorderSide(color: Palette.hairline)),
    ),
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        const SizedBox(width: 6),
        ..._wheels(x, (x.desktop ? _keysHeightDesktop : _keysHeightMobile) - 12),
        _octaveButton(x, -1),
        Expanded(child: _keys(x)),
        _octaveButton(x, 1),
      ],
    ),
  );

  /// As rodas de bend e de modulação ao lado do teclado (a bateria não tem afinação nem pedal).
  List<Widget> _wheels(_Ctx x, double height) =>
      x.t.kind == TrackKind.drums ? const [] : [ExpressionWheels(c: c, track: x.ti, height: height, color: x.color), const SizedBox(width: 6)];

  // ---------------------------------------------------------------------- corpo

  Widget _body(_Ctx x, double width) => switch (x.t.kind) {
    TrackKind.bus => _Empty(
      icon: Icons.call_split,
      title: 'Barramento',
      message: 'Barramentos recebem o áudio de outras faixas (envios e saídas) e não têm instrumento. Os efeitos dele ficam na aba Efeitos.',
      actions: _createButtons(),
    ),
    TrackKind.audio => _Empty(
      icon: Icons.graphic_eq,
      title: 'Faixa de áudio',
      message:
          'Faixas de áudio tocam os clipes gravados e importados e não têm instrumento; os efeitos dela ficam na aba Efeitos. '
          'Para tocar notas, crie uma faixa de instrumento.',
      actions: _createButtons(),
    ),
    TrackKind.synth => _layout(x, 'synth', _synthSections(x), width),
    TrackKind.drums => x.desktop ? _drumsDesktop(x) : _layout(x, 'drums', _drumSectionsMobile(x), width),
    TrackKind.sampler => _layout(x, 'sampler', _samplerSections(x), width),
    TrackKind.fm => _layout(x, 'fm', _fmSections(x), width),
    TrackKind.wavetable => _layout(x, 'wavetable', _wavetableSections(x), width),
  };

  /// Cartões numa fileira com rolagem horizontal (computador) ou quebrando em linhas com rolagem
  /// vertical (celular).
  Widget _layout(_Ctx x, String key, List<_Section> sections, double width) {
    if (x.desktop) {
      return _hStrip(key, [for (final s in sections) _Card(section: s, graphHeight: x.graph)]);
    }
    final avail = width - 20;
    final cardW = avail >= 600 ? (avail - 8) / 2 : avail;
    final v = _scroll('$key-v');
    return Scrollbar(
      controller: v,
      child: SingleChildScrollView(
        controller: v,
        padding: const EdgeInsets.all(10),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [for (final s in sections) _Card(section: s, graphHeight: x.graph, width: s.fullWidth ? avail : cardW)],
        ),
      ),
    );
  }

  /// Fileira horizontal do computador. A roda vertical do mouse rola a fileira (quando não está
  /// em cima de um knob, que fica com ela); se o painel for baixo demais, rola na vertical também.
  Widget _hStrip(String key, List<Widget> children) {
    final h = _scroll('$key-h');
    return Listener(
      onPointerSignal: (e) {
        if (e is! PointerScrollEvent || e.scrollDelta.dy == 0 || e.scrollDelta.dx != 0) return;
        if (!h.hasClients || h.position.maxScrollExtent <= 0) return;
        GestureBinding.instance.pointerSignalResolver.register(e, (ev) {
          final p = h.position;
          p.jumpTo((p.pixels + (ev as PointerScrollEvent).scrollDelta.dy).clamp(p.minScrollExtent, p.maxScrollExtent));
        });
      },
      child: SingleChildScrollView(
        child: Scrollbar(
          controller: h,
          child: SingleChildScrollView(
            controller: h,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(width: 8), children[i]],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------- sintetizador

  List<_Section> _synthSections(_Ctx x) {
    double v(int id) => x.t.param(id);
    final lfoOff = v(SynthId.lfoPitch) == 0 && v(SynthId.lfoCutoff) == 0 && v(SynthId.lfoAmp) == 0;
    final filterEnvOff = v(SynthId.filterEnv) == 0;
    // o que não faz efeito com os ajustes de agora fica apagado (mas mexível)
    bool dim(int id) => switch (id) {
      SynthId.pulse => v(SynthId.osc1Wave) != 1 && (v(SynthId.osc2Wave) != 1 || v(SynthId.osc2Level) == 0),
      SynthId.osc2Wave || SynthId.osc2Semi || SynthId.osc2Detune => v(SynthId.osc2Level) == 0,
      SynthId.unisonDetune || SynthId.unisonSpread => v(SynthId.unison) <= 1,
      SynthId.lfoWave || SynthId.lfoRate => lfoOff,
      SynthId.fltAttack || SynthId.fltDecay || SynthId.fltSustain || SynthId.fltRelease => filterEnvOff,
      _ => false,
    };
    String fmt(int id) => _formatValue(x.spec(id), v(id));

    final groups = <String, List<ParamSpec>>{};
    for (final p in synthParams) {
      (groups[p.group] ??= []).add(p);
    }
    return [
      for (final MapEntry(key: group, value: params) in groups.entries)
        _Section(
          group,
          dimmed: (group == 'Envelope do filtro' && filterEnvOff) || (group == 'LFO' && lfoOff),
          display: switch (group) {
            'Oscilador 1' => _Display(
              painter: _OscPainter(shape: v(SynthId.osc1Wave).round(), pulse: v(SynthId.pulse), level: v(SynthId.osc1Level), color: x.color),
              caption: v(SynthId.osc1Wave) == 1 ? 'pulso ${fmt(SynthId.pulse)}' : null,
            ),
            'Oscilador 2' => _Display(
              painter: _OscPainter(shape: v(SynthId.osc2Wave).round(), pulse: v(SynthId.pulse), level: v(SynthId.osc2Level), color: x.color),
              caption: '${fmt(SynthId.osc2Semi)}  ${fmt(SynthId.osc2Detune)}',
            ),
            'Mistura' => _MixDisplay(
              levels: [('Osc 1', v(SynthId.osc1Level)), ('Osc 2', v(SynthId.osc2Level)), ('Sub', v(SynthId.sub)), ('Ruído', v(SynthId.noise))],
              unison: v(SynthId.unison).round(),
              color: x.color,
            ),
            'Filtro' => _Display(
              painter: _FilterPainter(
                type: v(SynthId.filterType).round(),
                cutoff: v(SynthId.cutoff),
                resonance: v(SynthId.resonance),
                envelope: v(SynthId.filterEnv),
                color: x.color,
              ),
            ),
            'Amplitude' => _Display(
              painter: _EnvelopePainter(v(SynthId.ampAttack), v(SynthId.ampDecay), v(SynthId.ampSustain), v(SynthId.ampRelease), x.color),
            ),
            'Envelope do filtro' => _Display(
              painter: _EnvelopePainter(v(SynthId.fltAttack), v(SynthId.fltDecay), v(SynthId.fltSustain), v(SynthId.fltRelease), x.color),
              caption: filterEnvOff ? 'sem efeito: Envelope do filtro em 0' : null,
            ),
            'LFO' => _Display(
              painter: _LfoPainter(wave: v(SynthId.lfoWave).round(), rate: v(SynthId.lfoRate), color: x.color),
              caption: lfoOff ? 'sem efeito: vibrato, filtro e tremolo em 0' : null,
            ),
            'Geral' => _Readout(
              lines: [
                v(SynthId.voices) <= 1 ? 'Mono · legato' : 'Poli · ${v(SynthId.voices).round()} vozes',
                v(SynthId.glide) > 0 ? 'Glide ${fmt(SynthId.glide)}' : 'Sem glide',
              ],
              color: x.color,
            ),
            _ => null,
          },
          controls: [for (final p in params) x.knob(p, dimmed: dim(p.id))],
        ),
    ];
  }

  // ---------------------------------------------------------------------- FM

  /// Valores de razão que mais se usa: oitavas, quinta, terça maior e as razões de sino.
  static const _ratioChips = [0.5, 1.0, 2.0, 3.0, 4.0, 5.0, 7.0];

  List<_Section> _fmSections(_Ctx x) {
    double v(int id) => x.t.param(id);
    final alg = v(FmId.algorithm).round().clamp(0, 7);
    final carriers = fmAlgorithmCarriers[alg];
    final lfoOff = v(FmId.lfoPitch) == 0 && v(FmId.lfoAmp) == 0 && v(FmId.lfoIndex) == 0;
    final groups = <String, List<ParamSpec>>{};
    for (final p in fmParams) {
      (groups[p.group] ??= []).add(p);
    }
    String fmt(int id) => _formatValue(x.spec(id), v(id));
    final tileHeight = math.max(x.graph, 46.0);
    return [
      _Section(
        'Algoritmo',
        width: 400,
        fullWidth: true,
        body: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _AlgorithmPicker(
            selected: alg,
            feedback: v(FmId.feedback),
            color: x.color,
            height: tileHeight,
            onPick: (i) => c.setParam(x.ti, FmId.algorithm, i.toDouble(), undoable: true),
          ),
        ),
        controls: [x.knob(x.spec(FmId.feedback))],
      ),
      for (var n = 0; n < 4; n++)
        _Section(
          'Operador ${n + 1}',
          dimmed: v(FmId.op(n, FmId.opLevel)) == 0,
          trailing: Text(
            carriers >> n & 1 == 1 ? 'PORTADOR' : 'MODULADOR',
            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.7, color: carriers >> n & 1 == 1 ? x.color : Colors.white38),
          ),
          display: _Display(
            painter: _EnvelopePainter(
              v(FmId.op(n, FmId.attack)),
              v(FmId.op(n, FmId.decay)),
              v(FmId.op(n, FmId.sustain)),
              v(FmId.op(n, FmId.release)),
              carriers >> n & 1 == 1 ? x.color : x.color.withValues(alpha: 0.6),
            ),
            caption: '${fmt(FmId.op(n, FmId.ratio))}  nível ${fmt(FmId.op(n, FmId.opLevel))}',
          ),
          controls: [for (final p in groups['Operador ${n + 1}']!) x.knob(p)],
          footer: _RatioChips(
            values: _ratioChips,
            current: v(FmId.op(n, FmId.ratio)),
            color: x.color,
            onPick: (r) => c.setParam(x.ti, FmId.op(n, FmId.ratio), r, undoable: true),
          ),
        ),
      _Section(
        'LFO',
        dimmed: lfoOff,
        display: _Display(
          painter: _LfoPainter(wave: v(FmId.lfoWave).round(), rate: v(FmId.lfoRate), color: x.color),
          caption: lfoOff ? 'sem efeito: vibrato, tremolo e brilho em 0' : null,
        ),
        controls: [for (final p in groups['LFO']!) x.knob(p, dimmed: (p.id == FmId.lfoWave || p.id == FmId.lfoRate) && lfoOff)],
      ),
      _Section(
        'Geral',
        display: _Readout(
          lines: [
            v(FmId.voices) <= 1 ? 'Mono · legato' : 'Poli · ${v(FmId.voices).round()} vozes',
            v(FmId.glide) > 0 && v(FmId.voices) <= 1 ? 'Glide ${fmt(FmId.glide)}' : 'Algoritmo ${alg + 1}',
          ],
          color: x.color,
        ),
        controls: [for (final p in groups['Geral']!) x.knob(p, dimmed: p.id == FmId.glide && v(FmId.voices) > 1)],
      ),
    ];
  }

  // ---------------------------------------------------------------------- wavetable

  List<_Section> _wavetableSections(_Ctx x) {
    double v(int id) => x.t.param(id);
    String fmt(int id) => _formatValue(x.spec(id), v(id));
    final lfoOff = v(WtId.lfoPitch) == 0 && v(WtId.lfoCutoff) == 0 && v(WtId.lfoAmp) == 0 && v(WtId.lfoPos) == 0;
    final filterEnvOff = v(WtId.filterEnv) == 0 && v(WtId.envPos) == 0;
    bool dim(int id) => switch (id) {
      WtId.osc2Series || WtId.osc2Pos || WtId.osc2Semi || WtId.osc2Detune => v(WtId.osc2Level) == 0,
      WtId.unisonDetune || WtId.unisonSpread => v(WtId.unison) <= 1,
      WtId.lfoWave || WtId.lfoRate => lfoOff,
      WtId.fltAttack || WtId.fltDecay || WtId.fltSustain || WtId.fltRelease => filterEnvOff,
      _ => false,
    };
    // o LFO e o envelope do filtro deslocam a posição: o gráfico mostra a posição base e a faixa
    // que eles varrem
    _Display scope(int series, int pos, int level) => _Display(
      painter: _TablePainter(
        series: v(series).round().clamp(0, 2),
        pos: v(pos),
        level: v(level),
        sweep: math.max(v(WtId.lfoPos).abs(), v(WtId.envPos).abs()),
        color: x.color,
      ),
      caption: wavetableLabel(v(series).round().clamp(0, 2), v(pos)),
    );
    final groups = <String, List<ParamSpec>>{};
    for (final p in wavetableParams) {
      (groups[p.group] ??= []).add(p);
    }
    return [
      for (final MapEntry(key: group, value: params) in groups.entries)
        _Section(
          group,
          dimmed: (group == 'Envelope do filtro' && filterEnvOff) || (group == 'LFO' && lfoOff) || (group == 'Oscilador 2' && v(WtId.osc2Level) == 0),
          display: switch (group) {
            'Oscilador 1' => scope(WtId.osc1Series, WtId.osc1Pos, WtId.osc1Level),
            'Oscilador 2' => scope(WtId.osc2Series, WtId.osc2Pos, WtId.osc2Level),
            'Mistura' => _MixDisplay(
              levels: [('Osc 1', v(WtId.osc1Level)), ('Osc 2', v(WtId.osc2Level)), ('Sub', v(WtId.sub)), ('Ruído', v(WtId.noise))],
              unison: v(WtId.unison).round(),
              color: x.color,
            ),
            'Filtro' => _Display(
              painter: _FilterPainter(
                type: v(WtId.filterType).round(),
                cutoff: v(WtId.cutoff),
                resonance: v(WtId.resonance),
                envelope: v(WtId.filterEnv),
                color: x.color,
              ),
            ),
            'Amplitude' => _Display(painter: _EnvelopePainter(v(WtId.ampAttack), v(WtId.ampDecay), v(WtId.ampSustain), v(WtId.ampRelease), x.color)),
            'Envelope do filtro' => _Display(
              painter: _EnvelopePainter(v(WtId.fltAttack), v(WtId.fltDecay), v(WtId.fltSustain), v(WtId.fltRelease), x.color),
              caption: filterEnvOff ? 'sem efeito: filtro e posição em 0' : null,
            ),
            'LFO' => _Display(
              painter: _LfoPainter(wave: v(WtId.lfoWave).round(), rate: v(WtId.lfoRate), color: x.color),
              caption: lfoOff ? 'sem efeito: vibrato, filtro, tremolo e posição em 0' : null,
            ),
            'Geral' => _Readout(
              lines: [
                v(WtId.voices) <= 1 ? 'Mono · legato' : 'Poli · ${v(WtId.voices).round()} vozes',
                v(WtId.glide) > 0 ? 'Glide ${fmt(WtId.glide)}' : 'Sem glide',
              ],
              color: x.color,
            ),
            _ => null,
          },
          controls: [for (final p in params) x.knob(p, dimmed: dim(p.id))],
        ),
    ];
  }

  // ---------------------------------------------------------------------- bateria

  static final _drumMaster = drumParams.firstWhere((p) => p.id == DrumId.master);

  List<ParamSpec> _pieceParams(int piece) => [for (var k = 0; k < 4; k++) drumParams[piece * 4 + k]];

  Widget _drumPad(_Ctx x, int piece, {double? width, required double height}) {
    final p = drumPieces[piece];
    return _DrumPad(
      name: p.name,
      pitch: p.pitch,
      color: x.color,
      width: width,
      height: height,
      onDown: (velocity) => _noteOn(x.ti, p.pitch, velocity),
      onUp: () => _noteOff(p.pitch),
    );
  }

  /// Computador: uma coluna por peça, com o pad em cima e os quatro knobs (2×2 se couber na
  /// altura, senão numa fileira).
  Widget _drumsDesktop(_Ctx x) {
    final cellW = knobCellWidth(x.drumKnob);
    final perRow = x.drumGrid ? 2 : 4;
    // padding (8 + 8) e a borda do cartão (1 + 1)
    final colW = cellW * perRow + 18;
    return _hStrip('drums', [
      _Card(
        section: _Section(
          'Geral',
          controls: [x.knob(_drumMaster)],
          footer: const _Hint('Pads tocam na hora (mais forte em cima). No piano roll, cada peça é uma nota: bumbo no C2.'),
        ),
        graphHeight: x.graph,
        width: 176,
      ),
      for (var i = 0; i < drumPieces.length; i++)
        Container(
          width: colW,
          padding: const EdgeInsets.all(8),
          decoration: _cardDecoration,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _drumPad(x, i, height: x.drumPad),
              const SizedBox(height: 6),
              Wrap(runSpacing: 4, children: [for (final p in _pieceParams(i)) x.knob(p, size: x.drumKnob)]),
            ],
          ),
        ),
    ]);
  }

  /// Celular: os pads juntos em cima (para tocar com os dedos) e os ajustes de cada peça embaixo.
  List<_Section> _drumSectionsMobile(_Ctx x) => [
    _Section(
      'Pads',
      fullWidth: true,
      body: LayoutBuilder(
        builder: (context, box) {
          final cols = box.maxWidth >= 520 ? 6 : 4;
          final w = (box.maxWidth - (cols - 1) * 6) / cols;
          return Wrap(spacing: 6, runSpacing: 6, children: [for (var i = 0; i < drumPieces.length; i++) _drumPad(x, i, width: w, height: 52)]);
        },
      ),
    ),
    _Section('Geral', controls: [x.knob(_drumMaster)]),
    for (var i = 0; i < drumPieces.length; i++) _Section(drumPieces[i].name, controls: [for (final p in _pieceParams(i)) x.knob(p)]),
  ];

  // ---------------------------------------------------------------------- sampler

  List<_Section> _samplerSections(_Ctx x) {
    final t = x.t;
    double v(int id) => t.param(id);
    // com zonas o Modo do cartão Áudio não vale (cada zona tem o dela): o envelope é o das zonas sustentadas
    final zoned = t.zones.isNotEmpty;
    final oneShot = !zoned && v(SamplerId.oneShot) >= 0.5;
    final byGroup = <String, List<ParamSpec>>{};
    for (final p in samplerParams) {
      (byGroup[p.group] ??= []).add(p);
    }
    return [
      _Section(
        'Áudio',
        width: 340,
        trailing: _samplePicker(x),
        display: _sampleDisplay(x),
        controls: [
          for (final p in byGroup['Áudio']!)
            x.knob(
              p,
              dimmed: zoned && (p.id == SamplerId.root || p.id == SamplerId.oneShot),
              format: p.id == SamplerId.root ? (n) => noteName(n.round()) : null,
            ),
        ],
      ),
      _Section(
        'Envelope',
        display: _Display(
          painter: _EnvelopePainter(v(SamplerId.attack), v(SamplerId.decay), v(SamplerId.sustain), oneShot ? 0.001 : v(SamplerId.release), x.color),
          caption: oneShot ? 'até o fim: a soltura não entra' : null,
        ),
        controls: [for (final p in byGroup['Envelope']!) x.knob(p, dimmed: oneShot && p.id == SamplerId.release)],
      ),
      _Section('Geral', controls: [for (final p in byGroup['Geral']!) x.knob(p)]),
      _Section(
        'Zonas',
        width: 640,
        fullWidth: true,
        body: SamplerZonesPanel(key: ValueKey('zonas-${t.id}'), c: c, track: x.ti, color: x.color, compact: !x.desktop),
      ),
    ];
  }

  /// Item do menu de áudio que importa um arquivo (um sha-256 nunca é este texto).
  static const _importSample = 'importar';

  Widget? _samplePicker(_Ctx x) {
    final hash = x.t.sample;
    final samples = c.doc.samples.entries.toList()..sort((a, b) => a.value.name.toLowerCase().compareTo(b.value.name.toLowerCase()));
    final info = hash == null ? null : c.doc.samples[hash];
    final label = hash == null ? (samples.isEmpty ? 'Importar o áudio' : 'Escolher o áudio') : (info?.name ?? 'Áudio fora do projeto');
    return PopupMenuButton<String>(
      tooltip: 'Áudio que o sampler toca',
      position: PopupMenuPosition.under,
      constraints: const BoxConstraints(minWidth: 240, maxWidth: 360, maxHeight: 420),
      onSelected: (h) {
        if (h == _importSample) {
          c.importSamplerAudio(x.ti);
        } else {
          c.setInstrumentSample(x.ti, h.isEmpty ? null : h);
        }
      },
      itemBuilder: (_) => [
        for (final e in samples)
          PopupMenuItem(
            value: e.key,
            height: 38,
            child: Row(
              children: [
                SizedBox(width: 24, child: e.key == hash ? Icon(Icons.check, size: 16, color: x.color) : null),
                Flexible(child: Text(e.value.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 12),
                Text(
                  _duration(e.value.duration),
                  style: const TextStyle(fontSize: 12, color: Colors.white54, fontFeatures: [FontFeature.tabularFigures()]),
                ),
              ],
            ),
          ),
        if (samples.isNotEmpty) const PopupMenuDivider(),
        const PopupMenuItem(
          value: _importSample,
          height: 38,
          child: Row(
            children: [
              SizedBox(width: 24, child: Icon(Icons.upload_file, size: 16)),
              Text('Importar um arquivo…'),
            ],
          ),
        ),
        if (hash != null)
          const PopupMenuItem(
            value: '',
            height: 38,
            child: Row(children: [SizedBox(width: 24), Text('Sem áudio')]),
          ),
      ],
      child: Container(
        height: 24,
        padding: const EdgeInsets.only(left: 8, right: 1),
        decoration: BoxDecoration(
          color: hash == null ? x.color.withValues(alpha: 0.14) : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: hash == null ? x.color.withValues(alpha: 0.6) : Palette.hairlineStrong),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.audio_file_outlined, size: 14, color: hash == null ? x.color : Colors.white70),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
              ),
            ),
            const Icon(Icons.arrow_drop_down, size: 16, color: Colors.white54),
          ],
        ),
      ),
    );
  }

  Widget _sampleDisplay(_Ctx x) {
    final hash = x.t.sample;
    if (hash == null) {
      return _Display(
        child: c.doc.samples.isEmpty
            ? const _Hint(
                'Nenhum áudio no projeto ainda. Importe um arquivo pelo menu acima: ele vira o som deste sampler, sem entrar no arranjo.',
                icon: Icons.upload_file,
              )
            : const _Hint('Escolha acima qual áudio do projeto este sampler toca.', icon: Icons.touch_app_outlined),
      );
    }
    final wave = c.waveforms[hash];
    if (wave == null || c.missing.contains(hash)) {
      return const _Display(child: _Hint('Este áudio não está neste aparelho. Importe o arquivo de novo para ouvi-lo.', icon: Icons.cloud_off_outlined));
    }
    final root = x.t.param(SamplerId.root).round();
    final info = c.doc.samples[hash];
    return Tooltip(
      message: 'Segure para ouvir na nota base',
      waitDuration: const Duration(milliseconds: 700),
      triggerMode: TooltipTriggerMode.manual,
      child: _Pressable(
        onDown: () => _noteOn(x.ti, root, 0.8),
        onUp: () => _noteOff(root),
        child: _Display(
          painter: _SampleWavePainter(wave, x.color),
          caption: '${info == null ? '' : '${_duration(info.duration)} · '}${noteName(root)}',
          trailing: const Icon(Icons.play_arrow, size: 14, color: Colors.white54),
        ),
      ),
    );
  }
}

/// O valor como o painel mostra: o `format` da tabela, mas semitons inteiros ganham sinal e espaço
/// ("+12 st"), como os fracionários.
String _formatValue(ParamSpec p, double v) {
  if (p.curve == Curve.integer && p.unit == 'st') {
    final n = v.round();
    return '${n >= 0 ? '+' : ''}$n st';
  }
  return p.format(v);
}

/// "0.84 s", "12.5 s", "3:07".
String _duration(double secs) {
  if (secs < 60) return '${secs.toStringAsFixed(secs < 10 ? 2 : 1)} s';
  final m = secs ~/ 60;
  return '$m:${(secs - m * 60).floor().toString().padLeft(2, '0')}';
}

// ------------------------------------------------------------------------ contexto e medidas

/// O que os cartões de uma faixa precisam: faixa, cor e as medidas que cabem na altura do painel.
class _Ctx {
  final DawController c;
  final int ti;
  final DawTrack t;
  final Color color;
  final bool desktop;

  /// Diâmetro dos knobs e altura dos gráficos dos cartões.
  final double knobSize, graph;

  /// Bateria no computador: knob e altura do pad; e se os knobs vão em 2×2.
  final double drumKnob, drumPad;
  final bool drumGrid;

  const _Ctx(this.c, this.ti, this.t, this.color, this.desktop, this.knobSize, this.graph, this.drumKnob, this.drumPad, this.drumGrid);

  factory _Ctx.of(_InstrumentPanelState s, int ti, DawTrack t, Color color, bool desktop, double bodyH) {
    if (!desktop) return _Ctx(s.c, ti, t, color, false, 44, 60, 44, 52, false);
    // cartão: margem da fileira (20) + do cartão (20) + título (20) + gráfico + 8 + a célula do knob
    // (diâmetro + 32 de texto); o knob cresce até 46 e a sobra vai para o gráfico
    final title = t.kind == TrackKind.sampler ? 28.0 : 20.0;
    final avail = bodyH - 20 - 20 - title - 8 - 32;
    final knob = (avail - 44).clamp(28.0, 46.0);
    final graph = (avail - knob).clamp(36.0, 76.0);
    // coluna da bateria: margens (20 + 16) + pad + 6 + as células; 2×2 se o knob passar de 30
    final gridKnob = (bodyH - 20 - 16 - 44 - 6 - 4 - 64) / 2;
    final grid = gridKnob >= 30;
    final drumKnob = grid ? math.min(gridKnob, 40.0) : (bodyH - 20 - 16 - 40 - 6 - 32).clamp(28.0, 40.0);
    final used = grid ? 2 * (drumKnob + 32) + 4 : drumKnob + 32;
    final drumPad = (bodyH - 20 - 16 - 6 - used).clamp(36.0, 64.0);
    return _Ctx(s.c, ti, t, color, true, knob, graph, drumKnob, drumPad, grid);
  }

  ParamSpec spec(int id) => t.kind.params.firstWhere((p) => p.id == id);

  Widget knob(ParamSpec p, {bool dimmed = false, String Function(double)? format, double? size}) {
    Knob build(double value, Color color) => Knob(
      spec: p,
      value: value,
      size: size ?? knobSize,
      color: color,
      dimmed: dimmed,
      format: format ?? (v) => _formatValue(p, v),
      optionIcon: p.curve == Curve.choice ? (i, col) => _optionGlyph(p.options[i], col) : null,
      onChangeStart: (_) => c.checkpoint(),
      onChanged: (v) => c.setParam(ti, p.id, v, undoable: p.curve == Curve.choice),
    );
    final target = AutoTarget(AutoKind.instrument, param: p.id);
    if (!c.automatedTarget(ti, target)) return build(t.param(p.id), color);
    // com automação e tocando, o knob segue a curva (mexer muda o valor fixo, que volta a valer
    // quando para)
    return ValueListenableBuilder<double>(
      valueListenable: c.beat,
      builder: (_, _, _) => build(c.liveTargetValue(ti, target, t.param(p.id)), c.playing.value ? automationColor : color),
    );
  }
}

// ------------------------------------------------------------------------ cartões

final _cardDecoration = BoxDecoration(
  color: Palette.raised,
  borderRadius: BorderRadius.circular(10),
  border: Border.all(color: Palette.hairline),
);

/// Conteúdo de um cartão: título, um widget ao lado do título, o gráfico, os controles e um
/// rodapé. [body] substitui gráfico e controles quando o cartão é outra coisa (os pads).
class _Section {
  final String title;
  final Widget? trailing, display, body, footer;
  final List<Widget> controls;
  final bool dimmed;

  /// Largura fixa no computador (senão a da fileira de controles).
  final double? width;

  /// No celular ocupa a linha toda mesmo com duas colunas.
  final bool fullWidth;

  const _Section(
    this.title, {
    this.trailing,
    this.display,
    this.body,
    this.footer,
    this.controls = const [],
    this.dimmed = false,
    this.width,
    this.fullWidth = false,
  });
}

class _Card extends StatelessWidget {
  final _Section section;
  final double graphHeight;

  /// Largura imposta (celular, ou o `width` da seção). Sem ela, o cartão tem a largura dos
  /// controles numa fileira só e o gráfico acompanha.
  final double? width;
  const _Card({required this.section, required this.graphHeight, this.width});

  @override
  Widget build(BuildContext context) {
    final s = section;
    final w = width ?? s.width;
    final title = Text(
      s.title.toUpperCase(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.9, color: s.dimmed ? Colors.white30 : Colors.white60),
    );
    final head = SizedBox(
      height: s.trailing == null ? 20 : 28,
      child: Row(
        children: [
          if (s.trailing == null) Flexible(child: title) else title,
          if (s.trailing != null) ...[
            const SizedBox(width: 10),
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: Padding(padding: const EdgeInsets.only(bottom: 4), child: s.trailing),
              ),
            ),
          ],
        ],
      ),
    );
    final children = <Widget>[
      head,
      if (s.body != null) s.body!,
      if (s.display != null) ...[
        SizedBox(
          height: graphHeight,
          child: s.dimmed ? Opacity(opacity: 0.5, child: s.display) : s.display,
        ),
        const SizedBox(height: 8),
      ],
      if (s.controls.isNotEmpty)
        w == null
            ? Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: s.controls)
            : Wrap(alignment: WrapAlignment.spaceEvenly, runSpacing: 6, children: s.controls),
      if (s.footer != null) ...[const SizedBox(height: 6), s.footer!],
    ];
    final column = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
    return Container(
      width: w,
      padding: const EdgeInsets.all(10),
      decoration: _cardDecoration,
      child: w == null ? IntrinsicWidth(child: column) : column,
    );
  }
}

/// Fundo dos gráficos: um visor escuro e recortado, com legenda opcional no canto.
class _Display extends StatelessWidget {
  final CustomPainter? painter;
  final Widget? child, trailing;
  final String? caption;
  const _Display({this.painter, this.child, this.caption, this.trailing});

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(6),
    child: Container(
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Palette.hairline),
      ),
      color: Palette.ink,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (painter != null) CustomPaint(painter: painter),
          ?child,
          if (caption != null)
            Positioned(
              left: 4,
              top: 3,
              right: trailing == null ? 4 : 22,
              child: Align(
                alignment: Alignment.centerLeft,
                // fundo translúcido: a legenda fica legível por cima da curva
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                  decoration: BoxDecoration(color: Palette.ink.withValues(alpha: 0.75), borderRadius: BorderRadius.circular(3)),
                  child: Text(
                    caption!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 9.5, color: Colors.white60, fontFeatures: [FontFeature.tabularFigures()]),
                  ),
                ),
              ),
            ),
          if (trailing != null) Positioned(right: 4, top: 2, child: trailing!),
        ],
      ),
    ),
  );
}

class _Hint extends StatelessWidget {
  final String text;
  final IconData? icon;
  const _Hint(this.text, {this.icon});

  @override
  Widget build(BuildContext context) {
    final label = Text(
      text,
      maxLines: 6,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 11, height: 1.3, color: Colors.white60),
    );
    if (icon == null) return label;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: Colors.white38),
            const SizedBox(width: 8),
            Flexible(child: label),
          ],
        ),
      ),
    );
  }
}

/// Níveis das fontes do sintetizador, como barras.
class _MixDisplay extends StatelessWidget {
  final List<(String, double)> levels;
  final int unison;
  final Color color;
  const _MixDisplay({required this.levels, required this.unison, required this.color});

  @override
  Widget build(BuildContext context) => _Display(
    trailing: unison > 1
        ? Text(
            '×$unison',
            style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: color),
          )
        : null,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 26, 4),
      // cada linha divide a altura do visor, que encolhe em painéis baixos
      child: Column(
        children: [
          for (final (name, level) in levels)
            Expanded(
              child: Row(
                children: [
                  SizedBox(
                    width: 34,
                    child: Text(name, maxLines: 1, style: const TextStyle(fontSize: 9, height: 1, color: Colors.white54)),
                  ),
                  // pintado (não FractionallySizedBox): o cartão mede a largura intrínseca, e fator 0
                  // lá dá infinito
                  Expanded(
                    child: SizedBox(height: 4, child: CustomPaint(painter: _BarPainter(level, color))),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}

class _BarPainter extends CustomPainter {
  final double level;
  final Color color;
  _BarPainter(this.level, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final r = Radius.circular(size.height / 2);
    canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, r), Paint()..color = Colors.white.withValues(alpha: 0.07));
    final w = size.width * level.clamp(0.0, 1.0);
    if (w > 0) canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, math.max(w, size.height), size.height), r), Paint()..color = color);
  }

  @override
  bool shouldRepaint(_BarPainter o) => o.level != level || o.color != color;
}

/// Visor de texto (modo de vozes, glide).
class _Readout extends StatelessWidget {
  final List<String> lines;
  final Color color;
  const _Readout({required this.lines, required this.color});

  @override
  Widget build(BuildContext context) => _Display(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < lines.length; i++)
            Text(
              lines[i],
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: i == 0 ? 12.5 : 11,
                height: 1.35,
                fontWeight: i == 0 ? FontWeight.w700 : FontWeight.w500,
                color: i == 0 ? color : Colors.white60,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
        ],
      ),
    ),
  );
}

class _SmallIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  const _SmallIcon({required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onTap,
    icon: Icon(icon, size: 18),
    visualDensity: VisualDensity.compact,
    padding: EdgeInsets.zero,
    constraints: const BoxConstraints(minWidth: 28, minHeight: 32),
  );
}

/// Estado vazio compacto (cabe no painel de baixo): ícone, título, explicação e ações.
class _Empty extends StatelessWidget {
  final IconData icon;
  final String title, message;
  final List<Widget> actions;
  const _Empty({required this.icon, required this.title, required this.message, this.actions = const []});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = theme.colorScheme.primary;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [tint.withValues(alpha: 0.26), tint.withValues(alpha: 0.02)]),
                  border: Border.all(color: tint.withValues(alpha: 0.35)),
                ),
                child: Icon(icon, size: 24, color: tint),
              ),
              const SizedBox(height: 10),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.4),
              ),
              if (actions.isNotEmpty) ...[const SizedBox(height: 14), Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: actions)],
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------------ tocar

/// Um alvo que toca enquanto pressionado (um dedo de cada vez).
class _Pressable extends StatefulWidget {
  final VoidCallback onDown, onUp;
  final Widget child;
  const _Pressable({required this.onDown, required this.onUp, required this.child});

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  int? _pointer;

  void _release(PointerEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    widget.onUp();
  }

  @override
  void dispose() {
    if (_pointer != null) widget.onUp();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (e) {
      if (_pointer != null || (e.kind == PointerDeviceKind.mouse && e.buttons != kPrimaryMouseButton)) return;
      _pointer = e.pointer;
      widget.onDown();
    },
    onPointerUp: _release,
    onPointerCancel: _release,
    child: MouseRegion(cursor: SystemMouseCursors.click, child: widget.child),
  );
}

/// Pad de uma peça da bateria. Toca no toque (mais forte perto do topo) e acende enquanto
/// pressionado.
class _DrumPad extends StatefulWidget {
  final String name;
  final int pitch;
  final Color color;
  final double? width;
  final double height;
  final ValueChanged<double> onDown;
  final VoidCallback onUp;

  const _DrumPad({required this.name, required this.pitch, required this.color, required this.height, required this.onDown, required this.onUp, this.width});

  @override
  State<_DrumPad> createState() => _DrumPadState();
}

class _DrumPadState extends State<_DrumPad> {
  int? _pointer;
  double _velocity = 0;

  void _release(PointerEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    setState(() {});
    widget.onUp();
  }

  @override
  void dispose() {
    if (_pointer != null) widget.onUp();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final down = _pointer != null;
    final color = widget.color;
    return Semantics(
      button: true,
      label: 'Tocar ${widget.name}',
      child: Listener(
        onPointerDown: (e) {
          if (_pointer != null || (e.kind == PointerDeviceKind.mouse && e.buttons != kPrimaryMouseButton)) return;
          final h = context.size?.height ?? widget.height;
          _velocity = (1 - 0.5 * (e.localPosition.dy / h)).clamp(0.4, 1.0);
          _pointer = e.pointer;
          setState(() {});
          widget.onDown(_velocity);
        },
        onPointerUp: _release,
        onPointerCancel: _release,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: AnimatedContainer(
            duration: Duration(milliseconds: down ? 0 : 180),
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: down
                    ? [color.withValues(alpha: 0.35 + 0.4 * _velocity), color.withValues(alpha: 0.25 + 0.3 * _velocity)]
                    : [color.withValues(alpha: 0.2), color.withValues(alpha: 0.1)],
              ),
              border: Border.all(color: color.withValues(alpha: down ? 0.95 : 0.45)),
            ),
            child: Stack(
              children: [
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      widget.name,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.15,
                        fontWeight: FontWeight.w700,
                        color: down ? Colors.white : Colors.white.withValues(alpha: 0.88),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 5,
                  top: 3,
                  child: Text(noteName(widget.pitch), style: const TextStyle(fontSize: 8.5, color: Colors.white38)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Teclado de piano da tela. Cada dedo (ou o mouse) toca uma tecla; arrastar desliza entre as
/// teclas. A força vem da altura do toque: mais perto da frente, mais forte.
class _PianoKeys extends StatefulWidget {
  /// Primeira nota (um dó) e quantas teclas.
  final int first, count;
  final Color color;

  /// Notas com uma marca (as peças da bateria, a nota base do sampler).
  final Set<int> marks;

  /// Rótulo de dica por nota (nome da peça na bateria).
  final Map<int, String> labels;
  final void Function(int pitch, double velocity) onDown;
  final void Function(int pitch) onUp;

  const _PianoKeys({
    required this.first,
    required this.count,
    required this.color,
    required this.marks,
    required this.labels,
    required this.onDown,
    required this.onUp,
  });

  @override
  State<_PianoKeys> createState() => _PianoKeysState();
}

class _PianoKeysState extends State<_PianoKeys> {
  /// Dedo → nota que ele segura.
  final _held = <int, int>{};
  int? _hover;

  _KeyLayout _layout(Size size) => _KeyLayout(widget.first, widget.count, size);

  double _velocity(Offset p, Size size) => (0.35 + 0.65 * (p.dy / size.height)).clamp(0.1, 1.0);

  void _press(int pointer, int pitch, Offset p, Size size) {
    _held[pointer] = pitch;
    widget.onDown(pitch, _velocity(p, size));
  }

  void _lift(int pointer) {
    final pitch = _held.remove(pointer);
    // outro dedo ainda na mesma tecla: ela continua soando
    if (pitch != null && !_held.containsValue(pitch)) widget.onUp(pitch);
  }

  @override
  void dispose() {
    for (final p in _held.values.toSet()) {
      widget.onUp(p);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final size = box.biggest;
        final layout = _layout(size);
        // nunca vazia: o Tooltip sem mensagem sai da árvore e a troca recriaria o teclado
        String tip() {
          final h = _hover;
          if (h == null) return 'Teclado';
          final label = widget.labels[h];
          return label == null ? noteName(h) : '$label (${noteName(h)})';
        }

        return MouseRegion(
          cursor: SystemMouseCursors.click,
          onHover: (e) {
            final p = layout.pitchAt(e.localPosition);
            if (p != _hover) setState(() => _hover = p);
          },
          onExit: (_) => setState(() => _hover = null),
          child: Listener(
            onPointerDown: (e) {
              if (e.kind == PointerDeviceKind.mouse && e.buttons != kPrimaryMouseButton) return;
              final p = layout.pitchAt(e.localPosition);
              if (p == null) return;
              setState(() => _press(e.pointer, p, e.localPosition, size));
            },
            onPointerMove: (e) {
              final old = _held[e.pointer];
              if (old == null) return;
              final p = layout.pitchAt(e.localPosition);
              if (p == null || p == old) return;
              setState(() {
                _lift(e.pointer);
                _press(e.pointer, p, e.localPosition, size);
              });
            },
            onPointerUp: (e) => setState(() => _lift(e.pointer)),
            onPointerCancel: (e) => setState(() => _lift(e.pointer)),
            // segura o gesto: arrastar no teclado desliza entre as teclas, não rola a tela
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (_) {},
              onVerticalDragStart: (_) {},
              child: Tooltip(
                message: tip(),
                waitDuration: const Duration(milliseconds: 500),
                triggerMode: TooltipTriggerMode.manual,
                child: CustomPaint(
                  size: size,
                  painter: _KeysPainter(
                    layout: layout,
                    held: _held.values.toSet(),
                    marks: widget.marks,
                    color: widget.color,
                    hover: _hover,
                    fontFamily: DefaultTextStyle.of(context).style.fontFamily,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Geometria do teclado: brancas lado a lado, pretas por cima nas divisas.
class _KeyLayout {
  final int first, count;
  final Size size;
  late final List<int> whites = [
    for (var p = first; p < first + count; p++)
      if (!isBlackKey(p)) p,
  ];
  _KeyLayout(this.first, this.count, this.size);

  double get whiteW => size.width / whites.length;
  double get blackW => whiteW * 0.6;
  double get blackH => size.height * 0.6;

  Rect whiteRect(int i) => Rect.fromLTWH(i * whiteW, 0, whiteW, size.height);

  /// Retângulo da preta [pitch], centrada na divisa com a branca de baixo.
  Rect blackRect(int pitch) {
    final left = whites.indexOf(pitch - 1);
    final x = (left + 1) * whiteW;
    return Rect.fromLTWH(x - blackW / 2, 0, blackW, blackH);
  }

  int? pitchAt(Offset p) {
    if (p.dx < 0 || p.dy < 0 || p.dx > size.width || p.dy > size.height) return null;
    if (p.dy < blackH) {
      for (var pitch = first; pitch < first + count; pitch++) {
        if (isBlackKey(pitch) && blackRect(pitch).contains(p)) return pitch;
      }
    }
    final i = (p.dx / whiteW).floor().clamp(0, whites.length - 1);
    return whites[i];
  }
}

class _KeysPainter extends CustomPainter {
  final _KeyLayout layout;
  final Set<int> held, marks;
  final Color color;
  final int? hover;

  /// Fonte do tema para os nomes dos dós (o pintor não herda o DefaultTextStyle).
  final String? fontFamily;

  _KeysPainter({required this.layout, required this.held, required this.marks, required this.color, required this.hover, this.fontFamily});

  @override
  void paint(Canvas canvas, Size size) {
    final ww = layout.whiteW;
    final radius = Radius.circular(math.min(4, ww * 0.18));
    for (var i = 0; i < layout.whites.length; i++) {
      final pitch = layout.whites[i];
      final r = layout.whiteRect(i).deflate(0.5);
      final down = held.contains(pitch);
      final base = down ? Color.lerp(const Color(0xFFD9DCE1), color, 0.75)! : (pitch == hover ? const Color(0xFFF1F3F5) : const Color(0xFFD9DCE1));
      canvas.drawRRect(RRect.fromRectAndCorners(r, bottomLeft: radius, bottomRight: radius), Paint()..color = base);
      if (marks.contains(pitch)) {
        canvas.drawCircle(Offset(r.center.dx, r.bottom - math.min(10, size.height * 0.12)), math.min(2.6, ww * 0.14), Paint()..color = color);
      }
      // o nome nos dós, para achar a oitava
      if (pitch % 12 == 0 && ww >= 12 && size.height >= 30) {
        final tp = TextPainter(
          text: TextSpan(
            text: noteName(pitch),
            style: TextStyle(fontSize: math.min(9, ww * 0.5), color: const Color(0xFF5B616B), fontWeight: FontWeight.w600, fontFamily: fontFamily),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final y = r.bottom - tp.height - (marks.contains(pitch) ? math.min(14, size.height * 0.2) : 3);
        tp.paint(canvas, Offset(r.center.dx - tp.width / 2, y));
      }
    }
    for (var pitch = layout.first; pitch < layout.first + layout.count; pitch++) {
      if (!isBlackKey(pitch)) continue;
      final r = layout.blackRect(pitch);
      final down = held.contains(pitch);
      final base = down ? color : (pitch == hover ? const Color(0xFF3A404A) : const Color(0xFF1A1D22));
      canvas.drawRRect(RRect.fromRectAndCorners(r, bottomLeft: radius, bottomRight: radius), Paint()..color = base);
      if (!down) {
        // brilho de cima, para a preta parecer em relevo
        canvas.drawRect(Rect.fromLTWH(r.left + 1.5, r.top, r.width - 3, r.height * 0.18), Paint()..color = Colors.white.withValues(alpha: 0.06));
      }
      if (marks.contains(pitch)) {
        canvas.drawCircle(Offset(r.center.dx, r.bottom - 6), math.min(2.4, ww * 0.12), Paint()..color = down ? Colors.white : color);
      }
    }
  }

  @override
  bool shouldRepaint(_KeysPainter o) =>
      o.layout.first != layout.first ||
      o.layout.count != layout.count ||
      o.layout.size != layout.size ||
      !setEquals(o.held, held) ||
      !setEquals(o.marks, marks) ||
      o.color != color ||
      o.hover != hover ||
      o.fontFamily != fontFamily;
}

// ------------------------------------------------------------------------ gráficos

/// Forma de onda num ponto da fase (0..1): 0 serra, 1 quadrada (com [pulse]), 2 triângulo,
/// 3 senoide, 4 aleatório (um degrau por ciclo, [cycle]).
double _wave(int shape, double phase, double pulse, [int cycle = 0]) => switch (shape) {
  0 => 2 * phase - 1,
  1 => phase < pulse ? 1 : -1,
  2 => phase < 0.5 ? 4 * phase - 1 : 3 - 4 * phase,
  3 => math.sin(2 * math.pi * phase),
  _ => _noise(cycle),
};

/// Valor pseudoaleatório fixo por índice, em −1..1 (o desenho do "aleatório" não pisca).
double _noise(int i) {
  final s = math.sin(i * 12.9898 + 4.1414) * 43758.5453;
  return (s - s.floorToDouble()) * 2 - 1;
}

/// Ondas do LFO na ordem da tabela (senoide, triângulo, serra, quadrada, aleatório) → [_wave].
const _lfoShapes = [3, 2, 0, 1, 4];

/// Resposta de um filtro de estado variável de 2 polos (12 dB/oit), a mesma família do motor.
double _filterMag(int type, double f, double fc, double q) {
  final w = f / fc, w2 = w * w;
  final den = math.sqrt((1 - w2) * (1 - w2) + (w / q) * (w / q));
  return switch (type) {
    1 => w2 / den,
    2 => (w / q) / den,
    _ => 1 / den,
  };
}

/// Q aproximado da ressonância 0..1: 0,5 sem ressonância, subindo até a auto-oscilação.
double _qFor(double resonance) => 1 / (2 - 1.96 * resonance.clamp(0.0, 1.0));

Paint _stroke(Color color, double width) => Paint()
  ..style = PaintingStyle.stroke
  ..strokeWidth = width
  ..strokeJoin = StrokeJoin.round
  ..strokeCap = StrokeCap.round
  ..color = color;

Paint _fill(Color color, Rect rect) => Paint()
  ..shader = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [color.withValues(alpha: 0.3), color.withValues(alpha: 0.03)],
  ).createShader(rect);

final _grid = Paint()..color = Colors.white.withValues(alpha: 0.06);

/// Ícone das opções: formas de onda e tipos de filtro.
Widget? _optionGlyph(String option, Color color) {
  final shape = switch (option) {
    'Serra' => 0,
    'Quadrada' => 1,
    'Triângulo' => 2,
    'Senoide' => 3,
    'Aleatório' => 4,
    _ => null,
  };
  if (shape != null) {
    return CustomPaint(
      painter: _GlyphPainter(shape: shape, color: color),
    );
  }
  final filter = switch (option) {
    'Passa-baixa' => 0,
    'Passa-alta' => 1,
    'Passa-banda' => 2,
    _ => null,
  };
  if (filter != null) {
    return CustomPaint(
      painter: _GlyphPainter(filter: filter, color: color),
    );
  }
  return null;
}

class _GlyphPainter extends CustomPainter {
  final int? shape, filter;
  final Color color;
  _GlyphPainter({this.shape, this.filter, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    final w = size.width, h = size.height;
    final n = math.max(8, w.ceil() * 2);
    for (var i = 0; i <= n; i++) {
      final t = i / n;
      final double y;
      if (shape != null) {
        // aleatório: quatro degraus; o resto: um ciclo
        final v = shape == 4 ? _noise((t * 4).floor().clamp(0, 3)) : _wave(shape!, t == 1 ? 0.9999 : t, 0.5);
        y = h / 2 - v * (h / 2 - 1);
      } else {
        final f = 20 * math.pow(1000, t).toDouble();
        final db = 20 * math.log(math.max(_filterMag(filter!, f, 632, 1.2), 1e-4)) / math.ln10;
        y = ((6 - db) / 30 * h).clamp(0.5, h - 0.5);
      }
      i == 0 ? path.moveTo(0, y) : path.lineTo(t * w, y);
    }
    canvas.drawPath(path, _stroke(color, 1.4));
  }

  @override
  bool shouldRepaint(_GlyphPainter o) => o.shape != shape || o.filter != filter || o.color != color;
}

/// Dois ciclos da onda do oscilador; o fantasma é a forma em nível cheio.
class _OscPainter extends CustomPainter {
  final int shape;
  final double pulse, level;
  final Color color;
  _OscPainter({required this.shape, required this.pulse, required this.level, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final mid = size.height / 2;
    final amp = size.height / 2 - 6;
    canvas.drawLine(Offset(0, mid), Offset(size.width, mid), _grid);
    Path trace(double a) {
      final p = Path();
      final n = size.width.ceil();
      for (var i = 0; i <= n; i++) {
        final phase = (i / size.width * 2) % 1.0;
        final y = mid - _wave(shape, phase, pulse) * a;
        i == 0 ? p.moveTo(0, y) : p.lineTo(i.toDouble(), y);
      }
      return p;
    }

    canvas.drawPath(trace(amp), _stroke(color.withValues(alpha: 0.16), 1.2));
    if (level > 0.001) canvas.drawPath(trace(amp * level.clamp(0.0, 1.0)), _stroke(color, 1.6));
  }

  @override
  bool shouldRepaint(_OscPainter o) => o.shape != shape || o.pulse != pulse || o.level != level || o.color != color;
}

/// Curva de resposta do filtro (log em frequência, dB na vertical), com o fantasma de até onde o
/// envelope leva o corte.
class _FilterPainter extends CustomPainter {
  final int type;
  final double cutoff, resonance, envelope;
  final Color color;
  _FilterPainter({required this.type, required this.cutoff, required this.resonance, required this.envelope, required this.color});

  /// +18 dB no topo, −30 dB embaixo.
  static const _top = 18.0, _range = 48.0;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    double x(double f) => math.log(f / 20) / math.log(1000) * w;
    double y(double db) => ((_top - db) / _range * h).clamp(-2.0, h + 2);
    for (final f in const [100.0, 1000.0, 10000.0]) {
      canvas.drawLine(Offset(x(f), 0), Offset(x(f), h), _grid);
    }
    canvas.drawLine(Offset(0, y(0)), Offset(w, y(0)), _grid);
    final q = _qFor(resonance);
    double dbAt(double f, double fc) => 20 * math.log(math.max(_filterMag(type, f, fc, q), 1e-5)) / math.ln10;
    Path curve(double fc) {
      final p = Path();
      final n = math.max(2, (w / 1.5).ceil());
      for (var i = 0; i <= n; i++) {
        final px = i / n * w;
        final f = 20 * math.pow(1000, px / w).toDouble();
        final py = y(dbAt(f, fc));
        i == 0 ? p.moveTo(px, py) : p.lineTo(px, py);
      }
      return p;
    }

    if (envelope.abs() > 0.01) {
      final peak = (cutoff * math.pow(2, 6 * envelope)).clamp(20.0, 20000.0);
      canvas.drawPath(curve(peak), _stroke(color.withValues(alpha: 0.3), 1));
    }
    final main = curve(cutoff);
    final area = Path.from(main)
      ..lineTo(w, h + 2)
      ..lineTo(0, h + 2)
      ..close();
    canvas.drawPath(area, _fill(color, Offset.zero & size));
    canvas.drawPath(main, _stroke(color, 1.6));
    final cx = x(cutoff.clamp(20.0, 20000.0));
    canvas.drawCircle(Offset(cx, y(dbAt(cutoff, cutoff)).clamp(3.0, h - 3)), 3, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_FilterPainter o) => o.type != type || o.cutoff != cutoff || o.resonance != resonance || o.envelope != envelope || o.color != color;
}

/// ADSR: ataque em rampa, decaimento e soltura exponenciais como no motor. Os tempos vão em
/// escala logarítmica (1 ms e 10 s precisam aparecer no mesmo cartão); a sustentação ocupa o resto.
class _EnvelopePainter extends CustomPainter {
  final double attack, decay, sustain, release;
  final Color color;
  _EnvelopePainter(this.attack, this.decay, this.sustain, this.release, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    const pad = 5.0;
    final w = size.width, h = size.height - 2 * pad;
    double seg(double t) => math.log(1 + math.max(0, t) / 0.002) / math.log(1 + 10 / 0.002);
    final unit = w / 3.3;
    final wa = math.max(2.0, seg(attack) * unit), wd = math.max(2.0, seg(decay) * unit), wr = math.max(2.0, seg(release) * unit);
    final hold = math.max(0.0, w - wa - wd - wr);
    final s = sustain.clamp(0.0, 1.0);
    double y(double v) => pad + (1 - v) * h;
    const steps = 24;
    final p = Path()
      ..moveTo(0, y(0))
      ..lineTo(wa, y(1));
    for (var i = 1; i <= steps; i++) {
      final k = i / steps;
      p.lineTo(wa + wd * k, y(s + (1 - s) * math.exp(-6.9 * k)));
    }
    p.lineTo(wa + wd + hold, y(s));
    for (var i = 1; i <= steps; i++) {
      final k = i / steps;
      p.lineTo(wa + wd + hold + wr * k, y(s * math.exp(-6.9 * k)));
    }
    for (final x in [wa, wa + wd, wa + wd + hold]) {
      canvas.drawLine(Offset(x, pad), Offset(x, size.height - pad), _grid);
    }
    final area = Path.from(p)
      ..lineTo(0, y(0))
      ..close();
    canvas.drawPath(area, _fill(color, Offset.zero & size));
    canvas.drawPath(p, _stroke(color, 1.6));
    final dot = Paint()..color = Colors.white;
    for (final o in [Offset(wa, y(1)), Offset(wa + wd, y(s)), Offset(wa + wd + hold, y(s))]) {
      canvas.drawCircle(o, 2.2, dot);
    }
  }

  @override
  bool shouldRepaint(_EnvelopePainter o) => o.attack != attack || o.decay != decay || o.sustain != sustain || o.release != release || o.color != color;
}

/// A onda do LFO: mais ciclos quanto mais rápido (de 1 a 16 no visor).
class _LfoPainter extends CustomPainter {
  final int wave;
  final double rate;
  final Color color;
  _LfoPainter({required this.wave, required this.rate, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final mid = size.height / 2, amp = size.height / 2 - 6;
    canvas.drawLine(Offset(0, mid), Offset(size.width, mid), _grid);
    final shape = _lfoShapes[wave.clamp(0, _lfoShapes.length - 1)];
    final cycles = rate.clamp(1.0, 16.0);
    final p = Path();
    final n = size.width.ceil();
    for (var i = 0; i <= n; i++) {
      final t = i / size.width * cycles;
      final y = mid - _wave(shape, t % 1.0, 0.5, t.floor()) * amp;
      i == 0 ? p.moveTo(0, y) : p.lineTo(i.toDouble(), y);
    }
    canvas.drawPath(p, _stroke(color, 1.5));
  }

  @override
  bool shouldRepaint(_LfoPainter o) => o.wave != wave || o.rate != rate || o.color != color;
}

// ------------------------------------------------------------------------ FM: algoritmos

/// Posição de cada operador (x, y em 0..1, y = 0 no alto) no mini diagrama de cada algoritmo:
/// moduladores em cima, portadores embaixo, como nos diagramas dos DX.
const _algoLayout = <List<Offset>>[
  [Offset(0.5, 0), Offset(0.5, 0.33), Offset(0.5, 0.66), Offset(0.5, 1)],
  [Offset(0.28, 0), Offset(0.72, 0), Offset(0.5, 0.5), Offset(0.5, 1)],
  [Offset(0.25, 0.5), Offset(0.75, 0), Offset(0.75, 0.5), Offset(0.5, 1)],
  [Offset(0.25, 0), Offset(0.25, 0.5), Offset(0.75, 0.5), Offset(0.5, 1)],
  [Offset(0.25, 0), Offset(0.25, 1), Offset(0.75, 0), Offset(0.75, 1)],
  [Offset(0.5, 0), Offset(0.15, 1), Offset(0.5, 1), Offset(0.85, 1)],
  [Offset(0.15, 0), Offset(0.15, 1), Offset(0.5, 1), Offset(0.85, 1)],
  [Offset(0.12, 0.5), Offset(0.37, 0.5), Offset(0.63, 0.5), Offset(0.88, 0.5)],
];

/// Os 8 algoritmos como fileira de mini diagramas clicáveis (duas fileiras de 4 se faltar largura).
class _AlgorithmPicker extends StatelessWidget {
  final int selected;
  final double feedback, height;
  final Color color;
  final ValueChanged<int> onPick;
  const _AlgorithmPicker({required this.selected, required this.feedback, required this.color, required this.height, required this.onPick});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final rows = box.maxWidth < 8 * 40 ? 2 : 1;
      final perRow = 8 ~/ rows;
      const gap = 4.0;
      final tileW = (box.maxWidth - gap * (perRow - 1)) / perRow;
      final tileH = rows == 1 ? height : math.max(40.0, (height - gap) / 2);
      return Column(
        children: [
          for (var r = 0; r < rows; r++) ...[
            if (r > 0) const SizedBox(height: gap),
            Row(
              children: [
                for (var k = 0; k < perRow; k++) ...[if (k > 0) const SizedBox(width: gap), _tile(r * perRow + k, tileW, tileH)],
              ],
            ),
          ],
        ],
      );
    },
  );

  Widget _tile(int i, double w, double h) {
    final on = i == selected;
    return Tooltip(
      message: 'Algoritmo ${i + 1}: ${fmAlgorithmNames[i]}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onPick(i),
        child: Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: on ? color.withValues(alpha: 0.16) : Palette.ink,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: on ? color : Palette.hairline, width: on ? 1.4 : 1),
          ),
          child: CustomPaint(
            painter: _AlgoPainter(algorithm: i, color: on ? color : Colors.white54, feedback: on ? feedback : 0),
          ),
        ),
      ),
    );
  }
}

/// Um algoritmo: círculos numerados (cheios = portadores, que vão à saída; vazados = moduladores)
/// e setas de quem modula quem; um laço no operador 1 quando há realimentação.
class _AlgoPainter extends CustomPainter {
  final int algorithm;
  final Color color;
  final double feedback;
  _AlgoPainter({required this.algorithm, required this.color, required this.feedback});

  @override
  void paint(Canvas canvas, Size size) {
    const padX = 11.0, padY = 10.0;
    final r = math.min(5.2, size.width / 9);
    Offset at(int n) {
      final p = _algoLayout[algorithm][n];
      return Offset(padX + p.dx * (size.width - 2 * padX), padY + p.dy * (size.height - 2 * padY - 5));
    }

    final line = _stroke(color.withValues(alpha: 0.8), 1.1);
    final mods = fmAlgorithmMods[algorithm];
    final carriers = fmAlgorithmCarriers[algorithm];
    for (var to = 0; to < 4; to++) {
      for (var from = 0; from < to; from++) {
        if (mods[to] >> from & 1 == 0) continue;
        final a = at(from), b = at(to);
        final d = (b - a);
        final len = d.distance;
        if (len < 0.1) continue;
        final u = d / len;
        final s = a + u * r, e = b - u * (r + 1.5);
        canvas.drawLine(s, e, line);
        // ponta da seta
        final n = Offset(-u.dy, u.dx);
        canvas.drawPath(
          Path()
            ..moveTo(e.dx, e.dy)
            ..lineTo(e.dx - u.dx * 3.5 + n.dx * 2.2, e.dy - u.dy * 3.5 + n.dy * 2.2)
            ..lineTo(e.dx - u.dx * 3.5 - n.dx * 2.2, e.dy - u.dy * 3.5 - n.dy * 2.2)
            ..close(),
          Paint()..color = color.withValues(alpha: 0.8),
        );
      }
    }
    for (var n = 0; n < 4; n++) {
      final c = at(n);
      final carrier = carriers >> n & 1 == 1;
      if (carrier) canvas.drawLine(c + Offset(0, r), c + Offset(0, r + 4), line);
      canvas.drawCircle(c, r, carrier ? (Paint()..color = color.withValues(alpha: 0.85)) : _stroke(color, 1.2));
      final tp = TextPainter(
        text: TextSpan(
          text: '${n + 1}',
          style: TextStyle(fontSize: r * 1.45, height: 1, fontWeight: FontWeight.w700, color: carrier ? Palette.ink : color),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
    }
    if (feedback > 0) {
      // laço de realimentação sobre o operador 1
      final c = at(0);
      final loop = Rect.fromCircle(center: c + Offset(-r * 1.1, -r * 0.9), radius: r * 0.85);
      canvas.drawArc(loop, 0.6, 4.6, false, _stroke(color.withValues(alpha: 0.4 + 0.6 * feedback.clamp(0.0, 1.0)), 1.1));
    }
  }

  @override
  bool shouldRepaint(_AlgoPainter o) => o.algorithm != algorithm || o.color != color || o.feedback != feedback;
}

/// Atalhos de razão (0,5, 1, 2, 3...): as razões que mais se usa ficam a um toque.
class _RatioChips extends StatelessWidget {
  final List<double> values;
  final double current;
  final Color color;
  final ValueChanged<double> onPick;
  const _RatioChips({required this.values, required this.current, required this.color, required this.onPick});

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 4,
    runSpacing: 4,
    children: [
      for (final r in values)
        GestureDetector(
          onTap: () => onPick(r),
          child: Container(
            height: 20,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: (current - r).abs() < 1e-6 ? color.withValues(alpha: 0.22) : Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: (current - r).abs() < 1e-6 ? color : Palette.hairline),
            ),
            child: Text(
              '×${r == r.roundToDouble() ? r.round() : r}',
              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: (current - r).abs() < 1e-6 ? color : Colors.white60),
            ),
          ),
        ),
    ],
  );
}

// ------------------------------------------------------------------------ wavetable

/// Um ciclo da tabela na posição escolhida (a mistura das duas tabelas vizinhas), com o nível do
/// oscilador como amplitude e uma régua embaixo com as 8 tabelas da série: as duas em jogo acesas
/// e, se o LFO ou o envelope movem a posição, a faixa que eles varrem.
class _TablePainter extends CustomPainter {
  final int series;
  final double pos, level, sweep;
  final Color color;
  _TablePainter({required this.series, required this.pos, required this.level, required this.sweep, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    const ruler = 7.0;
    final mid = (size.height - ruler) / 2;
    final amp = mid - 5;
    canvas.drawLine(Offset(0, mid), Offset(size.width, mid), _grid);
    final n = math.max(64, size.width.ceil());
    final shape = wavetableShape(series, pos, n);
    Path trace(double a) {
      final p = Path();
      for (var i = 0; i <= n; i++) {
        final v = shape[i % n].clamp(-1.6, 1.6) / 1.6;
        final y = mid - v * a;
        i == 0 ? p.moveTo(0, y) : p.lineTo(i * size.width / n, y);
      }
      return p;
    }

    final path = trace(amp);
    canvas.drawPath(path, _stroke(color.withValues(alpha: 0.16), 1.2));
    if (level > 0.001) {
      final live = trace(amp * level.clamp(0.0, 1.0));
      canvas.drawPath(
        Path.from(live)
          ..lineTo(size.width, mid)
          ..lineTo(0, mid)
          ..close(),
        _fill(color, Offset.zero & size),
      );
      canvas.drawPath(live, _stroke(color, 1.6));
    }
    // régua: 8 casas; a faixa varrida em tom fraco e as tabelas vizinhas da posição acesas
    final cell = size.width / wavetableTables;
    final y0 = size.height - ruler + 1, h = ruler - 3;
    if (sweep > 0) {
      final lo = ((pos - sweep).clamp(0.0, 1.0)) * (wavetableTables - 1), hi = ((pos + sweep).clamp(0.0, 1.0)) * (wavetableTables - 1);
      canvas.drawRect(Rect.fromLTRB((lo + 0.5) * cell, y0, (hi + 0.5) * cell, y0 + h), Paint()..color = color.withValues(alpha: 0.22));
    }
    final x = pos.clamp(0.0, 1.0) * (wavetableTables - 1);
    for (var i = 0; i < wavetableTables; i++) {
      final near = (x - i).abs() < 1;
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(i * cell + 2, y0, cell - 4, h), const Radius.circular(1.5)),
        Paint()..color = near ? color.withValues(alpha: 0.35 + 0.65 * (1 - (x - i).abs())) : Colors.white.withValues(alpha: 0.1),
      );
    }
  }

  @override
  bool shouldRepaint(_TablePainter o) => o.series != series || o.pos != pos || o.level != level || o.sweep != sweep || o.color != color;
}

/// O áudio do sampler inteiro, normalizado pelo pico para amostras baixas aparecerem.
class _SampleWavePainter extends CustomPainter {
  final Waveform wave;
  final Color color;
  _SampleWavePainter(this.wave, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final n = wave.mins.length;
    if (n == 0 || size.width <= 0) return;
    var peak = 0.0;
    for (var i = 0; i < n; i++) {
      peak = math.max(peak, math.max(-wave.mins[i], wave.maxs[i]));
    }
    final mid = size.height / 2;
    final amp = (size.height / 2 - 4) / (peak > 1e-4 ? peak : 1);
    canvas.drawLine(Offset(0, mid), Offset(size.width, mid), _grid);
    final paint = Paint()
      ..color = color.withValues(alpha: 0.9)
      ..strokeWidth = 1;
    final cols = size.width.floor();
    for (var x = 0; x < cols; x++) {
      final a = (x * n / cols).floor();
      final b = math.max(a + 1, ((x + 1) * n / cols).floor());
      var lo = 0.0, hi = 0.0;
      for (var i = a; i < b && i < n; i++) {
        if (wave.mins[i] < lo) lo = wave.mins[i];
        if (wave.maxs[i] > hi) hi = wave.maxs[i];
      }
      canvas.drawLine(Offset(x + 0.5, mid - hi * amp), Offset(x + 0.5, mid - lo * amp + 0.5), paint);
    }
  }

  @override
  bool shouldRepaint(_SampleWavePainter o) => o.wave != wave || o.color != color;
}
