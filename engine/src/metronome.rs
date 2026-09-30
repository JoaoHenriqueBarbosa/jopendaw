//! Metrônomo: um clique sintético em cada tempo do compasso vigente, com acento no primeiro tempo.
//!
//! Sem samples e sem alocação: cada timbre é uma senoide (ou duas) ou ruído filtrado com um
//! envelope curto que chega a zero no fim (sem estalo). O padrão (timbre `Click`, sem subdivisão,
//! acento 1600 Hz contra 1000 Hz) é o clique de sempre, quadro a quadro.
//!
//! As subdivisões dividem o tempo do compasso (a semínima em x/4, a colcheia em 6/8 e 7/8): 2
//! (colcheias em x/4), 3 (tercina) ou 4 (semicolcheias) cliques por tempo, ou só o acento do
//! primeiro tempo. Os cliques seguem o mapa de compassos e o de andamento, e o que cai entre dois
//! tempos usa a batida interpolada entre eles (o render fora de tempo real dá o mesmo resultado do
//! tempo real: nenhum estado depende de onde o bloco termina).

use crate::tempo::{Click, MeterMap, TempoMap};

/// Duração do clique padrão.
const CLICK_SECS: f64 = 0.03;
/// Frequência do clique padrão (Hz); o acento multiplica por [`DEFAULT_ACCENT_PITCH`] (ou o que o app mandar).
const CLICK_HZ: f64 = 1000.0;
/// Altura padrão do acento: 1600 Hz sobre 1000 Hz.
pub const DEFAULT_ACCENT_PITCH: f32 = 1.6;
/// Semente do ruído do hi-hat: a mesma em todo clique, para o resultado não depender do que veio antes.
const NOISE_SEED: u32 = 0x9E37_79B9;

/// Os timbres do clique (o número é o que o app manda).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Timbre {
    /// O clique senoidal padrão.
    Click = 0,
    /// Madeira (wood block): duas parciais que morrem rápido.
    Wood = 1,
    /// Bipe agudo, com corpo e bordas suaves.
    Beep = 2,
    /// Cowbell: duas senoides inarmônicas.
    Cowbell = 3,
    /// Hi-hat: ruído passa-altas.
    HiHat = 4,
}

impl Timbre {
    pub const ALL: [Timbre; 5] = [Timbre::Click, Timbre::Wood, Timbre::Beep, Timbre::Cowbell, Timbre::HiHat];

    /// O timbre de um código do app; fora da faixa vale o padrão.
    pub fn from_code(code: u32) -> Timbre {
        Self::ALL.get(code as usize).copied().unwrap_or(Timbre::Click)
    }

    /// Duração do clique (s) e frequência base (Hz; no hi-hat, o corte do passa-altas).
    fn shape(self) -> (f64, f64) {
        match self {
            Timbre::Click => (CLICK_SECS, CLICK_HZ),
            Timbre::Wood => (0.06, 800.0),
            Timbre::Beep => (0.05, 1800.0),
            Timbre::Cowbell => (0.16, 540.0),
            Timbre::HiHat => (0.06, 6000.0),
        }
    }
}

/// Divisões do tempo (o número é o que o app manda).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Subdivision {
    /// Um clique por tempo (a semínima em x/4).
    Beat = 0,
    /// Dois por tempo (colcheias em x/4).
    Eighth = 1,
    /// Três por tempo (tercina).
    Triplet = 2,
    /// Quatro por tempo (semicolcheias em x/4).
    Sixteenth = 3,
    /// Só o acento do primeiro tempo de cada compasso.
    AccentOnly = 4,
}

impl Subdivision {
    pub const ALL: [Subdivision; 5] = [Subdivision::Beat, Subdivision::Eighth, Subdivision::Triplet, Subdivision::Sixteenth, Subdivision::AccentOnly];

    pub fn from_code(code: u32) -> Subdivision {
        Self::ALL.get(code as usize).copied().unwrap_or(Subdivision::Beat)
    }

    /// Cliques por tempo do compasso.
    fn parts(self) -> u32 {
        match self {
            Subdivision::Beat | Subdivision::AccentOnly => 1,
            Subdivision::Eighth => 2,
            Subdivision::Triplet => 3,
            Subdivision::Sixteenth => 4,
        }
    }
}

/// Que clique é: o do primeiro tempo, o de um tempo comum ou o de uma subdivisão.
#[derive(Clone, Copy, PartialEq, Eq)]
enum Kind {
    Accent,
    Beat,
    Sub,
}

/// O próximo clique: o tempo do compasso e a subdivisão dentro dele.
#[derive(Clone, Copy)]
struct Cursor {
    click: Click,
    sub: u32,
}

#[derive(Clone, Debug)]
pub struct Metronome {
    pub on: bool,
    pub gain: f32,
    timbre: Timbre,
    subdivision: Subdivision,
    /// Nível do acento e das subdivisões em relação a `gain`.
    accent_level: f32,
    sub_level: f32,
    /// Quanto o acento é mais agudo que o clique comum (razão de frequência).
    accent_pitch: f32,
    /// Quadros que faltam do clique atual e quantos ele tem ao todo.
    left: usize,
    total: usize,
    /// Nível deste clique em relação a `gain`.
    level: f32,
    freq: f64,
    phase: f64,
    phase2: f64,
    /// Ruído e passa-altas do hi-hat.
    rng: u32,
    hp_a: f32,
    x1: f32,
    y1: f32,
}

impl Default for Metronome {
    fn default() -> Self {
        Self {
            on: false,
            gain: 0.6,
            timbre: Timbre::Click,
            subdivision: Subdivision::Beat,
            accent_level: 1.0,
            sub_level: 0.5,
            accent_pitch: DEFAULT_ACCENT_PITCH,
            left: 0,
            total: 0,
            level: 1.0,
            freq: CLICK_HZ,
            phase: 0.0,
            phase2: 0.0,
            rng: NOISE_SEED,
            hp_a: 0.0,
            x1: 0.0,
            y1: 0.0,
        }
    }
}

impl Metronome {
    pub fn silence(&mut self) {
        self.left = 0;
    }

    /// Timbre, subdivisão, nível do acento e das subdivisões (em relação ao ganho) e altura do acento
    /// (razão de frequência). Valores fora da faixa são limitados; o que não é número volta ao padrão.
    pub fn set_style(&mut self, timbre: u32, subdivision: u32, accent_level: f32, accent_pitch: f32, sub_level: f32) {
        self.timbre = Timbre::from_code(timbre);
        self.subdivision = Subdivision::from_code(subdivision);
        self.accent_level = if accent_level.is_finite() { accent_level.clamp(0.0, 2.0) } else { 1.0 };
        self.sub_level = if sub_level.is_finite() { sub_level.clamp(0.0, 2.0) } else { 0.5 };
        self.accent_pitch = if accent_pitch.is_finite() { accent_pitch.clamp(0.5, 4.0) } else { DEFAULT_ACCENT_PITCH };
    }

    pub fn timbre(&self) -> Timbre {
        self.timbre
    }

    pub fn subdivision(&self) -> Subdivision {
        self.subdivision
    }

    fn kind(&self, c: Cursor, meter: &MeterMap) -> Option<Kind> {
        if c.sub != 0 {
            Some(Kind::Sub)
        } else if meter.is_downbeat(c.click) {
            Some(Kind::Accent)
        } else if self.subdivision == Subdivision::AccentOnly {
            None
        } else {
            Some(Kind::Beat)
        }
    }

    fn frame_of(c: Cursor, tempo: &TempoMap, meter: &MeterMap, parts: u32) -> f64 {
        let b0 = meter.beat_of(c.click);
        if c.sub == 0 {
            return tempo.to_frames(b0);
        }
        let b1 = meter.beat_of(meter.next(c.click));
        tempo.to_frames(b0 + (b1 - b0) * f64::from(c.sub) / f64::from(parts))
    }

    fn step(c: &mut Cursor, meter: &MeterMap, parts: u32) {
        c.sub += 1;
        if c.sub >= parts {
            c.sub = 0;
            c.click = meter.next(c.click);
        }
    }

    /// Soma os cliques do bloco que começa em `pos` (quadros da linha do tempo). Os cliques caem
    /// nos tempos do compasso vigente (`meter`), na posição em quadros que o mapa de andamento
    /// dá a cada um; o primeiro tempo do compasso é o acento.
    pub fn render(&mut self, l: &mut [f32], r: &mut [f32], pos: f64, tempo: &TempoMap, meter: &MeterMap, rate: f64) {
        if !self.on {
            self.left = 0;
            return;
        }
        let parts = self.subdivision.parts();
        let end = pos + l.len() as f64;
        // primeiro clique que cai neste bloco (a folga de 1e-6 batida absorve o erro da conversão); com
        // subdivisão, começa um tempo (4 semínimas, no máximo) antes para pegar as que vêm entre os tempos
        let back = if parts > 1 { 4.0 } else { 0.0 };
        let mut cur = Cursor { click: meter.click_at_or_after(tempo.to_beats(pos) - 1e-6 - back), sub: 0 };
        let mut at = loop {
            let f = Self::frame_of(cur, tempo, meter, parts);
            if f >= pos && self.kind(cur, meter).is_some() {
                break f;
            }
            Self::step(&mut cur, meter, parts);
        };
        // o quadro do bloco em que o próximo clique começa (o do quadro inteiro que o contém)
        let mut next = if at < end { (at - pos) as usize } else { usize::MAX };
        for i in 0..l.len() {
            while i == next {
                if let Some(kind) = self.kind(cur, meter) {
                    self.fire(kind, rate);
                }
                Self::step(&mut cur, meter, parts);
                while self.kind(cur, meter).is_none() {
                    Self::step(&mut cur, meter, parts);
                }
                at = Self::frame_of(cur, tempo, meter, parts);
                next = if at < end { ((at - pos) as usize).max(i + 1) } else { usize::MAX };
            }
            if self.left > 0 {
                let s = self.voice(rate) * (self.gain * self.level);
                self.left -= 1;
                l[i] += s;
                r[i] += s;
            }
        }
    }

    /// Começa um clique do [`Kind`] dado (o anterior, se ainda soa, é cortado: o clique novo entra
    /// em fase zero, como sempre foi).
    fn fire(&mut self, kind: Kind, rate: f64) {
        let (secs, base) = self.timbre.shape();
        let (level, pitch) = match kind {
            Kind::Accent => (self.accent_level, f64::from(self.accent_pitch)),
            Kind::Beat => (1.0, 1.0),
            Kind::Sub => (self.sub_level, 1.0),
        };
        // a razão (f32) volta ao decimal em que foi escolhida: 1,6 dá 1600 Hz exatos
        let pitch = (pitch * 1000.0).round() / 1000.0;
        self.total = ((secs * rate) as usize).max(1);
        self.left = self.total;
        self.level = level;
        self.freq = base * pitch;
        self.phase = 0.0;
        self.phase2 = 0.0;
        if self.timbre == Timbre::HiHat {
            let fc = self.freq.min(rate * 0.4);
            self.hp_a = (-std::f64::consts::TAU * fc / rate).exp() as f32;
            self.rng = NOISE_SEED;
            self.x1 = 0.0;
            self.y1 = 0.0;
        }
    }

    /// A próxima amostra do clique em curso, sem o nível (o envelope já vai nela).
    fn voice(&mut self, rate: f64) -> f32 {
        let x = self.left as f64 / self.total as f64;
        let done = self.total - self.left;
        // subida de 0,5 ms nos timbres que não começam em zero
        let attack = (done as f64 / (0.0005 * rate)).min(1.0) as f32;
        let tau = std::f64::consts::TAU;
        match self.timbre {
            Timbre::Click => {
                let env = x.powi(3) as f32;
                let s = (self.phase * tau).sin() as f32 * env;
                self.phase += self.freq / rate;
                s
            }
            Timbre::Wood => {
                let env = x.powi(4) as f32;
                let s = ((self.phase * tau).sin() + 0.35 * (self.phase2 * tau).sin()) as f32 * env * attack * 0.75;
                self.phase += self.freq / rate;
                self.phase2 += self.freq * 2.4 / rate;
                s
            }
            Timbre::Beep => {
                // corpo plano com bordas de 2 ms
                let edge = (0.002 * rate).max(1.0);
                let env = (done as f64 / edge).min(self.left as f64 / edge).min(1.0) as f32;
                let s = (self.phase * tau).sin() as f32 * env * 0.8;
                self.phase += self.freq / rate;
                s
            }
            Timbre::Cowbell => {
                let env = x.powf(2.5) as f32;
                let s = ((self.phase * tau).sin() + 0.8 * (self.phase2 * tau).sin()) as f32 * env * attack * 0.55;
                self.phase += self.freq / rate;
                self.phase2 += self.freq * 1.4815 / rate;
                s
            }
            Timbre::HiHat => {
                self.rng ^= self.rng << 13;
                self.rng ^= self.rng >> 17;
                self.rng ^= self.rng << 5;
                let n = (self.rng as f32 / u32::MAX as f32) * 2.0 - 1.0;
                // passa-altas de um polo: y = a (y' + x − x')
                let y = self.hp_a * (self.y1 + n - self.x1);
                self.x1 = n;
                self.y1 = y;
                y * (x.powi(3) as f32) * attack * 0.7
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const RATE: f64 = 48_000.0;

    /// Renderiza `frames` quadros em blocos de `block` e devolve o canal esquerdo.
    fn run(m: &mut Metronome, tempo: &TempoMap, meter: &MeterMap, from: f64, frames: usize, block: usize) -> Vec<f32> {
        let mut out = Vec::with_capacity(frames);
        let mut pos = from;
        while out.len() < frames {
            let n = block.min(frames - out.len());
            let (mut l, mut r) = (vec![0.0; n], vec![0.0; n]);
            m.render(&mut l, &mut r, pos, tempo, meter, RATE);
            out.extend_from_slice(&l);
            pos += n as f64;
        }
        out
    }

    fn maps(bpm: f64, meter: MeterMap) -> (TempoMap, MeterMap) {
        (TempoMap::new(RATE, bpm), meter)
    }

    fn on(gain: f32) -> Metronome {
        Metronome { on: true, gain, ..Metronome::default() }
    }

    /// Começos de clique: os quadros em que o sinal sai de um silêncio de 40 quadros.
    fn onsets(s: &[f32]) -> Vec<usize> {
        let mut v = Vec::new();
        let mut last_loud: Option<usize> = None;
        for (i, x) in s.iter().enumerate() {
            if x.abs() > 1e-4 {
                if last_loud.is_none_or(|p| i - p > 40) {
                    v.push(i);
                }
                last_loud = Some(i);
            }
        }
        v
    }

    fn peak(s: &[f32]) -> f32 {
        s.iter().fold(0.0, |a, x| a.max(x.abs()))
    }

    #[test]
    fn cada_timbre_tem_energia_e_termina() {
        for t in Timbre::ALL {
            let mut m = on(1.0);
            m.set_style(t as u32, 0, 1.0, 1.6, 0.5);
            let (tempo, meter) = maps(60.0, MeterMap::new(4));
            let s = run(&mut m, &tempo, &meter, 0.0, 48_000, 128);
            let energy: f32 = s[..8000].iter().map(|x| x * x).sum();
            assert!(energy > 0.01, "{t:?}: sem energia ({energy})");
            assert!(s.iter().all(|x| x.is_finite() && x.abs() <= 1.5), "{t:?}: fora da faixa");
            // o clique acaba bem antes do próximo (1 s depois) e termina em zero
            assert!(s[9000..47_000].iter().all(|&x| x == 0.0), "{t:?}: não terminou");
            let last = s[..8000].iter().rev().find(|x| **x != 0.0).map_or(0.0, |x| x.abs());
            assert!(last < 0.02, "{t:?}: termina com estalo ({last})");
        }
    }

    #[test]
    fn cada_timbre_soa_diferente() {
        let (tempo, meter) = maps(60.0, MeterMap::new(4));
        let all: Vec<Vec<f32>> = Timbre::ALL
            .iter()
            .map(|&t| {
                let mut m = on(1.0);
                m.set_style(t as u32, 0, 1.0, 1.6, 0.5);
                run(&mut m, &tempo, &meter, 0.0, 9000, 128)
            })
            .collect();
        for i in 0..all.len() {
            for j in i + 1..all.len() {
                assert_ne!(all[i], all[j], "timbres {i} e {j} iguais");
            }
        }
    }

    /// Cliques do primeiro compasso inteiro num compasso `num/den`.
    fn clicks_in_bar(num: u32, den: u32, sub: u32) -> usize {
        let mut meter = MeterMap::new(4);
        meter.insert(1, num, den);
        let tempo = TempoMap::new(RATE, 120.0);
        let mut m = on(1.0);
        m.set_style(0, sub, 1.0, 1.6, 0.5);
        // 120 bpm: uma semínima = 0,5 s; o compasso tem num * 4/den semínimas
        let bar_frames = (f64::from(num) * 4.0 / f64::from(den) * 0.5 * RATE) as usize;
        let s = run(&mut m, &tempo, &meter, 0.0, bar_frames - 1, 100);
        onsets(&s).len()
    }

    #[test]
    fn subdivisoes_dao_o_numero_certo_de_cliques() {
        // 4/4: semínima, colcheia, tercina, semicolcheia, só o acento
        assert_eq!([0, 1, 2, 3, 4].map(|s| clicks_in_bar(4, 4, s)), [4, 8, 12, 16, 1]);
        // 6/8: o tempo é a colcheia
        assert_eq!([0, 1, 2, 3, 4].map(|s| clicks_in_bar(6, 8, s)), [6, 12, 18, 24, 1]);
        // 7/8
        assert_eq!([0, 1, 2, 3, 4].map(|s| clicks_in_bar(7, 8, s)), [7, 14, 21, 28, 1]);
    }

    #[test]
    fn cliques_de_subdivisao_caem_igualmente_espacados() {
        let (tempo, meter) = maps(120.0, MeterMap::new(4));
        let mut m = on(1.0);
        m.set_style(0, 2, 1.0, 1.6, 0.5);
        let s = run(&mut m, &tempo, &meter, 0.0, 24_000, 64);
        let o = onsets(&s);
        assert_eq!(o.len(), 3);
        // tercina: 3 por semínima (0,5 s) = 8000 quadros
        for (k, at) in o.iter().enumerate() {
            assert!((*at as i64 - (k * 8000) as i64).abs() <= 1, "{o:?}");
        }
    }

    #[test]
    fn acento_mais_forte_no_primeiro_tempo() {
        let (tempo, meter) = maps(120.0, MeterMap::new(4));
        let mut m = on(0.5);
        m.set_style(0, 0, 1.5, 1.0, 0.5);
        let s = run(&mut m, &tempo, &meter, 0.0, 4 * 24_000, 128);
        let p = |k: usize| peak(&s[k * 24_000..k * 24_000 + 2000]);
        assert!(p(0) > p(1) * 1.4, "{} {}", p(0), p(1));
        assert!((p(1) - p(2)).abs() < 1e-6 && (p(2) - p(3)).abs() < 1e-6);
        // acento mudo: o primeiro tempo some, os outros não
        let mut quiet = on(0.5);
        quiet.set_style(0, 0, 0.0, 1.6, 0.5);
        let s3 = run(&mut quiet, &tempo, &meter, 0.0, 4 * 24_000, 128);
        assert_eq!(peak(&s3[..2000]), 0.0);
        assert!(peak(&s3[24_000..26_000]) > 0.1);
    }

    #[test]
    fn altura_do_acento_muda_a_frequencia() {
        let (tempo, meter) = maps(120.0, MeterMap::new(4));
        let zero_crossings = |pitch: f32| {
            let mut m = on(1.0);
            m.set_style(0, 0, 1.0, pitch, 0.5);
            let s = run(&mut m, &tempo, &meter, 0.0, 1440, 128);
            s.windows(2).filter(|w| w[0] <= 0.0 && w[1] > 0.0).count()
        };
        assert!(zero_crossings(3.0) > zero_crossings(1.0) * 2);
    }

    #[test]
    fn subdivisao_toca_mais_baixa_que_o_tempo() {
        let (tempo, meter) = maps(120.0, MeterMap::new(4));
        let mut m = on(1.0);
        m.set_style(0, 1, 1.0, 1.0, 0.25);
        let s = run(&mut m, &tempo, &meter, 0.0, 24_000, 128);
        let (beat, sub) = (peak(&s[..1500]), peak(&s[12_000..13_500]));
        assert!(beat > 0.5 && (sub / beat - 0.25).abs() < 0.05, "{beat} {sub}");
    }

    #[test]
    fn blocos_de_qualquer_tamanho_dao_o_mesmo_som() {
        // render offline (blocos grandes) igual ao tempo real (blocos pequenos), com todas as opções
        let mut meter = MeterMap::new(4);
        meter.insert(2, 7, 8);
        meter.insert(4, 3, 4);
        let mut tempo = TempoMap::new(RATE, 100.0);
        tempo.insert(6.0, 150.0, true);
        for t in Timbre::ALL {
            for sub in Subdivision::ALL {
                let go = |block: usize| {
                    let mut m = on(0.7);
                    m.set_style(t as u32, sub as u32, 1.3, 2.0, 0.6);
                    run(&mut m, &tempo, &meter, 0.0, 200_000, block)
                };
                let a = go(128);
                assert_eq!(a, go(1000), "{t:?} {sub:?}");
                assert_eq!(a, go(4096), "{t:?} {sub:?}");
                assert!(peak(&a) > 0.05 && a.iter().all(|x| x.is_finite()));
            }
        }
    }

    #[test]
    fn comecar_no_meio_de_uma_subdivisao_nao_perde_clique() {
        let (tempo, meter) = maps(120.0, MeterMap::new(4));
        let mut whole = on(1.0);
        whole.set_style(0, 3, 1.0, 1.6, 0.5);
        let a = run(&mut whole, &tempo, &meter, 0.0, 24_000, 128);
        // 120 bpm, semicolcheias: um clique a cada 6000 quadros; o bloco começa 100 antes do de 6000
        let mut cut = on(1.0);
        cut.set_style(0, 3, 1.0, 1.6, 0.5);
        let b = run(&mut cut, &tempo, &meter, 5900.0, 6200, 100);
        // o primeiro quadro do clique é zero (fase 0), o segundo já passa do limiar
        assert_eq!(onsets(&b).iter().map(|o| o / 10).collect::<Vec<_>>(), vec![10, 610]);
        assert_eq!(&a[6000..6100], &b[100..200]);
    }

    /// O clique de antes das opções, copiado como estava: o que o padrão tem de continuar produzindo.
    fn legacy(l: &mut [f32], pos: f64, tempo: &TempoMap, meter: &MeterMap, rate: f64, gain: f32, st: &mut (usize, f64, f64)) {
        let total = (CLICK_SECS * rate) as usize;
        let end = pos + l.len() as f64;
        let mut click = meter.click_at_or_after(tempo.to_beats(pos) - 1e-6);
        let mut at = loop {
            let f = tempo.to_frames(meter.beat_of(click));
            if f >= pos {
                break f;
            }
            click = meter.next(click);
        };
        let mut next = if at < end { (at - pos) as usize } else { usize::MAX };
        for i in 0..l.len() {
            while i == next {
                st.1 = if meter.is_downbeat(click) { 1600.0 } else { 1000.0 };
                st.0 = total;
                st.2 = 0.0;
                click = meter.next(click);
                at = tempo.to_frames(meter.beat_of(click));
                next = if at < end { ((at - pos) as usize).max(i + 1) } else { usize::MAX };
            }
            if st.0 > 0 {
                let env = (st.0 as f64 / total as f64).powi(3) as f32;
                let s = (st.2 * std::f64::consts::TAU).sin() as f32 * env * gain;
                st.2 += st.1 / rate;
                st.0 -= 1;
                l[i] += s;
            }
        }
    }

    #[test]
    fn opcoes_padrao_dao_exatamente_o_clique_de_antes() {
        let mut meter = MeterMap::new(4);
        meter.insert(3, 6, 8);
        meter.insert(5, 5, 4);
        let mut tempo = TempoMap::new(RATE, 97.0);
        tempo.insert(8.0, 143.0, false);
        tempo.insert(16.0, 90.0, true);
        for gain in [0.5f32, 0.6, 1.0] {
            for explicit in [false, true] {
                let mut new = on(gain);
                if explicit {
                    // as opções explícitas do padrão também não mudam nada
                    new.set_style(0, 0, 1.0, 1.6, 0.5);
                }
                let mut old = (0usize, 1000.0f64, 0.0f64);
                let (mut pos, mut a, mut b) = (0.0, Vec::new(), Vec::new());
                for k in 0..3000 {
                    let n = [64usize, 128, 200, 512][k % 4];
                    let (mut l, mut r) = (vec![0.0f32; n], vec![0.0f32; n]);
                    new.render(&mut l, &mut r, pos, &tempo, &meter, RATE);
                    let mut lo = vec![0.0f32; n];
                    legacy(&mut lo, pos, &tempo, &meter, RATE, gain, &mut old);
                    a.extend_from_slice(&l);
                    b.extend_from_slice(&lo);
                    pos += n as f64;
                }
                assert!(peak(&a) > 0.1);
                assert!(a.iter().zip(&b).all(|(x, y)| x.to_bits() == y.to_bits()), "diferiu com ganho {gain}");
            }
        }
    }

    #[test]
    fn valores_absurdos_sao_limitados() {
        let mut m = on(1.0);
        m.set_style(99, 99, f32::NAN, f32::INFINITY, -5.0);
        assert_eq!((m.timbre(), m.subdivision()), (Timbre::Click, Subdivision::Beat));
        let (tempo, meter) = maps(120.0, MeterMap::new(4));
        let s = run(&mut m, &tempo, &meter, 0.0, 30_000, 128);
        assert!(s.iter().all(|x| x.is_finite() && x.abs() <= 2.0));
        m.set_style(1, 1, 1e9, 1e9, 1e9);
        let s = run(&mut m, &tempo, &meter, 0.0, 30_000, 128);
        assert!(s.iter().all(|x| x.is_finite() && x.abs() <= 6.0));
    }

    #[test]
    fn taxas_e_andamentos_extremos_nao_dao_nan() {
        for rate in [8000.0, 44_100.0, 192_000.0] {
            for bpm in [20.0, 300.0] {
                for t in Timbre::ALL {
                    let mut m = on(1.0);
                    m.set_style(t as u32, 3, 1.0, 4.0, 1.0);
                    let tempo = TempoMap::new(rate, bpm);
                    let meter = MeterMap::new(4);
                    let (mut l, mut r) = (vec![0.0; 512], vec![0.0; 512]);
                    for k in 0..200 {
                        m.render(&mut l, &mut r, k as f64 * 512.0, &tempo, &meter, rate);
                        assert!(l.iter().chain(&r).all(|x| x.is_finite()));
                    }
                }
            }
        }
    }
}
