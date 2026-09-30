part of 'piano_roll.dart';

// ---------------------------------------------------------------------- preferências

/// Grade do editor de notas, independente da grade do arranjo. Em batidas; 0 = livre.
enum _Grid {
  quarter('1/4', 1),
  eighth('1/8', .5),
  sixteenth('1/16', .25),
  thirtySecond('1/32', .125),
  eighthTriplet('1/8T', 1 / 3),
  sixteenthTriplet('1/16T', 1 / 6),
  off('Livre', 0);

  final String label;
  final double beats;
  const _Grid(this.label, this.beats);
}

/// Lápis (clique vazio cria nota) ou seleção (arraste vazio seleciona por retângulo).
enum _Tool { draw, select }

/// Duração da nota nova.
class _Length {
  final String label, short;

  /// Em batidas; 0 segue a grade, -1 repete a última usada.
  final double beats;
  const _Length(this.label, this.short, this.beats);
}

const _lengths = [
  _Length('Seguir a grade', 'grade', 0),
  _Length('Última usada', 'última', -1),
  _Length('1/32', '1/32', .125),
  _Length('1/16', '1/16', .25),
  _Length('1/8', '1/8', .5),
  _Length('1/4', '1/4', 1),
  _Length('1/2', '1/2', 2),
  _Length('1/1', '1/1', 4),
];

/// Preferências do editor: valem para a sessão toda, de um clipe para outro.
abstract final class _Prefs {
  static var grid = _Grid.sixteenth;
  static var length = 0;
  static var tool = _Tool.draw;
  static var velocityLane = true;
  static var preview = true;
  static var strength = 1.0;
  static var ends = false;

  /// Prender na escala do clipe (notas desenhadas, movidas e coladas).
  static var snapScale = false;

  /// Fantasmas: notas dos outros clipes da faixa e das outras faixas de instrumento, em cinza.
  static var ghostSame = true;
  static var ghostOthers = false;

  /// Acorde que o clique numa área vazia cria no lugar de uma nota só (null = desligado).
  static _Stamp? chordStamp;

  /// Último acorde escolhido no diálogo (o ponto de partida do próximo).
  static var chordType = 'maj';
  static var chordInversion = 0;

  static var arpPattern = ArpPattern.up;
  static var arpRate = 4;
  static var arpOctaves = 1;
  static var arpGate = .9;
  static var humTiming = .5;
  static var humVelocity = .5;
  static var staccato = .5;

  /// A semente cresce a cada uso (arpejo aleatório, humanizar): repetir dá outro resultado.
  static var seed = 1;
  static double? panelHeight;
  static var lastLength = 1.0;
  static var lastVelocity = .8;

  /// Zoom e rolagem de cada clipe já aberto, para reabrir onde estava.
  static final views = <String, _View>{};

  /// Notas copiadas, com o início contado da primeira; serve para colar em qualquer clipe.
  static var clipboard = const <MidiNote>[];
}

/// Um acorde para carimbar no clique: o tipo (id de `chordTypes` ou diatônico) e a inversão.
class _Stamp {
  final String type;
  final int inversion;
  const _Stamp(this.type, this.inversion);
}

// ---------------------------------------------------------------------- medidas

/// Tamanhos fixos do editor; no toque as linhas e alças crescem.
class _Dims {
  final bool coarse, drums;
  const _Dims({required this.coarse, required this.drums});

  static const toolbar = 44.0;
  static const handle = 6.0;

  double get ruler => coarse ? 28 : 24;
  double get keys => drums ? (coarse ? 112 : 136) : (coarse ? 56 : 50);
  double get velocity => coarse ? 84 : 72;
  double get row => drums ? (coarse ? 34 : 24) : (coarse ? 22 : 14);
  double get rowMin => drums ? 14 : 6;
  double get rowMax => drums ? 72 : 44;
}

/// Zoom e rolagem do editor: batidas contadas do início do clipe, linhas de cima para baixo.
class _View {
  double ppb, rowH, scrollX, scrollY;
  _View({required this.ppb, required this.rowH}) : scrollX = 0, scrollY = 0;
}

/// As linhas do editor, de cima para baixo. No teclado melódico, uma por semitom (C0..C8, ou
/// mais se alguma nota passa disso); na bateria, as peças do kit mais as alturas soltas que
/// alguma nota use, ordenadas pela nota.
class _Rows {
  final bool drums;
  final List<int> pitches;
  final Map<int, int> _index;
  _Rows._(this.drums, this.pitches) : _index = {for (var i = 0; i < pitches.length; i++) pitches[i]: i};

  factory _Rows.melodic(int lo, int hi) => _Rows._(false, [for (var p = hi; p >= lo; p--) p]);

  factory _Rows.kit(Set<int> extra) {
    final all = {..._drumPitches, ...extra}.toList()..sort((a, b) => b.compareTo(a));
    return _Rows._(true, all);
  }

  int get length => pitches.length;
  int? rowOf(int pitch) => _index[pitch];
  int? pitchAt(int row) => row >= 0 && row < pitches.length ? pitches[row] : null;
}

final _drumPitches = {for (final p in drumPieces) p.pitch};

/// Notas vizinhas do General MIDI que o motor também aceita na bateria, com a nota da peça que
/// tocam (espelho de `drum_param::piece_for` em `engine/src/instrument.rs`, só para os rótulos).
const _drumAliases = {35: 36, 40: 38, 44: 42, 43: 41, 47: 45, 50: 48, 52: 49, 55: 49, 57: 49, 53: 51, 59: 51};

/// Rótulo de uma altura na bateria: a peça, a peça que a nota vizinha aciona ou "sem peça".
(String, _DrumRow) _drumLabel(int pitch) {
  final exact = drumNameFor(pitch);
  if (exact != null) return (exact, _DrumRow.piece);
  final alias = _drumAliases[pitch];
  if (alias != null) return (drumNameFor(alias)!, _DrumRow.alias);
  return ('sem peça', _DrumRow.silent);
}

enum _DrumRow { piece, alias, silent }

/// Foto da visão para pintar e converter coordenadas (tela ↔ batidas e linhas).
class _Geo {
  final double ppb, rowH, scrollX, scrollY;
  final _Rows rows;
  _Geo(_View v, this.rows) : ppb = v.ppb, rowH = v.rowH, scrollX = v.scrollX, scrollY = v.scrollY;

  double x(double beat) => (beat - scrollX) * ppb;
  double beatAt(double x) => scrollX + x / ppb;
  double y(int row) => row * rowH - scrollY;
  double rowAtF(double y) => (y + scrollY) / rowH;
  int rowAt(double y) => rowAtF(y).floor();

  /// Fim das linhas na tela (abaixo disso não há teclas).
  double get bottom => y(rows.length);

  bool same(_Geo o) => o.ppb == ppb && o.rowH == rowH && o.scrollX == scrollX && o.scrollY == scrollY && identical(o.rows, rows);
}

// ---------------------------------------------------------------------- utilidades

/// Margem de cima e de baixo da faixa de velocidade.
const _velPad = 6.0;

double _velY(double v, double h) => _velPad + (1 - v) * math.max(1.0, h - 2 * _velPad);
double _velAt(double y, double h) => _vel127(1 - (y - _velPad) / math.max(1.0, h - 2 * _velPad));

/// Velocidade nos 127 degraus do MIDI (nunca zero: nota com velocidade 0 é nota desligada).
double _vel127(double v) => (v * 127).round().clamp(1, 127) / 127;

/// Tira o ruído de ponto flutuante das somas (tercinas), para o documento não guardar 0.30000000000000004.
double _tidy(double v) => (v * 1e9).roundToDouble() / 1e9;

bool _near(double x) => (x - x.roundToDouble()).abs() < 1e-6;

/// De quantos em quantos compassos marcar, para as marcas ficarem a pelo menos [minPx].
int _barStep(double barPx, double minPx) {
  if (barPx <= 0) return 1;
  var s = 1;
  while (barPx * s < minPx) {
    s *= 2;
  }
  return s;
}

final _colorCache = <int, List<Color>>{};

/// A cor da faixa em 128 tons pela velocidade: fraca é escura e apagada, forte é clara e viva.
List<Color> _velocityColors(Color base) => _colorCache.putIfAbsent(base.toARGB32(), () {
  final hsl = HSLColor.fromColor(base);
  return List.generate(128, (i) {
    final v = i / 127;
    return hsl.withSaturation((hsl.saturation * (.35 + .65 * v)).clamp(0.0, 1.0)).withLightness(.22 + .4 * v).toColor();
  });
});

Color _velColor(List<Color> colors, double v) => colors[(v * 127).round().clamp(0, 127)];

/// Duração em figura musical (1/16, 3/8, 1/8T), ou em tempos quando não é nenhuma.
String _formatLength(double beats) {
  final whole = beats / 4;
  for (final d in const [1, 2, 4, 8, 16, 32, 64]) {
    final n = whole * d;
    if (n.round() > 0 && _near(n)) return '${n.round()}/$d';
  }
  // tercinas: três no lugar de duas
  for (final d in const [2, 4, 8, 16, 32]) {
    final n = whole * d * 1.5;
    if (n.round() > 0 && _near(n)) return '${n.round()}/${d}T';
  }
  return '${beats.toStringAsFixed(3)} tempos';
}

/// Duração em compassos e tempos ("2 compassos", "1 compasso e 2 tempos").
String _formatSpan(double beats, int beatsPerBar) {
  final bars = (beats / beatsPerBar + 1e-9).floor();
  final rest = beats - bars * beatsPerBar;
  final parts = <String>[
    if (bars > 0) '$bars ${bars == 1 ? 'compasso' : 'compassos'}',
    if (rest > 1e-6) rest == rest.roundToDouble() ? '${rest.round()} ${rest.round() == 1 ? 'tempo' : 'tempos'}' : _formatLength(rest),
  ];
  return parts.isEmpty ? '0' : parts.join(' e ');
}

/// Reconhece o segundo clique (ou toque) de um duplo, perto no tempo e no espaço.
class _Clicks {
  Duration? _time;
  Offset? _pos;

  bool hit(Duration t, Offset p) {
    final pt = _time, pp = _pos;
    final dbl = pt != null && pp != null && t - pt < const Duration(milliseconds: 380) && (p - pp).distance < 8;
    // um terceiro clique começa outra contagem, não vira outro duplo
    _time = dbl ? null : t;
    _pos = p;
    return dbl;
  }
}
