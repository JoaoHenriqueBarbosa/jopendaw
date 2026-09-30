# Configurações, atalhos e Android

> Tudo o que se ajusta uma vez e se esquece: a janela `Configurações` (entrada de áudio, contagem, pré-roll, punch, latência e metrônomo), a lista completa de atalhos de teclado (e como personalizá-los), as permissões de microfone e MIDI, e o que muda entre usar o jopendaw no navegador ou no app Android.

## Onde fica

- **Configurações:** botão de engrenagem na barra de transporte (tooltip `Configurações: entrada de áudio, latência e contagem`), ou a seta ao lado do botão de gravar (`Opções de gravação`) e o item `Configurações de gravação…`.
- **Atalhos:** a tecla `?` com o estúdio em foco (vale em qualquer largura, com teclado físico); o botão `Atalhos do teclado` no rodapé da janela `Configurações` (sempre presente, e é o caminho no celular); e o botão de teclado com o símbolo de comando na barra de transporte (tooltip `Atalhos do teclado (?)`, com a tecla de agora da ação `Janela de atalhos`), que **só existe em janelas de 1640 px ou mais** (em janelas menores, inclusive no celular, ele foi tirado para a barra caber; ver [capítulo 02](02-transporte.md#onde-fica)). Para **personalizar**, o botão `Personalizar` no rodapé dessa janela (aparece em todo aparelho, inclusive no app Android; num celular ou tablet em que nenhuma tecla de teclado físico foi vista, a tela avisa que precisa de um). Passo a passo em [Personalizar os atalhos](#personalizar-os-atalhos).
- **Permissões:** aparecem sozinhas na primeira vez que o app precisa do microfone ou do MIDI (ver abaixo).
- **Barra de transporte:** no computador fica no topo do projeto; no celular, embaixo ([capítulo 00](00-visao-geral.md)).

## Controles

### Janela `Configurações`

Abre com três seções, `ENTRADA DE ÁUDIO`, `GRAVAÇÃO` e `METRÔNOMO` (esta desde a fase 17), e, no rodapé, dois botões: `Atalhos do teclado` (à esquerda, botão de texto com o ícone de tecla de comando) e `Fechar` (cheio). Ao abrir, a janela procura as entradas de áudio e, na web, é aí que o navegador pede permissão para o microfone. Se ninguém mais precisava do microfone, a entrada é fechada de novo ao terminar a procura.

**Seção `ENTRADA DE ÁUDIO`**

| Controle (rótulo exato) | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| Seletor de entrada | Escolhe de onde vem o áudio da gravação e do monitoramento | Primeiro item `Padrão do sistema` (ou `Padrão (<nome do aparelho>)` quando o navegador informa qual é a padrão); depois cada entrada pelo nome; sem permissão os nomes ficam escondidos e aparecem como `Entrada 1`, `Entrada 2`… | Trocar com uma faixa armada reabre a entrada na hora |
| Item `Entrada desconectada` | Aparece quando a entrada escolhida antes sumiu (cabo puxado, interface desligada) | Em vermelho: `A entrada escolhida não está conectada. Conecte de novo ou escolha outra.` | Se a escolhida não abrir, o app usa a padrão e avisa: `A entrada de áudio escolhida não abriu (foi desconectada?): usando a entrada padrão.` |
| Botão de atualizar (tooltip `Procurar as entradas de novo (depois de conectar um microfone ou interface)`) | Refaz a lista | Vira um círculo girando enquanto procura ou troca | Use depois de plugar um microfone ou interface |
| Texto de apoio | Estado da lista | Na web: `O navegador pede permissão para o microfone na primeira vez.` No Android: `O Android pede permissão para o microfone na primeira vez.` Nos dois: `Nenhuma entrada encontrada. Conecte um microfone ou interface e toque em procurar.`; `Pare a gravação para trocar de entrada.` | O seletor fica desligado durante a gravação e enquanto procura |
| `Nível` | Barra horizontal com o nível de entrada | Texto: `Mexe enquanto a entrada está aberta: com uma faixa de áudio armada ou monitorando.` | Serve para acertar o ganho do microfone antes de gravar |
| Aviso vermelho | Erro ao procurar ou trocar a entrada | Mensagens na seção "Permissões" | |

A escolha da entrada é do **aparelho**: fica guardada nele e não vai para a nuvem nem muda ao abrir o mesmo projeto em outro aparelho.

**Seção `GRAVAÇÃO`**

| Controle (rótulo exato) | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| Interruptor `Contagem de um compasso` | Liga a contagem: o metrônomo conta um compasso antes de a gravação começar. Legenda: `O metrônomo conta um compasso antes de a gravação começar` | Padrão: ligado, em qualquer projeto novo | Mesmo controle do item `Contagem de um compasso` do menu `Opções de gravação`. Não entra no desfazer |
| Título `Pré-roll` com cinco fichas de escolha (`Não`, `1`, `2`, `3`, `4`) e, abaixo, o texto `Compassos que tocam a música antes de a gravação valer (com punch, antes do punch in). É independente da contagem: a contagem são os cliques, o pré-roll é o arranjo tocando.` | Quantos compassos do arranjo tocam antes do ponto de gravar (o cursor, ou o punch in com punch ligado). Contados para trás pelo mapa de compassos; perto do zero só vai até o zero | 0 a 4 compassos, padrão `Não` (0) | Mesmo controle da lista `Pré-roll` do menu `Opções de gravação` (`Sem pré-roll`, `1 compasso`…). Só vale com o transporte parado ao apertar `R`. Fora do desfazer |
| Interruptor `Punch in/out`, com a legenda `Ligue para marcar a região na régua (arraste as pontas vermelhas)` (sem região) ou `Da posição 9.1.1 à 11.1.1: só isso é gravado` (com região; as posições no formato `compasso.tempo.dezesseis-avos`) | Liga o punch: a gravação só vale entre o punch in e o punch out | Padrão desligado. Ligando sem região, ela nasce do loop (se ligado e com largura) ou de dois compassos a partir do cursor | Mesmo controle do botão `Punch (P)` e do item `Punch in/out (P)` da barra. Gravando, avisa `Pare a gravação para ligar ou desligar o punch.`. Fora do desfazer |
| Botão de texto `Usar a região do loop` | Copia a região do loop para a do punch, sem ligar o punch | Desligado (cinza) se o **loop está desligado**, se a região tem 0,01 batida ou menos de largura ou se está gravando. Desde a fase 19 é o mesmo critério do interruptor `Punch in/out` (antes o botão também copiava o loop desligado, com o 0 a 16 padrão que ele guarda) | Serve para marcar o punch por cima de uma região de loop já desenhada e ligada |
| Controle deslizante `Compensação de latência` | Ajusta o quanto o áudio gravado é deslocado para acertar a batida | De −200 a 500 ms, passos de 1 ms, padrão 0 ms (vale além da latência do motor e do aparelho, que já é medida sozinha; a ida e volta do monitoramento aparece logo abaixo) | O número aparece sobre o controle enquanto se arrasta; só vale ao soltar |
| Campo numérico com o sufixo `ms` | O mesmo valor, digitado | Aceita dígitos e o sinal de menos (`-` ou `−`); fora da faixa mostra `De -200 a 500 ms` | Vale ao apertar `Enter`, ao sair do campo ou ao tocar em `Fechar` |
| Texto de apoio | Como usar | `Quanto o áudio gravado chega atrasado, além do que já é medido sozinho (a latência do motor, com os efeitos e o limitador, e a que o navegador informa para a entrada e a saída): positivo adianta o que for gravado, negativo atrasa. Para medir, grave o metrônomo pelo microfone e ajuste até a batida gravada cair na grade.` No Android, onde está "o navegador" o texto diz `o sistema` | Um número inválido segura a janela aberta com o motivo à vista |
| Linha `Ida e volta do monitoramento: N ms`, com a legenda `Entrada do aparelho, motor com a compensação dos efeitos e saída, somados: o atraso que quem toca ouve entre o gesto e o som.` | Só informa (não é controle): a soma da latência de entrada do aparelho, da do motor (PDC dos efeitos, cadeia do `Master` e limitador de segurança) e da saída do aparelho, em ms inteiros | Sem o microfone aberto a linha ganha ` (sem a entrada: ela só é medida com o microfone aberto)` e a parte da entrada não entra na soma | É o atraso que quem toca ouve ao monitorar; não muda a gravação nem a `Compensação de latência` |
| `Fechar` | Fecha a janela | | Leva junto o número digitado e ainda não confirmado |

A contagem, o pré-roll, o punch (região e liga/desliga) e a latência valem para **este projeto** (ficam no documento do projeto, e por isso sobem à nuvem), mas ao receber uma versão nova da nuvem cada aparelho mantém a sua. Nenhum deles entra no desfazer (é calibragem e preferência, não edição da música).

**Seção `METRÔNOMO`**

Vem depois da `Ida e volta do monitoramento`. Os três primeiros são listas; os quatro seguintes, controles deslizantes com o valor à direita que só entregam o número **ao soltar** (arrastar não manda o estilo ao motor a cada passo). Tudo vale para o projeto, fica fora do desfazer e só vai ao arquivo quando foge do padrão (`metronome_options`, [dev/10](../dev/10-app-flutter.md#punch-pré-roll-tap-tempo-e-opções-do-metrônomo-fase-17-c)).

| Controle (rótulo exato) | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| Lista `Timbre` | O som do clique | `Clique` (padrão: senoide de 30 ms em 1000 Hz), `Madeira` (60 ms, 800 Hz mais uma parcial em 2,4 vezes), `Bipe agudo` (50 ms, 1800 Hz, corpo plano), `Cowbell` (160 ms, 540 Hz mais uma parcial inarmônica em 1,4815 vezes) e `Hi-hat` (60 ms de ruído com passa-altas em 6000 Hz) | `(o som dos timbres não foi ouvido; durações e frequências são as do código do motor)` |
| Lista `Subdivisão` | Quantos cliques cabem em cada tempo do compasso | `Um clique por tempo` (padrão), `Colcheias` (2 por tempo), `Tercinas` (3), `Semicolcheias` (4) e `Só o acento do compasso` (1 clique por compasso, no primeiro tempo) | O "tempo" é a semínima em x/4 e a colcheia em 6/8 e 7/8: em 4/4, `Colcheias` dá 8 cliques por compasso; em 6/8, 12 |
| Lista `Quando soa` | Em que condição o clique toca | `Sempre que ligado` (padrão) ou `Só ao gravar` | No modo `Só ao gravar` o botão do metrônomo (`C`) é a permissão: ligado, o clique só soa gravando, na contagem e no pré-roll |
| Controle `Volume` | Volume do clique comum | 0 a 100%, padrão **60%** | É o ganho da chamada `metronome` do motor (0,6, o mesmo do motor sozinho: desde a fase 19 o app e um motor novo soam igual; até a fase 18 o padrão do app era 50%). Um projeto que nunca mexeu nele agora abre com 60% |
| Controle `Acento do primeiro tempo` | Nível do clique do primeiro tempo do compasso em relação ao `Volume` | 0 a 200%, padrão 100% | 0% cala o primeiro tempo; os outros seguem. O pico do clique é `Volume × nível` e não passa de 1,0: o nível mandado ao motor é limitado a `1 ÷ Volume` (com `Volume` 100%, o acento de 200% soa como 100%; com 60%, como 166,7%). O controle e o projeto guardam o valor que você pôs |
| Controle `Altura do acento` | Quanto o acento é mais agudo que o clique comum (razão de frequência) | `×0,50` a `×4,00`, padrão `×1,60` (1600 Hz sobre 1000 Hz no timbre `Clique`) | No `Hi-hat` mexe no corte do passa-altas |
| Controle `Volume das subdivisões` | Nível dos cliques entre os tempos em relação ao `Volume` | 0 a 200%, padrão 50% | **Só aparece** com `Colcheias`, `Tercinas` ou `Semicolcheias`. Vale o mesmo teto de pico 1,0 do acento (nível limitado a `1 ÷ Volume` no que soa) |
| Texto de apoio | Lembra como ligar | `Liga e desliga pelo botão do metrônomo (C). O clique acompanha o compasso e o andamento do projeto.` e, no modo `Só ao gravar`, `Liga e desliga pelo botão do metrônomo (C); nesse modo ele só soa gravando, na contagem e no pré-roll.` | O `(C)` é a tecla de agora da ação `Metrônomo`: se você a personalizou, o texto mostra a nova; sem atalho, o parêntese some |

O motor recebe o estilo pela chamada `metronome_style` quando algo muda; um projeto com tudo no padrão nunca a envia. O clique não vai para a exportação. Detalhes de como gravar: [capítulo 03c](03c-gravacao.md).

### Janela `Atalhos do teclado`

Abre com a tecla `?` (ou `Shift+/`, que o teclado digita como `?`; ver a nota sobre `Shift+/` em [Exportar e importar](#exportar-e-importar-o-arquivo-jokeys)), com o botão `Atalhos do teclado` do rodapé da janela `Configurações` ou com o botão da barra (só em janelas de 1640 px ou mais). **A lista é gerada do catálogo de ações** (`app/lib/daw/keymap.dart`) e das teclas de agora: se você personalizar um atalho, a janela já mostra o novo (fase 16). O rodapé tem `Personalizar` (sempre presente, também no Android; ver [Personalizar os atalhos](#personalizar-os-atalhos)) e `Fechar`. Os títulos dos grupos aparecem em maiúsculas. Cada linha mostra as teclas (várias separadas por `·`; ação sem tecla mostra `—`) e o texto da ação; com a tela abaixo de 520 px de largura as teclas ficam em cima do texto.

São 8 grupos, nesta ordem: `Transporte`, `Marcadores e loop`, `Visão`, `Edição`, `Painéis`, `Aprender MIDI`, `Teclado do computador (Ctrl+K liga)` (o título escreve as teclas de agora do `Teclado do computador liga/desliga`; no Mac, `⌘+K liga`; se você tirou todos os atalhos dessa ação, o título é só `Teclado do computador`, sem `Sem atalho liga`) e `Piano roll`. Depois vem o grupo `Suspensos enquanto o teclado do computador está ligado`. Antes da fase 16 o grupo `Aprender MIDI` vinha entre `Edição` e `Painéis`.

Nesta página `Ctrl` vale para Windows, Linux e Chrome OS; no Mac (e no iOS) a mesma tecla é `⌘` (`Cmd`), e a janela já mostra o símbolo certo (`⌘+Z`). As tabelas abaixo foram conferidas contra `app/lib/daw/keymap.dart` (o catálogo, com as **57 ações** e as teclas padrão; `Punch liga/desliga` e `Tap tempo` entraram na fase 17 e `Abrir o histórico` (`Ctrl+Shift+H`, id `history.open`, logo depois de `Importar áudio ou MIDI`) na fase 18), `shortcuts_dialog.dart` e `project_screen.dart` na versão `53ca96d` `(testado só por testes automáticos: a janela nova, gerada do catálogo, não foi vista no navegador)`. Cada tabela é um grupo da janela: **Ação** é o rótulo do catálogo, **Contexto** diz onde a ação vale (ver [Contextos e camadas](#contextos-e-camadas)), **Texto na janela** só aparece quando a janela escreve algo mais longo que o rótulo, e **Id** é o nome estável da ação no arquivo `.jokeys` ([Formato do arquivo](#exportar-e-importar-o-arquivo-jokeys)).

**Transporte**

| Ação | Contexto | Teclas padrão | Texto na janela | Id |
|---|---|---|---|---|
| Tocar / pausar | Geral | `Espaço` | | `transport.play` |
| Parar | Geral | `Enter` · `Home` | Parar e voltar ao começo (ou ao início do loop) | `transport.stop` |
| Gravar | Geral | `R` | Gravar (com faixas armadas) | `transport.record` |
| Loop liga/desliga | Geral | `L` | Loop liga/desliga (arraste na régua para marcar a região) | `transport.loop` |
| Metrônomo | Geral | `C` | | `transport.metronome` |
| Punch liga/desliga | Geral | `P` | Punch liga/desliga: com ele, a gravação só vale na região marcada na régua | `transport.punch` |
| Tap tempo | Geral | `T` | Tap tempo: bata no ritmo; o andamento vale quando você para de bater | `transport.tap` |

**Marcadores e loop**

| Ação | Contexto | Teclas padrão | Texto na janela | Id |
|---|---|---|---|---|
| Marcador no cursor | Geral | `M` | | `marker.add` |
| Marcador no cursor, pedindo o nome | Geral | `Shift+M` | | `marker.rename` |
| Cursor no marcador anterior | Geral | `[` | | `marker.prev` |
| Cursor no marcador seguinte | Geral | `]` | | `marker.next` |
| Loop no clipe selecionado | Arranjo | `Shift+L` | Loop no clipe selecionado (ou na seção do cursor) | `loop.clip` |

**Visão**

| Ação | Contexto | Teclas padrão | Texto na janela | Id |
|---|---|---|---|---|
| Enquadrar o projeto inteiro | Geral | `Z` | | `view.fitAll` |
| Enquadrar o clipe selecionado | Arranjo | `Shift+Z` | | `view.fitClip` |
| Aproximar | Geral | `+` · `=` | | `view.zoomIn` |
| Afastar | Geral | `−` | | `view.zoomOut` |
| Seguir o cursor | Geral | (sem atalho: a janela mostra `—`) | | `view.follow` |

O `+` e o `−` andam em passos de 1,25 vez (aproximar) e 0,8 (afastar), ancorados no cursor. O `−` da tabela é a tecla de menos; o `+` também vale com `Shift+=` e o teclado numérico tem o seu `+` e `−` (mesmas ações).

**Edição**

| Ação | Contexto | Teclas padrão | Texto na janela | Id |
|---|---|---|---|---|
| Desfazer | Geral | `Ctrl+Z` | | `edit.undo` |
| Refazer | Geral | `Ctrl+Shift+Z` · `Ctrl+Y` | | `edit.redo` |
| Duplicar o clipe | Arranjo | `Ctrl+D` | | `edit.duplicate` |
| Cortar no cursor | Arranjo | `S` | | `edit.split` |
| Apagar o clipe | Arranjo | `Delete` · `Backspace` | | `edit.delete` |
| Importar áudio ou MIDI | Geral | `Ctrl+I` | | `edit.import` |
| Abrir o histórico | Geral | `Ctrl+Shift+H` | Histórico de desfazer e versões do projeto | `history.open` |

`Importar áudio ou MIDI` abre o mesmo seletor do botão da barra (que aceita áudio e arquivos MIDI `.mid` e `.midi`).

`Abrir o histórico` abre o painel `Histórico` (passos do desfazer, com o botão `Versões…`); a janela escreve o texto `Histórico de desfazer e versões do projeto`. Ver [02d Histórico e versões](02d-historico-e-versoes.md). Em alguns navegadores esse mesmo atalho é do próprio navegador (histórico de navegação): se a tecla não chegar ao app, troque-a em `Personalizar` ou use o botão direito em `Desfazer`. `(não confirmado)`

**Painéis**

| Ação | Contexto | Teclas padrão | Texto na janela | Id |
|---|---|---|---|---|
| Mixer | Geral | `X` | | `panel.mixer` |
| Editor de notas (piano roll) | Geral | `E` | | `panel.editor` |
| Instrumento da faixa | Geral | `I` | | `panel.instrument` |
| Efeitos da faixa | Geral | `F` | | `panel.effects` |
| Fechar o painel | Geral | `Esc` (fixa: não muda) | | `panel.close` |
| Janela de atalhos | Geral | `?` | Esta janela | `help.shortcuts` |

**Aprender MIDI**

Capítulo próprio: [06f MIDI learn](06f-midi-learn.md).

| Ação | Contexto | Teclas padrão | Texto na janela | Id |
|---|---|---|---|---|
| Cancelar o controle armado | Geral | `Esc` (fixa: não muda) | Cancela o controle armado; de novo, sai do modo | `midilearn.cancel` |
| Aprender MIDI liga/desliga | Geral | `Shift+K` | Liga o modo: os controles ganham contorno; clique num e mexa no botão do teclado | `midilearn.toggle` |

**Teclado do computador (`Ctrl+K` liga)**

| Ação | Contexto | Teclas padrão | Texto na janela | Id |
|---|---|---|---|---|
| Teclado do computador liga/desliga | Geral | `Ctrl+K` | | `kbd.toggle` |
| Oitava abaixo | Teclado tocando | `Z` | Oitava abaixo (só da faixa que está tocando: a bateria começa no C2) | `kbd.octaveDown` |
| Oitava acima | Teclado tocando | `X` | | `kbd.octaveUp` |
| Velocidade menor | Teclado tocando | `C` | | `kbd.velocityDown` |
| Velocidade maior | Teclado tocando | `V` | | `kbd.velocityUp` |

As 16 teclas de nota (`A W S E D F T G Y H U J K O L P`, do dó até o ré# da oitava de cima) **não fazem parte do catálogo e não se personalizam**: a janela as lista numa linha à parte (ver "Linhas de mouse e menu" abaixo). As quatro ações do contexto `Teclado tocando` são presas à **posição física** da tecla, como as notas.

**Piano roll**

Valem com o editor ativo (ver as regras de prioridade abaixo).

| Ação | Contexto | Teclas padrão | Texto na janela | Id |
|---|---|---|---|---|
| Selecionar tudo | Piano roll | `Ctrl+A` | | `pr.selectAll` |
| Copiar | Piano roll | `Ctrl+C` | | `pr.copy` |
| Recortar | Piano roll | `Ctrl+X` | | `pr.cut` |
| Colar no cursor | Piano roll | `Ctrl+V` | | `pr.paste` |
| Duplicar as notas | Piano roll | `Ctrl+D` | | `pr.duplicate` |
| Apagar as notas | Piano roll | `Delete` · `Backspace` | | `pr.delete` |
| Limpar a seleção | Piano roll | `Esc` (fixa: não muda) | | `pr.deselect` |
| Quantizar | Piano roll | `Q` | | `pr.quantize` |
| Dividir as notas no cursor | Piano roll | `K` | Dividir as notas no cursor (a seleção, ou todas) | `pr.split` |
| Unir notas iguais adjacentes | Piano roll | `J` | | `pr.join` |
| Humanizar | Piano roll | `Shift+H` | Humanizar com os últimos ajustes | `pr.humanize` |
| Legato | Piano roll | `Shift+L` | Legato: cada nota vai até a próxima | `pr.legato` |
| Transpor um semitom acima | Piano roll | `↑` | | `pr.up` |
| Transpor um semitom abaixo | Piano roll | `↓` | | `pr.down` |
| Transpor uma oitava acima | Piano roll | `Shift+↑` | | `pr.octaveUp` |
| Transpor uma oitava abaixo | Piano roll | `Shift+↓` | | `pr.octaveDown` |
| Mover para a esquerda (grade) | Piano roll | `←` | | `pr.left` |
| Mover para a direita (grade) | Piano roll | `→` | | `pr.right` |
| Mover um compasso para a esquerda | Piano roll | `Shift+←` | | `pr.barLeft` |
| Mover um compasso para a direita | Piano roll | `Shift+→` | | `pr.barRight` |

As setas só agem com notas selecionadas; na bateria as linhas são peças, então a oitava anda uma linha, como o semitom. Os detalhes de cada ação estão em [05 Piano roll](05-piano-roll.md) e [05b Ferramentas MIDI](05b-ferramentas-midi.md).

**Linhas de mouse e menu (fixas, não são do catálogo)**

A janela acrescenta ao fim de alguns grupos estas linhas, que descrevem gestos e menus e **não se personalizam**:

| Grupo | Linha (teclas) | Texto |
|---|---|---|
| `Marcadores e loop` | Arrastar · duplo clique | Move (com encaixe) · renomeia o marcador na régua |
| `Marcadores e loop` | Botão direito | Menu do marcador: cor, loop da seção, apagar |
| `Marcadores e loop` | Menu `Seções` | Lista de marcadores, loop entre marcadores e da seção |
| `Visão` | Menu `Visão` | Altura das faixas (pequena, média, grande), seguir o cursor, régua em mm:ss |
| `Visão` | Clique em `comp.` / `mm:ss` | Alterna a régua entre compassos e tempo |
| `Visão` | `Visão geral` (embaixo) | Clique ou arraste para rolar o projeto |
| `Edição` | `Ctrl + roda` | Zoom no ponto do mouse |
| `Edição` | `Shift + roda` | Rolar na horizontal |
| `Aprender MIDI` | Botão direito · toque longo | Menu do controle: aprender ou remover o mapeamento |
| `Teclado do computador` | `A W S E D F T G Y H U J K O L P` (com o layout aprendido, cada letra sai como a que está na tecla: `Q (posição do A)` num AZERTY, por exemplo) | Notas: do dó até o ré# da oitava de cima |
| `Teclado do computador` | `Por posição` (só aparece se alguma tecla aprendida difere do QWERTY) | As teclas de nota, oitava e velocidade seguem a posição no teclado (a fileira do A), não a letra: o seu layout não é QWERTY. |
| `Piano roll` | Clique no vazio | Nova nota (arraste para a duração) |
| `Piano roll` | `Alt` ao arrastar | Sem grade; no começo do arraste, duplica |
| `Piano roll` | Menu `Ferramentas` | Escala, acordes, arpejador, rampa de velocidade, inverter, escalar o tempo, fantasmas |

**Suspensos enquanto o teclado do computador está ligado**

Este grupo é **calculado** a cada abertura (`suspendedShortcutsOf` em `shortcuts_dialog.dart`) a partir das teclas de agora: entra cada ação do estúdio ou do piano roll que tenha uma tecla **sem `Ctrl`/`⌘` nem `Alt`** que seja letra de nota (`A W S E D F T G Y H U J K O L P`) ou tecla do teclado tocando (as de oitava e velocidade). Se você tirar `Mixer` do `X`, ele sai da lista; se puser `Gravar` no `Y`, ele entra. Com os padrões são estas 16 linhas (o texto é o rótulo da ação e o que a tecla vira):

| Tecla | Ação suspensa (e no que a tecla se transforma) |
|---|---|
| `L` | Loop liga/desliga (vira nota) |
| `C` | Metrônomo (vira velocidade menor) |
| `P` | Punch liga/desliga (vira nota) |
| `T` | Tap tempo (vira nota) |
| `Shift+L` | Loop no clipe selecionado (vira nota) |
| `Z` | Enquadrar o projeto inteiro (vira oitava abaixo) |
| `Shift+Z` | Enquadrar o clipe selecionado (vira oitava abaixo) |
| `S` | Cortar no cursor (vira nota) |
| `X` | Mixer (vira oitava acima) |
| `E` | Editor de notas (piano roll) (vira nota) |
| `F` | Efeitos da faixa (vira nota) |
| `Shift+K` | Aprender MIDI liga/desliga (vira nota) |
| `K` | Dividir as notas no cursor (vira nota) |
| `J` | Unir notas iguais adjacentes (vira nota) |
| `Shift+H` | Humanizar (vira nota) |
| `Shift+L` | Legato (vira nota) |

As duas últimas linhas do grupo são `Com Ctrl` (`Com ⌘` no Mac): `Os atalhos com Ctrl continuam valendo (desfazer, duplicar, importar, Ctrl+K desliga o teclado)`, e o `Ctrl+K` que ela escreve é a tecla de agora do `Teclado do computador liga/desliga` (sem nenhuma tecla nessa ação, o texto é `Os atalhos com Ctrl continuam valendo (desfazer, duplicar, importar); o teclado do computador desliga pelo botão da barra`); e `Com Shift`: `Não muda nada: Shift+L toca a nota L, como L. Os atalhos com Shift nessas letras ficam suspensos; desligue o teclado para usá-los`. O teclado tocando ignora o `Shift`: `Shift+L` também é a letra `L`, então com o teclado ligado ele toca nota em vez de fazer o loop do clipe.

**O que a janela não escreve, mas o código aceita**

| Tecla | Ação |
|---|---|
| `+` e `−` do teclado numérico | Aproximar / afastar (mesmas ações de `+` e `−` do teclado principal) |
| `Shift` + `=` (ou qualquer tecla que digite o caractere `+`) | Aproximar: o app trata o caractere digitado `+` como a tecla `+`. Do mesmo modo, qualquer tecla que digite `-` afasta. `(lido do código; não testado com outros layouts de teclado)` |
| `Shift` ou `Alt` a mais | Se nenhuma combinação exata casa, o `Shift` e o `Alt` que sobraram não contam: `Shift+R` também grava, como sempre foi. Exceção: `Q`, `K` e `J` do piano roll não valem com `Shift` (com `Shift+K` o piano roll não age e a tecla cai no `Aprender MIDI`, do arranjo). E `Espaço`, `Enter`, `Home`, `Delete`, `Backspace`, `Esc`, `=`, `+`, `-` e `?` valem também com `Ctrl`/`⌘` a mais. Uma combinação exata de outra ação sempre vence |

**Regras de prioridade (quando duas coisas usam a mesma tecla)**

- As teclas só valem com o foco no estúdio e **não** valem enquanto você digita num campo de texto.
- Com o **teclado do computador ligado**, as letras dele (`A W S E D F T G Y H U J K O L P`, mais `Z`, `X`, `C`, `V` nos atalhos padrão) viram nota, oitava e velocidade e passam à frente dos outros atalhos; a lista exata do que fica suspenso é o grupo acima (com os padrões: `C`, `L`, `S`, `X`, `Z`, `E`, `F`, e no piano roll `K`, `J` e `Shift+H`/`Shift+L`; se você personalizou, a lista muda junto). `R`, `I`, `M`, `Espaço`, `Enter`, `Home`, `Esc` e todos os atalhos com `Ctrl`/`⌘` continuam funcionando. Com `Ctrl`, `⌘` ou `Alt` apertados a letra deixa de ser nota. Na barra (e no painel do instrumento), o botão do teclado avisa o estado: fica com o rótulo `C4 · sem atalhos` (a oitava e o aviso) e o tooltip é montado das teclas de agora. Desligado: `Tocar com o teclado do computador (Ctrl+K)` (sem atalho na ação, sem o parêntese). Ligado, com os atalhos de fábrica: `Teclado tocando: atalhos suspensos (C E F J K L P S T X Z e Shift+H/K/L/Z). A a P tocam a partir do C4, Z/X mudam a oitava, C/V a intensidade (<n>%). O Shift não muda nada: Shift+L toca a nota L. Ctrl+K desliga` (sem atalho em `Teclado do computador liga/desliga`, o fim é `Desligue pelo botão`; ação de oitava ou velocidade sem tecla aparece como `—`). A lista entre parênteses é calculada, como a do grupo `Suspensos enquanto o teclado do computador está ligado` da janela `?`, e muda com a personalização (com os padrões: a do tooltip foi calculada a partir do código, não vista na tela `(testado só por testes automáticos)`).
- **A oitava do teclado é uma por tipo de faixa.** O botão mostra a oitava da faixa que ele toca (a selecionada, ou a primeira faixa de instrumento armada). Cada tipo (áudio, sintetizador, bateria, sampler, FM, wavetable) guarda a sua; todas partem de `C4` (a tecla `A` é o dó central, nota 60), menos a bateria, que parte de `C2` (a tecla `A` toca a nota 36, o `Bumbo`, porque a bateria só responde às notas 35 a 59). Mudar a oitava numa bateria não muda a do sintetizador, e vice-versa; ao trocar de faixa o botão passa a mostrar a oitava do tipo novo. A oitava vai de 0 a 8 e não é gravada no projeto (volta ao padrão ao reabrir o projeto).
- Os atalhos do **piano roll** só respondem depois que você clica dentro do editor (ele precisa ser o último lugar clicado); senão `Delete` e `Ctrl+D` continuam sendo do arranjo. `Shift+L` fora do editor faz o loop do clipe/seção; dentro dele, `Legato`.
- **Gravando**, `Ctrl+Z`, `Ctrl+Y` e `Ctrl+I` são engolidos (não fazem nada) para não apagar ou deslocar a faixa que está recebendo o áudio. `Ctrl+R` fica para o navegador.
- **Tooltips e menus usam o símbolo do sistema.** Os textos com tecla (`Desfazer (Ctrl+Z)`, `Refazer (Ctrl+Shift+Z)`, `Duplicar (Ctrl+D)`, `Importar áudio ou MIDI (Ctrl+I)`, o tooltip do teclado com `Ctrl+K`, o atalho do item `Duplicar` do menu do clipe) saem do catálogo e escrevem `Mod` como `⌘` no Mac e no iOS (`⌘+Z`) e como `Ctrl` nos outros; a ajuda do piano roll ainda passa por `withMod` (`app/lib/widgets/format.dart`), que troca o `Ctrl` do texto por `⌘`.
- **Tooltips e dicas acompanham a personalização** (desde a fase 18). As dicas saem do mesmo catálogo da janela `?` (`shortcutHint`/`shortcutLabel` em `keymap.dart`): o texto é o rótulo mais ` (<tecla de agora>)` (ação com mais de um atalho mostra todos separados por ` · `, como `Parar e voltar (Enter · Home)` e `Refazer (Ctrl+Shift+Z · Ctrl+Y)`), e uma ação sem nenhum atalho fica sem o parêntese. Valem para os tooltips da barra (`Parar e voltar`, `Tocar`/`Pausar`, `Gravar`, `Punch`, `Loop`, `Metrônomo`, `Desfazer`, `Refazer`, `Cortar no cursor`, `Duplicar`, `Mixer`, `Editor de notas`, `Instrumento da faixa`, `Efeitos da faixa`, `Importar áudio ou MIDI`, `Atalhos do teclado`), os das abas do painel de baixo e o `Fechar o painel`, o do botão do `Aprender MIDI`, o do armar da faixa (o `R` de gravar), o texto de apoio do metrônomo nas `Configurações`, os itens de menu (`Marcador no cursor`, `Loop no clipe selecionado`, `Enquadrar tudo`, `Enquadrar a seleção`, `Punch in/out`, o atalho à direita dos itens `Duplicar`, `Cortar no cursor`, `Apagar` e `Abrir no editor` do menu do clipe, e `Humanizar…`, `Legato`, `Dividir no cursor` e `Unir notas iguais adjacentes` no menu `Ferramentas` do piano roll) e o resumo `?` do piano roll. A tela do projeto se refaz quando você personaliza, então o texto muda na hora. `(testado só por testes automáticos; não visto na tela)`. **Ficam de fora, com a tecla escrita à mão:** o `(Q)` do tooltip do botão de quantizar do piano roll e o `(Ctrl+Z)` do texto da janela de edição de áudio `Dá para desfazer numa vez só (Ctrl+Z).`.

### Contextos e camadas

Cada ação do catálogo tem um **contexto**, que diz em que camada de teclas ela vale:

| Contexto | Onde vale | Camada | Ações |
|---|---|---|---|
| `Geral` | Em toda a tela do projeto | Camada do estúdio | 25 |
| `Arranjo` | Em toda a tela do projeto, mas a ação é sobre clipes (duplicar, cortar, apagar, loop e enquadrar o clipe) | A mesma camada do `Geral`: `Geral` e `Arranjo` **conflitam entre si** | 5 |
| `Piano roll` | Só com o editor ativo (o último lugar clicado) e sem digitar num campo | Camada própria, que vem **antes** da do estúdio | 20 |
| `Teclado tocando` | Só com o teclado do computador ligado; a tecla vale pela posição física | Camada própria, que vem antes de tudo | 4 |

O tratamento de uma tecla segue esta ordem: (1) teclado tocando, se ligado; (2) editor de notas, se ativo; (3) atalhos do estúdio. Por isso o mesmo `Ctrl+D` pode ser `Duplicar o clipe` (`Arranjo`) e `Duplicar as notas` (`Piano roll`): as camadas são separadas e **não há conflito** entre elas; o que decide é onde foi o último clique. Se o piano roll não usa a tecla naquele momento (setas sem nota selecionada, por exemplo), ela segue para a camada do estúdio.

### Personalizar os atalhos

Cada ação tem até 3 atalhos, e você pode trocar, acrescentar, tirar, restaurar, exportar e importar. Vale para a web, o computador e o app Android (o botão `Personalizar` está em todos; num celular ou tablet sem teclado físico visto, a tela avisa que é preciso um, ver [Web × Android](#web--android)). Não há personalização por projeto: os atalhos são do aparelho.

**Onde fica.** Abra a janela `Atalhos do teclado` (`?`, o botão `Atalhos do teclado` das `Configurações` ou o botão da barra, em janelas de 1640 px ou mais) e toque em `Personalizar` no rodapé. A janela passa a se chamar `Personalizar atalhos` e o botão vira `Voltar à lista`; `Fechar` continua ao lado. As personalizações valem na hora e ficam guardadas sem apertar nada.

**A tela.** De cima para baixo:

| Elemento (rótulo exato) | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| Texto de ajuda: `Clique num atalho para regravar. Esc cancela; Backspace ou Delete remove. Cada ação aceita até 3 atalhos.` | Resume os gestos | Fixo | |
| Aviso vermelho (`InlineNotice`) | Mostra o problema de guardado, se houver: `Não deu para ler seus atalhos guardados neste aparelho. O que você mudar agora vale só até fechar o app.`, `Seus atalhos foram guardados por uma versão mais nova do app. Aqui eles ficam só para leitura: o que você mudar vale só até fechar o app.`, `O arquivo dos seus atalhos estava ilegível. Guardei uma cópia dele (keymap.bak) e voltei aos atalhos padrão.`, `O arquivo dos seus atalhos está ilegível e não deu para guardar uma cópia dele. Nada será gravado por cima; o que você mudar vale só até fechar o app.` ou, se a gravação falhar, `Não deu para guardar seus atalhos neste aparelho. Eles valem só até fechar o app.` | Só aparece quando há problema | Veja [Armazenamento](#armazenamento-e-alcance) |
| Aviso de teclado físico (neutro, sem botão de dispensar) | Diz: `Regravar atalhos precisa de um teclado físico e nenhum foi detectado neste aparelho. Conecte um (USB ou Bluetooth) e aperte uma tecla; sem ele você só consegue ver a lista.` | Só aparece em Android ou iOS (inclusive no navegador do celular) enquanto nenhuma tecla de teclado físico foi apertada nesta sessão; some quando uma chega | Fica acima do resultado de exportar ou importar |
| Aviso do resultado de exportar ou importar | Mostra o que aconteceu (textos em [Exportar e importar](#exportar-e-importar-o-arquivo-jokeys)) | Com botão para dispensar; vermelho quando é erro. Depois de uma importação que deu certo ganha o botão `Desfazer importação` | O botão vale enquanto você não mudar nenhum atalho e a tela ficar aberta |
| Campo `Buscar ação ou tecla` (lupa) | Filtra a lista enquanto você digita; botão `Limpar a busca` (tooltip) aparece com texto | Ignora maiúsculas e acentos; várias palavras: a ação tem de casar com todas | Casa o rótulo, o título do grupo, o contexto e as teclas de agora (`ctrl`, `piano`, `arranjo`, `mixer`…) |
| `Restaurar tudo` | Descarta todas as personalizações (pede confirmação) | Desligado (cinza) enquanto nada foi personalizado | |
| `Exportar atalhos…` | Salva um arquivo `atalhos.jokeys` | Sempre ligado | |
| `Importar atalhos…` | Lê um `.jokeys`, mostra o que ele traria e, se você confirmar, **substitui** as personalizações de agora | Sempre ligado | Pede confirmação (`Importar atalhos?`) e dá para desfazer logo depois; ver [Exportar e importar](#exportar-e-importar-o-arquivo-jokeys) |
| Título de grupo (`TRANSPORTE`, `MARCADORES E LOOP`…) | Agrupa as ações na ordem do catálogo | Só aparece o grupo que tem ação encontrada | |
| Rótulo da ação, com o contexto embaixo em cinza (`Geral`, `Arranjo`, `Piano roll`, `Teclado tocando`) | Nome da ação | | |
| "Chip" de atalho (a tecla, por exemplo `Ctrl+Z`) | Toque para **regravar** esse atalho | Cada atalho da ação é um chip; com a tela abaixo de 460 px de largura os chips ficam embaixo do nome | Ação sem tecla mostra o chip `Sem atalho` (em itálico), que também é clicável |
| `+` ao lado dos chips (tooltip `Adicionar outro atalho`) | Acrescenta um atalho à ação | Só aparece com pelo menos 1 e menos de 3 atalhos | |
| Cadeado (tooltip `Tecla fixa: não pode ser mudada`) | Marca as ações fixas: `Fechar o painel`, `Cancelar o controle armado` e `Limpar a seleção` (as três são `Esc`) | Os chips delas não são clicáveis | |
| Botão de seta circular (tooltip `Restaurar o padrão desta ação`) | Volta só aquela ação aos atalhos padrão | Só aparece nas ações personalizadas; sem confirmação | |

**Passo a passo**

*Trocar uma tecla*

1. Em `Personalizar`, ache a ação (role, ou digite no campo `Buscar ação ou tecla`, por exemplo `mixer`).
2. Toque no chip da tecla: o texto dele vira `Pressione a nova combinação…` e ele ganha o destaque na cor do app (turquesa).
3. Aperte a nova combinação (tecla com `Ctrl`/`⌘`, `Shift` e `Alt` como quiser). Teclas de modificador sozinhas são ignoradas: a tela espera uma tecla de verdade.
4. Se a combinação está livre, o chip mostra a nova tecla e o app guarda. Se não vale, aparece uma linha vermelha embaixo da ação com o motivo ([teclas reservadas](#teclas-reservadas)) e a tela continua esperando outra tecla. Se já é de outra ação, abre o aviso de conflito (abaixo).
5. `Esc` cancela e deixa o atalho como estava.

*Acrescentar um segundo ou terceiro atalho:* toque no `+` (tooltip `Adicionar outro atalho`) e aperte a combinação. Numa ação sem nenhum atalho, toque no chip `Sem atalho`.

*Tirar um atalho:* toque no chip e aperte `Backspace` ou `Delete` (sem `Ctrl`, `Shift` nem `Alt`). A ação pode ficar sem atalho nenhum: fica `Sem atalho` (na janela `?` aparece `—`). Sobre um chip novo (o do `+`) essas teclas só cancelam.

*Resolver um conflito:* se a combinação já pertence a outra ação da mesma camada, aparece uma caixa vermelha embaixo da ação: `<tecla> já é de "<outra ação>" (<contexto da outra>). Trocar? …` e o fim da frase depende do caso: `"<outra ação>" passa a usar <a tecla que este chip tinha>.` (a outra ação **recebe o atalho que você está substituindo**) ou, quando o chip era novo, `"<outra ação>" fica sem esse atalho.` Dois botões: `Trocar` aplica; `Cancelar` deixa tudo como estava (`Esc` também cancela). Enquanto a caixa está aberta as outras teclas são ignoradas.

*Restaurar:* o botão de seta circular da ação (`Restaurar o padrão desta ação`) volta só aquela. Se o padrão dela foi tomado por outra ação, o padrão volta e **a outra perde essa tecla**. `Restaurar tudo` abre a confirmação `Restaurar todos os atalhos?` (`Todas as suas personalizações serão descartadas e os atalhos padrão voltam.`) com `Cancelar` e `Restaurar tudo`.

*Buscar:* digite no campo. `Nenhuma ação encontrada para "<texto>".` aparece quando nada casa.

*Levar para outro aparelho:* `Exportar atalhos…` num, `Importar atalhos…` no outro.

**Regras**

- **Até 3 atalhos por ação** (`maxBindingsPerAction`). Com 3, o `+` some; para trocar um deles, toque no chip.
- **Regravar com a mesma tecla que a ação já tem** não muda nada (a tela só sai do modo de gravação).
- **Ações fixas** (as três `Esc`) não mudam nem entram em conflito: `Esc` continua fechando o painel, cancelando o controle armado e limpando a seleção.
- **Teclado tocando:** ali a tecla vale **pela posição** (como as notas) e vale **sozinha**, sem `Ctrl`, `Shift` nem `Alt`. As 16 teclas de nota não se personalizam e são recusadas. O arquivo `.jokeys` e os chips da tela `Personalizar` guardam e mostram a tecla pela posição do QWERTY (`B`); a janela `?` e o tooltip do botão do teclado mostram a letra que está de fato naquela tecla no seu layout (`N (posição do B)`), aprendida quando você aperta teclas (antes da primeira tecla aparece a letra do QWERTY).

#### Teclas reservadas

Estas combinações **não podem** ser atribuídas (`reservedReason`); a tela mostra o texto em vermelho e continua esperando. Vale o mesmo no arquivo importado (a combinação é descartada com aviso).

| Combinação | Mensagem exata | Por quê |
|---|---|---|
| `Esc` | `Esc é reservado: cancela e fecha painéis.` | Tecla de cancelar do app |
| `Tab` | `Tab é reservado para a navegação por foco.` | Foco |
| `F5`, `F11`, `F12` (com qualquer modificador) | `<tecla> é do navegador (recarregar, tela cheia, ferramentas) e o app não consegue capturá-la.` | Navegador |
| `Alt+F4` (com ou sem outras) | `Alt+F4 fecha a janela: o sistema não deixa o app usá-lo.` | Sistema |
| `Ctrl`/`⌘` + `R`, `W`, `T`, `N` ou `Q` (com ou sem `Shift`; sem `Alt`) | `<combinação> é do navegador ou do sistema (recarregar, fechar, nova aba ou janela, sair) e o app não consegue capturá-la.` | Navegador e sistema |
| `Ctrl`/`⌘` + `1` a `9` | `<combinação> troca de aba no navegador.` | Navegador |
| No `Teclado tocando`: qualquer modificador | `No teclado tocando a tecla vale sozinha, sem Ctrl, Shift nem Alt.` | Posição física |
| No `Teclado tocando`: tecla que não é letra nem dígito | `O teclado tocando só usa letras e dígitos.` (na tela, uma tecla que não tem posição de letra ou dígito mostra antes `Essa tecla não pode ser usada em atalhos. Tente outra.`) | |
| No `Teclado tocando`: letra de nota | `<letra> já toca uma nota no teclado do computador.` | As 16 notas |

Também é recusada, na tela, a tecla que o app não conhece: `Essa tecla não pode ser usada em atalhos. Tente outra.` As teclas conhecidas são letras `A` a `Z`, dígitos `0` a `9`, `Espaço`, `Enter`, `Home`, `End`, `PageUp`, `PageDown`, `Delete`, `Backspace`, `Esc`, `Tab`, as quatro setas, `F1` a `F12`, `[`, `]`, `=`, `-`, `+`, `?`, `/`, `,`, `.`, `;`, `'`, `\` e a crase (`` ` ``).

`Ctrl`/`⌘`: as duas teclas valem como a mesma coisa, em qualquer sistema (`Mod` no arquivo).

#### Exportar e importar o arquivo `.jokeys`

- **`Exportar atalhos…`:** gera `atalhos.jokeys` (JSON em UTF-8, tipo `application/octet-stream`) só com o que **difere dos padrões**. Na web é um download direto do navegador (que não avisa se você o cancelar). Resultados: `Atalhos exportados em atalhos.jokeys.`; onde o sistema informa o cancelamento da janela de salvar, `Exportação cancelada: nada foi salvo.`; se falhar, `Não foi possível exportar: <motivo>`.
- **`Importar atalhos…`:** abre o seletor de arquivos (título `Importar atalhos`; aceita `.jokeys` e `.json`). O arquivo é lido e validado **antes** de mudar qualquer coisa; se ele é aceito, abre a confirmação `Importar atalhos?` com o texto `<arquivo>: N atalhos serão trocados. <agora> Dá para desfazer logo depois, nesta sessão.` (`1 atalho será trocado` com um só; `<agora>` é `Você não tem personalizações agora.` ou `As suas N personalizações atuais serão descartadas.`, com `As suas 1 personalização atual serão descartadas.` no singular; quando o arquivo traz o que será descartado, acrescenta `N avisos (o que não vale no arquivo é descartado).` ou `1 aviso ...`). O `N` é o número de **ações** que o arquivo personaliza. Botões `Cancelar` (nada muda) e `Importar`. Confirmado, **substitui todas as personalizações de agora** pelas do arquivo e grava. Resultados: `Atalhos importados de <arquivo>.` ou, quando algo foi ignorado, `Atalhos importados de <arquivo>, com avisos:` seguido de uma linha `•` por aviso; o aviso ganha o botão `Desfazer importação`, que devolve as personalizações de antes e mostra `Importação desfeita: seus atalhos de antes voltaram.`. O desfazer vale **só nesta sessão e só até você mudar outro atalho** (qualquer troca, restauro ou nova importação descarta o instantâneo) e só enquanto o aviso estiver na tela: fechar a tela `Personalizar` perde o botão. `Restaurar tudo` volta aos padrões, não ao estado anterior à importação. Arquivo recusado (lista abaixo) não pede confirmação nem muda nada. `(testado só por testes automáticos)`
- **`Shift+/` num arquivo.** O teclado entrega `Shift+/` como o caractere `?` (o atalho `?` da janela de atalhos), então a forma escrita `Shift+/` vale como `?` (também com `Mod`: `Mod+Shift+/` vira `Mod+?`). O arquivo importa com o aviso `"<texto>" em "<ação>" vale como ?, que é o que o teclado envia.` e a tecla passa a disparar a ação.
- **Formato:** um objeto com `format` = `jopendaw-keymap-file`, `version` = `1` e `bindings`, que mapeia o id da ação para a lista de teclas em texto (`Mod+Shift+Z`, `Space`, `[`…). Exemplo:

```json
{
  "format": "jopendaw-keymap-file",
  "version": 1,
  "bindings": {
    "panel.mixer": ["B"],
    "edit.redo": ["Mod+Shift+Z"],
    "view.follow": ["Shift+F"],
    "transport.metronome": []
  }
}
```

Uma lista vazia (`"transport.metronome": []`) quer dizer "sem atalho". Ação que não aparece em `bindings` fica com os padrões. Modificadores: `Mod` (Ctrl ou ⌘), `Shift` e `Alt`, antes da tecla e com `+` entre eles; as teclas escritas como na lista acima (`Space`, `Enter`, `Up`, `Down`, `Left`, `Right`, `Escape`, `F1`…). Maiúsculas e minúsculas importam (`ctrl+z` e `z` são inválidos). Campo a campo e tratamento de erros: [dev/10 App Flutter](../dev/10-app-flutter.md#atalhos-personalizáveis-keymapdart-keymap_uidart).
- **O que acontece com o que o arquivo traz de errado** (o resto é aproveitado, cada item vira uma linha `•` de aviso):

| Problema no arquivo | O que o app faz | Aviso (exato) |
|---|---|---|
| Ação que este app não conhece (por exemplo, de uma versão mais nova) | Ignora a ação | `Ação desconhecida "<id>" ignorada.` |
| Ação de tecla fixa (`Esc`) | Ignora | `"<ação>" tem tecla fixa e não muda; ignorada.` |
| Valor que não é lista | Ignora aquela ação | `Os atalhos de "<ação>" não são uma lista; ignorados.` |
| Tecla que não existe ou está mal escrita | Descarta a tecla | `Tecla inválida "<texto>" em "<ação>" descartada.` |
| Tecla reservada | Descarta a tecla | `<tecla> em "<ação>" descartada: <mensagem da tabela de reservadas>` |
| Mais de 3 teclas numa ação | Guarda as 3 primeiras, descarta o resto | `"<ação>" aceita até 3 atalhos; <tecla> descartado.` |
| Mesma tecla repetida na lista da ação | Guarda uma vez | Sem aviso |
| Tecla que outra ação importada (da mesma camada) já ficou | Vale a primeira do catálogo; a outra perde a tecla | `<tecla> já é de "<ação>"; descartada em "<outra>".` |
| Tecla que é padrão de uma ação **não** citada no arquivo | O arquivo vence: a ação não citada perde a tecla padrão | `"<ação>" perdeu <tecla>, que agora é de "<outra>".` |

**O arquivo inteiro é recusado** (nada muda; a mensagem vem depois de `Não foi possível importar: `) quando:

| Situação | Mensagem |
|---|---|
| Mais de 256 KB | `O arquivo é grande demais para ser de atalhos.` |
| Não é JSON (ou não é UTF-8) | `O arquivo não é de atalhos do jopendaw (não é um JSON válido).` |
| `format` diferente de `jopendaw-keymap-file` | `O arquivo não é de atalhos do jopendaw.` |
| `version` que não é inteiro `>= 1` | `O arquivo tem uma versão de formato inválida.` |
| `version` maior que 1 | `Os atalhos são de uma versão mais nova do jopendaw. Atualize o app para importá-los.` |
| `bindings` ausente ou não é objeto | `O arquivo não tem a lista de atalhos.` |

#### Armazenamento e alcance

- **Chave `keymap`** do guardado local do aparelho, um JSON só com o que difere dos padrões (`format` = `jopendaw-keymap`, `version` = 1, `bindings`). Na **web** é o IndexedDB do navegador (banco `jopendaw`, repositório `kv`), por site e perfil do navegador; no **Android**, o arquivo `keymap.txt` na pasta `jopendaw/` do app (o botão `Personalizar` existe lá, então o arquivo é gravado quando você personaliza); em **outros sistemas** nada é guardado e o que você mudar vale só até fechar o app. `(lido do código)`
- **É do aparelho e do navegador**, não do projeto nem da conta: não sobe para a nuvem, não vai no arquivo `.jopendaw` nem na sincronização. Para levar para outro aparelho, use `Exportar atalhos…` e `Importar atalhos…`.
- **Arquivo local ilegível:** o app guarda uma cópia (chave `keymap.bak`; no Android, o arquivo `keymap%2Ebak.txt`), volta aos atalhos padrão e avisa. Se já existia uma cópia diferente, a nova vai para `keymap.bak.<milissegundos>`. Nada no app lê a cópia de volta. **Arquivo de uma versão mais nova do app:** as personalizações legíveis entram, mas o guardado fica só para leitura (o que você mudar vale só até fechar o app). Se a leitura ou a gravação falha, o app segue com os atalhos na memória e mostra o aviso.
- Ao abrir a tela do projeto o app carrega os atalhos guardados (antes disso valem os padrões, por instantes). Se você mudar um atalho antes de o carregamento acabar, **a sessão vence**: o guardado entra por baixo, e uma combinação guardada que a ação que você mudou agora já usa na mesma camada é descartada, com o aviso (o mesmo vermelho da tela `Personalizar`) `Um atalho guardado foi descartado porque você já o usou em outra ação nesta sessão, antes de o carregamento terminar.` (`N atalhos guardados foram descartados porque ...` no plural). A gravação só começa depois do carregamento, então o que estava guardado não é sobrescrito antes de ser lido. `(testado só por testes automáticos)`

#### O que não muda de tecla

- As **16 teclas de nota** (`A W S E D F T G Y H U J K O L P`).
- `Esc` (três ações fixas).
- O que não é do catálogo: as teclas da **raia de automação** (`Delete`, `Ctrl+A`, `Esc` depois de clicar nela), as do editor de zonas do sampler, os gestos de mouse (`Alt` ao arrastar, `Shift` e `Ctrl` com a roda…) e os menus. `(lido do código: só essas 54 ações consultam o catálogo)`

#### Web × Android

| | Web e computador | App Android |
|---|---|---|
| Botão `Personalizar` | Aparece | Aparece (desde a fase 18 o app deixou de decidir pela plataforma: quem tem teclado físico por Bluetooth ou USB personaliza) |
| Aviso de teclado físico | Não aparece | Aparece na tela `Personalizar` até uma tecla de teclado físico ser apertada (`Regravar atalhos precisa de um teclado físico e nenhum foi detectado neste aparelho. ...`) |
| Janela `?` | Lista gerada do catálogo | A mesma lista |
| Guardado | IndexedDB do navegador | Arquivo `keymap.txt` |

No **navegador do celular** (web) vale o mesmo do Android: o botão `Personalizar` aparece e o aviso de teclado físico também, pois o teste é pela plataforma do aparelho (Android ou iOS), não pela web. `(testado só por testes automáticos; não visto num aparelho)`

### Permissões

| Permissão | Quando o app pede | Se você negar | Como liberar de novo |
|---|---|---|---|
| Microfone (web) | Ao abrir `Configurações`, ao armar uma faixa de áudio, ao ligar `Monitorar a entrada` ou ao gravar pela primeira vez | Mensagem: `O navegador negou o acesso ao microfone. Libere o microfone nas permissões do site e tente de novo.` A faixa que pediu volta a ficar desarmada | Cadeado ao lado do endereço, permissões do site, microfone |
| Microfone (Android) | Na mesma hora do uso (não ao abrir o app) | Negado uma vez: `O Android negou o acesso ao microfone. Permita o microfone para o jopendaw e tente de novo.` Negado de vez ou restrito: `O Android negou o acesso ao microfone de vez: libere o microfone nas permissões do jopendaw (Configurações › Apps › jopendaw › Permissões) e tente de novo.` | Ajustes do Android, Apps, jopendaw, Permissões |
| MIDI (web) | Ao clicar no botão de cabo (tooltip `Entrada MIDI: ligar teclado ou controlador`) | `O navegador negou o acesso ao MIDI. Libere o MIDI nas permissões do site e tente de novo.` Sem suporte: `Este navegador não dá acesso a MIDI. Use o Chrome ou o Edge, com o jopendaw aberto em https.` | Permissões do site |
| MIDI (Android) | Ao clicar no mesmo botão | Sem MIDI no aparelho: `Este aparelho não dá acesso a MIDI.` Outra falha: `Não deu para abrir o MIDI: <motivo>.` | |

Outros avisos de entrada de áudio (web):

| Mensagem | Causa |
|---|---|
| `Este navegador não dá acesso ao microfone. Use um navegador atual, com o jopendaw aberto em https.` | Navegador sem suporte, ou página sem `https` |
| `Nenhuma entrada de áudio encontrada. Conecte um microfone ou uma interface de áudio e tente de novo.` | Nenhum microfone |
| `A entrada de áudio escolhida não está mais conectada. Escolha outra ou volte para a padrão.` | Aparelho sumiu |
| `A entrada de áudio está ocupada por outro programa ou não respondeu. Feche o que estiver usando ela e tente de novo.` | Outro programa usa o microfone |
| `A entrada de áudio está em <N> Hz e o motor em <M> Hz, e este navegador não converte. Ajuste a entrada para <M> Hz nas configurações de som do sistema.` | Taxas diferentes de entrada e saída |
| `A abertura da entrada de áudio foi cancelada.` | Fechada durante a abertura |

Depois de conectado, o botão de cabo mostra quantos aparelhos MIDI há (`0` ligado sem aparelho). Aparelhos plugados depois entram sozinhos na contagem.

## Web e Android

O app é o mesmo; o motor de áudio e o acesso ao aparelho é que mudam.

| Aspecto | Web (navegador) | Android (app) |
|---|---|---|
| Motor de áudio | Rust compilado para WebAssembly, dentro de um AudioWorklet | O mesmo Rust como biblioteca nativa (`libjopendaw_engine.so`), tocando pela saída do Android (AAudio) |
| Onde ficam o documento e os áudios | IndexedDB do navegador (banco `jopendaw`, repositório `kv`), por site e perfil | Arquivos na pasta de documentos privada do app, subpasta `jopendaw/` (documento, estado de sincronização, áudios, e as versões nomeadas do projeto, chaves `snapshots:<projeto>:<id>`: [02d](02d-historico-e-versoes.md)) |
| Onde ficam os tokens de sessão | Armazenamento local cifrado do navegador | Armazenamento seguro do Android (Keystore) |
| Entrar com Google/Discord | A página vai ao provedor e volta ao jopendaw | Uma aba do Chrome sobre o app; o Discord, com o app dele instalado, autoriza dentro dele |
| Link do email de entrada | Abre no navegador | Abre o app, se o Android confirmou o vínculo com o domínio; senão, o navegador |
| Microfone | Pedido do navegador, por site | Pedido do Android na hora de usar (`RECORD_AUDIO`) |
| MIDI | Web MIDI (Chrome e Edge) | USB e aparelhos que o Android já conhece (`android.media.midi`); conecta em todas as entradas, ignora aparelhos que só recebem |
| Exportar e salvar arquivos | Download do navegador | Janela de salvar do Android (`Salvar <nome>`); sem ela, a folha de compartilhar. Vale também para o `.flac` e o `.mp3`: o app baixa o arquivo convertido do servidor e o entrega pelo mesmo caminho do WAV (ver [Exportação](08-exportacao.md#flac-e-mp3-pelo-servidor)) |
| Importar áudio ou MIDI (`.mid`) | Seletor de arquivos do navegador | Seletor de arquivos do Android |
| Exportar notas em MIDI (`.mid`) | Download do navegador | Janela `Salvar <nome>` do Android (ou o compartilhar do sistema, se a janela não estiver disponível) |
| Menu do botão direito | Usado pelo app nos clipes (o do navegador é desligado no projeto) | Não há botão direito; o toque longo faz o papel (não confirmado) |
| Teclado | Todos os atalhos, e o botão `Personalizar` na janela `?` | Só com teclado físico (não confirmado); o botão `Personalizar` também aparece, com um aviso se nenhuma tecla de teclado físico foi vista (ver [Personalizar os atalhos](#personalizar-os-atalhos)) |
| Instalar como app | Navegadores que oferecem instalar sites (o site tem manifesto `standalone` e abre a casca sem rede) | App do Android |
| Exigências | Navegador atual, `https` para gravar | Android 8.0 (API 26) ou mais novo; ABIs `arm64-v8a`, `armeabi-v7a` e `x86_64` |
| Ajustar áudio ao andamento (warp) | Progresso durante o processamento | Só avisa o fim (sem barra de progresso) |
| Tela enquanto toca ou grava | A aba do navegador cuida sozinha (o app não faz nada) | O app mantém a tela acesa enquanto o transporte toca ou grava e solta ao parar (ver "O aparelho no Android") |
| O app sai da tela | A aba segue tocando em segundo plano, como qualquer player do navegador | Para o transporte (gravando, encerra a gravação, que fica salva), solta as notas ao vivo e fecha a entrada de áudio |
| O fone sai | O app não faz nada (o navegador decide) | Para o transporte, sem voltar o cursor |
| Falha do motor | Aviso na tela do projeto com o botão `Reiniciar o áudio` | O mesmo aviso e o mesmo botão |
| Palavras das mensagens | `este navegador`, `O navegador negou...` | `este aparelho`, `O Android negou...` |

**O que só existe num dos lados**

- Só no Android: a permissão `RECORD_AUDIO` em tempo de execução, a folha de compartilhar como plano B ao exportar e a autorização pelo app do Discord.
- Só na web: a instalação como app pelo navegador e a casca do app offline (`sw.js`).
- Em qualquer outro sistema (um build de computador nativo, testes) não há motor: a tela do projeto avisa `O motor de áudio não roda neste sistema: use o jopendaw no navegador ou no Android.` (o mesmo texto de "não roda neste sistema" vale para a gravação, a exportação, o warp e o MIDI, cada um com o seu verbo).

### O aparelho no Android

Só no app do Android o estúdio conversa com o aparelho por um canal próprio (`app/lib/platform/platform_native.dart` e `MainActivity.kt`). Tudo abaixo vale só enquanto a tela do projeto está aberta e foi coberto por testes automáticos com o canal simulado (`app/test/android_session_test.dart`); **não foi visto num aparelho nem no emulador** `(testado só por testes automáticos)`.

| Situação | O que o app faz |
|---|---|
| O transporte começa a tocar ou a gravação começa | Liga o sinal de manter a tela acesa (`FLAG_KEEP_SCREEN_ON`). Repetir o mesmo estado não repete o pedido ao Android. |
| O transporte para, ou você fecha a tela do projeto | Solta a tela: ela volta a apagar pelo tempo normal do aparelho. |
| O app sai da tela (outro app na frente, botão de início, tela desligada) | Para o transporte sem voltar o cursor; se estava gravando, encerra a gravação e ela fica salva (como no `stop`); solta as notas tocadas ao vivo; fecha a entrada de áudio (o aviso de privacidade do microfone apaga). Se estava gravando, a entrada **só fecha depois** de o fim da gravação terminar de ser recolhido (senão a cauda da tomada seria cortada); se você voltar ao app antes disso, ela nem chega a fechar. Um diálogo por cima, a cortina de notificações ou a tela dividida **não** contam como sair. |
| O app volta à tela | Pede ao motor que garanta a saída tocando (o motor só reabre a saída se o Android a derrubou; se ela está tocando, nada muda) e reabre a entrada de áudio se alguma faixa de áudio ficou armada ou monitorando. Com o motor caído (o aviso `Reiniciar o áudio` na tela), não mexe no motor: quem o recria é o botão do aviso. |
| O fone (com fio ou Bluetooth) sai | Para o transporte, como todo app de mídia, sem voltar o cursor, e solta as notas ao vivo; gravando, encerra a gravação. Sem nada tocando, não faz nada. |
| Um aparelho de áudio entra ou sai (fone plugado, interface USB) | Não pausa; pede ao motor que garanta a saída (reabre se a rota mudou e a saída caiu) e **relê a lista de entradas** do seletor de `Configurações`, sem abrir o microfone (ele só abre para armar, monitorar ou gravar). Se a entrada escolhida tinha sumido, o seletor volta para `Padrão do sistema` e aparece o aviso `A entrada de áudio escolhida foi desconectada: usando a entrada padrão.` Lista vazia não conta como entrada que sumiu (é falta de permissão). |

Os dois avisos (fone que sai; aparelho que entra ou sai) só são escutados enquanto o app está à mostra. O de aparelho compara a lista de aparelhos de áudio com a da última vez e só avisa quando ela mudou, inclusive de algo plugado enquanto o app estava fora.

No Android o pedido "garanta a saída" (`AudioEngine.resume()`) chama o `jd_start` do motor nativo, que só reabre a saída de áudio quando o sistema a derrubou ou a rota trocou (com a saída tocando, não faz nada). É o caminho imediato: o supervisor do motor (`jopendaw-sup`, verifica a cada 250 ms) faz o mesmo sozinho e continua como rede de segurança. Se a reabertura falhar, o app só registra no console de depuração e o supervisor tenta de novo. `(testado só por testes automáticos)`

## Instalação do app Android

**Requisitos:** Android 8.0 (API 26) ou mais novo, em aparelho `arm64-v8a`, `armeabi-v7a` ou `x86_64`. Pacote: `tech.johnenrique.jopendaw`. O app precisa de internet (só HTTPS) e pede o microfone só quando você usa a gravação. Bluetooth e USB MIDI são usados quando existem, nunca exigidos.

**Instalar**

1. Baixe o app. O repositório não fixa um canal de distribuição (há uma conta de demonstração pensada para a revisão da Play Store, então a publicação lá é prevista, mas não confirmada). Sem loja, use o arquivo `.apk`.
2. Para instalar um `.apk` fora da loja, o Android pede para permitir "instalar apps desconhecidos" para o app que o abriu (navegador ou gerenciador de arquivos). Permita, abra o arquivo e toque em `Instalar`. Com o cabo e o `adb`: `adb install -r app-release.apk`.
3. Abra o jopendaw e entre (link no email, Google, Discord ou código de acesso). Ele fala por padrão com o servidor de produção (`https://jopendaw.johnenrique.tech`).
4. Abra ou crie um projeto. Na primeira gravação, o Android pede o microfone.

**Para quem compila:** `cd app && flutter build apk --release -PdiscordClientId=<id>` (o `<id>` é o id do app do Discord, o mesmo `DISCORD_CLIENT_ID` do servidor; sem ele o valor é `0` e a volta da autorização pelo app do Discord não funciona). O `.apk` sai no caminho padrão do Flutter, `app/build/app/outputs/flutter-apk/app-release.apk` (não confirmado). A chave de assinatura de release fica fora do repositório (`android/key.properties` ou `~/.config/jopendaw/android-release.properties`); sem ela o release sai com a chave de debug, que instala e roda, mas não abre os links do email dentro do app. Se mudar o motor de áudio, recompile os `.so` antes (`./engine/build-android.sh`); o passo a passo técnico está em [dev/03](../dev/03-build-teste-e-depuracao.md).

## Passo a passo

**Gravar com o microfone certo**

1. Abra `Configurações` (engrenagem da barra). Permita o microfone quando o navegador ou o Android pedir.
2. No seletor de entrada, escolha o microfone ou a interface. Se acabou de plugar, toque no botão de atualizar.
3. Fale ou toque e veja a barra `Nível` andar; ajuste o ganho no próprio aparelho até ela subir sem passar do fim.
4. Toque em `Fechar`.

**Calibrar a latência da gravação**

1. Ligue o metrônomo (`C`) e arme uma faixa de áudio; ponha o microfone perto do alto-falante ou use um cabo de retorno.
2. Grave alguns compassos só com o clique.
3. Olhe onde a batida gravada caiu em relação à grade. Em `Configurações`, mova `Compensação de latência` (positivo adianta o gravado, negativo atrasa) e grave de novo.
4. Repita até a batida gravada cair na grade. O valor fica no projeto.

**Escolher pré-roll e punch**

1. Abra `Configurações` (engrenagem da barra) e, em `GRAVAÇÃO`, toque numa ficha de `Pré-roll` (`Não`, `1` a `4`).
2. Ligue `Punch in/out`: a legenda passa a `Da posição … à …: só isso é gravado`. Ajuste as pontas vermelhas `IN` e `OUT` na régua, ou ligue o loop (`L`) sobre o trecho e toque em `Usar a região do loop` (o botão só funciona com o loop ligado). Sem loop, a gravação para sozinha no punch out.
3. Feche em `Fechar` e grave com `R` ([capítulo 03c](03c-gravacao.md#punch-pré-roll-e-metrônomo-fase-17)).

**Trocar o timbre do metrônomo e ouvir as subdivisões**

1. Em `Configurações`, na seção `METRÔNOMO`, escolha `Timbre` (`Madeira`, por exemplo) e `Subdivisão` (`Colcheias`).
2. Ligue o metrônomo (`C`) e toque: o clique de cada tempo ganha um meio-tempo mais baixo. Ajuste `Volume das subdivisões` (que apareceu com a subdivisão) até ele ficar de fundo.
3. Para o clique só valer gravando, ponha `Quando soa` em `Só ao gravar`.

**Ligar ou desligar a contagem**

1. Abra a seta ao lado do botão de gravar (`Opções de gravação`).
2. Marque ou desmarque `Contagem de um compasso`. O mesmo interruptor existe em `Configurações`.

**Ligar um teclado MIDI**

1. Conecte o teclado (USB, ou Bluetooth já pareado no Android).
2. Toque no botão de cabo da barra. Permita o MIDI se o navegador perguntar.
3. Confira o número ao lado do cabo (`1` para um aparelho) e toque na faixa de instrumento: as notas tocam a faixa selecionada, ou a armada.

**Consultar os atalhos**

1. Aperte `?`, ou abra `Configurações` (engrenagem) e toque em `Atalhos do teclado`; o botão de atalhos da barra só existe em janelas de 1640 px ou mais.
2. Role a lista, e feche em `Fechar`.

**Personalizar um atalho (precisa de teclado físico)**

1. Aperte `?` e toque em `Personalizar`.
2. Digite parte do nome da ação em `Buscar ação ou tecla` (por exemplo `metr`) e toque no chip da tecla dela (`C`).
3. Quando o chip mostrar `Pressione a nova combinação…`, aperte a nova tecla (por exemplo `B`). Se a tecla for de outra ação, escolha `Trocar` ou `Cancelar`; se for reservada, a linha vermelha explica e você aperta outra.
4. `Voltar à lista` mostra a janela `?` já com a tecla nova; `Fechar` sai. Para desfazer, o botão de seta circular da ação (`Restaurar o padrão desta ação`) ou `Restaurar tudo`.
5. Para guardar uma cópia ou levar para outro aparelho: `Exportar atalhos…` (arquivo `atalhos.jokeys`) e, no outro, `Importar atalhos…` (confirme em `Importar`; se não era isso, `Desfazer importação` no aviso que aparece).

## Combina com

- [00 Visão geral](00-visao-geral.md): onde fica cada botão citado aqui.
- [03c Gravação](03c-gravacao.md): usar a entrada, a contagem e a latência numa tomada de verdade.
- [02 Transporte](02-transporte.md): metrônomo, loop e o menu `Opções de gravação`.
- [05 Piano roll](05-piano-roll.md) e [05b Ferramentas MIDI](05b-ferramentas-midi.md): os atalhos do grupo `Piano roll` (todos personalizáveis, menos o `Esc`).
- [Atalhos e fluxo rápido](../guias/atalhos-e-fluxo-rapido.md): sequências de teclas prontas e, no fim, como adaptá-las depois de personalizar.
- [01b Nuvem e sincronização](01b-nuvem-e-sincronizacao.md): o que sobe e o que fica só no aparelho.
- [08 Exportação](08-exportacao.md): salvar arquivos na web e no Android.
- [06f MIDI learn](06f-midi-learn.md): o grupo `Aprender MIDI` da janela de atalhos e o `Shift+K`.
- [02d Histórico e versões](02d-historico-e-versoes.md): a ação `Abrir o histórico` (`Ctrl+Shift+H`) e as versões nomeadas guardadas no aparelho.

## Limites e pegadinhas

- **As mensagens falam do lugar onde você está.** No Android os textos dizem `este aparelho` e `O Android negou o acesso ao microfone` onde a web diz `este navegador` e `O navegador negou o acesso ao microfone` (a janela `Configurações` e os erros de importar áudio, ligar o MIDI e abrir a entrada).
- **A entrada de áudio é do aparelho; a latência, a contagem, o pré-roll, o punch e as opções do metrônomo são do projeto** (mas cada aparelho mantém os seus ao receber uma versão da nuvem). Se você calibrar a latência num aparelho e abrir o projeto em outro, a versão da nuvem não troca o valor de cada aparelho, então calibre em cada um.
- **A latência está limitada a −200 a 500 ms.** O valor é guardado no projeto e entra na sincronização, mas não no desfazer.
- **Trocar a entrada no meio da gravação não é permitido:** o seletor fica desligado e o texto pede `Pare a gravação para trocar de entrada.`
- **Um atalho que "não pega"** costuma ser: campo de texto com foco, teclado do computador ligado (as letras viram notas; o botão da barra mostra `C4 · sem atalhos` e a janela de atalhos tem um grupo que lista o que ficou suspenso), o piano roll sem ter sido o último lugar clicado, ou **você personalizou aquela ação** (abra `?`: a janela mostra a tecla de agora, e os tooltips também).
- **Personalizar muda os tooltips, com duas exceções.** `Loop (L)`, `Mixer (X)`, `Humanizar…` e os demais textos com tecla mostram a tecla de agora (ação sem atalho fica sem parêntese). Ficam com a tecla escrita à mão o `(Q)` do tooltip de quantizar do piano roll e o `(Ctrl+Z)` do texto da janela de edição de áudio; a fonte confiável continua a janela `?`.
- **Importar pede confirmação e tem desfazer curto.** `Importar atalhos…` mostra quantos atalhos entram e quantas personalizações saem, e só troca depois do `Importar`; o botão `Desfazer importação` do aviso devolve o que havia, mas só até você mudar outro atalho ou fechar a tela. Exporte antes se quiser uma cópia duradoura.
- **`Shift+/` num arquivo de atalhos vale como `?`**, com um aviso, porque o teclado entrega o `Shift+/` como o caractere `?`.
- **No teclado tocando o `Shift` não conta.** `Shift+L` toca a nota `L`; os atalhos com `Shift` nas letras de nota (e de oitava e velocidade) ficam suspensos enquanto o teclado está ligado (linha `Com Shift` do grupo `Suspensos...`).
- **Duas ações na mesma tecla só em camadas diferentes.** `Ctrl+D` duplica o clipe (`Arranjo`) e as notas (`Piano roll`); dentro de uma mesma camada a tela pede `Trocar` ou `Cancelar`. Já o `Teclado tocando` (oitava e velocidade) tem camada própria: nele a tecla pode ser a mesma de uma ação do estúdio (por exemplo `X` é `Mixer` e `Oitava acima`), e com o teclado ligado ganha a do teclado tocando, o que a janela `?` mostra no grupo `Suspensos…`.
- **Teclas do navegador não dá para tomar.** `F5`, `F11`, `F12`, `Ctrl`+`R`/`W`/`T`/`N`/`Q`, `Ctrl`+`1` a `9` e `Alt+F4` são recusadas na tela; `Ctrl+D` (favoritos) e `Ctrl+B`, por exemplo, são aceitas mas o navegador pode reagir a elas antes do app `(não confirmado)`.
- **Os atalhos são do aparelho e do navegador.** Trocar de navegador, de perfil ou limpar os dados do site volta aos padrões; exporte para não perder.
- **Personalizar existe no app Android**, mas regravar uma tecla precisa de teclado físico (USB ou Bluetooth): sem nenhuma tecla vista, a tela `Personalizar` avisa e só a lista se consulta. `(testado só por testes automáticos; não visto no Android)`
- **Ao sair do app no Android o transporte para sozinho, e ao desplugar o fone também.** Isto é intencional (ver "O aparelho no Android"); a tela fica acesa só enquanto toca ou grava. `(testado só por testes automáticos)`
- **Sair do app no meio de uma gravação a encerra.** O que já foi gravado fica salvo, mas a gravação não continua em segundo plano (sem serviço em primeiro plano o Android poderia matar o processo).
- **Se o som some e aparece o aviso `O motor de áudio parou de responder e o som ficou mudo...`,** o projeto está intacto: use o botão `Reiniciar o áudio` do aviso (ver o [capítulo 00](00-visao-geral.md)).
- **`Esc` fecha o painel de baixo**, mas se o editor tiver notas selecionadas o primeiro `Esc` só limpa a seleção.

## Atalhos

Os atalhos deste assunto (as teclas **padrão**; a janela `?` mostra as suas, se você personalizou; a lista completa está em [Janela `Atalhos do teclado`](#janela-atalhos-do-teclado)):

| Tecla | Ação |
|---|---|
| `?` | Abrir a janela `Atalhos do teclado` (dentro dela, `Personalizar`) |
| `Ctrl+K` (`⌘+K` no Mac) | Ligar/desligar o teclado do computador |
| `Shift+K` | Ligar/desligar o modo `Aprender MIDI` (com o teclado do computador ligado vira nota e fica listado em `Suspensos enquanto o teclado do computador está ligado`) |
| `R` | Gravar |
| `C` | Metrônomo (com o teclado do computador ligado, vira "velocidade menor" e fica listado em `Suspensos enquanto o teclado do computador está ligado`) |
| `P` | Punch liga/desliga (com o teclado ligado vira nota) |
| `T` | Tap tempo (com o teclado ligado vira nota) |
| `Z` / `X` | Com o teclado ligado: oitava abaixo / acima da faixa que toca (a bateria começa no `C2`) |
| `Enter` · `Home` | Parar e voltar ao começo |
| `Delete` · `Backspace` | Apagar o clipe |
| `+` (ou `=`) / `−` | Aproximar / afastar |
| `Esc` | Fechar o painel de baixo |
| `Enter` no campo de latência | Confirmar o número digitado |

## Aprender MIDI

Resumo; o capítulo completo é o [06f MIDI learn](06f-midi-learn.md). Botão com o ícone de controle remoto na barra (aparece com a entrada MIDI ligada, com o modo ligado ou com mapeamentos no projeto; tooltip `Aprender MIDI (Shift+K): clique num controle e mexa no botão do seu teclado`, com a tecla de agora da ação) ou `Shift+K` (que pede o MIDI se ele estava desligado; com o teclado do computador ligado a tecla vira nota). No modo, os controles mapeáveis (knobs de instrumento e de efeito, volume, pan e envios) ganham contorno; clique num deles e mexa num botão do teclado ou controlador (CC, pitch bend ou pressão do canal): o controle passa a acompanhá-lo, na mesma escala da automação, e grava automação se o modo de gravação de automação estiver armado. `Esc` desarma; de novo, sai do modo. Botão direito (ou toque longo) no controle: `Aprender MIDI` e `Remover mapeamento`. `Mapeamentos (n)` na faixa do modo, ou botão direito no botão da barra, abre a lista: origem, alvo, invertido, curva linear ou logarítmica, faixa mín/máx e remover; ali também ficam a opção **Suave** (o controle só assume quando o botão cruza o valor que ele já tem; ligada por padrão) e **Salvar como padrão para novos projetos** (só neste aparelho; leva volume, pan e parâmetros de instrumento, faixas pela posição; efeitos e envios ficam de fora). Os mapeamentos moram no projeto (`midi_map` no documento). CC 1, pedal e pitch bend seguem sendo expressão do instrumento a menos que você os mapeie; CC 120 a 127 (pânico, reset) nunca são mapeados. Mapeamento cujo alvo sumiu (faixa apagada, efeito removido) é ignorado e aparece em vermelho na lista.
