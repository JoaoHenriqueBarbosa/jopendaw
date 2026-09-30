# Batida com o sequenciador de passos

> Três batidas programadas na aba `Passos` em vez de nota por nota no piano roll: um house de quatro no chão com chimbal e bumbo à parte para o sidechain, um hip-hop com swing e notas fantasma, e um trap com rolos de chimbal; cerca de 10 minutos por cenário.

Os andamentos, os níveis e os efeitos daqui são pontos de partida musicais: acerte de ouvido. O que depende do programa (rótulos, faixas de valor, o que cada ação faz) vem do código e dos capítulos, e vale para compasso de 4 tempos (os padrões de fábrica se adaptam a 3/4 e a compassos maiores, ver o [05c](../manual/05c-sequenciador-de-passos.md#padrões-de-fábrica)). O texto acompanha o comportamento da fase 19 (A) com os ajustes da fase 22 (`938272c` e `aa563b3`) e da fase 25 (`55cc53b`): o swing é lido das notas (só quando o desenho é mesmo uma grade com swing), vale no clipe todo, e o clipe guarda a resolução e o valor do último `Aplicar swing` (a dica) para o `Tirar swing` voltar exatamente às notas de antes. A aba `Passos` só tem testes automáticos e o uso no Chrome pela sessão de código não cobriu estas receitas: o que soa bem `(não confirmado ao ouvido)`.

## Ingredientes

| Recurso | Para quê aqui | Capítulo |
|---|---|---|
| Aba `Passos`: grade, `Passo`, `Compassos`, pincéis `Normal`, `Acento`, `Fantasma` | Desenhar o ritmo com cliques | [05c Sequenciador de passos](../manual/05c-sequenciador-de-passos.md) |
| Botão `Padrões` (`House`, `Hip-hop`, `Trap`) | Começar de um ritmo pronto | [05c Padrões de fábrica](../manual/05c-sequenciador-de-passos.md#padrões-de-fábrica) |
| `Swing` com `Aplicar swing` e `Tirar swing` | Atrasar as notas dos passos pares | [05c Swing](../manual/05c-sequenciador-de-passos.md#swing) |
| Menu `Ações`: `Preencher a cada N passos…`, `Limpar linha`, `Repetir até o fim do clipe` | Refazer uma linha, tirar o bumbo, estender para o clipe inteiro | [05c Ações](../manual/05c-sequenciador-de-passos.md#ações) |
| Faixa `Velocidade` (abre com uma linha selecionada) | Acertar a intensidade de cada passo | [05c Velocidade](../manual/05c-sequenciador-de-passos.md#velocidade-pincéis-acento-duplo-clique-e-a-faixa) |
| Kits `909`, `Lo-fi`, `Trap` e o `Volume` das peças | O timbre de cada estilo | [04b Bateria](../manual/04b-bateria.md) |
| `Compressor` (presets `Bateria cola`, `Paralelo pesado`, e o `Sidechain`) | Cola, peso e bombeio | [06d Compressor](../manual/06d-efeitos-referencia.md#2-compressor) |
| `Reverb` (preset `Placa`) num barramento | Espaço na caixa, sem encher a mistura | [06d Reverb](../manual/06d-efeitos-referencia.md#6-reverb-fdn) |
| Loop (`L`), andamento, `Espaço` | Programar ouvindo | [02 Transporte](../manual/02-transporte.md) |

Para o sidechain do cenário 1: [Efeitos em combinação, receita 3](efeitos-em-combinacao.md#receita-3-sidechain-pumping-com-o-bumbo). Para a compressão paralela: [receita 2](efeitos-em-combinacao.md#receita-2-bateria-com-compressor-paralelo-em-barramento).

## Cenário 1: house de quatro no chão com chimbal, e o bumbo à parte

Resultado: 4 compassos a 124 BPM com bumbo em todo tempo, palmas no 2 e no 4, chimbal aberto no contratempo e chimbais fechados fantasmas, com um baixo ou pad "respirando" no bumbo.

1. Toque no botão `120 BPM · 4/4`, ponha `BPM` em `124` e `Salvar`. Ligue o loop com `L`.
2. `Faixa` > `Bateria`; no seletor `Kits de bateria`, escolha `909`. Dê dois cliques no vazio da raia, no compasso 1, para criar um clipe de um compasso. Abra a aba `Passos`.
3. Toque em `Padrões` e escolha `House`. Aparece `Padrão House aplicado.` e a grade mostra, em `1/16 · 16/comp.`: `Bumbo` nos passos 1, 5, 9 e 13; `Palmas` nos 5 e 13; `Chimbal aberto` nos 3, 7, 11 e 15; `Chimbal fechado` só com fantasmas nos passos 2, 4, 6... até 16.
4. Dê o acento nos tempos fortes do chimbal aberto: dois cliques rápidos nos passos 3 e 11 da linha `Chimbal aberto` (o primeiro clique apaga, o segundo acende de novo como acento, velocidade 1,00).
5. Tire o bumbo desta faixa, porque ele vai para uma faixa própria (o sidechain lê a faixa inteira): toque no nome `Bumbo` para selecionar a linha e use `Ações` > `Limpar linha`. Confira que a primeira linha do menu diz `Vale para: Bumbo`.
6. Estique o clipe até 4 compassos (aparar a ponta direita na raia, [02b](../manual/02b-timeline-e-clipes.md)) e use `Ações` > `Repetir até o fim do clipe`. Aviso: `Padrão repetido até o fim do clipe (3 vezes).` Faça o `Limpar linha` do passo 5 **antes** deste passo: ele só vale dentro do padrão (o 1º compasso).
7. Crie uma segunda faixa `Bateria` (chame de `Bumbo`), kit `909`, clipe de 4 compassos. Na aba `Passos`, toque no nome `Bumbo` e use `Ações` > `Preencher a cada N passos…` com `A cada: 4 passos` (é o valor padrão), `Aplicar`. Depois `Ações` > `Repetir até o fim do clipe`. Agora o bumbo está sozinho numa faixa.
8. Numa faixa de pad ou de baixo (ver [Primeira batida do zero](primeira-batida-do-zero.md)), adicione um `Compressor` (sem preset) e, no grupo `CHAVE`, `Sidechain` na faixa `Bumbo`. Valores: `Detector` `Pico`, `Passa-alta` 20 Hz, `Razão` 8:1, `Ataque` 1 ms, `Joelho` 0 dB, `Mistura` 100%, `Soltura` 194 ms (0,4 × 60 ÷ 124). Toque e arraste o `Limiar` a partir de −30 dB até o medidor marcar de −6 a −12 dB de redução a cada bumbo.
9. Na faixa da bateria sem bumbo, um `Compressor` com o preset `Bateria cola` (−16 dB, 2:1, 30 ms, 200 ms) cola as palmas e os chimbais.

## Cenário 2: hip-hop com swing e notas fantasma

Resultado: um boom bap a 90 BPM em que as semicolcheias fracas balançam e a caixa ganha notas fantasma, em 4 compassos.

1. Andamento `90`. `Faixa` > `Bateria`, kit `Lo-fi` (timbres escuros e curtos, `Volume` geral 85%). Clipe de 1 compasso; aba `Passos`.
2. `Padrões` > `Hip-hop`: `Bumbo` `x.....x..x......`, `Caixa` `....x.......x...`, `Chimbal fechado` em colcheias, `Chimbal aberto` no passo 15.
3. Notas fantasma na caixa: pincel `Fantasma` (0,30) e, na linha `Caixa`, clique nos passos 8, 10 e 16.
4. Chimbal em 16 fantasmas: pincel `Fantasma`, e na linha `Chimbal fechado` arraste com o mouse do passo 2 até o 16, começando num passo apagado: o arraste acende só os apagados, então as colcheias ficam e entram 8 semicolcheias fracas. Se o arraste pular algum passo, clique nele.
5. Suavize os fantasmas: com `Chimbal fechado` selecionada, na faixa `Velocidade` arraste sobre os passos fracos até cerca da metade da altura (velocidade em torno de 0,5).
6. Deixe `Passo` em `1/16` e arraste o controle de `Swing` até `Swing 20%`; toque em `Aplicar swing`. O aviso deve dizer `Swing de 20% aplicado (12 notas, em 1/16).` (se você aplicar o swing antes dos fantasmas, só com o `Hip-hop` puro, o aviso é `Swing de 20% aplicado (1 nota, em 1/16).`: só o bumbo do passo 10 está num passo par). Só as notas exatamente nos passos pares andam: os 3 fantasmas da caixa, os 8 fantasmas do chimbal e o bumbo do passo 10. Cada uma cai 0,05 batida depois (33 ms a 90 BPM); o segundo 16 do par passa a soar em 60% do par em vez de 50%.
7. Ouça. Compare com `Tirar swing` (aviso `Swing tirado (12 notas, em 1/16).`; as notas voltam exatamente às posições de antes) e volte a aplicar. Se ficar quadrado, suba para 25%; 33% já vira tercina.
8. Estique o clipe para 4 compassos e use `Ações` > `Repetir até o fim do clipe`. Ele copia as notas do compasso 1 com o swing que já têm. A ordem não é obrigatória: o swing vale no clipe todo (desde a fase 19 A), então também dá para repetir primeiro e aplicar o swing depois, nos 4 compassos de uma vez. Se você desfizer (`Ctrl+Z`) o `Aplicar swing`, o controle de `Swing` volta a 0% junto com as notas e com a dica do clipe.
9. Efeitos: `Compressor` `Bateria cola` na faixa; um barramento `Reverb` com o preset `Placa` (`Mistura` 100%) e o envio da bateria baixo, em torno de −20 dB, porque o envio leva a faixa inteira, bumbo incluído (o preset já corta os graves da cauda em 200 Hz).

## Cenário 3: trap com rolos de chimbal

Resultado: 4 compassos a 140 BPM, com bumbo 808, caixa no tempo 3 (meio tempo) e chimbal com rolos em 1/32 e um rolo mais denso no fim.

1. Andamento `140`. `Faixa` > `Bateria`, kit `Trap` (bumbo virando baixo, chimbal fechado bem curto). Clipe de 1 compasso; aba `Passos`.
2. `Padrões` > `Trap`. `Passo` muda para `1/32 · 32/comp.`, com `Compassos` em 1. O que a grade tem: `Bumbo` nos passos 1, 21 e 25; `Caixa` no 17; `Chimbal fechado` com colcheias do passo 1 ao 17, semicolcheias nos passos 19, 21 e 23 e o rolo do 25 ao 32 (fantasmas nos 25 e 27, normais nos 26, 28 e 29, acentos nos 30, 31 e 32).
3. Estique o clipe para 2 compassos e use `Ações` > `Repetir até o fim do clipe` (`Padrão repetido até o fim do clipe (1 vez).`). Toque em `+` ao lado de `Compassos` para ver os dois compassos na grade.
4. Um rolo mais denso no último tempo do compasso 2: troque `Passo` para `1/64 · 64/comp.` (as notas em 1/32 continuam nos passos, um sim e um não), toque no nome `Chimbal fechado`, escolha o pincel `Fantasma` e arraste do passo 114 (o primeiro vazio depois do passo 113) até o 128, sempre a partir de um passo apagado. Os fantasmas entram entre as notas do rolo.
5. Ajuste à mão: com `Chimbal fechado` selecionada, na faixa `Velocidade` arraste em diagonal, de baixo para cima, sobre os passos 97 a 128 para desenhar um crescendo. (`Ações` > `Aleatorizar…` refaria a linha do chimbal fechado nos dois compassos e apagaria o rolo; use só para procurar ideias e desfaça com `Ctrl+Z`.)
6. Peso: um barramento de retorno com `Compressor` `Paralelo pesado` (`Mistura` 100% no barramento), como na [receita 2](efeitos-em-combinacao.md#receita-2-bateria-com-compressor-paralelo-em-barramento). Tudo passa junto pela faixa: o `Compressor` de insert que abaixa o bumbo abaixa também os chimbais.

## Variações

- **Outros ritmos prontos:** `Funk` (chimbal em 16 avos com acento nos tempos e caixa com fantasmas), `Reggaeton (dembow)`, `Bossa nova` (clave no `Aro`) e `Shuffle (tercinas)` em `1/8 tercina`. Depois ajuste com os mesmos gestos.
- **Uma linha por vez com `Preencher a cada N passos…`:** com o bumbo selecionado, `2` faz colcheias, `4` quatro no chão, `8` só os tempos 1 e 3; com os chimbais, `1` enche todos os passos.
- **Deslocar:** `Ações` > `Deslocar →` com o chimbal aberto selecionado leva cada nota um passo à frente e dá a volta no padrão: vira contratempo em segundos.
- **Sampler fatiado:** com um loop fatiado ([Sampler multi-zona, receita 2](sampler-multi-zona-e-fatiar-loops.md#receita-2-kit-de-bateria-a-partir-de-um-loop-fatiado)), a aba `Passos` da faixa `Sampler` tem uma linha por fatia (`Fatia 1 · C1`...): os mesmos gestos, sem `Padrões`. A faixa é "fatiada" quando a maioria das zonas (mais da metade, e ao menos duas) é do mesmo áudio, de uma nota só e em `Até o fim`, com ao menos um `Trecho` (é o que `Fatiar sample…` faz; apará-lo depois à mão não muda isso). `Fatia N` é a posição da zona na lista, e uma zona que você editou (passou para `Sustenta`, trocou o áudio ou alargou `Notas de`/`até`) vira `Zona · <nota>` sozinha, sem renumerar nem tirar as outras: editar a 2ª de 5 fatias dá `Fatia 1`, `Zona`, `Fatia 3`, `Fatia 4`, `Fatia 5`. Num sampler de áudio inteiro com várias zonas (um piano multi-sample), com uma zona só aparada à mão, ou quando as zonas editadas passam de metade, as linhas se chamam `Zona · C3` e não `Fatia`.
- **Passar para o piano roll:** `E` abre as mesmas notas nas linhas das peças, para alongar, humanizar ou quantizar ([05b](../manual/05b-ferramentas-midi.md)). As notas que saírem dos passos voltam na grade com contorno âmbar.

## Por que funciona

- **Nota fantasma é velocidade baixa.** O pincel `Fantasma` grava 0,30; a bateria soa mais baixa e com um pouco menos de ataque, e o groove vem da diferença entre os golpes, não de mais notas.
- **O swing atrasa só os passos pares de uma resolução.** Em `1/16`, o atraso é `swing × 0,25 batida` e só as notas exatamente nesses passos andam; as colcheias do hip-hop estão nos passos ímpares e ficam retas, então quem balança são as semicolcheias fracas. Em `1/8` a mesma conta age sobre as colcheias fracas (os contratempos). Escolha a resolução em que estão as notas que você quer balançar.
- **O swing é uma propriedade das notas, não da tela.** O controle `Swing` mostra o que o clipe já tem (lido na resolução atual): `Ctrl+Z`, reabrir o projeto ou mexer no piano roll mudam o número junto. A leitura das notas é rígida de propósito: só há swing se todas as notas dos passos pares estão atrasadas do mesmo tanto e há nota num passo ímpar; humanização, tercinas e o rolo de 1/32 leem 0% (o rolo no meio de um swing não atrapalha). O que a leitura não alcança (clipe só com contratempos, 50% com rolos) o clipe lembra pela dica que o `Aplicar swing` grava (`1/16:40`, resolução e valor), conferida contra as notas: por isso `Tirar swing` desfaz qualquer `Aplicar swing`, na resolução em que ele foi feito, mesmo que `Passo` esteja em outra. `Aplicar swing` e `Tirar swing` valem para o clipe todo; `Limpar linha` e as outras ações do menu `Ações` trabalham só dentro do padrão (`Compassos`). `Repetir até o fim do clipe` copia o que já está pronto, com o atraso incluído.
- **O sidechain lê a faixa inteira.** Por isso o bumbo do house vai para uma faixa própria; num kit inteiro, os chimbais e as palmas também disparariam o efeito. A aba `Passos` edita uma faixa por vez, então `Limpar linha` numa e `Preencher a cada N passos…` na outra fazem a separação em poucos cliques.
- **Chimbal fechado e aberto se cortam.** O fechado abafa o aberto em cerca de 6 ms (e o contrário). No `House`, os fantasmas fechados vêm um 16 depois de cada aberto, então o aberto soa curto, só até o próximo fantasma.
- **Rolo é densidade.** A 140 BPM um 1/32 dura 53,6 ms e um 1/64, 26,8 ms (0,125 e 0,0625 batida × 60 ÷ 140). Por isso a grade fina existe: o rolo em `1/16` seria só a metade das notas.
- **A duração da nota não importa na bateria.** Os passos criam notas de no máximo 1/16 e cada peça toca até o fim; o que muda o som é a linha, a posição e a velocidade.

## Se der errado

| Sintoma | Causa provável | Como resolver |
|---|---|---|
| A aba `Passos` não aparece | A faixa selecionada não é `Bateria` nem `Sampler` com zonas | Selecione a faixa certa (sampler sem zonas não conta) |
| Clico nos passos e nada acende | Passo escurecido, depois do fim do clipe; ou não há clipe sob o cursor (`Criar clipe aqui`) | Estique o clipe, ou crie um |
| `Limpar linha` está apagado no menu | Não há linha selecionada | Toque no nome da linha |
| Uma ação refez a bateria inteira | Nenhuma linha selecionada: valeu para todas | `Ctrl+Z`; confira `Vale para: …` antes |
| `Limpar linha`, `Inverter`, `Aleatorizar…` ou `Preencher a cada N passos…` só mexeram no primeiro compasso | Essas ações trabalham só dentro do padrão (`Compassos`). O swing não: vale no clipe todo | Aumente `Compassos` até cobrir o clipe e repita a ação |
| `Aplicar swing` não muda nada e aparece `Nenhuma nota está nos passos pares de 1/16: troque a resolução para a das notas ou desenhe algo antes.` (ou a resolução que estiver em `Passo`) | Nenhuma nota está exatamente num passo par desta resolução; o botão não edita nada e não cria passo no `Ctrl+Z` | Escolha a resolução das notas que devem balançar (ex.: `1/16`) |
| `Tirar swing` está apagado, mas as notas parecem atrasadas | Nem a leitura das notas na resolução de `Passo` (um swing aplicado em `1/16` aparece como 0% em `1/8`) nem a dica do clipe valem: o projeto é de antes da fase 25 (sem dica), ou as notas foram mexidas depois do `Aplicar swing` (uma nota reta num passo par, ou nenhuma no atraso da dica) | Volte `Passo` para a resolução em que você aplicou o swing; se foi mexido à mão, leve as notas de volta ao passo reto no piano roll |
| Depois de `Padrões` o swing que eu tinha sumiu | `Padrões` tira o swing da dica do clipe e o que as notas mostram na resolução da grade de antes e na do padrão, e escreve o padrão reto, no mesmo passo do `Ctrl+Z`. Notas que só parecem swing em outra resolução não andam | Escolha o padrão primeiro e aplique o swing depois; ou `Ctrl+Z` |
| `Aplicar swing` avisou que moveu notas num clipe só com contratempos (ou com 50% e rolos de 1/32) e o controle mostra `Swing 0%` | Isso acontecia antes da fase 25 (a leitura das notas dava 0%). Agora a dica do clipe faz o controle mostrar o valor aplicado e acender `Tirar swing`; se ainda mostra 0%, a dica foi invalidada (notas mexidas à mão) ou o projeto é de antes da fase 25 | `Tirar swing` devolve exatamente as notas; em projeto antigo, `Ctrl+Z` ou ponha uma nota num passo ímpar antes de aplicar |
| Arrastei o `Swing` e, ao trocar `Passo`, o número voltou ao do clipe e `Aplicar swing` apagou | Trocar `Passo` (ou escolher um padrão) zera o valor arrastado e ainda não aplicado (fase 25): ele era de outra resolução | Escolha o `Passo` primeiro e arraste o `Swing` depois |
| Notas com contorno âmbar depois de reabrir | A resolução voltou a `1/16` e as notas são de `1/32` (ou de tercina), ou foram movidas à mão no piano roll | Escolha a resolução das notas. O swing que ficou nas notas reaparece no controle e `Tirar swing` fica ligado |
| `Repetir até o fim do clipe` avisa `O padrão já ocupa o clipe inteiro.` ou `Não há notas no padrão para repetir.` e nada acontece | O padrão (`Compassos`) é do tamanho do clipe, ou os primeiros compassos estão sem notas. Nada é apagado nem entra no `Ctrl+Z` | Estique o clipe, ou ajuste `Compassos` e desenhe algo no começo |
| `Repetir até o fim do clipe` apagou uma variação | Ele troca tudo que estava depois do padrão | `Ctrl+Z`; faça as variações depois de repetir |
| Ao clicar num passo do rolo, sumiram várias notas | A grade estava numa resolução mais grossa que a das notas, e o passo escondia mais de uma | `Ctrl+Z`; escolha `1/32` ou `1/64` antes |
| O arraste deixou passos vazios no meio | O arraste lê uma posição por vez e pulou passos em movimento rápido `(lido do código, não confirmado)` | Arraste mais devagar ou clique nos que faltaram |
| Não ouço nada ao clicar | O transporte está tocando (a prévia do clique só toca com ele parado), ou a peça está com `Volume` 0% | Pare o transporte; confira o painel `Instrumento` |

## Ver também

- [05c Sequenciador de passos](../manual/05c-sequenciador-de-passos.md): todos os controles e gestos.
- [Primeira batida do zero](primeira-batida-do-zero.md): o caminho pelo piano roll, com baixo, pad e exportação.
- [Efeitos em combinação](efeitos-em-combinacao.md): compressão paralela e sidechain em detalhe.
- [Mixagem e automação](mixagem-e-automacao.md): níveis e retorno de reverb.
