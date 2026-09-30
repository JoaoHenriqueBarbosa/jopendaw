//! Testes da expressão MIDI (bend, modulação, pedal), do instrumento ao clipe e ao registro.

use std::f32::consts::TAU;

use super::*;
use crate::Sample;
use crate::instrument::{fm_param, kind, pitch_hz, sampler_param, synth_param, wavetable_param};

const RATE: f64 = 48_000.0;
/// Uma batida a 120 bpm, em quadros.
const BEAT: usize = 24_000;

/// Motor com uma faixa do tipo dado, em tom puro (uma senoide), soltura curtíssima.
fn engine(kind: u32) -> Engine {
    let mut e = Engine::new(RATE);
    e.set_tempo(120.0, 4);
    e.set_track_count(1);
    e.set_track_kind(0, kind);
    pure(&mut e, kind);
    e
}

/// Os parâmetros do tom puro na faixa 0 (que já é do tipo `kind`).
fn pure(e: &mut Engine, kind: u32) {
    let set = |e: &mut Engine, params: &[(u32, f32)]| params.iter().for_each(|&(id, v)| e.set_param(0, id, v));
    match kind {
        kind::SYNTH => {
            use synth_param as P;
            set(e, &[(P::OSC1_WAVE, 3.0), (P::OSC2_LEVEL, 0.0), (P::CUTOFF, 20_000.0), (P::RESONANCE, 0.0), (P::FILTER_ENV, 0.0), (P::KEYTRACK, 0.0)]);
            set(e, &[(P::AMP_ATTACK, 0.0005), (P::AMP_SUSTAIN, 1.0), (P::AMP_RELEASE, 0.001), (P::LEVEL, 0.7)]);
        }
        kind::FM => {
            use fm_param as P;
            set(e, &[(P::ALGORITHM, 7.0), (P::FEEDBACK, 0.0)]);
            for n in 0..4 {
                set(e, &[(P::op(n, P::LEVEL), if n == 0 { 1.0 } else { 0.0 }), (P::op(n, P::SUSTAIN), 1.0), (P::op(n, P::VELOCITY), 0.0)]);
                set(e, &[(P::op(n, P::ATTACK), 0.0005), (P::op(n, P::RELEASE), 0.001)]);
            }
        }
        kind::WAVETABLE => {
            use wavetable_param as P;
            set(e, &[(P::OSC1_SERIES, 0.0), (P::OSC1_POS, 0.0), (P::OSC1_LEVEL, 1.0), (P::OSC2_LEVEL, 0.0), (P::CUTOFF, 20_000.0)]);
            set(e, &[(P::RESONANCE, 0.0), (P::FILTER_ENV, 0.0), (P::KEYTRACK, 0.0), (P::AMP_SUSTAIN, 1.0), (P::AMP_ATTACK, 0.0005)]);
            set(e, &[(P::AMP_RELEASE, 0.001)]);
        }
        _ => {}
    }
}

/// O canal esquerdo de `frames` quadros, em blocos de 128.
fn render(e: &mut Engine, frames: usize) -> Vec<f32> {
    let (mut l, mut r) = ([0.0f32; 128], [0.0f32; 128]);
    let mut out = Vec::with_capacity(frames + 128);
    while out.len() < frames {
        e.process(&mut l, &mut r);
        out.extend_from_slice(&l);
    }
    out.truncate(frames);
    out
}

fn rms(x: &[f32]) -> f32 {
    (x.iter().map(|v| v * v).sum::<f32>() / x.len() as f32).sqrt()
}

/// Nível (rms) de `frames` quadros.
fn level(e: &mut Engine, frames: usize) -> f32 {
    rms(&render(e, frames))
}

/// Frequência pelos cruzamentos por zero subindo, com interpolação dentro do quadro.
fn freq(x: &[f32]) -> f32 {
    let (mut first, mut last, mut count) = (None, 0.0, 0);
    for (i, w) in x.windows(2).enumerate() {
        if w[0] < 0.0 && w[1] >= 0.0 {
            let t = i as f64 + f64::from(-w[0] / (w[1] - w[0]));
            first.get_or_insert(t);
            last = t;
            count += 1;
        }
    }
    if count < 3 { 0.0 } else { ((count - 1) as f64 / ((last - first.unwrap()) / RATE)) as f32 }
}

/// Frequência com o motor já assentado: descarta 100 ms e mede 200 ms.
fn settled(e: &mut Engine) -> f32 {
    render(e, 4800);
    freq(&render(e, 9600))
}

fn close(got: f32, want: f32, tol: f32) -> bool {
    (got / want - 1.0).abs() < tol
}

fn semis(n: f32) -> f32 {
    (n / 12.0).exp2()
}

/// Frequências medidas em janelas de 10 ms.
fn track_freq(e: &mut Engine, windows: usize) -> Vec<f32> {
    (0..windows).map(|_| freq(&render(e, 480))).collect()
}

/// Razão entre a maior e a menor frequência medidas.
fn spread(f: &[f32]) -> f32 {
    let (lo, hi) = f.iter().fold((f32::MAX, 0.0f32), |(lo, hi), &v| (lo.min(v), hi.max(v)));
    hi / lo
}

fn sampler_engine() -> Engine {
    let mut e = Engine::new(RATE);
    e.set_track_count(1);
    e.set_track_kind(0, kind::SAMPLER);
    let tone: Vec<f32> = (0..480_000).map(|i| 0.5 * (TAU * 440.0 * i as f32 / RATE as f32).sin()).collect();
    e.load_sample(1, Sample::new(vec![tone], RATE));
    e.set_instrument_sample(0, 1);
    e.set_param(0, sampler_param::ROOT, 69.0);
    e.set_param(0, sampler_param::SUSTAIN, 1.0);
    e.set_param(0, sampler_param::RELEASE, 0.001);
    e
}

// ---------------------------------------------------------------------------------- PitchExpr

#[test]
fn pitch_expr_chega_ao_alvo_sem_degrau() {
    let mut p = PitchExpr::new(48_000.0);
    assert_eq!(p.step(16), 0.0);
    p.set_bend(1.0);
    let mut prev = 0.0;
    let mut first = 0.0;
    for i in 0..3000 {
        let v = p.step(16);
        assert!(v >= prev && v <= 2.0 + 1e-6, "sobe sem passar do alvo: {v}");
        if i == 0 {
            first = v;
        }
        prev = v;
    }
    // a 1ª fatia de 16 quadros (0,3 ms) anda uma fração pequena do caminho
    assert!(first > 0.0 && first < 0.2, "{first}");
    assert!((prev - 2.0).abs() < 1e-3, "{prev}");
    p.set_bend(-1.0);
    for _ in 0..3000 {
        p.step(16);
    }
    assert!((p.step(16) + 2.0).abs() < 1e-3);
}

#[test]
fn pitch_expr_limita_e_ignora_valores_ruins() {
    let mut p = PitchExpr::new(48_000.0);
    p.set_bend(7.5);
    p.snap();
    assert_eq!(p.step(16), 2.0);
    p.set_bend(f32::NAN);
    p.set_bend(f32::INFINITY);
    p.snap();
    assert_eq!(p.step(16), 2.0, "não finito é ignorado");
    p.set_bend(-9.0);
    p.snap();
    assert_eq!(p.step(16), -2.0);
    p.set_range(500.0);
    p.snap();
    assert_eq!(p.step(16), -MAX_BEND_RANGE);
    p.set_range(-3.0);
    p.snap();
    assert_eq!(p.step(16), 0.0, "alcance negativo vira 0");
    p.set_range(f32::NAN);
    p.set_wheel(f32::NAN);
    p.set_vibrato(f32::NAN);
    p.set_vibrato(50.0);
    p.set_wheel(9.0);
    p.snap();
    // roda limitada a 1 e vibrato a MAX_VIBRATO: nunca passa disso
    for _ in 0..2000 {
        assert!(p.step(16).abs() <= MAX_VIBRATO + 1e-4);
    }
}

#[test]
fn pitch_expr_sem_roda_nao_move_a_fase() {
    let mut p = PitchExpr::new(48_000.0);
    for _ in 0..100 {
        assert_eq!(p.step(16), 0.0);
    }
    p.set_wheel(1.0);
    p.snap();
    let v: Vec<f32> = (0..2000).map(|_| p.step(16)).collect();
    assert!(v.iter().any(|&x| x > 0.9) && v.iter().any(|&x| x < -0.9), "vibrato de ±1 semitom");
}

// ---------------------------------------------------------------------------------- bend

#[test]
fn bend_afina_sintetizador_fm_e_wavetable() {
    for k in [kind::SYNTH, kind::FM, kind::WAVETABLE] {
        let mut e = engine(k);
        e.live_on(0, 69, 1.0);
        let base = settled(&mut e);
        assert!(close(base, 440.0, 0.003), "tipo {k}: {base}");
        // alcance padrão ±2 semitons
        for (bend, want) in [(1.0, 2.0), (0.5, 1.0), (-1.0, -2.0), (-0.25, -0.5), (0.0, 0.0)] {
            e.live_bend(0, bend);
            let got = settled(&mut e);
            assert!(close(got, 440.0 * semis(want), 0.004), "tipo {k}: bend {bend} deu {got} Hz");
        }
    }
}

#[test]
fn bend_afina_todas_as_vozes_e_as_notas_novas() {
    let mut e = engine(kind::SYNTH);
    e.live_on(0, 57, 1.0);
    let before = settled(&mut e);
    e.live_bend(0, 1.0);
    // a voz que já soava sobe...
    let held = settled(&mut e);
    assert!(close(held / before, semis(2.0), 0.004), "{held} / {before}");
    // ...e a nota que começa depois já nasce afinada
    e.live_off(0, 57);
    render(&mut e, 4800);
    e.live_on(0, 69, 1.0);
    let fresh = settled(&mut e);
    assert!(close(fresh, 440.0 * semis(2.0), 0.004), "{fresh}");
}

#[test]
fn bend_move_todas_as_vozes_de_um_acorde() {
    // duas notas com a mesma senoide: a soma tem a frequência da mais grave só se não se mexerem
    // uma em relação à outra; com o bend as duas sobem a mesma razão, então o acorde inteiro
    // (o intervalo) se preserva e a frequência da mistura sobe a mesma razão
    let mut e = engine(kind::SYNTH);
    e.live_on(0, 57, 1.0);
    e.live_on(0, 69, 1.0);
    render(&mut e, 9600);
    let flat = freq(&render(&mut e, 9600));
    e.live_bend(0, 1.0);
    render(&mut e, 9600);
    let bent = freq(&render(&mut e, 9600));
    assert!(close(bent / flat, semis(2.0), 0.02), "{bent} / {flat}");
}

#[test]
fn bend_respeita_o_alcance_do_instrumento() {
    for (k, id) in [(kind::SYNTH, synth_param::BEND_RANGE), (kind::FM, fm_param::BEND_RANGE), (kind::WAVETABLE, wavetable_param::BEND_RANGE)] {
        let mut e = engine(k);
        e.set_param(0, id, 12.0);
        e.live_on(0, 60, 1.0);
        e.live_bend(0, 1.0);
        let got = settled(&mut e);
        assert!(close(got, pitch_hz(72.0), 0.004), "tipo {k}: {got}");
        e.set_param(0, id, 0.0);
        let got = settled(&mut e);
        assert!(close(got, pitch_hz(60.0), 0.004), "alcance 0 não move: {got}");
        // fora da faixa é limitado: 24 é o máximo
        e.set_param(0, id, 1000.0);
        let got = settled(&mut e);
        assert!(close(got, pitch_hz(84.0), 0.005), "{got}");
    }
}

#[test]
fn bend_no_limite_e_valores_ruins_nao_quebram() {
    for k in [kind::SYNTH, kind::FM, kind::WAVETABLE, kind::SAMPLER, kind::DRUMS] {
        let mut e = if k == kind::SAMPLER { sampler_engine() } else { engine(k) };
        for id in [synth_param::BEND_RANGE, fm_param::BEND_RANGE, wavetable_param::BEND_RANGE] {
            if k == kind::SYNTH || (k == kind::FM && id == fm_param::BEND_RANGE) || (k == kind::WAVETABLE && id == wavetable_param::BEND_RANGE) {
                e.set_param(0, id, 24.0);
            }
        }
        // nota aguda + bend máximo de 24 semitons passa de Nyquist: nada de NaN nem estouro
        e.live_on(0, 127, 1.0);
        e.live_on(0, 36, 1.0);
        for v in [1.0, -1.0, 100.0, -100.0, f32::NAN, f32::INFINITY, f32::NEG_INFINITY, 0.0, 1.0] {
            e.live_bend(0, v);
            for s in render(&mut e, 2048) {
                assert!(s.is_finite() && s.abs() <= 1.01, "tipo {k}, bend {v}: {s}");
            }
        }
    }
}

#[test]
fn faixa_sem_instrumento_ou_inexistente_e_controle_desconhecido_sao_inocuos() {
    let mut e = Engine::new(RATE);
    e.set_track_count(2);
    // faixa de áudio (sem instrumento), faixa que não existe, controle desconhecido
    e.live_bend(0, 1.0);
    e.live_bend(9, 1.0);
    e.live_cc(0, 64, 1.0);
    e.live_cc(0, 2, 1.0);
    e.live_cc(0, 0, 1.0);
    e.live_cc(0, u32::MAX, 1.0);
    e.set_track_kind(1, kind::SYNTH);
    e.live_on(1, 60, 1.0);
    let a = render(&mut e, 4096);
    let mut control = Engine::new(RATE);
    control.set_track_count(2);
    control.set_track_kind(1, kind::SYNTH);
    control.live_on(1, 60, 1.0);
    assert_eq!(a, render(&mut control, 4096), "nada do que era inválido chegou ao motor");
}

#[test]
fn bend_de_uma_faixa_nao_vaza_para_outra() {
    let mut e = engine(kind::SYNTH);
    e.set_track_count(2);
    e.set_track_kind(1, kind::SYNTH);
    for (id, v) in [(synth_param::OSC1_WAVE, 3.0), (synth_param::OSC2_LEVEL, 0.0), (synth_param::CUTOFF, 20_000.0), (synth_param::FILTER_ENV, 0.0)] {
        e.set_param(1, id, v);
    }
    e.track_mut(0).unwrap().mute = true;
    e.live_bend(0, 1.0);
    e.live_on(1, 69, 1.0);
    let got = settled(&mut e);
    assert!(close(got, 440.0, 0.004), "a faixa 1 não foi dobrada: {got}");
}

#[test]
fn sampler_responde_ao_bend() {
    let mut e = sampler_engine();
    e.live_on(0, 69, 1.0);
    assert!(close(settled(&mut e), 440.0, 0.004));
    e.live_bend(0, 1.0);
    let up = settled(&mut e);
    assert!(close(up, 440.0 * semis(2.0), 0.005), "{up}");
    e.set_param(0, sampler_param::BEND_RANGE, 12.0);
    let oct = settled(&mut e);
    assert!(close(oct, 880.0, 0.005), "{oct}");
    e.live_bend(0, -1.0);
    let down = settled(&mut e);
    assert!(close(down, 220.0, 0.005), "{down}");
    // a nota nova nasce já no bend
    e.live_off(0, 69);
    render(&mut e, 4800);
    e.live_on(0, 69, 1.0);
    let fresh = settled(&mut e);
    assert!(close(fresh, 220.0, 0.005), "{fresh}");
}

#[test]
fn bateria_ignora_bend_modulacao_e_pedal() {
    let run = |touch: bool| {
        let mut e = engine(kind::DRUMS);
        if touch {
            e.live_bend(0, 1.0);
            e.live_cc(0, 1, 1.0);
            e.live_cc(0, 64, 1.0);
        }
        e.live_on(0, 36, 1.0);
        let mut out = render(&mut e, 2048);
        e.live_off(0, 36);
        e.live_on(0, 38, 1.0);
        e.live_off(0, 38);
        out.extend(render(&mut e, 4096));
        out
    };
    let (touched, clean) = (run(true), run(false));
    assert!(rms(&clean) > 0.001);
    assert_eq!(touched, clean, "a bateria não muda com bend, roda ou pedal");
}

// ---------------------------------------------------------------------------------- modulação

#[test]
fn roda_de_modulacao_liga_o_vibrato_nos_tres_instrumentos() {
    for (k, range) in [(kind::SYNTH, synth_param::VIBRATO_RANGE), (kind::FM, fm_param::VIBRATO_RANGE), (kind::WAVETABLE, wavetable_param::VIBRATO_RANGE)] {
        let mut e = engine(k);
        e.live_on(0, 84, 1.0);
        render(&mut e, 4800);
        let flat = spread(&track_freq(&mut e, 40));
        assert!(flat < 1.01, "tipo {k}: sem roda não há vibrato ({flat})");

        e.live_cc(0, 1, 1.0);
        render(&mut e, 12_000);
        let deep = spread(&track_freq(&mut e, 40));
        // ±1 semitom = razão 2^(2/12) = 1,122 entre o pico e o vale
        assert!((1.09..1.15).contains(&deep), "tipo {k}: {deep}");

        e.live_cc(0, 1, 0.5);
        render(&mut e, 12_000);
        let half = spread(&track_freq(&mut e, 40));
        assert!((1.04..1.075).contains(&half), "tipo {k}: meia roda, {half}");

        // o alcance do vibrato é o parâmetro
        e.set_param(0, range, 0.0);
        render(&mut e, 4800);
        let none = spread(&track_freq(&mut e, 40));
        assert!(none < 1.01, "tipo {k}: alcance 0, {none}");
        e.set_param(0, range, 2.0);
        render(&mut e, 4800);
        let wide = spread(&track_freq(&mut e, 40));
        assert!(wide > 1.09, "tipo {k}: alcance 2 com meia roda, {wide}");

        // soltar a roda apaga o vibrato
        e.live_cc(0, 1, 0.0);
        render(&mut e, 24_000);
        assert!(spread(&track_freq(&mut e, 40)) < 1.01, "tipo {k}");
    }
}

#[test]
fn sampler_tambem_faz_vibrato_com_a_roda() {
    let mut e = sampler_engine();
    e.live_on(0, 81, 1.0);
    e.live_cc(0, 1, 1.0);
    render(&mut e, 12_000);
    let deep = spread(&track_freq(&mut e, 40));
    assert!((1.09..1.15).contains(&deep), "{deep}");
}

#[test]
fn vibrato_roda_a_5_5_hz_e_nao_muda_o_volume() {
    let mut e = engine(kind::SYNTH);
    e.live_on(0, 84, 1.0);
    e.live_cc(0, 1, 1.0);
    render(&mut e, 12_000);
    let f = track_freq(&mut e, 100);
    let mean = f.iter().sum::<f32>() / f.len() as f32;
    let crossings = f.windows(2).filter(|w| (w[0] - mean) * (w[1] - mean) < 0.0).count();
    // 1 s de janelas de 10 ms: 5,5 ciclos, 11 cruzamentos da média
    assert!((9..=13).contains(&crossings), "{crossings}");
    let flat = {
        let mut e = engine(kind::SYNTH);
        e.live_on(0, 84, 1.0);
        render(&mut e, 12_000);
        rms(&render(&mut e, 9600))
    };
    let with_wheel = rms(&render(&mut e, 9600));
    assert!((with_wheel / flat - 1.0).abs() < 0.03, "{with_wheel} {flat}");
}

#[test]
fn bend_e_vibrato_somam() {
    let mut e = engine(kind::SYNTH);
    e.live_on(0, 84, 1.0);
    e.live_bend(0, 1.0);
    e.live_cc(0, 1, 1.0);
    render(&mut e, 12_000);
    let f = track_freq(&mut e, 40);
    let mean = f.iter().sum::<f32>() / f.len() as f32;
    // o vibrato oscila em torno da nota já dobrada
    assert!(close(mean, pitch_hz(86.0), 0.03), "{mean}");
    assert!(spread(&f) > 1.09);
}

// ---------------------------------------------------------------------------------- sustain ao vivo

#[test]
fn sem_pedal_a_nota_solta_some() {
    let mut e = engine(kind::SYNTH);
    e.live_on(0, 60, 1.0);
    assert!(level(&mut e, 4800) > 0.05);
    e.live_off(0, 60);
    render(&mut e, 2400);
    assert!(level(&mut e, 4800) < 1e-4);
}

#[test]
fn pedal_segura_a_nota_solta_ate_soltar_o_pedal() {
    let mut e = engine(kind::SYNTH);
    e.live_cc(0, 64, 1.0);
    e.live_on(0, 60, 1.0);
    render(&mut e, 4800);
    e.live_off(0, 60);
    render(&mut e, 2400);
    assert!(level(&mut e, 24_000) > 0.05, "segurada pelo pedal");
    assert_eq!(e.lanes[0].pending_pitches(), 1);
    e.live_cc(0, 64, 0.0);
    render(&mut e, 2400);
    assert!(level(&mut e, 4800) < 1e-4, "o pedal solto libera");
    assert_eq!(e.lanes[0].pending_pitches(), 0);
}

#[test]
fn pedal_solto_libera_varias_notas_presas_de_uma_vez() {
    let mut e = engine(kind::SYNTH);
    let pitches = [48, 55, 60, 64, 67, 72, 79, 84, 96, 33];
    e.live_cc(0, 64, 1.0);
    for p in pitches {
        e.live_on(0, p, 0.9);
    }
    render(&mut e, 4800);
    for p in pitches {
        e.live_off(0, p);
    }
    // a polifonia é 8: as duas primeiras foram roubadas, mas o pedal registra as dez alturas
    assert_eq!(e.lanes[0].pending_pitches(), 10);
    assert!(level(&mut e, 12_000) > 0.05);
    e.live_cc(0, 64, 0.0);
    render(&mut e, 2400);
    assert!(level(&mut e, 4800) < 1e-4);
    assert_eq!(e.lanes[0].pending_pitches(), 0);
}

#[test]
fn nota_solta_antes_do_pedal_descer_nao_ressuscita() {
    let mut e = engine(kind::SYNTH);
    e.live_on(0, 60, 1.0);
    render(&mut e, 4800);
    e.live_off(0, 60);
    render(&mut e, 2400);
    e.live_cc(0, 64, 1.0);
    assert!(level(&mut e, 4800) < 1e-4, "o pedal não traz de volta o que já soltou");
    // (o note off que já passou não fica pendente: o pedal só registra o que solta depois de descer)
    assert_eq!(e.lanes[0].pending_pitches(), 0);
}

#[test]
fn tecla_apertada_quando_o_pedal_desce_e_solta_depois_fica_segura() {
    let mut e = engine(kind::SYNTH);
    e.live_on(0, 60, 1.0);
    e.live_on(0, 64, 1.0);
    render(&mut e, 4800);
    e.live_cc(0, 64, 1.0);
    e.live_off(0, 60);
    render(&mut e, 4800);
    assert_eq!(e.lanes[0].pending_pitches(), 1);
    e.live_cc(0, 64, 0.0);
    // a 64 continua apertada e soando; só a 60 foi liberada
    render(&mut e, 4800);
    assert!(level(&mut e, 4800) > 0.05);
    e.live_off(0, 64);
    render(&mut e, 2400);
    assert!(level(&mut e, 4800) < 1e-4);
}

#[test]
fn pedal_solto_com_a_tecla_ainda_apertada_nao_corta() {
    let mut e = engine(kind::SYNTH);
    e.live_cc(0, 64, 1.0);
    e.live_on(0, 60, 1.0);
    render(&mut e, 4800);
    e.live_cc(0, 64, 0.0);
    assert!(level(&mut e, 9600) > 0.05, "a tecla segue apertada");
}

#[test]
fn reatacar_a_nota_segurada_pelo_pedal_e_soltar_de_novo() {
    let mut e = engine(kind::SYNTH);
    e.live_cc(0, 64, 1.0);
    e.live_on(0, 60, 1.0);
    e.live_off(0, 60);
    render(&mut e, 4800);
    e.live_on(0, 60, 1.0);
    // apertada de novo: o pedido de soltar antigo não vale mais
    assert_eq!(e.lanes[0].pending_pitches(), 0);
    e.live_cc(0, 64, 0.0);
    assert!(level(&mut e, 9600) > 0.05, "a nota reatacada segue apertada");
    e.live_off(0, 60);
    render(&mut e, 2400);
    assert!(level(&mut e, 4800) < 1e-4);
}

#[test]
fn pedal_tem_limiar_em_meio_e_aceita_valores_extremos() {
    let mut e = engine(kind::SYNTH);
    // 63/127 solta, 64/127 desce (0,504)
    e.live_cc(0, 64, 63.0 / 127.0);
    e.live_on(0, 60, 1.0);
    e.live_off(0, 60);
    assert_eq!(e.lanes[0].pending_pitches(), 0);
    e.live_cc(0, 64, 64.0 / 127.0);
    e.live_on(0, 60, 1.0);
    e.live_off(0, 60);
    assert_eq!(e.lanes[0].pending_pitches(), 1);
    e.live_cc(0, 64, -5.0);
    assert_eq!(e.lanes[0].pending_pitches(), 0, "negativo é limitado a 0: pedal solto");
    e.live_cc(0, 64, 99.0);
    e.live_on(0, 62, 1.0);
    e.live_off(0, 62);
    assert_eq!(e.lanes[0].pending_pitches(), 1, "acima de 1 é limitado: embaixo");
    // não finito é ignorado: o pedal continua embaixo
    e.live_cc(0, 64, f32::NAN);
    e.live_cc(0, 64, f32::NEG_INFINITY);
    e.live_on(0, 64, 1.0);
    e.live_off(0, 64);
    assert_eq!(e.lanes[0].pending_pitches(), 2);
}

#[test]
fn pedal_repetido_nao_solta_de_novo() {
    let mut e = engine(kind::SYNTH);
    e.live_cc(0, 64, 1.0);
    e.live_on(0, 60, 1.0);
    e.live_off(0, 60);
    e.live_cc(0, 64, 1.0);
    e.live_cc(0, 64, 0.9);
    assert_eq!(e.lanes[0].pending_pitches(), 1);
}

#[test]
fn pedal_funciona_no_fm_wavetable_e_sampler() {
    for k in [kind::FM, kind::WAVETABLE] {
        let mut e = engine(k);
        e.live_cc(0, 64, 1.0);
        e.live_on(0, 60, 1.0);
        render(&mut e, 4800);
        e.live_off(0, 60);
        render(&mut e, 2400);
        assert!(level(&mut e, 12_000) > 0.05, "tipo {k}");
        e.live_cc(0, 64, 0.0);
        render(&mut e, 4800);
        assert!(level(&mut e, 4800) < 1e-3, "tipo {k}");
    }
    let mut e = sampler_engine();
    e.live_cc(0, 64, 1.0);
    e.live_on(0, 60, 1.0);
    render(&mut e, 4800);
    e.live_off(0, 60);
    render(&mut e, 2400);
    assert!(level(&mut e, 12_000) > 0.05, "sampler");
    e.live_cc(0, 64, 0.0);
    render(&mut e, 4800);
    assert!(level(&mut e, 4800) < 1e-3);
}

#[test]
fn panic_zera_bend_roda_e_pedal() {
    let mut e = engine(kind::SYNTH);
    e.live_bend(0, 1.0);
    e.live_cc(0, 1, 1.0);
    e.live_cc(0, 64, 1.0);
    e.live_on(0, 60, 1.0);
    e.live_off(0, 60);
    assert_eq!(e.lanes[0].pending_pitches(), 1);
    e.panic();
    assert_eq!(e.lanes[0].pending_pitches(), 0);
    assert!(level(&mut e, 4800) < 1e-6, "tudo calado");
    // a nota seguinte sai afinada e sem vibrato, e o pedal já não segura
    e.live_on(0, 69, 1.0);
    let f = settled(&mut e);
    assert!(close(f, 440.0, 0.004), "{f}");
    assert!(spread(&track_freq(&mut e, 20)) < 1.01);
    e.live_off(0, 69);
    render(&mut e, 2400);
    assert!(level(&mut e, 4800) < 1e-4);
}

#[test]
fn trocar_o_tipo_da_faixa_reinicia_a_expressao() {
    let mut e = engine(kind::SYNTH);
    e.live_bend(0, 1.0);
    e.live_cc(0, 64, 1.0);
    e.live_on(0, 60, 1.0);
    e.live_off(0, 60);
    assert_eq!(e.lanes[0].pending_pitches(), 1);
    e.set_track_kind(0, kind::FM);
    assert_eq!(e.lanes[0].pending_pitches(), 0);
    // bateria não segura notas com o pedal
    e.set_track_kind(0, kind::DRUMS);
    e.live_cc(0, 64, 1.0);
    e.live_on(0, 36, 1.0);
    e.live_off(0, 36);
    assert_eq!(e.lanes[0].pending_pitches(), 0);
    e.set_track_kind(0, kind::SYNTH);
    pure(&mut e, kind::SYNTH);
    e.live_on(0, 69, 1.0);
    let f = settled(&mut e);
    assert!(close(f, 440.0, 0.004), "o instrumento novo nasce sem bend: {f}");
}

// ---------------------------------------------------------------------------------- clipe

#[test]
fn eventos_de_controle_entram_ordenados_e_valores_invalidos_sao_ignorados() {
    let mut e = engine(kind::SYNTH);
    e.add_cc(0, 128, 2.0, 0.5);
    e.add_cc(0, 128, 1.0, -0.5);
    e.add_cc(0, 64, 1.0, 1.0);
    e.add_cc(0, 64, 1.0, 0.0);
    e.add_cc(0, 1, 3.0, 5.0);
    e.add_cc(0, 1, -4.0, 0.5);
    // ignorados: controle desconhecido, valor ou batida não finitos, faixa que não existe
    e.add_cc(0, 7, 1.0, 1.0);
    e.add_cc(0, 128, f64::NAN, 1.0);
    e.add_cc(0, 128, f64::INFINITY, 1.0);
    e.add_cc(0, 128, 1.0, f32::NAN);
    e.add_cc(5, 128, 1.0, 1.0);
    render(&mut e, 128);
    let ev: Vec<(f64, u8, f32)> = e.lanes[0].cc.iter().map(|c| (c.beat, c.cc, c.value)).collect();
    assert_eq!(ev, [(0.0, CC_MOD, 0.5), (1.0, CC_BEND, -0.5), (1.0, CC_SUSTAIN, 1.0), (1.0, CC_SUSTAIN, 0.0), (2.0, CC_BEND, 0.5), (3.0, CC_MOD, 1.0)]);
}

#[test]
fn notes_clear_nao_apaga_os_controles_e_cc_clear_sim() {
    let mut e = engine(kind::SYNTH);
    e.add_cc(0, 128, 1.0, 1.0);
    e.clear_notes();
    render(&mut e, 128);
    assert_eq!(e.lanes[0].cc.len(), 1);
    e.clear_cc();
    render(&mut e, 128);
    assert!(e.lanes[0].cc.is_empty());
}

#[test]
fn clipe_dobra_a_nota_na_batida_do_evento() {
    let mut e = engine(kind::SYNTH);
    e.add_note(0, 0.0, 4.0, 69, 1.0);
    e.add_cc(0, 128, 1.0, 1.0);
    e.play();
    // batida 0 a 1: sem bend
    render(&mut e, BEAT / 2);
    let before = freq(&render(&mut e, BEAT / 4));
    assert!(close(before, 440.0, 0.004), "{before}");
    // depois da batida 1 (mais a latência do limitador e a suavização): dobrada
    render(&mut e, BEAT / 4 + 2400 + 4800);
    let after = freq(&render(&mut e, 9600));
    assert!(close(after, 440.0 * semis(2.0), 0.004), "{after}");
}

#[test]
fn eventos_do_clipe_soam_igual_em_qualquer_tamanho_de_bloco() {
    let go = |sizes: &[usize]| {
        let mut e = engine(kind::SYNTH);
        e.add_note(0, 0.0, 8.0, 69, 1.0);
        for (i, b) in [0.0, 0.7, 1.31, 2.0, 2.0004, 3.5].iter().enumerate() {
            e.add_cc(0, 128, *b, if i % 2 == 0 { 1.0 } else { -0.7 });
            e.add_cc(0, 1, *b + 0.1, (i as f32 * 0.37).fract());
            e.add_cc(0, 64, *b + 0.2, (i % 2) as f32);
        }
        e.play();
        let mut out = Vec::new();
        let (mut l, mut r) = (vec![0.0f32; 4096], vec![0.0f32; 4096]);
        let mut i = 0;
        while out.len() < BEAT * 5 {
            let n = sizes[i % sizes.len()];
            i += 1;
            e.process(&mut l[..n], &mut r[..n]);
            out.extend_from_slice(&l[..n]);
        }
        out.truncate(BEAT * 5);
        out
    };
    let a = go(&[128]);
    assert!(rms(&a) > 0.05);
    assert!(a == go(&[4096]), "blocos de 4096");
    assert!(a == go(&[256, 1024, 128, 4096, 384, 640, 2048]), "blocos variados");
}

#[test]
fn eventos_no_mesmo_instante_valem_na_ordem_em_que_chegaram() {
    // pedal desce, sobe e desce na mesma batida: vale o último
    let mut e = engine(kind::SYNTH);
    e.add_cc(0, 64, 0.0, 1.0);
    e.add_cc(0, 64, 0.0, 0.0);
    e.add_cc(0, 64, 0.0, 1.0);
    e.play();
    render(&mut e, 256);
    e.live_on(0, 60, 1.0);
    e.live_off(0, 60);
    assert_eq!(e.lanes[0].pending_pitches(), 1);
    // e ao contrário: vale o último, solto
    let mut e = engine(kind::SYNTH);
    e.add_cc(0, 64, 0.0, 0.0);
    e.add_cc(0, 64, 0.0, 1.0);
    e.add_cc(0, 64, 0.0, 0.0);
    e.play();
    render(&mut e, 256);
    e.live_on(0, 60, 1.0);
    e.live_off(0, 60);
    assert_eq!(e.lanes[0].pending_pitches(), 0);
}

#[test]
fn pedal_do_clipe_segura_a_nota_do_clipe() {
    let mut e = engine(kind::SYNTH);
    // nota de 1 batida; pedal de 0 a 3 batidas
    e.add_note(0, 0.0, 1.0, 60, 1.0);
    e.add_cc(0, 64, 0.0, 1.0);
    e.add_cc(0, 64, 3.0, 0.0);
    e.play();
    render(&mut e, BEAT + 4800);
    // a nota acabou na batida 1, mas o pedal a segura até a 3
    assert!(level(&mut e, BEAT) > 0.05, "batida 1 a 2");
    assert!(level(&mut e, BEAT / 2) > 0.05, "batida 2 a 2,5");
    // passou a batida 3 (com a latência do limitador): silêncio
    render(&mut e, BEAT / 2 + 4800);
    assert!(level(&mut e, 9600) < 1e-4);
}

#[test]
fn sem_pedal_a_nota_do_clipe_acaba_no_fim() {
    let mut e = engine(kind::SYNTH);
    e.add_note(0, 0.0, 1.0, 60, 1.0);
    e.play();
    render(&mut e, BEAT + 4800);
    assert!(level(&mut e, 9600) < 1e-4);
}

#[test]
fn pedal_sobe_na_batida_de_uma_nota_solta_as_anteriores_antes_dela() {
    let mut e = engine(kind::SYNTH);
    // nota A (60) de 0 a 1, pedal de 0 a 2; nota B (64) começa em 2, quando o pedal sobe
    e.add_note(0, 0.0, 1.0, 60, 1.0);
    e.add_note(0, 2.0, 1.0, 64, 1.0);
    e.add_cc(0, 64, 0.0, 1.0);
    e.add_cc(0, 64, 2.0, 0.0);
    e.play();
    // a saída do limitador atrasa alguns quadros em relação ao motor: mede-se pelo estado
    render(&mut e, 2 * BEAT - 512);
    assert_eq!(e.lanes[0].pending_pitches(), 1, "A esperando o pedal");
    render(&mut e, 1024);
    assert_eq!(e.lanes[0].pending_pitches(), 0, "o pedal subiu");
    // B soa: a liberação de A não a cortou
    assert!(level(&mut e, 4800) > 0.05);
}

#[test]
fn pedal_desce_na_batida_da_nota_e_a_segura() {
    let mut e = engine(kind::SYNTH);
    e.add_note(0, 1.0, 0.5, 60, 1.0);
    e.add_cc(0, 64, 1.0, 1.0);
    e.play();
    render(&mut e, BEAT + BEAT / 2 + 2400 + 2048);
    assert_eq!(e.lanes[0].pending_pitches(), 1);
}

#[test]
fn seek_reconstitui_o_estado_dos_controles_do_clipe() {
    let mut e = engine(kind::SYNTH);
    e.add_cc(0, 128, 1.0, 1.0);
    e.add_cc(0, 128, 4.0, 0.0);
    e.add_cc(0, 64, 1.0, 1.0);
    e.add_cc(0, 64, 5.0, 0.0);
    e.seek(2.0);
    e.play();
    render(&mut e, 256);
    // começou no meio do trecho com bend e pedal: as notas ao vivo já pegam os dois
    e.live_on(0, 69, 1.0);
    let f = settled(&mut e);
    assert!(close(f, 440.0 * semis(2.0), 0.004), "{f}");
    e.live_off(0, 69);
    assert_eq!(e.lanes[0].pending_pitches(), 1);
    // pula para antes do primeiro evento: o estado neutro volta e o pedal libera a nota
    e.seek(0.0);
    render(&mut e, 512);
    assert_eq!(e.lanes[0].pending_pitches(), 0);
    e.live_on(0, 69, 1.0);
    let f = settled(&mut e);
    assert!(close(f, 440.0, 0.004), "{f}");
    // pula para depois do último: fim do clipe, tudo neutro
    e.live_off(0, 69);
    e.seek(9.0);
    render(&mut e, 512);
    e.live_on(0, 69, 1.0);
    let f = settled(&mut e);
    assert!(close(f, 440.0, 0.004), "{f}");
}

#[test]
fn parar_devolve_ao_neutro_o_que_o_clipe_dirigia_e_deixa_o_que_era_ao_vivo() {
    let mut e = engine(kind::SYNTH);
    e.add_cc(0, 128, 0.0, 1.0);
    e.add_cc(0, 64, 0.0, 1.0);
    e.play();
    render(&mut e, 4800);
    e.live_on(0, 69, 1.0);
    e.stop();
    render(&mut e, 4800);
    e.live_off(0, 69);
    render(&mut e, 4800);
    assert!(level(&mut e, 4800) < 1e-4, "o pedal do clipe não segura nada depois de parar");
    e.live_on(0, 69, 1.0);
    let f = settled(&mut e);
    assert!(close(f, 440.0, 0.004), "bend do clipe zerado: {f}");
    // já o bend que veio ao vivo, sem evento de bend no clipe, fica
    let mut e = engine(kind::SYNTH);
    e.add_cc(0, 64, 0.0, 1.0);
    e.live_bend(0, 1.0);
    e.play();
    render(&mut e, 4800);
    e.stop();
    render(&mut e, 4800);
    e.live_on(0, 69, 1.0);
    let f = settled(&mut e);
    assert!(close(f, 440.0 * semis(2.0), 0.004), "{f}");
}

#[test]
fn apagar_os_eventos_com_o_transporte_tocando_volta_ao_neutro() {
    let mut e = engine(kind::SYNTH);
    e.add_note(0, 0.0, 16.0, 69, 1.0);
    e.add_cc(0, 128, 0.0, 1.0);
    e.play();
    let bent = settled(&mut e);
    assert!(close(bent, 440.0 * semis(2.0), 0.004));
    e.clear_cc();
    let back = settled(&mut e);
    assert!(close(back, 440.0, 0.004), "{back}");
    // o app reenvia tudo a cada sincronização: reenviar os mesmos eventos não muda nada
    e.add_cc(0, 128, 0.0, 1.0);
    let again = settled(&mut e);
    assert!(close(again, 440.0 * semis(2.0), 0.004), "{again}");
}

#[test]
fn reenviar_o_clipe_com_o_pedal_embaixo_nao_corta_a_nota_segura() {
    let mut e = engine(kind::SYNTH);
    e.add_note(0, 0.0, 0.5, 60, 1.0);
    e.add_cc(0, 64, 0.0, 1.0);
    e.play();
    render(&mut e, BEAT);
    assert_eq!(e.lanes[0].pending_pitches(), 1);
    // sincronização: apaga e reenvia notas e eventos
    e.clear_notes();
    e.clear_cc();
    e.add_note(0, 0.0, 0.5, 60, 1.0);
    e.add_cc(0, 64, 0.0, 1.0);
    render(&mut e, 4800);
    assert_eq!(e.lanes[0].pending_pitches(), 1, "a nota segue esperando o pedal");
    assert!(level(&mut e, 4800) > 0.05);
}

#[test]
fn loop_reconstitui_o_pedal_na_volta() {
    let mut e = engine(kind::SYNTH);
    // pedal desce na batida 0 e sobe na 1 (dentro do loop de 0 a 2)
    e.add_note(0, 0.0, 0.25, 60, 1.0);
    e.add_cc(0, 64, 0.0, 1.0);
    e.add_cc(0, 64, 1.0, 0.0);
    e.set_loop(true, 0.0, 2.0);
    e.play();
    render(&mut e, BEAT / 2);
    assert_eq!(e.lanes[0].pending_pitches(), 1);
    render(&mut e, BEAT);
    assert_eq!(e.lanes[0].pending_pitches(), 0, "subiu na batida 1");
    // dá a volta em 2 e o pedal desce de novo na batida 0 do loop, segurando a nota nova
    render(&mut e, BEAT + BEAT / 4);
    assert_eq!(e.lanes[0].pending_pitches(), 1);
}

#[test]
fn documento_sem_eventos_soa_exatamente_como_antes() {
    // sem evento algum e com roda, bend e pedal nos valores neutros: bit a bit igual a não mexer
    let run = |touch: bool| {
        let mut e = engine(kind::SYNTH);
        e.add_note(0, 0.0, 1.0, 60, 0.8);
        e.add_note(0, 1.0, 1.0, 67, 0.8);
        if touch {
            e.live_bend(0, 0.0);
            e.live_cc(0, 1, 0.0);
            e.live_cc(0, 64, 0.0);
        }
        e.play();
        render(&mut e, 3 * BEAT)
    };
    let a = run(false);
    assert!(rms(&a) > 0.05);
    assert_eq!(a, run(true));
}

#[test]
fn processar_controles_nao_aloca() {
    let mut e = engine(kind::SYNTH);
    e.add_note(0, 0.0, 4.0, 60, 1.0);
    for i in 0..200 {
        e.add_cc(0, 128, i as f64 * 0.05, ((i % 7) as f32 - 3.0) / 3.0);
        e.add_cc(0, 64, i as f64 * 0.11, (i % 2) as f32);
    }
    render(&mut e, 128);
    e.play();
    let allocs = crate::testalloc::count(|| {
        let (mut l, mut r) = ([0.0f32; 128], [0.0f32; 128]);
        for i in 0..2000 {
            e.live_bend(0, (i % 9) as f32 / 4.0 - 1.0);
            e.live_cc(0, 1, (i % 5) as f32 / 4.0);
            e.live_cc(0, 64, (i % 3) as f32 / 2.0);
            e.live_on(0, 60 + (i % 12) as u32, 0.8);
            e.live_off(0, 60 + ((i + 5) % 12) as u32);
            e.process(&mut l, &mut r);
        }
    });
    assert_eq!(allocs, 0, "o caminho de áudio não pode alocar");
}

// ---------------------------------------------------------------------------------- gravação

/// Lê o registro inteiro: (faixa, código, início, fim, valor).
fn drain(e: &mut Engine) -> Vec<[f32; 5]> {
    let mut buf = vec![0.0f32; 5 * 64];
    let n = e.rec_notes(&mut buf);
    buf[..n].chunks(5).map(|c| [c[0], c[1], c[2], c[3], c[4]]).collect()
}

#[test]
fn gravacao_registra_os_controles_com_a_batida_de_agora() {
    let mut e = engine(kind::SYNTH);
    e.rec_notes_start();
    // parado: nada entra
    e.live_cc(0, 64, 1.0);
    e.live_bend(0, 0.5);
    e.play();
    render(&mut e, BEAT);
    e.live_on(0, 60, 0.8);
    e.live_bend(0, -0.25);
    e.live_cc(0, 1, 0.75);
    e.live_cc(0, 64, 1.0);
    e.live_cc(0, 9, 1.0); // desconhecido: não entra
    render(&mut e, 128);
    e.live_off(0, 60);
    e.rec_notes_stop();
    let rec = drain(&mut e);
    let codes: Vec<f32> = rec.iter().map(|r| r[1]).collect();
    assert_eq!(codes, [60.0, 384.0, 257.0, 320.0], "{codes:?}");
    // a nota tem velocidade; os eventos são pontos (início = fim) com o valor no último campo
    let note = rec.iter().find(|r| r[1] == 60.0).unwrap();
    assert_eq!(note[4], 0.8);
    let vals: Vec<f32> = rec.iter().filter(|r| r[1] >= 256.0).map(|r| r[4]).collect();
    assert_eq!(vals, [-0.25, 0.75, 1.0]);
    for r in rec.iter().filter(|r| r[1] >= 256.0) {
        assert_eq!(r[2], r[3]);
        assert!((r[2] - 1.0).abs() < 0.1, "batida {}", r[2]);
    }
    assert!(rec.iter().all(|r| r[0] == 0.0));
}

#[test]
fn os_controles_nao_tomam_o_lugar_das_notas_no_registro() {
    use crate::record::{MAX_REC_CCS, MAX_REC_NOTES, NoteRecorder};
    let mut r = NoteRecorder::new();
    r.start();
    for i in 0..MAX_REC_CCS + 100 {
        r.cc(0, CC_BEND, (i % 3) as f32 - 1.0, i as f64 * 0.01);
    }
    assert_eq!(r.dropped(), 100);
    // as notas têm a cota delas, intacta
    for i in 0..MAX_REC_NOTES {
        r.note_on(0, (i % 128) as u8, 1.0, i as f64);
        r.note_off(0, (i % 128) as u8, i as f64 + 0.5);
    }
    assert_eq!(r.dropped(), 100);
    assert_eq!(r.len(), MAX_REC_CCS + MAX_REC_NOTES);
    // ler em pedaços mantém a contagem de eventos coerente
    let mut buf = vec![0.0f32; 5 * 1000];
    while !r.is_empty() {
        r.drain(&mut buf, 0.0);
    }
    r.cc(0, CC_MOD, 0.5, 1.0);
    for _ in 0..MAX_REC_CCS {
        r.cc(0, CC_MOD, 0.5, 1.0);
    }
    assert_eq!(r.len(), MAX_REC_CCS, "a cota dos eventos voltou inteira depois de ler tudo");
}

#[test]
fn salto_do_loop_com_tecla_segurada_parte_so_as_notas() {
    let mut e = engine(kind::SYNTH);
    e.rec_notes_start();
    e.set_loop(true, 0.0, 1.0);
    e.play();
    e.live_on(0, 60, 1.0);
    e.live_bend(0, 0.5);
    render(&mut e, BEAT + 4800);
    e.live_off(0, 60);
    e.rec_notes_stop();
    let rec = drain(&mut e);
    assert_eq!(rec.iter().filter(|r| r[1] == 384.0).count(), 1, "o salto do loop não duplica controles");
    assert!(rec.iter().filter(|r| r[1] == 60.0).count() >= 2, "a tecla foi partida no salto");
}
