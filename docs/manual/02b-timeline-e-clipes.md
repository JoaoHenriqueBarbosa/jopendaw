# Timeline e clipes

> A timeline é o arranjo da música: a régua no alto, uma linha por faixa com os clipes, o Master no fim e o minimapa embaixo. Use este capítulo para criar faixas, posicionar, cortar e reordenar clipes, marcar seções e mexer no painel de baixo.

## Onde fica

É a área central da tela do projeto (abra um projeto na lista). De cima para baixo:

1. A **barra do transporte** (ver [Transporte](02-transporte.md)); no celular ela fica embaixo.
2. A **régua** (30 px de altura), com o canto esquerdo mostrando `N faixas` e `comp.` ou `mm:ss`.
3. A **lista de faixas**: à esquerda os cabeçalhos (232 px no computador, 132 px no celular), à direita as raias com os clipes. As duas metades rolam juntas na vertical.
4. No fim da lista, a linha **Nova faixa** (44 px) e a linha do **Master**.
5. O **minimapa** `Visão geral` (28 px), fixo embaixo da lista.
6. O **painel de baixo** (dock), quando aberto: mixer, editor de notas, instrumento ou efeitos.

Um traço branco vertical com uma ponta triangular no alto marca o cursor de reprodução, sobre a régua e as raias.

## Controles

### Régua

| Controle | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| Clique na régua | Posiciona o cursor naquele ponto, com encaixe na grade. | Encaixe da grade do transporte. | Alt não desliga o encaixe do clique; use a grade `Livre`. |
| Arrastar na régua | Desenha a região do loop (do ponto onde começou ao ponto onde soltou, com encaixe) e liga o loop. | Precisa de mais de 0,01 batida de largura; menor que isso não liga. Entra no desfazer como um passo. | Redesenhe para trocar a região; não há alças nas pontas dela. |
| Passar o mouse | Mostra um fio vertical e uma etiqueta com `compasso.tempo.dezesseis-avos · m:ss.d` do ponto sob o mouse. | | Só no computador. |
| Canto esquerdo (`N faixas` + `comp.` / `mm:ss`) | Clicar alterna a régua entre compassos e minutos:segundos. O tooltip é `Régua em compassos: clique para alternar` (ou `... minutos e segundos ...`). O texto em cor da marca é o modo atual. | Padrão: compassos. | O mesmo que **Régua em minutos e segundos** do menu Visão. |
| Números da régua | Em compassos: número do compasso (começa em 1); a régua pula números (a cada 2, 4, 8… compassos) quando o zoom diminui. Marcas de tempo aparecem a partir de 12 px por batida. Em mm:ss: rótulos a cada 0,5, 1, 2, 5, 10, 15, 30 s, 1, 2, 5, 10, 30 min ou 1 h, o menor passo que deixa 64 px entre rótulos. | | Em mm:ss, traços curtos embaixo continuam marcando os compassos. |
| Bandeirinhas de marcador | Ver a seção Marcadores e seções. | | |
| Selo **Contando…** | Aparece na régua, ao lado do cursor, durante a contagem antes de gravar. | | |

Gravando (e na contagem), clicar e arrastar na régua não fazem nada: mexer no meio desalinharia a gravação.

A grade de fundo das raias mostra uma linha por compasso (mais forte) e, com 16 px ou mais por batida, uma linha por batida.

### Cabeçalho de faixa

O cabeçalho tem uma faixa de cor de 4 px na esquerda (a cor da faixa) e o medidor de pico de 6 px na direita. Tocar no cabeçalho seleciona a faixa (fundo mais claro). No computador:

| Controle (tooltip) | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| Nome da faixa | Texto do nome. **Duplo toque** no cabeçalho (fora dos botões) abre a janela **Nome da faixa** (campo **Nome**, botão **Salvar**). | Até 60 caracteres; nome vazio é ignorado. | Novas faixas nascem `Áudio 1`, `Sintetizador 2`… com o próximo número livre do tipo. |
| Ícone do tipo (à esquerda do nome) | Nas faixas de instrumento, abre e fecha o painel do instrumento (tooltip `Sintetizador: abrir o instrumento (I)`, `Fechar o instrumento (I)`; o nome muda por tipo: Bateria, Sampler, FM, Wavetable). No barramento, abre os efeitos (`Barramento: abrir os efeitos` / `Fechar os efeitos`). Na faixa de áudio é só um ícone (tooltip `Faixa de áudio`). | Um ícone por tipo (tabela abaixo). | |
| **Opções da faixa** (três pontos) | Menu da faixa (tabela abaixo). | | |
| **M** (tooltip `Mudo`) | Silencia a faixa. Aceso em vermelho-salmão. | Desligado. | |
| **S** (tooltip `Solo`) | Toca só as faixas em solo. Aceso em amarelo. | Desligado. | |
| Bolinha de gravar (tooltips abaixo) | Arma a faixa para gravar. Contornada em vermelho quando armada; cheia enquanto grava de fato (depois da contagem). Barramento não tem o botão (fica um vão no lugar). | Desarmada. Não entra no desfazer. | Bloqueada durante a gravação (`Pare a gravação para armar esta faixa`). |
| **A** (tooltip `Automação` ou `Automação (N)`) | Abre o menu dos parâmetros automatizáveis da faixa; escolher um mostra a sub-raia dele embaixo da faixa (escolher um já aberto oculta). Aceso quando há sub-raia aberta; contornado quando há automação, mas oculta. O menu ainda tem `Mostrar as ocultas (N)` e `Ocultar todas`, e `Nada para automatizar aqui` quando não há alvo. | | Ver [Automação](07-automacao.md). |
| **FX** (tooltip `Efeitos` ou `Efeitos (N)`; aberto: `Fechar os efeitos`) | Abre e fecha o rack de efeitos da faixa. Aceso enquanto aberto; contornado quando a cadeia tem efeitos. | | Ver [Painel de efeitos](06c-painel-de-efeitos.md). |
| Mini fader (controle deslizante fino) | Volume da faixa. O tooltip mostra o valor em dB. Tocando com automação de volume, mostra o valor ao vivo na cor da automação. | −∞ a +6 dB (ganho 0 a 2, curva cúbica). | Um arraste é um passo do desfazer. |
| Barra fina no rodapé do cabeçalho | Nível da entrada, só na faixa de áudio armada. Sobe na hora, cai devagar; a ponta fica vermelha por 1,5 s se saturar. | Escala de −48 a 0 dB. | Ajuste o ganho do microfone por ele antes de gravar. |

No celular (barra de 132 px) o cabeçalho tem duas linhas: nome e três pontos em cima; ícone do tipo, M, S, gravar e A embaixo (botões de 20 px). O **FX** e o mini fader saem do cabeçalho: use o item **Efeitos** do menu ou o mixer.

Tooltips da bolinha de gravar: `Armar para gravar as notas (teclado ou MIDI)` (faixa de instrumento), `Armar para gravar a entrada de áudio` (faixa de áudio), `Desarmar`, e durante a gravação `Gravando nesta faixa` (armada) ou `Pare a gravação para armar esta faixa`.

#### Menu Opções da faixa (três pontos)

| Item | O que faz | Aparece / habilitado |
|---|---|---|
| **Abrir o instrumento** | Abre o painel do instrumento desta faixa. | Só em faixas de instrumento |
| **Efeitos** | Abre o rack de efeitos desta faixa. | Sempre |
| **Monitorar a entrada** (marcável) | Ouve o microfone passando pela cadeia da faixa enquanto você toca. Não entra no desfazer. | Só em faixa de áudio |
| **Renomear** | Abre a janela **Nome da faixa**. | Sempre |
| **Duplicar a faixa** | Cria uma cópia logo abaixo, com clipes, instrumento, efeitos, envios e automação (ids novos). O nome ganha `(2)`, depois `(3)`. A cópia sai desarmada e sem monitorar. | Sempre |
| **Congelar em áudio** (legenda `Vira uma faixa de áudio nova; esta fica muda`) | Renderiza a faixa num áudio novo. Ver [Exportação](08-exportacao.md#congelar-uma-faixa). | Desligado, com o motivo na legenda: `Barramento não tem som próprio`, `A faixa está vazia`, `Pare a gravação antes` |
| **Mover para cima** / **Mover para baixo** | Troca a faixa de posição. | Desligado na primeira / na última |
| **Trocar a cor** | Passa para a próxima cor da paleta (6 cores, em ciclo). | Sempre |
| **Apagar a faixa** | Apaga a faixa. Se tiver clipes, efeitos ou automação, pede confirmação: `Apagar "nome"?` — `A faixa e o que há nela (clipes, efeitos, automação) saem do projeto (dá para desfazer).` com **Apagar** / cancelar. Faixa vazia apaga direto. Apagar um barramento também remove os envios e saídas que apontavam para ele. | Sempre |

#### Reordenar arrastando

Segure o cabeçalho (toque longo; com o mouse, segure o botão por cerca de meio segundo) e arraste na vertical. Enquanto arrasta, o cabeçalho ganha borda colorida e o nome vira `Mover para a posição N`. Soltar move a faixa (as sub-raias de automação abertas vão junto com a faixa de cima). No dedo, um arraste simples, sem segurar, rola a lista. Os itens **Mover para cima** e **Mover para baixo** do menu fazem o mesmo passo a passo.

A ordem das faixas é a ordem do sinal entre barramentos: se mover uma faixa faria um barramento apontar para trás, esse roteamento é desfeito (a faixa volta ao master e o envio sai). Sidechains de compressor e gate acompanham as faixas.

### Nova faixa

A linha **Nova faixa** (botão `+ Faixa` com uma seta) fica logo depois da última faixa. O tooltip é `Nova faixa`. Toque e escolha o tipo. A faixa nova entra no fim da lista, já selecionada, com a próxima cor da paleta.

| Item do menu | Ícone | O que cria | Notas |
|---|---|---|---|
| **Áudio** | forma de onda | Faixa que recebe clipes de áudio (importados ou gravados). | Nome `Áudio N`. Pode ser armada (grava a entrada) e monitorada. |
| **Sintetizador** | piano | Faixa de notas com o sintetizador subtrativo. | Recebe clipes de notas. Ver [Sintetizador](04a-sintetizador.md). |
| **Bateria** | grade | Faixa de notas com a bateria de 12 peças. | Ver [Bateria](04b-bateria.md). |
| **Sampler** | nota musical | Faixa de notas que toca um áudio como instrumento. | Ver [Sampler](04c-sampler.md). |
| **FM** | pontos | Faixa de notas com o FM de 4 operadores. | Ver [FM](04d-fm.md). |
| **Wavetable** | ondas | Faixa de notas com o wavetable. | Ver [Wavetable](04e-wavetable.md). |
| **Barramento** (depois de uma linha divisória) | bifurcação | Faixa sem clipes que só recebe áudio de outras faixas (retornos de envio e grupos). | Não grava. O ícone dela abre os efeitos. Ver [Mixer](06-mixer.md). |


### Raias e clipes

| Ação | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| Clique no vazio de uma raia | Desmarca o clipe, seleciona a faixa e posiciona o cursor, com encaixe (gravando, o cursor não se move). | | |
| **Duplo clique** no vazio de uma faixa de instrumento | Cria um clipe de notas e abre o editor. O clipe começa no início do compasso clicado, dura 1 compasso e se encolhe para não montar em cima dos vizinhos (começa depois do anterior, termina antes do próximo). Nasce com o nome da faixa. | Duração: 1 compasso. | Em faixa vazia e desarmada aparece a dica `Clique duas vezes para criar um clipe de notas` (`Toque duas vezes ...` no celular). |
| Clique num clipe | Seleciona o clipe (borda branca) e a faixa dele. Só um clipe fica selecionado por vez. | | Selecionar um clipe de notas com o editor aberto troca o clipe do editor. |
| Arrastar o meio do clipe | Move o clipe. O começo encaixa na grade. Vertical: muda de faixa (o clipe de áudio só vai para faixa de áudio; o de notas, para faixa de instrumento; as sub-raias abertas contam como parte da faixa de cima). | Não passa do compasso 1 (começo em 0). | **Alt** desliga o encaixe. |
| Arrastar a borda esquerda | Apara o começo. No áudio, o som fica no lugar (o começo do trecho avança); no clipe de notas as notas ficam onde estavam na linha do tempo. | Áudio: não recua além do começo do arquivo; duração mínima 0,01 s. Notas: mínimo de um passo da grade (1/16 de batida em `Livre` ou com Alt). | Borda de 8 px (16 px com o dedo; num clipe estreito, um quarto da largura). |
| Arrastar a borda direita | Apara o fim. No áudio, estica até o fim do arquivo, no máximo. No clipe de notas, alonga ou encurta o clipe. | Mesmos mínimos. | O cursor do mouse vira setas nas bordas. |
| Arrastar o canto superior esquerdo (14 × 14 px) | Ajusta o fade in do clipe de áudio. O canto ganha uma bolinha branca e um triângulo sombreado mostra a rampa. | 0 até a duração do clipe menos o fade out. Sem encaixe. | Só em clipe de áudio. Ver [Áudio e clipes](03-audio-e-clipes.md). |
| Arrastar o canto superior direito | Ajusta o fade out. | 0 até a duração menos o fade in. | |
| Botão direito, ou toque longo no celular | Abre o menu do clipe (tabelas abaixo). | | |
| Duplo clique num clipe de notas | Abre o clipe no editor. | | Em clipe de áudio não faz nada. |

**Nome exibido no clipe:** o de áudio mostra o nome do arquivo; o de notas, o nome do clipe (ou o da faixa, se vazio), com um ícone de lápis quando está aberto no editor. Clipe de áudio cujo arquivo não está neste aparelho fica avermelhado com o texto `áudio fora deste aparelho`.

**Selos no clipe de áudio:** um selo escuro com `W` (warp), `+3st` (semitons) e `R` (invertido), ou `processando…`, se houver processamento (tooltip `Warp e altura`, `Processando o warp…`, ou `O warp não ficou pronto: o clipe toca o original`); e `N tomadas` (só o número em clipe curto) para gravações em loop, com o tooltip `Tomada X de N: escolher outra`. Os selos somem em clipes muito estreitos (menos de 40 px o de warp, menos de 60 px o de tomadas).

#### Menu do clipe de áudio

| Item | O que faz |
|---|---|
| **Tomadas** (só com tomadas; mostra a quantidade) | Abre a lista `TOMADAS` (`Tomada 1`, `Tomada 2`…, a ativa marcada; `fora deste aparelho` nas que faltam). Escolher troca o áudio; posição, corte e fades ficam. Desfazível. |
| **Duplicar** (Ctrl+D) | Copia para logo depois. |
| **Cortar no cursor** (S) | Divide no cursor. |
| **Warp e altura…** | Abre a janela de warp. Ver [Warp e altura](03b-warp-e-altura.md). |
| **Converter em notas (MIDI)** | Cria uma faixa de sintetizador com as notas detectadas no áudio. Ver [Áudio para MIDI](03d-audio-para-midi.md). |
| **Apagar** (Delete) | Apaga o clipe. |

#### Menu do clipe de notas

| Item | O que faz |
|---|---|
| **Abrir no editor** (E) | Abre o clipe no piano roll. |
| **Renomear** | Janela **Nome do clipe** (campo **Nome**, sugestão com o nome da faixa, até 60 caracteres, **Salvar**). |
| **Duplicar** (Ctrl+D) | Copia para logo depois; o editor aberto passa para a cópia. |
| **Cortar no cursor** (S) | Divide no cursor; uma nota que cruza o corte vira duas. |
| **Apagar** (Delete) | Apaga o clipe. |

Os atalhos do menu são escritos `Ctrl` mesmo no Mac (vale o Cmd).

### Cortar, duplicar, apagar e sobreposição

- **Cortar (S):** com um clipe selecionado, divide só ele, se o cursor estiver dentro dele. Sem seleção, divide todos os clipes que o cursor cruza na faixa selecionada. As duas metades ficam com o mesmo som; o fade in fica na esquerda e o fade out, na direita.
- **Duplicar (Ctrl+D):** a cópia começa onde o original termina e fica selecionada.
- **Apagar (Delete ou Backspace):** apaga o clipe selecionado e deixa o vão.
- **Copiar e colar clipes:** a timeline não tem (Ctrl+C e Ctrl+V só existem no piano roll, para notas). Use Duplicar.
- **Sobreposição:** um clipe nunca toca somado com outro da mesma faixa. Ao terminar um arraste (mover ou aparar) e ao duplicar, o clipe que você mexeu fica por cima e o que ele cobre dos outros é cortado: o outro encurta, perde o começo, é partido em dois (se o seu clipe cai no meio dele) ou some (se fica todo coberto). Tudo isso é um passo só do desfazer. Áudio e notas seguem a mesma regra. Nos pedaços que sobram, o fade do lado cortado é zerado; só quando o seu clipe cobre o fim de outro, o fade de saída desse outro apenas é limitado ao novo tamanho.

### Rolagem e zoom

| Gesto | O que faz | Dica |
|---|---|---|
| Roda do mouse (vertical) | Rola a lista de faixas para cima e para baixo. | Cabeçalhos e raias rolam juntos. |
| **Shift** + roda, ou roda horizontal / trackpad de lado | Rola a linha do tempo na horizontal. | |
| **Ctrl** (ou Cmd) + roda | Zoom com centro no ponto do mouse. | Fator de 1,0015 por unidade de roda; 4 a 800 px por batida. |
| Arrastar no vazio das raias (mouse ou dedo) na horizontal | Rola a linha do tempo. | No dedo, é o jeito principal de andar pelo projeto. |
| Arrastar na vertical (dedo) | Rola a lista de faixas. | |
| Botões **Afastar** e **Aproximar**, teclas − e +, Z e Shift+Z | Zoom e enquadramento. | Ver [Transporte](02-transporte.md). |

Não há zoom de pinça com dois dedos: no celular use os botões **Afastar** e **Aproximar**.

### Altura das faixas

O menu **Visão** da barra escolhe **Faixas pequena (P)**, **Faixas média (M)** ou **Faixas grande (G)**. A altura da faixa é 76 px (computador) ou 64 px (celular) vezes 0,7, 1 ou 1,5. As sub-raias de automação têm altura própria e não mudam. Não há atalho de teclado para isso.

### Master

A linha **Master** (ícone de alto-falante) fica no fim da lista, depois da linha Nova faixa, e rola com ela (não fica fixa na tela). Tem faixa de cor cinza-clara e:

| Controle | O que faz | Valores | Dica |
|---|---|---|---|
| **A** (`Automação`) | Automação do master (volume, pan e parâmetros dos efeitos dele). | | Ver [Automação](07-automacao.md). |
| **FX** (`Efeitos`) | Abre a cadeia de efeitos do master. | | Ver [Painel de efeitos](06c-painel-de-efeitos.md). |
| Mini fader (só no computador) | Volume do master; o tooltip mostra os dB. | −∞ a +6 dB | |
| Medidor de 6 px | Pico do master. | | |

O Master não tem M, S nem bolinha de gravar, e a raia dele não recebe clipes.

### Minimapa Visão geral

Uma faixa fina de 28 px embaixo da lista, com o rótulo `Visão geral` à esquerda (o nome acessível é `Visão geral do projeto`). Ela mostra o projeto inteiro numa linha por faixa: clipes na cor da faixa, a região do loop (sombreada, mais forte com o loop ligado), os marcadores (traços na cor deles), a janela visível (retângulo claro) e o cursor (traço branco).

| Ação | O que faz | Dica |
|---|---|---|
| Clicar | Leva a janela: o ponto clicado vira o centro do que você vê. | Não muda o zoom nem o cursor. |
| Arrastar na horizontal | Rola continuamente. | |

A escala do minimapa é o fim do arranjo mais 5% (no mínimo 4 compassos), para dar para arrastar um pouco além do último clipe.

### Marcadores e seções

Marcadores são bandeirinhas na régua (etiqueta de até 96 px com o nome, haste de 1,5 px). Ficam ordenados e são salvos com o projeto.

| Ação | Como | O que faz |
|---|---|---|
| Criar | **M**, ou o item **Marcador no cursor (M)** do menu Seções | Marcador no cursor, com o nome `Marcador N` (N = quantidade + 1) e a primeira cor (âmbar). Se já há um ali (diferença menor que 1/1000 de batida), só o seleciona. |
| Criar pedindo o nome | **Shift+M** | Abre **Nome do marcador** (campo **Nome**, até 40 caracteres, **Salvar**). Se há marcador no cursor, renomeia; senão cria com esse nome. Cancelar ou nome vazio não faz nada. |
| Ir até ele | Clicar na bandeirinha | Leva o cursor ao marcador (e rola a janela se estiver fora) e o seleciona (borda branca). Gravando, o cursor não se move. |
| Mover | Arrastar a bandeirinha | Move com encaixe (Alt: livre). O arraste inteiro é um passo do desfazer, e só entra se o marcador andou. |
| Renomear | Duplo clique | Janela **Nome do marcador**. |
| Menu | Botão direito, ou toque longo | **Renomear**, **Loop desta seção** (leva o cursor ao marcador e faz loop da seção dele), seis bolinhas de cor (`Cor do marcador`: âmbar, vermelho, azul, verde, roxo, rosa) e **Apagar o marcador**. |
| Pular | **[** e **]** | Cursor no marcador anterior / seguinte. Sem marcador antes, `[` vai ao compasso 1. |

Tooltip da bandeirinha: `nome · posição` e `Arraste para mover · duplo clique renomeia · botão direito: menu`.

**Seções:** a seção de um marcador vai dele até o próximo marcador; a última vai até o fim do arranjo (o maior entre o último clipe, o último marcador e o fim do loop ligado). Antes do primeiro marcador não há seção. O menu **Seções e marcadores** da barra faz os loops de seção, entre marcadores e do clipe (ver [Transporte](02-transporte.md)). Todos ligam o loop e são um passo do desfazer; não funcionam gravando.

### Dock: o painel de baixo

O painel de baixo divide a altura com a timeline. Abre pelos botões da barra (X, E, I, F) ou pelas abas dele.

| Controle | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| Aba **Mixer** (`Mixer (X)`) | Mostra o mixer. | | Em janela abaixo de 560 px todas as abas mostram só o ícone. |
| Aba **Editor** (`Editor de notas (E)`) | Piano roll. Abre no clipe de notas selecionado, se houver. | | |
| Aba **Instrumento** (`Instrumento da faixa (I)`) | Painel do instrumento; o ícone é o do tipo da faixa selecionada. | | |
| Aba **Efeitos** (`Efeitos da faixa (F)`) | Cadeia da faixa selecionada (master se não há faixa). Clicar nela com o painel já em Efeitos não troca o que está à vista (por exemplo, o master aberto pelo mixer). | | |
| Texto de contexto (à direita das abas) | Diz de quem o painel fala: `clipe · faixa` no editor (`Nenhum clipe aberto` sem clipe); `faixa · tipo` no instrumento (`faixa de áudio, sem instrumento` / `barramento, sem instrumento`); `faixa · N efeitos` (`sem efeitos`, `1 efeito`) nos efeitos, ou `Master · ...`. Bolinha na cor da faixa. | | |
| **Maximizar o painel** / **Restaurar a altura** (seta para cima/baixo; só no computador) | Alterna entre a altura atual e a altura máxima. | | |
| **Fechar o painel (Esc)** (X) | Fecha o painel. | | |
| Alça no topo (barra fina de 6 px) e área vazia da barra de abas | Arrastar na vertical redimensiona o painel; duplo clique na alça maximiza e restaura. A alça acende ao passar o mouse. | Altura padrão: metade do espaço disponível, mínimo 320 px. Mínima 230 px; a timeline mantém ao menos 150 px. | A altura escolhida vale até fechar o app. |

No celular o painel ocupa sempre 60% do espaço, sem alça nem botão de maximizar.

## Passo a passo

**Criar uma faixa de instrumento e um clipe de notas**
1. Na linha **Nova faixa**, toque e escolha **Sintetizador**.
2. Dê duplo clique numa parte vazia da raia, no compasso que quiser. Nasce um clipe de 1 compasso e o editor abre.
3. Escreva as notas no piano roll ([Piano roll](05-piano-roll.md)).

**Cortar uma parte e apagar**
1. Toque no clipe para selecioná-lo.
2. Clique na régua no ponto do corte e aperte S.
3. Selecione a metade que sobra e aperte Delete. O vão fica; arraste o clipe seguinte para fechá-lo.

**Repetir um trecho**
1. Selecione o clipe e aperte Ctrl+D várias vezes: cada cópia sai colada no fim da anterior.
2. Se uma cópia cai sobre outro clipe, o outro é aparado sozinho.

**Organizar a música em seções**
1. Ponha o cursor no começo do refrão e aperte Shift+M; digite `Refrão`.
2. Repita para cada parte.
3. Abra **Seções e marcadores** e escolha um marcador para ir até ele, ou **Loop desta seção** para ensaiar a parte.

**Reordenar uma faixa**
1. Segure o cabeçalho da faixa até ele ganhar uma borda colorida.
2. Arraste para cima ou para baixo (o texto mostra `Mover para a posição N`) e solte.

## Combina com

- [Transporte](02-transporte.md): grade, zoom, loop e enquadramento, que valem para tudo aqui.
- [Áudio e clipes](03-audio-e-clipes.md): importar, fades e as propriedades do clipe de áudio.
- [Warp e altura](03b-warp-e-altura.md) e [Áudio para MIDI](03d-audio-para-midi.md): itens do menu do clipe de áudio.
- [Piano roll](05-piano-roll.md): editar o clipe de notas.
- [Mixer](06-mixer.md), [Automação](07-automacao.md) e [Exportação](08-exportacao.md) (**Congelar em áudio**): botões do cabeçalho e do menu da faixa.
- Receitas: pasta [`../guias/`](../guias/).

## Limites e pegadinhas

- **Um clipe selecionado por vez.** Não há seleção múltipla, laço de seleção nem mover vários clipes juntos.
- **Sem copiar e colar clipes** na timeline; sem ganho por clipe na interface (o campo de ganho existe no arquivo do projeto e o desenho da onda o reflete, mas nenhum controle o altera). Volume se ajusta na faixa (mini fader ou mixer).
- **O único modificador de arraste é o Alt** (encaixe livre), nos clipes, marcadores e ao aparar. Shift e Ctrl não mudam o arraste; valem só na roda do mouse (Shift: horizontal, Ctrl: zoom) e nos atalhos.
- **Só o clipe que você mexeu é preservado numa sobreposição:** o cortado dos outros é apagado do arranjo (o desfazer traz de volta). Se quiser guardar as duas partes, mova o clipe para outra faixa.
- **Áudio só muda para faixa de áudio; notas só para faixa de instrumento.** Soltar sobre outro tipo deixa o clipe na faixa de origem.
- **Gravando** ficam travados: clicar e arrastar na régua e nas raias (cursor), marcadores (ir até eles), loop e o botão de armar. Faixas armadas mostram uma região vermelha crescendo (`Gravando`, ou `Tomada N` gravando em loop).
- **Faixa só de barramento:** não tem clipes nem bolinha de gravar; a raia mostra `Barramento: recebe o som das faixas que enviam ou saem para ele`.
- **Tudo daqui vai para o projeto** (faixas, clipes, marcadores, loop), exceto zoom, rolagem, altura das faixas, seleção e modo da régua.
- **Web e Android:** o mesmo comportamento; no celular a seleção de clipes por toque usa bordas de 16 px, o menu do clipe abre com toque longo, e o duplo toque cria o clipe de notas.

## Atalhos

| Tecla / gesto | Ação |
|---|---|
| S | Cortar no cursor |
| Ctrl+D | Duplicar o clipe |
| Delete ou Backspace | Apagar o clipe |
| M | Marcador no cursor |
| Shift+M | Marcador pedindo o nome |
| `[` / `]` | Marcador anterior / seguinte |
| Shift+L | Loop no clipe (ou na seção do cursor) |
| Z / Shift+Z | Enquadrar tudo / o clipe selecionado |
| X, E, I, F, Esc | Alternar Mixer, Editor, Instrumento, Efeitos; fechar o painel |
| Alt ao arrastar | Encaixe livre |
| Ctrl + roda | Zoom no ponto do mouse |
| Shift + roda | Rolar na horizontal |
| Duplo clique na raia (faixa de instrumento) | Criar clipe de notas |
| Duplo clique no clipe de notas | Abrir no editor |
| Duplo clique no nome da faixa | Renomear |
| Duplo clique na bandeirinha | Renomear o marcador |
| Botão direito no clipe ou na bandeirinha | Menu de contexto |
