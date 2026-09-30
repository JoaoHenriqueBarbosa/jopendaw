# Mixer

> O painel onde cada faixa vira um canal (volume, pan, mudo, solo, envios, saída) e onde o master fecha a mistura; use para acertar níveis, montar retornos de reverb e agrupar faixas.

## Onde fica

- **Computador:** botão com ícone de controles deslizantes na barra superior (tooltip `Mixer (X)`), aba `Mixer` no painel de baixo, ou a tecla `X`. `Esc` fecha o painel.
- **Celular:** o mesmo painel de baixo; na tela estreita as abas mostram só o ícone (tooltip `Mixer (X)`).
- O painel mostra um canal por faixa, na ordem da lista de faixas, e o **Master** fixo à direita, separado por uma linha. Com muitas faixas a lista de canais rola na horizontal; o Master não sai do lugar. Se o painel de baixo ficar baixo demais, o mixer rola na vertical em vez de espremer o fader (o fader tem no mínimo 72 px de curso).
- Tocar no fundo de um canal seleciona a faixa (o fundo clareia); o mesmo vale na linha do tempo.

De cima para baixo, cada canal de faixa tem: lista de efeitos (inserts), lista de envios, pan, fader com medidor, leitura em dB, armar/monitorar, `M`/`S`, saída e nome. O canal do Master não tem envios, armar, `M`/`S` nem nome editável; ele usa o espaço dos envios para a lista de efeitos dele.

Os barramentos aparecem com um fundo violeta discreto, para não se confundirem com faixas de som.

## Controles

### Efeitos do canal (inserts)

| Controle (rótulo exato) | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| Linha com o nome do efeito (ex.: `Reverb`) | Um efeito da cadeia da faixa. Tocar abre o painel `Efeitos` já naquela faixa. A ordem de cima para baixo é a ordem do sinal. | Até 16 efeitos por cadeia no motor (ver Limites). Tooltip: `Reverb: toque para abrir` + `Botão direito ou toque longo: ligar, mover, remover`. | Efeito desligado fica com o nome apagado e o texto `(desligado)` no tooltip. |
| Luz redonda à esquerda do nome | Liga e desliga (bypass) o efeito sem abrir o painel. Cheia na cor da faixa = ligado; só o contorno = desligado. | O motor troca por crossfade de 10 ms, sem estalo. | Ao religar, o efeito esquece o que tinha guardado (um delay não devolve os ecos de antes do bypass). |
| Menu da linha (botão direito ou toque longo): `Abrir nos efeitos` | Abre o painel `Efeitos` neste efeito. | | |
| `Ligar` / `Desligar (bypass)` | O texto muda conforme o estado. Mesma ação da luz. | | |
| `Mover para cima` / `Mover para baixo` | Sobe ou desce o efeito na cadeia. Só aparecem quando há para onde ir. | | Ordem importa: EQ antes ou depois do compressor soa diferente. |
| `Remover` | Tira o efeito e apaga as automações que apontavam para ele. | Entra no desfazer. | |
| Linha `Efeito` (com `+`) | Abre o menu de efeitos, agrupado por família (Timbre, Dinâmica e utilidade, Espaço, Modulação, Saturação); cada item mostra nome e descrição. | Tooltip: `Adicionar efeito`; no master, `Adicionar efeito no master`. | O painel de efeitos tem mais opções: ver [06c](06c-painel-de-efeitos.md). Os 12 efeitos estão em [06d](06d-efeitos-referencia.md). |

A altura da lista acompanha o painel de baixo (o painel maior mostra mais linhas, todas as faixas usam a mesma altura); passando do que cabe, um trilho fino à direita avisa que há mais e a lista rola.

### Envios

| Controle (rótulo exato) | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| Linha `Envio` (com `+`) | Aparece quando a faixa não tem nenhum barramento para onde enviar (numa faixa comum: quando o projeto ainda não tem barramento; num barramento: quando não há outro depois dele). Cria um barramento novo e já manda esta faixa para ele. | Tooltip: `Criar um barramento e enviar esta faixa para ele (retorno de reverb, delay...)`. O barramento nasce com o nome `Barramento 1`, no fim da lista, e fica selecionado. | O caminho mais curto para montar um retorno de reverb. |
| Linha com o nome de um barramento (ex.: `Barramento 1`) e um knob pequeno | Um envio possível para aquele barramento. Com o knob vazio (só um `+`) não há envio. Tocar cria o envio; arrastar na vertical dosa (e cria se preciso). | Nível de −∞ a +6 dB (ganho de 0 a 2), pela mesma curva do fader. Envio novo nasce em **−6,0 dB, pós-fader**. Arrastar: 150 px para o curso todo; `Shift` deixa 5 vezes mais fino. | Passando o mouse ou arrastando, o nome dá lugar ao nível em dB (ex.: `−6.0 dB`). |
| Roda do mouse sobre o knob do envio | Mexe no nível (`Shift`: fino). | | |
| Duplo clique no envio | Volta o nível a 0 dB (tooltip: `duplo clique: 0 dB`). | Só age se já existe envio e o nível não é 0 dB. | |
| Menu do envio (botão direito ou toque longo), sem envio: `Criar envio pós-fader`, `Criar envio pré-fader` | Cria o envio já no modo escolhido. | | |
| Menu do envio, com envio: `Pós-fader`, `Pré-fader` | Marca qual dos dois vale. | Pós-fader é o padrão. | |
| `Nível em 0 dB` | Põe o nível do envio em 0 dB. | | |
| `Remover envio` | Apaga o envio e a automação de nível dele. | | |
| Etiqueta `PRÉ` (âmbar) | Aparece à direita da linha quando o envio é pré-fader. | | |

**Pré ou pós-fader.** No motor o caminho é: efeitos → **envios pré-fader** → volume, pan e mudo → **envios pós-fader** → porta do solo → saída. O pré-fader tira o sinal *antes* do volume, do pan e do mudo: baixar o fader ou apertar `M` não mexe nele. O pós-fader segue o fader (e leva o pan da faixa).

Quais barramentos aparecem na lista: uma faixa comum lista todos os barramentos. Um barramento lista só os barramentos que vêm *depois* dele na lista de faixas (ver "Ordem de processamento" abaixo). O master não envia.

### Pan, fader e medidores

| Controle (rótulo exato) | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| Knob de pan, com a leitura ao lado (tooltip `Pan: C`) | Posição da faixa entre esquerda e direita. Arrastar na vertical ou roda. | Leitura `C` (centro), `E30` (30% à esquerda) até `E100`; `D30` a `D100` à direita. Padrão `C`. Perto do centro (±3%) o arraste "gruda" em `C`. `Shift` deixa mais fino. | Duplo clique volta ao centro. |
| Fader (tooltip `Volume: −6.0 dB` + `Arraste (Shift: fino) ou use a roda · duplo clique: 0 dB`) | Volume da faixa. Arrasta a partir de onde a tampa está (clicar no trilho não pula o volume, como numa mesa). | De −∞ a **+6 dB**; padrão **0 dB**. Curva cúbica: ganho = 2 × posição³, então 0 dB fica a ~79% do curso. | Escala ao lado do trilho: `+6`, `0`, `6`, `12`, `24`, `48` (os números de baixo são negativos: −6, −12, −24, −48). Em fader baixo, rótulos que se encostariam somem e ficam só os traços. |
| Leitura em dB abaixo do fader (tooltip `Volume (duplo clique: 0 dB)`) | Valor atual do volume. | Ex.: `−6.0 dB`, `+0.0 dB`, `−∞ dB`. | Duplo clique nela volta a 0 dB. |
| Medidor de duas barras ao lado do fader | Pico esquerdo e direito da faixa, depois de volume, pan, mudo e solo. | Escala de −48 a 0 dB. Ver [06b](06b-analisador-e-medidores.md). | Faixa silenciada por mudo ou solo não mexe o medidor. |
| Barra fina à direita do medidor (só em faixa de áudio armada) | Nível da entrada (o que chega do microfone, antes dos efeitos). Tooltip: `Nível da entrada (o que chega do microfone, antes dos efeitos)` + `Vermelho no topo: saturou; baixe o ganho na fonte`. | O lugar fica reservado em toda faixa, para armar não empurrar o fader. Faixa de instrumento armada não mostra: ali entram notas, não áudio. | Detalhes do "clip" em [06b](06b-analisador-e-medidores.md). |

Fader, pan e envios entram no desfazer como **um passo por gesto** (do começo ao fim do arraste). Tudo é salvo com o projeto.

### Gravação, mudo e solo

| Controle (rótulo exato) | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| Botão com ponto vermelho (`Armar para gravar`) | Arma a faixa: ao gravar (`R`), o microfone (faixa de áudio) ou as notas tocadas ao vivo (faixa de instrumento) viram um clipe nela. | Desligado por padrão. Barramento não tem o botão. | Detalhes em [03c Gravação](03c-gravacao.md). |
| Botão de fones (`Monitorar a entrada`) | Só em faixa de áudio: o microfone passa ao vivo pelos efeitos e pelo fader da faixa. Na faixa de instrumento o lugar fica vazio, para o armar alinhar com os vizinhos. | Desligado por padrão. | Use fones; sem eles o microfone capta o próprio som (o tooltip avisa). |
| `M` (tooltip `Mudo`) | Silencia a faixa (vermelho quando ligado). | O volume desce a zero em ~5 ms, sem estalo. | Mudo e solo também estão no cabeçalho da faixa na linha do tempo. |
| `S` (tooltip `Solo`) | Deixa soar só as faixas em solo (âmbar quando ligado). | Vários solos acumulam; não há "desligar os outros solos" automático. | Ver "Solo e mudo" abaixo. |

### Saída e nome

| Controle (rótulo exato) | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| Botão de saída, com o nome do destino (tooltip `Saída: Master`) | Para onde a faixa sai: `Master` ou um barramento. Abre um menu. | Padrão `Master`. O item marcado é o atual. | A saída é *no lugar* do master: a faixa deixa de ir direto para ele. |
| Menu da saída: `Master` | Volta a faixa para o master. | | |
| Menu da saída: nome de um barramento | Manda a faixa para ele (só lista os que não fecham ciclo). | | Use para grupos (bateria, vozes). |
| Menu da saída: `Novo barramento` | Cria um barramento no fim da lista e já liga a saída da faixa nele. | | |
| Ícone do tipo + nome, no pé do canal | Mostra o tipo da faixa (tooltip: `Áudio`, `Sintetizador`, `Bateria`, `Sampler`, `FM`, `Wavetable`, `Barramento`). Tocar no ícone de uma faixa de instrumento abre o instrumento (`Sintetizador: abrir o instrumento`); no de um barramento abre os efeitos (`Barramento: abrir os efeitos`). | Nome truncado com reticências; o tooltip mostra inteiro. | Renomear é pelo menu da faixa na linha do tempo. |

### Coluna `Faixa` (fim da lista)

| Controle (rótulo exato) | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| `Faixa` com `+` (tooltip `Nova faixa ou barramento`) | Abre um menu com `Áudio`, `Sintetizador`, `Bateria`, `Sampler`, `FM`, `Wavetable` e, por último, `Barramento`. | Barramento novo entra no fim da lista, com o nome `Barramento N`. | Criar sem sair do mixer. |

### Master

| Controle (rótulo exato) | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| Lista de efeitos do master (`Efeito`, tooltip `Adicionar efeito no master`) | Efeitos que processam a mistura inteira, em série, **antes** do volume do master e do limitador de segurança. | Mesmo menu e mesmas ações de uma faixa. | Sugestão do próprio app para o master vazio: `EQ`, `Compressor`, `Limitador`. |
| Pan do master | **Balanço**, não pan: só atenua o lado oposto; o centro fica em 0 dB. | Mesma leitura `C`, `E..`, `D..`. Padrão `C`. | |
| Fader do master e leitura em dB | Volume final da mistura. | −∞ a +6 dB, padrão 0 dB. Automatizável. | |
| Medidor do master | Pico esquerdo e direito **depois do limitador**. | Nunca passa de −0,3 dB quando o limitador age. | |
| `Saída` (tooltip `O master sai no áudio do aparelho, depois do limitador de segurança`) | Só informa: o master vai para a saída de áudio do aparelho. Não é botão. | | |
| Nome `Master` | Fixo. | | |

### Como o som corre (ordem de processamento)

1. **Faixas comuns.** Cada uma faz: fonte (clipes, instrumento, e a entrada se estiver monitorando) → efeitos → envios pré-fader → volume, pan e mudo → envios pós-fader → porta do solo → saída.
2. **Barramentos**, em ordem de posição na lista. Cada um soma o que chegou (saídas e envios), passa pelos efeitos, fader, envios e saída dele.
3. **Master.** Soma tudo o que saiu para ele → efeitos do master → volume e balanço → clique do metrônomo (se ligado; ele segue o volume do master mas não passa pelos efeitos do master) → **limitador de segurança** → saída, medidor do master e analisador do master.

**Limite conhecido da ordem dos barramentos.** As faixas comuns sempre são processadas antes de todos os barramentos, então uma faixa comum pode mandar (envio ou saída) para *qualquer* barramento. Já um barramento só pode mandar para um barramento que venha **depois** dele na lista de faixas (índice maior). O app só oferece esses destinos nos menus. Se você usa `Mover para cima` / `Mover para baixo` (menu da faixa na linha do tempo) e a nova ordem quebra uma dessas ligações, o app **apaga o envio** (com a automação dele) ou **volta a saída para o Master**, sem perguntar. O motor, por segurança, ignora um destino inválido (a saída vira o master).

Efeito prático: crie primeiro os barramentos que vão *alimentar* outros (grupos, delay) e depois os que recebem (o retorno de reverb, no fim). Como o barramento novo entra sempre no fim da lista, todos os que já existem conseguem mandar para ele.

### Solo e mudo

- **Mudo** zera o volume da faixa (pós-fader). Os envios *pós*-fader dela calam junto; os *pré*-fader continuam. Mudo num barramento cala tudo o que passa por ele.
- **Solo** deixa audível: a faixa em solo, tudo que ela alimenta (o barramento da saída dela e os barramentos dos envios dela, em cadeia) e, se o solo estiver num barramento, tudo o que sai nele. As demais são silenciadas em ~5 ms (o medidor delas também apaga).
- Por isso, soar uma faixa em solo mantém o reverb dela: o retorno é alimentado só por ela, porque os envios das faixas caladas para o retorno são cortados. Solo no próprio barramento de retorno deixa só ele soar, com o que chega pelos envios.
- Faixa com `M` e `S` juntos fica muda: o mudo vence.
- Não existe solo exclusivo, "solo seguro" nem solo no Master.

### Sidechain (de onde vem a fonte)

O sidechain existe no `Compressor` e no `Gate`, no parâmetro `Sidechain` (grupo Chave), que é um menu: `Própria entrada` (o padrão) ou o nome de qualquer outra faixa (barramentos incluídos). A faixa em que o efeito está não aparece na lista dela mesma. Também dá para usar no master.

- O sinal-chave é a saída da faixa-fonte **depois dos efeitos dela e antes do fader**, do mudo e do solo. Então a fonte pode estar muda, com o fader baixo ou calada por solo e ainda assim controlar o compressor.
- O motor processa a faixa-fonte antes de quem a usa, para a chave ser do mesmo bloco. Numa chave circular (A é chave de B e B de A), uma das duas usa a chave do bloco anterior.
- O sidechain escolhido não é automatizável, não é trocado por presets e acompanha a faixa se ela mudar de lugar na lista.

## Passo a passo

**Acertar volume e pan de uma faixa**
1. Abra o mixer (`X`).
2. Arraste o fader do canal para cima ou para baixo; `Shift` para ajuste fino. Leia o valor em dB abaixo do fader.
3. Arraste o knob de pan na vertical até a leitura desejada (`E30`, `D40`...). Duplo clique volta ao centro.
4. Duplo clique no fader ou na leitura devolve 0 dB.

**Criar um retorno de reverb**
1. No canal de uma faixa, toque na linha `Envio` (é o que aparece enquanto o projeto não tem barramento). Nasce `Barramento 1` com o envio já ligado em −6,0 dB.
2. No canal `Barramento 1`, toque em `Efeito` e escolha `Reverb`.
3. Nas outras faixas, na lista de envios, toque no knob de `Barramento 1` e arraste para dosar.
4. Para o passo a passo completo, com valores: [guia de mixagem e automação](../guias/mixagem-e-automacao.md).

**Agrupar faixas num barramento**
1. No botão de saída de uma faixa, escolha `Novo barramento` (ou um barramento que já exista).
2. Repita nas outras faixas do grupo, escolhendo o mesmo barramento.
3. No canal do barramento, acerte o fader do grupo e ponha efeitos de grupo (ex.: `Compressor`).

**Ouvir só uma faixa**
1. Toque em `S` no canal. As outras calam; o retorno de reverb dela continua.
2. Toque de novo em `S` para voltar.

**Tirar o pré-fader de um envio**
1. Botão direito no envio (ou toque longo no celular).
2. Escolha `Pré-fader`. A etiqueta `PRÉ` aparece.

## Combina com

- [06b Analisador e medidores](06b-analisador-e-medidores.md): como ler os medidores e o espectro.
- [06c Painel de efeitos](06c-painel-de-efeitos.md) e [06d Referência dos efeitos](06d-efeitos-referencia.md): o que colocar nos inserts, nos barramentos e no master.
- [07 Automação](07-automacao.md): mover volume, pan, envios e parâmetros no tempo; fader, pan e knobs seguem a automação enquanto toca.
- [08 Exportação](08-exportacao.md): o arquivo sai depois do limitador do master; "Congelar em áudio" leva volume, pan, saída e envios para a faixa nova.
- [03c Gravação](03c-gravacao.md): armar e monitorar.
- [Guia: mixagem e automação](../guias/mixagem-e-automacao.md): mix do zero, retorno de reverb, fades.

## Limites e pegadinhas

- **Limitador de segurança do master** (ver seção própria abaixo): sempre ligado, sem controle na tela e sem medidor de redução. O medidor do master mostra o sinal *depois* dele.
- **Acima de 0 dB nas faixas não estala.** O motor trabalha em ponto flutuante: o som de uma faixa (ou de um barramento) pode passar de 0 dBFS e voltar sem distorcer, desde que a soma no master seja domada. Quem ataca o excesso é o limitador do master, e só no fim.
- **Pan por faixa perde 3 dB no centro.** É uma lei de potência constante: no centro cada lado sai com −3 dB em relação a uma faixa toda para um lado. A leitura em dB do fader não inclui isso. O pan do master é diferente (balanço, centro em 0 dB).
- **Pico, não volume percebido.** Os medidores mostram o pico de amostra, não RMS nem LUFS.
- **Envio pré-fader continua com a faixa muda.** É a definição de pré-fader; se o reverb some quando você silencia a faixa, o envio é pós-fader.
- **Envios e solo:** com outra faixa em solo, os envios das faixas que não estão em solo são cortados (menos os que vão para um barramento solado).
- **Só faixas de áudio monitoram.** A entrada soma antes dos efeitos e o monitoramento tem a latência do aparelho.
- **Latência de efeitos com lookahead não é compensada** entre faixas (o efeito `Limitador`, que tem o parâmetro `Lookahead`, atrasa só a faixa em que está). O limitador do master é compensado na exportação.
- **Limites do motor:** até 16 efeitos por cadeia e 16 envios por faixa. O app não trava você antes: passando disso, os que sobram não soam `(não confirmado: não testei passar de 16 no app)`.
- **O knob de envio não anda com a automação** do nível do envio (só a raia de automação mostra o valor). Fader, pan e knobs de efeito e instrumento andam em laranja, tocando.
- **Salvo com o projeto:** ganho, pan, mudo, solo, armar, monitorar, efeitos, envios (nível e pré/pós) e saída de cada faixa, mais volume e balanço do master.

### O limitador de segurança do master

É o último estágio antes da saída. Somar várias faixas passa fácil de 0 dBFS, e sem ele o que saía era corte duro (distorção audível). Ele age assim:

| Característica | Valor |
|---|---|
| Teto | 0,966 de amplitude, ou seja, **−0,3 dBFS** (folga para a reconstrução do conversor) |
| Lookahead | **1,5 ms** (72 amostras a 48 kHz); é também a latência que o master ganha |
| Soltura | 80 ms |
| Abaixo do teto | Transparente: o áudio só sai atrasado do lookahead, sem alteração |
| Ligado | Sempre; o app não tem chave para desligar |

Ele existe para **nunca deixar passar nada acima do teto**, não para dar volume: não é o limitador de masterização (esse é o efeito `Limitador`, que você coloca no master ou nas faixas). Se o medidor do master vive encostado no topo, abaixe as faixas: o limitador está trabalhando o tempo todo e o som se achata.

## Atalhos

| Tecla / gesto | Ação |
|---|---|
| `X` | Abre ou fecha o mixer |
| `Esc` | Fecha o painel de baixo |
| Arrastar (vertical) no fader, pan ou envio | Muda o valor |
| `Shift` ao arrastar | Ajuste fino (5 vezes mais lento) |
| Roda do mouse sobre fader, pan ou envio | Muda o valor (com `Shift`, mais fino) |
| Duplo clique no fader, na leitura de dB ou no envio | 0 dB |
| Duplo clique no pan | Centro |
| Botão direito (ou toque longo no celular) num efeito ou num envio | Menu do item |
