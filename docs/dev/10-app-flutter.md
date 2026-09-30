# App Flutter: rotas, documento, controlador

> Para quem mexe no app (`app/lib/`): como as telas se ligam, o formato exato do documento do projeto (o JSON que vai para o disco do aparelho e para o servidor), o que o `DawController` faz a cada edição e o passo a passo para acrescentar instrumento, efeito ou parâmetro.

Citações `arquivo:linha` valem para o estado do repositório em 30/09/2026 (commit `357b6fc` mais a documentação); as linhas andam, o nome do símbolo é o que vale.

## Visão geral

```
main.dart (go_router, Session)
  │
  ├── screens/ ── login, link do email, projetos, conta, projeto
  │        └── ProjectScreen ── cria ─► DawController(project) ──► DawStudio (daw/*.dart, UI)
  │
  ├── api/client.dart (ApiClient : SyncApi)   único acesso HTTP; renova o JWT no 401
  ├── auth/session.dart, auth/social.dart      tokens (armazenamento seguro), Google/Discord
  ├── platform/                                o que muda entre navegador e Android
  ├── audio/                                   AudioEngine + LocalStore (web: IndexedDB; Android: arquivos)
  └── daw/
        model.dart        documento (DawDoc) ◄──────────── JSON ────────► guardado local + servidor
        controller.dart   edição, desfazer, sync com o motor, importar, gravar, exportar, congelar
        instruments.dart / effects.dart   tabelas de parâmetros (contrato com o motor Rust)
        sync.dart         sincronização com o servidor (ver 12-sincronizacao.md)
```

Duas regras de desenho atravessam tudo:

1. **Local primeiro.** O documento e os áudios moram no aparelho (`LocalStore`); o servidor só sincroniza. O projeto abre sem rede.
2. **O motor é escravo do documento.** O `DawController` nunca lê estado do motor para montar o documento; cada mudança no `DawDoc` vira, por diferença, uma lista de chamadas `[nome, ...argumentos]` para o motor (`AudioEngine.calls`). O contrato dessas chamadas é o do motor: ver [02 Pontes web e Android](02-pontes-web-e-android.md).

## Peças e responsabilidades

### Entrada, rotas e sessão

| Arquivo | Papel |
|---|---|
| `app/lib/main.dart` | `main()` (URL sem `#`, `initPlatform`, `Session.load`), o `GoRouter` e o `MaterialApp.router` |
| `app/lib/auth/session.dart` | `Session`: tokens no `flutter_secure_storage` (chaves `jopendaw.access` e `jopendaw.refresh`), `signedIn` = existe refresh token |
| `app/lib/auth/social.dart` | entrada com Google/Discord: segredo PKCE do app, retorno por URL (web) ou aba/esquema (Android) |
| `app/lib/api/client.dart` | `ApiClient` (singleton) implementa `SyncApi`; toda chamada leva `Authorization: Bearer` |
| `app/lib/api/sync_api.dart` | a interface `SyncApi` (documento, samples, jobs), `ServerDoc`, `DocConflict`, `SyncJob`; existe para os testes trocarem o servidor (`app/test/fake_sync_api.dart`) |
| `app/lib/models/` | `Project` (espelha `server/src/routes/projects.rs`), `User`, `Tokens`, `Me` |
| `app/lib/screens/` | `login_screen` (magic link, Google, Discord, código de acesso), `link_screen` (`/entrar?token=`), `projects_screen` (lista, criar com modelo, renomear, apagar; apagar também limpa o aparelho com `purgeLocalProject`), `account_screen`, `project_screen` (`DawStudio`; `projectSubtitle` lê o andamento e o compasso do documento vivo; o cabeçalho recebe `SyncIndicator(c: daw)` em `actions` quando o estúdio está pronto) |

Rotas (`app/lib/main.dart:27`):

| Caminho | Tela | Observação |
|---|---|---|
| `/login` | `LoginScreen` | recebe `?from=` (para onde ir depois), `?oauth=` e `?erro=` (retorno do Google/Discord) |
| `/authorize/callback` | `LoginScreen(discordApp: ...)` | volta do app do Discord no Android (`discord-{id}:/authorize/callback`) |
| `/entrar` | `LinkScreen` | troca o token do magic link por sessão e vai para `/` |
| `/` | `ProjectsScreen` | dentro do `ResponsiveScaffold` (ShellRoute) |
| `/projetos/:id` | `ProjectScreen` | aninhada em `/`; `key: ValueKey(id)` força recriar o controlador ao trocar de projeto |
| `/conta` | `AccountScreen` | dentro do `ResponsiveScaffold` |

O `redirect` (`main.dart:30`) manda quem não tem sessão para `/login` (guardando `from`, exceto quando o destino é `/`), e quem tem sessão sai de `/login` para o `from` ou `/`. `refreshListenable: Session.instance` reavalia a regra sempre que a sessão muda, então o logout e o fim de sessão (refresh falho) levam ao login sozinhos. `/login`, `/entrar` e `/authorize/callback` são as únicas rotas públicas.

`ResponsiveScaffold` (`widgets/responsive_scaffold.dart`) usa rail lateral a partir de 800 px (`kDesktopBreakpoint`) e barra inferior abaixo.

### `ApiClient` (`app/lib/api/client.dart`)

- **URL base** (`ApiClient.baseFor`, `client.dart:46`): `--dart-define=API_BASE=` se definido; senão, na web, **a origem da própria página, em qualquer porta e host** (o servidor Rust em `:8080`, o nginx do compose em `:8081`, a produção, sempre com `/api` no mesmo host); fora da web (Android) a produção `https://jopendaw.johnenrique.tech`. Consequência: num `flutter run -d chrome`, que serve o app numa porta própria sem API, é **obrigatório** passar `--dart-define=API_BASE=http://localhost:8080` (senão as chamadas `/api` vão para a porta do `flutter run`). O emulador Android usa `--dart-define=API_BASE=http://10.0.2.2:8080`. Antes da fase 9 a origem só valia com porta 8080 ou host diferente de `localhost` (o resto caía na produção).
- **Renovação no 401** (`_send`, `_refresh`): um 401 com sessão ativa dispara uma única renovação, dividida entre as chamadas simultâneas (`_refreshing`). Antes de chamar `/api/auth/refresh` o cliente relê o armazenamento seguro: se outra aba já renovou, adota o token dela. Um 409 do servidor (janela de 60 s de rotação, ver [11 Servidor](11-servidor.md)) faz até 3 tentativas, esperando 300 ms × n e relendo o armazenamento. Se a renovação falha, `signOut(notifyServer: false)` e `Unauthenticated`.
- **Tempos**: 120 s para qualquer pedido (`_raw`), 20 s para o refresh. Um upload de sample grande em conexão lenta pode estourar os 120 s (ver Armadilhas).
- **Erros**: `ApiException(status, message)` com a mensagem `{"error": ...}` do servidor; `Unauthenticated` para 401 pós-renovação; falha de rede sobe como exceção do `http`. `describeError` (`widgets/feedback.dart:12`) traduz tudo em frase para o usuário; erro é sempre inline (`InlineNotice`), nunca toast.
- **Projetos**: `createProject(name)` manda só `name`, então todo projeto nasce 120 BPM, 4/4, 48000 Hz.
- **`ApiState`** (`widgets/api_state.dart`): mixin de tela com `fetch`, `run`, `fail` e `error`/`info`/`busy`; as telas de projetos e de conta o usam.

### `platform/` e por que nada de `package:web` fora dali

`platform/platform.dart` reexporta `platform_native.dart` ou `platform_web.dart` conforme `dart.library.js_interop`. O mesmo código Dart compila para web e Android, e `package:web` (e `dart:js_interop` para o DOM) não compila no Android. Quem importasse `package:web` em qualquer outro lugar quebraria o `flutter build apk`. A regra do `CLAUDE.md` ("não importar `package:web` fora dali") vale para o DOM e as APIs do navegador; o mesmo desenho de exportação condicional aparece em `audio/engine.dart` (`engine_web.dart` no navegador, `engine_io.dart` + `engine_ffi.dart` no Android). Conferido por `grep`: `package:web` só aparece em `platform/platform_web.dart`; `dart:js_interop` também em `audio/engine_web.dart` (a ponte com `host.js`).

O que `platform/` expõe nos dois lados (mesma assinatura): `initPlatform`, `pageVisible`, `onVisibilityChange`, `isFullscreen`/`toggleFullscreen`/`exitFullscreen`, `openSignIn` (na web navega a aba; no Android abre uma aba do Chrome e devolve a URL de retorno), `openInOtherApp`, `openExternal`, `localRead`/`localWrite` (string síncrona: `localStorage` na web, `SharedPreferences` no Android; usados só pelo segredo PKCE da entrada social). Só o lado Android define também `keepScreenOn` e `watchAudioSession` (ponte `jopendaw/apps` com o `MainActivity`). `microphoneAllowed`/`ensureMicrophone` foram removidos (fase 11): o pedido de microfone do motor nativo passa só por `permission_handler` em `startInput` (`audio/engine_ffi.dart`).

### `widgets/`

Base visual compartilhada: `PageScaffold`/`PageBar`/`BrandMark` (`page.dart`), `ApiState`, `InlineNotice`/`NoticeStack`/`EmptyState`/`ErrorState`/`LoadingState` (`feedback.dart`), `confirmAction`/`confirmDelete`/`promptText` (`dialogs.dart`), `theme.dart` (`buildTheme`, `Palette`, `trackColorAt`, `automationColor`), `format.dart` (plural, milhar, datas), `AuthFrame`, `LegalLinks`, `brand_logos.dart`.

### `audio/` (só a fronteira com o controlador)

`AudioEngine.instance` (decodificar, `loadSample`, `calls`, entrada, captura, render fora de tempo real, `sha256Hex`, `saveFile`) e `LocalStore.instance` (`get`/`put`/`delete` por chave, e `keys(prefix)` para listar as chaves com um prefixo, usado pelo purge; valor `String` ou `Uint8List`). Na web o `LocalStore` é o IndexedDB do `host.js`; no Android é `FileStore` em `<documentos>/jopendaw`, um arquivo `.txt` (texto) ou `.bin` (bytes) por chave, com escrita por arquivo temporário + rename (`audio/engine_io.dart:157` e seguintes). Fora do Android e da web o `LocalStore` não guarda nada (`_files` é nulo).

Chaves do `LocalStore` usadas pelo app:

| Chave | Valor | Quem grava |
|---|---|---|
| `doc:<projectId>` | JSON do `DawDoc` (texto) | `DawController._save`; `importProjectBundle` (a primeira gravação de um projeto importado) |
| `sample:<sha256>` | bytes do arquivo de áudio como foi importado ou gravado | importar, gravar, congelar, baixar do servidor, importar `.jopendaw` (`importProjectBundle`, só se a chave ainda não existe) |
| `sync:<projectId>` | `{"version": int, "dirty": bool}` | `SyncService._persist` |
| `template:<projectId>` | nome do modelo escolhido ao criar o projeto (apagada na 1ª abertura) | `projects_screen`, `_fromTemplate` |
| `rec:input` | id da entrada de áudio escolhida | `_chooseInput` |
| `userpresets` | JSON com **todos** os presets do usuário (instrumentos e efeitos), ver [Presets do usuário](#presets-do-usuário-user_presetsdart-user_presets_uidart) | `UserPresets._changed` |
| `warp:<chave>` | WAV 32f do som derivado do warp (cache) | `WarpCache._run` |

## O documento (`daw/model.dart`)

O documento é a única fonte de verdade da música. Tudo o que está nele vai para o disco, para o desfazer e para o servidor; o que não está (seleção, zoom, painel aberto, entrada de áudio) é estado de tela do controlador.

### Unidades

| Grandeza | Unidade | Onde |
|---|---|---|
| Posição e duração na linha do tempo | **batidas** (`double`) | `AudioClip.start`, `MidiClip.start/length`, `AutoPoint.beat`, `Marker.beat`, `loop_start/loop_end` |
| Trecho do áudio de origem | **segundos do arquivo** | `AudioClip.offset/length/fade_in/fade_out` |
| Notas dentro de um clipe MIDI | batidas **desde o início do clipe** | `MidiNote.start/length` |
| Ganho | linear (1 = 0 dB; teto do fader 2 = +6 dB, `maxGain`; teto do ganho de clipe +12 dB, `maxClipGain`) | `gain`, `master_gain`, `Send.level`, automação de volume e envio; `AudioClip.gain` |
| Pan | −1 (esq.) .. 1 (dir.) | `pan`, `master_pan` |
| Parâmetros de instrumento e efeito | a unidade da tabela do parâmetro (Hz, s, dB, semitons, 0..1); **nunca normalizados** | `params` |
| Latência de gravação | milissegundos | `rec_latency_ms` |

Duração de um clipe de áudio em batidas: `length * tempoFor(bpm) / 60`, onde `tempoFor` é o `source_bpm` do próprio áudio quando o warp está esticando e o andamento do projeto caso contrário (`model.dart:96`). O fim do último clipe define `DawDoc.contentEnd`. **Com mapa de andamento** essa conta deixa de ser `length * tempoFor(bpm) / 60` e passa por `DawDoc.clipEnd(c)`: o clipe começa na batida dele e ocupa segundos reais constantes (`AudioClip.seconds(bpm0)`, com warp esticado ao andamento **inicial**), então o fim em batidas é `tempo.beatAt(tempo.secondsAt(start) + seconds)`. Com um andamento só, `clipEnd` devolve a conta de sempre (`c.end(bpm)`). Ver "Mapa de andamento e de compassos no documento".

### Esquema JSON completo (versão 1)

Regras gerais de leitura e escrita:

- `toJson` sempre escreve os campos "sempre"; os marcados **(omitido se padrão)** só aparecem quando diferem do padrão, para o documento antigo ficar byte a byte igual.
- `fromJson` é estrito nos campos **obrigatórios**: campo ausente ou de tipo errado lança (`TypeError`) e o documento não abre. Os **opcionais** têm o padrão indicado. Números aceitam inteiro ou decimal (`num`).
- Campos que o app não conhece são ignorados na leitura e **perdidos na próxima gravação** (o documento é reconstruído por `toJson`, não editado no lugar).
- O campo `version` é escrito (`DawDoc.version = 1`, `model.dart:423`) mas **não é lido nem conferido** em lugar nenhum: não há migração por versão hoje.

#### Raiz (`DawDoc`, `model.dart:422`)

| Campo | Tipo | Obrigatório? | Padrão (construtor / leitura) | Significado |
|---|---|---|---|---|
| `version` | int | escrito, não lido | `1` | versão do esquema |
| `bpm` | número | sim | (do projeto, só num documento novo) | andamento. **É a fonte de verdade** (desde a fase 9); `projects.bpm` no servidor é um espelho inteiro (20..999) enviado em segundo plano por `_mirrorTempo`. `open()` só parte do projeto quando não há documento local; `_applyRemote` traz o do documento remoto |
| `beats_per_bar` | int | sim | (do projeto, só num documento novo) | tempos por compasso. Mesma regra do `bpm` (espelho em `projects.beats_per_bar`). A figura do compasso (`beat_unit`) e a taxa de amostragem não estão no documento |
| `tempo_map` | lista de ponto de andamento | não | **(omitido sem mudanças)** | mapa de andamento: `[{"beat", "bpm", "ramp"}]`, ordenado, o primeiro na batida 0 (espelha `bpm`). Ver "Mapa de andamento e de compassos no documento" |
| `meter_map` | lista de mudança de compasso | não | **(omitido sem mudanças)** | mapa de compassos: `[{"bar", "num", "den"}]`, o primeiro no compasso 1. Idem |
| `tracks` | lista de faixa | sim | `[]` no construtor | faixas, na ordem do sinal (ordem = índice no motor) |
| `samples` | mapa `sha256 → {name, duration}` | sim | `{}` no construtor | catálogo dos áudios do projeto |
| `loop_on` | bool | sim | `false` | loop ligado |
| `loop_start`, `loop_end` | número (batidas) | sim | `0`, `16` no construtor; projeto novo: `beats_per_bar * 4` | região do loop |
| `metronome` | bool | sim | `false` | metrônomo ligado |
| `master_gain` | número | sim | `1` | volume do master (linear) |
| `master_pan` | número | sim | `0` | pan do master |
| `count_in` | bool | não | `true` | contagem de um compasso antes de gravar |
| `rec_latency_ms` | número | não | `0` | compensação manual da latência de gravação, −500..500 (`setRecLatency`) |
| `master_effects` | lista de efeito | não | `[]` | cadeia de inserts do master (depois dele vem o volume e o limitador de segurança do motor) |
| `master_lanes` | lista de lane | não | `[]` | automação do master (alvos volume, pan e efeito) |
| `markers` | lista de marcador | não | `[]` (reordenada por `beat` ao ler) | marcadores da régua |
| `midi_map` | objeto `{soft, items}` | não | **(omitido sem mapeamentos)**; ausente ou inválido lê como mapa vazio | mapeamentos do MIDI learn e a opção de takeover. Formato campo a campo na seção [MIDI learn](#midi-learn) |

#### Catálogo `samples`

Chave: SHA-256 do arquivo em hexadecimal minúsculo (64 caracteres), o mesmo endereço que o servidor usa. Valor `SampleInfo` (`model.dart:391`):

| Campo | Tipo | Obrigatório? | Significado |
|---|---|---|---|
| `name` | string | sim | nome de exibição (importado: nome do arquivo; gravado: `Gravação N`; congelado: `<faixa> (congelada).wav`) |
| `duration` | número (s) | sim | duração do áudio; `0` quando o hash entrou sem o áudio decodificado |

Cada tomada de uma gravação em loop também entra aqui. O som derivado do warp **nunca** entra (fica só em `warp:<chave>` no guardado local).

#### Faixa (`DawTrack`, `model.dart:283`)

| Campo | Tipo | Obrigatório? | Padrão | Significado |
|---|---|---|---|---|
| `id` | string (12 caracteres `a-z0-9`, `newId()`) | sim | | identificador estável; envios, saídas e automação apontam por ele |
| `name` | string | sim | | nome; faixa nova: `<Tipo> N` |
| `color` | int | sim | posição `% 6` | **índice** na paleta `Palette.tracks` (6 cores), não ARGB |
| `gain` | número | sim | `1` | volume linear |
| `pan` | número | sim | `0` | pan |
| `mute`, `solo` | bool | sim | `false` | |
| `kind` | string | sim (tolerante) | `audio` | `audio`, `synth`, `drums`, `sampler`, `bus`, `fm` ou `wavetable` (o `name` do enum `TrackKind`). Valor desconhecido **vira `audio`** na leitura |
| `params` | mapa `"id" → número` | não | `{}` (na leitura); faixa nova traz os padrões da tabela | parâmetros do instrumento. Chaves são o id numérico **como string**. Id ausente vale o padrão da tabela (`DawTrack.param`) |
| `sample` | string ou `null` | não | `null` | sha-256 do áudio do sampler (só `kind: sampler`) |
| `armed`, `monitor` | bool | não | `false` | armada para gravar; monitorando a entrada (preferência do aparelho, ver Sincronização) |
| `clips` | lista de clipe de áudio | sim | `[]` | clipes de áudio (só faixa `audio` toca) |
| `midi` | lista de clipe MIDI | não | `[]` | clipes de notas (faixas de instrumento) |
| `effects` | lista de efeito | não | `[]` | inserts, na ordem do sinal (até 16 slots no motor) |
| `sends` | lista de envio | não | `[]` | envios para barramentos |
| `output` | string ou `null` | não | `null` | id do barramento de saída; `null` = master |
| `lanes` | lista de lane | não | `[]` | automação da faixa |

O barramento (`kind: bus`) não tem clipes (`TrackKind.hasClips`), só recebe áudio por envios e saídas.

#### Clipe de áudio (`AudioClip`, `model.dart:13`)

| Campo | Tipo | Obrigatório? | Padrão | Significado |
|---|---|---|---|---|
| `id` | string | sim | | |
| `sample` | string | sim | | sha-256 do áudio ativo (a tomada tocada) |
| `takes` | lista de string | **(omitido se vazia)** | `[]` | tomadas de uma gravação em loop (sha-256 de cada passada, em ordem); a ativa é `sample`. Vazia para importado ou gravado sem loop |
| `start` | número (batidas) | sim | | onde o clipe começa na linha do tempo |
| `offset` | número (s) | sim | `0` | onde começa o trecho, em segundos do arquivo (corte à esquerda) |
| `length` | número (s) | sim | | duração do trecho, em segundos do arquivo |
| `gain` | número | não | `1` | ganho do clipe (linear). A interface (`Ganho do clipe…`, `clip_gain_dialog.dart`) vai de −40 a +12 dB: 0 no piso (−∞) e `10^(dB/20)` acima; `setClipGain` limita a 0..`maxClipGain` (+12 dB, ≈ 3,98). Cada arraste do slider é um `checkpoint` (`onChangeStart`) seguido de `mutate`s sem histórico, ou seja, um passo do desfazer; o `Zerar (0 dB)` é um passo próprio. Vai ao motor em `clip_add` |
| `fade_in`, `fade_out` | número (s) | não | `0` | fades, em segundos do arquivo |
| `fade_in_shape`, `fade_out_shape` | inteiro | **(omitido se 0)** | `0` | curva de cada fade (`FadeShape`): 0 linear (o envelope histórico, `x²`), 1 potência constante, 2 exponencial, 3 S. Código desconhecido vale 0 |
| `auto_fade_in`, `auto_fade_out` | objeto `{len, shape}` | **(omitido se nulo)** | `null` | marca de fade gerado pelo crossfade automático, com o comprimento e a curva de antes; `reconcileAutoFades` os devolve quando a sobreposição some. Fade mexido à mão perde a marca |
| `warp` | bool | **(omitido se falso)** | `false` | esticar para seguir o andamento do projeto |
| `source_bpm` | número ou ausente | **(omitido se nulo)** | `null` | andamento original do áudio (20..999); sem ele o warp não estica |
| `pitch` | número (semitons) | **(omitido se 0)** | `0` | transposição, −24..24, sem mudar a duração |
| `reverse` | bool | **(omitido se falso)** | `false` | toca de trás para a frente |

#### Clipe MIDI (`MidiClip`, `model.dart:127`) e nota (`MidiNote`, `model.dart:104`)

| Campo | Tipo | Obrigatório? | Padrão | Significado |
|---|---|---|---|---|
| `id` | string | sim | | |
| `name` | string | não | `''` | |
| `start`, `length` | número (batidas) | sim | | posição e duração do clipe |
| `notes` | lista de nota | sim | `[]` | |
| `scale` | string | **(omitido se nulo)** | `null` | escala escolhida no editor, `"<tônica 0..11>:<id>"` (ex.: `"9:minor"`, `ClipScale.encode` em `midi_tools.dart:69`); texto inválido ou de escala desconhecida é ignorado ao interpretar |

Nota: `pitch` (int; só 0..127 toca, fora disso é ignorada por `flattenNotes`), `start` e `length` (batidas **desde o início do clipe**; nota além de `length` ou antes de 0 fica guardada e não toca), `velocity` (0..1, padrão `0.8`, obrigatório escrever, opcional ler).

#### Efeito (`EffectSlot`, `model.dart:159`)

| Campo | Tipo | Obrigatório? | Padrão | Significado |
|---|---|---|---|---|
| `id` | string | sim | | identificador do slot (a automação de efeito aponta por ele) |
| `kind` | string | sim | | `eq`, `compressor`, `gate`, `limiter`, `utility`, `reverb`, `delay`, `chorus`, `phaser`, `tremolo`, `distortion` ou `filter` (o `name` de `EffectKind`). **Tipo desconhecido: o slot é descartado ao abrir** |
| `params` | mapa `"id" → número` | não | `{}` | id como string; ausente vale o padrão da tabela |
| `bypass` | bool | não | `false` | |

#### Envio (`Send`, `model.dart:199`)

| Campo | Tipo | Obrigatório? | Padrão | Significado |
|---|---|---|---|---|
| `target` | string | sim | | `id` da faixa barramento |
| `level` | número | sim | `0.5` ao criar (−6 dB) | ganho linear, 0..2 |
| `pre` | bool | não | `false` | antes do fader da faixa |

Um envio cujo `target` não existe, não é barramento, é a própria faixa ou fecharia um ciclo continua no documento mas **não vai ao motor** (`_routeIndex` em `controller.dart`).

#### Faixa de automação (`AutoLane`, `model.dart:255`)

| Campo | Tipo | Obrigatório? | Padrão | Significado |
|---|---|---|---|---|
| `id` | string | sim | | |
| `target` | objeto | sim | | ver abaixo |
| `points` | lista de ponto | sim | | ordenados por `beat` ao escrever pelo editor; o controlador reordena de forma estável antes de mandar ao motor |
| `open` | bool | não | `true` | sub-raia aberta embaixo da faixa |

`target` (`AutoTarget`, `model.dart:219`): `{"kind": ..., "ref": ..., "param": ...}`.

| Campo | Tipo | Obrigatório? | Padrão | Significado |
|---|---|---|---|---|
| `kind` | string | sim | | `volume`, `pan`, `instrument`, `effect` ou `send` (`AutoKind`). **Valor desconhecido lança** (`byName`) e o documento não abre |
| `ref` | string ou `null` | não | `null` | `effect`: `id` do slot; `send`: `id` da faixa barramento; nos outros, `null` |
| `param` | int | não | `0` | id do parâmetro (`instrument` e `effect`) |

Ponto (`AutoPoint`, `model.dart:243`): `beat` (número, batidas, obrigatório), `value` (número, obrigatório, na unidade do alvo: ganho linear no volume e no envio, −1..1 no pan, unidade da tabela nos parâmetros) e `curve` (−1..1, padrão `0` = reta; formato `t^(2^(curva·3))`, ver `automation_math.dart`). Alvo que não existe mais (efeito removido, parâmetro fora da tabela) fica no documento e é ignorado ao montar as chamadas ao motor (`_resolve` devolve `null`).

#### Marcador (`Marker`, `model.dart:402`)

| Campo | Tipo | Obrigatório? | Padrão | Significado |
|---|---|---|---|---|
| `id` | string | não | `newId()` gerado na leitura | |
| `beat` | número (batidas) | sim | | |
| `name` | string | não | `''` | |
| `color` | int ARGB | não | `0xFFE3B341` (4293112641) | cor da bandeirinha |

#### Exemplo mínimo (projeto novo vazio, "Vazio")

```json
{
  "version": 1,
  "bpm": 120.0,
  "beats_per_bar": 4,
  "tracks": [
    {
      "id": "k3j9x0q2m1ab", "name": "Áudio 1", "color": 0, "gain": 1.0, "pan": 0.0,
      "mute": false, "solo": false, "kind": "audio", "params": {}, "sample": null,
      "armed": false, "monitor": false, "clips": [], "midi": [], "effects": [],
      "sends": [], "output": null, "lanes": []
    }
  ],
  "samples": {},
  "loop_on": false, "loop_start": 0.0, "loop_end": 16.0,
  "metronome": false, "master_gain": 1.0, "master_pan": 0.0,
  "count_in": true, "rec_latency_ms": 0.0,
  "master_effects": [], "master_lanes": [], "markers": []
}
```

#### Exemplo com os campos condicionais (trechos)

```json
{
  "id": "clip1", "sample": "e3b0c4…(64 hex)", "takes": ["e3b0c4…", "9f86d0…"],
  "start": 4.0, "offset": 0.25, "length": 3.5, "gain": 1.0, "fade_in": 0.01, "fade_out": 0.0,
  "warp": true, "source_bpm": 96.0, "pitch": -2.0, "reverse": true
}
```
```json
{ "id": "lane1", "open": true,
  "target": { "kind": "effect", "ref": "slotabc12345", "param": 3 },
  "points": [ { "beat": 0.0, "value": 900.0, "curve": 0.0 }, { "beat": 8.0, "value": 6000.0, "curve": -0.4 } ] }
```
```json
{ "id": "m1", "beat": 16.0, "name": "Refrão", "color": 4293112641 }
```

#### Fora do documento

Vivem só no controlador: seleção (`selectedClip`, `selectedTrack`, `selectedMarker`), zoom e rolagem (`pxPerBeat`, `scrollBeat`, `follow`), grade (`snap`), altura das faixas (`laneScale`), modo da régua, painel de baixo (`dock`, `editingClip`), teclado do computador (`keyboardOn`, oitava, velocidade), entradas MIDI e a entrada de áudio escolhida (`inputDevice`, guardada em `rec:input`); também o aviso de projeto trocado (`remoteNotice`, dispensado por `clearRemoteNotice`) e o contador de ponteiros apertados (`_pointersDown`, alimentado por `_onPointer`, uma rota global do `GestureBinding.instance.pointerRouter`), que só servem ao pull do `SyncService` (`busyEditing`: gravando, tocando ou ponteiro apertado; ver [12 Sincronização](12-sincronizacao.md)).

### Mapa de andamento e de compassos no documento

`app/lib/daw/tempo_map.dart` (a mesma conta de `engine/src/tempo.rs`; ver [01-motor.md](01-motor.md#mapa-de-andamento-e-de-compassos-enginesrctempors)), `tempo_lane.dart` (a faixa `Andamento` e o diálogo de compasso), campos e conversões em `model.dart`, edição em `controller.dart`.

**JSON.** Dois campos novos na raiz do documento, ambos **omitidos** quando não há mudanças (`toJson` só os escreve com `!tempo.isSingle` e `!meter.isSingle`), então um documento sem mapa sai byte a byte igual ao de antes:

```json
"bpm": 120.0, "beats_per_bar": 4,
"tempo_map": [ {"beat": 0.0, "bpm": 120.0, "ramp": 0}, {"beat": 32.0, "bpm": 60.0, "ramp": 0} ],
"meter_map": [ {"bar": 1, "num": 4, "den": 4}, {"bar": 9, "num": 3, "den": 4}, {"bar": 13, "num": 6, "den": 8} ]
```

- `tempo_map[i]`: `beat` (número, batidas do projeto desde 0), `bpm` (número, 20 a 999), `ramp` (escrito como `0` ou `1`; a leitura aceita também `true`/`false`). Rampa: do ponto ao seguinte o BPM anda em reta em função da batida; senão salta no seguinte. O primeiro ponto, na batida 0, espelha `bpm` (o andamento inicial): `DawDoc.tempo` usa o `bpm` da raiz para o ponto 0, e `setTempoMap`/`setTempo` mantêm os dois iguais.
- `meter_map[i]`: `bar` (inteiro ≥ 1), `num` (1 a 64), `den` (`1`, `2`, `4`, `8`, `16`, `32`; outro valor vira `4`). A batida do documento é a semínima: um compasso dura `num × 4 ÷ den` batidas. `beats_per_bar` continua sendo o campo que a barra e o servidor conhecem: espelha o primeiro compasso (`num` quando `den` é 4; `round(num × 4 ÷ den)`, limitado a 1–32, quando é outra fórmula, então 6/8 é 3 e 7/8 é 4 no campo, embora o mapa guarde 3,5 batidas).
- **Normalização** (`normalizeTempoPoints`, `normalizeMeterChanges`, chamadas no construtor e em `fromJson`): descarta não finitos, batida negativa vira 0, bpm preso a 20–999, na mesma batida (ou no mesmo compasso) o último vale, ordena, garante o ponto da batida 0 (ou o compasso 1) e limita a `maxTempoPoints = 4096` pontos e `maxMeterChanges = 1024` mudanças (os de batida ou compasso menores ficam; os mesmos valores de `MAX_TEMPO_POINTS`/`MAX_METER_POINTS` do motor, com `minBpm`/`maxBpm` 20 e 999 e `minBpmInt`/`maxBpmInt` para o espelho do servidor, tudo em `tempo_map.dart`; desde `dd4ef07`, antes eram 512 e 256). Passar do limite avisa em `error` (`tempoPointsFullMessage` = `O mapa de andamento chegou ao limite de 4096 pontos.`, `meterChangesFullMessage` = `O mapa de compassos chegou ao limite de 1024 mudanças.`). Um mapa que sobra com **um ponto só** vira `[]` ("sem mapa"); para o compasso, um só `n/4`. Um único compasso `6/8` ou `7/8` **não** é "sem mapa" (`MeterMap.isSingle` exige `den == 4`) e é gravado.
- **Compatibilidade.** Documento antigo (sem os campos) abre com mapas `[]`: um andamento e um compasso só, e o som é o de antes (`documento antigo abre e salva igual, sem os campos novos` em `app/test/tempo_map_test.dart`). Campos estranhos dentro dos itens não derrubam a leitura. **App velho com documento novo:** o app antigo ignora `tempo_map` e `meter_map` na leitura e **os perde na próxima gravação** (regra geral de campos desconhecidos, ver acima); o projeto passa a tocar no andamento inicial e no compasso `beats_per_bar`/4. O espelho no servidor (`projects.bpm`, `projects.beats_per_bar`) guarda só o inicial; o servidor trata o documento como JSON opaco (nada em `server/src/routes/docs.rs` lê `bpm` ou os mapas).

**Objetos de conta.** `DawDoc.tempo` (`TempoMap`) e `DawDoc.meter` (`MeterMap`) são getters com cache: refazem-se quando a **lista** troca de identidade (`identical`), muda de tamanho ou muda o `bpm`/`beatsPerBar`. Por isso o código troca a lista inteira (`d.tempoMap = [...]`) em vez de mexer num item. `TempoMap` guarda os segundos acumulados por ponto e oferece `secondsAt(batida)`, `beatAt(segundos)`, `bpmAt(batida)`, `indexAt`, `pointAt`; `MeterMap`, `barStart`, `barOf`, `barBeats`, `barBeatsAt`, `changeAt`, `nearestBarStart`. Conversões do documento: `DawDoc.secondsAt`, `beatAtSeconds`, `bpmAt`, `clipEnd`, `clipBeats`, `sourceTempoAt(clip, beat)` (segundos do áudio por batida, para arrastar e desenhar), `sourceSeconds(clip, de, até)` (segundos da origem entre duas batidas, para cortar e aparar), `contentEnd` e `durationSeconds` (pelo mapa). `formatPosition(beat, beatsPerBar, {meter})` conta compassos pelo mapa quando ele existe.

**Controlador** (`controller.dart`, seção "mapa de andamento e de compassos"):

| Método | O que faz |
|---|---|
| `setTempoMap(pontos, {undoable})` | troca o mapa inteiro; o ponto da batida ≤ 0 dado vira `doc.bpm`; um ponto só apaga o mapa; edição desfazível; vai ao motor (`_sync`) e ao servidor (`_mirrorTempo`). Bloqueado gravando (`Pare a gravação para mudar o andamento.`) |
| `setMeterMap(mudanças, {undoable})` | troca o mapa de compassos; `beatsPerBar` acompanha o primeiro compasso (ver acima). Bloqueado gravando (`Pare a gravação para mudar o compasso.`) |
| `addTempoPoint(beat, {bpm, ramp})` | ponto novo no BPM vigente ali (`bpmAt`); na batida de um ponto existente só iguala o BPM |
| `moveTempoPoint(i, {beat, bpm, undoable})` | muda BPM e/ou batida; o ponto 0 não sai da batida 0; não passa dos vizinhos (folga de `1e-3`); `undoable: false` é o passo de arraste (quem chama faz `checkpoint()` antes, uma vez) |
| `removeTempoPoint(i)`, `setTempoPointRamp(i, ramp)` | apaga (menos o 0) / troca salto e rampa |
| `setMeterAt(bar, num, den)`, `removeMeterChange(bar)` | põe e desfaz mudanças de compasso (mudar para o que já vale ali não faz nada; a do compasso 1 não se remove) |
| `setTempo(bpm, beatsPerBar)` | `bpm` é `num` (com decimais, limitado a `minBpm`..`maxBpm`); mantém o ponto 0 do mapa igual ao `bpm` novo e iguala o primeiro compasso do mapa a `beatsPerBar`/4 quando ele já era `n/4` **ou quando `beatsPerBar` mudou** (antes de `dd4ef07` um `6/8` inicial ficava como estava). Pegadinha: `changed` compara com `doc.beatsPerBar`, que num `6/8` vale 3 e num `7/8` vale 4, então pedir `3/4` num `6/8` (ou `4/4` num `7/8`) não muda nada `(lido do código)`. Na `_TempoDialog` o valor `0` em `beatsPerBar` significa "deixar o compasso inicial como está" e o botão passa `c.doc.beatsPerBar` |
| `tempoLaneVisible`, `toggleTempoLane()` | a faixa `Andamento` à mostra: `_tempoLane ?? !doc.tempo.isSingle` (automática com mapa, manual depois do primeiro clique; **não** vai no documento) |
| `snapBeat(b)` | com `Snap.bar` e mapa de compassos, encaixa em `meter.nearestBarStart(b)` |
| `secondsAt`, `bpmAt` | atalhos para o relógio em segundos e o BPM vigente |

**Do documento ao motor.** `_tempoMapCalls(cache)` (chamado por `_docCalls`) compara a assinatura (`jsonEncode` dos pontos) com `_SyncCache.tempoSig`/`meterSig` e só então emite `tempo_clear` + um `tempo_point` por ponto e `meter_clear` + um `meter_point` por mudança; volta ao mapa simples manda o `tempo_clear` seco. Vão logo depois do `tempo`. Ver a tabela em "Como cada mudança vira chamadas ao motor" e [02-pontes-web-e-android.md](02-pontes-web-e-android.md#chamadas-do-mapa-de-andamento-e-de-compassos-tempo_clear-tempo_point-meter_clear-meter_point).

**Consumidores no app** (tudo que antes multiplicava `beat * 60 / bpm` passa pelo mapa): relógio da barra (`_Position`, `secondsAt`), régua e grade (`_RulerPainter`, `_GridPainter` por `MeterMap`; régua em mm:ss por `secondsAt` e `beatAt`), etiqueta do mouse na régua, clipes (largura por `clipBeats`, arrastar e aparar por `sourceTempoAt`, cortar e sobrepor por `sourceSeconds`), estimativa de posição durante o play (`_estimatedBeat`), contagem e passadas da gravação (`_Recording.tempo`, `framesBetween`, `recordingPasses(tempo:)`, `_countFrames`, compasso da contagem por `meter.barBeatsAt`), exportação e congelar (`secondsAt`), render (`renderTempoMap`, `renderFrames`, `prepareRenderCalls` no Dart e o `tempoMapOf` do `render-worker.js`), `DurationLabel`, dialogo de exportação (`_bars`, `_spanSeconds`), e o botão de andamento (`_TempoButton`: `bpmAt` no cursor, `↗` quando o trecho é uma rampa que sobe e `↘` quando desce, sem seta se os dois BPM são iguais). O áudio → MIDI usa o BPM vigente na batida do clipe (`notesForClip(r, audio, doc.bpmAt(audio.start))`).

**Warp.** Decisão: `WarpSpec.of(c, doc.bpm)` (o inicial) em toda parte (`setClipWarp`, `_clipSound`, congelar). O clipe esticado toca a velocidade constante; se atravessa uma mudança de andamento, sai da grade. O `warp_dialog.dart` avisa: `O projeto tem mudanças de andamento: o warp estica o áudio para o andamento INICIAL (X BPM) e ele toca em velocidade constante, sem acompanhar as mudanças.` Mudar só outros pontos do mapa não refaz o warp.

**Importador de MIDI.** Desde `020003f` (fase 11) o `.mid` leva e traz o mapa: `applyImportedTempo` (`controller.dart:2569`) escreve `d.bpm`/`d.tempoMap` e `d.beatsPerBar`/`d.meterMap` **direto no documento** (dentro do `edit` da importação, um só passo do desfazer), com as listas de `importedTempo`/`importedMeter`; não chama `setTempoMap`/`setMeterMap` (que existiam como ganchos, teste `ganchos do importador de MIDI: setTempoMap e setMeterMap`, e continuam servindo à faixa `Andamento`). O espelho para o servidor e o motor sai por `_mirrorTempo()` e pela sincronização normal (`_tempoMapCalls`). Formatos e limites em "Arquivo MIDI padrão". `(lido do código; testado só por testes automáticos)`

**Compassos pelo mapa (desde `dd4ef07`; antes tudo isto usava `doc.beatsPerBar`, o compasso inicial).** O piano roll (`_barsIn` em `piano_roll_paint.dart` desenha compassos e números da grade e da régua a partir de `MeterMap`; sem mapa, `n/4` contado do começo do clipe como a grade de encaixe; `_barLen` e `_ceilBar` em `piano_roll_input.dart` servem a `Shift`+← →, colar, duplicar, o espaço depois do fim e as ferramentas que crescem o clipe; `_formatSpan(..., meter:, from:)`), `createMidiClip` sem `length` (`meter.barBeatsAt(start)`), o arredondamento em compassos de notas gravadas (`_placeRecordedNotes` com `floorBarStart`/`ceilBarStart`), `fitRange`, o tamanho mínimo do minimapa (`meter.barStart(5)`), o passo `Compasso` (`snapBeat` e `_gridBeats(c, at)` com `barBeatsAt`) e a conta de compassos do tooltip de `DurationLabel` (`meter.barOf(contentEnd)`). `MeterMap` ganhou `floorBarStart`, `ceilBarStart` e `spanBars`. Continua com `beatsPerBar` fixo o `Z/4` da pergunta de andamento do `.mid` (`askUseFileTempo`, `midi_file_ui.dart`: um projeto em `6/8` aparece como `3/4`).

### Duas armadilhas de compatibilidade do esquema

1. **Tipos de faixa novos em app velho.** `TrackKind.parse` devolve `audio` para um `kind` que a versão não conhece. Um app antigo que abre um projeto com faixa `fm`/`wavetable` a lê como `audio`, e ao salvar **regrava `audio`**, perdendo o tipo (aconteceu com um APK velho instalado por engano em 30/09/2026, segundo as notas de processo). `AutoKind.byName` é o oposto: lança, e o documento não abre.
2. **Sidechain é índice de faixa, não id.** O parâmetro `10` do compressor e o `6` do gate guardam o **índice** da faixa-chave (−1 = desligado, faixa `-1..63` na tabela). Por isso `removeTrack`, `duplicateTrack`, `moveTrack` e o congelar reescrevem esses valores (`_remapSidechains` em `controller.dart`). Editar o documento por fora (ou mesclar dois documentos) exige o mesmo cuidado.
3. **Mapas em app velho.** `tempo_map` e `meter_map` só existem a partir da fase 10: um app anterior os ignora ao ler e os perde ao gravar (o projeto vira um andamento e um compasso só, o `bpm` e o `beats_per_bar` da raiz). Ver "Mapa de andamento e de compassos no documento".

## Fluxo de dados / ciclo de vida do `DawController`

O controlador (`daw/controller.dart`, ~4 400 linhas) é criado por `ProjectScreen.reload` (`DawController(project)..open()`) e descartado no `dispose` da tela. Construtor: `DawController(project, {engine, store, api, canSync, syncTimeScale, patchProject})`; os cinco últimos existem para os testes (`FakeEngine`, servidor falso; `patchProject` troca o `PATCH` do espelho do andamento).

### Grupos de métodos (seções do arquivo)

| Grupo (linha) | Responsabilidade |
|---|---|
| funções puras (`:90`–`:265`) | `flattenNotes`, `quantizeNoteList`, planejamento de gravação (`recordingPasses`, `gatherFrames`), mapa de teclas do computador |
| abrir (`:585`) | `open()`, `_onEngineState`, `_fromTemplate`, `_loadSample`, `_register`, `dispose` |
| motor (`:752`) | `_sync()` e o cache do que o motor já recebeu |
| warp e tradução para o motor (`:789`–`:1260`) | `_clipSound`, `setClipWarp`, `detectClipBpm`, `_settleWarp`; e a tradução documento → chamadas: `_fullSyncCalls`, `_docCalls`, `_monitorCalls`, `_syncChain`, `_routeIndex`, `_syncRouting`, `_automationCalls`, `_resolve`, `_watchCalls` |
| transporte (`:1261`) | `togglePlay`, `stop`, `seek`, `toggleLoop/Metronome/CountIn`, `setRecLatency`, `setLoop`, `setTempo` |
| mapa de andamento e de compassos (logo depois de `setTempo`) | `setTempoMap`, `setMeterMap`, `addTempoPoint`, `moveTempoPoint`, `removeTempoPoint`, `setTempoPointRamp`, `setMeterAt`, `removeMeterChange`, `_tempoMapCalls`, `secondsAt`, `bpmAt`; a visibilidade da faixa (`tempoLaneVisible`, `toggleTempoLane`) fica na seção de visão |
| edição (`:1335`) | `edit`, `checkpoint`, `mutate`, `undo`, `redo`, `_prune`, `_scheduleSave`, `_save` |
| sincronização (`:1423`) | `_obtainSample`, `_fetchMissing`, `_applyRemote`, `convertToMidi` (áudio → MIDI pelo servidor), `snapBeat` |
| faixas (`:1555`) | `addTrack`, `removeTrack`, `duplicateTrack`, `moveTrack`, roteamento inválido (`_dropRoutesTo`, `_dropBackwardRoutes`), `_remapSidechains` |
| clipes (`:1711`) | seleção, `moveClipToTrack`, `deleteSelected`, `placeOnTop` (o clipe novo recorta o que cobre), `duplicateSelected`, `splitAtPlayhead` |
| importar (`:1919`) | `importAudio`, `importBytes`, `_ingest`, `importSamplerAudio/Bytes` |
| instrumentos e MIDI (`:2031`) | `addInstrumentTrack`, `createMidiClip`, `noteOn/noteOff` ao vivo, `setParam`, `applyPreset`, `setInstrumentSample`, `quantizeNotes`, painéis (`setDock`) |
| teclado do computador (`:2224`) e MIDI (`:2301`) | `toggleKeyboard`, `handleNoteKey`, `enableMidiInput`, `_onMidi` (notas, pedal de sustentação) |
| efeitos, roteamento, automação (`:2399`) | rack (`addEffect`, `removeEffect`, `moveEffect`, `setEffectParam`, `setEffectBypass`, `applyEffectPreset`), barramentos (`addBusTrack`, `setSend`, `removeSend`, `setOutput`), automação (`automatable`, `addLane`, `removeLane`, `targetRange`), observação (`watchEffect`, `watchAnalyzer`) |
| gravação de automação | `automation_record.dart` (`simplifyAutoSamples`: RDP na escala do controle, tolerância 0,8%; `applyAutoTake`: sobrescreve a região, pontos antes/depois, reamostra o trecho curvo cortado; `AutoRecorder`: `touch`/`value`/`release` chamados pelos setters e pelos controles, `_onBeat` amostra, `_endSession` guarda o passo de desfazer), `automation_mode.dart` (`AutoMode`, botão da barra e seletor da raia). Glue no controlador: `autoRec`, `autoInfo`, `autoApply`, `autoCommitUndo`; `checkpoint` absorve o do gesto anunciado; a raia gravada sai de `_automationCalls` e de `liveTargetValue` |
| gravação, exportação, bounce (`:2740`) | armar/monitorar, entradas de áudio, `toggleRecord`, contagem, tomadas, `exportAudio`, `cancelRender`, `bounceTrack` |
| visão (`:3945`) | zoom, rolagem, enquadrar |
| marcadores e seções (`:4016`) | `addMarker`, `moveMarker`, loops por seção/marcadores/seleção |

### `open()` (`DawController.open` em `controller.dart`)

1. Confere `_engine.supported`; `_engine.start()` devolve a taxa do motor (`engineRate`).
2. Lê `doc:<id>` do `LocalStore`. Se existe, `DawDoc.fromJson`. Senão `_fromTemplate()`: se há `template:<id>` (modelo escolhido ao criar; apagado na hora), `ProjectTemplate.build`; senão `_fresh()` (uma faixa `Áudio 1`, `loop_end = beats_per_bar * 4`). O modelo `Vazio` da tela de projetos **não** grava `template:<id>`, então cai em `_fresh()`.
3. (Não sobrescreve mais `doc.bpm` e `doc.beatsPerBar` com os do projeto: o documento local vale; só um documento novo, de `_fromTemplate`/`_fresh`, parte dos do projeto.)
4. Carrega cada áudio de `doc.samples` (`sample:<hash>` → `_engine.decode` → `_register`, que atribui um id inteiro ao hash em `_sampleIds`, manda ao motor e desenha a forma de onda). Áudio ausente do aparelho entra em `missing`.
5. Sincronização: `sync.start(localExisted: ...)`. **Espera de até 25 s** (o `started.timeout(const Duration(seconds: 25))` em `DawController.open`) quando `saved is! String && !_templated && _canSync()`, isto é, projeto sem documento local, sem modelo e com sessão: nesse caso o projeto pode existir só no servidor (criado em outro aparelho) e o spinner só termina depois da primeira conversa (documento + áudios). Ver [12 Sincronização](12-sincronizacao.md). Nos demais casos a sincronização segue em segundo plano. Nesse caso `open` guarda também o documento vazio (`_blankJson`): o `_applyRemote` que o troca pelo do servidor não põe o `remoteNotice` (`Projeto atualizado de outro aparelho…`), que só sai quando havia documento local que mudou (resolvido em `1180152`). Se o projeto está gravando, tocando ou com um gesto em andamento, o pull da abertura não troca e tenta de novo 2 s depois (ver [12 Sincronização](12-sincronizacao.md)).
6. `ready = true`, primeiro `_sync()` (manda o documento inteiro ao motor), `_lastSaved` = documento atual. Faixa de áudio que estava armada ou monitorando reabre a entrada (`_restoreInput`).

### `edit()` e o desfazer (`DawController.edit`, `checkpoint`, `mutate`, `undo`/`redo` e `_travel` em `controller.dart`)

```
edit(fn, undoable: true)
  ├─ checkpoint()   ← empilha jsonEncode(doc.toJson()) em _undo (máx. 200), limpa _redo
  └─ mutate(fn)
        ├─ fn(doc)
        ├─ _prune()          esquece seleção/editor/rack que sumiram
        ├─ _sync()           diferença → chamadas ao motor
        ├─ _scheduleSave()   debounce de 400 ms → _save()
        └─ notifyListeners()
```

- **O histórico guarda documentos inteiros como texto JSON**, não comandos. `undo`/`redo` (`_travel`) reconstroem o `DawDoc` do JSON e depois **restauram do estado atual** o que é preferência do aparelho e não deve ser desfeito: `metronome`, `count_in`, `rec_latency_ms`, `armed`, `monitor` de cada faixa; `loop_on` também fica, a não ser que o passo desfeito tenha mudado a região do loop. O `midi_map` também fica (`..midiMap = before.midiMap`): o mapa mora no histórico só como cópia no JSON e nunca é restaurado por ele, então mapear e desfazer uma nota são independentes ([MIDI learn](#midi-learn)).
- **Arraste**: `checkpoint()` no início e `mutate` a cada passo (um passo só no histórico). Com a gravação de automação ligada (`AutoRecorder`), o `checkpoint` do gesto anunciado por `touch` é engolido e a passada inteira entra como um passo só ao parar (seção [Gravação de automação](#gravação-de-automação-automation_recorddart-automation_modedart)). `edit(..., undoable: false)` para preferências (metrônomo, contagem, latência, armar).
- **Caminhos rápidos** (`setParam` `:2185`, `setEffectParam` `:2487`): mudam o valor, mandam **uma** chamada (`param` ou `fx_param`) e atualizam o cache `_sent`, sem `_sync()` do documento inteiro. Se o motor ainda não tem aquele efeito naquele slot, caem no `_sync()` completo (um `fx_param` solto atingiria outro efeito).
- `setTempo` (`controller.dart:1565`) edita o documento (entra no desfazer) e chama `_mirrorTempo()`, o `PATCH /api/projects/{id}` de `{bpm, beats_per_bar}` **best-effort**: não lança offline e o valor pendente sai de novo em `_save` (desfazer e refazer incluídos), no fim de `open()` e de `_applyRemote` e quando `sync.phase` vira `synced` (`_onSyncPhase`). Detalhes em [12 Sincronização](12-sincronizacao.md#andamento-e-compasso-documento-é-a-fonte-o-servidor-espelha).

### Como cada mudança vira chamadas ao motor (`_sync`, `_docCalls`)

`_sync()` (`:762`) chama `_docCalls` com o cache `_SyncCache` (o que o motor já recebeu) e envia tudo numa mensagem (`_engine.calls`). Ordem: **áudio → instrumentos → efeitos → roteamento → automação → observação → notas → monitoração da entrada**.

| Parte do documento | Chamadas (nome dos exports do motor) | Reenvio |
|---|---|---|
| andamento, nº de faixas, master, loop, metrônomo | `tempo`, `tracks`, `master`, `loop_set`, `metronome` | sempre, inteiro |
| mapa de andamento e de compassos | `tempo_clear` e `tempo_point beat bpm ramp` por ponto; `meter_clear` e `meter_point bar num den` por mudança (logo depois do `tempo`, antes de `tracks`) | só quando a assinatura (`_SyncCache.tempoSig`/`meterSig`) muda; sem mapa nada vai (o `tempo` já basta) |
| faixa (volume, pan, mudo, solo) | `track i gain pan mute solo` | sempre |
| clipes de áudio | `clips_clear` e `clip_add track sample start offset length gain fade_in fade_out`, seguido de `clip_fade_shape in out` (do último clipe) só quando alguma curva não é a linear | sempre, a lista inteira |
| tipo da faixa | `track_kind i kind.index` (o **índice** do enum é o código do motor) | só quando o tipo daquele índice muda |
| parâmetros do instrumento | `param i id valor` | só os que mudaram (`_SentTrack.params`) |
| áudio do sampler | `instrument_sample i id` | só quando muda |
| cadeia de efeitos (faixas e master, `track = -1`) | `fx_count`, `fx_set track slot code`, `fx_param`, `fx_bypass` | só o que mudou; tipo novo no slot manda tudo daquele slot |
| envios e saída | `sends_count`, `send_set i k bus level pre`, `track_output i bus` | só o que mudou |
| automação | `auto_clear`, `auto_lane track code slot id`, `auto_point lane beat value curve` | a automação inteira, **só quando a lista de chamadas muda** |
| observação (medidor, analisador) | `watch_fx`, `watch_analyzer` | quando muda o alvo |
| notas dos clipes MIDI | `notes_clear`, `note_add track start length pitch velocity` | a lista inteira quando muda (`flattenNotes`) |
| entrada monitorada | `input_monitor i on` | só o índice que mudou |

Pontos que não são óbvios:

- **Ids do motor**: cada sha-256 vira um inteiro sequencial (`_sampleIds`); os sons do warp usam a chave `warp:<key>` no mesmo mapa.
- **Índices**: faixas e slots são identificados no motor por posição. Se a lista de ids de faixa deixa de ser prefixo da anterior (faixa removida ou reordenada), `_sync` solta o que soa ao vivo (`_releaseLive`) e zera o cache das faixas, para tudo ser reenviado.
- **Roteamento**: faixa comum manda para qualquer barramento; barramento só manda para barramento de índice **maior** que o dele. A ordem das faixas é a ordem do sinal (`_routeIndex`).
- **Automação**: entre dois pontos o valor anda na escala do controle do alvo (curva do fader no volume e nos envios, logarítmica em Hz/s). O motor só interpola reto, então esses segmentos viram vários pontos curtos (a cada 1/8 de batida, 4 a 64 por segmento) em `autoEnginePoints` (`daw/automation_math.dart:55`). `autoValueAt` é a mesma conta que o desenho da raia e os knobs (que seguem a automação tocando) usam.
- **Gravando**, loop, metrônomo e automação podem estar trocados pela contagem (`_loopOverride`, `_countMetronome`, `_autoSuppressed`): o sync manda o que vale agora, não o que está no documento.
- **Render fora de tempo real** (`exportAudio`, `bounceTrack`): `_fullSyncCalls()` chama o mesmo `_docCalls` com um cache vazio, ou seja, o documento inteiro como lista de chamadas para um motor novo. `_callsFor(outro)` faz isso para um documento diferente (o do congelamento) trocando `doc` só durante a montagem síncrona.

### Importação e SHA-256

`importAudio` (`:1924`) abre o seletor (extensões `wav mp3 ogg oga flac m4a aac opus webm aif aiff`, `audioExtensions` `:1921`) e chama `importBytes(files, at, track)`. Para cada arquivo, `_ingest(name, bytes)` (`:1972`):

1. `hash = await _engine.sha256Hex(bytes)` (WebCrypto no navegador; num isolate no Android). O hash é do **arquivo original**, não do PCM decodificado.
2. Se o hash ainda não tem forma de onda: `_engine.decode`, `LocalStore.put('sample:<hash>', bytes)` (os bytes originais, mp3 continua mp3), `_register`, e `doc.samples[hash] = SampleInfo(nome, duração)`.
3. O clipe entra na faixa de áudio selecionada se ela existe, é de áudio, é o primeiro arquivo e o trecho está livre; senão numa faixa nova com o nome do arquivo (sem extensão, até 40 caracteres).

O mesmo hash é o endereço do áudio no servidor (`PUT /api/samples/{hash}`), o que dá deduplicação e conferência de integridade de graça. Gravações e congelamentos seguem o mesmo caminho: WAV 32f codificado (`encodeWav`), sha-256 e `sample:<hash>`.

### Gravação (`:2740`–`:3580`)

`setArmed` arma a faixa (áudio grava a entrada; instrumento grava notas); armar a primeira faixa de áudio abre a entrada (`_needInput`, microfone). `toggleRecord` → `_startRecording` → `_beginRecording`:

- conta um compasso antes do cursor (`count_in`), com o metrônomo ligado só na contagem; onde não cabe (primeiro compasso, ou o fim do loop dentro da contagem) a contagem toca numa região vazia bem depois do fim de tudo (`zone`) e o cursor exibido anda o compasso anterior;
- o motor liga a captura (`capture`) e o Dart junta os blocos de entrada (`_onRecordBlock`) com a batida exata do primeiro quadro (`recordBeat`);
- `_finishRecording` espera a latência da entrada, para o transporte, desliga a captura (que devolve as notas tocadas: `onCaptureEnd`) e chama `_commitRecording`;
- `_commitRecording` transforma o áudio em WAV 32f, calcula o sha-256, guarda `sample:<hash>`, cria `AudioClip`s (em loop, cada passada é uma tomada e a ativa é a última passada completa, `_planAudio`), coloca as notas (`_placeRecordedNotes`, overdub no clipe sob o cursor ou clipe novo) e faz tudo **num passo do desfazer**. A entrada estéreo que é mono de fato vira um canal só (`_inputChannels`). Menos de 50 ms de áudio útil não vira clipe.

**Latência da gravação (fase 13).** `_beginRecording` (`controller.dart:3957`) lê uma vez, ao começar, `_outputLatency` (`:3661`) = `_engine.latency` (aparelho, s) + `_engine.engineLatency` (motor, s: PDC, cadeia do master, limitador de segurança; ver [02](02-pontes-web-e-android.md)) e guarda no `_Recording`: `latency` = `_outputLatency` + `_inputLatency` + `rec_latency_ms / 1000`, só se a gravação tem áudio (`audio`), que vira `skip` (quadros descartados do começo do que a entrada mandou; negativo acrescenta silêncio) e a espera do `_finishRecording` (`latency` + 20 ms); e `midiLatency` = só `_outputLatency`, sem a entrada nem o `rec_latency_ms`. As notas e os CCs voltam por `_Recording.shiftBeat` (`:405`), que subtrai `midiLatency` em segundos pelo mapa de andamento da gravação e trava em 0; em `_recordedNotes` a nota também tem um piso (`min(início da gravação, início do loop se o loop está ligado)`: uma nota que já estava antes dele não recua mais), e em `_recordedControls` (`:4472`) o ponto de CC só passa por `shiftBeat`. `engineLatency` vale 0 num motor sem a chamada (`engine_web.dart` e `engine_ffi.dart` engolem a ausência), então o comportamento antigo (só o aparelho) é o fallback. `monitorLatency` (`:3668`) = `_outputLatency` + entrada é a ida e volta da faixa monitorada; só os testes o leem, nenhuma tela o mostra. Testes: `recording_test.dart`, grupo `latência do motor na gravação`, com o `FakeEngine.engineLatency` (ver [03](03-build-teste-e-depuracao.md)).

Sem a fase 13 a latência descartada era a do contexto de áudio + a da entrada + `rec_latency_ms` (o MIDI não tinha compensação). Parar durante a contagem cancela sem gravar nada.

**Com mapa de andamento.** `_Recording` guarda o `TempoMap` que valia quando a gravação começou (`tempo`, um mapa constante quando não há mapa) e converte batidas em quadros por ele (`framesBetween`); a contagem dura o compasso do cursor (`meter.barBeatsAt(start)`) e seus quadros vêm de `_countFrames` (segundos entre as batidas pelo mapa); `recordingPasses(..., tempo:)` acha as voltas do loop no quadro que o motor conta; `recordedBeats` estima as batidas gravadas pelo relógio pelo mapa (a contagem, no andamento do começo). Mudar o andamento ou o compasso gravando é bloqueado (`_blockedByRecording`), porque o mapa da gravação é fixo do começo ao fim.

### Congelar (`bounceTrack`, `:3711`)

Renderiza a faixa fora de tempo real (instrumento, clipes, inserts e a automação **deles**) do começo ao fim do conteúdo dela mais 8 s de cauda (`_bounceTail`: o que soar depois disso está abaixo de −100 dB; o silêncio final é aparado por `_trimTail`), num documento auxiliar (`_bounceDoc`): fader em 0 dB, pan no centro, sem mudo, sem solo em nenhuma faixa e sem a automação de volume/pan. O resultado (WAV 32f, mono se os canais são idênticos) vira uma **faixa de áudio nova logo abaixo** com o clipe, herdando volume, pan, mudo/solo, saída, envios e as lanes de volume, pan e envio; a original fica **muda**, perde os envios pré-fader (senão dobrariam) e os sidechains são remapeados. Tudo num passo do desfazer. Barramento congela o que recebe (a música toda). `exportAudio` usa o mesmo render (mixagem `-1` mais stems opcionais, em lotes que cabem em 384 MiB de memória de áudio) e normaliza a −1 dBFS quando pedido.

## `automation_math.dart`: a mesma conta na raia, nos knobs e no motor

`app/lib/daw/automation_math.dart` (72 linhas) é a única definição de como a automação anda entre dois pontos; a raia (`automation_lane.dart`), os controles que seguem a automação tocando (`liveTargetValue`) e o que vai ao motor usam a mesma função.

| Símbolo | O que faz |
|---|---|
| `AutoWarp` | par `(toNorm, fromNorm)` do controle do alvo; `null` = reta no valor |
| `autoShape(t, curve)` | forma entre dois pontos, `t^(2^(curva·3))`, `curva` −1..1 (0 = reta) |
| `autoSegment(a, b, beat, warp)` | valor no segmento: interpola na escala do controle (`toNorm` → reta → `fromNorm`) |
| `autoValueAt(points, beat, fallback, warp)` | valor numa batida (busca binária; antes do primeiro ponto vale o primeiro, depois do último vale o último; sem pontos, `fallback`) |
| `autoEnginePoints(sorted, warp)` | os pontos `(batida, valor, curva)` que vão ao motor; com `warp`, cada segmento vira pontos retos a cada 1/8 de batida (de 4 a 64 por segmento) |

A escala vem de `DawController._warpOf`: `gainToFader`/`faderToGain` (curva cúbica do fader) para volume (`code 0`) e envio (`code 4`); `ParamSpec.toNorm`/`fromNorm` para parâmetros logarítmicos (Hz, segundos); reta para pan e parâmetros lineares. O motor só interpola reto no valor, por isso o Dart discretiza. Teste: `app/test/automation_math_test.dart`.

## Gravação de automação (`automation_record.dart`, `automation_mode.dart`)

> Como o app grava, como pontos de automação, o que a mão faz nos controles com o transporte tocando (modos `Ler`, `Escrever`, `Toque` e `Trava`); para quem mexe no app (controlador, painéis, linha do tempo). O que o usuário vê está em [Automação, Gravar automação](../manual/07-automacao.md#gravar-automação).

### Visão geral

```
controle (fader, pan, envio, knob, mini fader)
   │  touch(track, alvo)   ao agarrar        ┐
   │  value(track, alvo, v) a cada mudança   ├─ AutoRecorder (c.autoRec)
   │  release(track, alvo) ao soltar         ┘
   ▼
_Live por alvo ── _Seg (amostras: batida, valor) ◄── _onBeat (c.beat, uma por atualização)
   │  Toque: solta → _finish       Escrever/Trava: transporte para → _endSession; loop deu a volta → _apply(wrapped)
   ▼
simplifyAutoSamples (RDP na escala do controle)  →  applyAutoTake (encaixe sobre a raia)  →  c.autoApply (mutate, sem checkpoint)
                                                                                          └─ _endSession: c.autoCommitUndo(snapshot)  = 1 passo
```

### Peças e responsabilidades

| Arquivo | Papel |
|---|---|
| `daw/automation_record.dart` | `simplifyAutoSamples` (afinamento), `applyAutoTake` (encaixe na raia, funções puras) e `AutoRecorder` (estado da gravação; `ChangeNotifier`) |
| `daw/automation_mode.dart` | `AutoMode` (`read`, `write`, `touch`, `latch`: rótulo, inicial e frase de cada um), `AutoModeMenu` (botão da barra), `AutoLaneModeButton` (seletor `L`/`E`/`T`/`V` do cabeçalho da raia) e `automationRecordColor` (`#F2433A`) |
| `daw/controller.dart` | `autoRec` (criado no construtor e descartado no `dispose`), `autoInfo`, `autoLaneOf`, `autoSnapshot`, `autoTakeCheckpoint`, `autoCommitUndo`, `autoSyncNow`, `autoApply`; `checkpoint` (consome o "engole"); `_automationCalls` e `liveTargetValue` (a raia gravada sai do motor e do controle); `_onPointer` chama `autoRec.releaseAll()` quando o último ponteiro levanta; `setParam`, `setEffectParam` e `setSend` chamam `autoRec.value` antes de gravar o valor |
| `daw/mixer_panel.dart` | mixin `_DragValue`: `autoKey` (alvo do controle) e as chamadas de `touch` (na primeira mudança do gesto, antes do `checkpoint`) e `release` (em `end()`, também ao fim da roda: 500 ms parada); `_Fader` e `_PanKnob` chamam `value` em `_set`; `_SendRow` só tem `autoKey` se o envio existe |
| `daw/instrument_panel.dart`, `daw/fx_editors.dart` | `onChangeStart` chama `touch` antes de `checkpoint`; `onChangeEnd` chama `release` |
| `daw/timeline.dart` | mini fader do cabeçalho da **faixa** (`_miniStart`, `_miniGain`, `onEnd`; um único `_MiniFader` para tocando e parado, para a árvore não mudar no meio do gesto). O do **master** não foi ligado (ver Armadilhas) |
| `daw/automation_lane.dart` | monta o `AutoLaneModeButton` no cabeçalho da raia, antes do olho riscado |
| `test/automation_record_test.dart` | 640 linhas: afinamento, encaixe puro e gravação sobre o controlador com motor de mentira |

### Fluxo de dados / ciclo de vida

1. **Modo.** `AutoRecorder.mode` (barra) e `laneModes` (mapa `id da raia → AutoMode`, só na sessão, não vai para o JSON do documento). `modeFor(track, alvo)` devolve o da raia do alvo, se tem, senão o da barra. `setMode` e `setLaneMode` com o transporte tocando chamam `_endSession()`.
2. **Agarrar.** `touch` (só se o modo grava e `_canRecord`: transporte tocando e sem gravação de áudio/contagem, senão `notice`) cria o `_Live` do alvo (`_entryFor`: consulta `autoInfo` e `automatable`; alvo sem automação entra em `_rejected` e dá o aviso `Este controle não tem automação.`), tira o `_snapshot` do documento (`autoSnapshot`) e liga `_swallow` por um microtask: o `checkpoint()` que o gesto chama a seguir é **engolido** (`consumeSwallow`), porque o passo de desfazer é o da passada inteira.
3. **Mexer.** `value` chama-se antes de o valor entrar no documento. Sem `touch` prévio (roda, duplo clique, setters chamados de outros lugares) o alvo abre na hora e o ponto de desfazer que o gesto acabou de guardar é **tirado** do histórico (`autoTakeCheckpoint`, só se foi guardado no mesmo turno: `_ckptTurn`) para servir de `_snapshot`. O valor é preso a `[min, max]`, vira `e.last` e uma amostra em `c.beat.value`; na primeira amostra `autoSyncNow()` reenvia a automação ao motor **sem** a raia deste alvo.
4. **Amostrar.** `_onBeat` (ouvinte de `c.beat`) acrescenta `(beat, e.last)` a cada alvo aberto, mesmo com a mão parada. Se o cursor voltou (`b < prev - 1e-6`: loop ou salto), a volta que acabou é aplicada (`_apply(wrapped: true)`) e outra começa na batida nova.
5. **Fechar.** `release` no `Toque` chama `_finish` (aplica e tira o alvo de `_live`). No `Escrever` e na `Trava` o alvo segue até o transporte parar: `_onPlaying(false)` → `_endSession` aplica tudo e, se houve mudança (`_dirty`), `autoCommitUndo(snapshot)` empilha o passo. `_startWrites` (no play) abre, para toda raia com modo próprio `Escrever` que já existe, um trecho com o valor fixo desde o cursor.
6. **Aplicar.** `_apply` afina as amostras (`simplifyAutoSamples`) e chama `c.autoApply(track, alvo, (existing) => applyAutoTake(...))`, que cria a raia se falta (`AutoLane(open: true)`) e troca os pontos com `mutate` (sem `checkpoint`). Uma volta de loop que continua na seguinte usa `AutoMode.latch` mesmo se o modo era `touch`.

### Contratos

- `typedef AutoInfo = ({double min, double max, double fixed, AutoWarp? warp, bool stepped})` vem de `DawController.autoInfo`: `stepped` é verdadeiro para `Curve.choice` e `Curve.integer`.
- `autoSimplifyTolerance = 0.008` (fração da faixa, medida em `autoNorm`: a escala do `warp` do alvo, senão linear) e `autoTouchRamp = 0.25` (batidas).
- `simplifyAutoSamples(samples, {norm, tolerance, stepped})`: descarta não finitos e fora de ordem, na mesma batida fica a última; até 2 amostras, devolve como estão; `stepped` guarda só as trocas (dois pontos na mesma batida); senão Ramer-Douglas-Peucker iterativo (pilha, sem recursão).
- `applyAutoTake({existing, take, mode, fallback, warp, stepped, ramp, norm})`: região = do primeiro ao último ponto do `take`; antes, um ponto com o valor que a curva antiga tinha (ou `fallback`) se difere do primeiro do `take`; depois, no `touch` um ponto em `e + ramp` (em degrau se `stepped`) com o valor da curva antiga, no `write`/`latch` só se há pontos depois. Um trecho curvo cortado é reamostrado (de 2 a 32 retas, 8 por batida). A entrada `existing` não é alterada.
- Saída do motor: `_automationCalls` pula raias com `autoRec.isRecording(track, alvo)`; `liveTargetValue` devolve o valor fixo nesse caso.
- Avisos (`notice`, 5 s): `Este controle não tem automação.` e `A automação não grava junto com a gravação de áudio ou MIDI.`

### Decisões e por quê

- **A raia gravada sai do motor durante o trecho.** Sem isso o motor aplicaria a curva antiga por cima do valor que a mão põe; com o valor fixo indo pelos caminhos rápidos, o que se ouve é o gesto.
- **Os pontos entram na raia só no fim do trecho.** Uma raia que muda a cada quadro obrigaria a reenviar a automação ao motor e a redesenhar a linha do tempo no meio do gesto; o preço é que a raia não cresce na tela enquanto se grava.
- **Afinar na escala do controle.** Uma reta na raia é reta na escala do fader ou logarítmica em Hz; afinar em valor bruto guardaria pontos demais onde a curva é forte e perderia detalhe onde ela é fraca.
- **A passada é um passo só no desfazer.** `touch` engole o `checkpoint` do gesto e `autoCommitUndo` guarda o documento de antes da passada quando o transporte para; o `Ctrl+Z` volta todos os controles e raias criadas de uma vez.
- **Modo só na sessão.** O modo depende do momento de trabalho, não da música; salvá-lo faria um projeto abrir gravando por cima da curva no primeiro play.
- **Seletor por raia sobrepõe a barra.** Deixa uma raia gravando sem que os outros controles do mixer o façam.

### Como testar

```bash
cd app && flutter test test/automation_record_test.dart
```

Grupos: `afinamento` (senoide de 4 s vira no máximo 90 pontos com erro abaixo de 1%; escala do controle; entradas inválidas; parâmetro em degraus; milhares de amostras), `encaixe na automação (função pura)` (região substituída e vizinhança, trecho curvo, escala do fader, Toque sem automação, `Escrever`/`Trava` sem pontos depois, degraus) e `gravação sobre o controlador` (Ler não grava; parado não grava; Toque, Trava e Escrever pela barra e pela raia; loop; parâmetro logarítmico e inteiro; volume nos extremos; envio; sidechain; gravação de áudio; troca de modo tocando; controle mostra o valor fixo e o motor não recebe a raia gravada; raia criada na hora; passada com vários alvos como um passo). Mais um teste de widget do botão da barra e do seletor da raia. Tudo com motor de mentira; o uso real no Chrome (Toque no fader de uma faixa, com recarregar a página depois) foi feito à mão pela sessão que implementou.

### Armadilhas conhecidas

- **O mini fader do cabeçalho do `Master` (`timeline.dart`, `_MasterHeader`) não foi ligado à gravação:** ele ainda chama `c.checkpoint` e `c.mutate(... masterGain ...)` direto, sem `autoRec.touch/value/release`, e não troca o valor pela curva enquanto grava. O fader do canal `Master` no mixer grava. `(lido do código)`
- **`releaseAll` corre em todo evento de ponteiro sem botão apertado.** `_onPointer` chama `autoRec.releaseAll()` quando `_pointersDown == 0` e o evento não é `PointerDownEvent`; com mouse isso inclui o movimento sobre a tela. Numa roda do mouse no `Toque`, mexer o mouse fecha o trecho antes dos 500 ms. `(lido do código; não testado)`
- **O valor fixo do documento acompanha a mão.** `_set`/`setParam` gravam o valor também no documento; depois de um `Toque` a raia volta ao valor antigo, mas o valor fixo (o que se vê parado) fica onde a mão largou. O desfazer o restaura.
- **`_startWrites` não olha a visibilidade da raia.** Uma raia oculta com modo próprio `Escrever` grava desde o play. O modo de uma raia apagada fica em `laneModes` até o fim da sessão (sem efeito).
- **`Escrever` pelo seletor grava o valor fixo desde o play e apaga a curva antiga do trecho** que o cursor percorrer, se o controle não for movido.
- **`setMode`/`setLaneMode` não fazem `_endSession` parado** (só tocando); os `_Live` só existem tocando.
- **A frase do menu do botão é a mesma do tooltip** (`AutoMode.hint`): mudar o texto de um muda o outro, e os testes de widget procuram o rótulo `Ler`, `Escrever`, `Toque` e `Trava`.

## Onde está cada tela em `daw/`

| Arquivo | Papel |
|---|---|
| `timeline.dart` | régua, cabeçalhos das faixas, raias com clipes, sub-raias de automação, linha do master, cursor. **Reordenar x mini fader (fase 13, `18c72f4`):** o `_MiniFader` do `_TrackHeader` leva `key: _faderKey` e o corpo do cabeçalho está num `Listener(behavior: translucent)` cujo `onPointerDown` guarda `_skipReorder = _onSlider(posição global)`; `_onSlider` compara o ponto com o retângulo do fader inflado em `_sliderGuard` (15 px). Com `_skipReorder`, `onLongPressStart` e `onLongPressMoveUpdate` do reordenar retornam sem fazer nada (o `onLongPressEnd` roda, mas `_dragTo` é nulo, então nada se move). A zona de 15 px pega também a borda do botão `FX` e o medidor ao lado do fader. No celular (`compact`) o cabeçalho não tem mini fader, `_faderKey.currentContext` é nulo e a proteção não existe. Teste: `fase13c_test.dart` (`cabeçalho: o deslizador de volume tem prioridade sobre o reordenar`; segurar em cima e a 12 px não reordena, no resto do cabeçalho reordena, e arrastar o deslizador continua mudando o volume) |
| `transport_bar.dart` | barra do transporte e das ferramentas (tocar, gravar, andamento, loop, metrônomo, edição, grade, o botão `Automação` (`AutoModeMenu`), zoom, painéis, teclado, MIDI, importar, exportar, configurações; divisores de 4 px de cada lado para caber em 1512 px; sem o indicador de nuvem); o botão de andamento (`_TempoButton`: BPM vigente no cursor, ícone `show_chart` e `↗` (rampa que sobe) ou `↘` (rampa que desce) com mapa; o texto do BPM vem de `formatBpm` de `tempo_format.dart` (fase 13; `warp_dialog.dart` a reexporta), o mesmo do `projectSubtitle`, da faixa `Andamento`, do warp e da pergunta do `.mid`: arredonda a uma casa e tira o `,0`, então `120,04` sai `120`; o compasso do botão com um andamento e um compasso só vem de `formatDocMeter`) e a janela `Andamento e compasso` (`_TempoDialog`, com o atalho para a mudança de compasso) |
| `tempo_map.dart` | `TempoPoint`, `MeterChange`, `TempoMap`, `MeterMap`, a normalização dos dois e `tempoMapCalls`; Dart puro, sem `dart:ui`. Espelho de `engine/src/tempo.rs` |
| `tempo_lane.dart` | a faixa `Andamento` sob a régua (`TempoLane`, `_TempoPainter`, gestos e menus) e o diálogo `Mudar compasso a partir do compasso N` (`showMeterChangeDialog`) |
| `tempo_format.dart` | o formatador **único** do andamento e do compasso (commit `1180152`, fase 13): `formatBpm(double)` (arredonda a uma casa, sem `,0`, vírgula decimal: `120`, `97,5`; `120,04` e `119,96` viram `120`, `120,06` vira `120,1`), `formatMeter(numerador, denominador)` (`4/4`, `6/8`) e `formatDocMeter(DawDoc)` (o compasso do compasso 1 com a figura verdadeira, por `d.meter.changeAt(1)`, e não um `/4` fixo). Usado pela barra (`_TempoButton`, `_TempoDialog`), pelo `projectSubtitle`, pela faixa `Andamento`, pelo diálogo do warp (`warp_dialog.dart` o reexporta: `export 'tempo_format.dart' show formatBpm`) e pela pergunta do `.mid` (`_bpmText`). Antes havia duas contas: o `formatBpm` de `warp_dialog.dart` (só tirava o `,0` de um valor exatamente inteiro, então `120,04` aparecia `120,0`) e o `_bpmText` de `midi_file_ui.dart` (tolerância de 0,05). Testes: `app/test/fase13b_test.dart` |
| `dock.dart` | painel de baixo em abas (mixer, editor de notas, instrumento, efeitos) |
| `mixer_panel.dart`, `meter.dart` | canais do mixer, medidor de pico |
| `piano_roll*.dart`, `midi_tools.dart`, `piano_roll_tools.dart` | editor de notas (partes de `piano_roll.dart`) e a lógica pura das ferramentas de produtor |
| `instrument_panel.dart`, `knob.dart`, `presets.dart`, `wavetable_shape.dart` | painel do instrumento, controle giratório, presets e ids nomeados, gráfico das tabelas |
| `sampler_zones.dart`, `sampler_zones_controller.dart`, `sampler_zones_panel.dart`, `slice_dialog.dart` | zonas do sampler no app (o motor está em [01-motor.md](01-motor.md#zonas-do-sampler-e-fatiamento-enginesrcsampler_zonesrs)). `sampler_zones.dart` é Dart puro: `SamplerZone`, `maxZones` 128, `nextZoneRange`, `zoneAddBlocker` (a mensagem única `Não dá para criar outra zona: o limite é de 128 zonas ou o teclado já está todo ocupado por zonas de uma nota só. Apague alguma antes.`), `velocityLayers(n, {lo, hi})` (camadas dentro da faixa atual da zona, no máximo o número de valores dela), `parseNoteInput`, `slicePoints(áudio, {count, sensitivity, limit})` (`limit` padrão `maxSlices` = 96, paridade com o motor; o diálogo passa 100000 para saber quantos ataques há). `sampler_zones_controller.dart` (extensão de `DawController`): `zoneAddBlockerOf`, `addZone` (com o teclado todo coberto divide a zona mais larga e, se a `Nota base` dela ficaria acima da faixa que sobrou, traz-a para a ponta e diz no aviso), `splitZoneLayers`, `addZoneFromFile` (checa o bloqueio antes de abrir o seletor), `createSlices`. `sampler_zones_panel.dart`: cartão `ZONAS`, mapa, editor e o `_Stepper` dos campos digitáveis (texto e erro inline, `Esc` cancela). `slice_dialog.dart`: diálogo `Fatiar sample`, aviso `N fatias achadas; só as 96 primeiras viram nota.` com `Menos sensibilidade` (baixa 0,15 e refaz) e os cortes além do 96º apagados em `_SlicePainter`. O cartão `Envelope` e o visor do cartão `Áudio` com zonas ficam em `instrument_panel.dart` (`_samplerSections`, `_sampleDisplay`). Várias destas regras são de `d196fec` |
| `effects_panel.dart`, `fx_editors.dart`, `fx_presets.dart` | rack de efeitos, editores (EQ, dinâmica, genérico) e presets |
| `automation_lane.dart`, `automation_math.dart` | editor de pontos e a conta da curva |
| `automation_record.dart`, `automation_mode.dart` | gravação de automação ao mexer nos controles e os seletores de modo (seção [Gravação de automação](#gravação-de-automação-automation_recorddart-automation_modedart)) |
| `marker.dart`, `structure_menu.dart`, `minimap.dart` | marcadores, menus Seções e Visão, minimapa |
| `export.dart`, `export_options.dart`, `wav.dart` | exportar (janela e opções) e codificação/leitura de WAV |
| `settings_dialog.dart`, `shortcuts_dialog.dart` | configurações de gravação e janela de atalhos (o grupo `Aprender MIDI` e a linha `Shift+K` de `suspendedShortcuts`) |
| `midi_map.dart`, `midi_learn.dart`, `midi_learn_ui.dart` | MIDI learn: modelo e conta (Dart puro), o motor do aprender e do takeover com o padrão para novos projetos, e a tela (contorno, menu, botão, faixa, janela `Mapeamentos MIDI`); ver a seção [MIDI learn](#midi-learn) |
| `warp.dart`, `warp_dialog.dart` | sons derivados do warp e o diálogo |
| `audio_to_midi.dart`, `midi_convert_dialog.dart` | áudio → MIDI pelo servidor (job `audio_to_midi`) e o diálogo; `notesForClip` segue o warp (`AudioClip.tempoFor`), soma a transposição e espelha no reverso |
| `clip_gain_dialog.dart` | diálogo `Ganho do clipe` (item `Ganho do clipe…` do menu do clipe de áudio em `timeline.dart`): slider −40 a +12 dB, `clipGainFromDb`/`clipGainToDb`, `setClipGain` |
| `sync.dart`, `sync_ui.dart` | sincronização (com pull periódico, e pull da abertura, que esperam o transporte parar e o gesto acabar; o envio reenvia os áudios de um `422` e repete o `PUT`, até 3 vezes) e seu indicador (`SyncIndicator`, montado no cabeçalho do projeto por `project_screen.dart`, não na `TransportBar`: na barra ele saía da tela em janelas de 1500 px) |
| `user_presets.dart`, `user_presets_ui.dart` | presets do usuário: modelo, guardado local, arquivo `.jopreset` e a seção `MEUS PRESETS` dos menus (ver [Presets do usuário](#presets-do-usuário-user_presetsdart-user_presets_uidart)) |
| `local_purge.dart` | `purgeLocalProject`: limpeza local de um projeto apagado (confere todos os `doc:*` do guardado, via `LocalStore.keys`, e leva os `warp:<hash>\|…` dos áudios apagados) |
| `templates.dart` | modelos de projeto (`Vazio`, `Batida eletrônica`, `Gravação de banda`) |
| `project_file.dart`, `project_file_ui.dart` | o arquivo `.jopendaw`: montar, ler e validar o zip, refazer ids, importar (lógica pura) e a janela `Exportar projeto` com o seletor de arquivo (seção [Arquivo de projeto `.jopendaw`](#arquivo-de-projeto-jopendaw)) |
| `midi_file.dart`, `midi_file_ui.dart` | o arquivo MIDI padrão `.mid`: leitura (SMF tipo 0, 1 e 2), escrita (tipo 1, 480 PPQ), o `Importar` da barra e a janela `Exportar MIDI (.mid)` (seção [Arquivo MIDI padrão `.mid`](#arquivo-midi-padrão-mid)) |

## Arquivo MIDI padrão (`.mid`)

As notas dos clipes de notas indo e voltando em arquivo MIDI padrão (SMF): importar um `.mid` cria faixas e clipes, exportar escreve o clipe selecionado ou todas as faixas de notas. Vem do commit `945e937`. Só Dart puro (sem motor, sem servidor, sem `package:web`), então roda igual na web, no Android e nos testes. Para quem mexe no app; o uso está em [Áudio e clipes](../manual/03-audio-e-clipes.md#importar-um-arquivo-midi-mid) e [Exportação](../manual/08-exportacao.md#notas-em-midi-mid).

### Peças

| Arquivo | Papel |
|---|---|
| `daw/midi_file.dart` | tudo o que não é tela: `parseMidiFile` (leitura), `buildMidiFile` (escrita), `midiImportTracks` (arquivo lido → faixas e clipes), `midiFileName`, `appBpmFor`, o mapa da bateria GM (`drumPitchForGm`, `gmDrumName`) e as classes `MidiFileData`, `MidiFileTrack`, `MidiTempoPoint`, `MidiExport`, `MidiImportReport`, `MidiFormatException` (a mensagem já vem em português para a tela); desde a fase 11 também o mapa de andamento e de compassos: `simplifyTempo`, `importedTempo`, `importedMeter`, `midiTempoDiffers` (a decisão de perguntar), `importedMeterBeats` e, na escrita, `_tempoMeterEvents` |
| `daw/midi_file_ui.dart` | `importFiles` (o seletor único de áudio e MIDI, ligado ao botão `Importar` e ao `Ctrl+I`), `importMidiFlow`, `askImportKind` (a janela `Importar como`, chaves `midi-import-<kind>` e `midi-import-go`; `midiImportKinds` = sintetizador, FM, wavetable, sampler), `askUseFileTempo` (a pergunta do andamento; `_bpmText` só chama o `formatBpm` de `tempo_format.dart`, e o compasso do projeto sai de `formatDocMeter` mais ` e N mudança(s) de compasso` do `meterMap`, fase 13), `exportSummary` (o texto de "salvo"), a janela de avisos e `ExportMidiDialog` (chaves `midi-export-clip`, `midi-export-all`, `midi-export-go`; `save` devolve `Future<bool?>`: `false` = cancelou) |
| `daw/controller.dart` | `DawController.importMidiBytes` (bloqueia gravando, chama o leitor, se há faixa melódica pergunta o tipo por `chooseKind` (ou usa `kind`, ou `midiImportKind`, a última escolha da sessão; `null` cancela tudo), pergunta se `midiTempoDiffers`, cria as faixas num só `edit` e dá ao clipe o nome da trilha, monta os avisos de andamento) e `applyImportedTempo` (grava o mapa de andamento e o de compassos do arquivo no documento) |
| `daw/export.dart` | `ExportDialog.onMidi` (botão `Notas em MIDI (.mid)…`, chave `export-midi-link`) e `showExportDialog`, que abre `showExportMidiDialog` quando o botão foi tocado |
| `daw/transport_bar.dart`, `screens/project_screen.dart` | o botão `Importar` (tooltip `Importar áudio ou MIDI (Ctrl+I)`) e o `Ctrl+I` chamam `importFiles`; o `Ctrl+I` cai em `importAudio` se o nó de foco não tem contexto |
| `test/midi_file_test.dart` | 650 linhas: leitura à mão, arquivos ruins, ida e volta, desempenho e a importação no controlador |

### Fluxo de dados

```
Importar:  seletor (audioExtensions + mid, midi)
             ├─ áudio  → DawController.importBytes (sha-256, ver acima)
             └─ .mid   → importMidiFlow → importMidiBytes
                          parseMidiFile → MidiFileData (faixas, tempoMap, beatsPerBar, warnings)
                          ├─ falhou → error = 'Não deu para importar <nome>: <mensagem>' (nada muda)
                          ├─ há faixa melódica → chooseKind (askImportKind: 'Importar como'; cancelar = nada muda)
                          ├─ midiTempoDiffers(data, doc) → confirmTempo (askUseFileTempo)
                          └─ edit(): applyImportedTempo (se aceito: bpm + tempoMap + beatsPerBar + meterMap)
                             + DawTrack por faixa + clipe, num checkpoint
                             → _mirrorTempo() (espelho do andamento no servidor) → MidiImportReport
                             → janela de avisos se houve warnings

Exportar:  ExportDialog → 'Notas em MIDI (.mid)…' → ExportMidiDialog
             → buildMidiFile(doc, [only, onlyTrack], title) → MidiExport(bytes, tracks, notes, skipped, skippedControls, silenced)
             → AudioEngine.saveFile(nome, bytes, 'application/octet-stream') → bool (false: cancelou; nada de "salvo")
```

O tipo MIME é `application/octet-stream` de propósito (como no `.jopendaw`): com `audio/midi` alguns seletores do Android acrescentam outra extensão ao nome.

### Contratos

**Batidas ↔ ticks.** O app conta em batidas (semínimas) como `double`. Na escrita, `tick = round((clip.start + offset + nota.start) * 480)`; o fim é `tick + max(1, round(duração * 480))`; o `offset` é `-clip.start` no `Clipe selecionado` (o clipe vai para o instante zero) e 0 em `Todas as faixas de notas`. Na leitura, `batida = tick / ppq` para qualquer PPQ (1 a 32767, testado 1, 96, 960 e 32767), sem arredondar; só a duração zero ganha `midiMinNoteBeats` (1/32), duração de 1 tick continua 1 tick. Velocidade: escreve `round(v * 127)` limitada a 1–127; lê `v / 127`.

**O que a leitura entende** (`parseMidiFile`):

| Evento | Resultado |
|---|---|
| Cabeçalho `MThd` (ou `RIFF`+`RMID`+`data`, pulando 20 bytes) | Formato 0, 1 ou 2; divisão em PPQ. SMPTE (bit 15 ligado), divisão 0, formato > 2, cabeçalho < 6 bytes ou cortado: `MidiFormatException` |
| Bloco que não é `MTrk` | Pulado pelo tamanho |
| Bloco cortado no fim do arquivo | Lê o que dá e acrescenta o aviso `O arquivo está cortado ou tem trechos corrompidos…` |
| `8n`/`9n` (nota) | Nota ligada com velocidade > 0; `9n` com velocidade 0 e `8n` desligam. Fila por (canal, altura): o desligar fecha a nota ligada mais antiga da mesma altura. Nota presa fecha no fim da trilha (contada no aviso) |
| `En` (pitch bend) | Controle `ccBend` (128), `min(1, (lsb + msb*128 - 8192) / 8192)` |
| `Bn` CC 1 | `ccMod`, `valor / 127` |
| `Bn` CC 64 | `ccSustain`, 1.0 se ≥ 64, senão 0.0 |
| `Bn` CC ≥ 120 | Descartado sem contar |
| `Bn` CC 6, 38 e 98 a 101 (RPN/NRPN) | Descartado sem contar: é o alcance do bend que a exportação escreve (`dd4ef07`) |
| `Bn` outros CC | Ignorado e contado (`Ignorei N eventos de controle…`) |
| `Cn` e `Dn` | Ignorados sem aviso (um byte de dados); o `Program Change` do arquivo continua ignorado na importação |
| `FF 51` (tamanho 3) | Ponto do mapa de andamento: batida e `60000000 / µs` BPM |
| `FF 58` (≥ 2 bytes) | Fórmula de compasso: numerador e `dd` (denominador = 2^dd). Vira uma `MeterChange` de `MidiFileData.meterMap` (ver "Andamento e compasso do arquivo"); numerador ≤ 0 é ignorado |
| `FF 03` | Nome da trilha (só o primeiro; UTF-8 tolerante, sem caracteres de controle) |
| `FF 2F` | Fim da trilha |
| `F0`, `F7`, `F1`–`F6`, `F8`–`FE`, outros meta | Pulados. Meta e SysEx cancelam o *running status* |

Running status vale. Dado sem status anterior, byte de dados ≥ 128 onde deveria haver dado, ou VLQ de mais de 4 bytes: a **trilha** para ali (o que veio antes vale) e o arquivo ganha o aviso de corrompido; a leitura nunca lança nada além de `MidiFormatException` (há teste com bytes aleatórios). Uma trilha é dividida por canal em grupos; só grupos com nota viram `MidiFileTrack`. Trilhas com mais de um canal com nota ganham o canal no nome (`Nome (canal N)` ou `Canal N`). Canal 9 (o 10 dos músicos) é `MidiFileTrack.drums`.

**Andamento e compasso do arquivo (leitura).** Desde `020003f` o leitor devolve o mapa inteiro nas duas frentes, e a importação o leva para o documento.

- *Andamento.* `MidiFileData.tempoMap` guarda a lista inteira e ordenada (batida = tick/PPQ, BPM real `60000000 / µs`; dois `FF 51` na mesma batida: o último vale); `firstBpm` é o primeiro ponto; `hasTempoChanges` é verdadeiro se algum BPM difere do primeiro por mais de 0,5 (só serve ao aviso de "mantive o do projeto"). `tempoPoints` (`late final`) é o mapa que entra no projeto: `simplifyTempo` (`midi_file.dart:123`) põe um ponto de 120 BPM na batida 0 se o primeiro `Set Tempo` vem depois, prende cada BPM a 20–999, **funde** o ponto que difere menos de `midiTempoEpsilon = 0.05` BPM do último mantido e, se ainda passa de `midiMaxTempoPoints = 256`, dobra o epsilon até caber (ou até passar de 999). O limite é o de pontos que o motor reserva sem realocar. Todos entram como salto (`ramp: false`).
- *`importedTempo`.* Sem andamento no arquivo: `null` (o do projeto fica). Um ponto só: `bpm` = `appBpmFor(bpm)` (inteiro 20–999, como o app sempre guardou; a pergunta mostra o BPM por `_bpmText` (uma casa; `formatBpm`), então `97,5` aparece na pergunta e entra como 98) e mapa `[]`. Vários: `bpm` = o primeiro ponto **sem arredondar** e o mapa passa por `normalizeTempoPoints` (que limita a 4096).
- *Compasso.* `parseMidiFile` junta os `FF 58` numa lista de `MeterChange` (`MidiFileData.meterMap`, compasso 1 = o primeiro): uma fórmula por tick (a última vale); denominador `2^dd` até 32, e acima disso a mesma duração em fusas (`numerador / 2^(dd−5)`, com aviso); numerador acima de 64 vira 64 (com aviso). Se o primeiro `FF 58` vem depois do tick 0, o compasso `4/4` vale até ele. A batida de cada mudança vira número de compasso contando compassos inteiros desde a mudança anterior (`k = round((batida − início) / barBeats)`); fora de 1e-6 de um compasso inteiro, o `misaligned` levanta o aviso e a mudança vai para o compasso mais próximo; `k < 1` (a mudança cai antes do fim do compasso vigente) troca a fórmula vigente em vez de abrir compasso novo. Fórmula igual à vigente é descartada.
- *`beatsPerBar`.* Sem `meterMap` (arquivo sem `FF 58`) é `null`. Com ele, `importedMeterBeats(primeira)` = `barBeats.round()` limitado a **1–32** (6/8 → 3; 7/8 → 3,5 → 4, **sem** o aviso antigo de aproximação; até a fase 13 o limite era 12, e um primeiro compasso de 13/4 ou 4/1 criava o clipe com 12 tempos: alinhado ao documento em `18c72f4`) e vale para o `length` dos clipes criados. Já `importedMeter` (o que vai para `doc.beatsPerBar`) usa `numerador` quando `den == 4` e `barBeats.round()` senão, limitado a **1–32**, e devolve `changes` por `normalizeMeterChanges` (vazio se só sobra um `n/4`; um `6/8` ou `7/8` único **fica** no mapa). A antiga diferença 12 × 32 entre `importedMeterBeats` e `importedMeter` acabou (ver "Armadilhas do arquivo MIDI").
- *Perguntar.* `midiTempoDiffers(data, doc)` compara `importedTempo`/`importedMeter` com o documento: BPM arredondado, tamanho do mapa e cada `TempoPoint` (igualdade por batida, BPM e rampa); `beatsPerBar`, tamanho e cada `MeterChange`. Diferiu, `askUseFileTempo` abre a pergunta (títulos e texto em [Áudio e clipes](../manual/03-audio-e-clipes.md#importar-um-arquivo-midi-mid)); recusar não muda nada.
- *Avisos de andamento* (em `importMidiBytes`): aceito e `tempoPoints.length < tempoMap.length` → `O arquivo tem N mudanças de andamento; fundi as que diferem menos de 0,05 BPM e M ficaram no mapa (o limite é 256 pontos).` (desde `18c72f4` o `midiTempoEpsilon` sai com vírgula decimal e o texto flexiona: `1 mudança`/`mudanças`, `ficou`/`ficaram`; `N` é `tempoMap.length - 1` e `M` é `tempoPoints.length - 1`); recusado e `hasTempoChanges` → `O arquivo muda de andamento no meio (de X a Y BPM); mantive o do projeto.` Os avisos `o app tem um andamento só…`, `O arquivo muda de compasso no meio…` e `O compasso 7/8 foi aproximado para 4/4…` saíram. Restam os de compasso `Uma fórmula de compasso do arquivo passa dos limites do app (denominador até 32, numerador até 64) e foi aproximada.` e `Uma mudança de compasso caiu no meio de um compasso: alinhei ao compasso mais próximo.`
- `appBpmFor` arredonda o BPM ao inteiro e limita a `minBpmInt`..`maxBpmInt` (20–999, como o servidor e o motor; antes de `dd4ef07` era 20–400).

**Bateria GM.** As notas do canal 10 passam por `drumPitchForGm`: se a altura é de uma das 12 peças de `drumPieces` (36, 37, 38, 39, 41, 42, 45, 46, 48, 49, 51, 56) fica; senão vale a tabela de apelidos (`_gmDrumAlias`: 35→36, 40→38, 43→41, 44→42, 47→45, 50→48, 52→49, 53→51, 55→49, 57→49, 59→51, contada no aviso); qualquer outra altura (54, 58, fora de 35–59) **entra no clipe sem mudar** e vai para o aviso `A bateria do app não tem: …` com o nome GM (`gmDrumName`, ou `nota N`).

**Do arquivo lido ao documento** (`midiImportTracks`): uma `DawTrack` por `MidiFileTrack`, tipo `melodic` (parâmetro, padrão `TrackKind.synth`; `synth`, `fm`, `wavetable` ou `sampler`) ou `drums` no canal 10, clipe `MidiClip` com `start` = cursor encaixado na grade (`snapBeat(beat.value)`), notas e controles exatamente como lidos (batidas contadas do instante zero do arquivo) e `length` fechado no compasso seguinte ao fim das notas **pelo `meter`** que o projeto terá (`lengthFor`: `meter.ceilBarStart(start + fim) - start`, no mínimo `meter.barBeatsAt(start)`; sem mapa, `max(bar, ceil(fim / bar) * bar)` com `bar` = tempos por compasso do projeto ou do arquivo, se aceito). Nome da faixa: o do arquivo, ou `TrackKind.label N` (o primeiro número livre, `_nextTrackName`); o clipe leva o nome da trilha (o da faixa nova se a trilha não tem nome). Nada de `Program Change`: instrumento e parâmetros ficam nos padrões da faixa.

**Escrita** (`buildMidiFile`). Bytes de saída:

| Trecho | Conteúdo |
|---|---|
| `MThd` | tamanho 6, formato **1**, `N+1` trilhas, divisão **480** (`midiExportPpq`) |
| Trilha 0 | `FF 03` com o título (nome do projeto), os eventos de `_tempoMeterEvents(doc, deslocamento)` com delta em VLQ (`FF 51`: µs = `round(60000000 / bpm)`, limitado a 1..16777215, BPM inválido vira 120; `FF 58`: `numerador` (1–255), `log2(denominador)` por `meterDenominators.indexOf`, `24`, `8`), `FF 2F` |
| Trilha `i` | `FF 03` com o nome, os eventos ordenados por (tick, ordem, sequência) com delta em VLQ e o status completo em cada evento (**sem** *running status*), `FF 2F` |
| Ordem no mesmo tick | desligar nota, depois controles, depois ligar nota: uma nota que começa onde outra igual termina não se funde |
| Canais | `Bateria` no 10 (índice 9); as demais, a k-ésima faixa melódica no canal `k % 15`, pulando o 10 (`k % 15 >= 9` ganha +1): 1–9, 11–16 e a 16ª volta ao 1 |
| Faixas | `exportableTracks(doc)`: `kind.isInstrument` e pelo menos um clipe com notas ou controles; em `Todas as faixas` só as de `audibleExportTracks(doc)` (com alguma em solo, só as em solo; senão todas menos as mudas; as fora vão para `MidiExport.silenced` e se não sobra nenhuma: `As faixas com notas estão mudas (ou há outra em solo): tire o mudo, ou exporte só o clipe selecionado.`). O clipe avulso sai mesmo em faixa muda |
| Abertura da trilha | Tick 0, antes de tudo (`order: -1`): `_channelSetup(track, canal)`: RPN 0 com o `Alcance do bend` (`bendRangeOf`, 0–24 st: `CC 101`=0, `CC 100`=0, `CC 6`=semitons, `CC 38`=centésimos, `CC 101`=127, `CC 100`=127) e o `Program Change` de `midiProgramFor` (categoria do preset de fábrica mais parecido, `_nearestPreset`, até `_presetMaxDiff = 6` parâmetros diferentes ignorando o alcance do bend e, no sampler, `Nota base` e `Afinação`; `Baixos` 38, `Leads` 80, `Pads` 89, `Teclas` 4, `Vocais` 54, `Efeitos` 98, `Texturas` 88, `Básico` 80, `Plucks…` 45, sem preset 80 ou 0 no sampler; bateria: programa 0 e sem RPN) |
| Nota | `9n altura vel` / `8n altura 0`. Descartadas (e contadas em `skipped`): altura fora de 0–127, início ou duração não finitos, início < 0 ou ≥ `clip.length` |
| Controles | Bend: `round(v * 8192) + 8192` limitado a 0–16383 em 2 bytes de 7 bits; CC 1: `round(v * 127)`; CC 64: 127 se `v ≥ 0.5`, senão 0. Fora de 0..`clip.length`: descartados e contados em `MidiExport.skippedControls` (`exportSummary` avisa) |
| Sem nada | `MidiFormatException('Não há notas para exportar: desenhe ou grave um clipe de notas primeiro.')` |

Há `Program Change` e `RPN 0` (ver "Abertura da trilha"); não há letras, marcadores nem nome de instrumento.

**Andamento e compasso na escrita** (`_tempoMeterEvents`, `midi_file.dart:722`, desde `020003f`). Lê `doc.tempo` e `doc.meter` (o mapa inteiro; a marca `ramp` decide o degrau):

1. *Andamento.* Cada ponto vira um degrau `(batida, BPM)`. Um ponto com `ramp` cujo BPM difere do do próximo (> 1e-9) vira `n = min(4096, max(1, ceil(len × 16)))` degraus (`_rampStepsPerBeat = 16`), o k-ésimo em `p.beat + k·len/n` com BPM `p.bpm + Δ·k/n` (reta na batida; o último degrau para antes do BPM do ponto seguinte, que entra com o próprio evento). Rampa de mais de 256 batidas fica com degraus mais largos que 1/16.
2. *Deslocamento.* No `Clipe selecionado` o `shift` é `−clip.start`: degraus em batida ≤ começo do clipe viram o valor "em vigor" (`inEffect`; com mapa, `doc.tempo.bpmAt(start)`), gravado no tick 0; só os depois do começo entram, em `tickOf(batida + shift)`. Em `Todas as faixas`, `shift = 0`.
3. *Deduplicação.* Um degrau com o mesmo µs do último não gera evento, exceto se o tick já tem um; dois no mesmo tick ficam com o último (mapa `tick → µs` em ordem de inserção).
4. *Compasso.* O tick 0 leva a fórmula do compasso que contém o começo (`meter.changeAt(barOf(max(0, start)).$1)`); cada `MeterChange` de `doc.meter.changes` cujo começo (`meter.barStart(bar)`) fica depois do começo entra em `tickOf(...)`. O `FF 58` escreve `numerador` (1–255) e `log2(denominador)`.
5. *Ordem.* Ordenação estável por (tick, tipo, ordem de inserção): no mesmo tick o `FF 51` (0x51) vem antes do `FF 58` (0x58).

Sem mapa nenhum sai um `FF 51` e um `FF 58` no tick 0, como antes (mas o `FF 58` agora é a fórmula real do documento, por exemplo `6/8`, e não mais só `beatsPerBar/4`). No clipe avulso que começa no meio de um compasso, as mudanças de compasso seguintes caem nas batidas exatas e podem ficar no meio de um compasso do arquivo (o importador alinha e avisa) `(lido do código; não testado em uso)`.

**Nome do arquivo** (`midiFileName`): substitui `\u0000-\u001f`, `\u007f` e `/ \ : * ? " < > |` por `_`, tira pontos do começo, corta em 80 caracteres (por pontos de código), `notas` se vazio, e põe `.mid`. Em `Todas as faixas de notas` o título é o nome do projeto; em `Clipe selecionado`, o nome do clipe (ou o do projeto se vazio).

### Compatibilidade com outros programas

O que o app escreve é o SMF mais comum: tipo 1, 480 PPQ (dentro do que Ableton Live, FL Studio, MuseScore e afins leem), uma trilha de andamento e compasso à parte, uma trilha por faixa com nome e um canal fixo, bateria no canal 10. O que o app lê cobre tipos 0, 1 e 2, qualquer PPQ, *running status*, SysEx e meta desconhecidos. Nada disso foi conferido abrindo um arquivo do jopendaw nesses programas, nem um arquivo deles no jopendaw `(não confirmado; testado só por testes automáticos)`: os testes fabricam os bytes à mão e fazem a ida e volta com o próprio leitor. Desde `dd4ef07` cada trilha abre com o `Program Change` aproximado e o `RPN 0` do alcance do bend; o que **não** se escreve são os parâmetros do timbre (o programa de destino escolhe o som dele) e programas que ignoram o RPN usam o alcance padrão deles (em geral ±2 semitons).

### Decisões e por quê

- **Só Dart puro e sem inteiros de 32 bits.** O dart2js faz operações de bit em 32 bits (ver [Armadilhas](#armadilhas-conhecidas)): o VLQ, os tempos de 32 bits e a escrita usam multiplicação, `%` e `~/`, nunca `<<` ou `&`.
- **Um leitor tolerante.** Arquivo cortado ou com lixo devolve o que deu para ler, com aviso, em vez de recusar tudo (uma trilha corrompida não derruba as outras). Só o que impede de saber o tempo (SMPTE, PPQ 0, sem `MThd`, sem trilha) ou de ter algo para importar (sem nota) vira erro.
- **O leitor cede o controle.** A cada `yieldEvery` (20 mil) eventos ele faz `await Future.delayed(Duration.zero)`, para a tela não travar num arquivo enorme (teste de 100 mil notas).
- **Uma faixa por (trilha, canal), não só por trilha.** Um arquivo tipo 0 põe tudo numa trilha, e um canal só pode ser bateria ou não; separar por canal mantém a bateria (canal 10) numa faixa `Bateria` e o resto em `Sintetizador`.
- **Batidas como estão.** Importar recusando o andamento do arquivo mantém as batidas: só a velocidade muda (o texto da pergunta diz isso).
- **O mapa do arquivo substitui o do projeto, não se mistura.** A pergunta é tudo ou nada (`Usar o do arquivo` / `Manter o do projeto`), e as notas ficam nas mesmas batidas: o que muda é a velocidade. Misturar pontos de dois mapas não teria significado musical.
- **Simplificar na importação, não no motor.** Um arquivo com rampa gravada em dezenas de milhares de `Set Tempo` estouraria os 256 pontos que o motor reserva sem realocar (e os 4096 do `normalizeTempoPoints`); por isso `simplifyTempo` funde o que difere menos de 0,05 BPM e, se preciso, dobra a tolerância.
- **Rampa vira degraus na escrita e não volta como rampa.** O SMF só tem `Set Tempo` em degraus; a marca `ramp` não sobrevive à ida e volta (a importação entra sempre em salto).

### Como testar

```bash
cd app
flutter test test/midi_file_test.dart
```

Cobertura de `test/midi_file_test.dart`: leitura à mão (tipo 0 com running status e `9n` de velocidade 0, tipo 1 com trilha de andamento, VLQ de 4 bytes, SysEx e mensagens de sistema, bend/modulação/pedal, notas presas, duração zero, bateria GM, vários canais numa trilha, várias mudanças de andamento, 6/8 e 7/8, PPQ 1/96/960/32767); arquivos ruins (vazio, não-MIDI, SMPTE, PPQ 0, tipo desconhecido, cabeçalho cortado, sem faixa, sem nota, truncado, lixo na trilha, 300 arquivos de bytes aleatórios que só podem lançar `MidiFormatException`, RMID); escrita e ida e volta (notas, velocidades, controles, andamento 97, compasso 3, nomes, posição absoluta da bateria; clipe selecionado sai do começo; 15 faixas melódicas pulam o canal 10 e a 16ª volta ao 1; notas fora de 0–127 ou do clipe; notas emendadas; nome do arquivo); desempenho (100 mil notas escritas e lidas em menos de 20 s, com a leitura cedendo o controle); e a importação no controlador com o motor de mentira (faixa de sintetizador e de bateria, andamento aceito e desfeito com `undo`, andamento recusado, pergunta só quando difere, aviso de mudança de andamento, arquivo ruim vira `error` sem mexer no documento). O grupo `mapa de andamento e de compassos` (fase 11) cobre: salto, rampa e compassos que voltam iguais na ida e volta (a rampa de 8 batidas vira mais de 128 degraus e o `secondsAt` do mapa lido bate com o original em até 15 ms); um andamento e um compasso só sem mapa (um evento de cada, como antes); o clipe avulso levando o andamento e o compasso que valiam no começo dele; ausência de deslocamento de bits (dart2js); um `.mid` com mudança de andamento no meio virando o mapa do projeto sem o aviso antigo; recusar avisando `mantive o do projeto`; arquivo com dezenas de milhares de eventos de andamento simplificado para caber; fusão só do que difere menos de 0,05 BPM; compassos `6/8` no compasso 3 e `7/8` depois entrando no mapa; e mudança de compasso no meio de um compasso alinhando e avisando. `6/8` lê `beatsPerBar` 3 e `7/8` lê 4 com `meterMap` exato e sem aviso. Em `test/piano_roll_tools_test.dart`: `dropSnapCollisions` e `keyboardTooltip`. Os testes rodam na VM do Dart, não no dart2js: o cuidado com inteiros de 32 bits vem da leitura do código, não de teste na web `(não confirmado no navegador)`. `app/test/fase12c_test.dart` (fase 12, `dd4ef07`, 511 linhas) cobre: `Tempos por compasso` trocando um `6/8` inicial, BPM decimal no documento e no motor, os limites 4096/1024 com aviso, a janela 20–999, compasso pelo mapa (clipe novo, `fitRange`, encaixe, duração), a seta `↘` e o diálogo de andamento (widget), `Program Change` e RPN 0 na exportação, faixa muda e solo, pontos de controle fora do clipe, o `Salvar como` cancelado (widget), `Importar como` (FM, wavetable, sampler; o seletor só abre com faixa melódica, lembra a escolha e cancelar não importa), o nome do clipe, e na expressão a faixa antiga voltando ao repouso, parar zerando pedal, bend e roda, a bateria sem pontos, `cutControls` e o aparo da borda esquerda. Sem teste de widget para `importFiles` nem `askUseFileTempo` `(não confirmado em uso)`; nada disto foi visto no navegador nem no Android `(testado só por testes automáticos)`.

### Armadilhas do arquivo MIDI

- **Rampa não faz a viagem de volta.** A exportação a escreve em degraus de 1/16 de batida (máximo de 4096 por rampa) e a importação a lê como saltos, fundindo o que difere menos de 0,05 BPM e limitando a 256 pontos; o mapa de ida e volta soa igual (tolerância de 15 ms no teste), mas o desenho da faixa `Andamento` fica cheio de pontos em vez de uma rampa.
- **O texto do projeto na pergunta ignorava o mapa de compassos do projeto: resolvido em `18c72f4` (com `1180152`, o formatador).** `askUseFileTempo` escrevia `o projeto está em Y BPM[ e N mudanças de andamento], Z/4` com `doc.beatsPerBar`, então um projeto em `6/8` aparecia como `3/4`. Agora usa `formatDocMeter(c.doc)` e acrescenta ` e N mudança(s) de compasso` quando `meterMap.length > 1`. Teste: `fase13c_test.dart` (`a pergunta dos andamentos mostra o compasso real do projeto (6/8 não vira 3/4)`). `(testado só por testes automáticos)`.
- **`importedMeter` limitava `beatsPerBar` a 1–32 e `importedMeterBeats` a 1–12: resolvido.** Em `dd4ef07` a lista `Tempos por compasso` da `_TempoDialog` passou a ir até `max(12, beatsPerBar)` (e a mostrar `n/d (atual)` como item `0` quando o compasso inicial não é `n/4`). Em `18c72f4` (fase 13) os limites se alinharam: `importedMeterBeats` (usado como `bar` de `midiImportTracks` quando o mapa é de um compasso só) vai a 32, e a lista `Tempos por compasso` vai sempre de `1/4` a `32/4` (`math.max(32, _custom ? 0 : beatsPerBar)`). Teste: `fase13c_test.dart` (`a lista de tempos por compasso vai a 32/4 e mostra o valor atual`). `(testado só por testes automáticos)`.
- **Mudança de compasso mais próxima, não a exata.** Uma mudança que cai no meio de um compasso é alinhada ao compasso inteiro mais próximo; as notas ficam onde estavam, então o compasso do projeto pode não coincidir com o que o programa de origem mostrava.
- **O clipe criado segue o mapa de compassos** (resolvido em `dd4ef07`): `midiImportTracks` recebe o `MeterMap` que o projeto terá e fecha o `length` pelos compassos dele; só sem mapa (ou com um compasso só) vale o `bar` fixo.
- **Resolvido em `dd4ef07` (antes eram limites listados aqui).** A escrita ganhou `Program Change` e `RPN 0`; mudo e solo valem na exportação de todas as faixas; o tipo da faixa criada na importação vem de `Importar como` (`Sintetizador`, `FM`, `Wavetable` ou `Sampler`; o canal 10 é sempre `Bateria`); `saveFile` devolve `bool` (`false` = cancelou, e `ExportMidiDialog` não escreve `salvo`; a web devolve sempre `true`); a janela de atalhos diz `Importar áudio ou MIDI`; pontos de controle descartados entram em `skippedControls`. `(testado só por testes automáticos; o cancelar do Android não foi visto no aparelho)`
- **A leitura descarta o alcance do bend do arquivo.** `RPN 0` (CC 6/38/98–101) é ignorado sem aviso e vale o `Alcance do bend` do instrumento da faixa nova; um arquivo com bend de ±12 st toca com o alcance padrão (2 st) até você ajustar o knob.
- **O `Program Change` do arquivo é ignorado na importação**, e `Importar como` vale para todas as faixas melódicas do arquivo de uma vez (não dá para misturar tipos por trilha).
- **A ordem de dois pontos de andamento na mesma batida** vem de `List.sort` (não garantida como estável) e o último da batida vence. Caso raro `(lido do código; não testado)`.

## Arquivo de projeto (`.jopendaw`)

O projeto inteiro (documento e áudios) num zip: backup, transporte entre aparelhos e contas, envio a terceiros. Vem do commit `7af1f19`. Só o app conhece o formato; o servidor não o vê (o que ele recebe, depois da importação, é o fluxo normal de sincronização).

### Peças

| Arquivo | Símbolos | Papel |
|---|---|---|
| `app/lib/daw/project_file.dart` | `projectFileFormat`, `ProjectFileLimits`, `ProjectFileException`, `ProjectBundle`, `projectHashes`, `projectFileName`, `buildProjectFile`, `parseProjectFile`, `remapDocIds`, `importedProjectName`, `importProjectBundle` | Lógica pura, sem tela: monta e lê o zip, valida, refaz ids e cria o projeto pelos callbacks que recebe |
| `app/lib/daw/project_file_ui.dart` | `showExportProjectDialog`, `loadSampleLocalOrServer`, `loadDocLocalOrServer`, `ExportProjectDialog`, `pickProjectFile`, `ProjectImporter` | A janela `Exportar projeto` (progresso e erro dentro dela), de onde vêm o documento e os áudios, o seletor de arquivo e o orquestrador da importação (`ProjectImporter.import`) |
| `app/lib/daw/export.dart` | `showExportDialog`, `ExportDialog.onWholeProject` | Botão `Projeto inteiro (.jopendaw)…` (ícone `inventory_2_outlined`) no rodapé da janela `Exportar áudio` do projeto aberto. Ao tocar, `showExportDialog` fecha a janela de opções e chama `showExportProjectDialog(context, name: c.project.name, loadDoc: () async => c.doc, loadSample: loadSampleLocalOrServer)`: usa `c.doc` (a memória). Antes do commit `677f064` era um botão só na barra (`transport_bar.dart`), tirado dali porque a barra estourava; a barra não importa mais `project_file_ui.dart` |
| `app/lib/screens/projects_screen.dart` | `_importFile`, `_export`, item `Exportar projeto…` do menu `Mais` | Botão `Importar projeto`, importação e exportação a partir do cartão (`loadDocLocalOrServer`) |
| `app/test/project_file_test.dart` | 737 linhas | Ida e volta, arquivos inválidos, ids, nomes, importação com falha, janela de exportar |

Dependências novas: `archive: ^4.3.0` (zip) e, já presentes, `crypto` (sha-256), `file_picker` (abrir e salvar) e `share_plus` (folha de compartilhar do Android).

### O formato, campo a campo (versão 1)

O arquivo é um zip comum (qualquer descompactador abre), com três tipos de entrada:

```
Minha música.jopendaw
├── samples/<sha-256 em 64 hexa minúsculos>.<ext>   (um por áudio distinto; ordem por hash)
├── project.json
└── manifest.json
```

**`project.json`** (objeto JSON UTF-8, até 64 MiB na leitura):

| Campo | Tipo | Conteúdo | Na leitura |
|---|---|---|---|
| `format` | int | Versão do formato do arquivo (`projectFileFormat`, hoje `1`) | Obrigatório, inteiro ≥ 1; maior que o que o app lê é recusado |
| `name` | string | Nome do projeto na hora da exportação | Opcional; `trim()`; vazio vira `Projeto importado` |
| `app_version` | string | `projectFileAppVersion`, constante `'0.1.0'` | Informativo; guardado em `ProjectBundle.appVersion` |
| `exported_at` | string | Data e hora UTC em ISO 8601 | Informativo; `DateTime.tryParse`, valor ruim vira nulo |
| `doc` | objeto | `DawDoc.toJson()`, o mesmo JSON de [Esquema JSON completo](#esquema-json-completo-versão-1), inclusive `version` | Obrigatório; `doc.version` maior que `DawDoc.version` é recusado; `DawDoc.fromJson` que lança vira `O arquivo está corrompido: o documento do projeto não pôde ser lido.` |

**`manifest.json`** (objeto JSON UTF-8, até 64 MiB):

| Campo | Tipo | Conteúdo | Na leitura |
|---|---|---|---|
| `format` | int | Igual ao de `project.json` | Não é lido |
| `samples` | lista | Um item por áudio que entrou no zip | Obrigatória |
| `samples[].hash` | string | sha-256 do arquivo original, 64 hexa minúsculos | Precisa casar `^[0-9a-f]{64}$` |
| `samples[].size` | int | Tamanho em bytes | Confere com o tamanho descomprimido |
| `samples[].name` | string | Nome original do áudio (`doc.samples[hash].name`), `''` se não há | Não é lido (informativo) |
| `samples[].file` | string | Caminho da entrada no zip | Precisa casar `^samples/<hash>\.([a-z0-9]{1,8})$` com o mesmo hash |
| `missing` | lista de hash | Áudios que o documento cita e o exportador não tinha | Não é lido: o importador recalcula o conjunto a partir do documento e do que veio |

**`samples/<hash>.<ext>`:** os bytes do arquivo como foram importados ou gravados. A extensão vem da extensão do nome original se estiver em `wav mp3 ogg oga flac m4a aac opus webm aif aiff`; senão `bin`. Os formatos já comprimidos (`mp3 ogg oga flac m4a aac opus webm`) entram **sem compressão** no zip (`ArchiveFile.noCompress`); o resto (WAV, AIFF, `.bin` e os dois JSON) usa a compressão padrão do `archive` (deflate no zip). O conjunto de áudios é `projectHashes(doc)`: `doc.samples`, o `sample` de cada faixa (sampler) e o `sample` e as `takes` de cada clipe. Um hash que não é sha-256 no documento não vira arquivo: entra em `missing`. Os sons derivados do warp (`warp:<chave>`) **não** entram.

### Exportar

1. `showExportProjectDialog` abre `ExportProjectDialog` (não dispensável clicando fora), que chama `loadDoc()` e `buildProjectFile`.
2. **De onde vem o documento:** projeto aberto, `c.doc` (o que está na memória, mesmo sem ter sido salvo). Cartão da lista, `loadDocLocalOrServer`: `doc:<id>` do `LocalStore` e, se o aparelho nunca abriu o projeto, o do servidor (`ApiClient.projectDoc`); sem nenhum, `StateError('Este projeto ainda não tem nada para exportar: ...')`.
3. **De onde vêm os áudios:** `loadSampleLocalOrServer`: `sample:<hash>` do `LocalStore`, senão `ApiClient.getSample`; falha de rede vira "ausente".
4. `buildProjectFile` percorre os hashes em ordem, cede o laço a cada áudio (`Future.delayed(Duration.zero)`) e reporta `onProgress(done, total)`. Ele **copia o documento no começo** (`doc.toJson()`), então editar durante a montagem não muda o arquivo. Devolve `BuiltProjectFile(bytes, missing, sampleCount)`.
5. O arquivo vai para `AudioEngine.instance.saveFile(projectFileName(name), bytes, 'application/octet-stream')`, o mesmo caminho do WAV: na web `saveFile` do `host.js` (Blob + `<a download>`, `URL.revokeObjectURL` depois de 60 s); no Android `saveFile` de `engine_ffi.dart` (`FilePicker.saveFile`, com a folha do `share_plus` de reserva se o seletor não existe). Fora da web e do Android, `UnsupportedError('Salvar arquivos não funciona neste sistema...')`. O MIME é `octet-stream` de propósito: com `application/zip` o seletor do Android poderia acrescentar `.zip` ao nome.
6. `projectFileName`: troca `\u0000-\u001f`, `\u007f` e `/ \ : * ? " < > |` por `_`, tira pontos do começo, corta em 80 caracteres, vazio vira `projeto`, acrescenta `.jopendaw`.

### Importar

Cadeia: `projects_screen._importFile` → `pickProjectFile` → `ProjectImporter.import` → `parseProjectFile` → `importProjectBundle`.

- `pickProjectFile`: `FilePicker.pickFiles(dialogTitle: 'Importar projeto', type: FileType.custom, allowedExtensions: ['jopendaw', 'zip'])`; devolve `(nome, bytes)` ou nulo se cancelou.
- `ProjectImporter.import`: espera 20 ms para a tela pintar `Conferindo o arquivo…` (a leitura é síncrona e pesada), chama `parseProjectFile` e passa ao `importProjectBundle` com `onProgress` virando `Guardando os áudios: d de t`. Existe como classe para os testes trocarem API e guardado.
- `parseProjectFile(bytes, {limits})` valida nesta ordem, lançando `ProjectFileException` com a mensagem pronta para a tela: arquivo vazio; tamanho ≤ `maxFileBytes`; zip decodificável; número de entradas ≤ `maxEntries`; **para cada entrada** nome hostil (`_hostileName`: vazio, começa com `/`, contém `\` ou NUL, prefixo de unidade `C:`, segmento `..`), link simbólico, nome repetido e soma dos tamanhos **declarados** ≤ `maxTotalBytes`; `project.json` presente e ≤ `maxJsonBytes`; `format`; `doc` e `doc.version`; `DawDoc.fromJson`; `manifest.json`; para cada áudio do manifesto, formato do hash e do caminho, presença da entrada, `size` ≤ `maxSampleBytes`, **descompressão com teto** (`_inflate`/`_BoundedOutput` para no instante em que passa do limite, mesmo que o cabeçalho do zip minta o tamanho), soma real ≤ `maxTotalBytes`, tamanho igual ao declarado e sha-256 igual ao hash. Tudo o que o zip traz além disso é ignorado. Nada é gravado em disco a partir de um nome de dentro do zip: os áudios são procurados pelo nome exato que o manifesto declara.
- `ProjectFileLimits` (padrões): arquivo 1 GiB (`1024 * 1024 * 1024`, não `1 << 30`: ver a armadilha dos operadores de bit em 32 bits), soma descomprimida 2 GiB (`2 * 1024 * 1024 * 1024`), um áudio 512 MiB, cada JSON 64 MiB, 20 000 entradas.
- `importProjectBundle(bundle, ...)`, na ordem que deixa o pior caso inofensivo: `remapDocIds(doc)`; `createProject(importedProjectName(...))` (POST `/api/projects`); se o andamento (`doc.bpm` arredondado e limitado a 20–999, `minBpmInt`..`maxBpmInt`; o andamento com decimais fica no documento, só o espelho do servidor é inteiro) ou o compasso (`beatsPerBar` limitado a 1–32) diferem dos padrões do projeto novo, `patchProject`; copia o andamento e o compasso do projeto para o documento; grava cada `sample:<hash>` **se a chave ainda não existe**; grava `doc:<id>` por último (é o que faz o projeto "existir" para o editor). Qualquer falha depois de criado o projeto chama `deleteProject` (melhor esforço) e relança.
- `remapDocIds`: id de faixa, clipe de áudio, clipe MIDI, efeito (faixas e master), marcador e raia de automação fica igual se casa `^[A-Za-z0-9_-]{1,64}$` e ainda não foi usado; senão recebe `newId()`. Depois reaponta: envio para faixa que sumiu é descartado, `output` inexistente vira `null` (master), raia de efeito ou de envio cujo alvo não existe é descartada. Faixas com id repetido: as referências vão para a primeira. Sidechain não precisa de tratamento, é índice de faixa (ver [Duas armadilhas de compatibilidade](#duas-armadilhas-de-compatibilidade-do-esquema)).
- `importedProjectName(nome, existentes)`: compara sem maiúsculas e sem espaços nas pontas; acrescenta ` (importado)`, ` (importado 2)`...; corta em 120 caracteres.

**Depois da importação não há chamada de sincronização própria.** A tela navega para `/projetos/<id>`; o `DawController.open` encontra `doc:<id>` (então `saved is String`, `localExisted = true`), não encontra `sync:<id>`, e o `SyncService._start` marca o documento como pendente (`_dirty = localExisted`, versão 0). Como o projeto novo não tem documento no servidor (`version: 0, doc: null`), não há conflito: `_push` envia os áudios que faltam (`uploadSamples`) e faz `PUT` com `base_version: 0`. Ver [12 Sincronização](12-sincronizacao.md).

### Como evoluir o formato sem quebrar arquivos antigos

Existem duas versões independentes: `format` (a moldura do zip: nomes, manifesto, o que é cada entrada) e `doc.version` (o esquema do documento, `DawDoc.version`, hoje 1). Um leitor **recusa** o que é mais novo que ele (mensagem `Atualize o app`) e **lê** o que é mais antigo.

1. **Mudança aditiva** (campo opcional novo em `project.json` ou no `manifest.json`, entrada nova que o leitor pode ignorar): não muda `format`. O leitor só olha as chaves que conhece e ignora entradas extras do zip, então apps velhos continuam abrindo. Se o campo tem efeito, um app velho o perde ao regravar (ver Armadilhas).
2. **Campo novo no documento:** siga [Um campo novo no documento](#um-campo-novo-no-documento) (`fromJson` com padrão, `toJson`). O `.jopendaw` o carrega sozinho, porque `doc` é o `toJson()`. Não muda `format`, nem precisa mudar `DawDoc.version` enquanto o app antigo lê o documento sem quebrar.
3. **Mudança incompatível na moldura** (renomear `project.json`, outra estrutura de `samples/`, mudar o significado de um campo, exigir uma entrada nova): suba `projectFileFormat` para `2` **e** mantenha a leitura do `1`. Hoje `parseProjectFile` só compara `format` com o máximo; o caminho é uma ramificação por versão logo depois de ler `format` que normaliza o arquivo antigo para o `ProjectBundle` atual, sem reescrever o arquivo. Um app na versão 1 recusa o arquivo `2` com a mensagem certa (foi para isso que a checagem existe). Nenhuma migração existe ainda, porque só há a versão 1.
4. **Mudança incompatível no documento:** suba `DawDoc.version` e escreva a migração em `DawDoc.fromJson` (hoje ele ignora `version`). O `parseProjectFile` já recusa `doc.version` maior que o do app e aceita a ausência do campo.
5. **Regras que não se quebram:** o nome de entrada de áudio segue a expressão regular `samples/<hash>.<ext>` e o hash confere com o conteúdo (nenhum nome vindo do zip vira caminho de disco); os limites de leitura continuam valendo para entradas novas; `project.json` e `manifest.json` mantêm os nomes; não leia o que o arquivo diz como se fosse confiável.
6. **Teste de compatibilidade:** os testes atuais constroem o arquivo com `buildProjectFile` na hora, então não pegam uma regressão da leitura de arquivos antigos. Ao subir o formato, guarde um `.jopendaw` da versão 1 em `app/test/` como fixture e leia com o código novo (recomendação; não existe hoje).

### Decisões e por quê

- **Zip com JSON e áudios avulsos**, não um JSON com base64: abre em qualquer descompactador, os áudios não incham 33% e dá para inspecionar ou consertar à mão.
- **Áudio endereçado por sha-256**, como no guardado local e no servidor: deduplica, e a conferência na leitura pega arquivo truncado ou adulterado.
- **Importar sempre cria projeto novo:** evita decidir conflito com um projeto existente; o custo é não haver "restaurar por cima".
- **Documento por último, projeto apagado na falha:** o editor só enxerga o projeto quando `doc:<id>` existe.
- **Sincronizar pelo caminho normal** (documento local sem `sync:<id>` conta como pendente) em vez de enviar tudo dentro da importação: não duplica a lógica de cota, nomes e conflito.
- **Limites e nomes recusados na leitura:** o arquivo pode vir de qualquer pessoa. O teto de 2 GiB é aplicado duas vezes (declarado e real) por causa de zip bomb.

### Como testar

```bash
cd app
flutter test test/project_file_test.dart
```

Cobre: ida e volta exata do documento e dos áudios, dedupe e extensões, projeto sem áudio e com muitos, áudio ausente (`missing`), arquivos inválidos (vazio, lixo, truncado, sem `project.json`/`manifest.json`, formato e documento novos demais, nomes hostis, caminho fora do padrão, sha-256 e tamanho errados, zip bomb honesta e com cabeçalho mentindo), ids (seguros preservados, repetidos refeitos, referências acompanhando), nomes, criação do projeto com andamento e compasso, falha no meio (projeto apagado), importar duas vezes e a janela de exportar. Uso real (arquivo grande, `saveFile` no Android): `(não confirmado)`; o Android usa o seletor do sistema e a web o download do navegador.

### Armadilhas do arquivo de projeto

- **`app_version` é uma constante** (`'0.1.0'`), não lida do `pubspec.yaml`: não serve para diagnosticar qual build exportou.
- **Versão do documento e mensagem de erro:** a checagem de `doc.version` só atua se `version` é inteiro; um documento sem `version` passa. Um campo novo lido por `DawDoc.fromJson` sem padrão (ou `AutoKind.byName`, que lança) faz o documento cair em `O arquivo está corrompido: o documento do projeto não pôde ser lido.`, mensagem enganosa para um arquivo que só é de um app mais novo.
- **Andamento inteiro:** o projeto no servidor guarda `bpm` inteiro; o importador arredonda `doc.bpm` e o limita a 20–999 (a mesma janela do servidor e do motor, desde `dd4ef07`). Um andamento fracionado é arredondado no espelho do servidor, mas o documento importado guarda o valor com decimais.
- **Preferências e armar/monitorar viajam junto** porque estão no `toJson`; o projeto importado abre com o metrônomo, a contagem, a latência e as faixas armadas do original (e o `open` tenta reabrir a entrada de áudio se há faixa de áudio armada).
- **Leitura inteira na memória:** `pickProjectFile` faz `readAsBytes` e `parseProjectFile` roda síncrona na thread da interface; um arquivo perto de 1 GiB é pesado para um celular. `(não medido)`
- **`saveFile` cancelado no Android** volta sem erro; a janela `Exportar projeto` então mostra `Pronto: ...`. `FilePicker.saveFile` devolve nulo ao cancelar; desde `dd4ef07` o `saveFile` do motor devolve `false` nesse caso, mas só a janela `Exportar MIDI (.mid)` o consulta: a do `.jopendaw` continua descartando o resultado.
- **O cabeçalho do código** de `project_file.dart` diz "para abrir sem servidor", mas a importação cadastra o projeto pela API (`createProject`), então exige sessão e rede.

## Presets do usuário (`user_presets.dart`, `user_presets_ui.dart`)

> Os presets do usuário (commit `b39d3d4`): o timbre de um instrumento ou de um efeito guardado com nome no aparelho, e o arquivo `.jopreset` para levá-lo a outro. Para quem mexe no app; o uso está em [manual 04, Meus presets](../manual/04-painel-de-instrumento.md#meus-presets) e [manual 06c](../manual/06c-painel-de-efeitos.md#presets-do-usuário).

### Peças

| Arquivo | Símbolos | Papel |
|---|---|---|
| `app/lib/daw/user_presets.dart` (522 linhas) | `PresetFamily`, `userPresetFormatVersion` (1), `userPresetExtension` (`jopreset`), `maxUserPresetName` (60), `maxUserPresetsPerKind` (300), `maxUserPresetFileBytes` (256 KB), `presetSpecs`, `presetSkipIds`, `cleanPresetName`, `presetFileName`, `UserPreset`, `PresetFormatException`, `PresetImport`, `UserPresetStorage` (`LocalUserPresetStorage`, `MemoryUserPresetStorage`), `UserPresets` | O modelo, a lógica pura (sem `dart:io`, roda igual no dart2js), o guardado e a validação do arquivo |
| `app/lib/daw/user_presets_ui.dart` (319 linhas) | `userPresetEntries`, `handleUserPresetChoice`, `askPresetName`, `confirmPresetDialog`, `showPresetMessage`, `pickUserPresetFile`, `UserPresetChoice` (`ApplyUserPreset`, `UserPresetMore`, `SaveUserPreset`, `ImportUserPreset`), `SavePresetFile`, `PickPresetFile` | A seção `MEUS PRESETS` dos menus e as janelas |
| `app/lib/daw/instrument_panel.dart` | `_presetControls` (o rótulo, as setas `step`, o menu) | Menu do instrumento: `PopupMenuButton<Object>`, `maxHeight` 460; `MEUS PRESETS` no topo (fase 13) |
| `app/lib/daw/effects_panel.dart` | `_cardMenu` (`maxHeight` 680), `_cardHeader` (subtítulo), `_applyUserPreset` | Menu do cartão de efeito; `MEUS PRESETS` no topo (fase 13) |
| `app/lib/daw/presets.dart`, `fx_presets.dart` | `presetParams`, `matchingPreset`, `matchingEffectPreset` | Os de fábrica, dos quais os do usuário copiam a regra de aplicar e de casar |
| `app/test/user_presets_test.dart` (600 linhas) | 4 grupos | Ver [Como testar](#como-testar-os-presets-do-usuário) |

### Modelo e armazenamento

`UserPreset {id, family, kind, name, values, created, version}`: `family` é `instrument` ou `effect` (o nome do tipo sozinho seria ambíguo no futuro), `kind` é `TrackKind.name` (`synth`, `drums`, `sampler`, `fm`, `wavetable`) ou `EffectKind.name` (`eq`, `compressor`, `gate`, `limiter`, `utility`, `reverb`, `delay`, `chorus`, `phaser`, `tremolo`, `distortion`, `filter`), `values` é `id do ParamSpec → valor` na unidade da tabela. `presetSpecs(family, kind)` devolve a tabela do tipo ou `null` (áudio, barramento e nome desconhecido não têm presets). O id é `u<microssegundos em base 36><sequência em base 36>`.

`UserPresets` (`ChangeNotifier`; singleton `UserPresets.instance`, criado com `LocalUserPresetStorage()`) mantém a lista na memória e grava **tudo num único valor de texto** na chave `userpresets` do `LocalStore`:

```json
{ "format": "jopendaw-user-presets", "version": 1,
  "presets": [ { "id": "u...", "family": "instrument", "kind": "synth", "name": "Meu baixo grave",
                 "version": 1, "created": "2026-09-30T13:04:15.000Z", "params": { "13": 500.0 } } ] }
```

| Onde | O que é a chave `userpresets` |
|---|---|
| Web | Chave `userpresets` do object store `kv` do IndexedDB `jopendaw` (`host.js`), valor texto; por origem do site |
| Android | `FileStore` em `<documentos do app>/jopendaw/userpresets.txt` (grava em arquivo temporário e troca o nome no fim, então um app morto no meio deixa o valor anterior inteiro) |
| Outros sistemas | O `LocalStore` de `engine_io.dart` só guarda no Android: `get` devolve `null` e `put` não faz nada; os presets valem só até fechar o app |

Ciclo de vida: cada painel (`InstrumentPanel`, `EffectsPanel`) assina o notificador e chama `load()` no `initState`; `load()` roda uma vez (`_loading ??= _load()`), lê e junta ao que já foi salvo na sessão (`insertAll(0, …)`, sem duplicar por id nem por nome). Cada `save`, `rename`, `delete` e `importBytes` chama `_changed()`: notifica e enfileira a gravação do JSON inteiro (`_writes`, uma por vez, a última vence; `flush()` espera as pendentes, para os testes). Se a gravação falha, `saveError` recebe `Não deu para guardar os presets neste aparelho.` e os presets seguem na memória. Não há servidor: **não sincroniza com a conta** (ideia futura: uma tabela `user_presets` ou uma chave por conta).

### O que entra e o que fica de fora

`UserPresets.capture(family, kind, current)` percorre a tabela do tipo e guarda **todo id**, limitado à faixa do `ParamSpec` (`_fit`: fora da faixa vira o limite; não finito vira o padrão; opção de lista é arredondada), menos os ids de `presetSkipIds`:

| Tipo | Fora do preset | Por quê |
|---|---|---|
| `sampler` | `SamplerId.root` (`Nota base`) e `SamplerId.tune` (`Afinação`) | Pertencem ao áudio escolhido (a mesma exceção de `presets.dart`, `_samplerKeeps`) |
| `compressor` | id 10 (`Sidechain`) | Roteamento do projeto |
| `gate` | id 6 (`Sidechain`) | Idem |
| todos | Áudio e zonas do sampler, bypass e posição do efeito, automação | Não são parâmetros da tabela |

Sobram: instrumentos com todos os seus ids (a bateria, 49); o sampler com 9 (`Modo`, `Ataque`, `Decaimento`, `Sustentação`, `Soltura`, `Sens. vel.`, `Volume`, `Alcance do bend`, `Vibrato da roda`); efeitos: EQ 49, compressor 10, gate 6, limitador 5, utilitário 8, reverb 10, delay 12, chorus 7, phaser 7, tremolo 6, distorção 9, filtro 11 (contagens lidas das tabelas de `effects.dart`).

### Aplicar e casar (o rótulo)

`UserPresets.paramsFor(preset, track)` monta o mapa completo `defaultParams(kind)` + valores do preset, mantendo `Nota base` e `Afinação` da faixa no sampler; `paramsForEffect(preset, slot)` monta um mapa com todos os ids do efeito, o `Sidechain` sendo o do slot e o resto `values[id] ?? padrão`. O painel entrega o mapa a `DawController.applyPreset` (instrumento) ou `applyEffectPreset` (efeito): os dois são um passo de `edit()`, então entram no desfazer. Salvar, renomear, apagar e importar **não** passam pelo `DawController`: não entram no desfazer do projeto.

`matchingTrack(track)` e `matchingEffect(slot)` devolvem o primeiro preset do tipo (ordem de criação) cujos valores batem com os da faixa (`|atual − esperado| ≤ 1e-6 · max(1, |esperado|)`, ignorando os ids de fora; o que o preset não cita vale o padrão). Nos painéis, o preset do usuário tem prioridade sobre o de fábrica quando os dois batem (`current = userCurrent == null ? matchingPreset(t) : null`), e só o do usuário leva o visto na linha dele. O rótulo do instrumento é `current?.name ?? userCurrent?.name ?? (last != null ? '$last (editado)' : (pristine ? 'Inicial' : 'Personalizado'))`; o do efeito não tem `Inicial` nem `Personalizado`. `_lastPreset` (nome do último preset aplicado, por id de faixa ou de slot) vive no `State` do painel e não é salvo. As setas do instrumento (`step`) andam por `[...fábrica, ...usuário]` com módulo.

### Formato do arquivo `.jopreset`

JSON UTF-8 com recuo de 2 espaços (`exportBytes`), tipo de mídia `application/octet-stream` (`userPresetMime`, de propósito, como o `.jopendaw`: com um tipo específico o seletor do Android pode acrescentar uma extensão). O nome do arquivo é `presetFileName(nome)`: nome limpo, `\ / : * ? " < > |` viram `_`, pontos do começo saem, vazio vira `preset`, mais `.jopreset`.

| Campo | Tipo | Regra na importação |
|---|---|---|
| `format` | texto | Tem de ser `jopendaw-preset`; senão `O arquivo não é um preset do jopendaw.` |
| `version` | inteiro | `>= 1` e `<= userPresetFormatVersion` (1). Menor que 1 ou não inteiro: `O arquivo tem uma versão de formato inválida.`; maior: `O preset é de uma versão mais nova do jopendaw. Atualize o app para importá-lo.` |
| `family` | texto | `instrument` ou `effect`; outro valor é tipo desconhecido |
| `kind` | texto | `TrackKind.name` de instrumento com presets ou `EffectKind.name`; senão `Tipo de preset desconhecido ("família/tipo"). Ele pode ser de uma versão mais nova do jopendaw.` |
| `name` | texto | Passa por `cleanPresetName` (controle e marcas invisíveis viram espaço, espaços colapsados, sem pontas, no máximo 60 caracteres sem partir par substituto). Vazio ou ausente: `Preset importado` (com aviso). Nome em uso no tipo (sem diferenciar maiúsculas): `Nome (2)`, `(3)`…, cortando o nome para caber em 60 |
| `created` | texto ISO 8601 | `DateTime.tryParse`; inválido vira agora |
| `params` | objeto `{"<id>": número}` | Tem de ser objeto (senão `O preset não traz parâmetros.`). Chave que não é inteiro ou id que a tabela do tipo não tem: contada como desconhecida e ignorada. Id de `presetSkipIds`: ignorado sem aviso. Valor que não é número ou não é finito: contado como inválido e ignorado. Valor fora da faixa: limitado (`_fit`), contado. Sem nenhum valor aproveitável: `O preset não tem nenhum valor utilizável para este tipo.` Ids que o arquivo não cita voltam ao padrão |

O arquivo **não leva `id`** (o exportado não o escreve; o importado ganha id novo). Exemplo (montado à mão, com valores plausíveis para o `Gate`, ids 0 a 5):

```json
{
  "format": "jopendaw-preset",
  "version": 1,
  "family": "effect",
  "kind": "gate",
  "name": "Ruído de fundo (meu)",
  "created": "2026-09-30T13:04:15.000Z",
  "params": { "0": -55.0, "1": 0.001, "2": 0.05, "3": 0.2, "4": -30.0, "5": 20.0 }
}
```

Recusas antes de olhar o conteúdo: mais de 256 KB (`O arquivo é grande demais para ser um preset.`); não é UTF-8/JSON (`O arquivo não é um preset do jopendaw (não é um JSON válido).`); já há 300 presets do tipo (`Limite de 300 presets para este tipo. Apague algum antes.`). Todas lançam `PresetFormatException`, cuja mensagem vai para a janela `Não foi possível importar "arquivo"`. Avisos (`PresetImport.warnings`) usam a concordância certa do plural (`1 parâmetro desconhecido ignorado.`, `2 valores fora da faixa foram limitados.`).

### Versionamento

`userPresetFormatVersion = 1` vale para os dois formatos (o do guardado local, `format: jopendaw-user-presets`, e o do arquivo, `jopendaw-preset`). Uma versão maior que a conhecida é recusada no arquivo; no guardado local o **arquivo inteiro** é ignorado (`parseStored` devolve vazio), sem lançar. Campo novo opcional pode entrar sem subir a versão (o leitor ignora chave desconhecida); mudar o significado de um campo pede versão nova. O campo `version` de cada preset no guardado local é escrito mas não é lido (o preset relido sai sempre com a versão 1).

### Leitura do guardado local

`parseStored` (`@visibleForTesting`) é tolerante: JSON inválido, `format` diferente ou versão futura dão lista vazia; entrada que não é objeto, de tipo desconhecido, sem `params`, ou com id repetido é pulada sem afetar as outras. Diferente da importação, ali nada vira aviso (`strict: false`) e um valor ruim é ajustado em silêncio.

### Interface

`userPresetEntries({presets, current, color, checkWidth})` devolve as entradas que os menus põem **no topo**, acima dos de fábrica (desde `18c72f4`, fase 13; antes eram acrescentadas depois, com um divisor na frente): título `MEUS PRESETS`, `Nenhum ainda` (sem presets), uma linha por preset (`ValueKey('user-preset-<id>')`, valor `ApplyUserPreset`; o `…` tem `ValueKey('user-preset-more-<id>')`, tooltip `Renomear, apagar ou exportar` e valor `UserPresetMore`), divisor, `Salvar como preset…` (`user-preset-save`), `Importar preset…` (`user-preset-import`) e um divisor final (`PopupMenuDivider(height: 8)`) que já separa dos de fábrica. Os menus só a espalham no começo da lista de itens: em `instrument_panel.dart`, `entries = [...userPresetEntries(...)]` e as categorias de fábrica (com o divisor entre categorias e o título `p.category.toUpperCase()`) vêm depois; em `effects_panel.dart`, `itemBuilder` começa por `...userPresetEntries(...)`, depois o título `PRESETS` e a lista de fábrica com um `PopupMenuDivider()`, e então as ações do cartão. No painel de efeitos, `checkWidth` é 30 (alinha com os de fábrica) e as ações do cartão (`Reiniciar…`, bypass, mover, `Remover`) seguem no fim, como antes. A ordem das setas `step` do instrumento **não** mudou (fábrica e depois os do usuário; `[...list, ...userList]`), então já não acompanha a ordem visual do menu. Ambos os menus passam a ser `PopupMenuButton<Object>`, e o `onSelected` despacha por tipo: `Preset`/`EffectPreset` (fábrica), `ApplyUserPreset` (cada painel aplica), `UserPresetChoice` (`handleUserPresetChoice`).

`handleUserPresetChoice(context, choice, {family, kind, capture, presets, save, pick})`: o gerenciador, o `save` (padrão `AudioEngine.instance.saveFile`) e o `pick` (padrão `pickUserPresetFile`) são injetáveis para os testes. Fluxos: `Salvar` chama `askPresetName` (`_NameDialog`: título `Salvar como preset`, campo `Nome` com `maxLength` 60, contador oculto, filtro que nega controle C0/C1 e U+2028/U+2029, botão `Salvar` desabilitado com nome vazio, `Enter` confirma) e `UserPresets.save`; nome em uso devolve `null` e abre `confirmPresetDialog` (`Substituir o preset?`, `Substituir`), que chama `save(..., replace: true)` (mantém id, nome e data). `Renomear…`: `askPresetName(title: 'Renomear preset', confirm: 'Renomear', initial: nome)`; `rename` devolve `false` se **outro** preset do tipo tem o nome (`Nome em uso`). `Apagar…`: `Apagar o preset?` com botão vermelho `Apagar`. `Exportar preset…`: `presetFileName` e `exportBytes` para `save`; exceção vira `Não foi possível exportar`. `Importar preset…`: `FilePicker.pickFiles(dialogTitle: 'Importar preset', type: custom, allowedExtensions: [jopreset, json])`, cancelar não muda nada; `importBytes`; a janela `Preset "nome" importado` só abre se houver avisos ou se o preset for de outro tipo (`O preset é de outro tipo (kind): ele foi guardado, mas só aparece no menu desse tipo.`). Erros em diálogo (`showPresetMessage`, botão `Ok`), nunca toast.

### Decisões e por quê

- **Um valor só no `LocalStore`, não uma chave por preset.** Uma gravação atômica de tudo (a fila garante a ordem) e nenhuma listagem de chaves; o custo é regravar o JSON inteiro a cada mudança (até 300 presets por tipo, com centenas de bytes cada, é pequeno).
- **Sem áudio nem zonas no preset do sampler.** O áudio é endereçado por SHA-256 e vive no projeto e na nuvem; um preset que o citasse teria de carregar ou referenciar blobs, e teria de sobreviver ao áudio sumir. Por isso o preset do sampler é só timbre e envelope.
- **`Sidechain` fora.** É o id de uma faixa do projeto atual; em outro projeto apontaria para outra coisa. Igual aos presets de fábrica de efeito.
- **`family` no arquivo.** Deixa o `kind` (nome de tipo) livre para tipos novos sem colidir entre instrumento e efeito.
- **Nome único por tipo, sem diferenciar maiúsculas.** Evita duas linhas iguais no menu; salvar sobre um existente pergunta antes de substituir.
- **Aviso em vez de recusa na importação** quando dá para aproveitar o arquivo: um `.jopreset` de uma versão do app com um parâmetro a mais ainda entra.
- **Não sincroniza com a conta (por enquanto).** Sem rota nem tabela no servidor; o arquivo cobre o transporte.

### Como testar os presets do usuário

```bash
cd app && flutter test test/user_presets_test.dart
# a posição no topo dos menus (fase 13): grupo `menus de presets: Meus presets no topo` (instrumento e efeito) em test/fase13c_test.dart
cd app && flutter test test/fase13c_test.dart
```

Grupos: `nomes` (limpeza, 60 caracteres, nome hostil), `guardado` (ida e volta do arquivo local, capturar e aplicar são a identidade em todos os instrumentos e nos 12 efeitos, o EQ leva as 8 bandas, sidechain e `Nota base`/`Afinação` ficam como estão, substituir/renomear/apagar, nome único, limite de 300, arquivo local corrompido ou de versão futura, guardado que falha), `.jopreset` (exportar e importar, sufixo ` (2)`, arquivos ruins, `NaN`, infinito e valores enormes, nome hostil, sampler ignora `Nota base` e `Afinação` do arquivo) e `menu (widget)` (instrumento, efeito, celular estreito com nome comprido, importar pelo menu, exportar pelo `saveFile` injetado; os testes trocam `UserPresets.instance` por um em memória). A sessão de código relatou o uso no Chrome (salvar `Meu baixo grave` e o preset aparecer marcado com o visto), `(não repetido por quem escreveu esta documentação)`; o Android e o seletor de arquivos reais só têm teste automático `(testado só por testes automáticos)`.

### Armadilhas dos presets do usuário

- **`saveError` não aparece em tela nenhuma.** O comentário do campo diz que a tela pode avisar, mas nada em `app/lib/` o lê: se o guardado recusar a gravação (cota do navegador, disco cheio), a pessoa não vê aviso e perde os presets ao fechar o app.
- **Guardado ilegível ou de versão futura é tratado como vazio, e a próxima gravação o sobrescreve.** Voltar para um app mais antigo (que só conhece a versão 1) e salvar um preset apaga os presets do arquivo mais novo.
- **`Nome (editado)` fantasma.** O `_lastPreset` do painel não é limpo ao apagar nem ao renomear o preset: aplicar um preset seu, apagá-lo e deixar os valores como estão mostra `Nome (editado)` de um preset que não existe mais; depois de renomear e mexer num knob, o rótulo mostra o nome antigo.
- **Importar sem ressalvas não avisa.** A janela só abre com avisos: o único sinal de sucesso é a linha nova na seção `MEUS PRESETS` (e no menu de outro tipo, se o arquivo era de outro tipo, a mensagem cita o nome interno do tipo, como `reverb`).
- **Preset com todos os valores no padrão passa na frente de `Inicial`.** Salvar um instrumento intocado cria um preset que casa com o estado inicial de toda faixa nova daquele tipo, e o rótulo mostra o nome dele em vez de `Inicial`.
- **O campo de nome não nega marcas invisíveis (largura zero, direção do texto)**: elas são aceitas na digitação e viram espaço em `cleanPresetName` ao guardar, então o nome guardado pode diferir do digitado.
- **`userpresets` é global do aparelho**: não entra na chave nenhum id de conta e o `purgeLocalProject` e o sair da conta não mexem nele.
- **Cancelar o "salvar como" do Android volta em silêncio**: o `saveFile` devolve `false` e a interface ignora o resultado, como no projeto.
- **`UserPresets.instance` é estático**: testes de painel que não o troquem por um `UserPresets(MemoryUserPresetStorage())` leem o `LocalStore` de verdade.

## MIDI learn

> Para quem mexe no app: como um CC, pitch bend ou pressão do canal vira o movimento de um controle (`midi_map.dart`, `midi_learn.dart`, `midi_learn_ui.dart`), o formato do campo `midi_map` do documento e o que cuidar ao mexer aqui. Uso: [manual 06f](../manual/06f-midi-learn.md). Veio na fase 13 (`18c72f4`). Sem motor novo: o motor não sabe que existe mapa, tudo passa pelos setters de sempre.

### Visão geral

```
Web MIDI / plugin Android ── (status, d1, d2) ──► DawController._onMidi
                                                      │ 0xB0 / 0xE0 / 0xD0 e (há mapa ou MidiLearn criado)?
                                                      ▼
                                              MidiLearn.handle ── true ─► fim (não vira expressão)
                                                      │ false
                                                      ▼
                                   notas, CC 1/64/121/120/123, bend (caminho da expressão)

MidiLearn.handle
   ├─ armado?  ── sim ─► _learn: cria (ou substitui) o MidiMapping do alvo; lastLearned; consome
   └─ senão, para cada mapeamento com a mesma origem: _drive(m, raw)  ── consome (used = true)

_drive: midiMappingNorm (curva → inversão → mín/máx) ─► takeover (MidiPickup.accept)
        ─► midiTargetValue (escala do controle) ─► _set ─► setters dos gestos ─► autoRec, motor, salvar
```

### Peças e responsabilidades

| Arquivo | Papel |
|---|---|
| `daw/midi_map.dart` | Dart puro (sem Flutter): `MidiSourceKind` (`cc`, `bend`, `pressure`), `MidiSource` (tipo, canal 0..15, número do CC; `label` `Canal 1 · CC 74`, `shortLabel` `CC74`/`Bend`/`Pres.`), `MidiCurve` (`linear`, `log`), `MidiMapping`, `MidiMap` (`items` e `soft`), a conta (`midiRaw`, `midiCurveApply`, `midiMappingNorm`) e `MidiPickup` com `midiPickupTolerance` = 0,02 |
| `daw/midi_learn.dart` | `MidiLearn` (`ChangeNotifier`, criado sob demanda em `DawController.midiLearn`): modo (`learning`), alvo armado (`armed`), `lastLearned`, `handle`, `_drive`, `update`, `remove`, `removeFor`, `clear`, `setSoft`; `midiTargetValue`; o padrão para novos projetos (`midiDefaultKey` = `midimap:default`, `midiDefaultToJson`, `midiDefaultFrom`, `saveMidiDefault`, `clearMidiDefault`, `loadMidiDefault`) |
| `daw/midi_learn_ui.dart` | `MidiLearnControl` (o contorno que embrulha o controle), `showMidiLearnMenu`, `midiLearnActions` (entradas extras do menu do knob), `toggleMidiLearn`, `MidiLearnButton`, `MidiLearnBanner`, `showMidiMapPanel` e `MidiMapPanel` |
| `daw/model.dart` | `DawDoc.midiMap`, lido de `midi_map` e escrito só se não vazio |
| `daw/controller.dart` | `midiLearn` (criado sob demanda), `localStore` (o guardado local, para o padrão), `_onMidi` (o desvio para `handle`), `_travel` (mantém o `midiMap` no desfazer) e `_fromTemplate` (aplica o padrão a um projeto novo) |
| `daw/knob.dart` | `KnobMenuAction` e `Knob.extraActions`: com entradas extras, o botão direito e o toque longo abrem um menu (`Digitar o valor…` mais as extras) em vez do campo direto |
| `daw/instrument_panel.dart` (`_Ctx.knob`), `daw/fx_editors.dart` (`_Fx.knob`) | Embrulham cada knob em `MidiLearnControl` e passam `extraActions: () => midiLearnActions(...)`. O seletor de faixa-chave do `Sidechain` e o valor do gráfico do EQ **não** são embrulhados |
| `daw/mixer_panel.dart` | `MidiLearnControl` no pan e no fader (`secondaryMenu: true`) e em cada linha de envio (`radius: 4`, sem `secondaryMenu`, o botão direito é o menu do envio) |
| `daw/timeline.dart` | `MidiLearnControl` no mini fader do cabeçalho da faixa (o do `Master` não) |
| `daw/transport_bar.dart` | `MidiLearnButton` depois do cabo, se `midiEnabled \|\| midiLearn.learning \|\| !doc.midiMap.isEmpty` |
| `screens/project_screen.dart` | `MidiLearnBanner` abaixo da barra; `Shift+K` chama `toggleMidiLearn`; `Esc` chama `midiLearn.escape` (antes do `Esc` que fecha o painel de baixo) |
| `daw/shortcuts_dialog.dart` | grupo `Aprender MIDI` e a linha `Shift+K` em `suspendedShortcuts` (o teste `keyboard_test.dart` tira o `Shift+` e confere que a letra, aqui `K`, é do teclado musical) |

### O campo `midi_map` do documento

Só escrito quando há mapeamentos. Leitura tolerante: qualquer coisa que não seja objeto vira mapa vazio; um item inválido é descartado sem derrubar os outros; ids repetidos ficam com o primeiro.

| Campo | Tipo | Obrigatório? | Padrão / leitura | Significado |
|---|---|---|---|---|
| `soft` | bool | não | `true` (só `false` explícito desliga) | takeover de todos os mapeamentos |
| `items` | lista | não | `[]` | os mapeamentos |

Cada item de `items` (`MidiMapping`):

| Campo | Tipo | Obrigatório? | Padrão / leitura | Significado |
|---|---|---|---|---|
| `id` | string | sim | (item descartado se ausente) | id do mapeamento (`mm` + tempo em base 36 + contador) |
| `src` | objeto | sim | (item descartado) | origem, abaixo |
| `track` | string ou `null` | não | `null` = master | **id** da faixa (não o índice). Um valor que não é string vira `null` e portanto **master** |
| `target` | objeto | sim | (item descartado) | o `AutoTarget` da automação: `{"kind", "ref", "param"}`; `kind` desconhecido descarta o item |
| `min`, `max` | número | não | `0` e `1`; fora de 0..1 é levado para dentro; não finito vira o padrão | trecho do curso do controle (fração da posição 0..1 na escala dele), não do valor bruto |
| `curve` | string | não | `linear`; `log` (`MidiCurve.name`), qualquer outra coisa lê como `linear` | curva do controlador |
| `inv` | bool | não | `false` | invertido |

`src`: `k` (`cc`, `bend` ou `pressure`; outro valor descarta o item), `ch` (0..15, padrão 0, levado para dentro) e `cc` (0..127, padrão 0; só é escrito quando `k` é `cc`). Um `cc` de 120 a 127 vindo de um arquivo é aceito na leitura, mas `handle` nunca o casa (mapeamento inerte).

```json
"midi_map": {
  "soft": true,
  "items": [
    { "id": "mmlx3k9a0", "src": { "k": "cc", "ch": 0, "cc": 21 }, "track": "k3j9x0q2m1ab",
      "target": { "kind": "volume", "ref": null, "param": 0 },
      "min": 0.0, "max": 1.0, "curve": "linear", "inv": false },
    { "id": "mmlx3k9a1", "src": { "k": "bend", "ch": 1 }, "track": null,
      "target": { "kind": "pan", "ref": null, "param": 0 },
      "min": 0.0, "max": 1.0, "curve": "log", "inv": true }
  ]
}
```

Um app velho que abre um documento com `midi_map` ignora o campo e o **perde na próxima gravação** (regra geral do esquema); um documento sem mapa sai byte a byte igual ao de antes.

### Fluxo: aprender e mover

1. **Armar.** `MidiLearn.arm(track, target)` recusa (`false`) um alvo que `autoInfo` não resolve; senão liga `learning` e guarda `armed`. A tela chama `arm` no clique do contorno e no item `Aprender MIDI`. `Esc` (`escape`): desarma; sem armado, sai do modo.
2. **Aprender.** `handle` monta a `MidiSource` da mensagem (canal do `status`, CC em `d1`; `0xB0` com `d1 >= 120` sai com `false`, sem tocar em `armed`). Com `armed` presente: apaga o mapeamento anterior do **mesmo alvo** (`sameTarget`: faixa e `AutoTarget`), cria o novo com `min 0`, `max 1`, `linear`, sem inversão, guarda em `lastLearned`, semeia `MidiPickup.lastIn` com o valor da mensagem e devolve `true`: a mensagem que ensinou não move o controle. O mesmo CC pode ter vários alvos; um alvo tem uma origem só.
3. **Mover.** Sem armado, `handle` percorre uma **cópia** da lista (mudar o valor mexe no documento) e chama `_drive` para cada mapeamento de mesma origem; devolve `true` se houve ao menos um, **inclusive quando o alvo sumiu ou o takeover segurou o valor**.
4. **`_drive`.** Resolve a faixa por id (`trackOf`; faixa apagada: nada) e o `AutoInfo` do alvo; `midiMappingNorm` (curva, inversão, `min + (max − min) · n`); se `soft`, `MidiPickup.accept(incoming, autoNorm(fixed), min, max)`; converte com `midiTargetValue` (usa o `warp` do alvo: curva do fader no volume e no envio, logarítmica em Hz e segundos; reta no pan e nos lineares; degraus em inteiros e opções, pelo `_fit` dos setters) e chama `_set`.
5. **`_set`** usa os mesmos caminhos dos gestos: volume e pan: `autoRec.value` e `mutate` (`masterGain`/`masterPan` no `-1`); instrumento: `setParam`; efeito: `setEffectParam`; envio: `setSend(level:)`. É isso que faz o movimento gravar automação nos modos que gravam e entrar no motor pelo caminho rápido.
6. **Gesto e desfazer.** O primeiro valor que muda de um mapeamento abre uma "corrida" (`_runs[id]`): `autoRec.touch` e `checkpoint()` (um passo de desfazer). Cada mensagem reinicia um `Timer` de `midiIdleRelease` = 700 ms; ao vencer, `_endRun` chama `autoRec.release` (é o "soltar" do modo `Toque`). Remover ou limpar cancela as corridas (`_cancelRun`).

### Takeover (`MidiPickup.accept`)

Um `MidiPickup` por mapeamento (`_pickups[id]`), com `picked`, `lastIn` e `lastOut`. `accept(incoming, current, lo, hi)`:

1. Se estava `picked` e o controle agora está a mais de `midiPickupTolerance` (2%) do último valor que o app aplicou (`lastOut`): outra mão mexeu (mouse, desfazer, preset, automação): `picked = false`.
2. Se não está `picked`: `current` é levado para dentro de `[lo, hi]` (senão um controle fora da faixa nunca seria alcançado) e vira `picked` se `|incoming − current| <= 0,02` **ou** se a mensagem anterior e a atual ficam de lados opostos de `current` (`(lastIn − current) · (incoming − current) <= 0`, o cruzamento).
3. Grava `lastIn = incoming` (mesmo sem assumir) e devolve `picked`.

`update` (curva, inversão, faixa) zera `picked` daquele mapeamento. `soft == false` pula tudo e assume sempre. Depois de um valor aplicado, `lastOut` recebe a posição real do controle lida de volta (`autoInfo` de novo), para o setter poder ter arredondado ou limitado. O `current` vem de `info.fixed`, o **valor fixo**, não da curva de automação que está tocando.

### Padrão para novos projetos

`midiDefaultToJson(map, tracks)`: tira efeitos e envios; troca `track` (id) por `index` (posição da faixa; `null` para o master); faixa que não está mais na lista é descartada. `midiDefaultFrom(json, tracks, newId)`: cria mapeamentos com ids novos apontando para o id da faixa da mesma posição; posição fora do intervalo é descartada. `DawController._fromTemplate` aplica o padrão a todo documento **novo** (modelo ou `_fresh`), lendo `midimap:default` do `LocalStore` (guardado local: IndexedDB na web, arquivo no Android; nunca sincroniza). Um projeto que já tem `doc:<id>` não passa por lá.

### Como a tela se liga

- **`MidiLearnControl`** embrulha o controle e mantém a árvore igual nos dois estados (para o filho não perder o gesto em andamento ao ligar o modo): com o modo ligado, um `Positioned.fill` opaco por cima (`GestureDetector`: clique arma ou desarma, botão direito e toque longo abrem o menu) e o contorno (âmbar; verde se mapeado; etiqueta `shortLabel`); com o modo desligado e mapeado, um pontinho de 6 px. As chaves de teste têm o formato `midi-learn-<faixa>_<kind>_<ref>_<param>` (`-1` = master). Por ser opaco, o overlay **come** arrasto, roda e duplo clique do controle. `secondaryMenu: true` (fader e pan) põe um `Listener` que abre `showMidiLearnMenu` no botão direito **do mouse** (não no toque) fora do modo.
- **`Knob.extraActions`** (instrumento e efeito) mantém o toque longo e o botão direito no próprio `Knob`; sem `extraActions` (ou vazio) o comportamento antigo (`_type`, o campo de digitar) fica igual.
- **`toggleMidiLearn`** liga o modo e, se `midiEnabled` é falso, dispara `enableMidiInput` (o clique é o gesto que o navegador pede).
- **`MidiLearnBanner`** escuta `c` e `c.midiLearn`; escolhe o texto por armado, `lastLearned` vivo, `midiEnabled` e `midiInputs.isEmpty`.
- **`MidiMapPanel`** reconstrói com `Listenable.merge([c, l])`; guarda só uma nota de status local (`_note`) para as respostas do padrão.

### Decisões e por quê

- **Mapa no documento**, não no aparelho: o mapeamento é parte do projeto (viaja na nuvem e no `.jopendaw`); só o padrão para novos projetos é do aparelho.
- **Origem = canal + controle**: o Web MIDI e o plugin Android entregam `(status, d1, d2)` sem identificar o aparelho.
- **Alvo = `AutoTarget`**: reaproveita a resolução, os limites e a escala da automação (`autoInfo`, `automatable`, `targetName`); o que se automatiza é o que se mapeia.
- **Mesmos setters dos gestos**: um único caminho, então motor, salvar, desfazer e gravação de automação valem sem código novo.
- **Consumir a mensagem mesmo com alvo morto ou takeover segurando**: o controlador mapeado nunca vira expressão às escondidas.
- **`CC 120` a `127` fora**: o pânico, o reset e as notas desligadas seguem funcionando com qualquer mapa.
- **Mapa fora do histórico**: `_travel` mantém o `midiMap` (mapear não é edição musical).
- **Sem `dart:io` e sem bit a bit acima de 32 bits**: roda igual no dart2js (o pitch bend usa multiplicação: `msb * 128 + lsb`).

### Como testar

```bash
cd app
flutter test test/midi_learn_test.dart test/fase13c_test.dart
```

- `midi_learn_test.dart` (unidade e controlador, com o motor de mentira): ida e volta do JSON, compatibilidade (sem o campo, sem a chave), entradas inválidas, o mapa sobrevive a um desfazer; a conta (CC, pressão e bend de 14 bits; linear, log, invertida, faixa; escala do controle em Hz, volume, pan e inteiros); aprender por CC, bend e pressão, `CC 120..127` nunca, notas passam, substituir, remover, limpar, recusar alvo inexistente, `Esc`; conflito com a expressão (`CC 1`, pedal e bend mapeados de propósito); takeover (cruzar, 2%, mouse solta, desligado salta, faixa estreita); alvos que somem (efeito removido, faixa apagada, tipo trocado; o CC continua consumido); gesto de desfazer e os 700 ms; gravação de automação pelo controlador; padrão (`midiDefaultToJson`/`midiDefaultFrom`, projeto novo, projeto que já tem documento).
- `fase13c_test.dart`, grupo `MIDI learn na tela` (widget): contorno, clique arma, o CC mapeia, o pontinho, `Esc`; botão direito no knob (`Digitar o valor…`, `Aprender MIDI`, `Remover mapeamento (...)`); a janela `Mapeamentos MIDI` (invertido, curva, faixa, takeover, padrão, remover, alvo removido, `Remover todos`); `Shift+K` pela tela do projeto e o botão da barra; mixer no modo (fader, pan, envio e o master).
- No Chrome (`node tool/cdp.mjs` com `jopendawEngine.injectMidi(0xB0, 21, 40)` depois de armar um controle), a sessão de código viu `Aprendido: Canal 1 · CC 21 → Pad · Volume`, a etiqueta `CC21` e o fader em −24,1 dB com o `CC 40` (relato; não repeti). Não há teste com controlador de verdade.

### Armadilhas conhecidas

- **Um `CC 1`, `CC 64` ou bend mapeado deixa de ser expressão** (e de gravar pontos no clipe) até o mapeamento ser removido, mesmo com o alvo apagado. Ver [04 Expressão MIDI](04-expressao-midi.md).
- **O canal conta no mapeamento e não na expressão.** O mesmo `CC 1` em outro canal segue como modulação.
- **Os ids de parâmetro se repetem entre instrumentos** (`13` é `Corte` no sintetizador, `Ataque` do operador 2 no FM, `Desafino` no wavetable) e o mapeamento guarda só o id, não o tipo: um padrão aplicado por posição a um modelo cujas faixas têm outros instrumentos pode cair em outro parâmetro sem aviso. `(lido do código; não testado)`
- **Desfazer não cobre o mapa.** Nem `Remover todos`, nem `Remover mapeamento`, nem aprender de novo (que substitui o anterior) entram no histórico; e `_applyRemote` troca o documento inteiro, inclusive o `midi_map`, pelo do servidor.
- **Só `midiMap.items` decide se o campo é escrito.** `isEmpty` olha os itens: com a lista vazia o `soft` desligado não é gravado (volta a `true` ao reabrir).
- **`track` que não é string lê como master.** Um item de outra versão com `track` fora do formato vira mapeamento do `Master` em silêncio.
- **`remapDocIds` (importar `.jopendaw`) não reescreve o `midi_map`.** Enquanto os ids de faixa forem os de sempre (seguros e únicos) eles são mantidos e o mapa segue valendo; ids inseguros ou repetidos ganham id novo e os mapeamentos daquelas faixas viram `Faixa removida`. `(lido do código; não testado)`
- **O início do gesto pode não abrir o passo de desfazer.** Em `_drive`, se a primeira mensagem de um gesto resulta num valor igual ao fixo (`v == info.fixed`, comum em parâmetros inteiros e de opção), o código chama `_keepRun` e sai; a corrida já existe quando o valor muda na mensagem seguinte, então `autoRec.touch` e `checkpoint()` (guardados por `!_runs.containsKey(id)`) **não** rodam, e essa mudança não tem passo próprio no desfazer (`Ctrl+Z` desfaria outro passo anterior). `(lido do código; não reproduzido)`
- **O tooltip do knob e o `keyboardTooltip` estão atrasados**: o do knob ainda diz `botão direito: digitar o valor` (agora é um menu) e o do teclado ligado lista `C L S X Z E F K J e Shift+H/L`, sem o `Shift+K` que a lista de atalhos suspensos já traz (`widgets/format.dart`).
- **Flutter desenha em canvas**: para o teste de uso no Chrome os cliques e teclas vão pelo `node tool/cdp.mjs`, não pelo MCP `chrome-devtools`.

## Tabelas espelhadas do motor (`instruments.dart`, `effects.dart`)

- **`TrackKind`** (`instruments.dart:13`): `audio, synth, drums, sampler, bus, fm, wavetable`. `values[i].index` é o código de `track_kind` no motor: **tipo novo só entra no fim** do enum.
- **`ParamSpec(id, nome, grupo, mín, máx, padrão, unit, curve)`** (`:65`): `curve` é `linear`, `log`, `integer` ou `choice` (lista de opções; o valor é o índice). `toNorm`/`fromNorm` convertem entre valor e posição 0..1 do controle; `format` monta o texto ("1,2 kHz", "250 ms", "+3 st").
- **Instrumentos**: `synthParams` (35 ids, tipo 1), `drumParams` (12 peças × 4 + volume geral no id 48, tipo 2), `samplerParams` (tipo 3), `fmParams` (42 ids, tipo 5, operadores em `2 + operador*8 + k`), `wavetableParams` (39 ids, tipo 6); mais `fmAlgorithmMods`/`fmAlgorithmCarriers` (roteamento dos 8 algoritmos FM, espelho de `ALGORITHMS` em `fm.rs`). Os valores vão ao motor **na unidade da tabela**.
- **`EffectKind`** (`effects.dart:12`): 12 tipos com `code` 1..12 (o argumento de `fx_set`), família do menu (`family`) e `params`. Tabelas: `eqParams` (8 bandas × 6 + saída no id 48), `compressorParams`, `gateParams`, `limiterParams`, `utilityParams`, `reverbParams`, `delayParams`, `chorusParams`, `phaserParams`, `tremoloParams`, `distortionParams`, `filterParams`. `noteValues` espelha `NOTE_BEATS` do motor (figuras do delay, tremolo e filtro sincronizados).
- `defaultParams(kind)` e `defaultEffectParams(kind)` montam o mapa de padrões (usados ao criar faixa e slot e por `DawTrack.param`).

### Testes de contrato (o que quebra se as tabelas divergirem)

| Teste | O que confere | Como |
|---|---|---|
| `engine/src/synth.rs::faixas_iguais_as_do_app` | faixas, padrões, discretos e opções do `synthParams` | lê `app/lib/daw/instruments.dart` como **texto** e compara linha a linha |
| `engine/src/fm.rs::faixas_iguais_as_do_app`, `algoritmos_iguais_aos_do_app` | `fmParams`; `fmAlgorithmMods` e `fmAlgorithmCarriers` | `instrument.rs::contract::check` |
| `engine/src/wavetable.rs::faixas_iguais_as_do_app` | `wavetableParams` | `contract::check` |
| `app/test/effects_contract_test.dart` | ids, nomes e faixas de cada efeito (`*_param` de `engine/src/effect.rs` × `effects.dart`), códigos de `fx_set` × `EffectKind`, `NOTE_BEATS` × `noteValues` | lê `../engine/src/effect.rs` |
| `app/test/studio_test.dart` | toda chamada que o controlador manda existe em `engine/wasm/src/lib.rs` com o número certo de argumentos | lê o `lib.rs` do wasm |
| `app/test/fm_wavetable_test.dart` | índice do enum = código do motor, operadores FM, algoritmos, presets | Dart puro |

Duas consequências práticas: (1) os testes de Rust **fazem parse de texto do Dart**; a tabela precisa manter o formato (uma `ParamSpec(...)` ou `ParamSpec.choice(...)` por linha, números literais, `Curve.integer` na mesma linha, `def: n` em opções) ou o teste quebra por formato, não por valor; (2) **bateria e sampler não têm teste de contrato** (nenhum arquivo de `drums.rs`/`sampler.rs` lê o Dart: há só comentários apontando para as tabelas), então uma divergência ali passa silenciosa.

## Contratos (resumo)

- Documento: seção "Esquema JSON" acima. O servidor guarda o objeto sem interpretá-lo (só exige objeto JSON, sem `\u0000`, ≤ 8 MB): ver [11 Servidor](11-servidor.md).
- Motor: nomes e argumentos das chamadas em [02 Pontes web e Android](02-pontes-web-e-android.md) e `engine/src/api.rs`.
- Servidor: rotas em [11 Servidor](11-servidor.md); o cliente delas é `ApiClient` (`api/client.dart`).
- Arquivo `.jopendaw`: seção [Arquivo de projeto](#arquivo-de-projeto-jopendaw) acima (zip com `project.json`, `manifest.json` e `samples/<sha-256>.<ext>`; `format` 1).

## Como acrescentar (checklist ponta a ponta)

### Um instrumento novo

Exemplo: tipo 7. Nada do servidor muda (o documento é JSON opaco) e o `model.dart` também não (o tipo é gravado pelo nome).

**Motor** (dono: quem mexe em `engine/`):
1. `engine/src/instrument.rs`: `kind::NOVO = 7`, módulo `novo_param` com os ids e `COUNT`, e o ramo em `create()`.
2. `engine/src/novo.rs` implementando `Instrument` (`note_on`, `note_off`, `release_all`, `silence`, `set_param`, `render`, `active`), tabela `SPECS` na ordem dos ids, `pub mod novo;` em `engine/src/lib.rs`.
3. Teste `faixas_iguais_as_do_app` com `contract::check("novoParams", &rows)` (como em `fm.rs`).
4. `./engine/build-web.sh` e `./engine/build-android.sh` (NDK 28, `ANDROID_NDK_HOME`) e **commitar `engine.wasm` e os `.so` juntos**.

**App**:
5. `app/lib/daw/instruments.dart`: `TrackKind.novo('Rótulo', Icons.x)` **no fim** do enum; incluir em `isInstrument`; ramo em `params`; `const novoParams = <ParamSpec>[...]` no formato que o teste lê. O compilador aponta os `switch` exaustivos que faltam.
6. `app/lib/daw/presets.dart`: `abstract final class NovoId` (constantes dos ids), lista de presets e o ramo em `presetsFor`.
7. `app/lib/daw/instrument_panel.dart`: oitava do teclado (`_octave`, `:44`), a lista de botões de criar (`_createButtons`, `:132`) e o `switch` do layout (`:384`), com as seções de knobs.
8. `app/lib/daw/timeline.dart:1316`: o `case` do menu "Nova faixa".
9. Testes: cópia do padrão de `app/test/fm_wavetable_test.dart` (índice do enum, persistência pelo nome, painel monta e o preset chega ao motor).
10. Documentação: manual do instrumento e `docs/dev`.

Se o instrumento tem um desenho próprio no painel (como o gráfico da wavetable), o espelho Dart da lógica do motor deve ter teste que o compare (ver `wavetable_shape_test.dart`).

### Um efeito novo

1. Motor: `engine/src/effect.rs` (`kind::NOVO = 13`, módulo `novo_param`, ramo em `create()`), arquivo em `engine/src/fx/`, faixas dos ids documentadas no comentário `///` de cada constante (o teste de contrato lê "−60..0" desse comentário).
2. `app/lib/daw/effects.dart`: `EffectKind.novo(13, 'Rótulo', 'Descrição', ícone)` no fim, `family`, `params` e a tabela `novoParams`.
3. `app/test/effects_contract_test.dart`: entrada no mapa `_names` (constante do motor → nome do parâmetro).
4. `app/lib/daw/fx_presets.dart`: lista de presets e o ramo do `switch` (`~:190`); editor: o genérico (`fx_editors.dart`) já monta knobs por grupo; um editor próprio (como o EQ e a dinâmica) entra no `switch` de `fx_editors.dart:290`/`:300`. Regras de habilitar/esmaecer parâmetros por dependência estão em `fx_editors.dart:327`–`:341`.
5. Se tem sidechain: ampliar `_sidechainParam` (`controller.dart`) e `isSidechain` (`fx_editors.dart`).
6. Recompilar os binários; testes; documentação.

### Um parâmetro novo em instrumento ou efeito existente

1. Motor: nova constante **no fim** da numeração do módulo `*_param` (nunca reaproveitar nem renumerar: projetos salvos guardam o id), `COUNT`/`SPECS` e o uso no DSP.
2. Dart: nova linha na tabela (`ParamSpec(id, ...)`), mesmo id, mesma faixa, mesmo padrão.
3. Projetos antigos não têm o id em `params`: o padrão da tabela vale (`DawTrack.param`, `EffectSlot.param`); nada a migrar.
4. Painel: incluir o controle na seção certa (`instrument_panel.dart`) ou, nos efeitos, o grupo da tabela já o coloca no editor genérico.
5. Presets e modelos: só os que diferem do padrão precisam mencionar o id.
6. Recompilar wasm e `.so`, rodar os testes de contrato, teste de uso no Chrome (o som muda com o knob?).

### Um campo novo no documento

1. `model.dart`: campo, `fromJson` com **padrão** (documento antigo não tem), `toJson` com o campo (omitido se padrão, se a compatibilidade byte a byte importa).
2. Decidir se é preferência do aparelho (então `_travel` e `_applyRemote` precisam preservá-lo, como `metronome`) ou parte da música.
3. Se vai ao motor: `_docCalls` e o cache `_Sent*`; a chamada nova precisa existir no motor e nas duas pontes.
4. Um app velho que abrir o documento novo **descartará** o campo ao regravar (ver Armadilhas).

## Decisões e por quê

- **Documento como JSON, histórico como cópias do JSON.** Simplicidade: desfazer é trocar o documento; o custo é memória (até 200 cópias) e o `jsonEncode` a cada checkpoint.
- **Diferença em vez de reenvio total ao motor.** Um arraste de knob mandaria centenas de parâmetros por quadro; o cache `_Sent*` reduz a uma chamada. O que é barato (clipes, notas) reenvia inteiro para ficar simples.
- **Ids como contrato.** Mudar o id de um parâmetro quebra projetos salvos; por isso as tabelas são apenas cumulativas e há testes que leem o outro lado.
- **Erro inline, nunca toast** (decisão de produto, `InlineNotice`).
- **Prosa em português acentuado, identificadores em inglês**; `dart format -l 160`.

## Como testar

```bash
cd app
flutter analyze
flutter test                                   # unidade e widget, motor de mentira (test/fake_engine.dart)
flutter test test/sync_test.dart               # sincronização e jobs, servidor de mentira (test/fake_sync_api.dart)
flutter test test/fase13b_test.dart            # 422 com reenvio, pull da abertura ocupado, ponteiro sem PointerUp, purge do warp, texto da limpeza do servidor
flutter test integration_test -d emulator-5554 # motor nativo no emulador Android
cargo test -p jopendaw-engine                  # inclui os testes de contrato que leem o Dart
```

Mapa de andamento e de compassos: `flutter test test/tempo_map_test.dart test/tempo_lane_test.dart` (conta do mapa, JSON e documento antigo, controlador e motor de mentira, gravação e render com mapa, e a comparação com o `render-worker.js` real no node; no `tempo_lane_test.dart`, a faixa `Andamento` com duplo clique, arrasto, menu e o diálogo de compasso, em widget test) e `cargo test -p jopendaw-engine tempo` (os 10 testes de `tempo.rs` e os 13 de `tempo_tests.rs`). No navegador: segundo o relato da sessão de código, o duplo clique na faixa e o diálogo de compasso **não** foram exercitados no Chrome (só há widget test); o botão direito na faixa, o menu, o arraste e a medição do salto foram (relato; não repeti).

Para conferir a saída: `flutter test 2>&1 | tr '\r' '\n' | grep -E "All tests passed|Some tests failed|\[E\]"`. Mudou o motor: recompile os binários antes de testar no navegador ou no Android. O teste de uso (obrigatório antes de dar uma fase por pronta) é usar o app no Chrome: ver [03 Build, teste e depuração](03-build-teste-e-depuracao.md) e [20 Processo e histórico](20-processo-e-historico.md).

## Armadilhas conhecidas

- **Preferências contam como mudança para sincronizar.** `_save` compara o JSON inteiro com o último gravado (`DawController._save` em `controller.dart`); `metronome`, `count_in`, `rec_latency_ms`, `armed` e `monitor` estão no JSON, então ligar o metrônomo marca o projeto como pendente e gera versão nova no servidor (mesmo que outro aparelho as ignore ao aplicar). Lido no código; efeito sobre conflitos falsos `(não confirmado no uso)`.
- **`setTempo` e o desfazer (corrigido na fase 9).** O andamento mora no documento; desfazer restaura o `bpm` antigo no documento e o `_save` seguinte reenvia o espelho (`PATCH`) se ele difere do último confirmado. Reabrir usa o `doc.bpm` local. Resta que `projects.bpm` (lista de projetos) pode ficar defasado enquanto o `PATCH` está pendente (offline). `(lido do código e coberto por `phase9c_test`; não visto no Chrome)`
- **Limpeza local ao apagar projeto (fase 9).** `projects_screen._delete` chama `deleteProject` na API e depois `purgeLocalProject(LocalStore.instance, id, idsDaLista)` (`local_purge.dart`): apaga `doc:<id>`, `sync:<id>`, `template:<id>` e os `sample:<hash>` que só o documento local desse projeto cita. Os de qualquer outro projeto ficam, e "outro projeto" é a união dos ids da lista com todo `doc:*` que `LocalStore.keys('doc:')` devolve (**resolvido em `8b07070`**: antes só valia a lista carregada, então um projeto ausente dela, de outra conta ou só deste aparelho não protegia seus áudios). `keys(prefix)` existe nos dois lados do `LocalStore`: no Android lista os arquivos do diretório e desfaz o nome (`FileStore.keyOfFileName`; as chaves longas que viraram hash não voltam), na web usa `idbKeys` do `host.js`. Nunca lança, devolve quantos áudios apagou. **Resolvido em `1180152`: o cache `warp:<hash>|<parâmetros>` (o derivado do warp de cada áudio, ver `WarpSpec.key`) também sai**, mas só o dos áudios apagados: a limpeza lista as chaves `warp:` e apaga as que começam pelo hash de um `sample:` que saiu (antes ele ficava para sempre, e o comentário de `local_purge.dart` dizia, sem ser verdade, que o guardado não lista chaves); o derivado de um áudio que outro projeto ainda usa fica. O retorno continua contando só os `sample:`. Só limpa o aparelho que apagou. `(testado só por testes automáticos)`
- **URL da API e `flutter run`.** Na web a base é a origem da página em qualquer porta (`baseFor`), então o app do compose em `localhost:8081` usa o `/api` do nginx dele. Já um `flutter run -d chrome` (porta própria, sem API) exige `--dart-define=API_BASE=...`; sem isso as chamadas caem na porta do `flutter run`. `(lido do código e coberto por `phase9c_test`; não rodado com `flutter run`)`
- **Cache do navegador.** Depois de `flutter build web`, `host.js`, `engine.wasm` e `main.dart.js` podem ficar velhos no navegador (service worker). O servidor de desenvolvimento manda `Cache-Control: no-cache`; ao testar, limpar o service worker e os caches evita `... is not a function`.
- **Estado de estúdio em teste.** `DawStudio` é público para os testes montarem a tela sem a API; o controlador aceita motor, guardado e API por injeção.
- **`ProjectScreen` recria o controlador** ao trocar de projeto (`ValueKey`), e o `dispose` do controlador salva (`_save`) e para o motor (`stop`, `panic`, `watch_*`): um projeto nunca deixa nota soando para o próximo.
- **Áudio → MIDI e formatos (resolvido na fase 9, `e2bc4ea`).** `convertToMidi` envia o sample **original** (`sample:<hash>`) ao servidor. Até a fase 8 o servidor só decodificava WAV; agora decodifica também MP3, FLAC, OGG Vorbis e AAC/M4A/ALAC (symphonia), com limite de 10 minutos por arquivo; OGG/Opus, AIFF e WebM seguem sem suporte. Ver [11 Servidor](11-servidor.md) e [03d](../manual/03d-audio-para-midi.md). Visto no Chrome só com MP3.
- **`flac` nunca é pedido pelo app.** O job `flac` existe no servidor, mas nada em `app/lib/` chama `createJob('flac', ...)`.
- **dart2js: operadores de bit em 32 bits.** Na web, `<<`, `>>`, `&`, `|`, `^` e `~` trabalham em 32 bits (o inteiro do dart2js é um número de JavaScript), enquanto na VM do Dart (testes, Android) o inteiro tem 64 bits. Então `1 << 62` dá 0 no navegador e `2 << 30` dá um número negativo, e a VM não mostra nada. Caso real, corrigido em `606664f`: `slicePoints` (`sampler_zones.dart`) começava a busca do menor comprimento de canal em `1 << 62`, que no navegador virava 0; `n == 0` devolvia lista vazia e o `Fatiar sample…` nunca achava corte (nem por transientes, nem em N fatias iguais). No mesmo commit, `ProjectFileLimits` (`project_file.dart`) tinha `maxTotalBytes = 2 << 30`, negativo no navegador, e o limite de tamanho do `.jopendaw` ficava errado. A regra: para inteiros grandes que rodam na web, use aritmética normal (`1024 * 1024 * 1024`, `reduce(math.min)` em vez de um valor inicial enorme; um `int` da web é exato só até 2^53) ou `BigInt`, nunca `<<` que passe de 31 bits, e nunca máscara ou deslocamento em valor que possa passar de 32 bits. O teste `app/test/web_int_safety_test.dart` varre `app/lib/` atrás de constantes `N << K` que passem de 31 bits, mas só enxerga literais (não vê `1 << n` com `n` variável, `>>` nem máscaras) e roda na VM, lendo os arquivos com `dart:io`. Levantamento de `<<` e `>>` em `app/lib/` (feito depois de `606664f`), todos hoje dentro de 32 bits, listados como riscos a vigiar:
  - `daw/project_file.dart:51-52`: `512 << 20` (2^29) e `64 << 20` (2^26); passam, mas não aceitam mais um bit; prefira a multiplicação, como os outros dois limites.
  - `daw/export.dart:126`: `1 << 30` como teto do `clamp` (2^30, no limite: `1 << 31` já seria negativo).
  - `daw/controller.dart:3271`: `_countZoneBars = 1 << 16`; `audio/engine_ffi.dart:883`: `1 << 20` (só Android); `daw/sync.dart:292`: `1 << math.min(_failures, 10)` (o `min` segura em 2^10; sem ele, a partir de 31 falhas o valor viraria negativo ou voltaria a 1 no navegador).
  - `daw/wav.dart:104-106` e `:185-186`: WAV de 24 bits, `q & 0xFF`, `q >> 8`, `q >> 16` e `bytes[p+2] << 16`; valores de no máximo 24 bits com sinal, seguros.
  - `daw/controller.dart:2453`: pitch bend `(data2 & 0x7F) << 7 | (data1 & 0x7F)`, 14 bits, seguro.
  - `daw/instrument_panel.dart:564-573` e `:2049-2071`: máscaras de portadores e moduladores do FM (`carriers >> n & 1`, `mods[to] >> from & 1`), de poucos bits (4 operadores), seguras.
  - `daw/automation_lane.dart:34,48,63`, `daw/automation_math.dart:42` e `daw/timeline.dart:274`: `(lo + hi) >> 1` em índices de busca binária; seguros enquanto a lista tiver menos de 2^31 itens.
  - Fora dos deslocamentos, os `Uint64` de `audio/engine_ffi.dart` são `dart:ffi` (só Android, 64 bits de verdade); `wav.dart:37` compara `total - 8 > 0xFFFFFFFF` sem operador de bit (comparação normal, exata até 2^53); o LCG de `sampler_zones_test.dart` faz `& 0xFFFFFFFF` sobre um produto de cerca de 2^52, no limite da exatidão da web.
