//! EQ paramétrico de 8 bandas.
//!
//! Cada banda tem a resposta de um filtro do Audio EQ Cookbook (Robert Bristow-Johnson): o mesmo
//! protótipo analógico, pela mesma transformada bilinear com pré-distorção na frequência da banda.
//! A realização não é a forma direta do biquad, e sim o SVF trapezoidal de Andrew Simper
//! (Cytomic), que tem exatamente a mesma função de transferência e se comporta melhor nos dois
//! pontos que importam aqui: em f32 nos graves (a forma direta perde precisão com os polos colados
//! no círculo unitário, e um passa-alta de 48 dB a 20 Hz vira ruído) e sob modulação (o estado não
//! dá degrau quando os coeficientes andam, então arrastar a banda não estala).
//!
//! Para a interface desenhar a curva, espelhe o cookbook. Com f limitado a 0,49·taxa,
//! ω₀ = 2π·f/taxa, A = 10^(ganho/40), α = sen ω₀ / (2Q) e c = cos ω₀:
//!
//! - passa-alta: b = [(1 + c)/2, −(1 + c), (1 + c)/2], a = [1 + α, −2c, 1 − α]
//! - passa-baixa: b = [(1 − c)/2, 1 − c, (1 − c)/2], a = [1 + α, −2c, 1 − α]
//! - sino: b = [1 + αA, −2c, 1 − αA], a = [1 + α/A, −2c, 1 − α/A]
//! - prateleira grave: b = [A((A+1) − (A−1)c + 2√A·α), 2A((A−1) − (A+1)c), A((A+1) − (A−1)c − 2√A·α)],
//!   a = [(A+1) + (A−1)c + 2√A·α, −2((A−1) + (A+1)c), (A+1) + (A−1)c − 2√A·α]
//! - prateleira aguda: b = [A((A+1) + (A−1)c + 2√A·α), −2A((A−1) + (A+1)c), A((A+1) + (A−1)c − 2√A·α)],
//!   a = [(A+1) − (A−1)c + 2√A·α, 2((A−1) − (A+1)c), (A+1) − (A−1)c − 2√A·α]
//! - rejeita-faixa: b = [1, −2c, 1], a = [1 + α, −2c, 1 − α]
//!
//! O ganho de uma seção na frequência f (ω = 2π·f/taxa) é
//! |b₀ + b₁e^(−jω) + b₂e^(−2jω)| / |a₀ + a₁e^(−jω) + a₂e^(−2jω)|. Passa-alta e passa-baixa de 24 e
//! 48 dB/oit são cascatas de 2 e 4 seções (ganhos multiplicam) com os Q de um Butterworth de ordem
//! 4 e 8 ([`BUTTERWORTH`]); o Q da banda escala só a última seção (a de Q mais alto) por Q/√½, então
//! Q = 0,71 dá o Butterworth exato e Q maior põe ressonância no corte. Em 12 dB/oit a seção única
//! usa o Q da banda direto. A curva total é a soma em dB das bandas ligadas mais o ganho de saída.

use std::f32::consts::{FRAC_1_SQRT_2, PI};

use crate::dsp::{Smoothed, smoothing};
use crate::effect::{Effect, eq_param};

const BANDS: usize = eq_param::BANDS;
/// Seções de 2ª ordem por banda: 48 dB/oit = ordem 8.
const MAX_SECTIONS: usize = 4;
/// O projeto das seções é refeito a cada `SUB` quadros enquanto frequência, ganho ou Q andam, e
/// interpolado quadro a quadro no meio (ver [`Design`]).
const SUB: usize = 32;
/// Constante de tempo de cada um dos dois polos da suavização dos parâmetros contínuos (ver
/// [`Glide`]): absorve os degraus de um arrasto na interface (~60 atualizações por segundo) sem
/// deixar o botão mole.
const SMOOTH_SECS: f32 = 0.008;
/// Constante de tempo de cada polo do fade da troca discreta (ligar, desligar, mudar o tipo ou a
/// inclinação): a banda sai (−60 dB em ~13 ms), troca parada e volta, em vez de pular de um filtro
/// para outro com o estado velho.
const FADE_SECS: f32 = 0.0015;

/// Q das seções de 2ª ordem de um Butterworth de ordem 2, 4 e 8, índice = inclinação:
/// Q_k = 1 / (2·cos((2k − 1)·π / (2N))), k = 1..N/2, em ordem crescente.
pub const BUTTERWORTH: [&[f32]; 3] = [&[FRAC_1_SQRT_2], &[0.541_196_1, 1.306_563], &[0.509_795_6, 0.601_344_9, 0.899_976_2, 2.562_915_4]];

/// Suavização de 2ª ordem: dois polos em cascata. Com um polo só, a velocidade do parâmetro vai de
/// zero ao máximo no instante do pulo, e isso vira quina no som: num sino ressonante em cima do
/// sinal, num ganho grande, num fade que muda de ideia no meio. Com dois, a velocidade parte de
/// zero e muda sempre continuamente, até quando o alvo inverte. Os efeitos de dinâmica e o
/// utilitário usam o mesmo.
#[derive(Clone, Copy, Debug)]
pub(crate) struct Glide {
    first: Smoothed,
    second: Smoothed,
}

impl Glide {
    pub(crate) fn new(value: f32) -> Self {
        Self { first: Smoothed::new(value), second: Smoothed::new(value) }
    }

    pub(crate) fn set(&mut self, target: f32) {
        self.first.set(target);
    }

    pub(crate) fn snap(&mut self) {
        self.first.snap();
        self.second = self.first;
    }

    pub(crate) fn settled(&self) -> bool {
        self.first.settled() && self.second.settled() && self.second.value == self.first.value
    }

    pub(crate) fn value(&self) -> f32 {
        self.second.value
    }

    /// Anda um passo (fração `a` do caminho em cada polo) e devolve o valor novo.
    #[inline]
    pub(crate) fn step(&mut self, a: f32) -> f32 {
        self.second.set(self.first.step(a));
        self.second.step(a)
    }
}

/// Tipo da banda (valor do parâmetro `TYPE`).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Shape {
    HighPass,
    LowShelf,
    Bell,
    HighShelf,
    LowPass,
    Notch,
}

impl Shape {
    fn from_param(v: f32) -> Self {
        match v.round() as i32 {
            i32::MIN..=0 => Shape::HighPass,
            1 => Shape::LowShelf,
            2 => Shape::Bell,
            3 => Shape::HighShelf,
            4 => Shape::LowPass,
            _ => Shape::Notch,
        }
    }
}

/// A parte discreta de uma banda: mudar qualquer campo exige a troca com fade.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct Config {
    on: bool,
    shape: Shape,
    /// Índice em [`BUTTERWORTH`]; 0 fora do passa-alta/baixa, para mexer na inclinação de um sino
    /// não disparar troca nenhuma.
    slope: usize,
}

/// Uma seção de 2ª ordem pelos parâmetros de projeto: `g` = tan(π·f/taxa) já ajustado pelo tipo,
/// `k` = amortecimento (1/Q efetivo) e a mistura de saída y = m0·v0 + m1·v1 + m2·v2, onde v0 é a
/// entrada, v1 o passa-banda e v2 o passa-baixa (normalizados como no artigo de Simper).
///
/// Enquanto a banda anda, o projeto é refeito a cada `SUB` quadros e interpolado quadro a quadro
/// no meio: trocar os coeficientes em degrau faz a saída pular Δm·v (a 1,5 kHz, é o zíper de um
/// arrasto). Interpolar g e k, e não os coeficientes derivados, mantém cada passo intermediário
/// um SVF válido, e o SVF é estável com quaisquer g, k > 0.
#[derive(Clone, Copy, Debug, Default)]
struct Design {
    g: f32,
    k: f32,
    m0: f32,
    m1: f32,
    m2: f32,
}

impl Design {
    fn new(g: f32, k: f32, m0: f32, m1: f32, m2: f32) -> Self {
        Self { g, k, m0, m1, m2 }
    }

    #[inline]
    fn lerp(&self, to: &Design, t: f32) -> Design {
        Design {
            g: self.g + (to.g - self.g) * t,
            k: self.k + (to.k - self.k) * t,
            m0: self.m0 + (to.m0 - self.m0) * t,
            m1: self.m1 + (to.m1 - self.m1) * t,
            m2: self.m2 + (to.m2 - self.m2) * t,
        }
    }

    #[inline]
    fn section(&self) -> Section {
        let a1 = 1.0 / (1.0 + self.g * (self.g + self.k));
        let a2 = self.g * a1;
        Section { a1, a2, a3: self.g * a2, m0: self.m0, m1: self.m1, m2: self.m2 }
    }
}

/// Os coeficientes prontos de um SVF trapezoidal (o que roda por quadro).
#[derive(Clone, Copy, Debug, Default)]
struct Section {
    a1: f32,
    a2: f32,
    a3: f32,
    m0: f32,
    m1: f32,
    m2: f32,
}

impl Section {
    #[inline]
    fn tick(&self, s: &mut [f32; 2], v0: f32) -> f32 {
        let v3 = v0 - s[1];
        let v1 = self.a1 * s[0] + self.a2 * v3;
        let v2 = s[1] + self.a2 * s[0] + self.a3 * v3;
        s[0] = 2.0 * v1 - s[0];
        s[1] = 2.0 * v2 - s[1];
        self.m0 * v0 + self.m1 * v1 + self.m2 * v2
    }
}

struct Band {
    /// Pedido pelo app.
    on: bool,
    shape: Shape,
    slope: usize,
    /// Tocando agora; difere de `config()` só durante a troca.
    active: Config,
    /// log2 da frequência em Hz, ganho em dB e log2 do Q: frequência e Q andam em escala
    /// logarítmica, como o ouvido e o botão da interface.
    freq: Glide,
    gain: Glide,
    q: Glide,
    /// Projeto em uso (fim do último trecho), os coeficientes dele e o alvo do trecho atual.
    from: [Design; MAX_SECTIONS],
    sections: [Section; MAX_SECTIONS],
    to: [Design; MAX_SECTIONS],
    /// O trecho atual interpola de `from` a `to`.
    gliding: bool,
    count: usize,
    /// Estado (ic1, ic2) por canal e seção.
    state: [[[f32; 2]; MAX_SECTIONS]; 2],
    /// Quanto da banda entra (0 = a entrada passa direto, 1 = só a banda), para trocar sem estalo.
    wet: Glide,
    dirty: bool,
    /// Estado recém-zerado: o primeiro quadro do próximo trecho o põe no regime (ver `prime`).
    fresh_state: bool,
}

impl Band {
    fn new(on: bool, shape: Shape, freq: f32, q: f32) -> Self {
        let mut band = Self {
            on,
            shape,
            slope: 1,
            active: Config { on: false, shape, slope: 0 },
            freq: Glide::new(freq.log2()),
            gain: Glide::new(0.0),
            q: Glide::new(q.log2()),
            from: [Design::default(); MAX_SECTIONS],
            sections: [Section::default(); MAX_SECTIONS],
            to: [Design::default(); MAX_SECTIONS],
            gliding: false,
            count: 1,
            state: [[[0.0; 2]; MAX_SECTIONS]; 2],
            wet: Glide::new(0.0),
            dirty: true,
            fresh_state: true,
        };
        band.snap();
        band
    }

    fn config(&self) -> Config {
        let slope = if matches!(self.shape, Shape::HighPass | Shape::LowPass) { self.slope } else { 0 };
        Config { on: self.on, shape: self.shape, slope }
    }

    /// Vai direto ao pedido, sem suavizar nem fazer fade (antes do primeiro bloco e no reset).
    fn snap(&mut self) {
        self.freq.snap();
        self.gain.snap();
        self.q.snap();
        self.active = self.config();
        self.wet.set(if self.active.on { 1.0 } else { 0.0 });
        self.wet.snap();
        self.state = [[[0.0; 2]; MAX_SECTIONS]; 2];
        self.fresh_state = true;
        self.dirty = true;
    }

    /// Projeta as seções (em `to`) a partir dos valores suavizados atuais.
    fn design(&mut self, rate: f32, max_freq: f32) {
        let f = self.freq.value().exp2().clamp(20.0, max_freq);
        let q = self.q.value().exp2().clamp(0.1, 18.0);
        let w = (PI * f / rate).tan();
        let a = (self.gain.value() * (std::f32::consts::LN_10 / 40.0)).exp();
        let k = 1.0 / q;
        self.count = 1;
        self.to[0] = match self.active.shape {
            Shape::HighPass | Shape::LowPass => {
                let qs = BUTTERWORTH[self.active.slope];
                for (i, &bq) in qs.iter().enumerate() {
                    let qi = if i + 1 == qs.len() { bq * q / FRAC_1_SQRT_2 } else { bq };
                    let k = 1.0 / qi;
                    self.to[i] = if self.active.shape == Shape::HighPass { Design::new(w, k, 1.0, -k, -1.0) } else { Design::new(w, k, 0.0, 0.0, 1.0) };
                }
                self.count = qs.len();
                self.to[0]
            }
            Shape::Bell => {
                let k = 1.0 / (q * a);
                Design::new(w, k, 1.0, k * (a * a - 1.0), 0.0)
            }
            Shape::LowShelf => Design::new(w / a.sqrt(), k, 1.0, k * (a - 1.0), a * a - 1.0),
            Shape::HighShelf => Design::new(w * a.sqrt(), k, a * a, k * (1.0 - a) * a, 1.0 - a * a),
            Shape::Notch => Design::new(w, k, 1.0, -k, 0.0),
        };
    }

    /// Passa a usar `to` de vez (fim de um trecho interpolado, ou estado novo sem o que interpolar).
    fn settle(&mut self) {
        self.from = self.to;
        for (s, d) in self.sections.iter_mut().zip(&self.to).take(self.count) {
            *s = d.section();
        }
        self.gliding = false;
    }

    /// Começo de cada trecho de `SUB` quadros: conduz a troca discreta e a suavização.
    fn update(&mut self, rate: f32, max_freq: f32, a: f32) {
        let want = self.config();
        if want != self.active {
            if !self.active.on || (self.wet.settled() && self.wet.value() == 0.0) {
                // nada desta banda está soando: troca parada, com o estado zerado, e sobe
                self.active = want;
                self.state = [[[0.0; 2]; MAX_SECTIONS]; 2];
                self.fresh_state = true;
                self.wet.set(if want.on { 1.0 } else { 0.0 });
                self.dirty = true;
            } else {
                self.wet.set(0.0);
            }
        } else if self.active.on {
            // uma troca desfeita no meio do fade (ligou e desligou, voltou o tipo): a banda volta
            self.wet.set(1.0);
        }
        let moving = !(self.freq.settled() && self.gain.settled() && self.q.settled());
        if moving {
            self.freq.step(a);
            self.gain.step(a);
            self.q.step(a);
        }
        if self.active.on && (moving || self.dirty) {
            self.design(rate, max_freq);
            if self.dirty {
                // estado zerado (troca ou reset): não há de onde interpolar
                self.settle();
            } else {
                self.gliding = true;
            }
            self.dirty = false;
        }
    }

    /// Põe o estado zerado no regime de CC da entrada atual (ic1 = 0, ic2 = entrada da seção): o
    /// filtro novo começa como se já estivesse rodando, em vez de soltar a resposta ao degrau (um
    /// toque na frequência da banda) por baixo do fade. Para o que está abaixo do corte, é quase
    /// exato; para o resto, sobra um transitório pequeno e na frequência de corte.
    fn prime(&mut self, l: f32, r: f32) {
        for (c, x0) in [l, r].into_iter().enumerate() {
            let mut x = if x0.is_finite() { x0 } else { 0.0 };
            for (s, d) in self.state[c].iter_mut().zip(&self.from).take(self.count) {
                *s = [0.0, x];
                // ganho em CC da seção: v1 = 0 e v2 = x
                x *= d.m0 + d.m2;
            }
        }
        self.fresh_state = false;
    }

    fn process(&mut self, left: &mut [f32], right: &mut [f32], fade: f32) {
        if self.fresh_state
            && let (Some(&l), Some(&r)) = (left.first(), right.first())
        {
            self.prime(l, r);
        }
        let n = self.count;
        let [sl, sr] = &mut self.state;
        if !self.gliding && self.wet.settled() && self.wet.value() == 1.0 {
            let secs = &self.sections[..n];
            for (a, b) in left.iter_mut().zip(right.iter_mut()) {
                let (mut x, mut y) = (*a, *b);
                for (i, s) in secs.iter().enumerate() {
                    x = s.tick(&mut sl[i], x);
                    y = s.tick(&mut sr[i], y);
                }
                *a = x;
                *b = y;
            }
            return;
        }
        // caminho geral: interpolando o projeto e/ou no meio de um fade
        let (from, to, fixed, gliding) = (self.from, self.to, self.sections, self.gliding);
        let dt = 1.0 / left.len().max(1) as f32;
        for (j, (a, b)) in left.iter_mut().zip(right.iter_mut()).enumerate() {
            let m = self.wet.step(fade);
            let t = (j + 1) as f32 * dt;
            let (mut x, mut y) = (*a, *b);
            for i in 0..n {
                let s = if gliding { from[i].lerp(&to[i], t).section() } else { fixed[i] };
                x = s.tick(&mut sl[i], x);
                y = s.tick(&mut sr[i], y);
            }
            *a += m * (x - *a);
            *b += m * (y - *b);
        }
        if gliding {
            self.settle();
        }
    }

    /// Fim do bloco: estados minúsculos viram zero (a cauda de um filtro em silêncio vira denormal)
    /// e um estado que deixou de ser finito (entrada com NaN) é esquecido em vez de envenenar a
    /// banda para sempre.
    fn flush(&mut self) {
        for ch in &mut self.state {
            for s in ch.iter_mut() {
                for v in s.iter_mut() {
                    if v.abs() < 1e-15 {
                        *v = 0.0;
                    }
                }
            }
        }
        if !self.state.iter().flatten().flatten().all(|v| v.is_finite()) {
            self.state = [[[0.0; 2]; MAX_SECTIONS]; 2];
        }
    }
}

pub struct Eq {
    rate: f32,
    max_freq: f32,
    bands: [Band; BANDS],
    /// Ganho de saída linear.
    out: Glide,
    /// Fração do caminho da suavização por trecho de `SUB` quadros e por quadro.
    smooth_sub: f32,
    smooth_frame: f32,
    fade: f32,
    /// Nenhum bloco processado desde a criação ou o reset: parâmetros entram direto, sem rampa
    /// (abrir um projeto não pode varrer as bandas a partir do padrão).
    fresh: bool,
}

impl Eq {
    pub fn new(rate: f64) -> Self {
        let rate = rate as f32;
        // o padrão do app (effects.dart): bandas das pontas desligadas, as do meio em 0 dB
        const FREQS: [f32; BANDS] = [30.0, 100.0, 250.0, 800.0, 2500.0, 6000.0, 12000.0, 18000.0];
        const SHAPES: [Shape; BANDS] = [Shape::HighPass, Shape::LowShelf, Shape::Bell, Shape::Bell, Shape::Bell, Shape::Bell, Shape::HighShelf, Shape::LowPass];
        let bands = std::array::from_fn(|b| {
            let q = if SHAPES[b] == Shape::Bell { 1.0 } else { 0.71 };
            Band::new(b != 0 && b != BANDS - 1, SHAPES[b], FREQS[b], q)
        });
        Self {
            rate,
            max_freq: (0.49 * rate).min(20_000.0),
            bands,
            out: Glide::new(1.0),
            smooth_sub: smoothing(SMOOTH_SECS, SUB, rate),
            smooth_frame: smoothing(SMOOTH_SECS, 1, rate),
            fade: smoothing(FADE_SECS, 1, rate),
            fresh: true,
        }
    }
}

impl Effect for Eq {
    fn set_param(&mut self, id: u32, value: f32) {
        if !value.is_finite() {
            return;
        }
        if id == eq_param::OUTPUT {
            self.out.set((value.clamp(-24.0, 24.0) * (std::f32::consts::LN_10 / 20.0)).exp());
            if self.fresh {
                self.out.snap();
            }
            return;
        }
        let Some(band) = self.bands.get_mut((id / 6) as usize) else { return };
        match id % 6 {
            eq_param::ON => band.on = value >= 0.5,
            eq_param::TYPE => band.shape = Shape::from_param(value),
            eq_param::FREQ => band.freq.set(value.clamp(20.0, 20_000.0).log2()),
            eq_param::GAIN => band.gain.set(value.clamp(-24.0, 24.0)),
            eq_param::Q => band.q.set(value.clamp(0.1, 18.0).log2()),
            _ => band.slope = (value.round() as i32).clamp(0, 2) as usize,
        }
        if self.fresh {
            band.snap();
        }
    }

    fn process(&mut self, left: &mut [f32], right: &mut [f32]) {
        self.fresh = false;
        let n = left.len().min(right.len());
        let (left, right) = (&mut left[..n], &mut right[..n]);
        for (l, r) in left.chunks_mut(SUB).zip(right.chunks_mut(SUB)) {
            for band in &mut self.bands {
                band.update(self.rate, self.max_freq, self.smooth_sub);
                if band.active.on {
                    band.process(l, r, self.fade);
                }
            }
        }
        if self.out.settled() {
            let g = self.out.value();
            if g != 1.0 {
                for (a, b) in left.iter_mut().zip(right.iter_mut()) {
                    *a *= g;
                    *b *= g;
                }
            }
        } else {
            for (a, b) in left.iter_mut().zip(right.iter_mut()) {
                let g = self.out.step(self.smooth_frame);
                *a *= g;
                *b *= g;
            }
        }
        for band in &mut self.bands {
            band.flush();
        }
    }

    fn reset(&mut self) {
        for band in &mut self.bands {
            band.snap();
        }
        self.out.snap();
        self.fresh = true;
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::f64::consts::PI as PI64;

    const RATE: f64 = 48_000.0;

    fn band(eq: &mut Eq, b: u32, shape: f32, freq: f32, gain: f32, q: f32, slope: f32) {
        eq.set_param(b * 6 + eq_param::ON, 1.0);
        eq.set_param(b * 6 + eq_param::TYPE, shape);
        eq.set_param(b * 6 + eq_param::FREQ, freq);
        eq.set_param(b * 6 + eq_param::GAIN, gain);
        eq.set_param(b * 6 + eq_param::Q, q);
        eq.set_param(b * 6 + eq_param::SLOPE, slope);
    }

    /// Um EQ com todas as bandas desligadas.
    fn flat() -> Eq {
        let mut eq = Eq::new(RATE);
        for b in 0..BANDS as u32 {
            eq.set_param(b * 6 + eq_param::ON, 0.0);
        }
        eq
    }

    fn sine(freq: f64, amp: f32, n: usize) -> Vec<f32> {
        (0..n).map(|i| (amp as f64 * (2.0 * PI64 * freq * i as f64 / RATE).sin()) as f32).collect()
    }

    fn rms(x: &[f32]) -> f64 {
        (x.iter().map(|&v| (v as f64) * (v as f64)).sum::<f64>() / x.len() as f64).sqrt()
    }

    /// Ganho em dB que o EQ dá a uma senoide de `freq`, medido depois do transitório.
    fn gain_at(eq: &mut Eq, freq: f64) -> f64 {
        gain_over(eq, freq, 1.0)
    }

    /// Como [`gain_at`], com `secs` de sinal (graves de ordem alta demoram a assentar).
    fn gain_over(eq: &mut Eq, freq: f64, secs: f64) -> f64 {
        eq.reset_state_only();
        let n = (RATE * secs) as usize;
        let src = sine(freq, 0.25, n);
        let (mut l, mut r) = (src.clone(), src.clone());
        for (cl, cr) in l.chunks_mut(128).zip(r.chunks_mut(128)) {
            eq.process(cl, cr);
        }
        let tail = n / 2;
        20.0 * (rms(&l[tail..]) / rms(&src[tail..])).log10()
    }

    impl Eq {
        /// Zera os estados sem mexer nos parâmetros (entre medições).
        fn reset_state_only(&mut self) {
            for band in &mut self.bands {
                band.state = [[[0.0; 2]; MAX_SECTIONS]; 2];
            }
        }
    }

    /// Referência: o biquad do cookbook, avaliado em f64 direto dos coeficientes.
    fn rbj_db(shape: Shape, f0: f64, gain: f64, q: f64, f: f64) -> f64 {
        let w0 = 2.0 * PI64 * f0 / RATE;
        let (s, c) = w0.sin_cos();
        let a = 10f64.powf(gain / 40.0);
        let alpha = s / (2.0 * q);
        let sa = 2.0 * a.sqrt() * alpha;
        let (b, den) = match shape {
            Shape::HighPass => ([(1.0 + c) / 2.0, -(1.0 + c), (1.0 + c) / 2.0], [1.0 + alpha, -2.0 * c, 1.0 - alpha]),
            Shape::LowPass => ([(1.0 - c) / 2.0, 1.0 - c, (1.0 - c) / 2.0], [1.0 + alpha, -2.0 * c, 1.0 - alpha]),
            Shape::Bell => ([1.0 + alpha * a, -2.0 * c, 1.0 - alpha * a], [1.0 + alpha / a, -2.0 * c, 1.0 - alpha / a]),
            Shape::LowShelf => (
                [a * ((a + 1.0) - (a - 1.0) * c + sa), 2.0 * a * ((a - 1.0) - (a + 1.0) * c), a * ((a + 1.0) - (a - 1.0) * c - sa)],
                [(a + 1.0) + (a - 1.0) * c + sa, -2.0 * ((a - 1.0) + (a + 1.0) * c), (a + 1.0) + (a - 1.0) * c - sa],
            ),
            Shape::HighShelf => (
                [a * ((a + 1.0) + (a - 1.0) * c + sa), -2.0 * a * ((a - 1.0) + (a + 1.0) * c), a * ((a + 1.0) + (a - 1.0) * c - sa)],
                [(a + 1.0) - (a - 1.0) * c + sa, 2.0 * ((a - 1.0) - (a + 1.0) * c), (a + 1.0) - (a - 1.0) * c - sa],
            ),
            Shape::Notch => ([1.0, -2.0 * c, 1.0], [1.0 + alpha, -2.0 * c, 1.0 - alpha]),
        };
        let w = 2.0 * PI64 * f / RATE;
        let mag = |k: [f64; 3]| {
            let re = k[0] + k[1] * w.cos() + k[2] * (2.0 * w).cos();
            let im = -k[1] * w.sin() - k[2] * (2.0 * w).sin();
            (re * re + im * im).sqrt()
        };
        20.0 * (mag(b) / mag(den)).log10()
    }

    #[test]
    fn sino_de_12_db() {
        let mut eq = flat();
        band(&mut eq, 3, 2.0, 1000.0, 12.0, 1.0, 0.0);
        let at = gain_at(&mut eq, 1000.0);
        assert!((at - 12.0).abs() < 0.1, "1 kHz: {at}");
        for f in [40.0, 16_000.0] {
            let g = gain_at(&mut eq, f);
            assert!(g.abs() < 0.3, "{f} Hz: {g}");
        }
    }

    #[test]
    fn passa_alta_por_oitava() {
        // Butterworth de ordem N uma oitava abaixo do corte: −10·log10(1 + 2^(2N)) dB
        for (slope, expect) in [(0.0, -12.3), (1.0, -24.1), (2.0, -48.2)] {
            let mut eq = flat();
            band(&mut eq, 0, 0.0, 1000.0, 0.0, 0.71, slope);
            let below = gain_at(&mut eq, 500.0);
            assert!((below - expect).abs() < 1.0, "inclinação {slope}: {below} dB em 500 Hz");
            let at = gain_at(&mut eq, 1000.0);
            assert!((at + 3.0).abs() < 0.3, "inclinação {slope}: {at} dB no corte");
            let above = gain_at(&mut eq, 5000.0);
            assert!(above.abs() < 0.2, "inclinação {slope}: {above} dB em 5 kHz");
        }
        // passa-baixa espelhado
        let mut eq = flat();
        band(&mut eq, 7, 4.0, 1000.0, 0.0, 0.71, 1.0);
        let above = gain_at(&mut eq, 2000.0);
        assert!((above + 24.1).abs() < 1.0, "passa-baixa: {above}");
    }

    #[test]
    fn respostas_iguais_ao_cookbook() {
        let cases = [
            (Shape::HighPass, 0.0, 2.0),
            (Shape::LowPass, 0.0, 2.0),
            (Shape::Bell, -9.0, 3.0),
            (Shape::Bell, 18.0, 0.4),
            (Shape::LowShelf, 10.0, 0.71),
            (Shape::LowShelf, -15.0, 1.5),
            (Shape::HighShelf, 8.0, 0.71),
            (Shape::HighShelf, -20.0, 2.0),
            (Shape::Notch, 0.0, 4.0),
        ];
        for (shape, gain, q) in cases {
            let code = match shape {
                Shape::HighPass => 0.0,
                Shape::LowShelf => 1.0,
                Shape::Bell => 2.0,
                Shape::HighShelf => 3.0,
                Shape::LowPass => 4.0,
                Shape::Notch => 5.0,
            };
            let mut eq = flat();
            band(&mut eq, 2, code, 2000.0, gain as f32, q as f32, 0.0);
            for f in [100.0, 700.0, 1900.0, 3000.0, 9000.0] {
                let want = rbj_db(shape, 2000.0, gain, q, f);
                let got = gain_at(&mut eq, f);
                // o rejeita-faixa vai a −∞ no centro; lá só importa que corte muito
                let tol = if want < -40.0 { 3.0 } else { 0.1 };
                assert!((got - want).abs() < tol, "{shape:?} {gain} dB Q {q} em {f} Hz: {got} (cookbook {want})");
            }
        }
    }

    #[test]
    fn butterworth_confere() {
        for (slope, qs) in BUTTERWORTH.iter().enumerate() {
            let order = 2usize << slope;
            for (k, &q) in qs.iter().enumerate() {
                let want = 1.0 / (2.0 * ((2 * k + 1) as f64 * PI64 / (2 * order) as f64).cos());
                assert!((q as f64 - want).abs() < 1e-6, "ordem {order}, seção {k}: {q} ≠ {want}");
            }
        }
    }

    #[test]
    fn tudo_desligado_e_transparente() {
        let mut eq = flat();
        let src = sine(440.0, 0.8, 4096);
        let (mut l, mut r) = (src.clone(), src.clone());
        eq.process(&mut l, &mut r);
        assert_eq!(l, src);
        assert_eq!(r, src);
        // e o padrão do app (bandas do meio ligadas em 0 dB) também não mexe no som
        let mut eq = Eq::new(RATE);
        let (mut l, mut r) = (src.clone(), src.clone());
        eq.process(&mut l, &mut r);
        let err = l.iter().zip(&src).fold(0.0f32, |m, (a, b)| m.max((a - b).abs()));
        assert!(err < 1e-5, "{err}");
    }

    #[test]
    fn grave_extremo_em_f32() {
        // passa-alta de 48 dB em 20 Hz: a forma direta em f32 perde a resposta aqui; o SVF não
        let mut eq = flat();
        band(&mut eq, 0, 0.0, 20.0, 0.0, 0.71, 2.0);
        let below = gain_over(&mut eq, 10.0, 4.0);
        assert!((below + 48.2).abs() < 1.0, "10 Hz: {below}");
        let at = gain_over(&mut eq, 20.0, 4.0);
        assert!((at + 3.0).abs() < 0.3, "20 Hz: {at}");
        let pass = gain_at(&mut eq, 1000.0);
        assert!(pass.abs() < 0.01, "1 kHz: {pass}");
        // e uma prateleira grave de +12 dB em 40 Hz chega aos +12 lá embaixo
        let mut eq = flat();
        band(&mut eq, 1, 1.0, 40.0, 12.0, 0.71, 0.0);
        let low = gain_over(&mut eq, 5.0, 4.0);
        assert!((low - 12.0).abs() < 0.3, "5 Hz: {low}");
    }

    #[test]
    fn troca_desfeita_no_meio_volta() {
        let mut eq = flat();
        band(&mut eq, 3, 2.0, 1000.0, 12.0, 1.0, 0.0);
        let (mut l, mut r) = (vec![0.0; 256], vec![0.0; 256]);
        eq.process(&mut l, &mut r);
        // vira passa-alta e, antes de o fade de saída acabar, volta a ser sino
        eq.set_param(3 * 6 + eq_param::TYPE, 0.0);
        let (mut l, mut r) = (vec![0.0; 64], vec![0.0; 64]);
        eq.process(&mut l, &mut r);
        eq.set_param(3 * 6 + eq_param::TYPE, 2.0);
        let at = gain_at(&mut eq, 1000.0);
        assert!((at - 12.0).abs() < 0.1, "{at}");
        // e o mesmo com liga/desliga
        eq.set_param(3 * 6 + eq_param::ON, 0.0);
        let (mut l, mut r) = (vec![0.0; 64], vec![0.0; 64]);
        eq.process(&mut l, &mut r);
        eq.set_param(3 * 6 + eq_param::ON, 1.0);
        let at = gain_at(&mut eq, 1000.0);
        assert!((at - 12.0).abs() < 0.1, "{at}");
    }

    #[test]
    fn ganho_de_saida() {
        let mut eq = flat();
        eq.set_param(eq_param::OUTPUT, -6.0);
        let g = gain_at(&mut eq, 1000.0);
        assert!((g + 6.0).abs() < 0.01, "{g}");
    }

    /// Maior salto entre quadros vizinhos: um estalo aparece como um salto muito maior que o da
    /// própria senoide.
    fn max_step(x: &[f32]) -> f32 {
        x.windows(2).fold(0.0f32, |m, w| m.max((w[1] - w[0]).abs()))
    }

    #[test]
    fn arrastar_a_banda_nao_estala() {
        let mut eq = flat();
        band(&mut eq, 3, 2.0, 100.0, 12.0, 4.0, 0.0);
        let src = sine(200.0, 0.2, 96_000);
        let (mut l, mut r) = (src.clone(), src.clone());
        // um arrasto de 100 Hz a 10 kHz e de volta, em degraus a cada bloco, como o app manda
        for (i, (cl, cr)) in l.chunks_mut(128).zip(r.chunks_mut(128)).enumerate() {
            let t = i as f32 / 375.0;
            let f = 100.0 * 100f32.powf(if t < 1.0 { t } else { 2.0 - t });
            eq.set_param(3 * 6 + eq_param::FREQ, f);
            eq.set_param(3 * 6 + eq_param::GAIN, if i % 40 < 20 { 12.0 } else { -12.0 });
            eq.process(cl, cr);
        }
        // a senoide limpa com +12 dB anda no máximo 0,2·4·2π·200/48000 ≈ 0,021 por quadro (mais o
        // transitório da ressonância com Q 4); coeficiente trocado sem suavizar pularia ~0,6
        let step = max_step(&l);
        assert!(step < 0.06, "salto de {step}");
        assert!(l.iter().all(|v| v.is_finite()));
    }

    #[test]
    fn trocar_tipo_nao_estala() {
        let mut eq = flat();
        band(&mut eq, 2, 2.0, 300.0, 18.0, 2.0, 0.0);
        let src = sine(300.0, 0.1, 48_000);
        let (mut l, mut r) = (src.clone(), src.clone());
        for (i, (cl, cr)) in l.chunks_mut(128).zip(r.chunks_mut(128)).enumerate() {
            match i {
                60 => eq.set_param(2 * 6 + eq_param::TYPE, 4.0),
                120 => eq.set_param(2 * 6 + eq_param::SLOPE, 2.0),
                180 => eq.set_param(2 * 6 + eq_param::ON, 0.0),
                240 => eq.set_param(2 * 6 + eq_param::ON, 1.0),
                300 => eq.set_param(2 * 6 + eq_param::TYPE, 0.0),
                _ => {}
            }
            eq.process(cl, cr);
        }
        // +18 dB em 300 Hz: 0,1·7,94·2π·300/48000 ≈ 0,031 por quadro no pior trecho
        let step = max_step(&l);
        assert!(step < 0.045, "salto de {step}");
    }

    /// O uso de verdade: uma senoide tocando enquanto alguém mexe em tudo no painel, em momentos
    /// aleatórios, chaves incluídas. Estalo é descontinuidade, e descontinuidade aparece na segunda
    /// diferença, medida relativa ao nível do sinal ali (o EQ empilha ganhos até ~5): a da senoide
    /// de 110 Hz é (2π·110/48000)² ≈ 2e-4 do nível; um degrau de 1% do nível dá 0,01. Os defeitos
    /// que este teste achou mediam de 0,017 a 0,06 (zíper dos coeficientes, filtro novo partindo do
    /// zero, rampas de um polo); o pior uso legítimo (um fade de banda que revela sinal alto a
    /// partir do quase silêncio) fica perto de 0,006.
    /// Os tempos de ataque ficam acima de 1 ms e o lookahead acima de zero, porque ataque instantâneo
    /// quina o som de propósito (é o que o usuário pediu, não um defeito da troca). Quatro sorteios
    /// por padrão; `SEED=n` começa de outro, para caçar caso raro em lote.
    #[test]
    fn uso_mexendo_em_tudo_sem_estalo() {
        use crate::effect::{compressor_param as c, create, gate_param as g, kind, limiter_param as li, utility_param as u};
        /// (id, mínimo, máximo, discreto)
        type Knob = (u32, f32, f32, bool);
        let eq_params: Vec<Knob> = (0..BANDS as u32)
            .flat_map(|b| {
                [
                    (b * 6 + eq_param::ON, 0.0, 1.0, true),
                    (b * 6 + eq_param::TYPE, 0.0, 5.0, true),
                    (b * 6 + eq_param::FREQ, 60.0, 3000.0, false),
                    (b * 6 + eq_param::GAIN, -12.0, 12.0, false),
                    (b * 6 + eq_param::Q, 0.3, 4.0, false),
                    (b * 6 + eq_param::SLOPE, 0.0, 2.0, true),
                ]
            })
            .chain([(eq_param::OUTPUT, -12.0, 12.0, false)])
            .collect();
        let cases: [(&str, u32, Vec<Knob>); 5] = [
            ("EQ", kind::EQ, eq_params),
            (
                "compressor",
                kind::COMPRESSOR,
                vec![
                    (c::THRESHOLD, -40.0, 0.0, false),
                    (c::RATIO, 1.0, 20.0, false),
                    (c::ATTACK, 0.001, 0.25, false),
                    (c::RELEASE, 0.02, 3.0, false),
                    (c::KNEE, 0.0, 24.0, false),
                    (c::MAKEUP, 0.0, 12.0, false),
                    (c::MIX, 0.0, 1.0, false),
                    (c::DETECTOR, 0.0, 1.0, true),
                    (c::SC_HPF, 20.0, 500.0, false),
                    (c::AUTO_MAKEUP, 0.0, 1.0, true),
                ],
            ),
            (
                "gate",
                kind::GATE,
                vec![
                    (g::THRESHOLD, -30.0, 0.0, false),
                    (g::ATTACK, 0.002, 0.1, false),
                    (g::HOLD, 0.0, 0.2, false),
                    (g::RELEASE, 0.02, 2.0, false),
                    (g::RANGE, -80.0, 0.0, false),
                    (g::SC_HPF, 20.0, 300.0, false),
                ],
            ),
            (
                "limitador",
                kind::LIMITER,
                vec![
                    (li::GAIN, 0.0, 24.0, false),
                    (li::CEILING, -24.0, 0.0, false),
                    (li::RELEASE, 0.01, 1.0, false),
                    (li::LOOKAHEAD, 0.002, 0.01, false),
                    (li::LINK, 0.0, 1.0, false),
                ],
            ),
            (
                "utilitário",
                kind::UTILITY,
                vec![
                    (u::GAIN, -48.0, 12.0, false),
                    (u::PAN, -1.0, 1.0, false),
                    (u::WIDTH, 0.0, 2.0, false),
                    (u::MONO, 0.0, 1.0, true),
                    (u::INVERT_L, 0.0, 1.0, true),
                    (u::INVERT_R, 0.0, 1.0, true),
                    (u::SWAP, 0.0, 1.0, true),
                    (u::DC, 0.0, 1.0, true),
                ],
            ),
        ];
        let mut failed = vec![];
        let base: u32 = std::env::var("SEED").ok().and_then(|v| v.parse().ok()).unwrap_or(0);
        for (seed, (name, k, params)) in (base..base + 4).flat_map(|seed| cases.iter().map(move |c| (seed, c))) {
            let (name, k) = (*name, *k);
            let mut fx = create(k, RATE).unwrap();
            if k == kind::COMPRESSOR {
                fx.set_param(c::ATTACK, 0.005);
            }
            if k == kind::GATE {
                fx.set_param(g::ATTACK, 0.005);
            }
            let mut rng = crate::dsp::Rng::new(k * 7919 + seed * 104_729);
            let w = 2.0 * PI64 * 110.0 / RATE;
            let (mut prev, mut prev2) = ([0.0f32; 2], [0.0f32; 2]);
            let mut level = [0.0f32; 2];
            let mut worst = 0.0f32;
            let mut frame = 0usize;
            for block in 0..3000 {
                // um "clique" do usuário a cada ~5 blocos, às vezes vários de uma vez
                while rng.unit() < 0.2 {
                    let (id, lo, hi, discrete) = params[(rng.next_u32() as usize) % params.len()];
                    let v = lo + (hi - lo) * rng.unit();
                    fx.set_param(id, if discrete { v.round() } else { v });
                }
                let (mut l, mut r) = ([0.0f32; 128], [0.0f32; 128]);
                for (i, (a, b)) in l.iter_mut().zip(r.iter_mut()).enumerate() {
                    let t = (frame + i) as f64 * w;
                    // entra em 20 ms: o começo seco da senoide seria um degrau do próprio teste
                    let fade = ((frame + i) as f64 / 960.0).min(1.0);
                    *a = (0.5 * fade * t.sin()) as f32;
                    *b = (0.4 * fade * (t + 0.7).sin()) as f32;
                }
                fx.process(&mut l, &mut r);
                for i in 0..128 {
                    for (ch, y) in [l[i], r[i]].into_iter().enumerate() {
                        assert!(y.is_finite(), "{name}: saída não finita no bloco {block}");
                        // nível: pico com decaimento de ~20 ms; o que está baixo é julgado como se
                        // estivesse em −12 dBFS
                        level[ch] = y.abs().max(level[ch] * 0.999);
                        if frame + i >= 2 {
                            worst = worst.max((y - 2.0 * prev[ch] + prev2[ch]).abs() / level[ch].max(0.25));
                        }
                        prev2[ch] = prev[ch];
                        prev[ch] = y;
                    }
                }
                frame += 128;
            }
            println!("{name}, sorteio {seed}: maior segunda diferença relativa {worst:.5}");
            if worst >= 0.01 {
                failed.push(format!("{name}, sorteio {seed}: segunda diferença de {worst} (estalo)"));
            }
        }
        assert!(failed.is_empty(), "{failed:?}");
    }

    /// Custo dos efeitos de timbre e dinâmica em tempo real, em blocos de 128 com parâmetros
    /// mexendo (o pior caso da suavização): `cargo test --release -p jopendaw-engine desempenho_dinamica -- --ignored --nocapture`.
    #[test]
    #[ignore = "medição: cargo test --release -p jopendaw-engine desempenho_dinamica -- --ignored --nocapture"]
    fn desempenho_dinamica() {
        use crate::effect::{create, kind};
        let secs = 20.0;
        let frames = (secs * RATE) as usize;
        for (name, k, moving) in [
            ("EQ, 8 bandas (2 de 48 dB)", kind::EQ, 2 * 6 + eq_param::FREQ),
            ("compressor RMS", kind::COMPRESSOR, crate::effect::compressor_param::THRESHOLD),
            ("gate", kind::GATE, crate::effect::gate_param::THRESHOLD),
            ("limitador, 10 ms", kind::LIMITER, crate::effect::limiter_param::GAIN),
            ("utilitário", kind::UTILITY, crate::effect::utility_param::WIDTH),
        ] {
            let mut fx = create(k, RATE).unwrap();
            if k == kind::EQ {
                for b in 0..BANDS as u32 {
                    fx.set_param(b * 6 + eq_param::ON, 1.0);
                    fx.set_param(b * 6 + eq_param::GAIN, 3.0);
                }
                fx.set_param(eq_param::SLOPE, 2.0);
                fx.set_param(7 * 6 + eq_param::SLOPE, 2.0);
            }
            if k == kind::LIMITER {
                fx.set_param(crate::effect::limiter_param::LOOKAHEAD, 0.01);
            }
            let mut rng = crate::dsp::Rng::new(9);
            let (mut l, mut r) = ([0.0f32; 128], [0.0f32; 128]);
            let start = std::time::Instant::now();
            let mut done = 0;
            let mut i = 0u32;
            while done < frames {
                for (a, b) in l.iter_mut().zip(r.iter_mut()) {
                    *a = rng.bipolar() * 0.8;
                    *b = rng.bipolar() * 0.8;
                }
                i += 1;
                fx.set_param(moving, if i % 64 < 32 { -10.0 } else { 1000.0 + (i % 64) as f32 * 10.0 });
                fx.process(&mut l, &mut r);
                done += 128;
            }
            let took = start.elapsed().as_secs_f64();
            println!("{name}: {:.3}% de um núcleo ({:.1}× tempo real)", took / secs * 100.0, secs / took);
        }
    }

    #[test]
    fn extremos_sem_nan() {
        for rate in [22_050.0, 44_100.0, 192_000.0] {
            let mut eq = Eq::new(rate);
            let mut rng = crate::dsp::Rng::new(7);
            for b in 0..BANDS as u32 {
                eq.set_param(b * 6 + eq_param::ON, 1.0);
                eq.set_param(b * 6 + eq_param::TYPE, (b % 6) as f32);
                eq.set_param(b * 6 + eq_param::FREQ, if b % 2 == 0 { 1e9 } else { -5.0 });
                eq.set_param(b * 6 + eq_param::GAIN, if b % 3 == 0 { 1e9 } else { -1e9 });
                eq.set_param(b * 6 + eq_param::Q, if b % 2 == 0 { 1e9 } else { 0.0 });
                eq.set_param(b * 6 + eq_param::SLOPE, 99.0);
            }
            eq.set_param(eq_param::OUTPUT, f32::NAN);
            eq.set_param(eq_param::OUTPUT, 1e9);
            eq.set_param(999, 1.0);
            let (mut l, mut r): (Vec<f32>, Vec<f32>) = (0..8192).map(|_| (rng.bipolar() * 4.0, rng.bipolar())).unzip();
            for (cl, cr) in l.chunks_mut(100).zip(r.chunks_mut(100)) {
                eq.process(cl, cr);
            }
            assert!(l.iter().chain(&r).all(|v| v.is_finite()), "taxa {rate}");
            // modulando rápido entre os extremos
            for i in 0..200 {
                eq.set_param(2 * 6 + eq_param::FREQ, if i % 2 == 0 { 20.0 } else { 20_000.0 });
                eq.set_param(2 * 6 + eq_param::Q, if i % 3 == 0 { 0.1 } else { 18.0 });
                let (mut l, mut r) = (vec![0.5; 64], vec![-0.5; 64]);
                eq.process(&mut l, &mut r);
                assert!(l.iter().chain(&r).all(|v| v.is_finite()));
            }
            // com Q 18 nas pontas as ressonâncias somam mais de 100 dB, mas o filtro é estável:
            // parada a modulação, o silêncio apaga tudo (o polo lento do rejeita-faixa de 20 Hz com
            // Q 0,1 fica em 2 Hz, por isso 4 s)
            for _ in 0..(rate as usize * 4 / 128) {
                let (mut l, mut r) = (vec![0.0; 128], vec![0.0; 128]);
                eq.process(&mut l, &mut r);
            }
            let (mut l, mut r) = (vec![0.0; 128], vec![0.0; 128]);
            eq.process(&mut l, &mut r);
            assert!(l.iter().chain(&r).all(|v| v.abs() < 1e-6), "taxa {rate}: não decaiu");
            // um NaN na entrada não envenena o EQ para sempre
            let (mut l, mut r) = (vec![f32::NAN; 64], vec![0.0; 64]);
            eq.process(&mut l, &mut r);
            let (mut l, mut r) = (vec![0.1; 256], vec![0.1; 256]);
            eq.process(&mut l, &mut r);
            let (mut l, mut r) = (vec![0.1; 256], vec![0.1; 256]);
            eq.process(&mut l, &mut r);
            assert!(l.iter().chain(&r).all(|v| v.is_finite()));
            // e o silêncio longo leva os estados a zero, não a denormais
            for _ in 0..2000 {
                let (mut l, mut r) = (vec![0.0; 128], vec![0.0; 128]);
                eq.process(&mut l, &mut r);
            }
            for band in &eq.bands {
                assert!(band.state.iter().flatten().flatten().all(|v| *v == 0.0 || v.abs() > 1e-15));
            }
        }
    }
}
