//! Rotas da exportação compactada (`encode_audio`): WAV enviado → FLAC ou MP3 gravado na conta.

use super::*;
use crate::audio;

/// WAV estéreo de 16 bits com um tom (esquerda em `hz`, direita no dobro).
fn stereo_wav(rate: u32, hz: f32, secs: f32) -> Vec<u8> {
    let n = (rate as f32 * secs) as usize;
    let mut payload = Vec::with_capacity(n * 4);
    for i in 0..n {
        for c in 0..2 {
            let f = hz * (1 + c) as f32;
            payload.extend(((12_000.0 * (std::f32::consts::TAU * f * i as f32 / rate as f32).sin()) as i16).to_le_bytes());
        }
    }
    let mut v = b"RIFF".to_vec();
    v.extend((36 + payload.len() as u32).to_le_bytes());
    v.extend(b"WAVEfmt ");
    v.extend(16u32.to_le_bytes());
    v.extend([1, 0, 2, 0]);
    v.extend(rate.to_le_bytes());
    v.extend((rate * 4).to_le_bytes());
    v.extend([4, 0, 16, 0]);
    v.extend(b"data");
    v.extend((payload.len() as u32).to_le_bytes());
    v.extend(payload);
    v
}

fn hz_left(p: &audio::Pcm) -> f64 {
    let frames = p.data.len() / p.channels;
    let (from, to) = (frames / 4, frames * 3 / 4);
    let x: Vec<i32> = (from..to).map(|i| p.data[i * p.channels]).collect();
    x.windows(2).filter(|w| w[0] < 0 && w[1] >= 0).count() as f64 / ((to - from) as f64 / p.rate as f64)
}

async fn run(e: &Env, u: &User, hash: &str, params: Value) -> Value {
    let r = new_job(e, u, "encode_audio", hash, Some(params)).await;
    assert_eq!(r.status, StatusCode::ACCEPTED, "{}", String::from_utf8_lossy(&r.body));
    wait_job(e, u, r.json()["id"].as_str().unwrap()).await
}

#[tokio::test]
async fn encode_flac_ida_e_volta_com_metadados() {
    let e = env_or_skip!();
    let a = user(&e).await;
    let wav = stereo_wav(44_100, 440.0, 0.6);
    let (hash, r) = upload(&e, &a, &wav).await;
    assert_eq!(r.status, StatusCode::NO_CONTENT);
    let before: Value = get(&e, "/api/samples", &a).await.json();

    let j = run(&e, &a, &hash, json!({"format": "flac", "bits": 16, "level": 8, "title": "Minha\u{0} canção\n", "artist": "Eu", "album": "Álbum"})).await;
    assert_eq!(j["status"], "done", "{j}");
    let res = &j["result"];
    assert_eq!((res["format"].clone(), res["mime"].clone()), (json!("flac"), json!("audio/flac")));
    assert_eq!(res["filename"], "Eu - Minha canção.flac");
    assert!(res["warnings"].as_array().unwrap().iter().any(|w| w.as_str().unwrap().contains("16 bits")) || res["warnings"].as_array().unwrap().is_empty());
    let out = res["sample"].as_str().unwrap().to_string();

    let file = get(&e, &format!("/api/samples/{out}"), &a).await;
    assert_eq!(&file.body[..4], b"fLaC");
    assert_eq!(storage::hex_sha256(&file.body), out);
    let back = audio::decode_audio(&file.body).unwrap();
    let orig = audio::decode_wav(&wav).unwrap();
    assert_eq!(back.data, orig.data, "sem perda");
    let text = String::from_utf8_lossy(&file.body[..300]).to_string();
    assert!(text.contains("TITLE=Minha canção") && text.contains("ARTIST=Eu") && text.contains("ALBUM=Álbum"));

    // o resultado é um áudio da conta, sem uso, contado na cota
    let after = get(&e, "/api/samples", &a).await.json();
    let row = sample_row(&after, &out);
    assert_eq!(row["unused"], true);
    assert_eq!(after["used_bytes"].as_i64().unwrap() - before["used_bytes"].as_i64().unwrap(), file.body.len() as i64);

    // a limpeza do app: apaga o resultado e o WAV, e a tarefa
    assert_eq!(del_force(&e, &out, &a).await.status, StatusCode::OK);
    assert_eq!(del_force(&e, &hash, &a).await.status, StatusCode::OK);
    let id = j["id"].as_str().unwrap();
    assert_eq!(del(&e, &format!("/api/jobs/{id}"), &a).await.status, StatusCode::NO_CONTENT);
    assert_eq!(del(&e, &format!("/api/jobs/{id}"), &a).await.status, StatusCode::NOT_FOUND);
    assert_eq!(get(&e, &format!("/api/jobs/{id}"), &a).await.status, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn encode_mp3_duracao_frequencia_e_id3() {
    let e = env_or_skip!();
    let a = user(&e).await;
    let (hash, _) = upload(&e, &a, &stereo_wav(48_000, 440.0, 2.0)).await;
    for params in [json!({"format": "mp3", "bitrate": 192, "title": "Faixa"}), json!({"format": "mp3", "vbr": 2})] {
        let j = run(&e, &a, &hash, params.clone()).await;
        assert_eq!(j["status"], "done", "{j}");
        assert_eq!((j["result"]["mime"].clone(), j["result"]["format"].clone()), (json!("audio/mpeg"), json!("mp3")));
        let out = j["result"]["sample"].as_str().unwrap();
        let file = get(&e, &format!("/api/samples/{out}"), &a).await;
        let back = audio::decode_audio(&file.body).unwrap();
        assert_eq!((back.rate, back.channels), (48_000, 2));
        let dur = back.data.len() as f64 / 2.0 / 48_000.0;
        assert!((dur - 2.0).abs() < 0.05, "duração {dur}");
        assert!((hz_left(&back) - 440.0).abs() < 8.0);
        assert_eq!(&file.body[..3] == b"ID3", params.get("title").is_some());
    }
}

#[tokio::test]
async fn encode_parametros_invalidos() {
    let e = env_or_skip!();
    let a = user(&e).await;
    let (hash, _) = upload(&e, &a, &stereo_wav(44_100, 440.0, 0.2)).await;
    let bad = [
        None,
        Some(json!({})),
        Some(json!({"format": "ogg"})),
        Some(json!({"format": "flac", "bits": 8})),
        Some(json!({"format": "flac", "level": 9})),
        Some(json!({"format": "flac", "bitrate": 128})),
        Some(json!({"format": "mp3", "bitrate": 100})),
        Some(json!({"format": "mp3", "vbr": 5})),
        Some(json!({"format": "mp3", "bitrate": 128, "vbr": 1})),
        Some(json!({"format": "mp3", "level": 3})),
        Some(json!({"format": "mp3", "title": 5})),
        Some(json!({"format": "mp3", "title": "x".repeat(900)})),
        Some(json!({"format": "mp3", "extra": 1})),
        Some(json!("flac")),
    ];
    for p in bad {
        let r = new_job(&e, &a, "encode_audio", &hash, p.clone()).await;
        assert_eq!(r.status, StatusCode::BAD_REQUEST, "{p:?}: {}", String::from_utf8_lossy(&r.body));
    }
    // metadados hostis são limpos antes de ir para o banco
    let r = new_job(&e, &a, "encode_audio", &hash, Some(json!({"format": "mp3", "title": "a\u{0}\u{1b}[31m\r\nb", "artist": "\u{0}\n"}))).await;
    assert_eq!(r.status, StatusCode::ACCEPTED);
    let id: Uuid = r.json()["id"].as_str().unwrap().parse().unwrap();
    wait_job(&e, &a, &id.to_string()).await;
    let (params,): (sqlx::types::Json<Value>,) = sqlx::query_as("SELECT params FROM jobs WHERE id = $1").bind(id).fetch_one(&e.state.pool).await.unwrap();
    assert_eq!(params.0["title"], "a[31m b");
    assert!(params.0.get("artist").is_none());
}

#[tokio::test]
async fn encode_entradas_ruins_falham_com_mensagem_clara() {
    let e = env_or_skip!();
    let a = user(&e).await;
    let good = stereo_wav(44_100, 440.0, 0.3);
    let mut cases: Vec<(&str, Vec<u8>, &str)> = vec![
        ("não é WAV", b"OggS\0\x02 conteudo qualquer que nao e wav".to_vec(), "não é um WAV"),
        ("sem dados", good[..44].to_vec(), "vazio"),
        ("cabeçalho cortado", good[..30].to_vec(), "não suportado"),
    ];
    // acima de 30 minutos (mono de 8 kHz, para o arquivo de teste ser pequeno)
    let long = wav16(8_000, &vec![0i16; 8_000 * 1_860]);
    cases.push(("longo demais", long, "máximo é 30 minutos"));
    for (what, bytes, expect) in cases {
        let (h, r) = upload(&e, &a, &bytes).await;
        assert_eq!(r.status, StatusCode::NO_CONTENT, "{what}");
        let j = run(&e, &a, &h, json!({"format": "flac"})).await;
        assert_eq!(j["status"], "failed", "{what}: {j}");
        assert!(j["error"].as_str().unwrap().contains(expect), "{what}: {j}");
    }
    // MP3 a 22,05 kHz: recusado com a explicação
    let (h, _) = upload(&e, &a, &wav16(22_050, &vec![100i16; 22_050])).await;
    let j = run(&e, &a, &h, json!({"format": "mp3"})).await;
    assert_eq!(j["status"], "failed");
    assert!(j["error"].as_str().unwrap().contains("44,1 ou 48 kHz"), "{j}");
    // o mesmo áudio em FLAC serve
    assert_eq!(run(&e, &a, &h, json!({"format": "flac"})).await["status"], "done");
}

#[tokio::test]
async fn encode_isolamento_entre_contas() {
    let e = env_or_skip!();
    let a = user(&e).await;
    let b = user(&e).await;
    let (hash, _) = upload(&e, &a, &stereo_wav(44_100, 330.0, 0.3)).await;
    // a conta B não cria tarefa com o áudio de A
    assert_eq!(new_job(&e, &b, "encode_audio", &hash, Some(json!({"format": "flac"}))).await.status, StatusCode::NOT_FOUND);
    let j = run(&e, &a, &hash, json!({"format": "flac"})).await;
    assert_eq!(j["status"], "done");
    let out = j["result"]["sample"].as_str().unwrap();
    let id = j["id"].as_str().unwrap();
    // nem lê, nem apaga o resultado, nem enxerga ou apaga a tarefa de A
    assert_eq!(get(&e, &format!("/api/samples/{out}"), &b).await.status, StatusCode::NOT_FOUND);
    assert_eq!(get(&e, &format!("/api/jobs/{id}"), &b).await.status, StatusCode::NOT_FOUND);
    assert_eq!(del(&e, &format!("/api/jobs/{id}"), &b).await.status, StatusCode::NOT_FOUND);
    assert_eq!(del_force(&e, out, &b).await.status, StatusCode::NOT_FOUND);
    assert_eq!(get(&e, &format!("/api/samples/{out}"), &a).await.status, StatusCode::OK);
    // sem token
    assert_eq!(call(&e, Method::DELETE, &format!("/api/jobs/{id}"), None, vec![], &[]).await.status, StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn encode_com_cota_estourada_diz_onde_liberar() {
    let e = env_or_skip!();
    let a = user(&e).await;
    let (h, _) = upload(&e, &a, &stereo_wav(44_100, 440.0, 0.3)).await;
    let fake = storage::hex_sha256(b"enorme-de-cota-encode");
    sqlx::query("INSERT INTO samples (owner_id, hash, size) VALUES ($1, $2, $3)")
        .bind(a.id)
        .bind(&fake)
        .bind(storage::QUOTA_BYTES - 100)
        .execute(&e.state.pool)
        .await
        .unwrap();
    let j = run(&e, &a, &h, json!({"format": "mp3", "bitrate": 320})).await;
    assert_eq!(j["status"], "failed");
    assert!(j["error"].as_str().unwrap().contains("tela Conta"), "{j}");
}
