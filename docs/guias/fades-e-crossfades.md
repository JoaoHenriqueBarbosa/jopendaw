# Fades e crossfades na prática

> Três emendas de áudio resolvidas com a curva certa: juntar duas tomadas de voz sem buraco nem pancada, repetir um loop sem clique e fazer um pad entrar (e sair) sem tranco; cerca de 10 minutos por cenário, mais o tempo de ouvir e acertar de ouvido.

Os números são exemplos a 120 BPM em 4/4 (1 batida = 0,5 s; 1 compasso = 2 s). Troque pelos seus. O que depende do programa (rótulos, condições do crossfade automático, fórmulas das curvas) vem do código; os tamanhos de fade recomendados (10 a 50 ms para emenda, alguns segundos para pad) são pontos de partida musicais, **não** regras do programa, e não foram conferidos ao ouvido `(não confirmado ao ouvido)`. Toda a mecânica aqui foi conferida no código e em testes automáticos, e não vista funcionando no navegador `(testado só por testes automáticos)`.

## Ingredientes

| Recurso | Para quê aqui | Capítulo |
|---|---|---|
| Alça de fade in (canto de cima à esquerda do clipe) e alça de fade out (canto de cima à direita) | Dar tamanho ao fade, arrastando | [03 Áudio e clipes](../manual/03-audio-e-clipes.md#o-clipe-na-linha-do-tempo) |
| Menu do clipe (botão direito, toque longo no celular): `Fade de entrada…` e `Fade de saída…` | Digitar o tamanho exato do fade, em ms ou batidas | [03 Tamanho do fade por campo](../manual/03-audio-e-clipes.md#tamanho-do-fade-por-campo) |
| Menu do clipe: `Fade de entrada: …` e `Fade de saída: …` (`Suave (padrão)`, `Potência constante`, `Exponencial`, `S (seno cosseno)`) | Escolher a curva de cada lado | [03 Fades e crossfade](../manual/03-audio-e-clipes.md#fades-e-crossfade) |
| Crossfade automático (ao soltar um arrasto que move ou apara) e os itens `Crossfade neste clipe` e `Crossfade em toda a faixa` | Emendar dois clipes com sobreposição | [03 Fades e crossfade](../manual/03-audio-e-clipes.md#crossfade-automático) · [02b Timeline e clipes](../manual/02b-timeline-e-clipes.md#cortar-duplicar-apagar-e-sobreposição) |
| `Cortar no cursor` (`S`), `Apagar` (`Delete`), `Duplicar` (`Ctrl+D`), `Alt` ao arrastar (sem encaixe na grade), zoom (`Ctrl` + roda) | Preparar os clipes e posicioná-los com precisão | [03 Áudio e clipes](../manual/03-audio-e-clipes.md) · [02b Timeline e clipes](../manual/02b-timeline-e-clipes.md) |
| Automação de volume da faixa (opcional) | Um fade que vale para a faixa inteira, em vez de um clipe | [Mixagem e automação, passo 4](mixagem-e-automacao.md#4-fazer-um-fade-de-volume-por-automação) |

## Antes de começar: qual curva, em uma tabela

`x` é o progresso do fade (0 = silêncio, 1 = cheio); a saída é a mesma curva vista de trás. Fórmulas e valores completos em [03 Fades e crossfade](../manual/03-audio-e-clipes.md#as-quatro-curvas).

| Curva | Ganho | No meio do fade | Use para |
|---|---|---|---|
| `Suave (padrão)` (era `Linear`) | `x²` | 0,25 (−12 dB) | O fade de sempre; **não** para crossfade (a soma dos dois clipes afunda 6 a 9 dB no meio) |
| `Potência constante` | `sin(x·π/2)` | 0,71 (−3 dB) | Crossfade de dois sons **diferentes** (soma potência 1) |
| `S (seno cosseno)` | `(1 − cos πx)/2` | 0,5 (−6 dB) | Crossfade de dois sons **iguais** (soma amplitude 1) e fade de ponta sem quina |
| `Exponencial` | `(e^(4x) − 1)/(e^4 − 1)` | 0,12 (−18 dB) | Entrada em crescendo; saída que "esvai". Não para crossfade |

## Cenário 1: emendar duas tomadas de voz

**Resultado:** a boa frase da tomada 1 e a boa frase da tomada 2 numa faixa só, sem clique e sem o volume afundar na emenda. Curva recomendada: **`Potência constante`**, que é a que o crossfade automático já usa, e fade curto de **10 a 50 ms** (aqui, 30 ms).

Ponto de partida: duas tomadas da mesma frase em duas faixas de áudio (`Áudio 1` e `Áudio 2`); a tomada 1 é boa até o fim da palavra "vamos" (em 12,000 s = batida 24) e a tomada 2 é boa dali em diante.

1. Ponha o cursor no fim da parte boa da tomada 1 (clique na régua; aproxime o zoom com `Ctrl` + roda até ver a onda). Escolha um ponto de pouca energia (um respiro ou o fim de uma consoante). Selecione o clipe da tomada 1 e aperte `S`.
2. Selecione a metade da direita (a parte ruim) e aperte `Delete`. A tomada 1 agora termina no ponto do corte.
3. Na tomada 2, ponha o cursor no começo da parte boa (o mesmo tipo de ponto de pouca energia), selecione o clipe e aperte `S`; selecione a metade da esquerda e aperte `Delete`.
4. Arraste a metade que sobrou da tomada 2 **na diagonal**, segurando `Alt` (sem encaixe na grade): para cima, até a raia de `Áudio 1`, e para a direita, até o começo dela entrar cerca de **30 ms** na cauda da tomada 1. Aqui 30 ms = 0,06 batida, ou seja, o clipe termina na batida 24 e a tomada 2 começa na 23,94. O áudio só muda para outra faixa **de áudio**, e a soltura precisa ser por cima da cauda da tomada 1 (o que sobrou da parte ruim já foi apagado no passo 2, então o cruzamento é de borda).
5. Solte. O crossfade sai sozinho: a tomada 1 ganha um fade de saída de 30 ms e a tomada 2 um fade de entrada de 30 ms, os dois em `Potência constante`, e nenhum é aparado. A linha branca de cada clipe mostra a rampa (curta: aproxime o zoom para vê-la).
6. Ponha o cursor uns 2 s antes da emenda e toque com `Espaço`. Se a emenda ainda soa (uma "pancada" ou o nível pulando), aumente ou diminua a sobreposição arrastando o clipe da direita de novo (os fades acompanham o tamanho da sobreposição, e só mudam quando você solta), ou desfaça com `Ctrl+Z` e escolha outro ponto de corte.

### Variações

- **Emenda dentro de uma nota sustentada** (o mesmo timbre e a mesma altura dos dois lados): abra o menu de cada clipe e escolha `Fade de saída: S (seno cosseno)` na tomada 1 e `Fade de entrada: S (seno cosseno)` na tomada 2. Escolher a curva torna o fade seu: mover o clipe depois não o redimensiona mais.
- **Tomadas de um mesmo clipe gravado em loop** (selo `N tomadas`): a troca de tomada pelo selo troca o áudio do clipe inteiro, não emenda pedaços. Para emendar pedaços de tomadas diferentes, o caminho é o acima (cortar, apagar, levar para a mesma faixa).
- **Sem espaço para sobrepor** (o corte foi rente demais nos dois lados): aparar a borda esquerda da tomada 2 mais para a esquerda (o começo do arquivo continua lá) e a borda direita da tomada 1 mais para a direita (só até o fim do arquivo) devolve material para o cruzamento.

### Por que funciona

Duas tomadas da mesma voz não têm relação de fase no ponto da emenda: a onda de uma não "soma" com a da outra, o que se soma é a **potência**. `Potência constante` foi desenhada para isso (`g_entrada² + g_saída² = 1` em todo instante), então o volume percebido não afunda nem estufa. Com `Suave (padrão)`, a soma de potência cai a 0,125 no meio (−9 dB): um "buraco" de volume na emenda. Com fade de 30 ms a diferença entre as curvas é curta, e por isso o fade curto pesa mais que a curva na maioria das emendas de voz `(não confirmado ao ouvido)`.

### Se der errado

| Sintoma | Causa provável | O que fazer |
|---|---|---|
| Solto o clipe e o de baixo é aparado, sem fades | Sobreposição maior que **metade do menor clipe**; ou um clipe **contido** no outro; ou um fade seu na ponta da emenda (fade de saída na tomada 1 ou de entrada na tomada 2) | Diminua a sobreposição; apague ou zere o fade seu (arraste a alça até 0) e solte de novo; ou use `Crossfade neste clipe` no menu, que não tem o teto e passa por cima de fade seu (o aviso na tela diz quantos crossfades aplicou) |
| Depois de soltar, o clipe da direita "mordeu" o começo da palavra | O ponto de corte da tomada 2 caiu dentro da palavra | `Ctrl+Z` e corte antes; ou apare a borda esquerda para trás |
| Ainda há clique | Fade curto demais para a onda no ponto de corte | Aumente a sobreposição para uns 50 ms, ou mude o ponto de corte para um lugar mais calmo |

## Cenário 2: um loop repetido sem clique

**Resultado:** um clipe de 1 compasso (2 s) repetido quatro vezes sem o estalo que aparece quando o fim da onda (com valor diferente de zero) salta para o começo. Curva recomendada: **`S (seno cosseno)`**, com fade de **5 a 10 ms** em cada ponta (aqui, 5 ms).

1. Importe o loop (`Ctrl+I`) e ouça a repetição: selecione o clipe, aperte `Ctrl+D` uma vez e toque no ponto em que as duas cópias se encontram. Se estala, siga; se não, o loop já está bom.
2. Aproxime bastante o zoom no fim do clipe (`Shift+Z` enquadra o clipe; depois `Ctrl` + roda) até que 5 ms sejam alguns pixels. Arraste a alça do canto de cima à direita para a esquerda por uns 5 ms (0,01 batida a 120 BPM). A alça não tem encaixe.
3. Faça o mesmo no começo com a alça do canto esquerdo, **a menos que o loop comece por um ataque** (bumbo, palheta): nesse caso deixe o começo sem fade, para o transiente não perder o ataque, e faça só o fade de saída.
4. Botão direito no clipe, `Fade de saída: S (seno cosseno)` e, se pôs fade de entrada, `Fade de entrada: S (seno cosseno)`.
5. Apague a cópia do passo 1 (`Delete` com ela selecionada), selecione o original e aperte `Ctrl+D` três vezes (a cada vez a cópia nova fica selecionada e a próxima sai colada no fim dela): cada cópia leva o fade e a curva do original. Toque.

### Variações

- **Pad ou nota sustentada, e o estalo vira um "buraco" audível com fade curto:** o crossfade real precisa de sobreposição, e ela encurta o período do loop pelo tamanho da sobreposição. Para manter a grade, o arquivo precisa ter áudio **além** do fim do loop: com a cópia já no compasso seguinte, estenda a borda direita do clipe original por 20 a 50 ms sobre a cabeça da cópia (só dá até o fim do arquivo). Ao soltar, o crossfade sai sozinho, **desde que as pontas do cruzamento não tenham fade seu** (zere antes os fades curtos do passo 2 e 3 dessas duas pontas, senão eles bloqueiam o crossfade automático; o item `Crossfade neste clipe` do menu passa por cima deles). Troque as duas curvas por `S (seno cosseno)` no menu (os dois lados são o mesmo som).
- **Loop de bateria:** fade de saída de 5 ms, sem fade de entrada; o ataque do primeiro tempo fica intacto.

### Por que funciona

O estalo nasce do salto brusco de nível quando a onda termina em um valor e a repetição recomeça em outro. Levar a ponta do clipe a zero com um fade de 5 ms tira o salto. `S` é a curva sem "quina" nas duas pontas (a inclinação é zero em 0 e em 1): o começo do fade e a chegada ao volume cheio são suaves, o que importa justamente para um fade tão curto. Para o crossfade de um loop contra ele mesmo, os dois lados são o mesmo áudio (correlacionado): as amplitudes se somam, e o `S` soma amplitude constante (`g_entrada + g_saída = 1`), enquanto `Potência constante` levantaria uns 3 dB no meio do cruzamento (a soma de `sin` e `cos` chega a 1,41).

### Se der errado

| Sintoma | Causa provável | O que fazer |
|---|---|---|
| A repetição ainda estala | 5 ms é pouco para essa onda, ou o loop tem componente grave forte | Tente 10 ms; ou mude o ponto de corte do clipe para um cruzamento por zero |
| O ritmo "engasga" no começo do loop | O fade de entrada comeu o ataque | Tire o fade de entrada (alça até 0) e fique só com o de saída |
| Estendo a borda direita e o clipe de baixo é aparado em vez de virar crossfade | Sobrou um fade seu numa das pontas do cruzamento (o de saída do original ou o de entrada da cópia) | Zere esses dois fades e solte de novo, ou use `Crossfade neste clipe` |
| A borda direita não estende | O arquivo acabou: a borda não passa do fim do arquivo | Use um arquivo com sobra depois do fim do loop |

## Cenário 3: a entrada suave de um pad (e a saída)

**Resultado:** um pad de 8 compassos (16 s) que sobe do silêncio em 2 compassos (4 s) e some nos 2 compassos finais. Curvas recomendadas: entrada **`S (seno cosseno)`** (ou `Exponencial` para um crescendo dramático) e saída **`Exponencial`**.

1. Selecione o clipe do pad. Aperte `Z` para enquadrar e use as barras de compasso da régua como medida (ou, para um valor exato, botão direito no clipe e `Fade de entrada…` / `Fade de saída…`, que aceitam ms ou batidas).
2. Arraste a alça do canto de cima à esquerda para a direita até 2 compassos de distância (8 batidas = 4 s a 120 BPM em 4/4). A rampa sombreada mostra o que o fade tira. Ou, sem arrastar: botão direito, `Fade de entrada…`, seletor `batidas`, digite `8` e `Aplicar` (o valor é limitado ao que sobra do clipe).
3. Arraste a alça do canto de cima à direita para a esquerda até 2 compassos antes do fim do clipe (também 4 s), ou use `Fade de saída…` com `8` batidas.
4. Botão direito, `Fade de entrada: S (seno cosseno)`. A linha branca passa a desenhar um S: sobe devagar, ganha inclinação no meio e chega ao topo suave.
5. Botão direito de novo, `Fade de saída: Exponencial`. A linha desenhada cai depressa no começo do fade e vai a zero devagar.
6. Toque do compasso anterior à entrada até o fim e ajuste de ouvido: fade de entrada mais longo se ainda "aparece" de repente, ou troque a entrada para `Exponencial` se quiser que ela seja quase inaudível no começo e acelere no fim (a `Exponencial` está em −30 dB a 25% do fade e −9 dB a 75%).

### Variações

- **Entrada mais dramática (riser):** `Fade de entrada: Exponencial` com um fade longo (4 a 8 compassos). A curva sobe devagar e acelera, terminando em subida forte: o fim do fade é o ponto de mais energia. Fica bem quando algo entra logo depois (uma batida).
- **Manter a curva de fábrica:** `Suave (padrão)` (`x²`, o que era rotulado `Linear`) também começa muito suave e ganha força no fim; a `S` chega ao topo mais macia. Use `Suave (padrão)` se quer que o pad soe igual ao de projetos antigos.
- **Fade da faixa inteira, com vários clipes:** a automação de volume da faixa faz um fade só para todos os clipes: [Mixagem e automação, passo 4](mixagem-e-automacao.md#4-fazer-um-fade-de-volume-por-automação). O fade do clipe é por clipe.

### Por que funciona

`Suave (padrão)` (`x²`) e `Exponencial` deixam o começo quase mudo e concentram a subida no fim (de −12 dB a 50% na `Suave (padrão)`; −18 dB na `Exponencial`), enquanto `S` distribui a subida no meio e chega ao volume cheio com inclinação zero, sem "quina". Na saída a curva é a mesma vista de trás: `Exponencial` cai depressa no começo e desce devagar até zero, o desenho de uma nota que se apaga sozinha. Como no pad não há outro clipe cruzando, a discussão de soma de potência ou amplitude dos crossfades não se aplica: só importa o formato da subida.

### Se der errado

| Sintoma | Causa provável | O que fazer |
|---|---|---|
| Não consigo arrastar a alça | O canto tem só 14 × 14 px; com o dedo, mire no círculo branco | Aproxime o zoom ou use o mouse |
| A curva não muda o som | O clipe não tem fade nesse lado (tamanho 0) | Puxe a alça primeiro; a escolha da curva fica guardada, mas só se ouve com fade |
| Apaguei um dos dois clipes de um crossfade e quero saber o que foi do fade do outro | `Apagar` revê os fades automáticos: o do clipe que ficou volta ao tamanho e à curva de antes na hora (até a fase 15 ele ficava até o próximo arrasto) `(testado só por testes automáticos)` | Nada a fazer; `Ctrl+Z` traz o clipe e o crossfade de volta |
| Cortei um clipe com `S` e o fade da emenda sumiu | `Cortar no cursor` zera o fade de saída da metade da esquerda e o de entrada da direita e limpa a marca de automático desses lados | Refaça o fade da ponta que quiser (alça ou `Fade de entrada…`) |

## Resumo em uma linha por caso

| Caso | Curva | Tamanho |
|---|---|---|
| Emenda de voz (sons diferentes) | `Potência constante` | 10 a 50 ms |
| Emenda dentro de nota sustentada (mesmo som) | `S (seno cosseno)` | 20 a 50 ms |
| Estalo na repetição de um loop | `S (seno cosseno)` | 5 a 10 ms |
| Entrada de pad | `S (seno cosseno)` ou `Exponencial` | 2 a 4 compassos |
| Saída de pad ou de nota | `Exponencial` | 1 a 4 compassos |
| Fade de um clipe sozinho, como sempre foi | `Suave (padrão)` | o que quiser |
