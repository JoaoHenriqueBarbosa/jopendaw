//! De-esser: reduz a sibilância (s, x, ch) comprimindo uma banda de detecção ajustável.
//!
//! Um passa-banda de pico unitário (SVF, frequência e Q ajustáveis) separa a banda. O nível dela
//! (pico dos dois canais, seguidor de queda curta) passa por um computador de ganho com joelho
//! curto e balística em dB (ver `compressor.rs`). Dois modos:
//!
//! - banda dividida: o ganho age só na banda (`x + banda · (g − 1)`), o resto do espectro passa
//!   intacto: é o modo transparente. Sem redução (g = 1) a saída é exatamente a entrada.
//! - banda larga: o ganho age no sinal todo (`x · g`), como um compressor com chave filtrada.
//!
//! "Ouvir" troca a saída pela banda de detecção, para achar a frequência do "s" de quem canta.
//! Os dois modos e o "ouvir" se misturam por um ganho suavizado, sem estalo ao trocar.

use super::compressor::{fast_exp2, fast_log2, reduction};
use super::eq::Glide;
use crate::dsp::{FilterMode, Smoothed, Svf, smoothing};
use crate::effect::{Effect, deesser_param as p};

const SMOOTH_SECS: f32 = 0.010;
const GLIDE_SECS: f32 = 0.005;
const FREQ_SECS: f32 = 0.02;
/// Quanto o seguidor segura o pico da banda (as sibilâncias têm mais de 4 kHz: 1,5 ms cobre vários
/// ciclos sem arrastar o ganho).
const HOLD_SECS: f32 = 0.0015;
/// Joelho fixo, dB: um degrau seco no limiar estalaria numa banda tão estreita.
const KNEE_DB: f32 = 2.0;
const DB_PER_LOG2: f32 = 3.010_3;
const LOG2_PER_DB: f32 = 0.166_096_4;
const INPUT_LIMIT: f32 = 1e6;

fn time_coef(secs: f32, rate: f32) -> f32 {
    (-1.0 / (secs * rate)).exp()
}

pub struct Deesser {
    rate: f32,
    freq: Smoothed,
    q: Smoothed,
    /// (freq, q) em uso: só recalcula a tangente quando muda.
    used: (f32, f32),
    filter: [Svf; 2],
    /// Amortecimento do filtro (1/Q), para dar pico unitário ao passa-banda.
    k: f32,
    threshold: Smoothed,
    slope: Smoothed,
    /// 0 banda dividida, 1 banda larga.
    wide: Glide,
    listen: Glide,
    attack: f32,
    release: f32,
    peak: f32,
    hold: f32,
    env: f32,
    meter: f32,
    smooth: f32,
    glide: f32,
    fresh: bool,
}

impl Deesser {
    pub fn new(rate: f64) -> Self {
        let rate = rate as f32;
        let mut d = Self {
            rate,
            freq: Smoothed::new(6500.0),
            q: Smoothed::new(1.5),
            used: (0.0, 0.0),
            filter: [Svf::default(); 2],
            k: 1.0,
            threshold: Smoothed::new(-30.0),
            slope: Smoothed::new(0.8),
            wide: Glide::new(0.0),
            listen: Glide::new(0.0),
            attack: time_coef(0.001, rate),
            release: time_coef(0.05, rate),
            peak: 0.0,
            hold: time_coef(HOLD_SECS, rate),
            env: 0.0,
            meter: 0.0,
            smooth: smoothing(SMOOTH_SECS, 1, rate),
            glide: smoothing(GLIDE_SECS, 1, rate),
            fresh: true,
        };
        d.update_filter(true);
        d
    }

    fn update_filter(&mut self, force: bool) {
        let now = (self.freq.value, self.q.value);
        if !force && now == self.used {
            return;
        }
        self.used = now;
        self.k = 1.0 / now.1.max(0.1);
        let g = Svf::g(now.0.min(0.45 * self.rate), self.rate);
        for f in &mut self.filter {
            f.set(g, self.k);
        }
    }

    fn snap(&mut self) {
        self.freq.snap();
        self.q.snap();
        self.threshold.snap();
        self.slope.snap();
        self.wide.snap();
        self.listen.snap();
        self.update_filter(false);
    }
}

#[inline]
fn clean(x: f32) -> f32 {
    if x.is_finite() { x.clamp(-INPUT_LIMIT, INPUT_LIMIT) } else { 0.0 }
}

impl Effect for Deesser {
    fn set_param(&mut self, id: u32, value: f32) {
        if !value.is_finite() {
            return;
        }
        match id {
            p::FREQ => self.freq.set(value.clamp(4000.0, 10000.0)),
            p::Q => self.q.set(value.clamp(0.5, 4.0)),
            p::THRESHOLD => self.threshold.set(value.clamp(-60.0, 0.0)),
            p::RATIO => self.slope.set(1.0 - 1.0 / value.clamp(1.0, 20.0)),
            p::ATTACK => self.attack = time_coef(value.clamp(0.0001, 0.05), self.rate),
            p::RELEASE => self.release = time_coef(value.clamp(0.005, 0.5), self.rate),
            p::MODE => self.wide.set(if value >= 0.5 { 1.0 } else { 0.0 }),
            p::LISTEN => self.listen.set(if value >= 0.5 { 1.0 } else { 0.0 }),
            _ => return,
        }
        if self.fresh {
            self.snap();
        }
    }

    fn process(&mut self, left: &mut [f32], right: &mut [f32]) {
        self.fresh = false;
        let frames = left.len().min(right.len());
        let fa = smoothing(FREQ_SECS, frames.max(1), self.rate);
        self.freq.step(fa);
        self.q.step(fa);
        self.update_filter(false);
        let a = self.smooth;
        let mut peak_gr = 0.0f32;
        for i in 0..frames {
            let x = [clean(left[i]), clean(right[i])];
            let band = [self.filter[0].tick(x[0], FilterMode::BandPass).0 * self.k, self.filter[1].tick(x[1], FilterMode::BandPass).0 * self.k];
            self.peak = (self.peak * self.hold).max(band[0].abs().max(band[1].abs())).max(1e-9);
            let level = 2.0 * DB_PER_LOG2 * fast_log2(self.peak);
            let gr = reduction(level - self.threshold.step(a), self.slope.step(a), KNEE_DB);
            let coef = if gr > self.env { self.attack } else { self.release };
            self.env = gr + (self.env - gr) * coef;
            let dg = fast_exp2(-self.env * LOG2_PER_DB) - 1.0;
            let wide = self.wide.step(self.glide);
            let listen = self.listen.step(self.glide);
            for ch in 0..2 {
                // g − 1 age na banda (dividida) ou no sinal todo (larga)
                let comp = x[ch] + dg * (band[ch] + wide * (x[ch] - band[ch]));
                let out = comp + listen * (band[ch] - comp);
                if ch == 0 {
                    left[i] = out;
                } else {
                    right[i] = out;
                }
            }
            peak_gr = peak_gr.max(self.env);
        }
        self.meter = peak_gr;
        if self.env < 1e-9 {
            self.env = 0.0;
        }
        let mut sick = false;
        for f in &mut self.filter {
            f.flush();
            sick |= !f.is_finite();
        }
        if sick {
            for f in &mut self.filter {
                f.reset();
            }
        }
    }

    fn reset(&mut self) {
        for f in &mut self.filter {
            f.reset();
        }
        self.peak = 0.0;
        self.env = 0.0;
        self.meter = 0.0;
        self.snap();
        self.fresh = true;
    }

    fn meter(&self) -> f32 {
        self.meter
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::dsp::Rng;
    use std::f32::consts::TAU;

    const RATE: f64 = 48_000.0;

    fn sine(freq: f32, amp: f32, n: usize) -> Vec<f32> {
        (0..n).map(|i| amp * (TAU * freq * i as f32 / RATE as f32).sin()).collect()
    }

    fn run(d: &mut Deesser, src: &[f32]) -> Vec<f32> {
        let (mut l, mut r) = (src.to_vec(), src.to_vec());
        for (cl, cr) in l.chunks_mut(128).zip(r.chunks_mut(128)) {
            d.process(cl, cr);
        }
        l
    }

    fn rms(x: &[f32]) -> f32 {
        (x.iter().map(|v| (*v as f64).powi(2)).sum::<f64>() / x.len() as f64).sqrt() as f32
    }

    fn db(x: f32) -> f32 {
        20.0 * x.log10()
    }

    fn deesser(freq: f32, threshold: f32, ratio: f32, mode: f32) -> Deesser {
        let mut d = Deesser::new(RATE);
        d.set_param(p::FREQ, freq);
        d.set_param(p::THRESHOLD, threshold);
        d.set_param(p::RATIO, ratio);
        d.set_param(p::MODE, mode);
        d.set_param(p::ATTACK, 0.0005);
        d.set_param(p::RELEASE, 0.03);
        d
    }

    #[test]
    fn seno_de_7k_cai_e_o_de_300_nao() {
        for mode in [0.0, 1.0] {
            let mut d = deesser(7000.0, -30.0, 10.0, mode);
            let src = sine(7000.0, 0.5, 48_000);
            let out = run(&mut d, &src);
            let gain = db(rms(&out[30_000..]) / rms(&src[30_000..]));
            assert!(gain < -15.0, "modo {mode}: 7 kHz só caiu {gain} dB");
            assert!(d.meter() > 15.0);
            let mut d = deesser(7000.0, -30.0, 10.0, mode);
            let src = sine(300.0, 0.5, 48_000);
            let out = run(&mut d, &src);
            let gain = db(rms(&out[30_000..]) / rms(&src[30_000..]));
            assert!(gain.abs() < 0.1, "modo {mode}: 300 Hz mexeu {gain} dB");
        }
    }

    #[test]
    fn banda_dividida_poupa_o_resto_e_a_larga_nao() {
        // grave forte + sibilância: na dividida o grave sai intacto, na larga desce junto
        let mix: Vec<f32> = sine(200.0, 0.4, 48_000).iter().zip(sine(7000.0, 0.4, 48_000)).map(|(a, b)| a + b).collect();
        let low_level = |out: &[f32]| {
            // média de 200 Hz por correlação com o seno
            let s = sine(200.0, 1.0, 48_000);
            let n = 18_000;
            let dot: f64 = out[30_000..].iter().zip(&s[30_000..]).map(|(a, b)| (*a * *b) as f64).sum();
            (2.0 * dot / n as f64) as f32
        };
        let mut split = deesser(7000.0, -30.0, 10.0, 0.0);
        let out = run(&mut split, &mix);
        assert!((low_level(&out) - 0.4).abs() < 0.03, "dividida: {}", low_level(&out));
        let mut wide = deesser(7000.0, -30.0, 10.0, 1.0);
        let out = run(&mut wide, &mix);
        assert!(low_level(&out) < 0.2, "larga: {}", low_level(&out));
    }

    #[test]
    fn voz_sem_sibilancia_passa_quase_intacta() {
        // vogal sintética: fundamental e harmônicos que decaem 6 dB/oitava, sem energia nos 4..10 kHz
        let n = 48_000;
        let mut voice = vec![0.0f32; n];
        for h in 1..=12 {
            let f = 140.0 * h as f32;
            for (o, v) in voice.iter_mut().zip(sine(f, 0.25 / h as f32, n)) {
                *o += v;
            }
        }
        let mut d = deesser(6500.0, -30.0, 6.0, 0.0);
        let out = run(&mut d, &voice);
        let gain = db(rms(&out[24_000..]) / rms(&voice[24_000..]));
        assert!(gain.abs() < 0.3, "{gain} dB");
        assert!(d.meter() < 2.0, "{}", d.meter());
    }

    #[test]
    fn ouvir_a_banda() {
        let mut d = deesser(7000.0, 0.0, 1.0, 0.0);
        d.set_param(p::LISTEN, 1.0);
        let mix: Vec<f32> = sine(200.0, 0.4, 48_000).iter().zip(sine(7000.0, 0.1, 48_000)).map(|(a, b)| a + b).collect();
        let out = run(&mut d, &mix);
        // fica só a sibilância: o grave (a 5 oitavas) some quase todo
        let high = sine(7000.0, 0.1, 48_000);
        let gain = db(rms(&out[30_000..]) / rms(&high[30_000..]));
        assert!(gain.abs() < 1.0, "{gain} dB");
    }

    #[test]
    fn ruido_sem_nan_e_extremos() {
        for rate in [8_000.0, 44_100.0, 192_000.0] {
            let mut d = Deesser::new(rate);
            let mut rng = Rng::new(11);
            for id in 0..12 {
                for v in [-1e9, 1e9, 0.0, -1.0, f32::NAN, f32::INFINITY] {
                    d.set_param(id, v);
                }
            }
            let (mut l, mut r): (Vec<f32>, Vec<f32>) = (0..8192).map(|_| (rng.bipolar() * 1e6, rng.bipolar())).unzip();
            for (cl, cr) in l.chunks_mut(100).zip(r.chunks_mut(100)) {
                d.process(cl, cr);
            }
            assert!(l.iter().chain(&r).all(|v| v.is_finite()), "taxa {rate}");
            let (mut l, mut r) = (vec![f32::NAN; 64], vec![f32::INFINITY; 64]);
            d.process(&mut l, &mut r);
            assert!(l.iter().chain(&r).all(|v| v.is_finite()) && d.meter().is_finite());
            assert_eq!(d.latency(), 0);
        }
    }
}
