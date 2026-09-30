# Servidor: rotas, banco, armazenamento e jobs

> Para quem mexe no backend (`server/`, Rust com axum + SeaORM sobre Postgres): como o processo sobe (e por que dá para editá-lo sem reiniciar), cada rota com corpo, respostas e erros, o schema, o armazenamento dos áudios (disco ou S3/MinIO), a cota, a fila de tarefas e como testar e implantar.

Citações `arquivo:linha` valem para o estado de 30/09/2026 (commit `9a790a2`); as rotas de cota (`GET /api/samples`, `DELETE /api/samples/{hash}`, `POST /api/samples/cleanup`) e a decodificação em vários formatos (fase 9) foram descritas a partir de `f0d9879` (integradas em `f25935f`; a última correção do app é `15670b7`), sem números de linha. De lá até `677f064` nenhum arquivo de `server/src` mudou; as únicas mudanças de servidor e de implantação foram `server/Dockerfile`, `.dockerignore` e `app/nginx.conf.template` (commit `0c0593e`, descrito em "Docker, compose e deploy"). As mudanças da fase 11 no servidor (commit `94731e8`, integradas em `601ad49`: apagar, limpar, criar tarefa e gravar documento sob a mesma trava por hash; folga de 1 h também no `DELETE` por item; `422` no `PUT` do documento; trecho `start`/`end` no áudio → MIDI; Opus com mensagem própria; `rms_floor_db` até −10; `QUOTA_MESSAGE` única) foram descritas a partir do código de `601ad49`, sem números de linha; os trechos mais antigos que ainda dizem o contrário estão marcados como "resolvido em `94731e8`". As mudanças da fase 13 (B) (commit `1180152`, integradas em `c5425a0`: `409` antes de `422` no `PUT` do documento, uma conexão só do pool nas chamadas que seguram a trava, `skipped_in_use` e `skipped_job` no `cleanup`, `end` obrigatório com `start` maior que 0, `OpusHead` achado em qualquer posição do Ogg) foram descritas a partir do código de `c5425a0`, sem números de linha, e os trechos antigos que diziam o contrário estão marcados como "resolvido em `1180152`".

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
| `server/src/routes/samples.rs` | upload e download de áudios por SHA-256, `missing`; listar (`GET /api/samples`), apagar (`DELETE /api/samples/{hash}`) e limpar (`POST /api/samples/cleanup`), com o cálculo de "em uso" (`references`, `collect_hashes`) |
| `server/src/routes/jobs.rs` | criar e consultar tarefas; o worker |
| `server/src/audio.rs` | decodificação (`decode_audio_span`: WAV próprio + symphonia para FLAC, MP3, OGG Vorbis, AAC/M4A, ALAC; só do trecho `Span` pedido), codificação FLAC, áudio → MIDI (YIN) |
| `server/src/encode.rs` | exportação compactada (fase 15 C): `Format`, `Meta`, `clean_text`, `suggested_name`, `encode_cancelable` (WAV lido → FLAC ou MP3; recebe uma função `cancel` que o MP3 pergunta a cada segundo de áudio; `encode` é só um atalho sob `#[cfg(test)]`), `id3v24`, `with_vorbis_comment`; puro e síncrono, testado sem banco (`encode_tests.rs`) |
| `server/src/storage.rs` | `Store` (disco ou S3), registro e cota, `QUOTA_MESSAGE`, trava por hash (`lock_hash`, `lock_hashes`), faxina dos blobs |
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
| `PUT /api/projects/{id}/doc` | `{"base_version": int, "doc": objeto}` | `200` `{"version": nova, "updated_at"}` | `400` corpo inválido, `base_version` negativo, `doc` que não é objeto, ou caractere nulo (`\u0000`, que o jsonb não guarda); `404`; `401`; `409` versão base velha; `413` acima de 8 MB; `422` o documento passa a citar um áudio da conta que foi apagado neste instante (corpo com `missing`) |

- `base_version = 0` é a primeira gravação (`INSERT ... ON CONFLICT DO NOTHING`); qualquer outro valor faz `UPDATE ... SET version = version + 1 WHERE version = <base>`. Sem linha afetada, é conflito.
- **`409`**: `{"error": "o projeto foi alterado em outro lugar; recarregue a versão do servidor", "version": <atual>, "doc": <atual>}`. O corpo já traz o documento vencedor para o app decidir sem outra ida ao servidor.
- **`422`** (fase 11, `94731e8`): `{"error": "um áudio citado pelo projeto foi apagado neste instante; envie o áudio de novo e tente salvar outra vez", "missing": ["<hash>", …]}`. Nada é gravado e a versão não anda. Antes de gravar, o `PUT` calcula os hashes que o documento novo cita e o guardado não citava (`newly_cited`, só os que a conta tem registrados), toma a trava por hash de todos, em ordem fixa (`storage::lock_hashes`, valem até o `commit`), e confere que continuam em `samples`. Um apagar concorrente ou espera este `PUT` (e depois o vê citando, respondendo `409 ... projects`) ou já terminou (e o `PUT` responde `422`). Hash que a conta nunca registrou não entra: o servidor não trata citação de áudio inexistente como erro (o app sobe os áudios antes do documento). A versão vem **antes** (resolvido em `1180152`; até então o `422` vinha na frente do `409`): o `PUT` tenta gravar primeiro e só depois confere os áudios, então um `PUT` de versão-base velha recebe `409` com o documento vencedor mesmo que cite um áudio sumido (o `422` só aparece com a versão certa, e desfaz a gravação). Tudo roda na conexão da transação que segura as travas (ver "Corrida com o documento e com tarefas"). O app trata o `422`: reenvia os áudios de `missing` e tenta de novo (até 3 vezes; `SyncService._push`).
- A gravação do documento e o `updated_at` do projeto andam numa transação (ou os dois, ou nenhum): o `PUT` faz a lista de projetos subir.
- **Teto de 8 MB** para o corpo inteiro (o limite padrão de 2 MB do axum é desligado nesta rota, para o teto e a mensagem serem os da API).
- Não há histórico: o `UPDATE` substitui o documento; só a versão atual existe.

### Áudios (`routes/samples.rs`)

Endereçados pelo SHA-256 do conteúdo (hexadecimal minúsculo, 64 caracteres). O registro (`samples`) diz de quem é cada áudio e quanto a conta usa; o objeto em si é **um só por conteúdo**, mesmo com várias contas.

| Método e caminho | Corpo | Sucesso | Erros |
|---|---|---|---|
| `POST /api/samples/missing` | `{"hashes": [..]}` (até 2000) | `200` `{"missing": [..]}` os que a conta **não** tem, na ordem do pedido, sem repetir | `400` mais de 2000 ou hash inválido; `401` |
| `PUT /api/samples/{hash}` | bytes (`application/octet-stream`) | `204` (idempotente: se a conta já tem, não lê o corpo) | `400` hash inválido, corpo vazio, envio interrompido, ou o SHA-256 do corpo não confere com o da URL; `413` acima de 512 MB (`arquivo grande demais (máximo de 512 MB)`) ou cota de 4 GB excedida (`storage::QUOTA_MESSAGE`, texto abaixo); `401` |
| `GET /api/samples/{hash}` | | `200` bytes (`application/octet-stream`, `Content-Length`, `Cache-Control: private, max-age=31536000, immutable`) | `404` hash malformado, áudio que a conta não registrou, ou registro sem arquivo; `401` |
| `GET /api/samples` | | `200` a conta de áudios (formato abaixo) | `401` |
| `DELETE /api/samples/{hash}?force=true` | | `200` `{"freed_bytes": n}` (bytes que voltam à cota da conta) | `404` hash malformado ou áudio que a conta não registrou; `409` em uso (corpo com `projects`), com tarefa ativa ou enviado há pouco (corpo com `recent: true`; `force=true` insiste só nesse caso); `401` |
| `POST /api/samples/cleanup` | (o app manda `{}`; o corpo é ignorado) | `200` `{"removed": n, "freed_bytes": n, "skipped_recent": n, "skipped_in_use": n, "skipped_job": n}` | `401` |

**`GET /api/samples`** devolve:

```json
{"quota_bytes": 4294967296, "used_bytes": 123, "unused_bytes": 45, "unused_count": 2,
 "samples": [{"hash": "…", "name": "voz.wav" | null, "size": 123, "created_at": "…",
              "unused": false, "recent": false, "project_count": 1, "projects": [{"id": "<uuid>", "name": "Meu projeto"}]}]}
```

`samples` vem ordenada por `size` decrescente e depois por `hash`. `used_bytes` é a soma dos `size` listados; `unused_*` só conta os que nenhum documento cita. `recent` (fase 11) é `true` quando `created_at` tem menos de `CLEANUP_GRACE_SECS` (3600 s), calculado na hora da listagem para **todos** os áudios (com ou sem uso); a tela `Conta` só o usa nos sem uso. `name` é o nome de arquivo do mapa `samples` do documento (o primeiro que aparecer; `null` se nenhum documento o guarda, como um FLAC gerado por job). `projects` só traz projetos que têm linha em `project_docs` (projeto que nunca enviou documento não cita nada).

**`DELETE /api/samples/{hash}`** na ordem: hash inválido → `404`; não registrado na conta → `404`; citado por algum documento da conta → `409` com o corpo `{"error": "este áudio ainda é usado em projetos; tire-o de lá antes de apagar", "projects": [{"id", "name"}]}`; tarefa `queued`/`running` da conta com esse `sample_hash` → `409 {"error": "há uma tarefa em andamento com este áudio; tente de novo quando ela terminar"}`; enviado há menos de `CLEANUP_GRACE_SECS` (1 h) e sem `force=true` → `409 {"error": "áudio enviado há pouco; o projeto que o usa pode não ter sincronizado ainda. Espere ou confirme para apagar mesmo assim", "recent": true}` (o documento que o cita pode não ter sincronizado; a tela Conta marca `sem uso · recém-enviado` pelo campo `recent` da lista e pergunta antes de insistir; o app distingue este `409` dos outros por `recent == true`); senão apaga e responde `freed_bytes` = `size` do registro. `?force=true` (`DeleteQuery.force`, padrão `false`) desliga **só** a folga de 1 h: documento que cita e tarefa ativa continuam recusando com `409`. **Todas** essas conferências (documentos, tarefa, folga) são feitas por `remove_if_unused` **sob a trava do hash**, imediatamente antes do `DELETE`, e não antes dela.

**`POST /api/samples/cleanup`** calcula os candidatos com uma leitura dos documentos e então apaga, um a um (cada um **reconferido** por `remove_if_unused` sob a trava do hash), todo áudio da conta que (a) nenhum documento cita, (b) não tem tarefa ativa e (c) foi registrado há mais de `CLEANUP_GRACE_SECS` (3600 s). O que passa em (a) e (b) mas falha em (c) conta em `skipped_recent` e fica. O que passa em (a) na lista mas, na reconferência sob a trava, ganhou um documento que o cita conta em `skipped_in_use`, e o que ganhou tarefa ativa em `skipped_job` (a tela Conta mostra os dois; o que já era citado na lista não é candidato e não conta). `freed_bytes` soma os `size` registrados (bytes que voltam à cota), mesmo se o arquivo em si ficou por ser de outra conta. Idempotente: uma segunda chamada devolve `removed: 0`.

Detalhes do upload: em **streaming** para um temporário local (`DATA_DIR/tmp/<uuid>`), calculando o hash e o tamanho conforme os pedaços chegam; os tetos valem pelo que **realmente chega**, não pelo `Content-Length`, que o cliente pode mentir (o `Content-Length` declarado só antecipa a recusa). O corpo é sempre conferido contra o hash, mesmo que o objeto já exista (de outra conta): senão bastaria conhecer um hash para "ter" o áudio de alguém. Depois `Store::commit_tmp` (no S3: `HEAD`, e `PUT` só se não existir; em disco: `rename`) e `storage::register` (cota, ver abaixo). `TmpGuard` apaga o temporário se o envio falha ou o cliente desiste. O limite padrão do axum é desligado só nas rotas de upload.

A mensagem de cota é uma só, a constante `storage::QUOTA_MESSAGE`: `cota de armazenamento de 4 GB excedida; apague áudios sem uso na tela Conta`. Sai como `413` no upload (nas três recusas: `Content-Length` declarado, soma durante o envio e `register`) e como `error` do job de FLAC (resolvido em `94731e8`: o job dizia só `cota de armazenamento de 4 GB excedida`, sem dizer onde liberar). Há ação correspondente (as rotas acima). Apagar um **projeto** (`DELETE /api/projects/{id}`) apaga o documento em cascata, **mas não mexe em `samples`**: os áudios dele ficam registrados e passam a `unused`.

#### O modelo de "em uso"

`references(pool, owner)` percorre, **um documento por vez** (eles chegam a 8 MB), todos os `project_docs` dos projetos da conta e junta os hashes com `collect_hashes`: **qualquer string JSON com cara de SHA-256** (64 caracteres hexadecimais minúsculos, `storage::valid_hash`) em qualquer profundidade, e também qualquer **chave** de objeto com essa forma. Isso cobre o mapa `samples` do documento, o `sample` dos clipes, as zonas do sampler e qualquer campo futuro que guarde um hash, sem o servidor conhecer o esquema do documento: é conservador de propósito (um hash citado em lugar inesperado só segura o áudio, nunca o libera por engano). Só a **própria conta** conta: o projeto de outra conta não segura o áudio, e o áudio de outra conta nunca aparece. `names` sai só de `doc.samples[hash].name`.

O estado "em uso" é o do **documento no servidor**, isto é, o último `PUT /doc` aceito. Um áudio recém-subido cujo documento ainda não chegou (o app sobe os áudios **antes** do documento) parece `unused`: por isso a limpeza em massa **e** o apagar por item têm a folga de 1 hora (`CLEANUP_GRACE_SECS`; no item ela cai com `?force=true`) e o app manda os áudios primeiro.

#### Apagar de verdade (`remove`) e a trava por hash

```
remove_if_unused(owner, hash, grace):     -- samples.rs; o DELETE passa grace = !force, o cleanup passa true
  tx = lock_hash(hash)                    -- pg_advisory_xact_lock(hashtextextended(hash, 1))
  SELECT created_at FROM samples WHERE owner_id=$1 AND hash=$2      -- nada: Gone (404 no DELETE)
  citing = projects_citing(owner, hash)   -- pela mesma conexão da trava; não vazio: InUse (409 com projects)
  EXISTS jobs (owner, sample_hash, status queued|running)           -- sim: Job (409)
  if grace && created_at > now() - 3600 s: Recent (409 recent:true)
  DELETE FROM samples WHERE owner_id=$1 AND hash=$2 RETURNING size  -- nada: Gone
  shared = EXISTS (SELECT 1 FROM samples WHERE hash=$1)             -- outra conta o registra?
  if !shared: store.delete(hash)          -- disco: remove_file (NotFound é ok); S3: DELETE do objeto
  tx.commit()  ->  Removed(size)
```

As conferências de uso ficam **dentro** da trava (resolvido em `94731e8`: antes o `DELETE` conferia os documentos uma vez, sem trava, e um `PUT` de documento que passasse a citar o áudio no meio podia deixar o projeto citando um áudio apagado).

- **O blob só sai do disco/S3 quando nenhuma conta o registra.** Se `store.delete` falha, a transação **volta** e o registro fica, coerente com o arquivo que ainda existe (`500` sem detalhe).
- **A trava por hash** (`storage::lock_hash`, chave `hashtextextended(hash, 1)`; o `register` usa a chave `0` com o id do dono, então são travas distintas) serializa **gravar e apagar o mesmo conteúdo**. Sem ela, apagar o blob da conta A enquanto a conta B acaba de "reaproveitá-lo" no upload (o `HEAD` do S3 viu que existia e pulou o `PUT`) deixaria um registro sem arquivo. Quem grava (`PUT /api/samples/{hash}` e `jobs::save_flac`) toma a trava **antes** de `commit_tmp`/`store_bytes` e só a solta (`commit`) depois de `register` ter dado certo; se `register` falha (cota), a transação é descartada (`rollback`) e o blob fica órfão para a faxina de 1 hora.
- O `PUT` que encontra o áudio **já registrado** na conta responde `204` antes de tomar a trava (nada a gravar).

#### Corrida com o documento e com tarefas (resolvido em `94731e8`, fase 11; uma conexão só por chamada, `1180152`)

Apagar (`DELETE` e cada item do `cleanup`), criar tarefa (`POST /api/jobs`) e gravar documento que passa a citar um áudio (`PUT /doc`) tomam a **mesma trava por hash** (`storage::lock_hash`/`lock_hashes`, advisory lock de transação). `remove_if_unused` toma a trava e só então confere os documentos (`projects_citing`: filtra no banco os documentos que contêm o texto do hash e confirma com `collect_hashes`), as tarefas ativas e a folga de 1 h; `POST /api/jobs` confere que o áudio existe e insere a tarefa sob a trava; o `PUT` toma, em ordem fixa, a trava dos hashes que o documento novo cita e o antigo não citava (só os da conta, para não gastar locks à toa) e, se algum sumiu enquanto esperava, responde `422 {"error": …, "missing": [hash…]}` sem gravar (a mensagem pede para enviar o áudio de novo e salvar outra vez; o app faz isso sozinho, até 3 vezes). O `PUT` do documento, o `DELETE`/`cleanup` e o envio de áudio (`storage::register` recebe a transação da trava, tanto no `PUT /api/samples/{hash}` quanto no `jobs::save_flac`, e o `cleanup` também: só o levantamento inicial dos candidatos usa o pool, antes de qualquer trava) usam **uma conexão só** do pool do começo ao fim. Antes de `1180152` cada um pedia uma segunda conexão ao pool enquanto segurava a primeira. Teste: `muitas_chamadas_simultaneas_com_a_trava_nao_esgotam_o_pool` (40 rodadas de `PUT`, `DELETE` e envio ao mesmo tempo num pool de 8; `put_com_versao_velha_e_audio_sumido_recebe_409_e_nao_422`). Resultado: uma tarefa criada no meio de uma limpeza não falha mais com "áudio não encontrado no armazenamento", e um documento não fica citando um áudio apagado no mesmo instante. Testes: `limpar_revalida_documento_que_chegou_depois_da_lista`, `limpar_nao_apaga_o_que_ganhou_tarefa_no_meio`, `criar_tarefa_e_apagar_do_mesmo_audio_nao_se_cruzam`, `put_do_documento_espera_a_trava_do_hash_e_recusa_audio_que_sumiu`.

### Tarefas (`routes/jobs.rs`)

`Job` (JSON): `id`, `kind` (`flac`, `audio_to_midi` ou `encode_audio`), `status` (`queued`, `running`, `done`, `failed`), `progress` (0..1), `error` (string ou `null`), `result` (objeto ou `null`). `owner_id`, `sample_hash`, `params` e datas não saem.

| Método e caminho | Corpo | Sucesso | Erros |
|---|---|---|---|
| `POST /api/jobs` | `{"kind", "sample", "params"?}` | `202` `{"id", "status": "queued"}` | `400` `kind` (só `flac`, `audio_to_midi` ou `encode_audio`), hash inválido ou `params` (no `encode_audio` são obrigatórios: ver abaixo); `404` sample que a conta não tem; `429` já há 10 tarefas em andamento (`queued` ou `running`) na conta; `401` |
| `GET /api/jobs/{id}` | | `200` `Job` | `404` (inclusive de outra conta); `401` |
| `GET /api/jobs` | | `200` lista das 50 mais recentes da conta | `401` |
| `DELETE /api/jobs/{id}` (fase 15) | | `204` tira a tarefa do histórico (`queued`, `done` ou `failed`) ou **cancela** uma `running` neste processo (fase 17: a bandeira `AtomicBool` da tarefa em `RUNNING` sobe, a linha some na hora e o resultado, quando o trabalho para, é jogado fora; o MP3 olha a bandeira a cada segundo de áudio, o FLAC só ao fim) | `404` (inclusive de outra conta); `409` tarefa rodando em outra instância (`a tarefa está em andamento e não pode ser cancelada agora`); `401`. Vale para os três `kind`. Não apaga o áudio de entrada nem o resultado: quem chama apaga com `DELETE /api/samples/{hash}?force=true` |

`params` de `audio_to_midi` (normalizados por `check_params` na criação; para `flac` são descartados, mas um `params` que não seja objeto dá `400` nos dois tipos):

| Chave | Faixa | Padrão | Erro `400` (texto) |
|---|---|---|---|
| `min_note_ms` | 0 a 5000 | 60 | `min_note_ms: número entre 0 e 5000` |
| `rms_floor_db` | −120 a −10 | −45 | `rms_floor_db: número entre -120 e -10` |
| `start` (segundos do arquivo) | 0 a 10 000 000 | 0 | `start: segundos, número de 0 em diante` |
| `end` (segundos do arquivo) | 0 a 10 000 000, e `end > start` (com `start` ausente, vale 0); **obrigatório quando `start` > 0** (`400 {"error": "end: obrigatório quando há start (o trecho tem no máximo 10 minutos)"}`; o servidor não sabe a duração na criação e sem `end` só falharia na decodificação; `start` 0 sem `end` é o arquivo inteiro e passa; resolvido em `1180152`) | fim do arquivo | `end: segundos, número de 0 em diante`; `end: precisa ser maior que start`; `trecho longo demais: o máximo é 10 minutos` (se `end − start` passa de 600 s) |

Resolvido em `94731e8`: o teto de `rms_floor_db` era 0, e com piso ≥ −6 dB o divisor `(−6 − piso)` da velocidade da nota (`audio.rs`) some (zero ou negativo); agora o teto é −10, que deixa 4 dB de margem (o app só oferece −80 a −20). Valores `null` são tratados como ausentes. `start`/`end` são por trecho de arquivo: sem `end` (e sem `start`, ou com `start` 0) o trecho é o arquivo inteiro e só o decodificador, já rodando, recusa se passar de 10 min (a tarefa vira `failed` com `áudio longo demais: o máximo é 10 minutos`, não um `400`); com `start` maior que 0 e sem `end` a criação já dá `400` (resolvido em `1180152`: antes o pedido entrava na fila e só falhava na decodificação, se o trecho até o fim do arquivo passasse de 10 minutos; agora a recusa é sempre na criação, mesmo com um arquivo curto). Um `end` sozinho, ou com `start`, cujo trecho passa de 600 s dá `400` (`trecho longo demais: o máximo é 10 minutos`) na criação. Com trecho, só ele é decodificado (o que vem antes é descartado sem ficar na memória); no resultado, `duration` é a do **trecho analisado** e `start` o início dele, e as notas continuam em segundos do arquivo inteiro.

Erros de decodificação vão para o `error` do job (texto em português, minúsculo; o app capitaliza e põe o ponto): `formato de áudio não suportado (aceitos: WAV, FLAC, MP3, OGG Vorbis e AAC/M4A, mono ou estéreo)` (constante `audio::UNSUPPORTED`), `áudio longo demais: o máximo é 10 minutos` (sem trecho, ou com `start` 0 e sem `end`), `áudio Opus não é suportado; converta para WAV, FLAC, MP3, OGG Vorbis ou AAC/M4A` (Ogg com `OpusHead` no começo do primeiro pacote de uma página de início de fluxo, reconhecido antes do symphonia; resolvido em `94731e8`, e em `1180152` para o `OpusHead` que fica depois dos 512 primeiros bytes do arquivo), `trecho longo demais: o máximo é 10 minutos` (com trecho), `o trecho pedido está fora do áudio` (o trecho não pegou nenhuma amostra; sem trecho a mesma situação é `áudio vazio`), `não consegui decodificar o áudio (arquivo corrompido ou formato não suportado)` (mudou de "…ou codec não suportado, como Opus" em `94731e8`), `áudio vazio`, `áudio não encontrado no armazenamento`, `cota de armazenamento de 4 GB excedida; apague áudios sem uso na tela Conta` (só no `flac`), `erro interno` (pânico da thread de cálculo), `erro interno ao gravar o arquivo` e `erro interno ao registrar o arquivo` (só no `flac`, ao gravar o resultado).

Mensagens de `POST /api/jobs` com `kind: "encode_audio"` (`400`, `check_encode_params` em `jobs.rs`): `params: informe o formato (format: flac ou mp3)` (sem `params`), `params precisa ser um objeto`, `<chave>: parâmetro desconhecido` (aceitas: `format`, `bits`, `level`, `bitrate`, `vbr`, `title`, `artist`, `album`), `format: flac ou mp3`, `<chave>: número inteiro`, `bitrate e vbr valem só para MP3`, `bits: 16, 24 ou 32`, `level: nível de compressão de 0 a 8`, `bits e level valem só para FLAC`, `informe bitrate (CBR) ou vbr, não os dois`, `bitrate: 128, 192, 256 ou 320 (kbps)`, `vbr: de 0 (melhor) a 4`, `<chave>: texto` e `<chave>: no máximo 200 caracteres`. `error` do job (`failed`, em português, mesmo estilo dos outros): `o arquivo enviado não é um WAV (a exportação compactada parte de um WAV de 16, 24 ou 32 bits)`, `áudio longo demais: o máximo é 30 minutos`, `MP3 exige 44,1 ou 48 kHz e o áudio tem N Hz; exporte o WAV nessa taxa ou use FLAC`, `falha ao codificar o MP3: …`, `o codificador de MP3 não produziu áudio`, `falha no FLAC (…)`, e as de cota e de gravação do `save_output`.

`result`: `flac` → `{"sample": "<sha256 do FLAC>", "bytes": n}` (o FLAC entra no armazenamento da conta como qualquer áudio e **conta na cota**); `encode_audio` → o mesmo `sample` e `bytes` mais `format`, `mime`, `filename`, `duration` (s), `rate`, `channels` e `warnings` (ver o item `encode_audio` abaixo); `audio_to_midi` → `{"notes": [{"pitch", "start", "length", "velocity"}], "duration", "start"}` com tempos em **segundos do arquivo inteiro** (o `start` de cada nota já soma o `start` do trecho), `pitch` 0..127, `velocity` 0,05..1; `duration` é a duração do **trecho analisado** (não do arquivo) e `start` o início dele (0 sem trecho). O app lê `notes` e `duration` e ignora `start` (não precisa dele: os tempos das notas já são do arquivo).

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
| `jobs` | `id`, `owner_id` → users (cascade), `kind` (`flac`/`audio_to_midi`/`encode_audio`), `sample_hash`, `params` jsonb, `status`, `progress` real, `error`, `result` jsonb, datas | índice parcial da fila (`queued`/`running`) |

**Fase 15 (C), `db/migrations/2026-10-01-fase15-encode.sql`:** derruba (`DROP CONSTRAINT IF EXISTS jobs_kind_check`) e recria a CHECK de `jobs.kind` com `('flac', 'audio_to_midi', 'encode_audio')`; idempotente. Um banco existente **precisa** rodar o script (`docker exec -i jopendaw-pg psql -U jopendaw -d jopendaw < db/migrations/2026-10-01-fase15-encode.sql`), senão o `INSERT` da tarefa `encode_audio` falha na CHECK e o app recebe `500`, que ele mostra como motivo da queda para WAV. O `schema.sql` já traz a CHECK nova, então bancos novos e o banco de teste (criado do `schema.sql`) não precisam. Sem tabela nem coluna nova.

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

- Teto de **512 MB por arquivo** (`MAX_SAMPLE_BYTES`) e **4 GB por conta** (`QUOTA_BYTES`), somando o `size` de `samples` da conta. Somam os áudios enviados e os arquivos gerados por job (FLAC do `flac`; FLAC e MP3 do `encode_audio`). No `encode_audio` o WAV de entrada (enviado pelo app) e o resultado somam juntos até o app apagar os dois.
- `storage::register` serializa por conta com um **advisory lock** transacional (`pg_advisory_xact_lock(hashtextextended(owner, 0))`): sem ele, dois uploads de 3 GB conferem "cabe" ao mesmo tempo e passam de 4 GB. Áudio já registrado não conta duas vezes. Se passar da cota, `413`. Desde `1180152` o `register` roda **na transação da trava do hash** que quem chama já segura (`&mut Transaction`), em vez de abrir a própria: o advisory lock da conta passa a valer até o `commit` dessa transação, não só até o fim do `register`.
- O upload confere a cota antes (com o `Content-Length` declarado) e durante (com o que chega); a conferência final é a do `register`.
- **Saída da cota:** `DELETE /api/samples/{hash}` e `POST /api/samples/cleanup` (ver "Áudios"). O uso da cota é `sum(size)` de `samples` da conta; apagar o registro devolve a cota **imediatamente**, mesmo que o arquivo continue no armazenamento por ser de outra conta.
- **Apagar projeto não devolve cota**: o registro é da conta, não do projeto. `DELETE /api/me` apaga tudo em cascata (e a faxina de 1 hora leva os blobs que ficarem sem registro).

### Faxina dos blobs

`storage::cleanup` (a cada hora): apaga blobs **sem registro** em `samples` de nenhuma conta (conta apagada, cota estourada no meio de um upload) e temporários esquecidos, só os **modificados há mais de 1 hora** (`ORPHAN_GRACE`): dá tempo de um upload ou job terminar de registrar o que acabou de gravar. Como cada conta só registra o que enviou, um blob compartilhado só é apagado quando **nenhuma** conta o registra (a mesma regra vale no `DELETE /api/samples/{hash}`, que apaga na hora em vez de esperar a faxina). A faxina não toma a trava por hash.

## Fila de tarefas e `audio.rs`

**Fila:** a tabela `jobs`. Um worker tokio criado no `setup` (frio, então sobrevive aos patches) faz o laço: espera uma vaga (`Semaphore`, no máximo **2 tarefas ao mesmo tempo**), tenta tomar a vez das exportações (`ENCODE_TURN`, 1 vaga; sem ela o `claim` pula as `encode_audio`), pega a mais antiga `queued` com `UPDATE ... WHERE id = (SELECT ... AND ($1 OR kind <> 'encode_audio') ORDER BY created_at FOR UPDATE SKIP LOCKED LIMIT 1)` (vira `running`), registra a bandeira de cancelamento da tarefa em `RUNNING` (um `HashMap<Uuid, Arc<AtomicBool>>` do processo), roda o trabalho em `tokio::task::spawn_blocking` e grava o resultado. Acorda na hora com `POST /api/jobs` (`job_wake`) e, por garantia, a cada 2 s. Enquanto a thread trabalha, o progresso vai para o banco duas vezes por segundo. Falha vira `failed` com a mensagem (o pânico da thread vira "erro interno"). No boot, `requeue_orphans` devolve à fila o que estava `running` quando o processo caiu.

Áudio de entrada: lido do armazenamento inteiro para a memória antes da thread (a decodificação é síncrona). `audio::decode_audio_span(bytes, Span { start, end })` é o ponto de entrada (`compute` em `jobs.rs` o chama para os dois tipos de tarefa; `decode_audio` e `decode_wav`, sem trecho, existem só sob `#[cfg(test)]`). `Span` são segundos do arquivo, convertidos em quadros `[de, até)` pela taxa (`Span::frames`, arredondando):

1. **WAV pelo caminho próprio** (`decode_wav_span`, o mais rápido; recorta o trecho direto dos bytes): PCM inteiro de 16, 24 ou 32 bits ou float de 32 bits (inclusive `WAVE_FORMAT_EXTENSIBLE`), mono ou estéreo, taxa de 1 a 655 350 Hz. O tamanho do `data` pode mentir (0xFFFFFFFF, gravação interrompida): vale o que há no arquivo.
2. Se `decode_wav` devolve `UNSUPPORTED` (não é RIFF/WAVE, ou é um WAV de 8 ou 64 bits, ou 3+ canais), tenta `decode_symphonia`: a symphonia sonda o formato (sem `Hint`), pega a primeira faixa com codec conhecido e decodifica pacote a pacote. Formatos e codecs ligados em `server/Cargo.toml` (`default-features = false`): `flac`, `mp3`, `ogg`, `vorbis`, `aac`, `isomp4`, `alac`. Ou seja: **FLAC, MP3, OGG Vorbis, AAC/M4A e ALAC**. **Sem** Opus (a symphonia 0.5 não o decodifica), AIFF, WAV pelo lado da symphonia (`wav`/`pcm` não estão ligados; WAV só pelo caminho 1) nem WebM/MKV. Mono ou estéreo; a taxa e o número de canais são fixados no primeiro pacote decodificado e **mudar no meio** é `UNSUPPORTED`. Pacote corrompido (`DecodeError`) é pulado; outro erro encerra o laço e vale o que já saiu; arquivo cortado ao meio converte o que deu, cortado antes do primeiro quadro dá erro (teste `lixo_e_arquivo_cortado_dao_erro_claro`).
3. Tudo vira `Pcm` de inteiros de 24 bits intercalados (float da symphonia × 2^23, arredondado e saturado; NaN vira 0).

**Limite de duração:** `MAX_SECONDS = 600` (10 minutos), medido em quadros por taxa. O WAV é recusado **antes** de virar amostras (pelo tamanho do `data`); na symphonia a checagem é a cada pacote, então a memória chega a ~10 minutos de `i32` antes do erro. `áudio longo demais: o máximo é 10 minutos` (com trecho a mensagem é `trecho longo demais: o máximo é 10 minutos`). Exatamente 600 s passa. Vale para o **trecho** pedido (`start`/`end`), ou para o arquivo inteiro quando não há trecho (resolvido em `94731e8`: antes valia sempre para o arquivo, e um clipe curto de um arquivo com mais de 10 min falhava). O app manda o trecho que o clipe toca com 0,25 s de folga de cada lado (`spanForClip`, `convertMarginSeconds` em `app/lib/daw/audio_to_midi.dart`: `start = max(0, offset − 0,25)`, `end = offset + length + 0,25`), então um clipe curto de um arquivo longo converte. O `flac` não recebe trecho (`params` descartados): converte o arquivo inteiro, com o teto de 10 min.

**Qual mensagem o Opus dá (resolvido em `94731e8`):** a symphonia 0.5.5 reconhece o fluxo Opus no Ogg (`CODEC_TYPE_OPUS`) mas não tem decodificador, então `get_codecs().make` falha e, sozinha, a função devolveria `UNSUPPORTED` (a mensagem "…como Opus" que havia era inatingível). Agora `decode_symphonia` testa antes (`is_ogg_opus`: anda pelas páginas de início de fluxo do Ogg e olha o começo do primeiro pacote de cada uma, então acha o `OpusHead` mesmo com outro fluxo multiplexado antes; para na primeira página que não é de início de fluxo, e página cortada ou arquivo que não começa com `OggS` não é Opus) e devolve `OPUS_UNSUPPORTED`: `áudio Opus não é suportado; converta para WAV, FLAC, MP3, OGG Vorbis ou AAC/M4A`. Resolvido em `1180152`: em `94731e8` a busca só olhava os primeiros 512 bytes do arquivo, e um Ogg com outro fluxo (uma página de mais de 512 bytes) na frente do Opus não era reconhecido como Opus e o symphonia o recusava com a mensagem genérica dele. Coberto por `job_opus_tem_mensagem_propria` (com um fluxo de 700 bytes multiplexado antes do `OpusHead`) e por um teste unitário de `audio.rs` com páginas sintéticas (`ogg_page`); não há teste com um `.opus` real `(não executado com um arquivo Opus real)`.

- **`flac`** (`audio::encode_flac`): FLAC de 24 bits em Rust puro (`flacenc`, sem libFLAC), com o cabeçalho corrigido no fim (mínimo do bloco = máximo, para decodificadores estritos como o symphonia do Android aceitarem). Progresso 0,1 depois de decodificar. O resultado entra no armazenamento pelo hash (sob a trava do hash, ver "Áudios") e conta na cota. **Nada no app pede esta tarefa hoje.**
- **`encode_audio`** (fase 15, `encode.rs`; exportação em FLAC e MP3): recebe o hash de um **WAV** já enviado (16, 24 ou 32 float; mono ou estéreo; até 30 minutos, `audio::ENCODE_MAX_SECONDS`, e 512 MB de upload; outro formato falha com `o arquivo enviado não é um WAV…`) e devolve o arquivo compactado como áudio da conta (sob a trava do hash, conta na cota, nasce `unused`; o download continua `application/octet-stream`, o MIME vai no resultado). Uma exportação por vez no processo (`ENCODE_TURN`, um `tokio::sync::Semaphore` de 1 vaga, desde a fase 17; antes era um `Mutex` dentro do `spawn_blocking`: o WAV de 30 min decodificado ocupa centenas de MB); a segunda espera `queued`. `params` (validados na criação, `400` em parâmetro desconhecido ou fora da faixa): `format` (`flac` | `mp3`, obrigatório); FLAC: `bits` 16, 24 ou 32 (32 grava 24 com aviso; de 24 para 16 arredonda sem dither, com aviso) e `level` 0 a 8 (padrão 5); MP3: `bitrate` CBR 128, 192 (padrão), 256 ou 320, **ou** `vbr` 0 a 4 (V0 a V4), nunca os dois; só 44,1 ou 48 kHz (outra taxa: `MP3 exige 44,1 ou 48 kHz e o áudio tem N Hz; …`; o FLAC aceita qualquer uma); `title`, `artist`, `album` (até 200 caracteres; sem caracteres de controle, de direção de texto nem marca de ordem de bytes, espaços repetidos viram um; o que vai para o banco já está limpo). Metadados: bloco VORBIS_COMMENT no FLAC (`TITLE=`, `ARTIST=`, `ALBUM=`, inserido logo depois do STREAMINFO) e ID3v2.4 em UTF-8 no MP3. `result`: `{"sample", "bytes", "format", "mime" ("audio/flac" | "audio/mpeg"), "filename" (sugerido: "Artista - Título.ext" ou "exportacao.ext", sem separador de caminho), "duration", "rate", "channels", "warnings": [texto…]}`. **Encoder MP3: `rusty_mp3` 0.8 (Rust puro, Apache-2.0, sem C nem FFI)**, e não o LAME (`mp3lame-encoder`, `shine-rs`: LGPL, ligariam C na imagem Docker e trariam obrigação de licença). Custo: a qualidade fica um pouco atrás do LAME (a crate mede 0,1 a 0,2 ODG a menos em 128 a 192 kbps) e é uma crate jovem; o VBR dela é uma taxa média alvo (V0 ~245, V1 ~225, V2 ~190, V3 ~175, V4 ~165 kbps) e não o VBR do LAME. O FLAC usa o mesmo `flacenc` do job `flac` (`audio::encode_flac_with`). Migração: `db/migrations/2026-10-01-fase15-encode.sql` (a CHECK de `jobs.kind`); testes: `encode_tests.rs` (ida e volta decodificada pelo symphonia em todos os níveis, taxas e formatos) e `routes/tests_encode.rs`.
  - **Fluxo no worker** (`compute_encode` em `jobs.rs`, dentro de `spawn_blocking`): (a vez `ENCODE_TURN` já foi tomada pelo worker antes de a tarefa virar `running`) `Format::from_params` e `Meta::from_params` → `audio::decode_wav_for_encode` (só RIFF/WAVE; o mesmo `parse_wav` do `decode_wav`, com teto de 1800 s em vez de 600 s; WAV de 1 ou 2 canais, taxa até 655 350 Hz, 16/24/32 inteiro ou 32 float; tudo vira `i32` de 24 bits, com o 32 inteiro truncado por `>> 8`) → `encode::encode_cancelable` → `Output::Encoded(bytes, info)` → `save_output` (hash SHA-256 do arquivo, sob a trava do hash, `register` com cota). O resultado é o `info` (`format`, `mime`, `filename`, `duration`, `rate`, `channels`, `warnings`) mais `sample` e `bytes`.
  - **Progresso:** 0,05 depois de decodificar; o FLAC só marca 0,2 do trecho (`0,05 + 0,95 × 0,2`) antes de acabar, então a barra dele salta; o MP3 anda por segundo de áudio, de 0,1 a 0,95 do trecho, mapeado da mesma forma.
  - **FLAC** (`audio::encode_flac_with(pcm, bits, level)`, `flacenc`): `level` 0 = só preditores fixos de ordem até 1 e sem estéreo lateral; 1 e 2 = só preditores fixos; 3, 4, 5, 6, 7, 8 = LPC de ordem 6, 8, padrão do `flacenc`, 12, 16, 24. De 24 para 16 bits: `(s + 128) >> 8`, saturado, **sem dither** (o app manda o WAV 16 bits já com dither, então o caminho normal não passa por aqui). Metadados: `with_vorbis_comment` insere um bloco VORBIS_COMMENT (tipo 4, vendor `jopendaw`, `TITLE=`, `ARTIST=`, `ALBUM=`) logo depois do STREAMINFO e tira o bit de "último bloco" deste; sem metadado devolve o FLAC igual.
  - **MP3** (`rusty_mp3::Mp3Encoder`): CBR com `bitrate_kbps`, VBR com `vbr_quality_index(q)`; alimenta 1 s de amostras por vez (`f32 = i32 / 8 388 608`), esvazia os pacotes, `finish()`. Só 44 100 e 48 000 Hz. A tag ID3v2.4 (`TIT2`, `TPE1`, `TALB`, codificação 3 = UTF-8, tamanhos syncsafe) vai na frente; sem metadado não há tag.
  - **Metadados:** `clean_text` tira caracteres de controle (não os espaços), os de direção de texto (U+200B–200F, U+202A–202E, U+2066–2069) e a marca de ordem de bytes (U+FEFF), junta espaços repetidos e apara; vazio vira `None`. O limite de 200 caracteres vale depois da limpeza (recusa com `400`; antes dela, o limite bruto é 800). O app manda só `title` e `album`.
  - **`filename`:** `suggested_name` (`Artista - Título.ext`, `Título.ext` ou `exportacao.ext`, com `/ \ : * ? " < > |` trocados por `-`, cortado em 100 caracteres, sem ponto ou espaço nas pontas). O app **não usa** esse nome: monta o dele a partir do nome do WAV.
  - **Memória:** o WAV lido (até 512 MB) e o áudio decodificado em `i32` (até cerca de 690 MB para 30 min estéreo a 48 kHz) coexistem antes do `drop(bytes)`; por isso a trava de uma exportação por vez `(estimativa pelo tamanho dos vetores, não medida)`.
- **`audio_to_midi`** (`audio::audio_to_midi`): transcrição de áudio **monofônico** em notas, pelo detector de altura **YIN**:
  1. mistura em mono; taxas acima de 30 kHz são reduzidas por média de blocos (a janela de 2048 quadros continua cobrindo 50 Hz);
  2. quadros de 2048 amostras com passo de 512; quadro abaixo do piso de energia (`rms_floor_db`) é silêncio e nem gasta o YIN;
  3. YIN por quadro (diferença, normalização cumulativa, primeiro mínimo abaixo de 0,15, interpolação parabólica), faixa de 50 Hz a 2 kHz; altura em semitons MIDI fracionários;
  4. mediana de 5 quadros sobre as alturas (tira saltos de oitava de um quadro só);
  5. segmentação: silêncio fecha a nota; uma mudança de altura de 0,7 semitom ou mais por 3 quadros seguidos abre outra nota; quadro com energia mas sem altura clara continua a nota aberta;
  6. descarta notas mais curtas que `min_note_ms`; `pitch` é a mediana arredondada, `start` e `length` em segundos, `velocity` = do piso a −6 dBFS mapeado em 0..1, nunca abaixo de 0,05 (zero é note-off em MIDI).

## Testes

- **Unitários** (sem banco): `audio.rs` (YIN em senoides, ruído e silêncio, segmentação, vibrato que não divide, parâmetros, taxa alta, WAV de 16/24/32 e float, formato não suportado, FLAC ida e volta sem perda; e, da fase 9, decodificação de MP3/OGG estéreo/M4A a partir de `server/testdata/seno440.{mp3,ogg,m4a}` achando o lá 440 (nota 69), FLAC e WAV pelo mesmo `decode_audio`, lixo/arquivo cortado, limite de 10 minutos: 660 s recusado, 599 s passa; e, da fase 11, `trecho_limita_o_trecho_e_nao_o_arquivo` (um trecho curto de um arquivo longo passa; um trecho de 650 s dá `trecho longo demais`) e `trecho_em_formato_comprimido`, mais o Opus sintético que dá `OPUS_UNSUPPORTED` e o Vorbis que não é tomado por Opus; e, da fase 13, o `OpusHead` numa segunda página depois de um fluxo de 700 bytes, a página de dados sem início de fluxo e a página cortada, que não são Opus), `storage.rs` (hash válido e SHA-256 conhecido), `oauth.rs` (PKCE do RFC 7636, só email verificado).
- **De rota** (`server/src/routes/tests.rs`), contra um Postgres de verdade. Precisam de `TEST_DATABASE_URL` apontando para um banco **à parte** com o `schema.sql` (nunca o de desenvolvimento: os testes criam contas e tarefas). Sem a variável cada teste se declara pulado e passa.

```bash
docker exec jopendaw-pg psql -U jopendaw -d postgres -c "CREATE DATABASE jopendaw_test"
docker exec -i jopendaw-pg psql -U jopendaw -d jopendaw_test < server/schema.sql
TEST_DATABASE_URL=postgres://jopendaw:jopendaw@localhost:5432/jopendaw_test cargo test -p jopendaw-server

# os mesmos testes contra o S3 (MinIO local: docker-compose up -d minio minio-init)
S3_ENDPOINT=http://localhost:9000 S3_BUCKET=jopendaw S3_ACCESS_KEY=jopendaw S3_SECRET_KEY=jopendaw-minio-dev \
  TEST_DATABASE_URL=... cargo test -p jopendaw-server
```

Cobertura das rotas: documento versionado (409 com o documento, entradas inválidas, alheio 404, gravações simultâneas: só uma vence, 8 MB, ~3 MB passa), samples (idas e voltas, hash que não confere, idempotência, `missing`, isolamento entre contas, limites de tamanho e cota; e, da fase 9, `samples_listar_e_apagar` (lista sem documento = tudo sem uso; uso pelo mapa `samples`, pelo clipe e só pela zona de um sampler; 409 com os projetos; apagar sem uso; da fase 11, o campo `recent`, o `409` com `recent: true` no envio da última hora, o apagar sem insistir depois de vencida a folga (o teste envelhece o `created_at` no banco) e `?force=true` insistindo; hash inválido e sem login; apagar projeto deixa o áudio sem uso). Os testes que só querem apagar usam o auxiliar `del_force`, `samples_apagar_devolve_a_cota`, `samples_isolamento_entre_contas_e_hash_igual` (o projeto de uma conta não segura o áudio de outra; o blob só sai quando nenhuma conta o registra) e `samples_limpar_sem_uso` (poupa citado, recente e com tarefa ativa; resposta `{removed: 1, freed_bytes: 16, skipped_recent: 1, skipped_in_use: 0, skipped_job: 1}`; segunda chamada `removed: 0`; e, da fase 13, `limpar_revalida_documento_que_chegou_depois_da_lista` e `limpar_nao_apaga_o_que_ganhou_tarefa_no_meio` conferem `skipped_in_use` e `skipped_job` igual a 1)), faxina (só o que não tem registro), operações básicas do armazenamento, temporário não fica para trás, migração disco → S3, tarefas (FLAC, áudio → MIDI, formato não suportado, validações, dono, limite de 10, órfão volta para a fila; e `job_validacoes_dono_e_limite`, que, da fase 13, também confere `start` 5 sem `end` recusado com `400` (a mensagem cita `end`), `start` 0 sem `end` aceito com `202` e `params` que não é objeto (`"x"`, `[1]`, `3`) recusado no FLAC também; e `job_audio_para_midi_mp3_e_parametros_extremos`: MP3 com `min_note_ms`/`rms_floor_db` explícitos, `400` fora da faixa e os limites 0/5000 e −120/−10 rodando até `done`; da fase 11, `rms_floor_db` de −121, −9,9, −6, 0 e 0,1 recusado com `400`, com a mensagem de −6 citando −120 e −10) e, da fase 11, os testes de corrida com a trava por hash (`limpar_revalida_documento_que_chegou_depois_da_lista`, `limpar_nao_apaga_o_que_ganhou_tarefa_no_meio`, `criar_tarefa_e_apagar_do_mesmo_audio_nao_se_cruzam` e `put_do_documento_espera_a_trava_do_hash_e_recusa_audio_que_sumiu`, que seguram a trava numa transação à parte, `hold_lock`, e conferem que o outro lado espera ou recusa com `422`), `job_de_cota_estourada_diz_onde_liberar` (o `error` do job de FLAC cita "tela Conta"), `job_opus_tem_mensagem_propria` (da fase 13, também com o `OpusHead` depois dos 512 primeiros bytes) e `job_trecho_de_arquivo_longo` (11 min de WAV a 8 kHz com uma senoide de 440 Hz em 100 s: sem trecho `failed` com `longo demais`; `start` 99,5 e `end` 101,5 → `done`, `duration` ≈ 2 s, nota 69 com `start` entre 99,9 e 101; `400` para `start` −1, `start` 10 e `end` 5, `start` 5 e `end` 5, `end` 601, `end` texto, `start` 1e9; trecho 700–701 → `failed` com `fora do áudio`). Todos rodam contra o Postgres e o disco de verdade, não contra o app no Chrome `(testado só por testes automáticos)`. O teste cria os usuários e sessões direto no banco e emite o JWT com `auth::issue_access`; todos os testes do processo dividem o mesmo `DATA_DIR` temporário (cada um sobe o próprio worker). **Não há teste de rota para a parte de contas** (`auth.rs`, `oauth.rs`): só as funções puras acima. **Também não há teste automático do nginx nem da imagem**: `docker-compose up --build` sobe a `api` pelo `server/Dockerfile` e a `web` (porta 8081) com o `app/nginx.conf.template`, e um `PUT` de mais de 1 MB em `http://localhost:8081/api/projects/{id}/doc` ou `/api/samples/{hash}` (com um token válido) é a conferência de que o proxy não devolve `413`; não rodei isso nesta atualização. Rodar o servidor de verdade é o teste de uso: `./hot.sh`, login pelo código de acesso da conta de revisão (`REVIEW_EMAIL`/`REVIEW_CODE` do `server/.env`).

**Exportação compactada (fase 15 C).** `server/src/encode_tests.rs` (unitários, **sem banco**, rodam em qualquer `cargo test`): FLAC ida e volta idêntico em todos os níveis e nas duas profundidades, nível mais alto não fica maior, 24 para 16 arredonda e avisa, 32 float vira 24 com aviso, metadados no FLAC, MP3 em CBR 128/192/256/320 e VBR V0/V2/V4 com a duração e a frequência certas (uma senoide por canal), tamanho do CBR dentro de 10% da taxa, MP3 mono a 48 kHz e curto, recusa de taxa que não seja 44,1 nem 48 kHz, tag ID3 decodificável, metadados hostis limpos, nome sugerido seguro, WAV de entrada ruim, formato lido dos parâmetros. `server/src/routes/tests_encode.rs` (de rota, precisam de `TEST_DATABASE_URL`): FLAC com metadados ida e volta, MP3 (48 kHz, CBR com `title` e VBR sem) com duração, frequência e `ID3` só quando há título, 14 conjuntos de `params` inválidos (`400`) e metadado hostil limpo no banco, entradas ruins (`failed` com mensagem clara, `DELETE` da tarefa `204`), isolamento entre contas (`404` em tarefa, resultado, `DELETE` e `?force=true` de outra conta, `401` sem token), cota estourada (mensagem com `tela Conta`) e, da fase 17, `encode_segunda_espera_na_fila_e_midi_nao_fica_sem_vaga` (a segunda exportação fica `queued`, um `audio_to_midi` passa na frente, a da fila e a que roda se cancelam com `DELETE`) e `encode_em_andamento_pode_ser_cancelada` (a tarefa some, o WAV de entrada já pode ser apagado e nenhum resultado sobra na conta). Nenhum deles mede tempo de conversão nem o uso de memória de um arquivo de 30 minutos `(não medido)`. O lado do app está em `app/test/export_compressed_test.dart` (ver [App Flutter](10-app-flutter.md#exportação-em-flac-e-mp3-export_compresseddart)).

Verificações do repositório: `cargo fmt --all --check` e `cargo clippy -p jopendaw-server --all-targets -- -D warnings` (rustfmt com `max_width` 160).

## Docker, compose e deploy

**`server/Dockerfile`** (contexto: a **raiz do repositório**; `docker build -f server/Dockerfile .`): estágio `rust:1-bookworm` compila com `cargo build --profile server -p jopendaw-server` (o perfil `server` do `Cargo.toml` raiz herda o `release` com `panic = "unwind"`: um pânico num handler do axum derruba só aquele pedido; com `abort` levaria o processo junto). As dependências entram numa camada própria (compila com um `main.rs` vazio antes de copiar `server/src`) para o cache sobreviver a mudanças no código. Essa camada copia o `Cargo.toml` e o `Cargo.lock` da raiz, o `server/Cargo.toml` **e a pasta `engine/` inteira** (`COPY engine engine`): o workspace lista `engine`, `engine/wasm` e `engine/android` como membros, e o cargo precisa achar os manifestos e os alvos deles (`src/`) para carregar o workspace, mesmo compilando só o servidor, que não depende do motor. O `.dockerignore` da raiz deixa fora `target/`, `app/`, `dumps/`, `**/.env`, `.git/`, `.claude/`, `docs/`, `engine/target/` e `node_modules/`, então o contexto leva só o workspace e `server/`. Estágio final `debian:bookworm-slim` com `ca-certificates` e `libssl3`, usuário de sistema `jopendaw` sem shell (um bug no servidor não vira root no host), `ENV PORT=8080 DATA_DIR=/data`, `VOLUME /data`, `EXPOSE 8080`, `CMD ["jopendaw-server"]`. O `schema.sql` é copiado para `/app/schema.sql`, mas **o servidor não o aplica sozinho**.

**`docker-compose.yml`**: `db` (Postgres 17, `jopendaw-pg`, porta 5432), `minio` + `minio-init` (S3 local), `api` (build do Dockerfile, porta 8080, `S3_*` apontando para o MinIO, `JMAIL_URL` para o jmail do host, `APP_BASE_URL=http://localhost:8081`), `web` (build de `app/`, nginx em 8081 com `JOPENDAW_API_HOST=api:8080`). O `api` usa `context: .` e `dockerfile: server/Dockerfile`, isto é, a raiz do repositório como contexto. `docker-compose up --build` sobe tudo. Segredos do compose são só de desenvolvimento; `JMAIL_API_KEY`, `GOOGLE_*` e `DISCORD_*` vêm do ambiente do host.

**nginx** (`app/nginx.conf.template`): gzip, cabeçalhos de segurança e CSP (o Flutter/CanvasKit carrega o motor do gstatic e compila WebAssembly), `proxy_pass` de `/api/` para `${JOPENDAW_API_HOST}` com `proxy_read_timeout 300s`, `client_max_body_size 600m` e `proxy_request_buffering off` (só nesse `location`: uploads de áudio de até 512 MB e o documento de até 8 MB passam, e o corpo segue para a API sem ser guardado em disco pelo nginx; o padrão do nginx seria 1 MB), `/healthz`, `manifest.json`, `sw.js` sem cache, arquivos do build revalidados a cada carga (`expires -1`; o Flutter não põe hash no nome), `/entrar` e `/login` sem `Referer` e sem cache (o token vai na URL), `/privacidade` e `/termos` estáticos, e fallback de SPA para `index.html`. Há um `location = /api/ws` de WebSocket, "quando existir": o servidor **não tem** rota `/api/ws` hoje.

**Produção:** o domínio previsto é `jopendaw.johnenrique.tech` (a URL está fixa em `app/lib/api/client.dart`, no manifest Android e no `assetlinks.json`). Os segredos vêm do Dokploy (comentário do compose) e o deploy segue o processo da VPS do dono (build da imagem, push para o registry próprio, acionamento no Dokploy). O jopendaw ainda não tem receita de deploy escrita no repositório, e as credenciais do MinIO da VPS ainda estavam pendentes nas notas do projeto: `(não confirmado se está em produção)`. Não mexa na VPS sem o dono.

## Decisões e por quê

- **SeaORM para o domínio, sqlx direto para contas e para o documento.** O query builder serve ao CRUD; contas precisam de `UPDATE ... RETURNING` atômicos e de `FOR UPDATE`, e o documento, do `UPDATE ... WHERE version = $n` numa transação.
- **Concorrência otimista, não bloqueio.** Vários aparelhos editam offline; ninguém segura trava. O 409 devolve o documento vencedor para o app decidir.
- **Endereçamento por conteúdo.** O SHA-256 dá deduplicação, idempotência do upload, cache imutável no navegador e conferência de integridade; a prova do conteúdo no `PUT` impede "ter" o áudio alheio só sabendo o hash.
- **Erros sem detalhe do banco** no 5xx; detalhe só no log.
- **"Em uso" por varredura de qualquer string com cara de hash (`collect_hashes`), não por campos conhecidos.** O documento é um JSON aberto que evolui com o app; listar os campos que guardam hash faria um campo novo liberar áudio em uso. O custo é ler todos os documentos; o ganho é nunca apagar por esquecimento.
- **Folga de 1 hora nos dois apagares, com `force` só no item (`94731e8`).** O app sobe áudio antes do documento, então um áudio recém-enviado parece sem uso mesmo quando um projeto ainda por sincronizar o cita. A limpeza em massa nunca apaga o recente (é ação em lote, o erro custa mais e a pessoa não vê cada linha); o item também recusa com `409 {"recent": true}`, mas a pessoa pode insistir com `?force=true` depois de o app avisar. Antes, o apagar por item não tinha folga alguma. `force` desliga só a folga: documento que cita e tarefa ativa continuam valendo.
- **Conferir sob a trava, não antes.** `remove_if_unused` confere documentos, tarefas e folga já com a trava do hash tomada, em vez de conferir e depois travar. A leitura dos documentos vai pela mesma conexão da trava (o filtro `position(hash in doc::text)` evita ler os documentos que não citam), mas só depois de a trava chegar, então enxerga tudo o que um `PUT` concorrente já confirmou.
- **Trava por hash separada da trava por dono.** A cota é por conta (`hashtextextended(owner, 0)`), a integridade do blob é por conteúdo (`hashtextextended(hash, 1)`): contas diferentes com o mesmo arquivo precisam se serializar entre si na gravação/apagamento do blob, mas não na cota uma da outra.
- **Perfil `server` com `unwind`.** Um handler que entra em pânico não derruba o processo.
- **`setup` frio, `serve` quente.** O hot-patch precisa de um lugar estável para o estado (pool, worker, faxina) e de um lugar recriável para o que se edita.
- **Cache-Control `no-cache` nos estáticos** no servidor de desenvolvimento para não rodar o app novo com o `host.js` ou o wasm velhos.
- **Imagem do servidor com o workspace inteiro (`0c0593e`).** O cargo carrega o workspace todo antes de compilar um membro, então a imagem precisa dos manifestos de `engine/`, `engine/wasm` e `engine/android` mesmo sem usá-los; trocar isso por um workspace só com `server` faria o `Cargo.toml` do build divergir do de desenvolvimento. O preço é o cache de dependências invalidado por mudanças em `engine/` (ver Armadilhas).
- **nginx com corpo de até 600 MB e sem buffer de requisição no `/api/` (`0c0593e`).** O teto real dos uploads é da API (512 MB por áudio, 8 MB por documento); o nginx só precisa deixar passar, e o `proxy_request_buffering off` faz o nginx repassar o corpo à medida que chega, em vez de guardá-lo inteiro antes de entregar à API (o comentário no arquivo só cita o limite; essa razão é deduzida do comportamento do nginx). `(não medido)`

## Armadilhas conhecidas

- **Resolvido em `0c0593e`: `server/Dockerfile` não carregava o workspace.** Antes ele copiava só `Cargo.toml`, `Cargo.lock` e `server/Cargo.toml`, e o cargo falharia com "failed to load manifest for workspace member" porque o workspace lista também `engine`, `engine/wasm` e `engine/android` (desde as fases 1 e 5). O commit acrescentou `COPY engine engine` antes da camada de dependências e ampliou o `.dockerignore` (`.claude/`, `docs/`, `engine/target/`, `node_modules/`). Não rodei o build da imagem nesta atualização; o que está escrito vem do diff e dos arquivos atuais. Efeito colateral deduzido da leitura: como `COPY engine engine` vem antes do `cargo build` das dependências, qualquer mudança em `engine/` invalida a camada de dependências do servidor, que não usa o motor; o cache que sobrevive a mudanças é o de `server/src`, não o de `engine/`. `(deduzido do Dockerfile; não medido)`
- **Resolvido em `0c0593e`: nginx sem `client_max_body_size`.** O padrão do nginx é 1 MB, e o documento pode ter até 8 MB e os áudios até 512 MB; um `PUT` maior que 1 MB pelo nginx do `app` receberia `413` do próprio nginx antes de chegar à API. O `location /api/` agora tem `client_max_body_size 600m` (cobre os 512 MB do áudio com folga) e `proxy_request_buffering off`. O limite vale só para `/api/`: os demais `location` (estáticos) e `/api/ws` seguem no padrão de 1 MB. Continua `(não confirmado em produção)`: se houver outro proxy na frente do nginx (como o Traefik do Dokploy), a regra dele também vale, e o `proxy_read_timeout 300s` limita um upload lento; o cliente do app corta o `PUT` em 120 s (`app/lib/api/client.dart:60`).
- **Apagar projeto não libera cota.** O áudio fica registrado e aparece como `unused` em `GET /api/samples`; quem libera é a tela `Conta` (ou as rotas `DELETE`/`cleanup`). Ninguém apaga áudio sozinho.
- **"Em uso" é o documento sincronizado.** Um áudio cujo documento ainda não subiu parece `unused`; o `DELETE` por item também tem a folga de 1 hora (`409` com `recent: true`; `force=true` insiste) e a lista traz `recent`. Resolvido em `94731e8`: o `DELETE` por item não tinha folga.
- **`references` lê todos os documentos da conta** (até 8 MB cada) a cada `GET /api/samples` e a cada `cleanup` (que ainda confere de novo cada candidato com `projects_citing`); o `DELETE` por item lê só os documentos que contêm o texto do hash. Contas com muitos projetos grandes pagam isso em cada chamada da tela `Conta`. `(não medido)`
- **Resolvido em `94731e8`: corrida entre `PUT /doc` e `DELETE`/`cleanup`.** O `DELETE` conferia o uso uma vez, sem trava, e um documento que passasse a citar o áudio nesse intervalo ficava apontando para um áudio apagado (os outros aparelhos mostravam `áudio fora deste aparelho`). Hoje os dois tomam a trava por hash (ver "Corrida com o documento e com tarefas"). Resolvido também: a tarefa criada no meio de uma limpeza falhava com `áudio não encontrado no armazenamento`.
- **Resolvido em `1180152`: o app trata o `422`.** `putProjectDoc` lança `DocSamplesMissing(hashes)`; `SyncService._push` tira esses hashes de `_serverHas`, reenvia os áudios e repete o `PUT`, até `maxMissingRetries` (3) vezes; esgotado, vira `SyncFailure` (estado `Erro`, projeto intacto no aparelho) com o `error` do servidor seguido de `. Não consegui reenviar o áudio; abra o projeto no aparelho que o tem e tente de novo.`. Antes, o `422` caía no ramo `ApiException` e o app mostrava o `error` cru, sem ler `missing` e mantendo o áudio em `_serverHas` (a tentativa seguinte pulava o reenvio). Coberto em `app/test/fase13b_test.dart`.
- **Resolvido em `1180152`: `409` antes de `422`.** Um `PUT` de versão-base velha que citasse um áudio apagado recebia `422`, não o `409` com o documento vencedor. Agora a versão é conferida (gravando) antes dos áudios e o `422` desfaz a gravação; o `422` só aparece com a versão certa. Coberto por `put_com_versao_velha_e_audio_sumido_recebe_409_e_nao_422`.
- **Resolvido em `1180152`: duas conexões do pool por chamada.** O `DELETE`/`cleanup`, o `PUT /doc` e o envio de áudio seguravam uma conexão com a trava e pediam **outra** ao pool (10 conexões, timeout de 10 s) para ler documentos ou registrar; ~10 chamadas simultâneas podiam travar todas. Agora leem e gravam pela conexão da própria transação (`projects_citing` e `newly_cited` recebem a conexão; `storage::register` recebe a transação). Coberto por teste de concorrência (pool de 8, 120 chamadas).
- **Job de FLAC e cota:** o FLAC gerado entra em `samples` sem projeto que o cite, então nasce `unused` (e é poupado pela limpeza só na primeira hora). O app não pede a tarefa `flac` hoje (o FLAC da exportação vem do `encode_audio`).
- **`encode_audio`: uma por vez, esperando na fila (resolvido na fase 17).** O worker toma `ENCODE_TURN` (`tokio::sync::Semaphore` de 1 vaga) **antes** de reivindicar a tarefa: sem a vez, `claim` pula as `encode_audio` (`kind <> 'encode_audio'`), então a segunda exportação espera `queued` (sem `running` falso, apagável) e uma `audio_to_midi` passa na frente. Terminando uma tarefa o worker se acorda na hora. Testes: `encode_segunda_espera_na_fila_e_midi_nao_fica_sem_vaga`.
- **`encode_audio`: cancelar (resolvido na fase 17).** O `DELETE` de uma tarefa `running` deste processo sobe a bandeira, apaga a linha e o worker descarta o resultado (`encode_em_andamento_pode_ser_cancelada`), então nem o WAV de entrada fica preso (`Removal::Job`) nem sobra resultado. Só uma tarefa rodando em **outra instância** do servidor continua dando `409` (o registro `RUNNING` é do processo); o app insiste em 3, 10 e 30 s.
- **Teto de 512 MB no envio antes do teto de 30 minutos (o app avisa antes, desde `52d25c1`).** O WAV que o app manda passa por `MAX_SAMPLE_BYTES` (512 MB) no `PUT /api/samples/{hash}`: a 96 kHz e 24 bits estéreo o limite prático é perto de 15 minutos, não 30. O servidor continua recusando (`arquivo grande demais (máximo de 512 MB)`, `413`), mas o app já calcula o tamanho do WAV (`estimatedWavBytes`, contra `kEncodeMaxUploadBytes`) e, acima disso, mostra o aviso na janela `Exportar áudio` e desliga o botão `Exportar`: a recusa do servidor só chega ao app se a estimativa errar. `(conta feita à mão, não testada contra o servidor)`
- **Sem medida do custo.** Não há número para tempo de conversão e pico de memória de um arquivo de 30 minutos, nem para a qualidade do `rusty_mp3` além do que a documentação da crate diz (0,1 a 0,2 ODG abaixo do LAME em 128 a 192 kbps). O VBR é taxa média alvo; os `~245 kbps` de V0 e afins são os rótulos do app, não uma medida do arquivo. `(não medido)`
- **Os avisos (`warnings`) do FLAC não saem do app.** O app manda o WAV já na profundidade pedida (16 ou 24), então nem o aviso do 32 float nem o do 24 para 16 chegam à janela no uso normal; só chamando a API diretamente.
- **Resolvido em `52d25c1`: o app usa o `filename` do resultado.** `CompressedExport._savedName` salva com o nome sugerido pelo servidor (`Artista - Título.ext`) quando ele termina na extensão do formato; senão cai no nome do WAV com a extensão trocada (`compressedName`). Mudar `suggested_name` muda o arquivo salvo.
- **Uma instância só.** `requeue_orphans` no boot devolve **todas** as tarefas `running` à fila, inclusive as que outra instância estaria rodando; o limite de 2 tarefas simultâneas é por processo. O desenho pressupõe um único processo.
- **Decodificação no servidor cobre o que o navegador importa, menos Opus.** MP3, FLAC, OGG Vorbis, AAC/M4A e ALAC decodificam; OGG/Opus falha com mensagem própria (`áudio Opus não é suportado; …`, resolvido em `94731e8`); AIFF e WebM, com `formato de áudio não suportado (…)`. O teto de 10 minutos vale pelo trecho (`start`/`end`), não pelo arquivo (resolvido em `94731e8`); sem trecho, vale pelo arquivo.
- **Resolvido em `1180152`: `cleanup` conta o que pulou por uso ou tarefa** (`skipped_in_use`, `skipped_job`) e a tela Conta mostra (`cleanupSummary` em `app/lib/screens/account_screen.dart`). Antes só `skipped_recent` era devolvido e o resto sumia do resultado sem aviso. Um servidor antigo, sem os campos, é lido como zero.
- **A decodificação (symphonia) é trabalho de CPU síncrono** dentro de `spawn_blocking`, sem teto de tempo: 10 minutos de MP3 ocupam uma das 2 vagas do worker enquanto decodificam e analisam. `(não medido)`
- **Leitura do áudio inteiro na memória** (`Store::read`) nos jobs: até 512 MB por tarefa, 2 tarefas ao mesmo tempo.
- **`requeue` e testes.** Os testes de rota dividem banco e `DATA_DIR`; `requeue(pool, Some(owner))` existe para não mexer nas tarefas alheias.
- **`/README.md` da raiz é uma cópia antiga do `CLAUDE.md`** (diz que `entities/` "hoje só tem `project`"); vale o `CLAUDE.md`.
- **Mudou a assinatura ou o `AppState`?** O hot-patch não aplica: reinicie o `./hot.sh` (ver acima).
