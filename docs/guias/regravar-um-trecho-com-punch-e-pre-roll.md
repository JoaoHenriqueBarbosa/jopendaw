# Regravar um trecho com punch e pré-roll

> Consertar uma frase de voz sem cantar a música toda (punch in/out), gravar um solo entrando no groove sem contagem (pré-roll), achar o andamento batendo no ritmo (tap tempo) e ajustar um metrônomo com timbre e subdivisões; cerca de 20 minutos para os três cenários.

Tudo abaixo supõe compasso de 4 tempos, uma faixa de áudio `Voz` já gravada e a entrada de áudio configurada ([Gravar uma banda e mixar](gravar-uma-banda-e-mixar.md), passos 2 e 3). Os números de tempo são contas de andamento, não medidas de uso. A gravação com punch e pré-roll, o som dos timbres e o tap tempo vieram do código e de testes automáticos: **nada foi visto ou ouvido rodando** `(testado só por testes automáticos; não visto rodando)`.

## Ingredientes

| Recurso | Para quê aqui | Capítulo |
|---|---|---|
| `Punch (P)`, pontas `IN` e `OUT` na régua, `Configurações` › `Punch in/out` e `Usar a região do loop` | Limitar a gravação a uma região | [03c Gravação](../manual/03c-gravacao.md#punch-inout), [02b Régua](../manual/02b-timeline-e-clipes.md#régua) |
| `Pré-roll` (setinha do gravar ou `Configurações`) | A música toca de 1 a 4 compassos antes de você entrar | [03c Pré-roll](../manual/03c-gravacao.md#pré-roll) |
| `Contagem de um compasso` | Cliques antes de gravar; independente do pré-roll | [03c Gravação](../manual/03c-gravacao.md), [02 Transporte](../manual/02-transporte.md) |
| Janela `Andamento e compasso`, botão `Tap tempo`, atalho `T` | Achar o BPM batendo | [02 Transporte](../manual/02-transporte.md#janela-andamento-e-compasso) |
| `Configurações` › `METRÔNOMO` | Timbre, subdivisão, acento, volumes e `Só ao gravar` | [09 Configurações](../manual/09-configuracoes-atalhos-android.md), [03c Metrônomo](../manual/03c-gravacao.md#metrônomo) |
| Fades do clipe de áudio | Suavizar uma emenda seca | [03 Áudio e clipes](../manual/03-audio-e-clipes.md) |

## Passo a passo

### Cenário 1. Consertar uma frase de voz (punch in/out)

Projeto a **100 BPM** em 4/4: um compasso = 4 × 60 ÷ 100 = **2,4 s**. A faixa `Voz` tem um clipe `Gravação 1.wav` de `1.1.1` a `17.1.1` (38,4 s). A frase que saiu ruim está nos compassos 5 e 6: de `5.1.1` a `7.1.1`, batidas 16 a 24, de **9,6 s a 14,4 s**.

1. Arme a `Voz` (`Armar para gravar`) e ligue `Monitorar a entrada` no mixer (fones!). Confira a entrada em `Configurações`.
2. Ponha o cursor no começo da frase: clique na régua perto do compasso 5. Com a grade em `1/4` (padrão) o cursor cai na batida mais próxima; confirme `5.1.1` na caixa de posição.
3. Aperte `P` (ou o botão `Punch (P)`, duas setas opostas, depois da setinha do gravar). Sem loop ligado, a região nasce com **dois compassos** a partir do cursor: `5.1.1` a `7.1.1`. Abra `Configurações`: `Punch in/out` está ligado e a legenda diz `Da posição 5.1.1 à 7.1.1: só isso é gravado`. Na régua aparece a faixa vermelha com as pontas `IN` e `OUT`; se a frase for outra, arraste as pontas (encaixe da grade, `1/4` por padrão).
4. Na setinha do gravar, em `Pré-roll`, escolha `2 compassos` (4,8 s). Deixe `Contagem de um compasso` marcada. O tooltip do gravar passa a `Gravar (R) na faixa armada, com um compasso de contagem, 2 de pré-roll, só na região de punch`.
5. Aperte `R`. A gravação parte 3 compassos antes do punch in (contagem + pré-roll), em `2.1.1` (batida 4, 2,4 s):

| Tempo | Posição | O que acontece |
|---|---|---|
| 2,4 s a 4,8 s | `2.1.1` a `3.1.1` | Contagem: o botão pisca, selo `Contando…` (o arranjo já toca por baixo) |
| 4,8 s a 9,6 s | `3.1.1` a `5.1.1` | Pré-roll: você ouve os compassos 3 e 4 e se prepara |
| 9,6 s a 14,4 s | `5.1.1` a `7.1.1` | A região: cante a frase |

6. Continue depois do punch out se quiser (o app **não** para sozinho ali); pare com `R`, `Espaço` ou `Enter` (por exemplo em 16,8 s, `8.1.1`). Aparece `Salvando a gravação…`.
7. Resultado na faixa: o clipe antigo de 0 a 9,6 s fica como estava; nasce um clipe novo de 9,6 s a 14,4 s (4,8 s); e o clipe antigo de 14,4 s a 38,4 s passa a começar 7 ms antes (14,393 s), com fade de entrada de 7 ms; o clipe novo termina com fade de saída de 7 ms. O cursor volta a `5.1.1`. Aperte `Espaço` e ouça as duas emendas.
8. Se o começo da frase nova estalar, selecione o clipe novo e arraste a alça de fade de entrada até uns 5 a 10 ms: com pré-roll a gravação começa exatamente no punch in, e nessa borda não há fade nem crossfade (o de 7 ms só existe onde havia áudio gravado além da região).
9. Não gostou? `Ctrl+Z` desfaz a gravação inteira e a frase antiga volta. A região continua marcada: aperte `R` de novo.
10. Terminou: desligue o punch (`P`), senão o próximo `R` continua limitado à região.

Nota sobre a contagem: com `Contagem de um compasso` ligada e o metrônomo desligado, os cliques da contagem também soam durante o pré-roll (o metrônomo provisório só é desligado meio tempo antes do ponto de gravar). Se preferir só a música, desmarque a contagem: o pré-roll já basta. `(lido do código; não visto rodando)`

### Cenário 2. Gravar um solo com pré-roll e sem contagem

Uma faixa de áudio `Solo` (guitarra pela interface) numa música a **120 BPM** (compasso = 2 s). O solo entra no compasso 9 (`9.1.1`, 16 s).

1. Na setinha do gravar, **desmarque** `Contagem de um compasso` e escolha `4 compassos` em `Pré-roll` (8 s). Confira que o punch está desligado (o botão `Punch (P)` sem destaque).
2. Ponha o cursor em `9.1.1` (compasso 9) e arme a faixa `Solo`. O tooltip do gravar diz `Gravar (R) na faixa armada, 4 de pré-roll`.
3. `R`. O transporte parte do compasso 5 (`5.1.1`, 8 s): você ouve 4 compassos de música, sem cliques, e entra no groove; a gravação vale a partir de `9.1.1`. O clipe nasce em `9.1.1` (`Gravação N.wav`); o pré-roll não vai para o arquivo.
4. Para ter o clique só enquanto grava (sem deixar o metrônomo tocando o tempo todo), ligue o metrônomo (`C`) e, em `Configurações` › `METRÔNOMO`, ponha `Quando soa` em `Só ao gravar`: o clique soa no pré-roll e na gravação, e cala parado. Use fones, senão o clique vaza para o microfone.
5. Pare com `R`. O cursor volta a `9.1.1`.

Perto do começo da música o pré-roll encolhe: com o cursor em `3.1.1` (compasso 3), `4 compassos` de pré-roll dão só 2 compassos (até o zero). E se o fim do loop (ligado) cai dentro do pré-roll, ele é ignorado.

### Cenário 3. Achar o andamento batendo e afinar um metrônomo com subdivisões

**Tap tempo.**
1. Toque em `120 BPM · 4/4` (janela `Andamento e compasso`) e depois em `Tap tempo` no ritmo da música, umas 8 vezes. A primeira batida só arma; da segunda em diante o campo `BPM` mostra a média das últimas 8 batidas com uma casa decimal:

| Intervalo médio entre as batidas | BPM no campo |
|---|---|
| 0,50 s | `120` |
| 0,60 s | `100` |
| 0,65 s | `92,3` |
| 0,75 s | `80` |

2. Toque em `Salvar`. Ou, sem abrir a janela, aperte `T` no ritmo: o botão do andamento mostra `Tap · 92,3 BPM` e, 1,5 s depois da última batida, o andamento entra no projeto (`Andamento: 92,3 BPM (tap).`). `Ctrl+Z` desfaz. Para andamentos abaixo de uns 40 BPM use o botão da janela (com `T` o prazo de 1,5 s vence entre as batidas).
3. Ajustar o andamento **antes** de gravar áudio: mudar depois desalinha o áudio já gravado (o botão do andamento fica desligado gravando).

**Metrônomo com subdivisões** (o projeto agora a 92,3 BPM):
1. Abra `Configurações` e desça até `METRÔNOMO`.
2. `Timbre`: `Madeira`. `Subdivisão`: `Colcheias` (em 4/4, 8 cliques por compasso, um a cada 0,325 s a 92,3 BPM). O controle `Volume das subdivisões` aparece: leve a 30%.
3. `Acento do primeiro tempo` em 150% e `Altura do acento` em `×1,50` (1200 Hz sobre os 800 Hz da madeira). `Volume` em 60%. Solte cada controle deslizante: o valor só vale ao soltar.
4. `Quando soa`: `Sempre que ligado` para ensaiar; ligue o metrônomo (`C`) e dê play. Depois troque para `Só ao gravar` se quiser o clique só na gravação.
5. Num compasso de 6/8 o "tempo" é a colcheia: `Um clique por tempo` dá 6 cliques por compasso e `Colcheias` dá 12.

## Variações

- **Regravar várias tomadas só do trecho.** Marque o loop em cima da frase (`5.1.1` a `7.1.1`), use `Usar a região do loop`, ligue o punch e o loop, cursor no começo do loop: cada volta é uma tomada só da região, e a ativa é a última que a cobre inteira. Escolha depois no selo `N tomadas`.
- **Punch em notas MIDI.** Com uma faixa de instrumento armada, o punch guarda só as notas da região (a que estava segurada no punch in começa nele, a que passa do punch out é cortada nele); as notas que já estavam no clipe **não** são apagadas: limpe antes no editor de notas. Com o teclado do computador ligado, `P` e `T` viram notas: use os botões.
- **Punch sem pré-roll.** Cursor antes do punch in e `Pré-roll` em `Não`: o transporte parte do cursor, o que você tocar antes do punch in é descartado e a emenda de entrada ganha o crossfade de 7 ms.
- **Tercinas.** `Subdivisão` em `Tercinas` (3 cliques por tempo, 0,217 s entre cliques a 92,3 BPM) para ensaiar um shuffle.
- **Só o acento.** `Só o acento do compasso` dá um clique por compasso, para sentir a forma da música sem marcar cada tempo.

## Por que funciona

- **O punch corta depois, não durante.** O app grava tudo o que a entrada mandou e, ao parar, guarda só a região. Por isso você pode passar do punch out e o clipe não ganha lixo, e por isso o punch não silencia nada ao vivo.
- **Pré-roll conta compassos, não segundos.** Ele volta pelo mapa de compassos (2 s por compasso a 120 BPM, 2,4 s a 100): a preparação é sempre musical, em qualquer andamento.
- **A contagem e o pré-roll são coisas diferentes.** A contagem é um compasso de cliques; o pré-roll é a música. Juntos, a contagem vem primeiro e o pré-roll depois, e o ponto de gravar não muda.
- **Fades de 7 ms.** Curtos demais para comer a sílaba e longos o bastante para não estalar; só existem onde a gravação foi cortada. Com pré-roll a entrada da região é seca, por isso o passo 8 do cenário 1.
- **Tap por média.** A média de até 8 batidas suaviza o erro de cada toque; por isso o valor melhora conforme você bate.
- **Subdivisão em cima do tempo do compasso.** Os cliques extras dividem o tempo do compasso vigente e seguem o mapa de andamento: o clique fica coerente em 6/8, 7/8 e com rampas.

## Se der errado

| Sintoma | Causa provável | Como resolver |
|---|---|---|
| `O cursor está depois do punch out: nada seria gravado. Mova o cursor ou a região de punch.` | Punch ligado, sem pré-roll, cursor depois da região | Cursor antes do punch in, ou mova as pontas `IN` e `OUT`; com loop ligado que contém a região, a gravação começa |
| `Nada foi gravado dentro da região de punch: a gravação parou antes do punch in, ou nada foi tocado nela.` | Parou antes de chegar ao punch in, ou não tocou dentro | Grave de novo e pare só depois do punch in |
| `Pare a gravação para ligar ou desligar o punch.` | Tentou ligar o punch gravando | Pare, ajuste, grave de novo (as pontas também não se mexem gravando) |
| Estalo no começo da frase regravada | Com pré-roll a emenda de entrada é seca | Fade de entrada de 5 a 10 ms no clipe novo |
| O punch ainda vale numa gravação que devia ser inteira | Ficou ligado do ensaio anterior | `P` desliga; o botão `Punch (P)` apagado |
| `P` e `T` viram nota | O teclado do computador está ligado (`Ctrl+K`) | Desligue o teclado ou use os botões |
| O pré-roll ficou menor que o escolhido | Cursor perto do começo (só vai até o zero) ou fim do loop dentro do pré-roll | Mova o cursor para mais adiante; ou desligue o loop |
| O tap tempo não muda nada | Gravando; ou o valor é igual ao atual; ou passou de 1,5 s e a sequência já recomeçou | Bata seguido; com o botão da janela o valor só vale no `Salvar` |
| O andamento pulou no meio das batidas (com `T`) | Pausa maior que 1,5 s: o valor foi aplicado e a sequência recomeçou | Bata sem pausas, ou use o botão da janela |
| Só ouço o clique padrão, mesmo com outro timbre | Página em cache ou APK antigo sem a chamada `metronome_style` (o `Volume` continua valendo) | Recarregue a página ou atualize o app |
| Depois de `Reiniciar o áudio` o timbre voltou ao clique | O estilo não é reenviado ao motor novo até a próxima mudança de opção `(lido do código)` | Mude qualquer opção do metrônomo e volte |
| `Volume das subdivisões` sumiu | A subdivisão é `Um clique por tempo` ou `Só o acento do compasso` | Escolha `Colcheias`, `Tercinas` ou `Semicolcheias` |
