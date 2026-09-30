# Transporte e barra de ferramentas

> A barra do transporte reúne tudo o que se faz sem sair do arranjo: tocar, parar, gravar, andamento, loop, metrônomo, edição rápida, grade, zoom, painéis, importar, exportar e configurações. Leia este capítulo para saber o que cada botão faz e qual atalho o aciona.

## Onde fica

- **Computador (tela de 800 px ou mais):** uma barra horizontal no topo do projeto, acima da régua. Ela rola na horizontal quando a janela é estreita.
- **Celular ou janela abaixo de 800 px:** a mesma barra, mas embaixo da tela, perto do polegar, também com rolagem horizontal.
- Os botões aparecem nesta ordem, da esquerda para a direita. Linhas finas separam os quatro primeiros grupos: **transporte** | **edição e visão** | **painéis** | **entradas de notas**; depois vêm, só com um espaço maior no lugar da linha, **importar e exportar** e, em seguida, **configurações, atalhos, sincronização e status**. Não há botão do arquivo de projeto na barra: `Projeto inteiro (.jopendaw)…` fica dentro da janela **Exportar áudio**.
- Importar e Exportar mostram o nome ao lado do ícone só quando a barra tem 1540 px ou mais de largura (e no computador). Abaixo disso, ou no celular, ficam só os ícones, cada um com o tooltip abaixo. Com o nome à mostra, o **Exportar** mantém o tooltip e o **Importar** fica sem tooltip.
- Quando o app está ocupado (importando, exportando, congelando, processando o warp), aparece no fim da barra um círculo girando com o texto do que está acontecendo (por exemplo `Importando nome.wav…`, `Exportando…`, `Congelando Áudio 1…`, `Processando o warp…`). Enquanto esse texto está na barra, Importar e Exportar ficam desligados.

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
| **Posição** (caixa escura, dois números) | Em cima, a posição em `compasso.tempo.dezesseis-avos` (começa em `1.1.1`, cor da marca); embaixo, o tempo `m:ss.cc` (minutos, segundos e centésimos). Só mostra; não dá para digitar nela. | Ex.: `2.3.1` e `0:03.00`. | Na contagem antes do zero, mostra em vermelho as batidas que faltam (`−4`, `−3`…) e o tempo negativo. |
| **`120 BPM · 4/4`** (botão de texto) | Abre a janela **Andamento e compasso** (ver abaixo). Desligado durante a gravação. | O texto mostra o andamento arredondado e os tempos por compasso. | |
| **Loop (L) · arraste na régua para marcar** (ícone de repetição) | Liga e desliga o loop. Aceso na cor da marca quando ligado. Quando ligado, ao chegar ao fim da região o cursor volta ao começo dela. | Desligado por padrão. Um projeto novo já traz a região do compasso 1 ao 4 (4 compassos), ainda desligada. | Não entra no desfazer. Não dá para ligar ou desligar gravando (aparece `Pare a gravação para ligar ou desligar o loop.`). |
| **Metrônomo (C)** (ícone de cronômetro) | Liga e desliga o clique. | Clique de 30 ms: 1600 Hz no primeiro tempo do compasso, 1000 Hz nos outros. Desligado por padrão. | Não entra no desfazer nem na exportação. |

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
| **BPM** (campo de número) | Andamento do projeto. Só aceita dígitos; vem com o valor atual selecionado, então digitar substitui. | 20 a 400, inteiro. Fora disso: `Entre 20 e 400.` | Enter confirma. |
| **Tempos por compasso** (lista) | Numerador da fórmula de compasso. | `1/4` a `12/4`. O denominador é sempre 4. | Só existe compasso sobre semínima (`/4`); não há 6/8 nem 7/8. |
| **Cancelar** | Fecha sem mudar nada. | | |
| **Salvar** | Aplica o andamento e o compasso. Entra no desfazer e é gravado também no servidor. | | |

O que muda ao trocar o andamento: os clipes ficam na mesma batida de início. Clipes de áudio sem warp mantêm a duração em segundos, então o fim deles anda em batidas; com warp ligado o clipe acompanha o andamento do projeto (ver [Warp e altura](03b-warp-e-altura.md)). Clipes de notas ficam iguais em batidas e passam a tocar mais rápido ou mais devagar. Não dá para mudar o andamento nem o compasso gravando (`Pare a gravação para mudar o andamento.`).

### Edição e visão

| Controle (tooltip) | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| **Desfazer (Ctrl+Z)** (seta para trás) | Volta um passo. | Guarda até 200 passos. Desligado sem passos ou gravando. | Um arraste inteiro (mover, aparar, desenhar loop) é um passo só. |
| **Refazer (Ctrl+Shift+Z)** (seta para frente) | Refaz o passo desfeito. | Também Ctrl+Y. | Fazer uma edição nova apaga o que dava para refazer. |
| **Cortar no cursor (S)** (tesoura) | Divide no cursor o clipe selecionado. Sem clipe selecionado, divide todos os clipes que o cursor cruza na faixa selecionada. Só corta se o cursor está estritamente dentro do clipe. | Áudio e notas; uma nota que cruza o corte vira duas. | Sem efeito se nenhum clipe cruza o cursor. |
| **Duplicar (Ctrl+D)** (ícone de cópia) | Copia o clipe selecionado para logo depois dele e seleciona a cópia. O que a cópia cobrir é aparado (ver [sobreposição de clipes](02b-timeline-e-clipes.md)). | Desligado sem clipe selecionado. | Com o editor de notas aberto, ele passa para a cópia. |
| **Apagar o clipe (Delete)** (lixeira) | Apaga o clipe selecionado, sem fechar o vão. | Desligado sem clipe selecionado. | Backspace também apaga. |
| **Grade de encaixe (Alt ao arrastar: livre)** (menu, ícone de grade + valor atual) | Escolhe o passo de encaixe de tudo que se posiciona com o mouse. | `Livre`, `Compasso`, `1/4`, `1/8`, `1/16`. Padrão: `1/4`. | Veja a tabela da grade abaixo. |
| **Afastar** (lupa com menos) | Reduz o zoom em 1,5 vez, mantendo o cursor no mesmo ponto da tela. | Faixa: 4 a 800 px por batida; padrão 48. | |
| **Aproximar** (lupa com mais) | Aumenta o zoom em 1,5 vez, também ancorado no cursor. | | As teclas + e − mexem em passos menores (1,25 vez). |
| **Seguir o cursor na reprodução** (ícone de alvo) | Liga e desliga o acompanhamento. Ligado e tocando, quando o cursor passa de 92% da largura visível (ou sai pela esquerda), a janela salta e deixa o cursor a 5% da borda esquerda. | Ligado por padrão. | Desligue para editar em outro ponto enquanto a música toca. |
| **Visão: enquadrar, altura das faixas, seguir o cursor** (ícone de zoom em expansão) | Menu de visão (tabela abaixo). O ícone fica esmaecido quando Seguir o cursor está desligado. | | |
| **Seções e marcadores (M cria um no cursor)** (ícone de bandeira) | Menu dos marcadores (tabela abaixo). A bandeira fica na cor da marca quando há marcadores. | | |
| **Duração do projeto: m:ss (N compassos)** (texto cinza discreto) | Mostra a duração até o fim do último clipe, no andamento atual. O texto é só o tempo (`1:24`); o tooltip acrescenta os compassos. | | Marcadores e loop não contam. |

#### Grade de encaixe

| Opção | Passo | Onde vale |
|---|---|---|
| `Livre` | sem encaixe | |
| `Compasso` | 1 compasso (`tempos por compasso` batidas) | |
| `1/4` (padrão) | 1 batida | |
| `1/8` | meia batida | |
| `1/16` | um quarto de batida | |

O encaixe vale para: clicar ou arrastar na régua, clicar numa raia para posicionar o cursor, mover e aparar clipes (começo e fim), arrastar marcadores e a posição onde a importação coloca o áudio. Segurar **Alt** ao arrastar desliga o encaixe naquele arraste. Um clipe de notas não fica menor que um passo da grade ao aparar (1/16 de batida se a grade está em `Livre` ou com Alt). A grade não é salva com o projeto: volta a `1/4` ao reabrir.

#### Menu Visão

| Item | O que faz | Atalho |
|---|---|---|
| **Enquadrar tudo (Z)** | Ajusta zoom e rolagem para caber o projeto inteiro (até o último clipe, marcador ou o fim do loop ligado), com 4% de folga; no mínimo um compasso de largura. | Z |
| **Enquadrar a seleção (Shift+Z)** | Faz o mesmo com o clipe selecionado; sem clipe, enquadra tudo. | Shift+Z |
| **Faixas pequena (P)**, **Faixas média (M)**, **Faixas grande (G)** | Altura das faixas: 70%, 100% (padrão) e 150% da altura normal. Um item fica marcado. | sem atalho (o P, M e G entre parênteses só identificam o tamanho) |
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
| **Tocar com o teclado do computador (Ctrl+K)** (ícone de teclado) | Liga o teclado musical. Ligado, o botão mostra a oitava (`C4`) e o tooltip vira `Teclado do computador ligado (Ctrl+K): A a L tocam a partir do C4, Z/X mudam a oitava, C/V a intensidade (80%)`. | Desligado; oitava 4; intensidade 80%. | Com o teclado ligado, as letras dele têm prioridade sobre os atalhos (o Z deixa de enquadrar e o C, de ligar o metrônomo). O R continua gravando. |
| **Entrada MIDI: ligar teclado ou controlador** (ícone de cabo) | Liga a entrada MIDI. Ligado, mostra a quantidade de aparelhos conectados; com zero, o tooltip diz `MIDI ligado, nenhum aparelho conectado: conecte e ele aparece aqui sozinho`; com aparelhos, `Entrada MIDI: nomes`. | Desligado. | No Chrome o MIDI pede permissão. Detalhes em [Gravação](03c-gravacao.md) e [Configurações, atalhos e Android](09-configuracoes-atalhos-android.md). |

### Arquivos, configurações e sincronização

| Controle (rótulo ou tooltip) | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| **Importar** (só o ícone: tooltip **Importar áudio (Ctrl+I)**; com o nome à mostra não há tooltip) | Abre o seletor de arquivos e coloca cada áudio a partir do cursor (com encaixe na grade). O primeiro vai para a faixa selecionada se ela é de áudio e está livre naquele ponto; os demais, e o primeiro nos outros casos, criam faixas de áudio novas com o nome do arquivo. | Extensões: `wav`, `mp3`, `ogg`, `oga`, `flac`, `m4a`, `aac`, `opus`, `webm`, `aif`, `aiff`. | Desligado gravando ou ocupado. Ver [Áudio e clipes](03-audio-e-clipes.md). |
| **Exportar** (tooltip **Exportar a música (e as faixas separadas) em WAV**) | Abre a janela **Exportar áudio**. Gravando, o tooltip é `Pare a gravação para exportar` e o botão fica desligado. | Ver [Exportação](08-exportacao.md). | No rodapé da janela, `Projeto inteiro (.jopendaw)…` leva ao arquivo do projeto ([capítulo 01](01-projetos-modelos-conta.md#projeto-em-arquivo-jopendaw)). |
| **Configurações: entrada de áudio, latência e contagem** (engrenagem) | Abre a janela **Configurações** (tabela abaixo). | | |
| **Atalhos do teclado (?)** (ícone de tecla de comando) | Abre a janela **Atalhos do teclado** com a lista completa, em grupos, e o botão **Fechar**. | Tecla `?`. | |
| Indicador de sincronização (nuvem, sem texto) | Mostra o estado da sincronização pelo ícone; o tooltip diz o texto. Some por inteiro quando a sincronização está desligada. Só é clicável no conflito. | Ver tabela abaixo. | Detalhes em [Nuvem e sincronização](01b-nuvem-e-sincronizacao.md). |

Estados do indicador:

| Ícone | Tooltip |
|---|---|
| Nuvem com visto (cinza) | `Sincronizado` |
| Nuvem com setas (cor da marca) | `Sincronizando` ou `Sincronizando (N/M arquivos)` |
| Nuvem cortada (âmbar) | `Offline (tentando de novo em N s)` |
| Nuvem com alerta (vermelho) | A mensagem do conflito, ou `Conflito: o projeto mudou em outro aparelho. Toque para resolver` |
| Círculo com ponto de exclamação (vermelho) | A mensagem do erro, ou `Não deu para sincronizar` |

No conflito, a janela **O projeto mudou em outro aparelho** abre sozinha uma vez, com três botões: **Decidir depois** (o ícone reabre a janela), **Usar a versão do servidor** (descarta as mudanças deste aparelho, sem desfazer) e **Manter esta e enviar** (a versão do servidor é substituída pela daqui). Nada é sobrescrito antes da escolha.

#### Janela Configurações

| Controle | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| **ENTRADA DE ÁUDIO** (lista) | Escolhe de onde vem o áudio da gravação. Itens: `Padrão do sistema` (ou `Padrão (nome do aparelho)`), cada entrada encontrada (`Entrada N` quando o navegador esconde os nomes) e `Entrada desconectada` se a escolhida sumiu. | Padrão do sistema. A escolha fica no aparelho, não no projeto. | Desligada gravando (`Pare a gravação para trocar de entrada.`). |
| Botão de atualizar (tooltip **Procurar as entradas de novo (depois de conectar um microfone ou interface)**) | Procura as entradas de novo. Enquanto procura, vira um círculo girando. | | O navegador pede permissão para o microfone na primeira vez. |
| **Nível** (barra horizontal) | Mede o pico da entrada. | | Só se mexe com a entrada aberta: faixa de áudio armada ou monitorando. |
| **GRAVAÇÃO**, **Contagem de um compasso** (interruptor) | Liga a contagem (`O metrônomo conta um compasso antes de a gravação começar`). O mesmo item do menu da seta do Gravar. | Ligada. Vale para este projeto. | |
| **Compensação de latência** (controle deslizante + campo com `ms`) | Quanto o áudio gravado chega atrasado, além do que o navegador já informa. Positivo adianta o que foi gravado; negativo atrasa. | −200 a 500 ms, passo de 1 ms, padrão 0. Fora do intervalo o campo mostra `De -200 a 500 ms`. | Para medir: grave o metrônomo pelo microfone e ajuste até a batida gravada cair na grade. Não entra no desfazer. |
| **Fechar** | Fecha a janela. Um número digitado e ainda não confirmado é aplicado; se for inválido a janela continua aberta com o motivo. | | |

## Passo a passo

**Tocar, pausar e recomeçar**
1. Aperte a barra de espaço (ou toque no botão cheio). A música toca do cursor.
2. Aperte espaço de novo para pausar; o cursor fica onde parou.
3. Aperte Enter (ou o botão de quadrado) para parar e voltar. Com o loop ligado e a música tocando, você volta ao início do loop.

**Mudar o andamento e o compasso**
1. Toque no botão de texto (`120 BPM · 4/4`).
2. Digite o novo valor em **BPM** (20 a 400) e escolha os **Tempos por compasso**.
3. **Salvar**. Se errar, Ctrl+Z desfaz.

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

- [Timeline e clipes](02b-timeline-e-clipes.md): a régua, o cursor, a grade e os marcadores que a barra controla.
- [Gravação](03c-gravacao.md): armar faixas, contagem, tomadas e latência.
- [Mixer](06-mixer.md) e [Painel de efeitos](06c-painel-de-efeitos.md): os painéis abertos pelos botões X e F.
- [Exportação](08-exportacao.md): o botão **Exportar**.
- [Configurações, atalhos e Android](09-configuracoes-atalhos-android.md): a lista completa de teclas e as diferenças no celular.
- Receitas que juntam vários recursos: pasta [`../guias/`](../guias/).

## Limites e pegadinhas

- **Gravando, a barra trava o que mudaria a gravação:** desfazer, refazer, andamento, compasso, loop (ligar, desenhar, seções), importar, exportar, congelar e trocar de entrada ficam desligados ou avisam `Pare a gravação para…`. O cursor também não pula (clicar na régua, numa raia ou num marcador não move o cursor).
- **O que não entra no desfazer:** ligar o loop, o metrônomo, a contagem, a compensação de latência, armar e monitorar faixas. Desfazer uma nota nunca mexe neles. Desenhar a região do loop na régua entra, e desfazer volta o loop junto.
- **O que não é salvo com o projeto:** grade, zoom, rolagem, seguir o cursor, altura das faixas, modo da régua, teclado musical (oitava e intensidade), altura do painel de baixo e a última escolha da janela de exportação (dura só a sessão). O que fica no projeto: andamento, compasso, loop (região e liga/desliga), metrônomo, contagem, compensação de latência e marcadores.
- **Metrônomo e loop não vão para a exportação.** O arquivo sai linear, do começo ao fim, sem cliques.
- **Web e Android:** os botões são os mesmos; no celular Importar e Exportar mostram só o ícone, a barra fica embaixo e o painel de baixo ocupa 60% da altura livre.
- **Teclas com o teclado musical ligado:** as teclas dele (A W S E D F T G Y H U J K O L P para notas, Z e X para a oitava, C e V para a intensidade) passam na frente dos atalhos, com ou sem Shift. Ou seja, S (cortar), L e Shift+L (loop), E, F, Z (enquadrar), X (mixer) e C (metrônomo) deixam de funcionar como atalho. Continuam valendo Espaço, Enter, R, I, M, `[`, `]`, + e −, ?, Esc, Delete e tudo com Ctrl (o Ctrl+K desliga o teclado musical).
- O andamento digitado é sempre inteiro (20 a 400); o botão da barra mostra o valor arredondado.

## Atalhos

Vale o Ctrl no Windows e no Linux e o Cmd (⌘) no Mac; a janela de atalhos mostra ⌘ no Mac. Os tooltips e menus escrevem sempre `Ctrl`.

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
| Ctrl+I | Importar áudio |
| + ou = (também o + do teclado numérico) | Aproximar (1,25 vez) |
| − (também o − do teclado numérico) | Afastar |
| Z | Enquadrar o projeto inteiro |
| Shift+Z | Enquadrar o clipe selecionado |
| M | Marcador no cursor |
| Shift+M | Marcador no cursor pedindo o nome |
| `[` e `]` | Cursor no marcador anterior / seguinte |
| X, E, I, F | Alternar Mixer, Editor de notas, Instrumento, Efeitos |
| Esc | Fechar o painel de baixo |
| ? | Abrir a janela de atalhos |
| Ctrl+K | Ligar/desligar o teclado musical |
| Ctrl + roda do mouse | Zoom no ponto do mouse (na área das raias) |
| Shift + roda do mouse | Rolar na horizontal |

Os atalhos não funcionam enquanto você digita num campo de texto.
