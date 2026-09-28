//! Filtro: SVF TPT de 12 ou 24 dB/oit (passa-baixa, passa-alta, passa-banda, rejeita-faixa), com
//! drive antes, LFO (livre ou no andamento) e seguidor de envelope movendo o corte, e mistura.
//!
//! O corte é recalculado a cada [`CHUNK`] quadros e o `g` anda em rampa linear entre um passo e
//! outro, amostra a amostra: o LFO e o envelope varrem o filtro sem degrau (zipper), e a forma TPT
//! continua estável sob essa modulação. Trocar o tipo é uma transição cruzada de 20 ms entre dois
//! bancos de filtros, o novo partindo do estado do velho.

use crate::dsp::{FilterMode, Rng, Smoothed, Svf, fast_tanh, sin_turns, smoothing};
use crate::effect::{Effect, NOTE_BEATS, filter_param as P};

/// Valores de [`P::TYPE`].
mod mode {
    pub const LP12: u32 = 0;
    pub const LP24: u32 = 1;
    pub const HP12: u32 = 2;
    pub const HP24: u32 = 3;
    pub const BP: u32 = 4;
    pub const NOTCH: u32 = 5;
}

/// Quadros por passo de controle.
const CHUNK: usize = 8;
/// Suavização dos botões.
const TAU: f32 = 0.015;
/// Suavização do LFO: arredonda os degraus da quadrada, da serra e do aleatório (que, num filtro
/// ressonante, estalariam) sem mudar o caráter.
const LFO_TAU: f32 = 0.002;
const FADE: f32 = 0.02;
/// Ressonância 0..1 em escala exponencial de Q, até este Q.
const Q_MAX: f32 = 30.0;
/// Q sem ressonância: Butterworth. No de 24 dB são duas seções com os Q do Butterworth de 4ª
/// ordem; a ressonância vai toda para a segunda.
const Q_12: f32 = std::f32::consts::FRAC_1_SQRT_2;
const Q_24_FIRST: f32 = 0.541_196_1;
const Q_24_SECOND: f32 = 1.306_563;
/// Limite da ressonância: quando o passa-banda interno passa deste nível, o amortecimento sobe e
/// o pico se contém, como num filtro analógico saturando. Sem isso, Q 30 com um sinal forte no
/// corte daria +30 dB.
const RES_LIMIT_LEVEL: f32 = 1.5;
const RES_LIMIT_DEPTH: f32 = 0.5;
const RES_LIMIT_TAU: f32 = 0.03;
/// Seguidor de envelope: ataque rápido, soltura de ~100 ms.
const ENV_ATTACK: f32 = 0.002;
const ENV_RELEASE: f32 = 0.1;
/// Menor corte depois da modulação.
const MIN_HZ: f32 = 10.0;

#[inline]
fn sane(x: f32) -> f32 {
    let a = x.abs();
    if a > 1e-20 && a < 1e6 { x } else { 0.0 }
}

/// Formas do LFO, bipolares, começando no zero subindo (as que podem).
fn lfo_shape(wave: u32, p: f32, hold: f32) -> f32 {
    match wave {
        0 => sin_turns(p),
        1 => {
            let q = p + 0.25;
            1.0 - 4.0 * (q - q.floor() - 0.5).abs()
        }
        2 => 2.0 * p - 1.0,
        3 => {
            if p < 0.5 {
                1.0
            } else {
                -1.0
            }
        }
        _ => hold,
    }
}

fn is_24(m: u32) -> bool {
    m == mode::LP24 || m == mode::HP24
}

/// Os filtros de um tipo, nos dois canais.
#[derive(Clone, Copy)]
struct Bank {
    mode: u32,
    first: [Svf; 2],
    second: [Svf; 2],
    /// Nível do passa-banda da seção ressonante (para o limite da ressonância).
    level: [f32; 2],
}

/// O que um passo de controle entrega aos bancos.
struct Ctl {
    g0: f32,
    dg: f32,
    k12: f32,
    k24: f32,
    level_rel: f32,
}

impl Bank {
    fn new(mode: u32) -> Self {
        Self { mode, first: [Svf::default(); 2], second: [Svf::default(); 2], level: [0.0; 2] }
    }

    fn reset(&mut self) {
        for f in self.first.iter_mut().chain(&mut self.second) {
            f.reset();
        }
        self.level = [0.0; 2];
    }

    /// Banco novo para o tipo `m`, continuando deste. Os tipos de 12 dB saem do mesmo filtro e
    /// herdam o estado exato; a segunda seção que só agora entra começa com o estado da primeira no
    /// passa-baixa (a entrada dela é quase a mesma) e zerada no passa-alta (que parte do zero sem
    /// buraco).
    fn successor(&self, m: u32) -> Self {
        let mut b = *self;
        b.mode = m;
        if is_24(m) && !is_24(self.mode) {
            for ch in 0..2 {
                b.second[ch] = if m == mode::LP24 { self.first[ch] } else { Svf::default() };
            }
        }
        b
    }

    fn run(&mut self, ch: usize, ctl: &Ctl, x: &[f32], y: &mut [f32]) {
        let first = &mut self.first[ch];
        let second = &mut self.second[ch];
        let level = &mut self.level[ch];
        let limit = |level: f32| RES_LIMIT_DEPTH * (level - RES_LIMIT_LEVEL).max(0.0);
        let g_at = |i: usize| ctl.g0 + ctl.dg * (i + 1) as f32;
        match self.mode {
            m @ (mode::LP12 | mode::HP12) => {
                let fm = if m == mode::LP12 { FilterMode::LowPass } else { FilterMode::HighPass };
                for (i, (y, &x)) in y.iter_mut().zip(x).enumerate() {
                    first.set(g_at(i), ctl.k12 + limit(*level));
                    let (out, band) = first.tick(x, fm);
                    *level = band.abs().max(*level * ctl.level_rel);
                    *y = out;
                }
            }
            m @ (mode::LP24 | mode::HP24) => {
                let fm = if m == mode::LP24 { FilterMode::LowPass } else { FilterMode::HighPass };
                let k1 = 1.0 / Q_24_FIRST;
                for (i, (y, &x)) in y.iter_mut().zip(x).enumerate() {
                    let g = g_at(i);
                    first.set(g, k1);
                    second.set(g, ctl.k24 + limit(*level));
                    let (a, _) = first.tick(x, fm);
                    let (out, band) = second.tick(a, fm);
                    *level = band.abs().max(*level * ctl.level_rel);
                    *y = out;
                }
            }
            m => {
                // passa-banda normalizado (ganho 1 no centro, qualquer Q) e rejeita-faixa (entrada
                // menos esse passa-banda): nenhum dos dois tem pico, dispensam o limite
                debug_assert!(m == mode::BP || m == mode::NOTCH);
                let notch = m == mode::NOTCH;
                let k = ctl.k12;
                for (i, (y, &x)) in y.iter_mut().zip(x).enumerate() {
                    first.set(g_at(i), k);
                    let (_, band) = first.tick(x, FilterMode::BandPass);
                    *y = if notch { x - k * band } else { k * band };
                }
            }
        }
    }

    fn flush(&mut self) {
        for f in self.first.iter_mut().chain(&mut self.second) {
            f.flush();
        }
        for l in &mut self.level {
            if *l < 1e-15 {
                *l = 0.0;
            }
        }
    }

    fn finite(&self) -> bool {
        self.first.iter().chain(&self.second).all(Svf::is_finite)
    }
}

pub struct Filter {
    rate: f32,
    kind: u32,
    /// log2(Hz).
    cutoff: Smoothed,
    resonance: Smoothed,
    drive: Smoothed,
    mix: Smoothed,
    lfo_depth: Smoothed,
    env_amount: Smoothed,
    lfo_rate: f32,
    lfo_wave: u32,
    sync: bool,
    note: usize,
    bpm: f64,
    lfo_phase: f32,
    lfo_hold: f32,
    lfo: f32,
    rng: Rng,
    env: f32,
    env_att: f32,
    env_rel: f32,
    level_rel: f32,
    banks: [Bank; 2],
    active: usize,
    fading: bool,
    fade: f32,
    /// `g` e mistura no fim do último passo, de onde partem as rampas.
    g: f32,
    mix_now: f32,
    /// Corte efetivo no último passo (Hz), para os testes e para quem quiser mostrar.
    hz: f32,
    /// Ainda não processou nada: parâmetros chegam sem rampa nem transição.
    fresh: bool,
}

impl Filter {
    pub fn new(rate: f64) -> Self {
        let rate = rate as f32;
        let pole = |secs: f32| 1.0 - (-1.0 / (secs * rate)).exp();
        let mut f = Self {
            rate,
            kind: mode::LP24,
            cutoff: Smoothed::new(1000f32.log2()),
            resonance: Smoothed::new(0.2),
            drive: Smoothed::new(0.0),
            mix: Smoothed::new(1.0),
            lfo_depth: Smoothed::new(0.0),
            env_amount: Smoothed::new(0.0),
            lfo_rate: 1.0,
            lfo_wave: 0,
            sync: false,
            note: 8,
            bpm: 120.0,
            lfo_phase: 0.0,
            lfo_hold: 0.0,
            lfo: 0.0,
            rng: Rng::new(0x5EED_F117),
            env: 0.0,
            env_att: pole(ENV_ATTACK),
            env_rel: pole(ENV_RELEASE),
            level_rel: (-1.0 / (RES_LIMIT_TAU * rate)).exp(),
            banks: [Bank::new(mode::LP24), Bank::new(mode::LP24)],
            active: 0,
            fading: false,
            fade: 0.0,
            g: 0.0,
            mix_now: 1.0,
            hz: 1000.0,
            fresh: true,
        };
        f.snap();
        f
    }

    fn max_hz(&self) -> f32 {
        0.45 * self.rate
    }

    /// Botões direto no alvo, e o `g` no corte sem modulação.
    fn snap(&mut self) {
        for s in [&mut self.cutoff, &mut self.resonance, &mut self.drive, &mut self.mix, &mut self.lfo_depth, &mut self.env_amount] {
            s.snap();
        }
        self.hz = self.cutoff.value.exp2().clamp(MIN_HZ, self.max_hz());
        self.g = Svf::g(self.hz, self.rate);
        self.mix_now = self.mix.value;
    }

    fn retarget(&mut self) {
        if self.fresh {
            self.banks[self.active].mode = self.kind;
            return;
        }
        if self.fading || self.banks[self.active].mode == self.kind {
            return;
        }
        self.banks[1 - self.active] = self.banks[self.active].successor(self.kind);
        self.fading = true;
        self.fade = 0.0;
    }

    fn lfo_hz(&self) -> f32 {
        if self.sync { (self.bpm / 60.0 / NOTE_BEATS[self.note]) as f32 } else { self.lfo_rate }
    }

    fn chunk(&mut self, left: &mut [f32], right: &mut [f32]) {
        let len = left.len();
        let inv = 1.0 / len as f32;
        let rate = self.rate;
        let a = smoothing(TAU, len, rate);

        // envelope da entrada (ligado entre os canais: o corte é um só)
        for (&l, &r) in left.iter().zip(right.iter()) {
            let e = sane(l).abs().max(sane(r).abs());
            self.env += (e - self.env) * if e > self.env { self.env_att } else { self.env_rel };
        }

        self.lfo_phase += self.lfo_hz() * len as f32 / rate;
        if self.lfo_phase >= 1.0 {
            self.lfo_phase -= self.lfo_phase.floor();
            self.lfo_hold = self.rng.bipolar();
        }
        let raw = lfo_shape(self.lfo_wave, self.lfo_phase, self.lfo_hold);
        self.lfo += (raw - self.lfo) * smoothing(LFO_TAU, len, rate);

        let base = self.cutoff.step(a);
        let depth = self.lfo_depth.step(a);
        let env_amount = self.env_amount.step(a);
        // raiz: −12 dBFS já leva metade do caminho, o que soa mais natural que a amplitude crua
        let octaves = base + self.lfo * depth + self.env.min(1.0).sqrt() * env_amount;
        self.hz = octaves.exp2().clamp(MIN_HZ, self.max_hz());
        let g1 = Svf::g(self.hz, rate);
        let res = self.resonance.step(a);
        let ctl = Ctl {
            g0: self.g,
            dg: (g1 - self.g) * inv,
            k12: 1.0 / (Q_12 * (Q_MAX / Q_12).powf(res)),
            k24: 1.0 / (Q_24_SECOND * (Q_MAX / Q_24_SECOND).powf(res)),
            level_rel: self.level_rel,
        };
        self.g = g1;

        // drive: até +24 dB de entrada na tanh; os primeiros 12% do botão fazem a passagem do limpo
        // para o saturado, e a compensação segura o volume quando a onda vira quase quadrada
        let d = self.drive.step(a);
        let blend = (d * 8.0).min(1.0);
        let pre = (4.0 * d).exp2();
        let comp = 0.6 + 0.4 / pre;

        let mix1 = self.mix.step(a);
        let (m0, dm) = (self.mix_now, (mix1 - self.mix_now) * inv);
        self.mix_now = mix1;

        let (act, idle) = (self.active, 1 - self.active);
        let fading = self.fading;
        let (t0, dt) = if fading { (self.fade, ((self.fade + len as f32 / (FADE * rate)).min(1.0) - self.fade) * inv) } else { (0.0, 0.0) };

        for ch in 0..2 {
            let buf: &mut [f32] = if ch == 0 { &mut *left } else { &mut *right };
            let mut dry = [0.0f32; CHUNK];
            let mut xd = [0.0f32; CHUNK];
            for ((&x, d), v) in buf.iter().zip(dry.iter_mut()).zip(xd.iter_mut()) {
                *d = sane(x);
                *v = if blend > 0.0 { *d + (fast_tanh(*d * pre) * comp - *d) * blend } else { *d };
            }
            let mut wet = [0.0f32; CHUNK];
            self.banks[act].run(ch, &ctl, &xd[..len], &mut wet[..len]);
            if fading {
                let mut other = [0.0f32; CHUNK];
                self.banks[idle].run(ch, &ctl, &xd[..len], &mut other[..len]);
                for (i, (w, &o)) in wet[..len].iter_mut().zip(&other[..len]).enumerate() {
                    *w += (o - *w) * (t0 + dt * (i + 1) as f32);
                }
            }
            for (i, ((y, &w), &d)) in buf.iter_mut().zip(&wet[..len]).zip(&dry[..len]).enumerate() {
                *y = d + (w - d) * (m0 + dm * (i + 1) as f32);
            }
        }

        if fading {
            self.fade = t0 + dt * len as f32;
            if self.fade >= 1.0 {
                self.active = idle;
                self.fading = false;
                self.fade = 0.0;
                self.retarget();
            }
        }
    }

    /// Corte efetivo (Hz) no último passo de controle.
    pub fn cutoff_hz(&self) -> f32 {
        self.hz
    }
}

impl Effect for Filter {
    fn set_param(&mut self, id: u32, value: f32) {
        if !value.is_finite() {
            return;
        }
        match id {
            P::TYPE => {
                self.kind = value.round().clamp(0.0, mode::NOTCH as f32) as u32;
                self.retarget();
            }
            P::CUTOFF => self.cutoff.set(value.clamp(20.0, 20_000.0).log2()),
            P::RESONANCE => self.resonance.set(value.clamp(0.0, 1.0)),
            P::LFO_RATE => self.lfo_rate = value.clamp(0.02, 20.0),
            P::LFO_DEPTH => self.lfo_depth.set(value.clamp(0.0, 6.0)),
            P::LFO_WAVE => self.lfo_wave = value.round().clamp(0.0, 4.0) as u32,
            P::ENVELOPE => self.env_amount.set(value.clamp(-6.0, 6.0)),
            P::DRIVE => self.drive.set(value.clamp(0.0, 1.0)),
            P::MIX => self.mix.set(value.clamp(0.0, 1.0)),
            P::SYNC => self.sync = value >= 0.5,
            P::NOTE => self.note = value.round().clamp(0.0, (NOTE_BEATS.len() - 1) as f32) as usize,
            _ => return,
        }
        if self.fresh {
            self.snap();
        }
    }

    fn process(&mut self, left: &mut [f32], right: &mut [f32]) {
        self.fresh = false;
        let n = left.len().min(right.len());
        let mut start = 0;
        while start < n {
            let end = (start + CHUNK).min(n);
            self.chunk(&mut left[start..end], &mut right[start..end]);
            start = end;
        }
        for b in &mut self.banks {
            b.flush();
        }
        if self.env < 1e-15 {
            self.env = 0.0;
        }
        if !self.banks.iter().all(Bank::finite) {
            // não deveria acontecer (a entrada é saneada e o TPT é estável), mas um estado podre
            // calaria a faixa para sempre
            for b in &mut self.banks {
                b.reset();
            }
        }
    }

    fn set_tempo(&mut self, bpm: f64) {
        if bpm.is_finite() && bpm > 0.0 {
            self.bpm = bpm.clamp(10.0, 1000.0);
        }
    }

    fn reset(&mut self) {
        for b in &mut self.banks {
            b.reset();
        }
        self.banks[self.active].mode = self.kind;
        self.fading = false;
        self.fade = 0.0;
        self.env = 0.0;
        self.lfo_phase = 0.0;
        self.lfo_hold = 0.0;
        self.lfo = lfo_shape(self.lfo_wave, 0.0, 0.0);
        self.snap();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::f32::consts::TAU as TWO_PI;

    const RATE: f32 = 48_000.0;

    fn make(params: &[(u32, f32)]) -> Filter {
        let mut f = Filter::new(RATE as f64);
        for &(id, v) in params {
            f.set_param(id, v);
        }
        f
    }

    fn sine(freq: f32, amp: f32, n: usize) -> Vec<f32> {
        (0..n).map(|i| amp * (i as f32 * freq / RATE * TWO_PI).sin()).collect()
    }

    fn run(f: &mut Filter, input: &[f32]) -> Vec<f32> {
        let mut out = Vec::with_capacity(input.len());
        for block in input.chunks(128) {
            let mut l = block.to_vec();
            let mut r = block.to_vec();
            f.process(&mut l, &mut r);
            out.extend_from_slice(&l);
        }
        out
    }

    fn peak(x: &[f32]) -> f32 {
        x.iter().fold(0.0f32, |m, v| m.max(v.abs()))
    }

    /// Ganho em dB de um tom estável.
    fn gain_db(params: &[(u32, f32)], freq: f32) -> f32 {
        let mut f = make(params);
        let y = run(&mut f, &sine(freq, 0.5, 24_000));
        20.0 * (peak(&y[12_000..]) / 0.5).log10()
    }

    #[test]
    fn passa_baixa_24_cai_24_db_por_oitava() {
        let p = [(P::TYPE, mode::LP24 as f32), (P::CUTOFF, 1000.0), (P::RESONANCE, 0.0)];
        assert!(gain_db(&p, 100.0).abs() < 0.1);
        // Butterworth: −3 dB no corte
        assert!((gain_db(&p, 1000.0) + 3.0).abs() < 0.3);
        let slope = gain_db(&p, 2000.0) - gain_db(&p, 4000.0);
        assert!((slope - 24.0).abs() < 1.5, "{slope} dB/oit");
    }

    #[test]
    fn passa_baixa_12_cai_12_db_por_oitava() {
        let p = [(P::TYPE, mode::LP12 as f32), (P::CUTOFF, 1000.0), (P::RESONANCE, 0.0)];
        let slope = gain_db(&p, 2000.0) - gain_db(&p, 4000.0);
        assert!((slope - 12.0).abs() < 1.0, "{slope} dB/oit");
        assert!((gain_db(&p, 1000.0) + 3.0).abs() < 0.3);
    }

    #[test]
    fn passa_alta_espelha_o_passa_baixa() {
        let p24 = [(P::TYPE, mode::HP24 as f32), (P::CUTOFF, 1000.0), (P::RESONANCE, 0.0)];
        assert!(gain_db(&p24, 10_000.0).abs() < 0.1);
        let slope = gain_db(&p24, 500.0) - gain_db(&p24, 250.0);
        assert!((slope - 24.0).abs() < 1.5, "{slope} dB/oit");
        let p12 = [(P::TYPE, mode::HP12 as f32), (P::CUTOFF, 1000.0), (P::RESONANCE, 0.0)];
        let slope = gain_db(&p12, 500.0) - gain_db(&p12, 250.0);
        assert!((slope - 12.0).abs() < 1.0, "{slope} dB/oit");
    }

    #[test]
    fn passa_banda_e_rejeita_faixa() {
        let bp = [(P::TYPE, mode::BP as f32), (P::CUTOFF, 1000.0), (P::RESONANCE, 0.5)];
        assert!(gain_db(&bp, 1000.0).abs() < 0.2);
        assert!(gain_db(&bp, 250.0) < -12.0 && gain_db(&bp, 4000.0) < -12.0);
        let notch = [(P::TYPE, mode::NOTCH as f32), (P::CUTOFF, 1000.0), (P::RESONANCE, 0.5)];
        assert!(gain_db(&notch, 1000.0) < -40.0);
        assert!(gain_db(&notch, 100.0).abs() < 0.2 && gain_db(&notch, 10_000.0).abs() < 0.2);
    }

    #[test]
    fn ressonancia_faz_pico_e_fica_contida() {
        let p = |res: f32| [(P::TYPE, mode::LP24 as f32), (P::CUTOFF, 1000.0), (P::RESONANCE, res)];
        // pico no corte com ressonância média, sinal baixo (o limite não age)
        let mut f = make(&p(0.5));
        let y = run(&mut f, &sine(1000.0, 0.05, 24_000));
        assert!(peak(&y[12_000..]) > 0.05 * 3.0);
        // ressonância máxima com sinal forte no corte: o limite segura o pico
        let mut f = make(&p(1.0));
        let y = run(&mut f, &sine(1000.0, 1.0, 48_000));
        let top = peak(&y[24_000..]);
        assert!(top < 8.0, "pico de {top}");
        // e com um impulso de pé, sem entrada depois, a ressonância morre sozinha
        let mut x = vec![0.0; 96_000];
        x[100] = 1.0;
        let y = run(&mut f, &x);
        assert!(peak(&y[90_000..]) < 1e-4);
    }

    #[test]
    fn lfo_move_o_corte() {
        let mut f = make(&[(P::CUTOFF, 1000.0), (P::LFO_DEPTH, 2.0), (P::LFO_RATE, 2.0)]);
        let (mut lo, mut hi) = (f32::MAX, f32::MIN);
        let mut l = vec![0.0; 64];
        let mut r = vec![0.0; 64];
        for _ in 0..750 {
            f.process(&mut l, &mut r);
            lo = lo.min(f.cutoff_hz());
            hi = hi.max(f.cutoff_hz());
        }
        // ±2 oitavas em torno de 1 kHz
        assert!((lo - 250.0).abs() < 10.0 && (hi - 4000.0).abs() < 150.0, "{lo}..{hi}");

        // e o som acompanha: um tom de 3 kHz passa e some conforme o corte varre
        let mut f = make(&[(P::CUTOFF, 1000.0), (P::LFO_DEPTH, 2.0), (P::LFO_RATE, 2.0)]);
        let y = run(&mut f, &sine(3000.0, 0.5, 48_000));
        let windows: Vec<f32> = y.chunks(2400).map(peak).collect();
        let (wlo, whi) = windows.iter().fold((f32::MAX, 0.0f32), |(a, b), &v| (a.min(v), b.max(v)));
        assert!(whi > 0.3 && wlo < 0.01, "{wlo}..{whi}");
    }

    #[test]
    fn lfo_sincronizado_segue_o_andamento() {
        // 1/4 a 120 bpm = 2 Hz: meio segundo por ciclo; a serra (±1 oitava em torno de 1 kHz) sobe
        // e despenca a cada ciclo. Conta as quedas com histerese: armada acima de 1,5 kHz, conta
        // abaixo de 700 Hz.
        let mut f = make(&[(P::CUTOFF, 1000.0), (P::LFO_DEPTH, 1.0), (P::LFO_WAVE, 2.0), (P::SYNC, 1.0), (P::NOTE, 8.0)]);
        f.set_tempo(120.0);
        let mut l = vec![0.0; 48];
        let mut r = vec![0.0; 48];
        let mut count = |f: &mut Filter, blocks: usize| {
            let (mut drops, mut armed) = (0, false);
            for _ in 0..blocks {
                f.process(&mut l, &mut r);
                if f.cutoff_hz() > 1500.0 {
                    armed = true;
                } else if armed && f.cutoff_hz() < 700.0 {
                    armed = false;
                    drops += 1;
                }
            }
            drops
        };
        // 2,1 s → 4 quedas (em 0,5, 1, 1,5 e 2 s)
        assert_eq!(count(&mut f, 2100), 4);
        // a 60 bpm, 1 Hz: 2 quedas em 2 s
        f.set_tempo(60.0);
        assert_eq!(count(&mut f, 2000), 2);
    }

    #[test]
    fn envelope_abre_o_filtro() {
        let mut f = make(&[(P::CUTOFF, 200.0), (P::ENVELOPE, 4.0)]);
        let mut l = vec![0.0; 128];
        let mut r = vec![0.0; 128];
        f.process(&mut l, &mut r);
        assert!((f.cutoff_hz() - 200.0).abs() < 1.0);
        let mut x = sine(500.0, 1.0, 4800);
        let _ = run(&mut f, &x);
        // sinal em 0 dBFS: +4 oitavas
        assert!((f.cutoff_hz() / 3200.0 - 1.0).abs() < 0.1, "{}", f.cutoff_hz());
        // e fecha depois que o som para: constante de tempo de 100 ms
        x.iter_mut().for_each(|v| *v = 0.0);
        let _ = run(&mut f, &x);
        assert!(f.cutoff_hz() < 1200.0, "{}", f.cutoff_hz());
        for _ in 0..4 {
            let _ = run(&mut f, &x);
        }
        assert!(f.cutoff_hz() < 260.0, "{}", f.cutoff_hz());
        // envelope negativo fecha
        let mut f = make(&[(P::CUTOFF, 2000.0), (P::ENVELOPE, -3.0)]);
        let _ = run(&mut f, &sine(500.0, 1.0, 4800));
        assert!((f.cutoff_hz() / 250.0 - 1.0).abs() < 0.1, "{}", f.cutoff_hz());
    }

    #[test]
    fn mistura_zero_e_o_seco() {
        let mut f = make(&[(P::TYPE, mode::HP24 as f32), (P::CUTOFF, 5000.0), (P::RESONANCE, 0.9), (P::DRIVE, 1.0), (P::LFO_DEPTH, 3.0), (P::MIX, 0.0)]);
        let x = sine(440.0, 0.7, 9600);
        let y = run(&mut f, &x);
        assert_eq!(x, y);
    }

    #[test]
    fn drive_satura_sem_pular_o_volume() {
        let p = |d: f32| [(P::TYPE, mode::LP12 as f32), (P::CUTOFF, 20_000.0), (P::RESONANCE, 0.0), (P::DRIVE, d)];
        let clean = gain_db(&p(0.0), 200.0);
        let driven = gain_db(&p(1.0), 200.0);
        assert!(clean.abs() < 0.2 && (driven - clean).abs() < 6.0, "{clean} → {driven}");
    }

    #[test]
    fn modulacao_e_troca_de_tipo_sem_estalo() {
        // quadrada no LFO, várias oitavas, e trocas de tipo no meio: a saída de um tom grave não
        // pode dar degrau
        let mut f = make(&[(P::CUTOFF, 2000.0), (P::LFO_DEPTH, 4.0), (P::LFO_WAVE, 3.0), (P::LFO_RATE, 8.0), (P::RESONANCE, 0.3)]);
        let x = sine(80.0, 0.3, 96_000);
        let mut y = Vec::new();
        for (n, block) in x.chunks(4800).enumerate() {
            f.set_param(P::TYPE, (n % 6) as f32);
            y.extend(run(&mut f, block));
        }
        // o tom anda até 0,003 por amostra; uma quina de verdade passaria de 0,05
        let worst = y[4800..].windows(2).map(|w| (w[1] - w[0]).abs()).fold(0.0f32, f32::max);
        assert!(worst < 0.03, "salto de {worst}");
    }

    #[test]
    fn nenhum_nan_com_extremos() {
        let mut f = make(&[]);
        let mut rng = Rng::new(3);
        let ids = [P::TYPE, P::CUTOFF, P::RESONANCE, P::LFO_RATE, P::LFO_DEPTH, P::LFO_WAVE, P::ENVELOPE, P::DRIVE, P::MIX, P::SYNC, P::NOTE];
        let extremes = [-1e9, -6.0, 0.0, 0.5, 1.0, 5.0, 6.0, 20.0, 20_000.0, 1e9, f32::NAN, f32::INFINITY];
        for round in 0..600 {
            let id = ids[round % ids.len()];
            f.set_param(id, extremes[(rng.next_u32() as usize) % extremes.len()]);
            if round % 50 == 0 {
                f.set_tempo([0.0, 1e9, f64::NAN, 300.0][round / 50 % 4]);
            }
            let mut l: Vec<f32> = (0..128)
                .map(|i| match (round + i) % 9 {
                    0 => 1e5,
                    1 => -1e5,
                    2 => f32::NAN,
                    3 => f32::INFINITY,
                    4 => 1e-39,
                    _ => rng.bipolar() * 4.0,
                })
                .collect();
            let mut r = l.clone();
            f.process(&mut l, &mut r);
            assert!(l.iter().chain(&r).all(|v| v.is_finite()), "rodada {round}");
        }
        f.reset();
        let mut l = vec![0.0; 128];
        let mut r = vec![0.0; 128];
        f.process(&mut l, &mut r);
        assert!(l.iter().all(|v| *v == 0.0));
    }

    #[test]
    fn blocos_de_qualquer_tamanho() {
        let params = [(P::TYPE, mode::LP24 as f32), (P::CUTOFF, 800.0), (P::RESONANCE, 0.6), (P::DRIVE, 0.3)];
        let x = sine(300.0, 0.6, 4000);
        let mut a = make(&params);
        let ya = run(&mut a, &x);
        let mut b = make(&params);
        let mut yb = Vec::new();
        let mut i = 0;
        for n in [1usize, 3, 8, 13, 128, 500].iter().cycle() {
            if i >= x.len() {
                break;
            }
            let end = (i + n).min(x.len());
            let mut l = x[i..end].to_vec();
            let mut r = l.clone();
            b.process(&mut l, &mut r);
            yb.extend(l);
            i = end;
        }
        for (p, q) in ya.iter().zip(&yb) {
            assert!((p - q).abs() < 1e-4);
        }
    }
}
