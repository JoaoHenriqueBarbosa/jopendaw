//! Armazenamento dos áudios, endereçado pelo SHA-256: `blobs/<2 hex>/<hash>`, em disco
//! (`DATA_DIR`, desenvolvimento e testes) ou num bucket S3 compatível (produção, MinIO). O banco
//! (`samples`) diz de quem é cada blob e quanto a conta já usa; o objeto em si é um só por
//! conteúdo, mesmo que várias contas o tenham. Em disco a escrita é temporário + rename; no S3 o
//! objeto só aparece depois do PUT completo. Nos dois casos nunca existe blob pela metade.

use std::{
    io,
    path::{Path, PathBuf},
    time::{Duration, SystemTime},
};

use anyhow::{Context, bail};
use axum::body::Body;
use futures_util::StreamExt;
use rusty_s3::{Bucket, Credentials, S3Action, UrlStyle, actions::ListObjectsV2};
use sha2::{Digest, Sha256};
use sqlx::PgPool;
use tokio_util::io::ReaderStream;
use uuid::Uuid;

use crate::config::{Config, S3Config};

/// Teto de um arquivo.
pub const MAX_SAMPLE_BYTES: u64 = 512 * 1024 * 1024;
/// Cota de cada conta.
pub const QUOTA_BYTES: i64 = 4 * 1024 * 1024 * 1024;
/// Arquivo sem registro só é apagado depois disso: dá tempo de um upload ou job terminar de
/// registrar o que acabou de gravar.
const ORPHAN_GRACE: Duration = Duration::from_secs(3600);

/// SHA-256 em hexadecimal minúsculo (64 caracteres).
pub fn valid_hash(s: &str) -> bool {
    s.len() == 64 && s.bytes().all(|b| matches!(b, b'0'..=b'9' | b'a'..=b'f'))
}

pub fn hex_sha256(bytes: &[u8]) -> String {
    hex(&Sha256::digest(bytes))
}

pub fn hex(digest: &[u8]) -> String {
    digest.iter().map(|b| format!("{b:02x}")).collect()
}

/// Chave do objeto no bucket (e caminho relativo em disco): `blobs/<2 hex>/<hash>`. O chamador
/// garante `valid_hash`: é isso que impede `..` e barras.
fn blob_key(hash: &str) -> String {
    format!("blobs/{}/{}", &hash[..2], hash)
}

/// Apaga o arquivo temporário se o upload falhar ou o cliente desistir (a future é largada no
/// meio). `keep` desarma depois que o `commit_tmp` consumiu o arquivo.
pub struct TmpGuard(Option<PathBuf>);

impl TmpGuard {
    pub fn new(p: &Path) -> Self {
        TmpGuard(Some(p.to_path_buf()))
    }
    pub fn keep(&mut self) {
        self.0 = None;
    }
}

impl Drop for TmpGuard {
    fn drop(&mut self) {
        if let Some(p) = self.0.take() {
            let _ = std::fs::remove_file(p);
        }
    }
}

/// Um blob aberto para leitura: o corpo em streaming e o tamanho, quando o backend o informa.
pub struct Blob {
    pub body: Body,
    pub len: Option<u64>,
}

/// Um blob listado, para a faxina.
pub struct BlobInfo {
    pub hash: String,
    pub modified: SystemTime,
}

/// Onde os bytes moram. Disco em desenvolvimento e testes, S3 (MinIO) em produção; o resto do
/// servidor só conversa com isto. O envio sempre passa antes por um arquivo temporário local
/// (`new_tmp`), que é onde o hash, o tamanho e a cota são conferidos.
pub struct Store {
    /// `DATA_DIR`: raiz dos blobs no modo disco e dos temporários nos dois modos.
    dir: PathBuf,
    backend: Backend,
}

enum Backend {
    Disk,
    S3(Box<S3>),
}

struct S3 {
    bucket: Bucket,
    creds: Credentials,
    http: reqwest::Client,
}

/// Validade das URLs assinadas: cada uma é usada na hora.
const SIGN_TTL: Duration = Duration::from_secs(300);
/// Operações curtas (HEAD, DELETE, listagem); PUT e GET de blobs não têm teto de tempo total.
const SHORT_TIMEOUT: Duration = Duration::from_secs(60);

impl Store {
    /// S3 se `S3_ENDPOINT` estava definido, senão disco em `DATA_DIR`.
    pub fn from_config(cfg: &Config) -> anyhow::Result<Self> {
        match &cfg.s3 {
            None => Ok(Store { dir: cfg.data_dir.clone(), backend: Backend::Disk }),
            Some(c) => Self::from_s3(c.clone(), cfg.data_dir.clone()),
        }
    }

    /// `dir` continua servindo de raiz dos temporários de upload.
    pub fn from_s3(c: S3Config, dir: PathBuf) -> anyhow::Result<Self> {
        let endpoint: reqwest::Url = c.endpoint.parse().with_context(|| format!("S3_ENDPOINT inválido: {}", c.endpoint))?;
        let style = if c.path_style { UrlStyle::Path } else { UrlStyle::VirtualHost };
        let bucket = Bucket::new(endpoint, style, c.bucket, c.region).context("S3_ENDPOINT/S3_BUCKET inválidos")?;
        let http = reqwest::Client::builder().connect_timeout(Duration::from_secs(10)).build()?;
        Ok(Store { dir, backend: Backend::S3(Box::new(S3 { bucket, creds: Credentials::new(c.access_key, c.secret_key), http })) })
    }

    pub fn kind(&self) -> &'static str {
        match self.backend {
            Backend::Disk => "disco",
            Backend::S3(_) => "S3",
        }
    }

    fn disk_path(&self, hash: &str) -> PathBuf {
        self.dir.join(blob_key(hash))
    }

    /// Um caminho novo para escrever, em `DATA_DIR/tmp` (no modo disco, o mesmo volume do destino,
    /// para o rename valer).
    pub async fn new_tmp(&self) -> io::Result<PathBuf> {
        let tmp = self.dir.join("tmp");
        tokio::fs::create_dir_all(&tmp).await?;
        Ok(tmp.join(Uuid::new_v4().to_string()))
    }

    pub async fn exists(&self, hash: &str) -> anyhow::Result<bool> {
        match &self.backend {
            Backend::Disk => Ok(tokio::fs::try_exists(self.disk_path(hash)).await?),
            Backend::S3(s3) => {
                let url = s3.bucket.head_object(Some(&s3.creds), &blob_key(hash)).sign(SIGN_TTL);
                let res = s3.http.head(url).timeout(SHORT_TIMEOUT).send().await?;
                match res.status() {
                    s if s.is_success() => Ok(true),
                    reqwest::StatusCode::NOT_FOUND => Ok(false),
                    s => bail!("S3 HEAD respondeu {s}"),
                }
            }
        }
    }

    /// Guarda o temporário (já conferido) como o blob e o consome. Se o blob já existe (mesmo
    /// conteúdo, outra conta), só descarta o temporário: no S3 isso poupa o PUT.
    pub async fn commit_tmp(&self, tmp: &Path, hash: &str) -> anyhow::Result<()> {
        if self.exists(hash).await? {
            tokio::fs::remove_file(tmp).await?;
            return Ok(());
        }
        match &self.backend {
            Backend::Disk => {
                let dest = self.disk_path(hash);
                tokio::fs::create_dir_all(dest.parent().expect("blob tem pasta")).await?;
                tokio::fs::rename(tmp, &dest).await?;
            }
            Backend::S3(s3) => {
                // PUT de objeto único (até 5 GB, e o teto aqui é 512 MB), lido do disco em streaming
                s3.put_file(tmp, hash).await?;
                tokio::fs::remove_file(tmp).await?;
            }
        }
        Ok(())
    }

    /// Grava bytes já em memória (resultado de um job).
    pub async fn store_bytes(&self, hash: &str, bytes: &[u8]) -> anyhow::Result<()> {
        let tmp = self.new_tmp().await?;
        let _guard = TmpGuard::new(&tmp);
        tokio::fs::write(&tmp, bytes).await?;
        self.commit_tmp(&tmp, hash).await
    }

    /// Abre o blob em streaming. `None` se não existe.
    pub async fn open(&self, hash: &str) -> anyhow::Result<Option<Blob>> {
        match &self.backend {
            Backend::Disk => match tokio::fs::File::open(self.disk_path(hash)).await {
                Ok(f) => {
                    let len = f.metadata().await.ok().map(|m| m.len());
                    Ok(Some(Blob { body: Body::from_stream(ReaderStream::new(f)), len }))
                }
                Err(e) if e.kind() == io::ErrorKind::NotFound => Ok(None),
                Err(e) => Err(e.into()),
            },
            Backend::S3(s3) => {
                let url = s3.bucket.get_object(Some(&s3.creds), &blob_key(hash)).sign(SIGN_TTL);
                let res = s3.http.get(url).send().await?;
                match res.status() {
                    reqwest::StatusCode::NOT_FOUND => Ok(None),
                    s if s.is_success() => {
                        let len = res.content_length();
                        Ok(Some(Blob { body: Body::from_stream(res.bytes_stream()), len }))
                    }
                    s => bail!("S3 GET respondeu {s}"),
                }
            }
        }
    }

    /// Lê o blob inteiro para a memória (os jobs decodificam o áudio todo de qualquer jeito).
    pub async fn read(&self, hash: &str) -> anyhow::Result<Option<Vec<u8>>> {
        let Some(blob) = self.open(hash).await? else { return Ok(None) };
        let mut out = Vec::with_capacity(blob.len.unwrap_or(0).min(MAX_SAMPLE_BYTES) as usize);
        let mut stream = blob.body.into_data_stream();
        while let Some(chunk) = stream.next().await {
            out.extend_from_slice(&chunk?);
            if out.len() as u64 > MAX_SAMPLE_BYTES {
                bail!("blob acima do teto de {MAX_SAMPLE_BYTES} bytes");
            }
        }
        Ok(Some(out))
    }

    pub async fn delete(&self, hash: &str) -> anyhow::Result<()> {
        match &self.backend {
            Backend::Disk => match tokio::fs::remove_file(self.disk_path(hash)).await {
                Ok(()) => Ok(()),
                Err(e) if e.kind() == io::ErrorKind::NotFound => Ok(()),
                Err(e) => Err(e.into()),
            },
            Backend::S3(s3) => {
                let url = s3.bucket.delete_object(Some(&s3.creds), &blob_key(hash)).sign(SIGN_TTL);
                let res = s3.http.delete(url).timeout(SHORT_TIMEOUT).send().await?;
                // o S3 responde 204 mesmo para chave inexistente
                if !res.status().is_success() {
                    bail!("S3 DELETE respondeu {}", res.status());
                }
                Ok(())
            }
        }
    }

    /// Todos os blobs do armazenamento (no S3, a listagem paginada de `blobs/`).
    pub async fn list(&self) -> anyhow::Result<Vec<BlobInfo>> {
        let mut out = Vec::new();
        match &self.backend {
            Backend::Disk => {
                let Ok(mut shards) = tokio::fs::read_dir(self.dir.join("blobs")).await else { return Ok(out) };
                while let Some(shard) = shards.next_entry().await? {
                    let Ok(mut files) = tokio::fs::read_dir(shard.path()).await else { continue };
                    while let Some(f) = files.next_entry().await? {
                        let hash = f.file_name().to_string_lossy().into_owned();
                        let Ok(meta) = f.metadata().await else { continue };
                        if valid_hash(&hash)
                            && meta.is_file()
                            && let Ok(modified) = meta.modified()
                        {
                            out.push(BlobInfo { hash, modified });
                        }
                    }
                }
            }
            Backend::S3(s3) => {
                let mut token: Option<String> = None;
                loop {
                    let mut action = s3.bucket.list_objects_v2(Some(&s3.creds));
                    action.with_prefix("blobs/");
                    if let Some(t) = &token {
                        action.with_continuation_token(t.clone());
                    }
                    let res = s3.http.get(action.sign(SIGN_TTL)).timeout(SHORT_TIMEOUT).send().await?;
                    if !res.status().is_success() {
                        bail!("S3 ListObjectsV2 respondeu {}", res.status());
                    }
                    let page = ListObjectsV2::parse_response(&res.text().await?).context("resposta da listagem do S3 ilegível")?;
                    for o in page.contents {
                        let hash = o.key.rsplit('/').next().unwrap_or_default().to_string();
                        let modified = chrono::DateTime::parse_from_rfc3339(&o.last_modified).map(SystemTime::from);
                        if let (true, Ok(modified)) = (valid_hash(&hash), modified) {
                            out.push(BlobInfo { hash, modified });
                        }
                    }
                    match page.next_continuation_token {
                        Some(t) => token = Some(t),
                        None => break,
                    }
                }
            }
        }
        Ok(out)
    }

    /// Copia os blobs de `dir/blobs` (um `DATA_DIR` antigo) para este armazenamento (S3), pulando
    /// os que já estão lá: pode rodar quantas vezes precisar. Devolve (copiados, já existiam).
    pub async fn import_from_disk(&self, dir: &Path) -> anyhow::Result<(u32, u32)> {
        let Backend::S3(s3) = &self.backend else { bail!("o destino da migração precisa ser o S3") };
        let src = Store { dir: dir.to_path_buf(), backend: Backend::Disk };
        let (mut copied, mut skipped) = (0, 0);
        for b in src.list().await? {
            if self.exists(&b.hash).await? {
                skipped += 1;
                continue;
            }
            s3.put_file(&src.disk_path(&b.hash), &b.hash).await?;
            copied += 1;
            tracing::info!(hash = %b.hash, "blob copiado para o S3");
        }
        Ok((copied, skipped))
    }
}

impl S3 {
    async fn put_file(&self, path: &Path, hash: &str) -> anyhow::Result<()> {
        let file = tokio::fs::File::open(path).await?;
        let len = file.metadata().await?.len();
        let url = self.bucket.put_object(Some(&self.creds), &blob_key(hash)).sign(SIGN_TTL);
        // Content-Length explícito: o S3 não aceita corpo em chunked
        let res = self.http.put(url).header(reqwest::header::CONTENT_LENGTH, len).body(reqwest::Body::wrap_stream(ReaderStream::new(file))).send().await?;
        if !res.status().is_success() {
            bail!("S3 PUT respondeu {}: {}", res.status(), res.text().await.unwrap_or_default());
        }
        Ok(())
    }
}

pub async fn used_bytes(pool: &PgPool, owner: Uuid) -> Result<i64, sqlx::Error> {
    let (n,): (i64,) = sqlx::query_as("SELECT COALESCE(sum(size), 0)::bigint FROM samples WHERE owner_id = $1").bind(owner).fetch_one(pool).await?;
    Ok(n)
}

/// Trava (até o fim da transação devolvida) o que se faz com um conteúdo, para gravar e apagar o mesmo
/// hash não se cruzarem: sem ela, apagar o blob de uma conta enquanto outra acaba de "reaproveitá-lo"
/// no envio deixaria um registro sem arquivo.
pub async fn lock_hash(pool: &PgPool, hash: &str) -> Result<sqlx::Transaction<'static, sqlx::Postgres>, sqlx::Error> {
    let mut tx = pool.begin().await?;
    sqlx::query("SELECT pg_advisory_xact_lock(hashtextextended($1, 1))").bind(hash).execute(&mut *tx).await?;
    Ok(tx)
}

/// Mensagem da cota estourada, a mesma no envio e nas tarefas (a saída é a mesma: apagar o que não se usa).
pub const QUOTA_MESSAGE: &str = "cota de armazenamento de 4 GB excedida; apague áudios sem uso na tela Conta";

/// Toma, na transação `tx`, a trava por hash (a mesma de [`lock_hash`]) de vários conteúdos de uma vez, em
/// ordem fixa para duas transações com os mesmos hashes não se travarem uma na outra.
pub async fn lock_hashes(tx: &mut sqlx::Transaction<'static, sqlx::Postgres>, hashes: &[String]) -> Result<(), sqlx::Error> {
    let mut sorted: Vec<&String> = hashes.iter().collect();
    sorted.sort();
    sorted.dedup();
    for h in sorted {
        sqlx::query("SELECT pg_advisory_xact_lock(hashtextextended($1, 1))").bind(h).execute(&mut **tx).await?;
    }
    Ok(())
}

pub enum RegisterError {
    /// Passaria da cota da conta.
    Quota,
    Db(sqlx::Error),
}

impl From<sqlx::Error> for RegisterError {
    fn from(e: sqlx::Error) -> Self {
        RegisterError::Db(e)
    }
}

/// Registra que a conta tem o blob, respeitando a cota. O advisory lock por conta serializa
/// uploads simultâneos: sem ele, dois de 3 GB conferem "cabe" ao mesmo tempo e passam de 4 GB.
/// Já registrado não conta duas vezes.
pub async fn register(pool: &PgPool, owner: Uuid, hash: &str, size: i64) -> Result<(), RegisterError> {
    let mut tx = pool.begin().await?;
    sqlx::query("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))").bind(owner.to_string()).execute(&mut *tx).await?;
    let has: Option<(i64,)> =
        sqlx::query_as("SELECT size FROM samples WHERE owner_id = $1 AND hash = $2").bind(owner).bind(hash).fetch_optional(&mut *tx).await?;
    if has.is_none() {
        let (used,): (i64,) = sqlx::query_as("SELECT COALESCE(sum(size), 0)::bigint FROM samples WHERE owner_id = $1").bind(owner).fetch_one(&mut *tx).await?;
        if used + size > QUOTA_BYTES {
            return Err(RegisterError::Quota);
        }
        sqlx::query("INSERT INTO samples (owner_id, hash, size) VALUES ($1, $2, $3)").bind(owner).bind(hash).bind(size).execute(&mut *tx).await?;
    }
    tx.commit().await?;
    Ok(())
}

/// Faxina: apaga blobs que nenhuma conta registra (contas apagadas, cota estourada no meio) e
/// temporários esquecidos por uma queda, sempre só os de mais de uma hora.
pub async fn cleanup(pool: &PgPool, store: &Store) -> anyhow::Result<()> {
    cleanup_before(pool, store, SystemTime::now() - ORPHAN_GRACE).await
}

/// A faxina de fato: só mexe no que foi modificado antes de `cutoff`. Separada para os testes
/// escolherem o corte sem depender de `set_modified`, que o S3 não tem.
pub async fn cleanup_before(pool: &PgPool, store: &Store, cutoff: SystemTime) -> anyhow::Result<()> {
    let mut removed = 0u32;
    // os temporários são sempre locais, também no modo S3
    if let Ok(mut rd) = tokio::fs::read_dir(store.dir.join("tmp")).await {
        while let Some(e) = rd.next_entry().await? {
            let old = e.metadata().await.is_ok_and(|m| m.is_file() && m.modified().is_ok_and(|t| t < cutoff));
            if old && tokio::fs::remove_file(e.path()).await.is_ok() {
                removed += 1;
            }
        }
    }
    for b in store.list().await? {
        if b.modified >= cutoff {
            continue;
        }
        let (used,): (bool,) = sqlx::query_as("SELECT EXISTS (SELECT 1 FROM samples WHERE hash = $1)").bind(&b.hash).fetch_one(pool).await?;
        if !used && store.delete(&b.hash).await.is_ok() {
            removed += 1;
        }
    }
    if removed > 0 {
        tracing::info!(removed, "faxina dos arquivos de áudio sem registro");
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hash_valido_so_hex_minusculo_de_64() {
        assert!(valid_hash(&"a".repeat(64)));
        assert!(!valid_hash(&"A".repeat(64)));
        assert!(!valid_hash(&"a".repeat(63)));
        assert!(!valid_hash(&format!("../{}", "a".repeat(61))));
    }

    #[test]
    fn sha256_conhecido() {
        assert_eq!(hex_sha256(b"abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
    }
}
