use sea_orm::entity::prelude::*;
use serde::Serialize;

/// Um projeto do DAW: a sessão de uma música, com o andamento e a fórmula de compasso. Faixas,
/// clipes e mixagem entram como tabelas filhas.
#[derive(Clone, Debug, PartialEq, Eq, DeriveEntityModel, Serialize)]
#[sea_orm(table_name = "projects")]
pub struct Model {
    #[sea_orm(primary_key, auto_increment = false)]
    pub id: Uuid,
    /// Dono do projeto; nunca sai na API.
    #[serde(skip)]
    pub owner_id: Uuid,
    pub name: String,
    pub bpm: i32,
    pub beats_per_bar: i32,
    pub beat_unit: i32,
    pub sample_rate: i32,
    pub created_at: DateTimeWithTimeZone,
    pub updated_at: DateTimeWithTimeZone,
}

#[derive(Copy, Clone, Debug, EnumIter, DeriveRelation)]
pub enum Relation {}

impl ActiveModelBehavior for ActiveModel {}
