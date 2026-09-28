//! Tremolo e autopan: o volume de cada canal segue um LFO (senoide, triângulo ou quadrada), livre
//! em Hz ou no andamento (figura rítmica). Com a defasagem estéreo em 0,5 os canais andam em
//! oposição e o som passeia de um lado para o outro.
//!
//! A quadrada tem bordas de 3 ms em forma de meia senoide: corta o som como um chopper, sem
//! clique. Trocar de onda é um crossfade de 20 ms entre as formas; mudar a velocidade mantém a
//! fase, então nada salta.

use crate::dsp::{Smoothed, sin_turns, smoothing};
use crate::effect::{Effect, NOTE_BEATS, tremolo_param as P};
use crate::fx::delay::Ramp;

const CONTROL: usize = 32;
const PARAM_TAU: f32 = 0.02;
/// Crossfade entre formas de onda.
const WAVE_TAU: f32 = 0.02;
/// Duração das bordas da quadrada.
const EDGE_SECS: f32 = 0.003;
const WAVES: usize = 3;

pub struct Tremolo {
    rate: f32,
    hz: f32,
    depth: Smoothed,
    stereo: Smoothed,
    /// Peso de cada forma de onda (senoide, triângulo, quadrada).
    wave: [Smoothed; WAVES],
    sync: bool,
    note: usize,
    bpm: f64,
    /// Fase em voltas. Em f64: no andamento, o erro de uma f32 somaria um desvio audível em minutos.
    phase: f64,
    primed: bool,
}

impl Tremolo {
    pub fn new(rate: f64) -> Self {
        let mut wave = [Smoothed::new(0.0); WAVES];
        wave[0] = Smoothed::new(1.0);
        Self {
            rate: rate as f32,
            hz: 4.0,
            depth: Smoothed::new(0.5),
            stereo: Smoothed::new(0.0),
            wave,
            sync: false,
            note: 5,
            bpm: 120.0,
            phase: 0.0,
            primed: false,
        }
    }

    /// Frequência do LFO em Hz.
    fn frequency(&self) -> f32 {
        if self.sync { (self.bpm / 60.0 / NOTE_BEATS[self.note]) as f32 } else { self.hz }
    }
}

/// Forma bipolar (−1..1) numa fase em voltas, com os pesos das ondas. Todas começam no zero
/// subindo, como o LFO dos instrumentos.
#[inline]
fn shape(p: f32, weights: &[f32; WAVES], steep: f32) -> f32 {
    let s = sin_turns(p);
    let mut out = weights[0] * s;
    if weights[1] > 0.0 {
        let q = p + 0.25;
        out += weights[1] * (1.0 - 4.0 * (q - q.floor() - 0.5).abs());
    }
    if weights[2] > 0.0 {
        // quadrada suave: a senoide esticada e cortada, com as quinas arredondadas por outra meia
        // senoide; a transição dura EDGE_SECS em qualquer velocidade (até virar quase senoide)
        let c = (steep * s).clamp(-1.0, 1.0);
        out += weights[2] * sin_turns(0.25 * c);
    }
    out
}

impl Effect for Tremolo {
    fn set_param(&mut self, id: u32, value: f32) {
        if !value.is_finite() {
            return;
        }
        match id {
            P::RATE => self.hz = value.clamp(0.05, 20.0),
            P::DEPTH => self.depth.set(value.clamp(0.0, 1.0)),
            P::WAVE => {
                let pick = (value.round().max(0.0) as usize).min(WAVES - 1);
                for (i, w) in self.wave.iter_mut().enumerate() {
                    w.set(if i == pick { 1.0 } else { 0.0 });
                }
            }
            P::STEREO => self.stereo.set(value.clamp(0.0, 1.0)),
            P::SYNC => self.sync = value >= 0.5,
            P::NOTE => self.note = (value.round().max(0.0) as usize).min(NOTE_BEATS.len() - 1),
            _ => {}
        }
    }

    fn set_tempo(&mut self, bpm: f64) {
        if bpm.is_finite() && bpm > 0.0 {
            self.bpm = bpm.clamp(10.0, 1000.0);
        }
    }

    fn process(&mut self, left: &mut [f32], right: &mut [f32]) {
        let n = left.len().min(right.len());
        if !self.primed {
            self.depth.snap();
            self.stereo.snap();
            for w in &mut self.wave {
                w.snap();
            }
            self.primed = true;
        }
        let rate = self.rate;
        let mut done = 0;
        while done < n {
            let len = (n - done).min(CONTROL);
            let a = smoothing(PARAM_TAU, len, rate);
            let mut depth = Ramp::new(self.depth.value, self.depth.step(a), len);
            let mut stereo = Ramp::new(self.stereo.value, self.stereo.step(a), len);
            let aw = smoothing(WAVE_TAU, len, rate);
            let mut wave = [Ramp::default(); WAVES];
            for (r, w) in wave.iter_mut().zip(self.wave.iter_mut()) {
                *r = Ramp::new(w.value, w.step(aw), len);
            }
            let hz = self.frequency().min(0.45 * rate);
            let inc = hz as f64 / rate as f64;
            // inclinação da quadrada: a senoide cruza de −1/k a 1/k em EDGE_SECS
            let steep = (1.0 / (std::f32::consts::PI * hz * EDGE_SECS)).max(1.0);

            let block_l = &mut left[done..done + len];
            let block_r = &mut right[done..done + len];
            for (l, r) in block_l.iter_mut().zip(block_r.iter_mut()) {
                let weights = [wave[0].next(), wave[1].next(), wave[2].next()];
                let p = self.phase as f32;
                let d = depth.next();
                let off = stereo.next();
                // ganho = 1 − d·(1 − u), com u = (1 + forma)/2: no vale com profundidade 1, zero
                let gain = |p: f32| 1.0 - d * 0.5 * (1.0 - shape(p, &weights, steep));
                *l *= gain(p);
                *r *= gain(p + off);
                self.phase += inc;
                if self.phase >= 1.0 {
                    self.phase -= 1.0;
                }
            }
            done += len;
        }
    }

    fn reset(&mut self) {
        self.phase = 0.0;
        self.primed = false;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const RATE: f64 = 48_000.0;

    fn gains(t: &mut Tremolo, n: usize) -> (Vec<f32>, Vec<f32>) {
        let mut l = vec![1.0; n];
        let mut r = vec![1.0; n];
        for (cl, cr) in l.chunks_mut(128).zip(r.chunks_mut(128)) {
            t.process(cl, cr);
        }
        (l, r)
    }

    #[test]
    fn profundidade_total_zera_no_vale() {
        for wave in 0..3 {
            let mut t = Tremolo::new(RATE);
            t.set_param(P::DEPTH, 1.0);
            t.set_param(P::WAVE, wave as f32);
            t.set_param(P::RATE, 4.0);
            let (l, _) = gains(&mut t, 48_000);
            let lo = l.iter().cloned().fold(f32::MAX, f32::min);
            let hi = l.iter().cloned().fold(f32::MIN, f32::max);
            assert!(lo < 1e-3, "onda {wave}: vale {lo}");
            assert!(hi > 0.999, "onda {wave}: pico {hi}");
        }
    }

    #[test]
    fn quadrada_nao_estala() {
        let mut t = Tremolo::new(RATE);
        t.set_param(P::DEPTH, 1.0);
        t.set_param(P::WAVE, 2.0);
        for hz in [0.05, 4.0, 20.0] {
            t.set_param(P::RATE, hz);
            let (l, _) = gains(&mut t, 96_000);
            let worst = l.windows(2).map(|w| (w[1] - w[0]).abs()).fold(0.0f32, f32::max);
            // borda de 3 ms em meia senoide: no máximo π/2 por borda, ~0,011 por quadro
            assert!(worst < 0.02, "{hz} Hz: degrau de {worst}");
            // e é quadrada de verdade: metade do tempo aberta, metade fechada
            let open = l.iter().filter(|&&g| g > 0.99).count() as f32 / l.len() as f32;
            if (4.0..10.0).contains(&hz) {
                assert!((open - 0.5).abs() < 0.05, "aberta {open}");
            }
        }
    }

    #[test]
    fn trocar_de_onda_nao_estala() {
        let mut t = Tremolo::new(RATE);
        t.set_param(P::DEPTH, 1.0);
        let mut l = vec![1.0; 48_000];
        let mut r = vec![1.0; 48_000];
        for (k, (cl, cr)) in l.chunks_mut(128).zip(r.chunks_mut(128)).enumerate() {
            match k {
                50 => t.set_param(P::WAVE, 2.0),
                120 => t.set_param(P::WAVE, 1.0),
                200 => t.set_param(P::STEREO, 0.5),
                _ => {}
            }
            t.process(cl, cr);
        }
        let worst = l.windows(2).chain(r.windows(2)).map(|w| (w[1] - w[0]).abs()).fold(0.0f32, f32::max);
        assert!(worst < 0.02, "degrau de {worst}");
    }

    #[test]
    fn sincronizado_segue_o_andamento() {
        let mut t = Tremolo::new(RATE);
        t.set_param(P::DEPTH, 1.0);
        t.set_param(P::SYNC, 1.0);
        t.set_param(P::NOTE, 8.0); // 1/4
        t.set_tempo(120.0);
        let (l, _) = gains(&mut t, 48_000 * 2);
        // senoide de 2 Hz: vales a cada 24 000 quadros
        // (o fundo é chato no arredondamento da f32: conta só o início de cada vale)
        let valleys: Vec<usize> = (1..l.len()).filter(|&i| l[i] < 1e-3 && l[i - 1] >= 1e-3).collect();
        assert!(valleys.len() >= 3, "{valleys:?}");
        for w in valleys.windows(2) {
            assert!((w[1] as i64 - w[0] as i64 - 24_000).abs() <= 2, "{valleys:?}");
        }
    }

    #[test]
    fn autopan_soma_constante() {
        let mut t = Tremolo::new(RATE);
        t.set_param(P::DEPTH, 1.0);
        t.set_param(P::STEREO, 0.5);
        let (l, r) = gains(&mut t, 48_000);
        assert!(l.iter().zip(&r).all(|(a, b)| (a + b - 1.0).abs() < 1e-4));
    }

    #[test]
    fn profundidade_zero_passa_intacto() {
        let mut t = Tremolo::new(RATE);
        t.set_param(P::DEPTH, 0.0);
        let (l, r) = gains(&mut t, 4_800);
        assert!(l.iter().chain(&r).all(|&g| g == 1.0));
    }
}
