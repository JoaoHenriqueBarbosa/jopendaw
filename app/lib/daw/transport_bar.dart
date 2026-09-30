/// Barra do transporte e das ferramentas: tocar, parar, gravar, posição, andamento, loop,
/// metrônomo, edição, grade, zoom, os painéis de baixo (mixer, editor, instrumento, efeitos), as
/// entradas de notas (teclado do computador e MIDI), importar, exportar e as configurações.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/feedback.dart';
import '../widgets/format.dart';
import '../widgets/theme.dart';
import 'controller.dart';
import 'dock.dart';
import 'automation_mode.dart';
import 'export.dart';
import 'history_ui.dart' show HistoryStepButton;
import 'midi_file_ui.dart' show importFiles;
import 'midi_learn_ui.dart' show MidiLearnButton;
import 'mixer_panel.dart' show recordColor;
import 'model.dart';
import 'shortcuts_dialog.dart';
import 'settings_dialog.dart';
import 'structure_menu.dart';
import 'tempo_lane.dart' show showMeterChangeDialog;
import 'tap_tempo.dart';
import 'tempo_map.dart';
import 'tempo_format.dart' show formatBpm, formatDocMeter, formatMeter;
import 'warp_dialog.dart' show parseBpm;
import 'timeline.dart' show deleteSelectedClip, duplicateSelectedClip, splitClipsAtPlayhead;
import 'keymap.dart';

/// Para onde as ações do transporte (botões e atalhos) mandam uma falha que o controlador não
/// transformou em aviso: a tela mostra inline, em vez de a exceção sumir no console. Null: a ação
/// deu certo, e o aviso de uma falha anterior já não vale.
typedef ActionErrorSink = void Function(String? message);

/// Uma falha do gravar, do exportar ou da entrada como a pessoa deve ler: sem o prefixo em inglês
/// das exceções do Dart ("Bad state:", "Exception:").
String describeActionError(Object e) {
  switch (e) {
    // antes do UnsupportedError: o UnimplementedError também é um
    case UnimplementedError():
      return 'Isso ainda não funciona neste aparelho.';
    case UnsupportedError(:final message?):
      return sentence(message);
    case UnsupportedError():
      return 'Isso não funciona neste aparelho.';
    case StateError(:final message):
      return sentence(message);
  }
  final text = '$e';
  const prefix = 'Exception: ';
  return text.startsWith(prefix) ? sentence(text.substring(prefix.length)) : describeError(e);
}

/// Roda [action] e devolve o aviso da falha, ou null quando deu certo.
Future<String?> _attempt(Future<void> Function() action) async {
  try {
    await action();
    return null;
  } catch (e) {
    return describeActionError(e);
  }
}

/// Liga/desliga a gravação (botão e R). Os problemas esperados (sem microfone, nenhuma faixa
/// armada) o controlador mostra em `c.error`; o que escapar dele chega em [onError].
Future<void> toggleRecording(DawController c, ActionErrorSink onError) async => onError(await _attempt(c.toggleRecord));

/// Tocar/pausar (botão e espaço). Gravando, pausar encerra a gravação antes, com os clipes do que
/// foi gravado até ali: senão a captura seguiria com o transporte parado. Se encerrar já parou o
/// transporte, não toca de novo. A falha do encerrar não some porque o pausar deu certo.
Future<void> playOrPause(DawController c, ActionErrorSink onError) async {
  if (!c.recording) return onError(await _attempt(c.togglePlay));
  final recordError = await _attempt(c.toggleRecord);
  final playError = c.playing.value ? await _attempt(c.togglePlay) : null;
  onError(recordError ?? playError);
}

/// Parar e voltar (botão, Enter e Home). Gravando, encerra a gravação primeiro: o fim dos clipes é
/// onde o cursor estava, e o parar leva o cursor de volta ao começo.
Future<void> stopTransport(DawController c, ActionErrorSink onError) async {
  final recordError = c.recording ? await _attempt(c.toggleRecord) : null;
  final stopError = await _attempt(c.stop);
  onError(recordError ?? stopError);
}

/// Largura da barra a partir da qual importar e exportar mostram o nome ao lado do ícone (a barra
/// inteira com os nomes media uns 1520 px e sem eles uns 1350 quando o limite foi escolhido, medido no Chrome;
/// os botões que apareceram depois (aprender MIDI, com a entrada ligada) somam mais, então a medida pode estar
/// um pouco acima. No teste de widget a fonte Ahem alarga os textos e a medida não vale, por isso o número é
/// só a referência: os nomes ocupam uns 100 px a mais que os ícones. O documento cita 1540 px.)
const _labelsWidth = 1540.0;

class TransportBar extends StatelessWidget {
  final DawController c;
  final bool compact;
  final ActionErrorSink onError;
  const TransportBar({super.key, required this.c, required this.compact, required this.onError});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final d = c.doc;
        final recording = c.recording;
        final transport = [
          IconButton(
            tooltip: recording ? 'Parar a gravação e voltar${shortcutHint('transport.stop')}' : 'Parar e voltar${shortcutHint('transport.stop')}',
            onPressed: () => stopTransport(c, onError),
            icon: const Icon(Icons.stop),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: c.playing,
            builder: (_, playing, _) => IconButton.filled(
              tooltip: recording
                  ? 'Parar a gravação${shortcutHint('transport.play')}'
                  : (playing ? 'Pausar${shortcutHint('transport.play')}' : 'Tocar${shortcutHint('transport.play')}'),
              onPressed: () => playOrPause(c, onError),
              icon: Icon(playing ? Icons.pause : Icons.play_arrow),
            ),
          ),
          _RecordButton(c: c, onError: onError),
          // só o ícone: a barra já é apertada; o nome e as opções estão no menu ao lado do gravar
          _Toggle(
            icon: Icons.compare_arrows,
            on: d.punchActive,
            tooltip: d.punchRegion == null
                ? 'Punch${shortcutHint('transport.punch')}: grava só numa região. Ligue e ajuste as pontas na régua'
                : 'Punch${shortcutHint('transport.punch')}: a gravação só vale entre o punch in e o punch out da régua',
            onTap: c.togglePunch,
          ),
          const SizedBox(width: 4),
          _Position(c: c),
          const SizedBox(width: 8),
          // o andamento não muda no meio de uma gravação: as batidas do que já foi gravado mudariam
          // de lugar em relação ao áudio que ainda está chegando
          _TempoButton(c: c, onPressed: recording ? null : () => _editTempo(context)),
          _Toggle(icon: Icons.repeat, on: d.loopOn, tooltip: 'Loop${shortcutHint('transport.loop')} · arraste na régua para marcar', onTap: c.toggleLoop),
          _Toggle(icon: Icons.av_timer, on: d.metronome, tooltip: 'Metrônomo${shortcutHint('transport.metronome')}', onTap: c.toggleMetronome),
        ];
        // desfazer no meio da gravação poderia apagar ou mover a faixa que está recebendo o áudio
        final tools = [
          HistoryStepButton(c: c, redo: false, blocked: recording),
          HistoryStepButton(c: c, redo: true, blocked: recording),
          IconButton(tooltip: 'Cortar no cursor${shortcutHint('edit.split')}', onPressed: () => splitClipsAtPlayhead(c), icon: const Icon(Icons.content_cut)),
          IconButton(
            tooltip: 'Duplicar${shortcutHint('edit.duplicate')}',
            onPressed: c.selectedClip == null ? null : () => duplicateSelectedClip(c),
            icon: const Icon(Icons.copy_all),
          ),
          IconButton(
            tooltip: 'Apagar o clipe (Delete)',
            onPressed: c.selectedClip == null ? null : () => deleteSelectedClip(c),
            icon: const Icon(Icons.delete_outline),
          ),
          PopupMenuButton<Snap>(
            tooltip: 'Grade de encaixe (Alt ao arrastar: livre)',
            initialValue: c.snap,
            onSelected: c.setSnap,
            itemBuilder: (_) => [for (final s in Snap.values) PopupMenuItem(value: s, child: Text(s.label))],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(children: [const Icon(Icons.grid_4x4, size: 18), const SizedBox(width: 4), Text(c.snap.label)]),
            ),
          ),
          AutoModeMenu(c: c, compact: compact),
          IconButton(tooltip: 'Afastar', onPressed: () => c.zoom(1 / 1.5), icon: const Icon(Icons.zoom_out)),
          IconButton(tooltip: 'Aproximar', onPressed: () => c.zoom(1.5), icon: const Icon(Icons.zoom_in)),
          _Toggle(icon: Icons.my_location, on: c.follow, tooltip: 'Seguir o cursor na reprodução', onTap: c.toggleFollow),
          ViewMenu(c: c),
          SectionsMenu(c: c),
          // o tempo total fica só em janelas largas: em 1512 px ele empurrava a engrenagem e os atalhos para fora
          if (MediaQuery.sizeOf(context).width >= 1640) DurationLabel(c: c),
        ];
        final panels = [
          _Toggle(icon: Icons.tune, on: c.dock == Dock.mixer, tooltip: 'Mixer${shortcutHint('panel.mixer')}', onTap: () => toggleDock(c, Dock.mixer)),
          _Toggle(
            icon: Icons.edit_note,
            on: c.dock == Dock.editor,
            tooltip: 'Editor de notas${shortcutHint('panel.editor')}',
            onTap: () => toggleDock(c, Dock.editor),
          ),
          _Toggle(
            icon: dockInstrumentIcon(c),
            on: c.dock == Dock.instrument,
            tooltip: 'Instrumento da faixa${shortcutHint('panel.instrument')}',
            onTap: () => toggleDock(c, Dock.instrument),
          ),
          _Toggle(
            icon: Icons.auto_fix_high,
            on: c.dock == Dock.effects,
            tooltip: 'Efeitos da faixa${shortcutHint('panel.effects')}',
            onTap: () => toggleDock(c, Dock.effects),
          ),
        ];
        final velocity = (c.keyboardVelocity * 100).round();
        final inputs = [
          _Toggle(
            icon: Icons.keyboard,
            on: c.keyboardOn,
            // a oitava à vista (é o que muda com Z/X sem outro retorno na tela) e o aviso de que as letras
            // viraram notas: os atalhos delas ficam suspensos até desligar
            label: c.keyboardOn ? 'C${c.keyboardOctave} · sem atalhos' : null,
            tooltip: keyboardTooltip(on: c.keyboardOn, octave: c.keyboardOctave, velocityPercent: velocity),
            onTap: c.toggleKeyboard,
          ),
          _Toggle(
            icon: Icons.cable,
            on: c.midiEnabled,
            label: c.midiInputs.isEmpty ? (c.midiEnabled ? '0' : null) : '${c.midiInputs.length}',
            tooltip: !c.midiEnabled
                ? 'Entrada MIDI: ligar teclado ou controlador'
                : c.midiInputs.isEmpty
                ? 'MIDI ligado, nenhum aparelho conectado: conecte e ele aparece aqui sozinho'
                : 'Entrada MIDI: ${c.midiInputs.join(', ')}',
            onTap: c.enableMidiInput,
          ),
          // só com o MIDI ligado (ou já em uso): sem controlador o botão só gastaria largura da barra
          if (c.midiEnabled || c.midiLearn.learning || !c.doc.midiMap.isEmpty) MidiLearnButton(c: c),
        ];
        const divider = Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: SizedBox(width: 1, height: 28, child: ColoredBox(color: Palette.hairline)),
        );
        // importar e exportar mexem no documento inteiro: nem no meio de outro trabalho nem no de
        // uma gravação (uma faixa nova no meio mudaria o lugar das armadas)
        final idle = c.status == null && !recording;
        void export() => showExportDialog(context, c);
        // só o ícone no celular e em tela estreita: a barra rola na horizontal, mas o texto
        // empurraria as configurações para fora da vista num notebook comum
        List<Widget> files(bool labels) => !labels
            ? [
                IconButton.filledTonal(
                  tooltip: 'Importar áudio ou MIDI${shortcutHint('edit.import')}',
                  onPressed: idle ? () => importFiles(context, c) : null,
                  icon: const Icon(Icons.file_open_outlined),
                ),
                const SizedBox(width: 4),
                IconButton.filledTonal(
                  tooltip: recording ? 'Pare a gravação para exportar' : 'Exportar áudio (WAV, FLAC ou MP3)',
                  onPressed: idle ? export : null,
                  icon: const Icon(Icons.save_alt),
                ),
              ]
            : [
                FilledButton.tonalIcon(
                  onPressed: idle ? () => importFiles(context, c) : null,
                  icon: const Icon(Icons.file_open_outlined),
                  label: const Text('Importar'),
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: recording ? 'Pare a gravação para exportar' : 'Exportar áudio (WAV, FLAC ou MP3)',
                  child: FilledButton.tonalIcon(onPressed: idle ? export : null, icon: const Icon(Icons.save_alt), label: const Text('Exportar')),
                ),
              ];
        // largura toda: dentro da coluna da tela a barra encolhia até o conteúdo e ficava centralizada
        return LayoutBuilder(
          builder: (context, box) => Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              color: Palette.bar,
              border: Border.symmetric(horizontal: BorderSide(color: Palette.hairline)),
            ),
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  children: [
                    ...transport,
                    const SizedBox(width: 4),
                    divider,
                    ...tools,
                    divider,
                    ...panels,
                    divider,
                    ...inputs,
                    const SizedBox(width: 12),
                    ...files(!compact && box.maxWidth >= _labelsWidth),
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: 'Configurações: entrada de áudio, latência e contagem',
                      onPressed: () => showSettingsDialog(context, c),
                      icon: const Icon(Icons.settings_outlined),
                    ),
                    // em janelas estreitas os atalhos ficam na tecla ? e nas Configurações: o botão não cabe
                    if (MediaQuery.sizeOf(context).width >= 1640)
                      IconButton(
                        tooltip: 'Atalhos do teclado${shortcutHint('help.shortcuts')}',
                        onPressed: () => showShortcuts(context),
                        icon: const Icon(Icons.keyboard_command_key),
                      ),
                    if (c.status != null) ...[
                      const SizedBox(width: 12),
                      const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                      const SizedBox(width: 8),
                      Text(c.status!, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _editTempo(BuildContext context) async {
    final r = await showDialog<(double, int)>(
      context: context,
      builder: (_) => _TempoDialog(bpm: c.doc.bpm, beatsPerBar: c.doc.beatsPerBar, initialMeter: c.doc.meter.first, mapped: !c.doc.tempo.isSingle),
    );
    if (r == null) return;
    // (0, 0): o botão "Mudar compasso a partir de…" do diálogo
    if (r.$1 == 0) {
      if (context.mounted) await showMeterChangeDialog(context, c);
      return;
    }
    // 0 tempos: o compasso inicial não é n/4 e a pessoa o deixou como está
    await c.setTempo(r.$1, r.$2 == 0 ? c.doc.beatsPerBar : r.$2, keepMeter: r.$2 == 0);
  }
}

/// O andamento e o compasso no cursor: com um andamento só, "120 BPM · 4/4"; com mapa, o vigente na
/// posição do cursor (com o marcador de mapa) e o compasso dali. Clicar edita o inicial e abre a
/// mudança de compasso.
class _TempoButton extends StatelessWidget {
  final DawController c;
  final VoidCallback? onPressed;
  const _TempoButton({required this.c, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(fontFeatures: [FontFeature.tabularFigures()]);
    final d = c.doc;
    // batendo o tap tempo, o botão mostra o andamento que as batidas dão (o projeto muda quando elas param)
    return ValueListenableBuilder<double?>(
      valueListenable: c.tapBpm,
      builder: (context, tap, _) => tap == null
          ? _plain(context, d, style)
          : TextButton(
              onPressed: onPressed,
              child: Text('Tap · ${formatBpm(tap)} BPM', style: style.copyWith(color: Palette.accent)),
            ),
    );
  }

  Widget _plain(BuildContext context, DawDoc d, TextStyle style) {
    if (d.tempo.isSingle && d.meter.isSingle) {
      return TextButton(
        onPressed: onPressed,
        child: Text('${formatBpm(d.bpm)} BPM · ${formatDocMeter(d)}', style: style),
      );
    }
    return ValueListenableBuilder<double>(
      valueListenable: c.beat,
      builder: (context, beat, _) {
        final b = math.max(0.0, beat);
        final bpm = d.bpmAt(b);
        final m = d.meter.changeAt(d.meter.barOf(b).$1);
        final at = d.tempo.indexAt(b);
        final ramp = !d.tempo.isSingle && d.tempo.points[at].ramp && at + 1 < d.tempo.points.length && d.tempo.points[at].bpm != d.tempo.points[at + 1].bpm;
        // a rampa desce quando o ponto seguinte é mais lento
        final falling = ramp && d.tempo.points[at + 1].bpm < d.tempo.points[at].bpm;
        return Tooltip(
          message: d.tempo.isSingle
              ? 'Compasso no cursor. Clique para editar o andamento ou mudar o compasso.'
              : 'Andamento no cursor (mapa com ${d.tempo.points.length} pontos, inicial ${formatBpm(d.bpm)} BPM). Clique para editar o inicial ou mudar o compasso.',
          child: TextButton(
            onPressed: onPressed,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!d.tempo.isSingle) const Icon(Icons.show_chart, size: 14, color: Palette.accent),
                if (!d.tempo.isSingle) const SizedBox(width: 4),
                Text('${formatBpm(bpm)}${ramp ? (falling ? '↘' : '↗') : ''} BPM · ${formatMeter(m.numerator, m.denominator)}', style: style),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Gravar: o círculo vermelho, aceso gravando e piscando no andamento durante a contagem. A seta
/// ao lado abre as opções (contagem, configurações de gravação).
class _RecordButton extends StatefulWidget {
  final DawController c;
  final ActionErrorSink onError;
  const _RecordButton({required this.c, required this.onError});

  @override
  State<_RecordButton> createState() => _RecordButtonState();
}

enum _RecordMenu { countIn, punch, settings }

class _RecordButtonState extends State<_RecordButton> with SingleTickerProviderStateMixin {
  /// Um ciclo por batida: aceso na primeira metade, apagado na segunda.
  late final _blink = AnimationController(vsync: this);

  DawController get c => widget.c;

  @override
  void initState() {
    super.initState();
    _syncBlink();
  }

  @override
  void didUpdateWidget(_RecordButton old) {
    super.didUpdateWidget(old);
    _syncBlink();
  }

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  /// Pisca só na contagem, no andamento do projeto: o que se vê bate com os cliques que se ouvem.
  void _syncBlink() {
    if (c.countingIn) {
      final beat = Duration(microseconds: (60e6 / c.doc.bpm.clamp(minBpm, maxBpm)).round());
      if (!_blink.isAnimating || _blink.duration != beat) {
        _blink.duration = beat;
        _blink.repeat();
      }
    } else if (_blink.isAnimating || _blink.value != 0) {
      _blink
        ..stop()
        ..value = 0;
    }
  }

  void _menu(_RecordMenu v) {
    switch (v) {
      case _RecordMenu.countIn:
        c.toggleCountIn();
      case _RecordMenu.punch:
        c.togglePunch();
      case _RecordMenu.settings:
        showSettingsDialog(context, c);
    }
  }

  String _tooltip() {
    if (c.countingIn) return 'Contando o compasso de entrada: toque para cancelar${shortcutHint('transport.record')}';
    if (c.recording) return 'Gravando: toque para parar${shortcutHint('transport.record')}';
    final armed = c.doc.tracks.where((t) => t.armed && t.kind.hasClips).length;
    final count =
        '${c.doc.countIn ? ', com um compasso de contagem' : ''}'
        '${c.doc.preRollBars > 0 ? ', ${c.doc.preRollBars} de pré-roll' : ''}'
        '${c.doc.punchActive ? ', só na região de punch' : ''}';
    return switch (armed) {
      0 => 'Gravar${shortcutHint('transport.record')}: nenhuma faixa armada; arme no mixer (●)',
      1 => 'Gravar${shortcutHint('transport.record')} na faixa armada$count',
      _ => 'Gravar${shortcutHint('transport.record')} nas $armed faixas armadas$count',
    };
  }

  @override
  Widget build(BuildContext context) {
    final recording = c.recording;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: _tooltip(),
          child: Semantics(
            button: true,
            toggled: recording,
            label: 'Gravar',
            child: AnimatedBuilder(
              animation: _blink,
              builder: (context, _) {
                final lit = recording && (!c.countingIn || _blink.value < 0.5);
                return IconButton(
                  onPressed: () => toggleRecording(c, widget.onError),
                  style: IconButton.styleFrom(
                    backgroundColor: lit ? recordColor : Colors.transparent,
                    side: BorderSide(color: recording ? recordColor : Colors.transparent),
                  ),
                  icon: Icon(Icons.fiber_manual_record, color: lit ? Colors.white : recordColor),
                );
              },
            ),
          ),
        ),
        PopupMenuButton<Object>(
          tooltip: 'Opções de gravação',
          position: PopupMenuPosition.under,
          // o menu leva o pré-roll (o número de compassos) e as ações
          onSelected: (v) => v is int ? c.setPreRoll(v) : _menu(v as _RecordMenu),
          itemBuilder: (_) => [
            CheckedPopupMenuItem<Object>(value: _RecordMenu.countIn, checked: c.doc.countIn, child: const Text('Contagem de um compasso')),
            CheckedPopupMenuItem<Object>(value: _RecordMenu.punch, checked: c.doc.punchActive, child: Text('Punch in/out${shortcutHint('transport.punch')}')),
            const PopupMenuDivider(),
            const PopupMenuItem<Object>(enabled: false, height: 28, child: Text('Pré-roll: toca a música antes de gravar')),
            for (var n = 0; n <= DawDoc.maxPreRollBars; n++)
              CheckedPopupMenuItem<Object>(
                value: n,
                checked: c.doc.preRollBars == n,
                child: Text(n == 0 ? 'Sem pré-roll' : (n == 1 ? '1 compasso' : '$n compassos')),
              ),
            const PopupMenuDivider(),
            const PopupMenuItem<Object>(
              value: _RecordMenu.settings,
              child: Row(
                children: [
                  Icon(Icons.settings_outlined, size: 18),
                  SizedBox(width: 12),
                  Flexible(child: Text('Configurações de gravação…', overflow: TextOverflow.ellipsis)),
                ],
              ),
            ),
          ],
          child: const SizedBox(width: 20, height: 40, child: Icon(Icons.arrow_drop_down, size: 18, color: Colors.white54)),
        ),
      ],
    );
  }
}

class _Position extends StatelessWidget {
  final DawController c;
  const _Position({required this.c});

  @override
  Widget build(BuildContext context) {
    final mono = Theme.of(context).textTheme.titleMedium!.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    return ValueListenableBuilder<double>(
      valueListenable: c.beat,
      builder: (_, beat, _) {
        // antes do zero (a contagem que começa um compasso antes do cursor, se o motor andar por
        // ali) mostra as batidas que faltam, em vez de um "1.1.1" parado e um tempo "0:-2.00"
        final before = beat < 0;
        final secs = before ? beat.abs() * 60 / c.doc.bpm : c.doc.secondsAt(beat);
        final m = secs ~/ 60, s = secs - m * 60;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: Palette.ink, borderRadius: BorderRadius.circular(6)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                before ? '−${(-beat).ceil()}' : formatPosition(beat, c.doc.beatsPerBar, meter: c.doc.meter),
                style: mono.copyWith(color: before ? recordColor : Palette.accent),
              ),
              Text(
                '${before ? '−' : ''}$m:${s.toStringAsFixed(2).padLeft(5, '0')}',
                style: Theme.of(context).textTheme.labelSmall!.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Botão de ligar e desligar: aceso na cor da marca. Com [label], mostra um valor ao lado do
/// ícone (a oitava do teclado, quantas entradas MIDI).
class _Toggle extends StatelessWidget {
  final IconData icon;
  final bool on;
  final String tooltip;
  final String? label;
  final VoidCallback onTap;
  const _Toggle({required this.icon, required this.on, required this.tooltip, required this.onTap, this.label});

  @override
  Widget build(BuildContext context) {
    if (label == null) {
      return IconButton(
        tooltip: tooltip,
        onPressed: onTap,
        isSelected: on,
        style: IconButton.styleFrom(foregroundColor: Colors.white70),
        selectedIcon: Icon(icon, color: Palette.accent),
        icon: Icon(icon),
      );
    }
    return Tooltip(
      message: tooltip,
      child: TextButton.icon(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: on ? Palette.accent : Colors.white70,
          backgroundColor: on ? Palette.accent.withValues(alpha: 0.1) : null,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          minimumSize: const Size(40, 40),
        ),
        icon: Icon(icon),
        label: Text(
          label!,
          style: const TextStyle(fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()]),
        ),
      ),
    );
  }
}

class _TempoDialog extends StatefulWidget {
  final double bpm;
  final int beatsPerBar;

  /// O compasso inicial do documento: se não for n/4 (6/8, 7/8…), o seletor de tempos por compasso
  /// o mostra como está e só o troca se a pessoa escolher outro.
  final MeterChange initialMeter;

  /// O documento tem mudanças de andamento: o BPM daqui é o inicial.
  final bool mapped;
  const _TempoDialog({required this.bpm, required this.beatsPerBar, required this.initialMeter, this.mapped = false});
  @override
  State<_TempoDialog> createState() => _TempoDialogState();
}

class _TempoDialogState extends State<_TempoDialog> {
  // valor todo selecionado: digitar substitui em vez de emendar no número que já estava
  late final _bpm = TextEditingController(text: formatBpm(widget.bpm))..selection = TextSelection(baseOffset: 0, extentOffset: formatBpm(widget.bpm).length);
  late final bool _custom = widget.initialMeter.denominator != 4;
  // 0: o compasso inicial (que não é n/4) como está
  late int _bpb = _custom ? 0 : widget.beatsPerBar;
  String? _error;
  final _tap = TapTempo();
  final _tapClock = Stopwatch()..start();

  /// Uma batida do tap: o BPM do campo acompanha a média das últimas (salvar aplica ao projeto).
  void _tapped() {
    final v = _tap.tap(_tapClock.elapsedMicroseconds / 1e6);
    if (v == null) return;
    setState(() {
      _error = null;
      _bpm.text = formatBpm(v);
      _bpm.selection = TextSelection(baseOffset: 0, extentOffset: _bpm.text.length);
    });
  }

  void _save() {
    final v = parseBpm(_bpm.text);
    if (v == null) {
      setState(() => _error = 'Entre $minBpmInt e $maxBpmInt (aceita decimais, como 120,5).');
      return;
    }
    // uma casa decimal: é a resolução do resto do app (pontos do mapa, rótulos)
    Navigator.pop(context, ((v * 10).round() / 10, _bpb));
  }

  @override
  void dispose() {
    _bpm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Andamento e compasso'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _bpm,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
          decoration: InputDecoration(labelText: widget.mapped ? 'BPM inicial' : 'BPM', errorText: _error),
          onSubmitted: (_) => _save(),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: Tooltip(
            message: 'Bata no ritmo: o BPM acima segue a média das últimas batidas (a tecla T faz o mesmo fora desta janela)',
            child: OutlinedButton.icon(onPressed: _tapped, icon: const Icon(Icons.touch_app_outlined), label: const Text('Tap tempo')),
          ),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<int>(
          initialValue: _bpb,
          decoration: const InputDecoration(labelText: 'Tempos por compasso'),
          items: [
            if (_custom) DropdownMenuItem(value: 0, child: Text('${formatMeter(widget.initialMeter.numerator, widget.initialMeter.denominator)} (atual)')),
            // 1/4 a 32/4, o limite do documento e da importação do .mid; o valor de agora aparece mesmo se passasse
            for (var i = 1; i <= math.max(32, _custom ? 0 : widget.beatsPerBar); i++) DropdownMenuItem(value: i, child: Text('$i/4')),
          ],
          onChanged: (v) => setState(() => _bpb = v ?? _bpb),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(onPressed: () => Navigator.pop(context, (0.0, 0)), child: const Text('Mudar compasso a partir de um compasso…')),
        ),
      ],
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
      FilledButton(onPressed: _save, child: const Text('Salvar')),
    ],
  );
}
