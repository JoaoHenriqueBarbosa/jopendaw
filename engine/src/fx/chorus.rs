//! Chorus e flanger: 1 a 4 vozes por canal lendo a mesma linha de atraso em posições que um LFO
//! senoidal balança, cada voz com a sua fase.
//!
//! Atraso base longo (10–30 ms) e realimentação zero dão o chorus; base curta (1–5 ms) com
//! realimentação dá o flanger, com os picos do filtro-pente. A leitura fracionária é por Hermite
//! (plana no agudo, sem o abafamento da linear). A largura defasa os LFOs da direita em relação
//! aos da esquerda: em 1 as vozes de um lado caem no meio das do outro.
//!
//! Trocar o número de vozes não estala: as vozes entram e saem num fade e as fases deslizam até a
//! distribuição nova.

use crate::dsp::{Smoothed, sin_turns, smoothing};
use crate::effect::{Effect, chorus_param as P};
use crate::fx::delay::{DelayLine, Ramp, equal_power, flush, safety};

const CONTROL: usize = 16;
const VOICES: usize = 4;
const MAX_DELAY_SECS: f32 = 0.03;
const MIN_DELAY_SECS: f32 = 0.001;
/// Excursão máxima do LFO. Nunca passa de 90% do atraso base: a leitura não cruza a escrita.
const MAX_SWEEP_SECS: f32 = 0.004;
const PARAM_TAU: f32 = 0.02;
/// Fade de entrada e saída de uma voz.
const VOICE_TAU: f32 = 0.03;
/// Deslize das fases quando muda o número de vozes ou a largura.
const SPREAD_TAU: f32 = 0.15;

pub struct Chorus {
    rate: f32,
    lines: [DelayLine; 2],
    mix: Smoothed,
    speed: Smoothed,
    depth: Smoothed,
    delay: Smoothed,
    feedback: Smoothed,
    width: f32,
    voices: usize,
    gain: [Smoothed; VOICES],
    /// Fase de cada voz em relação ao LFO, em voltas.
    spread: [Smoothed; VOICES],
    /// Defasagem da direita, em voltas.
    stereo: Smoothed,
    phase: f32,
    /// Posição de leitura de cada voz no fim do bloco anterior (canal, voz).
    pos: [[f32; VOICES]; 2],
    /// Ganho de cada voz e as normalizações de saída e de realimentação no fim do bloco anterior.
    mixdown: Mixdown,
    /// Soma das vozes no último quadro (sem normalizar), para a realimentação.
    last: (f32, f32),
    primed: bool,
}

impl Chorus {
    pub fn new(rate: f64) -> Self {
        let rate = rate as f32;
        let len = ((MAX_DELAY_SECS + MAX_SWEEP_SECS) * rate).ceil() as usize + 8;
        let mut c = Self {
            rate,
            lines: [DelayLine::new(len), DelayLine::new(len)],
            mix: Smoothed::new(0.5),
            speed: Smoothed::new(0.8),
            depth: Smoothed::new(0.5),
            delay: Smoothed::new(0.012),
            feedback: Smoothed::new(0.0),
            width: 1.0,
            voices: 2,
            gain: [Smoothed::new(0.0); VOICES],
            spread: [Smoothed::new(0.0); VOICES],
            stereo: Smoothed::new(0.0),
            phase: 0.0,
            pos: [[0.0; VOICES]; 2],
            mixdown: Mixdown::default(),
            last: (0.0, 0.0),
            primed: false,
        };
        c.retarget();
        c
    }

    /// Alvos de ganho e fase das vozes para o número de vozes e a largura atuais.
    fn retarget(&mut self) {
        let n = self.voices as f32;
        for v in 0..VOICES {
            self.gain[v].set(if v < self.voices { 1.0 } else { 0.0 });
            // vozes que saem mantêm a fase: só somem
            if v < self.voices {
                self.spread[v].set(v as f32 / n);
            }
        }
        self.stereo.set(self.width * 0.5 / n);
    }

    fn prime(&mut self) {
        for p in [&mut self.mix, &mut self.speed, &mut self.depth, &mut self.delay, &mut self.feedback, &mut self.stereo] {
            p.snap();
        }
        for v in 0..VOICES {
            self.gain[v].snap();
            self.spread[v].snap();
        }
        (self.pos, self.mixdown) = self.positions();
        self.primed = true;
    }

    /// Posições de leitura (quadros) das vozes com o LFO em `self.phase`, e a mistura delas.
    fn positions(&self) -> ([[f32; VOICES]; 2], Mixdown) {
        let base = self.delay.value * self.rate;
        let sweep = self.depth.value * (0.9 * base).min(MAX_SWEEP_SECS * self.rate);
        let mut pos = [[0.0; VOICES]; 2];
        let mut mix = Mixdown::default();
        let (mut sum, mut energy) = (0.0f32, 0.0f32);
        for (v, (gain, spread)) in self.gain.iter().zip(&self.spread).enumerate() {
            let g = gain.value;
            let p = self.phase + spread.value;
            pos[0][v] = base + sweep * sin_turns(p);
            pos[1][v] = base + sweep * sin_turns(p + self.stereo.value);
            mix.gain[v] = g;
            sum += g;
            energy += g * g;
        }
        // saída com potência constante (as vozes se descorrelacionam); realimentação pela média,
        // para a malha nunca passar do ganho pedido mesmo onde as vozes somam em fase
        mix.out = if energy > 0.0 { 1.0 / energy.sqrt() } else { 0.0 };
        mix.feedback = if sum > 0.0 { 1.0 / sum } else { 0.0 };
        (pos, mix)
    }
}

#[derive(Clone, Copy, Debug, Default)]
struct Mixdown {
    gain: [f32; VOICES],
    out: f32,
    feedback: f32,
}

impl Effect for Chorus {
    fn set_param(&mut self, id: u32, value: f32) {
        if !value.is_finite() {
            return;
        }
        match id {
            P::MIX => self.mix.set(value.clamp(0.0, 1.0)),
            P::RATE => self.speed.set(value.clamp(0.02, 10.0)),
            P::DEPTH => self.depth.set(value.clamp(0.0, 1.0)),
            P::DELAY => self.delay.set(value.clamp(MIN_DELAY_SECS, MAX_DELAY_SECS)),
            P::VOICES => {
                self.voices = (value.round() as i32).clamp(1, VOICES as i32) as usize;
                self.retarget();
            }
            P::FEEDBACK => self.feedback.set(value.clamp(-0.95, 0.95)),
            P::WIDTH => {
                self.width = value.clamp(0.0, 1.0);
                self.retarget();
            }
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
            let (dry0, wet0) = equal_power(self.mix.value);
            let (dry1, wet1) = equal_power(self.mix.step(a));
            let fb0 = self.feedback.value;
            let fb1 = self.feedback.step(a);
            self.speed.step(a);
            self.depth.step(a);
            self.delay.step(a);
            let av = smoothing(VOICE_TAU, len, rate);
            let asp = smoothing(SPREAD_TAU, len, rate);
            for v in 0..VOICES {
                self.gain[v].step(av);
                self.spread[v].step(asp);
            }
            self.stereo.step(asp);
            self.phase = (self.phase + self.speed.value * len as f32 / rate).fract();
            let (pos1, mix1) = self.positions();

            let mut pos = [[Ramp::default(); VOICES]; 2];
            let mut gain = [Ramp::default(); VOICES];
            let mut active = [false; VOICES];
            for v in 0..VOICES {
                active[v] = self.mixdown.gain[v] > 0.0 || mix1.gain[v] > 0.0;
                gain[v] = Ramp::new(self.mixdown.gain[v], mix1.gain[v], len);
                for c in 0..2 {
                    pos[c][v] = Ramp::new(self.pos[c][v], pos1[c][v], len);
                }
            }
            // com realimentação o pente ressoa até 1/(1 − |g|); √(1 − g²) centra essa faixa em dB
            let comp = |g: f32| (1.0 - g * g).sqrt();
            let mut out = Ramp::new(self.mixdown.out * wet0 * comp(fb0), mix1.out * wet1 * comp(fb1), len);
            let mut fb = Ramp::new(self.mixdown.feedback * fb0, mix1.feedback * fb1, len);
            let mut dry = Ramp::new(dry0, dry1, len);
            self.pos = pos1;
            self.mixdown = mix1;

            let block_l = &mut left[done..done + len];
            let block_r = &mut right[done..done + len];
            for (l, r) in block_l.iter_mut().zip(block_r.iter_mut()) {
                let (xl, xr) = (*l, *r);
                let (sl, sr) = self.last;
                let g = fb.next();
                self.lines[0].write(flush(safety(xl + g * sl)));
                self.lines[1].write(flush(safety(xr + g * sr)));
                let (mut wl, mut wr) = (0.0f32, 0.0f32);
                for v in 0..VOICES {
                    let w = gain[v].next();
                    let (pl, pr) = (pos[0][v].next(), pos[1][v].next());
                    if active[v] {
                        wl += w * self.lines[0].hermite(pl);
                        wr += w * self.lines[1].hermite(pr);
                    }
                }
                self.last = (wl, wr);
                let k = out.next();
                let d = dry.next();
                *l = xl * d + wl * k;
                *r = xr * d + wr * k;
            }
            done += len;
        }
        if !(self.last.0.is_finite() && self.last.1.is_finite()) {
            self.reset();
            left[..n].fill(0.0);
            right[..n].fill(0.0);
        }
    }

    fn reset(&mut self) {
        for line in &mut self.lines {
            line.clear();
        }
        self.last = (0.0, 0.0);
        self.prime();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::fx::delay::peak;

    const RATE: f64 = 48_000.0;

    fn noise(n: usize, seed: u32) -> Vec<f32> {
        let mut rng = crate::dsp::Rng::new(seed);
        (0..n).map(|_| rng.bipolar() * 0.5).collect()
    }

    fn run(c: &mut Chorus, left: &mut [f32], right: &mut [f32]) {
        for (l, r) in left.chunks_mut(128).zip(right.chunks_mut(128)) {
            c.process(l, r);
        }
    }

    #[test]
    fn mistura_zero_e_seco() {
        let mut c = Chorus::new(RATE);
        c.set_param(P::MIX, 0.0);
        c.set_param(P::FEEDBACK, 0.9);
        let src = noise(9_600, 1);
        let mut l = src.clone();
        let mut r = src.clone();
        run(&mut c, &mut l, &mut r);
        assert!(l.iter().zip(&src).all(|(a, b)| a == b));
        assert!(r.iter().zip(&src).all(|(a, b)| a == b));
    }

    #[test]
    fn modula_o_atraso() {
        // uma voz, mistura toda molhada: a senoide sai com a afinação balançando (vibrato), então
        // a distância entre cruzamentos por zero varia
        let mut c = Chorus::new(RATE);
        c.set_param(P::MIX, 1.0);
        c.set_param(P::VOICES, 1.0);
        c.set_param(P::RATE, 2.0);
        c.set_param(P::DEPTH, 1.0);
        let n = 48_000;
        let mut l: Vec<f32> = (0..n).map(|i| (i as f32 * 1000.0 / 48_000.0 * std::f32::consts::TAU).sin()).collect();
        let mut r = l.clone();
        run(&mut c, &mut l, &mut r);
        let crossings: Vec<usize> = (4800..n).filter(|&i| l[i - 1] < 0.0 && l[i] >= 0.0).collect();
        let periods: Vec<usize> = crossings.windows(2).map(|w| w[1] - w[0]).collect();
        let (lo, hi) = (periods.iter().min().unwrap(), periods.iter().max().unwrap());
        assert!(hi - lo >= 1, "período fixo em {lo}");
        // e o nível se mantém (Hermite, uma voz)
        let rms = (l[4800..].iter().map(|v| v * v).sum::<f32>() / (n - 4800) as f32).sqrt();
        assert!((rms - std::f32::consts::FRAC_1_SQRT_2).abs() < 0.02, "rms {rms}");
    }

    #[test]
    fn largura_separa_os_canais() {
        let render = |width: f32| {
            let mut c = Chorus::new(RATE);
            c.set_param(P::MIX, 1.0);
            c.set_param(P::WIDTH, width);
            let n = 48_000;
            let src = noise(n, 4);
            let mut l = src.clone();
            let mut r = src;
            run(&mut c, &mut l, &mut r);
            l[4800..].iter().zip(&r[4800..]).map(|(a, b)| (a - b).abs()).fold(0.0f32, f32::max)
        };
        assert!(render(0.0) < 1e-6);
        assert!(render(1.0) > 0.05);
    }

    #[test]
    fn trocar_vozes_nao_estala() {
        let mut c = Chorus::new(RATE);
        c.set_param(P::MIX, 1.0);
        let n = 48_000;
        let tone = |i: usize| (i as f32 * 300.0 / 48_000.0 * std::f32::consts::TAU).sin() * 0.5;
        let mut l: Vec<f32> = (0..n).map(tone).collect();
        let mut r = l.clone();
        let mut last = 0.0f32;
        let mut worst = 0.0f32;
        for (k, (cl, cr)) in l.chunks_mut(128).zip(r.chunks_mut(128)).enumerate() {
            match k {
                100 => c.set_param(P::VOICES, 4.0),
                200 => c.set_param(P::VOICES, 1.0),
                300 => c.set_param(P::VOICES, 3.0),
                _ => {}
            }
            c.process(cl, cr);
            if k > 50 {
                for &v in cl.iter() {
                    worst = worst.max((v - last).abs());
                    last = v;
                }
            }
            last = cl[127];
        }
        // 300 Hz em 0,5 anda até 0,02 por quadro; somas de vozes de até ~1,4 vezes isso
        assert!(worst < 0.06, "degrau de {worst}");
    }

    #[test]
    fn extremos_sem_nan() {
        for (delay, fb, voices) in [(0.001, 0.95, 4.0), (0.001, -0.95, 1.0), (0.03, 0.95, 3.0), (0.002, -0.95, 4.0)] {
            let mut c = Chorus::new(44_100.0);
            c.set_param(P::MIX, 1.0);
            c.set_param(P::RATE, 10.0);
            c.set_param(P::DEPTH, 1.0);
            c.set_param(P::DELAY, delay);
            c.set_param(P::FEEDBACK, fb);
            c.set_param(P::VOICES, voices);
            let n = 44_100 * 4;
            let mut l = noise(n, 7);
            let mut r = noise(n, 8);
            l[100] = 30.0;
            for v in l[n / 2..].iter_mut().chain(r[n / 2..].iter_mut()) {
                *v = 0.0;
            }
            run(&mut c, &mut l, &mut r);
            assert!(l.iter().chain(&r).all(|v| v.is_finite()));
            assert!(peak(&l, &r) < 20.0);
            // a realimentação morre depois que a entrada para
            assert!(peak(&l[n - 4410..], &r[n - 4410..]) < 1e-3);
        }
        let mut c = Chorus::new(RATE);
        for id in 0..8 {
            c.set_param(id, f32::NAN);
            c.set_param(id, 1e30);
        }
        let mut l = noise(4800, 2);
        let mut r = noise(4800, 3);
        run(&mut c, &mut l, &mut r);
        assert!(l.iter().chain(&r).all(|v| v.is_finite()));
    }
}
