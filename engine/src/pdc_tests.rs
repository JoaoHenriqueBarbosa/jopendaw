//! Testes da compensação de latência dos efeitos (PDC): equivalência com o motor de antes quando
//! nenhum efeito tem latência (quadro a quadro, por hash gravado do motor anterior à PDC),
//! alinhamento de faixas, barramentos, envios e sidechain, bypass sem estalo, render offline igual
//! ao tempo real e ausência de alocação.

use super::*;
use crate::effect::{Effect, auto_target, kind as fx_kind};
use crate::instrument::kind;

const RATE: f64 = 48_000.0;

/// Hash FNV-1a dos bits de uma sequência de blocos.
struct Hasher(u64);

impl Hasher {
    fn new() -> Self {
        Self(0xcbf29ce484222325)
    }

    fn feed(&mut self, l: &[f32], r: &[f32]) {
        for s in l.iter().chain(r) {
            self.0 = (self.0 ^ u64::from(s.to_bits())).wrapping_mul(0x100000001b3);
        }
    }
}

/// Cena com clipes, sintetizador, bateria, sampler, efeitos SEM latência em faixa, barramento e
/// master, envios pré e pós, saída roteada, sidechain, automação, loop, metrônomo, seek e parada.
fn plain_scene(e: &mut Engine) {
    use effect::{compressor_param as cp, delay_param as dp, reverb_param as rp};
    e.set_tempo(128.0, 4);
    e.set_track_count(6);
    let noise: Vec<f32> = (0..96_000u32).map(|i| ((i.wrapping_mul(2_654_435_761) >> 8) as f32 / 16_777_216.0 - 0.5) * 0.6).collect();
    let tone: Vec<f32> = (0..48_000).map(|i| (i as f32 * 0.05).sin() * 0.5).collect();
    e.load_sample(1, Sample::new(vec![noise.clone(), noise.iter().rev().copied().collect()], 44_100.0));
    e.load_sample(2, Sample::new(vec![tone], RATE));
    e.add_clip(Clip { track: 0, sample: 1, start: 0.5, offset: 0.1, length: 1.5, gain: 0.8, fade_in: 0.01, fade_out: 0.2 });
    e.set_track_kind(1, kind::SYNTH);
    e.set_track_kind(2, kind::DRUMS);
    e.set_track_kind(3, kind::SAMPLER);
    e.set_track_kind(4, kind::BUS);
    e.set_track_kind(5, kind::BUS);
    e.set_instrument_sample(3, 2);
    for (i, p) in [60, 64, 67, 72].into_iter().enumerate() {
        e.add_note(1, i as f64 * 0.75, 1.0, p, 0.9);
        e.add_note(3, 0.25 + i as f64 * 0.5, 0.4, p - 12, 0.7);
    }
    for i in 0..16 {
        e.add_note(2, i as f64 * 0.25, 0.1, [36, 42, 38, 42][i % 4], 1.0);
    }
    e.set_fx(0, 0, fx_kind::EQ);
    e.set_fx(0, 1, fx_kind::COMPRESSOR);
    e.set_fx_param(0, 1, cp::SIDECHAIN, 2.0);
    e.set_fx_param(0, 1, cp::THRESHOLD, -30.0);
    e.set_fx(0, 2, fx_kind::GATE);
    e.set_fx(1, 0, fx_kind::CHORUS);
    e.set_fx(1, 1, fx_kind::PHASER);
    e.set_fx(1, 2, fx_kind::FILTER);
    e.set_sends_count(1, 2);
    e.set_send(1, 0, 4, 0.6, false);
    e.set_send(1, 1, 5, 0.4, true);
    e.set_output(3, 4);
    e.set_output(4, 5);
    e.set_fx(4, 0, fx_kind::REVERB);
    e.set_fx_param(4, 0, rp::MIX, 0.5);
    e.set_fx(4, 1, fx_kind::DELAY);
    e.set_fx_param(4, 1, dp::FEEDBACK, 0.5);
    e.set_fx(5, 0, fx_kind::TREMOLO);
    e.set_fx(-1, 0, fx_kind::COMPRESSOR);
    e.set_fx(-1, 1, fx_kind::UTILITY);
    e.master_mut().gain = 1.5;
    let vol = e.add_lane(1, auto_target::VOLUME, 0, 0);
    e.add_point(vol, 0.0, 0.2, 0.0);
    e.add_point(vol, 2.0, 1.0, 0.5);
    let cut = e.add_lane(1, auto_target::EFFECT, 2, effect::filter_param::CUTOFF);
    e.add_point(cut, 0.0, 300.0, 0.0);
    e.add_point(cut, 3.0, 8000.0, -0.3);
    let send = e.add_lane(1, auto_target::SEND, 0, 0);
    e.add_point(send, 1.0, 0.0, 0.0);
    e.add_point(send, 2.5, 1.0, 0.0);
    e.set_loop(true, 1.0, 3.0);
    e.set_metronome(true, 0.3);
}

/// Tempo real: blocos de tamanhos variados, seek no meio, bypass no meio, parada e cauda.
fn realtime_hash() -> u64 {
    let mut e = Engine::new(RATE);
    plain_scene(&mut e);
    e.play();
    let mut h = Hasher::new();
    let (mut l, mut r) = (vec![0.0f32; 4096], vec![0.0f32; 4096]);
    for k in 0..500 {
        let n = [128, 500, 1000, 64][k % 4];
        e.process(&mut l[..n], &mut r[..n]);
        h.feed(&l[..n], &r[..n]);
        match k {
            120 => e.seek(0.7),
            200 => e.set_fx_bypass(1, 1, true),
            260 => e.set_fx_bypass(1, 1, false),
            300 => e.set_loop(false, 0.0, 0.0),
            400 => e.stop(),
            _ => {}
        }
    }
    h.0
}

/// Render offline: a saída e uma captura de cada faixa, em blocos variados.
fn offline_hash() -> u64 {
    let mut e = Engine::new(RATE);
    plain_scene(&mut e);
    e.capture_clear();
    let idx: Vec<i32> = [-1, 0, 1, 2, 3, 4, 5].iter().map(|&t| e.capture_add(t)).collect();
    e.seek(0.5);
    e.play();
    let mut h = Hasher::new();
    let (mut l, mut r) = (vec![0.0f32; MAX_BLOCK], vec![0.0f32; MAX_BLOCK]);
    let (mut cl, mut cr) = (vec![0.0f32; MAX_BLOCK], vec![0.0f32; MAX_BLOCK]);
    let mut done = 0;
    let mut i = 0;
    while done < 72_000 {
        let n = [256, 1024, 128, 4096, 384][i % 5].min(72_000 - done);
        e.process(&mut l[..n], &mut r[..n]);
        h.feed(&l[..n], &r[..n]);
        for &k in &idx {
            e.captured(k as usize, &mut cl[..n], &mut cr[..n]);
            h.feed(&cl[..n], &cr[..n]);
        }
        done += n;
        i += 1;
    }
    h.0
}

/// Hashes gravados do motor ANTERIOR à PDC (`plain_scene`, sem nenhum efeito com latência).
const GOLDEN_REALTIME: u64 = 0xd9accd71dab901f0;
const GOLDEN_OFFLINE: u64 = 0x4a2f765ddc5d2a93;

#[test]
fn sem_efeito_com_latencia_a_saida_e_identica_a_de_antes() {
    assert_eq!(realtime_hash(), GOLDEN_REALTIME, "tempo real");
    assert_eq!(offline_hash(), GOLDEN_OFFLINE, "render offline");
    let mut e = Engine::new(RATE);
    plain_scene(&mut e);
    e.play();
    let (mut l, mut r) = (vec![0.0; 128], vec![0.0; 128]);
    e.process(&mut l, &mut r);
    assert_eq!(e.pdc_latency(), 0);
}

// ------------------------------------------------------------------------------------ ferramentas

/// Início do impulso, em quadros: batida 1 a 120 bpm.
const AT: usize = 24_000;

/// Motor sem o limitador de segurança, com `n` faixas em pan todo à esquerda (ganho 1 na esquerda)
/// e um impulso de 0,25 em cada uma no quadro [`AT`], em clipes curtos (a faixa fica calada logo
/// depois: o que sai atrasado precisa sair mesmo assim).
fn impulses(n: usize) -> Engine {
    let mut e = Engine::new(RATE);
    e.set_limiter(false);
    e.set_tempo(120.0, 4);
    e.set_track_count(n);
    let mut click = vec![0.0f32; 4800];
    click[0] = 0.25;
    e.load_sample(1, Sample::new(vec![click], RATE));
    for t in 0..n {
        e.track_mut(t).unwrap().pan = -1.0;
        e.add_clip(Clip { track: t, sample: 1, start: 1.0, offset: 0.0, length: 0.001, gain: 1.0, fade_in: 0.0, fade_out: 0.0 });
    }
    e
}

/// Põe o efeito nos padrões, já assentado (sem o fade de entrada).
fn fx(e: &mut Engine, track: i32, slot: usize, kind: u32) {
    e.set_fx(track, slot, kind);
    e.chain_mut(track).unwrap().snap();
}

fn play(e: &mut Engine, frames: usize, block: usize) -> Vec<f32> {
    e.play();
    let mut out = Vec::with_capacity(frames);
    let (mut l, mut r) = (vec![0.0; block], vec![0.0; block]);
    while out.len() < frames {
        e.process(&mut l, &mut r);
        out.extend_from_slice(&l);
    }
    out
}

/// Quadros com som (acima de `eps`).
fn onsets(v: &[f32], eps: f32) -> Vec<usize> {
    v.iter().enumerate().filter(|(_, s)| s.abs() > eps).map(|(i, _)| i).collect()
}

fn argmax(v: &[f32]) -> usize {
    v.iter().enumerate().fold((0, 0.0f32), |m, (i, s)| if s.abs() > m.1 { (i, s.abs()) } else { m }).0
}

type Channels = (Vec<f32>, Vec<f32>);

/// Render offline como o app faz: capturas das saídas, `seek`/`play`, blocos de `block` quadros.
fn offline(e: &mut Engine, outputs: &[i32], from: f64, frames: usize, block: usize) -> (Vec<Channels>, Channels) {
    e.capture_clear();
    let idx: Vec<i32> = outputs.iter().map(|&t| e.capture_add(t)).collect();
    e.seek(from);
    e.play();
    let mut caps = vec![(Vec::new(), Vec::new()); outputs.len()];
    let (mut out_l, mut out_r) = (Vec::new(), Vec::new());
    let (mut l, mut r) = (vec![0.0; block], vec![0.0; block]);
    let (mut cl, mut cr) = (vec![0.0; block], vec![0.0; block]);
    while out_l.len() < frames {
        e.process(&mut l, &mut r);
        out_l.extend_from_slice(&l);
        out_r.extend_from_slice(&r);
        for (c, &k) in caps.iter_mut().zip(&idx) {
            assert_eq!(e.captured(k as usize, &mut cl, &mut cr), block);
            c.0.extend_from_slice(&cl);
            c.1.extend_from_slice(&cr);
        }
    }
    (caps, (out_l, out_r))
}

// ------------------------------------------------------------------------------------ alinhamento

#[test]
fn limitador_da_faixa_alinha_com_a_faixa_sem_efeito() {
    let mut e = impulses(2);
    fx(&mut e, 0, 0, fx_kind::LIMITER);
    let out = play(&mut e, 30_000, 128);
    // a latência do limitador (3 ms = 144 quadros) vale para todas: os dois impulsos coincidem
    // no mesmo quadro, somados, e nada sai no quadro original
    assert_eq!(e.pdc_latency(), 144);
    assert_eq!(onsets(&out, 1e-6), vec![AT + 144]);
    assert!((out[AT + 144] - 0.5).abs() < 1e-6, "{}", out[AT + 144]);
}

#[test]
fn atraso_medido_e_zero_no_render_offline_faixas_master_e_stems() {
    let mut e = impulses(2);
    fx(&mut e, 0, 0, fx_kind::LIMITER);
    let (caps, (master, _)) = offline(&mut e, &[-1, 0, 1], 0.0, 30_720, 128);
    // o começo do render descarta a latência: o impulso sai no quadro dele, em todas as saídas
    assert_eq!(onsets(&master, 1e-6), vec![AT]);
    assert_eq!(onsets(&caps[0].0, 1e-6), vec![AT], "master capturado");
    assert_eq!(onsets(&caps[1].0, 1e-6), vec![AT], "stem da faixa com limitador");
    assert_eq!(onsets(&caps[2].0, 1e-6), vec![AT], "stem da faixa sem efeito");
    assert!((master[AT] - 0.5).abs() < 1e-6);
    assert_eq!(e.latency_frames(), 144);
}

#[test]
fn distorcao_alinha_com_a_faixa_sem_efeito() {
    use effect::distortion_param as dp;
    // dura sem drive abaixo do teto é linear: o impulso sai inteiro, no quadro dele (em 1×, 2× e 4×)
    for os in [0.0, 1.0, 2.0] {
        let mut e = impulses(2);
        fx(&mut e, 0, 0, fx_kind::DISTORTION);
        for (id, v) in [(dp::TYPE, 3.0), (dp::DRIVE, 0.0), (dp::TONE, 20_000.0), (dp::OVERSAMPLE, os)] {
            e.set_fx_param(0, 0, id, v);
        }
        let (caps, _) = offline(&mut e, &[0, 1], 0.0, 30_720, 128);
        assert_eq!(e.pdc_latency(), crate::fx::distortion::LATENCY);
        assert_eq!(argmax(&caps[1].0), AT);
        assert_eq!(argmax(&caps[0].0), AT, "distorção fora de alinhamento ({os})");
    }
    // nos padrões (curva suave e passa-baixa da distorção, que deformam o impulso) o pico erra, no
    // máximo, um quadro
    let mut e = impulses(2);
    fx(&mut e, 0, 0, fx_kind::DISTORTION);
    let (caps, _) = offline(&mut e, &[0, 1], 0.0, 30_720, 128);
    assert!(argmax(&caps[0].0).abs_diff(AT) <= 1);
}

#[test]
fn envio_para_barramento_com_efeito_de_latencia_chega_junto_com_a_saida_direta() {
    for pre in [false, true] {
        // faixa 0 → master direto e, por um envio, o barramento 1 (limitador): sem PDC a saída
        // direta soaria 144 quadros antes do retorno (filtro de pente); com ela, as duas coincidem
        let mut e = impulses(1);
        e.set_track_count(2);
        e.set_track_kind(1, kind::BUS);
        e.track_mut(1).unwrap().pan = -1.0;
        e.set_sends_count(0, 1);
        e.set_send(0, 0, 1, 0.5, pre);
        fx(&mut e, 1, 0, fx_kind::LIMITER);
        let out = play(&mut e, 30_000, 96);
        assert_eq!(onsets(&out, 1e-6), vec![AT + 144], "pre = {pre}");
        assert!((out[AT + 144] - 0.375).abs() < 1e-6, "pre = {pre}: {}", out[AT + 144]);
    }
}

#[test]
fn barramentos_em_cadeia_somam_as_latencias_e_alinham_todas_as_fontes() {
    // faixa 0 → barramento 2 (limitador 144) → barramento 3 (limitador de 1 ms, 48) → master;
    // a faixa 1 vai direto ao master; a 4 também entra no 2
    let mut e = impulses(2);
    e.set_track_count(5);
    for b in [2, 3] {
        e.set_track_kind(b, kind::BUS);
        e.track_mut(b).unwrap().pan = -1.0;
    }
    e.track_mut(4).unwrap().pan = -1.0;
    e.add_clip(Clip { track: 4, sample: 1, start: 1.0, offset: 0.0, length: 0.001, gain: 1.0, fade_in: 0.0, fade_out: 0.0 });
    e.set_output(0, 2);
    e.set_output(2, 3);
    e.set_output(4, 2);
    fx(&mut e, 2, 0, fx_kind::LIMITER);
    fx(&mut e, 3, 0, fx_kind::LIMITER);
    e.set_fx_param(3, 0, effect::limiter_param::LOOKAHEAD, 0.001);
    let out = play(&mut e, 30_000, 128);
    assert_eq!(e.pdc_latency(), 144 + 48);
    // três fontes (0, 1 e 4, todas em 0,25) num só quadro
    assert_eq!(onsets(&out, 1e-6), vec![AT + 192]);
    assert!((out[AT + 192] - 0.75).abs() < 1e-6, "{}", out[AT + 192]);
}

#[test]
fn chave_de_sidechain_e_sinal_chegam_alinhados() {
    use effect::compressor_param as cp;

    /// Anota em que quadro o efeito viu o primeiro som na entrada e na chave (e quantos viu).
    struct Probe(std::sync::Arc<std::sync::Mutex<[Option<usize>; 3]>>);
    impl Effect for Probe {
        fn set_param(&mut self, _: u32, _: f32) {}
        fn process(&mut self, l: &mut [f32], r: &mut [f32]) {
            self.process_keyed(l, r, None);
        }
        fn process_keyed(&mut self, l: &mut [f32], _: &mut [f32], key: Option<(&[f32], &[f32])>) {
            let mut s = self.0.lock().unwrap();
            let base = s[2].unwrap_or(0);
            for i in 0..l.len() {
                if s[0].is_none() && l[i].abs() > 1e-6 {
                    s[0] = Some(base + i);
                }
                if let Some((k, _)) = key
                    && s[1].is_none()
                    && k[i].abs() > 1e-6
                {
                    s[1] = Some(base + i);
                }
            }
            s[2] = Some(base + l.len());
        }
        fn reset(&mut self) {}
    }

    // sons longos (a faixa não pode calar: o contador de quadros do efeito só anda com ela rodando)
    let scene = |a_lat: Option<f32>, b_lat: Option<f32>| {
        let mut e = Engine::new(RATE);
        e.set_limiter(false);
        e.set_tempo(120.0, 4);
        e.set_track_count(2);
        let mut click = vec![0.0f32; 48_000];
        click[AT] = 0.5;
        e.load_sample(1, Sample::new(vec![click], RATE));
        for t in 0..2 {
            e.add_clip(Clip { track: t, sample: 1, start: 0.0, offset: 0.0, length: 1.0, gain: 1.0, fade_in: 0.0, fade_out: 0.0 });
        }
        for (t, lat) in [(0, a_lat), (1, b_lat)] {
            if let Some(look) = lat {
                fx(&mut e, t, 0, fx_kind::LIMITER);
                e.set_fx_param(t, 0, effect::limiter_param::LOOKAHEAD, look);
            }
        }
        let log = std::sync::Arc::new(std::sync::Mutex::new([None, None, None]));
        let slot = usize::from(b_lat.is_some());
        e.set_fx_count(1, slot + 1);
        e.chain_mut(1).unwrap().install(slot, fx_kind::COMPRESSOR, Box::new(Probe(log.clone())));
        e.chain_mut(1).unwrap().snap();
        e.set_fx_param(1, slot, cp::SIDECHAIN, 0.0);
        play(&mut e, 40_000, 128);
        let seen = *log.lock().unwrap();
        (seen[0], seen[1], e.pdc_latency())
    };
    // a chave (faixa 0) tem latência e o alvo não: a fonte do alvo espera
    let (input, key, total) = scene(Some(0.003), None);
    assert_eq!((input, key, total), (Some(AT + 144), Some(AT + 144), 144));
    // o alvo tem latência antes do slot da chave e a chave não: a chave é atrasada
    let (input, key, total) = scene(None, Some(0.003));
    assert_eq!((input, key, total), (Some(AT + 144), Some(AT + 144), 144));
    // as duas: 96 na chave, 144 no alvo antes do compressor; a chave espera a diferença
    let (input, key, total) = scene(Some(0.002), Some(0.003));
    assert_eq!((input, key, total), (Some(AT + 144), Some(AT + 144), 144));
    // a chave com mais latência que o alvo antes do slot: o alvo espera a diferença
    let (input, key, total) = scene(Some(0.003), Some(0.001));
    assert_eq!((input, key, total), (Some(AT + 144), Some(AT + 144), 144));
}

#[test]
fn cadeia_do_master_e_a_pdc_somam_e_o_render_descarta_tudo() {
    let mut e = impulses(2);
    fx(&mut e, 0, 0, fx_kind::LIMITER);
    fx(&mut e, -1, 0, fx_kind::LIMITER);
    // faixas alinhadas na entrada do master (144) e o limitador do master (144) depois dele
    let out = play(&mut e, 30_000, 128);
    assert_eq!(onsets(&out, 1e-6), vec![AT + 288]);
    assert_eq!((e.pdc_latency(), e.latency_frames()), (144, 288));
    let mut e = impulses(2);
    fx(&mut e, 0, 0, fx_kind::LIMITER);
    fx(&mut e, -1, 0, fx_kind::LIMITER);
    let (caps, (master, _)) = offline(&mut e, &[-1, 0, 1], 0.0, 30_720, 128);
    assert_eq!(onsets(&master, 1e-6), vec![AT]);
    assert_eq!(onsets(&caps[1].0, 1e-6), vec![AT]);
    assert_eq!(onsets(&caps[2].0, 1e-6), vec![AT]);
    // com o limitador de segurança do master ligado, a latência dele também sai do começo
    let mut e = impulses(2);
    e.set_limiter(true);
    fx(&mut e, 0, 0, fx_kind::LIMITER);
    let safety = e.latency;
    assert!(safety > 0);
    let (caps, (master, _)) = offline(&mut e, &[-1, 0, 1], 0.0, 30_720, 128);
    assert_eq!(e.latency_frames(), 144 + safety);
    assert_eq!(onsets(&master, 1e-6), vec![AT]);
    assert_eq!(onsets(&caps[2].0, 1e-6), vec![AT]);
}

/// Seno de `amp` e `freq` em um clipe de 2 s na faixa `track` (pan todo à esquerda).
fn sine_track(e: &mut Engine, track: usize, freq: f32, amp: f32) -> Vec<f32> {
    let src: Vec<f32> = (0..96_000).map(|i| amp * (std::f32::consts::TAU * freq * i as f32 / RATE as f32).sin()).collect();
    e.load_sample(10 + track as u32, Sample::new(vec![src.clone()], RATE));
    e.track_mut(track).unwrap().pan = -1.0;
    e.add_clip(Clip { track, sample: 10 + track as u32, start: 0.0, offset: 0.0, length: 2.0, gain: 1.0, fade_in: 0.0, fade_out: 0.0 });
    src
}

fn sine_engine() -> (Engine, Vec<f32>) {
    let mut e = Engine::new(RATE);
    e.set_limiter(false);
    e.set_tempo(120.0, 4);
    e.set_track_count(2);
    let a = sine_track(&mut e, 0, 440.0, 0.4);
    let b = sine_track(&mut e, 1, 660.0, 0.4);
    let sum = a.iter().zip(&b).map(|(x, y)| x + y).collect();
    (e, sum)
}

/// Maior degrau entre quadros vizinhos.
fn max_step(v: &[f32]) -> f32 {
    v.windows(2).map(|w| (w[1] - w[0]).abs()).fold(0.0, f32::max)
}

/// Maior diferença entre a saída e a soma das fontes atrasada de `delay` quadros, de `from` em diante.
fn max_err(out: &[f32], sum: &[f32], delay: usize, from: usize, to: usize) -> f32 {
    (from..to).map(|i| (out[i] - if i >= delay { sum[i - delay] } else { 0.0 }).abs()).fold(0.0, f32::max)
}

#[test]
fn bypass_ligando_e_desligando_nao_muda_o_alinhamento_nem_estala() {
    let (mut e, sum) = sine_engine();
    fx(&mut e, 0, 0, fx_kind::LIMITER);
    e.play();
    let (mut l, mut r) = (vec![0.0; 128], vec![0.0; 128]);
    let mut out = Vec::new();
    for k in 0..600 {
        // liga e desliga em ritmos que caem no meio dos crossfades (10 ms = 3,75 blocos)
        let bypass = (k % 11) < 5 || (k % 7) == 3;
        e.set_fx_bypass(0, 0, bypass);
        e.process(&mut l, &mut r);
        out.extend_from_slice(&l);
    }
    // a saída é sempre a soma das fontes atrasada de 144 quadros: o bypass troca um sinal por outro
    // idêntico (o limitador abaixo do teto é transparente), sem degrau e sem mudar o atraso
    assert_eq!(e.pdc_latency(), 144);
    let err = max_err(&out, &sum, 144, 0, out.len());
    assert!(err < 1e-5, "erro {err}");
    assert!(max_step(&out) < 0.1);
    // e o mesmo sem nunca ligar o efeito: a latência do bypass é a mesma
    let (mut e2, _) = sine_engine();
    fx(&mut e2, 0, 0, fx_kind::LIMITER);
    e2.set_fx_bypass(0, 0, true);
    let out2 = play(&mut e2, 76_800, 128);
    assert!(max_err(&out2, &sum, 144, 0, out2.len()) < 1e-5);
}

#[test]
fn trocar_o_tipo_do_efeito_recalcula_a_compensacao_sem_estalo() {
    let settle = 4000;
    for (from, to, before, after) in [
        (fx_kind::LIMITER, fx_kind::UTILITY, 144, 0),
        (fx_kind::UTILITY, fx_kind::LIMITER, 0, 144),
        (fx_kind::LIMITER, fx_kind::DISTORTION, 144, crate::fx::distortion::LATENCY),
        (fx_kind::LIMITER, 0, 144, 0),
        (0, fx_kind::LIMITER, 0, 144),
    ] {
        let (mut e, sum) = sine_engine();
        if from != 0 {
            fx(&mut e, 0, 0, from);
            if from == fx_kind::UTILITY {
                // sem pan nem largura: passa direto
                e.set_fx_param(0, 0, effect::utility_param::PAN, 0.0);
            }
        }
        e.play();
        let (mut l, mut r) = (vec![0.0; 128], vec![0.0; 128]);
        let mut out = Vec::new();
        let mut change_at = 0;
        for k in 0..700 {
            if k == 300 {
                change_at = out.len();
                e.set_fx(0, 0, to);
            }
            e.process(&mut l, &mut r);
            out.extend_from_slice(&l);
        }
        let name = format!("{from} → {to}");
        // antes: a latência de antes; depois de assentar: a de depois; no meio, sem degrau
        assert!(max_err(&out, &sum, before, 2000, change_at) < 1e-4, "{name}: antes");
        assert_eq!(e.pdc_latency(), after, "{name}");
        if to != fx_kind::DISTORTION {
            // (a distorção nos padrões deforma a onda: aqui só o atraso, que o teste do impulso mede)
            assert!(
                max_err(&out, &sum, after, change_at + settle, out.len()) < 1e-3,
                "{name}: depois {}",
                max_err(&out, &sum, after, change_at + settle, out.len())
            );
        }
        assert!(max_step(&out[change_at.saturating_sub(64)..]) < 0.12, "{name}: degrau {}", max_step(&out[change_at.saturating_sub(64)..]));
    }
}

#[test]
fn mudar_o_lookahead_tocando_realinha_as_duas_faixas() {
    let (mut e, sum) = sine_engine();
    fx(&mut e, 0, 0, fx_kind::LIMITER);
    e.play();
    let (mut l, mut r) = (vec![0.0; 128], vec![0.0; 128]);
    let mut out = Vec::new();
    for k in 0..700 {
        if k == 200 {
            e.set_fx_param(0, 0, effect::limiter_param::LOOKAHEAD, 0.005);
        }
        e.process(&mut l, &mut r);
        out.extend_from_slice(&l);
    }
    assert_eq!(e.pdc_latency(), 240);
    assert!(max_err(&out, &sum, 144, 2000, 25_000) < 1e-4);
    assert!(max_err(&out, &sum, 240, 40_000, out.len()) < 1e-4);
    assert!(max_step(&out) < 0.2, "{}", max_step(&out));
}

/// Cena com latências em todo lado: faixas com limitador e distorção, envio para um barramento com
/// limitador e delay, e o master com limitador.
fn latency_scene(e: &mut Engine) {
    e.set_tempo(120.0, 4);
    e.set_track_count(4);
    let noise: Vec<f32> = (0..96_000u32).map(|i| ((i.wrapping_mul(2_654_435_761) >> 8) as f32 / 16_777_216.0 - 0.5) * 0.6).collect();
    e.load_sample(1, Sample::new(vec![noise], RATE));
    for (t, f) in [(0, 300.0), (1, 500.0), (2, 700.0)] {
        sine_track(e, t, f, 0.3);
    }
    e.track_mut(0).unwrap().pan = 0.2;
    e.track_mut(2).unwrap().pan = -0.3;
    e.add_clip(Clip { track: 1, sample: 1, start: 0.5, offset: 0.0, length: 1.0, gain: 0.5, fade_in: 0.0, fade_out: 0.0 });
    e.set_track_kind(3, kind::BUS);
    e.set_sends_count(2, 1);
    e.set_send(2, 0, 3, 0.7, false);
    e.set_sends_count(0, 1);
    e.set_send(0, 0, 3, 0.4, true);
    fx(e, 0, 0, fx_kind::LIMITER);
    fx(e, 1, 0, fx_kind::EQ);
    fx(e, 1, 1, fx_kind::DISTORTION);
    // (sem reverb: o LFO da modulação dele anda no aquecimento do render e não no tempo real)
    fx(e, 3, 0, fx_kind::DELAY);
    fx(e, 3, 1, fx_kind::LIMITER);
    e.set_fx_param(3, 1, effect::limiter_param::LOOKAHEAD, 0.002);
    fx(e, -1, 0, fx_kind::COMPRESSOR);
    fx(e, -1, 1, fx_kind::LIMITER);
    e.set_fx_param(-1, 1, effect::limiter_param::LOOKAHEAD, 0.001);
    // os envios já no nível (tocando, um envio novo sobe do zero; o render começa com ele pronto)
    for strip in &mut e.strips {
        for send in &mut strip.sends {
            send.settle(true);
        }
    }
}

#[test]
fn render_offline_e_o_tempo_real_do_o_mesmo_alinhamento() {
    const N: usize = 60_000;
    let mut rt = Engine::new(RATE);
    latency_scene(&mut rt);
    let out = {
        rt.play();
        let mut out = Vec::new();
        let (mut l, mut r) = (vec![0.0; 128], vec![0.0; 128]);
        while out.len() < N + 1024 {
            rt.process(&mut l, &mut r);
            out.extend_from_slice(&l);
        }
        out
    };
    // faixa 0 (limitador 144) → envio pré → barramento 3 (limitador de 2 ms, 96) = 240 na entrada
    // do master, e o limitador do master (1 ms, 48) depois dele
    let total = rt.latency_frames();
    assert_eq!((rt.pdc_latency(), total), (240, 288 + 72));
    let mut off = Engine::new(RATE);
    latency_scene(&mut off);
    let (caps, (master, _)) = offline(&mut off, &[-1, 0, 1, 2, 3], 0.0, N, 128);
    assert_eq!(off.latency_frames(), total);
    // o render sai `total` quadros antes do tempo real, idêntico
    let err = (0..N).map(|i| (master[i] - out[i + total]).abs()).fold(0.0, f32::max);
    assert!(err < 1e-6, "erro {err}, latência {total}");
    assert!(master.iter().any(|v| v.abs() > 0.1));
    assert_eq!(caps[0].0, master);
    // os stems também começam alinhados à fonte: a faixa 2 (um seno desde o quadro 0) já soa nele
    assert!(caps[3].0[8].abs() > 0.0 && caps[3].0[0..4].iter().any(|v| v.abs() > 0.0));
}

#[test]
fn a_pdc_nao_aloca_no_caminho_de_audio() {
    let mut e = Engine::new(RATE);
    latency_scene(&mut e);
    e.play();
    let (mut l, mut r) = (vec![0.0f32; 128], vec![0.0f32; 128]);
    for _ in 0..600 {
        e.process(&mut l, &mut r);
    }
    let allocs = crate::testalloc::count(|| {
        for k in 0..1500 {
            match k {
                100 => e.set_fx_bypass(0, 0, true),
                200 => e.set_fx_bypass(0, 0, false),
                300 => e.set_send(2, 0, 3, 0.2, false),
                400 => e.set_fx_bypass(1, 1, true),
                500 => e.stop(),
                600 => e.seek(0.5),
                650 => e.play(),
                800 => e.set_fx_bypass(1, 1, false),
                900 => e.track_mut(0).unwrap().mute = true,
                1000 => e.track_mut(0).unwrap().mute = false,
                _ => {}
            }
            e.process(&mut l, &mut r);
        }
    });
    assert_eq!(allocs, 0, "o áudio alocou");
    // o render offline também roda sem alocar depois do preparo
    e.capture_clear();
    let idx = e.capture_add(-1);
    let t = e.capture_add(1);
    e.process(&mut l, &mut r);
    let allocs = crate::testalloc::count(|| {
        for _ in 0..600 {
            e.process(&mut l, &mut r);
            e.captured(idx as usize, &mut [0.0; 128], &mut [0.0; 128]);
            e.captured(t as usize, &mut [0.0; 128], &mut [0.0; 128]);
        }
    });
    assert_eq!(allocs, 0, "o render alocou");
}

#[test]
fn latencia_maxima_e_limitada_a_um_segundo() {
    // 16 limitadores de 10 ms numa cadeia: 16 · 480 quadros
    let mut e = impulses(1);
    for s in 0..16 {
        fx(&mut e, 0, s, fx_kind::LIMITER);
        e.set_fx_param(0, s, effect::limiter_param::LOOKAHEAD, 0.01);
    }
    let out = play(&mut e, 40_000, 128);
    assert_eq!(e.pdc_latency(), 16 * 480);
    assert_eq!(onsets(&out, 1e-6), vec![AT + 16 * 480]);
    // sete barramentos em série com 16 limitadores cada passariam de 1 s (53 760 quadros a 48 kHz):
    // a conta trava em 1 s (a taxa em quadros) e o motor segue sem estourar nada
    let mut e = impulses(1);
    e.set_track_count(8);
    for b in 1..8 {
        e.set_track_kind(b, kind::BUS);
        e.set_output(b - 1, b as i32);
        for s in 0..16 {
            fx(&mut e, b as i32, s, fx_kind::LIMITER);
            e.set_fx_param(b as i32, s, effect::limiter_param::LOOKAHEAD, 0.01);
        }
    }
    let out = play(&mut e, 128, 128);
    assert_eq!(e.pdc_latency(), RATE as usize);
    assert!(out.iter().all(|v| v.is_finite()));
}

#[test]
fn arredondamento_do_lookahead_em_quadros_inteiros() {
    // 3 ms a 44,1 kHz = 132,3 → 132 quadros; a PDC usa o que o efeito informa, sem outra rodada
    let mut e = Engine::new(44_100.0);
    e.set_limiter(false);
    e.set_track_count(1);
    e.set_fx(0, 0, fx_kind::LIMITER);
    e.set_fx_param(0, 0, effect::limiter_param::LOOKAHEAD, 0.0031);
    let (mut l, mut r) = (vec![0.0; 128], vec![0.0; 128]);
    e.process(&mut l, &mut r);
    assert_eq!(e.pdc_latency(), 137);
}

#[test]
fn edicoes_aleatorias_com_latencia_nunca_quebram_e_voltam_ao_alinhamento() {
    let (mut e, sum) = sine_engine();
    e.set_track_count(5);
    for t in 2..5 {
        e.set_track_kind(t, if t == 4 { kind::BUS } else { kind::SYNTH });
    }
    e.set_track_kind(3, kind::BUS);
    let mut seed = 12345u32;
    let mut rnd = move |n: u32| {
        seed = seed.wrapping_mul(1_664_525).wrapping_add(1_013_904_223);
        (seed >> 8) % n
    };
    e.play();
    let (mut l, mut r) = (vec![0.0; 128], vec![0.0; 128]);
    let kinds = [0, fx_kind::LIMITER, fx_kind::DISTORTION, fx_kind::EQ, fx_kind::DELAY, fx_kind::COMPRESSOR];
    for k in 0..2500 {
        if k % 7 == 0 {
            let track = rnd(6) as i32 - 1;
            let slot = rnd(3) as usize;
            match rnd(8) {
                0 | 1 => e.set_fx(track, slot, kinds[rnd(6) as usize]),
                2 => e.set_fx_bypass(track, slot, rnd(2) == 0),
                3 => e.set_fx_param(track, slot, effect::limiter_param::LOOKAHEAD, rnd(11) as f32 * 0.001),
                4 => e.set_output(rnd(5) as usize, rnd(6) as i32 - 1),
                5 => {
                    e.set_sends_count(rnd(5) as usize, 2);
                    e.set_send(rnd(5) as usize, rnd(2) as usize, rnd(5) as i32, 0.5, rnd(2) == 0);
                }
                6 => e.set_fx_param(track, slot, effect::compressor_param::SIDECHAIN, rnd(5) as f32 - 1.0),
                _ => e.set_fx_count(track, rnd(4) as usize),
            }
        }
        if k == 1200 {
            e.seek(0.25);
        }
        e.process(&mut l, &mut r);
        assert!(l.iter().chain(&r).all(|v| v.is_finite() && v.abs() < 20.0), "bloco {k}");
    }
    // volta a uma configuração conhecida: o alinhamento é o da conta, sem resíduo das edições
    for t in 0..5 {
        e.set_fx_count(t, 0);
        e.set_output(t as usize, -1);
        e.set_sends_count(t as usize, 0);
    }
    e.set_fx_count(-1, 0);
    e.stop();
    e.seek(0.0);
    for _ in 0..200 {
        e.process(&mut l, &mut r);
    }
    fx(&mut e, 0, 0, fx_kind::LIMITER);
    e.set_fx_param(0, 0, effect::limiter_param::LOOKAHEAD, 0.003);
    e.seek(0.0);
    e.play();
    let mut out = Vec::new();
    for _ in 0..600 {
        e.process(&mut l, &mut r);
        out.extend_from_slice(&l);
    }
    assert_eq!(e.pdc_latency(), 144);
    assert!(max_err(&out, &sum, 144, 4000, out.len()) < 1e-4, "{}", max_err(&out, &sum, 144, 4000, out.len()));
}

/// O clique do metrônomo soa junto das faixas: atrasa a latência total (PDC e cadeia do master).
#[test]
fn metronomo_alinha_com_as_faixas_com_latencia() {
    for (track_fx, master_fx, delay) in [(false, false, 0), (true, false, 144), (false, true, 144), (true, true, 288)] {
        let mut e = impulses(1);
        if track_fx {
            fx(&mut e, 0, 0, fx_kind::LIMITER);
        }
        if master_fx {
            fx(&mut e, -1, 0, fx_kind::LIMITER);
        }
        e.set_metronome(true, 1.0);
        e.play();
        let (mut l, mut r) = (vec![0.0; 128], vec![0.0; 128]);
        let (mut left, mut right) = (Vec::new(), Vec::new());
        while left.len() < AT + 2000 {
            e.process(&mut l, &mut r);
            left.extend_from_slice(&l);
            right.extend_from_slice(&r);
        }
        // a faixa está toda à esquerda (o impulso) e o clique vai aos dois lados: a direita é só o clique e
        // esquerda menos direita é só o impulso
        let only: Vec<f32> = left.iter().zip(&right).map(|(a, b)| a - b).collect();
        let imp = argmax(&only[AT - 100..]) + AT - 100;
        let click = right.iter().enumerate().skip(AT - 100).find(|(_, v)| v.abs() > 1e-6).unwrap().0;
        assert_eq!(imp, AT + delay, "impulso, latência {delay}");
        // o primeiro quadro do clique é a fase zero (silêncio): o som começa um quadro depois
        assert_eq!(click, AT + delay + 1, "clique, latência {delay}");
        // e nada de clique antes (o do tempo 0 cai no começo e passa pelo mesmo atraso)
        assert!(right[AT - 100..AT + delay].iter().all(|v| v.abs() < 1e-6));
    }
}

/// Trocar o tipo de um efeito que soava, entre efeitos bem audíveis (senoide constante), mantém o
/// crossfade de 10 ms mesmo com o recálculo da PDC entre um bloco e outro: um corte seco entre as
/// duas saídas apareceria como um degrau grande.
#[test]
fn trocar_entre_efeitos_audiveis_mantem_o_crossfade() {
    for (from, to) in
        [(fx_kind::DISTORTION, fx_kind::EQ), (fx_kind::EQ, fx_kind::DISTORTION), (fx_kind::DISTORTION, fx_kind::FILTER), (fx_kind::FILTER, fx_kind::DISTORTION)]
    {
        let (mut e, _) = sine_engine();
        fx(&mut e, 0, 0, from);
        e.set_fx_param(0, 0, effect::distortion_param::DRIVE, 6.0);
        e.set_fx_param(0, 0, effect::filter_param::CUTOFF, 300.0);
        e.play();
        let (mut l, mut r) = (vec![0.0; 128], vec![0.0; 128]);
        let mut out = Vec::new();
        let mut at = 0;
        for k in 0..500 {
            if k == 200 {
                at = out.len();
                e.set_fx(0, 0, to);
                e.set_fx_param(0, 0, effect::distortion_param::DRIVE, 6.0);
            }
            e.process(&mut l, &mut r);
            out.extend_from_slice(&l);
        }
        // o degrau máximo de antes da troca é o do próprio efeito; o crossfade não pode passar muito dele
        let base = max_step(&out[2000..at]);
        let step = max_step(&out[at.saturating_sub(64)..]);
        assert!(step < base * 1.5 + 0.01, "{from} → {to}: degrau {step} contra {base} de antes");
    }
}

/// A automação do lookahead do limitador muda a latência real: a PDC acompanha (no máximo a cada
/// 20 ms) e a saída volta a ficar alinhada.
#[test]
fn automacao_do_lookahead_refaz_a_compensacao_com_limite_de_frequencia() {
    let (mut e, sum) = sine_engine();
    fx(&mut e, 0, 0, fx_kind::LIMITER);
    // degrau de 3 ms para 10 ms na batida 1 (quadro 24000)
    let lane = e.add_lane(0, auto_target::EFFECT, 0, effect::limiter_param::LOOKAHEAD);
    for (beat, v) in [(0.0, 0.003), (1.0, 0.003), (1.001, 0.010), (4.0, 0.010)] {
        e.add_point(lane, beat, v, 0.0);
    }
    e.play();
    let (mut l, mut r) = (vec![0.0; 128], vec![0.0; 128]);
    let mut out = Vec::new();
    while out.len() < 90_000 {
        e.process(&mut l, &mut r);
        out.extend_from_slice(&l);
    }
    assert_eq!(e.pdc_latency(), 480, "a PDC ficou com a conta velha");
    assert!(max_err(&out, &sum, 144, 4000, 24_000) < 1e-4, "antes");
    assert!(max_err(&out, &sum, 480, 40_000, out.len()) < 1e-4, "depois");
    assert!(e.pdc_runs < 6, "recalculou {} vezes", e.pdc_runs);
    // rampa contínua: no máximo um recálculo a cada 20 ms (50 por segundo)
    let (mut e, _) = sine_engine();
    fx(&mut e, 0, 0, fx_kind::LIMITER);
    let lane = e.add_lane(0, auto_target::EFFECT, 0, effect::limiter_param::LOOKAHEAD);
    e.add_point(lane, 0.0, 0.0, 0.0);
    e.add_point(lane, 2.0, 0.010, 0.0);
    e.play();
    let before = e.pdc_runs;
    for _ in 0..(48_000 / 128) {
        e.process(&mut l, &mut r);
    }
    let runs = e.pdc_runs - before;
    assert!((30..=52).contains(&runs), "{runs} recálculos em 1 s");
}

/// Os atrasos da PDC crescem no comando (e com folga), não no bloco: depois de um comando de
/// lookahead maior, processar não aloca; e uma rampa de lookahead automatizada, com os anéis já
/// crescidos, também não.
#[test]
fn o_crescimento_dos_atrasos_da_pdc_acontece_no_comando() {
    let (mut e, _) = sine_engine();
    let (mut l, mut r) = (vec![0.0; 128], vec![0.0; 128]);
    fx(&mut e, 0, 0, fx_kind::LIMITER);
    e.play();
    for _ in 0..100 {
        e.process(&mut l, &mut r);
    }
    // o comando (pela mesma via do hospedeiro) recalcula e aloca; o bloco seguinte, não
    let args = [0.0, 0.0, f64::from(effect::limiter_param::LOOKAHEAD), 0.010];
    crate::api::apply(&mut e, "fx_param", &args).unwrap();
    let allocs = crate::testalloc::count(|| {
        for _ in 0..300 {
            e.process(&mut l, &mut r);
        }
    });
    assert_eq!(allocs, 0, "o bloco alocou depois do comando");
    assert_eq!(e.pdc_latency(), 480);
    // rampa automatizada (com os anéis já crescidos): sem alocar
    let lane = e.add_lane(0, auto_target::EFFECT, 0, effect::limiter_param::LOOKAHEAD);
    e.add_point(lane, 0.0, 0.0, 0.0);
    e.add_point(lane, 2.0, 0.010, 0.0);
    e.seek(0.0);
    let allocs = crate::testalloc::count(|| {
        for _ in 0..(2 * 48_000 / 128) {
            e.process(&mut l, &mut r);
        }
    });
    assert_eq!(allocs, 0, "a automação do lookahead alocou");
}

/// Um impulso na entrada, monitorado numa faixa com limitador (e o limitador de segurança ligado),
/// sai depois de exatamente `latency_frames()`: é o que o app soma à latência do aparelho para
/// pôr a gravação na posição certa.
#[test]
fn impulso_monitorado_sai_depois_da_latencia_exposta() {
    for (track_fx, master_fx) in [(false, false), (true, false), (true, true)] {
        let mut e = Engine::new(RATE);
        e.set_tempo(120.0, 4);
        e.set_track_count(2);
        e.track_mut(0).unwrap().pan = -1.0;
        e.set_monitor(0, true);
        if track_fx {
            fx(&mut e, 0, 0, fx_kind::LIMITER);
        }
        if master_fx {
            fx(&mut e, -1, 0, fx_kind::LIMITER);
        }
        e.play();
        let at = 5 * 128 + 37;
        let (mut l, mut r) = (vec![0.0; 128], vec![0.0; 128]);
        let mut out = Vec::new();
        for k in 0..12 {
            let mut input = vec![0.0f32; 128];
            if k == at / 128 {
                input[at % 128] = 0.25;
            }
            e.set_input(&input, None);
            e.process(&mut l, &mut r);
            out.extend_from_slice(&l);
        }
        let want = at + e.latency_frames();
        assert_eq!(argmax(&out), want, "faixa {track_fx}, master {master_fx}, latência {}", e.latency_frames());
    }
}
