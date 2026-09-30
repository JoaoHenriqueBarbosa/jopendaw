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
| `app/lib/screens/` | `login_screen` (magic link, Google, Discord, código de acesso), `link_screen` (`/entrar?token=`), `projects_screen` (lista, criar com modelo, renomear, apagar; apagar também limpa o aparelho com `purgeLocalProject`), `account_screen`, `project_screen` (`DawStudio`; `projectSubtitle` lê o andamento e o compasso do documento vivo) |

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

`AudioEngine.instance` (decodificar, `loadSample`, `calls`, entrada, captura, render fora de tempo real, `sha256Hex`, `saveFile`) e `LocalStore.instance` (`get`/`put`/`delete` por chave; valor `String` ou `Uint8List`). Na web o `LocalStore` é o IndexedDB do `host.js`; no Android é `FileStore` em `<documentos>/jopendaw`, um arquivo `.txt` (texto) ou `.bin` (bytes) por chave, com escrita por arquivo temporário + rename (`audio/engine_io.dart:157` e seguintes). Fora do Android e da web o `LocalStore` não guarda nada (`_files` é nulo).

Chaves do `LocalStore` usadas pelo app:

| Chave | Valor | Quem grava |
|---|---|---|
| `doc:<projectId>` | JSON do `DawDoc` (texto) | `DawController._save`; `importProjectBundle` (a primeira gravação de um projeto importado) |
| `sample:<sha256>` | bytes do arquivo de áudio como foi importado ou gravado | importar, gravar, congelar, baixar do servidor, importar `.jopendaw` (`importProjectBundle`, só se a chave ainda não existe) |
| `sync:<projectId>` | `{"version": int, "dirty": bool}` | `SyncService._persist` |
| `template:<projectId>` | nome do modelo escolhido ao criar o projeto (apagada na 1ª abertura) | `projects_screen`, `_fromTemplate` |
| `rec:input` | id da entrada de áudio escolhida | `_chooseInput` |
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
| `bpm` | número | sim | (do projeto, só num documento novo) | andamento. **É a fonte de verdade** (desde a fase 9); `projects.bpm` no servidor é um espelho inteiro (20..400) enviado em segundo plano por `_mirrorTempo`. `open()` só parte do projeto quando não há documento local; `_applyRemote` traz o do documento remoto |
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

Vivem só no controlador: seleção (`selectedClip`, `selectedTrack`, `selectedMarker`), zoom e rolagem (`pxPerBeat`, `scrollBeat`, `follow`), grade (`snap`), altura das faixas (`laneScale`), modo da régua, painel de baixo (`dock`, `editingClip`), teclado do computador (`keyboardOn`, oitava, velocidade), entradas MIDI e a entrada de áudio escolhida (`inputDevice`, guardada em `rec:input`).

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
- **Normalização** (`normalizeTempoPoints`, `normalizeMeterChanges`, chamadas no construtor e em `fromJson`): descarta não finitos, batida negativa vira 0, bpm preso a 20–999, na mesma batida (ou no mesmo compasso) o último vale, ordena, garante o ponto da batida 0 (ou o compasso 1) e limita a `maxTempoPoints = 512` pontos e `maxMeterChanges = 256` mudanças (os de batida ou compasso menores ficam). Um mapa que sobra com **um ponto só** vira `[]` ("sem mapa"); para o compasso, um só `n/4`. Um único compasso `6/8` ou `7/8` **não** é "sem mapa" (`MeterMap.isSingle` exige `den == 4`) e é gravado.
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
| `setTempo(bpm, beatsPerBar)` | mantém o ponto 0 do mapa igual ao `bpm` novo e, se o primeiro compasso do mapa é `n/4`, o iguala a `beatsPerBar`/4 |
| `tempoLaneVisible`, `toggleTempoLane()` | a faixa `Andamento` à mostra: `_tempoLane ?? !doc.tempo.isSingle` (automática com mapa, manual depois do primeiro clique; **não** vai no documento) |
| `snapBeat(b)` | com `Snap.bar` e mapa de compassos, encaixa em `meter.nearestBarStart(b)` |
| `secondsAt`, `bpmAt` | atalhos para o relógio em segundos e o BPM vigente |

**Do documento ao motor.** `_tempoMapCalls(cache)` (chamado por `_docCalls`) compara a assinatura (`jsonEncode` dos pontos) com `_SyncCache.tempoSig`/`meterSig` e só então emite `tempo_clear` + um `tempo_point` por ponto e `meter_clear` + um `meter_point` por mudança; volta ao mapa simples manda o `tempo_clear` seco. Vão logo depois do `tempo`. Ver a tabela em "Como cada mudança vira chamadas ao motor" e [02-pontes-web-e-android.md](02-pontes-web-e-android.md#chamadas-do-mapa-de-andamento-e-de-compassos-tempo_clear-tempo_point-meter_clear-meter_point).

**Consumidores no app** (tudo que antes multiplicava `beat * 60 / bpm` passa pelo mapa): relógio da barra (`_Position`, `secondsAt`), régua e grade (`_RulerPainter`, `_GridPainter` por `MeterMap`; régua em mm:ss por `secondsAt` e `beatAt`), etiqueta do mouse na régua, clipes (largura por `clipBeats`, arrastar e aparar por `sourceTempoAt`, cortar e sobrepor por `sourceSeconds`), estimativa de posição durante o play (`_estimatedBeat`), contagem e passadas da gravação (`_Recording.tempo`, `framesBetween`, `recordingPasses(tempo:)`, `_countFrames`, compasso da contagem por `meter.barBeatsAt`), exportação e congelar (`secondsAt`), render (`renderTempoMap`, `renderFrames`, `prepareRenderCalls` no Dart e o `tempoMapOf` do `render-worker.js`), `DurationLabel`, dialogo de exportação (`_bars`, `_spanSeconds`), e o botão de andamento (`_TempoButton`: `bpmAt` no cursor, `↗` quando o trecho é rampa). O áudio → MIDI usa o BPM vigente na batida do clipe (`notesForClip(r, audio, doc.bpmAt(audio.start))`).

**Warp.** Decisão: `WarpSpec.of(c, doc.bpm)` (o inicial) em toda parte (`setClipWarp`, `_clipSound`, congelar). O clipe esticado toca a velocidade constante; se atravessa uma mudança de andamento, sai da grade. O `warp_dialog.dart` avisa: `O projeto tem mudanças de andamento: o warp estica o áudio para o andamento INICIAL (X BPM) e ele toca em velocidade constante, sem acompanhar as mudanças.` Mudar só outros pontos do mapa não refaz o warp.

**Gancho do importador de MIDI.** `setTempoMap` e `setMeterMap` foram escritos como o ponto onde o importador de `.mid` aplicaria `MidiFileData.tempoMap` e as fórmulas de compasso do arquivo (teste `ganchos do importador de MIDI: setTempoMap e setMeterMap`). Hoje `importMidiBytes` **não os chama**: `applyImportedTempo` só grava o primeiro BPM e o primeiro compasso, e o aviso da importação ainda diz que o app "tem um andamento só" e ignora as mudanças (texto anterior ao mapa, ver "Arquivo MIDI padrão"). `(lido do código)`

**Não segue o mapa de compassos** (usa `doc.beatsPerBar`, o compasso inicial): o piano roll (linhas de compasso, `Shift`+← →, tamanho de clipe crescido pelas ferramentas), `createMidiClip` sem `length`, o arredondamento em compassos de notas gravadas (`_placeRecordedNotes`), `fitRange`, o tamanho mínimo do minimapa, o passo `Compasso` que limita a duração mínima ao aparar (`_gridBeats`) e a conta de compassos do tooltip de `DurationLabel`.

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
| gravação, exportação, bounce (`:2740`) | armar/monitorar, entradas de áudio, `toggleRecord`, contagem, tomadas, `exportAudio`, `cancelRender`, `bounceTrack` |
| visão (`:3945`) | zoom, rolagem, enquadrar |
| marcadores e seções (`:4016`) | `addMarker`, `moveMarker`, loops por seção/marcadores/seleção |

### `open()` (`DawController.open` em `controller.dart`)

1. Confere `_engine.supported`; `_engine.start()` devolve a taxa do motor (`engineRate`).
2. Lê `doc:<id>` do `LocalStore`. Se existe, `DawDoc.fromJson`. Senão `_fromTemplate()`: se há `template:<id>` (modelo escolhido ao criar; apagado na hora), `ProjectTemplate.build`; senão `_fresh()` (uma faixa `Áudio 1`, `loop_end = beats_per_bar * 4`). O modelo `Vazio` da tela de projetos **não** grava `template:<id>`, então cai em `_fresh()`.
3. (Não sobrescreve mais `doc.bpm` e `doc.beatsPerBar` com os do projeto: o documento local vale; só um documento novo, de `_fromTemplate`/`_fresh`, parte dos do projeto.)
4. Carrega cada áudio de `doc.samples` (`sample:<hash>` → `_engine.decode` → `_register`, que atribui um id inteiro ao hash em `_sampleIds`, manda ao motor e desenha a forma de onda). Áudio ausente do aparelho entra em `missing`.
5. Sincronização: `sync.start(localExisted: ...)`. **Espera de até 25 s** (o `started.timeout(const Duration(seconds: 25))` em `DawController.open`) quando `saved is! String && !_templated && _canSync()`, isto é, projeto sem documento local, sem modelo e com sessão: nesse caso o projeto pode existir só no servidor (criado em outro aparelho) e o spinner só termina depois da primeira conversa (documento + áudios). Ver [12 Sincronização](12-sincronizacao.md). Nos demais casos a sincronização segue em segundo plano.
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

- **O histórico guarda documentos inteiros como texto JSON**, não comandos. `undo`/`redo` (`_travel`) reconstroem o `DawDoc` do JSON e depois **restauram do estado atual** o que é preferência do aparelho e não deve ser desfeito: `metronome`, `count_in`, `rec_latency_ms`, `armed`, `monitor` de cada faixa; `loop_on` também fica, a não ser que o passo desfeito tenha mudado a região do loop.
- **Arraste**: `checkpoint()` no início e `mutate` a cada passo (um passo só no histórico). `edit(..., undoable: false)` para preferências (metrônomo, contagem, latência, armar).
- **Caminhos rápidos** (`setParam` `:2185`, `setEffectParam` `:2487`): mudam o valor, mandam **uma** chamada (`param` ou `fx_param`) e atualizam o cache `_sent`, sem `_sync()` do documento inteiro. Se o motor ainda não tem aquele efeito naquele slot, caem no `_sync()` completo (um `fx_param` solto atingiria outro efeito).
- `setTempo` (`controller.dart:1565`) edita o documento (entra no desfazer) e chama `_mirrorTempo()`, o `PATCH /api/projects/{id}` de `{bpm, beats_per_bar}` **best-effort**: não lança offline e o valor pendente sai de novo em `_save` (desfazer e refazer incluídos), no fim de `open()` e de `_applyRemote` e quando `sync.phase` vira `synced` (`_onSyncPhase`). Detalhes em [12 Sincronização](12-sincronizacao.md#andamento-e-compasso-documento-é-a-fonte-o-servidor-espelha).

### Como cada mudança vira chamadas ao motor (`_sync`, `_docCalls`)

`_sync()` (`:762`) chama `_docCalls` com o cache `_SyncCache` (o que o motor já recebeu) e envia tudo numa mensagem (`_engine.calls`). Ordem: **áudio → instrumentos → efeitos → roteamento → automação → observação → notas → monitoração da entrada**.

| Parte do documento | Chamadas (nome dos exports do motor) | Reenvio |
|---|---|---|
| andamento, nº de faixas, master, loop, metrônomo | `tempo`, `tracks`, `master`, `loop_set`, `metronome` | sempre, inteiro |
| mapa de andamento e de compassos | `tempo_clear` e `tempo_point beat bpm ramp` por ponto; `meter_clear` e `meter_point bar num den` por mudança (logo depois do `tempo`, antes de `tracks`) | só quando a assinatura (`_SyncCache.tempoSig`/`meterSig`) muda; sem mapa nada vai (o `tempo` já basta) |
| faixa (volume, pan, mudo, solo) | `track i gain pan mute solo` | sempre |
| clipes de áudio | `clips_clear` e `clip_add track sample start offset length gain fade_in fade_out` | sempre, a lista inteira |
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

A latência total descartada do começo da gravação é a do contexto de áudio + a da entrada + `rec_latency_ms`. Parar durante a contagem cancela sem gravar nada.

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

## Onde está cada tela em `daw/`

| Arquivo | Papel |
|---|---|
| `timeline.dart` | régua, cabeçalhos das faixas, raias com clipes, sub-raias de automação, linha do master, cursor |
| `transport_bar.dart` | barra do transporte e das ferramentas (tocar, gravar, andamento, loop, metrônomo, painéis, teclado, MIDI); o botão de andamento (`_TempoButton`: BPM vigente no cursor, ícone `show_chart` e `↗` com mapa) e a janela `Andamento e compasso` (`_TempoDialog`, com o atalho para a mudança de compasso) |
| `tempo_map.dart` | `TempoPoint`, `MeterChange`, `TempoMap`, `MeterMap`, a normalização dos dois e `tempoMapCalls`; Dart puro, sem `dart:ui`. Espelho de `engine/src/tempo.rs` |
| `tempo_lane.dart` | a faixa `Andamento` sob a régua (`TempoLane`, `_TempoPainter`, gestos e menus) e o diálogo `Mudar compasso a partir do compasso N` (`showMeterChangeDialog`) |
| `dock.dart` | painel de baixo em abas (mixer, editor de notas, instrumento, efeitos) |
| `mixer_panel.dart`, `meter.dart` | canais do mixer, medidor de pico |
| `piano_roll*.dart`, `midi_tools.dart`, `piano_roll_tools.dart` | editor de notas (partes de `piano_roll.dart`) e a lógica pura das ferramentas de produtor |
| `instrument_panel.dart`, `knob.dart`, `presets.dart`, `wavetable_shape.dart` | painel do instrumento, controle giratório, presets e ids nomeados, gráfico das tabelas |
| `effects_panel.dart`, `fx_editors.dart`, `fx_presets.dart` | rack de efeitos, editores (EQ, dinâmica, genérico) e presets |
| `automation_lane.dart`, `automation_math.dart` | editor de pontos e a conta da curva |
| `marker.dart`, `structure_menu.dart`, `minimap.dart` | marcadores, menus Seções e Visão, minimapa |
| `export.dart`, `export_options.dart`, `wav.dart` | exportar (janela e opções) e codificação/leitura de WAV |
| `settings_dialog.dart`, `shortcuts_dialog.dart` | configurações de gravação e janela de atalhos |
| `warp.dart`, `warp_dialog.dart` | sons derivados do warp e o diálogo |
| `audio_to_midi.dart`, `midi_convert_dialog.dart` | áudio → MIDI pelo servidor (job `audio_to_midi`) e o diálogo; `notesForClip` segue o warp (`AudioClip.tempoFor`), soma a transposição e espelha no reverso |
| `clip_gain_dialog.dart` | diálogo `Ganho do clipe` (item `Ganho do clipe…` do menu do clipe de áudio em `timeline.dart`): slider −40 a +12 dB, `clipGainFromDb`/`clipGainToDb`, `setClipGain` |
| `sync.dart`, `sync_ui.dart` | sincronização (com pull periódico) e seu indicador |
| `local_purge.dart` | `purgeLocalProject`: limpeza local de um projeto apagado |
| `templates.dart` | modelos de projeto (`Vazio`, `Batida eletrônica`, `Gravação de banda`) |
| `project_file.dart`, `project_file_ui.dart` | o arquivo `.jopendaw`: montar, ler e validar o zip, refazer ids, importar (lógica pura) e a janela `Exportar projeto` com o seletor de arquivo (seção [Arquivo de projeto `.jopendaw`](#arquivo-de-projeto-jopendaw)) |
| `midi_file.dart`, `midi_file_ui.dart` | o arquivo MIDI padrão `.mid`: leitura (SMF tipo 0, 1 e 2), escrita (tipo 1, 480 PPQ), o `Importar` da barra e a janela `Exportar MIDI (.mid)` (seção [Arquivo MIDI padrão `.mid`](#arquivo-midi-padrão-mid)) |

## Arquivo MIDI padrão (`.mid`)

As notas dos clipes de notas indo e voltando em arquivo MIDI padrão (SMF): importar um `.mid` cria faixas e clipes, exportar escreve o clipe selecionado ou todas as faixas de notas. Vem do commit `945e937`. Só Dart puro (sem motor, sem servidor, sem `package:web`), então roda igual na web, no Android e nos testes. Para quem mexe no app; o uso está em [Áudio e clipes](../manual/03-audio-e-clipes.md#importar-um-arquivo-midi-mid) e [Exportação](../manual/08-exportacao.md#notas-em-midi-mid).

### Peças

| Arquivo | Papel |
|---|---|
| `daw/midi_file.dart` | tudo o que não é tela: `parseMidiFile` (leitura), `buildMidiFile` (escrita), `midiImportTracks` (arquivo lido → faixas e clipes), `midiFileName`, `appBpmFor`, o mapa da bateria GM (`drumPitchForGm`, `gmDrumName`) e as classes `MidiFileData`, `MidiFileTrack`, `MidiTempoPoint`, `MidiExport`, `MidiImportReport`, `MidiFormatException` (a mensagem já vem em português para a tela) |
| `daw/midi_file_ui.dart` | `importFiles` (o seletor único de áudio e MIDI, ligado ao botão `Importar` e ao `Ctrl+I`), `importMidiFlow`, `askUseFileTempo` (a pergunta do andamento), a janela de avisos e `ExportMidiDialog` (chaves `midi-export-clip`, `midi-export-all`, `midi-export-go`) |
| `daw/controller.dart` | `DawController.importMidiBytes` (bloqueia gravando, chama o leitor, decide o andamento, cria as faixas num só `edit`) e `applyImportedTempo` |
| `daw/export.dart` | `ExportDialog.onMidi` (botão `Notas em MIDI (.mid)…`, chave `export-midi-link`) e `showExportDialog`, que abre `showExportMidiDialog` quando o botão foi tocado |
| `daw/transport_bar.dart`, `screens/project_screen.dart` | o botão `Importar` (tooltip `Importar áudio ou MIDI (Ctrl+I)`) e o `Ctrl+I` chamam `importFiles`; o `Ctrl+I` cai em `importAudio` se o nó de foco não tem contexto |
| `test/midi_file_test.dart` | 493 linhas: leitura à mão, arquivos ruins, ida e volta, desempenho e a importação no controlador |

### Fluxo de dados

```
Importar:  seletor (audioExtensions + mid, midi)
             ├─ áudio  → DawController.importBytes (sha-256, ver acima)
             └─ .mid   → importMidiFlow → importMidiBytes
                          parseMidiFile → MidiFileData (faixas, tempoMap, beatsPerBar, warnings)
                          ├─ falhou → error = 'Não deu para importar <nome>: <mensagem>' (nada muda)
                          ├─ andamento/compasso difere → confirmTempo (askUseFileTempo)
                          └─ edit(): applyImportedTempo (se aceito) + DawTrack por faixa + clipe, num checkpoint
                             → _mirrorTempo() (espelho do andamento no servidor) → MidiImportReport
                             → janela de avisos se houve warnings

Exportar:  ExportDialog → 'Notas em MIDI (.mid)…' → ExportMidiDialog
             → buildMidiFile(doc, [only, onlyTrack], title) → MidiExport(bytes, tracks, notes, skipped)
             → AudioEngine.saveFile(nome, bytes, 'application/octet-stream')
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
| `Bn` outros CC | Ignorado e contado (`Ignorei N eventos de controle…`) |
| `Cn` e `Dn` | Ignorados sem aviso (um byte de dados) |
| `FF 51` (tamanho 3) | Ponto do mapa de andamento: batida e `60000000 / µs` BPM |
| `FF 58` (≥ 2 bytes) | Fórmula de compasso: numerador, `dd` (denominador = 2^dd, `dd` limitado a 6) |
| `FF 03` | Nome da trilha (só o primeiro; UTF-8 tolerante, sem caracteres de controle) |
| `FF 2F` | Fim da trilha |
| `F0`, `F7`, `F1`–`F6`, `F8`–`FE`, outros meta | Pulados. Meta e SysEx cancelam o *running status* |

Running status vale. Dado sem status anterior, byte de dados ≥ 128 onde deveria haver dado, ou VLQ de mais de 4 bytes: a **trilha** para ali (o que veio antes vale) e o arquivo ganha o aviso de corrompido; a leitura nunca lança nada além de `MidiFormatException` (há teste com bytes aleatórios). Uma trilha é dividida por canal em grupos; só grupos com nota viram `MidiFileTrack`. Trilhas com mais de um canal com nota ganham o canal no nome (`Nome (canal N)` ou `Canal N`). Canal 9 (o 10 dos músicos) é `MidiFileTrack.drums`.

**Andamento e compasso do arquivo.** `MidiFileData.tempoMap` guarda a lista inteira e ordenada (batida, BPM real); `firstBpm` é o primeiro ponto; `hasTempoChanges` é verdadeiro se algum BPM difere do primeiro por mais de 0,5. `beatsPerBar` vem só da **primeira** fórmula de compasso: `numerador * 4 / 2^dd`, arredondado e limitado a 1–12 (6/8 → 3; 7/8 → 3,5 → 4 com aviso). Mudanças de compasso no meio geram aviso e são ignoradas. `appBpmFor` arredonda o BPM ao inteiro e limita a 20–400 (o que o app aceita).

**Bateria GM.** As notas do canal 10 passam por `drumPitchForGm`: se a altura é de uma das 12 peças de `drumPieces` (36, 37, 38, 39, 41, 42, 45, 46, 48, 49, 51, 56) fica; senão vale a tabela de apelidos (`_gmDrumAlias`: 35→36, 40→38, 43→41, 44→42, 47→45, 50→48, 52→49, 53→51, 55→49, 57→49, 59→51, contada no aviso); qualquer outra altura (54, 58, fora de 35–59) **entra no clipe sem mudar** e vai para o aviso `A bateria do app não tem: …` com o nome GM (`gmDrumName`, ou `nota N`).

**Do arquivo lido ao documento** (`midiImportTracks`): uma `DawTrack` por `MidiFileTrack`, tipo `TrackKind.synth` (ou `drums` no canal 10), clipe `MidiClip` com `start` = cursor encaixado na grade (`snapBeat(beat.value)`), notas e controles exatamente como lidos (batidas contadas do instante zero do arquivo) e `length` = `max(bar, ceil(fim / bar) * bar)`, com `bar` = tempos por compasso do projeto (ou do arquivo, se o andamento foi aceito). Nome da faixa: o do arquivo, ou `TrackKind.label N` (o primeiro número livre, `_nextTrackName`). Nada de `Program Change`: instrumento e parâmetros ficam nos padrões da faixa.

**Escrita** (`buildMidiFile`). Bytes de saída:

| Trecho | Conteúdo |
|---|---|
| `MThd` | tamanho 6, formato **1**, `N+1` trilhas, divisão **480** (`midiExportPpq`) |
| Trilha 0 | `FF 03` com o título (nome do projeto), `FF 51` (µs = `round(60000000 / bpm)`, limitado a 1..16777215; BPM inválido vira 120), `FF 58` (`beatsPerBar`, `02`, `24`, `8`, ou seja, `N/4`), `FF 2F` |
| Trilha `i` | `FF 03` com o nome, os eventos ordenados por (tick, ordem, sequência) com delta em VLQ e o status completo em cada evento (**sem** *running status*), `FF 2F` |
| Ordem no mesmo tick | desligar nota, depois controles, depois ligar nota: uma nota que começa onde outra igual termina não se funde |
| Canais | `Bateria` no 10 (índice 9); as demais, a k-ésima faixa melódica no canal `k % 15`, pulando o 10 (`k % 15 >= 9` ganha +1): 1–9, 11–16 e a 16ª volta ao 1 |
| Faixas | `exportableTracks(doc)`: `kind.isInstrument` e pelo menos um clipe com notas ou controles. Mudo e solo não são olhados |
| Nota | `9n altura vel` / `8n altura 0`. Descartadas (e contadas em `skipped`): altura fora de 0–127, início ou duração não finitos, início < 0 ou ≥ `clip.length` |
| Controles | Bend: `round(v * 8192) + 8192` limitado a 0–16383 em 2 bytes de 7 bits; CC 1: `round(v * 127)`; CC 64: 127 se `v ≥ 0.5`, senão 0. Fora de 0..`clip.length`: descartados sem contar |
| Sem nada | `MidiFormatException('Não há notas para exportar: desenhe ou grave um clipe de notas primeiro.')` |

Não há `Program Change`, `RPN` (alcance do bend), letras, marcadores nem nome de instrumento. Só o andamento e o compasso **iniciais** do documento (`doc.bpm`, `doc.beatsPerBar`) são escritos: o mapa de andamento e o de compassos (`doc.tempo`, `doc.meter`, commit `02f1910`) **não** são consultados.

**Nome do arquivo** (`midiFileName`): substitui `\u0000-\u001f`, `\u007f` e `/ \ : * ? " < > |` por `_`, tira pontos do começo, corta em 80 caracteres (por pontos de código), `notas` se vazio, e põe `.mid`. Em `Todas as faixas de notas` o título é o nome do projeto; em `Clipe selecionado`, o nome do clipe (ou o do projeto se vazio).

### Compatibilidade com outros programas

O que o app escreve é o SMF mais comum: tipo 1, 480 PPQ (dentro do que Ableton Live, FL Studio, MuseScore e afins leem), uma trilha de andamento e compasso à parte, uma trilha por faixa com nome e um canal fixo, bateria no canal 10. O que o app lê cobre tipos 0, 1 e 2, qualquer PPQ, *running status*, SysEx e meta desconhecidos. Nada disso foi conferido abrindo um arquivo do jopendaw nesses programas, nem um arquivo deles no jopendaw `(não confirmado; testado só por testes automáticos)`: os testes fabricam os bytes à mão e fazem a ida e volta com o próprio leitor. Consequências previsíveis do que **não** se escreve (pelo padrão MIDI, não por teste): sem `Program Change`, o programa de destino toca cada trilha com o timbre padrão do canal (o piano, no GM); sem `RPN`, o alcance do pitch bend fica no padrão do programa (em geral ±2 semitons), diferente do `Alcance do bend` do instrumento do jopendaw.

### Decisões e por quê

- **Só Dart puro e sem inteiros de 32 bits.** O dart2js faz operações de bit em 32 bits (ver [Armadilhas](#armadilhas-conhecidas)): o VLQ, os tempos de 32 bits e a escrita usam multiplicação, `%` e `~/`, nunca `<<` ou `&`.
- **Um leitor tolerante.** Arquivo cortado ou com lixo devolve o que deu para ler, com aviso, em vez de recusar tudo (uma trilha corrompida não derruba as outras). Só o que impede de saber o tempo (SMPTE, PPQ 0, sem `MThd`, sem trilha) ou de ter algo para importar (sem nota) vira erro.
- **O leitor cede o controle.** A cada `yieldEvery` (20 mil) eventos ele faz `await Future.delayed(Duration.zero)`, para a tela não travar num arquivo enorme (teste de 100 mil notas).
- **Uma faixa por (trilha, canal), não só por trilha.** Um arquivo tipo 0 põe tudo numa trilha, e um canal só pode ser bateria ou não; separar por canal mantém a bateria (canal 10) numa faixa `Bateria` e o resto em `Sintetizador`.
- **Batidas como estão.** Importar recusando o andamento do arquivo mantém as batidas: só a velocidade muda (o texto da pergunta diz isso).
- **`MidiFileData.tempoMap` e `applyImportedTempo` são ganchos.** O leitor já devolve o mapa de andamento inteiro, mas `applyImportedTempo` aplica só o primeiro BPM e o primeiro compasso em `doc.bpm` e `doc.beatsPerBar`. Depois de `02f1910` o controlador tem `setTempoMap` e `setMeterMap` (ambos comentados como "o gancho para o importador de MIDI"); ligar o importador a eles é o próximo passo natural e a escrita deveria ler `doc.tempo` e `doc.meter` no mesmo movimento.

### Como testar

```bash
cd app
flutter test test/midi_file_test.dart
```

Cobertura de `test/midi_file_test.dart`: leitura à mão (tipo 0 com running status e `9n` de velocidade 0, tipo 1 com trilha de andamento, VLQ de 4 bytes, SysEx e mensagens de sistema, bend/modulação/pedal, notas presas, duração zero, bateria GM, vários canais numa trilha, várias mudanças de andamento, 6/8 e 7/8, PPQ 1/96/960/32767); arquivos ruins (vazio, não-MIDI, SMPTE, PPQ 0, tipo desconhecido, cabeçalho cortado, sem faixa, sem nota, truncado, lixo na trilha, 300 arquivos de bytes aleatórios que só podem lançar `MidiFormatException`, RMID); escrita e ida e volta (notas, velocidades, controles, andamento 97, compasso 3, nomes, posição absoluta da bateria; clipe selecionado sai do começo; 15 faixas melódicas pulam o canal 10 e a 16ª volta ao 1; notas fora de 0–127 ou do clipe; notas emendadas; nome do arquivo); desempenho (100 mil notas escritas e lidas em menos de 20 s, com a leitura cedendo o controle); e a importação no controlador com o motor de mentira (faixa de sintetizador e de bateria, andamento aceito e desfeito com `undo`, andamento recusado, pergunta só quando difere, aviso de mudança de andamento, arquivo ruim vira `error` sem mexer no documento). Os testes rodam na VM do Dart, não no dart2js: o cuidado com inteiros de 32 bits vem da leitura do código, não de teste na web `(não confirmado no navegador)`. Não há teste de widget para `importFiles`, `askUseFileTempo` nem `ExportMidiDialog` `(não confirmado em uso)`.

### Armadilhas do arquivo MIDI

- **Andamento e compasso variáveis são perdidos nos dois sentidos.** Na importação só entram o primeiro andamento e o primeiro compasso; na exportação sai só o inicial do documento. O texto do aviso de importação (`o app tem um andamento só`), o comentário `GANCHO` de `midi_file.dart` e o texto da janela de exportar (`Leva o andamento (X BPM)`) são de antes do mapa de andamento (`02f1910`) e ficaram desatualizados.
- **`applyImportedTempo` não mexe em `doc.tempoMap` nem em `doc.meterMap`.** Se o projeto já tem mapa com mais de um ponto, o BPM importado vira o andamento inicial (os getters `DawDoc.tempo` e `DawDoc.meter` reconciliam o primeiro ponto com `bpm` e `beatsPerBar`), mas os pontos seguintes ficam com o BPM absoluto que tinham. `(lido do código; não testado)`.
- **A pergunta de andamento compara só o andamento inicial** (`doc.bpm`) com o primeiro do arquivo.
- **Sem `Program Change` nem `RPN` na escrita.** Ver "Compatibilidade".
- **Mudo e solo não são consultados na exportação.** Faixa muda sai no arquivo.
- **O tipo da faixa criada é só `Sintetizador` ou `Bateria`.** Nunca `Sampler`, `FM` ou `Wavetable`.
- **`saveFile` não avisa cancelamento.** `AudioEngine.saveFile` no Android devolve sem erro se a janela de salvar for cancelada e `ExportMidiDialog` escreve `<nome> salvo` do mesmo jeito `(não confirmado em uso)`.
- **A janela de atalhos ficou com o texto antigo.** `shortcuts_dialog.dart` ainda diz `Importar áudio` para o `Ctrl+I`.
- **Pontos de controle descartados na exportação não entram em `skipped`.** Só notas são contadas.
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
- `importProjectBundle(bundle, ...)`, na ordem que deixa o pior caso inofensivo: `remapDocIds(doc)`; `createProject(importedProjectName(...))` (POST `/api/projects`); se o andamento (`doc.bpm` arredondado e limitado a 20–400) ou o compasso (`beatsPerBar` limitado a 1–32) diferem dos padrões do projeto novo, `patchProject`; copia o andamento e o compasso do projeto para o documento; grava cada `sample:<hash>` **se a chave ainda não existe**; grava `doc:<id>` por último (é o que faz o projeto "existir" para o editor). Qualquer falha depois de criado o projeto chama `deleteProject` (melhor esforço) e relança.
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
- **Andamento inteiro:** o projeto no servidor guarda `bpm` inteiro; o importador arredonda `doc.bpm` e o limita a 20–400 (o servidor aceita 20–999). Um andamento fracionado ou acima de 400 muda na importação.
- **Preferências e armar/monitorar viajam junto** porque estão no `toJson`; o projeto importado abre com o metrônomo, a contagem, a latência e as faixas armadas do original (e o `open` tenta reabrir a entrada de áudio se há faixa de áudio armada).
- **Leitura inteira na memória:** `pickProjectFile` faz `readAsBytes` e `parseProjectFile` roda síncrona na thread da interface; um arquivo perto de 1 GiB é pesado para um celular. `(não medido)`
- **`saveFile` cancelado no Android** volta sem erro; a janela `Exportar projeto` então mostra `Pronto: ...`. `FilePicker.saveFile` devolve nulo ao cancelar e o resultado é descartado (`engine_ffi.dart:1276`).
- **O cabeçalho do código** de `project_file.dart` diz "para abrir sem servidor", mas a importação cadastra o projeto pela API (`createProject`), então exige sessão e rede.

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
flutter test integration_test -d emulator-5554 # motor nativo no emulador Android
cargo test -p jopendaw-engine                  # inclui os testes de contrato que leem o Dart
```

Mapa de andamento e de compassos: `flutter test test/tempo_map_test.dart test/tempo_lane_test.dart` (conta do mapa, JSON e documento antigo, controlador e motor de mentira, gravação e render com mapa, e a comparação com o `render-worker.js` real no node; no `tempo_lane_test.dart`, a faixa `Andamento` com duplo clique, arrasto, menu e o diálogo de compasso, em widget test) e `cargo test -p jopendaw-engine tempo` (os 10 testes de `tempo.rs` e os 13 de `tempo_tests.rs`). No navegador: segundo o relato da sessão de código, o duplo clique na faixa e o diálogo de compasso **não** foram exercitados no Chrome (só há widget test); o botão direito na faixa, o menu, o arraste e a medição do salto foram (relato; não repeti).

Para conferir a saída: `flutter test 2>&1 | tr '\r' '\n' | grep -E "All tests passed|Some tests failed|\[E\]"`. Mudou o motor: recompile os binários antes de testar no navegador ou no Android. O teste de uso (obrigatório antes de dar uma fase por pronta) é usar o app no Chrome: ver [03 Build, teste e depuração](03-build-teste-e-depuracao.md) e [20 Processo e histórico](20-processo-e-historico.md).

## Armadilhas conhecidas

- **Preferências contam como mudança para sincronizar.** `_save` compara o JSON inteiro com o último gravado (`DawController._save` em `controller.dart`); `metronome`, `count_in`, `rec_latency_ms`, `armed` e `monitor` estão no JSON, então ligar o metrônomo marca o projeto como pendente e gera versão nova no servidor (mesmo que outro aparelho as ignore ao aplicar). Lido no código; efeito sobre conflitos falsos `(não confirmado no uso)`.
- **`setTempo` e o desfazer (corrigido na fase 9).** O andamento mora no documento; desfazer restaura o `bpm` antigo no documento e o `_save` seguinte reenvia o espelho (`PATCH`) se ele difere do último confirmado. Reabrir usa o `doc.bpm` local. Resta que `projects.bpm` (lista de projetos) pode ficar defasado enquanto o `PATCH` está pendente (offline). `(lido do código e coberto por `phase9c_test`; não visto no Chrome)`
- **Limpeza local ao apagar projeto (fase 9).** `projects_screen._delete` chama `deleteProject` na API e depois `purgeLocalProject(LocalStore.instance, id, idsDaLista)` (`local_purge.dart`): apaga `doc:<id>`, `sync:<id>`, `template:<id>` e os `sample:<hash>` que só o documento local desse projeto cita (os de qualquer outro projeto da lista ficam). Nunca lança, devolve quantos áudios apagou. O cache `warp:<chave>` continua sem limpeza (o guardado não lista chaves). Só limpa o aparelho que apagou.
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
