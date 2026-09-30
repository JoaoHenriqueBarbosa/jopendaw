# Processo de construção e histórico por fase

> Como o jopendaw é construído (contrato, agentes em paralelo, integração, teste de uso, correção), as regras do dono que valem para qualquer contribuição e a cronologia das fases 1 a 7 montada do `git log`, com os defeitos que só o uso revelou. Para quem vai continuar o trabalho, humano ou agente.

Fontes: `git log` do repositório (61 commits em 28 e 30/09/2026), `CLAUDE.md` da raiz, o `CLAUDE.md` global do dono e as anotações de processo do dono (memória do projeto, fora do repositório). O que só aparece nas anotações e não no `git` está marcado `(fonte: notas do dono)`. Horários são os do git (`%ad`, data de autoria; commits integrados depois por `cherry-pick` têm data de commit posterior: isso aparece na fase 5).

## Visão geral

Cada "fase" é uma onda de recursos entregue assim:

```
   ┌────────────────────────────────────────────────────────────────────────────────────────────┐
   │ 1. CONTRATO   commit "wip: contrato da fase N" no main (ids, tabelas, modelo, assinaturas)   │
   └───────────────────────────────────────────┬────────────────────────────────────────────────┘
                                               ▼
   ┌────────────────────────────────────────────────────────────────────────────────────────────┐
   │ 2. AGENTES    um por área, cada um num git worktree próprio, com arquivos disjuntos          │
   │               (motor / dsp / controlador / UI ...): fmt, clippy, analyze, test verdes,      │
   │               commit sem trailers, branch faseN/<nome>, sem push, sem recompilar binários    │
   └───────────────────────────────────────────┬────────────────────────────────────────────────┘
                                               ▼
   ┌────────────────────────────────────────────────────────────────────────────────────────────┐
   │ 3. INTEGRAÇÃO cherry-pick na ordem, resolver conflitos, RECOMPILAR engine.wasm e os .so,     │
   │               rodar tudo, flutter build web --release, commit "chore: integra a fase N"      │
   └───────────────────────────────────────────┬────────────────────────────────────────────────┘
                                               ▼
   ┌────────────────────────────────────────────────────────────────────────────────────────────┐
   │ 4. TESTE DE USO  usar o app no Chrome (e no emulador Android quando algo roda lá),           │
   │               medir, testar os dois lados, casos longos e negativos                          │
   └───────────────────────────────────────────┬────────────────────────────────────────────────┘
                                               ▼
   ┌────────────────────────────────────────────────────────────────────────────────────────────┐
   │ 5. CORREÇÃO   o que apareceu é corrigido no mesmo ciclo: commit "fix: achados do teste de    │
   │               uso da fase N"; push no main; e já começa a fase seguinte (ciclo sem fim)      │
   └────────────────────────────────────────────────────────────────────────────────────────────┘
```

## Peças e responsabilidades

| Peça | Papel |
|---|---|
| `CLAUDE.md` (raiz) | regras do projeto, comandos, arquitetura, a seção "Teste de uso" |
| `~/.claude/CLAUDE.md` (global do dono) | regra dos commits sem trailers, vale para todos os projetos |
| `.claude/worktrees/` | onde ficam os worktrees dos agentes (ignorado pelo git; `.gitignore`, commit `160b7f5`) |
| `engine/build-web.sh`, `engine/build-android.sh` | recompilam `app/web/engine/engine.wasm` e os `.so` do Android; o integrador roda, nunca o agente |
| `tool/cdp.mjs` | cliente CDP mínimo para testar o app no Chrome de depuração (:9222): cliques por coordenada, teclas com modificadores, arrastos, screenshots, `probe` do motor, concessão de permissões |
| `hot.sh` | backend com hot-patch (ver [11 Servidor](11-servidor.md)) |
| Testes de contrato | leem o Rust e comparam com o Dart (ids e faixas de parâmetros, exports do wasm × chamadas do controlador): pegam divergência entre agentes cedo (ver [10 App Flutter](10-app-flutter.md)) |

## Fluxo, passo a passo

### 1. Contrato (feito pelo integrador, antes dos agentes)

Escrito e enviado ao `main` como `wip: contrato da fase N`. Contém o que os agentes precisam para trabalhar sem se esperar: trait e ids no motor (`engine/src/effect.rs`, `instrument.rs`, `api.rs`), a tabela espelhada em Dart (`instruments.dart`, `effects.dart`), campos novos do modelo (`model.dart`), assinaturas do controlador com `UnimplementedError`, esqueletos que compilam. Os worktrees dos agentes partem desse commit (o agente faz `git merge --ff-only <sha>` se o worktree estiver atrás). Commits `wip:` existentes: `3f91b9a` (fase 2), `8e0efe7` (3), `1fd29e1` (4), `a1477ad` (5).

### 2. Agentes em worktrees com arquivos disjuntos

Um agente por área (as áreas dos commits da fase 3, por exemplo: cadeia e barramentos no motor, EQ e dinâmica, modulação e espaço, distorção e filtro, controlador, rack de efeitos, mixer, automação na linha do tempo), cada um em `isolation: worktree`. Regras fixas no prompt: prosa em português acentuado; `fmt`, `clippy`, `analyze` e `test` verdes; **commit sem trailers**; `git branch -f faseN/<nome>`; **sem push**; relatório curto; **não recompilar `engine.wasm` nem os `.so`**. Áreas disjuntas evitam conflito; quando há sobreposição, é quase sempre em `timeline.dart` e `controller.dart` (imports e áreas vizinhas). `(fonte: notas do dono)`

Fases 2 a 5 foram rodadas com Workflow (fases Implementar → Integrar) quando o modo estava ligado; sem ele, vários agentes na mesma mensagem. `(fonte: notas do dono)`

### 3. Integração

Por `cherry-pick` dos branches na ordem, resolvendo conflitos; **recompilar os binários**; rodar tudo (`cargo fmt --all --check`, `cargo clippy ... -D warnings`, `cargo test`, `flutter analyze`, `flutter test`); `flutter build web --release`; commit `chore: integra a fase N` e push. O integrador acha o que os agentes não podiam ver: o motor do agente tinha o **esqueleto** em vez da implementação, ou o `.so` do agente sem o despachante deixava tudo mudo (commit `c379259`).

Regra dura: **binários nunca vêm dos agentes.** `engine.wasm` e os três `.so` (`arm64-v8a`, `armeabi-v7a`, `x86_64`) são recompilados pelo integrador e commitados **juntos** com a mudança do motor; sem recompilar os `.so`, o Android fica com o motor velho (e mudo, se a chamada `apply` for nova).

Depois de integrar: `git worktree unlock` e `remove --force` dos worktrees, e apagar os branches `faseN/*` e `worktree-agent-*`. `(fonte: notas do dono)`

### 4. Teste de uso

O teste é **usar o app**, não revisar código. A seção "Teste de uso" do `CLAUDE.md` descreve o caminho: subir o `./hot.sh`, `flutter build web --release`, e conduzir o Chrome de depuração pelo `tool/cdp.mjs` (o Flutter desenha em canvas: não há DOM para clicar por seletor) e/ou pelo Claude in Chrome. Detalhes em "Como testar" abaixo.

### 5. Correção e push

O que aparecer é corrigido pelo próprio integrador, com commit `fix: achados do teste de uso da fase N` (lista com os achados no corpo). Push no `main`. Sem parar para perguntar se pode seguir: o mandato do dono é o **ciclo sem fim** (implementar, testar, corrigir, propor a próxima leva, até ele mandar parar). Pausas dele ("pausa tudo, vou fazer um deploy") são sagradas: parar workflow, `hot.sh`, containers e daemons Gradle e só voltar quando ele avisar. `(fonte: notas do dono)`

### Convenção de commits observada

Mensagens em português, prefixo no estilo Conventional Commits, corpo em prosa explicando o porquê e o que foi medido. Contagem do histórico: `feat` 36, `fix` 9, `chore` 8, `wip` 4, `docs` 3 e 1 merge (`knobs-automacao`), todos do mesmo autor. **Nenhum commit tem trailer de assinatura** (verificado: zero ocorrências de `Co-Authored-By`, `Claude-Session` ou `Generated with` em `git log --format=%B`).

| Prefixo | Uso |
|---|---|
| `wip: contrato da fase N` | o contrato antes dos agentes |
| `feat(motor)`, `feat(app)`, `feat(server)`, `feat(engine,app)`, `feat(warp)`, `feat(mixer)`, `feat(timeline)` | trabalho dos agentes, por área |
| `chore: integra a fase N` | integração: cherry-picks, binários recompilados |
| `fix: achados do teste de uso da fase N` | resultado do teste de uso |
| `docs:` | `CLAUDE.md` e a pasta `docs/` |

## Regras do dono

Estas regras valem para qualquer contribuição; nasceram de experiências ruins.

1. **Nunca adicionar trailers de assinatura** (`Co-Authored-By: Claude ...`, `Claude-Session: ...`, `Generated with Claude Code`) em commits nem em corpos de PR, em nenhum projeto. Vale mesmo quando o ambiente de execução pede esses trailers: a regra do dono vence. A mensagem termina no último parágrafo do corpo. Quem escreve prompts de agentes repete isso neles. (`~/.claude/CLAUDE.md`)
2. **Backend sempre com `./hot.sh`** (em background, `--interactive false` sem TTY), nunca `cargo run` reiniciado a cada mudança. Rebuild completo só quando o patch não serve (struct, enum, assinatura, `Cargo.toml`, `setup`). Patch que falha ou processo que cai depois dele: investigar a causa, não voltar ao `cargo run`. A 8080 é do `main`; agentes em worktree validam com `cargo test`, não sobem servidor. (`CLAUDE.md`)
3. **Teste de uso em vez de revisão de código.** Toda fase só está pronta depois de usada no navegador, e no emulador Android quando mexe em algo que roda lá. O dono trocou uma revisão adversarial de código por "teste no Chrome, teste completamente tudo: o uso revela o que a revisão revelaria muito mais rápido; o que surgir, corrija e siga". (`CLAUDE.md`; `(fonte: notas do dono)` para as palavras)
4. **Sem buracos de teste.** Medir de verdade: clipes **longos** (o detector de andamento foi testado só com 4 s e o dono mandou repetir com clipe longo), casos **extremos** e **negativos** (ruído, pad e tom puro devem ser recusados), e transformar o achado em teste de regressão. Dizer com honestidade o que **não** foi testado. `(fonte: notas do dono)`
5. **Testar os dois lados de um fluxo.** Sincronização, por exemplo: criar e editar num aparelho, ver no outro, editar de volta. `(fonte: notas do dono)`
6. **Efeitos temporais.** Ao mexer em carregamento, animação ou estado transitório, raciocinar sobre o que aparece **entre** os estados e tirar screenshots em sequência, não só do estado final (o spinner que parava antes de tudo carregar foi achado assim). `(fonte: notas do dono)`
7. **Comportamento estranho: investigar até entender** e distinguir defeito do produto de defeito do harness de teste antes de concluir. `(fonte: notas do dono)`
8. **Português do Brasil com acentos** em prosa, comentários, mensagens de erro da API e textos de UI; identificadores em inglês. Estilo: `rustfmt` com `max_width` 160 e `dart format -l 160`. (`CLAUDE.md`)
9. **Nada na VPS ou na produção sem o dono.** Deploys e credenciais (MinIO da VPS) são dele. `(fonte: notas do dono)`

## Como testar (o teste de uso)

Passos do `CLAUDE.md`, mais os detalhes acumulados:

```bash
docker-compose up -d db                       # Postgres (colima: use docker-compose)
docker-compose up -d minio minio-init         # opcional: S3 local
./hot.sh --interactive false > $LOG 2>&1 &    # API + web em :8080; aguardar /healthz
until curl -sf localhost:8080/healthz; do sleep 3; done
cd app && flutter build web --release         # o servidor serve app/build/web
node tool/cdp.mjs run <tabId> passos.json     # clicar, arrastar, teclas, shots, probe
```

- **Login de teste:** o código de acesso (`REVIEW_EMAIL` e `REVIEW_CODE` do `server/.env`; na tela de login, "Tenho um código de acesso"). Não repetir o código em relatórios.
- **O que o `tool/cdp.mjs` faz:** `open`, `tabs`, `eval`, `shot`, `click`, `key` (mods: 1 alt, 2 ctrl, 4 meta, 8 shift), `drag`, `grant` (permissões do CDP só valem enquanto a sessão que as concedeu está aberta: rodar em segundo plano durante o teste, com `audioCapture midi midiSysex`), `reset` e `run` (passos em JSON: `click`, `dbl`, `rclick`, `down/move/up`, `drag`, `wheel`, `type`, `key`, `wait`, `shot`, `eval`, `probe`, `file`). Coordenadas em pixels CSS.
- **Provar que o som sai sem ouvir:** `jopendawEngine.probe()` (posição, estado e picos por faixa, master por último). `jopendawEngine.injectMidi(status, d1, d2)` simula um aparelho MIDI. Microfone falso: sobrescrever `navigator.mediaDevices.getUserMedia` com um oscilador, para não abrir o prompt do macOS.
- **Importar áudio de teste:** arquivos em `app/build/web/` entram no seletor com `file` no `run`; ou, no Claude in Chrome, sobrescrever `HTMLInputElement.prototype.click` com um `File` vindo de `fetch('/arquivo.wav')`. `(fonte: notas do dono)`
- **Cache depois de rebuild:** remover service workers e `caches`, e recarregar `/engine/host.js`, `/engine/engine.wasm` e `/main.dart.js` com `cache: 'reload'`; sem isso aparecem erros como `detectBpm is not a function`. O servidor de desenvolvimento manda `no-cache` desde `f1cfbaa`.
- **Emulação de viewport** fica presa na aba: feche a aba e abra outra para voltar ao desktop.
- **Android:** emulador `Galaxy_S24_Plus_API36` (`-no-snapshot-save -no-audio`); `flutter test integration_test -d emulator-5554`; o app aponta para o servidor local com `--dart-define=API_BASE=http://10.0.2.2:8080`; `adb shell pm clear tech.johnenrique.jopendaw` simula aparelho novo. Coordenadas de toque = imagem exibida × 1,56 (tela 1440×3120). O `SIGABRT` do bluetooth no logcat do emulador é ruído. `(fonte: notas do dono)`
- **Armadilha do build em segundo plano:** nunca rodar `( flutter build ... ) &` dentro de um comando em background: a notificação de "concluído" vem quando o shell externo sai, não quando o build termina, e o APK velho foi instalado. Rodar o build direto em background e conferir tamanho e hash do APK. (Custou uma regravação de `fm`/`wavetable` como `audio` pelo app velho.) `(fonte: notas do dono)`
- **Duas abas do Chrome no mesmo projeto** geram conflito de sincronização legítimo.

## Cronologia por fase

Números entre parênteses: arquivos alterados e linhas inseridas (`git show --shortstat`). "Autoria" é o horário do commit original.

### Fase 0: ponto de partida (28/09)

| Commit | O que fez |
|---|---|
| `bb16dc1` 09:24 | `feat: scaffold do jopendaw` (94 arquivos, +9 796): autenticação por magic link, Google e Discord, projetos com CRUD, layout responsivo, build web e Android, docker-compose e hot-patch. No mesmo desenho do bulkscan (`CLAUDE.md`) |

### Fase 1: motor de áudio e arranjo (28/09, 09:24 a 10:36)

| Commit | O que fez |
|---|---|
| `2f1844f` 10:36 | motor em Rust (`engine/`: transporte, clipes de áudio, mixer com volume, pan, mudo, solo e picos, loop, metrônomo) compilado para WASM (`engine/wasm/`, funções C sem wasm-bindgen) e hospedado num AudioWorklet; no Flutter, `lib/daw/`: documento guardado no IndexedDB, importação de áudio, linha do tempo com onda, mover, aparar, fade, cortar, duplicar, desfazer, grade, zoom, régua com loop e o mixer (27 arquivos, +3 254) |
| `51dc74c` | clippy limpo no motor wasm |

### Fase 2: instrumentos e MIDI (28/09, 11:22 a 12:58)

Contrato `3f91b9a` (+826): trait `Instrument`, ids de parâmetros, ADSR compartilhado, esqueletos; tabela espelhada, modelo MIDI e assinaturas do controlador, do piano roll e do painel.

| Commit | Área | O que fez |
|---|---|---|
| `b1a815b` | motor | faixas com tipo e instrumento, notas do sequenciador disparadas no quadro exato, sampler completo (16 vozes, Hermite, antialiasing), mixer com ganho suavizado, clipes reamostrados (+1 743) |
| `e2a0840` | motor | sintetizador subtrativo: 2 osciladores com anti-aliasing (polyBLEP), uníssono de até 7 cópias, sub e ruído, SVF TPT, 2 ADSR, LFO, polifonia de 1 a 16 com roubo de voz, mono legato (+1 896) |
| `b6f1921` | motor | bateria sintetizada de doze peças, sem samples (+1 551) |
| `d46c20e` | app | controlador: sync de instrumentos e notas, clipes MIDI, teclado do computador, Web MIDI (+1 390) |
| `e5b8604` | app | painel de instrumento, `Knob`, presets (+3 184) |
| `73fe9e5` | app | piano roll pintado por `CustomPainter` (+2 927) |
| `dca6064` | app | MIDI e instrumentos na tela do projeto: arranjo, painel de baixo, transporte (+1 366) |
| `dcd81d2` | integração | `engine.wasm` recompilado com os três instrumentos; testes do piano roll contra o controlador de verdade e conferência de que toda chamada do controlador existe no wasm |
| `160b7f5` | | ignora os worktrees dos agentes |
| `b7e1e9c`, `9806c01` | uso | achados do teste de uso (ver defeitos) |
| `834a917` | docs | teste de uso pelo Chrome (`tool/cdp.mjs`) no `CLAUDE.md` |

### Fase 3: efeitos, barramentos e automação (28/09, 13:02 a 14:47)

Contrato `8e0efe7` (+1 052): trait `Effect`, ids dos 12 efeitos, faixa barramento, `effects.dart`, modelo de slots, envios, lanes e master, painel de efeitos.

| Commit | Área | O que fez |
|---|---|---|
| `a0ccab4` | motor | cadeias de inserts (até 16 slots) por faixa e no master, barramentos, envios pré e pós, sidechain, automação em lanes, analisador de espectro (+2 523) |
| `b243f0e` | motor | EQ de 8 bandas, compressor, gate, limitador com lookahead, utilitário (+2 681) |
| `45dacd8` | motor | reverb FDN de 8 linhas, delay, chorus/flanger, phaser, tremolo (+2 575) |
| `911b5cf` | motor | distorção (6 tipos, sobreamostragem até 4×) e filtro (+1 903) |
| `9767c88` | app | controlador: sync incremental de cadeias, envios, saídas, automação e observação (+1 457) |
| `e938f9c` | app | rack de efeitos, editores (EQ com gráfico de resposta, dinâmica com curva de transferência) e presets (+3 903) |
| `2ed997c` | app | mixer com inserts, envios, saída e barramentos; aba Efeitos (+1 294) |
| `75e994c` | app | sub-raias de automação na linha do tempo e no master (+2 172) |
| `795bf8d` | integração | `engine.wasm` recompilado com os 12 efeitos; teste de contrato que lê `effect.rs` e confere ids, nomes, faixas, códigos de `fx_set` e `NOTE_BEATS` contra `effects.dart` |
| `fb2ff08`, `df068f4` | uso | achados do teste de uso (ver defeitos) |

### Fase 4: gravação, exportação e congelamento (28/09, 14:49 a 16:01)

Contrato `1fd29e1`: faixa armada/monitorando, tomadas, contagem e compensação de latência no documento; opções de exportação; assinaturas do controlador e da ponte.

| Commit | Área | O que fez |
|---|---|---|
| `33963f6` | motor | entrada monitorada, registro de notas ao vivo (até 16 mil), capturas para o render alinhadas à linha do tempo (+1 128) |
| `ab6a79b` | ponte web | entrada do microfone no worklet, captura, render fora de tempo real num Worker (`render-worker.js`), `saveFile` (+1 132) |
| `c04b9e7` | app | controlador: gravar (contagem, latência, tomadas em loop, MIDI com overdub), exportar, congelar; `wav.dart` com dither TPDF (+2 872) |
| `f4549cb` | app | interface: botão Gravar, exportar, configurações, entrada, medidor (+1 669) |
| `64efd92` | app | gravação, tomadas e congelar na linha do tempo (+801) |
| `e029956` | integração | liga `onCaptureEnd`, acerta nota segurada partida por salto do transporte, entrada perdida, cancelar render, render só do master alinhado; `cdp.mjs grant` |
| `3563f17` | uso | achados do teste de uso (ver defeitos) |

### Fase 5: motor nativo no Android (contrato e agentes em 28/09; integração em 30/09)

| Commit | O que fez |
|---|---|
| `a1477ad` 09-28 16:03 | contrato: despachante por nome no crate do motor |
| `2ac14c8` 09-28 16:18 (commit 09-30 06:19) | `engine::api::apply`: todas as chamadas sem ponteiro do worklet, mesma semântica de conversão do JavaScript, `Call::parse` separado de `Call::apply` (sem heap, para a fila sem trava); teste que confere a tabela contra os exports do wasm (+906) |
| `e6e19ce` (commit 09-30 06:19) | `engine/android`: superfície `jd_*`, saída e entrada por AAudio, fila de comandos, captura, render offline, decodificação com symphonia, `.so` dos três ABIs (+4 787) |
| `1f35fa2` (autoria 09-28 16:36) | lado Dart: `engine_ffi.dart` (dart:ffi), `LocalStore` em arquivos, render em isolate (+2 899) |
| `380aec0` (autoria 09-28 16:29) | Android pronto: `RECORD_AUDIO`, `minSdk 26`, `MainActivity` carrega a lib, testes de integração (+816) |
| `c379259` 09-30 06:25 | **integra a fase 5**: `.so` recompilados com o despachante integrado (os do agente tinham o esqueleto e tudo saía mudo); no emulador, 10 testes de integração passam e o app abre, loga e abre projeto no motor nativo |
| `7c92db5`, `d7faac9`, `e5e1d4e` | (branch `knobs-automacao`, merge `ea107fa`) knobs de instrumento e de efeito que seguem a automação tocando; modelos de projeto (vazio, batida eletrônica, gravação de banda); janela de atalhos (`?`) |
| `9463dc4` | `CLAUDE.md`: motor nativo no Android |

### Fase 6: servidor, sincronização e áudio para MIDI (30/09, 06:54 a 07:14)

| Commit | O que fez |
|---|---|
| `5195284` app | `SyncService` (local primeiro, debounce de 3 s, recuo de 2 s a 2 min, conflito com diálogo), indicador na barra, `ApiClient` com documento, samples e jobs atrás da interface `SyncApi`, "Converter em notas (MIDI)" (+1 542) |
| `a1afc57` servidor | documento versionado em JSONB (409 com a versão do servidor), áudios por SHA-256 com cota de 4 GB por conta, fila de jobs (FLAC 24 bits e áudio para MIDI por YIN), faxina, schema e migração idempotente, testes de rota (+2 058) |
| `8bde870` | volume persistente para os áudios (`DATA_DIR=/data` no container e no compose) |
| `6e41240` | `fix`: sem documento local, o spinner só termina depois da primeira sincronização (espera de até 25 s) |
| `d425497` | armazenamento dos áudios em S3 compatível (MinIO) com disco de fallback, subcomando `migrate-blobs-to-s3`, MinIO no compose, testes de rota nos dois backends (+815) |

### Fase 7: estrutura, ferramentas MIDI, warp e instrumentos novos (30/09, 07:11 a 07:47)

| Commit | O que fez |
|---|---|
| `62a14ae` | marcadores na régua, seções, minimapa, enquadrar, régua em mm:ss, loops por seção e entre marcadores (+1 218) |
| `b7315ca` | ferramentas MIDI de produtor: escala por clipe, acordes, arpejador, humanizar, legato, staccato, dividir, unir e mais (`midi_tools.dart`) (+2 139) |
| `6fe498e` | warp: WSOLA de 40 ms, transposição, inversão, detecção de andamento por autocorrelação do envelope de onsets (60 a 200 BPM); `WarpCache` (+1 721) |
| `4184c4f` | integra a fase 7 parcial: `engine.wasm` e `.so` recompilados |
| `02ea5a7` | instrumentos FM (4 operadores, 8 algoritmos, índice limitado pela regra de Carson) e wavetable (3 séries de 8 tabelas com mip-map); 15 presets de FM e 17 de wavetable (+4 607) |
| `8e3c6a6` | integra FM e wavetable (binários recompilados) |
| `f1cfbaa` | fix: detector de andamento recusa o que não tem batida; cache do servidor de desenvolvimento |
| `9a790a2` | fix: seletor de presets com largura fixa e rótulo `Inicial` |
| `924bac4` | docs: índice, guia de estilo e changelog da documentação |

### Fase 8 (em andamento; fora do `main`)

Não faz parte do histórico do `main`. Quatro worktrees de agentes existem em `.claude/worktrees/` (`git worktree list`), dois com commits ainda não integrados: `30e606a feat(app): exportar e importar o projeto inteiro como arquivo .jopendaw` (branch `fase8/arquivo`) e `c81f8d5 feat(engine): zonas do sampler (multi-sample, camadas, round-robin, loop) e fatiamento de loops`. Segundo as notas do dono, a leva reúne LUFS e true-peak com normalização na exportação, expressão MIDI (pitch bend, mod wheel, sustain, faixas de CC), projeto em arquivo e sampler multi-zona. `(fonte: notas do dono; estado de 30/09/2026)`

## Defeitos notáveis achados no uso, e como foram corrigidos

Todos vieram do teste de uso ou da integração, não de revisão de código (a coluna Commit tem a correção).

| Fase | Sintoma no uso | Causa | Correção | Commit |
|---|---|---|---|---|
| 2 | a soma das faixas saía com clipping duro | sem proteção no master | limitador de segurança no master (−0,3 dBFS, lookahead de 1,5 ms); o medidor do master mede depois dele | `b7e1e9c` |
| 2 | onda dos clipes e miniatura das notas perdiam o começo | `getLocalClipBounds` vem deslocado no Flutter web | o recorte usa a posição do clipe na janela | `b7e1e9c` |
| 2 | desfazer mexia no metrônomo e no liga/desliga do loop | preferências estavam no documento restaurado | `_travel` restaura essas preferências do estado atual | `b7e1e9c` |
| 2 | piano roll: colar empilhava sobre as notas copiadas; rolava para depois do fim tocando; clipe de bateria vazio abria fora do bumbo | vários | corrigidos (cada um no piano roll) | `b7e1e9c` |
| 2 | clipes sobrepostos tocavam somados | nada recortava o que ficava embaixo | clipe colocado por cima recorta o que cobre (encurta, apara, parte em dois ou some), no fim do arraste e ao duplicar | `9806c01` |
| 2 | o menu do navegador abria por cima do menu dos clipes | o piano roll religava o menu ao fechar | quem desliga e religa é a tela do projeto, pelo tempo em que ela está aberta | `dcd81d2` |
| 3 | limitador com teto em −6 dB abaixava tudo 6 dB sem limitar nada, medidor em zero | o teto era um volume de saída | o teto é o limiar (abaixo dele o som passa intacto) | `fb2ff08` |
| 3 | fade do master desfeito pelo limitador ou compressor da cadeia; cadeia depois do fader | cadeia do master rodava depois do volume | a cadeia roda antes do volume, como nas faixas | `fb2ff08` |
| 3 | curva do EQ dos filtros de 24 e 48 dB/oit desenhada errada (−6/−12 dB no corte) | desenho como estágios iguais | desenhada como o motor monta (seções de Butterworth, −3 dB no corte, Q 0,71); conferido contra o motor em todos os tipos | `fb2ff08` |
| 3 | espectro numa taxa errada | fixo em 48 kHz | usa a taxa real do motor | `fb2ff08` |
| 3 | automação: o que se desenhava reto soava curvo (volume despencava no fim, Hz subia quase tudo no começo) | interpolação linear no valor | interpolação na escala do controle (curva do fader, logarítmica em Hz e segundos); o motor recebe pontos a cada 1/8 de batida nesses segmentos (`automation_math.dart`) | `df068f4` |
| 3 | todo estado do motor quebrava no Chrome | o dart2js despacha o callback pelo número de argumentos e o host mandava 3 | argumentos opcionais no callback do estado (medidor e espectro) | `9767c88` |
| 4 | gravação em loop: a tomada tocada de primeira não era a esperada | regra de escolha da tomada ativa (o commit descreve só a regra nova) | a ativa é a última passada **completa**; a de quem parou no meio fica guardada, mas não toca de primeira | `3563f17` |
| 4 | gravando com o transporte andando, o clipe começava fora do lugar | usava a posição que a tela tinha no clique | começa na batida exata do primeiro quadro capturado (`recordBeat`) | `3563f17` |
| 4 | gravações longas travavam a tela | cálculo do sha-256 fora do WebCrypto (deduzido do commit) | sha-256 pelo WebCrypto no navegador | `3563f17` |
| 4 | faixa nova numerada errado (`Áudio 6`) | contava faixas de todos os tipos | numera entre as do mesmo tipo (`Áudio 2`) | `3563f17` |
| 4 | (integração) notas gravadas não chegavam; nota segurada duplicava na volta da contagem | ponte e controlador com nomes diferentes (`onCaptureEnd` × `onRecordedNotes`); salto do transporte | controlador ouve `onCaptureEnd`; o motor parte a nota no salto e ela volta a ser uma só | `e029956` |
| 5 | (integração) app Android todo mudo | `.so` do agente do motor nativo tinha o esqueleto do despachante | `.so` recompilados na integração | `c379259` |
| 6 | abrir no Android um projeto que só existia no servidor mostrava uma faixa vazia que depois trocava por tudo de uma vez | o `open` não esperava a sincronização | espera até 25 s pelo documento e áudios do servidor (só sem documento local e sem modelo); offline abre vazio | `6e41240` |
| 7 | detector de andamento dava 117,9 BPM com confiança 0,71 para pad, tom puro e ruído; o teste original era um trecho de 4 s | o detector não exigia onsets claros nem periodicidade real | exige onsets claros (razão pico/média, densidade) e periodicidade real; testes com clipes longos: exato de 75 a 140 BPM, erro de oitava nos extremos (65, 170, 190) coberto e documentado | `f1cfbaa` |
| 7 | o app novo rodava com `host.js` e `engine.wasm` velhos no navegador | o servidor de desenvolvimento não mandava `Cache-Control` e o navegador guardava por tempo heurístico | `no-cache` nos estáticos (o nginx de produção já tinha) | `f1cfbaa` |
| 7 | seletor de presets "andava" a cada nome; faixa recém-criada dizia "Personalizado" | largura variável; rótulo | largura fixa e rótulo `Inicial` | `9a790a2` |

Achados que não viraram commit de código, só de processo `(fonte: notas do dono)`: o APK velho instalado por engano regravou `fm` e `wavetable` como `audio` no documento local (tipo desconhecido vira `audio` na leitura: ver [10 App Flutter](10-app-flutter.md)); duas abas do Chrome no mesmo projeto geram conflito de sincronização legítimo.

## Estado e lacunas conhecidas (30/09/2026)

`(fonte: notas do dono, exceto onde indicado)`

- **Testado no Chrome:** todas as fases; FM e wavetable (todos os presets soam, picos > 0), ferramentas MIDI (acorde, arpejo, inverter, ×2 no tempo, humanizar), detector de andamento (90 BPM com 88% de confiança num clipe longo; o pad é recusado).
- **Testado no Android (emulador):** motor nativo (10 testes de integração), login, abrir projeto, sincronização Chrome ↔ Android nos dois sentidos, FM e wavetable sincronizados.
- **Nunca testado:** Android físico, microfone real e MIDI real no aparelho.
- **Limites conhecidos:** sem compensação de latência entre faixas (a distorção soma 0,67 ms e o limitador, o lookahead); o cache `warp:` do aparelho não tem limpeza; a automação de parâmetros só toca com o valor fixo quando parado; barramento só manda para barramento de índice maior; MinIO da VPS ainda sem credenciais fornecidas (o backend S3 está pronto).
- **Roteiro (ideias, não compromissos):** separação de stems e áudio → MIDI polifônico no servidor, colaboração em tempo real, mapa de andamento e compasso, LUFS e true-peak, MIDI CC e pitch bend, sampler multi-zona e fatiamento, compensação de latência (PDC), pastas de faixa, exportar MP3/AAC (job), projeto em arquivo, Android físico.

## Decisões e por quê

- **Contrato primeiro.** Sem o contrato commitado, agentes em paralelo inventam ids e assinaturas diferentes; com ele, cada um trabalha numa área e a integração vira cherry-pick.
- **Arquivos disjuntos e worktrees.** Elimina conflito de merge por construção; os poucos conflitos que sobram são de imports em `timeline.dart` e `controller.dart`.
- **Binários só na integração.** O agente do motor compila num estado que não tem o resto; o `.wasm` e os `.so` só valem quando todo o motor está junto (a lição do `c379259`).
- **Testes de contrato que leem o outro lado.** Ids de parâmetro, exports do wasm, códigos de efeito: a divergência entre agentes aparece como teste vermelho, não como botão que move o parâmetro errado.
- **Teste de uso no lugar de revisão.** O uso revela o que a leitura não vê (o master sem limitador, a curva de automação, o callback do dart2js), e cada achado vira teste de regressão.
- **Medir antes de mexer.** Os limiares do detector de andamento saíram dos números do envelope de onsets, não de palpite.

## Armadilhas conhecidas

- **Trailers vêm do ambiente, não do dono.** O ambiente de execução do agente pode pedir `Co-Authored-By`/`Claude-Session` no commit e um rodapé em PRs; a regra do dono é nenhuma, sempre. Conferir a mensagem antes de commitar.
- **Sessões paralelas no mesmo repositório.** A documentação (`docs/`) e o código (`app/`, `engine/`, `server/`) evoluem em sessões diferentes: quem escreve documentação não edita o código e não commita (o coordenador commita); antes de publicar, `git pull --rebase`. Em 30/09/2026 o `origin/main` estava um commit atrás do `main` local (`924bac4`, de documentação).
- **Worktrees de agentes ficam bloqueados** (`locked`) enquanto o agente vive; remover com `git worktree unlock` e `remove --force` só depois de integrar.
- **Fase "pronta" é fase usada.** Testes automáticos verdes não bastam; sem a rodada de uso no Chrome (e no Android, se toca lá), a fase não fecha.
