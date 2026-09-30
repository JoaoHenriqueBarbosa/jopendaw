//! Testes do mapa de andamento no motor: equivalência com o andamento único de antes (quadro a
//! quadro, por hash de um cenário variado gravado do motor anterior ao mapa), rampa e salto,
//! notas, clipes, loop, metrônomo com mapa de compassos, gravação e ausência de alocação.

use super::*;
use crate::effect::auto_target;
use crate::instrument::kind;

const RATE: f64 = 48_000.0;

/// Hash FNV-1a dos bits da saída de um cenário variado: clipes com fade, notas em batidas
/// quebradas, automação, metrônomo, loop, seek no meio, parada e cauda.
fn scenario(prep: impl FnOnce(&mut Engine)) -> u64 {
    let mut e = Engine::new(RATE);
    prep(&mut e);
    let tone = (0..96_000).map(|i| 0.5 * (std::f32::consts::TAU * 330.0 * i as f32 / RATE as f32).sin()).collect::<Vec<f32>>();
    e.load_sample(1, Sample::new(vec![tone.clone(), tone], RATE));
    e.set_track_count(3);
    e.add_clip(Clip { track: 0, sample: 1, start: 1.25, offset: 0.1, length: 1.5, gain: 0.8, fade_in: 0.05, fade_out: 0.2 });
    e.add_clip(Clip { track: 0, sample: 1, start: 5.0, offset: 0.0, length: 0.7, gain: 1.0, fade_in: 0.0, fade_out: 0.0 });
    e.set_track_kind(1, kind::SYNTH);
    for (i, s) in [0.0, 0.5, 1.0, 1.75, 2.5, 3.3333, 4.0, 5.5, 6.0, 7.25].into_iter().enumerate() {
        e.add_note(1, s, 0.6, 48 + 3 * i as u32, 0.5 + 0.05 * i as f32);
    }
    e.set_track_kind(2, kind::SYNTH);
    e.add_note(2, 1.0, 8.0, 36, 0.7);
    e.add_lane(1, auto_target::VOLUME, 0, 0);
    e.add_point(0, 0.0, 0.2, 0.0);
    e.add_point(0, 4.0, 1.0, 0.3);
    e.add_point(0, 8.0, 0.4, -0.3);
    e.set_metronome(true, 0.5);
    e.set_loop(true, 2.0, 6.5);
    e.seek(1.0);
    e.play();
    let mut h: u64 = 0xcbf29ce484222325;
    let mut peak = 0.0f32;
    let mut feed = |l: &[f32], r: &[f32]| {
        for s in l.iter().chain(r) {
            h = (h ^ u64::from(s.to_bits())).wrapping_mul(0x100000001b3);
            peak = peak.max(s.abs());
        }
    };
    let (mut l, mut r) = (vec![0.0f32; 4096], vec![0.0f32; 4096]);
    for k in 0..400 {
        let n = match k % 3 {
            0 => 128,
            1 => 500,
            _ => 1000,
        };
        e.process(&mut l[..n], &mut r[..n]);
        feed(&l[..n], &r[..n]);
        if k == 150 {
            e.seek(0.3);
        }
        if k == 260 {
            e.set_loop(false, 0.0, 0.0);
        }
        if k == 330 {
            e.stop();
        }
    }
    assert!(peak > 0.05, "o cenário precisa soar (pico {peak})");
    h
}

/// Hashes do cenário no motor de andamento único, de antes do mapa (fase 9).
const GOLDEN_120: u64 = 0xc1e398f928c1c9ed;
const GOLDEN_97: u64 = 0xeb2b6fcee3483e5d;

#[test]
fn andamento_unico_soa_quadro_a_quadro_como_antes() {
    assert_eq!(scenario(|e| e.set_tempo(120.0, 4)), GOLDEN_120);
    assert_eq!(scenario(|e| e.set_tempo(97.3, 3)), GOLDEN_97);
}

#[test]
fn mapa_de_um_ponto_e_o_mesmo_que_sem_mapa() {
    // o mapa reenviado com só o ponto 0 (e uma rampa sem ponto seguinte, que não faz nada)
    let one = |bpm: f64, bpb: u32, ramp: bool| {
        move |e: &mut Engine| {
            e.set_tempo(bpm, bpb);
            e.tempo_clear();
            e.tempo_point(0.0, bpm, ramp);
            e.meter_clear();
            e.meter_point(1, bpb, 4);
        }
    };
    assert_eq!(scenario(one(120.0, 4, false)), GOLDEN_120);
    assert_eq!(scenario(one(120.0, 4, true)), GOLDEN_120);
    assert_eq!(scenario(one(97.3, 3, false)), GOLDEN_97);
}

fn quiet() -> Engine {
    let mut e = Engine::new(RATE);
    e.set_limiter(false);
    e
}

fn run(e: &mut Engine, frames: usize) -> (Vec<f32>, Vec<f32>) {
    let (mut l, mut r) = (vec![0.0; frames], vec![0.0; frames]);
    let mut at = 0;
    while at < frames {
        let n = (frames - at).min(128);
        e.process(&mut l[at..at + n], &mut r[at..at + n]);
        at += n;
    }
    (l, r)
}

fn first_sound(v: &[f32]) -> Option<usize> {
    v.iter().position(|s| s.abs() > 1e-7)
}

#[test]
fn rampa_de_60_a_120_dura_a_integral_exata() {
    let mut e = quiet();
    e.set_tempo(120.0, 4);
    e.tempo_point(0.0, 60.0, true);
    e.tempo_point(4.0, 120.0, false);
    // 4 batidas indo de 60 a 120 bpm: 4·ln 2 segundos
    let want = 4.0 * std::f64::consts::LN_2 * RATE;
    assert!((e.beats_to_frames(4.0) - want).abs() < 1e-6);
    assert!((e.frames_to_beats(want) - 4.0).abs() < 1e-9);
    // e o transporte anda essa quantidade de quadros até a batida 4
    e.play();
    let frames = want.round() as usize;
    run(&mut e, frames);
    assert!((e.beat() - 4.0).abs() < 1e-3, "beat {}", e.beat());
    assert!((e.beat() - e.frames_to_beats(frames as f64)).abs() < 1e-12);
}

#[test]
fn salto_muda_o_andamento_no_ponto() {
    let mut e = quiet();
    e.set_tempo(120.0, 4);
    e.tempo_point(4.0, 60.0, false);
    assert_eq!(e.beats_to_frames(4.0), 96_000.0);
    assert_eq!(e.beats_to_frames(5.0), 96_000.0 + 48_000.0);
    e.play();
    run(&mut e, 96_000 + 24_000);
    assert!((e.beat() - 4.5).abs() < 1e-9);
}

#[test]
fn a_posicao_musical_se_mantem_quando_o_mapa_muda() {
    let mut e = quiet();
    e.set_tempo(120.0, 4);
    e.seek(6.0);
    e.set_loop(true, 2.0, 8.0);
    e.tempo_clear();
    e.tempo_point(1.0, 60.0, false);
    e.tempo_point(3.0, 240.0, true);
    e.tempo_point(5.0, 90.0, false);
    assert!((e.frames_to_beats(e.pos) - 6.0).abs() < 1e-9);
    assert!((e.frames_to_beats(e.loop_start) - 2.0).abs() < 1e-9);
    assert!((e.frames_to_beats(e.loop_end) - 8.0).abs() < 1e-9);
    // o lote acabou (um bloco passou): o próximo reenvio parte da posição de agora
    e.play();
    run(&mut e, 128);
    let now = e.frames_to_beats(e.pos);
    e.tempo_clear();
    e.tempo_point(0.0, 100.0, false);
    assert!((e.frames_to_beats(e.pos) - now).abs() < 1e-9);
}

#[test]
fn clipe_de_audio_comeca_no_quadro_da_batida_e_toca_em_tempo_real() {
    for (start, length) in [(6.0, 0.25), (3.0, 0.5), (1.5, 0.1)] {
        let mut e = quiet();
        e.set_track_count(1);
        e.track_mut(0).unwrap().pan = 0.0;
        e.load_sample(1, Sample::new(vec![vec![0.5; 96_000]], RATE));
        e.add_clip(Clip { track: 0, sample: 1, start, offset: 0.0, length, gain: 1.0, fade_in: 0.0, fade_out: 0.0 });
        e.set_tempo(120.0, 4);
        e.tempo_point(0.0, 60.0, true);
        e.tempo_point(4.0, 240.0, false);
        e.tempo_point(6.0, 90.0, false);
        e.play();
        let f = e.beats_to_frames(start);
        let (l, _) = run(&mut e, (f + length * RATE) as usize + 500);
        let first = first_sound(&l).unwrap();
        assert_eq!(first, f.ceil() as usize, "clipe na batida {start}");
        // a duração do clipe é em segundos, seja qual for o andamento no trecho
        let count = l.iter().filter(|s| s.abs() > 1e-7).count();
        assert!((count as f64 - length * RATE).abs() <= 2.0, "clipe na batida {start}: {count} quadros para {}", length * RATE);
    }
}

#[test]
fn nota_do_sequenciador_dispara_no_quadro_da_batida() {
    let mut e = quiet();
    e.set_tempo(120.0, 4);
    e.set_track_count(1);
    e.set_track_kind(0, kind::SYNTH);
    e.track_mut(0).unwrap().pan = 0.0;
    e.tempo_point(0.0, 60.0, true);
    e.tempo_point(4.0, 240.0, false);
    e.add_note(0, 3.0, 1.0, 69, 1.0);
    e.play();
    let f = e.beats_to_frames(3.0);
    let (l, _) = run(&mut e, f as usize + 4000);
    let first = first_sound(&l).unwrap();
    assert!(first >= f.ceil() as usize && first <= f.ceil() as usize + 3, "nota esperada em {f}, soou em {first}");
    // a nota seguinte à mudança de andamento cai no quadro do novo andamento
    let mut e = quiet();
    e.set_track_count(1);
    e.set_track_kind(0, kind::SYNTH);
    e.track_mut(0).unwrap().pan = 0.0;
    e.tempo_point(2.0, 240.0, false);
    e.add_note(0, 6.0, 1.0, 69, 1.0);
    e.play();
    let f = e.beats_to_frames(6.0);
    assert_eq!(f, 2.0 * 24_000.0 + 4.0 * 12_000.0);
    let (l, _) = run(&mut e, f as usize + 4000);
    let first = first_sound(&l).unwrap();
    assert!(first >= f as usize && first <= f as usize + 3, "nota esperada em {f}, soou em {first}");
}

#[test]
fn loop_e_seek_cruzando_pontos() {
    let mut e = quiet();
    e.set_tempo(120.0, 4);
    e.tempo_point(4.0, 60.0, true);
    e.tempo_point(6.0, 200.0, false);
    e.tempo_point(8.0, 30.0, true);
    e.tempo_point(9.0, 400.0, false);
    e.set_loop(true, 2.0, 10.0);
    e.seek(2.0);
    e.play();
    let loop_frames = e.beats_to_frames(10.0) - e.beats_to_frames(2.0);
    let mut wraps = 0;
    let mut last = e.beat();
    let total = (loop_frames * 3.5) as usize;
    let mut done = 0;
    while done < total {
        run(&mut e, 128);
        done += 128;
        let b = e.beat();
        assert!((2.0 - 1e-9..10.0).contains(&b), "fora do loop: {b}");
        if b < last {
            wraps += 1;
        }
        last = b;
    }
    assert_eq!(wraps, 3);
    // a posição em batidas no meio do loop bate com o mapa
    e.seek(7.0);
    assert!((e.beat() - 7.0).abs() < 1e-9);
    e.seek(8.5);
    assert!((e.beat() - 8.5).abs() < 1e-9);
    run(&mut e, 128);
    let want = e.frames_to_beats(e.beats_to_frames(8.5) + 128.0);
    assert!((e.beat() - want).abs() < 1e-9);
}

/// Onde começam os cliques do metrônomo na saída (silêncio antes de cada um) e quantas passagens
/// por zero o começo dele tem (o mais agudo é o tempo forte).
fn clicks(out: &[f32]) -> Vec<(usize, usize)> {
    let mut found = Vec::new();
    let mut i = 0;
    while i < out.len() {
        if out[i].abs() > 1e-9 && found.last().is_none_or(|&(at, _)| i > at + 1500) {
            let crossings = out[i..(i + 400).min(out.len())].windows(2).filter(|w| w[0] * w[1] < 0.0).count();
            found.push((i, crossings));
            i += 1500;
        } else {
            i += 1;
        }
    }
    found
}

#[test]
fn metronomo_segue_o_mapa_de_andamento_e_de_compassos() {
    let mut e = quiet();
    e.set_tempo(120.0, 4);
    e.tempo_point(4.0, 60.0, false);
    e.tempo_point(8.0, 120.0, true);
    e.tempo_point(12.0, 240.0, false);
    // 4/4 no compasso 1, 3/4 a partir do 2 (batida 4), 6/8 a partir do 4 (batida 10)
    e.meter_point(2, 3, 4);
    e.meter_point(4, 6, 8);
    e.set_metronome(true, 0.5);
    e.play();
    let (l, _) = run(&mut e, 16 * 48_000);
    let got = clicks(&l);
    // batidas esperadas e se são tempo forte
    let mut want: Vec<(f64, bool)> = vec![(0.0, true), (1.0, false), (2.0, false), (3.0, false)];
    want.extend([(4.0, true), (5.0, false), (6.0, false), (7.0, true), (8.0, false), (9.0, false)]);
    // 6/8 a partir da batida 10: um clique a cada colcheia, tempo forte a cada 3 batidas
    want.extend([(10.0, true), (10.5, false), (11.0, false), (11.5, false), (12.0, false), (12.5, false), (13.0, true)]);
    let mut checked = 0;
    for (n, &(beat, down)) in want.iter().enumerate() {
        let f = e.beats_to_frames(beat);
        if f + 1500.0 >= l.len() as f64 {
            break;
        }
        let (at, crossings) = *got.get(n).unwrap_or_else(|| panic!("faltou o clique {n} (batida {beat}); vieram {}", got.len()));
        assert_eq!(at, f.floor() as usize + 1, "clique da batida {beat}");
        assert_eq!(crossings > 21, down, "batida {beat}: tempo forte = {down}, passagens por zero = {crossings}");
        checked += 1;
    }
    assert!(checked >= 12, "só {checked} cliques conferidos");
}

#[test]
fn metronomo_do_andamento_unico_nao_muda() {
    // 4/4 a 120 bpm: um clique a cada 24000 quadros, o primeiro tempo mais agudo
    let mut e = quiet();
    e.set_tempo(120.0, 4);
    e.set_metronome(true, 0.5);
    e.play();
    let (l, _) = run(&mut e, 5 * 24_000);
    let got = clicks(&l);
    assert_eq!(got.iter().map(|c| c.0).collect::<Vec<_>>(), [1, 24_001, 48_001, 72_001, 96_001]);
    assert!(got[0].1 > 21 && got[1].1 <= 21 && got[4].1 > 21);
}

#[test]
fn gravacao_de_notas_usa_o_mapa() {
    let mut e = quiet();
    e.set_tempo(120.0, 4);
    e.set_track_count(1);
    e.set_track_kind(0, kind::SYNTH);
    e.tempo_point(2.0, 30.0, false);
    e.rec_notes_start();
    e.play();
    // 2 batidas a 120 bpm (48000 quadros) + 1 s a 30 bpm (0,5 batida)
    run(&mut e, 48_000 + 48_000);
    e.live_on(0, 60, 0.8);
    run(&mut e, 24_000);
    e.live_off(0, 60);
    e.rec_notes_stop();
    let mut out = vec![0.0f32; 5 * 4];
    let n = e.rec_notes(&mut out);
    assert_eq!(n, 5);
    assert!((f64::from(out[2]) - 2.5).abs() < 1e-3, "início {}", out[2]);
    assert!((f64::from(out[3]) - 2.75).abs() < 1e-3, "fim {}", out[3]);
}

#[test]
fn mapa_grande_nao_aloca_no_audio() {
    let mut e = quiet();
    e.set_tempo(120.0, 4);
    e.set_track_count(2);
    e.set_track_kind(1, kind::SYNTH);
    e.load_sample(1, Sample::new(vec![vec![0.3; 96_000]], RATE));
    e.add_clip(Clip { track: 0, sample: 1, start: 100.0, offset: 0.0, length: 1.0, gain: 1.0, fade_in: 0.0, fade_out: 0.0 });
    for i in 0..64 {
        e.add_note(1, i as f64 * 2.0, 1.0, 60, 0.8);
    }
    for i in 1..=256 {
        e.tempo_point(i as f64, 60.0 + (i * 37 % 200) as f64, i % 3 == 0);
    }
    for bar in 2..40 {
        e.meter_point(bar, 2 + bar % 5, 4);
    }
    e.set_metronome(true, 0.5);
    e.set_loop(true, 10.0, 90.0);
    e.seek(20.0);
    e.play();
    run(&mut e, 4096);
    let (mut l, mut r) = (vec![0.0f32; 128], vec![0.0f32; 128]);
    let allocs = crate::testalloc::count(|| {
        for k in 0..1400 {
            if k == 1000 {
                e.seek(50.0);
            }
            e.process(&mut l, &mut r);
        }
    });
    assert_eq!(allocs, 0, "o áudio alocou");
}

#[test]
fn extremos_de_andamento_dao_posicoes_finitas_e_ordenadas() {
    for bpm in [20.0, 400.0] {
        let mut e = quiet();
        e.set_tempo(bpm, 4);
        e.tempo_point(4.0, bpm * 2.0, true);
        e.tempo_point(8.0, bpm / 2.0, false);
        let mut prev = -1.0;
        for k in 0..400 {
            let f = e.beats_to_frames(k as f64 * 0.05);
            assert!(f.is_finite() && f > prev);
            prev = f;
            assert!((e.frames_to_beats(f) - k as f64 * 0.05).abs() < 1e-9);
        }
    }
}
