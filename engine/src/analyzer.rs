//! Analisador de espectro: guarda a saída de uma faixa (ou do master) num anel e calcula o
//! espectro quando a interface pede.
//!
//! A FFT é real, radix-2, própria: os 2n quadros viram n números complexos (pares nas partes
//! reais, ímpares nas imaginárias), uma FFT complexa de n pontos e um passo final que separa os
//! dois espectros e junta o resultado. Janela, fatores de giro e buffers são criados no `new`, no
//! tamanho máximo; calcular não aloca (roda na thread de áudio, entre um bloco e outro).

use std::f64::consts::TAU;

/// Tamanho do anel (quadros mono) e da maior FFT.
pub const RING: usize = 4096;

/// Piso da escala: abaixo disso é silêncio para a interface.
pub const FLOOR_DB: f32 = -120.0;

pub struct Analyzer {
    ring: Vec<f32>,
    /// Próxima posição de escrita no anel.
    pos: usize,
    /// Janela de Hann periódica de `RING` pontos; FFTs menores a leem com passo.
    window: Vec<f32>,
    /// e^(−2πik/RING) para k < RING/2; FFTs menores leem com passo.
    cos: Vec<f32>,
    sin: Vec<f32>,
    re: Vec<f32>,
    im: Vec<f32>,
}

impl Default for Analyzer {
    fn default() -> Self {
        Self::new()
    }
}

impl Analyzer {
    pub fn new() -> Self {
        let window = (0..RING).map(|i| (0.5 - 0.5 * (TAU * i as f64 / RING as f64).cos()) as f32).collect();
        let half = RING / 2;
        let cos = (0..half).map(|k| (TAU * k as f64 / RING as f64).cos() as f32).collect();
        let sin = (0..half).map(|k| -(TAU * k as f64 / RING as f64).sin() as f32).collect();
        Self { ring: vec![0.0; RING], pos: 0, window, cos, sin, re: vec![0.0; half], im: vec![0.0; half] }
    }

    /// Esquece o que foi guardado (troca da faixa observada).
    pub fn clear(&mut self) {
        self.ring.fill(0.0);
        self.pos = 0;
    }

    /// Guarda um bloco estéreo como mono (média dos canais).
    pub fn push(&mut self, l: &[f32], r: &[f32]) {
        for (&a, &b) in l.iter().zip(r) {
            let v = (a + b) * 0.5;
            self.ring[self.pos] = if v.is_finite() { v } else { 0.0 };
            self.pos = (self.pos + 1) % RING;
        }
    }

    /// Guarda `n` quadros de silêncio (a faixa observada não soou no bloco).
    pub fn push_silence(&mut self, n: usize) {
        for _ in 0..n.min(RING) {
            self.ring[self.pos] = 0.0;
            self.pos = (self.pos + 1) % RING;
        }
    }

    /// Escreve em `out` o espectro dos últimos `2m` quadros, em dB (−120..0, 0 dB = senoide de
    /// amplitude 1 no centro de uma faixa), onde `m` é a maior potência de 2 que cabe em `out` e
    /// em metade do anel. A faixa `k` cobre a frequência `k · taxa / 2m`. Devolve `m`.
    pub fn spectrum(&mut self, out: &mut [f32]) -> usize {
        let cap = out.len().min(RING / 2);
        if cap == 0 {
            return 0;
        }
        // m = pontos complexos da FFT = faixas escritas; o sinal tem 2m quadros
        let m = 1usize << (usize::BITS - 1 - cap.leading_zeros());
        let size = 2 * m;
        let stride = RING / size;
        // pares e ímpares, janelados, nas partes real e imaginária
        let start = (self.pos + RING - size) % RING;
        for k in 0..m {
            let (i0, i1) = (2 * k, 2 * k + 1);
            self.re[k] = self.ring[(start + i0) % RING] * self.window[i0 * stride];
            self.im[k] = self.ring[(start + i1) % RING] * self.window[i1 * stride];
        }
        self.fft(m);
        // separa os espectros dos pares (E) e dos ímpares (O) e junta: X[k] = E[k] + W^k·O[k]
        let (re, im) = (&self.re, &self.im);
        // Hann tem ganho coerente 1/2: uma senoide de amplitude A dá |X| = A·N/4
        let norm = 4.0 / size as f32;
        for (k, o) in out.iter_mut().enumerate().take(m) {
            let j = (m - k) % m;
            let (zr, zi) = (re[k], im[k]);
            let (cr, ci) = (re[j], -im[j]); // conjugado de Z[m − k]
            let (er, ei) = ((zr + cr) * 0.5, (zi + ci) * 0.5);
            // O = (Z − conj) / 2i
            let (dr, di) = ((zr - cr) * 0.5, (zi - ci) * 0.5);
            let (or_, oi) = (di, -dr);
            let (wr, wi) = (self.cos[k * stride], self.sin[k * stride]);
            let xr = er + wr * or_ - wi * oi;
            let xi = ei + wr * oi + wi * or_;
            let mag = (xr * xr + xi * xi).sqrt() * norm;
            *o = if mag > 1e-6 { (20.0 * mag.log10()).clamp(FLOOR_DB, 0.0) } else { FLOOR_DB };
        }
        m
    }

    /// FFT complexa de `m` pontos (potência de 2) no lugar, em `re`/`im`: permutação por bits
    /// invertidos e borboletas de Cooley-Tukey (decimação no tempo).
    fn fft(&mut self, m: usize) {
        if m < 2 {
            return;
        }
        let bits = m.trailing_zeros();
        let (re, im) = (&mut self.re[..m], &mut self.im[..m]);
        for i in 0..m {
            let j = i.reverse_bits() >> (usize::BITS - bits);
            if j > i {
                re.swap(i, j);
                im.swap(i, j);
            }
        }
        let mut len = 2;
        while len <= m {
            let half = len / 2;
            // e^(−2πi j/len) = tabela de RING com passo RING/len
            let stride = RING / len;
            for base in (0..m).step_by(len) {
                for j in 0..half {
                    let (wr, wi) = (self.cos[j * stride], self.sin[j * stride]);
                    let (a, b) = (base + j, base + j + half);
                    let tr = re[b] * wr - im[b] * wi;
                    let ti = re[b] * wi + im[b] * wr;
                    re[b] = re[a] - tr;
                    im[b] = im[a] - ti;
                    re[a] += tr;
                    im[a] += ti;
                }
            }
            len *= 2;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sine(freq: f64, amp: f32, frames: usize) -> Vec<f32> {
        (0..frames).map(|i| (TAU * freq * i as f64 / 48_000.0).sin() as f32 * amp).collect()
    }

    fn argmax(v: &[f32]) -> usize {
        v.iter().enumerate().fold((0, f32::MIN), |(bi, bv), (i, &x)| if x > bv { (i, x) } else { (bi, bv) }).0
    }

    #[test]
    fn senoide_tem_pico_na_faixa_certa() {
        let mut a = Analyzer::new();
        // faixa 100 de uma FFT de 2048 pontos a 48 kHz
        let s = sine(100.0 * 48_000.0 / 2048.0, 0.5, RING);
        a.push(&s, &s);
        let mut out = vec![0.0; 1024];
        assert_eq!(a.spectrum(&mut out), 1024);
        assert_eq!(argmax(&out), 100);
        // amplitude 0,5 = −6 dB
        assert!((out[100] + 6.02).abs() < 0.1, "{}", out[100]);
        // longe do pico, a janela de Hann derruba o vazamento
        assert!(out[300] < -90.0, "{}", out[300]);
    }

    #[test]
    fn fora_do_centro_cai_na_vizinha_e_tamanhos_menores() {
        let mut a = Analyzer::new();
        let s = sine(1000.0, 1.0, RING);
        a.push(&s, &s);
        // 1000 Hz numa FFT de 512 pontos: faixa 1000 / (48000/512) = 10,67 → 11
        let mut out = vec![0.0; 256];
        assert_eq!(a.spectrum(&mut out), 256);
        assert_eq!(argmax(&out), 11);
        assert!(out[11] > -3.0 && out[11] <= 0.0, "{}", out[11]);
        // um tamanho que não é potência de 2 usa a maior que cabe
        let mut out = vec![0.0; 1000];
        assert_eq!(a.spectrum(&mut out), 512);
    }

    #[test]
    fn silencio_fica_no_piso() {
        let mut a = Analyzer::new();
        let mut out = vec![0.0; 1024];
        a.spectrum(&mut out);
        assert!(out.iter().all(|&v| v == FLOOR_DB));
        let s = sine(440.0, 1.0, 2048);
        a.push(&s, &s);
        a.push_silence(RING);
        a.spectrum(&mut out);
        assert!(out.iter().all(|&v| v == FLOOR_DB));
    }

    #[test]
    fn usa_so_o_mais_recente() {
        let mut a = Analyzer::new();
        let old = sine(5000.0, 1.0, RING);
        a.push(&old, &old);
        let new = sine(100.0 * 48_000.0 / 2048.0, 1.0, 2048);
        a.push(&new, &new);
        let mut out = vec![0.0; 1024];
        a.spectrum(&mut out);
        assert_eq!(argmax(&out), 100);
        assert!(out[(5000.0 / (48_000.0 / 2048.0)) as usize] < -80.0);
    }
}
