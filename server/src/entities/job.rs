use sea_orm::entity::prelude::*;
use serde::Serialize;

/// Uma tarefa pesada na fila. O worker pega e atualiza por SQL direto (`jobs.rs`); a API lê por aqui.
#[derive(Clone, Debug, PartialEq, DeriveEntityModel, Serialize)]
#[sea_orm(table_name = "jobs")]
pub struct Model {
    #[sea_orm(primary_key, auto_increment = false)]
    pub id: Uuid,
    #[serde(skip)]
    pub owner_id: Uuid,
    pub kind: String,
    #[serde(skip)]
    pub sample_hash: String,
    #[serde(skip)]
    pub params: Option<Json>,
    pub status: String,
    pub progress: f32,
    pub error: Option<String>,
    pub result: Option<Json>,
    #[serde(skip)]
    pub created_at: DateTimeWithTimeZone,
    #[serde(skip)]
    pub updated_at: DateTimeWithTimeZone,
}

#[derive(Copy, Clone, Debug, EnumIter, DeriveRelation)]
pub enum Relation {}

impl ActiveModelBehavior for ActiveModel {}
