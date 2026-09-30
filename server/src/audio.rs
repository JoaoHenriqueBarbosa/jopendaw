//! Processamento de áudio das tarefas pesadas (`routes/jobs.rs`): leitura de WAV, codificação FLAC
//! e transcrição de áudio monofônico para notas MIDI (detector de altura YIN). Tudo aqui é puro e
//! síncrono (bytes entram, resultado sai), para rodar dentro de `spawn_blocking` e ser testado sem
//! banco nem disco.

use serde::Serialize;

/// Mensagem das falhas de formato que o usuário pode corrigir (vai para o `error` do job).
pub const UNSUPPORTED: &str = "formato não suportado";

/// Áudio decodificado: amostras intercaladas como inteiros de 24 bits (em `i32`). 24 bits cobre
/// 16, 24 e o float de 32 sem perda relevante, e é o que o FLAC de saída grava.
#[derive(Debug)]
pub struct Pcm {
    pub rate: u32,
    pub channels: usize,
    pub data: Vec<i32>,
}

const I24_MAX: i32 = 8_388_607;
const I24_MIN: i32 = -8_388_608;

fn u16le(b: &[u8], at: usize) -> Option<u16> {
    Some(u16::from_le_bytes(b.get(at..at + 2)?.try_into().ok()?))
}

fn u32le(b: &[u8], at: usize) -> Option<u32> {
    Some(u32::from_le_bytes(b.get(at..at + 4)?.try_into().ok()?))
}

/// Lê um WAV: PCM inteiro de 16, 24 ou 32 bits, ou float de 32 bits (inclusive no formato
/// EXTENSIBLE), mono ou estéreo. O resto (8 bits, 64 bits, 3+ canais, MP3 etc.) é `UNSUPPORTED`.
pub fn decode_wav(bytes: &[u8]) -> Result<Pcm, String> {
    let bad = || UNSUPPORTED.to_string();
    if bytes.len() < 12 || &bytes[0..4] != b"RIFF" || &bytes[8..12] != b"WAVE" {
        return Err(bad());
    }
    let mut pos = 12;
    let mut fmt: Option<(u16, usize, u32, usize)> = None; // (tag, canais, taxa, bits)
    let mut data: Option<&[u8]> = None;
    while pos + 8 <= bytes.len() {
        let id = &bytes[pos..pos + 4];
        let size = u32le(bytes, pos + 4).ok_or_else(bad)? as usize;
        let body = pos + 8;
        // o tamanho do `data` pode mentir (gravação interrompida, 0xFFFFFFFF): vale o que há no arquivo
        let end = body.saturating_add(size).min(bytes.len());
        match id {
            b"fmt " => {
                let chunk = &bytes[body..end];
                let mut tag = u16le(chunk, 0).ok_or_else(bad)?;
                if tag == 0xFFFE {
                    // EXTENSIBLE: o formato de verdade é o início do GUID do subformato
                    tag = u16le(chunk, 24).ok_or_else(bad)?;
                }
                fmt = Some((tag, u16le(chunk, 2).ok_or_else(bad)? as usize, u32le(chunk, 4).ok_or_else(bad)?, u16le(chunk, 14).ok_or_else(bad)? as usize));
            }
            b"data" => {
                data = Some(&bytes[body..end]);
                break;
            }
            _ => {}
        }
        pos = body.saturating_add(size).saturating_add(size & 1);
    }
    let ((tag, channels, rate, bits), data) = fmt.zip(data).ok_or_else(bad)?;
    if !(1..=2).contains(&channels) || rate == 0 || rate > 655_350 {
        return Err(bad());
    }
    let frame = channels * (bits / 8);
    let usable = &data[..data.len() - data.len() % frame.max(1)];
    let samples: Vec<i32> = match (tag, bits) {
        (1, 16) => usable.as_chunks::<2>().0.iter().map(|c| (i16::from_le_bytes(*c) as i32) << 8).collect(),
        (1, 24) => usable.as_chunks::<3>().0.iter().map(|c| i32::from_le_bytes([0, c[0], c[1], c[2]]) >> 8).collect(),
        (1, 32) => usable.as_chunks::<4>().0.iter().map(|c| i32::from_le_bytes(*c) >> 8).collect(),
        (3, 32) => usable
            .as_chunks::<4>()
            .0
            .iter()
            .map(|c| {
                let f = f32::from_le_bytes(*c);
                // NaN vira silêncio; o resto satura em vez de dar a volta
                if f.is_nan() { 0 } else { (f * 8_388_608.0).round().clamp(I24_MIN as f32, I24_MAX as f32) as i32 }
            })
            .collect(),
        _ => return Err(bad()),
    };
    if samples.is_empty() {
        return Err("áudio vazio".into());
    }
    Ok(Pcm { rate, channels, data: samples })
}

impl Pcm {
    /// Mistura os canais em mono, em ponto flutuante de -1 a 1.
    pub fn to_mono(&self) -> Vec<f32> {
        let scale = 1.0 / 8_388_608.0;
        self.data.chunks_exact(self.channels).map(|f| f.iter().map(|&s| s as f32).sum::<f32>() / self.channels as f32 * scale).collect()
    }
}

/// Codifica em FLAC de 24 bits (puro Rust, sem depender de libFLAC instalada).
pub fn encode_flac(pcm: &Pcm) -> Result<Vec<u8>, String> {
    use flacenc::{
        bitsink::ByteSink,
        component::{BitRepr, Stream},
        error::Verify,
        source::{Context, FrameBuf, MemSource, Source},
    };
    let fail = |what: &str, e: &dyn std::fmt::Debug| format!("falha no FLAC ({what}): {e:?}");
    let config = flacenc::config::Encoder::default().into_verified().map_err(|e| fail("configuração", &e))?;
    let block = config.block_size;
    let mut src = MemSource::from_samples(&pcm.data, pcm.channels, 24, pcm.rate as usize);
    let mut stream = Stream::new(pcm.rate as usize, pcm.channels, 24).map_err(|e| fail("cabeçalho", &e))?;
    stream.stream_info_mut().set_block_sizes(block, block).map_err(|e| fail("blocos", &e))?;
    let mut buf = (FrameBuf::with_size(pcm.channels, block).map_err(|e| fail("buffer", &e))?, Context::new(24, pcm.channels));

    // o laço é o do `encode_with_fixed_block_size` do flacenc, aberto para corrigir o cabeçalho no
    // fim (ver abaixo): decodificadores estritos (symphonia, que o motor usa no Android) recusam
    // o arquivo que a função pronta entrega
    let mut frame_number = 0usize;
    while src.read_samples(block, &mut buf).map_err(|e| fail("leitura", &e))? > 0 {
        let frame = flacenc::encode_fixed_size_frame(&config, &buf.0, frame_number, stream.stream_info()).map_err(|e| fail("quadro", &e))?;
        stream.add_frame(frame);
        frame_number += 1;
    }
    stream.stream_info_mut().set_md5_digest(&buf.1.md5_digest());
    let total = pcm.data.len() / pcm.channels;
    stream.stream_info_mut().set_total_samples(total);
    // `add_frame` baixa o mínimo para o tamanho do último quadro (mais curto), o que declara um
    // fluxo de bloco variável e faz os decodificadores lerem o número do quadro como número de
    // amostra. Mínimo igual ao máximo é o que diz "bloco fixo, o último pode ser menor".
    let fixed = if frame_number > 1 { block } else { total.min(block) };
    stream.stream_info_mut().set_block_sizes(fixed, fixed).map_err(|e| fail("blocos", &e))?;

    let mut sink = ByteSink::new();
    stream.write(&mut sink).map_err(|e| fail("gravação", &e))?;
    Ok(sink.as_slice().to_vec())
}

// ---------------------------------------------------------------- áudio para MIDI

const FRAME: usize = 2048;
const HOP: usize = 512;
/// A janela de integração do YIN é metade do quadro; o maior período medido cabe nela.
const WINDOW: usize = FRAME / 2;
const YIN_THRESHOLD: f32 = 0.15;
const MIN_HZ: f32 = 50.0;
const MAX_HZ: f32 = 2000.0;
const MEDIAN_FRAMES: usize = 5;
/// Mudança de altura (em semitons) que conta como outra nota, e por quantos quadros seguidos.
const SPLIT_SEMITONES: f32 = 0.7;
const SPLIT_FRAMES: usize = 3;

#[derive(Clone, Copy, Debug)]
pub struct MidiParams {
    pub min_note_ms: f32,
    pub rms_floor_db: f32,
}

impl Default for MidiParams {
    fn default() -> Self {
        MidiParams { min_note_ms: 60.0, rms_floor_db: -45.0 }
    }
}

#[derive(Clone, Debug, Serialize, PartialEq)]
pub struct Note {
    pub pitch: u8,
    pub start: f64,
    pub length: f64,
    pub velocity: f32,
}

/// Altura (Hz) de um quadro de `FRAME` amostras pelo YIN: diferença, normalização cumulativa,
/// primeiro mínimo abaixo do limiar e interpolação parabólica. `None` quando não há altura clara.
fn yin_pitch(x: &[f32], rate: f32, diff: &mut Vec<f32>) -> Option<f32> {
    let tau_max = ((rate / MIN_HZ) as usize).min(WINDOW - 1);
    let tau_min = ((rate / MAX_HZ) as usize).max(2);
    if tau_min + 1 >= tau_max {
        return None;
    }
    diff.clear();
    diff.resize(tau_max + 2, 0.0);
    for tau in 1..=tau_max + 1 {
        let mut sum = 0.0f32;
        for j in 0..WINDOW {
            let d = x[j] - x[j + tau];
            sum += d * d;
        }
        diff[tau] = sum;
    }
    // diferença normalizada pela média cumulativa (d'): tira o viés de favorecer períodos curtos
    let mut running = 0.0f32;
    let mut norm = vec![1.0f32; tau_max + 2];
    for tau in 1..=tau_max + 1 {
        running += diff[tau];
        norm[tau] = if running > 0.0 { diff[tau] * tau as f32 / running } else { 1.0 };
    }
    let mut tau = tau_min;
    while tau <= tau_max {
        if norm[tau] < YIN_THRESHOLD {
            while tau < tau_max && norm[tau + 1] < norm[tau] {
                tau += 1;
            }
            let (a, b, c) = (norm[tau - 1], norm[tau], norm[tau + 1]);
            let denom = a - 2.0 * b + c;
            let shift = if denom.abs() > 1e-9 { (0.5 * (a - c) / denom).clamp(-1.0, 1.0) } else { 0.0 };
            let hz = rate / (tau as f32 + shift);
            return (MIN_HZ..=MAX_HZ).contains(&hz).then_some(hz);
        }
        tau += 1;
    }
    None
}

/// Uma nota em construção: os quadros já somados a ela.
struct Open {
    start: usize,
    end: usize, // exclusivo
    pitches: Vec<f32>,
    pitch_sum: f32,
    rms: Vec<f32>,
}

impl Open {
    fn new(i: usize, pitch: f32, rms: f32) -> Self {
        Open { start: i, end: i + 1, pitches: vec![pitch], pitch_sum: pitch, rms: vec![rms] }
    }
    fn push(&mut self, i: usize, pitch: Option<f32>, rms: f32) {
        self.end = i + 1;
        self.rms.push(rms);
        if let Some(p) = pitch {
            self.pitches.push(p);
            self.pitch_sum += p;
        }
    }
    fn reference(&self) -> f32 {
        self.pitch_sum / self.pitches.len() as f32
    }
}

fn median(v: &mut [f32]) -> f32 {
    v.sort_by(|a, b| a.total_cmp(b));
    v[v.len() / 2]
}

/// Transcreve áudio monofônico (já em mono, -1..1) em notas. `progress` recebe 0..1.
pub fn audio_to_midi(mono: &[f32], rate: u32, params: MidiParams, progress: &dyn Fn(f32)) -> Vec<Note> {
    // taxas altas viram ~30 kHz por média de blocos: os 2048 do quadro continuam cobrindo 50 Hz
    let k = (rate / 30_000).max(1) as usize;
    let decimated: Vec<f32>;
    let x: &[f32] = if k > 1 {
        decimated = mono.chunks_exact(k).map(|c| c.iter().sum::<f32>() / k as f32).collect();
        &decimated
    } else {
        mono
    };
    let rate_f = rate as f32 / k as f32;
    if x.len() < FRAME {
        return Vec::new();
    }
    let frames = (x.len() - FRAME) / HOP + 1;

    // 1. uma altura (semitons MIDI, fracionário) e uma energia por quadro
    let mut pitch: Vec<Option<f32>> = Vec::with_capacity(frames);
    let mut rms: Vec<f32> = Vec::with_capacity(frames);
    let mut silent: Vec<bool> = Vec::with_capacity(frames);
    let floor_lin = 10f32.powf(params.rms_floor_db / 20.0);
    let mut diff = Vec::new();
    for i in 0..frames {
        let frame = &x[i * HOP..i * HOP + FRAME];
        let r = (frame.iter().map(|s| s * s).sum::<f32>() / FRAME as f32).sqrt();
        rms.push(r);
        silent.push(r < floor_lin);
        // quadro em silêncio não gasta o YIN (a parte cara)
        pitch.push(if r < floor_lin { None } else { yin_pitch(frame, rate_f, &mut diff).map(|hz| 69.0 + 12.0 * (hz / 440.0).log2()) });
        if i % 64 == 0 {
            progress(i as f32 / frames as f32);
        }
    }

    // 2. mediana de 5 quadros sobre as alturas: tira os saltos de oitava de um quadro só
    let smoothed: Vec<Option<f32>> = (0..frames)
        .map(|i| {
            pitch[i]?;
            let lo = i.saturating_sub(MEDIAN_FRAMES / 2);
            let hi = (i + MEDIAN_FRAMES / 2 + 1).min(frames);
            let mut w: Vec<f32> = pitch[lo..hi].iter().flatten().copied().collect();
            Some(median(&mut w))
        })
        .collect();

    // 3. segmentação em notas
    let mut closed: Vec<Open> = Vec::new();
    let mut cur: Option<Open> = None;
    // quadros seguidos que destoam da nota aberta: com SPLIT_FRAMES deles, nasce a nota seguinte
    let mut pending: Vec<(usize, f32, f32)> = Vec::new();
    for i in 0..frames {
        if silent[i] {
            if let Some(mut o) = cur.take() {
                for (j, p, r) in pending.drain(..) {
                    o.push(j, Some(p), r);
                }
                closed.push(o);
            }
            pending.clear();
            continue;
        }
        let Some(p) = smoothed[i] else {
            // com energia mas sem altura clara (transiente, ruído): continua a nota aberta
            if let Some(o) = cur.as_mut() {
                o.push(i, None, rms[i]);
            }
            continue;
        };
        match cur.as_mut() {
            None => cur = Some(Open::new(i, p, rms[i])),
            Some(o) if (p - o.reference()).abs() >= SPLIT_SEMITONES => {
                pending.push((i, p, rms[i]));
                if pending.len() >= SPLIT_FRAMES {
                    let first = pending[0].0;
                    let mut old = cur.take().expect("nota aberta");
                    old.end = first;
                    closed.push(old);
                    let mut next = Open::new(first, pending[0].1, pending[0].2);
                    for &(j, pp, r) in &pending[1..] {
                        next.push(j, Some(pp), r);
                    }
                    pending.clear();
                    cur = Some(next);
                }
            }
            Some(o) => {
                for (j, pp, r) in pending.drain(..) {
                    o.push(j, Some(pp), r);
                }
                o.push(i, Some(p), rms[i]);
            }
        }
    }
    if let Some(mut o) = cur.take() {
        for (j, pp, r) in pending.drain(..) {
            o.push(j, Some(pp), r);
        }
        closed.push(o);
    }

    // 4. notas em segundos; descarta as curtas demais
    let secs = |frames: usize| frames as f64 * HOP as f64 / rate_f as f64;
    let floor_db = params.rms_floor_db;
    let notes = closed
        .into_iter()
        .filter_map(|mut o| {
            let length = secs(o.end - o.start);
            if length * 1000.0 < params.min_note_ms as f64 {
                return None;
            }
            let pitch = median(&mut o.pitches).round().clamp(0.0, 127.0) as u8;
            // início do quadro = centro menos meio passo (cada quadro representa um passo de 512)
            let start = ((o.start * HOP + FRAME / 2) as f64 - HOP as f64 / 2.0) / rate_f as f64;
            let mean_rms = o.rms.iter().sum::<f32>() / o.rms.len() as f32;
            let db = 20.0 * mean_rms.max(1e-9).log10();
            // do piso (-45 dBFS) a -6 dBFS vai de 0 a 1; nunca zero, que em MIDI é note-off
            let velocity = ((db - floor_db) / (-6.0 - floor_db)).clamp(0.05, 1.0);
            Some(Note { pitch, start: start.max(0.0), length, velocity })
        })
        .collect();
    progress(1.0);
    notes
}

#[cfg(test)]
mod tests {
    use super::*;

    const RATE: u32 = 44_100;

    fn sine(hz: f32, secs: f32, amp: f32) -> Vec<f32> {
        (0..(RATE as f32 * secs) as usize).map(|i| amp * (std::f32::consts::TAU * hz * i as f32 / RATE as f32).sin()).collect()
    }

    fn silence(secs: f32) -> Vec<f32> {
        vec![0.0; (RATE as f32 * secs) as usize]
    }

    fn run(x: &[f32], p: MidiParams) -> Vec<Note> {
        audio_to_midi(x, RATE, p, &|_| {})
    }

    fn wav(tag: u16, bits: u16, channels: u16, rate: u32, payload: &[u8]) -> Vec<u8> {
        let block = channels * bits / 8;
        let mut v = b"RIFF".to_vec();
        v.extend((36 + payload.len() as u32).to_le_bytes());
        v.extend(b"WAVEfmt ");
        v.extend(16u32.to_le_bytes());
        v.extend(tag.to_le_bytes());
        v.extend(channels.to_le_bytes());
        v.extend(rate.to_le_bytes());
        v.extend((rate * block as u32).to_le_bytes());
        v.extend(block.to_le_bytes());
        v.extend(bits.to_le_bytes());
        v.extend(b"data");
        v.extend((payload.len() as u32).to_le_bytes());
        v.extend(payload);
        v
    }

    #[test]
    fn yin_acha_a_altura_de_senoides() {
        let mut diff = Vec::new();
        for hz in [82.41f32, 110.0, 220.0, 440.0, 880.0, 1760.0] {
            let x = sine(hz, 0.2, 0.5);
            let got = yin_pitch(&x[1000..1000 + FRAME], RATE as f32, &mut diff).unwrap_or_else(|| panic!("sem altura em {hz} Hz"));
            assert!((got - hz).abs() / hz < 0.005, "{hz} Hz lido como {got}");
        }
    }

    #[test]
    fn yin_ignora_ruido_e_silencio() {
        let mut diff = Vec::new();
        assert!(yin_pitch(&vec![0.0; FRAME], RATE as f32, &mut diff).is_none());
        // ruído determinístico (LCG)
        let mut s = 12345u32;
        let noise: Vec<f32> = (0..FRAME)
            .map(|_| {
                s = s.wrapping_mul(1_664_525).wrapping_add(1_013_904_223);
                (s >> 8) as f32 / 8_388_608.0 - 1.0
            })
            .collect();
        assert!(yin_pitch(&noise, RATE as f32, &mut diff).is_none());
    }

    #[test]
    fn duas_notas_separadas_por_silencio() {
        let mut x = sine(440.0, 0.5, 0.5);
        x.extend(silence(0.2));
        x.extend(sine(660.0, 0.5, 0.25));
        let notes = run(&x, MidiParams::default());
        assert_eq!(notes.len(), 2, "{notes:?}");
        assert_eq!((notes[0].pitch, notes[1].pitch), (69, 76));
        assert!((notes[0].start - 0.0).abs() < 0.08 && (notes[0].length - 0.5).abs() < 0.1, "{notes:?}");
        assert!((notes[1].start - 0.7).abs() < 0.08 && (notes[1].length - 0.5).abs() < 0.1, "{notes:?}");
        assert!(notes[0].velocity > notes[1].velocity, "a nota mais forte tem velocity maior");
        assert!(notes.iter().all(|n| (0.0..=1.0).contains(&n.velocity)));
    }

    #[test]
    fn mudanca_de_altura_sem_silencio_divide_a_nota() {
        let mut x = sine(440.0, 0.4, 0.5);
        x.extend(sine(523.25, 0.4, 0.5)); // dó 5, três semitons acima
        let notes = run(&x, MidiParams::default());
        assert_eq!(notes.iter().map(|n| n.pitch).collect::<Vec<_>>(), vec![69, 72], "{notes:?}");
        assert!((notes[1].start - 0.4).abs() < 0.08, "{notes:?}");
    }

    #[test]
    fn vibrato_pequeno_nao_divide() {
        // 440 Hz com ±0,3 semitom de vibrato a 5 Hz: continua uma nota só
        let mut phase = 0.0f32;
        let x: Vec<f32> = (0..(RATE as f32 * 0.8) as usize)
            .map(|i| {
                let t = i as f32 / RATE as f32;
                let hz = 440.0 * 2f32.powf(0.3 * (std::f32::consts::TAU * 5.0 * t).sin() / 12.0);
                phase += std::f32::consts::TAU * hz / RATE as f32;
                0.5 * phase.sin()
            })
            .collect();
        let notes = run(&x, MidiParams::default());
        assert_eq!(notes.len(), 1, "{notes:?}");
        assert_eq!(notes[0].pitch, 69);
    }

    #[test]
    fn descarta_notas_curtas_e_respeita_parametros() {
        let mut x = sine(440.0, 0.05, 0.5);
        x.extend(silence(0.3));
        x.extend(sine(440.0, 0.3, 0.5));
        assert_eq!(run(&x, MidiParams::default()).len(), 1);
        // com o mínimo em 0 a nota de 50 ms aparece (se houver quadros suficientes)
        assert!(!run(&x, MidiParams { min_note_ms: 0.0, ..Default::default() }).is_empty());
        // piso de ruído alto demais: a nota fraca some
        let quiet = sine(440.0, 0.5, 0.005); // cerca de -49 dBFS de RMS
        assert!(run(&quiet, MidiParams::default()).is_empty());
        assert_eq!(run(&quiet, MidiParams { rms_floor_db: -70.0, ..Default::default() }).len(), 1);
    }

    #[test]
    fn audio_curto_ou_mudo_nao_gera_notas() {
        assert!(run(&[0.0; 100], MidiParams::default()).is_empty());
        assert!(run(&silence(1.0), MidiParams::default()).is_empty());
    }

    #[test]
    fn taxa_alta_e_decimada() {
        let rate = 96_000u32;
        let x: Vec<f32> = (0..rate as usize / 2).map(|i| 0.5 * (std::f32::consts::TAU * 110.0 * i as f32 / rate as f32).sin()).collect();
        let notes = audio_to_midi(&x, rate, MidiParams::default(), &|_| {});
        assert_eq!(notes.len(), 1);
        assert_eq!(notes[0].pitch, 45); // lá 2
    }

    #[test]
    fn wav_pcm16_estereo_vira_24_bits() {
        let payload: Vec<u8> = [1000i16, -1000, 32767, -32768].iter().flat_map(|s| s.to_le_bytes()).collect();
        let pcm = decode_wav(&wav(1, 16, 2, 44_100, &payload)).unwrap();
        assert_eq!((pcm.channels, pcm.rate), (2, 44_100));
        assert_eq!(pcm.data, vec![1000 << 8, -1000 << 8, 32767 << 8, -32768 << 8]);
    }

    #[test]
    fn wav_24_32_e_float() {
        let p24: Vec<u8> = [0x7FFFFFi32, -0x800000].iter().flat_map(|s| s.to_le_bytes()[..3].to_vec()).collect();
        assert_eq!(decode_wav(&wav(1, 24, 1, 48_000, &p24)).unwrap().data, vec![0x7FFFFF, -0x800000]);
        let p32: Vec<u8> = [i32::MAX, i32::MIN].iter().flat_map(|s| s.to_le_bytes()).collect();
        assert_eq!(decode_wav(&wav(1, 32, 1, 48_000, &p32)).unwrap().data, vec![0x7FFFFF, -0x800000]);
        let pf: Vec<u8> = [0.5f32, -2.0, f32::NAN].iter().flat_map(|s| s.to_le_bytes()).collect();
        assert_eq!(decode_wav(&wav(3, 32, 1, 48_000, &pf)).unwrap().data, vec![0x400000, -0x800000, 0]);
    }

    #[test]
    fn wav_nao_suportado() {
        assert_eq!(decode_wav(b"nao sou wav").unwrap_err(), UNSUPPORTED);
        assert_eq!(decode_wav(&wav(1, 8, 1, 8000, &[1, 2, 3])).unwrap_err(), UNSUPPORTED);
        assert_eq!(decode_wav(&wav(1, 16, 6, 48_000, &[0; 12])).unwrap_err(), UNSUPPORTED);
        assert_eq!(decode_wav(&wav(3, 64, 1, 48_000, &[0; 16])).unwrap_err(), UNSUPPORTED);
    }

    #[test]
    fn flac_ida_e_volta_sem_perda() {
        roundtrip(2, 44_100); // vários quadros, o último mais curto
        roundtrip(1, 1000); // um quadro só, curto
        roundtrip(2, 4096); // exatamente um bloco
    }

    fn roundtrip(channels: usize, n: usize) {
        use symphonia::core::{audio::SampleBuffer, codecs::DecoderOptions, formats::FormatOptions, io::MediaSourceStream, meta::MetadataOptions, probe::Hint};
        // conteúdo diferente em cada canal, em 16 bits (viram 24 pelo <<8)
        let mut payload = Vec::new();
        let mut expected = Vec::new();
        for i in 0..n {
            let l = (12_000.0 * (std::f32::consts::TAU * 440.0 * i as f32 / 44_100.0).sin()) as i16;
            let r = (9_000.0 * (std::f32::consts::TAU * 660.0 * i as f32 / 44_100.0).sin()) as i16;
            payload.extend(l.to_le_bytes());
            expected.push((l as i32) << 8);
            if channels == 2 {
                payload.extend(r.to_le_bytes());
                expected.push((r as i32) << 8);
            }
        }
        let pcm = decode_wav(&wav(1, 16, channels as u16, 44_100, &payload)).unwrap();
        let flac = encode_flac(&pcm).unwrap();
        assert_eq!(&flac[..4], b"fLaC");
        if n > 10_000 {
            assert!(flac.len() < payload.len(), "o FLAC deveria ser menor que o WAV de 16 bits");
        }

        let mss = MediaSourceStream::new(Box::new(std::io::Cursor::new(flac)), Default::default());
        let mut format = symphonia::default::get_probe().format(&Hint::new(), mss, &FormatOptions::default(), &MetadataOptions::default()).unwrap().format;
        let track = format.default_track().unwrap().clone();
        assert_eq!(track.codec_params.sample_rate, Some(44_100));
        assert_eq!(track.codec_params.bits_per_sample, Some(24));
        let mut decoder = symphonia::default::get_codecs().make(&track.codec_params, &DecoderOptions::default()).unwrap();
        let mut got: Vec<i32> = Vec::new();
        while let Ok(packet) = format.next_packet() {
            let buf = decoder.decode(&packet).unwrap();
            let mut s = SampleBuffer::<i32>::new(buf.frames() as u64, *buf.spec());
            s.copy_interleaved_ref(buf);
            // o symphonia entrega inteiros alinhados a 32 bits: 24 bits valem `>> 8`
            got.extend(s.samples().iter().map(|v| v >> 8));
        }
        assert_eq!(got, expected);
    }
}
