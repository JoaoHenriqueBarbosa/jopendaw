# Remix com warp e altura

> Traz uma música de outro andamento para o andamento do projeto (detectando o BPM, corrigindo a oitava com `÷2` e `×2`), transpõe o tom, faz um reverso de efeito, coloca uma batida por cima e exporta; cerca de 30 minutos, mais o tempo de ouvir e acertar de ouvido.

Os números abaixo são um exemplo: uma música de 100 BPM e 3:20 num projeto de 128 BPM. Troque pelos seus. Valores de nível e de efeito são pontos de partida, não regras do programa; o que depende do programa (rótulos, faixas de valor, limites do detector) vem do código.

## Ingredientes

| Recurso | Para quê aqui | Capítulo |
|---|---|---|
| `Importar áudio (Ctrl+I)` | Trazer a música para uma faixa de áudio | [03 Áudio e clipes](../manual/03-audio-e-clipes.md) |
| `Warp e altura…` (menu do clipe): `BPM do áudio`, `Detectar`, `÷2`, `×2`, `Ajustar ao andamento`, `ALTURA`, `Inverter o áudio` | Esticar ao andamento, transpor, reverso | [03b Warp e altura](../manual/03b-warp-e-altura.md) |
| `120 BPM · 4/4` (`Andamento e compasso`), `Metrônomo (C)`, `Loop (L)`, `Shift+L`, grade de encaixe | Fixar o andamento alvo, conferir o alinhamento, ensaiar um trecho | [02 Transporte](../manual/02-transporte.md) |
| `Cortar no cursor (S)`, `Duplicar`, `Duplicar a faixa`, mover com `Alt`, fades | Recortar a parte da música e montar o arranjo | [02b Timeline e clipes](../manual/02b-timeline-e-clipes.md) |
| Faixa `Bateria` e piano roll | A batida que entra por cima | [04b Bateria](../manual/04b-bateria.md), [05 Piano roll](../manual/05-piano-roll.md) |
| `Compressor` com `Sidechain`, `EQ` | Abrir espaço entre a música e a batida | [06d Referência dos efeitos](../manual/06d-efeitos-referencia.md), [06 Mixer](../manual/06-mixer.md) |
| `Exportar` | Tirar o WAV (o warp já processado é o que sai) | [08 Exportação](../manual/08-exportacao.md) |

Receitas relacionadas: a batida em si em [Primeira batida do zero](primeira-batida-do-zero.md) e o sidechain (receita 3) em [Efeitos em combinação](efeitos-em-combinacao.md).

## Passo a passo

### 1. O projeto e o andamento alvo

1. `Novo projeto`, `Nome` `Remix 128`, `Começar com` `Vazio`, `Criar`. O estúdio abre com uma faixa `Áudio 1`, que vai receber a música.
2. Toque em `120 BPM · 4/4`, digite `128` em `BPM`, `Salvar`. O remix inteiro vai seguir esse número: a música é esticada para ele, e a batida que você escrever também.

### 2. Importar

1. Cursor no compasso 1 (`Enter`) e a faixa `Áudio 1` selecionada.
2. `Ctrl+I` (`⌘+I` no Mac), escolha o arquivo (`wav`, `mp3`, `ogg`, `flac`, `m4a`, `aac`, `aif` e outros; alguns dependem do navegador). O clipe cai a partir do cursor, na faixa selecionada se ela é de áudio e está livre naquele ponto.
3. Aperte `Z` para enquadrar tudo e `Espaço` para ouvir. Ligue o metrônomo (`C`): o clique vai a 128 BPM e a música toca a 100, então os dois se afastam. É o que o warp vai resolver.

### 3. Detectar o andamento e esticar

1. Botão direito no clipe (toque longo no celular), `Warp e altura…`.
2. Toque em `Detectar` (o botão vira `Analisando…`). O detector estima o andamento do arquivo **inteiro** (só os primeiros 90 s contam) e preenche o campo `BPM do áudio`. A linha `Detectado: 100 BPM, confiança 87%` mostra o resultado, com confiança em %; abaixo de 35% o texto acrescenta `(baixa: confira de ouvido)`. Detectar já **liga o warp** com esse valor.
3. Espere o `processando…` acabar. O clipe passa a durar menos (100 ÷ 128 = 0,78 da duração original: 3:20 vira cerca de 2:36) e ganha o selo `W`. Por enquanto o clipe toca o original.
4. Confira a oitava de ouvido, com o metrônomo (`C`) ligado: cada clique deve cair numa batida da música (o bumbo, por exemplo). O detector procura entre 60 e 200 BPM e nos extremos pode devolver o dobro ou a metade do real (nunca outro valor). O exemplo de 100 BPM está na faixa em que ele é exato; nos extremos, a conta é esta:
   - o detector achou o **dobro** (140 para uma música de 70): a música é esticada demais e soa **arrastada**, uma batida dela a cada dois cliques. Use `÷2` (tooltip `Metade (÷2)`): ele divide o campo por 2 e já aplica;
   - o detector achou a **metade** (85 para uma música de 170): a música soa **corrida**, duas batidas dela por clique. Use `×2` (tooltip `Dobro (×2)`).
5. Se você **sabe** o andamento, digite direto no campo (aceita vírgula ou ponto, de 20 a 999, por exemplo `99,6`) e toque em `Ajustar ao andamento` (ou `Enter` no campo). `Desligar o warp` só aparece com o warp ligado e devolve o clipe à velocidade original, sem apagar o número.
6. Feche em `Fechar`. Tudo vale na hora e cada mudança é um passo do desfazer.

O clipe com warp tem sempre a mesma largura na linha do tempo, qualquer que seja o andamento do projeto (um segundo do áudio ocupa sempre a mesma fração de batida: a do andamento do próprio áudio). É o **som** que é refeito para caber. Se você mudar o `128` do projeto depois, o som se refaz sozinho cerca de 400 ms depois da última mudança.

### 4. Alinhar a primeira batida e conferir o fim

1. Com o metrônomo ligado, ouça o começo. Se a primeira batida forte da música não cai no clique do compasso 1 (há uma introdução sem batida, um respiro), apare o começo (arraste a borda esquerda com `Alt`, sem encaixe): o som fica no lugar e o começo do clipe avança até a batida. Depois arraste o clipe (com a grade em `Compasso`) para o compasso 1. Se a batida cai um pouco antes ou depois do clique, mova o clipe segurando `Alt` para ajustar sem grade; o clipe não vai para antes do compasso 1, então para adiantar a música apare o começo. Aproxime a régua (`+`) para ver melhor.
2. Vá até o fim da música (`Espaço` num ponto avançado, ou clique na régua) e confira se as batidas ainda caem nos cliques. O detector arredonda a 0,1 BPM e não é exato em música tocada por gente (andamento que varia): um erro pequeno vai acumulando. Se o fim está adiantado ou atrasado, refine o `BPM do áudio` com casas decimais (por exemplo, de `100` para `99,8`) e `Ajustar ao andamento`.
3. Para material longo com andamento que oscila, é mais seguro trabalhar em pedaços: corte o clipe (`S` no cursor) nas seções e dê a cada pedaço o seu `BPM do áudio`.

### 5. Recortar o que interessa

1. Ponha o cursor no começo do trecho que vai usar (com a grade em `Compasso`, clique na régua) e aperte `S`. Repita no fim. Sem clipe selecionado, `S` corta o que o cursor cruza na faixa selecionada; com um selecionado, corta ele. Cada corte deixa dois clipes independentes com o mesmo warp.
2. Selecione o que sobrou de fora e apague com `Delete` (deixa o vão).
3. Selecione o trecho bom e aperte `Shift+L`: o loop passa a cobrir exatamente o clipe e liga. Ensaie o remix em cima dele.

### 6. Transpor o tom

1. Botão direito no clipe, `Warp e altura…`, seção `ALTURA`. O botão `+` (tooltip `Um semitom acima`) sobe 1 semitom por clique; o `−` (tooltip `Um semitom abaixo`) desce. A leitura mostra `+3 st`. `Zerar` volta a 0.
2. Exemplo: sua base nova está em Dó menor e a música original em Lá menor. De Lá a Dó são 3 semitons acima: toque `+` três vezes. O app não detecta o tom: a leitura do tom é de ouvido, ou com um afinador.
3. Espere o `processando…`. A transposição vai de −24 a +24 semitons, só de 1 em 1 pela interface (não há ajuste fino em cents), e **não muda a duração**. Não precisa do warp ligado para transpor.
4. Pequenas transposições (1 a 3 semitons) costumam soar melhor que as grandes; em voz falada ou cantada, transposições grandes mudam também o timbre, porque o método reamostra e não preserva formantes (consequência do método, não medida) `(não confirmado o quanto incomoda)`.

### 7. Reverso como efeito (subida antes da virada)

O reverso vira o áudio de trás para a frente. Uma cauda de prato que decai vira uma subida que estoura na batida. Para usar a cauda do prato da própria música na virada do compasso 33:

1. No cabeçalho da faixa da música, abra `Opções da faixa` (três pontos) e escolha `Duplicar a faixa`. A cópia (`Áudio 1 (2)`) fica selecionada e traz o clipe com o warp; a original fica intacta.
2. Clique no clipe da **cópia** para selecioná-lo (assim o `S` corta ele, e não o da faixa original). Ponha o cursor no compasso 33 (a virada; com a grade em `Compasso`, clique na régua) e aperte `S`. Clique no pedaço da direita, ponha o cursor no compasso 34 e aperte `S` de novo. O pedaço do meio, de um compasso, contém o prato que decai. Selecione cada um dos outros dois pedaços da cópia e apague (`Delete`).
3. Botão direito no trecho, `Warp e altura…`, ligue `Inverter o áudio`. O reverso puro fica pronto quase na hora. O que era o fim vira o começo.
4. Arraste o clipe (com a grade em `Compasso`) para que **termine** no compasso 33, ou seja, começando no 32. Você ouve o prato ao contrário, crescendo até o compasso 33, onde a música volta com o golpe original.
5. Na alça de fade in do clipe (círculo branco no canto de cima à esquerda), puxe um fade curto para o começo entrar sem estalo; o fade in fica no começo do clipe, mesmo invertido, e o fade out no fim.

Duplicar a **faixa** (em vez de duplicar o clipe) evita que a cópia caia em cima do clipe seguinte e aparé-lo: `Duplicar` põe a cópia logo depois do clipe e o que ela cobre é aparado.

### 8. Sobrepor uma batida

1. `Faixa` > `Bateria`; no seletor `Kits de bateria`, `909`. Dois cliques no vazio da raia, no compasso 1, para criar um clipe; o bumbo em toda batida (`Bumbo`), a `Caixa` na 2 e na 4, o chimbal aberto no contratempo (é a receita de [Primeira batida do zero](primeira-batida-do-zero.md)), e `Ctrl+A` seguido de `Ctrl+D` para repetir o compasso.
2. Como as notas são em batidas, a bateria já segue os 128 BPM do projeto, o mesmo alvo da música esticada. Ouça as duas juntas e mova o clipe da bateria (grade `Compasso`) até a batida nova cair junto com a música.
3. Abaixe a faixa da música uns 3 dB (fader no mixer, `X`) para dar folga à batida. Se o grave da música e o do bumbo brigam, ponha um `EQ` na faixa da música com o preset `Corte de graves` e suba a `Frequência` da banda 1 para 100 a 120 Hz (isso tira o grave original: só faça se a batida nova vai fornecer o grave).
4. Para a música respirar no ritmo do bumbo, use o sidechain: passe o bumbo para uma faixa `Bateria` só dele (a bateria toda numa faixa só dispararia o compressor com todas as peças; as outras peças ficam em outra faixa `Bateria`). Na faixa da música, adicione um `Compressor` com `Sidechain` apontando para a faixa do bumbo: é a receita 3 de [Efeitos em combinação](efeitos-em-combinacao.md), com a música no lugar do pad.
5. Como alternativa à bateria MIDI, importe um loop de bateria em WAV (`Ctrl+I`) e passe pelo mesmo `Warp e altura…` (`Detectar`, quase sempre com confiança alta em material rítmico limpo).

### 9. Exportar

1. Toque em `Exportar`. Se algum clipe ainda está processando o warp, a barra mostra `Processando o warp…` e a exportação espera: o que soa é o que exporta.
2. `Música inteira`, `WAV 24 bits`, `Cauda` 2 s; `Exportar`. Aparecem `Renderizando N%` e o arquivo `Remix 128.wav`.

## Variações

- **Só mudar o andamento do remix.** Troque o `128` de `120 BPM · 4/4` por outro número: o som dos clipes com warp se refaz sozinho e a bateria acompanha. Teste 124 e 128 sem mexer no resto.
- **Sample transposto.** Um trecho de voz ou de instrumento em outra faixa de áudio, cortado (`S`), com `+5 st` (uma quarta acima), sob a batida: dá um segundo tom ao remix sem gravar nada.
- **Só o reverso.** Em vez de duplicar a faixa, importe um prato (ou uma palma) como arquivo e ligue `Inverter o áudio` nele; arraste o clipe até terminar no ponto da virada.
- **Loop de 8 compassos para ensaiar.** Depois de cortar o trecho bom (passo 5), `Shift+L` liga o loop nele; com o loop rodando, teste cada valor de `+`/`−`.

## Por que funciona

- **Warp por razão de andamento.** O clipe é esticado por (BPM do áudio ÷ BPM do projeto); com isso as batidas da música caem nas batidas do projeto e a bateria escrita em batidas encaixa sem esforço. A razão fica entre 0,25 e 4.
- **Esticar preserva os transientes.** O método corta o áudio em janelas de cerca de 40 ms, escolhe o melhor ponto de emenda e reemenda as janelas sem alterar a forma de onda; por isso bumbo e caixa continuam nítidos. Fica melhor com razões entre 0,5 e 2, nos loops de bateria e trechos rítmicos.
- **O detector procura a periodicidade dos ataques**, não o tom nem a melodia. Onde há batida regular, ele acerta; onde não há (pad, tom sustentado, ruído), ele diz que não achou. A ambiguidade entre 60 e 120 (ou 100 e 200) é a "oitava" que `÷2` e `×2` resolvem.
- **Transpor e esticar são operações separadas** no motor: a transposição estica pela razão de altura e depois reamostra. Fazer as duas juntas dobra o trabalho, e é por isso que o `processando…` de um clipe com as duas leva mais tempo.
- **O original não muda.** O que o warp gera é um áudio derivado, guardado só no aparelho (cache); em outro aparelho ele se refaz a partir do original. Mexer nos valores nunca degrada o arquivo.

## Se der errado

| Sintoma | Causa provável | Como resolver |
|---|---|---|
| `Não deu para achar o andamento (pouca batida ou trecho curto). Digite o andamento do áudio.` | O detector não achou batida: o áudio tem menos de 3 s, é um pad, um tom, ruído ou música muito esparsa | Digite o BPM à mão e toque em `Ajustar ao andamento` (ou use um trecho com bateria) |
| `Detectado: ... (baixa: confira de ouvido)` | Confiança abaixo de 35%: material com pouca batida ou andamento que varia | Confira com o metrônomo; se não bate, digite o valor certo |
| A música soa a metade ou o dobro da velocidade | Erro de oitava do detector (nos extremos, por volta de 65 ou acima de 170 BPM) | `÷2` ou `×2` |
| O começo bate e o fim sai do clique | O andamento real é uma fração diferente (o detector arredonda a 0,1 BPM) ou a música oscila | Refine o `BPM do áudio` com decimais; ou corte em pedaços com um valor cada |
| Som "tremulado" (flutter) em acordes e mixagens densas | O esticamento junta janelas de áudio com muita informação simultânea; razões extremas pioram | Aproxime os andamentos (razão entre 0,5 e 2), ou use um trecho mais rítmico e menos polifônico |
| A voz muda de timbre depois de transpor | O método não preserva formantes | Transponha menos (1 a 3 semitons) ou use outra fonte |
| `processando…` demora | Material longo, ou warp e altura juntos | Espere: o clipe toca o original até ficar pronto. Trabalhe em pedaços cortados |
| `O warp não ficou pronto (...): o clipe toca o original.` (selo com borda vermelha) | Falha na geração; o motivo vem entre parênteses, por exemplo `O áudio original não está neste aparelho.` | Abra o projeto no aparelho que tem o áudio, ou reimporte o arquivo |
| `Pare a gravação para mudar o warp.` | O warp não muda durante a gravação | Pare a gravação |
| O botão `Detectar` diz `O áudio deste clipe não está neste aparelho.` | O clipe veio da nuvem e o áudio ainda não desceu | Espere o ícone de nuvem ficar `Sincronizado` ([Trabalhar em dois aparelhos](trabalhar-em-dois-aparelhos.md)) |
| O warp de um clipe volta ao original em outro aparelho | O derivado não sobe à nuvem: cada aparelho refaz o seu | Espere o `processando…` acabar no outro aparelho |
| O detector deu um andamento estranho em música ao vivo | Andamento que varia (bateria humana, rubato) | Confira de ouvido e digite; o detector foi testado só com material sintético `(não confirmado além dos testes do motor)` |

### Limites do detector, em resumo

- Procura entre **60 e 200 BPM**; só os primeiros **90 s** do arquivo (o arquivo inteiro, não só o trecho que o clipe mostra); exige pelo menos **3 s** de áudio.
- Rejeita silêncio, tom puro, ruído branco e pad de acordes; exige ataques claros e em quantidade.
- Nos testes do motor (bumbo, caixa e chimbal sintéticos), acerta com erro menor que 0,5 BPM de 75 a 140 BPM e, nos extremos, pode devolver o dobro ou a metade, nunca outro valor.
- É uma estimativa de **um** andamento fixo para o arquivo: música com mudança de andamento pede pedaços separados.
