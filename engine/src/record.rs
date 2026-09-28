//! Gravação e render: o registro das notas tocadas ao vivo e as capturas das saídas.
//!
//! O registro guarda as notas ao vivo (teclado, MIDI) com a batida em que o motor as aplicou, para
//! o app transformar a passada num clipe de notas. As capturas copiam, bloco a bloco, a saída
//! pós-fader de uma faixa ou a do master (depois do limitador) para o render fora de tempo real
//! (exportação, stems, congelar faixa) ler depois de cada `process`.
//!
//! Nada aqui aloca no caminho de áudio: o registro nasce com espaço para [`MAX_REC_NOTES`] notas e
//! cada captura ganha os buffers dela uma vez, no comando que a cria, e os reaproveita depois.

use crate::MAX_BLOCK;
use crate::mixer::Stereo;

/// Notas que o registro guarda. Passar disso descarta as novas: o registro não pode crescer na
/// thread de áudio, e 16 mil notas são horas de execução contínua.
pub const MAX_REC_NOTES: usize = 16_384;

/// Floats por nota na leitura do registro: faixa, altura, início, fim (batidas) e velocidade.
pub const REC_NOTE_FLOATS: usize = 5;

/// Capturas simultâneas (a mixagem e um stem por faixa, com folga).
pub const MAX_CAPTURES: usize = 64;

/// Uma nota tocada ao vivo durante a gravação.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct RecNote {
    pub track: u32,
    pub pitch: u8,
    /// Batidas absolutas da linha do tempo.
    pub start: f64,
    /// NaN enquanto a tecla está segurada.
    pub end: f64,
    pub velocity: f32,
}

impl RecNote {
    fn held(&self) -> bool {
        self.end.is_nan()
    }
}

/// O registro das notas ao vivo. Quem decide se o transporte está tocando é o motor: aqui só se
/// guarda o que ele manda.
pub struct NoteRecorder {
    on: bool,
    notes: Vec<RecNote>,
    /// Notas descartadas por falta de espaço desde o último início.
    dropped: usize,
}

impl Default for NoteRecorder {
    fn default() -> Self {
        Self::new()
    }
}

impl NoteRecorder {
    pub fn new() -> Self {
        Self { on: false, notes: Vec::with_capacity(MAX_REC_NOTES), dropped: 0 }
    }

    pub fn recording(&self) -> bool {
        self.on
    }

    /// Começa uma gravação do zero: o que sobrou de uma anterior não lida não se mistura com ela.
    pub fn start(&mut self) {
        self.notes.clear();
        self.dropped = 0;
        self.on = true;
    }

    /// Para de registrar; as teclas ainda seguradas terminam em `beat`, para a leitura não
    /// depender de onde o transporte estiver quando o app ler.
    pub fn stop(&mut self, beat: f64) {
        self.close_all(beat);
        self.on = false;
    }

    /// Notas descartadas por falta de espaço nesta gravação.
    pub fn dropped(&self) -> usize {
        self.dropped
    }

    /// Notas no registro (fechadas e seguradas).
    pub fn len(&self) -> usize {
        self.notes.len()
    }

    pub fn is_empty(&self) -> bool {
        self.notes.is_empty()
    }

    /// Tecla apertada em `beat`. A mesma tecla de novo sem soltar (reataque, como o instrumento
    /// faz) termina a anterior aqui.
    pub fn note_on(&mut self, track: u32, pitch: u8, velocity: f32, beat: f64) {
        if !self.on {
            return;
        }
        self.note_off(track, pitch, beat);
        self.push(RecNote { track, pitch, start: beat, end: f64::NAN, velocity });
    }

    /// Tecla solta em `beat`. Sem nota aberta daquela tecla (apertada antes de gravar, ou com o
    /// transporte parado) não há o que fechar.
    pub fn note_off(&mut self, track: u32, pitch: u8, beat: f64) {
        if !self.on {
            return;
        }
        // de trás para a frente: a aberta é sempre das últimas
        if let Some(n) = self.notes.iter_mut().rev().find(|n| n.held() && n.track == track && n.pitch == pitch) {
            n.end = beat.max(n.start);
        }
    }

    /// Fecha todas as seguradas em `beat` (o transporte parou).
    pub fn close_all(&mut self, beat: f64) {
        for n in self.notes.iter_mut().filter(|n| n.held()) {
            n.end = beat.max(n.start);
        }
    }

    /// O transporte saltou de `from` para `to` (volta do loop, seek tocando) com teclas seguradas:
    /// cada uma termina em `from` e continua, como nota nova, em `to`. É o que se ouve (a nota ao
    /// vivo segue soando) e mantém toda nota com o fim depois do início.
    pub fn jump(&mut self, from: f64, to: f64) {
        if !self.on {
            return;
        }
        let len = self.notes.len();
        for i in 0..len {
            if self.notes[i].held() {
                let n = self.notes[i];
                self.notes[i].end = from.max(n.start);
                self.push(RecNote { start: to, ..n });
            }
        }
    }

    fn push(&mut self, n: RecNote) {
        if self.notes.len() < MAX_REC_NOTES {
            self.notes.push(n);
        } else {
            self.dropped += 1;
        }
    }

    /// Escreve as notas em `out`, em grupos de [`REC_NOTE_FLOATS`] (faixa, altura, início, fim,
    /// velocidade), na ordem em que foram tocadas; as seguradas terminam em `beat`. As escritas
    /// saem do registro; as que não couberam ficam para a próxima leitura (com espaço para todas,
    /// o registro fica vazio). Devolve quantos floats escreveu.
    pub fn drain(&mut self, out: &mut [f32], beat: f64) -> usize {
        let fit = (out.len() / REC_NOTE_FLOATS).min(self.notes.len());
        for (n, o) in self.notes[..fit].iter().zip(out.as_chunks_mut::<REC_NOTE_FLOATS>().0) {
            let end = if n.held() { beat.max(n.start) } else { n.end };
            *o = [n.track as f32, n.pitch as f32, n.start as f32, end as f32, n.velocity];
        }
        // sem alocar: desloca o resto para o começo
        self.notes.drain(..fit);
        fit * REC_NOTE_FLOATS
    }
}

/// Uma saída capturada: a faixa (−1 = master) e o que ela soltou no último bloco.
struct Capture {
    track: i32,
    buf: Stereo,
    /// Atraso que alinha a faixa com o master: o limitador do master devolve o áudio atrasado do
    /// lookahead dele, e o preparo do render adianta o transporte desse tanto; as faixas, que não
    /// passam pelo limitador, esperam aqui o mesmo tanto.
    ring: Stereo,
    ring_at: usize,
    delay: usize,
}

/// As capturas do render. Os índices devolvidos por [`Captures::add`] valem até o próximo
/// [`Captures::clear`].
pub struct Captures {
    slots: Vec<Capture>,
    count: usize,
    /// Quadros do último bloco processado.
    frames: usize,
    /// Capturas mexidas: o próximo `process` prepara o render (transições assentadas, adiantamento
    /// da latência do limitador).
    pub(crate) pending: bool,
    /// No adiantamento: as capturas só enchem o atraso, nada vai para a leitura.
    pub(crate) priming: bool,
}

impl Default for Captures {
    fn default() -> Self {
        Self::new()
    }
}

impl Captures {
    pub fn new() -> Self {
        Self { slots: Vec::with_capacity(MAX_CAPTURES), count: 0, frames: 0, pending: false, priming: false }
    }

    pub fn len(&self) -> usize {
        self.count
    }

    pub fn is_empty(&self) -> bool {
        self.count == 0
    }

    /// Faixa da captura `i` (−1 = master).
    pub fn track(&self, i: usize) -> i32 {
        self.slots[i].track
    }

    pub fn clear(&mut self) {
        self.count = 0;
        self.frames = 0;
        self.pending = true;
    }

    /// Passa a capturar a faixa `track` (−1 = master). Devolve o índice, ou −1 sem lugar ou com
    /// faixa inválida. Os buffers de uma captura nova são alocados aqui, no comando, e reaproveitados
    /// nas próximas; `ring` é o atraso máximo que ela pode precisar (a latência do limitador).
    pub fn add(&mut self, track: i32, ring: usize) -> i32 {
        if track < -1 || self.count == MAX_CAPTURES {
            return -1;
        }
        if self.count == self.slots.len() {
            self.slots.push(Capture { track, buf: Stereo::new(MAX_BLOCK), ring: Stereo::new(ring), ring_at: 0, delay: 0 });
        }
        let c = &mut self.slots[self.count];
        c.track = track;
        c.delay = 0;
        if c.ring.l.len() < ring {
            c.ring = Stereo::new(ring);
        }
        self.count += 1;
        self.pending = true;
        (self.count - 1) as i32
    }

    /// Começo do render: as faixas esperam `delay` quadros (o master já sai atrasado disso pelo
    /// limitador), com o atraso vazio e a leitura zerada.
    pub(crate) fn arm(&mut self, delay: usize) {
        self.frames = 0;
        for c in &mut self.slots[..self.count] {
            c.delay = if c.track >= 0 { delay.min(c.ring.l.len()) } else { 0 };
            c.ring.l.fill(0.0);
            c.ring.r.fill(0.0);
            c.ring_at = 0;
            c.buf.l.fill(0.0);
            c.buf.r.fill(0.0);
        }
    }

    /// Começo de um bloco do hospedeiro de `n` quadros (só os primeiros [`MAX_BLOCK`] são
    /// guardados).
    pub(crate) fn begin_block(&mut self, n: usize) {
        self.frames = n.min(MAX_BLOCK);
    }

    /// Guarda na captura `i` a fatia que começa no quadro `at` do bloco: `src` (esq, dir) ou
    /// silêncio quando `None` (a faixa não soou).
    pub(crate) fn write(&mut self, i: usize, at: usize, n: usize, src: Option<(&[f32], &[f32])>) {
        let priming = self.priming;
        let c = &mut self.slots[i];
        // no adiantamento, o master (sem atraso) não guarda nada
        if priming && c.delay == 0 {
            return;
        }
        let room = if priming { 0 } else { MAX_BLOCK.saturating_sub(at).min(n) };
        if c.delay == 0 {
            match src {
                Some((l, r)) => {
                    c.buf.l[at..at + room].copy_from_slice(&l[..room]);
                    c.buf.r[at..at + room].copy_from_slice(&r[..room]);
                }
                None => {
                    c.buf.l[at..at + room].fill(0.0);
                    c.buf.r[at..at + room].fill(0.0);
                }
            }
            return;
        }
        for k in 0..n {
            let (a, b) = src.map_or((0.0, 0.0), |(l, r)| (l[k], r[k]));
            let p = c.ring_at;
            let (da, db) = (c.ring.l[p], c.ring.r[p]);
            c.ring.l[p] = a;
            c.ring.r[p] = b;
            c.ring_at = if p + 1 == c.delay { 0 } else { p + 1 };
            if k < room {
                c.buf.l[at + k] = da;
                c.buf.r[at + k] = db;
            }
        }
    }

    /// Copia a captura `i` do último bloco para `l`/`r`; o que passar do bloco (ou índice
    /// inválido) sai zerado. Devolve quantos quadros do bloco couberam em `l`.
    pub fn read(&self, i: usize, l: &mut [f32], r: &mut [f32]) -> usize {
        let Some(c) = self.slots[..self.count].get(i) else {
            l.fill(0.0);
            r.fill(0.0);
            return 0;
        };
        let nl = l.len().min(self.frames);
        let nr = r.len().min(self.frames);
        l[..nl].copy_from_slice(&c.buf.l[..nl]);
        r[..nr].copy_from_slice(&c.buf.r[..nr]);
        l[nl..].fill(0.0);
        r[nr..].fill(0.0);
        nl
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn read_all(r: &mut NoteRecorder, beat: f64) -> Vec<[f32; 5]> {
        let mut out = vec![0.0; MAX_REC_NOTES * REC_NOTE_FLOATS];
        let n = r.drain(&mut out, beat);
        out[..n].as_chunks::<5>().0.to_vec()
    }

    #[test]
    fn registro_fecha_reataca_e_salta() {
        let mut r = NoteRecorder::new();
        r.note_on(0, 60, 1.0, 0.0);
        assert!(r.is_empty(), "sem gravar, nada");
        r.start();
        r.note_on(0, 60, 0.5, 1.0);
        // reataque: a primeira termina onde a segunda começa
        r.note_on(0, 60, 0.7, 1.5);
        r.note_off(0, 60, 2.0);
        // soltar de novo (já fechada) não mexe
        r.note_off(0, 60, 9.0);
        r.note_on(1, 64, 1.0, 3.5);
        r.jump(4.0, 0.0);
        r.note_off(1, 64, 0.25);
        r.note_on(1, 67, 1.0, 0.5);
        assert_eq!(
            read_all(&mut r, 0.75),
            vec![[0.0, 60.0, 1.0, 1.5, 0.5], [0.0, 60.0, 1.5, 2.0, 0.7], [1.0, 64.0, 3.5, 4.0, 1.0], [1.0, 64.0, 0.0, 0.25, 1.0], [1.0, 67.0, 0.5, 0.75, 1.0]]
        );
        assert!(r.is_empty(), "a leitura zera");
    }

    #[test]
    fn registro_cheio_descarta_e_leitura_parcial_guarda_o_resto() {
        let mut r = NoteRecorder::new();
        r.start();
        for i in 0..MAX_REC_NOTES + 10 {
            r.note_on(0, (i % 128) as u8, 1.0, i as f64);
        }
        assert_eq!(r.len(), MAX_REC_NOTES);
        assert_eq!(r.dropped(), 10);
        r.stop(1e6);
        let mut out = [0.0; 12];
        assert_eq!(r.drain(&mut out, 0.0), 10, "só grupos inteiros");
        assert_eq!(out[2], 0.0);
        assert_eq!(out[7], 1.0);
        assert_eq!(r.len(), MAX_REC_NOTES - 2);
        // parado não registra mais
        r.note_on(0, 1, 1.0, 5.0);
        assert_eq!(r.len(), MAX_REC_NOTES - 2);
    }

    #[test]
    fn captura_com_atraso_e_leitura() {
        let mut c = Captures::new();
        assert_eq!(c.add(-2, 4), -1);
        let m = c.add(-1, 4) as usize;
        let t = c.add(0, 4) as usize;
        c.arm(4);
        c.priming = true;
        let src: Vec<f32> = (1..=8).map(|i| i as f32).collect();
        c.write(m, 0, 4, Some((&src[..4], &src[..4])));
        c.write(t, 0, 4, Some((&src[..4], &src[..4])));
        c.priming = false;
        c.begin_block(4);
        c.write(m, 0, 4, Some((&src[4..], &src[4..])));
        c.write(t, 0, 4, Some((&src[4..], &src[4..])));
        let (mut l, mut r) = (vec![9.0; 6], vec![9.0; 6]);
        assert_eq!(c.read(m, &mut l, &mut r), 4);
        assert_eq!(l, vec![5.0, 6.0, 7.0, 8.0, 0.0, 0.0]);
        c.read(t, &mut l, &mut r);
        assert_eq!(r, vec![1.0, 2.0, 3.0, 4.0, 0.0, 0.0], "a faixa sai atrasada do adiantamento");
        assert_eq!(c.read(7, &mut l, &mut r), 0);
        assert!(l.iter().all(|&v| v == 0.0));
        for _ in 2..MAX_CAPTURES {
            assert!(c.add(0, 4) >= 0);
        }
        assert_eq!(c.add(0, 4), -1, "cheio");
        c.clear();
        assert_eq!(c.add(3, 4), 0, "limpar reaproveita os lugares");
        assert_eq!(c.track(0), 3);
    }
}
