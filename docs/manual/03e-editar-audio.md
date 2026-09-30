# Editar áudio: dividir, remover silêncio, normalizar e quantizar

> Corta um clipe de áudio em pedaços (pelos golpes, em partes iguais ou na grade), tira os silêncios, leva o clipe a um volume-alvo e encaixa cada golpe na grade, sem tocar no arquivo: serve para reorganizar um loop de bateria, limpar uma voz, nivelar vozes e apertar uma bateria gravada.

Legenda de confiança: todo o capítulo vem da leitura do código (`app/lib/daw/audio_edit.dart`, `audio_edit_ui.dart`, `timeline.dart`) e dos testes automáticos (40 testes de lógica em `audio_edit_test.dart` e 11 de tela em `audio_edit_ui_test.dart`). **Nada foi visto nem ouvido rodando** no Chrome ou no Android `(testado só por testes automáticos)`.

## Onde fica

Clique com o botão direito no clipe de áudio (computador) ou faça um toque longo (celular) e escolha **`Editar áudio`** (ícone de varinha, com uma setinha `>` à direita). Abre um segundo menu, no mesmo ponto da tela, com quatro itens:

| Item (rótulo exato) | Ícone | Abre o diálogo |
|---|---|---|
| `Dividir por transientes…` | dois galhos | `Dividir por transientes` |
| `Remover silêncio…` | tesoura | `Remover silêncio` |
| `Normalizar clipe…` | equalizador | `Normalizar clipe` |
| `Quantizar por fatias…` | grade | `Quantizar por fatias` |

O menu só existe no clipe de **áudio** (o clipe de notas não tem). Não há botão na barra nem atalho de teclado. Os diálogos cabem em 360 px de largura (celular).

Toda ação é **não destrutiva**: o arquivo de áudio nunca é alterado. `Dividir`, `Remover silêncio` e `Quantizar` só trocam o clipe por vários clipes que apontam para o mesmo áudio (cada um com o seu `offset`, duração, ganho e fades); `Normalizar` só muda o `Ganho do clipe`. Cada ação é **um passo do desfazer**.

## Como funciona

**A prévia.** Todos os diálogos mostram a forma de onda do trecho que o clipe toca (96 px de altura; 112 px na quantização) e desenham nela o que vai acontecer antes de você aplicar:

- linhas na cor do tema, numeradas a partir de 1, onde o clipe será cortado (os números somem quando passam de 60 cortes);
- em `Remover silêncio`, os trechos que serão removidos aparecem escurecidos;
- em `Quantizar por fatias`, uma faixa a mais no pé, com uma seta âmbar de cada fatia até o lugar novo (só as que andam 0,5 ms ou mais, e só com até 96 fatias).

Sem a forma de onda no aparelho, o espaço da prévia fica vazio. Enquanto você arrasta um deslizante, o valor muda na hora e a prévia é refeita **quando você solta** (o cálculo passa pelo áudio todo).

**Depois de aplicar.** O diálogo troca o conteúdo por um aviso com o que foi feito, mais a frase `Dá para desfazer numa vez só (Ctrl+Z).`, e fica só o botão `Fechar`. Se a ação não deu, o aviso de erro aparece dentro do diálogo e nada muda.

**A detecção de transientes.** `Dividir por transientes…` e `Quantizar por fatias…` usam **o mesmo detector do `Fatiar sample…` do sampler** ([04c](04c-sampler.md#fatiar-sample)): a função `slicePoints`, espelho em Dart da conta de `engine/src/sampler_zones.rs` (os testes de paridade dos dois lados seguem valendo). Em resumo: mistura os canais em mono, mede a energia e a variação do sinal a cada 5 ms, procura os saltos de energia que passam de um limiar (contra a média das redondezas e contra o maior salto do áudio), exige 50 ms entre ataques, recua cada corte até o começo do ataque e, se der, até o cruzamento de zero mais próximo (até 2 ms), para não estalar. A diferença para o sampler: aqui o detector analisa só o **trecho que o clipe toca**, e não há o limite de 96 fatias (o teto é o de 500 clipes, ver [Limites](#limites-e-pegadinhas)).

O que a **`Sensibilidade`** faz: 0% a 100%, padrão 50%. Ela afrouxa três exigências de uma vez: em 0% o ataque precisa chegar a 30% do maior ataque do áudio e a 6 vezes a média das redondezas (0,2 s de cada lado); em 100%, a 8% e a 1,5 vez. Em termos de uso: mais sensibilidade pega também chimbais fracos e notas fantasma, e pode cortar dentro de uma nota longa; menos deixa passar tudo o que não é golpe forte.

**Como o tempo é lido.** As ações por fatias só valem para clipe sem warp, que toca em tempo real; então as batidas da grade viram segundos pelo **mapa de andamento** do projeto (vale com andamento variável).

### Dividir por transientes

Parte o clipe em vários, no mesmo lugar da linha do tempo: o som em sequência é o mesmo do clipe original (ver a ressalva das emendas abaixo).

| Controle (rótulo exato) | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| Título `Dividir por transientes` | Identifica o diálogo | | |
| `Por transientes` / `N fatias iguais` / `Na grade` (chips) | Como achar os cortes | Padrão `Por transientes` | Cada modo mostra os seus controles abaixo |
| `Sensibilidade` (só em `Por transientes`) | Quantos ataques contam como corte | 0% a 100%, padrão 50%; mostra `50%` | Ver [a detecção](#como-funciona) |
| `Distância mínima entre cortes` (só em `Por transientes`) | Dois cortes mais próximos que isto viram um só (fica o primeiro) | 10 ms a 500 ms, padrão `50 ms` | Ver a pegadinha do valor escondido em [Limites](#limites-e-pegadinhas) |
| `Fatias` (só em `N fatias iguais`) com os botões `Menos uma fatia` e `Mais uma fatia` (tooltips) | Número de fatias iguais no **tempo** (do trecho do clipe) | 2 a 96, padrão 8 (`−` apagado no 2 e `+` apagado no 96) | Não olha o som nem o andamento; o primeiro corte é o começo do clipe e não conta como corte |
| `1/4` / `1/8` / `1/16` / `1/32` (chips, só em `Na grade`) | Um corte em cada linha da grade dentro do clipe | Começa na grade da barra: `1/4`→`1/4`, `1/8`→`1/8`, e `1/16`, `Livre` ou `Compasso`→`1/16` | `1/4` é uma batida. A linha que cai exatamente no começo do clipe não gera corte |
| Prévia | Forma de onda com as linhas numeradas | | |
| Resumo (texto pequeno) | `N fatias, com emendas de 2 ms que não mudam o som.` | | Sem cortes: `Nenhum transiente achado: tente mais sensibilidade, fatias iguais ou a grade.` (modo transientes) ou `Nenhum corte cai dentro do clipe.` (os outros). Passando de 500: `Fatias demais (N; o máximo é 500). Diminua a sensibilidade.` |
| `Cancelar` / `Dividir` | Fecha / aplica | `Dividir` fica apagado sem cortes ou se o clipe foi recusado | |

Resultado: `Dividido em N fatias, com emendas de 2 ms sem mudar o som.` (e, se o fade original era maior que a fatia, ` O fade original do clipe foi encurtado para caber na fatia.`). O primeiro pedaço fica selecionado.

O que acontece com fades e nomes:

- **Fades originais.** O fade de entrada do clipe (e a curva e a marca de fade automático dele) fica só na **primeira** fatia; o fade de saída fica só na **última**. Se o fade original é maior que a fatia que o recebe, ele é encurtado.
- **Emendas.** Entre duas fatias coladas há uma emenda de **2 ms**: a fatia seguinte começa 2 ms antes do corte, com fade de entrada, e a anterior termina no corte com fade de saída do mesmo tamanho. A curva usada é a `Suave (padrão)` (o código 0 do motor, `x²`; ver [Áudio e clipes](03-audio-e-clipes.md#fades-e-crossfade)). **Ressalva:** essa curva não é uma rampa reta, então no meio dos 2 ms os dois lados somam 0,5 em amplitude (cerca de −6 dB por um instante), não 1. O teste do app usa rampas retas e por isso não vê isso; a queda de 2 ms dificilmente se ouve em material de bateria, mas pode aparecer em notas sustentadas `(lido do código; não ouvido)`.
- **Ganho, warp e demais campos** de cada fatia são cópias do clipe original (o ganho também).
- **Nomes.** O clipe de áudio não tem nome próprio no documento, então não há o que nomear: as fatias são clipes comuns, na mesma faixa, cada um com um id novo, no mesmo lugar da lista.
- **Posição.** Cada fatia começa onde o trecho dela já estava (nada anda). Como a fatia começa 2 ms antes do corte, arrastar uma fatia com o encaixe da grade põe o início do **clipe** na linha, e o ataque cai 2 ms depois dela.

### Remover silêncio

Acha as pausas do clipe, tira do meio o que é silêncio e deixa a **lacuna**: os trechos que sobram ficam **onde estavam**; nada é puxado para fechar o buraco.

| Controle (rótulo exato) | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| Título `Remover silêncio` | Identifica o diálogo | | |
| `Limiar` | Abaixo disto é silêncio. Mede o **pico** de cada bloco de 1 ms (o maior entre os canais) no áudio original, sem o ganho do clipe | −80 a −10 dBFS, em passos de 1 dB, padrão `−45 dBFS` | Ruído de sala acima de −45 dBFS não conta como silêncio: suba para −40 ou −35 |
| `Silêncio mínimo` | Silêncio mais curto que isto fica (respiro, pausa entre palavras) | 10 ms a 2 s, padrão `100 ms` | Suba para 300 a 500 ms para tirar só pausas de verdade |
| `Margem antes do som` | O que sobra do silêncio **antes** de cada som que volta | 0 a 300 ms, padrão `10 ms` | Protege o ataque das consoantes |
| `Margem depois do som` | O que sobra do silêncio **depois** de cada som que passou | 0 a 300 ms, padrão `20 ms` | Protege o rabo das notas e da reverberação da sala |
| `Fade nos cortes` | Fade de entrada e de saída dos pedaços que ficam, onde houve corte | 0 a 50 ms, padrão `5 ms` | Fade com a curva `Suave (padrão)`; nas pontas do clipe valem os fades originais |
| Prévia | A onda com os trechos removidos escurecidos | | |
| Resumo | `N trechos, X s removidos (a parte apagada da onda). A lacuna fica: o resto do clipe não se move.` | | Sem nada a tirar: `Nenhum silêncio com esses ajustes.`; tudo abaixo do limiar: `O clipe todo está abaixo do limiar: nada seria mantido.`; muitos trechos: `Trechos demais (N; o máximo é 500). Aumente o silêncio mínimo.` |
| `Cancelar` / `Remover` | Fecha / aplica | `Remover` fica apagado nesses três casos de erro | |

Como decide: percorre o clipe em blocos de 1 ms; uma sequência de blocos abaixo do `Limiar` que dure pelo menos o `Silêncio mínimo` é um silêncio. Cada silêncio **encolhe** pelas margens (a `Margem depois do som` no começo dele e a `Margem antes do som` no fim) e só o miolo que sobra (1 ms ou mais) é removido. Nas pontas do clipe não há som do outro lado, então a margem só vale do lado onde há som: um silêncio no começo é removido até a `Margem antes do som` antes do primeiro som, e um silêncio no fim, a partir da `Margem depois do som`.

O que fica: cada trecho mantido vira um clipe na posição original (mesmo ganho, mesmo áudio), com `Fade nos cortes` onde houve corte. O resultado mostra `N trechos, X,XX s removidos` (um trecho: `1 trecho`; `X,X s` a partir de 10 s). Recusas: o clipe todo silencioso (`O clipe todo está abaixo do limiar: nada seria mantido. Suba o limiar ou diminua o silêncio mínimo.`; nada é apagado) e sem silêncio (`Nenhum silêncio nesses ajustes: o clipe fica como está.`).

### Normalizar clipe

Mede o trecho que o clipe toca e ajusta o **ganho do clipe** para chegar ao alvo. O áudio não é alterado. Vale também para clipe com warp, transposição ou inversão (ganho é ganho).

| Controle (rótulo exato) | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| Título `Normalizar clipe` | Identifica o diálogo | | |
| `Pico` / `RMS` / `LUFS` (chips) | O que medir e levar ao alvo | Padrão `Pico`. Trocar de chip volta o `Alvo` ao padrão do chip | Pico: o volume máximo. RMS: a média de energia. LUFS: o volume percebido |
| `Alvo` (deslizante; mostra ex. `−1,0 dBFS`) | O valor que o trecho deve ter depois | `Pico`: −24,0 a 0,0 dBFS, padrão `−1,0`. `RMS`: −40,0 a 0,0 dBFS, padrão `−18,0`. `LUFS`: −40,0 a 0,0 LUFS, padrão `−14,0`. Passos de 0,5 | Para vozes de podcast, `LUFS` −16; para o ajuste de nível de uma tomada, `Pico` −1 |
| Barra de progresso | Aparece enquanto mede | | O LUFS devolve o controle à tela a cada meio segundo de áudio |
| `Medido: X unidade (pico Y dBFS)` | O valor do trecho no modo escolhido e o pico dele | Ex.: `Medido: −20,5 LUFS (pico −8,0 dBFS)` | A medida não depende do alvo: mexer no `Alvo` só refaz a conta |
| `Ganho do clipe: X (agora Y)` | O ganho que será aplicado e o ganho atual do clipe | Ex.: `Ganho do clipe: +4,5 dB (agora 0,0 dB)` | O novo ganho **substitui** o atual |
| Aviso `Limitado porque …: o alvo não será atingido.` | O ganho foi segurado por um teto | Ver abaixo | |
| Texto fixo | `Mede o trecho que o clipe toca e ajusta só o ganho dele; o áudio não é alterado.` | | |
| `Cancelar` / `Normalizar` | Fecha / aplica | `Normalizar` fica apagado enquanto mede ou se não deu para medir | |

Como mede e que ganho aplica:

- **Sempre o áudio original do trecho** (de `offset` até `offset + duração`): ignora o `Ganho do clipe` atual, os fades, o fader da faixa, o pan e os efeitos. Por isso normalizar duas vezes dá o mesmo resultado.
- **`Pico`:** o maior valor de amostra (valor absoluto, todos os canais). **`RMS`:** a raiz da média dos quadrados de todas as amostras dos canais juntos. **`LUFS`:** o loudness integrado (ITU-R BS.1770, com os gates de −70 LUFS e de 10 LU), a mesma conta do `Normalizar o loudness` da exportação ([08](08-exportacao.md#normalizar-o-loudness)), mas só nos **dois primeiros canais** do arquivo, sem true peak.
- **Ganho** = `Alvo` − medida, em dB, como **ganho absoluto** do clipe (ganho linear = 10^(dB/20)).
- **Tetos.** Fora do modo `Pico`, o ganho não pode levar o pico do clipe além de 0 dBFS: se passaria, o ganho é reduzido até o pico chegar a 0 dBFS e o aviso diz `Limitado porque o pico do clipe chegou a 0 dBFS antes do alvo`. Em qualquer modo, o ganho do clipe vai no máximo a **+12 dB** (`Limitado porque o ganho do clipe vai até +12 dB`). O mínimo interno é cerca de −60 dB.
- **Resultado:** `Ganho do clipe: +4,5 dB. LUFS medido: −20,5 LUFS; alvo: −16,0 LUFS.` (mais ` Limitado porque …: o alvo não foi atingido.` quando um teto segurou). O novo ganho aparece no `Ganho do clipe…` ([03](03-audio-e-clipes.md#ganho-do-clipe)), cujo controle vai de −40 a +12 dB.
- **Recusas:** `O trecho do clipe está em silêncio: não há o que normalizar.` (pico abaixo de cerca de −140 dBFS); no `LUFS`, `Não deu para medir o LUFS: o trecho tem menos de 400 ms ou está muito baixo. Use o pico ou o RMS.` (o erro fica no chip; os outros chips continuam medindo).

### Quantizar por fatias

Corta o clipe nos transientes e leva o **começo de cada fatia** à linha de grade mais próxima, movendo as fatias. O áudio não é esticado: entre duas fatias pode sobrar silêncio.

| Controle (rótulo exato) | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| Título `Quantizar por fatias` | Identifica o diálogo | | |
| `Grade` (chips `1/4`, `1/8`, `1/16`, `1/32`) | A linha para onde cada golpe vai | Começa na grade da barra (`1/4`→`1/4`, `1/8`→`1/8`, `Livre`, `Compasso` e `1/16`→`1/16`) | `1/4` é uma batida |
| `Força` | Quanto do caminho até a linha cada fatia anda | 0% a 100% em passos de 5%, padrão `100%` | 0% não move (equivale a dividir); 50% anda metade do caminho e guarda parte da pegada |
| `Sensibilidade dos transientes` | A mesma `Sensibilidade` do detector | 0% a 100%, padrão `50%` | A distância mínima entre cortes é fixa em 50 ms aqui |
| `Manter as fatias juntas` (interruptor) | Uma fatia que passa do começo da seguinte é cortada seco ali. Legenda: `Corta seco a fatia que a seguinte cobre, sem deixar rabo por baixo. Lacunas ficam em silêncio: o áudio nunca é esticado.` | Desligado | Desligado: a fatia deixa um rabo de até 10 ms que some com fade por baixo do ataque novo |
| Prévia | Onda com as linhas dos cortes e, no pé, as setas até o lugar novo | | |
| Resumo | `N fatias, M movidas (até X ms). As setas mostram para onde cada uma vai.` | | Sem transientes: `Nenhum transiente achado: não há o que quantizar. Aumente a sensibilidade.`; passando de 500: `Fatias demais (N; o máximo é 500). Diminua a sensibilidade.` |
| `Cancelar` / `Quantizar` | Fecha / aplica | `Quantizar` fica apagado com menos de 2 fatias | |

Como move: para cada fatia, a posição atual (em batidas, pelo mapa de andamento) vai para `posição + Força × (linha mais próxima − posição)`. O **começo do clipe** também é uma fatia e também vai à grade (um clipe que começa fora da grade anda). Nenhuma fatia vai para antes do zero.

O que faz com as emendas:

- **Fatias ainda coladas** ficam com a emenda de 2 ms de sempre (ver [Dividir](#dividir-por-transientes)).
- **Sobreposição** (a fatia anterior passou a cobrir o começo da seguinte): com `Manter as fatias juntas`, ela é cortada seca no começo da seguinte (com fade de 2 ms); sem ele, deixa um rabo de 10 ms por baixo do ataque novo, que some com fade. Uma fatia que ficaria com menos de 4 ms depois do corte não é cortada: as duas soam juntas.
- **Lacuna** (a anterior acaba antes de a seguinte começar, por mais de 2 ms): fica em silêncio nos dois casos.

O resultado resume: `N fatias, M movidas (até X,X ms).`, e, quando houve, `K fatias cortadas onde a seguinte entrou por cima.`, `K lacunas ficaram em silêncio (o áudio não é esticado).` e `K fatias curtas soam junto com a vizinha.`

## Quando é recusado (e por quê)

`Dividir`, `Remover silêncio` e `Quantizar` **recusam** clipe com warp ligado (e andamento do áudio conhecido), transposição diferente de 0 ou `Inverter o áudio`. No lugar dos controles, o diálogo mostra:

`Este clipe usa warp, transposição ou inversão. A edição por fatias trabalha no áudio original e ignora o warp; desligue o processamento em “Warp e altura…” antes de editar.`

O motivo: os cortes são pontos do arquivo original, e o som esticado, transposto ou invertido não cai nesses pontos; uma fatia ficaria fora do lugar no som processado. `Normalizar clipe…` **não** é recusado: ganho é ganho.

Outras recusas, com a mensagem no lugar dos controles: `Este áudio não está neste aparelho. Importe o arquivo de novo para editá-lo.` (áudio de outro aparelho, ainda sem o arquivo aqui); `O trecho deste clipe está fora do áudio.`; `O clipe não existe mais.`

## Passo a passo

**1. Cortar um loop de bateria por transientes e reorganizar** (4 compassos a 120 BPM, projeto em 120 BPM, sem warp)
1. Importe o loop (`Importar` ou `Ctrl+I`). Se o clipe tem warp, abra `Warp e altura…` e `Desligar o warp` antes (ver [03b](03b-warp-e-altura.md)).
2. Botão direito no clipe, `Editar áudio`, `Dividir por transientes…`. Deixe `Por transientes`, `Sensibilidade` 50% e `Distância mínima entre cortes` 50 ms. Confira a prévia: uma linha numerada em cada golpe que você quer separar. Se faltar o chimbal, suba a sensibilidade e solte o deslizante; se cortou no meio de uma nota longa, desça.
3. Toque `Dividir`. O aviso diz `Dividido em N fatias, com emendas de 2 ms sem mudar o som.` Toque `Fechar`: o som continua idêntico ao do loop.
4. Reorganize: arraste uma fatia pelo miolo (com o encaixe da grade ligado), `Duplicar` (`Ctrl+D`) a fatia da caixa, `Apagar` (`Delete`) a que sobra. Ao soltar uma fatia sobre outra, o trecho coberto da outra é aparado ([02b](02b-timeline-e-clipes.md)): deixe espaço livre.
5. Ouça. Se não gostou de tudo, `Ctrl+Z` volta passo a passo até o loop inteiro.

**2. Limpar os silêncios de uma voz**
1. Botão direito na voz, `Editar áudio`, `Remover silêncio…`.
2. Comece por `Limiar` −45 dBFS e `Silêncio mínimo` 400 ms: só pausas de verdade entram. A prévia escurece o que sai.
3. Se a sala tem ruído e quase nada escureceu, suba o `Limiar` para −40 ou −35 dBFS e solte. Se o fim das frases está sendo cortado, suba a `Margem depois do som` para 100 a 150 ms.
4. Toque `Remover`. O aviso diz `N trechos, X s removidos`.
5. As lacunas **ficam**: arraste cada trecho para fechar o buraco (não há "fechar lacunas" automático), ou use as lacunas como respiro e ouça.

**3. Normalizar vozes para o mesmo LUFS**
1. Para cada clipe de voz: botão direito, `Editar áudio`, `Normalizar clipe…`.
2. Escolha o chip `LUFS` e leve o `Alvo` a `−16,0 LUFS` (o padrão do chip é −14). Espere a barra de progresso acabar.
3. Leia `Medido: −20,5 LUFS (pico −8,0 dBFS)` e `Ganho do clipe: +4,5 dB (agora 0,0 dB)` (valores de exemplo) e toque `Normalizar`. Se aparecer `Limitado porque …`, o teto segurou: o clipe não chega ao alvo (ver [Normalizar clipe](#normalizar-clipe)).
4. Repita em cada voz com o **mesmo** alvo. Confira em `Ganho do clipe…` que o valor novo entrou.
5. Se uma voz vai ser cortada em pedaços, normalize **antes** de dividir: cada pedaço medido sozinho teria um ganho diferente.

**4. Quantizar uma bateria gravada**
1. Com a gravação sem warp e o projeto no andamento em que tocou, botão direito no clipe, `Editar áudio`, `Quantizar por fatias…`.
2. `Grade` `1/16` (ou `1/8` para um groove mais aberto). `Sensibilidade dos transientes` 50%. Veja na prévia as setas: as curtas são golpes quase certos; as longas são o que vai mudar.
3. Para manter a pegada humana, `Força` 70%; para travar, 100%. Ligue `Manter as fatias juntas` se ouvir um rabo de som duplicado depois de aplicar.
4. Toque `Quantizar` e leia o resumo (ex.: `36 fatias, 30 movidas (até 41,0 ms).`). Ouça com o metrônomo.
5. Não gostou? `Ctrl+Z` e refaça com outra `Força` ou `Grade`.

## Combina com

- [Warp e altura](03b-warp-e-altura.md): para **trazer um loop de outro andamento** ao projeto, use o warp; a edição por fatias só vale sem warp. Desligue o warp, transposição e inversão do clipe para editar; depois de editar, cada pedaço é um clipe separado, e ligar o warp de novo é por pedaço.
- [Áudio e clipes](03-audio-e-clipes.md): fades, `Ganho do clipe…` e `Duplicar` para reorganizar as fatias; `Crossfade neste clipe` depois de aproximar pedaços.
- [Sampler](04c-sampler.md#fatiar-sample): o mesmo detector, mas para tocar as fatias no teclado em vez de reorganizá-las na linha do tempo.
- [Gravação](03c-gravacao.md): clipes recém-gravados (voz, bateria) são os candidatos de `Remover silêncio` e `Quantizar por fatias`.
- [Exportação](08-exportacao.md#normalizar-o-loudness): `Normalizar clipe…` nivela **um clipe**; `Normalizar o loudness` na exportação nivela a **mixagem inteira**. Use os dois: o do clipe antes (igualar vozes), o da exportação no fim.
- Guia: [Editar áudio: dividir, quantizar e normalizar](../guias/editar-audio-dividir-quantizar-normalizar.md).

## Limites e pegadinhas

- **Um clipe por vez.** Não há seleção múltipla; cada ação vale para o clipe em que você abriu o menu.
- **Tetos.** No máximo **500 clipes por ação** (`Fatias demais (N; o máximo é 500)…`, `Trechos demais (N; o máximo é 500)…`); `N fatias iguais` vai de 2 a 96. Um corte a menos de 5 ms das pontas do clipe é descartado. O clipe não tem limite de duração, mas a prévia e o cálculo rodam no próprio app (na tela): um áudio muito longo demora a refazer a prévia `(não confirmado o tempo)`.
- **A `Distância mínima entre cortes` vale em todos os modos**, mesmo escondida: fora do modo `Por transientes` ela fica no último valor (50 ms na primeira abertura), então em `N fatias iguais` com fatias mais próximas que isso, ou em `Na grade` `1/32` acima de uns 150 BPM, alguns cortes somem e o resumo mostra o número real.
- **Nada é esticado.** `Quantizar por fatias` só move fatias; o que sobra entre elas é silêncio, e o que passa é cortado ou sobreposto. Serve para bateria tocada perto da grade; para adaptar um loop a outro andamento, use o warp.
- **Fatia que cai na grade com encaixe.** Cada fatia começa 2 ms antes do golpe; o encaixe da timeline alinha o início do clipe, não o golpe.
- **Desfazer.** Cada ação é um passo só, então `Ctrl+Z` volta tudo de uma vez. `Dividir`, `Remover silêncio` e `Quantizar` entram no histórico com o nome `Edição`; `Normalizar clipe` entra como `Ganho do clipe` `(lido do código)`. `Ctrl+Shift+Z` (ou `Ctrl+Y`) refaz a edição inteira.
- **Normalizar não protege contra clip.** Fora do `Pico`, o pico do clipe fica no máximo em 0 dBFS, mas os efeitos da faixa e o fader podem levar o som além; olhe o [medidor](06b-analisador-e-medidores.md).
- **LUFS de clipe mono ou com silêncio longo.** O clipe é medido sozinho (dois primeiros canais, com os gates do BS.1770), sem o pan e sem a soma com as outras faixas; o valor na mixagem pode ficar diferente do valor do clipe `(não confirmado com material real)`.
- **O áudio precisa estar no aparelho.** Sem ele, nenhuma das quatro ações abre (ver as recusas acima).
- **Sincronização e tamanho.** O resultado são clipes comuns no documento: até 500 clipes novos por ação entram no `.jopendaw` e na nuvem como qualquer outro clipe.

## Atalhos

Nenhum atalho próprio. Valem os do arranjo:

| Tecla | Ação |
|---|---|
| `Ctrl+Z` (`⌘+Z`) | Desfaz a edição inteira |
| `Ctrl+Shift+Z` ou `Ctrl+Y` | Refaz a edição inteira |
| `Ctrl+D` (`⌘+D`) | `Duplicar` a fatia selecionada |
| `Delete` | `Apagar` a fatia selecionada |
| `S` | `Cortar no cursor` (corte à mão, ao lado de `Dividir por transientes…`) |
