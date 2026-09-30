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
| `beats_per_bar` | int | sim | (do projeto, só num documento novo) | tempos por compasso. Mesma regra do `bpm`. Conta **semínimas** (um 6/8 guarda 3). O espelho no servidor (`projects.beats_per_bar` e `projects.beat_unit`) não usa este campo: leva o numerador e a figura do compasso 1 do `meter_map` (`_wantedTempo`, fase 15; um 6/8 vira `6` e `8`; o numerador é limitado a 1–32 **de propósito**: o mapa aceita até 64 no JSON, mas o servidor e o `CHECK` de `projects.beats_per_bar` só aceitam 32, e um `PATCH` com mais seria recusado e o espelho ficaria pendente para sempre). Num documento **novo** (`_fresh`/`_fromTemplate`) o caminho é o inverso, desde `52d25c1`: `_quarterBeatsPerBar` = `round(project.beatsPerBar * 4 / project.beatUnit)` limitado a 1–32 vira o `beatsPerBar` (um 6/8 do cadastro dá 3, um 7/8 dá 3,5 arredondado para 4), e `_projectMeterMap` põe o compasso exato no `meter_map` quando `beatUnit != 4`. A figura do compasso e a taxa de amostragem não estão no documento fora do mapa |
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
| `metronome_options` | objeto | não | **(omitido no padrão)** | fase 17: `timbre`, `subdivision`, `mode` (nomes dos enums), `volume`, `accent_level`, `accent_pitch`, `sub_level`; só o que foge do padrão (`MetronomeOptions`). Valor ruim cai no padrão ou no limite |
| `pre_roll` | inteiro | não | **(omitido em 0)** | fase 17: compassos de pré-roll, 0..4 (`setPreRoll`) |
| `punch_in`, `punch_out`, `punch_on` | número (batidas), número, `true` | não | **(omitidos sem região)** | fase 17: região de punch (início ≥ 0 antes do fim; senão some) e se está ligado. `_travel` e `_applyRemote` preservam `metronomeOptions`, `preRollBars`, `punchIn`, `punchOut` e `punchOn` como preferência do aparelho; campo a campo em [Punch, pré-roll, tap tempo e opções do metrônomo](#punch-pré-roll-tap-tempo-e-opções-do-metrônomo-fase-17-c) |
| `master_effects` | lista de efeito | não | `[]` | cadeia de inserts do master (depois dele vem o volume e o limitador de segurança do motor) |
| `master_lanes` | lista de lane | não | `[]` | automação do master (alvos volume, pan e efeito) |
| `markers` | lista de marcador | não | `[]` (reordenada por `beat` ao ler) | marcadores da régua |
| `midi_map` | objeto `{soft, items}` | não | **(omitido quando é o mapa padrão: sem mapeamentos e `soft` ligado, `MidiMap.isDefault`)**; ausente ou inválido lê como mapa vazio | mapeamentos do MIDI learn e a opção de takeover. Formato campo a campo na seção [MIDI learn](#midi-learn) |

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
| `group` | bool | não | ausente (`false`) | fase 14: só escrito quando `true`. Marca o barramento como **pasta** de faixas. Lido só se `kind` for `bus` (em outra faixa é ignorado) |
| `group_id` | string | não | ausente (`null`) | fase 14: só escrito quando há valor. Id da pasta a que a faixa pertence |
| `collapsed` | bool | não | ausente (`false`) | fase 14: só escrito em pasta (`group: true`) recolhida |

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
| `kind` | string | sim | | `eq`, `compressor`, `gate`, `limiter`, `utility`, `reverb`, `delay`, `chorus`, `phaser`, `tremolo`, `distortion`, `filter`, `multiband`, `deesser` ou `imager` (o `name` de `EffectKind`). **Tipo desconhecido: o slot é descartado ao abrir** |
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

### Pastas de faixa (`daw/track_groups.dart`, `track_groups_ui.dart`)

Uma pasta é uma faixa `TrackKind.bus` com `isGroup` (JSON `group: true`; `collapsed: true` quando recolhida). As filhas têm `groupId` (JSON `group_id`) igual ao id dela, `output` igual ao id dela e ficam contíguas logo abaixo. Os três campos só vão ao JSON quando têm valor: documento sem pastas sai byte a byte igual. `DawDoc.fromJson` solta filhas órfãs (`_repairGroups`). O motor não sabe de pasta: é um barramento e `track_output` das filhas aponta para o índice dele. Não há pasta em pasta nem retorno como filho. `planTrackMove` (puro) decide o movimento de faixa/bloco e as trocas de pasta e saída; `moveTrack`, `routesBrokenByMove` (o aviso) e `setTrackOrder` (sidechains, rotas para trás, seleção) o usam. `groupTracks`, `ungroup`, `joinGroup`, `leaveGroup` e `setGroupCollapsed` estão na extensão `DawGroupsController`; cada uma é uma edição só no desfazer (exceto recolher, que usa `mutate` e que `_travel` preserva). Na linha do tempo, filhas de pasta recolhida ficam com bloco de altura zero em `_Layout` (o índice de faixa segue igual) e não desenham clipes.

**Modelo e compatibilidade (`model.dart`).** `DawTrack.isGroup`, `groupId` e `collapsed` (ver a tabela da faixa acima). `toJson` escreve `group: true`, `group_id` e `collapsed: true` só quando têm valor, então um documento sem pastas sai igual ao de antes (teste "documento antigo, sem os campos, abre igual e volta igual"). `fromJson` só aceita `group` em faixa `bus`. `DawDoc._repairGroups` (chamado no construtor a partir do JSON) zera o `groupId` de faixa cuja pasta não existe ou que é barramento. Não repara contiguidade nem `output` diferente da pasta. Quem abre o documento numa versão anterior do app vê a pasta como um barramento comum e as filhas como faixas que saem nele (a leitura ignora as chaves novas `(dedução; não testado)`). O servidor guarda o documento como JSON opaco, sem espelho dos campos novos (`(não confirmado)`: não li o servidor).

**Extensões (`track_groups.dart`).** `DawGroups` sobre `DawDoc`: `hasGroups`, `folderOf(i)` (−1 fora de pasta ou na própria pasta), `membersOf(folder)`, `hiddenByGroup(i)` e `groupSize`. `canJoinGroup` (não é pasta nem barramento). `planTrackMove(tracks, from, to)` é pura e devolve `TrackMovePlan(order, changes)` ou `null`: mover pasta leva o bloco e nunca a deixa cair dentro de outra pasta; largar dentro de um bloco põe a faixa nela e troca a `output`; largar fora tira da pasta e devolve a saída ao master; pasta recolhida e barramento pulam para fora do bloco (`_insideGroup`, `_blockEnd`). `GroupChange.warning` alimenta o aviso de rota.

**Controlador (`DawGroupsController`, extensão de `DawController`).** `whyNotGroupable`, `nextGroupName` (`Pasta N`), `groupTracks(ids, name:)` → `GroupResult` (`folder`, `error`), `ungroup(id)` → `UngroupResult` (`none`, `removed`, `keptAsBus`), `leaveGroup`, `joinGroup`, `setGroupCollapsed` e `setAllGroupsCollapsed`. Cada operação de estrutura é **um** `edit` (um passo de desfazer); `setGroupCollapsed` usa `mutate` (sem checkpoint) e, se a seleção ficou escondida, `selectTrack(pasta)`. Em `controller.dart`: `moveTrack` e `routesBrokenByMove` passam por `planTrackMove`; `setTrackOrder(order)` troca a lista mantendo sidechains (`_remapSidechains`), apagando rotas para faixas que saíram (`_dropRoutesTo`), desfazendo rotas para trás (`_dropBackwardRoutes`) e a seleção; `removeTrack` de uma pasta zera o `groupId` das filhas (o caminho pela interface, desde a fase 16 `ffa76ba`, é `confirmDeleteGroup`, o item `Apagar a pasta (as faixas ficam)…`; `_dropRoutesTo` manda as filhas ao master); `duplicateTrack` ignora pasta; `_travel` (desfazer e refazer) restaura `collapsed` da faixa atual, então recolher não é desfeito nem refeito.

**Interface (`track_groups_ui.dart`).** `showGroupDialog` / `_GroupDialog` (chaves `group-name`, `group-pick:<id>`, `group-confirm`; `_submit` pergunta por `confirmGroupRoute` antes de agrupar faixas que já saíam para um barramento), `confirmUngroup` (dois textos: o de `ungroupKeepsRoutes` e o de barramento que some), `confirmDeleteGroup` (item `delete` do `_GroupMenu`), `groupMenuItems` e `onGroupMenu` (valores `grp:new`, `grp:leave`, `grp:join:<id>`, chamados no `default` do `_TrackMenu` em `timeline.dart`; `leave` e `join` pedem `confirmGroupRoute` quando `leaveGroupNotes`/`joinGroupNotes` trazem linhas), `GroupHeader` (chaves `group-header:<id>`, `group-toggle:<id>`, `group-fader:<id>`, `group-menu`; layout `compact` no celular), `GroupIndent` (tira no `_TrackHeader`), `GroupMiniLane` (chave `group-mini:<id>`, `CustomPaint` sob `IgnorePointer`) e `GroupBar` (`group-bar:<id>`, `group-member:<id>`, altura `groupBarHeight` = 14, usada por `mixer_panel.dart`). Em `timeline.dart`, `_Layout.of` pula as filhas de pasta recolhida (`ends.add(y)` sem linha; as raias de automação delas também não entram) e `trackAt` volta à última faixa visível; a raia, os clipes e o retângulo da gravação usam `!doc.hiddenByGroup(ti)`. O `_KindIcon` do mixer mostra `Icons.folder` e o tooltip `Grupo`.

**Testes.** `app/test/track_groups_test.dart` (34 testes; a fase 16 A acrescentou os casos de pasta em `app/test/fase16a_test.dart`: saída do mixer que tira da pasta, congelar dentro da pasta, notas e diálogos de troca de saída, `remapDocIds`, `ungroup` com efeito e `Apagar a pasta`), (`flutter test test/track_groups_test.dart`): JSON (antigo, ida e volta, filha órfã), agrupar (saídas, motor recebe `track_output`, contiguidade, recusas), desagrupar (`removed`, `keptAsBus`, desfazer), recolher (desfazer não o desfaz, seleção, todas), mudo e solo enviados ao motor no índice da pasta, mover (avisos, bloco, pasta recolhida, retorno, `joinGroup`, `leaveGroup`, sidechain), apagar e duplicar, e widgets (menu, diálogo, `Mover a faixa?`, barra `Grupo`, celular 400 px). Nenhum teste ouve áudio nem roda o motor real `(testado só por testes automáticos)`.

**Armadilhas das pastas.**
- **Resolvidas em `ffa76ba` (fase 16 A), o que esta lista trazia:**
  - `setOutput` deixava a filha "na pasta" (recuada, contada) com a saída em outro lugar. Agora `setOutput` usa `folderLeftByOutput(track, busId)` e, se a saída nova não é a própria pasta, chama `takeOutOfFolder` (a faixa desce para depois do bloco, `groupId = null`) no mesmo `edit`; o botão de saída do mixer (`_OutputButton._choose`, inclusive `Novo barramento`) pergunta antes por `confirmGroupRoute` (`Tirar "Nome" da pasta?`). `leaveGroup` reaproveita `takeOutOfFolder`.
  - `bounceTrack` (congelar) não copiava `groupId` e a faixa `(áudio)` caía fora da pasta, quebrando a contiguidade. Agora copia `groupId` de `src` (a nova entra em `i + 1`, dentro do bloco).
  - `joinGroup`, `leaveGroup` e `groupTracks` trocavam a saída sem aviso. Agora `joinGroupNotes`, `leaveGroupNotes` e `groupNotes` listam a troca e `confirmGroupRoute` (`structure_menu.dart`) pergunta (títulos `Mover "Nome" para a pasta "Pasta"?`, `Tirar "Nome" da pasta?`, `Agrupar as faixas?`).
  - O texto de `Mover a faixa?` era o de barramento mesmo quando só havia troca de pasta. Agora `routesBrokenByMove(from, to, groups: false)` traz só as rotas de barramento e `groupNotesForMove` só as de pasta; `moveTrackAsking` monta o texto com os parágrafos que existem.
  - `remapDocIds` não reapontava `group_id`. Agora `t.groupId = trackIds[t.groupId]` (pasta que não está no arquivo vira `null`).
  - `ungroup` mantinha o barramento mas mandava as filhas ao master, deixando o efeito sem entrada. Agora `ungroupKeepsRoutes(folder)` (efeitos, automação ou envios) mantém `output` das filhas na pasta; só receber de outras faixas mantém o barramento e manda as filhas ao master. Não havia caminho para apagar a pasta: `confirmDeleteGroup` (`removeTrack`).
- O motor não sabe de pasta: mudar o significado de `isGroup` não exige recompilar `.wasm` nem `.so`.

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
- **Normalização** (`normalizeTempoPoints`, `normalizeMeterChanges`, chamadas no construtor e em `fromJson`): descarta não finitos, batida negativa vira 0, bpm preso a 20–999, na mesma batida (ou no mesmo compasso) o último vale, ordena, garante o ponto da batida 0 (ou o compasso 1) e limita a `maxTempoPoints = 4096` pontos e `maxMeterChanges = 1024` mudanças (os de batida ou compasso menores ficam; os mesmos valores de `MAX_TEMPO_POINTS`/`MAX_METER_POINTS` do motor, com `minBpm`/`maxBpm` 20 e 999 e `minBpmInt`/`maxBpmInt` para o espelho do servidor, tudo em `tempo_map.dart`; desde `dd4ef07`, antes eram 512 e 256). Passar do limite avisa em `error` (`tempoPointsFullMessage` = `O mapa de andamento chegou ao limite de 4096 pontos.`, `meterChangesFullMessage` = `O mapa de compassos chegou ao limite: o compasso inicial mais 1023 mudanças.`; até a fase 15 dizia `... de 1024 mudanças.`, mas o limite conta o compasso inicial como uma das 1024 entradas: texto corrigido em `ffa76ba`). Um mapa que sobra com **um ponto só** vira `[]` ("sem mapa"); para o compasso, um só `n/4`. Um único compasso `6/8` ou `7/8` **não** é "sem mapa" (`MeterMap.isSingle` exige `den == 4`) e é gravado.
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
| `setTempo(bpm, beatsPerBar, {keepMeter = false})` | `bpm` é `num` (com decimais, limitado a `minBpm`..`maxBpm`); mantém o ponto 0 do mapa igual ao `bpm` novo. Sem `keepMeter`, grava `beatsPerBar` e iguala o primeiro compasso do mapa a `MeterChange(1, beatsPerBar, 4)` **sempre**, mesmo que `beatsPerBar` seja igual ao guardado (fase 14, `725ce0f`). Até a fase 13 o app só trocava o compasso quando `n` diferia de `doc.beatsPerBar` (`changed`), que num `6/8` vale 3 e num `7/8` vale 4, então pedir `3/4` num `6/8` (ou `4/4` num `7/8`) não mudava nada. Com `keepMeter: true` o compasso inicial (`6/8`, `7/8`…) e o `beatsPerBar` ficam como estão e só o andamento muda. Na `_TempoDialog` o item `n/d (atual)` tem o valor `0`; `_editTempo` (`transport_bar.dart`) chama `c.setTempo(r.$1, r.$2 == 0 ? c.doc.beatsPerBar : r.$2, keepMeter: r.$2 == 0)`. Teste: `fase14b_test.dart`, grupo `tempos por compasso` `(testado só por testes automáticos)` |
| `tempoLaneVisible`, `toggleTempoLane()` | a faixa `Andamento` à mostra: `_tempoLane ?? !doc.tempo.isSingle` (automática com mapa, manual depois do primeiro clique; **não** vai no documento) |
| `snapBeat(b)` | com `Snap.bar` e mapa de compassos, encaixa em `meter.nearestBarStart(b)` |
| `secondsAt`, `bpmAt` | atalhos para o relógio em segundos e o BPM vigente |

**Do documento ao motor.** `_tempoMapCalls(cache)` (chamado por `_docCalls`) compara a assinatura (`jsonEncode` dos pontos) com `_SyncCache.tempoSig`/`meterSig` e só então emite `tempo_clear` + um `tempo_point` por ponto e `meter_clear` + um `meter_point` por mudança; volta ao mapa simples manda o `tempo_clear` seco. Vão logo depois do `tempo`. Ver a tabela em "Como cada mudança vira chamadas ao motor" e [02-pontes-web-e-android.md](02-pontes-web-e-android.md#chamadas-do-mapa-de-andamento-e-de-compassos-tempo_clear-tempo_point-meter_clear-meter_point).

**Consumidores no app** (tudo que antes multiplicava `beat * 60 / bpm` passa pelo mapa): relógio da barra (`_Position`, `secondsAt`), régua e grade (`_RulerPainter`, `_GridPainter` por `MeterMap`; régua em mm:ss por `secondsAt` e `beatAt`), etiqueta do mouse na régua, clipes (largura por `clipBeats`, arrastar e aparar por `sourceTempoAt`, cortar e sobrepor por `sourceSeconds`), estimativa de posição durante o play (`_estimatedBeat`), contagem e passadas da gravação (`_Recording.tempo`, `framesBetween`, `recordingPasses(tempo:)`, `_countFrames`, compasso da contagem por `meter.barBeatsAt`), exportação e congelar (`secondsAt`), render (`renderTempoMap`, `renderFrames`, `prepareRenderCalls` no Dart e o `tempoMapOf` do `render-worker.js`), `DurationLabel`, dialogo de exportação (`_bars`, `_spanSeconds`), e o botão de andamento (`_TempoButton`: `bpmAt` no cursor, `↗` quando o trecho é uma rampa que sobe e `↘` quando desce, sem seta se os dois BPM são iguais). O áudio → MIDI usa o BPM vigente na batida do clipe (`notesForClip(r, audio, doc.bpmAt(audio.start))`).

**Warp.** Decisão: `WarpSpec.of(c, doc.bpm)` (o inicial) em toda parte (`setClipWarp`, `_clipSound`, congelar). O clipe esticado toca a velocidade constante; se atravessa uma mudança de andamento, sai da grade. O `warp_dialog.dart` avisa: `O projeto tem mudanças de andamento: o warp estica o áudio para o andamento INICIAL (X BPM) e ele toca em velocidade constante, sem acompanhar as mudanças.` Mudar só outros pontos do mapa não refaz o warp.

**Importador de MIDI.** Desde `020003f` (fase 11) o `.mid` leva e traz o mapa: `applyImportedTempo` (`controller.dart:2569`) escreve `d.bpm`/`d.tempoMap` e `d.beatsPerBar`/`d.meterMap` **direto no documento** (dentro do `edit` da importação, um só passo do desfazer), com as listas de `importedTempo`/`importedMeter`; não chama `setTempoMap`/`setMeterMap` (que existiam como ganchos, teste `ganchos do importador de MIDI: setTempoMap e setMeterMap`, e continuam servindo à faixa `Andamento`). O espelho para o servidor e o motor sai por `_mirrorTempo()` e pela sincronização normal (`_tempoMapCalls`). Formatos e limites em "Arquivo MIDI padrão". `(lido do código; testado só por testes automáticos)`

**Compassos pelo mapa (desde `dd4ef07`; antes tudo isto usava `doc.beatsPerBar`, o compasso inicial).** O piano roll (`_barsIn` em `piano_roll_paint.dart` desenha compassos e números da grade e da régua a partir de `MeterMap`; sem mapa, `n/4` contado do começo do clipe como a grade de encaixe; `_barLen` e `_ceilBar` em `piano_roll_input.dart` servem a `Shift`+← →, colar, duplicar, o espaço depois do fim e as ferramentas que crescem o clipe; `_formatSpan(..., meter:, from:)`), `createMidiClip` sem `length` (`meter.barBeatsAt(start)`), o arredondamento em compassos de notas gravadas (`_placeRecordedNotes` com `floorBarStart`/`ceilBarStart`), `fitRange`, o tamanho mínimo do minimapa (`meter.barStart(5)`), o passo `Compasso` (`snapBeat` e `_gridBeats(c, at)` com `barBeatsAt`) e a conta de compassos do tooltip de `DurationLabel` (`meter.barOf(contentEnd)`). `MeterMap` ganhou `floorBarStart`, `ceilBarStart` e `spanBars`. Continua com `beatsPerBar` fixo o `Z/4` da pergunta de andamento do `.mid` (`askUseFileTempo`, `midi_file_ui.dart`: um projeto em `6/8` aparece como `3/4`).

### Curvas de fade e crossfade automático (`FadeShape`, `AutoFade`)

Fase 14 D (`991c05d`). Arquivos: `daw/model.dart` (`FadeShape`, `AutoFade`, campos do `AudioClip`), `daw/controller.dart` (`_docCalls`, `placeOnTop`, `_crossing`, `_tryCrossfade`, `reconcileAutoFades`, `crossfadeOverlaps`, `setFadeShapes`), `daw/timeline.dart` (menu do clipe, `_FadePainter`, `_DragEdit._endDrag`), `audio/engine_ffi.dart` e `web/engine/render-worker.js` (aparo do render). Teste: `app/test/fade_test.dart`.

**Modelo.**
- `enum FadeShape { linear, equalPower, exponential, sCurve }` com `label` (`Suave (padrão)` para o valor `linear`, `Potência constante`, `Exponencial`, `S (seno cosseno)`; o rótulo era `Linear` até `ffa76ba`, fase 16: só o texto mudou, o nome do valor do enum, o código 0 e a curva não), na ordem dos códigos do motor (o `index` é o valor de `clip_fade_shape`; tipo novo só entra no fim). `FadeShape.fromCode(Object?)` devolve `linear` para nulo, não inteiro ou fora de 0..3. `gain(x)` é o espelho em Dart de `fade_curve` do motor (`x²`, `sin`, `(e^(4x) − 1)/(e^4 − 1)`, `(1 − cos πx)/2`, com `x` limitado a 0..1); serve ao desenho da rampa em `_FadePainter`, e o teste compara os quatro com o motor nos quartos.
- `AudioClip.fadeInShape`/`fadeOutShape` (padrão `linear`) e `autoFadeIn`/`autoFadeOut` (`AutoFade?`, nulo = fade do usuário). `AutoFade(prevLength, prevShape)` guarda o que o fade era **antes** do crossfade (tamanho em segundos do arquivo e curva).
- **JSON.** `fade_in_shape`, `fade_out_shape` (inteiro; omitidos quando `linear`/0), `auto_fade_in`, `auto_fade_out` (`{"len": segundos, "shape": inteiro}`; omitidos quando nulos). `fromJson` lê os quatro com padrão `linear`/`null`. **Compatibilidade:** um documento anterior à fase 14 abre com `linear` nos dois lados e sem marcas, e volta a `toJson` sem nenhum campo novo (o teste confere que as quatro chaves não aparecem); ou seja, projeto que nunca escolheu curva tem o JSON byte a byte como antes, e o som é o mesmo porque o padrão 0 é o `x²` de sempre. Um app **anterior** à fase 14 ignora os campos ao ler e os perde ao gravar (mesma armadilha do item 4, abaixo).

**Motor.** `_docCalls` emite `['clip_fade_shape', fadeInShape.index, fadeOutShape.index]` logo depois do `['clip_add', …]` do clipe, só se alguma das duas é diferente de `linear`. As marcas `auto_*` nunca vão ao motor. Ver [02](02-pontes-web-e-android.md#chamada-de-curva-de-fade-clip_fade_shape).

**Menu e desenho (`timeline.dart`).** `_menu` do `_ClipViewState` monta, entre dois `PopupMenuDivider`, um `_shapeItem` por curva e por lado (fase 16; era `_checkItem`), com valor `fin:<índice>` e `fout:<índice>`, rótulo `Fade de entrada: <label>` / `Fade de saída: <label>`, a marca de visto no da curva atual e um `Tooltip` com `fadeShapeHint(shape)`. Antes das curvas vêm `_menuItem('fadein_len', …, 'Fade de entrada…')` e `_menuItem('fadeout_len', …, 'Fade de saída…')` (abrem `showFadeLengthDialog`, `fade_length_dialog.dart`), e depois delas `_menuItem('crossfade', …, 'Crossfade neste clipe')` e `_menuItem('crossfade_all', …, 'Crossfade em toda a faixa')`. Os valores chamam `setFadeShapes`, `setFadeLength` e `crossfadeOverlaps(id, wholeTrack: …)`. `_FadePainter` desenha, para cada fade > 0, um sombreado (o que o fade tira) e uma linha de até 48 segmentos (`max(4, min(48, largura/3))`, ganho `shape.gain(i/n)` como altura); a saída é a mesma curva espelhada. As alças (círculos de 3 px) continuam em `max(5, fadeIn)` e `min(largura − 5, largura − fadeOut)`. Arrastar uma alça (`_Grab.fadeIn`/`fadeOut`) zera a marca `auto*` desse lado e liga `_fadeOnly`, que faz o `_endDrag` **não** chamar `placeOnTop` (sem reacomodar clipes nem crossfade).

**Controlador.**

| Método | O que faz |
|---|---|
| `setFadeShapes(id, {fadeIn, fadeOut})` | Troca a curva do lado pedido (`edit`, desfazível; sai sem fazer nada se nada muda) e zera a marca `auto*` desse lado: escolher a curva é decisão do usuário e o fade deixa de ser revertido |
| `placeOnTop(id, {crossfade = false})` | O clipe fica por cima dos outros da faixa (aparo de sempre). Com `crossfade`, antes de aparar cada clipe `o` que ele cobre, tenta `_tryCrossfade(o, top, …)`; se der certo, `o` **não** é aparado. Ao fim de qualquer chamada de áudio roda `reconcileAutoFades()`. O único chamador com `crossfade: true` é `_DragEdit._endDrag` (fim de arrasto de mover ou aparar); duplicar, gravar por cima e os demais usam o padrão `false` |
| `_crossing(early, late)` | Sobreposição em batidas se `late` **começa dentro** de `early` (`late.start > early.start` e `< fim de early`) e **termina depois** dele; senão nulo (contido, mesmo começo ou sem contato). Tolerância `_fadeEps = 1e-9` |
| `_tryCrossfade(o, top, {oEnd, topEnd, force = false})` | Ordena o par por início (`early`, `late`), exige `_crossing`, e (sem `force`) que a sobreposição seja ≤ metade do **menor** dos dois em batidas (`+ _fadeEps`) e que não haja fade do usuário no lado do cruzamento (recusa se `early.fadeOut > 0` com `early.autoFadeOut == null`, ou `late.fadeIn > 0` com `late.autoFadeIn == null`); com ou sem `force`, exige que `early.fadeIn + outSecs ≤ early.length` e `inSecs + late.fadeOut ≤ late.length`. `outSecs`/`inSecs` são `doc.sourceSeconds(clip, late.start, late.start + sobreposição)` (segundos do arquivo, com warp e mapa de andamento). Se passa: `autoFadeOut ??= AutoFade(fadeOut, fadeOutShape)`, `fadeOut = outSecs`, `fadeOutShape = equalPower`, e o espelho em `late` (`autoFadeIn`, `fadeIn = inSecs`, `equalPower`). Reaproveita a marca já existente (o "antes" é o primeiro, não o de um crossfade anterior) |
| `reconcileAutoFades()` | Para **todos** os clipes de **todas** as faixas com `autoFadeIn`/`autoFadeOut`: acha a maior travessia de borda com outro clipe da faixa; se existe e o fade cabe (`secs + fade do outro lado ≤ length`), `fade = secs`; senão devolve `fade = min(prevLength, max(0, length − fade do outro lado))`, a curva `prevShape` e zera a marca. Fade sem marca nunca é tocado. Não faz checkpoint |
| `crossfadeOverlaps(id, {wholeTrack = false})` | Comando do menu: junta os pares `(x, y)` da faixa do clipe com `_crossing(x, y) != null` (só os que têm o clipe clicado, ou todos com `wholeTrack`), faz `checkpoint()` e `mutate` chamando `_tryCrossfade(..., force: true)` em cada par (sem o teto de metade e por cima dos fades do usuário); devolve quantos viraram crossfade e escreve o resultado em `notice` (`1 crossfade aplicado.`, `N crossfades aplicados.`, `(M não coube nos fades dos clipes)`, ou o texto de "não há crossfade a aplicar" quando não há par). Um passo do desfazer |
| `setFadeLength(id, {fadeIn, fadeOut})` | Tamanho dos fades em segundos do arquivo (`FadeLengthDialog` converte ms ou batidas por `sourceTempoAt / 60`): cada lado é limitado a `length − fade do outro lado`, não finito vira 0, sem mudança sai sem checkpoint; `edit` desfazível e zera a marca `auto*` do lado mexido |
| `notice` / `clearNotice()` | Aviso informativo de uma ação que terminou (não é erro): `project_screen.dart` mostra `InlineNotice(c.notice!, error: false, onClose: c.clearNotice)` acima do de erro, dentro de um `_AutoDismiss` (chave `ValueKey(c.notice)`, relógio de `DawController.noticeDuration` = 6 s, que chama `clearNotice`): o aviso some sozinho (desde a fase 18 A; antes ficava até ser dispensado), um texto novo reinicia o relógio e o controlador não guarda `Timer` nenhum `(testado só por testes automáticos)` |

O desfazer do crossfade automático é o do arrasto inteiro: `_DragEdit.change` faz o `checkpoint` na primeira mudança e o `_endDrag` roda o `placeOnTop(..., crossfade: true)` dentro de um `mutate` (sem checkpoint novo), então mover o clipe e o crossfade que sai dele são **um** `Ctrl+Z`.

**Testes** (`app/test/fade_test.dart`, `flutter test test/fade_test.dart`; só automáticos `(testado só por testes automáticos)`): grupo `curvas` (valores nos quartos iguais aos do motor e pontas exatas; os códigos são os do motor e código estranho vale linear; documento sem curvas abre linear e volta igual, com curvas e marcas faz a viagem); grupo `crossfade automático (120 BPM)` (travessia de borda pela cauda com fade de 1 s e `equalPower`; pela cabeça; sem a opção, sobreposição demais de 3 s em clipes de 4 s e clipe contido apara como sempre; fade do usuário bloqueia; a sobreposição some e os fades voltam ao que eram, só eles, inclusive a curva; a sobreposição muda de tamanho e o fade acompanha, e fade mexido à mão perde a marca; o comando do menu com três clipes, dois cruzamentos e o desfazer devolve o JSON idêntico); grupo `motor` (o sync manda `clip_fade_shape` logo depois do `clip_add`, só para curva fora do padrão, com o `FakeEngine`; e o render aparado leva a curva do clipe que fica e descarta a do que sai, por `prepareRenderCalls`). Não há teste de widget do menu, do desenho nem do gesto de soltar o arrasto: o caminho `_endDrag` → `placeOnTop(crossfade: true)` e o menu `(lido do código; não visto no navegador)`.

**Decisões e por quê.**
- *`linear` = `x²` como padrão:* o motor já fazia `(t/fade)²`; manter o valor do enum e o código 0 nesse envelope faz projeto antigo soar igual e o JSON não mudar. O rótulo `Linear` enganava (a curva não é reta em amplitude): a fase 16 trocou só o texto para `Suave (padrão)` e pôs a explicação no tooltip do item.
- *Chamada relativa ao último clipe:* o render offline descarta clipes depois do fim; um índice deslocaria as curvas dos que sobram.
- *Marca com o "antes" no clipe, não uma tabela de crossfades:* o crossfade se refaz sozinho quando o clipe se move, sem estado fora do documento; a marca também viaja pelo JSON e pela sincronização.
- *Teto de metade do menor clipe:* impede que o crossfade engula um clipe pequeno; acima disso o aparo de sempre vale.
- *Usuário manda:* fade posto à mão (tamanho ou curva) bloqueia o crossfade automático e perde a marca; só o comando do menu (`force`) passa por cima.

**Armadilhas conhecidas (lidas do código, não vistas no navegador).**
- **Resolvidas em `ffa76ba` (fase 16 A):** `deleteSelected` agora chama `reconcileAutoFades()` dentro do `edit`, e o outro clipe de um crossfade volta ao fade de antes na hora; `splitAtPlayhead` e o aparo de `placeOnTop` zeram a marca `auto*` do lado cujo fade viraram 0 (`autoFadeIn = null` no clipe da direita e `autoFadeOut = null` no da esquerda), então uma revisão seguinte não "devolve" o `prevLength` às metades; `crossfadeOverlaps` só considera os pares do clipe clicado (o item `Crossfade em toda a faixa` mantém o comportamento antigo) e avisa o resultado por `notice`, inclusive quando é 0.
- Depois de um crossfade a faixa tem, de propósito, dois clipes de áudio sobrepostos, que o motor soma. Código novo que suponha "no máximo um clipe de áudio por instante na faixa" precisa levar isso em conta.

### Duas armadilhas de compatibilidade do esquema

1. **Tipos de faixa novos em app velho.** `TrackKind.parse` devolve `audio` para um `kind` que a versão não conhece. Um app antigo que abre um projeto com faixa `fm`/`wavetable` a lê como `audio`, e ao salvar **regrava `audio`**, perdendo o tipo (aconteceu com um APK velho instalado por engano em 30/09/2026, segundo as notas de processo). `AutoKind.byName` é o oposto: lança, e o documento não abre.
2. **Sidechain é índice de faixa, não id.** O parâmetro `10` do compressor e o `6` do gate guardam o **índice** da faixa-chave (−1 = desligado, faixa `-1..63` na tabela). Por isso `removeTrack`, `duplicateTrack`, `moveTrack` e o congelar reescrevem esses valores (`_remapSidechains` em `controller.dart`). Editar o documento por fora (ou mesclar dois documentos) exige o mesmo cuidado.
3. **Mapas em app velho.** `tempo_map` e `meter_map` só existem a partir da fase 10: um app anterior os ignora ao ler e os perde ao gravar (o projeto vira um andamento e um compasso só, o `bpm` e o `beats_per_bar` da raiz). Ver "Mapa de andamento e de compassos no documento".
4. **Curvas de fade em app velho (fase 14 D).** `fade_in_shape`, `fade_out_shape`, `auto_fade_in` e `auto_fade_out` só existem a partir de `991c05d`: um app anterior os ignora ao ler e os perde ao gravar (os fades voltam a `x²` e o crossfade perde a marca de "automático", então o fade que ele gerou passa a ser tratado como do usuário). Ver "Curvas de fade e crossfade automático".

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
| clipes (`:1711`) | seleção, `moveClipToTrack`, `deleteSelected`, `placeOnTop` (o clipe novo recorta o que cobre; com `crossfade: true`, ao soltar um arrasto, faz crossfade em travessia de borda), `_crossing`, `_tryCrossfade`, `reconcileAutoFades`, `crossfadeOverlaps`, `setFadeShapes` (ver [Curvas de fade e crossfade automático](#curvas-de-fade-e-crossfade-automático-fadeshape-autofade)), `duplicateSelected`, `splitAtPlayhead` |
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
2. Lê `doc:<id>` do `LocalStore`. Se existe, `DawDoc.fromJson`. Senão `_fromTemplate()`: se há `template:<id>` (modelo escolhido ao criar; apagado na hora), `ProjectTemplate.build`; senão `_fresh()` (uma faixa `Áudio 1`, `loop_end = project.beatsPerBar * 4 * 4 / project.beatUnit`, quatro compassos do compasso exato; desde `52d25c1` o `beatsPerBar` do documento é o do projeto convertido em semínimas por `_quarterBeatsPerBar` e o `meterMap` leva o compasso exato quando a figura não é 4; antes um 6/8 do cadastro abria como 6/4 e o espelho tentava mudá-lo). O modelo `Vazio` da tela de projetos **não** grava `template:<id>`, então cai em `_fresh()`.
3. (Não sobrescreve mais `doc.bpm` e `doc.beatsPerBar` com os do projeto: o documento local vale; só um documento novo, de `_fromTemplate`/`_fresh`, parte dos do projeto.)
4. Carrega cada áudio de `doc.samples` (`sample:<hash>` → `_engine.decode` → `_register`, que atribui um id inteiro ao hash em `_sampleIds`, manda ao motor e desenha a forma de onda). Áudio ausente do aparelho entra em `missing`.
5. Sincronização: `sync.start(localExisted: ...)`. **Espera de até 25 s** (o `started.timeout(const Duration(seconds: 25))` em `DawController.open`) quando `saved is! String && !_templated && _canSync()`, isto é, projeto sem documento local, sem modelo e com sessão: nesse caso o projeto pode existir só no servidor (criado em outro aparelho) e o spinner só termina depois da primeira conversa (documento + áudios). Ver [12 Sincronização](12-sincronizacao.md). Nos demais casos a sincronização segue em segundo plano. Nesse caso `open` guarda também o documento vazio (`_blankJson`): o `_applyRemote` que o troca pelo do servidor não põe o `remoteNotice` (`Projeto atualizado de outro aparelho…`), que só sai quando havia documento local que mudou (resolvido em `1180152`). Se o projeto está gravando, tocando ou com um gesto em andamento, o pull da abertura não troca e tenta de novo 2 s depois (ver [12 Sincronização](12-sincronizacao.md)).
6. `ready = true`, primeiro `_sync()` (manda o documento inteiro ao motor), `_lastSaved` = documento atual. Faixa de áudio que estava armada ou monitorando reabre a entrada (`_restoreInput`).

### `edit()` e o desfazer (`DawController.edit`, `checkpoint`, `mutate`, `undo`/`redo` e `_travel` em `controller.dart`)

```
edit(fn, undoable: true)
  ├─ checkpoint(label)   ← empilha HistoryEntry(jsonEncode(doc.toJson()), label, hora) em _undo (máx. 200), limpa _redo
  └─ mutate(fn)
        ├─ fn(doc)
        ├─ _prune()          esquece seleção/editor/rack que sumiram
        ├─ _sync()           diferença → chamadas ao motor
        ├─ _scheduleSave()   debounce de 400 ms → _save()
        └─ notifyListeners()
```

- **Desde a fase 18 C cada passo é um `HistoryEntry {json, label, time}`** (`history.dart`), `editAs(label, fn)` dá o nome, `_travel(from, to, count:)` anda vários passos de uma vez e a parte de "adotar o JSON" virou `_adopt` (também usada pela restauração de versão). Detalhes e armadilhas: [Histórico com nomes e versões nomeadas](#histórico-com-nomes-e-versões-nomeadas-fase-18-c).
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
| modulação | `mod_clear`, `mod_source track i kind rate sync depth phase bipolar shape attack release value`, `mod_dest track i j code slot id amount min max scale` | a modulação inteira, **só quando a lista muda** (`_SyncCache.mod`); num projeto que nunca teve modulação nada sai, e ao apagar o último modulador sai um `mod_clear` sozinho |
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

- conta um compasso antes do cursor (`count_in`), com o metrônomo ligado só na contagem (e, com `pre_roll`, também durante o pré-roll, como o fluxo da seção [Punch, pré-roll, tap tempo e opções do metrônomo](#punch-pré-roll-tap-tempo-e-opções-do-metrônomo-fase-17-c) descreve); onde não cabe (primeiro compasso, ou o fim do loop dentro da contagem) a contagem toca numa região vazia bem depois do fim de tudo (`zone`) e o cursor exibido anda o compasso anterior;
- o motor liga a captura (`capture`) e o Dart junta os blocos de entrada (`_onRecordBlock`) com a batida exata do primeiro quadro (`recordBeat`);
- `_finishRecording` espera a latência da entrada (com áudio e `latency > 0`, desde `ffa76ba` ele manda antes `_releaseControls()`: pedal, bend e roda voltam ao repouso já, e não só quando a espera acaba, porque o transporte ainda anda nesses ms), para o transporte (o `stopTransport` local manda `['stop']` e `..._releaseControls()` juntos: pedal solto, bend e roda ao centro, também no cancelamento durante a contagem; fase 14), desliga a captura (que devolve as notas tocadas: `onCaptureEnd`) e chama `_commitRecording`;
- `_commitRecording` transforma o áudio em WAV 32f, calcula o sha-256, guarda `sample:<hash>`, cria `AudioClip`s (em loop, cada passada é uma tomada e a ativa é a última passada completa, `_planAudio`), coloca as notas (`_placeRecordedNotes`, overdub no clipe sob o cursor ou clipe novo) e faz tudo **num passo do desfazer**. A entrada estéreo que é mono de fato vira um canal só (`_inputChannels`). Menos de 50 ms de áudio útil não vira clipe.

**Latência da gravação (fase 13).** `_beginRecording` (`controller.dart:3957`) lê uma vez, ao começar, `_outputLatency` (`:3661`) = `_engine.latency` (aparelho, s) + `_engine.engineLatency` (motor, s: PDC, cadeia do master, limitador de segurança; ver [02](02-pontes-web-e-android.md)) e guarda no `_Recording`: `latency` = `_outputLatency` + `_inputLatency` + `rec_latency_ms / 1000`, só se a gravação tem áudio (`audio`), que vira `skip` (quadros descartados do começo do que a entrada mandou; negativo acrescenta silêncio) e a espera do `_finishRecording` (`latency` + 20 ms); e `midiLatency` = só `_outputLatency`, sem a entrada nem o `rec_latency_ms`. As notas e os CCs voltam por `_Recording.shiftBeat` (`:405`), que subtrai `midiLatency` em segundos pelo mapa de andamento da gravação e trava em 0; em `_recordedNotes` a nota também tem um piso (`min(início da gravação, início do loop se o loop está ligado)`: uma nota que já estava antes dele não recua mais), e em `_recordedControls` o ponto de CC tem o mesmo piso (`beat = max(shiftBeat(início), min(início, piso))` só com `midiLatency > 0`; fase 15, `1d90812`: antes só passava por `shiftBeat`, e um CC tocado nos primeiros ms com contagem ligada recuava para antes do começo e o filtro da contagem, que roda depois, o jogava fora; o piso de 1/64 de batida é só das notas). `engineLatency` vale 0 num motor sem a chamada (`engine_web.dart` e `engine_ffi.dart` engolem a ausência), então o comportamento antigo (só o aparelho) é o fallback. `monitorLatency` = `_outputLatency` + entrada é a ida e volta da faixa monitorada; a janela `Configurações` (`settings_dialog.dart`) a mostra em `Ida e volta do monitoramento: N ms` (fase 15; sem `inputOpen` o texto avisa que a entrada só é medida com o microfone aberto) e o texto de ajuda de `Compensação de latência` cita a latência do motor e a do navegador ou sistema para entrada e saída. Testes: `recording_test.dart`, grupo `latência do motor na gravação`, com o `FakeEngine.engineLatency` (ver [03](03-build-teste-e-depuracao.md)).

Sem a fase 13 a latência descartada era a do contexto de áudio + a da entrada + `rec_latency_ms` (o MIDI não tinha compensação). Parar durante a contagem cancela sem gravar nada.

**Com mapa de andamento.** `_Recording` guarda o `TempoMap` que valia quando a gravação começou (`tempo`, um mapa constante quando não há mapa) e converte batidas em quadros por ele (`framesBetween`); a contagem dura o compasso do cursor (`meter.barBeatsAt(start)`) e seus quadros vêm de `_countFrames` (segundos entre as batidas pelo mapa); `recordingPasses(..., tempo:)` acha as voltas do loop no quadro que o motor conta; `recordedBeats` estima as batidas gravadas pelo relógio pelo mapa (a contagem, no andamento do começo). Mudar o andamento ou o compasso gravando é bloqueado (`_blockedByRecording`), porque o mapa da gravação é fixo do começo ao fim.

### Punch, pré-roll, tap tempo e opções do metrônomo (fase 17 C)

> Para quem mexe na gravação com punch e pré-roll, no tap tempo e no estilo do metrônomo. Manual: [Gravação](../manual/03c-gravacao.md#punch-pré-roll-e-metrônomo-fase-17), [Transporte](../manual/02-transporte.md) e [Configurações](../manual/09-configuracoes-atalhos-android.md). Commit `8a9ea40` (app) sobre `54bd4da` (motor); integrado em `f41fe00`. O motor não conhece punch nem pré-roll: só recebeu a chamada `metronome_style` ([02](02-pontes-web-e-android.md#chamada-de-estilo-do-metrônomo-metronome_style)).

**Peças.**

| Arquivo | Papel |
|---|---|
| `daw/model.dart` | `MetronomeTimbre`, `MetronomeSubdivision`, `MetronomeMode` (o índice do timbre e da subdivisão é o código do motor), `MetronomeOptions` (`fromJson`, `toJson`, `isDefault`, `copy`, `styleCall`) e, em `DawDoc`, `metronomeOptions`, `preRollBars`, `maxPreRollBars` (4), `punchIn`/`punchOut`/`punchOn`, `punchRegion` e `punchActive`, mais `_punchOf` (leitura da região do JSON) |
| `daw/controller.dart` | `setMetronomeOptions`, `setPreRoll`, `togglePunch`, `setPunchRegion`, `tapTempo`/`commitTap`/`tapBpm`/`tapCommitDelay`/`debugTapClock`; `_metronomeWanted`, `_metronomeStyleCalls` (`_SyncCache.metroSig`); em `_beginRecording`, `_preRollBeats` e `_punchWraps`; em `_Recording`, `preBeats` e `punch`; no fim da gravação, `_planAudio` (= `_cropToPunch` de `_planAudioFull`), `punchFade`, `_punchCrossfade`, o corte do punch em `_recordedNotes`, `_recordedControls` e `_placeRecordedNotes` |
| `daw/tap_tempo.dart` | `TapTempo`: a média das últimas batidas, sem relógio próprio (o tempo vem de fora, em segundos) |
| `daw/timeline.dart` | `_PunchHandles`/`_PunchHandle` (as pontas `IN` e `OUT` na régua), `_PunchBand` e `_PunchBandPainter` (a faixa sobre as raias), e a faixa da região no `_RulerPainter` |
| `daw/transport_bar.dart` | o `_Toggle` do punch (ícone `Icons.compare_arrows`), o `_RecordMenu` (`countIn`, `punch`, `settings`) e o `PopupMenuButton<Object>` que também devolve um `int` (o pré-roll escolhido), o tooltip do gravar com o pré-roll e o punch, o `Tap tempo` do `_TempoDialog` e o `Tap · N BPM` do `_TempoButton` (`ValueListenableBuilder` sobre `c.tapBpm`) |
| `daw/settings_dialog.dart` | `Pré-roll`, `Punch in/out`, `Usar a região do loop` (seção `GRAVAÇÃO`), `_punchText`, `_MetronomeSection` (seção `METRÔNOMO`) e `OptionSlider` (só entrega o valor ao soltar) |
| `daw/keymap.dart`, `screens/project_screen.dart` | ações `transport.punch` (`P`) e `transport.tap` (`T`) no catálogo (56 ações) e o `_actionFor` que as liga a `togglePunch` e `tapTempo` |
| `web/engine/worklet.js` | `metronome_style` em `OPTIONAL_CALLS` |

**Esquema JSON (versão 1; todos opcionais, só gravados quando fogem do padrão).**

| Campo | Tipo | Padrão (omitido) | Leitura e escrita |
|---|---|---|---|
| `metronome_options` | objeto | ausente | Não é objeto: tudo no padrão. Escrita: só se `!isDefault`, e só as chaves abaixo que diferem do padrão |
| `metronome_options.timbre` | texto: `click`, `wood`, `beep`, `cowbell`, `hihat` (o `name` do enum) | `click` | Nome desconhecido: `click` |
| `metronome_options.subdivision` | texto: `beat`, `eighth`, `triplet`, `sixteenth`, `accentOnly` | `beat` | Nome desconhecido: `beat` |
| `metronome_options.mode` | texto: `always`, `recording` | `always` | Nome desconhecido: `always` |
| `metronome_options.volume` | número 0 a 1 | 0,5 | Não número ou não finito: 0,5; fora da faixa é limitado. É o `ganho` do `metronome` |
| `metronome_options.accent_level` | número 0 a 2 | 1,0 | Idem (padrão 1,0) |
| `metronome_options.accent_pitch` | número 0,5 a 4 | 1,6 | Idem (padrão 1,6) |
| `metronome_options.sub_level` | número 0 a 2 | 0,5 | Idem (padrão 0,5) |
| `pre_roll` | inteiro 0 a 4 | 0 | Limitado a 0 a `maxPreRollBars`; só escrito se maior que 0 |
| `punch_in`, `punch_out` | números (batidas) | ausentes | Valem só os dois juntos, números finitos com `punch_in ≥ 0` e `punch_out > punch_in`; senão os dois somem e `punch_on` também. Escritos sempre que há região válida (`punchOut > punchIn + 1e-9`), **mesmo com o punch desligado** |
| `punch_on` | `true` | ausente | `true` só vale com região; só escrito quando ligado |

Um documento antigo abre com tudo no padrão e sai igual ao de antes (teste `documento antigo abre com os padrões e sai igual`). O documento vai inteiro na sincronização ([12](12-sincronizacao.md)), então os campos sobem com ele `(não conferido no servidor)`. `_travel` (desfazer e refazer) e `_applyRemote` (versão da nuvem) **preservam** `metronomeOptions`, `preRollBars`, `punchIn`, `punchOut` e `punchOn` do documento vivo, como preferência do aparelho (mesma regra de `metronome`, `count_in` e `rec_latency_ms`); mudar qualquer um deles usa `edit(..., undoable: false)`. Um app de antes da fase 17 abre o arquivo e ignora os campos novos; ao salvar, os perde `(lido do código; não testado)`.

**Fluxo de `_beginRecording` com punch e pré-roll (o que mudou).**
1. `punch = d.punchActive ? d.punchRegion : null`. O ponto de gravar `start` é o cursor (ou `_estimatedBeat()` se já toca). Com punch, transporte parado, `preRollBars > 0` e `start < punch.in`, `start = punch.in`.
2. Se `punch != null` e `start ≥ punch.out` e o loop não traz de volta (`_punchWraps`: loop ligado, `start < loopEnd` e a região inteira dentro dele): `error = 'O cursor está depois do punch out: nada seria gravado. Mova o cursor ou a região de punch.'` e a gravação não começa.
3. `preBeats = wasPlaying ? 0 : _preRollBeats(d, start, preRollBars)` (compassos para trás pelo `meter`, parando em 0); zerado se `d.loopEnd` cai dentro de `(start − preBeats, start]` com o loop ligado. `from = start − preBeats`; com contagem, `before = start − preBeats − bar`, e a contagem cabe se `before ≥ 0` e o fim do loop não cai nela; senão vai para a `zone` (região vazia longe do fim de tudo) com `_loopOverride = (true, start − preBeats, zone + bar)`.
4. `skip` (quadros do começo da entrada descartados) = contagem + pré-roll (na `zone`, os dois somados; fora dela, `start − from` em batidas) + latência. `_Recording` recebe `preBeats` e `punch`; `recordedBeats` desconta contagem e pré-roll.
5. `_metronomeWanted` = `(doc.metronome && (mode == always || recording)) || _countMetronome`. `_countMetronome` liga na contagem (com `count && !d.metronome`) e só cai em `_endPreRoll`, meio tempo antes de `start` (sem `zone`) ou na volta da `zone`: **por isso os cliques da contagem também soam durante o pré-roll fora da `zone`** (o teste `junto da contagem…` diz "metrônomo só na contagem" e só confere o começo).
6. Parar: `cancel = countingIn`. `countingIn` dura até `s.beat ≥ start` (sem `zone`), ou seja, cobre o pré-roll; cancelar não grava nada. No fim, `_backTo(r.start)`.
7. `_commitRecording`: `plans = _planAudio(r)`; `notes`/`ccs` de `_recordedNotes`/`_recordedControls`; se tudo vazio e `r.punch != null && (r.frames > 0 || r.midiIds.isNotEmpty)`, `error = 'Nada foi gravado dentro da região de punch: a gravação parou antes do punch in, ou nada foi tocado nela.'`. Senão `checkpoint()` e um `mutate` único (um passo do desfazer) que, por faixa de áudio, cria o `AudioClip` do plano (`fadeIn`/`fadeOut` com `FadeShape.equalPower` quando maiores que 0), chama `placeOnTop` e `_punchCrossfade`.

**O corte do punch no áudio (`_cropToPunch`).** Para cada plano (um por clipe; no loop, várias peças = tomadas): `s = max(plan.start, punch.in)`, `e = min(fim do plano, punch.out)`; se `e − s < 1e-6`, o plano some. Cada peça é recortada em quadros (`f0` a `f1`, pelo `TempoMap` da gravação); peça que não sobra (menos de 1 quadro) some; a `active` é a última peça **completa** (`pad == 0` e ao menos 98% dos quadros da região), senão a mesma de antes, senão a última. `fade = min(punchFade = 0,007 s, duração / 3)`; `fadeIn = fade` só se `s > plan.start + 1e-9` (cortou o começo) e `fadeOut = fade` só se `e < fim − 1e-9`. **Consequência:** com pré-roll (ou cursor dentro da região) `plan.start == punch.in` e a entrada da região fica sem fade e sem crossfade.

**`_punchCrossfade(t, clip)`.** Depois do `placeOnTop`, para cada outro clipe da faixa que seja "simples" (`!warp && !reverse && pitch == 0`): se `clip.fadeIn > 0` e o fim dele coincide com `clip.start` (1e-6 batida), `fadeOut == 0` e o sample tem `offset + length + 7 ms` de áudio, ele ganha `length += 7 ms`, `fadeOut = 7 ms`, `equalPower`; se `clip.fadeOut > 0` e ele começa em `fim do clip`, `fadeIn == 0` e `offset ≥ 7 ms`, ele passa a começar 7 ms antes (`start` recuado pelo `TempoMap`), com `offset −= 7 ms`, `length += 7 ms`, `fadeIn = 7 ms`, `equalPower`.

**O corte do punch nas notas.** Em `_recordedNotes`, depois do recuo pela latência e da regra da contagem: nota com `e ≤ punch.in + minLength` (1/64 de batida) ou `s ≥ punch.out` é descartada; senão `s = max(s, punch.in)` e `e = min(e, punch.out)`. Em `_recordedControls`, evento com `beat < punch.in − 1e-9` ou `> punch.out + 1e-9` é descartado. O que soou antes de `r.start` (contagem e pré-roll) é `counted` e cai fora (`lead`). Em `_placeRecordedNotes`, o clipe-alvo é o que cobre `anchor = max(r.start, punch.in)`; sem alvo, o clipe novo vai de `max(from, punch.in)` até `max(min(to, punch.out), maxEnd)`, em compassos inteiros, e `_mergeControls` usa `stop = min(r.stopBeat, punch.out)`. Notas que já estavam no clipe **não** são apagadas.

**Região do punch (`togglePunch`, `setPunchRegion`).** `togglePunch` é bloqueado gravando (`_blockedByRecording('ligar ou desligar o punch')`); ao ligar sem região usa a do loop **se `loopOn` e a largura passa de 0,01**, senão `from = snapBeat(max(0, cursor))` e `to = from + 2 × barBeatsAt(from)`. `setPunchRegion(a, b)` ignora gravando ou valor não finito, ordena as pontas, limita a 0 e, com largura menor que 0,01, apaga a região e desliga o punch; **não** liga o punch. As alças da régua chamam `setPunchRegion` a cada `onHorizontalDragUpdate` com `snapBeat` e o mínimo de 0,05 batida entre as pontas (`onHorizontalDrag*` é `null` gravando).

**Tap tempo (`tap_tempo.dart`, `controller.dart`, `_TempoDialog`).**
- `TapTempo` (constantes: `maxTaps` 8, `resetAfter` 2,5 s, `firstGap` 2,0 s, `minInterval` 0,15 s): `tap(agora)` ignora tempo não finito; gap negativo ou maior que `resetAfter` limpa a sequência; gap menor que `minInterval` devolve o BPM atual sem mexer; com uma batida só e gap maior que `firstGap`, ela é descartada; guarda no máximo 8. `bpm` = `60 ÷ ((última − primeira) ÷ (n − 1))`, limitado a `minBpm`/`maxBpm` (20 e 999) e arredondado a uma casa; `null` com menos de duas batidas.
- Controlador: `tapTempo()` (o atalho `T`) não faz nada gravando, ocupado ou descartado; guarda o BPM em `tapBpm` (`ValueNotifier<double?>`) e rearma um `Timer` de `tapCommitDelay` (1500 ms) quando há BPM. `commitTap()` (o timer, ou direto nos testes) cancela o timer, lê `_tap.bpm`, **zera** a sequência e `tapBpm`; se o valor difere de `doc.bpm`, chama `setTempo(v, doc.beatsPerBar, keepMeter: true)` (entra no desfazer; com mapa de andamento muda o ponto inicial) e mostra `notice = 'Andamento: N,N BPM (tap).'`. `debugTapClock` troca o relógio (`Stopwatch`) nos testes.
- O diálogo `Andamento e compasso` tem **outra** instância de `TapTempo` e o próprio `Stopwatch`: o botão `Tap tempo` só preenche o campo `BPM` (selecionado), sem timer e sem tocar no projeto até o `Salvar`. As duas sequências não se misturam.

**Estilo do metrônomo.** `setMetronomeOptions(change)` aplica `change` numa cópia, passa pelo `fromJson` (limites valem para quem chama direto), sai sem `edit` se o JSON não mudou e senão `edit(..., undoable: false)`. `_sync` chama `_metronomeStyleCalls()` depois de `_docCalls` e antes de `_monitorCalls()`: vazio se a assinatura (`metroSig`, os cinco números em texto; `''` no padrão) não mudou. `_docCalls` manda `['metronome', ligado, options.volume]`.

**Como testar.** `flutter test test/fase17c_test.dart` (937 linhas, 47 declarações; as duas de janela rodam em 360 px e em 1512 px): grupos `tap tempo`, `JSON do documento`, `opções do metrônomo`, `pré-roll`, `punch: áudio`, `punch: MIDI` e `punch: estado do projeto`, mais testes de widget da barra, das configurações e do diálogo de andamento. `flutter test test/keymap_test.dart` (o oráculo ganhou `P` e `T`) e `test/recording_ui_test.dart` (rola até o interruptor da contagem, porque a janela ficou mais longa). Motor: `cargo test -p jopendaw-engine metronom` ([01](01-motor.md#metrônomo-timbres-subdivisões-e-acento-enginesrcmetronomers-fase-17)). Nada foi visto rodando no Chrome nem no Android: nem a gravação com punch e pré-roll, nem o som dos timbres, nem o tap tempo `(testado só por testes automáticos)`.

**Armadilhas.**
- **Sem fade no punch in com pré-roll** (acima): o corte é seco e o clipe antigo termina em `punch.in`. Só o punch out e o punch in "cortado" ganham os 7 ms.
- **`restartAudio` não zera `metroSig`** (`controller.dart`, junto de `tempoSig` e `meterSig`): depois de `Reiniciar o áudio` um estilo fora do padrão não é reenviado ao motor novo até a próxima mudança de opção. O mesmo vale para `_cache.mod` (modulação), que também não é zerado ali `(lido do código; não testado)`.
- **`togglePunch` e `Usar a região do loop` divergem:** o primeiro só copia o loop se ele está **ligado**; o botão da janela copia com o loop desligado.
- **`punchActive` × `punchOn`:** o botão da barra e o item do menu usam `punchActive` (ligado e com região); o interruptor de `Configurações` usa `punchOn`. Como `punchOn` nunca fica ligado sem região (a leitura e `setPunchRegion` garantem), na prática coincidem.
- **`T` e andamentos lentos:** com o atalho, o `Timer` de 1,5 s vence antes da próxima batida quando o intervalo passa de 1,5 s (abaixo de 40 BPM); o valor é aplicado com só duas batidas e a sequência recomeça. O botão do diálogo não tem o problema.
- **`T` e `P` são notas do teclado do computador** (estão em `noteKeyLetters`): com o teclado ligado o atalho não vale e a janela `?` os lista em `Suspensos…` (16 linhas com os padrões).
- **O app não para no punch out** e a entrada continua sendo capturada e guardada até o parar (o que passa do punch out é descartado no `_cropToPunch`).
- **Catálogo:** de 54 para 56 ações (`Geral` 27); a ordem importa para o `.jokeys` (as duas novas ficam logo depois de `transport.metronome`).

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
| `daw/controller.dart` | `autoRec` (criado no construtor e descartado no `dispose`), `autoInfo`, `autoLaneOf`, `autoSnapshot`, `autoTakeCheckpoint`, `autoCommitUndo`, `autoSyncNow`, `autoApply`; `checkpoint` (consome o "engole"); `_automationCalls` e `liveTargetValue` (a raia gravada sai do motor e do controle); `_onPointer` chama `autoRec.releaseAll()` quando o último ponteiro levanta (só `PointerUpEvent` e `PointerCancelEvent` contam); `autoSetFixed` (devolve o valor fixo do alvo sem passar pela gravação nem pelo histórico: é o que o `Toque` usa ao acabar); `setParam`, `setEffectParam` e `setSend` chamam `autoRec.value` antes de gravar o valor |
| `daw/mixer_panel.dart` | mixin `_DragValue`: `autoKey` (alvo do controle) e as chamadas de `touch` (na primeira mudança do gesto, antes do `checkpoint`) e `release` (em `end()`, também ao fim da roda: 500 ms parada); `_Fader` e `_PanKnob` chamam `value` em `_set`; `_SendRow` só tem `autoKey` se o envio existe |
| `daw/instrument_panel.dart`, `daw/fx_editors.dart` | `onChangeStart` chama `touch` antes de `checkpoint`; `onChangeEnd` chama `release` |
| `daw/timeline.dart` | mini fader do cabeçalho da **faixa** (`_miniStart`, `_miniGain`, `onEnd`; um único `_MiniFader` para tocando e parado, para a árvore não mudar no meio do gesto) e o do **master** (`_MasterHeader`: um `ListenableBuilder` sobre `c.beat` e `c.autoRec` com `onStart` → `touch(-1, volume)` + `checkpoint`, `onGain` → `value` + `mutate`, `onEnd` → `release`; gravando, mostra `masterGain`, a mão, e não a curva). Desde `504b4b8` |
| `daw/automation_lane.dart` | monta o `AutoLaneModeButton` no cabeçalho da raia, antes do olho riscado |
| `test/automation_record_test.dart` | 651 linhas: afinamento, encaixe puro e gravação sobre o controlador com motor de mentira |
| `test/fase14a_test.dart` | grupo `automação` (hover não fecha o `Toque`; `Toque` devolve o valor fixo, também no parâmetro de instrumento; `Toque` e `Trava` no loop; mini fader do `Master`) e grupo `presets` (ver [Presets do usuário](#presets-do-usuário-user_presetsdart-user_presets_uidart)) |

### Fluxo de dados / ciclo de vida

1. **Modo.** `AutoRecorder.mode` (barra) e `laneModes` (mapa `id da raia → AutoMode`, só na sessão, não vai para o JSON do documento). `modeFor(track, alvo)` devolve o da raia do alvo, se tem, senão o da barra. `setMode` e `setLaneMode` com o transporte tocando chamam `_endSession()`.
2. **Agarrar.** `touch` (só se o modo grava e `_canRecord`: transporte tocando e sem gravação de áudio/contagem, senão `notice`) cria o `_Live` do alvo (`_entryFor`: consulta `autoInfo` e `automatable`; alvo sem automação entra em `_rejected` e dá o aviso `Este controle não tem automação.`), tira o `_snapshot` do documento (`autoSnapshot`) e liga `_swallow` por um microtask: o `checkpoint()` que o gesto chama a seguir é **engolido** (`consumeSwallow`), porque o passo de desfazer é o da passada inteira.
3. **Mexer.** `value` chama-se antes de o valor entrar no documento. Sem `touch` prévio (roda, duplo clique, setters chamados de outros lugares) o alvo abre na hora e o ponto de desfazer que o gesto acabou de guardar é **tirado** do histórico (`autoTakeCheckpoint`, só se foi guardado no mesmo turno: `_ckptTurn`) para servir de `_snapshot`. O valor é preso a `[min, max]`, vira `e.last` e uma amostra em `c.beat.value`; na primeira amostra `autoSyncNow()` reenvia a automação ao motor **sem** a raia deste alvo.
4. **Amostrar.** `_onBeat` (ouvinte de `c.beat`) acrescenta `(beat, e.last)` a cada alvo aberto, mesmo com a mão parada. Se o cursor voltou (`b < prev - 1e-6`: loop ou salto), a volta que acabou é aplicada (`_apply(wrapped: true)`) e outra começa na batida nova **só se** `goOn`: `Escrever` sempre, `Trava` se `e.held` (controle ainda seguro). Senão `e.seg` vira `null` (o alvo segue em `_live`, sem trecho aberto; o próximo `value` abre outro) e, no `Toque`, `_restoreFixed` devolve o valor fixo.
5. **Fechar.** `release` no `Toque` chama `_finish` (aplica, tira o alvo de `_live` e chama `_restoreFixed`). No `Escrever` e na `Trava` o alvo segue até o transporte parar: `_onPlaying(false)` → `_endSession` aplica tudo (e `_restoreFixed`, que só age no `Toque`) e, se houve mudança (`_dirty`), `autoCommitUndo(snapshot)` empilha o passo. Ninguém abre trecho no play: um trecho só nasce em `value` (a primeira mudança do controle); o antigo `_startWrites`, que abria as raias com modo próprio `Escrever` desde o cursor, foi removido em `504b4b8`. `_restoreFixed` chama `DawController.autoSetFixed(track, alvo, e.fallback)`, com `fallback` = o valor fixo de antes da primeira mexida (`_Live.fallback`), só quando `e.mode == AutoMode.touch`.
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
- **`Escrever` só depois do primeiro toque.** Gravar desde o play (o antigo `_startWrites`) apagava a curva antiga de quem só apertava play com uma raia em `E`; agora o trecho nasce no primeiro `value`, igual pela barra e pela raia.
- **O `Toque` devolve o valor fixo.** O valor fixo do documento vai junto com a mão (a raia grava e o motor recebe o valor pelos caminhos rápidos); ao acabar o `Toque` o app o devolve ao `fallback` (`autoSetFixed`), senão o controle parado ficaria no último ponto da mão e o `Toque` deixaria de ser "só um trecho".
- **Só `PointerUp`/`PointerCancel` soltam.** O mouse sem botão e a roda também mandam eventos com nenhum ponteiro apertado; tratá-los como "soltou" fechava o trecho no meio do gesto.

### Como testar

```bash
cd app && flutter test test/automation_record_test.dart
# as correções da fase 14 (A): grupo `automação` de test/fase14a_test.dart
cd app && flutter test test/fase14a_test.dart
```

O grupo `automação` de `fase14a_test.dart` cobre: o mouse sem botão não fecha o `Toque` e só `PointerUp`/`PointerCancel` fecham; ao fechar, o valor fixo volta ao de antes da mão (também num parâmetro de instrumento); `Toque` com loop não regrava o último valor mantido na volta seguinte; `Trava` com loop só segue com o controle seguro; e um teste de widget em que o mini fader do `Master` grava em `Toque` na raia do master e devolve o valor fixo. O `Escrever` da raia sem gesto (não apaga a curva) e com gesto (grava dali até parar) está em `automation_record_test.dart`. Só testes automáticos `(testado só por testes automáticos)`.

Grupos: `afinamento` (senoide de 4 s vira no máximo 90 pontos com erro abaixo de 1%; escala do controle; entradas inválidas; parâmetro em degraus; milhares de amostras), `encaixe na automação (função pura)` (região substituída e vizinhança, trecho curvo, escala do fader, Toque sem automação, `Escrever`/`Trava` sem pontos depois, degraus) e `gravação sobre o controlador` (Ler não grava; parado não grava; Toque, Trava e Escrever pela barra e pela raia; loop; parâmetro logarítmico e inteiro; volume nos extremos; envio; sidechain; gravação de áudio; troca de modo tocando; controle mostra o valor fixo e o motor não recebe a raia gravada; raia criada na hora; passada com vários alvos como um passo). Mais um teste de widget do botão da barra e do seletor da raia. Tudo com motor de mentira; o uso real no Chrome (Toque no fader de uma faixa, com recarregar a página depois) foi feito à mão pela sessão que implementou.

### Armadilhas conhecidas

- **O valor fixo do documento acompanha a mão no `Escrever` e na `Trava`.** `_set`/`setParam` gravam o valor também no documento; depois de uma `Trava` (ou de um `Escrever`) a raia tem o que foi gravado e o valor fixo (o que se vê parado) fica onde a mão largou. O desfazer o restaura. No `Toque` isso foi corrigido (ver abaixo).
- **O modo de uma raia apagada fica em `laneModes` até o fim da sessão** (sem efeito). Uma raia oculta com modo próprio `Escrever` continua valendo, mas só grava depois do primeiro `value`.
- **`autoSetFixed` não passa pelo histórico nem pela gravação** (só `mutate`): o retorno do valor fixo no fim do `Toque` não é um passo do desfazer; quem o desfaz é o passo da passada inteira (o `_snapshot` tirado no primeiro toque). `(lido do código)`
- **Resolvido em `504b4b8` (fase 14 A), o que esta seção listava como armadilha:**
  - o mini fader do `Master` não gravava (agora chama `touch`/`value`/`release` e mostra a mão enquanto grava; teste `mini fader do Master grava` de `fase14a_test.dart`, com widget);
  - `releaseAll` corria em todo evento de ponteiro sem botão apertado, então mexer o mouse (ou a roda) fechava o `Toque` antes dos 500 ms (agora só `PointerUpEvent` e `PointerCancelEvent`);
  - o valor fixo ficava onde a mão largou depois de um `Toque` (agora `_restoreFixed` o devolve ao de antes, ao soltar, na volta do loop e ao parar o transporte);
  - `_startWrites` fazia o `Escrever` da raia gravar o valor fixo desde o play e apagar a curva antiga (removido: só grava depois do primeiro toque no controle, na barra e na raia);
  - no loop, o `Toque` regravava na volta 2 o último valor mantido e a `Trava` seguia gravando com o controle solto (agora o `Toque` para na volta seguinte e a `Trava` só segue com `held`).
- **Resolvido em `ffa76ba` (fase 16 A): o `Toque` que a volta do loop fechava reabria assim que o valor mudava de novo.** `_onBeat` deixava `held = true` depois de fechar o trecho; o próximo `value()` do dedo que seguia se mexendo reabria o trecho e regravava. Agora a virada do loop põe `held = false` (com `_restoreFixed`) e `value()` sai cedo (`!fresh && mode == touch && !held`) até um `touch()` novo (agarrar de novo) ou o `release`. Teste em `app/test/fase16a_test.dart` (`Toque no loop`). As frases de `AutoMode` (`write`, `touch`, `latch`) passaram a dizer `Começa ao mexer no controle (só agarrar não basta)…`, porque `touch()` só marca `held` e quem abre o trecho é o primeiro `value()`.
- **`setMode`/`setLaneMode` não fazem `_endSession` parado** (só tocando); os `_Live` só existem tocando.
- **A frase do menu do botão é a mesma do tooltip** (`AutoMode.hint`): mudar o texto de um muda o outro, e os testes de widget procuram o rótulo `Ler`, `Escrever`, `Toque` e `Trava`.

## Onde está cada tela em `daw/`

| Arquivo | Papel |
|---|---|
| `timeline.dart` | régua, cabeçalhos das faixas, raias com clipes, sub-raias de automação, linha do master, cursor. **Reordenar x mini fader (fase 13, `18c72f4`):** o `_MiniFader` do `_TrackHeader` leva `key: _faderKey` e o corpo do cabeçalho está num `Listener(behavior: translucent)` cujo `onPointerDown` guarda `_skipReorder = _onSlider(posição global)`; `_onSlider` compara o ponto com o retângulo do fader inflado em `_sliderSideGuard` (4 px) dos lados e expandido `_sliderGuard` (15 px) para cima e para baixo (`_verticalGuard`; fase 15, `1d90812`: antes eram 15 px em volta, e o botão `FX` e o medidor ao lado não reordenavam), e `onLongPressStart` recalcula `_skipReorder` com a posição onde o toque longo começou, em vez de confiar no último `PointerDown`. Com `_skipReorder`, `onLongPressStart` e `onLongPressMoveUpdate` do reordenar retornam sem fazer nada (o `onLongPressEnd` roda, mas `_dragTo` é nulo, então nada se move). No celular (`compact`) o cabeçalho não tem mini fader, `_faderKey.currentContext` é nulo e a proteção não existe. Teste: `fase13c_test.dart` (`cabeçalho: o deslizador de volume tem prioridade sobre o reordenar`; segurar em cima e a 12 px não reordena, no resto do cabeçalho reordena, e arrastar o deslizador continua mudando o volume) |
| `transport_bar.dart` | barra do transporte e das ferramentas (tocar, gravar, andamento, loop, metrônomo, edição, grade, o botão `Automação` (`AutoModeMenu`), zoom, painéis, teclado, MIDI, importar, exportar, configurações; divisores de 4 px de cada lado para caber em 1512 px; sem o indicador de nuvem; a ordem dentro da `Row` é transporte (parar, tocar, `_RecordButton` com a seta, o `_Toggle` do punch, `_Position`, `_TempoButton`, loop, metrônomo) | edição e visão (termina em `ViewMenu`, `SectionsMenu` e `DurationLabel`) | painéis | entradas (teclado, cabo e `MidiLearnButton`, este só com o MIDI ligado, em aprendizado ou com mapeamentos) | importar e exportar | engrenagem | atalhos | status; desde `47c5f3d` o `DurationLabel` e o `IconButton` dos atalhos só entram com `MediaQuery.sizeOf(context).width >= 1640` (a largura da **janela**, ao contrário de `_labelsWidth` = 1540, que é a da barra e decide se `Importar`/`Exportar` mostram o nome), porque em 1512 px eles empurravam a engrenagem para fora; o `SettingsDialog` ganhou o botão de texto `Atalhos do teclado` (`showShortcuts`) ao lado do `Fechar` para o caminho que a barra perdeu, e a tecla `?` (`help.shortcuts` em `project_screen.dart`) continua valendo em qualquer largura; o tooltip do exportar é `Exportar áudio (WAV, FLAC ou MP3)`); o botão de andamento (`_TempoButton`: BPM vigente no cursor, ícone `show_chart` e `↗` (rampa que sobe) ou `↘` (rampa que desce) com mapa; o texto do BPM vem de `formatBpm` de `tempo_format.dart` (fase 13; `warp_dialog.dart` a reexporta), o mesmo do `projectSubtitle`, da faixa `Andamento`, do warp e da pergunta do `.mid`: arredonda a uma casa e tira o `,0`, então `120,04` sai `120`; o compasso do botão com um andamento e um compasso só vem de `formatDocMeter`) e a janela `Andamento e compasso` (`_TempoDialog`, com o atalho para a mudança de compasso) |
| `tempo_map.dart` | `TempoPoint`, `MeterChange`, `TempoMap`, `MeterMap`, a normalização dos dois e `tempoMapCalls`; Dart puro, sem `dart:ui`. Espelho de `engine/src/tempo.rs` |
| `tempo_lane.dart` | a faixa `Andamento` sob a régua (`TempoLane`, `_TempoPainter`, gestos e menus) e o diálogo `Mudar compasso a partir do compasso N` (`showMeterChangeDialog`) |
| `tempo_format.dart` | o formatador **único** do andamento e do compasso (commit `1180152`, fase 13): `formatBpm(double)` (arredonda a uma casa, sem `,0`, vírgula decimal: `120`, `97,5`; `120,04` e `119,96` viram `120`, `120,06` vira `120,1`), `formatPitch(double)` (a altura do warp em semitons, fase 15: até duas casas, sem zeros sobrando, vírgula: `2`, `-0,5`, `0,04`; não usa o `formatBpm`, que com uma casa faria `0,04 st` aparecer como `0`; usado pela leitura do `warp_dialog.dart`, mas o selo do clipe em `timeline.dart` ainda formata com `toStringAsFixed(1)`), `formatMeter(numerador, denominador)` (`4/4`, `6/8`; também usado pelo botão de andamento da barra e pela lista `Tempos por compasso`) e `formatDocMeter(DawDoc)` (o compasso do compasso 1 com a figura verdadeira, por `d.meter.changeAt(1)`, e não um `/4` fixo). Usado pela barra (`_TempoButton`, `_TempoDialog`), pelo `projectSubtitle`, pela faixa `Andamento`, pelo diálogo do warp (`warp_dialog.dart` o reexporta: `export 'tempo_format.dart' show formatBpm`) e pela pergunta do `.mid` (`_bpmText`). Antes havia duas contas: o `formatBpm` de `warp_dialog.dart` (só tirava o `,0` de um valor exatamente inteiro, então `120,04` aparecia `120,0`) e o `_bpmText` de `midi_file_ui.dart` (tolerância de 0,05). Testes: `app/test/fase13b_test.dart` |
| `dock.dart` | painel de baixo em abas (mixer, editor de notas, `Passos`, instrumento, efeitos, modulação); a aba `Passos` só entra quando a faixa selecionada tem sequenciador (`stepsAvailable`) |
| `step_sequencer.dart`, `step_sequencer_ui.dart` | sequenciador de passos da bateria e do sampler com zonas (fase 17 B): a conversão pura grade ↔ notas e a aba `Passos` (seção [Sequenciador de passos](#sequenciador-de-passos-fase-17-b)) |
| `mixer_panel.dart`, `meter.dart` | canais do mixer, medidor de pico; com pastas, a barra `Grupo` (`GroupBar`) sobre os canais |
| `track_groups.dart`, `track_groups_ui.dart` | pastas de faixa: modelo derivado (`DawGroups`), `planTrackMove`, operações do controlador (`DawGroupsController`) e a interface (linha da pasta, diálogo, menus, miniatura, barra do mixer); seção [Pastas de faixa](#pastas-de-faixa-dawtrack_groupsdart-track_groups_uidart) |
| `piano_roll*.dart`, `midi_tools.dart`, `piano_roll_tools.dart` | editor de notas (partes de `piano_roll.dart`) e a lógica pura das ferramentas de produtor |
| `instrument_panel.dart`, `knob.dart`, `presets.dart`, `wavetable_shape.dart` | painel do instrumento, controle giratório, presets e ids nomeados, gráfico das tabelas |
| `sampler_zones.dart`, `sampler_zones_controller.dart`, `sampler_zones_panel.dart`, `slice_dialog.dart` | zonas do sampler no app (o motor está em [01-motor.md](01-motor.md#zonas-do-sampler-e-fatiamento-enginesrcsampler_zonesrs)). `sampler_zones.dart` é Dart puro: `SamplerZone`, `maxZones` 128, `nextZoneRange`, `zoneAddBlocker` (a mensagem única `Não dá para criar outra zona: o limite é de 128 zonas ou o teclado já está todo ocupado por zonas de uma nota só. Apague alguma antes.`), `velocityLayers(n, {lo, hi})` (camadas dentro da faixa atual da zona, no máximo o número de valores dela), `parseNoteInput`, `slicePoints(áudio, {count, sensitivity, limit})` (`limit` padrão `maxSlices` = 96, paridade com o motor; o diálogo passa 100000 para saber quantos ataques há). `sampler_zones_controller.dart` (extensão de `DawController`): `zoneAddBlockerOf`, `addZone` (com o teclado todo coberto divide a zona mais larga e, se a `Nota base` dela ficaria acima da faixa que sobrou, traz-a para a ponta e diz no aviso), `splitZoneLayers`, `addZoneFromFile` (checa o bloqueio antes de abrir o seletor), `createSlices`. `sampler_zones_panel.dart`: cartão `ZONAS`, mapa, editor (o `_ZoneEditor` recebe `full: zones.length >= maxZones`: com 128 zonas o `IconButton` de duplicar fica com `onPressed: null` e o tooltip `Não dá para duplicar: as zonas já estão no limite de 128.`; `duplicateZone` continua devolvendo `null` no limite, como rede de segurança; fase 14) e o `_Stepper` dos campos digitáveis (texto e erro inline, `Esc` cancela). `slice_dialog.dart`: diálogo `Fatiar sample`, aviso `N fatias achadas; só as 96 primeiras viram nota.` com `Menos sensibilidade` (baixa 0,15 e refaz) e os cortes além do 96º apagados em `_SlicePainter`. O cartão `Envelope` e o visor do cartão `Áudio` com zonas ficam em `instrument_panel.dart` (`_samplerSections`, `_sampleDisplay`). Várias destas regras são de `d196fec` |
| `effects_panel.dart`, `fx_editors.dart`, `fx_presets.dart` | rack de efeitos, editores (EQ, dinâmica, genérico; `fx_editors_dyn.dart` é `part` de `fx_editors.dart` e traz os do multibanda, do de-esser e da imagem estéreo) e presets |
| `automation_lane.dart`, `automation_math.dart` | editor de pontos e a conta da curva |
| `automation_record.dart`, `automation_mode.dart` | gravação de automação ao mexer nos controles e os seletores de modo (seção [Gravação de automação](#gravação-de-automação-automation_recorddart-automation_modedart)) |
| `marker.dart`, `structure_menu.dart`, `minimap.dart` | marcadores, menus Seções e Visão, minimapa |
| `export.dart`, `export_options.dart`, `wav.dart` | exportar (janela e opções) e codificação/leitura de WAV |
| `export_compressed.dart` | exportar em FLAC e MP3 pelo servidor (fase 15 C): sobe o WAV, espera a tarefa `encode_audio`, baixa e salva; queda para WAV (seção [Exportação em FLAC e MP3](#exportação-em-flac-e-mp3-export_compresseddart)) |
| `history.dart`, `history_ui.dart`, `snapshots.dart`, `snapshots_ui.dart` | histórico de desfazer com nomes e versões nomeadas do projeto (fase 18 C): [seção própria](#histórico-com-nomes-e-versões-nomeadas-fase-18-c) |
| `settings_dialog.dart`, `shortcuts_dialog.dart` | configurações de gravação (desde a fase 17 também `Pré-roll`, `Punch in/out`, `Usar a região do loop` e a seção `METRÔNOMO`) e janela de atalhos (desde a fase 16 gerada do catálogo de `keymap.dart`: `shortcutGroups`, `suspendedShortcutsOf`, o botão `Personalizar`) |
| `keymap.dart`, `keymap_ui.dart` | atalhos personalizáveis (fase 16 C): o catálogo de 56 ações (54 na fase 16; `transport.punch` e `transport.tap` na fase 17), o `Keymap` (resolver, regras, guardado local), o arquivo `.jokeys` e a tela de personalizar (seção [Atalhos personalizáveis](#atalhos-personalizáveis-keymapdart-keymap_uidart)) |
| `midi_map.dart`, `midi_learn.dart`, `midi_learn_ui.dart` | MIDI learn: modelo e conta (Dart puro), o motor do aprender e do takeover com o padrão para novos projetos, e a tela (contorno, menu, botão, faixa, janela `Mapeamentos MIDI`); ver a seção [MIDI learn](#midi-learn) |
| `warp.dart`, `warp_dialog.dart` | sons derivados do warp e o diálogo |
| `audio_to_midi.dart`, `midi_convert_dialog.dart` | áudio → MIDI pelo servidor (job `audio_to_midi`) e o diálogo; `notesForClip` segue o warp (`AudioClip.tempoFor`), soma a transposição e espelha no reverso |
| `clip_gain_dialog.dart` | diálogo `Ganho do clipe` (item `Ganho do clipe…` do menu do clipe de áudio em `timeline.dart`): slider −40 a +12 dB, `clipGainFromDb`/`clipGainToDb`, `setClipGain` |
| `audio_edit.dart`, `audio_edit_ui.dart` | edição de áudio por fatias (fase 18 B): a lógica pura (cortes, fatias, silêncio, normalização, quantização, `extension AudioEditing on DawController`) e os quatro diálogos do submenu `Editar áudio` do clipe (seção [Edição de áudio](#edição-de-áudio-fase-18-b)) |
| `tap_tempo.dart` | `TapTempo`: a média das últimas 8 batidas do tap tempo (Dart puro, o tempo vem de fora); seção [Punch, pré-roll, tap tempo e opções do metrônomo](#punch-pré-roll-tap-tempo-e-opções-do-metrônomo-fase-17-c) |
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

- *Andamento.* `MidiFileData.tempoMap` guarda a lista inteira e ordenada (batida = tick/PPQ, BPM real `60000000 / µs`; dois `FF 51` na mesma batida: o último vale); `firstBpm` é o primeiro ponto; `hasTempoChanges` é verdadeiro se algum BPM difere do primeiro por mais de 0,5 (só serve ao aviso de "mantive o do projeto"). `tempoPoints` (`late final`) é o mapa que entra no projeto: `simplifyTempo` (`midi_file.dart:123`) põe um ponto de 120 BPM na batida 0 se o primeiro `Set Tempo` vem depois, prende cada BPM a 20–999, **funde** o ponto que difere menos de `midiTempoEpsilon = 0.05` BPM do último mantido e, se ainda passa de `midiMaxTempoPoints = 1024`, dobra o epsilon até caber (ou até passar de 999). O limite subiu de 256 para 1024 na fase 14: o mapa aceita até `maxTempoPoints = 4096`, e 1024 mantém baixo o custo de CPU do motor e cobre rampas gravadas com folga. Antes o número era o de pontos que o motor reserva sem realocar (`TEMPO_RESERVED = 256`, que **não** mudou; acima disso o `Vec` do `TempoMap` cresce ao aplicar os pontos, `(lido do código; não medido se isso causa glitch no thread de áudio)`). Todos entram como salto (`ramp: false`).
- *`importedTempo`.* Sem andamento no arquivo: `null` (o do projeto fica). Um ponto só: `bpm` = `((bpm × 10).round() / 10)` limitado a `minBpm`..`maxBpm` (uma casa decimal, a resolução do app; não finito vira 120), com mapa `[]` (fase 14, `725ce0f`: até a fase 13 era `appBpmFor`, inteiro, e `97,5` entrava como 98; o arredondamento a uma casa também absorve o 90,00009 que sai de microssegundos por semínima). A pergunta mostra o BPM por `_bpmText` (`formatBpm`) e agora o valor mostrado é o que entra. `appBpmFor` continua existindo (`midi_file.dart`) para os demais usos. Vários: `bpm` = o primeiro ponto **sem arredondar** e o mapa passa por `normalizeTempoPoints` (que limita a 4096).
- *Compasso.* `parseMidiFile` junta os `FF 58` numa lista de `MeterChange` (`MidiFileData.meterMap`, compasso 1 = o primeiro): uma fórmula por tick (a última vale); denominador `2^dd` até 32, e acima disso a mesma duração em fusas (`numerador / 2^(dd−5)`, com aviso); numerador acima de 64 vira 64 (com aviso). Se o primeiro `FF 58` vem depois do tick 0, o compasso `4/4` vale até ele. A batida de cada mudança vira número de compasso contando compassos inteiros desde a mudança anterior (`k = round((batida − início) / barBeats)`); fora de 1e-6 de um compasso inteiro, o `misaligned` levanta o aviso e a mudança vai para o compasso mais próximo; `k < 1` (a mudança cai antes do fim do compasso vigente) troca a fórmula vigente em vez de abrir compasso novo. Fórmula igual à vigente é descartada.
- *`beatsPerBar`.* Sem `meterMap` (arquivo sem `FF 58`) é `null`. Com ele, `importedMeterBeats(primeira)` = `barBeats.round()` limitado a **1–32** (6/8 → 3; 7/8 → 3,5 → 4, **sem** o aviso antigo de aproximação; até a fase 13 o limite era 12, e um primeiro compasso de 13/4 ou 4/1 criava o clipe com 12 tempos: alinhado ao documento em `18c72f4`) e vale para o `length` dos clipes criados. Já `importedMeter` (o que vai para `doc.beatsPerBar`) usa `numerador` quando `den == 4` e `barBeats.round()` senão, limitado a **1–32**, e devolve `changes` por `normalizeMeterChanges` (vazio se só sobra um `n/4`; um `6/8` ou `7/8` único **fica** no mapa). A antiga diferença 12 × 32 entre `importedMeterBeats` e `importedMeter` acabou (ver "Armadilhas do arquivo MIDI").
- *Perguntar.* `midiTempoDiffers(data, doc)` compara `importedTempo`/`importedMeter` com o documento: BPM pela diferença absoluta (`(t.bpm - doc.bpm).abs() > 0.05`; até a fase 15 era `t.bpm.round() != doc.bpm.round()`, o que deixava uma lacuna: com a fração preservada desde a fase 14, um arquivo em 97,5 contra um projeto em 98 não perguntava e o 98 ficava; resolvido em `ffa76ba`, tolerância de 0,05 BPM, uma casa decimal é a resolução do app), tamanho do mapa e cada `TempoPoint` (igualdade por batida, BPM e rampa); `beatsPerBar`, tamanho e cada `MeterChange`. Diferiu, `askUseFileTempo` abre a pergunta (títulos e texto em [Áudio e clipes](../manual/03-audio-e-clipes.md#importar-um-arquivo-midi-mid)); recusar não muda nada.
- *Avisos de andamento* (em `importMidiBytes`): aceito e `tempoPoints.length < tempoMap.length` → `O arquivo tem N mudanças de andamento; fundi as que diferem menos de 0,05 BPM e M ficaram no mapa (o limite é 1024 pontos).` (o texto usa `$midiMaxTempoPoints`; desde `18c72f4` o `midiTempoEpsilon` sai com vírgula decimal e o texto flexiona: `1 mudança`/`mudanças`, `ficou`/`ficaram`; `N` é `tempoMap.length - 1` e `M` é `tempoPoints.length - 1`); recusado e `hasTempoChanges` → `O arquivo muda de andamento no meio (de X a Y BPM); mantive o do projeto.` Os avisos `o app tem um andamento só…`, `O arquivo muda de compasso no meio…` e `O compasso 7/8 foi aproximado para 4/4…` saíram. Restam os de compasso `Uma fórmula de compasso do arquivo passa dos limites do app (denominador até 32, numerador até 64) e foi aproximada.` e `Uma mudança de compasso caiu no meio de um compasso: alinhei ao compasso mais próximo.` Desde a fase 14 há também, em `parseMidiFile`, o corte do mapa de compassos: se `meters.length > maxMeterChanges` (1024 entradas, contando o compasso inicial) o aviso é `O arquivo tem N mudanças de compasso; o app aceita até 1023, então as seguintes ficaram de fora.` (`N = meters.length - 1` antes do corte; `meters.removeRange(maxMeterChanges, ...)`); antes `normalizeMeterChanges` cortava em silêncio com o `take(maxMeterChanges)` `(testado só por testes automáticos: `fase14b_test.dart` gera 1100 `FF 58`)`.
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
- **Simplificar na importação, não no motor.** Um arquivo com rampa gravada em dezenas de milhares de `Set Tempo` estouraria os 4096 do `normalizeTempoPoints` (e os 256 que o motor reserva sem realocar); por isso `simplifyTempo` funde o que difere menos de 0,05 BPM e, se preciso, dobra a tolerância.
- **Rampa vira degraus na escrita e não volta como rampa.** O SMF só tem `Set Tempo` em degraus; a marca `ramp` não sobrevive à ida e volta (a importação entra sempre em salto).

### Como testar

```bash
cd app
flutter test test/midi_file_test.dart
```

Cobertura de `test/midi_file_test.dart`: leitura à mão (tipo 0 com running status e `9n` de velocidade 0, tipo 1 com trilha de andamento, VLQ de 4 bytes, SysEx e mensagens de sistema, bend/modulação/pedal, notas presas, duração zero, bateria GM, vários canais numa trilha, várias mudanças de andamento, 6/8 e 7/8, PPQ 1/96/960/32767); arquivos ruins (vazio, não-MIDI, SMPTE, PPQ 0, tipo desconhecido, cabeçalho cortado, sem faixa, sem nota, truncado, lixo na trilha, 300 arquivos de bytes aleatórios que só podem lançar `MidiFormatException`, RMID); escrita e ida e volta (notas, velocidades, controles, andamento 97, compasso 3, nomes, posição absoluta da bateria; clipe selecionado sai do começo; 15 faixas melódicas pulam o canal 10 e a 16ª volta ao 1; notas fora de 0–127 ou do clipe; notas emendadas; nome do arquivo); desempenho (100 mil notas escritas e lidas em menos de 20 s, com a leitura cedendo o controle); e a importação no controlador com o motor de mentira (faixa de sintetizador e de bateria, andamento aceito e desfeito com `undo`, andamento recusado, pergunta só quando difere, aviso de mudança de andamento, arquivo ruim vira `error` sem mexer no documento). O grupo `mapa de andamento e de compassos` (fase 11) cobre: salto, rampa e compassos que voltam iguais na ida e volta (a rampa de 8 batidas vira mais de 128 degraus e o `secondsAt` do mapa lido bate com o original em até 15 ms); um andamento e um compasso só sem mapa (um evento de cada, como antes); o clipe avulso levando o andamento e o compasso que valiam no começo dele; ausência de deslocamento de bits (dart2js); um `.mid` com mudança de andamento no meio virando o mapa do projeto sem o aviso antigo; recusar avisando `mantive o do projeto`; arquivo com dezenas de milhares de eventos de andamento simplificado para caber; fusão só do que difere menos de 0,05 BPM; compassos `6/8` no compasso 3 e `7/8` depois entrando no mapa; e mudança de compasso no meio de um compasso alinhando e avisando. `6/8` lê `beatsPerBar` 3 e `7/8` lê 4 com `meterMap` exato e sem aviso. Em `test/piano_roll_tools_test.dart`: `dropSnapCollisions` e `keyboardTooltip`. Os testes rodam na VM do Dart, não no dart2js: o cuidado com inteiros de 32 bits vem da leitura do código, não de teste na web `(não confirmado no navegador)`. `app/test/fase12c_test.dart` (fase 12, `dd4ef07`, 511 linhas) cobre: `Tempos por compasso` trocando um `6/8` inicial, BPM decimal no documento e no motor, os limites 4096/1024 com aviso, a janela 20–999, compasso pelo mapa (clipe novo, `fitRange`, encaixe, duração), a seta `↘` e o diálogo de andamento (widget), `Program Change` e RPN 0 na exportação, faixa muda e solo, pontos de controle fora do clipe, o `Salvar como` cancelado (widget), `Importar como` (FM, wavetable, sampler; o seletor só abre com faixa melódica, lembra a escolha e cancelar não importa), o nome do clipe, e na expressão a faixa antiga voltando ao repouso, parar zerando pedal, bend e roda, a bateria sem pontos, `cutControls` e o aparo da borda esquerda. Sem teste de widget para `importFiles` nem `askUseFileTempo` `(não confirmado em uso)`; nada disto foi visto no navegador nem no Android `(testado só por testes automáticos)`.

### Armadilhas do arquivo MIDI

- **Rampa não faz a viagem de volta.** A exportação a escreve em degraus de 1/16 de batida (máximo de 4096 por rampa) e a importação a lê como saltos, fundindo o que difere menos de 0,05 BPM e limitando a 1024 pontos (eram 256 até a fase 14); o mapa de ida e volta soa igual (tolerância de 15 ms no teste), mas o desenho da faixa `Andamento` fica cheio de pontos em vez de uma rampa.
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
- `importProjectBundle(bundle, ...)`, na ordem que deixa o pior caso inofensivo: `remapDocIds(doc)`; `createProject(importedProjectName(...))` (POST `/api/projects`); se o andamento (`doc.bpm` arredondado e limitado a 20–999, `minBpmInt`..`maxBpmInt`; o andamento com decimais fica no documento, só o espelho do servidor é inteiro) ou o compasso (o numerador do compasso 1 do mapa, `doc.meter.changeAt(1).numerator`, limitado a 1–32, ou a figura dele, se estiver em `{1, 2, 4, 8, 16, 32}` e diferir) diferem dos padrões do projeto novo, `patchProject` com `{bpm, beats_per_bar, beat_unit?}` (fase 15; antes usava `beatsPerBar` e não mandava a figura); copia o andamento do projeto para o documento e limita `doc.beatsPerBar` a 1–32 (o `beatsPerBar` do documento é dele: um 6/8 guarda 3 lá e 6 no espelho); grava cada `sample:<hash>` **se a chave ainda não existe**; grava `doc:<id>` por último (é o que faz o projeto "existir" para o editor). Qualquer falha depois de criado o projeto chama `deleteProject` (melhor esforço) e relança.
- `remapDocIds`: id de faixa, clipe de áudio, clipe MIDI, efeito (faixas e master), marcador, modulador (`ModSource.id`, das faixas e do master; desde `52d25c1`), raia de automação e mapeamento de MIDI learn (`MidiMapping.id`, também desde `52d25c1`) fica igual se casa `^[A-Za-z0-9_-]{1,64}$` e ainda não foi usado; senão recebe `newId()`. Depois reaponta: envio para faixa que sumiu é descartado, `output` inexistente vira `null` (master), raia de efeito ou de envio cujo alvo não existe é descartada, e o mesmo vale para os itens do `midi_map` (`track`, e o `ref` dos alvos de efeito e de envio; ver [MIDI learn](#midi-learn)). Faixas com id repetido: as referências vão para a primeira. Sidechain não precisa de tratamento, é índice de faixa (ver [Duas armadilhas de compatibilidade](#duas-armadilhas-de-compatibilidade-do-esquema)).
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
| `app/lib/daw/user_presets.dart` (800 linhas na fase 18 A; a fase 18 A acrescentou `MultiBackupStorage` e `PresetRestore`) | `PresetFamily`, `userPresetFormatVersion` (1), `userPresetExtension` (`jopreset`), `maxUserPresetName` (60), `maxUserPresetsPerKind` (300), `maxUserPresetFileBytes` (256 KB), `presetSpecs`, `presetSkipIds`, `presetKindLabel`, `cleanPresetName`, `presetFileName`, `UserPreset`, `PresetFormatException`, `PresetImport`, `UserPresetStorage` (`LocalUserPresetStorage`, `MemoryUserPresetStorage`; ambos com `writeBackup`/`readBackup`), `UserPresets` (`saveError`, `loadNotice`, `problem`, `byId`) | O modelo, a lógica pura (sem `dart:io`, roda igual no dart2js), o guardado e a validação do arquivo |
| `app/lib/daw/user_presets_ui.dart` (431 linhas) | `userPresetEntries`, `handleUserPresetChoice` (e o privado `_warnIfNotStored`), `askPresetName`, `confirmPresetDialog`, `showPresetMessage`, `pickUserPresetFile`, `UserPresetChoice` (`ApplyUserPreset`, `UserPresetMore`, `SaveUserPreset`, `ImportUserPreset`), `SavePresetFile`, `PickPresetFile` | A seção `MEUS PRESETS` dos menus e as janelas |
| `app/lib/daw/instrument_panel.dart` | `_presetControls` (o rótulo, as setas `step`, o menu) | Menu do instrumento: `PopupMenuButton<Object>`, `maxHeight` 460; `MEUS PRESETS` no topo (fase 13) |
| `app/lib/daw/effects_panel.dart` | `_cardMenu` (`maxHeight` 680), `_cardHeader` (subtítulo), `_applyUserPreset` | Menu do cartão de efeito; `MEUS PRESETS` no topo (fase 13) |
| `app/lib/daw/presets.dart`, `fx_presets.dart` | `presetParams`, `matchingPreset`, `matchingEffectPreset` | Os de fábrica, dos quais os do usuário copiam a regra de aplicar e de casar |
| `app/test/user_presets_test.dart` (604 linhas) | 4 grupos | Ver [Como testar](#como-testar-os-presets-do-usuário) |
| `app/test/fase14a_test.dart` | grupo `presets` | Os avisos de gravação e de leitura do guardado, o backup, a versão futura, o `(editado)`, o `Inicial`, o campo de nome e o cancelar do "salvar como" (fase 14 A) |

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

A cópia de um arquivo ilegível vai para a chave `userpresets.bak` (`LocalUserPresetStorage.backupKey`): no Android o nome do arquivo passa por `FileStore.fileName`, que troca o `.` por `%2E`, então o arquivo é `userpresets%2Ebak.txt` (`(lido do código)`); na web é a chave `userpresets.bak` do mesmo object store. Se já existe uma cópia **diferente**, a nova vai para `userpresets.bak.<milissegundos>`; se é igual, não grava de novo (`writeBackup`). `readBackup` devolve a `userpresets.bak`, a mais antiga que ainda existe. Desde a fase 16 (`ffa76ba`) o app lê a cópia e, desde a fase 18 A (`c1fb192`), **todas as cópias**: `LocalUserPresetStorage` implementa também `MultiBackupStorage.readBackups()` (`_store.keys('userpresets.bak')`, filtra a principal e as `userpresets.bak.<número>` de número válido, ordena da mais recente para a mais antiga, com a principal por último, e descarta valor vazio); um guardado que não implementa a interface (o `MemoryUserPresetStorage` dos testes simples) cai em `[readBackup()]`. `load()` guarda `hasBackup = _anyBackup()` (há alguma cópia) **também quando a leitura do arquivo principal lança**, e `restoreFromBackup()` (item `Restaurar presets do backup…`) recupera os presets de todas; as cópias nunca são apagadas. No Android `keys` lista os arquivos `.txt`/`.bin` da pasta e desfaz o nome (`keyOfFileName`).

Ciclo de vida: cada painel (`InstrumentPanel`, `EffectsPanel`) assina o notificador e chama `load()` no `initState`; `load()` roda uma vez (`_loading ??= _load()`), lê e junta ao que já foi salvo na sessão (`insertAll(0, …)`, sem duplicar por id nem por nome). Cada `save`, `rename`, `delete` e `importBytes` chama `_changed()`: notifica e enfileira a gravação do JSON inteiro (`_writes`, uma por vez, a última vence; `flush()` espera as pendentes). A gravação da fila **espera o `load()`** (para não gravar por cima do que ainda não foi lido) e monta o JSON só na hora de gravar, já com o que o carregamento trouxe. Não há servidor: **não sincroniza com a conta** (ideia futura: uma tabela `user_presets` ou uma chave por conta).

Erros e avisos (campos de `UserPresets`; desde `ffa76ba` `problem => saveError ?? (_readOnly ? loadNotice : null)` e `infoNotice => _readOnly ? null : loadNotice`; até a fase 15 `problem` era `saveError ?? loadNotice`, e o arquivo ilegível guardado com sucesso saía como problema):

| Situação | O que o código faz | Texto (exato) |
|---|---|---|
| A gravação falha (`_storage.write` lança) | `saveError` recebe o texto; os presets seguem na memória; notifica só se o valor de `saveError` mudou. A próxima gravação que der certo o zera | `Não deu para guardar seus presets neste aparelho.` |
| A leitura lança (não dá para saber o que há lá) | `_readOnly = true` (nada é gravado até fechar o app) | `Não deu para ler seus presets guardados neste aparelho. O que você salvar agora vale só até fechar o app.` |
| O texto não é JSON, o `format` não é `jopendaw-user-presets` ou a `version` não é inteiro `>= 1` (`_Stored.unreadable`) | `writeBackup(raw)`; se deu certo, a lista começa vazia e a próxima gravação sobrescreve o arquivo (a cópia fica) | `O arquivo dos seus presets estava ilegível. Guardei uma cópia dele (userpresets.bak) e a lista começou vazia.` |
| Ilegível **e** a cópia também falha | `_readOnly = true` | `O arquivo dos seus presets está ilegível e não deu para guardar uma cópia dele. Nada será gravado por cima; o que você salvar vale só até fechar o app.` |
| `version` maior que `userPresetFormatVersion` (`_Stored.future`) | Os presets legíveis entram na lista; `_readOnly = true`: salvar, renomear, apagar e importar valem só na memória | `Seus presets foram guardados por uma versão mais nova do app. Aqui eles ficam só para leitura: o que você salvar, renomear ou apagar vale só até fechar o app.` |

Onde aparece: `userPresetEntries(problem:, notice: infoNotice, hasBackup:)` põe no topo do menu, antes de `MEUS PRESETS`, um item desabilitado para o problema (`ValueKey('user-preset-problem')`, 44 px de altura, texto de 12 px em `Palette.danger`) e, para o `infoNotice`, um item tocável (`ValueKey('user-preset-notice')`, 56 px, ícone `info_outline`, texto cinza com ` (toque para dispensar)` no fim) cujo valor `DismissUserPresetNotice` chama `dismissLoadNotice()` (não tem efeito com `_readOnly`); com `hasBackup`, depois de `Importar preset…`, o item `ValueKey('user-preset-restore')` com o valor `RestoreUserPresets` (`Restaurar presets do backup…`). Depois de salvar, renomear, apagar ou importar, `_warnIfNotStored` faz `await store.flush()` e, se `problem != null`, abre `showPresetMessage` com o título `Presets não guardados`; um `PresetFormatException` de salvar ou renomear faz `return` antes disso.

`restoreFromBackup()` (`Future<PresetRestore>` desde a fase 18 A; antes `({int restored, int skipped})`): `await load()`; lança `PresetFormatException` se `_readOnly` (`Os presets deste aparelho estão só para leitura agora; restaurar não seria gravado.`), se não há cópia não vazia (`Não há cópia de presets neste aparelho.`) ou se `salvage` de todas as cópias juntas não rende nada (`Não consegui recuperar nenhum preset da cópia: o arquivo está danificado demais.`). `PresetRestore {restored, duplicates, overLimit, copies}` (`skipped` = `duplicates + overLimit`): `duplicates` são os que já existiam (mesmo nome no tipo, inclusive o mesmo preset visto em mais de uma cópia), `overLimit` os que passariam de `maxUserPresetsPerKind`; `copies` é quantas cópias foram lidas (a UI não mostra). `salvage` (estático, `@visibleForTesting`) tenta o JSON inteiro e, se falhar, varre o texto atrás de objetos completos com `params` e `kind` (`_objectEnd` casa as chaves respeitando strings), então um arquivo cortado ao meio rende os presets que vieram inteiros; recusa texto acima de 8 MB. Cada preset achado que já existe conta em `duplicates` e, se não, o que passaria do limite conta em `overLimit`; um id já em uso ganha id novo; se `restored > 0`, zera `loadNotice` e chama `_changed()`. A UI (`handleUserPresetChoice`, caso `RestoreUserPresets`) confirma (`Restaurar do backup?`, texto no plural: `... as cópias (a mais recente primeiro) ... As cópias continuam guardadas.`), mostra `Presets restaurados` / `Nada novo para restaurar` (`Nenhum preset da cópia pôde ser somado.`) / `Não foi possível restaurar`, com as frases separadas dos dois contadores (`M já existiam (mesmo nome) e ficaram como estavam.` e `K ficaram de fora porque o tipo já tem o máximo de 300 presets.`), e chama `_warnIfNotStored`. **Incoerência:** quando a leitura do principal lança, `_readOnly` fica verdadeiro e `hasBackup` pode ficar verdadeiro, então o item aparece e o restaurar sempre termina na recusa de só leitura `(lido do código)`.

### O que entra e o que fica de fora

`UserPresets.capture(family, kind, current)` percorre a tabela do tipo e guarda **todo id**, limitado à faixa do `ParamSpec` (`_fit`: fora da faixa vira o limite; não finito vira o padrão; opção de lista é arredondada), menos os ids de `presetSkipIds`:

| Tipo | Fora do preset | Por quê |
|---|---|---|
| `sampler` | `SamplerId.root` (`Nota base`) e `SamplerId.tune` (`Afinação`) | Pertencem ao áudio escolhido (a mesma exceção de `presets.dart`, `_samplerKeeps`) |
| `compressor` | id 10 (`Sidechain`) | Roteamento do projeto |
| `gate` | id 6 (`Sidechain`) | Idem |
| todos | Áudio e zonas do sampler, bypass e posição do efeito, automação | Não são parâmetros da tabela |

Sobram: instrumentos com todos os seus ids (a bateria, 49); o sampler com 9 (`Modo`, `Ataque`, `Decaimento`, `Sustentação`, `Soltura`, `Sens. vel.`, `Volume`, `Alcance do bend`, `Vibrato da roda`); efeitos: EQ 49, compressor 10, gate 6, limitador 5, utilitário 8, reverb 10, delay 12, chorus 7, phaser 7, tremolo 6, distorção 9, filtro 11, multibanda 27, de-esser 8, imagem estéreo 8 (contagens lidas das tabelas de `effects.dart`).

### Aplicar e casar (o rótulo)

`UserPresets.paramsFor(preset, track)` monta o mapa completo `defaultParams(kind)` + valores do preset, mantendo `Nota base` e `Afinação` da faixa no sampler; `paramsForEffect(preset, slot)` monta um mapa com todos os ids do efeito, o `Sidechain` sendo o do slot e o resto `values[id] ?? padrão`. O painel entrega o mapa a `DawController.applyPreset` (instrumento) ou `applyEffectPreset` (efeito): os dois são um passo de `edit()`, então entram no desfazer. Salvar, renomear, apagar e importar **não** passam pelo `DawController`: não entram no desfazer do projeto.

`matchingTrack(track)` e `matchingEffect(slot)` devolvem o primeiro preset do tipo (ordem de criação) cujos valores batem com os da faixa (`|atual − esperado| ≤ 1e-6 · max(1, |esperado|)`, ignorando os ids de fora; o que o preset não cita vale o padrão). Nos painéis, o preset do usuário tem prioridade sobre o de fábrica quando os dois batem (`current = userCurrent == null ? matchingPreset(t) : null`), e só o do usuário leva o visto na linha dele. O rótulo do instrumento é `current?.name ?? (hideUser ? null : userCurrent?.name) ?? (last != null ? '${last.name} (editado)' : (pristine ? 'Inicial' : 'Personalizado'))`, onde `hideUser = userCurrent != null && pristine && last == null`: numa faixa nova (todos os valores no padrão e nenhum preset aplicado nesta sessão do painel) o `Inicial` vale mesmo que exista um preset seu todo no padrão (o visto na linha dele no menu continua, porque `userCurrent` segue indo a `userPresetEntries`); o do efeito não tem `Inicial` nem `Personalizado`. `_lastPreset` (último preset aplicado, por id de faixa ou de slot) vive no `State` do painel e não é salvo; o valor é um registro `({String name, String? userId})`, com `userId` só nos presets do usuário. `_onUserPresets` (o painel assina o notificador) percorre `_lastPreset`: se o `userId` já não existe em `UserPresets.byId`, tira a entrada (o `(editado)` some); se o nome mudou, atualiza o nome (o `(editado)` mostra o novo). As setas do instrumento (`step`) andam por `[...fábrica, ...usuário]` com módulo e acham o preset "de onde se está" pelo `userId` (usuário) ou pelo nome (fábrica, `userId == null`).

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

`userPresetFormatVersion = 1` vale para os dois formatos (o do guardado local, `format: jopendaw-user-presets`, e o do arquivo, `jopendaw-preset`). Uma versão maior que a conhecida é recusada no arquivo `.jopreset`; no guardado local os presets legíveis **entram na lista**, mas o arquivo fica só para leitura (`_readOnly`, ver a tabela de avisos acima): nada é gravado por cima. (`parseStored`, que os testes usam, devolve vazio nesse caso e no ilegível; quem distingue é `_inspect`, que devolve `_Stored.ok`, `future` ou `unreadable` mais os presets.) Campo novo opcional pode entrar sem subir a versão (o leitor ignora chave desconhecida); mudar o significado de um campo pede versão nova. O campo `version` de cada preset no guardado local é escrito mas não é lido (o preset relido sai sempre com a versão 1).

### Leitura do guardado local

`_inspect` (e `parseStored`, `@visibleForTesting`, que o envolve) é tolerante: JSON inválido, `format` diferente ou `version` não inteira ou menor que 1 dão `unreadable` (lista vazia, e o `load` guarda a cópia); versão futura dá `future` com os presets legíveis; entrada que não é objeto, de tipo desconhecido, sem `params`, ou com id repetido é pulada sem afetar as outras. Diferente da importação, ali nada vira aviso (`strict: false`) e um valor ruim é ajustado em silêncio.

### Interface

`userPresetEntries({presets, current, color, checkWidth})` devolve as entradas que os menus põem **no topo**, acima dos de fábrica (desde `18c72f4`, fase 13; antes eram acrescentadas depois, com um divisor na frente): título `MEUS PRESETS`, `Nenhum ainda` (sem presets), uma linha por preset (`ValueKey('user-preset-<id>')`, valor `ApplyUserPreset`; o `…` tem `ValueKey('user-preset-more-<id>')`, tooltip `Renomear, apagar ou exportar` e valor `UserPresetMore`), divisor, `Salvar como preset…` (`user-preset-save`), `Importar preset…` (`user-preset-import`) e um divisor final (`PopupMenuDivider(height: 8)`) que já separa dos de fábrica. Os menus só a espalham no começo da lista de itens: em `instrument_panel.dart`, `entries = [...userPresetEntries(...)]` e as categorias de fábrica (com o divisor entre categorias e o título `p.category.toUpperCase()`) vêm depois; em `effects_panel.dart`, `itemBuilder` começa por `...userPresetEntries(...)`, depois o título `PRESETS` e a lista de fábrica com um `PopupMenuDivider()`, e então as ações do cartão. No painel de efeitos, `checkWidth` é 30 (alinha com os de fábrica) e as ações do cartão (`Reiniciar…`, bypass, mover, `Remover`) seguem no fim, como antes. A ordem das setas `step` do instrumento **não** mudou (fábrica e depois os do usuário; `[...list, ...userList]`), então já não acompanha a ordem visual do menu. Ambos os menus passam a ser `PopupMenuButton<Object>`, e o `onSelected` despacha por tipo: `Preset`/`EffectPreset` (fábrica), `ApplyUserPreset` (cada painel aplica), `UserPresetChoice` (`handleUserPresetChoice`).

`handleUserPresetChoice(context, choice, {family, kind, capture, presets, save, pick})`: o gerenciador, o `save` (padrão `AudioEngine.instance.saveFile`) e o `pick` (padrão `pickUserPresetFile`) são injetáveis para os testes. Fluxos: `Salvar` chama `askPresetName` (`_NameDialog`: título `Salvar como preset`, campo `Nome` com `maxLength` 60, contador oculto, filtro que nega exatamente o que `cleanPresetName` trocaria por espaço (`FilteringTextInputFormatter.deny`: U+0000–U+001F, U+007F–U+009F, U+2028, U+2029, U+200B–U+200F, U+202A–U+202E e U+FEFF; o nome guardado é o digitado), botão `Salvar` desabilitado com nome vazio, `Enter` confirma) e `UserPresets.save`; nome em uso devolve `null` e abre `confirmPresetDialog` (`Substituir o preset?`, `Substituir`), que chama `save(..., replace: true)` (mantém id, nome e data). `Renomear…`: `askPresetName(title: 'Renomear preset', confirm: 'Renomear', initial: nome)`; `rename` devolve `false` se **outro** preset do tipo tem o nome (`Nome em uso`). `Apagar…`: `Apagar o preset?` com botão vermelho `Apagar`. `Exportar preset…`: `presetFileName` e `exportBytes` para `save` (`SavePresetFile` devolve `Future<Object?>`: o `saveFile` do motor devolve `bool`); se devolve `false` (a pessoa cancelou o "salvar como", Android), abre `Exportação cancelada` com `O preset "nome" não foi exportado.`; exceção vira `Não foi possível exportar`. `Importar preset…`: `FilePicker.pickFiles(dialogTitle: 'Importar preset', type: custom, allowedExtensions: [jopreset, json])`, cancelar não muda nada; `importBytes`; a janela `Preset "nome" importado` só abre se houver avisos ou se o preset for de outro tipo (`O preset é de outro tipo (Reverb): ele foi guardado, mas só aparece no menu desse tipo.`, com o nome em português de `presetKindLabel`: `TrackKind.label` ou `EffectKind.label`, e o nome interno se o tipo é desconhecido). Depois de salvar, renomear, apagar e importar, `_warnIfNotStored` (ver acima). Erros em diálogo (`showPresetMessage`, botão `Ok`), nunca toast.

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
# os avisos, o backup, a versão futura, o (editado), o Inicial e o campo de nome (fase 14 A): grupo `presets` de test/fase14a_test.dart
cd app && flutter test test/fase14a_test.dart
```

Grupos: `nomes` (limpeza, 60 caracteres, nome hostil), `guardado` (ida e volta do arquivo local, capturar e aplicar são a identidade em todos os instrumentos e nos 15 efeitos, o EQ leva as 8 bandas, sidechain e `Nota base`/`Afinação` ficam como estão, substituir/renomear/apagar, nome único, limite de 300, arquivo local corrompido ou de versão futura, guardado que falha), `.jopreset` (exportar e importar, sufixo ` (2)`, arquivos ruins, `NaN`, infinito e valores enormes, nome hostil, sampler ignora `Nota base` e `Afinação` do arquivo) e `menu (widget)` (instrumento, efeito, celular estreito com nome comprido, importar pelo menu, exportar pelo `saveFile` injetado; os testes trocam `UserPresets.instance` por um em memória). O grupo `presets` de `fase14a_test.dart` cobre: a falha de gravação (`problem` mostra o aviso e a tela é notificada), o arquivo ilegível indo para o backup antes de qualquer gravação, a versão futura (mostra o que dá, não sobrescreve e avisa), o nome do tipo em português, apagar o preset aplicado tirando o `(editado)` e renomear atualizando o nome, a faixa nova valendo `Inicial`, o menu com o aviso quando não guarda, a importação de outro tipo com o nome em português, o cancelar do "salvar como" e o campo de nome barrando marcas de largura zero e de direção `(testado só por testes automáticos)`. A sessão de código relatou o uso no Chrome (salvar `Meu baixo grave` e o preset aparecer marcado com o visto), `(não repetido por quem escreveu esta documentação)`; o Android e o seletor de arquivos reais só têm teste automático `(testado só por testes automáticos)`. A fase 18 A acrescenta em `test/fase18a_test.dart` o grupo `presets do usuário` (restaurar separando `duplicates` de `overLimit`, `hasBackup` com a leitura do principal falhando e a leitura das cópias extras da mais recente para a mais antiga, com um guardado de teste que implementa `MultiBackupStorage`) e o grupo `avisos` (o aviso do controlador some em 6 s e o texto novo tem o seu tempo) `(testado só por testes automáticos)`.

### Armadilhas dos presets do usuário

- **Resolvido em `504b4b8` (fase 14 A), o que esta seção listava:** `saveError` sem tela (agora o menu mostra o texto em vermelho e a ação abre `Presets não guardados`); arquivo ilegível ou de versão futura tratado como vazio e sobrescrito pela próxima gravação (agora vai para o backup `userpresets.bak` ou fica só para leitura); o `_lastPreset` do painel não limpo ao apagar nem ao renomear (o `(editado)` some ou segue o nome novo); preset todo no padrão passando na frente de `Inicial` numa faixa nova; o campo de nome aceitando marcas invisíveis; o aviso de importação citando o nome interno (`reverb`); e cancelar o "salvar como" do Android voltando em silêncio (`Exportação cancelada`).
- **Resolvidas em `ffa76ba` (fase 16 A):** o aviso de carregamento do arquivo ilegível guardado com sucesso deixou de ser `problem` (não sai mais em vermelho nem abre `Presets não guardados`; é o `infoNotice` cinza e dispensável); a cópia `userpresets.bak` ganhou tela de recuperação (`Restaurar presets do backup…`). **Resolvido em `c1fb192` (fase 18 A):** só a cópia principal era lida (agora todas, `MultiBackupStorage`); o texto de `skipped` da UI dizia `já existia (mesmo nome)` também para o preset que ficou de fora pelo limite de 300 por tipo (agora dois contadores, `duplicates` e `overLimit`, com frases próprias); `hasBackup` só era preenchido se o arquivo principal abrisse (agora também quando a leitura lança, com a incoerência descrita acima); cópias extras `userpresets.bak.<ms>` eram ignoradas.
- **Só leitura vale por sessão do app.** Ao reabrir o app com o arquivo de versão futura, o aviso volta e nada é gravado; o app não tem ação para "converter" o arquivo, e nada do que se fez na sessão é gravado.
- **Importar sem ressalvas não avisa.** A janela só abre com avisos: o único sinal de sucesso é a linha nova na seção `MEUS PRESETS` (e no menu de outro tipo, se o arquivo era de outro tipo, a mensagem cita o nome do tipo em português, como `Reverb`).
- **`userpresets` é global do aparelho**: não entra na chave nenhum id de conta e o `purgeLocalProject` e o sair da conta não mexem nele.
- **`UserPresets.instance` é estático**: testes de painel que não o troquem por um `UserPresets(MemoryUserPresetStorage())` leem o `LocalStore` de verdade.

## Atalhos personalizáveis (`keymap.dart`, `keymap_ui.dart`)

> Fase 16 (C), commit `e8c613a`, integrado em `53ca96d`: o catálogo único de ações do estúdio, o `Keymap` que resolve tecla em ação com as personalizações por cima, o guardado local, o arquivo `.jokeys` e a tela de personalizar. Para quem mexe no app; o uso está em [manual 09, Personalizar os atalhos](../manual/09-configuracoes-atalhos-android.md#personalizar-os-atalhos). Só há testes automáticos; nada foi visto no navegador por quem escreveu esta documentação `(testado só por testes automáticos)`.

### Peças

| Arquivo | Símbolos | Papel |
|---|---|---|
| `app/lib/daw/keymap.dart` (1079 linhas na fase 18 A) | Na fase 18 A entraram: `KeymapImportPlan` (`planImport`/`applyImport`/`undoImport`/`canUndoImport`), `Keymap.hintOf` e os atalhos de topo `shortcutHint`/`shortcutLabel`, `KeyboardLayoutHints` (layout aprendido dos eventos, `labelFor`, `physicalKeyboardSeen`), `shortcutsNeedKeyboardHint`, `suspendedKeysLabel` e `keyboardTooltip` (que morava em `widgets/format.dart`). Antes: `KeyContext`, `KeyCategory`, `KeyAction`, `keyCatalog` (`:75`, 56 ações desde a fase 17), `keyActionById`, `keyTokens`, `physicalKeyToken`, `isModifierKey`, `KeyCombo` (`fromKey`, `parse`, `toString`, `label`), `tokenLabel`, `reservedReason`, `noteKeyLetters`, `maxBindingsPerAction` (3), `AssignStatus`/`AssignCheck`, `KeymapFormatException`, `KeymapImport`, `KeymapStorage` (`LocalKeymapStorage`, `MemoryKeymapStorage`), `keymapFormatVersion` (1), `keymapExtension` (`jokeys`), `maxKeymapFileBytes` (256 KB), `Keymap` (`instance`, `resolve`, `playingAction`, `check`, `conflictOf`, `assign`, `removeBinding`, `reset`, `resetAll`, `load`, `flush`, `exportBytes`, `importBytes`, `parseStored`), `logicalKeyForToken` | Lógica pura (sem `dart:io`, sem operador de bit: roda igual no dart2js): o catálogo, a tecla como texto, as regras e o guardado |
| `app/lib/daw/keymap_ui.dart` (530 linhas) | `KeymapEditor`, `pickKeymapFile`, `foldForSearch`, `SaveKeymapFile`, `PickKeymapFile`, `keymapMime` | A tela de personalizar (regravar, conflito, restaurar, busca, exportar, importar) |
| `app/lib/daw/shortcuts_dialog.dart` (193 linhas) | `shortcutGroups(Keymap)`, `suspendedShortcutsOf(Keymap)`, `canCustomizeShortcuts`, `showShortcuts`, `ShortcutsDialog` | A janela `?` gerada do catálogo; o botão `Personalizar`; o texto dos mouse e menus (`_extras`) |
| `app/lib/screens/project_screen.dart` | `_DawStudioState.initState` (`Keymap.instance.load()`), `_actionFor(id, node)` (`:131`), `_onKey` (`:210`) | Camada do estúdio: resolve a tecla e roda a ação do id |
| `app/lib/daw/piano_roll_input.dart` | `_handleKey` (`switch (hits.first.id)`, `:1139`) | Camada do piano roll |
| `app/lib/daw/controller.dart` | `_isKeyboardKey`, `handleNoteKey` (`Keymap.instance.playingAction(key)`) | Camada do teclado tocando (oitava e velocidade) |
| `app/test/keymap_test.dart` (1071 linhas), `app/test/fase18a_test.dart` (grupo `atalhos`), `app/test/keyboard_test.dart` | Ver [Como testar](#como-testar-os-atalhos-personalizáveis) | |

### Modelo

`KeyAction {id, label, help, category, context, defaults, fixed, exactShift}`: o `id` é **estável** (vai para o arquivo; nunca renomear, ação nova ganha id novo); `label` é o texto da tela de personalizar; `help` é o texto mais longo da janela `?` (`helpText` cai no `label`); `defaults` são atalhos em texto no formato de `KeyCombo.parse`; `fixed` marca o `Esc` (aparece, mas não muda nem conflita: `midilearn.cancel`, `panel.close`, `pr.deselect`); `exactShift` diz que o `Shift` a mais **invalida** a tecla (`pr.quantize`, `pr.split`, `pr.join`: `K` divide, `Shift+K` é outra coisa). `KeyContext` (`global`, `arrangement`, `pianoRoll`, `playing`) e `KeyCategory` (`transport`, `markers`, `view`, `edit`, `panels`, `midiLearn`, `keyboard`, `pianoRoll`; a ordem do enum é a ordem dos grupos da janela).

O catálogo tem 57 ações desde a fase 18 C (56 até a fase 18 A; a nova é `history.open`, `Mod+Shift+H`, em `Geral`, logo depois de `edit.import`: [histórico e versões](#histórico-com-nomes-e-versões-nomeadas-fase-18-c); a contagem por grupo a seguir é a de antes dela) (Geral 27, Arranjo 5, Piano roll 20, Teclado tocando 4; `transport.punch` `P` e `transport.tap` `T` entraram na fase 17, logo depois de `transport.metronome`) e a **ordem dele importa**: é a ordem da janela, desempata conflitos na importação (`_sanitize`) e decide a ordem em que `resolve` devolve ações da mesma combinação (só o `Esc` tem mais de uma: `midilearn.cancel` vem antes de `panel.close`, de propósito, para que com o modo ligado e um painel aberto o `Esc` cancele primeiro o controle armado; `_actionFor` devolve `null` quando a ação não se aplica ao estado e o laço passa à seguinte).

**A tecla é texto, não `keyId`.** `KeyCombo {token, mod, shift, alt}`: `mod` é Ctrl **ou** Cmd (valem os dois, em qualquer sistema). O texto é `[Mod+][Shift+][Alt+]<token>`; `parse` aceita os modificadores em qualquer ordem, uma vez cada, e é sensível a maiúsculas; `toString` escreve sempre na ordem `Mod`, `Shift`, `Alt`. Os tokens válidos são os de `_logicalToToken` (`keyTokens`): `A` a `Z`, `0` a `9`, `Space`, `Enter`, `Home`, `End`, `PageUp`, `PageDown`, `Delete`, `Backspace`, `Escape`, `Tab`, `Up`, `Down`, `Left`, `Right`, `F1` a `F12`, `[`, `]`, `=`, `-`, `+`, `?`, `/`, `,`, `.`, `;`, `'`, `\`, `` ` ``. `?` e `+` já trazem o Shift no caractere (`_shiftFree`): `parse` recusa `Shift+?` e `Shift++`, e `fromKey` apaga o `shift` deles e vê `Shift+/` como `?`; desde a fase 18 A o `parse` faz o mesmo com a forma escrita: `Shift+/` (e `Mod+Shift+/`) vale como `?` (`Mod+?`), e a importação avisa. O `-` e o `+` do teclado numérico mapeiam para os mesmos tokens. `KeyCombo.label` é o texto da tela (`Ctrl` ou `⌘` por `modKey`, `Espaço`, `Esc`, setas `↑↓←→`, `−`).

**Teclado tocando por posição.** As ações `kbd.octaveDown/octaveUp/velocityDown/velocityUp` (contexto `playing`) são presas à tecla **física** (`_physicalToToken`, só letras e dígitos): o teclado de notas é por posição, não pelo layout. `Keymap.playingAction(PhysicalKeyboardKey)` devolve a ação; `DawController.handleNoteKey` faz um `switch` no id. As 16 notas (`noteKeyLetters`, igual a `noteKeys` do controlador: um teste confere) **não são ações**. Desde a fase 18 A o **rótulo** dessas ações (`Keymap.labelOf`, no contexto `playing`) e o das notas na janela `?` passam por `KeyboardLayoutHints.labelFor(token)`: o singleton escuta `HardwareKeyboard` (instalado em `DawStudio.initState`), aprende a letra real de cada tecla física a partir do `logicalKey.keyLabel` dos `KeyDownEvent` (`learn(physical, logical)`) e escreve `<letra real> (posição do <token>)` quando difere do QWERTY; antes da primeira tecla vale o token. O token guardado e o arquivo `.jokeys` seguem sendo o do QWERTY; os chips da tela de personalizar (`bindings[i].label`) **não** passam pelo aprendizado.

### Resolver: `Keymap.resolve(stroke, layer)`

O índice `combinação → ações` é montado por **camada** (`_scope`: `global` e `arrangement` = 0, `pianoRoll` = 1, `playing` = 2) e refeito a cada mudança. `resolve`:

1. Combinação exata no índice da camada: devolve as ações dela.
2. Senão, tolera o que sobrou: tira o `Shift`, depois o `Alt`, depois os dois (`Shift+R` também grava, como sempre); as teclas de `_modifierAgnostic` (`Space`, `Enter`, `Home`, `Delete`, `Backspace`, `Escape`, `=`, `+`, `-`, `?`) toleram também o `Mod` a mais. Quando o `Shift` foi tirado, as ações com `exactShift` saem do resultado. Uma combinação exata de outra ação sempre vence, porque a busca exata vem antes.
3. Sem nada: lista vazia.

A tolerância existe para o comportamento **idêntico ao de antes** nos padrões (o `if` encadeado antigo não olhava `Shift` nem `Alt` na maioria das teclas).

**Quem chama, em camadas** (`project_screen.dart::_onKey`): `_typing()` → nada; teclado tocando (se ligado, sem Ctrl/Cmd, `handleNoteKey`); `editorKeyHandler` (piano roll ativo, `_handleKey`: `resolve(stroke, KeyContext.pianoRoll)` e um `switch` no `hits.first.id`; ação que "não se aplica" devolve `false`, e a tecla segue); por fim `resolve(stroke, KeyContext.global)`, e para cada ação `_actionFor(a.id, node)` devolve a função ou `null`; a primeira função não nula roda e a tecla é consumida. Sem função, `KeyEventResult.ignored` (o navegador vê a tecla).

### Regras de atribuição

`Keymap.check(id, combo)` devolve `AssignCheck(status, reason, other)` com `AssignStatus`: `notEditable` (ação fixa ou id desconhecido), `reserved` (`reservedReason`), `already` (a ação já tem a combinação), `conflict` (outra ação editável da mesma camada tem), `ok`. Ordem: não editável, reservada, já tem, conflito.

`reservedReason(combo, context)`: `Escape`; `Tab`; `F5`, `F11`, `F12` (qualquer modificador); `Alt+F4`; `Mod` + `R`/`W`/`T`/`N`/`Q` (sem `Alt`); `Mod` + `1` a `9`; e, no contexto `playing`, qualquer modificador, tecla que não é letra ou dígito e as 16 letras de nota. As mensagens exatas estão no [manual 09](../manual/09-configuracoes-atalhos-android.md#teclas-reservadas). A **mesma função** filtra o arquivo importado.

`assign(id, combo, {slot, swap})`: `already` devolve `true` sem mudar; reservada e não editável devolvem `false`; `slot` dentro da lista **troca** aquele atalho, sem `slot` ou fora dela **acrescenta** (recusa acima de `maxBindingsPerAction` = 3); com conflito só grava se `swap`: a outra ação recebe o atalho que esta tinha no `slot` (`old`), ou perde a combinação se `old` era nulo ou ela já o tinha. `removeBinding` tira o índice; `reset(id)` volta ao padrão e, se outra ação tomou algum padrão dela, **a outra perde a tecla**; `resetAll` limpa. `_setCustom` guarda só a **diferença**: uma lista igual ao padrão remove a chave (lista vazia é "sem atalho" e é guardada).

### Guardado local

`Keymap.instance` (estático; os testes trocam por `Keymap(MemoryKeymapStorage())`) usa `LocalKeymapStorage`, que fala com o `LocalStore` (web: IndexedDB `jopendaw`, repositório `kv`; Android: `FileStore` em `<documentos do app>/jopendaw/`; outros sistemas: nada é guardado). Chave `keymap`, um texto JSON compacto:

```json
{"format":"jopendaw-keymap","version":1,"bindings":{"panel.mixer":["B"],"transport.metronome":[]}}
```

Só as ações que **diferem** dos padrões, na ordem do catálogo. A cópia de um arquivo ilegível vai para `keymap.bak` (no Android, `FileStore.fileName` troca o `.` por `%2E`: `keymap%2Ebak.txt`); se já existe uma cópia **diferente**, a nova vai para `keymap.bak.<milissegundos>`; se é igual, não grava de novo. Nada lê a cópia de volta.

`load()` (`_loading ??= _load()`, chamado pelo `initState` de `DawStudio` e da janela) lê e classifica com `_inspect`: `unreadable` (não é JSON, `format` diferente de `jopendaw-keymap`, `version` não inteira ou menor que 1, `bindings` que não é objeto), `future` (`version` maior que 1) ou `ok`. Avisos (campos `loadNotice`, `saveError`; `problem => saveError ?? loadNotice`):

| Situação | O que o código faz | Texto (exato) |
|---|---|---|
| A leitura lança | `_readOnly = true` (nada é gravado até fechar o app) | `Não deu para ler seus atalhos guardados neste aparelho. O que você mudar agora vale só até fechar o app.` |
| `unreadable` e a cópia deu certo | Cópia em `keymap.bak`; começa nos padrões e a próxima gravação sobrescreve o arquivo | `O arquivo dos seus atalhos estava ilegível. Guardei uma cópia dele (keymap.bak) e voltei aos atalhos padrão.` |
| `unreadable` e a cópia falhou | `_readOnly = true` | `O arquivo dos seus atalhos está ilegível e não deu para guardar uma cópia dele. Nada será gravado por cima; o que você mudar vale só até fechar o app.` |
| `future` | As personalizações legíveis entram; `_readOnly = true` | `Seus atalhos foram guardados por uma versão mais nova do app. Aqui eles ficam só para leitura: o que você mudar vale só até fechar o app.` |
| A gravação lança | `saveError`; as mudanças seguem valendo; a próxima gravação que der certo o zera | `Não deu para guardar seus atalhos neste aparelho. Eles valem só até fechar o app.` |

Cada mudança (`_changed`) esvazia o índice, notifica e enfileira `_persist` (uma gravação por vez, a última vence; `flush()` espera as pendentes, para os testes). Desde a fase 18 A o `_persist` **espera o `load()`** antes de gravar (e só então olha `_readOnly`), então uma mudança feita antes de o carregamento acabar não sobrescreve o guardado; e o que já foi mudado na sessão vale mais que o lido: `_mergeStored` aplica do guardado só as ações que a sessão não tocou e **descarta** a combinação guardada que uma ação mudada na sessão já usa na mesma camada (`_scope`), contando quantas; se descartou alguma, `loadNotice` vira `Um atalho guardado foi descartado porque você já o usou em outra ação nesta sessão, antes de o carregamento terminar.` (`N atalhos guardados foram descartados ...`), que **substitui** um `loadNotice` anterior do mesmo carregamento (o de arquivo ilegível ou de versão futura) `(lido do código)`. Antes (fases 16 e 17) `_persist` não esperava o `load` e a fusão era `putIfAbsent` sem checar conflito.

### Formato do arquivo `.jokeys`, campo a campo

JSON UTF-8 com recuo de 2 espaços (`exportBytes`), nome `atalhos.jokeys`, tipo de mídia `application/octet-stream` (`keymapMime`, de propósito, como o `.jopendaw` e o `.jopreset`). A tela aceita `.jokeys` e `.json` ao importar.

| Campo | Tipo | Regra na importação |
|---|---|---|
| `format` | texto | Tem de ser `jopendaw-keymap-file` (o do guardado local é outro: `jopendaw-keymap`); senão `O arquivo não é de atalhos do jopendaw.` |
| `version` | inteiro | `>= 1` e `<= keymapFormatVersion` (1). Menor que 1 ou não inteiro: `O arquivo tem uma versão de formato inválida.`; maior: `Os atalhos são de uma versão mais nova do jopendaw. Atualize o app para importá-los.` |
| `bindings` | objeto `{"<id>": ["<tecla>", ...]}` | Tem de ser objeto (`O arquivo não tem a lista de atalhos.`). Cada chave é o `id` de uma ação; o valor, a lista **completa** de atalhos dela (não é um acréscimo); `[]` = sem atalho; ação ausente = padrões |

Recusas antes de olhar o conteúdo, todas por `KeymapFormatException` (mensagem mostrada como `Não foi possível importar: <mensagem>`): mais de 256 KB (`O arquivo é grande demais para ser de atalhos.`) e não ser UTF-8/JSON (`O arquivo não é de atalhos do jopendaw (não é um JSON válido).`). O resto vira **avisos** (`KeymapImport.warnings`, uma linha `•` na tela) e o arquivo é aproveitado: `_parseBindings` descarta id desconhecido, ação fixa, valor que não é lista, tecla inválida (`KeyCombo.parse` nulo), tecla reservada (`reservedReason`), mais de 3 teclas (as 3 primeiras ficam) e repetidas (sem aviso); uma lista igual ao padrão da ação não entra. `_sanitize` tira **conflitos**: entre ações personalizadas vale a primeira do catálogo (`<tecla> já é de "<a>"; descartada em "<b>".`), e sobre o padrão de uma ação **não** citada vale o arquivo (a outra perde a tecla: `"<b>" perdeu <tecla>, que agora é de "<a>".`). O conjunto **substitui** as personalizações de agora (`_custom..clear()..addAll`) e grava. Desde a fase 18 A a importação tem dois tempos: `planImport(bytes)` lê e valida sem aplicar e devolve `KeymapImportPlan` (`custom` já limpo, `warnings`, `replacing` = quantas ações estão personalizadas agora; `incoming` = `custom.length`), e `applyImport(plan)` aplica, guarda em `_beforeImport` uma cópia das personalizações de antes e grava; `importBytes` é os dois juntos. `undoImport()` devolve a cópia (`_changed(keepUndo: true)`) e a zera; qualquer outro `_changed()` (atribuir, remover, restaurar, nova importação) zera `_beforeImport` (`canUndoImport` fica falso). A cópia é só em memória: não sobrevive a fechar o app. A tela pede `Importar atalhos?` entre o `planImport` e o `applyImport` e o aviso do resultado ganha `Desfazer importação` (ver Interface). `KeymapImport.applied` é o número de ações personalizadas depois da limpeza. O aviso `"<texto>" em "<ação>" vale como ?, que é o que o teclado envia.` nasce em `_parseBindings` quando o token vira `?` e o texto escrito tinha `/`.

### Versionamento

`keymapFormatVersion = 1` vale para os dois formatos (`jopendaw-keymap` local e `jopendaw-keymap-file`). Campo novo opcional pode entrar sem subir a versão (o leitor ignora chave desconhecida da raiz); mudar o significado de um campo, ou de um token, pede versão nova. **Ids de ação e tokens são o contrato:** id novo é aceito por um app novo e vira `Ação desconhecida … ignorada` num antigo (aviso, não erro); renomear um id **apaga** silenciosamente a personalização de quem tinha.

### Interface (`keymap_ui.dart`, `shortcuts_dialog.dart`)

`showShortcuts(context, {canCustomize, keymap})`: `canCustomizeShortcuts` é `true` desde a fase 18 A (antes `kIsWeb || (plataforma != android && != iOS)`: o app Android não tinha o botão mesmo com teclado físico), então o botão `Personalizar` (`ValueKey('shortcuts-customize')`) existe em todo aparelho. Quem decide se a personalização "serve" é `shortcutsNeedKeyboardHint(physicalKeyboardSeen)`: `true` em Android ou iOS (`defaultTargetPlatform`, então também no navegador do celular) enquanto `KeyboardLayoutHints.physicalKeyboardSeen` é falso (nenhum `KeyDownEvent` ainda); o `KeymapEditor` mostra então o `InlineNotice` neutro `Regravar atalhos precisa de um teclado físico e nenhum foi detectado neste aparelho. ...`. A janela alterna `_customizing`: título `Atalhos do teclado`/`Personalizar atalhos`, botão `Personalizar`/`Voltar à lista`, corpo `_list` (`ListenableBuilder` no `Keymap`) ou `KeymapEditor`.

`KeymapEditor` (um `Focus` próprio em volta de tudo): `_rec` é o `_Target(id, slot)` em gravação, `_conflict` o `_Conflict(target, combo, other)`, `_refusal` o texto vermelho da linha. `_onKey`: `KeyUp` e modificador sozinho são engolidos; `Esc` cancela; `Backspace`/`Delete` sem modificador remove (só sem conflito aberto); com conflito aberto, o resto é engolido; no contexto `playing` o token vem da tecla **física** (`physicalKeyToken`), nos outros `KeyCombo.fromKey` (tecla que o app não conhece: `Essa tecla não pode ser usada em atalhos. Tente outra.`); depois `Keymap.check` decide (`reserved` → `_refusal`; `conflict` → caixa `Trocar`/`Cancelar`; `ok` e `already` → `assign` e sai). `_swap` chama `assign(..., swap: true)`. Chaves dos testes: `keymap-search`, `keymap-reset-all` (`keymap-reset-all-confirm`), `keymap-export`, `keymap-import`, `bind-<id>-<slot>`, `add-<id>`, `reset-<id>`, `conflict-<id>`, `conflict-swap`, `conflict-cancel`, `refusal-<id>`, `keymap-empty`. Layout estreito abaixo de 460 px (chips embaixo do nome); a janela `?` fica estreita abaixo de 520 px.

Exportar: `AudioEngine.instance.saveFile('atalhos.jokeys', bytes, keymapMime)` (na web sempre devolve `true`; `false` só onde o sistema informa cancelamento, e vira `Exportação cancelada: nada foi salvo.`). Importar: `pickKeymapFile()` (`FilePicker.pickFiles`, `dialogTitle: 'Importar atalhos'`), depois `planImport` (uma `KeymapFormatException` vira o aviso vermelho sem diálogo), `_confirmImport` (`AlertDialog` `Importar atalhos?`, chaves `keymap-import-cancel` e `keymap-import-confirm`; texto `<arquivo>: N atalhos serão trocados. <Você não tem personalizações agora. | As suas N personalizações atuais serão descartadas.> Dá para desfazer logo depois, nesta sessão.` mais, se há avisos, `N avisos (o que não vale no arquivo é descartado).`) e `applyImport`. O `InlineNotice` do resultado ganha `actionLabel: 'Desfazer importação'` (`_undoImport`: `Importação desfeita: seus atalhos de antes voltaram.`) enquanto `km.canUndoImport` e a nota não é erro; a nota vive no estado do `KeymapEditor`, então fechar a tela perde o botão mesmo que o `_beforeImport` siga no `Keymap`. Os dois são injetáveis (`save`, `pick`) para os testes.

A **busca** (`_matches`) usa `foldForSearch` (minúsculas e sem os acentos `áàâãäéèêëíìîïóòôõöúùûüçñ`) sobre `rótulo + título do grupo + contexto + teclas de agora`; todas as palavras têm de aparecer.

A **janela `?`** é `shortcutGroups(km)`: para cada `KeyCategory`, uma linha por ação (`km.labelOf(id, none: '—')` com ` · ` trocado por `  ·  `, mais `helpText`), depois as linhas de `_extras()` (mouse e menus, texto fixo). O título do grupo `keyboard` é `Teclado do computador (<teclas do kbd.toggle> liga)`, ou só `Teclado do computador` se o `kbd.toggle` ficou sem atalho (fase 18 A; antes saía `Sem atalho liga`). O grupo final `Suspensos…` sai de `suspendedShortcutsOf(km)` (ver [manual 09](../manual/09-configuracoes-atalhos-android.md#janela-atalhos-do-teclado)) mais as linhas `Com <modKey>` (com texto próprio se o `kbd.toggle` está sem atalho) e `Com Shift` (`Não muda nada: Shift+L toca a nota L, como L. ...`, fase 18 A). `_extras()` ganhou a linha das letras de nota pelo `labelFor` e, se `KeyboardLayoutHints.differsFromQwerty`, a linha `Por posição`. O texto do tooltip do botão do teclado vem de `keyboardTooltip` (em `keymap.dart`, dinâmico: `suspendedKeysLabel`, `labelOf` das ações de oitava e velocidade e do `kbd.toggle`).

### Oráculo de equivalência com o tratamento de antes

O compromisso da fase: **nos atalhos padrão, cada tecla faz exatamente o que fazia antes.** O `keymap_test.dart` guarda, copiadas como estavam, as duas cadeias de `if` antigas (`legacyGlobal`, de `project_screen.dart`, e `legacyRoll`, de `piano_roll_input.dart`) e compara com o novo (`nowGlobal`, `nowRoll`, que aplicam as mesmas regras de estado que a tela: gravando, modo Aprender MIDI ligado, painel aberto, seleção vazia, bateria). Três testes: (1) cada tecla padrão do catálogo dispara a mesma ação que antes; (2) a **varredura** de todos os tokens × `Ctrl` × `Shift` × `Alt` × gravando × aprendendo × painel aberto (mais de 3000 combinações) dá o mesmo resultado; (3) o piano roll idem (tokens × `Ctrl` × `Shift` × `Alt` × seleção vazia × bateria). Mais: `Shift+=` é `+`, `Shift+/` é `?`, o `-` e o `+` do numérico, e `Espaço`/`Enter`/`Home`/`Delete`/`Backspace` com qualquer modificador.

O que o oráculo **não** cobre: `nowGlobal` e `nowRoll` são a reimplementação, no teste, da regra de estado, então ele prova o `Keymap.resolve` e o catálogo, **não** o `switch` de `_actionFor` nem o de `_handleKey` (o teste de tela só exercita algumas ações). `(lido do código)`

### Como registrar uma ação nova no catálogo (checklist)

1. **`keymap.dart`, `keyCatalog`:** acrescente `KeyAction('grupo.nome', 'Rótulo', KeyCategory.x, KeyContext.y, ['Mod+Shift+K'])`. O id é para sempre. Escolha a posição com cuidado: ela é a ordem da janela e o desempate do conflito. Os padrões têm de ser válidos (`KeyCombo.parse` devolve a mesma forma canônica), **não reservados** (exceto ações `fixed`) e sem repetir combinação na mesma camada (geral e arranjo dividem uma). `help:` só se a janela precisa de texto mais longo; `exactShift: true` se o `Shift` a mais deve invalidar; padrão `[]` para "sem atalho" (como `view.follow`).
2. **Faça algo com o id**, na camada certa: contexto `global`/`arrangement` → um `case` em `_actionFor` (`project_screen.dart`) devolvendo a função (ou `null` quando não se aplica ao estado); `pianoRoll` → um `case` no `switch (hits.first.id)` de `_handleKey` (`piano_roll_input.dart`), lembrando do `repeat` e de `return false` se a ação não se aplica; `playing` → um `case` em `DawController.handleNoteKey`. **Esquecer isso agora quebra um teste** (fase 18 A): `fase18a_test.dart`, `(3) toda ação do catálogo tem tratamento nos switches das telas`, lê o texto de `_actionFor`, de `_handleKey` e de `handleNoteKey` e exige o id de cada ação do catálogo, e o inverso (nenhum `case` de id que o catálogo não conhece). É um teste por **texto do código-fonte** (regex sobre `'grupo.nome'` entre marcadores de trecho), não de comportamento: mover os trechos de lugar o quebra `(testado só por testes automáticos)`.
3. **`shortcuts_dialog.dart`:** a janela e o grupo `Suspensos…` já leem o catálogo; só acrescente uma linha de `_extras()` se a ação tem um gesto de mouse ou menu para descrever.
4. **Tooltips e dicas de menu:** desde a fase 18 A eles leem o `Keymap` (`shortcutHint(id)` devolve ` (L)` ou `''`; `shortcutLabel(id, none:)` devolve o texto puro para o atalho à direita de itens de menu): `transport_bar.dart`, `dock.dart`, `structure_menu.dart`, `timeline.dart`, `mixer_panel.dart`, `settings_dialog.dart`, `piano_roll_tools.dart`, `piano_roll.dart::_help`, `midi_learn_ui.dart` e `keyboardTooltip`. Se a sua ação ganha um tooltip com a tecla, use `shortcutHint('id')` em vez de escrever a tecla; o teste `(1) nenhum texto de dica escrito à mão...` só vigia `Loop`, `Metrônomo`, `Mixer`, `Fechar o painel` e `Punch` em `transport_bar.dart`, `dock.dart` e `structure_menu.dart`. A tela do projeto escuta `Keymap.instance` e `KeyboardLayoutHints.instance` (`Listenable.merge` em `project_screen.dart`), então personalizar refaz os textos na hora.
5. **Testes:** a varredura do oráculo cobre o padrão sozinha (ela pega uma tecla nova que muda o comportamento antigo: **atualize `legacyGlobal`/`legacyRoll` só se a mudança de comportamento for de propósito**); acrescente o id em `cobre as teclas que o estúdio tratava…` se for uma ação central, e um teste de tela como o de `na tela do projeto` se a ação for nova.
6. **Docs:** a tabela do grupo em [manual 09](../manual/09-configuracoes-atalhos-android.md#janela-atalhos-do-teclado) (uma linha com categoria, rótulo, contexto, padrão e id) e a contagem de ações por contexto de [Contextos e camadas](../manual/09-configuracoes-atalhos-android.md#contextos-e-camadas).

### Decisões e por quê

- **Um catálogo, uma fonte da verdade.** A janela `?`, a tela de personalizar, o resolver e o guardado leem a mesma lista: o texto da janela deixou de ser escrito à mão (o `suspendedShortcuts` const e o `keyboard_test` antigo viraram `suspendedShortcutsOf(km)`).
- **Só a diferença dos padrões no guardado e no arquivo.** Um padrão que muda numa versão nova do app chega a quem nunca personalizou aquela ação; e o arquivo fica curto.
- **Tecla como texto estável (`Mod+Shift+Z`), não `keyId`.** O arquivo não depende da plataforma e é legível; sem operador de bit, roda igual no dart2js.
- **Ctrl e Cmd são a mesma coisa (`Mod`).** O jopendaw sempre tratou os dois iguais (`isControlPressed || isMetaPressed`); o arquivo vai de um sistema ao outro.
- **Camadas separadas para arranjo, piano roll e teclado tocando.** `Ctrl+D` é do clipe e das notas; o conflito só existe dentro da camada.
- **`Esc` fixo.** Ele cancela e fecha vários níveis (o controle armado, o painel, a seleção): personalizá-lo quebraria o modelo de "voltar um nível".
- **Sem editar o teclado de notas.** As notas são por posição e estão fixas; só oitava e velocidade se personalizam.
- **Somente leitura em vez de sobrescrever** um guardado ilegível ou de versão futura, o mesmo cuidado dos presets do usuário.

### Como testar os atalhos personalizáveis

```bash
cd app && flutter test test/keymap_test.dart test/keyboard_test.dart
```

`keymap_test.dart` (1071 linhas; o grupo `tela de personalização` passou a cobrir a confirmação `Importar atalhos?` e o `Desfazer importação`, e o de `janela de atalhos`, o `canCustomizeShortcuts` sempre verdadeiro, em lugar de "celular sem o botão"; a fase 18 A acrescenta `app/test/fase18a_test.dart`, grupo `atalhos`: dicas do `Keymap`, `_persist` esperando o `load` e a sessão vencendo, cobertura dos switches, importar e desfazer, `Shift+/`, título sem `Sem atalho`, `Com Shift`, rótulo por posição, aviso de teclado físico) tem os grupos: `catálogo` (ids únicos, padrões válidos e sem duplicados no mesmo contexto, cobertura, formato e rótulos por sistema), `equivalência com o tratamento de teclas de antes` (o oráculo, 6 testes), `regravar, conflito, restaurar` (7 testes: regravar e restaurar, acrescentar até o limite, conflito no mesmo contexto, contextos diferentes, reservadas, restaurar com padrão tomado, o resolver com a tecla nova), `guardado local e .jokeys` (ida e volta, arquivo ilegível, versão futura, guardado que falha, exportar/importar, arquivo ruim, defeitos, conflitos, importar substitui e grava), `janela de atalhos gerada do catálogo` (todo atalho aparece, os suspensos saem do catálogo), `tela de personalização` (em 360 e 1512 px, sem overflow: lista, regravar, conflito, restaurar, busca; todas as categorias com atalho longo; teclado tocando; exportar e importar pelas funções injetadas), `janela de atalhos` (em 360 e 1512 px: lista gerada, `Personalizar` troca e volta; celular sem o botão; `canCustomizeShortcuts`) e `na tela do projeto` (a tecla personalizada dispara a ação e a padrão deixa de disparar; `Esc` e a gravação continuam; oitava do teclado tocando). `keyboard_test.dart` confere que todo atalho suspenso listado é mesmo uma letra do teclado musical.

### Armadilhas dos atalhos personalizáveis

- **Resolvido em `c1fb192` (fase 18 A), o que esta seção listava:** (1) tooltips e dicas de menu com a tecla padrão escrita à mão: agora saem do `Keymap` (`shortcutHint`/`shortcutLabel`); (2) nada garantia que todo id do catálogo tivesse tratamento: teste `(3)` de `fase18a_test.dart`; (3) `_persist` não esperava o `load()` e a fusão ignorava conflito com a sessão: espera e a sessão vence (`_mergeStored`); (4) `Shift+/` no arquivo importava sem aviso e nunca disparava: vale como `?`, com aviso; (5) importar não pedia confirmação nem tinha desfazer: `Importar atalhos?` e `Desfazer importação`; (6) o botão `Personalizar` não existia no app Android com teclado físico: está em todo aparelho, com aviso quando nenhuma tecla física foi vista; (7) o título do grupo do teclado escrevia `Sem atalho liga`; (8) o rótulo do teclado tocando era sempre o QWERTY: aprende a letra real (janela `?` e tooltip, não os chips).
- **Continuam valendo (fase 18 A):** o oráculo testa o resolver, não o despacho (ver acima); ficam com a tecla escrita à mão o `(Q)` do tooltip de quantizar (`piano_roll.dart`, ~linha 525) e o `(Ctrl+Z)` da janela de edição de áudio (`audio_edit_ui.dart`); o teste `(1)` de `fase18a_test.dart` só vigia cinco rótulos em três arquivos; o `_beforeImport` é um instantâneo em memória (não sobrevive a fechar o app) e a tela perde o botão `Desfazer importação` ao fechar; o aviso de `_mergeStored` pode sobrescrever o `loadNotice` de arquivo ilegível do mesmo carregamento; um arquivo que cita a tecla padrão de uma ação não citada **tira** a tecla dela (com aviso).
- **Um build de computador nativo** (sem motor) abre a personalização, mas o `LocalStore` de `engine_io.dart` só guarda no Android e o `saveFile` do motor falha fora dele (`Salvar arquivos não funciona neste sistema: use o jopendaw no navegador ou no Android.`): no computador nativo as mudanças valem só até fechar o app e o exportar mostra `Não foi possível exportar: …`. `(lido do código)`
- **`Keymap.instance` é estático**: teste de tela que não o troque por `Keymap(MemoryKeymapStorage())` lê o `LocalStore` de verdade.
- **Teclado tocando e layouts não QWERTY:** as quatro ações dele são por posição física. Na janela `?` e no tooltip o rótulo segue a letra real depois de a pessoa apertar teclas (`Q (posição do A)`); antes disso, e nos **chips** da tela de personalizar e no `.jokeys`, o rótulo é a letra QWERTY daquela posição (num AZERTY o chip mostra `Z` para a tecla impressa como `W`).

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
| `daw/model.dart` | `DawDoc.midiMap`, lido de `midi_map` e escrito só se `!midiMap.isDefault` (com mapeamentos ou com `soft` desligado) |
| `daw/controller.dart` | `midiLearn` (criado sob demanda), `localStore` (o guardado local, para o padrão), `_onMidi` (o desvio para `handle`), `_travel` (mantém o `midiMap` no desfazer) e `_fromTemplate` (aplica o padrão a um projeto novo) |
| `daw/knob.dart` | `KnobMenuAction` e `Knob.extraActions`: com entradas extras, o botão direito e o toque longo abrem um menu (`Digitar o valor…` mais as extras) em vez do campo direto |
| `daw/instrument_panel.dart` (`_Ctx.knob`), `daw/fx_editors.dart` (`_Fx.knob`) | Embrulham cada knob em `MidiLearnControl` e passam `extraActions: () => midiLearnActions(...)`. O seletor de faixa-chave do `Sidechain` e o valor do gráfico do EQ **não** são embrulhados |
| `daw/mixer_panel.dart` | `MidiLearnControl` no pan e no fader (`secondaryMenu: true`) e em cada linha de envio (`radius: 4`, sem `secondaryMenu`, o botão direito é o menu do envio) |
| `daw/timeline.dart` | `MidiLearnControl` no mini fader do cabeçalho da faixa (o do `Master` não) |
| `daw/transport_bar.dart` | `MidiLearnButton` depois do cabo, se `midiEnabled \|\| midiLearn.learning \|\| !doc.midiMap.isEmpty` |
| `screens/project_screen.dart` | `MidiLearnBanner` abaixo da barra; `midilearn.toggle` (padrão `Shift+K`) chama `toggleMidiLearn`; `midilearn.cancel` (`Esc`, fixa) chama `midiLearn.escape` (antes do `panel.close`, que fecha o painel de baixo: a ordem do catálogo) |
| `daw/shortcuts_dialog.dart`, `daw/keymap.dart` | (fase 16 C) a ação `midilearn.toggle` (`Shift+K`) e a fixa `midilearn.cancel` (`Esc`) agora são do catálogo, e a linha `Shift+K` do grupo de suspensos sai de `suspendedShortcutsOf` (o teste `keyboard_test.dart` tira o `Shift+` e confere que a letra, aqui `K`, é do teclado musical) |

### O campo `midi_map` do documento

Só escrito quando há mapeamentos ou o `soft` está desligado (`isDefault` é `items.isEmpty && soft`; fase 15, `1d90812`: antes bastava a lista vazia para o campo sumir e um `Suave` desligado voltava a ligado ao reabrir). Leitura tolerante: qualquer coisa que não seja objeto vira mapa vazio; um item inválido é descartado sem derrubar os outros; ids repetidos ficam com o primeiro.

| Campo | Tipo | Obrigatório? | Padrão / leitura | Significado |
|---|---|---|---|---|
| `soft` | bool | não | `true` (só `false` explícito desliga) | takeover de todos os mapeamentos |
| `items` | lista | não | `[]` | os mapeamentos |

Cada item de `items` (`MidiMapping`):

| Campo | Tipo | Obrigatório? | Padrão / leitura | Significado |
|---|---|---|---|---|
| `id` | string | sim | (item descartado se ausente) | id do mapeamento (`mm` + tempo em base 36 + contador) |
| `src` | objeto | sim | (item descartado) | origem, abaixo |
| `track` | string ou `null` | não | `null` = master | **id** da faixa (não o índice). Um valor que não é string nem nulo faz o item ser **descartado** (`FormatException` em `MidiMapping.fromJson`; fase 15: antes virava `null` e portanto **master**) |
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
4. **`_drive`.** Resolve a faixa por id (`trackOf`; faixa apagada: nada) e o `AutoInfo` do alvo; `midiMappingNorm` (curva, inversão, `min + (max − min) · n`); se `soft`, `MidiPickup.accept(incoming, autoNorm(live), min, max, held: autoNorm(fixed))`, onde `live = c.liveTargetValue(track, alvo, info.fixed)` é o que o controle **mostra** (a curva da automação com o transporte tocando; o fixo se parado ou se o alvo está sendo gravado) e `held` é o fixo, o que este mapeamento escreve; converte com `midiTargetValue` (usa o `warp` do alvo: curva do fader no volume e no envio, logarítmica em Hz e segundos; reta no pan e nos lineares; degraus em inteiros e opções, pelo `_fit` dos setters) e chama `_set`.
5. **`_set`** usa os mesmos caminhos dos gestos: volume e pan: `autoRec.value` e `mutate` (`masterGain`/`masterPan` no `-1`); instrumento: `setParam`; efeito: `setEffectParam`; envio: `setSend(level:)`. É isso que faz o movimento gravar automação nos modos que gravam e entrar no motor pelo caminho rápido.
6. **Gesto e desfazer.** O primeiro valor que **muda de verdade** (`v != info.fixed`) de um gesto de um mapeamento faz `autoRec.touch` e `checkpoint()` (um passo de desfazer); quem decide que é a primeira é o conjunto `_stepped` (`_stepped.add(id)`), não a existência da corrida `_runs[id]` (fase 15, `1d90812`: antes uma primeira mensagem no valor que já estava criava a corrida sem o `checkpoint`, e a mudança da mensagem seguinte ficava sem passo próprio). Cada mensagem (mesmo a que cai no valor fixo, que só faz `_keepRun`) reinicia um `Timer` de `midiIdleRelease` = 700 ms; ao vencer, `_endRun` chama `autoRec.release` (é o "soltar" do modo `Toque`). Remover ou limpar cancela as corridas (`_cancelRun`); `_endRun`, `_cancelRun` e o `dispose` também esvaziam `_stepped`, então o gesto seguinte volta a abrir um passo.

### Takeover (`MidiPickup.accept`)

Um `MidiPickup` por mapeamento (`_pickups[id]`), com `picked`, `lastIn` e `lastOut`. `accept(incoming, current, lo, hi, {held})`:

1. Se estava `picked` e o controle agora está a mais de `midiPickupTolerance` (2%) do último valor que o app aplicou (`lastOut`; a comparação usa `held`, o valor fixo, e `current` se `held` é nulo): outra mão mexeu (mouse, desfazer, preset): `picked = false`. A curva de automação andando sozinha não conta, porque só mexe no mostrado, não no fixo.
2. Se não está `picked`: `current` é levado para dentro de `[lo, hi]` (senão um controle fora da faixa nunca seria alcançado) e vira `picked` se `|incoming − current| <= 0,02` **ou** se a mensagem anterior e a atual ficam de lados opostos de `current` (`(lastIn − current) · (incoming − current) <= 0`, o cruzamento).
3. Grava `lastIn = incoming` (mesmo sem assumir) e devolve `picked`.

`update` (curva, inversão, faixa) zera `picked` daquele mapeamento. `soft == false` pula tudo e assume sempre. Depois de um valor aplicado, `lastOut` recebe a posição real do controle lida de volta (`autoInfo` de novo), para o setter poder ter arredondado ou limitado. O `current` vem de `liveTargetValue`: o valor que o knob mostra, isto é, a curva da automação que está tocando (fase 15, `1d90812`: antes vinha de `info.fixed`, o valor fixo, e com automação em `Ler` o botão "pegava" um valor que a tela não mostrava).

### Padrão para novos projetos

`midiDefaultToJson(map, tracks)`: tira efeitos e envios; troca `track` (id) por `index` (posição da faixa; `null` para o master); faixa que não está mais na lista é descartada; nos alvos de instrumento com faixa acrescenta `kind` (o `TrackKind.name` da faixa: `synth`, `fm`, `wavetable`...), porque o id do parâmetro só quer dizer algo dentro do instrumento. `midiDefaultFrom(json, tracks, newId)`: cria mapeamentos com ids novos apontando para o id da faixa da mesma posição; posição fora do intervalo é descartada, e um item com `kind` também é descartado se a faixa da posição é de outro tipo (padrões guardados antes da fase 15, sem `kind`, valem como antes, por posição). `DawController._fromTemplate` aplica o padrão a todo documento **novo** (modelo ou `_fresh`), lendo `midimap:default` do `LocalStore` (guardado local: IndexedDB na web, arquivo no Android; nunca sincroniza). Um projeto que já tem `doc:<id>` não passa por lá.

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
- `fase15a_test.dart`, grupo `MIDI learn` (fase 15): o passo de desfazer na primeira mudança real (mesmo com a primeira mensagem no valor fixo), o padrão com o tipo do instrumento (só aplica em faixa do mesmo tipo), `remapDocIds` reescrevendo o `midi_map` (faixa, efeito, envio, e descartando o solto), o `Suave` desligado sem mapeamentos sobrevivendo ao salvar e reabrir, o `track` inválido descartando o item e o takeover comparando com o valor que o knob mostra tocando.
- No Chrome (`node tool/cdp.mjs` com `jopendawEngine.injectMidi(0xB0, 21, 40)` depois de armar um controle), a sessão de código viu `Aprendido: Canal 1 · CC 21 → Pad · Volume`, a etiqueta `CC21` e o fader em −24,1 dB com o `CC 40` (relato; não repeti). Não há teste com controlador de verdade.

### Armadilhas conhecidas

- **Um `CC 1`, `CC 64` ou bend mapeado deixa de ser expressão** (e de gravar pontos no clipe) até o mapeamento ser removido, mesmo com o alvo apagado. Ver [04 Expressão MIDI](04-expressao-midi.md).
- **O canal conta no mapeamento e não na expressão.** O mesmo `CC 1` em outro canal segue como modulação.
- **Os ids de parâmetro se repetem entre instrumentos** (`13` é `Corte` no sintetizador, `Ataque` do operador 2 no FM, `Desafino` no wavetable): resolvido em `1d90812` (fase 15): o padrão guarda o `kind` da faixa e só se aplica numa faixa do mesmo tipo. Resta o padrão antigo, guardado sem `kind`, que ainda cai por posição (limpe com `Apagar o padrão` e salve de novo). `(testado só por testes automáticos)`
- **Desfazer não cobre o mapa.** Nem `Remover todos`, nem `Remover mapeamento`, nem aprender de novo (que substitui o anterior) entram no histórico; e `_applyRemote` troca o documento inteiro, inclusive o `midi_map`, pelo do servidor.
- **`MidiMap.isEmpty` continua olhando só os itens** (é o que decide se o botão `Aprender MIDI` aparece na barra); quem decide se o campo é escrito é `isDefault`. Resolvido em `1d90812`: com a lista vazia o `soft` desligado agora é gravado e volta desligado ao reabrir.
- **`track` que não é string nem nulo descarta o item** (resolvido em `1d90812`; antes virava o `Master` em silêncio).
- **`remapDocIds` reescreve o `midi_map`** (resolvido em `1d90812`): reaponta `track` pelo mapa de ids de faixa, e o `ref` dos alvos `effect` (ids de slot) e `send` (ids de faixa); o item que aponta para o que não existe é descartado (antes, com id inseguro ou repetido, virava `Faixa removida`). Os ids dos próprios mapeamentos **são refeitos** desde `52d25c1` (`id: keep(m.id)`; antes ficavam como vinham, mesmo inseguros ou repetidos). `(testado só por testes automáticos)`
- **O início do gesto sem passo de desfazer: resolvido em `1d90812`.** Em `_drive`, uma primeira mensagem que cai no valor fixo (`v == info.fixed`, comum em parâmetros inteiros e de opção) só faz `_keepRun`; o `touch` e o `checkpoint()` agora são guardados por `_stepped` e rodam na primeira mudança real. `(testado só por testes automáticos)`
- **O tooltip do knob e o `keyboardTooltip`: resolvido em `1d90812`.** O do knob com `extraActions` dizia `botão direito: menu (digitar o valor, Aprender MIDI)` (sem elas, `digitar o valor`), e o do teclado ligado listava `Shift+H/K/L` (`widgets/format.dart`, `knob.dart`); na fase 18 A o do knob passou a `botão direito ou toque longo: menu (digitar o valor, Aprender MIDI, Modular…)` (`Knob._menuHint`) e o do teclado virou `keyboardTooltip` de `keymap.dart`, que lista `Shift+H/K/L/Z` (o teste `6` de `fase15a_test.dart` afirma agora o `Shift+H/K/L/Z`).
- **Flutter desenha em canvas**: para o teste de uso no Chrome os cliques e teclas vão pelo `node tool/cdp.mjs`, não pelo MCP `chrome-devtools`.

## Exportação em FLAC e MP3 (`export_compressed.dart`)

> Para quem mexe na janela `Exportar áudio` e no envio ao servidor (fase 15 C, commit `792b6f5`, integrado em `9192220`): como o app usa a tarefa `encode_audio` sem tirar o WAV do aparelho. O lado do servidor está em [11 Servidor](11-servidor.md) (item `encode_audio`); o texto para quem usa está em [Exportação](../manual/08-exportacao.md#flac-e-mp3-pelo-servidor).

### Visão geral

O motor continua escrevendo só WAV. Para FLAC e MP3, o render entrega o WAV de sempre a um `sink` (em vez de salvar), e o `CompressedExport` sobe esse WAV, espera a tarefa, baixa o resultado e o salva pelo caminho de sempre. Se algo falha, o WAV já renderizado fica guardado na memória para a pessoa salvá-lo assim, sem renderizar de novo.

```
ExportDialog ── ExportOptions(format: flac|mp3, flacBits, flacLevel, mp3Quality)
     │
ExportProgressDialog ──► DawController.exportAudio(options, sink: cx.deliver)
     │                         │  render em lotes → normaliza → encodeWav(options.renderFormat) → sink(nome.wav, bytes)
     │                         ▼
     │               CompressedExport.deliver(wavName, wav)
     │                  sem sessão? ─► failure + fallbacks.add(PendingWav)
     │                  _compress: sha256 → missingSamples → putSample → createJob('encode_audio', hash, params)
     │                             → job() a cada 0,8 s → getSample(result.sample) → save(nome.flac|mp3, bytes, mime)
     │                             → finally: deleteJob · deleteSample(resultado, force) · deleteSample(WAV, force) (409: _retryTidy)
     ▼
 fim: saveCanceled? ─ "Exportação cancelada" · fallbacks vazio? ─ sim: "Exportação concluída" · não: "Não deu para compactar" → saveWavs() / Voltar / Fechar
```

### Peças e responsabilidades

| Arquivo | Papel |
|---|---|
| `app/lib/daw/export_options.dart` | `ExportFormat` ganha `flac` (`FLAC (sem perda, menor)`) e `mp3` (`MP3 (para compartilhar)`) com `compressed`, `extension` e `mime`; `FlacLevel` (`Rápido` 2, `Padrão` 5, `Menor arquivo` 8); `Mp3Quality` (nove itens: `cbr128`… `cbr320`, `vbr0`… `vbr4`, com `params`); `kEncodeMaxSeconds` = 1800; `kEncodeMaxUploadBytes` = 512 MiB e `estimatedWavBytes(segundos, taxa, bits)` = `44 + ceil(segundos × taxa) × 2 × (bits ÷ 8)` (fase 17 A: o aviso do teto do servidor); em `ExportOptions`: `flacBits` (padrão 24), `flacLevel` (`Padrão`), `mp3Quality` (`cbr192`), `artist` (fase 17 A; vazio = sem artista; só entra nas opções de FLAC e MP3), `renderFormat` (o WAV do render: 16 bits para o MP3, `flacBits` para o FLAC) e `encodeParams` (o corpo `params` da tarefa, sem metadados) |
| `app/lib/daw/export.dart` | `ExportDialog`: chips `flac-bits-16` e `flac-bits-24`, listas `flac-level` e `mp3-quality`, `_pickFormat` (MP3 numa taxa que não seja 44,1 nem 48 kHz passa para 44,1), filtro da lista de taxas, `_tooLongForServer` (desliga `Exportar` e mostra o aviso), o campo `export-artist` (`Artista (opcional)`, só com FLAC ou MP3, até 200 caracteres), `_tooBigToUpload` (`_uploadBytes` > `kEncodeMaxUploadBytes`: aviso e `Exportar` desligado) e `_monitoring` (aviso `export-monitoring-warning` dos efeitos em solo ou ouvindo a banda). `ExportProgressDialog`: cria o `CompressedExport`, estados `_fallback`, `_savingWav`, `_wavSaved`, `_saveCanceled`, `_shown` e `_barValue()` (barra em duas fases, monotônica), `_savedFormats`, botão `export-wav-anyway`; aceita `api` e `signedIn` injetados para os testes |
| `app/lib/daw/export_compressed.dart` | `CompressedExport` (`ChangeNotifier`; campos novos da fase 17 A: `saveCanceled`, `canceledName`, `retryDelays` = 3, 10 e 30 s), `PendingWav`, `compressedName`, a exceção privada `_JobFailed`, `_savedName` (o nome sugerido pelo servidor) e `_retryTidy` |
| `app/lib/api/export_api.dart` | `ExportApi`: `missingSamples`, `putSample`, `getSample`, `createJob`, `job`, `deleteSample({force})`, `deleteJob`. Interface própria para o falso dos testes não depender da `SyncApi` |
| `app/lib/api/client.dart` | `ApiClient implements SyncApi, ExportApi`; `deleteJob` = `DELETE /api/jobs/{id}` (o único método novo) |
| `app/lib/daw/controller.dart` | `exportAudio(options, {onProgress, sink})`: com `sink` entrega cada WAV (`names[batch[k]]!`, `bytes`) a ele; sem, salva como WAV. `saveExportedFile(name, bytes, mime)` = `_engine.saveFile` (o caminho único de salvar) |
| `app/test/export_compressed_test.dart` | 675 linhas depois da fase 17 A: `FakeExportApi` e o `CompressedExport` inteiro, mais testes de janela; os novos: o teto de 512 MB antes dos 30 minutos, artista e nome sugerido, `Salvar` fechada (na conversão e no `WAV mesmo assim`), o cancelar com `409` apagado de novo aos poucos, `Exportação cancelada`, o resumo por formato, a barra que não recua e o aviso de solo com o artista nas opções |

### Fluxo e estados de `CompressedExport`

- `deliver(wavName, wav)` é chamado uma vez por arquivo, na ordem do render (mixagem, depois os stems). Se `failure` já foi preenchida, o WAV vai direto para `fallbacks` (os arquivos seguintes nem tentam a rede). Sem sessão (`signedIn()` falso), preenche `failure` com `Entre na sua conta para exportar em MP3|FLAC: a conversão é feita no servidor.`
- `_compress`: `hash = sha256(wav)`; `uploaded = (await api.missingSamples([hash])).contains(hash)` (só apaga depois o que ele mesmo subiu); `createJob('encode_audio', hash, {...options.encodeParams, 'title': <nome sem .wav>, if (artist.isNotEmpty) 'artist': <artista aparado>, if (album.isNotEmpty) 'album': <nome do projeto>})`; laço de espera enquanto `queued` ou `running` (`pollEvery` 800 ms, `maxWait` 20 min, três `job()` com falha de rede seguidas derrubam; `ApiException` e `Unauthenticated` derrubam na hora); `failed` → `_JobFailed(job.error ?? 'A conversão falhou no servidor.')`; sem `result.sample` → `O servidor não devolveu o arquivo convertido.`; `getSample` nulo → `O arquivo convertido sumiu do servidor.`; junta `result.warnings` (sem repetir) em `warnings`; `name = _savedName(result, wavName)` (o `filename` do resultado quando termina na extensão do formato, senão `compressedName`) e `save(name, bytes, options.format.mime)`: se devolve `false` (janela `Salvar` fechada no Android), `saveCanceled = true` e `canceledName = name`, e o `deliver` lança `RenderCanceled` (não conta em `compressed` e a exportação para ali, sem abrir outra janela por stem).
- `finally` do `_compress` (reordenado na fase 17 A): três limpezas em `tidy` (engole qualquer erro; um `ApiException` `409` põe a limpeza numa lista de repetição), nesta ordem: `deleteJob(jobId)` (o servidor cancela uma tarefa `running`), `deleteSample(resultado, force: true)` e `deleteSample(hash, force: true)` (só se `uploaded`). O que deu `409` (um servidor sem o cancelamento, ou a tarefa rodando em outra instância) é tentado de novo por `_retryTidy` (`unawaited`, sem segurar a janela) depois de `retryDelays` (3, 10 e 30 s); o que sobrar fica como áudio sem uso na tela `Conta`.
- `_describe` traduz o erro em `failure`: `Unauthenticated` → `Sua sessão terminou; entre de novo para exportar em MP3|FLAC.`; `ApiException` e `_JobFailed` → a mensagem do servidor; `TimeoutException` → `O servidor demorou demais para responder.`; `StateError` → a mensagem dela; qualquer outra → `Não consegui falar com o servidor (sem conexão?).`
- Progresso: `stage` (texto: `Enviando ao servidor (N MB)…`, `Na fila do servidor…`, `Compactando no servidor N%…`, `Baixando o arquivo…`, `Salvando…`) e `fraction` = `(índice do arquivo + fração do arquivo) / expectedFiles`, limitada a 0,999; `expectedFiles` = `tracks.length + 1` com stems, 1 sem (o número real de stems pode ser menor: faixa muda é pulada, então a barra não chega perto de 100% nesse caso, o que é inofensivo). A barra do diálogo (`_barValue`) tem duas fases nos formatos compactados: `0,5 × render + 0,5 × cx.fraction`, com o maior valor já mostrado guardado em `_shown` (nunca recua, mesmo quando o render do lote seguinte recomeça de baixo) e o teto de 0,999; sem `CompressedExport` (WAV) é só o progresso do render. O texto `Renderizando N%` usa o progresso do render, não a barra somada.
- `cancel()` liga `_canceled`; `_checkCanceled` lança `RenderCanceled` (a mesma exceção do render, que o `exportAudio` já trata como "não é falha").
- `saveWavs()` salva os `fallbacks` como `audio/wav` e devolve quantos foram salvos; para no primeiro que a janela `Salvar` deixou sem salvar (`save` devolveu `false`) e os outros continuam em `fallbacks`. O diálogo soma em `_wavSaved` e mostra a mensagem de cancelamento se sobrou WAV (resolvido em `52d25c1`: antes o retorno de `save` era ignorado e cancelar a janela de salvar do Android contava como salvo). No caminho de WAV direto (`exportAudio` sem `sink`) o retorno de `saveFile` continua ignorado (ver Armadilhas).

### Contratos

`encodeParams` (com os metadados que o `_compress` acrescenta):

```json
{"format": "flac", "bits": 24, "level": 5, "title": "Meu projeto", "album": "Meu projeto"}
{"format": "mp3",  "bitrate": 192, "title": "Meu projeto", "album": "Meu projeto"}
{"format": "mp3",  "vbr": 0, "title": "Meu projeto - Baixo", "album": "Meu projeto"}
{"format": "mp3",  "bitrate": 192, "title": "Meu projeto", "artist": "Fulana", "album": "Meu projeto"}
```

O `result` do job (fase 17 A, `SyncJob` em `sync_api.dart`): `sample`, `bytes`, `format`, `mime`, `filename` (nome sugerido, `Artista - Título.ext`; o app o usa), `duration`, `rate`, `channels` e `warnings`.

Mensagens da janela (texto exato): `Não deu para compactar` (título), `Não deu para exportar em MP3|FLAC: <motivo>`, `O arquivo já está renderizado em WAV: dá para salvar assim, sem renderizar de novo.` / `O áudio já está renderizado (N arquivos) em WAV: ...`, `N arquivo(s) foi/foram salvo(s) compactado(s). O outro já está renderizado em WAV: ...`, botões `Fechar` (`pop(false)`), `Voltar às opções` (`pop(true)`, refaz o render pelo laço de `showExportDialog`) e `Exportar em WAV mesmo assim` (chave `export-wav-anyway`), aviso `O servidor converte até 30 minutos por arquivo: escolha um trecho menor, diminua a cauda ou exporte em WAV.`; da fase 17 A: aviso `O WAV desta música passa de 512 MB (N MB), o limite do servidor para converter: exporte em WAV, ou reduza a taxa de amostragem, o trecho ou a cauda.` (`Exportar` desligado), aviso `Um efeito está em solo ou ouvindo a banda: a exportação sairá assim (<efeito (faixa)>, …). Desligue o solo ou o "Ouvir banda" antes, se não era a intenção.`, título `Exportação cancelada` com `Exportação cancelada: você não escolheu onde salvar "<nome>".` (mais ` Os N arquivos anteriores já tinham sido salvos.` se houve) e, no meio do `Exportar em WAV mesmo assim`, `Exportação cancelada: N arquivo(s) ficou/ficaram sem salvar.`, com os botões `Fechar` e `Voltar às opções`.

### Decisões e por quê

- **O render não muda:** `exportAudio` normaliza e mede o loudness no PCM float como sempre e só depois chama `encodeWav(channels, rate, options.renderFormat)`. A normalização de pico e a de loudness valem, portanto, para o WAV, e o relatório (`exportReport`) descreve o WAV. O FLAC decodifica idêntico a ele; o MP3, não.
- **WAV de 16 bits para o MP3, e o do chip para o FLAC:** o encoder do servidor lê 16, 24 ou 32; mandar o formato final evita os avisos de perda do servidor e o arredondamento sem dither dele.
- **Falha pega tudo o que deu para renderizar:** `failure` é do exportador inteiro, não de um arquivo, para não repetir tentativa de rede num servidor fora do ar e para o botão `Exportar em WAV mesmo assim` salvar de uma vez os stems que sobraram.
- **`ExportApi` separada da `SyncApi`:** o falso dos testes de exportação implementa 7 métodos em vez de toda a sincronização.
- **Limpeza silenciosa e com `force`:** o WAV enviado tem menos de 1 hora, e sem `force` o `DELETE /api/samples/{hash}` daria `409` (`recent`).

### Como testar

`cd app && flutter test test/export_compressed_test.dart`. O `FakeExportApi` guarda os áudios, anota as chamadas em ordem (`missing`, `put`, `create`, `job`, `get`, `delete_sample:result|wav:<force>`, `delete_job`) e aceita um `script` de `SyncJob` e um `fail` por chamada. Grupos: opções (o `renderFormat` acompanha o formato, `encodeParams` de FLAC, MP3 CBR e VBR, extensão e MIME) e o exportador (sucesso completo com a limpeza, FLAC com bits e nível e o WAV que já estava na conta não apagado, stems em série, sem sessão, offline, erro do job, erro de cota e de sessão, falha ao apagar silenciosa, tropeço de rede tolerado e três seguidos derrubam, cancelar). Cinco testes de widget montam `ExportProgressDialog` com o falso: FLAC com sucesso, sem sessão e `Exportar em WAV mesmo assim` salvando sem novo render, erro do job na janela, stems em FLAC e cancelar durante a espera. **Tudo isto é teste automático com servidor falso** `(testado só por testes automáticos)`; o que foi visto de verdade foi o MP3 no navegador (ver o manual). Contra o servidor real há os testes de rota do lado do servidor (`server/src/routes/tests_encode.rs`).

### Armadilhas conhecidas

- **Resolvido em `52d25c1`: tooltip do botão `Exportar`.** Dizia `Exportar a música (e as faixas separadas) em WAV`; agora é `Exportar áudio (WAV, FLAC ou MP3)` (duas ocorrências em `transport_bar.dart`, a do ícone e a do botão com nome).
- **O WAV direto ignora a janela `Salvar` fechada.** No caminho sem `sink` (`exportAudio`, `await _engine.saveFile(...)`) o retorno booleano de `saveFile` é descartado: no Android, fechar a janela `Salvar` num WAV ainda termina em `Exportação concluída`. Só FLAC e MP3 (e o `WAV mesmo assim`) conferem o retorno. `(lido do código; não reproduzido)`
- **Resolvido em `ffa76ba` (fase 16 A): parênteses duplos na conclusão.** `A mixagem foi salva (${format}) em N s.` usava o `label` do formato, que já tem parênteses (`(MP3 (para compartilhar))`). Agora usa `ExportFormat.shortLabel` (`FLAC`, `MP3`; os WAV ficam com o `label`, como `WAV 24 bits`); o `label` da lista de `FORMATO` não mudou. Continua valendo: depois de `Exportar em WAV mesmo assim` o `format` vira só `WAV` (sem profundidade), mesmo se parte dos arquivos já tinha saído compactada.
- **Resolvido em `52d25c1`: a barra de progresso não era monotônica.** O render de um lote ia até `95%` e, ao converter, o diálogo passava a mostrar `cx.fraction`, que começa em 0. Agora `_barValue` soma as duas fases (0 a 50% o render, 50 a 100% a conversão) e guarda o maior valor mostrado. Ainda assim, com stems, o render do lote seguinte recomeça de baixo e a barra fica parada até ultrapassá-lo `(testado só por testes automáticos)`.
- **Resolvido em `52d25c1`: cancelar não parava a tarefa no servidor.** Agora o `deleteJob` da limpeza cancela uma tarefa `running` (ver [11 Servidor](11-servidor.md)) e, contra um servidor sem isso, `_retryTidy` insiste; o MP3 para em até 1 s de áudio e o FLAC só ao fim (o resultado é descartado).
- **`SyncJob` carrega `flac`, `audio_to_midi` e `encode_audio`** (o comentário foi atualizado em `52d25c1`; o `result` do `encode_audio` traz `format`, `mime`, `filename`, `duration`, `rate`, `channels`, `warnings`). O app usa `sample`, `warnings` e, desde a fase 17 A, `filename`.
- **Memória:** os `fallbacks` guardam os WAV renderizados até a pessoa decidir; com muitos stems longos são várias dezenas de MB cada (o WAV de 4 minutos estéreo a 48 kHz tem cerca de 46 MB em 16 bits e 69 MB em 24 bits, pelas contas da tabela de formatos do manual) `(não medido)`.
- **Upload grande e o teto de 120 s por pedido** (`ApiClient`): um WAV de centenas de MB numa conexão lenta pode cair em `O servidor demorou demais para responder.` `(lido do código; não reproduzido)`.
- **Lista de taxas e MP3:** com o formato `mp3` e a taxa do aparelho fora de 44,1/48 kHz, o item `A do aparelho` some da lista; só o `_pickFormat` corrige a taxa. Se as opções guardadas (`_lastOptions`) já tiverem `mp3` com `sampleRate` nulo e o aparelho mudar de taxa, a lista abre sem o item que é o valor inicial `(lido do código; não reproduzido)`.

## Tabelas espelhadas do motor (`instruments.dart`, `effects.dart`)

- **`TrackKind`** (`instruments.dart:13`): `audio, synth, drums, sampler, bus, fm, wavetable`. `values[i].index` é o código de `track_kind` no motor: **tipo novo só entra no fim** do enum.
- **`ParamSpec(id, nome, grupo, mín, máx, padrão, unit, curve)`** (`:65`): `curve` é `linear`, `log`, `integer` ou `choice` (lista de opções; o valor é o índice). `toNorm`/`fromNorm` convertem entre valor e posição 0..1 do controle; `format` monta o texto ("1,2 kHz", "250 ms", "+3 st").
- **Instrumentos**: `synthParams` (35 ids, tipo 1), `drumParams` (12 peças × 4 + volume geral no id 48, tipo 2), `samplerParams` (tipo 3), `fmParams` (42 ids, tipo 5, operadores em `2 + operador*8 + k`), `wavetableParams` (39 ids, tipo 6); mais `fmAlgorithmMods`/`fmAlgorithmCarriers` (roteamento dos 8 algoritmos FM, espelho de `ALGORITHMS` em `fm.rs`). Os valores vão ao motor **na unidade da tabela**.
- **`EffectKind`** (`effects.dart:12`): 15 tipos com `code` 1..15 (o argumento de `fx_set`), família do menu (`family`) e `params`. Tabelas: `eqParams` (8 bandas × 6 + saída no id 48), `compressorParams`, `gateParams`, `limiterParams`, `utilityParams`, `reverbParams`, `delayParams`, `chorusParams`, `phaserParams`, `tremoloParams`, `distortionParams`, `filterParams`, `multibandParams`, `deesserParams`, `imagerParams` (os três da fase 15; `multibandBase = 4`, `multibandStride = 8` e `unpackMultibandMeter`, o inverso do empacotamento do motor, também moram em `effects.dart`). `noteValues` espelha `NOTE_BEATS` do motor (figuras do delay, tremolo e filtro sincronizados).
- `defaultParams(kind)` e `defaultEffectParams(kind)` montam o mapa de padrões (usados ao criar faixa e slot e por `DawTrack.param`).

### Testes de contrato (o que quebra se as tabelas divergirem)

| Teste | O que confere | Como |
|---|---|---|
| `engine/src/synth.rs::faixas_iguais_as_do_app` | faixas, padrões, discretos e opções do `synthParams` | lê `app/lib/daw/instruments.dart` como **texto** e compara linha a linha |
| `engine/src/fm.rs::faixas_iguais_as_do_app`, `algoritmos_iguais_aos_do_app` | `fmParams`; `fmAlgorithmMods` e `fmAlgorithmCarriers` | `instrument.rs::contract::check` |
| `engine/src/wavetable.rs::faixas_iguais_as_do_app` | `wavetableParams` | `contract::check` |
| `app/test/effects_contract_test.dart` | ids, nomes e faixas de cada efeito (`*_param` de `engine/src/effect.rs` × `effects.dart`), códigos de `fx_set` × `EffectKind`, `NOTE_BEATS` × `noteValues`; o multibanda tem teste à parte (`BAND_BASE`, `BAND_STRIDE` e `BANDS` × `multibandBase`, `multibandStride` e 3; cada `BAND_*` × nome e faixa da tabela nas três bandas; 27 ids sem repetição) e o `unpackMultibandMeter` é conferido contra o empacotamento `gr0 + 256 * gr1 + 65536 * gr2` (inclusive `NaN` e negativo) | lê `../engine/src/effect.rs` |
| `app/test/studio_test.dart` | toda chamada que o controlador manda existe em `engine/wasm/src/lib.rs` com o número certo de argumentos | lê o `lib.rs` do wasm |
| `app/test/fm_wavetable_test.dart` | índice do enum = código do motor, operadores FM, algoritmos, presets | Dart puro |

Duas consequências práticas: (1) os testes de Rust **fazem parse de texto do Dart**; a tabela precisa manter o formato (uma `ParamSpec(...)` ou `ParamSpec.choice(...)` por linha, números literais, `Curve.integer` na mesma linha, `def: n` em opções) ou o teste quebra por formato, não por valor; (2) **bateria e sampler não têm teste de contrato** (nenhum arquivo de `drums.rs`/`sampler.rs` lê o Dart: há só comentários apontando para as tabelas), então uma divergência ali passa silenciosa.

### Editores do multibanda, do de-esser e da imagem estéreo (`fx_editors_dyn.dart`)

Fase 15, commit `bd6bbb9`. Manual: [06c](../manual/06c-painel-de-efeitos.md#gráficos-do-multibanda-do-de-esser-e-da-imagem-estéreo) e [06d, seções 13 a 15](../manual/06d-efeitos-referencia.md#13-multibanda). Motor: [01 Motor](01-motor.md#os-três-efeitos-da-fase-15-multibanda-de-esser-e-imagem-estéreo).

| Peça | Papel |
|---|---|
| `daw/effects.dart` | `EffectKind.multiband` (13), `deesser` (14) e `imager` (15), o ramo de `family` (`Dinâmica e utilidade` para os dois primeiros, `Espaço` para o terceiro) e as tabelas `multibandParams`, `deesserParams`, `imagerParams`. No multibanda: ids 0 e 1 (cruzamentos), 2 (saída) e, por banda `b`, `multibandBase + b * multibandStride + k` (`4`, `8`, k de 0 a 7); `unpackMultibandMeter(double)` devolve as três reduções em dB. Desde `52d25c1` (fase 17 A): `effectiveCrossovers(low, high)` (a regra do motor: o alto fica ao menos 1,5× acima do baixo; devolve `(baixo, alto)` em Hz, usada pelo gráfico do multibanda) e `effectMonitoringNote(kind, params, {bypass})`, que devolve `'solo'` (multibanda com algum `Solo` ligado, k = 5 das três bandas), `'ouvindo a banda'` (de-esser com `Ouvir banda`, id 7) ou `null` (desligado ou outro efeito). |
| `daw/fx_editors_dyn.dart` | `part of 'fx_editors.dart'` (enxerga os privados `_Fx`, `_Watch`, `_GroupsRow`, `_GroupsColumn`, `_GrMeter`, `_axisLabel`, `_knobFit`). `_VizEditor`/`_VizEditorState` (o editor dos três), `_VizPainter` (o gráfico) e `_freqToX`/`_xToFreq` (eixo de 20 Hz a 20 kHz, log). |
| `daw/fx_editors.dart` | `EffectEditor.widthFor` e `build` mandam `multiband \|\| deesser \|\| imager` para `_VizEditor` (os outros editores próprios são `_EqEditor` e `_DynamicsEditor`; o resto cai no `_GenericEditor`). `effectParamDimmed` ganhou os ramos do multibanda e da imagem. |
| `daw/fx_presets.dart` | `_mb(b, threshold:, ratio:, attack:, release:, makeup:, knee:)` monta os ids de uma banda; `_multiband` (4 presets), `_deesser` (4), `_imager` (4) e os ramos de `effectPresetsFor`. |

**Layout.** Computador: `Row` com o gráfico (largura `side × 1,9` no multibanda, `× 1,5` no de-esser, `× 1,3` na imagem, com `side = clamp(altura do painel, 70, 220)`), o medidor (só no de-esser: `_GrMeter` de 36 px, máximo 24 dB) e os knobs (`_GroupsRow`). Celular: `Column` com uma linha de 150 px (gráfico e, no de-esser, medidor) e os knobs empilhados (`x.groups(44)`). Os grupos vêm do campo `group` de cada `ParamSpec`, na ordem da tabela, e o título aparece em maiúsculas (`BAIXA`, `MÉDIA`, `AGUDA`...). As opções `Não`/`Sim` viram pílula (`_ToggleCell`); `Modo` do de-esser, cujas opções são `Banda dividida`/`Banda larga`, é o seletor de opções comum.

**Gestos** (`ValueKey('fx-viz')` no gráfico, usado nos testes):

| Efeito | Detector | O que faz |
|---|---|---|
| Multibanda | `onHorizontalDrag*` | `_mbStart` guarda o cruzamento mais perto do toque, `_mbUpdate` põe nele a frequência do ponto (`_set` limita à faixa da tabela). O primeiro `_set` de um arraste chama `x.begin()` (`checkpoint`), então um arraste é um passo do desfazer. Desde `52d25c1`, `DawController.setEffectParam` aplica a regra dos 1,5× nos ids 0 e 1 do multibanda e da imagem estéreo (baixo = `min(v, alto/1,5)`, alto = `max(v, baixo×1,5)`, de novo limitado à faixa do knob), então o valor guardado, o do knob e o do gráfico são o efetivo, e o `_VizPainter` ainda passa o par por `effectiveCrossovers` para desenhar documentos que já vinham com o par cruzado. |
| De-esser | `onPan*` | `_dsUpdate`: a frequência é a do ponto no eixo de 1 kHz a 20 kHz (`_dsRange`, limitada a 4 kHz a 10 kHz pela tabela); o `Q` muda por `Q × exp(−dy × 0,012 × fino)`, com `fino` 0,2 se `Shift` está apertado (`HardwareKeyboard`). |
| Imagem estéreo | nenhum (`KeyedSubtree`) | O gráfico só mostra as três larguras e a correlação. |

**Indicador (`_MeterHost`).** O motor mede um efeito por vez (`watch_fx`), e o `_Watch` do controlador escolhe qual editor o pede. Antes da fase 15 ele guardava `_DynamicsEditorState`; agora guarda a interface `_MeterHost` (`meterTrack`, `meterSlot`), que `_DynamicsEditorState` e `_VizEditorState` implementam, e os métodos `addDynamics`, `removeDynamics` e `activate` mudaram de tipo. `_VizEditor` embrulha o corpo num `Listener` que chama `activate(this)` ao tocar (gráfico ou knob); `live = active == this && !slot.bypass`. Com `live`, o `_VizPainter` é reconstruído por um `ValueListenableBuilder` sobre `DawController.fxMeter`; sem, recebe 0. O valor cru significa: multibanda, três reduções empacotadas (`unpackMultibandMeter`); imagem, correlação (limitada a −1..1); de-esser, o `_GrMeter` lê `fxMeter` direto (dB). O `_GrMeter` corta valores negativos em 0, e por isso a imagem estéreo não o usa.

**Habilitar e apagar (`effectParamDimmed`).** Multibanda: todo parâmetro de banda cujo `k` não é 5 (`Solo`) nem 6 (`Bypass`) fica apagado quando o `Bypass` da banda (`k = 6`) é ≥ 0,5. Imagem: `Abaixo de` (id 7) apagado com `Mono nos graves` (id 6) < 0,5. Apagado ainda é mexível.

**Testes.** `app/test/effects_contract_test.dart` (ver a tabela acima), `app/test/effects_controller_test.dart` (`fx_set` com 13, 14 e 15 e todos os `fx_param` na sequência; mexer num parâmetro manda só ele, limitado à faixa; `targetRange` da largura da banda média da imagem `(0, 2, 1)` e do limiar da banda média do multibanda `(−60, 0, −22)`), `app/test/rack_test.dart` (3 testes novos: arrastar perto do cruzamento move o cruzamento em um só passo do desfazer, o cruzamento alto não passa de 12 kHz, o indicador chega empacotado e `Bypass` aparece 3 vezes; de-esser: arrastar sobe a frequência, e a imagem mostra `LARGURA` e `Baixa`; celular de 360 px sem estouro; o teste "um de cada" passa a incluir os três porque itera `EffectKind.values`, e o de presets confere ids, faixas e reconhecimento dos 12 presets novos). Nenhum destes foi rodado por quem escreveu esta documentação `(testado só por testes automáticos)`.

**Armadilhas.**
- **Resolvido em `52d25c1`: o tooltip do medidor com o efeito em bypass.** O do multibanda/de-esser (`_VizEditor`) dizia `O medidor mostra um efeito por vez: toque neste para medir` (porque `live` inclui `!bypass`); agora, com bypass, os dois medidores (o das dinâmicas e o deste editor) dizem `Efeito desligado: nada a medir`.
- **Selo no cartão (fase 17 A).** `_cardHeader` de `effects_panel.dart` mostra, depois de `desligado`, um selo vermelho (`ValueKey('fx-monitor-badge')`, texto em maiúsculas: `SOLO` ou `OUVINDO A BANDA`) com o tooltip `Este efeito está em solo: o áudio muda de verdade, inclusive na exportação` (ou `... em ouvindo a banda: ...`, a mesma frase com o texto de `effectMonitoringNote`), quando a nota não é `null`. O `ExportDialog` varre as cadeias das faixas e do master com a mesma função (`_monitoring`) e mostra o aviso `export-monitoring-warning`.
- `multibandParams` não é conferido pelo laço genérico do teste de contrato (ele o exclui) e depende do formato dos comentários `///` de `multiband_param` em `effect.rs`: cada constante com uma faixa `a..b` (o teste lê esse texto).
- Um projeto salvo com os novos tipos aberto num app anterior perde os slots ao abrir (`EffectSlot.fromJson` devolve `null` para tipo desconhecido); o motor antigo, por sua vez, limpa o slot do tipo que não conhece (`effect::create` devolve `None`).

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

1. Motor: `engine/src/effect.rs` (`kind::NOVO = 16`, módulo `novo_param`, ramo em `create()`), arquivo em `engine/src/fx/`, faixas dos ids documentadas no comentário `///` de cada constante (o teste de contrato lê "−60..0" desse comentário).
2. `app/lib/daw/effects.dart`: `EffectKind.novo(16, 'Rótulo', 'Descrição', ícone)` no fim, `family`, `params` e a tabela `novoParams`.
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
flutter test test/keymap_test.dart             # atalhos personalizáveis: catálogo, oráculo de equivalência, guardado, .jokeys e telas (fase 16 C)
flutter test test/fase17c_test.dart            # punch, pré-roll, tap tempo e opções do metrônomo (fase 17 C)
flutter test integration_test -d emulator-5554 # motor nativo no emulador Android
cargo test -p jopendaw-engine                  # inclui os testes de contrato que leem o Dart
```

Mapa de andamento e de compassos: `flutter test test/tempo_map_test.dart test/tempo_lane_test.dart` (conta do mapa, JSON e documento antigo, controlador e motor de mentira, gravação e render com mapa, e a comparação com o `render-worker.js` real no node; no `tempo_lane_test.dart`, a faixa `Andamento` com duplo clique, arrasto, menu e o diálogo de compasso, em widget test) e `cargo test -p jopendaw-engine tempo` (os 10 testes de `tempo.rs` e os 13 de `tempo_tests.rs`). No navegador: segundo o relato da sessão de código, o duplo clique na faixa e o diálogo de compasso **não** foram exercitados no Chrome (só há widget test); o botão direito na faixa, o menu, o arraste e a medição do salto foram (relato; não repeti).

Para conferir a saída: `flutter test 2>&1 | tr '\r' '\n' | grep -E "All tests passed|Some tests failed|\[E\]"`. Mudou o motor: recompile os binários antes de testar no navegador ou no Android. O teste de uso (obrigatório antes de dar uma fase por pronta) é usar o app no Chrome: ver [03 Build, teste e depuração](03-build-teste-e-depuracao.md) e [20 Processo e histórico](20-processo-e-historico.md).

## Armadilhas conhecidas

- **Preferências contam como mudança para sincronizar.** `_save` compara o JSON inteiro com o último gravado (`DawController._save` em `controller.dart`); `metronome`, `count_in`, `rec_latency_ms`, `armed` e `monitor` estão no JSON, então ligar o metrônomo marca o projeto como pendente e gera versão nova no servidor (mesmo que outro aparelho as ignore ao aplicar). Lido no código; efeito sobre conflitos falsos `(não confirmado no uso)`.
- **`setTempo` e o desfazer (corrigido na fase 9).** O andamento mora no documento; desfazer restaura o `bpm` antigo no documento e o `_save` seguinte reenvia o espelho (`PATCH`) se ele difere do último confirmado. Reabrir usa o `doc.bpm` local. Resta que `projects.bpm` (lista de projetos) pode ficar defasado enquanto o `PATCH` está pendente (offline). Desde a fase 15 o espelho também leva o numerador real e a figura do compasso 1 (`_wantedTempo`, `beat_unit` só quando muda). `(lido do código e coberto por `phase9c_test`; não visto no Chrome)`
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

## Modulação (fase 16 B)

| Arquivo | O que tem |
|---|---|
| `daw/modulation.dart` | Modelo Dart puro do documento: `ModKind` (o índice é o código do motor), `LfoShape`, `ModSource` (LFO, seguidor, macro), `ModDest` (`AutoTarget` + quantidade −1..1 do curso), `TrackModulation` (`deltaRange` para o anel do knob, `prune`, `remapTargets`), as 24 divisões e os presets de fábrica (`modPresets`: wobble no corte, tremolo no volume, auto-pan, vibrato de afinação; `ModPreset.hideWithoutTarget`/`availableFor` escondem do menu o preset sem alvo na faixa, e `_octaveAmount` converte ±1 oitava em fração do curso log) |
| `daw/model.dart` | `DawTrack.modulation` (`modulation`) e `DawDoc.masterModulation` (`master_modulation`): só vão ao JSON quando há algo, então um documento sem modulação sai igual ao de antes |
| `daw/controller.dart` | `_modulationCalls` (o documento como `mod_source`/`mod_dest`; `_SyncCache.mod`, reenvio só quando a lista muda), `modulationOf`, `editModulation`, `_prune` (tira destinos cujo alvo sumiu), `duplicateTrack` (ids novos e efeitos da cópia) e congelar (volume, pan e envios vão para a faixa nova; o resto vira som) |
| `daw/modulation_ops.dart` | Extensão do controlador: `modAssign` (25% de quantidade padrão), `modAddSource`, `modRemoveSource`, `modRemoveDest`, `modApplyPreset`, `canModulate` (opções e inteiros não se modulam) |
| `daw/modulation_ui.dart` | `ModulationPanel` (aba "Modulação" do dock, na faixa do rack de efeitos), `showModulateDialog` e `modulateAction` (o "Modular…" do menu de contexto do knob e do fader) |
| `daw/knob.dart` | `Knob.modRange` (o anel ciano por fora do trilho: o intervalo estático em que o valor efetivo se move; o valor mostrado segue sendo a base) e `KnobMenuAction.withContext` |

O motor não devolve o valor modulado em tempo real: o anel é estático. A macro só se controla pelo painel (não há MIDI learn nem automação dela).

### O JSON, campo a campo

Em cada faixa, `modulation` (e no documento, `master_modulation`) só é gravado quando há ao menos um modulador (`TrackModulation.isEmpty` é falso): um documento sem modulação sai byte a byte como antes (teste `sem modulação o JSON fica como antes...`). O formato é `{"sources": [ ... ]}`. Cada elemento de `sources` (`ModSource.toJson`, lido por `ModSource.fromJson`):

| Campo | Tipo | Leitura tolerante | Padrão se falta |
|---|---|---|---|
| `id` | texto | obrigatório (sem ele o modulador é descartado) | | 
| `kind` | `lfo`, `follower` ou `macro` (o nome do enum `ModKind`; o índice é o código do motor) | nome desconhecido vira `lfo` | `lfo` |
| `shape` | `sine`, `triangle`, `saw`, `square`, `sampleHold` (`LfoShape`) | desconhecido vira `sine` | `sine` |
| `rate` | número, Hz da taxa livre | limitado a 0,01–50 | 1 |
| `sync` | booleano | | `false` |
| `division` | inteiro 0 a 23 (`base·3 + variação`) | limitado a 0–23 | 12 (`1/4`) |
| `depth` | número: amplitude do LFO, ganho do seguidor | limitado a 0–8 (o motor limita de novo: 0–1 no LFO e na macro) | 1 (o construtor dá 2 ao seguidor novo, mas o `fromJson` lê 1) |
| `phase` | número 0..1 de ciclo | limitado a 0–1 | 0 |
| `bipolar` | booleano | | `true` (o construtor dá `false` ao seguidor e à macro novos) |
| `attack`, `release` | milissegundos do seguidor | limitados a 0–5000 (desde a fase 18 A os knobs do cartão andam em 0,5–5000 e 5–5000; antes só em 0,5–500 e 5–3000, então o JSON aceitava o que a tela não alcançava) | 10 e 120 |
| `value` | número 0..1 da macro | limitado a 0–1 | 0 |
| `dests` | lista de `{"target": {"kind", "ref", "param"}, "amount"}` | um destino que não se lê derruba **o modulador** (o `try` de `TrackModulation.fromJson` o descarta) | vazia |

`target` é o `AutoTarget` da automação (`kind` em `volume`, `pan`, `instrument`, `effect`, `send`; `ref` o id do efeito ou da faixa barramento; `param` o id do parâmetro); `amount` fica em −1..1 (padrão 0,25). `TrackModulation.fromJson` aceita só um mapa com a lista `sources`; qualquer outra coisa vira "sem modulação"; mantém no máximo **4** moduladores e corta cada um em **4** destinos (o motor tem os mesmos limites).

**Compatibilidade.** Projeto anterior à fase 16: abre normalmente, sem modulação. Projeto novo num app anterior: o campo é ignorado ao abrir e **some** ao salvar (o app antigo não o conhece) `(lido do código; não testado)`. O `.jopendaw` e o documento da nuvem levam os campos como qualquer outro; `remapDocIds` (`project_file.dart`) refaz os alvos `effect` (pelo id do slot) e `send` (pelo id da faixa) e descarta o destino cujo alvo não existe (`TrackModulation.remapTargets`). Duplicar a faixa (`duplicateTrack`) copia a modulação com ids de modulador novos e os alvos de efeito reapontados para os efeitos da cópia (os de envio ficam, porque apontam o barramento).

### Controlador

- **Leitura e edição.** `modulationOf(track)` (−1 é o master; `null` se a faixa não existe) e `editModulation(track, fn, {undoable})`, que passa por `edit`/`mutate` (histórico e sincronização normais). Um arraste guarda `checkpoint()` no início e edita com `undoable: false`.
- **Operações** (`modulation_ops.dart`, extensão de `DawController`): `modAddSource`, `modRemoveSource`, `modRemoveDest`, `modAssign` (o `Modular…`: valida `canModulate`, os limites 4 e 4 e devolve o **texto da recusa** em vez de lançar), `modApplyPreset`, `canModulate` (usa `autoInfo(...).stepped`: opções e inteiros ficam de fora), `modRangeOf` e `modTargetLabel` (o rótulo do menu `A` da automação, `Destino removido` se o alvo sumiu). Cada operação é **um passo** de histórico.
- **Sincronização.** `_modulationCalls(sends)` monta a lista; só entram os moduladores com ao menos um destino que `_resolve` acha e que não é `Curve.choice` nem `Curve.integer`; a escala é `2` (fader) para volume e envio (`code` 0 e 4), `1` (log) para `Curve.log` e `0` no resto. Comparada com `_SyncCache.mod` por `_sameCalls`; se difere, vai `mod_clear` mais a lista inteira. A lista é reenviada por inteiro a cada mudança, mas desde a fase 18 A o motor **preserva** a fase do LFO livre e o nível do seguidor de quem volta com o mesmo tipo na mesma posição, então editar um modulador com o projeto tocando não recomeça os LFOs livres nem os seguidores (resolvido em `c1fb192`; ver [Motor](01-motor.md#modulação-enginesrcmodulationrs-fase-16-b)).
- **Limpeza.** `_prune()` (que roda depois de todo `mutate`) chama `TrackModulation.prune` com `_modTargetOk`: some o **destino** cujo efeito, envio ou parâmetro deixou de existir; o modulador continua (o comentário de `prune` foi corrigido na fase 18 A para dizer isso; antes falava em tirar também os moduladores sem destino que não são macro, mas o código só removia destinos).
- **Congelar.** `bounceTrack` (congelar em áudio) leva à faixa nova os moduladores com destino em volume, pan ou envio (cópia com ids novos, só esses destinos); `_bounceDoc` tira do render a modulação de volume e pan e deixa a de instrumento, efeito e envio, que então vira som.
- **Dock.** `Dock.modulation` é o último valor do enum. `showDock` o trata como o rack de efeitos (`showEffects(faixa selecionada ou −1)` e depois `setDock(Dock.modulation)`) **quando vem de outro painel**; vindo de `Efeitos` (ou de `Modulação` para `Efeitos`) ele só faz `setDock(d)`, e `setDock` não refaz `_effectsId` nessa troca, então a faixa (ou o master) à vista é a mesma nas duas abas (fase 18 A). `_select` mantém `_effectsId` acompanhando a faixa selecionada nas duas abas.

### Interface (`modulation_ui.dart`, `knob.dart`, `midi_learn_ui.dart`, `dock.dart`)

- `ModulationPanel` (cabeçalho com `Adicionar` e `Presets` como `PopupMenuButton`, aviso `InlineNotice`, cartões num `Wrap` de 200 a 340 px) → `_SourceCard` (controles por tipo; `_Toggle` para `Livre`/`Andamento`/`Bipolar`/`Unipolar`, `_Drop` para forma e divisão, `Knob` de cor `modulationColor` com as tabelas `ParamSpec` locais: `Taxa` 0,01–50 Hz log, `Profundidade` 0–1 (era `Profund.`), `Fase` 0–1 lida em graus, `Ganho` 0–8, `Ataque` 0,5–5000 ms log, `Soltura` 5–5000 ms log, `Valor` 0–1) → `_DestRow` (nome, `+25%`, `Slider` de −1 a 1, `Tirar este destino`).
- `showModulateDialog` / `_ModulateDialog` (`Modular: <controle>`) e `modulateAction` (`KnobMenuAction.withContext`, para o menu do knob); no menu de fader e pan, `showMidiLearnMenu` ganhou o valor `'modulate'`. `midiLearnActions` acrescenta `modulateAction` quando `canModulate`. Desde a fase 18 A: `MidiLearnControl(secondaryMenu: true)` envolve o filho num `GestureDetector` só para toque e caneta (`supportedDevices: touch, stylus, invertedStylus`) cujo `onLongPress` abre o mesmo `showMidiLearnMenu` (sem abrir no modo aprender, em que a sobreposição tem o próprio toque longo); o menu do envio (`_SendRowState._menu`, com envio criado) ganhou o item `Modular…` (`'modulate'` → `showModulateDialog`); o mini fader do cabeçalho usa o mesmo `MidiLearnControl(secondaryMenu: true)`; `Knob._menuHint()` monta o fim da dica a partir de `extraActions` (rótulo sem o ` (...)` final, por isso `Remover mapeamento (Canal 1 · CC 74)` vira `Remover mapeamento`), e as dicas do fader, do pan e do envio citam `Modular…` escritas à mão. O menu do painel de modulação esconde os presets sem alvo (`modPresets.where(!hideWithoutTarget || availableFor(...))`).
- `Knob.modRange` (função opcional) devolve `(mín, máx)` em fração do curso; o `_KnobPainter` desenha o arco por fora do trilho (raio do trilho + meia espessura + 1,6; espessura 1,8; mínimo de 0,02 do curso de 270°; opacidade 0,4 no knob esmaecido). Só o painel de instrumento (`instrument_panel.dart`) e os knobs do painel de efeitos (`fx_editors.dart`) passam `modRange`; os controles desenhados à mão (gráficos) não `(não confirmado)`. `MidiLearnControl` desenha o `_ModDot` (6 px, `ValueKey('mod-dot')`) em todo controle com modulação.
- Chaves de teste: `mod-add`, `mod-presets`, `mod-<id>`, `mod-shape-<id>`, `mod-division-<id>`, `mod-remove-<id>`, `mod-add-dest-<id>`, `mod-dest-remove-<id>-<i>`, `mod-amount-<id>-<i>`, `modulate-source-<id>`, `modulate-new-<tipo>`.

### Testes

`app/test/modulation_test.dart`: 21 casos (15 `test` e 6 `testWidgets` na contagem de hoje; a descrição abaixo é da fase 16 B e ainda vale, com os presets atualizados na fase 18 A: `wobble` confere ±1 oitava e o extremo em 4800 Hz com o corte padrão, o `vibrato` é recusado no sintetizador e achado no `Sampler`). A fase 18 A acrescenta em `app/test/fase18a_test.dart` o grupo `modulação` (aba que mantém a faixa, inclusive o master, e toque longo no fader com `Modular…` e a dica do knob). Lógica (JSON sem o campo, ida e volta dos três tipos e do master, JSON estragado, divisões, duplicar, apagar e desfazer, as chamadas e a ordem, só reenvia quando muda, escalas, alvos sem efeito e opções, o render recebe tudo, limites, atribuir com 25%, presets, intervalo do anel) e os de widget (aba vazia e com quatro moduladores a 360 px, adicionar e aplicar preset e apagar, entre outros). Não há teste de widget do anel do knob nem do diálogo `Modular…`; o toque longo abrindo `Modular…` é testado sobre um `MidiLearnControl` genérico, não sobre o `_Fader`, o `_PanKnob` nem a linha do envio do mixer `(testado só por testes automáticos)`.

### Armadilhas

- **Resolvido em `c1fb192` (fase 18 A), o que esta seção listava:** (1) o `Vibrato de afinação` escolhia o primeiro parâmetro em `ct` linear (no sintetizador a `Desafinação` do `Oscilador 2`, no FM o `Fino` do `Operador 1`, no wavetable a `Desafinação` do `Oscilador 1`): agora só o `Sampler` tem o preset (`Afinação`, +6%) e nos outros ele some do menu; (2) o `Wobble no corte` usava +40% em escala log e prendia a onda no topo com o `Corte` padrão: agora é ±1 oitava (`_octaveAmount`, cerca de +10% do curso de 20 Hz a 20 kHz); (3) o texto de `prune` prometia apagar moduladores sem destino: o comentário agora diz que eles ficam; (4) a aba `Modulação` recalculava a faixa pela seleção e abandonava o master aberto pelo rack: `showDock` vindo de `Efeitos`/`Modulação` só troca a aba; (5) o tooltip do knob não citava `Modular…`: `Knob._menuHint()`; (6) só o botão direito abria o `Modular…` do fader e do pan, e o envio e o mini fader não tinham o menu: toque longo no fader, no pan e no mini fader (`MidiLearnControl`) e o item `Modular…` no menu do envio (testado só por testes automáticos; o toque longo não foi visto num aparelho); (7) reenviar a modulação recomeçava LFOs e seguidores: ver o Motor.
- **Continuam valendo:** `prune` não apaga moduladores, então uma faixa pode ficar com cartões sem destino (eles não vão ao motor); o estado do motor é por **posição** do modulador, então apagar o modulador 1 de dois do mesmo tipo faz o 2 herdar o estado do 1 uma vez `(lido do código; não confirmado em uso)`; as dicas do fader, do pan e do envio citam `Modular…` escritas à mão (não saem de `extraActions`), então uma entrada nova nesses menus exige mexer nos textos.

## Sequenciador de passos (fase 17 B)

> Para quem mexe na aba `Passos` (`app/lib/daw/step_sequencer.dart` e `step_sequencer_ui.dart`). Manual do usuário: [05c](../manual/05c-sequenciador-de-passos.md).

### Visão geral

A aba é uma **visão** das notas de um `MidiClip`, não um formato: nada novo no documento, no JSON, no motor nem nas pontes. Uma linha da grade é uma altura (`pitch`); um passo é uma subdivisão do compasso; um passo aceso é uma `MidiNote` daquela altura no início do passo. Tudo passa por `DawController.checkpoint`/`mutate`, então desfazer, sincronização, exportação `.mid` e o som são os das notas de sempre.

```
Dock.steps ─ StepSequencerPanel (step_sequencer_ui.dart)
   │  stepTarget(c): faixa selecionada + clipe (selectedClip → editingClip → o sob o cursor)
   │  _Prefs por clip.id (estático, só em memória): res, bars, swing, pending, selected, brush
   ▼
StepLayout (step_sequencer.dart) ── pos(i), nearest, cellOf, onGrid
   ▼
readRow / addStep / removeStep / setStepVelocity ... ─► clip.notes  ─► c.mutate ─► motor
```

### Peças e responsabilidades

| Arquivo | Papel |
|---|---|
| `step_sequencer.dart` | Puro (sem widgets): `stepEps`, `maxPatternBars` (8), as velocidades (`stepNormalVelocity` 0,8, `stepAccentVelocity` 1,0, `stepGhostVelocity` 0,3), `StepDynamic` e `dynamicOf` (acento a partir de 0,95, fantasma até 0,4), `StepResolution` e a lista `stepResolutions`, `StepLayout`, `StepHit`, `readRow`, as edições (`addStep`, `removeStep`, `setStepVelocity`, `clearRows`, `shiftRows`, `invertRows`, `randomizeRows`, `fillEvery`, `retimeSwing`, `repeatPattern`, `copyPattern`, `pastePattern`, `sortNotes`), as linhas (`drumRows`, `zoneRows`, `stepRowsOf`, `stepsAvailable`) e os 9 padrões (`stepPresets`, `presetNotes`, `applyPreset`) |
| `step_sequencer_ui.dart` | `stepTarget`, `StepSequencerPanel` (barra, avisos, ações, diálogos), `_Surface` (ponteiros crus, sem entrar na arena de gestos), os pintores (`_HeaderPainter`, `_GridPainter`, `_StripPainter`, `_PlayheadPainter`), `_Prefs` |
| `controller.dart` | só o valor `Dock.steps` no fim do enum `Dock` |
| `dock.dart` | a aba (`Icons.grid_on`, rótulo `Passos`, tooltip `Sequenciador de passos da bateria e do sampler fatiado`), o assunto (`<clipe> · <faixa>`) e `iconsOnly` abaixo de 760 px quando a aba existe (560 px sem ela). Não há tecla nem botão de barra para a aba |

### O modelo grade ↔ notas

- **Tolerância.** Uma nota está no passo `i` se `|start − pos(i)| ≤ stepEps` (1e-3 batida). `readRow` agrupa as notas de uma altura pelo passo mais próximo (`StepLayout.nearest`, com empate para o passo anterior) e devolve um `StepHit` por passo, com `offGrid` verdadeiro quando nenhuma nota está exatamente nele. Notas depois do padrão (`cellOf` nulo) não entram na leitura.
- **Escrita.** `addStep` só liga passo vazio, cria `MidiNote(pitch, pos(i), stepNoteLength(step), velocity)` com `stepNoteLength = min(step, 0,25)`; `removeStep` tira **todas** as notas do `StepHit` (as fora da grade também); `setStepVelocity` não mexe no `start`.
- **Ordem.** Cada edição termina em `sortNotes` (estável, pelo início), porque o resto do app espera as notas ordenadas.
- **Linhas.** Bateria: as 12 de `drumPieces` em `_drumRowOrder` (bumbo, caixa, palmas, chimbal fechado, chimbal aberto, aro, toms, pratos, cowbell); qualquer peça fora dessa lista iria no fim. Sampler: `zoneRows`, uma linha por zona (nota = `root.clamp(lo, hi)`, duplicadas descartadas), nomeada `Fatia N · <nota>` com `N` contando linhas. `stepsAvailable` é falso para sampler sem zonas e para os outros tipos.
- **Resolução.** `StepLayout.of(barBeats, bars, step, swing)`: `steps = max(1, ceil(barBeats × bars / step − 1e-6))`. O `barBeats` vem de `c.doc.meter.barBeatsAt(clip.start)` (o mapa de compassos vale). Não há detecção automática da resolução: `_Prefs.res` nasce em `1/16` e só muda pelo menu `Passo` ou por um padrão de fábrica. O que é automático é `Compassos` (`_barsOf`): sem valor explícito, `floor(início da última nota / compasso) + 1`, limitado a 1 e aos compassos do clipe (até `maxPatternBars`). Um padrão de fábrica ou os botões `−`/`+` fixam o valor.
- **Swing.** `pos(i) = i·step + (i.isOdd ? swing·step : 0)`, ou seja, atrasa os passos de índice ímpar (o 2º, o 4º... da tela). `retimeSwing(notes, layout, from, to)` reposiciona só as notas que `onGrid` no passo ímpar do swing `from`; o resto (passos pares, notas fora da grade, notas depois do padrão) não anda. O swing entra na leitura (`StepLayout.swing`), então depois de aplicar os passos continuam acesos.
- **Ações.** Todas recebem o conjunto de alturas do escopo (a linha selecionada ou todas) e o `StepLayout`, e só tocam notas cujo `cellOf` existe (dentro do padrão), exceto `repeatPattern`, que olha o clipe todo: copia as notas com `start < span`, apaga as com `start ≥ span` e replica até `clipLength`, cortando o comprimento no fim do clipe.
- **Padrões.** `StepPresetRow(pitch, pattern, step)`: `.` vazio, `x` normal, `X` acento, `o` fantasma; cada caractere vale `step` batidas (0,25 por padrão; o chimbal do `Trap` usa 0,125 e o `Shuffle` 1/3). `applyPreset` apaga as notas de `drumPieces` com `start` em `[0, span)`, com `span = bars × 4` (fixo em 4 batidas por compasso, mesmo em 3/4), e soma as do padrão que caem antes do fim do clipe. A UI define `res = p.resolution` e `bars = ceil(span / barBeats)`.

### Interface

- **Barra** (`_toolbar`): `Wrap` a partir de 700 px de largura; abaixo, uma linha que rola na horizontal. Chaves de teste: `step-res`, `step-bars-minus`, `step-bars`, `step-bars-plus`, `step-swing`, `step-swing-apply`, `step-swing-off`, `step-brush-normal|accent|ghost`, `step-presets`, `step-actions`, `step-preset-<id>` (`four`, `rock`, `funk`, `hiphop`, `trap`, `dembow`, `bossa`, `house`, `shuffle`), `step-number-slider`, `step-number-ok`, `step-notice`, `step-create`, `step-grid`, `step-strip`, `step-row-<pitch>`, `step-ear-<pitch>`.
- **Gestos** (`_Surface`): `Listener` com `HitTestBehavior.opaque`; mouse e caneta pintam ao arrastar; toque: o toque longo de 300 ms pinta e trava a rolagem (`_locked`), movimento acima de 10 px cancela e vira rolagem, o toque curto vale um gesto no `PointerUp`. O primeiro passo decide ligar ou apagar (`_painting`) e o arraste fica na linha em que começou (`_lastRow`). Dois toques no mesmo passo em 320 ms (`_lastCell` + `_dblTimer`) viram acento. Um gesto é um `checkpoint()` na primeira mudança e depois só `mutate` (`_gestureEdit`, `_ckpt`).
- **Prévia.** `_audition` chama `c.noteOn`/`noteOff` por 220 ms, só com o transporte parado (`c.playing.value` falso).
- **Tamanho.** Coluna de nomes de 152 px (112 abaixo de 560 px), passos de 32 a 56 px (`_cellMin`, `_cellMax`), linhas de 32 px, faixa de velocidade de 64 px. A faixa `Velocidade` mapeia `1 − y/64` para 0,05–1,0.
- **Cursor.** `_PlayheadPainter` escuta `c.beat` e `c.playing`; usa `rel % span` (dá a volta no padrão) e `_follow` rola a grade com `jumpTo` quando o cursor sai da janela.
- **Ações e avisos.** `_menu` (`clear-row`, `clear-all`, `copy`, `paste`, `left`, `right`, `invert`, `random`, `every`, `repeat`), `_pickNumber` (diálogo com `Slider`), avisos em `_notice`: `Padrão "<nome>" aplicado.`, `Padrão copiado (N notas).`, `Swing de N% aplicado (M notas).`, `Swing tirado (M notas).`, `Padrão repetido até o fim do clipe (N vez|vezes).`, `O padrão já ocupa o clipe inteiro.`
- `_Prefs` (por `clip.id`) e `_clipboard` são estáticos do `State`: valem enquanto o app está aberto, nunca vão para o documento.

### Como testar

```bash
cd app
flutter test test/step_sequencer_test.dart      # 29 testes de lógica: ida e volta, tolerância, fora da grade, ações, swing, padrões, linhas
flutter test test/step_sequencer_ui_test.dart   # 18 testes de widget: toque, arraste, toque longo, duplo toque, faixa de velocidade, padrões, ações, swing, sampler, 360 px
```

Os testes de UI usam um `StepDaw` (subclasse de `DawController` com o motor de mentira) e as chaves acima. Nada disso foi visto rodando no Chrome nem no Android `(testado só por testes automáticos)`.

### Armadilhas

- **Swing como estado da tela.** `_Prefs.swing` não vai ao documento. Depois de reabrir o app, as notas seguem atrasadas mas o `StepLayout` volta a `swing = 0`: elas viram "fora da grade" e `Tirar swing` fica apagado. Um `Ctrl+Z` logo depois de `Aplicar swing` desfaz as notas mas não `_Prefs.swing`/`pending`, então a grade passa a esperar swing em notas retas e `Aplicar swing` fica apagado até mexer no controle `(lido do código; o teste de swing de `step_sequencer_ui_test.dart` faz `c.undo()` e depois toca em `Aplicar swing`, que estaria apagado, então não prova o caso)`.
- **Padrão de fábrica e swing.** `applyPreset` escreve notas retas e mantém `_Prefs.swing`; com swing aplicado, os passos ímpares do padrão ficam fora da grade.
- **Swing por resolução.** O swing aplicado é um só valor por clipe (`_Prefs.swing`), usado em qualquer resolução. Aplicado em `1/16`, as colcheias (índices pares) não andam; ao trocar para `1/8`, o layout espera atraso nas colcheias fracas e as notas atrasadas em 1/16 ficam fora da grade.
- **Ações só dentro do padrão.** `clearRows`, `shiftRows`, `retimeSwing`, `copyPattern` etc. usam `cellOf`, que devolve nulo depois do fim do padrão (`Compassos`). Swing depois de `repeatPattern` só mexe no primeiro trecho.
- **`addStep` não confere o fim do clipe.** Só o gesto (`_beyondClip`) recusa passos além dele; `invertRows`, `fillEvery`, `randomizeRows` e `pastePattern` podem gravar notas depois do fim do clipe (não tocam, mas ficam no documento) `(lido do código)`.
- **`nearest` em empate** escolhe o passo anterior (nota no meio de dois passos vai para o de baixo); duas notas na mesma linha no mesmo passo ficam num `StepHit` só e `removeStep` as apaga juntas.
- **O arraste do mouse não interpola** entre dois `PointerMove`: um movimento rápido pode pular passos `(lido do código)`.
- **`repeatPattern` faz `_run` (checkpoint) mesmo sem nada a repetir**: o `Ctrl+Z` ganha um passo vazio.
- **`applyPreset` usa 4 batidas por compasso** (`StepPreset.span = bars × 4`), mesmo com o mapa de compassos em 3/4 ou 6/8.
- **Descrição do `Rock`:** o texto diz "bumbo no 1 e no 3", mas o desenho tem também o passo 11 (`x.......x.x.....`).
- **Nome `Fatia`** para toda zona, inclusive de multi-sample que não veio de `Fatiar sample…`.


## Histórico com nomes e versões nomeadas (fase 18 C)

> Para quem mexe em `app/lib/daw/history.dart`, `history_ui.dart`, `snapshots.dart`, `snapshots_ui.dart` e nos pontos do `DawController` que os ligam (commits `c0ea89b`, `03e6d05` e `ed605e3`). Manual do usuário: [02d](../manual/02d-historico-e-versoes.md).

### Visão geral

Duas camadas de "voltar atrás", sem nada novo no documento, no JSON, no motor, nas pontes nem no servidor:

```
edit / editAs / checkpoint(label)            VersionKeeper (snapshots.dart)
   └─ _undo: List<HistoryEntry>  ◄─ _travel ─► _redo      LocalStore  snapshots:<projeto>:<id>
        (json de ANTES, label, hora)                        ▲  save / list / load / rename / delete
   historySteps(_undo, _redo) ─► painel Histórico           │  noteEdit() ◄── _scheduleSave()
   jumpToHistory(n) = _travel(count: k)                     │  onOpen()   ◄── open()
   restoreDocument(doc, label) ── checkpoint + _adopt ◄─────┘  (Restaurar, em snapshots_ui.dart)
```

O histórico é memória da sessão (a pilha do controlador); as versões são texto no guardado local e sobrevivem ao fechar o projeto. Nenhuma das duas sobe para a nuvem.

### Peças e responsabilidades

| Arquivo | Símbolos | Papel |
|---|---|---|
| `app/lib/daw/history.dart` | `historyLimit` (200), `unlabeledStep` (`Edição`), `HistoryEntry {json, label, time}` (`title`, `labeled`), `HistoryStep`, `historySteps(undo, redo)`, `formatClock24`, `stepText`, `undoTooltip` | Tipos puros e a leitura que o painel usa: as linhas do mais recente ao mais antigo (refazíveis, feitas, e o `Início do histórico` por último) |
| `app/lib/daw/history_ui.dart` | `HistoryStepButton`, `showHistoryMenu`, `HistoryMenuChoice`, `runHistoryChoice`, `undoTooltipText`/`redoTooltipText`, `HistoryDialog`, `showHistoryDialog`, `confirmClear` | Os botões `Desfazer`/`Refazer` (um `Listener` para o botão direito, um `GestureDetector.onLongPressStart` para o dedo e um `Tooltip` com `triggerMode: manual`, para a pressão longa não disputar com o tooltip), o menu de três itens, o painel e a confirmação de `Limpar` |
| `app/lib/daw/snapshots.dart` | `VersionKeeper`, `Snapshot`, `VersionList`, `VersionsPrefs`, `parseSnapshotEnvelope`, `snapshotKey`/`snapshotPrefix`, `diffDocs`/`DocDiff`/`DiffRow`/`describeDiff`, `duplicateVersionAsProject`, `formatStamp`, `formatSize`, constantes `autoKeep` (20), `snapshotWarnBytes` (50 MiB), `openGap` (1 h), `defaultAutoMinutes` (15), `autoMinuteChoices` (5, 10, 15, 30, 60), `noVersionsMessage` | Lógica das versões, sem widget: guardar, listar, carregar, renomear, apagar, automáticas, comparar e duplicar |
| `app/lib/daw/snapshots_ui.dart` | `VersionsDialog`, `showVersionsDialog`, `promptVersion`, `saveVersionFlow`, `saveVersionNow`, typedefs `DuplicateVersion` e `OpenProject` | As telas. Os dois typedefs são as costuras dos testes (criar o projeto novo e navegar) |
| `app/lib/daw/controller.dart` | `_undo`/`_redo` (`List<HistoryEntry>`), `clock`, `nextUndo`/`nextRedo`, `historyCount`, `historyRows`, `clearHistory`, `jumpToHistory`, `edit(label:)`, `editAs`, `checkpoint([label])`, `_travel(count:)`, `_adopt`, `versions` (`late final VersionKeeper`), `restoreDocument`, `autoCommitUndo` | O ponto de ligação. `_scheduleSave` chama `versions.noteEdit()`, `open()` chama `versions.onOpen()` (sem esperar), `dispose()` fecha o `versions` |
| `app/lib/daw/local_purge.dart` | `_versionKeys` | `purgeLocalProject` apaga também as chaves `snapshots:<projeto>:*` (inclusive as ilegíveis) |
| `app/lib/daw/keymap.dart`, `app/lib/screens/project_screen.dart` | ação `history.open` (`Mod+Shift+H`, categoria `Edição`, contexto global), `_actionFor` | O atalho abre `showHistoryDialog` com o `context` do nó em foco |
| `app/lib/daw/structure_menu.dart`, `app/lib/daw/transport_bar.dart` | `ViewMenu` (itens `history` e `versions`), os dois `HistoryStepButton` no lugar dos `IconButton` | Onde o usuário chega |
| Vários arquivos de `daw/` (`controller.dart`, `timeline.dart`, `mixer_panel.dart`, `piano_roll_input.dart`, `piano_roll_tools.dart`, `track_groups.dart`, `modulation_ops.dart`, `sampler_zones_controller.dart`…) | `editAs('Nome', …)` e `checkpoint('Nome')` | Os rótulos (lista no [manual 02d](../manual/02d-historico-e-versoes.md#os-nomes-dos-passos)) |

### Fluxo de dados e ciclo de vida

**Histórico.** `checkpoint([label])` empilha `HistoryEntry(jsonEncode(doc.toJson()), label, clock())` em `_undo` (corta em `historyLimit`, limpa `_redo`). `undo`/`redo` são `_travel(from, to)`: para cada passo tira o último de `from`, põe em `to` uma entrada com o documento de AGORA e o **mesmo rótulo e hora**, e adota o JSON tirado (`_adopt`); no fim, uma só vez, `_prune`, `_sync`, `_scheduleSave` e `notifyListeners`. `jumpToHistory(n)` (n = quantas ações valem depois do passo, 0 é o início; `clamp(0, historyCount)`) é `_travel` com `count` = distância, então ir três passos atrás custa um sync e um salvar. Não faz nada gravando. `clearHistory` esvazia as duas pilhas e nada mais; `_applyRemote` (a nuvem trocou o projeto) também as esvazia, com o `remoteNotice`.

`historySteps` numera de 1 a `undo.length + redo.length`; a linha `current` é a de posição `undo.length` (o `Início` quando `_undo` está vazia); `future` são as de posição maior. Uma entrada de `_redo` guarda o documento de **depois** da ação, e a de `_undo`, o de **antes**: o rótulo é o mesmo nas duas.

**`_adopt(json)`** é o trecho que antes morava dentro de `_travel` e agora é compartilhado com a restauração: monta o `DawDoc` do JSON e devolve ao documento novo o que é preferência do aparelho (`metronome`, `count_in`, `rec_latency_ms`, `metronome_options`, `pre_roll`, punch, `midi_map`, `armed`/`monitor` de cada faixa, `collapsed` de cada pasta e `loop_on` quando a região do loop é a mesma). Por isso um `Restaurar` não desfaz nada disso.

**Restaurar** (`_restore` em `snapshots_ui.dart`): confirma; `keeper.load(id)`; `keeper.save(name: 'Antes de restaurar <nome>')` (não cria se o projeto é idêntico à versão mais nova; se a mais nova é automática e idêntica, a **promove** e a renomeia); `c.restoreDocument(doc, label: 'Restaurar versão “<nome>”')`. `restoreDocument` (`Future<bool>`): devolve `false` gravando ou com documento inválido; carrega no motor os áudios que o documento cita e `_sampleIds` ainda não tem (`_loadSample`; o que falta vai para `missing`); `checkpoint(label)`, `_adopt`, `_prune`, `_sync`, `_scheduleSave`. É, portanto, um passo comum do histórico.

**Versões.** `VersionKeeper(store, projectId, currentJson, clock, hasContent)`; toda escrita passa por `_serial` (uma fila de `Future`, sem corrida entre salvar e limpar). `save` compara só com a versão **mais nova** (`jsonEncode(doc)` igual): igual e a mais nova é manual, devolve `null`; igual e ela é automática com um pedido manual, reescreve-a como manual (`_rewrite`, o mesmo `id`). Senão, `seq` = maior `seq` + 1, `id` = `<seq em base 36>-<milissegundos em base 36>`, grava o envelope, zera `_baseline` para agora e, se a versão é automática, `_pruneAuto` apaga as automáticas além das 20 mais novas. `rename` escreve `auto: false`: renomear tira da limpeza. `list` lê todas as chaves do prefixo, **descarta** (e devolve em `corruptKeys`) as que `parseSnapshotEnvelope` rejeita ou cujo `id` do envelope não bate com a chave, e ordena por `created_at` e `seq` (mais nova primeiro).

**Automáticas.** `noteEdit()` (chamado por todo `_scheduleSave`, isto é, toda `mutate`): sem `auto`, nada; `_baseline ??= agora`; se passaram `prefs.minutes` desde o `_baseline` e não há uma automática em andamento (`_autoBusy`), move o `_baseline` para agora e salva `Versão automática` (`auto: true`). Não há `Timer`: só uma edição dispara, e a versão já leva essa edição. `onOpen()`: carrega as preferências; sai se `auto` está desligado ou `hasContent()` é falso (o `controller` passa "alguma faixa tem clipe de áudio ou MIDI"); salva `Ao abrir o projeto` se não há versão ou a mais nova tem mais de `openGap`.

### Contratos

**Chave e envelope.** Chave do guardado local `snapshots:<id do projeto>:<id da versão>` (web: IndexedDB `jopendaw`, repositório `kv`, via `idbKeys(prefix)`; Android: `FileStore`, arquivo `.txt` com o nome da chave em `%XX`, pasta `jopendaw` dos documentos). Valor: texto JSON

```json
{"format":"jopendaw-version","version":1,"id":"1-abc","seq":1,"name":"…","note":"…","auto":false,
 "created_at":"2026-09-30T16:50:00.000Z","tracks":4,"clips":3,"doc":{ …DawDoc.toJson()… }}
```

`doc` é o JSON do `DawDoc` sem os áudios (só o mapa `samples` com os hashes). `parseSnapshotEnvelope` devolve `null` para `format` diferente, `version` maior que 1 (ou não inteira), `doc` que não é objeto com `tracks` lista, `created_at` que não lê e `id` vazio; `tracks` e `clips` ausentes são recontados do `doc` (pastas não contam como faixa; clipes são áudio + MIDI). `Snapshot.bytes` é o `length` do texto (caracteres, não bytes UTF-8). Preferências: chave `versions-prefs`, `{"auto": bool, "minutes": int}`; `VersionsPrefs.fromJson` aceita minutos de 1 a 1440 (a tela só oferece 5, 10, 15, 30, 60) e usa 15 fora disso.

**Gancho para o servidor (não implementado).** `exportEnvelope(id)` devolve o texto pronto para um `PUT /projects/:id/versions/:id` futuro; `parseSnapshotEnvelope` lê de volta. Nada disso existe em `server/` nem em `api/client.dart`.

**Comparação.** `diffDocs(base, now)` (os dois JSON) devolve `DocDiff(rows, notes)`: linhas `Faixas` (a casca da faixa, sem `clips`, `midi`, `effects`, `sends`, `lanes`), `Clipes de áudio`, `Clipes MIDI`, `Notas MIDI` (multiconjunto `(clipe, nota)`; mover é remover e adicionar), `Efeitos` e `Raias de automação` (as das faixas mais as do master), `Envios` (chave `<faixa>><destino>`), `Marcadores`; frases de `bpm`, `beats_per_bar`, `tempo_map`, `meter_map`, `master_gain`, `master_pan`. "Adicionado" é o que está em `now` e não em `base`; "mudado", mesmo id com `jsonEncode` diferente.

**Duplicar.** `duplicateVersionAsProject` monta um `ProjectBundle(format: 1, samples: {}, missing: {})` com o `DawDoc` da versão e chama `importProjectBundle` ([Arquivo de projeto](#arquivo-de-projeto-jopendaw)): `remapDocIds`, nome livre (`importedProjectName`), `createProject` e `patchProject` (espelho do andamento e compasso) e grava `doc:<novo id>`. Sem áudios no pacote: os hashes já estão em `sample:<hash>` neste aparelho.

### Decisões e por quê

- **Rótulo por `editAs`.** O corpo de muitas edições tem várias linhas; `editAs(label, fn)` só troca a chamada (`edit(fn, label:)`) e deixa o corpo intacto. Gestos contínuos nomeiam no começo (`checkpoint('Volume da faixa')`, `_DragEdit.beginEdit(grab)`).
- **Continua JSON inteiro por passo.** Nada mudou no custo (até 200 cópias); o rótulo e a hora são dois campos a mais. A pilha de `refazer` guarda o rótulo e a hora originais, para o painel mostrar o mesmo nome dos dois lados.
- **Versões fora do documento.** O documento sobe inteiro para a nuvem a cada edição; um histórico dentro dele o faria crescer e sincronizar. Como chaves à parte, o tamanho só pesa no aparelho (alerta a 50 MiB por projeto) e o `.jopendaw` continua igual.
- **Restaurar é um passo do histórico, mais uma cópia de segurança.** O `Ctrl+Z` desfaz a restauração enquanto a pilha existe; `Antes de restaurar` cobre o caso de a pilha ter sido esvaziada.
- **Sem `Timer` nas automáticas.** Uma versão a cada N minutos de relógio guardaria cópias idênticas de um projeto parado; disparar pela edição evita e o dedupe cobre o resto.
- **`Tooltip` manual.** O dedo longo abre o menu; com o disparo padrão do tooltip os dois concorreriam pelo mesmo gesto.

### Como testar

`cd app && flutter test test/history_versions_test.dart test/keymap_test.dart` (o `keymap_test` guarda `history.open` no oráculo `legacyGlobal`). `history_versions_test.dart` tem 34 testes de lógica (rótulos e ordem, refazer guarda o rótulo, `jumpToHistory`, limpar, limite de 200, arraste, `Edição` para rótulo em branco, `Gravar automação`, a ação no catálogo; versões: salvar/listar/apagar, sem áudio no instantâneo, dedupe e promoção, renomear, restaurar como passo, preferências do aparelho preservadas, documento inválido, comparar, automáticas com relógio falso, limite de 20, abrir, arquivo corrompido, envelope inválido, alerta de espaço, duplicar, `purgeLocalProject`, aparelho novo, `exportEnvelope`) e 6 de tela (histórico e versões em 360 e 1512 px sem overflow, avisos de espaço e de arquivo ilegível com o interruptor, tooltip e menu de pressão longa nos botões), tudo com relógio falso (`c.clock`) e `LocalStore` de memória. Em `rack_test.dart`, `RackDaw.checkpoint` ganhou o parâmetro opcional `label`. Visto no Chrome pela sessão de código: histórico, `Versões` e `Salvar versão…` (teste de uso, não automatizado); o que não foi visto rodando: restaurar, comparar, renomear, apagar, duplicar, as automáticas com o tempo real e o Android.

### Armadilhas conhecidas

- **`setTempo` nomeia o passo errado.** Em `controller.dart`, `setTempo` usa `editAs('Região do loop', …)`; o `Salvar` da janela `Andamento e compasso` e o tap tempo (`commitTap`) entram no histórico como `Região do loop`. O nome certo seria `Mudar andamento` (o de `setTempoMap`).
- **Quem sobrescrever `checkpoint` precisa aceitar o rótulo opcional** (`void checkpoint([String? label])`), como o `RackDaw` dos testes. Um `checkpoint()` sem nome vira `Edição`.
- **Edição sem nome (`Edição`).** Hoje: `_replaceClip` da edição de áudio (`audio_edit.dart`: dividir por transientes, remover silêncio, quantizar por fatias), renomear clipe pelo piano roll (`piano_roll.dart`), os `checkpoint()` dos gestos de `modulation_ui.dart`, `clip_gain_dialog.dart` e `sampler_zones_panel.dart`.
- **`noteEdit` roda em toda `mutate`**, também nas que não são desfazíveis (ligar o metrônomo, abrir uma raia), e antes de as preferências serem lidas (o padrão é ligado, 15 min); `onOpen` as lê.
- **`hasContent` só olha clipes.** Um projeto só com faixas de instrumento e parâmetros (sem clipe) não ganha `Ao abrir o projeto`.
- **`bytes` são caracteres.** O alerta de 50 MiB soma `text.length`; nomes e notas acentuados têm mais bytes que caracteres.
- **Minutos fora da lista.** Um `versions-prefs` editado à mão com 7 minutos funciona (`noteEdit` usa o valor), mas a lista suspensa não marca nenhum item e mostra `a cada 7 min` como dica.
- **Palavras diferentes.** O item do menu é `Duplicar como novo projeto…` e o título da janela, `Duplicar como projeto novo`; o campo `Nome` da janela de nome limita em 80 caracteres e o nome de projeto aceita até 120 (o padrão `<projeto> — <versão>` pode passar de 80 e fica como veio).
- **A comparação é tirada uma vez.** `_diffs[id]` guarda o resultado do `Comparar`; só `Fechar comparação` e `Comparar` de novo o refazem.
- **Varrer o prefixo custa.** `list()` lê e decodifica o texto de todas as versões do projeto (para o resumo e o tamanho) a cada `save` (dedupe e limpeza das automáticas), a cada recarga do painel e em `onOpen`; com muitas versões grandes isso é trabalho na thread da tela.
- **O `Listener` do botão direito abre o menu também com o botão desligado** (sem passos ou gravando); `Histórico…` então abre o painel inerte.

## Edição de áudio (fase 18 B)

> Para quem mexe em `app/lib/daw/audio_edit.dart` e `audio_edit_ui.dart` (commit `d139758`). Manual do usuário: [03e](../manual/03e-editar-audio.md).

### Visão geral

Quatro ações sobre um clipe de áudio, todas **não destrutivas** e só no app: nada novo no documento (JSON), no motor, nas pontes nem no servidor. Uma ação troca o clipe por clipes que apontam para o **mesmo** `sample` (com `offset`, `length`, `gain` e fades próprios), ou só muda o `gain`. O resultado é um clipe comum: o motor, a exportação e a sincronização nem sabem que houve "edição".

```
timeline.dart  _ClipViewState._menu ── 'Editar áudio' ──► showEditAudioMenu (segundo menu, no mesmo ponto)
                                                              │ 'split' | 'strip' | 'normalize' | 'quantize'
audio_edit_ui.dart   SplitTransientsDialog / StripSilenceDialog / NormalizeClipDialog / QuantizeSlicesDialog
   │  _Subject.of ─► c.audioEditTarget(id)      (clipe, ClipRange do trecho decodificado, ou o erro em texto)
   │  _recompute  ─► detectCuts / planSilence / measureForNormalize+normalizePlanFor / planQuantize   (puro, a cada mudança)
   ▼  Aplicar
audio_edit.dart  extension AudioEditing on DawController
   splitClipAt · stripClipSilence · normalizeClip (async) · quantizeClipSlices  ──►  _replaceClip  ──► edit(...)  (um checkpoint)
```

### Peças e responsabilidades

| Símbolo (`audio_edit.dart`) | Papel |
|---|---|
| `microFade` (2 ms), `maxEditPieces` (500), `_ring` (10 ms), `_minTrimmed` (4 ms), `_edgeMin` (5 ms) | constantes da emenda, do teto de clipes por ação, do rabo da quantização, da fatia mínima cortável e da folga nas pontas |
| `AudioEditResult(ok, message, ids)` | o que a ação fez, já em texto para a tela (erro inline ou confirmação) |
| `sliceEditBlocker(clip)` | recusa `clip.processed` (`warp` com `sourceBpm`, `pitch != 0` ou `reverse`); `warp: true` sem `sourceBpm` **não** é recusado, porque não estica |
| `ClipRange` (`.of(full, clip)`) | visão sem cópia (`Float32List.sublistView`) do trecho `offset..offset+length`; `base` é o segundo do sample onde a visão começa (arredondado ao quadro) |
| `CutMode`, `EditGrid`, `detectCuts`, `gridCuts`, `filterCuts` | os três modos de corte; `EditGrid.fromSnap` converte o `Snap` da barra (`1/4`→`1/4`, `1/8`→`1/8`, o resto→`1/16`); `filterCuts` tira o que está fora, repetido, a menos de `minGap` do anterior (o primeiro, a menos de 5 ms do começo) ou a menos de 5 ms do fim |
| `SliceSpec`, `buildSlices` (`:227`), `specsForCuts` | uma fatia é `[srcStart, srcEnd)` do sample mais o instante `atSec` da linha do tempo onde ela toca; `buildSlices` monta os `AudioClip` (emendas de 2 ms, corte das sobreposições, lacunas, fades originais só nas pontas) |
| `SilenceSettings`, `planSilence` (`:322`), `buildKept` | silêncio por blocos de 1 ms (pico entre os canais) e os clipes dos trechos mantidos |
| `NormalizeMode`, `measureForNormalize`, `normalizePlanFor` (`:496`), `planNormalize`, `peakOf`, `rmsOf` | a medida (pico, RMS, LUFS via `measureLoudness` de `loudness.dart`) e o ganho com os tetos |
| `QuantizeSettings`, `planQuantize` (`:558`), `QuantizePlan` | cortes por transiente e, para cada fatia, a posição nova em batidas pelo mapa de andamento |
| `extension AudioEditing on DawController` (`:582`) | `audioEditTarget`, `_replaceClip`, as quatro ações e os resumos em texto (`silenceSummary`, `normalizeSummary`, `quantizeSummary`) |

`audio_edit_ui.dart`: `showEditAudioMenu`, `ClipPreview` (+ `_PreviewPainter`: onda, cortes numerados, trechos escurecidos, setas de movimento), o casco `_EditShell` (título, conteúdo rolável, `Cancelar` + ação; depois de aplicar só o aviso e `Fechar`), `_SliderRow`, `_Choice` e os quatro diálogos. Tudo pensado para 360 px.

### Fluxo de dados

1. **Abrir.** `_menu` (`timeline.dart`) seleciona o clipe (`c.selectClip`) e, em `'edit_audio'`, chama `showEditAudioMenu(context, c, clip.id, at)`, um segundo `showMenu` no mesmo `Offset` (não é um submenu de verdade; a setinha `>` é só o desenho).
2. **Prévia.** O diálogo guarda um `_Subject` (clipe, `ClipRange`, erro) obtido uma vez, e recalcula o plano a cada mudança. Deslizantes caros (`Sensibilidade`, `Distância mínima entre cortes`, os de silêncio) só refazem em `onChangeEnd`. `Normalizar` mede uma vez por modo (`_measures`/`_errors`) e refaz só a conta quando o `Alvo` muda.
3. **Aplicar.** O diálogo chama a ação do controlador, que **recalcula** tudo a partir do estado atual (não confia no plano da tela), valida e devolve `AudioEditResult`. Nenhuma ação mexe em nada quando recusa.
4. **Gravar.** `_replaceClip` faz `edit((_) { ... })`: tira o clipe original, insere as fatias **no mesmo índice** da lista da faixa e seleciona a primeira. `normalizeClip` usa `setClipGain` (um `editAs('Ganho do clipe', ...)`). Um `checkpoint` por ação: `undo` volta tudo.

### Contratos

- **Posição em tempo real.** Sem warp, o clipe toca em tempo real: o segundo do sample e o segundo da linha do tempo andam juntos. A grade e a quantização convertem batidas em segundos por `doc.secondsAt` e `doc.beatAtSeconds` (o mapa de andamento), nunca com `bpm` fixo.
- **Emenda.** A fatia seguinte começa `head = min(2 ms, srcStart − orig.offset, len/2)` antes do corte, com `fadeIn = head`; a anterior termina no corte com `fadeOut = 2 ms`. Fades da fatia: a primeira herda `fadeIn`, `fadeInShape` e `autoFadeIn` do original, a última herda `fadeOut`, `fadeOutShape` e `autoFadeOut`; as do meio têm `FadeShape.linear` e `autoFade*` nulos. Se `fadeIn + fadeOut` passa da duração, os dois são escalados e `SliceBuildReport.fadeShortened` avisa.
- **Sobreposição (quantização).** Com `nextAt` o começo da fatia seguinte: se `endSec > nextAt`, corta em `nextAt` (`keepTogether`, fade 2 ms) ou em `nextAt + 10 ms` (fade do rabo); se a fatia ficaria com menos de 4 ms, não corta (`overlapping`). Lacuna: `endSec < nextAt − 2 ms` (`gaps`).
- **Silêncio.** `thresholdDb` vira `10^(dB/20)`; blocos de `round(rate·0,001)` quadros; silêncio = corrida de blocos com pico `< thr` de pelo menos `minSilence` (NaN conta como silêncio); cada corrida perde `guardAfter` no começo (se não é a ponta do clipe) e `guardBefore` no fim (idem); fica só o que tem 1 ms ou mais. Trecho mantido com `|a − offset| < 1e-4` encosta na ponta do clipe e mantém o fade original daquele lado.
- **Normalização.** `ganho_dB = alvo − medido`; fora do pico, `if (peakDb + ganho_dB > 0) ganho_dB = −peakDb` (`limited`); `if (ganho_dB > 20·log10(maxClipGain)) ganho_dB = 20·log10(maxClipGain)` (`+12 dB`, `limited`); `gain = clamp(10^(dB/20), 1e-3, maxClipGain)`. O ganho **substitui** `clip.gain`. LUFS: `measureLoudness` (2 primeiros canais, gates de −70 LUFS e 10 LU); sem `hasLoudness` (menos de 400 ms ou abaixo de −70 LUFS) devolve o erro em texto.
- **Mensagens.** Os textos (`sliceEditBlocker`, `missingAudioMessage`, resumos) são a fonte; o manual os copia. `maxEditPieces` é checado em `splitClipAt`, `stripClipSilence` (sobre os trechos mantidos) e `quantizeClipSlices`.

### Decisões e por quê

- **Reaproveitar `slicePoints`** (o detector do fatiamento do sampler, espelho em Dart de `sampler_zones.rs`) em vez de um segundo detector: a paridade com o motor e os testes ficam num lugar só. Com `limit: 100000` para não cortar os ataques em 96 (ver [motor](01-motor.md#zonas-do-sampler-e-fatiamento-enginesrcsampler_zonesrs)).
- **Recusar warp/transposição/inversão** em vez de converter posições: o áudio derivado não tem os mesmos pontos do original, e fatias no som esticado exigiriam reprocessar cada uma.
- **Clipes novos, não metadados novos.** Fatiar não cria um tipo de clipe: o motor, os fades, o crossfade automático, a exportação e o `.jopendaw` continuam iguais, ao custo de até 500 clipes novos por ação no documento.
- **Normalizar = só ganho do clipe.** Não toca o áudio nem o fader; mede o trecho do clipe no original.
- **Sem deslocamento de bits** em `audio_edit.dart` (na web os inteiros do dart2js têm 32 bits; comentário no topo do arquivo).

### Como testar

```bash
cd app
flutter test test/audio_edit_test.dart      # 40 testes de lógica: cortes, dividir, silêncio, normalizar, quantizar
flutter test test/audio_edit_ui_test.dart   # 11 testes de widget (360 px, texto 1x e 1,4x; inversão; áudio fora do aparelho; o menu)
```

`audio_edit_test.dart` monta um `fakeController(FakeEngine())`, importa um WAV sintético (`drums`: rajadas de ruído nos instantes dados; `tone`; `noiseBursts`) e confere: cada corte a menos de 1 ms do ataque; soma das durações; desfazer volta o JSON idêntico (`docJson`); fades e `offset` do clipe original; tetos; recusas; quantização a menos de 1 ms da grade (inclusive com mapa de andamento 120 → 90 BPM). O `render` do teste simula o motor com **rampas retas** nos fades. Nada foi visto rodando no Chrome nem no Android, nem ouvido `(testado só por testes automáticos)`.

### Armadilhas conhecidas

- **A emenda de 2 ms não soma 1.** O código e o comentário do topo dizem "fade linear" e "os ganhos somam 1", mas `FadeShape.linear` é a curva `x²` (rótulo `Suave (padrão)`, espelho de `fade_curve` do motor, `FADE_*` = 0): entrada `x²` e saída `(1−x)²` somam 0,5 no meio da emenda (cerca de −6 dB por 2 ms), não 1. O teste usa `render` com rampas retas e por isso passa. A curva que soma 1 em amplitude para o mesmo material é `FadeShape.sCurve` (`S (seno cosseno)`). Mesma coisa nos fades de 5 ms do `Remover silêncio`, que aí não tem par a somar e é inofensiva `(lido do código; não ouvido)`.
- **Nome do passo no histórico.** `_replaceClip` chama `edit` sem `label`, então `Dividir`, `Remover silêncio` e `Quantizar` entram no histórico de desfazer como `Edição` (o de `Normalizar` é `Ganho do clipe`, por `setClipGain`). As outras edições da fase 18 C têm nomes.
- **`Distância mínima entre cortes` escondida.** `_SplitState._minGap` (padrão 0,05 s) é passado a `detectCuts` em todos os modos, mas o deslizante só aparece em `Por transientes`: em `N fatias iguais` e `Na grade` ela continua valendo e pode eliminar cortes (ex.: `1/32` acima de uns 150 BPM) sem aviso. `QuantizeSettings.minGap` fica fixo em 0,05.
- **`Dividir` não desliga com fatias demais.** `SplitTransientsDialog` só desliga o botão sem cortes; com mais de 500 fatias a prévia já diz `Fatias demais`, mas o erro de verdade vem ao tocar em `Dividir` (`Remover` e `Quantizar` desligam antes).
- **Normalizar mede duas vezes.** O diálogo mede ao abrir (e por modo) para mostrar o plano, e `normalizeClip` mede **de novo** ao aplicar (no LUFS, o mesmo trabalho em dobro).
- **Plural na tela.** O resumo da prévia de `Quantizar` diz `N fatias, M movidas`, mesmo com `M = 1` (`1 movidas`), enquanto o resultado final (`quantizeSummary`) concorda no singular.
- **Comentário do topo × código na quantização.** O texto do arquivo diz que só as fatias que mudam de lugar trocam o crossfade por um fade simples; `buildSlices` calcula `head` (a cabeça de 2 ms) para toda fatia que não é a primeira, tenha andado ou não.
- **Ajuste da grade.** A fatia começa 2 ms antes do corte (`start = at − head`): o encaixe da timeline alinha o início do clipe, e o ataque cai 2 ms depois da linha.
- **Áudio longo.** `detectCuts` e `planSilence` rodam síncronos na thread da tela (só o LUFS cede o controle a cada ~0,5 s de áudio): uma prévia de um clipe muito longo pode travar a tela por um instante `(não confirmado)`.
