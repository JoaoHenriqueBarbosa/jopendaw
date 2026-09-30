# Modulação na prática

> Quatro movimentos que a aba `Modulação` faz sozinha: um wobble de baixo preso ao andamento, um tremolo de pad, um auto-pan de sintetizador e um bombeio falso com o seguidor de envelope; cerca de 10 minutos por cenário, mais o tempo de ouvir e acertar de ouvido.

Os números de tempo são exemplos a 120 BPM em 4/4 (1 batida = 0,5 s; 1 compasso = 2 s). Troque pelos seus. Os valores de parâmetro (faixas de corte, dB do volume, graus de pan) são contas feitas a partir do código e das tabelas dos capítulos; o que soa bom, isso é ouvido: **nada foi ouvido** por quem escreveu este guia, e o único teste no Chrome relatado pela sessão de código foi o `Tremolo no volume` num pad (o pico do motor oscilou entre 0,021 e 0,216) `(não confirmado ao ouvido)`. Cada cenário parte de um projeto que já toca, como o de [Primeira batida do zero](primeira-batida-do-zero.md).

## Ingredientes

| Recurso | Para quê aqui | Capítulo |
|---|---|---|
| Aba `Modulação` do painel de baixo (ao lado de `Efeitos`) | Criar e ajustar os moduladores da faixa selecionada | [06g Modulação](../manual/06g-modulacao.md#onde-fica) |
| `Presets` (`Wobble no corte`, `Tremolo no volume`, `Auto-pan`, `Vibrato de afinação`) | Começar de um modulador já ligado | [06g Presets](../manual/06g-modulacao.md#presets) |
| Cartão do LFO: forma, `Livre`/`Andamento`, divisão, `Profundidade`, `Fase`, `Bipolar`/`Unipolar` | O movimento em si | [06g Cartão do LFO](../manual/06g-modulacao.md#cartão-do-lfo) |
| Cartão do seguidor de envelope: `Ganho`, `Ataque`, `Soltura` | Um movimento que responde ao nível do som da faixa | [06g Cartão do seguidor de envelope](../manual/06g-modulacao.md#cartão-do-seguidor-de-envelope) |
| A barra de profundidade de cada destino (−100% a +100%) | Quanto do curso do controle o modulador percorre | [06g Destinos e profundidade](../manual/06g-modulacao.md#destinos-e-profundidade) |
| `Modular…` (botão direito num knob; botão direito do mouse no fader e no pan) | Ligar um controle específico, sem passar pelos presets | [06g O menu `Modular…`](../manual/06g-modulacao.md#o-menu-modular) |
| Sintetizador (`Reese`, `Pad quente`) e o knob `Corte` | O baixo e o pad dos exemplos | [04a Sintetizador](../manual/04a-sintetizador.md) |
| Barramento e saída da faixa | Reunir bumbo e pad no cenário 4 | [06 Mixer, saída e nome](../manual/06-mixer.md#saída-e-nome) |
| Fader, pan e medidor do canal | Ler o nível em que a modulação parte | [06 Mixer](../manual/06-mixer.md) · [06b Medidores](../manual/06b-analisador-e-medidores.md) |

## Antes de começar: o que a profundidade quer dizer

A profundidade de um destino é uma **fração do curso inteiro** do controle, na escala em que o knob anda; o LFO bipolar a 100% vai de −profundidade a +profundidade em volta do valor que o knob mostra. O knob não se mexe (mostra a base) e ganha um anel ciano. Detalhes em [06g](../manual/06g-modulacao.md#destinos-e-profundidade).

| Controle | Curso | Profundidade típica | O que você ouve (base → faixa percorrida) |
|---|---|---|---|
| `Corte` (Hz, log) | 20 Hz a 20 kHz, ~10 oitavas | ±30% | Base 700 Hz: de 88 Hz a 5,6 kHz |
| `Volume` (fader) | 0 a +6 dB, curva cúbica (0 dB em 79% do curso) | ±15% | Base 0 dB: de −5,5 dB a +4,5 dB; base −6 dB: de −13,1 dB a −0,4 dB |
| `Pan` | −1 a +1 | ±50% | Base no centro: de todo à esquerda a todo à direita |

## Cenário 1: wobble de baixo preso ao andamento

**Resultado:** um baixo cujo filtro abre e fecha no tempo da música, oito vezes por compasso (colcheias: 4 Hz a 120 BPM), sem desenhar um ponto de automação.

### Passo a passo

1. Numa faixa de sintetizador, escolha o preset `Reese` (grupo `Baixos`: `Corte` em 700 Hz, `Ressonância` 22%) e escreva ou grave algumas notas longas num clipe.
2. Selecione a faixa e abra a aba `Modulação` (o assunto mostra `<faixa> · sem moduladores`).
3. `Presets`, `Wobble no corte`. Nasce o cartão `1 · LFO senoide · 1/8` com o destino `Instrumento · Corte` em `+10%` do curso (±1 oitava).
4. Dê play e arraste a barra do destino para abrir ou fechar o movimento: `+30%` leva o corte de 88 Hz a 5,6 kHz (com a base de 700 Hz).
5. Volte ao painel `Instrumento` e suba a `Ressonância` de 22% para 45%: o "uau" fica mais nítido. O knob `Corte` continua em 700 Hz, com o anel ciano ao redor.
6. Para trocar o ritmo, abra a lista de divisões do cartão: `1/4` (2 Hz), `1/8 pontilhada` (2,7 Hz) ou `1/16` (8 Hz).

### Variações

- **Cada vez mais aberto:** desenhe uma automação de `Corte` subindo por 8 compassos ([Mixagem e automação, passo 3](mixagem-e-automacao.md#3-automatizar-um-filtro-para-a-subida-da-música)); a curva move a base e o wobble soma por cima, sem passar dos 20 kHz.
- **O filtro respirando junto com a ressonância:** no cartão, `Destino` e `Instrumento · Ressonância`, em `+10%` (de 12% a 32% com a base em 22%). Cada LFO tem até 4 destinos.
- **Sem instrumento com `Corte` (FM, sampler):** ponha um efeito `Filtro` na cadeia ([06c](../manual/06c-painel-de-efeitos.md)); o preset acha o `Corte` dele.
- **Forma:** `Triângulo` (curva reta, mais "mecânica"), `Dente de serra` (sobe e cai de uma vez, como um "ba-dum" de bombeio) ou `Quadrada` (liga e desliga o filtro).

### Por que funciona

O LFO em `Andamento` tira a fase da **posição em batidas** da música, não de um relógio: cada ciclo cai sempre no mesmo lugar do compasso, depois de um seek, do loop e mesmo com o andamento mudando (o mapa de andamento com rampa vale). Em Hz o corte é uma escala de oitavas, então ±30% é uma varredura de várias oitavas simétrica **para o ouvido**, e o instrumento recebe o valor novo a cada 32 quadros (cerca de 0,7 ms a 48 kHz) `(não confirmado ao ouvido que isso baste para o filtro não "escadear")`.

### Se der errado

| Sintoma | Causa provável | O que fazer |
|---|---|---|
| O wobble parece "chapado" em cima (fica aberto boa parte do ciclo) | A base está perto do topo do curso e o destino passa dos 20 kHz, onde a onda é presa (o preset, com ±1 oitava, já evita isso no `Corte` padrão) | Baixe a profundidade ou o `Corte` base (700 Hz é uma base equilibrada) |
| Com o preset `Baixo ácido (303)` o wobble fica preso no fundo | O `Corte` base de 260 Hz com `+40%` desce além dos 20 Hz, o mínimo do knob, e a onda fica cortada embaixo | Suba o `Corte` base para 700 Hz, ou desça a profundidade para `+25%` (com 260 Hz de base, de 46 Hz a 1,5 kHz) |
| Arrastar a barra ou um knob do cartão com o projeto tocando faz o wobble "engasgar" | (Corrigido) o motor mantém a fase do LFO e o nível do seguidor quando a modulação é reenviada | Se ainda ouvir, use `Andamento` (a fase vem da batida) e avise |
| Nada acontece | O clipe está sem notas, ou a barra do destino está em `0%`, ou o controle não é um destino (`Onda`, `Tipo`, `Vozes`) | Confira o cartão: a linha do destino mostra `+40%` e o nome `Instrumento · Corte` |

## Cenário 2: tremolo de pad

**Resultado:** o volume de um pad pulsando a 6 Hz, de forma discreta; ou preso ao andamento.

### Passo a passo

1. Selecione a faixa do pad (por exemplo o preset `Pad quente`) e abra a aba `Modulação`.
2. `Presets`, `Tremolo no volume`: LFO livre, senoide, 6 Hz (`1 · LFO senoide · 6,0 Hz`), destino `Volume` em `+15%`. Com o fader em 0 dB o volume vai de −5,5 dB a +4,5 dB.
3. Para um tremolo mais lento e macio, mude o knob `Taxa` para 3,5 Hz (arrastar na vertical, ou botão direito e digitar `3,5`) e a barra do destino para `+8%`.
4. Para só **descer** a partir do nível que você acertou (sem passar dele): troque o LFO para `Unipolar` e ponha o destino em `-15%` (o volume varia entre o valor do fader e −15% do curso abaixo dele).
5. Ouça com o resto da música e acerte a profundidade: pelo caminho de dB, o mesmo `+15%` varia mais quanto mais baixo o fader (base −6 dB: de −13,1 a −0,4 dB).

### Variações

- **Preso ao andamento:** troque para `Andamento` e `1/8 tercina` (2/3 de colcheia; a 120 BPM dá 6 Hz, o mesmo do preset, mas agora acompanha o andamento se ele mudar).
- **Tremolo quadrado (gate rítmico):** forma `Quadrada` e `1/16`: o volume liga e desliga com transições de cerca de 1 ms. Em `Unipolar` com destino `-100%` o volume vai a zero (silêncio) na metade do ciclo.
- **Em vez do efeito `Tremolo`:** [06d Tremolo](../manual/06d-efeitos-referencia.md#10-tremolo) faz o mesmo dentro da cadeia; a modulação tem a vantagem de reunir volume, corte e pan num mesmo LFO (até 4 destinos).

### Por que funciona

O destino de volume anda na **curva do fader** (ganho = 2 × posição³), então a profundidade é uma fração do curso do fader, não de dB. Por isso, com o fader mais baixo, a mesma porcentagem varia mais em dB. O valor é somado à posição do fader (a base) e preso entre o mínimo e o máximo do curso (−∞ e +6 dB); nada é gravado no fader, e apagar o modulador devolve o volume ao valor dele.

### Se der errado

| Sintoma | Causa provável | O que fazer |
|---|---|---|
| O tremolo estala | Uma forma com salto (`Dente de serra`, `Quadrada`, `Sample & hold`) em taxa alta | Elas já passam por um alisamento de ~1 ms; troque para `Senoide` ou `Triângulo` se ainda incomodar |
| O volume passa de 0 dB nos picos | A base do fader mais a profundidade sobe além de 0 dB (o topo é +6 dB) | Abaixe o fader ou passe o LFO para `Unipolar` com destino negativo |
| O fader não se mexe | Não é para se mexer: ele mostra a base | Confira o pontinho ciano no canto do fader e o cartão da aba |
| No celular não acho o `Modular…` do fader | Toque longo no fader, no pan ou no nível de envio (e no mini fader do cabeçalho) abre o menu com `Modular…` | Ou use o `Destino` do cartão (lista `Volume`, `Pan`, `Envio → nome`) |

## Cenário 3: auto-pan de sintetizador

**Resultado:** um sintetizador que passeia entre as caixas em ciclos de 2 batidas (1 volta por segundo a 120 BPM).

### Passo a passo

1. Numa faixa de instrumento com o pan no centro, abra a aba `Modulação`.
2. `Presets`, `Auto-pan`: LFO em `Andamento`, divisão `1/2`, destino `Pan` em `+50%`. Como o curso do pan vai de −1 a +1 e a base está em 0, os `+50%` percorrem tudo, de `E100` a `D100`.
3. Toque: cada ciclo dura 2 batidas (1 s a 120 BPM), esquerda, direita e de volta.
4. Para um passeio mais discreto, baixe a profundidade para `+20%` (de `E20` a `D20`). Para ir mais devagar, troque para `1 compasso` (4 batidas, 2 s por volta).
5. Para um par em oposição, duplique a faixa (a modulação vai junto) e ponha `Fase` em 50% (180°) na cópia: uma sobe no pan enquanto a outra desce.

### Variações

- **Salto de lado a lado:** forma `Quadrada`; o pan troca de lado a cada meio ciclo, com a transição alisada em ~1 ms.
- **Com pan de partida fora do centro:** a base do pan soma com o LFO e o resultado é preso em ±1; com o pan em `E30`, o `+50%` vai de `E100` (preso na ponta) a `D70`.
- **Mexer também no nível de um envio:** no cartão, `Destino` e `Envio → <barramento>` (até 4 destinos por LFO); o envio anda na curva do fader, como o volume.

### Por que funciona

O pan é linear de −1 a +1, então o LFO bipolar a 100% ao redor do centro varre tudo; a profundidade menor estreita o passeio em torno do valor base. Em `Andamento` a fase acompanha as batidas, e a `Fase` decide onde no ciclo o som começa (0° parte do centro indo para a direita: a senoide começa em 0 e sobe).

### Se der errado

| Sintoma | Causa provável | O que fazer |
|---|---|---|
| Não escuto passeio nenhum | A profundidade do destino está em `0%`, ou a faixa não está tocando | Confira a linha `Pan` no cartão (`+50%`) e ouça em fones |
| Soa como corte, não como passeio | Forma `Quadrada` | Mude para `Senoide` ou `Triângulo` |
| O passeio fica torto, mais para um lado | A base do `Pan` (ou a curva de automação dele) está fora do centro: o LFO soma em volta dela e é preso nas pontas | Ponha o pan no centro ou baixe a profundidade |

## Cenário 4: bombeio falso com o seguidor de envelope

**Resultado:** o grupo bumbo mais pad "abaixa" a cada golpe do bumbo e volta na soltura, sem usar o `Sidechain` do compressor.

Antes: o seguidor de envelope mede o nível **da própria faixa** (depois dos efeitos e antes do fader) e só move controles da própria faixa. Ele **não** escuta o bumbo de outra faixa para abaixar o pad: isso é o `Sidechain` do compressor ([Efeitos em combinação, receita 3](efeitos-em-combinacao.md#receita-3-sidechain-pumping-com-o-bumbo)), a forma certa quando o pad deve responder só ao bumbo. O que o seguidor faz é abaixar o **grupo** a cada golpe mais forte que ele mede.

### Passo a passo

1. Crie um barramento (`Grupo`) e mande para ele a saída da faixa do bumbo e a do pad ([06 Mixer, saída e nome](../manual/06-mixer.md#saída-e-nome)). O bumbo deve ser bem mais forte que o pad, para o pico do grupo ser o do bumbo.
2. Selecione o barramento e abra a aba `Modulação`; `Adicionar`, `Seguidor de envelope`.
3. No cartão: `Ganho` ×2 (o padrão), `Ataque` 5 ms, `Soltura` 150 ms (três constantes de tempo, cerca de 450 ms, quase uma batida a 120 BPM), `Unipolar`.
4. `Destino`, `Volume`; deslize a barra até `-30%`. Com a leitura cheia (pico do grupo em 0,5, ou −6 dBFS, ×2), o volume do grupo cai até cerca de −12 dB e volta com a soltura.
5. Olhe o medidor do barramento: se o pico dos golpes for de −12 dBFS (0,25), o `Ganho` de ×2 só enche metade da escala; suba para ×4 para a leitura chegar a 1.
6. Ajuste `Soltura` ao andamento e `Ataque` à quantidade de transiente do bumbo que deve passar: `Ataque` maior deixa mais do golpe inteiro antes do volume cair.

### Variações

- **Sem seguidor, exato no tempo:** numa faixa (ou no grupo) ponha o fader uns 6 dB abaixo do nível final, adicione um LFO `Andamento` `1/4`, forma `Dente de serra`, `Unipolar`, destino `Volume` em `+16%`: o volume sobe do nível do fader (−6 dB) até 0 dB durante cada tempo e cai de uma vez no seguinte. É um bombeio que não depende do sinal: cai no tempo mesmo sem bumbo tocando.
- **Só o filtro pulsando, não o volume:** no barramento, um efeito `Filtro` (`Passa-baixa`) e o seguidor mexendo no `Corte` com profundidade negativa. Cuidado: o seguidor lê depois dos efeitos, então o filtro fechando diminui o nível lido (realimentação de um passo); prefira o volume ou o nível de um envio.
- **O bombeio verdadeiro:** `Compressor` no pad com `Sidechain` no bumbo ([06d, o sidechain](../manual/06d-efeitos-referencia.md#o-sidechain-o-que-ele-exige)).

### Por que funciona

O seguidor guarda o maior pico de cada passo de 32 quadros e o alisa com o `Ataque` (sobe) e a `Soltura` (desce); a saída, 0 a 1, multiplica a profundidade negativa do destino de volume. Como o seguidor lê **antes do fader** (e o volume do barramento é o fader dele), abaixar o volume não faz a leitura cair: não há laço de realimentação. A leitura é em amplitude, não em dB, então só os sons fortes mexem no volume; por isso o `Ganho` normaliza os picos do grupo.

### Se der errado

| Sintoma | Causa provável | O que fazer |
|---|---|---|
| Nada se move | O seguidor não tem destino, ou o grupo está quase mudo (leitura perto de 0) | Ligue `Volume` no `Destino` e suba o `Ganho` |
| O bumbo também é abaixado | O seguidor mede o grupo inteiro, bumbo incluído | É a limitação deste truque; para poupar o bumbo use o `Sidechain` do compressor no pad |
| O volume oscila sem parar | `Soltura` curta demais para o sinal (segue cada oscilação) | Suba a `Soltura` para 150 a 300 ms |
| A modulação cai no pad todo o tempo, mesmo sem bumbo | O pad domina o pico do grupo | Abaixe o pad ou suba o bumbo; o seguidor não separa os dois |
| Com o seguidor só na faixa do pad, o pad não reage ao bumbo | Ele lê a faixa a que pertence, não o bumbo | Ligue o seguidor num barramento que reúne os dois |

## Resumo em uma linha por cenário

| Cenário | Preset ou modulador | Destino e profundidade |
|---|---|---|
| Wobble de baixo | `Wobble no corte` (`1/8`) | `Instrumento · Corte` em `+30%` (base 700 Hz) |
| Tremolo de pad | `Tremolo no volume` (6 Hz) | `Volume` em `+15%` (ou `Andamento` `1/8 tercina`) |
| Auto-pan | `Auto-pan` (`1/2`) | `Pan` em `+50%` (ou `+20%` mais discreto) |
| Bombeio falso | `Seguidor de envelope` (`Ataque` 5 ms, `Soltura` 150 ms) no barramento | `Volume` em `-30%` |

## Ver também

- [06g Modulação](../manual/06g-modulacao.md): cada botão da aba, os limites e o que a modulação não alcança.
- [07 Automação](../manual/07-automacao.md): a curva por baixo, com a modulação somando por cima.
- [Mixagem e automação](mixagem-e-automacao.md) e [Efeitos em combinação](efeitos-em-combinacao.md): o `Sidechain` de verdade, a subida de filtro por automação.
- [Controlador MIDI e MIDI learn](controlador-midi-e-midi-learn.md): o controlador move a base de um controle modulado.
