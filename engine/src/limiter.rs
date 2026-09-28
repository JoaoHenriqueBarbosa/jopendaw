//! Limitador de segurança do master: o último estágio antes do conversor. Com várias faixas a soma
//! passa fácil de 0 dBFS, e sem ele o que saía era clipping duro (a trava em ±1), audível como
//! distorção. Não é o limitador de masterização (esse entra como efeito): aqui a meta é ser
//! transparente abaixo do teto e nunca deixar passar nada acima dele.
//!
//! Desenho (o de "Signalsmith: designing a straightforward limiter"): o ganho necessário em cada
//! quadro passa por um release exponencial (só na subida), depois por uma retenção de mínimo e um
//! filtro de caixa, ambos do tamanho do lookahead, e o áudio sai atrasado desse mesmo tanto. A
//! retenção garante que o ganho já desceu inteiro quando o pico sai do atraso; a caixa transforma a
//! descida num ataque suave em vez de um degrau.

/// Lookahead em segundos (também é a latência que o master ganha).
const LOOKAHEAD: f64 = 0.0015;
/// Teto: −0,3 dBFS, com folga para a reconstrução do conversor.
const CEILING: f32 = 0.966;
/// Tempo de release (volta do ganho), em segundos.
const RELEASE: f64 = 0.08;

pub struct Limiter {
    len: usize,
    /// Atraso do áudio (entrelaçado esq/dir) e das janelas, todos anéis de `len`.
    delay: Vec<f32>,
    /// Janela da retenção de mínimo e da caixa.
    held: Vec<f32>,
    boxed: Vec<f32>,
    pos: usize,
    box_sum: f64,
    release: f32,
    smoothed: f32,
    /// Menor ganho aplicado desde a última leitura (para um medidor de redução).
    min_gain: f32,
}

impl Limiter {
    pub fn new(rate: f64) -> Self {
        let len = ((LOOKAHEAD * rate).round() as usize).max(1);
        Self {
            len,
            delay: vec![0.0; len * 2],
            held: vec![1.0; len],
            boxed: vec![1.0; len],
            pos: 0,
            box_sum: len as f64,
            release: (1.0 - (-1.0 / (RELEASE * rate)).exp()) as f32,
            smoothed: 1.0,
            min_gain: 1.0,
        }
    }

    /// Latência em quadros.
    #[cfg(test)]
    pub fn latency(&self) -> usize {
        self.len
    }

    /// Menor ganho desde a última leitura (1 = nada reduzido); zera para a próxima.
    pub fn take_min_gain(&mut self) -> f32 {
        std::mem::replace(&mut self.min_gain, 1.0)
    }

    pub fn process(&mut self, l: &mut [f32], r: &mut [f32]) {
        let n = self.len;
        for (a, b) in l.iter_mut().zip(r.iter_mut()) {
            let peak = a.abs().max(b.abs());
            let need = if peak > CEILING { CEILING / peak } else { 1.0 };
            // desce na hora, sobe devagar
            self.smoothed = if need < self.smoothed { need } else { self.smoothed + (need - self.smoothed) * self.release };
            // retenção de mínimo sobre a janela (n pequeno: varrer é mais barato que uma fila)
            self.held[self.pos] = self.smoothed;
            let mut held = self.smoothed;
            for &h in &self.held {
                held = held.min(h);
            }
            // caixa: média da retenção na mesma janela
            self.box_sum += (held - self.boxed[self.pos]) as f64;
            self.boxed[self.pos] = held;
            let gain = ((self.box_sum / n as f64) as f32).min(1.0);
            // áudio atrasado de n quadros
            let (dl, dr) = (self.delay[self.pos * 2], self.delay[self.pos * 2 + 1]);
            self.delay[self.pos * 2] = *a;
            self.delay[self.pos * 2 + 1] = *b;
            *a = dl * gain;
            *b = dr * gain;
            self.min_gain = self.min_gain.min(gain);
            self.pos += 1;
            if self.pos == n {
                self.pos = 0;
                // a soma corrida acumula erro de arredondamento: recalcula a cada volta
                self.box_sum = self.boxed.iter().map(|&v| v as f64).sum();
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn nada_passa_do_teto() {
        let mut lim = Limiter::new(48_000.0);
        // senoide a +12 dB com um degrau súbito
        let (mut l, mut r): (Vec<f32>, Vec<f32>) = (0..48_000)
            .map(|i| {
                let s = (i as f32 * 0.05).sin() * if i > 10_000 { 4.0 } else { 0.5 };
                (s, -s)
            })
            .unzip();
        for (cl, cr) in l.chunks_mut(128).zip(r.chunks_mut(128)) {
            lim.process(cl, cr);
        }
        let max = l.iter().chain(r.iter()).fold(0.0f32, |m, s| m.max(s.abs()));
        assert!(max <= CEILING + 1e-4, "{max}");
        assert!(lim.take_min_gain() < 0.3);
    }

    #[test]
    fn abaixo_do_teto_e_transparente() {
        let mut lim = Limiter::new(48_000.0);
        let src: Vec<f32> = (0..4800).map(|i| (i as f32 * 0.01).sin() * 0.5).collect();
        let (mut l, mut r) = (src.clone(), src.clone());
        lim.process(&mut l, &mut r);
        let d = lim.latency();
        for i in d..src.len() {
            assert!((l[i] - src[i - d]).abs() < 1e-6);
        }
    }
}
