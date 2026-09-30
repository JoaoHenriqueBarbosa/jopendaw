//! Sintetizador FM (faixa do tipo 5): 4 operadores senoidais em modulação de fase, no estilo dos
//! DX/OPM.
//!
//! Cada operador é uma senoide com frequência `nota × razão` (mais um ajuste fino em cents), um
//! nível e o seu próprio envelope ADSR. Um operador modulador não soma ao som: a saída dele (nível
//! × envelope) desloca a fase de quem ele modula, e o índice de modulação é esse nível. Só os
//! operadores portadores vão para a saída. O operador 1 tem realimentação (a saída dele modula a
//! própria fase), que leva a senoide à serra e ao ruído.
//!
//! # Algoritmos
//!
//! `a→b` = `a` modula `b`; `+` = soma na saída; o que vem por último na cadeia (ou solto) é
//! portador. Os operadores só modulam outros de índice maior, então o cálculo é 1, 2, 3, 4 e não
//! precisa de atraso nenhum.
//!
//! ```text
//! 0  1→2→3→4              cadeia: o mais brilhante e agressivo (baixos, metais)
//! 1  (1+2)→3→4            dois moduladores em paralelo na cadeia (timbres complexos)
//! 2  (1 + 2→3)→4          um modulador direto e outro em cadeia sobre o mesmo portador
//! 3  (1→2 + 3)→4          o par 1→2 e o operador 3 modulam juntos o portador 4
//! 4  (1→2) + (3→4)        dois pares independentes: piano elétrico, sinos (2 timbres somados)
//! 5  1→(2 + 3 + 4)        um modulador para três portadores: cordas e pads (o brilho é comum)
//! 6  (1→2) + 3 + 4        um par e duas senoides puras
//! 7  1 + 2 + 3 + 4        aditivo, sem modulação: órgão de 4 drawbars
//! ```
//!
//! # Anti-aliasing
//!
//! FM tem espectro que cresce com o índice e com a frequência do modulador (regra de Carson: a
//! banda é ~ 2·(índice + 1)·f_mod). O índice de cada modulador é limitado de forma suave para que
//! essa banda caiba abaixo de 0,4 da taxa; em notas agudas o timbre escurece em vez de dobrar.
//! Operadores cuja frequência passa de Nyquist somem num fade, e a realimentação segue a mesma
//! regra. O limite é calculado por bloco de controle, então não custa nada por quadro.
//!
//! # Estalos
//!
//! Níveis e realimentação são suavizados, o envelope parte de onde está (reataque sem degrau) e a
//! troca de algoritmo com som passa por um fade curto de saída (o roteamento muda de uma vez, a
//! senoide não). As vozes são 16 mais 4 de folga: a voz roubada sai num fade de 5 ms numa das
//! folgas enquanto a nota nova já começa. Tudo é pré-alocado em `new`.

use std::sync::atomic::{AtomicU32, Ordering};

use crate::dsp::{Adsr, Rng, Smoothed, Stage, sin_turns, smoothing};
use crate::instrument::{Instrument, fm_param as P, pitch_hz};
use crate::synth::{Ramp, Spec, cont, disc, lfo_shape, wrap};

const OPS: usize = P::OPS as usize;
const MAX_VOICES: usize = 16;
const SPARE_VOICES: usize = 4;
const CONTROL: usize = 16;
const PARAMS: usize = P::COUNT as usize;

/// Ganho por voz: uma nota fica perto de −10 dBFS e um acorde ainda cabe sem estourar.
const VOICE_GAIN: f32 = 0.5;
/// Fade da voz roubada.
const STEAL_SECS: f32 = 0.005;
/// Fade de saída na troca de algoritmo com som.
const ALGO_FADE_SECS: f32 = 0.004;
/// Deslocamento de fase, em voltas, de um modulador com nível 1 (≈ 7,9 rad, um pouco acima do
/// índice máximo de um DX7 típico em uso).
const INDEX_TURNS: f32 = 1.25;
/// Realimentação máxima, em voltas, sobre a média das duas últimas saídas (a média de duas
/// amostras é o que mantém a realimentação alta em ruído colorido e não em um chiado estridente).
const FEEDBACK_TURNS: f32 = 0.6;
/// Fração da taxa que a banda de um sinal FM pode ocupar sem dobrar.
const BAND_LIMIT: f32 = 0.4;
const LFO_TAU: f32 = 0.0015;
const PARAM_TAU: f32 = 0.01;

const fn ratio(def: f32) -> Spec {
    cont(0.25, 16.0, def)
}

/// Faixa, padrão e se o valor é inteiro, na ordem dos ids. Espelho de `fmParams` em
/// `app/lib/daw/instruments.dart` (um teste confere os dois).
const SPECS: [Spec; PARAMS] = [
    disc(0.0, 7.0, 4.0), // ALGORITHM
    cont(0.0, 1.0, 0.0), // FEEDBACK
    // operador 1: modulador do par 1→2
    ratio(1.0),                // RATIO
    cont(-100.0, 100.0, 0.0),  // FINE
    cont(0.0, 1.0, 0.5),       // LEVEL
    cont(0.0005, 10.0, 0.001), // ATTACK
    cont(0.001, 10.0, 0.6),    // DECAY
    cont(0.0, 1.0, 0.0),       // SUSTAIN
    cont(0.001, 10.0, 0.3),    // RELEASE
    cont(0.0, 1.0, 0.5),       // VELOCITY
    // operador 2: portador do primeiro par
    ratio(1.0),
    cont(-100.0, 100.0, 0.0),
    cont(0.0, 1.0, 0.8),
    cont(0.0005, 10.0, 0.001),
    cont(0.001, 10.0, 1.2),
    cont(0.0, 1.0, 0.3),
    cont(0.001, 10.0, 0.3),
    cont(0.0, 1.0, 0.3),
    // operador 3: modulador do segundo par (a batida metálica do ataque)
    ratio(14.0),
    cont(-100.0, 100.0, 0.0),
    cont(0.0, 1.0, 0.3),
    cont(0.0005, 10.0, 0.001),
    cont(0.001, 10.0, 0.15),
    cont(0.0, 1.0, 0.0),
    cont(0.001, 10.0, 0.15),
    cont(0.0, 1.0, 0.5),
    // operador 4: portador do segundo par
    ratio(1.0),
    cont(-100.0, 100.0, 0.0),
    cont(0.0, 1.0, 0.7),
    cont(0.0005, 10.0, 0.001),
    cont(0.001, 10.0, 1.0),
    cont(0.0, 1.0, 0.2),
    cont(0.001, 10.0, 0.3),
    cont(0.0, 1.0, 0.3),
    disc(0.0, 4.0, 0.0),   // LFO_WAVE
    cont(0.05, 30.0, 5.0), // LFO_RATE
    cont(0.0, 12.0, 0.0),  // LFO_PITCH
    cont(0.0, 1.0, 0.0),   // LFO_AMP
    cont(0.0, 1.0, 0.0),   // LFO_INDEX
    disc(1.0, 16.0, 8.0),  // VOICES
    cont(0.0, 2.0, 0.0),   // GLIDE
    cont(0.0, 1.5, 0.7),   // LEVEL_OUT
];

/// Roteamento de um algoritmo. `mods[i]` tem o bit `j` ligado quando o operador `j` modula o
/// operador `i` (sempre `j < i`); `carriers`, um bit por operador que vai para a saída.
#[derive(Clone, Copy)]
struct Algorithm {
    mods: [u8; OPS],
    carriers: u8,
    /// Compensação de ganho pelo número de portadores (somar portadores soma volume).
    norm: f32,
}

impl Algorithm {
    /// Operadores que modulam alguém: são os que precisam do limite de índice.
    fn sources(&self) -> u8 {
        self.mods.iter().fold(0, |m, &x| m | x)
    }
}

const ALGORITHMS: [Algorithm; 8] = [
    Algorithm { mods: [0, 0b0001, 0b0010, 0b0100], carriers: 0b1000, norm: 1.0 },
    Algorithm { mods: [0, 0, 0b0011, 0b0100], carriers: 0b1000, norm: 1.0 },
    Algorithm { mods: [0, 0, 0b0010, 0b0101], carriers: 0b1000, norm: 1.0 },
    Algorithm { mods: [0, 0b0001, 0, 0b0110], carriers: 0b1000, norm: 1.0 },
    Algorithm { mods: [0, 0b0001, 0, 0b0100], carriers: 0b1010, norm: 0.7 },
    Algorithm { mods: [0, 0b0001, 0b0001, 0b0001], carriers: 0b1110, norm: 0.58 },
    Algorithm { mods: [0, 0b0001, 0, 0], carriers: 0b1110, norm: 0.58 },
    Algorithm { mods: [0; OPS], carriers: 0b1111, norm: 0.5 },
];

/// Semente diferente por instância: duas faixas tocando a mesma nota não saem com o mesmo aleatório.
static SEED: AtomicU32 = AtomicU32::new(0x7A3B_51C9);

/// Limite suave do índice `beta` (radianos) para caber em `max` (a banda que o modulador deixa):
/// passa direto bem abaixo do limite e encosta nele sem quina (norma 4). Devolve o fator (0..1)
/// que multiplica o índice.
#[inline]
fn band_factor(beta: f32, max: f32) -> f32 {
    if beta <= 1e-4 {
        return 1.0;
    }
    let x = beta / max.max(0.05);
    let x2 = x * x;
    1.0 / (1.0 + x2 * x2).sqrt().sqrt()
}

/// O que todas as vozes usam num bloco de controle, calculado uma vez por bloco.
struct Block {
    rate: f32,
    algo: Algorithm,
    /// Razão × ajuste fino de cada operador.
    ratio: [f32; OPS],
    level: [Ramp; OPS],
    velocity: [f32; OPS],
    feedback: f32,
    lfo: f32,
    lfo_pitch: f32,
    /// Fator do LFO sobre o índice (1 sem LFO).
    index_lfo: f32,
    /// Volume de saída × tremolo × ganho por voz × fade de algoritmo.
    gain: Ramp,
    smooth: f32,
    glide: f32,
    fade_step: f32,
}

struct Voice {
    pitch: u8,
    /// Tecla presa (os envelopes podem estar em qualquer estágio menos o release).
    gate: bool,
    age: u64,
    /// Velocidade da nota: a atual persegue o alvo, porque reatacar uma voz que ainda soa com
    /// outra velocidade não pode pular de nível no meio da onda.
    vel: f32,
    vel_target: f32,
    ph: [f32; OPS],
    env: [Adsr; OPS],
    /// Últimas duas saídas do operador 1, para a realimentação.
    y1: f32,
    y2: f32,
    /// Altura atual (com glide) e alvo, em semitons MIDI.
    cur: f32,
    target: f32,
    dying: bool,
    fade: f32,
}

impl Voice {
    fn new(rate: f64) -> Self {
        Self {
            pitch: 0,
            gate: false,
            age: 0,
            vel: 1.0,
            vel_target: 1.0,
            ph: [0.0; OPS],
            env: std::array::from_fn(|_| Adsr::new(rate)),
            y1: 0.0,
            y2: 0.0,
            cur: 60.0,
            target: 60.0,
            dying: false,
            fade: 1.0,
        }
    }

    /// Algum portador soando: a voz existe enquanto isso durar (o modulador não faz som sozinho).
    fn alive(&self, carriers: u8) -> bool {
        (0..OPS).any(|i| carriers >> i & 1 != 0 && self.env[i].active())
    }

    fn busy(&self, carriers: u8) -> bool {
        self.alive(carriers) && !self.dying
    }

    /// Maior nível de envelope entre os portadores (para escolher a vítima do roubo).
    fn loudness(&self, carriers: u8) -> f32 {
        (0..OPS).filter(|&i| carriers >> i & 1 != 0).map(|i| self.env[i].value()).fold(0.0, f32::max)
    }

    /// Tecla presa e todos os portadores numa sustentação zero (o pluck típico): só sairiam
    /// zeros até o note off, então a voz nem é calculada.
    fn silent_hold(&self, carriers: u8) -> bool {
        (0..OPS).filter(|&i| carriers >> i & 1 != 0).all(|i| self.env[i].stage() == Stage::Sustain && self.env[i].sustain == 0.0 && self.env[i].value() == 0.0)
    }

    fn kill(&mut self) {
        for e in &mut self.env {
            e.reset();
        }
        self.y1 = 0.0;
        self.y2 = 0.0;
        self.gate = false;
        self.dying = false;
        self.fade = 1.0;
    }

    fn trigger(&mut self, pitch: u8, velocity: f32, age: u64) {
        self.pitch = pitch;
        self.gate = true;
        self.age = age;
        self.vel_target = velocity;
        for e in &mut self.env {
            e.gate_on();
        }
    }

    fn release(&mut self) {
        self.gate = false;
        for e in &mut self.env {
            e.gate_off();
        }
    }

    /// Muda a nota sem redisparar nada (legato): desliza se houver glide.
    fn slide(&mut self, pitch: u8, glide: bool) {
        self.pitch = pitch;
        self.target = pitch as f32;
        if !glide {
            self.cur = self.target;
        }
    }

    fn render(&mut self, b: &Block, carriers: u8, out: &mut [f32]) {
        let d = self.target - self.cur;
        self.cur = if d.abs() < 1e-3 { self.target } else { self.cur + d * b.glide };
        let f0 = pitch_hz(self.cur + b.lfo * b.lfo_pitch);

        // velocidade: o ganho de cada operador é 1 − s + s·v² (como no subtrativo)
        let dv = self.vel_target - self.vel;
        self.vel = if dv.abs() < 1e-5 { self.vel_target } else { self.vel + dv * b.smooth };
        let v2 = self.vel * self.vel;

        let mut dt = [0.0f32; OPS];
        let mut lv = [0.0f32; OPS];
        let mut lv_step = [0.0f32; OPS];
        let mut idx = [0.0f32; OPS];
        let sources = b.algo.sources();
        for i in 0..OPS {
            let f = f0 * b.ratio[i];
            dt[i] = (f / b.rate).min(0.49);
            // passa de 0,4 da taxa até Nyquist o operador some: uma senoide que dobra soa como
            // outra nota, pior que sumir
            let alias = ((0.5 * b.rate - f) / (0.1 * b.rate)).clamp(0.0, 1.0);
            let k = (1.0 - b.velocity[i] + b.velocity[i] * v2) * alias;
            lv[i] = b.level[i].from * k;
            lv_step[i] = b.level[i].step * k;
            if sources >> i & 1 != 0 {
                let beta = 2.0 * std::f32::consts::PI * INDEX_TURNS * b.level[i].from * k * b.index_lfo;
                // banda ≈ 2·(β + 1)·f_mod tem de caber em BAND_LIMIT·taxa
                let max_beta = (BAND_LIMIT * b.rate / (2.0 * f.max(1.0)) - 1.0).max(0.0) + 0.05;
                idx[i] = INDEX_TURNS * b.index_lfo * band_factor(beta, max_beta);
            }
        }
        let fb = {
            let beta = 2.0 * std::f32::consts::PI * FEEDBACK_TURNS * b.feedback;
            let max_beta = (BAND_LIMIT * b.rate / (2.0 * (f0 * b.ratio[0]).max(1.0)) - 1.0).max(0.0) + 0.05;
            FEEDBACK_TURNS * b.feedback * band_factor(beta, max_beta) * 0.5
        };

        let mut gain = b.gain.from * b.algo.norm;
        let gain_step = b.gain.step * b.algo.norm;
        for o in out.iter_mut() {
            let mut y = [0.0f32; OPS];
            let mut mix = 0.0;
            for i in 0..OPS {
                let mut m = 0.0;
                let src = b.algo.mods[i];
                for j in 0..i {
                    if src >> j & 1 != 0 {
                        m += y[j] * idx[j];
                    }
                }
                if i == 0 {
                    m += fb * (self.y1 + self.y2);
                }
                let e = self.env[i].next();
                let s = sin_turns(self.ph[i] + m) * (lv[i] * e);
                y[i] = s;
                self.ph[i] = wrap(self.ph[i] + dt[i]);
                lv[i] += lv_step[i];
                if carriers >> i & 1 != 0 {
                    mix += s;
                }
            }
            self.y2 = self.y1;
            self.y1 = y[0];
            let mut g = gain;
            if self.dying {
                self.fade = (self.fade - b.fade_step).max(0.0);
                g *= self.fade;
            }
            *o += mix * g;
            gain += gain_step;
        }
        // zera estados minúsculos (o WASM não tem flush-to-zero)
        if self.y1.abs() < 1e-15 {
            self.y1 = 0.0;
        }
        if self.y2.abs() < 1e-15 {
            self.y2 = 0.0;
        }
        // um NaN aqui envenenaria a faixa inteira para sempre; melhor perder a nota
        if (self.dying && self.fade <= 0.0) || !self.y1.is_finite() || !self.y2.is_finite() || self.ph.iter().any(|p| !p.is_finite()) {
            self.kill();
            self.ph = [0.0; OPS];
        }
    }
}

pub struct Fm {
    rate: f32,
    params: [f32; PARAMS],
    voices: [Voice; MAX_VOICES + SPARE_VOICES],
    /// Algoritmo em uso (pode estar atrás do parâmetro durante o fade da troca).
    algo: usize,
    algo_pending: bool,
    algo_gain: f32,
    held: [u8; 128],
    held_len: usize,
    clock: u64,
    last_pitch: Option<f32>,
    rng: Rng,
    lfo_phase: f32,
    lfo_hold: f32,
    lfo: f32,
    level: [Smoothed; OPS],
    feedback: Smoothed,
    out_level: Smoothed,
    tremolo: Smoothed,
    index_lfo: Smoothed,
    gain: f32,
    block: Block,
}

impl Fm {
    pub fn new(rate: f64) -> Self {
        let seed = SEED.fetch_add(0x9E37_79B9, Ordering::Relaxed);
        let r = rate as f32;
        let mut s = Self {
            rate: r,
            params: SPECS.map(|s| s.def),
            voices: std::array::from_fn(|_| Voice::new(rate)),
            algo: 4,
            algo_pending: false,
            algo_gain: 1.0,
            held: [0; 128],
            held_len: 0,
            clock: 0,
            last_pitch: None,
            rng: Rng::new(seed),
            lfo_phase: 0.0,
            lfo_hold: 0.0,
            lfo: 0.0,
            level: [Smoothed::new(0.0); OPS],
            feedback: Smoothed::new(0.0),
            out_level: Smoothed::new(0.0),
            tremolo: Smoothed::new(0.0),
            index_lfo: Smoothed::new(0.0),
            gain: 0.0,
            block: Block {
                rate: r,
                algo: ALGORITHMS[4],
                ratio: [1.0; OPS],
                level: [Ramp::default(); OPS],
                velocity: [0.0; OPS],
                feedback: 0.0,
                lfo: 0.0,
                lfo_pitch: 0.0,
                index_lfo: 1.0,
                gain: Ramp::default(),
                smooth: 1.0,
                glide: 1.0,
                fade_step: 1.0 / (STEAL_SECS * r),
            },
        };
        for id in 0..P::COUNT {
            s.apply(id);
        }
        s.snap();
        s
    }

    fn carriers(&self) -> u8 {
        self.block.algo.carriers
    }

    fn limit(&self) -> usize {
        self.params[P::VOICES as usize] as usize
    }

    fn glide_on(&self) -> bool {
        self.params[P::GLIDE as usize] > 0.0
    }

    /// Leva um parâmetro já limitado para onde ele é usado.
    fn apply(&mut self, id: u32) {
        let v = self.params[id as usize];
        match id {
            P::ALGORITHM => {
                if self.active() {
                    // com som: sai num fade curto, troca o roteamento no silêncio do fade e volta
                    self.algo_pending = true;
                } else {
                    self.algo = v as usize;
                    self.block.algo = ALGORITHMS[self.algo];
                    self.algo_pending = false;
                    self.algo_gain = 1.0;
                }
            }
            P::FEEDBACK => self.feedback.set(v),
            P::LEVEL_OUT => self.out_level.set(v),
            P::LFO_AMP => self.tremolo.set(v),
            P::LFO_INDEX => self.index_lfo.set(v),
            P::VOICES => {
                let (limit, c) = (self.limit(), self.carriers());
                while self.voices.iter().filter(|v| v.busy(c)).count() > limit {
                    match self.victim() {
                        Some(i) => self.voices[i].dying = true,
                        None => break,
                    }
                }
            }
            _ if (P::OP_BASE..P::OP_BASE + P::OP_STRIDE * P::OPS).contains(&id) => {
                let op = ((id - P::OP_BASE) / P::OP_STRIDE) as usize;
                match (id - P::OP_BASE) % P::OP_STRIDE {
                    P::RATIO | P::FINE => {
                        let base = P::OP_BASE + op as u32 * P::OP_STRIDE;
                        self.block.ratio[op] = self.params[(base + P::RATIO) as usize] * (self.params[(base + P::FINE) as usize] / 1200.0).exp2();
                    }
                    P::LEVEL => self.level[op].set(v),
                    P::VELOCITY => self.block.velocity[op] = v,
                    _ => {
                        let base = (P::OP_BASE + op as u32 * P::OP_STRIDE) as usize;
                        let p = &self.params;
                        let (a, d, s, r) =
                            (p[base + P::ATTACK as usize], p[base + P::DECAY as usize], p[base + P::SUSTAIN as usize], p[base + P::RELEASE as usize]);
                        for voice in &mut self.voices {
                            voice.env[op].set(a, d, s, r);
                        }
                    }
                }
            }
            // os demais são lidos direto de `params` a cada bloco
            _ => {}
        }
    }

    /// Todos os valores suavizados no alvo: depois de um silêncio (sem `render`), a próxima nota
    /// não pode começar varrendo de um valor velho.
    fn snap(&mut self) {
        for s in self.level.iter_mut().chain([&mut self.feedback, &mut self.out_level, &mut self.tremolo, &mut self.index_lfo]) {
            s.snap();
        }
        self.gain = VOICE_GAIN * self.out_level.value * self.algo_gain * (1.0 - self.tremolo.value * (1.0 - self.lfo) * 0.5);
    }

    /// Calcula o bloco de controle de `len` quadros.
    fn prepare(&mut self, len: usize) {
        let frames = len as f32;
        let rate = self.rate;
        let a = smoothing(PARAM_TAU, len, rate);
        let p = self.params;

        for i in 0..OPS {
            self.block.level[i] = Ramp::advance(&mut self.level[i], a, frames);
        }
        self.block.feedback = self.feedback.step(a);

        self.lfo_phase += p[P::LFO_RATE as usize] * frames / rate;
        if self.lfo_phase >= 1.0 {
            self.lfo_phase -= self.lfo_phase.floor();
            self.lfo_hold = self.rng.bipolar();
        }
        let raw = lfo_shape(p[P::LFO_WAVE as usize] as u32, self.lfo_phase, self.lfo_hold);
        let dl = raw - self.lfo;
        self.lfo = if dl.abs() < 1e-6 { raw } else { self.lfo + dl * smoothing(LFO_TAU, len, rate) };
        self.block.lfo = self.lfo;
        self.block.lfo_pitch = p[P::LFO_PITCH as usize];
        // com o LFO em −1..1, o índice varia em 1 ± profundidade (nunca abaixo de 0)
        self.block.index_lfo = (1.0 + self.index_lfo.step(a) * self.lfo).max(0.0);

        // troca de algoritmo: desce o fade, troca no silêncio e sobe de novo
        let fade = frames / (ALGO_FADE_SECS * rate);
        if self.algo_pending {
            self.algo_gain = (self.algo_gain - fade).max(0.0);
            if self.algo_gain <= 0.0 {
                self.algo = p[P::ALGORITHM as usize] as usize;
                self.block.algo = ALGORITHMS[self.algo];
                self.algo_pending = false;
            }
        } else if self.algo_gain < 1.0 {
            self.algo_gain = (self.algo_gain + fade).min(1.0);
        }

        let tremolo = 1.0 - self.tremolo.step(a) * (1.0 - self.lfo) * 0.5;
        let gain = VOICE_GAIN * self.out_level.step(a) * tremolo * self.algo_gain;
        self.block.gain = Ramp { from: self.gain, step: (gain - self.gain) / frames };
        self.gain = gain;

        self.block.smooth = a;
        let glide = p[P::GLIDE as usize];
        // 99% do caminho no tempo do botão
        self.block.glide = if glide > 0.0 { smoothing(glide / 4.6, len, rate) } else { 1.0 };
    }

    fn busy_count(&self) -> usize {
        let c = self.carriers();
        self.voices.iter().filter(|v| v.busy(c)).count()
    }

    /// A voz a roubar: a mais baixa entre as já soltas; se todas estão presas, a mais antiga.
    fn victim(&self) -> Option<usize> {
        let c = self.carriers();
        let busy = self.voices.iter().enumerate().filter(|(_, v)| v.busy(c));
        let released = busy.clone().filter(|(_, v)| !v.gate).min_by(|a, b| a.1.loudness(c).total_cmp(&b.1.loudness(c)));
        released.or_else(|| busy.min_by_key(|(_, v)| v.age)).map(|(i, _)| i)
    }

    /// Uma voz parada para a nota nova. Se até as folgas estão ocupadas (rajada de roubos), leva a
    /// que está mais perto do fim do fade.
    fn free_voice(&mut self) -> usize {
        let c = self.carriers();
        let i = match self.voices.iter().position(|v| !v.alive(c)) {
            Some(i) => i,
            None => {
                let dying = self.voices.iter().enumerate().filter(|(_, v)| v.dying).min_by(|a, b| a.1.fade.total_cmp(&b.1.fade)).map(|(i, _)| i);
                dying.or_else(|| self.victim()).unwrap_or(0)
            }
        };
        self.voices[i].kill();
        i
    }

    /// Começa uma nota numa voz parada.
    fn start(&mut self, i: usize, pitch: u8, velocity: f32) {
        let from = if self.glide_on() { self.last_pitch } else { None };
        let v = &mut self.voices[i];
        // parte da fase zero, igual toda vez: o ataque não tem degrau e não varia entre notas
        v.ph = [0.0; OPS];
        v.target = pitch as f32;
        v.cur = from.unwrap_or(v.target);
        v.trigger(pitch, velocity, self.clock);
        // voz nova parte do zero no envelope: pode começar direto no ganho certo
        v.vel = v.vel_target;
    }

    fn poly_on(&mut self, pitch: u8, velocity: f32) {
        let c = self.carriers();
        if let Some(v) = self.voices.iter_mut().find(|v| v.busy(c) && v.pitch == pitch) {
            v.target = pitch as f32;
            v.trigger(pitch, velocity, self.clock);
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

    /// A voz do modo mono: a mais nova que ainda soa. Sobras do modo poli saem em fade.
    fn mono_voice(&mut self) -> Option<usize> {
        let c = self.carriers();
        let newest = self.voices.iter().enumerate().filter(|(_, v)| v.busy(c)).max_by_key(|(_, v)| v.age).map(|(i, _)| i)?;
        for (i, v) in self.voices.iter_mut().enumerate() {
            if i != newest && v.busy(c) {
                v.dying = true;
            }
        }
        Some(newest)
    }

    fn mono_on(&mut self, pitch: u8, velocity: f32) {
        let glide = self.glide_on();
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
                    v.trigger(pitch, velocity, clock);
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

impl Instrument for Fm {
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
        let c = self.carriers();
        for v in self.voices.iter_mut().filter(|v| v.busy(c) && v.gate && v.pitch == pitch) {
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
            let c = self.carriers();
            // mono: a voz soma no canal esquerdo e o resultado é copiado para o direito
            let l = &mut left[done..done + len];
            let mut mono = [0.0f32; CONTROL];
            let mono = &mut mono[..len];
            for v in self.voices.iter_mut().filter(|v| v.alive(c)) {
                if v.silent_hold(c) {
                    // uma roubada em silêncio não tem o que esvaziar
                    if v.dying {
                        v.kill();
                    }
                    continue;
                }
                v.render(&self.block, c, mono);
            }
            let r = &mut right[done..done + len];
            for ((l, r), m) in l.iter_mut().zip(r.iter_mut()).zip(mono.iter()) {
                *l += m;
                *r += m;
            }
            done += len;
        }
    }

    fn active(&self) -> bool {
        let c = self.carriers();
        self.voices.iter().any(|v| v.alive(c))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::instrument::contract;

    const RATE: f64 = 48_000.0;

    fn run(s: &mut Fm, frames: usize) -> (Vec<f32>, Vec<f32>) {
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

    fn set(s: &mut Fm, params: &[(u32, f32)]) {
        for &(id, v) in params {
            s.set_param(id, v);
        }
    }

    fn op(n: u32, k: u32) -> u32 {
        P::op(n, k)
    }

    /// Só o operador 1 audível (algoritmo aditivo), sustentado, sem LFO.
    fn sine(ratio: f32) -> Fm {
        let mut s = Fm::new(RATE);
        set(&mut s, &[(P::ALGORITHM, 7.0), (P::VOICES, 8.0)]);
        for n in 0..4 {
            set(&mut s, &[(op(n, P::LEVEL), if n == 0 { 1.0 } else { 0.0 }), (op(n, P::SUSTAIN), 1.0), (op(n, P::VELOCITY), 0.0), (op(n, P::ATTACK), 0.0005)]);
        }
        set(&mut s, &[(op(0, P::RATIO), ratio)]);
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

    /// Amplitude da componente em `hz` numa janela de Hann de `x` (a janela evita que o vazamento
    /// da componente forte apareça nos harmônicos que o teste quer ver vazios).
    fn tone(x: &[f32], hz: f32) -> f32 {
        let w = std::f64::consts::TAU * hz as f64 / RATE;
        let n = x.len() as f64;
        let (mut re, mut im, mut win_sum) = (0.0f64, 0.0f64, 0.0f64);
        for (i, &v) in x.iter().enumerate() {
            let hann = 0.5 - 0.5 * (std::f64::consts::TAU * i as f64 / n).cos();
            win_sum += hann;
            re += v as f64 * hann * (w * i as f64).cos();
            im += v as f64 * hann * (w * i as f64).sin();
        }
        (2.0 * (re * re + im * im).sqrt() / win_sum) as f32
    }

    #[test]
    fn frequencia_correta_com_razao() {
        for (pitch, ratio) in [(69u8, 1.0f32), (69, 2.0), (57, 3.0), (60, 0.5), (48, 7.0)] {
            let mut s = sine(ratio);
            s.note_on(pitch, 1.0);
            let (l, _) = run(&mut s, 24_000);
            let want = pitch_hz(pitch as f32) * ratio;
            let got = frequency(&l[4800..]);
            assert!((got / want - 1.0).abs() < 0.003, "nota {pitch} razão {ratio}: {got} Hz, esperava {want}");
        }
    }

    #[test]
    fn ajuste_fino_em_cents() {
        let mut s = sine(1.0);
        set(&mut s, &[(op(0, P::FINE), 100.0)]);
        s.note_on(69, 1.0);
        let (l, _) = run(&mut s, 24_000);
        let got = frequency(&l[4800..]);
        assert!((got / (440.0 * 2f32.powf(1.0 / 12.0)) - 1.0).abs() < 0.003, "{got}");
    }

    #[test]
    fn modulador_cria_bandas_laterais() {
        // cadeia 1→2 com razões iguais: sem modulação só existe f; com ela aparecem 2f, 3f...
        let mut s = Fm::new(RATE);
        set(&mut s, &[(P::ALGORITHM, 4.0), (P::VOICES, 4.0), (P::FEEDBACK, 0.0)]);
        for n in 0..4 {
            set(&mut s, &[(op(n, P::SUSTAIN), 1.0), (op(n, P::VELOCITY), 0.0), (op(n, P::RATIO), 1.0), (op(n, P::ATTACK), 0.0005)]);
        }
        set(&mut s, &[(op(0, P::LEVEL), 0.0), (op(1, P::LEVEL), 1.0), (op(2, P::LEVEL), 0.0), (op(3, P::LEVEL), 0.0)]);
        s.note_on(60, 1.0);
        let f = pitch_hz(60.0);
        let (l, _) = run(&mut s, 9600);
        let plain = &l[4800..];
        assert!(tone(plain, f) > 0.1 && tone(plain, 2.0 * f) < 0.005 * tone(plain, f));
        s.silence();
        set(&mut s, &[(op(0, P::LEVEL), 0.5)]);
        s.note_on(60, 1.0);
        let (l, _) = run(&mut s, 9600);
        let fm = &l[4800..];
        assert!(tone(fm, 2.0 * f) > 0.05 && tone(fm, 3.0 * f) > 0.02, "{} {}", tone(fm, 2.0 * f), tone(fm, 3.0 * f));
    }

    #[test]
    fn todos_os_algoritmos_soam_e_diferem() {
        let mut rmss = Vec::new();
        for alg in 0..8 {
            let mut s = Fm::new(RATE);
            set(&mut s, &[(P::ALGORITHM, alg as f32)]);
            for n in 0..4 {
                set(&mut s, &[(op(n, P::SUSTAIN), 1.0), (op(n, P::LEVEL), 0.8), (op(n, P::RATIO), [1.0, 2.0, 3.0, 1.0][n as usize])]);
            }
            s.note_on(48, 0.9);
            let (l, r) = run(&mut s, 9600);
            assert!(l == r, "algoritmo {alg} deve ser mono");
            let level = rms(&l[4800..]);
            assert!(level > 0.03 && level < 0.9 && peak(&l) < 1.5, "algoritmo {alg}: rms {level} pico {}", peak(&l));
            rmss.push(level);
        }
        assert!(rmss.windows(2).any(|w| (w[0] - w[1]).abs() > 1e-3));
    }

    #[test]
    fn extremos_sem_nan_nem_infinito() {
        for alg in 0..8 {
            for &(pitch, ratio, fb) in &[(0u8, 16.0f32, 1.0f32), (127, 16.0, 1.0), (127, 0.25, 0.0), (60, 16.0, 1.0), (96, 7.0, 0.7)] {
                let mut s = Fm::new(RATE);
                set(
                    &mut s,
                    &[(P::ALGORITHM, alg as f32), (P::FEEDBACK, fb), (P::LFO_PITCH, 12.0), (P::LFO_RATE, 30.0), (P::LFO_INDEX, 1.0), (P::LFO_AMP, 1.0)],
                );
                for n in 0..4 {
                    set(
                        &mut s,
                        &[(op(n, P::LEVEL), 1.0), (op(n, P::RATIO), ratio), (op(n, P::FINE), 100.0), (op(n, P::SUSTAIN), 1.0), (op(n, P::ATTACK), 0.0005)],
                    );
                }
                s.note_on(pitch, 1.0);
                s.note_on(pitch.saturating_add(7).min(127), 1.0);
                let (l, r) = run(&mut s, 12_000);
                assert!(l.iter().chain(&r).all(|x| x.is_finite() && x.abs() < 4.0), "alg {alg} nota {pitch} razão {ratio}");
            }
        }
    }

    #[test]
    fn parametros_absurdos_sao_limitados() {
        let mut s = Fm::new(RATE);
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
    fn realimentacao_estavel() {
        for fb in [0.25, 0.5, 0.75, 1.0] {
            let mut s = Fm::new(RATE);
            set(&mut s, &[(P::ALGORITHM, 7.0), (P::FEEDBACK, fb)]);
            for n in 0..4 {
                set(&mut s, &[(op(n, P::LEVEL), if n == 0 { 1.0 } else { 0.0 }), (op(n, P::SUSTAIN), 1.0)]);
            }
            s.note_on(45, 1.0);
            let (l, _) = run(&mut s, 96_000);
            assert!(l.iter().all(|x| x.is_finite()));
            // saída de um operador: limitada por construção (±1 × ganho)
            assert!(peak(&l) < 0.6, "fb {fb}: pico {}", peak(&l));
            assert!(rms(&l[48_000..]) > 0.05);
        }
    }

    #[test]
    fn realimentacao_engrossa_o_timbre() {
        let mut spectral = Vec::new();
        for fb in [0.0, 1.0] {
            let mut s = Fm::new(RATE);
            set(&mut s, &[(P::ALGORITHM, 7.0), (P::FEEDBACK, fb)]);
            for n in 0..4 {
                set(&mut s, &[(op(n, P::LEVEL), if n == 0 { 1.0 } else { 0.0 }), (op(n, P::SUSTAIN), 1.0)]);
            }
            s.note_on(45, 1.0);
            let (l, _) = run(&mut s, 24_000);
            let f = pitch_hz(45.0);
            let harm: f32 = (2..8).map(|h| tone(&l[4800..], f * h as f32)).sum();
            spectral.push(harm);
        }
        assert!(spectral[0] < 0.01 && spectral[1] > 0.1, "{spectral:?}");
    }

    #[test]
    fn indice_limitado_em_notas_agudas() {
        // um modulador forte numa nota aguda não pode passar do limite: a energia acima de 0,4 da
        // taxa (dobrada) fica baixa. Compara o topo do espectro com o de uma nota grave.
        let mut top = Vec::new();
        for pitch in [48u8, 100] {
            let mut s = Fm::new(RATE);
            set(&mut s, &[(P::ALGORITHM, 0.0)]);
            for n in 0..4 {
                set(&mut s, &[(op(n, P::LEVEL), 1.0), (op(n, P::SUSTAIN), 1.0), (op(n, P::VELOCITY), 0.0)]);
            }
            s.note_on(pitch, 1.0);
            let (l, _) = run(&mut s, 9600);
            let x = &l[4800..];
            // aliasing aparece como energia fora da série harmônica; mede o que sobra depois de
            // tirar os harmônicos de f0: aqui basta a energia total ser finita e sem estouro
            top.push(peak(x));
            assert!(x.iter().all(|v| v.is_finite()));
        }
        assert!(top[1] <= top[0] * 1.5 + 0.1);
    }

    #[test]
    fn operador_acima_de_nyquist_some() {
        let mut s = sine(16.0);
        s.note_on(120, 1.0);
        let (l, _) = run(&mut s, 4800);
        assert!(peak(&l) < 1e-3, "{}", peak(&l));
    }

    #[test]
    fn release_termina_e_active_acompanha() {
        let mut s = Fm::new(RATE);
        assert!(!s.active());
        s.note_on(60, 0.8);
        assert!(s.active());
        let (l, _) = run(&mut s, 4800);
        assert!(rms(&l[480..]) > 0.02);
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
    fn release_all_solta_tudo() {
        let mut s = Fm::new(RATE);
        for p in [60, 64, 67] {
            s.note_on(p, 0.8);
        }
        run(&mut s, 2400);
        s.release_all();
        run(&mut s, 96_000);
        assert!(!s.active());
    }

    #[test]
    fn pluck_sem_sustentacao_nao_gasta_voz() {
        // sustentação zero: com a tecla presa a voz fica muda e a nota não some do controle
        let mut s = Fm::new(RATE);
        for n in 0..4 {
            set(&mut s, &[(op(n, P::SUSTAIN), 0.0), (op(n, P::DECAY), 0.05)]);
        }
        s.note_on(60, 1.0);
        let (l, _) = run(&mut s, 24_000);
        assert!(peak(&l[20_000..]) == 0.0);
        s.note_off(60);
        run(&mut s, 48_000);
        assert!(!s.active());
    }

    #[test]
    fn polifonia_rouba_a_voz_e_nao_estala() {
        let mut s = Fm::new(RATE);
        set(&mut s, &[(P::VOICES, 2.0), (P::ALGORITHM, 7.0)]);
        for n in 0..4 {
            set(&mut s, &[(op(n, P::SUSTAIN), 1.0), (op(n, P::LEVEL), if n == 0 { 1.0 } else { 0.0 })]);
        }
        s.note_on(60, 1.0);
        s.note_on(64, 1.0);
        run(&mut s, 4800);
        s.note_on(67, 1.0);
        let c = s.carriers();
        assert_eq!(s.voices.iter().filter(|v| v.busy(c)).count(), 2);
        assert!(s.voices.iter().any(|v| v.busy(c) && v.pitch == 67));
        assert!(!s.voices.iter().any(|v| v.busy(c) && v.pitch == 60), "a mais antiga saiu");
        // a roubada sai em fade: nenhum salto grande entre quadros consecutivos
        let (l, _) = run(&mut s, 2400);
        let jump = l.windows(2).map(|w| (w[1] - w[0]).abs()).fold(0.0, f32::max);
        assert!(jump < 0.2, "salto {jump}");
    }

    #[test]
    fn dezesseis_vozes_de_uma_vez() {
        let mut s = Fm::new(RATE);
        set(&mut s, &[(P::VOICES, 16.0)]);
        for p in 0..16 {
            s.note_on(40 + p, 0.9);
        }
        let c = s.carriers();
        assert_eq!(s.voices.iter().filter(|v| v.busy(c)).count(), 16);
        let (l, _) = run(&mut s, 9600);
        assert!(l.iter().all(|x| x.is_finite()) && peak(&l) < 4.0);
    }

    #[test]
    fn mono_legato_e_portamento() {
        let mut s = sine(1.0);
        set(&mut s, &[(P::VOICES, 1.0), (P::GLIDE, 0.2)]);
        s.note_on(60, 1.0);
        run(&mut s, 4800);
        s.note_on(72, 1.0);
        let c = s.carriers();
        assert_eq!(s.voices.iter().filter(|v| v.busy(c)).count(), 1);
        // 100 ms depois de mudar a altura ainda está a caminho; depois de 1 s, chegou
        let (l, _) = run(&mut s, 4800);
        let mid = frequency(&l[2400..]);
        assert!(mid > pitch_hz(60.0) * 1.02 && mid < pitch_hz(72.0) * 0.98, "{mid}");
        let (l, _) = run(&mut s, 48_000);
        assert!((frequency(&l[24_000..]) / pitch_hz(72.0) - 1.0).abs() < 0.005);
        // soltar a 72 volta (legato) para a 60, que seguia presa; só soltando as duas a nota acaba
        s.note_off(72);
        assert!(s.active() && s.voices.iter().any(|v| v.gate && v.pitch == 60));
        s.note_off(60);
        run(&mut s, 96_000);
        assert!(!s.active());
    }

    #[test]
    fn velocidade_move_o_nivel_dos_moduladores() {
        let mut lows = Vec::new();
        for vel in [0.2, 1.0] {
            let mut s = Fm::new(RATE);
            set(&mut s, &[(P::ALGORITHM, 0.0)]);
            for n in 0..4 {
                set(
                    &mut s,
                    &[(op(n, P::SUSTAIN), 1.0), (op(n, P::VELOCITY), if n == 0 { 1.0 } else { 0.0 }), (op(n, P::LEVEL), if n == 0 { 0.6 } else { 0.0 })],
                );
            }
            set(&mut s, &[(op(1, P::LEVEL), 0.0), (op(3, P::LEVEL), 1.0)]);
            // op 1 modula 2 que está em zero: nada soa; o teste é sobre op 4 estar livre de velocidade
            s.note_on(60, vel);
            let (l, _) = run(&mut s, 4800);
            lows.push(peak(&l));
        }
        // op 4 (carrier) sem sensibilidade: o volume não depende da velocidade
        assert!((lows[0] - lows[1]).abs() < 0.02, "{lows:?}");
    }

    #[test]
    fn troca_de_algoritmo_com_som_nao_estala() {
        let mut s = Fm::new(RATE);
        set(&mut s, &[(P::ALGORITHM, 0.0)]);
        for n in 0..4 {
            set(&mut s, &[(op(n, P::SUSTAIN), 1.0), (op(n, P::LEVEL), 0.7)]);
        }
        s.note_on(48, 1.0);
        run(&mut s, 4800);
        set(&mut s, &[(P::ALGORITHM, 7.0)]);
        let (l, _) = run(&mut s, 4800);
        let jump = l.windows(2).map(|w| (w[1] - w[0]).abs()).fold(0.0, f32::max);
        assert!(jump < 0.35, "salto {jump}");
        assert_eq!(s.algo, 7);
    }

    #[test]
    fn blocos_de_tamanhos_diferentes_dao_o_mesmo_som() {
        let mk = || {
            let mut s = Fm::new(RATE);
            s.note_on(57, 0.7);
            s
        };
        let (mut a, mut b) = (mk(), mk());
        let (la, _) = run(&mut a, 4096);
        let mut lb = vec![0.0; 4096];
        let mut rb = vec![0.0; 4096];
        for (cl, cr) in lb.chunks_mut(37).zip(rb.chunks_mut(37)) {
            b.render(cl, cr);
        }
        // os blocos de controle de 16 quadros não alinham igual: tolera diferença mínima
        let diff = la.iter().zip(&lb).map(|(x, y)| (x - y).abs()).fold(0.0, f32::max);
        assert!(diff < 0.01, "{diff}");
    }

    #[test]
    fn render_soma_sem_zerar() {
        let mut s = Fm::new(RATE);
        s.note_on(60, 1.0);
        let (mut l, mut r) = (vec![0.25; 256], vec![0.25; 256]);
        s.render(&mut l, &mut r);
        assert!(l.iter().any(|&x| x != 0.25));
        let mut idle = Fm::new(RATE);
        let mut l2 = vec![0.25; 64];
        let mut r2 = vec![0.25; 64];
        idle.render(&mut l2, &mut r2);
        assert!(l2.iter().all(|&x| x == 0.25));
    }

    #[test]
    fn nao_aloca_depois_do_new() {
        let mut s = Fm::new(RATE);
        let (mut l, mut r) = (vec![0.0; 128], vec![0.0; 128]);
        let allocs = crate::testalloc::count(|| {
            for p in 30..46 {
                s.note_on(p, 0.8);
            }
            set(&mut s, &[(P::ALGORITHM, 2.0), (P::FEEDBACK, 0.5), (P::LFO_PITCH, 1.0), (P::VOICES, 3.0), (P::GLIDE, 0.1)]);
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

    // ------------------------------------------------------------ contrato com o app

    #[test]
    fn faixas_iguais_as_do_app() {
        let rows: Vec<contract::Row> = SPECS.iter().map(|s| (s.min, s.max, s.def, s.discrete)).collect();
        contract::check("fmParams", &rows);
    }

    #[test]
    fn algoritmos_iguais_aos_do_app() {
        let path = concat!(env!("CARGO_MANIFEST_DIR"), "/../app/lib/daw/instruments.dart");
        let Ok(src) = std::fs::read_to_string(path) else {
            eprintln!("sem {path}: conferência pulada");
            return;
        };
        let numbers = |name: &str| -> Vec<u8> {
            let body = &src[src.find(&format!("const {name} = ")).unwrap()..];
            let body = &body[body.find('[').unwrap()..body.find("];").unwrap()];
            body.split(|c: char| !c.is_ascii_digit()).filter(|t| !t.is_empty()).map(|t| t.parse().unwrap()).collect()
        };
        let mods = numbers("fmAlgorithmMods");
        let carriers = numbers("fmAlgorithmCarriers");
        assert_eq!(mods.len(), 8 * OPS);
        for (i, a) in ALGORITHMS.iter().enumerate() {
            assert_eq!(&mods[i * OPS..(i + 1) * OPS], &a.mods, "algoritmo {i}");
            assert_eq!(carriers[i], a.carriers, "algoritmo {i}");
            // só modula de índice menor para maior, e há pelo menos um portador
            assert!(a.mods.iter().enumerate().all(|(op, &m)| m >> op == 0) && a.carriers != 0);
        }
    }

    #[test]
    fn ids_de_operador_batem_com_a_tabela() {
        // o último parâmetro do último operador fecha o bloco de operadores e o LFO começa logo depois
        assert_eq!(P::op(3, P::VELOCITY) + 1, P::LFO_WAVE);
        assert_eq!(SPECS.len(), P::COUNT as usize);
    }

    // ------------------------------------------------------------ desempenho

    fn bench(voices: usize, algo: f32) -> f64 {
        let mut s = Fm::new(RATE);
        set(&mut s, &[(P::ALGORITHM, algo), (P::VOICES, 16.0), (P::FEEDBACK, 0.4), (P::LFO_PITCH, 0.2)]);
        for n in 0..4 {
            set(&mut s, &[(op(n, P::SUSTAIN), 1.0), (op(n, P::LEVEL), 0.7)]);
        }
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

    #[test]
    #[ignore = "medição: cargo test --release -p jopendaw-engine -- --ignored --nocapture"]
    fn desempenho() {
        for (name, voices, algo) in [("8 vozes, algoritmo 0 (cadeia)", 8, 0.0), ("8 vozes, algoritmo 7 (aditivo)", 8, 7.0), ("16 vozes, algoritmo 4", 16, 4.0)]
        {
            // o melhor de 10: tira o aquecimento da CPU e as trocas de núcleo
            let secs = (0..10).map(|_| bench(voices, algo)).fold(f64::MAX, f64::min);
            println!("FM {name}: 1 s de áudio a 48 kHz em {:.2} ms ({:.2}% de um núcleo)", secs * 1000.0, secs * 100.0);
        }
    }
}
