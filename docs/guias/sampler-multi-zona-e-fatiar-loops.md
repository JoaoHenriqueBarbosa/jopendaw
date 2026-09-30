# Sampler multi-zona e fatiar loops

> Três receitas com as zonas do sampler: um piano multi-sample com duas camadas de força do toque (cerca de 20 minutos, com os arquivos já em mãos), um kit de bateria montado de um loop fatiado (cerca de 10 minutos) e um instrumento com round-robin para o mesmo golpe não soar mecânico (cerca de 10 minutos).

## Ingredientes

| Recurso | Para quê aqui | Capítulo |
|---|---|---|
| Faixa `Sampler`, cartão `ZONAS` (mapa de teclado e editor da zona) | Espalhar áudios pelo teclado, por força do toque, e ajustar cada um | [04c Sampler](../manual/04c-sampler.md) |
| `Fatiar sample…` | Cortar um loop em partes e dar uma nota a cada uma | [04c Sampler](../manual/04c-sampler.md#fatiar-sample) |
| `Duplicar a zona` e `Round-robin` | Camadas e variações sem refazer tudo | [04c Sampler](../manual/04c-sampler.md#o-editor-da-zona) |
| Envelope e `Sens. vel.` do sampler | Soltura natural e quanto a força do toque muda o volume | [04c Sampler](../manual/04c-sampler.md), [04 Painel de instrumento](../manual/04-painel-de-instrumento.md) |
| Piano roll e painel `Vel.` | Escrever as notas e a força de cada uma | [05 Piano roll](../manual/05-piano-roll.md) |
| Ferramentas MIDI (`Humanizar`, `Rampa de velocidade`) | Variar força e tempo; passear pelas camadas | [05b Ferramentas MIDI](../manual/05b-ferramentas-midi.md) |
| Efeitos `Compressor`, `Reverb`, `EQ`, `Filtro` | Cola, espaço e acabamento sobre o sampler inteiro | [06c Painel de efeitos](../manual/06c-painel-de-efeitos.md), [06d Referência dos efeitos](../manual/06d-efeitos-referencia.md) |
| Automação (botão `A`) | Mover `Volume`, `Afinação` ou o `Corte` do filtro ao longo da música | [07 Automação](../manual/07-automacao.md) |

Os números daqui são pontos de partida musicais: ajuste de ouvido. O que depende do programa (rótulos, faixas de valor, o que cada botão faz) vem do código; o que soa em cada passo é `(não confirmado em uso)`.

## Antes de começar: como o sampler decide o que toca

Cada nota dispara **todas as zonas** cuja faixa de notas e cuja faixa de velocidade a contêm, e cada zona ocupa uma voz (são 16). Zonas sobrepostas empilham; buraco no mapa fica mudo. A força que decide a camada é a velocidade da nota, de 1 a 127 (a bolinha do painel `Vel.` no piano roll). O `Velocidade` do cartão `GERAL` (padrão 70%) escala o volume pela força por cima disso: com 70% um toque de velocidade 64 sai cerca de 6,4 dB abaixo do máximo; com 35%, cerca de 2,6 dB. Quando as camadas já trazem a dinâmica nas próprias gravações, um `Velocidade` menor evita que a dinâmica seja aplicada duas vezes.

## Receita 1: piano multi-sample com camadas de velocidade

Resultado: um piano com duas regiões do teclado, cada uma com uma gravação suave e uma forte; tocar fraco usa a suave, tocar forte usa a forte. Precisa de 4 arquivos de áudio: por exemplo `piano_C3_suave`, `piano_C3_forte`, `piano_C5_suave`, `piano_C5_forte` (cada um uma nota única, gravada na altura do nome).

### Passo a passo

**1. Faixa e envelope**

1. `Nova faixa` > `Sampler`; abra `Instrumento` (`I`).
2. Escolha o preset `Instrumento` (ataque 3 ms, soltura 350 ms, `Sens. vel.` 80%).
3. No cartão `GERAL`, baixe `Sens. vel.` para 35%: as camadas já cuidam da dinâmica.

**2. A região grave (C3): camada suave**

1. No cartão `ZONAS`, `Adicionar sample como zona` > `Importar um arquivo…` e escolha `piano_C3_suave`. A zona nasce cobrindo o teclado todo (de C-1 a G9), `Nota base` C4.
2. No editor da zona, leve a `Nota base` a `C3`: toque no número da `Nota base`, digite `C3` (ou `48`) e aperte Enter.
3. No mapa, arraste a borda direita do bloco até a nota 59 (B3): a zona fica de C-1 a B3. Confira no primeiro par (`Notas de` `C-1`, `até` `B3`).

**3. A região aguda (C5): camada suave**

1. `Adicionar sample como zona` > `Importar um arquivo…` e escolha `piano_C5_suave`. A zona ocupa a lacuna que sobrou (de C4 a G9), com a `Nota base` em `C4`.
2. Leve a `Nota base` a `C5` digitando `C5` no campo dela (ela nasce em `C4`, a nota mais perto do dó central que cabe na faixa).

**4. As camadas fortes**

1. Selecione a zona grave (toque no bloco dela) e clique em `Duplicar a zona`: a cópia fica logo depois, na mesma faixa de notas.
2. Com a cópia selecionada, clique no nome do áudio (tooltip `Trocar o áudio da zona`) e escolha `piano_C3_forte`. A `Nota base` continua `C3`.
3. Repita com a zona aguda: `Duplicar a zona` e troque o áudio por `piano_C5_forte`.

**5. Dividir por força do toque**

O objetivo é: suaves cobrem as velocidades 1 a 83; fortes cobrem de 81 a 127 (uma sobreposição de 3 valores, em vez de um buraco). As duas camadas tocam juntas nesses 3 valores.

1. Selecione uma zona suave. No mapa, arraste a borda **de cima** do bloco para baixo até o segundo par (`Velocidade de` / `até`) mostrar `até` perto de 83. Ajuste fino digitando o valor no campo ou com `Menos` e `Mais` (1 em 1). Para camadas iguais sem conta, `Camadas de velocidade` > `Dividir em 2 camadas iguais` (ver o manual do sampler).
2. Selecione a zona forte da mesma região. Arraste a borda **de baixo** para cima até `Velocidade de` mostrar 81 (ou 1 a 3 acima do `até` da suave: sobrepor é seguro, deixar um valor sem zona o deixa mudo).
3. Faça o mesmo para a outra região.
4. Confira o mapa: dois andares de blocos em cada região, o de baixo (suave) e o de cima (forte), sem vão entre eles.

**5b. Igualar os volumes**

1. Toque uma nota em cada camada (o teclado embaixo do mapa toca com força 102, que cai na camada forte; para ouvir a suave, use o teclado da tela ou um clipe com velocidades baixas).
2. Se a forte estiver desproporcional, use `Ganho` na zona: por exemplo `-2.0 dB` na forte, ou `+1.5 dB` na suave.

**6. Escrever e conferir**

1. Abra ou crie um clipe MIDI da faixa (duplo clique no vazio da faixa) e escreva uma frase simples.
2. No painel `Vel.`, deixe as notas do começo em cerca de 50 e as do fim em cerca de 110: a frase passa da camada suave para a forte.
3. Com as notas selecionadas, `Rampa de velocidade` (menu `Ferramentas`) faz a passagem em linha reta entre a primeira e a última nota: defina 40 na primeira e 115 na última antes.

**7. Efeitos, na aba `Efeitos` da faixa**

| Efeito | Ajuste | Por quê |
|---|---|---|
| `EQ` | Banda 1 ligada (`Ligada` `Sim`), `Tipo` `Passa-alta`, `Frequência` 40 Hz, `Inclinação` `12 dB/oit` | Tira o rumor grave que as gravações trazem |
| `Compressor` | `Limiar` -18 dB, `Razão` 2:1, `Ataque` 30 ms, `Soltura` 200 ms | Suaviza a passagem entre camadas de volumes diferentes sem achatar |
| `Reverb` | `Mistura` 20%, `Decaimento` 2.2 s (o padrão), `Cortar graves` 120 Hz | Espaço; o piano fica em sala, não seco |

### Variações

- **Mais regiões e camadas.** O mesmo processo com 3 ou 4 regiões por oitava e meia soa mais natural: quanto mais perto da nota gravada, menos o timbre muda ao esticar.
- **Três camadas.** Duplique de novo e divida a força em 1 a 50, 48 a 90 e 88 a 127 (sobreposições de 2 a 3 valores).
- **Piano que respira.** Automatize o `Corte` de um `Filtro` (`Tipo` `Passa-baixa 24`) no clipe: o piano abre nos refrãos. Veja [07 Automação](../manual/07-automacao.md).
- **Humanizar a interpretação.** Com as notas selecionadas, `Humanizar…` com `Tempo` 20% e `Velocidade` 20% (a variação de velocidade cruza a divisão das camadas, então nem toda nota fica na camada que você escreveu: é o efeito desejado).
- **Zona com loop para as notas longas.** Se o arquivo é longo o bastante, no editor da zona `Sustentado` + `Loop enquanto a nota está presa` sustenta a nota para além do arquivo. Veja [04c](../manual/04c-sampler.md#sustentar-uma-nota-curta-com-loop).

### Por que funciona

O mapa é um quadro de notas por força: cada arquivo ocupa um retângulo, e a nota toca o retângulo em que cai. Duas gravações da mesma nota em forças diferentes trocam o timbre (o piano forte tem harmônicos que o suave não tem), que é o que dá realismo a um teclado que só muda o volume. A sobreposição pequena entre camadas evita o buraco de força; a soma das duas ali é curta e quase inaudível `(não confirmado em uso)`. Baixar o `Velocidade` do sampler evita contar a dinâmica duas vezes.

### Se der errado

| Sintoma | Causa provável | O que fazer |
|---|---|---|
| Algumas notas não soam | Nota fora de todas as zonas, ou força num vão entre as camadas | Olhe as teclas embaixo do mapa (as cobertas ficam claras) e confira `Velocidade de` e `até` |
| Duas zonas tocam juntas o tempo todo | As faixas de velocidade se sobrepõem demais | Arraste as bordas até os números mostrarem faixas separadas |
| As duas camadas soam iguais | As duas zonas apontam para o mesmo áudio | Selecione a zona e troque o áudio (`Trocar o áudio da zona`) |
| Notas altas soam finas ou curtas | Zona esticada demais a partir da nota base | Acrescente mais gravações e encurte as regiões |
| A região aguda sai muito acima ou abaixo da nota certa | `Nota base` errada (a nova zona nasce com a base em `C4`, ou na nota da faixa mais perto dele) | Digite a `Nota base` certa (`C5`, `A#3` ou o número) |
| A segunda zona nasceu por cima da primeira | A primeira cobria o teclado inteiro | Encurte a primeira antes de acrescentar a próxima (passo 2.3) |
| Acorde longo com camadas corta notas | Cada nota usa uma voz por camada e o limite é 16 | Use uma camada por região, ou toque menos notas juntas |

## Receita 2: kit de bateria a partir de um loop fatiado

Resultado: cada golpe de um loop de bateria vira uma tecla; com elas você refaz, reordena e reescreve o ritmo no piano roll. Precisa de um loop de bateria de 1 ou 2 compassos (arquivo de áudio).

### Passo a passo

**1. Fatiar**

1. `Nova faixa` > `Sampler`; painel `Instrumento` (`I`).
2. No cartão `ZONAS`, `Adicionar sample como zona` > `Importar um arquivo…` e escolha o loop. (Ele vira uma zona provisória; o fatiamento a substitui.)
3. Clique em `Fatiar sample…`. Em `ÁUDIO` confirme o loop.
4. Deixe `Por transientes` e `Sensibilidade` em 50%. Veja a prévia: uma linha numerada em cada golpe. Se faltar o chimbal, suba a `Sensibilidade` (até 70%); se aparecerem cortes no meio de uma nota, baixe (30%).
5. Se o loop é regular e você prefere corte por tempo, clique em `N fatias iguais` e escolha `16` (com um loop de um compasso em 4/4, uma fatia por semicolcheia).
6. Confirme o resumo (por exemplo, `8 fatias: C1 a G1, uma nota cada, tocando até o fim de cada trecho.`) e clique em `Criar`.

**2. Ouvir e nomear**

1. Escolha o preset `Percussão (até o fim)`: ataque de 0,5 ms e soltura de 50 ms; o `Modo` dele não vale com zonas (cada fatia é `Até o fim` sozinha), mas o envelope curto vale.
2. Abaixe a oitava do teclado da tela até C1 (`Oitava abaixo` duas vezes a partir de C3) e toque cada tecla. Anote no papel qual fatia é qual (kick, snare, hat...): o app não dá nome às fatias.
3. No mapa, cada fatia é uma coluna estreita; toque nas teclas embaixo do mapa para ouvir também.

**3. Acertar cada peça**

Toque num bloco para abrir o editor da fatia:

| Peça | Ajuste | Valor |
|---|---|---|
| Chimbal (hat) | `Ganho` | -4.0 dB |
| Chimbal | `Pan` | `D20` (20% para a direita) |
| Caixa (snare) | `Ganho` | 0.0 dB |
| Bumbo (kick) | `Ganho` | +1.0 dB |
| Qualquer fatia com estalo no começo ou lixo no fim | `Trecho` | Arraste o cursor do início alguns milissegundos para dentro ou o do fim para trás |
| Uma fatia que tem dois golpes | Apague (`Apagar a zona`) o que não serve ou faça outra fatia | |

**4. Escrever o ritmo**

1. Crie um clipe MIDI de 1 compasso na faixa (duplo clique no vazio) e abra o piano roll (`E`).
2. Escreva as notas nas linhas C1, C#1, D1... (a fatia 1 é a nota C1, a 2 é C#1, etc.). Para refazer o loop original: uma nota em cada golpe, na ordem 1, 2, 3, ... na grade em que o loop foi tocado. Para variar: repita a fatia do bumbo, tire o segundo chimbal, embaralhe a ordem.
3. Grade em 1/16. A duração das notas não importa (cada fatia toca até o fim), então use notas curtas.
4. No painel `Vel.` dê acentos: contratempos em 70 a 90, batidas fortes em 100 a 120.
5. Selecione tudo e `Humanizar…`: `Tempo` 20% e `Velocidade` 25%, para não soar de máquina.

**5. Efeitos e automação**

| Efeito | Ajuste | Por quê |
|---|---|---|
| `Compressor` | `Limiar` -18 dB, `Razão` 4:1, `Ataque` 10 ms, `Soltura` 150 ms | Cola as fatias, que vêm de gravações diferentes de níveis |
| `Reverb` | `Mistura` 12%, `Decaimento` 1.2 s, `Pré-atraso` 20 ms | Sala curta que junta o kit |
| `Filtro` | `Tipo` `Passa-baixa 24`, `Corte` 20 kHz, depois automatizado para 800 Hz | Um build-up: ver abaixo |

1. Para um build-up antes do refrão: botão `A` da faixa > `Volume` (o fader da faixa) para um crescendo, ou, com um `Filtro` na cadeia, o submenu do efeito (por exemplo `1. Filtro`) > `Corte`, de 20 kHz até 800 Hz durante 4 compassos.
2. A `Afinação` do cartão `ÁUDIO`, automatizada de 0 a -100 ct (botão `A` > submenu com o nome do instrumento, `(não confirmado)` o rótulo exato), desce a altura de todas as fatias juntas, somada à `Afinação` de cada zona; é um efeito de fita desacelerando, discreto (um semitom no máximo).

### Variações

- **Kit por peça.** Fatie com `Por transientes`, depois apague as zonas que não quer e mantenha só bumbo, caixa e chimbal: o teclado fica limpo.
- **Loop com mais de 96 golpes.** O máximo é 96 fatias (C1 a B8). Por transientes, o app guarda o começo do áudio e os 95 ataques mais fortes (não os 95 primeiros) e o resumo já mostra `96 fatias: C1 a B8, ...`; o aviso `Passa do limite de 96 fatias: só as primeiras viram nota.` existe no código, mas hoje não chega a aparecer. Baixe a `Sensibilidade` para ficar só com os golpes fortes.
- **Reordenar as fatias.** O `Legato`, o `Staccato` e as outras ferramentas de duração não mudam nada aqui (cada fatia toca até o fim); `Inverter na altura` e `Reverter a ordem das notas` trocam quais fatias tocam. Ver [05b Ferramentas MIDI](../manual/05b-ferramentas-midi.md).
- **Trocar o andamento.** Fatias não se esticam: com um andamento mais lento, as notas se afastam e você ouve as caudas; mais rápido, as fatias se sobrepõem. Ajuste a `Soltura` (50 ms) e a nota mais curta.

### Por que funciona

Cada fatia é uma zona de uma nota só, com o trecho da fatia, modo `Até o fim` e nota base igual à própria nota: tocar a tecla toca a fatia na altura original, e a duração da nota no piano roll não importa. O corte por transiente acha o começo de cada golpe e o ajusta ao cruzamento de zero mais próximo, então as fatias começam sem estalo; a descida de 1 ms no fim de cada uma fecha o corte sem clique. Como o loop virou um teclado, você reescreve o ritmo com todas as ferramentas do piano roll.

### Se der errado

| Sintoma | Causa provável | O que fazer |
|---|---|---|
| `Nenhum corte achado` ou uma fatia só | Áudio sem ataques claros, ou `Sensibilidade` baixa | Suba a `Sensibilidade`, ou use `N fatias iguais` |
| Fatias demais (o chimbal virou 6 fatias) | `Sensibilidade` alta | Baixe a `Sensibilidade` até a prévia ficar com uma linha por golpe |
| A prévia não aparece, ou `Este áudio não está neste aparelho...` | O áudio do projeto não foi carregado neste aparelho | Importe o arquivo de novo |
| Uma fatia soa com um pedaço do golpe seguinte | O corte caiu antes do ataque | Ajuste o `Trecho` da fatia (o `fim`), ou refaça com outra `Sensibilidade` |
| Repetir a mesma nota rápido corta a anterior | Mesma nota de novo solta a anterior com a `Soltura` (50 ms com o preset da receita) | Aumente a `Soltura`, ou espalhe as repetições em fatias duplicadas |
| Nada soa nas notas escritas | A nota escrita está fora de C1 em diante, ou acima do número de fatias | Confira no mapa quais notas têm bloco |
| Perdi as zonas de antes | `Criar` substitui as zonas da faixa | Desfaça (`Ctrl+Z`) logo em seguida |

## Receita 3: round-robin para o mesmo golpe não soar mecânico

Resultado: uma caixa (ou qualquer golpe repetido) que alterna entre três gravações levemente diferentes a cada nota, em vez de repetir sempre o mesmo áudio. Precisa de 3 gravações do mesmo golpe (`caixa_a`, `caixa_b`, `caixa_c`); sem elas, veja a variação com um arquivo só.

### Passo a passo

1. `Nova faixa` > `Sampler`; painel `Instrumento` (`I`). Escolha o preset `Percussão (até o fim)`.
2. No cartão `ZONAS`, `Adicionar sample como zona` > `Importar um arquivo…` e escolha `caixa_a`. A zona cobre o teclado todo, com `Nota base` C4: tocar C4 toca o áudio na altura original.
3. No editor, ponha o modo em `Até o fim`. Em `Round-robin`, escolha `grupo 1`.
4. Clique em `Duplicar a zona`: a cópia (mesmo mapa, mesma nota base, mesmo modo e mesmo grupo) fica selecionada. Clique no nome do áudio (`Trocar o áudio da zona`) e escolha `caixa_b`.
5. Duplique de novo e troque o áudio por `caixa_c`. Agora são 3 zonas no `grupo 1`.
6. Um pouco de variação a mais em cada uma:

| Zona | `Ganho` | `Afinação` | `Pan` |
|---|---|---|---|
| `caixa_a` | 0.0 dB | 0 ct | `C` |
| `caixa_b` | -0.5 dB | +8 ct | `D3` |
| `caixa_c` | -1.0 dB | -8 ct | `E3` |

7. No piano roll, escreva um padrão sempre na nota C4 (a `Nota base`): por exemplo, semicolcheias em 1/16 por dois compassos, com velocidades de 70 a 110.
8. Toque: a cada nota o sampler passa para a próxima gravação, na ordem das zonas na lista (a, b, c, a, b, c...). Repita a mesma nota e você ouve o rodízio.

**Efeitos e ferramentas**

1. `Compressor` (`Limiar` -18 dB, `Razão` 3:1, `Ataque` 8 ms) para colar as três gravações.
2. `Reverb` (`Mistura` 10%, `Decaimento` 0.8 s) para dar um espaço curto.
3. Selecione as notas e `Humanizar…` com `Tempo` 15% e `Velocidade` 20%.
4. Automação: botão `A` > `Volume` (o fader da faixa) para um crescendo na frase.

### Variações

- **Round-robin com camadas de força.** Faça 3 zonas suaves no `grupo 1` (`Velocidade de` 1 a 83) e 3 fortes no `grupo 2` (`Velocidade de` 81 a 127). Um grupo por camada mantém cada uma em ordem estrita; se todas dividissem o mesmo grupo, cada camada poderia pular gravações.
- **Um arquivo só.** Faça três zonas com o mesmo áudio (`Duplicar a zona` sem trocar o áudio), no mesmo grupo, e varie: `Afinação` -10, 0 e +10 ct; `Trecho` começando em 0.000, 0.004 e 0.008 s; `Ganho` 0, -0.7 e -1.4 dB. A variação é sutil e ajuda pouco, mas tira o efeito de metralhadora.
- **Vários instrumentos numa faixa.** Ponha a caixa numa região do teclado (por exemplo, a nota D2 e a `Nota base` D2, encolhendo a zona com as bordas do mapa) e outro golpe em outra, com o próprio grupo: cada peça gira sozinha.
- **Corte diferente.** Em vez de `Até o fim`, deixe `Sustentado` e a `Soltura` do preset `Instrumento` (350 ms) para um som de nota tocada com pedal.

### Por que funciona

Zonas do mesmo grupo que casam com a mesma nota e força dividem um contador: a cada nota o motor avança o contador e toca só a zona da vez (`contador` módulo o número de zonas que casam). Assim a mesma nota nunca repete o mesmo áudio duas vezes seguidas. O `Ganho`, a `Afinação` e o `Pan` por zona somam variações que o ouvido não separa mas sente como "vivo". Zonas fora do grupo (grupo `nenhum`) não alternam: tocam sempre.

### Se der errado

| Sintoma | Causa provável | O que fazer |
|---|---|---|
| Sempre a mesma gravação | As zonas estão em `nenhum`, ou em grupos diferentes | Ponha as três no mesmo `grupo` |
| As três tocam juntas | Grupo `nenhum` nas três | Ponha `grupo 1` em todas |
| Soa só uma das três | A faixa de notas ou de velocidade das outras não cobre a nota | Confira `Notas de`, `até` e as velocidades de cada uma |
| A ordem pula uma gravação | Duas regiões ou camadas dividem o mesmo grupo | Um grupo por região e camada |
| O rodízio recomeça na primeira depois de editar | Editar uma zona reenvia a lista e reinicia o ciclo `(não confirmado em uso)` | É esperado: toque de novo depois de editar |
| A repetição rápida de uma nota corta a cauda da anterior | A mesma nota solta a anterior com a `Soltura` | Reduza a `Soltura` (50 ms) ou espalhe mais as notas |

## Combina com

- [04c Sampler](../manual/04c-sampler.md): cada botão e campo do mapa, do editor e do diálogo `Fatiar sample`.
- [05 Piano roll](../manual/05-piano-roll.md): escrever as notas e as velocidades que escolhem camadas e fatias.
- [05b Ferramentas MIDI](../manual/05b-ferramentas-midi.md): `Humanizar`, `Rampa de velocidade`, `Legato`, `Staccato`.
- [06c Painel de efeitos](../manual/06c-painel-de-efeitos.md) e [efeitos em combinação](efeitos-em-combinacao.md): compressor, reverb, filtro e EQ no sampler.
- [07 Automação](../manual/07-automacao.md) e [mixagem e automação](mixagem-e-automacao.md): mover volume, afinação e corte ao longo do tempo.
- [Melodia e harmonia com as ferramentas](melodia-e-harmonia-com-as-ferramentas.md): o que escrever para o piano da receita 1.
