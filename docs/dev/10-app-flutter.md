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
| `app/lib/screens/` | `login_screen` (magic link, Google, Discord, código de acesso), `link_screen` (`/entrar?token=`), `projects_screen` (lista, criar com modelo, renomear, apagar), `account_screen`, `project_screen` (`DawStudio`) |

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

- **URL base** (`client.dart:37`): `--dart-define=API_BASE=` se definido; senão, na web, a origem da própria página quando a porta é 8080 ou o host não é `localhost`; em qualquer outro caso (inclusive web em `localhost:8081` do docker-compose e `flutter run`) a produção `https://jopendaw.johnenrique.tech`. O app Android usa a produção salvo `API_BASE` (o emulador usa `--dart-define=API_BASE=http://10.0.2.2:8080`).
- **Renovação no 401** (`_send`, `_refresh`): um 401 com sessão ativa dispara uma única renovação, dividida entre as chamadas simultâneas (`_refreshing`). Antes de chamar `/api/auth/refresh` o cliente relê o armazenamento seguro: se outra aba já renovou, adota o token dela. Um 409 do servidor (janela de 60 s de rotação, ver [11 Servidor](11-servidor.md)) faz até 3 tentativas, esperando 300 ms × n e relendo o armazenamento. Se a renovação falha, `signOut(notifyServer: false)` e `Unauthenticated`.
- **Tempos**: 120 s para qualquer pedido (`_raw`), 20 s para o refresh. Um upload de sample grande em conexão lenta pode estourar os 120 s (ver Armadilhas).
- **Erros**: `ApiException(status, message)` com a mensagem `{"error": ...}` do servidor; `Unauthenticated` para 401 pós-renovação; falha de rede sobe como exceção do `http`. `describeError` (`widgets/feedback.dart:12`) traduz tudo em frase para o usuário; erro é sempre inline (`InlineNotice`), nunca toast.
- **Projetos**: `createProject(name)` manda só `name`, então todo projeto nasce 120 BPM, 4/4, 48000 Hz.
- **`ApiState`** (`widgets/api_state.dart`): mixin de tela com `fetch`, `run`, `fail` e `error`/`info`/`busy`; as telas de projetos e de conta o usam.

### `platform/` e por que nada de `package:web` fora dali

`platform/platform.dart` reexporta `platform_native.dart` ou `platform_web.dart` conforme `dart.library.js_interop`. O mesmo código Dart compila para web e Android, e `package:web` (e `dart:js_interop` para o DOM) não compila no Android. Quem importasse `package:web` em qualquer outro lugar quebraria o `flutter build apk`. A regra do `CLAUDE.md` ("não importar `package:web` fora dali") vale para o DOM e as APIs do navegador; o mesmo desenho de exportação condicional aparece em `audio/engine.dart` (`engine_web.dart` no navegador, `engine_io.dart` + `engine_ffi.dart` no Android). Conferido por `grep`: `package:web` só aparece em `platform/platform_web.dart`; `dart:js_interop` também em `audio/engine_web.dart` (a ponte com `host.js`).

O que `platform/` expõe nos dois lados (mesma assinatura): `initPlatform`, `pageVisible`, `onVisibilityChange`, `isFullscreen`/`toggleFullscreen`/`exitFullscreen`, `openSignIn` (na web navega a aba; no Android abre uma aba do Chrome e devolve a URL de retorno), `openInOtherApp`, `openExternal`, `localRead`/`localWrite` (string síncrona: `localStorage` na web, `SharedPreferences` no Android; usados só pelo segredo PKCE da entrada social). Só o lado Android define também `keepScreenOn`, `watchAudioSession`, `microphoneAllowed` e `ensureMicrophone` (ponte `jopendaw/apps` com o `MainActivity`); em `app/lib/` nenhum outro arquivo os chama, só o teste `integration_test/platform_test.dart` (o pedido de microfone do motor nativo passa por `permission_handler` em `audio/engine_ffi.dart:714`). `(não confirmado se ficaram sem uso de propósito)`

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
| Ganho | linear (1 = 0 dB; teto do fader 2 = +6 dB, `maxGain`) | `gain`, `master_gain`, `Send.level`, automação de volume e envio |
| Pan | −1 (esq.) .. 1 (dir.) | `pan`, `master_pan` |
| Parâmetros de instrumento e efeito | a unidade da tabela do parâmetro (Hz, s, dB, semitons, 0..1); **nunca normalizados** | `params` |
| Latência de gravação | milissegundos | `rec_latency_ms` |

Duração de um clipe de áudio em batidas: `length * tempoFor(bpm) / 60`, onde `tempoFor` é o `source_bpm` do próprio áudio quando o warp está esticando e o andamento do projeto caso contrário (`model.dart:96`). O fim do último clipe define `DawDoc.contentEnd`.

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
| `bpm` | número | sim | (do projeto) | andamento. **Cópia**: a fonte de verdade é `projects.bpm` no servidor; `open()` e `_applyRemote` sobrescrevem com o do projeto |
| `beats_per_bar` | int | sim | (do projeto) | tempos por compasso. Mesma regra do `bpm` (`projects.beats_per_bar`). A figura do compasso (`beat_unit`) e a taxa de amostragem não estão no documento |
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
| `gain` | número | não | `1` | ganho do clipe (linear) |
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

### Duas armadilhas de compatibilidade do esquema

1. **Tipos de faixa novos em app velho.** `TrackKind.parse` devolve `audio` para um `kind` que a versão não conhece. Um app antigo que abre um projeto com faixa `fm`/`wavetable` a lê como `audio`, e ao salvar **regrava `audio`**, perdendo o tipo (aconteceu com um APK velho instalado por engano em 30/09/2026, segundo as notas de processo). `AutoKind.byName` é o oposto: lança, e o documento não abre.
2. **Sidechain é índice de faixa, não id.** O parâmetro `10` do compressor e o `6` do gate guardam o **índice** da faixa-chave (−1 = desligado, faixa `-1..63` na tabela). Por isso `removeTrack`, `duplicateTrack`, `moveTrack` e o congelar reescrevem esses valores (`_remapSidechains` em `controller.dart`). Editar o documento por fora (ou mesclar dois documentos) exige o mesmo cuidado.

## Fluxo de dados / ciclo de vida do `DawController`

O controlador (`daw/controller.dart`, ~4 400 linhas) é criado por `ProjectScreen.reload` (`DawController(project)..open()`) e descartado no `dispose` da tela. Construtor: `DawController(project, {engine, store, api, canSync, syncTimeScale})`; os quatro últimos existem para os testes (`FakeEngine`, servidor falso).

### Grupos de métodos (seções do arquivo)

| Grupo (linha) | Responsabilidade |
|---|---|
| funções puras (`:90`–`:265`) | `flattenNotes`, `quantizeNoteList`, planejamento de gravação (`recordingPasses`, `gatherFrames`), mapa de teclas do computador |
| abrir (`:585`) | `open()`, `_onEngineState`, `_fromTemplate`, `_loadSample`, `_register`, `dispose` |
| motor (`:752`) | `_sync()` e o cache do que o motor já recebeu |
| warp e tradução para o motor (`:789`–`:1260`) | `_clipSound`, `setClipWarp`, `detectClipBpm`, `_settleWarp`; e a tradução documento → chamadas: `_fullSyncCalls`, `_docCalls`, `_monitorCalls`, `_syncChain`, `_routeIndex`, `_syncRouting`, `_automationCalls`, `_resolve`, `_watchCalls` |
| transporte (`:1261`) | `togglePlay`, `stop`, `seek`, `toggleLoop/Metronome/CountIn`, `setRecLatency`, `setLoop`, `setTempo` |
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
3. Sobrescreve `doc.bpm` e `doc.beatsPerBar` com os do projeto (servidor).
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
- `setTempo` edita o documento **e** faz `PATCH /api/projects/{id}` com `bpm` e `beats_per_bar` (`:1326`). O desfazer restaura o `bpm` antigo só no documento local; o servidor continua com o novo até o próximo `setTempo` (ver Armadilhas).

### Como cada mudança vira chamadas ao motor (`_sync`, `_docCalls`)

`_sync()` (`:762`) chama `_docCalls` com o cache `_SyncCache` (o que o motor já recebeu) e envia tudo numa mensagem (`_engine.calls`). Ordem: **áudio → instrumentos → efeitos → roteamento → automação → observação → notas → monitoração da entrada**.

| Parte do documento | Chamadas (nome dos exports do motor) | Reenvio |
|---|---|---|
| andamento, nº de faixas, master, loop, metrônomo | `tempo`, `tracks`, `master`, `loop_set`, `metronome` | sempre, inteiro |
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
| `transport_bar.dart` | barra do transporte e das ferramentas (tocar, gravar, andamento, loop, metrônomo, painéis, teclado, MIDI) |
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
| `audio_to_midi.dart`, `midi_convert_dialog.dart` | áudio → MIDI pelo servidor (job `audio_to_midi`) e o diálogo |
| `sync.dart`, `sync_ui.dart` | sincronização e seu indicador |
| `templates.dart` | modelos de projeto (`Vazio`, `Batida eletrônica`, `Gravação de banda`) |
| `project_file.dart`, `project_file_ui.dart` | o arquivo `.jopendaw`: montar, ler e validar o zip, refazer ids, importar (lógica pura) e a janela `Exportar projeto` com o seletor de arquivo (seção [Arquivo de projeto `.jopendaw`](#arquivo-de-projeto-jopendaw)) |

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

Para conferir a saída: `flutter test 2>&1 | tr '\r' '\n' | grep -E "All tests passed|Some tests failed|\[E\]"`. Mudou o motor: recompile os binários antes de testar no navegador ou no Android. O teste de uso (obrigatório antes de dar uma fase por pronta) é usar o app no Chrome: ver [03 Build, teste e depuração](03-build-teste-e-depuracao.md) e [20 Processo e histórico](20-processo-e-historico.md).

## Armadilhas conhecidas

- **Preferências contam como mudança para sincronizar.** `_save` compara o JSON inteiro com o último gravado (`DawController._save` em `controller.dart`); `metronome`, `count_in`, `rec_latency_ms`, `armed` e `monitor` estão no JSON, então ligar o metrônomo marca o projeto como pendente e gera versão nova no servidor (mesmo que outro aparelho as ignore ao aplicar). Lido no código; efeito sobre conflitos falsos `(não confirmado no uso)`.
- **`setTempo` e o desfazer.** O andamento mora no servidor; desfazer a mudança de andamento restaura só o documento local (`bpm` antigo no motor), enquanto `projects.bpm` mantém o novo. Ao reabrir, `open()` sobrescreve `doc.bpm` com o do projeto. `(não testado no app; deduzido de _travel e setTempo)`
- **Sem limpeza local ao apagar projeto.** `projects_screen` chama só `deleteProject` na API; `doc:<id>`, `sync:<id>` e os `sample:<hash>` ficam no aparelho. O cache `warp:<chave>` também não tem limpeza (registrado nas notas do projeto).
- **`docker-compose up` e a URL da API.** O app web servido em `localhost:8081` (container `web`) **não** usa o `api` do compose: `ApiClient.base` só adota a origem da página quando a porta é 8080 ou o host não é `localhost`; em `localhost:8081` cai na URL de produção (a menos de `--dart-define=API_BASE`, definido só no build). `(deduzido de client.dart:37; não testado)`
- **Cache do navegador.** Depois de `flutter build web`, `host.js`, `engine.wasm` e `main.dart.js` podem ficar velhos no navegador (service worker). O servidor de desenvolvimento manda `Cache-Control: no-cache`; ao testar, limpar o service worker e os caches evita `... is not a function`.
- **Estado de estúdio em teste.** `DawStudio` é público para os testes montarem a tela sem a API; o controlador aceita motor, guardado e API por injeção.
- **`ProjectScreen` recria o controlador** ao trocar de projeto (`ValueKey`), e o `dispose` do controlador salva (`_save`) e para o motor (`stop`, `panic`, `watch_*`): um projeto nunca deixa nota soando para o próximo.
- **Áudio → MIDI só com WAV.** `convertToMidi` envia o sample **original** (`sample:<hash>`) ao servidor, e o servidor só decodifica WAV PCM 16/24/32 ou float 32, mono/estéreo (`server/src/audio.rs:33`). Clipes importados de mp3, ogg, flac etc. falham com "formato não suportado" no job. `(não testado no app com mp3; deduzido do código)`
- **`flac` nunca é pedido pelo app.** O job `flac` existe no servidor, mas nada em `app/lib/` chama `createJob('flac', ...)`.
- **dart2js: operadores de bit em 32 bits.** Na web, `<<`, `>>`, `&`, `|`, `^` e `~` trabalham em 32 bits (o inteiro do dart2js é um número de JavaScript), enquanto na VM do Dart (testes, Android) o inteiro tem 64 bits. Então `1 << 62` dá 0 no navegador e `2 << 30` dá um número negativo, e a VM não mostra nada. Caso real, corrigido em `606664f`: `slicePoints` (`sampler_zones.dart`) começava a busca do menor comprimento de canal em `1 << 62`, que no navegador virava 0; `n == 0` devolvia lista vazia e o `Fatiar sample…` nunca achava corte (nem por transientes, nem em N fatias iguais). No mesmo commit, `ProjectFileLimits` (`project_file.dart`) tinha `maxTotalBytes = 2 << 30`, negativo no navegador, e o limite de tamanho do `.jopendaw` ficava errado. A regra: para inteiros grandes que rodam na web, use aritmética normal (`1024 * 1024 * 1024`, `reduce(math.min)` em vez de um valor inicial enorme; um `int` da web é exato só até 2^53) ou `BigInt`, nunca `<<` que passe de 31 bits, e nunca máscara ou deslocamento em valor que possa passar de 32 bits. O teste `app/test/web_int_safety_test.dart` varre `app/lib/` atrás de constantes `N << K` que passem de 31 bits, mas só enxerga literais (não vê `1 << n` com `n` variável, `>>` nem máscaras) e roda na VM, lendo os arquivos com `dart:io`. Levantamento de `<<` e `>>` em `app/lib/` (feito depois de `606664f`), todos hoje dentro de 32 bits, listados como riscos a vigiar:
  - `daw/project_file.dart:51-52`: `512 << 20` (2^29) e `64 << 20` (2^26); passam, mas não aceitam mais um bit; prefira a multiplicação, como os outros dois limites.
  - `daw/export.dart:126`: `1 << 30` como teto do `clamp` (2^30, no limite: `1 << 31` já seria negativo).
  - `daw/controller.dart:3271`: `_countZoneBars = 1 << 16`; `audio/engine_ffi.dart:883`: `1 << 20` (só Android); `daw/sync.dart:227`: `1 << math.min(_failures, 10)` (o `min` segura em 2^10; sem ele, a partir de 31 falhas o valor viraria negativo ou voltaria a 1 no navegador).
  - `daw/wav.dart:104-106` e `:185-186`: WAV de 24 bits, `q & 0xFF`, `q >> 8`, `q >> 16` e `bytes[p+2] << 16`; valores de no máximo 24 bits com sinal, seguros.
  - `daw/controller.dart:2453`: pitch bend `(data2 & 0x7F) << 7 | (data1 & 0x7F)`, 14 bits, seguro.
  - `daw/instrument_panel.dart:564-573` e `:2049-2071`: máscaras de portadores e moduladores do FM (`carriers >> n & 1`, `mods[to] >> from & 1`), de poucos bits (4 operadores), seguras.
  - `daw/automation_lane.dart:34,48,63`, `daw/automation_math.dart:42` e `daw/timeline.dart:274`: `(lo + hi) >> 1` em índices de busca binária; seguros enquanto a lista tiver menos de 2^31 itens.
  - Fora dos deslocamentos, os `Uint64` de `audio/engine_ffi.dart` são `dart:ffi` (só Android, 64 bits de verdade); `wav.dart:37` compara `total - 8 > 0xFFFFFFFF` sem operador de bit (comparação normal, exata até 2^53); o LCG de `sampler_zones_test.dart` faz `& 0xFFFFFFFF` sobre um produto de cerca de 2^52, no limite da exatidão da web.
