//! Zonas do sampler (multi-sample). O fatiamento de loops mora no app (ver `slice_ref` no fim deste arquivo).
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

use super::{Sampler, VOICES, ignores_note_off};
use crate::Sample;

/// Zonas por sampler.
pub const MAX_ZONES: usize = 128;
/// Tamanho da tabela de grupos de round-robin: valem os grupos 1 a 63 (0 = sem round-robin; acima de 63 vira 63).
/// O app (`maxZoneGroup`) e o manual usam o mesmo limite.
pub(super) const MAX_GROUPS: usize = 64;
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
        // (as "até o fim" não: ignoram o note off e só empilham, até o limite de vozes)
        let global = self.one_shot;
        for voice in self.voices.iter_mut().filter(|w| w.held() && !w.released && w.pitch == pitch && !ignores_note_off(w, global)) {
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

// O fatiamento de loops (pontos de corte e zonas por fatia) é feito no app (`app/lib/daw/sampler_zones.dart`,
// que decodifica o áudio e já tem os pontos para a prévia). Aqui fica só a referência, compilada nos testes,
// contra a qual os vetores fixos de paridade valem dos dois lados.
#[cfg(test)]
#[path = "sampler_slice_ref.rs"]
mod slice_ref;

#[cfg(test)]
#[path = "sampler_zones_tests.rs"]
mod tests;
