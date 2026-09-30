//! Expressão MIDI: pitch bend, roda de modulação (CC 1) e pedal de sustain (CC 64).
//!
//! Duas metades:
//!
//! - [`PitchExpr`]: o que os instrumentos com afinação (sintetizador, FM, wavetable, sampler) usam
//!   para transformar o bend e a modulação num desvio de afinação em semitons, calculado uma vez
//!   por bloco de controle e suavizado, para a roda não dar degrau audível. A modulação liga um
//!   vibrato (LFO senoidal de [`VIBRATO_HZ`]) cuja profundidade máxima é o parâmetro de alcance do
//!   vibrato do instrumento.
//! - [`ExprState`] e os `impl Lane`/`impl Engine` deste arquivo: o estado por faixa. O pedal mora
//!   aqui, na camada do motor, e não nos instrumentos: com o pedal embaixo o `note_off` não chega
//!   ao instrumento, a altura fica pendente, e ao soltar o pedal todos os `note_off` pendentes
//!   saem de uma vez. Os instrumentos só veem `set_pitch_bend` e `set_mod_wheel`. A bateria não
//!   tem afinação nem sustain: ignora tudo (o pedal nem segura as notas dela).
//!
//! # Valores
//!
//! Sempre normalizados: bend −1..1 (14 bits do MIDI divididos por 8192), modulação 0..1 (CC/127) e
//! pedal 0..1 (embaixo a partir de 0,5, como o MIDI trata 64 ou mais). Os ids de controle são os
//! do MIDI (1 e 64) e o 128 para o pitch bend, que no MIDI não é um CC.
//!
//! # Sequenciador
//!
//! O clipe de notas carrega eventos de controle (`cc_add`), na mesma linha do tempo das notas. Na
//! reprodução eles disparam no quadro exato, antes das notas do mesmo quadro (um pedal que desce
//! na batida de uma nota segura essa nota; um que sobe na batida de outra solta as anteriores
//! antes dela). Ao começar a tocar, saltar ou voltar o loop, o estado dos controles que o clipe
//! usa é reconstituído (vale o último evento antes da posição); ao parar, os controles do clipe
//! voltam ao neutro (bend 0, modulação 0, pedal solto). Os controles que o clipe não usa ficam
//! com quem os mexeu ao vivo.

use crate::dsp::{Smoothed, sin_turns, smoothing};
use crate::instrument::Instrument;
use crate::{Engine, Lane, event_offset, instrument};

/// Modulação (mod wheel).
pub const CC_MOD: u8 = 1;
/// Pedal de sustain.
pub const CC_SUSTAIN: u8 = 64;
/// Pitch bend (não é um CC no MIDI; o 128 fica fora dos 0..=127 dos controles reais).
pub const CC_BEND: u8 = 128;

/// Frequência do vibrato da roda de modulação.
pub const VIBRATO_HZ: f32 = 5.5;
/// Alcance padrão do bend, em semitons (para cima e para baixo).
pub const DEFAULT_BEND_RANGE: f32 = 2.0;
/// Vibrato padrão com a roda toda para cima, em semitons.
pub const DEFAULT_VIBRATO: f32 = 1.0;
/// Alcance máximo do bend, em semitons.
pub const MAX_BEND_RANGE: f32 = 24.0;
/// Vibrato máximo, em semitons.
pub const MAX_VIBRATO: f32 = 2.0;

/// Suavização do bend: rápida o bastante para acompanhar a mão, lenta o bastante para os 128
/// degraus de 7 bits de um controlador simples não virarem escada.
const BEND_TAU: f32 = 0.004;
/// Suavização da profundidade do vibrato.
const MOD_TAU: f32 = 0.015;

/// Desvio de afinação de um instrumento por bend e modulação.
#[derive(Clone, Debug)]
pub struct PitchExpr {
    rate: f32,
    /// Bend normalizado (−1..1) e alcance, em semitons.
    norm: f32,
    range: f32,
    /// Vibrato máximo, em semitons.
    vibrato: f32,
    /// Bend em semitons, suavizado.
    bend: Smoothed,
    /// Profundidade da roda (0..1), suavizada.
    wheel: Smoothed,
    phase: f32,
}

impl PitchExpr {
    pub fn new(rate: f32) -> Self {
        Self { rate, norm: 0.0, range: DEFAULT_BEND_RANGE, vibrato: DEFAULT_VIBRATO, bend: Smoothed::new(0.0), wheel: Smoothed::new(0.0), phase: 0.0 }
    }

    /// Bend normalizado; fora de −1..1 é limitado e não finito é ignorado.
    pub fn set_bend(&mut self, value: f32) {
        if value.is_finite() {
            self.norm = value.clamp(-1.0, 1.0);
            self.bend.set(self.norm * self.range);
        }
    }

    /// Alcance do bend em semitons (0..=[`MAX_BEND_RANGE`]).
    pub fn set_range(&mut self, semitones: f32) {
        if semitones.is_finite() {
            self.range = semitones.clamp(0.0, MAX_BEND_RANGE);
            self.bend.set(self.norm * self.range);
        }
    }

    /// Roda de modulação, 0..1.
    pub fn set_wheel(&mut self, value: f32) {
        if value.is_finite() {
            self.wheel.set(value.clamp(0.0, 1.0));
        }
    }

    /// Vibrato com a roda toda, em semitons (0..=[`MAX_VIBRATO`]).
    pub fn set_vibrato(&mut self, semitones: f32) {
        if semitones.is_finite() {
            self.vibrato = semitones.clamp(0.0, MAX_VIBRATO);
        }
    }

    /// Vai direto para os alvos: depois de um silêncio (sem `step`) a próxima nota não pode nascer
    /// varrendo de um valor velho.
    pub fn snap(&mut self) {
        self.bend.snap();
        self.wheel.snap();
    }

    /// O desvio, em semitons, para um bloco de controle de `len` quadros.
    pub fn step(&mut self, len: usize) -> f32 {
        let bend = self.bend.step(smoothing(BEND_TAU, len, self.rate));
        let wheel = self.wheel.step(smoothing(MOD_TAU, len, self.rate));
        if wheel > 0.0 {
            self.phase = (self.phase + VIBRATO_HZ * len as f32 / self.rate).fract();
            bend + sin_turns(self.phase) * wheel * self.vibrato
        } else {
            bend
        }
    }
}

/// Estado de expressão de uma faixa.
pub(crate) struct ExprState {
    bend: f32,
    wheel: f32,
    sustain: bool,
    /// A faixa segura notas com o pedal (a bateria não).
    pedal: bool,
    /// Alturas cujo `note_off` está esperando o pedal subir (um bit por altura).
    pending: u128,
    /// Controles que os eventos do clipe estão dirigindo (bit 0 modulação, 1 pedal, 2 bend).
    driven: u8,
}

const DRIVEN: [(u8, u8); 3] = [(CC_MOD, 1), (CC_SUSTAIN, 2), (CC_BEND, 4)];

impl ExprState {
    pub(crate) fn new(kind: u32) -> Self {
        Self { bend: 0.0, wheel: 0.0, sustain: false, pedal: kind != instrument::kind::DRUMS, pending: 0, driven: 0 }
    }

    /// O `note_on`, sem mais nada a esperar do pedal para essa altura.
    pub(crate) fn note_on(&mut self, inst: &mut dyn Instrument, pitch: u8, velocity: f32) {
        self.pending &= !(1u128 << (pitch & 127));
        inst.note_on(pitch, velocity);
    }

    /// O `note_off`: com o pedal embaixo fica pendente.
    pub(crate) fn note_off(&mut self, inst: &mut dyn Instrument, pitch: u8) {
        if self.sustain && self.pedal {
            self.pending |= 1u128 << (pitch & 127);
        } else {
            inst.note_off(pitch);
        }
    }

    /// Aplica um valor de controle (já limitado à faixa dele).
    pub(crate) fn set(&mut self, inst: &mut dyn Instrument, cc: u8, value: f32) {
        match cc {
            CC_BEND => {
                let v = value.clamp(-1.0, 1.0);
                if v != self.bend {
                    self.bend = v;
                    inst.set_pitch_bend(v);
                }
            }
            CC_MOD => {
                let v = value.clamp(0.0, 1.0);
                if v != self.wheel {
                    self.wheel = v;
                    inst.set_mod_wheel(v);
                }
            }
            CC_SUSTAIN if self.pedal => {
                let down = value >= 0.5;
                if down != self.sustain {
                    self.sustain = down;
                    if !down {
                        self.flush(inst);
                    }
                }
            }
            _ => {}
        }
    }

    /// Manda os `note_off` que o pedal segurava.
    fn flush(&mut self, inst: &mut dyn Instrument) {
        let mut bits = std::mem::take(&mut self.pending);
        while bits != 0 {
            let pitch = bits.trailing_zeros() as u8;
            bits &= bits - 1;
            inst.note_off(pitch);
        }
    }

    /// Tudo no neutro, sem soltar nada (o instrumento acabou de ser cortado ou soltou tudo).
    fn reset(&mut self, inst: &mut dyn Instrument) {
        self.pending = 0;
        self.sustain = false;
        for cc in [CC_BEND, CC_MOD] {
            self.set(inst, cc, 0.0);
        }
    }
}

/// Um evento de controle do clipe, na linha do tempo (batidas absolutas).
#[derive(Clone, Copy, Debug, PartialEq)]
pub(crate) struct CcEvent {
    pub(crate) beat: f64,
    pub(crate) cc: u8,
    pub(crate) value: f32,
    /// Ordem de chegada: no mesmo instante vale a ordem em que o app mandou.
    seq: u32,
}

/// Limita o valor à faixa do controle; `None` para um controle que o motor não conhece.
pub fn clamp_cc(cc: u32, value: f32) -> Option<(u8, f32)> {
    if !value.is_finite() {
        return None;
    }
    match cc {
        1 => Some((CC_MOD, value.clamp(0.0, 1.0))),
        64 => Some((CC_SUSTAIN, value.clamp(0.0, 1.0))),
        128 => Some((CC_BEND, value.clamp(-1.0, 1.0))),
        _ => None,
    }
}

/// Neutro de todos os controles: bend no centro, roda em zero, pedal solto.
const NEUTRAL: f32 = 0.0;

impl Lane {
    /// Ordena os eventos (sem alocar: o `sort_unstable` desempata pela ordem de chegada).
    pub(crate) fn sort_cc(&mut self) {
        self.cc.sort_unstable_by(|a, b| a.beat.total_cmp(&b.beat).then(a.seq.cmp(&b.seq)));
    }

    /// Reposiciona o cursor dos eventos em `pos` e, com o transporte andando, reconstitui o estado
    /// dos controles que o clipe usa.
    pub(crate) fn cue_cc(&mut self, pos: f64, frames_per_beat: f64, playing: bool) {
        self.cc_cursor = self.cc.partition_point(|e| event_offset(e.beat * frames_per_beat, pos) < 0.0);
        if !playing {
            return;
        }
        let Self { instrument: Some(inst), cc, cc_cursor, expr, .. } = self else { return };
        for (id, bit) in DRIVEN {
            if cc.iter().any(|e| e.cc == id) {
                let value = cc[..*cc_cursor].iter().rev().find(|e| e.cc == id).map_or(NEUTRAL, |e| e.value);
                expr.set(inst.as_mut(), id, value);
                expr.driven |= bit;
            } else if expr.driven & bit != 0 {
                expr.set(inst.as_mut(), id, NEUTRAL);
                expr.driven &= !bit;
            }
        }
    }

    /// O transporte parou: os controles do clipe voltam ao neutro e o pedal não segura mais nada
    /// (o `release_all` já soltou o som).
    pub(crate) fn stop_cc(&mut self) {
        let Self { instrument, expr, .. } = self;
        if let Some(inst) = instrument.as_mut() {
            for (id, bit) in DRIVEN {
                if expr.driven & bit != 0 {
                    expr.set(inst.as_mut(), id, NEUTRAL);
                }
            }
        }
        expr.driven = 0;
        expr.pending = 0;
    }

    /// Pânico: instrumento cortado, controles no neutro (o "reset all controllers" do MIDI).
    pub(crate) fn panic_cc(&mut self) {
        let Self { instrument, expr, .. } = self;
        if let Some(inst) = instrument.as_mut() {
            expr.reset(inst.as_mut());
        } else {
            expr.pending = 0;
        }
    }

    /// Controle ao vivo (roda, pedal, MIDI).
    fn live_cc(&mut self, cc: u8, value: f32) {
        let Self { instrument, expr, .. } = self;
        if let Some(inst) = instrument.as_mut() {
            expr.set(inst.as_mut(), cc, value);
        }
    }

    pub(crate) fn live_note_on(&mut self, pitch: u8, velocity: f32) {
        let Self { instrument, expr, .. } = self;
        if let Some(inst) = instrument.as_mut() {
            expr.note_on(inst.as_mut(), pitch, velocity);
        }
    }

    pub(crate) fn live_note_off(&mut self, pitch: u8) {
        let Self { instrument, expr, .. } = self;
        if let Some(inst) = instrument.as_mut() {
            expr.note_off(inst.as_mut(), pitch);
        }
    }

    /// Solta as notas do sequenciador (seek, volta do loop) respeitando o pedal.
    pub(crate) fn release_held_pedal(&mut self) {
        let Self { instrument, held, expr, .. } = self;
        if let Some(inst) = instrument.as_mut() {
            for h in held.iter() {
                expr.note_off(inst.as_mut(), h.pitch);
            }
        }
        held.clear();
    }

    /// Está com o pedal embaixo segurando alguma altura? (para os testes)
    #[cfg(test)]
    pub(crate) fn pending_pitches(&self) -> u32 {
        self.expr.pending.count_ones()
    }
}

impl Engine {
    /// Controle ao vivo numa faixa: `cc` 1 (modulação 0..1), 64 (pedal, 0,5 ou mais é embaixo) ou
    /// 128 (pitch bend −1..1). Controle desconhecido, valor não finito ou faixa que não existe
    /// são ignorados; valor fora da faixa é limitado. Tocando e gravando, entra no registro com a
    /// batida de agora.
    pub fn live_cc(&mut self, track: usize, cc: u32, value: f32) {
        let Some((cc, value)) = clamp_cc(cc, value) else { return };
        if track >= self.lanes.len() {
            return;
        }
        if self.playing {
            self.recorder.cc(track as u32, cc, value, self.transport_beat());
        }
        self.lanes[track].live_cc(cc, value);
    }

    /// Pitch bend ao vivo, −1..1 (a roda de 14 bits do MIDI dividida por 8192).
    pub fn live_bend(&mut self, track: usize, value: f32) {
        self.live_cc(track, u32::from(CC_BEND), value);
    }

    /// Evento de controle do clipe: `beat` absoluto na linha do tempo. Controle desconhecido, batida
    /// ou valor não finitos são ignorados.
    pub fn add_cc(&mut self, track: usize, cc: u32, beat: f64, value: f32) {
        let Some((cc, value)) = clamp_cc(cc, value) else { return };
        let Some(lane) = self.lanes.get_mut(track) else { return };
        if !beat.is_finite() {
            return;
        }
        let seq = lane.cc_seq;
        lane.cc_seq = seq.wrapping_add(1);
        lane.cc.push(CcEvent { beat: beat.max(0.0), cc, value, seq });
        self.notes_dirty = true;
    }

    /// Apaga os eventos de controle de todas as faixas. O estado que eles dirigiam volta ao neutro
    /// no próximo bloco, se o transporte estiver tocando (senão, quando parar).
    pub fn clear_cc(&mut self) {
        for lane in &mut self.lanes {
            lane.cc.clear();
            lane.cc_seq = 0;
        }
        self.notes_dirty = true;
    }
}

#[cfg(test)]
#[path = "expression_tests.rs"]
mod tests;
