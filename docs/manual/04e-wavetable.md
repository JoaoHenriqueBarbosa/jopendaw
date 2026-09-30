# Sintetizador wavetable

> Instrumento que lê tabelas de formas de onda e permite "passear" entre elas com um botão, o LFO ou um envelope: serve para pads que mudam de timbre sozinhos, leads com PWM, vozes, plucks digitais e sons metálicos.

## Onde fica

1. Crie a faixa: na linha do tempo, botão `+` com tooltip `Nova faixa` → item `Wavetable` (no mixer, o botão com tooltip `Nova faixa ou barramento` tem o mesmo item). A faixa nasce no padrão e o seletor de presets mostra `Inicial`. Na lista de faixas, no mixer e na aba `Instrumento`, a faixa Wavetable usa o ícone `ssid_chart` do Material (uma linha de gráfico com pontos).
2. Abra o painel: aba `Instrumento` da barra do painel inferior (tooltip `Instrumento da faixa (I)`), com a faixa selecionada.
3. No computador os cartões ficam numa fileira com rolagem horizontal; no celular, em linhas com rolagem vertical.

Os cartões, na ordem: `Oscilador 1`, `Oscilador 2`, `Mistura`, `Filtro`, `Amplitude`, `Envelope do filtro`, `LFO` e `Geral`. O cabeçalho (presets, teclado) e os gestos dos knobs são comuns a todos os instrumentos: veja [Painel de instrumento](04-painel-de-instrumento.md).

## O que é uma wavetable

Um oscilador comum toca **uma** forma de onda: serra, quadrada, senoide. Uma wavetable é uma **fileira de formas de onda** guardadas lado a lado. Aqui cada fileira (chamada de **série**) tem **8 tabelas**. O botão `Posição` escolhe em qual ponto da fileira o oscilador está lendo: em 0% ele toca a 1ª tabela, em 100% a 8ª, e no meio o som é uma **mistura suave das duas tabelas vizinhas**. Girar o botão percorre o timbre sem degraus, como girar um seletor de "mais redondo" para "mais brilhante" ou "de A para E".

Isso é diferente de um filtro: o filtro apaga harmônicos de uma onda que já existe; a `Posição` troca a própria onda. Os dois se combinam.

Como as 8 tabelas ficam distribuídas de 0 a 100%:

| Tabela | 1ª | 2ª | 3ª | 4ª | 5ª | 6ª | 7ª | 8ª |
|---|---|---|---|---|---|---|---|---|
| `Posição` | 0% | 14% | 29% | 43% | 57% | 71% | 86% | 100% |

A legenda no canto do visor mostra a mistura atual, por exemplo `Serra 90% + Quadrada 10%`. As tabelas foram construídas somando harmônicos (nada de forma desenhada e depois filtrada), então são de banda limitada e não geram aliasing; nas notas agudas o motor usa versões com menos harmônicos.

## As 3 séries e suas 8 tabelas

O menu `Série` escolhe entre `Clássica`, `Vozes` e `Digital`. Todas as tabelas são normalizadas para ter volume parecido entre si.

### `Clássica`: as formas de onda tradicionais

| Posição | Tabela | O que contém | Som |
|---|---|---|---|
| 0% | `Senoide` | Só o harmônico fundamental | Puro, redondo, sem brilho |
| 14% | `Triângulo` | Só harmônicos ímpares, caindo rápido (1/h²) | Macio e oco, parecido com flauta |
| 29% | `Serra` | Todos os harmônicos, caindo com 1/h | Brilhante e cheio, a base de baixos e cordas |
| 43% | `Quadrada` | Pulso com 50% de largura: só ímpares (1/h) | Oco, tipo clarinete |
| 57% | `Pulso 35%` | Pulso de 35% de largura | Um pouco mais nasal que a quadrada |
| 71% | `Pulso 22%` | Pulso de 22% | Nasal, fino |
| 86% | `Pulso 12%` | Pulso de 12% | Bem fino, "fanho" |
| 100% | `Pulso 6%` | Pulso de 6% | O mais estreito e agudo dos pulsos |

Do trecho `Quadrada` até `Pulso 6%` as fases são alinhadas, então **varrer a `Posição` entre 43% e 100% estreita o pulso continuamente: é uma modulação de largura de pulso (PWM)**. Com o LFO movendo a `Posição`, o som "respira" como um sintetizador analógico com PWM.

### `Vozes`: vogais e coros

As vogais são uma fonte com harmônicos em 1/h passando por três formantes (picos de ressonância da boca). As duas primeiras frequências de cada formante, calculadas para uma nota fundamental de 150 Hz:

| Posição | Tabela | Formantes principais (Hz) | Som |
|---|---|---|---|
| 0% | `A` | 800 e 1150 | Vogal "a", aberta |
| 14% | `E` | 400 e 1700 | Vogal "e" |
| 29% | `I` | 300 e 2300 | Vogal "i", fina e clara |
| 43% | `O` | 450 e 850 | Vogal "o", fechada |
| 57% | `U` | 320 e 750 | Vogal "u", a mais escura |
| 71% | `Nasal` | 280, 1100 e 2300 (estreitos) | Vogal fanha |
| 86% | `Coral` | 500, 1500 e 2500 (largos) | Coro difuso, vogal indefinida |
| 100% | `Rosnado` | Sem formantes: harmônicos com amplitude irregular | Áspero, tipo voz rouca |

Atenção: os formantes ficam em posições **fixas do espectro**, feitas para uma nota de cerca de 150 Hz (perto do Ré 3). Eles sobem junto com a nota que você toca, então as vogais são mais reconhecíveis nessa região e vão "mudando de vogal" em notas bem mais agudas ou graves. O teclado da tela começa no Dó 3, dentro dessa região.

### `Digital`: espectros de laboratório

| Posição | Tabela | O que contém | Som |
|---|---|---|---|
| 0% | `Ímpares` | Só harmônicos ímpares, caindo devagar (1/√h) | Mais áspero e "zumbido" que a quadrada |
| 14% | `Vazada` | Até o harmônico 24; os pares entram com 35% da força dos ímpares | Palhetado, oco e mais macio |
| 29% | `Ressonante` | Serra com um pico forte no 7º harmônico | Um "uóu" fixo, como filtro ressonante embutido |
| 43% | `Fibonacci` | Só os harmônicos 1, 2, 3, 5, 8, 13, 21... | Esparso, cristalino |
| 57% | `Primos` | Só os harmônicos primos (2, 3, 5, 7, 11...), sem o fundamental | Esparso e estranho; a altura percebida vem dos parciais |
| 71% | `Sino` | Harmônicos 2, 3, 4, 5, 7, 9, 12, 16, 21, 27, 35 e 44, sem o fundamental | O mais perto de "metálico" que um ciclo periódico permite |
| 86% | `Granulada` | Todos os harmônicos com fases quadráticas | Textura granulada, sem pico de crista |
| 100% | `Vidro` | Fundamental mais uma nuvem de harmônicos em torno do 13º | Senoide com um assobio brilhante em cima |

## Controles

### Cartões `Oscilador 1` e `Oscilador 2`

Cada um tem o mesmo conjunto de 5 controles. O visor mostra um ciclo da onda na posição atual (a mistura das duas tabelas vizinhas), com a altura proporcional ao `Nível`, e uma régua de 8 casinhas embaixo: as duas tabelas em jogo ficam acesas e, se o LFO ou o envelope movem a posição, a faixa que eles varrem aparece em tom mais fraco. A legenda diz o nome da tabela ou da mistura. O cartão `Oscilador 2` fica esmaecido (mas mexível) quando o `Nível` dele é 0%.

| Controle (rótulo exato) | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| `Série` | Escolhe a série de tabelas do oscilador (menu). | `Clássica`, `Vozes`, `Digital`. Padrão `Clássica` nos dois | Cada oscilador tem a sua série: dá para misturar uma vogal com um pulso. |
| `Posição` | Ponto da fileira em que o oscilador lê, misturando as tabelas vizinhas. | 0–100%, linear. Padrão: osc. 1 = 30% (`Serra 90% + Quadrada 10%`), osc. 2 = 50% (`Quadrada 50% + Pulso 35% 50%`) | O botão mais importante do instrumento. Automatize-o para morfar no tempo. |
| `Nível` | Volume do oscilador. | 0–100%. Padrão: osc. 1 = 80%, osc. 2 = 50% | Com 0% o oscilador some e o cartão esmaece. |
| `Semitons` | Transposição em semitons inteiros. | −24 a +24 st, padrão +0 st | +12 ou −12 para dobrar uma oitava acima ou abaixo. |
| `Desafinação` | Ajuste fino em cents. | −100 a +100 ct. Padrão: osc. 1 = +0 ct, osc. 2 = +7 ct | O padrão de +7 ct no osc. 2 faz um leve batimento (efeito de dois osciladores analógicos). |

### Cartão `Mistura`

O visor mostra 4 barras (`Osc 1`, `Osc 2`, `Sub`, `Ruído`) com os níveis, e `×N` no canto quando o uníssono é maior que 1.

| Controle (rótulo exato) | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| `Sub` | Senoide uma oitava **abaixo** da nota tocada, no centro do estéreo. Não é afetada por `Semitons`, `Desafinação` nem pelo uníssono. | 0–100%, padrão 0% | Engorda baixos; segura o grave mesmo com uníssono largo. |
| `Ruído` | Ruído branco no centro do estéreo, também fora do uníssono. | 0–100%, padrão 0% | Um pouco de ruído com filtro passa-banda faz sopro (`Sopro vocal`). |
| `Uníssono` | Número de cópias de cada oscilador tocando juntas, levemente desafinadas e espalhadas no estéreo. | 1–7, padrão 1 | Cada nota usa N cópias dos dois osciladores: o custo de CPU cresce com N. Com 1 cópia a fase de partida é sempre a mesma; com 2 ou mais as fases partem aleatórias. |
| `Desafino` | Largura da desafinação entre as cópias do uníssono: as cópias das pontas ficam a metade desse valor acima e abaixo da nota. | 0–100 ct, padrão 20 ct | 10 a 25 ct para supersaw suave; mais que 40 fica "desafinado". Esmaecido quando `Uníssono` é 1. |
| `Espalhar` | Quanto as cópias se abrem entre esquerda e direita. | 0–100%, padrão 50% | 0% = todas no centro; 100% = as extremas totalmente nos lados. Esmaecido quando `Uníssono` é 1. |

**Por que `Desafino` e `Espalhar` aparecem esmaecidos com `Uníssono` em 1.** Os dois só distribuem as cópias do uníssono: `Desafino` afasta as afinações delas e `Espalhar` abre a posição delas no panorama. Com uma cópia só, não há com quem afastar: essa cópia fica no centro e na afinação exata, então mexer nos dois knobs não muda nada no som. O painel os apaga como aviso de "sem efeito agora". Continuam mexíveis, e o valor fica guardado: ao subir `Uníssono` para 2 ou mais, eles voltam a valer e ganham cor.

### Cartão `Filtro`

Filtro de 12 dB por oitava (2 polos). O visor mostra a curva do filtro com corte e ressonância atuais. O `Corte` é o ponto de partida: o envelope do filtro (cartão `Envelope do filtro`), o knob `Teclado` e o `Filtro` do LFO deslocam o corte por cima dele.

| Controle (rótulo exato) | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| `Tipo` | Tipo do filtro (menu). | `Passa-baixa`, `Passa-alta`, `Passa-banda`. Padrão `Passa-baixa` | Passa-baixa tira brilho; passa-alta tira graves; passa-banda deixa uma faixa, ótimo para sopro e som de rádio. |
| `Corte` | Frequência de corte. | 20 Hz–20 kHz, escala logarítmica, padrão 8,00 kHz | O motor não deixa o corte passar de 45% da taxa de amostragem. |
| `Ressonância` | Realce de volume ao redor do corte. | 0–100%, padrão 10% | Vai de Q 0,5 a Q 16. O motor limita picos exagerados de ressonância para não estourar. |
| `Envelope` | Quanto o envelope do filtro mexe no corte. Positivo abre, negativo fecha. | −100% a +100%, padrão 0%. 100% = 6 oitavas | 50% = 3 oitavas. Em notas fracas (`Sens. vel.` do cartão `Geral` alta) o efeito é menor. |
| `Teclado` | Quanto o corte acompanha a altura da nota, a partir do Dó 4. | 0–100%, padrão 50% | 100% mantém o brilho constante do grave ao agudo; 0% deixa o corte fixo. |

### Cartão `Amplitude`

O volume da nota no tempo (envelope ADSR). O desenho ao lado é um visor: subida linear, quedas exponenciais, tempos em escala logarítmica. **Ele não é arrastável**: use os quatro knobs.

| Controle (rótulo exato) | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| `Ataque` | Tempo para o volume subir de 0 a 100%. | 0,5 ms–10 s, log, padrão 5,0 ms | Pad: 500 ms a 1,2 s. Pluck: 1 ms. |
| `Decaimento` | Tempo para cair de 100% até a `Sustentação`. | 1 ms–10 s, log, padrão 300 ms | |
| `Sustentação` | Nível mantido com a tecla presa. | 0–100%, padrão 80% | Com 0% a nota decai até o silêncio mesmo com a tecla presa (pluck). |
| `Soltura` | Tempo de sumir depois de soltar a tecla. | 1 ms–10 s, log, padrão 300 ms | |

### Cartão `Envelope do filtro`

Um segundo envelope ADSR que age sobre o corte do filtro (na quantidade do knob `Envelope` do cartão `Filtro`) **e** sobre a posição das tabelas (na quantidade do knob `Posição (env. do filtro)`). O cartão fica esmaecido, com a legenda `sem efeito: filtro e posição em 0`, quando os dois valores são 0.

| Controle (rótulo exato) | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| `Ataque` | Tempo de subida do envelope. | 0,5 ms–10 s, log, padrão 5,0 ms | |
| `Decaimento` | Tempo de queda até a `Sustentação`. | 1 ms–10 s, log, padrão 500 ms | |
| `Sustentação` | Nível mantido com a tecla presa. | 0–100%, padrão 30% | |
| `Soltura` | Tempo de queda depois de soltar. | 1 ms–10 s, log, padrão 400 ms | |
| `Posição (env. do filtro)` | Quanto este envelope empurra a `Posição` dos dois osciladores. Positivo: a posição sobe com o envelope e volta à base quando ele cai; negativo: desce. | −100% a +100%, padrão 0% (a fração é do percurso total, então 50% andam 3,5 das 7 casas) | Plucks: `Posição` base baixa e este knob positivo, para o ataque ser rico e o fim mais simples. O rótulo é longo e aparece em fonte menor. |

O envelope do filtro e a `Posição (env. do filtro)` compartilham os mesmos tempos.

### Cartão `LFO`

Um oscilador lento que mexe em quatro coisas, cada uma com sua profundidade. Há **um LFO por faixa**, livre (em Hz, sem sincronia com o andamento) e compartilhado por todas as notas: ele não recomeça a cada nota. Com as quatro profundidades em 0 o cartão esmaece com a legenda `sem efeito: vibrato, filtro, tremolo e posição em 0`, e `Onda` e `Taxa` ficam apagados.

| Controle (rótulo exato) | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| `Onda` | Forma do LFO (menu). | `Senoide`, `Triângulo`, `Serra`, `Quadrada`, `Aleatório`. Padrão `Senoide` | `Triângulo` varre a posição para cima e para baixo igualmente; `Aleatório` salta de valor em valor (textura granular); `Quadrada` alterna entre duas posições. |
| `Taxa` | Frequência do LFO. | 0,05–30 Hz, log, padrão 4,00 Hz | Morfar pad: 0,1 a 0,3 Hz. PWM: cerca de 2 Hz. |
| `Vibrato` | Quanto o LFO balança a altura. | 0–12 st, padrão +0 st | 0,1 a 0,3 st para vibrato musical. |
| `Filtro` | Quanto o LFO balança o corte do filtro. | 0–4 oitavas (`0.0 oit`), padrão 0 | Efeito de "wah" lento com valores de 1 a 2 oitavas. |
| `Tremolo` | Quanto o LFO balança o volume. | 0–100%, padrão 0% | |
| `Posição` | Quanto o LFO empurra a `Posição` dos dois osciladores para cada lado da posição-base. | −100% a +100%, padrão 0% (fração do percurso: 18% andam cerca de 1,3 tabela para cada lado) | Valor negativo inverte o sentido do movimento. |

A posição efetiva de cada oscilador é: `Posição` do cartão do oscilador + LFO × `Posição` do LFO + envelope × `Posição (env. do filtro)`, sempre presa entre 0% e 100% (sem "dar a volta"). Se o LFO pede mais que o extremo, a posição fica parada no extremo por um instante: deixe a posição-base afastada das pontas (ou reduza a profundidade) para o movimento não achatar.

### Cartão `Geral`

O visor diz `Mono · legato` ou `Poli · N vozes` e `Glide` com o tempo ou `Sem glide`.

| Controle (rótulo exato) | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| `Glide` | Tempo de deslizar de uma nota para a próxima. | 0–2 s, padrão 0 (sem glide) | Leads mono: 50 a 80 ms. |
| `Vozes` | Máximo de notas ao mesmo tempo. Com 1 vira mono com legato. | 1–16, padrão 8 | Passando do limite, sai num fade de 5 ms a mais baixa entre as notas já soltas ou, se todas estão presas, a mais antiga. |
| `Sens. vel.` | Sensibilidade à velocidade (força) da nota. Não confundir com a `Taxa` do LFO. | 0–100%, padrão 70% | Também reduz a profundidade do envelope do filtro e da `Posição (env. do filtro)` em notas fracas (até a metade). |
| `Volume` | Volume de saída do instrumento. | 0–150%, padrão 70% | |

### Presets do wavetable

O seletor de presets (tooltip `Presets`, com as setas `Anterior (preset)` e `Próximo (preset)` no computador) lista 16 presets em 7 categorias. Aplicar um preset **substitui todos os parâmetros**: o que ele não cita volta ao padrão (inclusive `Volume`, `Vozes` e o LFO). É um passo só no desfazer. Depois de mexer num knob o seletor mostra o nome do preset seguido de `(editado)`. Não há como guardar presets próprios.

**Baixos** (mono, `Vozes` 1)

| Preset | Caráter |
|---|---|
| `Baixo sub` | Osc. 1 senoide (90%), osc. 2 triângulo uma oitava abaixo (30%), `Sub` 35%, corte 900 Hz. Grave redondo e firme, com `Glide` de 20 ms. |
| `Baixo serra` | Osc. 1 serra, osc. 2 quadrada uma oitava abaixo (50%), `Sub` 30%, corte 500 Hz, ressonância 30% e `Envelope` +60%: baixo analógico com "uóu" curto do filtro. |
| `Baixo digital` | Série `Digital`: `Ímpares` mais `Fibonacci` uma oitava abaixo, corte 1,4 kHz, `Envelope` +70% e `Posição (env. do filtro)` +40%: o ataque é brilhoso e a nota assenta no grave. |

**Leads** (mono)

| Preset | Caráter |
|---|---|
| `Lead PWM` | Dois osciladores nos pulsos (71% e 75%, desafinados +9 ct), `Uníssono` 3 com `Desafino` 18 ct, `LFO` triângulo a 2,2 Hz com `Posição` 18%: o pulso abre e fecha devagar. `Glide` 50 ms. |
| `Lead vocal` | Série `Vozes` em `E`, com um segundo oscilador uma oitava acima (35%), `Vibrato` 0,2 st a 5,2 Hz e `Posição` do LFO 8%, ataque de 30 ms e `Glide` 70 ms: voz que canta a melodia. |
| `Lead ácido` | Série `Digital` (`Ressonante` mais `Primos` desafinado +12 ct), corte 1,8 kHz, ressonância 50%, `Envelope` +60% e `Posição (env. do filtro)` +30%: lead ácido com `Glide` de 80 ms. |

**Pads**

| Preset | Caráter |
|---|---|
| `Pad morfante` | Osc. 1 `Clássica` a 15% e osc. 2 `Vozes` a 20% (40%, +9 ct), `Uníssono` 4 com `Desafino` 25 ct e `Espalhar` 80%. O LFO senoide a 0,12 Hz com `Posição` 35% varre a série devagar: o timbre nunca fica parado. Ataque de 0,9 s, soltura de 1,8 s. |
| `Pad de vozes` | `Vozes` em `A` mais `U` uma oitava acima (25%), `Uníssono` 3, `LFO` a 0,09 Hz com `Posição` 50%: coro que percorre as vogais. Ataque de 0,8 s, soltura de 2 s. |
| `Pad de vidro` | Série `Digital`: `Vidro` e `Granulada` (35%, +12 st, +6 ct), `Uníssono` 3 com `Espalhar` 90%, corte 9 kHz, LFO triângulo a 0,2 Hz. Ataque de 1,2 s, soltura de 2,2 s. |

**Vocais**

| Preset | Caráter |
|---|---|
| `Coro AEIOU` | Dois osciladores `Vozes` a 25% (o 2º em 50% e +14 ct), `Uníssono` 2, LFO triângulo a 0,35 Hz com `Posição` 45%: percorre A, E, I, O, U e volta. Ataque 250 ms, soltura 700 ms. |
| `Sopro vocal` | Osc. 1 `Vozes` em `A`, osc. 2 mudo, `Ruído` 22%, filtro `Passa-banda` em 1,8 kHz com ressonância 40%: respiração com cor de vogal. |

**Plucks**

| Preset | Caráter |
|---|---|
| `Pluck digital` | Série `Digital` a 15% (perto de `Vazada`), corte 700 Hz, `Envelope` +80% e `Posição (env. do filtro)` +50%, sustentação 0%: ataque rico que cai rápido para um timbre mais simples. |
| `Kalimba` | Senoide mais `Sino` uma oitava acima (30%), corte 6 kHz, decaimento de 0,6 s, sem sustentação. |
| `Sino metálico` | `Sino` mais `Primos` (40%, +7 st, +3 ct), corte 9 kHz, decaimento de 1,5 s e `Tremolo` 20% a 4 Hz. |

**Teclas**

| Preset | Caráter |
|---|---|
| `Teclas de cristal` | `Triângulo` mais `Ressonante` uma oitava acima (35%), `Envelope` +30% e `Posição (env. do filtro)` +30%, decaimento de 0,9 s e sustentação 20%. |

**Texturas**

| Preset | Caráter |
|---|---|
| `Granular` | `Granulada` (86%) com LFO `Aleatório` a 7 Hz e `Posição` 40%: a posição salta de tabela em tabela, textura granular. |

## Passo a passo

**1. Tocar um som pronto e morfar**
1. Crie a faixa `Wavetable`, abra a aba `Instrumento` e escolha `Pad morfante`.
2. Segure uma nota (teclado da tela, do computador ou MIDI) e gire a `Posição` do `Oscilador 1`. Olhe o visor: a forma de onda muda junto.
3. Escolha outra `Série` no menu e repita para ouvir a diferença entre elas.

**2. Fazer PWM**
1. No `Oscilador 1`, série `Clássica`, `Posição` 71%.
2. No cartão `LFO`, `Onda` `Triângulo`, `Taxa` 2,2 Hz, `Posição` 18%.
3. Se quiser mais corpo, ponha `Nível` do `Oscilador 2` em 60%, com a mesma série e `Posição` 75%, e `Uníssono` 3.

**3. Engrossar com uníssono**
1. No cartão `Mistura`, `Uníssono` 3 a 5.
2. Ajuste `Desafino` (largura de afinação) e `Espalhar` (abertura no estéreo). Enquanto o `Uníssono` estiver em 1, os dois estão esmaecidos e não fazem nada.
3. Se o grave ficou fino, suba `Sub`: ele não entra no uníssono e fica no centro.

**4. Timbre que muda ao longo da nota (pluck)**
1. Ponha `Posição` baixa (por exemplo 15%) e `Sustentação` da `Amplitude` em 0%.
2. No cartão `Filtro`, `Envelope` +80%; no cartão `Envelope do filtro`, `Decaimento` 180 ms, `Sustentação` 0% e `Posição (env. do filtro)` +50%.
3. Cada nota começa em uma posição mais rica e cai para a posição-base junto com o filtro.

**5. Automatizar a posição**
1. No cabeçalho da faixa na linha do tempo, botão com tooltip `Automação`.
2. Escolha o item `Wavetable`, e no segundo menu, sob o título `OSCILADOR 1`, o item `Posição`.
3. Clique na sub-raia para criar pontos. Veja [Automação](07-automacao.md).

## Combina com

- [Painel de instrumento](04-painel-de-instrumento.md): presets, teclado da tela, MIDI, gestos dos knobs.
- [Sintetizador subtrativo](04a-sintetizador.md): o `Filtro`, o `Uníssono` e o `LFO` do wavetable são iguais aos do subtrativo; o que muda é a fonte do som (tabelas morfáveis em vez de 4 formas fixas).
- [FM](04d-fm.md): para sons metálicos e percussivos que a wavetable não alcança tão bem.
- [Painel de efeitos](06c-painel-de-efeitos.md) e [Referência dos efeitos](06d-efeitos-referencia.md): `Chorus`, `Reverb` e `Delay` sobre pads e leads.
- [Automação](07-automacao.md): a `Posição` de cada oscilador é automatizável e é a forma de morfar sincronizado com o andamento (o LFO é livre, em Hz).
- [Piano roll](05-piano-roll.md): a velocidade das notas influencia volume e profundidade do envelope do filtro.
- Guia: [FM e Wavetable na prática](../guias/fm-e-wavetable-na-pratica.md).

## Limites e pegadinhas

- **`Posição` presa entre 0% e 100%**: LFO e envelope somam à posição-base e o resultado é cortado nas pontas (não dá a volta da 8ª tabela para a 1ª).
- **O LFO é um só e livre**: não recomeça a cada nota e não é sincronizado com o andamento. Duas notas juntas se movem juntas. Para um morfar alinhado ao compasso, automatize a `Posição`.
- **Vogais dependem da nota**: os formantes da série `Vozes` acompanham a altura (feitos para cerca de 150 Hz), então a vogal muda em notas muito mais altas ou mais baixas.
- **`Primos` e `Sino` não têm o fundamental**: a altura que se ouve vem dos parciais; em notas graves podem soar mais agudos ou ambíguos.
- **Dois osciladores com o mesmo nome de knob**: `Série`, `Posição`, `Nível`, `Semitons` e `Desafinação` aparecem nos dois cartões; `Posição` ainda aparece no LFO e (como `Posição (env. do filtro)`) no envelope. No menu de automação, cada um fica sob o título do próprio cartão.
- **Presets apagam ajustes**: aplicar um preset sobrescreve tudo, inclusive `Volume`, `Vozes` e o LFO. `Ctrl+Z` (`Cmd+Z` no Mac) desfaz.
- **Sem sustentação, a nota morre**: com `Sustentação` da `Amplitude` em 0% a nota decai até o silêncio mesmo com a tecla presa.
- **Custo**: 16 vozes, cada uma com até 7 cópias de 2 osciladores; em celular fraco, prefira `Uníssono` menor e `Vozes` menor. (Custo estimado pela estrutura do código; não medido.)
- **Web e Android**: motor idêntico (WASM no navegador, nativo no Android); o painel muda só de disposição, e no celular o seletor de presets não tem as setas.

## Atalhos

| Tecla / gesto | Ação |
|---|---|
| `I` | Abre ou fecha o painel na aba `Instrumento` (tooltip `Instrumento da faixa (I)`); `Esc` fecha o painel |
| `Ctrl+K` (`Cmd+K` no Mac) | Liga e desliga o teclado do computador como teclado musical |
| Arrastar um knob na vertical | Muda o valor (200 px cobrem a faixa inteira); um arraste é um passo do desfazer |
| `Shift` + arrastar | Ajuste fino (cinco vezes mais lento) |
| Roda do mouse sobre o knob | Muda o valor (`Shift` = fino); em valores inteiros (`Semitons`, `Uníssono`, `Vozes`) anda um passo por "dente" |
| Duplo clique num knob | Volta ao padrão |
| Botão direito (ou toque longo no celular) num knob | Abre um campo para digitar o valor, com unidade se quiser: `50%`, `250 ms`, `+7 ct`, `2.4 kHz` |
| `Z` / `X` (teclado do computador ligado) | Oitava abaixo / acima |
| `C` / `V` (teclado do computador ligado) | Velocidade menor / maior das notas tocadas |
