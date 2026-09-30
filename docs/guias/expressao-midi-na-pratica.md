# Expressão MIDI na prática

> Quatro receitas para tocar e desenhar expressão (pitch bend, vibrato pela roda de modulação e pedal de sustain): um solo de sintetizador com scoop e vibrato que entra devagar, acordes de teclado segurados pelo pedal, uma queda de altura desenhada e automatizada, e a gravação de tudo isso com um teclado MIDI de verdade. Cada receita leva de 5 a 10 minutos.

Os valores vêm dos presets do app e das tabelas de parâmetros do código. O que se ouve **não foi conferido de ouvido** ao escrever este guia (`não confirmado ao ouvido`): use os números como ponto de partida. As contas de tempo usam 120 bpm (uma batida = 500 ms).

## Ingredientes

- [Faixa de controle do piano roll](../manual/05-piano-roll.md#faixa-de-controle): as visões `Pitch bend`, `Modulação` e `Sustain` sob a grade, com lápis, reta, mover e apagar.
- [Rodas do teclado da tela e alcance do bend](../manual/04-painel-de-instrumento.md#rodas-de-pitch-bend-e-de-modulação): os knobs `Alcance do bend` (0 a 24 st, padrão 2) e `Vibrato da roda` (0 a 2 st, padrão 1) do cartão `GERAL`.
- [Sintetizador](../manual/04a-sintetizador.md), [FM](../manual/04d-fm.md) e [Wavetable](../manual/04e-wavetable.md): os três respondem a bend, vibrato e pedal. O [Sampler](../manual/04c-sampler.md) responde a bend, a vibrato e ao pedal, e também tem os knobs `Alcance do bend` e `Vibrato da roda` no cartão `GERAL` (mesmos valores: 0 a 24 st e 0 a 2 st). A [Bateria](../manual/04b-bateria.md) ignora os três: as rodas nem aparecem no painel dela e a gravação não cria pontos nela.
- [Gravação](../manual/03c-gravacao.md): como o motor registra bend, modulação e pedal junto das notas.
- [Painel de efeitos](../manual/06c-painel-de-efeitos.md) e [Referência dos efeitos](../manual/06d-efeitos-referencia.md): `Delay` e `Reverb`.
- [Automação](../manual/07-automacao.md): para mover parâmetros do instrumento (como o `Corte`) junto da expressão.
- [Ferramentas MIDI](../manual/05b-ferramentas-midi.md): `Escala…`, `Acorde no clique` e `Escalar o tempo` (que leva os pontos de controle junto).

Três coisas para saber antes:

1. **A curva é em degraus.** Cada ponto vale até o próximo; o lápis põe um ponto por passo da grade. Para um bend que soe como deslize, use a grade `1/32` (um ponto a cada 62 ms a 120 bpm).
2. **O bend é uma fração do alcance.** O ponto vai de -1 a +1 e o valor real é ponto × `Alcance do bend`: com o padrão de 2 st o topo da faixa é +2 st; com 12 st, é uma oitava.
3. **Os pontos são do clipe.** Movem-se, duplicam-se e são cortados junto com ele na linha do tempo, mas não acompanham notas que você move dentro do editor. Copiar, recortar, colar e duplicar notas (`Ctrl+C`, `Ctrl+X`, `Ctrl+V`, `Ctrl+D`) levam os pontos do trecho delas, do começo da primeira nota ao fim da última (`Ctrl+X` também os tira do clipe de origem, junto das notas).

## Passo a passo

### Receita 1: solo de sintetizador com scoop e vibrato que entra

Resultado: uma nota longa que "sobe" 2 semitons no ataque e ganha vibrato depois de meio segundo, como um cantor ou uma guitarra.

1. Crie uma faixa `Sintetizador` e escolha o preset `Lead serra` (mono, glide de 60 ms).
2. No cartão `GERAL`, `Alcance do bend` **2 st** (o padrão) e `Vibrato da roda` **0,5 st** (botão direito no knob para digitar `0,5 st`). Com a roda toda para cima o vibrato terá ±0,5 st a 5,5 Hz; a 60% da roda, ±0,3 st (30 cents), que é um vibrato de cantor.
3. Abra o clipe (dois cliques num espaço vazio da faixa, um compasso) e escreva com a grade `1/4`: `A4` no tempo 0, `C5` no tempo 1 e `E5` no tempo 2 com duração de 2 tempos (arraste a direita da nota).
4. Troque a grade para `1/32`. Na faixa de baixo do editor, toque no canto e escolha `Pitch bend`.
5. Scoop: com o lápis, arraste na faixa do tempo 2 (início do `E5`) até o tempo 2,5, do **fundo** da faixa (-1, o balão mostra `-2.00 st`) até o **meio** (o balão mostra `+0.00 st`; o meio "atrai", então soltar perto dele dá zero exato). A nota nasce dois semitons abaixo (ré) e sobe até o mi em meio tempo.
6. Escolha `Modulação`. Marque o item `Linha reta (ou Shift)` no menu do canto (ou segure `Shift`) e arraste do tempo 2,5 no **fundo** (0%) até o tempo 3,5 a cerca de **60%** (o balão mostra `60%` ou perto). O vibrato cresce ao longo de um tempo.
7. Não é preciso devolver a roda a zero no fim: ao chegar ao fim do clipe o motor leva o bend e a modulação ao repouso. Só se o clipe continuar com mais notas depois do `E5` vale pôr um ponto em 0% (um clique no fundo da faixa `Modulação`) logo após o fim da nota.
8. Toque (`Espaço`). Se o vibrato passar do ponto, arraste os pontos mais altos para baixo (ferramenta mover) ou use `Limpar modulação` no menu do canto e refaça.

Variações:

- **FM:** o preset `Lead FM` (mono, `Glide` 60 ms, `Vibrato` 0,25 st) aceita a mesma receita: os operadores partem de uma frequência só, então o timbre se mantém no bend (não confirmado ao ouvido). Ponha `Vibrato da roda` em 0,4 st, já que o preset traz vibrato de LFO.
- **Wavetable:** `Lead PWM` (mono, `Glide` 50 ms). O bend não mexe na `Posição`, então o PWM continua igual enquanto a nota sobe.
- **Efeitos:** na aba `Efeitos`, `Delay` com `Nota` `1/8D`, `Mistura` 25% e `Realimentação` 35%, e `Reverb` preset `Sala` (`Mistura` 22%). Os efeitos vêm depois do instrumento, então os ecos repetem o scoop e o vibrato.
- **Automação:** para o brilho abrir junto do vibrato, no botão `A` da faixa escolha o submenu do instrumento, cartão `FILTRO`, `Corte` (a raia se chama `Filtro · Corte`) e ponha dois pontos: um no tempo 2 do compasso do clipe e outro meio compasso depois, mais alto.

Por que funciona: o bend e a roda mexem só na afinação; o scoop dura meio tempo (250 ms), então soa como ataque, e o vibrato entrando devagar imita o cantor que "abre" a nota. Vibrato constante desde o início soa mecânico.

Se der errado:

- *O bend dá degraus audíveis:* a grade estava em `1/16` ou `Livre` (passo de 0,25 tempo). Volte para `1/32` e redesenhe.
- *A nota não muda de altura:* confira `Alcance do bend` (0 desliga) e se a faixa é de `Bateria`.
- *Não há vibrato:* `Vibrato da roda` em 0, ou os pontos de `Modulação` caíram fora do clipe (a parte escurecida da faixa não toca).

### Receita 2: pedal de sustain em acordes de teclado

Resultado: quatro acordes de um compasso que ressoam juntos e se limpam na hora da troca, como um pianista com o pé no pedal.

1. Crie uma faixa `Sintetizador` e escolha `Teclado (EP)` (categoria `Teclas`: decaimento de 1,8 s, sustentação 25%). Confirme `Vozes` em 8 ou mais: as notas seguradas pelo pedal ocupam voz até ele subir.
2. Abra o clipe e estique o fim dele para o compasso 5 (16 tempos). Em `Ferramentas > Escala e acordes > Escala…`, `Tônica` `C` e `Escala` `Maior`, `Aplicar`.
3. `Ferramentas > Escala e acordes > Acorde no clique`, `Tipo` `Diatônico: tríade`, `Usar no clique`. Ponha `Nota:` em `1/4` (a duração da nota nova) e a grade em `1/4`.
4. Com o Lápis, clique `C4` no tempo 0, `A3` no tempo 4, `F3` no tempo 8 e `G3` no tempo 12. Saem `C4 E4 G4`, `A3 C4 E4`, `F3 A3 C4` e `G3 B3 D4`, cada um com uma batida de duração (curtas de propósito).
5. Toque agora (`Espaço`): cada acorde some em uma batida. Aí entra o pedal.
6. Grade `1/16`. Na faixa de baixo, escolha `Sustain`. Arraste do tempo 0 ao 3,75, depois do 4 ao 7,75, do 8 ao 11,75 e do 12 ao 15,75: cada arraste pinta um trecho com o pedal embaixo (o balão diz `Pedal embaixo`). Ficam pontos de descida em 0, 4, 8 e 12 e de subida em 3,75, 7,75, 11,75 e 15,75.
7. Toque de novo: cada acorde ressoa por quase quatro tempos no nível de `Sustentação` (25%) e é solto um quarto de tempo antes do seguinte, sem misturar com ele.

Variações:

- **Repetir notas com o pedal:** selecione as notas e use `Ctrl+D` (ou `Ctrl+C` e `Ctrl+V` em outro ponto): os pontos de pedal (e de bend e modulação) que caem entre o começo da primeira nota e o fim da última vão junto. Cuidado: o trecho termina onde a última nota selecionada termina. Se o pedal solta depois disso (como aqui, em que cada acorde dura uma batida e o pedal quase quatro), a cópia leva um ponto de subida no fim do trecho e o pedal da cópia sobe antes do original. Para copiar o pedal inteiro, estique as notas até o fim do trecho do pedal ou redesenhe o pedal na cópia (testado só por testes automáticos).
- **Sem reta no pedal:** o menu do canto do `Sustain` não oferece `Linha reta (ou Shift)`; o pedal só se pinta.
- **Pedal "tardio":** feche cada trecho já no tempo do acorde seguinte (sem o quarto de tempo de folga) para uma mistura leve dos acordes, tipo pedal de igreja. Mova os pontos de subida com a ferramenta mover.
- **Sampler ou Wavetable:** o mesmo pedal vale para um `Sampler` com áudio de piano e para `Teclas de cristal` da wavetable.
- **FM:** `Sino elétrico` com o pedal deixa as notas se misturarem em campainhas; as solturas longas do preset já fazem isso, então reduza o trecho do pedal.
- **Reverb:** `Reverb` preset `Sala` (`Mistura` 22%, `Decaimento` 1,4 s) depois do pedal dá espaço sem lama, porque o pedal já limpa a cada troca.

Por que funciona: com o pedal embaixo, o motor não entrega o fim da nota ao instrumento: a altura fica pendente. Quando o pedal sobe, todas as notas pendentes saem de uma vez e entram na `Soltura` do instrumento. Por isso a subida do pedal é o "corte" do acorde, e por isso a subida vem um quarto de tempo antes da descida seguinte.

Se der errado:

- *As notas não seguram:* a faixa é de `Bateria` (não tem pedal) ou o pedal foi pintado fora do clipe.
- *Acordes se misturam:* o trecho passou do acorde seguinte; encurte-o (mova o ponto de subida).
- *Falta nota no fim:* faltam vozes; suba `Vozes`.

### Receita 3: queda de altura desenhada e automatizada

Resultado: uma nota de wavetable que cai duas oitavas em três tempos enquanto o filtro fecha, tipo laser ou "sirene morrendo".

1. Crie uma faixa `Wavetable` e escolha `Lead PWM` (mono, `Glide` 50 ms). No cartão `GERAL`, `Alcance do bend` **24 st** (o máximo): o fundo da faixa de bend passa a valer -24 st, duas oitavas.
2. No editor, uma nota `G4` no tempo 0 com duração de 4 tempos (o clipe de um compasso).
3. Grade `1/16`. Na faixa de baixo, escolha `Pitch bend`.
4. Marque `Linha reta (ou Shift)` no menu do canto. Arraste do **meio** da faixa no tempo 1 (o balão mostra `+0.00 st`) até o **fundo** no tempo 4 (o balão termina em `-24.00 st`). A reta põe 13 pontos, um a cada 1/4 de tempo; a nota fica em `G4` no primeiro tempo e cai até `G2` no fim.
5. Para uma curva em vez de reta, desmarque `Linha reta`, ponha a grade em `1/32` e passe o ponteiro pelo desenho que quiser (lento no começo, rápido no fim, por exemplo); depois mova os pontos que destoarem e apague os que sobrarem com o botão direito.
6. Automação do filtro: no cabeçalho da faixa, botão `A`, o submenu do instrumento (`Wavetable`), cartão `FILTRO`, `Corte` (a raia chama `Filtro · Corte`). Ponha um ponto no começo do clipe, alto (perto de 5,50 kHz), e outro no fim, baixo (perto de 800 Hz): o filtro fecha junto da queda.
7. Efeito: na aba `Efeitos`, `Delay` com `Nota` `1/8D`, `Realimentação` 45%, `Passa-baixa` 3 kHz e `Mistura` 30%. Cada eco repete a queda e fica mais escuro.

Variações:

- **Subida (riser):** com o mesmo `Alcance do bend` de 24 st, desenhe a reta do **meio** ao **topo** (+24 st) e abra o `Corte` na automação.
- **Escalar o tempo:** selecione a nota e use `Ferramentas > Escalar o tempo > ×2 (dobro)`: os pontos do bend são escalados junto e a queda dura o dobro; estique o clipe para dois compassos depois. A automação do filtro, que é da faixa, não muda: refaça-a.
- **FM:** um `Lead FM` com `Alcance do bend` 24 st cai do mesmo jeito. Automatizar o `Nível` de um modulador (ver [FM e Wavetable na prática](fm-e-wavetable-na-pratica.md)) faz o timbre "morrer" durante a queda.

Por que funciona: a curva de bend é um dado do clipe; a automação é um dado da faixa. As duas andam no tempo do arranjo, mas só a primeira acompanha o clipe se você o mover, cortar ou duplicar. Uma queda que precisa repetir junto da nota fica melhor como bend; um filtro que fecha ao longo da música, como automação.

Se der errado:

- *A queda para na metade:* o `Alcance do bend` ficou em 2 st; suba para 24.
- *A queda soa em degraus:* a grade estava em `1/16` ou `Livre` (um ponto a cada 0,25 tempo, que são 125 ms a 120 bpm); use `1/32`.
- *Sobra bend depois da nota:* se o clipe continua com outras notas, ponha um ponto em zero logo depois do fim da queda (o motor só devolve ao repouso no fim do clipe).
- *O filtro não fecha:* a automação foi criada na faixa errada ou os dois pontos ficaram na mesma altura.

### Receita 4: gravar com um teclado MIDI de verdade

Resultado: uma frase gravada com bend, modulação e pedal, limpa e pronta para editar.

1. Conecte o teclado e, no painel do instrumento, clique no ícone USB (tooltip `Tocar com um teclado MIDI`) ou no cabo da barra de ferramentas (`Entrada MIDI: ligar teclado ou controlador`) e aceite a permissão do navegador. O tooltip passa a listar o aparelho.
2. Crie uma faixa `Sintetizador`, escolha `Lead serra`, e **arme** a faixa (`Armar para gravar`). Deixe `Alcance do bend` em 2 st (o padrão; a maioria dos teclados usa ±2 st) e `Vibrato da roda` em 0,5 st. O jopendaw **não** lê a mensagem de alcance do bend do controlador: o alcance é o do knob (não confirmado com um aparelho real).
3. Aperte `R`, espere o compasso de contagem e toque: uma nota longa mexendo a roda de bend, uma frase levantando a roda de modulação e um acorde com o pedal embaixo. Tudo o que você fizer na contagem fica de fora.
4. Aperte `R`, espaço ou `Enter` para parar. As notas e os pontos caem num clipe novo. Abra-o no editor: no canto da faixa de baixo, escolha `Pitch bend`, `Modulação` e `Sustain` e veja o que veio; o rótulo diz quantos pontos há (`N pontos`).
5. Limpeza: o motor já afinou a gravação (no máximo um ponto a cada 1/48 de tempo por controle, sem repetir valor, o pedal só nas mudanças). Se restou um tremor que você não quer, use `Limpar modulação` e redesenhe com a reta, ou apague pontos soltos com o botão direito.
6. Regravar só o pedal: ponha o cursor no começo do clipe, arme a mesma faixa e grave só o pedal por cima (sem tocar notas). O pedal novo substitui os pontos de pedal do trecho gravado; as notas e o resto ficam. Com um clipe sob o cursor, os pontos entram nele; sem clipe, nasce um clipe novo, sem notas, só com os pontos.
7. Se o pedal estava embaixo, o bend fora do centro ou a roda levantada quando você parou, o clipe ganha um ponto de retorno ao repouso na parada (pedal solto, bend no centro, modulação em zero), e o clipe não toca o resto com o pedal preso.

Variações:

- **Sem teclado MIDI:** as duas rodas do teclado da tela (bend com mola e modulação sem mola) gravam do mesmo jeito, em faixa armada, com a mesma resolução do teclado MIDI. Não há pedal na tela.
- **Parar e trocar de faixa.** Parar (`Enter`) ou pausar (`Espaço`) solta o pedal e leva o bend e a roda ao centro, seja do teclado MIDI ou das rodas da tela (elas voltam ao zero sozinhas). Se você muda de faixa com o pedal embaixo, a faixa antiga volta ao repouso, então um pedal segurado antes da troca não fica preso lá `(testado só por testes automáticos)`.
- **FM e wavetable:** funcionam igual; no FM o bend afina os quatro operadores juntos.
- **Em loop:** ligue o loop e grave várias passadas para as notas; só a última passada vale para os controles.

Por que funciona: o motor registra bend, modulação e pedal com a batida exata em que os aplicou, do mesmo jeito que as notas. O app os transforma em pontos do clipe (os mesmos que você desenha nas receitas anteriores), então gravar e desenhar são dois jeitos de escrever o mesmo dado.

Se der errado:

- *Não gravou controle nenhum:* a faixa estava desarmada, o teclado mandou os controles em outro número (só pitch bend, `CC 1` e `CC 64` são lidos), ou você mexeu nas rodas durante a contagem.
- *A roda de modulação estava alta antes de gravar e o clipe começou sem ela:* só o que muda depois do começo da gravação entra (não confirmado); mexa a roda depois do primeiro tempo.
- *O clipe ficou cheio de pontos:* o teclado pode mandar centenas de valores por segundo; passe a `Limpar` e redesenhe, ou apague trechos.

## Se der errado (geral)

- **Nada muda de altura em nenhuma faixa:** confira se a faixa é de instrumento com afinação e não `Bateria`, e o `Alcance do bend` (0 desliga).
- **Vibrato sem parar depois de tocar com a roda da tela:** a roda de modulação não tem mola: leve-a até embaixo. Parar ou pausar o transporte também a devolve ao zero.
- **Depois de mover ou dividir notas no editor, a curva ficou no lugar antigo:** os pontos não acompanham notas que mudam de lugar (só `Escalar o tempo`, `Inverter no tempo` e a cópia com `Ctrl+C`/`Ctrl+V`/`Ctrl+D` os levam); mova os pontos também.
