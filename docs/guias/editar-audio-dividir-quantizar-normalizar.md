# Editar áudio: dividir, limpar silêncios e nivelar

> Três trabalhos de edição de áudio resolvidos dentro do app, sem tocar no arquivo: fatiar um loop de bateria pelos golpes e reorganizar, tirar os silêncios longos de uma voz e levar várias vozes ao mesmo LUFS; cerca de 10 a 15 minutos por cenário.

Os números são exemplos (loop a 100 BPM em 4/4, 1 batida = 0,6 s; voz de 5 minutos; três vozes de um podcast). Troque pelos seus. Rótulos, faixas de valores, padrões e mensagens vêm do código; **nada disto foi visto nem ouvido rodando** (o capítulo [03e](../manual/03e-editar-audio.md) e este guia foram escritos lendo `audio_edit.dart`, `audio_edit_ui.dart` e os testes `(testado só por testes automáticos)`), e os valores musicais (sensibilidade, limiar, alvo) são pontos de partida para acertar de ouvido.

## Ingredientes

| Recurso | Para quê aqui | Capítulo |
|---|---|---|
| Menu do clipe de áudio (botão direito; toque longo no celular) › `Editar áudio` | Abre o segundo menu com as quatro ações | [03e Editar áudio](../manual/03e-editar-audio.md#onde-fica) |
| `Dividir por transientes…` (`Por transientes`, `N fatias iguais`, `Na grade`) | Cortar o clipe em pedaços sem mudar o som | [03e Dividir](../manual/03e-editar-audio.md#dividir-por-transientes) |
| `Remover silêncio…` (`Limiar`, `Silêncio mínimo`, margens, `Fade nos cortes`) | Tirar as pausas longas e deixar a lacuna | [03e Remover silêncio](../manual/03e-editar-audio.md#remover-silêncio) |
| `Normalizar clipe…` (`Pico`, `RMS`, `LUFS`) | Levar o `Ganho do clipe` a um alvo medido | [03e Normalizar clipe](../manual/03e-editar-audio.md#normalizar-clipe) · [03 Ganho do clipe](../manual/03-audio-e-clipes.md#ganho-do-clipe) |
| `Duplicar` (`Ctrl+D`), `Apagar` (`Delete`), arrastar pelo miolo, `Alt` (sem encaixe), `Ctrl+Z` | Reorganizar as fatias e desfazer | [03 Áudio e clipes](../manual/03-audio-e-clipes.md) · [02b Timeline e clipes](../manual/02b-timeline-e-clipes.md) |
| `Warp e altura…` (`Desligar o warp`, `Zerar`, `Inverter o áudio`) | Desligar o que faz o clipe ser recusado | [03b Warp e altura](../manual/03b-warp-e-altura.md) |
| `Normalizar o loudness` da exportação (chip `Podcast −16,0`) | Acertar a mixagem inteira no fim | [08 Exportação](../manual/08-exportacao.md#normalizar-o-loudness) |

## Antes de começar

- **Clipe sem warp, sem transposição e sem inversão.** `Dividir`, `Remover silêncio` e `Quantizar` recusam o clipe (`Este clipe usa warp, transposição ou inversão…`). Em `Warp e altura…`: `Desligar o warp`, `Zerar` na altura e `Inverter o áudio` desligado. `Normalizar clipe…` vale em qualquer clipe.
- **O áudio precisa estar neste aparelho.** Senão: `Este áudio não está neste aparelho. Importe o arquivo de novo para editá-lo.`
- **Cada ação é um passo do desfazer.** `Ctrl+Z` volta a ação inteira; experimente à vontade.
- **Os pedaços são clipes comuns.** Mover um pedaço por cima de outro apara o que ele cobre ([02b](../manual/02b-timeline-e-clipes.md#limites-e-pegadinhas)): deixe espaço livre.

## Cenário 1: um loop de bateria fatiado e reordenado

**Resultado:** um loop de 2 compassos separado em um clipe por golpe, com o último compasso mudado (a caixa do tempo 4 repetida no contratempo, no lugar do chimbal), e o som idêntico ao do loop onde você não mexeu. Sensibilidade de partida: **50%**.

Ponto de partida: um loop de bateria de 2 compassos a 100 BPM (4,8 s), bumbo nos tempos 1 e 3, caixa nos 2 e 4 e chimbal em colcheias: 16 golpes. Projeto em 100 BPM, clipe sem warp.

1. Importe o loop (`Importar` ou `Ctrl+I`) e ponha o clipe no compasso 1.
2. Botão direito no clipe, `Editar áudio`, `Dividir por transientes…`. Deixe `Por transientes`, `Sensibilidade` 50% e `Distância mínima entre cortes` 50 ms.
3. Olhe a prévia: uma linha numerada em cada golpe. Conte: 15 linhas dão 16 fatias. Se faltam linhas no chimbal, arraste `Sensibilidade` para 70% e **solte** (a prévia só é refeita ao soltar); se aparecem linhas no meio do decaimento de um prato ou do bumbo, desça para 35%.
4. Toque `Dividir`. O aviso diz `Dividido em 16 fatias, com emendas de 2 ms sem mudar o som.` Toque `Fechar` e ouça o loop: deve soar como antes.
5. Apague o chimbal do fim: selecione o último clipe (o golpe em 4,5 do compasso 2, batida 7,5) e aperte `Delete`.
6. Selecione a fatia da caixa do tempo 4 do compasso 2 (agora a última, no começo da batida 7) e aperte `Ctrl+D`. A cópia cai logo depois dela, exatamente no espaço que você liberou, e a caixa passa a soar no 4 e no "e" do 4.
7. Ouça o loop com o metrônomo. Se a caixa do contratempo estiver alta demais, abra `Ganho do clipe…` na cópia e ponha −4 dB.

### Variações

- **Fatias exatas em batidas.** Em vez de `Por transientes`, escolha `Na grade` com `1/4`: um corte por batida (8 fatias de 0,6 s), para trocar compassos de lugar arrastando com o encaixe da grade.
- **Loop tocado solto, em vez de programado.** Em vez de reorganizar, use `Quantizar por fatias…` (`Grade` `1/16`, `Força` 100%): cada golpe vai para a linha mais próxima. Ver o [capítulo 03e](../manual/03e-editar-audio.md#quantizar-por-fatias) e a receita 4 de lá.
- **Reorganizar no teclado em vez de na linha do tempo.** Para tocar as fatias como notas, o caminho é `Fatiar sample…` do sampler: [Sampler multi-zona e fatiar loops](sampler-multi-zona-e-fatiar-loops.md).

### Por que funciona

O detector é o mesmo do fatiamento do sampler: ele procura saltos de energia e recua cada corte até o começo do ataque (e até o cruzamento de zero mais próximo, até 2 ms), então cada fatia começa no golpe, e não no meio dele. Cada fatia é um clipe que aponta para o mesmo arquivo e começa 2 ms antes do corte, com um fade de 2 ms que emenda com a fatia anterior: como elas ficam coladas, o som em sequência é o do loop original. A cópia por `Ctrl+D` cai no fim do clipe, por isso apagar o vizinho antes libera o lugar certo.

O que merece atenção: a curva dessa emenda de 2 ms é a `Suave (padrão)` (`x²`), e não uma rampa reta: no meio dos 2 ms os dois lados somam 0,5 em amplitude, uma queda curtíssima (cerca de −6 dB) que em bateria não se ouve, mas que pode aparecer em nota sustentada `(lido do código; não ouvido)`. Se você ouvir um pequeno "tum" numa emenda de nota longa, junte de novo com `Ctrl+Z` e corte só onde há golpe.

### Se der errado

| Sintoma | Causa provável | O que fazer |
|---|---|---|
| A prévia mostra `Nenhum transiente achado: tente mais sensibilidade, fatias iguais ou a grade.` | Loop sem ataques claros (pad, ruído) ou sensibilidade baixa | Suba a `Sensibilidade`, ou use `N fatias iguais` (16) ou `Na grade` |
| Linha no meio de um prato ou de um bumbo longo | Sensibilidade alta demais | Desça a `Sensibilidade`, ou suba a `Distância mínima entre cortes` para 150 ms |
| Alguns cortes sumiram em `N fatias iguais` ou `Na grade` `1/32` | A `Distância mínima entre cortes` (50 ms) segue valendo mesmo escondida | Use uma grade maior, ou abra o modo `Por transientes`, mude o valor e volte |
| Ao soltar uma fatia, a vizinha ficou mais curta | Mover um clipe apara o que ele cobre | `Ctrl+Z`; deixe espaço livre ou use uma segunda faixa como mesa de trabalho |
| Com o encaixe da grade o golpe cai um pouco depois da linha | A fatia começa 2 ms antes do golpe; o encaixe alinha o início do clipe | Normal (2 ms); se incomodar, arraste com `Alt` e confira de ouvido |
| O diálogo mostra `Este clipe usa warp, transposição ou inversão…` | O clipe tem processamento | `Warp e altura…`: `Desligar o warp`, `Zerar`, desligue `Inverter o áudio` |

## Cenário 2: uma voz sem os silêncios longos

**Resultado:** uma narração de 5 minutos sem as pausas de mais de meio segundo, mantendo um respiro natural de cerca de 300 ms. Ponto de partida: **`Limiar` −45 dBFS**, **`Silêncio mínimo` 500 ms**, **`Margem antes do som` 100 ms**, **`Margem depois do som` 200 ms**.

Ponto de partida: um clipe de voz gravado num quarto calmo (ruído de fundo por volta de −55 dBFS), sem warp.

1. Botão direito na voz, `Editar áudio`, `Remover silêncio…`.
2. Ponha `Silêncio mínimo` em 500 ms, `Margem antes do som` em 100 ms e `Margem depois do som` em 200 ms (solte cada deslizante para a prévia refazer). Deixe `Limiar` em −45 dBFS e `Fade nos cortes` em 5 ms.
3. Veja a prévia: os trechos removidos aparecem escurecidos e o texto diz, por exemplo, `23 trechos, 47,3 s removidos (a parte apagada da onda). A lacuna fica: o resto do clipe não se move.` (valores de exemplo). Se quase nada escureceu, o ruído da sala está acima do limiar: suba `Limiar` para −40 e depois −35 dBFS; se escureceu até o meio de palavras baixas, desça.
4. Toque `Remover`. O aviso repete o resumo. Toque `Fechar`.
5. As lacunas ficam (não há "fechar buracos" automático). Para fechar: com o encaixe desligado (segure `Alt` ao arrastar), arraste cada trecho para a esquerda até encostar no fim do anterior. Encostados, sobra um respiro de cerca de **300 ms** (200 ms de margem depois do som + 100 ms de margem antes do seguinte), em vez das pausas longas.
6. Ouça as emendas. Se uma palavra perdeu o ataque, desfaça (`Ctrl+Z`) e suba a `Margem antes do som`.

### Variações

- **Só tirar o começo e o fim mudos.** Ponha `Silêncio mínimo` em 2 s (o máximo do controle): só saem os silêncios de 2 s ou mais (inclusive o do começo e o do fim do clipe, se tiverem essa duração).
- **Sincronizada com outra coisa (vídeo, música).** Deixe as lacunas: o resto do clipe não se move, então o que vem depois continua no tempo original.
- **Sala mais barulhenta.** Com ruído de sala em −35 dBFS, use `Limiar` −30 dBFS e confira em cada pausa; se cortar sílabas finais, suba a `Margem depois do som`.

### Por que funciona

O app olha o **pico de cada bloco de 1 ms** (o maior entre os canais, no áudio original, sem o ganho do clipe) e chama de silêncio uma sequência de blocos abaixo do limiar que dure pelo menos o `Silêncio mínimo`. Cada silêncio encolhe pelas margens antes de ser removido: por isso as palavras mantêm o ataque e o rabo: de uma pausa de 1 s saem 700 ms e ficam 300 ms de margem. Um silêncio mais curto que o mínimo (um respiro entre palavras) nem é considerado. Cada trecho mantido é um clipe no mesmo lugar, com fade de 5 ms nos cortes, então não há estalo.

### Se der errado

| Sintoma | Causa provável | O que fazer |
|---|---|---|
| `O clipe todo está abaixo do limiar: nada seria mantido. Suba o limiar ou diminua o silêncio mínimo.` | `Limiar` acima do nível da voz (mensagem de erro, nada é apagado) | Desça o `Limiar` |
| `Nenhum silêncio com esses ajustes.` | `Silêncio mínimo` longo demais, margens maiores que as pausas ou ruído acima do limiar | Desça o `Silêncio mínimo`, diminua as margens ou suba o `Limiar` |
| `Trechos demais (N; o máximo é 500). Aumente o silêncio mínimo.` | Muitos cortes num áudio longo | Suba o `Silêncio mínimo`, ou divida o clipe antes em partes |
| O som ficou "picotado" | Silêncio mínimo curto demais para a fala | Suba para 400 a 500 ms e as margens para 100/200 ms |
| Clique numa emenda | Fade curto demais no corte | Suba `Fade nos cortes` para 10 a 20 ms; ou `Ctrl+Z` e refaça |

## Cenário 3: um conjunto de vozes com o mesmo LUFS

**Resultado:** a voz do apresentador e dos dois convidados, gravadas em níveis diferentes, nivelam no mesmo **−16 LUFS** cada uma, para o mix ficar equilibrado antes dos efeitos. Alvo: **`LUFS` −16,0** (o de podcast).

Ponto de partida: três clipes de voz em três faixas (`Apresentador`, `Convidada A`, `Convidado B`), sem edição por fatias ainda. Valores de exemplo: `Medido: −23,1 LUFS (pico −9,0 dBFS)`, `−19,8 LUFS (pico −6,5 dBFS)` e `−26,4 LUFS (pico −12,0 dBFS)`.

1. Numa voz: botão direito no clipe, `Editar áudio`, `Normalizar clipe…`.
2. Escolha o chip `LUFS` e leve o deslizante `Alvo` a `−16,0 LUFS` (o padrão do chip é −14,0; passo de 0,5). Espere a barra de progresso.
3. Leia as duas linhas: `Medido: −23,1 LUFS (pico −9,0 dBFS)` e `Ganho do clipe: +7,1 dB (agora 0,0 dB)`. Sem aviso de `Limitado porque…`, o alvo será atingido (o pico vai a −1,9 dBFS). Toque `Normalizar`: `Ganho do clipe: +7,1 dB. LUFS medido: −23,1 LUFS; alvo: −16,0 LUFS.`
4. Repita nas outras duas vozes com o mesmo alvo: a convidada A dá `+3,8 dB` e o convidado B `+10,4 dB` (pico a −1,6 dBFS).
5. Confira em `Ganho do clipe…` de cada clipe: o valor novo entrou. O volume da faixa (fader) continua à parte.
6. Toque as três falas seguidas e ajuste só os faders para o gosto: agora a diferença que sobra é de timbre e sala, não de nível. No fim, exporte com `Normalizar o loudness` no chip `Podcast −16,0` (veja [Loudness e master](loudness-e-master.md)).

### Variações

- **Só o pico (sem medir loudness).** Chip `Pico`, alvo −1,0 dBFS (padrão): serve para deixar tomadas de nível parecido; não iguala o volume percebido, porque uma voz com picos de consoante parece mais baixa que outra sem eles.
- **`RMS` −18.** Mede a média de energia do trecho sem a ponderação de frequência do LUFS (`−18,0 dBFS` é o padrão do chip); mais simples, mas igualar RMS não iguala o volume percebido quando o timbre difere.
- **Voz dividida em pedaços.** Normalize **antes** de dividir: cada pedaço medido sozinho teria um ganho diferente.

### Por que funciona

O `Normalizar clipe…` mede o trecho que o clipe toca no áudio original (sem fader, pan nem efeitos) com a mesma conta de loudness integrado da exportação (BS.1770, com os gates de −70 LUFS e de 10 LU) e ajusta o `Ganho do clipe` para levar a medida ao alvo: o ganho novo **substitui** o antigo, então repetir a operação dá sempre o mesmo resultado. Como o volume percebido das três vozes fica igual já na fonte, o mix não depende de um fader compensando diferenças de 7 a 10 dB. O loudness medido é o **do clipe**, sozinho: depois de efeitos diferentes por faixa (compressor numa voz e não na outra) os valores na mixagem podem divergir, e a exportação com `Normalizar o loudness` leva a mixagem toda ao alvo no fim.

### Se der errado

| Sintoma | Causa provável | O que fazer |
|---|---|---|
| Aparece `Limitado porque o pico do clipe chegou a 0 dBFS antes do alvo: o alvo não será atingido.` | Voz com picos altos e nível médio baixo (ex.: −24 LUFS com pico −3 dBFS pede +8 dB, que levaria o pico a +5 dBFS; o ganho fica em +3 dB) | Aceite o ganho menor, ou comprima a voz na faixa (ver [Efeitos em combinação](efeitos-em-combinacao.md), cadeia vocal) e normalize de novo |
| `Limitado porque o ganho do clipe vai até +12 dB` | Gravação muito baixa | Regrave com mais nível, ou aceite (o teto do `Ganho do clipe` é +12 dB) |
| `Não deu para medir o LUFS: o trecho tem menos de 400 ms ou está muito baixo. Use o pico ou o RMS.` | Clipe curto demais ou quase mudo | Use `Pico` ou `RMS` neste clipe |
| `O trecho do clipe está em silêncio: não há o que normalizar.` | Pico abaixo de cerca de −140 dBFS | Confira se é o clipe certo |
| Depois de normalizar uma voz, o `Ganho do clipe…` mostra o valor, mas a voz ainda parece mais baixa | O LUFS mede energia ponderada, não o timbre: uma voz com mais agudos pode parecer mais alta ou mais baixa | Acerte de ouvido com o fader da faixa |
| O mix final ficou acima ou abaixo de −16 LUFS | Vozes que falam juntas somam mais que −16; efeitos mudam o nível | Use `Normalizar o loudness` na exportação, que mede a mixagem ([08](../manual/08-exportacao.md#normalizar-o-loudness)) |
