# Ferramentas MIDI (menu Ferramentas do editor de notas)

> Um menu de transformações prontas para as notas de um clipe: escolher uma escala, montar acordes, arpejar, humanizar, inverter, esticar o tempo e limpar; use quando escrever nota por nota ficaria lento ou repetitivo.

## Onde fica

Dentro do [editor de notas](05-piano-roll.md), na barra de ferramentas, o botão `Ferramentas` (ícone de varinha; tooltip `Ferramentas de produtor: escala, acordes, arpejo, humanizar e transformações das notas`). Ao lado dele, em faixa melódica, fica o botão `Escala`. Nada disso aparece com o clipe fechado.

O menu tem cinco submenus: `Escala e acordes`, `Seleção`, `Escalar o tempo`, `Cortar e limpar` e `Fantasmas`. Itens que não se aplicam ao momento aparecem apagados (sem notas no clipe, sem nada selecionado, faixa de bateria).

Regras que valem para o menu inteiro:

- **Sobre quais notas atua.** As transformações agem na **seleção**; **sem seleção, em todas as notas do clipe**. Onde a tabela diz "só seleção", o item fica apagado enquanto nada estiver selecionado.
- **Desfazer.** Cada ferramenta é uma edição só no histórico: um `Ctrl+Z` desfaz tudo o que ela fez. Se o resultado seria idêntico ao que já existe, nada é gravado.
- **Depois de aplicar**, as notas resultantes ficam selecionadas e a tela rola até elas se estiverem fora de vista.
- **Pontos de controle.** Um clipe também guarda pontos de pitch bend, modulação e sustain (faixa de controle do editor). Nenhum item novo entrou no menu por causa deles, mas dois itens passaram a levá-los junto das notas (`Escalar o tempo` e `Inverter no tempo`); o resto do menu só mexe em notas. O quadro completo está em [Os controles nas ferramentas](#os-controles-nas-ferramentas).
- **Notação dos exemplos.** `C4@0(1)` é a nota C4 começando no tempo 0 do clipe, com 1 tempo de duração (1 tempo = uma semínima; um compasso 4/4 tem 4 tempos). `[C4 E4 G4]@0(4)` são três notas juntas, no tempo 0, com 4 tempos. Os nomes de nota usam sustenidos (`D#4`, nunca `Eb4`); C4 é o dó central (MIDI 60). Os números com vírgula são decimais.

## Controles

### Os controles nas ferramentas

Os pontos de `Pitch bend`, `Modulação` e `Sustain` do clipe (ver [Faixa de controle](05-piano-roll.md#faixa-de-controle)) têm batidas contadas do início do clipe, como as notas. Este quadro diz o que cada operação faz com eles.

| Operação | O que acontece com os pontos de controle | Detalhe |
|---|---|---|
| `Escalar o tempo` › `×0,5 (metade)`, `×2 (dobro)` e `Personalizado…` | **Escalados** pelo mesmo fator, a partir do início da primeira nota alvo (a que fica parada) | Sem seleção, todos os pontos do clipe; com notas selecionadas, só os pontos entre o início da primeira e o fim da última nota selecionada (as bordas contam). O fator vale para os pontos mesmo com `Escalar as durações também` desmarcado. Nenhum ponto passa para antes do começo do clipe: os que ficariam antes do 0 param no 0 |
| `Inverter no tempo` | **Espelhados** no trecho ocupado pelas notas alvo (do menor início ao maior fim): a curva de bend e de modulação toca de trás para frente | O `Sustain` **não** é espelhado (cada "desce" viraria "sobe" e o que era segurado passaria a soltar). Pontos fora do trecho ficam onde estão |
| `Dividir no cursor` (`K`) | **Nada**: só corta notas. Os pontos continuam no mesmo clipe, onde estavam | Para cortar também os pontos, divida o clipe na linha do tempo (`Cortar no cursor`, tecla `S`; ver abaixo) |
| `Unir notas iguais adjacentes`, `Remover duplicadas`, `Aparar sobrepostas` | Nada | `Aparar sobrepostas` encurta **notas** da mesma altura; não tem relação com aparar o clipe |
| `Humanizar…`, `Rampa de velocidade`, `Legato`, `Staccato…`, `Inverter na altura`, `Reverter a ordem das notas`, `Dividir colcheias em 3 notas`, arpejo, acordes e `Prender seleção na escala` | Nada | Os pontos não acompanham notas que mudam de lugar por essas ferramentas |
| `Quantizar` (`Q`), setas, arrastar notas | Nada | Um bend desenhado numa nota não anda com ela |
| Copiar, recortar, colar e duplicar notas (`Ctrl+C`, `Ctrl+X`, `Ctrl+V`, `Ctrl+D`) | Nada: a área de transferência guarda só notas | Para repetir um bend junto do trecho, duplique o clipe inteiro na linha do tempo ou redesenhe |

Como os itens de `Escalar o tempo` e `Inverter no tempo` agem sobre "as notas alvo", eles ficam apagados num clipe **sem notas**, mesmo que ele tenha pontos de controle.

**Na linha do tempo** (não são itens do menu `Ferramentas`, mas decidem o destino dos pontos):

| Operação | O que acontece com os pontos de controle |
|---|---|
| `Cortar no cursor` (`S`, também no menu do clipe) | Divide os pontos junto do clipe: os anteriores ao corte ficam no clipe da esquerda; os demais vão para o da direita, com a batida recontada a partir do corte. O controle que estava fora do repouso no corte (pedal embaixo, bend ou modulação fora do centro) **começa o clipe da direita com o mesmo valor**, a menos que já haja um ponto exatamente no começo dele |
| `Duplicar` (`Ctrl+D`) | A cópia leva os pontos |
| Mover o clipe | Os pontos vão junto (as batidas deles são relativas ao clipe) |
| Aparar a borda esquerda | Os pontos são deslocados como as notas: ficam no mesmo lugar do arranjo. Os que passam a ficar antes do início do clipe ficam guardados, mudos, e voltam se você estender o clipe de novo (ou desfizer) |
| Aparar a borda direita | Só muda a duração; pontos depois do novo fim ficam guardados e mudos |
| Sobrepor (soltar, colar ou gravar um clipe em cima de outro) | O clipe de baixo é aparado, partido ou removido como as notas dele: a parte que sobra à esquerda mantém os pontos; se o clipe novo cai no meio, a parte da direita vira um clipe novo com os pontos deslocados; o clipe totalmente coberto some com os pontos |

Ao aparar a borda esquerda e ao sobrepor, o **estado** que um controle tinha antes do novo começo não é carregado: um pedal que estava embaixo no trecho aparado não continua embaixo no que sobrou (ao contrário do `Cortar no cursor`).

### Escala e acordes

| Item (rótulo exato) | O que faz | Atua sobre | Valores / padrão | Dica |
|---|---|---|---|---|
| `Escala…` | Abre o diálogo `Escala do clipe` (o mesmo do botão `Escala`) | O clipe (a escala é gravada nele) | Ver tabela do diálogo abaixo | Só em faixa melódica |
| `Prender na escala` (caixa de marcar) | Faz notas criadas, movidas de linha e coladas encaixarem na nota da escala mais próxima | Ações de desenhar, mover e colar (não mexe nas notas existentes) | Desligado por padrão; apagado enquanto o clipe não tem escala | Só em faixa melódica; vale para a sessão |
| `Manter o encaixe ao mudar a altura` (caixa de marcar) | Faz três operações que mudam a altura também respeitarem a escala: as setas `↑`/`↓` do editor (inclusive com `Shift`), `Inverter na altura` e `Inserir acorde…` | Seleção ou tudo, conforme a operação | **Desligado por padrão**; apagado enquanto o clipe não tem escala. Só vale com `Prender na escala` também ligado | Só em faixa melódica; vale para a sessão. Ver "Como o encaixe escolhe a nota" abaixo |
| `Prender seleção na escala` | Leva agora as notas que já estão no clipe para a nota da escala mais próxima | Seleção ou tudo | Apagado sem escala no clipe ou sem notas. Não depende das duas caixas acima. Empate vai para a nota de baixo; nota cuja linha de destino não existe no editor fica onde está | Só em faixa melódica; é uma edição só no histórico e não grava nada se nenhuma nota mudou (testado só por testes automáticos) |
| `Inserir acorde…` | Abre o diálogo `Acorde` | Ver diálogo abaixo | Último tipo e inversão usados ficam de ponto de partida (começa em `Maior`, `Fundamental`) | Só em faixa melódica |
| `Acorde no clique` (vira `Acorde no clique: Maior`, com `, 1ª inversão` etc., quando ligado) | Liga o "carimbo": cada nota criada por clique vira um acorde inteiro | Notas novas (Lápis, ou dois cliques na Seleção) | Desligado por padrão. Desligado: abre o diálogo `Acorde`. Ligado: um clique no item desliga | Só em faixa melódica; o arraste na criação dá a duração a todas as notas do acorde |
| `Desdobrar acorde em arpejo` | Transforma cada acorde em notas em sequência | Só seleção | | Funciona também na bateria |
| `Arpejador…` | Abre o diálogo `Arpejador` | Só seleção | Ver diálogo abaixo | Funciona também na bateria |

#### Diálogo `Escala do clipe`

| Controle | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| `Tônica` (12 fichas) | Nota de partida da escala | `C`, `C#`, `D`, `D#`, `E`, `F`, `F#`, `G`, `G#`, `A`, `A#`, `B`; padrão `C` (ou a tônica atual do clipe) | |
| `Escala` (15 fichas) | Tipo de escala | `Maior` (padrão), `Menor natural`, `Menor harmônica`, `Menor melódica`, `Dórico`, `Frígio`, `Lídio`, `Mixolídio`, `Lócrio`, `Pentatônica maior`, `Pentatônica menor`, `Blues`, `Tons inteiros`, `Diminuta (tom e semitom)`, `Cromática` | A cromática usa as 12 notas: realça tudo e não prende em nada |
| `Prender na escala` (chave) com o texto "Notas desenhadas, movidas e coladas encaixam na nota mais próxima da escala (transpor, inverter e acordes: opção no menu)" | Liga/desliga o encaixe | Começa no valor atual | É a mesma opção do item do menu. A opção `Manter o encaixe ao mudar a altura` não está no diálogo: fica só no menu |
| `Cancelar` | Fecha sem mudar nada | | |
| `Sem escala` | Tira a escala do clipe | Só aparece se o clipe já tem escala | |
| `Aplicar` | Grava a escala no clipe e o estado da chave | | |

Intervalos, em semitons acima da tônica:

| Escala | Semitons | Escala | Semitons |
|---|---|---|---|
| Maior | 0 2 4 5 7 9 11 | Mixolídio | 0 2 4 5 7 9 10 |
| Menor natural | 0 2 3 5 7 8 10 | Lócrio | 0 1 3 5 6 8 10 |
| Menor harmônica | 0 2 3 5 7 8 11 | Pentatônica maior | 0 2 4 7 9 |
| Menor melódica | 0 2 3 5 7 9 11 | Pentatônica menor | 0 3 5 7 10 |
| Dórico | 0 2 3 5 7 9 10 | Blues | 0 3 5 6 7 10 |
| Frígio | 0 1 3 5 7 8 10 | Tons inteiros | 0 2 4 6 8 10 |
| Lídio | 0 2 4 6 7 9 11 | Diminuta (tom e semitom) | 0 2 3 5 6 8 9 11 |
| Cromática | 0 a 11 | | |

O que a escala faz na tela: as linhas da escala ficam realçadas (a tônica mais forte), as de fora escurecem e as teclas da escala ganham um pontinho (maior na tônica). O botão `Escala` mostra o nome (por exemplo `A menor natural`) em destaque.

**Como o encaixe escolhe a nota.** Uma nota fora da escala vai para a mais próxima. Se está exatamente entre duas (empate), vai para a de baixo; quando você arrasta uma nota para cima, o empate anda para cima (senão ela nunca sairia do lugar).

```
Escala C maior (C D E F G A B):
C#4 -> C4    (empate: desce)
F#4 -> F4    (empate: desce)
A#4 -> A4    (empate: desce)
Arrastando C4 uma linha para cima com o encaixe ligado: C#4 -> D4 (empate sobe)
```

Mover uma nota só na horizontal nunca a tira do lugar: o encaixe só age quando a altura muda.

**Encaixe ao transpor, inverter e inserir acordes.** Com `Prender na escala` **e** `Manter o encaixe ao mudar a altura` ligados (o segundo vem desligado):

- as setas `↑` e `↓` (e `Shift+↑`/`Shift+↓`, uma oitava) andam de nota da escala em nota da escala, no sentido da seta: a seta primeiro sobe ou desce a altura e depois a nota cai na nota da escala mais próxima, com o empate a favor do sentido em que você vai. Se nenhuma nota muda, nada é gravado;
- `Inverter na altura` espelha as alturas e depois encaixa o resultado na escala (empate para baixo);
- `Inserir acorde…` (botão `Inserir nas notas`) encaixa as notas do acorde na escala. Um acorde que tem notas fora da escala (por exemplo `Maior` numa escala menor) tem essas notas puxadas para a escala; os acordes `Diatônico: …` já saem dentro dela.

Com uma das duas caixas desligada, essas três operações continuam podendo gerar notas fora da escala. Nada disso vale na bateria (testado só por testes automáticos).

#### Diálogo `Acorde`

| Controle | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| `Tipo` (fichas) | Tipo do acorde | 18 tipos fixos (tabela abaixo) e, se o clipe tem escala, mais 3 diatônicos: `Diatônico: tríade`, `Diatônico: sétima`, `Diatônico: nona`. Padrão: `Maior` | Sem escala, um diatônico guardado de antes volta para `Maior` |
| `Inversão` (fichas) | Quantas vezes a nota mais grave sobe uma oitava | `Fundamental` (padrão), `1ª`, `2ª`, `3ª` | Ver exemplos |
| Legenda "Os acordes diatônicos usam o grau da escala em que a nota cai." | Só aparece com escala | | |
| `Cancelar` | Fecha | | |
| `Usar no clique` | Liga o "Acorde no clique" com esse tipo e inversão | Sempre disponível | Vira o botão principal se não há seleção |
| `Inserir nas notas` | Troca cada nota selecionada pelo acorde | Só aparece com seleção | Botão principal quando aparece |

São 18 tipos fixos, mais 3 diatônicos que só aparecem com escala no clipe (21 opções no máximo). Sobre C4:

| Rótulo da ficha | Semitons | Notas sobre C4 |
|---|---|---|
| `Maior` | 0 4 7 | C4 E4 G4 |
| `Menor` | 0 3 7 | C4 D#4 G4 |
| `Diminuto` | 0 3 6 | C4 D#4 F#4 |
| `Aumentado` | 0 4 8 | C4 E4 G#4 |
| `Sus2` | 0 2 7 | C4 D4 G4 |
| `Sus4` | 0 5 7 | C4 F4 G4 |
| `Sétima (7)` | 0 4 7 10 | C4 E4 G4 A#4 |
| `Sétima maior (maj7)` | 0 4 7 11 | C4 E4 G4 B4 |
| `Menor com sétima (m7)` | 0 3 7 10 | C4 D#4 G4 A#4 |
| `Meio-diminuto (m7b5)` | 0 3 6 10 | C4 D#4 F#4 A#4 |
| `Diminuto com sétima (dim7)` | 0 3 6 9 | C4 D#4 F#4 A4 |
| `Sexta (6)` | 0 4 7 9 | C4 E4 G4 A4 |
| `Menor com sexta (m6)` | 0 3 7 9 | C4 D#4 G4 A4 |
| `Add9` | 0 4 7 14 | C4 E4 G4 D5 |
| `Nona (9)` | 0 4 7 10 14 | C4 E4 G4 A#4 D5 |
| `Nona maior (maj9)` | 0 4 7 11 14 | C4 E4 G4 B4 D5 |
| `Menor com nona (m9)` | 0 3 7 10 14 | C4 D#4 G4 A#4 D5 |
| `Quinta (power chord)` | 0 7 | C4 G4 |

Acordes diatônicos (só com escala no clipe): a nota clicada é primeiro encaixada na escala e o acorde empilha notas da escala de dois em dois graus a partir dela (terças): `tríade` = 3 notas, `sétima` = 4, `nona` = 5. Em C maior:

```
Diatônico: tríade  sobre C4 -> C4 E4 G4      (maior)
                   sobre D4 -> D4 F4 A4      (menor)
                   sobre B3 -> B3 D4 F4      (diminuto)
Diatônico: sétima  sobre D4 -> D4 F4 A4 C5
Diatônico: nona    sobre D4 -> D4 F4 A4 C5 E5
```

Numa escala pentatônica ou cromática "de dois em dois graus" ainda vale, mas os acordes saem diferentes do que a teoria de terças diria.

Inversões (a nota mais grave sobe uma oitava, uma vez por inversão):

```
Maior, fundamental  C4 E4 G4
Maior, 1ª           E4 G4 C5
Maior, 2ª           G4 C5 E5
Maior, 3ª           C5 E5 G5      (com 3 notas, volta ao fundamental uma oitava acima)
maj7, 3ª            B4 C5 E5 G5   (só com 4 notas a 3ª inversão é diferente)
```

Notas que passariam do limite MIDI (0 a 127) ficam de fora.

**`Inserir nas notas`**: cada nota selecionada é substituída pelo acorde, herdando o início, a duração e a velocidade dela. A nota original só permanece se estiver no acorde (na fundamental ela é a mais grave; numa inversão, ela sobe).

```
Selecionado: C4@0(4)          Tipo: Menor, Fundamental
Resultado:   [C4 D#4 G4]@0(4)

Selecionado: C4@0(4)          Tipo: Maior, 1ª
Resultado:   [E4 G4 C5]@0(4)
```

**`Acorde no clique`**: com ele ligado, um clique no vazio cria o acorde inteiro com a nota clicada como base (encaixada na escala, se `Prender na escala` está ligado). O arraste na criação muda a duração de todas as notas do acorde. Na bateria o carimbo é ignorado (cria uma nota só). O carimbo é da sessão, não do clipe.

#### Item `Desdobrar acorde em arpejo`

Cada grupo de notas que começam juntas vira uma sequência, da mais grave à mais aguda: a duração do acorde (a maior entre as notas) é dividida em partes iguais. Nota sozinha fica como está. Cada nota guarda a própria velocidade.

```
[C4 E4 G4]@0(3)  ->  C4@0(1)  E4@1(1)  G4@2(1)
[C4 E4 G4]@0(4)  ->  C4@0(1,333)  E4@1,333(1,333)  G4@2,667(1,333)
```

Sem parâmetros. Para controlar ritmo, direção e oitavas, use o `Arpejador…`.

#### Diálogo `Arpejador`

| Controle | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| `Padrão` | Ordem em que as notas do acorde são tocadas | `Subir` (padrão), `Descer`, `Subir e descer`, `Aleatório`, `Ordem tocada` | `Subir e descer` não repete as pontas: `1 2 3 2 · 1 2 3 2`. `Ordem tocada` segue a ordem das notas no clipe, não a altura. `Aleatório` sorteia com uma semente que muda a cada uso (repetir dá outro resultado) |
| `Taxa` | Distância entre as notas geradas | `1/4`, `1/4T`, `1/8`, `1/8T`, `1/16` (padrão), `1/16T`, `1/32`, `1/32T` | Em tempos: 1, 2/3, 1/2, 1/3, 1/4, 1/6, 1/8, 1/12 |
| `Oitavas` | Quantas oitavas o arpejo percorre | 1 (padrão), 2, 3, 4 | Notas acima de 127 são descartadas |
| `Gate` | Quanto de cada passo a nota dura | 10% a 100%, de 10 em 10, padrão 90% | Baixo = staccato; 100% = notas coladas |
| Legenda "Cada grupo de notas que começam juntas vira um arpejo pela duração dele." | Explica o alcance | | |
| `Cancelar` / `Arpejar` | Fecha / aplica | | |

Como funciona: cada grupo de notas que começam juntas é um acorde; dentro da duração dele toca-se uma nota a cada `Taxa`. A velocidade de todas as notas geradas é a média das velocidades do acorde. Um resto que não completa uma taxa ainda toca, curto, até o fim do acorde. **Uma nota sozinha vira uma repetição dela mesma** (com 2 ou mais oitavas, ela pula de oitava em oitava).

```
[C4 E4 G4]@0(4), Taxa 1/8, Subir, 1 oitava, Gate 90%
-> C4 E4 G4 C4 E4 G4 C4 E4  (8 colcheias, cada uma com 0,45 tempo de duração)

Mesmo acorde, Subir e descer
-> C4 E4 G4 E4 C4 E4 G4 E4

Mesmo acorde, Descer, 2 oitavas
-> G5 E5 C5 G4 E4 C4 G5 E5

Nota sozinha C2@0(4), Taxa 1/8, Subir, 2 oitavas
-> C2 C3 C2 C3 C2 C3 C2 C3  (baixo em oitavas)
```

### Seleção

| Item (rótulo exato) | O que faz | Atua sobre | Valores / padrão | Dica |
|---|---|---|---|---|
| `Humanizar…` (`Shift+H`) | Espalha levemente início e velocidade | Seleção ou tudo | Diálogo `Humanizar` (abaixo) | Sem notas no clipe fica apagado |
| `Rampa de velocidade` | Faz a velocidade crescer ou cair em linha reta do começo ao fim | Seleção ou tudo | Sem parâmetros | Ajuste antes a velocidade da primeira e da última nota |
| `Legato` (`Shift+L`) | Cada nota vai até o começo da próxima | Seleção ou tudo | Sem parâmetros | |
| `Staccato…` | Encurta as notas | Seleção ou tudo | Diálogo `Staccato` (abaixo) | |
| `Inverter no tempo` | Toca de trás para frente (espelha no tempo) | Seleção ou tudo | Sem parâmetros | |
| `Inverter na altura` | Vira de cabeça para baixo (espelha na altura) | Seleção ou tudo | Sem parâmetros; apagado na bateria | Com `Prender na escala` e `Manter o encaixe ao mudar a altura` ligados, o resultado é encaixado na escala |
| `Reverter a ordem das notas` | Toca as alturas de trás para frente mantendo o ritmo | Seleção ou tudo | Sem parâmetros | |
| `Dividir colcheias em 3 notas` | Cada colcheia vira três notas iguais | Seleção ou tudo | Sem parâmetros | Só age em notas de exatamente 1/2 tempo. O nome não é ritmo de tercina do compasso: ele só divide a colcheia em três notas iguais |

#### Diálogo `Humanizar`

| Controle | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| `Tempo` | Quanto o início de cada nota pode se deslocar (para mais ou para menos) | 0% a 100%, de 5 em 5, padrão 50%. 100% = até 1/8 de tempo (0,125 tempo, 1/32 de nota) para cada lado | Nota nunca passa para antes do início do clipe |
| `Velocidade` | Quanto a velocidade pode variar (para mais ou para menos) | 0% a 100%, de 5 em 5, padrão 50%. 100% = até 0,3 da escala 0 a 1, ou seja cerca de 38 de 127 para cada lado (a legenda do diálogo diz "até 38 de 127", o mesmo valor) | O resultado é sempre entre 1 e 127 |
| `Semente` | Escolhe qual "sorteio" será usado | 1 a 99; começa em 1 e cada uso avança um | A mesma semente com os mesmos ajustes dá sempre o mesmo resultado; mude para outro |
| Legenda | "Tempo 100% desloca até 1/32 de nota; velocidade 100%, até 38 de 127. A mesma semente dá sempre o mesmo resultado." | | |
| `Cancelar` / `Humanizar` | Fecha / aplica | | |

`Shift+H` (e o item, pelo atalho) aplica **direto** com os últimos valores de `Tempo` e `Velocidade` do diálogo e uma semente nova a cada vez, sem abrir o diálogo. Repetir `Shift+H` empilha desvios diferentes.

```
Antes:   C4@0(1) E4@1(1) G4@2(1)   velocidades 100 100 100
Depois:  C4@0,04(1) E4@0,97(1) G4@2,05(1)   velocidades 94 108 99   (exemplo; varia com a semente)
```

#### `Rampa de velocidade`

Linha reta no tempo (não no número da nota) da velocidade da **primeira nota** (a de início mais cedo) até a da **última** (a de início mais tarde). As notas do meio recebem a velocidade proporcional ao início delas. Se todas começam no mesmo instante, todas ficam com a velocidade da primeira.

```
Antes:   C4@0(1) D4@1(1) E4@2(1) F4@3(1)   velocidades 40 90 90 100
Depois:  C4@0(1) D4@1(1) E4@2(1) F4@3(1)   velocidades 40 60 80 100
```

Para um decrescendo, deixe a primeira mais forte que a última. Para dar valores certos, defina a primeira e a última no painel de velocidade e aplique a rampa.

#### `Legato`

Cada nota passa a durar até o início da **próxima nota que começa depois dela, de qualquer altura**; a última fica como está. Isso também **encurta** notas que estavam mais longas que o intervalo (o comprimento vira exatamente a distância até a próxima).

```
Antes:   C4@0(0,5) E4@1(0,5) G4@2(0,5)
Depois:  C4@0(1)   E4@1(1)   G4@2(0,5)
```

Notas de um acorde (mesmo início) vão todas até o mesmo início seguinte.

#### Diálogo `Staccato`

| Controle | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| `Duração` | Fração da duração original que sobra | 10% a 90%, de 10 em 10, padrão 50% | Aplicado de novo, encurta de novo (a duração já é a encurtada). Mínimo de 1/128 de tempo |
| `Cancelar` / `Encurtar` | Fecha / aplica | | |

```
Antes:   C4@0(1) E4@1(1) G4@2(1)      Duração 50%
Depois:  C4@0(0,5) E4@1(0,5) G4@2(0,5)
```

#### `Inverter no tempo`, `Inverter na altura` e `Reverter a ordem das notas`

Três "reversos" diferentes. Nos exemplos, uma frase com ritmo desigual: C4 longa e duas curtas.

```
Original                        C4@0(2)  E4@2(1)  G4@3(1)

Inverter no tempo               G4@0(1)  E4@1(1)  C4@2(2)
  (espelha início e fim: a nota que acabava por último passa a começar primeiro;
   o ritmo também vai de trás para frente)

Reverter a ordem das notas      G4@0(2)  E4@2(1)  C4@3(1)
  (o ritmo fica; só as alturas e velocidades se invertem, como uma melodia tocada de trás para frente)

Inverter na altura              G4@0(2)  D#4@2(1) C4@3(1)
  (a mais grave vira a mais aguda em torno da faixa ocupada: pitch = mais grave + mais aguda - pitch)
```

Detalhes:

- `Inverter no tempo` espelha em torno do trecho ocupado pelas notas (do menor início ao maior fim). As alturas não mudam.
- `Inverter na altura` espelha em torno da faixa entre a nota mais grave e a mais aguda da seleção. Sem as duas opções de encaixe ligadas, não passa pela escala: `E4` virou `D#4` no exemplo (60 + 67 - 64 = 63). Com `Prender na escala` e `Manter o encaixe ao mudar a altura` ligados e uma escala no clipe, o resultado é encaixado nela. Está apagado na bateria. Resultado limitado a 0..127.
- `Reverter a ordem das notas` mantém os inícios e as durações onde estão e troca as alturas e velocidades de trás para frente. Notas simultâneas seguem a ordem da altura.

#### `Dividir colcheias em 3 notas`

Cada nota que dura **exatamente 1/2 tempo** (uma colcheia) vira três notas iguais que dividem essa duração em três partes. Notas de outras durações não mudam.

```
Antes:   C4@0(0,5)  E4@1(1)
Depois:  C4@0(0,1667) C4@0,1667(0,1667) C4@0,3333(0,1667)  E4@1(1)
```

O efeito é um "rolo" de três notas repetidas dentro de cada colcheia (o som de uma tercina de semicolcheia sobre a colcheia); ele não converte pares de colcheias em ritmo de tercina do compasso. Para um ritmo ternário de verdade, escreva na grade `1/8T` ou `1/16T`.

### Escalar o tempo

Multiplica as posições das notas (contadas a partir da **primeira nota** da seleção, que fica parada) e, por padrão, as durações também.

| Item (rótulo exato) | O que faz | Atua sobre | Valores / padrão | Dica |
|---|---|---|---|---|
| `×0,5 (metade)` | Encolhe o tempo: o trecho passa a ocupar metade (toca o dobro da velocidade) | Seleção ou tudo | Fator 0,5, durações também | |
| `×2 (dobro)` | Estica: o trecho passa a ocupar o dobro (meio andamento) | Seleção ou tudo | Fator 2, durações também | Se as notas passam do fim do clipe, o clipe cresce até o compasso que as contém, no mesmo passo do `Ctrl+Z` (testado só por testes automáticos) |
| `Personalizado…` | Abre o diálogo `Escalar o tempo` | Seleção ou tudo | Abaixo | |

Diálogo `Escalar o tempo`:

| Controle | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| `Fator` | Multiplicador | ×0,25 a ×4, de 0,05 em 0,05, padrão ×1,50 (o rótulo mostra `×1,50`) | 0,75 = três quartos do tempo |
| `Escalar as durações também` (caixa) | Também multiplica a duração de cada nota | Marcada por padrão | Desmarcada, o ritmo muda mas as notas mantêm a duração (podem se sobrepor ou deixar vãos) |
| `Cancelar` / `Aplicar` | Fecha / aplica | | |

```
Antes:      C4@0(1)  E4@1(1)  G4@2(2)
×2:         C4@0(2)  E4@2(2)  G4@4(4)
×0,5:       C4@0(0,5) E4@0,5(0,5) G4@1(1)
×2, sem durações: C4@0(1) E4@2(1) G4@4(2)

Primeira nota parada:  C4@2(1) E4@3(1)  ×2 -> C4@2(2) E4@4(2)
```

A duração de cada nota nunca fica abaixo de 1/128 de tempo. Depois de `×2` (ou de qualquer fator maior que 1, ou de `Personalizado…`), se o fim das notas passa do fim do clipe, o clipe **cresce sozinho** até o fim do compasso que contém a última nota (compassos do projeto; por exemplo, um clipe de 4 tempos com a última nota acabando no tempo 6 vira um clipe de 8 tempos em 4/4). O clipe cresce na mesma edição da escala: um `Ctrl+Z` devolve notas, pontos de controle e comprimento. Ele só cresce, nunca encolhe, e não cresce se as notas já passavam do fim antes da ferramenta e não foram mais longe. O mesmo vale para as outras ferramentas que mexem no tempo ou na duração (`Legato`, `Arpejador…`, `Inserir acorde…` e as demais).

### Cortar e limpar

| Item (rótulo exato) | O que faz | Atua sobre | Valores / padrão | Dica |
|---|---|---|---|---|
| `Dividir no cursor` (`K`) | Parte em duas as notas que o cursor atravessa | Seleção ou tudo | Usa a posição do cursor de reprodução relativa ao clipe; se ela é zero ou antes do início, não faz nada | Mova o cursor clicando na régua do editor |
| `Unir notas iguais adjacentes` (`J`) | Junta notas de mesma altura que se tocam ou se sobrepõem | Seleção ou tudo | Sem parâmetros | Guarda a velocidade da primeira |
| `Remover duplicadas` | Apaga notas repetidas | Seleção ou tudo | Mesma altura e mesmo início | Fica a mais longa (a primeira, em empate) |
| `Aparar sobrepostas` | Encurta a nota que invade a seguinte da mesma altura | Seleção ou tudo | Sem parâmetros | Não mexe em notas que começam juntas (isso é caso de `Remover duplicadas`) |

```
Dividir no cursor (cursor no tempo 1,5 do clipe)
Antes:   C4@0(4)          Depois:  C4@0(1,5)  C4@1,5(2,5)
Notas que terminam antes do cursor, ou começam depois, ficam como estão.

Unir notas iguais adjacentes
Antes:   C4@0(1) C4@1(1)          Depois:  C4@0(2)
Antes:   C4@0(2) C4@1(2)          Depois:  C4@0(3)   (sobreposição também une)
Antes:   C4@0(1) C4@1,5(1)        Depois:  igual (há um vão de 0,5)
Notas de alturas diferentes nunca se unem. O resultado sai ordenado por início e altura.

Remover duplicadas
Antes:   C4@0(1) C4@0(2) E4@0(1)   Depois:  C4@0(2) E4@0(1)

Aparar sobrepostas
Antes:   C4@0(3) C4@2(1) E4@1(4)   Depois:  C4@0(2) C4@2(1) E4@1(4)
(C4 termina onde a segunda C4 começa; E4 é outra altura e não é tocada)
```

`Dividir` e `Unir` são opostos: dividir uma nota em 1,5 e unir logo depois a devolve inteira.

### Fantasmas

Submenu com duas caixas de marcar. Não altera notas: só decide o que aparece em cinza atrás das suas notas, como referência.

| Item (rótulo exato) | O que faz | Padrão | Dica |
|---|---|---|---|
| `Outros clipes da faixa` | Mostra as notas dos outros clipes da mesma faixa | Ligado | Ajuda a escrever uma resposta a uma frase anterior |
| `Outras faixas de instrumento` | Mostra as notas dos clipes das outras faixas de instrumento (melódicas com melódicas, bateria com bateria) | Desligado | Bom para escrever um baixo olhando os acordes de outra faixa |

Os fantasmas se alinham pelo tempo do arranjo, não pelo início do clipe; só clipes com notas contam.

## Passo a passo

**Trocar uma nota por um acorde**

1. Selecione a nota (clique nela).
2. `Ferramentas > Escala e acordes > Inserir acorde…`.
3. Escolha o `Tipo` (por exemplo `Menor`) e a `Inversão`.
4. Clique em `Inserir nas notas`. Um `Ctrl+Z` desfaz.

**Escrever acordes com um clique cada**

1. `Ferramentas > Escala e acordes > Escala…`, escolha tônica e escala e `Aplicar`.
2. `Ferramentas > Escala e acordes > Acorde no clique`, escolha `Diatônico: tríade` e `Usar no clique`.
3. Com o Lápis, clique a nota-base de cada acorde (o arraste define a duração).
4. Para voltar a criar nota única, abra o menu e clique em `Acorde no clique: …` (desliga).

**Transformar acordes em arpejo**

1. Selecione os acordes (`Ctrl+A` seleciona todas as notas).
2. `Ferramentas > Escala e acordes > Arpejador…`.
3. Escolha `Padrão`, `Taxa`, `Oitavas` e `Gate`; clique em `Arpejar`.
4. Para um arpejo simples (uma passada, sem controle) use `Desdobrar acorde em arpejo`.

**Deixar mais humano**

1. Selecione as notas (ou nada, para todas).
2. `Ferramentas > Seleção > Humanizar…`, deixe `Tempo` em 50% e `Velocidade` em 30% para começar.
3. Clique em `Humanizar`. Se não gostou, `Ctrl+Z` e tente outra `Semente`.
4. Para repetir sem abrir o diálogo, use `Shift+H`.

## Combina com

- [Editor de notas](05-piano-roll.md): a seleção, o painel de velocidade, a faixa de controle (bend, modulação e sustain), o cursor e o fim do clipe que estas ferramentas usam.
- `Quantizar` (barra do editor, tecla `Q`): o par natural do `Humanizar`. Humanizar afasta as notas da grade; quantizar com força 50% traz parte do caminho de volta.
- [Melodia e harmonia com as ferramentas](../guias/melodia-e-harmonia-com-as-ferramentas.md): progressão, arpejo, baixo e escala passo a passo.

## Limites e pegadinhas

- **Sem seleção, tudo é afetado.** Para as transformações de `Seleção`, `Escalar o tempo` e `Cortar e limpar`, esquecer de selecionar significa mexer no clipe inteiro. `Inserir nas notas`, `Desdobrar` e `Arpejador…` exigem seleção.
- **Teto do `Humanizar`.** Velocidade 100% varia até 0,3 na escala 0 a 1, ou seja 38 de 127 para cada lado; a legenda do diálogo calcula esse número a partir do mesmo valor, então bate com o resultado.
- **Encaixe é opcional e vem desligado nas operações de altura.** `Prender na escala` sozinho só age ao criar, mover de linha e colar. Para transpor com as setas, `Inverter na altura` e `Inserir acorde…` respeitarem a escala é preciso ligar também `Manter o encaixe ao mudar a altura`. Para encaixar de uma vez as notas que já estão no clipe, use `Prender seleção na escala`.
- `Escalar o tempo`, `Legato` e as demais ferramentas esticam o clipe sozinhas até o compasso que contém o fim das notas quando elas passam do fim dele; o clipe não encolhe de volta (`Ctrl+Z` desfaz as duas coisas juntas). Notas que já estavam além do fim antes de você aplicar a ferramenta continuam mudas, e o clipe só cresce se a ferramenta as levar ainda mais longe.
- `Dividir colcheias em 3 notas` só reconhece 1/2 tempo exato (tolerância de 0,0001).
- No arpejador, "Ordem tocada" segue a ordem das notas na lista do clipe (a ordem em que foram criadas ou coladas), não a ordem em que você as tocaria.
- Na bateria: `Escala…`, `Prender na escala`, `Manter o encaixe ao mudar a altura`, `Prender seleção na escala`, `Inserir acorde…`, `Acorde no clique` e `Inverter na altura` não estão disponíveis; o botão `Escala` some. `Arpejador…` e `Desdobrar acorde em arpejo` funcionam, mas arpejar peças de bateria raramente faz sentido musical.
- **Bend, modulação e pedal não acompanham as ferramentas de notas.** Só `Escalar o tempo` e `Inverter no tempo` levam os pontos junto; depois de `Humanizar`, `Quantizar`, arpejo ou mover notas, um bend desenhado sob uma nota continua onde estava. `Dividir no cursor` (`K`) corta notas, não pontos.
- A semente do `Humanizar` e do arpejo `Aleatório` avança a cada uso, então repetir a mesma ferramenta dá um resultado diferente.
- Os ajustes dos diálogos (padrão, taxa, oitavas, gate, tempo, velocidade, staccato) e o `Acorde no clique` valem para a sessão; o `Escalar o tempo` sempre reabre em ×1,50. A escala do clipe fica gravada no clipe.

## Atalhos

| Tecla | Ação |
|---|---|
| `Shift+H` | Humanizar com os últimos ajustes e semente nova |
| `Shift+L` | Legato |
| `K` | Dividir no cursor |
| `J` | Unir notas iguais adjacentes |
| `Q` | Quantizar (não é do menu, mas combina com ele) |

Com o teclado musical do computador ligado (`Ctrl+K`), `K`, `J`, `Shift+H` e `Shift+L` tocam notas em vez de acionar as ferramentas; use o menu `Ferramentas` nesse caso.
