//! Áudios da conta, endereçados pelo SHA-256 do conteúdo. O app pergunta quais faltam, manda só
//! esses e depois lê de volta por hash. Os bytes ficam em disco (`storage.rs`), o registro e a
//! cota no banco.

use axum::{
    Json,
    body::Body,
    extract::{Path, State},
    http::{HeaderMap, HeaderValue, StatusCode, header},
    response::Response,
};
use futures_util::StreamExt;
use sea_orm::{ColumnTrait, EntityTrait, QueryFilter};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use tokio::io::AsyncWriteExt;
use tokio_util::io::ReaderStream;

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
    err(StatusCode::PAYLOAD_TOO_LARGE, "cota de armazenamento de 4 GB excedida; apague áudios que não usa mais")
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

    // em streaming: cada pedaço vai para o disco e para o hash, sem segurar o arquivo na RAM. Os
    // tetos valem pelo que realmente chega, não pelo Content-Length, que o cliente pode mentir.
    let dir = &s.cfg.data_dir;
    let tmp = storage::new_tmp(dir).await.map_err(ApiError::internal)?;
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
    // mesmo que o arquivo já exista no disco (de outra conta), o conteúdo mandado é conferido: senão
    // bastaria saber um hash para "ter" o áudio de outra pessoa
    if storage::hex(&hasher.finalize()) != hash {
        return Err(err(StatusCode::BAD_REQUEST, "o SHA-256 do corpo não confere com o hash da URL"));
    }
    storage::commit_tmp(dir, &tmp, &hash).await.map_err(ApiError::internal)?;
    guard.keep();
    match storage::register(&s.pool, auth.user_id, &hash, size as i64).await {
        Ok(()) => Ok(StatusCode::NO_CONTENT),
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
    let file = tokio::fs::File::open(storage::blob_path(&s.cfg.data_dir, &hash)).await.map_err(|e| {
        tracing::error!(hash = %hash, error = %e, "registro sem arquivo em disco");
        ApiError::not_found()
    })?;
    let mut res = Response::new(Body::from_stream(ReaderStream::new(file)));
    let h = res.headers_mut();
    h.insert(header::CONTENT_TYPE, HeaderValue::from_static("application/octet-stream"));
    h.insert(header::CONTENT_LENGTH, HeaderValue::from(rec.size as u64));
    // o endereço é o hash do conteúdo: nunca muda, então o navegador pode guardar para sempre (e
    // `private` impede cache compartilhado, já que só o dono lê)
    h.insert(header::CACHE_CONTROL, HeaderValue::from_static("private, max-age=31536000, immutable"));
    Ok(res)
}
