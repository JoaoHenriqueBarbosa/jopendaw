//! Metrônomo: um clique senoidal curto em cada batida, mais agudo no primeiro tempo do compasso.

use crate::tempo::{MeterMap, TempoMap};

const CLICK_SECS: f64 = 0.03;

#[derive(Clone, Debug)]
pub struct Metronome {
    pub on: bool,
    pub gain: f32,
    /// Quadros que faltam do clique atual.
    left: usize,
    freq: f64,
    phase: f64,
}

impl Default for Metronome {
    fn default() -> Self {
        Self { on: false, gain: 0.6, left: 0, freq: 1000.0, phase: 0.0 }
    }
}

impl Metronome {
    pub fn silence(&mut self) {
        self.left = 0;
    }

    /// Soma os cliques do bloco que começa em `pos` (quadros da linha do tempo). Os cliques caem
    /// nos tempos do compasso vigente (`meter`), na posição em quadros que o mapa de andamento
    /// dá a cada um; o primeiro tempo do compasso é mais agudo.
    pub fn render(&mut self, l: &mut [f32], r: &mut [f32], pos: f64, tempo: &TempoMap, meter: &MeterMap, rate: f64) {
        if !self.on {
            self.left = 0;
            return;
        }
        let total = (CLICK_SECS * rate) as usize;
        let end = pos + l.len() as f64;
        // primeiro clique que cai neste bloco (a folga de 1e-6 batida absorve o erro da conversão)
        let mut click = meter.click_at_or_after(tempo.to_beats(pos) - 1e-6);
        let mut at = loop {
            let f = tempo.to_frames(meter.beat_of(click));
            if f >= pos {
                break f;
            }
            click = meter.next(click);
        };
        // o quadro do bloco em que o próximo clique começa (o do quadro inteiro que o contém)
        let mut next = if at < end { (at - pos) as usize } else { usize::MAX };
        for i in 0..l.len() {
            while i == next {
                let downbeat = meter.is_downbeat(click);
                self.freq = if downbeat { 1600.0 } else { 1000.0 };
                self.left = total;
                self.phase = 0.0;
                click = meter.next(click);
                at = tempo.to_frames(meter.beat_of(click));
                next = if at < end { ((at - pos) as usize).max(i + 1) } else { usize::MAX };
            }
            if self.left > 0 {
                let env = (self.left as f64 / total as f64).powi(3) as f32;
                let s = (self.phase * std::f64::consts::TAU).sin() as f32 * env * self.gain;
                self.phase += self.freq / rate;
                self.left -= 1;
                l[i] += s;
                r[i] += s;
            }
        }
    }
}
