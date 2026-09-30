# Mapa de andamento e de compassos na prática

> Faz o andamento virar no meio da música (de 90 para 120 BPM), frear no final com um ritardando em rampa e trocar de compasso (4/4 para 3/4 e para 6/8), sabendo o que acompanha essas mudanças e o que não; cerca de 20 minutos, mais o tempo de ouvir e acertar de ouvido.

Os números abaixo são um exemplo: uma música de 16 compassos que começa a 90 BPM. Troque pelos seus. O que depende do programa (rótulos, faixas de valor, o que segue ou não o mapa) vem do código; os valores de andamento são só um ponto de partida musical. As três receitas são independentes: dá para fazer só uma delas, ou as três no mesmo projeto.

## Ingredientes

| Recurso | Para quê aqui | Capítulo |
|---|---|---|
| Botão de velocímetro (canto esquerdo da régua, tooltip `Mostrar a faixa de andamento`) e a faixa `Andamento` | Ver e editar os pontos de andamento sob a régua | [02b Faixa Andamento e mapa de compassos](../manual/02b-timeline-e-clipes.md#faixa-andamento-e-mapa-de-compassos) |
| Botão direito na faixa: `Adicionar ponto aqui`; num ponto: `Digitar BPM…`, `Rampa até o próximo ponto` / `Salto até o próximo ponto`, `Apagar o ponto` | Criar a virada, o ritardando e desfazê-los | [02b Faixa Andamento e mapa de compassos](../manual/02b-timeline-e-clipes.md#faixa-andamento-e-mapa-de-compassos) |
| Grade de encaixe `Compasso` | Fazer o ponto cair no começo de um compasso | [02 Transporte](../manual/02-transporte.md) |
| `120 BPM · 4/4` (janela `Andamento e compasso`) e o botão `Mudar compasso a partir de um compasso…` (janela `Mudar compasso a partir do compasso N`) | Fixar o andamento inicial e trocar a fórmula de compasso | [02 Transporte](../manual/02-transporte.md#janela-mudar-compasso-a-partir-do-compasso-n) |
| `Metrônomo (C)` | Ouvir a virada, a rampa e a fórmula de compasso | [02 Transporte](../manual/02-transporte.md) |
| `Cortar no cursor (S)` e `Warp e altura…` (`BPM do áudio`) | Encaixar um loop de áudio numa parte de outro andamento | [03b Warp e altura](../manual/03b-warp-e-altura.md) |
| Delay em `Tempo` `Andamento`, com a `Nota` | Saber por que o eco não acompanha a virada | [06d Referência dos efeitos](../manual/06d-efeitos-referencia.md#7-delay) |
| Gravação com contagem | Gravar sobre um mapa já desenhado | [03c Gravação](../manual/03c-gravacao.md) |
| `Exportar` | Tirar o WAV com os tempos certos | [08 Exportação](../manual/08-exportacao.md) |

## Antes de começar: como o mapa funciona

- Tudo no projeto (clipes, notas, automação, marcadores, loop) fica em **batidas**, e a batida é a semínima. O mapa só decide quantos segundos dura cada batida. Por isso notas, bateria programada e automação seguem o mapa sozinhas.
- O **andamento inicial** é o primeiro ponto (batida 0), o mesmo `BPM` da janela `Andamento e compasso` (20 a 400, inteiro). Os outros pontos aceitam 20 a 999, com decimais (`92,5`).
- Cada ponto diz como chega ao próximo: em **salto** (mantém o BPM e muda de uma vez no ponto seguinte) ou em **rampa** (o BPM anda em reta, em função da batida, até o BPM do seguinte). Os pontos novos nascem em salto, no BPM que já vale ali.
- Numa música em 4/4, o compasso N começa na batida `4 × (N − 1)`: o compasso 9 é a batida 32, o 13 é a 48, o 17 é a 64. O título da janela `Digitar BPM…` (`Andamento na batida 32`) confere isso.
- Sem nenhum ponto novo, o projeto soa exatamente como antes do mapa (um teste do motor compara a saída quadro a quadro com a do motor de antes). `(testado só por testes automáticos)`

## Passo a passo

### Receita 1: virada de andamento (90 para 120 BPM no compasso 9)

1. Projeto novo, `Vazio`. Toque em `120 BPM · 4/4`, digite `90` em `BPM`, `Salvar`. Esse é o andamento inicial.
2. No canto esquerdo da régua, toque no botão de velocímetro. A faixa `Andamento` aparece sob a régua, com o texto `Duplo clique adiciona uma mudança de andamento`.
3. No menu da grade de encaixe do transporte, escolha `Compasso`.
4. Com o botão direito na faixa `Andamento`, bem sobre o número 9 da régua, escolha `Adicionar ponto aqui`. O ponto nasce em salto, a 90 BPM. (Afaste o zoom com `Z` se o compasso 9 estiver fora da tela.)
5. Botão direito no ponto novo, `Digitar BPM…`. O título diz `Andamento na batida 32`: é o compasso 9. Digite `120`, `Salvar`. A linha da faixa passa a 90 até o degrau e a 120 depois, com os números `90` e `120` ao lado dos pontos.
6. Ligue o metrônomo (`C`) e toque a partir do compasso 7. O botão do transporte mostra o BPM vigente no cursor (`90 BPM · 4/4` antes do ponto e `120 BPM · 4/4` depois, com um ícone de linha quebrada na cor da marca). Os cliques aceleram de uma vez no compasso 9.
7. Escreva as notas de sempre. Elas estão em batidas e acompanham a virada.

Conta para conferir: os 8 primeiros compassos (32 batidas) a 90 BPM levam 21,33 s, então o cursor chega ao compasso 9 em `0:21.33`; dali, cada compasso leva 2 s. A mesma conta com 120 BPM até a batida 8 e 60 BPM depois dá 2 batidas por segundo até 4,0 s e uma por segundo dali em diante, e foi o que a sessão de código mediu no Chrome (relato; não repeti). Ctrl+Z desfaz cada passo.

**Se o projeto tem loops de áudio (warp).** O warp estica o áudio **uma vez**, para o andamento **inicial** (90), e ele toca em velocidade constante: na parte de 120 BPM o loop com warp continua a 90 e sai da grade. Duas saídas:

1. Corte o clipe no ponto (cursor no compasso 9, `S`; o corte conta os segundos reais entre as batidas). Na segunda metade, se o loop original já é de 120 BPM, desligue o warp dela (`Desligar o warp`): sem warp o clipe toca na velocidade original.
2. Se o loop original tem outro andamento (digamos 90) e você quer ele a 120 na parte de cima, dê à segunda metade o `BPM do áudio` calculado: `BPM do áudio = andamento real do áudio × BPM inicial ÷ BPM da parte`, aqui `90 × 90 ÷ 120 = 67,5`. Digite `67,5` e `Ajustar ao andamento`. `(conta pela fórmula do warp, razão = BPM do áudio ÷ BPM inicial; não ouvi o resultado)`

**Se o projeto tem delay sincronizado.** O delay, o tremolo e o filtro em `Tempo` `Andamento` usam **só o andamento inicial**. Um delay `1/8D` (0,75 batida) faz 500 ms a 90 BPM e deveria fazer 375 ms a 120 BPM; ele continua a 500 ms na parte de cima. Escolha o que preferir:

- deixe o andamento **inicial** ser o da parte em que o eco mais aparece (o resto do mapa não muda);
- ou ponha as duas partes em faixas separadas, cada uma com o delay em `Tempo` `Livre` e `Tempo livre` calculado à mão: `batidas da figura × 60 ÷ BPM` (1/8D: 500 ms a 90 BPM e 375 ms a 120 BPM; a faixa vai de 1 ms a 4 s).

### Receita 2: ritardando em rampa no final (120 para 70 BPM nos 4 últimos compassos)

Projeto de 16 compassos em 4/4, andamento inicial 120 (`120 BPM · 4/4`, sem mexer). O ritardando começa no compasso 13 (batida 48) e termina no fim do compasso 16, que é o começo do 17 (batida 64).

1. Ligue a faixa `Andamento` (botão de velocímetro) e a grade `Compasso`.
2. Botão direito na faixa, sobre o número 13: `Adicionar ponto aqui`. O ponto nasce com 120 BPM (o que já vale ali).
3. Botão direito na faixa, sobre o número 17: `Adicionar ponto aqui` (afaste o zoom se preciso). Botão direito nesse ponto, `Digitar BPM…` (título `Andamento na batida 64`), `70`, `Salvar`.
4. Botão direito no **primeiro** ponto (o do compasso 13, batida 48), `Rampa até o próximo ponto`. A linha vira uma diagonal do 120 ao 70. No menu do ponto do compasso 17 o item de rampa fica desligado: ele é o último, não há para onde rampar. `(testado só por testes automáticos)`
5. Toque a partir do compasso 11 com o metrônomo. No meio da rampa (compasso 15, batida 56) o botão do transporte mostra `95↗ BPM · 4/4`: a rampa é reta em função da batida, então na metade das batidas o BPM é a média, 95. O `↗` aparece em qualquer rampa, também nas que descem.

Conta para conferir (a fórmula `segundos = 60 × L ÷ (B − A) × ln(B ÷ A)`, com L = 16 batidas de A = 120 a B = 70): a rampa dura cerca de 10,35 s, contra 8 s se ficasse a 120; até a batida 48 são 24 s, então o fim do compasso 16 cai em torno de `0:34.35`. Metade das batidas (as 8 primeiras da rampa) leva 4,49 s e as outras 8 levam 5,86 s. O que vier depois do ponto de 70 BPM toca a 70. Um som que precisa "voltar a tempo" pede outro ponto depois, por exemplo 120 em salto no compasso 21.

**Notas, bateria programada e automação** acompanham a rampa. **Um clipe de áudio com warp não**: ele toca a velocidade constante (a do andamento inicial) e não freia junto. Para um final com loop de áudio, prefira material em notas ou use o clipe sem warp cortado em pedaços de um compasso, cada um com o `BPM do áudio` da média do compasso (aproximação por degraus; `(dedução; não testado)`).

### Receita 3: de 4/4 para 3/4 e para 6/8

Música de 16 compassos: 4/4 nos compassos 1 a 8, 3/4 do 9 ao 12, 6/8 do 13 ao 16.

1. Toque em `120 BPM · 4/4` (o texto pode mostrar outro andamento) e, na janela `Andamento e compasso`, em `Mudar compasso a partir de um compasso…`. A janela `Mudar compasso a partir do compasso N` abre com o compasso do cursor. `(testado só por testes automáticos; a janela não foi exercitada no navegador)`
2. Em `A partir do compasso` digite `9`; em `Tempos` escolha `3`; em `Unidade`, `4`. `Aplicar`. A régua mostra `3/4` em cor da marca sob o número 9.
3. Repita: botão `120 BPM · 3/4` (com o cursor entre os compassos 9 e 12 o botão mostra o compasso do cursor) → `Mudar compasso a partir de um compasso…`, `A partir do compasso` `13`, `Tempos` `6`, `Unidade` `8`, `Aplicar`. A régua mostra `6/8` sob o 13.
4. Ligue o metrônomo e toque do compasso 7. Em 3/4 o tempo forte agudo (1600 Hz) volta a cada 3 cliques; em 6/8 há um clique por colcheia, seis por compasso, só o primeiro agudo.
5. Confira as contas: a batida do projeto é a semínima, então 4/4 ocupa 4 batidas, 3/4 ocupa 3, 6/8 ocupa 3 (6 colcheias de meia batida). Os compassos 9 a 12 ocupam 12 batidas, o compasso 13 começa na batida 44 e o 17, na 56. O contador de posição usa a fórmula do trecho: no 6/8 o segundo número vai de 1 a 6 (uma colcheia por número).
6. Crie um clipe de notas com duplo clique numa faixa de instrumento, no compasso 13: ele nasce com 1 compasso de 6/8, ou seja, 3 batidas (e 3 batidas também no compasso 9).

Para pensar o 6/8 em dois tempos pontuados de 60 por minuto, o `BPM` do projeto (que conta semínimas) é `60 × 1,5 = 90`. Para desfazer uma mudança: `Mudar compasso a partir de um compasso…`, o mesmo compasso, e `Remover a mudança` (só existe para compassos depois do 1); ou Ctrl+Z.

## Variações

- **Accelerando.** Igual à receita 2, com o ponto final mais alto (por exemplo de 100 a 140 em 8 compassos).
- **Várias viradas.** Cada ponto novo cria uma virada; use marcadores (`M`, `Shift+M` para dar nome) para lembrar onde é o refrão. Cada projeto guarda até 512 pontos de andamento e 256 mudanças de compasso.
- **5/4 e 7/8.** Mesma janela: `5` e `4` (5 batidas por compasso) ou `7` e `8` (7/8 ocupa 3,5 batidas; o metrônomo clica por colcheia e marca o primeiro).
- **Voltar a um andamento só.** Botão direito num lugar vazio da faixa `Andamento`, `Apagar todas as mudanças de andamento` (o andamento inicial fica).
- **Gravar sobre o mapa.** Desenhe o mapa **antes** de gravar: gravando, o andamento e o compasso ficam travados (`Pare a gravação para mudar o andamento.`). A contagem tem o tamanho do compasso onde está o cursor (em 6/8, 3 batidas), com os quadros contados pelo mapa, e o metrônomo segue o mapa. Notas gravadas ficam em batidas e acompanham mudanças futuras do mapa; **áudio gravado não**: ele fica preso ao tempo real, então se você mexer no mapa antes dele depois de gravar, o clipe sai da grade.
- **Exportar.** O WAV segue o mapa (o tempo do trecho e o fim dos clipes são contados por ele). Já `Exportar MIDI (.mid)` grava só o andamento inicial e o compasso inicial (`n/4`), sem o mapa. `(lido do código)`

## Por que funciona

- O documento guarda posições em batidas e o mapa converte batidas em segundos. Trocar o mapa muda o **quando** de tudo que está em batidas, sem tocar nas notas: por isso a bateria programada e a automação viram junto com a música.
- A rampa é linear no **BPM em função da batida**, e a conta do tempo é a integral exata dela. Por isso a metade das batidas de um ritardando leva menos tempo que a outra metade, e por isso o BPM no meio da rampa é a média, não o BPM do meio do tempo.
- Áudio é diferente: um clipe sem warp começa na batida dele e dura os mesmos segundos de sempre. Com warp, ele é esticado para o andamento inicial e depois toca em velocidade constante. Nenhum dos dois freia ou acelera no meio; quem precisa seguir a grade em cada trecho é o material em notas.
- Efeitos sincronizados (delay, tremolo, filtro) recebem o andamento inicial uma vez e o guardam; o motor não os avisa a cada ponto do mapa.

## O que não acompanha o mapa

| Recurso | Segue o mapa? | O que fazer |
|---|---|---|
| Notas, bateria programada, automação, marcadores, loop, cursor, relógio, metrônomo, exportação em WAV, congelar faixa | Sim | Nada |
| Clipe de áudio sem warp | Começa na batida dele e toca em tempo real constante | Cortar e posicionar por trecho, ou usar o `BPM do áudio` calculado |
| Clipe de áudio com warp | Não: usa só o andamento inicial | Ver a receita 1 |
| Delay, tremolo e filtro em `Andamento` | Não: só o andamento inicial | `Tempo` `Livre` com o valor calculado, ou faixas separadas |
| Áudio já gravado | Não (tempo real fixo) | Desenhar o mapa antes de gravar |
| Editor de notas (linhas de compasso, `Shift`+← →) | Não: usa os tempos por compasso do compasso inicial | Guiar-se pela régua da timeline e pela grade de 1/8 ou 1/16 |
| Tooltip de `Duração do projeto` (o número de compassos) | Não: conta pelo compasso inicial | O tempo (`m:ss`) está certo; o número de compassos não |
| Lista de projetos e servidor | Só o andamento inicial e o compasso 1 (`n/4`) | O mapa completo viaja no documento sincronizado |
| `Exportar MIDI (.mid)` | Não: só o andamento e o compasso iniciais | |
| `Importar` de um `.mid` com mudanças de andamento | Não: só o primeiro andamento e o primeiro compasso entram (o aviso ainda diz `o app tem um andamento só`) | Refazer os pontos à mão na faixa `Andamento` |

## Se der errado

- **O ponto não cai no compasso que eu queria.** O encaixe da grade leva o ponto ao passo mais próximo. Escolha `Compasso` na grade e confira pelo título da janela `Digitar BPM…` (`Andamento na batida N`): em 4/4, batida `4 × (compasso − 1)`. Com **Alt** apertado o ponto não encaixa.
- **O ponto não se mexe ao arrastar.** O arraste só pega o ponto se o mouse ou o dedo tocou a menos de 10 px dele. Gravando, a faixa não responde. Na vertical são 0,5 BPM por pixel (2 px por BPM); com Alt, ajuste fino de 0,1 BPM.
- **O ponto inicial não sai do lugar nem se apaga.** É o andamento inicial. Mude o BPM dele arrastando na vertical, por `Digitar BPM…` ou pela janela `Andamento e compasso`.
- **O loop de áudio ficou adiantado depois da virada.** O warp usa só o andamento inicial; ver a receita 1.
- **O eco do delay não acompanhou o andamento.** Mesmo motivo; ver a receita 1.
- **A batida caiu fora depois de mexer no mapa.** Se você mudou o mapa antes de um clipe de áudio gravado ou sem warp, o clipe fica no mesmo tempo real e a grade se moveu. Mova o clipe (com Alt, sem encaixe) ou desfaça (Ctrl+Z).
- **Um projeto inteiro em 6/8 ou 7/8 (uma só mudança, no compasso 1) e o metrônomo voltou a marcar como `n/4` depois de algumas edições.** Pelo código, a cada sincronização o app reenvia `tempo` com os `tempos por compasso`, e o motor, quando o mapa de compassos tem um ponto só, o troca por `n/4`; com duas mudanças ou mais o mapa resiste. É um bug provável, `(não confirmado por execução)`, sem contorno confirmado; ver [dev/01-motor.md](../dev/01-motor.md#armadilhas-conhecidas).
- **O campo `Tempos por compasso` da janela `Andamento e compasso` não mudou nada.** Se o compasso inicial já é de outra fórmula (por exemplo 6/8), esse campo não o muda: use `Mudar compasso a partir de um compasso…` com `A partir do compasso` `1`.
