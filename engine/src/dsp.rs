//! Blocos de DSP compartilhados pelos instrumentos (e, depois, pelos efeitos).

/// Envelope ADSR: ataque linear, decaimento e release exponenciais (um polo em direção ao alvo,
/// com um alvo um pouco além para terminar em tempo finito).
#[derive(Clone, Debug)]
pub struct Adsr {
    rate: f32,
    pub attack: f32,
    pub decay: f32,
    pub sustain: f32,
    pub release: f32,
    stage: Stage,
    value: f32,
    step: f32,
    coef: f32,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Stage {
    Idle,
    Attack,
    Decay,
    Sustain,
    Release,
}

/// Coeficiente de um polo que percorre ~99,9% do caminho em `secs`.
fn pole(secs: f32, rate: f32) -> f32 {
    (-6.9 / (secs.max(0.0005) * rate)).exp()
}

impl Adsr {
    pub fn new(rate: f64) -> Self {
        Self { rate: rate as f32, attack: 0.005, decay: 0.2, sustain: 0.7, release: 0.2, stage: Stage::Idle, value: 0.0, step: 0.0, coef: 0.0 }
    }

    pub fn set(&mut self, attack: f32, decay: f32, sustain: f32, release: f32) {
        self.attack = attack.max(0.0);
        self.decay = decay.max(0.0005);
        self.sustain = sustain.clamp(0.0, 1.0);
        self.release = release.max(0.0005);
    }

    /// Dispara (ou redispara, a partir do valor atual, sem estalo).
    pub fn gate_on(&mut self) {
        self.stage = Stage::Attack;
        self.step = 1.0 / (self.attack.max(0.0005) * self.rate);
    }

    pub fn gate_off(&mut self) {
        if self.stage != Stage::Idle {
            self.stage = Stage::Release;
            self.coef = pole(self.release, self.rate);
        }
    }

    /// Zera na hora.
    pub fn reset(&mut self) {
        self.stage = Stage::Idle;
        self.value = 0.0;
    }

    pub fn stage(&self) -> Stage {
        self.stage
    }

    pub fn active(&self) -> bool {
        self.stage != Stage::Idle
    }

    pub fn value(&self) -> f32 {
        self.value
    }

    /// Avança um quadro e devolve o nível 0..1.
    #[inline]
    pub fn next(&mut self) -> f32 {
        match self.stage {
            Stage::Idle => {}
            Stage::Attack => {
                self.value += self.step;
                if self.value >= 1.0 {
                    self.value = 1.0;
                    self.stage = Stage::Decay;
                    self.coef = pole(self.decay, self.rate);
                }
            }
            Stage::Decay => {
                self.value = self.sustain + (self.value - self.sustain) * self.coef;
                if (self.value - self.sustain).abs() < 1e-4 {
                    self.value = self.sustain;
                    self.stage = Stage::Sustain;
                }
            }
            Stage::Sustain => self.value = self.sustain,
            Stage::Release => {
                self.value *= self.coef;
                if self.value < 1e-4 {
                    self.value = 0.0;
                    self.stage = Stage::Idle;
                }
            }
        }
        self.value
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn adsr_percorre_os_estagios() {
        let mut e = Adsr::new(1000.0);
        e.set(0.01, 0.05, 0.5, 0.05);
        e.gate_on();
        for _ in 0..10 {
            e.next();
        }
        assert!((e.value() - 1.0).abs() < 1e-3);
        for _ in 0..200 {
            e.next();
        }
        assert_eq!(e.stage(), Stage::Sustain);
        assert!((e.value() - 0.5).abs() < 1e-3);
        e.gate_off();
        for _ in 0..200 {
            e.next();
        }
        assert!(!e.active());
    }
}
