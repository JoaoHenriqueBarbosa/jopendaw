mod audio;
mod auth;
mod config;
mod db;
mod encode;
#[cfg(test)]
mod encode_tests;
mod entities;
mod mail;
mod oauth;
mod routes;
mod storage;

use std::{net::SocketAddr, sync::Arc, time::Duration};

use axum::http::{HeaderValue, header};
use axum::{Router, extract::FromRef};
use sea_orm::DatabaseConnection;
use sqlx::PgPool;
use tower_http::{
    cors::CorsLayer,
    services::{ServeDir, ServeFile},
    set_header::SetResponseHeaderLayer,
    trace::TraceLayer,
};

use crate::{config::Config, mail::Mailer};

/// Estado das rotas. O SeaORM e o sqlx dividem o mesmo pool: o domínio usa o query builder,
/// contas usam SQL direto pelo sqlx.
#[derive(Clone)]
pub struct AppState {
    pub db: DatabaseConnection,
    pub pool: PgPool,
    pub cfg: Arc<Config>,
    /// Onde os áudios moram (disco ou S3), criado no setup frio a partir do `Config`.
    pub store: Arc<storage::Store>,
    pub mailer: Arc<Mailer>,
    /// Acorda o worker das tarefas quando entra uma nova (`routes/jobs.rs`).
    pub job_wake: Arc<tokio::sync::Notify>,
}

/// Os handlers do domínio pedem só `State<DatabaseConnection>`.
impl FromRef<AppState> for DatabaseConnection {
    fn from_ref(s: &AppState) -> Self {
        s.db.clone()
    }
}

/// O que roda uma vez só: ambiente, log, banco, email e a faxina. Com o hot-patch, isto sobrevive
/// aos patches (nada de `std::env::var` na parte quente: o `.env` some depois de um patch).
struct Setup {
    state: AppState,
    static_dir: String,
    port: u16,
}

async fn setup() -> anyhow::Result<Setup> {
    dotenvy::dotenv().ok();
    tracing_subscriber::fmt().with_env_filter(tracing_subscriber::EnvFilter::try_from_default_env().unwrap_or_else(|_| "info,tower_http=info".into())).init();

    let cfg = Config::from_env()?;
    let static_dir = std::env::var("JOPENDAW_STATIC").unwrap_or_else(|_| "../app/build/web".into());
    let port: u16 = std::env::var("PORT").ok().and_then(|p| p.parse().ok()).unwrap_or(8080);

    let db = db::connect().await?;
    let pool = db.get_postgres_connection_pool().clone();
    tracing::info!("banco conectado");
    let mailer = Arc::new(Mailer::new(&cfg.jmail_url, &cfg.jmail_api_key)?);

    let store = Arc::new(storage::Store::from_config(&cfg)?);
    tracing::info!(backend = store.kind(), "armazenamento dos áudios");
    let state = AppState { db, pool: pool.clone(), cfg: Arc::new(cfg), store, mailer, job_wake: Arc::new(tokio::sync::Notify::new()) };

    // tarefas que estavam rodando quando o processo caiu voltam para a fila, e o worker começa
    routes::jobs::requeue_orphans(&pool).await?;
    tokio::spawn(routes::jobs::worker(state.clone()));

    // faxina de tokens vencidos e de áudios sem registro, uma vez por hora
    let cleanup_pool = pool.clone();
    let cleanup_store = state.store.clone();
    tokio::spawn(async move {
        loop {
            if let Err(e) = auth::cleanup(&cleanup_pool).await {
                tracing::warn!(error = %e, "faxina falhou");
            }
            if let Err(e) = oauth::cleanup(&cleanup_pool).await {
                tracing::warn!(error = %e, "faxina das entradas por provedor falhou");
            }
            if let Err(e) = storage::cleanup(&cleanup_pool, &cleanup_store).await {
                tracing::warn!(error = %e, "faxina dos áudios falhou");
            }
            tokio::time::sleep(Duration::from_secs(3600)).await;
        }
    });

    Ok(Setup { state, static_dir, port })
}

/// A parte quente: o roteador e o servidor HTTP. Com o hot-patch, cada patch derruba esta future
/// e cria outra com o código novo (handlers, rotas, validação), sem refazer o `setup`.
async fn serve(state: AppState, static_dir: String, port: u16) -> anyhow::Result<()> {
    let mut app = Router::new().merge(routes::router(state));

    // Em desenvolvimento o próprio servidor publica o build web do Flutter na raiz, e as
    // rotas desconhecidas caem no index.html (aplicação de página única). Em produção o
    // frontend tem container próprio, o diretório não existe e a API sobe sozinha.
    if std::path::Path::new(&static_dir).is_dir() {
        let index = format!("{static_dir}/index.html");
        let spa = ServeDir::new(&static_dir).not_found_service(ServeFile::new(index));
        app = app.fallback_service(spa);
        tracing::info!("publicando o frontend de {static_dir}");
    }

    // CORS aberto: a autenticação vai no cabeçalho Authorization, não em cookie, então outra
    // origem não tem credencial nenhuma para aproveitar
    let app = app
        .layer(CorsLayer::permissive())
        // os arquivos do Flutter não têm hash no nome (main.dart.js, engine/host.js, engine.wasm):
        // sem `Cache-Control` o navegador guarda por tempo heurístico (só há Last-Modified) e depois
        // de uma atualização o app novo roda com o host, o worklet ou o wasm velhos. `no-cache` faz
        // revalidar a cada carga (304 quando nada mudou), como o nginx de produção. A API já define
        // o próprio Cache-Control (no-store; os samples, immutable) e este só entra onde falta.
        .layer(SetResponseHeaderLayer::if_not_present(header::CACHE_CONTROL, HeaderValue::from_static("no-cache")))
        .layer(TraceLayer::new_for_http());

    let addr = SocketAddr::from(([0, 0, 0, 0], port));
    tracing::info!("escutando em http://{addr}");
    let listener = tokio::net::TcpListener::bind(addr).await?;
    axum::serve(listener, app).await?;
    Ok(())
}

/// `jopendaw-server migrate-blobs-to-s3`: copia `DATA_DIR/blobs` para o bucket (idempotente) e
/// sai, sem subir a API nem tocar no banco. Só precisa de `DATA_DIR` e das variáveis `S3_*`.
async fn migrate_blobs_to_s3() -> anyhow::Result<()> {
    dotenvy::dotenv().ok();
    tracing_subscriber::fmt().with_env_filter(tracing_subscriber::EnvFilter::try_from_default_env().unwrap_or_else(|_| "info".into())).init();
    let s3 = config::S3Config::from_env()?.ok_or_else(|| anyhow::anyhow!("defina S3_ENDPOINT (e S3_BUCKET, S3_ACCESS_KEY, S3_SECRET_KEY) para migrar"))?;
    let data_dir: std::path::PathBuf = std::env::var("DATA_DIR").unwrap_or_else(|_| "./data".into()).into();
    let store = storage::Store::from_s3(s3, data_dir.clone())?;
    let (copied, skipped) = store.import_from_disk(&data_dir).await?;
    tracing::info!(copied, skipped, "migração concluída");
    Ok(())
}

/// Subcomando de linha de comando que roda no lugar do servidor.
fn is_migration() -> bool {
    std::env::args().nth(1).as_deref() == Some("migrate-blobs-to-s3")
}

#[cfg(not(feature = "hot"))]
#[tokio::main]
async fn main() -> anyhow::Result<()> {
    if is_migration() {
        return migrate_blobs_to_s3().await;
    }
    let s = setup().await?;
    serve(s.state, s.static_dir, s.port).await
}

#[cfg(feature = "hot")]
#[tokio::main]
async fn main() -> anyhow::Result<()> {
    if is_migration() {
        return migrate_blobs_to_s3().await;
    }
    let s = setup().await?;
    let args = (s.state, s.static_dir, s.port);
    dioxus_devtools::serve_subsecond_with_args(args, |(state, static_dir, port)| async move {
        if let Err(e) = serve(state, static_dir, port).await {
            tracing::error!(error = %e, "servidor caiu");
        }
    })
    .await;
    Ok(())
}
