//! Testes da exportação compactada: cada arquivo gerado é decodificado de volta (symphonia) e conferido.

use crate::{
    audio::{self, Pcm, WavIn},
    encode::*,
};
use serde_json::json;

/// WAV PCM (16 ou 24 bits) ou float de 32 com as amostras dadas (i32 de 24 bits, intercaladas por canal).
fn wav(rate: u32, channels: u16, bits: u16, float: bool, samples: &[i32]) -> Vec<u8> {
    let mut payload = Vec::new();
    for &s in samples {
        match (bits, float) {
            (16, _) => payload.extend(((s >> 8) as i16).to_le_bytes()),
            (24, _) => payload.extend(&s.to_le_bytes()[..3]),
            (32, true) => payload.extend((s as f32 / 8_388_608.0).to_le_bytes()),
            _ => unreachable!(),
        }
    }
    let block = channels * bits / 8;
    let mut v = b"RIFF".to_vec();
    v.extend((36 + payload.len() as u32).to_le_bytes());
    v.extend(b"WAVEfmt ");
    v.extend(16u32.to_le_bytes());
    v.extend((if float { 3u16 } else { 1u16 }).to_le_bytes());
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

/// Tom de `hz` por `secs`, intercalado por canal (o canal 1 com o dobro da frequência).
fn tone(rate: u32, channels: u16, hz: f64, secs: f64) -> Vec<i32> {
    let n = (rate as f64 * secs) as usize;
    let mut v = Vec::with_capacity(n * channels as usize);
    for i in 0..n {
        for c in 0..channels {
            let f = hz * (1 + c) as f64;
            v.push((6_000_000.0 * (std::f64::consts::TAU * f * i as f64 / rate as f64).sin()) as i32);
        }
    }
    v
}

fn read(bytes: &[u8]) -> WavIn {
    audio::decode_wav_for_encode(bytes).unwrap()
}

/// Frequência do canal `ch` pelos cruzamentos de zero, no miolo do arquivo (longe do atraso do codificador).
fn hz_of(pcm: &Pcm, ch: usize) -> f64 {
    let frames = pcm.data.len() / pcm.channels;
    let (from, to) = (frames / 4, frames * 3 / 4);
    let x: Vec<i32> = (from..to).map(|i| pcm.data[i * pcm.channels + ch]).collect();
    let crossings = x.windows(2).filter(|w| w[0] < 0 && w[1] >= 0).count();
    crossings as f64 / ((to - from) as f64 / pcm.rate as f64)
}

fn none() -> Meta {
    Meta::default()
}

fn go(w: &WavIn, f: Format, m: &Meta) -> Result<Encoded, String> {
    encode(w, f, m, &|_| {})
}

#[test]
fn flac_volta_identico_em_todos_os_niveis_e_profundidades() {
    for (channels, bits) in [(1u16, 16u16), (2, 16), (2, 24)] {
        let bytes = wav(44_100, channels, bits, false, &tone(44_100, channels, 440.0, 0.4));
        let w = read(&bytes);
        for level in 0..=8u8 {
            let out = go(&w, Format::Flac { bits: bits as u32, level }, &none()).unwrap();
            let back = audio::decode_audio(&out.bytes).unwrap();
            assert_eq!((back.rate, back.channels), (44_100, channels as usize), "nível {level}");
            assert_eq!(back.data, w.pcm.data, "{channels} canais, {bits} bits, nível {level}");
            assert!(out.warnings.is_empty(), "{:?}", out.warnings);
        }
    }
}

#[test]
fn flac_nivel_mais_alto_nao_fica_maior() {
    let w = read(&wav(44_100, 2, 24, false, &tone(44_100, 2, 220.0, 1.0)));
    let size = |level| go(&w, Format::Flac { bits: 24, level }, &none()).unwrap().bytes.len();
    assert!(size(8) <= size(0), "{} > {}", size(8), size(0));
    assert!(size(5) < size(0));
}

#[test]
fn flac_24_para_16_arredonda_e_avisa_e_32f_vira_24_com_aviso() {
    let src = tone(48_000, 1, 1000.0, 0.3);
    let w24 = read(&wav(48_000, 1, 24, false, &src));
    let out = go(&w24, Format::Flac { bits: 16, level: 5 }, &none()).unwrap();
    assert!(out.warnings[0].contains("24 bits foi gravado com 16"), "{:?}", out.warnings);
    let back = audio::decode_audio(&out.bytes).unwrap();
    assert!(back.data.iter().zip(&w24.pcm.data).all(|(a, b)| (a - b).abs() <= 128));

    let w32 = read(&wav(48_000, 1, 32, true, &src));
    assert!(w32.float);
    let out = go(&w32, Format::Flac { bits: 24, level: 5 }, &none()).unwrap();
    assert!(out.warnings[0].contains("ponto flutuante"), "{:?}", out.warnings);
    assert_eq!(audio::decode_audio(&out.bytes).unwrap().data, w32.pcm.data);
}

#[test]
fn flac_com_metadados_ainda_decodifica_e_traz_os_campos() {
    let meta = Meta { title: Some("Canção".into()), artist: Some("Eu".into()), album: None };
    let w = read(&wav(44_100, 2, 16, false, &tone(44_100, 2, 440.0, 0.3)));
    let out = go(&w, Format::Flac { bits: 16, level: 5 }, &meta).unwrap();
    let text = String::from_utf8_lossy(&out.bytes).to_string();
    assert!(text.contains("TITLE=Canção") && text.contains("ARTIST=Eu") && !text.contains("ALBUM="));
    assert_eq!(audio::decode_audio(&out.bytes).unwrap().data, w.pcm.data);
    // o STREAMINFO deixou de ser o último bloco
    assert_eq!(out.bytes[4], 0);
}

#[test]
fn mp3_todas_as_qualidades_tem_duracao_e_frequencia_certas() {
    let (rate, secs) = (44_100u32, 3.0);
    let w = read(&wav(rate, 2, 16, false, &tone(rate, 2, 440.0, secs)));
    let formats = [Format::Cbr(128), Format::Cbr(192), Format::Cbr(256), Format::Cbr(320), Format::Vbr(0), Format::Vbr(2), Format::Vbr(4)];
    for f in formats {
        let out = go(&w, f, &none()).unwrap();
        let back = audio::decode_audio(&out.bytes).unwrap();
        assert_eq!((back.rate, back.channels), (rate, 2), "{f:?}");
        let dur = back.data.len() as f64 / 2.0 / rate as f64;
        assert!((dur - secs).abs() < 0.05, "{f:?}: duração {dur}");
        let (l, r) = (hz_of(&back, 0), hz_of(&back, 1));
        assert!((l - 440.0).abs() < 8.0 && (r - 880.0).abs() < 16.0, "{f:?}: {l} Hz e {r} Hz");
        if let Format::Cbr(k) = f {
            // taxa constante: o tamanho segue o bitrate (com folga para cabeçalhos e o último quadro)
            let expect = k as f64 * 1000.0 / 8.0 * secs;
            assert!((out.bytes.len() as f64 - expect).abs() < expect * 0.1 + 2000.0, "{f:?}: {} bytes, esperado ~{expect}", out.bytes.len());
        }
    }
}

#[test]
fn mp3_48k_mono_e_curto() {
    let w = read(&wav(48_000, 1, 24, false, &tone(48_000, 1, 1000.0, 1.0)));
    let out = go(&w, Format::Cbr(128), &none()).unwrap();
    let back = audio::decode_audio(&out.bytes).unwrap();
    assert_eq!((back.rate, back.channels), (48_000, 1));
    assert!((hz_of(&back, 0) - 1000.0).abs() < 15.0);
    // poucos quadros, e até uma única amostra, não derrubam o codificador
    for n in [1usize, 100, 1152, 1153] {
        let w = read(&wav(44_100, 1, 16, false, &tone(44_100, 1, 440.0, 1.0)[..n]));
        let out = go(&w, Format::Cbr(128), &none()).unwrap();
        assert!(!out.bytes.is_empty(), "{n} amostras");
        audio::decode_audio(&out.bytes).unwrap_or_else(|e| panic!("{n} amostras: {e}"));
    }
}

#[test]
fn mp3_recusa_taxa_que_nao_e_44_1_nem_48() {
    let w = read(&wav(22_050, 1, 16, false, &tone(22_050, 1, 440.0, 0.2)));
    let e = go(&w, Format::Cbr(128), &none()).err().unwrap();
    assert!(e.contains("44,1 ou 48 kHz") && e.contains("22050"), "{e}");
    // o FLAC aceita qualquer taxa
    assert!(go(&w, Format::Flac { bits: 16, level: 5 }, &none()).is_ok());
}

#[test]
fn mp3_com_id3_decodifica_e_leva_os_campos() {
    let meta = Meta { title: Some("Título ☺".into()), artist: Some("Artista".into()), album: Some("Álbum".into()) };
    let w = read(&wav(44_100, 2, 16, false, &tone(44_100, 2, 440.0, 1.0)));
    let out = go(&w, Format::Cbr(192), &meta).unwrap();
    assert_eq!(&out.bytes[..3], b"ID3");
    // o tamanho sincronizado do cabeçalho bate com os quadros, e o primeiro quadro MP3 vem logo depois
    let size = out.bytes[6..10].iter().fold(0usize, |a, &b| a << 7 | b as usize);
    assert_eq!(out.bytes[10 + size], 0xFF);
    let text = String::from_utf8_lossy(&out.bytes[..10 + size]).to_string();
    assert!(text.contains("TIT2") && text.contains("Título ☺") && text.contains("TPE1") && text.contains("TALB"));
    let back = audio::decode_audio(&out.bytes).unwrap();
    assert!((hz_of(&back, 0) - 440.0).abs() < 8.0);
}

#[test]
fn metadados_hostis_saem_limpos() {
    assert_eq!(clean_text("a\u{0}b\r\nc\u{7}\td"), Some("ab c d".into()));
    assert_eq!(clean_text("  \u{202E}evil\u{200B}  "), Some("evil".into()));
    assert_eq!(clean_text("\u{0}\u{1}\n "), None);
    assert_eq!(clean_text(""), None);
    let m = Meta::from_params(Some(&json!({"title": "x\u{0}\n=y", "artist": "ARTIST=fake\nALBUM=zz", "album": "a".repeat(500)})));
    assert_eq!(m.title.as_deref(), Some("x =y"));
    assert_eq!(m.artist.as_deref(), Some("ARTIST=fake ALBUM=zz"));
    assert_eq!(m.album.unwrap().chars().count(), META_MAX_CHARS);
    // nenhum caractere de controle chega ao bloco do FLAC nem ao ID3
    let hostile = Meta { title: clean_text("t\u{0}\u{1b}[31m"), artist: None, album: None };
    let w = read(&wav(44_100, 1, 16, false, &tone(44_100, 1, 440.0, 0.1)));
    for f in [Format::Flac { bits: 16, level: 5 }, Format::Cbr(128)] {
        let out = go(&w, f, &hostile).unwrap();
        let head = &out.bytes[..out.bytes.len().min(200)];
        assert!(!head.contains(&0x1b), "{f:?}");
    }
}

#[test]
fn nome_sugerido_e_seguro() {
    let m = |t: &str, a: &str| Meta { title: clean_text(t), artist: clean_text(a), album: None };
    assert_eq!(suggested_name(&m("Minha música", "Eu"), "mp3"), "Eu - Minha música.mp3");
    assert_eq!(suggested_name(&m("../../etc/passwd", ""), "flac"), "-..-etc-passwd.flac");
    assert_eq!(suggested_name(&m("a:b*c?", ""), "flac"), "a-b-c-.flac");
    assert_eq!(suggested_name(&none(), "mp3"), "exportacao.mp3");
    assert_eq!(suggested_name(&m("...", ""), "mp3"), "exportacao.mp3");
    assert!(suggested_name(&m(&"x".repeat(500), ""), "mp3").chars().count() <= 104);
}

#[test]
fn wav_de_entrada_ruim() {
    let good = wav(44_100, 1, 16, false, &tone(44_100, 1, 440.0, 0.2));
    let err = |b: &[u8]| audio::decode_wav_for_encode(b).err().unwrap_or_else(|| "ok".into());
    // não é WAV
    assert!(err(b"OggS....").contains("não é um WAV"));
    assert!(audio::decode_wav_for_encode(&[]).is_err());
    // cabeçalho cortado, sem dados, corpo cortado no meio de uma amostra
    assert!(audio::decode_wav_for_encode(&good[..30]).is_err());
    assert!(err(&good[..44]).contains("vazio"), "{}", err(&good[..44]));
    assert!(audio::decode_wav_for_encode(&good[..47]).is_ok());
    // o tamanho do `data` mente (0xFFFFFFFF): vale o que há no arquivo
    let mut lie = good.clone();
    lie[40..44].copy_from_slice(&u32::MAX.to_le_bytes());
    assert!(audio::decode_wav_for_encode(&lie).is_ok());
    // formato ilegível
    let mut junk = good.clone();
    junk[20] = 9;
    assert!(audio::decode_wav_for_encode(&junk).is_err());
    // bytes aleatórios depois de um cabeçalho válido nunca derrubam o leitor
    let mut x = 12345u32;
    for _ in 0..200 {
        let mut v = good[..44].to_vec();
        for _ in 0..64 {
            x = x.wrapping_mul(1_664_525).wrapping_add(1_013_904_223);
            v.push((x >> 24) as u8);
        }
        let _ = audio::decode_wav_for_encode(&v);
    }
    // mais de 30 minutos
    let long = wav(8_000, 1, 16, false, &vec![0; 8_000 * 1_860]);
    assert!(err(&long).contains("máximo é 30 minutos"));
    assert!(audio::decode_wav_for_encode(&wav(8_000, 1, 16, false, &vec![0; 8_000 * 1_790])).is_ok());
}

#[test]
fn formato_a_partir_dos_parametros() {
    let f = |v: serde_json::Value| Format::from_params(&v);
    assert_eq!(f(json!({"format": "flac"})), Format::Flac { bits: 24, level: 5 });
    assert_eq!(f(json!({"format": "flac", "bits": 16, "level": 8})), Format::Flac { bits: 16, level: 8 });
    assert_eq!(f(json!({"format": "flac", "bits": 32})), Format::Flac { bits: 24, level: 5 });
    assert_eq!(f(json!({"format": "mp3"})), Format::Cbr(192));
    assert_eq!(f(json!({"format": "mp3", "bitrate": 320})), Format::Cbr(320));
    assert_eq!(f(json!({"format": "mp3", "vbr": 0})), Format::Vbr(0));
}
