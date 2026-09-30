// Ferramentas MIDI de produtor (midi_tools.dart): funções puras sobre listas de notas.
import 'package:flutter_test/flutter_test.dart';
import 'package:jopendaw_app/daw/midi_tools.dart';
import 'package:jopendaw_app/daw/model.dart';

MidiNote n(int pitch, double start, [double length = 1, double velocity = .8]) => MidiNote(pitch: pitch, start: start, length: length, velocity: velocity);

List<int> pitches(List<MidiNote> l) => [for (final x in l) x.pitch];
List<double> starts(List<MidiNote> l) => [for (final x in l) x.start];
List<double> lengths(List<MidiNote> l) => [for (final x in l) x.length];

Scale sc(String id) => scaleById(id)!;

List<int> inKey(int lo, int hi, int root, String id, {bool mod = false}) => [
  for (var p = lo; p < hi; p++)
    if (inScale(p, root, sc(id))) (mod ? p % 12 : p),
];

void main() {
  group('escalas', () {
    test('todas as escalas têm tônica 0, intervalos crescentes e dentro da oitava', () {
      final ids = <String>{};
      for (final s in scales) {
        expect(ids.add(s.id), isTrue, reason: 'id repetido ${s.id}');
        expect(s.intervals.first, 0);
        for (var i = 1; i < s.intervals.length; i++) {
          expect(s.intervals[i], greaterThan(s.intervals[i - 1]), reason: s.id);
        }
        expect(s.intervals.last, lessThan(12));
      }
      expect(scales.length, greaterThanOrEqualTo(15));
    });

    test('inScale e escalas conhecidas', () {
      // dó maior: só as brancas
      final major = inKey(60, 72, 0, 'major');
      expect(major, [60, 62, 64, 65, 67, 69, 71]);
      // lá menor natural tem as mesmas notas
      expect(inKey(60, 72, 9, 'minor'), major);
      // pentatônica menor de lá: A C D E G
      expect(inKey(57, 69, 9, 'pentatonicMinor'), [57, 60, 62, 64, 67]);
      // blues de dó: C Eb F Gb G Bb
      expect(inKey(60, 72, 0, 'blues'), [60, 63, 65, 66, 67, 70]);
      // tons inteiros
      expect(inKey(60, 72, 0, 'wholeTone'), [60, 62, 64, 66, 68, 70]);
      // cromática: tudo
      expect(inKey(60, 72, 3, 'chromatic').length, 12);
    });

    test('modos gregos a partir de ré', () {
      // dórico de ré = as brancas
      expect(inKey(62, 74, 2, 'dorian', mod: true), [2, 4, 5, 7, 9, 11, 0]);
      // lídio de ré tem a 4ª aumentada (G#) e sem a 4ª justa (G)
      expect(inScale(68, 2, sc('lydian')), isTrue);
      expect(inScale(67, 2, sc('lydian')), isFalse);
      // frígio de ré tem a 2ª menor (Eb)
      expect(inScale(63, 2, sc('phrygian')), isTrue);
      expect(inScale(64, 2, sc('phrygian')), isFalse);
      // mixolídio de dó tem a 7ª menor
      expect(inScale(70, 0, sc('mixolydian')), isTrue);
      expect(inScale(71, 0, sc('mixolydian')), isFalse);
      // lócrio de si: as brancas
      expect(inKey(59, 71, 11, 'locrian', mod: true), [11, 0, 2, 4, 5, 7, 9]);
    });

    test('menor harmônica e melódica de lá', () {
      expect(inKey(57, 69, 9, 'harmonicMinor', mod: true), [9, 11, 0, 2, 4, 5, 8]);
      expect(inKey(57, 69, 9, 'melodicMinor', mod: true), [9, 11, 0, 2, 4, 6, 8]);
    });

    test('snapToScale: dentro fica; fora vai para a mais próxima, empate para baixo', () {
      final major = sc('major');
      expect(snapToScale(60, 0, major), 60);
      expect(snapToScale(61, 0, major), 60); // C#: entre C e D, empate, desce
      expect(snapToScale(63, 0, major), 62); // D#: entre D e E, desce
      expect(snapToScale(66, 0, major), 65); // F#: entre F e G
      expect(snapToScale(70, 0, major), 69); // A#: entre A e B
      // com preferUp o empate sobe
      expect(snapToScale(61, 0, major, preferUp: true), 62);
      expect(snapToScale(66, 0, major, preferUp: true), 67);
      // mais perto de um lado que do outro: dó ré mi sol lá
      final pent = sc('pentatonicMajor');
      expect(snapToScale(65, 0, pent), 64); // F: E a 1, G a 2
      expect(snapToScale(66, 0, pent), 67); // F#: G a 1, E a 2
      expect(snapToScale(71, 0, pent), 72); // B: C a 1, A a 2
    });

    test('snapToScale com tônica diferente e nos limites do MIDI', () {
      // ré menor: D E F G A Bb C
      expect(snapToScale(71, 2, sc('minor')), 70); // B -> Bb
      expect(snapToScale(0, 0, sc('major')), 0);
      expect(snapToScale(127, 0, sc('major')), 127); // G
      expect(snapToScale(126, 0, sc('major')), 125); // F#: desce
      expect(snapToScale(1, 1, sc('pentatonicMajor')), 1);
      // cromática nunca muda
      for (var p = 0; p < 128; p++) {
        expect(snapToScale(p, 5, sc('chromatic')), p);
      }
    });

    test('snapToScale sempre devolve nota da escala e nunca anda mais que o necessário', () {
      for (final s in scales) {
        for (var root = 0; root < 12; root++) {
          for (var p = 12; p < 120; p++) {
            final r = snapToScale(p, root, s);
            expect(inScale(r, root, s), isTrue, reason: '${s.id} $root $p');
            // nenhuma nota da escala está mais perto
            for (var q = p - 12; q <= p + 12; q++) {
              if (inScale(q, root, s)) expect((q - p).abs() >= (r - p).abs(), isTrue, reason: '${s.id} $root $p -> $r, existe $q');
            }
          }
        }
      }
    });

    test('scalePitches', () {
      expect(scalePitches(0, sc('major'), lo: 60, hi: 72), [60, 62, 64, 65, 67, 69, 71, 72]);
      expect(scalePitches(0, sc('chromatic')).length, 128);
    });

    test('ClipScale: codifica, lê e recusa lixo', () {
      final s = ClipScale(9, sc('minor'));
      expect(s.encode(), '9:minor');
      final back = ClipScale.parse('9:minor')!;
      expect(back.root, 9);
      expect(back.scale.id, 'minor');
      expect(ClipScale(14, sc('major')).root, 2);
      expect(ClipScale.parse(null), isNull);
      expect(ClipScale.parse(''), isNull);
      expect(ClipScale.parse('minor'), isNull);
      expect(ClipScale.parse('x:minor'), isNull);
      expect(ClipScale.parse('12:minor'), isNull);
      expect(ClipScale.parse('3:naoexiste'), isNull);
      expect(s.label, 'A menor natural');
      expect(s.isRoot(69), isTrue);
      expect(s.isRoot(70), isFalse);
      expect(s.contains(72), isTrue);
      expect(s.contains(73), isFalse);
      expect(s.snap(73), 72);
    });

    test('snapNotes só muda a altura e não toca nas originais', () {
      final src = [n(61, 0, 2, .3), n(64, 1)];
      final out = snapNotes(src, ClipScale(0, sc('major')));
      expect(pitches(out), [60, 64]);
      expect(out[0].length, 2);
      expect(out[0].velocity, .3);
      expect(src[0].pitch, 61);
    });

    test('MidiClip guarda a escala no JSON e documentos sem ela continuam iguais', () {
      final clip = MidiClip(id: 'a', start: 0, length: 4, scale: '9:minor');
      expect(clip.toJson()['scale'], '9:minor');
      expect(MidiClip.fromJson(clip.toJson()).scale, '9:minor');
      final plain = MidiClip(id: 'b', start: 0, length: 4);
      expect(plain.toJson().containsKey('scale'), isFalse);
      expect(MidiClip.fromJson(plain.toJson()).scale, isNull);
      // JSON antigo, sem o campo
      expect(MidiClip.fromJson({'id': 'c', 'start': 0, 'length': 2, 'notes': []}).scale, isNull);
    });
  });

  group('acordes', () {
    test('tipos e intervalos', () {
      expect(chordPitches(60, 'maj'), [60, 64, 67]);
      expect(chordPitches(60, 'min'), [60, 63, 67]);
      expect(chordPitches(60, 'dim'), [60, 63, 66]);
      expect(chordPitches(60, 'aug'), [60, 64, 68]);
      expect(chordPitches(60, 'sus2'), [60, 62, 67]);
      expect(chordPitches(60, 'sus4'), [60, 65, 67]);
      expect(chordPitches(60, '7'), [60, 64, 67, 70]);
      expect(chordPitches(60, 'maj7'), [60, 64, 67, 71]);
      expect(chordPitches(60, 'm7'), [60, 63, 67, 70]);
      expect(chordPitches(60, 'm7b5'), [60, 63, 66, 70]);
      expect(chordPitches(60, 'dim7'), [60, 63, 66, 69]);
      expect(chordPitches(60, '9'), [60, 64, 67, 70, 74]);
      expect(chordPitches(60, 'maj9'), [60, 64, 67, 71, 74]);
      expect(chordPitches(60, 'm9'), [60, 63, 67, 70, 74]);
      expect(chordPitches(60, 'add9'), [60, 64, 67, 74]);
      expect(chordPitches(60, '6'), [60, 64, 67, 69]);
      expect(chordPitches(60, '5'), [60, 67]);
      // tipo desconhecido cai no maior
      expect(chordPitches(60, 'xyz'), [60, 64, 67]);
    });

    test('ids dos tipos são únicos', () {
      final ids = [for (final t in chordTypes) t.id, for (final d in diatonicChords) d.$1];
      expect(ids.toSet().length, ids.length);
    });

    test('inversões passam a nota mais grave uma oitava para cima', () {
      expect(chordPitches(60, 'maj', inversion: 1), [64, 67, 72]);
      expect(chordPitches(60, 'maj', inversion: 2), [67, 72, 76]);
      expect(chordPitches(60, 'maj', inversion: 3), [72, 76, 79]); // volta à fundamental uma oitava acima
      expect(chordPitches(60, '7', inversion: 3), [70, 72, 76, 79]);
      expect(chordPitches(60, 'maj', inversion: 0), [60, 64, 67]);
      expect(invertChord([67, 60, 64], 1), [64, 67, 72]); // ordena antes
      expect(invertChord([60], 2), [60]);
    });

    test('alturas além do MIDI ficam de fora', () {
      expect(chordPitches(125, 'maj'), [125]);
      expect(chordPitches(120, 'maj'), [120, 124, 127]);
      expect(chordPitches(2, 'maj', inversion: 1), [6, 9, 14]);
    });

    test('acordes diatônicos empilham terças da escala', () {
      final c = ClipScale(0, sc('major'));
      expect(chordPitches(60, 'dia3', scale: c), [60, 64, 67]); // I
      expect(chordPitches(62, 'dia3', scale: c), [62, 65, 69]); // ii
      expect(chordPitches(64, 'dia3', scale: c), [64, 67, 71]); // iii
      expect(chordPitches(71, 'dia3', scale: c), [71, 74, 77]); // vii°
      expect(chordPitches(67, 'dia4', scale: c), [67, 71, 74, 77]); // V7
      expect(chordPitches(60, 'dia4', scale: c), [60, 64, 67, 71]); // Imaj7
      expect(chordPitches(60, 'dia5', scale: c), [60, 64, 67, 71, 74]);
      // lá menor: i é menor, VII é maior
      final a = ClipScale(9, sc('minor'));
      expect(chordPitches(69, 'dia3', scale: a), [69, 72, 76]);
      expect(chordPitches(67, 'dia3', scale: a), [67, 71, 74]);
      // nota fora da escala vai antes para a escala (C# em dó maior desce para C)
      expect(chordPitches(61, 'dia3', scale: c), [60, 64, 67]);
      // inversão vale também no diatônico
      expect(chordPitches(60, 'dia3', scale: c, inversion: 1), [64, 67, 72]);
      // sem escala, cai no acorde maior
      expect(chordPitches(60, 'dia3'), [60, 64, 67]);
    });

    test('chordNotes herda início, duração e velocidade da nota base', () {
      final base = n(60, 2.5, .75, .6);
      final out = chordNotes(base, [60, 64, 67]);
      expect(pitches(out), [60, 64, 67]);
      for (final x in out) {
        expect(x.start, 2.5);
        expect(x.length, .75);
        expect(x.velocity, .6);
      }
      expect(out.any((x) => identical(x, base)), isFalse);
    });

    test('spreadChords: acorde vira arpejo, da mais grave à mais aguda, pela duração dele', () {
      final out = spreadChords([n(67, 0, 2, .9), n(60, 0, 2, .5), n(64, 0, 2)]);
      expect(pitches(out), [60, 64, 67]);
      expect(starts(out), [0, closeTo(2 / 3, 1e-9), closeTo(4 / 3, 1e-9)]);
      for (final x in out) {
        expect(x.length, closeTo(2 / 3, 1e-9));
      }
      expect(out[0].velocity, .5); // cada nota guarda a sua velocidade
    });

    test('spreadChords deixa notas sozinhas e trata vários acordes', () {
      final out = spreadChords([n(60, 0, 1), n(72, 1, 1), n(60, 2, 1), n(64, 2, 1)]);
      expect(pitches(out), [60, 72, 60, 64]);
      expect(starts(out), [0, 1, 2, 2.5]);
      expect(lengths(out), [1, 1, .5, .5]);
    });
  });

  group('arpejador', () {
    List<MidiNote> chord() => [n(64, 0, 2, .6), n(60, 0, 2, .8), n(67, 0, 2, .7)];

    test('subir: notas na taxa, pela duração do acorde', () {
      final out = arpeggiate(chord(), pattern: ArpPattern.up, rate: .5, gate: 1);
      expect(pitches(out), [60, 64, 67, 60]);
      expect(starts(out), [0, .5, 1, 1.5]);
      expect(lengths(out), [.5, .5, .5, .5]);
      // velocidade média do acorde
      expect(out.first.velocity, closeTo(.7, 1e-9));
    });

    test('descer', () {
      expect(pitches(arpeggiate(chord(), pattern: ArpPattern.down, rate: .5)), [67, 64, 60, 67]);
    });

    test('subir e descer não repete as pontas', () {
      final out = arpeggiate(chord(), pattern: ArpPattern.upDown, rate: .25);
      expect(pitches(out), [60, 64, 67, 64, 60, 64, 67, 64]);
      expect(starts(out), [0, .25, .5, .75, 1, 1.25, 1.5, 1.75]);
      // com duas notas vira só subir
      final two = arpeggiate([n(60, 0, 1), n(64, 0, 1)], pattern: ArpPattern.upDown, rate: .25);
      expect(pitches(two), [60, 64, 60, 64]);
    });

    test('ordem tocada respeita a ordem da lista', () {
      final out = arpeggiate(chord(), pattern: ArpPattern.played, rate: .5);
      expect(pitches(out), [64, 60, 67, 64]);
    });

    test('oitavas empilham o conjunto', () {
      final out = arpeggiate([n(60, 0, 2), n(64, 0, 2)], rate: .25, octaves: 2);
      expect(pitches(out), [60, 64, 72, 76, 60, 64, 72, 76]);
      final four = arpeggiate([n(60, 0, 2), n(64, 0, 2)], rate: .25, octaves: 4);
      expect(pitches(four).take(8), [60, 64, 72, 76, 84, 88, 96, 100]);
      // oitavas além de 4 valem 4; abaixo de 1 valem 1
      expect(pitches(arpeggiate([n(60, 0, 1)], rate: .25, octaves: 9)), pitches(arpeggiate([n(60, 0, 1)], rate: .25, octaves: 4)));
      expect(pitches(arpeggiate([n(60, 0, 1)], rate: .25, octaves: 0)), [60, 60, 60, 60]);
    });

    test('oitavas não passam de 127', () {
      final out = arpeggiate([n(120, 0, 1), n(124, 0, 1)], rate: .25, octaves: 4);
      for (final x in out) {
        expect(x.pitch, lessThanOrEqualTo(127));
      }
    });

    test('gate encurta cada nota', () {
      final out = arpeggiate(chord(), rate: .5, gate: .5);
      expect(lengths(out), [.25, .25, .25, .25]);
      expect(starts(out), [0, .5, 1, 1.5]);
    });

    test('tercinas e taxas', () {
      final out = arpeggiate([n(60, 0, 1), n(64, 0, 1)], rate: 1 / 3);
      expect(out.length, 3);
      expect(starts(out), [0, closeTo(1 / 3, 1e-9), closeTo(2 / 3, 1e-9)]);
      expect(arpRates.map((r) => r.$1), containsAll(['1/4', '1/8', '1/16', '1/32', '1/8T', '1/16T']));
      expect(arpeggiate(chord(), rate: 1).length, 2);
      expect(arpeggiate(chord(), rate: .125).length, 16);
    });

    test('aleatório: mesma semente, mesmo arpejo; outra semente, outro', () {
      final a = pitches(arpeggiate(chord(), pattern: ArpPattern.random, rate: .125, seed: 7));
      final b = pitches(arpeggiate(chord(), pattern: ArpPattern.random, rate: .125, seed: 7));
      final c = pitches(arpeggiate(chord(), pattern: ArpPattern.random, rate: .125, seed: 8));
      expect(a, b);
      expect(a, isNot(c));
      expect(a.toSet().difference({60, 64, 67}), isEmpty);
    });

    test('vários grupos e a nota sozinha repetida', () {
      final out = arpeggiate([n(60, 0, 1), n(64, 0, 1), n(72, 2, 1)], rate: .5);
      expect(starts(out), [0, .5, 2, 2.5]);
      expect(pitches(out), [60, 64, 72, 72]);
    });

    test('a última nota não passa do fim do acorde', () {
      final out = arpeggiate([n(60, 0, 1.25), n(64, 0, 1.25)], rate: .5);
      expect(starts(out), [0, .5, 1]);
      expect(out.last.length, closeTo(.25, 1e-9));
    });

    test('entrada vazia e taxa inválida', () {
      expect(arpeggiate([]), isEmpty);
      final src = [n(60, 0, 1)];
      final out = arpeggiate(src, rate: 0);
      expect(pitches(out), [60]);
      expect(identical(out.first, src.first), isFalse);
    });
  });

  group('humanizar', () {
    List<MidiNote> grid() => [for (var i = 0; i < 16; i++) n(60 + i % 4, i * .5, .25, .7)];

    test('mesma semente, mesmo resultado; outra, outro', () {
      final a = humanize(grid(), seed: 3);
      final b = humanize(grid(), seed: 3);
      final c = humanize(grid(), seed: 4);
      expect(starts(a), starts(b));
      expect([for (final x in a) x.velocity], [for (final x in b) x.velocity]);
      expect(starts(a), isNot(starts(c)));
    });

    test('respeita os limites de tempo e velocidade', () {
      final src = grid();
      final out = humanize(src, timing: .1, velocity: .2, seed: 9);
      var moved = 0;
      for (var i = 0; i < src.length; i++) {
        expect((out[i].start - src[i].start).abs(), lessThanOrEqualTo(.1 + 1e-9));
        expect((out[i].velocity - src[i].velocity).abs(), lessThanOrEqualTo(.2 + 1 / 127));
        if (out[i].start != src[i].start) moved++;
        expect(out[i].pitch, src[i].pitch);
        expect(out[i].length, src[i].length);
      }
      expect(moved, greaterThan(8));
    });

    test('força escala o desvio; zero não muda nada', () {
      final src = grid();
      final full = humanize(src, seed: 5);
      final half = humanize(src, seed: 5, strength: .5);
      for (var i = 0; i < src.length; i++) {
        // a primeira nota está em 0 e pode ser cortada nele; as outras escalam certinho
        if (i == 0) continue;
        expect((half[i].start - src[i].start).abs(), closeTo((full[i].start - src[i].start).abs() / 2, 1e-8));
      }
      final zero = humanize(src, seed: 5, strength: 0);
      expect(starts(zero), starts(src));
    });

    test('nunca passa para antes do 0 nem fora de 1..127', () {
      final out = humanize([n(60, 0, 1, 1), n(60, .01, 1, .01)], timing: 1, velocity: 1, seed: 2);
      for (final x in out) {
        expect(x.start, greaterThanOrEqualTo(0));
        expect(x.velocity, inInclusiveRange(1 / 127, 1));
      }
    });

    test('não mexe nas originais', () {
      final src = grid();
      humanize(src, seed: 1);
      expect(starts(src), starts(grid()));
    });
  });

  group('rampa de velocidade', () {
    test('linear no tempo entre a primeira e a última', () {
      final src = [n(60, 0, 1, .2), n(62, 1, 1, .9), n(64, 3, 1, .5), n(65, 4, 1, 1.0)];
      final out = velocityRamp(src);
      expect(out[0].velocity, closeTo(.2, 1 / 127));
      expect(out[3].velocity, closeTo(1.0, 1 / 127));
      expect(out[1].velocity, closeTo(.2 + .8 * .25, 1 / 127)); // t = 1/4
      expect(out[2].velocity, closeTo(.2 + .8 * .75, 1 / 127)); // t = 3/4
    });

    test('a ordem da lista não importa, só o tempo', () {
      final out = velocityRamp([n(65, 4, 1, 1.0), n(60, 0, 1, .2), n(62, 2, 1, .9)]);
      expect(out[0].velocity, closeTo(1.0, 1 / 127));
      expect(out[1].velocity, closeTo(.2, 1 / 127));
      expect(out[2].velocity, closeTo(.6, 1 / 127));
    });

    test('extremos explícitos, decrescente e notas simultâneas', () {
      final out = velocityRamp([n(60, 0), n(62, 1), n(64, 2)], from: 1, to: .2);
      expect(out[0].velocity, closeTo(1, 1 / 127));
      expect(out[1].velocity, closeTo(.6, 1 / 127));
      expect(out[2].velocity, closeTo(.2, 1 / 127));
      // tudo no mesmo instante: todas na velocidade inicial
      final same = velocityRamp([n(60, 1, 1, .3), n(64, 1, 1, .9)]);
      expect(same.map((x) => x.velocity), everyElement(closeTo(.3, 1 / 127)));
      expect(velocityRamp([]), isEmpty);
    });
  });

  group('legato e staccato', () {
    test('legato: cada nota vai até o início da próxima; a última fica', () {
      final out = legato([n(60, 0, .25), n(62, 1, .25), n(64, 1.5, .25), n(65, 4, .5)]);
      expect(lengths(out), [1, .5, 2.5, .5]);
      expect(starts(out), [0, 1, 1.5, 4]);
    });

    test('legato com acordes: as simultâneas vão juntas até o próximo instante', () {
      final out = legato([n(60, 0, .1), n(64, 0, .1), n(67, 2, .1)]);
      expect(lengths(out), [2, 2, .1]);
    });

    test('legato encurta as que invadiam a próxima', () {
      final out = legato([n(60, 0, 3), n(62, 1, 1)]);
      expect(lengths(out), [1, 1]);
    });

    test('legato fora de ordem', () {
      final out = legato([n(64, 2, .1), n(60, 0, .1), n(62, 1, .1)]);
      expect(lengths(out), [.1, 1, 1]);
    });

    test('staccato encurta a x% e nunca zera', () {
      final out = staccato([n(60, 0, 1), n(62, 1, .5)], factor: .5);
      expect(lengths(out), [.5, .25]);
      expect(starts(out), [0, 1]);
      expect(staccato([n(60, 0, .001)], factor: .01).first.length, greaterThan(0));
      expect(lengths(staccato([n(60, 0, 2)], factor: 1)), [2]);
    });
  });

  group('inverter, escalar e reverter', () {
    test('espelhar no tempo em torno do trecho', () {
      final out = mirrorTime([n(60, 0, 1), n(62, 1, .5), n(64, 3, 1)]);
      // trecho 0..4: início' = 4 - fim
      expect(starts(out), [3, 2.5, 0]);
      expect(lengths(out), [1, .5, 1]);
      // espelhar duas vezes volta ao original
      expect(starts(mirrorTime(out)), [0, 1, 3]);
      expect(mirrorTime([]), isEmpty);
    });

    test('espelhar nas alturas em torno da faixa', () {
      final out = mirrorPitch([n(60, 0), n(64, 1), n(72, 2)]);
      expect(pitches(out), [72, 68, 60]);
      expect(pitches(mirrorPitch(out)), [60, 64, 72]);
      expect(pitches(mirrorPitch([n(60, 0)])), [60]);
      // nunca sai do MIDI
      for (final x in mirrorPitch([n(0, 0), n(127, 1), n(64, 2)])) {
        expect(x.pitch, inInclusiveRange(0, 127));
      }
    });

    test('escalar o tempo a partir da primeira nota', () {
      final src = [n(60, 2, 1), n(62, 3, .5), n(64, 5, 1)];
      final half = scaleTime(src, .5);
      expect(starts(half), [2, 2.5, 3.5]);
      expect(lengths(half), [.5, .25, .5]);
      final dbl = scaleTime(src, 2);
      expect(starts(dbl), [2, 4, 8]);
      expect(lengths(dbl), [2, 1, 2]);
      final only = scaleTime(src, 2, lengths: false);
      expect(starts(only), [2, 4, 8]);
      expect(lengths(only), [1, .5, 1]);
      expect(starts(scaleTime(src, 1)), starts(src));
      expect(starts(scaleTime(src, 0)), starts(src)); // fator inválido não faz nada
      expect(starts(scaleTime(src, -1)), starts(src));
    });

    test('reverter a ordem: o ritmo fica, as alturas e velocidades andam de trás para frente', () {
      final src = [n(60, 0, 1, .2), n(62, 1, .5, .4), n(64, 1.5, .5, .6), n(67, 2, 2, .9)];
      final out = reverseOrder(src);
      expect(pitches(out), [67, 64, 62, 60]);
      expect([for (final x in out) x.velocity], [.9, .6, .4, .2]);
      expect(starts(out), starts(src));
      expect(lengths(out), lengths(src));
    });

    test('reverter mantém a correspondência com a lista mesmo fora de ordem', () {
      final src = [n(64, 2), n(60, 0), n(62, 1)];
      final out = reverseOrder(src);
      expect(pitches(out), [60, 64, 62]);
      expect(starts(out), [2, 0, 1]);
      expect(pitches(reverseOrder(out)), pitches(src));
    });
  });

  group('tercinas', () {
    test('cada colcheia vira três notas iguais que a dividem', () {
      final out = tripletize([n(60, 0, .5, .7), n(62, 1, .5)]);
      expect(out.length, 6);
      expect(pitches(out), [60, 60, 60, 62, 62, 62]);
      expect(starts(out), [0, closeTo(1 / 6, 1e-9), closeTo(1 / 3, 1e-9), 1, closeTo(1 + 1 / 6, 1e-9), closeTo(1 + 1 / 3, 1e-9)]);
      for (final x in out) {
        expect(x.length, closeTo(1 / 6, 1e-9));
      }
      expect(out.first.velocity, .7);
    });

    test('só as da duração pedida; as outras ficam', () {
      final out = tripletize([n(60, 0, .5), n(62, 1, 1), n(64, 2, .25)]);
      expect(out.length, 5);
      expect(pitches(out), [60, 60, 60, 62, 64]);
      // semínima como unidade
      expect(tripletize([n(60, 0, 1)], unit: 1).length, 3);
      expect(tripletize([]), isEmpty);
    });
  });

  group('dividir', () {
    test('corta a nota que atravessa a posição', () {
      final out = splitAt([n(60, 0, 4, .6)], 1.5);
      expect(out.length, 2);
      expect(starts(out), [0, 1.5]);
      expect(lengths(out), [1.5, 2.5]);
      expect(pitches(out), [60, 60]);
      expect(out[1].velocity, .6);
    });

    test('quem termina ou começa na posição não é cortada', () {
      final out = splitAt([n(60, 0, 1), n(62, 1, 1), n(64, 2, 1)], 1);
      expect(out.length, 3);
      expect(starts(out), [0, 1, 2]);
      // posição fora de todas
      expect(splitAt([n(60, 0, 1)], 5).length, 1);
    });

    test('corta várias de uma vez e não altera as originais', () {
      final src = [n(60, 0, 2), n(64, .5, 2), n(67, 3, 1)];
      final out = splitAt(src, 1);
      expect(out.length, 5);
      expect(src[0].length, 2);
      expect(pitches(out), [60, 60, 64, 64, 67]);
    });
  });

  group('unir, duplicadas e sobrepostas', () {
    test('une notas iguais que se tocam', () {
      final out = joinAdjacent([n(60, 0, 1, .5), n(60, 1, 1, .9), n(60, 2, .5), n(62, 0, 1)]);
      expect(out.length, 2);
      final c = out.firstWhere((x) => x.pitch == 60);
      expect(c.start, 0);
      expect(c.length, 2.5);
      expect(c.velocity, .5); // a da primeira
      expect(out.firstWhere((x) => x.pitch == 62).length, 1);
    });

    test('com folga não une; com tolerância une', () {
      expect(joinAdjacent([n(60, 0, 1), n(60, 1.25, 1)]).length, 2);
      expect(joinAdjacent([n(60, 0, 1), n(60, 1.25, 1)], tolerance: .25).length, 1);
    });

    test('une também as que se sobrepõem, sem encurtar a maior', () {
      final out = joinAdjacent([n(60, 0, 4), n(60, 1, 1)]);
      expect(out.length, 1);
      expect(out.first.length, 4);
    });

    test('só une a mesma altura; saída por tempo', () {
      final out = joinAdjacent([n(62, 1, 1), n(60, 0, 1), n(62, 2, 1), n(60, 1, 1)]);
      expect(pitches(out), [60, 62]);
      expect(lengths(out), [2, 2]);
    });

    test('removeDuplicates fica com a mais longa', () {
      final out = removeDuplicates([n(60, 0, 1, .5), n(60, 0, 1, .9), n(60, 0, 2), n(62, 0, 1), n(60, 1, 1)]);
      expect(out.length, 3);
      expect(lengths(out.where((x) => x.pitch == 60 && x.start == 0).toList()), [2]);
      // empate: a primeira
      final tie = removeDuplicates([n(60, 0, 1, .5), n(60, 0, 1, .9)]);
      expect(tie.length, 1);
      expect(tie.first.velocity, .5);
      expect(removeDuplicates([n(60, 0), n(62, 0), n(60, 1)]).length, 3);
    });

    test('trimOverlaps apara a anterior onde a seguinte começa', () {
      final out = trimOverlaps([n(60, 0, 3), n(60, 1, 3), n(60, 2, 1), n(62, 0, 5)]);
      expect(lengths(out), [1, 1, 1, 5]);
      expect(starts(out), [0, 1, 2, 0]);
    });

    test('trimOverlaps ignora notas que começam juntas e alturas diferentes', () {
      final out = trimOverlaps([n(60, 0, 2), n(60, 0, 1), n(64, 1, 2)]);
      expect(lengths(out), [2, 1, 2]);
    });

    test('trimOverlaps fora de ordem mantém o alinhamento', () {
      final out = trimOverlaps([n(60, 2, 3), n(60, 0, 3)]);
      expect(lengths(out), [3, 2]);
    });
  });

  group('sameNotes e tidy', () {
    test('sameNotes compara campo a campo', () {
      expect(sameNotes([n(60, 0)], [n(60, 0)]), isTrue);
      expect(sameNotes([n(60, 0)], [n(61, 0)]), isFalse);
      expect(sameNotes([n(60, 0)], [n(60, 0), n(62, 1)]), isFalse);
      expect(sameNotes([n(60, 0, 1, .5)], [n(60, 0, 1, .6)]), isFalse);
      expect(sameNotes([], []), isTrue);
    });

    test('tidyBeats tira o ruído de ponto flutuante', () {
      expect(tidyBeats(0.1 + 0.2), .3);
      expect(tidyBeats(1 / 3), closeTo(1 / 3, 1e-9));
    });
  });
}
