//! Utilitário: ganho, balanço, largura estéreo, mono, fase, troca de canais e remoção de DC.
//!
//! Ordem, por quadro: tira o DC, inverte a fase de cada entrada, troca os canais, ajusta a largura
//! (mid/side; mono é largura 0), e por fim balanço e ganho. A inversão vale para o canal de
//! entrada: "inverter esq." com "trocar" ligados inverte o que era a esquerda e o manda para a
//! direita.
//!
//! Nada aqui é discreto no áudio: cada chave liga/desliga um valor suavizado por dois polos (a fase
//! passa de +1 a −1 por zero, a troca é um crossfade da matriz, o mono leva a largura a 0 e o DC
//! mistura a saída do filtro, que roda sempre para não começar com estado velho).

use std::f32::consts::PI;

use super::eq::Glide;
use crate::dsp::smoothing;
use crate::effect::{Effect, utility_param};

/// Constante de tempo de cada polo da suavização (dois em cascata, ver [`Glide`]).
const SMOOTH_SECS: f32 = 0.005;
/// Corte do passa-alta que tira o DC.
const DC_HZ: f32 = 5.0;

pub struct Utility {
    gain: Glide,
    /// Ganho (esq, dir) do balanço: o centro fica em 0 dB e o pan só atenua o lado oposto, como o
    /// balanço do master.
    bal_l: Glide,
    bal_r: Glide,
    width_param: f32,
    mono: bool,
    /// Largura efetiva (0 com mono ligado).
    width: Glide,
    inv_l: Glide,
    inv_r: Glide,
    swap: Glide,
    dc: Glide,
    /// Passa-alta de 1 polo e 1 zero (x₋₁, y₋₁) por canal.
    dc_state: [[f32; 2]; 2],
    dc_pole: f32,
    smooth: f32,
    fresh: bool,
}

impl Utility {
    pub fn new(rate: f64) -> Self {
        let rate = rate as f32;
        Self {
            gain: Glide::new(1.0),
            bal_l: Glide::new(1.0),
            bal_r: Glide::new(1.0),
            width_param: 1.0,
            mono: false,
            width: Glide::new(1.0),
            inv_l: Glide::new(1.0),
            inv_r: Glide::new(1.0),
            swap: Glide::new(0.0),
            dc: Glide::new(0.0),
            dc_state: [[0.0; 2]; 2],
            dc_pole: (-2.0 * PI * DC_HZ / rate).exp(),
            smooth: smoothing(SMOOTH_SECS, 1, rate),
            fresh: true,
        }
    }

    fn snap(&mut self) {
        for s in [&mut self.gain, &mut self.bal_l, &mut self.bal_r, &mut self.width, &mut self.inv_l, &mut self.inv_r, &mut self.swap, &mut self.dc] {
            s.snap();
        }
    }

    fn settled(&self) -> bool {
        [&self.gain, &self.bal_l, &self.bal_r, &self.width, &self.inv_l, &self.inv_r, &self.swap, &self.dc].iter().all(|s| s.settled())
    }
}

impl Effect for Utility {
    fn set_param(&mut self, id: u32, value: f32) {
        if !value.is_finite() {
            return;
        }
        let on = value >= 0.5;
        let sign = |on: bool| if on { -1.0 } else { 1.0 };
        match id {
            utility_param::GAIN => self.gain.set((value.clamp(-48.0, 24.0) * (std::f32::consts::LN_10 / 20.0)).exp()),
            utility_param::PAN => {
                let p = value.clamp(-1.0, 1.0);
                self.bal_l.set(1.0 - p.max(0.0));
                self.bal_r.set(1.0 + p.min(0.0));
            }
            utility_param::WIDTH => self.width_param = value.clamp(0.0, 2.0),
            utility_param::MONO => self.mono = on,
            utility_param::INVERT_L => self.inv_l.set(sign(on)),
            utility_param::INVERT_R => self.inv_r.set(sign(on)),
            utility_param::SWAP => self.swap.set(if on { 1.0 } else { 0.0 }),
            utility_param::DC => self.dc.set(if on { 1.0 } else { 0.0 }),
            _ => return,
        }
        self.width.set(if self.mono { 0.0 } else { self.width_param });
        if self.fresh {
            self.snap();
        }
    }

    fn process(&mut self, left: &mut [f32], right: &mut [f32]) {
        self.fresh = false;
        let a = if self.settled() { 0.0 } else { self.smooth };
        let pole = self.dc_pole;
        let [dl, dr] = &mut self.dc_state;
        for (l, r) in left.iter_mut().zip(right.iter_mut()) {
            let (xl, xr) = (*l, *r);
            // o passa-alta roda sempre: ligar o DC no meio não começa de um estado velho
            let hl = xl - dl[0] + pole * dl[1];
            let hr = xr - dr[0] + pole * dr[1];
            *dl = [xl, hl];
            *dr = [xr, hr];
            let d = self.dc.step(a);
            let mut l1 = xl + d * (hl - xl);
            let mut r1 = xr + d * (hr - xr);
            l1 *= self.inv_l.step(a);
            r1 *= self.inv_r.step(a);
            let s = self.swap.step(a);
            let (l2, r2) = (l1 + s * (r1 - l1), r1 + s * (l1 - r1));
            // mid/side com largura w, na forma que dá bit a bit a entrada em w = 1:
            // L = M + w·S = l·(1 + w)/2 + r·(1 − w)/2
            let w = self.width.step(a);
            let (same, cross) = (0.5 + 0.5 * w, 0.5 - 0.5 * w);
            let g = self.gain.step(a);
            *l = (same * l2 + cross * r2) * g * self.bal_l.step(a);
            *r = (same * r2 + cross * l2) * g * self.bal_r.step(a);
        }
        for s in [dl, dr] {
            for v in s.iter_mut() {
                if v.abs() < 1e-20 || !v.is_finite() {
                    *v = 0.0;
                }
            }
        }
    }

    fn reset(&mut self) {
        self.dc_state = [[0.0; 2]; 2];
        self.snap();
        self.fresh = true;
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::effect::utility_param as p;

    const RATE: f64 = 48_000.0;

    fn signal(n: usize) -> (Vec<f32>, Vec<f32>) {
        (0..n).map(|i| ((i as f32 * 0.031).sin() * 0.6, (i as f32 * 0.017).cos() * 0.3)).unzip()
    }

    /// Processa em blocos e devolve a saída; `settle` quadros antes para a suavização assentar.
    fn run(u: &mut Utility, l: &[f32], r: &[f32]) -> (Vec<f32>, Vec<f32>) {
        let (mut ol, mut or) = (l.to_vec(), r.to_vec());
        for (cl, cr) in ol.chunks_mut(128).zip(or.chunks_mut(128)) {
            u.process(cl, cr);
        }
        (ol, or)
    }

    fn close(a: &[f32], b: &[f32], tol: f32) -> bool {
        a.iter().zip(b).all(|(x, y)| (x - y).abs() <= tol)
    }

    #[test]
    fn padrao_e_transparente() {
        let (l, r) = signal(4096);
        let mut u = Utility::new(RATE);
        let (ol, or) = run(&mut u, &l, &r);
        assert_eq!(ol, l);
        assert_eq!(or, r);
    }

    #[test]
    fn mono_largura_fase_e_troca() {
        let (l, r) = signal(4096);
        let mono: Vec<f32> = l.iter().zip(&r).map(|(a, b)| 0.5 * (a + b)).collect();
        let side: Vec<f32> = l.iter().zip(&r).map(|(a, b)| 0.5 * (a - b)).collect();

        let mut u = Utility::new(RATE);
        u.set_param(p::MONO, 1.0);
        let (ol, or) = run(&mut u, &l, &r);
        assert!(close(&ol, &mono, 1e-6) && close(&or, &mono, 1e-6));

        let mut u = Utility::new(RATE);
        u.set_param(p::WIDTH, 0.0);
        let (ol, _) = run(&mut u, &l, &r);
        assert!(close(&ol, &mono, 1e-6));

        let mut u = Utility::new(RATE);
        u.set_param(p::WIDTH, 2.0);
        let (ol, or) = run(&mut u, &l, &r);
        let wide_l: Vec<f32> = mono.iter().zip(&side).map(|(m, s)| m + 2.0 * s).collect();
        let wide_r: Vec<f32> = mono.iter().zip(&side).map(|(m, s)| m - 2.0 * s).collect();
        assert!(close(&ol, &wide_l, 1e-6) && close(&or, &wide_r, 1e-6));

        let mut u = Utility::new(RATE);
        u.set_param(p::INVERT_L, 1.0);
        let (ol, or) = run(&mut u, &l, &r);
        let neg: Vec<f32> = l.iter().map(|v| -v).collect();
        assert!(close(&ol, &neg, 1e-6) && close(&or, &r, 1e-6));

        let mut u = Utility::new(RATE);
        u.set_param(p::INVERT_R, 1.0);
        u.set_param(p::SWAP, 1.0);
        let (ol, or) = run(&mut u, &l, &r);
        let neg_r: Vec<f32> = r.iter().map(|v| -v).collect();
        assert!(close(&ol, &neg_r, 1e-6) && close(&or, &l, 1e-6));
    }

    #[test]
    fn balanco_e_ganho() {
        let (l, r) = signal(4096);
        let mut u = Utility::new(RATE);
        u.set_param(p::PAN, 0.5);
        u.set_param(p::GAIN, -6.0);
        let (ol, or) = run(&mut u, &l, &r);
        let g = 10f32.powf(-6.0 / 20.0);
        let want_l: Vec<f32> = l.iter().map(|v| v * 0.5 * g).collect();
        let want_r: Vec<f32> = r.iter().map(|v| v * g).collect();
        assert!(close(&ol, &want_l, 1e-6) && close(&or, &want_r, 1e-6));
    }

    #[test]
    fn tira_o_dc() {
        let mut u = Utility::new(RATE);
        u.set_param(p::DC, 1.0);
        let n = 48_000;
        let l: Vec<f32> = (0..n).map(|i| 0.3 + 0.2 * (i as f32 * 0.1).sin()).collect();
        let r = vec![-0.5; n];
        let (ol, or) = run(&mut u, &l, &r);
        // 5 Hz: constante de tempo de 32 ms; depois de 1 s o DC sumiu e a senoide (764 Hz) passa
        let tail = &ol[40_000..];
        let mean = tail.iter().sum::<f32>() / tail.len() as f32;
        assert!(mean.abs() < 1e-3, "{mean}");
        let peak = tail.iter().fold(0.0f32, |m, v| m.max(v.abs()));
        assert!((peak - 0.2).abs() < 0.005, "{peak}");
        assert!(or[40_000..].iter().all(|v| v.abs() < 1e-4));
    }

    #[test]
    fn chaves_nao_estalam() {
        let n = 48_000;
        let (l, r): (Vec<f32>, Vec<f32>) = (0..n).map(|i| ((i as f32 * 0.02).sin() * 0.5, (i as f32 * 0.02).sin() * 0.5 + 0.2)).unzip();
        let (mut ol, mut or) = (l.clone(), r.clone());
        let mut u = Utility::new(RATE);
        for (i, (cl, cr)) in ol.chunks_mut(128).zip(or.chunks_mut(128)).enumerate() {
            match i {
                20 => u.set_param(p::INVERT_L, 1.0),
                40 => u.set_param(p::SWAP, 1.0),
                60 => u.set_param(p::MONO, 1.0),
                80 => u.set_param(p::DC, 1.0),
                100 => u.set_param(p::GAIN, -48.0),
                120 => u.set_param(p::GAIN, 24.0),
                140 => u.set_param(p::PAN, -1.0),
                _ => {}
            }
            u.process(cl, cr);
            if i == 119 {
                break;
            }
        }
        // a senoide anda no máximo 0,01 por quadro; cada chave vira uma rampa de ~10 ms
        let step = |x: &[f32]| x[..120 * 128].windows(2).fold(0.0f32, |m, w| m.max((w[1] - w[0]).abs()));
        assert!(step(&ol) < 0.02, "{}", step(&ol));
        assert!(step(&or) < 0.02, "{}", step(&or));
    }

    #[test]
    fn extremos_sem_nan() {
        let mut u = Utility::new(8_000.0);
        for id in 0..10 {
            u.set_param(id, 1e9);
            u.set_param(id, -1e9);
            u.set_param(id, f32::NAN);
        }
        let (mut l, mut r) = (vec![1e30; 256], vec![f32::MAX; 256]);
        l[3] = f32::NAN;
        u.process(&mut l, &mut r);
        let (mut l, mut r) = (vec![0.1; 256], vec![0.1; 256]);
        u.process(&mut l, &mut r);
        assert!(l.iter().chain(&r).all(|v| v.is_finite()));
        assert!(u.dc_state.iter().flatten().all(|v| v.is_finite()));
    }
}
