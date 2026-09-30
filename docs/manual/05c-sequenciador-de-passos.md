# Sequenciador de passos

> Uma grade de quadradinhos (uma linha por peça da bateria ou por fatia do sampler, um quadrado por subdivisão do compasso) para programar batidas com cliques em vez de notas no piano roll; use para montar um ritmo em minutos, com acentos, notas fantasma, swing e nove padrões de fábrica.

![A aba Passos de uma faixa de bateria: a barra (Passo, Compassos, Swing, Aplicar swing e Tirar swing, os pincéis Normal, Acento e Fantasma, Padrões e Ações) e a grade com uma linha por peça; a batida que já existia aparece como grade.](../img/passos-sequenciador.jpg)

*A aba Passos de uma faixa de bateria: a barra (Passo, Compassos, Swing, Aplicar swing e Tirar swing, os pincéis Normal, Acento e Fantasma, Padrões e Ações) e a grade com uma linha por peça; a batida que já existia aparece como grade.*

![O diálogo Padrões de bateria, com a descrição de cada padrão de fábrica; escolher um escreve o padrão na faixa e avisa com uma mensagem.](../img/passos-padroes.jpg)

*O diálogo Padrões de bateria, com a descrição de cada padrão de fábrica; escolher um escreve o padrão na faixa e avisa com uma mensagem. Captura da fase 17, que não acompanha a fase 19 (A): ela mostra só oito dos nove padrões (o `Shuffle (tercinas)` ficava fora da tela), não tem o botão `Cancelar` e traz os textos antigos de `Rock` e `Reggaeton (dembow)`. Hoje o conteúdo do diálogo rola por inteiro, com o título fixo, e o texto certo de cada padrão está na tabela de [Padrões de fábrica](#padrões-de-fábrica).*

## Onde fica

- Aba `Passos` do painel de baixo (tooltip `Sequenciador de passos da bateria e do sampler fatiado`), entre `Editor` e `Instrumento`. Não há botão na barra de transporte nem tecla própria.
- A aba só aparece na barra de abas quando a faixa selecionada é uma `Bateria` ou um `Sampler` que tem ao menos uma zona (áudio único, sem zonas, não conta). Se você já está na aba e seleciona uma faixa de outro tipo, a aba fica e mostra `Sequenciador de passos` com o texto `Selecione uma faixa de bateria ou um sampler com zonas (fatias) para desenhar batidas em passos.`
- O assunto ao lado das abas diz `<clipe> · <faixa>` (ou só `<faixa>`, se o clipe não tem nome).
- Com a aba `Passos` visível há seis abas: abaixo de 760 px de largura os rótulos somem e ficam só os ícones (sem a aba `Passos`, o limite é 560 px). Isso vale para o computador e para o celular.
- `E`, `I`, `X` e `F` trocam para as abas `Editor`, `Instrumento`, `Mixer` e `Efeitos`, como sempre; não existe atalho que abra a aba `Passos`.

**Que clipe a grade edita.** O clipe de notas da faixa selecionada, nesta ordem: o clipe selecionado no arranjo, o aberto no editor, ou o que está debaixo do cursor de reprodução. Sem nenhum deles, a aba mostra `Nenhum clipe de notas sob o cursor`, o texto `A faixa <nome> não tem um clipe de notas aqui.` e o botão `Criar clipe aqui`. O botão cria um clipe de um compasso a partir do começo do compasso do cursor (empurrado para depois de um clipe que já ocupe o lugar, e encurtado se o próximo clipe começa antes de fechar o compasso).

**É uma visão, não um formato.** A grade lê e escreve as mesmas notas do clipe que o [piano roll](05-piano-roll.md) mostra. Não há dado novo no projeto: o som, o `.mid` exportado, o `Ctrl+Z` e a sincronização são os das notas de sempre.

## Controles

### Barra da aba

Em janelas de 700 px ou mais a barra quebra em linhas; abaixo disso ela é uma linha só que rola na horizontal.

| Controle (rótulo exato) | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| `Passo` (menu) | Escolhe a resolução: quanto vale um quadrado | `1/4 · 4/comp.`, `1/8 · 8/comp.`, `1/8 tercina · 12/comp.`, `1/16 · 16/comp.`, `1/16 tercina · 24/comp.`, `1/32 · 32/comp.`, `1/64 · 64/comp.` (o número depois do ponto é quantos passos cabem num compasso de 4 tempos; em outro compasso ele muda). Padrão `1/16` | Trocar a resolução não mexe nas notas, só na grade que as lê |
| `Compassos` com `−` (tooltip `Menos um compasso`), número e `+` (tooltip `Mais um compasso`) | Tamanho do padrão, em compassos | 1 a 8. Enquanto você não mexe nos botões, é automático: os compassos que cobrem as notas do clipe (pelo início da última nota), no mínimo 1 e no máximo os compassos do clipe | Depois do primeiro clique em `−` ou `+` o valor fica fixo até você fechar o app |
| `Swing N%` e o controle deslizante ao lado | Escolhe o swing que `Aplicar swing` vai gravar. Ao abrir, mostra o swing que o clipe já tem nesta resolução: o da dica guardada no clipe, se ela bate com as notas, ou o que as notas mostram (ver [Swing](#swing)) | 0 a 75%, de 1 em 1; 0% quando as notas estão retas | Só o número muda ao arrastar; as notas só andam ao clicar em `Aplicar swing`. O valor arrastado só vale enquanto o swing do clipe é o mesmo de quando você arrastou: se ele muda por fora (`Ctrl+Z`, piano roll, outro padrão), o controle volta a mostrar o do clipe. Trocar o `Passo` (e escolher um padrão) também zera o valor arrastado |
| `Aplicar swing` | Atrasa as notas dos passos pares, em todo o clipe, até o valor escolhido | Só liga quando o controle está diferente do swing que o clipe tem nesta resolução. Aviso: `Swing de N% aplicado (M notas, em <resolução>).` (por exemplo `em 1/16`; com uma nota só, `1 nota`). Se nenhuma nota está nos passos pares da resolução atual, não muda nada e avisa `Nenhuma nota está nos passos pares de <resolução>: troque a resolução para a das notas ou desenhe algo antes.` | Um passo do `Ctrl+Z`, que desfaz as notas, a dica do swing e o valor do controle juntos. Também grava no clipe a resolução e o valor aplicados (a dica, ver [Swing](#swing)) |
| `Tirar swing` | Devolve as notas ao passo reto, na resolução em que o swing foi aplicado (a da dica do clipe, mesmo com a grade aberta em outro `Passo`) | Liga quando o clipe tem swing nesta resolução (como o [Swing](#swing) o lê) **ou** quando a dica do clipe bate com as notas, em qualquer resolução. Aviso: `Swing tirado (M notas, em <resolução>).` (por exemplo `Swing tirado (8 notas, em 1/16).`; com uma nota só, `1 nota`). Se nenhuma nota anda, avisa `Nenhuma nota está nos passos pares de <resolução>: …` como o `Aplicar swing` | Um passo do `Ctrl+Z` (desfaz notas e dica juntas). Aplicar e depois tirar volta exatamente às notas de antes, inclusive num clipe só com contratempos |
| `Normal`, `Acento`, `Fantasma` (pincéis) | Escolhem a velocidade dos passos que você liga | `Normal` 0,80 (padrão), `Acento` 1,00, `Fantasma` 0,30 | Vale também para `Inverter` e `Preencher a cada N passos…` |
| `Padrões` (só na bateria) | Abre `Padrões de bateria`, com 9 padrões prontos | Ver [Padrões de fábrica](#padrões-de-fábrica) | No sampler o botão não existe |
| `Ações` (ícone de reticências; tooltip `Ações do padrão`) | Menu de operações sobre o padrão | Ver [Ações](#ações) | |

Depois de uma ação, um aviso em cor de destaque aparece sob a barra (`Padrão copiado (N notas).`, `Padrão copiado (1 nota).` no singular, e os outros abaixo). Ele some quando você troca a resolução ou faz outra ação sem aviso.

Nada dessa barra é salvo com o projeto: resolução, `Compassos`, pincel e linha selecionada valem enquanto o app está aberto, um conjunto por clipe. O swing é a exceção: o que vale é lido das notas do clipe, que são salvas, e o `Aplicar swing` guarda no próprio clipe uma dica (a resolução e o valor, campo `swing_hint` do clipe MIDI; ver [Swing](#swing)), que vai no projeto, na nuvem e no `.jopendaw`.

### A grade

| Elemento | O que é | Dica |
|---|---|---|
| Nomes das linhas (152 px de largura; 112 px abaixo de 560 px de janela) | Uma linha por peça ou fatia. Tocar no nome seleciona a linha (fundo colorido e nome em negrito); tocar de novo tira a seleção | A seleção decide a quem as `Ações` se aplicam e abre a faixa `Velocidade` |
| Alto-falante no fim do nome (tooltip `Ouvir <nome>`) | Toca a peça uma vez, na velocidade 0,80, por 220 ms | Só com o transporte parado |
| Régua de cima | Um número por tempo: o do compasso em destaque no começo de cada um, depois `2`, `3`, `4` | Em `1/4` cada quadrado é um tempo |
| Quadrados (32 a 56 px de largura, 32 px de altura) | Cada um é um passo. Apagado: cinza escuro. Aceso: a cor da faixa | A grade ocupa a largura da janela; se 32 px por passo não cabem, ela rola na horizontal |
| Altura do preenchimento | Mostra a velocidade: de 30% da altura (velocidade 0) a 100% (velocidade 1) | Um filete branco no topo marca o acento; o fantasma fica mais transparente |
| Contorno âmbar com um ponto | Nota fora da grade (ver adiante) | |
| Faixa de fundo mais clara | Os tempos 2 e 4 (a cada tempo par) | Ajuda a se localizar em `1/32` e `1/64` |
| Passos escurecidos | Passos que caem depois do fim do clipe | Não se editam por clique; estique o clipe |
| Linha vertical branca | O cursor de reprodução, com o passo atual iluminado. Ele dá a volta na largura do padrão (`Compassos`) e a grade rola sozinha para acompanhá-lo | Só na reprodução |
| Faixa `Velocidade <nome da linha>` (64 px de altura, embaixo da grade) | Aparece quando há uma linha selecionada: uma barra por passo aceso | Ver [Velocidade](#velocidade-pincéis-acento-duplo-clique-e-a-faixa) |

## Gestos

| Gesto | O que faz |
|---|---|
| Clicar num passo apagado | Acende com a velocidade do pincel e toca a peça (se o transporte está parado) |
| Clicar num passo aceso | Apaga (todas as notas que caem naquele passo) |
| Arrastar com o mouse | O primeiro passo decide: começando num passo apagado, o arraste acende os apagados por onde passa; começando num aceso, apaga. Ele fica na linha em que começou. Um gesto inteiro é um passo do `Ctrl+Z` |
| Dois cliques rápidos no mesmo passo (até 320 ms entre eles) | O passo vira acento (1,00), qualquer que seja o pincel. Cada clique é um passo do `Ctrl+Z` |
| Toque curto (celular) | Liga ou desliga o passo, como um clique |
| Arrastar o dedo (celular) | Rola a grade; não pinta |
| Segurar o dedo 300 ms e arrastar (celular) | Pinta ou apaga como o mouse, com a rolagem travada. Mexer o dedo mais de 10 px antes disso cancela o toque longo e vira rolagem |
| Tocar o nome da linha | Seleciona ou desmarca a linha. Clicar num passo também seleciona a linha dele |

## Velocidade: pincéis, acento, duplo clique e a faixa

- **Os três pincéis** gravam a velocidade de cada passo novo: `Normal` 0,80, `Acento` 1,00, `Fantasma` 0,30. Um passo é lido como acento a partir de 0,95 e como fantasma até 0,40; qualquer valor entre eles aparece como normal. Trocar o pincel não muda passos que já estão acesos.
- **Duplo clique** acende (ou reacende) o passo como acento, mesmo com o pincel em `Normal`.
- **Faixa `Velocidade`**: com uma linha selecionada, arraste sobre a barra de um passo aceso: a altura do ponteiro dentro dos 64 px vira a velocidade (topo 1,00, base 0,05). Só muda passos que já existem; nunca cria nem move nota. Um gesto inteiro é um passo do `Ctrl+Z`.
- Uma nota vinda do piano roll com velocidade 0,55, por exemplo, aparece como passo normal, com o preenchimento na altura certa.
- No `Sampler` a velocidade escolhe a camada de velocidade das zonas (ver [04c](04c-sampler.md)); na bateria ela muda o nível e um pouco o timbre do golpe (ver [04b](04b-bateria.md#programar-no-piano-roll) e o passo a passo de notas fantasma).

## Resoluções e como a grade lê as notas

- **A grade não adivinha a resolução.** Ela abre em `1/16` (16 passos por compasso de 4 tempos) em todo clipe e só muda quando você escolhe outra em `Passo` ou aplica um padrão de fábrica. `Compassos`, esse sim, é calculado pelas notas do clipe enquanto você não o fixa.
- **Passo aceso** quer dizer: existe nota daquela linha a até 1/1000 de batida do início do passo.
- **Fora da grade.** Uma nota que não cai em nenhum passo (humanizada, tocada ao vivo, ou escrita em `1/32` quando a grade está em `1/16`) aparece no passo mais próximo, com contorno âmbar e um ponto. Se a nota fica no meio de dois passos, vai para o anterior. Editar outros passos não a move. Apagar aquele passo apaga todas as notas dele, as fora da grade também.
- **Duas notas no mesmo passo.** Se a resolução é mais grossa que a das notas, várias notas da mesma linha caem no mesmo quadrado. Se uma delas está exatamente no passo, o quadrado parece normal e as outras ficam escondidas atrás; clicar nele apaga todas juntas. Para ver o que há de verdade, escolha a resolução que combina com as notas (por exemplo `1/32` num padrão de rolos).
- **Tercinas.** `1/8 tercina` (12 passos por compasso de 4/4) e `1/16 tercina` (24) dividem o tempo em 3 e em 6. Notas de tercina em grade reta aparecem fora da grade, e o contrário também.
- **Outros compassos.** Em 3/4 o compasso tem 3 tempos; o número de passos por compasso e o desenho da régua seguem o compasso do clipe no mapa de compassos ([guia](../guias/mapa-de-andamento-e-compasso.md)). Os padrões de fábrica também: cortados em 3 tempos, repetidos em compassos maiores que 4 (ver [Padrões de fábrica](#padrões-de-fábrica)).
- **Notas fora do padrão.** Notas depois do fim do padrão (`Compassos`) e notas de alturas que não são linhas da grade (por exemplo uma nota melódica num clipe de bateria) não aparecem e não são mexidas pelas ações de limpar, inverter, deslocar e preencher. Só `Repetir até o fim do clipe` as leva, e o swing (`Aplicar swing` e `Tirar swing`) também as alcança, porque vale para o clipe todo e para qualquer altura (inclusive uma nota melódica que esteja exatamente num passo par).
- **Comprimento das notas que a grade cria:** o do passo, no máximo 1/16 de batida (0,25). A bateria toca a peça inteira de qualquer jeito; no `Sampler`, ver [Sampler com zonas](#sampler-com-zonas).

## Swing

- **A conta.** Os passos pares da grade (o 2º, o 4º, o 6º..., contando de 1) começam mais tarde que o passo reto por `swing × duração do passo`. A 1/16 (0,25 batida) e 50%, o 2º passo de cada par sai 0,125 batida depois (62,5 ms a 120 BPM). A 33% o segundo 16 cai em 0,3325 batida, quase a tercina (0,333); 75% é o máximo. Vale em qualquer resolução: em `1/8` atrasa as colcheias fracas, em `1/16` as semicolcheias fracas.
- **`Aplicar swing`** move só as notas que estão exatamente num passo par da resolução escolhida, no swing atual, em todas as linhas e **no clipe todo**, não só nos `Compassos` do padrão. Notas fora da grade e passos ímpares (o 1º, o 3º...) não se movem. Se já havia swing, ele vai do valor atual ao novo. Em `1/8` são as colcheias fracas (os contratempos) que andam; em `1/16`, as semicolcheias fracas. Se nenhuma nota está num passo par da resolução atual, o botão não edita nada e o aviso `Nenhuma nota está nos passos pares de <resolução>: troque a resolução para a das notas ou desenhe algo antes.` diz o que fazer.
- **A grade passa a enxergar o swing.** Depois de aplicar, os passos continuam acesos e os novos cliques nos passos pares já caem atrasados.
- **A dica do swing (fase 25, `55cc53b`).** `Aplicar swing` também grava no clipe a resolução e o valor aplicados, num campo opcional do clipe MIDI (`swing_hint`, por exemplo `1/16:40` para 40% em `1/16`; os ids das resoluções são `1/4`, `1/8`, `1/8T`, `1/16`, `1/16T`, `1/32` e `1/64`). A dica é só uma anotação: nunca vale sozinha, o app a confere contra as notas e, se elas não batem, a ignora. Ela vale quando (1) ao menos uma nota está exatamente num passo par (o 2º, o 4º...) da resolução dela, atrasada do tanto que a dica diz, e (2) nenhuma nota está exatamente num passo par sem atraso (sinal de que o clipe foi mexido depois). Notas fora da grade e rolos não contam contra, e a conta olha o clipe todo, de qualquer altura, não só os `Compassos`. É a dica que cobre o que a leitura das notas não alcança (clipe só com contratempos, swing de 50% com rolos de 1/32) e que deixa tirar o swing na resolução em que ele foi aplicado. Quem apaga a dica: `Tirar swing` e `Padrões`; editar as notas à mão só a invalida (ela continua escrita no projeto e volta a valer se as notas voltarem a bater, por exemplo com `Ctrl+Z`). Dividir um clipe deixa a dica nos dois pedaços (cada um a confere com as suas notas) e duplicar o clipe a leva junto `(lido do código)`. Um projeto de antes da fase 25 não tem dica: o swing dele é lido só das notas, como antes. `(testado só por testes automáticos)`
- **`Tirar swing`** volta as notas dos passos pares ao passo reto. Com a dica válida, tira o swing dela na resolução dela (mesmo que `Passo` esteja em outra), e zera a dica; sem dica, tira o que as notas mostram na resolução de `Passo`. O botão acende também quando só a dica vale (o controle `Swing` pode mostrar 0% em outra resolução e o botão estar ligado). `Aplicar swing` seguido de `Tirar swing` devolve as notas exatamente às posições de antes, em qualquer clipe: só com contratempos, com swing de 50% e rolos, com a grade aberta em outra resolução. `Ctrl+Z` desfaz notas e dica no mesmo passo. `(testado só por testes automáticos)`
- **O swing é lido das notas, não guardado na tela (desde a fase 19 A, `fc5878b`; regra de leitura refeita na fase 22, `938272c` e `aa563b3`; dica guardada no clipe na fase 25, `55cc53b`).** A cada desenho da grade o app olha as notas do clipe inteiro na resolução em `Passo` e só diz que há swing quando o desenho é mesmo uma grade com swing. Cada nota pertence ao passo que começa antes dela (da posição reta desse passo até a do seguinte). O controle mostra N% (de 1 em 1, de 1 a 75, com a tolerância de 1/1000 de batida) quando: (1) **todas** as notas dos passos pares (o 2º, o 4º...) estão atrasadas do mesmo N% do passo; (2) há ao menos uma nota exatamente num passo ímpar (o 1º, o 3º...); e (3) nenhuma nota dos passos ímpares está fora da grade (salvo o rolo, ver adiante). Fora disso lê 0%: humanização (atrasos diferentes, ou uma só nota fora do lugar; uma nota reta num passo par junto com as atrasadas também), tercinas vistas em `1/16`, um rolo de 1/32 sozinho, notas só nos passos pares, notas todas retas, atraso acima de 75% (o controle só mostra o valor de um clipe só com notas nos passos pares, ou de um swing de 50% com rolos, se a dica do clipe bate com as notas, ver acima). A regra antiga (escolher o valor que deixasse mais notas na grade, com desempate para o reto) deixou de existir: em `1/8` a colcheia reta é 0% e só o atraso comum a todas as colcheias fracas vira swing. Por isso: `Ctrl+Z` logo depois de `Aplicar swing` desfaz as notas e o swing mostrado junto (o controle volta a 0% e `Tirar swing` apaga); fechar e reabrir o projeto mostra o swing que as notas têm e deixa `Tirar swing` ligado; e uma edição no [piano roll](05-piano-roll.md) que muda o atraso das notas também muda o controle. Antes da fase 19 (A) o valor era estado da tela e sumia ao recarregar, deixando as notas atrasadas com contorno âmbar e `Tirar swing` apagado. O swing arrastado no controle (e ainda não aplicado) também não é escrito em lugar nenhum: só vale enquanto o que as notas têm não muda. `(testado só por testes automáticos)`
- **Rolos de 1/32 não atrapalham a leitura (`aa563b3`).** Uma nota a meio passo (o rolo de 1/32 visto em `1/16`) é ignorada quando está num passo ímpar (o 1º, o 3º...); quando está num passo par (o 2º, o 4º...) a 50% do passo, é ignorada se as outras notas dos passos pares dão um swing, então um chimbal de `1/16` com rolo no fim lê o swing certo depois de `Aplicar swing`, e `Aplicar swing` seguido de `Tirar swing` devolve as notas às posições de antes, rolo incluído. Só notas a 50% nos passos pares, sem nenhuma outra, valem como swing de 50% se não houver nota a meio passo nos passos ímpares. Limitação das notas: um swing de exatamente 50% num clipe que tem rolos nos passos ímpares não se distingue do rolo e as notas sozinhas leem 0%. Desde a fase 25 isso deixou de travar: a dica do clipe (`1/16:50`) bate com as notas, o controle mostra 50%, `Tirar swing` fica ligado e devolve as notas às posições de antes, rolos incluídos. Sem a dica (projeto de antes da fase 25, ou notas mexidas depois), o controle fica em 0% e `Tirar swing` apagado. `(testado só por testes automáticos)`
- **O swing lido depende da resolução.** Ele é calculado na resolução em `Passo`: cada resolução lê o seu. Um clipe de semicolcheias seguidas com swing aplicado em `1/16` mostra `Swing 0%` em `1/8` (coberto por teste), porque em `1/8` as notas atrasadas caem em passos pares fora da grade; volte a `1/16` para ver o valor e para usar `Tirar swing`. Na resolução mais fina a mesma batida pode aparecer como outro valor: um swing de 40% em `1/16` é, matematicamente, um de 60% em `1/64` (vale para uma faixa de valores, não só 40%). Com `Passo` em `1/64` o controle mostra o que as notas dizem (`Swing 60%`), mas, se a dica do clipe (`1/16:40`) ainda bate, `Tirar swing` leva as notas à grade de `1/16`, a em que o swing foi aplicado, e não à de `1/64` (fase 25); sem a dica (projeto antigo), ele tiraria o swing que as notas mostram em `1/64`. Aplicar um swing numa resolução diferente da dica troca a dica pela nova: o swing antigo fica nas notas, mas deixa de ser conhecido pelo `Tirar swing` `(deduzido do código)`. Humanização e gravação ao vivo (notas deslocadas para o meio dos passos) deixaram de ser lidas como swing com a regra da fase 22.
- **Trocar `Passo` zera o valor arrastado (fase 25).** O valor que você arrastou no controle (sem aplicar) vale só para a resolução em que foi arrastado e enquanto o swing do clipe não muda por baixo dele; ao escolher outro item do menu `Passo` (e ao escolher um padrão em `Padrões`) o controle volta a mostrar o swing do clipe naquela resolução e `Aplicar swing` apaga, em vez de levar o número arrastado para a grade nova (antes da fase 25 ele sobrevivia à troca, quase sempre porque o swing lido era 0%). `(testado só por testes automáticos)`
- **Padrão de fábrica com swing ligado:** `Padrões` tira o swing que o clipe tinha (de todas as notas do clipe, não só as do padrão, para a grade não ficar meio no swing e meio reta) e escreve o padrão reto, tudo no mesmo passo do `Ctrl+Z`: o controle volta a 0%, a dica do clipe é apagada e, desfazendo, o swing volta junto com as notas e a dica. **Só sai o swing que se sabe que é swing (fase 25, `55cc53b`):** (1) o da dica do clipe, na resolução em que foi aplicado (por isso um swing aplicado em `1/16` sai também ao escolher `Trap`, em `1/32`, ou `Shuffle (tercinas)`, em `1/8 tercina`, mesmo com `Passo` em outra resolução); e (2) o que as notas mostram na resolução que `Passo` tinha antes de você abrir `Padrões` e na resolução do padrão escolhido. Notas que só por acaso formam swing em outra resolução (por exemplo, notas em 0, 0,75, 1 e 1,75 batida leem 50% em `1/8`) **não andam**, a menos que essa seja a resolução da grade aberta ou a do padrão. Antes da fase 25 o app lia as sete resoluções, da `1/4` à `1/64`, e levava ao passo reto qualquer coisa que parecesse swing em alguma (fase 22, `938272c`). Um projeto de antes da fase 25 não tem dica: o swing de `1/16` dele só sai se a grade estava em `1/16` (ou se o padrão é de `1/16`). Aplique o swing depois do padrão, não antes, se quiser que ele fique. `(testado só por testes automáticos)`

## Padrões de fábrica

O botão `Padrões` (só na bateria) abre `Padrões de bateria`, uma lista de 9 itens com nome e descrição; tocar num item aplica na hora, sem confirmação.

O botão `Cancelar` (no rodapé, sempre à vista) fecha sem aplicar; tocar fora do diálogo também deve fechar, pelo padrão do Flutter `(não confirmado)`. O conteúdo da lista rola por inteiro, com o título `Padrões de bateria` fixo, então o último item (`Shuffle (tercinas)`) é alcançável em qualquer tamanho de tela (coberto por teste em 360 e em 1512 px de largura).

**O que aplicar faz:** apaga as notas das 12 peças da bateria no compasso do padrão (todos os padrões têm 1 compasso: as batidas do compasso do clipe no mapa de compassos, contadas a partir do começo do clipe) e escreve as do padrão. Notas de outras alturas e notas depois dessa faixa ficam. Notas que passariam do fim do clipe não são escritas. A resolução da grade e `Compassos` mudam para os do padrão (`Compassos` fica em 1, em qualquer compasso). O pincel continua como estava. O swing que o clipe tinha sai no mesmo passo (ver [Swing](#swing)): o padrão entra reto. Aviso: `Padrão <nome> aplicado.` (sem aspas; por exemplo `Padrão Rock aplicado.`). Um passo do `Ctrl+Z`.

**Em outro compasso.** O desenho dos padrões é escrito em 4 tempos. Num compasso de 3 tempos (3/4, 6/8) ele é cortado: ficam só os 3 primeiros tempos, o `Quatro no chão` leva bumbos nos tempos 1, 2 e 3 e palmas só no 2. Num compasso maior que 4 tempos (5/4, 6/4, 7/4) o desenho se repete para preencher o compasso: em 6/4 o bumbo do `Quatro no chão` cai nos seis tempos. Em 4/4 nada muda. `(testado só por testes automáticos)`

Nas linhas abaixo, cada caractere é um passo na resolução indicada: `.` vazio, `x` normal (0,80), `X` acento (1,00), `o` fantasma (0,30).

| Padrão (item da lista) | Resolução | Bumbo | Caixa / palmas / aro | Chimbal fechado | Chimbal aberto |
|---|---|---|---|---|---|
| `Quatro no chão` (`Bumbo em todo tempo, palmas no 2 e no 4.`) | `1/16` | `x...x...x...x...` | Palmas `....x.......x...` | `x.x.x.x.x.x.x.x.` | |
| `Rock` (`Bumbo no 1, no 3 e no passo 11 (o e do 3), caixa no 2 e no 4, chimbal em colcheias.`) | `1/16` | `x.......x.x.....` | Caixa `....x.......x...` | `x.x.x.x.x.x.x.x.` | |
| `Funk` (`Bumbo sincopado, caixa com notas fantasma, chimbal em semicolcheias.`) | `1/16` | `x..x...x..x.....` | Caixa `....x..o.o..x..o` | `XxxxXxxxXxxxXxxx` | |
| `Hip-hop` (`Boom bap: bumbo deslocado, caixa seca e chimbal aberto no fim.`) | `1/16` | `x.....x..x......` | Caixa `....x.......x...` | `x.x.x.x.x.x.x.x.` | `..............x.` |
| `Trap` (`Meio tempo, caixa no 3 e chimbal com rolos em 1/32.`) | `1/32` | `x.........x.x...` (16 caracteres, cada um vale 1/16) | Caixa `........x.......` (16 caracteres de 1/16, um só golpe: o tempo 3) | `x...x...x...x...x.x.x.x.oxoxxXXX` (32 caracteres de 1/32) | |
| `Reggaeton (dembow)` (`Bumbo em todo tempo e a caixa do dembow (4º e 7º passos de cada meio compasso).`) | `1/16` | `x...x...x...x...` | Caixa `...x..x....x..x.` | `x.x.x.x.x.x.x.x.` | |
| `Bossa nova` (`Clave no aro (3-2), bumbo sincopado e chimbal em colcheias.`) | `1/16` | `x..x....x..x....` | Aro `x..x..x...x..x..` | `x.x.x.x.x.x.x.x.` | |
| `House` (`Bumbo em todo tempo, palmas no 2 e no 4, chimbal aberto no contratempo.`) | `1/16` | `x...x...x...x...` | Palmas `....x.......x...` | `.o.o.o.o.o.o.o.o` (fantasmas) | `..x...x...x...x.` |
| `Shuffle (tercinas)` (`Balanço ternário: três passos por tempo.`) | `1/8 tercina` | `x.....x.....` | Caixa `...x.....x..` | `x.xx.xx.xx.x` | |

Cada linha do padrão vira notas na linha da peça de mesmo nome: `Bumbo` (nota 36), `Caixa` (38), `Palmas` (39), `Aro` (37), `Chimbal fechado` (42), `Chimbal aberto` (46).

Notas sobre o que cada padrão escreve de fato (lidas do código):

- No `Trap`, na grade de 32 passos o bumbo cai nos passos 1, 21 e 25 (no tempo 1, no "e" do tempo 3 e no tempo 4) e a caixa no passo 17 (tempo 3). O chimbal faz colcheias do passo 1 ao 17 (de 4 em 4), semicolcheias nos passos 19, 21 e 23 e, no último tempo, o rolo em 1/32: fantasmas nos passos 25 e 27, normais nos 26, 28 e 29 e três acentos nos 30, 31 e 32.
- No `Rock` o bumbo cai nos passos 1, 9 e 11 (`x.......x.x.....`): o 1, o 3 e o "e" do tempo 3. A descrição do item já diz isso desde a fase 19 (A); antes falava só do 1 e do 3.
- No `Reggaeton (dembow)` a caixa cai nos passos 4, 7, 12 e 15 (`...x..x....x..x.`), ou seja, o 4º e o 7º passos de cada meio compasso de 8 passos.
- No `House` os chimbais fechados são todos fantasmas nos passos 2, 4, 6... (o "e" e o "a" de cada tempo) e o aberto fica no "&" de cada tempo. Como o fechado abafa o aberto e o aberto abafa o fechado (6 ms de fade, ver [04b](04b-bateria.md#limites-e-pegadinhas)), o aberto soa só até o fantasma seguinte, um 16 depois.
- No `Hip-hop` o chimbal fechado e o aberto caem juntos no passo 15; na ordem em que entram, o aberto vence e corta o fechado.
- Cada padrão tem 1 compasso (de 4 tempos no 4/4; ver "Em outro compasso" acima). Para tocar um clipe de 4 compassos, use `Ações` > `Repetir até o fim do clipe`.

## Ações

O menu `Ações` abre com uma linha desativada, `Vale para: todas as linhas` (sem linha selecionada) ou `Vale para: <nome da linha>`, e itens. As ações trabalham só dentro do padrão (`Compassos`) e cada uma é um passo do `Ctrl+Z`.

| Item | O que faz | Detalhes |
|---|---|---|
| `Limpar linha` | Apaga os passos da linha selecionada | Desativado sem linha selecionada |
| `Limpar tudo` | Apaga os passos de todas as linhas da grade | Ignora a seleção. Não mexe em notas de fora das linhas nem nas depois do padrão |
| `Copiar padrão` | Guarda as notas do escopo (linha selecionada ou todas) | Aviso `Padrão copiado (N notas).` (`Padrão copiado (1 nota).` no singular). A cópia fica na memória do app: vale entre clipes e faixas, some ao recarregar |
| `Colar padrão` | Troca o escopo pelo conteúdo copiado | Desativado sem cópia. Cola nas mesmas posições em relação ao começo do clipe, só nas linhas do escopo. Se você copiou todas as linhas e cola com uma selecionada, só entra a dela |
| `Deslocar ←` | Move os passos acesos do escopo um passo para trás | Dá a volta: o primeiro vai para o último passo do padrão. O micro-tempo de uma nota fora da grade acompanha |
| `Deslocar →` | Move um passo para a frente | Idem, o último vai para o primeiro |
| `Inverter` | Acende o que está apagado e apaga o que está aceso | Os acesos novos usam a velocidade do pincel |
| `Aleatorizar…` | Refaz o escopo ao acaso | Abre `Aleatorizar` com o controle `Densidade: N%` (0 a 100, padrão 40) e `Cancelar` / `Aplicar`. Apaga o escopo e acende cada passo com essa chance, com velocidades sorteadas entre 0,55 e 1,00 (nunca fantasma) |
| `Preencher a cada N passos…` | Refaz o escopo com um passo aceso a cada N | Abre `Preencher a cada N passos…` com `A cada: N passos` (de 1 até metade dos passos do padrão, no mínimo 2; padrão 4, ou 2 se o padrão tem menos de 16 passos), `Cancelar` / `Aplicar`. Começa no primeiro passo, com a velocidade do pincel. Em `1/16`, `4` é quatro no chão; `2` são colcheias; `8` são os tempos 1 e 3 |
| `Repetir até o fim do clipe` | Repete o padrão até o fim do clipe | Copia as notas dos primeiros `Compassos` do clipe (todas as linhas e alturas, sem olhar a seleção) e **apaga tudo que havia depois do padrão**, no lugar das cópias. Só age quando há o que repetir: o padrão é menor que o clipe e tem ao menos uma nota. Aviso: `Padrão repetido até o fim do clipe (N vezes).` (`1 vez` no singular). Sem nada a repetir não muda nenhuma nota e não deixa passo vazio no `Ctrl+Z`; o aviso é `O padrão já ocupa o clipe inteiro.` se o padrão é do tamanho do clipe ou maior, ou `Não há notas no padrão para repetir.` se os primeiros `Compassos` estão sem notas (notas só depois do padrão ficam onde estão) |

Com uma linha selecionada, `Limpar linha`, `Copiar`, `Colar`, `Deslocar`, `Inverter`, `Aleatorizar…` e `Preencher…` valem só para ela; sem seleção, valem para todas as linhas. Como clicar num passo seleciona a linha dele, é fácil esquecer uma linha selecionada: confira a primeira linha do menu (`Vale para: …`) e toque de novo no nome da linha para voltar a `todas as linhas`.

## Sampler com zonas

- Uma linha por zona do sampler, na ordem das zonas. O nome depende do estado da **faixa toda** e, dentro dela, de cada zona (fase 22, `938272c`; tolerância da fase 25, `55cc53b`). Uma zona é **de fatia** quando é do áudio que mais zonas usam na faixa (o "dominante"; num empate vale o que aparece primeiro na lista), de uma nota só (`Notas de` igual a `até`) e em disparo (`Até o fim`, o modo de `Fatiar sample…`). A faixa conta como **fatiada** quando ao menos duas zonas são de fatia, elas são **mais da metade** das zonas da faixa e ao menos uma delas tem `Trecho` de início maior que 0 ou com fim definido, que é o que sai de `Fatiar sample…` (mesmo depois de aparar um ponto à mão). Numa faixa fatiada, as zonas de fatia levam `Fatia N · <nota>` (por exemplo `Fatia 1 · C1`, `Fatia 2 · C#1`) e uma zona que você editou (passou para `Sustenta`, trocou o áudio ou alargou `Notas de`/`até`) vira sozinha `Zona · <nota>`, sem tirar as outras de `Fatia N`: numa faixa de 5 fatias, editar a 2ª dá `Fatia 1`, `Zona`, `Fatia 3`, `Fatia 4`, `Fatia 5`. Quando as zonas de fatia não são mais da metade (2 zonas com uma editada, 4 com duas), a faixa deixa de ser fatiada e todas as linhas levam só `Zona · <nota>` (por exemplo `Zona · C3`), como num piano multi-sample (áudios diferentes), numa zona só, numa zona de áudio inteiro ou numa zona aparada à mão. Antes da fase 25 bastava uma zona fora do padrão para toda a faixa virar `Zona`; desde a fase 19 (A) uma zona de áudio inteiro deixou de ser chamada de `Fatia`; antes da fase 22 bastava a zona ter `Trecho` para levar `Fatia`.
- A nota da linha é a `Nota base` da zona, ou a mais próxima dentro da faixa `Notas de`–`até` se a base estiver fora dela. Zonas que resultam na mesma nota (camadas de velocidade, round-robin) dividem uma linha só (a primeira zona dá o nome). O número `N` de `Fatia N` é a **posição da zona na lista de zonas**, contando de 1, e não muda quando outra zona é editada (fase 25; antes contava as linhas de fatia, então editar uma renumerava as seguintes). Se duas zonas dividem a mesma nota, a segunda não tem linha e o número dela não aparece: a numeração tem um salto `(lido do código)`. Desde a fase 25 a mesma grade pode misturar `Fatia N` e `Zona` (a zona editada de uma faixa fatiada). `(testado só por testes automáticos)`
- Depois de [Fatiar sample](04c-sampler.md#fatiar-sample) (uma zona por fatia a partir de C1), a grade vira um sequenciador de fatias: cada linha toca um pedaço do loop.
- Não há o botão `Padrões` (os padrões são de bateria). Faixa de sampler com áudio único, sem zonas, não mostra a aba.
- As notas da grade têm no máximo 1/16 de batida. Zonas no modo `Até o fim` (as de `Fatiar sample…`) tocam inteiras assim mesmo; zonas em `Sustenta` soam só enquanto a nota dura, então uma nota de 1/16 corta um som longo. Para notas longas, edite no piano roll.
- A velocidade dos passos escolhe a camada de velocidade e o round-robin das zonas (04c): `Fantasma`, `Normal` e `Acento` são um jeito rápido de alternar camadas.

## Relação com o piano roll

- É a mesma nota. Um passo aceso é uma nota do clipe, de duração 1/16 (ou o passo, se menor); apagar o passo apaga a nota; a velocidade do passo é a da nota.
- Abrir o clipe no [piano roll](05-piano-roll.md) mostra a mesma batida nas linhas das peças; mover uma nota para um lugar fora do passo a deixa com contorno âmbar na aba `Passos`.
- Edições de duração, de altura (dentro do kit) e de micro-tempo se fazem no piano roll; a grade só liga, desliga e muda a velocidade.
- A ordem das notas no clipe é sempre a do início delas (a grade reordena depois de cada edição, sem trocar a ordem de notas empatadas).
- O `Ctrl+Z` é o mesmo: um gesto da grade, uma ação do menu, um padrão aplicado, um `Aplicar swing`, cada um é um passo.

## Passo a passo

### Programar um house de quatro no chão

1. Selecione a faixa `Bateria`. Dê dois cliques no vazio da raia, no compasso 1, para criar um clipe de um compasso. Abra a aba `Passos` (se a faixa ainda não tem clipe no cursor, o botão `Criar clipe aqui` da aba faz o mesmo).
2. Confira `Passo` em `1/16 · 16/comp.` e `Compassos` em `1` (o clipe vazio abre assim).
3. Na linha `Bumbo`, clique nos passos 1, 5, 9 e 13 (os tempos). Atalho: toque no nome `Bumbo`, `Ações` > `Preencher a cada N passos…`, `A cada` 4, `Aplicar`.
4. Na linha `Palmas`, clique nos passos 5 e 13 (tempos 2 e 4).
5. Na linha `Chimbal aberto`, clique nos passos 3, 7, 11 e 15 (o "e" de cada tempo).
6. Escolha o pincel `Fantasma` e, na linha `Chimbal fechado`, clique nos passos 2, 4, 6... até 16 (dá 8 fantasmas).
7. Ligue o loop (`L`) e aperte `Espaço`. O cursor branco corre pela grade. É o mesmo desenho do padrão `House`: para ter tudo pronto de uma vez, `Padrões` > `House`.

Para um clipe de 4 compassos, `Ações` > `Repetir até o fim do clipe`.

### Aplicar swing

1. Com o padrão de hip-hop (`Padrões` > `Hip-hop`) ou o seu, deixe `Passo` em `1/16`.
2. Arraste o controle ao lado de `Swing` até `Swing 40%`. As notas ainda não mexeram.
3. Toque em `Aplicar swing`. O aviso diz `Swing de 40% aplicado (N notas, em 1/16).`, com o número de notas que andaram. As semicolcheias fracas (passos 2, 4, 6...) ficam 0,1 batida mais tarde. No `Hip-hop` puro só o bumbo do passo 10 está num passo par (as colcheias do chimbal e a caixa estão nos ímpares), então o aviso diz `Swing de 40% aplicado (1 nota, em 1/16).` (no singular; antes da fase 22 saía `1 notas`); com fantasmas nos passos pares o número cresce (ver o [guia](../guias/batida-com-o-sequenciador-de-passos.md#cenário-2-hip-hop-com-swing-e-notas-fantasma)). Isso vale o clipe inteiro, mesmo que `Compassos` cubra só o começo.
4. Ouça; compare com `Tirar swing` e refaça, ou `Ctrl+Z` (que desfaz as notas e o valor do controle juntos). Para outro valor, arraste o controle e toque em `Aplicar swing` de novo: ele parte do swing que as notas têm, não do zero. Se você fechar e reabrir o projeto, o controle mostra o swing que ficou nas notas e `Tirar swing` continua ligado. `Tirar swing` devolve as notas exatamente às posições de antes do `Aplicar swing`, porque o clipe guardou a resolução e o valor aplicados (a dica, ver [Swing](#swing)); o aviso diz em que resolução (`Swing tirado (N notas, em 1/16).`).
5. O swing vale sempre para todas as linhas de uma vez (não há swing por linha). Para deixar só o chimbal balançando, aplique o swing e, no piano roll, leve à mão as notas das outras linhas de volta ao tempo reto (ou faça o padrão sem swing e mova só as notas do chimbal `(dedução)`).

### Rolos de chimbal com fantasmas

1. Escolha `Passo` `1/32 · 32/comp.`. Toque no nome `Chimbal fechado` para selecionar a linha (aparece a faixa `Velocidade`).
2. Pincel `Normal`: clique nos passos 1, 5, 9, 13, 17, 19, 21 e 23 (colcheias e semicolcheias).
3. Nos passos 25 a 32 faça o rolo: pincel `Fantasma` nos passos 25 e 27, `Normal` nos passos 26, 28 e 29, `Acento` nos passos 30, 31 e 32 (para acender vários com o mesmo pincel, arraste sobre eles).
4. Ajuste as alturas finas na faixa `Velocidade`: arraste sobre as barras dos passos do rolo para desenhar uma rampa de baixo para cima.
5. O caminho curto é `Padrões` > `Trap`, que traz esse rolo pronto: 16 notas de chimbal, com dois fantasmas e três acentos.

### Passar um padrão para o piano roll e editar

1. Monte o padrão na aba `Passos`.
2. Aperte `E` (ou toque na aba `Editor`). O piano roll abre no mesmo clipe, com as notas nas linhas das peças e a grade `1/16`.
3. Faça o que a grade não faz: alongue uma nota, arraste um chimbal um pouco para fora do tempo, use `Humanizar…` ou `Quantizar` ([05b](05b-ferramentas-midi.md)).
4. Volte para a aba `Passos`: as notas que saíram dos passos aparecem com contorno âmbar e continuam tocando onde estão. Editar outros passos não as move.

## Combina com

- [04b Bateria](04b-bateria.md): as 12 peças, os kits e o `Volume` de cada uma, que a grade usa como linhas.
- [04c Sampler](04c-sampler.md): `Fatiar sample…` cria as zonas que viram linhas.
- [05 Piano roll](05-piano-roll.md): as mesmas notas em outra visão, com duração, altura e micro-tempo.
- [05b Ferramentas MIDI](05b-ferramentas-midi.md): `Humanizar` e `Quantizar` sobre o padrão da grade (humanizar cria notas fora da grade; quantizar as devolve).
- [02 Transporte](02-transporte.md): loop, metrônomo e andamento para programar ouvindo.
- [06d Efeitos, compressor e sidechain](06d-efeitos-referencia.md#2-compressor): efeitos na faixa inteira da bateria.
- [Guia: batida com o sequenciador de passos](../guias/batida-com-o-sequenciador-de-passos.md): house, hip-hop com swing e trap com rolos, com valores.

## Limites e pegadinhas

- **Só bateria e sampler com zonas.** Sintetizador, FM e wavetable não têm a aba (nem linhas para notas melódicas).
- **A bateria mostra as 12 peças e mais nada.** Notas de outras alturas não aparecem na grade. Ordem das linhas: `Bumbo`, `Caixa`, `Palmas`, `Chimbal fechado`, `Chimbal aberto`, `Aro`, `Tom grave`, `Tom médio`, `Tom agudo`, `Prato de ataque`, `Prato de condução`, `Cowbell`.
- **Sem mudo por linha.** Só o alto-falante de ouvir. Para calar uma peça, zere o `Volume` dela no painel `Instrumento` ([04b](04b-bateria.md)).
- **Uma resolução para a grade toda.** Não há resolução por linha, nem passos com probabilidade, repetição (ratchet) ou micro-tempo por passo. Para isso, use resolução mais fina (`1/32`, `1/64`) ou o piano roll.
- **Não adivinha a resolução.** Um clipe em `1/32` aberto na grade padrão de `1/16` mostra notas fora da grade e as junta nos passos vizinhos. Escolha a resolução certa antes de clicar: clicar num passo que esconde notas apaga todas.
- **Um clipe de cada vez.** A grade edita o clipe da seleção; para o de outra faixa, selecione a faixa.
- **`Repetir até o fim do clipe` é destrutivo.** Apaga tudo que estava depois do padrão, de todas as alturas e linhas, incluindo notas de variação que você fez nos compassos seguintes. `Ctrl+Z` volta. Ele só roda quando o padrão tem notas e é menor que o clipe; senão avisa e não mexe em nada (nem deixa um passo vazio no `Ctrl+Z`).
- **Sem seleção, as ações valem para todas as linhas.** `Inverter`, `Aleatorizar…` e `Preencher a cada N passos…` sem linha selecionada refazem a bateria inteira.
- **Padrão maior que o clipe.** Se `Compassos` passa do fim do clipe, os passos de fora ficam escurecidos e o clique não os liga; mas `Inverter`, `Aleatorizar…` e `Preencher a cada N passos…` podem gravar notas lá `(lido do código, não confirmado no app)`. Elas não tocam (notas depois do fim do clipe não tocam); estique o clipe.
- **O arraste do mouse lê uma posição por vez.** Um arraste muito rápido pode pular passos no meio do caminho `(lido do código, não confirmado no app)`.
- **Estado da tela.** Resolução, `Compassos` fixado, pincel, linha selecionada e a cópia do `Copiar padrão` não vão para o projeto nem para a nuvem: cada aparelho começa em `1/16` e `Compassos` automático. O swing não entra nessa lista: é lido das notas do clipe (e da dica `swing_hint` gravada nele, que vai no projeto), então acompanha o `Ctrl+Z`, a reabertura do projeto e a edição no piano roll (ver [Swing](#swing)); só o valor arrastado no controle e ainda não aplicado é estado de tela.
- **A leitura das notas sozinha ainda precisa de nota num passo ímpar; a dica cobre o resto (fase 25).** Num clipe que só tem notas nos passos pares (por exemplo só contratempos), as notas sozinhas leem 0%, mas `Aplicar swing` grava a dica: o controle mostra o valor aplicado, `Tirar swing` fica ligado e devolve as notas às posições de antes (antes da fase 25 o controle voltava a `Swing 0%`, `Tirar swing` ficava apagado e só o `Ctrl+Z` desfazia). A dica só vale enquanto as notas batem com ela: se você mexer nas notas à mão de modo que uma fique reta num passo par, ou que nenhuma fique no atraso dito, ela é ignorada e o clipe volta à leitura só das notas (0% nesse caso). Clipes já atrasados por versões anteriores do app não têm dica. `(testado só por testes automáticos)`
- **Android.** A grade é a mesma; os gestos são os de toque descritos acima. `(testado só por testes automáticos; não foi visto no aparelho)`
- **Testado.** A lógica (conversões passo/nota, ações, leitura do swing, a dica do swing e `removeSwing`, a regra da faixa fatiada por maioria, os 9 padrões, padrões em compassos de 3, 6 e 7 tempos, nomes de zona) e a interface (cliques, arraste, toque longo, duplo toque, faixa de velocidade, presets, ações, swing com `Ctrl+Z` e reabertura, aplicar e tirar swing num clipe só com contratempos, `Passo` zerando o arrasto, `Padrões` sem mexer em nota que só parece swing, `Repetir` sem notas, `Padrões` em 3/4, diálogo de padrões em 360 e 1512 px, sampler, layout de 360 px) só têm testes automáticos; a aba não foi vista no Chrome nem no Android `(testado só por testes automáticos)`.

## Atalhos

| Tecla | Ação |
|---|---|
| `Ctrl+Z` / `Ctrl+Shift+Z` | Desfaz e refaz: um gesto, uma ação de menu, um padrão ou um swing por passo |
| `Espaço` | Toca e para; a grade acompanha com o cursor |
| `E`, `I`, `X`, `F` | Trocam para o editor, o instrumento, o mixer e os efeitos |
| `L`, `C` | Loop e metrônomo, úteis para programar ouvindo |

A aba `Passos` não tem teclas próprias: tudo é clique, arraste e menu.
