//! O documento de um projeto (faixas, clipes, mixagem) como JSON versionado. O app grava com
//! concorrência otimista: manda a versão em que se baseou e só vale se ela ainda for a atual; do
//! contrário volta 409 com o documento do servidor para o app decidir o que fazer.

use axum::{
    Json,
    body::{Body, to_bytes},
    extract::{Path, State},
    http::StatusCode,
    response::{IntoResponse, Response},
};
use chrono::{DateTime, Utc};
use sea_orm::EntityTrait;
use serde::Deserialize;
use serde_json::{Value, json};
use uuid::Uuid;

use super::{ApiError, ApiResult, err, projects::owned};
use crate::{AppState, auth::Auth, entities::prelude::ProjectDoc};

/// Teto do documento. O corpo também leva `base_version` e as chaves, então a leitura aceita uma
/// folga pequena e quem decide é o tamanho do corpo inteiro.
const DOC_MAX_BYTES: usize = 8 * 1024 * 1024;

pub async fn get(State(s): State<AppState>, auth: Auth, Path(id): Path<Uuid>) -> ApiResult<Value> {
    let project = owned(&s.db, &auth, id).await?;
    Ok(Json(match ProjectDoc::find_by_id(id).one(&s.db).await? {
        Some(d) => json!({"version": d.version, "doc": d.doc, "updated_at": d.updated_at}),
        // projeto que ainda não tem documento: versão 0, e o primeiro PUT parte dela
        None => json!({"version": 0, "doc": null, "updated_at": project.updated_at}),
    }))
}

#[derive(Deserialize)]
struct PutDoc {
    base_version: i64,
    doc: Value,
}

pub async fn put(State(s): State<AppState>, auth: Auth, Path(id): Path<Uuid>, body: Body) -> Result<Response, ApiError> {
    owned(&s.db, &auth, id).await?;
    // sem o limite padrão do axum (2 MB) nesta rota: quem corta é o teto do documento, com a
    // resposta no formato da API em vez de texto solto
    let bytes = to_bytes(body, DOC_MAX_BYTES + 1).await.map_err(|_| too_big())?;
    if bytes.len() > DOC_MAX_BYTES {
        return Err(too_big());
    }
    // o jsonb do Postgres não guarda U+0000: melhor recusar aqui do que virar 500 no INSERT
    if bytes.windows(6).any(|w| w == b"\\u0000") {
        return Err(err(StatusCode::BAD_REQUEST, "o documento não pode conter o caractere nulo (U+0000)"));
    }
    let b: PutDoc = serde_json::from_slice(&bytes).map_err(|e| err(StatusCode::BAD_REQUEST, format!("corpo inválido: {e}")))?;
    if b.base_version < 0 {
        return Err(err(StatusCode::BAD_REQUEST, "base_version não pode ser negativo"));
    }
    if !b.doc.is_object() {
        return Err(err(StatusCode::BAD_REQUEST, "doc precisa ser um objeto"));
    }

    // a troca de versão e o updated_at do projeto andam juntos: ou os dois, ou nenhum
    let mut tx = s.pool.begin().await?;
    let doc = sqlx::types::Json(&b.doc);
    let written: Option<(i64, DateTime<Utc>)> = if b.base_version == 0 {
        // primeira gravação: se outra chegou antes, a linha já existe e o INSERT não retorna nada
        sqlx::query_as(
            "INSERT INTO project_docs (project_id, version, doc) VALUES ($1, 1, $2) ON CONFLICT (project_id) DO NOTHING RETURNING version, updated_at",
        )
        .bind(id)
        .bind(doc)
        .fetch_optional(&mut *tx)
        .await?
    } else {
        sqlx::query_as(
            "UPDATE project_docs SET version = version + 1, doc = $2, updated_at = now() WHERE project_id = $1 AND version = $3 RETURNING version, updated_at",
        )
        .bind(id)
        .bind(doc)
        .bind(b.base_version)
        .fetch_optional(&mut *tx)
        .await?
    };

    let Some((version, updated_at)) = written else {
        tx.rollback().await?;
        let cur = ProjectDoc::find_by_id(id).one(&s.db).await?;
        let (version, doc) = cur.map(|d| (d.version, d.doc)).unwrap_or((0, None));
        let body = json!({"error": "o projeto foi alterado em outro lugar; recarregue a versão do servidor", "version": version, "doc": doc});
        return Ok((StatusCode::CONFLICT, Json(body)).into_response());
    };
    sqlx::query("UPDATE projects SET updated_at = $2 WHERE id = $1").bind(id).bind(updated_at).execute(&mut *tx).await?;
    tx.commit().await?;
    Ok(Json(json!({"version": version, "updated_at": updated_at})).into_response())
}

fn too_big() -> ApiError {
    err(StatusCode::PAYLOAD_TOO_LARGE, "documento grande demais (máximo de 8 MB)")
}
