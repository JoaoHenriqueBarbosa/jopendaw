# Sampler

> Toca áudios seus (uma nota, um golpe de bateria, uma frase, um loop fatiado) como instrumento: cada nota do teclado ou do piano roll dispara o áudio afinado naquela altura, com envelope e sensibilidade à força do toque. Com o cartão `ZONAS` o sampler vira multi-sample: vários áudios espalhados pelo teclado, camadas por força do toque, alternância entre gravações (round-robin), loop de sustentação e fatiamento de loops.

## Onde fica

1. Crie a faixa em `Nova faixa` (coluna de faixas do arranjo) > `Sampler`, ou selecione uma faixa `Sampler`.
2. Abra o painel de baixo na aba `Instrumento` (tecla `I`).
3. O cabeçalho é o do [painel de instrumento](04-painel-de-instrumento.md); abaixo dele ficam quatro cartões: `ÁUDIO` (com o seletor do arquivo), `ENVELOPE`, `GERAL` e `ZONAS` (o mapa de teclado, ocupa a largura toda no celular e 640 px no computador).

No teclado da tela, as teclas marcadas com um ponto colorido dependem do modo: sem zonas, a nota base do cartão `ÁUDIO`; com zonas, **todas as notas que alguma zona cobre** (a nota base do cartão deixa de ser marcada). O teclado abre em C3, como o do sintetizador.

## Dois modos: áudio único e zonas

O sampler tem dois modos, e quem escolhe é a lista de zonas da faixa:

| | Sem zonas (áudio único) | Com zonas |
|---|---|---|
| Que som toca | O áudio escolhido no cartão `ÁUDIO` | O áudio de cada zona que cobre a nota |
| Nota base | Knob `Nota base` | A `Nota base` de cada zona |
| Como termina a nota | Knob `Modo` (`Sustenta` ou `Até o fim`) | O modo de cada zona (`Sustentado` ou `Até o fim`) |
| Loop | Não existe | Por zona, no modo `Sustentado` |
| Trecho do áudio | Sempre o áudio inteiro | Início e fim por zona |
| Ganho e pan por nota | Não | Por zona |
| Camadas por força do toque | Não | Sim (faixa de velocidade por zona) |

O que **continua valendo nos dois modos**: o cartão `ENVELOPE` (`Ataque`, `Decaimento`, `Sustentação`, `Soltura`; nas vozes `Até o fim` só o `Ataque` vale), `Sens. vel.` e `Volume` do cartão `GERAL`, e a `Afinação` do cartão `ÁUDIO`, que **soma** com a afinação de cada zona. O que **deixa de valer** quando existe ao menos uma zona: o áudio único, o knob `Nota base` e o knob `Modo` (cada zona tem os seus). Com zonas, esses dois knobs aparecem apagados (mais escuros) no cartão `ÁUDIO`, embora ainda dê para movê-los; o cartão `ENVELOPE` também deixa de seguir o `Modo` do cartão (ver [Envelope](#envelope)), o visor do cartão `ÁUDIO` passa a dizer `Usando N zonas` e o teclado da tela marca as notas das zonas. Apagar todas as zonas devolve o sampler ao modo de áudio único, com o áudio e os knobs como estavam.

Um projeto salvo antes das zonas abre igual: só a faixa que tem zonas guarda a lista delas no projeto.

## Como o sampler toca

- O áudio é lido em velocidade variável: tocar a nota base toca o áudio na velocidade e na altura originais; uma nota um semitom acima toca mais rápido e mais agudo, e uma abaixo toca mais lento e mais grave. Como a duração muda junto com a altura, uma nota aguda dura menos que o áudio original e uma grave dura mais. Não há esticamento sem mudar a altura (para isso, ver [03b Warp e altura](03b-warp-e-altura.md), que vale para clipes de áudio).
- Sem zonas, o áudio toca uma vez, do começo ao fim: quando o áudio acaba, a voz acaba, mesmo que a tecla continue apertada. Com zonas, uma zona no modo `Sustentado` pode ter loop (ver [Loop da zona](#loop-da-zona)).
- Sem áudio escolhido (e sem zonas), as notas ficam mudas.
- Áudio estéreo continua estéreo; áudio mono sai igual dos dois lados. A taxa de amostragem do arquivo é convertida sozinha, e cada zona pode ter um arquivo de taxa e de canais diferentes.
- Ao tocar mais agudo que o original, o sampler filtra os agudos que passariam do limite do áudio digital (anti-aliasing), então notas altas não produzem chiado de aliasing.
- Com zonas, **cada nota dispara todas as zonas que a contêm**, tanto na faixa de notas quanto na faixa de velocidade. Zonas sobrepostas empilham (é assim que se fazem camadas). Uma nota que nenhuma zona cobre não soa.
- A velocidade que decide a zona é a força da nota, de 1 a 127 (a velocidade do piano roll, ou a do toque no teclado da tela).

## Controles

### Áudio

O cartão tem, ao lado do título, o botão do arquivo; abaixo, o visor; embaixo, os três knobs.

| Controle (rótulo exato) | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| Botão do arquivo, tooltip `Áudio que o sampler toca` | Abre o menu para escolher, importar ou remover o áudio | O texto do botão muda: `Importar o áudio` (projeto ainda sem nenhum áudio), `Escolher o áudio` (há áudios no projeto mas nenhum escolhido), o nome do arquivo quando há um escolhido, ou `Áudio fora do projeto` | Sem áudio escolhido o botão fica destacado com a cor da faixa |
| Item de áudio (nome e duração, como `0.84 s`, `12.5 s` ou `3:07`) | Escolhe esse áudio para o sampler | Lista de todos os áudios do projeto, em ordem alfabética sem distinção de maiúsculas; um visto marca o atual | Inclui os áudios que você importou para clipes |
| `Importar um arquivo…` | Abre o seletor de arquivos (`Áudio do sampler`), lê o áudio e o faz o som do sampler | Aceita `wav`, `mp3`, `ogg`, `oga`, `flac`, `m4a`, `aac`, `opus`, `webm`, `aif` e `aiff` | Aparece o aviso `Importando nome…` enquanto decodifica |
| `Sem áudio` | Tira o áudio do sampler | Só aparece se já há um áudio escolhido | O áudio continua no projeto, só deixa de ser o do sampler |
| Visor da forma de onda | Mostra o áudio inteiro, ampliado pelo pico para amostras baixas aparecerem; a legenda diz a duração e a nota base (`0.84 s · C4`). Tem um ícone de play no canto | Segurar o mouse ou o dedo sobre o visor toca o áudio na nota base, com 80% de força (tooltip `Segure para ouvir na nota base`) | Serve para conferir o áudio e a nota base sem abrir o teclado. Com zonas o visor vira `Usando N zonas` e não toca (use o teclado da tela) |
| Nota base | A nota em que o áudio soa na altura original | 0 a 127, inteiro, padrão C4 (60); o knob mostra o nome da nota (`C4`) | No diálogo de valor (botão direito) dá para digitar `C3`, `F#3`. Ajuste para a altura real do áudio: se o áudio é um lá 440 Hz, ponha `A4`. **Só vale no modo de áudio único** (com zonas o knob fica apagado) |
| Afinação | Ajuste fino da afinação de todas as notas | -100 a +100 ct, padrão +0 ct | Corrige um áudio levemente desafinado sem mexer na nota base. Com zonas, soma com a `Afinação` de cada zona |
| Modo | Como a nota termina | Lista: `Sustenta` (padrão) e `Até o fim` | `Sustenta`: soltar a tecla dispara a `Soltura`. `Até o fim`: soltar a tecla não faz nada, o áudio toca inteiro (percussão, golpes); a nota também **ignora a `Sustentação`** do envelope e tocar a mesma nota de novo **não** solta a anterior (as vozes empilham), e com esse modo a `Soltura` fica apagada no cartão `ENVELOPE`. **Só vale no modo de áudio único** (com zonas, cada zona tem o seu, e o knob fica apagado) |

Enquanto o áudio não está escolhido, o visor mostra uma orientação:

- `Nenhum áudio no projeto ainda. Importe um arquivo pelo menu acima: ele vira o som deste sampler, sem entrar no arranjo.`
- `Escolha acima qual áudio do projeto este sampler toca.`
- `Este áudio não está neste aparelho. Importe o arquivo de novo para ouvi-lo.` (o projeto guarda o áudio, mas este aparelho ainda não o tem)

Se o arquivo não puder ser lido, o app avisa `Não deu para abrir nome: é um formato de áudio que este navegador decodifica?`.

### Envelope

Visor: o desenho do envelope (ataque em rampa; decaimento e soltura exponenciais; tempos em escala logarítmica). Uma voz `Até o fim` só usa o `Ataque`: `Decaimento`, `Sustentação` e `Soltura` não entram. Sem zonas e com o `Modo` em `Até o fim`, a legenda diz `até o fim: só o ataque vale`, os três knobs ficam apagados e o desenho mostra só a subida. **Com zonas o `Modo` do cartão `ÁUDIO` é ignorado e vale o de cada zona**: se todas as zonas são `Até o fim`, a legenda diz `todas as zonas até o fim: só o ataque vale` e os três knobs ficam apagados; numa mistura, o desenho e os knobs seguem as zonas `Sustentado` e a legenda diz `zonas até o fim só usam o ataque`. A zona selecionada no modo `Até o fim` também mostra, no editor, o aviso de que só o `Ataque` vale nela.

O envelope vale para **todas as vozes**, inclusive as de zona, mas nem todos os estágios valem para toda voz:

| Voz | `Ataque` | `Decaimento` e `Sustentação` | `Soltura` |
|---|---|---|---|
| Sustentada (zona `Sustentado`, ou áudio único com `Modo` `Sustenta`) | Vale | Valem | Vale ao soltar a nota |
| `Até o fim` (zona `Até o fim`, ou áudio único com `Modo` `Até o fim`) | Vale | **Ignorados**: a voz sobe no `Ataque` e fica em 100% (a `Sustentação` conta como 100%, então o `Decaimento` não muda nada) `(testado só por testes automáticos)` | Só entra quando o transporte para |

Mexer na `Sustentação` com uma voz `Até o fim` soando também não a derruba `(testado só por testes automáticos)`.

| Controle | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| Ataque | Tempo para o volume subir do zero ao máximo no começo da nota | 0,5 ms a 10 s, logarítmico, padrão 2.0 ms | Deixe curto para não cortar o começo do áudio; longo para entrar suave |
| Decaimento | Tempo da queda do máximo até a `Sustentação` | 1 ms a 10 s, logarítmico, padrão 500 ms | Sem efeito audível com `Sustentação` em 100% |
| Sustentação | Nível mantido enquanto a tecla está apertada | 0 a 100%, padrão 100% | Em 0% a nota morre sozinha depois do decaimento, mesmo com a tecla apertada (pluck). **Não vale para vozes `Até o fim`** (fatias, golpes, `Modo` `Até o fim`): elas ficam em 100%. Quando nenhuma voz a usa (áudio único em `Até o fim`, ou todas as zonas `Até o fim`) o knob fica apagado e o desenho mostra só a subida; numa mistura de zonas ele fica aceso e vale só nas zonas `Sustentado` |
| Soltura | Tempo da queda depois de soltar a tecla | 1 ms a 10 s, logarítmico, padrão 200 ms | Apagada (junto com `Decaimento` e `Sustentação`, que também deixam de valer) quando nenhuma voz a usa: `Modo` `Até o fim` do cartão `ÁUDIO` sem zonas, ou todas as zonas `Até o fim` (só entra quando o transporte para). Com uma mistura de zonas ela fica acesa e age só nas zonas `Sustentado` |

### Geral

| Controle | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| Sens. vel. | Sensibilidade à força do toque (velocity), não uma velocidade de reprodução | 0 a 100%, padrão 70% | Em 0% todas as notas soam com o mesmo volume; em 100% o volume cresce com o quadrado da força (metade da força dá -12 dB). Vale por cima da escolha de zona por velocidade |
| Volume | Nível de saída do instrumento | 0 a 150%, padrão 80% | Muda sem degraus, mesmo com notas soando |
| Alcance do bend | Quanto o pitch bend inteiro (roda no fim, ou ponto `±1` na faixa `Pitch bend` do piano roll) afina o sampler | 0 a 24 st, inteiro, padrão 2 st | Vale com zonas e sem elas. Ver [Rodas de pitch bend e de modulação](04-painel-de-instrumento.md#rodas-de-pitch-bend-e-de-modulação) |
| Vibrato da roda | Profundidade do vibrato de 5,5 Hz que a roda de modulação (`CC 1`, ou pontos de `Modulação` no clipe) liga, com a roda toda levantada | 0 a 2 st, padrão 1 st | Em 0 a roda não faz nada. É diferente de um vibrato constante: o sampler não tem LFO, então este é o único vibrato dele. Vale com zonas e sem elas (testado só por testes automáticos) |

### Zonas: a barra do cartão

O cartão `ZONAS` abre com uma linha de botões e, embaixo dela, o mapa e o editor da zona selecionada.

| Controle (rótulo exato) | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| `Adicionar sample como zona` (tooltip `Acrescentar um áudio como zona`) | Abre um menu com os áudios do projeto (em ordem alfabética) e, no fim, `Importar um arquivo…`. Escolher um áudio cria uma zona nova já selecionada | Onde a zona nasce: a primeira cobre o teclado todo (0 a 127, `Nota base` C4). Da segunda em diante, ocupa a **maior lacuna** que as outras deixam no teclado (nunca por cima de outra), com a `Nota base` na nota da lacuna mais perto do C4 (`C4` se ele está na lacuna; senão a ponta da lacuna que fica mais perto). Sem lacuna (teclado todo coberto), ela **divide ao meio a zona de faixa mais larga**: a zona antiga fica com a metade de baixo (o `até` dela encurta) e a nova com a de cima; nesse caso o cartão mostra um aviso (ver abaixo). Velocidade de 1 a 127, sem ganho, sem pan, `Sustentado`, sem loop, sem round-robin | `Importar um arquivo…` abre o seletor (`Áudio da zona`, mesmos formatos do cartão `ÁUDIO`), guarda o áudio no projeto e já o põe como zona, sem criar clipe no arranjo. A altura real do áudio o app não sabe: acerte a `Nota base` (dá para digitar) |
| `Fatiar sample…` | Abre o diálogo `Fatiar sample` (ver adiante) | | Substitui todas as zonas da faixa |
| `Usar o áudio atual como zona` | Faz do áudio único do cartão `ÁUDIO` a primeira zona, com o teclado todo e a `Nota base` do cartão | Só aparece quando a faixa ainda não tem zonas e há um áudio escolhido | Caminho mais curto para começar um multi-sample a partir de um sampler que já toca |
| Contador `1 zona` / `N zonas` | Diz quantas zonas há | Só aparece com zonas | |
| `Apagar todas` (texto sublinhado) | Apaga todas as zonas e volta ao modo de áudio único | Só aparece com zonas; entra no desfazer | Os áudios continuam no projeto |

Sem zonas, no lugar do mapa aparece o texto: `Sem zonas o sampler toca um áudio só, afinado pelas notas. Acrescente samples como zonas para espalhá-los pelo teclado (e por camadas de velocidade), ou fatie um loop: cada fatia vira uma nota, a partir do C1. Com zonas, o áudio único e a nota base do cartão Áudio deixam de valer.`

**Avisos.** Acima do mapa pode aparecer um aviso dispensável (botão `Dispensar`), que some sozinho na próxima zona acrescentada sem aviso e ao usar `Apagar todas`:

| Aviso (texto exato) | Quando |
|---|---|
| `O teclado já estava coberto: a zona "NOME" foi dividida e a nova ficou com E4 a G9. Ajuste as faixas no mapa.` | Ao acrescentar uma zona com o teclado todo coberto. `NOME` é o nome do áudio da zona dividida (`sem nome` se ele não está no projeto); a faixa da nova varia (com uma zona única de 0 a 127 é `E4 a G9`) |
| `Não dá para criar outra zona: o limite é de 128 zonas ou o teclado já está todo ocupado por zonas de uma nota só. Apague alguma antes.` | Uma mensagem só para os dois casos em que não cabe outra zona. O botão `Adicionar sample como zona` fica desabilitado, com esse texto como dica, e nada é criado (nem o arquivo é importado) |
| `Nota inválida: use C4, C#3, 60` / `Velocidade inválida: use 1 a 127` | Embaixo do campo digitado, ver [Campos digitáveis](#campos-digitáveis) |
| `N cópias criadas logo depois desta zona, cada uma com a sua faixa de velocidade. Selecione cada uma e troque o áudio.` (`1 cópia criada` no singular) | Depois de `Camadas de velocidade` (ver [O editor da zona](#o-editor-da-zona)) |
| `Não coube: as zonas já estão no limite de 128.` | `Camadas de velocidade` sem espaço para as cópias |

### O mapa de teclado

O mapa desenha cada zona como um bloco colorido:

- **Na horizontal, as notas de 0 (C-1) a 127 (G9)**; cada nota tem pelo menos 8 px, então o mapa rola na horizontal (com barra de rolagem) quando não cabe. Linhas verticais marcam cada C.
- **Na vertical, a velocidade**: 127 em cima, 1 embaixo, com linhas discretas em 32, 64 e 96. O mapa tem 120 px de altura no computador e 96 px no celular.
- Cada zona tem uma cor própria pela posição na lista. O bloco selecionado fica mais forte e com contorno branco.
- Um risquinho branco no alto do bloco marca a `Nota base` da zona; se o bloco tem pelo menos 34 px de largura e 14 de altura, o nome da nota base (`C4`) aparece no canto de baixo à esquerda.
- **Faixa de teclas embaixo do mapa** (30 px): as teclas cobertas por alguma zona ficam mais claras. Tocar ou segurar uma tecla toca a nota ali, com 80% de força (o mesmo que velocidade 102), no instrumento da faixa; serve para ouvir o mapa sem abrir o teclado.

| Gesto (mouse ou dedo) | O que faz | Valores | Dica |
|---|---|---|---|
| Tocar num bloco | Seleciona a zona e abre o editor dela embaixo | Bloco de cima (o último da lista) ganha onde há sobreposição; o **selecionado** ganha das camadas por cima dele | Para pegar uma zona escondida por outra, toque no que não está coberto ou selecione-a antes |
| Tocar fora de qualquer bloco | Tira a seleção | O texto `Toque num bloco para editar a zona.` volta | |
| Arrastar a **borda esquerda** de um bloco | Muda a nota mais grave da zona (`Notas de`) | Não passa da nota mais aguda | A borda pega numa faixa de 7 px |
| Arrastar a **borda direita** | Muda a nota mais aguda (`até`) | Não passa da nota mais grave | |
| Arrastar a **borda de cima** | Muda a velocidade máxima da zona | 1 a 127; não passa da mínima | Só existe em blocos com pelo menos 21 px de altura (cerca de 23 valores de velocidade no computador, 28 no celular) |
| Arrastar a **borda de baixo** | Muda a velocidade mínima | 1 a 127; não passa da máxima | |
| Arrastar o **corpo** do bloco | Move o bloco só na horizontal: a faixa de notas e a `Nota base` andam juntas, o mesmo número de semitons | Para nos limites 0 e 127 (notas). **A faixa de velocidade não muda** por mais que o arraste suba ou desça | Para mudar a velocidade use as bordas de cima e de baixo, ou os campos `Velocidade de` e `até` |
| Arrastar num lugar vazio | Rola o mapa na horizontal | | O arraste só "pega" quando começa em cima de um bloco |

Um bloco com menos de 21 px de largura (cerca de três notas no zoom mínimo, como as zonas de uma nota só das fatias) não tem as bordas esquerda e direita: para mudar a faixa de notas dele use os botões do editor. Ele ainda tem as bordas de cima e de baixo, se for alto o bastante. Cada arraste inteiro é **um passo só** no desfazer.

### O editor da zona

Aparece embaixo do mapa quando uma zona está selecionada, com a borda na cor dela.

| Controle (rótulo exato) | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| Nome do áudio (tooltip `Trocar o áudio da zona`) | Abre a lista dos áudios do projeto; escolher um troca o áudio da zona, mantendo notas, velocidades e ajustes | Mostra `Áudio fora do projeto` se o áudio da zona não existe mais no projeto | Trocar o áudio **não** refaz o trecho e o loop: confira o `Trecho` |
| `Duplicar a zona` (ícone de copiar) | Cria uma cópia logo depois da zona, com a mesma faixa de notas e de velocidade, e a seleciona | Não passa de 128 zonas: com 128 o botão fica desabilitado, com o tooltip `Não dá para duplicar: as zonas já estão no limite de 128.` | O caminho para round-robin (duplique e troque o áudio). Para camadas de velocidade, `Camadas de velocidade` faz as cópias já com as faixas certas |
| `Apagar a zona` (ícone de lixeira) | Remove a zona | Entra no desfazer | |
| `Nota base` | Nota em que o áudio da zona soa na altura original | 0 a 127; campo digitável (ver [Campos digitáveis](#campos-digitáveis)) com `Menos` e `Mais` (tooltips) de 1 semitom; mostra o nome (`C4`) | Digite `C3` ou `48` em vez de clicar 12 vezes. Mover o bloco pelo corpo leva a nota base junto. Mudar a `Nota base` não move a faixa de notas |
| `Notas de` e `até` (primeiro par) | Nota mais grave e mais aguda da zona | 0 a 127, digitável, 1 semitom por `Menos`/`Mais`. Se um passar do outro, os dois trocam de lugar | Mais prático arrastar as bordas do bloco |
| `Velocidade de` e `até` (segundo par) | Velocidade mínima e máxima da zona | 1 a 127, digitável, **de 1 em 1** por `Menos`/`Mais`. Se um passar do outro, trocam de lugar | Para dividir em camadas iguais sem conta, `Camadas de velocidade` |
| `Afinação` (deslizante) | Afinação fina da zona | -100 a +100 ct, passo de 1 ct; o valor aparece como `12 ct` | Soma com a `Afinação` do cartão `ÁUDIO` |
| `Ganho` (deslizante) | Volume da zona | -24 a +12 dB, passo de 0,5 dB, padrão `0.0 dB` | Equilibre camadas e gravações diferentes |
| `Pan` (deslizante) | Posição da zona no estéreo | -1 a +1, passo de 0,01; mostra `C` no centro, `E30` (30% para a esquerda), `D30` (30% para a direita). Funciona como balanço: o centro não muda o nível, o extremo zera o lado oposto | Bom para espalhar zonas de bateria; diferente do pan da faixa no mixer, que se soma a ele |
| `Sustentado` / `Até o fim` (botões) | Como a zona termina | `Sustentado` (padrão): soltar a nota dispara a `Soltura`. `Até o fim`: toca o trecho todo ignorando a nota solta, a `Sustentação` do envelope e a mesma nota tocada de novo (bateria, fatias; ver [Até o fim](#até-o-fim-e-a-mesma-nota-de-novo)) | `Até o fim` esconde o loop |
| `Camadas de velocidade` (botão com menu; tooltip `Divide esta zona em camadas de velocidade iguais: ela fica com a primeira e as outras são cópias para trocar o áudio`) | Divide a zona selecionada em camadas iguais de força do toque | Itens `Dividir em 2 camadas iguais`, `Dividir em 3 camadas iguais` e `Dividir em 4 camadas iguais`. Numa zona de 1 a 127: 2: 1–63 e 64–127; 3: 1–42, 43–84 e 85–127; 4: 1–31, 32–63, 64–95 e 96–127 | A zona fica com a camada mais fraca (a primeira faixa) e as outras camadas são cópias colocadas logo depois dela (mesmo áudio, mesmas notas e mesma nota base). A divisão parte a faixa de velocidade **atual** da zona em partes iguais (uma zona de 40 a 100 em 2 vira 40–69 e 70–100); numa faixa estreita saem menos camadas que o pedido (aviso `a faixa só comporta N camadas`) e numa faixa de um valor só não há o que dividir (aviso próprio). Depois, selecione cada cópia (a seleção não muda: continua na zona original) e troque o áudio. Não coube nas 128 zonas: nada é criado e sai o aviso `Não coube...` |
| `Round-robin` (lista) | Grupo de alternância | `nenhum` (padrão) e `grupo 1` a `grupo 63`; a lista rola | Zonas do mesmo grupo que cobrem a mesma nota e a mesma força se alternam a cada nota (ver adiante) |
| Forma de onda do áudio (52 px) | Mostra o áudio com o trecho da zona em cor e o resto apagado; o loop aparece como uma faixa sombreada | | Se o áudio não está neste aparelho, no lugar dela aparece `Este áudio não está neste aparelho: o trecho e o loop ficam para quando ele voltar.` |
| `Trecho` (dois cursores) | Início e fim do trecho do áudio que a zona toca | Em segundos, com 3 casas (`0.250–1.500 s`); padrão do início 0 e do fim o fim do áudio. Levar o cursor do fim até o fim do áudio volta ao "até o fim" | Corta silêncio inicial ou cauda sem editar o arquivo |
| `Loop enquanto a nota está presa` (caixa) | Liga o loop da zona | Só aparece em zonas `Sustentado`. Ao ligar, o loop nasce de 25% a 75% do trecho | Desligar zera o loop |
| `Loop` (dois cursores) | Início e fim do loop | Só com o loop ligado; ficam dentro do `Trecho`; mostra `início–fim s` | Ver [Loop da zona](#loop-da-zona) |

Todos os ajustes das zonas (botões, deslizantes, cursores, campos digitados, arrastes no mapa) entram no desfazer; um deslizante ou cursor arrastado é um passo só.

#### Campos digitáveis

`Nota base`, `Notas de`, `até` (das notas), `Velocidade de` e `até` (das velocidades) são campos de texto entre os botões `Menos` e `Mais`. Clique no número, digite e confirme com Enter (ou saia do campo): o valor só vale ao confirmar. Com o campo vazio aparece uma dica: `C4 ou 60` nos de nota e `1 a 127` nos de velocidade.

| Campo | O que aceita | Exemplos |
|---|---|---|
| Notas (`Nota base`, `Notas de`, `até`) | Um número de 0 a 127, ou o nome da nota: letra `A` a `G` (maiúscula ou minúscula), sustenido `#` ou `♯` ou bemol `b` ou `♭` opcional, e a oitava de um dígito (`-1` a `9`). `C4` é a nota 60, como nos rótulos do app; `C-1` é a 0 e `G9` a 127 | `60`, `C4`, `c#3` (49), `Db3` (49), `F♯2` (42), `C-1` (0), `G9` (127) |
| Velocidades | Um número inteiro de 1 a 127 | `64`, `127` |

**Campos digitáveis.** O que o campo não entende (`H4`, `C`, `128`, `-1`, `G#9`, `0` numa velocidade, um número com vírgula, texto vazio) não muda a zona: o texto digitado **fica** no campo, com a borda vermelha e a mensagem `Nota inválida: use C4, C#3, 60` (ou `Velocidade inválida: use 1 a 127`) embaixo, até você corrigir (o erro some ao digitar e vale ao confirmar), apertar Esc no campo ou usar `Menos`/`Mais` (voltam ao valor da zona). `Menos` e `Mais` param nas pontas (0 e 127; 1 e 127). Se `Notas de` passar de `até` (ou o contrário), os dois trocam de lugar. Um campo que acaba de ser digitado mostra o valor normalizado (por exemplo `Db3` vira `C#3`).

### Loop da zona

- O loop só existe em zona `Sustentado`. Enquanto a nota está presa, o sampler toca o trecho até o fim do loop e volta ao início do loop, sem parar, até você soltar a nota; ao soltar, a `Soltura` do envelope apaga o som com o loop ainda rodando.
- O loop vale quando o fim é maior que o início e cabe dentro do `Trecho`. Um loop fora do trecho é descartado, sem aviso.
- Não há emenda suave (crossfade): o ponto de volta é seco. Escolha um trecho de som estável e, se estalar, mude o início ou o fim do loop `(não confirmado em uso)`.
- Uma zona sem loop e `Sustentado` toca o trecho uma vez; no fim dele o som desce a zero em cerca de 1 ms, então não estala.
- Uma zona `Até o fim` nunca faz loop.

### Round-robin

Round-robin serve para o mesmo golpe (um bumbo, uma nota) não soar igual toda hora: você põe duas ou mais gravações da mesma nota, cada uma numa zona, e todas no mesmo `grupo`; a cada nota o sampler toca a próxima do grupo, em ciclo.

- O grupo só alterna entre as zonas **que casam com a nota tocada** (faixa de notas e de velocidade): as que ficam de fora da nota ou da força não entram no revezamento. O contador é um só por grupo e anda a cada nota que casa com alguma zona dele. Para uma alternância estritamente em ordem (1, 2, 3, 1, 2, 3...), use **um grupo por região do teclado e por camada de velocidade**; se várias regiões ou camadas dividirem o mesmo grupo, a ordem de cada uma pode pular gravações, embora nunca toque duas zonas do grupo ao mesmo tempo.
- Zonas com `nenhum` não alternam: todas as que casam tocam juntas.
- Editar qualquer zona reenvia a lista ao motor, e o ciclo recomeça na primeira zona do grupo `(não confirmado em uso)`.
- Há 63 grupos (`grupo 1` a `grupo 63`), o que sobra para um grupo por região do teclado e por camada de velocidade. O menu mostra o número do grupo da zona qualquer que ele seja.

### Até o fim e a mesma nota de novo

Vozes `Até o fim` (zona `Até o fim`, ou o áudio único com `Modo` `Até o fim`) se comportam diferente das sustentadas quando a mesma nota é tocada de novo enquanto a anterior ainda soa:

- **Sustentadas:** a nova nota solta as anteriores da mesma nota (com a `Soltura`) e começa uma voz nova.
- **`Até o fim`:** as anteriores **não são soltas**; a nova voz empilha por cima e cada uma toca o seu trecho até o fim. Isso vale para uma fatia repetida rápido: a cauda da anterior segue soando.
- O empilhamento vai até o limite de 16 vozes; passando dele, a voz mais antiga sai em um fade curto de 3 ms (ver [Limites e pegadinhas](#limites-e-pegadinhas)).
- Essas vozes também ignoram a `Sustentação` do envelope (ver [Envelope](#envelope)).

`(testado só por testes automáticos)`: os testes do motor tocam a mesma nota várias vezes e conferem que nenhuma voz `Até o fim` entra em soltura e que o total nunca passa de 16 vozes.

### Fatiar sample

`Fatiar sample…` corta um áudio do projeto (um loop de bateria, uma frase) em partes e cria **uma zona por fatia**, uma nota por fatia, a partir de **C1 (nota 24)**, cada uma tocando só o seu trecho, até o fim, na altura original (a nota é a base da própria fatia). O diálogo mostra uma prévia dos cortes sobre a forma de onda antes de criar.

| Controle (rótulo exato) | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| Título `Fatiar sample` | | | Sem nenhum áudio no projeto, o diálogo diz: `Nenhum áudio no projeto ainda. Importe um arquivo (pelo cartão Áudio ou pelo botão de adicionar zona) e volte aqui.` |
| `ÁUDIO` (lista) | Escolhe o áudio a fatiar | Começa no áudio único da faixa; senão no áudio da primeira zona; senão no primeiro áudio do projeto | Só os áudios que estão neste aparelho têm prévia |
| `Por transientes` / `N fatias iguais` (botões) | Como achar os cortes | Padrão `Por transientes` | Transientes seguem os golpes do áudio; iguais dividem o tempo em partes iguais, sem olhar o andamento nem o som |
| `Sensibilidade` (só em `Por transientes`) | Quantos ataques contam como corte | 0% a 100%, padrão 50%; mostra `50%`. A prévia é refeita quando você solta o deslizante (não enquanto arrasta) | Em 100% pega também ataques fracos (chimbais, notas fantasma); em 0%, só os fortes. Por dentro, ela afrouxa três exigências ao mesmo tempo: em 0% o ataque precisa chegar a 30% do maior ataque do áudio e a 6 vezes a média das redondezas (0,2 s para cada lado); em 100%, a 8% e a 1,5 vez |
| `Fatias` (só em `N fatias iguais`) | Número de fatias | 2 a 96, padrão 8; botões `Menos uma fatia` (tooltip; desativado no 2) e `Mais uma fatia` (tooltip; desativado no 96); botões de escolha rápida `4`, `8`, `16` e `32`, com o do valor atual marcado | O corte é em tempo, não em batidas: o primeiro é sempre o começo do áudio e os outros o dividem em partes iguais |
| Prévia (96 px) | Forma de onda com uma linha em cada início de fatia, numerada | | Sem o áudio no aparelho: `Este áudio não está neste aparelho. Importe o arquivo de novo para fatiá-lo.` |
| Resumo | `8 fatias: C1 a G1, uma nota cada, tocando até o fim de cada trecho.` | | Sem cortes: `Nenhum corte achado: tente mais sensibilidade ou fatias iguais.`; só um transiente: `Nenhum transiente achado: uma fatia só. Tente mais sensibilidade ou fatias iguais.` |
| Aviso de limite | `N fatias achadas; só as 96 primeiras viram nota.` com o botão `Menos sensibilidade` | Aparece no modo por transientes quando o áudio tem mais de 96 ataques; o botão baixa a sensibilidade em 15 pontos e refaz. Os cortes depois do 96º aparecem apagados na forma de onda. `N fatias iguais` para em 96 e não avisa | Valem as 96 primeiras no tempo (não as mais fortes) |
| Aviso de substituição | `Criar substitui as zonas atuais desta faixa (dá para desfazer).` | Só aparece se a faixa já tem zonas | |
| `Cancelar` / `Criar` | Fecha / cria as zonas | `Criar` fica apagado sem áudio ou sem cortes | Fecha o diálogo ao criar |

O que o fatiamento cria, para cada fatia: `Notas de` e `até` na mesma nota (C1, C#1, D1, ...), `Nota base` nessa nota, velocidade de 1 a 127, modo `Até o fim`, `Trecho` do início dela até o início da próxima (a última vai até o fim do áudio), sem ganho, pan, loop nem round-robin. O primeiro corte é sempre o começo do áudio (0 s). Nos cortes por transiente, o ponto de corte é ajustado no próprio áudio: recuado até o começo do ataque e, se possível, até o cruzamento de zero mais próximo (até 2 ms), para o corte não estalar; ataques a menos de 50 ms de outro mais forte nem contam, e dois cortes que ficam a menos de cerca de 25 ms depois do ajuste viram um só (fica o mais forte), e cortes a menos de 10 ms do começo ou do fim do áudio são descartados. O fim de cada fatia desce a zero em cerca de 1 ms.

Depois de criadas, as zonas são zonas comuns: dá para mudar o `Ganho`, o `Pan`, o `Trecho` ou a `Afinação` de cada fatia, trocar o áudio, duplicar e apagar.

## Presets

O seletor de presets (categoria `SAMPLER`) tem cinco ajustes de envelope. Nenhum preset mexe no áudio escolhido, na `Nota base`, na `Afinação` nem nas zonas: elas pertencem ao áudio. Todo o resto volta ao padrão a cada preset, inclusive o `Modo` (ver [Presets](04-painel-de-instrumento.md#presets)).

| Preset | Ajustes | Caráter |
|---|---|---|
| Inicial | Tudo nos padrões | Ponto de partida: ataque de 2 ms, sustentação 100%, soltura de 200 ms |
| Instrumento | Ataque 3 ms, decaimento 500 ms, sustentação 100%, soltura 350 ms, `Sens. vel.` 80% | Áudio de uma nota tocado como teclado: soltura um pouco mais longa e resposta à força |
| Percussão (até o fim) | `Modo` `Até o fim`, ataque 0,5 ms, soltura 50 ms, `Sens. vel.` 80% | Golpes e vozes curtas: a nota sempre toca inteira, com ataque instantâneo. Com zonas, o `Modo` dele não vale (cada zona tem o seu); o `Ataque` curto vale, e a `Soltura` curta vale nas zonas `Sustentado` |
| Pad lento | Ataque 0,8 s, decaimento 1 s, sustentação 90%, soltura 1,8 s, `Sens. vel.` 30% | Áudio longo que entra e sai devagar; pouca resposta à força |
| Pluck | Ataque 1 ms, decaimento 350 ms, sustentação 0%, soltura 250 ms, `Sens. vel.` 80% | Nota curta e seca, mesmo com tecla apertada |

O rótulo do seletor compara só os parâmetros de timbre: como a `Nota base` e a `Afinação` são ignoradas, o preset continua marcado mesmo depois de você mudá-las.

Você também pode guardar os seus (`Salvar como preset…`, seção `MEUS PRESETS` no topo do menu; ver [Meus presets](04-painel-de-instrumento.md#meus-presets)). O preset do sampler guarda **só o timbre**: `Modo`, `Ataque`, `Decaimento`, `Sustentação`, `Soltura`, `Sens. vel.`, `Volume`, `Alcance do bend` e `Vibrato da roda`. **Não guarda o áudio escolhido, as zonas, a `Nota base` nem a `Afinação`**: o app não tem preset de zonas, então um multi-sample montado numa faixa não vai junto para outra pelo preset. Ao aplicar um preset seu, o áudio, as zonas, a `Nota base` e a `Afinação` da faixa ficam como estão.

## Relação com os clipes de áudio

- **Mesmo depósito.** O sampler e os clipes de áudio usam a mesma lista de áudios do projeto, identificados pela impressão digital (SHA-256) do arquivo. Um áudio que você já importou para um clipe (ver [03 Áudio e clipes](03-audio-e-clipes.md)) aparece no menu do sampler e no menu das zonas, e um áudio importado pelo sampler entra na mesma lista de áudios do projeto. Arquivos idênticos são um só.
- **Importar pelo sampler não põe clipe no arranjo.** O `Importar um arquivo…` do cartão `ÁUDIO` e o das zonas guardam o áudio no projeto sem criar nenhum clipe na linha do tempo. O do cartão `ÁUDIO` também o liga ao sampler como áudio único; o das zonas o liga só a uma zona nova.
- **Clipe toca uma vez numa posição; o sampler toca a cada nota.** Um clipe de áudio fica num ponto do arranjo, com fades e warp. Um sampler dispara o áudio sempre que uma nota (do piano roll, do teclado ou do MIDI) é tocada, e afina o áudio pela nota.
- **Áudio do sampler é usado na exportação.** O áudio escolhido e os áudios de todas as zonas entram na renderização da exportação junto com os clipes (ver [08 Exportação](08-exportacao.md)).
- **Não há sampler "a partir do clipe".** Não existe um comando que transforma um clipe já colocado no arranjo num sampler; o caminho é escolher o mesmo áudio no menu do sampler ou das zonas.

## Passo a passo

### Tocar uma nota gravada como instrumento

1. `Nova faixa` > `Sampler`. Abra o painel `Instrumento` (`I`).
2. No cartão `ÁUDIO`, clique em `Importar o áudio` e escolha o arquivo.
3. Descubra a altura do áudio (por exemplo, com o teclado da tela) e ponha o knob `Nota base` nela: se o áudio é um lá, `A3` ou `A4` conforme a oitava. Com o botão direito no knob, digite `A3`.
4. Toque o teclado da tela e confira que a nota base soa como o original (o ponto colorido marca a tecla).
5. Escolha o preset `Instrumento`, ou ajuste `Soltura` para o corte da nota ficar natural.

### Um golpe de percussão em qualquer nota

1. Importe o golpe (kick, palma, efeito) como acima.
2. Escolha o preset `Percussão (até o fim)`.
3. No piano roll, escreva o ritmo sempre na `Nota base` (C4 por padrão): a duração da nota não corta o áudio, só o começo importa.
4. Para variar o timbre, use notas mais agudas (a batida fica mais aguda e mais curta) ou graves (mais grave e mais longa).
5. Golpes repetidos na mesma nota não se cortam: com o `Modo` `Até o fim` cada golpe toca inteiro e o seguinte empilha por cima.

### Um pad a partir de um som longo

1. Importe um som sustentado e ajuste a `Nota base`.
2. Escolha `Pad lento`.
3. Escreva acordes longos no piano roll. No modo de áudio único o som toca uma vez sem loop e a nota fica muda quando o áudio acaba: use um áudio mais longo que as notas, ou (melhor) faça dele uma zona com loop: passo a passo em [Sustentar uma nota curta com loop](#sustentar-uma-nota-curta-com-loop).

### Trocar o áudio sem perder o timbre

1. Abra o menu do botão do arquivo e escolha outro áudio da lista, ou `Importar um arquivo…`.
2. O envelope, o `Modo` e o volume continuam; a `Nota base` e a `Afinação` também continuam: ajuste-as para o áudio novo.

### Fatiar um loop de bateria e tocar as fatias

1. `Nova faixa` > `Sampler` e abra o painel `Instrumento` (`I`).
2. Importe o loop: no cartão `ZONAS`, `Adicionar sample como zona` > `Importar um arquivo…`. (O loop entra no projeto e vira uma zona provisória que cobre o teclado; o passo seguinte a substitui.)
3. Clique em `Fatiar sample…`. Em `ÁUDIO` confira o loop, deixe `Por transientes` e mexa em `Sensibilidade` até a prévia mostrar uma linha em cada golpe que você quer separar (um loop de 1 compasso em colcheias costuma dar 8 fatias; se sobrar corte no meio de uma nota, baixe a sensibilidade; se faltar chimbal, suba). Para um corte regular, use `N fatias iguais` e `16`.
4. Confira o resumo (`8 fatias: C1 a G1, uma nota cada, ...`) e clique em `Criar`. O mapa passa a mostrar uma coluna estreita por fatia, de C1 em diante.
5. Escolha o preset `Percussão (até o fim)`: ataque instantâneo. As fatias são `Até o fim`, então a `Sustentação` e a nota solta não as afetam, e a mesma fatia repetida rápido **não corta a anterior**: as duas soam juntas (até 16 vozes). A `Soltura` de 50 ms só entra quando o transporte para.
6. Ouça: no teclado da tela desça duas vezes com `Oitava abaixo` (de C3 para C1) e toque; ou toque as teclas embaixo do mapa. Cada tecla é uma fatia, na ordem em que aparecem no loop.
7. No piano roll, escreva as notas nas linhas C1, C#1, D1, ...: para refazer o loop original, uma nota por batida na ordem 1, 2, 3, ...; para reorganizar, embaralhe a ordem, repita uma fatia, tire outra. A duração da nota não corta a fatia.
8. Ajuste cada fatia que precise: clique no bloco dela e mexa em `Ganho` (por exemplo -3 dB no chimbal), `Pan` ou `Afinação`.
9. Em vez de escrever as notas no piano roll, use a aba `Passos` do painel de baixo: uma linha por fatia (`Fatia 1 · C1`, `Fatia 2 · C#1`...), um clique por passo, com swing, acentos e fantasmas. Ver [05c Sequenciador de passos](05c-sequenciador-de-passos.md).

### Montar um instrumento multi-sample com 3 arquivos

O exemplo usa três gravações da mesma nota em alturas diferentes (um piano em C2, C4 e C6). Cada arquivo cobre uma região do teclado e é afinado a partir da nota em que foi gravado.

1. `Nova faixa` > `Sampler`; painel `Instrumento` (`I`).
2. `Adicionar sample como zona` > `Importar um arquivo…` e escolha a gravação grave (C2). A zona nasce cobrindo o teclado inteiro (de C-1 a G9), com `Nota base` C4.
3. Ajuste a `Nota base` dessa zona para a nota real do arquivo: clique no campo `Nota base`, digite `C2` (ou `36`) e aperte Enter.
4. Encolha a zona: arraste a borda direita do bloco até a nota 47 (B2). Confira em `até` do primeiro par (`B2`). A zona grave cobre de C-1 a B2, e a região livre passa a ser o resto do teclado.
5. `Adicionar sample como zona` > `Importar um arquivo…` com o arquivo do meio (C4). A zona nasce **na maior lacuna** (de C3 a G9, sem invadir a zona grave), com a `Nota base` em `C4`, que já é a nota real desse arquivo: confira o campo. Arraste a borda direita do bloco até a nota 71 (B4).
6. Repita com o arquivo agudo (C6): a lacuna que sobra é de C5 a G9 e a zona nasce com a `Nota base` em `C5` (a nota da lacuna mais perto do C4); digite `C6` no campo `Nota base`.
7. Confira no teclado embaixo do mapa: todas as teclas de C-1 a G9 devem estar claras (cobertas). Toque uma tecla em cada região para ouvir e compare a emenda entre elas (B2/C3 e B4/C5): se a mudança de timbre incomodar, use o `Ganho` de cada zona para igualar o volume.
8. Escolha o preset `Instrumento` (ataque de 3 ms, soltura de 350 ms) para uma soltura natural.

Se você acrescentar uma zona sem ter encolhido as outras (o teclado todo coberto), o app divide ao meio a zona mais larga e mostra o aviso `O teclado já estava coberto: ...` (ver [Avisos](#zonas-a-barra-do-cartão)): confira as faixas no mapa.

Para dar camadas de força do toque a esse instrumento (um piano macio e um forte), ver o guia [Sampler multi-zona e fatiar loops](../guias/sampler-multi-zona-e-fatiar-loops.md).

### Sustentar uma nota curta com loop

1. Crie uma zona com um áudio que tenha uma parte estável no meio (um pad, um órgão, uma corda) e a `Nota base` certa.
2. No editor da zona, deixe `Sustentado`.
3. Marque `Loop enquanto a nota está presa`: o loop nasce de 25% a 75% do trecho, sombreado na forma de onda.
4. Arraste os cursores de `Loop` para um trecho estável (sem o ataque do começo nem a cauda do fim).
5. Segure uma nota: o som fica no trecho do loop até você soltar; ao soltar, a `Soltura` do envelope apaga o som.

## Combina com

- [04 Painel de instrumento](04-painel-de-instrumento.md): presets, teclado da tela, gestos dos knobs.
- [03 Áudio e clipes](03-audio-e-clipes.md): importar áudios, fades e ganho de clipes; os áudios do projeto são os mesmos que o sampler e as zonas usam.
- [05 Piano roll](05-piano-roll.md): escrever as notas que disparam as zonas; o painel `Vel.` (velocidade) é o que escolhe a camada de velocidade.
- [05c Sequenciador de passos](05c-sequenciador-de-passos.md): a aba `Passos` mostra uma linha por zona e programa as fatias em grade, como uma bateria (as zonas de um trecho do áudio aparecem como `Fatia N · <nota>`, as de áudio inteiro, como um piano multi-sample, como `Zona · <nota>`); o botão `Padrões` só existe na bateria.
- [05b Ferramentas MIDI](05b-ferramentas-midi.md): `Humanizar` (varia a velocidade e por isso a camada e o round-robin) e `Rampa de velocidade` (passeia pelas camadas); `Staccato` e `Legato` não mudam o tamanho de zonas `Até o fim`.
- [06c Painel de efeitos](06c-painel-de-efeitos.md): efeitos da faixa (reverberação, filtro) sobre todo o sampler; um insert atua sobre todas as zonas juntas.
- [07 Automação](07-automacao.md): dá para automatizar `Volume`, `Afinação` e o envelope; as propriedades de cada zona (ganho, pan, faixas, loop) não são automatizáveis.
- [08 Exportação](08-exportacao.md): as zonas e os áudios delas entram na exportação.
- [03b Warp e altura](03b-warp-e-altura.md): para esticar ou transpor um áudio sem mudar a duração, use um clipe de áudio, não o sampler.
- [Guia: sampler multi-zona e fatiar loops](../guias/sampler-multi-zona-e-fatiar-loops.md): piano com camadas de velocidade, kit a partir de um loop e round-robin.

## Limites e pegadinhas

- **Sem zonas, sem loop e sem recorte.** No modo de áudio único o áudio toca inteiro, uma vez. Para loop, trecho, camadas ou fatias, use zonas.
- **Com zonas, o cartão `ÁUDIO` não manda mais.** O áudio único, a `Nota base` e o `Modo` do cartão são ignorados (os knobs `Nota base` e `Modo` ficam apagados); só a `Afinação` do cartão continua, somada à de cada zona. O teclado da tela marca as notas que as zonas cobrem, e o cartão `ENVELOPE` não segue mais o `Modo` do cartão: segue o modo das zonas (todas `Até o fim`: `Decaimento`, `Sustentação` e `Soltura` ficam apagados e o desenho mostra só a subida; mistura: a legenda `zonas até o fim só usam o ataque`). O visor do cartão `ÁUDIO` deixa de mostrar o áudio único e a `Nota base` do cartão: diz `Usando N zonas` e não toca ao ser segurado (o teclado da tela toca as zonas). Ao acrescentar uma zona com o teclado todo coberto, a zona dividida ao meio mantém a `Nota base` dentro da faixa que sobrou (se ela ficaria fora, vai para a ponta e o aviso diz de qual nota para qual).
- **Até 128 zonas por faixa.** Com 128, `Adicionar sample como zona` fica desabilitado e a dica é o aviso `Não dá para criar outra zona: ...`; `Duplicar a zona` também fica **desabilitado** (esmaecido), e o tooltip dele passa a ser `Não dá para duplicar: as zonas já estão no limite de 128.` (fase 14; na fase 12 o botão seguia ativo e o clique não fazia nada nem avisava) `(testado só por testes automáticos)`. Apagar uma zona reabilita o botão. O motor também ignora zonas além de 128.
- **A primeira zona cobre o teclado inteiro; as seguintes ocupam a maior lacuna.** Sem lacuna, a zona mais larga é dividida ao meio e o app avisa (o `até` da zona antiga encurta e, se a `Nota base` dela ficaria acima da faixa que sobrou, ela vai para a ponta e o aviso diz de qual nota para qual). Uma zona nova nasce com a `Nota base` perto do C4 e não na altura real do áudio: digite a nota certa.
- **Zonas sobrepostas empilham, lacunas calam.** Duas zonas com a mesma nota e força tocam juntas; uma nota ou uma força que nenhuma zona cobre não soa. Ao dividir por velocidade, garanta que a mínima de uma seja a máxima da outra mais um (ou uma sobreposição pequena): um buraco de um valor deixa aquela força muda.
- **Velocidade nunca é 0.** A faixa é 1 a 127, e a velocidade que decide a zona é a do toque arredondada para 1 a 127.
- **Round-robin: 63 grupos.** O menu tem `nenhum` e `grupo 1` a `grupo 63`; um projeto com grupo acima de 63 é limitado a 63 ao abrir.
- **16 vozes.** Cada zona que dispara consome uma voz: uma nota com 3 camadas usa 3 vozes, então acordes com camadas gastam as 16 vozes depressa. Ao passar disso, a voz mais antiga (de preferência já solta) sai em um fade de 3 ms. Tocar a mesma nota de novo solta as anteriores **sustentadas** (que fazem a `Soltura`) e começa novas; as vozes `Até o fim` **não são soltas**, empilham até o limite das 16 (ver [Até o fim e a mesma nota de novo](#até-o-fim-e-a-mesma-nota-de-novo)). Uma fatia ou um golpe repetido muito rápido pode, portanto, gastar as vozes e roubar as mais antigas.
- **Mexer nas zonas com notas soando não corta nada**: cada voz guarda o áudio e o trecho da zona que a disparou. Um áudio que sai do projeto também deixa a voz terminar; o que muda é a próxima nota.
- **Zona sem áudio fica muda.** Se o áudio da zona não está neste aparelho (projeto aberto em outro aparelho), a zona não soa até ele chegar ou ser importado de novo; o mapa e o editor continuam mostrando a zona, e o editor avisa `Este áudio não está neste aparelho: o trecho e o loop ficam para quando ele voltar.`
- **Fatiar substitui as zonas atuais** da faixa (com aviso no diálogo; dá para desfazer). Fatia é sempre `Até o fim`, uma nota cada, a partir do C1, no máximo 96 (C1 a B8, notas 24 a 119). Com menos fatias o mapa acaba antes (94 fatias vão de C1 a A8): as notas abaixo do C1 e acima da última fatia não têm zona e ficam mudas.
- **Fatias não seguem o andamento.** Cada fatia toca no tamanho original, na altura original; mudar o andamento do projeto muda o espaçamento das notas, não a duração das fatias. `N fatias iguais` divide o áudio em tempo, não em batidas do andamento do projeto.
- **A prévia e o corte por transiente são calculados neste aparelho, no app.** O áudio precisa estar no aparelho; um áudio muito longo demora um pouco mais para a prévia (`(não confirmado)` o tempo em áudios longos).
- **Altura e duração andam juntas.** Tocar mais agudo encurta a nota; tocar mais grave a alonga. Acima de cerca de quatro oitavas da nota base (com o áudio na mesma taxa do motor), a velocidade de leitura para de subir, e as notas ainda mais agudas soam todas na mesma altura.
- **Formatos.** A decodificação depende do navegador (ou do aparelho, no Android); um formato não suportado produz o aviso de erro acima.
- **`Até o fim` ignora a nota solta e a `Sustentação`.** Nem o fim da nota no piano roll nem soltar a tecla cortam o áudio, e a voz não decai com a `Sustentação` abaixo de 100%. Parar o transporte solta tudo com a `Soltura`, mesmo nesse modo.
- **Áudio fora do aparelho.** Um projeto aberto em outro aparelho pode mostrar `Este áudio não está neste aparelho. Importe o arquivo de novo para ouvi-lo.` até que o áudio chegue ou seja importado de novo. `(não confirmado)`: se ele chega sozinho pela sincronização.
- **O que é salvo.** O áudio escolhido, a `Nota base`, a `Afinação`, o resto dos knobs e as zonas de cada faixa (áudio, notas, velocidades, nota base, afinação, ganho, pan, modo, grupo, trecho e loop) são guardados no projeto. O nome do preset não é. As zonas entram no desfazer.
- **O visor pode confundir**: a forma de onda é normalizada pelo pico, então um áudio muito baixo parece cheio; o volume real é o do arquivo.
- **Não testado em uso.** Este capítulo foi escrito lendo o código; o comportamento ouvido (emendas de loop, transientes em loops reais, arrastes no celular) está marcado `(não confirmado)` onde só foi deduzido. Só têm teste automático (widget e Rust), sem uso real no Chrome ou no Android, `(testado só por testes automáticos)`: a zona nova numa lacuna ou dividindo a existente (com a `Nota base` trazida para dentro da faixa), o erro inline dos campos digitáveis, o botão desabilitado com o aviso único de limite, `Camadas de velocidade` na faixa atual da zona, o envelope apagado com todas as zonas `Até o fim`, o visor `Usando N zonas`, o aviso e o botão `Menos sensibilidade` do diálogo com mais de 96 ataques, o arraste do corpo sem mexer na velocidade, a `Sustentação` ignorada e o empilhamento das vozes `Até o fim`, o grupo de round-robin até 63.

## Atalhos

| Tecla | Ação |
|---|---|
| `I` | Abre e fecha o painel `Instrumento` |
| `Ctrl+K` | Liga o teclado do computador (`A` a `P` tocam a partir da oitava mostrada no botão da barra; `Z`/`X` mudam a oitava) |
| Segurar o visor da forma de onda | Toca o áudio na nota base |
| Botão direito no knob `Nota base` (cartão `ÁUDIO`) | Digitar o valor (aceita `C4`, `F#3`) |
| Tocar ou segurar uma tecla embaixo do mapa | Ouve a nota, com 80% de força |
| Enter num campo de nota ou de velocidade do editor da zona | Confirma o valor digitado (sair do campo também confirma) |
| Arrastar borda de um bloco do mapa | Muda a faixa de notas (bordas esquerda e direita) ou de velocidade (bordas de cima e de baixo) da zona |
| Arrastar o corpo de um bloco do mapa | Move a zona só na horizontal (notas e `Nota base`); a velocidade não muda |
