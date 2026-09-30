//! Sintetizador subtrativo (faixa do tipo 1).
//!
//! Por voz: dois osciladores com anti-aliasing (serra e pulso por polyBLEP, triângulo por
//! polyBLAMP, senoide) em uníssono de até 7 cópias espalhadas na afinação e no estéreo, um sub
//! (senoide uma oitava abaixo) e ruído branco; saturação opcional; um SVF de 12 dB/oit por canal;
//! envelopes de amplitude e de filtro. Um LFO global modula afinação, corte e volume.
//!
//! O trabalho anda em blocos de controle de até 16 quadros: glide, LFO, corte e coeficientes são
//! calculados uma vez por bloco; osciladores, envelopes e filtro andam por quadro, e todo ganho
//! que muda dentro do bloco é interpolado quadro a quadro (nada de zipper).
//!
//! As vozes são 16 mais 4 de folga: a voz roubada sai num fade de 5 ms numa das folgas enquanto a
//! nota nova já começa, em vez de cortar o som no meio da onda.

use std::sync::atomic::{AtomicU32, Ordering};

use crate::dsp::{Adsr, FilterMode, Rng, Smoothed, Stage, Svf, fast_tanh, poly_blamp, poly_blep, sin_turns, smoothing};
use crate::instrument::{Instrument, pitch_hz, synth_param as P};
use crate::pan_gains;

const MAX_VOICES: usize = 16;
const SPARE_VOICES: usize = 4;
const MAX_UNISON: usize = 7;
const CONTROL: usize = 16;
const PARAMS: usize = P::COUNT as usize;

/// Ganho por voz: uma nota fica perto de −10 dBFS e um acorde ainda cabe sem estourar.
const VOICE_GAIN: f32 = 0.5;
/// Fade da voz roubada.
const STEAL_SECS: f32 = 0.005;
/// Maior incremento de fase por quadro. Acima disso a nota já passou de Nyquist e só sobraria
/// aliasing; o limite também impede as janelas do polyBLEP de se sobreporem.
const MAX_DT: f32 = 0.45;
/// Constante de tempo da suavização de parâmetros.
const PARAM_TAU: f32 = 0.01;
/// Um pouco de inércia no LFO: a quadrada e o aleatório no volume não estalam.
const LFO_TAU: f32 = 0.0015;
/// Q com a ressonância no máximo; no mínimo é 0,5 (amortecimento crítico, sem pico).
const MAX_Q: f32 = 30.0;
/// Limitador de ressonância: quando o passa-banda passa deste nível, o amortecimento cresce com o
/// excesso. Abaixo dele o filtro é linear; acima, o pico ressonante satura suave (como num
/// analógico) em vez de subir 30 dB e estourar a mixagem.
const RES_LIMIT_LEVEL: f32 = 1.5;
const RES_LIMIT_DEPTH: f32 = 0.5;
const RES_LIMIT_TAU: f32 = 0.03;

/// Faixa, padrão e se o valor é inteiro, na ordem dos ids. Espelho de `synthParams` em
/// `app/lib/daw/instruments.dart` (um teste confere os dois).
#[derive(Clone, Copy)]
pub(crate) struct Spec {
    pub(crate) min: f32,
    pub(crate) max: f32,
    pub(crate) def: f32,
    pub(crate) discrete: bool,
}

pub(crate) const fn cont(min: f32, max: f32, def: f32) -> Spec {
    Spec { min, max, def, discrete: false }
}

pub(crate) const fn disc(min: f32, max: f32, def: f32) -> Spec {
    Spec { min, max, def, discrete: true }
}

const SPECS: [Spec; PARAMS] = [
    disc(0.0, 3.0, 0.0),         // OSC1_WAVE
    cont(0.0, 1.0, 0.8),         // OSC1_LEVEL
    cont(0.05, 0.95, 0.5),       // PULSE_WIDTH
    disc(0.0, 3.0, 0.0),         // OSC2_WAVE
    cont(0.0, 1.0, 0.5),         // OSC2_LEVEL
    disc(-24.0, 24.0, 0.0),      // OSC2_SEMI
    cont(-100.0, 100.0, 7.0),    // OSC2_DETUNE
    cont(0.0, 1.0, 0.0),         // SUB_LEVEL
    cont(0.0, 1.0, 0.0),         // NOISE_LEVEL
    disc(1.0, 7.0, 1.0),         // UNISON
    cont(0.0, 100.0, 20.0),      // UNISON_DETUNE
    cont(0.0, 1.0, 0.5),         // UNISON_SPREAD
    disc(0.0, 2.0, 0.0),         // FILTER_TYPE
    cont(20.0, 20000.0, 2400.0), // CUTOFF
    cont(0.0, 1.0, 0.2),         // RESONANCE
    cont(-1.0, 1.0, 0.3),        // FILTER_ENV
    cont(0.0, 1.0, 0.5),         // KEYTRACK
    cont(0.0005, 10.0, 0.005),   // AMP_ATTACK
    cont(0.001, 10.0, 0.3),      // AMP_DECAY
    cont(0.0, 1.0, 0.7),         // AMP_SUSTAIN
    cont(0.001, 10.0, 0.25),     // AMP_RELEASE
    cont(0.0005, 10.0, 0.005),   // FLT_ATTACK
    cont(0.001, 10.0, 0.4),      // FLT_DECAY
    cont(0.0, 1.0, 0.2),         // FLT_SUSTAIN
    cont(0.001, 10.0, 0.3),      // FLT_RELEASE
    disc(0.0, 4.0, 0.0),         // LFO_WAVE
    cont(0.05, 30.0, 5.0),       // LFO_RATE
    cont(0.0, 12.0, 0.0),        // LFO_PITCH
    cont(0.0, 4.0, 0.0),         // LFO_CUTOFF
    cont(0.0, 1.0, 0.0),         // LFO_AMP
    cont(0.0, 2.0, 0.0),         // GLIDE
    disc(1.0, 16.0, 8.0),        // VOICES
    cont(0.0, 1.0, 0.7),         // VELOCITY
    cont(0.0, 1.5, 0.7),         // LEVEL
    cont(0.0, 1.0, 0.0),         // DRIVE
];

/// Semente diferente por instância: duas faixas tocando a mesma nota não saem com as mesmas fases.
static SEED: AtomicU32 = AtomicU32::new(0x2545_F491);

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Wave {
    Saw,
    Pulse,
    Triangle,
    Sine,
}

impl Wave {
    fn from_param(v: f32) -> Self {
        match v as i32 {
            0 => Wave::Saw,
            1 => Wave::Pulse,
            2 => Wave::Triangle,
            _ => Wave::Sine,
        }
    }

    /// Fase em que a onda cruza o zero: é de onde a nota parte quando não há uníssono, para o
    /// ataque ser igual toda vez e não começar num degrau.
    fn zero_phase(self) -> f32 {
        match self {
            Wave::Saw => 0.5,
            Wave::Triangle => 0.25,
            Wave::Pulse | Wave::Sine => 0.0,
        }
    }
}

/// Um quadro de oscilador com anti-aliasing. `p` é a fase em [0, 1), `dt` o incremento por quadro
/// (< 0,5) e `pw` a largura do pulso.
#[inline(always)]
fn osc(wave: Wave, p: f32, dt: f32, pw: f32) -> f32 {
    match wave {
        Wave::Saw => 2.0 * p - 1.0 - poly_blep(p, dt),
        Wave::Pulse => {
            let mut t = p - pw;
            if t < 0.0 {
                t += 1.0;
            }
            let naive = if p < pw { 1.0 } else { -1.0 };
            // o pulso estreito tem média longe de zero; sem tirar o DC, o envelope o transformaria
            // num baque grave no ataque e na soltura
            naive + poly_blep(p, dt) - poly_blep(t, dt) - (2.0 * pw - 1.0)
        }
        Wave::Triangle => {
            // quinas em 0 (pico, a inclinação cai 8·dt por quadro) e em ½ (vale, sobe 8·dt)
            let mut t = p + 0.5;
            if t >= 1.0 {
                t -= 1.0;
            }
            4.0 * (p - 0.5).abs() - 1.0 + 8.0 * dt * (poly_blamp(t, dt) - poly_blamp(p, dt))
        }
        Wave::Sine => sin_turns(p),
    }
}

#[inline(always)]
pub(crate) fn wrap(p: f32) -> f32 {
    if p >= 1.0 { p - 1.0 } else { p }
}

pub(crate) fn lfo_shape(wave: u32, p: f32, hold: f32) -> f32 {
    match wave {
        0 => sin_turns(p),
        1 => {
            // começa no zero subindo, como a senoide
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

/// Um valor que vai de `from` a `from + step * n` ao longo do bloco.
#[derive(Clone, Copy, Debug, Default)]
pub(crate) struct Ramp {
    pub(crate) from: f32,
    pub(crate) step: f32,
}

impl Ramp {
    pub(crate) fn advance(s: &mut Smoothed, a: f32, frames: f32) -> Self {
        let from = s.value;
        Self { from, step: (s.step(a) - from) / frames }
    }

    pub(crate) fn on(&self) -> bool {
        self.from != 0.0 || self.step != 0.0
    }
}

/// O que todas as vozes usam num bloco de controle, calculado uma vez por bloco.
struct Block {
    rate: f32,
    wave1: Wave,
    wave2: Wave,
    pw: f32,
    osc1: Ramp,
    osc2: Ramp,
    sub: Ramp,
    noise: Ramp,
    /// Volume de saída × tremolo × ganho por voz.
    gain: Ramp,
    unison: usize,
    uni_ratio: [f32; MAX_UNISON],
    /// Ganhos de pan de cada cópia do uníssono, já com a normalização 1/√n.
    pan_l: [f32; MAX_UNISON],
    pan_r: [f32; MAX_UNISON],
    osc2_ratio: f32,
    mode: FilterMode,
    /// Corte em log2(Hz).
    cutoff: f32,
    max_cutoff: f32,
    k: f32,
    filter_env: f32,
    keytrack: f32,
    lfo: f32,
    lfo_pitch: f32,
    lfo_cutoff: f32,
    /// Mistura da saturação (0 = desligada), ganho de entrada e compensação.
    drive: f32,
    drive_pre: f32,
    drive_comp: f32,
    /// Fração do caminho que a suavização de parâmetros anda neste bloco.
    smooth: f32,
    /// Fração do caminho do glide neste bloco (1 = sem glide).
    glide: f32,
    res_release: f32,
    fade_step: f32,
}

#[derive(Clone, Copy, Debug, Default)]
struct Osc {
    ph1: f32,
    ph2: f32,
    dt1: f32,
    dt2: f32,
    pan_l: f32,
    pan_r: f32,
}

struct Voice {
    pitch: u8,
    /// Tecla presa (o envelope pode estar em qualquer estágio menos o release).
    gate: bool,
    age: u64,
    /// Ganho da velocidade: o atual persegue o alvo, porque redisparar uma voz que ainda soa com
    /// outra velocidade não pode pular de volume no meio da onda.
    vel_gain: f32,
    vel_target: f32,
    /// Quanto do envelope do filtro a velocidade deixa passar.
    env_depth: f32,
    amp: Adsr,
    flt: Adsr,
    /// Altura atual (com glide) e alvo, em semitons MIDI.
    cur: f32,
    target: f32,
    osc: [Osc; MAX_UNISON],
    sub: f32,
    fl: Svf,
    fr: Svf,
    /// Nível recente do passa-banda por canal, para o limitador de ressonância.
    res_l: f32,
    res_r: f32,
    /// Voz roubada saindo em fade; `fade` cai de 1 a 0.
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
            osc: [Osc::default(); MAX_UNISON],
            sub: 0.0,
            fl: Svf::default(),
            fr: Svf::default(),
            res_l: 0.0,
            res_r: 0.0,
            dying: false,
            fade: 1.0,
        }
    }

    /// Soando e não saindo em fade: é o que conta na polifonia.
    fn busy(&self) -> bool {
        self.amp.active() && !self.dying
    }

    /// Tecla presa num envelope que já chegou a uma sustentação zero (o pluck típico): a voz só
    /// produziria zeros até o note off, então nem é calculada. Se a sustentação subir, volta a
    /// soar dali, com o envelope seguindo o nível novo.
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

    /// (Re)dispara os envelopes a partir de onde estão, sem estalo.
    fn trigger(&mut self, pitch: u8, velocity: f32, sensitivity: f32, age: u64) {
        self.pitch = pitch;
        self.gate = true;
        self.age = age;
        // quadrática: meia velocidade com sensibilidade total dá −12 dB, perto do que o ouvido espera
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

    /// Muda a nota sem redisparar nada (legato): desliza se houver glide.
    fn slide(&mut self, pitch: u8, glide: bool) {
        self.pitch = pitch;
        self.target = pitch as f32;
        if !glide {
            self.cur = self.target;
        }
    }

    fn render(&mut self, b: &Block, rng: &mut Rng, out_l: &mut [f32], out_r: &mut [f32]) {
        let d = self.target - self.cur;
        self.cur = if d.abs() < 1e-3 { self.target } else { self.cur + d * b.glide };

        let dt = (pitch_hz(self.cur + b.lfo * b.lfo_pitch) / b.rate).min(MAX_DT);
        let dt2 = dt * b.osc2_ratio;
        let dt_sub = dt * 0.5;
        let uni = b.unison;
        for (u, o) in self.osc[..uni].iter_mut().enumerate() {
            o.dt1 = (dt * b.uni_ratio[u]).min(MAX_DT);
            o.dt2 = (dt2 * b.uni_ratio[u]).min(MAX_DT);
            o.pan_l = b.pan_l[u];
            o.pan_r = b.pan_r[u];
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
            for o in &mut self.osc[..uni] {
                let mut x = 0.0;
                if on1 {
                    x += osc(b.wave1, o.ph1, o.dt1, b.pw) * lv1;
                    o.ph1 = wrap(o.ph1 + o.dt1);
                }
                if on2 {
                    x += osc(b.wave2, o.ph2, o.dt2, b.pw) * lv2;
                    o.ph2 = wrap(o.ph2 + o.dt2);
                }
                l += x * o.pan_l;
                r += x * o.pan_r;
            }
            // sub e ruído ficam no centro e fora do uníssono: o grave continua firme e mono
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
            if b.drive > 0.0 {
                l += (fast_tanh(l * b.drive_pre) * b.drive_comp - l) * b.drive;
                r += (fast_tanh(r * b.drive_pre) * b.drive_comp - r) * b.drive;
            }
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

pub struct Synth {
    rate: f32,
    params: [f32; PARAMS],
    voices: [Voice; MAX_VOICES + SPARE_VOICES],
    /// Teclas presas, da mais antiga para a mais nova (o modo mono volta para a anterior).
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
    sub: Smoothed,
    noise: Smoothed,
    pw: Smoothed,
    cutoff: Smoothed,
    resonance: Smoothed,
    drive: Smoothed,
    level: Smoothed,
    tremolo: Smoothed,
    spread: Smoothed,
    gain: f32,
    pans_dirty: bool,
    block: Block,
}

impl Synth {
    pub fn new(rate: f64) -> Self {
        let seed = SEED.fetch_add(0x9E37_79B9, Ordering::Relaxed);
        let r = rate as f32;
        let mut s = Self {
            rate: r,
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
            sub: Smoothed::new(0.0),
            noise: Smoothed::new(0.0),
            pw: Smoothed::new(0.5),
            cutoff: Smoothed::new(0.0),
            resonance: Smoothed::new(0.0),
            drive: Smoothed::new(0.0),
            level: Smoothed::new(0.0),
            tremolo: Smoothed::new(0.0),
            spread: Smoothed::new(0.0),
            gain: 0.0,
            pans_dirty: true,
            block: Block {
                rate: r,
                wave1: Wave::Saw,
                wave2: Wave::Saw,
                pw: 0.5,
                osc1: Ramp::default(),
                osc2: Ramp::default(),
                sub: Ramp::default(),
                noise: Ramp::default(),
                gain: Ramp::default(),
                unison: 1,
                uni_ratio: [1.0; MAX_UNISON],
                pan_l: [1.0; MAX_UNISON],
                pan_r: [1.0; MAX_UNISON],
                osc2_ratio: 1.0,
                mode: FilterMode::LowPass,
                cutoff: 11.0,
                max_cutoff: 0.45 * r,
                k: 2.0,
                filter_env: 0.0,
                keytrack: 0.0,
                lfo: 0.0,
                lfo_pitch: 0.0,
                lfo_cutoff: 0.0,
                drive: 0.0,
                drive_pre: 1.0,
                drive_comp: 1.0,
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

    /// Leva um parâmetro já limitado para onde ele é usado.
    fn apply(&mut self, id: u32) {
        let v = self.params[id as usize];
        let p = &self.params;
        match id {
            P::OSC1_LEVEL => self.osc1.set(v),
            P::OSC2_LEVEL => self.osc2.set(v),
            P::SUB_LEVEL => self.sub.set(v),
            P::NOISE_LEVEL => self.noise.set(v),
            P::PULSE_WIDTH => self.pw.set(v),
            P::CUTOFF => self.cutoff.set(v.log2()),
            P::RESONANCE => self.resonance.set(v),
            P::DRIVE => self.drive.set(v),
            P::LEVEL => self.level.set(v),
            P::LFO_AMP => self.tremolo.set(v),
            P::UNISON_SPREAD => self.spread.set(v),
            P::OSC2_SEMI | P::OSC2_DETUNE => {
                self.block.osc2_ratio = ((p[P::OSC2_SEMI as usize] + p[P::OSC2_DETUNE as usize] / 100.0) / 12.0).exp2();
            }
            P::UNISON | P::UNISON_DETUNE => {
                let n = self.unison();
                let width = p[P::UNISON_DETUNE as usize];
                for (u, ratio) in self.block.uni_ratio.iter_mut().enumerate() {
                    // espalhamento simétrico: as cópias vão de −width/2 a +width/2 cents
                    let cents = unison_position(u, n) * width * 0.5;
                    *ratio = (cents / 1200.0).exp2();
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
                // polifonia menor que o que está soando: as vozes a mais saem em fade
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

    /// Todos os valores suavizados no alvo: depois de um silêncio (sem `render`), a próxima nota
    /// não pode começar varrendo de um valor velho.
    fn snap(&mut self) {
        for s in [
            &mut self.osc1,
            &mut self.osc2,
            &mut self.sub,
            &mut self.noise,
            &mut self.pw,
            &mut self.cutoff,
            &mut self.resonance,
            &mut self.drive,
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

    /// Calcula o bloco de controle de `len` quadros.
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
        b.pw = self.pw.step(a);
        b.wave1 = Wave::from_param(p[P::OSC1_WAVE as usize]);
        b.wave2 = Wave::from_param(p[P::OSC2_WAVE as usize]);

        b.mode = match p[P::FILTER_TYPE as usize] as i32 {
            1 => FilterMode::HighPass,
            2 => FilterMode::BandPass,
            _ => FilterMode::LowPass,
        };
        b.cutoff = self.cutoff.step(a);
        // Q de 0,5 a MAX_Q em escala exponencial: o meio do botão já é bem ressonante
        b.k = 2.0 * (-self.resonance.step(a) * (2.0 * MAX_Q).ln()).exp();
        b.filter_env = p[P::FILTER_ENV as usize];
        b.keytrack = p[P::KEYTRACK as usize];

        let d = self.drive.step(a);
        // até +24 dB na entrada; a compensação segura o volume quando a onda vira quase quadrada.
        // Os primeiros 12% do botão fazem a transição do sinal limpo para o saturado, sem degrau.
        b.drive = (d * 8.0).min(1.0);
        b.drive_pre = (4.0 * d).exp2();
        b.drive_comp = 0.6 + 0.4 / b.drive_pre;

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
        // 99% do caminho no tempo do botão
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

    /// Uma voz parada para a nota nova. Se até as folgas estão ocupadas (rajada de roubos), leva a
    /// que está mais perto do fim do fade.
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

    /// Começa uma nota numa voz parada.
    fn start(&mut self, i: usize, pitch: u8, velocity: f32) {
        let from = if self.glide_on() { self.last_pitch } else { None };
        let unison = self.unison();
        // de `params`, não do bloco: parado, o bloco não é recalculado
        let z1 = Wave::from_param(self.params[P::OSC1_WAVE as usize]).zero_phase();
        let z2 = Wave::from_param(self.params[P::OSC2_WAVE as usize]).zero_phase();
        let sensitivity = self.params[P::VELOCITY as usize];
        let v = &mut self.voices[i];
        for (u, o) in v.osc.iter_mut().enumerate() {
            // uma cópia só: parte do zero, igual toda vez; no uníssono, fases aleatórias (as
            // cópias em fase soariam como uma só, mais alta, até se desencontrarem)
            if unison == 1 && u == 0 {
                o.ph1 = z1;
                o.ph2 = z2;
            } else {
                o.ph1 = self.rng.unit();
                o.ph2 = self.rng.unit();
            }
        }
        v.sub = 0.0;
        v.target = pitch as f32;
        v.cur = from.unwrap_or(v.target);
        v.trigger(pitch, velocity, sensitivity, self.clock);
        // voz nova parte do zero no envelope: pode começar direto no ganho certo
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

    /// A voz do modo mono: a mais nova que ainda soa. Sobras do modo poli saem em fade.
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

/// Posição de uma cópia do uníssono em −1..1 (simétrica; uma cópia só fica no centro).
pub(crate) fn unison_position(u: usize, n: usize) -> f32 {
    if n > 1 { (u.min(n - 1) as f32 / (n - 1) as f32) * 2.0 - 1.0 } else { 0.0 }
}

impl Instrument for Synth {
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
                    // uma roubada em silêncio não tem o que esvaziar
                    if v.dying {
                        v.kill();
                    }
                    continue;
                }
                v.render(&self.block, &mut self.rng, l, r);
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

    const RATE: f64 = 48_000.0;

    fn run(s: &mut Synth, frames: usize) -> (Vec<f32>, Vec<f32>) {
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

    fn set(s: &mut Synth, params: &[(u32, f32)]) {
        for &(id, v) in params {
            s.set_param(id, v);
        }
    }

    /// Só o oscilador 1 em senoide, filtro aberto e parado.
    fn pure_sine() -> Synth {
        let mut s = Synth::new(RATE);
        set(&mut s, &[(P::OSC1_WAVE, 3.0), (P::OSC2_LEVEL, 0.0), (P::CUTOFF, 20_000.0), (P::RESONANCE, 0.0), (P::FILTER_ENV, 0.0), (P::KEYTRACK, 0.0)]);
        s
    }

    /// Frequência pelo tempo entre o primeiro e o último cruzamento por zero subindo, com
    /// interpolação linear dentro do quadro.
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

    fn busy_pitches(s: &Synth) -> Vec<u8> {
        let mut p: Vec<u8> = s.voices.iter().filter(|v| v.busy()).map(|v| v.pitch).collect();
        p.sort_unstable();
        p
    }

    fn voice_of(s: &Synth, pitch: u8) -> &Voice {
        s.voices.iter().find(|v| v.busy() && v.pitch == pitch).expect("voz da nota")
    }

    #[test]
    fn soa_depois_do_note_on_e_silencia_depois_do_release() {
        let mut s = Synth::new(RATE);
        assert!(!s.active());
        s.note_on(60, 0.8);
        assert!(s.active());
        let (l, r) = run(&mut s, 4800);
        assert!(rms(&l[480..]) > 0.02 && rms(&r[480..]) > 0.02, "{}", rms(&l[480..]));
        s.note_off(60);
        let (l, r) = run(&mut s, 48_000);
        assert!(!s.active());
        assert!(l[40_000..].iter().chain(&r[40_000..]).all(|&x| x == 0.0));
        // e parado não mexe na saída
        let (mut a, mut b) = (vec![0.25; 64], vec![0.25; 64]);
        s.render(&mut a, &mut b);
        assert!(a.iter().chain(&b).all(|&x| x == 0.25));
    }

    #[test]
    fn senoide_na_frequencia_da_nota() {
        let mut s = pure_sine();
        s.note_on(69, 1.0);
        let (l, r) = run(&mut s, 48_000);
        let f = frequency(&l[4800..]);
        assert!((f - 440.0).abs() < 0.05, "{f} Hz");
        // sem uníssono o som é mono
        assert!(l.iter().zip(&r).all(|(a, b)| (a - b).abs() < 1e-6));
    }

    #[test]
    fn oscilador_2_com_semitons_e_cents_e_sub_uma_oitava_abaixo() {
        let mut s = pure_sine();
        set(&mut s, &[(P::OSC1_LEVEL, 0.0), (P::OSC2_WAVE, 3.0), (P::OSC2_LEVEL, 1.0), (P::OSC2_SEMI, 7.0), (P::OSC2_DETUNE, -50.0)]);
        s.note_on(57, 1.0);
        let (l, _) = run(&mut s, 48_000);
        let want = 220.0 * 2f32.powf(6.5 / 12.0);
        let f = frequency(&l[4800..]);
        assert!((f - want).abs() < 0.05, "{f} Hz, esperava {want}");

        let mut s = pure_sine();
        set(&mut s, &[(P::OSC1_LEVEL, 0.0), (P::SUB_LEVEL, 1.0)]);
        s.note_on(69, 1.0);
        let (l, _) = run(&mut s, 48_000);
        let f = frequency(&l[4800..]);
        assert!((f - 220.0).abs() < 0.05, "{f} Hz");
    }

    #[test]
    fn unissono_abre_o_estereo_e_mantem_o_volume() {
        let loudness = |unison: f32, spread: f32| {
            let mut s = Synth::new(RATE);
            set(&mut s, &[(P::UNISON, unison), (P::UNISON_SPREAD, spread), (P::UNISON_DETUNE, 30.0), (P::OSC2_LEVEL, 0.0)]);
            s.note_on(57, 1.0);
            let (l, r) = run(&mut s, 48_000);
            (rms(&l[4800..]), rms(&r[4800..]), l.iter().zip(&r).map(|(a, b)| (a - b).abs()).fold(0.0f32, f32::max))
        };
        let (l1, r1, diff1) = loudness(1.0, 1.0);
        assert!(diff1 < 1e-6);
        let (l7, r7, diff7) = loudness(7.0, 1.0);
        assert!(diff7 > 0.05, "o uníssono aberto devia diferir entre os canais");
        // 1/√n: o volume percebido fica na mesma ordem (dentro de 3 dB)
        for (a, b) in [(l1, l7), (r1, r7)] {
            let db = 20.0 * (b / a).log10();
            assert!(db.abs() < 3.0, "{db} dB");
        }
        // sem abertura, o uníssono continua mono
        let (_, _, diff) = loudness(5.0, 0.0);
        assert!(diff < 1e-5, "{diff}");
    }

    #[test]
    fn parametros_extremos_nao_geram_nan() {
        let mut worst: f32 = 0.0;
        for wave in 0..4 {
            for mode in 0..3 {
                for cutoff in [20.0, 20_000.0] {
                    let mut s = Synth::new(RATE);
                    let w = wave as f32;
                    set(
                        &mut s,
                        &[
                            (P::OSC1_WAVE, w),
                            (P::OSC2_WAVE, 3.0 - w),
                            (P::FILTER_TYPE, mode as f32),
                            (P::CUTOFF, cutoff),
                            (P::RESONANCE, 1.0),
                            (P::DRIVE, 1.0),
                            (P::UNISON, 7.0),
                            (P::UNISON_DETUNE, 100.0),
                            (P::UNISON_SPREAD, 1.0),
                            (P::VOICES, 16.0),
                            (P::OSC1_LEVEL, 1.0),
                            (P::OSC2_LEVEL, 1.0),
                            (P::SUB_LEVEL, 1.0),
                            (P::NOISE_LEVEL, 1.0),
                            (P::OSC2_SEMI, 24.0),
                            (P::PULSE_WIDTH, 0.05),
                            (P::FILTER_ENV, 1.0),
                            (P::KEYTRACK, 1.0),
                            (P::LFO_WAVE, 4.0),
                            (P::LFO_RATE, 30.0),
                            (P::LFO_PITCH, 12.0),
                            (P::LFO_CUTOFF, 4.0),
                            (P::LFO_AMP, 1.0),
                            (P::GLIDE, 0.05),
                            (P::AMP_ATTACK, 0.0005),
                            (P::FLT_ATTACK, 0.0005),
                            (P::FLT_DECAY, 0.001),
                            (P::LEVEL, 1.5),
                        ],
                    );
                    // 32 notas em 16 vozes, do grave ao agudo
                    for i in 0..32u8 {
                        s.note_on(i * 4, 1.0);
                    }
                    let (l, r) = run(&mut s, 12_000);
                    // mexer em tudo com as notas soando
                    set(&mut s, &[(P::FILTER_ENV, -1.0), (P::CUTOFF, 20_020.0 - cutoff), (P::PULSE_WIDTH, 0.95), (P::OSC2_SEMI, -24.0), (P::UNISON, 2.0)]);
                    let (l2, r2) = run(&mut s, 12_000);
                    s.release_all();
                    let (l3, r3) = run(&mut s, 12_000);
                    for x in [&l, &r, &l2, &r2, &l3, &r3] {
                        assert!(x.iter().all(|v| v.is_finite()), "onda {wave}, filtro {mode}, corte {cutoff}");
                        worst = worst.max(peak(x));
                    }
                }
            }
        }
        eprintln!("pico com tudo no máximo: {worst}");
        assert!(worst < 24.0, "pico de {worst} com tudo no máximo");
    }

    #[test]
    fn ressonancia_maxima_fica_contida() {
        // serra a 110 Hz com o corte cravado no 2º harmônico: linear, o pico ressonante seria
        // Q × 0,8 × 2/(2π) ≈ 7,6 antes do ganho de saída (≈ 3,8 na saída)
        let mut s = Synth::new(RATE);
        set(
            &mut s,
            &[(P::OSC2_LEVEL, 0.0), (P::RESONANCE, 1.0), (P::CUTOFF, 220.0), (P::FILTER_ENV, 0.0), (P::KEYTRACK, 0.0), (P::AMP_SUSTAIN, 1.0), (P::LEVEL, 1.0)],
        );
        s.note_on(45, 1.0);
        let (l, _) = run(&mut s, 48_000);
        let p = peak(&l[24_000..]);
        eprintln!("pico com ressonância máxima: {p}");
        assert!(p < 1.5, "pico de {p}");
        // e a ressonância continua lá: bem mais forte que com o filtro sem pico
        s.set_param(P::RESONANCE, 0.0);
        let (l, _) = run(&mut s, 48_000);
        assert!(p > 2.0 * peak(&l[24_000..]), "{p} contra {}", peak(&l[24_000..]));
    }

    #[test]
    fn mono_legato_nao_redispara_o_envelope() {
        let mut s = Synth::new(RATE);
        s.set_param(P::VOICES, 1.0);
        s.note_on(60, 0.8);
        run(&mut s, 48_000);
        assert_eq!(voice_of(&s, 60).amp.stage(), Stage::Sustain);

        // outra nota com a primeira presa: a mesma voz muda de altura, os envelopes seguem
        s.note_on(64, 0.8);
        assert_eq!(busy_pitches(&s), [64]);
        let v = voice_of(&s, 64);
        assert_eq!((v.amp.stage(), v.flt.stage()), (Stage::Sustain, Stage::Sustain));
        assert_eq!(v.cur, 64.0);
        run(&mut s, 4800);

        // soltar a de cima volta para a de baixo, ainda sem redisparar
        s.note_off(64);
        let v = voice_of(&s, 60);
        assert_eq!((v.amp.stage(), v.cur), (Stage::Sustain, 60.0));
        run(&mut s, 4800);

        // soltar uma tecla que não é a que soa não muda nada
        s.note_on(67, 0.8);
        s.note_off(60);
        assert_eq!(voice_of(&s, 67).amp.stage(), Stage::Sustain);

        s.note_off(67);
        assert!(s.voices.iter().all(|v| !v.gate));
        assert!(s.voices.iter().any(|v| v.amp.stage() == Stage::Release));

        // nota nova sem nenhuma presa: redispara (da soltura, sem voltar a zero)
        run(&mut s, 480);
        s.note_on(72, 0.8);
        let v = voice_of(&s, 72);
        assert_eq!(v.amp.stage(), Stage::Attack);
        assert!(v.amp.value() > 0.1);
        assert_eq!(s.busy_count(), 1);
    }

    #[test]
    fn mono_com_glide_desliza_entre_as_notas() {
        let mut s = Synth::new(RATE);
        set(&mut s, &[(P::VOICES, 1.0), (P::GLIDE, 0.1)]);
        s.note_on(60, 0.8);
        assert_eq!(voice_of(&s, 60).cur, 60.0); // primeira nota: nada de onde deslizar
        run(&mut s, 4800);
        s.note_on(72, 0.8);
        run(&mut s, 1200); // 25 ms
        let cur = voice_of(&s, 72).cur;
        assert!(cur > 62.0 && cur < 71.0, "{cur}");
        run(&mut s, 9600); // 225 ms depois do início do glide
        let cur = voice_of(&s, 72).cur;
        assert!((cur - 72.0).abs() < 0.01, "{cur}");
        // o envelope seguiu do decaimento da primeira nota, sem voltar ao ataque
        assert_ne!(voice_of(&s, 72).amp.stage(), Stage::Attack);
    }

    #[test]
    fn poli_com_glide_parte_da_ultima_nota() {
        let mut s = Synth::new(RATE);
        s.set_param(P::GLIDE, 0.2);
        s.note_on(48, 0.8);
        run(&mut s, 480);
        s.note_on(60, 0.8);
        assert_eq!(voice_of(&s, 60).cur, 48.0);
        assert_eq!(voice_of(&s, 48).cur, 48.0);
        s.set_param(P::GLIDE, 0.0);
        s.note_on(67, 0.8);
        assert_eq!(voice_of(&s, 67).cur, 67.0);
    }

    #[test]
    fn rouba_voz_quando_passa_da_polifonia() {
        let mut s = Synth::new(RATE);
        s.set_param(P::VOICES, 4.0);
        for p in 60..64 {
            s.note_on(p, 0.8);
            run(&mut s, 480);
        }
        assert_eq!(busy_pitches(&s), [60, 61, 62, 63]);

        // a quinta nota rouba a mais antiga, que sai em fade numa voz de folga
        s.note_on(64, 0.8);
        assert_eq!(busy_pitches(&s), [61, 62, 63, 64]);
        assert_eq!(s.voices.iter().filter(|v| v.dying).count(), 1);
        run(&mut s, 480); // 10 ms > fade de 5 ms
        assert!(s.voices.iter().all(|v| !v.dying));
        assert_eq!(s.voices.iter().filter(|v| v.amp.active()).count(), 4);

        // com uma voz já solta, é ela a roubada, não a mais antiga
        s.note_off(63);
        run(&mut s, 480);
        s.note_on(70, 0.8);
        assert_eq!(busy_pitches(&s), [61, 62, 64, 70]);

        // rajada de notas maior que a polifonia e as folgas juntas
        for p in 80..110 {
            s.note_on(p, 0.8);
        }
        assert_eq!(busy_pitches(&s), [106, 107, 108, 109]);
        let (l, _) = run(&mut s, 4800);
        assert!(l.iter().all(|v| v.is_finite()));
    }

    #[test]
    fn baixar_a_polifonia_solta_as_vozes_a_mais() {
        let mut s = Synth::new(RATE);
        for p in [60, 64, 67] {
            s.note_on(p, 0.8);
        }
        run(&mut s, 480);
        s.set_param(P::VOICES, 1.0);
        assert_eq!(busy_pitches(&s), [67]);
        // e o mono continua dali: soltar a 67 volta para a 64, que ainda está presa
        s.note_off(67);
        assert_eq!(busy_pitches(&s), [64]);
        assert!(voice_of(&s, 64).gate);
    }

    #[test]
    fn mesma_nota_de_novo_reataca_a_mesma_voz() {
        let mut s = Synth::new(RATE);
        s.note_on(60, 0.8);
        run(&mut s, 24_000);
        s.note_on(60, 0.8);
        assert_eq!(s.busy_count(), 1);
        assert_eq!(voice_of(&s, 60).amp.stage(), Stage::Attack);
        // e também durante a soltura: não empilha duas vozes da mesma nota
        s.note_off(60);
        run(&mut s, 480);
        s.note_on(60, 0.8);
        assert_eq!(s.busy_count(), 1);
        assert!(voice_of(&s, 60).gate);
    }

    #[test]
    fn release_all_solta_e_silence_corta() {
        let mut s = Synth::new(RATE);
        for p in [60, 64, 67] {
            s.note_on(p, 0.8);
        }
        run(&mut s, 4800);
        s.release_all();
        assert!(s.voices.iter().filter(|v| v.amp.active()).all(|v| v.amp.stage() == Stage::Release));
        assert!(s.active());
        run(&mut s, 48_000);
        assert!(!s.active());

        for p in [60, 64, 67] {
            s.note_on(p, 0.8);
        }
        run(&mut s, 4800);
        s.silence();
        assert!(!s.active());
        let (l, _) = run(&mut s, 128);
        assert!(l.iter().all(|&v| v == 0.0));
    }

    #[test]
    fn velocidade_muda_o_volume() {
        let level = |sensitivity: f32, velocity: f32| {
            let mut s = pure_sine();
            s.set_param(P::VELOCITY, sensitivity);
            s.note_on(60, velocity);
            let (l, _) = run(&mut s, 24_000);
            rms(&l[12_000..])
        };
        let (loud, soft) = (level(1.0, 1.0), level(1.0, 0.5));
        let db = 20.0 * (soft / loud).log10();
        assert!((db + 12.0).abs() < 0.5, "{db} dB");
        let (loud, soft) = (level(0.0, 1.0), level(0.0, 0.2));
        assert!((loud - soft).abs() < 1e-3 * loud);
    }

    #[test]
    fn parametros_invalidos_sao_limitados_ou_ignorados() {
        let mut s = Synth::new(RATE);
        s.set_param(P::CUTOFF, f32::NAN);
        assert_eq!(s.params[P::CUTOFF as usize], 2400.0);
        s.set_param(P::CUTOFF, 1e9);
        assert_eq!(s.params[P::CUTOFF as usize], 20_000.0);
        s.set_param(P::UNISON, 3.4);
        assert_eq!(s.unison(), 3);
        s.set_param(P::VOICES, -5.0);
        assert_eq!(s.limit(), 1);
        s.set_param(P::COUNT, 1.0);
        s.set_param(u32::MAX, 1.0);
        s.note_on(60, f32::NAN);
        s.note_on(255, 2.0);
        let (l, _) = run(&mut s, 4800);
        assert!(l.iter().all(|v| v.is_finite()));
    }

    /// Maior salto entre dois quadros seguidos.
    fn max_jump(x: &[f32]) -> f32 {
        x.windows(2).fold(0.0f32, |m, w| m.max((w[1] - w[0]).abs()))
    }

    /// Maior salto a partir do último quadro de `before`: a emenda conta, é ali que uma mudança
    /// seca apareceria.
    fn seam_jump(before: &[f32], after: &[f32]) -> f32 {
        let seam: Vec<f32> = before[before.len() - 1..].iter().chain(after).copied().collect();
        max_jump(&seam)
    }

    /// Senoides graves (~98 Hz) têm salto natural pequeno entre quadros; 24 122 quadros são 49¼
    /// ciclos, então a mudança cai no pico da onda, onde um degrau seria maior.
    const AT_PEAK: usize = 24_122;

    #[test]
    fn mudar_o_volume_com_a_nota_soando_nao_da_degrau() {
        let mut s = pure_sine();
        set(&mut s, &[(P::LEVEL, 1.5), (P::AMP_SUSTAIN, 1.0)]);
        s.note_on(43, 1.0);
        let (before, _) = run(&mut s, AT_PEAK);
        s.set_param(P::LEVEL, 0.0);
        s.set_param(P::CUTOFF, 20.0);
        let (after, _) = run(&mut s, 4800);
        // sem suavização o degrau seria de 0,75
        let jump = seam_jump(&before, &after);
        assert!(jump < 0.02, "degrau de {jump}");
    }

    #[test]
    fn roubo_de_voz_nao_estala() {
        let mut s = pure_sine();
        set(&mut s, &[(P::VOICES, 2.0), (P::AMP_SUSTAIN, 1.0), (P::LEVEL, 1.5)]);
        s.note_on(43, 1.0);
        s.note_on(47, 1.0);
        let (before, _) = run(&mut s, AT_PEAK);
        let natural = max_jump(&before[12_000..]);
        // rouba a 43 no pico: cortada seco, daria um salto de ~0,6
        s.note_on(50, 1.0);
        let (after, _) = run(&mut s, 4800);
        let jump = seam_jump(&before, &after);
        assert!(jump < 2.0 * natural + 0.01, "salto de {jump} (natural {natural})");
    }

    #[test]
    fn reatacar_com_outra_velocidade_nao_da_degrau() {
        let mut s = pure_sine();
        set(&mut s, &[(P::VELOCITY, 1.0), (P::AMP_SUSTAIN, 1.0), (P::LEVEL, 1.5)]);
        s.note_on(43, 1.0);
        let (before, _) = run(&mut s, AT_PEAK);
        s.note_on(43, 0.1);
        let (after, _) = run(&mut s, 4800);
        let jump = seam_jump(&before, &after);
        assert!(jump < 0.02, "degrau de {jump}");
        assert!(rms(&after[2400..]) < 0.05, "a velocidade nova devia valer: {}", rms(&after[2400..]));
    }

    #[test]
    fn filtro_em_silencio_nao_acumula_denormais() {
        let mut s = Synth::new(RATE);
        set(&mut s, &[(P::OSC1_LEVEL, 0.0), (P::OSC2_LEVEL, 0.0), (P::RESONANCE, 1.0), (P::AMP_SUSTAIN, 1.0)]);
        s.note_on(60, 1.0);
        run(&mut s, 96_000);
        let v = voice_of(&s, 60);
        assert_eq!((v.res_l, v.res_r), (0.0, 0.0));
    }

    #[test]
    fn pluck_segurado_nao_gasta_e_volta_se_a_sustentacao_subir() {
        let mut s = Synth::new(RATE);
        set(&mut s, &[(P::AMP_DECAY, 0.05), (P::AMP_SUSTAIN, 0.0)]);
        s.note_on(60, 1.0);
        run(&mut s, 24_000);
        assert!(voice_of(&s, 60).silent_hold());
        let phase = voice_of(&s, 60).osc[0].ph1;
        let (l, _) = run(&mut s, 4800);
        assert!(l.iter().all(|&v| v == 0.0));
        assert_eq!(voice_of(&s, 60).osc[0].ph1, phase, "a voz em silêncio não devia ser calculada");
        assert!(s.active());

        // a sustentação sobe com a tecla presa: o som volta, subindo sem degrau
        s.set_param(P::AMP_SUSTAIN, 0.8);
        let (l, _) = run(&mut s, 4800);
        assert!(rms(&l[2400..]) > 0.05);
        assert!(l[..16].iter().all(|v| v.abs() < 0.05));

        // e o note off solta normalmente
        s.set_param(P::AMP_SUSTAIN, 0.0);
        run(&mut s, 24_000);
        s.note_off(60);
        run(&mut s, 128);
        assert!(!s.active());
    }

    // ------------------------------------------------------------ aliasing

    /// Energia fora dos harmônicos abaixo de 12 kHz (o aliasing que se ouve), relativa ao total,
    /// em dB, de 4800 quadros de uma onda a 2630 Hz (um mi agudo): harmônicos e espelhos caem todos
    /// em bins exatos de 10 Hz. Acima de 12 kHz o polyBLEP de 2 pontos ainda deixa espelhos, mas
    /// ali eles ficam mascarados pelos próprios harmônicos e o filtro costuma tirá-los.
    fn alias_db(sample: impl Fn(f32, f32) -> f32) -> f32 {
        const N: usize = 4800;
        let dt = 2630.0 / RATE as f32;
        let mut x = vec![0.0f32; N];
        let mut p = 0.0;
        for (i, v) in x.iter_mut().enumerate() {
            let hann = 0.5 - 0.5 * (std::f32::consts::TAU * i as f32 / N as f32).cos();
            *v = sample(p, dt) * hann;
            p = wrap(p + dt);
        }
        let twiddle: Vec<(f32, f32)> = (0..N).map(|i| (std::f32::consts::TAU * i as f32 / N as f32).sin_cos()).collect();
        let (mut alias, mut total) = (0.0f64, 0.0f64);
        for k in 3..N / 2 {
            let (mut re, mut im) = (0.0f32, 0.0f32);
            for (n, v) in x.iter().enumerate() {
                let (s, c) = twiddle[(k * n) % N];
                re += v * c;
                im -= v * s;
            }
            let power = (re * re + im * im) as f64;
            total += power;
            let h = (k as f32 / 263.0).round() as usize;
            if k < 1200 && (h == 0 || k.abs_diff(h * 263) > 2) {
                alias += power;
            }
        }
        (10.0 * (alias / total).log10()) as f32
    }

    #[test]
    fn osciladores_sem_aliasing() {
        let blep_saw = alias_db(|p, dt| osc(Wave::Saw, p, dt, 0.5));
        let naive_saw = alias_db(|p, _| 2.0 * p - 1.0);
        let blep_pulse = alias_db(|p, dt| osc(Wave::Pulse, p, dt, 0.3));
        let naive_pulse = alias_db(|p, _| if p < 0.3 { 1.0 } else { -1.0 });
        let blamp_tri = alias_db(|p, dt| osc(Wave::Triangle, p, dt, 0.5));
        let naive_tri = alias_db(|p, _| 4.0 * (p - 0.5).abs() - 1.0);
        let sine = alias_db(|p, dt| osc(Wave::Sine, p, dt, 0.5));
        eprintln!(
            "aliasing (dB): serra {blep_saw:.1} (ingênua {naive_saw:.1}), pulso {blep_pulse:.1} ({naive_pulse:.1}), triângulo {blamp_tri:.1} ({naive_tri:.1}), senoide {sine:.1}"
        );
        assert!(blep_saw < naive_saw - 20.0 && blep_saw < -40.0);
        assert!(blep_pulse < naive_pulse - 20.0 && blep_pulse < -40.0);
        assert!(blamp_tri < naive_tri - 20.0 && blamp_tri < -65.0);
        assert!(sine < -90.0);
    }

    #[test]
    fn pulso_sem_dc() {
        // 1 kHz a 48 kHz: 48 quadros por ciclo, 100 ciclos exatos
        let dt = 1000.0 / RATE as f32;
        for pw in [0.05, 0.2, 0.5, 0.9] {
            let mut p = 0.0;
            let mut sum = 0.0;
            for _ in 0..4800 {
                sum += osc(Wave::Pulse, p, dt, pw);
                p = wrap(p + dt);
            }
            assert!((sum / 4800.0).abs() < 1e-3, "pw {pw}: média {}", sum / 4800.0);
        }
    }

    // ------------------------------------------------------------ contrato com o app

    #[test]
    fn faixas_iguais_as_do_app() {
        let path = concat!(env!("CARGO_MANIFEST_DIR"), "/../app/lib/daw/instruments.dart");
        let Ok(src) = std::fs::read_to_string(path) else {
            eprintln!("sem {path}: conferência pulada");
            return;
        };
        let body = &src[src.find("const synthParams").unwrap()..];
        let body = &body[..body.find("];").unwrap()];
        let quoted = |s: &str| s.matches('\'').count() / 2;
        let mut seen = [false; PARAMS];
        for line in body.lines().map(str::trim) {
            if let Some(rest) = line.strip_prefix("ParamSpec.choice(") {
                let id: usize = rest.split(',').next().unwrap().trim().parse().unwrap();
                // as opções vêm numa lista literal ou numa constante (`_waves`)
                let options = match rest.split(',').nth(3).map(str::trim) {
                    Some(name) if name.starts_with('_') => {
                        let name = name.trim_end_matches(')');
                        let decl = &src[src.find(&format!("const {name} = [")).unwrap()..];
                        quoted(&decl[..decl.find(']').unwrap()])
                    }
                    _ => quoted(rest) - 2,
                };
                let spec = SPECS[id];
                assert!(spec.discrete && spec.min == 0.0 && spec.max == (options - 1) as f32 && spec.def == 0.0, "id {id}");
                seen[id] = true;
            } else if let Some(rest) = line.strip_prefix("ParamSpec(") {
                let fields: Vec<&str> = rest.split(',').map(|f| f.trim().trim_end_matches(')')).collect();
                let id: usize = fields[0].parse().unwrap();
                let (min, max, def): (f32, f32, f32) = (fields[3].parse().unwrap(), fields[4].parse().unwrap(), fields[5].parse().unwrap());
                let spec = SPECS[id];
                assert_eq!((spec.min, spec.max, spec.def), (min, max, def), "id {id}");
                assert_eq!(spec.discrete, line.contains("Curve.integer"), "id {id}");
                seen[id] = true;
            }
        }
        assert!(seen.iter().all(|&s| s), "ids sem espelho no app: {seen:?}");
    }

    // ------------------------------------------------------------ desempenho

    fn bench(voices: usize, unison: f32, extra: &[(u32, f32)]) -> f64 {
        let mut s = Synth::new(RATE);
        set(&mut s, &[(P::UNISON, unison), (P::VOICES, 16.0), (P::AMP_SUSTAIN, 1.0)]);
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

    /// Nome, vozes, uníssono e parâmetros extras de um caso de medição.
    type Case = (&'static str, usize, f32, &'static [(u32, f32)]);

    #[test]
    #[ignore = "medição: cargo test --release -p jopendaw-engine -- --ignored --nocapture"]
    fn desempenho() {
        let cases: [Case; 4] = [
            ("8 vozes × 3 uníssono", 8, 3.0, &[]),
            (
                "8 × 3 com sub, ruído, drive e LFO",
                8,
                3.0,
                &[(P::SUB_LEVEL, 0.5), (P::NOISE_LEVEL, 0.2), (P::DRIVE, 0.5), (P::LFO_PITCH, 0.2), (P::LFO_CUTOFF, 1.0)],
            ),
            ("8 × 3 triângulo + pulso", 8, 3.0, &[(P::OSC1_WAVE, 2.0), (P::OSC2_WAVE, 1.0)]),
            ("16 vozes × 7 uníssono (pior caso)", 16, 7.0, &[]),
        ];
        for (name, voices, unison, extra) in cases {
            // o melhor de 10: tira o aquecimento da CPU e as trocas de núcleo
            let secs = (0..10).map(|_| bench(voices, unison, extra)).fold(f64::MAX, f64::min);
            println!("{name}: 1 s de áudio a 48 kHz em {:.2} ms ({:.2}% de um núcleo)", secs * 1000.0, secs * 100.0);
        }
    }
}
