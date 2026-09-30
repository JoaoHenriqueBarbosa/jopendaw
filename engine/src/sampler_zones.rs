//! Zonas do sampler (multi-sample) e fatiamento de loops.
//!
//! Sem zonas o sampler é o de sempre: um áudio, uma nota base. Com pelo menos uma zona ele vira um
//! instrumento multi-sample: cada nota dispara **todas** as zonas cuja faixa de notas e cuja faixa
//! de velocidade a contêm (zonas sobrepostas empilham, é assim que se fazem camadas de velocidade;
//! uma nota que nenhuma zona cobre não soa). Cada zona tem o seu áudio, nota base, afinação fina,
//! ganho, pan, modo (sustentado ou até o fim), trecho (início e fim, em segundos do áudio) e, no modo
//! sustentado, um loop dentro do trecho. Zonas do mesmo grupo (> 0) que casam com a mesma nota
//! alternam a cada nota (round-robin): só uma delas toca por vez.
//!
//! O áudio de uma zona vem por id (o de `Engine::load_sample`). A zona pode ser criada antes de o
//! áudio chegar, e o áudio pode ser descartado depois: a zona sem áudio simplesmente não soa. A voz
//! que já tocava guarda o próprio `Arc<Sample>` e o próprio trecho, então mexer nas zonas (ou
//! descartar o áudio) com notas soando não corta ninguém.
//!
//! O que a thread de áudio faz aqui não aloca: a lista de zonas é reservada inteira em
//! `Sampler::new` (até [`MAX_ZONES`]; o que passar é ignorado) e o disparo usa só arrays na pilha.
//!
//! Este arquivo é um submódulo de `sampler.rs` (enxerga os campos privados dele).

use std::sync::Arc;

use super::{Sampler, VOICES};
use crate::Sample;

/// Zonas por sampler.
pub const MAX_ZONES: usize = 128;
/// Grupos de round-robin: 1..[`MAX_GROUPS`] (0 = sem round-robin).
pub(super) const MAX_GROUPS: usize = 64;
/// Fatias de uma vez (uma nota cada, a partir de [`FIRST_SLICE_NOTE`]; 24 + 96 − 1 = 119 < 127).
pub const MAX_SLICES: usize = 96;
/// Primeira nota das zonas de fatias: C1.
pub const FIRST_SLICE_NOTE: u8 = 24;
/// Descida no fim do trecho de uma zona, em segundos (sem estalo nas fatias).
const END_FADE_SECS: f64 = 0.001;

/// Definição de uma zona, como o app manda (`zone_add`).
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct ZoneDef {
    /// Nota em que o áudio soa na altura original.
    pub root: u8,
    /// Faixa de notas (inclusive), 0..=127.
    pub lo: u8,
    pub hi: u8,
    /// Faixa de velocidade (inclusive), 1..=127.
    pub vlo: u8,
    pub vhi: u8,
    /// Afinação fina em cents (−1200..1200).
    pub cents: f32,
    /// Ganho da zona em dB (−60..24).
    pub gain_db: f32,
    /// Pan, −1..1 (balanço: 0 não muda o nível, ±1 zera o lado oposto).
    pub pan: f32,
    /// Toca o trecho até o fim ignorando o note off (bateria, fatias).
    pub one_shot: bool,
    /// Grupo de round-robin (0 = nenhum).
    pub group: u8,
    /// Trecho do áudio em segundos; `end` ≤ 0 é o fim do áudio.
    pub start: f64,
    pub end: f64,
    /// Loop do trecho em segundos (só no modo sustentado): vale quando `loop_end > loop_start`.
    pub loop_start: f64,
    pub loop_end: f64,
}

impl Default for ZoneDef {
    fn default() -> Self {
        Self {
            root: 60,
            lo: 0,
            hi: 127,
            vlo: 1,
            vhi: 127,
            cents: 0.0,
            gain_db: 0.0,
            pan: 0.0,
            one_shot: false,
            group: 0,
            start: 0.0,
            end: 0.0,
            loop_start: 0.0,
            loop_end: 0.0,
        }
    }
}

impl ZoneDef {
    /// Valores dentro das faixas (faixas invertidas trocam de ponta; número não finito vira 0).
    pub fn sanitized(self) -> Self {
        let num = |v: f32, lo: f32, hi: f32| if v.is_finite() { v.clamp(lo, hi) } else { 0.0 };
        let time = |v: f64| if v.is_finite() && v > 0.0 { v } else { 0.0 };
        let (lo, hi) = (self.lo.min(127), self.hi.min(127));
        let (vlo, vhi) = (self.vlo.clamp(1, 127), self.vhi.clamp(1, 127));
        Self {
            root: self.root.min(127),
            lo: lo.min(hi),
            hi: lo.max(hi),
            vlo: vlo.min(vhi),
            vhi: vlo.max(vhi),
            cents: num(self.cents, -1200.0, 1200.0),
            gain_db: num(self.gain_db, -60.0, 24.0),
            pan: num(self.pan, -1.0, 1.0),
            one_shot: self.one_shot,
            group: self.group.min(MAX_GROUPS as u8 - 1),
            start: time(self.start),
            end: time(self.end),
            loop_start: time(self.loop_start),
            loop_end: time(self.loop_end),
        }
    }

    /// A nota e a velocidade (1..=127) caem na zona.
    pub fn matches(&self, pitch: u8, velocity: u8) -> bool {
        (self.lo..=self.hi).contains(&pitch) && (self.vlo..=self.vhi).contains(&velocity)
    }
}

/// O trecho de áudio (em quadros) e o resto do que uma voz precisa saber da zona que a disparou.
#[derive(Debug, Clone, Copy)]
pub(super) struct Span {
    /// Primeiro quadro tocado e primeiro quadro que já não toca.
    pub first: usize,
    pub limit: usize,
    /// Loop `[início, fim)` em quadros, dentro do trecho.
    pub looped: Option<(usize, usize)>,
    /// Ganho de cada lado (pan da zona); 1 no sampler sem zonas.
    pub gl: f32,
    pub gr: f32,
    /// A voz ignora o note off.
    pub one_shot: bool,
    /// A voz veio de uma zona (nota base e afinação abaixo valem no lugar dos do instrumento).
    pub zone: bool,
    pub root: f32,
    pub cents: f32,
    /// Duração da descida no fim do trecho, em quadros (0 = sem descida).
    pub fade: f64,
}

impl Span {
    /// O áudio inteiro, sem loop: o sampler de sample único.
    pub fn whole(frames: usize) -> Self {
        Self { first: 0, limit: frames, looped: None, gl: 1.0, gr: 1.0, one_shot: false, zone: false, root: 0.0, cents: 0.0, fade: 0.0 }
    }

    /// Os quadros que a zona toca no áudio dado; `None` se o trecho não tem nenhum quadro.
    fn resolve(def: &ZoneDef, sample: &Sample) -> Option<Self> {
        let (rate, frames) = (sample.rate(), sample.frames());
        if frames == 0 || !(rate.is_finite() && rate > 0.0) {
            return None;
        }
        let at = |t: f64| (t * rate).round().clamp(0.0, frames as f64) as usize;
        let first = at(def.start);
        let limit = if def.end > 0.0 { at(def.end) } else { frames };
        if first >= limit {
            return None;
        }
        let looped = if !def.one_shot && def.loop_end > def.loop_start && def.loop_end > 0.0 {
            let (ls, le) = (at(def.loop_start).max(first), at(def.loop_end).min(limit));
            (le > ls).then_some((ls, le))
        } else {
            None
        };
        let fade = if looped.is_some() { 0.0 } else { (END_FADE_SECS * rate).min((limit - first) as f64 / 2.0) };
        Some(Self {
            first,
            limit,
            looped,
            gl: 1.0 - def.pan.max(0.0),
            gr: 1.0 + def.pan.min(0.0),
            one_shot: def.one_shot,
            zone: true,
            root: f32::from(def.root),
            cents: def.cents,
            fade,
        })
    }
}

/// Uma zona do sampler.
pub(super) struct Zone {
    def: ZoneDef,
    sample_id: u32,
    sample: Option<Arc<Sample>>,
    /// O trecho já convertido em quadros (`None` sem áudio ou com trecho vazio).
    span: Option<Span>,
}

impl Zone {
    fn new(def: ZoneDef, sample_id: u32, sample: Option<Arc<Sample>>) -> Self {
        let mut z = Self { def, sample_id, sample, span: None };
        z.resolve();
        z
    }

    fn resolve(&mut self) {
        self.span = self.sample.as_deref().and_then(|s| Span::resolve(&self.def, s));
    }

    fn plays(&self, pitch: u8, velocity: u8) -> bool {
        self.span.is_some() && self.def.matches(pitch, velocity)
    }
}

impl Sampler {
    pub(super) fn clear_zones(&mut self) {
        self.zones.clear();
        self.rr = [0; MAX_GROUPS];
    }

    pub(super) fn add_zone(&mut self, def: ZoneDef, sample_id: u32, sample: Option<Arc<Sample>>) {
        // a lista foi reservada inteira: passar do limite descarta em vez de alocar
        if self.zones.len() < MAX_ZONES {
            self.zones.push(Zone::new(def.sanitized(), sample_id, sample));
        }
    }

    pub(super) fn bind_zone_sample(&mut self, id: u32, sample: Option<Arc<Sample>>) {
        for z in self.zones.iter_mut().filter(|z| z.sample_id == id) {
            z.sample = sample.clone();
            z.resolve();
        }
    }

    /// Uma vaga de voz para começar uma nota: rouba a mais antiga se a polifonia está cheia.
    fn take_slot(&mut self) -> usize {
        let voices = &mut self.voices;
        if voices.iter().filter(|w| w.held()).count() >= VOICES {
            let victim = voices.iter().enumerate().filter(|(_, w)| w.held()).min_by_key(|(_, w)| (!w.released, w.age)).map(|(i, _)| i);
            if let Some(i) = victim {
                voices[i].fade_step = self.fade_step;
            }
        }
        voices.iter().position(|w| !w.on).unwrap_or_else(|| {
            // todas as vagas ocupadas por fades: sai a que está mais perto do fim
            voices.iter().enumerate().filter(|(_, w)| w.fading()).min_by(|a, b| a.1.fade.total_cmp(&b.1.fade)).map_or(0, |(i, _)| i)
        })
    }

    /// Nota com zonas: dispara as que casam (uma por grupo de round-robin).
    pub(super) fn note_on_zones(&mut self, pitch: u8, velocity: f32) {
        let v = if velocity.is_finite() { velocity.clamp(0.0, 1.0) } else { 0.0 };
        let vel = ((v * 127.0).round() as u8).clamp(1, 127);

        // round-robin: quantas zonas de cada grupo casam e qual delas é a da vez
        let mut counts = [0u8; MAX_GROUPS];
        for z in self.zones.iter().filter(|z| z.plays(pitch, vel)) {
            counts[usize::from(z.def.group)] += 1;
        }
        let mut seen = [0u8; MAX_GROUPS];
        let mut picked = [0u8; MAX_ZONES];
        let mut n = 0;
        for (i, z) in self.zones.iter().enumerate().filter(|(_, z)| z.plays(pitch, vel)) {
            let g = usize::from(z.def.group);
            if g > 0 {
                let turn = seen[g];
                seen[g] += 1;
                if u32::from(turn) != self.rr[g] % u32::from(counts[g]) {
                    continue;
                }
            }
            picked[n] = i as u8;
            n += 1;
        }
        for (turn, &count) in self.rr.iter_mut().zip(&counts).skip(1) {
            if count > 0 {
                *turn = turn.wrapping_add(1);
            }
        }
        if n == 0 {
            return;
        }

        if !self.voices.iter().any(|w| w.on) {
            // a rampa do volume só anda com voz soando; a primeira nota já sai no volume pedido
            self.level_now = self.level;
        }
        // a mesma nota de novo: as anteriores entram no release e as novas começam do início
        for voice in self.voices.iter_mut().filter(|w| w.held() && !w.released && w.pitch == pitch) {
            voice.release();
        }
        let velocity_gain = 1.0 - self.velocity + self.velocity * v * v;
        for &i in &picked[..n] {
            let z = &self.zones[usize::from(i)];
            let (Some(sample), Some(span)) = (z.sample.clone(), z.span) else { continue };
            let Some(step) = self.step_at(pitch, &sample, span.root, span.cents + self.tune) else { continue };
            let gain = velocity_gain * 10f32.powf(z.def.gain_db / 20.0);
            let slot = self.take_slot();
            self.age += 1;
            let voice = &mut self.voices[slot];
            voice.span = span;
            voice.start(pitch, gain, step, &sample, self.adsr, self.age);
            voice.own = Some(sample);
        }
    }
}

#[cfg(test)]
#[path = "sampler_zones_tests.rs"]
mod tests;

// ------------------------------------------------------------------------------------ fatiamento

/// Como escolher os pontos de corte de [`slice_points`].
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum SliceMode {
    /// N fatias iguais (1..=[`MAX_SLICES`]).
    Count(usize),
    /// Um corte em cada transiente. Sensibilidade 0..1: com 1 pega também os ataques fracos.
    Transients(f32),
}

/// Tamanho do passo do envelope dos transientes.
const HOP_SECS: f64 = 0.005;
/// Distância mínima entre dois cortes.
const MIN_GAP_SECS: f64 = 0.05;
/// Os cortes a menos disto do começo ou do fim do áudio não valem.
const EDGE_SECS: f64 = 0.01;

/// Os pontos de corte de um áudio, em segundos, crescentes; o primeiro é sempre 0 (áudio vazio: nenhum).
/// Cada ponto é o início de uma fatia, que vai até o ponto seguinte (a última, até o fim).
pub fn slice_points(channels: &[Vec<f32>], rate: f64, mode: SliceMode) -> Vec<f64> {
    let n = channels.iter().map(Vec::len).min().unwrap_or(0);
    if n == 0 || !(rate.is_finite() && rate > 0.0) {
        return Vec::new();
    }
    let frames = match mode {
        SliceMode::Count(k) => {
            let k = k.clamp(1, MAX_SLICES).min(n);
            let mut p: Vec<usize> = (0..k).map(|i| (i as f64 * n as f64 / k as f64).round() as usize).collect();
            p.dedup();
            p
        }
        SliceMode::Transients(sensitivity) => transients(channels, n, rate, sensitivity),
    };
    frames.into_iter().map(|f| f as f64 / rate).collect()
}

/// Cortes por transientes, em quadros (o primeiro é 0).
///
/// O envelope é a energia do sinal e da derivada dele em log (mesma ideia do detector de andamento,
/// a derivada pega cliques e chimbais) a cada 5 ms; o fluxo positivo dele é comparado com a média
/// local (±0,2 s) e com o maior pico, e só os máximos locais distantes 50 ms passam. O ponto de corte
/// é refinado no áudio: o primeiro quadro em que o sinal passa de 10% do pico do ataque, recuado até o
/// cruzamento de zero mais próximo (até 2 ms), para o corte não estalar.
fn transients(channels: &[Vec<f32>], n: usize, rate: f64, sensitivity: f32) -> Vec<usize> {
    let mut points = vec![0usize];
    let hop = ((rate * HOP_SECS).round() as usize).max(1);
    let nf = n / hop;
    if nf < 4 {
        return points;
    }
    let m = |i: usize| -> f64 { channels.iter().map(|c| f64::from(c[i])).sum::<f64>() / channels.len() as f64 };
    let mono: Vec<f32> = (0..n).map(|i| m(i) as f32).collect();
    let level: Vec<f64> = (0..nf)
        .map(|f| {
            let w = &mono[f * hop..(f + 1) * hop];
            let e = w.iter().map(|&v| f64::from(v).powi(2)).sum::<f64>() / hop as f64;
            let d = w.windows(2).map(|p| f64::from(p[1] - p[0]).powi(2)).sum::<f64>() / hop as f64;
            (1.0 + 1e4 * e).ln() + (1.0 + 1e4 * d).ln()
        })
        .collect();
    let flux: Vec<f64> = (0..nf).map(|f| if f == 0 { 0.0 } else { (level[f] - level[f - 1]).max(0.0) }).collect();
    let top = flux.iter().copied().fold(0.0, f64::max);
    if top < 0.5 {
        return points;
    }
    // soma acumulada para a média local
    let mut prefix = vec![0.0; nf + 1];
    for f in 0..nf {
        prefix[f + 1] = prefix[f] + flux[f];
    }
    let half = ((0.2 / HOP_SECS) as usize).max(2);
    let s = f64::from(if sensitivity.is_finite() { sensitivity.clamp(0.0, 1.0) } else { 0.5 });
    let (relative, floor, of_top) = (6.0 - 4.5 * s, 1.2 - 0.8 * s, 0.30 - 0.22 * s);
    let gap = ((MIN_GAP_SECS / HOP_SECS) as usize).max(1);
    let edge = (EDGE_SECS * rate) as usize;

    let mut found: Vec<(usize, f64)> = Vec::new();
    for f in 1..nf - 1 {
        let v = flux[f];
        if v < floor || v < of_top * top {
            continue;
        }
        let (a, b) = (f.saturating_sub(gap), (f + gap + 1).min(nf));
        if flux[a..b].iter().any(|&o| o > v) || flux[f - 1] > v || flux[f + 1] >= v {
            continue;
        }
        let (a, b) = (f.saturating_sub(half), (f + half + 1).min(nf));
        if v < relative * (prefix[b] - prefix[a]) / (b - a) as f64 {
            continue;
        }
        found.push((onset(&mono, f, hop, rate), v));
    }
    // o refinamento pode juntar dois cortes: fica o mais forte de cada par próximo demais
    found.sort_by_key(|&(at, _)| at);
    let min_gap = (MIN_GAP_SECS * rate) as usize / 2;
    let mut kept: Vec<(usize, f64)> = Vec::new();
    for c in found {
        match kept.last_mut() {
            Some(last) if c.0 - last.0 < min_gap => {
                if c.1 > last.1 {
                    *last = c;
                }
            }
            _ => kept.push(c),
        }
    }
    kept.retain(|&(at, _)| at > edge && at + edge < n);
    if kept.len() > MAX_SLICES - 1 {
        kept.sort_by(|a, b| b.1.total_cmp(&a.1));
        kept.truncate(MAX_SLICES - 1);
        kept.sort_by_key(|&(at, _)| at);
    }
    points.extend(kept.into_iter().map(|(at, _)| at));
    points
}

/// Onde o ataque do quadro de envelope `f` começa no áudio.
fn onset(mono: &[f32], f: usize, hop: usize, rate: f64) -> usize {
    let n = mono.len();
    let from = f.saturating_sub(1) * hop;
    let peak = mono[f * hop..((f + 2) * hop).min(n)].iter().fold(0.0f32, |a, &v| a.max(v.abs()));
    let mut at = (from..((f + 1) * hop).min(n)).find(|&i| mono[i].abs() >= 0.1 * peak).unwrap_or(f * hop);
    let back = (0.002 * rate) as usize;
    if let Some(zero) = (at.saturating_sub(back).max(1)..=at).rev().find(|&j| j < n && (mono[j - 1] <= 0.0) != (mono[j] <= 0.0)) {
        at = zero;
    }
    at
}

/// Uma zona de uma nota por fatia, a partir de `first_note` (cromático): cada uma toca só a fatia
/// `[pontos[i], pontos[i+1])`, até o fim, na altura original (a nota é a base). `points` em segundos,
/// crescentes (a saída de [`slice_points`]); pontos fora de ordem ou repetidos são pulados; para no
/// limite de notas (127) ou de [`MAX_SLICES`].
pub fn slice_zones(points: &[f64], first_note: u8) -> Vec<ZoneDef> {
    let mut clean: Vec<f64> = Vec::new();
    for &p in points {
        if p.is_finite() && p >= 0.0 && clean.last().is_none_or(|&l| p > l) {
            clean.push(p);
        }
    }
    clean
        .iter()
        .enumerate()
        .take(MAX_SLICES)
        .map_while(|(i, &start)| {
            let note = u8::try_from(usize::from(first_note) + i).ok().filter(|&n| n <= 127)?;
            let end = clean.get(i + 1).copied().unwrap_or(0.0);
            Some(ZoneDef { root: note, lo: note, hi: note, one_shot: true, start, end, ..ZoneDef::default() })
        })
        .collect()
}
