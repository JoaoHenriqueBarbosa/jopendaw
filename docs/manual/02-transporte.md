# Transporte e barra de ferramentas

> A barra do transporte reúne tudo o que se faz sem sair do arranjo: tocar, parar, gravar, andamento, loop, metrônomo, edição rápida, grade, zoom, painéis, importar, exportar e configurações. Leia este capítulo para saber o que cada botão faz e qual atalho o aciona.

## Onde fica

- **Computador (tela de 800 px ou mais):** uma barra horizontal no topo do projeto, acima da régua. Ela rola na horizontal quando a janela é estreita.
- **Celular ou janela abaixo de 800 px:** a mesma barra, mas embaixo da tela, perto do polegar, também com rolagem horizontal.
- Os botões aparecem nesta ordem, da esquerda para a direita. Linhas finas separam os quatro primeiros grupos: **transporte** | **edição e visão** | **painéis** | **entradas de notas**; depois vêm, só com um espaço maior no lugar da linha, **importar e exportar** e, em seguida, **configurações, atalhos e status**. As linhas são estreitas de propósito (4 px de cada lado): com folga maior a barra não cabia em uma janela de 1512 px. O **indicador de nuvem não fica na barra**: ele está no cabeçalho do projeto, no canto superior direito (ver [Indicador de nuvem](#indicador-de-nuvem-no-cabeçalho-do-projeto)). O botão **Automação** (gravação de automação) fica no grupo de edição e visão, entre a grade de encaixe e o **Afastar**; ele mostra só o ícone no modo Ler e, nos outros modos, fica em vermelho com o nome do modo (o menu de modos está em [Automação](07-automacao.md)). Não há botão do arquivo de projeto na barra: `Projeto inteiro (.jopendaw)…` fica dentro da janela **Exportar áudio**.
- Importar e Exportar mostram o nome ao lado do ícone só quando a barra tem 1540 px ou mais de largura (e no computador). Abaixo disso, ou no celular, ficam só os ícones, cada um com o tooltip abaixo. Com o nome à mostra, o **Exportar** mantém o tooltip e o **Importar** fica sem tooltip.
- Quando o app está ocupado (importando, exportando, congelando, processando o warp), aparece no fim da barra um círculo girando com o texto do que está acontecendo (por exemplo `Importando nome.wav…`, `Lendo nome.mid…`, `Exportando…`, `Congelando Áudio 1…`, `Processando o warp…`). Enquanto esse texto está na barra, Importar e Exportar ficam desligados.

Um erro de uma ação da barra (por exemplo, gravar sem faixa armada) aparece em um aviso vermelho logo abaixo da barra, com um X para fechar. Ele some sozinho quando a próxima ação dá certo.

## Controles

Os rótulos abaixo são os tooltips exatos (passe o mouse ou segure o dedo). Onde há duas variações, o texto muda conforme o estado.

### Transporte

| Controle (tooltip) | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| **Parar e voltar (Enter)** (ícone de quadrado) | Para a reprodução e leva o cursor de volta. Se estava tocando com o loop ligado, volta ao início do loop; nos outros casos volta ao compasso 1. A janela rola para mostrar o cursor (2 batidas de folga). Gravando, o tooltip é **Parar a gravação e voltar (Enter)** e o botão encerra a gravação primeiro. | Atalhos: Enter ou Home. | Parado, Enter sempre volta ao começo do projeto. |
| **Tocar (espaço)** / **Pausar (espaço)** (botão cheio, ícone de play ou pausa) | Toca do cursor; tocando, pausa onde está (o cursor não volta). Gravando, o tooltip é **Parar a gravação (espaço)** e o botão encerra a gravação e gera os clipes. | Atalho: Espaço. | O navegador só libera o áudio depois do primeiro clique ou tecla; o primeiro toque já basta. |
| **Gravar** (círculo vermelho) | Liga e desliga a gravação nas faixas armadas. Aceso em vermelho gravando; durante a contagem pisca uma vez por batida, no andamento do projeto. O tooltip diz o estado (ver tabela abaixo). | Atalho: R (funciona mesmo com o teclado musical ligado). | Antes de gravar, arme uma faixa no botão de bolinha do cabeçalho dela. |
| **Opções de gravação** (seta ao lado do Gravar) | Abre um menu com dois itens: **Contagem de um compasso** (marcado quando ligada) e **Configurações de gravação…** (abre a janela Configurações). | Contagem ligada por padrão. | A contagem só toca quando a gravação começa parada; se já está tocando, grava na hora. |
| **Posição** (caixa escura, dois números) | Em cima, a posição em `compasso.tempo.dezesseis-avos` (começa em `1.1.1`, cor da marca); embaixo, o tempo `m:ss.cc` (minutos, segundos e centésimos). Só mostra; não dá para digitar nela. | Ex.: `2.3.1` e `0:03.00`. Com mapa de compassos, o compasso e o tempo são contados pela fórmula de cada trecho (em 6/8 o segundo número vai de 1 a 6, uma colcheia por número); com mapa de andamento, o tempo em segundos é o real, somando os trechos. | Na contagem antes do zero, mostra em vermelho as batidas que faltam (`−4`, `−3`…) e o tempo negativo. |
| **`120 BPM · 4/4`** (botão de texto) | Abre a janela **Andamento e compasso** (ver abaixo). Desligado durante a gravação. | Sem mapa de andamento nem de compassos: o andamento inicial e os tempos por compasso, fixos; o andamento sai arredondado a uma casa, **sem o `,0`** quando ela é zero, e com vírgula (`120`, `97,5`; `120,5 BPM · 4/4`): `120,04` e `119,96` aparecem como `120`, e `120,06` como `120,1`. O texto vem do formatador único de andamento e compasso (`tempo_format.dart`, fase 13), o mesmo do subtítulo do projeto, da janela do warp e da pergunta do `.mid`. Com mapa, o texto é o **andamento vigente no cursor** (o mesmo formato; `↗` depois do número quando o cursor está num trecho em rampa que sobe e `↘` quando a rampa desce) e o compasso do cursor (`3/4`, `6/8`…); com mapa de andamento aparece antes um ícone de linha quebrada na cor da marca, e o texto acompanha o cursor enquanto toca. Ver [Faixa Andamento e mapa de compassos](02b-timeline-e-clipes.md#faixa-andamento-e-mapa-de-compassos). | Com mapa o botão ganha tooltip: `Andamento no cursor (mapa com N pontos, inicial X BPM). Clique para editar o inicial ou mudar o compasso.`; só com mapa de compassos, `Compasso no cursor. Clique para editar o andamento ou mudar o compasso.` |
| **Loop (L) · arraste na régua para marcar** (ícone de repetição) | Liga e desliga o loop. Aceso na cor da marca quando ligado. Quando ligado, ao chegar ao fim da região o cursor volta ao começo dela. | Desligado por padrão. Um projeto novo já traz a região do compasso 1 ao 4 (4 compassos), ainda desligada. | Não entra no desfazer. Não dá para ligar ou desligar gravando (aparece `Pare a gravação para ligar ou desligar o loop.`). |
| **Metrônomo (C)** (ícone de cronômetro) | Liga e desliga o clique. | Clique de 30 ms: 1600 Hz no primeiro tempo do compasso, 1000 Hz nos outros. Desligado por padrão. Segue o mapa de compassos (em 3/4 o tempo forte volta a cada 3 cliques; em 6/8 há um clique por colcheia, seis por compasso) e o mapa de andamento (o intervalo entre cliques muda com o andamento). | Não entra no desfazer nem na exportação. |

Textos do tooltip do **Gravar**, conforme o estado:

| Estado | Tooltip |
|---|---|
| Nenhuma faixa armada | `Gravar (R): nenhuma faixa armada; arme no mixer (●)` |
| Uma faixa armada | `Gravar (R) na faixa armada` (com `, com um compasso de contagem` se a contagem está ligada) |
| Várias faixas armadas | `Gravar (R) nas N faixas armadas` (mesmo complemento da contagem) |
| Contando | `Contando o compasso de entrada: toque para cancelar (R)` |
| Gravando | `Gravando: toque para parar (R)` |

### Janela Andamento e compasso

Abre ao tocar no botão `120 BPM · 4/4`.

| Controle | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| **BPM** (campo de número; **BPM inicial** quando o projeto tem mapa de andamento) | Andamento do projeto (com mapa, o do ponto da batida 0, o andamento de partida). Só aceita dígitos, ponto e vírgula; vem com o valor atual e selecionado, então digitar substitui. | 20 a 999, com decimais (`120,5` ou `120.5`; o valor é arredondado a uma casa). Fora disso ou ilegível: `Entre 20 e 999 (aceita decimais, como 120,5).` | Enter confirma. Os pontos da faixa `Andamento` têm a mesma faixa (ver [Faixa Andamento](02b-timeline-e-clipes.md#faixa-andamento-e-mapa-de-compassos)). |
| **Tempos por compasso** (lista) | Numerador do compasso inicial, sobre semínima. | `1/4` a `32/4` (32 é o limite do documento e da importação do `.mid`; até a fase 12 a lista parava em `12/4`, e só passava disso se o compasso atual já tivesse mais tempos). Se o compasso inicial não é `n/4` (por exemplo `6/8`), a lista abre com o item `6/8 (atual)` selecionado: **Salvar** com ele deixa o compasso como está e só troca o BPM. | Serve para o compasso do começo da música. Escolher um `n/4` **troca** o compasso inicial por ele, mesmo que antes fosse `6/8` ou `7/8`, e **sempre**, inclusive um `3/4` num `6/8` ou um `4/4` num `7/8` (a troca funciona assim desde a fase 14; na fase 12 o campo já trocava, mas escolher o `n` igual às batidas arredondadas do compasso atual, 3 no `6/8` e 4 no `7/8`, não mudava nada). Só o item `(atual)` mantém o compasso: na fase 14 ele ganhou um caminho próprio (`keepMeter`) em vez de repetir as batidas `(testado só por testes automáticos)`. Salvar também mantém o BPM com uma casa decimal, como antes. Para 3/4 no meio da música, 6/8, 7/8 e outras fórmulas, use o botão logo abaixo. Desde a fase 13, um `5/8`, `7/8`, `9/8` ou `11/8` que seja o **único** compasso do projeto também já não volta a `n/4` no motor (metrônomo e contagem seguem a fórmula) depois de algumas edições: o motor guarda `meter_custom` e o `tempo` reenviado não toca no compasso ([motor](../dev/01-motor.md#armadilhas-conhecidas)) `(testado só por testes automáticos)`. |
| **Mudar compasso a partir de um compasso…** (botão de texto) | Fecha esta janela e abre **Mudar compasso a partir do compasso N** (ver abaixo). | | |
| **Cancelar** | Fecha sem mudar nada. | | |
| **Salvar** | Aplica o andamento e o compasso ao documento do projeto. Entra no desfazer. O servidor recebe uma cópia depois, sem travar nada (ver "O andamento e o servidor" abaixo). | | Fica valendo na hora, com ou sem rede |

#### Janela Mudar compasso a partir do compasso N

Abre pelo botão **Mudar compasso a partir de um compasso…** da janela acima. O título mostra o número escolhido (`Mudar compasso a partir do compasso 9`). `(testado só por testes automáticos; não visto no navegador)`

| Controle | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| **A partir do compasso** (campo de número) | Compasso em que a fórmula nova começa (1 é o primeiro). | 1 a 9999; fora disso `Entre 1 e 9999.` Vem com o compasso onde está o cursor. | Enter aplica. |
| **Tempos** (lista) | Numerador. | `1` a `32`. Vem com o valor que já vale no compasso escolhido. | |
| **Unidade** (lista) | Denominador: a figura que dá o tempo. | `1`, `2`, `4`, `8`, `16`, `32`. | `4` é a semínima; `8`, a colcheia. |
| **Remover a mudança** (só aparece se já existe uma mudança exatamente nesse compasso e ele não é o 1) | Apaga aquela mudança; o compasso anterior volta a valer daí em diante. | | |
| **Cancelar** / **Aplicar** | Fecha sem mudar / grava a mudança. Entra no desfazer. | Mudar para o que já vale ali não faz nada. | |

A janela lembra: `O compasso muda daí em diante, até a próxima mudança. A batida do projeto é a semínima: 6/8 ocupa 3 batidas.` Um compasso `N/D` dura `N × 4 ÷ D` batidas (4/4 = 4, 3/4 = 3, 6/8 = 3, 7/8 = 3,5, 5/4 = 5). O mapa de compassos muda a numeração e as linhas da régua e da grade, o contador de posição, o encaixe `Compasso`, o metrônomo, a contagem antes de gravar e o tamanho do clipe de notas criado por duplo clique; **não muda** o andamento nem o som das faixas. Não dá para mudar o compasso gravando (`Pare a gravação para mudar o compasso.`).

#### O andamento e o servidor

O andamento e o compasso são **do documento do projeto**, como as faixas e os clipes: quem manda é o valor que está na barra. O servidor guarda só um espelho (para a lista de projetos), enviado em segundo plano, no melhor esforço:

- Sem rede, com o servidor fora, ou sem sessão, **salvar não falha nem avisa erro**: o valor novo vale no aparelho e o envio do espelho fica pendente.
- O espelho é reenviado quando o documento é salvo de novo (0,4 s depois de qualquer edição, e também depois de **desfazer** e **refazer** um andamento), ao abrir o projeto, depois de aplicar uma versão vinda do servidor e quando a sincronização volta a ficar `Sincronizado`.
- Só é enviado o que difere do último valor que o servidor confirmou. O espelho leva o andamento arredondado ao inteiro (20 a 999), o **numerador real** do compasso do compasso 1 (limitado a 1–32) e a **figura do tempo** (`1`, `2`, `4`, `8`, `16` ou `32`; a figura só vai quando muda). Por isso um projeto que começa em `6/8` fica com `6` e `8` no servidor (a lista `Projetos` mostra `6/8`), e não `3` sobre `4` como o campo de tempos por compasso do documento guarda (o `beatsPerBar` do documento conta semínimas: 6/8 vale 3). Antes o espelho mandava só o `3` e o cartão mostrava `3/4`.
- O andamento e o compasso também viajam dentro do documento sincronizado: um outro aparelho que baixa a versão nova do projeto traz o andamento e o compasso dela (não ficam mais os do cadastro do projeto). Ver [Nuvem e sincronização](01b-nuvem-e-sincronizacao.md).
- Os mapas de andamento e de compassos (pontos da faixa `Andamento` e mudanças de compasso) **só existem dentro do documento**: o espelho do servidor guarda apenas o andamento inicial e o compasso do compasso 1 (numerador e figura). Um outro aparelho que baixa o documento traz os mapas junto; o cartão da lista de projetos mostra só o andamento inicial.
- O subtítulo do projeto (`120 BPM · 4/4`, embaixo do nome, no cabeçalho da tela) lê o documento aberto e acompanha o botão da barra, inclusive ao desfazer. Antes de o estúdio abrir, mostra o valor do servidor. Se o andamento do documento não for inteiro (por exemplo, um ponto inicial `120,5` editado na faixa `Andamento`), o subtítulo e o botão da barra mostram o **mesmo texto**, com uma casa decimal e vírgula (`120,5 BPM · 4/4`; a partir da fase 13 os dois usam o mesmo formatador, `formatBpm` de `tempo_format.dart`, que mostra `120` para `120,04`). O compasso do subtítulo também vem do compasso inicial real do documento (`formatDocMeter`): um projeto que começa em 6/8 mostra `6/8`, não mais `3/4`; antes de o estúdio abrir, vale o do servidor (`beats_per_bar` sobre `beat_unit`), que agora também é `6/8` porque o espelho leva o numerador e a figura reais (antes o subtítulo pré-abertura e o cartão da lista mostravam `3/4` para um projeto em 6/8). `(coberto por teste automático do subtítulo e do espelho; não visto no Chrome)` O cartão do projeto na lista `Projetos` lê o espelho do servidor e pode ficar para trás enquanto o envio estiver pendente.

O que muda ao trocar o andamento: os clipes ficam na mesma batida de início. Clipes de áudio sem warp mantêm a duração em segundos, então o fim deles anda em batidas; com warp ligado o clipe acompanha o andamento do projeto (o inicial, quando há mapa de andamento; ver [Warp e altura](03b-warp-e-altura.md)). Clipes de notas ficam iguais em batidas e passam a tocar mais rápido ou mais devagar. Não dá para mudar o andamento nem o compasso gravando (`Pare a gravação para mudar o andamento.`).

Com um mapa de andamento, este botão mexe só no **andamento inicial** (o ponto da batida 0): os outros pontos da faixa `Andamento` ficam com o BPM que têm, e o primeiro ponto acompanha o valor novo. Um projeto com um andamento só continua sendo tratado como antes, sem nenhuma diferença no som.

### Edição e visão

| Controle (tooltip) | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| **Desfazer (Ctrl+Z)** (seta para trás) | Volta um passo. | Guarda até 200 passos. Desligado sem passos ou gravando. | Um arraste inteiro (mover, aparar, desenhar loop) é um passo só; uma passada de gravação de automação (do play ao stop, com todos os controles) também. |
| **Refazer (Ctrl+Shift+Z)** (seta para frente) | Refaz o passo desfeito. | Também Ctrl+Y. | Fazer uma edição nova apaga o que dava para refazer. |
| **Cortar no cursor (S)** (tesoura) | Divide no cursor o clipe selecionado. Sem clipe selecionado, divide todos os clipes que o cursor cruza na faixa selecionada. Só corta se o cursor está estritamente dentro do clipe. | Áudio e notas; uma nota que cruza o corte vira duas. | Sem efeito se nenhum clipe cruza o cursor. |
| **Duplicar (Ctrl+D)** (ícone de cópia) | Copia o clipe selecionado para logo depois dele e seleciona a cópia. O que a cópia cobrir é aparado (ver [sobreposição de clipes](02b-timeline-e-clipes.md)). | Desligado sem clipe selecionado. | Com o editor de notas aberto, ele passa para a cópia. |
| **Apagar o clipe (Delete)** (lixeira) | Apaga o clipe selecionado, sem fechar o vão. | Desligado sem clipe selecionado. | Backspace também apaga. |
| **Grade de encaixe (Alt ao arrastar: livre)** (menu, ícone de grade + valor atual) | Escolhe o passo de encaixe de tudo que se posiciona com o mouse. | `Livre`, `Compasso`, `1/4`, `1/8`, `1/16`. Padrão: `1/4`. | Veja a tabela da grade abaixo. |
| **Automação: Ler…** (menu; só o ícone de gráfico em `Ler`, ícone e nome em vermelho nos outros modos) | Escolhe como mexer nos controles enquanto toca grava a automação: `Ler`, `Escrever`, `Toque` ou `Trava`. Fica entre a grade e o `Afastar`. | Padrão `Ler` (não grava). Não é salvo com o projeto. | Detalhes na seção `Botão Automação`, logo abaixo da grade. |
| **Afastar** (lupa com menos) | Reduz o zoom em 1,5 vez, mantendo o cursor no mesmo ponto da tela. | Faixa: 4 a 800 px por batida; padrão 48. | |
| **Aproximar** (lupa com mais) | Aumenta o zoom em 1,5 vez, também ancorado no cursor. | | As teclas + e − mexem em passos menores (1,25 vez). |
| **Seguir o cursor na reprodução** (ícone de alvo) | Liga e desliga o acompanhamento. Ligado e tocando, quando o cursor passa de 92% da largura visível (ou sai pela esquerda), a janela salta e deixa o cursor a 5% da borda esquerda. | Ligado por padrão. | Desligue para editar em outro ponto enquanto a música toca. |
| **Visão: enquadrar, altura das faixas, seguir o cursor** (ícone de zoom em expansão) | Menu de visão (tabela abaixo). O ícone fica esmaecido quando Seguir o cursor está desligado. | | |
| **Seções e marcadores (M cria um no cursor)** (ícone de bandeira) | Menu dos marcadores (tabela abaixo). A bandeira fica na cor da marca quando há marcadores. | | |
| **Duração do projeto: m:ss (N compassos)** (texto cinza discreto) | Mostra a duração até o fim do último clipe, no andamento atual (com mapa de andamento, somando os trechos em tempo real). O texto é só o tempo (`1:24`); o tooltip acrescenta os compassos (`Duração do projeto: 1:24 (N compassos)`), contados pelo mapa de compassos: um projeto que termina no meio de um compasso conta esse compasso; um que termina exatamente na barra não conta o seguinte. Projeto vazio: `0 compassos`. | | Marcadores e loop não contam. |

#### Grade de encaixe

| Opção | Passo | Onde vale |
|---|---|---|
| `Livre` | sem encaixe | |
| `Compasso` | 1 compasso (`tempos por compasso` batidas; com mapa de compassos, encaixa no começo do compasso mais próximo, de qualquer fórmula) | |
| `1/4` (padrão) | 1 batida | |
| `1/8` | meia batida | |
| `1/16` | um quarto de batida | |

O encaixe vale para: clicar ou arrastar na régua, clicar numa raia para posicionar o cursor, mover e aparar clipes (começo e fim), arrastar marcadores e a posição onde a importação coloca o áudio. Segurar **Alt** ao arrastar desliga o encaixe naquele arraste. Um clipe de notas não fica menor que um passo da grade ao aparar (1/16 de batida se a grade está em `Livre` ou com Alt). A grade não é salva com o projeto: volta a `1/4` ao reabrir.

#### Botão Automação

O botão fica entre a **Grade de encaixe** e o **Afastar**. Ele diz o que acontece quando você mexe no fader, no pan, no nível de envio ou num knob de instrumento ou de efeito **com a música tocando** (o fader do `Master` no mixer e o mini fader da linha `Master` da linha do tempo também gravam). O `Escrever` só começa a gravar depois do primeiro toque no controle, na barra e no seletor da raia. O passo a passo e o comportamento de cada modo estão em [Gravar automação](07-automacao.md#gravar-automação).

| Como aparece | Quando | Tooltip (texto exato) |
|---|---|---|
| Só o ícone de gráfico (`show_chart`), em cinza-claro, sem nome | Modo `Ler` (o padrão): o rótulo foi tirado para a barra caber em janela de 1512 px | `Automação: Ler. Só toca a automação; mexer no controle não grava.` |
| Ícone e nome em **vermelho** (`#F2433A`), com fundo vermelho leve: `Escrever`, `Toque` ou `Trava` | Modo que grava | `Automação: Escrever. Começa ao mexer no controle (só agarrar não basta): grava até parar, sobrescrevendo o que já havia.` / `Automação: Toque. Começa ao mexer no controle (só agarrar não basta) e grava enquanto você o segura; ao soltar, volta ao valor automatizado.` / `Automação: Trava. Começa ao mexer no controle (só agarrar não basta) e grava enquanto você o segura; mantém o último valor até parar.` |
| Ícone e só a **inicial** em vermelho: `E`, `T` ou `V` | Modo que grava, com a janela abaixo de 800 px (celular) | O mesmo tooltip (no celular, aparece com toque longo no botão) |

Tocar no botão abre o menu com quatro itens, cada um com o nome e, embaixo, uma frase em letra pequena (a mesma do tooltip, sem o `Automação: Modo.`): `Ler`, `Escrever`, `Toque`, `Trava`. O modo atual vem marcado. Mudar de modo com a música tocando fecha o que estava sendo gravado (a passada vira um passo do desfazer) e o modo novo vale dali em diante.

Ao lado do botão pode aparecer, em vermelho-salmão e numa linha só, um **aviso** que some sozinho em 5 segundos: `Este controle não tem automação.` (você mexeu num controle que não se automatiza, como o `Sidechain`) ou `A automação não grava junto com a gravação de áudio ou MIDI.` (mexeu num controle durante a gravação, ou na contagem).

Cada raia de automação tem ainda um seletor pequeno `L`, `E`, `T` ou `V` no cabeçalho, que vale só para ela e sobrepõe a barra (ver [Automação, seletor da raia](07-automacao.md#seletor-da-raia)).

#### Menu Visão

| Item | O que faz | Atalho |
|---|---|---|
| **Enquadrar tudo (Z)** | Ajusta zoom e rolagem para caber o projeto inteiro (até o último clipe, marcador ou o fim do loop ligado), com 4% de folga; no mínimo um compasso de largura (o compasso do mapa onde o trecho começa: 3,5 batidas num `7/8`). | Z |
| **Enquadrar a seleção (Shift+Z)** | Faz o mesmo com o clipe selecionado; sem clipe, enquadra tudo. | Shift+Z |
| **Faixas pequenas**, **Faixas médias**, **Faixas grandes** | Altura das faixas: 70%, 100% (padrão) e 150% da altura normal. Um item fica marcado. | sem atalho |
| **Seguir o cursor** (marcável) | O mesmo que o botão de alvo. | |
| **Régua em minutos e segundos** (marcável) | Troca a régua entre compassos e minutos:segundos. O mesmo que clicar no canto esquerdo da régua. | |

A altura das faixas, o modo da régua, o zoom e a rolagem não são salvos com o projeto.

#### Menu Seções e marcadores

| Item | O que faz | Habilitado quando |
|---|---|---|
| Lista de marcadores (bolinha de cor, nome e posição) | Leva o cursor ao marcador (e a janela, se ele estiver fora da vista) e o seleciona. Sem marcadores mostra `Nenhum marcador ainda`. Marcador sem nome aparece como `Marcador`. | sempre |
| **Marcador no cursor (M)** | Cria um marcador na posição do cursor; se já existe um ali, só o seleciona. | sempre |
| **Loop entre marcadores** | Com um marcador selecionado, faz loop dele até o próximo (se é o último, do anterior até ele). Sem seleção, do primeiro ao último. Liga o loop. | 2 marcadores ou mais |
| **Loop desta seção** | Loop da seção onde o cursor está (do marcador anterior ao seguinte; a última seção vai até o fim do arranjo). | cursor depois do primeiro marcador |
| **Loop no clipe selecionado (Shift+L)** | Loop exatamente sobre o clipe selecionado. | há clipe selecionado |

Detalhes de marcadores e seções (arrastar, renomear, cores) estão em [Timeline e clipes](02b-timeline-e-clipes.md).

### Painéis de baixo

Quatro botões abrem e fecham o painel inferior. Clicar no botão do painel já aberto fecha; clicar em outro troca. O botão aceso indica o painel atual.

| Controle (tooltip) | O que abre | Atalho | Dica |
|---|---|---|---|
| **Mixer (X)** (ícone de controles) | O mixer. Ver [Mixer](06-mixer.md). | X | |
| **Editor de notas (E)** (ícone de nota com linhas) | O piano roll. Se há um clipe de notas selecionado, abre nele; senão mostra `Nenhum clipe aberto`. Ver [Piano roll](05-piano-roll.md). | E | Duplo clique num clipe de notas também abre. |
| **Instrumento da faixa (I)** (ícone do tipo da faixa selecionada; piano se a faixa não é de instrumento) | O painel do instrumento da faixa selecionada. Ver [Painel de instrumento](04-painel-de-instrumento.md). | I | |
| **Efeitos da faixa (F)** (varinha) | A cadeia de efeitos da faixa selecionada; sem faixa selecionada, a do master. Ver [Painel de efeitos](06c-painel-de-efeitos.md). | F | |

O painel também tem abas e botões próprios (maximizar, fechar, redimensionar): ver [Timeline e clipes](02b-timeline-e-clipes.md#dock-o-painel-de-baixo).

### Entradas de notas

| Controle (tooltip) | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| **Tocar com o teclado do computador (Ctrl+K)** (ícone de teclado) | Liga o teclado musical. Ligado, o botão mostra a oitava (`C4`) e o tooltip vira `Teclado tocando: atalhos suspensos (C L S X Z E F K J e Shift+H/K/L). A a P tocam a partir do C4, Z/X mudam a oitava, C/V a intensidade (80%). Ctrl+K desliga` (o mesmo texto na barra e no painel do instrumento; no Mac o `Ctrl` vira `⌘`). | Desligado; oitava 4; intensidade 80%. | Com o teclado ligado, as letras dele têm prioridade sobre os atalhos (o Z deixa de enquadrar e o C, de ligar o metrônomo). O R continua gravando. |
| **Entrada MIDI: ligar teclado ou controlador** (ícone de cabo) | Liga a entrada MIDI. Ligado, mostra a quantidade de aparelhos conectados; com zero, o tooltip diz `MIDI ligado, nenhum aparelho conectado: conecte e ele aparece aqui sozinho`; com aparelhos, `Entrada MIDI: nomes`. | Desligado. | No Chrome o MIDI pede permissão. Detalhes em [Gravação](03c-gravacao.md) e [Configurações, atalhos e Android](09-configuracoes-atalhos-android.md). |
| **Aprender MIDI (Shift+K): clique num controle e mexa no botão do seu teclado** (ícone de controle remoto, logo depois do cabo) | Liga o modo MIDI learn: os controles mapeáveis (fader, pan, envios, knobs de instrumento e de efeito) ganham contorno, e uma faixa `Aprender MIDI` aparece abaixo da barra. Ligado, fica âmbar e o tooltip vira `Sair do modo Aprender MIDI (Shift+K)`. Com mapeamentos, o tooltip ganha a linha `N mapeamento(s) · botão direito: lista` e o ícone um pontinho de aviso. Botão direito ou toque longo abre a janela `Mapeamentos MIDI`. | Só **aparece** com o MIDI ligado, ou com o modo ligado, ou com mapeamentos no projeto; desligado ao abrir o projeto. | Sem o botão na barra, `Shift+K` liga o modo e pede o MIDI. Capítulo próprio: [06f MIDI learn](06f-midi-learn.md). |

### Arquivos e configurações

| Controle (rótulo ou tooltip) | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| **Importar** (só o ícone: tooltip **Importar áudio ou MIDI (Ctrl+I)**; com o nome à mostra não há tooltip) | Abre o seletor de arquivos (título `Importar áudio ou MIDI`) e coloca cada áudio a partir do cursor (com encaixe na grade). O primeiro vai para a faixa selecionada se ela é de áudio e está livre naquele ponto; os demais, e o primeiro nos outros casos, criam faixas de áudio novas com o nome do arquivo. Um arquivo MIDI (`.mid`, `.midi`) vira faixas de notas (`Sintetizador`; o canal 10 vira `Bateria`) e pode abrir a pergunta `Usar o andamento do arquivo (X BPM)?`. | Extensões: `wav`, `mp3`, `ogg`, `oga`, `flac`, `m4a`, `aac`, `opus`, `webm`, `aif`, `aiff`, `mid`, `midi`. | Desligado gravando ou ocupado. Ver [Áudio e clipes](03-audio-e-clipes.md#importar-um-arquivo-midi-mid). |
| **Exportar** (tooltip **Exportar áudio (WAV, FLAC ou MP3)**) | Abre a janela **Exportar áudio**. Gravando, o tooltip é `Pare a gravação para exportar` e o botão fica desligado. | Ver [Exportação](08-exportacao.md). | No rodapé da janela, `Projeto inteiro (.jopendaw)…` leva ao arquivo do projeto ([capítulo 01](01-projetos-modelos-conta.md#projeto-em-arquivo-jopendaw)). |
| **Configurações: entrada de áudio, latência e contagem** (engrenagem) | Abre a janela **Configurações** (tabela abaixo). | | |
| **Atalhos do teclado (?)** (ícone de tecla de comando) | Abre a janela **Atalhos do teclado** com a lista completa, em grupos (com as teclas de agora), e os botões **Personalizar** (só na web e no computador; troca a lista pela tela `Personalizar atalhos`) e **Fechar**. | Tecla `?`. | Como personalizar: [capítulo 09](09-configuracoes-atalhos-android.md#personalizar-os-atalhos) |

Depois de **Atalhos do teclado (?)** só aparece, quando há trabalho em andamento, o círculo girando com o texto (ver "Onde fica"). O indicador de nuvem não está mais na barra: mudou para o cabeçalho do projeto.

### Indicador de nuvem (no cabeçalho do projeto)

Fica no **cabeçalho da tela do projeto**, no canto superior direito (à direita do nome e do andamento do projeto), tanto no computador quanto no celular. Foi tirado da barra porque ela saía da tela em janelas de uns 1500 px. Só aparece com o projeto aberto e sessão iniciada (some por inteiro quando a sincronização está desligada). É um botão de ícone sem texto: o tooltip diz o estado e só é clicável no conflito. Detalhes em [Nuvem e sincronização](01b-nuvem-e-sincronizacao.md).

Estados do indicador:

| Ícone | Tooltip |
|---|---|
| Nuvem com visto (cinza) | `Sincronizado` |
| Nuvem com setas (cor da marca) | `Sincronizando` ou `Sincronizando (N/M arquivos)` |
| Nuvem cortada (âmbar) | `Offline (tentando de novo em N s)` |
| Ícone de sincronização com alerta (vermelho) | A mensagem do conflito, ou `Conflito: o projeto mudou em outro aparelho. Toque para resolver` |
| Círculo com ponto de exclamação (vermelho) | A mensagem do erro, ou `Não deu para sincronizar` |

No conflito, a janela **O projeto mudou em outro aparelho** abre sozinha uma vez, com três botões: **Decidir depois** (o ícone do cabeçalho reabre a janela), **Usar a versão do servidor** (descarta as mudanças deste aparelho, sem desfazer) e **Manter esta e enviar** (a versão do servidor é substituída pela daqui). Nada é sobrescrito antes da escolha.

#### Janela Configurações

| Controle | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| **ENTRADA DE ÁUDIO** (lista) | Escolhe de onde vem o áudio da gravação. Itens: `Padrão do sistema` (ou `Padrão (nome do aparelho)`), cada entrada encontrada (`Entrada N` quando o navegador esconde os nomes) e `Entrada desconectada` se a escolhida sumiu. | Padrão do sistema. A escolha fica no aparelho, não no projeto. | Desligada gravando (`Pare a gravação para trocar de entrada.`). |
| Botão de atualizar (tooltip **Procurar as entradas de novo (depois de conectar um microfone ou interface)**) | Procura as entradas de novo. Enquanto procura, vira um círculo girando. | | O navegador pede permissão para o microfone na primeira vez. |
| **Nível** (barra horizontal) | Mede o pico da entrada. | | Só se mexe com a entrada aberta: faixa de áudio armada ou monitorando. |
| **GRAVAÇÃO**, **Contagem de um compasso** (interruptor) | Liga a contagem (`O metrônomo conta um compasso antes de a gravação começar`). O mesmo item do menu da seta do Gravar. | Ligada. Vale para este projeto. | |
| **Compensação de latência** (controle deslizante + campo com `ms`) | Quanto o áudio gravado chega atrasado, além do que já é medido sozinho (a latência do motor, com os efeitos e o limitador, e a que o navegador informa para a entrada e a saída). Positivo adianta o que foi gravado; negativo atrasa. | −200 a 500 ms, passo de 1 ms, padrão 0. Fora do intervalo o campo mostra `De -200 a 500 ms`. | Para medir: grave o metrônomo pelo microfone e ajuste até a batida gravada cair na grade. Não entra no desfazer. Logo abaixo a janela mostra `Ida e volta do monitoramento: N ms` (ver [09](09-configuracoes-atalhos-android.md)). |
| **Fechar** | Fecha a janela. Um número digitado e ainda não confirmado é aplicado; se for inválido a janela continua aberta com o motivo. | | |

## Passo a passo

**Tocar, pausar e recomeçar**
1. Aperte a barra de espaço (ou toque no botão cheio). A música toca do cursor.
2. Aperte espaço de novo para pausar; o cursor fica onde parou.
3. Aperte Enter (ou o botão de quadrado) para parar e voltar. Com o loop ligado e a música tocando, você volta ao início do loop.

**Mudar o andamento e o compasso**
1. Toque no botão de texto (`120 BPM · 4/4`).
2. Digite o novo valor em **BPM** (20 a 999) e escolha os **Tempos por compasso**.
3. **Salvar**. Se errar, Ctrl+Z desfaz.

**Mudar o andamento no meio da música ou trocar o compasso**
1. Andamento: ligue o botão de velocímetro no canto esquerdo da régua, dê um clique com o botão direito na faixa `Andamento` no ponto desejado e escolha **Adicionar ponto aqui**; depois mude o BPM do ponto (arraste na vertical ou **Digitar BPM…**). Passo a passo completo em [Faixa Andamento e mapa de compassos](02b-timeline-e-clipes.md#faixa-andamento-e-mapa-de-compassos).
2. Compasso: toque no botão de texto (`120 BPM · 4/4`), depois em **Mudar compasso a partir de um compasso…**, escolha o compasso, os **Tempos** e a **Unidade**, e **Aplicar**.
3. Receitas com valores: [Mapa de andamento e de compassos na prática](../guias/mapa-de-andamento-e-compasso.md).

**Ensaiar um trecho em loop**
1. Arraste na régua, do começo ao fim do trecho. O loop liga sozinho e a região aparece na cor da marca.
2. Aperte Espaço. Ao chegar ao fim da região o cursor volta ao começo.
3. Desligue com L quando quiser tocar tudo. A região continua marcada, só desligada.

**Enquadrar o projeto e ver tudo**
1. Aperte Z (ou **Visão** > **Enquadrar tudo (Z)**).
2. Para ver só um clipe, selecione-o e aperte Shift+Z.
3. Para afastar ou aproximar aos poucos, use os botões **Afastar** e **Aproximar** ou as teclas − e +.

**Gravar com contagem**
1. Arme uma faixa no botão de bolinha do cabeçalho dela.
2. Confira a seta ao lado do Gravar: **Contagem de um compasso** marcada.
3. Aperte R. Você ouve um compasso de cliques e a gravação começa no cursor. Aperte R ou Espaço para parar.

## Combina com

- [Timeline e clipes](02b-timeline-e-clipes.md): a régua, o cursor, a grade e os marcadores que a barra controla, e a faixa `Andamento` (mapa de andamento) sob a régua.
- [Mapa de andamento e de compassos na prática](../guias/mapa-de-andamento-e-compasso.md): virada de andamento, ritardando em rampa, 4/4 para 3/4 e 6/8.
- [Gravação](03c-gravacao.md): armar faixas, contagem, tomadas e latência.
- [Mixer](06-mixer.md) e [Painel de efeitos](06c-painel-de-efeitos.md): os painéis abertos pelos botões X e F.
- [Exportação](08-exportacao.md): o botão **Exportar**.
- [MIDI learn](06f-midi-learn.md): o botão `Aprender MIDI` da barra e o `Shift+K`.
- [Configurações, atalhos e Android](09-configuracoes-atalhos-android.md): a lista completa de teclas e as diferenças no celular.
- Receitas que juntam vários recursos: pasta [`../guias/`](../guias/).

## Limites e pegadinhas

- **Gravando, a barra trava o que mudaria a gravação:** desfazer, refazer, andamento, compasso, loop (ligar, desenhar, seções), importar, exportar, congelar e trocar de entrada ficam desligados ou avisam `Pare a gravação para…`. O cursor também não pula (clicar na régua, numa raia ou num marcador não move o cursor).
- **O que não entra no desfazer:** ligar o loop, o metrônomo, a contagem, a compensação de latência, armar e monitorar faixas. Desfazer uma nota nunca mexe neles. Desenhar a região do loop na régua entra, e desfazer volta o loop junto.
- **O que não é salvo com o projeto:** o modo de automação (o da barra e o de cada raia: volta a `Ler` ao reabrir), grade, zoom, rolagem, seguir o cursor, altura das faixas, modo da régua, teclado musical (oitava e intensidade), altura do painel de baixo e a última escolha da janela de exportação (dura só a sessão). O que fica no projeto: andamento, compasso, loop (região e liga/desliga), metrônomo, contagem, compensação de latência e marcadores.
- **Metrônomo e loop não vão para a exportação.** O arquivo sai linear, do começo ao fim, sem cliques.
- **Web e Android:** os botões são os mesmos; no celular Importar e Exportar mostram só o ícone, a barra fica embaixo e o painel de baixo ocupa 60% da altura livre.
- **Teclas com o teclado musical ligado:** as teclas dele (A W S E D F T G Y H U J K O L P para notas, Z e X para a oitava, C e V para a intensidade) passam na frente dos atalhos, com ou sem Shift. Ou seja, S (cortar), L e Shift+L (loop), E, F, Z (enquadrar), X (mixer) e C (metrônomo) deixam de funcionar como atalho. Continuam valendo Espaço, Enter, R, I, M, `[`, `]`, + e −, ?, Esc, Delete e tudo com Ctrl (o Ctrl+K desliga o teclado musical). Isto vale para as teclas **padrão**: com atalhos personalizados o que fica suspenso é o que a janela `?` lista no grupo `Suspensos enquanto o teclado do computador está ligado`, e o tooltip do botão do teclado continua com o texto de fábrica.
- **Parar e pausar devolvem ao repouso o que se tocou ao vivo.** Espaço (pausando a música) e Enter ou Home (parar) soltam o pedal e levam o pitch bend e a roda de modulação ao centro, também nas rodas da tela, que voltam ao zero. Antes só o que o clipe dirigia era zerado, e um pedal seguro no controlador ficava preso ao trocar de faixa ou parar. `(testado só por testes automáticos)`
- O andamento digitado nesta janela aceita decimais (20 a 999, uma casa: `92,5`; mais casas são arredondadas a uma), e o botão da barra mostra o mesmo texto (`92,5 BPM · 4/4`; um `120,04` de um ponto do mapa aparece `120`); o servidor só recebe o inicial, arredondado ao inteiro e limitado a 20 a 999.
- **Não acompanham o mapa de andamento:** o warp dos clipes de áudio (usa só o andamento inicial) e o tempo sincronizado do delay, do tremolo e do filtro (também só o inicial). Ver o guia [Mapa de andamento e de compassos na prática](../guias/mapa-de-andamento-e-compasso.md).
- **Offline:** mudar o andamento ou o compasso funciona sem rede e o valor fica no projeto (reabrir o projeto não o desfaz). Só a cópia no servidor, usada pela lista de projetos, espera a rede voltar. `(lido do código e coberto por testes automáticos; não visto no Chrome)`

## Atalhos

Vale o Ctrl no Windows e no Linux e o Cmd (⌘) no Mac; a janela de atalhos mostra ⌘ no Mac. Os tooltips e menus escrevem sempre `Ctrl` (nos que passam por `withMod`, `⌘` no Mac). Estas são as teclas **padrão**: desde a fase 16 elas podem ser trocadas em `Atalhos do teclado` > `Personalizar` ([capítulo 09](09-configuracoes-atalhos-android.md#personalizar-os-atalhos)), e os tooltips da barra (`Loop (L)`, `Metrônomo (C)`, `Cortar no cursor (S)`, `Parar e voltar (Enter)`, `Apagar o clipe (Delete)`, `Duplicar (Ctrl+D)`, `Desfazer (Ctrl+Z)`…) **não acompanham a troca**: continuam com a tecla de fábrica. A janela `?` mostra a tecla de agora.

| Tecla | Ação |
|---|---|
| Espaço | Tocar / pausar (gravando, encerra a gravação) |
| Enter ou Home | Parar e voltar (ao começo, ou ao início do loop se estava tocando com ele ligado) |
| R | Gravar / parar de gravar |
| L | Loop liga/desliga |
| Shift+L | Loop no clipe selecionado (ou na seção do cursor, sem clipe) |
| C | Metrônomo |
| Ctrl+Z | Desfazer |
| Ctrl+Shift+Z ou Ctrl+Y | Refazer |
| S | Cortar no cursor |
| Ctrl+D | Duplicar o clipe |
| Delete ou Backspace | Apagar o clipe selecionado |
| Ctrl+I | Importar áudio ou MIDI (a janela de atalhos escreve `Importar áudio ou MIDI`) |
| + ou = (também Shift+=, que digita o +, e o + do teclado numérico) | Aproximar (1,25 vez, ancorado no cursor). A janela de atalhos lista `+  ·  =` em `Aproximar` |
| − (também o − do teclado numérico) | Afastar (0,8 vez, ou seja, o inverso de 1,25); a janela lista `−` em `Afastar` |
| Z | Enquadrar o projeto inteiro |
| Shift+Z | Enquadrar o clipe selecionado |
| M | Marcador no cursor |
| Shift+M | Marcador no cursor pedindo o nome |
| `[` e `]` | Cursor no marcador anterior / seguinte |
| X, E, I, F | Alternar Mixer, Editor de notas, Instrumento, Efeitos |
| Esc | Fechar o painel de baixo |
| ? | Abrir a janela de atalhos |
| Ctrl+K | Ligar/desligar o teclado musical |
| Shift+K | Ligar/desligar o modo Aprender MIDI ([06f](06f-midi-learn.md)); suspenso com o teclado musical ligado |
| Ctrl + roda do mouse | Zoom no ponto do mouse (na área das raias) |
| Shift + roda do mouse | Rolar na horizontal |

Os atalhos não funcionam enquanto você digita num campo de texto.
