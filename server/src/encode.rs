//! Exportação compactada (tarefa `encode_audio`): WAV → FLAC ou MP3, com metadados. Tudo puro e síncrono
//! (bytes entram, bytes saem), para rodar em `spawn_blocking` e ser testado sem banco.
//!
//! O MP3 sai do `rusty_mp3` (Rust puro, Apache-2.0, sem LAME nem C: a imagem Docker não ganha dependência de
//! sistema nem obrigação de LGPL). A qualidade dele fica um pouco atrás do LAME (a documentação da crate mede
//! cerca de 0,1 a 0,2 ODG a menos em 128 a 192 kbps), o que para "compartilhar" serve.

use serde_json::Value;

use crate::audio::{self, Pcm, WavIn};

/// Maior tamanho de cada campo de metadado, em caracteres.
pub const META_MAX_CHARS: usize = 200;

/// Formato de saída e a qualidade pedida.
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Format {
    /// FLAC de 16 ou 24 bits e nível de compressão de 0 a 8.
    Flac { bits: u32, level: u8 },
    /// MP3 a taxa constante (kbps).
    Cbr(u32),
    /// MP3 a taxa variável, de V0 (melhor) a V4.
    Vbr(u8),
}

impl Format {
    pub fn extension(&self) -> &'static str {
        match self {
            Format::Flac { .. } => "flac",
            _ => "mp3",
        }
    }

    pub fn mime(&self) -> &'static str {
        match self {
            Format::Flac { .. } => "audio/flac",
            _ => "audio/mpeg",
        }
    }

    /// Lê o formato dos parâmetros da tarefa (a rota já os validou, então o que sobra é padrão).
    pub fn from_params(p: &Value) -> Format {
        let int = |k: &str| p.get(k).and_then(Value::as_u64);
        match p.get("format").and_then(Value::as_str) {
            Some("mp3") => match int("vbr") {
                Some(q) => Format::Vbr(q as u8),
                None => Format::Cbr(int("bitrate").unwrap_or(192) as u32),
            },
            _ => Format::Flac {
                bits: int("bits").map_or(24, |b| if b == 16 { 16 } else { 24 }),
                level: int("level").map_or(audio::FLAC_DEFAULT_LEVEL, |l| l as u8),
            },
        }
    }
}

pub const CBR_RATES: [u64; 4] = [128, 192, 256, 320];
pub const VBR_MAX: u64 = 4;

/// Título, artista e álbum já limpos.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Meta {
    pub title: Option<String>,
    pub artist: Option<String>,
    pub album: Option<String>,
}

/// Tira o que não pode ir num campo de texto: caracteres de controle (inclusive quebra de linha e NUL), os que
/// mexem na direção do texto e a marca de ordem de bytes. Espaços repetidos viram um só. Vazio vira `None`.
pub fn clean_text(s: &str) -> Option<String> {
    let mut out = String::new();
    let mut space = true;
    for c in s.chars() {
        let hidden =
            (c.is_control() && !c.is_whitespace()) || matches!(c, '\u{200B}'..='\u{200F}' | '\u{202A}'..='\u{202E}' | '\u{2066}'..='\u{2069}' | '\u{FEFF}');
        if hidden {
            continue;
        }
        if c.is_whitespace() {
            if !space {
                out.push(' ');
            }
            space = true;
        } else {
            out.push(c);
            space = false;
        }
    }
    let out = out.trim_end().to_string();
    (!out.is_empty()).then_some(out)
}

impl Meta {
    /// Lê `title`, `artist` e `album` dos parâmetros, sempre limpos e no limite de tamanho.
    pub fn from_params(p: Option<&Value>) -> Meta {
        let get = |k: &str| p.and_then(|p| p.get(k)).and_then(Value::as_str).and_then(clean_text).map(|s| s.chars().take(META_MAX_CHARS).collect());
        Meta { title: get("title"), artist: get("artist"), album: get("album") }
    }

    fn fields(&self) -> [(&'static str, &Option<String>); 3] {
        [("TITLE", &self.title), ("ARTIST", &self.artist), ("ALBUM", &self.album)]
    }
}

/// Nome de arquivo sugerido: "Artista - Título.ext", ou "exportacao.ext" sem metadado. Sem separador de caminho,
/// caracteres proibidos no Windows nem ponto ou espaço nas pontas.
pub fn suggested_name(meta: &Meta, ext: &str) -> String {
    let base = match (&meta.artist, &meta.title) {
        (Some(a), Some(t)) => format!("{a} - {t}"),
        (None, Some(t)) => t.clone(),
        _ => "exportacao".to_string(),
    };
    let safe: String = base.chars().map(|c| if matches!(c, '/' | '\\' | ':' | '*' | '?' | '"' | '<' | '>' | '|') { '-' } else { c }).take(100).collect();
    let safe = safe.trim_matches(|c: char| c == '.' || c.is_whitespace());
    let safe = if safe.is_empty() { "exportacao" } else { safe };
    format!("{safe}.{ext}")
}

/// O resultado de uma codificação: os bytes e os avisos para o usuário (perdas de conversão).
pub struct Encoded {
    pub bytes: Vec<u8>,
    pub warnings: Vec<String>,
}

/// Codifica o WAV lido no formato pedido. `progress` recebe de 0 a 1.
pub fn encode(wav: &WavIn, format: Format, meta: &Meta, progress: &dyn Fn(f32)) -> Result<Encoded, String> {
    let mut warnings = Vec::new();
    let pcm = &wav.pcm;
    let bytes = match format {
        Format::Flac { bits, level } => {
            if wav.float {
                warnings.push(
                    "o áudio de 32 bits em ponto flutuante foi gravado com 24 bits inteiros no FLAC (perda de resolução abaixo de -144 dBFS)".to_string(),
                );
            } else if bits < wav.bits as u32 {
                warnings.push(format!("o áudio de {} bits foi gravado com {bits} bits no FLAC (arredondado, sem dither)", wav.bits));
            }
            progress(0.2);
            let flac = audio::encode_flac_with(pcm, bits, level)?;
            with_vorbis_comment(flac, meta)?
        }
        Format::Cbr(_) | Format::Vbr(_) => {
            let mp3 = encode_mp3(pcm, format, progress)?;
            let mut out = id3v24(meta);
            out.extend_from_slice(&mp3);
            out
        }
    };
    progress(1.0);
    Ok(Encoded { bytes, warnings })
}

fn encode_mp3(pcm: &Pcm, format: Format, progress: &dyn Fn(f32)) -> Result<Vec<u8>, String> {
    if !matches!(pcm.rate, 44_100 | 48_000) {
        return Err(format!("MP3 exige 44,1 ou 48 kHz e o áudio tem {} Hz; exporte o WAV nessa taxa ou use FLAC", pcm.rate));
    }
    let cfg = match format {
        Format::Cbr(kbps) => rusty_mp3::Mp3EncoderConfig { bitrate_kbps: kbps, vbr_quality: None },
        Format::Vbr(q) => rusty_mp3::Mp3EncoderConfig { bitrate_kbps: 0, vbr_quality: Some(rusty_mp3::vbr_quality_index(q as f32)) },
        Format::Flac { .. } => return Err("formato inesperado".into()),
    };
    let fail = |e: rusty_mp3::Error| format!("falha ao codificar o MP3: {e:?}");
    let mut enc = rusty_mp3::Mp3Encoder::new(cfg);
    let mut out = Vec::new();
    let drain = |enc: &mut rusty_mp3::Mp3Encoder, out: &mut Vec<u8>| {
        while let Ok(packet) = enc.next_packet() {
            out.extend_from_slice(&packet);
        }
    };
    let ch = pcm.channels;
    // um segundo por vez: o progresso anda e o vetor de floats não vira uma cópia inteira do áudio
    let chunk = pcm.rate as usize * ch;
    let total = pcm.data.len().max(1);
    let mut buf: Vec<f32> = Vec::with_capacity(chunk);
    for (i, part) in pcm.data.chunks(chunk).enumerate() {
        buf.clear();
        buf.extend(part.iter().map(|&s| s as f32 / 8_388_608.0));
        enc.push_pcm_f32(&buf, ch as u16, pcm.rate).map_err(fail)?;
        drain(&mut enc, &mut out);
        progress(0.1 + 0.85 * ((i + 1) * chunk).min(total) as f32 / total as f32);
    }
    enc.finish();
    drain(&mut enc, &mut out);
    if out.is_empty() {
        return Err("o codificador de MP3 não produziu áudio".into());
    }
    Ok(out)
}

/// Cabeçalho ID3v2.4 (texto em UTF-8) com título, artista e álbum; vazio sem metadado.
pub fn id3v24(meta: &Meta) -> Vec<u8> {
    let syncsafe = |n: usize| [(n >> 21) as u8 & 0x7F, (n >> 14) as u8 & 0x7F, (n >> 7) as u8 & 0x7F, n as u8 & 0x7F];
    let mut frames = Vec::new();
    for (id, value) in [("TIT2", &meta.title), ("TPE1", &meta.artist), ("TALB", &meta.album)] {
        if let Some(v) = value {
            let mut body = vec![3u8]; // codificação 3 = UTF-8
            body.extend_from_slice(v.as_bytes());
            frames.extend_from_slice(id.as_bytes());
            frames.extend_from_slice(&syncsafe(body.len()));
            frames.extend_from_slice(&[0, 0]);
            frames.extend_from_slice(&body);
        }
    }
    if frames.is_empty() {
        return Vec::new();
    }
    let mut out = b"ID3\x04\x00\x00".to_vec();
    out.extend_from_slice(&syncsafe(frames.len()));
    out.extend_from_slice(&frames);
    out
}

/// Põe um bloco VORBIS_COMMENT logo depois do STREAMINFO de um FLAC recém-gerado. Sem metadado devolve o FLAC igual.
fn with_vorbis_comment(flac: Vec<u8>, meta: &Meta) -> Result<Vec<u8>, String> {
    let fields: Vec<String> = meta.fields().iter().filter_map(|(k, v)| v.as_ref().map(|v| format!("{k}={v}"))).collect();
    if fields.is_empty() {
        return Ok(flac);
    }
    // "fLaC" + cabeçalho do STREAMINFO (tipo 0; o bit alto marca o último bloco) + 34 bytes
    if flac.len() < 42 || &flac[0..4] != b"fLaC" || flac[4] & 0x7F != 0 {
        return Err("FLAC gerado com cabeçalho inesperado".into());
    }
    let vendor = b"jopendaw";
    let mut body = Vec::new();
    body.extend_from_slice(&(vendor.len() as u32).to_le_bytes());
    body.extend_from_slice(vendor);
    body.extend_from_slice(&(fields.len() as u32).to_le_bytes());
    for f in &fields {
        body.extend_from_slice(&(f.len() as u32).to_le_bytes());
        body.extend_from_slice(f.as_bytes());
    }
    let len = body.len();
    if len >= 1 << 24 {
        return Err("metadados grandes demais".into());
    }
    let mut out = Vec::with_capacity(flac.len() + len + 4);
    out.extend_from_slice(&flac[..4]);
    out.push(flac[4] & 0x7F); // o STREAMINFO deixa de ser o último
    out.extend_from_slice(&flac[5..42]);
    out.extend_from_slice(&[0x80 | 4, (len >> 16) as u8, (len >> 8) as u8, len as u8]);
    out.extend_from_slice(&body);
    out.extend_from_slice(&flac[42..]);
    Ok(out)
}
