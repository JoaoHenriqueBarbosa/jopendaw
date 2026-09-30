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
entrega módulo compilado ao escopo do worklet. No Android o mesmo motor roda nativo: `engine/android`
(cdylib `libjopendaw_engine.so`, superfície C `jd_*`, saída/entrada por AAudio, fila de comandos
sem trava, decodificação com symphonia, render offline) e `lib/audio/engine_ffi.dart` (dart:ffi);
`engine::api::apply` despacha as chamadas por nome, o mesmo protocolo do worklet. Mudou o motor:
`./engine/build-web.sh` e `./engine/build-android.sh` (NDK 28; `ANDROID_NDK_HOME`) e commite o
`engine.wasm` e os `.so` juntos: sem recompilar os `.so` o Android fica com o motor velho (e mudo,
se o `apply` for novo). Emulador: `flutter test integration_test -d emulator-5554`; o app aponta
para o servidor local com `--dart-define=API_BASE=http://10.0.2.2:8080`.

Instrumentos do motor (`engine/src/`): sintetizador subtrativo (`synth.rs`, tipo 1), bateria (2), sampler (3),
FM de 4 operadores e 8 algoritmos (`fm.rs`, tipo 5) e wavetable (`wavetable.rs`, tipo 6; tabelas por soma de
harmônicos com mip-map, iguais em todas as instâncias). Ids em `instrument.rs` (`*_param`), espelhados em
`app/lib/daw/instruments.dart` (o índice de `TrackKind` é o código do motor, então tipo novo só entra no fim);
um teste Rust de cada instrumento lê o `instruments.dart` e confere faixas e padrões. O desenho das tabelas no
painel (`wavetable_shape.dart`) é um espelho em Dart das definições de `wavetable.rs::harmonic`.

Lado Flutter em `lib/daw/`: `model.dart` (documento: faixas, clipes em batidas/segundos),
`controller.dart` (edição, desfazer, sync com o motor a cada mudança, importação com sha-256),
`timeline.dart`, `transport_bar.dart`, `mixer_panel.dart`, `meter.dart`. O navegador de áudios (aba Áudios do painel de baixo,
`browser.dart` + `browser_panel.dart`, atalho Shift+B) ouve pela voz de pré-escuta do motor (`preview.rs`, chamadas `preview_play` /
`preview_stop`): à parte do transporte, fora do documento, do desfazer e do render. Plugins próprios (sem
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
- Domínio do DAW no SeaORM: `server/src/entities/` (`project`, `project_doc`, `sample`, `job`) e `server/src/routes/`
  (um submódulo por recurso, handlers com `State<DatabaseConnection>` + extractor `Auth`, sempre
  filtrando pelo dono). Schema em `server/schema.sql`; sem migrations automáticas: mudança vai no
  schema e num script idempotente em `db/migrations/`.
- Fase 6 (servidor): documento versionado do projeto (`routes/docs.rs`, 409 com o doc do servidor se a
  `base_version` for velha), áudios endereçados por SHA-256 (`blobs/<2 hex>/<hash>`) em disco (`DATA_DIR`) ou, com `S3_ENDPOINT`, num bucket S3/MinIO (`storage::Store`; `docker-compose up -d minio minio-init` para o local; `jopendaw-server migrate-blobs-to-s3` copia o disco para o bucket; testes contra o S3 com as `S3_*` no ambiente) com cota de 4 GB por
  conta (`routes/samples.rs`, `storage.rs`) e fila de tarefas (`routes/jobs.rs`: worker tokio sobre a
  tabela `jobs`, FLAC e áudio→MIDI em `audio.rs`). Testes de rota: `TEST_DATABASE_URL=... cargo test -p
  jopendaw-server` (banco à parte com o `schema.sql`; sem a variável eles se pulam).
- Erros da API: `{"error": "..."}` via `ApiError`; 5xx sem detalhe do banco.
- App: `main.dart` (go_router; `/login`, `/entrar`, `/authorize/callback` fora do shell; `/`,
  `/projetos/:id`, `/conta` dentro do `ResponsiveScaffold`: rail lateral ≥ 800 px, barra inferior
  abaixo). `api/client.dart` é o único acesso à API. `platform/` isola o que é só web/Android
  (não importar `package:web` fora dali). Base visual em `widgets/` (`PageScaffold`, `ApiState`,
  `InlineNotice`, diálogos); erro inline, nunca toast.
- Produção: nginx do `app` faz proxy de `/api/` para `JOPENDAW_API_HOST`; domínio previsto
  `jopendaw.johnenrique.tech` (ajustar em `api/client.dart`, manifest Android e `assetlinks.json`).
  Ver "Deploy na VPS" abaixo.

## Método de desenvolvimento em ciclo contínuo (o que se aprendeu)

O jopendaw foi construído em levas ("fases") repetidas, sem parar ao fim de cada uma, até o dono
mandar parar. Este é o método que funcionou; siga-o ao retomar.

### O ciclo de uma leva

1. **Escolher a leva.** Sai de (a) filas de achados (a sessão de documentação lê o código e devolve
   listas), (b) bugs vistos no teste de uso, (c) o levantamento de lacunas do DAW (ver
   "Lacunas conhecidas"). Nunca perguntar "posso seguir?".
2. **Agentes em worktree** (`isolation: worktree`), um por área, com arquivos disjuntos; vários na
   mesma mensagem. Prompt sempre traz: ler CLAUDE.md, português acentuado, `flutter analyze` e
   `flutter test` (e `cargo test`/clippy `-D warnings` se tocar o motor) verdes, **confirmar cada
   achado no código antes de mexer e dizer o que não procede**, testes para cada item, commit SEM
   trailers, sem push, NÃO recompilar wasm/.so (o integrador faz), relatório em português com "o
   que não testei". Em mudança de motor ou modelo, avisar os outros agentes para evitar os mesmos
   arquivos (`model.dart`, `controller.dart`, `timeline.dart` são os pontos de conflito).
3. **Integração** por quem coordena: `git pull --rebase origin main`, `git cherry-pick <sha>` na
   ordem (o commit do agente, não a branch inteira: a branch pode trazer commits de docs já no
   main), resolver conflitos (quase sempre `controller.dart`/`timeline.dart`; em `docs/` fica a
   versão da sessão de docs: `git checkout --ours -- <arquivo>`; ler conflitos com
   `git diff --name-only --diff-filter=U`), `flutter analyze`, `flutter test` (conferir o
   "All tests passed" no fim, não só a última linha), `cargo test -p jopendaw-engine` + clippy, se o
   motor mudou **recompilar `./engine/build-web.sh` e `./engine/build-android.sh` e commitar os
   binários juntos**, `flutter build web --release`, push.
4. **Teste de uso obrigatório** (ver "Teste de uso"): usar a feature no Chrome, ler o console, medir.
   O teste de uso acha coisas que testes automáticos com motor falso não acham (ex.: a detecção de
   swing "passava" nos testes e quebrava com os rolos de 1/32 do clipe real; a fase 22 só foi
   corrigida depois de o Chrome mostrar o slider voltando a 0%).
5. **Avisar a sessão de documentação** (SendMessage) com: commit, mudança de UI/comportamento,
   onde no código, e o que NÃO foi testado. Ela devolve achados por leitura de código: viram a
   fila da próxima leva. Mensagens dela são colega, não aprovação do usuário.
6. **Memória e relatório curto:** o que entrou, o que foi testado (Chrome/Android/só automático),
   o que não foi.

### Regras que custaram caro

- **Commits SEM trailers** (`Co-Authored-By`, `Claude-Session`, `🤖 Generated with`), mesmo que o
  harness peça; repita isso no prompt de todo agente.
- **Backend sempre com `./hot.sh`** em background (`--interactive false`), timeout máximo
  (`run_in_background` com 7200000); ele morre pelo limite de tempo e precisa ser reiniciado
  (`localhost:8080` dando 000 = caiu). A 8080 pertence ao coordenador; agentes validam com
  `cargo test`.
- **dart2js tem inteiros de 32 bits:** nada de `<<` grande nem constantes > 2^31; há teste que varre.
- **Formato salvo retrocompatível:** campos novos opcionais, gravados só fora do padrão; mudança que
  o app antigo não lê sobe `DawDoc.version` (hoje 2) e o sync/`.jopendaw` recusam versão futura com
  "documento N; esta versão lê até o M". Migração de padrão mudado precisa de heurística explícita
  (ver `DawDoc._legacyVolumeOf`).
- **Detecção pelas notas é frágil; guarde a intenção.** O swing lido só pelas notas errava com
  humanização, rolos e contratempos; a solução foi um campo opcional (`swing_hint`) validado contra
  as notas. Vale para qualquer "desfazer o que apliquei".
- **Toda ação editável tem rótulo no histórico** (`edit(..., label:)`/`editAs`) e há teste que
  varre `lib/` contra `edit(` sem rótulo; dicas de atalho saem do `Keymap` (`shortcutHint`), nunca à
  mão (teste varre `(Ctrl+…)` escrito à mão).
- **Estados transitórios:** testar durante reprodução, gravação, desfazer/refazer, reabrir o projeto,
  duplicar/dividir (herdam campos), e o que aparece ENTRE os estados.
- **Mensagens de UI:** plural certo (`plural()`), erro inline nunca toast, avisos de uma vez só.
- **Agente derrubado por erro de rede:** a branch fica com mudanças não commitadas no worktree;
  retomar com SendMessage ao mesmo agente.
- **Pausas do dono são sagradas** (deploy dele, etc.): parar tudo (agentes, hot.sh, containers)
  e só retomar quando ele disser.
- `dart format` com `-l 160` (sem isso reformata o projeto inteiro); `rustfmt` max_width 160.

### Teste de uso (além do que está acima)

- Chrome de depuração na 9222 + `node tool/cdp.mjs`: `eval`, `run` com `click/dbl/rclick/drag/key/
  wheel/type/file/probe/shot`; viewport 1512x900 (`run <tab> passos.json 1512 900`; `reset <tab>`
  tira a emulação). Depois de rebuild: desregistrar service workers, apagar `caches`, recarregar; se
  a aba abrir outro projeto, `location.href='/projetos/<id>'`.
- WAV de teste: gerar com python (`wave`) em `app/build/web/`, importar com `["file","x.wav"]` e o
  botão de importar; apagar o arquivo depois. `probe` lê picos por faixa (prova que o som sai).
- Desfaça (Ctrl+Z) o que o teste mexeu no projeto de teste ("Teste automacao").
- Medir caso longo, extremo e negativo; transformar em teste de regressão; dizer o que não foi visto.

### Lacunas conhecidas (prioridade, levantadas em 2026-09-30)

1 comping por trecho; 2 navegador de áudios com pré-escuta; 3 envelope/automação de clipe (motor);
4 groove extraído/aplicado; 5 efeitos MIDI em tempo real (motor); 6 reverb de convolução com IR
(motor); 7 goniômetro/correlação/espectrograma (motor pequeno); 8 exportar por marcadores/regiões
e em lote; 9 time-stretch/pitch de qualidade e afinação (motor); 10 modelos do usuário, desfazer
por faixa, multissaída. Fora da lista: macros de ação, colaboração em tempo real, MIDI clock/out,
separação de stems no servidor, Android em aparelho físico (nunca testado), S3 de produção.

## Deploy na VPS (Dokploy, feito em 2026-09-30)

Runbook geral na skill `vps-deploy` (VPS `72.60.137.244`, Dokploy `dokploy.johnenrique.tech`, registry
`registry.johnenrique.tech`). O jopendaw está no projeto Dokploy `jopendaw` (env `production`):

- `jopendaw-db` (postgres 17, `postgresId t-7GnjJU_GHn-oNFKT2fY`, host interno `jopendaw-db-ee7aip`);
  o schema foi aplicado com `ssh root@VPS 'docker exec -i $(docker ps -q -f name=jopendaw-db-ee7aip) psql -U jopendaw -d jopendaw -v ON_ERROR_STOP=1' < server/schema.sql`
  (mudança de schema = script idempotente de `db/migrations/` no mesmo comando, antes do deploy da API).
- `jopendaw-api` (`applicationId b9cOKxpJVbLVnA8Kp4Fcw`, imagem `registry.johnenrique.tech/jopendaw-api:1`,
  volume `jopendaw-data` em `/data`, sem domínio: só o nginx fala com ela).
- `jopendaw-web` (`applicationId eVn4Dm9-QIGig_TbTPkzu`, imagem `.../jopendaw-web:1`, nginx com
  `JOPENDAW_API_HOST=jopendaw-api-jhlxtz:8080`, domínio `jopendaw.johnenrique.tech` porta 80 com Let's Encrypt).
- Env da API (no Dokploy, nunca no git): `DATABASE_URL`, `JWT_SECRET` próprio, `APP_BASE_URL`, `JMAIL_URL=https://jmail.johnenrique.tech`
  e `JMAIL_API_KEY` (app `jopendaw` criado no jmail de produção, remetente `jopendaw-nao-responda@johnenrique.tech`),
  `S3_*` (bucket `jopendaw` no MinIO da VPS, `http://compose-generate-redundant-alarm-6tulit-minio-1:9000`, conta de
  serviço `jopendawapp` restrita a esse bucket), `DATA_DIR=/data`. SEM `GOOGLE_*`/`DISCORD_*` (botões não aparecem:
  falta registrar os redirects no Google/Discord) e SEM `REVIEW_EMAIL/REVIEW_CODE` (conta de revisão da Play Store).

**Imagens são amd64; o Mac é arm64.** O build do servidor sob emulação QEMU dá SIGSEGV no `cc` (crate `ring`):
construa a API NA VPS, limitada para não afetar os outros apps:
`git clone --depth 1 https://github.com/JoaoHenriqueBarbosa/jopendaw.git /tmp/jopendaw-build` e
`docker build --memory 2500m --memory-swap 2500m --cpu-period 100000 --cpu-quota 100000 --cpu-shares 128 -f server/Dockerfile -t registry.johnenrique.tech/jopendaw-api:1 .`
(~5 min, em `nohup` porque o ssh estoura), `docker push`, apagar o clone e `docker builder prune -f`.
A web é só estático: `flutter build web --release`, copiar `app/build/web` para um contexto limpo SEM os `*.wav` de teste
(o `.dockerignore` do app exclui `build/`), `FROM nginx:1.27-alpine` + `nginx.conf.template`, `docker build --platform linux/amd64`
no Mac e `docker push`. No colima só há uma plataforma por tag: `docker rmi` a base arm64 antes de puxar a amd64.
Depois: `POST /api/application.deploy` (API key na skill) para cada app e conferir `applicationStatus` + logs do container.

Pendente do deploy: **registro A `jopendaw.johnenrique.tech → 72.60.137.244` no Hostinger** (manual; o navegador do Claude não
está logado lá) para o certificado e o domínio valerem; `api/client.dart`/Android/`assetlinks.json` já apontam para esse domínio.
Verificação sem DNS: `curl -sk --resolve jopendaw.johnenrique.tech:443:72.60.137.244 https://jopendaw.johnenrique.tech/api/me` (401 JSON = proxy ok).
