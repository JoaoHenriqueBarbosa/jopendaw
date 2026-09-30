//! Testes da modulação: formas e taxas do LFO, sincronia com o andamento, seguidor de envelope,
//! escalas dos destinos, soma com a automação, segurança e igualdade entre blocos.

use std::sync::{Arc, Mutex};

use crate::effect::{Effect, auto_target as at};
use crate::instrument::{Instrument, kind as ikind, synth_param};
use crate::modulation::{DIVISIONS, Warp, division_beats, hash_unit, kind, scale, shape, wave};
use crate::{Clip, Engine, Sample};

const RATE: f64 = 48_000.0;
/// Um passo da modulação em quadros.
const STEP: usize = crate::AUTO_STEP;

/// Motor com uma faixa cujo clipe é uma constante de 0,5 (volume e envelope se leem por ela).
fn engine() -> Engine {
    let mut e = Engine::new(RATE);
    e.load_sample(1, Sample::new(vec![vec![0.5; 48_000 * 4], vec![0.5; 48_000 * 4]], RATE));
    e.set_track_count(2);
    e.add_clip(Clip { track: 0, sample: 1, start: 0.0, offset: 0.0, length: 4.0, gain: 1.0, fade_in: 0.0, fade_out: 0.0 });
    e
}

fn run(e: &mut Engine, frames: usize) -> Vec<f32> {
    let (mut l, mut r) = (vec![0.0f32; frames], vec![0.0f32; frames]);
    e.process(&mut l, &mut r);
    l
}

/// Valor de `mod_gain` da faixa 0 depois de cada passo, durante `steps` passos.
fn gains(e: &mut Engine, steps: usize) -> Vec<f32> {
    (0..steps)
        .map(|_| {
            run(e, STEP);
            e.tracks()[0].mod_gain.expect("sem modulação de volume")
        })
        .collect()
}

/// LFO no volume: curso linear 0..2 com base 1 (meio do curso); a quantidade 0,5 do curso (±1 no
/// valor) leva a saída de 0 a 2 com profundidade 1.
fn lfo(e: &mut Engine, shape: u32, hz: f32, bipolar: bool) {
    e.mod_source(0, 0, kind::LFO, hz, false, 1.0, 0.0, bipolar, shape, 10.0, 100.0, 0.0);
    e.mod_dest(0, 0, 0, at::VOLUME, 0, 0, 0.5, 0.0, 2.0, scale::LINEAR);
}

/// Instantes (em passos) em que a série cruza `level` subindo.
fn rising(v: &[f32], level: f32) -> Vec<usize> {
    (1..v.len()).filter(|&i| v[i - 1] < level && v[i] >= level).collect()
}

fn extremes(v: &[f32]) -> (f32, f32) {
    v.iter().fold((f32::MAX, f32::MIN), |(a, b), &x| (a.min(x), b.max(x)))
}

#[test]
fn divisoes_e_curso_das_escalas() {
    assert_eq!(division_beats(12), 1.0);
    assert_eq!(division_beats(13), 1.5);
    assert!((division_beats(14) - 2.0 / 3.0).abs() < 1e-12);
    assert_eq!(division_beats(0), 16.0);
    assert_eq!(division_beats(23), 0.125 * 2.0 / 3.0);
    assert_eq!(division_beats(999), division_beats(DIVISIONS - 1));
    let lin = Warp::sane(-1.0, 1.0, scale::LINEAR);
    assert_eq!((lin.to_norm(-1.0), lin.to_norm(0.0), lin.to_norm(1.0)), (0.0, 0.5, 1.0));
    let log = Warp::sane(20.0, 20_000.0, scale::LOG);
    assert!((log.to_norm(632.455_5) - 0.5).abs() < 1e-4);
    assert!((log.from_norm(0.5) - 632.455_5).abs() < 0.01);
    assert_eq!((log.from_norm(0.0), log.from_norm(1.0)), (20.0, 20_000.0));
    let fad = Warp::sane(0.0, 2.0, scale::FADER);
    // o mesmo ganho que o fader do app: g = 2·x³
    assert!((fad.from_norm(0.5) - 0.25).abs() < 1e-6 && (fad.to_norm(0.25) - 0.5).abs() < 1e-6);
    // curso inválido vira 0..1 linear; log com mínimo 0 vira linear
    assert_eq!(Warp::sane(f32::NAN, 5.0, scale::LINEAR), Warp { min: 0.0, max: 1.0, scale: scale::LINEAR });
    assert_eq!(Warp::sane(0.0, 10.0, scale::LOG).scale, scale::LINEAR);
}

#[test]
fn formas_de_onda_nos_pontos_notaveis() {
    let near = |a: f32, b: f32| assert!((a - b).abs() < 1e-6, "{a} != {b}");
    for (p, want) in [(0.0, 0.0), (0.25, 1.0), (0.5, 0.0), (0.75, -1.0)] {
        near(wave(shape::SINE, p, 0), want);
        near(wave(shape::TRIANGLE, p, 0), want);
    }
    near(wave(shape::SAW, 0.0, 0), -1.0);
    near(wave(shape::SAW, 0.5, 0), 0.0);
    near(wave(shape::SQUARE, 0.25, 0), 1.0);
    near(wave(shape::SQUARE, 0.75, 0), -1.0);
    // o que passa de um ciclo dá a volta
    near(wave(shape::SINE, 3.25, 0), 1.0);
    // sample&hold: constante no ciclo, muda entre ciclos, e sempre em −1..1
    assert_eq!(wave(shape::SAMPLE_HOLD, 2.1, 7), wave(shape::SAMPLE_HOLD, 2.9, 7));
    assert_ne!(wave(shape::SAMPLE_HOLD, 2.5, 7), wave(shape::SAMPLE_HOLD, 3.5, 7));
    assert_ne!(wave(shape::SAMPLE_HOLD, 2.5, 7), wave(shape::SAMPLE_HOLD, 2.5, 8));
    let xs: Vec<f32> = (0..2000).map(|i| hash_unit(i, 3)).collect();
    assert!(xs.iter().all(|v| (-1.0..1.0).contains(v)));
    let mean = xs.iter().sum::<f32>() / xs.len() as f32;
    assert!(mean.abs() < 0.1, "média {mean}");
}

#[test]
fn lfo_seno_tem_a_frequencia_e_a_amplitude_certas() {
    let mut e = engine();
    lfo(&mut e, shape::SINE, 5.0, true);
    e.play();
    let v = gains(&mut e, 750);
    // exato em cada passo: base 1 no meio do curso, amplitude ±1 → 1 + sin
    for (k, g) in v.iter().enumerate() {
        let want = 1.0 + (std::f64::consts::TAU * 5.0 * (k * STEP) as f64 / RATE).sin();
        assert!((f64::from(*g) - want).abs() < 2e-4, "passo {k}: {g} != {want}");
    }
    let (min, max) = extremes(&v);
    assert!(max > 1.999 && min < 0.001, "{min}..{max}");
    // 5 Hz: um ciclo a cada 0,2 s = 300 passos
    let up = rising(&v, 1.0);
    assert!(up.len() >= 2 && up.windows(2).all(|w| w[1] - w[0] == 300), "{up:?}");
}

#[test]
fn cada_forma_anda_na_taxa_pedida_e_respeita_a_profundidade() {
    for (name, sh) in [("seno", shape::SINE), ("triângulo", shape::TRIANGLE), ("serra", shape::SAW), ("quadrada", shape::SQUARE)] {
        let mut e = engine();
        // 4 Hz, profundidade 0,5: a série anda em 1 ± 0,5
        e.mod_source(0, 0, kind::LFO, 4.0, false, 0.5, 0.0, true, sh, 10.0, 100.0, 0.0);
        e.mod_dest(0, 0, 0, at::VOLUME, 0, 0, 0.5, 0.0, 2.0, scale::LINEAR);
        e.play();
        let v = gains(&mut e, 1500); // 1 s
        let up = rising(&v, 1.0);
        let cycles = up.len();
        assert!((3..=5).contains(&cycles), "{name}: {cycles} ciclos");
        // 4 ciclos em 1 s dão 375 passos cada (a serra e a quadrada têm degraus alisados)
        let period = (up[up.len() - 1] - up[0]) as f32 / (cycles - 1) as f32;
        assert!((period - 375.0).abs() <= 2.0, "{name}: período {period}");
        let (min, max) = extremes(&v);
        assert!(max <= 1.5 + 1e-4 && min >= 0.5 - 1e-4, "{name}: {min}..{max}");
        assert!(max > 1.45 && min < 0.55, "{name}: não chegou aos extremos {min}..{max}");
    }
}

#[test]
fn unipolar_vai_de_zero_a_profundidade() {
    let mut e = engine();
    e.track_mut(0).unwrap().gain = 0.0;
    e.mod_source(0, 0, kind::LFO, 2.0, false, 1.0, 0.0, false, shape::TRIANGLE, 10.0, 100.0, 0.0);
    e.mod_dest(0, 0, 0, at::VOLUME, 0, 0, 1.0, 0.0, 2.0, scale::LINEAR);
    e.play();
    let (min, max) = extremes(&gains(&mut e, 1500));
    // base 0 e quantidade 1 sobre o curso 0..2: a saída unipolar 0..1 leva o volume a 0..2
    assert!((0.0..0.01).contains(&min) && max > 1.98 && max <= 2.0, "{min}..{max}");
}

#[test]
fn sample_and_hold_segura_o_valor_por_ciclo() {
    let mut e = engine();
    lfo(&mut e, shape::SAMPLE_HOLD, 4.0, true);
    e.play();
    let v = gains(&mut e, 3000); // 2 s = 8 ciclos
    let mut plateaus = 1;
    let mut moving = false;
    let mut settled = Vec::new();
    for (i, w) in v.windows(2).enumerate() {
        // conta cada começo de transição (o alisamento leva alguns passos)
        let step = (w[1] - w[0]).abs() > 0.02;
        if step && !moving {
            plateaus += 1;
        }
        moving = step;
        // 200 passos depois do início de um ciclo o valor já assentou
        if i % 375 == 200 {
            settled.push(w[1]);
        }
    }
    assert!((7..=9).contains(&plateaus), "{plateaus} patamares");
    assert!(v.iter().all(|g| (0.0..=2.0).contains(g)));
    settled.dedup_by(|a, b| (*a - *b).abs() < 1e-6);
    assert!(settled.len() >= 6, "os ciclos sorteiam valores diferentes: {settled:?}");
}

#[test]
fn sincronizado_a_120_bpm_um_quarto_dá_2_hz() {
    let mut e = engine();
    e.set_tempo(120.0, 4);
    // divisão 12 = 1/4 reto
    e.mod_source(0, 0, kind::LFO, 12.0, true, 1.0, 0.0, true, shape::SINE, 10.0, 100.0, 0.0);
    e.mod_dest(0, 0, 0, at::VOLUME, 0, 0, 0.5, 0.0, 2.0, scale::LINEAR);
    e.play();
    let up = rising(&gains(&mut e, 3000), 1.0);
    assert!(up.len() >= 3 && up.windows(2).all(|w| w[1] - w[0] == 750), "{up:?}");
    // 1/4 pontilhada (12 + 1): 1,5 batida = 0,75 s = 1125 passos
    let mut e = engine();
    e.set_tempo(120.0, 4);
    e.mod_source(0, 0, kind::LFO, 13.0, true, 1.0, 0.0, true, shape::SINE, 10.0, 100.0, 0.0);
    e.mod_dest(0, 0, 0, at::VOLUME, 0, 0, 0.5, 0.0, 2.0, scale::LINEAR);
    e.play();
    let up = rising(&gains(&mut e, 3000), 1.0);
    assert!(up.len() >= 2 && up.windows(2).all(|w| w[1] - w[0] == 1125), "{up:?}");
    // 1/4 de tercina (12 + 2): 2/3 de batida = 1/3 s = 500 passos
    let mut e = engine();
    e.set_tempo(120.0, 4);
    e.mod_source(0, 0, kind::LFO, 14.0, true, 1.0, 0.0, true, shape::SINE, 10.0, 100.0, 0.0);
    e.mod_dest(0, 0, 0, at::VOLUME, 0, 0, 0.5, 0.0, 2.0, scale::LINEAR);
    e.play();
    let up = rising(&gains(&mut e, 3000), 1.0);
    assert!(up.len() >= 4 && up.windows(2).all(|w| (w[1] - w[0]).abs_diff(500) <= 1), "{up:?}");
}

#[test]
fn o_mapa_de_andamento_com_rampa_muda_a_taxa() {
    let mut e = engine();
    e.tempo_point(0.0, 60.0, true);
    e.tempo_point(8.0, 240.0, false);
    e.mod_source(0, 0, kind::LFO, 12.0, true, 1.0, 0.0, true, shape::SINE, 10.0, 100.0, 0.0);
    e.mod_dest(0, 0, 0, at::VOLUME, 0, 0, 0.5, 0.0, 2.0, scale::LINEAR);
    e.play();
    // a rampa de 60 a 240 bpm leva 3,7 s (8 batidas); um ciclo por batida
    let v = gains(&mut e, 5600);
    let up = rising(&v, 1.0);
    assert!(up.len() >= 6, "{up:?}");
    let secs = |a: usize, b: usize| (b - a) as f32 * STEP as f32 / RATE as f32;
    let first = secs(up[0], up[1]);
    let last = secs(up[up.len() - 2], up[up.len() - 1]);
    // no começo a batida dura ~0,8 s; no fim, ~0,3 s
    assert!(first > 0.6 && first < 1.05, "primeiro {first}");
    assert!(last < 0.4 && last > 0.2, "último {last}");
    // a fase é função da posição: voltar (seek) dá o mesmo valor
    e.seek(3.0);
    run(&mut e, STEP);
    let a = e.tracks()[0].mod_gain.unwrap();
    e.seek(3.0);
    run(&mut e, STEP);
    assert_eq!(a, e.tracks()[0].mod_gain.unwrap());
}

/// Motor com um clipe constante de 0,5 que dura 0,5 s na faixa 0, de volume base zero, e um
/// seguidor (ataque, soltura, ganho) que vai direto ao volume (curso 0..1).
fn follower(attack: f32, release: f32, gain: f32) -> Engine {
    let mut e = Engine::new(RATE);
    e.load_sample(1, Sample::new(vec![vec![0.5; 24_000], vec![0.5; 24_000]], RATE));
    e.set_track_count(1);
    e.add_clip(Clip { track: 0, sample: 1, start: 0.0, offset: 0.0, length: 0.5, gain: 1.0, fade_in: 0.0, fade_out: 0.0 });
    e.track_mut(0).unwrap().gain = 0.0;
    e.mod_source(0, 0, kind::FOLLOWER, 0.0, false, gain, 0.0, false, 0, attack, release, 0.0);
    e.mod_dest(0, 0, 0, at::VOLUME, 0, 0, 1.0, 0.0, 1.0, scale::LINEAR);
    e.play();
    e
}

#[test]
fn seguidor_de_envelope_sobe_com_o_ataque_e_desce_com_a_soltura() {
    let mut e = follower(50.0, 200.0, 1.0);
    let v = gains(&mut e, 2000);
    let at_ms = |ms: f32| v[(ms / 1000.0 * RATE as f32 / STEP as f32) as usize];
    assert!(v[0] < 0.05, "começa quieto: {}", v[0]);
    // uma constante de tempo depois: 63% de 0,5
    assert!((at_ms(50.0) - 0.5 * (1.0 - (-1.0f32).exp())).abs() < 0.03, "{}", at_ms(50.0));
    assert!((at_ms(400.0) - 0.5).abs() < 0.01, "{}", at_ms(400.0));
    // o clipe acaba em 500 ms: 200 ms depois o nível caiu a 37%, e some com o tempo
    let top = at_ms(495.0);
    assert!((at_ms(700.0) - top * (-1.0f32).exp()).abs() < 0.03, "{} de {top}", at_ms(700.0));
    assert!(at_ms(1200.0) < 0.03, "{}", at_ms(1200.0));
    // a série sobe e depois desce sem oscilar
    let end = (RATE as usize / 2) / STEP;
    assert!(v[..end].windows(2).all(|w| w[1] >= w[0] - 1e-6));
    assert!(v[end + 5..].windows(2).all(|w| w[1] <= w[0] + 1e-6));
    // ganho 2 dobra o envelope (e satura em 1)
    let mut e2 = follower(5.0, 200.0, 2.0);
    let v2 = gains(&mut e2, 600);
    assert!((v2[500] - 1.0).abs() < 0.01, "{}", v2[500]);
    // ataque mais curto sobe mais depressa
    let mut e3 = follower(5.0, 200.0, 1.0);
    let v3 = gains(&mut e3, 100);
    assert!(v3[30] > v[30] + 0.1);
}

#[test]
fn macro_e_quantidade_bipolar() {
    let mut e = engine();
    e.mod_source(0, 0, kind::MACRO, 0.0, false, 1.0, 0.0, false, 0, 0.0, 0.0, 0.5);
    e.mod_dest(0, 0, 0, at::VOLUME, 0, 0, -0.5, 0.0, 2.0, scale::LINEAR);
    run(&mut e, STEP);
    // base 1 (norma 0,5) + (−0,5 · 0,5) = 0,25 do curso = 0,5
    assert!((e.tracks()[0].mod_gain.unwrap() - 0.5).abs() < 1e-6);
    // a macro bipolar em 0,5 vale 0: sem deslocamento (a base)
    e.mod_clear();
    e.mod_source(0, 0, kind::MACRO, 0.0, false, 1.0, 0.0, true, 0, 0.0, 0.0, 0.5);
    e.mod_dest(0, 0, 0, at::VOLUME, 0, 0, -0.5, 0.0, 2.0, scale::LINEAR);
    run(&mut e, STEP);
    assert_eq!(e.tracks()[0].mod_gain, Some(1.0));
    // dois destinos no mesmo alvo somam no curso do controle
    e.mod_clear();
    e.mod_source(0, 0, kind::MACRO, 0.0, false, 1.0, 0.0, false, 0, 0.0, 0.0, 1.0);
    e.mod_source(0, 1, kind::MACRO, 0.0, false, 1.0, 0.0, false, 0, 0.0, 0.0, 1.0);
    e.mod_dest(0, 0, 0, at::VOLUME, 0, 0, 0.25, 0.0, 2.0, scale::LINEAR);
    e.mod_dest(0, 1, 0, at::VOLUME, 0, 0, 0.125, 0.0, 2.0, scale::LINEAR);
    run(&mut e, STEP);
    assert!((e.tracks()[0].mod_gain.unwrap() - 1.75).abs() < 1e-6, "{:?}", e.tracks()[0].mod_gain);
    // mudar o valor da macro reenviando o modulador (o estado continua)
    e.mod_clear();
    e.mod_source(0, 0, kind::MACRO, 0.0, false, 1.0, 0.0, false, 0, 0.0, 0.0, 0.0);
    e.mod_source(0, 1, kind::MACRO, 0.0, false, 1.0, 0.0, false, 0, 0.0, 0.0, 0.0);
    e.mod_dest(0, 0, 0, at::VOLUME, 0, 0, 0.25, 0.0, 2.0, scale::LINEAR);
    e.mod_dest(0, 1, 0, at::VOLUME, 0, 0, 0.125, 0.0, 2.0, scale::LINEAR);
    run(&mut e, STEP);
    assert_eq!(e.tracks()[0].mod_gain, Some(1.0));
}

#[test]
fn a_fase_inicial_e_o_reinicio_no_play() {
    let mut e = engine();
    // quadrada com fase 0,5: começa embaixo
    e.mod_source(0, 0, kind::LFO, 1.0, false, 1.0, 0.5, true, shape::SQUARE, 10.0, 100.0, 0.0);
    e.mod_dest(0, 0, 0, at::VOLUME, 0, 0, 1.0, 0.0, 2.0, scale::LINEAR);
    e.play();
    let v = gains(&mut e, 5);
    assert!(v[4] < 0.05, "{v:?}");
    // parado o relógio anda (em 0,5 s ela viraria para cima); o play recomeça a fase
    e.stop();
    for _ in 0..25 {
        run(&mut e, 960);
    }
    e.play();
    let v = gains(&mut e, 5);
    assert!(v[4] < 0.05, "{v:?}");
    let mut e = engine();
    e.mod_source(0, 0, kind::LFO, 1.0, false, 1.0, 0.25, true, shape::SINE, 10.0, 100.0, 0.0);
    e.mod_dest(0, 0, 0, at::VOLUME, 0, 0, 1.0, 0.0, 2.0, scale::LINEAR);
    e.play();
    assert!((gains(&mut e, 1)[0] - 2.0).abs() < 1e-4);
}

type Log = Arc<Mutex<Vec<(u32, f32)>>>;

/// Instrumento que só registra os parâmetros.
struct Probe(Log);
impl Instrument for Probe {
    fn note_on(&mut self, _: u8, _: f32) {}
    fn note_off(&mut self, _: u8) {}
    fn release_all(&mut self) {}
    fn silence(&mut self) {}
    fn set_param(&mut self, id: u32, value: f32) {
        self.0.lock().unwrap().push((id, value));
    }
    fn render(&mut self, _: &mut [f32], _: &mut [f32]) {}
    fn active(&self) -> bool {
        false
    }
}

/// Efeito que só registra os parâmetros.
struct FxProbe(Log);
impl Effect for FxProbe {
    fn set_param(&mut self, id: u32, value: f32) {
        self.0.lock().unwrap().push((id, value));
    }
    fn process(&mut self, _: &mut [f32], _: &mut [f32]) {}
    fn reset(&mut self) {}
}

fn with_probe(e: &mut Engine) -> Log {
    let log = Log::default();
    e.lanes[1].instrument = Some(Box::new(Probe(log.clone())));
    log
}

fn last(log: &Log) -> (u32, f32) {
    *log.lock().unwrap().last().unwrap()
}

#[test]
fn destino_logaritmico_e_linear_ficam_na_faixa_do_parametro() {
    let mut e = engine();
    let log = with_probe(&mut e);
    e.set_param(1, 13, 1000.0);
    // corte 20..20000 Hz, escala log; macro cheia, +30% do curso
    e.mod_source(1, 0, kind::MACRO, 0.0, false, 1.0, 0.0, false, 0, 0.0, 0.0, 1.0);
    e.mod_dest(1, 0, 0, at::INSTRUMENT, 0, 13, 0.3, 20.0, 20_000.0, scale::LOG);
    run(&mut e, STEP);
    let w = Warp::sane(20.0, 20_000.0, scale::LOG);
    let want = w.from_norm(w.to_norm(1000.0) + 0.3);
    assert_eq!(last(&log).0, 13);
    assert!((last(&log).1 / want - 1.0).abs() < 1e-4, "{} != {want}", last(&log).1);
    // na escala log +30% do curso multiplica o valor (não soma Hz): 1000 → ~7900
    assert!(last(&log).1 > 7000.0 && last(&log).1 < 9000.0, "{}", last(&log).1);
    // +100%: trava no máximo; −100%: no mínimo
    e.mod_dest(1, 0, 0, at::INSTRUMENT, 0, 13, 1.0, 20.0, 20_000.0, scale::LOG);
    run(&mut e, STEP);
    assert!((last(&log).1 - 20_000.0).abs() < 1.0);
    e.mod_dest(1, 0, 0, at::INSTRUMENT, 0, 13, -1.0, 20.0, 20_000.0, scale::LOG);
    run(&mut e, STEP);
    assert!((last(&log).1 - 20.0).abs() < 1e-3);
    // linear, curso 0..10, base 2, +30%: 2 + 3
    e.set_param(1, 5, 2.0);
    e.mod_dest(1, 0, 1, at::INSTRUMENT, 0, 5, 0.3, 0.0, 10.0, scale::LINEAR);
    run(&mut e, STEP);
    assert!((last(&log).1 - 5.0).abs() < 1e-4, "{:?}", last(&log));
    // o valor base nunca vira o valor do controle: o estático segue guardado
    assert_eq!(e.lanes[1].statics[5], 2.0);
    // mudar o valor base (o app mexeu no knob) reflete no efetivo, sem o valor cru chegar ao instrumento
    let n = log.lock().unwrap().len();
    e.set_param(1, 5, 4.0);
    assert_eq!(log.lock().unwrap().len(), n, "o valor cru não chega ao instrumento enquanto modulado");
    run(&mut e, STEP);
    assert!((last(&log).1 - 7.0).abs() < 1e-4);
    // sem mudança, o instrumento não é mexido de novo
    let n = log.lock().unwrap().len();
    run(&mut e, STEP * 10);
    assert_eq!(log.lock().unwrap().len(), n);
}

#[test]
fn destino_de_fader_usa_a_curva_do_fader() {
    let mut e = engine();
    e.track_mut(0).unwrap().gain = 0.25; // fader em 0,5
    e.mod_source(0, 0, kind::MACRO, 0.0, false, 1.0, 0.0, false, 0, 0.0, 0.0, 1.0);
    e.mod_dest(0, 0, 0, at::VOLUME, 0, 0, 0.5, 0.0, 2.0, scale::FADER);
    run(&mut e, STEP);
    // fader 0,5 + 0,5 = 1 → ganho máximo 2
    assert!((e.tracks()[0].mod_gain.unwrap() - 2.0).abs() < 1e-5);
    e.mod_dest(0, 0, 0, at::VOLUME, 0, 0, -0.25, 0.0, 2.0, scale::FADER);
    run(&mut e, STEP);
    // fader 0,25 → 2·0,25³
    assert!((e.tracks()[0].mod_gain.unwrap() - 2.0 * 0.25f32.powi(3)).abs() < 1e-5);
}

#[test]
fn soma_por_cima_da_automacao_sem_estourar_a_faixa() {
    let mut e = engine();
    let lane = e.add_lane(0, at::VOLUME, 0, 0);
    e.add_point(lane, 0.0, 1.5, 0.0);
    e.mod_source(0, 0, kind::MACRO, 0.0, false, 1.0, 0.0, false, 0, 0.0, 0.0, 1.0);
    e.mod_dest(0, 0, 0, at::VOLUME, 0, 0, 0.5, 0.0, 2.0, scale::LINEAR);
    e.play();
    run(&mut e, STEP * 4);
    // automação 1,5 (norma 0,75) + 0,5 passa do curso: trava em 2
    assert_eq!(e.tracks()[0].mod_gain, Some(2.0));
    // a automação segue no campo dela, intocada
    assert_eq!(e.tracks()[0].auto_gain, Some(1.5));
    e.mod_dest(0, 0, 0, at::VOLUME, 0, 0, -0.5, 0.0, 2.0, scale::LINEAR);
    run(&mut e, STEP * 4);
    assert!((e.tracks()[0].mod_gain.unwrap() - 0.5).abs() < 1e-6);
    // parado, a base volta a ser o estático (1,0): norma 0,5 − 0,5 = 0
    e.stop();
    run(&mut e, STEP * 4);
    assert_eq!(e.tracks()[0].auto_gain, None);
    assert!(e.tracks()[0].mod_gain.unwrap().abs() < 1e-6);
    // sem o destino, tudo volta ao valor base
    e.mod_clear();
    run(&mut e, STEP);
    assert_eq!(e.tracks()[0].mod_gain, None);
}

#[test]
fn automacao_e_modulacao_de_instrumento_convivem() {
    let mut e = engine();
    let log = with_probe(&mut e);
    e.set_param(1, 5, 2.0);
    let lane = e.add_lane(1, at::INSTRUMENT, 0, 5);
    e.add_point(lane, 0.0, 6.0, 0.0);
    e.mod_source(1, 0, kind::MACRO, 0.0, false, 1.0, 0.0, false, 0, 0.0, 0.0, 1.0);
    e.mod_dest(1, 0, 0, at::INSTRUMENT, 0, 5, 0.1, 0.0, 10.0, scale::LINEAR);
    e.play();
    run(&mut e, STEP * 4);
    assert!((last(&log).1 - 7.0).abs() < 1e-4, "{:?}", log.lock().unwrap());
    // parou: o estático 2 + 1 de modulação
    e.stop();
    run(&mut e, STEP * 4);
    assert!((last(&log).1 - 3.0).abs() < 1e-4, "{:?}", last(&log));
    // tirar o destino devolve o estático
    e.mod_clear();
    run(&mut e, STEP * 2);
    assert_eq!(last(&log), (5, 2.0));
}

#[test]
fn efeito_troca_de_tipo_e_destino_removido_sao_seguros() {
    let mut e = engine();
    e.set_fx_count(0, 1);
    let log = Log::default();
    e.chain_mut(0).unwrap().install(0, crate::effect::kind::UTILITY, Box::new(FxProbe(log.clone())));
    e.set_fx_param(0, 0, 3, 100.0);
    e.mod_source(0, 0, kind::LFO, 10.0, false, 1.0, 0.0, true, shape::SINE, 0.0, 0.0, 0.0);
    e.mod_dest(0, 0, 0, at::EFFECT, 0, 3, 0.5, 0.0, 200.0, scale::LINEAR);
    e.play();
    run(&mut e, 4800);
    let seen: Vec<f32> = log.lock().unwrap().iter().filter(|(id, _)| *id == 3).map(|p| p.1).collect();
    assert!(seen.len() > 50 && seen.iter().all(|v| (0.0..=200.0).contains(v)), "{}", seen.len());
    assert!(seen.iter().any(|&v| v > 140.0) && seen.iter().any(|&v| v < 60.0));
    // troca o tipo do efeito: o estático some e a modulação espera o app reenviar os parâmetros
    e.set_fx(0, 0, crate::effect::kind::DISTORTION);
    run(&mut e, 4800);
    e.set_fx_param(0, 0, 0, 0.0);
    run(&mut e, 4800);
    // esvazia o slot, corta a contagem, troca o tipo da faixa e faz pânico: nada quebra
    e.set_fx(0, 0, 0);
    e.set_fx_count(0, 0);
    e.set_track_kind(1, ikind::SYNTH);
    e.panic();
    run(&mut e, 4800);
    // destinos que não existem: inócuos
    e.mod_dest(0, 0, 1, at::SEND, 9, 0, 1.0, 0.0, 2.0, scale::FADER);
    e.mod_dest(0, 0, 2, at::INSTRUMENT, 0, 5, 1.0, 0.0, 2.0, scale::LINEAR);
    e.mod_dest(0, 0, 3, at::EFFECT, 4, 5, 1.0, 0.0, 2.0, scale::LINEAR);
    e.mod_dest(7, 0, 0, at::VOLUME, 0, 0, 1.0, 0.0, 2.0, scale::LINEAR);
    e.mod_source(9, 0, kind::LFO, 1.0, false, 1.0, 0.0, true, 0, 0.0, 0.0, 0.0);
    e.mod_source(0, 9, kind::LFO, 1.0, false, 1.0, 0.0, true, 0, 0.0, 0.0, 0.0);
    e.mod_dest(0, 0, 9, at::VOLUME, 0, 0, 1.0, 0.0, 2.0, scale::LINEAR);
    run(&mut e, 4800);
    // dado ruim vira padrão: nada de NaN no volume
    e.mod_source(0, 0, kind::LFO, f32::NAN, false, f32::NAN, f32::INFINITY, true, 99, f32::NAN, -5.0, f32::NAN);
    e.mod_dest(0, 0, 0, at::VOLUME, 0, 0, f32::NAN, f32::NAN, f32::NAN, 77);
    for _ in 0..50 {
        run(&mut e, STEP);
        assert!(e.tracks()[0].mod_gain.is_none_or(f32::is_finite));
    }
    // encolher as faixas com modulação viva não quebra
    e.mod_dest(1, 0, 0, at::VOLUME, 0, 0, 1.0, 0.0, 2.0, scale::LINEAR);
    e.set_track_count(1);
    run(&mut e, 4800);
    // remover tudo devolve o volume
    e.mod_clear();
    run(&mut e, STEP);
    assert_eq!(e.tracks()[0].mod_gain, None);
    assert!(!e.mod_busy);
}

#[test]
fn modulacao_de_master_e_de_envio() {
    let mut e = engine();
    e.mod_source(-1, 0, kind::MACRO, 0.0, false, 1.0, 0.0, false, 0, 0.0, 0.0, 1.0);
    e.mod_dest(-1, 0, 0, at::PAN, 0, 0, 0.25, -1.0, 1.0, scale::LINEAR);
    // o master não tem instrumento nem envios: inócuos
    e.mod_dest(-1, 0, 1, at::INSTRUMENT, 0, 5, 1.0, 0.0, 1.0, scale::LINEAR);
    e.mod_dest(-1, 0, 2, at::SEND, 0, 0, 1.0, 0.0, 1.0, scale::FADER);
    run(&mut e, STEP);
    // pan 0 (norma 0,5) + 0,25 do curso −1..1 = 0,5
    assert!((e.master().effective().1 - 0.5).abs() < 1e-6);
    // envio da faixa 0 para o barramento 1
    e.set_track_kind(1, ikind::BUS);
    e.set_sends_count(0, 1);
    e.set_send(0, 0, 1, 0.5, false);
    e.mod_source(0, 0, kind::MACRO, 0.0, false, 1.0, 0.0, false, 0, 0.0, 0.0, 1.0);
    e.mod_dest(0, 0, 0, at::SEND, 0, 0, 0.25, 0.0, 2.0, scale::FADER);
    run(&mut e, STEP);
    // ganho 0,5 = fader (0,25)^(1/3); mais 0,25 do curso do fader
    let x = 0.25f32.cbrt() + 0.25;
    assert!((e.strips[0].sends[0].mod_level.unwrap() - 2.0 * x.powi(3)).abs() < 1e-4);
    e.mod_clear();
    run(&mut e, STEP);
    assert_eq!(e.strips[0].sends[0].mod_level, None);
    assert_eq!(e.master().mod_pan, None);
}

/// Três moduladores de tipos diferentes em destinos de volume, instrumento e efeito.
fn cheio(e: &mut Engine) {
    e.set_track_kind(1, ikind::SYNTH);
    e.add_note(1, 0.0, 4.0, 60, 0.8);
    e.set_fx_count(1, 1);
    e.set_fx(1, 0, crate::effect::kind::FILTER);
    e.set_fx_param(1, 0, 0, 1000.0);
    e.set_param(1, synth_param::CUTOFF, 1500.0);
    e.set_tempo(133.0, 4);
    mods(e);
}

fn mods(e: &mut Engine) {
    e.mod_source(0, 0, kind::LFO, 3.3, false, 0.8, 0.1, true, shape::SINE, 0.0, 0.0, 0.0);
    e.mod_dest(0, 0, 0, at::VOLUME, 0, 0, 0.6, 0.0, 2.0, scale::FADER);
    e.mod_source(1, 0, kind::LFO, 9.0, true, 1.0, 0.0, true, shape::TRIANGLE, 0.0, 0.0, 0.0);
    e.mod_dest(1, 0, 0, at::INSTRUMENT, 0, synth_param::CUTOFF, 0.5, 20.0, 20_000.0, scale::LOG);
    e.mod_source(1, 1, kind::FOLLOWER, 0.0, false, 3.0, 0.0, false, 0, 5.0, 80.0, 0.0);
    e.mod_dest(1, 1, 0, at::EFFECT, 0, 0, 0.4, 20.0, 20_000.0, scale::LOG);
    e.mod_source(1, 2, kind::LFO, 6.0, false, 1.0, 0.0, true, shape::SAMPLE_HOLD, 0.0, 0.0, 0.0);
    e.mod_dest(1, 2, 0, at::VOLUME, 0, 0, 0.3, 0.0, 2.0, scale::LINEAR);
}

#[test]
fn nao_aloca_no_caminho_de_audio() {
    let mut e = engine();
    cheio(&mut e);
    e.play();
    for _ in 0..40 {
        run(&mut e, 128);
    }
    let mut out = vec![0.0f32; 128];
    let allocs = crate::testalloc::count(|| {
        for _ in 0..400 {
            e.process(&mut out, &mut [0.0f32; 128]);
        }
        // e reenviando a mesma modulação no meio (o app faz isso quando algo muda)
        e.mod_clear();
        mods(&mut e);
        for _ in 0..100 {
            e.process(&mut out, &mut [0.0f32; 128]);
        }
    });
    assert_eq!(allocs, 0);
}

#[test]
fn a_saida_nao_depende_do_tamanho_do_bloco() {
    let render = |block: usize| {
        let mut e = engine();
        cheio(&mut e);
        e.play();
        let (mut out_l, mut out_r) = (Vec::new(), Vec::new());
        let mut left = 48_000usize;
        while left > 0 {
            let n = block.min(left);
            let (mut l, mut r) = (vec![0.0f32; n], vec![0.0f32; n]);
            e.process(&mut l, &mut r);
            out_l.extend(l.iter().map(|s| s.to_bits()));
            out_r.extend(r.iter().map(|s| s.to_bits()));
            left -= n;
        }
        out_l.extend(out_r);
        out_l
    };
    let base = render(128);
    assert!(base.iter().any(|&b| f32::from_bits(b) != 0.0));
    // blocos que são múltiplos do passo (o tempo real do worklet, o render fora de tempo real)
    for block in [4096, 1024, 96, 32] {
        assert!(render(block) == base, "bloco de {block} difere do de 128");
    }
}

#[test]
fn a_modulacao_de_volume_se_ouve_na_saida() {
    let mut e = engine();
    lfo(&mut e, shape::SINE, 4.0, true);
    e.play();
    let out = run(&mut e, 12_000); // 0,25 s = 1 ciclo
    // 0,5 de sinal, pan central (−3 dB): a saída anda entre 0 e 2 · 0,5 · 0,7071
    let (low, peak) = extremes(&out[200..]);
    assert!((peak - std::f32::consts::FRAC_1_SQRT_2).abs() < 0.03, "{peak}");
    assert!(low < 0.05, "{low}");
}

/// Reenviar a mesma modulação (`mod_clear` + fontes + destinos, como o app faz a cada edição) com o
/// projeto tocando não recomeça a fase do LFO nem o nível do seguidor.
#[test]
fn reenviar_a_modulacao_preserva_a_fase_e_o_nivel() {
    let send_lfo = |e: &mut Engine| {
        e.mod_source(0, 0, kind::LFO, 3.0, false, 1.0, 0.0, true, shape::SINE, 10.0, 100.0, 0.0);
        e.mod_dest(0, 0, 0, at::VOLUME, 0, 0, 0.5, 0.0, 2.0, scale::LINEAR);
    };
    let mut a = engine();
    let mut b = engine();
    send_lfo(&mut a);
    send_lfo(&mut b);
    a.play();
    b.play();
    let before_a = gains(&mut a, 120);
    let before_b = gains(&mut b, 120);
    assert_eq!(before_a, before_b);
    // b é reenviado no meio do ciclo; a segue sem mexer
    b.mod_clear();
    send_lfo(&mut b);
    let (after_a, after_b) = (gains(&mut a, 60), gains(&mut b, 60));
    for (i, (x, y)) in after_a.iter().zip(&after_b).enumerate() {
        assert!((x - y).abs() < 1e-4, "passo {i}: {x} contra {y} (a fase recomeçou)");
    }

    // seguidor: o nível já subido sobrevive ao reenvio
    let mut c = follower(50.0, 200.0, 1.0);
    let mut d = follower(50.0, 200.0, 1.0);
    let (vc, vd) = (gains(&mut c, 300), gains(&mut d, 300));
    assert_eq!(vc, vd);
    assert!(vd[299] > 0.3, "o seguidor subiu: {}", vd[299]);
    d.mod_clear();
    d.mod_source(0, 0, kind::FOLLOWER, 0.0, false, 1.0, 0.0, false, 0, 50.0, 200.0, 0.0);
    d.mod_dest(0, 0, 0, at::VOLUME, 0, 0, 1.0, 0.0, 1.0, scale::LINEAR);
    let (nc, nd) = (gains(&mut c, 5), gains(&mut d, 5));
    for (x, y) in nc.iter().zip(&nd) {
        assert!((x - y).abs() < 1e-4, "o nível recomeçou: {x} contra {y}");
    }
}

/// Trocar o tipo do modulador no reenvio recomeça o estado (não herda a fase do LFO).
#[test]
fn trocar_o_tipo_no_reenvio_recomeca_o_estado() {
    let mut e = engine();
    e.mod_source(0, 0, kind::LFO, 3.0, false, 1.0, 0.0, true, shape::SINE, 10.0, 100.0, 0.0);
    e.mod_dest(0, 0, 0, at::VOLUME, 0, 0, 0.5, 0.0, 2.0, scale::LINEAR);
    e.play();
    gains(&mut e, 50);
    e.mod_clear();
    e.mod_source(0, 0, kind::MACRO, 0.0, false, 1.0, 0.0, false, 0, 0.0, 0.0, 1.0);
    e.mod_dest(0, 0, 0, at::VOLUME, 0, 0, 0.5, 0.0, 2.0, scale::LINEAR);
    // macro 1 unipolar, +0,5 do curso 0..2 sobre a base 1 (meio): 1,0 + 1,0 = 2
    assert!((gains(&mut e, 1)[0] - 2.0).abs() < 1e-4);
}

/// O estado do LFO (fase e alisamento) mora no ÍNDICE do modulador: quem é reenviado no mesmo índice segue
/// de onde estava, e quem ocupa o índice de outro que saiu herda a fase dele. Por isso o app mantém um índice
/// estável por modulador (apagar o 1 de dois LFOs reenvia o 2 no índice 1, não no 0).
#[test]
fn a_fase_do_lfo_e_por_indice_do_modulador() {
    // dois LFOs livres: 1 Hz no índice 0 e 3 Hz no índice 1, ambos no volume
    fn send(e: &mut Engine, index: usize, hz: f32) {
        e.mod_source(0, index, kind::LFO, hz, false, 1.0, 0.0, true, shape::SINE, 10.0, 100.0, 0.0);
        e.mod_dest(0, index, 0, at::VOLUME, 0, 0, 0.5, 0.0, 2.0, scale::LINEAR);
    }
    // referência: só o LFO de 3 Hz, no índice 1, rodando desde o começo
    let mut solo = engine();
    solo.play();
    send(&mut solo, 1, 3.0);
    gains(&mut solo, 37);
    let want = gains(&mut solo, 10);

    // apagar o primeiro e reenviar o de 3 Hz no MESMO índice (1): segue a fase própria, igual à referência
    let mut stable = engine();
    stable.play();
    send(&mut stable, 0, 1.0);
    send(&mut stable, 1, 3.0);
    gains(&mut stable, 37);
    stable.mod_clear();
    send(&mut stable, 1, 3.0);
    let got = gains(&mut stable, 10);
    for (g, w) in got.iter().zip(&want) {
        assert!((g - w).abs() < 1e-3, "a fase própria se perdeu: {g} contra {w}");
    }

    // reenviar o de 3 Hz no índice 0 (o que o app fazia pela posição na lista) herda a fase do que saiu
    let mut shifted = engine();
    shifted.play();
    send(&mut shifted, 0, 1.0);
    send(&mut shifted, 1, 3.0);
    gains(&mut shifted, 37);
    shifted.mod_clear();
    send(&mut shifted, 0, 3.0);
    let inherited = gains(&mut shifted, 10);
    let worst = inherited.iter().zip(&want).map(|(g, w)| (g - w).abs()).fold(0.0f32, f32::max);
    assert!(worst > 0.05, "esperava a fase herdada do índice 0 (diferença {worst})");
}
