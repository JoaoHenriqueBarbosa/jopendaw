//! Testes das rotas da fase 6 (documento, samples, jobs) contra um Postgres de verdade.
//!
//! Precisam de `TEST_DATABASE_URL` apontando para um banco com o `server/schema.sql` carregado
//! (nunca o de desenvolvimento: os testes criam contas e tarefas). Sem a variável, cada teste se
//! declara pulado e passa, para o `cargo test` seguir valendo em máquina sem banco:
//!
//! ```bash
//! docker exec jopendaw-pg psql -U jopendaw -d postgres -c "CREATE DATABASE jopendaw_test"
//! docker exec -i jopendaw-pg psql -U jopendaw -d jopendaw_test < server/schema.sql
//! TEST_DATABASE_URL=postgres://jopendaw:jopendaw@localhost:5432/jopendaw_test cargo test -p jopendaw-server
//! ```
//!
//! O armazenamento dos áudios é o disco por padrão. Com `S3_ENDPOINT` (e `S3_BUCKET`,
//! `S3_ACCESS_KEY`, `S3_SECRET_KEY`) no ambiente, os mesmos testes rodam contra o S3, por exemplo o
//! MinIO do `docker-compose up -d minio minio-init`:
//!
//! ```bash
//! S3_ENDPOINT=http://localhost:9000 S3_BUCKET=jopendaw S3_ACCESS_KEY=jopendaw S3_SECRET_KEY=jopendaw-minio-dev \
//!   TEST_DATABASE_URL=... cargo test -p jopendaw-server
//! ```

use std::{path::PathBuf, sync::Arc, time::Duration};

use axum::{
    Router,
    body::Body,
    http::{Method, Request, StatusCode, header},
};
use http_body_util::BodyExt;
use sea_orm::{ConnectOptions, Database};
use serde_json::{Value, json};
use tower::ServiceExt;
use uuid::Uuid;

use crate::{AppState, auth, config::Config, mail::Mailer, routes, storage};

/// Um diretório de dados só para todos os testes do processo: cada teste sobe o próprio worker,
/// e qualquer um deles pode acabar pegando a tarefa de outro.
fn data_dir() -> PathBuf {
    let d = std::env::temp_dir().join("jopendaw-test-data");
    std::fs::create_dir_all(&d).unwrap();
    d
}

struct Env {
    state: AppState,
    app: Router,
}

async fn env() -> Option<Env> {
    let url = std::env::var("TEST_DATABASE_URL").ok()?;
    let mut opt = ConnectOptions::new(url);
    opt.max_connections(8).sqlx_logging(false);
    let db = Database::connect(opt).await.expect("conecta no banco de teste");
    let pool = db.get_postgres_connection_pool().clone();
    let cfg = Config {
        jwt_secret: b"segredo-de-teste-com-mais-de-32-bytes!!".to_vec(),
        app_base_url: "http://localhost".into(),
        mail_from: "t@t.local".into(),
        mail_from_name: "t".into(),
        jmail_url: "http://127.0.0.1:1".into(),
        jmail_api_key: "x".into(),
        google: None,
        discord: None,
        review: None,
        data_dir: data_dir(),
        s3: crate::config::S3Config::from_env().expect("S3_* do teste"),
    };
    let store = Arc::new(storage::Store::from_config(&cfg).unwrap());
    let mailer = Arc::new(Mailer::new(&cfg.jmail_url, &cfg.jmail_api_key).unwrap());
    let state = AppState { db, pool, cfg: Arc::new(cfg), store, mailer, job_wake: Arc::new(tokio::sync::Notify::new()) };
    tokio::spawn(routes::jobs::worker(state.clone()));
    Some(Env { app: routes::router(state.clone()), state })
}

/// Pula o teste (passando) quando não há banco de teste configurado.
macro_rules! env_or_skip {
    () => {
        match env().await {
            Some(e) => e,
            None => {
                eprintln!("TEST_DATABASE_URL ausente: teste de rota pulado");
                return;
            }
        }
    };
}

struct User {
    id: Uuid,
    token: String,
}

async fn user(e: &Env) -> User {
    let (id,): (Uuid,) = sqlx::query_as("INSERT INTO users (email) VALUES ($1) RETURNING id")
        .bind(format!("{}@teste.local", Uuid::new_v4()))
        .fetch_one(&e.state.pool)
        .await
        .unwrap();
    let (sid,): (Uuid,) = sqlx::query_as("INSERT INTO sessions (user_id, refresh_hash, expires_at) VALUES ($1, $2, now() + interval '1 day') RETURNING id")
        .bind(id)
        .bind(Uuid::new_v4().as_bytes().to_vec())
        .fetch_one(&e.state.pool)
        .await
        .unwrap();
    User { id, token: auth::issue_access(&e.state, id, sid).unwrap() }
}

struct Res {
    status: StatusCode,
    headers: axum::http::HeaderMap,
    body: Vec<u8>,
}

impl Res {
    fn json(&self) -> Value {
        serde_json::from_slice(&self.body).unwrap_or_else(|_| panic!("corpo não é JSON: {}", String::from_utf8_lossy(&self.body)))
    }
}

async fn call(e: &Env, method: Method, uri: &str, token: Option<&str>, body: Vec<u8>, extra: &[(&str, &str)]) -> Res {
    let mut req = Request::builder().method(method).uri(uri);
    if let Some(t) = token {
        req = req.header(header::AUTHORIZATION, format!("Bearer {t}"));
    }
    for (k, v) in extra {
        req = req.header(*k, *v);
    }
    let res = e.app.clone().oneshot(req.body(Body::from(body)).unwrap()).await.unwrap();
    let (parts, body) = res.into_parts();
    Res { status: parts.status, headers: parts.headers, body: body.collect().await.unwrap().to_bytes().to_vec() }
}

async fn send_json(e: &Env, method: Method, uri: &str, u: &User, v: Value) -> Res {
    call(e, method, uri, Some(&u.token), serde_json::to_vec(&v).unwrap(), &[("content-type", "application/json")]).await
}

async fn get(e: &Env, uri: &str, u: &User) -> Res {
    call(e, Method::GET, uri, Some(&u.token), vec![], &[]).await
}

async fn project(e: &Env, u: &User) -> String {
    send_json(e, Method::POST, "/api/projects", u, json!({"name": "teste"})).await.json()["id"].as_str().unwrap().to_string()
}

async fn upload(e: &Env, u: &User, bytes: &[u8]) -> (String, Res) {
    let hash = storage::hex_sha256(bytes);
    let r = call(e, Method::PUT, &format!("/api/samples/{hash}"), Some(&u.token), bytes.to_vec(), &[("content-type", "application/octet-stream")]).await;
    (hash, r)
}

fn wav16(rate: u32, samples: &[i16]) -> Vec<u8> {
    let payload: Vec<u8> = samples.iter().flat_map(|s| s.to_le_bytes()).collect();
    let mut v = b"RIFF".to_vec();
    v.extend((36 + payload.len() as u32).to_le_bytes());
    v.extend(b"WAVEfmt ");
    v.extend(16u32.to_le_bytes());
    v.extend([1, 0, 1, 0]); // PCM, mono
    v.extend(rate.to_le_bytes());
    v.extend((rate * 2).to_le_bytes());
    v.extend([2, 0, 16, 0]);
    v.extend(b"data");
    v.extend((payload.len() as u32).to_le_bytes());
    v.extend(payload);
    v
}

fn sine_wav(hz: f32, secs: f32) -> Vec<u8> {
    let rate = 44_100u32;
    let s: Vec<i16> = (0..(rate as f32 * secs) as usize).map(|i| (16_000.0 * (std::f32::consts::TAU * hz * i as f32 / rate as f32).sin()) as i16).collect();
    wav16(rate, &s)
}

// ---------------------------------------------------------------- documento

#[tokio::test]
async fn documento_versionado() {
    let e = env_or_skip!();
    let (a, b) = (user(&e).await, user(&e).await);
    let pid = project(&e, &a).await;
    let uri = format!("/api/projects/{pid}/doc");

    // sem documento ainda
    let r = get(&e, &uri, &a).await;
    assert_eq!(r.status, StatusCode::OK);
    let j = r.json();
    assert_eq!((j["version"].clone(), j["doc"].clone()), (json!(0), Value::Null));
    assert!(j["updated_at"].is_string());
    assert_eq!(r.headers[header::CACHE_CONTROL], "no-store");

    // primeira gravação parte da versão 0 e muda o updated_at do projeto
    let before = get(&e, &format!("/api/projects/{pid}"), &a).await.json()["updated_at"].clone();
    let r = send_json(&e, Method::PUT, &uri, &a, json!({"base_version": 0, "doc": {"tracks": [1]}})).await;
    assert_eq!(r.status, StatusCode::OK, "{:?}", String::from_utf8_lossy(&r.body));
    assert_eq!(r.json()["version"], 1);
    let after = get(&e, &format!("/api/projects/{pid}"), &a).await.json()["updated_at"].clone();
    assert_ne!(before, after, "o updated_at do projeto deveria mudar");

    let r = send_json(&e, Method::PUT, &uri, &a, json!({"base_version": 1, "doc": {"tracks": [1, 2]}})).await;
    assert_eq!((r.status, r.json()["version"].clone()), (StatusCode::OK, json!(2)));
    let j = get(&e, &uri, &a).await.json();
    assert_eq!((j["version"].clone(), j["doc"].clone()), (json!(2), json!({"tracks": [1, 2]})));

    // base velha: 409 com a versão e o documento do servidor
    let r = send_json(&e, Method::PUT, &uri, &a, json!({"base_version": 1, "doc": {"x": 1}})).await;
    assert_eq!(r.status, StatusCode::CONFLICT);
    let j = r.json();
    assert_eq!((j["version"].clone(), j["doc"].clone()), (json!(2), json!({"tracks": [1, 2]})));
    assert!(j["error"].is_string());
    // base 0 depois de já existir também conflita
    assert_eq!(send_json(&e, Method::PUT, &uri, &a, json!({"base_version": 0, "doc": {}})).await.status, StatusCode::CONFLICT);

    // entradas inválidas
    assert_eq!(send_json(&e, Method::PUT, &uri, &a, json!({"base_version": 2, "doc": [1]})).await.status, StatusCode::BAD_REQUEST);
    assert_eq!(send_json(&e, Method::PUT, &uri, &a, json!({"base_version": -1, "doc": {}})).await.status, StatusCode::BAD_REQUEST);
    assert_eq!(send_json(&e, Method::PUT, &uri, &a, json!({"base_version": 2, "doc": {"s": "a\u{0}b"}})).await.status, StatusCode::BAD_REQUEST);

    // alheio é 404, leitura e escrita; e sem login, 401
    assert_eq!(get(&e, &uri, &b).await.status, StatusCode::NOT_FOUND);
    assert_eq!(send_json(&e, Method::PUT, &uri, &b, json!({"base_version": 0, "doc": {}})).await.status, StatusCode::NOT_FOUND);
    assert_eq!(call(&e, Method::GET, &uri, None, vec![], &[]).await.status, StatusCode::UNAUTHORIZED);

    // apagar o projeto apaga o documento
    assert_eq!(call(&e, Method::DELETE, &format!("/api/projects/{pid}"), Some(&a.token), vec![], &[]).await.status, StatusCode::NO_CONTENT);
    let (n,): (i64,) =
        sqlx::query_as("SELECT count(*) FROM project_docs WHERE project_id = $1").bind(pid.parse::<Uuid>().unwrap()).fetch_one(&e.state.pool).await.unwrap();
    assert_eq!(n, 0);
}

#[tokio::test]
async fn documento_gravacoes_simultaneas_so_uma_vence() {
    let e = env_or_skip!();
    let a = user(&e).await;
    let pid = project(&e, &a).await;
    let uri = format!("/api/projects/{pid}/doc");
    let (r1, r2, r3) = tokio::join!(
        send_json(&e, Method::PUT, &uri, &a, json!({"base_version": 0, "doc": {"w": 1}})),
        send_json(&e, Method::PUT, &uri, &a, json!({"base_version": 0, "doc": {"w": 2}})),
        send_json(&e, Method::PUT, &uri, &a, json!({"base_version": 0, "doc": {"w": 3}})),
    );
    let mut codes = [r1.status, r2.status, r3.status];
    codes.sort();
    assert_eq!(codes, [StatusCode::OK, StatusCode::CONFLICT, StatusCode::CONFLICT]);
    assert_eq!(get(&e, &uri, &a).await.json()["version"], 1);
}

#[tokio::test]
async fn documento_grande_demais() {
    let e = env_or_skip!();
    let a = user(&e).await;
    let uri = format!("/api/projects/{}/doc", project(&e, &a).await);
    let big = format!(r#"{{"base_version":0,"doc":{{"blob":"{}"}}}}"#, "a".repeat(8 * 1024 * 1024));
    let r = call(&e, Method::PUT, &uri, Some(&a.token), big.into_bytes(), &[("content-type", "application/json")]).await;
    assert_eq!(r.status, StatusCode::PAYLOAD_TOO_LARGE);
    assert!(r.json()["error"].is_string());
    // um documento de ~3 MB (acima do limite padrão de 2 MB do axum) passa
    let ok = format!(r#"{{"base_version":0,"doc":{{"blob":"{}"}}}}"#, "a".repeat(3 * 1024 * 1024));
    let r = call(&e, Method::PUT, &uri, Some(&a.token), ok.into_bytes(), &[("content-type", "application/json")]).await;
    assert_eq!(r.status, StatusCode::OK);
}

// ---------------------------------------------------------------- samples

#[tokio::test]
async fn samples_ida_e_volta() {
    let e = env_or_skip!();
    let (a, b) = (user(&e).await, user(&e).await);
    let bytes: Vec<u8> = (0..5000u32).map(|i| (i * 7 % 251) as u8).chain(Uuid::new_v4().into_bytes()).collect();
    let hash = storage::hex_sha256(&bytes);
    let other = storage::hex_sha256(b"outro");

    let r = send_json(&e, Method::POST, "/api/samples/missing", &a, json!({"hashes": [hash, other, hash]})).await;
    assert_eq!(r.status, StatusCode::OK);
    assert_eq!(r.json()["missing"], json!([hash, other]), "sem repetir, na ordem");

    // hash que não confere com o corpo: 400, e nada fica registrado
    let r = call(&e, Method::PUT, &format!("/api/samples/{other}"), Some(&a.token), bytes.clone(), &[]).await;
    assert_eq!(r.status, StatusCode::BAD_REQUEST);
    assert!(r.json()["error"].is_string());
    // hash malformado: 400
    assert_eq!(call(&e, Method::PUT, "/api/samples/ABC", Some(&a.token), bytes.clone(), &[]).await.status, StatusCode::BAD_REQUEST);
    assert_eq!(call(&e, Method::PUT, &format!("/api/samples/{}", "A".repeat(64)), Some(&a.token), bytes.clone(), &[]).await.status, StatusCode::BAD_REQUEST);

    let (_, r) = upload(&e, &a, &bytes).await;
    assert_eq!(r.status, StatusCode::NO_CONTENT);
    // idempotente
    assert_eq!(upload(&e, &a, &bytes).await.1.status, StatusCode::NO_CONTENT);
    let (n,): (i64,) = sqlx::query_as("SELECT count(*) FROM samples WHERE owner_id = $1").bind(a.id).fetch_one(&e.state.pool).await.unwrap();
    assert_eq!(n, 1);

    let r = send_json(&e, Method::POST, "/api/samples/missing", &a, json!({"hashes": [hash, other]})).await;
    assert_eq!(r.json()["missing"], json!([other]));

    // leitura: bytes, tipo, e o cache imutável vence o no-store do resto da API
    let r = get(&e, &format!("/api/samples/{hash}"), &a).await;
    assert_eq!(r.status, StatusCode::OK);
    assert_eq!(r.body, bytes);
    assert_eq!(r.headers[header::CONTENT_TYPE], "application/octet-stream");
    assert_eq!(r.headers[header::CACHE_CONTROL], "private, max-age=31536000, immutable");
    assert_eq!(r.headers[header::CONTENT_LENGTH], bytes.len().to_string());

    // outra conta não lê, e para ela o hash continua faltando (mesmo com o arquivo já em disco)
    assert_eq!(get(&e, &format!("/api/samples/{hash}"), &b).await.status, StatusCode::NOT_FOUND);
    let r = send_json(&e, Method::POST, "/api/samples/missing", &b, json!({"hashes": [hash]})).await;
    assert_eq!(r.json()["missing"], json!([hash]));
    // ... e ela só "tem" o áudio provando que possui o conteúdo
    let r = call(&e, Method::PUT, &format!("/api/samples/{hash}"), Some(&b.token), b"chute".to_vec(), &[]).await;
    assert_eq!(r.status, StatusCode::BAD_REQUEST);
    assert_eq!(upload(&e, &b, &bytes).await.1.status, StatusCode::NO_CONTENT);
    assert_eq!(get(&e, &format!("/api/samples/{hash}"), &b).await.body, bytes);

    // validações do missing e login
    let many: Vec<String> = (0..2001).map(|i| storage::hex_sha256(i.to_string().as_bytes())).collect();
    assert_eq!(send_json(&e, Method::POST, "/api/samples/missing", &a, json!({ "hashes": many })).await.status, StatusCode::BAD_REQUEST);
    assert_eq!(send_json(&e, Method::POST, "/api/samples/missing", &a, json!({"hashes": ["xyz"]})).await.status, StatusCode::BAD_REQUEST);
    assert_eq!(call(&e, Method::GET, &format!("/api/samples/{hash}"), None, vec![], &[]).await.status, StatusCode::UNAUTHORIZED);

    // o resto da API segue com no-store
    assert_eq!(get(&e, "/api/jobs", &a).await.headers[header::CACHE_CONTROL], "no-store");
}

#[tokio::test]
async fn samples_limites_de_tamanho_e_cota() {
    let e = env_or_skip!();
    let a = user(&e).await;
    let body = Uuid::new_v4().into_bytes().to_vec();
    let hash = storage::hex_sha256(&body);
    // Content-Length acima de 512 MB: recusa antes de ler o corpo
    let r = call(&e, Method::PUT, &format!("/api/samples/{hash}"), Some(&a.token), body.clone(), &[("content-length", "600000000")]).await;
    assert_eq!(r.status, StatusCode::PAYLOAD_TOO_LARGE);
    assert!(r.json()["error"].as_str().unwrap().contains("512"));
    // conta quase na cota: o próximo não cabe
    sqlx::query("INSERT INTO samples (owner_id, hash, size) VALUES ($1, $2, $3)")
        .bind(a.id)
        .bind(storage::hex_sha256(b"enorme"))
        .bind(storage::QUOTA_BYTES - 10)
        .execute(&e.state.pool)
        .await
        .unwrap();
    let (_, r) = upload(&e, &a, &body).await;
    assert_eq!(r.status, StatusCode::PAYLOAD_TOO_LARGE);
    assert!(r.json()["error"].as_str().unwrap().contains("cota"));
    let (n,): (i64,) =
        sqlx::query_as("SELECT count(*) FROM samples WHERE owner_id = $1 AND hash = $2").bind(a.id).bind(&hash).fetch_one(&e.state.pool).await.unwrap();
    assert_eq!(n, 0);
}

#[tokio::test]
async fn faxina_apaga_so_o_que_nao_tem_registro() {
    let e = env_or_skip!();
    let store = &e.state.store;
    let a = user(&e).await;
    let kept = Uuid::new_v4().into_bytes().to_vec();
    let (kept_hash, _) = upload(&e, &a, &kept).await;
    let orphan = Uuid::new_v4().into_bytes().to_vec();
    let orphan_hash = storage::hex_sha256(&orphan);
    store.store_bytes(&orphan_hash, &orphan).await.unwrap();
    // o S3 não deixa forjar a data do objeto: em vez de `set_modified`, o corte da faxina fica entre
    // o que já existe e o órfão "recente", criado depois de uma pausa (a data do S3 tem resolução
    // de milissegundos ou segundos, conforme o servidor)
    tokio::time::sleep(Duration::from_millis(2200)).await;
    let cutoff = std::time::SystemTime::now();
    tokio::time::sleep(Duration::from_millis(2200)).await;
    let fresh = Uuid::new_v4().into_bytes().to_vec();
    let fresh_hash = storage::hex_sha256(&fresh);
    store.store_bytes(&fresh_hash, &fresh).await.unwrap();

    storage::cleanup_before(&e.state.pool, store, cutoff).await.unwrap();
    assert!(store.exists(&kept_hash).await.unwrap(), "com registro fica");
    assert!(!store.exists(&orphan_hash).await.unwrap(), "sem registro e antigo sai");
    assert!(store.exists(&fresh_hash).await.unwrap(), "sem registro mas recente fica");

    // a faxina de verdade (1 hora) não mexe em nada recente
    storage::cleanup(&e.state.pool, store).await.unwrap();
    assert!(store.exists(&fresh_hash).await.unwrap());
    store.delete(&fresh_hash).await.unwrap();
}

#[tokio::test]
async fn armazenamento_operacoes_basicas() {
    let e = env_or_skip!();
    let store = &e.state.store;
    let bytes = Uuid::new_v4().into_bytes().repeat(1000);
    let hash = storage::hex_sha256(&bytes);
    assert!(!store.exists(&hash).await.unwrap());
    assert!(store.open(&hash).await.unwrap().is_none());
    assert!(store.read(&hash).await.unwrap().is_none());

    store.store_bytes(&hash, &bytes).await.unwrap();
    // gravar de novo o mesmo conteúdo é idempotente
    store.store_bytes(&hash, &bytes).await.unwrap();
    assert!(store.exists(&hash).await.unwrap());
    assert_eq!(store.read(&hash).await.unwrap().unwrap(), bytes);
    assert_eq!(store.open(&hash).await.unwrap().unwrap().len, Some(bytes.len() as u64));
    assert!(store.list().await.unwrap().iter().any(|b| b.hash == hash));

    store.delete(&hash).await.unwrap();
    store.delete(&hash).await.unwrap(); // apagar o que não existe também passa
    assert!(!store.exists(&hash).await.unwrap());
    assert!(!store.list().await.unwrap().iter().any(|b| b.hash == hash));
}

#[tokio::test]
async fn upload_nao_deixa_temporario_para_tras() {
    let e = env_or_skip!();
    let a = user(&e).await;
    let tmp = data_dir().join("tmp");
    // os testes rodam em paralelo e dividem a pasta: só conta o que tem o conteúdo deste teste
    let marker = Uuid::new_v4().into_bytes().repeat(64);
    let leftovers = |marker: &[u8]| -> usize {
        std::fs::read_dir(&tmp).map(|rd| rd.flatten().filter(|f| std::fs::read(f.path()).is_ok_and(|b| b.starts_with(marker))).count()).unwrap_or(0)
    };
    let (_, ok) = upload(&e, &a, &marker).await;
    assert_eq!(ok.status, StatusCode::NO_CONTENT);
    let hash = storage::hex_sha256(&marker);
    let bad = call(&e, Method::PUT, &format!("/api/samples/{}", storage::hex_sha256(b"outro-hash")), Some(&a.token), marker.clone(), &[]).await;
    assert_eq!(bad.status, StatusCode::BAD_REQUEST);
    // já existe no armazenamento (outra conta): o corpo é conferido e o temporário some sem regravar
    let b = user(&e).await;
    assert_eq!(upload(&e, &b, &marker).await.1.status, StatusCode::NO_CONTENT);
    assert_eq!(leftovers(&marker), 0);
    assert_eq!(get(&e, &format!("/api/samples/{hash}"), &b).await.body, marker);
}

#[tokio::test]
async fn migracao_do_disco_para_o_s3_e_idempotente() {
    let e = env_or_skip!();
    let store = &e.state.store;
    if store.kind() != "S3" {
        eprintln!("sem S3_ENDPOINT: teste da migração pulado");
        return;
    }
    // um DATA_DIR antigo, só em disco
    let old = std::env::temp_dir().join(format!("jopendaw-migra-{}", Uuid::new_v4()));
    let disk = storage::Store::from_config(&Config { s3: None, data_dir: old.clone(), ..(*e.state.cfg).clone() }).unwrap();
    let blobs: Vec<Vec<u8>> = (0..3).map(|_| Uuid::new_v4().into_bytes().repeat(100)).collect();
    for b in &blobs {
        disk.store_bytes(&storage::hex_sha256(b), b).await.unwrap();
    }
    assert_eq!(store.import_from_disk(&old).await.unwrap(), (3, 0));
    for b in &blobs {
        assert_eq!(store.read(&storage::hex_sha256(b)).await.unwrap().unwrap(), *b);
    }
    // segunda rodada: nada a copiar
    assert_eq!(store.import_from_disk(&old).await.unwrap(), (0, 3));
    for b in &blobs {
        store.delete(&storage::hex_sha256(b)).await.unwrap();
    }
    std::fs::remove_dir_all(old).unwrap();
}

// ---------------------------------------------------------------- jobs

async fn wait_job(e: &Env, u: &User, id: &str) -> Value {
    for _ in 0..200 {
        let j = get(e, &format!("/api/jobs/{id}"), u).await.json();
        if matches!(j["status"].as_str(), Some("done" | "failed")) {
            return j;
        }
        tokio::time::sleep(Duration::from_millis(50)).await;
    }
    panic!("a tarefa {id} não terminou");
}

async fn new_job(e: &Env, u: &User, kind: &str, sample: &str, params: Option<Value>) -> Res {
    let mut b = json!({"kind": kind, "sample": sample});
    if let Some(p) = params {
        b["params"] = p;
    }
    send_json(e, Method::POST, "/api/jobs", u, b).await
}

#[tokio::test]
async fn job_flac() {
    let e = env_or_skip!();
    let a = user(&e).await;
    let (hash, r) = upload(&e, &a, &sine_wav(440.0, 0.5)).await;
    assert_eq!(r.status, StatusCode::NO_CONTENT);

    let r = new_job(&e, &a, "flac", &hash, None).await;
    assert_eq!(r.status, StatusCode::ACCEPTED);
    let j = r.json();
    assert_eq!(j["status"], "queued");
    let id = j["id"].as_str().unwrap().to_string();

    let j = wait_job(&e, &a, &id).await;
    assert_eq!(j["status"], "done", "{j}");
    assert_eq!((j["progress"].clone(), j["error"].clone(), j["kind"].clone()), (json!(1.0), Value::Null, json!("flac")));
    let flac_hash = j["result"]["sample"].as_str().unwrap().to_string();
    assert!(j["result"]["bytes"].as_u64().unwrap() > 100);

    // o FLAC ficou no armazenamento da conta, legível, e com o hash e o tamanho declarados
    let r = get(&e, &format!("/api/samples/{flac_hash}"), &a).await;
    assert_eq!(r.status, StatusCode::OK);
    assert_eq!(&r.body[..4], b"fLaC");
    assert_eq!(storage::hex_sha256(&r.body), flac_hash);
    assert_eq!(r.body.len() as u64, j["result"]["bytes"].as_u64().unwrap());

    // aparece na listagem
    let l = get(&e, "/api/jobs", &a).await.json();
    assert!(l.as_array().unwrap().iter().any(|x| x["id"] == id));
}

#[tokio::test]
async fn job_audio_para_midi() {
    let e = env_or_skip!();
    let a = user(&e).await;
    let mut samples: Vec<i16> = Vec::new();
    let rate = 44_100usize;
    for (hz, secs) in [(440.0f32, 0.5f32), (0.0, 0.2), (660.0, 0.5)] {
        samples.extend((0..(rate as f32 * secs) as usize).map(|i| (12_000.0 * (std::f32::consts::TAU * hz * i as f32 / rate as f32).sin()) as i16));
    }
    let (hash, _) = upload(&e, &a, &wav16(rate as u32, &samples)).await;
    let r = new_job(&e, &a, "audio_to_midi", &hash, Some(json!({"min_note_ms": 80, "rms_floor_db": -50}))).await;
    assert_eq!(r.status, StatusCode::ACCEPTED);
    let j = wait_job(&e, &a, r.json()["id"].as_str().unwrap()).await;
    assert_eq!(j["status"], "done", "{j}");
    let notes = j["result"]["notes"].as_array().unwrap();
    assert_eq!(notes.iter().map(|n| n["pitch"].as_i64().unwrap()).collect::<Vec<_>>(), vec![69, 76], "{j}");
    assert!((j["result"]["duration"].as_f64().unwrap() - 1.2).abs() < 0.01);
    for n in notes {
        assert!(n["start"].is_f64() && n["length"].as_f64().unwrap() > 0.3);
        assert!((0.0..=1.0).contains(&n["velocity"].as_f64().unwrap()));
    }
}

#[tokio::test]
async fn job_formato_nao_suportado_falha() {
    let e = env_or_skip!();
    let a = user(&e).await;
    let (hash, _) = upload(&e, &a, b"isto nao e um wav, e so texto").await;
    for kind in ["flac", "audio_to_midi"] {
        let r = new_job(&e, &a, kind, &hash, None).await;
        let j = wait_job(&e, &a, r.json()["id"].as_str().unwrap()).await;
        assert_eq!(j["status"], "failed");
        assert!(j["error"].as_str().unwrap().starts_with("formato de áudio não suportado"), "{j}");
        assert_eq!(j["result"], Value::Null);
    }
}

#[tokio::test]
async fn job_validacoes_dono_e_limite() {
    let e = env_or_skip!();
    let (a, b) = (user(&e).await, user(&e).await);
    let (hash, _) = upload(&e, &a, &sine_wav(330.0, 0.3)).await;

    assert_eq!(new_job(&e, &a, "mp3", &hash, None).await.status, StatusCode::BAD_REQUEST);
    assert_eq!(new_job(&e, &a, "flac", "xyz", None).await.status, StatusCode::BAD_REQUEST);
    assert_eq!(new_job(&e, &a, "audio_to_midi", &hash, Some(json!({"min_note_ms": -1}))).await.status, StatusCode::BAD_REQUEST);
    assert_eq!(new_job(&e, &a, "audio_to_midi", &hash, Some(json!({"rms_floor_db": 5}))).await.status, StatusCode::BAD_REQUEST);
    assert_eq!(new_job(&e, &a, "audio_to_midi", &hash, Some(json!("x"))).await.status, StatusCode::BAD_REQUEST);
    // params que não é objeto vale para os dois tipos, o FLAC inclusive
    for p in [json!("x"), json!([1]), json!(3)] {
        assert_eq!(new_job(&e, &a, "flac", &hash, Some(p)).await.status, StatusCode::BAD_REQUEST);
    }
    // `start` sem `end` é recusado na criação (senão só falharia na decodificação); `start` 0 sem `end` é o arquivo inteiro
    let r = new_job(&e, &a, "audio_to_midi", &hash, Some(json!({"start": 5}))).await;
    assert_eq!(r.status, StatusCode::BAD_REQUEST);
    assert!(r.json()["error"].as_str().unwrap().contains("end"), "{}", r.json());
    assert_eq!(new_job(&e, &a, "audio_to_midi", &hash, Some(json!({"start": 0}))).await.status, StatusCode::ACCEPTED);
    // áudio que a conta não tem: 404 (inclusive o que é de outra conta)
    assert_eq!(new_job(&e, &a, "flac", &storage::hex_sha256(b"nada"), None).await.status, StatusCode::NOT_FOUND);
    assert_eq!(new_job(&e, &b, "flac", &hash, None).await.status, StatusCode::NOT_FOUND);
    assert_eq!(call(&e, Method::POST, "/api/jobs", None, b"{}".to_vec(), &[]).await.status, StatusCode::UNAUTHORIZED);

    // tarefa de outra conta: 404 no detalhe e fora da listagem
    let id = new_job(&e, &a, "flac", &hash, None).await.json()["id"].as_str().unwrap().to_string();
    assert_eq!(get(&e, &format!("/api/jobs/{id}"), &b).await.status, StatusCode::NOT_FOUND);
    assert!(get(&e, "/api/jobs", &b).await.json().as_array().unwrap().is_empty());
    assert_eq!(get(&e, &format!("/api/jobs/{}", Uuid::new_v4()), &a).await.status, StatusCode::NOT_FOUND);
    wait_job(&e, &a, &id).await;

    // 10 tarefas ativas: a 11ª leva 429 (ativas plantadas direto no banco, sem corrida com o worker)
    let c = user(&e).await;
    let (chash, _) = upload(&e, &c, &sine_wav(330.0, 0.3)).await;
    for _ in 0..10 {
        // `running` de outro processo: o worker não pega
        sqlx::query("INSERT INTO jobs (owner_id, kind, sample_hash, status) VALUES ($1, 'flac', $2, 'running')")
            .bind(c.id)
            .bind(&chash)
            .execute(&e.state.pool)
            .await
            .unwrap();
    }
    let r = new_job(&e, &c, "flac", &chash, None).await;
    assert_eq!(r.status, StatusCode::TOO_MANY_REQUESTS);
    assert!(r.json()["error"].is_string());
    // outra conta não é afetada
    assert_eq!(new_job(&e, &a, "flac", &hash, None).await.status, StatusCode::ACCEPTED);
}

#[tokio::test]
async fn job_orfao_volta_para_a_fila() {
    let e = env_or_skip!();
    let a = user(&e).await;
    let (hash, _) = upload(&e, &a, &sine_wav(330.0, 0.3)).await;
    let (id,): (Uuid,) =
        sqlx::query_as("INSERT INTO jobs (owner_id, kind, sample_hash, status, progress) VALUES ($1, 'flac', $2, 'running', 0.5) RETURNING id")
            .bind(a.id)
            .bind(&hash)
            .fetch_one(&e.state.pool)
            .await
            .unwrap();
    // só as desta conta: o `running` de outros testes é proposital
    routes::jobs::requeue(&e.state.pool, Some(a.id)).await.unwrap();
    // o worker do teste (ou o de outro teste) pega e termina. Se o pegou o worker de um teste que já acabou (o runtime
    // dele morre no meio), a tarefa fica `running` para sempre: recolocar na fila de novo faz parte do que se testa
    let mut j = Value::Null;
    for _ in 0..20 {
        j = get(&e, &format!("/api/jobs/{id}"), &a).await.json();
        if j["status"] == "done" {
            break;
        }
        tokio::time::sleep(Duration::from_millis(250)).await;
        routes::jobs::requeue(&e.state.pool, Some(a.id)).await.unwrap();
    }
    assert_eq!(j["status"], "done", "{j}");
}

// ---------------------------------------------------------------- áudios: listar, apagar, cota

async fn put_doc(e: &Env, u: &User, project: &str, base: i64, doc: Value) -> Res {
    send_json(e, Method::PUT, &format!("/api/projects/{project}/doc"), u, json!({"base_version": base, "doc": doc})).await
}

async fn del(e: &Env, uri: &str, u: &User) -> Res {
    call(e, Method::DELETE, uri, Some(&u.token), vec![], &[]).await
}

/// Apaga insistindo (`force=true`): os áudios dos testes acabaram de ser enviados e a proteção do envio recente os seguraria.
async fn del_force(e: &Env, hash: &str, u: &User) -> Res {
    del(e, &format!("/api/samples/{hash}?force=true"), u).await
}

async fn post_empty(e: &Env, uri: &str, token: Option<&str>) -> Res {
    call(e, Method::POST, uri, token, vec![], &[]).await
}

fn sample_row<'a>(list: &'a Value, hash: &str) -> &'a Value {
    list["samples"].as_array().unwrap().iter().find(|s| s["hash"] == hash).unwrap_or_else(|| panic!("{hash} fora da lista: {list}"))
}

fn rand_bytes() -> Vec<u8> {
    Uuid::new_v4().into_bytes().to_vec()
}

/// Faz o áudio parecer enviado há muito tempo (a limpeza em massa poupa o da última hora).
async fn backdate(e: &Env, u: &User, hash: &str) {
    sqlx::query("UPDATE samples SET created_at = now() - interval '2 hours' WHERE owner_id = $1 AND hash = $2")
        .bind(u.id)
        .bind(hash)
        .execute(&e.state.pool)
        .await
        .unwrap();
}

#[tokio::test]
async fn samples_listar_e_apagar() {
    let e = env_or_skip!();
    let a = user(&e).await;
    let (used_clip, _) = upload(&e, &a, &rand_bytes()).await;
    let (used_zone, _) = upload(&e, &a, &rand_bytes()).await;
    let (loose_hash, _) = upload(&e, &a, &rand_bytes()).await;

    // sem documento nenhum: tudo sem uso
    let l = get(&e, "/api/samples", &a).await.json();
    assert_eq!(l["quota_bytes"], storage::QUOTA_BYTES);
    assert_eq!((l["used_bytes"].as_i64().unwrap(), l["unused_count"].as_u64().unwrap()), (48, 3));

    // um documento cita um áudio pelo mapa `samples` e no clipe, outro só pela zona de um sampler
    let p1 = project(&e, &a).await;
    let p2 = project(&e, &a).await;
    let doc1 = json!({"samples": {used_clip.clone(): {"name": "kick.wav", "duration": 1.0}}, "tracks": [{"audio": [{"sample": used_clip}]}]});
    assert_eq!(put_doc(&e, &a, &p1, 0, doc1).await.status, StatusCode::OK);
    let doc2 = json!({"tracks": [{"sampler": {"sample": null, "zones": [{"sample": used_zone, "low": 0}]}}]});
    assert_eq!(put_doc(&e, &a, &p2, 0, doc2).await.status, StatusCode::OK);

    let l = get(&e, "/api/samples", &a).await.json();
    let s = sample_row(&l, &used_clip);
    assert_eq!((s["name"].as_str(), s["unused"].clone(), s["project_count"].clone(), s["size"].clone()), (Some("kick.wav"), json!(false), json!(1), json!(16)));
    assert_eq!(s["projects"][0]["id"], p1);
    assert_eq!(sample_row(&l, &used_zone)["project_count"], 1, "a zona do sampler conta como uso");
    assert_eq!(sample_row(&l, &loose_hash)["unused"], true);
    assert_eq!((l["unused_bytes"].as_i64().unwrap(), l["unused_count"].as_u64().unwrap()), (16, 1));

    // em uso: 409 com os projetos, e nada é apagado
    for h in [&used_clip, &used_zone] {
        let r = del(&e, &format!("/api/samples/{h}"), &a).await;
        assert_eq!(r.status, StatusCode::CONFLICT);
        assert_eq!(r.json()["projects"].as_array().unwrap().len(), 1);
        assert!(e.state.store.exists(h).await.unwrap());
    }
    // recém-enviado e sem uso: o documento que o cita pode não ter chegado, então o apagar avisa (409) e o usuário confirma
    let l = get(&e, "/api/samples", &a).await.json();
    assert_eq!(sample_row(&l, &loose_hash)["recent"], true);
    let r = del(&e, &format!("/api/samples/{loose_hash}"), &a).await;
    assert_eq!((r.status, r.json()["recent"].clone()), (StatusCode::CONFLICT, json!(true)));
    assert!(r.json()["error"].as_str().unwrap().contains("enviado há pouco"));
    assert!(e.state.store.exists(&loose_hash).await.unwrap());
    // com a folga vencida apaga sem insistir
    backdate(&e, &a, &loose_hash).await;
    assert_eq!(sample_row(&get(&e, "/api/samples", &a).await.json(), &loose_hash)["recent"], false);
    // sem uso: sai do registro e do armazenamento, e a cota volta
    let r = del(&e, &format!("/api/samples/{loose_hash}"), &a).await;
    assert_eq!((r.status, r.json()["freed_bytes"].clone()), (StatusCode::OK, json!(16)));
    assert!(!e.state.store.exists(&loose_hash).await.unwrap());
    assert_eq!(get(&e, &format!("/api/samples/{loose_hash}"), &a).await.status, StatusCode::NOT_FOUND);
    assert_eq!(get(&e, "/api/samples", &a).await.json()["used_bytes"], 32);
    // de novo, hash inválido e sem login
    assert_eq!(del(&e, &format!("/api/samples/{loose_hash}"), &a).await.status, StatusCode::NOT_FOUND);
    assert_eq!(del(&e, "/api/samples/xyz", &a).await.status, StatusCode::NOT_FOUND);
    assert_eq!(call(&e, Method::DELETE, &format!("/api/samples/{used_clip}"), None, vec![], &[]).await.status, StatusCode::UNAUTHORIZED);
    assert_eq!(call(&e, Method::GET, "/api/samples", None, vec![], &[]).await.status, StatusCode::UNAUTHORIZED);

    // apagar o projeto NÃO apaga o áudio: ele passa a constar como sem uso, e a decisão fica com a pessoa
    assert_eq!(del(&e, &format!("/api/projects/{p1}"), &a).await.status, StatusCode::NO_CONTENT);
    let l = get(&e, "/api/samples", &a).await.json();
    assert_eq!((sample_row(&l, &used_clip)["unused"].clone(), l["used_bytes"].clone()), (json!(true), json!(32)));
    assert!(e.state.store.exists(&used_clip).await.unwrap());
    // recente (acabou de ser enviado) mas a pessoa confirma: force=true
    assert_eq!(del(&e, &format!("/api/samples/{used_clip}"), &a).await.status, StatusCode::CONFLICT);
    assert_eq!(del_force(&e, &used_clip, &a).await.status, StatusCode::OK);
}

#[tokio::test]
async fn samples_apagar_devolve_a_cota() {
    let e = env_or_skip!();
    let a = user(&e).await;
    let fake = storage::hex_sha256(b"enorme");
    sqlx::query("INSERT INTO samples (owner_id, hash, size) VALUES ($1, $2, $3)")
        .bind(a.id)
        .bind(&fake)
        .bind(storage::QUOTA_BYTES - 10)
        .execute(&e.state.pool)
        .await
        .unwrap();
    let body = rand_bytes();
    let (hash, r) = upload(&e, &a, &body).await;
    assert_eq!(r.status, StatusCode::PAYLOAD_TOO_LARGE);
    assert!(r.json()["error"].as_str().unwrap().contains("Conta"), "a mensagem aponta a saída");

    let r = del_force(&e, &fake, &a).await;
    assert_eq!((r.status, r.json()["freed_bytes"].as_i64()), (StatusCode::OK, Some(storage::QUOTA_BYTES - 10)));
    let (_, r) = upload(&e, &a, &body).await;
    assert_eq!(r.status, StatusCode::NO_CONTENT);
    assert_eq!(get(&e, "/api/samples", &a).await.json()["used_bytes"], 16);
    assert!(e.state.store.exists(&hash).await.unwrap());
}

#[tokio::test]
async fn samples_isolamento_entre_contas_e_hash_igual() {
    let e = env_or_skip!();
    let (a, b) = (user(&e).await, user(&e).await);
    let body = rand_bytes();
    let (hash, _) = upload(&e, &a, &body).await;
    // a conta B nunca enviou: não pode apagar, nem ver o áudio da A
    assert_eq!(del(&e, &format!("/api/samples/{hash}"), &b).await.status, StatusCode::NOT_FOUND);
    assert!(get(&e, "/api/samples", &b).await.json()["samples"].as_array().unwrap().is_empty());
    assert!(e.state.store.exists(&hash).await.unwrap());
    assert_eq!(get(&e, &format!("/api/samples/{hash}"), &a).await.status, StatusCode::OK);

    // as duas enviam o mesmo conteúdo; a B usa num projeto dela, a A não usa em nenhum
    let (_, r) = upload(&e, &b, &body).await;
    assert_eq!(r.status, StatusCode::NO_CONTENT);
    let pb = project(&e, &b).await;
    assert_eq!(put_doc(&e, &b, &pb, 0, json!({"samples": {hash.clone(): {"name": "x.wav", "duration": 1.0}}})).await.status, StatusCode::OK);
    // o projeto da B não segura o áudio da A (mas segura o da própria B)
    assert_eq!(del(&e, &format!("/api/samples/{hash}"), &b).await.status, StatusCode::CONFLICT);
    assert_eq!(del_force(&e, &hash, &a).await.status, StatusCode::OK);
    // os bytes ficam, porque a B ainda os registra; a B lê normalmente
    assert!(e.state.store.exists(&hash).await.unwrap());
    let r = get(&e, &format!("/api/samples/{hash}"), &b).await;
    assert_eq!((r.status, r.body), (StatusCode::OK, body.clone()));
    assert_eq!(get(&e, &format!("/api/samples/{hash}"), &a).await.status, StatusCode::NOT_FOUND);
    assert_eq!(get(&e, "/api/samples", &b).await.json()["samples"].as_array().unwrap().len(), 1);

    // quando a B também larga, aí sim os bytes saem
    assert_eq!(put_doc(&e, &b, &pb, 1, json!({"samples": {}})).await.status, StatusCode::OK);
    assert_eq!(del_force(&e, &hash, &b).await.status, StatusCode::OK);
    assert!(!e.state.store.exists(&hash).await.unwrap());
}

#[tokio::test]
async fn samples_limpar_sem_uso() {
    let e = env_or_skip!();
    let (a, b) = (user(&e).await, user(&e).await);
    let (kept, _) = upload(&e, &a, &rand_bytes()).await;
    let (old, _) = upload(&e, &a, &rand_bytes()).await;
    let (fresh, _) = upload(&e, &a, &rand_bytes()).await;
    let (busy, _) = upload(&e, &a, &rand_bytes()).await;
    let (bs, _) = upload(&e, &b, &rand_bytes()).await;
    let p = project(&e, &a).await;
    assert_eq!(put_doc(&e, &a, &p, 0, json!({"tracks": [{"audio": [{"sample": kept}]}]})).await.status, StatusCode::OK);
    for h in [&kept, &old, &busy] {
        backdate(&e, &a, h).await;
    }
    backdate(&e, &b, &bs).await;
    // uma tarefa em andamento com o áudio: fica
    sqlx::query("INSERT INTO jobs (owner_id, kind, sample_hash, status) VALUES ($1, 'flac', $2, 'running')")
        .bind(a.id)
        .bind(&busy)
        .execute(&e.state.pool)
        .await
        .unwrap();
    assert_eq!(del(&e, &format!("/api/samples/{busy}"), &a).await.status, StatusCode::CONFLICT);

    let r = post_empty(&e, "/api/samples/cleanup", Some(&a.token)).await;
    assert_eq!(r.status, StatusCode::OK);
    assert_eq!(r.json(), json!({"removed": 1, "freed_bytes": 16, "skipped_recent": 1, "skipped_in_use": 0, "skipped_job": 1}));
    assert!(!e.state.store.exists(&old).await.unwrap());
    for h in [&kept, &fresh, &busy] {
        assert!(e.state.store.exists(h).await.unwrap(), "{h} deveria ter ficado");
    }
    // o áudio da outra conta é intocado, mesmo velho e sem uso
    assert_eq!(get(&e, &format!("/api/samples/{bs}"), &b).await.status, StatusCode::OK);
    assert_eq!(post_empty(&e, "/api/samples/cleanup", None).await.status, StatusCode::UNAUTHORIZED);
    // de novo: nada mais a fazer
    assert_eq!(post_empty(&e, "/api/samples/cleanup", Some(&a.token)).await.json()["removed"], 0);
}

#[tokio::test]
async fn job_audio_para_midi_mp3_e_parametros_extremos() {
    let e = env_or_skip!();
    let a = user(&e).await;
    let mp3 = std::fs::read(std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("testdata/seno440.mp3")).unwrap();
    let (hash, _) = upload(&e, &a, &mp3).await;
    let r = new_job(&e, &a, "audio_to_midi", &hash, Some(json!({"min_note_ms": 100, "rms_floor_db": -40}))).await;
    let j = wait_job(&e, &a, r.json()["id"].as_str().unwrap()).await;
    assert_eq!(j["status"], "done", "{j}");
    assert!(j["result"]["notes"].as_array().unwrap().iter().any(|n| n["pitch"] == 69), "{j}");
    // extremos: fora da faixa é 400 na criação; nos limites da faixa a tarefa roda sem quebrar
    for p in [
        json!({"min_note_ms": 5001}),
        json!({"min_note_ms": -0.5}),
        json!({"rms_floor_db": -121}),
        json!({"rms_floor_db": 0.1}),
        json!({"rms_floor_db": 0}),
        json!({"rms_floor_db": -9.9}),
        json!({"min_note_ms": "x"}),
    ] {
        assert_eq!(new_job(&e, &a, "audio_to_midi", &hash, Some(p)).await.status, StatusCode::BAD_REQUEST);
    }
    let r = new_job(&e, &a, "audio_to_midi", &hash, Some(json!({"rms_floor_db": -6}))).await;
    assert_eq!(r.status, StatusCode::BAD_REQUEST);
    let msg = r.json()["error"].as_str().unwrap().to_string();
    assert!(msg.contains("-120") && msg.contains("-10"), "{msg}");
    for p in [json!({"min_note_ms": 5000, "rms_floor_db": -10}), json!({"min_note_ms": 0, "rms_floor_db": -120})] {
        let r = new_job(&e, &a, "audio_to_midi", &hash, Some(p)).await;
        let j = wait_job(&e, &a, r.json()["id"].as_str().unwrap()).await;
        assert_eq!(j["status"], "done", "{j}");
    }
}

// ---------------------------------------------------------------- endurecimento (fase 11)

/// Segura a trava por hash como faria um envio ou apagar em andamento, até a transação ser confirmada.
async fn hold_lock(e: &Env, hash: &str) -> sqlx::Transaction<'static, sqlx::Postgres> {
    storage::lock_hash(&e.state.pool, hash).await.unwrap()
}

fn clone_user(u: &User) -> User {
    User { id: u.id, token: u.token.clone() }
}

#[tokio::test]
async fn limpar_revalida_documento_que_chegou_depois_da_lista() {
    let e = Arc::new(env_or_skip!());
    let a = user(&e).await;
    let (h, _) = upload(&e, &a, &rand_bytes()).await;
    backdate(&e, &a, &h).await;
    let p = project(&e, &a).await;
    // o cleanup lê os documentos (nada cita h), e só então chega o documento que cita
    let lock = hold_lock(&e, &h).await;
    let (e2, tok) = (e.clone(), a.token.clone());
    let task = tokio::spawn(async move { call(&e2, Method::POST, "/api/samples/cleanup", Some(&tok), vec![], &[]).await });
    tokio::time::sleep(Duration::from_millis(400)).await;
    sqlx::query("INSERT INTO project_docs (project_id, version, doc) VALUES ($1, 1, $2)")
        .bind(Uuid::parse_str(&p).unwrap())
        .bind(sqlx::types::Json(json!({"tracks": [{"audio": [{"sample": h}]}]})))
        .execute(&e.state.pool)
        .await
        .unwrap();
    lock.commit().await.unwrap();
    let r = task.await.unwrap();
    assert_eq!(r.json()["removed"], 0, "{}", r.json());
    assert_eq!(r.json()["skipped_in_use"], 1, "{}", r.json());
    assert!(e.state.store.exists(&h).await.unwrap());
    assert_eq!(get(&e, &format!("/api/samples/{h}"), &a).await.status, StatusCode::OK);
}

#[tokio::test]
async fn limpar_nao_apaga_o_que_ganhou_tarefa_no_meio() {
    let e = Arc::new(env_or_skip!());
    let a = user(&e).await;
    let (h, _) = upload(&e, &a, &rand_bytes()).await;
    backdate(&e, &a, &h).await;
    let lock = hold_lock(&e, &h).await;
    let (e2, tok) = (e.clone(), a.token.clone());
    let task = tokio::spawn(async move { call(&e2, Method::POST, "/api/samples/cleanup", Some(&tok), vec![], &[]).await });
    tokio::time::sleep(Duration::from_millis(400)).await;
    sqlx::query("INSERT INTO jobs (owner_id, kind, sample_hash, status) VALUES ($1, 'flac', $2, 'running')")
        .bind(a.id)
        .bind(&h)
        .execute(&e.state.pool)
        .await
        .unwrap();
    lock.commit().await.unwrap();
    let r = task.await.unwrap().json();
    assert_eq!((r["removed"].clone(), r["skipped_job"].clone()), (json!(0), json!(1)), "{r}");
    assert!(e.state.store.exists(&h).await.unwrap());
}

#[tokio::test]
async fn criar_tarefa_e_apagar_do_mesmo_audio_nao_se_cruzam() {
    let e = Arc::new(env_or_skip!());
    let a = user(&e).await;
    // vários pares tarefa x apagar ao mesmo tempo: ou a tarefa é criada (e o apagar recusa) ou o apagar vence (e a tarefa é 404);
    // nunca uma tarefa que falha com "áudio não encontrado no armazenamento"
    for _ in 0..6 {
        let (h, _) = upload(&e, &a, &rand_bytes()).await;
        let (e1, e2, t1, t2, h1, h2) = (e.clone(), e.clone(), a.token.clone(), a.token.clone(), h.clone(), h.clone());
        let job = tokio::spawn(async move {
            let body = serde_json::to_vec(&json!({"kind": "flac", "sample": h1})).unwrap();
            call(&e1, Method::POST, "/api/jobs", Some(&t1), body, &[("content-type", "application/json")]).await
        });
        let del = tokio::spawn(async move { call(&e2, Method::DELETE, &format!("/api/samples/{h2}?force=true"), Some(&t2), vec![], &[]).await });
        let (job, del) = (job.await.unwrap(), del.await.unwrap());
        match (job.status, del.status) {
            // a tarefa já tinha terminado (e falhado pelo formato) quando o apagar chegou: também vale
            (StatusCode::ACCEPTED, StatusCode::CONFLICT | StatusCode::OK) => {
                let j = wait_job(&e, &a, job.json()["id"].as_str().unwrap()).await;
                // o áudio de teste não é um WAV: a falha é do formato, não do armazenamento
                assert!(!j["error"].as_str().unwrap().contains("armazenamento"), "{j}");
            }
            (StatusCode::NOT_FOUND, StatusCode::OK) => {}
            other => panic!("combinação inesperada: {other:?}"),
        }
    }
}

#[tokio::test]
async fn put_do_documento_espera_a_trava_do_hash_e_recusa_audio_que_sumiu() {
    let e = Arc::new(env_or_skip!());
    let a = user(&e).await;
    let (h, _) = upload(&e, &a, &rand_bytes()).await;
    let p = project(&e, &a).await;
    // 1. um apagar em andamento segura o PUT que passa a citar o hash
    let lock = hold_lock(&e, &h).await;
    let (e2, u2, p2, h2) = (e.clone(), clone_user(&a), p.clone(), h.clone());
    let task = tokio::spawn(async move { put_doc(&e2, &u2, &p2, 0, json!({"tracks": [{"audio": [{"sample": h2}]}]})).await });
    tokio::time::sleep(Duration::from_millis(400)).await;
    assert!(!task.is_finished(), "o PUT deveria esperar a trava do hash");
    lock.commit().await.unwrap();
    assert_eq!(task.await.unwrap().status, StatusCode::OK);

    // 2. o apagar terminou antes de o PUT tomar a trava: o áudio sumiu, o PUT recusa em vez de gravar citação solta
    let (h3, _) = upload(&e, &a, &rand_bytes()).await;
    let mut lock = hold_lock(&e, &h3).await;
    let (e3, u3, p3, h4) = (e.clone(), clone_user(&a), p.clone(), h3.clone());
    let task = tokio::spawn(async move { put_doc(&e3, &u3, &p3, 1, json!({"tracks": [{"audio": [{"sample": h4}]}]})).await });
    tokio::time::sleep(Duration::from_millis(400)).await;
    sqlx::query("DELETE FROM samples WHERE owner_id = $1 AND hash = $2").bind(a.id).bind(&h3).execute(&mut *lock).await.unwrap();
    lock.commit().await.unwrap();
    let r = task.await.unwrap();
    assert_eq!(r.status, StatusCode::UNPROCESSABLE_ENTITY, "{}", r.json());
    assert_eq!(r.json()["missing"], json!([h3]));
    // e a versão não andou
    assert_eq!(get(&e, &format!("/api/projects/{p}/doc"), &a).await.json()["version"], 1);
}

#[tokio::test]
async fn job_de_cota_estourada_diz_onde_liberar() {
    let e = env_or_skip!();
    let a = user(&e).await;
    let (h, _) = upload(&e, &a, &sine_wav(440.0, 0.3)).await;
    let fake = storage::hex_sha256(b"enorme-de-cota");
    sqlx::query("INSERT INTO samples (owner_id, hash, size) VALUES ($1, $2, $3)")
        .bind(a.id)
        .bind(&fake)
        .bind(storage::QUOTA_BYTES - 100)
        .execute(&e.state.pool)
        .await
        .unwrap();
    let j = wait_job(&e, &a, new_job(&e, &a, "flac", &h, None).await.json()["id"].as_str().unwrap()).await;
    assert_eq!(j["status"], "failed");
    assert!(j["error"].as_str().unwrap().contains("tela Conta"), "{j}");
}

#[tokio::test]
async fn job_opus_tem_mensagem_propria() {
    let e = env_or_skip!();
    let a = user(&e).await;
    // com um fluxo de 700 bytes multiplexado antes: o OpusHead fica além dos 512 primeiros bytes
    let mut opus = crate::audio::ogg_page(0x02, &[1; 700]);
    opus.extend(crate::audio::ogg_page(0x02, b"OpusHead\x01\x02"));
    let (h, _) = upload(&e, &a, &opus).await;
    let j = wait_job(&e, &a, new_job(&e, &a, "audio_to_midi", &h, None).await.json()["id"].as_str().unwrap()).await;
    assert_eq!(j["status"], "failed");
    assert!(j["error"].as_str().unwrap().contains("Opus"), "{j}");
}

#[tokio::test]
async fn job_trecho_de_arquivo_longo() {
    let e = env_or_skip!();
    let a = user(&e).await;
    // 11 minutos a 8 kHz, com uma senoide de 440 Hz entre 100 s e 101 s: o arquivo passa do teto, o trecho não
    let rate = 8000usize;
    let mut samples = vec![0i16; 660 * rate];
    for (i, x) in samples.iter_mut().enumerate().skip(100 * rate).take(rate) {
        *x = (12_000.0 * (std::f32::consts::TAU * 440.0 * i as f32 / rate as f32).sin()) as i16;
    }
    let (h, _) = upload(&e, &a, &wav16(rate as u32, &samples)).await;
    let inteiro = wait_job(&e, &a, new_job(&e, &a, "audio_to_midi", &h, None).await.json()["id"].as_str().unwrap()).await;
    assert_eq!(inteiro["status"], "failed");
    assert!(inteiro["error"].as_str().unwrap().contains("longo demais"), "{inteiro}");

    let r = new_job(&e, &a, "audio_to_midi", &h, Some(json!({"start": 99.5, "end": 101.5}))).await;
    assert_eq!(r.status, StatusCode::ACCEPTED, "{}", r.json());
    let j = wait_job(&e, &a, r.json()["id"].as_str().unwrap()).await;
    assert_eq!(j["status"], "done", "{j}");
    assert!((j["result"]["duration"].as_f64().unwrap() - 2.0).abs() < 0.01, "{j}");
    let notes = j["result"]["notes"].as_array().unwrap();
    assert!(notes.iter().any(|n| n["pitch"] == 69), "{j}");
    // os tempos continuam em segundos do arquivo inteiro
    let s = notes[0]["start"].as_f64().unwrap();
    assert!((99.9..101.0).contains(&s), "{s}");

    // validações do trecho
    for p in [
        json!({"start": -1}),
        json!({"start": 10, "end": 5}),
        json!({"start": 5, "end": 5}),
        json!({"start": 0, "end": 601}),
        json!({"end": "x"}),
        json!({"start": 1e9}),
    ] {
        assert_eq!(new_job(&e, &a, "audio_to_midi", &h, Some(p)).await.status, StatusCode::BAD_REQUEST);
    }
    // trecho fora do áudio: falha clara
    let j = wait_job(&e, &a, new_job(&e, &a, "audio_to_midi", &h, Some(json!({"start": 700, "end": 701}))).await.json()["id"].as_str().unwrap()).await;
    assert!(j["error"].as_str().unwrap().contains("fora do áudio"), "{j}");
}

#[tokio::test]
async fn put_com_versao_velha_e_audio_sumido_recebe_409_e_nao_422() {
    let e = env_or_skip!();
    let a = user(&e).await;
    let (h, _) = upload(&e, &a, &rand_bytes()).await;
    let p = project(&e, &a).await;
    assert_eq!(put_doc(&e, &a, &p, 0, json!({"tracks": []})).await.status, StatusCode::OK);
    assert_eq!(put_doc(&e, &a, &p, 1, json!({"tracks": [{"n": 2}]})).await.status, StatusCode::OK);
    // base 1 já é velha (o servidor está na 2) e o documento cita um áudio que a conta não tem mais: 409, com o documento vencedor
    assert_eq!(del_force(&e, &h, &a).await.status, StatusCode::OK);
    let r = put_doc(&e, &a, &p, 1, json!({"tracks": [{"audio": [{"sample": h}]}]})).await;
    assert_eq!(r.status, StatusCode::CONFLICT, "{}", r.json());
    assert_eq!(r.json()["version"], 2);
    assert_eq!(r.json()["doc"], json!({"tracks": [{"n": 2}]}));
    // (o 422 só existe na corrida com um apagar, coberta por `put_do_documento_espera_a_trava_do_hash_e_recusa_audio_que_sumiu`;
    // versão velha + apagar no meio dá 409 também, porque a versão é conferida antes)
    assert_eq!(get(&e, &format!("/api/projects/{p}/doc"), &a).await.json()["version"], 2);
}

/// Muitas chamadas que seguram a trava do hash ao mesmo tempo (o pool do teste tem 8 conexões): nenhuma pode pedir uma
/// segunda conexão enquanto segura a primeira, senão todas ficam esperando o pool e o teste estoura o tempo.
#[tokio::test]
async fn muitas_chamadas_simultaneas_com_a_trava_nao_esgotam_o_pool() {
    let e = Arc::new(env_or_skip!());
    let a = Arc::new(user(&e).await);
    const N: usize = 40;
    let mut hashes = Vec::new();
    for _ in 0..N {
        hashes.push(upload(&e, &a, &rand_bytes()).await.0);
    }
    let mut projects = Vec::new();
    for _ in 0..N {
        projects.push(project(&e, &a).await);
    }
    let work = async {
        let mut tasks = Vec::new();
        for i in 0..N {
            let (e2, a2, h, p) = (e.clone(), a.clone(), hashes[i].clone(), projects[i].clone());
            // PUT do documento que cita o áudio (toma a trava e confere)
            tasks.push(tokio::spawn(async move { put_doc(&e2, &a2, &p, 0, json!({"tracks": [{"audio": [{"sample": h}]}]})).await.status }));
            // apagar de outro áudio (remove_if_unused: trava + leitura dos documentos)
            let (e3, a3, h2) = (e.clone(), a.clone(), hashes[(i + 1) % N].clone());
            tasks.push(tokio::spawn(async move { del(&e3, &format!("/api/samples/{h2}?force=true"), &a3).await.status }));
            // envio novo (trava + registro)
            let (e4, a4) = (e.clone(), a.clone());
            tasks.push(tokio::spawn(async move { upload(&e4, &a4, &rand_bytes()).await.1.status }));
        }
        let mut out = Vec::new();
        for t in tasks {
            out.push(t.await.unwrap());
        }
        out
    };
    let out = tokio::time::timeout(Duration::from_secs(60), work).await.expect("chamadas simultâneas travaram (pool esgotado)");
    // o que não pode aparecer é 5xx (timeout de conexão do pool vira 500)
    assert!(out.iter().all(|s| !s.is_server_error()), "{out:?}");
}

// a macro `env_or_skip!` só vale para o que vem depois dela
#[path = "tests_encode.rs"]
mod encode_routes;
