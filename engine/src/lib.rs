//! Motor de áudio do jopendaw.
//!
//! Tudo o que soa passa por aqui: o transporte (tocar, parar, loop), os clipes de áudio na linha do
//! tempo, as faixas de instrumento com as notas do sequenciador e as tocadas ao vivo, o mixer
//! (volume, pan, mudo, solo) e o metrônomo. O crate não sabe de plataforma: quem o hospeda (o
//! AudioWorklet na web, o Oboe no Android) chama [`Engine::process`] com blocos de amostras e manda
//! os comandos entre um bloco e outro, na mesma thread de áudio.
//!
//! O tempo da linha do tempo é contado em quadros (amostras por canal) na taxa do motor; posições
//! do documento chegam em tempos musicais (batidas) e viram quadros pelo andamento atual.
//!
//! # Notas
//!
//! Cada faixa guarda as notas do sequenciador ordenadas pelo início, em batidas absolutas da linha
//! do tempo; o app reenvia todas a cada edição ([`Engine::clear_notes`] + [`Engine::add_note`]),
//! inclusive tocando. Os eventos caem no quadro exato: o bloco é fatiado nos pontos das notas e o
//! instrumento renderiza cada fatia. O note on vem da lista; o note off vem do conjunto de notas
//! que o sequenciador disparou e ainda soam (altura e fim), mantido aqui, e não da lista: assim um
//! reenvio no meio de uma nota (que pode até apagá-la) nunca deixa nota presa. Tocar a partir do
//! meio de uma nota não a "persegue": só soam as notas que começam dali em diante.

pub mod drums;
pub mod dsp;
pub mod instrument;
mod limiter;
mod metronome;
mod mixer;
pub mod sampler;
pub mod synth;

use std::collections::HashMap;
use std::sync::Arc;

pub use metronome::Metronome;
pub use mixer::{Track, pan_gains};

use instrument::Instrument;

/// Maior bloco processado de uma vez; blocos maiores são fatiados.
pub const MAX_BLOCK: usize = 4096;

/// Fade dos clipes de áudio ao parar: cortar o áudio no meio de uma onda estala.
const STOP_FADE_SECS: f64 = 0.01;

/// Notas reservadas por faixa (cabem sem realocar; passar disso realoca no comando, nunca no
/// `process`).
const NOTES_RESERVED: usize = 1024;

/// Um áudio decodificado: um ou dois canais na taxa em que foi gravado.
pub struct Sample {
    channels: Vec<Vec<f32>>,
    rate: f64,
}

impl Sample {
    /// `channels` precisa ter 1 ou 2 canais do mesmo tamanho.
    pub fn new(mut channels: Vec<Vec<f32>>, rate: f64) -> Self {
        channels.truncate(2);
        if channels.is_empty() {
            channels.push(Vec::new());
        }
        let len = channels.iter().map(Vec::len).min().unwrap_or(0);
        for c in &mut channels {
            c.truncate(len);
        }
        Self { channels, rate }
    }

    pub fn frames(&self) -> usize {
        self.channels[0].len()
    }

    pub fn channels(&self) -> usize {
        self.channels.len()
    }

    /// As amostras de um canal (o último, se `ch` passar do número de canais).
    pub fn channel(&self, ch: usize) -> &[f32] {
        &self.channels[ch.min(self.channels.len() - 1)]
    }

    pub fn rate(&self) -> f64 {
        self.rate
    }

    pub fn duration(&self) -> f64 {
        self.frames() as f64 / self.rate
    }

    /// Amostra em `pos` (quadro fracionário) com interpolação linear; fora do áudio é silêncio.
    pub fn at(&self, ch: usize, pos: f64) -> f32 {
        let data = self.channel(ch);
        if pos < 0.0 {
            return 0.0;
        }
        let i = pos as usize;
        if i + 1 >= data.len() {
            return if i < data.len() { data[i] } else { 0.0 };
        }
        let frac = (pos - i as f64) as f32;
        data[i] + (data[i + 1] - data[i]) * frac
    }

    /// Amostra em `pos` com interpolação cúbica ([`hermite`]); fora do áudio é silêncio. Mais
    /// limpa que a linear na conversão de taxa (menos perda de agudos e menos imagens).
    pub fn at_cubic(&self, ch: usize, pos: f64) -> f32 {
        let data = self.channel(ch);
        if !(pos >= 0.0 && pos < data.len() as f64) {
            return 0.0;
        }
        let i = pos as usize;
        let t = (pos - i as f64) as f32;
        let get = |k: usize| data.get(k).copied().unwrap_or(0.0);
        let before = if i > 0 { data[i - 1] } else { 0.0 };
        hermite(before, data[i], get(i + 1), get(i + 2), t)
    }
}

/// Interpolação de Hermite (Catmull-Rom) de 4 pontos: o valor entre `x1` e `x2` na fração `t`.
/// Reproduz retas exatamente e passa pelos pontos.
#[inline]
pub fn hermite(x0: f32, x1: f32, x2: f32, x3: f32, t: f32) -> f32 {
    let c1 = 0.5 * (x2 - x0);
    let c2 = x0 - 2.5 * x1 + 2.0 * x2 - 0.5 * x3;
    let c3 = 0.5 * (x3 - x0) + 1.5 * (x1 - x2);
    ((c3 * t + c2) * t + c1) * t + x1
}

/// Um clipe de áudio numa faixa: que pedaço do sample toca e onde.
#[derive(Clone, Debug, PartialEq)]
pub struct Clip {
    pub track: usize,
    pub sample: u32,
    /// Início na linha do tempo, em batidas.
    pub start: f64,
    /// De onde o clipe começa a ler o sample, em segundos.
    pub offset: f64,
    /// Duração, em segundos do sample.
    pub length: f64,
    pub gain: f32,
    pub fade_in: f64,
    pub fade_out: f64,
}

/// Uma nota do sequenciador, em batidas absolutas da linha do tempo.
#[derive(Clone, Copy, Debug, PartialEq)]
struct Note {
    start: f64,
    end: f64,
    pitch: u8,
    velocity: f32,
}

/// Nota que o sequenciador disparou e ainda não soltou: altura e fim (batidas).
#[derive(Clone, Copy, Debug)]
struct Held {
    pitch: u8,
    end: f64,
}

/// Folga para posições que caem num quadro inteiro "quase exato" (erro de ponto flutuante na
/// conversão batida → quadro) não escorregarem para o quadro seguinte.
const FRAME_EPS: f64 = 1e-6;

/// Quadro do bloco (a partir de `pos`) em que cai um evento no quadro fracionário `frame`: o
/// primeiro quadro inteiro que o alcança. Negativo = já passou.
#[inline]
fn event_offset(frame: f64, pos: f64) -> f64 {
    (frame - pos - FRAME_EPS).ceil()
}

/// O que uma faixa tem além do canal do mixer: o tipo, o instrumento e as notas.
struct Lane {
    kind: u32,
    instrument: Option<Box<dyn Instrument>>,
    /// Áudio do sampler (id do motor, 0 = nenhum). Guardado para ligar quando o áudio chegar ou
    /// quando o instrumento for recriado.
    sample: u32,
    notes: Vec<Note>,
    /// Próxima nota da lista a disparar.
    cursor: usize,
    /// Notas do sequenciador soando; no máximo uma por altura.
    held: Vec<Held>,
}

impl Lane {
    fn new() -> Self {
        Self { kind: instrument::kind::AUDIO, instrument: None, sample: 0, notes: Vec::with_capacity(NOTES_RESERVED), cursor: 0, held: Vec::with_capacity(128) }
    }

    /// Aponta o cursor para a primeira nota que ainda não começou em `pos`.
    fn cue(&mut self, pos: f64, frames_per_beat: f64) {
        self.cursor = self.notes.partition_point(|n| event_offset(n.start * frames_per_beat, pos) < 0.0);
    }

    /// Solta as notas do sequenciador (seek, volta do loop). As ao vivo continuam.
    fn release_held(&mut self) {
        if let Some(inst) = self.instrument.as_mut() {
            for h in &self.held {
                inst.note_off(h.pitch);
            }
        }
        self.held.clear();
    }

    /// Soma o instrumento no bloco que começa em `pos`, disparando e soltando as notas do
    /// sequenciador nos quadros exatos quando o transporte anda. Devolve se renderizou algo.
    fn render(&mut self, l: &mut [f32], r: &mut [f32], playing: bool, pos: f64, frames_per_beat: f64) -> bool {
        let Self { instrument, notes, cursor, held, .. } = self;
        let Some(inst) = instrument.as_mut() else { return false };
        let n = l.len();
        let offset = |beat: f64| event_offset(beat * frames_per_beat, pos).clamp(0.0, n as f64) as usize;
        // próximo quadro com evento: o fim mais próximo das que soam ou o início da próxima nota
        let next_event = |held: &[Held], cursor: usize| {
            let off = held.iter().map(|h| offset(h.end)).min().unwrap_or(n);
            notes.get(cursor).map_or(off, |note| off.min(offset(note.start)))
        };
        let mut at = 0;
        let mut sounded = false;
        // parado não há eventos do sequenciador: o instrumento só soa (notas ao vivo, caudas)
        let mut next = if playing { next_event(held, *cursor) } else { n };
        while next < n {
            if next > at {
                if inst.active() {
                    inst.render(&mut l[at..next], &mut r[at..next]);
                    sounded = true;
                }
                at = next;
            }
            // no mesmo quadro, primeiro solta: uma nota que termina onde a mesma altura recomeça
            // não pode cortar a nova
            held.retain(|h| {
                let due = offset(h.end) <= next;
                if due {
                    inst.note_off(h.pitch);
                }
                !due
            });
            while let Some(&note) = notes.get(*cursor) {
                if offset(note.start) > next {
                    break;
                }
                *cursor += 1;
                inst.note_on(note.pitch, note.velocity);
                hold(held, note.pitch, note.end);
            }
            next = next_event(held, *cursor);
        }
        if at < n && inst.active() {
            inst.render(&mut l[at..], &mut r[at..]);
            sounded = true;
        }
        sounded
    }
}

/// Guarda uma nota que o sequenciador disparou. A mesma altura de novo antes de soltar (notas
/// sobrepostas) fica com o fim mais tardio; senão o note off da primeira cortaria a segunda.
fn hold(held: &mut Vec<Held>, pitch: u8, end: f64) {
    match held.iter_mut().find(|h| h.pitch == pitch) {
        Some(h) => h.end = h.end.max(end),
        None => held.push(Held { pitch, end }),
    }
}

/// O motor. Um por contexto de áudio.
pub struct Engine {
    rate: f64,
    bpm: f64,
    beats_per_bar: u32,
    playing: bool,
    /// Posição do transporte em quadros.
    pos: f64,
    loop_on: bool,
    loop_start: f64,
    loop_end: f64,
    samples: HashMap<u32, Arc<Sample>>,
    clips: Vec<Clip>,
    tracks: Vec<Track>,
    /// Paralelo a `tracks`.
    lanes: Vec<Lane>,
    master: Track,
    limiter: limiter::Limiter,
    limiter_on: bool,
    metronome: Metronome,
    buf_l: Vec<f32>,
    buf_r: Vec<f32>,
    /// Depois do stop, os clipes de áudio ainda soam por alguns quadros descendo a zero: quantos
    /// faltam, de quantos, e de que posição (quadros).
    tail: usize,
    tail_len: usize,
    tail_pos: f64,
    /// Notas mudaram desde o último bloco: reordenar antes de tocar.
    notes_dirty: bool,
    /// Reposicionar os cursores das notas na posição atual antes do próximo bloco.
    recue: bool,
}

impl Engine {
    pub fn new(rate: f64) -> Self {
        Self {
            rate,
            bpm: 120.0,
            beats_per_bar: 4,
            playing: false,
            pos: 0.0,
            loop_on: false,
            loop_start: 0.0,
            loop_end: 0.0,
            samples: HashMap::new(),
            clips: Vec::new(),
            tracks: Vec::new(),
            lanes: Vec::new(),
            master: Track::new(rate),
            limiter: limiter::Limiter::new(rate),
            limiter_on: true,
            metronome: Metronome::default(),
            buf_l: vec![0.0; MAX_BLOCK],
            buf_r: vec![0.0; MAX_BLOCK],
            tail: 0,
            tail_len: ((STOP_FADE_SECS * rate) as usize).max(1),
            tail_pos: 0.0,
            notes_dirty: false,
            recue: false,
        }
    }

    pub fn rate(&self) -> f64 {
        self.rate
    }

    // ---------------------------------------------------------------- andamento e posição

    /// Muda o andamento. As notas e os fins das que soam estão em batidas: seguem o andamento
    /// novo sem mais nada.
    pub fn set_tempo(&mut self, bpm: f64, beats_per_bar: u32) {
        // a posição musical fica onde estava: quem toca no tempo 9 continua no tempo 9
        let beat = self.beat();
        let (ls, le) = (self.frames_to_beats(self.loop_start), self.frames_to_beats(self.loop_end));
        self.bpm = bpm.clamp(20.0, 999.0);
        self.beats_per_bar = beats_per_bar.clamp(1, 32);
        self.pos = self.beats_to_frames(beat);
        self.loop_start = self.beats_to_frames(ls);
        self.loop_end = self.beats_to_frames(le);
    }

    pub fn beats_to_frames(&self, beats: f64) -> f64 {
        beats * 60.0 / self.bpm * self.rate
    }

    pub fn frames_to_beats(&self, frames: f64) -> f64 {
        frames / self.rate * self.bpm / 60.0
    }

    /// Posição do transporte em batidas.
    pub fn beat(&self) -> f64 {
        self.frames_to_beats(self.pos)
    }

    pub fn playing(&self) -> bool {
        self.playing
    }

    /// Toca a partir da posição atual. Notas que já tinham começado antes dela não soam.
    pub fn play(&mut self) {
        if !self.playing {
            self.playing = true;
            self.recue = true;
            self.tail = 0;
        }
    }

    /// Para. Os instrumentos soltam tudo com o release normal (as caudas continuam soando) e os
    /// clipes de áudio descem a zero num fade curto.
    pub fn stop(&mut self) {
        if self.playing {
            self.tail = self.tail_len;
            self.tail_pos = self.pos;
        }
        self.playing = false;
        self.metronome.silence();
        for lane in &mut self.lanes {
            lane.held.clear();
            if let Some(inst) = lane.instrument.as_mut() {
                inst.release_all();
            }
        }
    }

    /// Vai para uma posição; as notas do sequenciador que soavam são soltas.
    pub fn seek(&mut self, beat: f64) {
        self.pos = self.beats_to_frames(beat.max(0.0));
        self.metronome.silence();
        for lane in &mut self.lanes {
            lane.release_held();
        }
        self.recue = true;
    }

    /// Loop entre duas posições em batidas; `end <= start` desliga.
    pub fn set_loop(&mut self, on: bool, start: f64, end: f64) {
        self.loop_on = on && end > start;
        self.loop_start = self.beats_to_frames(start.max(0.0));
        self.loop_end = self.beats_to_frames(end.max(0.0));
    }

    pub fn set_metronome(&mut self, on: bool, gain: f32) {
        self.metronome.on = on;
        self.metronome.gain = gain;
    }

    // ---------------------------------------------------------------- conteúdo

    /// Guarda um áudio. Faixas de sampler que já apontavam para `id` (o áudio chegou depois da
    /// escolha, ou foi recarregado) passam a tocá-lo.
    pub fn load_sample(&mut self, id: u32, sample: Sample) {
        let sample = Arc::new(sample);
        for lane in self.lanes.iter_mut().filter(|l| l.sample == id) {
            if let Some(inst) = lane.instrument.as_mut() {
                inst.set_sample(Some(sample.clone()));
            }
        }
        self.samples.insert(id, sample);
    }

    /// Esquece um áudio; os instrumentos que o tocavam ficam sem áudio (as vozes que soam
    /// terminam, o instrumento guarda a referência até lá).
    pub fn drop_sample(&mut self, id: u32) {
        self.samples.remove(&id);
        for lane in self.lanes.iter_mut().filter(|l| l.sample == id) {
            if let Some(inst) = lane.instrument.as_mut() {
                inst.set_sample(None);
            }
        }
    }

    pub fn set_track_count(&mut self, n: usize) {
        let rate = self.rate;
        self.tracks.resize_with(n, || Track::new(rate));
        self.lanes.resize_with(n, Lane::new);
    }

    pub fn track_mut(&mut self, i: usize) -> Option<&mut Track> {
        self.tracks.get_mut(i)
    }

    pub fn tracks(&self) -> &[Track] {
        &self.tracks
    }

    /// Liga o limitador de segurança do master (ligado por padrão; os testes que medem amostras em
    /// quadros exatos desligam, por causa do atraso do lookahead).
    pub fn set_limiter(&mut self, on: bool) {
        self.limiter_on = on;
    }

    /// Menor ganho do limitador desde a última leitura (1 = não reduziu).
    pub fn take_limiter_gain(&mut self) -> f32 {
        self.limiter.take_min_gain()
    }

    pub fn master_mut(&mut self) -> &mut Track {
        &mut self.master
    }

    pub fn master(&self) -> &Track {
        &self.master
    }

    pub fn clear_clips(&mut self) {
        self.clips.clear();
    }

    pub fn add_clip(&mut self, clip: Clip) {
        self.clips.push(clip);
    }

    // ---------------------------------------------------------------- instrumentos e notas

    /// Tipo da faixa ([`instrument::kind`]). Só faz algo quando o tipo muda: aí o instrumento
    /// antigo é descartado e o novo nasce nos padrões (os parâmetros vêm depois, por
    /// [`Engine::set_param`]). Criar e destruir o instrumento aloca e libera memória na thread de
    /// áudio; é aceitável porque só acontece ao criar a faixa ou mudar o tipo dela (o app manda o
    /// tipo a cada sync, mas o mesmo tipo de novo não faz nada), nunca a cada bloco.
    pub fn set_track_kind(&mut self, i: usize, kind: u32) {
        let Some(lane) = self.lanes.get_mut(i) else { return };
        if lane.kind == kind {
            return;
        }
        lane.kind = kind;
        lane.held.clear();
        lane.instrument = instrument::create(kind, self.rate);
        if let Some(inst) = lane.instrument.as_mut()
            && lane.sample != 0
        {
            inst.set_sample(self.samples.get(&lane.sample).cloned());
        }
    }

    /// Tipo atual da faixa.
    pub fn track_kind(&self, i: usize) -> Option<u32> {
        self.lanes.get(i).map(|l| l.kind)
    }

    /// Parâmetro do instrumento da faixa, na unidade da tabela.
    pub fn set_param(&mut self, i: usize, id: u32, value: f32) {
        if !value.is_finite() {
            return;
        }
        if let Some(inst) = self.lanes.get_mut(i).and_then(|l| l.instrument.as_mut()) {
            inst.set_param(id, value);
        }
    }

    /// O áudio (id de [`Engine::load_sample`], 0 = nenhum) que o instrumento da faixa toca. Um id
    /// ainda não carregado fica guardado e é ligado quando o áudio chegar.
    pub fn set_instrument_sample(&mut self, i: usize, sample: u32) {
        let Some(lane) = self.lanes.get_mut(i) else { return };
        lane.sample = sample;
        if let Some(inst) = lane.instrument.as_mut() {
            inst.set_sample(if sample == 0 { None } else { self.samples.get(&sample).cloned() });
        }
    }

    /// Apaga as notas do sequenciador de todas as faixas. As que soam agora terminam no fim
    /// delas (o conjunto das que soam é do motor, não da lista).
    pub fn clear_notes(&mut self) {
        for lane in &mut self.lanes {
            lane.notes.clear();
        }
        self.notes_dirty = true;
    }

    /// Nota do sequenciador: início e duração em batidas absolutas da linha do tempo, altura MIDI
    /// 0..=127 e velocidade 0..=1. Nota vazia, fora da faixa de alturas ou com número inválido é
    /// ignorada.
    pub fn add_note(&mut self, track: usize, start: f64, length: f64, pitch: u32, velocity: f32) {
        let Some(lane) = self.lanes.get_mut(track) else { return };
        if pitch > 127 || !start.is_finite() || !(length > 0.0 && length.is_finite()) {
            return;
        }
        let start = start.max(0.0);
        let velocity = if velocity.is_finite() { velocity.clamp(0.0, 1.0) } else { 0.8 };
        lane.notes.push(Note { start, end: start + length, pitch: pitch as u8, velocity });
        self.notes_dirty = true;
    }

    /// Toca uma nota na hora, fora do sequenciador (teclado, MIDI, prévia do editor): não depende
    /// do transporte e não é solta por seek nem pela volta do loop. Velocidade 0 é note off, como
    /// no MIDI.
    pub fn live_on(&mut self, track: usize, pitch: u32, velocity: f32) {
        if velocity.is_nan() || velocity <= 0.0 {
            self.live_off(track, pitch);
            return;
        }
        if pitch > 127 {
            return;
        }
        if let Some(inst) = self.lanes.get_mut(track).and_then(|l| l.instrument.as_mut()) {
            inst.note_on(pitch as u8, velocity.min(1.0));
        }
    }

    pub fn live_off(&mut self, track: usize, pitch: u32) {
        if pitch > 127 {
            return;
        }
        if let Some(inst) = self.lanes.get_mut(track).and_then(|l| l.instrument.as_mut()) {
            inst.note_off(pitch as u8);
        }
    }

    /// Pânico: corta na hora todo som de instrumento (notas presas, caudas) e o metrônomo. O
    /// transporte segue como estava.
    pub fn panic(&mut self) {
        self.metronome.silence();
        for lane in &mut self.lanes {
            lane.held.clear();
            if let Some(inst) = lane.instrument.as_mut() {
                inst.silence();
            }
        }
    }

    // ---------------------------------------------------------------- áudio

    /// Enche `left` e `right` (mesmo tamanho) com o próximo bloco e avança o transporte.
    pub fn process(&mut self, left: &mut [f32], right: &mut [f32]) {
        self.prepare_notes();
        let n = left.len().min(right.len());
        let mut done = 0;
        while done < n {
            let mut chunk = (n - done).min(MAX_BLOCK);
            // o loop fatia o bloco na volta; tocando depois do fim do loop, segue reto
            let looping = self.playing && self.loop_on && self.pos < self.loop_end;
            if looping {
                let until_end = (self.loop_end - self.pos).ceil().max(1.0) as usize;
                chunk = chunk.min(until_end);
            }
            let (l, r) = (&mut left[done..done + chunk], &mut right[done..done + chunk]);
            self.render(l, r);
            done += chunk;
            if self.playing {
                self.pos += chunk as f64;
                if looping && self.pos >= self.loop_end {
                    self.pos = self.loop_start + (self.pos - self.loop_end);
                    self.wrap_notes();
                }
            }
        }
    }

    /// Reordena as notas mexidas e reposiciona os cursores, entre um bloco e outro.
    fn prepare_notes(&mut self) {
        if self.notes_dirty {
            // sem alocar: o sort instável ordena no lugar (e é linear na lista já ordenada, o caso
            // comum de um reenvio)
            for lane in &mut self.lanes {
                lane.notes.sort_unstable_by(|a, b| a.start.total_cmp(&b.start));
            }
            self.notes_dirty = false;
            self.recue = true;
        }
        if self.recue {
            let fpb = self.beats_to_frames(1.0);
            for lane in &mut self.lanes {
                lane.cue(self.pos, fpb);
            }
            self.recue = false;
        }
    }

    /// Volta do loop: o que o sequenciador segurava é solto no ponto da volta, e as notas do
    /// início do loop disparam no primeiro quadro depois dela.
    fn wrap_notes(&mut self) {
        let fpb = self.beats_to_frames(1.0);
        for lane in &mut self.lanes {
            lane.release_held();
            lane.cue(self.pos, fpb);
        }
    }

    fn render(&mut self, out_l: &mut [f32], out_r: &mut [f32]) {
        out_l.fill(0.0);
        out_r.fill(0.0);
        let n = out_l.len();
        let any_solo = self.tracks.iter().any(|t| t.solo);
        let fpb = self.beats_to_frames(1.0);

        for ti in 0..self.tracks.len() {
            let (bl, br) = (&mut self.buf_l[..n], &mut self.buf_r[..n]);
            bl.fill(0.0);
            br.fill(0.0);
            let mut sounded = false;
            if self.playing {
                sounded = render_clips(&self.clips, &self.samples, ti, bl, br, self.pos, self.bpm, self.rate);
            } else if self.tail > 0 && render_clips(&self.clips, &self.samples, ti, bl, br, self.tail_pos, self.bpm, self.rate) {
                sounded = true;
                let len = self.tail_len as f32;
                for (i, (l, r)) in bl.iter_mut().zip(br.iter_mut()).enumerate() {
                    let g = (self.tail as f32 - i as f32).max(0.0) / len;
                    *l *= g;
                    *r *= g;
                }
            }
            // instrumentos tocam parados também (notas ao vivo e caudas)
            if let Some(lane) = self.lanes.get_mut(ti) {
                sounded |= lane.render(bl, br, self.playing, self.pos, fpb);
            }
            let track = &mut self.tracks[ti];
            let audible = !track.mute && (!any_solo || track.solo);
            if sounded {
                track.apply(bl, br, audible);
                for i in 0..n {
                    out_l[i] += bl[i];
                    out_r[i] += br[i];
                }
            } else {
                track.settle(audible);
            }
        }

        if self.playing {
            let bpm = self.bpm;
            let frames_per_beat = 60.0 / bpm * self.rate;
            self.metronome.render(out_l, out_r, self.pos, frames_per_beat, self.beats_per_bar, self.rate);
        } else if self.tail > 0 {
            self.tail = self.tail.saturating_sub(n);
            self.tail_pos += n as f64;
        }

        let before = self.master.peaks();
        self.master.apply_master(out_l, out_r);
        // NaN que escape de algum instrumento vira silêncio antes do limitador (senão contaminaria
        // o estado dele); depois do limitador a trava só pega o que ele não pegou (nada, em tese)
        for s in out_l.iter_mut().chain(out_r.iter_mut()) {
            if !s.is_finite() {
                *s = 0.0;
            }
        }
        if self.limiter_on {
            self.limiter.process(out_l, out_r);
        }
        for s in out_l.iter_mut().chain(out_r.iter_mut()) {
            *s = s.clamp(-1.0, 1.0);
        }
        self.master.meter(before, out_l, out_r);
    }
}

/// Soma os clipes de áudio da faixa `track` no bloco que começa em `pos` (quadros). Devolve se
/// algum clipe caiu no bloco.
#[allow(clippy::too_many_arguments)]
fn render_clips(clips: &[Clip], samples: &HashMap<u32, Arc<Sample>>, track: usize, bl: &mut [f32], br: &mut [f32], pos: f64, bpm: f64, rate: f64) -> bool {
    let n = bl.len();
    let (start, end) = (pos, pos + n as f64);
    let mut sounded = false;
    for clip in clips.iter().filter(|c| c.track == track) {
        let Some(sample) = samples.get(&clip.sample) else { continue };
        let c_start = clip.start * 60.0 / bpm * rate;
        let c_end = c_start + clip.length * rate;
        if c_end <= start || c_start >= end {
            continue;
        }
        sounded = true;
        let step = sample.rate / rate;
        let stereo = sample.channels.len() > 1;
        let from = ((c_start - start).max(0.0)).ceil() as usize;
        let to = ((c_end - start).min(n as f64)).ceil() as usize;
        for i in from..to.min(n) {
            let t = start + i as f64 - c_start; // quadros desde o início do clipe
            let secs = t / rate;
            let env = fade(secs, clip.length, clip.fade_in, clip.fade_out) * clip.gain;
            let sp = clip.offset * sample.rate + t * step;
            let l = sample.at_cubic(0, sp);
            let r = if stereo { sample.at_cubic(1, sp) } else { l };
            bl[i] += l * env;
            br[i] += r * env;
        }
    }
    sounded
}

/// Envelope de fade de entrada e saída (lineares em amplitude, curva de potência quadrática).
fn fade(t: f64, length: f64, fade_in: f64, fade_out: f64) -> f32 {
    let mut g = 1.0;
    if fade_in > 0.0 && t < fade_in {
        g *= t / fade_in;
    }
    let left = length - t;
    if fade_out > 0.0 && left < fade_out {
        g *= (left / fade_out).max(0.0);
    }
    (g * g) as f32
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Motor sem o limitador do master (o lookahead atrasaria as amostras que os testes medem).
    fn engine() -> Engine {
        let mut e = Engine::new(RATE);
        e.set_limiter(false);
        e
    }

    const RATE: f64 = 48_000.0;

    fn engine_with_dc_clip(start: f64, length: f64) -> Engine {
        let mut e = engine();
        e.set_tempo(120.0, 4); // 1 batida = 0,5 s = 24000 quadros
        e.set_track_count(1);
        e.track_mut(0).unwrap().pan = 0.0;
        e.load_sample(1, Sample::new(vec![vec![0.5; 96_000]], RATE));
        e.add_clip(Clip { track: 0, sample: 1, start, offset: 0.0, length, gain: 1.0, fade_in: 0.0, fade_out: 0.0 });
        e
    }

    fn run(e: &mut Engine, frames: usize) -> (Vec<f32>, Vec<f32>) {
        let (mut l, mut r) = (vec![0.0; frames], vec![0.0; frames]);
        for (cl, cr) in l.chunks_mut(128).zip(r.chunks_mut(128)) {
            e.process(cl, cr);
        }
        (l, r)
    }

    #[test]
    fn parado_e_silencio() {
        let mut e = engine_with_dc_clip(0.0, 1.0);
        let (l, _) = run(&mut e, 1024);
        assert!(l.iter().all(|&s| s == 0.0));
        assert_eq!(e.beat(), 0.0);
    }

    #[test]
    fn clipe_toca_no_lugar_certo() {
        // clipe começa na batida 1 (quadro 24000) e dura 0,25 s (12000 quadros)
        let mut e = engine_with_dc_clip(1.0, 0.25);
        e.play();
        let (l, r) = run(&mut e, 48_000);
        let g = pan_gains(0.0).0 * 0.5;
        assert_eq!(l[23_999], 0.0);
        assert!((l[24_000] - g).abs() < 1e-5, "{}", l[24_000]);
        assert!((r[30_000] - g).abs() < 1e-5);
        assert!((l[35_999] - g).abs() < 1e-5);
        assert_eq!(l[36_000], 0.0);
        assert!((e.beat() - 2.0).abs() < 1e-9);
    }

    #[test]
    fn loop_volta_para_o_inicio() {
        let mut e = engine_with_dc_clip(0.0, 4.0);
        e.set_loop(true, 1.0, 2.0);
        e.seek(1.0);
        e.play();
        run(&mut e, 24_000 + 100);
        assert!((e.frames_to_beats(e.pos) - (1.0 + 100.0 / 24_000.0)).abs() < 1e-9);
    }

    #[test]
    fn stop_desce_o_audio_sem_estalo() {
        let mut e = engine_with_dc_clip(0.0, 2.0);
        e.play();
        run(&mut e, 1280);
        e.stop();
        e.seek(0.0);
        let (l, _) = run(&mut e, 1280);
        let g = pan_gains(0.0).0 * 0.5;
        assert!((l[0] - g).abs() < 0.01, "{}", l[0]);
        let jump = l.windows(2).map(|w| (w[0] - w[1]).abs()).fold(0.0, f32::max);
        assert!(jump < 0.001, "{jump}");
        assert!(l[480..].iter().all(|&s| s == 0.0));
        // tocar de novo não herda o fade
        e.play();
        let (l, _) = run(&mut e, 128);
        assert!((l[0] - g).abs() < 1e-5);
    }

    #[test]
    fn depois_do_fim_do_loop_segue_reto() {
        let mut e = engine_with_dc_clip(0.0, 4.0);
        e.seek(3.0);
        e.set_loop(true, 1.0, 2.0);
        e.play();
        run(&mut e, 1280);
        assert!((e.beat() - (3.0 + 1280.0 / 24_000.0)).abs() < 1e-9);
    }

    #[test]
    fn mudo_e_solo() {
        let mut e = engine_with_dc_clip(0.0, 1.0);
        e.set_track_count(2);
        e.add_clip(Clip { track: 1, sample: 1, start: 0.0, offset: 0.0, length: 1.0, gain: 1.0, fade_in: 0.0, fade_out: 0.0 });
        e.track_mut(1).unwrap().solo = true;
        e.track_mut(1).unwrap().mute = true;
        e.play();
        let (l, _) = run(&mut e, 256);
        // a 1 está em solo mas muda; a 0 não está em solo: silêncio
        assert!(l.iter().all(|&s| s == 0.0));
    }

    #[test]
    fn mudar_andamento_preserva_a_batida() {
        let mut e = engine_with_dc_clip(0.0, 1.0);
        e.seek(3.0);
        e.set_tempo(90.0, 4);
        assert!((e.beat() - 3.0).abs() < 1e-9);
    }

    #[test]
    fn taxa_diferente_e_reamostrada() {
        let mut e = engine();
        e.set_track_count(1);
        // rampa a 24 kHz: no motor a 48 kHz cada amostra do sample vira duas
        let ramp: Vec<f32> = (0..1000).map(|i| i as f32 / 1000.0).collect();
        e.load_sample(7, Sample::new(vec![ramp], 24_000.0));
        e.add_clip(Clip { track: 0, sample: 7, start: 0.0, offset: 0.0, length: 1000.0 / 24_000.0, gain: 1.0, fade_in: 0.0, fade_out: 0.0 });
        e.play();
        let (l, _) = run(&mut e, 256);
        let g = pan_gains(0.0).0;
        assert!((l[2] - 0.001 * g).abs() < 1e-5);
        assert!((l[3] - 0.0015 * g).abs() < 1e-5);
    }

    #[test]
    fn metronomo_clica_na_batida() {
        let mut e = engine();
        e.set_metronome(true, 1.0);
        e.play();
        let (l, _) = run(&mut e, 24_100);
        assert!(l[10..500].iter().any(|s| s.abs() > 0.1));
        assert!(l[20_000..23_999].iter().all(|&s| s == 0.0));
        assert!(l[24_010..24_100].iter().any(|s| s.abs() > 0.1));
    }

    #[test]
    fn hermite_reproduz_retas_e_passa_pelos_pontos() {
        assert!((hermite(1.0, 2.0, 3.0, 4.0, 0.25) - 2.25).abs() < 1e-6);
        assert_eq!(hermite(0.3, -0.7, 0.9, 0.1, 0.0), -0.7);
        assert!((hermite(0.3, -0.7, 0.9, 0.1, 1.0) - 0.9).abs() < 1e-6);
    }

    // ------------------------------------------------------------ instrumentos e notas

    use std::sync::Mutex;

    #[derive(Clone, Debug, PartialEq)]
    enum Ev {
        On(u64, u8),
        Off(u64, u8),
        ReleaseAll(u64),
        Silence(u64),
    }

    type Log = Arc<Mutex<Vec<Ev>>>;

    /// Instrumento de teste: anota cada evento com o quadro em que caiu (conta os quadros que
    /// renderizou; está sempre ativo, então renderiza todos) e soa 0,25 por nota presa.
    struct Probe {
        frame: u64,
        log: Log,
        held: [bool; 128],
    }

    impl Instrument for Probe {
        fn note_on(&mut self, pitch: u8, _velocity: f32) {
            self.log.lock().unwrap().push(Ev::On(self.frame, pitch));
            self.held[pitch as usize] = true;
        }
        fn note_off(&mut self, pitch: u8) {
            self.log.lock().unwrap().push(Ev::Off(self.frame, pitch));
            self.held[pitch as usize] = false;
        }
        fn release_all(&mut self) {
            self.log.lock().unwrap().push(Ev::ReleaseAll(self.frame));
            self.held = [false; 128];
        }
        fn silence(&mut self) {
            self.log.lock().unwrap().push(Ev::Silence(self.frame));
            self.held = [false; 128];
        }
        fn set_param(&mut self, _id: u32, _value: f32) {}
        fn render(&mut self, left: &mut [f32], right: &mut [f32]) {
            let v = self.held.iter().filter(|&&h| h).count() as f32 * 0.25;
            for (l, r) in left.iter_mut().zip(right.iter_mut()) {
                *l += v;
                *r += v;
            }
            self.frame += left.len() as u64;
        }
        fn active(&self) -> bool {
            true
        }
    }

    /// Motor a 120 bpm (24000 quadros por batida) com uma faixa de instrumento de teste.
    fn probe_engine() -> (Engine, Log) {
        let mut e = engine();
        e.set_tempo(120.0, 4);
        e.set_track_count(1);
        e.set_track_kind(0, instrument::kind::SYNTH);
        let log = Log::default();
        e.lanes[0].instrument = Some(Box::new(Probe { frame: 0, log: log.clone(), held: [false; 128] }));
        (e, log)
    }

    fn events(log: &Log) -> Vec<Ev> {
        log.lock().unwrap().clone()
    }

    /// Batidas de um quadro a 120 bpm / 48 kHz.
    fn b(frames: f64) -> f64 {
        frames / 24_000.0
    }

    #[test]
    fn notas_caem_no_quadro_exato() {
        let (mut e, log) = probe_engine();
        e.add_note(0, b(100.0), b(50.0), 60, 0.9);
        e.add_note(0, 0.5, 0.25, 64, 0.9);
        // fora de ordem: o motor ordena
        e.add_note(0, b(130.0), b(1000.0), 62, 0.9);
        e.play();
        run(&mut e, 24_000);
        assert_eq!(events(&log), vec![Ev::On(100, 60), Ev::On(130, 62), Ev::Off(150, 60), Ev::Off(1130, 62), Ev::On(12_000, 64), Ev::Off(18_000, 64)]);
    }

    #[test]
    fn nota_no_quadro_zero_toca_ao_dar_play() {
        let (mut e, log) = probe_engine();
        e.add_note(0, 0.0, 1.0, 60, 0.9);
        e.play();
        run(&mut e, 128);
        assert_eq!(events(&log), vec![Ev::On(0, 60)]);
    }

    #[test]
    fn nota_que_termina_onde_a_mesma_recomeca() {
        let (mut e, log) = probe_engine();
        e.add_note(0, 0.0, 0.5, 60, 0.9);
        e.add_note(0, 0.5, 0.5, 60, 0.9);
        e.play();
        run(&mut e, 30_000);
        assert_eq!(events(&log), vec![Ev::On(0, 60), Ev::Off(12_000, 60), Ev::On(12_000, 60), Ev::Off(24_000, 60)]);
    }

    #[test]
    fn notas_sobrepostas_da_mesma_altura_soltam_no_fim_mais_tardio() {
        let (mut e, log) = probe_engine();
        e.add_note(0, 0.0, 1.0, 60, 0.9);
        e.add_note(0, 0.25, 0.25, 60, 0.9);
        e.play();
        run(&mut e, 30_000);
        assert_eq!(events(&log), vec![Ev::On(0, 60), Ev::On(6000, 60), Ev::Off(24_000, 60)]);
    }

    #[test]
    fn volta_do_loop_solta_e_redispara() {
        let (mut e, log) = probe_engine();
        e.set_loop(true, 0.0, 1.0);
        e.add_note(0, 0.0, 0.25, 60, 0.9);
        // passa do fim do loop: é solta na volta
        e.add_note(0, 0.5, 1.0, 64, 0.9);
        e.play();
        run(&mut e, 48_000 + 128);
        assert_eq!(
            events(&log),
            vec![
                Ev::On(0, 60),
                Ev::Off(6000, 60),
                Ev::On(12_000, 64),
                Ev::Off(24_000, 64),
                Ev::On(24_000, 60),
                Ev::Off(30_000, 60),
                Ev::On(36_000, 64),
                Ev::Off(48_000, 64),
                Ev::On(48_000, 60),
            ]
        );
    }

    #[test]
    fn loop_fora_da_grade_de_blocos() {
        // fim do loop no meio de um bloco de 128: a volta fatia o bloco no ponto certo
        let (mut e, log) = probe_engine();
        e.set_loop(true, 0.0, b(1000.0));
        e.add_note(0, 0.0, b(100.0), 60, 0.9);
        e.play();
        run(&mut e, 2100);
        assert_eq!(events(&log), vec![Ev::On(0, 60), Ev::Off(100, 60), Ev::On(1000, 60), Ev::Off(1100, 60), Ev::On(2000, 60)]);
    }

    #[test]
    fn apagar_as_notas_no_meio_nao_prende() {
        let (mut e, log) = probe_engine();
        e.add_note(0, 0.0, 1.0, 60, 0.9);
        e.play();
        run(&mut e, 6000);
        e.clear_notes();
        run(&mut e, 30_000);
        assert_eq!(events(&log), vec![Ev::On(0, 60), Ev::Off(24_000, 60)]);
    }

    #[test]
    fn reenviar_as_notas_tocando_nao_redispara() {
        let (mut e, log) = probe_engine();
        let send = |e: &mut Engine| {
            e.clear_notes();
            e.add_note(0, 0.0, 1.0, 60, 0.9);
            e.add_note(0, 0.5, 0.25, 62, 0.9);
        };
        send(&mut e);
        e.play();
        for _ in 0..10 {
            run(&mut e, 2560);
            send(&mut e);
        }
        run(&mut e, 10_000);
        assert_eq!(events(&log), vec![Ev::On(0, 60), Ev::On(12_000, 62), Ev::Off(18_000, 62), Ev::Off(24_000, 60)]);
    }

    #[test]
    fn stop_solta_tudo_e_play_no_meio_nao_persegue() {
        let (mut e, log) = probe_engine();
        e.add_note(0, 0.0, 4.0, 60, 0.9);
        e.play();
        run(&mut e, 1280);
        e.stop();
        run(&mut e, 256);
        e.play();
        run(&mut e, 1280);
        assert_eq!(events(&log), vec![Ev::On(0, 60), Ev::ReleaseAll(1280)]);
    }

    #[test]
    fn seek_solta_as_notas_do_sequenciador() {
        let (mut e, log) = probe_engine();
        e.add_note(0, 0.0, 4.0, 60, 0.9);
        e.add_note(0, 2.0, 0.5, 62, 0.9);
        e.play();
        run(&mut e, 1000);
        e.seek(2.0);
        run(&mut e, 256);
        assert_eq!(events(&log), vec![Ev::On(0, 60), Ev::Off(1000, 60), Ev::On(1000, 62)]);
    }

    #[test]
    fn andamento_converte_as_batidas() {
        let (mut e, log) = probe_engine();
        e.set_tempo(60.0, 4); // 1 batida = 48000 quadros
        e.add_note(0, 1.0, 0.5, 60, 0.9);
        e.play();
        run(&mut e, 72_100);
        assert_eq!(events(&log), vec![Ev::On(48_000, 60), Ev::Off(72_000, 60)]);
    }

    #[test]
    fn notas_ao_vivo_independem_do_transporte() {
        let (mut e, log) = probe_engine();
        e.live_on(0, 60, 0.8);
        let (l, _) = run(&mut e, 256);
        assert!(l[10] > 0.0, "parado, a nota ao vivo soa");
        e.add_note(0, 0.0, 4.0, 62, 0.9);
        e.play();
        run(&mut e, 256);
        // seek solta as do sequenciador, não as ao vivo
        e.seek(0.0);
        run(&mut e, 256);
        e.live_off(0, 60);
        e.live_on(0, 64, 0.0); // velocidade 0 = note off
        e.panic();
        let (l, _) = run(&mut e, 256);
        assert_eq!(events(&log), vec![Ev::On(0, 60), Ev::On(256, 62), Ev::Off(512, 62), Ev::On(512, 62), Ev::Off(768, 60), Ev::Off(768, 64), Ev::Silence(768)]);
        assert!(l.iter().all(|&s| s == 0.0));
    }

    #[test]
    fn faixa_muda_nao_soa() {
        let (mut e, _) = probe_engine();
        e.track_mut(0).unwrap().mute = true;
        e.add_note(0, 0.0, 4.0, 60, 0.9);
        e.play();
        let (l, _) = run(&mut e, 1024);
        assert!(l.iter().all(|&s| s == 0.0));
        // tirar o mudo com a nota soando traz o som de volta (a nota seguiu presa, só calada)
        e.track_mut(0).unwrap().mute = false;
        let (l, _) = run(&mut e, 4800);
        assert!(l[4000] > 0.1);
        // e mudar de novo leva a zero sem degrau
        e.track_mut(0).unwrap().mute = true;
        let (l, _) = run(&mut e, 4800);
        let jump = l.windows(2).map(|w| (w[0] - w[1]).abs()).fold(0.0, f32::max);
        assert!(jump < 0.01, "{jump}");
        assert!(l[4799].abs() < 1e-6);
    }

    #[test]
    fn solo_de_instrumento_cala_as_outras() {
        let (mut e, _) = probe_engine();
        e.set_track_count(2);
        e.set_track_kind(1, instrument::kind::SYNTH);
        let log2 = Log::default();
        e.lanes[1].instrument = Some(Box::new(Probe { frame: 0, log: log2, held: [false; 128] }));
        e.track_mut(1).unwrap().solo = true;
        e.add_note(0, 0.0, 1.0, 60, 0.9);
        e.play();
        let (l, _) = run(&mut e, 512);
        assert!(l.iter().all(|&s| s == 0.0));
    }

    #[test]
    fn faixa_de_audio_nao_toca_notas() {
        let mut e = engine();
        e.set_track_count(1);
        e.add_note(0, 0.0, 1.0, 60, 0.9);
        e.live_on(0, 60, 1.0);
        e.play();
        let (l, _) = run(&mut e, 1024);
        assert!(l.iter().all(|&s| s == 0.0));
        assert_eq!(e.track_kind(0), Some(instrument::kind::AUDIO));
    }

    #[test]
    fn trocar_o_tipo_recria_o_instrumento_so_quando_muda() {
        let (mut e, log) = probe_engine();
        // o mesmo tipo de novo (o app manda a cada sync) não mexe no instrumento
        e.set_track_kind(0, instrument::kind::SYNTH);
        e.live_on(0, 60, 1.0);
        assert_eq!(events(&log), vec![Ev::On(0, 60)]);
        e.set_track_kind(0, instrument::kind::AUDIO);
        assert!(e.lanes[0].instrument.is_none());
        e.set_track_kind(0, instrument::kind::SAMPLER);
        assert!(e.lanes[0].instrument.is_some());
    }

    #[test]
    fn notas_invalidas_sao_ignoradas() {
        let (mut e, _) = probe_engine();
        e.add_note(0, 0.0, 0.0, 60, 0.9);
        e.add_note(0, 0.0, 1.0, 128, 0.9);
        e.add_note(0, f64::NAN, 1.0, 60, 0.9);
        e.add_note(0, 0.0, f64::INFINITY, 60, 0.9);
        e.add_note(5, 0.0, 1.0, 60, 0.9);
        assert!(e.lanes[0].notes.is_empty());
    }

    // ------------------------------------------------------------ sampler pelo motor

    fn sampler_engine() -> Engine {
        let mut e = engine();
        e.set_tempo(120.0, 4);
        e.set_track_count(1);
        e.set_track_kind(0, instrument::kind::SAMPLER);
        e.set_param(0, instrument::sampler_param::LEVEL, 1.0);
        e.set_param(0, instrument::sampler_param::VELOCITY, 0.0);
        e
    }

    #[test]
    fn sampler_toca_as_notas_da_faixa() {
        let mut e = sampler_engine();
        e.load_sample(3, Sample::new(vec![vec![0.5; 48_000]], RATE));
        e.set_instrument_sample(0, 3);
        e.add_note(0, 0.5, 0.25, 60, 1.0);
        e.play();
        let (l, _) = run(&mut e, 24_000);
        let g = pan_gains(0.0).0 * 0.5;
        assert!(l[..12_000].iter().all(|&s| s == 0.0));
        assert!((l[14_000] - g).abs() < 1e-4, "{}", l[14_000]);
        // o release (0,2 s) passa do fim do bloco, mas o note off veio no quadro 18000
        assert!(l[23_999] < l[17_999]);
    }

    #[test]
    fn audio_que_chega_depois_da_escolha_e_ligado() {
        let mut e = sampler_engine();
        e.set_instrument_sample(0, 9);
        e.live_on(0, 60, 1.0);
        let (l, _) = run(&mut e, 256);
        assert!(l.iter().all(|&s| s == 0.0), "sem áudio ainda: silêncio");
        e.load_sample(9, Sample::new(vec![vec![0.5; 48_000]], RATE));
        e.live_on(0, 60, 1.0);
        let (l, _) = run(&mut e, 256);
        assert!(l[200] > 0.3);
        // recriar o instrumento (troca de tipo e volta) religa o áudio guardado
        e.set_track_kind(0, instrument::kind::SYNTH);
        e.set_track_kind(0, instrument::kind::SAMPLER);
        e.set_param(0, instrument::sampler_param::VELOCITY, 0.0);
        e.live_on(0, 60, 1.0);
        let (l, _) = run(&mut e, 256);
        assert!(l[200] > 0.2);
    }

    #[test]
    fn caudas_soam_depois_do_stop() {
        let mut e = sampler_engine();
        e.set_param(0, instrument::sampler_param::RELEASE, 0.5);
        e.load_sample(3, Sample::new(vec![vec![0.5; 96_000]], RATE));
        e.set_instrument_sample(0, 3);
        e.add_note(0, 0.0, 4.0, 60, 1.0);
        e.play();
        run(&mut e, 4800);
        e.stop();
        let (l, _) = run(&mut e, 4800);
        assert!(l[4000] > 0.01, "o release continua depois do stop: {}", l[4000]);
        e.panic();
        let (l, _) = run(&mut e, 256);
        assert!(l.iter().all(|&s| s == 0.0));
    }
}
