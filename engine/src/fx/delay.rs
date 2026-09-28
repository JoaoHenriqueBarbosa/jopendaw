//! Delay estéreo: até 4 s de eco, livre ou no andamento, com ping-pong, desvio entre os canais,
//! filtros e saturação na realimentação, wow/flutter de fita e ducking.
//!
//! Cada canal tem uma linha de atraso pré-alocada para o tempo máximo. Filtros e saturação ficam
//! no caminho de gravação (entrada + realimentação), então cada repetição passa por eles mais uma
//! vez: os ecos escurecem e afinam aos poucos, como numa fita.
//!
//! Mudança de tempo: diferenças pequenas (automação de andamento) deslizam a cabeça de leitura com
//! velocidade limitada (no máximo ±2% de afinação); saltos maiores (outra figura, outro tempo,
//! botão arrastado) fazem um crossfade de 60 ms entre a cabeça velha e a nova, sem glissando e sem
//! estalo.
//!
//! Aqui também ficam as peças que os outros efeitos de espaço e modulação compartilham: a linha de
//! atraso com leitura fracionária, as cabeças de leitura que mudam de posição sem estalo (o
//! pré-atraso do reverb usa as mesmas), o limite de segurança das realimentações e a mistura de
//! potência constante.

use std::f32::consts::{FRAC_PI_2, SQRT_2};

use crate::dsp::{FilterMode, Smoothed, Svf, fast_tanh, sin_turns, smoothing};
use crate::effect::{Effect, NOTE_BEATS, delay_param as P};

/// Abaixo disto a entrada conta como silêncio (−160 dBFS): os efeitos de cauda longa dormem.
pub(crate) const SILENCE: f32 = 1e-8;

/// Linha de atraso circular de tamanho fixo, alocada uma vez. `tap(0)` é o último valor escrito.
pub(crate) struct DelayLine {
    buf: Box<[f32]>,
    /// Onde vai a próxima escrita.
    pos: usize,
}

impl DelayLine {
    /// Uma linha que guarda `len` quadros; o maior atraso legível fica uns quadros abaixo disso.
    pub(crate) fn new(len: usize) -> Self {
        Self { buf: vec![0.0; len.max(8)].into_boxed_slice(), pos: 0 }
    }

    pub(crate) fn len(&self) -> usize {
        self.buf.len()
    }

    pub(crate) fn clear(&mut self) {
        self.buf.fill(0.0);
        self.pos = 0;
    }

    #[inline]
    pub(crate) fn write(&mut self, x: f32) {
        self.buf[self.pos] = x;
        self.pos += 1;
        if self.pos == self.buf.len() {
            self.pos = 0;
        }
    }

    /// Índice do valor escrito `d` quadros antes do último (`d < len`).
    #[inline]
    fn index(&self, d: usize) -> usize {
        let n = self.buf.len();
        let i = self.pos + n - 1 - d;
        if i >= n { i - n } else { i }
    }

    /// O índice um quadro mais velho.
    #[inline]
    fn older(&self, i: usize) -> usize {
        if i == 0 { self.buf.len() - 1 } else { i - 1 }
    }

    /// O valor escrito `d` quadros antes do último (`d = 0`: o último), `d < len`.
    #[inline]
    pub(crate) fn tap(&self, d: usize) -> f32 {
        self.buf[self.index(d)]
    }

    /// Leitura fracionária linear, `d` em [0, len − 2]. Barata; boa para taps fixos, onde a posição
    /// só é fracionária enquanto desliza.
    #[inline]
    pub(crate) fn linear(&self, d: f32) -> f32 {
        // `max` antes de `min`: um NaN vira 0 em vez de um índice absurdo
        let d = d.max(0.0).min((self.buf.len() - 2) as f32);
        let i = d as usize;
        let f = d - i as f32;
        let k = self.index(i);
        let y0 = self.buf[k];
        let y1 = self.buf[self.older(k)];
        y0 + f * (y1 - y0)
    }

    /// Leitura fracionária por Hermite de 4 pontos (Catmull-Rom), `d` em [1, len − 3]: plana até
    /// bem alto no espectro e sem o abafamento que a linear impõe a um atraso modulado.
    #[inline]
    pub(crate) fn hermite(&self, d: f32) -> f32 {
        let d = d.max(1.0).min((self.buf.len() - 3) as f32);
        let i = d as usize;
        let f = d - i as f32;
        let k0 = self.index(i - 1);
        let k1 = self.older(k0);
        let k2 = self.older(k1);
        let k3 = self.older(k2);
        let (ym1, y0, y1, y2) = (self.buf[k0], self.buf[k1], self.buf[k2], self.buf[k3]);
        let c1 = 0.5 * (y1 - ym1);
        let c2 = ym1 - 2.5 * y0 + 2.0 * y1 - 0.5 * y2;
        let c3 = 0.5 * (y2 - ym1) + 1.5 * (y0 - y1);
        ((c3 * f + c2) * f + c1) * f + y0
    }
}

/// Limite de segurança das realimentações: linear até ±2 e saturando suave até ±4. Não colore o
/// uso normal; só impede que uma ressonância ou um arredondamento faça a malha disparar.
#[inline]
pub(crate) fn safety(x: f32) -> f32 {
    let a = x.abs();
    if a <= 2.0 { x } else { (2.0 + 2.0 * fast_tanh((a - 2.0) * 0.5)).copysign(x) }
}

/// Zera o que já é inaudível antes de gravar numa malha: sem isso a cauda decai até virar
/// denormal, e o WASM não tem flush-to-zero.
#[inline]
pub(crate) fn flush(x: f32) -> f32 {
    if x.abs() < 1e-20 { 0.0 } else { x }
}

/// Ganhos seco e molhado de potência constante: o molhado de um espaço não se correlaciona com o
/// seco, e a soma mantém o volume em qualquer mistura. `mix = 0` devolve exatamente o seco.
pub(crate) fn equal_power(mix: f32) -> (f32, f32) {
    if mix <= 0.0 {
        (1.0, 0.0)
    } else if mix >= 1.0 {
        (0.0, 1.0)
    } else {
        let a = mix * FRAC_PI_2;
        (a.cos(), a.sin())
    }
}

/// Pico absoluto de um bloco estéreo.
pub(crate) fn peak(left: &[f32], right: &[f32]) -> f32 {
    left.iter().chain(right).fold(0.0f32, |m, x| m.max(x.abs()))
}

/// Um valor interpolado linearmente ao longo de um bloco de controle.
#[derive(Clone, Copy, Debug, Default)]
pub(crate) struct Ramp {
    pub value: f32,
    pub step: f32,
}

impl Ramp {
    pub(crate) fn new(from: f32, to: f32, frames: usize) -> Self {
        Self { value: from, step: (to - from) / frames as f32 }
    }

    /// Devolve o valor atual e anda um quadro.
    #[inline]
    pub(crate) fn next(&mut self) -> f32 {
        let v = self.value;
        self.value += self.step;
        v
    }
}

/// Duração do crossfade entre a cabeça velha e a nova num salto de posição.
const XFADE_SECS: f32 = 0.06;
/// Velocidade máxima do deslize de uma cabeça, em quadros por quadro (±2% de afinação).
const GLIDE_SLOPE: f32 = 0.02;
/// Diferença acima da qual deslizar demoraria mais de 250 ms: vira crossfade.
const GLIDE_MAX_SECS: f32 = 0.005;

/// Cabeças de leitura (uma por canal) que mudam de posição sem estalo e sem glissando exagerado:
/// diferenças pequenas (automação de andamento, botão girado devagar) deslizam com velocidade
/// limitada; saltos fazem um crossfade de potência constante entre a posição velha e a nova. Um
/// salto que chega durante um crossfade espera ele terminar.
pub(crate) struct Heads<const N: usize> {
    pos: [f32; N],
    old: [f32; N],
    /// Progresso do crossfade, 0..1 (1 = só a cabeça nova toca).
    fade: f32,
}

/// O percurso das cabeças num bloco de controle.
pub(crate) struct HeadBlock<const N: usize> {
    pub pos: [Ramp; N],
    pub old: [Ramp; N],
    pub gain: Ramp,
    pub old_gain: Ramp,
    /// Há crossfade neste bloco: só então vale ler a cabeça velha.
    pub fading: bool,
}

impl<const N: usize> Heads<N> {
    pub(crate) fn new(pos: [f32; N]) -> Self {
        Self { pos, old: pos, fade: 1.0 }
    }

    pub(crate) fn settled(&self) -> bool {
        self.fade >= 1.0
    }

    /// Anda um bloco de `len` quadros rumo a `target`.
    pub(crate) fn advance(&mut self, target: [f32; N], len: usize, rate: f32) -> HeadBlock<N> {
        let mut start = self.pos;
        if self.fade >= 1.0 {
            let jump = self.pos.iter().zip(&target).fold(0.0f32, |m, (p, t)| m.max((t - p).abs()));
            if jump > GLIDE_MAX_SECS * rate {
                self.old = self.pos;
                self.pos = target;
                start = target;
                self.fade = 0.0;
            } else {
                let limit = GLIDE_SLOPE * len as f32;
                for (p, t) in self.pos.iter_mut().zip(target) {
                    *p += (t - *p).clamp(-limit, limit);
                }
            }
        }
        let fading = self.fade < 1.0;
        let fade0 = self.fade;
        let fade1 = (fade0 + len as f32 / (XFADE_SECS * rate)).min(1.0);
        self.fade = fade1;
        let (s0, c0) = (fade0 * FRAC_PI_2).sin_cos();
        let (s1, c1) = if fade1 >= 1.0 { (1.0, 0.0) } else { (fade1 * FRAC_PI_2).sin_cos() };
        HeadBlock {
            pos: std::array::from_fn(|c| Ramp::new(start[c], self.pos[c], len)),
            old: std::array::from_fn(|c| Ramp::new(self.old[c], self.old[c], len)),
            gain: Ramp::new(s0, s1, len),
            old_gain: Ramp::new(c0, c1, len),
            fading,
        }
    }
}

/// Quadros por bloco de controle: coeficientes e alvos mudam a cada bloco, ganhos e posições de
/// leitura andam por quadro, interpolados.
const CONTROL: usize = 32;
const MIN_SECS: f32 = 0.001;
const MAX_SECS: f32 = 4.0;
const PARAM_TAU: f32 = 0.02;
/// Wow (lento, largo) e flutter (rápido, estreito) no máximo da modulação. A excursão só soma
/// atraso, então o tempo mínimo continua legível.
const WOW_SECS: f32 = 0.0018;
const WOW_HZ: f32 = 0.55;
const FLUTTER_SECS: f32 = 0.00012;
const FLUTTER_HZ: f32 = 6.3;
const DUCK_ATTACK: f32 = 0.01;
const DUCK_RELEASE: f32 = 0.3;
/// Nível de entrada (−20 dBFS) a partir do qual o ducking abaixa os ecos por inteiro.
const DUCK_FULL: f32 = 0.1;
/// Joelho da saturação com o drive no máximo (−12 dBFS); com drive d o joelho fica em
/// `DRIVE_KNEE / d`, então drive baixo quase não toca no sinal.
const DRIVE_KNEE: f32 = 0.25;

pub struct Delay {
    rate: f32,
    lines: [DelayLine; 2],
    mix: Smoothed,
    feedback: Smoothed,
    /// 0 estéreo normal, 1 ping-pong; suavizado, a troca de rota não estala.
    ping_pong: Smoothed,
    high_pass: Smoothed,
    low_pass: Smoothed,
    modulation: Smoothed,
    drive: Smoothed,
    ducking: Smoothed,
    sync: bool,
    time: f32,
    note: usize,
    offset: f32,
    bpm: f64,
    /// Posições de leitura por canal, em quadros (já descontado o quadro que a leitura antes da
    /// escrita adianta).
    heads: Heads<2>,
    hp: [Svf; 2],
    lp: [Svf; 2],
    env: f32,
    duck_attack: f32,
    duck_release: f32,
    wow: f32,
    flutter: f32,
    /// Quadros seguidos de silêncio na entrada e nos ecos.
    silent: usize,
    idle: bool,
    primed: bool,
}

impl Delay {
    pub fn new(rate: f64) -> Self {
        let rate = rate as f32;
        let span = MAX_SECS + 2.0 * (WOW_SECS + FLUTTER_SECS);
        let len = (span * rate).ceil() as usize + 8;
        let mut d = Self {
            rate,
            lines: [DelayLine::new(len), DelayLine::new(len)],
            mix: Smoothed::new(0.3),
            feedback: Smoothed::new(0.4),
            ping_pong: Smoothed::new(0.0),
            high_pass: Smoothed::new(80.0),
            low_pass: Smoothed::new(8000.0),
            modulation: Smoothed::new(0.0),
            drive: Smoothed::new(0.0),
            ducking: Smoothed::new(0.0),
            sync: true,
            time: 0.375,
            note: 6,
            offset: 0.0,
            bpm: 120.0,
            heads: Heads::new([0.0; 2]),
            hp: [Svf::default(); 2],
            lp: [Svf::default(); 2],
            env: 0.0,
            duck_attack: (-1.0 / (DUCK_ATTACK * rate)).exp(),
            duck_release: (-1.0 / (DUCK_RELEASE * rate)).exp(),
            wow: 0.0,
            flutter: 0.37,
            silent: 0,
            idle: false,
            primed: false,
        };
        d.heads = Heads::new(d.target());
        d
    }

    /// Posições de leitura pedidas pelos parâmetros, por canal.
    fn target(&self) -> [f32; 2] {
        let base = if self.sync { (NOTE_BEATS[self.note] * 60.0 / self.bpm) as f32 } else { self.time };
        let base = base.clamp(MIN_SECS, MAX_SECS);
        let half = self.offset * 0.5;
        let frames = |secs: f32| secs.clamp(MIN_SECS, MAX_SECS) * self.rate - 1.0;
        [frames(base - half), frames(base + half)]
    }

    fn params(&mut self) -> [&mut Smoothed; 8] {
        [
            &mut self.mix,
            &mut self.feedback,
            &mut self.ping_pong,
            &mut self.high_pass,
            &mut self.low_pass,
            &mut self.modulation,
            &mut self.drive,
            &mut self.ducking,
        ]
    }

    fn prime(&mut self) {
        for p in self.params() {
            p.snap();
        }
        self.heads = Heads::new(self.target());
        self.primed = true;
    }

    /// Excursão do wow/flutter por canal, em quadros, nas fases dadas.
    fn wobble(&self, depth: f32, wow: f32, flutter: f32) -> [f32; 2] {
        let at = |w: f32, f: f32| depth * self.rate * (WOW_SECS * (1.0 + sin_turns(w)) + FLUTTER_SECS * (1.0 + sin_turns(f)));
        // a direita anda um pouco defasada: a fita é a mesma, mas o eco ganha largura
        [at(wow, flutter), at(wow + 0.13, flutter + 0.29)]
    }

    fn block(&mut self, left: &mut [f32], right: &mut [f32]) -> f32 {
        let len = left.len();
        let rate = self.rate;
        let a = smoothing(PARAM_TAU, len, rate);
        let (dry0, wet0) = equal_power(self.mix.value);
        let (dry1, wet1) = equal_power(self.mix.step(a));
        let fb0 = self.feedback.value;
        let fb1 = self.feedback.step(a);
        let pp0 = self.ping_pong.value;
        let pp1 = self.ping_pong.step(a);
        let duck = self.ducking.step(a);
        let drive = self.drive.step(a);
        let nyquist = 0.45 * rate;
        let g_hp = Svf::g(self.high_pass.step(a).min(nyquist), rate);
        let g_lp = Svf::g(self.low_pass.step(a).min(nyquist), rate);
        for c in 0..2 {
            self.hp[c].set(g_hp, SQRT_2);
            self.lp[c].set(g_lp, SQRT_2);
        }

        let HeadBlock { mut pos, mut old, mut gain, mut old_gain, fading } = self.heads.advance(self.target(), len, rate);
        let depth0 = self.modulation.value;
        let depth1 = self.modulation.step(a);
        let m0 = self.wobble(depth0, self.wow, self.flutter);
        self.wow = (self.wow + WOW_HZ * len as f32 / rate).fract();
        self.flutter = (self.flutter + FLUTTER_HZ * len as f32 / rate).fract();
        let m1 = self.wobble(depth1, self.wow, self.flutter);
        let mut wobble = [Ramp::new(m0[0], m1[0], len), Ramp::new(m0[1], m1[1], len)];
        let mut dry = Ramp::new(dry0, dry1, len);
        let mut wet = Ramp::new(wet0, wet1, len);
        let mut fb = Ramp::new(fb0, fb1, len);
        let mut pp = Ramp::new(pp0, pp1, len);
        // saturação: y = T·tanh(x/T), passiva (|y| ≤ |x|), então não sustenta a malha sozinha
        let knee = if drive > 1e-4 { DRIVE_KNEE / drive } else { 0.0 };
        let inv_knee = if knee > 0.0 { 1.0 / knee } else { 0.0 };

        let mut out_peak = 0.0f32;
        for (l, r) in left.iter_mut().zip(right.iter_mut()) {
            let (xl, xr) = (*l, *r);
            let level = xl.abs().max(xr.abs());
            let coef = if level > self.env { self.duck_attack } else { self.duck_release };
            self.env = level + (self.env - level) * coef;

            let (ml, mr) = (wobble[0].next(), wobble[1].next());
            let mut yl = self.lines[0].hermite(pos[0].next() + ml);
            let mut yr = self.lines[1].hermite(pos[1].next() + mr);
            if fading {
                let (wn, wo) = (gain.next(), old_gain.next());
                yl = yl * wn + self.lines[0].hermite(old[0].next() + ml) * wo;
                yr = yr * wn + self.lines[1].hermite(old[1].next() + mr) * wo;
            }

            // rota: no ping-pong a entrada (mono) entra só na esquerda e cada canal realimenta o
            // outro; o eco atravessa o estéreo a cada repetição
            let p = pp.next();
            let g = fb.next();
            let mono = (xl + xr) * 0.5;
            let mut wl = xl + p * (mono - xl) + g * (yl + p * (yr - yl));
            let mut wr = xr * (1.0 - p) + g * (yr + p * (yl - yr));
            wl = self.lp[0].tick(self.hp[0].tick(wl, FilterMode::HighPass).0, FilterMode::LowPass).0;
            wr = self.lp[1].tick(self.hp[1].tick(wr, FilterMode::HighPass).0, FilterMode::LowPass).0;
            if knee > 0.0 {
                wl = knee * fast_tanh(wl * inv_knee);
                wr = knee * fast_tanh(wr * inv_knee);
            }
            self.lines[0].write(flush(safety(wl)));
            self.lines[1].write(flush(safety(wr)));

            let ducked = wet.next() * (1.0 - duck * (self.env * (1.0 / DUCK_FULL)).min(1.0));
            let d = dry.next();
            *l = xl * d + yl * ducked;
            *r = xr * d + yr * ducked;
            out_peak = out_peak.max(yl.abs()).max(yr.abs());
        }
        for f in self.hp.iter_mut().chain(self.lp.iter_mut()) {
            f.flush();
        }
        if self.env < 1e-12 {
            self.env = 0.0;
        }
        out_peak
    }
}

impl Effect for Delay {
    fn set_param(&mut self, id: u32, value: f32) {
        if !value.is_finite() {
            return;
        }
        let pick = |v: f32, n: usize| (v.round().max(0.0) as usize).min(n - 1);
        match id {
            P::MIX => self.mix.set(value.clamp(0.0, 1.0)),
            P::SYNC => self.sync = value >= 0.5,
            P::TIME => self.time = value.clamp(MIN_SECS, MAX_SECS),
            P::NOTE => self.note = pick(value, NOTE_BEATS.len()),
            P::FEEDBACK => self.feedback.set(value.clamp(0.0, 0.98)),
            P::PING_PONG => self.ping_pong.set(if value >= 0.5 { 1.0 } else { 0.0 }),
            P::OFFSET => self.offset = value.clamp(-0.05, 0.05),
            P::HIGH_PASS => self.high_pass.set(value.clamp(20.0, 2000.0)),
            P::LOW_PASS => self.low_pass.set(value.clamp(500.0, 20000.0)),
            P::MODULATION => self.modulation.set(value.clamp(0.0, 1.0)),
            P::DRIVE => self.drive.set(value.clamp(0.0, 1.0)),
            P::DUCKING => self.ducking.set(value.clamp(0.0, 1.0)),
            _ => {}
        }
    }

    fn set_tempo(&mut self, bpm: f64) {
        if bpm.is_finite() && bpm > 0.0 {
            self.bpm = bpm.clamp(10.0, 1000.0);
        }
    }

    fn process(&mut self, left: &mut [f32], right: &mut [f32]) {
        let n = left.len().min(right.len());
        if n == 0 {
            return;
        }
        if !self.primed {
            self.prime();
        }
        let input = peak(&left[..n], &right[..n]);
        if self.idle {
            if input < SILENCE {
                // nada nas linhas nem chegando: só o seco passa, sem gastar nada
                let (dry, _) = equal_power(self.mix.target);
                self.mix.snap();
                for x in left[..n].iter_mut().chain(right[..n].iter_mut()) {
                    *x *= dry;
                }
                return;
            }
            self.idle = false;
        }
        let mut echoes = 0.0f32;
        let mut done = 0;
        while done < n {
            let len = (n - done).min(CONTROL);
            echoes = echoes.max(self.block(&mut left[done..done + len], &mut right[done..done + len]));
            done += len;
        }
        if !(echoes.is_finite() && left[n - 1].is_finite() && right[n - 1].is_finite()) {
            // um NaN que entrou (de cima ou de um arredondamento) envenenaria a malha para sempre
            self.reset();
            left[..n].fill(0.0);
            right[..n].fill(0.0);
            return;
        }
        if input < SILENCE && echoes < SILENCE {
            self.silent += n;
            // tudo o que está nas linhas foi gravado depois que o som acabou: pode dormir
            if self.silent > self.lines[0].len() && self.heads.settled() {
                self.idle = true;
            }
        } else {
            self.silent = 0;
        }
    }

    fn reset(&mut self) {
        for line in &mut self.lines {
            line.clear();
        }
        for f in self.hp.iter_mut().chain(self.lp.iter_mut()) {
            f.reset();
        }
        self.env = 0.0;
        self.silent = 0;
        self.idle = false;
        self.prime();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const RATE: f64 = 48_000.0;

    fn run(d: &mut Delay, left: &mut [f32], right: &mut [f32]) {
        for (l, r) in left.chunks_mut(128).zip(right.chunks_mut(128)) {
            d.process(l, r);
        }
    }

    fn clean(d: &mut Delay) {
        d.set_param(P::MIX, 1.0);
        d.set_param(P::HIGH_PASS, 20.0);
        d.set_param(P::LOW_PASS, 20000.0);
        d.set_param(P::FEEDBACK, 0.0);
    }

    fn noise(n: usize, seed: u32) -> Vec<f32> {
        let mut rng = crate::dsp::Rng::new(seed);
        (0..n).map(|_| rng.bipolar() * 0.5).collect()
    }

    #[test]
    fn linha_le_fracionario() {
        let mut line = DelayLine::new(64);
        for i in 0..64 {
            line.write(i as f32);
        }
        // rampa: qualquer interpolação decente acerta no meio do caminho
        assert_eq!(line.tap(0), 63.0);
        assert_eq!(line.tap(10), 53.0);
        assert!((line.linear(2.25) - 60.75).abs() < 1e-4);
        assert!((line.hermite(5.5) - 57.5).abs() < 1e-4);
        assert!((line.hermite(f32::NAN) - 62.0).abs() < 1e-4);
    }

    #[test]
    fn sincronizado_a_120_bpm_seminima_ecoa_em_meio_segundo() {
        let mut d = Delay::new(RATE);
        clean(&mut d);
        d.set_param(P::SYNC, 1.0);
        d.set_param(P::NOTE, 8.0);
        d.set_tempo(120.0);
        let n = 30_000;
        let mut l = vec![0.0; n];
        let mut r = vec![0.0; n];
        l[0] = 1.0;
        r[0] = 1.0;
        run(&mut d, &mut l, &mut r);
        let (at, _) = l.iter().enumerate().fold((0, 0.0f32), |(bi, bv), (i, v)| if v.abs() > bv { (i, v.abs()) } else { (bi, bv) });
        assert!((at as i64 - 24_000).abs() <= 2, "eco em {at}");
        assert!(l[..23_900].iter().all(|v| v.abs() < 1e-3), "som antes do eco");
    }

    #[test]
    fn tempo_livre_e_desvio() {
        let mut d = Delay::new(RATE);
        clean(&mut d);
        d.set_param(P::SYNC, 0.0);
        d.set_param(P::TIME, 0.1);
        d.set_param(P::OFFSET, 0.02);
        let n = 8_000;
        let mut l = vec![0.0; n];
        let mut r = vec![0.0; n];
        l[0] = 1.0;
        r[0] = 1.0;
        run(&mut d, &mut l, &mut r);
        let argmax = |v: &[f32]| v.iter().enumerate().fold((0, 0.0f32), |(bi, bv), (i, x)| if x.abs() > bv { (i, x.abs()) } else { (bi, bv) }).0;
        assert!((argmax(&l) as i64 - 4320).abs() <= 2, "esquerda em {}", argmax(&l));
        assert!((argmax(&r) as i64 - 5280).abs() <= 2, "direita em {}", argmax(&r));
    }

    #[test]
    fn ping_pong_alterna_os_lados() {
        let mut d = Delay::new(RATE);
        clean(&mut d);
        d.set_param(P::SYNC, 0.0);
        d.set_param(P::TIME, 0.05);
        d.set_param(P::FEEDBACK, 0.5);
        d.set_param(P::PING_PONG, 1.0);
        let n = 12_000;
        let mut l = vec![0.0; n];
        let mut r = vec![0.0; n];
        l[0] = 1.0;
        r[0] = 1.0;
        run(&mut d, &mut l, &mut r);
        // 1º eco (2400) só na esquerda, 2º (4800) só na direita, 3º (7200) de novo na esquerda
        let around = |v: &[f32], at: usize| v[at - 8..at + 8].iter().fold(0.0f32, |m, x| m.max(x.abs()));
        assert!(around(&l, 2400) > 0.5 && around(&r, 2400) < 1e-3);
        assert!(around(&r, 4800) > 0.25 && around(&l, 4800) < 1e-3);
        assert!(around(&l, 7200) > 0.12 && around(&r, 7200) < 1e-3);
    }

    #[test]
    fn realimentacao_no_maximo_e_estavel() {
        for (pp, drive, modulation) in [(0.0, 0.0, 1.0), (1.0, 0.0, 0.0), (1.0, 1.0, 1.0), (0.0, 0.5, 0.5)] {
            let mut d = Delay::new(RATE);
            d.set_param(P::MIX, 1.0);
            d.set_param(P::SYNC, 0.0);
            d.set_param(P::TIME, 0.01);
            d.set_param(P::FEEDBACK, 0.98);
            d.set_param(P::HIGH_PASS, 20.0);
            d.set_param(P::LOW_PASS, 20000.0);
            d.set_param(P::PING_PONG, pp);
            d.set_param(P::DRIVE, drive);
            d.set_param(P::MODULATION, modulation);
            let n = 48_000 * 20;
            let mut l = noise(n, 3);
            let mut r = noise(n, 5);
            for v in l[24_000..].iter_mut().chain(r[24_000..].iter_mut()) {
                *v = 0.0;
            }
            run(&mut d, &mut l, &mut r);
            assert!(l.iter().chain(&r).all(|v| v.is_finite()));
            let top = peak(&l, &r);
            assert!(top < 8.0, "pico {top}");
            // e a cauda morre: 0,98 por repetição de 10 ms = −17,5 dB/s
            let late = peak(&l[n - 4800..], &r[n - 4800..]);
            assert!(late < top * 1e-3, "cauda {late} de {top}");
        }
    }

    #[test]
    fn mudar_o_andamento_nao_estala() {
        let mut d = Delay::new(RATE);
        clean(&mut d);
        d.set_param(P::FEEDBACK, 0.5);
        d.set_param(P::SYNC, 1.0);
        d.set_param(P::NOTE, 8.0);
        d.set_tempo(120.0);
        let n = 48_000 * 3;
        let tone = |i: usize| (i as f32 * 220.0 / 48_000.0 * std::f32::consts::TAU).sin() * 0.5;
        let mut l: Vec<f32> = (0..n).map(tone).collect();
        let mut r = l.clone();
        let mut worst = 0.0f32;
        let mut last = 0.0f32;
        for (k, (cl, cr)) in l.chunks_mut(128).zip(r.chunks_mut(128)).enumerate() {
            match k {
                400 => d.set_tempo(90.0), // salto: crossfade
                700 => d.set_tempo(90.5), // deslize
                800 => d.set_param(P::NOTE, 5.0),
                _ => {}
            }
            d.process(cl, cr);
            if k > 380 {
                for &v in cl.iter() {
                    worst = worst.max((v - last).abs());
                    last = v;
                }
            } else {
                last = cl[127];
            }
        }
        // uma senoide de 220 Hz em 0,5 anda no máximo 0,0144 por quadro; ecos somados a 1,5 vezes
        // isso. Um estalo passaria de longe.
        assert!(worst < 0.06, "degrau de {worst}");
    }

    #[test]
    fn ducking_abaixa_os_ecos_com_entrada() {
        let render = |ducking: f32| {
            let mut d = Delay::new(RATE);
            clean(&mut d);
            d.set_param(P::SYNC, 0.0);
            d.set_param(P::TIME, 0.1);
            d.set_param(P::FEEDBACK, 0.6);
            d.set_param(P::DUCKING, ducking);
            let n = 48_000;
            let mut l = noise(n, 9);
            let mut r = noise(n, 11);
            run(&mut d, &mut l, &mut r);
            // saída molhada com a entrada tocando
            l[24_000..48_000].iter().map(|v| v * v).sum::<f32>()
        };
        assert!(render(1.0) < render(0.0) * 0.01);
    }

    #[test]
    fn mistura_zero_e_seco_e_extremos_sem_nan() {
        let mut d = Delay::new(RATE);
        d.set_param(P::MIX, 0.0);
        let n = 9_600;
        let src = noise(n, 13);
        let mut l = src.clone();
        let mut r = src.clone();
        run(&mut d, &mut l, &mut r);
        assert!(l.iter().zip(&src).all(|(a, b)| a == b));

        let mut rng = crate::dsp::Rng::new(77);
        let mut d = Delay::new(44_100.0);
        d.set_tempo(300.0);
        for round in 0..40 {
            for id in 0..12 {
                // metade das vezes nos extremos, metade fora da faixa
                let v = match rng.next_u32() % 4 {
                    0 => -1e9,
                    1 => 1e9,
                    2 => rng.unit(),
                    _ => rng.bipolar() * 5.0,
                };
                d.set_param(id, v);
            }
            d.set_param(P::MIX, 1.0);
            let mut l = noise(4410, round);
            let mut r = noise(4410, round + 100);
            l[7] = 40.0;
            run(&mut d, &mut l, &mut r);
            assert!(l.iter().chain(&r).all(|v| v.is_finite() && v.abs() < 50.0), "rodada {round}");
        }
    }

    #[test]
    fn dorme_no_silencio_e_acorda() {
        let mut d = Delay::new(RATE);
        d.set_param(P::FEEDBACK, 0.0);
        let mut l = vec![0.0; 128];
        let mut r = vec![0.0; 128];
        for _ in 0..(5 * 48_000 / 128) {
            l.fill(0.0);
            r.fill(0.0);
            d.process(&mut l, &mut r);
        }
        assert!(d.idle);
        l[0] = 1.0;
        d.process(&mut l, &mut r);
        assert!(!d.idle);
    }
}
