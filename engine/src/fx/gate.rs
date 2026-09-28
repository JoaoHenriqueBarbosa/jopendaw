//! Gate (portão de ruído) com histerese, retenção e alcance.
//!
//! A chave (a própria entrada ou a de sidechain, com passa-alta opcional) passa por um detector de
//! pico com ataque instantâneo e decaimento curto, que ignora os cruzamentos por zero de cada ciclo.
//! O portão abre quando o pico passa do limiar e só fecha quando cai [`HYSTERESIS_DB`] abaixo dele
//! e a retenção acabou: sem essa folga, um som que decai em cima do limiar faz o portão tremular.
//! Tudo é comparado em amplitude linear (os limiares são convertidos quando mudam), então não há
//! log por quadro.
//!
//! O ganho abre numa curva em S (smoothstep) do valor atual até 1 no tempo de ataque: um polo que
//! chegasse lá no mesmo tempo sairia 7 vezes mais íngreme, e mesmo a rampa linear dos gates
//! clássicos começa com uma quina; a curva em S começa e termina parada. Fecha por dois polos em
//! cascata que chegam a 99,9% do caminho no tempo de soltura: em amplitude linear isso desce quase
//! em linha reta em dB, como uma soltura de gate soa natural, sem a quina de um polo só no começo.

use std::f32::consts::SQRT_2;

use super::eq::Glide;
use crate::dsp::{FilterMode, Svf, smoothing};
use crate::effect::{Effect, gate_param};

/// Quanto abaixo do limiar o portão fecha, em dB.
pub const HYSTERESIS_DB: f32 = 4.0;
/// Constante de tempo do decaimento do detector: cobre o meio ciclo de um grave (~60 Hz) sem
/// segurar demais o fechamento.
const DETECTOR_SECS: f32 = 0.008;

fn db_to_amp(db: f32) -> f32 {
    (db * (std::f32::consts::LN_10 / 20.0)).exp()
}

/// Fração por quadro de cada um dos dois polos da soltura, para chegarem juntos a 99,9% do
/// caminho em `secs` ((1 + t/τ)·e^(−t/τ) = 0,001 em t ≈ 9,23τ): "soltura de 100 ms" fecha em
/// 100 ms, não numa constante de tempo.
fn release_coef(secs: f32, rate: f32) -> f32 {
    smoothing(secs / 9.23, 1, rate)
}

#[inline]
fn s_curve(t: f32) -> f32 {
    t * t * (3.0 - 2.0 * t)
}

pub struct Gate {
    rate: f32,
    open_at: f32,
    close_at: f32,
    /// Quanto a fase da abertura anda por quadro (1 / quadros de ataque).
    attack: f32,
    release: f32,
    hold_frames: u32,
    floor: f32,
    sc_hpf: [Svf; 2],
    detector_decay: f32,
    env: f32,
    open: bool,
    hold: u32,
    gain: f32,
    /// Abrindo: fase 0..1 da curva em S e o ganho de onde ela partiu.
    opening: bool,
    phase: f32,
    from: f32,
    /// Fechando (ou seguindo o piso): os dois polos, sempre alinhados ao ganho atual fora disso.
    closing: Glide,
    meter: f32,
}

impl Gate {
    pub fn new(rate: f64) -> Self {
        let rate = rate as f32;
        let mut g = Self {
            rate,
            open_at: 0.0,
            close_at: 0.0,
            attack: 1.0 / (0.0005 * rate),
            release: release_coef(0.1, rate),
            hold_frames: (0.02 * rate) as u32,
            floor: db_to_amp(-80.0),
            sc_hpf: [Svf::default(); 2],
            detector_decay: (-1.0 / (DETECTOR_SECS * rate)).exp(),
            env: 0.0,
            open: false,
            hold: 0,
            gain: 0.0,
            opening: false,
            phase: 0.0,
            from: 0.0,
            closing: Glide::new(0.0),
            meter: 0.0,
        };
        g.set_threshold(-50.0);
        g.set_sc_hpf(20.0);
        g.settle_closed();
        g
    }

    /// Fechado no piso, parado (criação e reset).
    fn settle_closed(&mut self) {
        self.gain = self.floor;
        self.opening = false;
        self.closing.set(self.floor);
        self.closing.snap();
    }

    fn set_threshold(&mut self, db: f32) {
        self.open_at = db_to_amp(db);
        self.close_at = db_to_amp(db - HYSTERESIS_DB);
    }

    fn set_sc_hpf(&mut self, freq: f32) {
        let g = Svf::g(freq.min(0.45 * self.rate), self.rate);
        for f in &mut self.sc_hpf {
            f.set(g, SQRT_2);
        }
    }
}

impl Effect for Gate {
    fn set_param(&mut self, id: u32, value: f32) {
        if !value.is_finite() {
            return;
        }
        match id {
            gate_param::THRESHOLD => self.set_threshold(value.clamp(-80.0, 0.0)),
            gate_param::ATTACK => self.attack = 1.0 / (value.clamp(0.0001, 0.1) * self.rate).max(1.0),
            gate_param::HOLD => self.hold_frames = (value.clamp(0.0, 1.0) * self.rate) as u32,
            gate_param::RELEASE => self.release = release_coef(value.clamp(0.005, 2.0), self.rate),
            // fechado, o ganho persegue o piso novo pelos polos da soltura: mudar o alcance com o
            // portão fechado não dá degrau
            gate_param::RANGE => self.floor = db_to_amp(value.clamp(-80.0, 0.0)),
            gate_param::SC_HPF => self.set_sc_hpf(value.clamp(20.0, 2000.0)),
            // SIDECHAIN: o motor escolhe a chave e entrega em `process_keyed`
            _ => {}
        }
    }

    fn process(&mut self, left: &mut [f32], right: &mut [f32]) {
        self.process_keyed(left, right, None);
    }

    fn process_keyed(&mut self, left: &mut [f32], right: &mut [f32], key: Option<(&[f32], &[f32])>) {
        let mut min_gain = 1.0f32;
        for (i, (l, r)) in left.iter_mut().zip(right.iter_mut()).enumerate() {
            let (kl, kr) = match key {
                Some((kl, kr)) => (kl.get(i).copied().unwrap_or(0.0), kr.get(i).copied().unwrap_or(0.0)),
                None => (*l, *r),
            };
            let kl = self.sc_hpf[0].tick(kl, FilterMode::HighPass).0;
            let kr = self.sc_hpf[1].tick(kr, FilterMode::HighPass).0;
            // `max` descarta NaN; `min` doma o infinito
            let peak = kl.abs().max(kr.abs()).min(1e10);
            self.env = peak.max(self.env * self.detector_decay);
            if self.env >= self.open_at {
                self.open = true;
                self.hold = self.hold_frames;
            } else if self.env < self.close_at {
                if self.hold > 0 {
                    self.hold -= 1;
                } else {
                    self.open = false;
                }
            }
            if self.open {
                if !self.opening && self.gain < 1.0 {
                    self.opening = true;
                    self.phase = 0.0;
                    self.from = self.gain;
                }
                if self.opening {
                    self.phase += self.attack;
                    if self.phase >= 1.0 {
                        self.opening = false;
                        self.gain = 1.0;
                    } else {
                        self.gain = self.from + (1.0 - self.from) * s_curve(self.phase);
                    }
                    // os polos da soltura partem de onde a abertura estiver
                    self.closing.set(self.gain);
                    self.closing.snap();
                }
            } else {
                self.opening = false;
                self.closing.set(self.floor);
                self.gain = self.closing.step(self.release);
            }
            *l *= self.gain;
            *r *= self.gain;
            min_gain = min_gain.min(self.gain);
        }
        self.meter = if left.is_empty() { self.meter } else { -20.0 * min_gain.max(1e-6).log10() };
        if self.env < 1e-20 {
            self.env = 0.0;
        }
        for f in &mut self.sc_hpf {
            f.flush();
            if !f.is_finite() {
                f.reset();
            }
        }
    }

    fn reset(&mut self) {
        for f in &mut self.sc_hpf {
            f.reset();
        }
        self.env = 0.0;
        self.open = false;
        self.hold = 0;
        self.settle_closed();
        self.meter = 0.0;
    }

    fn meter(&self) -> f32 {
        self.meter
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::effect::gate_param as p;

    const RATE: f64 = 48_000.0;

    fn amp(db: f32) -> f32 {
        10f32.powf(db / 20.0)
    }

    fn db(x: f32) -> f32 {
        20.0 * x.abs().max(1e-12).log10()
    }

    fn tone(level_db: f32, n: usize) -> Vec<f32> {
        (0..n).map(|i| amp(level_db) * (i as f32 * std::f32::consts::TAU * 1000.0 / 48_000.0).sin()).collect()
    }

    fn run(g: &mut Gate, src: &[f32]) -> Vec<f32> {
        let (mut l, mut r) = (src.to_vec(), src.to_vec());
        for (cl, cr) in l.chunks_mut(128).zip(r.chunks_mut(128)) {
            g.process(cl, cr);
        }
        l
    }

    fn peak(x: &[f32]) -> f32 {
        x.iter().fold(0.0f32, |m, v| m.max(v.abs()))
    }

    fn gate(threshold: f32) -> Gate {
        let mut g = Gate::new(RATE);
        g.set_param(p::THRESHOLD, threshold);
        g.set_param(p::HOLD, 0.0);
        g.set_param(p::RELEASE, 0.02);
        g
    }

    #[test]
    fn fecha_abaixo_e_abre_acima() {
        let mut g = gate(-40.0);
        let out = run(&mut g, &tone(-60.0, 9600));
        let rel = db(peak(&out[4800..])) + 60.0;
        assert!((rel + 80.0).abs() < 0.5, "abaixo: {rel} dB");
        assert!((g.meter() - 80.0).abs() < 0.5);
        let out = run(&mut g, &tone(-20.0, 9600));
        let rel = db(peak(&out[4800..])) + 20.0;
        assert!(rel.abs() < 0.01, "acima: {rel} dB");
        assert!(g.meter() < 0.01);
    }

    #[test]
    fn histerese_segura_entre_os_limiares() {
        let mut g = gate(-40.0);
        run(&mut g, &tone(-30.0, 4800));
        // −42 dB: abaixo do limiar, mas acima do fechamento (−44): continua aberto
        let out = run(&mut g, &tone(-42.0, 9600));
        assert!((db(peak(&out[4800..])) + 42.0).abs() < 0.01);
        // −46 dB: fecha
        let out = run(&mut g, &tone(-46.0, 9600));
        assert!(db(peak(&out[4800..])) < -46.0 - 60.0);
        // e para reabrir precisa passar do limiar, não só do fechamento
        let out = run(&mut g, &tone(-42.0, 9600));
        assert!(db(peak(&out[4800..])) < -42.0 - 60.0);
    }

    #[test]
    fn retencao_segura_aberto() {
        let mut g = gate(-40.0);
        g.set_param(p::HOLD, 0.1);
        run(&mut g, &tone(-20.0, 4800));
        // o som some: por 100 ms (menos o decaimento do detector) o portão segue aberto
        let out = run(&mut g, &[tone(-60.0, 9600), tone(-60.0, 9600)].concat());
        let during = db(peak(&out[1000..4000])) + 60.0;
        assert!(during.abs() < 0.01, "durante a retenção: {during}");
        let after = db(peak(&out[14_000..])) + 60.0;
        assert!(after < -70.0, "depois: {after}");
    }

    #[test]
    fn alcance_limita_o_fechamento() {
        let mut g = gate(-30.0);
        g.set_param(p::RANGE, -20.0);
        let out = run(&mut g, &tone(-50.0, 9600));
        let rel = db(peak(&out[4800..])) + 50.0;
        assert!((rel + 20.0).abs() < 0.05, "{rel}");
        // alcance 0: não faz nada
        g.set_param(p::RANGE, 0.0);
        let src = tone(-50.0, 9600);
        let out = run(&mut g, &src);
        assert!((db(peak(&out[4800..])) + 50.0).abs() < 0.01);
    }

    #[test]
    fn abre_sem_estalo_e_solta_devagar() {
        let mut g = gate(-40.0);
        g.set_param(p::ATTACK, 0.005);
        g.set_param(p::RELEASE, 0.2);
        let src = [tone(-80.0, 4800), tone(-6.0, 9600), tone(-80.0, 9600)].concat();
        let out = run(&mut g, &src);
        // ataque de 5 ms: o ganho sobe em ~240 quadros, sem saltar num quadro só
        let step = out.windows(2).fold(0.0f32, |m, w| m.max((w[1] - w[0]).abs()));
        let sine_step = amp(-6.0) * std::f32::consts::TAU * 1000.0 / 48_000.0;
        assert!(step < sine_step * 1.1, "{step} > {sine_step}");
        // 100 ms depois de o som cair, a soltura de 200 ms está no meio do caminho
        let tail = db(peak(&out[14_400 + 4800..14_400 + 5000])) + 80.0;
        assert!(tail > -60.0 && tail < -5.0, "{tail}");
    }

    #[test]
    fn chave_externa_e_passa_alta() {
        let mut g = gate(-30.0);
        let src = tone(-50.0, 128);
        let key = tone(-10.0, 128);
        let mut last = 0.0;
        for _ in 0..40 {
            let (mut l, mut r) = (src.clone(), src.clone());
            g.process_keyed(&mut l, &mut r, Some((&key, &key)));
            last = peak(&l);
        }
        assert!((db(last) + 50.0).abs() < 0.01, "a chave abre um sinal abaixo do limiar");
        // chave de 50 Hz com passa-alta em 2 kHz: nem abre
        let mut g = gate(-30.0);
        g.set_param(p::SC_HPF, 2000.0);
        let bass: Vec<f32> = (0..9600).map(|i| 0.5 * (i as f32 * std::f32::consts::TAU * 50.0 / 48_000.0).sin()).collect();
        let out = run(&mut g, &bass);
        assert!(db(peak(&out[4800..])) < -80.0);
    }

    #[test]
    fn grave_nao_faz_o_portao_tremer() {
        // 60 Hz a 10 dB acima do limiar: entre os picos o detector não pode cair abaixo do fechamento
        let mut g = gate(-30.0);
        let bass: Vec<f32> = (0..48_000).map(|i| amp(-20.0) * (i as f32 * std::f32::consts::TAU * 60.0 / 48_000.0).sin()).collect();
        run(&mut g, &bass[..4800]);
        let (mut l, mut r) = (bass[4800..].to_vec(), bass[4800..].to_vec());
        let mut min_gain = 1.0f32;
        for (cl, cr) in l.chunks_mut(128).zip(r.chunks_mut(128)) {
            g.process(cl, cr);
            min_gain = min_gain.min(g.gain);
        }
        assert_eq!(min_gain, 1.0);
    }

    #[test]
    fn extremos_sem_nan() {
        for rate in [8_000.0, 44_100.0, 192_000.0] {
            let mut g = Gate::new(rate);
            for (id, v) in [(0, 1e9), (1, 0.0), (2, 1e9), (3, -1.0), (4, -1e9), (5, 1e9), (6, 3.0), (42, 1.0)] {
                g.set_param(id, v);
                g.set_param(id, f32::NAN);
            }
            let mut rng = crate::dsp::Rng::new(11);
            let (mut l, mut r): (Vec<f32>, Vec<f32>) = (0..8192).map(|_| (rng.bipolar() * 1e6, rng.bipolar())).unzip();
            for (cl, cr) in l.chunks_mut(100).zip(r.chunks_mut(100)) {
                g.process(cl, cr);
            }
            assert!(l.iter().chain(&r).all(|v| v.is_finite()));
            let (mut l, mut r) = (vec![f32::NAN; 64], vec![f32::INFINITY; 64]);
            g.process(&mut l, &mut r);
            let (mut l, mut r) = (vec![0.1; 512], vec![0.1; 512]);
            g.process(&mut l, &mut r);
            assert!(l.iter().chain(&r).all(|v| v.is_finite()) && g.meter().is_finite());
            for _ in 0..1000 {
                let (mut l, mut r) = (vec![0.0; 128], vec![0.0; 128]);
                g.process(&mut l, &mut r);
            }
            assert!(g.env == 0.0 || g.env > 1e-20);
        }
    }
}
