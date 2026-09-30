# Processo de construção e histórico por fase

> Como o jopendaw é construído (o ciclo contínuo de levas: fila de achados, agentes em worktree, integração por `cherry-pick`, teste de uso, aviso à sessão de documentação), as regras do dono e as lições que custaram caro, a cronologia das fases 1 a 26 montada do `git log` e os defeitos que o uso e a leitura de código revelaram. Para quem vai continuar o trabalho, humano ou agente.

Fontes: `git log` do repositório (171 commits em 28 e 30/09/2026, até o commit `de20512`; eram 72 até `357b6fc` e 61 até `924bac4` nas versões anteriores deste capítulo), a seção "Método de desenvolvimento em ciclo contínuo (o que se aprendeu)" do `CLAUDE.md` da raiz (commit `72a7ec4`), o `CLAUDE.md` global do dono, o [changelog](../changelog.md) da documentação e as anotações de processo do dono (memória do projeto, fora do repositório). O que só aparece nas anotações e não no `git` está marcado `(fonte: notas do dono)`. Horários são os do git (`%ad`, data de autoria; commits integrados depois por `cherry-pick` têm data de commit posterior: isso aparece na fase 5). Todos os commits das fases 9 a 26 têm data de 30/09 no git; o [changelog](../changelog.md) rotula as fases 15 em diante como `01/10/2026` (ver "Inconsistências observadas" no fim).

## Visão geral

O jopendaw foi construído em **levas** ("fases") repetidas, sem parar ao fim de cada uma, até o dono mandar parar. Cada leva segue o mesmo ciclo (o método está na seção "Método de desenvolvimento em ciclo contínuo" do `CLAUDE.md` da raiz; este capítulo o descreve e o reconcilia com o que o `git log` mostra):

```
  1. escolher a leva ──► 2. agentes em worktree ──► 3. integração ──► 4. teste de uso ──► 5. avisar a sessão
     (fila de achados,      (um por área, arquivos      (cherry-pick      (Chrome; Android       de documentação
      bugs do uso,           disjuntos, vários na        do commit,        quando roda lá)        (commit, UI, onde,
      lacunas do DAW)        mesma mensagem)             binários, push)                          o que NÃO foi testado)
        ▲                                                                                              │
        └──── achados de leitura de código, devolvidos por ela, viram a fila da leva seguinte ◄────────┘
```

Nas fases 2 a 5 o ciclo tinha um passo extra na frente, o **contrato** (um commit `wip: contrato da fase N` com ids, tabelas e assinaturas, antes dos agentes). Depois da fase 5 não há mais commit `wip:` no histórico: as levas ficaram menores e o que o contrato garantia (áreas e arquivos disjuntos) passou para o prompt dos agentes (deduzido do histórico e do `CLAUDE.md`). Os testes de contrato que leem o Rust e comparam com o Dart continuam (ver abaixo).

## Peças e responsabilidades

| Peça | Papel |
|---|---|
| `CLAUDE.md` (raiz) | regras do projeto, comandos, arquitetura, a seção "Teste de uso", o "Método de desenvolvimento em ciclo contínuo" e as "Lacunas conhecidas" |
| `~/.claude/CLAUDE.md` (global do dono) | regra dos commits sem trailers, vale para todos os projetos |
| `.claude/worktrees/` | onde ficam os worktrees dos agentes (ignorado pelo git; `.gitignore`, commit `160b7f5`) |
| `engine/build-web.sh`, `engine/build-android.sh` | recompilam `app/web/engine/engine.wasm` e os `.so` do Android; o integrador roda, nunca o agente |
| `tool/cdp.mjs` | cliente CDP mínimo para testar o app no Chrome de depuração (:9222): cliques por coordenada, teclas com modificadores, arrastos, screenshots, `probe` do motor, concessão de permissões |
| `hot.sh` | backend com hot-patch (ver [11 Servidor](11-servidor.md)) |
| Testes de contrato | leem o Rust e comparam com o Dart (ids e faixas de parâmetros, exports do wasm × chamadas do controlador): pegam divergência entre agentes cedo (ver [10 App Flutter](10-app-flutter.md)) |
| Testes que varrem o código | `lib/` contra `edit(` sem rótulo, contra `(Ctrl+…)` escrito à mão e contra deslocamentos de 32 bits (`<<` grande, constantes acima de 2^31, para o dart2js): uma regra que custou caro vira teste, não só aviso (`CLAUDE.md`) |
| `docs/` (sessão de documentação) | manual, guias, documentação técnica, `changelog.md` e este capítulo; mantidos por uma sessão à parte (ver o passo 5 do fluxo) |

## Fluxo, passo a passo

### 1. Escolher a leva

Sai de três fontes: (a) **filas de achados**: a sessão de documentação lê o código para documentá-lo e devolve listas de defeitos e inconsistências; (b) **bugs vistos no teste de uso**; (c) o **levantamento de lacunas do DAW** (ver "Estado e lacunas conhecidas"). Nunca perguntar "posso seguir?": o mandato do dono é o **ciclo sem fim** (implementar, testar, corrigir, propor a próxima leva, até ele mandar parar; `(fonte: notas do dono)`).

O padrão aparece nos assuntos dos commits: a leva N costuma trazer um bloco de correções dos achados de uma leva anterior (por exemplo `fase 19 (A): achados do sequenciador de passos`, `fase 21: achados de leitura de código da fase 18`, `fase 22: achados de leitura de código da fase 19`, `fase 24: … e achados da fase 21`) ao lado dos recursos novos.

### 2. Agentes em worktrees com arquivos disjuntos

Um agente por área (as letras `A`, `B`, `C`, `D` dos assuntos `fase N (B): …`), cada um em `isolation: worktree`, **vários na mesma mensagem**. O prompt sempre traz: ler o `CLAUDE.md`; prosa em português acentuado; `flutter analyze` e `flutter test` verdes (e `cargo test` e `clippy -D warnings` se tocar o motor); **confirmar cada achado no código antes de mexer e dizer o que não procede** (a leitura de código da sessão de documentação às vezes erra ou já está resolvida); testes para cada item; **commit sem trailers**; sem push; **não recompilar `engine.wasm` nem os `.so`** (o integrador faz); relatório curto em português com "o que não testei". Quando a leva muda motor ou modelo, os agentes são avisados dos arquivos que os outros vão tocar: `model.dart`, `controller.dart` e `timeline.dart` são os pontos de conflito conhecidos.

Nas fases 2 a 5 valia também o contrato no `main` (`wip: contrato da fase N`: `3f91b9a` fase 2, `8e0efe7` fase 3, `1fd29e1` fase 4, `a1477ad` fase 5) e os worktrees partiam desse commit. Essas fases foram rodadas com Workflow (Implementar, depois Integrar) quando o modo estava ligado; sem ele, vários agentes na mesma mensagem. `(fonte: notas do dono)`

Um agente derrubado por erro de rede deixa a branch com mudanças não commitadas no worktree; a retomada é por `SendMessage` ao mesmo agente.

### 3. Integração (por quem coordena)

1. `git pull --rebase origin main`.
2. `git cherry-pick <sha>` na ordem, **o commit do agente e não a branch inteira** (a branch pode trazer commits de documentação que já estão no `main`). Por isso o hash no `main` difere do hash da branch do agente: o capítulo e o changelog citam sempre o do `main` (ver Armadilhas).
3. Resolver conflitos (quase sempre `controller.dart` e `timeline.dart`); em `docs/` fica a versão da sessão de documentação (`git checkout --ours -- <arquivo>`); ler os conflitos com `git diff --name-only --diff-filter=U`.
4. `flutter analyze`; `flutter test` (conferir o `All tests passed` no fim da saída, não só a última linha); se o motor mudou, `cargo test -p jopendaw-engine` e `clippy`.
5. Se o motor mudou, **recompilar `./engine/build-web.sh` e `./engine/build-android.sh` e commitar os binários juntos**. Regra dura: **binários nunca vêm dos agentes.** `engine.wasm` e os três `.so` (`arm64-v8a`, `armeabi-v7a`, `x86_64`) só valem com o motor inteiro integrado; sem recompilar os `.so` o Android fica com o motor velho (e mudo, se a chamada `apply` for nova: o `c379259` da fase 5). Nos commits: `chore: integra a fase N` até a fase 17 e `chore: recompila wasm e .so (…)` depois (`ccf3ca2`, `de20512`).
6. `flutter build web --release`; push.

Depois: `git worktree unlock` e `remove --force` dos worktrees e apagar os branches `faseN/*` e `worktree-agent-*` `(fonte: notas do dono)`. Em 30/09/2026 essa limpeza **não tinha sido feita**: o repositório local tinha 51 worktrees `agent-*` (um bloqueado) e 39 branches `fase*/*`, de `fase8` a `fase18` (`git worktree list`, `git branch`).

### 4. Teste de uso (obrigatório)

O teste é **usar o app**, não revisar código: subir o `./hot.sh`, `flutter build web --release` e conduzir o Chrome de depuração pelo `tool/cdp.mjs` (o Flutter desenha em canvas: não há DOM para clicar por seletor) e/ou pelo Claude in Chrome; no emulador Android quando a mudança roda lá. Detalhes em "Como testar" abaixo e em [03 Build, teste e depuração](03-build-teste-e-depuracao.md). Ele acha o que testes automáticos com motor falso não acham: a detecção de swing "passava" nos testes e quebrava com os rolos de 1/32 do clipe real (`aa563b3`); a correção da fase 22 só foi dada por boa depois de o Chrome mostrar o controle de swing voltando a 0%; o `Fatiar sample` que nunca achava cortes no navegador por causa de inteiros de 32 bits (`606664f`).

### 5. Avisar a sessão de documentação

Com `SendMessage`, o integrador manda: o commit, a mudança de UI ou de comportamento, onde está no código e **o que NÃO foi testado**. As mensagens dela são de colega, não aprovação do usuário. O que ela devolve (achados por leitura de código) vira a fila do passo 1.

**Quem é "a sessão de documentação" e como ela trabalha** (descrição do processo visto nos arquivos e nos commits `docs:`, não uma especificação):

1. **Contrato.** O [guia de estilo](../_estilo.md) (português com acentos, só o que existe, `(não confirmado)` quando só foi lido), os moldes de capítulo por tipo (manual, guia, técnico), o índice do `docs/README.md` e a divisão de quem escreve o quê, com arquivos disjuntos.
2. **Redatores por área.** Agentes, cada um com um conjunto de capítulos (por exemplo manual, guias, `dev/10`, `dev/01`), lendo o código-fonte (`app/lib/`, `engine/src/`, `server/src/`) e os commits da leva. Escrevem só em `docs/`, **não commitam** (quem coordena commita) e não editam código.
3. **Passada final.** Conferir links relativos, índice e `changelog.md`, reconciliar textos antigos que a leva tornou falsos (o assunto do `bb2d37c` diz "textos antigos reconciliados") e marcar `(testado só por testes automáticos)` no que ninguém viu rodando.
4. **Achados de volta.** Como a documentação é escrita lendo o código, ela encontra defeitos que o teste de uso não viu; o changelog os registra como "Inconsistências lidas do código (não corrigidas)" e eles voltam à sessão de código como lista (exemplos: os da fase 20 que a fase 24 corrigiu).

Duas limitações honestas: a documentação é **lida do código**, e o que foi visto rodando (Chrome, Android) é só o que a sessão de código relatou; e a separação não é absoluta (um commit de código, `55cc53b`, também alterou `docs/changelog.md`, 4 linhas). O que fica pronto entra no `main` por commits `docs:` (29 no histórico, até `9c7c0bf`); a árvore de trabalho da documentação é um worktree do mesmo repositório (`/Volumes/Projects/jopendaw-docs`, em `HEAD` destacado na hora da escrita) e a "branch de docs paralela" é o que as anotações do dono chamam esse arranjo `(fonte: notas do dono)`.

### 6. Memória e relatório curto

O integrador fecha a leva dizendo **o que entrou, o que foi testado (Chrome, Android ou só automático) e o que não foi**, e guarda o estado na memória do projeto `(fonte: notas do dono)`. Pausas do dono ("pausa tudo, vou fazer um deploy") são sagradas: parar agentes, `hot.sh`, containers e daemons Gradle e só voltar quando ele avisar. Volta ao passo 1.

### Convenção de commits observada

Mensagens em português, corpo em prosa explicando o porquê e o que foi medido (os commits de integração e os `docs:` costumam ter só o assunto). Contagem do histórico até `de20512` (171 commits, todos do mesmo autor): `feat` 58, `fase N (…):` sem prefixo convencional 34 (a partir da fase 11), `docs` 29, `fix` 25, `chore` 19, `wip` 4, 1 merge (`knobs-automacao`) e 1 `metrônomo: …` sem prefixo. **Nenhum commit tem trailer de assinatura** (verificado de novo: zero ocorrências de `Co-Authored-By`, `Claude-Session` ou `Generated with` em `git log --format=%B origin/main`).

| Prefixo | Uso |
|---|---|
| `wip: contrato da fase N` | o contrato antes dos agentes (só fases 2 a 5) |
| `feat(motor)`, `feat(app)`, `feat(server)`, `feat(engine,app)`, `feat(warp)`, `feat(mixer)`, `feat(timeline)`, `feat(sampler)` | trabalho dos agentes, por área |
| `fase N (A)`, `fase N (B)`…, `fase N: …` | da fase 11 em diante, o trabalho de cada agente da leva, pela letra da área, ou da leva inteira quando é um agente só |
| `chore: integra a fase N` | integração: cherry-picks, binários recompilados (fases 2 a 17) |
| `chore: recompila wasm e .so (…)` | só os binários (`ccf3ca2`, `de20512`) |
| `fix: achados do teste de uso da fase N`, `fix(app)`, `fix(engine)`… | resultado do teste de uso e dos achados de leitura |
| `docs:` | `CLAUDE.md` e a pasta `docs/` (`docs: fase N (…)` é o registro da documentação da leva) |

## Regras do dono

Estas regras valem para qualquer contribuição; nasceram de experiências ruins. As de 1 a 10 são o comportamento que o dono pede; as de 11 em diante são as regras técnicas que o `CLAUDE.md` chama de "regras que custaram caro" (o porquê de cada uma está em "Decisões e por quê" e em "Armadilhas conhecidas").

1. **Nunca adicionar trailers de assinatura** (`Co-Authored-By: Claude ...`, `Claude-Session: ...`, `Generated with Claude Code`) em commits nem em corpos de PR, em nenhum projeto. Vale mesmo quando o ambiente de execução pede esses trailers: a regra do dono vence. A mensagem termina no último parágrafo do corpo. **Repetir isso no prompt de todo agente.** (`~/.claude/CLAUDE.md`, `CLAUDE.md`)
2. **Backend sempre com `./hot.sh`** (em background, `--interactive false` sem TTY, com o timeout máximo: `run_in_background` com 7200000 ms), nunca `cargo run` reiniciado a cada mudança. Ele morre pelo limite de tempo e precisa ser reiniciado (`localhost:8080` respondendo 000 = caiu). Rebuild completo só quando o patch não serve (struct, enum, assinatura, `Cargo.toml`, `setup`). Patch que falha ou processo que cai depois dele: investigar a causa, não voltar ao `cargo run`. A 8080 é do coordenador (o `main`); agentes em worktree validam com `cargo test`, não sobem servidor. (`CLAUDE.md`)
3. **Teste de uso obrigatório, em vez de revisão de código.** Toda leva só está pronta depois de usada no navegador, e no emulador Android quando mexe em algo que roda lá. O dono trocou uma revisão adversarial de código por "teste no Chrome, teste completamente tudo: o uso revela o que a revisão revelaria muito mais rápido; o que surgir, corrija e siga". A leitura de código não sumiu: a sessão de documentação a faz ao escrever, e o que ela acha volta como fila de achados, **confirmados no código antes de mexer** (o agente diz o que não procede). (`CLAUDE.md`; `(fonte: notas do dono)` para as palavras)
4. **Sem buracos de teste.** Medir de verdade: clipes **longos** (o detector de andamento foi testado só com 4 s e o dono mandou repetir com clipe longo), casos **extremos** e **negativos** (ruído, pad e tom puro devem ser recusados), e transformar o achado em teste de regressão. Dizer com honestidade o que **não** foi testado (no relatório do agente e no aviso à sessão de documentação). `(fonte: notas do dono)`
5. **Testar os dois lados de um fluxo.** Sincronização, por exemplo: criar e editar num aparelho, ver no outro, editar de volta. `(fonte: notas do dono)`
6. **Estados transitórios.** Testar durante a reprodução, a gravação, desfazer e refazer, reabrir o projeto, duplicar e dividir (herdam campos), e raciocinar sobre o que aparece **entre** os estados, com screenshots em sequência e não só do estado final (o spinner que parava antes de tudo carregar foi achado assim). (`CLAUDE.md`; `(fonte: notas do dono)`)
7. **Comportamento estranho: investigar até entender** e distinguir defeito do produto de defeito do harness de teste antes de concluir. `(fonte: notas do dono)`
8. **Português do Brasil com acentos** em prosa, comentários, mensagens de erro da API e textos de UI; identificadores em inglês. Estilo: `rustfmt` com `max_width` 160 e `dart format -l 160` (sem o `-l 160` o `dart format` reformata o projeto inteiro). (`CLAUDE.md`)
9. **Nada na VPS ou na produção sem o dono.** Deploys e credenciais (MinIO da VPS) são dele. `(fonte: notas do dono)`
10. **Pausas do dono são sagradas.** Ele avisa ("pausa tudo, vou fazer um deploy"): parar agentes, `hot.sh`, containers e daemons Gradle, e só retomar quando ele disser. (`CLAUDE.md`)
11. **dart2js tem inteiros de 32 bits:** nada de `<<` grande nem constantes acima de 2^31; há teste que varre o código.
12. **Formato salvo retrocompatível:** campo novo é opcional e só é gravado fora do padrão; mudança que o app antigo não lê sobe `DawDoc.version` (hoje 2).
13. **Detecção pelas notas é frágil: guarde a intenção** (o `swing_hint`).
14. **Toda ação editável tem rótulo no histórico** (`edit(..., label:)` ou `editAs`), e dicas de atalho saem do `Keymap` (`shortcutHint`), nunca escritas à mão.
15. **Mensagens de UI:** plural certo (`plural()`), erro inline e nunca toast, avisos de uma vez só.
16. **Binários do motor nunca vêm dos agentes** e são commitados junto da mudança do motor (ver o passo 3 do fluxo).

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
- **Viewport de 1512x900:** `node tool/cdp.mjs run <tab> passos.json 1512 900`; `reset <tab>` tira a emulação. Se a aba abrir outro projeto depois do rebuild, `location.href='/projetos/<id>'`. (`CLAUDE.md`; a barra do transporte foi ajustada duas vezes para caber nessa largura: `beaca60` e `47c5f3d`.)
- **WAV de teste:** gerar com Python (`wave`) em `app/build/web/`, importar com `["file","x.wav"]` e o botão de importar, e **apagar o arquivo depois**. O `probe` lê os picos por faixa e prova que o som sai.
- **Desfazer o que o teste mexeu:** `Ctrl+Z` no projeto de teste ("Teste automacao") ao terminar, para o próximo teste partir do mesmo estado.
- **Medir caso longo, extremo e negativo**, transformar em teste de regressão e dizer o que não foi visto (regras 3 e 4).
- **O que só se vê no uso:** testes automáticos com motor falso não pegam o que depende do motor e da tela de verdade (a detecção de swing com rolos de 1/32, o `Fatiar sample` com deslocamentos de 32 bits no dart2js; ver "Defeitos notáveis").

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

### Fase 8: loudness, projeto em arquivo, zonas do sampler e expressão MIDI (30/09, 08:01 a 08:35)

**Situação:** as quatro frentes de recurso e a integração com os binários entraram no `main` em `357b6fc` (08:24); o primeiro achado de uso, do navegador, veio em `606664f` (08:35), e a leva seguinte (fase 9) começou às 08:40. Este capítulo foi escrito com a fase 8 ainda "em andamento" (em `357b6fc`); o fechamento está em "Fechamento da fase 8" abaixo. O fluxo foi o das fases anteriores: um agente por frente em worktree, com branch `fase8/arquivo`, `fase8/loudness`, `fase8/sampler` e `fase8/expressao`, e integração por `cherry-pick` (por isso os hashes do `main` diferem dos dos branches: `30e606a` virou `7af1f19`, `f2e09c4` virou `dca27bc`, `c81f8d5` virou `b6b7abb`, `2534ffc` virou `6f3d245`, `d4d97e7` virou `6e5fa7b`, `f91f2e2` virou `b7e802e` e `d0d897a` virou `01c0c44`; correspondência deduzida do assunto e do horário de autoria, iguais nos pares). Não há commit `wip: contrato da fase 8` no histórico. `(a razão não está registrada)`

A tabela vai de `9a790a2` (último commit da fase 7) até `606664f`. Horários: autoria, e entre parênteses o de integração quando difere (o `cherry-pick` do fim da manhã carimbou 08:10 e 08:16 em commits escritos antes). O `924bac4` (docs, 07:57), que a tabela da fase 7 já lista, cai dentro da mesma janela.

| Commit | Área | O que fez |
|---|---|---|
| `7af1f19` 08:01 (08:10) | app | **Projeto em arquivo `.jopendaw`**: zip com `project.json`, `manifest.json` e `samples/<sha256>.<ext>`; leitura com limites (zip bomb, nomes hostis, sha-256 conferido); importar cria um projeto novo e refaz os ids de forma consistente; exportar no editor e no cartão do projeto (`project_file.dart`, `project_file_ui.dart`; 7 arquivos, +1 523) |
| `b6b7abb` 08:04 (08:16) | motor | **Zonas do sampler**: lista de zonas por faixa (áudio, nota base, faixas de notas e de velocidade, afinação, ganho, pan, modo, trecho, loop e grupo de round-robin; sem zonas o sampler é o de sempre); chamadas `zones_clear` e `zone_add` em `api.rs` e no wasm; `slice_points` (N partes ou por transientes) e `slice_zones` (uma zona por fatia a partir de C1) (`sampler_zones.rs`; 7 arquivos, +1 453) |
| `dca27bc` 08:09 (08:10) | motor e app | **Loudness**: `engine/src/loudness.rs` (BS.1770-4 / EBU R128: K-weighting para qualquer taxa, momentâneo de 400 ms, curto prazo de 3 s, integrado com gates de -70 LUFS e -10 LU, faixa de loudness, true peak com sobreamostragem 4x, sem alocação na thread de áudio, alimentado com o master depois do limitador), chamadas `loudness_reset` e `loudness(kind)` na api, no wasm, no worklet/`host.js` e no Android (`jd_loudness`); no app, leitura M/S/I/TP no canal do master com alerta acima de -1 dBTP e botão `Zerar` (`loudness_panel.dart`) e, na exportação, `Normalizar o loudness` (streaming -14, podcast -16, broadcast -23 ou personalizado), teto de true peak, stems opcionais com o mesmo ganho e o LUFS final medido (`loudness.dart`, Dart puro para funcionar igual nas duas plataformas). **Binários não recompilados** (26 arquivos, +2 574) |
| `67208c5` 08:12 | docs | manual de uso completo (00 a 09), guias de combinações e a documentação técnica (dev 00 a 20) (36 arquivos, +8 907) |
| `0c0593e` 08:15 | servidor e app | **fix**: a imagem do servidor constrói com o workspace inteiro (`COPY engine engine` no `server/Dockerfile`; o cargo precisa dos manifestos dos membros `engine`, `engine/wasm` e `engine/android`) e o `location /api/` do nginx do app aceita uploads de até 600 MB (`client_max_body_size 600m`, `proxy_request_buffering off`; o padrão de 1 MB do nginx cortaria áudio e documento); o `.dockerignore` passa a deixar fora `.claude/`, `docs/`, `engine/target/` e `node_modules/` (3 arquivos, +10). Detalhes em [11 Servidor](11-servidor.md) |
| `6f3d245` 08:15 (08:16) | motor | **fix**: as vozes de zona ignoram a troca do áudio único do sampler; a fila de comandos do Android passa a aceitar até 16 argumentos por chamada (o `zone_add` tem 16; o limite era 12), com teste (3 arquivos, +30 -5) |
| `6e5fa7b` 08:15 (08:16) | app | **Zonas do sampler no app**: o documento guarda as zonas por faixa de sampler (JSON antigo abre igual); o sync manda `zones_clear` e `zone_add` só quando a lista muda; o render fora de tempo real leva as zonas e os áudios delas; cartão `Zonas` do painel do instrumento com o mapa (arrastar as bordas muda notas e velocidade), edição da zona, adicionar sample como zona e o diálogo `Fatiar sample…` com prévia dos cortes (8 arquivos, +2 339) |
| `677f064` 08:20 | app | **fix**: exportar o projeto inteiro passa para o diálogo de exportar, com o botão `Projeto inteiro (.jopendaw)…` (a barra do transporte estourava a largura; o botão de ícone saiu de `transport_bar.dart`) e o texto do loudness deixa de repetir o alvo (3 arquivos, +21 -14) |
| `b7e802e` 08:22 (08:22) | motor | **Expressão MIDI**: pitch bend de 14 bits normalizado (alcance por instrumento, padrão ±2 semitons) e vibrato da roda de modulação (LFO de 5,5 Hz, até ±1 semitom) no sintetizador, no FM e no wavetable; o sampler responde ao bend; a bateria ignora tudo; o pedal de sustain mora na camada da faixa (com ele embaixo o note off fica pendente até subir); chamadas `live_bend`, `live_cc`, `cc_add` e `cc_clear` (api, wasm e Android); os eventos de controle tocam com o clipe no quadro exato, com o estado reconstituído ao começar, saltar ou voltar o loop e devolvido ao repouso ao parar; a gravação registra os controles junto das notas (`expression.rs`; 13 arquivos, +1 712) |
| `01c0c44` 08:22 (08:22) | app | **Expressão MIDI no app**: `MidiClip.controls` no documento (JSON compatível com documentos antigos), levado ao motor por `cc_clear`/`cc_add` e cortado, deslocado e escalado junto das notas; ao vivo, Web MIDI e Android (bend `0xE0`, CC 1 e CC 64) e rodas de bend e de modulação no teclado da tela, com o pedal indo ao motor; gravação dos controles no clipe com overdub que substitui o trecho tocado; no piano roll, faixa de controle sob a grade (`Velocidade`, `Pitch bend`, `Modulação`, `Sustain`) com lápis, reta, mover, apagar e pedal pintado (19 arquivos, +2 279) |
| `357b6fc` 08:24 | integração | **`chore: integra a fase 8`**: `engine.wasm` e os três `.so` recompilados (o motor commitado passa a conhecer loudness, zonas e expressão) e a lista de símbolos conferidos pelo `engine/build-android.sh` ganha `jd_loudness`, `jd_stretch` e `jd_detect_bpm` (5 arquivos) |
| `606664f` 08:35 | app | **fix (achado do uso no navegador)**: `Fatiar sample…` nunca achava cortes e o limite de tamanho do `.jopendaw` era calculado errado, porque no dart2js os operadores de bit trabalham em 32 bits; o código passa a usar multiplicação e `~/`, e um teste varre o `lib/` atrás de deslocamentos e constantes que estouram (3 arquivos, +31 -4) |

**O que já entrou:** medição de loudness e normalização na exportação, projeto em arquivo `.jopendaw`, zonas do sampler com fatiamento de loops, expressão MIDI (pitch bend, roda de modulação, pedal de sustain, controles gravados e editáveis), a correção do Dockerfile do servidor e do limite de corpo do nginx, e os binários do motor recompilados. É o que as anotações do dono previam para a leva (`(fonte: notas do dono)`: LUFS e true-peak, expressão MIDI, projeto em arquivo, sampler multi-zona).

### Fechamento da fase 8

As quatro frentes e os binários entraram em `357b6fc`; o primeiro e único achado de uso registrado no git para a fase 8 é o `606664f` (dart2js, acima), já que não existe `fix: achados do teste de uso da fase 8`; o `fix` `677f064` (barra que estourava) não diz de onde veio o achado. O que a versão anterior deste capítulo listava como pendente ficou assim em `de20512`:

- **Envio ao servidor de origem:** feito (`origin/main` e `main` estão ambos em `de20512`).
- **Documentação:** os capítulos da fase 8 entraram em `67208c5` e `6e5354d` (capturas de tela) e o changelog tem a seção da fase 8.
- **Limpeza dos worktrees e branches:** **não foi feita** (51 worktrees `agent-*` e 39 branches `fase*/*` ainda existem).
- **Uso que o git não mostra:** exportar `.jopendaw` de projeto grande e importá-lo em outro aparelho e outra conta, loudness contra uma referência conhecida, zonas com round-robin e loop no Android e bend, modulação e pedal com um controlador MIDI real: nenhum registro de que tenham sido feitos `(não confirmado)`.
- **Build real da imagem do servidor e upload grande pelo nginx:** o `0c0593e` corrige as duas coisas pela leitura do Dockerfile e da configuração do nginx; não há registro de um `docker-compose up --build` nem de um `PUT` de mais de 1 MB pelo `web` (ver [11 Servidor](11-servidor.md)). `(não confirmado)`

### Fases 9 a 26: o ritmo e como ler esta parte

As fases 9 a 26 saíram todas em 30/09, entre 08:40 e 15:53 pelo horário de autoria do git (cerca de sete horas): cada leva concentra seus commits em poucos minutos a cerca de meia hora (horário de autoria), com dois a cinco agentes (as letras `A` a `D` dos assuntos). A partir da fase 11 os assuntos trazem `fase N (A)`. Cada fase tem os commits do `main` (não os das branches dos agentes), a integração e o que foi testado; os detalhes por recurso estão no [changelog](../changelog.md) e nos capítulos do manual e técnicos que ele lista. "Testado" segue o que o changelog registra sobre o uso relatado pela sessão de código; quando diz "só automático", ninguém viu o recurso rodando no Chrome nem no Android.

As fases 15 a 25 têm uma particularidade: a cada leva, parte dos commits **corrige achados de leitura de código de uma leva anterior** (ver o passo 1 do fluxo). As fases 19, 21, 22, 24 e 25 são **só** isso; as fases 18, 20 e 26 trazem recursos novos.

### Fase 9: áudio para MIDI em vários formatos, cota, sincronização e falha do motor (30/09, 08:40 a 08:58)

Integração `f25935f` (08:54); documentação `fb89dea`.

| Commit | Área | O que fez |
|---|---|---|
| `f0d9879` 08:46 | servidor e app | áudio→MIDI com MP3, FLAC, OGG e AAC/M4A (symphonia, teto de 10 minutos), opções `Nota mínima` e `Nível de silêncio`; cota de 4 GB com `GET /api/samples`, `DELETE /api/samples/{hash}` (409 se em uso) e `POST /api/samples/cleanup`, e a tela `Conta` com o uso (18 arquivos, +918) |
| `f03d6b0` 08:46 | app | andamento e compasso passam a valer do documento (o servidor guarda um espelho reenviado com `PATCH`), sincronização sem conflito falso e com pull a cada 30 s e ao voltar o foco, áudio→MIDI coerente com o warp, `Ganho do clipe…` (−40 a +12 dB), limpeza local ao apagar o projeto (13 arquivos, +805) |
| `b07b2b2` 08:43, `ae91ef4` 08:49, `4238761` 08:40, `cc8ca68` 08:52 | motor, pontes e Android | falha do motor avisa o app (`Reiniciar o áudio`); limites do motor explicados no app (16 efeitos e 16 envios) e render da web em passadas; retornos de 32 bits do FFI lidos com o tipo certo; tela acesa enquanto toca ou grava e pausa quando o fone sai (Android) |
| `e6b9858`, `cb29151`, `40712af`, `ffff18c`, `ba5b0d2` | app | edição MIDI (`Escalar o tempo` estica o clipe, `Prender seleção na escala`), oitava do teclado por tipo de faixa, aviso ao mover faixa que desfaria rotas de barramento, ganho do compressor coerente com o motor, `Dither` na distorção e rótulos renomeados |
| `15670b7` 08:58 | app | **fix**: a tela `Conta` não carregava o uso ao abrir (faltava o `initState`) |

Testado: o changelog não registra uso no Chrome ou no Android para esta fase; o `fix` `15670b7` é o de uma tela vista rodando (deduzido do tipo de defeito).

### Fase 10: mapa de andamento e compasso, `.mid`, polimentos (30/09, 09:07 a 09:31)

Integração `afdc8f7` (09:27); documentação `cf41c89`.

| Commit | Área | O que fez |
|---|---|---|
| `02f1910` 09:23 | motor e app | mapa de andamento e de compassos (saltos, rampas, 3/4, 6/8, 7/8), faixa `Andamento` sob a régua (26 arquivos, +3 238) |
| `945e937` 09:08 | app | importar e exportar arquivos MIDI padrão (`.mid`/`.midi`, SMF formato 1, PPQ 480) (8 arquivos, +1 472) |
| `0e08769` 09:08, `e2e9bfd` 09:07 | motor e app | polimento do sampler multi-zona (zona nova na maior lacuna, nota base digitável, round-robin, vozes `Até o fim` empilhadas) e da expressão MIDI (knob de vibrato no sampler, copiar e colar levam os pontos) |
| `629bafd` 09:31 | Android | **fix**: um comentário com `--` no `network_security_config.xml` quebrava o build do APK de debug; teste que confere os XML |

Testado: o `fix` do APK é achado de build; o resto, só automático segundo o changelog (sem nota de uso).

### Fase 11: compensação de latência (PDC), servidor sob trava e pontes (30/09, 09:37 a 09:53)

Integração `601ad49` (09:53); documentação `3779fd3`.

| Commit | Área | O que fez |
|---|---|---|
| `3d1cffa` 09:51 | motor | PDC: o motor atrasa as outras faixas, barramentos, envios e a chave do sidechain para compensar a latência do `Limitador` e da `Distorção` (11 arquivos, +1 381) |
| `020003f` 09:37 | app | o `.mid` leva e traz o mapa de andamento e de compassos (pergunta antes de usar os andamentos do arquivo) |
| `8b07070` 09:37 | app, pontes, Android | pull que não troca o projeto tocando ou em arraste (avisa), FFI com o tipo exato de cada argumento (handles `u64`), `resume()` reabre a saída, `formatBpm` (23 arquivos) |
| `94731e8` 09:43 | servidor | apagar, criar tarefa e gravar documento sob a mesma trava por hash, `422` com `missing`, folga de 1 h no `DELETE`, trecho (`start`/`end`) no áudio→MIDI |
| `5f7c80b` 09:45 | motor | **fix**: um compasso único 6/8 não volta a n/4 quando o app reenvia o tempo a cada sincronização |

Testado: só automático (o changelog diz que nada foi ouvido no navegador).

### Fase 12: gravação de automação, presets do usuário e correções (30/09, 10:01 a 10:25)

Sem commit `chore: integra a fase 12`; se os binários mudaram nesta leva, só aparecem na integração da fase 13 (`c5425a0`) `(não confirmado)`. Documentação `675223d`.

| Commit | Área | O que fez |
|---|---|---|
| `806fbb7` 10:06 | app | **gravar automação mexendo nos controles**, com os modos `Ler`, `Escrever`, `Toque` e `Trava` (11 arquivos, +1 438) |
| `b39d3d4` 10:04 | app | presets do usuário para instrumentos e efeitos (salvar, renomear, apagar, exportar e importar `.jopreset`) (+1 559) |
| `d196fec` 10:01, `dd4ef07` 10:09 | app | correções do sampler multi-zona (erro inline nos campos, avisos de limite) e do mapa de andamento, do `.mid` e da expressão MIDI (35 arquivos) |
| `beaca60` 10:25 | app | **fix**: o deslizador de volume do cabeçalho grava automação; o indicador de nuvem sai da barra (ela passava da tela em janelas de uns 1 500 px) |

Testado: só automático, segundo o changelog.

### Fase 13: MIDI learn, latência do motor na gravação, servidor e sincronização (30/09, 10:39 a 10:46)

Integração `c5425a0` (10:46, binários recompilados); documentação `3b0fc61`.

| Commit | Área | O que fez |
|---|---|---|
| `f7e34fe` 10:39, `347e8d1` 10:39 | motor e app (A) | a gravação soma a latência do motor à do aparelho (áudio e MIDI), o clique do metrônomo sai alinhado pela PDC, nova chamada `latency_frames` (`engineLatency` nas pontes), compasso único n/8 |
| `1180152` 10:39 | servidor e app (B) | o app trata o `422` reenviando os áudios de `missing`; a limpeza devolve `skipped_in_use` e `skipped_job`; conexão única do banco por chamada |
| `18c72f4` 10:44 | app (C) | **MIDI learn** (mapa no documento, takeover suave, painel `Mapeamentos MIDI`), `Meus presets` no topo dos menus e reordenar sem tomar o deslizador do cabeçalho (20 arquivos, +2 531) |

Testado: no Chrome, com MIDI injetado, aprender o `CC 21` no fader do `Pad` e o `CC 40` levando-o a −24,1 dB; o resto só automático; nada com um controlador de verdade.

### Fase 14: pastas de faixa, curvas de fade e crossfade automático (30/09, 10:53 a 11:02)

Integração `48ec9e8` (11:02); documentação `c51ae36` (e capturas `6eccedd`).

| Commit | Área | O que fez |
|---|---|---|
| `bda7a47` 11:00 | app (C) | **pastas de faixa**: `Agrupar em pasta…` reúne faixas sob um barramento de grupo, com recolher e expandir, mixer com a barra `Grupo` (o motor não mudou) (+1 776) |
| `991c05d` 10:57 | app (D) | curvas de fade selecionáveis (`Linear`, `Potência constante`, `Exponencial`, `S`) e crossfade automático entre clipes de áudio |
| `504b4b8` 10:58, `725ce0f` 10:53 | app (A, B) | correções da gravação de automação e dos presets do usuário; tempos por compasso contra o compasso real, limite do `.mid`, gravação solta os controles ao vivo |

Testado: só automático, segundo o changelog.

### Fase 15: multibanda, de-esser, imagem estéreo e exportar FLAC e MP3 (30/09, 12:01 a 12:09)

Integração `9192220` (12:09); documentação `c915fef`.

| Commit | Área | O que fez |
|---|---|---|
| `bd6bbb9` 12:01 | motor e app (B) | `Multibanda`, `De-esser` e `Imagem estéreo`: a cadeia passa de 12 para 15 tipos de efeito (12 arquivos, +2 064) |
| `792b6f5` 12:06 | servidor e app (C) | exportar em FLAC e MP3 pelo servidor (tarefa `encode_audio`, `DELETE /api/jobs/{id}`, migração `db/migrations/…`) (23 arquivos, +1 910) |
| `1d90812` 12:02 | app (A) | correções de MIDI learn, latência e gravação, sincronização e compasso (22 arquivos) |

Testado: no Chrome, o `Multibanda` no `Pad` (relatado pela sessão de código) e um MP3 de 192 kbps de 10 s exportado; FLAC e Android só automático.

### Fase 16: modulação, atalhos personalizáveis e correções (30/09, 12:26 a 12:39)

Integração `53ca96d` (12:39); documentação `812d74c`.

| Commit | Área | O que fez |
|---|---|---|
| `e364c48` 12:37 | motor e app (B) | **modulação**: aba `Modulação` com LFO, seguidor de envelope e macro, até 4 moduladores por faixa (22 arquivos, +3 494); capítulo [06g](../manual/06g-modulacao.md) |
| `e8c613a` 12:27 | app (C) | atalhos de teclado personalizáveis (tela `Personalizar atalhos`, `atalhos.jokeys`) |
| `ffa76ba` 12:26 | app (A) | correções de pastas, fades e crossfades, automação, presets do usuário, `.mid`, gravação e exportação |

Testado: no Chrome só o preset `Tremolo no volume` num `Pad`; o resto automático, nada ouvido nem visto no Android.

### Fase 17: sequenciador de passos, punch, pré-roll, tap tempo e metrônomo (30/09, 12:48 a 13:27)

Integração `f41fe00` (13:13; também "testes do servidor com 4 fios"); documentação `283bf7f`.

| Commit | Área | O que fez |
|---|---|---|
| `46a2a3c` 12:55 | app (B) | **sequenciador de passos** para bateria e sampler fatiado (aba `Passos`, presets, swing, ações), uma visão das mesmas notas do clipe (7 arquivos, +2 459); capítulo [05c](../manual/05c-sequenciador-de-passos.md) |
| `54bd4da` 12:48, `8a9ea40` 13:06 | motor e app (C) | metrônomo com timbres, subdivisões e acento (chamada nova `metronome_style`); punch in/out, pré-roll de 0 a 4 compassos, tap tempo e opções do metrônomo |
| `52d25c1` 12:56 | app (A) | correções dos efeitos novos, da exportação FLAC/MP3 e de tempo e compasso (32 arquivos) |
| `47c5f3d` 13:27 | app | **fix**: a barra do transporte voltou a caber em 1512 px (a duração e os atalhos saem em janelas estreitas) |

Testado: **não foi visto rodando**: a gravação com punch e pré-roll, o som dos timbres e o tap tempo; a aba `Passos` não foi vista no Chrome nem no Android; a largura de 1512 px é a medida do commit.

### Fase 18: edição de áudio, histórico e versões nomeadas, correções de modulação (30/09, 13:42 a 13:49)

Sem `chore: integra`; binários em `ccf3ca2` (13:48, modulação); documentação `43ffaa6` e `d8ac335`.

| Commit | Área | O que fez |
|---|---|---|
| `c0ea89b` 13:44 | app (C) | **histórico de desfazer com nomes e hora** (`HistoryEntry`, painel `Histórico`) e **versões nomeadas** do projeto (salvar, restaurar, comparar, duplicar, automáticas) (33 arquivos, +2 555); capítulo [02d](../manual/02d-historico-e-versoes.md) |
| `d139758` 13:43 | app (B) | edição de áudio por transientes: `Dividir por transientes…`, `Remover silêncio…`, `Normalizar clipe…`, `Quantizar por fatias…` (+2 356); capítulo [03e](../manual/03e-editar-audio.md) |
| `c1fb192` 13:42 | motor e app (A) | correções de modulação (a fase dos LFOs não recomeça ao editar), atalhos personalizáveis em todo aparelho e presets do usuário (28 arquivos) |
| `03e6d05` 13:47, `ed605e3` 13:49 | app | fixes: tooltips de desfazer e refazer usam o atalho do keymap; o nome padrão da versão já vem selecionado |

Testado: no Chrome (pela sessão de código) o painel `Histórico`, o menu do botão `Desfazer`, o painel `Versões`, `Salvar versão…` e a versão automática `Ao abrir o projeto`; o resto só automático (34 testes de lógica e 6 de tela).

### Fase 19: achados de leitura da fase 17 (30/09, 13:55 a 13:56)

Só o app; documentação `bb2d37c`.

| Commit | Área | O que fez |
|---|---|---|
| `fc5878b` 13:55 | app (A) | sequenciador de passos: swing lido das notas do clipe, `Repetir até o fim do clipe` com aviso, padrões pelo compasso do clipe, nomes das linhas do sampler |
| `c09b153` 13:56 | app (B) | contagem, pré-roll e punch (a gravação para sozinha no punch out), tap tempo, `Volume` do metrônomo de 50% para 60%, exportação (janela `Salvar` fechada não conta como salva) |

Testado: só automático (`fase19b_test.dart` e outros).

### Fase 20: mudo, fase e loop por clipe; congelar faixa no lugar (30/09, 14:06)

Só o app; documentação `b1b2dc4`.

| Commit | Área | O que fez |
|---|---|---|
| `3a27233` 14:06 | app (A) | menu do clipe de áudio: `Silenciar o clipe` (tecla `0`, ação nova `edit.mute`), `Inverter a fase (polaridade)` e `Repetir em loop` (até 1 hora e 4096 repetições); capítulo [03](../manual/03-audio-e-clipes.md) |
| `3bd56fd` 14:06 | app (B) | `Congelar faixa…` no lugar (o conteúdo fica guardado), `Descongelar` e `Converter em áudio…`; o antigo `Congelar em áudio` virou `Renderizar em faixa nova`; capítulo [02e](../manual/02e-congelar-faixa.md) |

Testado: o congelar foi visto no Chrome pela sessão de código (congelar o `Baixo`, ouvir, `Ctrl+Z` descongela); o resto, só automático. Os achados de leitura de código que a documentação anotou sobre loop e congelar foram corrigidos na fase 24.

### Fase 21: achados de leitura da fase 18 (30/09, 14:12)

| Commit | Área | O que fez |
|---|---|---|
| `6e87e92` 14:12 | app (mais um teste novo no motor) | edição de áudio (emenda de 2 ms pela curva `S`, `Fatias demais` com a dica do modo), nomes em todos os passos do histórico (um teste varre `lib/`), versão automática também por relógio, modulação (o LFO que sobra não herda a fase do apagado), atalhos sem tecla escrita à mão, `Restaurar presets do backup…` sem o arquivo principal (22 arquivos) |

Testado: nada visto nem ouvido; só automático (`fase21_test.dart` e outros).

### Fase 22: achados de leitura da fase 19 (30/09, 14:25 a 14:29)

Só o app; documentação `c94b506`.

| Commit | Área | O que fez |
|---|---|---|
| `938272c` 14:25 | app | tap tempo com teto de espera de 2,5 s; WAV direto cancelado em `Salvar` nomeia o arquivo; **`DawDoc.version` passa de 1 para 2**; parar logo depois do ponto de gravar não cancela; fade do punch out; plurais; sequenciador com leitura de swing mais rígida e `Padrões` que tira o swing de qualquer resolução (13 arquivos) |
| `aa563b3` 14:29 | app | a detecção de swing tolera rolos de 1/32 (notas a meio passo) (2 arquivos) |

Testado: o changelog diz só automático; o `CLAUDE.md` conta que esta fase só foi dada como corrigida depois de o Chrome mostrar o controle de swing voltando a 0% (achado do uso, origem do `aa563b3`).

### Fase 23

Não há commit nem seção do changelog com esse número: o histórico vai de `fase 22` a `fase 24`. `(não confirmado)`: pode ter sido uma leva absorvida pela 24.

### Fase 24: clipes em loop, congelar faixa e achados da fase 21 (30/09, 14:38)

Só o app; documentação `2dfd934`.

| Commit | Área | O que fez |
|---|---|---|
| `ebea0b1` 14:38 | app | loop (soltar clipe por cima respeita a fase, reverso com loop, edições por fatias e conversão em notas recusam clipe em loop, fade limitado à repetição, aviso do teto de 4096), congelar (a impressão do som inclui automação e modulação, recusas iguais no `Renderizar em faixa nova`, aviso ao editar faixa congelada, `Descongelar` tira o áudio de `doc.samples`) e três achados da fase 21 (10 arquivos, +668 -100) |

Testado: só automático (`fase24_test.dart`); nada foi ouvido.

### Fase 25: swing com dica persistente, gravação curta, versão futura na sincronização (30/09, 15:31)

Só o app; documentação `2dfd934`.

| Commit | Área | O que fez |
|---|---|---|
| `55cc53b` 15:31 | app | campo opcional `swing_hint` no clipe MIDI (resolução e valor do swing, validados contra as notas), `Padrões` só tira swing conhecido, faixa fatiada detectada por maioria, migração do `Volume` do metrônomo de documento versão 1, aviso de `Gravação muito curta`, tap tempo sem empate e recusa de documento de versão futura na sincronização e no `.jopendaw` (9 arquivos, +558 -76) |

Testado: só automático (`fase25_test.dart`); a recusa de versão futura só tem teste no caso da cópia local sem pendência.

### Fase 26: comping, exportação por marcadores e navegador de áudios (30/09, 15:42 a 15:53)

Levou a lacuna 1, a 2 e a parte de marcadores e regiões da 8 (ver "Estado e lacunas conhecidas"). O método do `CLAUDE.md` foi registrado logo antes, em `72a7ec4` (15:38). Os capítulos novos foram escritos por outros redatores ao mesmo tempo que este: [03f Comping](../manual/03f-comping.md), [03g Navegador de áudios](../manual/03g-navegador-de-audios.md) e o guia `guias/entregar-uma-musica-por-secoes-e-stems.md` (ainda não existe nesta hora); para o resto vale o que o `git log` mostra e o [changelog](../changelog.md) (a seção da fase 26 dele estava vazia quando este capítulo foi escrito).

| Commit | Área | O que fez |
|---|---|---|
| `ab57a40` 15:42 | app (A) | **comping por trecho**: raias por tomada, escolher o trecho arrastando, emendas com crossfade automático e achatar (`comp.dart`, `comp_ui.dart`; 7 arquivos, +1 043; só o app) |
| `f12d405` 15:45 | app (C) | **exportação por marcadores e seções**: novos intervalos no diálogo de exportar (entre dois marcadores; uma seção por marcador, com escolha das seções), faixas escolhidas (a mixagem é o solo delas, stems só delas), modelo de nome `{projeto}-{marcador}-{n}` editável, reunir tudo num `.zip`, loudness e cauda por arquivo, progresso por intervalo e cancelamento que preserva o que já saiu; o menu do marcador ganha `Exportar esta seção` (`export_plan.dart`; 7 arquivos, +1 255) |
| `d567f76` 15:51 | motor e app (B) | **navegador de áudios com pré-escuta**: aba `Áudios` do painel de baixo, voz de pré-escuta no motor (`preview.rs`; chamadas `preview_play` e `preview_stop`, à parte do transporte e do render), inserir e arrastar para o arranjo e para as zonas do sampler, baixar sob demanda, atalho `Shift+B` (18 arquivos, +2 123) |
| `de20512` 15:53 | integração | `engine.wasm` e os três `.so` recompilados com a pré-escuta (4 binários) |

Testado: o `git log` só mostra testes automáticos (`fase26_test.dart`, `export_regions_test.dart`, `browser_test.dart`, `preview_tests.rs`); uso no Chrome ou no Android: nenhum registro `(não confirmado)`. O comping e a exportação não tocam o motor; a pré-escuta sim, por isso os binários.

## Defeitos notáveis achados no uso, e como foram corrigidos

Até a fase 8 todos vieram do teste de uso ou da integração, não de revisão de código. Depois da fase 8 há duas origens, marcadas na coluna do sintoma: **uso** (o teste no Chrome ou a construção) e **leitura de código** (achados que a sessão de documentação devolveu ao ler o código; ver o passo 5 do fluxo); `(origem não registrada)` quando o commit não diz. A coluna Commit tem a correção; o changelog e os capítulos técnicos ([10 App Flutter](10-app-flutter.md), [12 Sincronização](12-sincronizacao.md)) trazem os detalhes e as armadilhas que continuam abertas. A lista não é exaustiva: só os defeitos mais instrutivos.

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
| 8 | a imagem Docker do servidor não construía (deduzido do commit e do comentário que ele acrescentou ao `Dockerfile`) | o `Dockerfile` copiava só os manifestos do servidor, mas o workspace lista `engine`, `engine/wasm` e `engine/android` e o cargo carrega o workspace inteiro | `COPY engine engine` antes da camada de dependências e `.dockerignore` ampliado | `0c0593e` |
| 8 | (previsto no código, antes de virar defeito visto) `PUT` de documento e de áudio acima de 1 MB atrás do nginx do app | o padrão do nginx é 1 MB de corpo; não havia `client_max_body_size` | `client_max_body_size 600m` e `proxy_request_buffering off` no `location /api/` | `0c0593e` |
| 8 | vozes de zona do sampler entravam na conta da troca do áudio único (marcadas como antigas e, numa segunda troca, cortadas); a fila do Android recusava o `zone_add` | o laço da troca em `sampler.rs` não excluía as vozes de zona, que guardam o próprio áudio; o limite de 12 argumentos por chamada era menor que os 16 do `zone_add` | o laço filtra `!v.span.zone`; limite da fila de 16 argumentos, com teste | `6f3d245` |
| 8 | a barra do transporte estourava com o botão de ícone de exportar o projeto inteiro | botão a mais na barra | o botão sai da barra e vira `Projeto inteiro (.jopendaw)…` no diálogo de exportar; o texto do loudness deixa de repetir o alvo (origem do achado não registrada no commit) | `677f064` |
| 8 | `Fatiar sample…` nunca achava cortes no navegador e o limite de tamanho do `.jopendaw` errava | os operadores de bit do dart2js trabalham em 32 bits (`<<` grande, constantes acima de 2^31) | produtos no lugar de deslocamentos e um teste que varre o código por esse erro | `606664f` |
| 9 | (uso) a tela `Conta` não mostrava o uso de armazenamento ao abrir | faltava o `initState` que carrega o uso | carrega ao abrir | `15670b7` |
| 9 | (origem não registrada) no Android, um retorno `-1` virava `4294967295` e o estado do motor saía errado | o FFI lia retornos `i32` e o estado `f64` com os tipos errados | tipos certos no FFI e teste com um motor de mentira; na fase 11 cada argumento passou a ter o tipo exato do Rust (handles `Uint64`, ids `Uint32`), o que consertou os argumentos desalinhados em armeabi-v7a | `4238761`, `8b07070` |
| 10 | (build) o APK de debug não construía | um comentário com `--` no `network_security_config.xml` (inválido em XML) | comentário corrigido e teste que confere os XML do Android | `629bafd` |
| 11 | (origem não registrada) apagar um áudio e usá-lo ao mesmo tempo podia deixar um documento citando áudio que sumiu | apagar, criar tarefa e gravar documento não tomavam a mesma trava | trava por hash, `PUT /doc` com `422` e `missing`, folga de 1 h no `DELETE` | `94731e8` |
| 11 | (leitura de código) o pull periódico trocava o projeto com o transporte tocando e no meio de um arraste | `busyEditing` não cobria tocar nem arrastar | passou a cobrir, e a troca avisa (`1180152` estendeu ao pull da abertura e ao `useServer`) | `8b07070`, `1180152` |
| 11 | um projeto cujo único compasso é 6/8 voltava a 3/4 no motor a cada sincronização | o reenvio do tempo a cada sincronização trocava o compasso único 6/8 por `n/4` no motor | compasso único 6/8 fica | `5f7c80b` |
| 12 (corrigido na 14) | (leitura de código) gravando automação, o `Escrever` da raia gravava o valor fixo desde o play e apagava a curva antiga; mexer o mouse fechava o `Toque` | `_startWrites` e o `releaseAll` a cada evento de ponteiro | só grava depois do primeiro toque; só `PointerUp` e `PointerCancel` fecham o `Toque` | `504b4b8` |
| 12 e 17 | a barra do transporte passava da tela em janelas de uns 1 500 px | botões e indicador de nuvem demais na barra | nuvem no cabeçalho do projeto (`beaca60`); duração e atalhos só em janelas de 1 640 px ou mais (`47c5f3d`) | `beaca60`, `47c5f3d` |
| 13 | (leitura de código) a gravação de MIDI não tinha compensação de latência e o clique do metrônomo soava adiantado | só a latência do aparelho entrava na conta, não a do motor (PDC, cadeia do `Master`, limitador) | a gravação soma a latência do motor; o clique é atrasado da latência total | `f7e34fe`, `347e8d1` |
| 14 | (leitura de código) mudar a saída de uma faixa de pasta pelo mixer não a tirava da pasta; `Congelar em áudio` criava a faixa fora da pasta; apagar um clipe não devolvia o fade do outro de um crossfade | regras de pasta e de fade só cobriam os menus | confirmação `Tirar "Nome" da pasta?`, a faixa nova nasce na pasta, `deleteSelected` reconcilia os fades automáticos | `ffa76ba` |
| 18 | (leitura de código) editar a modulação com o projeto tocando recomeçava a fase dos LFOs e o nível dos seguidores; o preset `Wobble no corte` prendia a onda em 20 kHz | o motor reiniciava o estado a cada edição; `+40%` do curso do corte | só reinicia quando o tipo do modulador muda; o preset passou a ±1 oitava | `c1fb192` |
| 21 | (leitura de código) a emenda de 2 ms entre fatias afundava uns −6 dB no meio; apagar o LFO 1 de 2 fazia o LFO 2 herdar a fase dele | curva `x²` (`Suave`) na emenda; os moduladores que sobravam mudavam de índice no motor | curva `S (seno cosseno)`, que soma amplitude 1; cada modulador guarda o índice do motor que recebeu | `6e87e92` |
| 19 | (leitura de código) `Usar a região do loop` copiava o loop desligado (0 a 16); fechar a janela `Salvar` no WAV direto terminava em `Exportação concluída` | o botão não olhava o loop ligado; o cancelamento não parava a fila | só o loop ligado e com largura é copiado; `Exportação cancelada: você não escolheu onde salvar.` | `c09b153` |
| 22 | o controle `Swing` do sequenciador lia humanização como swing e, com rolos de 1/32 no clipe real, o `Aplicar` e o `Tirar` não voltavam às notas (o Chrome mostrou o controle voltando a 0%) | o swing era deduzido das notas e os testes com motor e clipe de mentira passavam | leitura mais rígida, ignora notas a meio passo (`aa563b3`); depois a dica `swing_hint` no clipe (`55cc53b`, fase 25) | `938272c`, `aa563b3`, `55cc53b` |
| 22 | (leitura de código) todo projeto antigo abria com o `Volume` do metrônomo em 60%; parar logo depois do ponto de gravar cancelava a gravação | a fase 19 mudou o padrão sem versão do formato; `started` só muda com o estado do motor | `DawDoc.version` 2 (versão 1 sem o campo fica em 50%); o cancelamento confere a posição do transporte | `938272c` |
| 24 | (leitura de código) soltar um clipe por cima de um clipe em loop tocava áudio de fora do trecho; o reverso com loop tocava o fim do trecho na última repetição; fade maior que uma repetição fazia um degrau | o aparo avançava o `offset` sem descontar as repetições; a repetição parcial lia o lado errado do trecho invertido | aparo respeitando a fase, repetição parcial com o começo invertido, fade limitado à repetição, recusa das edições por fatias em clipe em loop | `ebea0b1` |
| 24 | (leitura de código) congelar uma faixa e mudar a automação ou a modulação durante o render deixava passar áudio velho; a cauda da faixa congelada saía cortada da exportação; `Descongelar` deixava o áudio em `doc.samples` (e na nuvem) | a impressão do som ignorava a automação e a modulação; o fim do projeto ignorava a faixa congelada | a impressão inclui os dois; o fim inclui a cauda congelada; `Descongelar` tira o áudio que nenhuma outra faixa usa | `ebea0b1` |
| 25 | (leitura de código) um documento de versão futura era aplicado pela sincronização; apertar gravar e parar na hora caía em mensagens que não diziam a causa; o tap tempo empatava a 24 BPM | sem checagem de `version` na sincronização; limites sem margem | recusa com `documento N; esta versão lê até o M`, aviso `Gravação muito curta (menos de 300 ms)…`, espera do tap tempo de 2,6 s | `55cc53b` |

Achados que não viraram commit de código, só de processo `(fonte: notas do dono)`: o APK velho instalado por engano regravou `fm` e `wavetable` como `audio` no documento local (tipo desconhecido vira `audio` na leitura: ver [10 App Flutter](10-app-flutter.md)); duas abas do Chrome no mesmo projeto geram conflito de sincronização legítimo.

## Estado e lacunas conhecidas (30/09/2026, em `de20512`)

`(fonte: notas do dono e changelog, exceto onde indicado)`

- **Testado no Chrome:** as fases 1 a 7 (FM e wavetable com todos os presets soando, ferramentas MIDI, detector de andamento: 90 BPM com 88% de confiança num clipe longo e o pad recusado); na fase 8, o achado do `Fatiar sample…` no navegador (`606664f`). Das fases 9 a 26, o que o changelog registra como **visto rodando** é pouco: aprender o `CC 21` e o `CC 40` com MIDI injetado (13), o `Multibanda` no `Pad` (15), a exportação de um MP3 de 192 kbps (15), o preset `Tremolo no volume` (16), o painel `Histórico`, o painel `Versões` e a versão automática (18), o congelar do `Baixo` (20) e o controle de swing (22). O resto das fases 9 a 26 é `(testado só por testes automáticos)` e a fase 26 não tem nenhum registro de uso `(não confirmado)`.
- **Testado no Android (emulador):** motor nativo (10 testes de integração), login, abrir projeto, sincronização Chrome e Android nos dois sentidos, FM e wavetable sincronizados (fases 5 a 7). Depois disso o changelog não registra uso no Android: as fases 9 a 26 só têm testes automáticos de Dart e de Rust para o que roda lá, e o `.so` recompilado de cada leva que tocou o motor (`c5425a0`, `de20512` e as outras integrações) não tem teste de uso registrado `(não confirmado)`.
- **Nunca testado:** Android físico, microfone real e controlador MIDI real no aparelho (MIDI learn, bend, modulação e pedal incluídos).
- **Limites conhecidos** (da fase 8; os que o changelog e os capítulos ainda confirmam): o cache `warp:` do aparelho não tem limpeza (só o servidor limpa áudios sem uso: [01b](../manual/01b-nuvem-e-sincronizacao.md)); barramento só manda para barramento de índice maior ([06 Mixer](../manual/06-mixer.md)); MinIO da VPS ainda sem credenciais fornecidas (o backend S3 está pronto); "a automação de parâmetros só toca com o valor fixo quando parado" não foi reconfirmado depois da fase 8 `(não confirmado)`. Desde a fase 13 a gravação do app soma a latência do motor (antes não somava). Do changelog: o aviso de editar uma faixa congelada não cobre os knobs; a recusa de documento de versão futura não cobre a cópia local, `Restaurar`, `Exportar projeto…` nem o `Manter esta e enviar` de um conflito; os presets, as versões nomeadas e os mapeamentos de atalho ficam só no aparelho.

**Lacunas do DAW** (a lista do `CLAUDE.md`, levantada em 30/09/2026, em ordem de prioridade):

| # | Lacuna | Situação em `de20512` |
|---|---|---|
| 1 | comping por trecho | **entregue na fase 26** (`ab57a40`) |
| 2 | navegador de áudios com pré-escuta | **entregue na fase 26** (`d567f76`, binários `de20512`) |
| 3 | envelope e automação de clipe (motor) | aberta |
| 4 | groove extraído e aplicado | aberta |
| 5 | efeitos MIDI em tempo real (motor) | aberta |
| 6 | reverb de convolução com IR (motor) | aberta |
| 7 | goniômetro, correlação e espectrograma (motor pequeno) | aberta (a `Imagem estéreo` tem a trilha `FASE`, correlação de fase, desde a fase 15; não é a ferramenta da lista) |
| 8 | exportar por marcadores e regiões e em lote | **entregue na fase 26** para marcadores, seções e faixas escolhidas (`f12d405`); o "em lote" além de uma seção por marcador e do `.zip` `(não confirmado)` |
| 9 | time-stretch e pitch de qualidade e afinação (motor) | aberta |
| 10 | modelos do usuário, desfazer por faixa, multissaída | aberta (os presets do usuário da fase 12 são de instrumentos e efeitos, não modelos de projeto) |

Fora da lista do `CLAUDE.md`: macros de ação, colaboração em tempo real, MIDI clock e saída MIDI, separação de stems no servidor, Android em aparelho físico (nunca testado), S3 de produção. **Já entregues do roteiro antigo** (o que esta página chamava de ideias em 30/09): LUFS e true-peak, MIDI CC e pitch bend, sampler multi-zona e projeto em arquivo (fase 8); mapa de andamento e compasso (10); compensação de latência, PDC (11); pastas de faixa (14); exportar FLAC e MP3 (15; AAC não: [08 Exportação](../manual/08-exportacao.md)).

## Decisões e por quê

- **Contrato primeiro, nas fases 2 a 5.** Sem o contrato commitado, agentes em paralelo inventam ids e assinaturas diferentes; com ele, cada um trabalha numa área e a integração vira cherry-pick. Depois da fase 5 o contrato virou áreas e arquivos disjuntos no prompt (levas menores).
- **Arquivos disjuntos e worktrees.** Elimina conflito de merge por construção; os poucos conflitos que sobram são de `controller.dart`, `timeline.dart` e `model.dart`.
- **Binários só na integração, e commitados junto do motor.** O agente do motor compila num estado que não tem o resto; o `.wasm` e os `.so` só valem quando todo o motor está junto (a lição do `c379259`). Quando o motor muda, recompilar `build-web.sh` e `build-android.sh` e **commitar `engine.wasm` e os três `.so` juntos**; o Android com `.so` velho fica com o motor velho e, se a chamada `apply` for nova, mudo. Exemplos recentes: `ccf3ca2` (modulação da fase 18) e `de20512` (pré-escuta da fase 26).
- **Testes de contrato que leem o outro lado.** Ids de parâmetro, exports do wasm, códigos de efeito (15 tipos desde a fase 15), padrões do multibanda: a divergência entre agentes aparece como teste vermelho, não como botão que move o parâmetro errado.
- **Teste de uso no lugar de revisão, e a leitura de código como fila.** O uso revela o que a leitura não vê (o master sem limitador, a curva de automação, o callback do dart2js, o swing com rolos de 1/32); a leitura de código revela o que o uso não alcança (o aparo de clipe em loop, a cauda da faixa congelada). Por isso o agente **confirma cada achado no código antes de mexer e diz o que não procede**, e cada achado vira teste de regressão.
- **Formato salvo retrocompatível e `DawDoc.version`.** Campo novo é opcional e só é gravado fora do padrão (`zones`, `cc`, `group`, os campos de fade, `muted`, `invert`, `loop_length`, `swing_hint`), então documento antigo abre igual e o JSON de quem não usa o recurso não muda. Um app anterior ignora o campo ao ler e o perde ao regravar (ver [10 App Flutter](10-app-flutter.md), "Duas armadilhas de compatibilidade"). Mudança que o app antigo não lê sobe a `version` (2 desde a fase 22), e o `.jopendaw` e a sincronização recusam versão futura com `documento N; esta versão lê até o M` ([12 Sincronização](12-sincronizacao.md)). Mudar um **padrão** pede heurística explícita de migração: a fase 19 passou o `Volume` do metrônomo de 50% para 60% sem versionar, a fase 22 criou a versão 2 e a fase 25 acrescentou `DawDoc._legacyVolumeOf` (50%, ou 60% se o documento traz marcas da fase 20 em diante).
- **Guardar a intenção em vez de deduzir pelas notas.** O swing lido só pelas notas errava com humanização, rolos de 1/32 e contratempos; a solução foi um campo opcional (`swing_hint`) validado contra as notas. Vale para qualquer "desfazer o que apliquei".
- **Rótulo em toda ação editável.** O histórico com nomes (fase 18 C) só funciona se cada `edit(..., label:)` ou `editAs` tem nome; na fase 21 ainda havia ações que gravavam `Edição` e um teste passou a varrer `lib/` contra `edit(` sem rótulo. As dicas de atalho saem do `Keymap` (`shortcutHint`), nunca escritas à mão (outro teste varre `(Ctrl+…)`).
- **Medir antes de mexer.** Os limiares do detector de andamento saíram dos números do envelope de onsets, não de palpite.

## Armadilhas conhecidas

- **Trailers vêm do ambiente, não do dono.** O ambiente de execução do agente pode pedir `Co-Authored-By`/`Claude-Session` no commit e um rodapé em PRs; a regra do dono é nenhuma, sempre. Conferir a mensagem antes de commitar e repetir a regra no prompt de cada agente.
- **Cite o hash da `main`, não o da branch ou do worktree.** O `cherry-pick` gera um commit novo: o agente da fase 25 escreveu `8289c3d` e o `main` ficou com `55cc53b`. Documento que cita o hash do worktree aponta para um commit que some quando o worktree é apagado. Conferir com `git merge-base --is-ancestor <hash> origin/main` (feito para o changelog inteiro em `de20512`: todos os hashes estão no `main`; os sete hashes de branch da fase 8 nesta página estão ali de propósito, como correspondência).
- **`cherry-pick` do commit, não da branch.** A branch do agente pode trazer commits de documentação que já estão no `main`.
- **Sessões paralelas no mesmo repositório.** A documentação (`docs/`) e o código (`app/`, `engine/`, `server/`) evoluem em sessões diferentes: quem escreve documentação não edita o código e não commita (o coordenador commita); antes de publicar, `git pull --rebase`; num conflito em `docs/` vale a versão da sessão de documentação. Em `de20512` o `main` local e o `origin/main` estavam iguais (em 30/09, no fim da fase 8, o `origin/main` chegou a ficar oito commits atrás).
- **Worktrees de agentes ficam bloqueados** (`locked`) enquanto o agente vive; remover com `git worktree unlock` e `remove --force` só depois de integrar. A limpeza não é automática: em `de20512` restavam 51 worktrees e 39 branches de agentes.
- **Agente derrubado por erro de rede** deixa a branch com mudanças não commitadas no worktree; retomar com `SendMessage` ao mesmo agente em vez de refazer.
- **`hot.sh` morre pelo limite de tempo** do processo em background; `localhost:8080` respondendo 000 significa que caiu e precisa subir de novo.
- **`flutter test`: conferir o `All tests passed` no fim**, não só a última linha da saída.
- **Fase "pronta" é fase usada.** Testes automáticos verdes não bastam; sem a rodada de uso no Chrome (e no Android, se toca lá), a fase não fecha. Nas fases 9 a 26 boa parte das levas foi fechada só com testes automáticos registrados (ver "Estado e lacunas conhecidas"): é a lacuna de processo mais visível do histórico.

## Inconsistências observadas entre as fontes

- **Datas.** O `git log` data todos os commits das fases 9 a 26 em 30/09; o [changelog](../changelog.md) rotula as fases 15 a 26 como `01/10/2026` (e as 9 a 14 como `30/09/2026`). Este capítulo segue o git.
- **Fase 23.** Não há commit nem seção do changelog com esse número (vai da 22 à 24).
- **Fase 26 no changelog.** Na hora da escrita a seção da fase 26 do changelog existia só com o título, sem conteúdo; os capítulos `03f` e `03g` já existiam e o guia `guias/entregar-uma-musica-por-secoes-e-stems.md` ainda não.
- **Integração sem commit próprio.** As fases 12 e 18 a 26 não têm `chore: integra a fase N`; o que o passo 3 do fluxo descreve como commit de integração aparece só como `chore: recompila wasm e .so (…)` (`ccf3ca2`, `de20512`) ou não aparece.
- **Uso da fase 22.** O `CLAUDE.md` diz que a correção da fase 22 veio depois de o Chrome mostrar o controle de swing em 0%; o changelog diz que a fase 22 só tem testes automáticos (o texto do changelog é da sessão de documentação, que não viu rodar).
- **Separação de sessões.** O `55cc53b`, commit da sessão de código, altera `docs/changelog.md`; as anotações do dono falam numa "branch de docs paralela", mas no histórico os commits `docs:` estão direto no `main` e a árvore de documentação está em `HEAD` destacado.
