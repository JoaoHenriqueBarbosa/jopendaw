//! O núcleo da thread de áudio: o [`Engine`] e tudo o que o callback toca.
//!
//! Sem plataforma: o callback do AAudio (só no Android) chama [`AudioCore::render`] com o buffer
//! de saída, e os testes no macOS chamam o mesmo `render` com um buffer qualquer. Os comandos
//! chegam pela fila (rtrb) e são aplicados antes de cada bloco, na ordem em que o Dart mandou; o
//! que eles soltam (a lista de chamadas já aplicada, uma entrada trocada) volta pela fila de lixo
//! para ser liberado fora daqui. O que o motor solta por dentro fica com o alocador ([`crate::alloc`]).
//!
//! A entrada de áudio não tem thread própria: o callback de saída lê a entrada sem bloquear (o
//! desenho de full duplex do Oboe), então saída e entrada andam no mesmo relógio, sem anel entre
//! duas threads.

use std::sync::Arc;
use std::sync::atomic::{AtomicU64, Ordering};

use jopendaw_engine::api::UnknownCall;
use jopendaw_engine::record::{MAX_REC_CCS, MAX_REC_NOTES, REC_NOTE_FLOATS};
use jopendaw_engine::{Engine, MAX_BLOCK, Sample};
use rtrb::{Consumer, Producer, RingBuffer};

use crate::call::{Call, NAME_MAX};
use crate::capture::{RING_SECS, RecReader, RecWriter, rec_ring};
use crate::state::{LOUDNESS_KINDS, MAX_PEAK_TRACKS, Snapshot, StateReader, StateWriter, state};

/// O despachante das chamadas por nome (`engine::api::apply`; os testes trocam).
pub type ApplyFn = fn(&mut Engine, &str, &[f64]) -> Result<Option<f64>, UnknownCall>;

/// Maior pedaço do buffer do callback que vai de uma vez ao `process` (o AAudio costuma pedir de
/// 48 a 1024 quadros; a entrada e as capturas do motor aceitam até [`MAX_BLOCK`]).
pub const BLOCK: usize = 1024;
const _: () = assert!(BLOCK <= MAX_BLOCK);

/// Comandos na fila (cada `jd_calls` é um só, a lista inteira aplicada entre dois blocos).
const COMMANDS: usize = 1024;

/// Notas e eventos de controle (bend, modulação, pedal) registrados numa captura, como o worklet
/// reserva (o registro do motor guarda até [`MAX_REC_NOTES`] e [`MAX_REC_CCS`]).
pub const REC_NOTES_MAX: usize = REC_NOTE_FLOATS * (MAX_REC_NOTES + MAX_REC_CCS);

/// Espectros publicados por segundo com o analisador ligado (o worklet manda ~20).
const SPECTRUM_PER_SEC: f64 = 30.0;

/// De onde o callback lê a entrada (no Android, um stream de entrada do AAudio sem callback).
pub trait InputSource: Send {
    /// Lê até `l.len()` quadros sem bloquear, estéreo (mono repete nos dois lados).
    fn read(&mut self, l: &mut [f32], r: &mut [f32]) -> InputRead;
}

pub enum InputRead {
    Frames(usize),
    /// A entrada caiu (desconectada): sai do núcleo e o host decide se reabre.
    Lost,
}

pub enum Command {
    /// Uma lista de `jd_calls`, aplicada inteira antes do próximo bloco.
    Calls(Box<[Call]>),
    Sample {
        id: u32,
        sample: Sample,
    },
    DropSample(u32),
    Capture {
        on: bool,
        epoch: u32,
    },
    /// Liga (ou troca) a entrada; `None` desliga.
    Input(Option<Box<dyn InputSource>>),
}

/// O que a thread de áudio solta e o host libera.
pub enum Garbage {
    Calls(#[allow(dead_code)] Box<[Call]>),
    Input(#[allow(dead_code)] Box<dyn InputSource>),
}

/// Contadores para o log (o supervisor escreve; nada disso vai ao Dart).
#[derive(Default)]
pub struct Diagnostics {
    pub unknown_calls: AtomicU64,
    /// O nome da última chamada desconhecida, em bytes empacotados (NAME_MAX = 4 × 8).
    last_unknown: [AtomicU64; NAME_MAX / 8],
    pub input_short: AtomicU64,
    pub rec_dropped: AtomicU64,
}

impl Diagnostics {
    fn unknown(&self, name: &str) {
        self.unknown_calls.fetch_add(1, Ordering::Relaxed);
        let mut bytes = [0u8; NAME_MAX];
        let n = name.len().min(NAME_MAX);
        bytes[..n].copy_from_slice(&name.as_bytes()[..n]);
        for (i, a) in self.last_unknown.iter().enumerate() {
            a.store(u64::from_le_bytes(bytes[i * 8..i * 8 + 8].try_into().unwrap_or_default()), Ordering::Relaxed);
        }
    }

    /// O nome da última chamada que o motor não conhecia.
    pub fn last_unknown(&self) -> String {
        let mut bytes = Vec::with_capacity(NAME_MAX);
        for a in &self.last_unknown {
            bytes.extend_from_slice(&a.load(Ordering::Relaxed).to_le_bytes());
        }
        let end = bytes.iter().position(|&b| b == 0).unwrap_or(bytes.len());
        String::from_utf8_lossy(&bytes[..end]).into_owned()
    }
}

/// O lado do host (thread do Dart) de um núcleo.
pub struct CoreLink {
    pub commands: Producer<Command>,
    pub garbage: Consumer<Garbage>,
    pub state: StateReader,
    pub notes: Consumer<f32>,
    /// Uma entrada por captura encerrada: quantos floats de notas ela deixou em `notes`.
    pub notes_done: Consumer<u32>,
    pub rec: RecReader,
    pub diag: Arc<Diagnostics>,
}

pub struct AudioCore {
    engine: Engine,
    apply: ApplyFn,
    commands: Consumer<Command>,
    garbage: Producer<Garbage>,
    state: StateWriter,
    notes: Producer<f32>,
    notes_done: Producer<u32>,
    notes_buf: Box<[f32]>,
    rec: RecWriter,
    input: Option<Box<dyn InputSource>>,
    capturing: bool,
    /// A captura atual já gravou áudio: segue gravando (silêncio, se a entrada cair) para o resto
    /// continuar no lugar certo da linha do tempo.
    rec_started: bool,
    analyzing: bool,
    spectrum_live: bool,
    spectrum_every: usize,
    spectrum_frames: usize,
    out_l: Box<[f32]>,
    out_r: Box<[f32]>,
    in_l: Box<[f32]>,
    in_r: Box<[f32]>,
    diag: Arc<Diagnostics>,
}

/// Cria o núcleo (para a thread de áudio) e o lado do host, com um motor na taxa `rate`.
pub fn core(rate: f64, apply: ApplyFn) -> (AudioCore, CoreLink) {
    let (cp, cc) = RingBuffer::new(COMMANDS);
    // um lixo no máximo por comando, e um de reserva para a entrada que cai no meio do bloco
    let (gp, gc) = RingBuffer::new(COMMANDS + 1);
    let (sw, sr) = state();
    let (np, nc) = RingBuffer::new(REC_NOTES_MAX);
    let (dp, dc) = RingBuffer::new(64);
    let (rw, rr) = rec_ring((RING_SECS * rate) as usize);
    let diag = Arc::new(Diagnostics::default());
    let block = || vec![0.0f32; BLOCK].into_boxed_slice();
    let core = AudioCore {
        engine: Engine::new(rate),
        apply,
        commands: cc,
        garbage: gp,
        state: sw,
        notes: np,
        notes_done: dp,
        notes_buf: vec![0.0f32; REC_NOTES_MAX].into_boxed_slice(),
        rec: rw,
        input: None,
        capturing: false,
        rec_started: false,
        analyzing: false,
        spectrum_live: false,
        spectrum_every: ((rate / SPECTRUM_PER_SEC) as usize).max(1),
        spectrum_frames: 0,
        out_l: block(),
        out_r: block(),
        in_l: block(),
        in_r: block(),
        diag: diag.clone(),
    };
    let link = CoreLink { commands: cp, garbage: gc, state: sr, notes: nc, notes_done: dc, rec: rr, diag };
    (core, link)
}

impl AudioCore {
    pub fn meters(&self) -> &Arc<crate::state::Meters> {
        &self.state.meters
    }

    /// Aplica os comandos da fila, na ordem. Cada comando pode soltar um lixo; sempre sobra uma
    /// vaga na fila de lixo para a entrada que cair no meio do bloco (senão o fechamento dela, que
    /// bloqueia, cairia aqui).
    fn drain(&mut self) {
        while self.garbage.slots() > 1 {
            let Ok(cmd) = self.commands.pop() else { break };
            match cmd {
                Command::Calls(calls) => {
                    for c in calls.iter() {
                        self.call(c);
                    }
                    let _ = self.garbage.push(Garbage::Calls(calls));
                }
                Command::Sample { id, sample } => self.engine.load_sample(id, sample),
                Command::DropSample(id) => self.engine.drop_sample(id),
                Command::Capture { on, epoch } => {
                    if self.capturing {
                        self.finish_capture();
                    }
                    if on {
                        self.start_capture(epoch);
                    }
                }
                Command::Input(src) => {
                    if let Some(old) = std::mem::replace(&mut self.input, src) {
                        let _ = self.garbage.push(Garbage::Input(old));
                    }
                }
            }
        }
    }

    fn call(&mut self, c: &Call) {
        let (name, args) = (c.name(), c.args());
        // o analisador só custa (FFT e cópia) quando alguém observa uma faixa; o motor limita a
        // faixa a −2 (desligado), então qualquer coisa abaixo de −1 desliga
        if name == "watch_analyzer" {
            self.analyzing = args.first().is_some_and(|&t| t >= -1.0);
        }
        if (self.apply)(&mut self.engine, name, args).is_err() {
            self.diag.unknown(name);
        }
    }

    /// Aplica pelo despachante e, se ele não conhecer o nome, direto no motor (as duas pontas da
    /// captura não podem depender de o despachante estar completo).
    fn apply_or(&mut self, name: &str, direct: fn(&mut Engine)) {
        if (self.apply)(&mut self.engine, name, &[]).is_err() {
            direct(&mut self.engine);
        }
    }

    fn start_capture(&mut self, epoch: u32) {
        self.capturing = true;
        self.rec_started = false;
        self.rec.begin(epoch);
        self.apply_or("rec_notes_start", Engine::rec_notes_start);
    }

    /// Fim da captura: fecha o trecho de áudio e entrega as notas registradas, lidas antes de
    /// parar o registro (a tecla ainda segurada termina na posição atual), como o worklet.
    fn finish_capture(&mut self) {
        self.rec.close();
        let n = self.engine.rec_notes(&mut self.notes_buf).min(self.notes_buf.len());
        let n = n.min(self.notes.slots());
        if let Ok(mut chunk) = self.notes.write_chunk(n) {
            let (a, b) = chunk.as_mut_slices();
            let split = a.len();
            a.copy_from_slice(&self.notes_buf[..split]);
            b.copy_from_slice(&self.notes_buf[split..n]);
            chunk.commit_all();
        }
        let _ = self.notes_done.push(n as u32);
        self.apply_or("rec_notes_stop", Engine::rec_notes_stop);
        self.capturing = false;
        self.rec_started = false;
    }

    /// Sem saída de áudio rodando (parada, segundo plano, dispositivo trocando): aplica os
    /// comandos e publica o estado sem processar áudio, para a fila não encher e o Dart ver o que
    /// mandou.
    pub fn idle(&mut self) {
        self.drain();
        self.publish(0);
    }

    /// Um callback de saída: aplica os comandos, lê a entrada, processa e enche `out`
    /// (intercalado, `channels` canais: mono recebe a média, o terceiro canal em diante, silêncio).
    pub fn render(&mut self, out: &mut [f32], channels: usize) {
        self.drain();
        let channels = channels.max(1);
        let frames = out.len() / channels;
        let mut done = 0;
        while done < frames {
            let m = (frames - done).min(BLOCK);
            let got_input = self.read_input(m);
            // posição e estado deste pedaço (os comandos só mudam entre um callback e outro)
            let playing = self.engine.playing();
            let beat = if playing { self.engine.beat() } else { 0.0 };
            self.engine.process(&mut self.out_l[..m], &mut self.out_r[..m]);
            let dst = &mut out[done * channels..(done + m) * channels];
            match channels {
                1 => {
                    for (i, o) in dst.iter_mut().enumerate() {
                        *o = 0.5 * (self.out_l[i] + self.out_r[i]);
                    }
                }
                2 => {
                    for (i, f) in dst.as_chunks_mut::<2>().0.iter_mut().enumerate() {
                        *f = [self.out_l[i], self.out_r[i]];
                    }
                }
                _ => {
                    for (i, f) in dst.chunks_exact_mut(channels).enumerate() {
                        f[0] = self.out_l[i];
                        f[1] = self.out_r[i];
                        f[2..].fill(0.0);
                    }
                }
            }
            if self.capturing {
                self.record(m, got_input, playing, beat);
            }
            done += m;
        }
        self.publish(frames);
    }

    /// Lê `m` quadros da entrada para o motor (o que faltar vira silêncio). `false` sem entrada.
    fn read_input(&mut self, m: usize) -> bool {
        let Some(src) = self.input.as_mut() else { return false };
        match src.read(&mut self.in_l[..m], &mut self.in_r[..m]) {
            InputRead::Frames(k) => {
                let k = k.min(m);
                if k < m {
                    self.in_l[k..m].fill(0.0);
                    self.in_r[k..m].fill(0.0);
                    self.diag.input_short.fetch_add(1, Ordering::Relaxed);
                }
                let peak = self.in_l[..k].iter().chain(&self.in_r[..k]).fold(0.0f32, |p, s| p.max(s.abs()));
                self.state.meters.raise_input(peak);
                self.engine.set_input(&self.in_l[..m], Some(&self.in_r[..m]));
                true
            }
            InputRead::Lost => {
                if let Some(old) = self.input.take() {
                    // a vaga reservada no `drain` garante que cabe
                    let _ = self.garbage.push(Garbage::Input(old));
                }
                self.state.meters.set_input_dropped();
                false
            }
        }
    }

    /// Grava o pedaço capturado, como o worklet: só com o transporte tocando e com entrada aberta
    /// (ou já gravando: aí a entrada que caiu vira silêncio no lugar).
    fn record(&mut self, m: usize, got_input: bool, playing: bool, beat: f64) {
        if playing && (self.input.is_some() || self.rec_started) {
            if !got_input {
                self.in_l[..m].fill(0.0);
                self.in_r[..m].fill(0.0);
            }
            let after = self.engine.beat();
            let bpf = self.engine.frames_to_beats(1.0);
            let before = self.rec.dropped;
            self.rec.write(&self.in_l[..m], &self.in_r[..m], beat, after, bpf);
            if self.rec.dropped != before {
                self.diag.rec_dropped.fetch_add(self.rec.dropped - before, Ordering::Relaxed);
            }
            self.rec_started = true;
        } else {
            // parou: tocar de novo começa outro trecho
            self.rec.close();
        }
    }

    fn publish(&mut self, frames: usize) {
        let meters = self.state.meters.clone();
        let e = &mut self.engine;
        let shown = e.tracks().len().min(MAX_PEAK_TRACKS);
        for i in 0..shown {
            let (l, r) = e.track_mut(i).map(|t| t.take_peaks()).unwrap_or_default();
            meters.raise_peak(2 * i, l);
            meters.raise_peak(2 * i + 1, r);
        }
        let (l, r) = e.master_mut().take_peaks();
        meters.raise_peak(2 * shown, l);
        meters.raise_peak(2 * shown + 1, r);
        let snap = Snapshot { beat: e.beat(), playing: e.playing(), fx_meter: e.fx_meter(), peaks: 2 * (shown as u32 + 1) };
        self.state.publish(snap);
        for k in 0..LOUDNESS_KINDS {
            meters.set_loudness(k, e.loudness(k as u32));
        }
        meters.set_latency(e.latency_frames() as f64);
        if self.analyzing {
            self.spectrum_frames += frames;
            if self.spectrum_frames >= self.spectrum_every || !self.spectrum_live {
                self.spectrum_frames = 0;
                self.spectrum_live = true;
                let e = &mut self.engine;
                self.state.publish_spectrum(|db| e.analyzer(db));
            }
        } else if self.spectrum_live {
            self.spectrum_live = false;
            self.state.publish_spectrum(|_| 0);
        }
    }
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;
    use jopendaw_engine::Clip;
    use std::sync::Mutex;

    /// Despachante dos testes: o de verdade (`engine::api::apply`) primeiro e, enquanto ele não
    /// conhecer o nome (no worktree desta fase ele ainda é um esqueleto), um mínimo com as
    /// chamadas que os testes usam, direto nos métodos do motor.
    pub fn test_apply(e: &mut Engine, name: &str, a: &[f64]) -> Result<Option<f64>, UnknownCall> {
        match jopendaw_engine::api::apply(e, name, a) {
            Err(UnknownCall(_)) => {}
            r => return r,
        }
        let g = |i: usize| a.get(i).copied().unwrap_or(0.0);
        match name {
            "tempo" => e.set_tempo(g(0), g(1) as u32),
            "play" => e.play(),
            "stop" => e.stop(),
            "seek" => e.seek(g(0)),
            "loop_set" => e.set_loop(g(0) != 0.0, g(1), g(2)),
            "metronome" => e.set_metronome(g(0) != 0.0, g(1) as f32),
            "tracks" => e.set_track_count(g(0) as usize),
            "track" => {
                if let Some(t) = e.track_mut(g(0) as usize) {
                    t.gain = g(1) as f32;
                    t.pan = g(2) as f32;
                    t.mute = g(3) != 0.0;
                    t.solo = g(4) != 0.0;
                }
            }
            "master" => {
                let m = e.master_mut();
                m.gain = g(0) as f32;
                m.pan = g(1) as f32;
            }
            "clips_clear" => e.clear_clips(),
            "clip_add" => e.add_clip(Clip {
                track: g(0) as usize,
                sample: g(1) as u32,
                start: g(2),
                offset: g(3),
                length: g(4),
                gain: g(5) as f32,
                fade_in: g(6),
                fade_out: g(7),
            }),
            "clip_fade_shape" => e.set_clip_fade_shape(g(0) as u32, g(1) as u32),
            "track_kind" => e.set_track_kind(g(0) as usize, g(1) as u32),
            "live_on" => e.live_on(g(0) as usize, g(1) as u32, g(2) as f32),
            "live_off" => e.live_off(g(0) as usize, g(1) as u32),
            "watch_analyzer" => e.watch_analyzer(g(0) as i32),
            "input_monitor" => e.set_monitor(g(0) as usize, g(1) != 0.0),
            "capture_clear" => e.capture_clear(),
            "capture_add" => return Ok(Some(e.capture_add(g(0) as i32) as f64)),
            "beat" => return Ok(Some(e.beat())),
            "playing" => return Ok(Some(e.playing() as u32 as f64)),
            _ => return Err(UnknownCall(name.to_owned())),
        }
        Ok(None)
    }

    fn calls(json: &str) -> Command {
        Command::Calls(crate::call::parse_calls(json.as_bytes()).unwrap().into_boxed_slice())
    }

    /// A ordem em que o despachante viu as chamadas (os testes rodam em paralelo: uma lista por
    /// teste, escolhida pelo primeiro argumento).
    static SEEN: Mutex<Vec<(String, Vec<f64>)>> = Mutex::new(Vec::new());

    fn recording_apply(_: &mut Engine, name: &str, a: &[f64]) -> Result<Option<f64>, UnknownCall> {
        if name == "nope" {
            return Err(UnknownCall(name.to_owned()));
        }
        SEEN.lock().unwrap().push((name.to_owned(), a.to_vec()));
        Ok(None)
    }

    #[test]
    fn commands_apply_in_order_before_the_block_and_come_back_as_garbage() {
        let (mut core, mut link) = core(48_000.0, recording_apply);
        let _ = link.commands.push(calls(r#"[["a", 1], ["b", 2], ["nope"], ["c", 3]]"#));
        let _ = link.commands.push(calls(r#"[["d", 4]]"#));
        let _ = link.commands.push(calls(r#"[["e", 5], ["f", 6]]"#));
        assert!(SEEN.lock().unwrap().iter().all(|(n, _)| n.len() != 1));
        let mut out = vec![0.0f32; 256];
        core.render(&mut out, 2);
        let seen: Vec<String> = SEEN.lock().unwrap().iter().filter(|(n, _)| n.len() == 1).map(|(n, a)| format!("{n}{}", a[0])).collect();
        assert_eq!(seen, ["a1", "b2", "c3", "d4", "e5", "f6"]);
        assert_eq!(link.diag.unknown_calls.load(Ordering::Relaxed), 1);
        assert_eq!(link.diag.last_unknown(), "nope");
        let mut garbage = 0;
        while let Ok(g) = link.garbage.pop() {
            assert!(matches!(g, Garbage::Calls(_)));
            garbage += 1;
        }
        assert_eq!(garbage, 3);
    }

    /// Um áudio de `n` quadros com valor constante `v` nos dois canais.
    pub fn dc(n: usize, v: f32) -> Sample {
        Sample::new(vec![vec![v; n], vec![v; n]], 48_000.0)
    }

    #[test]
    fn a_clip_sounds_and_state_and_peaks_come_back() {
        let (mut core, mut link) = core(48_000.0, test_apply);
        let _ = link.commands.push(Command::Sample { id: 7, sample: dc(48_000, 0.5) });
        let _ = link.commands.push(calls(r#"[["tempo", 120, 4], ["tracks", 1], ["track_kind", 0, 0], ["track", 0, 1, 0, 0, 0], ["master", 1, 0], ["clip_add", 0, 7, 0, 0, 1, 1, 0, 0], ["play"]]"#));
        let mut out = vec![0.0f32; 2 * 4800];
        // o limitador do master atrasa um pouco a saída: alguns callbacks até o som chegar
        for _ in 0..4 {
            core.render(&mut out, 2);
        }
        assert!(out.iter().any(|&s| s.abs() > 0.1), "o clipe não soou");
        let mut st = [0.0f64; 16];
        let n = link.state.write_state(&mut st);
        assert_eq!(n, 4 + 4);
        assert_eq!(st[1], 1.0);
        // 4 × 4800 quadros a 120 bpm (2 batidas por segundo) = 0,8 batida
        assert!((st[0] - 0.8).abs() < 1e-9, "batida {}", st[0]);
        assert!(st[4] > 0.1 && st[6] > 0.1, "picos {:?}", &st[4..8]);
        // a latência do motor (aqui só a do limitador de segurança) sai publicada
        let published = link.state.meters.latency();
        assert!(published > 0.0 && published == core.engine.latency_frames() as f64, "latência {published}");
        // mono: a média dos dois lados
        let mut mono = vec![0.0f32; 480];
        core.render(&mut mono, 1);
        assert!(mono.iter().any(|&s| s.abs() > 0.1));
        // parado: a batida congela e o estado diz que parou
        let _ = link.commands.push(calls(r#"[["stop"]]"#));
        core.idle();
        let n = link.state.write_state(&mut st);
        assert_eq!(st[1], 0.0);
        assert_eq!(n, 8);
    }

    /// Entrada de teste: uma rampa contínua, ou desconectada.
    pub struct FakeInput {
        pub next: f32,
        pub lost: bool,
    }

    impl InputSource for FakeInput {
        fn read(&mut self, l: &mut [f32], r: &mut [f32]) -> InputRead {
            if self.lost {
                return InputRead::Lost;
            }
            for (a, b) in l.iter_mut().zip(r.iter_mut()) {
                *a = self.next;
                *b = -self.next;
                self.next += 1.0;
            }
            InputRead::Frames(l.len())
        }
    }

    #[test]
    fn capture_records_the_input_while_playing_and_delivers_the_notes_at_the_end() {
        let (mut core, mut link) = core(48_000.0, test_apply);
        let _ = link.commands.push(Command::Input(Some(Box::new(FakeInput { next: 0.0, lost: false }))));
        let _ = link.commands.push(calls(r#"[["tempo", 120, 4], ["tracks", 1], ["track_kind", 0, 1], ["seek", 2]]"#));
        link.rec.begin(1);
        let _ = link.commands.push(Command::Capture { on: true, epoch: 1 });
        let mut out = vec![0.0f32; 2 * 512];
        // parado: nada gravado
        core.render(&mut out, 2);
        let (mut l, mut r) = (vec![0.0f32; 48_000], vec![0.0f32; 48_000]);
        assert_eq!(link.rec.read(&mut l, &mut r).0, 0);
        assert!(link.state.meters.take_input() > 0.0);
        let _ = link.commands.push(calls(r#"[["play"], ["live_on", 0, 60, 0.5]]"#));
        core.render(&mut out, 2);
        core.render(&mut out, 2);
        let _ = link.commands.push(calls(r#"[["live_off", 0, 60]]"#));
        core.render(&mut out, 2);
        let (n, beat) = link.rec.read(&mut l, &mut r);
        assert_eq!(n, 3 * 512);
        assert!((beat - 2.0).abs() < 1e-9, "batida do primeiro quadro {beat}");
        // contínuo: a rampa segue de um quadro ao outro
        assert!(l[..n].windows(2).all(|w| w[1] == w[0] + 1.0));
        assert_eq!(r[10], -l[10]);
        let _ = link.commands.push(Command::Capture { on: false, epoch: 1 });
        core.render(&mut out, 2);
        let floats = link.notes_done.pop().expect("fim da captura");
        let notes: Vec<f32> = (0..floats).map(|_| link.notes.pop().unwrap()).collect();
        assert_eq!(notes.len(), 5, "{notes:?}");
        assert_eq!(notes[0], 0.0);
        assert_eq!(notes[1], 60.0);
        let (start, end) = (notes[2] as f64, notes[3] as f64);
        // tocada no começo do 2º callback (o 1º foi parado, na batida 2), solta no começo do 4º
        assert!((start - 2.0).abs() < 1e-5, "início {start}");
        assert!((end - (2.0 + 1024.0 / 24_000.0)).abs() < 1e-5, "fim {end}");
        assert!((notes[4] - 0.5).abs() < 1e-6);
        // depois do fim, nada mais é gravado
        core.render(&mut out, 2);
        assert_eq!(link.rec.read(&mut l, &mut r).0, 0);
    }

    #[test]
    fn a_lost_input_leaves_the_core_and_the_capture_goes_on_in_silence() {
        let (mut core, mut link) = core(48_000.0, test_apply);
        let _ = link.commands.push(Command::Input(Some(Box::new(FakeInput { next: 1.0, lost: false }))));
        let _ = link.commands.push(calls(r#"[["play"]]"#));
        link.rec.begin(3);
        let _ = link.commands.push(Command::Capture { on: true, epoch: 3 });
        let mut out = vec![0.0f32; 2 * 256];
        core.render(&mut out, 2);
        let _ = link.commands.push(Command::Input(Some(Box::new(FakeInput { next: 0.0, lost: true }))));
        core.render(&mut out, 2);
        // a entrada antiga (trocada) e a que caiu voltaram como lixo
        let mut inputs = 0;
        while let Ok(g) = link.garbage.pop() {
            if matches!(g, Garbage::Input(_)) {
                inputs += 1;
            }
        }
        assert_eq!(inputs, 2);
        assert!(link.state.meters.take_input_dropped());
        core.render(&mut out, 2);
        let (mut l, mut r) = (vec![0.0f32; 4096], vec![0.0f32; 4096]);
        let (n, _) = link.rec.read(&mut l, &mut r);
        assert_eq!(n, 3 * 256, "a captura continua com silêncio");
        assert!(l[..256].iter().all(|&s| s != 0.0));
        assert!(l[256..n].iter().all(|&s| s == 0.0));
    }

    #[test]
    fn the_analyzer_publishes_only_when_watched() {
        let (mut core, mut link) = core(48_000.0, test_apply);
        let mut spec = vec![0.0f32; 1024];
        let mut out = vec![0.0f32; 2 * 2048];
        core.render(&mut out, 2);
        assert_eq!(link.state.spectrum(&mut spec), 0);
        let _ = link.commands.push(calls(r#"[["watch_analyzer", -1]]"#));
        core.render(&mut out, 2);
        assert_eq!(link.state.spectrum(&mut spec), 1024);
        let _ = link.commands.push(calls(r#"[["watch_analyzer", -2]]"#));
        core.render(&mut out, 2);
        assert_eq!(link.state.spectrum(&mut spec), 0);
    }
}
