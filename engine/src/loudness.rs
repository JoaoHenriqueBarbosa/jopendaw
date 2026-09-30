//! Medição de loudness do master: ITU-R BS.1770-4 e EBU R128 (Tech 3341 e 3342).
//!
//! - Filtro K-weighting (prateleira de agudos + passa-altas) calculado para a taxa do motor.
//! - Energia por bloco de 100 ms; o **momentâneo** é a média dos últimos 4 blocos (janela de
//!   400 ms) e o **curto prazo** a dos últimos 30 (3 s).
//! - **Integrado**: os blocos de 400 ms (a cada 100 ms, 75 % de sobreposição) passam pelo gate
//!   absoluto de −70 LUFS e, depois, pelo relativo de −10 LU abaixo da média do que passou.
//! - **Faixa de loudness** (LRA, Tech 3342): distribuição do curto prazo com gate absoluto de
//!   −70 LUFS e relativo de −20 LU; diferença entre os percentis 95 e 10.
//! - **True peak**: sobreamostragem 4× (FIR polifásico, janela de Kaiser) e o maior valor
//!   absoluto visto desde o reset, em dBTP.
//!
//! O medidor não aloca depois de criado: os blocos moram num anel e as distribuições dos gates em
//! histogramas de 0,01 LU (a energia de cada faixa do histograma é somada exata, então a
//! quantização só decide de que lado do gate um bloco cai, com erro de no máximo 0,01 LU). Por
//! isso a thread de áudio pode alimentá-lo direto ([`Meter::push`]). Fora do tempo real,
//! [`measure`] mede um trecho inteiro de uma vez.
//!
//! Valores em LUFS/LU/dBTP; [`NONE`] (−200) é "sem medida": menos de 400 ms de áudio, tudo abaixo
//! do gate ou silêncio. Nunca sai NaN nem infinito: amostras não finitas contam como silêncio.

use std::f64::consts::PI;

use crate::Engine;

/// "Sem medida" (também o piso: o que fica abaixo disso vira isso).
pub const NONE: f64 = -200.0;

/// Blocos de 100 ms que formam a janela do momentâneo (400 ms).
const MOMENTARY_HOPS: usize = 4;
/// ... e a do curto prazo (3 s).
const SHORT_HOPS: usize = 30;
/// Gate absoluto (LUFS).
const ABSOLUTE_GATE: f64 = -70.0;
/// Gate relativo do integrado (LU abaixo da média) e o da faixa de loudness.
const RELATIVE_GATE: f64 = -10.0;
const RANGE_GATE: f64 = -20.0;
/// Constante da BS.1770: ajusta a energia K-ponderada para LUFS (o ganho do filtro a 997 Hz).
const OFFSET: f64 = -0.691;

/// Histograma dos gates: de −70 a +10 LUFS em faixas de 0,01 LU (acima do teto vai na última).
const BIN: f64 = 0.01;
const BINS: usize = 8000;

/// Sobreamostragem do true peak e amostras de cada lado que o filtro de cada fase enxerga
/// (16 pontos por fase, 64 no protótipo).
const OVERSAMPLE: usize = 4;
const HALF: usize = 8;
const TAPS: usize = 2 * HALF;
/// Beta da janela de Kaiser do interpolador.
const KAISER_BETA: f64 = 7.0;

/// Quais medidas a chamada `loudness(kind)` devolve.
pub mod kind {
    /// Momentâneo (400 ms), LUFS.
    pub const MOMENTARY: u32 = 0;
    /// Curto prazo (3 s), LUFS.
    pub const SHORT_TERM: u32 = 1;
    /// Integrado desde o reset, LUFS.
    pub const INTEGRATED: u32 = 2;
    /// True peak máximo desde o reset, dBTP.
    pub const TRUE_PEAK: u32 = 3;
    /// Faixa de loudness (LRA), LU.
    pub const RANGE: u32 = 4;
}

/// O resultado de uma medição.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Loudness {
    /// Última janela de 400 ms fechada (LUFS).
    pub momentary: f64,
    /// Maior momentâneo desde o reset.
    pub momentary_max: f64,
    /// Última janela de 3 s fechada (LUFS).
    pub short_term: f64,
    /// Maior curto prazo desde o reset.
    pub short_term_max: f64,
    /// Integrado com os dois gates (LUFS).
    pub integrated: f64,
    /// True peak máximo (dBTP).
    pub true_peak: f64,
    /// Faixa de loudness (LU).
    pub range: f64,
}

impl Loudness {
    pub const EMPTY: Loudness =
        Loudness { momentary: NONE, momentary_max: NONE, short_term: NONE, short_term_max: NONE, integrated: NONE, true_peak: NONE, range: NONE };
}

fn lufs(energy: f64) -> f64 {
    if energy > 0.0 && energy.is_finite() { (OFFSET + 10.0 * energy.log10()).max(NONE) } else { NONE }
}

fn db(linear: f64) -> f64 {
    if linear > 0.0 && linear.is_finite() { (20.0 * linear.log10()).max(NONE) } else { NONE }
}

// ---------------------------------------------------------------- K-weighting

/// Biquad em forma transposta II, em f64 (o passa-altas de 38 Hz numa taxa alta pede a precisão).
#[derive(Clone, Copy)]
struct Biquad {
    b: [f64; 3],
    a: [f64; 2],
    z: [f64; 2],
}

impl Biquad {
    fn run(&mut self, x: f64) -> f64 {
        let y = self.b[0] * x + self.z[0];
        self.z[0] = self.b[1] * x - self.a[0] * y + self.z[1];
        self.z[1] = self.b[2] * x - self.a[1] * y;
        y
    }
}

/// Prateleira de agudos (+4 dB acima de ~1,7 kHz) e passa-altas (~38 Hz) da BS.1770, com os
/// coeficientes derivados dos protótipos analógicos para qualquer taxa (os da norma são só para
/// 48 kHz).
fn k_weighting(rate: f64) -> [Biquad; 2] {
    let (f0, gain, q) = (1_681.974_450_955_533, 3.999_843_853_973_347, 0.707_175_236_955_419_6);
    let k = (PI * f0 / rate).tan();
    let vh = 10f64.powf(gain / 20.0);
    let vb = vh.powf(0.499_666_774_154_541_6);
    let a0 = 1.0 + k / q + k * k;
    let shelf = Biquad {
        b: [(vh + vb * k / q + k * k) / a0, 2.0 * (k * k - vh) / a0, (vh - vb * k / q + k * k) / a0],
        a: [2.0 * (k * k - 1.0) / a0, (1.0 - k / q + k * k) / a0],
        z: [0.0; 2],
    };
    let (f0, q) = (38.135_470_876_024_44, 0.500_327_037_323_877_3);
    let k = (PI * f0 / rate).tan();
    let a0 = 1.0 + k / q + k * k;
    let high = Biquad { b: [1.0, -2.0, 1.0], a: [2.0 * (k * k - 1.0) / a0, (1.0 - k / q + k * k) / a0], z: [0.0; 2] };
    [shelf, high]
}

// ---------------------------------------------------------------- true peak

fn bessel_i0(x: f64) -> f64 {
    let (mut sum, mut term) = (1.0, 1.0);
    let q = x * x / 4.0;
    for k in 1..64 {
        term *= q / (k * k) as f64;
        sum += term;
        if term < sum * 1e-17 {
            break;
        }
    }
    sum
}

/// Interpolador 4× por fases (a fase 0 é a própria amostra): coeficientes das fases 1 a 3.
/// Cada fase soma 1 (ganho DC exato).
fn interpolator() -> [[f32; TAPS]; OVERSAMPLE - 1] {
    let norm = bessel_i0(KAISER_BETA);
    let mut out = [[0.0f32; TAPS]; OVERSAMPLE - 1];
    for (p, phase) in out.iter_mut().enumerate() {
        let frac = (p + 1) as f64 / OVERSAMPLE as f64;
        let mut taps = [0.0f64; TAPS];
        // `d` = idade da amostra no histórico (0 = a mais nova); o ponto interpolado fica entre a
        // de idade HALF e a de idade HALF − 1, `frac` depois da primeira
        for (d, tap) in taps.iter_mut().enumerate() {
            let t = (HALF as f64 - d as f64) - frac;
            let sinc = if t == 0.0 { 1.0 } else { (PI * t).sin() / (PI * t) };
            let r = t / HALF as f64;
            let window = if r.abs() < 1.0 { bessel_i0(KAISER_BETA * (1.0 - r * r).sqrt()) / norm } else { 0.0 };
            *tap = sinc * window;
        }
        let sum: f64 = taps.iter().sum();
        for (o, t) in phase.iter_mut().zip(taps) {
            *o = (t / sum) as f32;
        }
    }
    out
}

struct TruePeak {
    coef: [[f32; TAPS]; OVERSAMPLE - 1],
    /// Histórico de cada canal, o mais novo em 0.
    hist: [[f32; TAPS]; 2],
    /// Maior valor absoluto (linear) desde o reset.
    peak: f32,
}

impl TruePeak {
    fn new() -> Self {
        Self { coef: interpolator(), hist: [[0.0; TAPS]; 2], peak: 0.0 }
    }

    fn feed(&mut self, ch: usize, x: f32) {
        let h = &mut self.hist[ch];
        h.copy_within(0..TAPS - 1, 1);
        h[0] = x;
        // a amostra do meio do histórico é a fase 0 (o próprio valor)
        let mut peak = h[HALF].abs();
        for phase in &self.coef {
            let mut acc = 0.0f32;
            for (c, v) in phase.iter().zip(h.iter()) {
                acc += c * v;
            }
            peak = peak.max(acc.abs());
        }
        if peak > self.peak {
            self.peak = peak;
        }
    }
}

// ---------------------------------------------------------------- histogramas dos gates

/// Distribuição de valores de loudness em faixas de 0,01 LU, cada uma com a contagem e a soma das
/// energias (para a média exata depois do gate relativo).
struct Histogram {
    count: Vec<u32>,
    energy: Vec<f64>,
}

impl Histogram {
    fn new() -> Self {
        Self { count: vec![0; BINS], energy: vec![0.0; BINS] }
    }

    fn clear(&mut self) {
        self.count.fill(0);
        self.energy.fill(0.0);
    }

    /// Guarda um bloco de energia `energy` (loudness `l`), se passa do gate absoluto.
    fn add(&mut self, l: f64, energy: f64) {
        if l > ABSOLUTE_GATE {
            let bin = (((l - ABSOLUTE_GATE) / BIN) as usize).min(BINS - 1);
            self.count[bin] += 1;
            self.energy[bin] += energy;
        }
    }

    /// Média das energias (e quantas) das faixas de `from` em diante.
    fn mean_from(&self, from: usize) -> Option<(f64, u64)> {
        let from = from.min(BINS);
        let n: u64 = self.count[from..].iter().map(|&c| u64::from(c)).sum();
        if n == 0 {
            return None;
        }
        let e: f64 = self.energy[from..].iter().sum();
        Some((e / n as f64, n))
    }

    /// Primeira faixa cujo limite inferior fica em `gate` (LUFS) ou acima.
    fn bin_of(gate: f64) -> usize {
        (((gate - ABSOLUTE_GATE) / BIN).ceil().max(0.0)) as usize
    }

    /// Média depois do gate relativo `offset` LU abaixo da média dos que passaram do absoluto.
    fn gated(&self, offset: f64) -> Option<(f64, u64)> {
        let (all, _) = self.mean_from(0)?;
        self.mean_from(Self::bin_of(lufs(all) + offset))
    }

    /// Loudness do percentil `p` (0..1) das faixas de `from` em diante, com `total` valores.
    fn percentile(&self, from: usize, total: u64, p: f64) -> f64 {
        let target = (p * (total - 1) as f64).round() as u64;
        let mut seen = 0u64;
        for (i, &c) in self.count.iter().enumerate().skip(from) {
            seen += u64::from(c);
            if seen > target {
                return ABSOLUTE_GATE + (i as f64 + 0.5) * BIN;
            }
        }
        ABSOLUTE_GATE + BINS as f64 * BIN
    }
}

// ---------------------------------------------------------------- medidor

/// O medidor contínuo. Alimentado bloco a bloco com [`Meter::push`]; lido a qualquer momento com
/// [`Meter::read`]. Um canal só (`channels` = 1) mede a esquerda como sinal único; o motor sempre
/// usa dois.
pub struct Meter {
    channels: usize,
    filters: [[Biquad; 2]; 2],
    /// Quadros de cada bloco de 100 ms, o que já entrou no atual e a soma dos quadrados dos canais
    /// K-ponderados nele.
    hop: usize,
    filled: usize,
    acc: f64,
    /// Energia (média dos quadrados somada nos canais) dos últimos blocos, em anel.
    ring: [f64; SHORT_HOPS],
    ring_pos: usize,
    hops: usize,
    momentary: f64,
    momentary_max: f64,
    short_term: f64,
    short_term_max: f64,
    gated: Histogram,
    range: Histogram,
    true_peak: TruePeak,
    /// Integrado e faixa calculados desde o último bloco fechado (senão a leitura repetiria a
    /// soma dos histogramas a cada consulta).
    cache: Option<(f64, f64)>,
}

impl Meter {
    /// Medidor de `channels` (1 ou 2) na taxa `rate`.
    pub fn new(rate: f64, channels: usize) -> Self {
        let rate = if rate.is_finite() && rate >= 1000.0 { rate } else { 48_000.0 };
        let kw = k_weighting(rate);
        Self {
            channels: channels.clamp(1, 2),
            filters: [kw, kw],
            hop: ((rate * 0.1).round() as usize).max(1),
            filled: 0,
            acc: 0.0,
            ring: [0.0; SHORT_HOPS],
            ring_pos: 0,
            hops: 0,
            momentary: NONE,
            momentary_max: NONE,
            short_term: NONE,
            short_term_max: NONE,
            gated: Histogram::new(),
            range: Histogram::new(),
            true_peak: TruePeak::new(),
            cache: None,
        }
    }

    /// Esquece o que mediu (o integrado, a faixa, os máximos e o true peak). Os filtros seguem
    /// com o sinal que estão vendo, para o reset no meio da música não gerar transiente.
    pub fn reset(&mut self) {
        self.filled = 0;
        self.acc = 0.0;
        self.ring.fill(0.0);
        self.ring_pos = 0;
        self.hops = 0;
        self.momentary = NONE;
        self.momentary_max = NONE;
        self.short_term = NONE;
        self.short_term_max = NONE;
        self.gated.clear();
        self.range.clear();
        self.true_peak.peak = 0.0;
        self.cache = None;
    }

    /// Mede um pedaço do áudio. `right` faltando (ou de outro tamanho) mede só a esquerda; amostras
    /// não finitas contam como silêncio.
    pub fn push(&mut self, left: &[f32], right: Option<&[f32]>) {
        let right = right.filter(|r| self.channels == 2 && r.len() == left.len());
        for (i, &l) in left.iter().enumerate() {
            let l = if l.is_finite() { l } else { 0.0 };
            self.acc += self.weigh(0, l);
            self.true_peak.feed(0, l);
            if let Some(r) = right {
                let r = if r[i].is_finite() { r[i] } else { 0.0 };
                self.acc += self.weigh(1, r);
                self.true_peak.feed(1, r);
            }
            self.filled += 1;
            if self.filled == self.hop {
                self.close_hop();
            }
        }
    }

    fn weigh(&mut self, ch: usize, x: f32) -> f64 {
        let f = &mut self.filters[ch];
        let mid = f[0].run(f64::from(x));
        let y = f[1].run(mid);
        y * y
    }

    fn close_hop(&mut self) {
        let e = self.acc / self.hop as f64;
        self.acc = 0.0;
        self.filled = 0;
        self.ring[self.ring_pos] = if e.is_finite() { e } else { 0.0 };
        self.ring_pos = (self.ring_pos + 1) % SHORT_HOPS;
        self.hops = (self.hops + 1).min(SHORT_HOPS);
        self.cache = None;
        if self.hops >= MOMENTARY_HOPS {
            let e = self.mean_last(MOMENTARY_HOPS);
            let l = lufs(e);
            self.momentary = l;
            self.momentary_max = self.momentary_max.max(l);
            self.gated.add(l, e);
        }
        if self.hops >= SHORT_HOPS {
            let e = self.mean_last(SHORT_HOPS);
            let l = lufs(e);
            self.short_term = l;
            self.short_term_max = self.short_term_max.max(l);
            self.range.add(l, e);
        }
    }

    /// Média das energias dos últimos `n` blocos.
    fn mean_last(&self, n: usize) -> f64 {
        let sum: f64 = (0..n).map(|k| self.ring[(self.ring_pos + SHORT_HOPS - 1 - k) % SHORT_HOPS]).sum();
        sum / n as f64
    }

    /// Completa o true peak com o que falta do fim (as amostras que o interpolador só vê com as
    /// seguintes): alimenta zeros, como um sinal que acaba ali. Só para o uso offline.
    fn flush_true_peak(&mut self) {
        for _ in 0..HALF {
            for ch in 0..self.channels {
                self.true_peak.feed(ch, 0.0);
            }
        }
    }

    fn integrated_and_range(&mut self) -> (f64, f64) {
        if let Some(c) = self.cache {
            return c;
        }
        let integrated = self.gated.gated(RELATIVE_GATE).map_or(NONE, |(e, _)| lufs(e));
        let range = match self.range.mean_from(0) {
            Some((all, _)) => {
                let from = Histogram::bin_of(lufs(all) + RANGE_GATE);
                match self.range.mean_from(from) {
                    Some((_, total)) if total > 0 => {
                        let (lo, hi) = (self.range.percentile(from, total, 0.10), self.range.percentile(from, total, 0.95));
                        (hi - lo).max(0.0)
                    }
                    _ => NONE,
                }
            }
            None => NONE,
        };
        self.cache = Some((integrated, range));
        (integrated, range)
    }

    /// A medida de agora.
    pub fn read(&mut self) -> Loudness {
        let (integrated, range) = self.integrated_and_range();
        Loudness {
            momentary: self.momentary,
            momentary_max: self.momentary_max,
            short_term: self.short_term,
            short_term_max: self.short_term_max,
            integrated,
            true_peak: db(f64::from(self.true_peak.peak)),
            range,
        }
    }

    /// Uma medida só, por [`kind`]; tipo desconhecido é "sem medida".
    pub fn read_kind(&mut self, k: u32) -> f64 {
        let l = self.read();
        match k {
            kind::MOMENTARY => l.momentary,
            kind::SHORT_TERM => l.short_term,
            kind::INTEGRATED => l.integrated,
            kind::TRUE_PEAK => l.true_peak,
            kind::RANGE => l.range,
            _ => NONE,
        }
    }
}

/// Mede de uma vez um trecho inteiro (fora do tempo real). `right` vazio mede `left` como canal
/// único (a BS.1770 soma só os canais que existem: um seno de −20 dBFS sozinho dá −23 LUFS; o
/// mesmo nos dois canais, −20 LUFS). Menos de 400 ms não fecha nenhuma janela: momentâneo,
/// curto prazo, integrado e faixa saem [`NONE`]; o true peak sai sempre que há sinal.
pub fn measure(left: &[f32], right: &[f32], rate: f64) -> Loudness {
    let stereo = !right.is_empty() && right.len() == left.len();
    let mut m = Meter::new(rate, if stereo { 2 } else { 1 });
    m.push(left, if stereo { Some(right) } else { None });
    m.flush_true_peak();
    m.read()
}

impl Engine {
    /// Zera a medida de loudness do master (integrado, faixa, máximos e true peak).
    pub fn loudness_reset(&mut self) {
        self.loudness.reset();
    }

    /// Medida de loudness do master, por [`kind`]: 0 momentâneo, 1 curto prazo, 2 integrado (LUFS),
    /// 3 true peak máximo (dBTP), 4 faixa de loudness (LU). −200 quando não há medida.
    pub fn loudness(&mut self, kind: u32) -> f64 {
        self.loudness.read_kind(kind)
    }
}

#[cfg(test)]
mod tests {
    use std::f32::consts::TAU;

    use super::*;

    const RATE: f64 = 48_000.0;

    fn sine(hz: f32, amp: f32, secs: f64, rate: f64) -> Vec<f32> {
        (0..(secs * rate) as usize).map(|i| amp * (TAU * hz * i as f32 / rate as f32).sin()).collect()
    }

    fn dbfs(db: f32) -> f32 {
        10f32.powf(db / 20.0)
    }

    /// Ruído branco determinístico (LCG) em [−1, 1).
    fn noise(n: usize, seed: u64) -> Vec<f32> {
        let mut s = seed;
        (0..n)
            .map(|_| {
                s = s.wrapping_mul(6_364_136_223_846_793_005).wrapping_add(1_442_695_040_888_963_407);
                ((s >> 40) as f32 / (1u64 << 23) as f32) - 1.0
            })
            .collect()
    }

    fn near(a: f64, b: f64, tol: f64, what: &str) {
        assert!((a - b).abs() <= tol, "{what}: {a} não é {b} ± {tol}");
    }

    #[test]
    fn seno_estereo_em_fase_mede_o_proprio_nivel() {
        // EBU Tech 3341, caso 1: 1 kHz nos dois canais a −20 dBFS de pico dá −20 LUFS
        let s = sine(1000.0, dbfs(-20.0), 5.0, RATE);
        let l = measure(&s, &s, RATE);
        near(l.integrated, -20.0, 0.1, "integrado");
        near(l.momentary, -20.0, 0.1, "momentâneo");
        near(l.short_term, -20.0, 0.1, "curto prazo");
        near(l.true_peak, -20.0, 0.1, "true peak");
        // sinal constante: a faixa de loudness é nula
        near(l.range, 0.0, 0.1, "faixa");
    }

    #[test]
    fn canal_unico_mede_3_db_abaixo_do_par() {
        // a norma soma os canais que existem: um só carrega metade da energia
        let s = sine(1000.0, dbfs(-20.0), 5.0, RATE);
        let mono = measure(&s, &[], RATE);
        near(mono.integrated, -23.01, 0.1, "canal único");
        let dual = measure(&s, &s, RATE);
        near(mono.integrated, dual.integrated - 3.01, 0.02, "canal único contra dois iguais");
        // só um lado com sinal: mesma medida do canal único
        let silent = vec![0.0f32; s.len()];
        near(measure(&s, &silent, RATE).integrated, mono.integrated, 0.01, "esquerda com direita muda");
        // tamanhos diferentes: trata como canal único (e não pânico)
        near(measure(&s, &s[..100], RATE).integrated, mono.integrated, 0.01, "tamanhos diferentes");
    }

    #[test]
    fn a_ponderacao_k_muda_com_a_frequencia() {
        // a 100 Hz o passa-altas tira ~1,2 dB (e a 1 kHz a prateleira já pôs +0,7); a 10 kHz a
        // prateleira sobe ~+4 dB
        let amp = dbfs(-20.0);
        let at = |hz: f32| {
            let s = sine(hz, amp, 4.0, RATE);
            measure(&s, &s, RATE).integrated
        };
        let (l1k, l100, l10k, l30) = (at(1000.0), at(100.0), at(10_000.0), at(30.0));
        assert!(l10k - l1k > 3.0 && l10k - l1k < 4.6, "10 kHz: {}", l10k - l1k);
        assert!(l1k - l100 > 1.5 && l1k - l100 < 2.2, "100 Hz: {}", l1k - l100);
        assert!(l1k - l30 > 2.0, "30 Hz precisa ser atenuado pelo passa-altas: {}", l1k - l30);
    }

    #[test]
    fn a_ponderacao_vale_em_outras_taxas() {
        // o mesmo seno, a mesma medida em 44,1, 48, 96 e 192 kHz
        for rate in [44_100.0, 48_000.0, 96_000.0, 192_000.0, 22_050.0] {
            let s = sine(1000.0, dbfs(-23.0), 4.0, rate);
            near(measure(&s, &s, rate).integrated, -23.0, 0.15, &format!("{rate} Hz"));
        }
    }

    #[test]
    fn ruido_branco_confere_com_a_energia_ponderada() {
        // ruído branco de energia total E: a ponderação K deixa passar uma fração fixa; o valor
        // esperado sai da resposta em frequência (referência calculada por integração numérica)
        let n = noise(48_000 * 10, 1);
        let l = measure(&n, &n, RATE);
        let rms = (n.iter().map(|&x| f64::from(x) * f64::from(x)).sum::<f64>() / n.len() as f64).sqrt();
        // sem ponderação seria 20·log10(rms) + 3,01 (dois canais) − 0,691; a prateleira de +4 dB
        // acima de 1,7 kHz cobre a maior parte da banda do ruído: sobe uns 3,5 dB
        let flat = 20.0 * rms.log10() + 3.01 - 0.691;
        let gain = l.integrated - flat;
        assert!(gain > 3.0 && gain < 4.2, "ganho da ponderação em ruído branco: {gain}");
        // ruído estacionário: momentâneo, curto prazo e integrado quase iguais e faixa pequena
        near(l.momentary, l.integrated, 0.6, "momentâneo do ruído");
        near(l.short_term, l.integrated, 0.4, "curto prazo do ruído");
        assert!(l.range < 1.0, "faixa do ruído {}", l.range);
        assert!(l.true_peak > -1.0, "o ruído chega perto de 0 dBFS: {}", l.true_peak);
    }

    #[test]
    fn silencio_nao_tem_medida() {
        let z = vec![0.0f32; 48_000 * 5];
        let l = measure(&z, &z, RATE);
        assert_eq!(l, Loudness::EMPTY);
        assert!(l.integrated.is_finite() && l.true_peak.is_finite());
    }

    #[test]
    fn trecho_curto_demais_nao_fecha_janela() {
        // 399 ms: nenhum bloco de 400 ms
        let s = sine(1000.0, 0.5, 0.399, RATE);
        let l = measure(&s, &s, RATE);
        assert_eq!((l.momentary, l.short_term, l.integrated, l.range), (NONE, NONE, NONE, NONE));
        // mas o true peak sai
        near(l.true_peak, -6.02, 0.2, "true peak do trecho curto");
        // 400 ms exatos já dão momentâneo e integrado
        let s = sine(1000.0, dbfs(-20.0), 0.4, RATE);
        let l = measure(&s, &s, RATE);
        near(l.momentary, -20.0, 0.3, "momentâneo aos 400 ms");
        near(l.integrated, -20.0, 0.3, "integrado aos 400 ms");
        assert_eq!(l.short_term, NONE, "3 s ainda não fecharam");
        // extremos: vazio, uma amostra, uma amostra gigante
        assert_eq!(measure(&[], &[], RATE), Loudness::EMPTY);
        let one = measure(&[0.5], &[0.5], RATE);
        assert_eq!(one.integrated, NONE);
        near(one.true_peak, -6.02, 0.1, "uma amostra");
        let huge = measure(&[1e30, -1e30], &[1e30, -1e30], RATE);
        assert!(huge.true_peak.is_finite() && huge.true_peak > 500.0 - 1.0, "{huge:?}");
    }

    #[test]
    fn nunca_sai_nan_nem_infinito() {
        let mut s = sine(1000.0, dbfs(-20.0), 3.0, RATE);
        for i in (0..s.len()).step_by(97) {
            s[i] = [f32::NAN, f32::INFINITY, f32::NEG_INFINITY][i % 3];
        }
        let l = measure(&s, &s, RATE);
        for v in [l.momentary, l.momentary_max, l.short_term, l.short_term_max, l.integrated, l.true_peak, l.range] {
            assert!(v.is_finite(), "{l:?}");
        }
        assert!(l.integrated > -40.0 && l.true_peak < 0.5, "as amostras ruins contam como silêncio: {l:?}");
        // taxa inválida cai na padrão em vez de NaN
        for rate in [0.0, -1.0, f64::NAN, f64::INFINITY] {
            let s = sine(1000.0, dbfs(-20.0), 1.0, RATE);
            assert!(measure(&s, &s, rate).integrated.is_finite());
        }
    }

    #[test]
    fn gate_absoluto_ignora_o_que_esta_abaixo_de_menos_70() {
        // 10 s a −20 LUFS e 20 s a −80 LUFS (abaixo do gate): o integrado é o do trecho alto
        let mut s = sine(1000.0, dbfs(-20.0), 10.0, RATE);
        s.extend(sine(1000.0, dbfs(-80.0), 20.0, RATE));
        near(measure(&s, &s, RATE).integrated, -20.0, 0.15, "silêncio quase inaudível não puxa a média");
    }

    #[test]
    fn gate_relativo_ignora_o_fundo_10_lu_abaixo() {
        // 10 s a −20 LUFS e 10 s a −40: a média sem gate relativo seria ~−23; com ele o trecho
        // baixo (20 LU abaixo do que passou) sai e resta o alto
        let mut s = sine(1000.0, dbfs(-20.0), 10.0, RATE);
        s.extend(sine(1000.0, dbfs(-40.0), 10.0, RATE));
        near(measure(&s, &s, RATE).integrated, -20.0, 0.15, "fundo a −20 LU sai");
        // 10 LU abaixo exatos é o limite: a −29 LU (9 abaixo) o trecho baixo entra
        let mut s = sine(1000.0, dbfs(-20.0), 10.0, RATE);
        s.extend(sine(1000.0, dbfs(-29.0), 10.0, RATE));
        // energia média de −20 e −29 LUFS: 10·log10((1 + 10^-0,9)/2) − 20
        let mean = 10.0 * ((1.0 + 10f64.powf(-0.9)) / 2.0).log10() - 20.0;
        near(measure(&s, &s, RATE).integrated, mean, 0.2, "fundo a −9 LU entra");
    }

    #[test]
    fn rajadas_com_gate_medem_so_a_rajada() {
        // rajadas de 1 s a −18 LUFS separadas por 3 s de silêncio: o integrado é o da rajada
        let burst = sine(1000.0, dbfs(-18.0), 1.0, RATE);
        let gap = vec![0.0f32; 48_000 * 3];
        let mut s = Vec::new();
        for _ in 0..6 {
            s.extend(&burst);
            s.extend(&gap);
        }
        let l = measure(&s, &s, RATE);
        // os blocos de 400 ms que pegam só a borda da rajada (1/4, 1/2 e 3/4 dela) também passam
        // do gate relativo: 7 cheios e 6 parciais fazem a média cair 10·log10(10/13) = −1,14 dB
        near(l.integrated, -18.0 + 10.0 * (10.0f64 / 13.0).log10(), 0.2, "integrado das rajadas");
        // a janela de 400 ms sobre uma rajada de 1 s chega ao nível cheio
        assert!(l.momentary_max > -18.5 && l.momentary_max < -17.5, "{}", l.momentary_max);
        // o silêncio depois da última rajada derruba o momentâneo até o piso
        assert_eq!(l.momentary, NONE);
        // o curto prazo de 3 s pega 1 s de rajada em 3: 10·log10(1/3) = −4,8 dB abaixo
        assert!(l.short_term_max > -18.0 - 5.5 && l.short_term_max < -18.0 - 4.0, "{}", l.short_term_max);
    }

    #[test]
    fn faixa_de_loudness_mede_a_diferenca_entre_trechos() {
        // metade da música a −30 LUFS, metade a −20: LRA ≈ 10 LU
        let mut s = sine(1000.0, dbfs(-30.0), 30.0, RATE);
        s.extend(sine(1000.0, dbfs(-20.0), 30.0, RATE));
        let l = measure(&s, &s, RATE);
        near(l.range, 10.0, 0.6, "LRA");
        // um trecho a −60 LUFS (acima do gate absoluto, mas 20 LU abaixo da média) sai da conta
        let mut t = s.clone();
        t.extend(sine(1000.0, dbfs(-60.0), 30.0, RATE));
        near(measure(&t, &t, RATE).range, l.range, 1.0, "gate relativo da LRA");
    }

    #[test]
    fn true_peak_pega_o_pico_entre_amostras() {
        // seno em fs/4 com fase de 45°: as amostras valem ±0,7071 (−3 dBFS) e a onda chega a 1,0
        let a = std::f32::consts::FRAC_1_SQRT_2;
        let s: Vec<f32> = (0..48_000).map(|i| [a, a, -a, -a][i % 4]).collect();
        let sample_peak = s.iter().fold(0.0f32, |m, v| m.max(v.abs()));
        near(20.0 * f64::from(sample_peak).log10(), -3.01, 0.05, "pico de amostra");
        let l = measure(&s, &s, RATE);
        near(l.true_peak, 0.0, 0.25, "true peak");
        assert!(l.true_peak > -0.5, "o true peak tem de ficar bem acima do pico de amostra: {}", l.true_peak);
        // nunca abaixo do pico de amostra
        let noise = noise(48_000, 7);
        let l = measure(&noise, &noise, RATE);
        let sp = 20.0 * f64::from(noise.iter().fold(0.0f32, |m, v| m.max(v.abs()))).log10();
        assert!(l.true_peak >= sp - 1e-6, "{} < {}", l.true_peak, sp);
        // e um seno comum de 1 kHz não passa do pico real (0 dBFS de amplitude 1)
        let s = sine(1000.0, 1.0, 1.0, RATE);
        let l = measure(&s, &s, RATE);
        near(l.true_peak, 0.0, 0.1, "seno de amplitude 1");
    }

    #[test]
    fn true_peak_do_impulso_e_de_dc_sao_exatos() {
        // DC: cada fase soma 1, então o valor interpolado é o próprio DC
        // (com subida e descida suaves: o degrau do zero ao DC teria o overshoot de Gibbs, que é real)
        let dc: Vec<f32> = (0..14_400).map(|i| 0.5 * (i.min(14_399 - i) as f32 / 4800.0).min(1.0).powi(2)).collect();
        near(measure(&dc, &dc, RATE).true_peak, -6.02, 0.02, "DC");
        // impulso: a fase 0 é a própria amostra
        let mut imp = vec![0.0f32; 4800];
        imp[2000] = 0.8;
        assert!(measure(&imp, &imp, RATE).true_peak >= -1.95, "impulso");
    }

    #[test]
    fn o_medidor_ao_vivo_bate_com_o_offline_em_qualquer_fatiamento() {
        let s = sine(440.0, dbfs(-18.0), 6.0, RATE);
        let want = measure(&s, &s, RATE);
        for chunk in [1usize, 7, 128, 480, 4800, 100_000] {
            let mut m = Meter::new(RATE, 2);
            for c in s.chunks(chunk) {
                m.push(c, Some(c));
            }
            let got = m.read();
            near(got.integrated, want.integrated, 1e-9, "integrado");
            near(got.momentary, want.momentary, 1e-9, "momentâneo");
            near(got.short_term, want.short_term, 1e-9, "curto prazo");
            near(got.true_peak, want.true_peak, 0.02, "true peak (só difere no fim, sem o flush)");
        }
    }

    #[test]
    fn reset_zera_tudo_e_a_medida_recomeca() {
        let s = sine(1000.0, dbfs(-20.0), 4.0, RATE);
        let mut m = Meter::new(RATE, 2);
        m.push(&s, Some(&s));
        assert!(m.read().integrated > -21.0);
        m.reset();
        assert_eq!(m.read(), Loudness::EMPTY);
        let quiet = sine(1000.0, dbfs(-40.0), 4.0, RATE);
        m.push(&quiet, Some(&quiet));
        // só o que veio depois do reset conta
        near(m.read().integrated, -40.0, 0.2, "integrado depois do reset");
        // (o pico do seno de antes não volta; sobra só o transiente da emenda entre os dois)
        let tp = m.read().true_peak;
        assert!(tp > -40.5 && tp < -20.5, "true peak depois do reset: {tp}");
        assert_eq!(m.read_kind(99), NONE);
    }

    #[test]
    fn nao_aloca_depois_de_criado() {
        let s = sine(1000.0, dbfs(-20.0), 4.0, RATE);
        let mut m = Meter::new(RATE, 2);
        let allocs = crate::testalloc::count(|| {
            for c in s.chunks(128) {
                m.push(c, Some(c));
            }
            let _ = m.read();
            m.reset();
            m.push(&s, Some(&s));
            let _ = m.read_kind(kind::RANGE);
        });
        assert_eq!(allocs, 0);
    }

    fn engine_with_tone(amp: f32) -> Engine {
        let mut e = Engine::new(RATE);
        let tone = sine(1000.0, amp, 1.0, RATE);
        e.load_sample(1, crate::Sample::new(vec![tone.clone(), tone], RATE));
        e.set_track_count(1);
        e.add_clip(crate::Clip { track: 0, sample: 1, start: 0.0, offset: 0.0, length: 1.0, gain: 1.0, fade_in: 0.0, fade_out: 0.0 });
        e.set_tempo(120.0, 4);
        e
    }

    fn process(e: &mut Engine, frames: usize) -> (Vec<f32>, Vec<f32>) {
        let (mut ol, mut or) = (Vec::new(), Vec::new());
        let (mut l, mut r) = ([0.0f32; 128], [0.0f32; 128]);
        for _ in 0..frames / 128 {
            e.process(&mut l, &mut r);
            ol.extend_from_slice(&l);
            or.extend_from_slice(&r);
        }
        (ol, or)
    }

    #[test]
    fn o_motor_mede_a_saida_do_master_como_o_offline() {
        let mut e = engine_with_tone(dbfs(-20.0));
        // parado e sem nada: sem medida
        let pre = process(&mut e, 48_000);
        assert!(pre.0.iter().all(|&v| v == 0.0));
        assert_eq!((e.loudness(0), e.loudness(1), e.loudness(2), e.loudness(3), e.loudness(4)), (NONE, NONE, NONE, NONE, NONE));
        e.play();
        // o clipe dura 1 s: 1 s de tom e o resto silêncio
        let (l, r) = process(&mut e, 48_000 * 2);
        // a medida offline do que saiu desde o começo (as janelas que pegam a entrada do clipe
        // só existem se o trecho medido começa antes dele)
        let (full_l, full_r): (Vec<f32>, Vec<f32>) = (pre.0.iter().chain(&l).copied().collect(), pre.1.iter().chain(&r).copied().collect());
        let want = measure(&full_l, &full_r, RATE);
        assert!(want.integrated > -30.0, "o clipe tem de soar: {want:?}");
        // o medidor ao vivo viu exatamente o que saiu (os blocos de 128 dão a mesma grade de 100 ms)
        near(e.loudness(kind::INTEGRATED), want.integrated, 0.01, "integrado");
        near(e.loudness(kind::TRUE_PEAK), want.true_peak, 0.05, "true peak");
        assert_eq!(e.loudness(99), NONE);
        // reset: some tudo e a medida recomeça do que vier depois
        e.loudness_reset();
        assert_eq!((e.loudness(kind::INTEGRATED), e.loudness(kind::TRUE_PEAK)), (NONE, NONE));
        assert_eq!(crate::api::apply(&mut e, "loudness", &[2.0]), Ok(Some(NONE)));
        assert_eq!(crate::api::apply(&mut e, "loudness_reset", &[]), Ok(None));
    }

    #[test]
    fn o_true_peak_medido_e_o_de_depois_do_limitador() {
        // 12 dB acima do teto: sem o limitador seria +12 dBTP; o medidor vem depois dele
        let mut e = engine_with_tone(4.0);
        e.play();
        process(&mut e, 48_000);
        let tp = e.loudness(kind::TRUE_PEAK);
        assert!(tp > -3.0 && tp < 0.6, "true peak pós-limitador: {tp}");
        // sem limitador o excesso chega ao medidor (só a trava em ±1 segura: +0 dBFS)
        let mut e = engine_with_tone(4.0);
        e.set_limiter(false);
        e.play();
        process(&mut e, 48_000);
        assert!(e.loudness(kind::TRUE_PEAK) > -0.5);
    }

    #[test]
    fn muito_tempo_de_sinal_nao_estoura_nada() {
        // 20 minutos de ruído: contadores e somas seguem finitos e coerentes
        let block: Vec<f32> = noise(48_000, 3).iter().map(|v| v * 0.1).collect();
        let mut m = Meter::new(RATE, 2);
        for _ in 0..1200 {
            m.push(&block, Some(&block));
        }
        let l = m.read();
        assert!(l.integrated.is_finite() && l.integrated > -30.0 && l.integrated < -10.0, "{l:?}");
        assert!(l.range < 1.0);
    }
}
