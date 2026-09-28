# CLAUDE.md

## O que é

jopendaw: um DAW completo (em construção). Mesmo desenho do bulkscan (`/Volumes/Projects/bulkscan`):
backend Rust (`server/`, axum + SeaORM sobre Postgres), frontend Flutter (`app/`: build web e app
Android do mesmo código). Emails pelo jmail (`/Volumes/Projects/jmail`).

Prosa (comentários, mensagens de erro da API, textos de UI) em português acentuado;
identificadores em inglês.

## Regra: backend sempre com hot-patch

É imperativo: para rodar, testar ou iterar no backend, o Claude Code usa `./hot.sh` (em background,
com `--interactive false` quando não há TTY), nunca `cargo run` reiniciado a cada mudança. Suba uma
vez, edite e confira pelo log do dx (`Hot-patching: ... took NNNms`) e pela própria API, sem
reiniciar o processo. Rebuild completo só quando o patch não serve: mudou struct, enum ou
assinatura de função, `Cargo.toml` ou o `setup` frio; aí `r` no dx (ou reinicia o `./hot.sh`). Se o
patch falhar ou o processo cair depois dele, investigue e conserte a causa (ver a seção
Hot-patch do backend) em vez de voltar para o `cargo run`.

## Comandos

```bash
docker-compose up -d db                                   # Postgres (colima: use docker-compose)
docker exec -i jopendaw-pg psql -U jopendaw -d jopendaw < server/schema.sql   # schema, 1ª vez
cp server/.env.example server/.env                        # JWT_SECRET e JMAIL_API_KEY obrigatórios
cd server && cargo run                                    # API em :8080 (serve app/build/web se existir)
./hot.sh                                                  # a mesma API com hot-patch do Rust (dx serve)
cd app && flutter build web --release                     # web
cd app && flutter build apk --release -PdiscordClientId=<id>   # Android
docker-compose up --build                                 # tudo: API :8080, web :8081
./engine/build-web.sh                                     # motor → app/web/engine/engine.wasm (commitado)
cargo test -p jopendaw-engine                             # testes do motor
```

O compose não monta o `schema.sql` no initdb porque o colima não enxerga `/Volumes`.
`python3 app/tool/icones.py` regenera os ícones a partir de `app/web/favicon.svg`.

## Motor de áudio (local primeiro)

Tudo o que dá para processar no aparelho é processado lá; o backend fica com sincronização e
tarefas pesadas. O motor é o crate `engine/` (Rust puro, sem plataforma: transporte, clipes,
mixer, metrônomo; testes em `engine/src/lib.rs`). Na web ele roda compilado em WASM
(`engine/wasm/`, funções C sem wasm-bindgen) dentro de um AudioWorklet: `app/web/engine/worklet.js`
hospeda o módulo, `host.js` é a ponte com o Dart (`lib/audio/engine_web.dart`) e guarda documento
e áudios no IndexedDB. O host manda os *bytes* do wasm, não o `WebAssembly.Module`: o Chrome não
entrega módulo compilado ao escopo do worklet. No Android o mesmo crate entra como lib nativa com
Oboe (a fazer). Mudou o motor: `./engine/build-web.sh` e commite o `engine.wasm` junto.

Lado Flutter em `lib/daw/`: `model.dart` (documento: faixas, clipes em batidas/segundos),
`controller.dart` (edição, desfazer, sync com o motor a cada mudança, importação com sha-256),
`timeline.dart`, `transport_bar.dart`, `mixer_panel.dart`, `meter.dart`. Plugins próprios (sem
VST/CLAP, que não rodam em web nem Android). Roteiro: MIDI + instrumentos → efeitos e automação →
gravação e exportação → Android nativo → sincronização e jobs no backend.

## Hot-patch do backend

`./hot.sh` roda a API pelo `dx serve --hot-patch --features hot` (dioxus-cli 0.7.10, chamado por
`~/.cargo/bin/dx` porque o `dx` do Deno vem antes no PATH; o devserver do dx vai para a 8090).
Salvar o corpo de uma função em `server/src` aplica no processo rodando em ~1 s: `main.rs` separa o
`setup` frio (env, log, banco, email, faxina) do `serve` quente (roteador + HTTP), que é recriado a
cada patch. Mudou struct, enum ou assinatura: `r` no terminal do dx (rebuild completo). Nada de
`std::env::var` na parte quente. Não ponha `[profile.dev.package."*"] opt-level = 3` no
`Cargo.toml`: com ele o patch aplica e o processo cai com "no reactor running".

## Teste de uso (obrigatório antes de dar uma fase por pronta)

O teste é usar o app no Chrome, não revisar código. O Flutter desenha em canvas: o MCP
chrome-devtools serve para screenshot, console, JS e emulação de aparelho (`emulate`), mas não
clica em coordenadas; cliques, arrastes, teclas e `probe` vão pelo `node tool/cdp.mjs`, que fala
CDP com o mesmo Chrome de depuração da 9222. Suba o `./hot.sh`, faça o
`flutter build web --release` e rode passos com `run` (clicar, arrastar, teclas com modificadores
reais, screenshots em pixels CSS, `probe` para ler os picos do motor e provar que o som sai).
Arquivos de teste (ex.: um WAV) vão em `app/build/web/` e entram no seletor com `file`. O login
de teste é o código de acesso (`REVIEW_EMAIL`/`REVIEW_CODE` do `server/.env`). Gotchas: a
emulação de viewport fica presa na aba (feche a aba e abra outra para voltar ao desktop); as
permissões vão por `node tool/cdp.mjs grant http://localhost:8080 audioCapture midi midiSysex` em
segundo plano (o Chrome desfaz a concessão quando a sessão do CDP fecha, e o Web MIDI dele só
libera com `midiSysex` junto), o que evita o aviso de permissão que trava a automação; o
`jopendawEngine.injectMidi(status, d1, d2)` simula um aparelho MIDI. O que aparecer, corrija e
teste de novo.

## Arquitetura

- Auth igual à do bulkscan: magic link (`auth.rs`), Google e Discord (`oauth.rs`, fluxo de código no
  servidor com prova PKCE do app; no Android o Discord autoriza no app dele e volta por
  `discord-{id}:/authorize/callback`), código de acesso para a revisão da Play Store. JWT de 15 min +
  refresh opaco rotativo. Contas em SQL direto pelo sqlx no mesmo pool do SeaORM.
- Domínio do DAW no SeaORM: `server/src/entities/` (hoje só `project`) e `server/src/routes/`
  (um submódulo por recurso, handlers com `State<DatabaseConnection>` + extractor `Auth`, sempre
  filtrando pelo dono). Schema em `server/schema.sql`; sem migrations automáticas: mudança vai no
  schema e num script idempotente em `db/migrations/`.
- Erros da API: `{"error": "..."}` via `ApiError`; 5xx sem detalhe do banco.
- App: `main.dart` (go_router; `/login`, `/entrar`, `/authorize/callback` fora do shell; `/`,
  `/projetos/:id`, `/conta` dentro do `ResponsiveScaffold`: rail lateral ≥ 800 px, barra inferior
  abaixo). `api/client.dart` é o único acesso à API. `platform/` isola o que é só web/Android
  (não importar `package:web` fora dali). Base visual em `widgets/` (`PageScaffold`, `ApiState`,
  `InlineNotice`, diálogos); erro inline, nunca toast.
- Produção: nginx do `app` faz proxy de `/api/` para `JOPENDAW_API_HOST`; domínio previsto
  `jopendaw.johnenrique.tech` (ajustar em `api/client.dart`, manifest Android e `assetlinks.json`).
