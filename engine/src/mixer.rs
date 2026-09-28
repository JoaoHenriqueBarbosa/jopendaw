//! Canal do mixer: volume, pan, mudo, solo e o medidor de pico.

/// Um canal (faixa ou master).
#[derive(Clone, Debug)]
pub struct Track {
    /// Ganho linear (1.0 = 0 dB).
    pub gain: f32,
    /// -1 (esquerda) a 1 (direita).
    pub pan: f32,
    pub mute: bool,
    pub solo: bool,
    peak_l: f32,
    peak_r: f32,
}

impl Default for Track {
    fn default() -> Self {
        Self { gain: 1.0, pan: 0.0, mute: false, solo: false, peak_l: 0.0, peak_r: 0.0 }
    }
}

/// Lei de pan de potência constante (-3 dB no centro).
pub fn pan_gains(pan: f32) -> (f32, f32) {
    let a = (pan.clamp(-1.0, 1.0) + 1.0) * std::f32::consts::FRAC_PI_4;
    (a.cos(), a.sin())
}

impl Track {
    /// Aplica volume e pan no bloco e atualiza o pico.
    pub fn apply(&mut self, l: &mut [f32], r: &mut [f32]) {
        let (pl, pr) = pan_gains(self.pan);
        let (gl, gr) = (self.gain * pl, self.gain * pr);
        for (a, b) in l.iter_mut().zip(r.iter_mut()) {
            *a *= gl;
            *b *= gr;
            self.peak_l = self.peak_l.max(a.abs());
            self.peak_r = self.peak_r.max(b.abs());
        }
    }

    /// O master: volume e balanço (o pan só atenua o lado oposto, o centro fica em 0 dB).
    pub fn apply_master(&mut self, l: &mut [f32], r: &mut [f32]) {
        let p = self.pan.clamp(-1.0, 1.0);
        let gl = self.gain * (1.0 - p.max(0.0));
        let gr = self.gain * (1.0 + p.min(0.0));
        for (a, b) in l.iter_mut().zip(r.iter_mut()) {
            *a *= gl;
            *b *= gr;
            self.peak_l = self.peak_l.max(a.abs());
            self.peak_r = self.peak_r.max(b.abs());
        }
    }

    /// Pico desde a última leitura; zera para a próxima.
    pub fn take_peaks(&mut self) -> (f32, f32) {
        let p = (self.peak_l, self.peak_r);
        self.peak_l = 0.0;
        self.peak_r = 0.0;
        p
    }
}
