//! Áudios da conta, endereçados pelo SHA-256 do conteúdo. O app pergunta quais faltam, manda só
//! esses e depois lê de volta por hash. Os bytes ficam no armazenamento (`storage.rs`: disco ou S3), o registro e a
//! cota no banco.

use axum::{
    Json,
    body::Body,
    extract::{Path, State},
    http::{HeaderMap, HeaderValue, StatusCode, header},
    response::{IntoResponse, Response},
};
use chrono::{DateTime, Utc};
use futures_util::StreamExt;
use sea_orm::{ColumnTrait, EntityTrait, QueryFilter};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use sqlx::PgPool;
use std::collections::{BTreeMap, HashMap, HashSet};
use tokio::io::AsyncWriteExt;
use uuid::Uuid;

use super::{ApiError, ApiResult, err};
use crate::{
    AppState,
    auth::Auth,
    entities::{prelude::Sample, sample},
    storage::{self, MAX_SAMPLE_BYTES, QUOTA_BYTES, RegisterError, TmpGuard},
};

const MISSING_MAX: usize = 2000;

#[derive(Deserialize)]
pub struct MissingReq {
    hashes: Vec<String>,
}

#[derive(Serialize)]
pub struct MissingRes {
    missing: Vec<String>,
}

pub async fn missing(State(s): State<AppState>, auth: Auth, Json(b): Json<MissingReq>) -> ApiResult<MissingRes> {
    if b.hashes.len() > MISSING_MAX {
        return Err(err(StatusCode::BAD_REQUEST, format!("no máximo {MISSING_MAX} hashes por pedido")));
    }
    if !b.hashes.iter().all(|h| storage::valid_hash(h)) {
        return Err(err(StatusCode::BAD_REQUEST, "hash inválido: SHA-256 em hexadecimal minúsculo, 64 caracteres"));
    }
    let have: std::collections::HashSet<String> = Sample::find()
        .filter(sample::Column::OwnerId.eq(auth.user_id))
        .filter(sample::Column::Hash.is_in(b.hashes.iter().cloned()))
        .all(&s.db)
        .await?
        .into_iter()
        .map(|m| m.hash)
        .collect();
    // na ordem em que vieram, sem repetir
    let mut seen = std::collections::HashSet::new();
    let missing = b.hashes.into_iter().filter(|h| !have.contains(h) && seen.insert(h.clone())).collect();
    Ok(Json(MissingRes { missing }))
}

fn quota_error() -> ApiError {
    err(StatusCode::PAYLOAD_TOO_LARGE, "cota de armazenamento de 4 GB excedida; apague áudios sem uso na tela Conta")
}

pub async fn upload(State(s): State<AppState>, auth: Auth, Path(hash): Path<String>, headers: HeaderMap, body: Body) -> Result<StatusCode, ApiError> {
    if !storage::valid_hash(&hash) {
        return Err(err(StatusCode::BAD_REQUEST, "hash inválido: SHA-256 em hexadecimal minúsculo, 64 caracteres"));
    }
    // idempotente: já está na conta, nada a regravar (nem a ler do cliente)
    if Sample::find_by_id((auth.user_id, hash.clone())).one(&s.db).await?.is_some() {
        return Ok(StatusCode::NO_CONTENT);
    }
    let declared = headers.get(header::CONTENT_LENGTH).and_then(|v| v.to_str().ok()).and_then(|v| v.parse::<u64>().ok());
    if declared.is_some_and(|n| n > MAX_SAMPLE_BYTES) {
        return Err(too_big());
    }
    let used = storage::used_bytes(&s.pool, auth.user_id).await?;
    if declared.is_some_and(|n| used.saturating_add(n as i64) > QUOTA_BYTES) {
        return Err(quota_error());
    }

    // em streaming: cada pedaço vai para um temporário local e para o hash, sem segurar o arquivo na RAM. Os
    // tetos valem pelo que realmente chega, não pelo Content-Length, que o cliente pode mentir.
    let tmp = s.store.new_tmp().await.map_err(ApiError::internal)?;
    let mut guard = TmpGuard::new(&tmp);
    let mut file = tokio::fs::File::create(&tmp).await.map_err(ApiError::internal)?;
    let mut hasher = Sha256::new();
    let mut size: u64 = 0;
    let mut stream = body.into_data_stream();
    while let Some(chunk) = stream.next().await {
        let chunk = chunk.map_err(|e| err(StatusCode::BAD_REQUEST, format!("envio interrompido: {e}")))?;
        size += chunk.len() as u64;
        if size > MAX_SAMPLE_BYTES {
            return Err(too_big());
        }
        if used.saturating_add(size as i64) > QUOTA_BYTES {
            return Err(quota_error());
        }
        hasher.update(&chunk);
        file.write_all(&chunk).await.map_err(ApiError::internal)?;
    }
    file.flush().await.map_err(ApiError::internal)?;
    drop(file);
    if size == 0 {
        return Err(err(StatusCode::BAD_REQUEST, "corpo vazio"));
    }
    // mesmo que o arquivo já exista no armazenamento (de outra conta), o conteúdo mandado é conferido: senão
    // bastaria saber um hash para "ter" o áudio de outra pessoa
    if storage::hex(&hasher.finalize()) != hash {
        return Err(err(StatusCode::BAD_REQUEST, "o SHA-256 do corpo não confere com o hash da URL"));
    }
    // gravar e registrar sob a trava do hash: um DELETE de outra conta com o mesmo conteúdo não pode
    // apagar o blob entre um passo e outro
    let lock = storage::lock_hash(&s.pool, &hash).await?;
    // no S3 isto faz o HEAD (já existe: pula) e o PUT; em disco, o rename. Consome o temporário
    s.store.commit_tmp(&tmp, &hash).await.map_err(ApiError::internal)?;
    guard.keep();
    match storage::register(&s.pool, auth.user_id, &hash, size as i64).await {
        Ok(()) => {
            lock.commit().await?;
            Ok(StatusCode::NO_CONTENT)
        }
        Err(RegisterError::Quota) => Err(quota_error()),
        Err(RegisterError::Db(e)) => Err(e.into()),
    }
}

fn too_big() -> ApiError {
    err(StatusCode::PAYLOAD_TOO_LARGE, "arquivo grande demais (máximo de 512 MB)")
}

pub async fn download(State(s): State<AppState>, auth: Auth, Path(hash): Path<String>) -> Result<Response, ApiError> {
    if !storage::valid_hash(&hash) {
        return Err(ApiError::not_found());
    }
    let rec = Sample::find_by_id((auth.user_id, hash.clone())).one(&s.db).await?.ok_or_else(ApiError::not_found)?;
    let blob = s.store.open(&hash).await.map_err(ApiError::internal)?.ok_or_else(|| {
        tracing::error!(hash = %hash, "registro sem arquivo no armazenamento");
        ApiError::not_found()
    })?;
    let mut res = Response::new(blob.body);
    let h = res.headers_mut();
    h.insert(header::CONTENT_TYPE, HeaderValue::from_static("application/octet-stream"));
    h.insert(header::CONTENT_LENGTH, HeaderValue::from(blob.len.unwrap_or(rec.size as u64)));
    // o endereço é o hash do conteúdo: nunca muda, então o navegador pode guardar para sempre (e
    // `private` impede cache compartilhado, já que só o dono lê)
    h.insert(header::CACHE_CONTROL, HeaderValue::from_static("private, max-age=31536000, immutable"));
    Ok(res)
}

// ---------------------------------------------------------------- listar e apagar

/// Áudios enviados há menos que isto não entram na limpeza em massa: o app sobe o áudio antes de o
/// documento que o cita chegar ao servidor, e nesse intervalo ele parece "sem uso".
const CLEANUP_GRACE_SECS: i64 = 3600;

/// Quem cita cada áudio da conta, lido dos documentos dos projetos dela.
#[derive(Default)]
struct Refs {
    /// hash → (projeto → nome)
    projects: HashMap<String, BTreeMap<Uuid, String>>,
    /// hash → nome de arquivo, como o mapa `samples` do documento o chama
    names: HashMap<String, String>,
}

/// Todo texto do documento que tem cara de hash conta como citação (o `samples` do documento, o `sample`
/// de clipes e faixas de sampler, as zonas e o que vier depois): mais conservador que conhecer cada
/// campo, e por isso nunca libera um áudio que um campo novo ainda cita.
fn collect_hashes(v: &Value, out: &mut HashSet<String>) {
    match v {
        Value::String(s) if storage::valid_hash(s) => {
            out.insert(s.clone());
        }
        Value::Array(a) => a.iter().for_each(|x| collect_hashes(x, out)),
        Value::Object(o) => {
            for (k, x) in o {
                if storage::valid_hash(k) {
                    out.insert(k.clone());
                }
                collect_hashes(x, out);
            }
        }
        _ => {}
    }
}

async fn references(pool: &PgPool, owner: Uuid) -> Result<Refs, sqlx::Error> {
    let mut refs = Refs::default();
    // um documento por vez: eles chegam a 8 MB, e só o conjunto de hashes fica na memória
    let mut rows = sqlx::query_as::<_, (Uuid, String, Option<sqlx::types::Json<Value>>)>(
        "SELECT p.id, p.name, d.doc FROM projects p JOIN project_docs d ON d.project_id = p.id WHERE p.owner_id = $1",
    )
    .bind(owner)
    .fetch(pool);
    while let Some(row) = rows.next().await {
        let (id, name, doc) = row?;
        let Some(doc) = doc else { continue };
        let mut hashes = HashSet::new();
        collect_hashes(&doc.0, &mut hashes);
        for h in hashes {
            refs.projects.entry(h).or_default().insert(id, name.clone());
        }
        if let Some(map) = doc.0.get("samples").and_then(Value::as_object) {
            for (h, info) in map {
                if let Some(n) = info.get("name").and_then(Value::as_str) {
                    refs.names.entry(h.clone()).or_insert_with(|| n.to_string());
                }
            }
        }
    }
    Ok(refs)
}

fn projects_json(p: Option<&BTreeMap<Uuid, String>>) -> Vec<Value> {
    p.map(|m| m.iter().map(|(id, name)| json!({"id": id, "name": name})).collect()).unwrap_or_default()
}

/// A conta de áudios: cota, uso, e cada áudio com o tamanho e os projetos que o citam (`unused` quando
/// nenhum cita).
pub async fn list(State(s): State<AppState>, auth: Auth) -> ApiResult<Value> {
    let rows: Vec<(String, i64, DateTime<Utc>)> =
        sqlx::query_as("SELECT hash, size, created_at FROM samples WHERE owner_id = $1 ORDER BY size DESC, hash").bind(auth.user_id).fetch_all(&s.pool).await?;
    let refs = references(&s.pool, auth.user_id).await?;
    let (mut used, mut unused_bytes, mut unused) = (0i64, 0i64, 0u32);
    let samples: Vec<Value> = rows
        .into_iter()
        .map(|(hash, size, created_at)| {
            let projects = projects_json(refs.projects.get(&hash));
            used += size;
            if projects.is_empty() {
                unused_bytes += size;
                unused += 1;
            }
            json!({"hash": hash, "name": refs.names.get(&hash), "size": size, "created_at": created_at, "unused": projects.is_empty(), "project_count": projects.len(), "projects": projects})
        })
        .collect();
    Ok(Json(json!({"quota_bytes": QUOTA_BYTES, "used_bytes": used, "unused_bytes": unused_bytes, "unused_count": unused, "samples": samples})))
}

/// Tira o áudio da conta e, se nenhuma outra conta o tem, os bytes do armazenamento. Devolve os bytes
/// liberados na cota (`None` se já não estava registrado). Quem chama já conferiu que ninguém o usa.
async fn remove(s: &AppState, owner: Uuid, hash: &str) -> Result<Option<i64>, ApiError> {
    let mut lock = storage::lock_hash(&s.pool, hash).await?;
    let gone: Option<(i64,)> =
        sqlx::query_as("DELETE FROM samples WHERE owner_id = $1 AND hash = $2 RETURNING size").bind(owner).bind(hash).fetch_optional(&mut *lock).await?;
    let Some((size,)) = gone else { return Ok(None) };
    // o mesmo conteúdo pode ser de outra conta: os bytes só saem quando ninguém mais os registra
    let (shared,): (bool,) = sqlx::query_as("SELECT EXISTS (SELECT 1 FROM samples WHERE hash = $1)").bind(hash).fetch_one(&mut *lock).await?;
    if !shared {
        // falhou: a transação volta e o registro fica, coerente com o arquivo que ainda existe
        s.store.delete(hash).await.map_err(ApiError::internal)?;
    }
    lock.commit().await?;
    Ok(Some(size))
}

async fn has_active_job(pool: &PgPool, owner: Uuid, hash: &str) -> Result<bool, sqlx::Error> {
    let (n,): (bool,) = sqlx::query_as("SELECT EXISTS (SELECT 1 FROM jobs WHERE owner_id = $1 AND sample_hash = $2 AND status IN ('queued', 'running'))")
        .bind(owner)
        .bind(hash)
        .fetch_one(pool)
        .await?;
    Ok(n)
}

/// Apaga um áudio da conta, só se nenhum documento dela o cita; do contrário 409 com a lista dos projetos.
pub async fn delete(State(s): State<AppState>, auth: Auth, Path(hash): Path<String>) -> Result<Response, ApiError> {
    if !storage::valid_hash(&hash) {
        return Err(ApiError::not_found());
    }
    Sample::find_by_id((auth.user_id, hash.clone())).one(&s.db).await?.ok_or_else(ApiError::not_found)?;
    let refs = references(&s.pool, auth.user_id).await?;
    if let Some(p) = refs.projects.get(&hash) {
        let body = json!({"error": "este áudio ainda é usado em projetos; tire-o de lá antes de apagar", "projects": projects_json(Some(p))});
        return Ok((StatusCode::CONFLICT, Json(body)).into_response());
    }
    if has_active_job(&s.pool, auth.user_id, &hash).await? {
        return Err(err(StatusCode::CONFLICT, "há uma tarefa em andamento com este áudio; tente de novo quando ela terminar"));
    }
    let freed = remove(&s, auth.user_id, &hash).await?.ok_or_else(ApiError::not_found)?;
    Ok(Json(json!({"freed_bytes": freed})).into_response())
}

/// Apaga de uma vez todos os áudios da conta que nenhum documento cita (menos os enviados na última
/// hora, ver `CLEANUP_GRACE_SECS`).
pub async fn cleanup(State(s): State<AppState>, auth: Auth) -> ApiResult<Value> {
    let rows: Vec<(String, i64, DateTime<Utc>)> =
        sqlx::query_as("SELECT hash, size, created_at FROM samples WHERE owner_id = $1").bind(auth.user_id).fetch_all(&s.pool).await?;
    let refs = references(&s.pool, auth.user_id).await?;
    let cutoff = Utc::now() - chrono::Duration::seconds(CLEANUP_GRACE_SECS);
    let (mut removed, mut freed, mut recent) = (0u32, 0i64, 0u32);
    for (hash, _, created_at) in rows {
        if refs.projects.contains_key(&hash) || has_active_job(&s.pool, auth.user_id, &hash).await? {
            continue;
        }
        if created_at > cutoff {
            recent += 1;
            continue;
        }
        if let Some(size) = remove(&s, auth.user_id, &hash).await? {
            removed += 1;
            freed += size;
        }
    }
    Ok(Json(json!({"removed": removed, "freed_bytes": freed, "skipped_recent": recent})))
}
