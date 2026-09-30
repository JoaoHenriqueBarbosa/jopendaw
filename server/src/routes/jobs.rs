//! Tarefas pesadas em segundo plano: conversão de áudio para FLAC e áudio para MIDI. A fila é a
//! tabela `jobs`; um worker interno pega os `queued` (`FOR UPDATE SKIP LOCKED`), roda o trabalho
//! em `spawn_blocking` (no máximo `MAX_CONCURRENT` ao mesmo tempo) e grava progresso e resultado.

use std::{
    sync::{
        Arc,
        atomic::{AtomicU32, Ordering},
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
    entities::{
        job,
        prelude::{Job, Sample},
    },
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
    if kind != "audio_to_midi" {
        return Ok(None);
    }
    let mut out = Map::new();
    for (key, lo, hi) in [("min_note_ms", 0.0, 5000.0), ("rms_floor_db", -120.0, 0.0)] {
        if let Some(v) = obj.get(key).filter(|v| !v.is_null()) {
            match v.as_f64() {
                Some(n) if (lo..=hi).contains(&n) => out.insert(key.into(), json!(n)),
                _ => return Err(bad(&format!("{key}: número entre {lo} e {hi}"))),
            };
        }
    }
    Ok(Some(Value::Object(out)))
}

pub async fn create(State(s): State<AppState>, auth: Auth, Json(b): Json<NewJob>) -> Result<(StatusCode, Json<Value>), ApiError> {
    if !matches!(b.kind.as_str(), "flac" | "audio_to_midi") {
        return Err(err(StatusCode::BAD_REQUEST, "kind: flac ou audio_to_midi"));
    }
    if !storage::valid_hash(&b.sample) {
        return Err(err(StatusCode::BAD_REQUEST, "sample: hash SHA-256 inválido"));
    }
    let params = check_params(&b.kind, b.params)?;
    // áudio de outra conta é 404, igual ao que não existe
    Sample::find_by_id((auth.user_id, b.sample.clone())).one(&s.db).await?.ok_or_else(ApiError::not_found)?;

    let (active,): (i64,) =
        sqlx::query_as("SELECT count(*) FROM jobs WHERE owner_id = $1 AND status IN ('queued', 'running')").bind(auth.user_id).fetch_one(&s.pool).await?;
    if active >= MAX_ACTIVE_PER_USER {
        return Err(err(StatusCode::TOO_MANY_REQUESTS, format!("você já tem {MAX_ACTIVE_PER_USER} tarefas em andamento; aguarde alguma terminar")));
    }
    let (id,): (Uuid,) = sqlx::query_as("INSERT INTO jobs (owner_id, kind, sample_hash, params) VALUES ($1, $2, $3, $4) RETURNING id")
        .bind(auth.user_id)
        .bind(&b.kind)
        .bind(&b.sample)
        .bind(params.map(sqlx::types::Json))
        .fetch_one(&s.pool)
        .await?;
    s.job_wake.notify_one();
    Ok((StatusCode::ACCEPTED, Json(json!({"id": id, "status": "queued"}))))
}

pub async fn get(State(s): State<AppState>, auth: Auth, Path(id): Path<Uuid>) -> ApiResult<job::Model> {
    Job::find_by_id(id).filter(job::Column::OwnerId.eq(auth.user_id)).one(&s.db).await?.map(Json).ok_or_else(ApiError::not_found)
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

async fn claim(pool: &PgPool) -> Result<Option<Claimed>, sqlx::Error> {
    sqlx::query_as(
        "UPDATE jobs SET status = 'running', progress = 0, updated_at = now()
         WHERE id = (SELECT id FROM jobs WHERE status = 'queued' ORDER BY created_at FOR UPDATE SKIP LOCKED LIMIT 1)
         RETURNING id, owner_id, kind, sample_hash, params",
    )
    .fetch_optional(pool)
    .await
}

/// O laço do worker, criado uma vez no `setup` (frio). Acorda na hora com um `POST /api/jobs`
/// e, por garantia, a cada 2 s (jobs recolocados na fila, outra instância).
pub async fn worker(s: AppState) {
    let slots = Arc::new(Semaphore::new(MAX_CONCURRENT));
    loop {
        let permit = slots.clone().acquire_owned().await.expect("semáforo aberto");
        match claim(&s.pool).await {
            Ok(Some(job)) => {
                let s = s.clone();
                tokio::spawn(async move {
                    run(&s, job).await;
                    drop(permit);
                });
            }
            Ok(None) => {
                drop(permit);
                tokio::select! {
                    _ = s.job_wake.notified() => {}
                    _ = tokio::time::sleep(Duration::from_secs(2)) => {}
                }
            }
            Err(e) => {
                drop(permit);
                tracing::warn!(error = %e, "worker não conseguiu pegar tarefa");
                tokio::time::sleep(Duration::from_secs(5)).await;
            }
        }
    }
}

enum Output {
    Flac(Vec<u8>),
    Result(Value),
}

/// O trabalho pesado, síncrono: decodificar e processar o áudio já lido do armazenamento. Roda em `spawn_blocking`.
fn compute(kind: &str, bytes: Vec<u8>, params: Option<&Value>, progress: &AtomicU32) -> Result<Output, String> {
    let set = |p: f32| progress.store(p.to_bits(), Ordering::Relaxed);
    let pcm = audio::decode_audio(&bytes)?;
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
            Ok(Output::Result(json!({"notes": notes, "duration": duration})))
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

async fn run(s: &AppState, job: Claimed) {
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
    let mut handle = tokio::task::spawn_blocking(move || compute(&kind, bytes, params.as_ref(), &prog));

    // enquanto a thread trabalha, o progresso dela vai para o banco duas vezes por segundo
    let mut tick = tokio::time::interval(Duration::from_millis(500));
    let joined = loop {
        tokio::select! {
            r = &mut handle => break r,
            _ = tick.tick() => {
                let p = f32::from_bits(progress.load(Ordering::Relaxed));
                let _ = sqlx::query("UPDATE jobs SET progress = $2, updated_at = now() WHERE id = $1").bind(job.id).bind(p).execute(&s.pool).await;
            }
        }
    };
    let outcome = match joined {
        Err(e) => {
            tracing::error!(job = %job.id, error = %e, "a tarefa entrou em pânico");
            Err("erro interno".to_string())
        }
        Ok(Err(msg)) => Err(msg),
        Ok(Ok(Output::Result(v))) => Ok(v),
        Ok(Ok(Output::Flac(bytes))) => save_flac(s, job.owner_id, bytes).await,
    };
    finish(&s.pool, job.id, outcome).await;
}

/// O FLAC gerado entra no armazenamento da conta como qualquer outro áudio (e conta na cota).
async fn save_flac(s: &AppState, owner: Uuid, bytes: Vec<u8>) -> Result<Value, String> {
    let hash = storage::hex_sha256(&bytes);
    let internal = |what: &str, e: &dyn std::fmt::Display| {
        tracing::error!(error = %e, "falha ao {what} o FLAC");
        "erro interno ao gravar o arquivo".to_string()
    };
    // a trava do hash cobre gravar e registrar: apagar o mesmo conteúdo de outra conta não pode cair no meio
    let lock = storage::lock_hash(&s.pool, &hash).await.map_err(|e| internal("travar", &e))?;
    s.store.store_bytes(&hash, &bytes).await.map_err(|e| internal("gravar", &e))?;
    let registered = storage::register(&s.pool, owner, &hash, bytes.len() as i64).await;
    if registered.is_ok() {
        lock.commit().await.map_err(|e| internal("liberar a trava do", &e))?;
    }
    match registered {
        Ok(()) => Ok(json!({"sample": hash, "bytes": bytes.len()})),
        Err(RegisterError::Quota) => Err("cota de armazenamento de 4 GB excedida".into()),
        Err(RegisterError::Db(e)) => {
            tracing::error!(error = %e, "falha ao registrar o FLAC");
            Err("erro interno ao registrar o arquivo".into())
        }
    }
}
