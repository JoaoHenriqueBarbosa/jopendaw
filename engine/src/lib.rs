//! Motor de áudio do jopendaw.
//!
//! Tudo o que soa passa por aqui: o transporte (tocar, parar, loop), os clipes de áudio na linha do
//! tempo, o mixer (volume, pan, mudo, solo) e o metrônomo. O crate não sabe de plataforma: quem o
//! hospeda (o AudioWorklet na web, o Oboe no Android) chama [`Engine::process`] com blocos de
//! amostras e manda os comandos entre um bloco e outro, na mesma thread de áudio.
//!
//! O tempo da linha do tempo é contado em quadros (amostras por canal) na taxa do motor; posições
//! do documento chegam em tempos musicais (batidas) e viram quadros pelo andamento.

pub mod drums;
pub mod dsp;
pub mod instrument;
mod metronome;
mod mixer;
pub mod sampler;
pub mod synth;

use std::collections::HashMap;

pub use metronome::Metronome;
pub use mixer::{Track, pan_gains};

/// Maior bloco processado de uma vez; blocos maiores são fatiados.
pub const MAX_BLOCK: usize = 4096;

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

    pub fn rate(&self) -> f64 {
        self.rate
    }

    pub fn duration(&self) -> f64 {
        self.frames() as f64 / self.rate
    }

    /// Amostra em `pos` (quadro fracionário) com interpolação linear; fora do áudio é silêncio.
    pub fn at(&self, ch: usize, pos: f64) -> f32 {
        let data = &self.channels[ch.min(self.channels.len() - 1)];
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
    samples: HashMap<u32, Sample>,
    clips: Vec<Clip>,
    tracks: Vec<Track>,
    master: Track,
    metronome: Metronome,
    buf_l: Vec<f32>,
    buf_r: Vec<f32>,
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
            master: Track::default(),
            metronome: Metronome::default(),
            buf_l: vec![0.0; MAX_BLOCK],
            buf_r: vec![0.0; MAX_BLOCK],
        }
    }

    pub fn rate(&self) -> f64 {
        self.rate
    }

    // ---------------------------------------------------------------- andamento e posição

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

    pub fn play(&mut self) {
        self.playing = true;
    }

    pub fn stop(&mut self) {
        self.playing = false;
        self.metronome.silence();
    }

    pub fn seek(&mut self, beat: f64) {
        self.pos = self.beats_to_frames(beat.max(0.0));
        self.metronome.silence();
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

    pub fn load_sample(&mut self, id: u32, sample: Sample) {
        self.samples.insert(id, sample);
    }

    pub fn drop_sample(&mut self, id: u32) {
        self.samples.remove(&id);
    }

    pub fn set_track_count(&mut self, n: usize) {
        self.tracks.resize_with(n, Track::default);
    }

    pub fn track_mut(&mut self, i: usize) -> Option<&mut Track> {
        self.tracks.get_mut(i)
    }

    pub fn tracks(&self) -> &[Track] {
        &self.tracks
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

    // ---------------------------------------------------------------- áudio

    /// Enche `left` e `right` (mesmo tamanho) com o próximo bloco e avança o transporte.
    pub fn process(&mut self, left: &mut [f32], right: &mut [f32]) {
        let n = left.len().min(right.len());
        let mut done = 0;
        while done < n {
            let mut chunk = (n - done).min(MAX_BLOCK);
            // o loop fatia o bloco na volta
            if self.playing && self.loop_on && self.pos < self.loop_end {
                let until_end = (self.loop_end - self.pos).ceil().max(1.0) as usize;
                chunk = chunk.min(until_end);
            }
            let (l, r) = (&mut left[done..done + chunk], &mut right[done..done + chunk]);
            self.render(l, r);
            done += chunk;
            if self.playing {
                self.pos += chunk as f64;
                if self.loop_on && self.pos >= self.loop_end && self.loop_end > self.loop_start {
                    self.pos = self.loop_start + (self.pos - self.loop_end);
                }
            }
        }
    }

    fn render(&mut self, out_l: &mut [f32], out_r: &mut [f32]) {
        out_l.fill(0.0);
        out_r.fill(0.0);
        let n = out_l.len();
        let any_solo = self.tracks.iter().any(|t| t.solo);

        if self.playing {
            let (start, end) = (self.pos, self.pos + n as f64);
            for ti in 0..self.tracks.len() {
                let (bl, br) = (&mut self.buf_l[..n], &mut self.buf_r[..n]);
                bl.fill(0.0);
                br.fill(0.0);
                let mut sounded = false;
                for clip in self.clips.iter().filter(|c| c.track == ti) {
                    let Some(sample) = self.samples.get(&clip.sample) else { continue };
                    let c_start = clip.start * 60.0 / self.bpm * self.rate;
                    let c_end = c_start + clip.length * self.rate;
                    if c_end <= start || c_start >= end {
                        continue;
                    }
                    sounded = true;
                    let step = sample.rate / self.rate;
                    let stereo = sample.channels.len() > 1;
                    let from = ((c_start - start).max(0.0)).ceil() as usize;
                    let to = ((c_end - start).min(n as f64)).ceil() as usize;
                    for i in from..to.min(n) {
                        let t = start + i as f64 - c_start; // quadros desde o início do clipe
                        let secs = t / self.rate;
                        let env = fade(secs, clip.length, clip.fade_in, clip.fade_out) * clip.gain;
                        let sp = clip.offset * sample.rate + t * step;
                        let l = sample.at(0, sp);
                        let r = if stereo { sample.at(1, sp) } else { l };
                        bl[i] += l * env;
                        br[i] += r * env;
                    }
                }
                let track = &mut self.tracks[ti];
                let audible = !track.mute && (!any_solo || track.solo);
                if sounded && audible {
                    track.apply(bl, br);
                    for i in 0..n {
                        out_l[i] += bl[i];
                        out_r[i] += br[i];
                    }
                }
            }
        }

        if self.playing {
            let bpm = self.bpm;
            let frames_per_beat = 60.0 / bpm * self.rate;
            self.metronome.render(out_l, out_r, self.pos, frames_per_beat, self.beats_per_bar, self.rate);
        }

        self.master.apply_master(out_l, out_r);
        // sem limiter ainda: pelo menos nada passa de 0 dBFS no conversor
        for s in out_l.iter_mut().chain(out_r.iter_mut()) {
            *s = s.clamp(-1.0, 1.0);
        }
    }
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

    const RATE: f64 = 48_000.0;

    fn engine_with_dc_clip(start: f64, length: f64) -> Engine {
        let mut e = Engine::new(RATE);
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
        let mut e = Engine::new(RATE);
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
        let mut e = Engine::new(RATE);
        e.set_metronome(true, 1.0);
        e.play();
        let (l, _) = run(&mut e, 24_100);
        assert!(l[10..500].iter().any(|s| s.abs() > 0.1));
        assert!(l[20_000..23_999].iter().all(|&s| s == 0.0));
        assert!(l[24_010..24_100].iter().any(|s| s.abs() > 0.1));
    }
}
