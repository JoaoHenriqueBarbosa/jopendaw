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
use std::collections::HashSet;
use uuid::Uuid;

use super::{ApiError, ApiResult, err, projects::owned, samples::collect_hashes};
use crate::{AppState, auth::Auth, entities::prelude::ProjectDoc, storage};

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

    // a troca de versão e o updated_at do projeto andam juntos: ou os dois, ou nenhum. Tudo abaixo (ler o documento
    // gravado, conferir os áudios, gravar) usa esta única conexão, que segura as travas: pedir outra ao pool enquanto
    // se segura uma esgotaria o pool (10 conexões) com ~10 chamadas simultâneas
    let mut tx = s.pool.begin().await?;
    // áudios que este documento passa a citar: a trava por hash (a mesma do apagar e do criar tarefa) vale até o
    // commit, então um apagar concorrente ou espera este documento (e o vê ao conferir os usos) ou já terminou,
    // e aí a conferência abaixo pega o áudio que sumiu
    let newly = newly_cited(&mut tx, auth.user_id, id, &b.doc).await?;
    storage::lock_hashes(&mut tx, &newly).await?;
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

    // a versão velha vem primeiro (409 com o documento vencedor): quem está desatualizado precisa antes do documento
    // do servidor, e só depois de reenviar áudio faz sentido falar em áudio sumido
    let Some((version, updated_at)) = written else {
        let cur: Option<(i64, Option<sqlx::types::Json<Value>>)> =
            sqlx::query_as("SELECT version, doc FROM project_docs WHERE project_id = $1").bind(id).fetch_optional(&mut *tx).await?;
        tx.rollback().await?;
        let (version, doc) = cur.map(|(v, d)| (v, d.map(|d| d.0))).unwrap_or((0, None));
        let body = json!({"error": "o projeto foi alterado em outro lugar; recarregue a versão do servidor", "version": version, "doc": doc});
        return Ok((StatusCode::CONFLICT, Json(body)).into_response());
    };
    if !newly.is_empty() {
        let alive: Vec<(String,)> =
            sqlx::query_as("SELECT hash FROM samples WHERE owner_id = $1 AND hash = ANY($2)").bind(auth.user_id).bind(&newly).fetch_all(&mut *tx).await?;
        let alive: HashSet<String> = alive.into_iter().map(|r| r.0).collect();
        let gone: Vec<&String> = newly.iter().filter(|h| !alive.contains(*h)).collect();
        if !gone.is_empty() {
            // a gravação acima volta junto: a versão não anda
            tx.rollback().await?;
            let body =
                json!({"error": "um áudio citado pelo projeto foi apagado neste instante; envie o áudio de novo e tente salvar outra vez", "missing": gone});
            return Ok((StatusCode::UNPROCESSABLE_ENTITY, Json(body)).into_response());
        }
    }
    sqlx::query("UPDATE projects SET updated_at = $2 WHERE id = $1").bind(id).bind(updated_at).execute(&mut *tx).await?;
    tx.commit().await?;
    Ok(Json(json!({"version": version, "updated_at": updated_at})).into_response())
}

/// Os áudios da conta que `doc` cita e a versão gravada do projeto ainda não citava (só esses precisam de trava:
/// os que já eram citados continuam protegidos pela própria citação). Lê pela conexão da transação `tx`.
async fn newly_cited(tx: &mut sqlx::Transaction<'static, sqlx::Postgres>, owner: Uuid, project: Uuid, doc: &Value) -> Result<Vec<String>, sqlx::Error> {
    let mut cited = HashSet::new();
    collect_hashes(doc, &mut cited);
    if cited.is_empty() {
        return Ok(Vec::new());
    }
    let old: Option<(sqlx::types::Json<Value>,)> =
        sqlx::query_as("SELECT doc FROM project_docs WHERE project_id = $1 AND doc IS NOT NULL").bind(project).fetch_optional(&mut **tx).await?;
    if let Some((old,)) = old {
        let mut before = HashSet::new();
        collect_hashes(&old.0, &mut before);
        cited.retain(|h| !before.contains(h));
    }
    let cited: Vec<String> = cited.into_iter().collect();
    let owned: Vec<(String,)> =
        sqlx::query_as("SELECT hash FROM samples WHERE owner_id = $1 AND hash = ANY($2)").bind(owner).bind(&cited).fetch_all(&mut **tx).await?;
    Ok(owned.into_iter().map(|r| r.0).collect())
}

fn too_big() -> ApiError {
    err(StatusCode::PAYLOAD_TOO_LARGE, "documento grande demais (máximo de 8 MB)")
}
