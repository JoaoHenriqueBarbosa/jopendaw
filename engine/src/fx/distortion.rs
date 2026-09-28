//! Distorção: suave, válvula, fita, dura, dobra e bitcrusher.
//!
//! Por canal: drive → caminho do tipo → bloqueio de DC → tom → mistura com o seco → saída.
//!
//! Os tipos não lineares rodam sobreamostrados (1×, 2× ou 4×) entre meias-bandas FIR de fase
//! linear: a harmônica que a curva cria acima de Nyquist é filtrada antes de voltar à taxa do
//! projeto, em vez de rebater para o grave como aliasing. Fase linear porque a mistura paralela
//! soma seco e molhado: com um atraso inteiro e conhecido basta atrasar o seco igual, e a soma não
//! vira filtro pente. Esse atraso ([`LATENCY`]) é o mesmo em todos os modos e tipos, então trocar a
//! sobreamostragem ou o tipo não desloca o som; a troca em si é uma transição cruzada de 20 ms entre
//! dois caminhos, sem estalo.

use std::f32::consts::{FRAC_1_SQRT_2, LOG2_10, PI, SQRT_2};
use std::f64::consts::PI as PI64;
use std::sync::OnceLock;

use crate::dsp::{FilterMode, Rng, Smoothed, Svf, sin_turns, smoothing};
use crate::effect::{Effect, distortion_param as P};

/// Dither TPDF na quantização do bitcrusher (0/1, desligado no padrão). Adição ao contrato: a
/// tabela do app ainda não tem esse parâmetro.
pub const DITHER: u32 = 8;

/// Valores de [`P::TYPE`].
mod kind {
    pub const SOFT: u32 = 0;
    pub const VALVE: u32 = 1;
    pub const TAPE: u32 = 2;
    pub const HARD: u32 = 3;
    pub const FOLD: u32 = 4;
    pub const CRUSH: u32 = 5;
}

/// Quadros por passo de controle: ganhos e mistura andam em rampa linear dentro dele.
const CHUNK: usize = 16;
/// Constante de tempo da suavização dos botões.
const TAU: f32 = 0.02;
/// Duração da transição cruzada ao trocar de tipo ou de sobreamostragem.
const FADE: f32 = 0.02;
/// Amplitude de referência da compensação de ganho: um seno de −12 dBFS de pico, nível típico de
/// uma faixa. Nesse nível o volume fica parado ao girar o drive; abaixo dele a distorção sobe o
/// volume, como qualquer saturação.
const REF: f32 = 0.25;
/// Tabela de compensação: um ponto por dB de drive, 0..48.
const DRIVE_STEPS: usize = 49;

/// Meia-banda do 1º estágio (base ↔ 2×): N = 4·M1 + 3 = 55 coeficientes com janela de Kaiser.
/// Plana até 0,2·fs da taxa alta (19,2 kHz a 48 kHz), ≥ 85 dB de rejeição a partir de 0,3·fs:
/// o que rebate entre 20 e 24 kHz é inaudível, então a transição pode ser larga assim.
const M1: usize = 13;
const BETA1: f64 = 8.5;
/// 2º estágio (2× ↔ 4×): N = 19. Só precisa proteger 0..20 kHz de uma taxa quatro vezes maior, a
/// transição é larguíssima e poucos coeficientes dão ≥ 80 dB.
const M2: usize = 4;
const BETA2: f64 = 8.1;
/// Atraso do caminho molhado em quadros, igual em todos os modos. O 4× soma os dois estágios (o
/// 2º dá M2 + ½ quadro, arredondado por uma amostra de atraso na taxa 2×); os outros completam com
/// atraso puro.
pub const LATENCY: usize = 2 * M1 + 1 + M2 + 1;

/// Válvula: ponto de operação deslocado (harmônicas pares já em nível baixo) e o semiciclo negativo
/// saturando antes e mais duro que o positivo (assimetria em nível alto). O DC que isso gera sai no
/// bloqueio de DC.
const VALVE_BIAS: f32 = 0.15;
const VALVE_NEG: f32 = 2.0;

/// Fita: pré-ênfase de agudos antes da curva e o inverso depois. Em nível baixo as duas se anulam;
/// em nível alto o agudo, reforçado, satura primeiro e volta mais baixo: a perda de agudos da fita
/// saturada.
const TAPE_EMPHASIS_HZ: f32 = 3000.0;
const TAPE_EMPHASIS: f32 = 2.0;
/// Compressão leve antes da curva: ganho 1/√(1 + k·média quadrática), no máximo −6 dB.
const TAPE_SQUASH: f32 = 0.25;
const TAPE_SQUASH_TAU: f32 = 0.05;
/// Passa-baixa da cabeça: 18 kHz sem drive, uma oitava a menos a cada 32 dB de drive.
const TAPE_TOP_HZ: f32 = 18_000.0;
const TAPE_DB_PER_OCT: f32 = 32.0;

/// Bitcrusher: entrada abaixo de −100 dB vira zero. A quantização não tem nível zero (1 bit = dois
/// níveis, ±½): sem isso o silêncio viraria DC, e o fim de cada nota, um degrau.
const CRUSH_FLOOR: f32 = 1e-5;

/// O tom começa a abrir em 16 kHz e em 20 kHz sai da cadeia (o botão no máximo não filtra nada).
const OPEN_FROM: f32 = 13.965_784; // log2(16 000)
const OPEN_TO: f32 = 14.287_712; // log2(20 000)

/// Corte do bloqueio de DC.
const DC_HZ: f32 = 4.0;

#[inline]
fn db_to_gain(db: f32) -> f32 {
    (db * (LOG2_10 / 20.0)).exp2()
}

/// Entrada inválida (NaN, infinito, absurda) vira silêncio, e o denormal também: nada disso pode
/// entrar nos filtros.
#[inline]
fn sane(x: f32) -> f32 {
    let a = x.abs();
    if a > 1e-20 && a < 1e6 { x } else { 0.0 }
}

/// Tangente hiperbólica por Padé [7/6]: erro < 2e-4 em toda a reta, suave, e cruza o 1 perto de
/// 5, onde a derivada da tanh já é ~2e-4: a costura com o teto não vira quina.
#[inline]
fn tanh(x: f32) -> f32 {
    let x = x.clamp(-5.0, 5.0);
    let x2 = x * x;
    let p = x * (135_135.0 + x2 * (17_325.0 + x2 * (378.0 + x2)));
    let q = 135_135.0 + x2 * (62_370.0 + x2 * (3150.0 + x2 * 28.0));
    (p / q).clamp(-1.0, 1.0)
}

#[inline]
fn valve_raw(v: f32) -> f32 {
    if v >= 0.0 { tanh(v) } else { tanh(VALVE_NEG * v) * (1.0 / VALVE_NEG) }
}

/// Curva algébrica x/√(1 + x²): mais terceira harmônica que a tanh em nível baixo e chegada mais
/// lenta ao teto, o joelho largo da fita.
#[inline]
fn tape_curve(x: f32) -> f32 {
    let x = x.clamp(-1e4, 1e4);
    x / (1.0 + x * x).sqrt()
}

/// Dobrador senoidal: sen(x). Quase a identidade perto do zero, primeira dobra em ±π/2 e cada
/// excursão além disso volta refletida. A dobra triangular (a de quinas) tem harmônicas que caem
/// devagar demais: com drive alto o aliasing passava das próprias harmônicas mesmo a 4×. A senoidal
/// é lisa e sua banda termina perto de (amplitude × fundamental), então a sobreamostragem dá conta.
#[inline]
fn fold(x: f32) -> f32 {
    sin_turns(x.clamp(-1e4, 1e4) * (0.5 / PI))
}

/// Quantizador mid-rise de passo `step` em [−1, 1]: com 1 bit (passo 1), exatamente ±0,5.
#[inline]
fn quantize(x: f32, step: f32) -> f32 {
    let top = 1.0 - 0.5 * step;
    (((x / step).floor() + 0.5) * step).clamp(-top, top)
}

/// Curva estática de um tipo (o bitcrusher conta como corte rígido: a quantização em si não muda
/// o nível médio).
fn curve(k: u32, x: f32) -> f32 {
    match k {
        kind::SOFT => tanh(x),
        kind::VALVE => valve_raw(x + VALVE_BIAS) - valve_raw(VALVE_BIAS),
        kind::TAPE => tape_curve(x),
        kind::FOLD => fold(x),
        _ => x.clamp(-1.0, 1.0),
    }
}

/// Compensação por dB de drive: razão entre o RMS de um seno de referência e o RMS (sem DC) da
/// curva aplicada a ele com aquele drive. Integra num quarto de ciclo com `points` pontos (os
/// valores de um seno são ±sen θ com θ em [0, π/2]); só a válvula, assimétrica, precisa calcular o
/// semiciclo negativo e a média.
fn comp_table(k: u32, points: usize) -> [f32; DRIVE_STEPS] {
    let sines: Vec<f32> = (0..points).map(|i| ((i as f64 + 0.5) / points as f64 * PI64 * 0.5).sin() as f32).collect();
    let mut table = [1.0; DRIVE_STEPS];
    let rms_in = (REF * FRAC_1_SQRT_2) as f64;
    for (db, c) in table.iter_mut().enumerate() {
        let g = db_to_gain(db as f32) * REF;
        let (mut sum, mut sq) = (0.0f64, 0.0f64);
        for &s in &sines {
            let y = curve(k, g * s) as f64;
            // curva ímpar: o semiciclo negativo espelha o positivo
            let z = if k == kind::VALVE { curve(k, -g * s) as f64 } else { -y };
            sum += y + z;
            sq += y * y + z * z;
        }
        let n = (2 * points) as f64;
        let mean = sum / n;
        let rms = (sq / n - mean * mean).max(0.0).sqrt();
        *c = (rms_in / rms.max(1e-9)) as f32;
    }
    table
}

/// As tabelas de compensação dos seis tipos, calculadas uma vez por processo (na criação do
/// primeiro efeito, não na troca de tipo no meio da música). A dobra oscila várias vezes por ciclo
/// com drive alto e pede mais pontos.
fn comp_tables() -> &'static [[f32; DRIVE_STEPS]; 6] {
    static TABLES: OnceLock<[[f32; DRIVE_STEPS]; 6]> = OnceLock::new();
    TABLES.get_or_init(|| std::array::from_fn(|k| comp_table(k as u32, if k as u32 == kind::FOLD { 256 } else { 64 })))
}

/// Metade (de uma ponta até perto do centro) dos coeficientes não nulos fora do centro de uma
/// meia-banda de N = 4P − 1 coeficientes: seno cardinal com janela de Kaiser, normalizado para ganho
/// DC exato (os não nulos fora do centro somam ½, o centro vale ½).
fn half_band<const PAIRS: usize>(beta: f64) -> [f32; PAIRS] {
    fn i0(x: f64) -> f64 {
        let (mut sum, mut term, mut k) = (1.0, 1.0, 1.0);
        loop {
            term *= (x / (2.0 * k)) * (x / (2.0 * k));
            sum += term;
            if term < 1e-12 * sum {
                return sum;
            }
            k += 1.0;
        }
    }
    let center = (2 * PAIRS - 1) as f64;
    let mut h = [0.0f64; PAIRS];
    for (j, v) in h.iter_mut().enumerate() {
        let n = 2.0 * j as f64 - center;
        let r = n / center;
        *v = (PI64 * n * 0.5).sin() / (PI64 * n) * i0(beta * (1.0 - r * r).max(0.0).sqrt()) / i0(beta);
    }
    let sum: f64 = h.iter().sum();
    h.map(|v| (v * 0.25 / sum) as f32)
}

struct Coeffs {
    up1: [f32; M1 + 1],
    dn1: [f32; M1 + 1],
    up2: [f32; M2 + 1],
    dn2: [f32; M2 + 1],
}

impl Coeffs {
    fn new() -> Self {
        let h1 = half_band::<{ M1 + 1 }>(BETA1);
        let h2 = half_band::<{ M2 + 1 }>(BETA2);
        // interpolar enche de zeros metade das amostras: o ganho 2 devolve o nível
        Self { up1: h1.map(|v| 2.0 * v), dn1: h1, up2: h2.map(|v| 2.0 * v), dn2: h2 }
    }
}

/// Maior janela de histórico: o atraso de compensação, LATENCY + 1.
const RING: usize = 2 * (LATENCY + 1);

/// Histórico com cópia dupla: as últimas `len` amostras ficam sempre contíguas (a mais nova
/// primeiro), sem módulo no laço do FIR.
#[derive(Clone)]
struct Ring {
    buf: [f32; RING],
    pos: usize,
    len: usize,
}

impl Ring {
    fn new(len: usize) -> Self {
        assert!(len >= 1 && 2 * len <= RING);
        Self { buf: [0.0; RING], pos: 0, len }
    }

    fn clear(&mut self) {
        self.buf = [0.0; RING];
        self.pos = 0;
    }

    #[inline(always)]
    fn push(&mut self, x: f32) {
        self.pos = if self.pos == 0 { self.len - 1 } else { self.pos - 1 };
        self.buf[self.pos] = x;
        self.buf[self.pos + self.len] = x;
    }

    #[inline(always)]
    fn window(&self) -> &[f32] {
        &self.buf[self.pos..self.pos + self.len]
    }

    /// A amostra de `age` quadros atrás (0 = a mais nova).
    #[inline(always)]
    fn get(&self, age: usize) -> f32 {
        self.buf[self.pos + age]
    }
}

/// FIR simétrico: cada coeficiente multiplica o par de amostras equidistantes do centro.
#[inline(always)]
fn fir(c: &[f32], w: &[f32]) -> f32 {
    let n = w.len();
    let mut acc = 0.0;
    for (j, &cj) in c.iter().enumerate() {
        acc += cj * (w[j] + w[n - 1 - j]);
    }
    acc
}

/// Interpolação 2× polifásica de uma meia-banda: a fase par é o FIR, a ímpar só o centro (½·2 = 1),
/// isto é, a própria entrada atrasada de `m`.
#[inline(always)]
fn up(r: &mut Ring, c: &[f32], m: usize, x: f32) -> (f32, f32) {
    r.push(x);
    let w = r.window();
    (fir(c, w), w[m])
}

/// Decimação 2×: o par (v0, v1) vira uma amostra. As pares passam pelo FIR, as ímpares só pelo
/// centro.
#[inline(always)]
fn down(even: &mut Ring, odd: &mut Ring, c: &[f32], m: usize, v0: f32, v1: f32) -> f32 {
    even.push(v0);
    odd.push(v1);
    fir(c, even.window()) + 0.5 * odd.get(m + 1)
}

/// Filtro de 1ª ordem (prateleira de agudos da ênfase da fita), forma transposta.
#[derive(Clone, Copy, Default)]
struct FirstOrder {
    b0: f32,
    b1: f32,
    a1: f32,
    s: f32,
}

impl FirstOrder {
    /// Prateleira de agudos com ganho `gain` acima de `hz` (ganho 1 no DC), ou a inversa exata. A
    /// direta tem o zero dentro do círculo, então a inversa é estável.
    fn shelf(hz: f32, gain: f32, rate: f32, inverse: bool) -> Self {
        let k = (PI * hz.min(0.45 * rate) / rate).tan();
        let (mut n0, mut n1, mut d0, mut d1) = (gain + k, k - gain, 1.0 + k, k - 1.0);
        if inverse {
            std::mem::swap(&mut n0, &mut d0);
            std::mem::swap(&mut n1, &mut d1);
        }
        Self { b0: n0 / d0, b1: n1 / d0, a1: d1 / d0, s: 0.0 }
    }

    #[inline(always)]
    fn tick(&mut self, x: f32) -> f32 {
        let y = self.b0 * x + self.s;
        self.s = self.b1 * x - self.a1 * y;
        y
    }
}

/// O que um passo de controle entrega aos caminhos.
struct Ctl {
    tape_lp: f32,
    tape_ms: f32,
    crush_inc: f32,
    crush_step: f32,
    dither: bool,
}

/// Estado de um canal de um caminho.
#[derive(Clone)]
struct Chan {
    up1: Ring,
    dn1e: Ring,
    dn1o: Ring,
    up2: Ring,
    dn2e: Ring,
    dn2o: Ring,
    /// Atraso de uma amostra na taxa 2× do modo 4× (fecha o meio quadro do 2º estágio).
    z2: f32,
    pad: Ring,
    pre: FirstOrder,
    post: FirstOrder,
    lp: f32,
    ms: f32,
    phase: f32,
    hold: f32,
    rng: Rng,
}

impl Chan {
    fn new(pre: FirstOrder, post: FirstOrder, seed: u32) -> Self {
        Self {
            up1: Ring::new(2 * M1 + 2),
            dn1e: Ring::new(2 * M1 + 2),
            dn1o: Ring::new(M1 + 2),
            up2: Ring::new(2 * M2 + 2),
            dn2e: Ring::new(2 * M2 + 2),
            dn2o: Ring::new(M2 + 2),
            z2: 0.0,
            pad: Ring::new(LATENCY + 1),
            pre,
            post,
            lp: 0.0,
            ms: 0.0,
            phase: 1.0,
            hold: 0.0,
            rng: Rng::new(seed),
        }
    }

    fn clear(&mut self) {
        for r in [&mut self.up1, &mut self.dn1e, &mut self.dn1o, &mut self.up2, &mut self.dn2e, &mut self.dn2o, &mut self.pad] {
            r.clear();
        }
        self.z2 = 0.0;
        self.pre.s = 0.0;
        self.post.s = 0.0;
        self.lp = 0.0;
        self.ms = 0.0;
        // a primeira amostra já é capturada
        self.phase = 1.0;
        self.hold = 0.0;
    }

    fn flush(&mut self) {
        for v in [&mut self.pre.s, &mut self.post.s, &mut self.lp, &mut self.ms] {
            if v.abs() < 1e-15 {
                *v = 0.0;
            }
        }
    }

    fn finite(&self) -> bool {
        self.pre.s.is_finite() && self.post.s.is_finite() && self.lp.is_finite() && self.ms.is_finite()
    }

    /// Uma amostra pela curva `f` na taxa `os`× da base.
    #[inline(always)]
    fn core<F: Fn(f32) -> f32>(&mut self, c: &Coeffs, os: u32, x: f32, f: &F) -> f32 {
        match os {
            1 => f(x),
            2 => {
                let (a0, a1) = up(&mut self.up1, &c.up1, M1, x);
                down(&mut self.dn1e, &mut self.dn1o, &c.dn1, M1, f(a0), f(a1))
            }
            _ => {
                let (a0, a1) = up(&mut self.up1, &c.up1, M1, x);
                let (d0, d1) = (self.z2, a0);
                self.z2 = a1;
                let (b0, b1) = up(&mut self.up2, &c.up2, M2, d0);
                let (b2, b3) = up(&mut self.up2, &c.up2, M2, d1);
                let e0 = down(&mut self.dn2e, &mut self.dn2o, &c.dn2, M2, f(b0), f(b1));
                let e1 = down(&mut self.dn2e, &mut self.dn2o, &c.dn2, M2, f(b2), f(b3));
                down(&mut self.dn1e, &mut self.dn1o, &c.dn1, M1, e0, e1)
            }
        }
    }

    fn shape<F: Fn(f32) -> f32>(&mut self, c: &Coeffs, os: u32, pad: usize, v: &[f32], out: &mut [f32], f: F) {
        for (y, &x) in out.iter_mut().zip(v) {
            let w = self.core(c, os, x, &f);
            self.pad.push(w);
            *y = self.pad.get(pad);
        }
    }

    fn tape(&mut self, c: &Coeffs, ctl: &Ctl, os: u32, pad: usize, v: &[f32], out: &mut [f32]) {
        for (y, &x) in out.iter_mut().zip(v) {
            self.ms += (x * x - self.ms) * ctl.tape_ms;
            let squash = (1.0 + TAPE_SQUASH * self.ms).sqrt().recip().max(0.5);
            let e = self.pre.tick(x * squash);
            let w = self.core(c, os, e, &tape_curve);
            let w = self.post.tick(w);
            self.lp += (w - self.lp) * ctl.tape_lp;
            self.pad.push(self.lp);
            *y = self.pad.get(pad);
        }
    }

    fn crush(&mut self, ctl: &Ctl, pad: usize, v: &[f32], out: &mut [f32]) {
        let step = ctl.crush_step;
        for (y, &x) in out.iter_mut().zip(v) {
            // amostra e retém: com redução fracionária o intervalo entre capturas varia, na média
            // é o do botão, e mexer nele não dá degrau
            self.phase += ctl.crush_inc;
            if self.phase >= 1.0 {
                self.phase -= 1.0;
                self.hold = if x.abs() < CRUSH_FLOOR {
                    0.0
                } else {
                    // TPDF de ±1 degrau: o erro de quantização vira ruído em vez de distorção
                    let d = if ctl.dither { (self.rng.unit() - self.rng.unit()) * step } else { 0.0 };
                    quantize(x + d, step)
                };
            }
            self.pad.push(self.hold);
            *y = self.pad.get(pad);
        }
    }
}

/// Um caminho molhado completo (tipo + sobreamostragem). São dois: na troca, o novo entra enquanto o
/// velho sai.
struct Path {
    kind: u32,
    os: u32,
    pad: usize,
    comp: &'static [f32; DRIVE_STEPS],
    /// Compensação aplicada no fim do último passo (início da rampa do próximo).
    gain: f32,
    ch: [Chan; 2],
}

/// Configuração efetiva: o bitcrusher ignora a sobreamostragem (o aliasing é o efeito).
fn effective(k: u32, os: u32) -> (u32, u32) {
    (k, if k == kind::CRUSH { 1 } else { os })
}

impl Path {
    fn new(pre: FirstOrder, post: FirstOrder, seed: u32) -> Self {
        Self {
            kind: u32::MAX,
            os: 1,
            pad: LATENCY,
            comp: &comp_tables()[0],
            gain: 1.0,
            ch: [Chan::new(pre, post, seed), Chan::new(pre, post, seed.wrapping_mul(747_796_405).wrapping_add(1))],
        }
    }

    fn configure(&mut self, (k, os): (u32, u32)) {
        self.kind = k;
        self.os = os;
        self.pad = LATENCY
            - match os {
                1 => 0,
                2 => 2 * M1 + 1,
                _ => LATENCY,
            };
        self.comp = &comp_tables()[k as usize];
        for c in &mut self.ch {
            c.clear();
        }
    }

    fn config(&self) -> (u32, u32) {
        (self.kind, self.os)
    }

    fn comp_at(&self, db: f32) -> f32 {
        let x = db.clamp(0.0, (DRIVE_STEPS - 1) as f32);
        let i = (x as usize).min(DRIVE_STEPS - 2);
        let f = x - i as f32;
        self.comp[i] + (self.comp[i + 1] - self.comp[i]) * f
    }

    fn run(&mut self, ch: usize, c: &Coeffs, ctl: &Ctl, v: &[f32], out: &mut [f32]) {
        let (os, pad) = (self.os, self.pad);
        let s = &mut self.ch[ch];
        match self.kind {
            kind::SOFT => s.shape(c, os, pad, v, out, tanh),
            kind::VALVE => {
                let rest = valve_raw(VALVE_BIAS);
                s.shape(c, os, pad, v, out, move |x| valve_raw(x + VALVE_BIAS) - rest)
            }
            kind::TAPE => s.tape(c, ctl, os, pad, v, out),
            kind::HARD => s.shape(c, os, pad, v, out, |x| x.clamp(-1.0, 1.0)),
            kind::FOLD => s.shape(c, os, pad, v, out, fold),
            _ => s.crush(ctl, pad, v, out),
        }
    }
}

pub struct Distortion {
    rate: f32,
    coef: Coeffs,
    /// dB.
    drive: Smoothed,
    /// log2(Hz).
    tone: Smoothed,
    mix: Smoothed,
    /// dB.
    output: Smoothed,
    bits: Smoothed,
    downsample: Smoothed,
    kind: u32,
    os: u32,
    dither: bool,
    paths: [Path; 2],
    active: usize,
    fading: bool,
    /// Progresso da transição, 0..1.
    fade: f32,
    dry: [Ring; 2],
    /// Bloqueio de DC por canal: (entrada anterior, saída anterior).
    dc: [(f32, f32); 2],
    dc_r: f32,
    tone_f: [Svf; 2],
    /// Valores no fim do último passo, de onde partem as rampas.
    gain: f32,
    mix_now: f32,
    out_now: f32,
    tape_ms: f32,
    /// Ainda não processou nada: parâmetros chegam sem rampa e sem transição (carregar um projeto
    /// não pode soar como alguém girando os botões).
    fresh: bool,
}

impl Distortion {
    pub fn new(rate: f64) -> Self {
        let rate = rate as f32;
        let pre = FirstOrder::shelf(TAPE_EMPHASIS_HZ, TAPE_EMPHASIS, rate, false);
        let post = FirstOrder::shelf(TAPE_EMPHASIS_HZ, TAPE_EMPHASIS, rate, true);
        let pole = |secs: f32| 1.0 - (-1.0 / (secs * rate)).exp();
        let mut d = Self {
            rate,
            coef: Coeffs::new(),
            drive: Smoothed::new(12.0),
            tone: Smoothed::new(8000f32.log2()),
            mix: Smoothed::new(1.0),
            output: Smoothed::new(0.0),
            bits: Smoothed::new(8.0),
            downsample: Smoothed::new(1.0),
            kind: kind::SOFT,
            os: 2,
            dither: false,
            paths: [Path::new(pre, post, 0x1234_5678), Path::new(pre, post, 0x8765_4321)],
            active: 0,
            fading: false,
            fade: 0.0,
            dry: [Ring::new(LATENCY + 1), Ring::new(LATENCY + 1)],
            dc: [(0.0, 0.0); 2],
            dc_r: 1.0 - 2.0 * PI * DC_HZ / rate,
            tone_f: [Svf::default(); 2],
            gain: 1.0,
            mix_now: 1.0,
            out_now: 1.0,
            tape_ms: pole(TAPE_SQUASH_TAU),
            fresh: true,
        };
        d.paths[0].configure(effective(d.kind, d.os));
        d.snap();
        d
    }

    /// Pula todos os botões para o alvo.
    fn snap(&mut self) {
        for s in [&mut self.drive, &mut self.tone, &mut self.mix, &mut self.output, &mut self.bits, &mut self.downsample] {
            s.snap();
        }
        self.gain = db_to_gain(self.drive.value);
        self.mix_now = self.mix.value;
        self.out_now = db_to_gain(self.output.value);
        for p in &mut self.paths {
            p.gain = p.comp_at(self.drive.value);
        }
    }

    /// Tipo ou sobreamostragem mudou: começa a transição para o caminho novo (ou, no meio de uma,
    /// espera ela acabar; vale o último pedido).
    fn retarget(&mut self) {
        let want = effective(self.kind, self.os);
        if self.fresh {
            if self.paths[self.active].config() != want {
                self.paths[self.active].configure(want);
                self.paths[self.active].gain = self.paths[self.active].comp_at(self.drive.value);
            }
            return;
        }
        if self.fading || self.paths[self.active].config() == want {
            return;
        }
        let idle = &mut self.paths[1 - self.active];
        idle.configure(want);
        idle.gain = idle.comp_at(self.drive.value);
        self.fading = true;
        self.fade = 0.0;
    }

    fn chunk(&mut self, left: &mut [f32], right: &mut [f32]) {
        let len = left.len();
        let inv = 1.0 / len as f32;
        let rate = self.rate;
        let a = smoothing(TAU, len, rate);

        let drive_db = self.drive.step(a);
        let g1 = db_to_gain(drive_db);
        let (g0, dg) = (self.gain, (g1 - self.gain) * inv);
        self.gain = g1;
        let mix1 = self.mix.step(a);
        let (m0, dm) = (self.mix_now, (mix1 - self.mix_now) * inv);
        self.mix_now = mix1;
        let out1 = db_to_gain(self.output.step(a));
        let (o0, dout) = (self.out_now, (out1 - self.out_now) * inv);
        self.out_now = out1;

        let tone = self.tone.step(a);
        let open = ((tone - OPEN_FROM) / (OPEN_TO - OPEN_FROM)).clamp(0.0, 1.0);
        if open < 1.0 {
            let g = Svf::g(tone.exp2().min(0.45 * rate), rate);
            for f in &mut self.tone_f {
                f.set(g, SQRT_2);
            }
        }

        let tape_hz = (TAPE_TOP_HZ * (-drive_db / TAPE_DB_PER_OCT).exp2()).min(0.45 * rate);
        let ctl = Ctl {
            tape_lp: 1.0 - (-2.0 * PI * tape_hz / rate).exp(),
            tape_ms: self.tape_ms,
            crush_inc: 1.0 / self.downsample.step(a),
            crush_step: 2.0 / self.bits.step(a).exp2(),
            dither: self.dither,
        };

        let (act, idle) = (self.active, 1 - self.active);
        let ca0 = self.paths[act].gain;
        let ca1 = self.paths[act].comp_at(drive_db);
        let dca = (ca1 - ca0) * inv;
        let fading = self.fading;
        let (t0, dt, cb0, cb1) = if fading {
            let t1 = (self.fade + len as f32 / (FADE * rate)).min(1.0);
            (self.fade, (t1 - self.fade) * inv, self.paths[idle].gain, self.paths[idle].comp_at(drive_db))
        } else {
            (0.0, 0.0, 0.0, 0.0)
        };
        let dcb = (cb1 - cb0) * inv;
        let dc_r = self.dc_r;

        for ch in 0..2 {
            let buf: &mut [f32] = if ch == 0 { &mut *left } else { &mut *right };
            let mut dry = [0.0f32; CHUNK];
            let mut v = [0.0f32; CHUNK];
            let ring = &mut self.dry[ch];
            for (i, ((&x, d), v)) in buf.iter().zip(dry.iter_mut()).zip(v.iter_mut()).enumerate() {
                let x = sane(x);
                ring.push(x);
                *d = ring.get(LATENCY);
                *v = x * (g0 + dg * (i + 1) as f32);
            }

            let mut wet = [0.0f32; CHUNK];
            self.paths[act].run(ch, &self.coef, &ctl, &v[..len], &mut wet[..len]);
            for (i, w) in wet[..len].iter_mut().enumerate() {
                *w *= ca0 + dca * (i + 1) as f32;
            }
            if fading {
                let mut other = [0.0f32; CHUNK];
                self.paths[idle].run(ch, &self.coef, &ctl, &v[..len], &mut other[..len]);
                for (i, (w, &o)) in wet[..len].iter_mut().zip(&other[..len]).enumerate() {
                    let k = (i + 1) as f32;
                    let o = o * (cb0 + dcb * k);
                    *w += (o - *w) * (t0 + dt * k);
                }
            }

            let (x1, y1) = &mut self.dc[ch];
            let tf = &mut self.tone_f[ch];
            for (i, ((y, &w), &d)) in buf.iter_mut().zip(&wet[..len]).zip(&dry[..len]).enumerate() {
                let k = (i + 1) as f32;
                let hp = w - *x1 + dc_r * *y1;
                *x1 = w;
                *y1 = hp;
                let w = if open < 1.0 {
                    let (lp, _) = tf.tick(hp, FilterMode::LowPass);
                    lp + (hp - lp) * open
                } else {
                    hp
                };
                *y = (d + (w - d) * (m0 + dm * k)) * (o0 + dout * k);
            }
            if open >= 1.0 {
                tf.reset();
            }
        }

        self.paths[act].gain = ca1;
        if fading {
            self.paths[idle].gain = cb1;
            self.fade = t0 + dt * len as f32;
            if self.fade >= 1.0 {
                self.active = idle;
                self.fading = false;
                self.fade = 0.0;
                self.retarget();
            }
        }
    }

    fn flush(&mut self) {
        for (x1, y1) in &mut self.dc {
            if y1.abs() < 1e-15 {
                *y1 = 0.0;
            }
            if x1.abs() < 1e-15 {
                *x1 = 0.0;
            }
        }
        for f in &mut self.tone_f {
            f.flush();
        }
        for p in &mut self.paths {
            for c in &mut p.ch {
                c.flush();
            }
        }
    }

    fn finite(&self) -> bool {
        self.dc.iter().all(|(x, y)| x.is_finite() && y.is_finite())
            && self.tone_f.iter().all(Svf::is_finite)
            && self.paths.iter().all(|p| p.ch.iter().all(Chan::finite))
    }

    #[cfg(test)]
    fn comp_now(&self) -> f32 {
        self.paths[self.active].gain
    }
}

impl Effect for Distortion {
    fn set_param(&mut self, id: u32, value: f32) {
        if !value.is_finite() {
            return;
        }
        match id {
            P::DRIVE => self.drive.set(value.clamp(0.0, 48.0)),
            P::TYPE => {
                self.kind = value.round().clamp(0.0, kind::CRUSH as f32) as u32;
                self.retarget();
            }
            P::TONE => self.tone.set(value.clamp(500.0, 20_000.0).log2()),
            P::MIX => self.mix.set(value.clamp(0.0, 1.0)),
            P::OUTPUT => self.output.set(value.clamp(-24.0, 12.0)),
            P::BITS => self.bits.set(value.clamp(1.0, 16.0)),
            P::DOWNSAMPLE => self.downsample.set(value.clamp(1.0, 32.0)),
            P::OVERSAMPLE => {
                self.os = 1 << (value.round().clamp(0.0, 2.0) as u32);
                self.retarget();
            }
            DITHER => self.dither = value >= 0.5,
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
        self.flush();
        if !self.finite() {
            // não deveria acontecer (a entrada é saneada), mas um estado podre calaria a faixa
            // para sempre
            self.reset();
        }
    }

    fn reset(&mut self) {
        for p in &mut self.paths {
            for c in &mut p.ch {
                c.clear();
            }
        }
        self.fading = false;
        self.fade = 0.0;
        let want = effective(self.kind, self.os);
        if self.paths[self.active].config() != want {
            self.paths[self.active].configure(want);
        }
        for r in &mut self.dry {
            r.clear();
        }
        self.dc = [(0.0, 0.0); 2];
        for f in &mut self.tone_f {
            f.reset();
        }
        self.snap();
    }

    fn latency(&self) -> usize {
        LATENCY
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::f32::consts::TAU as TWO_PI;

    const RATE: f32 = 48_000.0;

    fn make(params: &[(u32, f32)]) -> Distortion {
        let mut d = Distortion::new(RATE as f64);
        // tom aberto: os testes medem a curva, não o passa-baixa
        d.set_param(P::TONE, 20_000.0);
        for &(id, v) in params {
            d.set_param(id, v);
        }
        d
    }

    fn sine(freq: f32, amp: f32, n: usize) -> Vec<f32> {
        (0..n).map(|i| amp * (i as f32 * freq / RATE * TWO_PI).sin()).collect()
    }

    /// Processa em blocos de 128 (como o worklet) e devolve o canal esquerdo.
    fn run(d: &mut Distortion, input: &[f32]) -> Vec<f32> {
        let mut out = Vec::with_capacity(input.len());
        for block in input.chunks(128) {
            let mut l = block.to_vec();
            let mut r = block.to_vec();
            d.process(&mut l, &mut r);
            out.extend_from_slice(&l);
        }
        out
    }

    fn rms(x: &[f32]) -> f32 {
        (x.iter().map(|v| v * v).sum::<f32>() / x.len() as f32).sqrt()
    }

    #[test]
    fn tanh_de_pade_confere() {
        for i in -8000..=8000 {
            let x = i as f32 / 1000.0;
            assert!((tanh(x) - x.tanh()).abs() < 2.5e-4, "x = {x}");
            assert!(tanh(x).abs() <= 1.0);
        }
        assert_eq!(tanh(1e30), 1.0);
        assert_eq!(tanh(-1e30), -1.0);
    }

    #[test]
    fn dobra_e_quase_identidade_perto_do_zero_e_dobra_depois() {
        for i in -300..=300 {
            let x = i as f32 / 1000.0;
            // sen x = x − x³/6 + …
            assert!((fold(x) - x).abs() <= x.abs().powi(3) / 6.0 + 1e-5, "x = {x}");
        }
        assert!((fold(std::f32::consts::FRAC_PI_2) - 1.0).abs() < 1e-5);
        assert!(fold(std::f32::consts::PI).abs() < 1e-5);
        let mut last = fold(-200.0);
        for i in -199_999..=200_000 {
            let y = fold(i as f32 / 1000.0);
            assert!(y.abs() <= 1.0 + 1e-5);
            assert!((y - last).abs() < 0.0011, "salto em {}", i as f32 / 1000.0);
            last = y;
        }
    }

    #[test]
    fn meias_bandas_tem_ganho_unitario_e_rejeitam() {
        let c = Coeffs::new();
        let dc1: f32 = c.dn1.iter().sum::<f32>() * 2.0 + 0.5;
        let dc2: f32 = c.dn2.iter().sum::<f32>() * 2.0 + 0.5;
        assert!((dc1 - 1.0).abs() < 1e-6 && (dc2 - 1.0).abs() < 1e-6);
        // resposta do 1º estágio na banda rejeitada (≥ 0,3·fs), pelo FIR completo
        let mut h = vec![0.0f64; 4 * M1 + 3];
        for (j, &v) in c.dn1.iter().enumerate() {
            h[2 * j] = v as f64;
            h[4 * M1 + 2 - 2 * j] = v as f64;
        }
        h[2 * M1 + 1] = 0.5;
        let mag = |f: f64| {
            let (mut re, mut im) = (0.0, 0.0);
            for (i, v) in h.iter().enumerate() {
                re += v * (2.0 * PI64 * f * i as f64).cos();
                im += v * (2.0 * PI64 * f * i as f64).sin();
            }
            (re * re + im * im).sqrt()
        };
        for k in 0..=100 {
            let f = 0.3 + 0.2 * k as f64 / 100.0;
            assert!(20.0 * mag(f).log10() < -80.0, "rejeição fraca em {f}");
        }
        assert!((mag(0.1) - 1.0).abs() < 1e-3);
    }

    #[test]
    fn tabelas_de_compensacao_convergem() {
        // os poucos pontos das tabelas de verdade contra uma integração densa
        for k in 0..6 {
            let dense = comp_table(k, 8192);
            for (db, (&a, &b)) in comp_tables()[k as usize].iter().zip(&dense).enumerate() {
                assert!((a / b - 1.0).abs() < 0.01, "tipo {k}, {db} dB: {a} × {b}");
            }
        }
        // e ficam lisas: o volume não pode pular de um dB de drive para o seguinte
        for t in comp_tables() {
            for w in t.windows(2) {
                assert!((w[1] / w[0]).log10().abs() * 20.0 < 1.5, "{t:?}");
            }
        }
    }

    #[test]
    fn suave_sem_drive_e_quase_transparente() {
        let mut d = make(&[(P::TYPE, 0.0), (P::DRIVE, 0.0)]);
        let x = sine(1000.0, 0.1, 24_000);
        let y = run(&mut d, &x);
        let err: Vec<f32> = (12_000..24_000).map(|i| y[i] - x[i - LATENCY]).collect();
        let rel = rms(&err) / rms(&x[12_000..]);
        assert!(rel < 0.03, "erro relativo {rel}");
    }

    #[test]
    fn latencia_e_a_mesma_em_todos_os_modos() {
        // dura com sinal abaixo do teto é linear: a saída tem que ser a entrada atrasada
        for os in 0..3 {
            let mut d = make(&[(P::TYPE, 3.0), (P::DRIVE, 0.0), (P::OVERSAMPLE, os as f32)]);
            let x = sine(997.0, 0.5, 24_000);
            let y = run(&mut d, &x);
            let err: Vec<f32> = (12_000..24_000).map(|i| y[i] - x[i - LATENCY]).collect();
            assert!(rms(&err) < 0.005, "{}×: erro {}", 1 << os, rms(&err));
            assert_eq!(d.latency(), LATENCY);
        }
    }

    #[test]
    fn dura_limita_a_amplitude() {
        for (os, slack) in [(0.0, 1.05), (2.0, 1.25)] {
            let mut peaks = Vec::new();
            for drive in [24.0, 36.0, 48.0] {
                let mut d = make(&[(P::TYPE, 3.0), (P::DRIVE, drive), (P::OVERSAMPLE, os)]);
                let x = sine(220.0, 0.5, 24_000);
                let y = run(&mut d, &x);
                let peak = y[12_000..].iter().fold(0.0f32, |m, v| m.max(v.abs()));
                // o teto é ±1 antes da compensação; sobreamostrado, a onda cortada volta limitada em
                // banda e ganha o overshoot de Gibbs nas quinas
                assert!(peak <= d.comp_now() * slack, "{os}: pico {peak} com drive {drive}");
                peaks.push(peak / d.comp_now());
            }
            // a 1× mais drive não fura o teto
            assert!(os > 0.0 || peaks[2] <= peaks[0] * 1.02, "{peaks:?}");
        }
    }

    #[test]
    fn bitcrusher_de_1_bit_tem_dois_niveis() {
        let mut levels: Vec<f32> = (0..1000).map(|i| quantize((i as f32 * 0.037).sin() * 0.8, 1.0)).collect();
        levels.sort_by(f32::total_cmp);
        levels.dedup();
        assert_eq!(levels, vec![-0.5, 0.5]);

        let mut d = make(&[(P::TYPE, 5.0), (P::DRIVE, 0.0), (P::BITS, 1.0)]);
        let x = sine(997.0, 0.5, 24_000);
        let y = run(&mut d, &x);
        let a = 0.5 * d.comp_now();
        for &v in &y[12_000..] {
            // o bloqueio de DC inclina o platô um pouco (1,6% em meio ciclo de 1 kHz)
            assert!((v.abs() - a).abs() < 0.03 * a, "{v} fora de ±{a}");
        }
    }

    #[test]
    fn bitcrusher_reduz_a_taxa() {
        let mut d = make(&[(P::TYPE, 5.0), (P::DRIVE, 0.0), (P::BITS, 16.0), (P::DOWNSAMPLE, 8.0)]);
        let x = sine(100.0, 0.5, 4800);
        let y = run(&mut d, &x);
        // blocos de 8 amostras iguais (antes do bloqueio de DC, que é quase nada a 100 Hz)
        let changes = y[2400..].windows(2).filter(|w| (w[1] - w[0]).abs() > 1e-3).count();
        assert!((290..=310).contains(&changes), "{changes} mudanças em 2400 amostras");
    }

    /// Energia fora das harmônicas de uma senoide aguda (em dB relativos às harmônicas): com a
    /// frequência numa raia exata da DFT, as harmônicas caem em múltiplos dela e o aliasing, rebatido
    /// de Nyquist, cai no meio.
    fn alias_db(kind_: f32, os: f32, drive: f32) -> f32 {
        const N: usize = 4800;
        const BIN: usize = 373; // 3730 Hz, primo com 4800
        let mut d = make(&[(P::TYPE, kind_), (P::DRIVE, drive), (P::OVERSAMPLE, os)]);
        let x = sine(BIN as f32 * RATE / N as f32, 0.5, 3 * N);
        let y = run(&mut d, &x);
        let w = &y[2 * N..3 * N];
        let twiddle: Vec<(f64, f64)> = (0..N).map(|m| (2.0 * PI64 * m as f64 / N as f64).sin_cos()).collect();
        let (mut harm, mut other) = (0.0f64, 0.0f64);
        for k in 1..N / 2 {
            let (mut re, mut im) = (0.0f64, 0.0f64);
            for (i, &v) in w.iter().enumerate() {
                let (s, c) = twiddle[k * i % N];
                re += v as f64 * c;
                im += v as f64 * s;
            }
            let e = re * re + im * im;
            // o que rebate entre 20 e 24 kHz é inaudível (e a meia-banda deixa passar de propósito)
            if k % BIN == 0 {
                harm += e
            } else if k < N * 20 / 48 {
                other += e
            }
        }
        (10.0 * (other / harm).log10()) as f32
    }

    #[test]
    fn sobreamostragem_reduz_o_aliasing() {
        // medido: suave/válvula/fita/dura caem de −14..−16 dB a 1× para −32..−39 dB a 4×; a dobra
        // senoidal, de −11/+12 dB para −59/−50 dB
        for (kind_, drive, gain) in [(0.0, 36.0, 15.0), (1.0, 36.0, 15.0), (2.0, 36.0, 15.0), (3.0, 36.0, 15.0), (4.0, 24.0, 40.0), (4.0, 36.0, 50.0)] {
            let a1 = alias_db(kind_, 0.0, drive);
            let a2 = alias_db(kind_, 1.0, drive);
            let a4 = alias_db(kind_, 2.0, drive);
            let msg = format!("tipo {kind_}, drive {drive}: 1× {a1:.1} dB, 2× {a2:.1} dB, 4× {a4:.1} dB");
            assert!(a2 < a1 - 1.0 && a4 <= a2 + 0.5 && a4 < a1 - gain, "{msg}");
        }
    }

    #[test]
    fn drive_nao_pula_o_volume() {
        for kind_ in 0..5 {
            let mut levels = Vec::new();
            for drive in [0.0, 12.0, 24.0, 36.0, 48.0] {
                let mut d = make(&[(P::TYPE, kind_ as f32), (P::DRIVE, drive), (P::OVERSAMPLE, 2.0)]);
                let y = run(&mut d, &sine(220.0, REF, 24_000));
                levels.push(20.0 * rms(&y[12_000..]).log10());
            }
            let (lo, hi) = levels.iter().fold((f32::MAX, f32::MIN), |(lo, hi), &v| (lo.min(v), hi.max(v)));
            assert!(hi - lo < 4.0, "tipo {kind_}: {levels:?}");
        }
    }

    #[test]
    fn mistura_zero_e_o_seco() {
        let mut d = make(&[(P::TYPE, 1.0), (P::DRIVE, 40.0), (P::MIX, 0.0)]);
        let x = sine(440.0, 0.7, 9600);
        let y = run(&mut d, &x);
        for i in LATENCY..x.len() {
            assert_eq!(y[i], x[i - LATENCY]);
        }
    }

    #[test]
    fn silencio_continua_silencio() {
        for kind_ in 0..6 {
            let mut d = make(&[(P::TYPE, kind_ as f32), (P::DRIVE, 48.0), (P::BITS, 1.0)]);
            // som e depois silêncio: nada de DC nem cauda eterna
            let mut x = sine(300.0, 0.5, 4800);
            x.extend(std::iter::repeat_n(0.0, 48_000));
            let y = run(&mut d, &x);
            let tail = y[48_000..].iter().fold(0.0f32, |m, v| m.max(v.abs()));
            assert!(tail < 1e-4, "tipo {kind_}: resto {tail}");
        }
    }

    #[test]
    fn trocas_nao_estalam() {
        let mut d = make(&[(P::DRIVE, 0.0), (P::BITS, 16.0)]);
        let x = sine(100.0, 0.2, 48_000);
        let mut y = run(&mut d, &x[..4800]);
        let mut step = 0;
        for block in x[4800..].chunks(2400) {
            // alterna tipo e sobreamostragem a cada 50 ms
            step += 1;
            d.set_param(P::TYPE, (step % 6) as f32);
            d.set_param(P::OVERSAMPLE, (step % 3) as f32);
            y.extend(run(&mut d, block));
        }
        // uma senoide de 100 Hz e 0,2 anda no máximo 0,0026 por amostra; o valor compensado das
        // curvas perto do linear varia pouco disso
        let worst = y[4800..].windows(2).map(|w| (w[1] - w[0]).abs()).fold(0.0f32, f32::max);
        assert!(worst < 0.006, "salto de {worst}");
    }

    #[test]
    fn drive_e_mistura_andam_sem_degrau() {
        let mut d = make(&[(P::TYPE, 0.0), (P::DRIVE, 0.0)]);
        let x = sine(100.0, 0.2, 9600);
        let mut y = run(&mut d, &x[..4800]);
        d.set_param(P::DRIVE, 30.0);
        d.set_param(P::MIX, 0.3);
        d.set_param(P::OUTPUT, -12.0);
        y.extend(run(&mut d, &x[4800..]));
        let worst = y[4700..6000].windows(2).map(|w| (w[1] - w[0]).abs()).fold(0.0f32, f32::max);
        assert!(worst < 0.01, "salto de {worst}");
    }

    #[test]
    fn nenhum_nan_com_extremos() {
        let mut d = make(&[]);
        let mut rng = Rng::new(7);
        let ids = [P::DRIVE, P::TYPE, P::TONE, P::MIX, P::OUTPUT, P::BITS, P::DOWNSAMPLE, P::OVERSAMPLE, DITHER];
        let extremes = [-1e9, -1.0, 0.0, 0.5, 1.0, 5.0, 16.0, 48.0, 20_000.0, 1e9, f32::NAN, f32::INFINITY];
        for round in 0..400 {
            let id = ids[round % ids.len()];
            d.set_param(id, extremes[(rng.next_u32() as usize) % extremes.len()]);
            let mut l: Vec<f32> = (0..128)
                .map(|i| match (round + i) % 7 {
                    0 => 1e5,
                    1 => -1e5,
                    2 => f32::NAN,
                    3 => 1e-39,
                    _ => rng.bipolar() * 4.0,
                })
                .collect();
            let mut r = l.clone();
            d.process(&mut l, &mut r);
            assert!(l.iter().chain(&r).all(|v| v.is_finite() && v.abs() < 1e7), "rodada {round}");
        }
        d.reset();
        let mut l = vec![0.0; 128];
        let mut r = vec![0.0; 128];
        d.process(&mut l, &mut r);
        assert!(l.iter().all(|v| v.abs() < 1e-6));
    }

    #[test]
    fn blocos_de_qualquer_tamanho() {
        let x = sine(700.0, 0.6, 4000);
        let mut a = make(&[(P::TYPE, 2.0), (P::DRIVE, 20.0)]);
        let ya = run(&mut a, &x);
        let mut b = make(&[(P::TYPE, 2.0), (P::DRIVE, 20.0)]);
        let mut yb = Vec::new();
        let mut i = 0;
        for n in [1usize, 7, 16, 33, 128, 500].iter().cycle() {
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
        // com parâmetros parados, o resultado não depende do tamanho do bloco
        for (p, q) in ya.iter().zip(&yb) {
            assert!((p - q).abs() < 1e-5);
        }
    }
}
