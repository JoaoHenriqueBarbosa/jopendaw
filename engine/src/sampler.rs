//! Sampler (tipo 3): toca um áudio afinado pelas notas.
//!
//! Cada voz lê o áudio numa velocidade que é a razão entre a nota tocada e a nota base (`ROOT`,
//! com o ajuste fino `TUNE`) vezes a razão entre a taxa do áudio e a do motor, com interpolação
//! cúbica (Hermite de 4 pontos). Acima da altura original a voz consome mais de um quadro do
//! áudio por quadro de saída, e o que passasse da metade da taxa de saída voltaria como aliasing:
//! por isso, nesse caso, os quadros lidos passam antes por um passa-baixa Butterworth de 4ª ordem
//! no corte que a razão pede, e só então são interpolados.
//!
//! São [`VOICES`] vozes tocáveis e mais algumas vagas só para as vozes roubadas terminarem num
//! fade curto em vez de estalar. Tudo é pré-alocado em `new`; os eventos e o `render` não
//! alocam.
//!
//! O áudio chega como `Arc<Sample>` pelo `set_sample`. Trocar de áudio com notas soando não corta
//! nada: as vozes que já tocavam seguem lendo o áudio anterior (guardado até a próxima troca) e só
//! as notas novas usam o novo.

use std::sync::Arc;

use crate::dsp::{Adsr, Stage};
use crate::expression::PitchExpr;
use crate::instrument::{Instrument, sampler_param as param};
use crate::{Sample, hermite};

// zonas de teclado e velocidade (multi-sample) e fatiamento de loops: ver `sampler_zones.rs`
#[path = "sampler_zones.rs"]
mod zones;
pub use zones::{FIRST_SLICE_NOTE, MAX_SLICES, MAX_ZONES, SliceMode, ZoneDef, slice_points, slice_zones};
use zones::{MAX_GROUPS, Span, Zone};

/// Vozes tocáveis ao mesmo tempo.
pub const VOICES: usize = 16;
/// Vagas totais: as tocáveis e as que terminam o fade de uma voz roubada.
const SLOTS: usize = VOICES + 4;
/// Duração do fade de uma voz roubada.
const STEAL_FADE_SECS: f64 = 0.003;
/// Maior razão de leitura (quadros do áudio por quadro de saída). Limita o custo por voz: cada
/// quadro lido passa pelo filtro antialiasing. 16 = quatro oitavas acima (na mesma taxa).
const MAX_STEP: f64 = 16.0;
/// Constante de tempo da suavização do volume (sem degraus ao girar o botão).
const LEVEL_SECS: f64 = 0.01;

/// Coeficientes de um biquad (forma direta II transposta), normalizados por a0.
#[derive(Clone, Copy, Debug, Default)]
struct Biquad {
    b0: f32,
    b1: f32,
    b2: f32,
    a1: f32,
    a2: f32,
}

impl Biquad {
    /// Passa-baixa do RBJ com corte `nu` em ciclos por amostra (0..0,5).
    fn lowpass(nu: f64, q: f64) -> Self {
        let w = std::f64::consts::TAU * nu.clamp(1e-4, 0.49);
        let (sin, cos) = w.sin_cos();
        let alpha = sin / (2.0 * q);
        let a0 = 1.0 + alpha;
        let b1 = (1.0 - cos) / a0;
        Self { b0: (b1 * 0.5) as f32, b1: b1 as f32, b2: (b1 * 0.5) as f32, a1: (-2.0 * cos / a0) as f32, a2: ((1.0 - alpha) / a0) as f32 }
    }

    #[inline]
    fn run(&self, z: &mut [f32; 2], x: f32) -> f32 {
        let y = self.b0 * x + z[0];
        z[0] = self.b1 * x - self.a1 * y + z[1];
        z[1] = self.b2 * x - self.a2 * y;
        // trechos de silêncio digital no áudio levariam o estado a denormais (lentos no x86)
        if z[0].abs() < 1e-30 {
            z[0] = 0.0;
        }
        if z[1].abs() < 1e-30 {
            z[1] = 0.0;
        }
        y
    }

    /// Estado de regime para uma entrada constante `x` (ganho 1 em DC): ligar o filtro no meio
    /// de uma voz a partir daqui não dá o degrau que o estado zerado daria.
    fn settle(&self, z: &mut [f32; 2], x: f32) {
        z[0] = x * (1.0 - self.b0);
        z[1] = x * (self.b2 - self.a2);
    }
}

/// Butterworth de 4ª ordem: dois biquads com os Q dos pares de polos.
fn butterworth4(nu: f64) -> [Biquad; 2] {
    [Biquad::lowpass(nu, 0.541_196_1), Biquad::lowpass(nu, 1.306_563)]
}

struct Voice {
    on: bool,
    pitch: u8,
    /// Já recebeu o note off (ou foi solta por reataque/release_all).
    released: bool,
    /// Lê o áudio anterior à última troca.
    old: bool,
    stereo: bool,
    /// Quadros do áudio que a voz lê.
    len: usize,
    /// Próximo quadro do áudio a entrar no histórico.
    next: usize,
    /// Posição entre `hist[1]` e `hist[2]`, 0..1.
    frac: f64,
    /// Quadros do áudio por quadro de saída.
    step: f64,
    /// Últimos quatro quadros lidos (já filtrados) por canal: x[i-1], x[i], x[i+1], x[i+2], com
    /// a posição atual entre x[i] e x[i+1].
    hist: [[f32; 4]; 2],
    /// Antialiasing (só quando `step > 1`) e o estado dele por canal e estágio.
    aa: Option<[Biquad; 2]>,
    z: [[[f32; 2]; 2]; 2],
    /// Ganho da velocidade.
    gain: f32,
    env: Adsr,
    /// Ordem de disparo (para roubar a mais antiga).
    age: u64,
    /// Fade da voz roubada: ganho atual e quanto cai por quadro (0 = não está roubada).
    fade: f32,
    fade_step: f32,
    /// Trecho, loop, pan e afinação da zona que disparou a voz (`Span::whole` no sampler sem zonas).
    span: Span,
    /// O áudio da zona: a voz o guarda para que mexer nas zonas com ela soando não a corte.
    own: Option<Arc<Sample>>,
}

impl Voice {
    fn new(rate: f64) -> Self {
        Self {
            on: false,
            pitch: 0,
            released: false,
            old: false,
            stereo: false,
            len: 0,
            next: 0,
            frac: 0.0,
            step: 1.0,
            hist: [[0.0; 4]; 2],
            aa: None,
            z: [[[0.0; 2]; 2]; 2],
            gain: 1.0,
            env: Adsr::new(rate),
            age: 0,
            fade: 1.0,
            fade_step: 0.0,
            span: Span::whole(0),
            own: None,
        }
    }

    fn fading(&self) -> bool {
        self.fade_step > 0.0
    }

    /// Voz que ainda responde a note off e conta na polifonia.
    fn held(&self) -> bool {
        self.on && !self.fading()
    }

    fn start(&mut self, pitch: u8, gain: f32, step: f64, sample: &Sample, adsr: [f32; 4], age: u64) {
        self.on = true;
        self.pitch = pitch;
        self.released = false;
        self.old = false;
        self.stereo = sample.channels() > 1;
        self.len = sample.frames();
        self.gain = gain;
        self.age = age;
        self.fade = 1.0;
        self.fade_step = 0.0;
        self.frac = 0.0;
        self.hist = [[0.0; 4]; 2];
        self.z = [[[0.0; 2]; 2]; 2];
        self.aa = None;
        self.step = step;
        if step > 1.0 {
            self.aa = Some(butterworth4(0.45 / step));
        }
        // o histórico começa com o silêncio antes do áudio (x[-1]) e os três primeiros quadros
        self.next = self.span.first;
        let (c0, c1) = channels(sample, self.stereo);
        for _ in 0..3 {
            self.push(c0, c1);
        }
        self.env.set(adsr[0], adsr[1], adsr[2], adsr[3]);
        self.env.reset();
        self.env.gate_on();
    }

    /// Muda a razão de leitura com a voz soando (nota base ou afinação mexidas ao vivo).
    fn retune(&mut self, step: f64) {
        self.step = step;
        if step > 1.0 {
            let aa = butterworth4(0.45 / step);
            if self.aa.is_none() {
                for c in 0..2 {
                    let x = self.hist[c][3];
                    aa[0].settle(&mut self.z[c][0], x);
                    aa[1].settle(&mut self.z[c][1], x);
                }
            }
            self.aa = Some(aa);
        } else {
            self.aa = None;
        }
    }

    fn release(&mut self) {
        self.env.gate_off();
        self.released = true;
    }

    fn kill(&mut self) {
        self.on = false;
        self.env.reset();
        self.own = None;
    }

    /// Lê o próximo quadro do áudio (silêncio depois do fim) para o histórico.
    #[inline]
    fn push(&mut self, c0: &[f32], c1: &[f32]) {
        let k = self.next;
        self.next += 1;
        // loop da zona: o quadro `end` nunca é lido, a leitura volta para `start` (sem emenda)
        if let Some((start, end)) = self.span.looped
            && self.next >= end
        {
            self.next = start;
        }
        // depois do fim do trecho da zona é silêncio
        let inside = k < self.span.limit;
        let mut x = [if inside { c0.get(k).copied().unwrap_or(0.0) } else { 0.0 }, 0.0];
        let chans = if self.stereo {
            x[1] = if inside { c1.get(k).copied().unwrap_or(0.0) } else { 0.0 };
            2
        } else {
            1
        };
        if let Some(aa) = &self.aa {
            for (c, v) in x.iter_mut().enumerate().take(chans) {
                let [z0, z1] = &mut self.z[c];
                *v = aa[1].run(z1, aa[0].run(z0, *v));
            }
        }
        for (h, v) in self.hist.iter_mut().zip(x).take(chans) {
            *h = [h[1], h[2], h[3], v];
        }
    }

    /// Soma a voz no bloco. `l0` e `dl`: rampa do volume do instrumento no bloco.
    fn render(&mut self, sample: &Sample, left: &mut [f32], right: &mut [f32], l0: f32, dl: f32) {
        // sustentação zero: passado o decaimento a voz não soa mais, mas continuaria ocupando vaga
        if self.env.stage() == Stage::Sustain && self.env.value() <= 0.0 {
            self.kill();
            return;
        }
        let (c0, c1) = channels(sample, self.stereo);
        // a posição atual é `next - 3 + frac`; passou do último quadro, a voz acabou
        let end = self.span.limit + 3;
        for (i, (l, r)) in left.iter_mut().zip(right.iter_mut()).enumerate() {
            if self.next >= end {
                self.kill();
                return;
            }
            let e = self.env.next();
            if !self.env.active() {
                self.kill();
                return;
            }
            let mut g = e * self.gain * (l0 + dl * i as f32);
            if self.fade_step > 0.0 {
                self.fade -= self.fade_step;
                if self.fade <= 0.0 {
                    self.kill();
                    return;
                }
                g *= self.fade;
            }
            if self.span.fade > 0.0 {
                // fim do trecho da zona: desce a zero em ~1 ms, sem estalo nas fatias
                let left = self.span.limit as f64 - (self.next as f64 - 3.0 + self.frac);
                if left < self.span.fade {
                    g *= (left / self.span.fade).max(0.0) as f32;
                }
            }
            let t = self.frac as f32;
            let [a, b, c, d] = self.hist[0];
            let yl = hermite(a, b, c, d, t);
            let yr = if self.stereo {
                let [a, b, c, d] = self.hist[1];
                hermite(a, b, c, d, t)
            } else {
                yl
            };
            *l += yl * g * self.span.gl;
            *r += yr * g * self.span.gr;
            self.frac += self.step;
            while self.frac >= 1.0 {
                self.frac -= 1.0;
                self.push(c0, c1);
            }
        }
    }
}

fn channels(sample: &Sample, stereo: bool) -> (&[f32], &[f32]) {
    let c0 = sample.channel(0);
    (c0, if stereo { sample.channel(1) } else { c0 })
}

pub struct Sampler {
    rate: f64,
    sample: Option<Arc<Sample>>,
    /// O áudio anterior à última troca, enquanto vozes antigas ainda o leem.
    old: Option<Arc<Sample>>,
    voices: [Voice; SLOTS],
    /// Contador de disparos.
    age: u64,
    root: f32,
    /// Cents.
    tune: f32,
    /// Ataque, decaimento, sustentação e release.
    adsr: [f32; 4],
    one_shot: bool,
    velocity: f32,
    /// Volume pedido e o que está em uso (persegue o pedido).
    level: f32,
    level_now: f32,
    /// Quanto do caminho até o volume pedido sobra a cada quadro.
    level_pole: f32,
    fade_step: f32,
    /// Zonas (vazio = instrumento de sample único) e o contador do round-robin de cada grupo.
    zones: Vec<Zone>,
    rr: [u32; MAX_GROUPS],
    /// Pitch bend e vibrato da roda de modulação, e o desvio (semitons) já aplicado às vozes.
    expr: PitchExpr,
    bend_semis: f32,
}

impl Sampler {
    pub fn new(rate: f64) -> Self {
        // os padrões são os da tabela do app (`samplerParams` em instruments.dart)
        Self {
            rate,
            sample: None,
            old: None,
            voices: std::array::from_fn(|_| Voice::new(rate)),
            age: 0,
            root: 60.0,
            tune: 0.0,
            adsr: [0.002, 0.5, 1.0, 0.2],
            one_shot: false,
            velocity: 0.7,
            level: 0.8,
            level_now: 0.8,
            level_pole: (-1.0 / (LEVEL_SECS * rate)).exp() as f32,
            fade_step: (1.0 / (STEAL_FADE_SECS * rate)) as f32,
            zones: Vec::with_capacity(MAX_ZONES),
            rr: [0; MAX_GROUPS],
            expr: PitchExpr::new(rate as f32),
            bend_semis: 0.0,
        }
    }

    /// Quadros do áudio por quadro de saída para tocar `pitch` a partir de `sample`; `None` se o
    /// áudio não dá para tocar (taxa inválida, vazio).
    fn step_for(&self, pitch: u8, sample: &Sample) -> Option<f64> {
        self.step_at(pitch, sample, self.root, self.tune)
    }

    /// Como [`Sampler::step_for`] com a nota base e a afinação (cents) dadas: as da zona.
    fn step_at(&self, pitch: u8, sample: &Sample, root: f32, cents: f32) -> Option<f64> {
        let semis = pitch as f64 - root as f64 + cents as f64 / 100.0 + self.bend_semis as f64;
        let step = (semis / 12.0).exp2() * sample.rate() / self.rate;
        (step.is_finite() && step > 0.0 && sample.frames() > 0).then(|| step.min(MAX_STEP))
    }

    fn retune(&mut self) {
        for i in 0..SLOTS {
            let v = &self.voices[i];
            if !v.on {
                continue;
            }
            let src = v.own.as_deref().or(if v.old { self.old.as_deref() } else { self.sample.as_deref() });
            let (root, cents) = if v.span.zone { (v.span.root, v.span.cents + self.tune) } else { (self.root, self.tune) };
            if let Some(step) = src.and_then(|s| self.step_at(v.pitch, s, root, cents)) {
                self.voices[i].retune(step);
            }
        }
    }

    fn apply_env(&mut self) {
        let [a, d, s, r] = self.adsr;
        for v in &mut self.voices {
            v.env.set(a, d, s, r);
        }
    }
}

impl Instrument for Sampler {
    fn note_on(&mut self, pitch: u8, velocity: f32) {
        if !self.voices.iter().any(|w| w.on) {
            // sem voz soando o bend não andou: a nota nasce já no valor pedido
            self.expr.snap();
            self.bend_semis = self.expr.step(0);
        }
        if !self.zones.is_empty() {
            self.note_on_zones(pitch, velocity);
            return;
        }
        let Some(sample) = self.sample.as_deref() else { return };
        let Some(step) = self.step_for(pitch, sample) else { return };
        let v = velocity.clamp(0.0, 1.0);
        let gain = 1.0 - self.velocity + self.velocity * v * v;
        if !self.voices.iter().any(|w| w.on) {
            // a rampa do volume só anda com voz soando; a primeira nota já sai no volume pedido
            self.level_now = self.level;
        }
        let voices = &mut self.voices;

        // a mesma nota de novo: a anterior entra no release e a nova começa do início
        for voice in voices.iter_mut().filter(|w| w.held() && !w.released && w.pitch == pitch) {
            voice.release();
        }
        // sem vaga na polifonia: rouba a mais antiga, preferindo as que já foram soltas
        if voices.iter().filter(|w| w.held()).count() >= VOICES {
            let victim = voices.iter().enumerate().filter(|(_, w)| w.held()).min_by_key(|(_, w)| (!w.released, w.age)).map(|(i, _)| i);
            if let Some(i) = victim {
                voices[i].fade_step = self.fade_step;
            }
        }
        let slot = voices.iter().position(|w| !w.on).unwrap_or_else(|| {
            // todas as vagas ocupadas por fades: sai a que está mais perto do fim
            voices.iter().enumerate().filter(|(_, w)| w.fading()).min_by(|a, b| a.1.fade.total_cmp(&b.1.fade)).map_or(0, |(i, _)| i)
        });
        self.age += 1;
        voices[slot].span = Span::whole(sample.frames());
        voices[slot].own = None;
        voices[slot].start(pitch, gain, step, sample, self.adsr, self.age);
    }

    fn note_off(&mut self, pitch: u8) {
        // com zonas, quem manda é o modo da zona; sem elas, o parâmetro do instrumento
        let global = self.one_shot;
        for v in self.voices.iter_mut().filter(|v| v.held() && !v.released && v.pitch == pitch && !(if v.span.zone { v.span.one_shot } else { global })) {
            v.release();
        }
    }

    /// Solta todas, inclusive no modo "até o fim": parar o transporte não pode deixar um áudio
    /// longo tocando sozinho até acabar.
    fn release_all(&mut self) {
        for v in self.voices.iter_mut().filter(|v| v.held()) {
            v.release();
        }
    }

    fn silence(&mut self) {
        for v in &mut self.voices {
            v.kill();
        }
    }

    fn set_pitch_bend(&mut self, bend: f32) {
        self.expr.set_bend(bend);
    }

    fn set_mod_wheel(&mut self, value: f32) {
        self.expr.set_wheel(value);
    }

    fn set_param(&mut self, id: u32, value: f32) {
        if !value.is_finite() {
            return;
        }
        match id {
            param::BEND_RANGE => self.expr.set_range(value),
            param::VIBRATO_RANGE => self.expr.set_vibrato(value),
            param::ROOT => {
                self.root = value.round().clamp(0.0, 127.0);
                self.retune();
            }
            param::TUNE => {
                self.tune = value.clamp(-100.0, 100.0);
                self.retune();
            }
            param::ATTACK => {
                self.adsr[0] = value.clamp(0.0005, 10.0);
                self.apply_env();
            }
            param::DECAY => {
                self.adsr[1] = value.clamp(0.001, 10.0);
                self.apply_env();
            }
            param::SUSTAIN => {
                self.adsr[2] = value.clamp(0.0, 1.0);
                self.apply_env();
            }
            param::RELEASE => {
                self.adsr[3] = value.clamp(0.001, 10.0);
                self.apply_env();
            }
            param::LEVEL => {
                self.level = value.clamp(0.0, 1.5);
                // sem voz soando não há o que suavizar: a próxima nota já sai no volume novo
                if !self.active() {
                    self.level_now = self.level;
                }
            }
            param::ONE_SHOT => self.one_shot = value >= 0.5,
            param::VELOCITY => self.velocity = value.clamp(0.0, 1.0),
            _ => {}
        }
    }

    fn set_sample(&mut self, sample: Option<Arc<Sample>>) {
        let same = match (&self.sample, &sample) {
            (Some(a), Some(b)) => Arc::ptr_eq(a, b),
            (None, None) => true,
            _ => false,
        };
        if same {
            return;
        }
        // só há lugar para um áudio anterior: quem ainda lia o penúltimo para agora (raro: duas
        // trocas dentro de uma cauda)
        // (as vozes de zona guardam o próprio áudio e não dependem desta troca)
        for v in self.voices.iter_mut().filter(|v| v.on && v.old && !v.span.zone) {
            v.kill();
        }
        let mut sounding = false;
        for v in self.voices.iter_mut().filter(|v| v.on && !v.span.zone) {
            v.old = true;
            sounding = true;
        }
        let previous = std::mem::replace(&mut self.sample, sample);
        // ninguém soando: o anterior já pode ir embora (com vozes, fica até a próxima troca ou até
        // o instrumento sair, para não liberar memória no meio do `render`)
        self.old = if sounding { previous } else { None };
    }

    fn zones_clear(&mut self) {
        self.clear_zones();
    }

    fn zone_add(&mut self, def: ZoneDef, sample_id: u32, sample: Option<Arc<Sample>>) {
        self.add_zone(def, sample_id, sample);
    }

    fn zone_sample(&mut self, id: u32, sample: Option<Arc<Sample>>) {
        self.bind_zone_sample(id, sample);
    }

    fn render(&mut self, left: &mut [f32], right: &mut [f32]) {
        let n = left.len().min(right.len());
        if n == 0 {
            return;
        }
        // afinação: o bend e o vibrato andam por bloco; só reafina quando mudou de verdade
        let semis = self.expr.step(n);
        if (semis - self.bend_semis).abs() > 1e-4 {
            self.bend_semis = semis;
            self.retune();
        }
        // volume: rampa linear no bloco até onde o polo de suavização chegaria
        let l0 = self.level_now;
        let l1 = if (l0 - self.level).abs() < 1e-5 { self.level } else { self.level + (l0 - self.level) * self.level_pole.powi(n as i32) };
        self.level_now = l1;
        let dl = (l1 - l0) / n as f32;

        let (current, old) = (self.sample.as_deref(), self.old.as_deref());
        for v in self.voices.iter_mut().filter(|v| v.on) {
            // a voz de zona lê o áudio que guarda (a zona pode ter mudado ou perdido o áudio)
            let own = v.own.take();
            match own.as_deref().or(if v.old { old } else { current }) {
                Some(s) => v.render(s, &mut left[..n], &mut right[..n], l0, dl),
                None => v.kill(),
            }
            if v.on {
                v.own = own;
            }
        }
    }

    fn active(&self) -> bool {
        self.voices.iter().any(|v| v.on)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const RATE: f64 = 48_000.0;

    /// Sampler com o áudio dado, volume 1 e sem sensibilidade à velocidade (ganho 1).
    fn sampler(channels: Vec<Vec<f32>>, rate: f64) -> Sampler {
        let mut s = Sampler::new(RATE);
        s.set_param(param::LEVEL, 1.0);
        s.set_param(param::VELOCITY, 0.0);
        s.set_param(param::ATTACK, 0.0005);
        s.set_sample(Some(Arc::new(Sample::new(channels, rate))));
        s
    }

    fn render(s: &mut Sampler, frames: usize) -> (Vec<f32>, Vec<f32>) {
        let (mut l, mut r) = (vec![0.0; frames], vec![0.0; frames]);
        for (cl, cr) in l.chunks_mut(128).zip(r.chunks_mut(128)) {
            s.render(cl, cr);
        }
        (l, r)
    }

    fn ramp(frames: usize) -> Vec<f32> {
        (0..frames).map(|i| i as f32 / frames as f32).collect()
    }

    /// Posição de leitura de uma voz, em quadros do áudio.
    fn position(v: &Voice) -> f64 {
        v.next as f64 - 3.0 + v.frac
    }

    fn sine(freq: f64, frames: usize, rate: f64) -> Vec<f32> {
        (0..frames).map(|i| (std::f64::consts::TAU * freq * i as f64 / rate).sin() as f32).collect()
    }

    fn zero_crossings(x: &[f32]) -> usize {
        x.windows(2).filter(|w| w[0] <= 0.0 && w[1] > 0.0).count()
    }

    #[test]
    fn sem_sample_e_silencio() {
        let mut s = Sampler::new(RATE);
        s.note_on(60, 1.0);
        assert!(!s.active());
        let (l, r) = render(&mut s, 256);
        assert!(l.iter().chain(&r).all(|&x| x == 0.0));
    }

    #[test]
    fn nota_base_toca_na_velocidade_original() {
        let mut s = sampler(vec![ramp(10_000)], RATE);
        s.note_on(60, 1.0);
        render(&mut s, 1000);
        let v = s.voices.iter().find(|v| v.on).unwrap();
        assert_eq!(v.step, 1.0);
        assert!(v.aa.is_none());
        assert!((position(v) - 1000.0).abs() < 1e-9);
    }

    #[test]
    fn oitava_acima_le_o_dobro_de_velocidade() {
        let mut s = sampler(vec![ramp(10_000)], RATE);
        s.note_on(72, 1.0);
        let (l, _) = render(&mut s, 1000);
        let v = s.voices.iter().find(|v| v.on).unwrap();
        assert!((v.step - 2.0).abs() < 1e-12);
        assert!((position(v) - 2000.0).abs() < 1e-9, "{}", position(v));
        // depois do ataque a rampa sai com o dobro da inclinação (o filtro só atrasa a rampa)
        let slope = (l[900] - l[800]) / 100.0;
        assert!((slope - 2.0 / 10_000.0).abs() < 1e-7, "{slope}");
    }

    #[test]
    fn afinacao_e_taxa_do_audio_entram_na_razao() {
        // áudio a 24 kHz no motor a 48 kHz, nota base 60 e +100 cents, tocando 59: altura original
        let mut s = sampler(vec![ramp(10_000)], 24_000.0);
        s.set_param(param::TUNE, 100.0);
        s.note_on(59, 1.0);
        let v = s.voices.iter().find(|v| v.on).unwrap();
        assert!((v.step - 0.5).abs() < 1e-12);
        // mexer na nota base com a voz soando reafina a voz
        s.set_param(param::ROOT, 48.0);
        let v = s.voices.iter().find(|v| v.on).unwrap();
        assert!((v.step - 1.0).abs() < 1e-12);
    }

    #[test]
    fn senoide_sobe_uma_oitava() {
        let mut s = sampler(vec![sine(1000.0, 48_000, RATE)], RATE);
        s.note_on(72, 1.0);
        let (l, _) = render(&mut s, 12_100);
        // 1 kHz tocado uma oitava acima: 2000 ciclos/s, 500 em 0,25 s
        let n = zero_crossings(&l[100..]);
        assert!((495..=505).contains(&n), "{n}");
    }

    #[test]
    fn antialiasing_segura_o_que_passaria_de_nyquist() {
        // 15 kHz duas oitavas acima iria a 60 kHz e voltaria dobrado em 12 kHz; com o filtro
        // quase nada sobra
        let mut s = sampler(vec![sine(15_000.0, 48_000, RATE)], RATE);
        s.note_on(84, 1.0);
        let (l, _) = render(&mut s, 4000);
        let rms = (l[1000..4000].iter().map(|x| x * x).sum::<f32>() / 3000.0).sqrt();
        assert!(rms < 0.01, "{rms}");
        // sem subir a altura, o mesmo áudio passa inteiro
        let mut s = sampler(vec![sine(15_000.0, 48_000, RATE)], RATE);
        s.note_on(60, 1.0);
        let (l, _) = render(&mut s, 4000);
        let rms = (l[1000..4000].iter().map(|x| x * x).sum::<f32>() / 3000.0).sqrt();
        assert!(rms > 0.6, "{rms}");
    }

    #[test]
    fn estereo_le_os_dois_canais() {
        let mut s = sampler(vec![vec![0.5; 2000], vec![-0.25; 2000]], RATE);
        s.note_on(60, 1.0);
        let (l, r) = render(&mut s, 500);
        assert!((l[400] - 0.5).abs() < 1e-4 && (r[400] + 0.25).abs() < 1e-4, "{} {}", l[400], r[400]);
    }

    #[test]
    fn fim_do_audio_encerra_a_voz() {
        let mut s = sampler(vec![vec![0.5; 1000]], RATE);
        s.note_on(60, 1.0);
        let (l, _) = render(&mut s, 2000);
        assert!(!s.active());
        assert!(l[500] > 0.4);
        assert!(l[1001..].iter().all(|&x| x == 0.0));
    }

    #[test]
    fn note_off_solta_com_release() {
        let mut s = sampler(vec![vec![0.5; 48_000]], RATE);
        s.set_param(param::RELEASE, 0.01);
        s.note_on(60, 1.0);
        render(&mut s, 1000);
        s.note_off(60);
        let (l, _) = render(&mut s, 2000);
        assert!(l[10] > 0.3, "o release começa do nível atual, sem degrau: {}", l[10]);
        assert!(!s.active());
    }

    #[test]
    fn one_shot_ignora_note_off() {
        let mut s = sampler(vec![vec![0.5; 4800]], RATE);
        s.set_param(param::ONE_SHOT, 1.0);
        s.set_param(param::RELEASE, 0.001);
        s.note_on(60, 1.0);
        render(&mut s, 100);
        s.note_off(60);
        let (l, _) = render(&mut s, 2000);
        assert!(s.active());
        assert!((l[1999] - 0.5).abs() < 1e-4);
        // toca até o fim do áudio
        render(&mut s, 3000);
        assert!(!s.active());
    }

    #[test]
    fn velocidade_muda_o_volume() {
        let mut s = sampler(vec![vec![0.5; 4800]], RATE);
        s.set_param(param::VELOCITY, 1.0);
        s.note_on(60, 0.5);
        let (l, _) = render(&mut s, 500);
        assert!((l[400] - 0.5 * 0.25).abs() < 1e-4, "{}", l[400]);
    }

    #[test]
    fn mesma_nota_reataca() {
        let mut s = sampler(vec![vec![0.5; 48_000]], RATE);
        s.note_on(60, 1.0);
        render(&mut s, 1000);
        s.note_on(60, 1.0);
        let on: Vec<_> = s.voices.iter().filter(|v| v.on).collect();
        assert_eq!(on.len(), 2);
        assert_eq!(on.iter().filter(|v| v.released).count(), 1, "a anterior entra no release");
        let fresh = on.iter().find(|v| !v.released).unwrap();
        assert_eq!(position(fresh), 0.0);
    }

    #[test]
    fn rouba_a_voz_mais_antiga_sem_estalo() {
        let mut s = sampler(vec![vec![0.5; 48_000]], RATE);
        for p in 0..VOICES as u8 {
            s.note_on(40 + p, 1.0);
            render(&mut s, 10);
        }
        assert_eq!(s.voices.iter().filter(|v| v.held()).count(), VOICES);
        s.note_on(90, 1.0);
        assert_eq!(s.voices.iter().filter(|v| v.held()).count(), VOICES);
        let stolen = s.voices.iter().find(|v| v.fading()).unwrap();
        assert_eq!(stolen.pitch, 40, "a mais antiga");
        // o fade dura alguns milissegundos e libera a vaga
        render(&mut s, 200);
        assert!(s.voices.iter().filter(|v| v.on).all(|v| !v.fading()));
        // com uma voz já solta, ela é a roubada antes das presas
        s.note_off(45);
        s.note_on(91, 1.0);
        assert_eq!(s.voices.iter().find(|v| v.fading()).unwrap().pitch, 45);
    }

    #[test]
    fn muitas_notas_de_uma_vez_nao_estouram_as_vagas() {
        let mut s = sampler(vec![vec![0.5; 48_000]], RATE);
        for p in 0..100u8 {
            s.note_on(p, 1.0);
        }
        assert!(s.voices.iter().filter(|v| v.held()).count() <= VOICES);
        let (l, _) = render(&mut s, 512);
        assert!(l.iter().all(|x| x.is_finite()));
    }

    #[test]
    fn trocar_o_audio_nao_corta_quem_soa() {
        let mut s = sampler(vec![vec![0.5; 48_000]], RATE);
        s.note_on(60, 1.0);
        render(&mut s, 500);
        s.set_sample(Some(Arc::new(Sample::new(vec![vec![-0.25; 48_000]], RATE))));
        s.note_on(64, 1.0);
        let (l, _) = render(&mut s, 500);
        // a voz antiga segue no áudio antigo (0,5) e a nova toca o novo (−0,25)
        assert!((l[400] - 0.25).abs() < 1e-3, "{}", l[400]);
        // sem áudio nenhum as notas novas não soam, mas as antigas terminam
        s.set_sample(None);
        s.note_on(67, 1.0);
        assert_eq!(s.voices.iter().filter(|v| v.on).count(), 1);
    }

    #[test]
    fn release_all_e_silence() {
        let mut s = sampler(vec![vec![0.5; 48_000]], RATE);
        s.set_param(param::ONE_SHOT, 1.0);
        s.set_param(param::RELEASE, 0.005);
        s.note_on(60, 1.0);
        s.note_on(62, 1.0);
        s.release_all();
        render(&mut s, 2000);
        assert!(!s.active(), "até o one-shot solta no stop");
        s.note_on(60, 1.0);
        s.silence();
        assert!(!s.active());
    }

    #[test]
    fn volume_muda_sem_degrau() {
        let mut s = sampler(vec![vec![0.5; 48_000]], RATE);
        s.note_on(60, 1.0);
        render(&mut s, 1000);
        s.set_param(param::LEVEL, 0.0);
        let (l, _) = render(&mut s, 4800);
        let max_jump = l.windows(2).map(|w| (w[1] - w[0]).abs()).fold(0.0, f32::max);
        assert!(max_jump < 0.01, "{max_jump}");
        assert!(l[4799].abs() < 1e-3);
    }

    // ------------------------------------------------------------ contrato com o app

    /// `samplerParams` (instruments.dart) e `SamplerId` (presets.dart) contra o motor: os mesmos ids,
    /// e cada limite e padrão da tabela é o que `set_param` limita e o `new` já traz.
    #[test]
    fn tabela_e_ids_iguais_aos_do_app() {
        use crate::instrument::contract;
        let Some(src) = contract::source() else { return };
        // o valor que o motor guardou de cada id (o alcance do bend mora em `PitchExpr`, conferido à parte)
        let read = |s: &Sampler, id: u32| -> f32 {
            match id {
                param::ROOT => s.root,
                param::TUNE => s.tune,
                param::ATTACK => s.adsr[0],
                param::DECAY => s.adsr[1],
                param::SUSTAIN => s.adsr[2],
                param::RELEASE => s.adsr[3],
                param::LEVEL => s.level,
                param::ONE_SHOT => f32::from(s.one_shot),
                param::VELOCITY => s.velocity,
                other => panic!("id {other} sem leitura no teste"),
            }
        };
        let rows = contract::rows(&src, "samplerParams");
        let ids: Vec<usize> = rows.iter().map(|r| r.0).collect();
        assert_eq!(ids.len(), 11, "os ids do sampler: {ids:?}");
        for id in 0..=param::VIBRATO_RANGE {
            assert!(ids.contains(&(id as usize)), "id {id} do sampler sem linha no app");
        }
        for (id, (min, max, def, _)) in rows {
            let id = id as u32;
            if id == param::BEND_RANGE {
                assert_eq!((min, max, def), (0.0, crate::expression::MAX_BEND_RANGE, crate::expression::DEFAULT_BEND_RANGE), "alcance do bend");
                continue;
            }
            if id == param::VIBRATO_RANGE {
                assert_eq!((min, max, def), (0.0, crate::expression::MAX_VIBRATO, crate::expression::DEFAULT_VIBRATO), "alcance do vibrato");
                continue;
            }
            let mut s = Sampler::new(RATE);
            assert_eq!(read(&s, id), def, "padrão do id {id}");
            s.set_param(id, min - 1e6);
            assert_eq!(read(&s, id), min, "mínimo do id {id}");
            s.set_param(id, max + 1e6);
            assert_eq!(read(&s, id), max, "máximo do id {id}");
        }
        // `SamplerId` do app: cada constante é o id do motor de mesmo nome
        let consts = [
            ("ROOT", param::ROOT),
            ("ATTACK", param::ATTACK),
            ("DECAY", param::DECAY),
            ("SUSTAIN", param::SUSTAIN),
            ("RELEASE", param::RELEASE),
            ("LEVEL", param::LEVEL),
            ("ONE_SHOT", param::ONE_SHOT),
            ("TUNE", param::TUNE),
            ("VELOCITY", param::VELOCITY),
            ("BEND_RANGE", param::BEND_RANGE),
            ("VIBRATO_RANGE", param::VIBRATO_RANGE),
        ];
        for (name, value) in contract::dart_ids("SamplerId") {
            let name = contract::screaming(&name);
            let engine = consts.iter().find(|c| c.0 == name).unwrap_or_else(|| panic!("SamplerId.{name} não existe no motor"));
            assert_eq!(engine.1, value, "SamplerId.{name}");
        }
    }
}
