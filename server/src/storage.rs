//! Armazenamento dos áudios em disco, endereçado pelo SHA-256: `DATA_DIR/blobs/<2 hex>/<hash>`.
//! O banco (`samples`) diz de quem é cada blob e quanto a conta já usa; o arquivo em si é um só por
//! conteúdo, mesmo que várias contas o tenham. Escrita sempre em arquivo temporário seguido de
//! rename, então nunca existe um blob pela metade no caminho final.

use std::{
    io,
    path::{Path, PathBuf},
    time::{Duration, SystemTime},
};

use sha2::{Digest, Sha256};
use sqlx::PgPool;
use uuid::Uuid;

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

/// Caminho final do blob. O chamador garante `valid_hash`: é isso que impede `..` e barras.
pub fn blob_path(dir: &Path, hash: &str) -> PathBuf {
    dir.join("blobs").join(&hash[..2]).join(hash)
}

/// Um caminho novo para escrever, em `DATA_DIR/tmp` (mesmo volume do destino, para o rename valer).
pub async fn new_tmp(dir: &Path) -> io::Result<PathBuf> {
    let tmp = dir.join("tmp");
    tokio::fs::create_dir_all(&tmp).await?;
    Ok(tmp.join(Uuid::new_v4().to_string()))
}

/// Apaga o arquivo temporário se o upload falhar ou o cliente desistir (a future é largada no
/// meio). `keep` desarma depois do rename.
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

/// Põe o temporário no lugar do blob. Se o blob já existe (mesmo conteúdo, outra conta), descarta o
/// temporário em vez de regravar.
pub async fn commit_tmp(dir: &Path, tmp: &Path, hash: &str) -> io::Result<()> {
    let dest = blob_path(dir, hash);
    if tokio::fs::try_exists(&dest).await? {
        return tokio::fs::remove_file(tmp).await;
    }
    tokio::fs::create_dir_all(dest.parent().expect("blob tem pasta")).await?;
    tokio::fs::rename(tmp, &dest).await
}

/// Grava bytes já em memória (resultado de um job).
pub async fn store_bytes(dir: &Path, hash: &str, bytes: &[u8]) -> io::Result<()> {
    let tmp = new_tmp(dir).await?;
    let mut guard = TmpGuard::new(&tmp);
    tokio::fs::write(&tmp, bytes).await?;
    commit_tmp(dir, &tmp, hash).await?;
    guard.keep();
    Ok(())
}

pub async fn used_bytes(pool: &PgPool, owner: Uuid) -> Result<i64, sqlx::Error> {
    let (n,): (i64,) = sqlx::query_as("SELECT COALESCE(sum(size), 0)::bigint FROM samples WHERE owner_id = $1").bind(owner).fetch_one(pool).await?;
    Ok(n)
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

fn old_enough(meta: &std::fs::Metadata) -> bool {
    meta.modified().ok().and_then(|m| SystemTime::now().duration_since(m).ok()).is_some_and(|age| age > ORPHAN_GRACE)
}

/// Faxina: apaga blobs que nenhuma conta registra (contas apagadas, cota estourada no meio) e
/// temporários esquecidos por uma queda, sempre só os de mais de uma hora.
pub async fn cleanup(pool: &PgPool, dir: &Path) -> anyhow::Result<()> {
    let mut removed = 0u32;
    if let Ok(mut rd) = tokio::fs::read_dir(dir.join("tmp")).await {
        while let Some(e) = rd.next_entry().await? {
            if e.metadata().await.is_ok_and(|m| m.is_file() && old_enough(&m)) && tokio::fs::remove_file(e.path()).await.is_ok() {
                removed += 1;
            }
        }
    }
    if let Ok(mut shards) = tokio::fs::read_dir(dir.join("blobs")).await {
        while let Some(shard) = shards.next_entry().await? {
            let Ok(mut files) = tokio::fs::read_dir(shard.path()).await else { continue };
            while let Some(f) = files.next_entry().await? {
                let name = f.file_name().to_string_lossy().into_owned();
                if !valid_hash(&name) || !f.metadata().await.is_ok_and(|m| m.is_file() && old_enough(&m)) {
                    continue;
                }
                let (used,): (bool,) = sqlx::query_as("SELECT EXISTS (SELECT 1 FROM samples WHERE hash = $1)").bind(&name).fetch_one(pool).await?;
                if !used && tokio::fs::remove_file(f.path()).await.is_ok() {
                    removed += 1;
                }
            }
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
