use sea_orm::entity::prelude::*;

/// O documento de um projeto (JSONB), com a versão da concorrência otimista. A escrita é SQL
/// direto em `routes/docs.rs` (o `UPDATE ... WHERE version = $n` atômico); aqui só a leitura.
#[derive(Clone, Debug, PartialEq, DeriveEntityModel)]
#[sea_orm(table_name = "project_docs")]
pub struct Model {
    #[sea_orm(primary_key, auto_increment = false)]
    pub project_id: Uuid,
    pub version: i64,
    pub doc: Option<Json>,
    pub updated_at: DateTimeWithTimeZone,
}

#[derive(Copy, Clone, Debug, EnumIter, DeriveRelation)]
pub enum Relation {}

impl ActiveModelBehavior for ActiveModel {}
