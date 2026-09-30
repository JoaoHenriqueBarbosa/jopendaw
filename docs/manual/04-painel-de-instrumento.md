# Painel de instrumento

> O painel onde você toca e ajusta o instrumento da faixa selecionada: presets, teclado da tela e os knobs de cada parâmetro. Vale para todos os instrumentos; os controles de cada um estão nos capítulos [04a Sintetizador](04a-sintetizador.md), [04b Bateria](04b-bateria.md), [04c Sampler](04c-sampler.md), [04d FM](04d-fm.md) e [04e Wavetable](04e-wavetable.md).

## Onde fica

O painel é uma das quatro abas do painel de baixo da tela do projeto (Mixer, Editor, Instrumento, Efeitos). Ele sempre mostra o instrumento da faixa selecionada; trocar de faixa troca o conteúdo. Formas de abrir:

| Como | Detalhe |
|---|---|
| Botão da barra superior, tooltip `Instrumento da faixa (I)` | O ícone acompanha o tipo da faixa selecionada (piano, grade, nota, etc.); numa faixa que não é de instrumento, o ícone é o de piano |
| Aba `Instrumento` do painel de baixo | Abaixo de 560 px de largura a aba mostra só o ícone (tooltip `Instrumento da faixa (I)`) |
| Tecla `I` | Abre e fecha o painel |
| Botão de tipo da faixa, na coluna de faixas do arranjo | Tooltip `Sintetizador: abrir o instrumento (I)` (o nome muda com o tipo); com o painel já aberto na faixa, o tooltip vira `Fechar o instrumento (I)` |
| Menu `Opções da faixa` (três pontinhos) > `Abrir o instrumento` | Só aparece em faixa de instrumento |
| Ícone do tipo da faixa no mixer | Tooltip `Sintetizador: abrir o instrumento` |

A barra do painel mostra, à direita das abas, o assunto: `Nome da faixa · Sintetizador`, ou `Nome · faixa de áudio, sem instrumento` / `Nome · barramento, sem instrumento`. Os botões `Maximizar o painel` / `Restaurar a altura` (só no computador) e `Fechar o painel (Esc)` ficam no fim da mesma barra.

Faixas de áudio e barramentos não têm instrumento. Nelas o painel mostra um aviso (`Faixa de áudio` ou `Barramento`), explica que os efeitos ficam na aba `Efeitos` e oferece um botão por instrumento (`Sintetizador`, `Bateria`, `Sampler`, `FM`, `Wavetable`) que cria uma faixa nova já selecionada. Sem nenhuma faixa no projeto, o aviso é `Nenhuma faixa no projeto`, com os mesmos botões.

Os instrumentos também nascem pelo botão `Nova faixa` da coluna de faixas do arranjo.

## Controles

### Cabeçalho (computador, painel com 800 px ou mais de largura)

| Controle (rótulo exato) | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| Barra colorida e ícone do tipo | Cor da faixa e tipo do instrumento | A cor é a da faixa; ela também pinta os knobs e as teclas acesas | Serve para ver a qual faixa o painel pertence |
| Nome da faixa e, embaixo, o tipo (`Sintetizador`, `Bateria`, `Sampler`, `FM`, `Wavetable`) | Identifica a faixa | Até 220 px, com reticências | Para renomear use o menu `Opções da faixa` |
| Seta esquerda, tooltip `Anterior (preset)` (na bateria, `Anterior (kit)`) | Aplica o preset anterior da lista, dando a volta do primeiro para o último | Sem preset atual, parte do fim da lista | Percorra timbres com o teclado da tela tocando |
| Seletor de presets, tooltip `Presets` (na bateria, `Kits de bateria`) | Abre o menu de presets agrupado por categoria, com um visto no preset que bate com os valores atuais | Largura fixa de 200 px; ver [Presets](#presets) | O rótulo mostra o nome do preset ou `Inicial`, `Personalizado`, `Nome (editado)` |
| Seta direita, tooltip `Próximo (preset)` (na bateria, `Próximo (kit)`) | Aplica o próximo preset, dando a volta do último para o primeiro | Sem preset atual, parte do começo | A largura do seletor é fixa para o botão não andar a cada nome |
| Ícone de teclado, tooltip `Tocar com o teclado do computador` (ligado: `Teclado do computador tocando (A a L; Z/X muda a oitava)`) | Liga e desliga o teclado do computador | Desligado ao abrir | É o mesmo interruptor do botão da barra superior e de `Ctrl+K` |
| Ícone USB, tooltip `Tocar com um teclado MIDI` (conectado: `MIDI: nome do aparelho`) | Pede acesso ao MIDI do aparelho e liga a entrada | Fica colorido quando há aparelho conectado | O navegador pede permissão na primeira vez |
| Setas `Oitava abaixo` e `Oitava acima`, com o teclado entre elas | Teclado da tela; só cabe no cabeçalho com o painel a partir de 1000 px de largura | 25 teclas | Abaixo de 1000 px o teclado desce para uma faixa própria, no pé do painel |

### Cabeçalho (celular, painel com menos de 800 px)

| Controle | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| Nome da faixa e tipo | Identifica a faixa | | O nome divide espaço com o preset; o preset tem prioridade |
| Seletor de presets (`Presets` ou `Kits de bateria`) | Igual ao do computador | Até 180 px ou 42% da largura | Não há setas anterior e próximo no celular |
| Ícone USB | Igual ao do computador | | |
| Ícone de piano, tooltip `Esconder o teclado` / `Mostrar o teclado` | Recolhe o teclado da tela para ganhar altura | Visível ao abrir | O estado não é salvo |

Não há ícone de teclado do computador no cabeçalho do celular; o botão equivalente fica na barra superior.

### Teclado da tela

| Controle | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| Teclas | Tocam a nota ao apertar e soltam ao soltar; arrastar o dedo ou o mouse desliza de tecla em tecla | 25 teclas: duas oitavas mais o dó de cima (15 brancas) | Vários dedos tocam várias notas |
| Altura do toque na tecla | Define a força (velocity) | Do alto da tecla (cerca de 35%) até o fundo (100%); nunca menos de 10% | Toque perto da frente da tecla para soar forte |
| Setas `Oitava abaixo` / `Oitava acima` | Deslocam o teclado de oitava em oitava | Primeira nota = dó da oitava escolhida; sintetizador, sampler, FM e wavetable abrem em C3 (nota 48 a 72), bateria em C2 (36 a 60); vai de C-1 até C7 | Cada tipo de instrumento lembra a própria oitava enquanto o painel está aberto |
| Nome nos dós | Rótulo `C3`, `C4`... para achar a oitava | Aparece se a tecla for larga o bastante | |
| Ponto colorido na tecla | Marca notas com função | Bateria: as 12 notas das peças; sampler: a nota base | Na bateria, passar o mouse mostra `Bumbo (C2)` |
| Tooltip de nota ao passar o mouse | Nome da nota (`D3`); na bateria, `Peça (nota)` | | |

O teclado fica no cabeçalho quando o painel tem 1000 px ou mais. Abaixo disso, ele vai para uma faixa embaixo dos controles, desde que o painel tenha altura para isso (cerca de 224 px no computador e 236 px no celular); se o painel for mais baixo, o teclado some para os controles caberem. No celular, o ícone de piano esconde ou mostra essa faixa. Aumente a altura do painel arrastando a alça ou com `Maximizar o painel`.

A nota tocada pela tela fica ligada à faixa em que você apertou a tecla: se a seleção mudar com o dedo ainda na tecla, a nota solta na faixa certa.

### Cartões de controles

Abaixo do cabeçalho vêm os controles do instrumento, em cartões com o título em maiúsculas (`OSCILADOR 1`, `FILTRO`...). No computador os cartões formam uma fileira única com rolagem horizontal (a roda vertical do mouse rola a fileira, exceto sobre um knob, que fica com a roda). No celular eles quebram em linhas, com rolagem vertical, em uma ou duas colunas.

Quase todo cartão tem um visor pequeno acima dos knobs: forma de onda, resposta do filtro, envelope, LFO, barras de mistura, ou um texto de estado (`Mono · legato`, `Poli · 8 vozes`, `Glide 80 ms`). O visor acompanha os knobs em tempo real. Um cartão inteiro fica apagado quando o que ele controla não faz efeito com os ajustes atuais (por exemplo, `ENVELOPE DO FILTRO` com `Envelope` do filtro em 0); o visor diz o motivo (`sem efeito: Envelope do filtro em 0`). Controles apagados continuam ajustáveis.

## Como os knobs funcionam

Cada parâmetro é um knob giratório: em cima o valor com a unidade (`2.40 kHz`, `+7 ct`, `250 ms`, `70%`), no meio o botão com o arco, embaixo o rótulo. O arco vai de 0 a 100% do curso; nos parâmetros que têm valores negativos (`Envelope` do filtro, `Semitons`, `Desafinação`) o arco parte do zero, para os dois lados. Uma marca discreta no trilho indica o valor padrão. Parâmetros de lista de opções (`Onda`, `Tipo`, `Algoritmo`) não são knobs: são uma caixa com a opção atual, e o clique abre o menu.

| Gesto | O que faz | Valores | Dica |
|---|---|---|---|
| Arrastar para cima ou para baixo | Sobe ou desce o valor | 200 px de arraste percorrem a faixa inteira | `Shift` durante o arraste dá ajuste fino: 1000 px para a faixa inteira (5 vezes mais fino) |
| Roda do mouse sobre o knob | Sobe (roda para cima) ou desce | Parâmetros contínuos: 1600 px de rolagem para a faixa inteira (`Shift`: 8000 px); parâmetros inteiros (Vozes, Uníssono, Semitons, Nota base): um passo por dente da roda | O trackpad acumula a rolagem até dar um passo; a roda só rola a fileira de cartões quando o mouse não está sobre um knob |
| Duplo clique (duplo toque no celular) | Volta ao valor padrão | O padrão aparece no tooltip: `Duplo clique: padrão (2.40 kHz)` | Se já está no padrão, nada acontece |
| Botão direito (toque longo no celular) | Abre um diálogo com o nome do parâmetro para digitar o valor | O texto de ajuda diz `De X a Y`; botões `Cancelar` e `Aplicar`; `Enter` também aplica | Veja abaixo o que o campo aceita |
| Tooltip (passar o mouse por cerca de 1 s) | Lembra os gestos: `arraste ou use a roda (Shift: ajuste fino)`, `Duplo clique: padrão (...)`, `botão direito: digitar o valor` | | Não aparece no toque |

O campo de digitação aceita o que o próprio painel mostra: `2.40 kHz`, `250 ms`, `70%`, `+7 st`, `×1.50`, `1.5 oit`. A vírgula vale como ponto. Sem unidade, um tempo maior que o máximo do parâmetro é lido como milissegundos (`300` num ataque de até 10 s vale 300 ms). No parâmetro `Nota base` do sampler dá para digitar o nome da nota (`C4`, `F#3`). Valor fora da faixa é limitado ao mínimo ou máximo. Se o texto não é entendido, o diálogo avisa `Não entendi. Use um número, com a unidade se quiser.`

Escalas: frequências e tempos usam curva logarítmica (o meio do curso é a média geométrica entre o mínimo e o máximo, então 20 Hz a 20 kHz e 0,5 ms a 10 s cabem no mesmo botão); porcentagens, semitons e cents são lineares; contagens (vozes, uníssono, semitons) são inteiras.

Desfazer: um arraste ou uma rajada da roda vale um passo só no `Ctrl+Z`. Clicar num knob sem mexer não cria passo. Cada escolha numa caixa de opções é um passo próprio. Duplo clique e valor digitado também são um passo cada.

Acessibilidade: cada knob se apresenta a leitores de tela como controle deslizante, com ações de aumentar e diminuir (um passo em parâmetros inteiros, 5% do curso nos demais). O knob não recebe foco de teclado, então não há como ajustá-lo só com o teclado físico.

### Knobs que seguem a automação (laranja)

Se o parâmetro tem uma raia de automação com pontos (ver [07 Automação](07-automacao.md)), o knob passa a acompanhar a curva enquanto o projeto toca: o valor e o arco andam sozinhos e o knob fica na cor de automação (laranja, `#F08A5D`) em vez da cor da faixa. Parado, o knob mostra o valor fixo e volta à cor normal. Mexer num knob automatizado muda o valor fixo (o que vale quando a automação não manda, por exemplo com o projeto parado), não a curva; para mudar a curva, edite a raia.

## Presets

### O que é um preset

Um preset é um conjunto de valores de parâmetros. Cada preset guarda só o que difere do padrão do instrumento. Ao escolher um, o painel aplica o padrão do tipo e, por cima, os valores do preset. Consequência prática: um preset soa igual não importa em que estado o instrumento estava antes, porque todo parâmetro que o preset não cita volta ao padrão. Escolher um preset sobrescreve o timbre inteiro, e vale um passo no desfazer (`Ctrl+Z` traz o timbre anterior de volta).

Exceção no sampler: a `Nota base`, a `Afinação` e o áudio escolhido pertencem ao áudio, não ao timbre, e nenhum preset os altera (ver [04c Sampler](04c-sampler.md)).

### O rótulo do seletor

O rótulo mostra em que pé o timbre está:

| Rótulo | Quando aparece |
|---|---|
| Nome do preset (ex.: `Pad quente`) | Todos os parâmetros batem com os de um preset da lista (com tolerância ínfima de arredondamento). O menu marca esse preset com um visto |
| `Nome (editado)` (ex.: `Pad quente (editado)`) | Você aplicou um preset nesta sessão do painel e depois mexeu em algum parâmetro |
| `Inicial` | Faixa recém-criada, com todos os parâmetros ainda no padrão do tipo e sem nenhum preset da lista igual a esse estado: é o caso de FM e wavetable. No sintetizador o mesmo estado bate com o preset chamado `Inicial` (categoria `BÁSICO`); na bateria e no sampler bate com o preset `Padrão` |
| `Personalizado` | Os valores não batem com nenhum preset e nenhum foi aplicado nesta sessão do painel (por exemplo, ao reabrir o projeto com um timbre ajustado à mão) |

O nome `(editado)` é lembrado só enquanto o painel está aberto: fechar o painel ou trocar de aba parece descartar essa lembrança, e o rótulo passa a `Personalizado` (`(não confirmado)` em uso; vem da leitura do código, em que o painel é recriado a cada troca de aba). O que é salvo com o projeto são os valores dos parâmetros, não o nome do preset.

### Setas anterior e próximo

As setas percorrem a lista na ordem do menu (as categorias em sequência) e dão a volta nas pontas. Partindo de `Personalizado` sem preset lembrado, `Próximo` vai para o primeiro da lista e `Anterior` para o último. Como cada passo aplica o preset inteiro, dá para "folhear" timbres com o teclado da tela ou o teclado do computador tocando.

### Listas por tipo

| Tipo | Categorias do menu | Onde está a lista completa |
|---|---|---|
| Sintetizador | `BÁSICO`, `BAIXOS`, `LEADS`, `PADS`, `TECLAS`, `PLUCKS E ARPEJOS`, `EFEITOS` (22 presets) | [04a](04a-sintetizador.md#presets) |
| Bateria | `KITS` (7 kits) | [04b](04b-bateria.md#kits-presets) |
| Sampler | `SAMPLER` (5 envelopes) | [04c](04c-sampler.md#presets) |
| FM | Ver o capítulo | [04d](04d-fm.md) |
| Wavetable | Ver o capítulo | [04e](04e-wavetable.md) |

Não existe, no painel, botão para salvar um timbre próprio como preset: a lista é fixa do app.

## Passo a passo

### Tocar e escolher um timbre

1. Selecione uma faixa de instrumento (ou crie uma em `Nova faixa`) e aperte `I`.
2. Toque no teclado da tela (ou ligue o teclado do computador com `Ctrl+K`).
3. Com uma nota sustentada, clique na seta `Próximo (preset)` algumas vezes, ou abra o seletor e escolha pelo nome.
4. Quando achar o mais próximo, ajuste os knobs; o rótulo passa a `Nome (editado)`.

### Ajustar um valor com precisão

1. Passe o mouse sobre o knob para ler o tooltip.
2. Arraste segurando `Shift` para mover devagar, ou clique com o botão direito.
3. Digite o valor com unidade (`1,8 kHz`, `350 ms`) e aperte `Enter`.
4. Para voltar ao padrão, dê duplo clique.

### Tocar com um teclado MIDI

1. Conecte o teclado ao aparelho.
2. Clique no ícone USB (tooltip `Tocar com um teclado MIDI`) e aceite a permissão do navegador.
3. O tooltip passa a listar o aparelho (`MIDI: nome`) e o ícone fica colorido.
4. As notas tocam a faixa selecionada (ou a faixa de instrumento armada; ver as pegadinhas).

### Ganhar altura no celular

1. Toque no ícone de piano do cabeçalho (`Esconder o teclado`).
2. Os cartões ganham a área do teclado; para voltar, toque de novo (`Mostrar o teclado`).

## Combina com

- [04a Sintetizador](04a-sintetizador.md), [04b Bateria](04b-bateria.md), [04c Sampler](04c-sampler.md), [04d FM](04d-fm.md), [04e Wavetable](04e-wavetable.md): os controles de cada instrumento.
- [05 Piano roll](05-piano-roll.md): as notas do clipe tocam o instrumento; a prévia das notas ao editar usa este mesmo instrumento.
- [03c Gravação](03c-gravacao.md): gravar notas ao vivo com o teclado da tela, o do computador ou o MIDI.
- [06c Painel de efeitos](06c-painel-de-efeitos.md): os efeitos da faixa ficam na aba `Efeitos`, não neste painel.
- [07 Automação](07-automacao.md): qualquer knob do painel pode ser automatizado; os knobs laranja mostram a curva tocando.
- [06 Mixer](06-mixer.md): volume, pan e envios da faixa; o `Volume` do instrumento é outro controle, dentro do instrumento.

## Limites e pegadinhas

- **Uma faixa por vez.** O painel só mostra a faixa selecionada; para comparar dois timbres, troque a seleção.
- **Preset apaga o que não é dele.** Aplicar um preset devolve ao padrão todo parâmetro que ele não cita. Se você ajustou um knob e quer guardá-lo, não troque de preset sem antes anotar (ou use `Ctrl+Z`).
- **Teclado do computador e MIDI tocam a faixa armada.** Eles tocam a faixa selecionada, a não ser que exista uma faixa de instrumento armada para gravar e a selecionada não seja uma delas; aí tocam a primeira armada. O teclado da tela sempre toca a faixa selecionada na hora do toque.
- **A oitava do teclado do computador é uma só para o projeto** (padrão C4, mostrada no botão da barra superior), diferente da oitava do teclado da tela, que é por tipo de instrumento. Numa bateria, o teclado do computador em C4 cai em notas sem peça: desça a oitava com `Z` até C2 (ver [04b](04b-bateria.md)).
- **Duas leituras de força.** No teclado de piano da tela, quanto mais perto da frente da tecla (mais embaixo), mais forte; nos pads da bateria, é o contrário: quanto mais perto do topo, mais forte.
- **Estado do painel não é salvo.** A oitava do teclado da tela, o teclado escondido no celular e o `(editado)` do preset valem só enquanto o painel está aberto. Os valores dos parâmetros, sim, vão com o projeto e sincronizam.
- **Sem teclado físico nos knobs.** Só mouse, toque ou leitor de tela.
- **Vozes.** O sintetizador, o FM, o wavetable e o sampler têm no máximo 16 vozes; passando disso, a voz mais antiga sai em um fade curto (alguns milissegundos), sem estalo.
- **MIDI.** No navegador, o MIDI depende do suporte e da permissão do navegador. Se falhar, uma mensagem de erro aparece na tela (`Este navegador não dá acesso a MIDI.` ou o motivo).
- **Teclado da tela some em painel baixo.** No computador não há botão para esconder o teclado; se ele sumiu, o painel está baixo demais: aumente a altura.

## Atalhos

| Tecla | Ação |
|---|---|
| `I` | Abre e fecha o painel `Instrumento` |
| `Esc` | Fecha o painel de baixo |
| `Ctrl+K` (`Cmd+K` no Mac) | Liga e desliga o teclado do computador |
| `A W S E D F T G Y H U J K O L P` (teclado do computador ligado) | Notas: `A` = dó, `W` = dó#, `S` = ré, `E` = ré#, `D` = mi, `F` = fá, `T` = fá#, `G` = sol, `Y` = sol#, `H` = lá, `U` = lá#, `J` = si, `K` = dó de cima, `O` = dó#, `L` = ré, `P` = ré# |
| `Z` / `X` (teclado ligado) | Oitava do teclado do computador abaixo / acima (faixa 0 a 8, padrão 4) |
| `C` / `V` (teclado ligado) | Intensidade das notas menor / maior, em passos de 10% (10% a 100%, padrão 80%) |
| `Shift` ao arrastar ou rolar sobre um knob | Ajuste fino (5 vezes mais fino) |
| Duplo clique num knob | Valor padrão |
| Botão direito num knob | Digitar o valor |
| `Enter` no diálogo de valor | Aplica |

Com o teclado do computador ligado, as letras acima ganham dos atalhos gerais que usam as mesmas teclas (`X` mixer, `E` editor, `F` efeitos, `C` metrônomo, `Z` enquadrar): o atalho só vale com o teclado desligado, ou com `Ctrl`/`Cmd`/`Alt` apertado. Enquanto você digita num campo de texto, as teclas não tocam notas. Segurar uma tecla não reataca a nota nem repete o `Z`, `X`, `C` ou `V`.
