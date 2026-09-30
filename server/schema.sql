-- Schema do jopendaw em Postgres.
--
-- Contas são só email, com entrada por magic link, Google ou Discord (o email verificado do
-- provedor é a conta). O domínio do DAW (projetos, e depois faixas, clipes, mixagem) é da conta
-- e é lido pelo SeaORM (server/src/entities). Não há migrations automáticas: mudança de schema é
-- editar este arquivo e escrever um script idempotente em db/migrations/ para rodar à mão em
-- produção.

-- ---------------------------------------------------------------- contas
CREATE TABLE users (
  id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  email         TEXT        NOT NULL,
  name          TEXT        NOT NULL DEFAULT '',
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_login_at TIMESTAMPTZ,
  -- bloqueada: não entra e as sessões não valem
  disabled_at   TIMESTAMPTZ
);
CREATE UNIQUE INDEX users_email_unq ON users (lower(email));

-- Magic link: só o hash do token vai para o banco. Uso único, vida curta.
CREATE TABLE magic_links (
  id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  email      TEXT        NOT NULL,
  token_hash BYTEA       NOT NULL UNIQUE,
  expires_at TIMESTAMPTZ NOT NULL,
  used_at    TIMESTAMPTZ,
  ip         TEXT,
  user_agent TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX magic_links_email_created ON magic_links (lower(email), created_at DESC);
CREATE INDEX magic_links_ip_created    ON magic_links (ip, created_at DESC);

-- Entrar com Google e com Discord (oauth.rs): o estado de cada entrada em andamento (10 min) e a
-- entrada pronta que o app troca por uma sessão (2 min), as duas de uso único e presas ao desafio
-- do app (SHA-256 de um segredo dele).
CREATE TABLE oauth_states (
  state_hash    BYTEA       PRIMARY KEY,
  provider      TEXT        NOT NULL CHECK (provider IN ('google', 'discord')),
  platform      TEXT        NOT NULL CHECK (platform IN ('web', 'android', 'discord-app')),
  challenge     TEXT        NOT NULL,
  pkce_verifier TEXT        NOT NULL,
  ip            TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at    TIMESTAMPTZ NOT NULL
);
CREATE INDEX oauth_states_ip_created ON oauth_states (ip, created_at DESC);

CREATE TABLE oauth_grants (
  token_hash BYTEA       PRIMARY KEY,
  provider   TEXT        NOT NULL CHECK (provider IN ('google', 'discord')),
  email      TEXT        NOT NULL,
  name       TEXT        NOT NULL DEFAULT '',
  challenge  TEXT        NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at TIMESTAMPTZ NOT NULL,
  used_at    TIMESTAMPTZ
);

-- Sessão = um refresh token opaco (hash) que gira a cada uso. O hash anterior fica guardado
-- para detectar reuso: um token velho apresentado de novo vazou, e a sessão inteira cai.
CREATE TABLE sessions (
  id                    UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id               UUID        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  refresh_hash          BYTEA       NOT NULL UNIQUE,
  previous_refresh_hash BYTEA,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_used_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at            TIMESTAMPTZ NOT NULL,
  revoked_at            TIMESTAMPTZ,
  ip                    TEXT,
  user_agent            TEXT
);
CREATE INDEX sessions_user ON sessions (user_id);
CREATE INDEX sessions_previous_hash ON sessions (previous_refresh_hash) WHERE previous_refresh_hash IS NOT NULL;

-- ---------------------------------------------------------------- DAW
-- Um projeto: a sessão de uma música. Faixas, clipes e mixagem entram como tabelas filhas.
CREATE TABLE projects (
  id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id      UUID        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  name          TEXT        NOT NULL,
  bpm           INTEGER     NOT NULL DEFAULT 120 CHECK (bpm BETWEEN 20 AND 999),
  beats_per_bar INTEGER     NOT NULL DEFAULT 4   CHECK (beats_per_bar BETWEEN 1 AND 32),
  beat_unit     INTEGER     NOT NULL DEFAULT 4   CHECK (beat_unit IN (1, 2, 4, 8, 16, 32)),
  sample_rate   INTEGER     NOT NULL DEFAULT 48000 CHECK (sample_rate IN (44100, 48000, 88200, 96000)),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX projects_owner_updated ON projects (owner_id, updated_at DESC);

-- ---------------------------------------------------------------- fase 6: documento, samples e jobs
-- Documento do projeto (JSONB) com versão: o PUT só vale se a versão base enviada for a atual
-- (concorrência otimista, 409 com o documento do servidor senão). `doc` é NULL até o primeiro envio.
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
