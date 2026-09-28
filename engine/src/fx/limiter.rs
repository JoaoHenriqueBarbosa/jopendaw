//! Limitador de masterização: teto absoluto, lookahead ajustável até 10 ms e ligação estéreo.
//!
//! O desenho é o do limitador de segurança do master (`crate::limiter`, de "Signalsmith: designing
//! a straightforward limiter"): o ganho necessário em cada quadro passa por um release exponencial
//! (só na subida), por uma retenção de mínimo e por um filtro de caixa, e o áudio sai atrasado do
//! lookahead. Com atraso de D quadros, retenção e caixa têm D + 1 quadros: assim todo valor da
//! caixa que chega ao quadro de saída já contém a necessidade dele, e a média nunca passa dela. Com
//! janelas de D, como no de segurança, um quadro fica fora da conta: com a soltura de 80 ms de lá
//! isso não chega a 0,001 dB, mas aqui a soltura vai a 1 ms e o lookahead a 1 quadro, e um pico
//! isolado passaria meio dB do teto.
//!
//! A retenção de mínimo usa uma fila monotônica (O(1) amortizado por quadro): varrer a janela, como
//! o de segurança faz com 72 quadros, custaria 480 por quadro com 10 ms a 48 kHz.
//!
//! Mudar o lookahead muda o atraso, e pular a leitura de um atraso estala: o limitador abaixa a
//! saída, troca com as janelas limpas e volta aos poucos (a latência nova vale a partir daí).

use super::eq::Glide;
use crate::dsp::smoothing;
use crate::effect::{Effect, limiter_param};

const MAX_LOOKAHEAD: f64 = 0.010;
/// Duração de cada metade da troca de lookahead.
const FADE_SECS: f32 = 0.004;
/// Constante de tempo de cada polo da suavização de ganho, teto e ligação.
const SMOOTH_SECS: f32 = 0.005;
/// Fração do teto que o ganho mira, um fio abaixo de 1: absorve o arredondamento de teto/pico e
/// da média da caixa.
const LIMIT: f32 = 0.999_99;

/// Uma cadeia de ganho (uma por canal; com ligação total as duas recebem a mesma necessidade).
struct Chain {
    smoothed: f32,
    /// Fila monotônica crescente de (valor, quadro) num anel: a frente é o mínimo da janela.
    dq_val: Vec<f32>,
    dq_at: Vec<u64>,
    dq_head: usize,
    dq_len: usize,
    /// Anel dos valores retidos, para a caixa, e a soma corrida deles.
    held: Vec<f32>,
    hpos: usize,
    sum: f64,
    /// Quadros até recalcular a soma do zero (o arredondamento acumula).
    until_resum: usize,
}

impl Chain {
    fn new(cap: usize) -> Self {
        Self { smoothed: 1.0, dq_val: vec![1.0; cap], dq_at: vec![0; cap], dq_head: 0, dq_len: 0, held: vec![1.0; cap], hpos: 0, sum: 0.0, until_resum: cap }
    }

    /// Esquece tudo, para uma janela de `window` quadros.
    fn clear(&mut self, window: usize) {
        self.smoothed = 1.0;
        self.dq_head = 0;
        self.dq_len = 0;
        self.held.fill(1.0);
        self.hpos = 0;
        self.sum = window as f64;
        self.until_resum = self.held.len();
    }

    /// Anda um quadro com a necessidade `need` (≤ 1) e devolve o ganho a aplicar ao quadro que sai
    /// do atraso agora.
    #[inline]
    fn push(&mut self, need: f32, release: f32, t: u64, window: usize) -> f32 {
        self.smoothed = if need < self.smoothed { need } else { self.smoothed + (need - self.smoothed) * release };
        let cap = self.dq_val.len();
        // quem não é menor que o novo nunca mais será o mínimo
        while self.dq_len > 0 {
            let mut back = self.dq_head + self.dq_len - 1;
            if back >= cap {
                back -= cap;
            }
            if self.dq_val[back] < self.smoothed {
                break;
            }
            self.dq_len -= 1;
        }
        let mut slot = self.dq_head + self.dq_len;
        if slot >= cap {
            slot -= cap;
        }
        self.dq_val[slot] = self.smoothed;
        self.dq_at[slot] = t;
        self.dq_len += 1;
        // quem saiu da janela; o que acabou de entrar sempre fica (janela ≥ 1)
        while self.dq_at[self.dq_head] + window as u64 <= t {
            self.dq_head += 1;
            if self.dq_head == cap {
                self.dq_head = 0;
            }
            self.dq_len -= 1;
        }
        let held = self.dq_val[self.dq_head];
        // caixa: entra o retido novo, sai o de `window` quadros atrás
        let hcap = self.held.len();
        let old = if self.hpos >= window { self.hpos - window } else { self.hpos + hcap - window };
        self.sum += (held - self.held[old]) as f64;
        self.held[self.hpos] = held;
        self.hpos += 1;
        if self.hpos == hcap {
            self.hpos = 0;
        }
        self.until_resum -= 1;
        if self.until_resum == 0 {
            self.until_resum = hcap;
            self.sum = (0..window).map(|k| self.held[(self.hpos + hcap - 1 - k) % hcap] as f64).sum();
        }
        (self.sum / window as f64) as f32
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Phase {
    Run,
    /// Abaixando a saída para trocar o lookahead.
    Out,
    /// Subindo a entrada depois da troca.
    In,
}

pub struct Limiter {
    rate: f32,
    /// Lookahead em uso e pedido, em quadros.
    len: usize,
    want: usize,
    /// Atraso entrelaçado (esq, dir), anel de `max + 1` quadros.
    delay: Vec<f32>,
    dpos: usize,
    chains: [Chain; 2],
    t: u64,
    gain_in: Glide,
    ceiling: Glide,
    link: Glide,
    release: f32,
    phase: Phase,
    fade_out: f32,
    fade_in: f32,
    fade_step: f32,
    smooth: f32,
    meter: f32,
    /// Nada processado desde a criação ou o reset: o lookahead muda sem a troca com fade.
    fresh: bool,
}

impl Limiter {
    pub fn new(rate: f64) -> Self {
        let max = (MAX_LOOKAHEAD * rate).ceil() as usize;
        // janela de até max + 1 quadros; o anel da caixa precisa de uma posição a mais
        let cap = max + 2;
        let rate = rate as f32;
        let mut lim = Self {
            rate,
            len: 0,
            want: 0,
            delay: vec![0.0; (max + 1) * 2],
            dpos: 0,
            chains: [Chain::new(cap), Chain::new(cap)],
            t: 0,
            gain_in: Glide::new(1.0),
            ceiling: Glide::new(db_to_amp(-0.3)),
            link: Glide::new(1.0),
            release: 0.0,
            phase: Phase::Run,
            fade_out: 1.0,
            fade_in: 1.0,
            fade_step: 1.0 / (FADE_SECS * rate).max(1.0),
            smooth: smoothing(SMOOTH_SECS, 1, rate),
            meter: 0.0,
            fresh: true,
        };
        lim.set_release(0.05);
        lim.want = lim.frames(0.003);
        lim.switch();
        lim
    }

    fn frames(&self, secs: f32) -> usize {
        ((secs * self.rate).round() as usize).min(self.delay.len() / 2 - 1)
    }

    fn set_release(&mut self, secs: f32) {
        self.release = 1.0 - (-1.0 / (secs * self.rate)).exp();
    }

    /// Passa a usar o lookahead pedido, com atraso e janelas limpos.
    fn switch(&mut self) {
        self.len = self.want;
        self.delay.fill(0.0);
        self.dpos = 0;
        for c in &mut self.chains {
            c.clear(self.len + 1);
        }
    }
}

/// NaN e infinito viram silêncio (o que sai daqui vai para a caixa de som), e amplitudes absurdas
/// são limitadas antes de virar ganho: 1/pico de um valor perto do máximo do f32 seria denormal.
#[inline]
fn sane(x: f32) -> f32 {
    if x.is_finite() { x.clamp(-1e15, 1e15) } else { 0.0 }
}

/// Curva em S (smoothstep) de um fade linear 0..1: começa e termina com velocidade zero, então a
/// troca de lookahead não põe quina no som.
#[inline]
fn s_curve(t: f32) -> f32 {
    t * t * (3.0 - 2.0 * t)
}

fn db_to_amp(db: f32) -> f32 {
    (db * (std::f32::consts::LN_10 / 20.0)).exp()
}

impl Effect for Limiter {
    fn set_param(&mut self, id: u32, value: f32) {
        if !value.is_finite() {
            return;
        }
        match id {
            limiter_param::GAIN => self.gain_in.set(db_to_amp(value.clamp(0.0, 24.0))),
            limiter_param::CEILING => self.ceiling.set(db_to_amp(value.clamp(-24.0, 0.0))),
            limiter_param::RELEASE => self.set_release(value.clamp(0.001, 1.0)),
            limiter_param::LOOKAHEAD => {
                self.want = self.frames(value.clamp(0.0, MAX_LOOKAHEAD as f32));
                if self.fresh {
                    self.switch();
                }
            }
            limiter_param::LINK => self.link.set(value.clamp(0.0, 1.0)),
            _ => return,
        }
        if self.fresh {
            self.gain_in.snap();
            self.ceiling.snap();
            self.link.snap();
        }
    }

    fn process(&mut self, left: &mut [f32], right: &mut [f32]) {
        self.fresh = false;
        let a = self.smooth;
        let dcap = self.delay.len() / 2;
        let mut min_gain = 1.0f32;
        for (l, r) in left.iter_mut().zip(right.iter_mut()) {
            match self.phase {
                Phase::Run => {
                    if self.want != self.len {
                        self.phase = Phase::Out;
                    }
                }
                Phase::Out => {
                    self.fade_out -= self.fade_step;
                    if self.fade_out <= 0.0 {
                        // a saída está muda: troca, e a entrada volta aos poucos (o atraso limpo
                        // sai em silêncio até o primeiro quadro novo)
                        self.switch();
                        self.fade_out = 1.0;
                        self.fade_in = 0.0;
                        self.phase = Phase::In;
                    }
                }
                Phase::In => {
                    self.fade_in += self.fade_step;
                    if self.fade_in >= 1.0 {
                        self.fade_in = 1.0;
                        self.phase = Phase::Run;
                    }
                }
            }
            let gi = self.gain_in.step(a) * s_curve(self.fade_in);
            let (xl, xr) = (sane(*l * gi), sane(*r * gi));
            let (pl, pr) = (xl.abs(), xr.abs());
            // o teto é o limiar: abaixo dele o som passa intacto (a interface desenha
            // saída = mín(entrada + ganho, teto))
            let top = self.ceiling.step(a) * LIMIT;
            let nl = if pl > top { top / pl } else { 1.0 };
            let nr = if pr > top { top / pr } else { 1.0 };
            let link = self.link.step(a);
            let both = nl.min(nr);
            let window = self.len + 1;
            let [cl, cr] = &mut self.chains;
            let gl = cl.push(nl + (both - nl) * link, self.release, self.t, window);
            let gr = cr.push(nr + (both - nr) * link, self.release, self.t, window);
            self.t += 1;
            // o atraso: escreve o quadro de agora e lê o de `len` quadros atrás
            self.delay[self.dpos * 2] = xl;
            self.delay[self.dpos * 2 + 1] = xr;
            let read = if self.dpos >= self.len { self.dpos - self.len } else { self.dpos + dcap - self.len };
            let (dl, dr) = (self.delay[read * 2], self.delay[read * 2 + 1]);
            self.dpos += 1;
            if self.dpos == dcap {
                self.dpos = 0;
            }
            let out = s_curve(self.fade_out);
            let (gl, gr) = (gl.min(1.0), gr.min(1.0));
            *l = dl * gl * out;
            *r = dr * gr * out;
            min_gain = min_gain.min(gl.min(gr));
        }
        if !left.is_empty() {
            self.meter = -20.0 * min_gain.max(1e-6).log10();
        }
    }

    fn reset(&mut self) {
        self.switch();
        self.phase = Phase::Run;
        self.fade_out = 1.0;
        self.fade_in = 1.0;
        self.gain_in.snap();
        self.ceiling.snap();
        self.link.snap();
        self.meter = 0.0;
        self.fresh = true;
    }

    fn latency(&self) -> usize {
        self.len
    }

    fn meter(&self) -> f32 {
        self.meter
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::effect::limiter_param as p;

    const RATE: f64 = 48_000.0;

    fn peak(x: &[f32]) -> f32 {
        x.iter().fold(0.0f32, |m, v| m.max(v.abs()))
    }

    fn lim(lookahead: f32, ceiling: f32, link: f32) -> Limiter {
        let mut l = Limiter::new(RATE);
        l.set_param(p::LOOKAHEAD, lookahead);
        l.set_param(p::CEILING, ceiling);
        l.set_param(p::LINK, link);
        l
    }

    /// Material cruel: senoide com degraus, picos isolados de um quadro (o que vaza com janelas
    /// curtas demais), ruído e um lado só.
    fn nasty(n: usize) -> (Vec<f32>, Vec<f32>) {
        let mut rng = crate::dsp::Rng::new(5);
        (0..n)
            .map(|i| {
                let base = (i as f32 * 0.05).sin() * if (i / 7000) % 2 == 1 { 3.0 } else { 0.4 };
                let spike = if i % 997 == 0 {
                    8.0
                } else if i % 1511 == 0 {
                    -5.0
                } else {
                    0.0
                };
                let noise = if (i / 5000) % 3 == 2 { rng.bipolar() * 2.0 } else { 0.0 };
                let l = base + spike + noise;
                let r = if (i / 9000) % 2 == 1 { 0.0 } else { -base * 0.7 + noise };
                (l, r)
            })
            .unzip()
    }

    #[test]
    fn nunca_passa_do_teto() {
        for lookahead in [0.0, 0.0005, 0.003, 0.01] {
            for link in [0.0, 0.5, 1.0] {
                for (gain, ceiling) in [(0.0, -0.3), (24.0, -6.0), (12.0, -24.0)] {
                    let mut lm = lim(lookahead, ceiling, link);
                    lm.set_param(p::GAIN, gain);
                    lm.set_param(p::RELEASE, 0.001);
                    let (mut l, mut r) = nasty(48_000);
                    for (cl, cr) in l.chunks_mut(128).zip(r.chunks_mut(128)) {
                        lm.process(cl, cr);
                    }
                    let max = peak(&l).max(peak(&r));
                    let top = db_to_amp(ceiling);
                    assert!(max <= top * (1.0 + 1e-6), "la {lookahead} link {link} ganho {gain}: {max} > {top}");
                    assert!(lm.meter().is_finite());
                }
            }
        }
    }

    #[test]
    fn latencia_e_o_lookahead() {
        for (secs, frames) in [(0.0, 0), (0.001, 48), (0.003, 144), (0.01, 480), (1.0, 480)] {
            let mut lm = lim(secs, 0.0, 1.0);
            assert_eq!(lm.latency(), frames, "{secs} s");
            // um impulso abaixo do teto sai intacto, `frames` quadros depois
            let (mut l, mut r) = (vec![0.0; 1024], vec![0.0; 1024]);
            l[10] = 0.5;
            r[10] = -0.25;
            lm.process(&mut l, &mut r);
            let at = l.iter().position(|&v| v != 0.0).unwrap();
            assert_eq!(at, 10 + frames);
            assert!((l[at] - 0.5).abs() < 1e-6);
            assert!((r[at] + 0.25).abs() < 1e-6);
        }
        assert_eq!(Limiter::new(44_100.0).latency(), 132);
    }

    #[test]
    fn abaixo_do_teto_e_transparente() {
        let mut lm = lim(0.002, 0.0, 1.0);
        let d = lm.latency();
        let src: Vec<f32> = (0..9600).map(|i| (i as f32 * 0.013).sin() * 0.9).collect();
        let (mut l, mut r) = (src.clone(), src.clone());
        for (cl, cr) in l.chunks_mut(128).zip(r.chunks_mut(128)) {
            lm.process(cl, cr);
        }
        for i in d..src.len() {
            assert!((l[i] - src[i - d]).abs() < 1e-6, "{i}");
        }
        assert_eq!(lm.meter(), 0.0);
    }

    #[test]
    fn teto_baixo_so_segura_o_que_passa_dele() {
        // teto em −12 dB: o que fica abaixo sai igual (o teto não é um volume de saída), o que
        // passa é segurado nele
        let mut lm = lim(0.002, -12.0, 1.0);
        let d = lm.latency();
        let quiet: Vec<f32> = (0..9600).map(|i| (i as f32 * 0.013).sin() * 0.2).collect();
        let (mut l, mut r) = (quiet.clone(), quiet.clone());
        for (cl, cr) in l.chunks_mut(128).zip(r.chunks_mut(128)) {
            lm.process(cl, cr);
        }
        for i in d..quiet.len() {
            assert!((l[i] - quiet[i - d]).abs() < 1e-6, "{i}");
        }
        let loud: Vec<f32> = (0..9600).map(|i| (i as f32 * 0.013).sin() * 0.9).collect();
        let (mut l, mut r) = (loud.clone(), loud);
        for (cl, cr) in l.chunks_mut(128).zip(r.chunks_mut(128)) {
            lm.process(cl, cr);
        }
        let top = db_to_amp(-12.0);
        assert!(peak(&l[4800..]) <= top * (1.0 + 1e-6) && peak(&l[4800..]) > top * 0.95);
        assert!((lm.meter() - 20.0 * (0.9 / top).log10()).abs() < 0.5, "{}", lm.meter());
    }

    #[test]
    fn reduz_e_solta() {
        let mut lm = lim(0.003, -1.0, 1.0);
        lm.set_param(p::GAIN, 12.0);
        lm.set_param(p::RELEASE, 0.05);
        let src: Vec<f32> = (0..24_000).map(|i| (i as f32 * 0.03).sin() * 0.5).collect();
        let (mut l, mut r) = (src.clone(), src.clone());
        for (cl, cr) in l.chunks_mut(128).zip(r.chunks_mut(128)) {
            lm.process(cl, cr);
        }
        // 0,5 com +12 dB = +6 dBFS, teto em −1 dB: reduz ~7 dB e enche até perto do teto
        assert!((lm.meter() - 7.0).abs() < 0.5, "{}", lm.meter());
        assert!(peak(&l[20_000..]) > db_to_amp(-1.0) * 0.9);
        // silêncio: o ganho volta (o medidor é o do último bloco)
        for _ in 0..200 {
            let (mut l, mut r) = (vec![0.0; 128], vec![0.0; 128]);
            lm.process(&mut l, &mut r);
        }
        assert!(lm.meter() < 0.01, "{}", lm.meter());
    }

    #[test]
    fn ligacao_estereo() {
        // só a esquerda passa do teto: ligado, a direita abaixa junto; solto, fica intacta
        let run = |link: f32| {
            let mut lm = lim(0.002, 0.0, link);
            let (mut l, mut r): (Vec<f32>, Vec<f32>) = (0..9600).map(|i| ((i as f32 * 0.03).sin() * 2.0, (i as f32 * 0.03).sin() * 0.5)).unzip();
            for (cl, cr) in l.chunks_mut(128).zip(r.chunks_mut(128)) {
                lm.process(cl, cr);
            }
            peak(&r[4800..])
        };
        assert!(run(1.0) < 0.3);
        assert!((run(0.0) - 0.5).abs() < 0.01);
    }

    #[test]
    fn trocar_o_lookahead_tocando() {
        let mut lm = lim(0.001, -3.0, 1.0);
        lm.set_param(p::GAIN, 12.0);
        let (mut l, mut r): (Vec<f32>, Vec<f32>) = (0..96_000).map(|i| ((i as f32 * 0.05).sin() * 0.5, (i as f32 * 0.05).sin() * -0.5)).unzip();
        for (i, (cl, cr)) in l.chunks_mut(128).zip(r.chunks_mut(128)).enumerate() {
            match i {
                100 => lm.set_param(p::LOOKAHEAD, 0.01),
                103 => lm.set_param(p::LOOKAHEAD, 0.0),
                300 => lm.set_param(p::LOOKAHEAD, 0.005),
                _ => {}
            }
            lm.process(cl, cr);
        }
        assert_eq!(lm.latency(), 240);
        assert!(peak(&l).max(peak(&r)) <= db_to_amp(-3.0) * (1.0 + 1e-6));
        assert!(l.iter().chain(&r).all(|v| v.is_finite()));
        // a troca desce e sobe em rampa: pular a leitura do atraso daria saltos de até 1,4
        let step = l.windows(2).fold(0.0f32, |m, w| m.max((w[1] - w[0]).abs()));
        assert!(step < 0.2, "{step}");
    }

    #[test]
    fn extremos_sem_nan() {
        for rate in [8_000.0, 44_100.0, 192_000.0] {
            let mut lm = Limiter::new(rate);
            for (id, v) in [(0, 1e9), (1, 1e9), (2, 0.0), (3, 1e9), (4, -1e9), (9, 1.0)] {
                lm.set_param(id, v);
                lm.set_param(id, f32::NAN);
            }
            let mut rng = crate::dsp::Rng::new(1);
            let (mut l, mut r): (Vec<f32>, Vec<f32>) = (0..8192).map(|_| (rng.bipolar() * 1e30, rng.bipolar())).unzip();
            l[5] = f32::NAN;
            r[9] = f32::INFINITY;
            for (cl, cr) in l.chunks_mut(100).zip(r.chunks_mut(100)) {
                lm.process(cl, cr);
            }
            assert!(l.iter().chain(&r).all(|v| v.is_finite() && v.abs() <= 1.0));
            assert!(lm.meter().is_finite());
            // lookahead mudando a cada bloco
            for i in 0..100 {
                lm.set_param(p::LOOKAHEAD, (i % 5) as f32 * 0.0025);
                let (mut l, mut r) = (vec![3.0; 64], vec![-3.0; 64]);
                lm.process(&mut l, &mut r);
                assert!(l.iter().chain(&r).all(|v| v.is_finite() && v.abs() <= 1.0));
            }
        }
    }
}
