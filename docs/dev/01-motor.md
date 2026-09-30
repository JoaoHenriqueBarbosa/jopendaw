# O motor de áudio (`engine/`)

> Referência do crate `jopendaw-engine` para quem mexe no motor: módulos, ciclo de render por bloco, transporte, notas, clipes, automação, ids de parâmetro, regras de tempo real e a tabela completa de `engine::api::apply`. As pontes para web e Android ficam em [02-pontes-web-e-android.md](02-pontes-web-e-android.md).

Citações no formato `arquivo:linha` valem para o estado do repositório em 2026-09-30 (commit `924bac4`); linhas andam, os nomes de função não.

## Visão geral

O crate `engine/` é Rust puro: `[dependencies]` vazio (`engine/Cargo.toml`), sem plataforma, sem threads, sem E/S. Quem hospeda cria um `Engine::new(rate)`, entrega comandos entre um bloco e outro e chama `Engine::process(left, right)` para receber áudio. Na web o hospedeiro é o AudioWorklet (`engine/wasm`), no Android é o `engine/android` (AAudio); o render offline usa o mesmo `Engine` numa instância à parte.

```
 comandos (documento, MIDI, UI)                    entrada de áudio (mic)
        │  api::apply / Call                              │ Engine::set_input
        ▼                                                 ▼
 ┌───────────────────────────── Engine ─────────────────────────────────┐
 │ transporte (pos em quadros, loop, andamento)                         │
 │                                                                      │
 │  por faixa, na ordem de `order` (normais primeiro, barramentos depois)│
 │  ┌──────────────────────────────────────────────────────────────┐    │
 │  │ fonte: clipes → entrada monitorada → instrumento (notas)     │    │
 │  │   ▼                                                          │    │
 │  │ inserts (Chain: até 16 efeitos, crossfade, sidechain)        │    │
 │  │   ▼ chave de sidechain (pós-inserts, pré-fader)              │    │
 │  │ envios pré-fader ─────────────────────────────► barramentos  │    │
 │  │   ▼                                                          │    │
 │  │ fader (volume, pan, mudo; rampa de 5 ms)                     │    │
 │  │   ▼ envios pós-fader ─────────────────────────► barramentos  │    │
 │  │ porta do solo → saída: master ou barramento de índice maior  │    │
 │  └──────────────────────────────────────────────────────────────┘    │
 │  master: inserts → volume/balanço → limpa NaN → metrônomo →          │
 │          limitador de segurança → clamp ±1 → medidor/analisador      │
 │  capturas (render offline) e picos (medidores)                       │
 └───────────────────────────────────────────────────────────────────────┘
        ▼
   left/right do hospedeiro
```

O tempo é contado em quadros (amostras por canal) na taxa do motor; o documento fala em batidas, e a conversão usa o andamento atual (`lib.rs:657`, `lib.rs:661`).

## Peças e responsabilidades

| Arquivo | Papel | Estruturas e funções principais |
|---|---|---|
| `engine/src/lib.rs` | O `Engine`: transporte, clipes, notas, automação, roteamento, ciclo de render, gravação e capturas. Também tem 57 testes. | `Engine` (`lib.rs:474`), `Sample` (`:127`), `Clip` (`:208`), `Lane` (`:250`, instrumento + notas de uma faixa), `Strip` (`:424`, inserts + envios + saída), `AutoLane` (`:392`), `Target` (`:369`) |
| `engine/src/api.rs` | As chamadas por nome (`[nome, ...args]` em f64), o mesmo protocolo dos exports do wasm. Usado pelo Android e pelo render offline nativo. | `apply` (`:55`), `Call::parse` (`:275`, valida e converte), `Call::apply` (`:348`, aplica), tabela `CALLS` (`:132`), `HOST_ONLY` (`:182`), `MAX_TRACKS = 1024` (`:51`) |
| `engine/src/mixer.rs` | Canal, envio e cadeia de efeitos. | `Track` (`:33`: ganho, pan, mudo, solo, picos, suavização), `Send` (`:231`), `Chain` (`:384`) e `Slot` (`:330`), `Scratch` (`:296`), `Stereo` (`:318`) |
| `engine/src/instrument.rs` | Contrato `Instrument`, tipos de faixa (`kind`), `create`, e os ids de parâmetro dos cinco instrumentos. | `trait Instrument` (`:16`), `kind` (`:36`), `create` (`:51`), `synth_param` (`:68`), `drum_param` (`:133`), `sampler_param` (`:183`), `fm_param` (`:202`), `wavetable_param` (`:248`), `contract` (`:317`, só teste) |
| `engine/src/synth.rs` | Sintetizador subtrativo (tipo 1): 2 osciladores com polyBLEP/BLAMP, sub, ruído, uníssono de até 7, SVF, 2 envelopes, LFO, glide, mono/legato. 16 vozes + 4 de folga. | `Synth` (`:455`), `SPECS` (`:65`, faixa/padrão por id) |
| `engine/src/drums.rs` | Bateria sintetizada (tipo 2): 12 peças geradas na hora, 3 vozes por peça, chimbal fechado corta o aberto. | `Drums`, `drum_param::piece_for` |
| `engine/src/sampler.rs` | Sampler (tipo 3): lê um `Arc<Sample>` afinado pela nota, Hermite de 4 pontos, passa-baixa Butterworth de 4ª ordem quando lê acima da altura original. 16 vozes + 4 de folga. Sem zonas toca um áudio único; com zonas delega o disparo a `sampler_zones.rs`. | `Sampler` (`:313`), `VOICES = 16` (`:32`), `SLOTS` (`:34`) |
| `engine/src/sampler_zones.rs` | Submódulo de `sampler.rs` (`#[path]`, enxerga os campos privados dele): zonas do sampler (multi-sample, camadas de velocidade, round-robin, loop, trecho) e fatiamento de loops. Ver "Zonas do sampler e fatiamento". Testes em `sampler_zones_tests.rs` (42). | `ZoneDef` (`:39`), `Zone`, `Span` (`:120`), `Sampler::note_on_zones` (`:240`), `slice_points` (`:321`), `slice_zones` (`:435`), `MAX_ZONES = 128`, `MAX_SLICES = 96` |
| `engine/src/fm.rs` | FM de 4 operadores, 8 algoritmos (tipo 5), limite de banda por regra de Carson. | `Fm` (`:374`), `ALGORITHMS` (`:143`) |
| `engine/src/wavetable.rs` | Wavetable (tipo 6): 2 osciladores, 3 séries de 8 tabelas, 9 níveis de mip-map, tabelas numa `OnceLock` compartilhada. | `Wavetable`, `Tables` |
| `engine/src/effect.rs` | Contrato `Effect`, tipos de efeito (`kind`), `create`, ids de parâmetro dos 12 efeitos e os alvos de automação. | `trait Effect` (`:12`), `kind` (`:37`), `create` (`:53`), `NOTE_BEATS` (`:73`), `*_param` (`:89`–`:305`), `auto_target` (`:306`) |
| `engine/src/fx/*.rs` | Implementação dos 12 efeitos: `eq`, `compressor`, `gate`, `limiter`, `utility`, `reverb`, `delay`, `chorus`, `phaser`, `tremolo`, `distortion`, `filter`. | `fx/mod.rs` só declara os módulos |
| `engine/src/dsp.rs` | Peças compartilhadas: `Adsr`, `Smoothed`, `Rng`, `poly_blep`/`poly_blamp`, `sin_turns`, `fast_tanh`, `Svf`. | `Adsr` (`:11`), `Smoothed` (`:125`), `Svf` |
| `engine/src/limiter.rs` | Limitador de segurança do master (privado): lookahead 1,5 ms, teto 0,966 (−0,3 dBFS), release 80 ms. Não é o efeito `fx/limiter.rs`. | `Limiter` (`:19`), constantes `:13`–`:17` |
| `engine/src/loudness.rs` | Medidor de loudness do master (BS.1770-4 / EBU R128): K-weighting para qualquer taxa, momentâneo (400 ms), curto prazo (3 s), integrado com gates de −70 LUFS e −10 LU, faixa de loudness (LRA) e true peak com sobreamostragem 4×. Sem alocação depois de criado. Ver "O medidor de loudness". | `Meter` (`push`, `read`, `read_kind`, `reset`), `measure` (offline), `Loudness`, `kind`, `NONE` (−200) |
| `engine/src/analyzer.rs` | Anel de 4096 quadros mono e FFT real radix-2 própria; devolve dB de −120 a 0. | `Analyzer` (`:17`), `RING` (`:12`) |
| `engine/src/record.rs` | Registro das notas ao vivo (`NoteRecorder`, até 16 384 notas) e capturas do render offline (`Captures`, até 64). | `MAX_REC_NOTES` (`:16`), `MAX_CAPTURES` (`:22`) |
| `engine/src/stretch.rs` | Offline, fora da thread de áudio: WSOLA para esticar (razão 0,25–4), reamostrador sinc para transpor (±24 semitons), `detect_bpm` (60–200). Funções puras canais → canais. | `stretch` (`:44`), `detect_bpm` (`:226`), `Tempo` (`:212`) |
| `engine/src/metronome.rs` | Clique senoidal de 30 ms: 1600 Hz no primeiro tempo do compasso, 1000 Hz nos outros. | `Metronome` |
| `engine/src/testalloc.rs` | Só em teste (`#[cfg(test)]`, `lib.rs:81`): alocador global que conta alocações de uma thread. | `count` |

Fora do crate, mas parte do contrato: `engine/wasm/src/lib.rs` (exports C do worklet) e `engine/android/src/` (superfície `jd_*`). O teste `apply_conhece_todos_os_exports_sem_ponteiro_do_wasm` (`api.rs:825`) lê o `lib.rs` do wasm e falha se um export novo não estiver espelhado em `CALLS`/`Call` ou em `HOST_ONLY`.

### Contratos dos traits

`Instrument` (`instrument.rs:16`) e `Effect` (`effect.rs:12`) são `Send`. O motor garante que `render`/`process` recebem blocos de até `CHUNK` quadros (128), abaixo do teto de contrato `MAX_BLOCK = 4096` (`lib.rs:98`). Todos os efeitos e instrumentos alocam tudo em `new`.

- `Instrument`: `note_on`, `note_off`, `release_all` (release normal, usado no stop), `silence` (corte imediato, usado no pânico), `set_param`, `set_sample` (só o sampler usa), `zones_clear`, `zone_add` e `zone_sample` (só o sampler usa: apagar as zonas, acrescentar uma, e ligar ou desligar o áudio de um id nas zonas que o citam; os três têm implementação vazia por padrão), `render` (soma, não zera), `active` (permite pular o render).
- `Effect`: `set_param`, `process`, `process_keyed` (sidechain; só compressor e gate sobrescrevem), `set_tempo` (só `delay`, `tremolo` e `filter`), `reset`, `latency`, `meter` (compressor, gate e limitador devolvem a redução de ganho em dB).

## Fluxo de dados / ciclo de vida

### Uma chamada de `process`

`Engine::process` (`lib.rs:1492`):

1. `prepare` (`:1538`), entre blocos: reordena as notas mexidas (`sort_unstable_by`, no lugar) e reposiciona os cursores (`prepare_notes`, `:1550`); `Chain::collect` solta efeitos cujas transições terminaram; `route` refaz a ordem de processamento se algo do roteamento mudou.
2. Se as capturas foram mexidas, `start_render` (`:1442`) prepara o render offline (ver abaixo).
3. `run` (`:1505`) fatia o bloco do hospedeiro em pedaços (`chunk`) e chama `render` em cada um.

O tamanho do pedaço é o menor entre: o resto até o próximo múltiplo de `CHUNK` (128) do relógio `clock`; com automação tocando, o resto até o próximo múltiplo de `AUTO_STEP` (32); e, dentro de um loop, os quadros até `loop_end`. Como a grade é do relógio do motor e não do bloco do hospedeiro, blocos de 4096 e 32 blocos de 128 geram exatamente a mesma saída (teste `mesma_sequencia_de_chamadas_da_a_mesma_saida_em_qualquer_bloco`, `lib.rs:3346`).

### Ordem real dentro de um pedaço (`Engine::render`, `lib.rs:1579`)

1. `out_l`/`out_r` zerados; `automate()` avalia as lanes na posição do pedaço; `solo()` recalcula quem passa pela porta do solo.
2. Os buffers dos barramentos são zerados e `incoming` limpo.
3. Para cada faixa na ordem de `order` (`render_track`, `lib.rs:1720`):
   1. Fonte. Faixa normal: `render_source` (`:1685`) zera o buffer e soma, nesta ordem, os clipes (tocando, ou a cauda de 10 ms depois do stop), a entrada de áudio monitorada (só faixa do tipo áudio) e o instrumento com as notas do sequenciador e as ao vivo (`Lane::render`, `:299`). Barramento: o que os envios e saídas de outras faixas acumularam no buffer dele.
   2. Inserts (`Chain::process`, `mixer.rs:635`): rodam se a cadeia estiver viva e (a faixa soou ou a cadeia não está parada); um bloco não finito vira silêncio e a cadeia é resetada.
   3. Chave de sidechain: se alguma cadeia usa esta faixa como chave, a saída pós-inserts (pré-fader) é copiada para `keys[t]`.
   4. Sem som: `settle` (ganhos vão direto ao alvo) e a faixa retorna.
   5. Envios pré-fader (`mix_sends` com `pre = true`), fader (`Track::fader`: volume, pan de potência constante, mudo, rampa de 5 ms), envios pós-fader.
   6. `Track::output`: porta do solo (rampa) e soma no destino, que é o buffer do master ou de um barramento de índice maior; mede o pico.
4. Capturas de faixa (`capture_tracks`, `:1671`).
5. Master: cadeia de inserts do master (`master_fx`, com parada por silêncio como nas faixas), depois volume e balanço (`Track::apply_master`, `mixer.rs`: o pan só atenua o lado oposto), depois a varredura que troca NaN/infinito por 0.
6. Metrônomo, só com o transporte tocando: renderizado num buffer de rascunho e somado depois da cadeia do master, multiplicado pelo ganho atual do fader do master (o clique não passa por efeito do master, mas segue o volume).
7. Com o transporte parado e cauda de clipes ativa, o contador `tail` desce.
8. Limitador de segurança (`limiter.rs`), `clamp(-1, 1)`, **medidor de loudness** (`loudness.push`, fora do pré-roll do render, ver abaixo), medidor de pico do master, analisador (se observa o master) e capturas do master.

Em resumo, a ordem que interessa para quem depura é: clipes → entrada monitorada → instrumento → inserts → envios pré → fader → envios pós → saída/barramentos (em ordem de índice) → inserts do master → volume do master → metrônomo → limitador.

### Roteamento e solo

- `route` (`lib.rs:1058`) roda só quando `routing_dirty`. Monta `order`: faixas normais primeiro, com quem serve de chave de sidechain antes de quem a usa (num ciclo, uma das duas fica com a chave do pedaço anterior), depois os barramentos em ordem de índice. Uma chave que é barramento também chega com um pedaço de atraso, porque barramentos são processados depois das normais (deduzido do código; sem teste que o cubra, `(não confirmado)`).
- Destino de saída ou de envio só vale se for barramento e vier depois da origem na ordem (`rank`); senão a saída vira o master e o envio fica inativo (`dst = -1`). O app garante isso, o motor só se defende.
- `solo` (`lib.rs:1134`): faixa solada segue audível junto com o que recebe dela (saída e envios, em cadeia); barramento solado mantém audível o que sai nele. O solo é uma porta na saída, fora do fader, para que os envios de uma faixa calada por solo ainda cheguem a um barramento solado.

### Transporte, loop e seek

Estado em `Engine` (`lib.rs:474`): `pos` (quadros, f64), `playing`, `loop_on`/`loop_start`/`loop_end` (quadros), `bpm`, `beats_per_bar`.

- `set_tempo` (`:638`): `bpm` limitado a 20–999, compasso a 1–32. A posição musical e os limites do loop são preservados em batidas (`pos` e loop são reconvertidos), então mudar o andamento tocando não faz a linha do tempo pular.
- `play` (`:682`): liga `playing`, marca `recue` (reposicionar cursores de nota) e zera a cauda. Notas que começaram antes de `pos` não soam ("não persegue"); uma nota que começa exatamente em `pos` toca (`cue` usa `event_offset < 0`, `:283`).
- `stop` (`:693`): a posição não volta; `tail = tail_len` (10 ms, `STOP_FADE_SECS`) faz os clipes de áudio descerem a zero; instrumentos recebem `release_all` (release normal, caudas seguem soando, as dos efeitos também); `held` do sequenciador é limpo; as notas gravadas seguradas são fechadas na posição atual. A automação volta ao valor estático no próximo pedaço (`auto_live`).
- `seek` (`:711`): `beat` mínimo 0; solta as notas do sequenciador (as ao vivo continuam); `recue`; zera `out_delay`.
- `set_loop` (`:726`): só liga com `end > start`. Em `run` (`:1505`), com `playing && loop_on && pos < loop_end` o pedaço é cortado para terminar em `loop_end` (`ceil`); ao alcançar o fim, `pos = loop_start + (pos - loop_end)` (a fração que passou é carregada), o gravador registra o salto e `wrap_notes` (`:1571`) solta o que o sequenciador segurava e reposiciona os cursores. Tocando depois do fim do loop, o transporte segue reto.
- Andamento e posição são consultáveis por `beat()` (`:668`): posição do próximo quadro que sai, já descontado o adiantamento do render (`out_delay`).

### Notas e clipes

**Notas.** Cada faixa tem `Lane.notes` ordenadas por início, em batidas absolutas (`Note`, `lib.rs:224`). O app reenvia todas a cada edição (`notes_clear` + `note_add`), inclusive tocando. `Lane::render` (`:299`) fatia o pedaço nos quadros exatos dos eventos: `event_offset` (`:245`) converte batida em quadro inteiro com folga `FRAME_EPS = 1e-6`. Em cada evento, primeiro soltam-se as notas que vencem e depois disparam-se as que começam no mesmo quadro (uma nota que termina onde a mesma altura recomeça não corta a nova). O note off vem do conjunto `held` (notas que o sequenciador disparou), não da lista: apagar ou reenviar notas no meio de uma nota nunca a deixa presa. Notas sobrepostas da mesma altura ficam com o fim mais tardio (`hold`, `lib.rs:350`). Parado, o sequenciador não dispara nada; o instrumento continua soando por notas ao vivo e caudas.

**Notas ao vivo** (`live_on`/`live_off`, `:905`/`:922`) vão direto ao instrumento, sem depender do transporte, e não são soltas por seek nem pela volta do loop. Velocidade 0 ou NaN equivale a `live_off`. Com a gravação ligada e o transporte tocando, entram no `NoteRecorder` com a batida do momento.

**Clipes.** `Engine.clips` é uma lista única (`Clip`, `lib.rs:208`): faixa, id do sample, `start` em batidas, `offset` e `length` em segundos do sample, ganho, `fade_in`/`fade_out` em segundos. `render_clips` (`:1817`) percorre todos os clipes filtrando pela faixa, converte o início para quadros pelo andamento atual, lê o sample com interpolação cúbica (`Sample::at_cubic`, com conversão de taxa) e aplica o envelope de fade (`fade`, `:1848`, curva quadrática). Clipe cujo `id` de sample não está carregado é ignorado. A lista é reenviada inteira a cada sincronização (`clips_clear` + `clip_add`). Não há checagem de tipo: `render_source` soma clipes em qualquer faixa que não seja barramento, mesmo de instrumento; só o monitoramento da entrada exige faixa de áudio.

### Zonas do sampler e fatiamento (`engine/src/sampler_zones.rs`)

Sem zonas o sampler é o de sempre (um áudio, nota base e modo do parâmetro do instrumento). Com **pelo menos uma zona** (`Sampler.zones` não vazio) `note_on` desvia para `note_on_zones` (`sampler.rs`, `sampler_zones.rs:240`): o áudio único, o parâmetro `root` e o parâmetro `one_shot` deixam de valer; `tune` (afinação fina do instrumento), o ADSR, `velocity` e `level` continuam valendo.

**Estruturas.**

| Estrutura | Papel |
|---|---|
| `ZoneDef` (`:39`, `Copy`) | O que o app manda em `zone_add`: `root`, `lo`..`hi` (notas), `vlo`..`vhi` (velocidade 1..=127), `cents`, `gain_db`, `pan`, `one_shot`, `group`, `start`/`end` (trecho em segundos do áudio, `end` ≤ 0 é o fim), `loop_start`/`loop_end` (só no modo sustentado, vale com `loop_end > loop_start`). `Default`: nota base 60, teclado e velocidades inteiros, sustentado, sem grupo, sem loop. |
| `ZoneDef::sanitized` (`:89`) | Roda em `add_zone`: limita cada campo (`cents` −1200..1200, `gain_db` −60..24, `pan` −1..1, `group` 0..63; notas 0..127, velocidades 1..127), troca as pontas de faixas invertidas, número não finito vira 0, tempo negativo vira 0. |
| `Zone` | `def` + `sample_id` + `Option<Arc<Sample>>` + `Option<Span>`. Sem áudio (ainda não carregado, ou descartado) ou com trecho vazio a zona não toca. |
| `Span` (`:120`, `Copy`) | O trecho já em quadros do áudio da zona (`first`, `limit`), o loop `[início, fim)` em quadros, o ganho de cada lado (pan), `one_shot`, nota base, cents e a descida do fim. A voz guarda uma cópia. `Span::whole` é o áudio inteiro sem loop (o sampler de áudio único). |

**Seleção da zona (`note_on_zones`).**

1. A velocidade do `note_on` (0..1) vira inteiro `round(v · 127)` limitado a 1..=127.
2. Passam as zonas com áudio e trecho válidos cuja faixa de notas e cuja faixa de velocidade contêm a nota e a velocidade (`Zone::plays`). **Todas** as que casam tocam: zonas sobrepostas empilham (camadas). Nenhuma zona casa: a nota não soa.
3. Round-robin: para cada grupo `g > 0` conta-se quantas zonas dele casam (`counts[g]`); a `k`-ésima delas (na ordem da lista) só toca se `k == rr[g] % counts[g]`. Depois de escolher, `rr[g]` avança em 1 para cada grupo que teve zona casada (`wrapping_add`). O contador é por grupo, não por nota. Grupo 0 não alterna.
4. Sem vozes soando a rampa do volume (`level_now`) salta para o `level` (a primeira nota sai no volume pedido).
5. A mesma nota de novo: as vozes seguras e ainda não soltas dessa altura entram em release (também as `one_shot`) e as novas começam do início.
6. Para cada zona escolhida: passo de leitura `step_at(pitch, sample, root, cents + tune)` (a nota base e os cents da zona, mais o `tune` do instrumento), ganho `1 − velocity + velocity · v²` vezes `10^(gain_db/20)`, vaga de voz por `take_slot` (rouba a mais antiga se as 16 estão seguras), o `Span` da zona entra na voz e a voz guarda o `Arc<Sample>` (`own`). Cada zona que dispara ocupa **uma voz**: uma nota com 3 camadas gasta 3 das 16.

**Na voz (`Voice`).** `span.first` é o primeiro quadro lido (`start` da zona); `push` volta de `end` para `start` no loop (o quadro `end` nunca é lido, sem crossfade); depois de `span.limit` o áudio é silêncio e, com `limit + 3` quadros, a voz acaba. Sem loop, `Span::fade` desce o ganho a zero no último milissegundo do trecho (`END_FADE_SECS = 1 ms`, no máximo metade do trecho), para as fatias não estalarem; com loop, o fade é 0. O pan da zona é balanço (`gl = 1 − max(pan, 0)`, `gr = 1 + min(pan, 0)`). No `note_off`, com `span.zone` vale o `span.one_shot` da zona e sem ele o parâmetro `one_shot` do instrumento; `release_all` (stop) solta tudo, `one_shot` inclusive.

**Áudio por id.** A zona cita o áudio pelo id de `Engine::load_sample`. `Engine::add_zone` (`lib.rs:921`) procura o `Arc<Sample>` e o entrega à zona (`None` se ainda não carregou); `load_sample` e `drop_sample` chamam `zone_sample(id, ...)` em todos os instrumentos (`bind_zone_sample`), que ligam ou desligam o áudio nas zonas com aquele id e refazem o `Span`. `Engine::clear_zones` (`lib.rs:913`) esvazia a lista e zera `rr`. As vozes que já tocavam **não** são cortadas por mexer nas zonas ou descartar o áudio: cada uma guarda o próprio `Arc` e o próprio `Span`; o `render` do sampler usa `own` antes do áudio único. A troca do áudio único (`set_sample`) não toca nas vozes de zona (`!v.span.zone`, commit `6f3d245`).

**Limites (`sampler_zones.rs:27-35`).** `MAX_ZONES = 128` (a lista nasce com essa capacidade em `Sampler::new`; passar disso descarta, sem alocar), `MAX_GROUPS = 64` (grupos 0..63; o `sanitized` limita a 63), `MAX_SLICES = 96`, `FIRST_SLICE_NOTE = 24` (C1; 24 + 96 − 1 = 119 < 127). O disparo usa só arrays na pilha (`counts`, `seen`, `picked`).

**Fatiamento.** `slice_points(channels, rate, mode)` (`:321`) devolve os pontos de corte em segundos, crescentes; o primeiro é sempre 0 (áudio vazio: nenhum). `SliceMode::Count(k)` (1..=96, no máximo o número de quadros) divide em `k` partes iguais. `SliceMode::Transients(sensibilidade 0..1)` (`transients`, `:345`):

- Mono = média dos canais. A cada 5 ms (`HOP_SECS`) calcula `ln(1 + 1e4·energia) + ln(1 + 1e4·energia da derivada)`; o fluxo positivo desse envelope é comparado com a média local (±0,2 s), com o maior fluxo e com um piso, e só os máximos locais a 50 ms um do outro passam. Se o maior fluxo é menor que 0,5 (silêncio, tom constante) não há cortes além do 0. Limiares: `relativo = 6,0 − 4,5·s`, `piso = 1,2 − 0,8·s`, `fração do pico = 0,30 − 0,22·s`.
- O corte é refinado no áudio (`onset`, `:419`): o primeiro quadro em que o sinal passa de 10% do pico do ataque, recuado até o cruzamento de zero mais próximo (até 2 ms). Depois do refinamento, dois cortes a menos de 25 ms viram o mais forte deles; cortes a menos de 10 ms (`EDGE_SECS`) do começo ou do fim caem; passando de 95, ficam os 95 mais fortes.

`slice_zones(pontos, primeira_nota)` (`:435`) gera uma `ZoneDef` por ponto: nota `primeira + i` (cromática, para em 127 ou em 96), `lo = hi = root = nota`, `one_shot`, `start` = o ponto, `end` = o ponto seguinte (0 na última), o resto no padrão; pontos repetidos, fora de ordem ou não finitos são pulados. **Nada disso é chamada da API**: `slice_points` e `slice_zones` não estão em `CALLS` nem no wasm. O app (`app/lib/daw/sampler_zones.dart`) tem uma **porta em Dart** da mesma conta (`slicePoints`, `sliceZones`, com os mesmos limiares e os testes equivalentes em `app/test/sampler_zones_test.dart`) e manda o resultado como zonas comuns (`zone_add`). O código Rust serve de referência e de teste; quem mudar um limiar tem de mudar os dois.

### Automação

Lanes (`AutoLane`, `lib.rs:392`) com pontos `(beat, value, curve)` ordenados; o alvo é `Target { track, kind, slot, id }` com `kind` em `effect::auto_target` (`effect.rs:306`).

| `auto_target` | Valor | Unidade do ponto | Efeito |
|---|---|---|---|
| `VOLUME` = 0 | `slot` e `id` ignorados | ganho linear | `Track.auto_gain` |
| `PAN` = 1 | idem | −1..1 | `Track.auto_pan` |
| `INSTRUMENT` = 2 | `id` = parâmetro do instrumento | unidade da tabela | `set_param` do instrumento, só quando o valor muda |
| `EFFECT` = 3 | `slot` e `id` | unidade da tabela | `Chain::set_param(..., from_app = false)`, só quando muda |
| `SEND` = 4 | `slot` = índice do envio | ganho linear | `Send.auto_level` |

- `value_at` (`:407`): antes do primeiro ponto vale o primeiro, depois do último vale o último; entre pontos a curva é `t^(2^(curva·3))` (`curva = 0` é reta; −1..1).
- Avaliada por `automate` (`:1214`) no início de cada pedaço, na posição do transporte, com passo máximo de 32 quadros (`AUTO_STEP`). Só roda tocando; parado, tudo volta ao valor estático (`restore`).
- O valor estático que o app manda (`param`, `fx_param`, `track`, `send_set`) fica guardado em `statics` (64 posições por instrumento e por slot, `STATIC_PARAMS`) e a automação o sobrepõe sem apagar. Com o alvo sob automação (tocando e com pontos), `set_param`/`set_fx_param` só guardam o estático e não repassam ao instrumento.
- `auto_clear` guarda os alvos das lanes apagadas em `auto_restore`; os que não voltarem a ser automatizados retornam ao estático no próximo pedaço, e os que voltarem seguem sem degrau.
- O parâmetro de faixa-chave do sidechain não é automatizável (mudaria o roteamento a cada pedaço), `Chain::set_param` (`mixer.rs`) o recusa.

### Parâmetros por id (`*_param`)

Todo parâmetro é um `u32` estável, com valor na unidade da tabela (Hz, s, dB, semitons), nunca normalizado. Os ids estão em `instrument.rs` e `effect.rs`; o espelho é `app/lib/daw/instruments.dart` e `app/lib/daw/effects.dart` (`ParamSpec`). Mudar ou reutilizar um id quebra projetos salvos; id novo entra no fim.

| Módulo | Ids | Observação |
|---|---|---|
| `synth_param` (`instrument.rs:68`) | 0–34, `COUNT = 35` | oscilador 1 (0–2), oscilador 2 (3–6), sub, ruído, uníssono (9–11), filtro (12–16), envelopes (17–24), LFO (25–29), glide, vozes, velocidade, nível, drive |
| `drum_param` (`:133`) | `peça * 4 + k` (k: 0 volume, 1 afinação, 2 decaimento, 3 timbre), `MASTER = 48` | 12 peças, ids 0–47; ordem das peças e nota GM em `PIECE_PITCH` |
| `sampler_param` (`:183`) | 0–8 | raiz, ADSR, nível, one-shot, afinação fina, velocidade |
| `fm_param` (`:202`) | 0 algoritmo, 1 realimentação, operadores em `OP_BASE + op * OP_STRIDE + k` (`OP_BASE = 2`, `OP_STRIDE = 8`, 4 operadores, ids 2–33), 34–41 LFO/vozes/glide/nível; `COUNT = 42` | `fm_param::op(op, k)` calcula o id |
| `wavetable_param` (`:248`) | 0–38, `COUNT = 39` | osciladores 1 (0–4) e 2 (5–9), sub, ruído, uníssono, filtro, envelopes, LFO, `ENV_POS` |
| `eq_param` (`effect.rs:89`) | banda `b * 6 + k` (8 bandas, k: ligada, tipo, freq, ganho, Q, inclinação), `OUTPUT = 48` | maior tabela, motivo de `STATIC_PARAMS = 64` |
| `compressor_param` (`:108`) | 0–10 | `SIDECHAIN = 10` (faixa-chave, −1 = a própria entrada) |
| `gate_param` (`:134`) | 0–6 | `SIDECHAIN = 6` |
| `limiter_param` (`:151`) | 0–4 | ganho, teto, release, lookahead (≤ 10 ms), link |
| `utility_param` (`:164`) | 0–7 | ganho, pan, largura, mono, inverter L/R, trocar, DC |
| `reverb_param` (`:180`) | 0–9 | FDN de 8 linhas, pré-atraso até 250 ms, `FREEZE` |
| `delay_param` (`:203`) | 0–11 | livre ou sincronizado (`NOTE` indexa `NOTE_BEATS`), até 4 s |
| `chorus_param` (`:228`) | 0–6 | 1–4 vozes, serve de flanger com atraso curto e realimentação |
| `phaser_param` (`:244`) | 0–6 | 2, 4, 6, 8 ou 12 estágios |
| `tremolo_param` (`:258`) | 0–5 | senoide, triângulo, quadrada; sincronizável |
| `distortion_param` (`:270`) | 0–7 | 6 tipos, sobreamostragem 1×/2×/4×; latência fixa `LATENCY` |
| `filter_param` (`:287`) | 0–10 | SVF 12/24 dB, LFO, seguidor de envelope, sincronizável |

Tipos de faixa (`instrument::kind`, `instrument.rs:36`): 0 áudio, 1 sintetizador, 2 bateria, 3 sampler, 4 barramento, 5 FM, 6 wavetable. O índice de `TrackKind` no Dart é o código do motor; tipo novo só entra no fim. Tipos de efeito (`effect::kind`, `effect.rs:37`): 1 EQ, 2 compressor, 3 gate, 4 limitador, 5 utilitário, 6 reverb, 7 delay, 8 chorus, 9 phaser, 10 tremolo, 11 distorção, 12 filtro; 0 esvazia o slot.

`Engine::set_param` guarda o valor em `statics` apenas para ids abaixo de 64; `Instrument::set_param` de cada instrumento limita ao intervalo da tabela (o synth arredonda os discretos, `synth.rs:890`) e ignora id desconhecido.

### Cadeia de efeitos (`Chain`, `mixer.rs:384`)

- Até `MAX_SLOTS = 16` slots por faixa e no master (`fx_count` com `track = -1`). O vetor nasce com capacidade `MAX_SLOTS * 2`, então esticar e encolher a cadeia não realoca.
- `set_kind`: mesmo tipo de novo não faz nada; tipo diferente cria o efeito nos padrões (`effect::create`) e troca por crossfade de 10 ms (`FADE_SECS`); tipo 0 esvazia em fade. Os `fx_param` vêm depois do `fx_set`. Slot além do fim estica a cadeia (o app pode mandar o tipo antes da contagem).
- Bypass e efeito entrando ou saindo passam por mistura seco/molhado (`wet`) com a mesma duração; voltar de um bypass assentado faz `reset` do efeito, para um delay não devolver ecos de antes.
- Cadeia parada: com a entrada calada e a saída em silêncio (abaixo de `SILENCE = 1e-6`, −120 dB) por mais que `hold` quadros, a cadeia deixa de rodar até a entrada voltar. `hold` é o maior `tail_secs` dos efeitos presentes: delay 4,5 s, reverb 0,5 s, chorus e phaser 0,1 s, os demais 0,05 s (`mixer.rs:374`). Enquanto sai som, a cadeia continua rodando, então as caudas longas de reverb e delay soam por inteiro depois do stop.
- Sidechain (compressor e gate): o valor do parâmetro `SIDECHAIN` é interceptado no motor (`Chain::set_param`), arredondado para o índice da faixa-chave (negativo = a própria entrada) e o motor entrega o buffer da chave em `process_keyed`.
- Latência de efeito (`Effect::latency`, implementada por `distortion` e `fx/limiter`) não é compensada: nada no motor chama `latency()` fora dos testes.

### Preparo do render offline (`start_render`, `lib.rs:1442`)

Quando o hospedeiro registra capturas (`capture_add`), o próximo `process` chama `start_render`: termina no silêncio as transições que um motor novo ainda faria (50 ms de `WARMUP_SECS` de silêncio pelas cadeias, envios e faders indo ao alvo com a automação da partida aplicada), zera o relógio e adianta o transporte da latência do limitador do master (medida por impulso em `limiter_latency`, `:562`), descartando essa saída. As capturas de faixa esperam o mesmo tanto num anel para ficarem alinhadas com a do master. `beat()` informa a posição do que sai. O resultado depende só das chamadas e dos quadros processados, nunca do relógio.

Capturas (`record.rs`): até `MAX_CAPTURES = 64`; cada uma guarda até `MAX_BLOCK` quadros do último bloco; faixa −1 é o master depois do limitador, faixa ≥ 0 é a saída pós-fader (a posição dos medidores). Com captura, o hospedeiro processa blocos de até 4096 quadros.

### Gravação e entrada

`set_input` (`:1365`) copia a entrada do próximo bloco (até 4096 quadros, NaN vira 0) e só vale para o `process` seguinte. Faixas de áudio com `input_monitor` somam essa entrada no buffer antes dos inserts. As notas ao vivo gravadas saem por `rec_notes` em grupos de 5 floats (faixa, altura, início, fim, velocidade).

## Contratos

### Tabela de `engine::api::apply`

`apply(engine, nome, args)` (`api.rs:55`) devolve `Ok(Some(v))` para as chamadas com retorno, `Ok(None)` para as outras, ou `Err(UnknownCall)` com o motor intocado. Regras de conversão (cabeçalho de `api.rs`, `wrap32` em `:203`): cada número é convertido como o JavaScript faz ao chamar um export do wasm (inteiros truncados com volta módulo 2³², `usize` de 32 bits, booleano = "diferente de zero" depois dessa conversão, f32 mais próximo); argumentos a mais são ignorados; argumento faltando, não finito (também depois de virar f32) ou `tracks` acima de 1024 são erro. Faixa `-1` é o master onde o export recebe `i32`. Antes de qualquer efeito, `Call::parse` valida e `Call::apply` só aplica, sem falhar.

Convenções abaixo: `faixa` é índice de zero; `bool` é 0/1; batidas são f64; ganhos são lineares.

| Chamada | Argumentos (tipo) | Efeito |
|---|---|---|
| `sample_drop` | `id` (u32) | Esquece o áudio `id`; instrumentos que o tocavam ficam sem áudio (vozes soando terminam). |
| `tempo` | `bpm` (f64), `tempos por compasso` (u32) | BPM limitado a 20–999, compasso a 1–32; preserva a posição em batidas e os limites do loop; repassa o andamento aos efeitos só se mudou. |
| `play` | nenhum | Liga o transporte a partir da posição atual. |
| `stop` | nenhum | Desliga; clipes descem em 10 ms, instrumentos soltam com release, automação volta ao estático. |
| `seek` | `batida` (f64) | Vai para a batida (mínimo 0); solta as notas do sequenciador. |
| `loop_set` | `ligado` (u32), `início` (f64), `fim` (f64) | Loop em batidas; só liga se `fim > início` (início e fim mínimos 0). |
| `metronome` | `ligado` (u32), `ganho` (f32) | Liga/desliga o clique e ajusta o ganho (padrão 0,6). |
| `tracks` | `quantidade` (usize) | Cria ou remove faixas até `quantidade` (0 a 1024; acima disso erro). Faixas novas nascem sem efeitos, sem envios, saindo no master. |
| `track` | `faixa` (usize), `ganho` (f32), `pan` (f32), `mudo` (u32), `solo` (u32) | Estado estático do canal; índice inexistente é ignorado. |
| `master` | `ganho` (f32), `pan` (f32) | Volume e balanço do master. |
| `clips_clear` | nenhum | Apaga todos os clipes. |
| `clip_add` | `faixa` (usize), `sample` (u32), `início` (f64, batidas), `offset` (f64, s), `duração` (f64, s), `ganho` (f32), `fade in` (f64, s), `fade out` (f64, s) | Acrescenta um clipe (sem validação de duração). |
| `track_kind` | `faixa` (usize), `tipo` (u32) | Só age se o tipo mudou: recria o instrumento nos padrões (envia antes dos `param`) e zera os estáticos; virar ou deixar de ser barramento refaz o roteamento. Tipo desconhecido fica sem instrumento. |
| `param` | `faixa` (usize), `id` (u32), `valor` (f32) | Parâmetro do instrumento; não finito é ignorado; guarda o estático e só repassa se o alvo não está sob automação. |
| `instrument_sample` | `faixa` (usize), `sample` (u32) | Áudio do sampler (0 = nenhum); id ainda não carregado fica guardado e é ligado quando chegar. |
| `zones_clear` | `faixa` (usize) | Apaga as zonas do sampler da faixa (volta ao áudio único) e zera os contadores de round-robin. Faixa que não é sampler ou índice inexistente: nada. As notas que soam terminam. |
| `zone_add` | `faixa` (usize), `sample` (u32), `nota base` (u32), `nota mínima` (u32), `nota máxima` (u32), `velocidade mínima` (u32), `velocidade máxima` (u32), `afinação em cents` (f32), `ganho em dB` (f32), `pan` (f32), `modo` (u32), `início` (f64, s), `fim` (f64, s), `início do loop` (f64, s), `fim do loop` (f64, s), `grupo` (u32) | **16 argumentos, a maior chamada.** Acrescenta uma zona ao sampler da faixa, tocando o áudio `sample` (o id de `sample_load`; pode chegar depois: a zona fica muda até o áudio chegar). Notas, velocidades e nota base passam por `min(127)`, grupo por `min(255)` e depois pelo `sanitized` (grupo até 63, velocidades 1..127, cents ±1200, ganho −60..24 dB, pan ±1); `modo` ≠ 0 é "até o fim"; `fim` ≤ 0 é o fim do áudio; o loop vale com `fim do loop > início do loop`, só no modo sustentado. Passa de 128 zonas: ignora. Em faixa que não é sampler não faz nada. |
| `notes_clear` | nenhum | Apaga as notas do sequenciador de todas as faixas (as que soam terminam no fim delas). |
| `note_add` | `faixa` (usize), `início` (f64), `duração` (f64), `altura` (u32), `velocidade` (f32) | Nota em batidas absolutas; altura > 127, início não finito ou duração ≤ 0 são ignorados; início mínimo 0; velocidade limitada a 0–1 (não finita vira 0,8). |
| `cc_clear` | nenhum | Apaga os eventos de controle (bend, modulação, pedal) de todas as faixas; as notas não são afetadas. Detalhes em [04](04-expressao-midi.md). |
| `cc_add` | `faixa` (usize), `controle` (u32: 1, 64 ou 128), `batida` (f64, absoluta), `valor` (f32) | Evento de controle do clipe; controle desconhecido ou valor não finito é ignorado. |
| `live_cc` | `faixa` (usize), `controle` (u32), `valor` (f32) | Controle ao vivo (roda, pedal); tocando, também entra no registro da gravação. |
| `live_bend` | `faixa` (usize), `valor` (f32, −1..1) | Pitch bend ao vivo; equivale a `live_cc` com o controle 128. |
| `live_on` | `faixa` (usize), `altura` (u32), `velocidade` (f32) | Nota ao vivo; velocidade ≤ 0 ou NaN vale `live_off`; altura > 127 ignorada; velocidade limitada a 1. |
| `live_off` | `faixa` (usize), `altura` (u32) | Solta a nota ao vivo. |
| `panic` | nenhum | Corta instrumentos, reseta todas as cadeias (faixas e master) e o metrônomo; o transporte segue. |
| `fx_count` | `faixa` (i32), `quantidade` (u32) | Slots da cadeia (−1 = master), até 16; os que sobram saem em fade. |
| `fx_set` | `faixa` (i32), `slot` (u32), `tipo` (u32) | Tipo do efeito no slot (0 esvazia); mesmo tipo não faz nada; slot ≥ 16 ignorado; troca por crossfade. |
| `fx_param` | `faixa` (i32), `slot` (u32), `id` (u32), `valor` (f32) | Parâmetro do efeito; slot ≥ contagem ou valor não finito são ignorados; trata o parâmetro de sidechain. |
| `fx_bypass` | `faixa` (i32), `slot` (u32), `ligado` (u32) | Bypass por crossfade. |
| `sends_count` | `faixa` (i32), `quantidade` (u32) | Envios da faixa, até 16 (o master, −1, é ignorado). |
| `send_set` | `faixa` (i32), `envio` (u32), `barramento` (i32), `nível` (f32), `pré-fader` (u32) | Envio para o barramento (índice da faixa) com nível linear (mínimo 0); índice ≥ 16 ignorado; um índice além do fim estica a lista; mudar o destino faz o nível entrar do zero; destino inválido é ignorado no roteamento. |
| `track_output` | `faixa` (i32), `destino` (i32) | Saída da faixa: −1 master ou barramento de índice maior; inválido vale como master. |
| `auto_clear` | nenhum | Apaga todas as lanes. |
| `auto_lane` | `faixa` (i32), `alvo` (u32), `slot` (u32), `id` (u32) | Cria uma lane e **devolve o índice** (u32) para `auto_point`. |
| `auto_point` | `lane` (u32), `batida` (f64), `valor` (f32), `curva` (f32) | Ponto ordenado na lane; batida mínima 0, curva limitada a −1..1; não finitos e lane inválida são ignorados. |
| `watch_fx` | `faixa` (i32), `slot` (i32) | Efeito cujo indicador vai em `fx_meter`; slot −1 desliga. |
| `watch_analyzer` | `faixa` (i32) | Faixa do analisador (−1 master, −2 desliga; abaixo de −2 vira −2); trocar limpa o anel. |
| `fx_meter` | nenhum | **Devolve** (f32) a redução de ganho em dB do efeito observado, 0 se nenhum. |
| `input_monitor` | `faixa` (i32), `ligado` (u32) | Monitora a entrada na faixa de áudio (faixa < 0 ignorada). |
| `rec_notes_start` | nenhum | Começa a registrar as notas ao vivo (do zero); só entram as tocadas com o transporte andando. |
| `rec_notes_stop` | nenhum | Para de registrar; as seguradas terminam na posição atual. |
| `capture_clear` | nenhum | Esquece as capturas; o próximo `process` com capturas prepara o render. |
| `capture_add` | `faixa` (i32) | **Devolve** (i32) o índice da captura, ou −1 (sem lugar ou faixa < −1). |
| `beat` | nenhum | **Devolve** (f64) a posição em batidas do próximo quadro que sai. |
| `playing` | nenhum | **Devolve** (u32) 1 se tocando, 0 se parado. |
| `loudness_reset` | nenhum | Zera o medidor de loudness do master: integrado, faixa, máximos de momentâneo e curto prazo e true peak. Os filtros K-weighting seguem com o sinal que veem (não gera transiente). |
| `loudness` | `tipo` (u32) | **Devolve** (f64) a medida do master depois do limitador: 0 momentâneo (LUFS), 1 curto prazo (LUFS), 2 integrado (LUFS), 3 true peak máximo (dBTP), 4 faixa de loudness (LU). −200 (`loudness::NONE`) = sem medida; tipo desconhecido também devolve −200. |

Chamadas fora de `apply` (levam ponteiro, cada hospedeiro tem função própria; lista `HOST_ONLY`, `api.rs:182`): `alloc`, `dealloc`, `init`, `process`, `sample_load`, `analyzer`, `set_input`, `rec_notes`, `captured`, `peaks`, `stretch_run`, `stretch_channel`, `stretch_free`, `detect_bpm`, `detect_confidence`. Chamar uma delas por `apply` é erro com mensagem específica; `init` diz que o motor nasce no hospedeiro.

`Call` (`api.rs:63`) é `Copy`, sem heap e com no máximo 96 bytes (era 64 até a `zone_add`, que leva uma `ZoneDef` inteira com quatro tempos em f64; teste `chamada_convertida_e_copia_simples`): um hospedeiro com thread de áudio valida na thread dele com `Call::parse` e manda o `Call` por uma fila sem trava; só o caminho de erro aloca (a mensagem).

### O medidor de loudness (`engine/src/loudness.rs`)

Contrato do que o medidor mede, para quem altera o motor ou compara com o cálculo em Dart (`app/lib/daw/loudness.dart`).

| Medida | `kind` | Definição |
|---|---|---|
| Momentâneo | 0 | Média da energia K-ponderada dos últimos 4 blocos de 100 ms (400 ms), em LUFS. Existe a partir de 400 ms de áudio. |
| Curto prazo | 1 | Idem com os últimos 30 blocos (3 s). Existe a partir de 3 s. |
| Integrado | 2 | Blocos de 400 ms a cada 100 ms (75% de sobreposição): passam pelo gate absoluto (−70 LUFS) e pelo relativo (−10 LU abaixo da média do que passou); média da energia do que sobrou. |
| True peak | 3 | Maior valor absoluto, dos dois canais, do sinal sobreamostrado 4× (FIR polifásico de 16 pontos por fase, janela de Kaiser com beta 7; a fase 0 é a própria amostra), desde o reset. |
| Faixa (LRA) | 4 | Distribuição do curto prazo com gate absoluto de −70 LUFS e relativo de −20 LU; percentil 95 menos percentil 10. |

Também guarda `momentary_max` e `short_term_max` (só `Meter::read`; nenhuma chamada da API os devolve).

**Algoritmo.**

- **K-weighting para qualquer taxa.** Dois biquads em f64, forma transposta II: prateleira de agudos (`f0` 1681,97 Hz, +3,9998 dB, `Q` 0,7072) e passa-altas (`f0` 38,135 Hz, `Q` 0,5003). Os coeficientes são calculados a partir dos protótipos analógicos com a transformada bilinear para a taxa do motor (`k_weighting(rate)`); a norma só tabela os de 48 kHz. Um teste confere 44,1, 48, 96, 192 e 22,05 kHz.
- **Energia.** Soma dos quadrados dos dois canais K-ponderados (peso 1 cada), média por bloco de 100 ms (`hop = rate × 0,1` quadros), guardada num anel de 30 posições. LUFS = `−0,691 + 10·log10(energia)`. Um canal só (`Meter::new(rate, 1)`) mede 3,01 dB abaixo do mesmo sinal nos dois.
- **Gates por histograma.** Integrado e faixa usam dois histogramas de 8000 faixas de 0,01 LU (−70 a +10 LUFS), cada faixa com a contagem e a soma das energias. A energia somada é exata; a quantização só decide de que lado do gate um bloco cai (erro de no máximo 0,01 LU). Por isso a thread de áudio não precisa guardar todos os blocos.
- **Cache.** `read` recalcula integrado e faixa só depois de um bloco fechado (`cache`); ler várias vezes por bloco não repete a soma dos histogramas.
- **Sanidade.** Amostra não finita conta como silêncio; nunca sai NaN nem infinito; tudo abaixo do piso vira −200.
- **Onde é alimentado.** No fim de `Engine::render`, depois do limitador e do `clamp(-1, 1)`, com o buffer final do master (`loudness.push(out_l, Some(out_r))`), exceto durante o pré-roll do render offline (`captures.priming`), que não é música. O metrônomo e a entrada monitorada entram na medida, porque estão antes do limitador.
- **Offline.** `loudness::measure(left, right, rate)` mede um trecho de uma vez e completa o true peak com 8 zeros no fim. O render offline do app **não** usa isso: ele traz os canais ao Dart, que mede com `loudness.dart` (ver [02](02-pontes-web-e-android.md)).

**Sem alocação no caminho de áudio.** O `Meter` aloca só em `Meter::new` (dois histogramas de 8000 posições, ~190 KB, na criação do `Engine`); `push`, `read` e `reset` não alocam. O teste `nao_aloca_depois_de_criado` usa `testalloc::count` e exige 0 alocações depois de criado; é um dos testes com essa prova, ao lado de `fm.rs`, `wavetable.rs` e das zonas do sampler (ver Tempo real). O ganho fixo de exportação não passa por aqui.

**Testes** (`cargo test -p jopendaw-engine loudness`, 20 testes no arquivo): seno de 1 kHz nos dois canais a −20 dBFS mede −20 LUFS (EBU Tech 3341, caso 1) e canal único −23,01; passa-altas e prateleira com a diferença esperada por frequência; ruído branco confere com a energia ponderada; silêncio, trecho curto e NaN; os gates; faixa de loudness; true peak entre amostras, de impulso e de DC; medidor ao vivo igual ao offline em qualquer fatiamento; reset; alocação zero; medida do `Engine` inteiro igual à offline; true peak depois do limitador.

### Limites e constantes

| Constante | Valor | Onde |
|---|---|---|
| `MAX_BLOCK` | 4096 quadros | `lib.rs:98` |
| `CHUNK` | 128 quadros | `lib.rs:105` |
| `AUTO_STEP` | 32 quadros | `lib.rs:114` |
| `STOP_FADE_SECS` | 10 ms | `lib.rs:120` |
| `WARMUP_SECS` | 50 ms | `lib.rs:109` |
| `NOTES_RESERVED` | 1024 notas por faixa (reserva inicial) | `lib.rs:124` |
| `POINTS_RESERVED` | 256 pontos por lane (reserva inicial) | `lib.rs:390` |
| `MAX_TRACKS` | 1024 (só em `apply`; o export do wasm não tem esse teto) | `api.rs:51` |
| `MAX_SLOTS`, `MAX_SENDS` | 16 e 16 | `mixer.rs:22`, `:25` |
| `STATIC_PARAMS` | 64 | `mixer.rs:29` |
| `MAX_REC_NOTES`, `MAX_CAPTURES` | 16 384 e 64 | `record.rs:16`, `:22` |
| `MAX_ZONES` | 128 zonas por sampler | `sampler_zones.rs:27` |
| `MAX_GROUPS` | 64 (grupos de round-robin 0..63) | `sampler_zones.rs:29` |
| `MAX_SLICES`, `FIRST_SLICE_NOTE` | 96 fatias, a partir da nota 24 (C1) | `sampler_zones.rs:31`, `:33` |
| `END_FADE_SECS` | 1 ms (descida no fim do trecho de uma zona sem loop) | `sampler_zones.rs:35` |
| `SMOOTH_SECS` (fader, porta do solo, envios) | 5 ms | `mixer.rs:9` |
| `FADE_SECS` (transições da cadeia) | 10 ms | `mixer.rs:13` |

## Decisões e por quê

- **Grade de fatias fixa (`CHUNK`).** Fatiar o bloco nos múltiplos de 128 do relógio do motor, e não no tamanho do bloco do hospedeiro, torna o render offline idêntico amostra por amostra em qualquer tamanho de bloco, e é o que permite comparar a web (128) com o Android (blocos de outro tamanho) e com a exportação.
- **Eventos no quadro exato.** Notas e fins de nota fatiam o pedaço em vez de arredondar para o início do bloco; a posição é f64 e a conversão usa `ceil` com folga de 1e-6.
- **O note off vem de `held`, não da lista.** O app reenvia todas as notas a cada edição, então a lista muda no meio de uma nota. Manter o conjunto do que foi disparado evita notas presas.
- **Estático guardado ao lado da automação.** Em vez de a automação escrever por cima do parâmetro, o motor guarda o último valor do app e o devolve ao parar; mexer no botão durante a automação não se perde.
- **Suavização por polo e rampas curtas em tudo que muda.** Volume, pan, mudo, solo e envios seguem o alvo em 5 ms; efeitos entram, saem e trocam por crossfade de 10 ms; o stop desce os clipes em 10 ms. Nenhuma troca discreta estala.
- **Cadeia que dorme.** Sem entrada e com saída em silêncio a cadeia não roda, mas só depois de passar pelo tempo máximo de cauda (`tail_secs`); assim um delay de 4 s não é cortado.
- **Limitador de segurança sempre depois do metrônomo, fora da cadeia do master.** O clique não ganha o reverb do master mas segue o volume; nada passa de −0,3 dBFS, e o clamp final em ±1 pega o resto.
- **Sanidade contra NaN em três pontos.** Sai da cadeia de uma faixa (silêncio e `reset` do efeito), sai da cadeia do master (idem) e antes do limitador (troca por 0). Um efeito que explode não contamina barramentos e master para sempre.
- **Loudness medido depois do limitador, dentro do motor; a normalização fica fora.** O medidor lê o que vai para a saída, no mesmo ponto do medidor de pico do master, e a tela do mixer só o mostra. A normalização da exportação (ganho constante até um alvo de LUFS, com teto de true peak) é feita **em Dart puro** (`app/lib/daw/loudness.dart`) sobre os canais que o render devolveu, por três razões: funciona igual na web e no Android sem chamada nova nas pontes, dispensa recompilar o `engine.wasm` e os `.so` para o que o usuário mais precisa (o arquivo certo), e o ganho é uma multiplicação que não pertence ao caminho de áudio. O preço são duas implementações do mesmo cálculo (motor e Dart) que precisam concordar; `app/test/loudness_test.dart` e `app/test/export_loudness_test.dart` as conferem. Diferenças conhecidas: o Dart guarda todos os blocos e aplica os gates exatos (o motor usa histogramas de 0,01 LU) e não calcula faixa de loudness.
- **Plataforma fora do crate.** O crate não sabe de threads nem de E/S, então o mesmo código roda no worklet, no AAudio e no render offline nativo, e os testes rodam no desktop.

## Tempo real: alocação e travas

A regra do código (declarada em `effect.rs`, `instrument.rs`, `dsp.rs`, `record.rs`, `analyzer.rs`): depois de criado, nada no caminho de áudio aloca, trava ou faz E/S. O que foi verificado nesta revisão, lendo o código de produção (fora de `#[cfg(test)]`) de todos os arquivos de `engine/src/`:

**Caminho por bloco (`process` → `run` → `render` → `render_track`, `Lane::render`, `Chain::process`, `render` de instrumentos e `process` de efeitos, limitador, analisador, metrônomo, capturas): nenhuma alocação encontrada.** Não há `Vec::new`/`vec!`/`push`/`collect`/`Box::new`/`format!`/`clone` de dados nesse caminho. Os `push` que aparecem em `sampler.rs:173`, `distortion.rs` (`Ring::push`) e `fx/limiter.rs:66` são métodos de estruturas de tamanho fixo, não de `Vec`; os `busy.clone()` de `synth.rs:726`, `fm.rs:579` e `wavetable.rs:777` clonam um iterador. Buffers de faixa, chaves, `Scratch`, filas do limitador, linhas de atraso e anéis são alocados em `new`.

**Onde alocações e liberações acontecem, e por que são aceitas** (todas em comandos, entre blocos, ou no preparo):

| Onde | O quê | Observação |
|---|---|---|
| `set_track_count` (`lib.rs:764`) | buffers, cadeias, `Vec` das faixas | ~40 KB por faixa; só ao mudar a quantidade |
| `set_track_kind` (`:825`) | cria e destrói o instrumento (`Box`); o primeiro wavetable gera as tabelas (`OnceLock`, alguns ms) | só quando o tipo muda |
| `set_fx` (`:982`) | `effect::create` aloca linhas de atraso e anéis no tamanho máximo (delay, reverb, limitador, compressor) | só ao pôr ou trocar efeito |
| `Chain::collect` (`mixer.rs:596`) | libera o efeito antigo (`Drop` de `Box<dyn Effect>`) | roda dentro de `prepare`, na thread de áudio, entre blocos; é uma liberação, não alocação, mas não é de custo zero |
| `add_clip` (`:814`) | `Vec::push` na lista de clipes, sem reserva inicial (`Vec::new()` em `Engine::new`) | realoca de tempos em tempos ao reenviar o documento com muitos clipes; ver Armadilhas |
| `add_note` (`:890`) | `push`; reserva de 1024 por faixa | passar disso realoca |
| `add_zone` (`:921`) | `Vec::push` na lista de zonas do sampler, reservada com 128 em `Sampler::new` | não realoca; passar de 128 descarta a zona |
| `add_point` (`:1196`) | `insert`; reserva de 256 por lane | passar disso realoca |
| `clear_automation` (`:1172`) | `push` em `auto_restore`, reserva de 64 | passar disso realoca |
| `add_lane` (`:1182`) | `AutoLane::new` reserva 256 pontos | só ao criar lane nova |
| `capture_add` (`record.rs:222`) | `Stereo::new(MAX_BLOCK)` por captura | só no comando |
| `load_sample` (`:741`) / `drop_sample` | `HashMap::insert` e liberação do `Arc<Sample>` | no hospedeiro; liberar o último `Arc` de um áudio grande acontece na thread de áudio |
| `start_render` (`:1442`) | `std::mem::replace` com `Vec::new()` (não aloca) e processamento de silêncio | uma vez por render |
| `Engine::new` | `limiter_latency` aloca `vec!` de ≥ 4096 quadros para medir o limitador | só na criação |

**Prova automática.** `engine/src/testalloc.rs` instala, só em teste, um `#[global_allocator]` que conta as alocações de uma thread dentro de `count(|| ...)`. Ele é usado em exatamente quatro testes: `nao_aloca_depois_do_new` de `fm.rs:1184` e de `wavetable.rs:1361` (notas em 16 alturas, troca de parâmetros, 50 renders, `note_off`, `release_all`, `silence`, exigindo 0 alocações), `zonas_nao_alocam_na_thread_de_audio` de `sampler_zones_tests.rs` (limpa e recria 128 zonas com round-robin e loop, dispara 70 notas, religa e desliga áudios por id, `release_all`, `silence`; exige 0 alocações no sampler com zonas) e `nao_aloca_depois_de_criado` de `loudness.rs` (o `Meter` sozinho: 4 s de seno em blocos de 128, `read`, `reset`, `push` de 4 s de uma vez e `read_kind`, exigindo 0 alocações; não cobre o `Engine` inteiro). **Não há teste de contagem para `synth`, `drums`, o `sampler` de áudio único, nenhum dos 12 efeitos, `Chain` nem o `Engine` inteiro**: para esses, a garantia de "sem alocação no áudio" é a leitura do código descrita acima e a convenção, não um teste (`(não confirmado)` por execução).

O `panic = "abort"` do perfil `wasm` e o `catch_unwind` do perfil `android` estão em `Cargo.toml` da raiz; um pânico no `process` derruba o worklet (web) ou vira silêncio e código de erro (Android).

## Como testar

```bash
cargo test -p jopendaw-engine                 # o motor inteiro (perfil test com opt-level 2)
cargo test -p jopendaw-engine api::           # só o protocolo de chamadas
cargo test -p jopendaw-engine nao_aloca       # os testes de alocação zero (fm e wavetable)
cargo clippy -p jopendaw-engine --all-targets
cargo fmt --check
```

Os testes ficam no fim de cada arquivo (`#[cfg(test)]`): `lib.rs` tem 57 (transporte, notas no quadro exato, loop, solo com barramentos, automação, sidechain, NaN, gravação, capturas e a igualdade entre tamanhos de bloco), `api.rs` 6, `sampler_zones_tests.rs` 42 (zonas, camadas, round-robin, loop, trecho, áudio que chega e sai, alocação zero, fatiamento por número e por transientes com rajadas sintéticas) e cada instrumento e efeito tem os seus. Testes do contrato com o Dart: `synth.rs:1502`, `fm.rs:1209` e `wavetable.rs:1394` leem `app/lib/daw/instruments.dart` e conferem faixas, padrões e ids (pulam com aviso se o arquivo não existir). Para tocar de verdade e medir picos no navegador, ver [03-build-teste-e-depuracao.md](03-build-teste-e-depuracao.md).

## Armadilhas conhecidas

- **Mudou o motor, recompile os hospedeiros.** `./engine/build-web.sh` e `./engine/build-android.sh` (NDK 28); commite `app/web/engine/engine.wasm` e os três `libjopendaw_engine.so` juntos. Sem recompilar os `.so` o Android fica com o motor velho, e mudo se o `apply` for novo. Detalhes em [02-pontes-web-e-android.md](02-pontes-web-e-android.md).
- **Binários sem o loudness (caso da fase 8, resolvido em `357b6fc`).** O commit `dca27bc` declarava no corpo que `engine.wasm` e os três `.so` não tinham sido recompilados; até a integração o medidor do mixer ficava em `—` e o botão `Zerar` não agia (web: o worklet confere `typeof w.loudness === 'function'` e não publica nada; Android: `jd_loudness` não existia e o Dart desiste uma vez, `_noLoudness`). A normalização da exportação sempre funcionou, porque é Dart puro. Ver [02](02-pontes-web-e-android.md).
- **Chamada nova no motor exige espelho em todos os lados.** Export no `engine/wasm/src/lib.rs` (o teste `apply_conhece_todos_os_exports_sem_ponteiro_do_wasm` obriga a entrada em `CALLS` e `Call`), `Call::parse` e `Call::apply`, o lado Android (`jd_*` e `jd_calls`), o `host.js`/`worklet.js` e o `engine_ffi.dart`.
- **Binários sem as zonas (caso da fase 8, resolvido em `357b6fc`).** Os commits `b6b7abb`, `6f3d245` e `6e5fa7b` (zonas do sampler) não recompilaram os binários; só faixas com zonas eram afetadas (web: `TypeError` em `w.zone_add` perdia o resto da lista; Android: o `.so` com `ARGS_MAX = 12` recusava a lista que contivesse um `zone_add` de 16 argumentos). A integração recompilou os quatro binários.
- **Zonas: o app reenvia todas a cada edição.** `_syncZones` (`controller.dart`) manda `zones_clear` seguido de todos os `zone_add` sempre que a lista de chamadas de zona muda (uma zona editada, ou o áudio de uma zona que acabou de carregar e ganhou id). Como `clear_zones` zera `rr`, o ciclo do round-robin recomeça a cada edição (`(não confirmado)` que isso seja audível). Editar com notas soando é seguro: as vozes guardam o próprio áudio e trecho.
- **Zonas: o parâmetro `one_shot` do instrumento não vale, mas a interface ainda o usa.** Com zonas, quem manda é o `one_shot` de cada zona; o painel do app, porém, continua apagando a `Soltura` e desenhando o envelope curto conforme o parâmetro do instrumento, e o teclado da tela continua marcando o `root` do instrumento.
- **Zonas: a `Sustentação` do ADSR vale também para vozes `one_shot`.** Fatias e golpes decaem com `Sustentação` abaixo de 1 (o ADSR é o do instrumento, comum a todas as zonas).
- **Fatiamento duplicado em Rust e Dart.** `slice_points`/`slice_zones` do motor não são chamados por nenhum hospedeiro; o app usa a porta em Dart. Mudou um limiar em um, mude no outro.
- **Ids de parâmetro são contrato.** Não reutilize nem renumere; id novo vai no fim e precisa entrar em `SPECS` do instrumento e em `instruments.dart`/`effects.dart`. Só synth, FM e wavetable têm teste que confere o Dart; bateria, sampler e os 12 efeitos não (`(não confirmado)` se há outra conferência).
- **Ordem dos comandos importa.** `track_kind` antes de `param`; `fx_set` antes de `fx_param`; `tracks` antes de tudo que indexa faixa. `fx_param` com slot ≥ contagem é ignorado; `set_fx` e `send_set` esticam sozinhos.
- **`tracks` sem teto no wasm.** O teto de 1024 vive só em `apply` (Android e render nativo); o export `tracks` do wasm aceita qualquer `usize`.
- **`track_kind` desconhecido** (≥ 7) deixa a faixa sem instrumento e sem ser barramento; os clipes dela ainda tocam.
- **Latência dos efeitos não é compensada.** `distortion` e o efeito `limiter` atrasam o sinal de sua faixa (`LATENCY`; lookahead até 10 ms) sem compensação entre faixas, e o limitador de segurança do master só é compensado no render offline (`out_delay`).
- **Chave de sidechain de barramento** chega com um pedaço (até 128 quadros) de atraso.
- **Andamento e loop em f64.** `pos` e os limites do loop são quadros fracionários; a fração que passa do fim do loop é carregada. Testes que medem amostras em quadros exatos desligam o limitador (`set_limiter(false)`) por causa do lookahead.
- **A automação só roda tocando.** Parado, valem os estáticos, mesmo com lanes cheias; um `param` durante a reprodução de um alvo automatizado só muda o estático (o que vale ao parar).
- **Comentário desatualizado em `lib.rs:5`:** cita "o Oboe no Android"; o hospedeiro nativo usa AAudio (`engine/android/src/platform/aaudio.rs`, carregado em tempo de execução).
- **Comentário desatualizado em `engine/wasm/src/lib.rs:137`:** descreve `track_kind` com tipos 0 a 4; existem também 5 (FM) e 6 (wavetable).
