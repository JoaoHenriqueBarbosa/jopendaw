# Sintetizador FM

> Instrumento de 4 operadores senoidais que se modulam entre si: serve para sinos, pianos elétricos, marimbas, baixos metálicos, órgãos e pads de vidro, sons que um sintetizador subtrativo faz com dificuldade.

## Onde fica

1. Crie a faixa: na linha do tempo, botão `+` com tooltip `Nova faixa` → item `FM` (no mixer, o botão com tooltip `Nova faixa ou barramento` tem o mesmo item). A faixa nasce com o instrumento no padrão, e o seletor de presets mostra `Inicial`. Na lista de faixas, no mixer e na aba `Instrumento`, a faixa FM usa o ícone `hub` do Material (nós ligados).
2. Abra o painel: aba `Instrumento` da barra do painel inferior (tooltip `Instrumento da faixa (I)`), com a faixa FM selecionada.
3. No computador os cartões ficam numa fileira com rolagem horizontal (a roda do mouse rola a fileira quando o ponteiro não está sobre um knob). No celular os cartões quebram em linhas e o painel rola na vertical.

Os cartões, da esquerda para a direita: `Algoritmo`, `Operador 1`, `Operador 2`, `Operador 3`, `Operador 4`, `LFO` e `Geral`. O cabeçalho (presets, teclado) e os gestos dos knobs são comuns a todos os instrumentos e estão em [Painel de instrumento](04-painel-de-instrumento.md).

## FM em linguagem de gente

Imagine um vibrato: você balança a altura de uma nota para cima e para baixo, umas 5 vezes por segundo. Agora acelere esse balanço até algumas centenas de vezes por segundo. Você deixa de ouvir "uma nota balançando" e passa a ouvir uma nota com **outro timbre**: mais brilhante, mais metálica, às vezes com sons que nem parecem soar na nota tocada. Isso é síntese FM (modulação de frequência).

Os nomes que o painel usa:

- **Operador**: uma senoide com envelope próprio (volume que sobe e desce no tempo). São 4, e o painel mostra um cartão para cada. Todo operador é sempre uma senoide pura; o timbre vem de quem balança quem.
- **Portador**: o operador que você **ouve**. Vai para a saída. No painel, o cartão diz `PORTADOR` e o círculo no desenho do algoritmo é cheio.
- **Modulador**: o operador que **balança a altura de outro** e não se ouve sozinho. O cartão diz `MODULADOR` e o círculo é vazado.
- **Razão** (`Razão`): a frequência do operador em múltiplos da nota tocada. Razão 1 = a própria nota; 2 = uma oitava acima; 3 = uma oitava e uma quinta acima; 0,5 = uma oitava abaixo. Razões inteiras (1, 2, 3, 4...) dão timbres "afinados", como cordas, órgãos e pianos elétricos. Razões quebradas (3,5, 1,41, 2,76...) dão timbres sem altura definida, como sinos, gongos e barras metálicas.
- **Índice de modulação**: quanto o modulador balança o portador. Aqui é o `Nível` do operador **quando ele é modulador** (o mesmo botão vira volume quando o operador é portador). Índice baixo: som quase senoidal. Índice alto: muito brilho, cada vez mais "áspero". O máximo (100%) equivale a um desvio de fase de cerca de 7,9 radianos.
- **Realimentação** (`Realimentação`): o operador 1 modulando a si mesmo. Com pouca, a senoide vira algo parecido com uma serra; com muita, vira ruído colorido.

O truque que faz o FM soar "vivo": o brilho depende do **envelope do modulador**. Se o modulador cai rápido e o portador segue soando, a nota começa brilhante e "assenta" numa senoide macia, que é o "toc" da tecla de um piano elétrico ou da baqueta numa marimba.

## Controles

### Cartão `Algoritmo`

O algoritmo é o mapa de quem modula quem. Há 8, mostrados como 8 miniaturas clicáveis (em duas fileiras de 4 quando o cartão é estreito). Cada miniatura tem tooltip `Algoritmo N: roteamento`. Nos desenhos: círculo cheio = portador (sai o som), círculo vazado = modulador, seta = "modula". Um pequeno laço em cima do operador 1 aparece na miniatura selecionada quando a realimentação é maior que 0.

| Controle (rótulo exato) | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| 8 miniaturas `Algoritmo 1` a `Algoritmo 8` | Escolhe o roteamento dos operadores. Entra no desfazer. | 8 opções; padrão `Algoritmo 5: (1→2) + (3→4)` | Trocar com nota soando faz um fade de cerca de 4 ms (sem estalo); o roteamento muda no silêncio do fade. |
| `Realimentação` | Quanto o operador 1 modula a própria fase. Vale em todos os algoritmos. | 0–100%, padrão 0%, linear | A realimentação usa a saída do operador 1 (o `Nível` dele vezes o envelope), então com `Nível` baixo ela quase some. No máximo o desvio é de cerca de 3,8 radianos. |

Os 8 algoritmos (`[n]` = modulador, `(n)` = portador; a seta aponta para quem é modulado):

**Algoritmo 1: `1→2→3→4`**, cadeia inteira.

```
 [1]
  ↓
 [2]
  ↓
 [3]
  ↓
 (4)  → saída
```

Um só portador (4), modulado por uma cadeia de três moduladores. É o mais brilhante e agressivo, com espectro denso. Serve para baixos, metais e sons "de DX". `Nível` dos operadores 1 a 3 é índice; só o `Nível` do 4 é volume.

**Algoritmo 2: `(1+2)→3→4`**, dois moduladores em paralelo.

```
 [1]   [2]
   ↘   ↙
    [3]
     ↓
    (4)
```

1 e 2 modulam juntos o 3; o 3 modula o 4. Timbres complexos, com dois "sabores" de modulação somados: metais, leads.

**Algoritmo 3: `(1 + 2→3)→4`**, um modulador direto e outro em cadeia.

```
 [2]
  ↓
 [3]   [1]
   ↘   ↙
    (4)
```

O 4 é modulado ao mesmo tempo pelo 1 (direto) e pelo 3 (que, por sua vez, é modulado pelo 2). Bom para ataques com "estalo" separado do corpo, como baixo slap.

**Algoritmo 4: `(1→2 + 3)→4`**, um par mais um modulador solto.

```
 [1]
  ↓
 [2]   [3]
   ↘   ↙
    (4)
```

O 1 modula o 2; o 2 e o 3 modulam juntos o 4. Ataque estalado e corpo curto, como clavinet.

**Algoritmo 5: `(1→2) + (3→4)`**, dois pares independentes (padrão).

```
 [1]   [3]
  ↓     ↓
 (2)   (4)
```

Dois portadores (2 e 4), cada um com o seu modulador; as saídas somam. É o algoritmo dos pianos elétricos, sinos, marimbas e vibrafones: um par dá o corpo e o outro dá a batida metálica do ataque.

**Algoritmo 6: `1→(2 + 3 + 4)`**, um modulador para três portadores.

```
     [1]
   ↙  ↓  ↘
 (2) (3) (4)
```

O 1 modula os três ao mesmo tempo, então o brilho é comum a todos, enquanto cada portador tem razão, afinação fina e envelope próprios. É o algoritmo de cordas e pads: desafinar levemente os três (`Fino`) dá o efeito de coro.

**Algoritmo 7: `(1→2) + 3 + 4`**, um par e duas senoides puras.

```
 [1]
  ↓
 (2)   (3)   (4)
```

O 2 é modulado pelo 1; o 3 e o 4 soam como senoides puras (ninguém os modula), somadas ao par. Bom para sons inarmônicos em camadas, como gongos: um timbre complexo mais duas "cores" limpas.

**Algoritmo 8: `1 + 2 + 3 + 4`**, aditivo.

```
 (1)   (2)   (3)   (4)
```

Sem modulação nenhuma: quatro senoides somadas. Com razões 0,5, 1, 2 e 4 vira um órgão de 4 barras (drawbars). Aqui a realimentação ainda age sobre o operador 1.

Quando há mais de um portador o motor compensa o volume para que a troca de algoritmo não mude muito o nível (fator 0,7 no algoritmo 5, 0,58 nos algoritmos 6 e 7, 0,5 no 8). O algoritmo é uma escolha por faixa e é salvo com o projeto.

### Cartões `Operador 1` a `Operador 4`

Cada cartão tem: título com o papel do operador neste algoritmo (`PORTADOR` ou `MODULADOR`, no canto), um desenho do envelope com a legenda (`×1.00  nível 80%`, razão e nível atuais), 8 knobs e uma fileira de atalhos de razão. O cartão inteiro fica esmaecido quando o `Nível` do operador é 0% (esmaecido não é desligado: os knobs continuam mexíveis).

| Controle (rótulo exato) | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| `Razão` | Frequência do operador = nota × razão. | 0,25–16, escala logarítmica. Padrão 1 (operador 3: 14) | Inteiros dão timbre afinado; quebrados dão timbre de sino. Em notas agudas, razões altas passam de 40% da taxa de amostragem (perto de 20 kHz) e o operador some num fade, em vez de dobrar e soar como outra nota. |
| `Fino` | Ajuste fino sobre a razão, em cents (centésimos de semitom). | −100 a +100 ct, padrão 0 | Desafinar 5 a 6 ct entre portadores dá coro (`Cordas FM`). Em moduladores, dá batimento e movimento ao timbre. |
| `Nível` | No portador: volume do operador. No modulador: índice de modulação (brilho). | 0–100%. Padrões: operador 1 = 50%, 2 = 80%, 3 = 30%, 4 = 70% | O índice é limitado suavemente nas notas agudas para o espectro caber na banda de áudio: o timbre escurece nas notas altas, não dobra. |
| `Ataque` | Tempo para o operador subir de 0 a 100%. Subida linear. | 0,5 ms–10 s, log. Padrão 1,0 ms em todos | Ataque lento no modulador abre o brilho depois do volume (`Metais`). |
| `Decaimento` | Tempo para cair de 100% até a `Sustentação`. Queda exponencial (o tempo vale para cerca de 99,9% do percurso). | 1 ms–10 s, log. Padrões: op. 1 = 600 ms, op. 2 = 1,20 s, op. 3 = 150 ms, op. 4 = 1,00 s | Decaimento curto no modulador = "toc" no ataque. |
| `Sustentação` | Nível mantido enquanto a tecla está presa. | 0–100%. Padrões: op. 1 = 0%, op. 2 = 30%, op. 3 = 0%, op. 4 = 20% | Com 0% em todos os portadores a nota some mesmo com a tecla presa (som de pluck, tipo piano e marimba). |
| `Soltura` | Tempo para o operador cair a zero depois de soltar a tecla. Queda exponencial. | 1 ms–10 s, log. Padrões: op. 1 = 300 ms, op. 2 = 300 ms, op. 3 = 150 ms, op. 4 = 300 ms | A nota só termina quando **todos os portadores** terminam a soltura. |
| `Sens. vel.` | Quanto a velocidade (força) da nota mexe no nível deste operador. | 0–100%. Padrões: op. 1 = 50%, op. 2 = 30%, op. 3 = 50%, op. 4 = 30% | Em modulador, mexe no brilho (tocar forte fica mais brilhante); em portador, mexe no volume. Com 0% o operador ignora a velocidade (usado nos órgãos). A resposta é quadrática: meia velocidade com 100% dá um quarto do nível. |

Os desenhos de envelope de cada cartão **só mostram** o formato (subida linear, queda exponencial, tempos em escala logarítmica para caber 1 ms e 10 s no mesmo desenho, pontos brancos nos cantos). Eles **não são arrastáveis**: para mudar o envelope, use os knobs `Ataque`, `Decaimento`, `Sustentação` e `Soltura` do mesmo cartão. O desenho acompanha os knobs na hora.

Fileira de atalhos de razão (embaixo de cada operador): 7 botões de toque com os textos `×0.5`, `×1`, `×2`, `×3`, `×4`, `×5` e `×7`. Tocar num deles põe esse valor no `Razão` do operador (entra no desfazer). O botão da razão atual fica aceso. O `Fino` não é alterado.

### Cartão `LFO`

O LFO é um oscilador lento que mexe em três coisas ao mesmo tempo, cada uma com sua profundidade. Há **um LFO só por faixa**, livre (em Hz, sem sincronia com o andamento) e compartilhado por todas as notas: ele não recomeça a cada nota. Com as três profundidades em 0 o cartão fica esmaecido com a legenda `sem efeito: vibrato, tremolo e brilho em 0`, e `Onda` e `Taxa` ficam apagados.

| Controle (rótulo exato) | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| `Onda` | Forma do LFO (menu). | `Senoide`, `Triângulo`, `Serra`, `Quadrada`, `Aleatório` (degraus aleatórios). Padrão `Senoide` | `Aleatório` sorteia um valor novo a cada ciclo. |
| `Taxa` | Frequência do LFO. | 0,05–30 Hz, log, padrão 5,00 Hz | Vibrato natural: 4 a 6 Hz. Respiração lenta de brilho: 0,2 a 0,4 Hz. |
| `Vibrato` | Quanto o LFO balança a altura (todos os operadores juntos, então a razão entre eles se mantém). | 0–12 st, padrão 0 | Vibrato musical: 0,1 a 0,3 st. |
| `Tremolo` | Quanto o LFO balança o volume final. | 0–100%, padrão 0% | Com 100% o volume oscila entre cheio e mudo. |
| `Brilho` | Quanto o LFO balança o índice de modulação, ou seja, o brilho. Multiplica o índice de todos os moduladores por 1 ± profundidade. | 0–100%, padrão 0% | Pads que "respiram": `Cordas FM` usa 25% a 0,35 Hz. Não mexe na realimentação. |

### Cartão `Geral`

O visor do cartão diz `Mono · legato` ou `Poli · N vozes` e, embaixo, `Glide` com o tempo (só em mono) ou `Algoritmo N`.

| Controle (rótulo exato) | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| `Vozes` | Máximo de notas ao mesmo tempo. Com 1 vira mono com legato (a nota nova segue a anterior sem recomeçar os envelopes se a anterior ainda estiver presa). | 1–16, padrão 8 | Baixos e leads: 1. Passando do limite, sai num fade de 5 ms a mais baixa entre as notas já soltas ou, se todas estão presas, a mais antiga. |
| `Glide` | Tempo de deslizar de uma nota para a próxima. | 0–2 s, padrão 0. Esmaecido quando `Vozes` é maior que 1 | Lead com 40 a 80 ms de glide. Só o modo mono está sinalizado no painel; ver "Limites e pegadinhas". |
| `Volume` | Volume de saída do instrumento. | 0–150%, padrão 70% | Vem antes dos efeitos e do fader da faixa. |

Não há filtro, ruído, uníssono, sub ou controle de estéreo no FM. A saída do instrumento é mono (a mesma voz nos dois lados); a largura vem de efeitos como Chorus e Reverb (veja [Combina com](#combina-com)).

### Presets do FM

O seletor de presets (tooltip `Presets`, com as setas `Anterior (preset)` e `Próximo (preset)` no computador) lista 15 presets em 7 categorias. Aplicar um preset **substitui todos os parâmetros** do instrumento: o que o preset não cita volta ao padrão (inclusive `Volume`, `Vozes` e o LFO). É um passo só no desfazer. Depois de mexer num knob o seletor mostra o nome do preset seguido de `(editado)`. Presets próprios: `Salvar como preset…` (seção `MEUS PRESETS`, no fim do menu) guarda todos os parâmetros do FM (algoritmo, os quatro operadores, LFO e `Geral`) com um nome, para chamar em qualquer faixa FM deste aparelho; ver [Meus presets](04-painel-de-instrumento.md#meus-presets). Sem isso, o trabalho fica salvo com o projeto, nos knobs.

Os números de algoritmo abaixo são os do painel (`Algoritmo 1` a `8`).

**Teclas**

| Preset | Algoritmo | Caráter |
|---|---|---|
| `Piano elétrico` | 5 | Corpo em 1:1 com decaimento de 1,6 a 3,2 s e um par de "batida" com razão 14 que morre em 90 ms. Tocar forte deixa a batida mais presente. Todas as sustentações em 0%. |
| `Clavinet` | 4 | Realimentação 20%, razões 3, 1, 2 e 1, soltura curta (80 ms). Ataque estalado e corpo seco. |

**Percussivos**

| Preset | Algoritmo | Caráter |
|---|---|---|
| `Sino elétrico` | 5 | Moduladores (operadores 1 e 3) com razões 3,5 e 7, inarmônicas, sobre portadores (operadores 2 e 4) de razão 1 e 2; decaimentos de 1 a 4 s e soltura longa (0,5 a 1,5 s), então as notas se misturam. Sino tipo DX. |
| `Marimba` | 5 | Modulador 4× cai em 60 ms (o "toc" da baqueta); segundo par soma o modo superior da barra (razão 10, 30 ms). Notas curtas. |
| `Vibrafone` | 5 | Como a marimba, com decaimento de 3,5 s e `Tremolo` 45% a 5,2 Hz (o motorzinho do vibrafone). |
| `Harpa` | 5 | Razões 2, 1, 3, 2: corda dedilhada, decaimento em torno de 1 s. |

**Baixos** (mono, `Vozes` 1)

| Preset | Algoritmo | Caráter |
|---|---|---|
| `Baixo DX` | 1 | Cadeia completa com realimentação 15%: o baixo clássico de DX, cheio e um pouco áspero. |
| `Baixo slap` | 3 | Realimentação 30%; os moduladores decaem em 80 a 200 ms e fazem o estalo do polegar, o portador (operador 4) segura o corpo. |

**Metais**

| Preset | Algoritmo | Caráter |
|---|---|---|
| `Metais` | 2 | Ataques de 40 a 60 ms nos quatro operadores: o brilho abre junto com o volume, como um sopro. `Sens. vel.` de 80% nos operadores 1 e 2. |
| `Gongo` | 7 | Razões de gongo (1,41 / 1 / 2,76 / 5,4), realimentação 40%, decaimentos de 1,5 a 5 s, solturas de 2 a 3 s. Metal inarmônico que demora a morrer. |

**Órgãos**

| Preset | Algoritmo | Caráter |
|---|---|---|
| `Órgão drawbar` | 8 | Razões 0,5, 1, 2 e 4 (as barras 16', 8', 4' e 2'), sustentação 100%, `Sens. vel.` 0%, realimentação 10% e `Tremolo` 25% a 6,5 Hz (o rotary). |
| `Órgão rock` | 8 | Razões 1, 2, 3 e 4 com realimentação 35%, que suja o operador 1 e dá a mordida. |

**Pads**

| Preset | Algoritmo | Caráter |
|---|---|---|
| `Cordas FM` | 6 | Um modulador comum para três portadores levemente desafinados (+6 ct, −6 ct e razão 2); ataques de 450 a 700 ms; `Brilho` 25% a 0,35 Hz. |
| `Pad vidro` | 5 | Razões 5 e 7 nos moduladores, portadores desafinados ±5 ct, ataques de 0,6 a 0,9 s; `Brilho` 35% a 0,25 Hz. Timbre de vidro, frio e brilhante. |

**Leads**

| Preset | Algoritmo | Caráter |
|---|---|---|
| `Lead FM` | 2 | Mono, `Glide` 60 ms, realimentação 50% e `Vibrato` 0,25 st a 5,5 Hz. Lead cortante de DX. |

## Passo a passo

**1. Tocar um som pronto**
1. Crie a faixa `FM` e abra a aba `Instrumento`.
2. Abra o seletor de presets e escolha `Piano elétrico` (ou use as setas para percorrer a lista).
3. Toque no teclado da tela, no do computador (botão de teclado do cabeçalho) ou num teclado MIDI. Desfaça com `Ctrl+Z` (`Cmd+Z` no Mac) se não gostar (o preset é um passo do desfazer).

**2. Fazer um sino do zero a partir do padrão**
1. Deixe o `Algoritmo 5: (1→2) + (3→4)` (o padrão).
2. No `Operador 1` (modulador), toque em `×3` nos atalhos e digite `3.5` no `Razão` (botão direito no knob, ou toque longo no celular): 3,5 é inarmônico.
3. No `Operador 3`, deixe a razão em 14 ou troque por `×7`. No `Operador 2` e no `Operador 4`, ponha `Razão` 1 e 2.
4. Ponha a `Sustentação` dos quatro operadores em 0% e o `Decaimento` dos portadores (2 e 4) em 2 a 4 s. Aumente a `Soltura` dos portadores para 1 s.
5. Aumente o `Nível` do operador 1 aos poucos: mais índice, mais metálico.

**3. Baixo com ataque estalado**
1. Escolha o `Algoritmo 1` (cadeia).
2. Ponha `Vozes` em 1 no cartão `Geral`.
3. Nos operadores 1 a 3 (moduladores), deixe o `Decaimento` entre 150 e 400 ms e a `Sustentação` baixa (0 a 20%). O ataque fica brilhante e depois "assenta".
4. No operador 4 (portador), `Nível` 85%, `Sustentação` 60%.
5. Se ficar áspero demais, abaixe a `Realimentação` ou o `Nível` do operador 2.

**4. Um pad que respira**
1. Escolha o `Algoritmo 6: 1→(2 + 3 + 4)`.
2. Nos operadores 2 e 3 use `Fino` de +6 ct e −6 ct, e `Ataque` de 0,5 s ou mais nos três portadores.
3. No cartão `LFO`, `Taxa` 0,3 Hz e `Brilho` 25%.

**5. Trocar de algoritmo mantendo o som**
1. Anote os valores dos operadores. Os operadores mantêm seus parâmetros na troca; o que muda é o papel de cada um.
2. Um operador que era portador vira modulador: o `Nível` dele deixa de ser volume e passa a ser brilho. Reajuste-o.

## Combina com

- [Painel de instrumento](04-painel-de-instrumento.md): presets, teclado da tela, MIDI e gestos dos knobs.
- [Sintetizador subtrativo](04a-sintetizador.md): para o que precisa de filtro, uníssono e ruído. FM e subtrativo se complementam: FM é ótimo para timbres metálicos e percussivos; subtrativo, para pads e baixos "gordos".
- [Wavetable](04e-wavetable.md): outro sintetizador de timbres "digitais", morfando entre formas de onda em vez de modular a frequência.
- [Painel de efeitos](06c-painel-de-efeitos.md) e [Referência dos efeitos](06d-efeitos-referencia.md): como o FM sai em mono, `Chorus` (por exemplo o preset `Ensemble`) e `Reverb` dão largura e ambiente; `Delay` funciona bem em leads.
- [Automação](07-automacao.md): todos os knobs do FM podem ser automatizados. `Nível` de um modulador automatizado abre e fecha o brilho no tempo; `Realimentação` também.
- [Piano roll](05-piano-roll.md): a velocidade das notas mexe no timbre quando o `Sens. vel.` do operador é maior que 0%.
- Guia: [FM e Wavetable na prática](../guias/fm-e-wavetable-na-pratica.md).

## Limites e pegadinhas

- **Sem forma de onda escolhível**: todo operador é uma senoide. Não existe filtro, ruído nem uníssono no FM.
- **Saída mono**: o instrumento envia a mesma voz para os dois lados. Para abrir o estéreo use Chorus, Reverb ou Delay em ping-pong; a `Largura` do Utilitário não ajuda aqui, porque ela age na diferença entre os lados (S), que é zero quando os dois lados são iguais.
- **O `Nível` muda de significado** conforme o papel do operador no algoritmo. Ao trocar de algoritmo, um operador que virou modulador pode soar de repente muito brilhante.
- **Sustentação 0% é "pluck"**: se todos os portadores têm `Sustentação` 0%, a nota decai até o silêncio mesmo com a tecla presa, e a voz nem é calculada depois disso. Para notas longas suba a `Sustentação` de pelo menos um portador.
- **Notas agudas escurecem** (o índice é limitado para não gerar aliasing) e operadores com frequência acima de 40% da taxa de amostragem somem. Não é defeito: é o anti-aliasing do motor.
- **`Glide` esmaecido com `Vozes` maior que 1**: o painel só trata o glide como ativo no modo mono. Pelo código do motor, com `Glide` maior que 0 uma voz nova também parte da altura da nota anterior no modo poli (não confirmado ao ouvido). Para ter certeza de como vai soar, use `Vozes` 1.
- **O LFO é um só e não recomeça a cada nota**: duas notas tocadas juntas se movem juntas.
- **Presets apagam ajustes**: aplicar um preset sobrescreve tudo, inclusive `Volume` e `Vozes`. Desfazer (`Ctrl+Z`) volta ao estado anterior.
- **Web e Android**: o motor é o mesmo (WASM no navegador, nativo no Android); o painel só muda de disposição (fileira horizontal no computador, cartões em linhas no celular; no celular o seletor de presets não tem setas).
- **Anti-aliasing e limite de vozes**: são 16 vozes mais 4 de folga para as notas roubadas saírem em fade; `Vozes` limita a 16.

## Atalhos

| Tecla / gesto | Ação |
|---|---|
| `I` | Abre ou fecha o painel na aba `Instrumento` (tooltip `Instrumento da faixa (I)`); `Esc` fecha o painel |
| `Ctrl+K` (`Cmd+K` no Mac) | Liga e desliga o teclado do computador como teclado musical |
| Arrastar um knob na vertical | Muda o valor (200 px cobrem a faixa inteira). Um arraste é um passo do desfazer |
| `Shift` + arrastar | Ajuste fino (cinco vezes mais lento) |
| Roda do mouse sobre o knob | Muda o valor (`Shift` = fino). Em valores inteiros (`Vozes`) anda um passo por "dente" |
| Duplo clique num knob | Volta ao padrão |
| Botão direito (ou toque longo no celular) num knob | Abre um campo para digitar o valor, com unidade se quiser: `3.5`, `250 ms`, `70%`, `+7 ct` |
| Botão `Onda` (menu) | Abre a lista de formas; cada escolha é um passo do desfazer |
| `Z` / `X` (teclado do computador ligado) | Oitava abaixo / acima |
| `C` / `V` (teclado do computador ligado) | Velocidade menor / maior das notas tocadas |
| `A`, `W`, `S`, `E`, `D`, `F`, `T`, `G`, `Y`, `H`, `U`, `J`, `K`, `O`, `L`, `P` | Tocam as notas quando o botão de teclado do cabeçalho está ligado (a tecla `A` é o dó da oitava atual) |
