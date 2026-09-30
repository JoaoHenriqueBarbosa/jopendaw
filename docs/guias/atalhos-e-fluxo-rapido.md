# Atalhos e fluxo rápido

> O jeito de trabalhar de quem não quer soltar o teclado: as teclas do estúdio combinadas em sequências (ensaiar, marcar, cortar, gravar, escrever notas, ajustar o som), com as regras que decidem quando uma tecla pega; cerca de 15 minutos para treinar as sequências e passar a usá-las sem olhar.

As tabelas de teclas estão em [02 Transporte](../manual/02-transporte.md), [02b Timeline e clipes](../manual/02b-timeline-e-clipes.md), [05 Piano roll](../manual/05-piano-roll.md) e [09 Configurações, atalhos e Android](../manual/09-configuracoes-atalhos-android.md); o que vem abaixo é a conferência delas com o código (`app/lib/screens/project_screen.dart`, `app/lib/daw/piano_roll_input.dart`, `app/lib/daw/controller.dart`) e a costura em sequências. A janela `Atalhos do teclado` (tecla `?`) lista as mesmas teclas em 8 grupos, inclusive o grupo `Suspensos enquanto o teclado do computador está ligado` (conferida com o código em `15670b7`).

## Ingredientes

| Recurso | Para quê aqui | Capítulo |
|---|---|---|
| Transporte: `Espaço`, `Enter`/`Home`, `R`, `L`, `C`, `Z`, `+`, `−` | Tocar, parar, gravar, loop, metrônomo, enquadrar, zoom | [02 Transporte](../manual/02-transporte.md) |
| Marcadores e seções: `M`, `Shift+M`, `[`, `]`, `Shift+L` | Marcar a música e ensaiar uma parte | [02b Timeline e clipes](../manual/02b-timeline-e-clipes.md) |
| Clipes: `S`, `Ctrl+D`, `Delete`, `Ctrl+I` | Cortar, repetir, apagar e importar | [02b Timeline e clipes](../manual/02b-timeline-e-clipes.md), [03 Áudio e clipes](../manual/03-audio-e-clipes.md) |
| Teclado do computador: `Ctrl+K`, `A W S E D F T G Y H U J K O L P`, `Z`/`X` (oitava por tipo de faixa; a bateria parte do `C2`), `C`/`V` | Tocar notas e gravá-las | [03c Gravação](../manual/03c-gravacao.md), [04 Painel de instrumento](../manual/04-painel-de-instrumento.md) |
| Editor de notas: `Ctrl+A`, `Ctrl+C/X/V/D`, `Q`, `K`, `J`, `Shift+H`, `Shift+L`, setas | Editar notas sem o mouse | [05 Piano roll](../manual/05-piano-roll.md), [05b Ferramentas MIDI](../manual/05b-ferramentas-midi.md) |
| Painéis: `X`, `E`, `I`, `F`, `Esc`, `?` | Abrir mixer, editor, instrumento, efeitos | [00 Visão geral](../manual/00-visao-geral.md) |
| Automação: `Delete`, `Ctrl+A`, `Esc` na raia | Apagar pontos | [07 Automação](../manual/07-automacao.md) |

Receitas que usam essas teclas: [Primeira batida do zero](primeira-batida-do-zero.md) (`Ctrl+A`, `Ctrl+D` e as setas) e [Melodia e harmonia com as ferramentas](melodia-e-harmonia-com-as-ferramentas.md).

## Passo a passo

### 0. Cinco regras que decidem se a tecla pega

O tratamento de teclas do estúdio tem camadas, nesta ordem: primeiro o teclado musical (se estiver ligado), depois o editor de notas, depois os atalhos gerais. Quase toda tecla que "não funciona" é uma das cinco regras abaixo.

1. **Foco.** As teclas valem com o estúdio em foco e **não** valem enquanto você digita num campo de texto (nome, `BPM`, valor de knob). Os botões da tela não pegam foco: `Espaço` toca mesmo depois de você clicar num botão.
2. **`Ctrl` ou `Cmd`.** No Windows e no Linux vale `Ctrl`; no Mac, `Cmd` (`⌘`). Os tooltips da barra (`Desfazer (⌘+Z)`), o menu do clipe e a janela `?` mostram `⌘` no Mac e no iOS e `Ctrl` nos outros sistemas. Nas tabelas abaixo, leia `Ctrl` como `Cmd` no Mac.
3. **Teclado do computador ligado (`Ctrl+K`).** As letras `A W S E D F T G Y H U J K O L P` viram notas e `Z`, `X`, `C`, `V` viram oitava e intensidade, passando à frente dos atalhos. O botão da barra avisa: `C4 · sem atalhos` (a oitava e o lembrete). Continuam valendo: `Espaço`, `Enter`, `Home`, `R`, `I`, `M`, `Shift+M`, `[`, `]`, `=`, `+`, `−`, `?`, `Esc`, `Delete`, `Backspace` e tudo com `Ctrl`/`Cmd`. Perdem o atalho (é exatamente o grupo `Suspensos enquanto o teclado do computador está ligado` da janela `?`): `S` (cortar), `E` (editor), `F` (efeitos), `L` (loop), `C` (metrônomo), `X` (mixer), `Z` e `Shift+Z` (enquadrar) e, no editor de notas, `K` (dividir), `J` (unir), `Shift+H` (humanizar) e `Shift+L` (legato, e o loop do clipe fora do editor). Com `Ctrl`, `Cmd` ou `Alt` apertados a letra deixa de ser nota. As teclas de nota são as **posições** físicas (a fileira do meio são as brancas, a de cima as pretas), então valem em qualquer layout.
4. **Editor ativo.** As teclas do editor (`Delete`, `Ctrl+D`, `Q`, setas...) só agem nas notas enquanto o editor foi o último lugar clicado. Pelo código ele já nasce ativo ao abrir, e um clique fora dele (no arranjo, na barra) devolve as teclas ao arranjo. Com o editor ativo, `Delete` nunca apaga o clipe: só notas. `(não confirmado em uso: o manual diz que só depois de um clique dentro do editor)`
5. **Gravando.** `Ctrl+Z`, `Ctrl+Y`, `Ctrl+Shift+Z` e `Ctrl+I` são engolidos (não fazem nada); `Ctrl+R` fica para o navegador. Cursor, loop, andamento, importar e exportar também ficam travados.

### 1. Marcar a música enquanto ela toca e ensaiar uma parte

Teclas: `Enter`, `Espaço`, `M`, `Shift+M`, `[`, `]`, `Shift+L`, `L`, `Z`.

1. `Enter`: para e leva o cursor ao começo (parado, sempre ao começo do projeto; com o loop ligado e a música tocando, ao início do loop; `Home` faz o mesmo).
2. `Espaço`: toca. No começo de cada parte, aperte `M`: nasce um marcador `Marcador N` na posição do cursor (se já existe um ali, só o seleciona). Para dar nome na hora, `Shift+M`: abre `Nome do marcador` (campo `Nome`, até 40 caracteres); digite `Refrão` e confirme com `Salvar`.
3. `Espaço` para parar. `[` e `]` levam o cursor ao marcador anterior e ao seguinte (sem marcador antes, `[` vai ao compasso 1).
4. Com o cursor num marcador, `Shift+L`: **loop da seção** (do marcador ao seguinte; a última seção vai até o fim do arranjo) e liga o loop. Só faz isso se **nenhum clipe estiver selecionado**: com um clipe selecionado, `Shift+L` faz o loop desse clipe.
5. `Espaço` e ensaie. `L` liga e desliga o loop; a região continua marcada. `Z` enquadra o projeto para ver tudo; `Shift+Z` enquadra o clipe selecionado.
6. `+` e `−` aproximam e afastam em passos de 1,25 vez; com o mouse, `Ctrl` mais a roda dá zoom no ponto do mouse e `Shift` mais a roda rola na horizontal.

Sequência para decorar: **`Enter`, `Espaço`, `M`, `M`, `M`, `Espaço`, `[`, `[`, `Shift+L`, `Espaço`**.

### 2. Cortar, repetir e apagar clipes

Teclas: `S`, `Ctrl+D`, `Delete` ou `Backspace`, `Ctrl+Z`, `Ctrl+Shift+Z` ou `Ctrl+Y`, `Ctrl+I`.

O arranjo **não tem tecla para selecionar clipe ou faixa**: clicar num clipe (só no mouse) o seleciona; o resto é teclado.

1. Clique no clipe que vai cortar. `]` até o marcador do começo do trecho (o cursor vai para lá) e `S`: o clipe se parte em dois no cursor (só se o cursor estiver estritamente dentro dele). Com um clipe selecionado, `S` corta só ele; sem nenhum selecionado, corta **todos** os clipes que o cursor cruza na faixa selecionada (áudio e notas).
2. `]` até o marcador do fim do trecho e `S` de novo. O clipe fica em três pedaços independentes.
3. Clique no pedaço do meio e `Ctrl+D`: a cópia cai logo depois dele e fica selecionada; o que ela cobrir dos vizinhos é aparado. Aperte `Ctrl+D` de novo para encadear cópias. Errou? `Ctrl+Z` (até 200 passos); `Ctrl+Shift+Z` ou `Ctrl+Y` refazem.
4. Selecione um pedaço de sobra e `Delete` (ou `Backspace`, que é a tecla `Delete` de muitos Macs): o clipe some e o vão fica.
5. `Ctrl+I` abre o seletor de arquivos de áudio: o arquivo cai no cursor, com encaixe na grade.

Sequência para decorar: **clique, `]`, `S`, `]`, `S`, clique, `Ctrl+D`, `Ctrl+Z`**.

### 3. Tocar e gravar sem o mouse

Teclas: `Ctrl+K`, `A W S E D F T G Y H U J K O L P`, `Z`, `X`, `C`, `V`, `R`, `Espaço`.

1. Selecione (ou arme) uma faixa de instrumento (mouse). Arme com o ponto `Armar para gravar` se quiser gravar as notas.
2. `Ctrl+K`: liga o teclado; o botão da barra passa a mostrar `C4 · sem atalhos` (a tecla `A` é o dó central, nota 60). O tooltip lista os atalhos suspensos e a intensidade atual.
3. Toque: `A` dó, `W` dó#, `S` ré, `E` ré#, `D` mi, `F` fá, `T` fá#, `G` sol, `Y` sol#, `H` lá, `U` lá#, `J` si, `K` dó de cima, `O` dó#, `L` ré, `P` ré#. `Z` e `X` descem e sobem a oitava (de 0 a 8; o botão mostra `C3 · sem atalhos`, `C5 · sem atalhos`...). A oitava é **uma por tipo de faixa** (áudio, sintetizador, bateria, sampler, FM, wavetable): mexer nela na bateria não muda a do sintetizador, e ao trocar de faixa o botão mostra a do tipo novo. Vale a faixa que toca: a selecionada, ou a primeira faixa de instrumento armada. `C` e `V` diminuem e aumentam a intensidade em passos de 10% (de 10% a 100%, padrão 80%; o tooltip do botão mostra o valor). Segurar a tecla não reataca a nota nem repete `Z`, `X`, `C` ou `V`.
4. `R` grava, mesmo com o teclado ligado (não é tecla de nota): com o transporte parado, um compasso de contagem e a gravação começa. `R`, `Espaço` ou `Enter` param.
5. Para bateria: a oitava já parte do `C2` (o botão mostra `C2 · sem atalhos`), onde ficam as peças, sem apertar `Z`: `A` `Bumbo`, `W` `Aro`, `S` `Caixa`, `E` `Palmas`, `F` `Tom grave`, `T` `Chimbal fechado`, `H` `Tom médio`, `U` `Chimbal aberto`, `K` `Tom agudo`, `O` `Prato de ataque`, `P` `Prato de condução` ([04b Bateria](../manual/04b-bateria.md)). O `Cowbell` (nota 56) fica fora do alcance de uma oitava só: com `X` (oitava `C3`) ele cai na tecla `Y`.
6. `Ctrl+K` de novo desliga o teclado e devolve `S`, `E`, `F`, `L`, `C`, `X` e `Z` aos atalhos. Depois de gravar, `E` abre o editor no clipe selecionado; se ele mostrar `Nenhum clipe aberto`, clique no clipe novo antes. `(não confirmado se o clipe recém-gravado já fica selecionado)`

Sequência para decorar: **`Ctrl+K`, `R`, (toque), `R`, `Ctrl+K`, `E`** (numa faixa de bateria; num sintetizador, o mesmo).

Com um controlador MIDI (botão do cabo) as letras ficam livres: deixe o `Ctrl+K` desligado e `S`, `L`, `E`, `F`, `X` seguem valendo enquanto as mãos tocam no controlador.

### 4. Editar notas só com o teclado

Teclas (com o editor ativo): `Ctrl+A`, `Ctrl+C`, `Ctrl+X`, `Ctrl+V`, `Ctrl+D`, `Delete`, `Q`, `K`, `J`, `Shift+H`, `Shift+L`, `↑`, `↓`, `←`, `→` (com `Shift`), `Esc`.

1. `E` abre o editor no clipe de notas selecionado. Clique uma vez dentro dele para ter certeza de que ele é o último lugar clicado (o contador de notas confirma o efeito de cada tecla).
2. **Limpar uma linha tocada ao vivo.** Escolha a grade certa (`1/16`, o padrão; a quantização usa a grade do **editor**, não a do arranjo), `Ctrl+A` (tudo), `Q` (quantiza: `Força` e `Quantizar as durações também` estão no menu da seta ao lado do botão `Quantizar`), `J` (une notas iguais adjacentes). Um passo de `Ctrl+Z` desfaz cada uma.
3. **Repetir e transpor um compasso.** `Ctrl+A`, `Ctrl+D` (a cópia cai logo depois, em compasso inteiro, já selecionada e o clipe cresce se precisar), `↓` transpõe 1 semitom, `Shift+↓` uma oitava; `←` e `→` movem 1 passo da grade (1/16 se `Livre`), `Shift+←` e `Shift+→` movem 1 compasso. Sem nada selecionado as setas não fazem nada.
4. **Emendar as notas.** `Ctrl+A`, `Shift+L` (legato: cada nota vai até o início da próxima; dentro do editor, `Shift+L` é legato, e não o loop do clipe).
5. **Dar folga humana.** `Shift+H` humaniza com os últimos ajustes do diálogo `Humanizar…` (`Tempo` e `Velocidade`); sem nunca ter aberto o diálogo, valem `Tempo` 50% e `Velocidade` 50%, e a cada aperto o sorteio é novo.
6. **Dividir uma nota no cursor.** Clique na régua do editor para pôr o cursor sobre a nota e `K`: divide as notas que ele atravessa (na seleção, ou em todas se nada estiver selecionado).
7. `Ctrl+C` copia; `Ctrl+X` recorta; `Ctrl+V` cola no cursor de reprodução (se ele está dentro do clipe) ou no começo da parte visível; colar de novo no mesmo ponto põe a cópia logo depois da anterior.
8. `Esc` limpa a seleção; um segundo `Esc` (sem nada selecionado) fecha o painel.

Sequência para decorar: **`E`, clique, `Ctrl+A`, `Q`, `J`, `Ctrl+D`, `↑`, `Esc`, `Esc`**.

### 5. Ajustar o som e conferir no mixer

Teclas: `I`, `X`, `F`, `Esc`, `?`.

1. `I` abre o painel `Instrumento`. Nos knobs: arrastar muda o valor; com `Shift`, o ajuste é 5 vezes mais fino; duplo clique volta ao padrão; botão direito abre a digitação (`1,8 kHz`, `350 ms`, `70%`), e `Enter` aplica.
2. `X` abre o mixer: fader, pan e envios aceitam `Shift` para o ajuste fino e duplo clique para 0 dB (pan volta ao centro).
3. `F` abre os efeitos da faixa selecionada (sem faixa selecionada, os do master).
4. Cada uma dessas teclas alterna: apertar a mesma de novo fecha o painel. `Esc` fecha o painel de baixo. `?` abre a janela `Atalhos do teclado`.
5. Na raia de automação (depois de clicar nela): `Delete` apaga os pontos selecionados, `Ctrl+A` seleciona todos os pontos da raia e `Esc` limpa a seleção (o `Esc` também segue para a tela).

Sequência para decorar: **`I`, (ajuste), `X`, (ajuste), `F`, `Esc`**.

### 6. Combinações de mouse e tecla que valem a pena

| Combinação | Efeito |
|---|---|
| `Alt` ao arrastar clipe, marcador ou borda | Sem encaixe na grade naquele arraste |
| `Alt` no começo do arraste de uma nota | Duplica em vez de mover |
| `Shift` ao arrastar knob, fader, pan ou envio | Ajuste fino (5 vezes mais lento) |
| `Shift` + clique numa nota | Soma ou tira da seleção |
| `Shift` ou `Ctrl` + arrastar no vazio do editor | Seleção por retângulo (`Shift` soma) |
| `Ctrl` + roda | Zoom no ponto do mouse (no editor, horizontal) |
| `Shift` + roda | Rolar na horizontal |
| `Alt` + roda (no editor) | Altura das linhas |
| `Shift` + arrastar na faixa de controle do editor (`Pitch bend`, `Modulação`) | Traça uma reta em vez de desenhar com o lápis |
| `Alt` + clique num ponto da faixa de controle | Apaga o ponto |
| Duplo clique num knob, no fader ou no envio | Volta ao padrão (0 dB nos dois últimos) |

### 7. O que não tem tecla

O arranjo não tem tecla para: selecionar clipe ou faixa; armar (`Armar para gravar`) ou monitorar; mudo (`M` é marcador) e solo; mover o cursor para um ponto qualquer (só `Enter`, `Home`, `[` e `]`, ou clicar na régua); criar faixa; mudar o andamento (clique em `120 BPM · 4/4`); abrir `Warp e altura…`; exportar; trocar a grade. Esses ficam no mouse (ou no toque). O ganho do fluxo é fazer o **verbo** no teclado (tocar, cortar, duplicar, quantizar, gravar) e deixar o mouse só para escolher **onde**.

## Variações

- **Só com o toque, no celular.** Os atalhos só existem com teclado físico conectado `(não confirmado)`. No toque, os mesmos verbos estão nos botões da barra (`Cortar no cursor (S)`, `Duplicar (Ctrl+D)`, `Apagar o clipe (Delete)`, `Desfazer (Ctrl+Z)`); os tooltips guardam a tecla.
- **Teclado sempre ligado.** Quem toca muito nas teclas pode deixar o `Ctrl+K` ligado o tempo todo e usar só os atalhos que sobram (`Espaço`, `Enter`, `Home`, `R`, `M`, `[`, `]`, `I`, `Esc`, `=`, `+`, `−`, `Delete`, `Backspace` e `Ctrl+...`): é possível gravar, marcar, voltar e apagar sem desligar.
- **Controlador MIDI com pedal, bend e roda.** Pelo código atual, além das notas e da velocidade, o app lê o pedal de sustain (`CC 64`, ligado a partir de 64), a roda de modulação (`CC 1`) e o pitch bend, e grava os três no clipe (o teclado da tela também tem rodas de bend e modulação). O capítulo 03c ainda diz que eles não são lidos. `(não confirmado em uso)` Com o `Ctrl+K` desligado, as letras seguem livres para os atalhos.
- **Aprender pela janela.** Com o estúdio em foco, `?` abre `Atalhos do teclado` (o botão `Fechar` sai). Funciona em qualquer layout que produza o caractere `?`.

## Por que funciona

- **Verbos na mão esquerda, sempre à mão.** As teclas mais usadas ficam ao alcance de uma mão só: `S` (cortar), `L` (loop), `X`, `E`, `I`, `F` (painéis), `C` (metrônomo), `Z` (enquadrar), mais `Espaço`, `Enter` e `R`. Como as mesmas letras são as do teclado musical, o app deixa o teclado musical passar na frente **só enquanto ligado**, e `Ctrl` é a saída de emergência: com ele apertado a letra volta a ser atalho.
- **Camadas previsíveis.** Teclado musical, depois editor ativo, depois atalhos gerais. Se uma tecla faz algo inesperado, é porque uma camada de cima pegou antes: `S` virou nota (teclado ligado) ou `Delete` apagou nota (editor ativo).
- **Seleção é o único gesto que exige o mouse.** Tudo o que age sobre um clipe usa o clipe selecionado ou, na falta, o cursor na faixa selecionada. Por isso as sequências começam com um clique e continuam no teclado.
- **Cada ferramenta é um passo do desfazer.** `Q`, `J`, `Shift+L` e `Ctrl+D` se desfazem com um só `Ctrl+Z`; dá para experimentar rápido e voltar.

## Se der errado

| Sintoma | Causa provável | Como resolver |
|---|---|---|
| Nenhuma tecla responde | Você está digitando num campo (nome, `BPM`), ou o foco está em outra janela | Feche o campo (`Enter` ou clique no estúdio) e tente de novo |
| `S`, `E`, `F`, `L`, `C`, `X` ou `Z` tocam nota em vez de agir | Teclado do computador ligado (o botão mostra `C4 · sem atalhos`) | `Ctrl+K` desliga (o botão volta a mostrar só o ícone) |
| `Z` não enquadra e muda a oitava | Idem: com o teclado ligado `Z` e `X` são oitava | `Ctrl+K` |
| `Delete` apaga notas, não o clipe | O editor é o último lugar clicado | Clique num clipe no arranjo (ou fora do editor) e aperte `Delete` de novo |
| `Ctrl+D` duplicou o clipe em vez das notas (ou o contrário) | Depende de onde foi o último clique | Clique dentro do editor para notas; no arranjo para clipes |
| `Shift+L` fez o loop do clipe, não da seção | Há um clipe selecionado | Desmarque o clipe (clique no vazio da raia) e repita |
| `Shift+L` não faz nada | Nem clipe selecionado nem cursor depois de um marcador | Crie um marcador antes (`M`) e ponha o cursor depois dele |
| `K`, `J`, `Shift+H`, `Shift+L` não agem no editor | Teclado ligado (letras viram nota) ou o editor não está ativo | `Ctrl+K` para desligar; clique dentro do editor |
| `Ctrl+Z`, `Ctrl+I` ou `Ctrl+Y` não fazem nada | Está gravando | Pare a gravação (`R`, `Espaço` ou `Enter`) |
| `R` recarrega a página | Você apertou `Ctrl+R` ou `Cmd+R` | `R` sozinho grava; com `Ctrl` fica para o navegador |
| As setas não movem nada | Não há nota selecionada (elas só agem com seleção) | `Ctrl+A` ou selecione com o retângulo |
| `+` não aproxima | A tecla `=` e o `+` do teclado numérico funcionam; o `+` com `Shift` no teclado principal `(não confirmado)` | Use `=`, o `+` do teclado numérico ou o botão `Aproximar` |
| A bateria não soa quando toco as letras | A oitava está acima do que a bateria responde (só as notas 35 a 59; o padrão dela é `C2`), ou a faixa que toca não é a bateria (a oitava é por tipo de faixa; toca a selecionada, ou a primeira de instrumento armada) | Olhe o botão do teclado: numa bateria ele deve mostrar `C2 · sem atalhos`; volte com `Z` e confira qual faixa está selecionada ou armada |
| No Mac o atalho não funciona | No Mac a tecla é `Cmd` (os tooltips agora escrevem `⌘`) | `Cmd+Z`, `Cmd+D`, `Cmd+K`... |
| `Ctrl+D` adiciona o site aos favoritos | Pode acontecer em alguns navegadores se o app não consumir a tecla `(não confirmado)` | Use o botão `Duplicar (Ctrl+D)` da barra |
