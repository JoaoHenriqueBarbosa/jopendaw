//! Blocos de DSP compartilhados pelos instrumentos (e, depois, pelos efeitos).
//!
//! Tudo aqui roda na thread de áudio: nada aloca, e cada bloco com realimentação se protege de
//! denormais (o WASM não tem flush-to-zero, e um denormal custa dezenas de vezes uma soma normal).

use std::f32::consts::{PI, TAU};

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
    /// Polo com que a sustentação persegue um novo nível (mexer no botão com a nota presa não
    /// pode dar degrau).
    follow: f32,
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
        let rate = rate as f32;
        Self { rate, attack: 0.005, decay: 0.2, sustain: 0.7, release: 0.2, stage: Stage::Idle, value: 0.0, step: 0.0, coef: 0.0, follow: pole(0.02, rate) }
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
    // o nome é contrato com os instrumentos; um envelope não é um `Iterator` (nunca acaba em `None`)
    #[allow(clippy::should_implement_trait)]
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
            Stage::Sustain => {
                let d = self.value - self.sustain;
                self.value = if d.abs() < 1e-5 { self.sustain } else { self.sustain + d * self.follow };
            }
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

/// Um valor que persegue o alvo por um polo: suaviza parâmetros contínuos (sem zipper) quando o
/// botão pula de um valor para outro.
#[derive(Clone, Copy, Debug)]
pub struct Smoothed {
    pub value: f32,
    pub target: f32,
}

impl Smoothed {
    pub fn new(value: f32) -> Self {
        Self { value, target: value }
    }

    pub fn set(&mut self, target: f32) {
        self.target = target;
    }

    /// Pula direto para o alvo.
    pub fn snap(&mut self) {
        self.value = self.target;
    }

    pub fn settled(&self) -> bool {
        self.value == self.target
    }

    /// Anda a fração `a` (0..=1) do caminho e devolve o valor novo. Perto o bastante, encosta no
    /// alvo: sem isso a diferença encolhe até virar denormal.
    #[inline]
    pub fn step(&mut self, a: f32) -> f32 {
        let d = self.target - self.value;
        if d.abs() <= 1e-6 * (1.0 + self.target.abs()) {
            self.value = self.target;
        } else {
            self.value += d * a;
        }
        self.value
    }
}

/// Fração do caminho que um polo com constante de tempo `tau` (segundos) percorre em `frames`.
pub fn smoothing(tau: f32, frames: usize, rate: f32) -> f32 {
    if tau <= 0.0 { 1.0 } else { 1.0 - (-(frames as f32) / (tau * rate)).exp() }
}

/// Gerador pseudoaleatório xorshift32: barato, sem alocação, bom o bastante para ruído e fases.
#[derive(Clone, Debug)]
pub struct Rng(u32);

impl Rng {
    pub fn new(seed: u32) -> Self {
        // o xorshift fica preso no zero
        Self(if seed == 0 { 0x9E37_79B9 } else { seed })
    }

    #[inline]
    pub fn next_u32(&mut self) -> u32 {
        let mut x = self.0;
        x ^= x << 13;
        x ^= x >> 17;
        x ^= x << 5;
        self.0 = x;
        x
    }

    /// Uniforme em [-1, 1).
    #[inline]
    pub fn bipolar(&mut self) -> f32 {
        (self.next_u32() as i32) as f32 * (1.0 / 2_147_483_648.0)
    }

    /// Uniforme em [0, 1).
    #[inline]
    pub fn unit(&mut self) -> f32 {
        (self.next_u32() >> 8) as f32 * (1.0 / 16_777_216.0)
    }
}

/// Resíduo polyBLEP de um degrau de altura 2 (de −1 para +1) na fase 0 de um oscilador com fase
/// `t` em [0, 1) e incremento `dt` por quadro: somado à forma ingênua, arredonda a quina nos dois
/// quadros vizinhos e tira o grosso do aliasing. Para um degrau para baixo, subtraia.
#[inline]
pub fn poly_blep(t: f32, dt: f32) -> f32 {
    if t < dt {
        let x = t / dt;
        x + x - x * x - 1.0
    } else if t > 1.0 - dt {
        let x = (t - 1.0) / dt;
        x * x + x + x + 1.0
    } else {
        0.0
    }
}

/// Resíduo polyBLAMP (a integral do polyBLEP) de uma quina na fase 0: para uma mudança de
/// inclinação de `s` por quadro, some `s * poly_blamp(t, dt)`. É o que tira o aliasing do
/// triângulo, cujas descontinuidades estão na derivada.
#[inline]
pub fn poly_blamp(t: f32, dt: f32) -> f32 {
    let x = if t < dt {
        1.0 - t / dt
    } else if t > 1.0 - dt {
        1.0 - (1.0 - t) / dt
    } else {
        return 0.0;
    };
    x * x * x * (1.0 / 6.0)
}

/// Seno de uma fase em voltas (1 = 2π), por polinômio: a `f32::sin` do WASM é software e custa
/// caro demais para rodar por oscilador por quadro. Erro abaixo de 4e-6 (−108 dB).
#[inline]
pub fn sin_turns(phase: f32) -> f32 {
    let mut x = phase - phase.floor();
    if x >= 0.5 {
        x -= 1.0;
    }
    // simetria em torno de ±¼ de volta: o polinômio só precisa valer em [−π/2, π/2]
    if x > 0.25 {
        x = 0.5 - x;
    } else if x < -0.25 {
        x = -0.5 - x;
    }
    let y = x * TAU;
    let y2 = y * y;
    y * (1.0 + y2 * (-1.0 / 6.0 + y2 * (1.0 / 120.0 + y2 * (-1.0 / 5040.0 + y2 * (1.0 / 362_880.0)))))
}

/// Tangente hiperbólica aproximada (Padé), exata em 0, saturando suave em ±1 a partir de ±3.
#[inline]
pub fn fast_tanh(x: f32) -> f32 {
    let x = x.clamp(-3.0, 3.0);
    let x2 = x * x;
    x * (27.0 + x2) / (27.0 + 9.0 * x2)
}

/// Saída de um [`Svf`].
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum FilterMode {
    LowPass,
    HighPass,
    BandPass,
}

/// Filtro de estado variável de 2 polos (12 dB/oit) na forma TPT de Andrew Simper (Cytomic):
/// estável com qualquer corte e amortecimento positivos e bem-comportado sob modulação rápida,
/// que é o que um filtro de sintetizador sofre o tempo todo.
#[derive(Clone, Copy, Debug)]
pub struct Svf {
    ic1: f32,
    ic2: f32,
    k: f32,
    a1: f32,
    a2: f32,
    a3: f32,
}

impl Default for Svf {
    fn default() -> Self {
        let mut f = Self { ic1: 0.0, ic2: 0.0, k: 0.0, a1: 0.0, a2: 0.0, a3: 0.0 };
        f.set(0.5, 1.0);
        f
    }
}

impl Svf {
    /// O `g` de um corte em Hz (pré-distorcido pela tangente, para o corte cair no lugar certo).
    /// O corte precisa estar abaixo de Nyquist; limite-o antes.
    pub fn g(cutoff: f32, rate: f32) -> f32 {
        (PI * cutoff / rate).tan()
    }

    /// Ajusta o corte (`g`) e o amortecimento `k = 1/Q` (2 = sem ressonância, perto de 0 toca
    /// sozinho). Não mexe no estado: pode ser chamado a cada bloco.
    #[inline]
    pub fn set(&mut self, g: f32, k: f32) {
        self.k = k;
        self.a1 = 1.0 / (1.0 + g * (g + k));
        self.a2 = g * self.a1;
        self.a3 = g * self.a2;
    }

    /// Processa um quadro e devolve (saída no modo pedido, passa-banda). O passa-banda sai sempre
    /// para quem quiser medir a ressonância.
    #[inline]
    pub fn tick(&mut self, v0: f32, mode: FilterMode) -> (f32, f32) {
        let v3 = v0 - self.ic2;
        let v1 = self.a1 * self.ic1 + self.a2 * v3;
        let v2 = self.ic2 + self.a2 * self.ic1 + self.a3 * v3;
        self.ic1 = 2.0 * v1 - self.ic1;
        self.ic2 = 2.0 * v2 - self.ic2;
        let out = match mode {
            FilterMode::LowPass => v2,
            FilterMode::HighPass => v0 - self.k * v1 - v2,
            FilterMode::BandPass => v1,
        };
        (out, v1)
    }

    pub fn reset(&mut self) {
        self.ic1 = 0.0;
        self.ic2 = 0.0;
    }

    /// Zera estados minúsculos (chame uma vez por bloco): com entrada em silêncio eles decaem até
    /// virar denormais.
    #[inline]
    pub fn flush(&mut self) {
        if self.ic1.abs() < 1e-15 {
            self.ic1 = 0.0;
        }
        if self.ic2.abs() < 1e-15 {
            self.ic2 = 0.0;
        }
    }

    /// Estado finito? (para testes e para se recuperar se algo der errado).
    pub fn is_finite(&self) -> bool {
        self.ic1.is_finite() && self.ic2.is_finite()
    }
}

/// O anel de um [`Delay`] cresce em múltiplos disto (quadros).
const GROW_STEP: usize = 1024;

/// Linha de atraso estéreo de tomada móvel, a peça da compensação de latência (PDC). O atraso
/// pedido (`target`) é alcançado por um crossfade curto entre a tomada antiga e a nova: mudar a
/// latência com som passando não estala nem pula. Com atraso zero (e nenhuma mudança em curso) a
/// linha está parada e quem a usa pula todas as chamadas: o caminho sem latência não muda em nada.
///
/// A memória cresce só em [`Delay::set_target`], que roda no comando (ou entre um bloco e outro),
/// nunca no meio do processamento.
#[derive(Clone, Debug, Default)]
pub struct Delay {
    l: Vec<f32>,
    r: Vec<f32>,
    /// Próxima posição de escrita.
    pos: usize,
    /// Tomada em uso e tomada pedida, em quadros.
    cur: usize,
    target: usize,
    /// Quadros já andados do crossfade `cur` → `target` e a duração dele.
    fade: usize,
    fade_len: usize,
}

impl Delay {
    pub fn new() -> Self {
        Self::default()
    }

    /// Pede o atraso `frames`, com o crossfade de `fade_len` quadros (pelo menos 1). Aumentar a
    /// capacidade preserva o histórico. Um crossfade ainda no meio termina na hora (raro: duas
    /// mudanças de latência em menos de 10 ms).
    pub fn set_target(&mut self, frames: usize, fade_len: usize) {
        if frames == self.target {
            return;
        }
        if !self.active() {
            // parada: o anel guarda o que sobrou de antes, que não é passado deste sinal
            self.l.fill(0.0);
            self.r.fill(0.0);
            self.pos = 0;
        }
        if self.l.len() < frames + 1 {
            // com folga: uma latência automatizada que sobe aos poucos não realoca a cada degrau
            self.grow((frames + 1).next_multiple_of(GROW_STEP));
        }
        self.cur = self.target;
        self.target = frames;
        self.fade = 0;
        self.fade_len = fade_len.max(1);
    }

    /// Cresce o anel para `len` quadros sem perder o histórico: o mais antigo (na posição de
    /// escrita) vai para o começo da parte final do anel novo, e a escrita recomeça em 0.
    fn grow(&mut self, len: usize) {
        let old = self.l.len();
        let (mut l, mut r) = (vec![0.0; len], vec![0.0; len]);
        for k in 0..old {
            let src = (self.pos + k) % old;
            l[len - old + k] = self.l[src];
            r[len - old + k] = self.r[src];
        }
        self.l = l;
        self.r = r;
        self.pos = 0;
    }

    /// O atraso pedido, em quadros.
    pub fn target(&self) -> usize {
        self.target
    }

    /// Há atraso (ou mudança) em curso: a linha precisa ver todo bloco.
    pub fn active(&self) -> bool {
        self.cur > 0 || self.target > 0
    }

    /// A tomada já chegou ao atraso pedido.
    pub fn settled(&self) -> bool {
        self.cur == self.target
    }

    /// Termina o crossfade na hora e esvazia o histórico (começo de um render).
    pub fn snap(&mut self) {
        self.cur = self.target;
        self.fade = 0;
        self.l.fill(0.0);
        self.r.fill(0.0);
        self.pos = 0;
    }

    /// Esquece o histórico (o efeito voltou de um bypass), mantendo o atraso.
    pub fn clear(&mut self) {
        self.l.fill(0.0);
        self.r.fill(0.0);
    }

    fn tap(&self, d: usize) -> usize {
        let len = self.l.len();
        // `pos` já avançou uma casa: o quadro de agora está em pos − 1
        (self.pos + len - 1 - d) % len
    }

    /// Copia o histórico gravado: `l[i]` é o quadro de `back − i` quadros atrás (o mais antigo
    /// primeiro; `back` = 0 é o último gravado). O que a linha nunca gravou vem zerado.
    pub fn history(&self, back: usize, l: &mut [f32], r: &mut [f32]) {
        let len = self.l.len();
        for (i, (a, b)) in l.iter_mut().zip(r.iter_mut()).enumerate() {
            match back.checked_sub(i) {
                Some(d) if d < len => {
                    let at = self.tap(d);
                    (*a, *b) = (self.l[at], self.r[at]);
                }
                _ => (*a, *b) = (0.0, 0.0),
            }
        }
    }

    /// Só grava o bloco (o atraso não é lido agora).
    pub fn record(&mut self, l: &[f32], r: &[f32]) {
        let len = self.l.len();
        if len == 0 {
            return;
        }
        for (a, b) in l.iter().zip(r) {
            self.l[self.pos] = *a;
            self.r[self.pos] = *b;
            self.pos = if self.pos + 1 == len { 0 } else { self.pos + 1 };
        }
    }

    /// Grava o bloco e o devolve atrasado, no lugar.
    pub fn process(&mut self, l: &mut [f32], r: &mut [f32]) {
        let len = self.l.len();
        if len == 0 {
            return;
        }
        for (a, b) in l.iter_mut().zip(r.iter_mut()) {
            self.l[self.pos] = *a;
            self.r[self.pos] = *b;
            self.pos = if self.pos + 1 == len { 0 } else { self.pos + 1 };
            let i = self.tap(self.cur);
            let (mut ol, mut or) = (self.l[i], self.r[i]);
            if self.cur != self.target {
                let j = self.tap(self.target);
                let t = self.fade as f32 / self.fade_len as f32;
                ol += (self.l[j] - ol) * t;
                or += (self.r[j] - or) * t;
                self.fade += 1;
                if self.fade >= self.fade_len {
                    self.cur = self.target;
                    self.fade = 0;
                }
            }
            *a = ol;
            *b = or;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn delay_atrasa_o_pedido_e_troca_sem_pular() {
        let mut d = Delay::new();
        d.set_target(5, 1);
        let src: Vec<f32> = (1..=20).map(|i| i as f32).collect();
        let (mut l, mut r) = (src.clone(), src.clone());
        d.process(&mut l, &mut r);
        // o crossfade de 1 quadro consome o primeiro; dali em diante são 5 quadros de atraso
        assert_eq!(l[0], 1.0);
        assert!(l[1..5].iter().all(|&v| v == 0.0), "{l:?}");
        assert_eq!(&l[5..], &src[..15]);
        // crescer no meio preserva o histórico
        d.set_target(9, 1);
        let (mut l, mut r) = (vec![0.0; 10], vec![0.0; 10]);
        d.process(&mut l, &mut r);
        assert_eq!(l[0], 16.0, "{l:?}");
        // (o anel cresce com folga e guardou o histórico todo: a tomada nova acha os quadros de trás)
        assert_eq!((l[1], l[2], l[3], l[8], l[9]), (13.0, 14.0, 15.0, 20.0, 0.0), "{l:?}");
        // voltar a zero devolve a entrada
        d.set_target(0, 4);
        let (mut l, mut r) = (vec![7.0; 8], vec![7.0; 8]);
        d.process(&mut l, &mut r);
        assert_eq!(l[7], 7.0);
        assert!(!d.active());
    }

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

    #[test]
    fn sustentacao_muda_sem_degrau() {
        let mut e = Adsr::new(48_000.0);
        e.set(0.001, 0.001, 0.8, 0.1);
        e.gate_on();
        for _ in 0..4800 {
            e.next();
        }
        assert_eq!(e.stage(), Stage::Sustain);
        e.sustain = 0.2;
        let mut last = e.value();
        for _ in 0..4800 {
            let v = e.next();
            assert!((v - last).abs() < 0.01, "degrau de {}", v - last);
            last = v;
        }
        assert!((e.value() - 0.2).abs() < 1e-4);
    }

    #[test]
    fn seno_polinomial_confere() {
        for i in 0..=1000 {
            let p = i as f32 / 1000.0;
            let err = (sin_turns(p) - (p * TAU).sin()).abs();
            assert!(err < 1e-5, "fase {p}: erro {err}");
        }
        assert!((sin_turns(1.25) - 1.0).abs() < 1e-5);
        assert!((sin_turns(-0.25) + 1.0).abs() < 1e-5);
    }

    #[test]
    fn tanh_aproximada_e_suave() {
        assert_eq!(fast_tanh(0.0), 0.0);
        assert!((fast_tanh(0.5) - 0.5f32.tanh()).abs() < 0.01);
        assert!((fast_tanh(10.0) - 1.0).abs() < 1e-6);
        assert!((fast_tanh(-10.0) + 1.0).abs() < 1e-6);
        // monótona (a derivada é 9(x² − 9)²/(27 + 9x²)², zero só em ±3; lá o arredondamento
        // pode devolver um ulp a menos)
        let mut last = fast_tanh(-4.0);
        for i in -399..=400 {
            let v = fast_tanh(i as f32 / 100.0);
            assert!(v >= last - 1e-6, "{} < {last}", v);
            last = v;
        }
    }

    #[test]
    fn residuos_somem_longe_da_quina() {
        let dt = 0.01;
        assert_eq!(poly_blep(0.5, dt), 0.0);
        assert_eq!(poly_blamp(0.5, dt), 0.0);
        // o polyBLEP é contínuo na quina: −1 logo depois, +1 logo antes (degrau de 2)
        assert!((poly_blep(0.0, dt) + 1.0).abs() < 1e-6);
        assert!((poly_blep(1.0 - 1e-7, dt) - 1.0).abs() < 1e-3);
        // e o polyBLAMP é simétrico, com pico de 1/6 na quina
        assert!((poly_blamp(0.0, dt) - 1.0 / 6.0).abs() < 1e-6);
        assert!((poly_blamp(0.004, dt) - poly_blamp(0.996, dt)).abs() < 1e-4);
    }

    #[test]
    fn svf_passa_baixa_corta_o_agudo() {
        let rate = 48_000.0;
        let tone = |freq: f32| {
            let mut f = Svf::default();
            f.set(Svf::g(1000.0, rate), std::f32::consts::SQRT_2);
            let mut peak: f32 = 0.0;
            for i in 0..48_000 {
                let (y, _) = f.tick((i as f32 * freq / rate * TAU).sin(), FilterMode::LowPass);
                if i > 24_000 {
                    peak = peak.max(y.abs());
                }
            }
            peak
        };
        assert!((tone(100.0) - 1.0).abs() < 0.02);
        assert!((tone(1000.0) - std::f32::consts::FRAC_1_SQRT_2).abs() < 0.02);
        assert!(tone(8000.0) < 0.02);
    }

    #[test]
    fn smoothed_encosta_no_alvo() {
        let mut s = Smoothed::new(0.0);
        s.set(1.0);
        let a = smoothing(0.01, 16, 48_000.0);
        for _ in 0..1000 {
            s.step(a);
        }
        assert!(s.settled());
        assert_eq!(s.value, 1.0);
    }
}
