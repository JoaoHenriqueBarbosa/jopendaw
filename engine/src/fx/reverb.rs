//! Reverb algorítmico de alta densidade: rede de atraso realimentada (FDN) de 8 linhas.
//!
//! Caminho do sinal: pré-atraso (até 250 ms) → dali saem as reflexões iniciais (taps esparsos,
//! diferentes em cada canal) e a entrada da cauda, que passa por um passa-alta (corte de graves)
//! e por 4 passa-tudo em série por canal (difusão: espalha o transiente antes de ele entrar na
//! rede). Na rede, 8 linhas com comprimentos primos (sem ressonâncias em comum) escalados pelo
//! tamanho, misturadas a cada volta por uma matriz de Hadamard 8×8 (ortogonal: não soma nem tira
//! energia, e cada linha alimenta todas as outras).
//!
//! Decaimento calibrado: cada linha tem um ganho que tira exatamente 60 dB em RT60 segundos,
//! proporcional ao seu comprimento, e um passa-baixa de um polo cuja perda extra no agudo também é
//! proporcional ao comprimento (filtro de absorção de Jot): na frequência de abafamento a cauda cai
//! duas vezes mais rápido, acima disso mais ainda, e o timbre do decaimento não depende de qual
//! linha a energia está atravessando.
//!
//! Modulação: cada linha balança o comprimento devagar (menos de 1 Hz, fases e velocidades
//! diferentes), o que desfaz o som metálico dos modos fixos. A leitura fracionária é por passa-tudo
//! de 1ª ordem: ganho 1 em todas as frequências, então a cauda (e o congelamento) não perdem
//! agudo a cada volta, como perderiam com interpolação linear ou cúbica.
//!
//! Congelar leva o RT60 a uma hora e corta a entrada: a cauda fica soando. Tudo é alocado em
//! `new` para o tamanho máximo na taxa; sem entrada e com a cauda abaixo de −160 dB o efeito dorme.

use std::f32::consts::{SQRT_2, TAU};

use crate::dsp::{FilterMode, Smoothed, Svf, sin_turns, smoothing};
use crate::effect::{Effect, reverb_param as P};
use crate::fx::delay::{DelayLine, HeadBlock, Heads, Ramp, SILENCE, equal_power, peak};

const LINES: usize = 8;
const CONTROL: usize = 32;
/// Comprimentos das linhas no tamanho máximo, em ms: espaçados quase geometricamente, sem razões
/// simples entre si (viram primos na taxa real).
const LINE_MS: [f32; LINES] = [58.1, 65.3, 72.4, 81.9, 90.7, 102.6, 113.8, 127.3];
/// Escala dos comprimentos no tamanho 0 (de uma cabine a um salão, exponencial no meio).
const SIZE_MIN: f32 = 0.25;
/// Escala das reflexões iniciais no tamanho 0 (elas encolhem menos que a cauda).
const EARLY_SIZE_MIN: f32 = 0.3;
const DIFFUSER_MS: [[f32; 4]; 2] = [[2.1, 3.3, 5.1, 7.7], [2.3, 3.1, 5.5, 7.3]];
const DIFFUSER_G: [f32; 4] = [0.7, 0.7, 0.62, 0.62];
/// Reflexões iniciais no tamanho máximo, ms.
const EARLY_MS: [[f32; 8]; 2] = [[7.1, 13.9, 19.7, 27.3, 34.1, 43.9, 55.3, 68.9], [8.3, 12.1, 21.9, 25.7, 37.3, 41.1, 58.7, 71.3]];
/// Polaridade das reflexões: quase todas positivas (paredes), algumas invertidas para não colorir.
const EARLY_SIGN: [[f32; 8]; 2] = [[1.0, -1.0, 1.0, 1.0, -1.0, 1.0, 1.0, -1.0], [1.0, 1.0, -1.0, 1.0, 1.0, -1.0, -1.0, 1.0]];
/// Constante de decaimento do nível das reflexões ao longo do tempo.
const EARLY_DECAY_MS: f32 = 35.0;
/// Excursão da modulação no máximo, ms (±).
const MOD_MS: f32 = 0.5;
const MOD_HZ: [f32; LINES] = [0.29, 0.41, 0.23, 0.53, 0.37, 0.61, 0.47, 0.67];
const MAX_PREDELAY: f32 = 0.25;
/// RT60 do congelamento: estável (ganho abaixo de 1) e, na prática, eterno.
const FREEZE_SECS: f32 = 3600.0;
const PARAM_TAU: f32 = 0.02;
/// O tamanho desliza devagar: as linhas mudam de comprimento sem estalo (com um leve glissando).
const SIZE_TAU: f32 = 0.25;
const FREEZE_TAU: f32 = 0.01;
/// Polaridade com que a entrada entra em cada linha (esquerda nas pares, direita nas ímpares).
const IN_SIGN: [f32; LINES] = [1.0, 1.0, -1.0, -1.0, 1.0, -1.0, -1.0, 1.0];
/// Como as linhas somam em cada saída: padrões ortogonais, as saídas saem descorrelacionadas.
const OUT_L: [f32; LINES] = [1.0, 1.0, 1.0, 1.0, -1.0, -1.0, -1.0, -1.0];
const OUT_R: [f32; LINES] = [1.0, -1.0, 1.0, -1.0, 1.0, -1.0, 1.0, -1.0];
/// Nível da cauda para ruído na entrada, no decaimento de referência (−6 dB). A energia de uma FDN
/// cresce com RT60 e cai com o comprimento das linhas; o ganho divide pela energia calculada e
/// devolve só T^¼: cauda longa ainda soa maior, mas não 10 dB mais alta, e o tamanho não mexe no
/// volume.
const TAIL_GAIN: f32 = 0.5;
const DECAY_REF: f32 = 2.2;
/// Piso da energia na normalização: com sala enorme e decaimento curtíssimo a cauda vira dois ou
/// três ecos esparsos, que não devem ser empurrados para o volume de uma cauda de verdade.
const MIN_ENERGY: f32 = 0.004;

pub struct Reverb {
    rate: f32,
    pre: [DelayLine; 2],
    diffusers: [[Diffuser; 4]; 2],
    low_cut: [Svf; 2],
    lines: [Line; LINES],
    /// Posição (quadros, na escala 1) e ganho de cada reflexão inicial.
    early_at: [[f32; 8]; 2],
    early_gain: [[f32; 8]; 2],
    mix: Smoothed,
    /// Pré-atraso pedido, em quadros, e a cabeça que o lê (desliza ou faz crossfade: girar o botão
    /// com som passando não dá glissando nem estalo).
    predelay: f32,
    pre_head: Heads<1>,
    size: f32,
    scale: Smoothed,
    early_scale: Smoothed,
    decay: Smoothed,
    damping: Smoothed,
    cut: Smoothed,
    width: Smoothed,
    modulation: Smoothed,
    early: Smoothed,
    freeze: Smoothed,
    /// Ganho da cauda no fim do bloco anterior.
    tail: f32,
    /// Energia média que uma linha acumula por unidade de entrada (ruído branco).
    energy: f32,
    /// Correção do nível da cauda durante o congelamento (1 sem congelar).
    held: f32,
    silent: usize,
    idle: bool,
    primed: bool,
}

/// Passa-tudo de Schroeder: espalha um impulso num trem denso sem colorir o espectro.
struct Diffuser {
    line: DelayLine,
    delay: usize,
    g: f32,
}

impl Diffuser {
    #[inline]
    fn tick(&mut self, x: f32) -> f32 {
        let z = self.line.tap(self.delay - 1);
        let w = x + self.g * z;
        self.line.write(w);
        z - self.g * w
    }
}

struct Line {
    buf: DelayLine,
    /// Comprimento da volta, em quadros (alvo primo).
    length: Smoothed,
    /// Estado do passa-tudo da leitura fracionária.
    allpass: f32,
    /// Estado e coeficientes do filtro de absorção `b0 / (1 − a1·z⁻¹)`.
    absorb: f32,
    b0: f32,
    a1: f32,
    phase: f32,
    /// Posição de leitura no fim do bloco anterior.
    read: f32,
}

fn is_prime(n: usize) -> bool {
    if n < 4 {
        return n >= 2;
    }
    if n.is_multiple_of(2) {
        return false;
    }
    let mut d = 3;
    while d * d <= n {
        if n.is_multiple_of(d) {
            return false;
        }
        d += 2;
    }
    true
}

/// O primo mais perto de `n` que seja maior que `floor`.
fn prime_near(n: usize, floor: usize) -> usize {
    let n = n.max(floor + 1);
    for k in 0.. {
        if n - k > floor && is_prime(n - k) {
            return n - k;
        }
        if is_prime(n + k) {
            return n + k;
        }
    }
    unreachable!()
}

/// Hadamard 8×8 normalizada (ortogonal), pela transformada rápida: 24 somas e 8 produtos.
#[inline]
fn hadamard(x: &mut [f32; LINES]) {
    let mut h = 1;
    while h < LINES {
        let mut i = 0;
        while i < LINES {
            for j in i..i + h {
                let (a, b) = (x[j], x[j + h]);
                x[j] = a + b;
                x[j + h] = a - b;
            }
            i += 2 * h;
        }
        h *= 2;
    }
    for v in x.iter_mut() {
        *v *= 0.353_553_38; // 1/√8
    }
}

/// Ganho `g` e polo `p` do filtro de absorção `g(1 − p)/(1 − p·z⁻¹)` de uma linha de `length`
/// quadros: −60 dB em `decay` segundos no grave, e na frequência de abafamento (`cos_w` = cos ω_d)
/// uma perda extra igual, ou seja, lá a cauda cai duas vezes mais rápido.
fn absorption(length: f32, decay: f32, cos_w: f32, rate: f32) -> (f32, f32) {
    // 10^(−3·L/(T·taxa))
    let g = (-6.907_755 * length / (decay * rate)).exp();
    // |H(ω_d)|² = g⁴ exige (1 − 2p·cos ω + p²)/(1 − p)² = K = 1/g², então p = B − √(B² − 1) com
    // B = (K − cos ω)/(K − 1). A forma 1/(B + √(B² − 1)) não perde precisão com B enorme
    // (decaimento longo), onde p tende a zero.
    let k = 1.0 / (g * g);
    let b = (k - cos_w) / (k - 1.0);
    let pole = if b.is_finite() && b >= 1.0 { 1.0 / (b + (b * b - 1.0).sqrt()) } else { 0.0 };
    (g, pole)
}

impl Reverb {
    pub fn new(rate: f64) -> Self {
        let rate = rate as f32;
        let ms = |ms: f32| ms * 0.001 * rate;
        let early_max = EARLY_MS.iter().flatten().fold(0.0f32, |m, &v| m.max(v));
        let pre_len = (ms(MAX_PREDELAY * 1000.0 + early_max)).ceil() as usize + 8;
        let mod_max = ms(MOD_MS).ceil() as usize;
        let diffusers = DIFFUSER_MS.map(|side| {
            let mut k = 0;
            side.map(|t| {
                let delay = (ms(t).round() as usize).max(1);
                let d = Diffuser { line: DelayLine::new(delay + 2), delay, g: DIFFUSER_G[k] };
                k += 1;
                d
            })
        });
        let lines = LINE_MS.map(|t| Line {
            // o primo pode passar um pouco do comprimento pedido; a modulação soma dos dois lados
            buf: DelayLine::new(ms(t).ceil() as usize + 64 + mod_max + 4),
            length: Smoothed::new(0.0),
            allpass: 0.0,
            absorb: 0.0,
            b0: 0.0,
            a1: 0.0,
            phase: 0.0,
            read: 0.0,
        });
        let mut early_at = [[0.0; 8]; 2];
        let mut early_gain = [[0.0; 8]; 2];
        for c in 0..2 {
            let mut energy = 0.0;
            for k in 0..8 {
                early_at[c][k] = ms(EARLY_MS[c][k]);
                early_gain[c][k] = EARLY_SIGN[c][k] * (-EARLY_MS[c][k] / EARLY_DECAY_MS).exp();
                energy += early_gain[c][k] * early_gain[c][k];
            }
            // a soma das reflexões tem a energia da entrada
            let norm = 1.0 / f32::sqrt(energy);
            for g in &mut early_gain[c] {
                *g *= norm;
            }
        }
        let mut r = Self {
            rate,
            pre: [DelayLine::new(pre_len), DelayLine::new(pre_len)],
            diffusers,
            low_cut: [Svf::default(); 2],
            lines,
            early_at,
            early_gain,
            mix: Smoothed::new(0.25),
            predelay: (0.02 * rate).round(),
            pre_head: Heads::new([0.0]),
            size: 0.6,
            scale: Smoothed::new(1.0),
            early_scale: Smoothed::new(1.0),
            decay: Smoothed::new(2.2),
            damping: Smoothed::new(7000.0),
            cut: Smoothed::new(120.0),
            width: Smoothed::new(1.0),
            modulation: Smoothed::new(0.3),
            early: Smoothed::new(0.5),
            freeze: Smoothed::new(0.0),
            tail: 0.0,
            energy: 1.0,
            held: 1.0,
            silent: 0,
            idle: false,
            primed: false,
        };
        r.resize();
        r
    }

    /// Alvos de comprimento das linhas e da escala das reflexões para o tamanho atual.
    fn resize(&mut self) {
        let scale = SIZE_MIN * (1.0 / SIZE_MIN).powf(self.size);
        self.scale.set(scale);
        self.early_scale.set(EARLY_SIZE_MIN * (1.0 / EARLY_SIZE_MIN).powf(self.size));
        let mut floor = 1;
        for (line, ms) in self.lines.iter_mut().zip(LINE_MS) {
            // primos distintos e crescentes: nenhum par de linhas divide um modo
            let p = prime_near((scale * ms * 0.001 * self.rate).round() as usize, floor);
            floor = p;
            line.length.set(p as f32);
        }
    }

    /// Ganho da cauda: divide pela energia que a malha acumula (para ruído branco na entrada) e
    /// devolve uma parte do efeito do decaimento, T^¼ na amplitude.
    fn tail_gain(&self) -> f32 {
        TAIL_GAIN * self.held * (self.decay.value / DECAY_REF).powf(0.25) / (self.energy.max(MIN_ENERGY) * LINES as f32).sqrt()
    }

    fn prime(&mut self) {
        for p in [
            &mut self.mix,
            &mut self.scale,
            &mut self.early_scale,
            &mut self.decay,
            &mut self.damping,
            &mut self.cut,
            &mut self.width,
            &mut self.modulation,
            &mut self.early,
            &mut self.freeze,
        ] {
            p.snap();
        }
        self.pre_head = Heads::new([self.predelay]);
        let depth = self.modulation.value.sqrt() * MOD_MS * 0.001 * self.rate;
        for line in &mut self.lines {
            line.length.snap();
            line.read = line.length.value - 1.0 + depth * sin_turns(line.phase);
        }
        self.coefficients();
        self.tail = self.tail_gain();
        self.primed = true;
    }

    /// Ganho e absorção de cada linha para o comprimento, o RT60 e o abafamento atuais, e a
    /// energia média que a malha acumula (sem o congelamento, que a levaria ao infinito).
    fn coefficients(&mut self) {
        // a entrada fecha primeiro (1 − fz) e só então a cauda se estende (fz⁸, em escala
        // logarítmica): se as duas coisas andassem juntas, o som que ainda entra durante a
        // transição acumularia numa malha quase sem perda e o congelado sairia mais alto
        let hold = self.freeze.value.powi(8);
        let user = self.decay.value;
        let decay = if hold > 0.0 { user * (FREEZE_SECS / user).powf(hold) } else { user };
        let cos_w = (TAU * self.damping.value.min(0.45 * self.rate) / self.rate).cos();
        let rate = self.rate;
        let mut energy = 0.0;
        let (mut g_user, mut g_held) = (0.0, 0.0);
        for line in &mut self.lines {
            let length = line.length.value;
            let (held, pole) = absorption(length, decay, cos_w, rate);
            line.b0 = held * (1.0 - pole);
            line.a1 = pole;
            let (g, pole) = if hold > 0.0 { absorption(length, user, cos_w, rate) } else { (held, pole) };
            g_user += g;
            g_held += held;
            // energia de um pente com esse filtro para ruído branco: a média em ω de
            // |H|²/(1 − |H|²), com |H|² = G/(1 − 2p·cos ω + p²) e G = g²(1 − p)², que tem forma
            // fechada: G/√((1 + p² − G)² − 4p²)
            let big_g = (g * (1.0 - pole)).powi(2);
            let a = 1.0 + pole * pole - big_g;
            energy += big_g / (a * a - 4.0 * pole * pole).max(1e-12).sqrt();
        }
        self.energy = energy / LINES as f32;
        // no regime, o conteúdo de uma linha tem espectro 1/(1 − |H|²) e a saída, |H|² vezes
        // isso; congelada (H ≈ 1) a linha solta o conteúdo inteiro, (1 + E)/E vezes mais energia
        // que a cauda que estava soando. O fator mantém o nível contínuo, interpolado pelo quanto
        // o ganho da volta já andou até 1.
        self.held = if hold > 0.0 {
            let (g_user, g_held) = (g_user / LINES as f32, g_held / LINES as f32);
            let w = if g_user < 1.0 { ((g_held - g_user) / (1.0 - g_user)).clamp(0.0, 1.0) } else { 0.0 };
            let e = self.energy.max(MIN_ENERGY);
            (e / (1.0 + e)).sqrt().powf(w)
        } else {
            1.0
        };
    }

    /// Reflexões iniciais e entrada crua da cauda com o pré-atraso em `pre` quadros.
    #[inline]
    fn taps(&self, pre: f32, early_scale: f32) -> ([f32; 2], [f32; 2]) {
        let mut er = [0.0f32; 2];
        let mut raw = [0.0f32; 2];
        for c in 0..2 {
            for (&at, &g) in self.early_at[c].iter().zip(&self.early_gain[c]) {
                er[c] += g * self.pre[c].linear(pre + early_scale * at);
            }
            raw[c] = self.pre[c].linear(pre);
        }
        (er, raw)
    }

    fn block(&mut self, left: &mut [f32], right: &mut [f32]) -> f32 {
        let len = left.len();
        let rate = self.rate;
        let a = smoothing(PARAM_TAU, len, rate);
        let a_size = smoothing(SIZE_TAU, len, rate);
        let (dry0, wet0) = equal_power(self.mix.value);
        let (dry1, wet1) = equal_power(self.mix.step(a));
        let fz0 = self.freeze.value;
        let fz1 = self.freeze.step(smoothing(FREEZE_TAU, len, rate));
        let early0 = self.early.value * (1.0 - fz0);
        let early1 = self.early.step(a) * (1.0 - fz1);
        let HeadBlock { mut pos, mut old, mut gain, mut old_gain, fading } = self.pre_head.advance([self.predelay], len, rate);
        let mut early_scale = Ramp::new(self.early_scale.value, self.early_scale.step(a_size), len);
        let mut width = Ramp::new(self.width.value, self.width.step(a), len);
        self.decay.step(a);
        self.damping.step(a);
        self.scale.step(a_size);
        let depth = self.modulation.step(a).sqrt() * MOD_MS * 0.001 * rate;
        let mut reads = [Ramp::default(); LINES];
        for ((line, read), hz) in self.lines.iter_mut().zip(reads.iter_mut()).zip(MOD_HZ) {
            line.length.step(a_size);
            line.phase = (line.phase + hz * len as f32 / rate).fract();
            // lida antes da escrita: a volta de L quadros lê L − 1 quadros atrás do último
            let to = line.length.value - 1.0 + depth * sin_turns(line.phase);
            *read = Ramp::new(line.read, to, len);
            line.read = to;
        }
        self.coefficients();
        let g_cut = Svf::g(self.cut.step(a).min(0.45 * rate), rate);
        for f in &mut self.low_cut {
            f.set(g_cut, SQRT_2);
        }
        let tail1 = self.tail_gain();
        let mut tail = Ramp::new(self.tail, tail1, len);
        self.tail = tail1;
        let mut feed = Ramp::new(1.0 - fz0, 1.0 - fz1, len);
        let mut early = Ramp::new(early0, early1, len);
        let mut dry = Ramp::new(dry0, dry1, len);
        let mut wet = Ramp::new(wet0, wet1, len);

        let mut out_peak = 0.0f32;
        for (l, r) in left.iter_mut().zip(right.iter_mut()) {
            let (xl, xr) = (*l, *r);
            self.pre[0].write(xl);
            self.pre[1].write(xr);
            // reflexões iniciais (taps esparsos do pré-atraso) e a entrada crua da cauda
            let es = early_scale.next();
            let (mut er, mut raw) = self.taps(pos[0].next(), es);
            if fading {
                let (wn, wo) = (gain.next(), old_gain.next());
                let (er_old, raw_old) = self.taps(old[0].next(), es);
                for c in 0..2 {
                    er[c] = er[c] * wn + er_old[c] * wo;
                    raw[c] = raw[c] * wn + raw_old[c] * wo;
                }
            }

            // entrada da cauda: corte de graves e difusão
            let fed = feed.next();
            let mut input = [0.0f32; 2];
            for (c, v) in input.iter_mut().enumerate() {
                let mut x = self.low_cut[c].tick(raw[c], FilterMode::HighPass).0;
                for d in &mut self.diffusers[c] {
                    x = d.tick(x);
                }
                *v = x * fed;
            }

            // a rede
            let mut y = [0.0f32; LINES];
            for ((line, read), out) in self.lines.iter_mut().zip(reads.iter_mut()).zip(y.iter_mut()) {
                let pos = read.next();
                // atraso fracionário por passa-tudo com a fração em [0,5, 1,5): o polo (−η) fica
                // longe do círculo unitário e o ganho é 1 em todo o espectro
                let whole = (pos - 0.5) as usize;
                let frac = pos - whole as f32;
                let eta = (1.0 - frac) / (1.0 + frac);
                let u0 = line.buf.tap(whole);
                let u1 = line.buf.tap(whole + 1);
                let v = eta * (u0 - line.allpass) + u1;
                line.allpass = v;
                line.absorb = line.b0 * v + line.a1 * line.absorb;
                *out = line.absorb;
            }
            let mut mixed = y;
            hadamard(&mut mixed);
            for (k, (line, m)) in self.lines.iter_mut().zip(mixed).enumerate() {
                line.buf.write(m + IN_SIGN[k] * input[k & 1]);
            }
            let (mut tl, mut tr) = (0.0f32, 0.0f32);
            for k in 0..LINES {
                tl += OUT_L[k] * y[k];
                tr += OUT_R[k] * y[k];
            }
            let tg = tail.next();
            let eg = early.next();
            let wl = tl * tg + er[0] * eg;
            let wr = tr * tg + er[1] * eg;
            let w = width.next();
            let mid = (wl + wr) * 0.5;
            let side = (wl - wr) * 0.5 * w;
            let (ol, or) = (mid + side, mid - side);
            out_peak = out_peak.max(ol.abs()).max(or.abs());
            let (d, g) = (dry.next(), wet.next());
            *l = xl * d + ol * g;
            *r = xr * d + or * g;
        }
        for f in &mut self.low_cut {
            f.flush();
        }
        out_peak
    }
}

impl Effect for Reverb {
    fn set_param(&mut self, id: u32, value: f32) {
        if !value.is_finite() {
            return;
        }
        match id {
            P::MIX => self.mix.set(value.clamp(0.0, 1.0)),
            P::PREDELAY => self.predelay = (value.clamp(0.0, MAX_PREDELAY) * self.rate).round(),
            P::SIZE => {
                self.size = value.clamp(0.0, 1.0);
                self.resize();
            }
            P::DECAY => self.decay.set(value.clamp(0.2, 20.0)),
            P::DAMPING => self.damping.set(value.clamp(1000.0, 20000.0)),
            P::LOW_CUT => self.cut.set(value.clamp(20.0, 1000.0)),
            P::WIDTH => self.width.set(value.clamp(0.0, 1.0)),
            P::MODULATION => self.modulation.set(value.clamp(0.0, 1.0)),
            P::EARLY => self.early.set(value.clamp(0.0, 1.0)),
            P::FREEZE => self.freeze.set(if value >= 0.5 { 1.0 } else { 0.0 }),
            _ => {}
        }
    }

    fn process(&mut self, left: &mut [f32], right: &mut [f32]) {
        let n = left.len().min(right.len());
        if n == 0 {
            return;
        }
        if !self.primed {
            self.prime();
        }
        let input = peak(&left[..n], &right[..n]);
        if self.idle {
            if input < SILENCE && self.freeze.target == 0.0 {
                let (dry, _) = equal_power(self.mix.target);
                self.mix.snap();
                for x in left[..n].iter_mut().chain(right[..n].iter_mut()) {
                    *x *= dry;
                }
                return;
            }
            self.idle = false;
        }
        let mut tail = 0.0f32;
        let mut done = 0;
        while done < n {
            let len = (n - done).min(CONTROL);
            tail = tail.max(self.block(&mut left[done..done + len], &mut right[done..done + len]));
            done += len;
        }
        if !(tail.is_finite() && left[n - 1].is_finite() && right[n - 1].is_finite()) {
            self.reset();
            left[..n].fill(0.0);
            right[..n].fill(0.0);
            return;
        }
        if input < SILENCE && tail < SILENCE && self.freeze.value == 0.0 {
            self.silent += n;
            // tudo o que resta no pré-atraso e nas linhas foi gravado já em silêncio
            if self.silent > self.pre[0].len() + self.lines[LINES - 1].buf.len() {
                self.idle = true;
            }
        } else {
            self.silent = 0;
        }
    }

    fn reset(&mut self) {
        for d in self.pre.iter_mut() {
            d.clear();
        }
        for d in self.diffusers.iter_mut().flatten() {
            d.line.clear();
        }
        for f in &mut self.low_cut {
            f.reset();
        }
        for line in &mut self.lines {
            line.buf.clear();
            line.allpass = 0.0;
            line.absorb = 0.0;
        }
        self.silent = 0;
        self.idle = false;
        self.prime();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const RATE: f64 = 48_000.0;

    fn run(rv: &mut Reverb, left: &mut [f32], right: &mut [f32]) {
        for (l, r) in left.chunks_mut(128).zip(right.chunks_mut(128)) {
            rv.process(l, r);
        }
    }

    fn noise(n: usize, seed: u32) -> Vec<f32> {
        let mut rng = crate::dsp::Rng::new(seed);
        (0..n).map(|_| rng.bipolar() * 0.5).collect()
    }

    fn wet_only(decay: f32) -> Reverb {
        let mut rv = Reverb::new(RATE);
        rv.set_param(P::MIX, 1.0);
        rv.set_param(P::PREDELAY, 0.0);
        rv.set_param(P::EARLY, 0.0);
        rv.set_param(P::DAMPING, 20000.0);
        rv.set_param(P::LOW_CUT, 20.0);
        rv.set_param(P::DECAY, decay);
        rv
    }

    /// RT60 medido pela integral de Schroeder da resposta ao impulso: a inclinação entre −5 e
    /// −35 dB extrapolada para 60 dB (T30).
    fn measure_rt60(energy: &[f64]) -> f32 {
        let mut edc = vec![0.0f64; energy.len()];
        let mut acc = 0.0;
        for i in (0..energy.len()).rev() {
            acc += energy[i];
            edc[i] = acc;
        }
        let total = edc[0];
        let db = |i: usize| 10.0 * (edc[i] / total).log10();
        let t5 = (0..edc.len()).find(|&i| db(i) < -5.0).unwrap();
        let t35 = (0..edc.len()).find(|&i| db(i) < -35.0).unwrap();
        (2.0 * (t35 - t5) as f64 / RATE) as f32
    }

    fn impulse_energy(rv: &mut Reverb, secs: f32) -> Vec<f64> {
        let n = (secs * RATE as f32) as usize;
        let mut l = vec![0.0; n];
        let mut r = vec![0.0; n];
        l[0] = 1.0;
        r[0] = 1.0;
        run(rv, &mut l, &mut r);
        l.iter().zip(&r).map(|(a, b)| (*a as f64).powi(2) + (*b as f64).powi(2)).collect()
    }

    #[test]
    fn primos_distintos() {
        assert!(is_prime(2) && is_prime(3) && is_prime(7919) && !is_prime(1) && !is_prime(7917));
        for size in [0.0, 0.3, 0.6, 1.0] {
            for rate in [22_050.0, 44_100.0, 48_000.0, 96_000.0, 192_000.0] {
                let mut rv = Reverb::new(rate);
                rv.set_param(P::SIZE, size);
                let lens: Vec<usize> = rv.lines.iter().map(|l| l.length.target as usize).collect();
                assert!(lens.iter().all(|&n| is_prime(n)), "{lens:?}");
                assert!(lens.windows(2).all(|w| w[0] < w[1]), "{lens:?}");
                for l in &rv.lines {
                    assert!((l.length.target + MOD_MS * 0.001 * rate as f32 + 2.0) < l.buf.len() as f32);
                }
            }
        }
    }

    #[test]
    fn decai_60_db_perto_do_rt60_pedido() {
        for (decay, size) in [(0.8, 0.3), (2.2, 0.6), (5.0, 1.0)] {
            let mut rv = wet_only(decay);
            rv.set_param(P::SIZE, size);
            let energy = impulse_energy(&mut rv, decay * 1.5 + 0.5);
            let rt60 = measure_rt60(&energy);
            assert!((rt60 / decay - 1.0).abs() < 0.15, "pedido {decay} s, medido {rt60} s");
        }
    }

    #[test]
    fn abafar_encurta_o_agudo() {
        // com abafamento em 2 kHz a cauda perde o agudo bem antes do grave
        let mut rv = wet_only(3.0);
        rv.set_param(P::DAMPING, 2000.0);
        let n = 48_000 * 2;
        let mut l = vec![0.0; n];
        let mut r = vec![0.0; n];
        l[0] = 1.0;
        run(&mut rv, &mut l, &mut r);
        // agudo ≈ diferença entre quadros vizinhos, grave ≈ média de 32 quadros
        let hf = |s: &[f32]| s.windows(2).map(|w| (w[1] - w[0]).powi(2)).sum::<f32>();
        let lf = |s: &[f32]| s.chunks(32).map(|c| (c.iter().sum::<f32>() / 32.0).powi(2)).sum::<f32>() * 32.0;
        let (early, late) = (&l[4800..14_400], &l[48_000..57_600]);
        let hf_drop = hf(late) / hf(early);
        let lf_drop = lf(late) / lf(early);
        assert!(hf_drop < lf_drop * 0.1, "agudo caiu {hf_drop}, grave {lf_drop}");
    }

    #[test]
    fn estavel_com_decaimento_de_20_s() {
        let mut rv = wet_only(20.0);
        rv.set_param(P::SIZE, 1.0);
        rv.set_param(P::MODULATION, 1.0);
        let n = 48_000 * 30;
        let mut l = noise(n, 1);
        let mut r = noise(n, 2);
        for v in l[24_000..].iter_mut().chain(r[24_000..].iter_mut()) {
            *v = 0.0;
        }
        run(&mut rv, &mut l, &mut r);
        assert!(l.iter().chain(&r).all(|v| v.is_finite()));
        let rms = |a: usize, b: usize| (l[a..b].iter().chain(&r[a..b]).map(|v| (*v as f64).powi(2)).sum::<f64>() / (2 * (b - a)) as f64).sqrt();
        let (first, last) = (rms(48_000, 96_000), rms(n - 48_000, n));
        // 28 s depois, 20 s de RT60: por volta de −84 dB (−3 dB/s)
        let drop = 20.0 * (last / first).log10();
        assert!((-95.0..-70.0).contains(&drop), "caiu {drop} dB");
    }

    #[test]
    fn congelar_mantem_a_energia_e_corta_a_entrada() {
        let mut rv = wet_only(1.5);
        let n = 48_000 * 10;
        let mut l = noise(n, 3);
        let mut r = noise(n, 4);
        for (chunk, (cl, cr)) in l.chunks_mut(128).zip(r.chunks_mut(128)).enumerate() {
            if chunk == 48_000 / 128 {
                rv.set_param(P::FREEZE, 1.0);
            }
            // depois de congelar a entrada dobra de volume: não pode entrar nada
            if chunk > 48_000 / 128 {
                for v in cl.iter_mut().chain(cr.iter_mut()) {
                    *v *= 2.0;
                }
            }
            rv.process(cl, cr);
        }
        let rms = |a: usize, b: usize| (l[a..b].iter().chain(&r[a..b]).map(|v| (*v as f64).powi(2)).sum::<f64>() / (2 * (b - a)) as f64).sqrt();
        let (before, early, late) = (rms(38_400, 48_000), rms(72_000, 120_000), rms(n - 48_000, n));
        let held = 20.0 * (late / early).log10();
        assert!(held.abs() < 0.5, "variou {held} dB em 7 s");
        // congelar não muda o nível da cauda (nem com a entrada dobrando: ela não entra mais)
        let jump = 20.0 * (early / before).log10();
        assert!((-2.0..1.0).contains(&jump), "antes {before}, congelado {early}: {jump} dB");
        // descongelar volta a decair
        rv.set_param(P::FREEZE, 0.0);
        let mut l = vec![0.0; 48_000 * 3];
        let mut r = vec![0.0; 48_000 * 3];
        run(&mut rv, &mut l, &mut r);
        let tail = l[l.len() - 4800..].iter().fold(0.0f32, |m, v| m.max(v.abs()));
        assert!(tail < 1e-2 * late as f32, "cauda {tail}");
    }

    #[test]
    fn mexer_com_som_passando_nao_estala() {
        // senoide pelo reverb com os botões mexendo. Estalo é banda larga: aparece na segunda
        // diferença, que numa senoide de 220 Hz (e na cauda dela) fica abaixo de 0,001; um degrau
        // de 1% do sinal já daria 0,005
        let mut rv = Reverb::new(RATE);
        rv.set_param(P::MIX, 0.5);
        let n = 48_000 * 6;
        let tone = |i: usize| (i as f32 * 220.0 / 48_000.0 * std::f32::consts::TAU).sin() * 0.5;
        let mut l: Vec<f32> = (0..n).map(tone).collect();
        let mut r = l.clone();
        let (mut steady, mut moving, mut last, mut last2) = (0.0f32, 0.0f32, 0.0f32, 0.0f32);
        for (k, (cl, cr)) in l.chunks_mut(128).zip(r.chunks_mut(128)).enumerate() {
            match k {
                750 => rv.set_param(P::PREDELAY, 0.25),
                900 => rv.set_param(P::SIZE, 1.0),
                1100 => rv.set_param(P::PREDELAY, 0.0),
                1250 => rv.set_param(P::SIZE, 0.0),
                1400 => rv.set_param(P::FREEZE, 1.0),
                1600 => rv.set_param(P::FREEZE, 0.0),
                1800 => rv.set_param(P::DECAY, 20.0),
                1900 => rv.set_param(P::DAMPING, 1000.0),
                _ => {}
            }
            rv.process(cl, cr);
            for &v in cl.iter() {
                let curve = (v - 2.0 * last + last2).abs();
                if (375..750).contains(&k) {
                    steady = steady.max(curve);
                } else if k >= 750 {
                    moving = moving.max(curve);
                }
                last2 = last;
                last = v;
            }
        }
        assert!(steady < 0.001, "parado {steady}");
        assert!(moving < 0.005, "mexendo {moving}");
    }

    #[test]
    fn mistura_zero_e_seco() {
        let mut rv = Reverb::new(RATE);
        rv.set_param(P::MIX, 0.0);
        let src = noise(9_600, 5);
        let mut l = src.clone();
        let mut r = src.clone();
        run(&mut rv, &mut l, &mut r);
        assert!(l.iter().zip(&src).all(|(a, b)| a == b));
        assert!(r.iter().zip(&src).all(|(a, b)| a == b));
    }

    #[test]
    fn largura_zero_e_mono_e_um_lado_so_espalha() {
        let mut rv = Reverb::new(RATE);
        rv.set_param(P::MIX, 1.0);
        rv.set_param(P::WIDTH, 0.0);
        let n = 48_000;
        let mut l = noise(n, 6);
        let mut r = vec![0.0; n];
        run(&mut rv, &mut l, &mut r);
        assert!(l.iter().zip(&r).all(|(a, b)| (a - b).abs() < 1e-6));
        let mut rv = Reverb::new(RATE);
        rv.set_param(P::MIX, 1.0);
        let mut l = noise(n, 6);
        let mut r = vec![0.0; n];
        run(&mut rv, &mut l, &mut r);
        let energy = |s: &[f32]| s.iter().map(|v| v * v).sum::<f32>();
        // entrada só na esquerda: a cauda aparece dos dois lados
        assert!(energy(&r[24_000..]) > 0.3 * energy(&l[24_000..]));
    }

    #[test]
    fn nivel_razoavel_no_padrao() {
        // ruído contínuo no padrão: o molhado fica na mesma ordem de grandeza da entrada
        let mut rv = Reverb::new(RATE);
        rv.set_param(P::MIX, 1.0);
        let n = 48_000 * 4;
        let src_l = noise(n, 7);
        let src_r = noise(n, 8);
        let (mut l, mut r) = (src_l.clone(), src_r.clone());
        run(&mut rv, &mut l, &mut r);
        let rms = |s: &[f32]| (s.iter().map(|v| v * v).sum::<f32>() / s.len() as f32).sqrt();
        let ratio = 20.0 * (rms(&l[96_000..]) / rms(&src_l[96_000..])).log10();
        assert!((-6.0..3.0).contains(&ratio), "molhado a {ratio} dB da entrada");
    }

    #[test]
    fn extremos_sem_nan() {
        let mut rng = crate::dsp::Rng::new(99);
        for round in 0..12 {
            let mut rv = Reverb::new(if round % 2 == 0 { 44_100.0 } else { 96_000.0 });
            for id in 0..10 {
                let v = match rng.next_u32() % 3 {
                    0 => -1e9,
                    1 => 1e9,
                    _ => rng.unit(),
                };
                rv.set_param(id, v);
            }
            rv.set_param(P::MIX, 1.0);
            let n = 48_000;
            let mut l = noise(n, round);
            let mut r = noise(n, round + 50);
            l[10] = 40.0;
            for (k, (cl, cr)) in l.chunks_mut(128).zip(r.chunks_mut(128)).enumerate() {
                // mexe no tamanho e no pré-atraso com som passando
                if k % 40 == 0 {
                    rv.set_param(P::SIZE, rng.unit());
                    rv.set_param(P::PREDELAY, rng.unit() * 0.3);
                }
                rv.process(cl, cr);
            }
            assert!(l.iter().chain(&r).all(|v| v.is_finite() && v.abs() < 100.0), "rodada {round}");
        }
    }

    #[test]
    fn dorme_no_silencio() {
        let mut rv = wet_only(0.5);
        let mut l = noise(4800, 1);
        let mut r = noise(4800, 2);
        run(&mut rv, &mut l, &mut r);
        let mut l = vec![0.0; 128];
        let mut r = vec![0.0; 128];
        for _ in 0..(4 * 48_000 / 128) {
            l.fill(0.0);
            r.fill(0.0);
            rv.process(&mut l, &mut r);
        }
        assert!(rv.idle);
        l[0] = 0.5;
        rv.process(&mut l, &mut r);
        assert!(!rv.idle);
    }
}
