//! Compressor multibanda de 3 bandas.
//!
//! O sinal se divide em baixa, média e aguda por filtros Linkwitz-Riley de 4ª ordem (dois
//! Butterworth de 2º grau em cascata): passa-baixa e passa-alta do mesmo corte somam num passa-tudo,
//! então, sem compressão, a soma das bandas tem módulo plano (só a fase gira, sem atraso no tempo:
//! latência 0). Com dois cruzamentos, a banda baixa precisa passar também por um passa-tudo de
//! segunda ordem no cruzamento alto (a soma dos LR4 dele) para que as três bandas fiquem em fase
//! entre si; senão a soma não seria plana perto do segundo cruzamento.
//!
//! Cada banda tem seu compressor (detector de pico com seguidor de queda proporcional à banda,
//! computador de ganho com joelho e balística em dB, como em `compressor.rs`), ganho de
//! compensação, bypass e solo. O detector liga os dois canais (o mais forte manda), então a imagem
//! estéreo não desliza.
//!
//! O indicador leva as reduções das três bandas juntas ([`pack_meter`]).

use std::f32::consts::SQRT_2;

use super::compressor::{fast_exp2, fast_log2, reduction};
use super::eq::Glide;
use crate::dsp::{FilterMode, Smoothed, Svf, smoothing};
use crate::effect::{Effect, multiband_param as p};

const BANDS: usize = p::BANDS;
/// Suavização de limiar, razão e joelho por quadro (ver `compressor.rs`).
const SMOOTH_SECS: f32 = 0.010;
/// Ganhos que vão direto ao áudio (saída, compensação, solo e bypass): dois polos desta constante.
const GLIDE_SECS: f32 = 0.005;
/// Deslizar dos cruzamentos, por bloco.
const XOVER_SECS: f32 = 0.02;
/// Quanto o seguidor de pico segura cada banda, s: a baixa precisa de mais para não tremer com o
/// período da própria onda.
const HOLD_SECS: [f32; BANDS] = [0.025, 0.010, 0.003];
/// dB de potência por unidade de log2 (10·log10(2)).
const DB_PER_LOG2: f32 = 3.010_3;
const LOG2_PER_DB: f32 = 0.166_096_4;
/// Maior redução que o indicador representa, dB.
const METER_MAX_DB: f32 = 25.5;
/// Entrada acima disto (em módulo) é limitada: um infinito não pode contaminar os filtros.
const INPUT_LIMIT: f32 = 1e6;

/// Empacota as reduções de ganho das três bandas (dB ≥ 0) num inteiro exato de 24 bits (cabe na
/// mantissa de um `f32`): `q0 + 256 q1 + 65536 q2`, com `q` em décimos de dB (0..255, ou seja,
/// até 25,5 dB).
pub fn pack_meter(gr: [f32; BANDS]) -> f32 {
    let mut v = 0u32;
    for (i, g) in gr.iter().enumerate() {
        let q = if g.is_finite() { (g.min(METER_MAX_DB) * 10.0).round().max(0.0) as u32 } else { 0 };
        v |= q << (8 * i);
    }
    v as f32
}

/// Inverso de [`pack_meter`] (dB por banda).
pub fn unpack_meter(v: f32) -> [f32; BANDS] {
    let v = if v.is_finite() { v.max(0.0) as u32 } else { 0 };
    [(v & 255) as f32 / 10.0, ((v >> 8) & 255) as f32 / 10.0, ((v >> 16) & 255) as f32 / 10.0]
}

/// Um cruzamento LR4 de um canal: passa-baixa e passa-alta em cascata de dois Butterworth.
#[derive(Clone, Copy, Default)]
pub(crate) struct Lr4 {
    lp: [Svf; 2],
    hp: [Svf; 2],
}

impl Lr4 {
    pub(crate) fn set(&mut self, g: f32) {
        for f in self.lp.iter_mut().chain(self.hp.iter_mut()) {
            f.set(g, SQRT_2);
        }
    }

    /// (baixa, alta) de um quadro.
    #[inline]
    pub(crate) fn split(&mut self, x: f32) -> (f32, f32) {
        let lo = self.lp[0].tick(x, FilterMode::LowPass).0;
        let lo = self.lp[1].tick(lo, FilterMode::LowPass).0;
        let hi = self.hp[0].tick(x, FilterMode::HighPass).0;
        let hi = self.hp[1].tick(hi, FilterMode::HighPass).0;
        (lo, hi)
    }

    /// Só a passa-baixa (o passa-alta fica parado: use um `Lr4` só para um dos lados).
    #[inline]
    pub(crate) fn lowpass(&mut self, x: f32) -> f32 {
        let lo = self.lp[0].tick(x, FilterMode::LowPass).0;
        self.lp[1].tick(lo, FilterMode::LowPass).0
    }

    /// Só a passa-alta.
    #[inline]
    pub(crate) fn highpass(&mut self, x: f32) -> f32 {
        let hi = self.hp[0].tick(x, FilterMode::HighPass).0;
        self.hp[1].tick(hi, FilterMode::HighPass).0
    }

    pub(crate) fn flush(&mut self) {
        for f in self.lp.iter_mut().chain(self.hp.iter_mut()) {
            f.flush();
        }
    }

    pub(crate) fn finite(&self) -> bool {
        self.lp.iter().chain(self.hp.iter()).all(Svf::is_finite)
    }

    pub(crate) fn reset(&mut self) {
        for f in self.lp.iter_mut().chain(self.hp.iter_mut()) {
            f.reset();
        }
    }
}

/// O compressor de uma banda.
struct Band {
    threshold: Smoothed,
    slope: Smoothed,
    knee: Smoothed,
    /// Ganho de compensação, dB.
    makeup: Glide,
    /// 0/1 suavizado: a banda passa direto.
    bypass: Glide,
    /// 0/1 suavizado: a banda é ouvida (solo).
    audible: Glide,
    attack: f32,
    release: f32,
    /// Seguidor de pico (linear).
    peak: f32,
    hold: f32,
    /// Redução de ganho suavizada, dB.
    env: f32,
    /// Maior redução do último bloco, dB (para o indicador).
    meter: f32,
    solo: bool,
    bypassed: bool,
}

fn time_coef(secs: f32, rate: f32) -> f32 {
    (-1.0 / (secs * rate)).exp()
}

impl Band {
    fn new(index: usize, rate: f32) -> Self {
        Self {
            threshold: Smoothed::new(-24.0),
            slope: Smoothed::new(0.75),
            knee: Smoothed::new(6.0),
            makeup: Glide::new(0.0),
            bypass: Glide::new(0.0),
            audible: Glide::new(1.0),
            attack: time_coef(0.01, rate),
            release: time_coef(0.15, rate),
            peak: 0.0,
            hold: time_coef(HOLD_SECS[index], rate),
            env: 0.0,
            meter: 0.0,
            solo: false,
            bypassed: false,
        }
    }

    fn snap(&mut self) {
        self.threshold.snap();
        self.slope.snap();
        self.knee.snap();
        self.makeup.snap();
        self.bypass.snap();
        self.audible.snap();
    }

    fn reset(&mut self) {
        self.peak = 0.0;
        self.env = 0.0;
        self.meter = 0.0;
        self.snap();
    }
}

pub struct Multiband {
    rate: f32,
    low_hz: Smoothed,
    high_hz: Smoothed,
    /// Cruzamentos em uso (Hz), depois de manter o alto acima do baixo.
    used: (f32, f32),
    xover_a: f32,
    /// Por canal: cruzamento baixo, alto, e o passa-tudo alto aplicado à banda baixa.
    split1: [Lr4; 2],
    split2: [Lr4; 2],
    split_ap: [Lr4; 2],
    bands: [Band; BANDS],
    output: Glide,
    smooth: f32,
    glide: f32,
    fresh: bool,
}

impl Multiband {
    pub fn new(rate: f64) -> Self {
        let rate = rate as f32;
        let mut m = Self {
            rate,
            low_hz: Smoothed::new(150.0),
            high_hz: Smoothed::new(3000.0),
            used: (0.0, 0.0),
            xover_a: 1.0,
            split1: [Lr4::default(); 2],
            split2: [Lr4::default(); 2],
            split_ap: [Lr4::default(); 2],
            bands: [Band::new(0, rate), Band::new(1, rate), Band::new(2, rate)],
            output: Glide::new(0.0),
            smooth: smoothing(SMOOTH_SECS, 1, rate),
            glide: smoothing(GLIDE_SECS, 1, rate),
            fresh: true,
        };
        m.update_crossovers(true);
        m
    }

    /// Cruzamentos efetivos: o alto fica pelo menos meia oitava acima do baixo e ambos abaixo de
    /// Nyquist. Só refaz a tangente dos filtros se algo mudou.
    fn update_crossovers(&mut self, force: bool) {
        let top = 0.45 * self.rate;
        let high = self.high_hz.value.max(self.low_hz.value * 1.5).min(top);
        let low = self.low_hz.value.min(high / 1.5).max(10.0);
        if !force && (low, high) == self.used {
            return;
        }
        self.used = (low, high);
        let (g1, g2) = (Svf::g(low, self.rate), Svf::g(high, self.rate));
        for ch in 0..2 {
            self.split1[ch].set(g1);
            self.split2[ch].set(g2);
            self.split_ap[ch].set(g2);
        }
    }

    fn update_audible(&mut self) {
        let any = self.bands.iter().any(|b| b.solo);
        for b in &mut self.bands {
            b.audible.set(if !any || b.solo { 1.0 } else { 0.0 });
        }
    }

    fn snap(&mut self) {
        self.low_hz.snap();
        self.high_hz.snap();
        self.output.snap();
        for b in &mut self.bands {
            b.snap();
        }
        self.update_crossovers(false);
    }
}

#[inline]
fn clean(x: f32) -> f32 {
    if x.is_finite() { x.clamp(-INPUT_LIMIT, INPUT_LIMIT) } else { 0.0 }
}

impl Effect for Multiband {
    fn set_param(&mut self, id: u32, value: f32) {
        if !value.is_finite() {
            return;
        }
        match id {
            p::XOVER_LOW => self.low_hz.set(value.clamp(40.0, 800.0)),
            p::XOVER_HIGH => self.high_hz.set(value.clamp(1000.0, 12000.0)),
            p::OUTPUT => self.output.set(value.clamp(-24.0, 24.0)),
            _ if id >= p::BAND_BASE && id < p::BAND_BASE + p::BAND_STRIDE * BANDS as u32 => {
                let rel = id - p::BAND_BASE;
                let (i, k) = ((rel / p::BAND_STRIDE) as usize, rel % p::BAND_STRIDE);
                let rate = self.rate;
                let b = &mut self.bands[i];
                match k {
                    p::BAND_THRESHOLD => b.threshold.set(value.clamp(-60.0, 0.0)),
                    p::BAND_RATIO => b.slope.set(1.0 - 1.0 / value.clamp(1.0, 20.0)),
                    p::BAND_ATTACK => b.attack = time_coef(value.clamp(0.0001, 0.25), rate),
                    p::BAND_RELEASE => b.release = time_coef(value.clamp(0.005, 3.0), rate),
                    p::BAND_MAKEUP => b.makeup.set(value.clamp(-12.0, 24.0)),
                    p::BAND_SOLO => {
                        b.solo = value >= 0.5;
                        self.update_audible();
                    }
                    p::BAND_BYPASS => {
                        b.bypassed = value >= 0.5;
                        b.bypass.set(if b.bypassed { 1.0 } else { 0.0 });
                    }
                    p::BAND_KNEE => b.knee.set(value.clamp(0.0, 24.0)),
                    _ => return,
                }
            }
            _ => return,
        }
        if self.fresh {
            self.snap();
        }
    }

    fn process(&mut self, left: &mut [f32], right: &mut [f32]) {
        self.fresh = false;
        let frames = left.len().min(right.len());
        // os cruzamentos deslizam por bloco (a tangente é cara); o filtro TPT aguenta o salto
        let xa = smoothing(XOVER_SECS, frames.max(1), self.rate);
        self.xover_a = xa;
        self.low_hz.step(xa);
        self.high_hz.step(xa);
        self.update_crossovers(false);
        let a = self.smooth;
        for b in &mut self.bands {
            b.meter = 0.0;
        }
        for i in 0..frames {
            let inp = [clean(left[i]), clean(right[i])];
            // bandas por canal: [baixa, média, aguda]
            let mut sig = [[0.0f32; 2]; BANDS];
            for (ch, &x) in inp.iter().enumerate() {
                let (lo, hi) = self.split1[ch].split(x);
                let (mid, high) = self.split2[ch].split(hi);
                let (lo_a, lo_b) = self.split_ap[ch].split(lo);
                sig[0][ch] = lo_a + lo_b;
                sig[1][ch] = mid;
                sig[2][ch] = high;
            }
            let out_gain = fast_exp2(self.output.step(self.glide) * LOG2_PER_DB);
            let mut out = [0.0f32; 2];
            for (b, s) in self.bands.iter_mut().zip(sig.iter()) {
                // detector: pico dos dois canais, com queda proporcional à banda
                let level_lin = s[0].abs().max(s[1].abs());
                b.peak = (b.peak * b.hold).max(level_lin).max(1e-9);
                let level = 2.0 * DB_PER_LOG2 * fast_log2(b.peak);
                let gr = reduction(level - b.threshold.step(a), b.slope.step(a), b.knee.step(a));
                let coef = if gr > b.env { b.attack } else { b.release };
                b.env = gr + (b.env - gr) * coef;
                let bypass = b.bypass.step(self.glide);
                let audible = b.audible.step(self.glide);
                let makeup = b.makeup.step(self.glide);
                let comp = fast_exp2((makeup - b.env) * LOG2_PER_DB);
                let g = (comp + bypass * (1.0 - comp)) * audible * out_gain;
                out[0] += s[0] * g;
                out[1] += s[1] * g;
                b.meter = b.meter.max(b.env * (1.0 - bypass));
            }
            left[i] = out[0];
            right[i] = out[1];
        }
        let mut sick = false;
        for ch in 0..2 {
            for s in [&mut self.split1[ch], &mut self.split2[ch], &mut self.split_ap[ch]] {
                s.flush();
                sick |= !s.finite();
            }
        }
        if sick {
            self.reset_filters();
        }
        for b in &mut self.bands {
            if b.env < 1e-9 {
                b.env = 0.0;
            }
        }
    }

    fn reset(&mut self) {
        self.reset_filters();
        for b in &mut self.bands {
            b.reset();
        }
        self.snap();
        self.fresh = true;
    }

    fn meter(&self) -> f32 {
        pack_meter([self.bands[0].meter, self.bands[1].meter, self.bands[2].meter])
    }
}

impl Multiband {
    fn reset_filters(&mut self) {
        for ch in 0..2 {
            self.split1[ch].reset();
            self.split2[ch].reset();
            self.split_ap[ch].reset();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::dsp::Rng;
    use std::f32::consts::TAU;

    const RATE: f64 = 48_000.0;

    fn id(band: usize, k: u32) -> u32 {
        p::BAND_BASE + band as u32 * p::BAND_STRIDE + k
    }

    fn sine(freq: f32, amp: f32, n: usize) -> Vec<f32> {
        (0..n).map(|i| amp * (TAU * freq * i as f32 / RATE as f32).sin()).collect()
    }

    fn run(m: &mut Multiband, src: &[f32]) -> Vec<f32> {
        let (mut l, mut r) = (src.to_vec(), src.to_vec());
        for (cl, cr) in l.chunks_mut(128).zip(r.chunks_mut(128)) {
            m.process(cl, cr);
        }
        l
    }

    fn rms(x: &[f32]) -> f32 {
        (x.iter().map(|v| (*v as f64).powi(2)).sum::<f64>() / x.len() as f64).sqrt() as f32
    }

    fn db(x: f32) -> f32 {
        20.0 * x.log10()
    }

    /// Sem compressão (limiares em 0 dB, sinal baixo), a soma das bandas é passa-tudo: o ganho de
    /// cada frequência fica a menos de 0,05 dB de zero.
    #[test]
    fn soma_plana() {
        for (lo, hi) in [(150.0, 3000.0), (60.0, 1200.0), (700.0, 11000.0)] {
            let mut m = Multiband::new(RATE);
            m.set_param(p::XOVER_LOW, lo);
            m.set_param(p::XOVER_HIGH, hi);
            for b in 0..BANDS {
                m.set_param(id(b, p::BAND_THRESHOLD), 0.0);
            }
            let mut f = 30.0f32;
            while f < 18_000.0 {
                // frequência inteira e janela de 1 s: ciclos inteiros, sem erro de medida
                f = f.round();
                let src = sine(f, 0.01, 96_000);
                let out = run(&mut m, &src);
                let gain = db(rms(&out[48_000..]) / rms(&src[48_000..]));
                assert!(gain.abs() < 0.05, "{lo}/{hi} Hz, {f} Hz: {gain} dB");
                f *= 1.19;
            }
        }
    }

    /// Ruído branco: a energia toda passa (soma passa-tudo).
    #[test]
    fn ruido_passa_intacto_em_energia() {
        let mut m = Multiband::new(RATE);
        for b in 0..BANDS {
            m.set_param(id(b, p::BAND_THRESHOLD), 0.0);
        }
        let mut rng = Rng::new(9);
        let src: Vec<f32> = (0..96_000).map(|_| rng.bipolar() * 0.05).collect();
        let out = run(&mut m, &src);
        assert!(db(rms(&out[2000..]) / rms(&src[2000..])).abs() < 0.05);
    }

    #[test]
    fn so_a_banda_certa_comprime() {
        // 1 kHz cai na banda média (150 Hz..3 kHz): −10 dB com limiar −30 e 4:1 → −15 dB
        let mut m = Multiband::new(RATE);
        for b in 0..BANDS {
            m.set_param(id(b, p::BAND_THRESHOLD), if b == 1 { -30.0 } else { 0.0 });
            m.set_param(id(b, p::BAND_KNEE), 0.0);
            m.set_param(id(b, p::BAND_RATIO), 4.0);
            m.set_param(id(b, p::BAND_ATTACK), 0.001);
        }
        let amp = 10f32.powf(-10.0 / 20.0);
        let out = run(&mut m, &sine(1000.0, amp, 48_000));
        let gr = db(amp / (out[40_000..].iter().fold(0.0f32, |a, v| a.max(v.abs()))));
        assert!((gr - 15.0).abs() < 1.0, "reduziu {gr} dB");
        let meters = unpack_meter(m.meter());
        assert!((meters[1] - 15.0).abs() < 1.0, "{meters:?}");
        assert!(meters[0] < 0.5 && meters[2] < 0.5, "{meters:?}");
    }

    #[test]
    fn bandas_independentes() {
        // um grave forte não abaixa o agudo: dois senos, só a banda baixa comprimindo
        let mut m = Multiband::new(RATE);
        for b in 0..BANDS {
            m.set_param(id(b, p::BAND_THRESHOLD), if b == 0 { -40.0 } else { 0.0 });
            m.set_param(id(b, p::BAND_RATIO), 20.0);
            m.set_param(id(b, p::BAND_KNEE), 0.0);
        }
        let n = 48_000;
        let hi_alone: Vec<f32> = sine(6000.0, 0.1, n);
        let mix: Vec<f32> = sine(80.0, 0.7, n).iter().zip(&hi_alone).map(|(a, b)| a + b).collect();
        let out = run(&mut m, &mix);
        // amplitude do componente de 6 kHz por correlação em quadratura
        let w = TAU * 6000.0 / RATE as f32;
        let (mut c, mut q) = (0.0f64, 0.0f64);
        for (i, v) in out.iter().enumerate().skip(30_000) {
            c += (*v * (w * i as f32).cos()) as f64;
            q += (*v * (w * i as f32).sin()) as f64;
        }
        let amp = 2.0 * (c * c + q * q).sqrt() / (n - 30_000) as f64;
        let gain = 20.0 * (amp / 0.1).log10();
        assert!(gain.abs() < 0.3, "o agudo mexeu {gain} dB");
    }

    #[test]
    fn solo_bypass_e_compensacao() {
        let amp = 0.05;
        let n = 48_000;
        let base = |m: &mut Multiband| {
            for b in 0..BANDS {
                m.set_param(id(b, p::BAND_THRESHOLD), 0.0);
            }
        };
        // solo na média: um seno de 30 Hz (banda baixa, 2,3 oitavas abaixo do cruzamento) some
        let mut m = Multiband::new(RATE);
        base(&mut m);
        m.set_param(id(1, p::BAND_SOLO), 1.0);
        let out = run(&mut m, &sine(30.0, amp, n));
        assert!(db(rms(&out[30_000..]) / (amp / 2f32.sqrt())) < -40.0);
        // solo na baixa: o mesmo seno passa
        m.set_param(id(1, p::BAND_SOLO), 0.0);
        m.set_param(id(0, p::BAND_SOLO), 1.0);
        let out = run(&mut m, &sine(30.0, amp, n));
        assert!(db(rms(&out[30_000..]) / (amp / 2f32.sqrt())).abs() < 0.5);
        // sem solo, compensação de +6 dB na média: 1 kHz sobe 6 dB
        let mut m = Multiband::new(RATE);
        base(&mut m);
        m.set_param(id(1, p::BAND_MAKEUP), 6.0);
        let out = run(&mut m, &sine(1000.0, amp, n));
        assert!((db(rms(&out[30_000..]) / (amp / 2f32.sqrt())) - 6.0).abs() < 0.2);
        // bypass da banda com limiar baixo: sem redução, sem compensação
        let mut m = Multiband::new(RATE);
        base(&mut m);
        m.set_param(id(1, p::BAND_THRESHOLD), -60.0);
        m.set_param(id(1, p::BAND_MAKEUP), 6.0);
        m.set_param(id(1, p::BAND_BYPASS), 1.0);
        let out = run(&mut m, &sine(1000.0, 0.5, n));
        assert!(db(rms(&out[30_000..]) / (0.5 / 2f32.sqrt())).abs() < 0.1);
        assert_eq!(unpack_meter(m.meter())[1], 0.0);
        // saída conjunta
        m.set_param(p::OUTPUT, -6.0);
        let out = run(&mut m, &sine(1000.0, 0.5, n));
        assert!((db(rms(&out[30_000..]) / (0.5 / 2f32.sqrt())) + 6.0).abs() < 0.1);
    }

    #[test]
    fn indicador_empacota_e_desempacota() {
        for gr in [[0.0, 0.0, 0.0], [1.5, 12.3, 25.5], [30.0, 0.1, 7.0]] {
            let v = pack_meter(gr);
            assert!((0.0..16_777_216.0).contains(&v));
            let back = unpack_meter(v);
            for (a, b) in gr.iter().zip(back) {
                assert!((a.min(25.5) - b).abs() < 0.051, "{gr:?} → {back:?}");
            }
        }
        assert_eq!(pack_meter([f32::NAN, -3.0, f32::INFINITY]), 0.0 + 0.0 + 0.0);
        assert_eq!(unpack_meter(f32::NAN), [0.0; 3]);
        assert_eq!(Multiband::new(RATE).latency(), 0);
    }

    #[test]
    fn extremos_sem_nan() {
        for rate in [8_000.0, 44_100.0, 192_000.0] {
            let mut m = Multiband::new(rate);
            let mut rng = Rng::new(5);
            for id in 0..40 {
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
            let (mut l, mut r) = (vec![0.1; 4096], vec![0.1; 4096]);
            m.process(&mut l, &mut r);
            assert!(l.iter().chain(&r).all(|v| v.is_finite()) && m.meter().is_finite());
            m.reset();
            let (mut l, mut r) = (vec![0.0; 128], vec![0.0; 128]);
            m.process(&mut l, &mut r);
            assert!(l.iter().chain(&r).all(|v| *v == 0.0));
        }
    }
}
