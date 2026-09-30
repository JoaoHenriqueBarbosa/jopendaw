# Arquitetura de ponta a ponta

> Visão geral do jopendaw para quem vai mexer em qualquer camada (app Flutter, motor Rust, pontes web/Android, servidor): quais são as peças, onde cada uma mora, como conversam e por que o desenho é "local primeiro".

## Visão geral

O jopendaw é um DAW: o som é produzido e mixado **no aparelho** da pessoa; o servidor só guarda contas, a cópia sincronizada do projeto, os arquivos de áudio e tarefas pesadas. Há um único código de app (Flutter) que vira o site e o app Android, e um único código de motor de áudio (Rust) que roda de duas formas: WASM dentro de um `AudioWorklet` no navegador, ou biblioteca nativa (`.so`) pelo `dart:ffi` no Android.

```
                       APARELHO (navegador ou Android)                          SERVIDOR (VPS)
 ┌─────────────────────────────────────────────────────────────────────┐   ┌─────────────────────────┐
 │  Flutter (app/lib)                                                  │   │ nginx (app/Dockerfile)  │
 │  ┌──────────────┐  edições   ┌────────────────────┐                 │   │  serve app/build/web    │
 │  │ telas/widgets│ ─────────▶ │ DawController      │                 │   │  proxy /api/ ───────┐   │
 │  │ (timeline,   │            │ (documento, undo,  │                 │   └─────────────────────┼───┘
 │  │  mixer, ...) │ ◀───────── │  sync com o motor) │                 │                         ▼
 │  └──────────────┘  estado    └───┬───────────┬────┘                 │   ┌─────────────────────────┐
 │                                  │           │ SyncService          │   │ API Rust (server/)      │
 │            AudioEngine (interface│comum)     │ (HTTP, em 2º plano)  │   │ axum + SeaORM + sqlx    │
 │      ┌───────────────────────────┴──┐        └──────────────────────┼──▶│  /api/auth, /api/me     │
 │      │                              │                               │   │  /api/projects[/{id}/doc]│
 │  WEB │ engine_web.dart              │ ANDROID  engine_ffi.dart      │   │  /api/samples/{hash}    │
 │      │   └ host.js (thread da UI)   │          (dart:ffi)           │   │  /api/jobs              │
 │      │       ├ AudioWorklet         │            └ libjopendaw_     │   │  worker de jobs (tokio) │
 │      │       │  worklet.js + wasm   │              engine.so        │   └───┬───────────┬─────────┘
 │      │       ├ Worker de render     │              ├ thread AAudio  │       │           │
 │      │       │  render-worker.js    │              ├ decodificação  │       ▼           ▼
 │      │       └ IndexedDB            │              └ render offline │   Postgres     S3/MinIO
 │      │                              │            arquivos em        │   (contas,     (áudios por
 │      │                              │            <docs>/jopendaw    │    projetos,    SHA-256;
 │      └──────────────────────────────┘                               │    documento    ou disco
 │                    ▲                                                │    JSONB, jobs) em DATA_DIR)
 │                    └── mesmo crate `engine/` (Rust puro) ───────────┤
 └─────────────────────────────────────────────────────────────────────┘
```

Três fatos estruturam tudo:

1. **O motor não sabe de plataforma.** `engine/` é Rust puro: recebe blocos para processar (`Engine::process`) e chamadas por nome (`engine::api::apply`). Quem o hospeda decide como chamar. Ver [01-motor.md](01-motor.md).
2. **O Dart fala com o motor por uma interface só.** `app/lib/audio/engine.dart` exporta `AudioEngine` e `LocalStore` de `engine_web.dart` (compilação web) ou de `engine_io.dart` (Android e o resto). O restante do app não sabe em qual dos dois está. Ver [02-pontes-web-e-android.md](02-pontes-web-e-android.md).
3. **O servidor não toca som.** Nenhuma amostra passa pelo motor do servidor: ele guarda e serve bytes e roda duas tarefas offline (`flac`, `audio_to_midi`).

## O princípio "local primeiro"

Tudo o que dá para processar no aparelho é processado lá; o backend fica com sincronização e tarefas pesadas (`CLAUDE.md`, seção "Motor de áudio"). Na prática:

| O quê | Onde mora primeiro | O servidor faz |
|---|---|---|
| Documento do projeto (faixas, clipes, notas, mixagem, automação) | Guardado local: IndexedDB na web, arquivos no Android, chave `doc:<id>` (`app/lib/daw/controller.dart:580`) | Guarda uma cópia versionada em `project_docs` (JSONB). |
| Áudios importados ou gravados | Guardado local, chave `sample:<sha-256>` (`controller.dart:1438`) | Guarda os bytes por hash e conta a cota da conta. |
| Estado de sincronização | Guardado local, chave `sync:<id>` (`app/lib/daw/sync.dart:377`) | Nada. |
| Áudio derivado do warp (esticado/transposto/invertido) | Cache local, chave `warp:<chave>` (`app/lib/daw/warp.dart:155`) | Nunca vai ao servidor (`model.dart`: "o som derivado nunca entra no documento nem no servidor"). |
| Render (exportar, congelar, stems), decodificação, warp, detecção de BPM | No aparelho (Worker na web, thread/isolate no Android) | Nada. |
| Áudio → MIDI (YIN) e conversão FLAC | Não roda local | Job na fila (`server/src/routes/jobs.rs`). Em `app/lib` só se cria o job `audio_to_midi` (`app/lib/daw/audio_to_midi.dart:73`); o `flac` existe na API, mas o app não o pede. |

Consequências de projeto:

- Abrir um projeto e tocá-lo funciona **sem rede** depois da primeira carga; a sincronização acontece em segundo plano (`SyncService`, espera de 3 s depois da última edição, recuo de até 2 min; `sync.dart:74-75`).
- Nunca há sobrescrita automática: se os dois lados mudaram, o servidor responde 409 com o documento dele e o app abre o diálogo de conflito (`app/lib/daw/sync_ui.dart`).
- Os áudios sobem **antes** do documento, para que o documento do servidor nunca cite um hash que o servidor não tem (`sync.dart`, cabeçalho do arquivo).
- O documento inteiro é reenviado ao motor a cada mudança (`model.dart`: "vai inteiro para o motor a cada mudança"), inclusive as notas (`engine/src/lib.rs`, seção "Notas": `clear_notes` + `add_note`).

## Peças e responsabilidades

### Fluxos principais

**Tocar.** Um gesto na interface muda o documento no `DawController`; o controlador monta listas de chamadas `[nome, arg...]` e chama `AudioEngine.calls(...)`. Na web a lista vai por `postMessage` ao worklet (`host.js` → `worklet.js`), que a aplica entre um bloco de 128 quadros e o próximo. No Android a lista vira JSON, passa por `jd_calls` e entra numa fila sem trava lida pela thread do AAudio (`engine/android/src/call.rs`, `host.rs`). Nos dois casos quem executa é o mesmo `engine::api::apply`. O estado (batida, tocando, picos, espectro) volta ~60 vezes por segundo: por mensagem do worklet na web, por polling em `jd_state` no Android.

**Sincronizar.** `SyncService` (`app/lib/daw/sync.dart`) fala com a API pela interface `SyncApi` (`app/lib/api/sync_api.dart`), implementada pelo `ApiClient` (`app/lib/api/client.dart`): `POST /api/samples/missing` → `PUT /api/samples/{hash}` para cada faltante → `PUT /api/projects/{id}/doc` com `base_version`. Detalhes em [Contratos](#contratos).

**Entrar.** Sem senha: magic link por email (via jmail), Google, Discord e um código de acesso para a revisão da Play Store (`server/src/auth.rs`, `oauth.rs`). O servidor devolve um JWT de acesso de 15 min (`ACCESS_TTL_MIN`, `auth.rs:31`) e um refresh opaco que gira a cada uso (30 dias, teto absoluto de 90; `auth.rs:33-34`). No app, os tokens ficam no `flutter_secure_storage` (`app/lib/auth/session.dart`); o `ApiClient` renova uma vez num 401 e repete.

### Mapa de diretórios

```
jopendaw/
├── CLAUDE.md            regras do projeto (fonte de verdade dos comandos e das regras)
├── Cargo.toml           workspace Rust: server, engine, engine/wasm, engine/android; perfis
│                        dev, test, release, server, wasm, android (ver 03-build-teste-e-depuracao.md)
├── rust-toolchain.toml  toolchain "stable" + rustfmt, clippy, rust-analyzer
├── rustfmt.toml         max_width 160, use_small_heuristics = "Max"
├── docker-compose.yml   db (Postgres 17), minio + minio-init, api, web (nginx)
├── hot.sh               a API com hot-patch (dx serve --hot-patch --features hot)
│
├── engine/              O MOTOR (crate jopendaw-engine, Rust puro, sem plataforma)
│   ├── src/
│   │   ├── lib.rs         Engine: transporte, clipes, notas, roteamento, automação, render por bloco
│   │   ├── api.rs         apply(): as chamadas do documento por nome (o protocolo comum)
│   │   ├── mixer.rs       canal do mixer: volume, pan, mudo, solo, medidor, inserts e envios
│   │   ├── instrument.rs  trait Instrument + ids de parâmetros (*_param)
│   │   ├── synth.rs       sintetizador subtrativo (tipo 1)
│   │   ├── drums.rs       bateria sintetizada, 12 peças (tipo 2)
│   │   ├── sampler.rs     sampler (tipo 3)
│   │   ├── fm.rs          FM de 4 operadores, 8 algoritmos (tipo 5)
│   │   ├── wavetable.rs   wavetable, 3 séries de 8 tabelas (tipo 6)
│   │   ├── effect.rs      trait Effect, Chain (cadeia de inserts) e ids de parâmetros
│   │   ├── fx/            12 efeitos: chorus, compressor, delay, distortion, eq, filter, gate,
│   │   │                  limiter, phaser, reverb, tremolo, utility
│   │   ├── dsp.rs         blocos de DSP compartilhados
│   │   ├── analyzer.rs    analisador de espectro (FFT sob demanda)
│   │   ├── limiter.rs     limitador de segurança do master
│   │   ├── stretch.rs     warp offline (WSOLA + pitch) e detecção de BPM
│   │   ├── record.rs      notas tocadas ao vivo e capturas de saída (render)
│   │   ├── metronome.rs   clique do metrônomo
│   │   └── testalloc.rs   só nos testes: alocador que conta alocações
│   ├── wasm/            crate jopendaw-engine-wasm: funções C para o AudioWorklet (sem wasm-bindgen)
│   ├── android/         crate jopendaw-engine-android: cdylib `libjopendaw_engine.so`
│   │   └── src/           lib.rs (superfície jd_*), core.rs, host.rs, call.rs, state.rs, alloc.rs,
│   │                      decode.rs (symphonia), capture.rs, offline.rs, platform/ (AAudio, JNI)
│   ├── build-web.sh     compila o wasm e copia para app/web/engine/engine.wasm
│   └── build-android.sh compila os três ABIs para app/android/app/src/main/jniLibs/
│
├── app/                 O APP (Flutter: web e Android do mesmo código)
│   ├── lib/
│   │   ├── main.dart      go_router (rotas em "Contratos"), tema, sessão
│   │   ├── api/           client.dart (único acesso à API), sync_api.dart (interface + tipos)
│   │   ├── auth/          session.dart (tokens), social.dart (Google/Discord)
│   │   ├── audio/         engine.dart (fachada), engine_types.dart, engine_web.dart (web +
│   │   │                  IndexedDB), engine_io.dart (Android + arquivos), engine_ffi.dart (dart:ffi)
│   │   ├── daw/           o estúdio: model.dart (documento), controller.dart (cérebro),
│   │   │                  timeline.dart, transport_bar.dart, mixer_panel.dart, dock.dart,
│   │   │                  piano_roll*.dart, instrument_panel.dart, effects_panel.dart,
│   │   │                  instruments.dart e effects.dart (tabelas de parâmetros = contrato com o motor),
│   │   │                  presets.dart, fx_presets.dart, automation_*.dart, warp*.dart, export*.dart,
│   │   │                  sync.dart e sync_ui.dart, midi_tools.dart, templates.dart, wav.dart, ...
│   │   ├── models/        account.dart, project.dart (espelham o servidor)
│   │   ├── platform/      o que é só web ou só Android (única parte que importa package:web)
│   │   ├── screens/       login, link (magic link), projetos, projeto, conta
│   │   └── widgets/       base visual: PageScaffold, ApiState, diálogos, tema, ResponsiveScaffold
│   ├── web/
│   │   ├── engine/        host.js, worklet.js, render-worker.js, engine.wasm (commitado)
│   │   ├── sw.js          service worker do PWA
│   │   ├── index.html, flutter_bootstrap.js, manifest.json, icons/, privacidade.html, termos.html
│   ├── android/         projeto Gradle; jniLibs/<abi>/libjopendaw_engine.so (commitados)
│   ├── test/            testes de unidade e de widget (com motor falso)
│   ├── integration_test/ testes no emulador/aparelho: engine_test.dart, platform_test.dart
│   ├── tool/icones.py   regenera os ícones a partir de web/favicon.svg
│   ├── Dockerfile, nginx.conf.template   build web + nginx com proxy de /api/
│
├── server/              A API (crate jopendaw-server)
│   ├── src/main.rs      setup frio (env, log, banco, storage, faxina, worker) x serve quente
│   ├── src/config.rs    variáveis de ambiente lidas uma vez
│   ├── src/auth.rs, oauth.rs, mail.rs   contas: magic link, Google/Discord, JWT + refresh, jmail
│   ├── src/routes/      mod.rs (roteador e ApiError), projects.rs, docs.rs, samples.rs, jobs.rs, tests.rs
│   ├── src/entities/    SeaORM: project, project_doc, sample, job
│   ├── src/storage.rs   áudios por SHA-256 em disco ou S3 (rusty-s3), cota, faxina de órfãos
│   ├── src/audio.rs     WAV → PCM, FLAC, YIN (áudio → notas): puro e síncrono
│   ├── schema.sql       schema completo (sem migrations automáticas)
│   └── Dockerfile
│
├── db/migrations/       scripts idempotentes para produção (hoje: 2026-09-30-fase6.sql)
├── tool/cdp.mjs         cliente CDP mínimo para testar o app no Chrome de depuração (:9222)
└── docs/                esta documentação (manual/, dev/, guias/; estilo em _estilo.md)
```

Observações sobre o mapa:

- `app/build/web/` é o resultado de `flutter build web`; o servidor de desenvolvimento o serve (`JOPENDAW_STATIC`, padrão `../app/build/web`, `server/src/main.rs`). Está no `.gitignore`.
- `engine/wasm/` e `engine/android/` são crates finos: quase toda a lógica está em `engine/`. O do Android acrescenta threads, filas, decodificação e E/S; o do wasm é só cola.
- `README.md` na raiz é uma versão antiga do `CLAUDE.md` (descreve `entities/` como "hoje só `project`" e não menciona motor, docs nem fases 6 em diante). A fonte de verdade é o `CLAUDE.md`.

### O servidor

| Módulo | Papel |
|---|---|
| `main.rs` | `setup()` roda uma vez (`.env`, log, conexão, `Mailer`, `storage::Store`, `requeue_orphans`, worker de jobs e a faxina horária); `serve()` monta o roteador e o HTTP e é o que o hot-patch recria a cada patch. Sem `hot`, `main` chama os dois em sequência. Também há o subcomando `migrate-blobs-to-s3`. |
| `config.rs` | `Config::from_env()`: falha cedo se faltar `JWT_SECRET` (mín. 32 caracteres) ou `JMAIL_API_KEY`; lê `S3_*`, `DATA_DIR`, `REVIEW_*`, `GOOGLE_*`, `DISCORD_*`. |
| `routes/mod.rs` | `router()`, `ApiError` (`{"error": "..."}`; 5xx sem detalhe do banco). Toda a API responde `Cache-Control: no-store` e `X-Content-Type-Options: nosniff`. |
| `routes/projects.rs` | CRUD de projetos, sempre filtrado pelo dono. |
| `routes/docs.rs` | documento versionado; teto de 8 MB. |
| `routes/samples.rs` + `storage.rs` | áudios por hash; teto de 512 MB por arquivo, cota de 4 GB por conta. |
| `routes/jobs.rs` + `audio.rs` | fila e worker. |
| `auth.rs`, `oauth.rs`, `mail.rs` | contas em SQL direto pelo sqlx (o mesmo pool do SeaORM). |

Domínio no SeaORM, contas em sqlx: `AppState` guarda `db: DatabaseConnection` e `pool: PgPool` sobre a mesma conexão (`main.rs`, `AppState`).

## Fluxo de dados / ciclo de vida

### Subida do backend

1. `setup()`: `dotenvy`, `tracing`, `Config::from_env()`, `db::connect()`, `Mailer::new`, `Store::from_config` (S3 se `S3_ENDPOINT` estiver definido, senão disco em `DATA_DIR`).
2. `routes::jobs::requeue_orphans`: tarefas `running` de um processo que caiu voltam para `queued`.
3. `tokio::spawn(jobs::worker(...))` e a faxina horária (`auth::cleanup`, `oauth::cleanup`, `storage::cleanup` de blobs sem registro após 1 h).
4. `serve()`: `Router` da API; se `JOPENDAW_STATIC` (padrão `../app/build/web`) existir como diretório, publica o build do Flutter na raiz com fallback para `index.html`; CORS permissivo (a autenticação vai no cabeçalho `Authorization`, não em cookie); `Cache-Control: no-cache` por padrão nos estáticos.

Em produção o frontend tem container próprio (nginx, `app/Dockerfile` + `nginx.conf.template`), o diretório estático não existe no container da API e o nginx faz proxy de `/api/` (e de `/api/ws`, ainda sem rota no servidor) para `JOPENDAW_API_HOST`.

### Do gesto ao som (web)

1. O usuário clica; o widget chama um método do `DawController`.
2. O controlador altera `model.dart`, grava `doc:<id>` no `LocalStore` e emite as chamadas (`_engine.calls([...])`).
3. `engine_web.dart` repassa a `jopendawEngine.calls` (`host.js`), que faz `postMessage` ao `AudioWorkletNode`.
4. `worklet.js` chama `apply` (via as funções C de `engine/wasm/src/lib.rs`) entre blocos e chama `process` a cada 128 quadros.
5. O estado volta por mensagem, o Dart atualiza os medidores.

### Do gesto ao som (Android)

Igual, trocando os passos 3–5: `engine_io.dart` → `FfiEngine` (`engine_ffi.dart`) serializa as chamadas em JSON → `jd_calls` → fila `rtrb` → callback do AAudio aplica antes de cada bloco → estado publicado sem trava, lido por polling.

### Sincronização

```
edição ─▶ grava doc local ─▶ marca "pendente" ─▶ espera 3 s ─▶ SyncService
   1. POST /api/samples/missing  {hashes}      → {missing: [...]}
   2. PUT  /api/samples/{hash}   (bytes)       para cada faltante
   3. PUT  /api/projects/{id}/doc {base_version, doc}
        200 → {version, updated_at}            (versão nova guardada em sync:<id>)
        409 → {error, version, doc}            (conflito: diálogo; nada é sobrescrito)
sem pendência local ─▶ GET /api/projects/{id}/doc traz a versão mais nova
```

## Contratos

### Rotas da API (`server/src/routes/mod.rs`)

| Rota | Método | Para quê |
|---|---|---|
| `/healthz` | GET | `ok` (usado para esperar o servidor subir). |
| `/api/auth/magic-link` | POST | pede o link por email. |
| `/api/auth/verify` | POST | troca o token do link por sessão. |
| `/api/auth/access-code` | POST | entrada por código (revisão da Play Store). |
| `/api/auth/providers` | GET | quais provedores estão ligados. |
| `/api/auth/oauth/{provider}/start`, `/callback` | GET | fluxo de código no servidor com PKCE do app. |
| `/api/auth/oauth/finish` | POST | o app troca a entrada pronta por uma sessão. |
| `/api/auth/oauth/discord/app`, `/app/finish` | POST | Discord pelo app dele no Android. |
| `/api/auth/refresh`, `/logout`, `/logout-all` | POST | renovar e encerrar sessões. |
| `/api/me` | GET, PATCH, DELETE | conta. |
| `/api/projects` | GET, POST | lista e cria. |
| `/api/projects/{id}` | GET, PATCH, DELETE | um projeto. |
| `/api/projects/{id}/doc` | GET, PUT | documento versionado (sem o limite padrão de corpo do axum; teto de 8 MB no handler). |
| `/api/samples/missing` | POST | dos hashes dados (até 2000), quais o servidor não tem. |
| `/api/samples/{hash}` | GET, PUT | baixa e envia (teto de 512 MB, cota de 4 GB). |
| `/api/jobs` | GET, POST | lista (50 mais recentes) e cria (`kind`: `flac` ou `audio_to_midi`; máx. 10 ativas por conta). |
| `/api/jobs/{id}` | GET | estado, progresso e resultado. |

### Tabelas (`server/schema.sql`)

`users`, `magic_links`, `oauth_states`, `oauth_grants`, `sessions` (contas); `projects` (nome, andamento 20–999, fórmula de compasso, taxa de amostragem); `project_docs` (`version` BIGINT + `doc` JSONB); `samples` (chave `(owner_id, hash)`, `size`); `jobs` (`kind`, `status` em `queued|running|done|failed`, `progress`, `result`). Não há migrations automáticas: mudança de schema vai em `schema.sql` **e** num script idempotente em `db/migrations/`.

### Rotas do app (`app/lib/main.dart`)

Fora do shell e públicas: `/login`, `/entrar` (link do email), `/authorize/callback` (volta do app do Discord). Dentro do `ResponsiveScaffold` (rail lateral a partir de 800 px, barra inferior abaixo): `/`, `/projetos/:id`, `/conta`. Sem sessão qualquer outra rota vai para `/login?from=...`.

### Base da API no app (`app/lib/api/client.dart:36-41`)

`--dart-define=API_BASE=` tem prioridade. Sem ele: na web, a mesma origem quando a porta é 8080 ou o host não é `localhost`; nos demais casos (incluindo o app Android sem `API_BASE`) a produção `https://jopendaw.johnenrique.tech`. Para o app Android falar com o servidor local do Mac: `--dart-define=API_BASE=http://10.0.2.2:8080`.

### Variáveis de ambiente do servidor (`server/.env.example`, `config.rs`)

| Variável | Obrigatória | Efeito |
|---|---|---|
| `DATABASE_URL` | sim (`db::connect`) | Postgres. |
| `PORT` | não (8080) | porta. |
| `JWT_SECRET` | sim, 32+ caracteres | HS256 do acesso. |
| `JMAIL_API_KEY` | sim | chave do app no jmail; `JMAIL_URL` (padrão `http://127.0.0.1:8790`), `MAIL_FROM`, `MAIL_FROM_NAME`. |
| `APP_BASE_URL` | não (`http://localhost:8080`) | origem pública, vai no link do email e no OAuth. |
| `GOOGLE_CLIENT_ID/SECRET`, `DISCORD_CLIENT_ID/SECRET` | pares | sem o par o botão do provedor some. |
| `REVIEW_EMAIL`, `REVIEW_CODE` | os dois ou nenhum; código com 24+ caracteres | conta de demonstração por código. |
| `DATA_DIR` | não (`./data`) | blobs em disco (sem S3) e temporários de upload. |
| `S3_ENDPOINT` | não | liga o S3; então `S3_BUCKET`, `S3_ACCESS_KEY`, `S3_SECRET_KEY` são obrigatórios; opcionais `S3_REGION` (`us-east-1`) e `S3_PATH_STYLE` (`true`). |
| `JOPENDAW_STATIC` | não (`../app/build/web`) | pasta do build web a servir. |

### Armazenamento de áudio

Chave `blobs/<2 primeiros hex do sha-256>/<sha-256>` em disco (`DATA_DIR`) ou no bucket. O objeto é único por conteúdo, mesmo com várias contas tendo o mesmo áudio; o banco (`samples`) diz de quem é e alimenta a cota. Nunca existe blob pela metade (temporário + `rename` em disco; o objeto S3 só aparece após o PUT completo). Docker Compose local: `docker-compose up -d minio minio-init` (S3 em `:9000`, console em `:9001`, bucket `jopendaw`).

## Decisões e por quê

- **Mesmo código para web e Android, motor único.** Um só crate de motor garante que o que soa no navegador soa igual no aparelho, e que o render offline (exportar) é reprodutível: o resultado depende só das chamadas e dos quadros processados (`engine/src/lib.rs`, seção "Render fora de tempo real").
- **Protocolo de chamadas por nome** (`[nome, arg...]`) em vez de uma API tipada por plataforma: o worklet e o Android recebem a mesma lista de dados; adicionar uma chamada é mexer em `api.rs` e no lado Dart, não em três FFIs (ver o checklist em [02-pontes-web-e-android.md](02-pontes-web-e-android.md)).
- **Plugins próprios, sem VST/CLAP**: nenhum dos dois roda em web nem no Android (`CLAUDE.md`).
- **Local primeiro** (seção acima): abre na hora, edita offline e não depende do servidor para soar.
- **Documento como JSONB versionado com concorrência otimista** em vez de operações/CRDT: simples, e o conflito vira uma escolha explícita da pessoa. Colaboração em tempo real está no roteiro, não no código (a rota `/api/ws` só existe no nginx).
- **Áudios endereçados por SHA-256**: deduplicação entre contas e entre projetos, upload idempotente, e o documento só carrega o hash. O SHA-256 é calculado no aparelho (`AudioEngine.sha256Hex`: `host.js` na web, nativo no Android, `crypto` do Dart nos demais sistemas).
- **Hot-patch do backend** (Subsecond via `dx serve --hot-patch`): `main.rs` separa `setup` (frio: env, banco, storage, worker) de `serve` (quente: roteador e HTTP). Por isso nada de `std::env::var` na parte quente, e por isso mudar struct/enum/assinatura exige rebuild completo (`r` no dx). O `Cargo.toml` deliberadamente não tem `[profile.dev.package."*"] opt-level = 3` (o processo cai com "no reactor running").
- **Perfis de compilação por alvo** (`Cargo.toml`): `wasm` com `panic = "abort"` (no worklet não há quem pegue), `android` com `panic = "unwind"` (cada função exportada e a thread de áudio pegam o pânico e viram código de erro ou silêncio), `server` com `unwind` (um pânico num handler derruba só o pedido).
- **Binários compilados ficam no git** (`engine.wasm`, os três `.so`) para que `flutter build` e o build Docker do app não precisem de Rust. O custo é a regra de recompilar e commitar tudo junto (ver [02-pontes-web-e-android.md](02-pontes-web-e-android.md)).

## Como testar

O mapa completo está em [03-build-teste-e-depuracao.md](03-build-teste-e-depuracao.md). Em uma linha por camada:

- Motor: `cargo test -p jopendaw-engine`.
- Ponte Android (crate): `cargo test -p jopendaw-engine-android`.
- App: `cd app && flutter analyze && flutter test`.
- Servidor: `TEST_DATABASE_URL=... cargo test -p jopendaw-server` (sem a variável os testes se pulam e passam).
- Uso real (obrigatório antes de dar uma fase por pronta): app no Chrome via `tool/cdp.mjs` e no emulador Android.

## Armadilhas conhecidas

- **Motor velho no Android.** Mudou algo em `engine/`: recompile e commite `engine.wasm` e os três `.so` juntos, ou o Android fica com o motor antigo (e mudo, se o `apply` for novo).
- **Comentário desatualizado:** `engine/src/lib.rs` (cabeçalho) diz "o Oboe no Android"; o motor usa AAudio carregado por `dlopen` (`engine/android/src/platform/aaudio.rs`). Não confie nesse trecho.
- **`README.md` da raiz desatualizado** (ver acima).
- **CI:** não há `.github/` nem outro pipeline no repositório; nada roda os testes sozinho (não confirmado se existe CI fora do repositório).
- **Cache de estáticos.** Os arquivos do build do Flutter não têm hash no nome (`main.dart.js`, `host.js`, `engine.wasm`); por isso o servidor de desenvolvimento manda `no-cache`, o nginx usa `expires -1` e `sw.js` vai sempre à rede primeiro. Depois de um rebuild, o navegador de teste ainda pode servir host/wasm velhos (ver o passo a passo de limpeza em [03-build-teste-e-depuracao.md](03-build-teste-e-depuracao.md)).
- **Duas abas no mesmo projeto** geram conflito de sincronização legítimo ("mudou em outro aparelho").
- **Motor só no navegador e no Android.** Em outros sistemas (`flutter test` no computador, desktop) `AudioEngine.supported` é falso e as chamadas ficam só em `AudioEngine.log` quando um teste pede (`engine_io.dart`).
- **Sem compensação de latência de efeitos** (PDC): efeitos com lookahead (limitador, sobreamostragem da distorção) atrasam a faixa sem compensação; está declarado no cabeçalho de `engine/src/lib.rs` ("Latência de efeito (lookahead) ainda não é compensada").
