//! Metrônomo: um clique senoidal curto em cada batida, mais agudo no primeiro tempo do compasso.

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

    /// Soma os cliques do bloco que começa em `pos` (quadros da linha do tempo).
    pub fn render(&mut self, l: &mut [f32], r: &mut [f32], pos: f64, frames_per_beat: f64, beats_per_bar: u32, rate: f64) {
        if !self.on {
            self.left = 0;
            return;
        }
        let total = (CLICK_SECS * rate) as usize;
        for i in 0..l.len() {
            let t = pos + i as f64;
            // começo de batida dentro deste quadro?
            let beat = (t / frames_per_beat).ceil();
            if (beat * frames_per_beat - t).abs() < 1.0 && beat * frames_per_beat >= t {
                let downbeat = (beat as u64).is_multiple_of(beats_per_bar as u64);
                self.freq = if downbeat { 1600.0 } else { 1000.0 };
                self.left = total;
                self.phase = 0.0;
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
