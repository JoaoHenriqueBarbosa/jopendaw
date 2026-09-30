# Servidor: rotas, banco, armazenamento e jobs

> Para quem mexe no backend (`server/`, Rust com axum + SeaORM sobre Postgres): como o processo sobe (e por que dá para editá-lo sem reiniciar), cada rota com corpo, respostas e erros, o schema, o armazenamento dos áudios (disco ou S3/MinIO), a cota, a fila de tarefas e como testar e implantar.

Citações `arquivo:linha` valem para o estado de 30/09/2026 (commit `9a790a2` e a documentação).

## Visão geral

```
                      ┌──────────────────────────────── processo jopendaw-server ───────────────────────────────┐
 app Flutter ──HTTP──►│ axum Router  (routes/mod.rs)                                                            │
 (web via nginx,      │   ├─ contas: auth.rs, oauth.rs      (sqlx direto: users, sessions, magic_links, oauth_*)│
  Android direto)     │   ├─ projetos: routes/projects.rs   (SeaORM: projects)                                  │
                      │   ├─ documento: routes/docs.rs      (SQL direto: project_docs, JSONB versionado)        │
                      │   ├─ áudios: routes/samples.rs ───► storage::Store ──► disco (DATA_DIR/blobs) ou S3     │
                      │   └─ tarefas: routes/jobs.rs ◄──── worker tokio (spawn_blocking: audio.rs)              │
                      │ ServeDir do app/build/web (só se existir; desenvolvimento)                              │
                      └────────────┬───────────────────────────────────────────────────────────────────────────┘
                                   │ pool sqlx compartilhado com o SeaORM
                              Postgres 17                       jmail (email do magic link, HTTP)   OAuth Google/Discord
```

Em produção o app web fica num container nginx próprio (`app/nginx.conf.template`) que serve o build do Flutter e faz proxy de `/api/` para o servidor; o servidor sobe sozinho (o diretório estático não existe no container). O app Android fala direto com a API pública.

## Peças e responsabilidades

| Arquivo | Papel |
|---|---|
| `server/src/main.rs` | `AppState`, `setup()` (frio), `serve()` (quente), subcomando `migrate-blobs-to-s3`, `main` com e sem a feature `hot` |
| `server/src/config.rs` | `Config::from_env` (falha cedo se faltar segredo ou for fraco), `S3Config`, cliente OAuth |
| `server/src/db.rs` | `connect()`: pool de até 10 conexões (mínimo 1, timeout de aquisição 10 s) a partir de `DATABASE_URL` |
| `server/src/auth.rs` | magic link, código de acesso, JWT de acesso, refresh rotativo, `/api/me`, o extractor `Auth`, faxina |
| `server/src/oauth.rs` | entrar com Google e Discord (fluxo de código no servidor, PKCE do app) |
| `server/src/mail.rs` | envio de email pelo jmail (corpo no formato SendGrid v3) |
| `server/src/routes/mod.rs` | `ApiError`, mapeamento de erros e o `Router` com todas as rotas |
| `server/src/routes/projects.rs` | CRUD de projetos (SeaORM) |
| `server/src/routes/docs.rs` | documento versionado do projeto |
| `server/src/routes/samples.rs` | upload e download de áudios por SHA-256, `missing` |
| `server/src/routes/jobs.rs` | criar e consultar tarefas; o worker |
| `server/src/audio.rs` | leitura de WAV, codificação FLAC, áudio → MIDI (YIN) |
| `server/src/storage.rs` | `Store` (disco ou S3), registro e cota, faxina dos blobs |
| `server/src/entities/` | entidades SeaORM: `project`, `project_doc`, `sample`, `job` |
| `server/schema.sql`, `db/migrations/` | schema completo e scripts idempotentes de mudança |
| `server/Dockerfile`, `docker-compose.yml`, `hot.sh` | imagem, ambiente local, hot-patch |

## `main.rs`: setup frio e serve quente (hot-patch)

`./hot.sh` roda `dx serve --hot-patch --features hot` (dioxus-cli 0.7.10; o devserver do dx vai para a porta 8090 e a API fica na 8080). O Subsecond recompila só o que mudou e aplica no processo **sem reiniciá-lo**, em cerca de 1 s. Para isso o `main.rs` separa duas partes (`main.rs:49` a `main.rs:131`):

| Parte | O que faz | Sobrevive a um patch? |
|---|---|---|
| `setup()` (frio) | `dotenvy`, log, `Config::from_env`, `JOPENDAW_STATIC`, `PORT`, pool do banco, `Mailer`, `Store`, `requeue_orphans`, `spawn` do worker de jobs e da faxina horária | sim: roda uma vez |
| `serve(state, static_dir, port)` (quente) | monta o `Router`, o `ServeDir`/SPA, CORS, `Cache-Control`, `TraceLayer`, faz `bind` e `axum::serve` | não: cada patch derruba essa future e cria outra com o código novo (handlers, rotas, validação) |

Com a feature `hot`, `main` chama `dioxus_devtools::serve_subsecond_with_args((state, static_dir, port), ...)`; sem ela (produção) chama `serve` direto. Regras que decorrem disso:

- **Nada de `std::env::var` na parte quente.** O ambiente é lido no `setup` e viaja no `AppState` (`Config`), porque depois de um patch o `.env` não está mais visível para o código novo.
- **Mudou struct, enum ou assinatura** (inclusive `AppState` e `Config`), `Cargo.toml` ou o `setup`: o patch não serve; `r` no terminal do dx (rebuild completo) ou reiniciar o `./hot.sh`.
- **Não ponha `[profile.dev.package."*"] opt-level = 3`** no `Cargo.toml`: o patch aplica e o processo cai com "no reactor running" (comentário no `Cargo.toml` da raiz).
- `hot.sh` exige dioxus-cli 0.7.x em `~/.cargo/bin/dx` (o `dx` do Deno costuma vir antes no PATH; `DX` aponta outro binário) e faz `cd server` (é de lá que o `.env` é lido).
- A regra do projeto: o backend é sempre iterado pelo `./hot.sh` (em background, `--interactive false` sem TTY), nunca por `cargo run` reiniciado a cada mudança.

**`AppState`** (`main.rs:29`): `db` (SeaORM), `pool` (o mesmo pool, para SQL direto), `cfg: Arc<Config>`, `store: Arc<Store>`, `mailer: Arc<Mailer>`, `job_wake: Arc<Notify>` (acorda o worker). O SeaORM e o sqlx dividem o pool: o domínio usa o query builder; contas e o documento usam SQL direto. `FromRef<AppState> for DatabaseConnection` deixa os handlers do domínio pedirem só `State<DatabaseConnection>`.

**`serve()`** também: publica `app/build/web` na raiz com fallback para `index.html` (SPA) **se o diretório existir**; `CorsLayer::permissive()` (a autenticação é por cabeçalho `Authorization`, sem cookie, então outra origem não tem credencial para aproveitar); `Cache-Control: no-cache` nos arquivos estáticos quando a resposta não define um (`if_not_present`; o build do Flutter não tem hash no nome, e sem isso o navegador guardava `host.js` e `engine.wasm` velhos por tempo heurístico); `TraceLayer`.

**Subcomando `migrate-blobs-to-s3`** (`main.rs:133`): copia `DATA_DIR/blobs` para o bucket (idempotente) e sai, sem subir a API nem tocar no banco. Precisa de `DATA_DIR` e das variáveis `S3_*`. Uso: `cd server && cargo run -- migrate-blobs-to-s3` (ou o binário `jopendaw-server migrate-blobs-to-s3` no container).

**Faxina periódica** (uma vez por hora, dentro do `setup`): `auth::cleanup` (magic links vencidos há mais de 1 dia; sessões revogadas ou vencidas há mais de 30 dias), `oauth::cleanup` (estados e entradas vencidos há mais de 1 dia), `storage::cleanup` (blobs sem registro em nenhuma conta e temporários, só os de mais de 1 hora).

## Variáveis de ambiente

Lidas em `server/src/config.rs`, `db.rs` e `main.rs`. Modelo em `server/.env.example`. Obrigatórias marcadas.

| Variável | Padrão | Uso |
|---|---|---|
| `DATABASE_URL` | `postgres://jopendaw:jopendaw@localhost:5432/jopendaw` | banco |
| `PORT` | `8080` | porta HTTP |
| `JOPENDAW_STATIC` | `../app/build/web` | diretório do build web servido (ignorado se não existe) |
| `JWT_SECRET` (obrigatória) | | HS256, no mínimo 32 caracteres (`openssl rand -base64 48`) |
| `APP_BASE_URL` | `http://localhost:8080` | origem pública do app, sem barra final; vai no link do email e nos retornos do OAuth |
| `JMAIL_API_KEY` (obrigatória) | | chave do app jopendaw no jmail |
| `JMAIL_URL` | `http://127.0.0.1:8790` | base da API do jmail |
| `MAIL_FROM`, `MAIL_FROM_NAME` | `no-reply@jopendaw.local`, `jopendaw` | remetente |
| `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET` | ausentes | os dois ou nenhum; sem o par o botão do provedor some (`GET /api/auth/providers`) |
| `DISCORD_CLIENT_ID`, `DISCORD_CLIENT_SECRET` | ausentes | idem |
| `REVIEW_EMAIL`, `REVIEW_CODE` | ausentes | conta de demonstração por código de acesso (Play Store); os dois ou nenhum, código com 24+ caracteres |
| `DATA_DIR` | `./data` | raiz dos blobs (modo disco) e dos temporários de upload (nos dois modos) |
| `S3_ENDPOINT` | ausente = modo disco | ativa o S3; com ele, os três seguintes são obrigatórios |
| `S3_BUCKET`, `S3_ACCESS_KEY`, `S3_SECRET_KEY` | | |
| `S3_REGION` | `us-east-1` | |
| `S3_PATH_STYLE` | `true` | `endpoint/bucket/chave` (MinIO); `false` = `bucket.endpoint/chave` |
| `RUST_LOG` | `info,tower_http=info` | filtro de log |

## Contas e sessões (`auth.rs`, `oauth.rs`)

Sem senha. A conta é o email (único sem distinguir maiúsculas); provar a posse do email (magic link, provedor ou código de acesso) cria a conta se preciso e abre uma sessão.

Tokens (`auth.rs:31`): JWT de acesso HS256 de **15 min** (claims `sub` = usuário, `sid` = sessão, `iat`, `exp`; tolerância de 30 s); refresh token **opaco** (32 bytes aleatórios em base64url) de **30 dias**, rotativo (cada uso gera outro), teto absoluto de sessão de **90 dias**. Só o SHA-256 dos tokens vai para o banco. O extractor `Auth` valida o JWT **e** confere no banco que a sessão existe, não foi revogada, não venceu e que a conta não está bloqueada (`disabled_at`): sair vale na hora, não só quando o JWT vence.

Reuso de refresh: o hash anterior fica guardado (`previous_refresh_hash`). Apresentar um refresh já trocado, **dentro de 60 s** da troca, devolve `409` sem revogar (corrida entre abas do navegador, que dividem a sessão); depois disso é reuso (vazamento) e a sessão inteira é revogada.

Limites: magic link, 5 por email e 30 por IP por hora (`429`, contados na tabela, valem entre réplicas); início de OAuth, 60 por IP por hora. O IP vem de `X-Real-Ip` ou do primeiro `X-Forwarded-For` (atrás do proxy).

Formato dos tokens devolvidos (`Tokens`): `{"access_token", "token_type": "Bearer", "expires_in": 900, "refresh_token", "user": {"id", "email", "name"}}`.

## Rotas

Convenções: todas sob `/api`, exceto `/healthz`. JSON em `Content-Type: application/json`. Erros: `{"error": "mensagem em português"}` com o status (`ApiError`); **5xx nunca traz detalhe do banco** (o detalhe vai só para o log). Toda resposta da API leva `X-Content-Type-Options: nosniff` e `Cache-Control: no-store`, exceto o download de sample (que define o próprio). "Auth" = precisa de `Authorization: Bearer <acesso>` (sem ou com token inválido: `401 {"error": "não autenticado"}`). `DbErr` de chave duplicada vira `409`. As rotas de conta usam o extractor JSON padrão do axum: corpo malformado ou UUID inválido no caminho respondem com o erro padrão do axum (texto, não `{"error"}`) `(não confirmado)`.

### Saúde

| Método e caminho | Auth | Resposta |
|---|---|---|
| `GET /healthz` | não | `200 ok` (texto) |

### Contas (`auth.rs`)

| Método e caminho | Corpo | Sucesso | Erros |
|---|---|---|---|
| `POST /api/auth/magic-link` | `{"email"}` | `202` sem corpo (sempre igual, exista a conta ou não) | `400` email inválido; `429` limite; `500` se o email não saiu (a linha do link é desfeita) |
| `POST /api/auth/verify` | `{"token"}` | `200` `Tokens` | `401` link usado, vencido ou inexistente (uso único garantido por `UPDATE ... WHERE used_at IS NULL`); `403` conta bloqueada |
| `POST /api/auth/access-code` | `{"email", "code"}` | `200` `Tokens` | `401` para tudo (inclusive quando `REVIEW_*` não está configurado); comparação em tempo constante |
| `POST /api/auth/refresh` | `{"refresh_token"}` | `200` `Tokens` (novo refresh) | `401`; `409` rotação há menos de 60 s |
| `POST /api/auth/logout` | | `204` (revoga a sessão do JWT) | `401` |
| `POST /api/auth/logout-all` | | `204` (revoga todas as sessões) | `401` |
| `GET /api/me` | | `200` `{"user": {...}}` | `401` |
| `PATCH /api/me` | `{"name"?}` (até 80 caracteres, sem quebra de linha) | `200` `User` | `400`; `401` |
| `DELETE /api/me` | | `204`; apaga a conta e, em cascata, sessões, projetos, documentos, samples e tarefas | `401` |

O link do email é `{APP_BASE_URL}/entrar?token=<token>` (vale 15 min, uso único), que abre a rota `/entrar` do app.

### Entrar com Google e Discord (`oauth.rs`)

Fluxo de código conduzido no servidor, com prova PKCE do app: o app guarda um segredo (`verifier`), manda o SHA-256 dele em base64url (`challenge`, 43 caracteres) ao começar e o segredo em si ao terminar; quem intercepta o retorno sem o segredo não entra. O servidor usa também PKCE S256 com o provedor. Escopos: Google `openid email profile`, Discord `identify email`. Só entra com **email verificado** pelo provedor; a conta é o email (o mesmo email por Google, Discord e magic link cai na mesma conta); conta sem nome ganha o do provedor.

| Método e caminho | Corpo / query | Resposta |
|---|---|---|
| `GET /api/auth/providers` | | `200` `{"providers": ["google", "discord"]}` (só os configurados) |
| `GET /api/auth/oauth/{provider}/start` | `?platform=web\|android&challenge=` | redireciona (303) para o provedor. `404` provedor desconhecido ou sem credencial; `400` pedido inválido; `429` |
| `GET /api/auth/oauth/{provider}/callback` | `?code&state` ou `?error` | redireciona para o app: web `{APP_BASE_URL}/login?oauth=<entrada>` (ou `?erro=cancelado\|expirou\|sem-email\|falhou`); Android `tech.johnenrique.jopendaw://oauth?oauth=` (ou `?erro=`) |
| `POST /api/auth/oauth/finish` | `{"token", "verifier"}` | `200` `Tokens`; `401` entrada usada, vencida (2 min) ou sem a prova do app |
| `POST /api/auth/oauth/discord/app` | `{"challenge"}` | `200` `{"url": "discord://action/oauth2/authorize?..."}` (Android com o app do Discord instalado); `404` sem Discord configurado |
| `POST /api/auth/oauth/discord/app/finish` | `{"code", "state", "verifier"}` | `200` `Tokens`; `401`; `403` `"sem-email"`; `502` `"falhou"` |

Estado de cada entrada em andamento: 10 min, uso único (`oauth_states`); a entrada pronta que o app troca por sessão: 2 min, uso único (`oauth_grants`). Endereços de retorno a registrar nos provedores: `{APP_BASE_URL}/api/auth/oauth/google/callback`, `.../discord/callback` e, no Discord, também `discord-{DISCORD_CLIENT_ID}:/authorize/callback`.

### Projetos (`routes/projects.rs`)

Toda consulta filtra pelo dono; projeto alheio responde `404`, igual ao inexistente.

`Project` (JSON): `id` (uuid), `name`, `bpm`, `beats_per_bar`, `beat_unit`, `sample_rate`, `created_at`, `updated_at` (o dono nunca sai).

| Método e caminho | Corpo | Sucesso | Erros |
|---|---|---|---|
| `GET /api/projects` | | `200` lista, mais recente primeiro (`updated_at desc`) | `401` |
| `POST /api/projects` | `{"name", "bpm"?, "beats_per_bar"?, "beat_unit"?, "sample_rate"?}` | `201` `Project` | `400`; `401` |
| `GET /api/projects/{id}` | | `200` `Project` | `404`; `401` |
| `PATCH /api/projects/{id}` | `{"name"?, "bpm"?, "beats_per_bar"?, "beat_unit"?}` | `200` `Project` (atualiza `updated_at`) | `400`; `404`; `401` |
| `DELETE /api/projects/{id}` | | `204` | `404`; `401` |

Validação: `name` de 1 a 120 caracteres, sem caractere de controle (aparado); `bpm` de 20 a 999 (padrão 120); `beats_per_bar` de 1 a 32 (padrão 4); `beat_unit` em `1, 2, 4, 8, 16, 32` (padrão 4); `sample_rate` em `44100, 48000, 88200, 96000` (padrão 48000; **só na criação**, `PATCH` não o altera). Fórmula de compasso é validada em conjunto (o `PATCH` completa o que faltou com o valor atual). O banco repete essas regras em `CHECK`.

O app só usa `name`, `bpm` e `beats_per_bar` (o `createProject` manda apenas `name`).

### Documento do projeto (`routes/docs.rs`)

O documento é o JSON do app (esquema em [10 App Flutter](10-app-flutter.md)) guardado como **JSONB opaco**: o servidor só exige que seja um objeto. Concorrência otimista por versão; detalhes do protocolo em [12 Sincronização](12-sincronizacao.md).

| Método e caminho | Corpo | Sucesso | Erros |
|---|---|---|---|
| `GET /api/projects/{id}/doc` | | `200` `{"version": int, "doc": objeto\|null, "updated_at"}`; projeto sem documento devolve `version: 0`, `doc: null` e o `updated_at` do projeto | `404`; `401` |
| `PUT /api/projects/{id}/doc` | `{"base_version": int, "doc": objeto}` | `200` `{"version": nova, "updated_at"}` | `400` corpo inválido, `base_version` negativo, `doc` que não é objeto, ou caractere nulo (`\u0000`, que o jsonb não guarda); `404`; `401`; `409` versão base velha; `413` acima de 8 MB |

- `base_version = 0` é a primeira gravação (`INSERT ... ON CONFLICT DO NOTHING`); qualquer outro valor faz `UPDATE ... SET version = version + 1 WHERE version = <base>`. Sem linha afetada, é conflito.
- **`409`**: `{"error": "o projeto foi alterado em outro lugar; recarregue a versão do servidor", "version": <atual>, "doc": <atual>}`. O corpo já traz o documento vencedor para o app decidir sem outra ida ao servidor.
- A gravação do documento e o `updated_at` do projeto andam numa transação (ou os dois, ou nenhum): o `PUT` faz a lista de projetos subir.
- **Teto de 8 MB** para o corpo inteiro (o limite padrão de 2 MB do axum é desligado nesta rota, para o teto e a mensagem serem os da API).
- Não há histórico: o `UPDATE` substitui o documento; só a versão atual existe.

### Áudios (`routes/samples.rs`)

Endereçados pelo SHA-256 do conteúdo (hexadecimal minúsculo, 64 caracteres). O registro (`samples`) diz de quem é cada áudio e quanto a conta usa; o objeto em si é **um só por conteúdo**, mesmo com várias contas.

| Método e caminho | Corpo | Sucesso | Erros |
|---|---|---|---|
| `POST /api/samples/missing` | `{"hashes": [..]}` (até 2000) | `200` `{"missing": [..]}` os que a conta **não** tem, na ordem do pedido, sem repetir | `400` mais de 2000 ou hash inválido; `401` |
| `PUT /api/samples/{hash}` | bytes (`application/octet-stream`) | `204` (idempotente: se a conta já tem, não lê o corpo) | `400` hash inválido, corpo vazio, envio interrompido, ou o SHA-256 do corpo não confere com o da URL; `413` acima de 512 MB ou cota de 4 GB excedida; `401` |
| `GET /api/samples/{hash}` | | `200` bytes (`application/octet-stream`, `Content-Length`, `Cache-Control: private, max-age=31536000, immutable`) | `404` hash malformado, áudio que a conta não registrou, ou registro sem arquivo; `401` |

Detalhes do upload: em **streaming** para um temporário local (`DATA_DIR/tmp/<uuid>`), calculando o hash e o tamanho conforme os pedaços chegam; os tetos valem pelo que **realmente chega**, não pelo `Content-Length`, que o cliente pode mentir (o `Content-Length` declarado só antecipa a recusa). O corpo é sempre conferido contra o hash, mesmo que o objeto já exista (de outra conta): senão bastaria conhecer um hash para "ter" o áudio de alguém. Depois `Store::commit_tmp` (no S3: `HEAD`, e `PUT` só se não existir; em disco: `rename`) e `storage::register` (cota, ver abaixo). `TmpGuard` apaga o temporário se o envio falha ou o cliente desiste. O limite padrão do axum é desligado só nas rotas de upload.

Não existe rota para **apagar** um sample: só sai quando a conta é apagada (cascata). A mensagem de cota ("apague áudios que não usa mais") não tem, portanto, ação correspondente na API.

### Tarefas (`routes/jobs.rs`)

`Job` (JSON): `id`, `kind` (`flac` ou `audio_to_midi`), `status` (`queued`, `running`, `done`, `failed`), `progress` (0..1), `error` (string ou `null`), `result` (objeto ou `null`). `owner_id`, `sample_hash`, `params` e datas não saem.

| Método e caminho | Corpo | Sucesso | Erros |
|---|---|---|---|
| `POST /api/jobs` | `{"kind", "sample", "params"?}` | `202` `{"id", "status": "queued"}` | `400` `kind` (só `flac` ou `audio_to_midi`), hash inválido ou `params`; `404` sample que a conta não tem; `429` já há 10 tarefas em andamento (`queued` ou `running`) na conta; `401` |
| `GET /api/jobs/{id}` | | `200` `Job` | `404` (inclusive de outra conta); `401` |
| `GET /api/jobs` | | `200` lista das 50 mais recentes da conta | `401` |

`params` de `audio_to_midi` (normalizados na criação; para `flac` são descartados): `min_note_ms` (0..5000, padrão 60) e `rms_floor_db` (−120..0, padrão −45); fora da faixa: `400`.

`result`: `flac` → `{"sample": "<sha256 do FLAC>", "bytes": n}` (o FLAC entra no armazenamento da conta como qualquer áudio e **conta na cota**); `audio_to_midi` → `{"notes": [{"pitch", "start", "length", "velocity"}], "duration"}` com tempos em **segundos** do áudio inteiro, `pitch` 0..127, `velocity` 0,05..1.

## Entidades SeaORM (`server/src/entities/`)

| Entidade | Tabela | Notas |
|---|---|---|
| `project::Model` | `projects` | serializa para a API; `owner_id` com `#[serde(skip)]` |
| `project_doc::Model` | `project_docs` | só leitura pelo SeaORM; a escrita é SQL direto em `docs.rs` (o `UPDATE ... WHERE version` atômico) |
| `sample::Model` | `samples` | chave primária composta (`owner_id`, `hash`) |
| `job::Model` | `jobs` | o worker escreve por SQL direto; `sample_hash`, `params`, `owner_id` e datas não serializam |

As tabelas de conta (`users`, `sessions`, `magic_links`, `oauth_states`, `oauth_grants`) **não** têm entidade: `auth.rs` e `oauth.rs` usam SQL direto pelo sqlx. Toda entidade tem `Relation` vazio: as cascatas são do banco.

## Banco: `server/schema.sql` e `db/migrations/`

Não há migrations automáticas. Mudança de schema = editar `server/schema.sql` **e** escrever um script idempotente em `db/migrations/` para rodar à mão em produção. Primeira instalação:

```bash
docker-compose up -d db
docker exec -i jopendaw-pg psql -U jopendaw -d jopendaw < server/schema.sql
```

O compose não monta o `schema.sql` no `initdb` porque o colima não enxerga `/Volumes`. Fase 6 em banco existente: `docker exec -i jopendaw-pg psql -U jopendaw -d jopendaw < db/migrations/2026-09-30-fase6.sql` (o único script até agora; cria `project_docs`, `samples` e `jobs` com `IF NOT EXISTS`).

| Tabela | Colunas (resumo) | Regras |
|---|---|---|
| `users` | `id` uuid, `email`, `name` (`''`), `created_at`, `last_login_at`, `disabled_at` | índice único em `lower(email)` |
| `magic_links` | `id`, `email`, `token_hash` bytea único, `expires_at`, `used_at`, `ip`, `user_agent`, `created_at` | índices por (email, data) e (ip, data) para o limite |
| `oauth_states` | `state_hash` PK, `provider` (`google`/`discord`), `platform` (`web`/`android`/`discord-app`), `challenge`, `pkce_verifier`, `ip`, `expires_at` | |
| `oauth_grants` | `token_hash` PK, `provider`, `email`, `name`, `challenge`, `expires_at`, `used_at` | |
| `sessions` | `id`, `user_id` → users (cascade), `refresh_hash` único, `previous_refresh_hash`, `last_used_at`, `expires_at`, `revoked_at`, `ip`, `user_agent` | índice parcial no hash anterior |
| `projects` | `id`, `owner_id` → users (cascade), `name`, `bpm` (20..999, 120), `beats_per_bar` (1..32, 4), `beat_unit` (1,2,4,8,16,32; 4), `sample_rate` (44100, 48000, 88200, 96000; 48000), `created_at`, `updated_at` | índice (owner, `updated_at desc`) |
| `project_docs` | `project_id` PK → projects (cascade), `version` bigint, `doc` jsonb, `updated_at` | |
| `samples` | (`owner_id` → users cascade, `hash` `^[0-9a-f]{64}$`) PK, `size` bigint, `created_at` | índice por `hash` |
| `jobs` | `id`, `owner_id` → users (cascade), `kind` (`flac`/`audio_to_midi`), `sample_hash`, `params` jsonb, `status`, `progress` real, `error`, `result` jsonb, datas | índice parcial da fila (`queued`/`running`) |

Nota: o comentário que abre `project_docs` no `schema.sql` está truncado (começa em "a versão base for a atual..."); o script de migração traz o texto completo.

## Armazenamento dos áudios (`storage.rs`)

Chave do objeto: `blobs/<2 primeiros hex>/<hash>`, em disco (`DATA_DIR`) ou num bucket S3 compatível (produção: MinIO). O nome só é montado a partir de hash validado (`valid_hash`: 64 caracteres hex minúsculos), o que impede `..` e barras.

| Operação (`Store`) | Disco | S3 |
|---|---|---|
| `new_tmp` | `DATA_DIR/tmp/<uuid>` (nos dois modos) | idem |
| `exists` | `try_exists` | `HEAD` assinado |
| `commit_tmp` | `rename` do temporário (mesmo volume). Se já existe, descarta o temporário | `PUT` do arquivo lido em streaming, `Content-Length` explícito (o S3 não aceita chunked); se já existe, pula o `PUT` |
| `store_bytes` | temporário + `commit_tmp` (usado pelo job de FLAC) | idem |
| `open` (`GET` em streaming) e `read` (para a memória, teto de 512 MB) | arquivo | `GET` assinado |
| `delete`, `list` | `read_dir` dos shards | `DELETE`; `ListObjectsV2` paginado com prefixo `blobs/` |
| `import_from_disk` | (origem) | copia `DATA_DIR/blobs` para o bucket, pulando o que já existe (base do `migrate-blobs-to-s3`) |

Nunca existe blob pela metade: em disco a escrita é temporário + `rename`; no S3 o objeto só aparece depois do `PUT` completo. As URLs assinadas (`rusty-s3`) valem 5 min e são usadas na hora; HEAD/DELETE/listagem têm timeout de 60 s, `PUT`/`GET` de blobs não têm teto de tempo total.

**Modo pelo ambiente:** com `S3_ENDPOINT` definido, S3; senão disco. Em produção o `Dockerfile` avisa: com S3, `/data` só guarda temporários (não precisa de volume persistente); sem `S3_ENDPOINT` os áudios moram em `/data` e o volume é **obrigatório** (sem ele os áudios somem a cada deploy). Local: `docker-compose up -d minio minio-init` (imagem `chainguard/minio`; API em :9000, console em :9001, credenciais só de desenvolvimento `jopendaw` / `jopendaw-minio-dev`, bucket `jopendaw` criado pelo `minio-init`).

**Migração disco → S3:** `migrate-blobs-to-s3` (idempotente, pode repetir). Registra "copiados" e "já existiam".

### Cota

- Teto de **512 MB por arquivo** (`MAX_SAMPLE_BYTES`) e **4 GB por conta** (`QUOTA_BYTES`), somando o `size` de `samples` da conta. Somam os áudios enviados e os FLACs gerados por job.
- `storage::register` serializa por conta com um **advisory lock** transacional (`pg_advisory_xact_lock(hashtextextended(owner, 0))`): sem ele, dois uploads de 3 GB conferem "cabe" ao mesmo tempo e passam de 4 GB. Áudio já registrado não conta duas vezes. Se passar da cota, `413`.
- O upload confere a cota antes (com o `Content-Length` declarado) e durante (com o que chega); a conferência final é a do `register`.

### Faxina dos blobs

`storage::cleanup` (a cada hora): apaga blobs **sem registro** em `samples` de nenhuma conta (conta apagada, cota estourada no meio de um upload) e temporários esquecidos, só os **modificados há mais de 1 hora** (`ORPHAN_GRACE`): dá tempo de um upload ou job terminar de registrar o que acabou de gravar. Como cada conta só registra o que enviou, um blob compartilhado só é apagado quando **nenhuma** conta o registra.

## Fila de tarefas e `audio.rs`

**Fila:** a tabela `jobs`. Um worker tokio criado no `setup` (frio, então sobrevive aos patches) faz o laço: espera uma vaga (`Semaphore`, no máximo **2 tarefas ao mesmo tempo**), pega a mais antiga `queued` com `UPDATE ... WHERE id = (SELECT ... FOR UPDATE SKIP LOCKED LIMIT 1)` (vira `running`), roda o trabalho em `tokio::task::spawn_blocking` e grava o resultado. Acorda na hora com `POST /api/jobs` (`job_wake`) e, por garantia, a cada 2 s. Enquanto a thread trabalha, o progresso vai para o banco duas vezes por segundo. Falha vira `failed` com a mensagem (o pânico da thread vira "erro interno"). No boot, `requeue_orphans` devolve à fila o que estava `running` quando o processo caiu.

Áudio de entrada: lido do armazenamento inteiro para a memória antes da thread (a decodificação é síncrona). **Só WAV** (`audio::decode_wav`): PCM inteiro de 16, 24 ou 32 bits ou float de 32 bits (inclusive `WAVE_FORMAT_EXTENSIBLE`), mono ou estéreo, taxa até 655 350 Hz. O resto (8 bits, 64 bits, 3+ canais, MP3, OGG...) falha com **"formato não suportado"**; `data` vazio, "áudio vazio". Internamente vira inteiros de 24 bits.

- **`flac`** (`audio::encode_flac`): FLAC de 24 bits em Rust puro (`flacenc`, sem libFLAC), com o cabeçalho corrigido no fim (mínimo do bloco = máximo, para decodificadores estritos como o symphonia do Android aceitarem). Progresso 0,1 depois de decodificar. O resultado entra no armazenamento pelo hash e conta na cota. **Nada no app pede esta tarefa hoje.**
- **`audio_to_midi`** (`audio::audio_to_midi`): transcrição de áudio **monofônico** em notas, pelo detector de altura **YIN**:
  1. mistura em mono; taxas acima de 30 kHz são reduzidas por média de blocos (a janela de 2048 quadros continua cobrindo 50 Hz);
  2. quadros de 2048 amostras com passo de 512; quadro abaixo do piso de energia (`rms_floor_db`) é silêncio e nem gasta o YIN;
  3. YIN por quadro (diferença, normalização cumulativa, primeiro mínimo abaixo de 0,15, interpolação parabólica), faixa de 50 Hz a 2 kHz; altura em semitons MIDI fracionários;
  4. mediana de 5 quadros sobre as alturas (tira saltos de oitava de um quadro só);
  5. segmentação: silêncio fecha a nota; uma mudança de altura de 0,7 semitom ou mais por 3 quadros seguidos abre outra nota; quadro com energia mas sem altura clara continua a nota aberta;
  6. descarta notas mais curtas que `min_note_ms`; `pitch` é a mediana arredondada, `start` e `length` em segundos, `velocity` = do piso a −6 dBFS mapeado em 0..1, nunca abaixo de 0,05 (zero é note-off em MIDI).

## Testes

- **Unitários** (sem banco): `audio.rs` (YIN em senoides, ruído e silêncio, segmentação, vibrato que não divide, parâmetros, taxa alta, WAV de 16/24/32 e float, formato não suportado, FLAC ida e volta sem perda), `storage.rs` (hash válido e SHA-256 conhecido), `oauth.rs` (PKCE do RFC 7636, só email verificado).
- **De rota** (`server/src/routes/tests.rs`), contra um Postgres de verdade. Precisam de `TEST_DATABASE_URL` apontando para um banco **à parte** com o `schema.sql` (nunca o de desenvolvimento: os testes criam contas e tarefas). Sem a variável cada teste se declara pulado e passa.

```bash
docker exec jopendaw-pg psql -U jopendaw -d postgres -c "CREATE DATABASE jopendaw_test"
docker exec -i jopendaw-pg psql -U jopendaw -d jopendaw_test < server/schema.sql
TEST_DATABASE_URL=postgres://jopendaw:jopendaw@localhost:5432/jopendaw_test cargo test -p jopendaw-server

# os mesmos testes contra o S3 (MinIO local: docker-compose up -d minio minio-init)
S3_ENDPOINT=http://localhost:9000 S3_BUCKET=jopendaw S3_ACCESS_KEY=jopendaw S3_SECRET_KEY=jopendaw-minio-dev \
  TEST_DATABASE_URL=... cargo test -p jopendaw-server
```

Cobertura das rotas: documento versionado (409 com o documento, entradas inválidas, alheio 404, gravações simultâneas: só uma vence, 8 MB, ~3 MB passa), samples (idas e voltas, hash que não confere, idempotência, `missing`, isolamento entre contas, limites de tamanho e cota), faxina (só o que não tem registro), operações básicas do armazenamento, temporário não fica para trás, migração disco → S3, tarefas (FLAC, áudio → MIDI, formato não suportado, validações, dono, limite de 10, órfão volta para a fila). O teste cria os usuários e sessões direto no banco e emite o JWT com `auth::issue_access`; todos os testes do processo dividem o mesmo `DATA_DIR` temporário (cada um sobe o próprio worker). **Não há teste de rota para a parte de contas** (`auth.rs`, `oauth.rs`): só as funções puras acima. Rodar o servidor de verdade é o teste de uso: `./hot.sh`, login pelo código de acesso da conta de revisão (`REVIEW_EMAIL`/`REVIEW_CODE` do `server/.env`).

Verificações do repositório: `cargo fmt --all --check` e `cargo clippy -p jopendaw-server --all-targets -- -D warnings` (rustfmt com `max_width` 160).

## Docker, compose e deploy

**`server/Dockerfile`** (contexto: a **raiz do repositório**; `docker build -f server/Dockerfile .`): estágio `rust:1-bookworm` compila com `cargo build --profile server -p jopendaw-server` (o perfil `server` do `Cargo.toml` raiz herda o `release` com `panic = "unwind"`: um pânico num handler do axum derruba só aquele pedido; com `abort` levaria o processo junto). As dependências entram numa camada própria (compila com um `main.rs` vazio antes de copiar `server/src`) para o cache sobreviver a mudanças no código. Estágio final `debian:bookworm-slim` com `ca-certificates` e `libssl3`, usuário de sistema `jopendaw` sem shell (um bug no servidor não vira root no host), `ENV PORT=8080 DATA_DIR=/data`, `VOLUME /data`, `EXPOSE 8080`, `CMD ["jopendaw-server"]`. O `schema.sql` é copiado para `/app/schema.sql`, mas **o servidor não o aplica sozinho**.

**`docker-compose.yml`**: `db` (Postgres 17, `jopendaw-pg`, porta 5432), `minio` + `minio-init` (S3 local), `api` (build do Dockerfile, porta 8080, `S3_*` apontando para o MinIO, `JMAIL_URL` para o jmail do host, `APP_BASE_URL=http://localhost:8081`), `web` (build de `app/`, nginx em 8081 com `JOPENDAW_API_HOST=api:8080`). `docker-compose up --build` sobe tudo. Segredos do compose são só de desenvolvimento; `JMAIL_API_KEY`, `GOOGLE_*` e `DISCORD_*` vêm do ambiente do host.

**nginx** (`app/nginx.conf.template`): gzip, cabeçalhos de segurança e CSP (o Flutter/CanvasKit carrega o motor do gstatic e compila WebAssembly), `proxy_pass` de `/api/` para `${JOPENDAW_API_HOST}` com `proxy_read_timeout 300s`, `/healthz`, `manifest.json`, `sw.js` sem cache, arquivos do build revalidados a cada carga (`expires -1`; o Flutter não põe hash no nome), `/entrar` e `/login` sem `Referer` e sem cache (o token vai na URL), `/privacidade` e `/termos` estáticos, e fallback de SPA para `index.html`. Há um `location = /api/ws` de WebSocket, "quando existir": o servidor **não tem** rota `/api/ws` hoje.

**Produção:** o domínio previsto é `jopendaw.johnenrique.tech` (a URL está fixa em `app/lib/api/client.dart`, no manifest Android e no `assetlinks.json`). Os segredos vêm do Dokploy (comentário do compose) e o deploy segue o processo da VPS do dono (build da imagem, push para o registry próprio, acionamento no Dokploy). O jopendaw ainda não tem receita de deploy escrita no repositório, e as credenciais do MinIO da VPS ainda estavam pendentes nas notas do projeto: `(não confirmado se está em produção)`. Não mexa na VPS sem o dono.

## Decisões e por quê

- **SeaORM para o domínio, sqlx direto para contas e para o documento.** O query builder serve ao CRUD; contas precisam de `UPDATE ... RETURNING` atômicos e de `FOR UPDATE`, e o documento, do `UPDATE ... WHERE version = $n` numa transação.
- **Concorrência otimista, não bloqueio.** Vários aparelhos editam offline; ninguém segura trava. O 409 devolve o documento vencedor para o app decidir.
- **Endereçamento por conteúdo.** O SHA-256 dá deduplicação, idempotência do upload, cache imutável no navegador e conferência de integridade; a prova do conteúdo no `PUT` impede "ter" o áudio alheio só sabendo o hash.
- **Erros sem detalhe do banco** no 5xx; detalhe só no log.
- **Perfil `server` com `unwind`.** Um handler que entra em pânico não derruba o processo.
- **`setup` frio, `serve` quente.** O hot-patch precisa de um lugar estável para o estado (pool, worker, faxina) e de um lugar recriável para o que se edita.
- **Cache-Control `no-cache` nos estáticos** no servidor de desenvolvimento para não rodar o app novo com o `host.js` ou o wasm velhos.

## Armadilhas conhecidas

- **`server/Dockerfile` provavelmente não compila mais.** Ele copia só `Cargo.toml`, `Cargo.lock` e `server/Cargo.toml`, mas o workspace agora lista também `engine`, `engine/wasm` e `engine/android` como membros (desde as fases 1 e 5): o cargo exige o manifesto de todo membro e falharia com "failed to load manifest for workspace member". O `.dockerignore` da raiz exclui só `target/`, `app/` e `dumps/`. `(não confirmado: não rodei o build; deduzido da leitura)`.
- **nginx sem `client_max_body_size`.** O padrão do nginx é 1 MB; o documento pode ter até 8 MB e os áudios até 512 MB, então atrás do `app/nginx.conf.template` um `PUT` maior que 1 MB deveria receber `413` do próprio nginx antes de chegar à API. `(não confirmado em produção; se houver outro proxy na frente, como o Traefik do Dokploy, a regra dele também vale)`.
- **Sem rota para apagar áudio.** A cota de 4 GB só se libera apagando a conta; a mensagem do erro sugere o contrário.
- **Uma instância só.** `requeue_orphans` no boot devolve **todas** as tarefas `running` à fila, inclusive as que outra instância estaria rodando; o limite de 2 tarefas simultâneas é por processo. O desenho pressupõe um único processo.
- **Áudio → MIDI só aceita WAV** e o app manda o arquivo original importado: um clipe de MP3 falha com "formato não suportado".
- **Leitura do áudio inteiro na memória** (`Store::read`) nos jobs: até 512 MB por tarefa, 2 tarefas ao mesmo tempo.
- **`requeue` e testes.** Os testes de rota dividem banco e `DATA_DIR`; `requeue(pool, Some(owner))` existe para não mexer nas tarefas alheias.
- **`/README.md` da raiz é uma cópia antiga do `CLAUDE.md`** (diz que `entities/` "hoje só tem `project`"); vale o `CLAUDE.md`.
- **Mudou a assinatura ou o `AppState`?** O hot-patch não aplica: reinicie o `./hot.sh` (ver acima).
