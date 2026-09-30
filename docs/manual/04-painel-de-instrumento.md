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
| Seletor de presets, tooltip `Presets` (na bateria, `Kits de bateria`) | Abre o menu de presets agrupado por categoria, com um visto no preset que bate com os valores atuais | Largura fixa de 200 px; ver [Presets](#presets). No fim do menu, a seção `MEUS PRESETS` ([Meus presets](#meus-presets)) | O rótulo mostra o nome do preset ou `Inicial`, `Personalizado`, `Nome (editado)` |
| Seta direita, tooltip `Próximo (preset)` (na bateria, `Próximo (kit)`) | Aplica o próximo preset, dando a volta do último para o primeiro | Sem preset atual, parte do começo | A largura do seletor é fixa para o botão não andar a cada nome |
| Ícone de teclado, tooltip `Tocar com o teclado do computador (Ctrl+K)` (ligado: `Teclado tocando: atalhos suspensos (C L S X Z E F K J e Shift+H/L). A a P tocam a partir do C4, Z/X mudam a oitava, C/V a intensidade (80%). Ctrl+K desliga`, com a oitava e a intensidade de agora no lugar de `C4` e `80%`) | Liga e desliga o teclado do computador | Desligado ao abrir | É o mesmo interruptor do botão da barra superior e de `Ctrl+K`, e o tooltip é o **mesmo texto** nos dois (vem de uma função só, `keyboardTooltip`; antes o do painel era uma versão curta); no Mac o tooltip mostra `⌘+K` no lugar de `Ctrl+K`. Ligado, os atalhos de letra do estúdio ficam suspensos (ver [Limites e pegadinhas](#limites-e-pegadinhas)) |
| Ícone USB, tooltip `Tocar com um teclado MIDI` (conectado: `MIDI: nome do aparelho`) | Pede acesso ao MIDI do aparelho e liga a entrada | Fica colorido quando há aparelho conectado | O navegador pede permissão na primeira vez |
| Duas rodas verticais, à esquerda de `Oitava abaixo` (tooltips `Pitch bend (solta e volta ao centro)` e `Modulação (vibrato)`) | Rodas de expressão do teclado da tela; ver [Rodas de pitch bend e de modulação](#rodas-de-pitch-bend-e-de-modulação) | 38 px de altura no cabeçalho | Não aparecem na bateria |
| Setas `Oitava abaixo` e `Oitava acima`, com o teclado entre elas | Teclado da tela; só cabe no cabeçalho com o painel a partir de 1000 px de largura | 25 teclas | Abaixo de 1000 px o teclado desce para uma faixa própria, no pé do painel (as rodas descem junto) |

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

### Rodas de pitch bend e de modulação

Ao lado esquerdo do teclado da tela, tanto no cabeçalho (painel com 1000 px ou mais) quanto na faixa de baixo do painel (computador com painel mais estreito e celular), ficam duas rodas verticais de 24 px de largura, uma ao lado da outra. Elas não têm texto na tela: a identificação é o tooltip (no computador) e o rótulo de acessibilidade. **A bateria não tem as rodas** (não tem afinação nem pedal).

| Roda (tooltip) | O que faz | Valores | Como usar |
|---|---|---|---|
| `Pitch bend (solta e volta ao centro)` | Sobe ou desce a afinação de **todas** as notas que estão soando e das próximas, na faixa do painel | De -1 (embaixo) a +1 (em cima), com o zero no meio da roda (marcado por um traço). Vale o `Alcance do bend` do instrumento: padrão ±2 semitons. Passos de 1/8192 (os 14 bits do pitch bend do MIDI; na prática contínuo) | Clique ou toque na roda e arraste na vertical: o cursor da roda vai para onde está o dedo. **É de mola:** ao soltar, volta ao centro numa curva curta de 140 ms (não num pulo) |
| `Modulação (vibrato)` | Liga um vibrato (oscilação de afinação) de 5,5 Hz; quanto mais alta a roda, mais fundo | De 0 (embaixo) a 1 (em cima), passos de 1/127. Profundidade máxima: o knob `Vibrato da roda` (0 a 2 st, padrão ±1 semitom; o sampler também tem esse knob) | Arraste na vertical. **Não tem mola:** fica onde você a deixou, como nos teclados de verdade. Para desligar, leve-a até embaixo |

- Enquanto a roda está fora do repouso, a moldura e o cursor dela ficam na cor da faixa.
- Se o painel fecha com uma roda fora do zero, o app a devolve ao repouso: o vibrato não fica ligado "por trás" do painel fechado. O mesmo vale ao trocar de aba ou de faixa, já que o painel é recriado (não confirmado na tela).
- Com uma gravação em andamento, o que você faz nas rodas é gravado junto das notas se a faixa do painel está armada (ver [Gravação](03c-gravacao.md)). A gravação para com o bend e a roda de volta ao repouso no clipe: se a roda de modulação ou o bend estavam fora do zero ao parar, o clipe ganha um ponto de retorno ali.
- As rodas da tela têm a resolução única dos controles (bend em 14 bits, modulação em 1/127), a mesma do controlador MIDI e da faixa de controle do piano roll. O app lembra separadamente o que as rodas da tela e o que o controlador MIDI deixaram fora do repouso: os dois não se desfazem um ao outro.
- A bateria ignora as rodas e o pedal: além de o painel dela não ter as rodas, o app nem manda esses controles a uma faixa de bateria.
- O mesmo bend e a mesma modulação chegam de um teclado MIDI (mensagem de pitch bend e `CC 1`). O pedal de sustain só existe no MIDI (`CC 64`): o teclado da tela não tem pedal.

#### Alcance do bend e vibrato da roda, por instrumento

Os knobs ficam no cartão `GERAL`, junto dos outros controles gerais do instrumento (`Vozes`, `Sens. vel.`, `Volume`...). Como são knobs comuns, aparecem também no menu de alvos da automação (não confirmado).

| Instrumento | `Alcance do bend` | `Vibrato da roda` | Resposta às rodas |
|---|---|---|---|
| Sintetizador ([04a](04a-sintetizador.md)) | 0 a 24 st, inteiro, padrão 2 st | 0 a 2 st, padrão 1 st | Bend e vibrato |
| FM ([04d](04d-fm.md)) | 0 a 24 st, inteiro, padrão 2 st | 0 a 2 st, padrão 1 st | Bend e vibrato (os quatro operadores sobem juntos, então o timbre se mantém) (não confirmado ao ouvido) |
| Wavetable ([04e](04e-wavetable.md)) | 0 a 24 st, inteiro, padrão 2 st | 0 a 2 st, padrão 1 st | Bend e vibrato |
| Sampler ([04c](04c-sampler.md)) | 0 a 24 st, inteiro, padrão 2 st | 0 a 2 st, padrão 1 st | Bend e vibrato (com zonas e sem elas). Os dois knobs ficam no cartão `GERAL` do sampler (ver [04c](04c-sampler.md#geral)) |
| Bateria ([04b](04b-bateria.md)) | não tem | não tem | Ignora rodas e pedal |

`Vibrato da roda` é diferente do `Vibrato` do LFO (cartão `LFO`, 0 a 12 st): o do LFO é constante e independente das rodas; o da roda só existe enquanto a roda de modulação estiver levantada (ou houver pontos de modulação no clipe) e tem frequência fixa de 5,5 Hz. Os dois somam.

Fora o vibrato do LFO, o bend e o vibrato da roda mexem só na afinação: não abrem filtro nem mudam volume.

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

Se o parâmetro tem uma raia de automação com pontos (ver [07 Automação](07-automacao.md)), o knob passa a acompanhar a curva enquanto o projeto toca: o valor e o arco andam sozinhos e o knob fica na cor de automação (laranja, `#F08A5D`) em vez da cor da faixa. Parado, o knob mostra o valor fixo e volta à cor normal. Com o botão `Automação` da barra em `Ler` (o padrão), mexer num knob automatizado muda o valor fixo (o que vale quando a automação não manda, por exemplo com o projeto parado), não a curva; para mudar a curva, edite a raia. Em `Escrever`, `Toque` ou `Trava`, os knobs do painel **gravam automação** enquanto o projeto toca: o movimento vira pontos na raia do parâmetro (criada na hora, se não existe). Modos e passo a passo em [07 Automação, Gravar automação](07-automacao.md#gravar-automação).

## Presets

### O que é um preset

Um preset é um conjunto de valores de parâmetros. Cada preset de fábrica guarda só o que difere do padrão do instrumento (os seus, salvos por você, guardam todos os parâmetros do tipo). Ao escolher um, o painel aplica o padrão do tipo e, por cima, os valores do preset. Consequência prática: um preset soa igual não importa em que estado o instrumento estava antes, porque todo parâmetro que o preset não cita volta ao padrão. Escolher um preset sobrescreve o timbre inteiro, e vale um passo no desfazer (`Ctrl+Z` traz o timbre anterior de volta).

Exceção no sampler: a `Nota base`, a `Afinação` e o áudio escolhido pertencem ao áudio, não ao timbre, e nenhum preset os altera (ver [04c Sampler](04c-sampler.md)).

### O rótulo do seletor

O rótulo mostra em que pé o timbre está:

| Rótulo | Quando aparece |
|---|---|
| Nome do preset (ex.: `Pad quente`) | Todos os parâmetros batem com os de um preset da lista, de fábrica ou seu (com tolerância ínfima de arredondamento). O menu marca esse preset com um visto |
| `Nome (editado)` (ex.: `Pad quente (editado)`) | Você aplicou um preset nesta sessão do painel e depois mexeu em algum parâmetro |
| `Inicial` | Faixa recém-criada, com todos os parâmetros ainda no padrão do tipo e sem nenhum preset da lista igual a esse estado: é o caso de FM e wavetable. No sintetizador o mesmo estado bate com o preset chamado `Inicial` (categoria `BÁSICO`); na bateria (categoria `KITS`) e no sampler (categoria `SAMPLER`) também existe um preset `Inicial`, sem valores, que bate com o estado de fábrica |
| `Personalizado` | Os valores não batem com nenhum preset e nenhum foi aplicado nesta sessão do painel (por exemplo, ao reabrir o projeto com um timbre ajustado à mão) |

O nome `(editado)` é lembrado só enquanto o painel está aberto: fechar o painel ou trocar de aba parece descartar essa lembrança, e o rótulo passa a `Personalizado` (`(não confirmado)` em uso; vem da leitura do código, em que o painel é recriado a cada troca de aba). O que é salvo com o projeto são os valores dos parâmetros, não o nome do preset.

### Setas anterior e próximo

As setas percorrem a lista na ordem do menu (as categorias em sequência) e dão a volta nas pontas. Partindo de `Personalizado` sem preset lembrado, `Próximo` vai para o primeiro da lista e `Anterior` para o último. Depois do último de fábrica as setas seguem pelos seus (`MEUS PRESETS`, na ordem em que foram criados) e só então dão a volta. Como cada passo aplica o preset inteiro, dá para "folhear" timbres com o teclado da tela ou o teclado do computador tocando.

### Listas por tipo

| Tipo | Categorias do menu | Onde está a lista completa |
|---|---|---|
| Sintetizador | `BÁSICO`, `BAIXOS`, `LEADS`, `PADS`, `TECLAS`, `PLUCKS E ARPEJOS`, `EFEITOS` (22 presets) | [04a](04a-sintetizador.md#presets) |
| Bateria | `KITS` (7 kits) | [04b](04b-bateria.md#kits-presets) |
| Sampler | `SAMPLER` (5 envelopes) | [04c](04c-sampler.md#presets) |
| FM | Ver o capítulo | [04d](04d-fm.md) |
| Wavetable | Ver o capítulo | [04e](04e-wavetable.md) |

### Meus presets

Você pode guardar o timbre de um instrumento com um nome e chamá-lo depois em qualquer faixa do mesmo tipo, em qualquer projeto deste aparelho. Passo a passo em [Presets do usuário](../guias/presets-do-usuario.md).

#### Onde fica o menu

O seletor de presets do cabeçalho do painel (tooltip `Presets`; na bateria, `Kits de bateria`) abre o menu dos presets de fábrica e, **no fim dele**, depois de todas as categorias, a seção `MEUS PRESETS`. O menu do sintetizador tem 22 presets em 7 categorias e rola (altura máxima de 460 px): para chegar em `MEUS PRESETS` role até o fim do menu. A seção só lista os presets do **tipo** do instrumento (um preset de sintetizador não aparece no FM); um instrumento sem presets de fábrica (`Áudio`, `Barramento`) não tem o seletor, e por isso não tem presets do usuário. O menu é o mesmo no computador e no celular; só as setas anterior e próximo faltam no celular.

| Item do menu | O que faz |
|---|---|
| `MEUS PRESETS` (título cinza, sem clique) | Abre a seção. |
| `Nenhum ainda` (cinza) | Aparece no lugar da lista enquanto você não tem nenhum preset deste tipo. |
| Um preset seu (o nome, cortado com reticências se for longo) | Aplica na faixa, como os de fábrica. Leva o visto quando os valores da faixa batem com ele. |
| Ícone `…` no fim da linha (tooltip `Renomear, apagar ou exportar`) | Fecha o menu e abre uma janela com o nome do preset no título e três opções: `Renomear…`, `Exportar preset…` e `Apagar…` (em vermelho). |
| `Salvar como preset…` (ícone de marcador com `+`) | Pede um nome e guarda os parâmetros atuais do instrumento. |
| `Importar preset…` (ícone de arquivo) | Abre o seletor de arquivos e adiciona um preset `.jopreset`. |

#### Salvar

1. Ajuste o instrumento até gostar.
2. Abra o seletor de presets, role até o fim e escolha `Salvar como preset…`.
3. Na janela `Salvar como preset`, digite o nome no campo `Nome` e toque em `Salvar` (ou `Enter`). `Cancelar` fecha sem guardar.
4. O preset entra na lista da seção e, como os valores da faixa são os dele, já aparece marcado com o visto e o nome dele no seletor.

Regras do nome:

| Regra | Valor |
|---|---|
| Tamanho | Até 60 caracteres (o campo para de aceitar no 60). |
| Limpeza | O campo não aceita caracteres de controle nem separadores de linha ou de parágrafo (nem digitados nem colados). Ao guardar, esses caracteres e as marcas invisíveis (largura zero, direção do texto) viram espaço; espaços seguidos viram um só; espaços nas pontas somem. |
| Vazio | O botão `Salvar` fica desabilitado enquanto o nome, depois da limpeza, estiver vazio. |
| Repetido | Único **por tipo de instrumento**, sem diferenciar maiúsculas de minúsculas (`Baixo` e `baixo` são o mesmo nome). Nome já usado abre o diálogo `Substituir o preset?` com o texto `Já existe um preset chamado "Nome". Substituir pelos valores atuais?` e os botões `Cancelar` e `Substituir`. Substituir troca só os valores; o nome (com as maiúsculas de antes) e a data de criação do preset antigo ficam. |
| Quantidade | No máximo 300 presets por tipo. No 301º, a janela `Não foi possível salvar` diz `Limite de 300 presets para este tipo. Apague algum antes.` |

#### O que o preset guarda e o que não guarda

| Tipo | Guarda | Não guarda |
|---|---|---|
| Sintetizador, FM, Wavetable | Todos os parâmetros do painel (todos os cartões, `Volume`, `Vozes`, `Glide`, LFO etc.). | O nome do preset ligado à faixa (o projeto guarda só os valores), as notas e a automação. |
| Bateria | Os 49 valores: `Volume`, `Afinação`, `Decaimento` e `Timbre` de cada uma das 12 peças, mais o `Volume` geral. | As notas do piano roll e a automação. |
| Sampler | Só o timbre: `Modo`, os quatro knobs do envelope (`Ataque`, `Decaimento`, `Sustentação`, `Soltura`), `Sens. vel.`, `Volume`, `Alcance do bend` e `Vibrato da roda`. | O **áudio** escolhido, as **zonas** (mapa, notas, velocidades, loops, round-robin), a `Nota base` e a `Afinação`, que continuam como estão na faixa que recebe o preset. |

A automação (as curvas das raias) nunca entra no preset: ele guarda só o valor fixo de cada knob no momento de salvar. Para uma faixa com o knob automatizado, o valor guardado é o fixo, não o da curva (ver [07 Automação](07-automacao.md)).

#### Aplicar

Escolher um preset seu faz o mesmo que escolher um de fábrica: aplica o padrão do tipo e, por cima, os valores do preset (no sampler, mantém a `Nota base` e a `Afinação` da faixa), e vale um passo no desfazer. Como o preset seu guarda todos os parâmetros, não sobra nada "do estado anterior". As setas anterior e próximo (só no computador) andam pelos presets de fábrica e, depois deles, pelos seus, e dão a volta no fim.

O rótulo do seletor segue a tabela de [O rótulo do seletor](#o-rótulo-do-seletor), com estas particularidades:

| Situação | Rótulo |
|---|---|
| Os valores da faixa batem com um preset seu | O nome dele, sem `(editado)`, e o visto na linha dele. Se batem com um preset seu **e** com um de fábrica, vale o seu. Se dois presets seus têm valores idênticos, o primeiro criado. |
| Você aplicou um preset seu e depois mexeu em algum parâmetro | `Nome (editado)` (só até fechar o painel ou trocar de aba; depois volta a `Personalizado`, como nos de fábrica) `(não confirmado em uso)`. |
| Faixa recém-criada, sem nenhum parâmetro mexido | `Inicial`, a não ser que você tenha salvo um preset com todos os valores no padrão: aí aparece o nome dele. |
| Faixa com valores que não batem com nada e nenhum preset aplicado nesta sessão do painel | `Personalizado`. |

#### Renomear, exportar e apagar

Toque no `…` da linha do preset.

| Opção | O que faz |
|---|---|
| `Renomear…` | Janela `Renomear preset` com o nome atual preenchido; o botão é `Renomear`. Nome já usado por **outro** preset do tipo abre `Nome em uso` (`Já existe outro preset chamado "Nome".`) e nada muda; trocar só as maiúsculas do próprio nome é permitido. |
| `Exportar preset…` | Gera um arquivo `.jopreset` com esse preset. No navegador o arquivo é baixado direto (pasta de downloads); no Android abre o seletor de "salvar como" e cancelar volta sem mensagem. Se o sistema não sabe salvar arquivo, a janela `Não foi possível exportar` mostra o motivo. |
| `Apagar…` | Janela `Apagar o preset?` com `O preset "Nome" será apagado deste aparelho. Isso não pode ser desfeito.`, botões `Cancelar` e `Apagar` (vermelho). Faixas que já usam o timbre não mudam: o projeto guarda valores, não uma ligação com o preset. |

O nome do arquivo exportado é o nome do preset mais `.jopreset`; os caracteres `\ / : * ? " < > |` viram `_` e pontos no começo saem (um nome que fica vazio vira `preset.jopreset`).

Renomear, apagar e salvar presets **não entram no desfazer** do projeto (`Ctrl+Z` não traz de volta um preset apagado): eles são do aparelho, não do projeto.

#### Importar

`Importar preset…` abre o seletor de arquivos (título `Importar preset`; aceita `.jopreset` e `.json`) e adiciona o preset ao tipo que o arquivo declara.

| Situação | O que acontece |
|---|---|
| Arquivo bom, sem ressalvas | Entra na lista **sem nenhuma janela**: confira na seção `MEUS PRESETS`. |
| Nome já usado no tipo | Entra como `Nome (2)` (depois `(3)`…) e a janela `Preset "Nome (2)" importado` avisa `Já havia um preset chamado "Nome": este entrou como "Nome (2)".` |
| Parâmetros que o tipo não tem, valores que não são número ou são infinitos | Ignorados, com aviso na mesma janela (`N parâmetros desconhecidos ignorados.`, `N valores inválidos (não numérico ou infinito) ignorados.`). |
| Valores fora da faixa | Limitados à faixa do parâmetro, com aviso (`N valores fora da faixa foram limitados.`). |
| Parâmetros que o arquivo não cita | Voltam ao padrão do tipo. |
| Nome ausente, vazio ou com caracteres estranhos | Entra como `Preset importado`, ou com o nome limpo, com aviso. |
| Arquivo de outro tipo (por exemplo um preset de `reverb` importado pelo menu do sintetizador) | É guardado no tipo dele e só aparece no menu desse tipo; a janela avisa `O preset é de outro tipo (reverb): ele foi guardado, mas só aparece no menu desse tipo.` |
| Arquivo recusado | A janela `Não foi possível importar "arquivo"` mostra o motivo: `O arquivo é grande demais para ser um preset.` (mais de 256 KB), `O arquivo não é um preset do jopendaw (não é um JSON válido).`, `O arquivo não é um preset do jopendaw.`, `O arquivo tem uma versão de formato inválida.`, `O preset é de uma versão mais nova do jopendaw. Atualize o app para importá-lo.`, `Tipo de preset desconhecido ("família/tipo"). Ele pode ser de uma versão mais nova do jopendaw.`, `O preset não traz parâmetros.`, `O preset não tem nenhum valor utilizável para este tipo.` ou o limite de 300 por tipo. Nada é adicionado. |

O formato do arquivo está em [dev 10, Presets do usuário](../dev/10-app-flutter.md#presets-do-usuário-user_presetsdart-user_presets_uidart).

#### Onde os presets ficam guardados

Ficam **neste aparelho**, num único registro chamado `userpresets` no guardado local do app (o mesmo que guarda o projeto e os áudios):

| Onde | Como |
|---|---|
| Navegador (web) | No IndexedDB do site (banco `jopendaw`, chave `userpresets`), separado por endereço do site. Limpar os dados do site apaga os presets; outro navegador, outro perfil ou uma janela anônima começam sem nenhum. |
| Android | Num arquivo de texto (`userpresets.txt`) na pasta `jopendaw` dos documentos do app. Desinstalar o app ou limpar os dados dele apaga. |
| Outros sistemas de computador | Nada é guardado: os presets valem só até fechar o app (o app é feito para o navegador e o Android). |

Eles **não sincronizam com a conta**: não vão para a nuvem, não aparecem no outro aparelho e não vão dentro do `.jopendaw` do projeto (o projeto leva os valores dos knobs, não a lista de presets). Não são separados por conta: quem entrar com outra conta neste mesmo navegador vê os mesmos presets `(não confirmado em uso; vem da leitura do código, que não usa a conta na chave)`. Para levar a outro aparelho, exporte cada preset e importe no outro. Se a gravação no guardado falhar, os presets seguem na memória até fechar o app, mas o app **não mostra aviso** disso (o erro fica guardado internamente e nenhuma tela o lê): faça uma exportação dos presets importantes como cópia.

No Android, `Exportar preset…` e `Importar preset…` dependem do seletor de arquivos do sistema `(não confirmado no aparelho; testado só por testes automáticos com o seletor e o salvar simulados)`.

## Passo a passo

### Tocar e escolher um timbre

1. Selecione uma faixa de instrumento (ou crie uma em `Nova faixa`) e aperte `I`.
2. Toque no teclado da tela (ou ligue o teclado do computador com `Ctrl+K`).
3. Com uma nota sustentada, clique na seta `Próximo (preset)` algumas vezes, ou abra o seletor e escolha pelo nome.
4. Quando achar o mais próximo, ajuste os knobs; o rótulo passa a `Nome (editado)`.

### Guardar o timbre como preset seu

1. Deixe o instrumento no timbre que quer guardar.
2. Abra o seletor de presets, role o menu até o fim e escolha `Salvar como preset…`.
3. Digite o nome (até 60 caracteres) e toque em `Salvar`.
4. Em outra faixa do mesmo tipo, abra o seletor e escolha o nome na seção `MEUS PRESETS`. Receita completa: [Presets do usuário](../guias/presets-do-usuario.md).

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
- [03c Gravação](03c-gravacao.md): gravar notas ao vivo com o teclado da tela, o do computador ou o MIDI, junto de bend, modulação e pedal.
- [05 Piano roll, faixa de controle](05-piano-roll.md#faixa-de-controle): editar depois os pontos de bend, modulação e sustain gravados (ou desenhá-los).
- [Expressão MIDI na prática](../guias/expressao-midi-na-pratica.md): receitas com as rodas, o alcance do bend e o pedal.
- [06c Painel de efeitos](06c-painel-de-efeitos.md): os efeitos da faixa ficam na aba `Efeitos`, não neste painel; lá os efeitos também têm `MEUS PRESETS`.
- [Presets do usuário](../guias/presets-do-usuario.md): salvar o som que você ajustou, montar a cadeia de efeitos favorita e levar os presets a outro aparelho.
- [07 Automação](07-automacao.md): qualquer knob do painel pode ser automatizado; os knobs laranja mostram a curva tocando.
- [06 Mixer](06-mixer.md): volume, pan e envios da faixa; o `Volume` do instrumento é outro controle, dentro do instrumento.

## Limites e pegadinhas

- **Uma faixa por vez.** O painel só mostra a faixa selecionada; para comparar dois timbres, troque a seleção.
- **Preset apaga o que não é dele.** Aplicar um preset devolve ao padrão todo parâmetro que ele não cita. Se você ajustou um knob e quer guardá-lo, não troque de preset sem antes salvar o timbre com `Salvar como preset…` (ver [Meus presets](#meus-presets)) ou usar `Ctrl+Z` depois.
- **`MEUS PRESETS` fica no fim do menu.** No sintetizador, o menu tem cerca de 30 linhas (22 presets e 7 títulos de categoria) e rola: `Salvar como preset…` e `Importar preset…` ficam abaixo de tudo, então é preciso rolar o menu até o fim para achá-los.
- **Presets seus são do aparelho, não do projeto nem da conta.** Não sincronizam, não vão no `.jopendaw` e não aparecem em outro navegador; para levá-los, `Exportar preset…` e `Importar preset…` (ver [Onde os presets ficam guardados](#onde-os-presets-ficam-guardados)). O projeto guarda os valores dos knobs, então um projeto aberto em outro aparelho soa igual mesmo sem o preset lá.
- **Teclado do computador e MIDI tocam a faixa armada.** Eles tocam a faixa selecionada, a não ser que exista uma faixa de instrumento armada para gravar e a selecionada não seja uma delas; aí tocam a primeira armada. O teclado da tela sempre toca a faixa selecionada na hora do toque.
- **A oitava do teclado do computador é uma por tipo de faixa**, como a do teclado da tela: sintetizador, sampler, FM e wavetable abrem em C4; a bateria abre em C2 (nota 36), onde ficam as peças, então `A` a `P` já tocam a bateria sem mexer na oitava (ver [04b](04b-bateria.md)). A oitava vale para o tipo da faixa que está tocando (a selecionada ou a armada) e é lembrada só na memória do controlador do projeto aberto, não vai para o arquivo do projeto (não confirmado em uso); o botão do teclado na barra superior mostra a oitava atual (por exemplo `C4 · sem atalhos`, ou `C2 · sem atalhos` numa bateria).
- **Teclado do computador ligado suspende atalhos de letra.** O botão da barra superior mostra `C4 · sem atalhos` para avisar: `C`, `L`, `S`, `X`, `Z`, `E`, `F`, `K`, `J` e `Shift+H`/`Shift+L` viram nota, oitava ou intensidade até você desligar com `Ctrl+K`. Os atalhos com `Ctrl`/`Cmd` continuam valendo.
- **Duas leituras de força.** No teclado de piano da tela, quanto mais perto da frente da tecla (mais embaixo), mais forte; nos pads da bateria, é o contrário: quanto mais perto do topo, mais forte.
- **Estado do painel não é salvo.** A oitava do teclado da tela, o teclado escondido no celular e o `(editado)` do preset valem só enquanto o painel está aberto. Os valores dos parâmetros, sim, vão com o projeto e sincronizam.
- **Sem teclado físico nos knobs.** Só mouse, toque ou leitor de tela.
- **Vozes.** O sintetizador, o FM, o wavetable e o sampler têm no máximo 16 vozes; passando disso, a voz mais antiga sai em um fade curto (alguns milissegundos), sem estalo.
- **MIDI.** No navegador, o MIDI depende do suporte e da permissão do navegador. Se falhar, uma mensagem de erro aparece na tela (`Este navegador não dá acesso a MIDI.` ou o motivo).
- **Rodas fora do painel.** A roda de modulação não é salva com o projeto nem sobrevive ao painel: fechar o painel, trocar de aba ou de faixa a devolve a zero. O bend não guarda nada (é de mola). Para um vibrato que faça parte da música, desenhe os pontos na faixa `Modulação` do piano roll.
- **Teclado da tela some em painel baixo.** No computador não há botão para esconder o teclado; se ele sumiu, o painel está baixo demais: aumente a altura.

## Atalhos

| Tecla | Ação |
|---|---|
| `I` | Abre e fecha o painel `Instrumento` |
| `Esc` | Fecha o painel de baixo |
| `Ctrl+K` (`Cmd+K` no Mac) | Liga e desliga o teclado do computador |
| `A W S E D F T G Y H U J K O L P` (teclado do computador ligado) | Notas: `A` = dó, `W` = dó#, `S` = ré, `E` = ré#, `D` = mi, `F` = fá, `T` = fá#, `G` = sol, `Y` = sol#, `H` = lá, `U` = lá#, `J` = si, `K` = dó de cima, `O` = dó#, `L` = ré, `P` = ré# |
| `Z` / `X` (teclado ligado) | Oitava do teclado do computador abaixo / acima, só para o tipo da faixa que está tocando (faixa 0 a 8; padrão 4, e 2 na bateria) |
| `C` / `V` (teclado ligado) | Intensidade das notas menor / maior, em passos de 10% (10% a 100%, padrão 80%) |
| `Shift` ao arrastar ou rolar sobre um knob | Ajuste fino (5 vezes mais fino) |
| Duplo clique num knob | Valor padrão |
| Botão direito num knob | Digitar o valor |
| `Enter` no diálogo de valor | Aplica |

Com o teclado do computador ligado, as letras acima ganham dos atalhos gerais que usam as mesmas teclas (`X` mixer, `E` editor, `F` efeitos, `C` metrônomo, `Z` enquadrar): o atalho só vale com o teclado desligado, ou com `Ctrl`/`Cmd`/`Alt` apertado. Enquanto você digita num campo de texto, as teclas não tocam notas. Segurar uma tecla não reataca a nota nem repete o `Z`, `X`, `C` ou `V`.
