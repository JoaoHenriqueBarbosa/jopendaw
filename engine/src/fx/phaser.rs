//! Phaser: 2 a 12 estágios passa-tudo de 1ª ordem em série, todos com o mesmo corte, que um LFO
//! senoidal varre em escala exponencial (oitavas) em torno do centro. Somado ao seco, cada par de
//! estágios cava um vale que anda pelo espectro; a realimentação da saída para a entrada afia os
//! vales e cria picos.
//!
//! Os estágios são filtros TPT (trapezoidais, de Zavalishin), que aguentam o corte mudando a cada
//! quadro sem estourar nem chiar; o coeficiente é calculado a cada 16 quadros e interpolado entre
//! eles. Os 12 estágios rodam sempre e a saída é tirada no estágio pedido: trocar o número de
//! estágios é um crossfade entre duas saídas da mesma cadeia, sem estalo.

use std::f32::consts::PI;

use crate::dsp::{Smoothed, sin_turns, smoothing};
use crate::effect::{Effect, phaser_param as P};
use crate::fx::delay::{Ramp, safety};

const CONTROL: usize = 16;
const STAGES: [usize; 5] = [2, 4, 6, 8, 12];
const MAX_STAGES: usize = 12;
/// Varredura com a profundidade no máximo: ±3 oitavas em torno do centro.
const RANGE_OCTAVES: f32 = 3.0;
const MIN_HZ: f32 = 20.0;
const PARAM_TAU: f32 = 0.02;
/// Crossfade entre saídas quando muda o número de estágios.
const STAGE_TAU: f32 = 0.03;

pub struct Phaser {
    rate: f32,
    /// Estado dos integradores (canal, estágio).
    state: [[f32; MAX_STAGES]; 2],
    mix: Smoothed,
    speed: Smoothed,
    depth: Smoothed,
    center: Smoothed,
    feedback: Smoothed,
    stereo: Smoothed,
    /// Peso da saída de cada opção de estágios.
    taps: [Smoothed; STAGES.len()],
    /// Estágios que rodaram no último bloco.
    active: usize,
    phase: f32,
    /// Coeficiente `G = g / (1 + g)` de cada canal no fim do bloco anterior.
    coef: [f32; 2],
    /// Saída do último quadro, para a realimentação.
    last: [f32; 2],
    primed: bool,
}

impl Phaser {
    pub fn new(rate: f64) -> Self {
        let mut taps = [Smoothed::new(0.0); STAGES.len()];
        taps[1] = Smoothed::new(1.0);
        Self {
            rate: rate as f32,
            state: [[0.0; MAX_STAGES]; 2],
            mix: Smoothed::new(0.5),
            speed: Smoothed::new(0.5),
            depth: Smoothed::new(0.7),
            center: Smoothed::new(1000.0),
            feedback: Smoothed::new(0.5),
            stereo: Smoothed::new(0.5),
            taps,
            active: 4,
            phase: 0.0,
            coef: [0.0; 2],
            last: [0.0; 2],
            primed: false,
        }
    }

    /// Coeficiente TPT do corte de cada canal com o LFO em `self.phase`.
    fn coefs(&self) -> [f32; 2] {
        let sweep = self.depth.value * RANGE_OCTAVES;
        let top = 0.45 * self.rate;
        let at = |offset: f32| {
            let hz = (self.center.value * (sweep * sin_turns(self.phase + offset)).exp2()).clamp(MIN_HZ, top);
            let g = (PI * hz / self.rate).tan();
            g / (1.0 + g)
        };
        // estéreo em 1 = meia volta (180°) entre os LFOs
        [at(0.0), at(0.5 * self.stereo.value)]
    }

    fn prime(&mut self) {
        for p in [&mut self.mix, &mut self.speed, &mut self.depth, &mut self.center, &mut self.feedback, &mut self.stereo] {
            p.snap();
        }
        for t in &mut self.taps {
            t.snap();
        }
        self.coef = self.coefs();
        self.primed = true;
    }
}

impl Effect for Phaser {
    fn set_param(&mut self, id: u32, value: f32) {
        if !value.is_finite() {
            return;
        }
        match id {
            P::MIX => self.mix.set(value.clamp(0.0, 1.0)),
            P::RATE => self.speed.set(value.clamp(0.02, 10.0)),
            P::DEPTH => self.depth.set(value.clamp(0.0, 1.0)),
            P::CENTER => self.center.set(value.clamp(100.0, 8000.0)),
            P::FEEDBACK => self.feedback.set(value.clamp(-0.95, 0.95)),
            P::STAGES => {
                let pick = (value.round().max(0.0) as usize).min(STAGES.len() - 1);
                for (i, t) in self.taps.iter_mut().enumerate() {
                    t.set(if i == pick { 1.0 } else { 0.0 });
                }
            }
            P::STEREO => self.stereo.set(value.clamp(0.0, 1.0)),
            _ => {}
        }
    }

    fn process(&mut self, left: &mut [f32], right: &mut [f32]) {
        let n = left.len().min(right.len());
        if !self.primed {
            self.prime();
        }
        let rate = self.rate;
        let mut done = 0;
        while done < n {
            let len = (n - done).min(CONTROL);
            let a = smoothing(PARAM_TAU, len, rate);
            let mix0 = self.mix.value;
            let mix1 = self.mix.step(a);
            let fb0 = self.feedback.value;
            let fb1 = self.feedback.step(a);
            self.speed.step(a);
            self.depth.step(a);
            // o centro anda em oitavas: suavizar em Hz faria o grave correr e o agudo se arrastar
            let c = self.center.value;
            self.center.value = (c.log2() + (self.center.target.log2() - c.log2()) * a).exp2();
            if (self.center.value - self.center.target).abs() < 1e-3 {
                self.center.snap();
            }
            self.stereo.step(a);
            let at = smoothing(STAGE_TAU, len, rate);
            let mut taps = [Ramp::default(); STAGES.len()];
            let mut used = 0;
            for (k, (t, s)) in taps.iter_mut().zip(self.taps.iter_mut()).enumerate() {
                let from = s.value;
                *t = Ramp::new(from, s.step(at), len);
                if from > 0.0 || s.value > 0.0 {
                    used = k + 1;
                }
            }
            // só roda os estágios até a saída mais funda em uso; um estágio que volta a rodar
            // parte do zero, escondido pelo crossfade que o traz
            let stages = STAGES[used.max(1) - 1];
            if stages > self.active {
                for side in &mut self.state {
                    side[self.active..stages].fill(0.0);
                }
            }
            self.active = stages;
            self.phase = (self.phase + self.speed.value * len as f32 / rate).fract();
            let coef1 = self.coefs();
            let mut coef = [Ramp::new(self.coef[0], coef1[0], len), Ramp::new(self.coef[1], coef1[1], len)];
            self.coef = coef1;
            // com realimentação a saída oscila entre 1/(1 + |g|) e 1/(1 − |g|); √(1 − g²) centra
            // essa faixa em dB, e a realimentação alta não vira só volume
            let comp = |g: f32| (1.0 - g * g).sqrt();
            let mut wet = Ramp::new(mix0 * comp(fb0), mix1 * comp(fb1), len);
            let mut dry = Ramp::new(1.0 - mix0, 1.0 - mix1, len);
            let mut fb = Ramp::new(fb0, fb1, len);

            let block_l = &mut left[done..done + len];
            let block_r = &mut right[done..done + len];
            for (l, r) in block_l.iter_mut().zip(block_r.iter_mut()) {
                let g = fb.next();
                let mut w = [0.0f32; STAGES.len()];
                for (wi, t) in w.iter_mut().zip(taps.iter_mut()) {
                    *wi = t.next();
                }
                let k = wet.next();
                let d = dry.next();
                for (c, x) in [&mut *l, &mut *r].into_iter().enumerate() {
                    let big_g = coef[c].next();
                    let dry_in = *x;
                    let mut y = safety(dry_in + g * self.last[c]);
                    let mut out = 0.0f32;
                    let mut tap = 0;
                    for (s, state) in self.state[c][..stages].iter_mut().enumerate() {
                        let v = (y - *state) * big_g;
                        let lp = v + *state;
                        *state = lp + v;
                        y = 2.0 * lp - y;
                        if s + 1 == STAGES[tap] {
                            out += w[tap] * y;
                            tap += 1;
                        }
                    }
                    self.last[c] = out;
                    *x = dry_in * d + out * k;
                }
            }
            done += len;
        }
        for s in self.state.iter_mut().flatten() {
            if s.abs() < 1e-15 {
                *s = 0.0;
            }
        }
        for v in &mut self.last {
            if v.abs() < 1e-15 {
                *v = 0.0;
            }
        }
        if !self.state.iter().flatten().chain(&self.last).all(|v| v.is_finite()) {
            self.reset();
            left[..n].fill(0.0);
            right[..n].fill(0.0);
        }
    }

    fn reset(&mut self) {
        self.state = [[0.0; MAX_STAGES]; 2];
        self.last = [0.0; 2];
        self.prime();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::fx::delay::peak;

    const RATE: f64 = 48_000.0;

    fn run(p: &mut Phaser, left: &mut [f32], right: &mut [f32]) {
        for (l, r) in left.chunks_mut(128).zip(right.chunks_mut(128)) {
            p.process(l, r);
        }
    }

    fn noise(n: usize, seed: u32) -> Vec<f32> {
        let mut rng = crate::dsp::Rng::new(seed);
        (0..n).map(|_| rng.bipolar() * 0.5).collect()
    }

    /// Ganho estável de uma senoide pelo phaser parado (profundidade 0).
    fn gain_at(freq: f32, stages: f32, feedback: f32) -> f32 {
        let mut p = Phaser::new(RATE);
        p.set_param(P::DEPTH, 0.0);
        p.set_param(P::CENTER, 1000.0);
        p.set_param(P::FEEDBACK, feedback);
        p.set_param(P::STAGES, stages);
        p.set_param(P::MIX, 0.5);
        let n = 48_000;
        let mut l: Vec<f32> = (0..n).map(|i| (i as f32 * freq / 48_000.0 * std::f32::consts::TAU).sin()).collect();
        let mut r = l.clone();
        run(&mut p, &mut l, &mut r);
        l[n / 2..].iter().fold(0.0f32, |m, v| m.max(v.abs()))
    }

    #[test]
    fn quatro_estagios_cavam_vales_no_lugar_certo() {
        // 4 estágios de 1ª ordem com corte fc: −180° em fc·tan(22,5°) e −540° em fc·tan(67,5°)
        // (vales), −360° em fc (em fase: soma inteira)
        let notch1 = 1000.0 * (std::f32::consts::PI / 8.0).tan();
        let notch2 = 1000.0 * (3.0 * std::f32::consts::PI / 8.0).tan();
        assert!(gain_at(notch1, 1.0, 0.0) < 0.02, "{}", gain_at(notch1, 1.0, 0.0));
        assert!(gain_at(notch2, 1.0, 0.0) < 0.02);
        assert!((gain_at(1000.0, 1.0, 0.0) - 1.0).abs() < 0.02);
        // 2 estágios: um vale só, no próprio corte
        assert!(gain_at(1000.0, 0.0, 0.0) < 0.02);
    }

    #[test]
    fn mistura_zero_e_seco() {
        let mut p = Phaser::new(RATE);
        p.set_param(P::MIX, 0.0);
        let src = noise(9_600, 1);
        let mut l = src.clone();
        let mut r = src.clone();
        run(&mut p, &mut l, &mut r);
        assert!(l.iter().zip(&src).all(|(a, b)| a == b));
        assert!(r.iter().zip(&src).all(|(a, b)| a == b));
    }

    #[test]
    fn estereo_defasa_os_canais() {
        let mut p = Phaser::new(RATE);
        p.set_param(P::STEREO, 1.0);
        p.set_param(P::MIX, 1.0);
        let src = noise(48_000, 5);
        let mut l = src.clone();
        let mut r = src;
        run(&mut p, &mut l, &mut r);
        let diff = l.iter().zip(&r).map(|(a, b)| (a - b).abs()).fold(0.0f32, f32::max);
        assert!(diff > 0.05);
    }

    #[test]
    fn trocar_estagios_nao_estala() {
        let mut p = Phaser::new(RATE);
        p.set_param(P::MIX, 1.0);
        p.set_param(P::FEEDBACK, 0.0);
        let n = 48_000;
        let tone = |i: usize| (i as f32 * 200.0 / 48_000.0 * std::f32::consts::TAU).sin() * 0.5;
        let mut l: Vec<f32> = (0..n).map(tone).collect();
        let mut r = l.clone();
        let (mut last, mut worst) = (0.0f32, 0.0f32);
        for (k, (cl, cr)) in l.chunks_mut(128).zip(r.chunks_mut(128)).enumerate() {
            match k {
                100 => p.set_param(P::STAGES, 4.0),
                200 => p.set_param(P::STAGES, 0.0),
                _ => {}
            }
            p.process(cl, cr);
            if k > 20 {
                for &v in cl.iter() {
                    worst = worst.max((v - last).abs());
                    last = v;
                }
            }
            last = cl[127];
        }
        // 200 Hz em 0,5 anda até 0,013 por quadro
        assert!(worst < 0.03, "degrau de {worst}");
    }

    #[test]
    fn extremos_sem_nan() {
        for (fb, stages, center, rate) in [(0.95, 4.0, 8000.0, 10.0), (-0.95, 0.0, 100.0, 10.0), (0.95, 3.0, 100.0, 0.02), (-0.95, 4.0, 8000.0, 0.02)] {
            let mut p = Phaser::new(44_100.0);
            p.set_param(P::MIX, 1.0);
            p.set_param(P::DEPTH, 1.0);
            p.set_param(P::FEEDBACK, fb);
            p.set_param(P::STAGES, stages);
            p.set_param(P::CENTER, center);
            p.set_param(P::RATE, rate);
            let n = 44_100 * 3;
            let mut l = noise(n, 3);
            let mut r = noise(n, 4);
            l[50] = 30.0;
            for v in l[n / 2..].iter_mut().chain(r[n / 2..].iter_mut()) {
                *v = 0.0;
            }
            run(&mut p, &mut l, &mut r);
            assert!(l.iter().chain(&r).all(|v| v.is_finite()));
            assert!(peak(&l, &r) < 20.0);
            assert!(peak(&l[n - 4410..], &r[n - 4410..]) < 1e-3);
        }
        let mut p = Phaser::new(RATE);
        for id in 0..8 {
            p.set_param(id, f32::INFINITY);
            p.set_param(id, -1e30);
        }
        let mut l = noise(4800, 2);
        let mut r = noise(4800, 3);
        run(&mut p, &mut l, &mut r);
        assert!(l.iter().chain(&r).all(|v| v.is_finite()));
    }
}
