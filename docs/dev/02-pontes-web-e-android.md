# Pontes do motor: web (WASM) e Android (FFI)

> Como o motor Rust de `engine/` chega ao Dart na web e no Android, o que cada ponte garante, como acrescentar uma chamada nova de ponta a ponta e por que `engine.wasm` e os três `.so` são recompilados e commitados juntos; para quem mexe no motor, no host JavaScript ou em `app/lib/audio/`.

## Visão geral

O motor (`engine/src/`, crate `jopendaw-engine`) não sabe de plataforma: quem o hospeda chama `Engine::process` com blocos e manda comandos entre um bloco e outro. Há dois hospedeiros, com a mesma linguagem de comandos (chamadas por nome, `[nome, ...números]`):

```
                          app/lib/daw/controller.dart
                   AudioEngine.instance.calls([['tempo', 120, 4], ...])
                                     │
                      app/lib/audio/engine.dart  (export condicional)
              ┌──────────────────────┴───────────────────────┐
   dart.library.js_interop                              (padrão: dart:io)
              │                                               │
      engine_web.dart                                  engine_io.dart ── só Android tem motor
      (dart:js_interop)                                       │
              │                                         engine_ffi.dart  (dart:ffi, isolates)
   window.jopendawEngine                                      │  jd_* (C ABI, JSON nas chamadas)
   app/web/engine/host.js                                     ▼
      │            │                                 libjopendaw_engine.so   (engine/android)
      │ port       │ Worker                          ┌──────────────────────────────────┐
      ▼            ▼                                 │ thread do Dart: Host + filas rtrb│
 worklet.js   render-worker.js                       │   ─ fila de comandos ─▶          │
 (AudioWorklet)  (render, warp,                      │ thread de áudio (callback AAudio)│
      │           detecção de BPM)                   │   AudioCore ─▶ Engine::process   │
      ▼            ▼                                 │ supervisor (250 ms), isolates    │
 engine.wasm   engine.wasm                           └──────────────────────────────────┘
 (engine/wasm, funções C, sem wasm-bindgen)          engine::api::apply despacha por nome
```

A regra que amarra tudo: **`engine/wasm/src/lib.rs` é a fonte da verdade do protocolo**. Cada função exportada por ele é uma chamada; o nome do export é o nome da chamada e os parâmetros são os argumentos, na ordem. O Android não reimplementa nada: `engine::api::apply` (`engine/src/api.rs:55`) recebe `(nome, [f64])` e chama o mesmo método do motor que o export chamaria; testes garantem que os dois lados não divergem (ver "Como testar").

## Peças e responsabilidades

| Arquivo | Papel |
|---|---|
| `engine/wasm/src/lib.rs` | Exports `extern "C"` do motor para o WASM. Motor global único (`static ENGINE`, uma thread só), memória por ponteiro via `alloc`/`dealloc`. Contém também o warp (`stretch_run`, `detect_bpm`) usado só pelo Worker. |
| `engine/wasm/Cargo.toml` | `crate-type = ["cdylib"]`, depende só de `jopendaw-engine`. Sem wasm-bindgen. |
| `app/web/engine/host.js` | Ponte no thread principal: `window.jopendawEngine`. Cria o `AudioContext` e o `AudioWorkletNode`, baixa o wasm, decodifica áudio, guarda no IndexedDB, Web MIDI, microfone (`getUserMedia`), Workers de render/warp, download de arquivo, sha-256. |
| `app/web/engine/worklet.js` | `AudioWorkletProcessor` `jopendaw-engine`: instancia o wasm, aplica as chamadas entre blocos de 128 quadros, chama `process`, devolve estado (~60/s), loudness do master (~30/s, só quando muda), nível da entrada e blocos de captura. |
| `app/web/engine/render-worker.js` | Worker com instância própria do wasm: render fora de tempo real, `stretch`, `detect`. Sua parte sem `self` também roda no node (testes). |
| `app/web/engine/engine.wasm` | O binário commitado (não há hash no nome). |
| `app/lib/audio/engine.dart` | `export 'engine_io.dart' if (dart.library.js_interop) 'engine_web.dart'`: escolhe a implementação de `AudioEngine`/`LocalStore` em tempo de compilação. |
| `app/lib/audio/engine_types.dart` | `DecodedAudio` (canais `Float32List` + taxa), `EngineState` (batida, tocando, picos, `fxMeter`, espectro) e `LoudnessReading` (momentâneo, curto prazo, integrado, true peak e faixa; `none` = −200; `fromList` troca não finito por `none` e limita a −200..400). Único código realmente comum às duas pontes. |
| `app/lib/audio/engine_web.dart` | `AudioEngine` e `LocalStore` na web, tipados sobre `jopendawEngine` (`extension type _Host`, linha 9). |
| `app/lib/audio/engine_io.dart` | `AudioEngine` para o resto: delega a `FfiEngine` só no Android (`Platform.isAndroid`, linha 26); em outros sistemas cada chamada falha com `UnsupportedError`. Traz o `LocalStore` em arquivos (`FileStore`). |
| `app/lib/audio/engine_ffi.dart` | `EngineLib` (as 28 funções `jd_*` por `lookupFunction`, com `jd_loudness`), `FfiEngine` (polling, captura, entrada, MIDI do Android), e as funções que rodam em isolate: `decodeNow`, `stretchNow`, `detectBpmNow`, `renderNow`. |
| `engine/android/src/lib.rs` | Superfície C `jd_*`, códigos `ERR_*`, `HOST` global. Cada função pega pânico (`guard`). |
| `engine/android/src/host.rs` | `Host`: lado da thread do Dart (empurra comandos, lê estado, gerencia entrada, `pump`). |
| `engine/android/src/core.rs` | `AudioCore`: dono do `Engine` na thread de áudio; `drain` (comandos), `render`, `publish`. |
| `engine/android/src/call.rs` | JSON `[[nome, arg...], ...]` → `Call` (tamanho fixo, sem heap). |
| `engine/android/src/state.rs` | Estado publicado sem trava: `triple_buffer` para retrato e espectro, atômicos para picos e para as cinco medidas de loudness (`AtomicU64` com os bits de um f64, `LOUDNESS_KINDS = 5`). |
| `engine/android/src/capture.rs` | Anel de captura da entrada (60 s), marcas de batida por pedaço. |
| `engine/android/src/alloc.rs` | `#[global_allocator]` que adia liberações feitas na thread de áudio. |
| `engine/android/src/decode.rs` | Decodificação com symphonia; tabela de handles. |
| `engine/android/src/offline.rs` | Render fora de tempo real: um `Engine` por handle, sem thread de áudio. |
| `engine/android/src/platform/aaudio.rs` | AAudio carregado por `dlopen`/`dlsym`. |
| `engine/android/src/platform/android.rs` | Streams de saída (callback) e entrada (sem callback), supervisor. |
| `engine/android/src/platform/devices.rs` | JNI (sem Kotlin de áudio): lista entradas, consulta permissão de gravar; `JNI_OnLoad`. |
| `engine/android/src/platform/none.rs` | Fora do Android (testes no macOS): sem E/S, o host aplica os comandos direto. |
| `engine/build-web.sh`, `engine/build-android.sh` | Compilam e copiam os binários para o app (ver "Contratos"). |

## Fluxo de dados / ciclo de vida

### Web

1. **Subida** (`start`, `host.js:46`). Cria `new AudioContext({ latencyHint: 'interactive' })` (a taxa é a do contexto, tipicamente 44,1 ou 48 kHz), baixa `engine/engine.wasm` (`engineBytes`, `host.js:31`) em paralelo com `audioWorklet.addModule('engine/worklet.js')`, cria o `AudioWorkletNode` com uma entrada e uma saída estéreo (`host.js:53`) e manda os bytes numa mensagem `init` (uma cópia transferida). O worklet compila e instancia (`new WebAssembly.Instance(new WebAssembly.Module(msg.bytes), {})`, `worklet.js:79`) sem nenhum import, chama `init(sampleRate)` e responde `ready` com a taxa. `start()` devolve essa taxa ao Dart. O navegador só solta o áudio depois de um gesto do usuário: o Dart chama `resume()` num gesto.
2. **Áudio importado**. O Dart manda os bytes do arquivo para `decode` (`host.js:90`), que usa `ctx.decodeAudioData` (o navegador decodifica na taxa do contexto) e devolve até dois canais `Float32Array`. `loadSample` copia os canais e manda `{t:'sample'}`; o worklet reserva memória do wasm com `alloc`, copia e chama `sample_load`, que passa a ser dono da memória.
3. **Comandos**. `calls(list)` manda `{t:'calls', list}`; o worklet executa `w[name](...args)` para cada item, na ordem, entre um bloco e outro (`worklet.js:121`). Booleanos viram 0/1 no Dart (`engine_web.dart` `_js`).
4. **Bloco**. `process(inputs, outputs)` (`worklet.js:221`): se a entrada tem canais, copia para a memória do wasm e chama `set_input`; lê `playing`/`beat`; chama `process(left, right, n)`; copia a saída para o quantum de 128 quadros. Só reconstrói as vistas `Float32Array` quando a memória cresce.
5. **Estado**. A cada 6 blocos (768 quadros, ~16 ms a 48 kHz) manda `{t:'state', beat, playing, peaks, fxMeter, analyzing, spectrum}` com buffers transferidos (`worklet.js:303`); o espectro (1024 faixas) só a cada 3 estados e só com `watch_analyzer` ligado. O host repassa ao Dart por `setOnState` e guarda o pico máximo para o `probe`.
5b. **Loudness do master**. A cada 12 blocos (1536 quadros, ~32 ms a 48 kHz) o worklet, se o wasm exporta `loudness`, lê `loudness(0)` a `loudness(4)` (momentâneo, curto prazo, integrado, true peak, faixa) e manda `{t:'loudness', v:[5 números]}` **só se algum mudou** desde a última vez (`lastLoudness`). O host guarda em `probe.loudness` e chama o callback de `setOnLoudness(cb)` com `(m, s, i, tp, r)`; o Dart (`engine_web.dart`, `_hookLoudness`) monta um `LoudnessReading`. Zerar é a chamada `loudness_reset` por `calls`. Um wasm sem `loudness` não publica nada (a checagem `typeof w.loudness === 'function'` evita `TypeError` no laço de blocos).
6. **Captura** (gravação). Com `setCapture(true)` e o transporte tocando, o worklet junta a entrada em blocos de 4096 quadros (pool reaproveitado de 8 pares) e manda `{t:'rec'}` com a batida do primeiro quadro; o host copia para o Dart e devolve o par (`recycle`). Desligar manda o resto, depois `{t:'captured', notes}` com as notas ao vivo registradas (`rec_notes`).
7. **Render offline e warp** (`renderOffline` `host.js:346`, `warpJob` `host.js:409`). O host compila o wasm uma vez (`engineModule`, `WebAssembly.compile`), cria um `Worker('engine/render-worker.js')` por tarefa e manda o `WebAssembly.Module` já compilado (Workers aceitam clonar módulos), as chamadas do documento, os áudios (copiados) e o pedido. O Worker instancia o próprio motor, aplica `prepareCalls` (tira o transporte e a observação, apara clipes e notas no fim do trecho), pede capturas por saída (`capture_add`) e roda `process` em blocos de 1024 quadros até o fim mais a cauda, mandando progresso a cada 100 ms; devolve `{t:'done', outputs}` com os canais transferidos. Cancelar (`cancelRender`) dá `terminate()` no Worker. O teto de memória das saídas é 4 GiB (`render-worker.js:41`); o controlador divide as saídas em lotes de 384 MB (`controller.dart:3605`).
8. **Guardado local**. IndexedDB `jopendaw` versão 1, um object store `kv` (`host.js:112`), com `idbGet`/`idbPut`/`idbDelete`. Chaves usadas pelo app: `doc:<idDoProjeto>` (JSON do documento, texto), `sample:<sha256>` (bytes do áudio importado), `warp:<chave>` (WAV 32-bit float do áudio esticado), `template:<idDoProjeto>`, `rec:input` (entrada de áudio escolhida).

### Android

1. **Subida** (`FfiEngine.start`, `engine_ffi.dart:750`). Abre `libjopendaw_engine.so` (a `MainActivity` já a carregou por `System.loadLibrary`, o que dispara `JNI_OnLoad` com a `JavaVM`), confere que `jd_calls`, `jd_sample_load` e `jd_state` existem e chama `jd_start`. Este abre a saída AAudio na taxa nativa do aparelho, cria o motor nessa taxa (só na primeira vez) e devolve a taxa. Depois de `jd_stop`, `jd_start` reabre na mesma taxa e reabre a entrada que estava aberta; depois de um pânico na thread de áudio, recria o motor vazio (o Dart reenvia documento e áudios).
2. **Threads**. Três atores: a thread do Dart chama as funções `jd_*`; a thread de áudio é o callback do AAudio (dona do `Engine`); o supervisor (`jopendaw-sup`, acorda a cada 250 ms) reabre dispositivos que caíram, libera lixo e escreve diagnósticos no logcat.
3. **Comandos**. `jd_calls` recebe o JSON UTF-8 (`encodeCalls`, `engine_ffi.dart:198`, descarta a chamada inteira que tenha número não finito). O parse acontece na thread do Dart (`call::parse_calls`), gera `Vec<Call>` (cada `Call` é uma cópia simples, nome até 32 bytes e até 16 argumentos (`ARGS_MAX`, era 12 até o commit `6f3d245`, que subiu o limite para caber o `zone_add`), `call.rs:13,16`) e a lista inteira entra como **um** `Command::Calls` numa fila `rtrb` de 1024 (`core.rs:34`). O callback esvazia a fila antes de cada bloco (`drain`, `core.rs:193`) e aplica cada chamada com `api::apply`. Nome desconhecido ou argumento inválido só incrementa um contador de diagnóstico (`core.rs:229`); não há erro devolvido ao Dart. A lista aplicada volta pela fila de lixo para ser liberada fora da thread de áudio.
4. **Áudio**. `jd_sample_load` copia os canais para `Vec<f32>` na thread do Dart e empurra `Command::Sample`. A decodificação (`jd_decode`) e o warp (`jd_stretch`, `jd_detect_bpm`) rodam em isolates do Dart (`Isolate.run`), nunca na thread da UI nem na de áudio.
5. **Estado**. A thread de áudio publica ao fim de cada callback (`publish`, `core.rs:367`): retrato (batida, tocando, `fxMeter`, número de picos) num `triple_buffer`, picos por `fetch_max` atômico (leitor zera com `swap`), espectro em outro `triple_buffer` (~30/s com o analisador ligado). O Dart faz polling a cada 16 ms (`Timer.periodic`, `_schedule`) com `jd_state`; o espectro a cada 3 leituras; o polling de estado para com o app em segundo plano (o áudio segue).
5b. **Loudness do master**. A cada bloco a thread de áudio chama `e.loudness(k)` para os cinco `k` e guarda o resultado em atômicos (`Meters::set_loudness`, `state.rs`). O Dart lê com `jd_loudness(kind)` a cada 3 leituras de estado (`_loudnessEvery = 3`, 48 ms, ~20/s), só com o app em primeiro plano, monta um `LoudnessReading` e só chama `onLoudness` se a leitura mudou (`_pollLoudness`, `engine_ffi.dart`). Uma biblioteca sem `jd_loudness` (`ArgumentError` no `lookupFunction`) é lembrada em `_noLoudness` e nunca mais consultada. Zerar é `loudness_reset` por `jd_calls`.
6. **Sem saída**. Se a saída está parada, o callback ficou 100 ms sem bater (`STALL`, `host.rs:23`) ou o dispositivo está trocando, `Host::pump` aplica os comandos na própria thread do Dart (`AudioCore::idle`), para a fila não encher e o estado refletir o que foi mandado.
7. **Captura**. O callback lê a entrada (stream AAudio sem callback, lido sem bloquear de dentro do callback de saída: um relógio só) e, com a captura ligada e o transporte tocando, escreve num anel estéreo pré-alocado de 60 s (`RING_SECS`, `capture.rs:25`) com marcas de batida. O Dart lê com `jd_recorded` (até 16384 quadros por leitura) e, no fim, as notas com `jd_rec_notes` (`−1` enquanto o fim da captura não chegou à thread de áudio).
8. **Render offline**. `renderNow` (`engine_ffi.dart:512`) roda num isolate: `jd_offline_new(rate)` cria um `Engine` só do render, envia o documento e os áudios, chama `jd_offline_process` em blocos de 1024 quadros e copia cada saída com `jd_offline_captured`. Mais de 64 saídas (`MAX_CAPTURES`) vão em passadas, cada uma com um motor novo. Cancelar escreve num `Int32` nativo compartilhado que o laço confere a cada bloco.
9. **Guardado local**. `FileStore` em `getApplicationDocumentsDirectory()/jopendaw`: texto em `<chave>.txt`, bytes em `<chave>.bin`, gravação em arquivo `.tmp` e renomeação; as mesmas chaves da web.

## Contratos

### O protocolo de chamadas (o mesmo nos dois lados)

Uma chamada é `[nome, ...args]`; args são números (o Dart converte `bool` em 0/1). O conjunto completo (tabela nome → argumentos → efeito) está em [`01-motor.md`](01-motor.md); aqui vale o que muda de ponte para ponte:

| Aspecto | Web (worklet) | Android (`api::apply`) |
|---|---|---|
| Nome desconhecido | `w[name]` não é função: `TypeError`, capturado em `worklet.js:56`, vira `{t:'error'}` no console do host, **e o resto da lista é descartado** | Conta em diagnóstico e segue para a próxima chamada |
| Argumento faltando | Chega `NaN`/0 ao wasm | Erro, motor intocado (`api.rs` topo) |
| Argumento não finito | Passa adiante | Erro, motor intocado; e o `encodeCalls` do Dart já descarta a chamada inteira |
| Conversão de inteiro | A do JavaScript ao chamar o wasm (ToInt32/ToUint32) | Reproduzida em `wrap32` (`api.rs`): −1 num `usize` é a faixa 4294967295, que não existe |
| Máx. de faixas em `tracks` | Memória do wasm | `MAX_TRACKS = 1024` (`api.rs:51`); acima disso, erro |
| Tamanho da chamada | Sem limite | Nome até 32 bytes, até 16 argumentos (`call.rs`: `NAME_MAX = 32`, `ARGS_MAX = 16`); a maior é `zone_add`, com 16; 17 argumentos recusam a **lista inteira** |

### Chamadas de zona do sampler (`zones_clear`, `zone_add`)

Duas chamadas comuns (só números, sem ponteiro) levam as zonas do sampler ao motor. Nenhum arquivo de `app/lib/audio/` ou de `app/web/engine/` teve de mudar: as pontes repassam qualquer nome. A semântica (seleção, round-robin, loop, limites) está em [01-motor.md](01-motor.md#zonas-do-sampler-e-fatiamento-enginesrcsampler_zonesrs).

| Chamada | Argumentos, na ordem (tipo no wasm) | Web (worklet) | Android (`jd_calls`) |
|---|---|---|---|
| `zones_clear` | `faixa` (`usize`) | `w.zones_clear(i)`, export em `engine/wasm/src/lib.rs` | `Call::new("zones_clear", ...)`, `api::apply` → `Engine::clear_zones` |
| `zone_add` | `faixa` (`usize`), `sample` (`u32`), `nota base` (`u32`), `nota mínima` (`u32`), `nota máxima` (`u32`), `velocidade mínima` (`u32`), `velocidade máxima` (`u32`), `afinação em cents` (`f32`), `ganho em dB` (`f32`), `pan` (`f32`), `modo` (`u32`), `início` (`f64`), `fim` (`f64`), `início do loop` (`f64`), `fim do loop` (`f64`), `grupo` (`u32`) | `w.zone_add(...16 argumentos)`: `#[allow(clippy::too_many_arguments)]`, monta o `ZoneDef` e chama `Engine::add_zone` | Cabe por `ARGS_MAX = 16` (teste `zone_add_cabe_com_os_16_argumentos` confere que 16 passam e 17 são recusados); `api::apply` (`Call::ZoneAdd`, com `ZoneDef` dentro: por isso `size_of::<Call>()` subiu de 64 para 96 bytes) |

### Chamadas de expressão MIDI (`cc_clear`, `cc_add`, `live_cc`, `live_bend`)

Quatro chamadas comuns (só números) levam bend, modulação e pedal ao motor, sem mudar o limite de argumentos (a maior tem 4). Tabela de argumentos e comportamento em [04 Expressão MIDI](04-expressao-midi.md). Na web são exports de `engine/wasm/src/lib.rs` chamados pelo worklet (`w.cc_add(...)` etc.); no Android passam pelo mesmo `jd_calls` e por `api::apply`, e o teste `live_controls_are_recorded_with_the_real_apply` (`#[ignore]` por padrão) cobre o caminho real.

Pontos que valem nas três pontes:

- **Quem manda e quando.** `_syncZones` (`controller.dart`, chamado por `_docCalls` logo depois de `instrument_sample`) monta as chamadas com `SamplerZone.engineCall(faixa, idDoMotor)` e só as envia quando a lista de chamadas de zona da faixa **mudou** em relação ao que o motor já recebeu (`_SentTrack.zones`): então vai `zones_clear` seguido de todos os `zone_add`, por inteiro. Faixa sem zonas, e que nunca teve, não manda nada (projetos antigos não emitem chamadas novas).
- **Id do áudio.** O terceiro argumento é o id do motor do sha-256 da zona (`_sampleIds`), ou 0 se o áudio ainda não foi carregado neste aparelho. Quando o áudio chega e ganha id, a lista de chamadas muda e as zonas são reenviadas com o id certo; no motor, `load_sample` liga o áudio também às zonas que já citavam aquele id.
- **Conversão.** Inteiros seguem a regra do `api.rs` (JavaScript ao chamar o export: `ToUint32`); notas, velocidades e nota base passam por `min(127)`, grupo por `min(255)` e o motor limita o resto em `ZoneDef::sanitized`. `modo` é "diferente de zero" = até o fim. Números não finitos: no Android o `encodeCalls` descarta a chamada inteira; no `apply`, erro.
- **Render offline.** As duas chamadas **não** estão nas listas `SKIP` (`render-worker.js`) nem `renderSkip` (`engine_ffi.dart`), então o render fora de tempo real recebe as zonas junto com o resto do documento (`_fullSyncCalls`), e os áudios delas vão no lote (`_usedHashes` inclui `t.zones`).
- **Fatiar não é chamada.** `slice_points` e `slice_zones` existem no motor mas não passam pelas pontes: o app fatia em Dart e envia o resultado como `zone_add` comuns.
- **Fila do Android.** Uma lista com zonas pode ter até 129 chamadas de zona por faixa (`zones_clear` + 128 `zone_add`), todas dentro do mesmo `jd_calls`; continua sendo um comando na fila de 1024.

### Exports do wasm que não são chamadas (`HOST_ONLY`, `api.rs:182`)

Levam memória por ponteiro; cada hospedeiro tem função própria.

| Export wasm | Uso | Equivalente no Android |
|---|---|---|
| `alloc(len)` / `dealloc(ptr, len)` | JS reserva/solta `f32`s na memória do wasm; quem recebe o ponteiro vira dono | (não há: a FFI copia) |
| `init(rate)` | Recria o motor na taxa do contexto | `jd_start` cria o motor na taxa nativa |
| `process(left, right, n)` | Um bloco (128 no worklet, 1024 no Worker) | `AudioCore::render` no callback; `jd_offline_process` no render |
| `sample_load(id, l, r, frames, rate)` | Entrega áudio (`r` nulo = mono) | `jd_sample_load`, `jd_offline_sample` (copiam) |
| `analyzer(out, n)` | Espectro em dB (−120..0), máx. 1024 faixas | `jd_spectrum` |
| `set_input(l, r, n)` | Entrada do próximo bloco (até 4096 quadros) | (interno: `AudioCore::read_input`) |
| `rec_notes(out, max)` | Notas ao vivo registradas, grupos de 5 floats (faixa, altura, início, fim, velocidade) | `jd_rec_notes` |
| `captured(index, l, r, n)` | Copia a saída do último bloco de uma captura | `jd_offline_captured` |
| `peaks(out, max)` | Picos (esq, dir) por faixa e o master por último | `jd_state` |
| `stretch_run` / `stretch_channel` / `stretch_free` | Warp (`ratio`, `semitones`); resultado guardado no wasm até `stretch_free` | `jd_stretch` (devolve handle) |
| `detect_bpm` / `detect_confidence` | Andamento (60..200 BPM) e confiança 0..1 | `jd_detect_bpm` |

### Mensagens do worklet (`host.js` ↔ `worklet.js`)

| Sentido | Mensagem | Conteúdo |
|---|---|---|
| host → worklet | `init` | `bytes` do wasm (transferido) |
| | `sample` | `id`, `channels` (1 ou 2 `Float32Array`), `rate` |
| | `calls` | `list`: `[[nome, ...args], ...]` |
| | `capture` | `on` |
| | `input` | `on`: microfone ligado ao nó |
| | `recycle` | par de blocos de captura devolvido |
| worklet → host | `ready` | `rate` |
| | `state` | `beat`, `playing`, `peaks`, `fxMeter`, `analyzing`, `spectrum` |
| | `loudness` | `v`: `[momentâneo, curto prazo, integrado, true peak, faixa]` (~30/s, só quando muda; −200 = sem medida) |
| | `level` | `peak` da entrada (~30/s) |
| | `rec` | `left`, `right`, `frames`, `beat` |
| | `captured` | `notes` (`Float32Array`, 5 floats por nota) |
| | `error` | `message` |

### Mensagens do Worker (`render-worker.js`)

| Sentido | Mensagem | Conteúdo |
|---|---|---|
| host → Worker | `render` | `wasm` (Module), `rate`, `calls`, `samples: [{id, channels, rate}]`, `fromBeat`, `toBeat`, `tail`, `outputs` (−1 master, i faixa) |
| | `stretch` | `wasm`, `channels`, `rate`, `ratio`, `semitones` |
| | `detect` | `wasm`, `channels`, `rate` |
| Worker → host | `progress` | `p` 0..1 |
| | `done` | `outputs: [[esq, dir], ...]`, `frames` |
| | `stretched` | `channels`, `frames` |
| | `tempo` | `bpm`, `confidence` |
| | `error` | `code` (`empty`, `memory`, `unsupported`, `failed`), `message` |

### `window.jopendawEngine` (`host.js:480`)

| Membro | O que faz |
|---|---|
| `start()` / `resume()` | Sobe contexto e motor (devolve a taxa) / destrava o áudio (precisa de gesto) |
| `decode(bytes)` | `{channels, rate}` pelo `decodeAudioData` |
| `loadSample(id, channels, rate)` | Entrega áudio ao motor |
| `calls(list)` | Manda chamadas (ignora se o nó não existe: antes de `start`, as chamadas se perdem) |
| `setOnState(cb)` | `cb(beat, playing, peaks, fxMeter, spectrum)` |
| `setOnLoudness(cb)` | `cb(momentâneo, curto prazo, integrado, true peak, faixa)`; −200 = sem medida |
| `latency()` | `baseLatency + outputLatency` do contexto, em segundos |
| `idbGet` / `idbPut` / `idbDelete` | IndexedDB `kv` |
| `enableMidi()`, `setOnMidi`, `setOnMidiInputs`, `injectMidi(status, d1, d2)` | Web MIDI sem sysex; só mensagens de canal (0x80..0xEF); `injectMidi` simula um aparelho |
| `startInput(deviceId)`, `stopInput()`, `inputDevices()` | Microfone sem eco, ruído nem ganho automático; devolve `{latency, label}` ou `{error, message}` (`unsupported`, `denied`, `notfound`, `missing`, `busy`, `rate`, `aborted`, `failed`) |
| `setCapture(on)`, `setOnRecord`, `setOnInputLevel`, `setOnCaptureEnd`, `setOnInputLost` | Gravação |
| `renderOffline(job, onProgress)`, `cancelRender()` | Render num Worker |
| `stretchAudio(job, onProgress)`, `detectBpm(job)` | Warp e detecção num Worker |
| `saveFile(name, bytes, mime)` | Download por link temporário (vive 60 s) |
| `sha256(bytes)` | WebCrypto, em hexa |
| `probe()` | Diagnóstico: posição, tocando, estado do contexto, picos, `fxMeter`, espectro, `loudness` (os cinco valores com uma casa), pico da entrada; **zera** picos e `fxMeter` ao ler (ver [`03-build-teste-e-depuracao.md`](03-build-teste-e-depuracao.md)) |

### Superfície C do Android (`jd_*`)

Convenções (`engine/android/src/lib.rs:21-26`): só números e ponteiros; tamanhos são `size_t`; handles são `u64` (0 = falhou); ponteiros de saída são de quem chama; os de entrada são copiados antes de a função voltar; códigos de erro são negativos; toda função pega o pânico. Do lado do Dart, inteiros vão como `IntPtr` (`engine_ffi.dart` topo).

| Função (linha em `lib.rs`) | Assinatura | Retorno / efeito |
|---|---|---|
| `jd_start` (164) | `() → f64` | Taxa da saída, ou `ERR_*` como f64. Abre saída, cria/reabre motor, dispara o supervisor. |
| `jd_stop` (192) | `()` | Fecha saída e entrada; o motor fica. |
| `jd_calls` (199) | `(json: *u8, len) → i32` | 0 ou `ERR_BAD_ARG`/`ERR_BAD_JSON`/`ERR_NOT_STARTED`/`ERR_BUSY`. Lista aplicada inteira entre dois blocos. |
| `jd_sample_load` (217) | `(id: u32, l, r: *f32, frames, rate: f64) → i32` | Copia um áudio (`r` nulo = mono); recarregar um id troca. |
| `jd_sample_drop` (228) | `(id: u32) → i32` | Esquece um áudio. |
| `jd_state` (237) | `(out: *f64, max) → i32` | Escreve `[batida, tocando, fxMeter, n, picos...]` em **f64**; devolve `4 + n`, ou `ERR_PANIC`. |
| `jd_spectrum` (252) | `(out: *f32, n) → i32` | Até 1024 faixas em dB da faixa observada; 0 sem observação. |
| `jd_latency` (265) | `() → f64` | Latência de saída em segundos (0 sem saída). |
| `jd_loudness` | `(kind: i32) → f64` | Última medida de loudness do master publicada pela thread de áudio: 0 momentâneo, 1 curto prazo, 2 integrado (LUFS), 3 true peak máximo (dBTP), 4 faixa (LU). −200 = sem medida, `kind` desconhecido ou negativo, ou motor não iniciado. Não trava nem espera: só lê atômicos. Zerar é `loudness_reset` em `jd_calls`. |
| `jd_decode` (274) | `(bytes: *u8, len) → u64` | Handle do áudio decodificado; 0 se falhou. |
| `jd_decoded_info` (289) | `(h, *i64 frames, *i32 channels, *f64 rate) → i32` | 0 ou `ERR_BAD_ARG`; ponteiro nulo = valor não pedido. |
| `jd_decoded_copy` (311) | `(h, channel: i32, out: *f32) → i32` | Copia `frames` floats do canal. |
| `jd_decoded_free` (326) | `(h)` | Solta o handle. |
| `jd_stretch` (352) | `(l, r: *f32, frames, rate, ratio, semitones: f64) → u64` | Warp offline; handle no formato de `jd_decode`; 0 se falhou. |
| `jd_detect_bpm` (363) | `(l, r, frames, rate, *f64 bpm, *f64 conf) → i32` | 0 ou `ERR_BAD_ARG`; `bpm` 0 = não deu. |
| `jd_input_start` (388) | `(device: i32) → f64` | Latência de entrada em s, ou `ERR_*` (`NOT_STARTED`, `DENIED`, `NOT_FOUND`, `DEVICE`, `UNSUPPORTED`). |
| `jd_input_stop` (394) | `()` | Fecha a entrada. |
| `jd_input_devices` (402) | `(out: *u8, max) → i32` | Bytes do JSON `[["id","nome"],...]` (maior que `max`: nada escrito, tentar de novo). |
| `jd_capture` (417) | `(on: i32) → i32` | Liga/desliga captura (áudio e notas ao vivo). |
| `jd_recorded` (426) | `(l, r: *f32, max, *f64 beat) → i32` | Quadros lidos (0 = nada novo), de um trecho contínuo; `left == right` dá `ERR_BAD_ARG`. |
| `jd_input_level` (447) | `() → f32` | Pico da entrada desde a última leitura; `−1` uma vez se a entrada caiu. |
| `jd_rec_notes` (456) | `(out: *f32, max) → i32` | Floats escritos (múltiplo de 5); `−1` enquanto o fim da captura não chegou à thread de áudio. |
| `jd_offline_new` (472) | `(rate: f64) → u64` | Motor de render (8000..384000 Hz); 0 se a taxa é inválida. |
| `jd_offline_calls` (484) | `(h, json, len) → i32` | Quantas chamadas o motor não conhecia, ou `ERR_*`. |
| `jd_offline_sample` (494) | `(h, id, l, r, frames, rate) → i32` | Áudio para o render. |
| `jd_offline_process` (510) | `(h, frames) → i32` | Quadros processados (até 4096). |
| `jd_offline_captured` (519) | `(h, index: i32, l, r, n) → i32` | Copia o último bloco; `−1` = saída do `process` (master pós-limitador), `≥ 0` = índice de `capture_add`. |
| `jd_offline_free` (533) | `(h)` | Solta o motor do render. |
| `JNI_OnLoad` (`platform/devices.rs:17`) | | Guarda a `JavaVM` para listar entradas e consultar a permissão de gravar. |

Códigos (`lib.rs:86-104`): `ERR_NOT_STARTED −1`, `ERR_BAD_JSON −2`, `ERR_BUSY −3` (fila cheia por mais de 250 ms), `ERR_BAD_ARG −4`, `ERR_PANIC −5`, `ERR_UNSUPPORTED −6` (sem AAudio ou fora do Android), `ERR_DEVICE −7`, `ERR_NOT_FOUND −8`, `ERR_DENIED −9` (sem `RECORD_AUDIO`), `ERR_MEMORY −10`.

### Formatos aceitos na decodificação do Android

`engine/android/Cargo.toml` liga o symphonia com `wav`, `aiff`, `caf`, `pcm`, `adpcm`, `flac`, `mp3`, `ogg`, `vorbis`, `aac`, `isomp4`, `alac`. **Sem Opus** (o symphonia 0.5 não tem). O formato é descoberto pelo conteúdo, `enable_gapless` está ligado, mais de dois canais ficam só com os dois primeiros, e a taxa do arquivo é mantida (o motor converte ao tocar). O que a web aceita depende do navegador (`decodeAudioData`).

### Regra de recompilar e commitar os binários

Os binários ficam no repositório para que `flutter build web`/`flutter build apk` e o Docker do `app` não precisem de Rust:

- `app/web/engine/engine.wasm` ← `./engine/build-web.sh` (`cargo build -p jopendaw-engine-wasm --target wasm32-unknown-unknown --profile wasm`, cópia de `target/wasm32-unknown-unknown/wasm/jopendaw_engine_wasm.wasm`).
- `app/android/app/src/main/jniLibs/{arm64-v8a,armeabi-v7a,x86_64}/libjopendaw_engine.so` ← `./engine/build-android.sh` (`cargo ndk -P 24 -t arm64-v8a -t armeabi-v7a -t x86_64 -o … build -p jopendaw-engine-android --profile android`).

**Mudou qualquer coisa em `engine/src/`, `engine/wasm/` ou `engine/android/`: rode os dois scripts e commite o `engine.wasm` e os três `.so` no mesmo commit do código-fonte.** Recompilar só um lado deixa uma plataforma com o motor velho, e o sintoma é traiçoeiro: no Android um `apply` novo simplesmente não existe (a chamada cai no contador de "desconhecidas" e o motor fica mudo naquele recurso); na web o `w[name]` inexistente lança `TypeError` e derruba o resto da lista de chamadas. Nada nos testes compara o binário commitado com o fonte: só a saída do `build-android.sh` (que confere os símbolos exportados) e os testes de paridade dos fontes protegem (ver "Como testar").

**Histórico dos binários (zonas do sampler).** Os commits das zonas (`b6b7abb`, `6f3d245`, `6e5fa7b`) não recompilaram os binários, e sem as chamadas `zone_add`/`zones_clear` a web perdia o resto da lista de chamadas (`TypeError` em `w.zone_add`) e o Android, com o `.so` velho de `ARGS_MAX = 12`, recusava a lista inteira. **Resolvido em `357b6fc`**, que recompilou o `engine.wasm` e os três `.so` (conferido: os quatro contêm `zone_add`).

**Histórico dos binários (loudness).** O commit `dca27bc` (medição de loudness) mexeu em `engine/src/`, `engine/wasm/` e `engine/android/` sem recompilar os binários, e o corpo do commit avisava; até a integração o medidor do mixer ficava em `—` e `Zerar` não fazia nada nas duas plataformas (a normalização da exportação sempre funcionou, é Dart puro). **Resolvido em `357b6fc`** (os quatro binários contêm `loudness_reset`). A lista `want` do `build-android.sh` ganhou os símbolos novos nesse commit (confira o script atual).

Requisitos do build (o `rust-toolchain.toml` só fixa `stable` e os componentes; os alvos e o NDK são por conta de quem compila): `rustup target add wasm32-unknown-unknown aarch64-linux-android armv7-linux-androideabi x86_64-linux-android`, `cargo install cargo-ndk`, NDK 28 (`ANDROID_NDK_HOME`, ou o `28.2.13676358` no Android Studio do Mac). O script Android confere que cada `.so` exporta as funções da lista `want` e que não depende de `libaaudio.so`.

Perfis (`Cargo.toml` raiz): `wasm` herda `release` (opt-level 3, LTO fat, `panic = "abort"`, símbolos removidos); `android` herda `release` mas com `panic = "unwind"`, porque cada função exportada e a thread de áudio usam `catch_unwind` (com `abort`, um pânico derrubaria o app inteiro).

## Decisões e por quê

- **Sem wasm-bindgen.** O escopo do AudioWorklet não tem `TextDecoder`, `fetch` e afins, e a cola do wasm-bindgen conta com eles (`engine/wasm/src/lib.rs:3`). Por isso a interface do wasm é só número e ponteiro, o wasm não importa nada (`Instance(module, {})`) e o JS mexe na memória por `memory.buffer`.
- **O host manda os bytes do wasm, não o `WebAssembly.Module`.** O Chrome não entrega um módulo compilado da thread principal ao escopo do worklet (`worklet.js:3-4`), então o host baixa uma vez (`engineBytes`) e o worklet compila. Já os Workers aceitam clonar um `Module`, então o host compila uma vez (`engineModule`) e reutiliza em cada render ou warp, sem depender da rede de novo.
- **Instância própria para render e warp.** O Worker não toca o motor que está tocando; exportar e tocar ao mesmo tempo não se atrapalham, e o cálculo pesado não roda na thread de áudio nem na da UI.
- **`engine::api::apply` como espelho, não como cópia.** Em vez de escrever a lista de chamadas duas vezes à mão, a tabela `CALLS` (`api.rs:132`) descreve cada export e testes a conferem contra o fonte do wasm e contra o efeito no motor. A conversão numérica reproduz a do JavaScript de propósito (`wrap32`), para que a mesma lista de chamadas dê o mesmo motor nas duas plataformas.
- **Fila sem trava e alocador adiado no Android.** O callback do AAudio nunca espera: pega o `Mutex` do núcleo só com `try_lock` (se falhar, entrega silêncio, `platform/android.rs:62`), recebe comandos por `rtrb`, devolve o que soltou por outra fila e, para o que o motor solta por dentro, o `#[global_allocator]` (`alloc.rs`) troca `dealloc` por um pedido numa fila fixa de 8192 posições que a thread do Dart ou o supervisor coletam. Fila cheia: libera ali mesmo (contado em `overflows`).
- **AAudio por `dlopen`.** Ligar direto na `libaaudio.so` faria a biblioteca inteira falhar ao abrir num aparelho sem AAudio (`aaudio.rs:1-7`), levando junto decodificação e render. Com `dlopen`, só o áudio ao vivo diz `ERR_UNSUPPORTED`. O `build-android.sh` proíbe a dependência.
- **Loudness: medir no motor, normalizar em Dart.** A leitura ao vivo do master (`loudness.rs`) precisa estar no motor porque só ele vê a saída depois do limitador, e chega às duas pontes como consulta (`loudness(kind)` no wasm e no `apply`, `jd_loudness` no Android). A normalização da exportação, ao contrário, roda em Dart puro (`app/lib/daw/loudness.dart`: `measureLoudness`, `planNormalization`, `normalizeLoudness`) sobre os canais que o render devolveu: o mesmo código serve a web e o Android, não precisa de chamada nova nem de recompilar os binários, e cede o controle ao laço de eventos a cada ~0,5 s de áudio para a tela não travar. O custo é manter dois cálculos do mesmo padrão (BS.1770-4) que devem concordar; os testes de Dart repetem os casos do Rust.
- **`loudness` é consulta, então precisa de `jd_` no Android.** `jd_calls` não devolve valores; por isso a mesma chamada existe como `loudness` em `CALLS` (para o wasm, o `apply` e os testes) e como `jd_loudness` (leitura de atômicos, sem esperar a thread de áudio). As duas, e `loudness_reset`, estão nas listas `SKIP` e `renderSkip`: o render offline não as executa.
- **Polling em vez de callback no Android.** O estado é lido a 16 ms pelo Dart em vez de a thread de áudio chamar o Dart: nada atravessa a fronteira a partir da thread de áudio.
- **JSON nas chamadas do Android.** Um `jd_calls` leva a lista inteira (uma sincronização completa manda milhares de `note_add`); um só custo de FFI, um só comando na fila e uma aplicação atômica entre dois blocos.
- **Isolates para o trabalho pesado.** `decodeNow`, `stretchNow`, `detectBpmNow` e `renderNow` abrem a biblioteca de novo dentro do isolate (`EngineLib.open`); são funções de nível superior e recebem só dados, porque timers e portas não viajam para outro isolate.
- **Duas listas de chamadas ignoradas no render.** `SKIP` (`render-worker.js:45`) e `renderSkip` (`engine_ffi.dart:338`) são idênticas de propósito; um teste em Dart compara o plano do render com o do `render-worker.js` rodando no node.
- **Mesma interface, sem `implements`.** `engine_web.dart` e `engine_io.dart` declaram cada um a sua `AudioEngine`; a paridade é por convenção e por compilar de cada lado (`engine_io.dart` só implementa o contrato `EngineEvents` de `engine_ffi.dart:87`).

## Como testar

- **Paridade wasm ↔ `apply` (Rust, sem plataforma):** `cargo test -p jopendaw-engine`. `apply_conhece_todos_os_exports_sem_ponteiro_do_wasm` (`api.rs:825`) lê `engine/wasm/src/lib.rs` com `include_str!` e falha, com mensagem explícita, se um export sem ponteiro não está em `CALLS` (mesmos tipos de parâmetros e retorno), se um com ponteiro não está em `HOST_ONLY`, ou se algo da tabela não existe no wasm. `cada_chamada_muda_o_motor_como_o_export` exige um caso em `cases()` (`api.rs:683`) para cada chamada e compara o efeito de `apply` com o do corpo do export.
- **Biblioteca Android no computador:** `cargo test -p jopendaw-engine-android`. Fora do Android não há E/S (`platform/none.rs`) e os testes chamam as `jd_*` e o `render` direto. Dois testes estão `#[ignore]` (`offline_render_with_the_real_apply`, `live_notes_with_the_real_apply`); rodam com `-- --ignored`.
- **Dart × wasm:** `flutter test test/studio_test.dart` (em `app/`) extrai os exports do fonte `engine/wasm/src/lib.rs` (`wasmExports()`) e confere que toda chamada que o controlador mandou existe, com o mesmo número de argumentos.
- **Fronteira `dart:ffi` no computador:** `flutter test test/engine_native_test.dart` compila `app/test/native/fake_engine.c` com o `cc` do sistema, que implementa o contrato `jd_*` do topo de `engine_ffi.dart`; sem compilador, os testes são pulados. `test/engine_ffi_test.dart` cobre JSON, plano do render e, com `node` disponível, compara com o `render-worker.js` real (linha 252).
- **No aparelho:** `flutter test integration_test -d emulator-5554` (`app/integration_test/engine_test.dart` e `platform_test.dart`; detalhes em [`03-build-teste-e-depuracao.md`](03-build-teste-e-depuracao.md)).
- **Loudness:** `cargo test -p jopendaw-engine loudness` (o medidor e sua medida pelo `Engine`), `cargo test -p jopendaw-engine-android` (`loudness_is_published_per_kind` em `state.rs`; `jd_loudness` devolve −200 sem motor e `loudness_reset` responde 0 em `lib.rs`), e em `app/`: `flutter test test/loudness_test.dart test/export_loudness_test.dart` (medição em Dart e a exportação normalizada) e `test/engine_native_test.dart` (o `fake_engine.c` tem um `jd_loudness` de mentira).
- **Saída do build Android:** o `build-android.sh` termina com erro se algum `.so` não exporta as funções da lista `want`.

## Checklist: acrescentar uma chamada nova de ponta a ponta

Caso comum: chamada sem ponteiro (números in, opcionalmente um número out). Suponha `foo(track, value)`.

1. **Motor.** Método em `Engine` (`engine/src/lib.rs` ou no módulo dono) com testes de unidade.
2. **Export do wasm** em `engine/wasm/src/lib.rs`: `#[unsafe(no_mangle)] pub extern "C" fn foo(track: usize, value: f32) { engine().foo(track, value) }`. Mantenha o formato (uma assinatura simples, sem vírgula dentro de tipo genérico, `pub extern "C" fn` ou `pub unsafe extern "C" fn`): o teste do `api.rs` e o `wasmExports()` do Dart leem o fonte por texto.
3. **`engine/src/api.rs`** (o teste do item 2 falha até você fazer os quatro): variante em `enum Call` (`api.rs:63`); linha em `CALLS` (`api.rs:132`) com os **mesmos tipos** do export (`Ty::F32` para `f32`, `Usize` para `usize`, e assim por diante; booleano é `U32`); ramo em `Call::parse` (`api.rs:275`); ramo em `Call::apply` (`api.rs:348`); e um caso em `cases()` (`api.rs:683`) que mostre que a chamada muda o motor (`Changes`), é inócua (`Same`) ou é consulta (`Query`).
4. **Dart.** O controlador emite `_engine.calls([['foo', track, value]])` (`controller.dart` tem dezenas de exemplos). **Nenhum arquivo de `app/lib/audio/` precisa mudar**: as três pontes repassam qualquer nome. Restrições: só `num`/`bool` como argumentos (fora o nome), até 16 argumentos e nome até 32 bytes (Android).
5. **Render offline.** Se a chamada não deve valer no render (transporte, observação, notas ao vivo, entrada, consulta), inclua o nome nas **duas** listas: `SKIP` (`app/web/engine/render-worker.js:45`) e `renderSkip` (`app/lib/audio/engine_ffi.dart:338`). Se ela tem tratamento especial no aparo do fim do trecho (como `clip_add` e `note_add`), o mesmo código precisa existir em `prepareCalls` (`render-worker.js:105`) e `prepareRenderCalls` (`engine_ffi.dart`).
6. **Testes do Dart.** Se o `FakeEngine` (`app/test/fake_engine.dart`) ou algum teste precisar conhecer a chamada nova, atualize (não confirmado que algum precise: ele registra as chamadas em `log`).
7. **Recompile e commite os binários**: `./engine/build-web.sh` e `./engine/build-android.sh`, com `engine.wasm` e os três `.so` no mesmo commit do código.
8. **Verifique** (ver `03`): `cargo test -p jopendaw-engine`, `cargo test -p jopendaw-engine-android`, `flutter test`, e o teste de uso no Chrome e no emulador (a chamada nova precisa fazer efeito nas duas pontes).

Se a chamada passa memória por ponteiro (buffers, áudio, resultados) ou tem retorno estruturado, o caminho é o de uma função de hospedeiro:

- **Web:** export em `engine/wasm/src/lib.rs`, nome em `HOST_ONLY` (`api.rs:182`); uso em `worklet.js` (bloco) ou `render-worker.js` (fora de tempo real), mensagem nova no protocolo e membro novo em `window.jopendawEngine` (`host.js:480`), mais o `extension type _Host` em `engine_web.dart:9`.
- **Consulta com retorno em tempo real** (o caso de `loudness`): no wasm basta o export (e a linha em `CALLS`), e o worklet o chama direto, sem passar por `calls`. No Android o retorno não volta por `jd_calls`; a thread de áudio publica o valor em atômicos (`state.rs`), a função `jd_*` só lê, e o polling no Dart (`_poll`) chama o callback quando muda. Coloque o nome nas duas listas de render ignorado (item 5).
- **Android:** função `jd_*` em `engine/android/src/lib.rs` com `guard` e código de erro, lógica em `host.rs`/`core.rs` (thread de áudio: sem alocar, sem esperar), `lookupFunction` em `EngineLib` (`engine_ffi.dart`), o nome na lista `want` de `engine/build-android.sh` e a implementação de mentira em `app/test/native/fake_engine.c`.
- **Dart comum:** o método novo nos dois `AudioEngine` (`engine_web.dart` e `engine_io.dart`, que delega a `FfiEngine`), com a mesma assinatura; tipos compartilhados em `engine_types.dart`.
- Recompile e commite os binários (item 7).

## Armadilhas conhecidas

- **`engine.wasm` ou `.so` desatualizados**: ver "Regra de recompilar". Depois de recompilar a web, o navegador pode servir `host.js`/`worklet.js`/wasm velhos; o servidor e o nginx mandam `no-cache` (revalide a cada carga), mas uma aba já aberta continua com o worklet antigo até recarregar, e o service worker `/sw.js` é rede primeiro com cache só sem rede. Detalhes em `03`.
- **Zonas do sampler com binário velho** (caso da fase 8, resolvido em `357b6fc`). Só aparece em faixa que tem zonas: na web, `zone_add` inexistente lança `TypeError` e descarta o resto da lista; no Android, o `.so` de 12 argumentos rejeita o JSON da lista toda (`ERR_BAD_JSON`, só um `debugPrint` no Dart). O sintoma é o instrumento mudo e outras mudanças da mesma sincronização não aplicadas. Se voltar a acontecer, falta recompilar (ver "Regra de recompilar").
- **Medidor de loudness mudo com binário velho** (caso da fase 8, resolvido em `357b6fc`). Com um `engine.wasm` ou `.so` anterior ao commit `dca27bc`, o app novo abre normalmente: o medidor mostra `—` e `Zerar` não faz nada (na web o `loudness_reset` lança `TypeError` no worklet, capturado como `{t:'error'}`; no Android a chamada cai no contador de desconhecidas). Não é defeito do código do app: falta recompilar.
- **Web: um nome desconhecido descarta o resto da lista.** O laço de `calls` no worklet lança no primeiro `TypeError`. No Android a mesma lista é aplicada com a chamada ignorada. Por isso um `.wasm` velho com um app novo dá defeito diferente em cada plataforma.
- **Web: `process` sem tratamento de trap.** O wasm é `panic = "abort"`; um pânico vira trap dentro do `process` do worklet, e não há `processorerror` em `host.js` (`grep` confirma): o nó fica mudo sem aviso ao Dart. (Trap em `onMessage` é capturado e vira `{t:'error'}`.)
- **Web: o áudio decodificado já vem na taxa do contexto** (`decodeAudioData` reamostra). No Android o `DecodedAudio` traz a taxa do arquivo e o motor converte ao tocar. O mesmo arquivo, portanto, não passa pelo mesmo reamostrador nas duas plataformas (`(não confirmado)` que a diferença seja audível).
- **Web: `sample_load` roda na thread de áudio** (o worklet aloca e copia a memória do áudio dentro do `onmessage`, `worklet.js:110-120`); importar um áudio longo com o projeto tocando pode causar falha de áudio. No Android a cópia é feita na thread do Dart e só o `Sample` pronto atravessa a fila.
- **Android: "nada aloca na thread de áudio" vale para liberação, não para alocação.** O alocador só adia `dealloc`/`realloc` (`alloc.rs:84`). Chamadas que criam faixa, instrumento ou efeito (`tracks`, `track_kind`, `fx_set`) alocam dentro do callback, como diz o topo de `api.rs`. Uma lista grande (sincronização completa) também é aplicada inteira dentro de um único callback (`core.rs:197`).
- **Android: retorno `i32` lido como `IntPtr` no Dart** (`jd_state`, `jd_spectrum`, `jd_recorded`, `jd_rec_notes`, `jd_input_devices`, `jd_decode*` em `engine_ffi.dart:121-151`). Em C, um `i32` negativo devolvido em 64 bits não é estendido com sinal garantidamente (no arm64 e no x86_64 o compilador costuma zerar a metade alta), então um `ERR_*` ou o `−1` de `jd_rec_notes` pode chegar ao Dart como 4294967291/4294967295. Em `_pollState` isso cai na validação de `parseEngineState` e é ignorado; em `_readNotes` o `math.min(..., _notesMax)` transformaria esse valor em 16384 notas zeradas. `(não confirmado em aparelho)`; a correção segura é declarar o retorno como `Int32` onde o Rust devolve `i32`.
- **Android: `jd_state` escreve f64, o binding declara `Pointer<Float>`.** O Dart reserva `Double` e lê primeiro como f32, depois como f64 (`parseEngineState`, `engine_ffi.dart:236`) por desconfiar da biblioteca; hoje a biblioteca sempre escreve f64 e o caminho f32 é herança. A heurística depende de o f32 falhar na validação; vale simplificar para f64.
- **Android: a fila de comandos tem 1024 posições** e cada `jd_calls` é uma posição; com a thread de áudio travada, `jd_calls` espera até 250 ms e devolve `ERR_BUSY` (`host.rs:31`), que o Dart só registra com `debugPrint`.
- **Android: trava global.** Toda `jd_*` da thread do Dart pega o `Mutex` global `HOST` (`lib.rs:106`), que o supervisor também pega a cada 250 ms para `maintain()`.
- **Picos:** o Android publica no máximo 256 faixas mais o master (`state.rs:12`); o wasm escreve quantos picos couberem em 514 floats (`worklet.js:15`), então com mais de 256 faixas o master pode ficar de fora na web. O Dart reserva espaço para 1024 faixas (`engine_ffi.dart:875`).
- **Render de muitas saídas:** o motor tem no máximo 64 capturas (`engine/src/record.rs:22`). No Android `renderNow` divide em passadas; na web `renderWith` falha com "O motor não conseguiu separar a faixa N" se um único render pedir mais de 64 saídas por faixa, e o lote do controlador é calculado só pela memória (`controller.dart:3650`). Projeto curto com mais de 64 faixas e stems: `(não confirmado)` se dispara na web.
- **Sem Opus no Android**: um `.opus` importa na web (se o navegador decodifica) e falha no aparelho com "o formato não é suportado".
- **Só Android tem motor fora do navegador.** Em desktop, `AudioEngine.supported` é falso e toda chamada de áudio dá `UnsupportedError`; os testes usam `FakeEngine` ou o `fake_engine.c`.
- **Comentários desatualizados** que confundem quem chega agora: `engine/src/lib.rs` (cabeçalho) e `engine_ffi.dart` falam em "Oboe"; o código usa AAudio direto por `dlopen`. `MainActivity.kt` fala em "cpal/oboe". `build-android.sh` diz que a mínima do app é 24, mas `app/android/app/build.gradle.kts` fixa `minSdk` em pelo menos 26 (o `dlopen` do AAudio continua útil como defesa, mas o motivo original não vale mais). Dois testes de `engine/android/src/lib.rs` seguem `#[ignore]` por um "esqueleto de `apply`" que não existe mais.
- **A lista `want` do `build-android.sh` não tem `jd_stretch` nem `jd_detect_bpm`** (a biblioteca as exporta, `lib.rs:352,363`, e o Dart as usa); uma regressão que apagasse essas duas passaria na conferência do script.
