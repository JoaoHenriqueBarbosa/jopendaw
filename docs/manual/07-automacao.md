# Automação

> Desenhar na linha do tempo, ou gravar mexendo nos controles com a música tocando, como um controle muda ao longo da música (volume, pan, nível de envio e qualquer parâmetro de instrumento ou de efeito); use para fades, varreduras de filtro, entradas e saídas de reverb.

![Botão A da faixa: o menu de alvos da automação (Volume, Pan, instrumento e cada efeito da cadeia).](../img/automacao-menu-alvo.jpg)

*Botão A da faixa: o menu de alvos da automação (Volume, Pan, instrumento e cada efeito da cadeia).*

![Raia de automação de volume sob a faixa Baixo: pontos e curvas entre eles, o seletor de modo L, o olho para ocultar e o X para fechar; ao alto, a faixa Andamento.](../img/automacao-volume.jpg)

*Raia de automação de volume sob a faixa Baixo: pontos e curvas entre eles, o seletor de modo L, o olho para ocultar e o X para fechar; ao alto, a faixa Andamento.*

## Onde fica

- **Botão `A`** no cabeçalho de cada faixa na linha do tempo (à direita de `S` e do botão de armar), e no cabeçalho do `Master`, no fim da lista de faixas. Tooltip: `Automação`, ou `Automação (N)` quando a faixa já tem N automações.
  - `A` cheio = há uma raia aberta; só o contorno na cor da automação = há automações, mas todas ocultas; apagado = nenhuma.
- **As raias** (sub-raias de 56 px) abrem logo abaixo da faixa, na mesma escala de tempo da linha do tempo; as do master abrem abaixo da linha `Master`.
- O mixer, o painel de instrumento e o de efeitos mostram o resultado: fader, pan e knobs andam sozinhos, em laranja, enquanto toca. Eles também **gravam** a automação quando o botão `Automação` da barra (ou o seletor da raia) está em `Escrever`, `Toque` ou `Trava`: ver [Gravar automação](#gravar-automação). Em `Ler` (o padrão) só mostram.
- **Botão `Automação`** na barra do transporte e **seletor `L`/`E`/`T`/`V`** no cabeçalho de cada raia: escolhem o modo de gravação.
- No celular vale o mesmo; os gestos de toque estão em "Controles".

## Controles

### Menu do botão `A`

Tocar em `A` abre um menu com os alvos automatizáveis daquela faixa. Escolher um alvo abre a raia dele (criando, se ainda não existe); escolher um que já está aberto **oculta** a raia (a automação continua valendo). Criar uma raia entra no desfazer; mostrar e ocultar, não.

| Item do menu (rótulo exato) | O que automatiza | Valores / padrão | Dica |
|---|---|---|---|
| `Volume` | O fader da faixa (ou do master). | De −∞ a +6 dB; escala do fader. | |
| `Pan` | O pan da faixa (no master, o balanço). | De −1 (esquerda) a +1 (direita); centro = 0. | |
| `Envio → Barramento 1` (um por envio existente) | O nível do envio da faixa para aquele barramento. | De −∞ a +6 dB, escala do fader. | Só aparece depois de criar o envio. Não existe no master. |
| Submenu com o nome do instrumento (ex.: `Sintetizador`, com ícone) | Cada parâmetro do instrumento da faixa, agrupado por seção (títulos em maiúsculas). | Faixa, unidade e escala da tabela do instrumento. | Só em faixa de instrumento. Barramento e faixa de áudio não têm este submenu. |
| Submenu `1. EQ`, `2. Reverb`... (posição do efeito na cadeia) | Cada parâmetro do efeito, agrupado por seção. | Faixa, unidade e escala da tabela do efeito (ver [06d](06d-efeitos-referencia.md)). | Dois efeitos do mesmo tipo ficam distinguíveis pelo número. |
| `Mostrar as ocultas (N)` | Reabre todas as raias ocultas. | | Só aparece com raias ocultas. |
| `Ocultar todas` | Fecha todas as raias abertas da faixa. | | A automação continua tocando. |
| `Nada para automatizar aqui` | Aviso quando o menu está vazio. | | |

Cada item de alvo mostra à esquerda um `✓` (raia aberta) ou um olho riscado (raia oculta), e à direita a contagem de pontos (`3 pontos`, `1 ponto`). O menu de um grupo mostra quantas raias já estão criadas nele.

O parâmetro `Sidechain` (compressor e gate) **não** aparece: é uma escolha de faixa, não um valor que anda.

### Cabeçalho da raia

| Controle (rótulo exato) | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| Nome do alvo (ex.: `Volume`, `Filtro · Corte`, `Envio → Barramento 1`) | Diz o que a raia move. Tocar seleciona a faixa. | Se o efeito ou o barramento foi apagado: `Alvo removido` e, embaixo, `não existe mais` (raia apagada, com hachura). | Remova a raia órfã com o `X`. |
| Valor embaixo do nome | O valor da curva **no cursor de reprodução**, ao vivo, na unidade do alvo (`−6.0 dB`, `C`, `E 30`, `1.41 kHz`). | Sem pontos, mostra o valor fixo do controle. | Vale também parado: mova o cursor e leia. |
| Olho riscado (tooltip `Ocultar (a automação continua valendo)`) | Fecha a raia sem apagar. | Não entra no desfazer. | Reabra pelo menu `A`. |
| `X` (tooltip `Remover a automação`) | Apaga a raia e os pontos; o controle volta ao valor fixo. | Entra no desfazer. | |

### Dentro da raia

O desenho é a curva; pontos são bolinhas; no meio de cada trecho há uma bolinha menor vazada, a **alça de curva**. A linha antes do primeiro ponto e depois do último fica parada no valor do ponto. Uma bolinha branca com contorno anda pela curva seguindo o cursor de reprodução. Linhas de grade: `0 dB`, `−12` e uma sem rótulo em −24 (volume e envios); `C` (pan); linhas em 25%, 50% e 75% da altura (parâmetros), ou uma linha `0` quando o parâmetro é linear e vai de negativo a positivo. Raia sem pontos mostra uma **linha tracejada** no valor fixo do controle e a dica `Clique para criar um ponto` (`Toque para criar um ponto` no celular).

| Gesto (mouse) | Efeito | Valores / padrão | Dica |
|---|---|---|---|
| Clique no vazio | Cria um ponto. A batida encaixa na grade; o valor é o da altura clicada. | A grade é a do botão da barra superior (tooltip `Grade de encaixe (Alt ao arrastar: livre)`: `Livre`, `Compasso`, `1/4`, `1/8`, `1/16`). `Alt` ao clicar ignora a grade. | Clicar a até 6 px da linha cria o ponto **em cima da linha** (a forma não muda). Nasce selecionado. |
| Clique num ponto | Seleciona. `Shift` alterna na seleção. | | |
| Arrastar um ponto | Move (batida e valor). Move junto todos os selecionados, sem passar do vizinho não selecionado nem antes da batida 0. | `Shift`: só o valor, em ajuste fino (um quarto). `Alt`: sem grade. | Um balão mostra `compasso.tempo.16avo · valor` (ex.: `5.1.1 · −6.0 dB`). |
| Duplo clique num ponto | Apaga o ponto. | Os dois cliques têm que cair no mesmo ponto. | Também: botão direito no ponto. |
| Arrastar no vazio | Seleção por retângulo. `Shift` soma à seleção atual. | | |
| Arrastar a alça de curva | Entorta o trecho entre este ponto e o próximo. | Curva de −100% a +100%; 50 px de arraste = 100%. `Shift`: um quarto. O balão diz `Curva +30%`, `Curva −30%` ou `Curva: reta`. | Tem alça só quando o trecho tem ao menos 18 px de largura e valores diferentes nas pontas. |
| `Alt` + arrastar no trecho | O mesmo que arrastar a alça, sem precisar acertá-la. | | |
| Duplo clique na alça (ou botão direito nela) | Volta o trecho à reta. | | |
| Botão direito no ponto | Apaga o ponto. | | |
| Botão direito no vazio | Limpa a seleção. | | |
| `Delete` ou `Backspace` | Apaga os pontos selecionados. | | Vale para a última raia em que você clicou. |
| `Ctrl+A` (`Cmd+A` no Mac) | Seleciona todos os pontos da raia. | | |
| `Esc` | Limpa a seleção (e segue para fechar o painel de baixo, se houver). | | |

**No celular (toque):** tocar no vazio cria um ponto; tocar num ponto seleciona; arrastar **um ponto** ou uma alça move; toque longo num ponto apaga. Arrastar no vazio rola a linha do tempo (não faz seleção por retângulo). Os alvos de toque são maiores (16 px de raio contra 7 do mouse).

Cada arraste é **um passo só** no desfazer; criar e apagar pontos também entram.

### Curva entre pontos (`curve`)

Cada ponto guarda a curva **até o próximo ponto**, de −1 a 1 (na tela, −100% a +100%). A forma entre dois pontos é `t^(2^(3·curva))`, onde `t` vai de 0 a 1 ao longo do trecho:

| Curva | Expoente | Como soa |
|---|---|---|
| 0 (padrão) | 1 | Reta |
| +50% | cerca de 2,8 | Começa devagar e acelera no fim |
| +100% | 8 | Quase parada no começo, muda quase tudo no finzinho |
| −50% | cerca de 0,35 | Muda depressa no começo e assenta |
| −100% | 0,125 | Salta quase tudo no começo |

O arraste da alça sempre segue o mouse (puxar para cima levanta a curva naquele trecho), mas o sinal da curva depende do sentido do trecho: num trecho que sobe, a alça para cima é curva negativa; num que desce, positiva. Dois pontos na **mesma batida** formam um **degrau**: o valor salta de um para o outro. Um ponto arrastado sobre a batida do vizinho vira degrau.

### Escala: por que o desenho não é uma reta em ganho nem em Hz

A curva entre dois pontos é calculada na **escala do controle**, não no valor bruto, para que "reta na tela" soe reta:

| Alvo | Escala do desenho | Efeito |
|---|---|---|
| `Volume` e `Envio →` | A curva do fader (ganho = 2 × posição³): 0 dB fica a ~79% da altura, +6 dB no topo, −∞ no fundo | Uma rampa reta soa como um fade parelho |
| `Pan` | Reta em −1 a +1 | |
| Parâmetros em Hz e segundos (`Corte`, `Frequência`, `Soltura`...) | Logarítmica, a mesma do knob | Uma rampa reta sobe o mesmo número de oitavas por compasso |
| Parâmetros lineares (`%`, `dB`...) | Reta no valor | |
| Parâmetros de opções e inteiros (`Tipo`, `Onda`, `Vozes`...) | Reta, com o valor arredondado a cada instante | O parâmetro anda em degraus |

Exemplos com números. **Fade de 0 dB a −∞ em 8 batidas**, reta na tela:

| Ponto do trecho | Ganho pela escala do fader (o desenho do app) | Se fosse reta no ganho linear |
|---|---|---|
| 25% | −7,5 dB | −2,5 dB |
| 50% | −18 dB | −6 dB |
| 75% | −36 dB | −12 dB |

Em ganho linear quase nada acontece no início e "despenca" no fim. **Varredura de `Corte` de 250 Hz a 8 kHz**: no meio do caminho, o filtro está em 1,4 kHz (média geométrica), meio caminho em oitavas; numa reta em Hz estaria em 4,1 kHz, e a maior parte da abertura já teria passado na primeira metade.

### Como isso vai ao motor

- O motor guarda os pontos em batidas absolutas e, **tocando**, avalia as raias a cada 32 quadros (0,7 ms a 48 kHz) e aplica: volume, pan, parâmetro de instrumento, parâmetro de efeito, nível de envio. Cada valor é limitado à faixa do parâmetro.
- Nos alvos com escala (volume, envios, e parâmetros em Hz, s etc.) o app quebra cada trecho em pequenos segmentos retos, um a cada 1/8 de batida (no mínimo 4 e no máximo 64 por trecho), porque o motor só interpola em reta. Nos trechos mais longos que 8 batidas os degraus ficam um pouco mais espaçados que 1/8 de batida.
- O valor **fixo** que você deixou no fader ou no knob fica guardado; a automação passa por cima dele sem apagá-lo. Parado, ou com a raia removida, vale o fixo.

### Knobs seguindo a automação

Enquanto **toca**, todo controle com automação passa a mostrar o valor da curva, na cor **laranja**:

| Controle | Onde |
|---|---|
| Fader e leitura em dB (a leitura fica laranja) | Mixer; minifader do cabeçalho da faixa e do master |
| Knob de pan | Mixer |
| Knobs de parâmetro | Painel de instrumento e painel de efeitos |

Parado, os controles mostram o valor fixo. Em `Ler`, arrastar um controle automatizado muda o **valor fixo** (não se ouve enquanto a curva toca; volta a valer ao parar); nos outros modos, o gesto grava. O knob de nível de envio, no mixer, **não** anda com a automação: quem mostra o valor é a raia.

## Gravar automação

Em vez de desenhar os pontos, você pode **tocar a música e mexer no controle**: o app grava o movimento como pontos de automação. Serve para fades, varreduras de filtro e ajustes de nível feitos "de ouvido". Só grava com o transporte **tocando**, e não junto com a gravação de áudio ou MIDI.

![O menu do botão Automação da barra: Ler, Escrever, Toque e Trava, cada um com a frase que resume o que faz. O seletor L da raia Volume (à esquerda do olho) mostra o modo daquela raia.](../img/automacao-modos.jpg)

*O menu do botão Automação da barra: Ler, Escrever, Toque e Trava, cada um com a frase que resume o que faz. O seletor L da raia Volume (à esquerda do olho) mostra o modo daquela raia.*

### Onde fica

- **Botão `Automação` na barra do transporte**, entre a `Grade de encaixe` e o `Afastar` (ver [02 Transporte, Botão Automação](02-transporte.md#botão-automação)). Em `Ler` (o padrão) ele é só o ícone de gráfico, cinza-claro. Em `Escrever`, `Toque` ou `Trava` ele fica **vermelho**, com o nome do modo ao lado (só a inicial `E`, `T` ou `V` no celular). O tooltip é `Automação: <modo>. <frase do modo>`.
- **Seletor `L`/`E`/`T`/`V` no cabeçalho de cada raia**, à esquerda do olho riscado (ver [Seletor da raia](#seletor-da-raia)). Vale só para aquela raia e sobrepõe a barra.
- O modo da barra vale para todas as raias sem modo próprio, inclusive controles que ainda não têm raia (a raia é criada na hora).

### Os quatro modos

Menu do botão (cada item tem o nome e uma frase em letra pequena):

| Modo (rótulo exato) | Frase do menu | O que faz na prática |
|---|---|---|
| `Ler` (padrão) | `Só toca a automação; mexer no controle não grava.` | Nada grava. Mexer num controle automatizado muda só o valor fixo; a curva continua mandando enquanto toca. |
| `Escrever` | `Grava o tempo todo enquanto toca, sobrescrevendo o que já havia.` | Grava sem parar e por cima da curva antiga, mesmo com a mão fora do controle (nesse caso, o último valor que ele teve). **Pelo botão da barra** começa na primeira vez em que você mexe no controle e vai até parar o transporte. **Pelo seletor `E` da raia** começa no instante em que você aperta play, com o valor fixo do controle, e grava até parar. |
| `Toque` | `Grava só enquanto você segura o controle; ao soltar, volta ao valor automatizado.` | Grava só enquanto o controle está seguro. Ao soltar, o valor volta ao que a automação tinha ali, numa rampa curta de **1/4 de batida**. Se não havia automação, volta ao valor fixo que o controle tinha antes da sua primeira mexida. Em parâmetros de opções e inteiros a volta é um degrau, sem rampa. |
| `Trava` | `Grava enquanto você segura o controle e mantém o último valor até parar.` | Grava enquanto você segura e, ao soltar, **mantém o último valor** (continua gravando-o) até o transporte parar. |

O `Escrever` pelo seletor da raia só começa sozinho **no play**, e só em raias que já existem (mesmo vazias). Se você troca a raia para `E` com a música já tocando, ela passa a gravar no primeiro movimento do controle. `(lido do código)`

"Soltar" é: fim do arraste; o último dedo ou botão do mouse levantado; ou, na roda do mouse, 0,5 s sem girar.

O que acontece no fim da passada (quando o transporte para) em `Escrever` e `Trava`: se a curva antiga tem pontos **depois** do ponto onde você parou, o valor dá um **degrau de volta** à curva antiga; se não tem, a raia fica no último valor gravado até o fim da música. No `Toque` o retorno já aconteceu ao soltar.

Trocar de modo, na barra ou no seletor de uma raia, com a música tocando, fecha na hora o que estava gravando (a passada entra no desfazer) e o modo novo vale dali em diante.

### O que grava

| Controle | Alvo da raia | Grava? |
|---|---|---|
| Fader do canal no mixer, e sua roda | `Volume` da faixa | Sim |
| Fader do canal `Master` no mixer | `Volume` do master | Sim |
| Knob de pan do canal (e do `Master`, que é balanço) | `Pan` | Sim |
| Knob de envio de um barramento (só se o envio já existe) | `Envio → nome do barramento` | Sim. Criar o envio, tocando no knob vazio, não grava |
| Mini fader do cabeçalho da faixa na linha do tempo | `Volume` da faixa | Sim (corrigido na versão de 30/09/2026: antes o deslizador do cabeçalho não gravava) |
| Mini fader do cabeçalho do `Master` | `Volume` do master | **Não** grava em nenhum modo (use o fader do `Master` no mixer) |
| Knobs do painel de instrumento (`I`) | `Instrumento · parâmetro` | Sim |
| Knobs do painel de efeitos (`F`) | `Efeito · parâmetro` | Sim, menos a faixa-chave do `Sidechain` |
| `Sidechain` (compressor e gate) | | Não: mostra o aviso `Este controle não tem automação.` ao lado do botão `Automação` |
| `M` e `S` (mudo e solo) | | Não são automatizáveis |
| Rodas de bend e modulação, pedal, notas tocadas | | Não: isso é expressão MIDI, que se grava no clipe ([03c Gravação](03c-gravacao.md)) |

Um parâmetro de opções ou inteiro (`Tipo`, `Onda`, `Vozes`) grava **degraus**: só as trocas, cada uma como dois pontos na mesma batida. `(testado só por testes automáticos)`

Durante o trecho gravado o controle mostra o que a sua mão pôs (não a curva), e a raia dele sai do som: vale o gesto. Os pontos **aparecem na raia quando o trecho acaba**: ao soltar (`Toque`) ou ao parar o transporte (`Escrever` e `Trava`); antes disso a raia não cresce na tela. Com o loop ligado, cada volta que termina já entra na raia.

### Densidade e alisamento dos pontos

- O app anota o valor do controle a cada atualização do cursor (cerca de uma por quadro da tela) enquanto o trecho está aberto, mesmo com a mão parada.
- No fim do trecho ele **afina** essas amostras: ficam só os pontos que a reta entre eles não consegue substituir com erro maior que **0,8% da faixa do controle**, medido na **escala do controle** (a do fader para volume e envio, logarítmica para Hz e segundos), a mesma em que a curva anda entre pontos. Valor parado vira 2 pontos; um movimento suave vira poucos. Um teste automático exige que uma senoide de 4 s (241 amostras) no pan vire no máximo 70 pontos, com erro abaixo de 0,02 numa faixa de −1 a 1 `(testado só por testes automáticos)`.
- Os pontos gravados são retas (`curve` 0), sem alças. Valores fora da faixa são presos a ela; volume nunca vira `NaN` nem passa de +6 dB.
- **Sobrescrever:** a região gravada (do primeiro ao último ponto do trecho) **substitui** os pontos antigos que estavam dentro dela; o que está fora fica. Nas duas pontas entram pontos com o valor que a curva antiga tinha ali, para a vizinhança não se deformar (um trecho **curvo** cortado ao meio é reamostrado em retas de cerca de 1/8 de batida, porque a curva de um trecho é medida do começo ao fim dele). Se o gesto começou noutro valor, há um degrau no começo.
- **Loop:** cada volta grava por cima da anterior; onde elas se cobrem, a **última vale**. No `Toque`, soltar numa volta e agarrar de novo na seguinte funciona; agarrado de uma volta à outra, o retorno ao valor antigo só acontece ao soltar de fato.
- Um cursor que volta atrás (por exemplo, você clica na régua tocando) é tratado como a virada do loop: a volta que acabou entra na raia e uma nova começa. `(lido do código)`

### Desfazer

A **passada inteira** (do play ao stop, com todos os controles gravados, inclusive raias criadas na hora e o valor fixo) entra no desfazer como **um passo só**, guardado quando o transporte para (ou quando você troca de modo tocando). `Ctrl+Z` volta tudo de uma vez; `Ctrl+Shift+Z` refaz. O ponto de desfazer que o arraste do controle normalmente guardaria é absorvido por esse passo.

### Seletor da raia

Botão pequeno (24 × 22 px) no cabeçalho de cada raia, com a letra do modo: `L` (`Ler`), `E` (`Escrever`), `T` (`Toque`) ou `V` (`Trava`, de "travar").

| Elemento | O que faz |
|---|---|
| Tooltip | `Modo de automação desta raia: Ler (o da barra)` quando a raia segue a barra; `Modo de automação desta raia: Toque` quando tem modo próprio |
| Menu | `Seguir a barra (Ler)` (o modo atual da barra entre parênteses), `Ler`, `Escrever`, `Toque`, `Trava` |
| Aparência | Letra e fundo vermelhos se o modo que vale grava; borda vermelha só quando o modo é próprio e grava; borda cinza-clara quando é próprio em `Ler`; borda quase apagada quando segue a barra |

O modo próprio **sobrepõe** o da barra: com a barra em `Ler` e uma raia em `T`, só aquele alvo grava; com a barra em `Toque` e uma raia em `L`, ela não grava. O modo próprio de `Escrever` é o único que grava desde o play, e por isso **apaga a curva antiga** de onde ele passar (grava o valor fixo do controle até você mexer).

### Limites da gravação

- Só com o transporte tocando. Parado, mexer no controle muda o valor fixo, como sempre.
- Durante a gravação de áudio ou MIDI (e na contagem) a automação não grava: aviso `A automação não grava junto com a gravação de áudio ou MIDI.` ao lado do botão, por 5 segundos.
- **O modo não é salvo no projeto**: nem o da barra nem os das raias. Reabrir o projeto volta tudo a `Ler`.
- Uma passada só guarda o que você mexeu; controles que você não tocou não mudam.
- **O valor fixo acompanha a sua mão.** O valor que o fader ou o knob mostra parado é o último que você pôs (é o valor fixo do documento), não a curva gravada; ao tocar, ele volta a seguir a curva. Mesmo depois de um `Toque`, que devolve a *curva* ao valor antigo, o valor fixo parado fica onde a sua mão largou. `(lido do código)`
- Ocultar a raia (olho riscado) não desliga o modo próprio dela: um `E` numa raia oculta continua gravando desde o play. `(lido do código)`

## Passo a passo

**Abrir a raia de volume de uma faixa**
1. Na linha do tempo, toque no `A` do cabeçalho da faixa.
2. Escolha `Volume`. A raia abre embaixo, com a linha tracejada no valor atual.
3. Clique na linha, no compasso onde o fade deve começar (cria um ponto em cima da linha).
4. Clique mais adiante, na altura desejada. Play: o fader do mixer segue a curva em laranja.

**Automatizar um parâmetro de efeito** (ex.: `Corte` do `Filtro`)
1. `A` da faixa, item `1. Filtro`, seção `FILTRO`, `Corte`.
2. Ponha ao menos dois pontos (início e fim da varredura).
3. Se quiser que a abertura aconteça mais perto do fim, puxe a alça do meio do trecho para baixo (curva positiva).
4. Toque: o knob `Corte` no painel `Efeitos` acompanha em laranja.

**Gravar um fade de volume com o fader (modo `Toque`)**
1. Na barra, toque em `Automação` (o ícone de gráfico) e escolha `Toque`. O botão fica vermelho, com o nome.
2. Com o mixer aberto (`X`), ponha o cursor uns compassos antes do fade e aperte Espaço.
3. No momento do fade, segure o fader da faixa e desça-o devagar até o fundo; solte.
4. Aperte Espaço para parar. Na linha do tempo, toque em `A` da faixa: o item `Volume` do menu já mostra a contagem de pontos. Abra a raia: os pontos do gesto estão lá (poucos, porque o movimento é afinado) e, depois deles, uma rampa curta de volta ao valor que a faixa tinha (se não havia automação, o valor fixo do fader). Se quiser que o fade **fique** no fundo, use `Trava` no passo 1.
5. `Ctrl+Z` desfaz a passada inteira de uma vez.

**Gravar uma varredura de filtro com o knob (modo `Trava`)**
1. Ponha um `Filtro` na cadeia da faixa e abra o painel de efeitos (`F`). No botão `Automação` da barra, escolha `Trava`.
2. Ponha o cursor antes da subida e aperte Espaço.
3. Segure o knob `Corte` e gire-o devagar até o valor final; solte. Ele mantém o último valor, gravando, até o transporte parar.
4. Pare. Abra `A` da faixa: a raia `Filtro · Corte` foi criada, aberta, com os pontos do gesto (a curva anda na escala logarítmica do knob). Se havia curva antiga depois do ponto onde você parou, o valor dá um degrau de volta a ela.

**Regravar só um trecho de uma automação que já existe**
1. Deixe o modo em `Toque`, para o resto da curva ficar intacto. Opcional: marque um loop no trecho (`L`) para tentar de novo; cada volta grava por cima e a última vale.
2. Toque, e no trecho segure o controle e mexa. Ao soltar, o valor volta à curva antiga em 1/4 de batida.
3. Pare. Só a região do seu gesto foi substituída; os pontos antes e depois continuam. Ouviu pior? `Ctrl+Z`.

**Gravar só uma raia (seletor da raia)**
1. No cabeçalho da raia, toque no botão pequeno `L` e escolha `Toque` (ou outro modo). A letra e a borda ficam vermelhas.
2. Só o alvo dessa raia grava; os outros controles seguem o modo da barra (em `Ler`, não gravam).

**Editar vários pontos de uma vez**
1. Arraste no vazio, formando um retângulo em volta dos pontos (`Shift` soma).
2. Arraste um dos selecionados: todos andam juntos, sem passar dos vizinhos.
3. `Delete` apaga os selecionados; `Ctrl+A` seleciona todos.

**Fazer um degrau (salto)**
1. Crie dois pontos em batidas vizinhas, um alto e um baixo.
2. Arraste um deles até a batida do outro (com a grade ligada, ele encaixa). Os dois na mesma batida formam o salto.

**Tirar a automação sem perder o desenho**
1. Toque no olho riscado do cabeçalho: a raia some, mas ainda vale. Para de valer só com `X`.

## Combina com

- [02 Transporte](02-transporte.md#botão-automação): o botão `Automação` da barra e o menu dos modos.
- [06 Mixer](06-mixer.md): fader, pan e envios que a automação move (e que também a gravam); solo e mudo continuam valendo por cima.
- [06c Painel de efeitos](06c-painel-de-efeitos.md) e [06d Referência dos efeitos](06d-efeitos-referencia.md): quais parâmetros existem e em que escala.
- [04 Painel de instrumento](04-painel-de-instrumento.md): parâmetros do instrumento automatizáveis (cortes, envelopes, LFO).
- [02b Timeline e clipes](02b-timeline-e-clipes.md): as raias abrem embaixo das faixas e seguem o zoom e a rolagem.
- [08 Exportação](08-exportacao.md): a automação entra na exportação e no congelar faixa.
- [Guia: mixagem e automação](../guias/mixagem-e-automacao.md): fade de volume e subida de filtro passo a passo, desenhados (passos 3 e 4) ou gravados com o mouse (passo 5).

## Limites e pegadinhas

- **Parado, vale o valor fixo.** Sem tocar, o motor não aplica curva: um parâmetro de instrumento ou efeito responde pelo valor fixo do knob, e o fader, o pan e os knobs mostram o fixo. Se você toca notas ao vivo com o transporte parado, o som usa o valor fixo, não o da curva no cursor. A leitura no cabeçalho da raia, esta sim, mostra o valor da curva no cursor mesmo parado.
- **Gravar automação** só com o transporte tocando e fora da gravação de áudio/MIDI (ver [Gravar automação](#gravar-automação)). O modo por raia e o da barra não vão para o projeto: voltam a `Ler` ao reabrir. O mini fader do cabeçalho do `Master` não grava.
- **Não há copiar e colar de pontos** entre raias ou trechos. `Duplicar a faixa` (menu da faixa) copia as raias junto.
- Uma raia por alvo: escolher o mesmo alvo de novo só reabre ou oculta a existente.
- **Apagar o efeito** apaga as raias dele; **remover um envio** ou o barramento apaga a raia do envio. Mover barramentos de posição pode desfazer envios e, com eles, as raias de envio (ver [06 Mixer](06-mixer.md)).
- Na raia de volume e de envio, o fundo é ganho 0 (`−∞ dB`) e o topo é +6 dB: não dá para automatizar além disso.
- Os controles de opções e inteiros andam em degraus: um `Tipo` de filtro automatizado troca de tipo a cada valor inteiro que a curva atravessa.
- Sem sidechain automatizável.
- Mostrar, ocultar e o estado aberto/fechado da raia **não** entram no desfazer.
- Depois de **congelar** uma faixa em áudio, o volume e o pan (com as automações deles) passam para a faixa nova; a automação de efeitos e instrumento vira som no arquivo.

## Atalhos

| Tecla / gesto | Ação (na raia de automação) |
|---|---|
| Clique | Cria um ponto |
| `Alt` ao clicar ou arrastar | Sem grade (livre); `Alt` + arrastar no trecho entorta a curva |
| `Shift` ao arrastar | Só o valor, fino; na alça, curva fina; ao clicar, alterna a seleção |
| Duplo clique no ponto / botão direito no ponto | Apaga o ponto |
| Duplo clique na alça | Curva volta à reta |
| `Delete` / `Backspace` | Apaga os pontos selecionados |
| `Ctrl+A` / `Cmd+A` | Seleciona todos os pontos da raia |
| `Esc` | Limpa a seleção |
| `Ctrl+Z` / `Ctrl+Shift+Z` | Desfaz / refaz (um passo por arraste; uma passada de gravação de automação inteira é um passo só) |
