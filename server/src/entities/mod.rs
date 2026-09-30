//! Entidades do SeaORM, uma por tabela do Postgres. As tabelas de contas (`users`, `sessions`,
//! `magic_links`, `oauth_*`) ficam fora: `auth.rs` e `oauth.rs` falam com elas em SQL direto.

pub mod job;
pub mod project;
pub mod project_doc;
pub mod sample;

pub mod prelude {
    pub use super::job::Entity as Job;
    pub use super::project::Entity as Project;
    pub use super::project_doc::Entity as ProjectDoc;
    pub use super::sample::Entity as Sample;
}
