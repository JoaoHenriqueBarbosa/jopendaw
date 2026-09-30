# Referência dos efeitos

> Os 15 efeitos do jopendaw, na ordem do motor: para que serve cada um, todos os parâmetros com faixa e padrão, o que o editor mostra, os presets e dois usos típicos. Use para achar o que um botão faz ou que valor tentar; como montar e mexer no rack está em [06c Painel de efeitos](06c-painel-de-efeitos.md).

## Onde fica

Cada efeito é um cartão no painel `Efeitos` (tecla `F`), na cadeia de uma faixa ou do `Master`. Os presets de cada um ficam no menu de três pontos do cartão (`Presets e mais`).

## Como ler as tabelas

- **Rótulo** é o texto que aparece embaixo do knob (ou na pílula, ou no seletor). **Grupo** é o título cinza em maiúsculas que agrupa os controles no cartão (`TIMBRE`, `SAÍDA`...).
- **Escala**: `linear`, `log` (o knob gasta o mesmo curso por oitava, para frequências e tempos), `inteiro` (passos de 1) ou `opções` (menu ou pílula).
- Porcentagens são mostradas de 0% a 100% (o motor guarda 0 a 1). Tempos abaixo de 1 s são mostrados em ms.
- **Padrão** é o valor de um efeito recém-adicionado e o que `Reiniciar (valores padrão)` restaura. Os padrões do app (`app/lib/daw/effects.dart`) e os do motor (`engine/src/fx/`) foram conferidos e são os mesmos nos 12 primeiros efeitos e no `De-esser` e na `Imagem estéreo`. No `Multibanda` o motor também foi alinhado ao app na fase 17 (limiar −24/−22/−20 dB, razão 3:1, ataque 20/10/4 ms e soltura 250/150/80 ms nas bandas baixa/média/aguda), e um teste do motor confere os números contra `effects.dart`.
- **Presets** aplicam *todos* os parâmetros: o que a tabela do preset não cita vale o padrão. Nas tabelas de preset, um traço `·` significa "padrão".
- Todo valor é guardado na unidade da tabela (dB, Hz, segundos) e limitado à faixa; digitar um valor fora dela o limita.
- Cada parâmetro pode ser automatizado, menos o `Sidechain`.

Os knobs se mexem como descrito em [06c, Controles individuais](06c-painel-de-efeitos.md#controles-individuais): arrastar na vertical, `Shift` para fino, roda, duplo clique para o padrão, botão direito (toque longo) para digitar.

## Resumo

| # | Efeito | Família no menu | Editor | Latência |
|---|---|---|---|---|
| 1 | `EQ` | Timbre | Gráfico de resposta + lista de bandas | 0 |
| 2 | `Compressor` | Dinâmica e utilidade | Curva de transferência + medidor | 0 |
| 3 | `Gate` | Dinâmica e utilidade | Curva de transferência + medidor | 0 |
| 4 | `Limitador` | Dinâmica e utilidade | Curva de transferência + medidor | = `Lookahead` |
| 5 | `Utilitário` | Dinâmica e utilidade | Controles | 0 |
| 6 | `Reverb` | Espaço | Controles | 0 |
| 7 | `Delay` | Espaço | Controles | 0 |
| 8 | `Chorus` (chorus e flanger) | Modulação | Controles | 0 |
| 9 | `Phaser` | Modulação | Controles | 0 |
| 10 | `Tremolo` | Modulação | Controles | 0 |
| 11 | `Distorção` | Saturação | Controles | 32 quadros (0,67 ms a 48 kHz) |
| 12 | `Filtro` | Timbre | Controles | 0 |
| 13 | `Multibanda` | Dinâmica e utilidade | Eixo de frequência com 3 bandas, redução ao vivo por banda + controles | 0 |
| 14 | `De-esser` | Dinâmica e utilidade | Resposta da banda de detecção + medidor de redução + controles | 0 |
| 15 | `Imagem estéreo` | Espaço | Larguras por banda + medidor de fase + controles | 0 |

Detalhes das latências em [Latência e custo de cada efeito](#latência-e-custo-de-cada-efeito).

---

## 1. EQ (8 bandas)

> Equalizador paramétrico com 8 bandas independentes, cada uma com seis tipos de filtro. Serve para limpar graves inúteis, tirar "lama", dar presença e brilho, ou moldar o timbre inteiro de uma faixa.

### Editor

Gráfico de resposta de 20 Hz a 20 kHz (escala logarítmica) e ±24 dB, com o espectro ao vivo da faixa em cinza por trás, mais a lista das 8 bandas. Cada banda tem um nó numerado e colorido. Tudo isso, incluindo o que se arrasta, está em [06c, Gráfico do EQ](06c-painel-de-efeitos.md#gráfico-do-eq); em resumo: arrastar o nó muda `Frequência` (horizontal) e `Ganho` (vertical; `Q` nos passa-alta/baixa), a roda muda o `Q`, duplo clique liga/desliga a banda ou acende uma nova no vazio.

A curva grossa é a resposta somada das bandas ligadas (sem o `Saída`); a curva fina por baixo é a da banda escolhida. O que o editor desenha usa as mesmas fórmulas do motor (Audio EQ Cookbook, de R. Bristow-Johnson).

### Parâmetros

Existem 6 controles por banda (`Banda 1` a `Banda 8`), mais a saída. Na tela eles aparecem na lista `#`, `TIPO`, `FREQ.`, `GANHO`, `Q`; a `Ligada` é o círculo numerado e a `Inclinação` ocupa a coluna `GANHO` nas bandas passa-alta e passa-baixa.

| Controle | O que faz | Valores / padrão |
|---|---|---|
| `Ligada` | Liga a banda. Banda desligada não processa (e seu nó fica vazado no gráfico). | `Não`/`Sim`. Padrão: bandas 1 e 8 `Não`; bandas 2 a 7 `Sim`. |
| `Tipo` | Formato do filtro. | `Passa-alta`, `Prateleira grave`, `Sino`, `Prateleira aguda`, `Passa-baixa`, `Rejeita-faixa`. Padrão por banda: 1 `Passa-alta`; 2 `Prateleira grave`; 3, 4, 5 e 6 `Sino`; 7 `Prateleira aguda`; 8 `Passa-baixa`. |
| `Frequência` | Frequência central (sino, rejeita-faixa), de corte (passa-alta/baixa) ou de virada (prateleiras). | 20 Hz a 20 kHz, log. Padrão: 30 Hz, 100 Hz, 250 Hz, 800 Hz, 2,5 kHz, 6 kHz, 12 kHz, 18 kHz (bandas 1 a 8). |
| `Ganho` | Realce ou corte. Só existe em `Prateleira grave`, `Sino` e `Prateleira aguda`; nos outros tipos o valor não tem efeito. | −24 a +24 dB, linear. Padrão 0 dB. |
| `Q` | Estreiteza. No `Sino` e no `Rejeita-faixa`, Q maior = banda mais estreita. Nas prateleiras muda a curvatura da virada. Nos passa-alta/baixa é a ressonância no corte: 0,71 é Butterworth (plano, −3 dB no corte); acima disso surge um pico no corte. | 0,1 a 18, log. Padrão 1 nos `Sino` (bandas 3 a 6) e 0,71 nas demais. |
| `Inclinação` | Quão abrupto o passa-alta/baixa corta. Só vale nesses dois tipos (nos outros o menu não aparece). | `12 dB/oit`, `24 dB/oit`, `48 dB/oit`. Padrão `24 dB/oit`. |
| `Saída` | Ganho de saída do EQ inteiro, para compensar o que as bandas somaram. | −24 a +24 dB. Padrão 0 dB. |

Nos passa-alta/baixa de 24 e 48 dB/oit, o `Q` da banda só afeta a última seção do filtro (a de Q mais alto), então a ressonância do corte fica localizada.

### Presets

O preset zera as bandas que ele não cita para o padrão (bandas 2 a 7 ligadas em 0 dB, 1 e 8 desligadas), então cada preset só "acende" o que está na tabela. Inclinação padrão 24 dB/oit quando não citada.

| Preset | O que faz (bandas ligadas) | Caráter |
|---|---|---|
| `Corte de graves` | 1: `Passa-alta` 80 Hz. | Limpa a lama abaixo de 80 Hz sem mexer no resto. Ponto de partida para quase qualquer faixa que não seja bumbo ou baixo. |
| `Voz presente` | 1: `Passa-alta` 90 Hz. 3: `Sino` 300 Hz, −2,5 dB, Q 1,2. 5: `Sino` 3 kHz, +3 dB, Q 0,9. 7: `Prateleira aguda` 10 kHz, +2 dB. | Tira o "embolado" de sala pequena e microfone perto, põe presença entre 2 e 5 kHz e um ar no topo. |
| `Bumbo` | 1: `Passa-alta` 30 Hz, 12 dB/oit. 2: `Sino` 60 Hz, +4 dB, Q 1,4. 4: `Sino` 350 Hz, −5 dB, Q 1,5. 5: `Sino` 3,5 kHz, +3,5 dB, Q 1,2. 8: `Passa-baixa` 12 kHz, 12 dB/oit. | Corpo em 60 Hz, tira a "caixa de papelão" em 350 Hz, realça o clique do batedor. |
| `Brilho` | 4: `Sino` 400 Hz, −1 dB, Q 1. 6: `Sino` 4,5 kHz, +1,5 dB, Q 0,7. 7: `Prateleira aguda` 9 kHz, +4 dB. | Abre o topo sem aspereza; bom no master ou num sample opaco. |
| `Calor` | 2: `Prateleira grave` 180 Hz, +2,5 dB. 6: `Sino` 3,2 kHz, −1,5 dB, Q 0,8. | Encorpa os graves-médios e suaviza a aspereza. |
| `Telefone` | 1: `Passa-alta` 400 Hz, 48 dB/oit. 5: `Sino` 1,5 kHz, +5 dB, Q 0,8. 8: `Passa-baixa` 3,2 kHz, 48 dB/oit. | Voz de rádio/telefone: só sobra a faixa de 400 Hz a 3,2 kHz. Efeito criativo. |

### Dois usos típicos

1. **Limpar uma voz gravada**: preset `Voz presente`; depois arraste o nó 3 para onde a voz "embola" (250 a 400 Hz) e ajuste o ganho de −2 a −4 dB.
2. **Cortar o subgrave do resto da mistura para o bumbo e o baixo respirarem**: em guitarras, teclas e vocais, banda 1 em `Passa-alta` a 100 Hz e 24 dB/oit (ou o preset `Corte de graves`, subindo `Frequência` para 100 Hz).

### Cuidados

- Sem latência: os filtros são de fase mínima (o EQ não usa fase linear).
- Trocar tipo, ligar/desligar banda ou mudar a inclinação faz um fade curtíssimo na banda, sem estalo.
- Ganhos somam: várias bandas realçando a mesma região podem passar de +24 dB. Compense com `Saída`.

---

## 2. Compressor

> Reduz a diferença entre os sons fortes e fracos: segura os picos e deixa o resto mais presente. Detector de pico ou RMS, joelho suave, compressão paralela interna, ganho automático e entrada de sidechain.

### Editor

Curva de transferência (entrada × saída, ambos −60 a 0 dB) com o medidor de redução de ganho ao lado e os knobs à direita. Arrastar o gráfico na horizontal muda o `Limiar` (bolinha branca no joelho; `Shift` = fino). Mais em [06c, Gráfico dos efeitos de dinâmica](06c-painel-de-efeitos.md#gráfico-dos-efeitos-de-dinâmica). A legenda do canto mostra limiar, razão e ` · auto`. A faixa sombreada é a largura do `Joelho`. A curva já inclui o ganho de saída como o motor o aplica: o `Ganho` manual mais, com `Ganho automático` ligado, o ganho automático (os dois somam; o desenho sobe junto quando você mexe em qualquer um).

### Parâmetros

| Controle (grupo) | O que faz | Valores / padrão |
|---|---|---|
| `Limiar` (`COMPRESSOR`) | Nível a partir do qual começa a comprimir. | −60 a 0 dB, linear. Padrão −18 dB. |
| `Razão` (`COMPRESSOR`) | Quanto do excesso acima do limiar é cortado. 4:1 = a cada 4 dB acima do limiar, sai 1 dB. | 1:1 a 20:1, log. Padrão 4,0:1. |
| `Ataque` (`COMPRESSOR`) | Tempo para o ganho descer quando o sinal passa do limiar. Lento deixa o transiente passar. | 0,1 ms a 250 ms, log. Padrão 10 ms. |
| `Soltura` (`COMPRESSOR`) | Tempo para o ganho voltar. A volta é exponencial em dB, com jeito analógico. | 5 ms a 3 s, log. Padrão 150 ms. |
| `Joelho` (`COMPRESSOR`) | Largura da transição suave em volta do limiar. 0 = joelho duro. | 0 a 24 dB, linear. Padrão 6 dB. |
| `Ganho` (`SAÍDA`) | Ganho de compensação manual depois da compressão. | 0 a 36 dB, linear. Padrão 0 dB. Continua valendo (e sem apagar) com `Ganho automático` ligado: os dois se somam. |
| `Ganho automático` (`SAÍDA`) | Compensa sozinho: soma ao `Ganho` manual `−Limiar × (1 − 1/Razão) × 0,5` dB (com −18 dB e 4:1, +6,75 dB). | `Não`/`Sim`. Padrão `Não`. |
| `Mistura` (`SAÍDA`) | Mistura do sinal comprimido com o original (compressão paralela dentro do próprio efeito). | 0 a 100%. Padrão 100%. |
| `Detector` (`CHAVE`) | Como o nível é medido. `Pico`: instantâneo, reage a cada transiente. `RMS`: média dos últimos 10 ms, mais parecido com o que o ouvido percebe. | `Pico`, `RMS`. Padrão `RMS`. |
| `Passa-alta` (`CHAVE`) | Filtro passa-alta aplicado **só no sinal que o detector escuta**, não no áudio. Impede que o grave dispare a compressão. | 20 Hz a 500 Hz, log. Padrão 20 Hz. |
| `Sidechain` (`CHAVE`) | Qual faixa o detector escuta. | `Própria entrada` ou o nome de outra faixa. Padrão `Própria entrada`. Ver [O sidechain](#o-sidechain-o-que-ele-exige). |

O detector é ligado entre os canais: o canal mais forte manda, e a redução vale igual para os dois (a imagem estéreo não desloca).

### Presets

| Preset | Limiar | Razão | Ataque | Soltura | Joelho | Ganho | Mistura | Detector | Passa-alta | Caráter |
|---|---|---|---|---|---|---|---|---|---|---|
| `Voz` | −20 dB | 3,5:1 | 5 ms | 80 ms | 6 dB | +4 dB | 100% | RMS | 80 Hz | Nivela a voz sem apertar; a chave sem graves não bombeia com respiração e pops. |
| `Bateria cola` | −16 dB | 2:1 | 30 ms | 200 ms | 4 dB | +2 dB | 100% | RMS | 90 Hz | Ataque lento deixa o transiente do bumbo e da caixa passar e "cola" o conjunto. |
| `Baixo` | −22 dB | 5:1 | 3 ms | 120 ms | 3 dB | +5 dB | 100% | RMS | 20 Hz | Firme e uniforme; chave sem filtro porque o grave é o que se quer medir. |
| `Paralelo pesado` | −35 dB | 10:1 | 1 ms | 100 ms | 0 dB | +12 dB | 40% | Pico | 20 Hz | Compressão de Nova York: esmaga forte e mistura por baixo do sinal limpo. |
| `Suave` | −12 dB | 1,6:1 | 20 ms | 300 ms | 12 dB | 0 dB | 100% | RMS | 20 Hz | Toque leve de cola; `Ganho automático` ligado. |

Aplicar um preset **não muda** o `Sidechain`.

### Dois usos típicos

1. **Nivelar uma voz**: preset `Voz`; abaixe o `Limiar` até o medidor marcar entre −3 e −6 dB nas frases mais fortes.
2. **Sidechain pumping**: o compressor numa faixa de pad ou baixo, `Sidechain` apontando para a faixa do bumbo, `Razão` 6:1, `Ataque` 1 ms, `Soltura` 150 ms, `Detector` `Pico`. Receita em [Efeitos em combinação](../guias/efeitos-em-combinacao.md).

### Cuidados

- O `Ganho` manual e o `Ganho automático` **se somam** no motor, e o editor mostra isso: o knob `Ganho` não fica apagado com o automático ligado e a curva do gráfico usa a soma. Se quiser só o automático, deixe o `Ganho` em 0 (testado só por testes automáticos).
- Sem lookahead: um ataque lento deixa passar o começo do transiente (é o efeito desejado em bateria; em picos de voz, use ataque mais curto).
- O medidor do compressor vai a 24 dB; se estiver batendo lá, o `Limiar` está baixo demais.

---

## 3. Gate

> Fecha o som quando ele fica abaixo do limiar: tira ruído de fundo entre frases, vazamento de outros instrumentos na bateria, cauda de reverb indesejada. Com sidechain, vira um "portão rítmico".

### Editor

Curva de transferência de −80 a 0 dB, medidor de redução (escala de 3 a 60 dB) e knobs. Arrastar na horizontal muda o `Limiar`. A curva é uma reta 1:1 acima do limiar e, abaixo, é a mesma reta deslocada pelo `Alcance`. Legenda: `limiar -50.0 dB`.

### Parâmetros

| Controle (grupo) | O que faz | Valores / padrão |
|---|---|---|
| `Limiar` (`GATE`) | Nível de abertura. O portão abre quando o pico passa dele. | −80 a 0 dB, linear. Padrão −50 dB. |
| `Ataque` (`GATE`) | Tempo de abertura, em curva suave (começa e termina parada, sem quina). | 0,1 ms a 100 ms, log. Padrão 0,5 ms. |
| `Retenção` (`GATE`) | Tempo que o portão fica aberto depois que o nível cai abaixo do limiar de fechamento. Evita tremular em sons que decaem. | 0 a 1 s, linear. Padrão 20 ms. |
| `Soltura` (`GATE`) | Tempo de fechamento (chega a 99,9% do caminho nesse tempo). | 5 ms a 2 s, log. Padrão 100 ms. |
| `Alcance` (`GATE`) | Quanto o portão fecha. −80 dB = silêncio; valores mais altos deixam parte do som passar (um gate "suave"). 0 dB = não fecha nada. | −80 a 0 dB, linear. Padrão −80 dB. |
| `Passa-alta` (`CHAVE`) | Passa-alta no sinal que o detector escuta (não no áudio). Tira o grave que abriria o portão à toa. | 20 Hz a 2 kHz, log. Padrão 20 Hz. |
| `Sidechain` (`CHAVE`) | Qual faixa o detector escuta. | `Própria entrada` ou outra faixa. Padrão `Própria entrada`. |

A histerese é fixa: o portão fecha 4 dB abaixo do limiar de abertura. O detector é de pico, ligado entre canais, com queda de 8 ms. O gate nasce fechado.

### Presets

| Preset | Limiar | Ataque | Retenção | Soltura | Alcance | Passa-alta | Caráter |
|---|---|---|---|---|---|---|---|
| `Ruído de fundo` | −55 dB | 1 ms | 50 ms | 200 ms | −30 dB | 20 Hz | Suave: abaixa o chiado 30 dB entre frases sem cortar seco. |
| `Tons de bateria` | −30 dB | 0,5 ms | 80 ms | 150 ms | −80 dB | 100 Hz | Fecha de vez entre as batidas de tom e surdo; a chave ignora o grave de outros instrumentos. |
| `Corte seco` | −35 dB | 0,1 ms | 10 ms | 20 ms | −80 dB | 20 Hz | Portão rápido e duro, para cortar caudas. |

### Dois usos típicos

1. **Limpar um microfone de voz**: preset `Ruído de fundo`; arraste o `Limiar` até o medidor só reagir entre as frases.
2. **Portão rítmico**: gate num pad com `Sidechain` na faixa do hi-hat, `Alcance` −80 dB, `Retenção` 50 ms, `Soltura` 100 ms: o pad só soa junto do hi-hat.

### Cuidados

- Sem lookahead: o ataque começa quando o sinal cruza o limiar. Com ataque lento, o começo do som é cortado. Use 0,1 a 1 ms em material percussivo.
- O medidor satura em 60 dB de redução, mesmo com `Alcance` em −80 dB.

---

## 4. Limitador

> Teto absoluto: nenhum pico passa do `Teto`. Serve no master, num barramento de bateria ou para ganhar volume sem estourar. Tem lookahead, portanto atrasa o som (o motor alinha o resto da mixagem a esse atraso: [06e](06e-compensacao-de-latencia.md)).

### Editor

Curva de transferência de −36 a 0 dB e medidor de redução (até 24 dB). A curva sobe 1:1 com o `Ganho` de entrada e bate no `Teto`. Arrastar na horizontal muda o `Ganho` (arrastar para a esquerda empurra **mais** ganho). Legenda: `teto -0.3 dB`.

### Parâmetros

| Controle (grupo) | O que faz | Valores / padrão |
|---|---|---|
| `Ganho` (`LIMITADOR`) | Ganho aplicado antes do limitador: é o que "empurra" o som contra o teto. | 0 a 24 dB, linear. Padrão 0 dB. |
| `Teto` (`LIMITADOR`) | Nível máximo de saída. | −24 a 0 dB, linear. Padrão −0,3 dB. |
| `Soltura` (`LIMITADOR`) | Tempo que o ganho leva para voltar depois de um pico. Curta = mais volume e mais distorção; longa = mais transparente. | 1 ms a 1 s, log. Padrão 50 ms. |
| `Lookahead` (`LIMITADOR`) | Quanto o limitador enxerga à frente. Mais lookahead = ataque mais suave, mas mais latência. | 0 a 10 ms, linear. Padrão 3 ms. |
| `Ligação estéreo` (`LIMITADOR`) | 100% = os dois canais recebem a mesma redução (a imagem não desloca). 0% = cada canal é limitado sozinho. | 0 a 100%. Padrão 100%. |

O limitador trabalha com o pico das amostras; não achei no código detecção de pico verdadeiro (entre amostras) `(não confirmado)`. O teto padrão de −0,3 dB deixa uma folga para o conversor.

### Presets

| Preset | Ganho | Teto | Soltura | Lookahead | Ligação | Caráter |
|---|---|---|---|---|---|---|
| `Master −1 dB` | +3 dB | −1 dB | 80 ms | 5 ms | 100% | Teto seguro para exportar, com 3 dB de empurrão. |
| `Transparente` | +1,5 dB | −0,5 dB | 250 ms | 6 ms | 70% | Quase inaudível: pouco ganho, soltura longa. |
| `Alto` | +8 dB | −1 dB | 150 ms | 6 ms | 80% | Ganho forte para mistura "alta"; aceita alguma distorção. |

### Dois usos típicos

1. **Último efeito do master**: preset `Master −1 dB`; suba o `Ganho` até o medidor marcar 2 a 4 dB nos picos.
2. **Amaciar picos de um barramento de bateria**: `Ganho` +4 dB, `Teto` −3 dB, `Soltura` 80 ms, `Lookahead` 3 ms.

### Cuidados

- Além deste efeito, o master tem um **limitador de segurança sempre ligado** no fim (teto −0,3 dBFS, lookahead de 1,5 ms); ele não aparece na cadeia e não tem controle na interface.
- A latência é igual ao `Lookahead` e é compensada pelo motor nas outras faixas ([06e](06e-compensacao-de-latencia.md)); o bypass não tira a latência (só `Lookahead` 0 ou remover o efeito). Mudá-lo com som passando abaixa a saída por um instante (fade de 4 ms) e volta, e o motor refaz a compensação com um crossfade de 10 ms. Automatizar o `Lookahead` refaz a compensação no máximo a cada 20 ms (ver 06e), mas o limitador abaixa a saída a cada valor novo: prefira degraus a rampas.
- Lookahead 0 = sem latência, mas o ataque do limitador passa a ser bruto.

---

## 5. Utilitário

> Ganho, balanço, largura estéreo, mono, inversão de fase, troca de canais e remoção de DC, num efeito só. Não colore o som: serve para arrumar o estéreo e o nível.

### Editor

Só controles, sem gráfico.

### Parâmetros

| Controle (grupo) | O que faz | Valores / padrão |
|---|---|---|
| `Ganho` (`UTILITÁRIO`) | Ganho de saída. | −48 a +24 dB, linear. Padrão 0 dB. |
| `Pan` (`UTILITÁRIO`) | Balanço. O centro fica em 0 dB e o `Pan` só **abaixa** o lado oposto (como o balanço do master, não como o pan de uma faixa). Mostrado como número, de −1 (esquerda) a +1 (direita). | −1 a +1, linear. Padrão 0. |
| `Largura` (`UTILITÁRIO`) | Largura estéreo por mid/side. 100% = igual à entrada; 0% = mono; até 200% = lado dobrado. | 0 a 200%, linear. Padrão 100%. |
| `Mono` (`CANAIS`) | Soma os canais (a largura vai a 0). | `Não`/`Sim`. Padrão `Não`. |
| `Inverter esq.` (`CANAIS`) | Inverte a polaridade do canal esquerdo. | `Não`/`Sim`. Padrão `Não`. |
| `Inverter dir.` (`CANAIS`) | Inverte a polaridade do canal direito. | `Não`/`Sim`. Padrão `Não`. |
| `Trocar E/D` (`CANAIS`) | Troca esquerda e direita. | `Não`/`Sim`. Padrão `Não`. |
| `Tirar DC` (`CANAIS`) | Passa-alta de 5 Hz que remove deslocamento DC. | `Não`/`Sim`. Padrão `Não`. |

Ordem interna: tira o DC, inverte a fase, troca os canais, ajusta a largura e por fim `Pan` e `Ganho`. Todas as chaves são suavizadas (sem clique).

### Presets

| Preset | O que muda | Caráter |
|---|---|---|
| `Mono` | `Mono` `Sim` | Confere a compatibilidade mono do baixo ou da mistura. |
| `Estéreo largo` | `Largura` 150% | Abre o estéreo de um pad ou de uma mistura. |
| `Fase invertida` | `Inverter esq.` e `Inverter dir.` `Sim` | Inverte a polaridade total; para casar dois microfones em oposição (ex.: caixa em cima e embaixo). |
| `−6 dB` | `Ganho` −6 dB | Corta 6 dB (metade da amplitude). |

### Dois usos típicos

1. **Baixo em mono**: `Utilitário` com `Mono` `Sim` na faixa do baixo, para o grave ficar no centro e não brigar entre os lados.
2. **Corrigir uma gravação com DC**: `Tirar DC` `Sim` na primeira posição da cadeia (antes de compressor ou distorção, que amplificam o DC).

### Cuidados

- Sem latência.
- `Largura` acima de 100% em material já largo pode causar cancelamento em mono.

---

## 6. Reverb (FDN)

> Ambiência de salas: rede de atraso realimentada de 8 linhas, com pré-atraso, reflexões iniciais, difusão e cauda calibrada em segundos. Vai de quarto a catedral e também congela a cauda.

### Editor

Só controles, em dois grupos: `REVERB` (as quatro primeiras) e `TIMBRE`.

### Parâmetros

| Controle (grupo) | O que faz | Valores / padrão |
|---|---|---|
| `Mistura` (`REVERB`) | Seco/molhado de potência constante: o volume total se mantém ao girar. 0% = só o original; 100% = só a reverb. | 0 a 100%. Padrão 25%. |
| `Pré-atraso` (`REVERB`) | Tempo antes de a reverb começar. Separa o som seco da ambiência e mantém a clareza. | 0 a 250 ms, linear. Padrão 20 ms. |
| `Tamanho` (`REVERB`) | Tamanho da sala (comprimento das 8 linhas, de 25% a 100% do máximo). O tamanho desliza devagar: mexer com som tocando dá um leve glissando na cauda. | 0 a 100%. Padrão 60%. |
| `Decaimento` (`REVERB`) | RT60: quanto a cauda leva para cair 60 dB. | 0,2 s a 20 s, log. Padrão 2,2 s. Apagado com `Congelar` ligado. |
| `Abafar` (`TIMBRE`) | Frequência acima da qual a cauda cai mais rápido (a cauda escurece). Menor = mais escuro. | 1 kHz a 20 kHz, log. Padrão 7 kHz. |
| `Cortar graves` (`TIMBRE`) | Passa-alta na entrada da cauda (o seco não é filtrado). Evita reverb "barrenta" nos graves. | 20 Hz a 1 kHz, log. Padrão 120 Hz. |
| `Largura` (`TIMBRE`) | Largura estéreo da cauda. | 0 a 100%. Padrão 100%. |
| `Modulação` (`TIMBRE`) | Balanço lento (menos de 1 Hz) do comprimento das linhas, que tira o som metálico. | 0 a 100%. Padrão 30%. |
| `Primeiras reflexões` (`TIMBRE`) | Nível das reflexões iniciais (as primeiras batidas nas paredes; no tamanho máximo caem entre 7 e 71 ms e encolhem com o `Tamanho`). | 0 a 100%. Padrão 50%. |
| `Congelar` (`TIMBRE`) | Sustenta a cauda indefinidamente (RT60 de 1 hora) e corta a entrada: o que estava soando fica soando. | `Não`/`Sim`. Padrão `Não`. |

### Presets

| Preset | Mistura | Pré-atraso | Tamanho | Decaimento | Abafar | Cortar graves | Largura | Modulação | Primeiras refl. | Congelar | Caráter |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `Quarto` | 18% | 5 ms | 25% | 0,5 s | 6 kHz | 150 Hz | 70% | 20% | 70% | Não | Ambiente curto e íntimo, de cabine. |
| `Sala` | 22% | 15 ms | 50% | 1,4 s | 7,5 kHz | 120 Hz | 90% | 30% | 55% | Não | Sala de ensaio, presença natural. |
| `Salão` | 28% | 30 ms | 80% | 2,8 s | 6 kHz | 100 Hz | 100% | 35% | 40% | Não | Espaço grande e nobre. |
| `Placa` | 25% | 10 ms | 55% | 1,8 s | 12 kHz | 200 Hz | 100% | 45% | 15% | Não | Quase sem reflexões iniciais, densa e brilhante desde o começo: a reverb clássica de voz e caixa. |
| `Catedral` | 35% | 60 ms | 100% | 7 s | 4,5 kHz | 80 Hz | 100% | 40% | 30% | Não | Cauda enorme e escura. |
| `Shimmer congelado` | 50% | 80 ms | 100% | 20 s | 9 kHz | 300 Hz | 100% | 80% | 10% | Sim | Cauda congelada e bem modulada: pad etéreo que segura o que entrou. |

### Dois usos típicos

1. **Retorno de reverb num barramento**: `Reverb` num barramento com `Mistura` **100%** (só molhado), e as faixas mandam para ele pelo envio (ver [06 Mixer](06-mixer.md)). Preset `Placa`; `Pré-atraso` 20 ms para vozes.
2. **Textura congelada**: preset `Shimmer congelado` numa faixa de sintetizador; toque um acorde e a cauda fica sustentando.

### Cuidados

- Como insert direto numa faixa, `Mistura` acima de 30% costuma empastar; prefira um barramento.
- Sem latência (o `Pré-atraso` é parte do som).
- Com `Congelar` ligado, `Decaimento` fica apagado; ainda dá para mexer nele, mas sem efeito.
- A cauda continua depois que a faixa acaba (o motor mantém a cadeia rodando enquanto houver som).

---

## 7. Delay

> Ecos de até 4 s, livres em segundos ou sincronizados com o andamento do projeto, com ping-pong, filtros e saturação a cada repetição, wow/flutter de fita e ducking.

### Editor

Só controles, em dois grupos: `DELAY` e `TIMBRE`. O controle `Tempo livre` só aparece com `Tempo` em `Livre`; `Nota` só aparece com `Tempo` em `Andamento`.

### Parâmetros

| Controle (grupo) | O que faz | Valores / padrão |
|---|---|---|
| `Mistura` (`DELAY`) | Seco/molhado de potência constante. | 0 a 100%. Padrão 30%. |
| `Tempo` (`DELAY`) | Escolhe se o atraso é livre (segundos) ou preso ao andamento. | `Livre`, `Andamento`. Padrão `Andamento`. |
| `Tempo livre` (`DELAY`) | Atraso em segundos (só com `Tempo` `Livre`). | 1 ms a 4 s, log. Padrão 375 ms. |
| `Nota` (`DELAY`) | Figura rítmica (só com `Tempo` `Andamento`). | `1/32`, `1/16T`, `1/16`, `1/16D`, `1/8T`, `1/8`, `1/8D`, `1/4T`, `1/4`, `1/4D`, `1/2`, `1/1`. Padrão `1/8D`. |
| `Realimentação` (`DELAY`) | Quanto do eco volta para a linha (número de repetições). | 0 a 98%, linear. Padrão 40%. |
| `Ping-pong` (`DELAY`) | Os ecos alternam entre esquerda e direita. | `Não`/`Sim`. Padrão `Não`. |
| `Desvio E/D` (`DELAY`) | Diferença de tempo entre os canais: o atraso da direita menos o da esquerda (positivo = direita mais atrasada; a diferença é dividida meio a meio entre os dois lados). Apagado com `Ping-pong` ligado. | −50 a +50 ms, linear. Padrão 0. |
| `Passa-alta` (`TIMBRE`) | Filtro na realimentação: cada repetição perde graves. | 20 Hz a 2 kHz, log. Padrão 80 Hz. |
| `Passa-baixa` (`TIMBRE`) | Filtro na realimentação: cada repetição escurece. | 500 Hz a 20 kHz, log. Padrão 8 kHz. |
| `Modulação` (`TIMBRE`) | Wow e flutter de fita: o atraso balança lento (0,55 Hz, até 1,8 ms) e rápido (6,3 Hz, até 0,12 ms). | 0 a 100%. Padrão 0%. |
| `Saturação` (`TIMBRE`) | Saturação suave (tanh) na realimentação: cada eco fica mais gordo. Drive baixo quase não toca no sinal. | 0 a 100%. Padrão 0%. |
| `Ducking` (`TIMBRE`) | Abaixa os ecos enquanto a entrada toca (ataque 10 ms, soltura 300 ms; abaixa por inteiro a partir de −20 dBFS de entrada). Os ecos voltam nas pausas. | 0 a 100%. Padrão 0%. |

**Cálculo do tempo sincronizado:** atraso em segundos = batidas da figura × 60 ÷ andamento. As batidas de cada `Nota` (tabela `NOTE_BEATS` do motor):

| `Nota` | `1/32` | `1/16T` | `1/16` | `1/16D` | `1/8T` | `1/8` | `1/8D` | `1/4T` | `1/4` | `1/4D` | `1/2` | `1/1` |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Batidas | 0,125 | 0,1667 | 0,25 | 0,375 | 0,3333 | 0,5 | 0,75 | 0,6667 | 1 | 1,5 | 2 | 4 |
| Atraso a 120 BPM | 62,5 ms | 83,3 ms | 125 ms | 187,5 ms | 166,7 ms | 250 ms | 375 ms | 333,3 ms | 500 ms | 750 ms | 1000 ms | 2000 ms |

(`T` = tercina; `D` = pontuada.) O tempo acompanha o andamento do projeto, inclusive quando ele muda: mudanças pequenas deslizam (no máximo ±2% de afinação) e saltos grandes fazem um crossfade de 60 ms entre a posição velha e a nova. **Com mapa de andamento** (faixa `Andamento`, ver [Timeline e clipes](02b-timeline-e-clipes.md#faixa-andamento-e-mapa-de-compassos)), o delay em `Andamento` usa só o andamento **inicial** do projeto: ele não acompanha os saltos nem as rampas do mapa (o mesmo vale para o tremolo e o filtro em `Andamento`). Só a mudança do BPM inicial, pelo botão de andamento, chega a ele.

**Como funciona o ping-pong:** a entrada (soma dos dois canais) entra só na linha esquerda; o primeiro eco sai à **esquerda**, o segundo à **direita**, o terceiro à esquerda, e assim por diante, cada um com a realimentação aplicada.

### Presets

| Preset | Mistura | Tempo | Nota / livre | Realim. | Ping-pong | Desvio | Passa-alta | Passa-baixa | Modul. | Satur. | Ducking | Caráter |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `1/8 pontilhado` | 25% | Andamento | `1/8D` | 35% | Não | · | 150 Hz | 6 kHz | 5% | · | 30% | O eco clássico de guitarra e voz, discreto e limpo; abaixa quando a fonte toca. |
| `Ping-pong 1/4` | 30% | Andamento | `1/4` | 45% | Sim | · | 120 Hz | 7 kHz | 10% | · | 20% | Ecos de semínima saltando de um lado a outro. |
| `Slapback` | 30% | Livre | 110 ms | 5% | Não | · | 100 Hz | 5 kHz | · | 10% | · | Eco curto e único, de rockabilly. |
| `Dub` | 35% | Andamento | `1/4D` | 72% | Não | · | 250 Hz | 2,5 kHz | 30% | 45% | · | Ecos de semínima pontuada que escurecem e saturam a cada volta, como fita gasta; muitas repetições. |
| `Eco largo` | 22% | Andamento | `1/4` | 30% | Não | +20 ms | 200 Hz | 9 kHz | · | · | 40% | Eco de semínima aberto (direita 20 ms depois da esquerda) que some enquanto a fonte toca. |

### Dois usos típicos

1. **Delay de voz sem sujar**: preset `1/8 pontilhado`, `Ducking` 30% para os ecos só aparecerem nas pausas.
2. **Ping-pong sincronizado**: preset `Ping-pong 1/4`; com o projeto a 100 BPM o eco cai a cada 600 ms. Receita em [Efeitos em combinação](../guias/efeitos-em-combinacao.md).

### Cuidados

- Sem latência. A cauda de ecos continua por até 4,5 s depois do fim do som.
- `Realimentação` acima de 90% quase não decai: com `Passa-baixa` e `Saturação` baixos o volume pode acumular; o motor limita a malha por segurança.
- Voltar de um bypass limpa as linhas: o delay não devolve ecos de antes.
- Projeto com mapa de andamento: em `Tempo` `Andamento` o eco fica preso ao BPM **inicial** (ver a nota acima); para um eco que caiba num trecho de outro andamento, use `Tempo` `Livre` (controle `Tempo livre`) com os milissegundos calculados à mão para aquele trecho.

---

## 8. Chorus (chorus e flanger)

> Duplica o som com atrasos que oscilam devagar: chorus (atraso longo, sem realimentação), flanger (atraso curtíssimo com realimentação, que varre um filtro-pente) e vibrato (só molhado, uma voz). Uma a quatro vozes por canal, em estéreo.

### Editor

Só controles, um grupo `CHORUS`.

### Parâmetros

| Controle (grupo) | O que faz | Valores / padrão |
|---|---|---|
| `Mistura` (`CHORUS`) | Seco/molhado de potência constante. | 0 a 100%. Padrão 50%. |
| `Taxa` (`CHORUS`) | Frequência do LFO senoidal que balança o atraso. | 0,02 Hz a 10 Hz, log. Padrão 0,8 Hz. |
| `Profundidade` (`CHORUS`) | Quanto o atraso oscila: até ±4 ms com 100% (nunca mais que 90% do atraso base). | 0 a 100%. Padrão 50%. |
| `Atraso` (`CHORUS`) | Atraso base. Longo (10 a 30 ms) = chorus; curto (1 a 5 ms) com realimentação = flanger. | 1 ms a 30 ms, linear. Padrão 12 ms. |
| `Vozes` (`CHORUS`) | Quantas cópias defasadas somam. Trocar o número faz fade das vozes, sem estalo. | 1 a 4, inteiro. Padrão 2. |
| `Realimentação` (`CHORUS`) | Realimentação do atraso. Positiva e negativa dão picos do pente em posições diferentes. | −95% a +95%. Padrão 0%. |
| `Largura` (`CHORUS`) | Defasagem dos LFOs da direita em relação aos da esquerda. 100% = as vozes de um lado caem no meio das do outro. | 0 a 100%. Padrão 100%. |

### Presets

| Preset | Mistura | Taxa | Prof. | Atraso | Vozes | Realim. | Largura | Caráter |
|---|---|---|---|---|---|---|---|---|
| `Chorus leve` | 35% | 0,6 Hz | 35% | 14 ms | 2 | 0% | 100% | Duplicação sutil, abre e engrossa sem chamar atenção. |
| `Flanger jato` | 50% | 0,12 Hz | 80% | 2 ms | 1 | 75% | 80% | Atraso curtíssimo com realimentação alta: o pente varrendo devagar, som de avião. |
| `Ensemble` | 50% | 1,1 Hz | 50% | 18 ms | 4 | 0% | 100% | Quatro vozes, efeito de "orquestra de cordas". |
| `Vibrato` | 100% | 5 Hz | 25% | 4 ms | 1 | 0% | 0% | Só molhado, uma voz e sem largura: modula a afinação, não engrossa. |

### Dois usos típicos

1. **Pad largo**: `Ensemble` com `Mistura` 40%, seguido de `Reverb`. Receita em [Efeitos em combinação](../guias/efeitos-em-combinacao.md).
2. **Flanger de transição em bateria ou sintetizador**: `Flanger jato`; automatize a `Mistura` de 0 a 50% durante o *build-up*.

### Cuidados

- Sem latência do efeito (o atraso é o próprio som).
- Realimentação alta com pouco atraso ressoa forte: o motor compensa o volume, mas confira o pico.

---

## 9. Phaser

> Filtros passa-tudo em série, varridos por um LFO: somados ao original, criam vales que caminham pelo espectro. De 2 a 12 estágios, realimentação e defasagem estéreo.

### Editor

Só controles, um grupo `PHASER`.

### Parâmetros

| Controle (grupo) | O que faz | Valores / padrão |
|---|---|---|
| `Mistura` (`PHASER`) | Quanto do sinal filtrado soma ao original (mistura linear). Em 50% os vales são mais profundos. | 0 a 100%. Padrão 50%. |
| `Taxa` (`PHASER`) | Frequência do LFO. | 0,02 Hz a 10 Hz, log. Padrão 0,5 Hz. |
| `Profundidade` (`PHASER`) | Amplitude da varredura em oitavas em torno do `Centro`: 100% = ±3 oitavas. | 0 a 100%. Padrão 70%. |
| `Centro` (`PHASER`) | Frequência em torno da qual a varredura acontece. | 100 Hz a 8 kHz, log. Padrão 1 kHz. |
| `Realimentação` (`PHASER`) | Afia os vales e cria picos (som mais vocálico). Negativa muda o timbre dos picos. | −95% a +95%. Padrão 50%. |
| `Estágios` (`PHASER`) | Número de estágios passa-tudo: mais estágios, mais vales. Trocar faz crossfade, sem estalo. | `2`, `4`, `6`, `8`, `12`. Padrão `4`. |
| `Estéreo` (`PHASER`) | Defasagem do LFO entre os canais. 100% = 180°. | 0 a 100%. Padrão 50%. |

### Presets

| Preset | Mistura | Taxa | Prof. | Centro | Realim. | Estágios | Estéreo | Caráter |
|---|---|---|---|---|---|---|---|---|
| `Lento` | 50% | 0,15 Hz | 80% | 800 Hz | 50% | 6 | 50% | Varredura longa e macia, para teclas e guitarra. |
| `Rápido` | 50% | 3,5 Hz | 60% | 1,2 kHz | 35% | 4 | 25% | Efeito de Leslie/vibração rápida. |
| `Profundo (12 estágios)` | 50% | 0,08 Hz | 100% | 1,5 kHz | 80% | 12 | 50% | Muitos vales, ressonante e lento: som de sintetizador. |

### Dois usos típicos

1. **Piano elétrico ou guitarra limpa**: `Lento`, `Mistura` 40%.
2. **Pad em movimento constante**: `Profundo (12 estágios)` antes da reverb.

### Cuidados

- Sem latência. O motor compensa o volume da realimentação alta.
- O `Phaser` não tem modo sincronizado ao andamento (só `Taxa` em Hz).

---

## 10. Tremolo

> Volume oscilando no ritmo de um LFO (senoide, triângulo ou quadrada), livre em Hz ou no andamento. Com defasagem estéreo em 50% vira autopan.

### Editor

Só controles, um grupo `TREMOLO`. `Taxa` só aparece com `Tempo` `Livre`; `Nota` só com `Andamento`.

### Parâmetros

| Controle (grupo) | O que faz | Valores / padrão |
|---|---|---|
| `Taxa` (`TREMOLO`) | Frequência do LFO (só com `Tempo` `Livre`). | 0,05 Hz a 20 Hz, log. Padrão 4 Hz. |
| `Profundidade` (`TREMOLO`) | Quanto o volume cai no vale. 100% = silêncio total no vale. | 0 a 100%. Padrão 50%. |
| `Onda` (`TREMOLO`) | Forma do LFO. `Quadrada` corta o som (efeito *chopper*) com bordas suaves de 3 ms, sem clique. | `Senoide`, `Triângulo`, `Quadrada`. Padrão `Senoide`. |
| `Estéreo` (`TREMOLO`) | Defasagem do LFO entre os canais. 50% = os canais em oposição: o som passeia de um lado a outro (autopan). | 0 a 100%. Padrão 0%. |
| `Tempo` (`TREMOLO`) | Livre em Hz ou preso ao andamento. | `Livre`, `Andamento`. Padrão `Livre`. |
| `Nota` (`TREMOLO`) | Duração de um ciclo completo do LFO (só com `Andamento`). Mesmas figuras do delay. | 12 figuras de `1/32` a `1/1`. Padrão `1/8`. |

A frequência sincronizada é `andamento ÷ 60 ÷ batidas da figura`: `1/4` = um ciclo por batida. O `andamento` aqui é o inicial do projeto: com mapa de andamento (faixa `Andamento`) o tremolo sincronizado não segue as mudanças (ver a nota no [Delay](#7-delay)).

### Presets

| Preset | Taxa | Prof. | Onda | Estéreo | Tempo | Nota | Caráter |
|---|---|---|---|---|---|---|---|
| `Tremolo clássico` | 5 Hz | 50% | `Senoide` | 0% | `Livre` | · | Tremolo de amplificador de guitarra. |
| `Autopan 1/4` | · | 80% | `Senoide` | 50% | `Andamento` | `1/4` | O som passeia entre os lados em um ciclo por batida. |
| `Picotado 1/16` | · | 100% | `Quadrada` | 0% | `Andamento` | `1/16` | *Chopper* em semicolcheias: liga e desliga o som no ritmo. |

### Dois usos típicos

1. **Autopan em pad ou percussão**: `Autopan 1/4`; `Nota` `1/2` para ir mais devagar.
2. **Efeito trance-gate rítmico**: `Picotado 1/16` num acorde sustentado.

### Cuidados

- Sem latência. O LFO não é realinhado ao início do compasso (a fase é livre): o ciclo acompanha o andamento, mas não necessariamente o batimento exato da timeline `(não confirmado)`.
- `Profundidade` 100% cria vazios totais: em `Quadrada` o som some por metade do ciclo.
- Projeto com mapa de andamento: em `Andamento` o ciclo usa só o BPM **inicial** e não segue as mudanças do mapa (ver a nota em cima, na tabela do tremolo).

---

## 11. Distorção (sobreamostragem)

> Saturação e distorção em seis tipos, de suave a bitcrusher, com sobreamostragem para evitar aliasing, filtro de tom, mistura paralela e volume compensado.

### Editor

Só controles, em três grupos: `DISTORÇÃO` (`Drive`, `Tipo`, `Tom`), `SAÍDA` (`Mistura`, `Saída`, `Sobreamostragem`) e `BITCRUSHER` (`Bits`, `Reduzir taxa`, `Dither`). `Bits`, `Reduzir taxa` e `Dither` ficam apagados quando `Tipo` não é `Bitcrusher`; `Sobreamostragem` fica apagada quando `Tipo` **é** `Bitcrusher` (o motor a ignora nesse tipo). Apagado continua mexível.

### Parâmetros

| Controle (grupo) | O que faz | Valores / padrão |
|---|---|---|
| `Drive` (`DISTORÇÃO`) | Ganho de entrada na curva: mais drive, mais harmônicos e compressão. O volume é compensado para um sinal de referência de −12 dBFS de pico: abaixo dele a distorção sobe o volume, como qualquer saturação. | 0 a 48 dB, linear. Padrão 12 dB. |
| `Tipo` (`DISTORÇÃO`) | Curva de distorção. Ver tabela abaixo. | `Suave`, `Válvula`, `Fita`, `Dura`, `Dobra`, `Bitcrusher`. Padrão `Suave`. |
| `Tom` (`DISTORÇÃO`) | Passa-baixa **depois** da saturação (tira o chiado agudo). Em 20 kHz sai da cadeia. | 500 Hz a 20 kHz, log. Padrão 8 kHz. |
| `Mistura` (`SAÍDA`) | Mistura do distorcido com o original (distorção paralela). O original é atrasado igual ao molhado, então a soma não vira filtro-pente. | 0 a 100%. Padrão 100%. |
| `Saída` (`SAÍDA`) | Ganho de saída. | −24 a +12 dB, linear. Padrão 0 dB. |
| `Sobreamostragem` (`SAÍDA`) | Processa a curva em taxa dobrada ou quadruplicada e filtra: sem isso, harmônicos acima de Nyquist rebatem para o grave (aliasing). 4× é o mais limpo e o mais pesado. Não vale no tipo `Bitcrusher` (o aliasing é o efeito): nele o controle fica apagado. | `1×`, `2×`, `4×`. Padrão `2×`. |
| `Bits` (`BITCRUSHER`) | Resolução da quantização. 1 bit = só dois níveis. | 1 a 16, inteiro. Padrão 8. |
| `Reduzir taxa` (`BITCRUSHER`) | Segura cada amostra por N quadros (queda da taxa de amostragem). | 1× a 32×, inteiro. Padrão 1×. |
| `Dither` (`BITCRUSHER`) | Liga um ruído triangular (TPDF, de ±1 degrau) somado antes de cada quantização: o erro de quantização vira um chiado suave em vez de distorção granulosa. Só age no tipo `Bitcrusher`. | `Não`/`Sim` (pílula). Padrão `Não`. Os presets voltam esse controle a `Não`. |

Os tipos:

| `Tipo` | Curva | Caráter |
|---|---|---|
| `Suave` | Tangente hiperbólica | Saturação clássica, compressão gradual, harmônicos ímpares. |
| `Válvula` | Assimétrica, com ponto de operação deslocado | Harmônicos pares e ímpares, mais calor; o semiciclo negativo satura antes. O DC gerado é removido. |
| `Fita` | Curva algébrica de joelho largo, com pré-ênfase de agudos em 3 kHz, leve compressão e passa-baixa da cabeça que fecha uma oitava a cada 32 dB de drive | Perde agudos ao saturar, como fita magnética. |
| `Dura` | Corte rígido em ±1 | Fuzz agressivo, harmônicos ímpares fortes. |
| `Dobra` | Dobrador senoidal (*wavefolder*) | O que passa do teto volta refletido: timbre metálico, quase FM. |
| `Bitcrusher` | Quantização e redução de taxa | Lo-fi digital. Entrada abaixo de −100 dB vira silêncio (sem DC). |

### Presets

| Preset | Drive | Tipo | Tom | Mistura | Saída | Sobreamostr. | Bits / Reduzir taxa | Caráter |
|---|---|---|---|---|---|---|---|---|
| `Saturação de fita` | 6 dB | `Fita` | 12 kHz | 100% | −2 dB | 2× | · | Cola e amacia; quase não se percebe como distorção. |
| `Válvula quente` | 14 dB | `Válvula` | 7 kHz | 100% | −6 dB | 2× | · | Calor e presença; bom em baixo e sintetizador. |
| `Fuzz` | 36 dB | `Dura` | 4,5 kHz | 100% | −12 dB | 4× | · | Distorção pesada, com `Tom` fechado. |
| `Lo-fi 8 bits` | 0 dB | `Bitcrusher` | 9 kHz | 100% | −1 dB | 1× | 8 bits / 4× | Som de videogame antigo. |
| `Dobra metálica` | 18 dB | `Dobra` | 6 kHz | 60% | −8 dB | 4× | · | Metálico e inarmônico, com 40% do som limpo. |

### Dois usos típicos

1. **Baixo com dentes**: `Distorção` `Válvula quente` com `Mistura` 50%, para manter o grave limpo e adicionar harmônicos. Receita em [Efeitos em combinação](../guias/efeitos-em-combinacao.md).
2. **Bateria lo-fi**: `Lo-fi 8 bits` num barramento de bateria com `Mistura` 40%.

### Cuidados

- **Latência fixa de 32 quadros** (0,67 ms a 48 kHz; cerca de 0,73 ms a 44,1 kHz), igual em todos os tipos e modos de sobreamostragem: a latência vem dos filtros de fase linear da sobreamostragem e trocar de modo não desloca o som. O motor compensa esse atraso nas outras faixas, barramentos e envios ([06e](06e-compensacao-de-latencia.md)), então duplicar uma faixa e distorcer só uma não põe as duas fora de fase `(testado só por testes automáticos)`; o que a compensação não cobre é a gravação do app.
- `Sobreamostragem` em `1×` aliasa audivelmente com drive alto em material agudo.
- `Bits`, `Reduzir taxa` e `Dither` só valem no tipo `Bitcrusher`; `Sobreamostragem` só vale nos outros cinco tipos (testado só por testes automáticos).

---

## 12. Filtro

> Filtro ressonante de 12 ou 24 dB por oitava, com drive, LFO (livre ou no andamento) e seguidor de envelope movendo o corte. Serve de varredura, de wobble, de wah e de passa-alta de transição.

### Editor

Só controles, em três grupos: `FILTRO` (`Tipo`, `Corte`, `Ressonância`, `Drive`, `Mistura`), `LFO` (`Tempo`, `Taxa`/`Nota`, `Profundidade`, `Onda`) e `ENVELOPE` (`Envelope`). Os controles do LFO (`Tempo`, `Taxa`, `Nota`, `Onda`) ficam apagados enquanto `Profundidade` é 0. `Taxa` só aparece com `Tempo` `Livre`; `Nota`, com `Andamento`.

### Parâmetros

| Controle (grupo) | O que faz | Valores / padrão |
|---|---|---|
| `Tipo` (`FILTRO`) | Modo do filtro. | `Passa-baixa 12`, `Passa-baixa 24`, `Passa-alta 12`, `Passa-alta 24`, `Passa-banda`, `Rejeita-faixa`. Padrão `Passa-baixa 24`. |
| `Corte` (`FILTRO`) | Frequência de corte (ou central, no passa-banda e no rejeita-faixa). | 20 Hz a 20 kHz, log. Padrão 1 kHz. |
| `Ressonância` (`FILTRO`) | Pico no corte. Vai de Q 0,71 (plano) a Q 30, em escala exponencial. Um limite interno segura o pico com sinal forte, como um filtro analógico saturando. | 0 a 100%. Padrão 20%. |
| `Drive` (`FILTRO`) | Saturação (tanh) **antes** do filtro, até +24 dB de entrada. Os primeiros 12% do botão fazem a passagem do limpo para o saturado; o volume é compensado. | 0 a 100%. Padrão 0%. |
| `Mistura` (`FILTRO`) | Seco/molhado (linear). | 0 a 100%. Padrão 100%. |
| `Tempo` (`LFO`) | LFO livre em Hz ou preso ao andamento. | `Livre`, `Andamento`. Padrão `Livre`. |
| `Taxa` (`LFO`) | Frequência do LFO (só `Livre`). | 0,02 Hz a 20 Hz, log. Padrão 1 Hz. |
| `Nota` (`LFO`) | Duração de um ciclo do LFO (só `Andamento`). | 12 figuras de `1/32` a `1/1`. Padrão `1/4`. |
| `Profundidade` (`LFO`) | Quantas oitavas o LFO move o corte (para cima e para baixo). 0 = LFO desligado. | 0 a 6 oitavas (mostrado como `oit`), linear. Padrão 0. |
| `Onda` (`LFO`) | Forma do LFO. `Aleatório` sorteia um valor novo a cada ciclo (com transição de 2 ms). | `Senoide`, `Triângulo`, `Serra`, `Quadrada`, `Aleatório`. Padrão `Senoide`. |
| `Envelope` (`ENVELOPE`) | Quantas oitavas a **força do sinal de entrada** move o corte: ataque de 2 ms, soltura de 100 ms. Positivo abre o filtro nos ataques; negativo fecha. O seguidor age mesmo com `Profundidade` em 0. | −6 a +6 oitavas (mostrado como `oit`), linear. Padrão 0. |

O corte efetivo é `Corte` + LFO × `Profundidade` + √(nível da entrada) × `Envelope`, em oitavas, limitado entre 10 Hz e 45% da taxa de amostragem.

### Presets

| Preset | Tipo | Corte | Ress. | Drive | Mistura | Tempo | Taxa / Nota | Prof. | Onda | Envelope | Caráter |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `Varredura lenta` | `Passa-baixa 24` | 700 Hz | 35% | 10% | 100% | `Livre` | 0,1 Hz | 3 oit | `Senoide` | 0 | Abre e fecha o brilho em 10 s por ciclo. |
| `Wobble 1/8` | `Passa-baixa 24` | 400 Hz | 55% | 30% | 100% | `Andamento` | `1/8` | 3,5 oit | `Senoide` | 0 | O wobble de baixo de dubstep, uma balançada por colcheia. |
| `Auto-wah` | `Passa-banda` | 500 Hz | 60% | 0% | 100% | · | · | 0 | · | +3,5 oit | O corte segue a dinâmica: cada nota "abre" o wah. |
| `Passa-alta de transição` | `Passa-alta 24` | 250 Hz | 25% | 0% | 100% | · | · | 0 | · | 0 | Ponto de partida para automatizar o `Corte` e tirar graves num *build-up*. |

### Dois usos típicos

1. **Baixo com wobble**: `Wobble 1/8` no baixo; troque a `Nota` para `1/4` ou `1/16` conforme o andamento.
2. **Transição para o refrão**: `Passa-alta de transição` na mistura ou num barramento, com o `Corte` automatizado de 250 Hz a 2 kHz nos quatro compassos que antecedem o refrão (ver [07 Automação](07-automacao.md)).

### Cuidados

- Sem latência.
- Ressonância alta com drive alto e sinal forte pode ficar estridente: reduza `Ressonância` ou `Drive`.
- Trocar o `Tipo` faz um crossfade de 20 ms entre os dois filtros, sem estalo.
- Com o LFO em `Andamento` e um projeto com mapa de andamento (faixa `Andamento`), a `Nota` usa só o andamento inicial: o balanço não acompanha saltos nem rampas (ver a nota no [Delay](#7-delay)).

---

## 13. Multibanda

> Compressor de 3 bandas (baixa, média e aguda) com cruzamentos ajustáveis: cada banda tem o próprio limiar, razão, tempos, joelho e ganho, e pode ser ouvida sozinha (`Solo`) ou deixada de fora da compressão (`Bypass`). Serve para segurar só os graves, ou só os agudos, sem apertar o resto; no `Master`, para uma cola leve.

### Como funciona

- O som se divide nos dois cruzamentos por filtros Linkwitz-Riley de 4ª ordem (24 dB por oitava). Sem compressão, a soma das três bandas tem a mesma resposta em frequência do som original (só a fase gira, sem atraso no tempo); nos testes o ganho de cada frequência fica a menos de 0,05 dB de zero `(testado só por testes automáticos)`.
- Cada banda tem o seu compressor: detector de **pico** que liga os dois canais (o mais forte manda e a imagem estéreo não desliza), com o mesmo cálculo de joelho e balística em dB do [`Compressor`](#2-compressor). Não há `Detector` `RMS`, `Mistura`, `Ganho automático` nem `Sidechain`.
- O `Ganho` da banda soma **sempre**, com ou sem compressão: `+6 dB` na banda média sobe a banda média em 6 dB. Não é ganho automático.

### Editor

Gráfico de 20 Hz a 20 kHz (escala logarítmica) dividido em três faixas coloridas, com o nome `BAIXA`, `MÉDIA` ou `AGUDA` no canto de cada uma, e os knobs à direita (no celular, o gráfico em cima, com 150 px de altura, e os knobs embaixo).

| O que se vê | Como se mexe | O que significa |
|---|---|---|
| Duas linhas verticais brancas | Arrastar **na horizontal** em qualquer ponto do gráfico move o cruzamento **mais perto de onde você tocou** (num passo só do desfazer por arraste). O cruzamento fica dentro da faixa do knob dele. | Frequência dos cruzamentos, escrita ao lado de cada linha embaixo (`150`, `3.0k`). |
| Uma linha horizontal em cada faixa | Só se muda pelo knob `Limiar`. | O `Limiar` da banda: 0 dB no topo, −60 dB embaixo. |
| Barra que desce do topo, com o número embaixo (`−10.6`) | Só leitura. | Redução de ganho ao vivo da banda, em escala de raiz até 24 dB. Só aparece com a banda comprimindo (mais de 0,05 dB) e com o efeito medido (ver [06c](06c-painel-de-efeitos.md#gráficos-do-multibanda-do-de-esser-e-da-imagem-estéreo)). |
| Faixa com fundo mais forte e contorno | Ligar `Solo` na banda. | Banda em solo. |
| Faixa cinza | Ligar `Bypass` na banda. | Banda fora da compressão. |

O medidor deste efeito é o próprio gráfico: o motor manda as reduções das três bandas juntas, empacotadas num só número (décimos de dB, até 25,5 dB por banda), e o app as separa. Na primeira prova de uso no Chrome (sessão de código, com o preset no `Pad`), o número da banda baixa marcou 0,6 dB e o da média, 10,6 dB `(não repetido por quem escreveu esta documentação)`.

### Parâmetros

Os knobs se agrupam em `CRUZAMENTO`, `SAÍDA` e um grupo por banda (`BAIXA`, `MÉDIA`, `AGUDA`, cada um com os mesmos oito controles).

| Controle (grupo) | O que faz | Valores / padrão |
|---|---|---|
| `Cruzamento baixo/médio` (`CRUZAMENTO`) | Frequência em que a banda baixa termina e a média começa. | 40 Hz a 800 Hz, log. Padrão 150 Hz. |
| `Cruzamento médio/agudo` (`CRUZAMENTO`) | Frequência em que a banda média termina e a aguda começa. | 1 kHz a 12 kHz, log. Padrão 3 kHz. |
| `Saída` (`SAÍDA`) | Ganho do efeito inteiro, depois de somar as bandas. | −24 a +24 dB, linear. Padrão 0 dB. |
| `Limiar` (por banda) | Nível a partir do qual a banda começa a ser comprimida. | −60 a 0 dB, linear. Padrão: baixa −24 dB, média −22 dB, aguda −20 dB. |
| `Razão` (por banda) | Quanto do excesso acima do limiar é cortado. | 1:1 a 20:1, log. Padrão 3,0:1 nas três. |
| `Ataque` (por banda) | Tempo para o ganho descer quando a banda passa do limiar. | 0,1 ms a 250 ms, log. Padrão: baixa 20 ms, média 10 ms, aguda 4 ms. |
| `Soltura` (por banda) | Tempo para o ganho voltar. | 5 ms a 3 s, log. Padrão: baixa 250 ms, média 150 ms, aguda 80 ms. |
| `Ganho` (por banda) | Ganho fixo da banda, depois da compressão (compensação manual ou realce da banda). | −12 a +24 dB, linear. Padrão 0 dB. |
| `Solo` (por banda) | Só as bandas em solo tocam; as outras somem da saída. Com mais de uma em solo, tocam as que estão em solo. | `Não`/`Sim`. Padrão `Não`. |
| `Bypass` (por banda) | A banda passa sem compressão **e sem o `Ganho`** dela. | `Não`/`Sim`. Padrão `Não`. |
| `Joelho` (por banda) | Largura da transição suave em volta do limiar; 0 = joelho duro. | 0 a 24 dB, linear. Padrão 6 dB. |

Com `Bypass` ligado numa banda, os outros seis controles dela ficam apagados (continuam mexíveis); `Solo` e `Bypass` não se apagam. O cruzamento médio/agudo fica sempre pelo menos 1,5 vez acima do baixo: nos extremos dos knobs (baixo perto de 800 Hz e médio/agudo perto de 1 kHz) o app aplica a mesma regra ao mover um cruzamento: o que você move para além do limite para em 1,5× (ou 1/1,5×) o outro, e o valor mostrado no knob e no gráfico é o efetivo (a imagem estéreo tem a mesma regra). Enquanto uma banda está em `Solo` o cartão ganha o selo `SOLO` e a janela de `Exportar` avisa que a exportação sairá assim `(testado só por testes automáticos)`. O id 3 do contrato de parâmetros do motor não é usado (reservado; o motor o ignora e o app não o mostra). Todos os controles são automatizáveis ([07 Automação](07-automacao.md)).

### Presets

Legenda das colunas de banda: `Limiar, Razão, Ataque, Soltura, Ganho, Joelho`. O que o preset não cita vale o padrão (`Solo` e `Bypass` em `Não`, `Saída` em 0 dB). O caráter vem dos valores, sem escuta `(não confirmado ao ouvido)`.

| Preset | Cruzamentos | Saída | Baixa | Média | Aguda | Caráter |
|---|---|---|---|---|---|---|
| `Bateria colada` | 120 Hz e 4 kHz | 0 dB | −20 dB, 3:1, 30 ms, 200 ms, +1 dB, 6 dB | −18 dB, 2,5:1, 20 ms, 120 ms, 0 dB, 6 dB | −22 dB, 2:1, 5 ms, 80 ms, +1 dB, 6 dB | Ataques lentos nos graves e nos médios deixam o golpe passar; compressão média nas três bandas e +1 dB nos extremos para o conjunto ficar mais cheio. Barramento de bateria. |
| `Mix de bus` | 150 Hz e 3,5 kHz | +1 dB | −16 dB, 2:1, 30 ms, 300 ms, 0 dB, 10 dB | −14 dB, 1,6:1, 20 ms, 200 ms, 0 dB, 10 dB | −18 dB, 1,8:1, 10 ms, 150 ms, 0 dB, 10 dB | Razões baixas, soltura longa e joelho largo: compressão leve e uniforme para uma mistura ou um grupo. |
| `Master suave` | 100 Hz e 5 kHz | 0 dB | −14 dB, 1,8:1, 40 ms, 400 ms, 0 dB, 12 dB | −12 dB, 1,4:1, 30 ms, 250 ms, 0 dB, 12 dB | −16 dB, 1,5:1, 15 ms, 200 ms, 0 dB, 12 dB | O mais brando dos quatro: razões de 1,4:1 a 1,8:1, joelho de 12 dB e tempos lentos. Para o `Master`, com poucos dB de redução. |
| `Controle de graves` | 180 Hz e 3 kHz | 0 dB | −26 dB, 5:1, 10 ms, 150 ms, 0 dB, 3 dB | −10 dB, 1,2:1, 10 ms, 150 ms, 0 dB, 6 dB | −30 dB, 3:1, 2 ms, 60 ms, 0 dB, 3 dB | Graves domados e agudos contidos, com o médio (onde mora a voz) quase intocado. |

### Dois usos típicos

1. **Cola leve no `Master`**: `Master suave` antes do `Limitador`; abaixe o `Limiar` das três bandas até o número embaixo de cada uma marcar de 1 a 2 dB de redução nos trechos fortes. Receita completa em [Efeitos em combinação, receita 7](../guias/efeitos-em-combinacao.md#receita-7-master-suave-com-multibanda).
2. **Segurar os graves de um baixo ou violão sem escurecer o resto**: preset `Controle de graves`; ligue o `Solo` na banda `BAIXA` para ouvi-la sozinha, arraste o cruzamento no gráfico até a banda pegar só a região que incomoda, e desligue o `Solo`.

### Cuidados

- **`Solo` é o som, não só a escuta**: com um `Solo` ligado as outras bandas somem da saída (com uma transição de poucos ms), inclusive na exportação. Confira que nenhum ficou ligado antes de exportar.
- Latência 0: não entra na compensação de latência ([06e](06e-compensacao-de-latencia.md)). Não tem `Sidechain`.
- Sem `Mistura`: para compressão paralela, use um envio para um barramento ([Efeitos em combinação, receita 2](../guias/efeitos-em-combinacao.md#receita-2-bateria-com-compressor-paralelo-em-barramento)).
- O medidor por banda só aparece no efeito que estiver sendo medido: um por vez, junto com o `Compressor`, o `Gate`, o `Limitador`, o `De-esser` e a `Imagem estéreo`. Toque no gráfico para passar a medida para ele.
- `Saída` e `Ganho` positivos podem somar bastante nível: confira o medidor do canal.

---

## 14. De-esser

> Doma a sibilância (o "s", o "x", o "ch") comprimindo só uma banda de detecção que você escolhe. Serve para uma voz que fica cortante depois do compressor e do EQ, ou para o chiado dos pratos; a `Frequência` se acha ouvindo a banda com `Ouvir banda`.

### Como funciona

- Um filtro passa-banda (`Frequência` e `Q`) separa a banda de detecção. O nível dela (pico dos dois canais) passa por um cálculo de compressão com `Limiar`, `Razão`, `Ataque` e `Soltura` e um joelho fixo de 2 dB.
- `Modo` `Banda dividida` (padrão): o ganho age **só na banda**; o resto do espectro passa intacto, e sem redução a saída é exatamente a entrada. `Banda larga`: o ganho age no **sinal inteiro** (o efeito vira um compressor com chave filtrada; o grave também abaixa quando o "s" estoura).
- `Ouvir banda` `Sim` troca a saída pela banda de detecção (sem a redução de ganho), para achar a frequência do "s" de quem canta. A troca é suavizada (5 ms), sem estalo.
- Sem `Sidechain`: o detector escuta a própria entrada. Latência 0.

### Editor

Gráfico à esquerda, medidor de redução ao lado e os knobs à direita (no celular, o gráfico e o medidor em cima, com 150 px de altura, e os knobs embaixo).

| O que | Como se mexe | Resultado |
|---|---|---|
| Curva da banda de detecção (eixo de 1 kHz a 20 kHz, log; 0 a −36 dB) | Arrastar (mouse ou dedo) em qualquer ponto: a posição **horizontal** vira a `Frequência` (o ponto tocado, limitado a 4 kHz a 10 kHz) e o movimento **vertical** muda o `Q` (para cima aumenta, para baixo diminui; `Shift` = fino). | A curva é o formato do passa-banda: `Q` maior = mais estreita. |
| Linha vertical branca | Só leitura. | A `Frequência` atual. |
| Legenda no canto superior direito | Só leitura. | Por exemplo `6.5k Hz  Q 1.5`. |
| Marcas 2k, 5k e 10k embaixo | Só leitura. | Referência do eixo. |
| Aviso `OUVINDO A BANDA` (canto superior esquerdo) | Aparece com `Ouvir banda` em `Sim`. | Lembrete de que a saída é só a banda. |
| Medidor à direita (marcas 1, 3, 6, 12 e 24 dB) | Só leitura. | Redução de ganho em dB, com o traço de pico (1,2 s, depois cai a 12 dB/s), como no [`Compressor`](#2-compressor): número `0.0`, `−4.5` ou `—`. |

O medidor é o mesmo das dinâmicas: um efeito por vez. Com este efeito medido o tooltip é `Redução de ganho agora (o traço segura o pico)`; senão, `O medidor mostra um efeito por vez: toque neste para medir` (também com o efeito em bypass).

### Parâmetros

| Controle (grupo) | O que faz | Valores / padrão |
|---|---|---|
| `Frequência` (`BANDA`) | Centro da banda de detecção. | 4 kHz a 10 kHz, log. Padrão 6,5 kHz. |
| `Q` (`BANDA`) | Estreiteza da banda. Maior = mais estreita e mais seletiva. | 0,5 a 4, log. Padrão 1,5. |
| `Limiar` (`COMPRESSÃO`) | Nível da banda a partir do qual a redução começa. | −60 a 0 dB, linear. Padrão −30 dB. |
| `Razão` (`COMPRESSÃO`) | Quanto do excesso é cortado. | 1:1 a 20:1, log. Padrão 5,0:1. |
| `Ataque` (`COMPRESSÃO`) | Tempo para o ganho descer. | 0,1 ms a 50 ms, log. Padrão 1 ms. |
| `Soltura` (`COMPRESSÃO`) | Tempo para o ganho voltar. | 5 ms a 500 ms, log. Padrão 50 ms. |
| `Modo` (`SAÍDA`) | Onde o ganho age. | `Banda dividida`, `Banda larga`. Padrão `Banda dividida`. |
| `Ouvir banda` (`SAÍDA`) | Ouve só a banda de detecção. | `Não`/`Sim`. Padrão `Não`. |

Todos são automatizáveis ([07 Automação](07-automacao.md)).

### Presets

Todos com `Ouvir banda` em `Não` e `Modo` `Banda dividida`, menos o `Banda larga`. O caráter vem dos valores, sem escuta `(não confirmado ao ouvido)`.

| Preset | Frequência | Q | Limiar | Razão | Ataque | Soltura | Modo | Caráter |
|---|---|---|---|---|---|---|---|---|
| `Voz suave` | 6,5 kHz | 1,5 | −32 dB | 4:1 | 1 ms | 50 ms | `Banda dividida` | O ponto de partida geral: limiar baixo e razão moderada, para tirar só a ponta do "s". |
| `Voz feminina` | 8 kHz | 1,8 | −30 dB | 5:1 | 1 ms | 40 ms | `Banda dividida` | Banda mais alta e mais estreita: a sibilância de vozes agudas mora acima. |
| `Voz masculina` | 5,5 kHz | 1,3 | −30 dB | 5:1 | 1 ms | 60 ms | `Banda dividida` | Banda mais baixa e mais larga, com soltura um pouco maior. |
| `Banda larga` | 7 kHz | 1 | −28 dB | 3:1 | 0,5 ms | 80 ms | `Banda larga` | Comprime o sinal todo quando o "s" estoura: pega pratos e chiado de uma vez, ao custo de abaixar o resto junto. |

### Dois usos típicos

1. **Voz sibilante**: no fim da cadeia vocal, antes do `Compressor` ([Efeitos em combinação, receita 8](../guias/efeitos-em-combinacao.md#receita-8-voz-com-de-esser-antes-do-compressor)): `Voz suave`; ligue `Ouvir banda`, ajuste a `Frequência` até ouvir só o chiado do "s", desligue, e abaixe o `Limiar` até o medidor marcar de 3 a 6 dB nas sibilantes.
2. **Pratos e chiado num barramento de bateria**: preset `Banda larga` com `Limiar` mais alto (−20 dB) para agir só nos picos.

### Cuidados

- Excesso vira ceceio: se a voz soar "sem o s", suba o `Limiar` ou baixe a `Razão`.
- `Ouvir banda` em `Sim` deixa a saída só com a banda, também na exportação; os presets o desligam.
- O `Q` alto e a `Frequência` errada fazem o efeito agir em pouca coisa: confira com o medidor e com `Ouvir banda`.
- Um `Limiar` acima do nível da banda não comprime nada; o efeito é então transparente (saída igual à entrada, no modo dividido).

---

## 15. Imagem estéreo

> Largura estéreo por 3 bandas (baixa, média e aguda), balanço, mono nos graves e um medidor de correlação de fase. Serve para abrir o topo de uma mistura sem abrir os graves, fechar o estéreo de um grave e conferir se o resultado ainda soa em mono.

### Como funciona

- O efeito trabalha em mid/side: o **centro** (`M = (L + R) / 2`) passa intacto e só o **lado** (`S = (L − R) / 2`) é mexido, banda a banda. Com o `Balanço` no centro, a soma esquerda + direita (o que uma caixa mono ouve) nunca muda `(testado só por testes automáticos)`.
- As bandas somam o lado exato: `100%` nas três é identidade (o som sai igual ao que entrou) e `0%` nas três dá esquerda = direita = centro (mono exato), sem o giro de fase de um divisor comum.
- `Mono nos graves` tira do lado o que fica abaixo de `Abaixo de`, **depois** das larguras. O `Balanço` vem por último e só abaixa o canal oposto, como o `Pan` do [`Utilitário`](#5-utilitário).
- Sem lado (som que já é mono: esquerda igual à direita) não há o que abrir: as larguras não mudam nada.

### Editor

Gráfico à esquerda e os knobs à direita (no celular, o gráfico em cima, com 150 px, e os knobs embaixo). O gráfico só mostra, não se arrasta (as larguras se mexem nos knobs).

| O que se vê | O que significa |
|---|---|
| Três trilhas `BAIXA`, `MÉDIA` e `AGUDA`, cada uma com o valor em % à direita | A `Largura` da banda. A linha no meio da trilha é 100% e a ponta direita é 200%. |
| Trilha `FASE` embaixo, com marca no meio | Correlação de fase da saída, de −1 a +1: barra para a direita (mono, +1) ou para a esquerda, na cor de alerta (vermelho-salmão; fases opostas, −1). Só aparece com o efeito medido (um por vez, ver [06c](06c-painel-de-efeitos.md#gráficos-do-multibanda-do-de-esser-e-da-imagem-estéreo)). |

A correlação é `Σ L·R / √(Σ L² · Σ R²)` da saída, com média móvel de constante 0,3 s: `1` é mono, `0` é sem relação entre os canais e `−1` é oposição de fase (o som some em mono). Em silêncio marca 0.

### Parâmetros

Grupos `CRUZAMENTOS`, `LARGURA`, `SAÍDA` e `MONO`.

| Controle (grupo) | O que faz | Valores / padrão |
|---|---|---|
| `Cruzamento baixo/médio` (`CRUZAMENTOS`) | Onde a banda baixa termina e a média começa. | 50 Hz a 1 kHz, log. Padrão 200 Hz. |
| `Cruzamento médio/agudo` (`CRUZAMENTOS`) | Onde a média termina e a aguda começa. | 1 kHz a 12 kHz, log. Padrão 4 kHz. |
| `Baixa` (`LARGURA`) | Largura do lado na banda baixa. 0% = mono, 100% = original, 200% = lado dobrado. | 0 a 200%, linear. Padrão 100%. |
| `Média` (`LARGURA`) | Idem, na banda média. | 0 a 200%, linear. Padrão 100%. |
| `Aguda` (`LARGURA`) | Idem, na banda aguda. | 0 a 200%, linear. Padrão 100%. |
| `Balanço` (`SAÍDA`) | Só abaixa o canal oposto: negativo abaixa a direita, positivo abaixa a esquerda (em `+1`, a esquerda some). Mostrado como número. | −1 a +1, linear. Padrão 0. |
| `Mono nos graves` (`MONO`) | Tira o lado abaixo da frequência de `Abaixo de`. | `Não`/`Sim`. Padrão `Não`. |
| `Abaixo de` (`MONO`) | Frequência do mono nos graves. Apagado com `Mono nos graves` em `Não`. | 40 Hz a 500 Hz, log. Padrão 120 Hz. |

O cruzamento médio/agudo fica sempre pelo menos 1,5 vez acima do baixo (com o baixo em 1 kHz e o outro em 1 kHz, o motor usa 1,5 kHz). Todos os controles são automatizáveis ([07 Automação](07-automacao.md)).

### Presets

O caráter vem dos valores, sem escuta `(não confirmado ao ouvido)`. `Balanço` fica em 0 em todos.

| Preset | Cruzamentos | Baixa / Média / Aguda | Mono nos graves | Caráter |
|---|---|---|---|---|
| `Mix de bus` | 200 Hz e 4 kHz | 80% / 110% / 125% | `Sim`, abaixo de 120 Hz | Abre um pouco o topo, fecha um pouco os graves e deixa o subgrave em mono. Para uma mistura ou um grupo. |
| `Graves em mono` | 150 Hz e 4 kHz | 0% / 100% / 100% | `Sim`, abaixo de 150 Hz | Só arruma os graves: mono abaixo de 150 Hz, o resto como entrou. |
| `Largo` | 250 Hz e 3 kHz | 60% / 140% / 170% | `Sim`, abaixo de 100 Hz | Estéreo bem aberto nos médios e nos agudos, com os graves quase fechados. Confira em mono. |
| `Quase mono` | 200 Hz e 4 kHz | 0% / 40% / 60% | `Não` (120 Hz apagado) | Fecha o estéreo: graves em mono e o resto com 40% e 60% do lado. |

### Dois usos típicos

1. **Graves em mono na mistura**: `Graves em mono` no `Master` ou num barramento; o subgrave fica no centro (bom para caixa mono e para vinil) e o resto não muda. Receita em [Efeitos em combinação, receita 9](../guias/efeitos-em-combinacao.md#receita-9-graves-em-mono-com-imagem-estéreo).
2. **Abrir um pad sem embolar**: `Largo` no pad, com a `Aguda` em 150% a 170%; confira com o medidor `FASE` que a correlação não vai a valores negativos.

### Cuidados

- Larguras acima de 100% dobram o lado e podem tirar o som do centro em mono: olhe a trilha `FASE` (perto de −1 é perigo).
- O `Balanço` muda a soma esquerda + direita: quando o `Balanço` não é 0, a garantia de mono do primeiro item não vale.
- Sem latência ([06e](06e-compensacao-de-latencia.md)).
- O medidor de fase é da **saída deste efeito**, não da mistura final.

---

## Latência e custo de cada efeito

Os efeitos processam bloco a bloco, sem alocar nem travar no meio do áudio. Alguns atrasam o som:

| Efeito | Latência | Quando importa |
|---|---|---|
| `Limitador` | Igual ao `Lookahead`: padrão 3 ms (144 quadros a 48 kHz), até 10 ms (480 quadros). Zero com `Lookahead` 0. | O motor alinha as faixas sozinho (compensação de latência, abaixo); o projeto inteiro sai esse tanto depois do cursor. |
| `Distorção` | 32 quadros fixos: 0,67 ms a 48 kHz, cerca de 0,73 ms a 44,1 kHz. Nos seis tipos e nas três sobreamostragens. | Compensada como as demais: duplicar uma faixa e distorcer só uma não põe as duas fora de fase. |
| Todos os outros | 0 (o pré-atraso do reverb, o atraso do delay e do chorus fazem parte do som, não são latência). Inclui o `Multibanda`, o `De-esser` e a `Imagem estéreo`: os cruzamentos Linkwitz-Riley e os filtros deles não atrasam o som no tempo (só giram a fase), e o teste do motor confere `latency() == 0` `(testado só por testes automáticos)`. | Não entram na compensação de latência: [06e](06e-compensacao-de-latencia.md). |

**Compensação de latência (PDC).** Capítulo próprio: [06e](06e-compensacao-de-latencia.md). O motor soma a latência de cada efeito nas faixas e nos barramentos e atrasa o resto para que tudo chegue junto ao master: uma faixa com `Limitador` não soa mais atrasada em relação às outras, e um envio para um barramento com efeito de latência não faz filtro de pente com a saída direta da mesma faixa. Vale também para o sidechain (a chave chega alinhada com o som). Ligar e desligar o bypass não muda o alinhamento nem estala, porque a latência do efeito conta ligado ou não.

- **Quanto:** a latência do projeto é a maior soma que existe de um lado a outro (uma faixa com `Limitador` de 3 ms: 3 ms para todas). Cada efeito e o total ficam limitados a 1 s. Em números inteiros de quadros: 3 ms a 48 kHz são exatamente 144 quadros; a 44,1 kHz, 132.
- **Exportar** descarta essa latência no começo: o arquivo sai alinhado com a linha do tempo, tanto a mixagem quanto cada stem.
- **Ao vivo** o som sai esse tanto depois do cursor (uns poucos ms). Trocar o tipo de um efeito, mudar o `Lookahead` ou mexer no roteamento com o som tocando refaz a compensação com um crossfade de 10 ms.
- **Gravação e metrônomo:** a gravação do app soma a latência do motor (esta compensação, mais a cadeia do `Master` e o limitador de segurança) à do aparelho, no áudio e nas notas MIDI, sem você somar nada à `Compensação de latência` ([06e](06e-compensacao-de-latencia.md#gravar-por-cima-de-um-projeto-com-efeitos-de-latência)); o clique do metrônomo é atrasado da mesma latência e soa junto das faixas.
- **Limites:** o volume automatizado age uns ms adiantado em relação ao som de uma faixa com efeito de latência; automatizar o `Lookahead` refaz a conta com até 20 ms de atraso. Nada disto foi ouvido no navegador `(testado só por testes automáticos)`.

Custo de CPU não foi medido para este manual. Por construção, o `Reverb` (rede de 8 linhas com difusores e reflexões) e a `Distorção` em `4×` (processa a taxa quadruplicada) fazem mais conta que os demais. Um efeito em bypass assentado não processa nada (o motor o pula).

---

## O sidechain: o que ele exige

O `Compressor` e o `Gate` têm o seletor `Sidechain` no grupo `CHAVE`. Em vez de escutar a própria entrada para decidir quando agir, escutam a saída de **outra faixa**, e agem sobre o áudio da faixa onde estão.

O que o sidechain exige e como se comporta:

1. **Uma faixa-chave que exista** e seja outra faixa (a lista do seletor tem `Própria entrada` e as demais pelo nome, incluindo barramentos; a própria faixa não aparece). Pode ser usado também nos efeitos do `Master`.
2. **A chave é a saída da faixa depois dos efeitos dela e antes do fader.** Volume, pan e mudo da faixa-chave não mudam a chave (pelo código; o efeito de silenciar o bumbo e ainda assim ver o bombeio não foi confirmado ouvindo, `(não confirmado)`).
3. **Uma faixa inteira é a chave.** Se o bumbo e o resto da bateria estão na mesma faixa (a `Bateria` é um instrumento só, com as 12 peças dentro), todas as peças disparam o efeito. Ponha o bumbo numa faixa própria.
4. **Ordem de processamento.** Faixas normais são processadas na ordem que resolve as chaves, então a chave é do mesmo bloco. Um **barramento** como chave chega com um bloco de atraso (128 quadros, cerca de 2,7 ms a 48 kHz), e duas faixas que se usam como chave uma da outra fazem uma delas usar o bloco anterior.
5. **O `Passa-alta` da chave** (nos dois efeitos) filtra só o que o detector escuta, nunca o áudio. Com chave de bumbo, deixe em 20 Hz para o grave chegar ao detector.
6. **O `Sidechain` não é automatizável** e nenhum preset o altera.
7. **Faixa-chave apagada:** o seletor mostra `Faixa N (removida)` e o efeito passa a escutar a própria entrada. Reordenar ou apagar outras faixas atualiza o número sozinho.
8. **Sem escuta da chave:** não há botão para ouvir o sinal do detector.
9. **Faixa-chave calada:** com a chave em silêncio, o compressor não comprime e o gate fica fechado.
10. **Só os dois têm sidechain.** O `Multibanda` e o `De-esser` detectam a própria entrada e não têm o seletor `Sidechain`.

## Inconsistências notadas ao ler o código

Estas não impedem o uso, mas você pode esbarrar nelas:

- **Limite de 16 efeitos por cadeia**: o app desabilita o botão de adicionar quando a cadeia chega a 16 (ver [06c](06c-painel-de-efeitos.md#limites-e-pegadinhas)).

## Combina com

- [06c Painel de efeitos](06c-painel-de-efeitos.md): como adicionar, ordenar, ligar/desligar e mexer nos controles.
- [06 Mixer](06-mixer.md): envios e barramentos, onde `Reverb` e `Delay` costumam morar; ordem dos inserts.
- [06b Analisador e medidores](06b-analisador-e-medidores.md): ouvir com os olhos o que o EQ e a distorção fizeram.
- [07 Automação](07-automacao.md): automatizar `Corte`, `Mistura`, `Limiar` e os demais parâmetros.
- [06e Compensação de latência](06e-compensacao-de-latencia.md): como o motor alinha as faixas quando o `Limitador` ou a `Distorção` atrasam o som.
- [Efeitos em combinação](../guias/efeitos-em-combinacao.md): receitas com valores concretos, incluindo o master suave com `Multibanda`, a voz com `De-esser` e os graves em mono com `Imagem estéreo`.

## Limites e pegadinhas

- Preset **substitui todos** os valores; ele não é aditivo. Para guardar um ajuste seu, não reaplique o preset.
- Os presets são pontos de partida (o código chama de "pontos de partida pensados para o uso comum, não receitas"): ajuste o `Limiar`, o `Corte` e a `Mistura` ao seu material.
- Web e Android usam o mesmo motor Rust (WASM na web, nativo no Android): os efeitos soam iguais.
- Tudo é salvo com o projeto (tipo, parâmetros, ordem, bypass). O nome de preset "editado" não.
- **`Multibanda`, `De-esser` e `Imagem estéreo` pedem o motor e o app da fase 15.** Um `engine.wasm` (ou APK) antigo não conhece os tipos 13 a 15: o slot fica sem efeito e o som passa como se ele não existisse. Um app antigo que abre um projeto com esses efeitos descarta os slots ao abrir (o tipo salvo não existe naquela versão), e ao salvar de novo eles se perdem `(não confirmado: lido no código, sem teste)`.

## Atalhos

Os atalhos do rack (abrir com `F`, desfazer com `Ctrl`/`Cmd` + `Z`, `Shift` para ajuste fino) estão em [06c, Atalhos](06c-painel-de-efeitos.md#atalhos).
