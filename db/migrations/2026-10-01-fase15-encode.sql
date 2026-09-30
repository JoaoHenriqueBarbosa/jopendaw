-- Fase 15 (C): tarefa encode_audio (exportação em FLAC e MP3 pelo servidor). Idempotente.
-- docker exec -i jopendaw-pg psql -U jopendaw -d jopendaw < db/migrations/2026-10-01-fase15-encode.sql
ALTER TABLE jobs DROP CONSTRAINT IF EXISTS jobs_kind_check;
ALTER TABLE jobs ADD CONSTRAINT jobs_kind_check CHECK (kind IN ('flac', 'audio_to_midi', 'encode_audio'));
