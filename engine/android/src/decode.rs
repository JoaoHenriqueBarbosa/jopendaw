//! Decodificação de áudio importado (o `decodeAudioData` do navegador, aqui pelo symphonia): WAV,
//! AIFF, CAF, FLAC, MP3, Ogg Vorbis, AAC e ALAC (M4A). O formato é descoberto pelo conteúdo.
//!
//! Sai em f32, um ou dois canais, na taxa do arquivo (o motor converte a taxa ao tocar, e o
//! `DecodedAudio` do Dart leva a taxa junto). Mais de dois canais ficam com os dois primeiros
//! (frente esquerda e direita em todo layout comum). Pacote corrompido no meio é pulado, como os
//! decodificadores fazem; arquivo truncado fica com o que deu para ler; nenhum áudio é falha.
//! Memória é pedida com `try_reserve`: um arquivo grande demais falha em vez de derrubar o app.

use std::collections::HashMap;
use std::io::Cursor;
use std::sync::Mutex;
use std::sync::atomic::{AtomicU64, Ordering};

use symphonia::core::audio::{AudioBuffer, AudioBufferRef, Signal};
use symphonia::core::codecs::{CODEC_TYPE_NULL, DecoderOptions};
use symphonia::core::errors::Error;
use symphonia::core::formats::FormatOptions;
use symphonia::core::io::MediaSourceStream;
use symphonia::core::meta::MetadataOptions;
use symphonia::core::probe::Hint;

/// Áudio decodificado.
pub struct Decoded {
    pub channels: Vec<Vec<f32>>,
    pub rate: f64,
}

impl Decoded {
    pub fn frames(&self) -> usize {
        self.channels.first().map_or(0, Vec::len)
    }
}

/// Por que não decodificou (para o log e os testes; o Dart só recebe o handle 0).
#[derive(Debug, PartialEq, Eq)]
pub enum DecodeFail {
    /// Formato desconhecido ou arquivo que não é áudio.
    Format,
    /// Sem faixa de áudio, ou um codec que este build não tem.
    Codec,
    /// Nada decodificou.
    Empty,
    /// Não coube na memória.
    Memory,
}

/// Decodifica os bytes de um arquivo inteiro.
pub fn decode(bytes: &[u8]) -> Result<Decoded, DecodeFail> {
    let mut owned = Vec::new();
    owned.try_reserve_exact(bytes.len()).map_err(|_| DecodeFail::Memory)?;
    owned.extend_from_slice(bytes);
    let mss = MediaSourceStream::new(Box::new(Cursor::new(owned)), Default::default());
    // o encoder põe silêncio no começo e no fim (MP3, AAC); com gapless ele sai, e um loop fecha
    let fmt = FormatOptions { enable_gapless: true, ..Default::default() };
    let probed = symphonia::default::get_probe().format(&Hint::new(), mss, &fmt, &MetadataOptions::default()).map_err(|_| DecodeFail::Format)?;
    let mut format = probed.format;
    let track = format.tracks().iter().find(|t| t.codec_params.codec != CODEC_TYPE_NULL).ok_or(DecodeFail::Codec)?;
    let track_id = track.id;
    let mut rate = track.codec_params.sample_rate.unwrap_or(0);
    let mut decoder = symphonia::default::get_codecs().make(&track.codec_params, &DecoderOptions::default()).map_err(|_| DecodeFail::Codec)?;

    let mut out: Vec<Vec<f32>> = Vec::new();
    let mut conv: Option<AudioBuffer<f32>> = None;
    loop {
        let packet = match format.next_packet() {
            Ok(p) => p,
            // fim do arquivo (ou dele truncado): fica o que deu para ler
            Err(Error::IoError(_)) => break,
            Err(Error::ResetRequired) => {
                decoder.reset();
                continue;
            }
            Err(_) if !out.is_empty() => break,
            Err(_) => return Err(DecodeFail::Format),
        };
        if packet.track_id() != track_id {
            continue;
        }
        let buf = match decoder.decode(&packet) {
            Ok(b) => b,
            // pacote corrompido: pula e segue
            Err(Error::DecodeError(_)) => continue,
            Err(Error::IoError(_)) => break,
            Err(Error::ResetRequired) => {
                decoder.reset();
                continue;
            }
            Err(_) if !out.is_empty() => break,
            Err(_) => return Err(DecodeFail::Codec),
        };
        if buf.frames() == 0 {
            continue;
        }
        if rate == 0 {
            rate = buf.spec().rate;
        }
        append(&buf, &mut conv, &mut out)?;
    }
    if out.is_empty() || out[0].is_empty() || rate == 0 {
        return Err(DecodeFail::Empty);
    }
    Ok(Decoded { channels: out, rate: rate as f64 })
}

/// Junta um pacote decodificado nos canais de saída (1 ou 2, fixados pelo primeiro pacote).
fn append(buf: &AudioBufferRef<'_>, conv: &mut Option<AudioBuffer<f32>>, out: &mut Vec<Vec<f32>>) -> Result<(), DecodeFail> {
    let spec = *buf.spec();
    let fits = conv.as_ref().is_some_and(|c| c.capacity() >= buf.capacity() && *c.spec() == spec);
    if !fits {
        *conv = Some(buf.make_equivalent::<f32>());
    }
    let Some(c) = conv.as_mut() else { return Err(DecodeFail::Memory) };
    buf.convert(c);
    let have = spec.channels.count();
    if have == 0 {
        return Ok(());
    }
    if out.is_empty() {
        out.resize_with(have.min(2), Vec::new);
    }
    let frames = c.frames();
    for (k, dst) in out.iter_mut().enumerate() {
        // um pacote com menos canais que o primeiro (raro, MP3 que muda no meio) repete o que tem
        let src = c.chan(k.min(have - 1));
        dst.try_reserve(frames).map_err(|_| DecodeFail::Memory)?;
        dst.extend_from_slice(&src[..frames]);
    }
    Ok(())
}

// ------------------------------------------------------------------ handles para o Dart

static DECODED: Mutex<Option<HashMap<u64, Decoded>>> = Mutex::new(None);
static NEXT: AtomicU64 = AtomicU64::new(1);

fn table() -> std::sync::MutexGuard<'static, Option<HashMap<u64, Decoded>>> {
    DECODED.lock().unwrap_or_else(|e| e.into_inner())
}

/// Guarda o decodificado e devolve o handle (nunca 0).
pub fn keep(d: Decoded) -> u64 {
    let id = NEXT.fetch_add(1, Ordering::Relaxed);
    table().get_or_insert_with(HashMap::new).insert(id, d);
    id
}

/// Quadros, canais e taxa do decodificado.
pub fn info(handle: u64) -> Option<(usize, usize, f64)> {
    table().as_ref()?.get(&handle).map(|d| (d.frames(), d.channels.len(), d.rate))
}

/// Copia um canal para `out` (que precisa ter `frames` floats).
pub fn with_channel<R>(handle: u64, channel: usize, f: impl FnOnce(&[f32]) -> R) -> Option<R> {
    let t = table();
    let d = t.as_ref()?.get(&handle)?;
    d.channels.get(channel).map(|c| f(c))
}

pub fn free(handle: u64) -> bool {
    table().as_mut().and_then(|t| t.remove(&handle)).is_some()
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;

    /// WAV PCM 16 bits.
    pub fn wav16(channels: &[Vec<f32>], rate: u32) -> Vec<u8> {
        let ch = channels.len() as u16;
        let frames = channels[0].len();
        let data = frames * ch as usize * 2;
        let mut v = Vec::new();
        v.extend_from_slice(b"RIFF");
        v.extend_from_slice(&(36 + data as u32).to_le_bytes());
        v.extend_from_slice(b"WAVEfmt ");
        v.extend_from_slice(&16u32.to_le_bytes());
        v.extend_from_slice(&1u16.to_le_bytes());
        v.extend_from_slice(&ch.to_le_bytes());
        v.extend_from_slice(&rate.to_le_bytes());
        v.extend_from_slice(&(rate * ch as u32 * 2).to_le_bytes());
        v.extend_from_slice(&(ch * 2).to_le_bytes());
        v.extend_from_slice(&16u16.to_le_bytes());
        v.extend_from_slice(b"data");
        v.extend_from_slice(&(data as u32).to_le_bytes());
        for i in 0..frames {
            for c in channels {
                v.extend_from_slice(&((c[i] * 32767.0).round() as i16).to_le_bytes());
            }
        }
        v
    }

    /// FLAC mínimo, 16 bits, subquadros VERBATIM (sem predição: o formato mais simples que um
    /// decodificador de verdade aceita), com os CRCs que o symphonia confere.
    pub fn flac16(channels: &[Vec<f32>], rate: u32) -> Vec<u8> {
        const BLOCK: usize = 1152;
        let ch = channels.len();
        let frames = channels[0].len();
        let mut v = Vec::new();
        v.extend_from_slice(b"fLaC");
        // STREAMINFO, o último (e único) bloco de metadados
        v.push(0x80);
        v.extend_from_slice(&[0, 0, 34]);
        let mut si = Bits::default();
        si.put(BLOCK as u64, 16);
        si.put(BLOCK as u64, 16);
        si.put(0, 24);
        si.put(0, 24);
        si.put(rate as u64, 20);
        si.put(ch as u64 - 1, 3);
        si.put(15, 5);
        si.put(frames as u64, 36);
        si.put(0, 64);
        si.put(0, 64);
        v.extend_from_slice(&si.bytes);
        for (index, start) in (0..frames).step_by(BLOCK).enumerate() {
            let n = BLOCK.min(frames - start);
            let mut f = Bits::default();
            f.put(0b11111111111110, 14);
            f.put(0, 1);
            f.put(0, 1); // tamanho de bloco fixo
            f.put(0b0111, 4); // tamanho em 16 bits no fim do cabeçalho
            f.put(0b0000, 4); // taxa do STREAMINFO
            f.put(ch as u64 - 1, 4); // canais independentes
            f.put(0b100, 3); // 16 bits
            f.put(0, 1);
            assert!(index < 128, "o teste só codifica o número do quadro em 1 byte");
            f.put(index as u64, 8);
            f.put(n as u64 - 1, 16);
            let crc = crc8(&f.bytes);
            f.put(crc as u64, 8);
            for c in channels {
                f.put(0b0000_0010, 8); // VERBATIM, sem bits desperdiçados
                for &s in &c[start..start + n] {
                    f.put(((s * 32767.0).round() as i16) as u16 as u64, 16);
                }
            }
            let crc = crc16(&f.bytes);
            f.put(crc as u64, 16);
            v.extend_from_slice(&f.bytes);
        }
        v
    }

    #[derive(Default)]
    struct Bits {
        bytes: Vec<u8>,
        acc: u64,
        n: u32,
    }

    impl Bits {
        fn put(&mut self, value: u64, bits: u32) {
            for i in (0..bits).rev() {
                self.acc = (self.acc << 1) | ((value >> i) & 1);
                self.n += 1;
                if self.n == 8 {
                    self.bytes.push(self.acc as u8);
                    self.acc = 0;
                    self.n = 0;
                }
            }
        }
    }

    fn crc8(data: &[u8]) -> u8 {
        let mut crc = 0u8;
        for &b in data {
            crc ^= b;
            for _ in 0..8 {
                crc = if crc & 0x80 != 0 { (crc << 1) ^ 0x07 } else { crc << 1 };
            }
        }
        crc
    }

    fn crc16(data: &[u8]) -> u16 {
        let mut crc = 0u16;
        for &b in data {
            crc ^= (b as u16) << 8;
            for _ in 0..8 {
                crc = if crc & 0x8000 != 0 { (crc << 1) ^ 0x8005 } else { crc << 1 };
            }
        }
        crc
    }

    fn sine(n: usize, freq: f32, rate: f32, amp: f32) -> Vec<f32> {
        (0..n).map(|i| amp * (std::f32::consts::TAU * freq * i as f32 / rate).sin()).collect()
    }

    fn close(a: &[f32], b: &[f32]) {
        assert_eq!(a.len(), b.len());
        let worst = a.iter().zip(b).map(|(x, y)| (x - y).abs()).fold(0.0, f32::max);
        assert!(worst < 1.0 / 16384.0, "diferença {worst}");
    }

    #[test]
    fn decodes_a_stereo_wav() {
        let l = sine(10_000, 440.0, 44_100.0, 0.5);
        let r = sine(10_000, 220.0, 44_100.0, 0.25);
        let d = decode(&wav16(&[l.clone(), r.clone()], 44_100)).unwrap();
        assert_eq!(d.rate, 44_100.0);
        assert_eq!(d.channels.len(), 2);
        close(&d.channels[0], &l);
        close(&d.channels[1], &r);
    }

    #[test]
    fn decodes_a_mono_wav_as_one_channel() {
        let m = sine(3000, 1000.0, 48_000.0, 0.8);
        let d = decode(&wav16(std::slice::from_ref(&m), 48_000)).unwrap();
        assert_eq!(d.channels.len(), 1);
        close(&d.channels[0], &m);
    }

    #[test]
    fn decodes_a_flac() {
        let l = sine(5000, 440.0, 48_000.0, 0.5);
        let r = sine(5000, 660.0, 48_000.0, -0.3);
        let d = decode(&flac16(&[l.clone(), r.clone()], 48_000)).unwrap();
        assert_eq!(d.rate, 48_000.0);
        assert_eq!(d.channels.len(), 2);
        close(&d.channels[0], &l);
        close(&d.channels[1], &r);
    }

    #[test]
    fn garbage_and_empty_files_fail() {
        assert!(decode(b"").is_err());
        assert!(decode(b"isto nao e audio, so texto qualquer que ninguem decodifica").is_err());
        let mut truncated = wav16(&[vec![0.1; 100]], 8000);
        truncated.truncate(30);
        assert!(decode(&truncated).is_err());
        // WAV sem nenhum quadro
        assert_eq!(decode(&wav16(&[Vec::new()], 8000)).err(), Some(DecodeFail::Empty));
    }

    #[test]
    fn a_truncated_file_keeps_what_was_read() {
        let m = sine(20_000, 440.0, 48_000.0, 0.5);
        let mut bytes = flac16(std::slice::from_ref(&m), 48_000);
        bytes.truncate(bytes.len() * 3 / 4);
        let d = decode(&bytes).unwrap();
        assert!(d.frames() > 1152 && d.frames() < 20_000, "{}", d.frames());
        close(&d.channels[0], &m[..d.frames()]);
    }

    #[test]
    fn handles_are_kept_until_freed() {
        let h = keep(Decoded { channels: vec![vec![0.5; 10], vec![-0.5; 10]], rate: 22_050.0 });
        assert_ne!(h, 0);
        assert_eq!(info(h), Some((10, 2, 22_050.0)));
        assert_eq!(with_channel(h, 1, |c| c[3]), Some(-0.5));
        assert_eq!(with_channel(h, 2, |c| c[0]), None);
        assert!(free(h));
        assert!(!free(h));
        assert_eq!(info(h), None);
    }
}
