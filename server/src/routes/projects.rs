//! Projetos da conta, sobre o query builder do SeaORM. Toda consulta filtra pelo dono: projeto
//! alheio responde 404, igual ao inexistente.

use axum::{
    Json,
    extract::{Path, State},
    http::StatusCode,
};
use chrono::Utc;
use sea_orm::{ActiveModelTrait, ColumnTrait, DatabaseConnection, EntityTrait, QueryFilter, QueryOrder, Set};
use serde::Deserialize;
use uuid::Uuid;

use super::{ApiError, ApiResult, err};
use crate::{
    auth::Auth,
    entities::{prelude::Project, project},
};

const DEFAULT_BPM: i32 = 120;
const DEFAULT_SAMPLE_RATE: i32 = 48_000;

async fn owned(db: &DatabaseConnection, auth: &Auth, id: Uuid) -> Result<project::Model, ApiError> {
    Project::find_by_id(id).filter(project::Column::OwnerId.eq(auth.user_id)).one(db).await?.ok_or_else(ApiError::not_found)
}

fn valid_name(raw: &str) -> Result<String, ApiError> {
    let n = raw.trim();
    if n.is_empty() || n.chars().count() > 120 || n.chars().any(char::is_control) {
        return Err(err(StatusCode::BAD_REQUEST, "nome: de 1 a 120 caracteres, sem quebra de linha"));
    }
    Ok(n.to_string())
}

fn valid_bpm(bpm: i32) -> Result<i32, ApiError> {
    if (20..=999).contains(&bpm) { Ok(bpm) } else { Err(err(StatusCode::BAD_REQUEST, "andamento: de 20 a 999 BPM")) }
}

/// Fórmula de compasso: 1 a 32 tempos, figura potência de 2 até 32.
fn valid_meter(beats: i32, unit: i32) -> Result<(i32, i32), ApiError> {
    if (1..=32).contains(&beats) && matches!(unit, 1 | 2 | 4 | 8 | 16 | 32) {
        Ok((beats, unit))
    } else {
        Err(err(StatusCode::BAD_REQUEST, "fórmula de compasso inválida"))
    }
}

pub async fn list(State(db): State<DatabaseConnection>, auth: Auth) -> ApiResult<Vec<project::Model>> {
    let rows = Project::find().filter(project::Column::OwnerId.eq(auth.user_id)).order_by_desc(project::Column::UpdatedAt).all(&db).await?;
    Ok(Json(rows))
}

pub async fn get(State(db): State<DatabaseConnection>, auth: Auth, Path(id): Path<Uuid>) -> ApiResult<project::Model> {
    Ok(Json(owned(&db, &auth, id).await?))
}

#[derive(Deserialize)]
pub struct NewProject {
    name: String,
    bpm: Option<i32>,
    beats_per_bar: Option<i32>,
    beat_unit: Option<i32>,
    sample_rate: Option<i32>,
}

pub async fn create(State(db): State<DatabaseConnection>, auth: Auth, Json(b): Json<NewProject>) -> Result<(StatusCode, Json<project::Model>), ApiError> {
    let (beats, unit) = valid_meter(b.beats_per_bar.unwrap_or(4), b.beat_unit.unwrap_or(4))?;
    let sample_rate = b.sample_rate.unwrap_or(DEFAULT_SAMPLE_RATE);
    if !matches!(sample_rate, 44_100 | 48_000 | 88_200 | 96_000) {
        return Err(err(StatusCode::BAD_REQUEST, "taxa de amostragem: 44100, 48000, 88200 ou 96000"));
    }
    let now = Utc::now().fixed_offset();
    let p = project::ActiveModel {
        id: Set(Uuid::new_v4()),
        owner_id: Set(auth.user_id),
        name: Set(valid_name(&b.name)?),
        bpm: Set(valid_bpm(b.bpm.unwrap_or(DEFAULT_BPM))?),
        beats_per_bar: Set(beats),
        beat_unit: Set(unit),
        sample_rate: Set(sample_rate),
        created_at: Set(now),
        updated_at: Set(now),
    }
    .insert(&db)
    .await?;
    Ok((StatusCode::CREATED, Json(p)))
}

#[derive(Deserialize)]
pub struct PatchProject {
    name: Option<String>,
    bpm: Option<i32>,
    beats_per_bar: Option<i32>,
    beat_unit: Option<i32>,
}

pub async fn patch(State(db): State<DatabaseConnection>, auth: Auth, Path(id): Path<Uuid>, Json(b): Json<PatchProject>) -> ApiResult<project::Model> {
    let current = owned(&db, &auth, id).await?;
    let (beats, unit) = valid_meter(b.beats_per_bar.unwrap_or(current.beats_per_bar), b.beat_unit.unwrap_or(current.beat_unit))?;
    let mut p: project::ActiveModel = current.into();
    if let Some(n) = b.name {
        p.name = Set(valid_name(&n)?);
    }
    if let Some(bpm) = b.bpm {
        p.bpm = Set(valid_bpm(bpm)?);
    }
    p.beats_per_bar = Set(beats);
    p.beat_unit = Set(unit);
    p.updated_at = Set(Utc::now().fixed_offset());
    Ok(Json(p.update(&db).await?))
}

pub async fn delete(State(db): State<DatabaseConnection>, auth: Auth, Path(id): Path<Uuid>) -> Result<StatusCode, ApiError> {
    let r = Project::delete_many().filter(project::Column::Id.eq(id)).filter(project::Column::OwnerId.eq(auth.user_id)).exec(&db).await?;
    if r.rows_affected == 0 {
        return Err(ApiError::not_found());
    }
    Ok(StatusCode::NO_CONTENT)
}
