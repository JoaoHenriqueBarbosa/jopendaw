//! Mapa de andamento e mapa de compassos.
//!
//! O documento guarda tudo em BATIDAS (posições de clipes, notas, automação, loop). O mapa de
//! andamento só decide quanto tempo real cada batida dura: uma lista de pontos `{batida, bpm,
//! rampa}` em que o primeiro (sempre na batida 0) é o andamento inicial. Entre um ponto e o
//! próximo o andamento é constante (salto) ou varia linearmente em função da batida (rampa, até o
//! bpm do ponto seguinte). A conversão batida → quadros integra por partes, com a forma fechada da
//! rampa (`t = 60·L/(B−A)·ln(B/A)` para `L` batidas indo de `A` a `B` bpm), e o inverso também é
//! fechado por trecho. Nada aloca no caminho de áudio: a busca do trecho é binária sobre os pontos.
//!
//! Com um ponto só as contas são exatamente as do andamento único de antes (mesmas fórmulas, mesma
//! ordem das operações), então um documento sem mudanças de andamento soa quadro a quadro igual.
//!
//! O mapa de compassos só serve ao metrônomo (onde cai o tempo forte e a cada quanto ele clica):
//! `{compasso, num, den}` com o primeiro sempre no compasso 1. A batida do documento é a semínima,
//! então um compasso `num/den` dura `num·4/den` batidas (6/8 = 3 batidas; 7/8 = 3,5).

pub const MIN_BPM: f64 = 20.0;
pub const MAX_BPM: f64 = 999.0;
/// Pontos de andamento aceitos (o resto é ignorado) e reservados sem realocar.
pub const MAX_TEMPO_POINTS: usize = 4096;
pub const TEMPO_RESERVED: usize = 256;
pub const MAX_METER_POINTS: usize = 1024;
pub const METER_RESERVED: usize = 64;

/// Um ponto do mapa de andamento.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct TempoPoint {
    pub beat: f64,
    pub bpm: f64,
    /// `true`: do ponto ao seguinte o andamento vai em rampa linear até o bpm do seguinte; `false`:
    /// fica em `bpm` e salta no ponto seguinte. No último ponto não há para onde rampar.
    pub ramp: bool,
}

#[derive(Clone, Debug)]
pub struct TempoMap {
    rate: f64,
    pts: Vec<TempoPoint>,
    /// Quadros desde o começo até cada ponto (paralelo a `pts`).
    frames: Vec<f64>,
}

/// A rampa é tratada como reta (sem logaritmo) quando os dois andamentos quase coincidem.
fn flat(a: f64, b: f64) -> bool {
    (b - a).abs() <= 1e-9 * a
}

impl TempoMap {
    pub fn new(rate: f64, bpm: f64) -> Self {
        let mut pts = Vec::with_capacity(TEMPO_RESERVED);
        pts.push(TempoPoint { beat: 0.0, bpm: bpm.clamp(MIN_BPM, MAX_BPM), ramp: false });
        let mut frames = Vec::with_capacity(TEMPO_RESERVED);
        frames.push(0.0);
        Self { rate, pts, frames }
    }

    pub fn points(&self) -> &[TempoPoint] {
        &self.pts
    }

    /// O andamento inicial (o do ponto da batida 0).
    pub fn bpm0(&self) -> f64 {
        self.pts[0].bpm
    }

    /// Só o andamento inicial, sem mudanças.
    pub fn is_single(&self) -> bool {
        self.pts.len() == 1
    }

    /// Volta a um ponto só, no andamento dado.
    pub fn clear(&mut self, bpm: f64) {
        self.pts.truncate(1);
        self.frames.truncate(1);
        self.pts[0] = TempoPoint { beat: 0.0, bpm: bpm.clamp(MIN_BPM, MAX_BPM), ramp: false };
        self.rebuild();
    }

    /// Muda o andamento do ponto da batida 0.
    pub fn set_bpm0(&mut self, bpm: f64) {
        self.pts[0].bpm = bpm.clamp(MIN_BPM, MAX_BPM);
        self.rebuild();
    }

    /// Põe um ponto. Fora de ordem entra no lugar; na mesma batida de um existente o substitui (o
    /// último a chegar vale); a batida 0 é o andamento inicial; valores não finitos são ignorados,
    /// batidas negativas viram 0 e o bpm fica entre [`MIN_BPM`] e [`MAX_BPM`].
    pub fn insert(&mut self, beat: f64, bpm: f64, ramp: bool) {
        if !beat.is_finite() || !bpm.is_finite() {
            return;
        }
        let p = TempoPoint { beat: beat.max(0.0), bpm: bpm.clamp(MIN_BPM, MAX_BPM), ramp };
        let at = self.pts.partition_point(|q| q.beat < p.beat);
        if at < self.pts.len() && self.pts[at].beat == p.beat {
            self.pts[at] = p;
        } else if self.pts.len() < MAX_TEMPO_POINTS {
            self.pts.insert(at, p);
            self.frames.push(0.0);
        } else {
            return;
        }
        self.rebuild();
    }

    fn rebuild(&mut self) {
        let mut acc = 0.0;
        self.frames[0] = 0.0;
        for i in 1..self.pts.len() {
            acc += self.segment_frames(i - 1, self.pts[i].beat - self.pts[i - 1].beat);
            self.frames[i] = acc;
        }
    }

    /// Quadros que as `x` primeiras batidas do trecho `i` levam.
    fn segment_frames(&self, i: usize, x: f64) -> f64 {
        let p = self.pts[i];
        match self.pts.get(i + 1) {
            Some(q) if p.ramp && !flat(p.bpm, q.bpm) => {
                let len = q.beat - p.beat;
                let (a, b) = (p.bpm, q.bpm);
                self.rate * 60.0 * len / (b - a) * ((a + (b - a) * x / len) / a).ln()
            }
            _ => x * 60.0 / p.bpm * self.rate,
        }
    }

    /// Batida → quadros (fracionário) desde o começo da linha do tempo.
    pub fn to_frames(&self, beat: f64) -> f64 {
        if self.pts.len() == 1 || beat <= 0.0 {
            return beat * 60.0 / self.pts[0].bpm * self.rate;
        }
        let i = self.pts.partition_point(|p| p.beat <= beat) - 1;
        self.frames[i] + self.segment_frames(i, beat - self.pts[i].beat)
    }

    /// Quadros → batida (o inverso de [`TempoMap::to_frames`]).
    pub fn to_beats(&self, frames: f64) -> f64 {
        if self.pts.len() == 1 || frames <= 0.0 {
            return frames / self.rate * self.pts[0].bpm / 60.0;
        }
        let i = self.frames.partition_point(|&f| f <= frames) - 1;
        let p = self.pts[i];
        let secs = (frames - self.frames[i]) / self.rate;
        match self.pts.get(i + 1) {
            Some(q) if p.ramp && !flat(p.bpm, q.bpm) => {
                let len = q.beat - p.beat;
                let (a, b) = (p.bpm, q.bpm);
                let k = (b - a) / (60.0 * len);
                // bpm(x) = a·e^(k·t): x = L·(bpm − a)/(b − a)
                let x = len * a * (k * secs).exp_m1() / (b - a);
                p.beat + x.clamp(0.0, len)
            }
            _ => p.beat + secs * p.bpm / 60.0,
        }
    }

    /// O andamento em bpm na batida (na rampa, o valor interpolado).
    pub fn bpm_at(&self, beat: f64) -> f64 {
        if beat <= 0.0 {
            return self.pts[0].bpm;
        }
        let i = self.pts.partition_point(|p| p.beat <= beat) - 1;
        let p = self.pts[i];
        match self.pts.get(i + 1) {
            Some(q) if p.ramp => p.bpm + (q.bpm - p.bpm) * (beat - p.beat) / (q.beat - p.beat),
            _ => p.bpm,
        }
    }
}

/// Uma mudança de compasso.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct MeterPoint {
    /// Compasso (1 = o primeiro) a partir do qual vale.
    pub bar: u32,
    pub num: u32,
    pub den: u32,
}

impl MeterPoint {
    /// Batidas (semínimas) por tempo do compasso: o passo do metrônomo.
    fn unit(&self) -> f64 {
        4.0 / self.den as f64
    }

    /// Batidas de um compasso inteiro.
    fn bar_beats(&self) -> f64 {
        self.num as f64 * self.unit()
    }
}

/// Um clique do metrônomo: o trecho de compasso e o índice do tempo dentro dele.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Click {
    seg: usize,
    k: u64,
}

#[derive(Clone, Debug)]
pub struct MeterMap {
    pts: Vec<MeterPoint>,
    /// Batida em que começa cada trecho (paralelo a `pts`).
    starts: Vec<f64>,
}

fn valid_den(den: u32) -> u32 {
    if den.is_power_of_two() && den <= 32 { den } else { 4 }
}

impl MeterMap {
    pub fn new(beats_per_bar: u32) -> Self {
        let mut pts = Vec::with_capacity(METER_RESERVED);
        pts.push(MeterPoint { bar: 1, num: beats_per_bar.clamp(1, 32), den: 4 });
        let mut starts = Vec::with_capacity(METER_RESERVED);
        starts.push(0.0);
        Self { pts, starts }
    }

    pub fn points(&self) -> &[MeterPoint] {
        &self.pts
    }

    pub fn is_single(&self) -> bool {
        self.pts.len() == 1
    }

    /// Volta a um compasso só, com `num`/4.
    pub fn clear(&mut self, beats_per_bar: u32) {
        self.pts.truncate(1);
        self.starts.truncate(1);
        self.pts[0] = MeterPoint { bar: 1, num: beats_per_bar.clamp(1, 32), den: 4 };
        self.rebuild();
    }

    /// Muda o compasso inicial (`num`/4) quando não há mapa; com mapa quem manda é o mapa.
    pub fn set_initial(&mut self, beats_per_bar: u32) {
        if self.pts.len() == 1 {
            let bpb = beats_per_bar.clamp(1, 32);
            // o app reenvia o compasso a cada sincronização: um 6/8 ou 7/8 único já tem as mesmas
            // batidas por compasso e não pode virar n/4
            if (self.pts[0].bar_beats() - f64::from(bpb)).abs() < 1e-9 {
                return;
            }
            self.pts[0] = MeterPoint { bar: 1, num: bpb, den: 4 };
            self.rebuild();
        }
    }

    /// Mudança de compasso a partir do compasso `bar` (≥ 1): mesma regra do andamento (ordena, o
    /// último na mesma barra vale). `den` precisa ser potência de 2 até 32 (senão vale 4).
    pub fn insert(&mut self, bar: u32, num: u32, den: u32) {
        let p = MeterPoint { bar: bar.max(1), num: num.clamp(1, 64), den: valid_den(den) };
        let at = self.pts.partition_point(|q| q.bar < p.bar);
        if at < self.pts.len() && self.pts[at].bar == p.bar {
            self.pts[at] = p;
        } else if self.pts.len() < MAX_METER_POINTS {
            self.pts.insert(at, p);
            self.starts.push(0.0);
        } else {
            return;
        }
        self.rebuild();
    }

    fn rebuild(&mut self) {
        self.starts[0] = 0.0;
        for i in 1..self.pts.len() {
            let prev = self.pts[i - 1];
            self.starts[i] = self.starts[i - 1] + (self.pts[i].bar - prev.bar) as f64 * prev.bar_beats();
        }
    }

    /// Batida em que começa o compasso `bar` (1 = o primeiro). Compassos antes do 1 repetem o
    /// primeiro compasso para trás.
    pub fn bar_start(&self, bar: i64) -> f64 {
        let i = self.pts.partition_point(|p| (p.bar as i64) <= bar).max(1) - 1;
        self.starts[i] + (bar - self.pts[i].bar as i64) as f64 * self.pts[i].bar_beats()
    }

    /// Compasso (1 = o primeiro) que contém a batida, e a batida dentro dele (a partir de 0).
    pub fn bar_of(&self, beat: f64) -> (i64, f64) {
        let i = self.starts.partition_point(|&s| s <= beat).max(1) - 1;
        let p = self.pts[i];
        let n = ((beat - self.starts[i]) / p.bar_beats() + 1e-12).floor();
        (p.bar as i64 + n as i64, beat - self.starts[i] - n * p.bar_beats())
    }

    /// O primeiro clique cuja batida é `beat` ou depois.
    pub fn click_at_or_after(&self, beat: f64) -> Click {
        let seg = self.starts.partition_point(|&s| s <= beat).max(1) - 1;
        let unit = self.pts[seg].unit();
        let mut k = ((beat - self.starts[seg]) / unit).ceil().max(0.0) as u64;
        // a divisão pode errar por um ulp: garante o "ou depois"
        while self.starts[seg] + k as f64 * unit < beat {
            k += 1;
        }
        self.normalize(Click { seg, k })
    }

    /// O clique seguinte.
    pub fn next(&self, c: Click) -> Click {
        self.normalize(Click { seg: c.seg, k: c.k + 1 })
    }

    /// Um clique que passa do fim do trecho é o tempo forte do trecho seguinte.
    fn normalize(&self, c: Click) -> Click {
        match self.starts.get(c.seg + 1) {
            Some(&end) if self.starts[c.seg] + c.k as f64 * self.pts[c.seg].unit() >= end - 1e-9 => Click { seg: c.seg + 1, k: 0 },
            _ => c,
        }
    }

    pub fn beat_of(&self, c: Click) -> f64 {
        self.starts[c.seg] + c.k as f64 * self.pts[c.seg].unit()
    }

    /// O clique é o primeiro tempo de um compasso.
    pub fn is_downbeat(&self, c: Click) -> bool {
        c.k.is_multiple_of(self.pts[c.seg].num as u64)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const RATE: f64 = 48_000.0;

    fn map(pts: &[(f64, f64, bool)]) -> TempoMap {
        let mut m = TempoMap::new(RATE, 120.0);
        for &(b, bpm, r) in pts {
            m.insert(b, bpm, r);
        }
        m
    }

    #[test]
    fn single_point_is_the_old_formula() {
        let m = TempoMap::new(RATE, 137.0);
        for b in [0.0, 0.25, 1.0, 7.5, 1234.567, -3.0] {
            assert_eq!(m.to_frames(b), b * 60.0 / 137.0 * RATE);
        }
        for f in [0.0, 1.0, 999.5, 1e7, -20.0] {
            assert_eq!(m.to_beats(f), f / RATE * 137.0 / 60.0);
        }
    }

    #[test]
    fn ramp_duration_is_the_exact_integral() {
        // 60 -> 120 em 4 batidas: t = 60·4/60·ln 2 = 4·ln 2 s
        let m = map(&[(0.0, 60.0, true), (4.0, 120.0, false)]);
        let want = 4.0 * std::f64::consts::LN_2 * RATE;
        assert!((m.to_frames(4.0) - want).abs() < 1e-6, "{} vs {want}", m.to_frames(4.0));
        // depois da rampa, 120 bpm constante: 0,5 s por batida
        assert!((m.to_frames(6.0) - (want + 2.0 * 0.5 * RATE)).abs() < 1e-6);
        // integração numérica (regra do ponto médio) confere
        let n = 200_000;
        let mut t = 0.0;
        for i in 0..n {
            let x = (i as f64 + 0.5) / n as f64 * 4.0;
            t += 60.0 / (60.0 + 60.0 * x / 4.0) * (4.0 / n as f64);
        }
        assert!((t * RATE - want).abs() < 1e-3);
    }

    #[test]
    fn jump_is_piecewise_constant() {
        let m = map(&[(4.0, 60.0, false), (8.0, 240.0, false)]);
        assert_eq!(m.to_frames(4.0), 4.0 * 0.5 * RATE);
        assert_eq!(m.to_frames(8.0), 4.0 * 0.5 * RATE + 4.0 * RATE);
        assert_eq!(m.to_frames(10.0), 4.0 * 0.5 * RATE + 4.0 * RATE + 2.0 * 0.25 * RATE);
        assert_eq!(m.bpm_at(3.9), 120.0);
        assert_eq!(m.bpm_at(4.0), 60.0);
        assert_eq!(m.bpm_at(100.0), 240.0);
    }

    #[test]
    fn roundtrip_everywhere() {
        let m = map(&[(2.0, 60.0, true), (6.0, 200.0, true), (10.0, 20.0, false), (11.0, 400.0, true), (30.0, 999.0, false)]);
        let mut b = 0.0;
        while b < 40.0 {
            let back = m.to_beats(m.to_frames(b));
            assert!((back - b).abs() < 1e-9, "beat {b} voltou {back}");
            b += 0.037;
        }
        // monotonia em quadros
        let mut prev = -1.0;
        for f in (0..2_000_000).step_by(997) {
            let beat = m.to_beats(f as f64);
            assert!(beat > prev);
            prev = beat;
        }
    }

    #[test]
    fn many_points() {
        let mut m = TempoMap::new(RATE, 100.0);
        for i in 1..=256 {
            m.insert(i as f64 * 2.0, 60.0 + (i % 7) as f64 * 20.0, i % 2 == 0);
        }
        assert_eq!(m.points().len(), 257);
        for i in 0..=256 {
            let b = i as f64 * 2.0;
            assert!((m.to_beats(m.to_frames(b + 0.5)) - (b + 0.5)).abs() < 1e-8);
        }
    }

    #[test]
    fn duplicates_and_disorder() {
        let mut m = TempoMap::new(RATE, 120.0);
        m.insert(8.0, 90.0, false);
        m.insert(4.0, 60.0, false);
        m.insert(8.0, 100.0, true); // duplicado: o último vale
        m.insert(0.0, 80.0, false); // o ponto 0 é o andamento inicial
        m.insert(-5.0, 70.0, false); // negativo vira 0
        m.insert(f64::NAN, 70.0, false);
        m.insert(3.0, f64::INFINITY, false);
        m.insert(2.0, 5000.0, false); // limite
        let pts = m.points();
        assert_eq!(pts.iter().map(|p| p.beat).collect::<Vec<_>>(), [0.0, 2.0, 4.0, 8.0]);
        assert_eq!(pts[0].bpm, 70.0);
        assert_eq!(pts[1].bpm, MAX_BPM);
        assert_eq!(pts[3], TempoPoint { beat: 8.0, bpm: 100.0, ramp: true });
        // ramp no último ponto não faz nada além dele
        assert_eq!(m.to_frames(10.0) - m.to_frames(8.0), 2.0 * 60.0 / 100.0 * RATE);
    }

    #[test]
    fn extremes() {
        for bpm in [20.0, 400.0] {
            let m = map(&[(0.0, bpm, false), (16.0, bpm * 2.0, true), (32.0, bpm, false)]);
            let f = m.to_frames(20.0);
            assert!((m.to_beats(f) - 20.0).abs() < 1e-9);
        }
        // rampa 20 -> 400
        let m = map(&[(0.0, 20.0, true), (8.0, 400.0, false)]);
        let want = 60.0 * 8.0 / 380.0 * (400.0f64 / 20.0).ln() * RATE;
        assert!((m.to_frames(8.0) - want).abs() < 1e-6);
        assert!((m.to_beats(want) - 8.0).abs() < 1e-9);
    }

    #[test]
    fn flat_ramp_is_linear() {
        let m = map(&[(0.0, 100.0, true), (4.0, 100.0, false)]);
        assert!((m.to_frames(4.0) - 4.0 * 0.6 * RATE).abs() < 1e-9);
    }

    #[test]
    fn meter_bars() {
        let mut mm = MeterMap::new(4);
        assert_eq!(mm.bar_start(1), 0.0);
        assert_eq!(mm.bar_start(3), 8.0);
        mm.insert(3, 3, 4); // a partir do compasso 3: 3/4
        mm.insert(5, 6, 8); // a partir do 5: 6/8 = 3 batidas
        mm.insert(7, 7, 8); // 7/8 = 3,5 batidas
        assert_eq!(mm.bar_start(3), 8.0);
        assert_eq!(mm.bar_start(5), 14.0);
        assert_eq!(mm.bar_start(7), 20.0);
        assert_eq!(mm.bar_start(9), 27.0);
        assert_eq!(mm.bar_of(0.0), (1, 0.0));
        assert_eq!(mm.bar_of(7.999).0, 2);
        assert_eq!(mm.bar_of(8.0), (3, 0.0));
        assert_eq!(mm.bar_of(20.0), (7, 0.0));
        assert_eq!(mm.bar_of(23.5), (8, 0.0));
    }

    #[test]
    fn meter_clicks() {
        let mut mm = MeterMap::new(4);
        mm.insert(2, 3, 4);
        // 4/4 no compasso 1 (batidas 0..4), depois 3/4
        let mut c = mm.click_at_or_after(0.0);
        let mut got = Vec::new();
        for _ in 0..8 {
            got.push((mm.beat_of(c), mm.is_downbeat(c)));
            c = mm.next(c);
        }
        let want = [(0.0, true), (1.0, false), (2.0, false), (3.0, false), (4.0, true), (5.0, false), (6.0, false), (7.0, true)];
        assert_eq!(got, want);
        assert_eq!(mm.beat_of(mm.click_at_or_after(4.5)), 5.0);
        // 6/8: um clique a cada colcheia (meia batida)
        let mut m8 = MeterMap::new(4);
        m8.insert(1, 6, 8);
        let c = m8.click_at_or_after(0.4);
        assert_eq!(m8.beat_of(c), 0.5);
        assert!(!m8.is_downbeat(c));
        let c = m8.click_at_or_after(3.0);
        assert_eq!(m8.beat_of(c), 3.0);
        assert!(m8.is_downbeat(c));
    }
}

#[cfg(test)]
mod meter_tests {
    use super::*;

    #[test]
    fn compasso_unico_6_8_sobrevive_ao_tempo_reenviado_a_cada_sincronizacao() {
        // o app manda `tempo` de novo a cada sincronização; o compasso único 6/8 (3 semínimas) não
        // pode voltar a 3/4 e mudar o passo do metrônomo
        let mut mapa = MeterMap::new(4);
        mapa.insert(1, 6, 8);
        let antes = (mapa.pts[0].num, mapa.pts[0].den);
        mapa.set_initial(3);
        assert_eq!((mapa.pts[0].num, mapa.pts[0].den), antes, "6/8 continua 6/8");
        // já um compasso diferente troca, como sempre
        mapa.set_initial(5);
        assert_eq!((mapa.pts[0].num, mapa.pts[0].den), (5, 4));
    }
}
