-- Fase 6 (documento do projeto, samples, jobs). Idempotente: pode rodar mais de uma vez.
-- docker exec -i jopendaw-pg psql -U jopendaw -d jopendaw < db/migrations/2026-09-30-fase6.sql

-- O documento do projeto (faixas, clipes, mixagem) como um JSONB versionado: o app só grava se
-- a versão base for a atual (concorrência otimista, 409 senão).
CREATE TABLE IF NOT EXISTS project_docs (
  project_id UUID        PRIMARY KEY REFERENCES projects (id) ON DELETE CASCADE,
  version    BIGINT      NOT NULL,
  doc        JSONB,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Registro dos áudios de cada conta; os bytes ficam em DATA_DIR/blobs/<2 hex>/<sha256>, dividi-
-- dos entre contas que mandaram o mesmo conteúdo. `size` alimenta a cota.
CREATE TABLE IF NOT EXISTS samples (
  owner_id   UUID        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  hash       TEXT        NOT NULL CHECK (hash ~ '^[0-9a-f]{64}$'),
  size       BIGINT      NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (owner_id, hash)
);
CREATE INDEX IF NOT EXISTS samples_hash ON samples (hash);

-- Fila de tarefas pesadas (conversão para FLAC, áudio para MIDI), consumida pelo worker interno.
CREATE TABLE IF NOT EXISTS jobs (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id    UUID        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  kind        TEXT        NOT NULL CHECK (kind IN ('flac', 'audio_to_midi')),
  sample_hash TEXT        NOT NULL,
  params      JSONB,
  status      TEXT        NOT NULL DEFAULT 'queued' CHECK (status IN ('queued', 'running', 'done', 'failed')),
  progress    REAL        NOT NULL DEFAULT 0,
  error       TEXT,
  result      JSONB,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS jobs_owner_created ON jobs (owner_id, created_at DESC);
CREATE INDEX IF NOT EXISTS jobs_queue ON jobs (created_at) WHERE status IN ('queued', 'running');
