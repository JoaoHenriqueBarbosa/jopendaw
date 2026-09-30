//! Modulação leve: por faixa (e no master), até [`MAX_SOURCES`] moduladores (LFO, seguidor de
//! envelope, macro) e, por modulador, até [`MAX_DESTS`] destinos. Um destino é um alvo no mesmo
//! modelo da automação ([`Target`]: volume, pan, parâmetro do instrumento, parâmetro de efeito,
//! nível de envio) com uma quantidade bipolar (−1..1 = ±100% do curso do controle, na escala dele:
//! linear, logarítmica ou a curva do fader).
//!
//! O valor efetivo do alvo é `base + modulação`, limitado ao curso: a base é o valor do controle
//! (o estático que o app mandou) ou, com a automação tocando o alvo, o valor da automação. A
//! modulação nunca é gravada nela: parar de modular devolve o alvo à base. Vários destinos no mesmo
//! alvo somam no curso do controle.
//!
//! Tudo roda no ritmo das fatias do motor (`AUTO_STEP` quadros, numa grade fixa do relógio dele),
//! então o render fora de tempo real sai igual ao tempo real. Sem alocação: os moduladores e
//! destinos são arrays fixos, e o sorteio do sample&hold é uma função da posição no ciclo.

use crate::effect::auto_target as at;
use crate::{Engine, Target};

/// Moduladores por faixa.
pub const MAX_SOURCES: usize = 4;
/// Destinos por modulador.
pub const MAX_DESTS: usize = 4;

/// Tipos de modulador (`mod_source`).
pub mod kind {
    /// Oscilador de baixa frequência.
    pub const LFO: u32 = 0;
    /// Seguidor de envelope: o nível do sinal da própria faixa (depois dos inserts, antes do fader).
    pub const FOLLOWER: u32 = 1;
    /// Valor fixo 0..1 (controlável de fora) como fonte para vários destinos.
    pub const MACRO: u32 = 2;
}

/// Formas do LFO.
pub mod shape {
    pub const SINE: u32 = 0;
    pub const TRIANGLE: u32 = 1;
    pub const SAW: u32 = 2;
    pub const SQUARE: u32 = 3;
    pub const SAMPLE_HOLD: u32 = 4;
}

/// Escala em que a quantidade anda no curso do alvo.
pub mod scale {
    pub const LINEAR: u32 = 0;
    /// Logarítmica (Hz, segundos): o meio do curso é a média geométrica.
    pub const LOG: u32 = 1;
    /// Curva do fader (volume e envio): o ganho é `máx · x³`.
    pub const FADER: u32 = 2;
}

/// Taxa livre do LFO, Hz.
pub const RATE_MIN: f32 = 0.01;
pub const RATE_MAX: f32 = 50.0;

/// Divisões sincronizadas: 8 bases (4 compassos, 2 compassos, 1 compasso, 1/2, 1/4, 1/8, 1/16,
/// 1/32) vezes 3 variações (reta, pontilhada, tercina); o índice é `base · 3 + variação`.
pub const DIVISIONS: usize = 24;

/// Compasso de 4 tempos para as divisões de compasso.
const BASE_BEATS: [f64; 8] = [16.0, 8.0, 4.0, 2.0, 1.0, 0.5, 0.25, 0.125];

/// Duração de um ciclo da divisão `index`, em batidas (índice além do fim vale o último).
pub fn division_beats(index: usize) -> f64 {
    let i = index.min(DIVISIONS - 1);
    let base = BASE_BEATS[i / 3];
    match i % 3 {
        1 => base * 1.5,
        2 => base * 2.0 / 3.0,
        _ => base,
    }
}

/// Constante de tempo do alisamento das formas com salto (dente de serra, quadrada, sample&hold).
const JUMP_SMOOTH_SECS: f64 = 0.001;

/// O curso de um alvo e a escala em que a quantidade anda nele.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Warp {
    pub min: f32,
    pub max: f32,
    pub scale: u32,
}

impl Warp {
    pub(crate) fn sane(min: f32, max: f32, scale: u32) -> Self {
        let (min, max) = if min.is_finite() && max.is_finite() && max > min { (min, max) } else { (0.0, 1.0) };
        // log precisa de mínimo positivo e o fader parte do zero: fora disso, linear
        let scale = if (scale == scale::LOG && min <= 0.0) || (scale == scale::FADER && (min != 0.0 || max <= 0.0)) { scale::LINEAR } else { scale };
        Self { min, max, scale }
    }

    /// Valor → posição 0..1 no curso.
    pub fn to_norm(self, v: f32) -> f32 {
        let v = v.clamp(self.min, self.max);
        let n = match self.scale {
            scale::LOG => (v / self.min).ln() / (self.max / self.min).ln(),
            scale::FADER => (v / self.max).cbrt(),
            _ => (v - self.min) / (self.max - self.min),
        };
        if n.is_finite() { n.clamp(0.0, 1.0) } else { 0.0 }
    }

    /// Posição 0..1 → valor.
    pub fn from_norm(self, n: f32) -> f32 {
        let n = n.clamp(0.0, 1.0);
        let v = match self.scale {
            scale::LOG => self.min * (self.max / self.min).powf(n),
            scale::FADER => self.max * n * n * n,
            _ => self.min + (self.max - self.min) * n,
        };
        if v.is_finite() { v.clamp(self.min, self.max) } else { self.min }
    }
}

/// O que cada passo sabe do transporte.
struct Step {
    frames: usize,
    rate: f64,
    playing: bool,
    /// Batida do transporte no começo do passo.
    beat: f64,
    /// Andamento nela, bpm.
    bpm: f64,
}

/// Um modulador: a configuração vinda de `mod_source` e o estado que anda com o tempo.
#[derive(Clone, Copy, Debug)]
pub struct Source {
    /// Vale (foi mandado desde o último `mod_clear`).
    live: bool,
    kind: u32,
    shape: u32,
    /// Hz (livre) ou índice da divisão (sincronizado).
    rate: f32,
    sync: bool,
    /// LFO: amplitude 0..1. Seguidor: ganho 0..8.
    depth: f32,
    /// Fase inicial, 0..1 de ciclo.
    phase: f32,
    bipolar: bool,
    attack_ms: f32,
    release_ms: f32,
    /// Macro: o valor 0..1.
    value: f32,
    /// Ciclos acumulados (livre; e sincronizado enquanto parado).
    acc: f64,
    /// Última saída (alisada nas formas com salto); NaN = nenhuma.
    out: f32,
    /// Nível do seguidor.
    env: f32,
    /// Maior pico que a faixa teve desde o último passo.
    peak: f32,
}

impl Source {
    const NEW: Source = Source {
        live: false,
        kind: kind::LFO,
        shape: shape::SINE,
        rate: 1.0,
        sync: false,
        depth: 1.0,
        phase: 0.0,
        bipolar: true,
        attack_ms: 10.0,
        release_ms: 100.0,
        value: 0.0,
        acc: 0.0,
        out: f32::NAN,
        env: 0.0,
        peak: 0.0,
    };

    /// Recomeça o LFO (o play): fase zero, sem alisamento antigo.
    fn restart(&mut self) {
        self.acc = 0.0;
        self.out = f32::NAN;
    }

    /// A saída deste passo (bipolar −depth..depth, unipolar 0..depth) e avança o estado.
    fn tick(&mut self, st: &Step, salt: u32) -> f32 {
        match self.kind {
            kind::FOLLOWER => {
                let coef = |ms: f32| if ms <= 0.0 { 1.0 } else { 1.0 - (-(st.frames as f64) / (st.rate * f64::from(ms) * 1e-3)).exp() as f32 };
                let target = self.peak;
                self.peak = 0.0;
                let c = if target > self.env { coef(self.attack_ms) } else { coef(self.release_ms) };
                self.env += (target - self.env) * c;
                let v = (self.env * self.depth).clamp(0.0, 1.0);
                if self.bipolar { v * 2.0 - 1.0 } else { v }
            }
            kind::MACRO => {
                let v = self.value.clamp(0.0, 1.0);
                if self.bipolar { v * 2.0 - 1.0 } else { v }
            }
            _ => self.lfo(st, salt),
        }
    }

    fn lfo(&mut self, st: &Step, salt: u32) -> f32 {
        let hz = f64::from(self.rate.clamp(RATE_MIN, RATE_MAX));
        let len = division_beats(self.rate.max(0.0) as usize);
        // sincronizado e tocando, a fase é a posição em batidas (o mapa de andamento vale, e o
        // seek cai na fase certa); parado (ou livre), ela anda pelo relógio
        let base = if self.sync && st.playing { st.beat / len } else { self.acc };
        let cycles = base + f64::from(self.phase);
        let raw = wave(self.shape, cycles, salt);
        let v = if self.bipolar { raw * self.depth } else { (raw + 1.0) * 0.5 * self.depth };
        let v = if v.is_finite() { v } else { 0.0 };
        let out = if matches!(self.shape, shape::SAW | shape::SQUARE | shape::SAMPLE_HOLD) && !self.out.is_nan() {
            let k = 1.0 - (-(st.frames as f64) / (st.rate * JUMP_SMOOTH_SECS)).exp() as f32;
            self.out + (v - self.out) * k
        } else {
            v
        };
        self.out = out;
        let secs = st.frames as f64 / st.rate;
        self.acc = if self.sync { if st.playing { st.beat / len } else { self.acc + secs * st.bpm / 60.0 / len } } else { self.acc + secs * hz };
        out
    }
}

/// A forma de onda na fase `cycles` (ciclos, o que passa de 1 dá a volta): −1..1.
pub(crate) fn wave(shape: u32, cycles: f64, salt: u32) -> f32 {
    let p = cycles - cycles.floor();
    match shape {
        shape::TRIANGLE => (1.0 - 4.0 * ((p + 0.25).fract() - 0.5).abs()) as f32,
        shape::SAW => (2.0 * p - 1.0) as f32,
        shape::SQUARE => {
            if p < 0.5 {
                1.0
            } else {
                -1.0
            }
        }
        shape::SAMPLE_HOLD => hash_unit(cycles.floor() as i64, salt),
        _ => (std::f64::consts::TAU * p).sin() as f32,
    }
}

/// Sorteio determinístico em −1..1 a partir do ciclo (splitmix64): o mesmo ciclo dá o mesmo valor
/// no tempo real, no render e depois de um seek.
pub(crate) fn hash_unit(idx: i64, salt: u32) -> f32 {
    let mut z = (idx as u64).wrapping_add(u64::from(salt).wrapping_mul(0x9E37_79B9_7F4A_7C15)).wrapping_add(0x9E37_79B9_7F4A_7C15);
    z = (z ^ (z >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
    z = (z ^ (z >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
    z ^= z >> 31;
    ((z >> 40) as f32 / (1u64 << 23) as f32) - 1.0
}

/// Um destino de modulador.
#[derive(Clone, Copy, Debug)]
pub struct Dest {
    live: bool,
    target: Target,
    amount: f32,
    warp: Warp,
    /// O alvo em que este destino está mexendo agora (para devolvê-lo à base quando sair).
    applied: Option<Target>,
    /// Base e valor efetivo do último passo: parâmetros de instrumento e efeito só são mexidos
    /// quando um dos dois muda.
    last_base: f32,
    last_eff: f32,
}

impl Dest {
    const NEW: Dest = Dest {
        live: false,
        target: Target { track: 0, kind: 0, slot: 0, id: 0 },
        amount: 0.0,
        warp: Warp { min: 0.0, max: 1.0, scale: scale::LINEAR },
        applied: None,
        last_base: f32::NAN,
        last_eff: f32::NAN,
    };
}

/// A modulação de uma faixa.
#[derive(Clone, Copy, Debug)]
pub struct TrackMod {
    src: [Source; MAX_SOURCES],
    dst: [[Dest; MAX_DESTS]; MAX_SOURCES],
    /// Há destino vivo: a faixa entra no passo.
    active: bool,
    /// Algum seguidor vivo: o motor entrega o nível da faixa a cada bloco.
    wants_level: bool,
}

impl TrackMod {
    pub const NEW: TrackMod = TrackMod { src: [Source::NEW; MAX_SOURCES], dst: [[Dest::NEW; MAX_DESTS]; MAX_SOURCES], active: false, wants_level: false };

    pub fn wants_level(&self) -> bool {
        self.wants_level
    }

    /// O pico do bloco (para os seguidores).
    pub fn feed(&mut self, l: &[f32], r: &[f32]) {
        let mut peak = 0.0f32;
        for &s in l.iter().chain(r) {
            peak = peak.max(s.abs());
        }
        if !peak.is_finite() {
            return;
        }
        for s in self.src.iter_mut().filter(|s| s.live && s.kind == kind::FOLLOWER) {
            s.peak = s.peak.max(peak);
        }
    }

    fn has_dest_for(&self, t: Target) -> bool {
        (0..MAX_SOURCES).any(|s| self.src[s].live && self.dst[s].iter().any(|d| d.live && d.target == t))
    }
}

impl Engine {
    fn mod_of(&mut self, track: i32) -> Option<&mut TrackMod> {
        match track {
            -1 => Some(&mut self.master_mod),
            t if t >= 0 => self.mods.get_mut(t as usize),
            _ => None,
        }
    }

    /// Esquece todos os moduladores e destinos: os alvos voltam à base. O app reenvia tudo com
    /// [`Engine::mod_source`] e [`Engine::mod_dest`]; o que voltar igual segue sem degrau e sem
    /// reiniciar a fase do LFO (o estado só some no passo seguinte, se não voltou).
    pub fn mod_clear(&mut self) {
        for tm in self.mods.iter_mut().chain(std::iter::once(&mut self.master_mod)) {
            for s in &mut tm.src {
                s.live = false;
            }
            for d in tm.dst.iter_mut().flatten() {
                d.live = false;
            }
        }
        self.mod_dirty = true;
        self.mod_busy = true;
    }

    /// Configura o modulador `index` da faixa (−1 master). `rate` é Hz (livre) ou o índice da
    /// divisão (`sync`); `depth` é a amplitude do LFO (0..1) ou o ganho do seguidor (0..8);
    /// `phase` 0..1; `attack_ms`/`release_ms` são do seguidor e `value` (0..1) da macro.
    #[allow(clippy::too_many_arguments)]
    pub fn mod_source(
        &mut self,
        track: i32,
        index: usize,
        kind: u32,
        rate: f32,
        sync: bool,
        depth: f32,
        phase: f32,
        bipolar: bool,
        shape: u32,
        attack_ms: f32,
        release_ms: f32,
        value: f32,
    ) {
        let Some(tm) = self.mod_of(track) else { return };
        let Some(s) = tm.src.get_mut(index) else { return };
        let fin = |v: f32, lo: f32, hi: f32, def: f32| if v.is_finite() { v.clamp(lo, hi) } else { def };
        let kind = kind.min(kind::MACRO);
        // trocar o tipo recomeça o estado; o resto da configuração muda sem mexer nele
        if !s.live || s.kind != kind {
            *s = Source { kind, ..Source::NEW };
        }
        s.live = true;
        s.sync = sync;
        s.rate = if sync { fin(rate, 0.0, (DIVISIONS - 1) as f32, 4.0).floor() } else { fin(rate, RATE_MIN, RATE_MAX, 1.0) };
        s.depth = fin(depth, 0.0, if kind == kind::FOLLOWER { 8.0 } else { 1.0 }, 1.0);
        s.phase = fin(phase, 0.0, 1.0, 0.0);
        s.bipolar = bipolar;
        s.shape = shape.min(shape::SAMPLE_HOLD);
        s.attack_ms = fin(attack_ms, 0.0, 5000.0, 10.0);
        s.release_ms = fin(release_ms, 0.0, 5000.0, 100.0);
        s.value = fin(value, 0.0, 1.0, 0.0);
        self.mod_dirty = true;
        self.mod_busy = true;
    }

    /// Destino `dest` do modulador `index`: o alvo (`target_kind`/`slot`/`id` como em `auto_lane`,
    /// na mesma faixa do modulador), a quantidade (−1..1 do curso) e o curso (`min`, `max`,
    /// `scale`) do parâmetro, que o motor não conhece.
    #[allow(clippy::too_many_arguments)]
    pub fn mod_dest(&mut self, track: i32, index: usize, dest: usize, target_kind: u32, slot: u32, id: u32, amount: f32, min: f32, max: f32, scale: u32) {
        let target = Target::new(track, target_kind, slot, id);
        let Some(tm) = self.mod_of(track) else { return };
        let Some(d) = tm.dst.get_mut(index).and_then(|row| row.get_mut(dest)) else { return };
        d.live = true;
        d.target = target;
        d.amount = if amount.is_finite() { amount.clamp(-1.0, 1.0) } else { 0.0 };
        d.warp = Warp::sane(min, max, scale);
        self.mod_dirty = true;
        self.mod_busy = true;
    }

    /// O alvo tem modulação (algum destino vivo)?
    pub(crate) fn modulated(&self, t: Target) -> bool {
        if !self.mod_busy {
            return false;
        }
        let tm = if t.track < 0 { Some(&self.master_mod) } else { self.mods.get(t.track as usize) };
        tm.is_some_and(|tm| tm.has_dest_for(t))
    }

    /// A automação (ou a volta ao estático) mexeu no alvo: a modulação reaplica no próximo passo.
    pub(crate) fn mod_touch(&mut self, t: Target) {
        if !self.mod_busy {
            return;
        }
        if let Some(tm) = self.mod_of(t.track) {
            for d in tm.dst.iter_mut().flatten().filter(|d| d.target == t) {
                d.last_base = f32::NAN;
            }
        }
    }

    /// O play recomeça a fase dos LFOs.
    pub(crate) fn mod_restart(&mut self) {
        for tm in self.mods.iter_mut().chain(std::iter::once(&mut self.master_mod)) {
            for s in &mut tm.src {
                s.restart();
            }
        }
    }

    /// Devolve o alvo à base (o destino saiu ou mudou de alvo).
    fn unmod(&mut self, t: Target) {
        match t.kind {
            at::VOLUME => {
                if let Some(ch) = self.channel_mut(t.track) {
                    ch.mod_gain = None;
                }
            }
            at::PAN => {
                if let Some(ch) = self.channel_mut(t.track) {
                    ch.mod_pan = None;
                }
            }
            at::SEND if t.track >= 0 => {
                if let Some(s) = self.strips.get_mut(t.track as usize).and_then(|s| s.sends.get_mut(t.slot as usize)) {
                    s.mod_level = None;
                }
            }
            at::INSTRUMENT | at::EFFECT => {
                if self.automated(t) {
                    for lane in self.auto[..self.auto_count].iter_mut().filter(|l| l.target == t) {
                        lane.last = f32::NAN;
                    }
                } else {
                    self.restore(t);
                }
            }
            _ => {}
        }
    }

    /// Põe em dia o que os comandos mudaram: destinos que saíram ou trocaram de alvo devolvem o
    /// alvo à base, e as marcas de atividade se refazem.
    fn mod_reconcile(&mut self) {
        self.mod_dirty = false;
        let mut any = false;
        for ti in -1..self.mods.len() as i32 {
            let Some(tm) = self.mod_of(ti) else { continue };
            // alvos que perderam o último destino (no máximo um por destino)
            let mut freed = [None::<Target>; MAX_SOURCES * MAX_DESTS];
            let mut n = 0;
            for s in 0..MAX_SOURCES {
                for j in 0..MAX_DESTS {
                    let d = tm.dst[s][j];
                    let now = (tm.src[s].live && d.live).then_some(d.target);
                    if d.applied == now {
                        continue;
                    }
                    tm.dst[s][j].applied = now;
                    tm.dst[s][j].last_base = f32::NAN;
                    if let Some(t) = d.applied {
                        freed[n] = Some(t);
                        n += 1;
                    }
                }
            }
            tm.active = (0..MAX_SOURCES).any(|s| tm.src[s].live && tm.dst[s].iter().any(|d| d.live));
            tm.wants_level = tm.active && tm.src.iter().any(|s| s.live && s.kind == kind::FOLLOWER);
            for s in 0..MAX_SOURCES {
                // um modulador que saiu para de guardar estado velho
                if !tm.src[s].live {
                    tm.src[s] = Source::NEW;
                }
            }
            any |= tm.active;
            let tm = *tm;
            for t in freed[..n].iter().flatten() {
                // outro destino ainda vivo no alvo: ele segue mandando
                if !tm.dst.iter().flatten().any(|d| d.applied == Some(*t)) {
                    self.unmod(*t);
                }
            }
        }
        self.mod_busy = any;
    }

    /// A base do alvo: o valor do controle ou o da automação tocando; `None` se ainda não se sabe.
    fn mod_base(&self, t: Target) -> Option<f32> {
        let auto = || {
            if !self.playing {
                return None;
            }
            self.auto[..self.auto_count].iter().find(|l| l.target == t && !l.points.is_empty() && !l.last.is_nan()).map(|l| l.last)
        };
        let ch = |track: i32| match track {
            -1 => Some(&self.master),
            k if k >= 0 => self.tracks.get(k as usize),
            _ => None,
        };
        let v = match t.kind {
            at::VOLUME => ch(t.track).map(|c| c.auto_gain.unwrap_or(c.gain)),
            at::PAN => ch(t.track).map(|c| c.auto_pan.unwrap_or(c.pan)),
            at::SEND if t.track >= 0 => self.strips.get(t.track as usize).and_then(|s| s.sends.get(t.slot as usize)).map(|s| s.auto_level.unwrap_or(s.level)),
            at::INSTRUMENT if t.track >= 0 => {
                auto().or_else(|| self.lanes.get(t.track as usize).and_then(|l| l.statics.get(t.id as usize)).copied().filter(|v| !v.is_nan()))
            }
            at::EFFECT => auto().or_else(|| self.chain(t.track).and_then(|c| c.static_param(t.slot as usize, t.id))),
            _ => None,
        };
        v.filter(|v| v.is_finite())
    }

    /// Escreve o valor efetivo no alvo.
    fn mod_apply(&mut self, t: Target, v: f32) {
        match t.kind {
            at::VOLUME => {
                if let Some(ch) = self.channel_mut(t.track) {
                    ch.mod_gain = Some(v.max(0.0));
                }
            }
            at::PAN => {
                if let Some(ch) = self.channel_mut(t.track) {
                    ch.mod_pan = Some(v.clamp(-1.0, 1.0));
                }
            }
            at::SEND if t.track >= 0 => {
                if let Some(s) = self.strips.get_mut(t.track as usize).and_then(|s| s.sends.get_mut(t.slot as usize)) {
                    s.mod_level = Some(v.max(0.0));
                }
            }
            at::INSTRUMENT | at::EFFECT => self.apply_auto(t, v, true),
            _ => {}
        }
    }

    /// Um passo: avança os moduladores em `AUTO_STEP` quadros e escreve nos alvos. Chamado no
    /// começo de cada fatia, depois da automação (a modulação soma por cima do valor automatizado),
    /// mas só age nas fronteiras da grade do relógio do motor: a saída não depende de como o
    /// hospedeiro parte os blocos. `warm` aplica os valores de agora sem avançar o tempo (a partida
    /// do render).
    pub(crate) fn modulate(&mut self, warm: bool) {
        if !self.mod_busy {
            return;
        }
        if self.mod_dirty {
            self.mod_reconcile();
            if !self.mod_busy {
                return;
            }
        }
        if !warm && !self.clock.is_multiple_of(crate::AUTO_STEP as u64) {
            return;
        }
        let frames = if warm { 0 } else { crate::AUTO_STEP };
        let beat = self.transport_beat();
        let st = Step { frames, rate: self.rate, playing: self.playing, beat, bpm: self.tempo.bpm_at(beat) };
        for ti in -1..self.mods.len() as i32 {
            let Some(tm) = self.mod_of(ti) else { continue };
            if !tm.active {
                continue;
            }
            let mut vals = [0.0f32; MAX_SOURCES];
            for (s, (val, src)) in vals.iter_mut().zip(tm.src.iter_mut()).enumerate() {
                if src.live {
                    let salt = (ti + 1) as u32 * MAX_SOURCES as u32 + s as u32;
                    *val = src.tick(&st, salt);
                }
            }
            let tm = *tm;
            for s in 0..MAX_SOURCES {
                for j in 0..MAX_DESTS {
                    let d = tm.dst[s][j];
                    if d.applied.is_none() {
                        continue;
                    }
                    // só o primeiro destino de cada alvo escreve, com a soma de todos
                    let mut first = true;
                    let mut delta = 0.0f32;
                    for (s2, row) in tm.dst.iter().enumerate() {
                        for (j2, o) in row.iter().enumerate() {
                            if o.applied == Some(d.target) {
                                if (s2, j2) < (s, j) {
                                    first = false;
                                }
                                delta += o.amount * vals[s2];
                            }
                        }
                    }
                    if !first {
                        continue;
                    }
                    let Some(base) = self.mod_base(d.target) else {
                        self.set_last(ti, s, j, f32::NAN, f32::NAN);
                        continue;
                    };
                    let eff = if delta == 0.0 { base } else { d.warp.from_norm(d.warp.to_norm(base) + delta) };
                    if !eff.is_finite() {
                        continue;
                    }
                    let stepped = matches!(d.target.kind, at::INSTRUMENT | at::EFFECT);
                    if stepped && eff == d.last_eff && base == d.last_base {
                        continue;
                    }
                    self.set_last(ti, s, j, base, eff);
                    self.mod_apply(d.target, eff);
                }
            }
        }
    }

    fn set_last(&mut self, track: i32, s: usize, j: usize, base: f32, eff: f32) {
        if let Some(d) = self.mod_of(track).map(|tm| &mut tm.dst[s][j]) {
            d.last_base = base;
            d.last_eff = eff;
        }
    }
}
