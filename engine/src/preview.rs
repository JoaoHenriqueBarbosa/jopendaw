//! A pré-escuta: uma voz de áudio à parte do transporte, mixada direto na saída (depois da cadeia e
//! do limitador do master, sem medidor, sem captura e fora do render). Serve ao navegador de áudios:
//! ouvir um arquivo sem mexer no projeto, tocando ou parado. Uma voz só; tocar outro áudio troca a
//! voz antiga com um fade curto.

use std::sync::Arc;

use crate::Sample;

/// Fade de entrada, em segundos (tira o estalo do corte no meio da onda).
const FADE_IN_SECS: f64 = 0.003;
/// Fade de saída ao parar ou trocar, em segundos.
const FADE_OUT_SECS: f64 = 0.012;

struct Voice {
    sample: Arc<Sample>,
    /// Posição de leitura, em quadros do próprio áudio.
    pos: f64,
    /// Quadros do áudio por quadro de saída (taxa do áudio sobre a do motor).
    step: f64,
    gain: f32,
    /// 0..1: o fade de entrada sobe, o de saída desce.
    env: f32,
    stopping: bool,
}

/// A voz de pré-escuta do motor (vazia até o primeiro `play`).
#[derive(Default)]
pub struct Preview {
    voice: Option<Voice>,
    /// A voz que está saindo (troca de áudio com a anterior ainda soando).
    leaving: Option<Voice>,
}

impl Preview {
    /// Começa a tocar `sample` a partir de `offset` segundos, com ganho `gain` (0..2).
    pub fn play(&mut self, sample: Arc<Sample>, offset: f64, gain: f32, engine_rate: f64) {
        self.stop();
        let rate = sample.rate().max(1.0);
        self.voice = Some(Voice {
            pos: (offset.max(0.0) * rate).min(sample.frames() as f64),
            step: rate / engine_rate.max(1.0),
            gain: gain.clamp(0.0, 2.0),
            env: 0.0,
            stopping: false,
            sample,
        });
    }

    /// Para com um fade curto.
    pub fn stop(&mut self) {
        if let Some(mut v) = self.voice.take() {
            v.stopping = true;
            self.leaving = Some(v);
        }
    }

    /// Soando (ou ainda saindo).
    pub fn active(&self) -> bool {
        self.voice.is_some() || self.leaving.is_some()
    }

    /// Soma a voz na saída do bloco. Sem alocar.
    pub fn mix(&mut self, l: &mut [f32], r: &mut [f32], engine_rate: f64) {
        let up = (1.0 / (FADE_IN_SECS * engine_rate)) as f32;
        let down = (1.0 / (FADE_OUT_SECS * engine_rate)) as f32;
        if let Some(v) = self.leaving.as_mut()
            && !v.render(l, r, up, down)
        {
            self.leaving = None;
        }
        if let Some(v) = self.voice.as_mut()
            && !v.render(l, r, up, down)
        {
            self.voice = None;
        }
    }
}

impl Voice {
    /// Soma um bloco; `false` quando acabou (o fim do áudio ou o fade de saída).
    fn render(&mut self, l: &mut [f32], r: &mut [f32], up: f32, down: f32) -> bool {
        let frames = self.sample.frames();
        let (a, b) = (self.sample.channel(0), self.sample.channel(1));
        for (ol, or) in l.iter_mut().zip(r.iter_mut()) {
            let i = self.pos as usize;
            if i >= frames {
                return false;
            }
            let f = (self.pos - i as f64) as f32;
            let j = (i + 1).min(frames - 1);
            let (sl, sr) = (a[i] + (a[j] - a[i]) * f, b[i] + (b[j] - b[i]) * f);
            if self.stopping {
                self.env -= down;
                if self.env <= 0.0 {
                    return false;
                }
            } else if self.env < 1.0 {
                self.env = (self.env + up).min(1.0);
            }
            let g = self.gain * self.env;
            *ol = (*ol + sl * g).clamp(-1.0, 1.0);
            *or = (*or + sr * g).clamp(-1.0, 1.0);
            self.pos += self.step;
        }
        true
    }
}
