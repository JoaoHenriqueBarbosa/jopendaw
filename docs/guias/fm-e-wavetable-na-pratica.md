# FM e Wavetable na prática

> Seis sons prontos para fazer com os instrumentos `FM` e `Wavetable` (sino elétrico, baixo FM, pad morfante, lead com PWM, coro vocal e som metálico), mais como vesti-los com Chorus, Reverb e Delay e como automatizar a posição da wavetable. Cada receita leva de 3 a 5 minutos.

Os valores abaixo vêm dos presets do app (o nome do preset equivalente aparece em cada receita: aplicá-lo já dá o ponto de partida) e das tabelas de parâmetros do código. O que se ouve **não foi conferido de ouvido** ao escrever este guia (não confirmado ao ouvido); use os números como ponto de partida e acerte por ouvido.

## Ingredientes

- Instrumento [FM](../manual/04d-fm.md): 4 operadores senoidais, 8 algoritmos, realimentação. Saída mono.
- Instrumento [Wavetable](../manual/04e-wavetable.md): 2 osciladores de tabela, uníssono, filtro, LFO. Saída estéreo.
- [Painel de instrumento](../manual/04-painel-de-instrumento.md): seletor de presets, teclado, gestos dos knobs (botão direito ou toque longo para digitar o valor).
- [Painel de efeitos](../manual/06c-painel-de-efeitos.md) e [Referência dos efeitos](../manual/06d-efeitos-referencia.md): `Chorus`, `Reverb` e `Delay`, com presets próprios (menu com tooltip `Presets e mais` em cada efeito).
- [Automação](../manual/07-automacao.md): para mexer na `Posição` da wavetable no tempo.
- [Piano roll](../manual/05-piano-roll.md): para escrever as notas de teste.

Convenções: `Razão` na forma `×3.5`; percentuais como no painel; tempos em `ms` ou `s` (digite com a unidade: `250 ms`).

## Passo a passo

### Receita 1: sino elétrico (FM)

Preset equivalente: `Sino elétrico` (categoria `Percussivos`).

1. Crie uma faixa `FM`. No cartão `Algoritmo` deixe o `Algoritmo 5: (1→2) + (3→4)` (o padrão): dois pares, cada modulador com o seu portador.
2. Preencha os operadores:

| | Razão | Nível | Ataque | Decaimento | Sustentação | Soltura | Sens. vel. |
|---|---|---|---|---|---|---|---|
| Operador 1 (modulador) | ×3.5 | 50% | 1,0 ms | 2,50 s | 0% | 1,00 s | 50% |
| Operador 2 (portador) | ×1.00 | 75% | 1,0 ms | 4,00 s | 0% | 1,50 s | 30% |
| Operador 3 (modulador) | ×7.00 | 35% | 1,0 ms | 1,00 s | 0% | 500 ms | 50% |
| Operador 4 (portador) | ×2.00 | 40% | 1,0 ms | 2,50 s | 0% | 1,20 s | 30% |

3. `Realimentação` 0%; `Vozes` 8; `Volume` 70% (o padrão).
4. Toque notas curtas e soltas: as solturas longas deixam as notas se misturarem.

Por quê: razões 3,5 e 7 não são múltiplos inteiros da nota, então os parciais que nascem não formam uma série harmônica, e o ouvido lê isso como sino.

### Receita 2: baixo FM

Preset equivalente: `Baixo DX` (categoria `Baixos`).

1. Crie uma faixa `FM` e escolha o `Algoritmo 1: 1→2→3→4` (cadeia inteira, um só portador).
2. Cartão `Geral`: `Vozes` 1 (mono com legato).
3. Cartão `Algoritmo`: `Realimentação` 15%.
4. Operadores:

| | Razão | Nível | Ataque | Decaimento | Sustentação | Soltura | Sens. vel. |
|---|---|---|---|---|---|---|---|
| Operador 1 (modulador) | ×1.00 | 45% | 1,0 ms | 350 ms | 10% | 100 ms | 60% |
| Operador 2 (modulador) | ×1.00 | 50% | 1,0 ms | 400 ms | 20% | 100 ms | 50% |
| Operador 3 (modulador) | ×2.00 | 30% | 1,0 ms | 150 ms | 0% | 100 ms | 50% |
| Operador 4 (portador) | ×1.00 | 85% | 1,0 ms | 400 ms | 60% | 120 ms | 30% |

5. Teste tocando notas graves (uma ou duas oitavas abaixo do Dó central) e variando a força da nota: com `Sens. vel.` maior nos moduladores, notas fortes ficam mais brilhantes.

Por quê: os moduladores caem em 150 a 400 ms e levam o brilho junto; o portador (operador 4) segura o corpo. É o "estalo" de baixo de DX.

### Receita 3: pad morfante (Wavetable)

Preset equivalente: `Pad morfante` (categoria `Pads`).

1. Crie uma faixa `Wavetable`.
2. `Oscilador 1`: `Série` `Clássica`, `Posição` 15%, `Nível` 80%.
3. `Oscilador 2`: `Série` `Vozes`, `Posição` 20%, `Nível` 40%, `Desafinação` +9 ct.
4. `Mistura`: `Uníssono` 4, `Desafino` 25 ct, `Espalhar` 80%.
5. `Filtro`: `Corte` 4,20 kHz (o resto no padrão).
6. `Amplitude`: `Ataque` 900 ms, `Decaimento` 1,00 s, `Sustentação` 80%, `Soltura` 1,80 s.
7. `LFO`: `Onda` `Senoide`, `Taxa` 0,12 Hz, `Posição` 35%.
8. `Geral`: `Sens. vel.` 30% (notas fracas e fortes soam parecidas, o que ajuda em pad).
9. Segure um acorde longo: o timbre percorre de "redondo" para "vocal" e volta, em ciclos de uns 8 segundos.

### Receita 4: lead com PWM (Wavetable)

Preset equivalente: `Lead PWM` (categoria `Leads`).

1. Crie uma faixa `Wavetable`.
2. `Oscilador 1`: `Série` `Clássica`, `Posição` 71% (`Pulso 22%`).
3. `Oscilador 2`: `Série` `Clássica`, `Posição` 75%, `Nível` 60%, `Desafinação` +9 ct.
4. `Mistura`: `Uníssono` 3, `Desafino` 18 ct.
5. `Filtro`: `Corte` 5,50 kHz, `Envelope` +20%. No `Envelope do filtro`, os padrões servem.
6. `LFO`: `Onda` `Triângulo`, `Taxa` 2,20 Hz, `Posição` 18%.
7. `Amplitude`: `Sustentação` 85%, `Soltura` 200 ms. `Geral`: `Vozes` 1, `Glide` 50 ms.
8. Toque uma nota longa: o pulso abre e fecha continuamente entre uns 40% e uns 10% de largura.

Por quê: na série `Clássica` as tabelas de `Quadrada` até `Pulso 6%` são pulsos com a mesma fase inicial; passear a `Posição` por elas é variar a largura do pulso, que é o PWM. O LFO faz esse passeio.

### Receita 5: coro vocal (Wavetable)

Preset equivalente: `Coro AEIOU` (categoria `Vocais`).

1. Crie uma faixa `Wavetable`.
2. `Oscilador 1`: `Série` `Vozes`, `Posição` 25%. `Oscilador 2`: `Série` `Vozes`, `Posição` 25%, `Nível` 50%, `Desafinação` +14 ct.
3. `Mistura`: `Uníssono` 2, `Desafino` 16 ct.
4. `Filtro`: `Corte` 6,50 kHz.
5. `Amplitude`: `Ataque` 250 ms, `Soltura` 700 ms.
6. `LFO`: `Onda` `Triângulo`, `Taxa` 0,35 Hz, `Posição` 45%.
7. Toque acordes em região média (a partir do Dó 3): a vogal passeia de A até U e volta.

Por quê: as tabelas da série `Vozes` são A, E, I, O, U nessa ordem, então o LFO em triângulo percorre as vogais. As vogais foram calculadas para uma nota fundamental perto de 150 Hz; em notas muito agudas a vogal muda.

### Receita 6: som metálico (FM)

Preset equivalente: `Gongo` (categoria `Metais`).

1. Crie uma faixa `FM` e escolha o `Algoritmo 7: (1→2) + 3 + 4`: um par modulado mais duas senoides puras.
2. `Realimentação` 40%.
3. Operadores:

| | Razão | Nível | Ataque | Decaimento | Sustentação | Soltura | Sens. vel. |
|---|---|---|---|---|---|---|---|
| Operador 1 (modulador) | ×1.41 | 70% | 1,0 ms | 4,00 s | 0% | 3,00 s | 40% |
| Operador 2 (portador) | ×1.00 | 60% | 1,0 ms | 5,00 s | 0% | 3,00 s | 30% |
| Operador 3 (portador, senoide pura) | ×2.76 | 40% | 1,0 ms | 3,00 s | 0% | 3,00 s | 40% |
| Operador 4 (portador, senoide pura) | ×5.40 | 25% | 1,0 ms | 1,50 s | 0% | 2,00 s | 40% |

4. Toque notas graves e deixe soar (soltura de 2 a 3 s).

Por quê: razões como 1,41, 2,76 e 5,4 não são inteiras: os parciais ficam "fora da série" e o timbre perde a altura clara, como um gongo. A realimentação suja o operador 1 e dá o rugido.

Variação com wavetable: o preset `Sino metálico` (série `Digital`, `Posição` 71% = `Sino` no osc. 1 e 57% = `Primos` no osc. 2, +7 st, +3 ct, `Decaimento` 1,5 s, `Tremolo` 20% a 4 Hz) faz um metal mais "digital".

### Combinando com efeitos

Todos os efeitos se adicionam na aba `Efeitos` (botão `Adicionar efeito`): `Chorus` na família `Modulação`; `Reverb` e `Delay` em `Espaço`. Os efeitos da faixa processam o som **em série, da esquerda para a direita** (de cima para baixo no celular) e a ordem se muda arrastando o título do cartão.

| Receita | Efeitos sugeridos (o nome é o do preset do efeito) |
|---|---|
| 1. Sino elétrico | `Chorus` preset `Chorus leve` (abre o estéreo, já que o FM é mono) e depois `Reverb` preset `Placa` (densa e brilhante, combina com metal). |
| 2. Baixo FM | Em geral, nenhum efeito de espaço: baixo fica melhor seco e centrado. Se precisar segurar os picos, um `Compressor` no padrão (`Limiar` −18 dB, `Razão` 4:1). |
| 3. Pad morfante | `Reverb` preset `Salão` (`Mistura` 28%, `Decaimento` 2,80 s). Se quiser mais movimento, `Chorus` preset `Ensemble` com a `Mistura` reduzida para 25 a 30%: o pad já tem uníssono e chorus demais engorda em excesso. |
| 4. Lead PWM | `Delay` preset `1/8 pontilhado` (`Tempo` `Andamento`, `Nota` `1/8D`, `Realimentação` 35%, `Ducking` 30%: o eco abaixa enquanto você toca e sobe entre as frases) e um pouco de `Reverb` preset `Sala`. |
| 5. Coro vocal | `Reverb` preset `Catedral` (`Decaimento` 7,00 s) ou `Salão`; `Chorus` preset `Ensemble` para o efeito de vários cantores. |
| 6. Som metálico | `Reverb` preset `Catedral` ou `Placa`. Para sujar: `Distorção` com `Tipo` `Dobra` e `Mistura` em 25%. |

Regras práticas:

- **FM sai em mono**: o primeiro efeito de estéreo (Chorus, Reverb, Delay em `Ping-pong`) é quem abre a imagem. Wavetable com `Uníssono` maior que 1 e `Espalhar` acima de 0% já sai aberta.
- **Chorus antes do Reverb**: a cauda do reverb sai limpa, sem modulação em cima dela.
- **Delay em `Andamento`** (não em `Livre`) mantém os ecos no tempo da música; a `Nota` escolhe a divisão.
- **Sub e graves**: `Sub` e sons abaixo do Dó 2 não gostam de reverb; se necessário use `Cortar graves` no `Reverb` (padrão 120 Hz) ou envie só uma parte do sinal por um envio de barramento (veja [Mixer](../manual/06-mixer.md)).

### Automatizando a posição da wavetable

O LFO da wavetable é livre (em Hz) e não acompanha o andamento. Para um morfar que chega exatamente ao compasso 5, automatize a `Posição`:

1. Na linha do tempo, no cabeçalho da faixa `Wavetable`, botão com tooltip `Automação`.
2. Item `Wavetable` → no segundo menu, sob o título `OSCILADOR 1`, item `Posição`. Aparece uma sub-raia embaixo da faixa. Repita para o `Oscilador 2` se quiser mexer nos dois.
3. Clique no vazio da sub-raia para criar pontos: por exemplo, ponto em 0% no compasso 1 e ponto em 100% no compasso 9. Arraste os pontos para ajustar; a alça no meio do segmento entorta a curva.
4. Toque: o knob `Posição` acompanha a curva enquanto o projeto toca.

Como a automação, o LFO e o envelope **somam** na mesma posição (e o resultado é preso entre 0% e 100%), deixe o `Posição` do LFO em 0% quando quiser que só a automação mande, ou use LFO com profundidade pequena (5% a 10%) por cima para dar vida ao movimento. Outros alvos que rendem: `Corte` (abrir o filtro numa subida), `Nível` do `Oscilador 2` (fazer entrar uma camada) e, no FM, o `Nível` de um modulador (abre e fecha o brilho).

## Variações

- **Sino em wavetable**: `Wavetable`, `Oscilador 1` `Clássica` 0% (senoide) e `Oscilador 2` `Digital` 71% (`Sino`) uma oitava acima (`Semitons` +12) com `Nível` 30%, `Amplitude` `Decaimento` 600 ms e `Sustentação` 0% (é o preset `Kalimba`).
- **Baixo em wavetable**: `Baixo sub` (`Clássica` senoide mais triângulo abaixo, `Sub` 35%, `Vozes` 1) para um grave redondo, sem o brilho do FM.
- **Pad de FM**: `Cordas FM` (`Algoritmo 6`, três portadores desafinados ±6 ct, `Brilho` do LFO 25% a 0,35 Hz) quando o pad precisa ser mais "vidro" que "voz".
- **Lead vocal**: `Lead vocal` (série `Vozes` em `E`, `Vibrato` 0,2 st a 5,2 Hz, `Glide` 70 ms).
- **Pluck que cai de timbre**: `Pluck digital`: `Posição` base 15% (série `Digital`), `Posição (env. do filtro)` +50% e `Sustentação` 0%.

## Por que funciona

- **FM**: quem soa é o portador; o modulador só decide **quanto brilho** ele tem. Envelope curto no modulador dá ataque brilhante que assenta; razão inteira dá altura clara, razão quebrada dá sino. Muitos dos sons clássicos de FM são só variações de razão, nível e envelope do modulador em um dos 8 algoritmos.
- **Wavetable**: em vez de mudar a onda com um filtro, você escolhe **onde na fileira de 8 tabelas** o oscilador lê. Como a `Posição` é contínua e pode ser movida por LFO, envelope e automação (somando), o timbre nunca precisa ficar parado.
- **Efeitos**: FM é mono e limpo, então ganha muito com efeito de estéreo; wavetable com uníssono já traz largura, então pede efeito com mais moderação. Efeitos de tempo (`Delay` em `Andamento`) devem seguir o andamento do projeto.
- **Reaproveitar**: troque a série e mantenha os números (LFO em `Posição`, uníssono, envelope) para ter variações de uma mesma receita; troque o algoritmo no FM mantendo razões e envelopes para ver como o mesmo material se comporta.

## Se der errado

- **O FM está agudo demais, "chiado"**: abaixe o `Nível` dos moduladores ou a `Realimentação`. Em notas muito agudas o timbre já escurece sozinho, porque o motor limita o índice.
- **O sino do FM não soa como sino**: verifique se as razões do modulador são quebradas (3,5 ou 7), não 1 ou 2, e se a `Sustentação` dos portadores está em 0%.
- **A nota do FM some antes de eu soltar a tecla**: é a `Sustentação` em 0% de todos os portadores; suba a de pelo menos um deles.
- **Trocar de algoritmo mudou o brilho de repente**: o `Nível` de um operador é volume quando ele é portador e brilho quando é modulador. Reajuste-o.
- **Wavetable: `Desafino` e `Espalhar` esmaecidos**: o `Uníssono` está em 1. Com uma cópia só, não há o que espalhar; suba o `Uníssono` para 2 ou mais.
- **A `Posição` não muda o som**: confira o `Nível` do oscilador (0% deixa o cartão esmaecido) e a `Série`; se a nota é muito aguda e o filtro está fechado, o `Corte` pode estar escondendo a diferença. Lembre que `Posição` mais o movimento do LFO é preso entre 0% e 100%.
- **As vogais do coro soam todas iguais ou trocadas**: os formantes foram feitos para uma nota perto de 150 Hz (Ré 3). Toque em região média; em notas muito agudas transponha o oscilador para baixo com `Semitons` −12.
- **O LFO do pad fica em movimento demais ou de menos**: `Taxa` abaixo de 0,3 Hz para morfar; acima de 2 Hz vira vibrato de timbre.
- **Aplicar um preset apagou o meu ajuste**: o preset sobrescreve todos os parâmetros; use desfazer (`Ctrl+Z`, `Cmd+Z` no Mac) e ajuste os valores depois de escolher o preset.
