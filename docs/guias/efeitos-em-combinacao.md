# Efeitos em combinação

> Nove receitas prontas de cadeia de efeitos com valores concretos (voz, bateria em paralelo, sidechain, delay em ping-pong no andamento, pad largo, baixo distorcido, master suave com multibanda, voz com de-esser e graves em mono). Cada uma leva de 5 a 15 minutos para montar.

Todos os efeitos, parâmetros e presets citados existem no jopendaw e estão descritos em [06d Referência dos efeitos](../manual/06d-efeitos-referencia.md). Como abrir o rack, adicionar, ordenar e aplicar presets está em [06c Painel de efeitos](../manual/06c-painel-de-efeitos.md).

Duas convenções para todas as receitas:

- **Presets aplicam todos os valores.** Escolha o preset primeiro e só depois ajuste os knobs; se reaplicar o preset, os ajustes voltam.
- **"Retorno"** = um barramento com efeitos (`Reverb`, `Delay`), para onde as faixas mandam pelo `Envio` da tira do mixer. Se ainda não existe barramento, o item `Envio` da tira da faixa cria um e já manda a faixa para ele (tooltip `Criar um barramento e enviar esta faixa para ele (retorno de reverb, delay...)`); o envio nasce em −6 dB, pós-fader. No retorno, o efeito de espaço fica com `Mistura` em **100%**: o seco vai pela faixa, o molhado pelo barramento.

---

## Receita 1: cadeia vocal (gate, EQ, compressor, reverb)

> Uma voz gravada em casa, limpa, presente, nivelada e com espaço, em cerca de 10 minutos.

### Ingredientes

- `Gate` (preset `Ruído de fundo`): [Gate](../manual/06d-efeitos-referencia.md#3-gate)
- `EQ` (preset `Voz presente`): [EQ](../manual/06d-efeitos-referencia.md#1-eq-8-bandas)
- `Compressor` (preset `Voz`): [Compressor](../manual/06d-efeitos-referencia.md#2-compressor)
- Retorno de `Reverb` (preset `Placa`): [Reverb](../manual/06d-efeitos-referencia.md#6-reverb-fdn) e [06 Mixer](../manual/06-mixer.md)

### Passo a passo

1. Selecione a faixa da voz, tecle `F` e adicione **nesta ordem**: `Gate`, `EQ`, `Compressor`.
2. `Gate`: aplique `Ruído de fundo` (`Limiar` −55 dB, `Ataque` 1 ms, `Retenção` 50 ms, `Soltura` 200 ms, `Alcance` −30 dB). Toque o gráfico e toque a faixa: arraste o `Limiar` na horizontal até o medidor ficar em `0.0` durante as frases e mostrar cerca de −30 nas pausas. Se cortar o começo das palavras, baixe o `Limiar` (deixa o portão mais sensível) e mantenha o `Ataque` em 1 ms.
3. `EQ`: aplique `Voz presente` (banda 1 `Passa-alta` 90 Hz; banda 3 `Sino` 300 Hz, −2,5 dB, Q 1,2; banda 5 `Sino` 3 kHz, +3 dB, Q 0,9; banda 7 `Prateleira aguda` 10 kHz, +2 dB). Arraste o nó 3 pela faixa de 200 a 400 Hz até o "embolado" sumir; voz masculina costuma pedir o corte mais para baixo (250 Hz), feminina mais para cima (350 Hz).
4. `Compressor`: aplique `Voz` (`Limiar` −20 dB, `Razão` 3,5:1, `Ataque` 5 ms, `Soltura` 80 ms, `Joelho` 6 dB, `Ganho` +4 dB, `Detector` `RMS`, `Passa-alta` 80 Hz). Arraste o `Limiar` até o medidor de redução marcar de −3 a −6 dB nas frases fortes.
5. No mixer, na tira da voz, toque em `Envio` para criar o barramento de retorno. No barramento (abra o rack dele), adicione `Reverb` e aplique `Placa` (`Pré-atraso` 10 ms, `Tamanho` 55%, `Decaimento` 1,8 s, `Abafar` 12 kHz, `Cortar graves` 200 Hz). Depois do preset, ponha `Mistura` em **100%** e `Pré-atraso` em 20 ms.
6. Ajuste o nível do envio da voz entre −12 e −6 dB até a ambiência aparecer nas pausas sem empastar as frases.

### Variações

- Voz falada ou podcast: `Compressor` `Razão` 3:1 e `Soltura` 150 ms; sem reverb, ou `Quarto` (`Mistura` 100% no retorno, envio em −18 dB).
- Voz rápida (andamento alto): `Decaimento` 1,2 s e `Pré-atraso` 10 ms na `Placa`.
- Segundo retorno com `Delay` `1/8 pontilhado` (`Mistura` 100%, `Ducking` 30%), envio em −18 dB, para a voz ecoar só nas pausas.

### Por que funciona

- **Gate antes de tudo:** o compressor sobe o volume dos trechos fracos, chiado incluso; se o gate vem depois, ele já encontra o ruído amplificado.
- **EQ antes do compressor:** cortar os graves (`Passa-alta`) e a "lama" antes evita que o compressor reaja ao que você ia tirar de qualquer modo. O realce de presença (+3 dB em 3 kHz) também é comprimido, e a voz fica estável.
- **Reverb no retorno com `Mistura` 100%:** o compressor e o EQ atuam só na voz seca; a reverb entra por um caminho separado, com o nível controlado pelo envio, e não é comprimida junto.
- **`Pré-atraso`:** os 20 ms deixam o começo de cada sílaba passar limpo antes da ambiência, preservando a dicção.

### Se der errado

- **O gate corta o fim das palavras:** aumente a `Retenção` para 80 ms ou a `Soltura` para 300 ms.
- **O compressor "respira" (o chiado sobe nas pausas):** o gate está aberto demais; suba o `Limiar` do gate ou aumente o `Alcance` para −40 dB.
- **A voz fica sibilante depois do EQ:** reduza o ganho da banda 5 para +1,5 dB ou baixe a `Prateleira aguda` para +1 dB.
- **A reverb suja os graves:** suba `Cortar graves` para 250 Hz.

---

## Receita 2: bateria com compressor paralelo em barramento

> A bateria ganha peso e sustentação sem perder os transientes, em cerca de 10 minutos.

### Ingredientes

- Um barramento de retorno (envio pós-fader, 0 dB): [06 Mixer](../manual/06-mixer.md)
- `Compressor` (preset `Paralelo pesado`, com `Mistura` 100%): [Compressor](../manual/06d-efeitos-referencia.md#2-compressor)
- `EQ` (preset `Brilho`, opcional): [EQ](../manual/06d-efeitos-referencia.md#1-eq-8-bandas)
- Faixa(s) de bateria: [04b Bateria](../manual/04b-bateria.md)

### Passo a passo

1. Na tira da faixa `Bateria` (ou de cada faixa de bateria, se estiverem separadas), toque em `Envio` para criar o barramento de retorno. Abra o menu do envio (botão direito ou toque longo) e escolha `Nível em 0 dB`; mantenha `Pós-fader`.
2. Abra o rack do barramento (tecla `F` com ele selecionado) e adicione `Compressor`. Aplique o preset `Paralelo pesado`: `Limiar` −35 dB, `Razão` 10:1, `Ataque` 1 ms, `Soltura` 100 ms, `Joelho` 0 dB, `Ganho` +12 dB, `Detector` `Pico`.
3. Mude a `Mistura` do compressor de 40% para **100%**: quem faz a mistura com o seco agora é o envio, e o barramento carrega só a cópia esmagada.
4. Toque a bateria: o medidor deve mostrar de −12 a −20 dB de redução nos golpes fortes. Se a redução for menor que 8 dB, abaixe o `Limiar` para −40 dB.
5. Abaixe o fader do barramento até cerca de −10 dB e suba aos poucos até a bateria ganhar peso e o "ar" entre as batidas; pare antes de o pulso perder a dinâmica.
6. Opcional: depois do compressor, `EQ` com o preset `Brilho` (o principal é a banda 7, `Prateleira aguda` 9 kHz, +4 dB; ele também põe −1 dB em 400 Hz e +1,5 dB em 4,5 kHz) para os pratos e o ataque da caixa aparecerem na cópia esmagada.

### Variações

- **Sem barramento:** um `Compressor` como insert da própria faixa com o preset `Paralelo pesado` como vem (`Mistura` 40%) faz a mesma compressão paralela dentro do efeito. Perde a possibilidade de agrupar várias faixas e de tratar só a cópia com EQ.
- **Cola no conjunto:** um segundo `Compressor` no insert da bateria, preset `Bateria cola` (`Limiar` −16 dB, `Razão` 2:1, `Ataque` 30 ms), antes do envio.
- **Cópia mais suja:** `Distorção` `Fita` (`Drive` 6 dB, `Mistura` 100%) no barramento, depois do compressor. Ela atrasa a cópia em 0,67 ms, mas o motor alinha o seco com essa latência (compensação de latência, [06e](../manual/06e-compensacao-de-latencia.md)); ver "Se der errado".

### Por que funciona

- O compressor com ataque de 1 ms e razão 10:1 esmaga o transiente e traz os sons baixos (o decaimento dos tons, o sustento dos pratos, o "ar" da sala) para o mesmo nível dos golpes. Somado ao original, que continua com o transiente intacto, você ganha volume aparente e sustentação sem "amassar" o ataque.
- O envio **pós-fader** faz o barramento acompanhar o fader da faixa: subir ou descer a bateria mantém a proporção entre o seco e o esmagado.
- `Detector` `Pico` acompanha cada transiente; `Joelho` 0 dB deixa a compressão dura e uniforme, adequada para uma cópia que ninguém vai ouvir sozinha.

### Se der errado

- **A bateria perde o punch:** o barramento está alto demais; baixe o fader em 3 dB.
- **O barramento "bombeia" de modo audível:** aumente a `Soltura` para 150 ms.
- **Efeito de pente ou som oco ao combinar seco e cópia:** o `Compressor` não tem latência, então não é a causa. Se você pôs `Distorção` ou `Limitador` no barramento, eles atrasam a cópia (0,67 ms e o `Lookahead`), mas o motor atrasa o seco e as outras entradas do barramento do mesmo tanto, então isso não deveria fazer pente (ver [06e](../manual/06e-compensacao-de-latencia.md) e [latência](../manual/06d-efeitos-referencia.md#latência-e-custo-de-cada-efeito); sem escuta no navegador) `(testado só por testes automáticos)`. Se mesmo assim soar oco, confira que o envio é mesmo o caminho do som e não duas cópias da faixa, tire o efeito de latência do barramento (`Lookahead` 0 no `Limitador`) para comparar, ou use o `Mistura` do próprio efeito no lugar do envio. Bypass do efeito não muda o alinhamento.
- **Vai gravar uma voz ou um instrumento por cima desta mixagem:** a latência de `Distorção` e `Limitador` (também a do `Master` e o limitador de segurança) entra sozinha na compensação da gravação, no áudio e nas notas MIDI, e o clique do metrônomo soa junto das faixas ([06e](../manual/06e-compensacao-de-latencia.md#gravar-por-cima-de-um-projeto-com-efeitos-de-latência)). Não some nada à mão na `Compensação de latência`; se sobrar desvio no áudio, ajuste-a `(testado só por testes automáticos)`.

---

## Receita 3: sidechain pumping com o bumbo

> Pad ou baixo "respirando" no ritmo do bumbo, em cerca de 5 minutos.

### Ingredientes

- Uma faixa **só de bumbo**: [04b Bateria](../manual/04b-bateria.md) (um clipe só com a nota do `Bumbo`) ou um áudio de bumbo.
- `Compressor` com `Sidechain` na faixa do bumbo: [Compressor](../manual/06d-efeitos-referencia.md#2-compressor) e [O sidechain](../manual/06d-efeitos-referencia.md#o-sidechain-o-que-ele-exige)

### Passo a passo

1. Confirme que o bumbo está numa faixa **própria**. A chave é a saída da faixa inteira: se hi-hat e caixa estão na mesma faixa, eles também disparam o efeito.
2. Selecione a faixa do pad (ou do baixo) e adicione um `Compressor` (sem preset).
3. No grupo `CHAVE`, abra o seletor `Sidechain` e escolha a faixa do bumbo pelo nome.
4. Ajuste: `Detector` `Pico`, `Passa-alta` 20 Hz (o grave do bumbo precisa chegar ao detector), `Razão` 8:1, `Ataque` 1 ms, `Joelho` 0 dB, `Ganho` 0, `Mistura` 100%.
5. `Soltura`: 40% de uma batida, `0,4 × 60 ÷ BPM` segundos (100 BPM = 240 ms; 124 BPM = 194 ms; 140 BPM = 171 ms). O ganho volta antes do próximo bumbo.
6. Toque o projeto e arraste o `Limiar` na horizontal até o medidor mostrar de −6 a −12 dB de redução em cada bumbo, de volta a 0 entre eles. Um ponto de partida é −30 dB; o valor certo depende do volume da faixa do bumbo.

### Variações

- **Um compressor no barramento:** ponha o `Compressor` num barramento que junta pad, baixo e teclas (cada uma com a saída direcionada ao barramento, no seletor de saída da tira do mixer) para todos bombearem juntos; o `Sidechain` continua na faixa do bumbo.
- **Bombeio mais discreto:** `Razão` 3:1, `Joelho` 6 dB, `Soltura` 120 ms, redução de 3 a 4 dB.
- **Portão rítmico em vez de bombeio:** `Gate` no pad com `Sidechain` na faixa do hi-hat, `Alcance` −80 dB, `Retenção` 50 ms: o pad soa só junto dos hats.

### Por que funciona

- O compressor mede **outro** sinal (o bumbo) mas age sobre o áudio da faixa dele: a cada bumbo o pad abaixa e volta durante a soltura, o que dá o movimento do bombeio e abre espaço para o grave do bumbo.
- `Detector` `Pico` responde na hora ao transiente do bumbo (o `RMS` faz uma média de 10 ms e reage mais devagar).
- `Ataque` 1 ms para o pad abaixar antes do pico do bumbo terminar; `Soltura` curta o bastante para ele voltar até o bumbo seguinte, que é o que cria o "vaivém".
- Pelo código, a chave é lida **depois dos efeitos da faixa do bumbo e antes do fader dela**; ou seja, baixar o fader do bumbo não deveria mudar o bombeio `(não confirmado ouvindo)`.

### Se der errado

- **Não há redução (medidor parado em 0):** confira se o `Sidechain` não está em `Própria entrada`. Depois, se o bumbo realmente toca no trecho, baixe o `Limiar`.
- **O medidor só reage quando toda a bateria toca:** o bumbo divide a faixa com as outras peças; separe-o.
- **O pad fica constantemente abaixado:** a `Soltura` é longa demais para o andamento; encurte-a.
- **O medidor é de outro efeito:** só um efeito de dinâmica é medido por vez; toque no gráfico do compressor.

---

## Receita 4: delay em ping-pong sincronizado ao andamento

> Ecos que saltam entre esquerda e direita, presos ao andamento, em cerca de 5 minutos.

### Ingredientes

- `Delay` (`Tempo` `Andamento`, `Ping-pong` `Sim`): [Delay](../manual/06d-efeitos-referencia.md#7-delay)
- Tabela de figuras (`NOTE_BEATS`) em [Delay](../manual/06d-efeitos-referencia.md#7-delay)
- Opcional: retorno num barramento, [06 Mixer](../manual/06-mixer.md)

### Passo a passo

1. Ponha um `Delay` na faixa (ou num retorno) e aplique o preset `Ping-pong 1/4`: `Mistura` 30%, `Tempo` `Andamento`, `Nota` `1/4`, `Realimentação` 45%, `Ping-pong` `Sim`, `Passa-alta` 120 Hz, `Passa-baixa` 7 kHz, `Modulação` 10%, `Ducking` 20%.
2. Confira o tempo que o eco vai ter: `atraso = batidas da figura × 60 ÷ BPM`.

   | BPM | `1/4` (1 batida) | `1/8D` (0,75) | `1/8` (0,5) | `1/16` (0,25) |
   |---|---|---|---|---|
   | 90 | 667 ms | 500 ms | 333 ms | 167 ms |
   | 100 | 600 ms | 450 ms | 300 ms | 150 ms |
   | 120 | 500 ms | 375 ms | 250 ms | 125 ms |
   | 128 | 469 ms | 352 ms | 234 ms | 117 ms |
   | 140 | 429 ms | 321 ms | 214 ms | 107 ms |

3. Para um groove mais "de fora do tempo", troque `Nota` para `1/8D` (o eco cai três semicolcheias depois, uma colcheia pontuada: o eco pontilhado clássico de guitarra e voz).
4. Se usar como retorno num barramento, suba `Mistura` para **100%** e controle o nível pelo envio (−12 a −6 dB).
5. Toque um som curto e bem separado (uma nota de sintetizador, um pluck): o primeiro eco sai à **esquerda** (na batida da `Nota`), o segundo à **direita**, o terceiro à esquerda, e assim por diante.
6. Mude o andamento do projeto: o `Delay` acompanha, sem precisar mexer em nada.

### Variações

- **Ecos que só aparecem nas pausas da voz:** `Ducking` 40%.
- **Eco de fita:** `Passa-baixa` 3 kHz, `Saturação` 30%, `Modulação` 30% (parecido com o preset `Dub`).
- **Sem sincronia:** `Tempo` `Livre` e `Tempo livre` em ms fixos (por exemplo 300 ms).
- **Mais repetições:** `Realimentação` 65%; passe de 90% só com `Passa-baixa` baixo, para os ecos escurecerem em vez de acumular.

### Por que funciona

- O atraso em segundos vem do andamento (`batidas × 60 ÷ BPM`), então o eco cai exatamente na grade; por isso funciona em qualquer andamento e acompanha mudanças.
- No ping-pong a entrada é somada em mono e entra só na linha da esquerda; cada eco alimenta o outro lado. Como o eco atravessa o estéreo a cada repetição, o som passeia em zigue-zague.
- `Passa-alta` e `Passa-baixa` estão **na realimentação**: cada repetição perde graves e agudos, e os ecos sentam atrás da fonte em vez de competir com ela.

### Se der errado

- **O eco não sincroniza:** confira se `Tempo` está em `Andamento` (em `Livre` o controle é o `Tempo livre`).
- **Não saem ecos alternados:** `Ping-pong` está em `Não`. Uma fonte panorâmica extrema perde o pan: o ping-pong soma a entrada em mono.
- **O `Desvio E/D` não faz nada:** ele fica apagado com o ping-pong ligado.
- **Os ecos cobrem a voz:** `Ducking` 40% e `Mistura` 20%.

---

## Receita 5: pad largo com chorus e reverb

> Um pad de sintetizador que enche o estéreo sem embolar os graves, em cerca de 10 minutos.

### Ingredientes

- Faixa de sintetizador com o som de pad: [04a Sintetizador](../manual/04a-sintetizador.md) (o `Uníssono` e o `Espalhar` do próprio instrumento já abrem o som)
- `Chorus` (preset `Ensemble`): [Chorus](../manual/06d-efeitos-referencia.md#8-chorus-chorus-e-flanger)
- `EQ` (preset `Corte de graves`): [EQ](../manual/06d-efeitos-referencia.md#1-eq-8-bandas)
- `Reverb` (preset `Salão`): [Reverb](../manual/06d-efeitos-referencia.md#6-reverb-fdn)
- `Utilitário` (opcional, para conferir mono): [Utilitário](../manual/06d-efeitos-referencia.md#5-utilitário)

### Passo a passo

1. Na faixa do pad, abra o rack e adicione `Chorus`. Aplique `Ensemble` (`Mistura` 50%, `Taxa` 1,1 Hz, `Profundidade` 50%, `Atraso` 18 ms, `Vozes` 4, `Realimentação` 0%, `Largura` 100%) e baixe a `Mistura` para 40%.
2. Adicione `EQ`, aplique `Corte de graves` e suba a `Frequência` da banda 1 para 150 Hz (24 dB/oit): o baixo e o bumbo têm a região abaixo dela.
3. Adicione `Reverb` e aplique `Salão` (`Mistura` 28%, `Pré-atraso` 30 ms, `Tamanho` 80%, `Decaimento` 2,8 s, `Abafar` 6 kHz, `Cortar graves` 100 Hz). Suba `Cortar graves` para 200 Hz para o pad não afogar o baixo.
4. Se preferir a reverb num retorno (mais limpo): tire `Mistura` do insert, faça o retorno com `Salão` em `Mistura` 100% e mande o pad pelo envio em −9 dB.
5. Confira a compatibilidade mono: adicione um `Utilitário` como último efeito com `Mono` `Sim`, escute e desligue (bypass) ou remova depois. O pad não pode desaparecer nem mudar de timbre.
6. Automatize (opcional) a `Mistura` do `Chorus` de 0 a 40% na entrada do pad: [07 Automação](../manual/07-automacao.md).

### Variações

- **Mais largo ainda:** `Utilitário` com `Largura` 130% no fim da cadeia (confira o mono).
- **Pad em movimento:** um `Phaser` `Profundo (12 estágios)` entre o `Chorus` e o `EQ`; `Mistura` 30%.
- **Pad congelado:** troque `Salão` por `Shimmer congelado` (`Congelar` `Sim`) e toque um acorde: a cauda sustenta.

### Por que funciona

- O `Chorus` engrossa e alarga o som **antes** da reverb: a reverb então cria o espaço em torno de um som já largo. Na ordem inversa, o chorus modularia a cauda da reverb (soa outro efeito, mais "flutuante").
- O corte de graves do `EQ` em 150 Hz e o `Cortar graves` da reverb tiram do pad a energia que compete com o baixo e o bumbo; é o que deixa a mistura aberta.
- `Vozes` 4 e `Largura` 100% espalham as vozes no estéreo com fases distribuídas; a potência é normalizada, então o volume se mantém.

### Se der errado

- **O pad some em mono:** a `Largura` do `Chorus` e do `Utilitário` está alta demais; baixe `Largura` para 60% ou tire o `Utilitário` acima de 100%.
- **Som "enjoado" (vibrato demais):** baixe `Profundidade` para 30%.
- **Graves turvos:** suba a `Frequência` da banda 1 para 200 Hz.
- **A reverb come o pad:** `Mistura` do insert em 20% ou use o retorno.

---

## Receita 6: distorção de baixo com filtro e EQ

> Um baixo com dentes e mordida que mantém o grave limpo, em cerca de 15 minutos.

### Ingredientes

- `EQ` (duas instâncias: antes e depois): [EQ](../manual/06d-efeitos-referencia.md#1-eq-8-bandas)
- `Compressor` (preset `Baixo`): [Compressor](../manual/06d-efeitos-referencia.md#2-compressor)
- `Distorção` (preset `Válvula quente`): [Distorção](../manual/06d-efeitos-referencia.md#11-distorção-sobreamostragem)
- `Filtro` (envelope): [Filtro](../manual/06d-efeitos-referencia.md#12-filtro)

### Passo a passo

A cadeia, nesta ordem: `EQ` → `Compressor` → `Distorção` → `Filtro` → `EQ`.

1. `EQ` (o primeiro): aplique `Corte de graves` e ponha a `Frequência` da banda 1 em **40 Hz** (24 dB/oit). O subgrave não deve empurrar a curva de distorção.
2. `Compressor`: aplique `Baixo` (`Limiar` −22 dB, `Razão` 5:1, `Ataque` 3 ms, `Soltura` 120 ms, `Joelho` 3 dB, `Ganho` +5 dB). O nível constante deixa a distorção uniforme entre as notas.
3. `Distorção`: aplique `Válvula quente` (`Drive` 14 dB, `Tipo` `Válvula`, `Tom` 7 kHz, `Mistura` 100%, `Saída` −6 dB, `Sobreamostragem` 2×). Suba o `Drive` para 18 dB e baixe a `Mistura` para **55%**: o original limpo (com todo o grave) soma ao distorcido; ajuste `Tom` para 5 kHz.
4. `Filtro`: `Tipo` `Passa-baixa 24`, `Corte` 600 Hz, `Ressonância` 35%, `Profundidade` 0, `Envelope` **+2,5 oit**, `Mistura` 100%. Cada nota "abre" o filtro no ataque e ele fecha na soltura (o seguidor tem soltura de 100 ms): mordida no ataque sem chiado sustentado. A abertura segue a raiz do nível: com o sinal do filtro em 0 dBFS o corte iria de 600 Hz a cerca de 3,4 kHz; em −12 dBFS, a cerca de 1,4 kHz. Ajuste `Envelope` (até +6 oit) ou o nível de entrada do filtro para escolher o quanto abre.
5. `EQ` (o segundo): banda 3 `Sino` 250 Hz, −3 dB, Q 1,2 (tira a lama); banda 4 `Sino` 800 Hz, +2 dB, Q 1 (a mordida); banda 8 `Passa-baixa` a 8 kHz, 24 dB/oit (liga a banda: o padrão dela está desligada).
6. Nivele com o `Saída` da `Distorção` (ou o `Saída` do segundo `EQ`) até o baixo ficar no mesmo volume de antes de ligar a cadeia (use o bypass de cada cartão para comparar).

### Variações

- **Baixo em mono:** um `Utilitário` com `Mono` `Sim` no fim da cadeia.
- **Wobble em vez de envelope:** no `Filtro`, `Envelope` 0, `Profundidade` 3,5 oit, `Tempo` `Andamento`, `Nota` `1/8` (o preset `Wobble 1/8`).
- **Mais sujo:** `Tipo` `Dura` com `Drive` 24 dB e `Mistura` 40%.
- **Baixo duplicado (limpo numa faixa, sujo na outra):** a `Distorção` atrasa o som em cerca de 0,67 ms; para não fazer filtro-pente na soma, use o `Mistura` da `Distorção` em vez de duas faixas.

### Por que funciona

- **EQ antes da distorção:** o que entra na curva define os harmônicos. Um subgrave forte "come" o espaço da curva e gera intermodulação. Cortar em 40 Hz antes mantém o grave audível e tira o que só atrapalha.
- **Compressor antes da distorção:** quanto mais uniforme o nível de entrada, mais uniforme o caráter da distorção entre notas fortes e fracas.
- **`Mistura` 55%:** o sinal original preserva a fundamental limpa e a distorção acrescenta os harmônicos; é assim que o baixo continua "grande" no sistema de som.
- **`Válvula`:** a curva assimétrica gera harmônicos pares e ímpares (mais calor que a `Suave`) e a compensação de volume mantém o nível ao girar o `Drive`.
- **Filtro com envelope:** o seguidor faz o corte acompanhar a força da nota, um "wah" automático, sem LFO.
- **EQ depois:** tira o que a distorção criou de indesejado (lama em 250 Hz, chiado acima de 8 kHz) e dá a mordida em 800 Hz.

### Se der errado

- **O grave sumiu:** aumente a `Mistura` da `Distorção` (limpo) ou diminua o `Drive`; confira se o primeiro `EQ` não está em 80 Hz ou mais.
- **Chiado agudo:** `Tom` mais baixo (4 kHz) e banda 8 do segundo `EQ` em 6 kHz.
- **O filtro não se mexe:** `Envelope` está em 0 ou o `Corte` já está alto demais para o efeito se notar; confira o `Corte` (600 Hz) e a `Ressonância`.
- **Volume muito diferente com a cadeia ligada:** `Saída` da `Distorção` (−24 a +12 dB) para nivelar; a compensação automática de volume é calibrada para −12 dBFS de pico, e abaixo disso a distorção sobe o volume.
- **Faltou o EQ:** dois `EQ` são possíveis na mesma cadeia (aparecem numerados nos alvos de automação).

---

## Receita 7: master suave com multibanda

> Uma cola leve na mistura inteira, banda por banda, com o `Limitador` no fim: de 5 a 10 minutos.

### Ingredientes

- `Multibanda` (preset `Master suave`): [Multibanda](../manual/06d-efeitos-referencia.md#13-multibanda)
- `Limitador` (preset `Master −1 dB`): [Limitador](../manual/06d-efeitos-referencia.md#4-limitador)
- `EQ` (opcional, antes de tudo): [EQ](../manual/06d-efeitos-referencia.md#1-eq-8-bandas)
- Medir e exportar: [Loudness e master](loudness-e-master.md)

### Passo a passo

1. Abra o rack do `Master` (tecla `F` e `Master` no seletor de faixa, ou o chip `FX` do cabeçalho `Master`) e adicione, nesta ordem: `EQ` (só se precisar), `Multibanda` e `Limitador`. Ele entra no lugar do `Compressor` que o guia de loudness sugere para o master.
2. `Multibanda`: aplique `Master suave`. Os valores de partida: cruzamentos em 100 Hz e 5 kHz; `BAIXA` com `Limiar` −14 dB, `Razão` 1,8:1, `Ataque` 40 ms, `Soltura` 400 ms; `MÉDIA` com −12 dB, 1,4:1, 30 ms, 250 ms; `AGUDA` com −16 dB, 1,5:1, 15 ms, 200 ms; `Joelho` de 12 dB nas três; `Saída` 0 dB.
3. Toque o gráfico do `Multibanda` (para ele ser o efeito medido) e toque a mistura no trecho mais forte. Olhe o número embaixo de cada banda (`−1.4`, por exemplo): o alvo é de **1 a 2 dB** de redução nos picos. Sem redução, baixe o `Limiar` da banda em passos de 2 dB (−14 para −16, −18...); acima de 3 dB, suba de novo.
4. Se uma banda parecer pesada, ligue o `Solo` nela, ouça, ajuste e **desligue o `Solo`**: ele muda o som de verdade, também na exportação.
5. `Limitador`: aplique `Master −1 dB` (`Ganho` +3 dB, `Teto` −1 dB) e siga o [passo 3 do guia de loudness](loudness-e-master.md#3-ganhar-volume-com-o-limitador-no-master-não-com-o-fader) para o volume final.
6. Compare com o bypass do `Multibanda` (botão de energia do cartão) no mesmo trecho e nivele com o `Saída` dele: a versão comprimida não deve soar mais alta só por isso.

### Variações

- **Mix de grupo em vez do master:** o preset `Mix de bus` (cruzamentos 150 Hz e 3,5 kHz, `Saída` +1 dB) numa pasta ou barramento, com razões de 1,6:1 a 2:1.
- **Graves soltos na mistura:** `Controle de graves` (180 Hz e 3 kHz; `BAIXA` −26 dB, 5:1) no lugar de `Master suave`, e depois suba o `Limiar` da `BAIXA` até a redução ficar em 2 a 3 dB.
- **Só o topo controlado:** ponha `Bypass` `Sim` nas bandas `BAIXA` e `MÉDIA`; a `AGUDA` continua comprimindo sozinha.

### Por que funciona

- Um compressor de banda inteira abaixa tudo quando o bumbo passa do limiar; com três bandas, um grave forte só abaixa os graves e o topo continua no lugar. Por isso as razões podem ser baixas (1,4:1 a 1,8:1) e ainda controlar o equilíbrio.
- Os ataques de 15 a 40 ms deixam os transientes passarem, e as solturas de 200 a 400 ms evitam o "bombeio" audível; o `Joelho` de 12 dB faz a compressão entrar sem degrau. O caráter vem dos valores, sem escuta `(não confirmado ao ouvido)`.
- Sem compressão, as três bandas somam de volta ao original (resposta plana), então o efeito só age onde há redução ([06d, Multibanda](../manual/06d-efeitos-referencia.md#13-multibanda)).
- Latência 0: não desalinha nada ([06e](../manual/06e-compensacao-de-latencia.md)).

### Se der errado

- **O medidor não mostra nada:** só um efeito é medido por vez (o `Limitador` do master pode ser o medido); toque no gráfico do `Multibanda`.
- **Os graves "respiram":** aumente a `Soltura` da `BAIXA` para 600 ms ou baixe a `Razão` dela para 1,5:1.
- **O topo ficou opaco:** suba o `Limiar` da `AGUDA` para −12 dB ou ponha a banda em `Bypass`.
- **O som mudou de volume e de timbre de repente:** um `Solo` ficou ligado numa banda.

---

## Receita 8: voz com de-esser antes do compressor

> Uma voz que segura o "s" sem perder o brilho, em cerca de 10 minutos. Continua a [receita 1](#receita-1-cadeia-vocal-gate-eq-compressor-reverb).

### Ingredientes

- A cadeia `Gate` → `EQ` da receita 1 (o `EQ` com `Voz presente` realça 3 kHz e 10 kHz, e é isso que deixa o "s" mais cortante)
- `De-esser` (preset `Voz suave`, ou `Voz feminina` / `Voz masculina`): [De-esser](../manual/06d-efeitos-referencia.md#14-de-esser)
- `Compressor` (preset `Voz`): [Compressor](../manual/06d-efeitos-referencia.md#2-compressor)

### Passo a passo

1. Na faixa da voz, deixe a ordem `Gate`, `EQ`, `De-esser`, `Compressor`: o `De-esser` entra **depois do `EQ`** (que realça o brilho) e **antes do `Compressor`**.
2. `De-esser`: aplique `Voz suave` (`Frequência` 6,5 kHz, `Q` 1,5, `Limiar` −32 dB, `Razão` 4:1, `Ataque` 1 ms, `Soltura` 50 ms, `Modo` `Banda dividida`). Para voz aguda, `Voz feminina` (`Frequência` 8 kHz, `Q` 1,8, `Limiar` −30 dB, `Razão` 5:1, `Soltura` 40 ms); para grave, `Voz masculina` (5,5 kHz, `Q` 1,3, −30 dB, 5:1, `Soltura` 60 ms).
3. Ache a frequência do "s": ponha `Ouvir banda` em `Sim`, toque uma frase e arraste no gráfico na horizontal (ou gire `Frequência`) até ouvir só o chiado dos "s" e dos "x"; então volte `Ouvir banda` para `Não`.
4. Toque o gráfico do `De-esser` para ele ser o efeito medido e abaixe o `Limiar` até o medidor marcar de **3 a 6 dB** nos "s" e ficar em `0.0` nas vogais.
5. `Compressor`: aplique `Voz` (`Limiar` −20 dB, `Razão` 3,5:1, `Ataque` 5 ms, `Soltura` 80 ms, `Ganho` +4 dB) e ajuste como no passo 4 da receita 1.
6. Alterne o bypass do `De-esser` no mesmo trecho: só o "s" deve mudar, o resto da voz fica igual (modo dividido).

### Variações

- **Sibilância misturada com respiração e chiado:** `Modo` `Banda larga` (preset `Banda larga`: 7 kHz, `Q` 1, `Limiar` −28 dB, `Razão` 3:1, `Ataque` 0,5 ms, `Soltura` 80 ms). O sinal inteiro abaixa quando o "s" estoura, então o resto da voz também.
- **"S" muito estreito:** `Q` 2,5 a 3 e `Frequência` no centro do chiado.
- **Tirar só o excesso:** `Razão` 3:1 no lugar de 4:1, e suba o `Limiar` até o medidor marcar 2 a 3 dB nos "s" mais fortes.

### Por que funciona

- O `Compressor` reage aos picos mais fortes; um "s" alto os dispara, e o `Ganho` de +4 dB do preset o traz para a frente. Tirando o "s" **antes**, o compressor não trabalha por causa dele e a compensação não realça a sibilância.
- Depois do `EQ` porque o realce de presença e de ar é justamente o que aumenta o "s": o `De-esser` corrige o que o `EQ` acentuou.
- No modo `Banda dividida` só a banda de detecção é comprimida, o corpo da voz passa intacto; sem redução, a saída é igual à entrada ([06d, De-esser](../manual/06d-efeitos-referencia.md#14-de-esser)).
- `Ataque` de 1 ms para pegar o início de cada "s"; `Soltura` de 40 a 60 ms para o ganho voltar antes da vogal seguinte.

### Se der errado

- **A voz fica com ceceio ("sem s"):** suba o `Limiar` para −26 dB ou baixe a `Razão` para 3:1.
- **O "s" continua saltando:** a `Frequência` está fora do chiado (use `Ouvir banda` de novo) ou o `Q` está estreito demais; baixe o `Q` para 1,0.
- **O medidor do compressor sumiu:** o medidor mostra um efeito por vez; toque no gráfico do efeito que quer medir.
- **Ficou só a banda chiando, sem a voz:** `Ouvir banda` está em `Sim`.

---

## Receita 9: graves em mono com imagem estéreo

> A mistura (ou o pad) mais aberta no topo e com o subgrave firme no centro, conferindo a fase: de 5 a 10 minutos.

### Ingredientes

- `Imagem estéreo` (presets `Graves em mono`, `Mix de bus` e `Largo`): [Imagem estéreo](../manual/06d-efeitos-referencia.md#15-imagem-estéreo)
- `Utilitário` (opcional, para conferir o mono): [Utilitário](../manual/06d-efeitos-referencia.md#5-utilitário)

### Passo a passo

1. No rack do `Master` (ou de um barramento/pasta de grupo), adicione `Imagem estéreo` **antes** do `Limitador`.
2. Aplique `Graves em mono`: cruzamentos em 150 Hz e 4 kHz, larguras `Baixa` 0%, `Média` 100%, `Aguda` 100%, `Mono nos graves` `Sim` abaixo de 150 Hz. Só o grave muda; o resto sai como entrou.
3. Toque o `Imagem estéreo` para ele ser o efeito medido e olhe a trilha `FASE`: com música normal ela fica para a direita (positiva). Encostar na esquerda, na cor de alerta, é fase oposta: a mistura perde corpo em mono.
4. Para abrir o topo, suba as larguras: `Média` 110% e `Aguda` 125% (é o `Mix de bus`, que também baixa a `Baixa` para 80% com `Mono nos graves` abaixo de 120 Hz). Vá de 5 em 5 pontos e olhe a `FASE`.
5. Confira em mono: `Utilitário` com `Mono` `Sim` no fim da cadeia, escute e depois tire (como no passo 5 da [receita 5](#receita-5-pad-largo-com-chorus-e-reverb)). O nível e o timbre não devem mudar muito.

### Variações

- **Só o pad:** `Largo` numa faixa de pad (larguras 60%, 140% e 170%, cruzamentos 250 Hz e 3 kHz, `Mono nos graves` abaixo de 100 Hz); confira em mono.
- **Fechar o estéreo de um baixo ou de um grave largo demais:** `Quase mono` (larguras 0%, 40% e 60%).
- **Corrigir um lado forte:** `Balanço` (−1 a +1) só abaixa o canal oposto; use valores pequenos: −0,1 deixa o canal direito com 90% da amplitude (cerca de −0,9 dB).

### Por que funciona

- A soma esquerda + direita, o que uma caixa mono ouve, não muda com nenhuma largura (com o `Balanço` em 0): só o lado é mexido, então abrir o estéreo não tira o centro ([06d, Imagem estéreo](../manual/06d-efeitos-referencia.md#15-imagem-estéreo)).
- Graves com diferença entre os lados enfraquecem ou somem em mono; tirar o lado abaixo de 120 a 150 Hz deixa o subgrave no centro. O caráter vem dos valores, sem escuta `(não confirmado ao ouvido)`.
- O medidor `FASE` é a correlação de fase da saída: +1 mono, 0 sem relação, −1 fases opostas.

### Se der errado

- **A `FASE` vai a valores negativos:** baixe `Média` e `Aguda` para 100% ou menos, ou confira se o material já vem com um lado invertido (o `Utilitário` tem `Inverter esq.`).
- **As larguras não mudam nada:** a fonte é mono (esquerda igual à direita); não há lado para abrir.
- **A trilha `FASE` está vazia:** o medidor é de um efeito por vez; toque no gráfico da `Imagem estéreo`.
- **`Abaixo de` está apagado:** `Mono nos graves` está em `Não`.

## Ver também

- [06c Painel de efeitos](../manual/06c-painel-de-efeitos.md) e [06d Referência dos efeitos](../manual/06d-efeitos-referencia.md).
- [06 Mixer](../manual/06-mixer.md): envios, barramentos e a ordem do sinal.
- [07 Automação](../manual/07-automacao.md): `Corte`, `Mistura` e `Limiar` mudando ao longo da música.
