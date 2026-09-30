# Loops e polaridade de clipes

> Três usos do mudo, da fase invertida e do loop que cada clipe de áudio ganhou na fase 20: esticar 1 compasso numa cama de 8 sem copiar, conferir a fase de dois microfones numa caixa e comparar tomadas (A/B) mutando clipes; cerca de 10 minutos por cenário, mais o tempo de ouvir.

Os números são exemplos a 120 BPM em 4/4 (1 batida = 0,5 s; 1 compasso = 4 batidas = 2 s; 8 compassos = 32 batidas = 16 s). Troque pelos seus. O que depende do programa (rótulos, limites, o que o corte faz num loop) vem do código da fase 20 (`3a27233`) e está em [03 Mudo, fase invertida e loop do clipe](../manual/03-audio-e-clipes.md#mudo-fase-invertida-e-loop-do-clipe); **nenhum dos passos abaixo foi feito no app rodando** `(testado só por testes automáticos)`. O que depende de como o material soa (qual polaridade fica melhor, se a emenda do loop estala) só se decide de ouvido.

## Ingredientes

| Recurso | Para quê aqui | Capítulo |
|---|---|---|
| Menu do clipe (botão direito, toque longo no celular): `Repetir em loop (estique a borda direita)` (selo `L`) | Fazer o trecho do clipe se repetir ao esticar a borda direita, até 1 hora | [03 Loop do clipe](../manual/03-audio-e-clipes.md#loop-do-clipe) |
| Menu do clipe: `Silenciar o clipe` (tecla `0`, selo `M`) | Tirar um clipe do som sem apagá-lo, e voltar com um toque | [03 Mudo do clipe](../manual/03-audio-e-clipes.md#mudo-do-clipe) |
| Menu do clipe: `Inverter a fase (polaridade)` (selo `Ø`) | Trocar o sinal de um clipe para ele somar com outro sem se anular | [03 Inverter a fase](../manual/03-audio-e-clipes.md#inverter-a-fase-polaridade) |
| Borda direita do clipe e grade `Compasso` | Esticar o loop de compasso em compasso | [02b Raias e clipes](../manual/02b-timeline-e-clipes.md#raias-e-clipes) · [02 Transporte](../manual/02-transporte.md) |
| `Cortar no cursor` (`S`), `Apagar` (`Delete`), `Fade de saída…` e `Fade de entrada…` | Partir a cama, tirar um pedaço, dar uma saída suave | [03 Áudio e clipes](../manual/03-audio-e-clipes.md) · [03 Tamanho do fade por campo](../manual/03-audio-e-clipes.md#tamanho-do-fade-por-campo) |
| Importar vários arquivos de uma vez | Cada arquivo vira um clipe em faixa própria, todos no mesmo ponto | [03 Importar](../manual/03-audio-e-clipes.md#importar) |
| Loop do transporte (`Shift+L`, `L`) | Ouvir o mesmo trecho em repetição enquanto se compara (não é o loop do clipe) | [02 Transporte](../manual/02-transporte.md) |
| Efeito `Utilitário` (`Inverter esq.` e `Inverter dir.`) | Polaridade da **faixa inteira**, quando serve para todos os clipes dela | [06d Utilitário](../manual/06d-efeitos-referencia.md#5-utilitário) |

Três coisas que têm nome parecido e não são a mesma: o **loop do clipe** (este guia; o trecho se repete dentro do clipe), o **loop do transporte** (a região da régua que o play repete) e o **warp** (estica o áudio ao andamento, [03b](../manual/03b-warp-e-altura.md)). E `Ø` (polaridade, troca o sinal) não é `R` (toca de trás para a frente).

## Cenário 1: um compasso de loop esticado numa cama de 8 compassos

**Resultado:** um loop de bateria (ou de pad) de 1 compasso cobrindo 8 compassos, **sem copiar e colar**: um clipe só, com emendas tracejadas, que você ainda corta, muta ou estende. Uns 5 minutos.

Ponto de partida: um arquivo de exatamente 1 compasso a 120 BPM (2,000 s), chamado aqui `cama.wav`, e um projeto novo em 120 BPM, 4/4.

1. Ponha o cursor no começo (`Home`) e importe `cama.wav` (`Importar` ou `Ctrl+I`). O clipe nasce numa faixa de áudio, com 4 batidas (1 compasso) de largura. Ajuste a grade da barra para `Compasso`.
2. Botão direito no clipe, `Repetir em loop (estique a borda direita)`. O item ganha uma marca de visto e o selo do clipe passa a mostrar `L`. Nada muda ainda no som: o trecho que repete é o clipe como ele está agora (2,000 s).
3. Arraste a **borda direita** do clipe (8 px com o mouse, 16 px com o dedo) até o começo do compasso 9, a batida 32. Com a grade em `Compasso` ela encaixa de compasso em compasso. O clipe passa a ter 16 s e mostra **sete linhas tracejadas** brancas (nas batidas 4, 8, 12, 16, 20, 24 e 28), uma em cada emenda.
4. Dê uma saída suave à cama: botão direito, `Fade de saída…`, `Tamanho` `500` ms, `Aplicar`. O fade vale só na **última repetição** (o compasso 8), porque um fade de saída num loop fecha o clipe inteiro.
5. Toque desde o começo. Se na emenda do compasso 1 para o 2 (e nas outras) há um estalo, veja [Se der errado](#se-der-errado).
6. Para fazer uma pausa de dois compassos (um break) sem apagar nada, ponha o cursor na batida 16 (clique na régua com a grade em `Compasso`), selecione o clipe e aperte `S`; depois ponha o cursor na batida 24, selecione o clipe da direita (o que vai da batida 16 em diante) e aperte `S` de novo. Saem três clipes em loop: compassos 1 a 4, compassos 5 e 6, compassos 7 e 8. Selecione o do meio e aperte `0`: ele fica mudo (selo `M L`, onda cinza) e a cama volta no compasso 7. O fade de saída de 500 ms ficou no último pedaço.

### Variações

- **Loop de outro andamento.** Se `cama.wav` tem 100 BPM no projeto de 120, ligue antes o warp (`Warp e altura…`, `Detectar`, [03b](../manual/03b-warp-e-altura.md)): o clipe encolhe para 100 ÷ 120 da duração e o loop repete o trecho já esticado. A ordem entre warp e loop não importa: o trecho que repete é guardado em segundos do áudio original.
- **Loop de 2 compassos com uma virada.** Importe o trecho de 2 compassos (4,000 s), ligue o loop e estique até o compasso 17: 8 repetições do par. Ou mude só o último: corte em uma emenda (batida 56 do exemplo de 16 compassos) e troque o pedaço final por outro clipe.
- **Variação de timbre.** Duplique a faixa (`Duplicar a faixa`, [02b](../manual/02b-timeline-e-clipes.md)), ponha outro loop de 1 compasso na cópia e faça o mesmo: duas camas sincronizadas que você muta e desmuta com `0`, clipe a clipe, para montar a arrumação.
- **Tocar de trás para a frente.** `Inverter o áudio` (`Warp e altura…`, selo `R`) num clipe em loop toca cada repetição invertida. Use uma duração que seja **múltipla** do trecho: com a última repetição cortada ao meio, o app toca o fim do trecho invertido em vez do começo `(lido do código; não ouvido)`.

### Por que funciona

O app não ensina o laço ao motor: cada repetição vira um clipe do motor com o mesmo trecho, colado na anterior (no exemplo, oito clipes de 2,000 s nas batidas 0, 4, 8 e assim por diante). O teste do motor conferiu, numa rampa, que isso não deixa buraco nem salto entre as repetições. Como o trecho é guardado em segundos do áudio original, o mesmo loop serve com ou sem warp. E como cada pedaço cortado numa emenda volta a ser um clipe inteiro, o corte do passo 6 não muda o som: só dá a você um clipe por trecho para mutar.

### Se der errado

| Sintoma | Causa provável | O que fazer |
|---|---|---|
| A borda direita não passa do fim do arquivo | O loop não está ligado (sem `L` no selo) | Liga pelo item do menu; só com o loop ligado a borda passa do fim do arquivo |
| Estalo em cada emenda | As repetições são coladas, **sem fade nem crossfade** entre elas: o fim do trecho e o começo não se encontram num ponto parecido | Apare o trecho (borda esquerda ou direita, com o loop ligado) até um ponto que fecha bem, como um compasso redondo, ou faça a repetição com `Duplicar` e fades curtos como em [Fades e crossfades, cenário 2](fades-e-crossfades.md#cenário-2-um-loop-repetido-sem-clique) |
| O corte da batida 16 fez três clipes, não dois | O cursor não caiu exatamente na emenda (com a grade em `Livre`, por exemplo): o corte no meio de uma repetição faz a sobra sem loop mais o loop que recomeça | O som é o mesmo; para evitar, use a grade `Compasso` ao pôr o cursor ([03 Cortar um clipe em loop](../manual/03-audio-e-clipes.md#cortar-um-clipe-em-loop)) |
| O som muda quando outro clipe é solto por cima do loop | O aparo por cima não respeita a fase do trecho `(lido do código; não ouvido)` | Corte o loop antes (`S` na emenda) ou ponha o outro clipe em outra faixa |
| A cama some depois de um tempo, num trecho muito curto esticado | O teto de 4096 repetições por clipe | Use um trecho maior, ou encadeie dois clipes |
| Fade de entrada grande deixa um degrau no compasso 2 | O fade vale só na primeira repetição e fica cortado nela | Mantenha o fade de entrada menor que 1 compasso (2 s no exemplo) |

## Cenário 2: conferir a fase de dois microfones numa caixa

**Resultado:** dois microfones da mesma caixa (um em cima, um embaixo) somando com corpo, em vez de se anularem. Cerca de 10 minutos, mais o tempo de ouvir.

Ponto de partida: duas gravações da mesma caixa feitas ao mesmo tempo, em arquivos separados (`caixa-topo.wav` e `caixa-fundo.wav`), por exemplo de um gravador multipista ou de outro programa. O app grava uma entrada por vez, então o par precisa chegar como arquivos ([03c Gravação](../manual/03c-gravacao.md)).

1. `Importar` e escolha os **dois arquivos de uma vez**. Cada um vira um clipe em uma faixa nova, `caixa-topo` e `caixa-fundo`, os dois começando no mesmo ponto (o cursor), como deveriam para a fase ser comparável. Não arraste nenhum dos dois por enquanto.
2. No [mixer](../manual/06-mixer.md), deixe as duas faixas com o mesmo volume e o pan no centro; a comparação só vale com os mesmos níveis.
3. Escolha um trecho com caixa e um pouco de silêncio em volta. Marque-o na régua arrastando (ou selecione o clipe e aperte `Shift+L`, que marca o loop do transporte no clipe inteiro e o liga) e toque com `Espaço`. Ouça como **está**.
4. Ouça cada microfone sozinho: clique no clipe `caixa-fundo` e aperte `0` (selo `M`, onda cinza): só o de cima soa. Aperte `0` de novo (o clipe continua selecionado) para o fundo voltar; clique no clipe `caixa-topo` e aperte `0`: só o de baixo soa; `0` outra vez e os dois voltam. Você sabe agora o que cada um traz (topo: ataque e estalo; fundo: corpo e esteira).
5. Com os dois soando (nenhum selo `M`), ouça a soma. Se a caixa soa fina e oca, com o corpo sumido, as fases estão brigando.
6. Clique no clipe `caixa-fundo`, botão direito, `Inverter a fase (polaridade)` (selo `Ø`, onda espelhada). Toque o mesmo trecho e compare. Ligue e desligue o item duas ou três vezes, sem pressa: **fique com a posição em que o corpo da caixa aparece**. Um microfone voltado para o lado oposto da pele costuma chegar com a polaridade oposta, por isso o de baixo é o candidato a inverter (conhecimento geral de gravação, não do app: confira de ouvido).
7. Olhe também o medidor do master ([06b](../manual/06b-analisador-e-medidores.md#medidor-de-loudness-do-master-m-s-i-tp)): com a polaridade que soma, o nível da caixa tende a subir; com a que cancela, tende a cair `(não confirmado com material real)`.
8. Antes de exportar, confirme que nenhum clipe ficou com `M` (mudo) sem querer: o mudo do clipe **não** vai ao arquivo.

### Variações

- **A faixa inteira, não um clipe.** Se todos os clipes do microfone de baixo estão com a polaridade errada, em vez de inverter um a um ponha o efeito `Utilitário` na faixa com `Inverter esq.` e `Inverter dir.` em `Sim` ([06d](../manual/06d-efeitos-referencia.md#5-utilitário), receita `Fase invertida`).
- **Só um trecho da música.** A fase é por clipe: corte (`S`) o clipe do microfone de baixo e inverta só o trecho em que ele briga.
- **Atraso entre microfones.** Se o microfone de baixo está mais longe, o som chega alguns milissegundos depois, e inverter não basta. Aproxime o zoom (`Ctrl` + roda) e arraste o clipe de baixo para a esquerda com `Alt` (sem encaixe na grade) até a onda da caixa alinhar com a do topo; só então compare a polaridade.
- **Teste de cancelamento.** Para ouvir a polaridade "em estado puro", duplique a faixa de um microfone, ponha o clipe da cópia em `Ø` e toque as duas juntas: o som some quase por inteiro (na mesma posição, clipes idênticos em faixas diferentes cancelam; o teste do motor mede menos de 1e-6). Apague a cópia depois.

### Por que funciona

Dois microfones captam o mesmo golpe em instantes e polaridades um pouco diferentes; ao somar, as componentes que chegam em oposição se anulam e o som afina. Inverter a polaridade de um dos dois troca quais componentes se somam e quais se anulam. No app, `Ø` guarda o ganho do clipe positivo e manda ao motor o ganho com o sinal trocado, então vale para todo o clipe, com fades, e não atrasa nada (não é um efeito de fase com atraso). O mudo do clipe (`0`) serve para a parte de ouvir um microfone de cada vez sem tocar no fader.

### Se der errado

| Sintoma | Causa provável | O que fazer |
|---|---|---|
| Inverti e não ouvi diferença | A polaridade sozinha não muda o som; só muda o que se soma com outro sinal | Ouça os dois microfones juntos, não o clipe invertido isolado |
| Inverto e fica pior | Os dois já estavam em fase, ou o atraso entre eles é o problema | Volte (`Ctrl+Z`) e alinhe o clipe de baixo no tempo antes de julgar a polaridade |
| Os dois arquivos entraram em pontos diferentes | O cursor mudou entre duas importações, ou foram importados em momentos diferentes | Importe os dois juntos, com o cursor no mesmo ponto |
| Um clipe não soa e eu não sei por quê | Mudo do clipe ligado (`M` no selo e onda cinza) | Selecione o clipe e aperte `0` |
| O `0` não faz nada | Não há clipe de áudio selecionado (clipe de notas não tem mudo de clipe), ou você está digitando num campo | Clique no clipe de áudio e tente de novo |

## Cenário 3: A/B de tomadas mutando clipes

**Resultado:** escolher entre três tomadas de voz de um verso ouvindo uma de cada vez, sem apagar nenhuma e sem mexer em fader, e depois montar o melhor de cada uma. Uns 15 minutos.

Ponto de partida: três arquivos com o mesmo verso de 16 compassos (32 s, batidas 0 a 64), `tomada-a.wav`, `tomada-b.wav` e `tomada-c.wav`, todos começando juntos no início do projeto.

1. `Importar`, escolha os três de uma vez: saem três faixas com um clipe cada, no mesmo ponto. Dê nomes às faixas se quiser ([02b](../manual/02b-timeline-e-clipes.md)).
2. Selecione o clipe da tomada A e aperte `Shift+L`: o loop do transporte cobre o verso inteiro (16 compassos). Ou arraste na régua para repetir só a frase que você quer comparar.
3. **Rodada A:** clique no clipe da B e aperte `0`, clique no da C e aperte `0`. Os selos mostram `M` e as ondas ficam cinza. Toque: só a A soa. Ouça duas ou três voltas.
4. **Rodada B:** clique na A e aperte `0` (ela fica muda), clique na B e aperte `0` (ela volta). Toque: só a B soa.
5. **Rodada C:** repita com a C. Volte à A se ficou em dúvida; o custo é um toque de tecla.
6. Para montar o melhor de cada uma, ponha o cursor na batida 32 (o fim do verso 1 e o começo do 2). Com o clipe da A selecionado, aperte `S`; faça o mesmo em B e C (cada clipe é cortado à parte). Fique, por exemplo, com a A no verso 1 e a B no verso 2: a metade da direita da A, a da esquerda da B e as duas metades da C recebem `0` (mudas), e as outras duas ficam soando.
7. Como o corte **zera** os fades da emenda, dê uma emenda suave nos dois pedaços que soam: no pedaço da A (metade da esquerda), `Fade de saída…` `20` ms; no da B (metade da direita), `Fade de entrada…` `20` ms. Os dois estão em faixas diferentes: não há crossfade automático entre faixas.
8. Toque a virada do verso 1 para o 2 e ouça. Quando decidir de vez, apague (`Delete`) o que ficou mudo, ou guarde como reserva: os clipes mudos não vão ao arquivo exportado.

### Variações

- **Só comparar dois efeitos.** O mesmo vale para duas versões de um mesmo instrumento gravado: um clipe com o `Inverter a fase` ligado contra outro sem, mutando o que você não quer ouvir.
- **Mudo do clipe contra mudo da faixa.** Se a comparação for entre *faixas inteiras* (cada uma com seus efeitos), o `M` da faixa ([06 Mixer](../manual/06-mixer.md#solo-e-mudo)) é mais rápido; o mudo do clipe vale quando só um pedaço da faixa entra na comparação.
- **Um clipe por tomada numa faixa só.** Se as tomadas estão uma depois da outra na mesma faixa, não precisa mutar: o que soa é o que está na linha do tempo. O mudo do clipe é para tomadas que cobrem o mesmo trecho em faixas diferentes.

### Por que funciona

Um clipe mudo continua no arranjo, com os cortes, os fades e o warp dele: o app só deixa de mandá-lo ao motor, por isso nada do mixer muda e o som de uma rodada para outra é comparável ao milésimo de nível. Como o render e a exportação usam as mesmas chamadas do que se ouve, o arquivo sai exatamente com os clipes que estão soando quando você exporta. O desfazer guarda cada troca (`Silenciar clipe` e `Reativar clipe` no histórico), então voltar a uma rodada anterior também é `Ctrl+Z`.

### Se der errado

| Sintoma | Causa provável | O que fazer |
|---|---|---|
| Aperto `0` e o clipe errado muda | O `0` age no clipe **selecionado**, não no da faixa selecionada | Clique no clipe antes (a borda fica branca) |
| Ouço as três ao mesmo tempo | Ninguém está mudo: o selo só aparece nos clipes com `M` | Confira o selo `M` e a onda cinza em cada clipe |
| Exportei e falta uma parte da voz | Um clipe ficou mudo | Desmute (`0`) antes de exportar; abra o arquivo no `Importar` para conferir |
| Um estalo na virada do verso 1 para o 2 | Os pedaços estão em faixas diferentes e o corte zera os fades da emenda | Fades de 10 a 30 ms nos dois pedaços (passo 7); para uma emenda por crossfade, ponha os dois pedaços na **mesma faixa** ([Fades e crossfades, cenário 1](fades-e-crossfades.md#cenário-1-emendar-duas-tomadas-de-voz)) |
| Mudei o mudo com a música tocando e ouvi um estalo | O clipe sai (ou entra) do motor na hora, sem rampa | Mude o mudo com o transporte parado, ou em um ponto de pouca energia `(não confirmado ao ouvido)` |

## Resumo em uma linha por caso

| Caso | Receita |
|---|---|
| 1 compasso em 8 sem copiar | `Repetir em loop (estique a borda direita)`, grade `Compasso`, borda direita até o compasso 9, `Fade de saída…` 500 ms |
| Break de 2 compassos numa cama | `S` nas emendas (batidas 16 e 24), `0` no pedaço do meio |
| Microfone de baixo da caixa | `Inverter a fase (polaridade)` no clipe dele; ouvir com e sem, ficar com o que tem corpo; alinhar no tempo antes, se for o caso |
| Comparar tomadas | `0` nas que não quer ouvir, uma rodada por tomada; cortar e mutar para montar |
