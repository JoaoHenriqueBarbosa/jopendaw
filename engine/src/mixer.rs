//! Canal do mixer: volume, pan, mudo, solo e o medidor de pico.

/// Constante de tempo com que o ganho aplicado persegue o pedido: curta o bastante para parecer
/// imediata, longa o bastante para que mexer no volume, no pan ou no mudo com som passando não
/// estale nem dê o "zíper" de degraus a cada bloco.
const SMOOTH_SECS: f64 = 0.005;

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
    /// Ganhos (esq, dir) aplicados agora; `None` até o primeiro bloco, que já começa no alvo.
    now: Option<[f32; 2]>,
    /// Fração do caminho até o alvo andada a cada quadro.
    smooth: f32,
}

impl Default for Track {
    fn default() -> Self {
        Self::new(48_000.0)
    }
}

/// Lei de pan de potência constante (-3 dB no centro).
pub fn pan_gains(pan: f32) -> (f32, f32) {
    let a = (pan.clamp(-1.0, 1.0) + 1.0) * std::f32::consts::FRAC_PI_4;
    (a.cos(), a.sin())
}

impl Track {
    /// Canal para um motor na taxa `rate` (a suavização é medida em segundos).
    pub fn new(rate: f64) -> Self {
        let smooth = (1.0 - (-1.0 / (SMOOTH_SECS * rate.max(1.0))).exp()) as f32;
        Self { gain: 1.0, pan: 0.0, mute: false, solo: false, peak_l: 0.0, peak_r: 0.0, now: None, smooth }
    }

    fn target(&self, audible: bool) -> [f32; 2] {
        if !audible {
            return [0.0; 2];
        }
        let (pl, pr) = pan_gains(self.pan);
        [self.gain * pl, self.gain * pr]
    }

    /// Aplica volume e pan no bloco e atualiza o pico. `audible` falso (mudo, ou outra faixa em
    /// solo) leva o ganho a zero suavemente.
    pub fn apply(&mut self, l: &mut [f32], r: &mut [f32], audible: bool) {
        let target = self.target(audible);
        self.ramp(target, l, r);
    }

    /// O bloco não teve som nesta faixa: não há o que suavizar, o ganho vai direto ao alvo.
    pub fn settle(&mut self, audible: bool) {
        self.now = Some(self.target(audible));
    }

    /// O master: volume e balanço (o pan só atenua o lado oposto, o centro fica em 0 dB).
    pub fn apply_master(&mut self, l: &mut [f32], r: &mut [f32]) {
        let p = self.pan.clamp(-1.0, 1.0);
        let target = [self.gain * (1.0 - p.max(0.0)), self.gain * (1.0 + p.min(0.0))];
        self.ramp(target, l, r);
    }

    fn ramp(&mut self, target: [f32; 2], l: &mut [f32], r: &mut [f32]) {
        let [mut gl, mut gr] = self.now.unwrap_or(target);
        let (mut pl, mut pr) = (self.peak_l, self.peak_r);
        if (gl - target[0]).abs() < 1e-5 && (gr - target[1]).abs() < 1e-5 {
            [gl, gr] = target;
            for (a, b) in l.iter_mut().zip(r.iter_mut()) {
                *a *= gl;
                *b *= gr;
                pl = pl.max(a.abs());
                pr = pr.max(b.abs());
            }
        } else {
            let k = self.smooth;
            for (a, b) in l.iter_mut().zip(r.iter_mut()) {
                gl += (target[0] - gl) * k;
                gr += (target[1] - gr) * k;
                *a *= gl;
                *b *= gr;
                pl = pl.max(a.abs());
                pr = pr.max(b.abs());
            }
        }
        self.now = Some([gl, gr]);
        (self.peak_l, self.peak_r) = (pl, pr);
    }

    /// Pico desde a última leitura; zera para a próxima.
    pub fn take_peaks(&mut self) -> (f32, f32) {
        let p = (self.peak_l, self.peak_r);
        self.peak_l = 0.0;
        self.peak_r = 0.0;
        p
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn primeiro_bloco_ja_no_alvo() {
        let mut t = Track::new(48_000.0);
        t.gain = 0.5;
        let (mut l, mut r) = (vec![1.0; 64], vec![1.0; 64]);
        t.apply(&mut l, &mut r, true);
        let (gl, _) = pan_gains(0.0);
        assert!((l[0] - 0.5 * gl).abs() < 1e-6);
    }

    #[test]
    fn mudo_desce_sem_degrau() {
        let mut t = Track::new(48_000.0);
        let (mut l, mut r) = (vec![1.0; 128], vec![1.0; 128]);
        t.apply(&mut l, &mut r, true);
        let (mut l, mut r) = (vec![1.0; 4800], vec![1.0; 4800]);
        t.apply(&mut l, &mut r, false);
        let jump = l.windows(2).map(|w| (w[0] - w[1]).abs()).fold(0.0, f32::max);
        assert!(jump < 0.01, "{jump}");
        assert!(l[4799] < 1e-6);
        // assentado em zero, o próximo bloco sai zerado de verdade
        let (mut l, mut r) = (vec![1.0; 128], vec![1.0; 128]);
        t.apply(&mut l, &mut r, false);
        assert!(l.iter().chain(&r).all(|&s| s == 0.0));
    }
}
