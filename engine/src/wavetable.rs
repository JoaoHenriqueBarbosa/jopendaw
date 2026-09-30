//! Sintetizador de wavetable (faixa do tipo 6).
//!
//! Dois osciladores leem tabelas de um ciclo. Cada um escolhe uma de 3 séries de 8 tabelas e uma
//! posição contínua (0..1) dentro dela: a saída é a mistura linear das duas tabelas vizinhas da
//! posição, então girar o botão (ou o LFO, ou o envelope do filtro) percorre o timbre sem degraus.
//!
//! # Séries
//!
//! ```text
//! Clássica   senoide → triângulo → serra → quadrada → pulsos cada vez mais estreitos (50 → 6%).
//!            O trecho dos pulsos, com as fases alinhadas, é um PWM: varrer a posição estreita o pulso.
//! Vozes      vogais A, E, I, O, U (fonte glotal 1/h filtrada por três formantes), nasal, coral e
//!            rosnado. Os formantes ficam em posições fixas do espectro (calculadas para uma
//!            fundamental de 150 Hz): sobem junto com a nota, como em qualquer wavetable.
//! Digital    ímpares, vazada (pares fracos), ressonante (pico no 7º harmônico), Fibonacci,
//!            primos e sino (harmônicos altos e esparsos, o mais perto de "metálico" que um
//!            ciclo periódico permite), granulada (fases quadráticas) e vidro.
//! ```
//!
//! # Anti-aliasing
//!
//! As tabelas nascem de somas de harmônicos (nada de forma de onda desenhada e depois filtrada), o
//! que dá tabelas de banda limitada por construção. Cada tabela existe em 9 versões (mip-map por
//! oitava): a versão `j` só tem os `256 >> j` primeiros harmônicos. A voz escolhe a maior versão
//! cujo último harmônico ainda fica abaixo de 0,45 da taxa na frequência tocada, por cópia do
//! uníssono e por bloco (o vibrato e o glide trocam de versão sozinhos). A leitura é linear com 2048
//! pontos por ciclo: com no máximo 256 harmônicos o erro de interpolação fica abaixo de −34 dB do
//! harmônico mais alto, que já é fraco.
//!
//! As tabelas são iguais para todas as instâncias: ficam numa `OnceLock` e cada instrumento guarda
//! um `Arc`. A primeira criação as gera (alguns milissegundos); as seguintes só clonam o `Arc`.
//!
//! O resto é o desenho do sintetizador subtrativo: uníssono de até 7 cópias, sub, ruído, SVF com
//! envelope, envelope de amplitude, LFO e glide, em blocos de controle de 16 quadros.

use std::f64::consts::{PI, TAU};
use std::sync::atomic::{AtomicU32, Ordering};
use std::sync::{Arc, OnceLock};

use crate::dsp::{Adsr, FilterMode, Rng, Smoothed, Stage, Svf, sin_turns, smoothing};
use crate::instrument::{Instrument, pitch_hz, wavetable_param as P};
use crate::pan_gains;
use crate::synth::{Ramp, Spec, cont, disc, lfo_shape, unison_position, wrap};

/// Pontos por ciclo (o último de cada tabela repete o primeiro, para a interpolação não precisar
/// de módulo).
pub const TABLE_LEN: usize = 2048;
const STRIDE: usize = TABLE_LEN + 1;
/// Harmônicos da versão mais rica de cada tabela.
pub const MAX_HARMONICS: usize = 256;
/// Versões de banda limitada: 256, 128, ..., 1 harmônico.
pub const LEVELS: usize = 9;
pub const SERIES: usize = 3;
pub const TABLES: usize = 8;

const MAX_VOICES: usize = 16;
const SPARE_VOICES: usize = 4;
const MAX_UNISON: usize = 7;
const CONTROL: usize = 16;
const PARAMS: usize = P::COUNT as usize;

/// Ganho por voz: uma nota fica perto de −10 dBFS e um acorde ainda cabe sem estourar.
const VOICE_GAIN: f32 = 0.5;
const STEAL_SECS: f32 = 0.005;
/// Maior incremento de fase por quadro (acima disso só sobraria aliasing).
const MAX_DT: f32 = 0.45;
/// Fração da taxa que o último harmônico da tabela pode alcançar.
const BAND_LIMIT: f32 = 0.45;
const PARAM_TAU: f32 = 0.01;
const LFO_TAU: f32 = 0.0015;
/// Q máximo do filtro (a ressonância de wavetable é mais contida que a do subtrativo: o espectro
/// das tabelas já é rico e o pico do filtro empilharia em cima).
const MAX_Q: f32 = 16.0;
const RES_LIMIT_LEVEL: f32 = 1.5;
const RES_LIMIT_DEPTH: f32 = 0.5;
const RES_LIMIT_TAU: f32 = 0.03;

/// Faixa, padrão e se o valor é inteiro, na ordem dos ids. Espelho de `wavetableParams` em
/// `app/lib/daw/instruments.dart` (um teste confere os dois).
const SPECS: [Spec; PARAMS] = [
    disc(0.0, 2.0, 0.0),         // OSC1_SERIES
    cont(0.0, 1.0, 0.3),         // OSC1_POS
    cont(0.0, 1.0, 0.8),         // OSC1_LEVEL
    disc(-24.0, 24.0, 0.0),      // OSC1_SEMI
    cont(-100.0, 100.0, 0.0),    // OSC1_DETUNE
    disc(0.0, 2.0, 0.0),         // OSC2_SERIES
    cont(0.0, 1.0, 0.5),         // OSC2_POS
    cont(0.0, 1.0, 0.5),         // OSC2_LEVEL
    disc(-24.0, 24.0, 0.0),      // OSC2_SEMI
    cont(-100.0, 100.0, 7.0),    // OSC2_DETUNE
    cont(0.0, 1.0, 0.0),         // SUB_LEVEL
    cont(0.0, 1.0, 0.0),         // NOISE_LEVEL
    disc(1.0, 7.0, 1.0),         // UNISON
    cont(0.0, 100.0, 20.0),      // UNISON_DETUNE
    cont(0.0, 1.0, 0.5),         // UNISON_SPREAD
    disc(0.0, 2.0, 0.0),         // FILTER_TYPE
    cont(20.0, 20000.0, 8000.0), // CUTOFF
    cont(0.0, 1.0, 0.1),         // RESONANCE
    cont(-1.0, 1.0, 0.0),        // FILTER_ENV
    cont(0.0, 1.0, 0.5),         // KEYTRACK
    cont(0.0005, 10.0, 0.005),   // AMP_ATTACK
    cont(0.001, 10.0, 0.3),      // AMP_DECAY
    cont(0.0, 1.0, 0.8),         // AMP_SUSTAIN
    cont(0.001, 10.0, 0.3),      // AMP_RELEASE
    cont(0.0005, 10.0, 0.005),   // FLT_ATTACK
    cont(0.001, 10.0, 0.5),      // FLT_DECAY
    cont(0.0, 1.0, 0.3),         // FLT_SUSTAIN
    cont(0.001, 10.0, 0.4),      // FLT_RELEASE
    disc(0.0, 4.0, 0.0),         // LFO_WAVE
    cont(0.05, 30.0, 4.0),       // LFO_RATE
    cont(0.0, 12.0, 0.0),        // LFO_PITCH
    cont(0.0, 4.0, 0.0),         // LFO_CUTOFF
    cont(0.0, 1.0, 0.0),         // LFO_AMP
    cont(-1.0, 1.0, 0.0),        // LFO_POS
    cont(0.0, 2.0, 0.0),         // GLIDE
    disc(1.0, 16.0, 8.0),        // VOICES
    cont(0.0, 1.0, 0.7),         // VELOCITY
    cont(0.0, 1.5, 0.7),         // LEVEL
    cont(-1.0, 1.0, 0.0),        // ENV_POS
];

/// Semente diferente por instância.
static SEED: AtomicU32 = AtomicU32::new(0x51ED_270B);

// ------------------------------------------------------------------------------------ tabelas

/// Coeficientes (cosseno, seno) do harmônico `h` (1..=256) de uma tabela: `a·cos(2πht) + b·sin(2πht)`.
/// A mesma definição está em `wavetable_shape.dart` (o gráfico do painel) — mudou aqui, mude lá.
pub fn harmonic(series: usize, table: usize, h: usize) -> (f64, f64) {
    let hf = h as f64;
    let odd = h % 2 == 1;
    let gauss = |x: f64, c: f64, w: f64| (-0.5 * ((x - c) / w) * ((x - c) / w)).exp();
    let sine = |b: f64| (0.0, b);
    match (series, table) {
        // clássica
        (0, 0) => sine(if h == 1 { 1.0 } else { 0.0 }),
        (0, 1) => sine(if odd { 8.0 / (PI * PI) * if (h / 2).is_multiple_of(2) { 1.0 } else { -1.0 } / (hf * hf) } else { 0.0 }),
        (0, 2) => sine(1.0 / hf),
        (0, t) => {
            // pulso de largura d que começa na fase 0: a = sen(2πhd)/(πh), b = (1 − cos(2πhd))/(πh)
            let d = [0.5, 0.35, 0.22, 0.12, 0.06][t - 3];
            ((TAU * hf * d).sin() / (PI * hf), (1.0 - (TAU * hf * d).cos()) / (PI * hf))
        }
        // vozes: fonte 1/h e três formantes (centro Hz, largura Hz, ganho) numa fundamental de 150 Hz
        (1, 7) => sine(hf.powf(-0.55) * (0.6 + 0.4 * (0.9 * hf).sin().abs())),
        (1, t) => {
            const VOWELS: [[(f64, f64, f64); 3]; 7] = [
                [(800.0, 120.0, 1.0), (1150.0, 100.0, 0.8), (2800.0, 220.0, 0.3)], // A
                [(400.0, 90.0, 1.0), (1700.0, 140.0, 0.7), (2600.0, 220.0, 0.4)],  // E
                [(300.0, 70.0, 1.0), (2300.0, 160.0, 0.6), (3100.0, 240.0, 0.4)],  // I
                [(450.0, 90.0, 1.0), (850.0, 100.0, 0.7), (2800.0, 220.0, 0.25)],  // O
                [(320.0, 70.0, 1.0), (750.0, 90.0, 0.55), (2500.0, 220.0, 0.2)],   // U
                [(280.0, 70.0, 1.0), (1100.0, 60.0, 0.6), (2300.0, 120.0, 0.6)],   // nasal
                [(500.0, 300.0, 1.0), (1500.0, 400.0, 0.6), (2500.0, 500.0, 0.4)], // coral
            ];
            let f = 150.0 * hf;
            let env = 0.02 + VOWELS[t].iter().map(|&(c, w, g)| g * gauss(f, c, w)).sum::<f64>();
            sine(env / hf)
        }
        // digital e metálica
        (2, 0) => sine(if odd { hf.powf(-0.5) } else { 0.0 }),
        (2, 1) => sine(if h <= 24 { (if odd { 1.0 } else { 0.35 }) * hf.powf(-0.6) } else { 0.0 }),
        (2, 2) => sine((1.0 + 6.0 * gauss(hf, 7.0, 1.4)) / hf),
        (2, 3) => sine(if is_fibonacci(h) { hf.powf(-0.5) } else { 0.0 }),
        (2, 4) => sine(if is_prime(h) { hf.powf(-0.55) } else { 0.0 }),
        (2, 5) => sine(if matches!(h, 2 | 3 | 4 | 5 | 7 | 9 | 12 | 16 | 21 | 27 | 35 | 44) { hf.powf(-0.5) } else { 0.0 }),
        (2, 6) => {
            // fase quadrática: espalha a energia no ciclo (som "granulado", sem pico de crista)
            let amp = hf.powf(-0.7);
            let ph = (0.7 * hf * hf) % TAU;
            (amp * ph.cos(), amp * ph.sin())
        }
        _ => sine((if h == 1 { 1.0 } else { 0.0 }) + if h >= 2 { 0.8 * gauss(hf, 13.0, 2.5) } else { 0.0 }),
    }
}

fn is_prime(n: usize) -> bool {
    n >= 2 && (2..).take_while(|d| d * d <= n).all(|d| !n.is_multiple_of(d))
}

fn is_fibonacci(n: usize) -> bool {
    let (mut a, mut b) = (1usize, 2usize);
    while b < n {
        (a, b) = (b, a + b);
    }
    n == 1 || b == n || a == n
}

/// Todas as tabelas: `[série][tabela][versão][STRIDE]`, planas.
pub struct Tables {
    data: Vec<f32>,
}

impl Tables {
    fn build() -> Self {
        // seno de um ciclo em 2048 pontos: `cos(2π·h·n/N)` = `SIN[(h·n + N/4) mod N]`, sem chamar
        // funções transcendentes 12 milhões de vezes
        let sin: Vec<f32> = (0..TABLE_LEN).map(|n| (TAU * n as f64 / TABLE_LEN as f64).sin() as f32).collect();
        let mut data = vec![0.0f32; SERIES * TABLES * LEVELS * STRIDE];
        let mut acc = vec![0.0f32; TABLE_LEN];
        for series in 0..SERIES {
            for table in 0..TABLES {
                acc.fill(0.0);
                // da versão mais pobre (1 harmônico) à mais rica: cada harmônico entra uma vez só
                let mut from = 1;
                for level in (0..LEVELS).rev() {
                    let to = MAX_HARMONICS >> level;
                    for h in from..=to {
                        let (a, b) = harmonic(series, table, h);
                        let (a, b) = (a as f32, b as f32);
                        if a == 0.0 && b == 0.0 {
                            continue;
                        }
                        let mut idx = 0usize;
                        for v in acc.iter_mut() {
                            *v += a * sin[(idx + TABLE_LEN / 4) & (TABLE_LEN - 1)] + b * sin[idx];
                            idx = (idx + h) & (TABLE_LEN - 1);
                        }
                    }
                    from = to + 1;
                    let base = ((series * TABLES + table) * LEVELS + level) * STRIDE;
                    data[base..base + TABLE_LEN].copy_from_slice(&acc);
                    data[base + TABLE_LEN] = acc[0];
                }
                // volume percebido parecido entre as tabelas: RMS de 0,5 (senoide a −6 dBFS de
                // pico), a menos que o pico passe de 1,6 (pulso estreito). O mesmo ganho vale para
                // todas as versões da tabela, senão o volume mudaria com a altura da nota.
                let full = ((series * TABLES + table) * LEVELS) * STRIDE;
                let t = &data[full..full + TABLE_LEN];
                let rms = (t.iter().map(|v| v * v).sum::<f32>() / TABLE_LEN as f32).sqrt().max(1e-9);
                let peak = t.iter().fold(0.0f32, |m, v| m.max(v.abs())).max(1e-9);
                let gain = (0.5 / rms).min(1.6 / peak);
                for v in &mut data[full..full + LEVELS * STRIDE] {
                    *v *= gain;
                }
            }
        }
        Self { data }
    }

    /// As tabelas compartilhadas (geradas na primeira chamada).
    pub fn shared() -> Arc<Tables> {
        static CELL: OnceLock<Arc<Tables>> = OnceLock::new();
        CELL.get_or_init(|| Arc::new(Tables::build())).clone()
    }

    /// Um ciclo (com o ponto de guarda) de uma tabela numa versão.
    #[inline]
    pub fn table(&self, series: usize, table: usize, level: usize) -> &[f32] {
        let base = ((series * TABLES + table) * LEVELS + level) * STRIDE;
        &self.data[base..base + STRIDE]
    }
}

/// Versão da tabela para uma nota de `dt` ciclos por quadro: a mais rica cujo último harmônico
/// fica abaixo de `BAND_LIMIT` da taxa.
#[inline]
pub fn mip_level(dt: f32) -> usize {
    let allowed = BAND_LIMIT / dt.max(1e-6);
    let mut level = 0;
    while level < LEVELS - 1 && (MAX_HARMONICS >> level) as f32 > allowed {
        level += 1;
    }
    level
}

/// Lê a tabela na fase `ph` (0..1) com interpolação linear.
#[inline(always)]
fn read(tab: &[f32], ph: f32) -> f32 {
    let x = ph * TABLE_LEN as f32;
    let i = (x as usize).min(TABLE_LEN - 1);
    let f = x - i as f32;
    tab[i] + (tab[i + 1] - tab[i]) * f
}

// ---------------------------------------------------------------------------------- sintetizador

/// O que todas as vozes usam num bloco de controle.
struct Block {
    rate: f32,
    series: [usize; 2],
    /// Posição base (0..1) de cada oscilador, já suavizada.
    pos: [f32; 2],
    osc1: Ramp,
    osc2: Ramp,
    sub: Ramp,
    noise: Ramp,
    gain: Ramp,
    unison: usize,
    uni_ratio: [f32; MAX_UNISON],
    pan_l: [f32; MAX_UNISON],
    pan_r: [f32; MAX_UNISON],
    /// Razão de afinação (semitons + cents) de cada oscilador.
    ratio: [f32; 2],
    mode: FilterMode,
    cutoff: f32,
    max_cutoff: f32,
    k: f32,
    filter_env: f32,
    keytrack: f32,
    lfo: f32,
    lfo_pitch: f32,
    lfo_cutoff: f32,
    lfo_pos: f32,
    env_pos: f32,
    smooth: f32,
    glide: f32,
    res_release: f32,
    fade_step: f32,
}

#[derive(Clone, Copy, Debug, Default)]
struct Copy1 {
    ph: [f32; 2],
    dt: [f32; 2],
}

struct Voice {
    pitch: u8,
    gate: bool,
    age: u64,
    vel_gain: f32,
    vel_target: f32,
    env_depth: f32,
    amp: Adsr,
    flt: Adsr,
    cur: f32,
    target: f32,
    copies: [Copy1; MAX_UNISON],
    sub: f32,
    fl: Svf,
    fr: Svf,
    res_l: f32,
    res_r: f32,
    dying: bool,
    fade: f32,
}

impl Voice {
    fn new(rate: f64) -> Self {
        Self {
            pitch: 0,
            gate: false,
            age: 0,
            vel_gain: 1.0,
            vel_target: 1.0,
            env_depth: 1.0,
            amp: Adsr::new(rate),
            flt: Adsr::new(rate),
            cur: 60.0,
            target: 60.0,
            copies: [Copy1::default(); MAX_UNISON],
            sub: 0.0,
            fl: Svf::default(),
            fr: Svf::default(),
            res_l: 0.0,
            res_r: 0.0,
            dying: false,
            fade: 1.0,
        }
    }

    fn busy(&self) -> bool {
        self.amp.active() && !self.dying
    }

    /// Tecla presa com sustentação zero e o envelope já em zero: só sairiam zeros.
    fn silent_hold(&self) -> bool {
        self.amp.stage() == Stage::Sustain && self.amp.sustain == 0.0 && self.amp.value() == 0.0
    }

    fn kill(&mut self) {
        self.amp.reset();
        self.flt.reset();
        self.fl.reset();
        self.fr.reset();
        self.res_l = 0.0;
        self.res_r = 0.0;
        self.gate = false;
        self.dying = false;
        self.fade = 1.0;
    }

    fn trigger(&mut self, pitch: u8, velocity: f32, sensitivity: f32, age: u64) {
        self.pitch = pitch;
        self.gate = true;
        self.age = age;
        // quadrática: meia velocidade com sensibilidade total dá −12 dB
        self.vel_target = 1.0 - sensitivity + sensitivity * velocity * velocity;
        self.env_depth = 1.0 - 0.5 * sensitivity * (1.0 - velocity);
        self.amp.gate_on();
        self.flt.gate_on();
    }

    fn release(&mut self) {
        self.gate = false;
        self.amp.gate_off();
        self.flt.gate_off();
    }

    fn slide(&mut self, pitch: u8, glide: bool) {
        self.pitch = pitch;
        self.target = pitch as f32;
        if !glide {
            self.cur = self.target;
        }
    }

    fn render(&mut self, b: &Block, tables: &Tables, rng: &mut Rng, out_l: &mut [f32], out_r: &mut [f32]) {
        let d = self.target - self.cur;
        self.cur = if d.abs() < 1e-3 { self.target } else { self.cur + d * b.glide };

        let dt = pitch_hz(self.cur + b.lfo * b.lfo_pitch) / b.rate;
        let dt_sub = (dt * 0.5).min(MAX_DT);
        let uni = b.unison;

        // posição de cada oscilador → duas tabelas vizinhas e a mistura entre elas
        let travel = b.lfo * b.lfo_pos + b.env_pos * self.env_depth * self.flt.value();
        let mut mix = [0.0f32; 2];
        let mut lo = [0usize; 2];
        for k in 0..2 {
            let x = ((b.pos[k] + travel).clamp(0.0, 1.0)) * (TABLES - 1) as f32;
            lo[k] = (x as usize).min(TABLES - 2);
            mix[k] = x - lo[k] as f32;
        }
        // fatias das tabelas por cópia do uníssono (a versão depende da frequência da cópia)
        let mut tab_a: [[&[f32]; MAX_UNISON]; 2] = [[&[]; MAX_UNISON]; 2];
        let mut tab_b: [[&[f32]; MAX_UNISON]; 2] = [[&[]; MAX_UNISON]; 2];
        for (u, c) in self.copies[..uni].iter_mut().enumerate() {
            for k in 0..2 {
                c.dt[k] = (dt * b.ratio[k] * b.uni_ratio[u]).min(MAX_DT);
                let level = mip_level(c.dt[k]);
                tab_a[k][u] = tables.table(b.series[k], lo[k], level);
                tab_b[k][u] = tables.table(b.series[k], lo[k] + 1, level);
            }
        }

        let octaves = b.filter_env * self.env_depth * 6.0 * self.flt.value() + b.keytrack * (self.cur - 60.0) / 12.0 + b.lfo * b.lfo_cutoff;
        let g = Svf::g((b.cutoff + octaves).exp2().clamp(20.0, b.max_cutoff), b.rate);
        self.fl.set(g, b.k + RES_LIMIT_DEPTH * (self.res_l - RES_LIMIT_LEVEL).max(0.0));
        self.fr.set(g, b.k + RES_LIMIT_DEPTH * (self.res_r - RES_LIMIT_LEVEL).max(0.0));

        let (on1, on2, on_sub, on_noise) = (b.osc1.on(), b.osc2.on(), b.sub.on(), b.noise.on());
        let (mut lv1, mut lv2, mut lv_sub, mut lv_noise, mut gain) = (b.osc1.from, b.osc2.from, b.sub.from, b.noise.from, b.gain.from);
        let mut vel = self.vel_gain;
        let dv = self.vel_target - vel;
        self.vel_gain = if dv.abs() < 1e-5 { self.vel_target } else { vel + dv * b.smooth };
        let vel_step = (self.vel_gain - vel) / out_l.len().max(1) as f32;
        let (mut peak_l, mut peak_r) = (0.0f32, 0.0f32);
        for (out_l, out_r) in out_l.iter_mut().zip(out_r.iter_mut()) {
            let (mut l, mut r) = (0.0, 0.0);
            for (u, c) in self.copies[..uni].iter_mut().enumerate() {
                let mut x = 0.0;
                if on1 {
                    let (ta, tb) = (tab_a[0][u], tab_b[0][u]);
                    let (sa, sb) = (read(ta, c.ph[0]), read(tb, c.ph[0]));
                    x += (sa + (sb - sa) * mix[0]) * lv1;
                    c.ph[0] = wrap(c.ph[0] + c.dt[0]);
                }
                if on2 {
                    let (ta, tb) = (tab_a[1][u], tab_b[1][u]);
                    let (sa, sb) = (read(ta, c.ph[1]), read(tb, c.ph[1]));
                    x += (sa + (sb - sa) * mix[1]) * lv2;
                    c.ph[1] = wrap(c.ph[1] + c.dt[1]);
                }
                l += x * b.pan_l[u];
                r += x * b.pan_r[u];
            }
            // sub e ruído no centro, fora do uníssono: o grave continua firme e mono
            let mut mono = 0.0;
            if on_sub {
                mono += sin_turns(self.sub) * lv_sub;
                self.sub = wrap(self.sub + dt_sub);
            }
            if on_noise {
                mono += rng.bipolar() * lv_noise;
            }
            l += mono;
            r += mono;
            let (yl, band_l) = self.fl.tick(l, b.mode);
            let (yr, band_r) = self.fr.tick(r, b.mode);
            peak_l = peak_l.max(band_l.abs());
            peak_r = peak_r.max(band_r.abs());

            let mut g = self.amp.next() * vel * gain;
            self.flt.next();
            if self.dying {
                self.fade = (self.fade - b.fade_step).max(0.0);
                g *= self.fade;
            }
            *out_l += yl * g;
            *out_r += yr * g;

            lv1 += b.osc1.step;
            lv2 += b.osc2.step;
            lv_sub += b.sub.step;
            lv_noise += b.noise.step;
            gain += b.gain.step;
            vel += vel_step;
        }

        self.res_l = peak_l.max(self.res_l * b.res_release);
        self.res_r = peak_r.max(self.res_r * b.res_release);
        if self.res_l < 1e-6 {
            self.res_l = 0.0;
        }
        if self.res_r < 1e-6 {
            self.res_r = 0.0;
        }
        self.fl.flush();
        self.fr.flush();
        // um NaN aqui envenenaria a faixa inteira para sempre; melhor perder a nota
        if (self.dying && self.fade <= 0.0) || !self.fl.is_finite() || !self.fr.is_finite() {
            self.kill();
        }
    }
}

pub struct Wavetable {
    rate: f32,
    tables: Arc<Tables>,
    params: [f32; PARAMS],
    voices: [Voice; MAX_VOICES + SPARE_VOICES],
    held: [u8; 128],
    held_len: usize,
    clock: u64,
    last_pitch: Option<f32>,
    rng: Rng,
    lfo_phase: f32,
    lfo_hold: f32,
    lfo: f32,
    osc1: Smoothed,
    osc2: Smoothed,
    pos1: Smoothed,
    pos2: Smoothed,
    sub: Smoothed,
    noise: Smoothed,
    cutoff: Smoothed,
    resonance: Smoothed,
    level: Smoothed,
    tremolo: Smoothed,
    spread: Smoothed,
    gain: f32,
    pans_dirty: bool,
    block: Block,
}

impl Wavetable {
    pub fn new(rate: f64) -> Self {
        let seed = SEED.fetch_add(0x9E37_79B9, Ordering::Relaxed);
        let r = rate as f32;
        let mut s = Self {
            rate: r,
            tables: Tables::shared(),
            params: SPECS.map(|s| s.def),
            voices: std::array::from_fn(|_| Voice::new(rate)),
            held: [0; 128],
            held_len: 0,
            clock: 0,
            last_pitch: None,
            rng: Rng::new(seed),
            lfo_phase: 0.0,
            lfo_hold: 0.0,
            lfo: 0.0,
            osc1: Smoothed::new(0.0),
            osc2: Smoothed::new(0.0),
            pos1: Smoothed::new(0.0),
            pos2: Smoothed::new(0.0),
            sub: Smoothed::new(0.0),
            noise: Smoothed::new(0.0),
            cutoff: Smoothed::new(0.0),
            resonance: Smoothed::new(0.0),
            level: Smoothed::new(0.0),
            tremolo: Smoothed::new(0.0),
            spread: Smoothed::new(0.0),
            gain: 0.0,
            pans_dirty: true,
            block: Block {
                rate: r,
                series: [0; 2],
                pos: [0.0; 2],
                osc1: Ramp::default(),
                osc2: Ramp::default(),
                sub: Ramp::default(),
                noise: Ramp::default(),
                gain: Ramp::default(),
                unison: 1,
                uni_ratio: [1.0; MAX_UNISON],
                pan_l: [1.0; MAX_UNISON],
                pan_r: [1.0; MAX_UNISON],
                ratio: [1.0; 2],
                mode: FilterMode::LowPass,
                cutoff: 11.0,
                max_cutoff: 0.45 * r,
                k: 2.0,
                filter_env: 0.0,
                keytrack: 0.0,
                lfo: 0.0,
                lfo_pitch: 0.0,
                lfo_cutoff: 0.0,
                lfo_pos: 0.0,
                env_pos: 0.0,
                smooth: 1.0,
                glide: 1.0,
                res_release: 0.0,
                fade_step: 1.0 / (STEAL_SECS * r),
            },
        };
        for id in 0..P::COUNT {
            s.apply(id);
        }
        s.snap();
        s
    }

    fn limit(&self) -> usize {
        self.params[P::VOICES as usize] as usize
    }

    fn unison(&self) -> usize {
        self.params[P::UNISON as usize] as usize
    }

    fn glide_on(&self) -> bool {
        self.params[P::GLIDE as usize] > 0.0
    }

    fn apply(&mut self, id: u32) {
        let v = self.params[id as usize];
        let p = &self.params;
        match id {
            P::OSC1_LEVEL => self.osc1.set(v),
            P::OSC2_LEVEL => self.osc2.set(v),
            P::OSC1_POS => self.pos1.set(v),
            P::OSC2_POS => self.pos2.set(v),
            P::SUB_LEVEL => self.sub.set(v),
            P::NOISE_LEVEL => self.noise.set(v),
            P::CUTOFF => self.cutoff.set(v.log2()),
            P::RESONANCE => self.resonance.set(v),
            P::LEVEL => self.level.set(v),
            P::LFO_AMP => self.tremolo.set(v),
            P::UNISON_SPREAD => self.spread.set(v),
            P::OSC1_SEMI | P::OSC1_DETUNE => {
                self.block.ratio[0] = ((p[P::OSC1_SEMI as usize] + p[P::OSC1_DETUNE as usize] / 100.0) / 12.0).exp2();
            }
            P::OSC2_SEMI | P::OSC2_DETUNE => {
                self.block.ratio[1] = ((p[P::OSC2_SEMI as usize] + p[P::OSC2_DETUNE as usize] / 100.0) / 12.0).exp2();
            }
            P::UNISON | P::UNISON_DETUNE => {
                let n = self.unison();
                let width = p[P::UNISON_DETUNE as usize];
                for (u, ratio) in self.block.uni_ratio.iter_mut().enumerate() {
                    *ratio = (unison_position(u, n) * width * 0.5 / 1200.0).exp2();
                }
                self.block.unison = n;
                self.pans_dirty = true;
            }
            P::AMP_ATTACK | P::AMP_DECAY | P::AMP_SUSTAIN | P::AMP_RELEASE => {
                let (a, d, s, r) = (p[P::AMP_ATTACK as usize], p[P::AMP_DECAY as usize], p[P::AMP_SUSTAIN as usize], p[P::AMP_RELEASE as usize]);
                for voice in &mut self.voices {
                    voice.amp.set(a, d, s, r);
                }
            }
            P::FLT_ATTACK | P::FLT_DECAY | P::FLT_SUSTAIN | P::FLT_RELEASE => {
                let (a, d, s, r) = (p[P::FLT_ATTACK as usize], p[P::FLT_DECAY as usize], p[P::FLT_SUSTAIN as usize], p[P::FLT_RELEASE as usize]);
                for voice in &mut self.voices {
                    voice.flt.set(a, d, s, r);
                }
            }
            P::VOICES => {
                let limit = self.limit();
                while self.busy_count() > limit {
                    match self.victim() {
                        Some(i) => self.voices[i].dying = true,
                        None => break,
                    }
                }
            }
            // os demais são lidos direto de `params` a cada bloco
            _ => {}
        }
    }

    fn snap(&mut self) {
        for s in [
            &mut self.osc1,
            &mut self.osc2,
            &mut self.pos1,
            &mut self.pos2,
            &mut self.sub,
            &mut self.noise,
            &mut self.cutoff,
            &mut self.resonance,
            &mut self.level,
            &mut self.tremolo,
            &mut self.spread,
        ] {
            s.snap();
        }
        self.pans_dirty = true;
        self.gain = VOICE_GAIN * self.level.value * (1.0 - self.tremolo.value * (1.0 - self.lfo) * 0.5);
    }

    fn update_pans(&mut self, spread: f32) {
        let n = self.unison();
        // √2 põe o centro em 0 dB (a lei de potência constante dá −3 dB no meio)
        let norm = std::f32::consts::SQRT_2 / (n as f32).sqrt();
        for u in 0..MAX_UNISON {
            let (l, r) = pan_gains(unison_position(u, n) * spread);
            self.block.pan_l[u] = l * norm;
            self.block.pan_r[u] = r * norm;
        }
    }

    fn prepare(&mut self, len: usize) {
        let frames = len as f32;
        let rate = self.rate;
        let a = smoothing(PARAM_TAU, len, rate);
        let p = self.params;

        let b = &mut self.block;
        b.osc1 = Ramp::advance(&mut self.osc1, a, frames);
        b.osc2 = Ramp::advance(&mut self.osc2, a, frames);
        b.sub = Ramp::advance(&mut self.sub, a, frames);
        b.noise = Ramp::advance(&mut self.noise, a, frames);
        b.pos = [self.pos1.step(a), self.pos2.step(a)];
        b.series = [p[P::OSC1_SERIES as usize] as usize, p[P::OSC2_SERIES as usize] as usize];

        b.mode = match p[P::FILTER_TYPE as usize] as i32 {
            1 => FilterMode::HighPass,
            2 => FilterMode::BandPass,
            _ => FilterMode::LowPass,
        };
        b.cutoff = self.cutoff.step(a);
        // Q de 0,5 a MAX_Q em escala exponencial
        b.k = 2.0 * (-self.resonance.step(a) * (2.0 * MAX_Q).ln()).exp();
        b.filter_env = p[P::FILTER_ENV as usize];
        b.keytrack = p[P::KEYTRACK as usize];
        b.lfo_pos = p[P::LFO_POS as usize];
        b.env_pos = p[P::ENV_POS as usize];

        self.lfo_phase += p[P::LFO_RATE as usize] * frames / rate;
        if self.lfo_phase >= 1.0 {
            self.lfo_phase -= self.lfo_phase.floor();
            self.lfo_hold = self.rng.bipolar();
        }
        let raw = lfo_shape(p[P::LFO_WAVE as usize] as u32, self.lfo_phase, self.lfo_hold);
        let dl = raw - self.lfo;
        self.lfo = if dl.abs() < 1e-6 { raw } else { self.lfo + dl * smoothing(LFO_TAU, len, rate) };
        b.lfo = self.lfo;
        b.lfo_pitch = p[P::LFO_PITCH as usize];
        b.lfo_cutoff = p[P::LFO_CUTOFF as usize];
        let tremolo = 1.0 - self.tremolo.step(a) * (1.0 - self.lfo) * 0.5;
        let gain = VOICE_GAIN * self.level.step(a) * tremolo;
        b.gain = Ramp { from: self.gain, step: (gain - self.gain) / frames };
        self.gain = gain;

        b.smooth = a;
        let glide = p[P::GLIDE as usize];
        b.glide = if glide > 0.0 { smoothing(glide / 4.6, len, rate) } else { 1.0 };
        b.res_release = 1.0 - smoothing(RES_LIMIT_TAU, len, rate);

        if self.pans_dirty || !self.spread.settled() {
            let spread = self.spread.step(a);
            self.update_pans(spread);
            self.pans_dirty = false;
        }
    }

    fn busy_count(&self) -> usize {
        self.voices.iter().filter(|v| v.busy()).count()
    }

    /// A voz a roubar: a mais baixa entre as já soltas; se todas estão presas, a mais antiga.
    fn victim(&self) -> Option<usize> {
        let busy = self.voices.iter().enumerate().filter(|(_, v)| v.busy());
        let released = busy.clone().filter(|(_, v)| !v.gate).min_by(|a, b| a.1.amp.value().total_cmp(&b.1.amp.value()));
        released.or_else(|| busy.min_by_key(|(_, v)| v.age)).map(|(i, _)| i)
    }

    fn free_voice(&mut self) -> usize {
        let i = match self.voices.iter().position(|v| !v.amp.active()) {
            Some(i) => i,
            None => {
                let dying = self.voices.iter().enumerate().filter(|(_, v)| v.dying).min_by(|a, b| a.1.fade.total_cmp(&b.1.fade)).map(|(i, _)| i);
                dying.or_else(|| self.victim()).unwrap_or(0)
            }
        };
        self.voices[i].kill();
        i
    }

    fn start(&mut self, i: usize, pitch: u8, velocity: f32) {
        let from = if self.glide_on() { self.last_pitch } else { None };
        let unison = self.unison();
        let sensitivity = self.params[P::VELOCITY as usize];
        let v = &mut self.voices[i];
        for (u, c) in v.copies.iter_mut().enumerate() {
            // uma cópia só parte da fase zero (ataque igual toda vez); no uníssono, fases
            // aleatórias, senão as cópias em fase soariam como uma só, mais alta
            if unison == 1 && u == 0 {
                c.ph = [0.0; 2];
            } else {
                c.ph = [self.rng.unit(), self.rng.unit()];
            }
        }
        v.sub = 0.0;
        v.target = pitch as f32;
        v.cur = from.unwrap_or(v.target);
        v.trigger(pitch, velocity, sensitivity, self.clock);
        v.vel_gain = v.vel_target;
    }

    fn poly_on(&mut self, pitch: u8, velocity: f32) {
        let sensitivity = self.params[P::VELOCITY as usize];
        if let Some(v) = self.voices.iter_mut().find(|v| v.busy() && v.pitch == pitch) {
            v.target = pitch as f32;
            v.trigger(pitch, velocity, sensitivity, self.clock);
            return;
        }
        let limit = self.limit();
        while self.busy_count() >= limit {
            match self.victim() {
                Some(i) => self.voices[i].dying = true,
                None => break,
            }
        }
        let i = self.free_voice();
        self.start(i, pitch, velocity);
    }

    fn mono_voice(&mut self) -> Option<usize> {
        let newest = self.voices.iter().enumerate().filter(|(_, v)| v.busy()).max_by_key(|(_, v)| v.age).map(|(i, _)| i)?;
        for (i, v) in self.voices.iter_mut().enumerate() {
            if i != newest && v.busy() {
                v.dying = true;
            }
        }
        Some(newest)
    }

    fn mono_on(&mut self, pitch: u8, velocity: f32) {
        let glide = self.glide_on();
        let sensitivity = self.params[P::VELOCITY as usize];
        let clock = self.clock;
        match self.mono_voice() {
            Some(i) => {
                let v = &mut self.voices[i];
                if v.gate && v.pitch != pitch {
                    // legato: outra tecla ainda presa, só a altura muda
                    v.slide(pitch, glide);
                    v.age = clock;
                } else {
                    v.slide(pitch, glide);
                    v.trigger(pitch, velocity, sensitivity, clock);
                }
            }
            None => {
                let i = self.free_voice();
                self.start(i, pitch, velocity);
            }
        }
    }

    fn push_held(&mut self, pitch: u8) {
        self.remove_held(pitch);
        if self.held_len < self.held.len() {
            self.held[self.held_len] = pitch;
            self.held_len += 1;
        }
    }

    fn remove_held(&mut self, pitch: u8) {
        if let Some(i) = self.held[..self.held_len].iter().position(|&p| p == pitch) {
            self.held.copy_within(i + 1..self.held_len, i);
            self.held_len -= 1;
        }
    }
}

impl Instrument for Wavetable {
    fn note_on(&mut self, pitch: u8, velocity: f32) {
        let velocity = if velocity.is_nan() { 1.0 } else { velocity.clamp(0.0, 1.0) };
        if !self.active() {
            self.snap();
        }
        self.clock += 1;
        self.push_held(pitch);
        if self.limit() == 1 {
            self.mono_on(pitch, velocity);
        } else {
            self.poly_on(pitch, velocity);
        }
        self.last_pitch = Some(pitch as f32);
    }

    fn note_off(&mut self, pitch: u8) {
        self.remove_held(pitch);
        // no mono, soltar a nota que soa com outras presas volta para a última delas, sem redisparar
        let back_to = if self.limit() == 1 { self.held[..self.held_len].last().copied() } else { None };
        let glide = self.glide_on();
        for v in self.voices.iter_mut().filter(|v| v.busy() && v.gate && v.pitch == pitch) {
            match back_to {
                Some(p) => v.slide(p, glide),
                None => v.release(),
            }
        }
    }

    fn release_all(&mut self) {
        self.held_len = 0;
        for v in &mut self.voices {
            if v.gate {
                v.release();
            }
        }
    }

    fn silence(&mut self) {
        self.held_len = 0;
        for v in &mut self.voices {
            v.kill();
        }
    }

    fn set_param(&mut self, id: u32, value: f32) {
        let Some(spec) = SPECS.get(id as usize) else { return };
        if value.is_nan() {
            return;
        }
        let v = value.clamp(spec.min, spec.max);
        self.params[id as usize] = if spec.discrete { v.round() } else { v };
        self.apply(id);
    }

    fn render(&mut self, left: &mut [f32], right: &mut [f32]) {
        if !self.active() {
            return;
        }
        let n = left.len().min(right.len());
        let mut done = 0;
        while done < n {
            let len = (n - done).min(CONTROL);
            self.prepare(len);
            let (l, r) = (&mut left[done..done + len], &mut right[done..done + len]);
            for v in self.voices.iter_mut().filter(|v| v.amp.active()) {
                if v.silent_hold() {
                    if v.dying {
                        v.kill();
                    }
                    continue;
                }
                v.render(&self.block, &self.tables, &mut self.rng, l, r);
            }
            done += len;
        }
    }

    fn active(&self) -> bool {
        self.voices.iter().any(|v| v.amp.active())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::instrument::contract;

    const RATE: f64 = 48_000.0;

    fn run(s: &mut Wavetable, frames: usize) -> (Vec<f32>, Vec<f32>) {
        let (mut l, mut r) = (vec![0.0; frames], vec![0.0; frames]);
        for (cl, cr) in l.chunks_mut(128).zip(r.chunks_mut(128)) {
            s.render(cl, cr);
        }
        (l, r)
    }

    fn rms(x: &[f32]) -> f32 {
        (x.iter().map(|v| v * v).sum::<f32>() / x.len() as f32).sqrt()
    }

    fn peak(x: &[f32]) -> f32 {
        x.iter().fold(0.0, |m, v| m.max(v.abs()))
    }

    fn set(s: &mut Wavetable, params: &[(u32, f32)]) {
        for &(id, v) in params {
            s.set_param(id, v);
        }
    }

    /// Só o oscilador 1, filtro aberto, sem envelope de filtro nem LFO.
    fn plain(series: f32, pos: f32) -> Wavetable {
        let mut s = Wavetable::new(RATE);
        set(
            &mut s,
            &[
                (P::OSC1_SERIES, series),
                (P::OSC1_POS, pos),
                (P::OSC1_LEVEL, 1.0),
                (P::OSC2_LEVEL, 0.0),
                (P::CUTOFF, 20_000.0),
                (P::RESONANCE, 0.0),
                (P::FILTER_ENV, 0.0),
                (P::KEYTRACK, 0.0),
                (P::AMP_SUSTAIN, 1.0),
                (P::AMP_ATTACK, 0.0005),
            ],
        );
        s
    }

    fn frequency(x: &[f32]) -> f32 {
        let (mut first, mut last, mut count) = (None, 0.0, 0);
        for (i, w) in x.windows(2).enumerate() {
            if w[0] < 0.0 && w[1] >= 0.0 {
                let t = i as f64 + (-w[0] / (w[1] - w[0])) as f64;
                first.get_or_insert(t);
                last = t;
                count += 1;
            }
        }
        ((count - 1) as f64 / ((last - first.unwrap()) / RATE)) as f32
    }

    /// Amplitude do harmônico `h` de um ciclo de tabela (DFT direta de um bin).
    fn bin(t: &[f32], h: usize) -> f32 {
        let (mut re, mut im) = (0.0f64, 0.0f64);
        for (n, &v) in t[..TABLE_LEN].iter().enumerate() {
            let w = TAU * (h * n) as f64 / TABLE_LEN as f64;
            re += v as f64 * w.cos();
            im += v as f64 * w.sin();
        }
        (2.0 * (re * re + im * im).sqrt() / TABLE_LEN as f64) as f32
    }

    #[test]
    fn tabelas_normalizadas_e_sem_dc() {
        let t = Tables::shared();
        for series in 0..SERIES {
            for table in 0..TABLES {
                let full = t.table(series, table, 0);
                let mean = full[..TABLE_LEN].iter().sum::<f32>() / TABLE_LEN as f32;
                let (pk, r) = (peak(full), rms(&full[..TABLE_LEN]));
                assert!(mean.abs() < 1e-3, "série {series} tabela {table}: DC {mean}");
                assert!(pk > 0.3 && pk <= 1.65, "série {series} tabela {table}: pico {pk}");
                assert!(r > 0.1 && r < 0.55, "série {series} tabela {table}: rms {r}");
                assert_eq!(full[0], full[TABLE_LEN], "ponto de guarda");
                assert!(full.iter().all(|v| v.is_finite()));
            }
        }
    }

    #[test]
    fn morfologia_das_tabelas_classicas() {
        let t = Tables::shared();
        // senoide: só o 1º harmônico
        let sine = t.table(0, 0, 0);
        assert!(bin(sine, 1) > 0.6 && bin(sine, 2) < 1e-3 && bin(sine, 3) < 1e-3);
        // triângulo: ímpares caindo com 1/h²
        let tri = t.table(0, 1, 0);
        assert!(bin(tri, 2) < 1e-3 && (bin(tri, 3) / bin(tri, 1) - 1.0 / 9.0).abs() < 0.01);
        // serra: todos os harmônicos, 1/h
        let saw = t.table(0, 2, 0);
        assert!((bin(saw, 2) / bin(saw, 1) - 0.5).abs() < 0.01 && (bin(saw, 4) / bin(saw, 1) - 0.25).abs() < 0.01);
        // quadrada: só ímpares, 1/h
        let sq = t.table(0, 3, 0);
        assert!(bin(sq, 2) < 1e-3 && (bin(sq, 3) / bin(sq, 1) - 1.0 / 3.0).abs() < 0.01);
        // pulso estreito: harmônicos pares presentes
        assert!(bin(t.table(0, 6, 0), 2) > 0.05);
        // a série de pulsos estreita de verdade: a fração do ciclo acima da metade do pico cai
        let duty = |tab: &[f32]| {
            let pk = peak(tab);
            tab[..TABLE_LEN].iter().filter(|&&v| v > 0.5 * pk).count() as f32 / TABLE_LEN as f32
        };
        let d: Vec<f32> = (3..8).map(|i| duty(t.table(0, i, 0))).collect();
        assert!(d.windows(2).all(|w| w[1] < w[0]), "{d:?}");
        assert!((d[0] - 0.5).abs() < 0.03 && d[4] < 0.1, "{d:?}");
    }

    #[test]
    fn vogais_tem_os_formantes_certos() {
        let t = Tables::shared();
        // fundamental de 150 Hz: harmônico h fica em 150·h Hz. O maior pico do espectro cai
        // perto do 1º formante de cada vogal (A 800, E 400, I 300, O 450, U 320)
        for (table, f1) in [(0, 800.0), (1, 400.0), (2, 300.0), (3, 450.0), (4, 320.0)] {
            let tab = t.table(1, table, 0);
            let best = (1..=40).max_by(|&a, &b| bin(tab, a).total_cmp(&bin(tab, b))).unwrap();
            let hz = 150.0 * best as f32;
            assert!((hz - f1).abs() <= 160.0, "vogal {table}: pico em {hz} Hz, esperava perto de {f1}");
        }
    }

    #[test]
    fn digital_e_metalica_tem_o_espectro_prometido() {
        let t = Tables::shared();
        let odd = t.table(2, 0, 0);
        assert!(bin(odd, 2) < 1e-3 && bin(odd, 3) > 0.05);
        let primes = t.table(2, 4, 0);
        assert!(bin(primes, 4) < 1e-3 && bin(primes, 6) < 1e-3 && bin(primes, 7) > 0.02 && bin(primes, 11) > 0.02);
        let glass = t.table(2, 7, 0);
        assert!(bin(glass, 13) > bin(glass, 6) && bin(glass, 13) > 0.05);
    }

    #[test]
    fn versoes_de_banda_limitada() {
        let t = Tables::shared();
        for level in 0..LEVELS {
            let max_h = MAX_HARMONICS >> level;
            let tab = t.table(0, 2, level);
            // acima do último harmônico da versão não sobra nada (as duas versões vizinhas diferem)
            for h in [max_h + 1, max_h + 3, (2 * max_h).min(300)] {
                if h < TABLE_LEN / 2 {
                    assert!(bin(tab, h) < 2e-3, "versão {level}: harmônico {h} = {}", bin(tab, h));
                }
            }
            // o último harmônico continua lá, com a amplitude 1/h da serra
            assert!(bin(tab, max_h) > 0.5 * bin(tab, 1) / max_h as f32, "versão {level} perdeu o último harmônico");
        }
    }

    #[test]
    fn mip_nunca_passa_de_nyquist() {
        for pitch in 0..=127 {
            for cents in [0.0f32, 30.0, 100.0] {
                let dt = pitch_hz(pitch as f32 + cents / 100.0) / RATE as f32;
                let level = mip_level(dt.min(MAX_DT));
                let top = (MAX_HARMONICS >> level) as f32 * dt.min(MAX_DT);
                // só o 1º harmônico pode passar do limite (não há versão mais pobre que ele)
                assert!(top <= BAND_LIMIT + 1e-4 || level == LEVELS - 1, "nota {pitch}: {top}");
                assert!(top <= 0.5 || level == LEVELS - 1);
            }
        }
        assert_eq!(mip_level(50.0 / RATE as f32), 0);
        assert!(mip_level(4000.0 / RATE as f32) >= 5);
    }

    #[test]
    fn frequencia_correta() {
        for (pitch, semi) in [(69u8, 0.0f32), (57, 0.0), (48, 12.0), (81, -12.0)] {
            let mut s = plain(0.0, 0.0);
            set(&mut s, &[(P::OSC1_SEMI, semi)]);
            s.note_on(pitch, 1.0);
            let (l, _) = run(&mut s, 24_000);
            let want = pitch_hz(pitch as f32 + semi);
            let got = frequency(&l[4800..]);
            assert!((got / want - 1.0).abs() < 0.003, "nota {pitch} {semi} st: {got} Hz, esperava {want}");
        }
    }

    #[test]
    fn posicao_mistura_as_tabelas_vizinhas() {
        // posição 0,5/7 entre a senoide (0) e o triângulo (1): o 3º harmônico é metade do do triângulo
        let tri3 = {
            let t = Tables::shared();
            bin(t.table(0, 1, 0), 3)
        };
        let mut s = plain(0.0, 0.5 / 7.0);
        set(&mut s, &[(P::CUTOFF, 20_000.0)]);
        s.note_on(45, 1.0);
        let (l, _) = run(&mut s, 24_000);
        let f = pitch_hz(45.0) as f64;
        let tone = |hz: f64| {
            let x = &l[4800..];
            let (mut re, mut im) = (0.0f64, 0.0f64);
            for (i, &v) in x.iter().enumerate() {
                let w = TAU * hz / RATE * i as f64;
                re += v as f64 * w.cos();
                im += v as f64 * w.sin();
            }
            (2.0 * (re * re + im * im).sqrt() / x.len() as f64) as f32
        };
        let unit = VOICE_GAIN * 0.7;
        let want = 0.5 * tri3 * unit;
        assert!((tone(3.0 * f) / want - 1.0).abs() < 0.08, "{} vs {want}", tone(3.0 * f));
    }

    #[test]
    fn posicao_move_o_timbre_continuamente() {
        // varrer a posição de 0 a 1 em passos pequenos nunca muda o som de golpe
        let mut prev: Option<Vec<f32>> = None;
        for i in 0..=28 {
            let mut s = plain(0.0, i as f32 / 28.0);
            s.note_on(48, 1.0);
            let (l, _) = run(&mut s, 2400);
            let cur = l[1200..].to_vec();
            if let Some(p) = &prev {
                let d: f32 = p.iter().zip(&cur).map(|(a, b)| (a - b).abs()).fold(0.0, f32::max);
                assert!(d < 0.45, "passo {i}: {d}");
            }
            prev = Some(cur);
        }
    }

    #[test]
    fn todas_as_series_soam_em_todas_as_posicoes() {
        for series in 0..3 {
            for tab in 0..8 {
                let mut s = plain(series as f32, tab as f32 / 7.0);
                s.note_on(52, 0.9);
                let (l, r) = run(&mut s, 6000);
                assert!(l == r || rms(&l) > 0.0);
                let level = rms(&l[3000..]);
                assert!(level > 0.03 && level < 0.7 && peak(&l) < 1.6, "série {series} tabela {tab}: rms {level} pico {}", peak(&l));
            }
        }
    }

    #[test]
    fn extremos_sem_nan_nem_infinito() {
        for &(pitch, unison, res, fenv) in &[(0u8, 7.0f32, 1.0f32, 1.0f32), (127, 7.0, 1.0, -1.0), (60, 1.0, 1.0, 1.0), (100, 3.0, 0.5, 0.0)] {
            for series in 0..3 {
                let mut s = Wavetable::new(RATE);
                set(
                    &mut s,
                    &[
                        (P::OSC1_SERIES, series as f32),
                        (P::OSC2_SERIES, (series as f32 + 1.0) % 3.0),
                        (P::OSC1_POS, 1.0),
                        (P::OSC2_POS, 0.0),
                        (P::OSC2_LEVEL, 1.0),
                        (P::OSC1_SEMI, 24.0),
                        (P::OSC2_SEMI, 24.0),
                        (P::UNISON, unison),
                        (P::UNISON_DETUNE, 100.0),
                        (P::RESONANCE, res),
                        (P::FILTER_ENV, fenv),
                        (P::CUTOFF, 20.0),
                        (P::SUB_LEVEL, 1.0),
                        (P::NOISE_LEVEL, 1.0),
                        (P::LFO_POS, 1.0),
                        (P::LFO_PITCH, 12.0),
                        (P::LFO_CUTOFF, 4.0),
                        (P::LFO_AMP, 1.0),
                        (P::LFO_RATE, 30.0),
                        (P::ENV_POS, 1.0),
                    ],
                );
                for cutoff in [20.0, 20_000.0] {
                    s.set_param(P::CUTOFF, cutoff);
                    s.note_on(pitch, 1.0);
                    s.note_on(pitch.saturating_add(5).min(127), 1.0);
                    let (l, r) = run(&mut s, 9600);
                    assert!(l.iter().chain(&r).all(|x| x.is_finite() && x.abs() < 12.0), "nota {pitch} série {series}");
                }
            }
        }
    }

    #[test]
    fn parametros_absurdos_sao_limitados() {
        let mut s = Wavetable::new(RATE);
        for id in 0..P::COUNT + 5 {
            for v in [f32::MIN, -1e30, -1.0, 0.0, 1e30, f32::MAX, f32::INFINITY, f32::NEG_INFINITY, f32::NAN] {
                s.set_param(id, v);
            }
        }
        s.note_on(60, 1.0);
        let (l, r) = run(&mut s, 4800);
        assert!(l.iter().chain(&r).all(|x| x.is_finite()));
    }

    #[test]
    fn release_termina_e_active_acompanha() {
        let mut s = Wavetable::new(RATE);
        assert!(!s.active());
        s.note_on(60, 0.8);
        assert!(s.active());
        let (l, r) = run(&mut s, 4800);
        assert!(rms(&l[480..]) > 0.02 && rms(&r[480..]) > 0.02);
        s.note_off(60);
        assert!(s.active(), "em release ainda conta como ativa");
        let (l, r) = run(&mut s, 96_000);
        assert!(!s.active());
        assert!(l[90_000..].iter().chain(&r[90_000..]).all(|&x| x == 0.0));
        s.note_on(60, 1.0);
        s.silence();
        assert!(!s.active());
    }

    #[test]
    fn unissono_alarga_o_estereo() {
        let corr = |unison: f32| {
            let mut s = plain(0.0, 0.2);
            set(&mut s, &[(P::UNISON, unison), (P::UNISON_DETUNE, 40.0), (P::UNISON_SPREAD, 1.0)]);
            s.note_on(48, 1.0);
            let (l, r) = run(&mut s, 24_000);
            let (l, r) = (&l[4800..], &r[4800..]);
            let dot: f32 = l.iter().zip(r).map(|(a, b)| a * b).sum();
            dot / (l.iter().map(|v| v * v).sum::<f32>().sqrt() * r.iter().map(|v| v * v).sum::<f32>().sqrt())
        };
        assert!(corr(1.0) > 0.999);
        assert!(corr(7.0) < 0.9, "{}", corr(7.0));
    }

    #[test]
    fn lfo_move_a_posicao() {
        // com o LFO na posição a forma de onda muda ao longo do tempo: 2 janelas diferentes
        let mut s = plain(0.0, 0.5);
        set(&mut s, &[(P::LFO_POS, 0.5), (P::LFO_RATE, 2.0)]);
        s.note_on(48, 1.0);
        let (l, _) = run(&mut s, 48_000);
        let a = rms(&l[6000..7000]);
        let b = rms(&l[30_000..31_000]);
        let c: f32 = l[6000..7000].iter().zip(&l[30_000..31_000]).map(|(x, y)| (x - y).abs()).sum();
        assert!(c > 1.0 || (a - b).abs() > 0.01, "{a} {b} {c}");
    }

    #[test]
    fn envelope_do_filtro_move_a_posicao() {
        let mut s = plain(0.0, 0.0);
        set(&mut s, &[(P::ENV_POS, 1.0), (P::FLT_ATTACK, 0.5), (P::FLT_DECAY, 0.4), (P::FLT_SUSTAIN, 1.0)]);
        s.note_on(48, 1.0);
        // no começo do envelope a posição é 0 (senoide); com o envelope no topo, é 1 (pulso 6%)
        let (l, _) = run(&mut s, 48_000);
        let f = pitch_hz(48.0);
        let h = |x: &[f32]| {
            let (mut re, mut im) = (0.0f64, 0.0f64);
            for (i, &v) in x.iter().enumerate() {
                let w = TAU * (2.0 * f as f64) / RATE * i as f64;
                re += v as f64 * w.cos();
                im += v as f64 * w.sin();
            }
            (re * re + im * im).sqrt() / x.len() as f64
        };
        assert!(h(&l[36_000..40_800]) > 4.0 * h(&l[400..2000]).max(1e-6), "{} {}", h(&l[36_000..40_800]), h(&l[400..2000]));
    }

    #[test]
    fn polifonia_rouba_a_voz_e_nao_estala() {
        let mut s = plain(0.0, 0.0);
        set(&mut s, &[(P::VOICES, 2.0)]);
        s.note_on(60, 1.0);
        s.note_on(64, 1.0);
        run(&mut s, 4800);
        s.note_on(67, 1.0);
        assert_eq!(s.voices.iter().filter(|v| v.busy()).count(), 2);
        assert!(!s.voices.iter().any(|v| v.busy() && v.pitch == 60));
        let (l, _) = run(&mut s, 2400);
        let jump = l.windows(2).map(|w| (w[1] - w[0]).abs()).fold(0.0, f32::max);
        assert!(jump < 0.2, "salto {jump}");
    }

    #[test]
    fn mono_legato_e_portamento() {
        let mut s = plain(0.0, 0.0);
        set(&mut s, &[(P::VOICES, 1.0), (P::GLIDE, 0.2)]);
        s.note_on(60, 1.0);
        run(&mut s, 4800);
        s.note_on(72, 1.0);
        assert_eq!(s.voices.iter().filter(|v| v.busy()).count(), 1);
        let (l, _) = run(&mut s, 4800);
        let mid = frequency(&l[2400..]);
        assert!(mid > pitch_hz(60.0) * 1.02 && mid < pitch_hz(72.0) * 0.98, "{mid}");
        let (l, _) = run(&mut s, 48_000);
        assert!((frequency(&l[24_000..]) / pitch_hz(72.0) - 1.0).abs() < 0.005);
    }

    #[test]
    fn nao_aloca_depois_do_new() {
        let mut s = Wavetable::new(RATE);
        let (mut l, mut r) = (vec![0.0; 128], vec![0.0; 128]);
        let allocs = crate::testalloc::count(|| {
            set(&mut s, &[(P::UNISON, 7.0), (P::OSC2_LEVEL, 1.0), (P::SUB_LEVEL, 0.5), (P::NOISE_LEVEL, 0.2), (P::LFO_POS, 0.5), (P::ENV_POS, 0.5)]);
            for p in 30..46 {
                s.note_on(p, 0.8);
            }
            set(&mut s, &[(P::OSC1_SERIES, 1.0), (P::OSC2_SERIES, 2.0), (P::VOICES, 3.0), (P::GLIDE, 0.1)]);
            for _ in 0..50 {
                s.render(&mut l, &mut r);
            }
            s.note_off(30);
            s.release_all();
            s.silence();
            s.note_on(60, 1.0);
            s.render(&mut l, &mut r);
        });
        assert_eq!(allocs, 0);
    }

    #[test]
    fn segunda_instancia_reaproveita_as_tabelas() {
        let a = Wavetable::new(RATE);
        let b = Wavetable::new(RATE);
        assert!(Arc::ptr_eq(&a.tables, &b.tables));
    }

    // ------------------------------------------------------------ contrato com o app

    #[test]
    fn faixas_iguais_as_do_app() {
        let rows: Vec<contract::Row> = SPECS.iter().map(|s| (s.min, s.max, s.def, s.discrete)).collect();
        contract::check("wavetableParams", &rows);
    }

    // ------------------------------------------------------------ desempenho

    fn bench(voices: usize, unison: f32, extra: &[(u32, f32)]) -> f64 {
        let mut s = Wavetable::new(RATE);
        set(&mut s, &[(P::UNISON, unison), (P::VOICES, 16.0), (P::AMP_SUSTAIN, 1.0), (P::OSC2_LEVEL, 0.5)]);
        set(&mut s, extra);
        for i in 0..voices {
            s.note_on(48 + (i as u8 * 5) % 36, 0.8);
        }
        let (mut l, mut r) = (vec![0.0; 128], vec![0.0; 128]);
        run(&mut s, 4800);
        let t = std::time::Instant::now();
        for _ in 0..375 {
            s.render(&mut l, &mut r);
            std::hint::black_box((&l, &r));
        }
        t.elapsed().as_secs_f64()
    }

    type Case = (&'static str, usize, f32, &'static [(u32, f32)]);

    #[test]
    #[ignore = "medição: cargo test --release -p jopendaw-engine -- --ignored --nocapture"]
    fn desempenho() {
        let t = std::time::Instant::now();
        let tables = Tables::build();
        println!("Wavetable: gerar as {} tabelas x {} versões: {:.1} ms", SERIES * TABLES, LEVELS, t.elapsed().as_secs_f64() * 1000.0);
        std::hint::black_box(tables);
        let cases: [Case; 3] = [
            ("8 vozes × 1 uníssono, 2 osciladores", 8, 1.0, &[]),
            ("8 vozes × 3 uníssono", 8, 3.0, &[]),
            ("16 vozes × 7 uníssono (pior caso)", 16, 7.0, &[(P::SUB_LEVEL, 0.5), (P::NOISE_LEVEL, 0.2), (P::LFO_POS, 0.5)]),
        ];
        for (name, voices, unison, extra) in cases {
            let secs = (0..10).map(|_| bench(voices, unison, extra)).fold(f64::MAX, f64::min);
            println!("Wavetable {name}: 1 s de áudio a 48 kHz em {:.2} ms ({:.2}% de um núcleo)", secs * 1000.0, secs * 100.0);
        }
    }
}
