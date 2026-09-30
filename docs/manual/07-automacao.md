# Automação

> Desenhar, na linha do tempo, como um controle muda ao longo da música (volume, pan, nível de envio e qualquer parâmetro de instrumento ou de efeito); use para fades, varreduras de filtro, entradas e saídas de reverb.

## Onde fica

- **Botão `A`** no cabeçalho de cada faixa na linha do tempo (à direita de `S` e do botão de armar), e no cabeçalho do `Master`, no fim da lista de faixas. Tooltip: `Automação`, ou `Automação (N)` quando a faixa já tem N automações.
  - `A` cheio = há uma raia aberta; só o contorno na cor da automação = há automações, mas todas ocultas; apagado = nenhuma.
- **As raias** (sub-raias de 56 px) abrem logo abaixo da faixa, na mesma escala de tempo da linha do tempo; as do master abrem abaixo da linha `Master`.
- O mixer, o painel de instrumento e o de efeitos **não** editam a automação, só mostram o resultado: fader, pan e knobs andam sozinhos, em laranja, enquanto toca.
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

Parado, os controles mostram o valor fixo. Arrastar um controle automatizado muda o **valor fixo** (não se ouve enquanto a curva toca; volta a valer ao parar). O knob de nível de envio, no mixer, **não** anda com a automação: quem mostra o valor é a raia.

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

- [06 Mixer](06-mixer.md): fader, pan e envios que a automação move; solo e mudo continuam valendo por cima.
- [06c Painel de efeitos](06c-painel-de-efeitos.md) e [06d Referência dos efeitos](06d-efeitos-referencia.md): quais parâmetros existem e em que escala.
- [04 Painel de instrumento](04-painel-de-instrumento.md): parâmetros do instrumento automatizáveis (cortes, envelopes, LFO).
- [02b Timeline e clipes](02b-timeline-e-clipes.md): as raias abrem embaixo das faixas e seguem o zoom e a rolagem.
- [08 Exportação](08-exportacao.md): a automação entra na exportação e no congelar faixa.
- [Guia: mixagem e automação](../guias/mixagem-e-automacao.md): fade de volume e subida de filtro passo a passo.

## Limites e pegadinhas

- **Parado, vale o valor fixo.** Sem tocar, o motor não aplica curva: um parâmetro de instrumento ou efeito responde pelo valor fixo do knob, e o fader, o pan e os knobs mostram o fixo. Se você toca notas ao vivo com o transporte parado, o som usa o valor fixo, não o da curva no cursor. A leitura no cabeçalho da raia, esta sim, mostra o valor da curva no cursor mesmo parado.
- **Não existe gravar automação** (mexer num knob durante o play e gravar o movimento): a automação se desenha à mão, ponto a ponto.
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
| `Ctrl+Z` / `Ctrl+Shift+Z` | Desfaz / refaz (um passo por arraste) |
