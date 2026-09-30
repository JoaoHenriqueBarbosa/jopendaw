//! Imagem estéreo: largura por 3 bandas, balanço, mono nos graves e medidor de correlação.
//!
//! O trabalho é no lado (side): `M = (L + R)/2` passa intacto (a soma L + R, o que uma caixa mono
//! ouve, nunca muda) e só `S = (L − R)/2` é mexido, por banda. A banda baixa é o passa-baixa LR4
//! do primeiro cruzamento, a aguda o passa-alta LR4 do segundo, e a média é o que sobra
//! (`S − baixa − aguda`): as três somam `S` por construção, então largura 100% é identidade e 0%
//! em tudo dá `L = R = M`, sem o giro de fase que um divisor passa-tudo deixaria.
//!
//! "Mono nos graves" tira do lado o que fica abaixo da frequência escolhida (passa-alta LR4 do
//! próprio lado no lugar dele), depois das larguras. O balanço vem por último e só atenua o
//! canal oposto, como o pan do utilitário. A correlação (`Σ LR / √(Σ LL · Σ RR)`, média de 300 ms
//! da saída) vai para [`Effect::meter`]: 1 mono, 0 sem relação, −1 em oposição de fase.

use super::eq::Glide;
use super::multiband::Lr4;
use crate::dsp::{Smoothed, Svf, smoothing};
use crate::effect::{Effect, imager_param as p};

const GLIDE_SECS: f32 = 0.005;
const XOVER_SECS: f32 = 0.02;
/// Janela da correlação, s.
const CORR_SECS: f64 = 0.3;
const INPUT_LIMIT: f32 = 1e6;

pub struct Imager {
    rate: f32,
    low_hz: Smoothed,
    high_hz: Smoothed,
    mono_hz: Smoothed,
    /// Em uso (Hz): baixo, alto, mono.
    used: (f32, f32, f32),
    /// Só o lado passa por estes: passa-baixa do cruzamento baixo, passa-alta do alto e passa-alta
    /// do mono nos graves.
    low: Lr4,
    high: Lr4,
    mono: Lr4,
    widths: [Glide; 3],
    balance: Glide,
    bass_mono: Glide,
    glide: f32,
    corr_coef: f64,
    sll: f64,
    srr: f64,
    slr: f64,
    meter: f32,
    fresh: bool,
}

impl Imager {
    pub fn new(rate: f64) -> Self {
        let rate32 = rate as f32;
        let mut m = Self {
            rate: rate32,
            low_hz: Smoothed::new(200.0),
            high_hz: Smoothed::new(4000.0),
            mono_hz: Smoothed::new(120.0),
            used: (0.0, 0.0, 0.0),
            low: Lr4::default(),
            high: Lr4::default(),
            mono: Lr4::default(),
            widths: [Glide::new(1.0); 3],
            balance: Glide::new(0.0),
            bass_mono: Glide::new(0.0),
            glide: smoothing(GLIDE_SECS, 1, rate32),
            corr_coef: (-1.0 / (CORR_SECS * rate)).exp(),
            sll: 0.0,
            srr: 0.0,
            slr: 0.0,
            meter: 0.0,
            fresh: true,
        };
        m.update_filters(true);
        m
    }

    /// Cruzamentos efetivos: o alto fica meia oitava acima do baixo; todos abaixo de Nyquist.
    fn update_filters(&mut self, force: bool) {
        let top = 0.45 * self.rate;
        let high = self.high_hz.value.max(self.low_hz.value * 1.5).min(top);
        let low = self.low_hz.value.min(high / 1.5).max(10.0);
        let mono = self.mono_hz.value.min(top).max(10.0);
        if !force && (low, high, mono) == self.used {
            return;
        }
        self.used = (low, high, mono);
        self.low.set(Svf::g(low, self.rate));
        self.high.set(Svf::g(high, self.rate));
        self.mono.set(Svf::g(mono, self.rate));
    }

    fn snap(&mut self) {
        self.low_hz.snap();
        self.high_hz.snap();
        self.mono_hz.snap();
        for w in &mut self.widths {
            w.snap();
        }
        self.balance.snap();
        self.bass_mono.snap();
        self.update_filters(false);
    }
}

impl Effect for Imager {
    fn set_param(&mut self, id: u32, value: f32) {
        if !value.is_finite() {
            return;
        }
        match id {
            p::XOVER_LOW => self.low_hz.set(value.clamp(50.0, 1000.0)),
            p::XOVER_HIGH => self.high_hz.set(value.clamp(1000.0, 12000.0)),
            p::WIDTH_LOW => self.widths[0].set(value.clamp(0.0, 2.0)),
            p::WIDTH_MID => self.widths[1].set(value.clamp(0.0, 2.0)),
            p::WIDTH_HIGH => self.widths[2].set(value.clamp(0.0, 2.0)),
            p::BALANCE => self.balance.set(value.clamp(-1.0, 1.0)),
            p::BASS_MONO => self.bass_mono.set(if value >= 0.5 { 1.0 } else { 0.0 }),
            p::MONO_FREQ => self.mono_hz.set(value.clamp(40.0, 500.0)),
            _ => return,
        }
        if self.fresh {
            self.snap();
        }
    }

    fn process(&mut self, left: &mut [f32], right: &mut [f32]) {
        self.fresh = false;
        let frames = left.len().min(right.len());
        let xa = smoothing(XOVER_SECS, frames.max(1), self.rate);
        self.low_hz.step(xa);
        self.high_hz.step(xa);
        self.mono_hz.step(xa);
        self.update_filters(false);
        let c = self.corr_coef;
        for i in 0..frames {
            let clean = |x: f32| if x.is_finite() { x.clamp(-INPUT_LIMIT, INPUT_LIMIT) } else { 0.0 };
            let (l, r) = (clean(left[i]), clean(right[i]));
            let mid = 0.5 * (l + r);
            let side = 0.5 * (l - r);
            let low = self.low.lowpass(side);
            let high = self.high.highpass(side);
            let band_mid = side - low - high;
            let mut s = self.widths[0].step(self.glide) * low + self.widths[1].step(self.glide) * band_mid + self.widths[2].step(self.glide) * high;
            // o filtro roda sempre (estado aquecido); o quanto vale é o ganho suavizado
            let kept = self.mono.highpass(s);
            s += self.bass_mono.step(self.glide) * (kept - s);
            let bal = self.balance.step(self.glide);
            let (gl, gr) = (1.0 - bal.max(0.0), 1.0 + bal.min(0.0));
            let (ol, or) = ((mid + s) * gl, (mid - s) * gr);
            left[i] = ol;
            right[i] = or;
            let (dl, dr) = (ol as f64, or as f64);
            self.sll = self.sll * c + dl * dl * (1.0 - c);
            self.srr = self.srr * c + dr * dr * (1.0 - c);
            self.slr = self.slr * c + dl * dr * (1.0 - c);
        }
        let den = (self.sll * self.srr).sqrt();
        self.meter = if den > 1e-16 { (self.slr / den).clamp(-1.0, 1.0) as f32 } else { 0.0 };
        for f in [&mut self.low, &mut self.high, &mut self.mono] {
            f.flush();
        }
        if ![&self.low, &self.high, &self.mono].iter().all(|f| f.finite()) || !(self.sll.is_finite() && self.srr.is_finite() && self.slr.is_finite()) {
            self.reset_state();
        }
    }

    fn reset(&mut self) {
        self.reset_state();
        self.snap();
        self.fresh = true;
    }

    fn meter(&self) -> f32 {
        self.meter
    }
}

impl Imager {
    fn reset_state(&mut self) {
        for f in [&mut self.low, &mut self.high, &mut self.mono] {
            f.reset();
        }
        self.sll = 0.0;
        self.srr = 0.0;
        self.slr = 0.0;
        self.meter = 0.0;
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::dsp::Rng;
    use std::f64::consts::TAU;

    const RATE: f64 = 48_000.0;

    fn noise(seed: u32, n: usize) -> (Vec<f32>, Vec<f32>) {
        let mut rng = Rng::new(seed);
        // estéreo com parte comum e parte independente
        (0..n)
            .map(|_| {
                let common = rng.bipolar() * 0.3;
                (common + rng.bipolar() * 0.2, common + rng.bipolar() * 0.2)
            })
            .unzip()
    }

    fn run(m: &mut Imager, l: &[f32], r: &[f32]) -> (Vec<f32>, Vec<f32>) {
        let (mut ol, mut or) = (l.to_vec(), r.to_vec());
        for (cl, cr) in ol.chunks_mut(100).zip(or.chunks_mut(100)) {
            m.process(cl, cr);
        }
        (ol, or)
    }

    fn widths(m: &mut Imager, lo: f32, mid: f32, hi: f32) {
        m.set_param(p::WIDTH_LOW, lo);
        m.set_param(p::WIDTH_MID, mid);
        m.set_param(p::WIDTH_HIGH, hi);
    }

    #[test]
    fn largura_zero_vira_mono_exato() {
        let (l, r) = noise(1, 20_000);
        let mut m = Imager::new(RATE);
        widths(&mut m, 0.0, 0.0, 0.0);
        let (ol, or) = run(&mut m, &l, &r);
        for i in 0..l.len() {
            let mid = 0.5 * (l[i] + r[i]);
            assert!((ol[i] - mid).abs() < 1e-6 && (or[i] - mid).abs() < 1e-6, "{i}");
            assert_eq!(ol[i], or[i]);
        }
        assert!((m.meter() - 1.0).abs() < 1e-4, "correlação {}", m.meter());
    }

    #[test]
    fn cem_por_cento_e_identidade() {
        let (l, r) = noise(2, 20_000);
        let mut m = Imager::new(RATE);
        let (ol, or) = run(&mut m, &l, &r);
        let err = l.iter().zip(&ol).chain(r.iter().zip(&or)).fold(0.0f32, |e, (a, b)| e.max((a - b).abs()));
        assert!(err < 1e-5, "{err}");
        // e depois de mexer e voltar
        widths(&mut m, 0.3, 1.7, 0.0);
        run(&mut m, &l, &r);
        widths(&mut m, 1.0, 1.0, 1.0);
        run(&mut m, &l, &r);
        let (ol, or) = run(&mut m, &l, &r);
        let err = l.iter().zip(&ol).chain(r.iter().zip(&or)).fold(0.0f32, |e, (a, b)| e.max((a - b).abs()));
        assert!(err < 1e-5, "{err}");
    }

    #[test]
    fn soma_lr_preservada_com_qualquer_largura() {
        let (l, r) = noise(3, 30_000);
        for (lo, mid, hi, bass) in [(0.0, 2.0, 0.5, 0.0), (2.0, 2.0, 2.0, 1.0), (0.4, 0.0, 1.3, 1.0)] {
            let mut m = Imager::new(RATE);
            widths(&mut m, lo, mid, hi);
            m.set_param(p::BASS_MONO, bass);
            m.set_param(p::MONO_FREQ, 250.0);
            let (ol, or) = run(&mut m, &l, &r);
            let err = (0..l.len()).fold(0.0f32, |e, i| e.max(((ol[i] + or[i]) - (l[i] + r[i])).abs()));
            assert!(err < 1e-5, "{lo}/{mid}/{hi}: {err}");
        }
    }

    #[test]
    fn largura_dobra_o_lado_em_cada_banda() {
        // lado puro (L = −R) a 1 kHz na banda média; 200% dobra, 50% pela metade
        let n = 48_000;
        let s: Vec<f32> = (0..n).map(|i| 0.2 * (std::f64::consts::TAU * 1000.0 * i as f64 / RATE).sin() as f32).collect();
        let neg: Vec<f32> = s.iter().map(|v| -v).collect();
        for (w, want) in [(2.0, 2.0), (0.5, 0.5), (0.0, 0.0)] {
            let mut m = Imager::new(RATE);
            widths(&mut m, 1.0, w, 1.0);
            let (ol, _) = run(&mut m, &s, &neg);
            let peak = ol[40_000..].iter().fold(0.0f32, |a, v| a.max(v.abs()));
            assert!((peak - 0.2 * want).abs() < 0.01, "largura {w}: {peak}");
        }
    }

    #[test]
    fn mono_nos_graves() {
        let n = 48_000;
        let tone = |f: f64| -> Vec<f32> { (0..n).map(|i| 0.3 * (TAU * f * i as f64 / RATE).sin() as f32).collect() };
        let neg = |v: &[f32]| -> Vec<f32> { v.iter().map(|x| -x).collect() };
        let peak = |v: &[f32]| v[40_000..].iter().fold(0.0f32, |a, x| a.max(x.abs()));
        let mut m = Imager::new(RATE);
        m.set_param(p::BASS_MONO, 1.0);
        m.set_param(p::MONO_FREQ, 200.0);
        // 40 Hz em oposição de fase: quase some (mono); 2 kHz fica como estava
        let (l, r) = (tone(40.0), neg(&tone(40.0)));
        let (ol, _) = run(&mut m, &l, &r);
        assert!(peak(&ol) < 0.03, "{}", peak(&ol));
        let mut m = Imager::new(RATE);
        m.set_param(p::BASS_MONO, 1.0);
        m.set_param(p::MONO_FREQ, 200.0);
        let (l, r) = (tone(2000.0), neg(&tone(2000.0)));
        let (ol, or) = run(&mut m, &l, &r);
        assert!((peak(&ol) - 0.3).abs() < 0.01 && (peak(&or) - 0.3).abs() < 0.01);
        // desligado, o grave fica estéreo
        let mut m = Imager::new(RATE);
        let (l, r) = (tone(40.0), neg(&tone(40.0)));
        let (ol, _) = run(&mut m, &l, &r);
        assert!((peak(&ol) - 0.3).abs() < 0.01);
    }

    #[test]
    fn balanco_atenua_so_o_lado_oposto() {
        let l = vec![0.5f32; 4800];
        let mut m = Imager::new(RATE);
        m.set_param(p::BALANCE, 1.0);
        let (ol, or) = run(&mut m, &l, &l);
        assert!(ol[4700].abs() < 1e-4 && (or[4700] - 0.5).abs() < 1e-4);
        let mut m = Imager::new(RATE);
        m.set_param(p::BALANCE, -0.5);
        let (ol, or) = run(&mut m, &l, &l);
        assert!((ol[4700] - 0.5).abs() < 1e-4 && (or[4700] - 0.25).abs() < 1e-4);
    }

    #[test]
    fn correlacao() {
        let x: Vec<f32> = noise(4, 48_000).0;
        let mut m = Imager::new(RATE);
        run(&mut m, &x, &x);
        assert!((m.meter() - 1.0).abs() < 1e-4);
        let neg: Vec<f32> = x.iter().map(|v| -v).collect();
        let mut m = Imager::new(RATE);
        run(&mut m, &x, &neg);
        assert!((m.meter() + 1.0).abs() < 1e-4);
        let (a, b) = (noise(5, 96_000).0, noise(6, 96_000).1);
        let mut m = Imager::new(RATE);
        run(&mut m, &a, &b);
        // partes comuns independentes entre as duas fontes: perto de zero
        assert!(m.meter().abs() < 0.2, "{}", m.meter());
        let mut m = Imager::new(RATE);
        run(&mut m, &vec![0.0; 4800], &vec![0.0; 4800]);
        assert_eq!(m.meter(), 0.0);
        assert_eq!(m.latency(), 0);
    }

    #[test]
    fn extremos_sem_nan() {
        for rate in [8_000.0, 44_100.0, 192_000.0] {
            let mut m = Imager::new(rate);
            let mut rng = Rng::new(17);
            for id in 0..12 {
                for v in [-1e9, 1e9, 0.0, -1.0, f32::NAN, f32::INFINITY] {
                    m.set_param(id, v);
                }
            }
            let (mut l, mut r): (Vec<f32>, Vec<f32>) = (0..8192).map(|_| (rng.bipolar() * 1e6, rng.bipolar())).unzip();
            for (cl, cr) in l.chunks_mut(100).zip(r.chunks_mut(100)) {
                m.process(cl, cr);
            }
            assert!(l.iter().chain(&r).all(|v| v.is_finite()), "taxa {rate}");
            let (mut l, mut r) = (vec![f32::NAN; 64], vec![f32::INFINITY; 64]);
            m.process(&mut l, &mut r);
            assert!(l.iter().chain(&r).all(|v| v.is_finite()) && m.meter().is_finite());
        }
    }
}
