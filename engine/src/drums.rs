//! Bateria sintetizada (tipo 2): doze peças geradas na hora, sem samples, no espírito da 808/909 e
//! dos kits eletrônicos atuais.
//!
//! Cada peça tem o próprio algoritmo: senoide com envelope de altura no bumbo e nos toms, duas
//! senoides mais ruído filtrado na caixa, rajadas de ruído nas palmas, o banco de seis osciladores
//! quadrados em razões metálicas da 808 nos chimbais e pratos, dois quadrados no cowbell. Os
//! parâmetros seguem `drum_param`: afinação, decaimento e timbre valem a partir do próximo golpe,
//! como numa bateria eletrônica; os volumes (da peça e o geral) mudam na hora, com rampa.
//!
//! Cada peça tem três vozes pré-alocadas. O redisparo esvanece a voz anterior em 1,5 ms em vez de
//! cortá-la (sem estalo); nos pratos a cauda anterior continua soando por baixo, como num prato de
//! verdade. O chimbal fechado e o aberto se cortam: é o mesmo par de pratos.
//!
//! Tempo real: nada aqui aloca depois do `new`. Os filtros processam as fontes cruas (ruído,
//! osciladores) e os envelopes multiplicam depois, então nenhum estado de filtro fica decaindo
//! sozinho até os denormais; os envelopes viram zero abaixo de `FLOOR`.

use std::f32::consts::{FRAC_PI_4, PI, SQRT_2, TAU};

use crate::instrument::{Instrument, drum_param};

const PIECES: usize = drum_param::PIECES;
/// Vozes por peça: a que soa, a que está esvanecendo e uma cauda de prato.
const SLOTS: usize = 3;
/// Pedaço em que os volumes são rampados (taxa de controle), em quadros.
const CHUNK: usize = 64;
/// Nível, relativo ao pico do golpe, abaixo do qual a voz acabou (≈ −90 dB).
const END: f32 = 3.2e-5;
/// Envelopes abaixo disto viram zero, para as caudas não descerem até os denormais.
const FLOOR: f32 = 1e-7;
/// Esvanecimento da voz anterior quando a mesma peça é redisparada, em segundos.
const RETRIGGER_FADE: f32 = 0.0015;
/// Esvanecimento do chimbal cortado pelo outro, em segundos.
const CHOKE_FADE: f32 = 0.006;
/// Constante de tempo da rampa dos volumes, em segundos.
const LEVEL_SMOOTH: f32 = 0.01;

const LEVEL: usize = drum_param::LEVEL as usize;
const TUNE: usize = drum_param::TUNE as usize;
const DECAY: usize = drum_param::DECAY as usize;
const TONE: usize = drum_param::TONE as usize;

const KICK: usize = 0;
const SNARE: usize = 1;
const CLAP: usize = 2;
const CLOSED_HAT: usize = 3;
const OPEN_HAT: usize = 4;
const LOW_TOM: usize = 5;
const MID_TOM: usize = 6;
const HIGH_TOM: usize = 7;
const CRASH: usize = 8;
const RIDE: usize = 9;
const RIM: usize = 10;
const COWBELL: usize = 11;

/// Posição no estéreo (−1..1), vista da plateia: chimbal e prato de ataque à direita, condução à
/// esquerda, toms do agudo (direita) ao grave (esquerda). Discreta de propósito.
const PAN: [f32; PIECES] = [0.0, 0.0, 0.0, 0.22, 0.22, -0.3, 0.05, 0.25, 0.25, -0.3, 0.0, -0.12];

/// Ganho interno de cada peça, para o kit sair equilibrado com todos os volumes em 1. Medido pela
/// sonoridade (ponderação K, janela de 100 ms), não pelo pico, com volume geral 1 e velocidade
/// máxima: bumbo em −8,7 LUFS, toms −10,6, caixa −11,6, palmas −13,1, aro −15,6, prato de ataque
/// −16,1, cowbell −17,1, chimbal aberto −19,1, condução −19,6 e chimbal fechado −22,1. Sobra
/// margem para uma levada com bumbo, prato e chimbal juntos não passar de 0 dBFS no padrão.
const GAIN: [f32; PIECES] = [0.64, 0.95, 1.09, 1.75, 1.18, 0.42, 0.43, 0.45, 0.59, 0.8, 0.6, 0.48];

/// Padrões da tabela do app (`drumParams` em `instruments.dart`).
const DEFAULT_PIECE: [f32; 4] = [1.0, 0.0, 1.0, 0.5];
const DEFAULT_MASTER: f32 = 0.8;

/// Faixa de cada parâmetro de peça, na ordem de `drum_param` (volume, afinação, decaimento, timbre).
const RANGE: [(f32, f32); 4] = [(0.0, 1.5), (-12.0, 12.0), (0.25, 4.0), (0.0, 1.0)];

// ------------------------------------------------------------------------------------------------
// blocos de DSP (daqui: o `dsp.rs` é compartilhado e esta bateria é auto contida)

/// sen(2π·p) para `p` em 0..1, por polinômio: erro abaixo de 4e-6 e bem mais barato que `sin`.
#[inline]
fn sine(p: f32) -> f32 {
    // leva a fase para −¼..¼ de volta pela simetria do seno e usa Taylor até x⁹
    let mut x = if p > 0.5 { p - 1.0 } else { p };
    if x > 0.25 {
        x = 0.5 - x;
    } else if x < -0.25 {
        x = -0.5 - x;
    }
    let y = x * TAU;
    let y2 = y * y;
    y * (1.0 - y2 * (1.0 / 6.0) * (1.0 - y2 * (1.0 / 20.0) * (1.0 - y2 * (1.0 / 42.0) * (1.0 - y2 * (1.0 / 72.0)))))
}

/// Correção PolyBLEP de um degrau na fase `t`, para um oscilador com incremento `dt` (`inv = 1/dt`).
#[inline]
fn blep(t: f32, dt: f32, inv: f32) -> f32 {
    if t < dt {
        let x = t * inv;
        x + x - x * x - 1.0
    } else if t > 1.0 - dt {
        let x = (t - 1.0) * inv;
        x * x + x + x + 1.0
    } else {
        0.0
    }
}

/// Onda quadrada com PolyBLEP (tira o grosso do aliasing dos degraus) na fase `p` (0..1).
#[inline]
fn square(p: f32, dt: f32, inv: f32) -> f32 {
    let (naive, half) = if p < 0.5 { (1.0, p + 0.5) } else { (-1.0, p - 0.5) };
    naive + blep(p, dt, inv) - blep(half, dt, inv)
}

/// Saturação suave: aproximação racional da tangente hiperbólica, que encosta em ±1 com derivada
/// zero em ±3 (sem quina, então sem harmônicos altos a mais).
#[inline]
fn soft_clip(x: f32) -> f32 {
    let x = x.clamp(-3.0, 3.0);
    x * (27.0 + x * x) / (27.0 + 9.0 * x * x)
}

/// Ruído branco xorshift32, em −1..1. Cada voz tem o seu: com um gerador só, a ordem em que as
/// vozes o consomem dependeria do fatiamento dos blocos e o mesmo trecho soaria diferente.
#[derive(Clone, Copy)]
struct Rng(u32);

impl Rng {
    /// Semente do golpe número `n`. O embaralhamento (hash "lowbias32") põe golpes seguidos em
    /// pontos distantes do ciclo do xorshift; sementes vizinhas dariam o mesmo ruído deslocado de
    /// uma amostra, e duas peças juntas virariam um filtro pente.
    fn seeded(n: u32) -> Self {
        let mut x = n.wrapping_add(0x9E37_79B9);
        x ^= x >> 16;
        x = x.wrapping_mul(0x7FEB_352D);
        x ^= x >> 15;
        x = x.wrapping_mul(0x846C_A68B);
        x ^= x >> 16;
        Self(x.max(1))
    }

    #[inline]
    fn next(&mut self) -> f32 {
        let mut x = self.0;
        x ^= x << 13;
        x ^= x >> 17;
        x ^= x << 5;
        self.0 = x;
        x as i32 as f32 * (1.0 / 2_147_483_648.0)
    }

    /// Em 0..1.
    fn unit(&mut self) -> f32 {
        (self.next() * 0.5 + 0.5).min(0.999_999)
    }
}

/// Decaimento exponencial: começa em `v` e cai 60 dB no tempo pedido.
#[derive(Clone, Copy, Default)]
struct Decay {
    v: f32,
    c: f32,
}

impl Decay {
    fn new(level: f32, t60: f32, rate: f32) -> Self {
        Self { v: level, c: t60_coef(t60, rate) }
    }

    /// O valor atual; avança um quadro.
    #[inline]
    fn next(&mut self) -> f32 {
        let v = self.v;
        let n = v * self.c;
        self.v = if n < FLOOR { 0.0 } else { n };
        v
    }
}

/// Coeficiente de um polo que cai 60 dB em `t60` segundos.
fn t60_coef(t60: f32, rate: f32) -> f32 {
    (-6.907_755 / (t60.max(1e-4) * rate)).exp()
}

/// Filtro de variáveis de estado trapezoidal (Andrew Simper, Cytomic): estável em qualquer corte,
/// sem distorcer a resposta perto de Nyquist, e dá passa-baixa, banda e alta de uma vez.
#[derive(Clone, Copy, Default)]
struct Svf {
    a1: f32,
    a2: f32,
    a3: f32,
    k: f32,
    ic1: f32,
    ic2: f32,
}

impl Svf {
    fn new(hz: f32, q: f32, rate: f32) -> Self {
        let g = (PI * hz.clamp(10.0, rate * 0.45) / rate).tan();
        let k = 1.0 / q.max(0.05);
        let a1 = 1.0 / (1.0 + g * (g + k));
        Self { a1, a2: g * a1, a3: g * g * a1, k, ic1: 0.0, ic2: 0.0 }
    }

    /// (banda, baixa)
    #[inline]
    fn tick(&mut self, x: f32) -> (f32, f32) {
        let v3 = x - self.ic2;
        let v1 = self.a1 * self.ic1 + self.a2 * v3;
        let v2 = self.ic2 + self.a2 * self.ic1 + self.a3 * v3;
        self.ic1 = 2.0 * v1 - self.ic1;
        self.ic2 = 2.0 * v2 - self.ic2;
        (v1, v2)
    }

    #[inline]
    fn lp(&mut self, x: f32) -> f32 {
        self.tick(x).1
    }

    /// Passa-banda com ganho 1 no centro, qualquer que seja o Q.
    #[inline]
    fn bp(&mut self, x: f32) -> f32 {
        self.k * self.tick(x).0
    }

    #[inline]
    fn hp(&mut self, x: f32) -> f32 {
        let (b, l) = self.tick(x);
        x - self.k * b - l
    }
}

/// Bloqueador de DC (passa-alta de um polo bem abaixo do audível): a senoide que começa na fase
/// zero e decai tem média positiva, que só gastaria margem no mix.
#[derive(Clone, Copy, Default)]
struct DcBlock {
    r: f32,
    x1: f32,
    y1: f32,
}

impl DcBlock {
    fn new(hz: f32, rate: f32) -> Self {
        Self { r: 1.0 - TAU * hz / rate, x1: 0.0, y1: 0.0 }
    }

    #[inline]
    fn tick(&mut self, x: f32) -> f32 {
        let y = x - self.x1 + self.r * self.y1;
        self.x1 = x;
        self.y1 = y;
        y
    }
}

/// Oscilador de fase (0..1) com incremento fixo, em ciclos por quadro.
#[derive(Clone, Copy, Default)]
struct Phase {
    p: f32,
    inc: f32,
    inv: f32,
}

impl Phase {
    fn new(inc: f32, start: f32) -> Self {
        Self { p: start, inc, inv: 1.0 / inc.max(1e-6) }
    }

    /// Avança com a frequência multiplicada por `k` (envelope de altura) e devolve a senoide.
    #[inline]
    fn sine(&mut self, k: f32) -> f32 {
        self.p += self.inc * k;
        if self.p >= 1.0 {
            self.p -= 1.0;
        }
        sine(self.p)
    }

    #[inline]
    fn square(&mut self) -> f32 {
        let s = square(self.p, self.inc, self.inv);
        self.p += self.inc;
        if self.p >= 1.0 {
            self.p -= 1.0;
        }
        s
    }
}

/// As frequências dos seis osciladores de prato da 808: quadrados sem relação harmônica entre si,
/// cujos harmônicos altos se embolam no chiado metálico.
const METAL_HZ: [f32; 6] = [205.3, 304.4, 369.6, 522.7, 540.0, 800.0];

#[derive(Clone, Copy, Default)]
struct Metal {
    osc: [Phase; 6],
}

impl Metal {
    /// Fases iniciais sorteadas: na 808 os osciladores correm soltos, então cada golpe pega as
    /// ondas num ponto diferente (é o que tira o som de metralhadora).
    fn new(scale: f32, h: &Hit, rng: &mut Rng) -> Self {
        let mut osc = [Phase::default(); 6];
        for (o, hz) in osc.iter_mut().zip(METAL_HZ) {
            *o = Phase::new(h.hz(hz * scale), rng.unit());
        }
        Self { osc }
    }

    #[inline]
    fn tick(&mut self) -> f32 {
        let mut s = 0.0;
        for o in &mut self.osc {
            s += o.square();
        }
        s * (1.0 / 6.0)
    }
}

// ------------------------------------------------------------------------------------------------
// as peças

/// Os parâmetros de um golpe, já na forma que as peças usam.
struct Hit {
    rate: f32,
    vel: f32,
    /// Razão de frequência da afinação (2^(semitons/12)).
    tune: f32,
    /// Multiplicador do decaimento.
    decay: f32,
    tone: f32,
}

impl Hit {
    /// Frequência afinada, em ciclos por quadro (abaixo de Nyquist com folga).
    fn hz(&self, hz: f32) -> f32 {
        (hz * self.tune / self.rate).min(0.45)
    }

    /// Fator de brilho do timbre: `oct` oitavas de uma ponta à outra, 1 no meio.
    fn bright(&self, oct: f32) -> f32 {
        2f32.powf((self.tone - 0.5) * oct)
    }
}

/// Uma peça tocando.
trait Sound {
    /// Um quadro: (meio, lado). O lado soma à esquerda e subtrai da direita (abertura estéreo).
    fn tick(&mut self, rng: &mut Rng) -> (f32, f32);
    /// Já caiu abaixo de [`END`]?
    fn done(&self) -> bool;
}

/// Bumbo: senoide com duas quedas de altura (a lenta, que dá o corpo, e a rapidíssima, que dá o
/// "toc" do ataque), segurada cheia por alguns milissegundos antes de decair, mais um clique de
/// ruído e saturação. Timbre = clique e drive.
#[derive(Clone, Copy)]
struct Kick {
    osc: Phase,
    sweep: f32,
    snap: f32,
    pitch: Decay,
    pitch_fast: Decay,
    hold: u32,
    amp: Decay,
    click: Decay,
    click_bp: Svf,
    drive: f32,
    drive_norm: f32,
    dc: DcBlock,
}

impl Kick {
    fn new(h: &Hit) -> Self {
        let r = h.rate;
        let drive = 0.25 + 3.25 * h.tone * h.tone;
        Self {
            osc: Phase::new(h.hz(50.0), 0.0),
            // golpe mais forte estica mais a pele: começa mais agudo
            sweep: 3.2 * (0.8 + 0.2 * h.vel),
            snap: 7.0 * h.tone,
            pitch: Decay::new(1.0, 0.11 * h.decay.powf(0.3), r),
            pitch_fast: Decay::new(1.0, 0.012, r),
            hold: (0.012 * r) as u32,
            amp: Decay::new(1.0, 0.5 * h.decay, r),
            click: Decay::new(0.35 * h.tone * (0.5 + 0.5 * h.vel), 0.008, r),
            click_bp: Svf::new(3200.0 * (0.8 + 0.4 * h.vel), 0.7, r),
            drive,
            // a saturação não muda o pico, só o corpo
            drive_norm: 1.0 / soft_clip(drive),
            dc: DcBlock::new(12.0, r),
        }
    }
}

impl Sound for Kick {
    #[inline]
    fn tick(&mut self, rng: &mut Rng) -> (f32, f32) {
        let k = 1.0 + self.sweep * self.pitch.next() + self.snap * self.pitch_fast.next();
        let a = if self.hold > 0 {
            self.hold -= 1;
            self.amp.v
        } else {
            self.amp.next()
        };
        let body = soft_clip(self.osc.sine(k) * a * self.drive) * self.drive_norm;
        let click = self.click_bp.bp(rng.next()) * self.click.next();
        (self.dc.tick(body) + click, 0.0)
    }

    fn done(&self) -> bool {
        self.hold == 0 && self.amp.v < END && self.click.v < END
    }
}

/// Caixa: duas senoides afinadas (~185/330 Hz, com um tranco de altura no ataque) mais o ruído da
/// esteira (passa-alta e passa-baixa), cada um com seu envelope, e uma saturação suave no fim.
/// Timbre = corpo × esteira.
#[derive(Clone, Copy)]
struct Snare {
    osc: [Phase; 2],
    pitch: Decay,
    body: [Decay; 2],
    body_gain: f32,
    hp: Svf,
    lp: Svf,
    crack: Decay,
    rattle: Decay,
    noise_gain: f32,
}

impl Snare {
    fn new(h: &Hit) -> Self {
        let r = h.rate;
        let t = h.tone;
        Self {
            osc: [Phase::new(h.hz(185.0), 0.0), Phase::new(h.hz(330.0), 0.0)],
            pitch: Decay::new(1.0, 0.05, r),
            body: [Decay::new(1.0, 0.18 * h.decay, r), Decay::new(0.55, 0.11 * h.decay, r)],
            body_gain: 1.0 - 0.65 * t,
            hp: Svf::new(1600.0 * h.tune.sqrt(), 0.6, r),
            lp: Svf::new(9000.0 * (0.7 + 0.3 * h.vel), 0.55, r),
            crack: Decay::new(0.6, 0.05, r),
            rattle: Decay::new(0.55, 0.3 * h.decay, r),
            noise_gain: (0.3 + 0.7 * t) * 1.6,
        }
    }
}

impl Sound for Snare {
    #[inline]
    fn tick(&mut self, rng: &mut Rng) -> (f32, f32) {
        let k = 1.0 + 0.35 * self.pitch.next();
        let body = self.osc[0].sine(k) * self.body[0].next() + self.osc[1].sine(k) * self.body[1].next();
        let n = self.lp.lp(self.hp.hp(rng.next()));
        let noise = n * (self.crack.next() + self.rattle.next());
        // a saturação só pega nos picos do ruído: mais densidade, menos fator de crista
        (soft_clip(body * self.body_gain + noise * self.noise_gain), 0.0)
    }

    fn done(&self) -> bool {
        self.body[0].v + self.body[1].v + self.crack.v + self.rattle.v < END
    }
}

/// Quando começa cada rajada das palmas, em segundos; a última abre a cauda. O espaçamento
/// levemente irregular soa como mãos de verdade.
const CLAP_BURSTS: [f32; 4] = [0.0, 0.0105, 0.0205, 0.031];
const CLAP_LEVELS: [f32; 4] = [0.9, 1.0, 0.95, 0.9];

/// Palmas: quatro rajadas curtas de ruído por um passa-banda e uma cauda, levemente aberta no
/// estéreo (ruído independente no lado). Timbre = centro do passa-banda.
#[derive(Clone, Copy)]
struct Clap {
    age: u32,
    at: [u32; 4],
    next: usize,
    burst: Decay,
    /// O envelope das rajadas suavizado (~0,2 ms): tira o degrau seco do começo de cada uma.
    burst_smooth: f32,
    smooth: f32,
    tail: Decay,
    bp: Svf,
    tail_mid: Svf,
    tail_side: Svf,
}

impl Clap {
    fn new(h: &Hit) -> Self {
        let r = h.rate;
        let fc = 1150.0 * h.tune * h.bright(1.2) * (0.9 + 0.2 * h.vel);
        Self {
            age: 0,
            at: CLAP_BURSTS.map(|s| (s * r) as u32),
            next: 0,
            burst: Decay::new(0.0, 0.024, r),
            burst_smooth: 0.0,
            smooth: 1.0 - (-1.0 / (0.0002 * r)).exp(),
            tail: Decay::new(0.0, 0.32 * h.decay, r),
            bp: Svf::new(fc, 1.5, r),
            tail_mid: Svf::new(fc * 0.85, 0.9, r),
            tail_side: Svf::new(fc * 0.85, 0.9, r),
        }
    }
}

impl Sound for Clap {
    #[inline]
    fn tick(&mut self, rng: &mut Rng) -> (f32, f32) {
        if self.next < CLAP_BURSTS.len() && self.age >= self.at[self.next] {
            self.burst.v = CLAP_LEVELS[self.next];
            if self.next == CLAP_BURSTS.len() - 1 {
                // a cauda sai do mesmo ruído que a rajada (soma coerente): começa mais baixa
                self.tail.v = 0.4;
            }
            self.next += 1;
        }
        self.age = self.age.saturating_add(1);
        self.burst_smooth += (self.burst.next() - self.burst_smooth) * self.smooth;
        if self.burst_smooth < FLOOR {
            self.burst_smooth = 0.0;
        }
        let n = rng.next();
        let t = self.tail.next();
        let mid = self.bp.bp(n) * self.burst_smooth + self.tail_mid.bp(n) * t;
        let side = self.tail_side.bp(rng.next()) * t * 0.3;
        (soft_clip(mid * 2.4), side * 2.4)
    }

    fn done(&self) -> bool {
        self.next == CLAP_BURSTS.len() && self.burst_smooth < END && self.burst.v < END && self.tail.v < END
    }
}

/// Chimbal: os seis quadrados metálicos por um passa-banda, mais um pouco de ruído, e um
/// passa-alta e um passa-baixa suave no fim. O fechado tem um envelope só, curto; o aberto cai
/// rápido nos primeiros milissegundos e depois sustenta o chiado. Timbre = brilho (centro dos
/// filtros e ruído).
#[derive(Clone, Copy)]
struct Hat {
    metal: Metal,
    bp: Svf,
    hp: Svf,
    lp: Svf,
    noise: f32,
    fast: Decay,
    slow: Decay,
}

impl Hat {
    fn new(open: bool, h: &Hit, rng: &mut Rng) -> Self {
        let r = h.rate;
        // os filtros acompanham metade da afinação: o timbre muda sem virar outro instrumento
        let tr = h.tune.sqrt();
        let bright = h.bright(1.2) * (0.85 + 0.15 * h.vel);
        let (fast, slow) =
            if open { (Decay::new(0.5, 0.09, r), Decay::new(0.55, 0.6 * h.decay, r)) } else { (Decay::new(1.0, 0.07 * h.decay, r), Decay::default()) };
        Self {
            metal: Metal::new(1.0, h, rng),
            bp: Svf::new(8200.0 * tr * bright, 1.0, r),
            hp: Svf::new(6400.0 * tr * bright.sqrt(), 0.7, r),
            lp: Svf::new((10000.0 + 9000.0 * h.tone) * tr * (0.85 + 0.15 * h.vel), 0.5, r),
            // pouco ruído: quem manda é o metal (o ruído é só o chiado por cima)
            noise: 0.04 + 0.16 * h.tone,
            fast,
            slow,
        }
    }
}

impl Sound for Hat {
    #[inline]
    fn tick(&mut self, rng: &mut Rng) -> (f32, f32) {
        let x = self.bp.bp(self.metal.tick()) * 3.0 + rng.next() * self.noise;
        (self.lp.lp(self.hp.hp(x)) * (self.fast.next() + self.slow.next()), 0.0)
    }

    fn done(&self) -> bool {
        self.fast.v + self.slow.v < END
    }
}

/// Afinação e decaimento de cada tom (grave, médio, agudo): quartas entre si (sol, dó, fá).
const TOM_HZ: [f32; 3] = [98.0, 131.0, 175.0];
const TOM_T60: [f32; 3] = [0.75, 0.6, 0.5];
/// Razão do segundo modo de uma membrana circular em relação ao fundamental.
const MEMBRANE: f32 = 1.593;

/// Tom: senoide com queda de altura, o segundo modo da membrana (inarmônico, mais curto), o ruído
/// da baqueta no ataque e uma saturação leve. Timbre = profundidade da queda e ataque.
#[derive(Clone, Copy)]
struct Tom {
    osc: [Phase; 2],
    sweep: f32,
    pitch: Decay,
    amp: Decay,
    over: Decay,
    click: Decay,
    click_bp: Svf,
    dc: DcBlock,
}

const TOM_DRIVE: f32 = 1.3;

impl Tom {
    fn new(i: usize, h: &Hit) -> Self {
        let r = h.rate;
        let t60 = TOM_T60[i] * h.decay;
        Self {
            osc: [Phase::new(h.hz(TOM_HZ[i]), 0.0), Phase::new(h.hz(TOM_HZ[i] * MEMBRANE), 0.0)],
            sweep: (0.2 + 0.6 * h.tone) * (0.8 + 0.2 * h.vel),
            pitch: Decay::new(1.0, 0.35 * h.decay.sqrt(), r),
            amp: Decay::new(1.0, t60, r),
            over: Decay::new(0.3, t60 * 0.3, r),
            click: Decay::new((0.08 + 0.3 * h.tone) * (0.5 + 0.5 * h.vel), 0.012, r),
            click_bp: Svf::new(2400.0 * h.tune.sqrt() * (1.0 + 0.15 * i as f32), 0.8, r),
            dc: DcBlock::new(12.0, r),
        }
    }
}

impl Sound for Tom {
    #[inline]
    fn tick(&mut self, rng: &mut Rng) -> (f32, f32) {
        let k = 1.0 + self.sweep * self.pitch.next();
        let body = self.osc[0].sine(k) * self.amp.next() + self.osc[1].sine(k) * self.over.next();
        let body = soft_clip(body * TOM_DRIVE) / soft_clip(TOM_DRIVE);
        let click = self.click_bp.bp(rng.next()) * self.click.next();
        (self.dc.tick(body) + click, 0.0)
    }

    fn done(&self) -> bool {
        self.amp.v + self.over.v + self.click.v < END
    }
}

/// Pratos: o banco metálico por um passa-banda (largo no de ataque, estreito e mais agudo no de
/// condução, que "pinga"), ruído passa-alta para o chiado, dois envelopes (o estouro e a cauda
/// longa) e um passa-baixa de brilho. Ruído independente no lado abre um pouco o estéreo.
/// Timbre = brilho.
#[derive(Clone, Copy)]
struct Cymbal {
    metal: Metal,
    bp: Svf,
    hp: Svf,
    side_hp: Svf,
    lp: Svf,
    side_lp: Svf,
    low_cut: Svf,
    metal_gain: f32,
    noise_gain: f32,
    width: f32,
    fast: Decay,
    slow: Decay,
}

impl Cymbal {
    fn new(ride: bool, h: &Hit, rng: &mut Rng) -> Self {
        let r = h.rate;
        let tr = h.tune.sqrt();
        let bright = h.bright(1.4).sqrt() * (0.85 + 0.15 * h.vel);
        let vel_lp = 0.8 + 0.2 * h.vel;
        if ride {
            Self {
                metal: Metal::new(1.45, h, rng),
                bp: Svf::new(5200.0 * tr, 2.4, r),
                hp: Svf::new(7500.0 * tr * bright, 0.7, r),
                side_hp: Svf::new(7500.0 * tr * bright, 0.7, r),
                lp: Svf::new((7000.0 + 11000.0 * h.tone) * vel_lp, 0.6, r),
                side_lp: Svf::new((7000.0 + 11000.0 * h.tone) * vel_lp, 0.6, r),
                low_cut: Svf::new(650.0 * tr, 0.7, r),
                metal_gain: 1.0,
                noise_gain: 0.3,
                width: 0.2,
                fast: Decay::new(0.75, 0.4 * h.decay.sqrt(), r),
                slow: Decay::new(0.3, 3.2 * h.decay, r),
            }
        } else {
            Self {
                metal: Metal::new(1.0, h, rng),
                bp: Svf::new(3600.0 * tr, 0.8, r),
                hp: Svf::new(4500.0 * tr * bright, 0.7, r),
                side_hp: Svf::new(4500.0 * tr * bright, 0.7, r),
                lp: Svf::new((5500.0 + 12000.0 * h.tone) * vel_lp, 0.6, r),
                side_lp: Svf::new((5500.0 + 12000.0 * h.tone) * vel_lp, 0.6, r),
                low_cut: Svf::new(450.0 * tr, 0.7, r),
                metal_gain: 0.8,
                noise_gain: 0.6,
                width: 0.28,
                fast: Decay::new(0.5, 0.35, r),
                slow: Decay::new(0.5, 2.5 * h.decay, r),
            }
        }
    }
}

impl Sound for Cymbal {
    #[inline]
    fn tick(&mut self, rng: &mut Rng) -> (f32, f32) {
        let m = self.bp.bp(self.metal.tick()) * self.metal_gain;
        let n = self.hp.hp(rng.next()) * self.noise_gain;
        let e = self.fast.next() + self.slow.next();
        let mid = self.low_cut.hp(self.lp.lp(m + n)) * e;
        let side = self.side_lp.lp(self.side_hp.hp(rng.next())) * self.noise_gain * self.width * e;
        (mid, side)
    }

    fn done(&self) -> bool {
        self.fast.v + self.slow.v < END
    }
}

/// Aro: duas senoides curtíssimas (~1,7 kHz e ~480 Hz, como os ressonadores da 808) mais um
/// estalo de ruído, saturadas e sem grave. Timbre = agudo × grave.
#[derive(Clone, Copy)]
struct Rim {
    osc: [Phase; 2],
    hi: Decay,
    lo: Decay,
    click: Decay,
    click_hp: Svf,
    hp: Svf,
}

const RIM_DRIVE: f32 = 2.2;

impl Rim {
    fn new(h: &Hit) -> Self {
        let r = h.rate;
        Self {
            osc: [Phase::new(h.hz(1720.0), 0.0), Phase::new(h.hz(480.0), 0.0)],
            hi: Decay::new(0.7 + 0.5 * h.tone, 0.03 * h.decay, r),
            lo: Decay::new(0.55 - 0.3 * h.tone, 0.045 * h.decay, r),
            click: Decay::new(0.4 * (0.5 + 0.5 * h.vel), 0.006, r),
            click_hp: Svf::new(3000.0, 0.7, r),
            hp: Svf::new(350.0 * h.tune.sqrt(), 0.7, r),
        }
    }
}

impl Sound for Rim {
    #[inline]
    fn tick(&mut self, rng: &mut Rng) -> (f32, f32) {
        let x = self.osc[0].sine(1.0) * self.hi.next() + self.osc[1].sine(1.0) * self.lo.next() + self.click_hp.hp(rng.next()) * self.click.next();
        let y = soft_clip(x * RIM_DRIVE) / soft_clip(RIM_DRIVE);
        (self.hp.hp(y), 0.0)
    }

    fn done(&self) -> bool {
        self.hi.v + self.lo.v + self.click.v < END
    }
}

/// Cowbell: dois quadrados (~540 e ~800 Hz, os da 808) por um passa-banda e um passa-baixa, com o
/// estalo inicial e a cauda. Timbre = centro do passa-banda.
#[derive(Clone, Copy)]
struct Cowbell {
    osc: [Phase; 2],
    bp: Svf,
    lp: Svf,
    fast: Decay,
    slow: Decay,
}

impl Cowbell {
    fn new(h: &Hit) -> Self {
        let r = h.rate;
        let bright = h.bright(1.2) * (0.9 + 0.2 * h.vel);
        Self {
            osc: [Phase::new(h.hz(540.0), 0.0), Phase::new(h.hz(800.0), 0.0)],
            bp: Svf::new(1100.0 * h.tune * bright, 1.4, r),
            lp: Svf::new(4500.0 * h.tune.sqrt() * bright, 0.6, r),
            fast: Decay::new(0.6, 0.06, r),
            slow: Decay::new(0.4, 0.5 * h.decay, r),
        }
    }
}

impl Sound for Cowbell {
    #[inline]
    fn tick(&mut self, _rng: &mut Rng) -> (f32, f32) {
        let s = self.osc[0].square() + 0.85 * self.osc[1].square();
        (self.lp.lp(self.bp.bp(s)) * (self.fast.next() + self.slow.next()), 0.0)
    }

    fn done(&self) -> bool {
        self.fast.v + self.slow.v < END
    }
}

// ------------------------------------------------------------------------------------------------
// vozes

/// O que uma voz está tocando. Tudo inline: as vozes são pré-alocadas e um golpe só troca a
/// variante, sem ir ao alocador.
#[derive(Clone, Copy)]
enum Body {
    Idle,
    Kick(Kick),
    Snare(Snare),
    Clap(Clap),
    Hat(Hat),
    Tom(Tom),
    Cymbal(Cymbal),
    Rim(Rim),
    Cowbell(Cowbell),
}

/// Ganho e esvanecimento de uma voz.
#[derive(Clone, Copy)]
struct Mix {
    /// Ganho do golpe (velocidade × ganho interno) já com o pan de cada lado.
    l: f32,
    r: f32,
    fade: f32,
    /// Quanto o `fade` desce por quadro; zero enquanto a voz não está saindo.
    fade_step: f32,
    /// Ordem do golpe, para achar a cauda mais antiga.
    seq: u32,
    rng: Rng,
}

#[derive(Clone, Copy)]
struct Voice {
    body: Body,
    mix: Mix,
}

impl Voice {
    const IDLE: Voice = Voice { body: Body::Idle, mix: Mix { l: 0.0, r: 0.0, fade: 1.0, fade_step: 0.0, seq: 0, rng: Rng(1) } };

    fn on(&self) -> bool {
        !matches!(self.body, Body::Idle)
    }

    fn fading(&self) -> bool {
        self.mix.fade_step > 0.0
    }

    /// Começa a sair, descendo `step` por quadro (se já saía mais rápido, continua como estava).
    fn fade_out(&mut self, step: f32) {
        if self.on() {
            self.mix.fade_step = self.mix.fade_step.max(step);
        }
    }

    /// Soma a voz no bloco com o volume rampando de `g0` a `g1`.
    fn render(&mut self, l: &mut [f32], r: &mut [f32], g0: f32, g1: f32) {
        let m = &mut self.mix;
        let on = match &mut self.body {
            Body::Idle => return,
            Body::Kick(s) => run(s, m, l, r, g0, g1),
            Body::Snare(s) => run(s, m, l, r, g0, g1),
            Body::Clap(s) => run(s, m, l, r, g0, g1),
            Body::Hat(s) => run(s, m, l, r, g0, g1),
            Body::Tom(s) => run(s, m, l, r, g0, g1),
            Body::Cymbal(s) => run(s, m, l, r, g0, g1),
            Body::Rim(s) => run(s, m, l, r, g0, g1),
            Body::Cowbell(s) => run(s, m, l, r, g0, g1),
        };
        if !on {
            self.body = Body::Idle;
        }
    }
}

/// O laço de uma peça (monomorfizado por peça: nenhum `match` por quadro). Devolve se continua.
#[inline]
fn run<S: Sound>(s: &mut S, m: &mut Mix, l: &mut [f32], r: &mut [f32], g0: f32, g1: f32) -> bool {
    let dg = (g1 - g0) / l.len().max(1) as f32;
    let mut g = g0;
    for (a, b) in l.iter_mut().zip(r.iter_mut()) {
        let (mid, side) = s.tick(&mut m.rng);
        let mut gain = g;
        if m.fade_step > 0.0 {
            m.fade -= m.fade_step;
            if m.fade <= 0.0 {
                return false;
            }
            gain *= m.fade;
        }
        *a += (mid + side) * gain * m.l;
        *b += (mid - side) * gain * m.r;
        g += dg;
    }
    !s.done()
}

// ------------------------------------------------------------------------------------------------
// o instrumento

pub struct Drums {
    rate: f32,
    /// Por peça, na ordem de `drum_param`: volume, afinação, decaimento, timbre.
    params: [[f32; 4]; PIECES],
    master: f32,
    /// Volumes como estão soando agora (rampam até `params`/`master`).
    level_now: [f32; PIECES],
    master_now: f32,
    voices: [[Voice; SLOTS]; PIECES],
    /// Ganho esquerdo/direito do pan de cada peça (potência constante, 0 dB no centro).
    pan: [[f32; 2]; PIECES],
    /// Contador de golpes: ordem das vozes e semente do ruído de cada uma.
    seq: u32,
}

impl Drums {
    pub fn new(rate: f64) -> Self {
        // taxa absurda (zero, NaN) viraria divisão por zero nos coeficientes
        let rate = (rate as f32).max(8000.0);
        Self {
            rate,
            params: [DEFAULT_PIECE; PIECES],
            master: DEFAULT_MASTER,
            level_now: [DEFAULT_PIECE[LEVEL]; PIECES],
            master_now: DEFAULT_MASTER,
            voices: [[Voice::IDLE; SLOTS]; PIECES],
            pan: PAN.map(|p| {
                let a = (p + 1.0) * FRAC_PI_4;
                [a.cos() * SQRT_2, a.sin() * SQRT_2]
            }),
            seq: 0,
        }
    }

    fn trigger(&mut self, p: usize, vel: f32) {
        let q = self.params[p];
        let hit = Hit { rate: self.rate, vel, tune: 2f32.powf(q[TUNE] / 12.0), decay: q[DECAY], tone: q[TONE] };
        let seq = self.seq.wrapping_add(1);
        let mut rng = Rng::seeded(seq);
        let body = match p {
            KICK => Body::Kick(Kick::new(&hit)),
            SNARE => Body::Snare(Snare::new(&hit)),
            CLAP => Body::Clap(Clap::new(&hit)),
            CLOSED_HAT | OPEN_HAT => Body::Hat(Hat::new(p == OPEN_HAT, &hit, &mut rng)),
            LOW_TOM | MID_TOM | HIGH_TOM => Body::Tom(Tom::new(p - LOW_TOM, &hit)),
            CRASH | RIDE => Body::Cymbal(Cymbal::new(p == RIDE, &hit, &mut rng)),
            RIM => Body::Rim(Rim::new(&hit)),
            COWBELL => Body::Cowbell(Cowbell::new(&hit)),
            _ => return,
        };
        match p {
            CLOSED_HAT => self.fade_piece(OPEN_HAT, CHOKE_FADE),
            OPEN_HAT => self.fade_piece(CLOSED_HAT, CHOKE_FADE),
            _ => {}
        }
        // peça (ou bateria) calada: o volume novo vale já, sem rampa a partir do antigo
        if !self.voices[p].iter().any(Voice::on) {
            self.level_now[p] = q[LEVEL];
        }
        if !self.active() {
            self.master_now = self.master;
        }
        let slot = self.slot_for(p);
        self.seq = seq;
        // curva de velocidade ~ v^1,5: nota fantasma (v 0,25) fica 18 dB abaixo
        let gain = GAIN[p] * vel * vel.sqrt();
        let [pl, pr] = self.pan[p];
        self.voices[p][slot] = Voice { body, mix: Mix { l: gain * pl, r: gain * pr, fade: 1.0, fade_step: 0.0, seq, rng } };
    }

    /// Esvazia uma vaga para o golpe novo na peça `p`.
    fn slot_for(&mut self, p: usize) -> usize {
        let step = 1.0 / (RETRIGGER_FADE * self.rate);
        let seq = self.seq;
        let voices = &mut self.voices[p];
        if p == CRASH || p == RIDE {
            // a cauda anterior continua por baixo; só a mais antiga sai quando não cabe mais
            let ringing = voices.iter().filter(|v| v.on() && !v.fading()).count();
            if ringing >= SLOTS - 1
                && let Some(v) = voices.iter_mut().filter(|v| v.on() && !v.fading()).max_by_key(|v| seq.wrapping_sub(v.mix.seq))
            {
                v.fade_out(step);
            }
        } else {
            for v in voices.iter_mut() {
                v.fade_out(step);
            }
        }
        if let Some(i) = voices.iter().position(|v| !v.on()) {
            return i;
        }
        // mais golpes que vozes dentro de 1,5 ms: sacrifica a que está mais perto de acabar
        (0..SLOTS).min_by(|&a, &b| voices[a].mix.fade.total_cmp(&voices[b].mix.fade)).unwrap_or(0)
    }

    fn fade_piece(&mut self, p: usize, secs: f32) {
        let step = 1.0 / (secs * self.rate);
        for v in &mut self.voices[p] {
            v.fade_out(step);
        }
    }
}

impl Instrument for Drums {
    fn note_on(&mut self, pitch: u8, velocity: f32) {
        let Some(p) = drum_param::piece_for(pitch) else { return };
        // velocidade zero é "nota solta" no MIDI; NaN também não dispara nada
        if velocity.is_nan() || velocity <= 0.0 {
            return;
        }
        self.trigger(p, velocity.min(1.0));
    }

    /// Peças de percussão tocam até o fim: soltar a nota não muda nada.
    fn note_off(&mut self, _pitch: u8) {}

    /// Idem: parar o transporte deixa as caudas (pratos, chimbal aberto) terminarem sozinhas.
    fn release_all(&mut self) {}

    fn silence(&mut self) {
        for v in self.voices.iter_mut().flatten() {
            v.body = Body::Idle;
        }
    }

    fn set_param(&mut self, id: u32, value: f32) {
        if !value.is_finite() {
            return;
        }
        if id == drum_param::MASTER {
            self.master = value.clamp(0.0, 1.5);
            return;
        }
        let (p, k) = ((id / 4) as usize, (id % 4) as usize);
        if p >= PIECES {
            return;
        }
        let (lo, hi) = RANGE[k];
        self.params[p][k] = value.clamp(lo, hi);
    }

    fn render(&mut self, left: &mut [f32], right: &mut [f32]) {
        if !self.active() {
            // nada soando: os volumes pulam direto para o alvo
            self.master_now = self.master;
            for (now, p) in self.level_now.iter_mut().zip(&self.params) {
                *now = p[LEVEL];
            }
            return;
        }
        let n = left.len().min(right.len());
        let mut start = 0;
        while start < n {
            let len = (n - start).min(CHUNK);
            // rampa de um polo, avaliada no fim do pedaço e interpolada linearmente dentro dele
            let a = (-(len as f32) / (LEVEL_SMOOTH * self.rate)).exp();
            let m0 = self.master_now;
            let m1 = self.master + (m0 - self.master) * a;
            self.master_now = m1;
            let (l, r) = (&mut left[start..start + len], &mut right[start..start + len]);
            for p in 0..PIECES {
                let target = self.params[p][LEVEL];
                let v0 = self.level_now[p];
                let v1 = target + (v0 - target) * a;
                self.level_now[p] = v1;
                for v in &mut self.voices[p] {
                    v.render(l, r, v0 * m0, v1 * m1);
                }
            }
            start += len;
        }
    }

    fn active(&self) -> bool {
        self.voices.iter().flatten().any(Voice::on)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::instrument::drum_param::PIECE_PITCH;

    const RATE: f64 = 48_000.0;

    /// Toca até a bateria ficar inativa (ou `max_secs`), em blocos de 128; devolve os dois lados.
    fn run_until_idle(d: &mut Drums, max_secs: f64) -> (Vec<f32>, Vec<f32>) {
        let (mut l, mut r) = (Vec::new(), Vec::new());
        let max = (max_secs * RATE) as usize;
        while d.active() && l.len() < max {
            let (mut bl, mut br) = ([0.0; 128], [0.0; 128]);
            d.render(&mut bl, &mut br);
            l.extend_from_slice(&bl);
            r.extend_from_slice(&br);
        }
        (l, r)
    }

    fn render(d: &mut Drums, frames: usize) -> (Vec<f32>, Vec<f32>) {
        let (mut l, mut r) = (vec![0.0; frames], vec![0.0; frames]);
        for (cl, cr) in l.chunks_mut(128).zip(r.chunks_mut(128)) {
            d.render(cl, cr);
        }
        (l, r)
    }

    fn peak(x: &[f32]) -> f32 {
        x.iter().fold(0.0, |m, s| m.max(s.abs()))
    }

    fn rms(x: &[f32]) -> f32 {
        (x.iter().map(|s| s * s).sum::<f32>() / x.len().max(1) as f32).sqrt()
    }

    /// Maior salto entre quadros vizinhos em `x[from..to]`.
    fn max_step(x: &[f32], from: usize, to: usize) -> f32 {
        x[from..to].windows(2).fold(0.0, |m, w| m.max((w[1] - w[0]).abs()))
    }

    /// Cruzamentos por zero (subindo) em `x[from..to]`.
    fn crossings(x: &[f32], from: usize, to: usize) -> usize {
        x[from..to].windows(2).filter(|w| w[0] < 0.0 && w[1] >= 0.0).count()
    }

    fn hit(pitch: u8, vel: f32, setup: impl Fn(&mut Drums)) -> (Vec<f32>, Vec<f32>) {
        let mut d = Drums::new(RATE);
        setup(&mut d);
        d.note_on(pitch, vel);
        run_until_idle(&mut d, 30.0)
    }

    #[test]
    fn cada_peca_soa_e_termina() {
        for (p, &pitch) in PIECE_PITCH.iter().enumerate() {
            for decay in [0.25, 1.0, 4.0] {
                let mut d = Drums::new(RATE);
                d.set_param(p as u32 * 4 + drum_param::DECAY, decay);
                d.note_on(pitch, 1.0);
                assert!(d.active(), "peça {p}");
                let (l, r) = run_until_idle(&mut d, 30.0);
                assert!(!d.active(), "peça {p} com decaimento {decay} não terminou em 30 s");
                let loud = peak(&l).max(peak(&r));
                assert!(loud > 0.1, "peça {p} quase muda: pico {loud}");
                assert!(loud < 1.5, "peça {p} alta demais: pico {loud}");
                // terminada, a saída é silêncio de verdade
                let (l, r) = render(&mut d, 1024);
                assert!(l.iter().chain(&r).all(|&s| s == 0.0), "peça {p}");
            }
        }
    }

    #[test]
    fn duracoes_seguem_o_decaimento() {
        let secs = |pitch: u8, decay: f32| {
            let p = drum_param::piece_for(pitch).unwrap() as u32;
            hit(pitch, 1.0, |d| d.set_param(p * 4 + drum_param::DECAY, decay)).0.len() as f64 / RATE
        };
        // fechado curto, aberto longo, prato bem mais longo; decaimento 4 alonga
        assert!(secs(42, 1.0) < 0.2);
        assert!(secs(46, 1.0) > 0.5);
        assert!(secs(49, 1.0) > 2.0);
        for pitch in [36, 38, 46, 45, 51] {
            assert!(secs(pitch, 4.0) > 2.5 * secs(pitch, 1.0), "nota {pitch}");
            assert!(secs(pitch, 0.25) < 0.5 * secs(pitch, 1.0), "nota {pitch}");
        }
    }

    #[test]
    fn nota_fora_do_mapa_e_ignorada() {
        let mut d = Drums::new(RATE);
        for pitch in [0, 34, 54, 58, 60, 127] {
            d.note_on(pitch, 1.0);
        }
        // velocidade zero é soltar a nota; NaN não é nada
        d.note_on(36, 0.0);
        d.note_on(36, f32::NAN);
        d.note_on(36, -1.0);
        assert!(!d.active());
        let (l, r) = render(&mut d, 512);
        assert!(l.iter().chain(&r).all(|&s| s == 0.0));
        // as vizinhas do General MIDI tocam a peça certa
        d.note_on(35, 1.0);
        assert!(d.voices[KICK].iter().any(Voice::on));
        d.note_on(44, 1.0);
        assert!(d.voices[CLOSED_HAT].iter().any(Voice::on));
    }

    #[test]
    fn note_off_nao_corta_a_peca() {
        let mut d = Drums::new(RATE);
        d.note_on(46, 1.0);
        let (mut l, _) = render(&mut d, 4800);
        d.note_off(46);
        d.release_all();
        l.extend(render(&mut d, 4800).0);
        let alone = hit(46, 1.0, |_| {}).0;
        assert_eq!(&l[..], &alone[..9600]);
    }

    #[test]
    fn chimbal_fechado_corta_o_aberto() {
        let open_only = hit(46, 1.0, |_| {}).0;
        let mut d = Drums::new(RATE);
        d.note_on(46, 1.0);
        let (mut l, _) = render(&mut d, 4800); // 100 ms
        d.note_on(42, 1.0);
        l.extend(render(&mut d, 960).0); // 20 ms: o corte já terminou
        assert!(d.voices[OPEN_HAT].iter().all(|v| !v.on()));
        assert!(d.voices[CLOSED_HAT].iter().any(Voice::on));
        // o corte é uma rampa, não um degrau
        assert!(max_step(&l, 4790, 5100) < 0.6);
        // o aberto sozinho soaria bem depois de o fechado ter acabado
        let total = l.len() + run_until_idle(&mut d, 30.0).0.len();
        assert!(total < open_only.len() / 3, "{total} vs {}", open_only.len());
        // o aberto também abafa o fechado (é o mesmo par de pratos)
        let mut d = Drums::new(RATE);
        d.note_on(42, 1.0);
        render(&mut d, 480);
        d.note_on(46, 1.0);
        render(&mut d, 960);
        assert!(d.voices[CLOSED_HAT].iter().all(|v| !v.on()));
    }

    #[test]
    fn redisparo_sem_estalo() {
        for pitch in [36, 41, 38] {
            let mut d = Drums::new(RATE);
            d.note_on(pitch, 1.0);
            // fora da fronteira de bloco, no meio do corpo
            let (mut l, _) = render(&mut d, 2400 + 37);
            let body = max_step(&l, 1200, l.len());
            d.note_on(pitch, 1.0);
            l.extend(render(&mut d, 480).0);
            let at = max_step(&l, 2400 + 30, 2400 + 37 + 100);
            // cortar seco a voz anterior daria um degrau do tamanho da amostra (~0,3 a 0,6)
            let attack = max_step(&hit(pitch, 1.0, |_| {}).0, 0, 100);
            assert!(at <= attack.max(body) * 1.3 + 0.02, "nota {pitch}: {at} (ataque {attack}, corpo {body})");
            // o golpe anterior já saiu (1,5 ms) e o novo toca inteiro
            assert_eq!(d.voices[drum_param::piece_for(pitch).unwrap()].iter().filter(|v| v.on()).count(), 1);
        }
    }

    #[test]
    fn pratos_deixam_a_cauda_anterior() {
        let mut d = Drums::new(RATE);
        d.note_on(51, 1.0);
        render(&mut d, 4800);
        d.note_on(51, 1.0);
        render(&mut d, 100);
        let ringing = |d: &Drums| d.voices[RIDE].iter().filter(|v| v.on() && !v.fading()).count();
        assert_eq!(ringing(&d), 2);
        // o terceiro golpe tira a cauda mais antiga
        d.note_on(51, 1.0);
        assert_eq!(ringing(&d), 2);
        render(&mut d, 480);
        assert_eq!(d.voices[RIDE].iter().filter(|v| v.on()).count(), 2);
        // rajada mais rápida que as vozes: nunca falta vaga e o golpe novo sempre toca
        for _ in 0..10 {
            d.note_on(51, 1.0);
            d.note_on(36, 1.0);
        }
        assert!(d.voices[RIDE].iter().filter(|v| v.on()).count() <= SLOTS);
        let (l, r) = render(&mut d, 4800);
        assert!(l.iter().chain(&r).all(|s| s.is_finite() && s.abs() < 4.0));
    }

    #[test]
    fn sem_nan_com_parametros_extremos() {
        let extremes = [f32::NAN, f32::INFINITY, f32::NEG_INFINITY, -1e30, 1e30, 0.0, -0.0, f32::MIN_POSITIVE];
        for rate in [8000.0, 22_050.0, 44_100.0, 48_000.0, 96_000.0, 192_000.0] {
            for (i, &x) in extremes.iter().enumerate() {
                let mut d = Drums::new(rate);
                // alterna entre o valor exótico e as pontas da faixa em cada parâmetro
                for id in 0..=drum_param::MASTER + 2 {
                    let (lo, hi) = RANGE[id as usize % 4];
                    let v = match (id as usize + i) % 3 {
                        0 => x,
                        1 => lo,
                        _ => hi,
                    };
                    d.set_param(id, v);
                }
                assert!(d.params.iter().flatten().chain([&d.master]).all(|v| v.is_finite()));
                for pitch in 30..=62 {
                    d.note_on(pitch, if pitch % 2 == 0 { 1.0 } else { 1e9 });
                }
                let frames = (rate * 0.5) as usize;
                let (mut l, mut r) = (vec![0.0; frames], vec![0.0; frames]);
                let mut at = 0;
                for n in [1, 7, 4096, 128, 333].iter().cycle() {
                    if at >= frames {
                        break;
                    }
                    let end = (at + n).min(frames);
                    d.render(&mut l[at..end], &mut r[at..end]);
                    at = end;
                }
                assert!(l.iter().chain(&r).all(|s| s.is_finite() && s.abs() < 32.0), "taxa {rate}, extremo {x}: {}", peak(&l).max(peak(&r)));
            }
        }
        // taxa inválida não vira divisão por zero
        let mut d = Drums::new(0.0);
        d.note_on(36, 1.0);
        let (l, _) = render(&mut d, 256);
        assert!(l.iter().all(|s| s.is_finite()));
    }

    #[test]
    fn master_zero_silencia() {
        let mut d = Drums::new(RATE);
        d.set_param(drum_param::MASTER, 0.0);
        for &pitch in &PIECE_PITCH {
            d.note_on(pitch, 1.0);
        }
        let (l, r) = render(&mut d, 48_000);
        assert!(l.iter().chain(&r).all(|&s| s == 0.0));
        // volume zero de uma peça cala só ela
        let mut d = Drums::new(RATE);
        d.set_param(SNARE as u32 * 4 + drum_param::LEVEL, 0.0);
        d.note_on(38, 1.0);
        let (l, _) = render(&mut d, 4800);
        assert!(l.iter().all(|&s| s == 0.0));
        d.note_on(36, 1.0);
        let (l, _) = render(&mut d, 4800);
        assert!(peak(&l) > 0.1);
    }

    #[test]
    fn volume_muda_com_rampa() {
        let reference = hit(36, 1.0, |_| {}).0;
        let mut d = Drums::new(RATE);
        d.note_on(36, 1.0);
        let (mut l, _) = render(&mut d, 4800);
        d.set_param(drum_param::MASTER, 0.0);
        l.extend(render(&mut d, 9600).0);
        // sem degrau na mudança: os primeiros quadros quase não mudam, e em 100 ms já calou
        assert!((l[4800] - reference[4800]).abs() < 0.02);
        assert!(max_step(&l, 4700, 5000) < 2.0 * max_step(&reference, 4700, 5000));
        assert!(peak(&l[9600..]) < 1e-3);
        // com tudo calado, o volume novo vale já no próximo golpe (sem rampa a partir do antigo)
        let mut d = Drums::new(RATE);
        d.set_param(KICK as u32 * 4 + drum_param::LEVEL, 0.5);
        d.note_on(36, 1.0);
        let (l, _) = render(&mut d, 4800);
        assert!((l[2400] - reference[2400] * 0.5).abs() < 1e-4);
    }

    #[test]
    fn velocidade_escala_o_volume() {
        let strong = peak(&hit(36, 1.0, |_| {}).0);
        let soft = peak(&hit(36, 0.5, |_| {}).0);
        let ratio = soft / strong;
        assert!((0.3..0.42).contains(&ratio), "{ratio}");
        // e escurece um pouco: menos agudo relativo no chimbal fraco
        let bright = |vel: f32| {
            let x = hit(42, vel, |_| {}).0;
            let diff: f32 = x.windows(2).map(|w| (w[1] - w[0]).abs()).sum();
            diff / x.iter().map(|s| s.abs()).sum::<f32>()
        };
        assert!(bright(0.3) < bright(1.0));
    }

    #[test]
    fn afinacao_muda_a_altura() {
        let tuned = |semis: f32| {
            let x = hit(45, 1.0, |d| d.set_param(MID_TOM as u32 * 4 + drum_param::TUNE, semis)).0;
            // janela depois da queda de altura
            crossings(&x, 12_000, 24_000) as f32
        };
        let base = tuned(0.0);
        assert!((base / 0.25 - 131.0).abs() < 8.0, "{base}");
        assert!((tuned(12.0) / base - 2.0).abs() < 0.1);
        assert!((tuned(-12.0) / base - 0.5).abs() < 0.06);
        // bumbo: o corpo assenta perto de 50 Hz
        let kick = hit(36, 1.0, |_| {}).0;
        let hz = crossings(&kick, 9600, 19_200) as f32 / 0.2;
        assert!((hz - 50.0).abs() < 3.0, "{hz}");
    }

    #[test]
    fn estereo_discreto() {
        let (l, r) = hit(42, 1.0, |_| {});
        let (el, er) = (rms(&l), rms(&r));
        assert!(er > el && er < el * 2.0, "{el} {er}");
        let (l, r) = hit(36, 1.0, |_| {});
        assert_eq!(l, r);
    }

    #[test]
    fn silence_corta_na_hora() {
        let mut d = Drums::new(RATE);
        d.note_on(49, 1.0);
        d.note_on(36, 1.0);
        render(&mut d, 1000);
        d.silence();
        assert!(!d.active());
        let (l, r) = render(&mut d, 512);
        assert!(l.iter().chain(&r).all(|&s| s == 0.0));
    }

    #[test]
    fn blocos_de_qualquer_tamanho_dao_o_mesmo_som() {
        let play = |sizes: &[usize]| {
            let mut d = Drums::new(RATE);
            let frames = 48_000;
            let (mut l, mut r) = (vec![0.0; frames], vec![0.0; frames]);
            let mut at = 0;
            let mut hits = [(0, 36), (0, 42), (6000, 38), (12_000, 46), (18_000, 42), (24_000, 51)].into_iter().peekable();
            for n in sizes.iter().cycle() {
                if at >= frames {
                    break;
                }
                while let Some(&(when, pitch)) = hits.peek() {
                    if when > at {
                        break;
                    }
                    d.note_on(pitch, 0.9);
                    hits.next();
                }
                // o bloco para no próximo golpe, como o motor faz
                let next = hits.peek().map_or(frames, |h| h.0);
                let end = (at + n).min(frames).min(next.max(at + 1));
                d.render(&mut l[at..end], &mut r[at..end]);
                at = end;
            }
            l
        };
        let a = play(&[128]);
        let b = play(&[1, 17, 333, 4096, 64, 5]);
        let worst = a.iter().zip(&b).fold(0.0f32, |m, (x, y)| m.max((x - y).abs()));
        assert!(worst < 1e-4, "{worst}");
    }

    #[test]
    fn ids_desconhecidos_e_faixas() {
        let mut d = Drums::new(RATE);
        let before = d.params;
        d.set_param(49, 1.0);
        d.set_param(1000, 1.0);
        d.set_param(u32::MAX, 1.0);
        assert_eq!(d.params, before);
        d.set_param(4 + drum_param::TUNE, 99.0);
        d.set_param(4 + drum_param::DECAY, 0.0);
        d.set_param(drum_param::MASTER, 9.0);
        assert_eq!(d.params[SNARE][TUNE], 12.0);
        assert_eq!(d.params[SNARE][DECAY], 0.25);
        assert_eq!(d.master, 1.5);
    }

    #[test]
    fn seno_polinomial_confere() {
        for i in 0..10_000 {
            let p = i as f32 / 10_000.0;
            assert!((sine(p) - (p * TAU).sin()).abs() < 1e-5, "{p}");
        }
    }

    /// Pior caso de CPU (as doze peças redisparadas a cada semicolcheia a 120 bpm, com os pratos
    /// acumulando caudas): `cargo test -p jopendaw-engine --release desempenho -- --ignored --nocapture`.
    #[test]
    #[ignore]
    fn desempenho() {
        let mut d = Drums::new(RATE);
        let secs = 20.0;
        let step = (RATE * 60.0 / 120.0 / 4.0) as usize;
        let (mut l, mut r) = ([0.0; 128], [0.0; 128]);
        let start = std::time::Instant::now();
        let mut frame = 0;
        while frame < (secs * RATE) as usize {
            if frame % step < 128 {
                for &pitch in &PIECE_PITCH {
                    d.note_on(pitch, 0.9);
                }
            }
            d.render(&mut l, &mut r);
            frame += 128;
        }
        let took = start.elapsed().as_secs_f64();
        println!("{secs} s de áudio em {took:.3} s: {:.0}× o tempo real", secs / took);
    }

    /// Grava um WAV estéreo de ponto flutuante.
    fn write_wav(path: &std::path::Path, l: &[f32], r: &[f32]) {
        let mut b = Vec::with_capacity(44 + l.len() * 8);
        let data = (l.len() * 8) as u32;
        b.extend_from_slice(b"RIFF");
        b.extend_from_slice(&(36 + data).to_le_bytes());
        b.extend_from_slice(b"WAVEfmt ");
        b.extend_from_slice(&16u32.to_le_bytes());
        b.extend_from_slice(&3u16.to_le_bytes()); // IEEE float
        b.extend_from_slice(&2u16.to_le_bytes());
        b.extend_from_slice(&(RATE as u32).to_le_bytes());
        b.extend_from_slice(&(RATE as u32 * 8).to_le_bytes());
        b.extend_from_slice(&8u16.to_le_bytes());
        b.extend_from_slice(&32u16.to_le_bytes());
        b.extend_from_slice(b"data");
        b.extend_from_slice(&data.to_le_bytes());
        for (a, c) in l.iter().zip(r) {
            b.extend_from_slice(&a.to_le_bytes());
            b.extend_from_slice(&c.to_le_bytes());
        }
        std::fs::write(path, b).unwrap();
    }

    /// Grava cada peça (e variações de parâmetro) e uma levada em WAV, para ouvir:
    /// `DRUMS_WAV=<pasta> cargo test -p jopendaw-engine grava_wav -- --ignored`.
    #[test]
    #[ignore]
    fn grava_wav() {
        let Ok(dir) = std::env::var("DRUMS_WAV") else { return };
        let dir = std::path::Path::new(&dir);
        std::fs::create_dir_all(dir).unwrap();
        let variants: [(&str, u32, f32, f32); 8] = [
            ("padrao", 0, 1.0, 1.0),
            ("timbre0", drum_param::TONE, 0.0, 1.0),
            ("timbre1", drum_param::TONE, 1.0, 1.0),
            ("grave", drum_param::TUNE, -12.0, 1.0),
            ("agudo", drum_param::TUNE, 12.0, 1.0),
            ("curto", drum_param::DECAY, 0.25, 1.0),
            ("longo", drum_param::DECAY, 4.0, 1.0),
            ("fraco", 0, 1.0, 0.3),
        ];
        for (p, &pitch) in PIECE_PITCH.iter().enumerate() {
            for (name, k, value, vel) in variants {
                let mut d = Drums::new(RATE);
                d.set_param(drum_param::MASTER, 1.0);
                d.set_param(p as u32 * 4 + k, value);
                d.note_on(pitch, vel);
                let (l, r) = run_until_idle(&mut d, 30.0);
                write_wav(&dir.join(format!("{p:02}_{name}.wav")), &l, &r);
            }
        }
        // dois compassos a 120 bpm, em semicolcheias: 1 bumbo, 2 caixa, 3 palmas, h chimbal
        // fechado, o aberto, c prato, t toms, r aro, b cowbell, d condução
        let grid = [
            "k...............k.......k.k.....",
            "....s.......s.......s.......s..s",
            "............p...............p...",
            "h.h.h.h.h.h.h...h.h.h.h.h.h.....",
            "..............o.............o...",
            "c...............................",
            "..........................t.t.t.",
        ];
        let step = (RATE * 60.0 / 120.0 / 4.0) as usize;
        let map = |ch: char, i: usize| match ch {
            'k' => Some((36, 1.0)),
            's' => Some((38, if i == 31 { 0.35 } else { 0.95 })),
            'p' => Some((39, 0.9)),
            'h' => Some((42, if i.is_multiple_of(4) { 0.9 } else { 0.6 })),
            'o' => Some((46, 0.8)),
            'c' => Some((49, 1.0)),
            't' => Some(([48, 45, 41][(i - 26) / 2], 0.9)),
            _ => None,
        };
        let mut d = Drums::new(RATE);
        let (mut l, mut r) = (Vec::new(), Vec::new());
        for rep in 0..2 {
            for i in 0..32 {
                for row in grid {
                    if let Some((pitch, vel)) = map(row.as_bytes()[i] as char, i) {
                        if rep == 1 && pitch == 49 {
                            continue;
                        }
                        d.note_on(pitch, vel);
                    }
                }
                let (bl, br) = render(&mut d, step);
                l.extend(bl);
                r.extend(br);
            }
        }
        let (bl, br) = run_until_idle(&mut d, 10.0);
        l.extend(bl);
        r.extend(br);
        write_wav(&dir.join("levada.wav"), &l, &r);
    }

    // ------------------------------------------------------------ contrato com o app

    /// `drumParams` e `drumPieces` (instruments.dart) e `DrumId` (presets.dart) contra o motor: as
    /// peças e suas notas, a faixa e o padrão de cada um dos 4 parâmetros e do volume geral.
    #[test]
    fn tabela_e_ids_iguais_aos_do_app() {
        use crate::instrument::{contract, drum_param as dp};
        let Some(src) = contract::source() else { return };
        // peças: `DrumPiece('nome', nota)`, na ordem dos ids
        let pieces = &src[src.find("const drumPieces").or_else(|| src.find("final drumPieces")).expect("drumPieces não está no app")..];
        let pieces = &pieces[..pieces.find("];").unwrap()];
        let pitches: Vec<u8> = pieces
            .lines()
            .filter_map(|l| l.trim().strip_prefix("DrumPiece("))
            .map(|l| l.trim_end_matches([')', ',']).rsplit(',').next().unwrap().trim().parse().unwrap())
            .collect();
        assert_eq!(pitches, PIECE_PITCH, "peças e notas do app");
        // a tabela é um laço sobre as peças (4 linhas) mais o volume geral (48)
        let table = &src[src.find("final drumParams").unwrap()..];
        let table = &table[..table.find("];").unwrap()];
        let field = |line: &str| -> [f32; 3] {
            let f: Vec<&str> = line.split(',').map(str::trim).collect();
            [f[3].parse().unwrap(), f[4].parse().unwrap(), f[5].trim_end_matches(')').parse().unwrap()]
        };
        let mut want: Vec<Option<[f32; 3]>> = vec![None; 4];
        let mut master = None;
        for line in table.lines().map(str::trim) {
            if let Some(rest) = line.strip_prefix("ParamSpec(i * 4") {
                let k = if let Some(r) = rest.strip_prefix(" + ") { r.split(',').next().unwrap().parse::<usize>().unwrap() } else { 0 };
                let rest = format!("{k}{}", &rest[rest.find(',').unwrap()..]);
                want[k] = Some(field(&rest));
            } else if let Some(rest) = line.strip_prefix("const ParamSpec(48,") {
                master = Some(field(&format!("48,{rest}")));
            }
        }
        let want: Vec<[f32; 3]> = want.into_iter().map(|w| w.expect("os 4 parâmetros de peça no app")).collect();
        let d = Drums::new(RATE);
        for (k, &[min, max, def]) in want.iter().enumerate() {
            assert_eq!((RANGE[k].0, RANGE[k].1, DEFAULT_PIECE[k]), (min, max, def), "parâmetro {k} da peça");
            // e o `set_param` limita nessa faixa
            let mut d = Drums::new(RATE);
            d.set_param(k as u32, min - 1e6);
            assert_eq!(d.params[0][k], min);
            d.set_param(k as u32, max + 1e6);
            assert_eq!(d.params[0][k], max);
            assert_eq!(d.params[PIECES - 1][k], DEFAULT_PIECE[k]);
        }
        assert_eq!(d.master, DEFAULT_MASTER);
        let [min, max, def] = master.expect("volume geral no app");
        let mut m = Drums::new(RATE);
        assert_eq!(m.master, def);
        m.set_param(dp::MASTER, min - 1e6);
        assert_eq!(m.master, min);
        m.set_param(dp::MASTER, max + 1e6);
        assert_eq!(m.master, max);
        // `DrumId` do app
        let consts = [("LEVEL", dp::LEVEL), ("TUNE", dp::TUNE), ("DECAY", dp::DECAY), ("TONE", dp::TONE), ("MASTER", dp::MASTER)];
        for (name, value) in contract::dart_ids("DrumId") {
            let name = contract::screaming(&name);
            let engine = consts.iter().find(|c| c.0 == name).unwrap_or_else(|| panic!("DrumId.{name} não existe no motor"));
            assert_eq!(engine.1, value, "DrumId.{name}");
        }
    }
}
