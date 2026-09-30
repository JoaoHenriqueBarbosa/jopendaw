//! Tarefas pesadas em segundo plano: conversão de áudio para FLAC e áudio para MIDI. A fila é a
//! tabela `jobs`; um worker interno pega os `queued` (`FOR UPDATE SKIP LOCKED`), roda o trabalho
//! em `spawn_blocking` (no máximo `MAX_CONCURRENT` ao mesmo tempo) e grava progresso e resultado.

use std::{
    collections::HashMap,
    sync::{
        Arc, LazyLock, Mutex,
        atomic::{AtomicBool, AtomicU32, Ordering},
    },
    time::Duration,
};

use axum::{
    Json,
    extract::{Path, State},
    http::StatusCode,
};
use sea_orm::{ColumnTrait, EntityTrait, QueryFilter, QueryOrder, QuerySelect};
use serde::Deserialize;
use serde_json::{Map, Value, json};
use sqlx::{FromRow, PgPool};
use tokio::sync::Semaphore;
use uuid::Uuid;

use super::{ApiError, ApiResult, err};
use crate::{
    AppState,
    audio::{self, MidiParams},
    auth::Auth,
    encode,
    entities::{job, prelude::Job},
    storage::{self, RegisterError},
};

const MAX_CONCURRENT: usize = 2;
const MAX_ACTIVE_PER_USER: i64 = 10;
const LIST_LIMIT: u64 = 50;

#[derive(Deserialize)]
pub struct NewJob {
    kind: String,
    sample: String,
    params: Option<Value>,
}

/// Confere e normaliza os parâmetros opcionais de cada tipo; o que sobra no banco já é válido.
fn check_params(kind: &str, params: Option<Value>) -> Result<Option<Value>, ApiError> {
    let bad = |m: &str| err(StatusCode::BAD_REQUEST, m);
    let obj = match params {
        None | Some(Value::Null) => return Ok(None),
        Some(Value::Object(o)) => o,
        Some(_) => return Err(bad("params precisa ser um objeto")),
    };
    if kind == "encode_audio" {
        return check_encode_params(&obj).map(Some);
    }
    if kind != "audio_to_midi" {
        return Ok(None);
    }
    let mut out = Map::new();
    // o piso de nível entra em `(db - piso) / (-6 - piso)`: com piso >= -6 dB o divisor some, então o teto é -10
    for (key, lo, hi) in [("min_note_ms", 0.0, 5000.0), ("rms_floor_db", -120.0, -10.0)] {
        if let Some(v) = obj.get(key).filter(|v| !v.is_null()) {
            match v.as_f64() {
                Some(n) if (lo..=hi).contains(&n) => out.insert(key.into(), json!(n)),
                _ => return Err(bad(&format!("{key}: número entre {lo} e {hi}"))),
            };
        }
    }
    // trecho do arquivo a analisar, em segundos; o teto de duração vale pelo trecho
    let seconds = |key: &str| -> Result<Option<f64>, ApiError> {
        match obj.get(key).filter(|v| !v.is_null()) {
            None => Ok(None),
            Some(v) => match v.as_f64() {
                Some(n) if n.is_finite() && (0.0..=1e7).contains(&n) => Ok(Some(n)),
                _ => Err(bad(&format!("{key}: segundos, número de 0 em diante"))),
            },
        }
    };
    let (start, end) = (seconds("start")?, seconds("end")?);
    // sem `end` o trecho vai até o fim do arquivo, e o servidor não sabe a duração aqui: com `start` isso só falharia
    // na decodificação (tarefa `failed`); melhor recusar já
    if start.is_some_and(|s| s > 0.0) && end.is_none() {
        return Err(bad("end: obrigatório quando há start (o trecho tem no máximo 10 minutos)"));
    }
    if let Some(e) = end {
        if e <= start.unwrap_or(0.0) {
            return Err(bad("end: precisa ser maior que start"));
        }
        if e - start.unwrap_or(0.0) > audio::MAX_SECONDS {
            return Err(bad(&format!("trecho longo demais: o máximo é {} minutos", (audio::MAX_SECONDS / 60.0) as u32)));
        }
    }
    for (key, v) in [("start", start), ("end", end)] {
        if let Some(n) = v {
            out.insert(key.into(), json!(n));
        }
    }
    Ok(Some(Value::Object(out)))
}

/// Parâmetros de `encode_audio`: `format` (`flac` | `mp3`, obrigatório); FLAC: `bits` (16, 24 ou 32; 32 vira 24 com
/// aviso) e `level` (0 a 8); MP3: `bitrate` (CBR 128, 192, 256 ou 320) ou `vbr` (V0 a V4), nunca os dois;
/// `title`, `artist` e `album` (texto de até 200 caracteres, limpo de caracteres de controle).
fn check_encode_params(obj: &Map<String, Value>) -> Result<Value, ApiError> {
    let bad = |m: String| err(StatusCode::BAD_REQUEST, m);
    let known = ["format", "bits", "level", "bitrate", "vbr", "title", "artist", "album"];
    if let Some(k) = obj.keys().find(|k| !known.contains(&k.as_str())) {
        return Err(bad(format!("{k}: parâmetro desconhecido")));
    }
    let format = obj.get("format").and_then(Value::as_str).unwrap_or_default();
    if !matches!(format, "flac" | "mp3") {
        return Err(bad("format: flac ou mp3".into()));
    }
    let int = |key: &str| -> Result<Option<u64>, ApiError> {
        match obj.get(key).filter(|v| !v.is_null()) {
            None => Ok(None),
            Some(v) => v.as_u64().map(Some).ok_or_else(|| bad(format!("{key}: número inteiro"))),
        }
    };
    let mut out = Map::new();
    out.insert("format".into(), json!(format));
    let (bits, level, bitrate, vbr) = (int("bits")?, int("level")?, int("bitrate")?, int("vbr")?);
    if format == "flac" {
        if bitrate.is_some() || vbr.is_some() {
            return Err(bad("bitrate e vbr valem só para MP3".into()));
        }
        if let Some(b) = bits {
            if !matches!(b, 16 | 24 | 32) {
                return Err(bad("bits: 16, 24 ou 32".into()));
            }
            out.insert("bits".into(), json!(b));
        }
        if let Some(l) = level {
            if l > 8 {
                return Err(bad("level: nível de compressão de 0 a 8".into()));
            }
            out.insert("level".into(), json!(l));
        }
    } else {
        if bits.is_some() || level.is_some() {
            return Err(bad("bits e level valem só para FLAC".into()));
        }
        match (bitrate, vbr) {
            (Some(_), Some(_)) => return Err(bad("informe bitrate (CBR) ou vbr, não os dois".into())),
            (Some(b), None) => {
                if !encode::CBR_RATES.contains(&b) {
                    return Err(bad("bitrate: 128, 192, 256 ou 320 (kbps)".into()));
                }
                out.insert("bitrate".into(), json!(b));
            }
            (None, Some(q)) => {
                if q > encode::VBR_MAX {
                    return Err(bad(format!("vbr: de 0 (melhor) a {}", encode::VBR_MAX)));
                }
                out.insert("vbr".into(), json!(q));
            }
            (None, None) => {}
        }
    }
    for key in ["title", "artist", "album"] {
        match obj.get(key).filter(|v| !v.is_null()) {
            None => {}
            Some(Value::String(t)) => {
                // o que vai para o banco já está limpo; passar do limite (antes ou depois da limpeza) recusa
                let too_long = || bad(format!("{key}: no máximo {} caracteres", encode::META_MAX_CHARS));
                if t.chars().count() > encode::META_MAX_CHARS * 4 {
                    return Err(too_long());
                }
                if let Some(clean) = encode::clean_text(t) {
                    if clean.chars().count() > encode::META_MAX_CHARS {
                        return Err(too_long());
                    }
                    out.insert(key.into(), json!(clean));
                }
            }
            Some(_) => return Err(bad(format!("{key}: texto"))),
        }
    }
    Ok(Value::Object(out))
}

pub async fn create(State(s): State<AppState>, auth: Auth, Json(b): Json<NewJob>) -> Result<(StatusCode, Json<Value>), ApiError> {
    if !matches!(b.kind.as_str(), "flac" | "audio_to_midi" | "encode_audio") {
        return Err(err(StatusCode::BAD_REQUEST, "kind: flac, audio_to_midi ou encode_audio"));
    }
    if b.kind == "encode_audio" && b.params.as_ref().is_none_or(Value::is_null) {
        return Err(err(StatusCode::BAD_REQUEST, "params: informe o formato (format: flac ou mp3)"));
    }
    if !storage::valid_hash(&b.sample) {
        return Err(err(StatusCode::BAD_REQUEST, "sample: hash SHA-256 inválido"));
    }
    let params = check_params(&b.kind, b.params)?;
    let (active,): (i64,) =
        sqlx::query_as("SELECT count(*) FROM jobs WHERE owner_id = $1 AND status IN ('queued', 'running')").bind(auth.user_id).fetch_one(&s.pool).await?;
    if active >= MAX_ACTIVE_PER_USER {
        return Err(err(StatusCode::TOO_MANY_REQUESTS, format!("você já tem {MAX_ACTIVE_PER_USER} tarefas em andamento; aguarde alguma terminar")));
    }
    // sob a trava do hash: conferir que o áudio existe e criar a tarefa não pode se cruzar com um apagar do
    // mesmo áudio, que senão o tiraria do armazenamento entre um passo e outro
    let mut lock = storage::lock_hash(&s.pool, &b.sample).await?;
    // áudio de outra conta é 404, igual ao que não existe
    let owned: Option<(i64,)> =
        sqlx::query_as("SELECT size FROM samples WHERE owner_id = $1 AND hash = $2").bind(auth.user_id).bind(&b.sample).fetch_optional(&mut *lock).await?;
    owned.ok_or_else(ApiError::not_found)?;
    let (id,): (Uuid,) = sqlx::query_as("INSERT INTO jobs (owner_id, kind, sample_hash, params) VALUES ($1, $2, $3, $4) RETURNING id")
        .bind(auth.user_id)
        .bind(&b.kind)
        .bind(&b.sample)
        .bind(params.map(sqlx::types::Json))
        .fetch_one(&mut *lock)
        .await?;
    lock.commit().await?;
    s.job_wake.notify_one();
    Ok((StatusCode::ACCEPTED, Json(json!({"id": id, "status": "queued"}))))
}

pub async fn get(State(s): State<AppState>, auth: Auth, Path(id): Path<Uuid>) -> ApiResult<job::Model> {
    Job::find_by_id(id).filter(job::Column::OwnerId.eq(auth.user_id)).one(&s.db).await?.map(Json).ok_or_else(ApiError::not_found)
}

/// Tarefas que este processo está rodando, com a bandeira de cancelamento de cada uma (cooperativa: o trabalho a
/// olha entre uma etapa e outra e o resultado de uma tarefa cancelada nunca é gravado).
static RUNNING: LazyLock<Mutex<HashMap<Uuid, Arc<AtomicBool>>>> = LazyLock::new(Mutex::default);

/// Tira uma tarefa do histórico da conta (a espera do app foi cancelada, ou ele já baixou o resultado). Uma tarefa
/// rodando neste processo é cancelada: a bandeira dela sobe, a linha some na hora (o áudio deixa de estar "em uso") e
/// o resultado, quando o trabalho parar, é jogado fora. Rodando em outra instância, não dá para interromper: 409.
pub async fn delete(State(s): State<AppState>, auth: Auth, Path(id): Path<Uuid>) -> Result<StatusCode, ApiError> {
    let r = sqlx::query("DELETE FROM jobs WHERE id = $1 AND owner_id = $2 AND status <> 'running'").bind(id).bind(auth.user_id).execute(&s.pool).await?;
    if r.rows_affected() > 0 {
        return Ok(StatusCode::NO_CONTENT);
    }
    let exists: Option<(i32,)> =
        sqlx::query_as("SELECT 1 FROM jobs WHERE id = $1 AND owner_id = $2").bind(id).bind(auth.user_id).fetch_optional(&s.pool).await?;
    if exists.is_none() {
        return Err(ApiError::not_found());
    }
    let flag = RUNNING.lock().unwrap_or_else(|e| e.into_inner()).get(&id).cloned();
    match flag {
        Some(flag) => {
            flag.store(true, Ordering::Relaxed);
            sqlx::query("DELETE FROM jobs WHERE id = $1 AND owner_id = $2").bind(id).bind(auth.user_id).execute(&s.pool).await?;
            Ok(StatusCode::NO_CONTENT)
        }
        None => Err(err(StatusCode::CONFLICT, "a tarefa está em andamento e não pode ser cancelada agora")),
    }
}

pub async fn list(State(s): State<AppState>, auth: Auth) -> ApiResult<Vec<job::Model>> {
    let rows = Job::find().filter(job::Column::OwnerId.eq(auth.user_id)).order_by_desc(job::Column::CreatedAt).limit(LIST_LIMIT).all(&s.db).await?;
    Ok(Json(rows))
}

// ---------------------------------------------------------------- worker

/// No boot: o que estava `running` quando o processo caiu volta para a fila.
pub async fn requeue_orphans(pool: &PgPool) -> anyhow::Result<()> {
    requeue(pool, None).await
}

/// `owner` restringe a uma conta (os testes dividem o banco e não podem mexer nas tarefas alheias).
pub async fn requeue(pool: &PgPool, owner: Option<Uuid>) -> anyhow::Result<()> {
    let r = sqlx::query("UPDATE jobs SET status = 'queued', progress = 0, updated_at = now() WHERE status = 'running' AND ($1::uuid IS NULL OR owner_id = $1)")
        .bind(owner)
        .execute(pool)
        .await?;
    if r.rows_affected() > 0 {
        tracing::info!(n = r.rows_affected(), "tarefas órfãs voltaram para a fila");
    }
    Ok(())
}

#[derive(FromRow)]
struct Claimed {
    id: Uuid,
    owner_id: Uuid,
    kind: String,
    sample_hash: String,
    params: Option<sqlx::types::Json<Value>>,
}

/// Pega a tarefa mais antiga da fila. Sem `allow_encode` (a vez das exportações está ocupada), pula as `encode_audio`:
/// elas esperam `queued`, sem `running` falso, e não seguram uma das vagas de quem pode andar.
async fn claim(pool: &PgPool, allow_encode: bool) -> Result<Option<Claimed>, sqlx::Error> {
    sqlx::query_as(
        "UPDATE jobs SET status = 'running', progress = 0, updated_at = now()
         WHERE id = (SELECT id FROM jobs WHERE status = 'queued' AND ($1 OR kind <> 'encode_audio') ORDER BY created_at FOR UPDATE SKIP LOCKED LIMIT 1)
         RETURNING id, owner_id, kind, sample_hash, params",
    )
    .bind(allow_encode)
    .fetch_optional(pool)
    .await
}

/// A vez das exportações compactadas: uma por vez no processo. O WAV decodificado (até 30 min) ocupa centenas de MB, e
/// duas juntas (mais a cópia do arquivo lido) passariam do que uma instância pequena aguenta. Tomada ANTES de a
/// tarefa virar `running`, então uma segunda exportação espera na fila, e sobra vaga para `audio_to_midi`.
static ENCODE_TURN: tokio::sync::Semaphore = tokio::sync::Semaphore::const_new(1);

/// O laço do worker, criado uma vez no `setup` (frio). Acorda na hora com um `POST /api/jobs`
/// e, por garantia, a cada 2 s (jobs recolocados na fila, outra instância).
pub async fn worker(s: AppState) {
    let slots = Arc::new(Semaphore::new(MAX_CONCURRENT));
    loop {
        let permit = slots.clone().acquire_owned().await.expect("semáforo aberto");
        let turn = ENCODE_TURN.try_acquire().ok();
        match claim(&s.pool, turn.is_some()).await {
            Ok(Some(job)) => {
                let s = s.clone();
                // a vez só fica com quem é exportação; as outras a devolvem já
                let turn = turn.filter(|_| job.kind == "encode_audio");
                let cancel = Arc::new(AtomicBool::new(false));
                RUNNING.lock().unwrap_or_else(|e| e.into_inner()).insert(job.id, cancel.clone());
                tokio::spawn(async move {
                    let id = job.id;
                    run(&s, job, cancel).await;
                    RUNNING.lock().unwrap_or_else(|e| e.into_inner()).remove(&id);
                    drop(turn);
                    drop(permit);
                    // quem esperava a vez (ou a vaga) não precisa esperar o relógio
                    s.job_wake.notify_one();
                });
            }
            Ok(None) => {
                drop(turn);
                drop(permit);
                tokio::select! {
                    _ = s.job_wake.notified() => {}
                    _ = tokio::time::sleep(Duration::from_secs(2)) => {}
                }
            }
            Err(e) => {
                drop(turn);
                drop(permit);
                tracing::warn!(error = %e, "worker não conseguiu pegar tarefa");
                tokio::time::sleep(Duration::from_secs(5)).await;
            }
        }
    }
}

enum Output {
    Flac(Vec<u8>),
    /// Arquivo gerado pela exportação compactada e os campos do resultado (nome, MIME, avisos).
    Encoded(Vec<u8>, Value),
    Result(Value),
}

fn compute_encode(bytes: Vec<u8>, params: Option<&Value>, progress: &AtomicU32, cancel: &AtomicBool) -> Result<Output, String> {
    let set = |p: f32| progress.store(p.to_bits(), Ordering::Relaxed);
    let params = params.ok_or("parâmetros ausentes")?;
    let format = encode::Format::from_params(params);
    let meta = encode::Meta::from_params(Some(params));
    let wav = audio::decode_wav_for_encode(&bytes)?;
    drop(bytes);
    set(0.05);
    let duration = wav.pcm.data.len() as f64 / wav.pcm.channels as f64 / wav.pcm.rate as f64;
    let done = encode::encode_cancelable(&wav, format, &meta, &|f| set(0.05 + 0.95 * f), &|| cancel.load(Ordering::Relaxed))?;
    let info = json!({
        "format": format.extension(),
        "mime": format.mime(),
        "filename": encode::suggested_name(&meta, format.extension()),
        "duration": duration,
        "rate": wav.pcm.rate,
        "channels": wav.pcm.channels,
        "warnings": done.warnings,
    });
    Ok(Output::Encoded(done.bytes, info))
}

/// O trabalho pesado, síncrono: decodificar e processar o áudio já lido do armazenamento. Roda em `spawn_blocking`.
fn compute(kind: &str, bytes: Vec<u8>, params: Option<&Value>, progress: &AtomicU32, cancel: &AtomicBool) -> Result<Output, String> {
    if kind == "encode_audio" {
        return compute_encode(bytes, params, progress, cancel);
    }
    let set = |p: f32| progress.store(p.to_bits(), Ordering::Relaxed);
    let span = audio::Span {
        start: params.and_then(|p| p.get("start")).and_then(Value::as_f64).unwrap_or(0.0),
        end: params.and_then(|p| p.get("end")).and_then(Value::as_f64),
    };
    let pcm = audio::decode_audio_span(&bytes, span)?;
    drop(bytes);
    set(0.1);
    match kind {
        "flac" => {
            let flac = audio::encode_flac(&pcm)?;
            Ok(Output::Flac(flac))
        }
        _ => {
            let mut p = MidiParams::default();
            if let Some(v) = params.and_then(|p| p.get("min_note_ms")).and_then(Value::as_f64) {
                p.min_note_ms = v as f32;
            }
            if let Some(v) = params.and_then(|p| p.get("rms_floor_db")).and_then(Value::as_f64) {
                p.rms_floor_db = v as f32;
            }
            let mono = pcm.to_mono();
            let duration = mono.len() as f64 / pcm.rate as f64;
            let notes = audio::audio_to_midi(&mono, pcm.rate, p, &|f| set(0.1 + 0.9 * f));
            // os tempos das notas continuam em segundos do arquivo inteiro, mesmo com só um trecho analisado
            let notes: Vec<audio::Note> = notes.into_iter().map(|n| audio::Note { start: n.start + span.start, ..n }).collect();
            Ok(Output::Result(json!({"notes": notes, "duration": duration, "start": span.start})))
        }
    }
}

async fn finish(pool: &PgPool, id: Uuid, outcome: Result<Value, String>) {
    let (status, error, result) = match outcome {
        Ok(v) => ("done", None, Some(v)),
        Err(e) => ("failed", Some(e), None),
    };
    let r = sqlx::query(
        "UPDATE jobs SET status = $2, progress = CASE WHEN $2 = 'done' THEN 1 ELSE progress END, error = $3, result = $4, updated_at = now() WHERE id = $1",
    )
    .bind(id)
    .bind(status)
    .bind(error)
    .bind(result.map(sqlx::types::Json))
    .execute(pool)
    .await;
    if let Err(e) = r {
        tracing::error!(job = %id, error = %e, "não consegui gravar o fim da tarefa");
    }
}

async fn run(s: &AppState, job: Claimed, cancel: Arc<AtomicBool>) {
    let progress = Arc::new(AtomicU32::new(0f32.to_bits()));
    // o áudio vem do armazenamento (disco ou S3) antes da thread de cálculo, que é síncrona
    let bytes = match s.store.read(&job.sample_hash).await {
        Ok(Some(b)) => b,
        other => {
            if let Err(e) = other {
                tracing::error!(job = %job.id, error = %e, "falha ao ler o áudio do armazenamento");
            }
            return finish(&s.pool, job.id, Err("áudio não encontrado no armazenamento".into())).await;
        }
    };
    let (kind, params, prog) = (job.kind.clone(), job.params.map(|p| p.0), progress.clone());
    let flag = cancel.clone();
    let mut handle = tokio::task::spawn_blocking(move || compute(&kind, bytes, params.as_ref(), &prog, &flag));

    // enquanto a thread trabalha, o progresso dela vai para o banco duas vezes por segundo
    let mut tick = tokio::time::interval(Duration::from_millis(500));
    let joined = loop {
        tokio::select! {
            r = &mut handle => break r,
            _ = tick.tick() => {
                if cancel.load(Ordering::Relaxed) {
                    continue;
                }
                let p = f32::from_bits(progress.load(Ordering::Relaxed));
                let _ = sqlx::query("UPDATE jobs SET progress = $2, updated_at = now() WHERE id = $1").bind(job.id).bind(p).execute(&s.pool).await;
            }
        }
    };
    // cancelada (a linha já foi apagada): o resultado, se houve, é jogado fora
    if cancel.load(Ordering::Relaxed) {
        return;
    }
    let outcome = match joined {
        Err(e) => {
            tracing::error!(job = %job.id, error = %e, "a tarefa entrou em pânico");
            Err("erro interno".to_string())
        }
        Ok(Err(msg)) => Err(msg),
        Ok(Ok(Output::Result(v))) => Ok(v),
        Ok(Ok(Output::Flac(bytes))) => save_output(s, job.owner_id, bytes, json!({})).await,
        Ok(Ok(Output::Encoded(bytes, info))) => save_output(s, job.owner_id, bytes, info).await,
    };
    finish(&s.pool, job.id, outcome).await;
}

/// O arquivo gerado (FLAC ou MP3) entra no armazenamento da conta como qualquer outro áudio (e conta na cota). O
/// resultado da tarefa leva o hash em `sample`, o tamanho em `bytes` e o que mais `info` trouxer.
async fn save_output(s: &AppState, owner: Uuid, bytes: Vec<u8>, info: Value) -> Result<Value, String> {
    let hash = storage::hex_sha256(&bytes);
    let internal = |what: &str, e: &dyn std::fmt::Display| {
        tracing::error!(error = %e, "falha ao {what} o arquivo gerado");
        "erro interno ao gravar o arquivo".to_string()
    };
    // a trava do hash cobre gravar e registrar: apagar o mesmo conteúdo de outra conta não pode cair no meio
    let mut lock = storage::lock_hash(&s.pool, &hash).await.map_err(|e| internal("travar", &e))?;
    s.store.store_bytes(&hash, &bytes).await.map_err(|e| internal("gravar", &e))?;
    let registered = storage::register(&mut lock, owner, &hash, bytes.len() as i64).await;
    if registered.is_ok() {
        lock.commit().await.map_err(|e| internal("liberar a trava do", &e))?;
    }
    match registered {
        Ok(()) => {
            let mut out = json!({"sample": hash, "bytes": bytes.len()});
            if let (Some(o), Value::Object(extra)) = (out.as_object_mut(), info) {
                o.extend(extra);
            }
            Ok(out)
        }
        Err(RegisterError::Quota) => Err(storage::QUOTA_MESSAGE.into()),
        Err(RegisterError::Db(e)) => {
            tracing::error!(error = %e, "falha ao registrar o arquivo gerado");
            Err("erro interno ao registrar o arquivo".into())
        }
    }
}
