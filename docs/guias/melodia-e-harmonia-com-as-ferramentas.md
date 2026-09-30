# Melodia e harmonia com as ferramentas MIDI

> Uma progressão de acordes com arpejo, humanizada, com baixo e uma melodia que não erra nota, montada só com as ferramentas do editor de notas; leva uns 15 minutos e serve de molde para qualquer tom.

Tudo abaixo supõe compasso de 4 tempos. Nas notações, `C4@0(4)` é a nota C4 começando no tempo 0 do clipe, com 4 tempos de duração.

## Ingredientes

- [Editor de notas](../manual/05-piano-roll.md): Lápis, grade, `Nota:`, seleção, `Ctrl+A`, `Ctrl+D`, `Shift+↓`, fim do clipe na régua, painel de velocidade, `Quantizar`.
- [Ferramentas MIDI](../manual/05b-ferramentas-midi.md): `Escala…`, `Prender na escala`, `Acorde no clique`, `Arpejador…`, `Humanizar…`, `Escalar o tempo`, `Fantasmas`.
- Duas faixas de instrumento melódico (por exemplo, uma de teclas para os acordes e uma de baixo) mais uma terceira opcional para a melodia. Para criar cada clipe: dois cliques no vazio da faixa, que abre um clipe de 1 compasso já no editor.

## Passo a passo

### 1. A progressão C, Am, F, G (um compasso cada)

1. Na faixa de teclas, dê dois cliques no vazio no compasso 1. Abre-se um clipe de um compasso.
2. Puxe a bandeirinha do fim do clipe, na régua do editor, até o fim do compasso 4 (16 tempos). Notas depois do fim do clipe não tocam.
3. Clique em `Escala`, deixe a `Tônica` em `C` e a `Escala` em `Maior`, ligue a chave `Prender na escala` e clique em `Aplicar`. As linhas de C maior ficam realçadas.
4. Deixe a grade em `1/4` e escolha `Nota: 1/1` (uma nota de 4 tempos por clique).
5. `Ferramentas > Escala e acordes > Acorde no clique`. No diálogo `Acorde`, em `Tipo` escolha `Diatônico: tríade`, em `Inversão` deixe `Fundamental` e clique em `Usar no clique`. No menu o item passa a se chamar `Acorde no clique: Diatônico: tríade`, marcado.
6. Com o Lápis, clique logo depois da linha de cada compasso (o início cai no tempo anterior da grade, então não clique antes da linha):
   - compasso 1, linha `C4`: nasce `[C4 E4 G4]@0(4)`;
   - compasso 2, linha `A3`: `[A3 C4 E4]@4(4)`;
   - compasso 3, linha `F3`: `[F3 A3 C4]@8(4)`;
   - compasso 4, linha `G3`: `[G3 B3 D4]@12(4)`.
7. Desligue o carimbo: `Ferramentas > Escala e acordes > Acorde no clique: Diatônico: tríade` (um clique desmarca). Sem isso, todo clique seguinte também cria acorde.
8. Aperte `Espaço` para ouvir os quatro acordes.

Os acordes saem maior, menor, maior, maior porque o tipo `Diatônico` olha o grau da escala em que a nota cai; você não precisou trocar de tipo a cada compasso.

### 2. Virar arpejo

1. Se quiser guardar os acordes fechados, `Ctrl+C` os copia (cole depois em outro clipe com `Ctrl+V`); ou confie no `Ctrl+Z`.
2. Aperte `Ctrl+A` para selecionar as 12 notas (o contador mostra `12 de 12 selecionadas`).
3. `Ferramentas > Escala e acordes > Arpejador…` e ajuste:
   - `Padrão`: `Subir e descer`
   - `Taxa`: `1/8`
   - `Oitavas`: `1`
   - `Gate`: `90%`
4. Clique em `Arpejar`. Cada compasso vira oito colcheias: `C4 E4 G4 E4 C4 E4 G4 E4` no compasso 1, `A3 C4 E4 C4 A3 C4 E4 C4` no 2, e assim por diante, cada nota com 0,45 tempo de duração.

### 3. Humanizar e quantizar

1. Com as notas ainda selecionadas, `Ferramentas > Seleção > Humanizar…`.
2. `Tempo` 30% (cada início se desloca até cerca de 0,04 tempo para cada lado), `Velocidade` 40% (cerca de 15 de 127 para cada lado), `Semente` 1. Clique em `Humanizar`.
3. Ouça. Se ficou solto demais, `Ctrl+Z` e refaça com `Tempo` 15%; se ficou igual, tente outra `Semente`.
4. Para um meio-termo entre humano e certinho, troque a grade do editor para `1/8` (a quantização usa a grade do editor: com `1/4` as colcheias do arpejo seriam puxadas para o tempo mais próximo e estragariam o desenho), abra a seta ao lado de `Quantizar`, marque `Força` `50%` e clique em `Quantizar` (ou `Q`): cada nota volta metade do caminho até a linha da grade. Como o desvio é bem menor que a grade, isso só reduz a folga pela metade.
5. Para o caminho inverso (material tocado ao vivo que ficou torto): grade na menor subdivisão que você usou (`1/16`, por exemplo), `Força` `100%` e `Q` para alinhar tudo; depois `Shift+H` para devolver uma folga leve, com os últimos ajustes do diálogo e uma semente nova a cada vez.
6. Aperte `Esc` para limpar a seleção (com as notas selecionadas, arrastar uma bolinha no painel de velocidade move todas juntas) e, no painel de velocidade, arraste para cima as bolinhas do primeiro tempo de cada compasso: o acorde ganha acento.

### 4. A linha de baixo, a partir da fundamental de cada acorde

1. Na faixa de baixo, dê dois cliques no vazio do compasso 1 e puxe o fim do clipe até o fim do compasso 4.
2. `Escala`, `C` e `Maior`, `Aplicar` (a escala é de cada clipe; `Prender na escala` continua ligado da sessão).
3. `Ferramentas > Fantasmas > Outras faixas de instrumento`: as notas do clipe de teclas aparecem em cinza atrás da grade, no mesmo tempo e altura.
4. Escolha `Nota: 1/1` e a grade `1/4`. Com o Lápis, clique na nota mais grave de cada acorde cinza, logo depois da linha de cada compasso: `C4@0(4)`, `A3@4(4)`, `F3@8(4)`, `G3@12(4)`.
5. `Ctrl+A` e `Shift+↓` duas vezes: cada aperto desce uma oitava; as notas ficam `C2`, `A1`, `F1`, `G1`.
6. Com tudo ainda selecionado, `Ferramentas > Escala e acordes > Arpejador…`: `Padrão` `Subir`, `Taxa` `1/8`, `Oitavas` `2`, `Gate` `60%`, `Arpejar`. Uma nota sozinha vira uma repetição dela mesma, e com duas oitavas ela salta de oitava: cada compasso vira `C2 C3 C2 C3 C2 C3 C2 C3` (baixo em oitavas). Com `Oitavas` `1` sai uma pulsação de colcheias na mesma nota.
7. Ouça as duas faixas juntas e ajuste as velocidades das notas de baixo no painel de velocidade.

### 5. A versão em dobro (e a em metade)

Faça na faixa de teclas, com o arpejo pronto.

1. Aperte `Ctrl+A` (selecionar tudo).
2. `Ferramentas > Escalar o tempo > ×0,5 (metade)`. A progressão passa a ocupar 2 compassos, com arpejo e acordes no dobro da velocidade (cada colcheia vira semicolcheia).
3. Aperte `Ctrl+D`: a seleção (2 compassos) é copiada logo depois, e o clipe continua com 4 compassos, agora com a progressão tocada duas vezes.
4. Repita o passo 2 na faixa de baixo para os dois acompanharem.

Para a versão em **metade** da velocidade: `Escalar o tempo > ×2 (dobro)` faz a progressão ocupar 8 compassos. O clipe **não** cresce sozinho: puxe o fim do clipe para o fim do compasso 8, senão a segunda metade fica escurecida e muda.

### 6. Uma melodia que nunca erra nota

1. Numa terceira faixa (lead), dê dois cliques no vazio e estique o clipe para 4 compassos.
2. `Escala`, `Tônica` `C`, `Escala` `Pentatônica maior`, `Aplicar` (`Prender na escala` ligado). A grade só realça C, D, E, G e A.
3. Ligue `Ferramentas > Fantasmas > Outras faixas de instrumento` para ver os acordes e o baixo de fundo.
4. Grade `1/8`, `Nota: grade`. Com o Lápis, clique onde quiser: qualquer clique numa linha escurecida vai para a nota mais próxima da escala (em empate, a de baixo; por exemplo `F4` vira `E4` e `B4` vira `C5`).
5. Arraste as notas para cima e para baixo: cada linha nova também é encaixada.
6. Troque a escala para `Maior` (ou `Menor natural`, `Dórico`) em `Escala…` para ver a mesma melodia em outra cor; as notas já escritas não se movem sozinhas.

## Variações

- **Acordes com sétima:** no passo 1.5, escolha `Diatônico: sétima` (quatro notas por acorde: `C4 E4 G4 B4`, `A3 C4 E4 G4`...). Com `Diatônico: nona` saem cinco notas.
- **Condução de vozes suave:** em vez do carimbo com `Fundamental`, use `Inversão` `1ª` ou `2ª` nos compassos em que o acorde ficaria muito longe do anterior (ligue o carimbo de novo, escolhendo a inversão nova, entre um compasso e outro).
- **Trocar tipo de acorde numa nota já escrita:** selecione a nota e use `Ferramentas > Escala e acordes > Inserir acorde…` com `Inserir nas notas`; ela é trocada pelo acorde escolhido, com a mesma duração e velocidade. Assim, notas soltas de uma melodia esboçada viram acordes sem redesenhar nada.
- **Arpejo sem escolher nada:** `Ferramentas > Escala e acordes > Desdobrar acorde em arpejo` divide cada acorde em notas iguais de baixo para cima, sem opções (bom para harpa, 3 notas em 4 tempos = 1,33 tempo cada).
- **Arpejo imprevisível:** `Padrão` `Aleatório`; cada `Arpejar` usa uma semente nova, então repetir dá outro desenho (`Ctrl+Z` para descartar).
- **Baixo staccato:** depois do arpejo do baixo, `Ferramentas > Seleção > Staccato…` com `Duração` `50%` deixa as notas mais curtas e secas; para o contrário, `Legato` (`Shift+L`) liga cada nota à seguinte.
- **Baixo copiando as fundamentais:** em vez dos fantasmas, no clipe de teclas selecione só as fundamentais com `Shift` + clique (a primeira sem `Shift`), `Ctrl+C`, abra o clipe do baixo, ponha o cursor no começo (clique na régua) e `Ctrl+V`; as notas coladas já ficam selecionadas para o `Shift+↓`.
- **Progressão em outro tom:** mude a `Tônica` em `Escala…` (por exemplo para `G`), apague as notas e refaça o passo 1.6 nas linhas de `G`, `Em`, `C`, `D`.
- **Melodia com resposta:** com `Outros clipes da faixa` ligado (já vem ligado), um segundo clipe da mesma faixa mostra o primeiro em cinza, para escrever uma frase que responda à outra.

## Por que funciona

- **A escala é um filtro na entrada.** Com `Prender na escala`, cada nota criada, movida de linha ou colada passa por "qual nota da escala é a mais próxima?". Por isso é impossível clicar uma nota fora da escala; e os acordes `Diatônicos` empilham notas da própria escala, então nem precisam ser escolhidos um a um.
- **Uma nota é um acorde de um som só.** O arpejador trata cada grupo de notas que começam juntas como um acorde; um grupo de uma nota vira repetição (e, com mais oitavas, oitavas alternadas), o que dá baixo rítmico sem escrever cada colcheia.
- **Ferramentas em série.** Cada ferramenta lê a seleção que a anterior deixou (as notas resultantes ficam selecionadas): arpejar, humanizar e quantizar sem mexer no mouse entre elas.
- **Humanizar e quantizar são opostos com dose regulável.** `Humanizar` espalha o início e a velocidade; `Quantizar` com força menor que 100% puxa parte do caminho de volta. Combinando as duas, você escolhe quanto de folga sobra.
- **Escalar o tempo mantém a proporção.** Ele multiplica posições e durações a partir da primeira nota, então o desenho rítmico não muda, só a velocidade. Notas que passam do fim do clipe ficam escondidas, por isso o clipe é esticado à mão.
- **Fantasmas ajudam a harmonia a ser visual.** Ver os acordes atrás do baixo evita ter que decorar as notas.

## Se der errado

- **Toda nota que clico vira acorde:** o `Acorde no clique` ficou ligado. Em `Ferramentas > Escala e acordes`, o item aparece marcado; clique nele para desligar.
- **O item `Arpejador…` ou `Desdobrar acorde em arpejo` está apagado:** nada está selecionado; use `Ctrl+A`.
- **`Prender na escala` está apagado:** o clipe não tem escala; abra `Escala…` e aplique uma.
- **O clipe do baixo toca só o primeiro compasso, ou o final some:** o clipe tem só 1 compasso (o tamanho ao criar) ou o clipe ficou menor que as notas; puxe a bandeirinha na régua. Notas escurecidas, além do fim, não tocam.
- **`K`, `J`, `Shift+H` e `Shift+L` tocam notas em vez de dividir, unir, humanizar ou fazer legato:** o teclado musical do computador está ligado (`Ctrl+K`); use o menu `Ferramentas` ou desligue o teclado.
- **Os fantasmas não aparecem:** confira `Outras faixas de instrumento`, se a outra faixa é do mesmo tipo (melódica com melódica; bateria com bateria) e se o clipe dela tem notas no mesmo trecho do arranjo.
- **O baixo ficou agudo demais:** selecione as notas e `Shift+↓` mais uma vez (uma oitava por aperto). O editor só mostra da C0 à C8, então o baixo mais grave possível é a C0 (12 no MIDI).
- **Humanizei demais:** `Ctrl+Z` desfaz tudo o que a ferramenta fez (é um passo só). Reduza `Tempo`, mude a `Semente` e refaça. Os valores de 100% chegam a 0,125 tempo (1/32 de nota) de deslocamento para cada lado.
- **Uma nota escorregou para fora da escala depois de `Inserir acorde` ou transposição por setas:** esses comandos não passam pelo encaixe. Se importa, mova a nota uma linha com o mouse (mover de linha aplica o encaixe).
