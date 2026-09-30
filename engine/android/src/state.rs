//! O estado que a thread de áudio publica e o Dart lê por polling (~60 Hz), sem trava.
//!
//! - Posição, tocando, indicador do efeito e número de faixas: um buffer triplo (o leitor sempre
//!   pega o último retrato inteiro, o escritor nunca espera).
//! - Espectro: outro buffer triplo, publicado ~30 vezes por segundo só com o analisador ligado.
//! - Picos: um atômico por valor, com "máximo desde a última leitura" exato: a thread de áudio
//!   sobe com `fetch_max` e o leitor zera com `swap`. Com os bits de um f32 não negativo a ordem
//!   dos inteiros é a dos valores, então o máximo atômico de inteiros serve.

use std::sync::Arc;
use std::sync::atomic::{AtomicBool, AtomicU32, AtomicU64, Ordering};

use triple_buffer::{Input, Output, triple_buffer};

/// Faixas com pico publicado (o `MAX_PEAKS` do worklet: 2 × 257 com o master).
pub const MAX_PEAK_TRACKS: usize = 256;
pub const MAX_PEAKS: usize = 2 * (MAX_PEAK_TRACKS + 1);

/// Faixas do espectro, como o worklet pede ao `analyzer` do wasm (FFT de 2048 pontos).
pub const SPECTRUM_BINS: usize = 1024;

/// Valores de `jd_state` antes dos picos: batida, tocando, indicador, quantos picos.
pub const STATE_HEADER: usize = 4;

/// Retrato do transporte.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Snapshot {
    pub beat: f64,
    pub playing: bool,
    pub fx_meter: f32,
    /// Picos publicados: 2 por faixa (até [`MAX_PEAK_TRACKS`]) e 2 do master.
    pub peaks: u32,
}

/// Espectro da faixa observada; `bins` 0 = nada observado.
#[derive(Clone)]
pub struct Spectrum {
    pub bins: usize,
    pub db: [f32; SPECTRUM_BINS],
}

impl Default for Spectrum {
    fn default() -> Self {
        Self { bins: 0, db: [-120.0; SPECTRUM_BINS] }
    }
}

/// Os medidores de "máximo desde a última leitura".
pub struct Meters {
    peaks: [AtomicU32; MAX_PEAKS],
    input: AtomicU32,
    /// A entrada caiu (a thread de áudio viu a desconexão); o host tenta reabrir antes de contar
    /// ao Dart.
    input_dropped: AtomicBool,
    /// A entrada caiu e não voltou; o Dart fica sabendo uma vez (`jd_input_level` −1).
    input_lost: AtomicBool,
    /// A thread de áudio entrou em pânico: o motor ficou em estado desconhecido e só sai silêncio.
    broken: AtomicBool,
    /// Loudness do master (momentâneo, curto prazo, integrado, true peak, faixa: os `kind` do motor),
    /// como os bits de um f64; a thread de áudio publica a cada bloco e o Dart lê quando quiser.
    loudness: [AtomicU64; LOUDNESS_KINDS],
    /// Latência do motor em quadros (`Engine::latency_frames`), como os bits de um f64.
    latency: AtomicU64,
}

/// Medidas de loudness publicadas.
pub const LOUDNESS_KINDS: usize = 5;

fn raise(a: &AtomicU32, v: f32) {
    // NaN e negativos não sobem nada; infinito sobe (bits maiores que qualquer finito)
    if v > 0.0 {
        a.fetch_max(v.to_bits(), Ordering::Relaxed);
    }
}

fn take(a: &AtomicU32) -> f32 {
    f32::from_bits(a.swap(0, Ordering::Relaxed))
}

impl Meters {
    pub fn new() -> Self {
        Self {
            peaks: std::array::from_fn(|_| AtomicU32::new(0)),
            input: AtomicU32::new(0),
            input_dropped: AtomicBool::new(false),
            input_lost: AtomicBool::new(false),
            broken: AtomicBool::new(false),
            loudness: std::array::from_fn(|_| AtomicU64::new(jopendaw_engine::loudness::NONE.to_bits())),
            latency: AtomicU64::new(0.0f64.to_bits()),
        }
    }

    pub fn raise_peak(&self, i: usize, v: f32) {
        if let Some(a) = self.peaks.get(i) {
            raise(a, v);
        }
    }

    pub fn take_peak(&self, i: usize) -> f32 {
        self.peaks.get(i).map_or(0.0, take)
    }

    pub fn raise_input(&self, v: f32) {
        raise(&self.input, v);
    }

    pub fn take_input(&self) -> f32 {
        take(&self.input)
    }

    pub fn set_input_dropped(&self) {
        self.input_dropped.store(true, Ordering::Release);
    }

    pub fn take_input_dropped(&self) -> bool {
        self.input_dropped.swap(false, Ordering::AcqRel)
    }

    pub fn set_input_lost(&self) {
        self.input_lost.store(true, Ordering::Release);
    }

    pub fn take_input_lost(&self) -> bool {
        self.input_lost.swap(false, Ordering::AcqRel)
    }

    pub fn set_loudness(&self, kind: usize, v: f64) {
        if let Some(a) = self.loudness.get(kind) {
            a.store(v.to_bits(), Ordering::Relaxed);
        }
    }

    /// A última medida publicada; −200 (sem medida) para um tipo que não existe.
    pub fn loudness(&self, kind: usize) -> f64 {
        self.loudness.get(kind).map_or(jopendaw_engine::loudness::NONE, |a| f64::from_bits(a.load(Ordering::Relaxed)))
    }

    pub fn set_latency(&self, frames: f64) {
        self.latency.store(frames.to_bits(), Ordering::Relaxed);
    }

    /// A última latência do motor publicada, em quadros (0 antes da primeira).
    pub fn latency(&self) -> f64 {
        f64::from_bits(self.latency.load(Ordering::Relaxed))
    }

    pub fn set_broken(&self) {
        self.broken.store(true, Ordering::Release);
    }

    pub fn broken(&self) -> bool {
        self.broken.load(Ordering::Acquire)
    }
}

impl Default for Meters {
    fn default() -> Self {
        Self::new()
    }
}

/// O lado da thread de áudio.
pub struct StateWriter {
    snapshot: Input<Snapshot>,
    spectrum: Input<Spectrum>,
    pub meters: Arc<Meters>,
}

/// O lado do Dart.
pub struct StateReader {
    snapshot: Output<Snapshot>,
    spectrum: Output<Spectrum>,
    pub meters: Arc<Meters>,
}

pub fn state() -> (StateWriter, StateReader) {
    let (si, so) = triple_buffer(&Snapshot { peaks: 2, ..Snapshot::default() });
    let (pi, po) = triple_buffer(&Spectrum::default());
    let meters = Arc::new(Meters::new());
    (StateWriter { snapshot: si, spectrum: pi, meters: meters.clone() }, StateReader { snapshot: so, spectrum: po, meters })
}

impl StateWriter {
    pub fn publish(&mut self, s: Snapshot) {
        self.snapshot.write(s);
    }

    /// Escreve o espectro no lugar (`fill` devolve quantas faixas escreveu) e publica.
    pub fn publish_spectrum(&mut self, fill: impl FnOnce(&mut [f32; SPECTRUM_BINS]) -> usize) {
        let buf = self.spectrum.input_buffer_mut();
        buf.bins = fill(&mut buf.db).min(SPECTRUM_BINS);
        self.spectrum.publish();
    }
}

impl StateReader {
    pub fn snapshot(&mut self) -> Snapshot {
        *self.snapshot.read()
    }

    /// Copia o último espectro em `out`; devolve quantas faixas (0 = nada observado).
    pub fn spectrum(&mut self, out: &mut [f32]) -> usize {
        let s = self.spectrum.read();
        let n = s.bins.min(out.len());
        out[..n].copy_from_slice(&s.db[..n]);
        n
    }

    /// Escreve em `out` o formato de `jd_state`: batida, tocando (0/1), indicador do efeito,
    /// quantos picos seguem e os picos (esq, dir de cada faixa e por último o master), zerando os
    /// que leu. Devolve quantos valores escreveu (no máximo `out.len()`).
    pub fn write_state(&mut self, out: &mut [f64]) -> usize {
        let s = self.snapshot();
        if out.len() < STATE_HEADER {
            return 0;
        }
        let peaks = (s.peaks as usize).min(MAX_PEAKS).min(out.len() - STATE_HEADER);
        out[0] = s.beat;
        out[1] = if s.playing { 1.0 } else { 0.0 };
        out[2] = if s.fx_meter.is_finite() { s.fx_meter as f64 } else { 0.0 };
        out[3] = peaks as f64;
        for (i, o) in out[STATE_HEADER..STATE_HEADER + peaks].iter_mut().enumerate() {
            *o = self.meters.take_peak(i) as f64;
        }
        STATE_HEADER + peaks
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn peaks_keep_the_maximum_until_read() {
        let m = Meters::new();
        m.raise_peak(0, 0.25);
        m.raise_peak(0, 0.75);
        m.raise_peak(0, 0.5);
        m.raise_peak(1, f32::NAN);
        m.raise_peak(1, -3.0);
        m.raise_peak(MAX_PEAKS, 1.0);
        assert_eq!(m.take_peak(0), 0.75);
        assert_eq!(m.take_peak(0), 0.0);
        assert_eq!(m.take_peak(1), 0.0);
        m.raise_input(0.1);
        m.raise_input(0.3);
        assert_eq!(m.take_input(), 0.3);
        assert_eq!(m.take_input(), 0.0);
    }

    #[test]
    fn state_round_trips_in_the_jd_state_layout() {
        let (mut w, mut r) = state();
        w.publish(Snapshot { beat: 12.5, playing: true, fx_meter: -3.0, peaks: 4 });
        w.meters.raise_peak(0, 0.1);
        w.meters.raise_peak(1, 0.2);
        w.meters.raise_peak(2, 0.3);
        w.meters.raise_peak(3, 0.4);
        let mut out = [9.0f64; 16];
        assert_eq!(r.write_state(&mut out), 8);
        assert_eq!(out[..4], [12.5, 1.0, -3.0, 4.0]);
        assert!((out[4] - 0.1).abs() < 1e-7 && (out[7] - 0.4).abs() < 1e-7);
        // lidos: zerados; o retrato continua o mesmo
        assert_eq!(r.write_state(&mut out), 8);
        assert_eq!(out[4..8], [0.0; 4]);
        assert_eq!(out[0], 12.5);
        // espaço curto: só os picos que cabem (e os outros continuam guardados)
        w.meters.raise_peak(3, 0.9);
        let mut short = [0.0f64; 6];
        assert_eq!(r.write_state(&mut short), 6);
        assert_eq!(short[3], 2.0);
        assert!((r.meters.take_peak(3) - 0.9).abs() < 1e-7);
        assert_eq!(r.write_state(&mut [0.0; 3]), 0);
    }

    #[test]
    fn loudness_is_published_per_kind() {
        let m = Meters::new();
        assert_eq!(m.loudness(2), -200.0);
        m.set_loudness(2, -14.5);
        m.set_loudness(9, 1.0);
        assert_eq!((m.loudness(2), m.loudness(9)), (-14.5, -200.0));
    }

    #[test]
    fn spectrum_is_published_whole() {
        let (mut w, mut r) = state();
        let mut out = [0.0f32; SPECTRUM_BINS];
        assert_eq!(r.spectrum(&mut out), 0);
        w.publish_spectrum(|db| {
            for (i, d) in db.iter_mut().enumerate() {
                *d = -(i as f32);
            }
            SPECTRUM_BINS
        });
        assert_eq!(r.spectrum(&mut out), SPECTRUM_BINS);
        assert_eq!(out[10], -10.0);
        let mut small = [0.0f32; 8];
        assert_eq!(r.spectrum(&mut small), 8);
        w.publish_spectrum(|_| 0);
        assert_eq!(r.spectrum(&mut out), 0);
    }
}
