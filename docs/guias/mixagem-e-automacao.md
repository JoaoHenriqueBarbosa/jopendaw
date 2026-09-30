# Mixagem e automação

> Montar um mix do zero (níveis, pan, envios, master), com um retorno de reverb compartilhado, uma subida de filtro e um fade de volume, em cerca de 30 a 40 minutos para uma música de 8 a 10 faixas.

## Ingredientes

| Recurso | Para quê aqui | Capítulo |
|---|---|---|
| Fader, pan, `M` e `S` de cada canal | Níveis e posição de cada faixa | [06 Mixer](../manual/06-mixer.md) |
| Envios e barramentos | Um reverb (e um delay) compartilhados por várias faixas | [06 Mixer](../manual/06-mixer.md) |
| Medidores | Ver o pico de cada faixa e do master, e a folga que sobra | [06b Analisador e medidores](../manual/06b-analisador-e-medidores.md) |
| Efeitos `Reverb`, `Compressor`, `Filtro`, `EQ`, `Limitador` | Espaço, ducking, varredura e acabamento | [06c Painel de efeitos](../manual/06c-painel-de-efeitos.md), [06d Referência dos efeitos](../manual/06d-efeitos-referencia.md) |
| Automação (botão `A`, raias, curva) | Fade e subida de filtro | [07 Automação](../manual/07-automacao.md) |
| Loop (`L`) e grade de encaixe | Repetir o trecho enquanto se mexe | [02 Transporte](../manual/02-transporte.md) |
| Exportação | Conferir o resultado no arquivo | [08 Exportação](../manual/08-exportacao.md) |

Os números daqui são pontos de partida musicais, não regras do programa: ajuste de ouvido. Tudo o que depende do programa (escalas, faixas de valor, rótulos) vem do código.

## Passo a passo

### 1. Ajustar um mix do zero

A ordem importa: cada etapa muda a anterior um pouco, então vá do que mexe mais para o que mexe menos.

**Preparação**
1. Marque um loop de 8 compassos no trecho mais cheio da música (`L`, arrastando na régua) e deixe tocando.
2. Abra o mixer (`X`). Duplo clique em cada fader para voltar a 0 dB e no pan para voltar a `C`. Deixe o fader do `Master` em 0 dB.

**Etapa 1: níveis (só faders)**
1. Comece pela base: bumbo e baixo. Ajuste os faders até o pico de cada um ficar por volta de −12 a −10 dB no medidor (a barra ainda verde, perto de onde ela começa a amarelar em −14,4 dB).
2. Some as outras faixas uma a uma, sempre ouvindo com tudo tocando. Os faders costumam ficar entre −6 e −20 dB. Use `S` para conferir uma faixa, mas decida o nível no conjunto.
3. Termine com o pico do `Master` entre −12 e −6 dB (a barra na parte verde-amarela). Se passar disso, baixe as faixas mais altas em vez de subir o master.

**Etapa 2: pan**
1. Bumbo, baixo, caixa e voz principal ficam em `C`.
2. Pares (duas guitarras, teclados, backing vocals): um em `E30` a `E60`, o outro no espelho, `D30` a `D60`. Arraste o knob de pan na vertical; ele "gruda" no centro.
3. Refaça os níveis das faixas que você abriu no pan. O pan das faixas é de potência constante: no centro cada lado sai com −3 dB, e uma faixa aberta para um lado passa a soar mais alta naquele lado.

**Etapa 3: envios (espaço)**
1. Monte o retorno de reverb da próxima seção e mande para ele as faixas que precisam de ambiência.
2. Se quiser um delay, monte um segundo retorno do mesmo jeito (variação abaixo).

**Etapa 4: master**
1. Deixe o fader do `Master` em 0 dB. Se o pico continua alto demais, baixe o grupo das faixas mais altas.
2. Se quiser acabamento, adicione no master (`Efeito` no canal `Master`): `EQ` leve e `Compressor` suave (3 dB de redução nos picos, medidos pelo indicador do cartão). Feche com o efeito `Limitador` com `Teto` em −1,0 dB, se o arquivo vai para um serviço que recodifica.
3. Confira o medidor do `Master`. Se ele vive grudado no topo, o limitador de segurança (−0,3 dBFS, sempre ligado) está segurando o som: o som achata. Baixe as faixas até ele só encostar de vez em quando.
4. Exporte um WAV ([08](../manual/08-exportacao.md)) e ouça fora do programa.

### 2. Criar um barramento de reverb compartilhado

O resultado: um só reverb para o mix inteiro, com a quantidade de cada faixa definida pelo envio dela.

1. No mixer, num canal de faixa (por exemplo a voz), toque na linha `Envio`. Nasce `Barramento 1` (no fim da lista, selecionado) e a voz já manda para ele em −6,0 dB, pós-fader.
2. No menu da faixa `Barramento 1` na linha do tempo, escolha `Renomear` e chame de `Reverb`.
3. No canal do barramento, toque em `Efeito` e escolha `Reverb` (família `Espaço`).
4. No cartão do reverb, abra `Presets e mais` e escolha `Placa` (densa e brilhante) ou `Sala`. Depois ajuste:
   - `Mistura`: **100%**. O retorno tem que ter só o som molhado; o seco já vai direto das faixas para o master. Com o padrão (25%) você misturaria seco duplicado.
   - `Pré-atraso`: 20 a 30 ms (deixa a voz na frente).
   - `Decaimento`: 1,8 s para a `Placa`; 1,4 s para a `Sala`.
   - `Cortar graves`: 200 Hz (tira o grave da cauda e evita lama).
   - `Abafar`: 7 kHz a 12 kHz, para a cauda não brilhar mais que a fonte.
5. Fader do barramento em 0 dB por enquanto.
6. Nas outras faixas, na lista de envios de cada uma, toque no knob de `Reverb` e arraste. Comece perto de −18 dB nas faixas de fundo e −14 dB na voz; a caixa em −16 dB. Arrastar 150 px percorre o curso todo; `Shift` deixa fino; duplo clique põe 0 dB. Ao arrastar, o nome do barramento dá lugar ao nível em dB.
7. Tire o bumbo e o baixo do reverb: cauda de grave suja a mistura.
8. Confira: `M` no barramento liga e desliga o reverb inteiro para comparar; `S` numa faixa deixa soar só ela **com o reverb dela**.
9. Acerte o total com o fader do barramento e o balanço entre faixas pelos envios.

**Ducking com sidechain** (o reverb abaixa quando a voz canta):
1. No canal `Reverb`, toque em `Efeito` e adicione um `Compressor` **depois** do `Reverb` (a ordem de cima para baixo é a ordem do sinal).
2. No parâmetro `Sidechain` (grupo `Chave`), escolha o nome da faixa da voz. O menu tem `Própria entrada` e as outras faixas.
3. Valores de partida: `Limiar` −30 dB, `Razão` 4:1, `Ataque` 10 ms, `Soltura` 300 ms. O medidor de redução do cartão mostra quanto o reverb abaixa; 3 a 6 dB costuma bastar.
4. A chave é a saída da voz depois dos efeitos dela e antes do fader: mesmo com o fader da voz baixo, o ducking funciona.

## Variações

- **Reverb que não segue o fader.** No envio de uma faixa, botão direito (toque longo no celular) e `Pré-fader`: aparece `PRÉ`. O envio sai antes de volume, pan e mudo, então o reverb continua quando você baixa o fader ou aperta `M` da faixa. Útil para deixar só a cauda de uma frase.
- **Retorno de delay.** Crie um segundo barramento (`Faixa` no fim do mixer, `Barramento`), ponha `Delay` nele com `Mistura` 100%, `Tempo` `Andamento`, `Nota` `1/8D` (o preset `1/8 pontilhado` já parte disso, com `Ducking` em 30%; só falta pôr a `Mistura` em 100%) e use o parâmetro `Ducking` do próprio delay (30%) para ele abaixar enquanto o som que entra nele toca.
- **Delay alimentando o reverb.** O delay só pode mandar para um barramento que venha **depois** dele na lista. Como o barramento novo entra no fim, o delay (criado depois) fica *abaixo* do reverb e não consegue mandar para ele. Solução: no menu da faixa do delay, `Mover para cima` até ficar acima do `Reverb`; aí ele aparece na lista de envios do delay, e o delay manda parte do sinal para o reverb.
- **Grupo de bateria.** Em cada faixa da bateria, no botão de saída escolha `Novo barramento` (na primeira) e depois o mesmo barramento nas outras. Ponha um `Compressor` no barramento e acerte o fader do grupo. Os envios de reverb continuam valendo por faixa. Para mandar o *grupo* para o `Reverb`, o grupo precisa estar **antes** do reverb na lista: como o barramento novo entra no fim, use `Mover para cima` no grupo até passar o `Reverb`.
- **Subida de filtro no master.** Faça a mesma receita abaixo no efeito `Filtro` do canal `Master`: a varredura pega a mistura inteira.

### 3. Automatizar um filtro para a subida da música

O resultado: uma varredura de 8 compassos que "fecha" o som (tira o grave) até o compasso do refrão, quando tudo abre de uma vez.

1. Escolha a faixa (ou o barramento de grupo) que faz a subida. No mixer, `Efeito` e `Filtro` (família `Timbre`).
2. No cartão, `Presets e mais` e `Passa-alta de transição`. Ele parte de `Tipo` `Passa-alta 24`, `Corte` 250 Hz, `Ressonância` 25% e `Mistura` 100%.
3. Marque um loop nos 8 compassos da subida (`L`) e na barra superior ponha a grade de encaixe em `Compasso` (tooltip `Grade de encaixe (Alt ao arrastar: livre)`).
4. Na linha do tempo, toque em `A` no cabeçalho da faixa, submenu `1. Filtro`, seção `FILTRO`, item `Corte`. A raia abre com a linha tracejada em 250 Hz.
5. Clique **no começo do primeiro compasso da subida**, sobre a linha: nasce o ponto em 250 Hz. Arraste-o para baixo até `60 Hz` (leia no balão: `1.1.1 · 60 Hz`).
6. Clique no primeiro tempo do refrão (o compasso 9 da subida), acima, até uns `3.00 kHz`. Entre os dois pontos o valor sobe em linha reta **na escala logarítmica do knob**: são cerca de 5,6 oitavas em 8 compassos, ou 0,7 oitava por compasso, um avanço que soa parelho.
7. Para o filtro se abrir de uma vez no refrão, ponha a grade em `1/4`, crie um terceiro ponto uma batida depois, em 20 Hz, e arraste-o para a esquerda até a batida do ponto anterior: dois pontos na mesma batida formam um degrau. `(não confirmado no app)`
8. Se quiser que a abertura aconteça mais no fim, puxe a alça no meio do trecho para baixo (curva positiva): o balão diz `Curva +30%`.
9. Automatize também `Ressonância`: `A`, `1. Filtro`, `Ressonância`. Vá de 20% no começo a 45% no fim; ressonância alta dá o assobio da subida.
10. Toque a partir do começo da subida. Em `Efeitos` (`F`), o knob `Corte` acompanha a curva **em laranja**. Parado, o knob volta ao valor fixo.

Variação de "abrir" em vez de "fechar": `Tipo` `Passa-baixa 24`, `Corte` de 300 Hz (início) a 12 kHz (fim), sem o degrau final.

### 4. Fazer um fade de volume por automação

O resultado: a música some nos últimos 4 compassos, em uma linha só.

1. Na linha do tempo, no cabeçalho `Master` (fim da lista), toque em `A` e escolha `Volume`. A raia abre abaixo do `Master`, com a linha tracejada em 0 dB.
2. Ponha a grade em `Compasso`. Clique na linha, no início do fade (por exemplo, o compasso 33): nasce um ponto em 0 dB.
3. Clique no fim do fade (compasso 37), na base da raia: o ponto vai a `−∞ dB` (leia no cabeçalho ou no balão).
4. Toque de antes do compasso 33 até depois do 37. O fader do `Master` no mixer desce em laranja.
5. Se o começo do fade parece rápido demais, puxe a alça do meio para cima: a curva fica positiva, o volume segura por mais tempo e cai mais no fim. Se parece arrastado, puxe para baixo.
6. Deixe a raia como está para exportar: a automação entra no arquivo. Parado, o fader volta a mostrar 0 dB (o valor fixo); isso é normal e não desfaz o fade.

Um fade de volume no `Master` funciona depois dos efeitos do master (o compressor não desfaz o fade). Para fazer o fade só numa faixa ou num grupo, use a raia `Volume` dela (ou do barramento do grupo).

## Por que funciona

- **Ordem dos passos.** O nível manda no que o ouvido escuta primeiro; o pan só reorganiza; o envio adiciona espaço e, por isso, vem depois de o mix já se sustentar seco; o master fecha a soma. Trocar a ordem faz você refazer o passo anterior.
- **Folga (headroom).** Os canais podem passar de 0 dBFS por dentro sem distorcer (o motor calcula em ponto flutuante), mas a soma no master tem um limitador de segurança que age em −0,3 dBFS. Deixar o pico do master entre −12 e −6 dB evita que ele trabalhe sem você notar.
- **Retorno em vez de efeito em cada faixa.** Um reverb só no barramento economiza processamento e dá a impressão de um mesmo espaço; a dose fica por conta do envio de cada faixa. Por isso `Mistura` é 100%: o seco não passa pelo retorno.
- **Pré e pós.** Pós-fader (o padrão) é o reverb que acompanha a faixa; pré-fader é o que continua depois de você mexer no fader.
- **A raia de automação não desenha em ganho nem em Hz.** O volume e o nível dos envios seguem a curva do fader (ganho = 2 × posição³) e os parâmetros em Hz seguem a escala logarítmica do knob. Uma reta na tela vira um fade parelho (−7,5 dB, −18 dB e −36 dB em 25%, 50% e 75% do trecho) e uma varredura constante em oitavas; a mesma reta em ganho linear despencaria no fim (−2,5, −6 e −12 dB) e em Hz linear acabaria a maior parte da abertura na primeira metade.
- **Valor fixo por baixo.** A automação sobrepõe o fader ou o knob sem apagá-lo; parado, vale o valor fixo. É por isso que a raia continua no lugar ao parar.

## Se der errado

| Sintoma | Causa provável | Como resolver |
|---|---|---|
| Faixa não manda som para o reverb | Knob do envio vazio (`+`) ou em −∞ | Toque no knob para criar o envio, arraste; ou duplo clique para 0 dB |
| Mesmo com envio, nada de reverb | `M` no barramento; ou `Mistura` do reverb em 0; ou a faixa de origem está muda com envio pós-fader | Tire o mudo, suba a `Mistura` a 100%, ou troque o envio para `Pré-fader` |
| O reverb de uma faixa some enquanto outra está em `S` | Solo corta os envios das faixas que não estão em solo | É o esperado: só a faixa em solo alimenta o retorno. Para ouvir tudo, desligue o solo |
| Um barramento não aparece na lista de envios ou de saída de outro barramento | Barramento só manda para barramentos que vêm **depois** dele na lista de faixas | Ponha o destino abaixo da origem: `Mover para baixo` no destino, ou `Mover para cima` na origem (menu da faixa na linha do tempo) |
| O envio ou a saída entre barramentos sumiu depois de mover uma faixa | Mover que quebra a regra desfaz o envio (com a automação dele) ou devolve a saída ao `Master` | Recrie a ligação com a nova ordem (destino abaixo da origem) |
| A mistura ficou "lavada" | Envio alto, cauda longa, grave no reverb | Baixe os envios, `Decaimento` menor, `Cortar graves` maior, ducking |
| O medidor do master vive no topo e o som achatou | Limitador de segurança trabalhando | Baixe os faders das faixas mais altas até o pico ficar entre −12 e −6 dB |
| A automação não soa com o transporte parado | Parado vale o valor fixo | Toque para ouvir; a leitura no cabeçalho da raia mostra o valor da curva no cursor mesmo parado |
| Arrasto o fader durante o play e nada muda | A curva passa por cima do valor fixo | Arrastar muda o valor fixo (que volta ao parar). Edite os pontos ou remova a raia (`X` no cabeçalho) |
| O knob do envio não anda com a automação do envio | O knob de envio não segue a automação | Olhe o valor na raia (cabeçalho) |
| O filtro "pula" no começo do play | Antes do primeiro ponto vale o valor do primeiro ponto | Ponha o primeiro ponto no início do trecho, no valor de partida |
| A raia sumiu | Ela foi ocultada (o olho riscado): continua valendo | `A` no cabeçalho, `Mostrar as ocultas` |

### O que evitar

- **Mandar bumbo e baixo para o reverb.** Cauda de grave entope o mix.
- **Deixar a `Mistura` do reverb do barramento em 25%.** O retorno é 100% molhado.
- **Usar o limitador de segurança como ferramenta de volume.** Ele é uma rede de proteção: sempre ligado, sem controles, sem medidor de redução. Volume de masterização se faz com o efeito `Limitador` no master.
- **Confundir mudo com fade.** `M` desce o volume em cerca de 5 ms.
- **Empilhar pré-fader por engano.** Um reverb pré-fader continua soando com a faixa em fade e em mudo: pode ser o que se quer, mas quase nunca é o que se espera.
- **Mover barramentos sem olhar os envios.** O app desfaz sozinho o que ficar contra a ordem, sem perguntar (dá para desfazer com `Ctrl+Z`).
- **Ajustar o fader esperando ouvir enquanto a raia de volume toca.** Ele muda o valor fixo, não a curva.
- **Mais de 16 efeitos numa cadeia ou 16 envios numa faixa.** O motor não processa além disso `(não confirmado no app)`.
