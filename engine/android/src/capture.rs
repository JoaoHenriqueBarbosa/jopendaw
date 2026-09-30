//! O áudio capturado da entrada: um anel pré-alocado (~60 s) que a thread de áudio enche enquanto
//! grava e o Dart esvazia por `jd_recorded`.
//!
//! Cada pedaço escrito (um bloco do callback) leva uma marca com a batida do primeiro quadro, as
//! batidas por quadro e a época da captura; a marca entra na fila antes dos quadros, então todo
//! quadro visível já tem a sua. Um pedaço que não continua o anterior no tempo do transporte (um
//! salto de posição, uma parada, quadros perdidos por anel cheio) começa um trecho novo: a leitura
//! nunca junta dois trechos, e cada leitura devolve a batida do seu primeiro quadro. A volta do
//! loop acontece dentro do `process` e não quebra o trecho (como no worklet: os quadros seguem
//! contínuos e o controlador sabe onde o loop volta).
//!
//! A época separa as capturas: o Dart liga uma captura nova antes de a thread de áudio saber
//! (os comandos vão pela fila), e o que sobrou da anterior no anel é descartado na leitura.

use std::collections::VecDeque;

use rtrb::{Consumer, Producer, RingBuffer};

/// Diferença de posição entre um pedaço e o seguinte que conta como salto e não como
/// arredondamento (a do worklet): um milionésimo de batida é bem menos que um quadro.
const BEAT_EPS: f64 = 1e-6;

/// Segundos que o anel guarda: folga para o Dart atrasar (coleta de lixo, app em segundo plano)
/// sem perder áudio.
pub const RING_SECS: f64 = 60.0;

/// Menor pedaço esperado (quadros) para dimensionar a fila de marcas.
const MIN_CHUNK: usize = 32;

#[derive(Clone, Copy, Debug)]
struct Marker {
    /// Posição (em quadros, contada desde a criação do anel) do primeiro quadro do pedaço.
    start: u64,
    beat: f64,
    /// Batidas por quadro no andamento do pedaço.
    bpf: f64,
    epoch: u32,
    /// Começa um trecho (não continua o pedaço anterior).
    fresh: bool,
}

/// Cria o anel para `frames` quadros estéreo.
pub fn rec_ring(frames: usize) -> (RecWriter, RecReader) {
    let frames = frames.max(1024);
    let (fp, fc) = RingBuffer::<[f32; 2]>::new(frames);
    let (mp, mc) = RingBuffer::<Marker>::new(frames / MIN_CHUNK + 16);
    (
        RecWriter { frames: fp, marks: mp, written: 0, open: false, next_beat: f64::NAN, epoch: 0, dropped: 0 },
        RecReader { frames: fc, marks: mc, pending: VecDeque::with_capacity(1024), read: 0, epoch: 0 },
    )
}

/// O lado da thread de áudio. Nada aqui aloca.
pub struct RecWriter {
    frames: Producer<[f32; 2]>,
    marks: Producer<Marker>,
    written: u64,
    /// Há um trecho aberto (o próximo pedaço pode continuá-lo).
    open: bool,
    /// Batida esperada no começo do próximo pedaço para continuar o trecho.
    next_beat: f64,
    epoch: u32,
    /// Quadros perdidos por anel cheio, desde o começo.
    pub dropped: u64,
}

impl RecWriter {
    /// Começa a captura `epoch`: o próximo pedaço abre um trecho.
    pub fn begin(&mut self, epoch: u32) {
        self.epoch = epoch;
        self.open = false;
    }

    /// Fecha o trecho (parada, fim da captura): o próximo pedaço começa outro.
    pub fn close(&mut self) {
        self.open = false;
    }

    /// Escreve um pedaço: `beat` é a posição do primeiro quadro, `after` a do quadro seguinte ao
    /// último (a do transporte depois do `process`), `bpf` as batidas por quadro.
    pub fn write(&mut self, l: &[f32], r: &[f32], beat: f64, after: f64, bpf: f64) {
        let n = l.len().min(r.len());
        if n == 0 {
            return;
        }
        let fresh = !self.open || (beat - self.next_beat).abs() > BEAT_EPS;
        if self.frames.slots() < n || self.marks.slots() == 0 {
            // anel cheio (o Dart parou de ler): perde o pedaço, e o seguinte abre um trecho novo
            // na posição certa em vez de colar áudio fora do lugar
            self.dropped += n as u64;
            self.open = false;
            return;
        }
        let _ = self.marks.push(Marker { start: self.written, beat, bpf, epoch: self.epoch, fresh });
        if let Ok(mut chunk) = self.frames.write_chunk(n) {
            let (a, b) = chunk.as_mut_slices();
            for (i, f) in a.iter_mut().chain(b.iter_mut()).enumerate() {
                *f = [l[i], r[i]];
            }
            chunk.commit_all();
        }
        self.written += n as u64;
        self.open = true;
        self.next_beat = after;
    }
}

/// O lado do Dart.
pub struct RecReader {
    frames: Consumer<[f32; 2]>,
    marks: Consumer<Marker>,
    /// Marcas já tiradas da fila; a primeira cobre o próximo quadro a ler.
    pending: VecDeque<Marker>,
    read: u64,
    epoch: u32,
}

impl RecReader {
    /// A captura `epoch` começou: o que sobrou de outras épocas é descartado na leitura.
    pub fn begin(&mut self, epoch: u32) {
        self.epoch = epoch;
    }

    /// Lê em `l`/`r` os quadros seguintes do trecho atual da captura em andamento; devolve
    /// quantos leu e a batida do primeiro. Quadros de um trecho só: um salto no meio fica para a
    /// próxima leitura. Sem nada para ler, `(0, 0.0)`.
    pub fn read(&mut self, l: &mut [f32], r: &mut [f32]) -> (usize, f64) {
        let max = l.len().min(r.len());
        while let Ok(m) = self.marks.pop() {
            self.pending.push_back(m);
        }
        loop {
            let avail = self.frames.slots();
            if avail == 0 || max == 0 {
                return (0, 0.0);
            }
            // a marca que cobre o próximo quadro: a última com início até ele
            while self.pending.len() >= 2 && self.pending[1].start <= self.read {
                self.pending.pop_front();
            }
            let Some(&cur) = self.pending.front() else { return (0, 0.0) };
            let end_avail = self.read + avail as u64;
            if cur.epoch != self.epoch {
                // de outra captura: descarta até a próxima marca (ou tudo o que já chegou)
                let end = self.pending.get(1).map_or(end_avail, |m| m.start).min(end_avail);
                let skip = (end - self.read) as usize;
                if let Ok(chunk) = self.frames.read_chunk(skip) {
                    chunk.commit_all();
                }
                self.read = end;
                if self.pending.len() < 2 {
                    // sem mais marcas: o resto do pedaço ainda pode estar chegando
                    return (0, 0.0);
                }
                continue;
            }
            // até o próximo começo de trecho (ou de outra época)
            let mut end = end_avail;
            for m in self.pending.iter().skip(1) {
                if m.fresh || m.epoch != self.epoch {
                    end = end.min(m.start);
                    break;
                }
            }
            let n = ((end - self.read) as usize).min(max);
            if n == 0 {
                return (0, 0.0);
            }
            let beat = cur.beat + (self.read - cur.start) as f64 * cur.bpf;
            if let Ok(chunk) = self.frames.read_chunk(n) {
                let (a, b) = chunk.as_slices();
                for (i, f) in a.iter().chain(b.iter()).enumerate() {
                    l[i] = f[0];
                    r[i] = f[1];
                }
                chunk.commit_all();
            }
            self.read += n as u64;
            return (n, beat);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ramp(from: usize, n: usize) -> (Vec<f32>, Vec<f32>) {
        ((from..from + n).map(|i| i as f32).collect(), (from..from + n).map(|i| -(i as f32)).collect())
    }

    #[test]
    fn contiguous_chunks_read_as_one_run_with_the_first_beat() {
        let (mut w, mut r) = rec_ring(4096);
        w.begin(1);
        r.begin(1);
        let bpf = 0.001;
        let (l, rr) = ramp(0, 100);
        w.write(&l, &rr, 2.0, 2.1, bpf);
        let (l, rr) = ramp(100, 100);
        w.write(&l, &rr, 2.1, 2.2, bpf);
        let (mut ol, mut or) = (vec![0.0; 1000], vec![0.0; 1000]);
        let (n, beat) = r.read(&mut ol, &mut or);
        assert_eq!(n, 200);
        assert_eq!(beat, 2.0);
        assert_eq!(ol[150], 150.0);
        assert_eq!(or[150], -150.0);
        assert_eq!(r.read(&mut ol, &mut or).0, 0);
    }

    #[test]
    fn a_jump_starts_a_new_run_and_partial_reads_interpolate_the_beat() {
        let (mut w, mut r) = rec_ring(4096);
        w.begin(1);
        r.begin(1);
        let (l, rr) = ramp(0, 100);
        w.write(&l, &rr, 0.0, 0.1, 0.001);
        // salto (seek): começa outro trecho
        let (l, rr) = ramp(100, 100);
        w.write(&l, &rr, 8.0, 8.1, 0.001);
        let (mut ol, mut or) = (vec![0.0; 60], vec![0.0; 60]);
        assert_eq!(r.read(&mut ol, &mut or), (60, 0.0));
        let (n, beat) = r.read(&mut ol, &mut or);
        assert_eq!(n, 40);
        assert!((beat - 0.06).abs() < 1e-12);
        assert_eq!(ol[0], 60.0);
        let (n, beat) = r.read(&mut ol, &mut or);
        assert_eq!((n, beat), (60, 8.0));
        assert_eq!(ol[0], 100.0);
        // depois de um close, mesmo na posição esperada, começa outro trecho
        w.close();
        let (l, rr) = ramp(200, 10);
        w.write(&l, &rr, 8.1, 8.11, 0.001);
        let (n, _) = r.read(&mut ol, &mut or);
        assert_eq!(n, 40);
        assert_eq!(r.read(&mut ol, &mut or), (10, 8.1));
    }

    #[test]
    fn leftovers_of_an_old_capture_are_discarded() {
        let (mut w, mut r) = rec_ring(4096);
        w.begin(1);
        r.begin(1);
        let (l, rr) = ramp(0, 50);
        w.write(&l, &rr, 0.0, 0.05, 0.001);
        // o Dart liga a captura 2 antes da thread de áudio saber: ainda chega áudio da 1
        r.begin(2);
        w.write(&l, &rr, 0.05, 0.1, 0.001);
        w.begin(2);
        let (l2, r2) = ramp(1000, 30);
        w.write(&l2, &r2, 4.0, 4.03, 0.001);
        let (mut ol, mut or) = (vec![0.0; 500], vec![0.0; 500]);
        let (n, beat) = r.read(&mut ol, &mut or);
        assert_eq!((n, beat), (30, 4.0));
        assert_eq!(ol[0], 1000.0);
        assert_eq!(r.read(&mut ol, &mut or).0, 0);
    }

    #[test]
    fn a_full_ring_drops_the_chunk_and_resumes_in_place() {
        let (mut w, mut r) = rec_ring(1024);
        w.begin(1);
        r.begin(1);
        let (l, rr) = ramp(0, 600);
        w.write(&l, &rr, 0.0, 0.6, 0.001);
        // não cabe: perdido
        w.write(&l, &rr, 0.6, 1.2, 0.001);
        assert_eq!(w.dropped, 600);
        let (mut ol, mut or) = (vec![0.0; 2000], vec![0.0; 2000]);
        assert_eq!(r.read(&mut ol, &mut or), (600, 0.0));
        // o próximo pedaço vem na posição certa, num trecho novo
        let (l, rr) = ramp(0, 100);
        w.write(&l, &rr, 1.2, 1.3, 0.001);
        assert_eq!(r.read(&mut ol, &mut or), (100, 1.2));
    }
}
