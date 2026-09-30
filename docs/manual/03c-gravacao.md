# Gravação

> Grave o microfone (ou uma interface de áudio) numa faixa de áudio e as notas que você toca (teclado do computador ou controlador MIDI) numa faixa de instrumento, com contagem, loop com várias tomadas e compensação de latência.

## Onde fica

- **Gravar:** botão vermelho (círculo cheio) na barra do transporte, ao lado de parar e tocar. A setinha logo à direita dele (tooltip `Opções de gravação`) abre a contagem e as configurações.
- **Armar a faixa:** cada faixa tem um ponto de gravação (`Armar para gravar`), no cabeçalho da faixa (entre `S` e `A`) e no canal do mixer. Sem faixa armada, gravar não grava nada.
- **Monitorar a entrada:** no canal do mixer (botão com ícone de fone, `Monitorar a entrada`) e no menu de três pontos da faixa (`Monitorar a entrada`, com marca de seleção); só em faixa de áudio.
- **Configurações de gravação:** engrenagem da barra (tooltip `Configurações: entrada de áudio, latência e contagem`) ou item `Configurações de gravação…` da setinha do botão gravar. Abre a janela `Configurações`.
- **Teclado e MIDI:** dois ícones no meio da barra: teclado (`Tocar com o teclado do computador (Ctrl+K)`) e cabo (`Entrada MIDI: ligar teclado ou controlador`).

## Controles

### Botão gravar e o transporte

| Controle (rótulo exato) | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| Botão gravar (tooltip muda: `Gravar (R): nenhuma faixa armada; arme no mixer (●)`, `Gravar (R) na faixa armada, com um compasso de contagem`, `Gravar (R) nas N faixas armadas`) | Começa a gravar a partir do cursor. Com faixa de áudio armada abre o microfone (se ainda não estava aberto) | Atalho `R` | Vermelho cheio = gravando. **Pisca no andamento** durante a contagem (tooltip `Contando o compasso de entrada: toque para cancelar (R)`). Gravando: `Gravando: toque para parar (R)` |
| Setinha `Opções de gravação` › `Contagem de um compasso` (item com marca) | Liga/desliga a contagem antes de gravar | Padrão: **ligada**; vale para o projeto; fora do desfazer | O mesmo interruptor existe em `Configurações` |
| Setinha › `Configurações de gravação…` | Abre a janela `Configurações` | | |
| Parar / tocar (`Parar a gravação e voltar (Enter)`, `Parar a gravação (espaço)`) | Encerram a gravação e geram os clipes | `Enter`, `Home`, `Espaço`, `R` | Parar durante a contagem **cancela** sem gravar nada |
| Posição na barra | Durante a contagem mostra `−N` em vermelho quando o cursor está antes do zero | | Só se a gravação começa no primeiro compasso |
| Selo `Contando…` (na régua) | Aparece durante o compasso de contagem, à direita do cursor | | |
| Faixa vermelha na raia (`Gravando` / `Tomada N`) | Retângulo que cresce com o cursor nas faixas armadas; volta do loop vira `Tomada 2`, `Tomada 3`… | | |

Durante a gravação ficam **travados**: mover o cursor e marcar/arrastar o loop na régua, ligar/desligar o loop, mudar o andamento (`BPM`), desfazer/refazer, importar, exportar, armar/desarmar pelo cabeçalho da faixa, mudar warp e trocar a entrada. O app mostra `Pare a gravação para <ação>.`.

### Na faixa: armar, monitorar, medidor

| Controle (rótulo exato) | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| `Armar para gravar` (ponto vermelho, tooltip `Armar para gravar: ao gravar (R), o que entra no microfone vira um clipe nesta faixa` na de áudio; `... as notas que você tocar (teclado do computador ou MIDI) viram um clipe nesta faixa` na de instrumento) | Escolhe as faixas que recebem a gravação. Armar a primeira faixa de áudio **abre a entrada** (o navegador pede o microfone). Desarmar a última que precisava dela fecha a entrada | Desligado por padrão. Barramento não tem o botão. Fica no projeto, mas **fora do desfazer** | Armada: contorno vermelho; cheio enquanto grava de verdade (depois da contagem). No cabeçalho da faixa os tooltips são `Armar para gravar a entrada de áudio`, `Armar para gravar as notas (teclado ou MIDI)`, `Desarmar` e, gravando, `Gravando nesta faixa` |
| `Monitorar a entrada` (fone azul, só faixa de áudio; também existe no menu de três pontos da faixa; tooltip `Monitorar a entrada: ouvir o microfone ao vivo pelos efeitos e pelo fader desta faixa (use fones, senão microfona)`) | Faz o microfone soar ao vivo na faixa, **depois dos efeitos e do fader**, sem precisar tocar nem gravar | Desligado por padrão | Use fones para não dar microfonia. Também abre a entrada; funciona com o transporte parado |
| Medidor de entrada | Mostra o nível de pico do que chega **antes de qualquer efeito** | Escala de −48 a 0 dB; verde até 70% do curso, âmbar até 88%, vermelho depois; ~30 atualizações por segundo, sobe na hora e cai devagar | Aparece só em faixa de **áudio armada**: barra vertical ao lado do fader no mixer, barra fina de 3 px no pé do cabeçalho da faixa, e a barra `Nível` na janela `Configurações` |
| Luz de saturação (ponta do medidor) | Fica vermelha por 2 s quando o pico chega a −0,1 dBFS ou mais (já cortou no conversor) | | Tooltip `Vermelho no topo: saturou; baixe o ganho na fonte` |

### Janela `Configurações`

| Controle (rótulo exato) | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| Seção `ENTRADA DE ÁUDIO`, seletor | Escolhe de onde vem o áudio | `Padrão do sistema` (ou `Padrão (<nome>)`), depois as entradas encontradas (`Entrada N` quando o navegador esconde os nomes) e, se a escolhida sumiu, `Entrada desconectada` | A escolha fica **no aparelho**, não no projeto. Não troca durante a gravação |
| Botão de recarregar (tooltip `Procurar as entradas de novo (depois de conectar um microfone ou interface)`) | Relê a lista de entradas (pede a permissão do microfone se ainda não tem) | | Vira um círculo girando enquanto procura |
| `Nível` | Medidor de entrada (o mesmo do mixer) | | Só se mexe com a entrada aberta (faixa de áudio armada ou monitorando) |
| Seção `GRAVAÇÃO`, interruptor `Contagem de um compasso` | O metrônomo conta um compasso antes de a gravação começar | Padrão ligado | Se o metrônomo estava desligado, ele soa só durante a contagem |
| Controle deslizante e campo `ms`: `Compensação de latência` | Ajuste manual, somado à latência que o navegador informa | **−200 a +500 ms**, passo de 1 ms, padrão 0. Positivo adianta o que foi gravado; negativo atrasa | Vale para o projeto; fora do desfazer. Campo aceita só números inteiros (`De -200 a 500 ms` se sair da faixa) |
| `Fechar` | Fecha (leva junto um número digitado e ainda não confirmado) | | |

### Teclado do computador e MIDI

| Controle (rótulo exato) | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| Ícone de teclado (tooltip `Tocar com o teclado do computador (Ctrl+K)`; ligado: `Teclado tocando: atalhos suspensos (C L S X Z E F K J e Shift+H/L). A a P tocam a partir do C4, Z/X mudam a oitava, C/V a intensidade (80%). Ctrl+K desliga`) | Liga as teclas como piano. Ligado, mostra a oitava no ícone (`C4`) | `A W S E D F T G Y H U J K O L P` = dó a ré# da oitava seguinte. Oitava **0 a 8**, padrão 4 (tecla `A` = dó central, nota 60). Intensidade **10% a 100%**, passo de 10%, padrão 80% | `Z`/`X` baixam/sobem a oitava; `C`/`V` diminuem/aumentam a intensidade. Segurar a tecla não reataca |
| Ícone de cabo (tooltip `Entrada MIDI: ligar teclado ou controlador`; depois `Entrada MIDI: <nomes>` ou `MIDI ligado, nenhum aparelho conectado: conecte e ele aparece aqui sozinho`) | Pede acesso ao MIDI e passa a ouvir todos os aparelhos. O número no ícone é a quantidade de aparelhos conectados | Web MIDI **sem sysex**; aparelho que entra ou sai com a página aberta é detectado sozinho | Precisa de um clique (gesto). Negado ou sem suporte: aviso em texto |

O MIDI entende, em qualquer canal (o número do canal é ignorado):

| Mensagem | O que faz | Valores |
|---|---|---|
| Nota ligada e desligada | Toca e solta a nota (nota ligada com velocidade 0 vale como desligada) | A velocidade vem do controlador |
| Pitch bend (`0xE0`) | Afina as notas da faixa, até o `Alcance do bend` do instrumento | 14 bits (LSB e MSB), 8192 no centro: de -1 a quase +1 (8191/8192) |
| `CC 1` (roda de modulação) | Liga o vibrato da roda | 0 a 127, vira 0 a 1 |
| `CC 64` (pedal de sustain) | Segura as notas soltas até o pedal subir | Embaixo a partir de 64 |
| `CC 121` (reset dos controles) | Bend, roda e pedal voltam ao repouso, cada um na faixa em que estava | |
| `CC 120` (all sound off) | Corta tudo na hora, inclusive as caudas, e zera bend, roda e pedal | |
| `CC 123` (todas as notas desligadas) | Solta as notas que o MIDI estava tocando | |

Outros controles não são lidos. O bend, a roda e o pedal vão para a mesma faixa das notas (regra abaixo) e, com uma gravação em andamento, são gravados junto (ver "Gravar bend, modulação e pedal"). O pedal agora é resolvido dentro do motor: as notas soltas com o pedal embaixo ficam soando até ele subir, também as tocadas pelas teclas do teclado da tela e do computador. A bateria ignora bend, roda e pedal: o app nem os manda a uma faixa de bateria (as rodas da tela não aparecem nela) e a gravação não os registra nela.

Seja qual for a origem (controlador MIDI, rodas da tela ou os pontos desenhados na faixa de controle), o valor tem a mesma resolução: o bend em passos de 1/8192 (14 bits, o centro exato), a modulação em passos de 1/127 e o pedal só solto ou embaixo. Assim, o que se grava e o que se desenha soam iguais.

**Qual faixa toca:** a faixa **selecionada**, se for de instrumento; mas havendo faixa de instrumento **armada** e a selecionada não estando armada, toca (e grava) a **primeira armada**. Armar leva a entrada para a faixa. Se a entrada muda de faixa com a roda de modulação, o bend ou o pedal fora do repouso, a faixa antiga volta ao repouso.

As rodas do teclado da tela (ver [Painel de instrumento](04-painel-de-instrumento.md#rodas-de-pitch-bend-e-de-modulação)) tocam a faixa do painel, não a regra acima; se essa faixa está armada, também são gravadas. O app lembra separadamente onde o controlador MIDI e as rodas da tela deixaram cada controle fora do repouso: trocar a faixa de entrada num deles não devolve ao repouso o que o outro deixou.

**Parar zera o que se tocou ao vivo.** Parar (`Enter`, `Home`) e pausar (`Espaço`, com a música tocando) soltam o pedal e levam o pitch bend e a roda de modulação ao centro, seja o que vier do controlador MIDI ou das rodas da tela (elas voltam ao zero sozinhas). Antes o motor só zerava o que o clipe dirigia, então um pedal seguro no controlador na hora de parar continuava valendo. Se a entrada troca de faixa (por exemplo, você seleciona outra faixa com o pedal embaixo), a faixa antiga volta ao repouso mesmo quando o valor novo é o de repouso: soltar o pedal já na faixa nova não deixa a antiga presa. Encerrar uma gravação em andamento não passa por esse caminho: o repouso do fim da gravação é o descrito em "Gravar bend, modulação e pedal". `(testado só por testes automáticos; não visto com um controlador de verdade)`

## Passo a passo

**Gravar voz ou instrumento no microfone**
1. Selecione uma faixa de áudio (ou crie com `Faixa` › `Áudio`).
2. Toque o ponto `Armar para gravar`. O navegador pede o microfone (no Android, a permissão do app); permita. O medidor da faixa começa a se mexer.
3. Fale ou toque forte: o pico deve ficar no verde/âmbar, sem acender a luz vermelha do topo. Ajuste o ganho na fonte (interface ou sistema).
4. Ponha o cursor onde quer começar e aperte `R`. O botão pisca, o metrônomo conta um compasso e a gravação começa.
5. Para encerrar, `R`, espaço ou `Enter`. Aparece `Salvando a gravação…` e o clipe nasce na faixa, com nome `Gravação N.wav`. O cursor volta ao ponto em que você começou, para ouvir.

**Gravar várias tomadas em loop e escolher**
1. Marque o loop arrastando na régua e ligue `Loop (L)`.
2. Arme a faixa de áudio e grave (`R`). A cada volta do loop o retângulo vermelho passa a dizer `Tomada 2`, `Tomada 3`…
3. Pare. Nasce **um clipe** cobrindo o loop, com o selo `N tomadas`. A tomada ativa é a **última passada completa** (uma passada é completa se cobre pelo menos 98% do loop, sem ter começado no meio).
4. Para trocar, toque o selo `N tomadas` ou use o menu do clipe (`Tomadas`): a lista `TOMADAS` marca a ativa com um visto; escolha outra (posição, corte e fades do clipe ficam).

**Gravar notas com o teclado do computador (e fazer overdub)**
1. Crie uma faixa de instrumento (`Sintetizador`, por exemplo) e arme o ponto dela.
2. Ligue o teclado (`Ctrl+K`); o ícone mostra `C4`.
3. Aperte `R`, espere a contagem e toque com `A W S E D F T G Y H U J K O L P`.
4. Pare. As notas caem no clipe de notas que já estava sob o cursor (o clipe **estica em compassos inteiros** se passar do fim) ou num clipe novo que cobre os compassos gravados. Para dar outra camada, volte o cursor para dentro do mesmo clipe e grave de novo: as notas novas **somam** às antigas.

**Gravar bend, modulação e pedal junto das notas**
1. Faixa de instrumento com afinação (`Sintetizador`, `FM`, `Wavetable` ou `Sampler`) armada e um teclado MIDI ligado (ícone de cabo), ou use as duas rodas do teclado da tela (a de bend volta ao centro sozinha; a de modulação fica onde você a deixa).
2. Aperte `R`, espere a contagem e toque mexendo a roda de bend, a de modulação e o pedal.
3. Pare. As notas e os pontos caem no mesmo clipe. Abra-o no editor de notas e, embaixo da grade, escolha `Pitch bend`, `Modulação` ou `Sustain` no canto esquerdo da faixa para ver e editar os pontos ([Faixa de controle](05-piano-roll.md#faixa-de-controle)).
4. Para regravar só o bend (ou só o pedal) por cima de um clipe, volte o cursor para dentro dele e grave de novo: veja as regras de overdub abaixo.
5. Para gravar só o pedal (ou só o bend) sem tocar nota nenhuma, é o mesmo caminho: se há um clipe sob o cursor, os pontos entram nele; se não há, nasce um clipe novo, vazio de notas, com os pontos.

**Gravar com o transporte andando**
1. Dê play (espaço), com faixa armada.
2. Aperte `R` no ponto onde quer começar a gravar. Não há contagem: a gravação vale a partir dali. A posição exata do início vem do primeiro bloco de áudio capturado (`recordBeat` da entrada), e não do desenho do cursor no momento do clique.
3. Pare com `R`, espaço ou `Enter`.

## Combina com

- [Áudio e clipes](03-audio-e-clipes.md): o clipe gravado é um clipe de áudio comum (aparar, cortar, mover, fades).
- [Warp e altura](03b-warp-e-altura.md): esticar ou transpor uma gravação depois; o warp só liga com a gravação parada.
- [Áudio para MIDI](03d-audio-para-midi.md): uma gravação de voz ou linha de baixo (que sai como WAV) pode virar notas.
- [Mixer](06-mixer.md): efeitos, fader e envios da faixa; o monitor passa por eles.
- [Compensação de latência dos efeitos](06e-compensacao-de-latencia.md): por que o som de um projeto com `Limitador` ou `Distorção` sai alguns ms atrasado e o que fazer ao gravar por cima.
- [Transporte e barra de ferramentas](02-transporte.md): botão gravar, contagem, loop e a janela `Configurações`.
- [Editor de notas (piano roll)](05-piano-roll.md): limpar, quantizar e editar as notas gravadas e, na faixa de controle, os pontos de bend, modulação e pedal.
- [Painel de instrumento](04-painel-de-instrumento.md): as rodas do teclado da tela e o `Alcance do bend` de cada instrumento.
- [Expressão MIDI na prática](../guias/expressao-midi-na-pratica.md): receitas de gravação com teclado MIDI, bend e pedal.

## Limites e pegadinhas

**Como o áudio é gravado**
- A entrada é aberta **sem** cancelamento de eco, supressão de ruído nem ganho automático (voz e instrumento não são "melhorados"). Pede estéreo se houver e na mesma taxa do motor; se a entrada for mono (os dois lados iguais, ou um lado em silêncio absoluto), o clipe sai **mono**.
- A gravação é a entrada **crua**: os efeitos da faixa não entram no arquivo, só no que você ouve. Cada gravação é guardada como WAV de 32 bits float, na taxa do motor, e entra no projeto como qualquer áudio importado (sha-256, guardado no aparelho, enviado ao servidor com a sincronização).
- Gravação com menos de 50 ms depois da compensação (um toque e solta no botão) não gera clipe. Se a entrada não mandou nada, o aviso é `A entrada não mandou áudio durante a gravação: confira o microfone e a entrada escolhida.`. Sem nota tocada numa faixa de instrumento armada: `Nenhuma nota foi tocada na faixa armada durante a gravação.`. Sem faixa armada: `Arme uma faixa para gravar (o botão de gravação dela): a de áudio grava a entrada; a de instrumento, as notas tocadas.`.
- Gravar por cima de um clipe existente **substitui** o trecho: o que estava embaixo é aparado, partido ou removido (como o restante do arranjo). Se duas faixas de áudio estão armadas, **cada uma recebe um clipe** com o mesmo áudio.
- A última passada do loop com menos de **uma batida** é descartada (é o passo além da volta de quem parou).
- Uma gravação em loop que começou **antes** do início do loop deixa um clipe comum para o trecho de antes do loop, mais o clipe de tomadas para o loop. Uma que começou **no meio** do loop tem a primeira tomada com silêncio na frente e não é escolhida como ativa (a menos que nenhuma passada esteja completa; aí vale a última).
- O clipe de tomadas dura o tamanho do loop em segundos no andamento em que foi gravado.

**Latência e compensação**
- O app desconta sozinho do começo do áudio a soma de: latência do contexto e da saída do navegador (`baseLatency` + `outputLatency`), latência do próprio motor (efeitos com latência, cadeia do `Master` e limitador de segurança do master, que o motor informa às pontes), latência da entrada que o aparelho informa e a `Compensação de latência` da janela `Configurações`. O clipe sai alinhado com a grade. As notas MIDI e os controles gravados voltam para antes da latência do motor mais a de saída do aparelho, sem passar do começo da gravação. `(precisa do motor recompilado; testado só por testes automáticos)`
- **Limites dessa conta:** com um motor de antes da fase 13 (sem a chamada de latência nas pontes) a latência dos efeitos ([06e](06e-compensacao-de-latencia.md)) não entra e o clipe cai esse tanto atrasado; com o motor novo entra sozinha. O clique do metrônomo é atrasado da mesma latência, então soa junto das faixas.
- **Se ainda sobrar um desvio:** ajuste a `Compensação de latência`. Passo a passo em [06e](06e-compensacao-de-latencia.md#gravar-por-cima-de-um-projeto-com-efeitos-de-latência).
- Para calibrar: grave o metrônomo (ou um clique) pelo microfone e ajuste a compensação até a batida gravada cair na grade. Positivo adianta, negativo atrasa. Calibre com os efeitos de latência tirados ou zerados, para medir só a do aparelho.
- Ao parar, o app espera uma fração de segundo (a latência total mais 20 ms) para a entrada terminar de chegar, antes de encerrar.

**Contagem**
- Um compasso, o do mapa de compassos no ponto onde a gravação começa (4 batidas em 4/4, 3 em 3/4 ou 6/8, 3,5 em 7/8). Só quando o transporte estava parado: gravando com play rodando não há contagem.
- Notas de instrumento tocadas **durante a contagem** são aproveitadas só se estiverem até 1/4 de batida antes do primeiro tempo (entram no primeiro tempo); a nota ainda segurando no primeiro tempo começa nele; o resto some.
- Quando o cursor está antes do fim do primeiro compasso, a contagem é feita numa região vazia longe do fim do projeto e volta (o cursor mostra os tempos negativos). Não muda nada do que você grava.

**Permissão do microfone**
- **Navegador:** a permissão é pedida ao **armar** a primeira faixa de áudio (ou ao abrir `Configurações`), não ao gravar. Precisa de `https` (ou `localhost`). Permissão negada desarma a faixa e mostra: `O navegador negou o acesso ao microfone. Libere o microfone nas permissões do site e tente de novo.`. Outras mensagens: `Nenhuma entrada de áudio encontrada. Conecte um microfone ou uma interface de áudio e tente de novo.`, `A entrada de áudio está ocupada por outro programa ou não respondeu…`, `A entrada de áudio escolhida não está mais conectada…`.
- **Android:** a permissão do sistema (`RECORD_AUDIO`) é pedida na primeira vez. Negada: `O Android negou o acesso ao microfone. Permita o microfone para o jopendaw e tente de novo.`; negada de vez: o app manda liberar em Configurações › Apps › jopendaw › Permissões.
- Ao abrir um projeto que tinha faixa **armada ou monitorando**, o app reabre o microfone; se falhar, desarma tudo (para não parecer pronto).
- Quando ninguém precisa do microfone (nenhuma faixa de áudio armada nem monitorando, fora de gravação), o app o solta e o aviso do navegador some.
- Se a entrada cai no meio (cabo, interface desligada, permissão revogada), o app avisa `A entrada de áudio "<nome>" foi desconectada.` (no Android `A entrada de áudio foi desconectada.`); as faixas ficam armadas e uma gravação em andamento segue com **silêncio** no lugar, para o resto continuar no lugar.
- Duplicar uma faixa **não** duplica o estado armado nem o de monitorar.

**Gravação MIDI**
- Grava as notas tocadas **ao vivo** (teclado do computador ou MIDI) enquanto o transporte toca, com a batida exata em que o motor as aplicou. O motor guarda até **16.384 notas** por gravação; passou disso, as novas são descartadas. A mesma tecla apertada de novo sem soltar termina a anterior. Nota segurada quando você para termina no ponto de parada.
- Nota com velocidade 0 não é nota. Nota mais curta que 1/64 de batida é esticada até isso.
- A nota segurada na volta do loop vira duas (até o fim do loop, e do começo dele até a soltura). Em loop, as notas de todas as passadas ficam **no mesmo clipe** (não há tomadas de MIDI).
- O clipe novo cobre compassos inteiros e tem no mínimo um compasso, com o nome da faixa. Os compassos são os do mapa de compassos (num projeto em 7/8 o clipe cresce em blocos de 3,5 batidas); antes a conta usava só os tempos por compasso do compasso inicial.
- Tocar notas clicando no teclado do piano roll também é "ao vivo" e pode ser gravado (não confirmado).
- `jopendawEngine.injectMidi(status, d1, d2)` (no console do navegador, só na web) injeta uma mensagem MIDI pelo mesmo caminho de um aparelho: por exemplo `jopendawEngine.injectMidi(0x90, 60, 100)` liga o dó central e `jopendawEngine.injectMidi(0x80, 60, 0)` desliga. **É só para teste e depuração**, sem hardware. Só chega depois de ligar o MIDI (ícone do cabo) (não confirmado sem isso).

**Gravação de bend, modulação e pedal**
- Os controles chegam ao motor pela mesma via das notas ao vivo (`live_bend`, `live_cc`) e são registrados com a batida exata em que ele os aplicou, **só com o transporte tocando**. O motor guarda até **32.768 eventos de controle** por gravação, numa cota à parte das 16.384 notas: uma roda mexida a fundo não toma o lugar das notas. Passou disso, os novos são descartados.
- O que entra no clipe: um ponto por mudança de valor (bend de -1 a 1; modulação de 0 a 1; pedal solto ou embaixo), com a batida contada do começo do clipe. A gravação é **afinada** antes de entrar: por controle, no máximo um ponto a cada 1/48 de batida (uns 10 ms a 120 bpm; dentro dessa janela vale o valor mais recente), sem repetir o valor anterior, sem o primeiro ponto se ele só confirma o repouso, e o último valor (onde a roda parou) sempre fica. O pedal guarda só as mudanças de estado.
- O que se tocou **na contagem** fica de fora (as notas da contagem têm regra própria, acima).
- **Repouso no fim:** o que estava fora do repouso quando a gravação parou volta a ele no clipe. Se o pedal estava embaixo, o bend fora do centro ou a roda de modulação levantada, o clipe ganha, para cada um, um ponto de retorno (pedal solto, bend no centro, modulação em zero) no ponto de parada, nunca menos de 1/16 de batida depois do último evento (para o pedal não ter duração zero). Sem isso, o clipe tocaria o resto dele com o pedal preso ou a nota dobrada (testado só por testes automáticos).
- **Overdub:** gravando sobre um clipe existente, para cada controle que você mexeu, os pontos velhos **do mesmo controle** no trecho tocado (do primeiro ao último ponto novo dele) são substituídos pelos novos; os outros controles e os pontos fora do trecho ficam. Notas novas somam às antigas, como sempre. Se o clipe estica para a esquerda para caber a gravação, os pontos velhos vão junto.
- **Só controles, sem nenhuma nota:** os pontos entram no clipe que estava sob o cursor (útil para gravar só o pedal por cima de notas que já existem), esticando-o em compassos inteiros se a gravação passar do fim. Sem clipe ali, nasce um **clipe novo, sem notas**, que cobre do ponto onde a gravação começou (ou do loop, se gravou em loop) até onde ela parou, em compassos inteiros e com no mínimo um compasso, como a gravação de notas faz. O aviso `Nenhuma nota foi tocada…` só sai quando não houve nota nem controle.
- **Em loop**, só a **última passada** vale para os controles (as passadas anteriores cobrem as mesmas batidas com outra curva, e curvas intercaladas dariam tremor); as notas de todas as passadas continuam entrando.
- Gravar só considera faixas de instrumento **armadas**; pontos de faixa desarmada ou inexistente são ignorados.
- **Bateria:** não recebe controles ao vivo (o app não os manda a uma faixa de bateria) e, se algum chegasse ao registro do motor, a gravação o descarta ao montar o clipe: o clipe de bateria não ganha pontos de bend, modulação nem pedal. Gravar só controles com uma faixa de bateria armada não cria clipe nenhum (não confirmado: lido no código; o teste cobre a bateria com uma nota e sem pontos). Tudo isto vale só por testes automáticos, não foi conferido com um controlador de verdade.
- Se a roda de modulação já estava levantada quando você apertou gravar, o motor grava só o que muda depois: o valor inicial não entra no clipe (não confirmado).
- Teste sem hardware (só web, depois de ligar o MIDI): `jopendawEngine.injectMidi(0xE0, 0, 96)` manda um pitch bend de meio alcance para cima (14 bits: MSB 96, LSB 0 = 12288, ou +0,5); `jopendawEngine.injectMidi(0xB0, 1, 127)` levanta a roda de modulação; `jopendawEngine.injectMidi(0xB0, 64, 127)` desce o pedal e `jopendawEngine.injectMidi(0xB0, 64, 0)` o solta (não confirmado).

**Teclado do computador ocupa atalhos**
- Com o teclado ligado, as letras de nota (`A W S E D F T G Y H U J K O L P`) e `Z X C V` são consumidas por ele: `S` (cortar no cursor), `E` (editor), `F` (efeitos), `L` (loop), `C` (metrônomo), `X` (mixer) e `Z` (enquadrar) **deixam de funcionar** como atalhos. `R`, `M`, `I`, espaço e `Enter` continuam. Com `Ctrl`/`⌘` apertado, as teclas voltam a ser atalhos. Desligue o teclado (`Ctrl+K`) para usar os atalhos de letra.

**Diferenças entre web e Android**
- Web: entrada pelo `getUserMedia` do navegador, captura em blocos de 4096 quadros (uns 85 ms a 48 kHz). Android: entrada nativa (AAudio) do aparelho, MIDI pelo plugin de MIDI do app.
- Bend (`0xE0`), modulação (`CC 1`) e pedal (`CC 64`) chegam pelo mesmo caminho nas duas plataformas: o Web MIDI do navegador e o plugin de MIDI do app no Android entregam a mensagem à mesma função do app, que a passa ao motor (o WASM na web, `libjopendaw_engine.so` no Android), com a mesma cota de 32.768 eventos por gravação. Este trecho vem da leitura do código e dos testes; nenhuma das duas plataformas foi conferida com um controlador de verdade (não confirmado).
- Em Firefox o navegador não converte taxa: se a entrada estiver numa taxa diferente do motor, o app manda ajustar nas configurações de som do sistema (`A entrada de áudio está em <taxa> Hz e o motor em <taxa> Hz…`).

## Atalhos

| Tecla | Ação |
|---|---|
| `R` | Gravar / parar a gravação (com `Ctrl`/`⌘` fica para o navegador recarregar) |
| `Espaço` | Tocar / pausar; gravando, encerra a gravação |
| `Enter` ou `Home` | Parar e voltar; gravando, encerra a gravação primeiro |
| `Ctrl+K` (`⌘+K`) | Liga/desliga o teclado do computador como piano |
| `A W S E D F T G Y H U J K O L P` | Notas (com o teclado ligado) |
| `Z` / `X` | Oitava abaixo / acima (com o teclado ligado) |
| `C` / `V` | Intensidade menor / maior (com o teclado ligado) |
| `L` | Loop liga/desliga (bloqueado durante a gravação) |
| `C` | Metrônomo (sem o teclado ligado) |
