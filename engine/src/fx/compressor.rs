//! Compressor com detector de pico ou RMS, joelho suave e compressão paralela.
//!
//! Desenho de Giannoulis, Massberg e Reiss ("Digital Dynamic Range Compressor Design — A Tutorial
//! and Analysis", JAES 2012), na variante que eles recomendam: o computador de ganho trabalha no
//! domínio dB sobre o nível instantâneo (ou a média quadrática), e a balística entra depois, na
//! redução de ganho em dB, como um detector de pico com ramificação suave (smooth branching):
//! ataque quando a redução pedida sobe, soltura quando desce. É o que dá a soltura com cara de
//! analógico (a volta do ganho é exponencial em dB, sem o degrau de um retorno linear) e mantém
//! ataque e soltura independentes do limiar e da razão.
//!
//! Um log e uma exponencial por quadro: as da biblioteca são software no WASM, então usamos
//! aproximações polinomiais com erro abaixo de 0,0001 dB ([`fast_log2`], [`fast_exp2`]).

use std::f32::consts::{LN_2, SQRT_2};

use super::eq::Glide;
use crate::dsp::{FilterMode, Smoothed, Svf, smoothing};
use crate::effect::{Effect, compressor_param};

/// Janela do detector RMS (média quadrática deslizante de verdade, não um polo).
const RMS_SECS: f64 = 0.010;
/// Suavização de limiar, razão e joelho: mexer neles com som passando não pode pular, nem com
/// ataque de 0,1 ms. Eles ainda passam pela balística, que faz o segundo polo.
const SMOOTH_SECS: f32 = 0.010;
/// Ganho de saída e mistura vão direto ao áudio: dois polos (ver [`Glide`]) desta constante cada.
const GLIDE_SECS: f32 = 0.005;
/// dB de potência por unidade de log2 (10·log10(2)).
const DB_PER_LOG2: f32 = 3.010_3;
/// Unidades de log2 de amplitude por dB (log2(10)/20).
const LOG2_PER_DB: f32 = 0.166_096_4;

/// log2 de `x` > 0, com erro abaixo de 1e-6. Zero, negativo ou denormal dão o piso de −126.
#[inline]
pub(crate) fn fast_log2(x: f32) -> f32 {
    let x = x.max(f32::MIN_POSITIVE);
    let bits = x.to_bits();
    let mut e = ((bits >> 23) & 0xff) as i32 - 127;
    let mut m = f32::from_bits((bits & 0x007f_ffff) | 0x3f80_0000);
    // mantissa em [√½, √2): t = (m − 1)/(m + 1) fica em ±0,172 e a série de atanh converge rápido
    if m > SQRT_2 {
        m *= 0.5;
        e += 1;
    }
    let t = (m - 1.0) / (m + 1.0);
    let t2 = t * t;
    // log2(m) = (2/ln 2)·(t + t³/3 + t⁵/5 + t⁷/7 + …)
    e as f32 + t * (2.885_39 + t2 * (0.961_796_7 + t2 * (0.577_078 + t2 * 0.412_198_6)))
}

/// 2^`x`, com erro relativo abaixo de 1e-6, para `x` em −126..127 (fora disso, limitado).
#[inline]
pub(crate) fn fast_exp2(x: f32) -> f32 {
    let x = x.clamp(-126.0, 127.0);
    let fl = x.floor();
    // 2^(x − ⌊x⌋) = √2 · e^(u), u em ±ln(2)/2: Taylor de grau 6 basta
    let u = (x - fl - 0.5) * LN_2;
    let p = 1.0 + u * (1.0 + u * (0.5 + u * (1.0 / 6.0 + u * (1.0 / 24.0 + u * (1.0 / 120.0 + u * (1.0 / 720.0))))));
    p * SQRT_2 * f32::from_bits(((fl as i32 + 127) as u32) << 23)
}

/// Redução de ganho em dB (≥ 0) para um nível `over` dB acima do limiar, com `slope` = 1 − 1/razão
/// e joelho de `knee` dB: quadrática dentro do joelho, que emenda sem quina nas duas retas.
#[inline]
pub(crate) fn reduction(over: f32, slope: f32, knee: f32) -> f32 {
    if 2.0 * over.abs() <= knee && knee > 0.0 {
        let t = over + 0.5 * knee;
        slope * t * t / (2.0 * knee)
    } else if over > 0.0 {
        slope * over
    } else {
        0.0
    }
}

/// Coeficiente de um polo com constante de tempo `secs` (63% do caminho).
fn time_coef(secs: f32, rate: f32) -> f32 {
    (-1.0 / (secs * rate)).exp()
}

pub struct Compressor {
    rate: f32,
    /// Alvos crus, para o ganho automático.
    threshold_db: f32,
    ratio: f32,
    makeup_db: f32,
    auto_makeup: bool,
    threshold: Smoothed,
    /// 1 − 1/razão: a fração do excesso que vira redução.
    slope: Smoothed,
    knee: Smoothed,
    /// Ganho de saída total em dB (manual + automático).
    makeup: Glide,
    mix: Glide,
    attack: f32,
    release: f32,
    /// 0 = pico, 1 = RMS; suavizado, para trocar de detector sem o nível medido pular (com ataque
    /// curto, o pulo de até 3 dB viraria um tranco no ganho).
    detector: Smoothed,
    /// Janela RMS: potência (máximo dos canais) de cada quadro, anel com soma corrida.
    window: Vec<f32>,
    wpos: usize,
    wsum: f64,
    sc_hpf: [Svf; 2],
    /// Redução de ganho suavizada, dB.
    env: f32,
    meter: f32,
    smooth: f32,
    glide: f32,
    fresh: bool,
}

impl Compressor {
    pub fn new(rate: f64) -> Self {
        let len = ((RMS_SECS * rate).round() as usize).max(1);
        let rate = rate as f32;
        let mut c = Self {
            rate,
            threshold_db: -18.0,
            ratio: 4.0,
            makeup_db: 0.0,
            auto_makeup: false,
            threshold: Smoothed::new(-18.0),
            slope: Smoothed::new(0.75),
            knee: Smoothed::new(6.0),
            makeup: Glide::new(0.0),
            mix: Glide::new(1.0),
            attack: time_coef(0.01, rate),
            release: time_coef(0.15, rate),
            detector: Smoothed::new(1.0),
            window: vec![0.0; len],
            wpos: 0,
            wsum: 0.0,
            sc_hpf: [Svf::default(); 2],
            env: 0.0,
            meter: 0.0,
            smooth: smoothing(SMOOTH_SECS, 1, rate),
            glide: smoothing(GLIDE_SECS, 1, rate),
            fresh: true,
        };
        c.set_sc_hpf(20.0);
        c
    }

    fn set_sc_hpf(&mut self, freq: f32) {
        let g = Svf::g(freq.min(0.45 * self.rate), self.rate);
        for f in &mut self.sc_hpf {
            f.set(g, SQRT_2);
        }
    }

    fn update_makeup(&mut self) {
        // ganho automático: metade do que falta a um sinal em 0 dBFS, um meio-termo que não estoura
        // com material que mal encosta no limiar
        let auto = if self.auto_makeup { -self.threshold_db * (1.0 - 1.0 / self.ratio) * 0.5 } else { 0.0 };
        self.makeup.set(self.makeup_db + auto);
    }

    fn snap(&mut self) {
        self.threshold.snap();
        self.slope.snap();
        self.knee.snap();
        self.detector.snap();
        self.makeup.snap();
        self.mix.snap();
    }
}

impl Effect for Compressor {
    fn set_param(&mut self, id: u32, value: f32) {
        if !value.is_finite() {
            return;
        }
        match id {
            compressor_param::THRESHOLD => {
                self.threshold_db = value.clamp(-60.0, 0.0);
                self.threshold.set(self.threshold_db);
                self.update_makeup();
            }
            compressor_param::RATIO => {
                self.ratio = value.clamp(1.0, 20.0);
                self.slope.set(1.0 - 1.0 / self.ratio);
                self.update_makeup();
            }
            compressor_param::ATTACK => self.attack = time_coef(value.clamp(0.0001, 0.25), self.rate),
            compressor_param::RELEASE => self.release = time_coef(value.clamp(0.005, 3.0), self.rate),
            compressor_param::KNEE => self.knee.set(value.clamp(0.0, 24.0)),
            compressor_param::MAKEUP => {
                self.makeup_db = value.clamp(0.0, 36.0);
                self.update_makeup();
            }
            compressor_param::MIX => self.mix.set(value.clamp(0.0, 1.0)),
            compressor_param::DETECTOR => self.detector.set(if value >= 0.5 { 1.0 } else { 0.0 }),
            compressor_param::SC_HPF => self.set_sc_hpf(value.clamp(20.0, 500.0)),
            compressor_param::AUTO_MAKEUP => {
                self.auto_makeup = value >= 0.5;
                self.update_makeup();
            }
            // SIDECHAIN: o motor escolhe a chave e entrega em `process_keyed`
            _ => return,
        }
        if self.fresh {
            self.snap();
        }
    }

    fn process(&mut self, left: &mut [f32], right: &mut [f32]) {
        self.process_keyed(left, right, None);
    }

    fn process_keyed(&mut self, left: &mut [f32], right: &mut [f32], key: Option<(&[f32], &[f32])>) {
        self.fresh = false;
        let a = self.smooth;
        let len = self.window.len();
        let inv_len = 1.0 / len as f64;
        let mut peak = 0.0f32;
        for (i, (l, r)) in left.iter_mut().zip(right.iter_mut()).enumerate() {
            let (kl, kr) = match key {
                // chave mais curta que o bloco (não deveria acontecer): o que falta é silêncio
                Some((kl, kr)) => (kl.get(i).copied().unwrap_or(0.0), kr.get(i).copied().unwrap_or(0.0)),
                None => (*l, *r),
            };
            let kl = self.sc_hpf[0].tick(kl, FilterMode::HighPass).0;
            let kr = self.sc_hpf[1].tick(kr, FilterMode::HighPass).0;
            // estéreo ligado: o canal mais forte manda; `min` também doma um infinito (e um NaN,
            // que `max`/`min` descartam)
            let p = (kl * kl).max(kr * kr).min(1e10);
            // a janela anda sempre, para trocar de detector no meio sem buraco
            self.wsum += (p - self.window[self.wpos]) as f64;
            self.window[self.wpos] = p;
            self.wpos += 1;
            if self.wpos == len {
                self.wpos = 0;
                // a soma corrida acumula erro de arredondamento: recalcula a cada volta
                self.wsum = self.window.iter().map(|&v| v as f64).sum();
            }
            let rms = (self.wsum * inv_len).max(0.0) as f32;
            let power = p + self.detector.step(a) * (rms - p);
            let level = DB_PER_LOG2 * fast_log2(power.max(1e-20));
            let threshold = self.threshold.step(a);
            let slope = self.slope.step(a);
            let knee = self.knee.step(a);
            let gr = reduction(level - threshold, slope, knee);
            let coef = if gr > self.env { self.attack } else { self.release };
            self.env = gr + (self.env - gr) * coef;
            let makeup = self.makeup.step(self.glide);
            let mix = self.mix.step(self.glide);
            let g = fast_exp2((makeup - self.env) * LOG2_PER_DB);
            let m = 1.0 + mix * (g - 1.0);
            *l *= m;
            *r *= m;
            peak = peak.max(self.env);
        }
        self.meter = peak;
        if self.env < 1e-9 {
            self.env = 0.0;
        }
        for f in &mut self.sc_hpf {
            f.flush();
            if !f.is_finite() {
                f.reset();
            }
        }
        if !self.wsum.is_finite() {
            self.window.fill(0.0);
            self.wsum = 0.0;
        }
    }

    fn reset(&mut self) {
        self.window.fill(0.0);
        self.wpos = 0;
        self.wsum = 0.0;
        for f in &mut self.sc_hpf {
            f.reset();
        }
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
    use crate::effect::compressor_param as p;

    const RATE: f64 = 48_000.0;

    fn db(x: f32) -> f32 {
        20.0 * x.abs().log10()
    }

    fn amp(db: f32) -> f32 {
        10f32.powf(db / 20.0)
    }

    /// Onda quadrada de ±`a` (6 kHz): o pico e o RMS são o mesmo nível, então pico e RMS têm de
    /// concordar. Rápida para o passa-alta de 20 Hz da chave não inclinar o topo.
    fn square(a: f32, n: usize) -> Vec<f32> {
        (0..n).map(|i| if (i / 4) % 2 == 0 { a } else { -a }).collect()
    }

    fn run(c: &mut Compressor, src: &[f32]) -> Vec<f32> {
        let (mut l, mut r) = (src.to_vec(), src.to_vec());
        for (cl, cr) in l.chunks_mut(128).zip(r.chunks_mut(128)) {
            c.process(cl, cr);
        }
        l
    }

    fn peak(x: &[f32]) -> f32 {
        x.iter().fold(0.0f32, |m, v| m.max(v.abs()))
    }

    fn comp(threshold: f32, ratio: f32, knee: f32) -> Compressor {
        let mut c = Compressor::new(RATE);
        c.set_param(p::THRESHOLD, threshold);
        c.set_param(p::RATIO, ratio);
        c.set_param(p::KNEE, knee);
        c.set_param(p::ATTACK, 0.001);
        c.set_param(p::RELEASE, 0.1);
        c
    }

    #[test]
    fn log_e_exp_rapidos_conferem() {
        let mut x = 1e-30f32;
        while x < 1e30 {
            let err = (fast_log2(x) as f64 - (x as f64).log2()).abs();
            assert!(err < 1e-5, "log2({x}): erro {err}");
            x *= 1.37;
        }
        let mut x = -120.0f32;
        while x < 120.0 {
            let (got, want) = (fast_exp2(x), x.exp2());
            assert!((got / want - 1.0).abs() < 2e-6, "2^{x}: {got} ≠ {want}");
            x += 0.173;
        }
        assert_eq!(fast_log2(0.0), -126.0);
        assert!(fast_log2(-1.0).is_finite());
    }

    #[test]
    fn razao_4_para_1_no_regime() {
        // 20 dB acima do limiar a 4:1: sai 5 dB acima, 15 dB de redução
        for detector in [0.0, 1.0] {
            let mut c = comp(-30.0, 4.0, 0.0);
            c.set_param(p::DETECTOR, detector);
            let out = run(&mut c, &square(amp(-10.0), 48_000));
            let level = db(peak(&out[40_000..]));
            assert!((level + 25.0).abs() < 0.2, "detector {detector}: saiu {level} dB");
            assert!((c.meter() - 15.0).abs() < 0.2, "detector {detector}: medidor {}", c.meter());
        }
        // senoide no RMS: o nível é o do valor eficaz (−13 dB para pico de −10), 17 dB acima
        let mut c = comp(-30.0, 4.0, 0.0);
        c.set_param(p::DETECTOR, 1.0);
        c.set_param(p::RELEASE, 1.0);
        let sine: Vec<f32> = (0..48_000).map(|i| amp(-10.0) * (i as f32 * 0.0654).sin()).collect();
        run(&mut c, &sine);
        assert!((c.meter() - 12.75).abs() < 0.3, "RMS da senoide: {}", c.meter());
    }

    #[test]
    fn abaixo_do_limiar_nao_mexe() {
        let mut c = comp(-20.0, 8.0, 0.0);
        let src = square(amp(-30.0), 9600);
        let out = run(&mut c, &src);
        assert!(out.iter().zip(&src).all(|(a, b)| (a - b).abs() < 1e-6));
        assert_eq!(c.meter(), 0.0);
    }

    #[test]
    fn joelho_suave() {
        // no limiar, com joelho de 12 dB: (1 − 1/4)·6²/(2·12) = 1,125 dB
        let mut c = comp(-20.0, 4.0, 12.0);
        run(&mut c, &square(amp(-20.0), 24_000));
        assert!((c.meter() - 1.125).abs() < 0.05, "{}", c.meter());
        // e a curva é contínua e monótona através do joelho
        let mut last = 0.0;
        for i in 0..400 {
            let over = -10.0 + i as f32 * 0.05;
            let gr = reduction(over, 0.75, 12.0);
            assert!(gr >= last - 1e-6 && gr - last < 0.05, "{over}: {gr}");
            last = gr;
        }
        assert!((reduction(10.0, 0.75, 12.0) - 7.5).abs() < 1e-5);
    }

    #[test]
    fn ganho_automatico() {
        // −30 dB a 4:1: 30·0,75/2 = 11,25 dB; um sinal abaixo do limiar só sobe
        let mut c = comp(-30.0, 4.0, 0.0);
        c.set_param(p::AUTO_MAKEUP, 1.0);
        let out = run(&mut c, &square(amp(-40.0), 9600));
        let gain = db(peak(&out[4800..])) + 40.0;
        assert!((gain - 11.25).abs() < 0.05, "{gain}");
        // somado ao manual
        c.set_param(p::MAKEUP, 3.0);
        let out = run(&mut c, &square(amp(-40.0), 9600));
        let gain = db(peak(&out[4800..])) + 40.0;
        assert!((gain - 14.25).abs() < 0.05, "{gain}");
    }

    #[test]
    fn mistura_paralela() {
        let mut c = comp(-40.0, 20.0, 0.0);
        c.set_param(p::MIX, 0.0);
        let src = square(0.5, 9600);
        let out = run(&mut c, &src);
        assert!(out.iter().zip(&src).all(|(a, b)| (a - b).abs() < 1e-6));
        assert!(c.meter() > 10.0, "o detector segue medindo");
        // metade: a seca a −6 dB mais a comprimida bem baixa
        c.set_param(p::MIX, 0.5);
        let out = run(&mut c, &src);
        let level = peak(&out[8000..]);
        assert!(level > 0.25 && level < 0.3, "{level}");
    }

    #[test]
    fn chave_externa() {
        let mut c = comp(-30.0, 10.0, 0.0);
        let src = square(amp(-40.0), 128);
        let key = square(amp(-6.0), 128);
        let mut last = 0.0;
        for _ in 0..100 {
            let (mut l, mut r) = (src.clone(), src.clone());
            c.process_keyed(&mut l, &mut r, Some((&key, &key)));
            last = peak(&l);
        }
        // a chave está 24 dB acima: 21,6 dB de redução num sinal que sozinho nem chega ao limiar
        assert!((db(last) + 40.0 + 21.6).abs() < 0.3, "{}", db(last));
        // chave só num canal também comprime os dois
        let silent = vec![0.0; 128];
        let (mut l, mut r) = (src.clone(), src.clone());
        c.process_keyed(&mut l, &mut r, Some((&silent, &key)));
        assert!(db(peak(&r)) < -55.0);
    }

    #[test]
    fn passa_alta_na_chave() {
        let bass: Vec<f32> = (0..48_000).map(|i| 0.5 * (i as f32 * std::f32::consts::TAU * 40.0 / 48_000.0).sin()).collect();
        let mut plain = comp(-30.0, 4.0, 0.0);
        plain.set_param(p::DETECTOR, 0.0);
        run(&mut plain, &bass);
        let mut filtered = comp(-30.0, 4.0, 0.0);
        filtered.set_param(p::DETECTOR, 0.0);
        filtered.set_param(p::SC_HPF, 500.0);
        run(&mut filtered, &bass);
        // 40 Hz está 3,6 oitavas abaixo de 500 Hz: −43 dB na chave, quase nada a comprimir
        assert!(plain.meter() > 15.0, "{}", plain.meter());
        assert!(filtered.meter() < 1.0, "{}", filtered.meter());
    }

    #[test]
    fn soltura_devolve_o_ganho() {
        let mut c = comp(-30.0, 4.0, 0.0);
        c.set_param(p::DETECTOR, 0.0);
        c.set_param(p::RELEASE, 0.05);
        run(&mut c, &square(0.5, 24_000));
        assert!(c.meter() > 10.0);
        // 0,5 s depois (10 constantes de tempo), a redução praticamente sumiu
        run(&mut c, &vec![0.0; 24_000]);
        assert!(c.meter() < 0.01, "{}", c.meter());
    }

    #[test]
    fn mexer_no_limiar_nao_pula() {
        let mut c = comp(-10.0, 20.0, 0.0);
        c.set_param(p::ATTACK, 0.0001);
        let src: Vec<f32> = (0..48_000).map(|i| 0.5 * (i as f32 * 0.02).sin()).collect();
        let (mut l, mut r) = (src.clone(), src.clone());
        for (i, (cl, cr)) in l.chunks_mut(128).zip(r.chunks_mut(128)).enumerate() {
            if i == 150 {
                c.set_param(p::THRESHOLD, -60.0);
            }
            c.process(cl, cr);
        }
        // a senoide anda no máximo 0,01 por quadro, e o ganho descendo 48 dB em ~30 ms soma pouco a
        // isso; sem suavizar o limiar, o ataque de 0,1 ms derrubaria o ganho em ~15 quadros
        let step = l.windows(2).fold(0.0f32, |m, w| m.max((w[1] - w[0]).abs()));
        assert!(step < 0.02, "{step}");
    }

    #[test]
    fn extremos_sem_nan() {
        for rate in [8_000.0, 44_100.0, 192_000.0] {
            let mut c = Compressor::new(rate);
            let mut rng = crate::dsp::Rng::new(3);
            for (id, v) in [(0, -1e9), (1, 1e9), (2, 0.0), (3, -1.0), (4, 1e9), (5, 1e9), (6, 7.0), (7, 3.0), (8, 1e9), (9, 1.0), (10, 5.0), (77, 1.0)] {
                c.set_param(id, v);
                c.set_param(id, f32::NAN);
                c.set_param(id, f32::INFINITY);
            }
            let (mut l, mut r): (Vec<f32>, Vec<f32>) = (0..8192).map(|_| (rng.bipolar() * 1e6, 0.0)).unzip();
            for (cl, cr) in l.chunks_mut(100).zip(r.chunks_mut(100)) {
                c.process(cl, cr);
            }
            assert!(l.iter().chain(&r).all(|v| v.is_finite()), "taxa {rate}");
            let (mut l, mut r) = (vec![f32::NAN; 64], vec![f32::INFINITY; 64]);
            c.process(&mut l, &mut r);
            let (mut l, mut r) = (vec![0.1; 4096], vec![0.1; 4096]);
            c.process(&mut l, &mut r);
            assert!(l.iter().chain(&r).all(|v| v.is_finite()) && c.meter().is_finite());
            for _ in 0..500 {
                let (mut l, mut r) = (vec![0.0; 128], vec![0.0; 128]);
                c.process(&mut l, &mut r);
            }
            assert!(c.env == 0.0 || c.env > 1e-9);
        }
    }
}
