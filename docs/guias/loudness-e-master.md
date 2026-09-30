# Loudness e master

> Levar uma música mixada até um master competitivo e seguro (no volume que a plataforma espera, sem estourar) e conferir o número no arquivo entregue; cerca de 20 a 30 minutos, com o mix já pronto.

## Ingredientes

| Recurso | Para quê aqui | Capítulo |
|---|---|---|
| Faders e medidores das faixas | Deixar folga (headroom) antes do master | [06 Mixer](../manual/06-mixer.md), [06b Analisador e medidores](../manual/06b-analisador-e-medidores.md) |
| Cadeia de efeitos do `Master` (`EQ`, `Compressor`, `Limitador`) | Dar volume sem estourar | [06c Painel de efeitos](../manual/06c-painel-de-efeitos.md), [06d Referência dos efeitos](../manual/06d-efeitos-referencia.md) |
| Limitador de segurança do master (−0,3 dBFS, sempre ligado) | Última rede: nada passa de −0,3 dBFS | [06 Mixer](../manual/06-mixer.md) |
| Leitura de loudness do master (`M`, `S`, `I`, `TP`, `Zerar`) | Saber o volume percebido e o pico verdadeiro | [06b Analisador e medidores](../manual/06b-analisador-e-medidores.md) |
| `Normalizar o loudness` na exportação | Levar o arquivo exatamente ao alvo, com teto de true peak | [08 Exportação](../manual/08-exportacao.md) |

Os números daqui são pontos de partida musicais, não regras do programa: ajuste de ouvido. As políticas das plataformas mudam; confira a atual do serviço onde vai publicar. O que depende do programa (rótulos, faixas de valor, o cálculo do loudness) vem do código.

Duas medidas, para não confundir:

- **LUFS (`I`)**: o volume percebido. Quanto mais alto o número (mais perto de 0), mais alta a música.
- **True peak (`TP`, dBTP)**: o pico verdadeiro, com o que o sinal faz entre uma amostra e outra. Fica em vermelho acima de −1 dBTP.

## Passo a passo

### 1. Nível de cada faixa: deixe folga

O master só consegue dar volume com qualidade se a soma chegar a ele sem estar já no limite.

1. Ajuste os faders como no guia [Mixagem e automação](mixagem-e-automacao.md): bumbo e baixo com pico por volta de −12 a −10 dB nas barras, o resto por cima.
2. Deixe o fader do `Master` em **0 dB** e mantenha ele lá. Não use o fader do master para ganhar volume: ele vem **antes** do limitador de segurança, então subir o fader só empurra o som contra o −0,3 dBFS e achata.
3. Confira com a música tocando no trecho mais forte: o pico do `Master` deve ficar entre −12 e −6 dB nas barras. Se passar disso, baixe as faixas mais altas.

### 2. Medir o ponto de partida

1. Abra o mixer (`X`). No canal `Master`, toque em `Zerar`.
2. Toque a música do começo ao fim, sem parar, com o metrônomo desligado (o clique entra na medida ao vivo).
3. Anote o `I` e o `TP`. Um mix sem masterização costuma dar `I` entre −22 e −16 LUFS, com `TP` entre −8 e −2 dBTP.

Exemplo que usaremos: `I` = **−17,5 LUFS** e `TP` = **−4,0 dBTP**. O alvo será streaming, **−14 LUFS**, então faltam 3,5 dB.

### 3. Ganhar volume com o `Limitador` no master (não com o fader)

Se você normalizasse agora, o app aplicaria +3,5 dB e o `TP` iria a −0,5 dBTP, passando do teto de −1 dBTP: o ganho pararia em +3,0 dB e o arquivo sairia em −14,5 LUFS, com aviso. Para chegar ao alvo, aumente o volume percebido **sem** aumentar o pico: é o trabalho do limitador.

1. No canal `Master`, toque em `Efeito` e adicione, nesta ordem (a ordem de cima para baixo é a do sinal): `EQ` (só se precisar), `Compressor` e, por último, `Limitador`.
2. `Compressor`: `Limiar` de modo que o medidor de redução do cartão marque 2 a 3 dB nos picos, `Razão` 2:1 a 3:1, `Ataque` 30 ms, `Soltura` 200 ms. É cola, não volume.
3. `Limitador`: abra `Presets e mais` e escolha `Master −1 dB` (`Ganho` +3 dB, `Teto` −1 dB, `Soltura` 80 ms, `Lookahead` 5 ms, `Ligação estéreo` 100%). Depois baixe o `Teto` para **−1,5 dB**: o limitador trabalha com o pico de amostra, e o true peak pode ficar uns 0,5 dB acima dele.
4. Suba o `Ganho` do `Limitador` em passos de 0,5 dB. Ouça e olhe o medidor de redução do cartão dele: **2 a 4 dB nos picos** é o ponto de equilíbrio; mais de 6 dB de redução constante já achata bumbo e caixa.
5. A cada mudança de `Ganho`, toque em `Zerar` no `Master`, toque o trecho mais forte e leia o `I` e o `TP`.

Alvo desta etapa: `I` entre **−15 e −14 LUFS** e `TP` abaixo de **−1,0 dBTP**. A exportação fecha o último décimo de dB.

### 4. Ler `M`, `S`, `I` e `TP` juntos

| Leitura | O que olhar | Sinal de problema |
|---|---|---|
| `M` (400 ms) | Sobe e desce com as batidas e as frases | `M` colado no `I` o tempo todo: música sem dinâmica |
| `S` (3 s) | O nível de cada parte (estrofe, refrão) | Uma parte muito acima das outras: ela decide o `I` e as demais ficam baixas quando a música é normalizada |
| `I` (negrito) | O número que se compara com o alvo; só vale depois de tocar tudo | Muda a cada passada sem você mexer: esqueceu o `Zerar`, ou o metrônomo está ligado |
| `TP` | O maior pico verdadeiro desde o `Zerar` | Vermelho (acima de −1 dBTP) |

**Regra de bolso da folga.** Para o arquivo chegar ao alvo só com ganho, a diferença `TP − I` da mixagem precisa ser de no máximo `−1 − alvo` dB (com o teto de −1 dBTP): **13 dB** para −14 LUFS, **15 dB** para −16 LUFS e **22 dB** para −23 LUFS. No exemplo, `TP − I` era 13,5 dB (−4,0 − (−17,5)), meio dB acima do limite, por isso o ganho puro não chegava. Um limitador no master encurta essa diferença: ele derruba os picos e deixa o `I` subir.

### 5. Escolher o alvo por plataforma

| Destino | Alvo no app | Teto de true peak | Observação |
|---|---|---|---|
| Música em Spotify, YouTube, Tidal e afins | **Streaming −14,0** | −1,0 dBTP | O app agrupa Spotify, YouTube e Apple Music neste alvo. Serviços recodificam para MP3/AAC/Opus: por isso o teto de −1 dBTP |
| Podcast, vídeo para celular, redes sociais | **Podcast −16,0** | −1,0 dBTP | Voz com pouca dinâmica de pico; costuma ser fácil de atingir |
| Rádio e TV (EBU R128) | **Broadcast −23,0** | −1,0 dBTP | A norma tolera ±0,5 LU. O app mede o arquivo final e mostra quanto ficou |
| Mais alto que o streaming (club, masters "quentes") | **Personalizado** −10 a −9 | −1,0 dBTP (ou −0,5) | Precisa de limitador forte; a diferença `TP − I` cabe em só 8 a 9 dB. Serviços de streaming vão abaixar de volta para o alvo deles |

Comprar mais volume que o alvo da plataforma não rende: os serviços baixam o que passa do alvo, e a música fica com menos dinâmica sem ficar mais alta.

### 6. Exportar normalizado e conferir o LUFS final

1. Toque em **Exportar** (barra do transporte).
2. Ligue **Normalizar o loudness** (o **Normalizar** de pico desliga sozinho). Escolha o chip do alvo (por exemplo, **Streaming −14,0**). Deixe o **Teto de true peak** em **−1,0 dBTP**.
3. **WAV 24 bits**, **Cauda** em 2 s (4 a 6 s se há reverb longo). Se for levar os stems para outro programa mantendo o equilíbrio, ligue **Stems** e **Stems com o mesmo ganho**.
4. **Exportar.** Perto do fim a barra mostra `Medindo o loudness…`.
5. Na janela **Exportação concluída**, leia a frase e confira:
   - `A mixagem subiu 0,4 dB até o alvo e mediu −14,0 LUFS · −1,6 dBTP.` (sem aviso): chegou. É o `I` do arquivo, medido de novo depois do ganho.
   - `A mixagem já estava no alvo e mediu −14,0 LUFS · −3,0 dBTP.` (sem aviso): o ganho ficou abaixo de 0,05 dB, ou seja, a mixagem já saía no alvo e o arquivo não mudou de volume.
   - `... abaixo dos −14,0 LUFS pedidos: o teto de −1,0 dBTP não deixou subir mais sem estourar.` (em aviso): o arquivo saiu mais baixo que o alvo. Volte ao passo 3, aumente o `Ganho` do `Limitador` e exporte de novo.

**Conferir por outro caminho (opcional).** Importe o WAV exportado num projeto novo, desligue o metrônomo, toque `Zerar` no `Master` e toque o arquivo inteiro: o `I` do mixer deve ficar dentro de uns 0,2 LU do número da janela do resultado `(não confirmado em uso: pela leitura do código, o motor e a exportação usam o mesmo cálculo)`.

## Variações

- **Podcast a −16 LUFS.** Corte de graves na voz (`EQ` com o preset `Corte de graves`, passa-alta em 80 Hz), `Compressor` com 3 a 4 dB de redução, `Limitador` com `Teto` −1,5 dB e `Ganho` até o `I` chegar perto de −16. Exporte com o chip **Podcast −16,0**.
- **Rádio e TV a −23 LUFS.** Quase sempre é só descer: uma mixagem em −18 LUFS desce 5 dB e o true peak cai junto. Sem `Limitador` no master, ou com o `Ganho` em 0 dB. Exporte com o chip **Broadcast −23,0**; o aviso do teto não aparece porque o ganho é negativo.
- **Alvo livre.** No chip **Personalizado** o controle **Alvo** vai de −40 a 0 LUFS em passos de 0,5. Use para plataformas com política própria ou para masters de referência (por exemplo, −12,0).
- **Só medir, sem normalizar.** Deixe **Normalizar o loudness** desligado e use só as leituras do mixer (`Zerar`, tocar tudo, ler `I` e `TP`).
- **Vários alvos do mesmo mix.** Exporte duas vezes com alvos diferentes (a janela guarda as últimas escolhas). O nome do arquivo é sempre `<nome do projeto>.wav`, então renomeie ou mova o primeiro antes de exportar o segundo.

## Por que funciona

- O ouvido sente o **volume percebido** (LUFS), não o pico. Duas músicas com o mesmo pico soam muito diferentes; com o mesmo `I`, soam igualmente altas. Por isso os serviços normalizam por LUFS.
- **O ganho da exportação é só multiplicação.** Ele não comprime nem limita: mantém a dinâmica que você deixou. Se a música já está no `I` certo, o ganho é quase zero (abaixo de 0,05 dB a frase do resultado diz `já estava no alvo`); se falta volume, o ganho até o alvo esbarra no teto de true peak, e o volume precisa vir de um limitador **antes** do arquivo.
- **O teto de true peak é a segurança da recodificação.** MP3, AAC e Opus recriam o sinal e podem passar do pico de amostra em 0,5 a 1 dB; −1 dBTP dá a folga.
- **O limitador de segurança (−0,3 dBFS) não é o master.** Ele só evita corte duro. Quem dá volume com qualidade é o efeito `Limitador` que você escolhe, com `Teto` abaixo dele.
- **Medir a música toda.** O `I` tem dois filtros de silêncio (−70 LUFS e 10 LU abaixo da média), então pausas e introduções muito baixas não puxam o número; mas trechos parciais dão `I` parcial.

## Se der errado

| Sintoma | Causa provável | O que fazer |
|---|---|---|
| Leituras `M`, `S`, `I`, `TP` em `—` | Menos de 400 ms de som; ou o motor é anterior ao commit `357b6fc` (o medidor só existe no `engine.wasm` e nos `.so` recompilados nele) | Toque a música por alguns segundos; se continuar `—` e `Zerar` não fizer nada, atualize o app e o motor ([dev 02](../dev/02-pontes-web-e-android.md)). A exportação normalizada não depende disso |
| `TP` vermelho o tempo todo | Pico verdadeiro acima de −1 dBTP | Baixe o `Teto` do `Limitador` do master para −1,5 dB; `Zerar` e meça de novo |
| O `I` do mixer muda a cada passada | Esqueceu o `Zerar`, ou o metrônomo/monitoramento está entrando na medida | `Zerar`, desligue o metrônomo, toque tudo de uma vez |
| Exportação sai abaixo do alvo, em aviso | O teto de true peak segurou o ganho (`TP − I` da mixagem maior que 13 dB para −14 LUFS) | Mais `Ganho` no `Limitador` do master, ou aceite o resultado; baixar o **Teto de true peak** só piora |
| `Não deu para medir o loudness` | Mixagem com menos de 400 ms, silêncio, ou toda abaixo de −70 LUFS (típico em **Região do loop** muito curta) | Exporte um trecho maior, ou confira se as faixas não estão mudas; a mixagem saiu sem normalizar |
| O `I` da exportação difere do mixer em 0,5 LU ou mais | O mixer mediu com o metrônomo, com o monitoramento, ou uma passada incompleta | Confie no número da janela do resultado: mede só o arquivo |
| Stems cortados (24 bits) depois de **Stems com o mesmo ganho** | O teto de true peak vale para a mixagem, não para os stems | Exporte os stems em **WAV 32 bits float**, ou desligue **Stems com o mesmo ganho** |
| Som achatado, sem golpe | `Limitador` com redução constante maior que 6 dB, ou fader do master subido | Baixe o `Ganho` do `Limitador`, volte o master a 0 dB, e aceite um `I` uns 1 a 2 LU mais baixo |
