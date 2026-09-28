//! Entidades do SeaORM, uma por tabela do Postgres. As tabelas de contas (`users`, `sessions`,
//! `magic_links`, `oauth_*`) ficam fora: `auth.rs` e `oauth.rs` falam com elas em SQL direto.

pub mod project;

pub mod prelude {
    pub use super::project::Entity as Project;
}
