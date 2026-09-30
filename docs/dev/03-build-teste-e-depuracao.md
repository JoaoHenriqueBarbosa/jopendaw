# Build, teste e depuração

> Todos os comandos para compilar, testar, checar estilo e depurar o jopendaw (Rust, Flutter web, Android, servidor), com as armadilhas que já custaram tempo. Para quem mexe em qualquer camada.

## Visão geral

Há quatro "mundos" e cada um tem o seu ciclo:

```
 Rust (workspace)          Flutter (app/)               Backend em execução        Uso real
 ─────────────────         ─────────────────            ───────────────────        ─────────────────────
 cargo fmt/clippy/test     flutter analyze / test       ./hot.sh (hot-patch)       Chrome :9222 + tool/cdp.mjs
 engine/build-web.sh   ──▶ flutter build web --release  Postgres + MinIO (docker)  emulador Android + adb
 engine/build-android.sh─▶ flutter build apk            login por código de acesso  flutter test integration_test
      (binários commitados: engine.wasm e os 3 .so)
```

Regra que atravessa tudo: o **teste de uso** (usar o app no Chrome e no emulador) é obrigatório antes de dar uma fase por pronta (`CLAUDE.md`, "Teste de uso"). Revisar código não substitui.

Não há CI no repositório (nenhum `.github/`): quem roda os checks é quem mexe.

## Peças e responsabilidades

| Arquivo | Papel |
|---|---|
| `Cargo.toml` (raiz) | workspace (`server`, `engine`, `engine/wasm`, `engine/android`) e perfis `dev`, `test`, `release`, `server`, `wasm`, `android`. |
| `rust-toolchain.toml` | `stable` com `rustfmt`, `clippy`, `rust-analyzer`. |
| `rustfmt.toml` | `max_width = 160`, `use_small_heuristics = "Max"`, edição 2024. |
| `hot.sh` | sobe a API com `dx serve --hot-patch --features hot`. |
| `engine/build-web.sh` | compila o motor para WASM e copia para `app/web/engine/engine.wasm`. |
| `engine/build-android.sh` | compila os três ABIs, confere os símbolos exportados e copia para `app/android/app/src/main/jniLibs/`. |
| `docker-compose.yml` | `db` (Postgres 17, `jopendaw-pg`), `minio` + `minio-init`, `api`, `web`. |
| `server/Dockerfile`, `.dockerignore` | imagem da API; contexto = a raiz do repositório (`docker build -f server/Dockerfile .`, ou o `api` do compose). Copia o workspace inteiro (inclusive `engine/`) para o cargo carregar os membros. |
| `app/Dockerfile`, `app/nginx.conf.template` | imagem do app web (Flutter 3.47.4 + nginx); contexto = `app/`. O nginx faz proxy de `/api/` com corpo de até 600 MB. |
| `tool/cdp.mjs` | cliente CDP sem dependências (Node 22 ou mais novo) para o Chrome de depuração. |
| `app/test/` | testes de unidade e de widget (`fake_engine.dart`, `fake_sync_api.dart`, `native/fake_engine.c`). |
| `app/integration_test/` | `engine_test.dart` (motor nativo no Android) e `platform_test.dart` (ponte com o Android). |
| `server/src/routes/tests.rs` | testes de rota contra Postgres de verdade (`TEST_DATABASE_URL`). |
| `app/web/sw.js` | service worker do PWA (relevante para cache ao testar; ver adiante). |

## Fluxo de dados / ciclo de vida

### 1. Preparar o ambiente

```bash
docker-compose up -d db                                  # Postgres (colima: use docker-compose)
docker exec -i jopendaw-pg psql -U jopendaw -d jopendaw < server/schema.sql   # schema, 1ª vez
cp server/.env.example server/.env                       # preencha JWT_SECRET e JMAIL_API_KEY
docker-compose up -d minio minio-init                    # (opcional) S3 local: API :9000, console :9001
```

- O compose não monta o `schema.sql` no `initdb` porque o colima não enxerga `/Volumes`.
- Imagens Docker (opcional): `docker-compose up --build` constrói a `api` (`server/Dockerfile`, contexto na raiz) e a `web` (`app/Dockerfile`, contexto `app/`) e sobe tudo, com a API em :8080 e o nginx em :8081. O contexto da API é a raiz porque o workspace lista `engine/`, `engine/wasm` e `engine/android`; o `Dockerfile` copia `engine/` por causa disso (desde `0c0593e`; antes dele o build da imagem não achava os manifestos dos membros do workspace). O `.dockerignore` da raiz mantém fora `target/`, `app/`, `dumps/`, `**/.env`, `.git/`, `.claude/`, `docs/`, `engine/target/` e `node_modules/`. Não rodei esse build ao atualizar este capítulo.
- Depois de mudar o schema em produção/dev, rode o script idempotente de `db/migrations/` (hoje: `docker exec -i jopendaw-pg psql -U jopendaw -d jopendaw < db/migrations/2026-09-30-fase6.sql`).
- `server/.env` precisa de `JWT_SECRET` (32+ caracteres) e `JMAIL_API_KEY`. Sem eles o servidor não sobe (`server/src/config.rs`). Para usar áudio no MinIO local, descomente as linhas `S3_*` do `.env.example` (`S3_ENDPOINT=http://localhost:9000`, `S3_BUCKET=jopendaw`, `S3_ACCESS_KEY=jopendaw`, `S3_SECRET_KEY=jopendaw-minio-dev`); sem `S3_ENDPOINT` os áudios vão para `DATA_DIR` em disco.

### 2. Backend: sempre com hot-patch (`./hot.sh`)

Regra do projeto: para rodar, testar ou iterar no backend usa-se `./hot.sh`, nunca `cargo run` reiniciado a cada mudança.

```bash
./hot.sh --interactive false > /tmp/hot.log 2>&1 &     # em background; sem TTY, --interactive false
until curl -sf localhost:8080/healthz; do sleep 3; done # espera subir (sleep longo em foreground é bloqueado)
```

- A API sobe na `:8080` e serve `app/build/web` se ele existir. O devserver do `dx` fica na `:8090` (`DX_PORT`), para não colidir.
- O script chama `~/.cargo/bin/dx` (padrão da variável `DX`) e exige `dioxus-cli 0.7.x` (`cargo install dioxus-cli --version 0.7.10 --locked`), porque o `dx` do Deno costuma vir antes no `PATH`.
- Editou o **corpo** de uma função em `server/src`: salvar aplica em ~1 s; confira no log do dx (`Hot-patching: ... took NNNms`) e pela própria API.
- Mudou struct, enum, assinatura de função, `AppState`, `Config`, `Cargo.toml` ou o `setup` frio: `r` no terminal do dx, ou reinicie o `./hot.sh` (rebuild completo).
- Se o patch falhar ou o processo cair depois dele, investigue a causa em vez de voltar ao `cargo run`. Duas causas conhecidas: `std::env::var` na parte quente (`serve`) e `[profile.dev.package."*"] opt-level = 3` no `Cargo.toml` (o patch aplica e o processo cai com "no reactor running").
- A `:8080` é de quem tem a sessão principal; sessões paralelas (worktrees) validam com `cargo test`, não sobem servidor.

### 3. Rust: formatação, lint e testes

```bash
cargo fmt --all --check
cargo clippy -p jopendaw-engine -p jopendaw-engine-wasm -p jopendaw-engine-android -p jopendaw-server --all-targets -- -D warnings
cargo test -p jopendaw-engine                       # motor (o crate tem testes em quase todos os módulos)
cargo test -p jopendaw-engine-android               # ponte nativa: fila, decodificação, captura, render offline
TEST_DATABASE_URL=postgres://jopendaw:jopendaw@localhost:5432/jopendaw_test cargo test -p jopendaw-server
```

Notas:

- Estilo: `rustfmt` com largura 160. O clippy roda com `-D warnings`.
- `cargo test` usa o perfil `test` (`opt-level = 2`, `Cargo.toml`), então os testes de DSP não são lentos como no `dev`.
- **Alocação no caminho de áudio.** `engine/src/testalloc.rs` é um alocador global só de testes que conta as alocações da thread; `fm.rs` e `wavetable.rs` o usam para provar que `render` não aloca (`fm.rs:1187`, `wavetable.rs:1364`). Detalhes em [01-motor.md](01-motor.md).
- **Testes novos da fase 8.** Motor: `loudness.rs` (medidor; inclui a prova de que não aloca, com `testalloc`), `sampler_zones_tests.rs` (zonas e fatiamento; idem) e `expression_tests.rs` (bend, roda de modulação e pedal); todos rodam no `cargo test -p jopendaw-engine`. Ponte Android: `zone_add_cabe_com_os_16_argumentos` em `engine/android/src/call.rs` (o limite de argumentos da fila subiu de 12 para 16 em `6f3d245`). App: `loudness_test.dart`, `export_loudness_test.dart`, `project_file_test.dart` (o `.jopendaw`), `sampler_zones_test.dart`, `expression_test.dart` e `piano_roll_cc_test.dart`. Esses testes passam sem os binários novos do motor (o app usa o motor falso), então **teste verde não prova que o `engine.wasm` e os `.so` commitados conhecem as chamadas novas**: veja a armadilha "Binários do motor atrás do código".
- **Servidor.** Sem `TEST_DATABASE_URL` cada teste de rota se declara pulado e passa; então "passou" sem a variável não prova nada sobre rotas. O banco tem de ser à parte (`jopendaw_test`), nunca o de desenvolvimento: os testes criam contas e tarefas.

  ```bash
  docker exec jopendaw-pg psql -U jopendaw -d postgres -c "CREATE DATABASE jopendaw_test"
  docker exec -i jopendaw-pg psql -U jopendaw -d jopendaw_test < server/schema.sql
  ```

  Para rodar os mesmos testes contra o S3: acrescente `S3_ENDPOINT=http://localhost:9000 S3_BUCKET=jopendaw S3_ACCESS_KEY=jopendaw S3_SECRET_KEY=jopendaw-minio-dev` ao ambiente (`server/src/routes/tests.rs`, cabeçalho). Há também testes unitários em `audio.rs` (WAV, FLAC, YIN), `oauth.rs` e `storage.rs`, que não dependem de banco.
- O `hot` é uma feature do `jopendaw-server` (`--features hot`); os checks acima rodam sem ela.

### 4. Compilar os binários do motor (e commitá-los juntos)

```bash
./engine/build-web.sh                                    # → app/web/engine/engine.wasm
ANDROID_NDK_HOME=~/Library/Android/sdk/ndk/28.2.13676358 ./engine/build-android.sh
                                                         # → app/android/app/src/main/jniLibs/{arm64-v8a,armeabi-v7a,x86_64}/libjopendaw_engine.so
```

- `build-web.sh` roda `cargo build -p jopendaw-engine-wasm --target wasm32-unknown-unknown --profile wasm` e copia para `app/web/engine/engine.wasm`. O `rust-toolchain.toml` não lista alvos: o `wasm32-unknown-unknown` precisa estar instalado (`rustup target add wasm32-unknown-unknown`).
- `build-android.sh` precisa do `cargo-ndk` (`cargo install cargo-ndk`), dos alvos `aarch64-linux-android`, `armv7-linux-androideabi`, `x86_64-linux-android` e do NDK (variável `ANDROID_NDK_HOME`, ou o NDK 28.2.13676358 / o mais novo em `$ANDROID_HOME/ndk`, padrão do Android Studio no Mac). Compila com `-P 24`, perfil `android`.
- Depois de compilar o script **confere** que cada `.so` exporta todos os `jd_*` da lista `want` e que nenhum depende de `libaaudio.so` (não existe no Android 7; o motor a abre por `dlopen`). Falta de símbolo aborta com `faltou <função> em <.so>`.
- **Regra:** mudou algo em `engine/`, rode os dois scripts e commite `engine.wasm` e os três `.so` **no mesmo commit**. Sem recompilar os `.so`, o Android fica com o motor antigo (e mudo, se o `apply` for novo). Os binários nunca vêm de sessões em worktree: quem integra recompila. O contexto completo está em [02-pontes-web-e-android.md](02-pontes-web-e-android.md).

### 5. Flutter: análise, testes e builds

```bash
cd app
flutter analyze
flutter test 2>&1 | tr '\r' '\n' | grep -E "All tests passed|Some tests failed|\[E\]"
dart format -l 160 lib test integration_test              # estilo do projeto (largura 160)
flutter build web --release                               # → app/build/web (servido pelo :8080)
flutter build apk --release -PdiscordClientId=<id>        # → app/build/app/outputs/flutter-apk/app-release.apk
flutter build apk --debug --dart-define=API_BASE=http://10.0.2.2:8080   # APK de teste apontando para o servidor do Mac
```

- O `flutter test` é barulhento; o filtro acima deixa só o veredito e as falhas.
- `analysis_options.yaml` usa `flutter_lints` e exclui `build/**`, `web/**`, `android/**`. Não há `formatter:` configurado ali; a largura 160 é convenção do projeto (`dart format -l 160`).
- Os testes de unidade usam um motor falso (`app/test/fake_engine.dart`) e um cliente de sincronização falso (`fake_sync_api.dart`). Alguns pontos:
  - `engine_native_test.dart` compila `test/native/fake_engine.c` com o `cc` do sistema para conferir a fronteira do `dart:ffi` no computador (ponteiros, cópias, memória, isolates, polling); sem compilador esses testes são pulados.
  - `engine_ffi_test.dart` confere o plano de render contra o `render-worker.js` pelo `node` quando há `node` (senão pula, `skip: 'sem node para rodar o render-worker.js'`).
  - Testes de contrato garantem que as tabelas do Dart batem com o motor (`effects_contract_test.dart`; os testes Rust dos instrumentos leem `instruments.dart`).
- **Testar no navegador, não só na VM do Dart.** `flutter test` roda na VM do Dart, onde o `int` tem 64 bits; no navegador (dart2js) o `int` é um número de JavaScript e os operadores de bit (`<<`, `>>`, `&`, `|`, `^`, `~`) valem 32 bits. Por isso a VM não pega bugs como o do `606664f` (`1 << 62` virava 0 na web e o `Fatiar sample…` nunca achava cortes; ver a armadilha em [10 App Flutter](10-app-flutter.md#armadilhas-conhecidas)). Para a lógica numérica (fatiamento, limites, conversões de bytes, máscaras), rode também no Chrome:

  ```bash
  cd app
  flutter test --platform chrome test/sampler_zones_test.dart
  ```

  O comando existe e funciona neste projeto (Flutter 3.47.2, Google Chrome instalado; o Flutter abre um Chrome próprio, sem relação com o de depuração da 9222). Ele compila os testes com o compilador de desenvolvimento (DDC), não com o dart2js do `build web --release`, mas a aritmética de inteiros é a mesma; nada substitui o teste de uso no build de release. Conferido em 2026-09-30, arquivo por arquivo (`flutter test --platform chrome test/<arquivo>`), **a suíte inteira não roda no Chrome**:
  - **Passam no Chrome:** `automation_math_test`, `export_loudness_test`, `export_test`, `keyboard_test`, `loudness_test`, `midi_tools_test`, `notes_test`, `recording_test`, `sync_test`, `templates_test`, `warp_test`, `wav_test`, `wavetable_shape_test`.
  - **Não compilam para a web** (usam `dart:ffi` por `engine_ffi.dart`, ou `AudioEngine.instance.log`/`e.log`, que só existe no motor falso do lado `dart:io`): `automation_lane_test`, `controller_test`, `effects_contract_test`, `effects_controller_test`, `engine_ffi_test`, `engine_native_test`, `expression_test`, `fm_wavetable_test`, `live_value_test`, `local_store_test`, `overlap_test`, `recording_ui_test`, `reorder_test`, `structure_test`, `studio_test`.
  - **Compilam e falham:** `sampler_zones_test` (28 passam, 1 falha: `documento sem zonas fica byte a byte como antes` compara o JSON como texto, e no navegador o `jsonDecode` reordena as chaves numéricas de `params`, então `"0","7","6",...` vira `"0","1","2",...`; a falha é da comparação de texto, não do app), `project_file_test` (33 passam, 3 falham, pela mesma ordem de chaves), `piano_roll_test` e `rack_test` (`Unsupported operation: Platform._environment` no `setUpAll`), `piano_roll_cc_test` (1 passa, 10 falham) e `piano_roll_tools_test` (4 passam, 17 falham), ambos com `variant: TargetPlatform.macOS`, causa não investigada `(não confirmado)`.
  - **Só roda na VM por natureza:** `web_int_safety_test` lê `app/lib/` com `dart:io` (`Unsupported operation: _Namespace` no Chrome); ele é justamente o teste que compensa a VM.

  Na prática: ao mexer em lógica numérica pura (`sampler_zones.dart`, `wav.dart`, `loudness.dart`, `midi_tools.dart`, `project_file.dart`), rode o arquivo de teste correspondente com `--platform chrome` se ele estiver na lista dos que rodam ou compilam; se o arquivo não roda no Chrome, escreva o caso numérico num teste pequeno sem `dart:io`, `dart:ffi` nem motor falso (como `automation_math_test`), para poder rodá-lo nos dois lados. Tornar a suíte toda verde no Chrome não foi feito.
- Versão do Flutter: o `app/Dockerfile` fixa `FLUTTER_VERSION=3.47.4`; a máquina local tem 3.47.2 (no dia desta escrita). O `pubspec.yaml` pede `sdk: ^3.13.2`.
- O nome do pacote para importar nos testes é `jopendaw_app`.
- `flutter build web --release` não é obrigatório para o servidor de desenvolvimento subir, mas sem ele a API não publica frontend algum (`JOPENDAW_STATIC` inexistente).

### 6. Testes de integração no emulador (motor nativo de verdade)

```bash
~/Library/Android/sdk/emulator/emulator -avd Galaxy_S24_Plus_API36 -no-snapshot-save -no-audio &
~/Library/Android/sdk/platform-tools/adb wait-for-device
adb shell getprop sys.boot_completed                      # repetir até devolver 1
cd app && flutter test integration_test -d emulator-5554                   # os dois arquivos
cd app && flutter test integration_test/engine_test.dart -d emulator-5554  # só o motor
cd app && flutter test integration_test/platform_test.dart -d emulator-5554
```

- `engine_test.dart`: sobe a saída, toca um projeto pelo controlador e confere pelos picos que o som sai; decodifica, renderiza offline, registra notas ao vivo e guarda arquivos. Se os `.so` não estiverem em `jniLibs/`, o primeiro teste falha dizendo isso.
- `platform_test.dart`: a ponte `MainActivity.kt` ↔ `platform_native.dart` (tela acesa, permissão do microfone, avisos de áudio). Não depende do motor.
- O AVD de referência é `Galaxy_S24_Plus_API36` (arm64, API 36); o `-no-audio` evita usar a saída do Mac.
- `SIGABRT` do Bluetooth no logcat do emulador é ruído.

### 7. A armadilha do APK velho (leia antes de instalar)

**Não rode `flutter build apk` dentro de um subshell em segundo plano** (por exemplo `( flutter build ... ) &` dentro de um comando que já roda em segundo plano). A notificação de "concluído" chega quando o shell **externo** sai, não quando o build termina; quem instala nessa hora instala o APK do build anterior. Já aconteceu (30/09/2026): o app velho continuou regravando `fm`/`wavetable` como `audio` no documento local.

Como fazer certo:

1. Rode o build **direto** com o mecanismo de segundo plano da ferramenta (sem `( ... ) &`), ou em primeiro plano, e espere o comando terminar de verdade.
2. Confira o artefato antes de instalar:

   ```bash
   cd app/build/app/outputs/flutter-apk
   ls -l app-debug.apk                     # o horário tem de ser de agora
   shasum -a 1 app-debug.apk; cat app-debug.apk.sha1   # o Flutter grava o .sha1; os dois têm de bater
   ```
3. Instale e confirme que **o que está no aparelho** é o APK novo:

   ```bash
   adb install -r app/build/app/outputs/flutter-apk/app-debug.apk
   adb shell pm path tech.johnenrique.jopendaw            # caminho do APK instalado
   adb pull <caminho impresso acima> /tmp/instalado.apk && shasum -a 1 /tmp/instalado.apk
   adb shell dumpsys package tech.johnenrique.jopendaw | grep -E "lastUpdateTime|versionName"
   ```

   O `sha1` do instalado deve igualar o do APK gerado (não confirmado que sempre iguala: o `pm path` pode listar mais de um `.apk` em instalações divididas). Se o app mostra um comportamento que o código atual já não tem, suspeite do APK antes de suspeitar do código.

Também vale lembrar: o release sem `android/key.properties` (ou `~/.config/jopendaw/android-release.properties`) sai assinado com a chave de **debug**: serve para testar, mas não abre os links dos emails (o `assetlinks.json` só confia na chave de release). `minSdk` do app é `max(flutter.minSdkVersion, 26)` (`app/android/app/build.gradle.kts`), porque o AAudio chegou no Android 8.

### 8. Testar o app no Chrome (o Chrome de depuração na 9222)

O Flutter desenha em canvas: o MCP `chrome-devtools` serve para screenshot, console, JS e emulação de aparelho, mas não clica em coordenadas. Cliques, arrastes, teclas com modificador e a leitura do `probe` vão por `node tool/cdp.mjs`, que fala CDP com o Chrome da 9222 (perfil `~/.chrome-devtools-profile`).

Se a 9222 não responder (`curl -s --max-time 3 http://127.0.0.1:9222/json/version`), abra o Chrome de depuração:

```bash
open -na "Google Chrome" --args --remote-debugging-port=9222 --remote-allow-origins='*' --user-data-dir="$HOME/.chrome-devtools-profile"
```

Comandos do `tool/cdp.mjs` (`node tool/cdp.mjs <comando> [args]`):

| Comando | O que faz |
|---|---|
| `tabs` | lista as abas (id, url, título). |
| `open <url>` | abre aba nova e imprime o id. |
| `close <tabId>` | fecha a aba. |
| `eval <tabId> <js>` | avalia JS (aceita `await`), imprime o resultado em JSON. |
| `shot <tabId> <arquivo.png> [largura altura]` | screenshot; com largura/altura emula o viewport. |
| `click <tabId> x y`, `dblclick`, `drag <tabId> x1 y1 x2 y2` | mouse real (pixels CSS). |
| `key <tabId> <tecla> [mods]` | tecla real. `mods`: 1 alt, 2 ctrl, 4 meta (Cmd), 8 shift (somam-se). |
| `type <tabId> <texto>` | insere texto. |
| `reset <tabId>` | tira a emulação de viewport. |
| `grant <origin> <permissão...>` | concede permissões do navegador (ex.: `audioCapture midi midiSysex`) e **fica rodando**: o Chrome desfaz a concessão quando a sessão CDP que a fez fecha. Rode em segundo plano durante o teste e encerre no fim. |
| `run <tabId> passos.json [largura altura]` | vários passos numa sessão (com largura/altura emula o aparelho; sem elas limpa a emulação). |

Passos de `run` (cada um é uma lista JSON, com 120 ms de pausa depois de cada um): `["click",x,y]`, `["dbl",x,y]`, `["rclick",x,y]`, `["down",x,y]`, `["move",x,y]`, `["up",x,y]`, `["hover",x,y]`, `["drag",x1,y1,x2,y2]`, `["wheel",x,y,dx,dy,mods]`, `["type","texto"]`, `["key","a",mods]`, `["keydown","a"]`, `["keyup","a"]`, `["wait",ms]`, `["shot","f.png"]`, `["eval","js"]`, `["probe"]`, `["file","nome.wav",...]`. Toque longo + arrasto: `down`, `wait 700`, vários `move`, `up`. Erros e avisos do console aparecem no fim da execução (`ERROS DO CONSOLE`).

Detalhes que importam:

- **`probe`**: lê `jopendawEngine.probe()` (ver a próxima seção) e imprime. É como se prova que o som sai sem ouvir.
- **`file`**: o próximo seletor de arquivos do app recebe esses arquivos, servidos da raiz do site (`/nome.wav`), então o arquivo de teste tem de estar em `app/build/web/`. O passo sobrescreve `HTMLInputElement.prototype.click` uma vez. O `Cmd+I` de importar não chega ao Flutter; clique o botão de importar.
- **Ativos de teste** ficam em `app/build/web/` (fora do git: `tempo*.wav`, `pad.wav`, `noise.wav`, `seno1k.wav`, `acorde.wav`, `bumbo.wav`, `loop-teste.wav`). Depois de um `flutter build web` confira se ainda estão lá (não confirmado se o build os preserva).
- **Emulação de viewport fica presa na aba.** Para voltar ao desktop feche a aba e abra outra (`reset` tira a emulação, mas o hábito seguro é abrir aba nova).
- **Permissões** (microfone, MIDI): rode `node tool/cdp.mjs grant http://localhost:8080 audioCapture midi midiSysex &` antes; o Web MIDI só libera com `midiSysex` junto, e sem a concessão aparece o aviso de permissão que trava a automação.
- Microfone falso, sem abrir o prompt do macOS: sobrescreva `navigator.mediaDevices.getUserMedia` (via `eval`) devolvendo um oscilador.
- Com o MCP `chrome-devtools`, prefira `evaluate_script` como sonda barata (com `waitForStableDom: false` em leituras) e screenshot só quando o visual importa; ele não clica em coordenadas.
- Uma alternativa aprovada para testes de navegador é o Claude in Chrome (o Chrome do Mac): `tabs_context_mcp` → criar aba própria → `navigate`/`computer`/`javascript_tool`, fechando a aba ao fim. O `tool/cdp.mjs` segue útil para clique por coordenada, tecla com modificador e leitura do probe.

### 9. `jopendawEngine`: probe e MIDI injetado

`app/web/engine/host.js` publica `window.jopendawEngine` (só na web). Para depuração:

| Chamada | O que devolve / faz |
|---|---|
| `jopendawEngine.probe()` | `{ beat, playing, context, peaks, fxMeter, spectrum?, input? }`. `peaks` = pico (0–1, arredondado a 3 casas) de cada canal desde a leitura anterior: esquerdo e direito de cada faixa, **master por último**. `context` = estado do `AudioContext` (`running`, `suspended`, ...; `none` se ainda não iniciou). `fxMeter` = maior redução de ganho (dB) do efeito observado. `spectrum` só com o analisador ligado (`bins`, `peakBin`, `peakDb`); `input` só com a entrada aberta. **Ler zera** os picos, `fxMeter` e `input`. |
| `jopendawEngine.injectMidi(status, d1, d2)` | injeta uma mensagem MIDI pelo mesmo caminho de um aparelho (ex.: nota ligada no canal 1: `injectMidi(0x90, 60, 100)`; desligada: `injectMidi(0x80, 60, 0)`). Testa sem hardware. |
| `jopendawEngine.latency()` | latência base + de saída do `AudioContext`, em segundos. |
| `jopendawEngine.idbGet/idbPut/idbDelete` | o guardado local (IndexedDB), útil para inspecionar `doc:<id>`, `sync:<id>`, `sample:<hash>`. |

Padrão de uso: tocar por 1 s, `probe`, e conferir `peaks` do master (último valor) > 0. Pico zero em tudo com `context: "suspended"` costuma ser o `AudioContext` aguardando um gesto do usuário.

### 10. Cache: service worker e arquivos sem hash

O build do Flutter **não põe hash** no nome dos arquivos (`main.dart.js`, `engine/host.js`, `engine/engine.wasm`). Por isso:

- O servidor de desenvolvimento manda `Cache-Control: no-cache` onde a resposta não define o seu (`server/src/main.rs`), e o nginx de produção usa `expires -1` para `js/wasm/json/...` (`app/nginx.conf.template`). A API manda `no-store`, e os áudios por hash, `immutable`.
- `app/web/sw.js` (cache `jopendaw-app-v1`) vai **primeiro à rede** para tudo da mesma origem, menos `/api/`, e só cai no cache sem rede. O `flutter_bootstrap.js` não registra o service worker do Flutter (descontinuado); registra `/sw.js`.
- Mesmo assim, no Chrome de teste, depois de um rebuild o navegador pode manter host/wasm/`main.dart.js` velhos (sintoma clássico: `detectBpm is not a function`, chamada nova do motor sem efeito, comportamento antigo). Limpeza completa, por `eval` na aba (ou `javascript_tool`):

  ```js
  (async () => {
    for (const r of await navigator.serviceWorker.getRegistrations()) await r.unregister();
    for (const k of await caches.keys()) await caches.delete(k);
    for (const u of ['/engine/host.js', '/engine/engine.wasm', '/engine/worklet.js', '/engine/render-worker.js', '/main.dart.js']) await fetch(u, { cache: 'reload' });
  })()
  ```

  Depois recarregue a página.
- No Android o equivalente do "motor velho" é o `.so` velho no APK (item 7).

### 11. Login de teste

O servidor tem um **código de acesso** para a revisão da Play Store, também usado nos testes de uso: `REVIEW_EMAIL` e `REVIEW_CODE` do `server/.env` (código com 24+ caracteres; os dois ou nenhum; `server/src/config.rs`). Na tela de login, o link "Tenho um código de acesso" leva ao formulário. O email de teste usado é `demo@jopendaw.local`. Não repita o código em relatórios, mensagens de commit ou documentação.

Sem o par `GOOGLE_*`/`DISCORD_*` os botões sociais não aparecem, e o magic link só chega se o `jmail` (repo irmão, `JMAIL_URL`, padrão `http://127.0.0.1:8790`) estiver rodando com a chave do app `jopendaw`.

Sessão de teste no Android: `adb shell pm clear tech.johnenrique.jopendaw` simula aparelho novo (apaga sessão e guardado local).

### 12. Android: comandos `adb` úteis

O `adb` fica em `~/Library/Android/sdk/platform-tools/adb` (nos exemplos abaixo ele está no `PATH`).

```bash
adb devices                                                   # emulator-5554 quando o AVD está de pé
adb install -r app/build/app/outputs/flutter-apk/app-debug.apk
adb shell monkey -p tech.johnenrique.jopendaw -c android.intent.category.LAUNCHER 1   # abre o app
adb shell am force-stop tech.johnenrique.jopendaw
adb shell pm clear tech.johnenrique.jopendaw                  # aparelho "novo": sem sessão, sem projetos locais
adb exec-out screencap -p > /tmp/tela.png                     # screenshot (tela do AVD: 1440x3120)
adb shell input tap X Y                                       # toque (coordenada = imagem exibida × 1,56)
adb logcat -s flutter                                         # logs do Dart (print/debugPrint)
adb logcat | grep -i jopendaw                                 # logs em geral filtrados
adb shell dumpsys package tech.johnenrique.jopendaw | grep -E "lastUpdateTime|versionName"
```

- **Servidor local a partir do emulador:** `10.0.2.2` é o Mac. Construa o APK com `--dart-define=API_BASE=http://10.0.2.2:8080`. Sem isso o app Android fala com a produção (`https://jopendaw.johnenrique.tech`, `app/lib/api/client.dart`).
- **Guardado local no Android** (debug): arquivos em `<documentos do app>/jopendaw/`, nome da chave com `%XX` nos caracteres não seguros: `doc%3A<id>.txt`, `sync%3A<id>.txt`, `sample%3A<hash>.bin` (`FileStore.fileName`, `app/lib/audio/engine_io.dart`). Para forçar o app a baixar de novo um projeto do servidor (debug, via `run-as`):

  ```bash
  adb shell run-as tech.johnenrique.jopendaw rm ./app_flutter/jopendaw/doc%3A<id>.txt ./app_flutter/jopendaw/sync%3A<id>.txt
  ```

  (O `app_flutter` é o diretório de documentos padrão do plugin `path_provider` em debug; não confirmado neste repositório além do uso nas anotações.)
- **Conflito de sincronização "legítimo":** duas abas do Chrome, ou Chrome e Android, mexendo no mesmo projeto geram o diálogo "mudou em outro aparelho". É o comportamento esperado, não um bug.
- Ao testar sincronização Chrome ↔ Android, a ordem importa: espere o indicador de nuvem ficar em "sincronizado" antes de abrir o outro lado.

## Contratos

### Portas e serviços de desenvolvimento

| Porta | Quem |
|---|---|
| 5432 | Postgres do compose (`jopendaw-pg`; usuário, senha e banco `jopendaw`). |
| 8080 | API (e o build web do Flutter, se existir). |
| 8090 | devserver do `dx` (`hot.sh`, `DX_PORT`). |
| 8081 | `web` (nginx) do `docker-compose up --build`. |
| 9000, 9001 | MinIO (API e console). |
| 9222 | Chrome de depuração (CDP). |

### Comandos "de bolso" da fase

Antes de declarar pronto:

```bash
cargo fmt --all --check
cargo clippy -p jopendaw-engine -p jopendaw-engine-wasm -p jopendaw-engine-android -p jopendaw-server --all-targets -- -D warnings
cargo test -p jopendaw-engine -p jopendaw-engine-android
TEST_DATABASE_URL=... cargo test -p jopendaw-server
(cd app && flutter analyze && flutter test)
./engine/build-web.sh && ./engine/build-android.sh          # se mexeu em engine/
(cd app && flutter build web --release)                     # então: uso real no Chrome
docker-compose up --build                                   # (opcional) imagens da api e da web; API em :8080, nginx em :8081
(cd app && flutter build apk --debug --dart-define=API_BASE=http://10.0.2.2:8080)   # então: emulador
```

## Decisões e por quê

- **`./hot.sh` no lugar de `cargo run`.** Editar e ver o efeito em ~1 s mantém o ciclo curto; o custo é seguir as regras do hot-patch (nada de `env::var` na parte quente, rebuild completo em mudança de tipo).
- **Teste de uso como critério de pronto.** O app desenha em canvas e o áudio é temporal; teste automático de widget não pega "não soa", "arrasta errado" ou "cache velho". O `probe` existe para provar som sem ouvir.
- **`tool/cdp.mjs` em vez de só o MCP.** O MCP não clica em coordenadas; o cliente CDP de ~185 linhas, sem dependências, faz cliques reais com `buttons` coerentes (sem isso o Flutter perde cliques em alvos que também aceitam arrastar), modificadores como teclas de verdade (o Flutter acompanha o estado pelo `keydown` deles) e screenshot em pixels CSS.
- **Binários do motor commitados.** `flutter build` e o Docker do app não precisam de Rust nem do NDK; a contrapartida é a regra de commitar tudo junto e a conferência de símbolos do `build-android.sh`.
- **Banco de teste separado e testes que se pulam.** O `cargo test` segue valendo em máquina sem Postgres; em troca, é preciso lembrar de passar `TEST_DATABASE_URL` quando se mexe no servidor.

## Como testar

Este capítulo é o "como testar". Um roteiro mínimo para uma mudança típica:

1. Mudou só Dart: `flutter analyze`, `flutter test`, `flutter build web --release`, subir `./hot.sh`, testar no Chrome (`tool/cdp.mjs`), e, se tem reflexo no Android, `flutter build apk --debug ...` + emulador.
2. Mudou o motor: `cargo test -p jopendaw-engine`, os dois scripts de build, os dois builds do app, `probe` no Chrome, `flutter test integration_test -d emulator-5554`.
3. Mudou o servidor: `cargo test -p jopendaw-server` com `TEST_DATABASE_URL`, e conferir no `./hot.sh` (log `Hot-patching`). Se mudou o schema: `schema.sql` + script idempotente em `db/migrations/` e rodar o script no banco local.

## Armadilhas conhecidas

- APK velho por build em subshell em segundo plano (item 7).
- Cache do service worker e de arquivos sem hash depois de rebuild (item 10).
- `flutter run -d chrome` sobe em `localhost:<porta aleatória>`; o `ApiClient` só usa a mesma origem na porta 8080 ou em host que não seja `localhost` (`client.dart:38-41`), então nesse modo o app fala com a **produção**. Para desenvolver contra a API local, sirva o build pela `:8080` ou passe `--dart-define=API_BASE=http://localhost:8080`.
- `cargo test` do servidor "passa" sem `TEST_DATABASE_URL` porque se pula (item 3).
- Nenhum dos `.so`/`engine.wasm` vem de agentes em worktree: recompile no main.
- O `grant` do `cdp.mjs` só vale enquanto o processo roda; se ele terminar, a permissão some e o aviso do navegador volta a travar a automação.
- `sleep` longo em primeiro plano é bloqueado no ambiente do agente; use `until curl ...; do sleep 3; done`.
- Duas abas no mesmo projeto: conflito de sincronização legítimo.
- Bug que só existe no navegador (operador de bit de 32 bits do dart2js, `int` além de 2^53) não aparece em `flutter test`, que roda na VM de 64 bits: rode a lógica numérica com `flutter test --platform chrome` (ver o item 5) e confirme no build web no Chrome.
- O motor só roda no navegador e no Android: `flutter test` no computador usa motor falso (e `AudioEngine.supported` é falso fora desses dois).
- **Binários do motor atrás do código.** Caso real da fase 8, resolvido em `357b6fc`: `dca27bc`, `b6b7abb`, `6f3d245` e `b7e802e` mexeram em `engine/` sem recompilar `engine.wasm` nem os `.so` (última recompilação antes disso: `f1cfbaa`, fase 7; conferido com `git log`), e só o commit de integração `357b6fc` recompilou os quatro binários e ampliou a lista `want` do `build-android.sh` (`jd_loudness`, `jd_stretch`, `jd_detect_bpm`). O `build-android.sh` confere os símbolos `jd_*` exportados, mas nenhum passo confere que o `.wasm` commitado está em dia com o código do motor: depois de mexer em `engine/`, confira com `git log -1 -- app/web/engine/engine.wasm` contra `git log -1 -- engine/src`.
- **Build da imagem Docker da API.** Resolvido em `0c0593e`: o `server/Dockerfile` copiava só os manifestos do servidor e o cargo não carregava o workspace (faltavam os membros `engine`, `engine/wasm`, `engine/android`). Se um membro novo entrar em `Cargo.toml`, copie-o no Dockerfile também.
- **Upload grande pelo nginx.** Resolvido em `0c0593e`: o padrão de 1 MB do nginx cortaria `PUT` de áudio e de documento acima disso; o `location /api/` agora aceita 600 MB. Quem testa upload contra o compose deve usar a porta 8081 (nginx), não a 8080: a 8080 (API direta) nunca teve esse limite.
- Detecção de BPM: exata em 75–140 BPM; nos extremos erra por oitava (65 vira 130, 170 vira 85, 190 vira 95; o diálogo tem ÷2/×2). Ao testar com os `tempo*.wav`, é o resultado esperado.
- Ferramentas MIDI e marcadores foram testadas de forma parcial no Chrome até a fase 7; ao dar uma fase por pronta, cubra os casos longos, extremos e negativos, e os dois lados (Chrome e Android).
