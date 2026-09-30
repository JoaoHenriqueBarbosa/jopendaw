# Expressão MIDI: pitch bend, modulação e sustain

> Como o pitch bend, a roda de modulação (CC 1) e o pedal de sustain (CC 64) andam do controlador, das rodas da tela e dos pontos do clipe até o instrumento, e de volta para o clipe na gravação; para quem mexe no motor (`engine/src/expression.rs`), na ponte (`worklet.js`, `engine_ffi.dart`) ou no app (`midi_cc.dart`, `piano_roll_cc.dart`). O uso está em [Piano roll](../manual/05-piano-roll.md#faixa-de-controle), [Gravação](../manual/03c-gravacao.md) e [Painel de instrumento](../manual/04-painel-de-instrumento.md#rodas-de-pitch-bend-e-de-modulação).

Citações `arquivo:linha` valem para o estado do repositório depois do commit `357b6fc` (2026-09-30); as linhas andam, os nomes não. O que só foi lido no código (não rodado ao escrever este capítulo) vem marcado `(não confirmado)`. Os comandos de teste abaixo também **não foram executados** ao escrever.

## Visão geral

Três controles, todos **normalizados** e com id do MIDI, mais o 128 para o bend (que no MIDI não é um CC):

| Controle | Id (`cc`) | Valor | Repouso |
|---|---|---|---|
| Modulação (roda) | `1` | 0 a 1 (CC/127) | 0 |
| Pedal de sustain | `64` | 0 a 1; embaixo a partir de 0,5 (o 64/127 do MIDI dá 0,504 e conta como embaixo, 63/127 não) | 0 (solto) |
| Pitch bend | `128` | -1 a 1 (14 bits do MIDI menos 8192, sobre 8192) | 0 (centro) |

```
 controlador MIDI (0xE0, CC 1, CC 64)   rodas do teclado da tela      piano roll: faixa de controle
        │ DawController._onMidi                │ ExpressionWheel                │
        └────────────►  DawController.liveControl  ◄─────────────┘              │ edita MidiClip.controls
                        (bend/roda/pedal, por faixa)                             │ (JSON: "cc")
                                │ live_bend / live_cc                            ▼ flattenControls (midi_cc.dart)
                                ▼                                                cc_clear + cc_add (batidas absolutas)
                     Engine::live_cc ──► NoteRecorder::cc  (só tocando)                  │
                                │                                                        ▼
                                ▼                                                  Lane.cc (ordenado)
                     Lane.expr (ExprState) ◄────────── Lane::render, no quadro exato, antes das notas
                        │  pedal: note_off pendente
                        │  bend / roda:
                        ▼
              Instrument::set_pitch_bend / set_mod_wheel ──► PitchExpr (sintetizador, FM, wavetable, sampler)
```

Duas ideias organizam tudo:

1. **O pedal mora na camada da faixa** (`ExprState`), não nos instrumentos: com o pedal embaixo o `note_off` não chega ao instrumento e a altura fica pendente; ao subir, todos os `note_off` pendentes saem juntos. Os instrumentos só conhecem `set_pitch_bend` e `set_mod_wheel`.
2. **Ao vivo e sequenciado são o mesmo estado.** Um valor que vem de `live_cc` e um que vem de um evento do clipe passam por `ExprState::set`. Por isso o pedal segura tanto a nota tocada no teclado quanto a nota do clipe.

## Peças e responsabilidades

### Motor (`engine/`)

| Arquivo | Papel |
|---|---|
| `engine/src/expression.rs` | Tudo de expressão: constantes, `PitchExpr` (bend + vibrato para os instrumentos), `ExprState` (estado por faixa, pedal), `CcEvent`, `clamp_cc`, os `impl Lane` (`sort_cc`, `cue_cc`, `stop_cc`, `panic_cc`, `live_cc`) e os `impl Engine` (`live_cc`, `live_bend`, `add_cc`, `clear_cc`) |
| `engine/src/expression_tests.rs` | 1062 linhas de testes (módulo `tests` de `expression.rs` via `#[path]`) |
| `engine/src/lib.rs` | `Lane` ganhou `cc`, `cc_cursor`, `cc_seq`, `expr` (`:267`); `Lane::render` (`:309`) dispara os controles antes das notas; `Lane::cue` (`:297`) reposiciona o cursor dos eventos; ganchos em parar (`:730`), trocar o tipo da faixa (`:866`), pânico (`:989`), reordenação (`:1603`), reposicionamento (`:1611`) e volta do loop (`:1623`) |
| `engine/src/instrument.rs` | Trait `Instrument`: `set_pitch_bend` e `set_mod_wheel` (com implementação vazia por padrão, que é o que a bateria usa); ids novos `synth_param::BEND_RANGE` 35 e `VIBRATO_RANGE` 36, `fm_param` 42 e 43, `wavetable_param` 39 e 40, `sampler_param::BEND_RANGE` 9 |
| `engine/src/synth.rs`, `fm.rs`, `wavetable.rs`, `sampler.rs` | Cada um tem um `PitchExpr` e soma o desvio (semitons) na afinação, por bloco de controle |
| `engine/src/record.rs` | `NoteRecorder::cc`, cota `MAX_REC_CCS` (32.768) à parte de `MAX_REC_NOTES` (16.384), código de leitura `CC_PITCH_BASE` (256) |
| `engine/src/api.rs` | Tabela `CALLS` (`:211`-`:214`), enum `Call::{LiveBend, LiveCc, CcAdd, CcClear}` e o despacho |
| `engine/wasm/src/lib.rs` | Exports C `live_bend`, `live_cc`, `cc_add`, `cc_clear` |
| `engine/android/src/{lib,core}.rs` | Sem função `jd_*` nova: as chamadas entram por `engine::api::apply` (o mesmo despacho por nome do worklet); `REC_NOTES_MAX` cresceu para `5 * (MAX_REC_NOTES + MAX_REC_CCS)` floats |

### App (`app/`)

| Arquivo | Papel |
|---|---|
| `app/lib/daw/model.dart:127` | `ccMod` (1), `ccSustain` (64), `ccBend` (128), `ccKinds` (ordem das faixas de controle: bend, modulação, pedal), `MidiCc` (`cc`, `beat`, `value`, `clampValue`) e `MidiClip.controls` |
| `app/lib/daw/midi_cc.dart` | Funções puras: `flattenControls`, `controlValueAt`, `splitControls`, `shiftControls`, `scaleControls`, `mirrorControls`, `thinControls`, `closePedal`, `drawControlLine`, `sameControls`, `pedalDown`, `recordedControlGap` |
| `app/lib/daw/controller.dart` | `liveControl`/`pitchBend`/`modWheel` (`:2252`), `_onMidi` (`:2443`), `_releaseControls`, `_sync` (envio de `cc_clear`/`cc_add`, `:1016`), `splitMidiClip` (`:161`), `placeOnTop` (`:1849`), gravação: `_recordedControls` (`:3651`), `_mergeControls` (`:3690`), `_placeRecordedNotes` (`:3728`) |
| `app/lib/daw/expression_wheels.dart` | As duas rodas do teclado da tela |
| `app/lib/daw/instrument_panel.dart` | Coloca as rodas no cabeçalho e na faixa do teclado (`_wheels`); nada nas faixas de bateria |
| `app/lib/daw/piano_roll_cc.dart` | Faixa de controle sob a grade: menu do canto, `_CcLane` (gestos), `_CcPainter` |
| `app/lib/daw/piano_roll_tools.dart` | `_scaleCc` e `_mirrorCc`: levam os pontos junto de `Escalar o tempo` e `Inverter no tempo`. Nenhum item de menu novo |
| `app/lib/daw/timeline.dart` | Aparar a borda esquerda do clipe desloca os pontos (`_Grab.left`) |
| `app/lib/audio/engine_types.dart` | `ccPitchBase = 256` |
| `app/lib/audio/engine_web.dart`, `engine_ffi.dart` | `parseRecordedNotes` deixa passar alturas de 256 em diante (eventos de controle) sem o `clamp(0, 127)` das notas; `renderSkip` e `prepareRenderCalls` conhecem as chamadas novas |
| `app/web/engine/worklet.js`, `render-worker.js` | Buffer de gravação maior; `EXPRESSION_CALLS`; `SKIP` e `prepareCalls` do render |

## Fluxo de dados / ciclo de vida

### 1. Ao vivo

1. **Origem.** `DawController._onMidi` (todos os canais; o número do canal é ignorado): `0xE0` → `pitchBend(((MSB << 7 | LSB) - 8192) / 8192)`, de -1 a 8191/8192; `CC 1` → `modWheel(valor / 127)`; `CC 64` → `_setSustain(valor >= 64)`; `CC 121` → `_releaseControls()` (bend, roda e pedal ao repouso); `CC 120` → tudo solto, `_ccTrack` limpo e `panic`; `CC 123` → só as notas. As rodas da tela chamam `c.pitchBend(v, track: faixa do painel)` e `c.modWheel(...)`.
2. **`liveControl(cc, valor, {track})`** (`controller.dart:2252`): exige motor pronto, `cc` em `ccKinds`, valor finito e faixa de instrumento; a faixa é `track` ou a de entrada (`_inputTrack`, a mesma regra das notas). Limita o valor, manda `['live_bend', faixa, valor]` (bend) ou `['live_cc', faixa, cc, valor]`. `_ccTrack` (controle → faixa) lembra onde o último valor foi: se a entrada muda de faixa com o controle fora do repouso, a faixa antiga recebe o repouso antes.
3. **Motor.** `Engine::live_cc` (`expression.rs:338`): `clamp_cc` (controle desconhecido ou valor não finito: ignora); faixa inexistente: ignora; **se o transporte está tocando, registra em `recorder.cc(faixa, cc, valor, batida_de_agora)`** (mesmo que a faixa não tenha instrumento); então `Lane::live_cc` → `ExprState::set`.
4. **`ExprState::set`**: bend e modulação só chamam o instrumento se o valor mudou; o pedal só tem efeito se a faixa segura notas (`pedal`: tudo menos a bateria); ao subir, `flush` manda os `note_off` pendentes.
5. **Notas ao vivo** (`live_on`/`live_off`) passam por `Lane::live_note_on`/`live_note_off` (`ExprState::note_on` limpa a pendência da altura; `note_off` fica pendente se o pedal está embaixo).

O pedal deixou de ser tratado no app: antes o `_midiNoteOff` guardava as alturas em `_sustained`; agora o app só manda `live_cc` 64 e o motor segura e grava.

### 2. Reprodução do clipe

1. **Envio.** `_sync` compara `flattenControls(doc.tracks)` com o que o motor tem (`_SyncCache.ccs`, `null` = pode ter lixo) e, se mudou, manda `['cc_clear']` e um `['cc_add', faixa, cc, batida, valor]` por evento (`controller.dart:1016`). Um documento sem controles **nunca** manda `cc_clear` nem `cc_add`; ao reordenar/remover faixas o cache vira `null` só se o motor tinha eventos (`:821`).
2. **`flattenControls`** (`midi_cc.dart:34`): só faixas de instrumento; batida absoluta = `clip.start + batida`; descarta eventos não finitos, antes de 0 ou depois do fim do clipe (guardados, mudos, como as notas); limita o valor; e **devolve ao repouso no fim do clipe** o controle que o último evento deixou fora dele (pedal embaixo, bend ou roda fora do zero), com o evento de retorno ordenado **antes** dos eventos de um clipe que começa na mesma batida (`order 0` contra `order 1`). No mesmo instante vale a ordem da lista.
3. **Motor.** `add_cc` guarda em `Lane.cc` (batida mínima 0; `seq` numera a chegada para desempatar) e marca `notes_dirty`. No início do bloco seguinte, `lib.rs:1603` ordena (`sort_cc`) e `recue` reposiciona (`cue_cc`).
4. **`Lane::render`** (`lib.rs:309`): `next_event` considera também o próximo evento de controle; em cada quadro-evento, **primeiro os controles** (um pedal que desce na batida de uma nota a segura; um que sobe na batida de outra solta as anteriores antes dela), depois os `note_off` que vencem, depois os `note_on`.
5. **Reconstituição do estado** (`cue_cc`, `expression.rs:250`): ao começar a tocar, saltar ou voltar o loop, para cada controle que o clipe usa vale o último evento antes da posição (repouso se não há); o controle que o clipe **não** usa fica com quem o mexeu ao vivo. `driven` (bits: 1 modulação, 2 pedal, 4 bend) lembra o que o clipe dirige.
6. **Parar** (`stop_cc`, `:270`): os controles que o clipe dirigia voltam ao neutro e a pendência do pedal é zerada (o `release_all` já soltou o som). **Pânico** (`panic_cc`): `ExprState::reset`, o "reset all controllers". **Trocar o tipo da faixa** recria o `ExprState` (`lib.rs:866`) e força `recue`.
7. **`cc_clear`** apaga só os eventos de controle (`notes_clear` não os apaga, e vice-versa); com o transporte tocando o estado que eles dirigiam volta ao neutro no bloco seguinte.

### 3. Gravação

1. Com a gravação ligada e o transporte tocando, cada `live_cc` vira um `RecNote` com `cc != 0`: início e fim iguais (a batida de agora), o valor no lugar da velocidade e a cota própria `MAX_REC_CCS`. `rec_notes` (`record.rs`) devolve grupos de 5 floats `[faixa, código, início, fim, valor]`, com `código = 256 + cc` (257 modulação, 320 pedal, 384 bend) em vez da altura; uma altura 0 a 127 continua sendo uma nota. Não há função de leitura nova: a ponte é a mesma `rec_notes`.
2. Ponte: o worklet e o `engine_ffi` reservam `5 * (16384 + 32768)` floats; `parseRecordedNotes` não faz `clamp(0, 127)` em alturas de controle e limita o valor de um evento de controle a -1..1 (o app limita de novo por controle em `_recordedControls`, com `MidiCc.clampValue`).
3. App (`controller.dart:3473`): `_recordedNotes` ignora os códigos de controle; `_recordedControls` (`:3651`) separa os eventos por faixa armada de instrumento, descarta o que veio na contagem (antes do `start`, exceto a volta do loop), e **em loop guarda só a última passada** (a última vez em que a batida recua).
4. `_placeRecordedNotes` põe notas e pontos no clipe sob o cursor (overdub, esticando em compassos inteiros; se estica para a esquerda, os pontos velhos são deslocados junto) ou num clipe novo. Só controles, sem notas: entram no clipe que estava sob o cursor; **sem clipe ali nada é criado**.
5. `_mergeControls` (`:3690`): `thinControls(closePedal(...))` e, por controle, os pontos velhos do mesmo controle no trecho `[primeiro novo, último novo]` são substituídos. `thinControls` (`midi_cc.dart:140`): no máximo um ponto por `recordedControlGap` (1/48 de batida) por controle (o valor mais recente da janela vence), sem repetir o valor anterior, sem o primeiro se só confirma o repouso; o pedal mantém só as mudanças; o último valor sempre fica. `closePedal`: se o pedal terminou embaixo, sobe em `max(último + 1/16, ponto de parada)`.

### 4. Exportação (render fora de tempo real)

`live_bend` e `live_cc` estão em `renderSkip` (`engine_ffi.dart`) e no `SKIP` do `render-worker.js`. `cc_add` passa por `prepareRenderCalls`/`prepareCalls`: antes do fim do trecho vai como está; depois dele **só o pedal que sobe** (`cc 64`, valor < 0,5) fica, movido para o próprio fim (senão as notas cortadas ali ficariam presas por um pedal que o trecho não solta).

## Contratos

### Chamadas da API (`engine::api::apply`, exports do wasm, `jd_calls` no Android)

| Chamada | Argumentos | Efeito |
|---|---|---|
| `live_bend` | `faixa` (usize), `valor` (f32, -1..1) | Igual a `live_cc(faixa, 128, valor)` |
| `live_cc` | `faixa` (usize), `controle` (u32: 1, 64 ou 128), `valor` (f32) | Controle ao vivo. Controle desconhecido, valor não finito e faixa inexistente são ignorados; valor fora da faixa é limitado (modulação e pedal 0..1, bend -1..1). Tocando, entra no registro com a batida de agora |
| `cc_add` | `faixa` (usize), `controle` (u32), `batida` (f64, absoluta), `valor` (f32) | Evento do clipe. Batida < 0 vira 0; batida ou valor não finitos e controle desconhecido são ignorados. A ordem de chegada desempata eventos na mesma batida |
| `cc_clear` | nenhum | Apaga os eventos de controle de todas as faixas e zera o contador de chegada |

Checklist de chamada nova (tabela `CALLS`, wasm, Android, `SKIP`/`renderSkip`, guarda no worklet): [02 Pontes](02-pontes-web-e-android.md). O worklet ignora as quatro chamadas se o `engine.wasm` carregado não as exporta (`EXPRESSION_CALLS`, `worklet.js:35` e `:127`), em vez de derrubar o lote inteiro.

### JSON do clipe (`MidiClip`)

Os pontos ficam em `MidiClip.controls` no Dart, mas a **chave no JSON é `cc`**, e só existe quando a lista não é vazia:

```json
{
  "id": "m1", "name": "Solo", "start": 4.0, "length": 4.0,
  "notes": [ { "pitch": 69, "start": 0.0, "length": 2.0, "velocity": 0.8 } ],
  "cc": [
    { "cc": 128, "beat": 1.5, "value": 0.0 },
    { "cc": 128, "beat": 1.75, "value": 0.5 },
    { "cc": 1,   "beat": 0.0, "value": 0.6 },
    { "cc": 64,  "beat": 0.0, "value": 1.0 },
    { "cc": 64,  "beat": 3.5, "value": 0.0 }
  ]
}
```

- `beat`: batidas contadas do **início do clipe** (como as notas), fora de ordem é aceito (o motor ordena e `thinControls`/desenho mantêm a lista).
- `value`: bend -1..1; modulação 0..1; pedal 0 (solto) ou 1 (embaixo; o motor trata 0,5 ou mais como embaixo).
- **Compatibilidade:** documento sem controles gera exatamente o mesmo JSON de antes (teste `documento sem controles: o JSON do clipe não ganha campo nenhum`); documento antigo, sem `cc`, abre com a lista vazia e reescreve idêntico (teste `documento antigo...`). Um `cc` com id fora de 1/64/128 é lido, mas `flattenControls` só manda os três conhecidos. Versões antigas do app não conhecem a chave e, ao salvar, a **descartam** (o `fromJson` delas a ignora) (não confirmado; vale para qualquer campo novo do documento).
- A sincronização com o servidor trata o documento como JSON opaco: nenhuma rota ou schema mudou.

### Parâmetros dos instrumentos

| Instrumento | `Alcance do bend` (id) | `Vibrato da roda` (id) | Faixa (padrão) |
|---|---|---|---|
| Sintetizador | 35 | 36 | alcance 0..24 st inteiro (2); vibrato 0..2 st (1) |
| FM | 42 | 43 | idem |
| Wavetable | 39 | 40 | idem |
| Sampler | 9 | não tem | alcance 0..24 st inteiro (2) |
| Bateria | não tem | não tem | |

Espelhados em `app/lib/daw/instruments.dart` (grupo `Geral`); o teste de conferência das tabelas (`engine/src/instrument.rs`) compara motor e app. A faixa de controle do piano roll tem um espelho dos ids de alcance (`_bendRangeId`, `piano_roll_cc.dart:27`), usado só para o texto do balão.

### Como cada instrumento responde

| Instrumento | Pitch bend | Modulação | Pedal |
|---|---|---|---|
| Sintetizador | Sim: `pitch_hz(cur + lfo * lfo_pitch + expr)`, todas as vozes | Sim: vibrato de 5,5 Hz, profundidade `Vibrato da roda` | Sim (camada da faixa) |
| FM | Sim: mesma soma; os operadores derivam de `f0` pelas razões, então devem subir juntos (lido no código, não conferido de ouvido) | Sim | Sim |
| Wavetable | Sim: mesma soma, com `dt` limitado a `MAX_DT` | Sim | Sim |
| Sampler | Sim: `bend_semis` entra no passo de leitura (`step_at`, com e sem zonas); reafina só quando muda mais de 1e-4 st | **Sim, com profundidade fixa de 1 st** (o `PitchExpr` do sampler usa o padrão e não há knob); o commit descreve só o bend, mas o teste `sampler_tambem_faz_vibrato_com_a_roda` confirma | Sim |
| Bateria | Ignora (`set_pitch_bend` vazio) | Ignora | Ignora: `ExprState.pedal` é falso, então o `note_off` passa direto |

`PitchExpr` (`expression.rs:62`): o bend é suavizado com constante de tempo de 4 ms (`BEND_TAU`) e a profundidade do vibrato com 15 ms (`MOD_TAU`); a fase do LFO só anda com a roda acima de zero; `snap()` vai direto aos alvos depois de um silêncio, para a próxima nota não nascer varrendo de um valor velho (o sampler também faz isso quando não há voz soando). O desvio é calculado uma vez por bloco de controle (`step(len)`). `set_range` limita a 0..24 st e `set_vibrato` a 0..2 st.

## Decisões e por quê

- **Pedal no motor, não no app.** Antes o app adiava o `note_off`; assim o pedal não valia no quadro exato, não segurava notas de clipe e não dava para gravar. No motor, `note_off` pendente é um bit por altura (`u128`), sem alocar, e o mesmo caminho serve ao vivo e ao sequenciador.
- **Valores normalizados e o id 128 para o bend.** O app e o motor falam a mesma coisa sem depender de resolução de 7 ou 14 bits; o repouso é sempre 0 (o pedal solto, a roda embaixo, o bend no centro).
- **Gravação pelo registro de notas, com altura 256 + controle.** Reaproveita a ponte `rec_notes` (worklet e Android) sem função nova; a cota separada evita que uma roda mexida a fundo (centenas de eventos por segundo) tome o lugar das notas.
- **Reenviar tudo (`cc_clear` + `cc_add`) quando muda.** Como as notas: simples e idempotente. Fica separado de `notes_clear` para documento sem controles nunca pagar nada, e para um motor antigo (sem as chamadas) receber só o que já entendia.
- **Repouso no fim do clipe (`flattenControls`).** O clipe que termina com o pedal embaixo não pode segurar as notas do resto do projeto.
- **Afinar a gravação (1/48 de batida).** Um controlador manda centenas de valores por segundo; o clipe guarda o que a mão distingue. O bend é suavizado no motor, então a escada não se ouve.
- **Só a última passada do loop.** Curvas de passadas diferentes intercaladas dariam tremor.
- **Degraus, não interpolação.** Cada evento vale até o próximo. O lápis da faixa de controle põe um ponto por passo da grade; a reta idem.

## Como testar

Nenhum destes comandos foi executado ao escrever este capítulo.

```bash
cargo test -p jopendaw-engine                     # inclui expression_tests.rs
cargo test -p jopendaw-engine expression          # só a expressão (filtro por nome)
cd app && flutter test test/expression_test.dart test/piano_roll_cc_test.dart
```

- **`engine/src/expression_tests.rs`** (1062 linhas), por assunto: `PitchExpr` (chega ao alvo sem degrau, limita e ignora valores ruins, sem roda não move a fase); bend nos três instrumentos, em todas as vozes, com o alcance do instrumento, sem vazar para outra faixa; `sampler_responde_ao_bend`; `bateria_ignora_bend_modulacao_e_pedal` (saída idêntica); vibrato a 5,5 Hz sem mudar o volume (e no sampler); pedal (segura, solta várias de uma vez, limiar em 0,5, reatacar a nota segurada, não ressuscita nota solta antes de descer, funciona em FM/wavetable/sampler); pânico e troca do tipo da faixa; ordem e validação dos eventos; controles do clipe em qualquer tamanho de bloco; pedal do clipe (segura, sobe na batida de outra nota, desce na batida da nota); reconstituição em seek e na volta do loop; parar devolve ao neutro só o que o clipe dirigia; `documento_sem_eventos_soa_exatamente_como_antes`; `processar_controles_nao_aloca`; gravação (batida de agora, cota própria, salto do loop com tecla segurada).
- **`engine/src/api.rs`** (módulo de testes): as quatro chamadas na tabela de casos (`live_bend`, `live_cc`, `cc_add`, `cc_clear`), com controle desconhecido e faixa inexistente inócuos.
- **`engine/android/src/lib.rs`**: `live_controls_are_recorded_with_the_real_apply`, marcado `#[ignore]` ("depende do engine::api::apply completo"), então **não roda por padrão**.
- **`app/test/expression_test.dart`** (795 linhas): modelo e compatibilidade do JSON; `flattenControls`; cortar, mover e escalar (`splitMidiClip`, `splitAtPlayhead`, duplicar, `placeOnTop`, `scaleControls`, `mirrorControls`); `thinControls` e `drawControlLine`; sincronização com o motor (`FakeEngine`); MIDI ao vivo (14 bits, CC 1 e 64, canais, CC 121 e 120, mudança de faixa); gravação (clipe novo, rajada, só controles, overdub, loop, contagem, `parseRecordedNotes`); render fora de tempo real; as rodas do teclado da tela.
- **`app/test/piano_roll_cc_test.dart`** (293 linhas): a faixa de controle contra o controlador de verdade (menu do canto, lápis, ímã do centro, mover, apagar por botão direito e `Alt`, reta por `Shift` e por `Linha reta`, pedal pintado, toque e segurar para apagar, ferramentas de tempo, limites do clipe).
- **Na prática** (regra do projeto: o teste de uso é usar o app): `./hot.sh`, `flutter build web --release`, e pelo `node tool/cdp.mjs` o `jopendawEngine.injectMidi(0xE0, lsb, msb)`, `injectMidi(0xB0, 1, valor)` e `injectMidi(0xB0, 64, valor)` simulam um controlador; `probe` lê os picos para provar que o som sai e muda de altura (não confirmado: não foi rodado ao escrever este capítulo).

## Armadilhas conhecidas

- **`controls` no Dart, `cc` no JSON.** Quem lê o documento por fora (servidor, script) procura `cc` dentro de cada item de `midi`.
- **Motor novo exige binários novos.** Mudou algo aqui: `./engine/build-web.sh` e `./engine/build-android.sh` e commitar `engine.wasm` e os `.so` juntos. Um `.so` antigo com o app novo fica sem as chamadas (o `apply` dele não as conhece).
- **Sampler faz vibrato.** A documentação do commit diz que ele "responde ao bend", mas o `PitchExpr` do sampler também aplica a roda (1 st fixo, sem knob).
- **A gravação só registra com o transporte tocando** e só o que muda depois de gravar: o valor em que a roda já estava (por exemplo modulação levantada antes do `R`) não entra no clipe (não confirmado).
- **Só controles e nenhum clipe sob o cursor: perda silenciosa.** O aviso `Nenhuma nota foi tocada…` só sai se não houve nota **nem** controle; com controles e sem clipe, nada é criado e nada é dito.
- **Cortar preserva o estado; aparar e sobrepor não.** `splitControls` faz o clipe da direita começar com o pedal (ou o bend) que estava valendo no corte; aparar a borda esquerda e `placeOnTop` só deslocam os pontos, então o estado que ficava antes do novo começo se perde. No corte, o retorno ao repouso do fim do clipe da esquerda vem antes do primeiro ponto do da direita, então o pedal sobe e desce de novo na mesma batida e as notas seguradas nele saem ali (não confirmado ao ouvido).
- **`Dividir no cursor` (`K`) do piano roll só corta notas.** Os pontos ficam no mesmo clipe. Copiar, colar e duplicar notas também não os levam.
- **`_ccTrack` é por controle, não por origem.** A roda da tela numa faixa e um controlador MIDI noutra disputam o mesmo registro: mexer num devolve ao repouso o valor do outro (não confirmado em uso).
- **Bend da roda da tela tem 128 passos (1/64), o da faixa de controle 1/127 de cada lado**; o controlador MIDI manda 14 bits.
- **`closePedal` promete mais que faz.** O comentário de `midi_cc.dart` fala em bend e roda "fora do centro", mas o código só fecha o pedal; bend e roda ficam onde a mão parou, e é o fim do clipe que os devolve ao repouso na reprodução.
- **A roda de modulação da tela é zerada quando o painel é destruído** (`dispose` do `ExpressionWheel`); um vibrato "deixado ligado" não sobrevive a trocar de faixa (não confirmado na tela).
- **`live_cc` grava também faixas sem instrumento** (o registro vem antes da checagem do instrumento); o app só manda para faixas de instrumento, então na prática não aparece.
