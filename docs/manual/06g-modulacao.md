# Modulação (LFO, seguidor de envelope e macro)

> Faz um controle andar sozinho em volta do valor que você deixou nele: um LFO balança o corte de um filtro no andamento, o volume vira tremolo, o pan passeia entre os lados, um seguidor de envelope abre e fecha um parâmetro com o nível da própria faixa. Use quando a automação desenhada seria repetitiva (o mesmo movimento em cada tempo) ou quando o movimento deve responder ao som.

Legenda de confiança deste capítulo: quase tudo vem da leitura do código (`engine/src/modulation.rs`, `app/lib/daw/modulation*.dart`) e de testes automáticos `(testado só por testes automáticos)`: 20 testes do motor (`modulation_tests.rs`) e 18 do app (`modulation_test.dart`). A sessão de código relatou um teste de uso no Chrome com o preset `Tremolo no volume` numa faixa `Pad` (cartão `1 · LFO senoide · 6,0 Hz`, destino `Volume +15%`, pico do motor oscilando entre 0,021 e 0,216); as três capturas de tela deste capítulo (aba vazia, cartão do LFO com o destino `Volume +15%` e menu `Presets`, tiradas no Chrome) conferem os rótulos e a disposição, mas quem escreveu esta documentação não repetiu o teste sonoro, e **nada foi ouvido** nem visto no Android. O que só se leu no código leva `(não confirmado)`.

## Onde fica

- **Aba `Modulação`** no painel de baixo, ao lado de `Efeitos` (ícone de ondas; tooltip `Modulação da faixa: LFO, seguidor de envelope e macros`; abaixo de 560 px de largura a aba mostra só o ícone). Ela mostra os moduladores de **uma** faixa por vez: a faixa do rack de efeitos, que é a selecionada; sem faixa selecionada, o `Master`. Trocar de faixa com a aba aberta troca o conteúdo. Não há atalho de teclado para a aba; `Esc` ou o `X` do painel a fecha.
- **Assunto** ao lado das abas: `<faixa> · sem moduladores`, `<faixa> · 1 modulador` ou `<faixa> · N moduladores` (`Master · ...` no master), com o ponto na cor da faixa (branco no `Master`).
- **Menu `Modular…`** de um controle: clique com o botão direito (toque longo no celular) num knob do [painel de instrumento](04-painel-de-instrumento.md) ou do [painel de efeitos](06c-painel-de-efeitos.md); botão direito do **mouse** no fader e no pan do [mixer](06-mixer.md) (inclusive os do `Master`). Ele abre um seletor e, ao escolher, a aba `Modulação` abre na faixa do controle.
- **Só com controle que se move de forma contínua.** Os seletores de opção e os inteiros não têm `Modular…` (ver [O que a modulação não alcança](#o-que-a-modulação-não-alcança)).
- **Celular (Android):** o mesmo motor e a mesma aba. A diferença é o gesto: toque longo nos knobs no lugar do botão direito. O fader e o pan do mixer **não** têm toque longo fora do modo `Aprender MIDI` (só o botão direito do mouse); no celular, ligue o fader, o pan e o nível de envio pela lista `Destino` do cartão (ver abaixo), que traz `Volume`, `Pan` e `Envio → nome`.

## Controles

### Cabeçalho da aba

| Controle (rótulo exato) | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| Texto `<faixa> · N/4 moduladores` | Diz de quem é a aba e quantos moduladores ela tem | Máximo 4 por faixa (e 4 no `Master`) | Numa faixa nova: `0/4 moduladores` |
| `Adicionar` (tooltip `Adicionar um modulador`) | Abre o menu `LFO`, `Seguidor de envelope`, `Macro` e cria o modulador **sem destino** | Desligado com 4 moduladores (tooltip `A faixa já tem 4 moduladores`) | Um modulador sem destino não faz nada |
| `Presets` (tooltip `Modulações prontas`) | Abre o menu dos quatro presets (cada item mostra nome e uma linha de descrição) e cria o modulador **já com o destino** | Desligado com 4 moduladores. Ver [Presets](#presets) | Recusa com aviso vermelho se a faixa não tem o controle que o preset move |
| Aviso em vermelho (com `X` para dispensar) | Diz por que a última ação foi recusada | `A faixa já tem 4 moduladores.` · `<preset>: esta faixa não tem o controle que o preset move.` | Erro fica na tela, sem toast |
| Estado vazio | Instrução no meio da aba | `Nenhum modulador. Adicione um LFO, um seguidor de envelope ou uma macro (ou use um preset) e ligue a controles: botão direito (ou toque longo) num knob ou fader, "Modular…".` | O texto diz "fader" mesmo no celular, onde o fader não tem toque longo |

Os cartões ficam lado a lado e quebram de linha, cada um com 200 a 340 px de largura, com rolagem vertical.

![A aba Modulação numa faixa `Pad` sem moduladores: cabeçalho `Pad · 0/4 moduladores`, os botões `Adicionar` e `Presets` e a instrução do estado vazio; o assunto ao lado das abas diz `Pad · sem moduladores`.](../img/modulacao-aba-vazia.jpg)

*A aba `Modulação` numa faixa sem moduladores.*

### Cartão de um modulador (parte comum)

| Controle (rótulo exato) | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| Título `N · <resumo>` (ícone de ondas para o LFO, de gráfico para o seguidor, de ajustes para a macro) | Número do modulador na faixa (de 1) e um resumo | LFO livre: `1 · LFO senoide · 6,0 Hz`; LFO no andamento: `1 · LFO senoide · 1/8`; seguidor: `2 · Seguidor de envelope`; macro: `3 · Macro · 0%` | A taxa livre sai com 2 casas abaixo de 1 Hz (`0,25`), 1 casa até 10 Hz (`6,0`), 0 casas acima (`12`). É o mesmo texto do seletor do `Modular…` |
| `X` (tooltip `Apagar o modulador`) | Apaga o modulador e os destinos dele | Um passo no desfazer | Os controles voltam ao valor base |
| Linha de destino: nome do controle, `+25%`, `Tirar este destino` (ícone de elo quebrado) | Um destino do modulador; o botão tira só ele | Nome como no menu `A` da automação: `Volume`, `Pan`, `Instrumento · Corte`, `Filtro · Corte`, `Envio → Reverb`. Se o alvo sumiu: `Destino removido` | Até 4 destinos por modulador |
| Barra deslizante sob o destino (a profundidade) | Quanto do curso do controle o modulador percorre | **−100% a +100%**, padrão de destino novo **+25%**; a leitura sai como `+25%`, `0%`, `-25%` | Negativo inverte o sentido. Um arraste inteiro é um passo no desfazer. Não há campo para digitar |
| `Destino` (tooltip `Ligar a um controle`) | Menu com os controles da faixa que ainda não são destino deste modulador | Volume, Pan, parâmetros do instrumento, parâmetros de cada efeito (`Filtro · Corte`), envios; só os que se modulam. Desligado com 4 destinos (tooltip `Cada modulador tem no máximo 4 destinos`) ou quando não sobra controle | O destino novo nasce com +25% |

Os knobs do cartão (cor ciano) são os mesmos knobs do resto do app: arrastar na vertical (200 px percorrem o curso; `Shift`, ajuste fino), roda do mouse, duplo clique volta ao padrão, botão direito ou toque longo abre o campo de digitar o valor. Eles **não** têm `Aprender MIDI` nem automação.

### Cartão do LFO

O LFO (oscilador de baixa frequência) é uma onda que sobe e desce; a saída dele é multiplicada pela profundidade do destino e somada ao valor base.

![O cartão `1 · LFO senoide · 6,0 Hz` (preset `Tremolo no volume`): lista de forma `Senoide`, chips `Livre` e `Andamento`, knobs `Taxa` (6.00 Hz), `Profund.` (100%) e `Fase` (0°), chips `Bipolar` e `Unipolar`, o destino `Volume` em `+15%` com a barra e o botão de tirar o destino, e o botão `Destino`.](../img/modulacao-lfo.jpg)

*O cartão de um LFO livre com um destino de volume.*

| Controle (rótulo exato) | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| Lista de forma | Escolhe a onda | `Senoide` (padrão), `Triângulo`, `Dente de serra`, `Quadrada`, `Sample & hold` | Senoide e triângulo começam em 0 e sobem; a serra sobe de −1 a +1 e cai de uma vez; a quadrada começa em cima; o `Sample & hold` sorteia um valor novo a cada ciclo e o segura (o sorteio é sempre o mesmo para o mesmo ciclo, então o render sai igual ao que se ouviu) |
| `Livre` / `Andamento` (chips; o ativo fica aceso e não clica) | `Livre`: a taxa é em Hz, independente da música. `Andamento`: cada ciclo dura uma divisão de compasso e acompanha o andamento | Padrão `Livre` | Com `Andamento` o knob `Taxa` dá lugar à lista de divisões. A taxa livre e a divisão ficam guardadas as duas ao alternar |
| `Taxa` (knob, só em `Livre`) | Velocidade em Hz | 0,01 a 50 Hz, escala logarítmica, padrão 1 Hz | Leitura `1.00 Hz`, `12 Hz` |
| Lista de divisões (só em `Andamento`) | Duração de um ciclo | 24 itens: `4 compassos`, `2 compassos`, `1 compasso`, `1/2`, `1/4`, `1/8`, `1/16`, `1/32`, cada um em três versões: reta, `pontilhada` (1,5 vez mais longa) e `tercina` (2/3 da duração). Padrão `1/4` | `1/4` é um ciclo por tempo (a 120 bpm, 2 Hz); `1/8` a 120 bpm dá 4 Hz. Os compassos contam sempre **4 tempos**, mesmo num projeto em 6/8 |
| `Profund.` (knob) | Amplitude do LFO, multiplicada pela profundidade de cada destino | 0 a 100%, padrão 100% | Em 50% todos os destinos deste LFO andam metade |
| `Fase` (knob) | Onde no ciclo a onda começa | 0 a 100% do ciclo, lido em graus (`0°` a `360°`), padrão 0° | Duas faixas com o mesmo LFO defasadas de 180° balançam em oposição |
| `Bipolar` / `Unipolar` (chips) | `Bipolar`: a saída vai de −profundidade a +profundidade, em volta do valor base. `Unipolar`: de 0 a +profundidade, então o valor só se afasta da base para um lado | Padrão `Bipolar` | Unipolar com profundidade de destino positiva só **sobe** a partir da base; negativa, só desce |

O LFO **livre recomeça do começo do ciclo a cada play** (não no seek nem na volta do loop). O `Andamento` usa a posição da música em batidas, então cai na fase certa depois de um seek e segue o mapa de andamento, inclusive rampas. Com o transporte parado o LFO continua andando (livre pelo relógio, sincronizado pelo andamento do ponto em que está o cursor), e isso vale para as notas tocadas ao vivo.

### Cartão do seguidor de envelope

O seguidor mede o nível do som **da própria faixa** (o pico, não a média) e devolve um valor que sobe com o volume e desce quando o som cede. Onde ele mede: depois dos efeitos da faixa e antes do fader (mexer no fader não muda a leitura; no `Master`, depois dos efeitos do master e antes do fader dele). Numa faixa sem som ele fica em zero.

| Controle (rótulo exato) | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| `Ganho` (knob) | Multiplica o nível medido antes de virar modulação | 0 a 8, leitura `×2.00`, padrão ×2 | O nível é em amplitude linear (0 a 1), **não em dB**: um pico de −6 dBFS (0,5) com `Ganho` ×2 já enche a escala; um sinal fraco, de −30 dBFS (0,03), quase não mexe em nada. A saída é presa em 0 a 1 |
| `Ataque` (knob) | Quão rápido a leitura sobe quando o som fica mais forte | 0,5 a 500 ms, escala logarítmica, padrão 10 ms | É a constante de tempo (cerca de 63% do caminho), não o tempo até 100% |
| `Soltura` (knob) | Quão rápido a leitura desce quando o som cede | 5 ms a 3 s, escala logarítmica, padrão 120 ms | Soltura curta acompanha cada golpe; longa forma uma "barriga" suave |
| `Bipolar` / `Unipolar` (chips) | Igual ao LFO: `Unipolar` (padrão) sai de 0 a 1; `Bipolar` remapeia para −1 a +1 (silêncio = −1) | Padrão `Unipolar` | Para "abaixa quando o som é forte", deixe `Unipolar` e ponha profundidade **negativa** no destino |

Um seguidor sem destino não mede nada (o motor só entrega o nível à faixa se há um destino vivo). Ele só mexe em controles **da mesma faixa** dele (ver [Limites e pegadinhas](#limites-e-pegadinhas)).

### Cartão da macro

A macro é um valor fixo, que você mexe com a mão, que vários destinos seguem juntos, cada um com a sua profundidade.

| Controle (rótulo exato) | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| `Valor` (knob) | O valor da macro | 0 a 100%, padrão 0% | Com `Unipolar` a macro só tem efeito quando sobe de 0. **Uma macro nova em 0% não muda nada** |
| `Bipolar` / `Unipolar` (chips) | `Unipolar` (padrão): a saída vai de 0 a 1. `Bipolar`: de −1 a +1, com 50% no meio (saída 0) | Padrão `Unipolar` | Bipolar dá um único botão que abre um parâmetro e fecha o outro (profundidades de sinais opostos) |

A macro se move **só pelo knob do cartão**: não tem MIDI learn, não tem automação e não tem modulação.

### Destinos e profundidade

A tabela abaixo mostra como a porcentagem age em cada tipo de controle. A profundidade de um destino é uma fração do **curso inteiro do controle**, na escala em que o knob anda. O valor que se ouve é o valor base mais `profundidade × saída do modulador`, andado no curso e preso entre o mínimo e o máximo do controle (nunca passa das pontas). Vários destinos no mesmo controle somam no curso.

| Tipo de controle | Como o curso é medido | Exemplo (LFO bipolar a 100%) |
|---|---|---|
| Frequência e tempo (Hz, s: `Corte`, `Ataque`, ...) | Escala **logarítmica** (a mesma do knob): o curso é contado em oitavas, não em Hz. 100% percorre o curso todo; o meio do curso é a média geométrica | `Corte` de 20 Hz a 20 kHz, base 700 Hz, **±30%**: de 88 Hz a 5,6 kHz. Base 2400 Hz, **±40%** (o preset `Wobble no corte`): de 151 Hz a 20 kHz (o topo é preso em 20 kHz, então a onda fica "cortada" em cima) |
| dB, porcentagem, semitons, centésimos (`ct`) e demais controles lineares | Escala **linear**: a profundidade é essa fração da largura do knob | Knob de −100 a +100 ct, **±6%**: ±12 ct (o preset `Vibrato de afinação`). Knob de 0 a 100%, ±25%: ±25 pontos percentuais |
| `Volume` e nível de `Envio` | Curva do fader: ganho = 2 × posição³, com 0 dB em 79% do curso e +6 dB no topo (a mesma do [mixer](06-mixer.md)). A profundidade anda na **posição do fader** | Base em 0 dB: ±15% dá de −5,5 dB a +4,5 dB (o `Tremolo no volume`); ±25% de −9,9 dB a +6,0 dB (topo preso); ±50% de −25,9 dB a +6,0 dB. Com o fader mais baixo, a mesma % é **mais fundo em dB** |
| `Pan` | Linear, de −1 (esquerda) a +1 (direita) | Pan no centro, **±50%**: de todo à esquerda a todo à direita (o preset `Auto-pan`). ±25%: `E50` a `D50` |

Notas de leitura:

- A % é do **curso**, não do valor: 50% de profundidade num controle cujo valor base já está no meio do curso vai de uma ponta a outra.
- Em Hz, uma escala de 20 a 20 000 Hz tem cerca de 10 oitavas; cada 10% de profundidade vale cerca de 1 oitava.
- O valor base é o que o controle mostra. O knob **não anda** com a modulação (só o som muda); ver [O anel e o pontinho](#o-anel-e-o-pontinho).

### O menu `Modular…`

Ele é uma entrada do menu de contexto do controle (botão direito; toque longo nos knobs), logo abaixo de `Aprender MIDI` e de `Remover mapeamento (...)`. No fader e no pan do mixer o menu do botão direito traz `Aprender MIDI`, `Remover mapeamento (...)` (só se mapeado), `Modular…` e `Mapeamentos MIDI…`. O item só aparece se o controle se modula. No nível de `Envio` do mixer e no mini fader do cabeçalho da faixa não há `Modular…` (o botão direito do envio é o menu do envio); ligue-os pelo `Destino` do cartão.

Escolhido `Modular…`, abre o diálogo `Modular: <controle>` (por exemplo `Modular: Instrumento · Corte`):

| Item (rótulo exato) | O que faz | Dica |
|---|---|---|
| `Modulador N · <resumo>` (um por modulador que a faixa já tem; com marca de visto se ele já modula este controle) | Liga o controle a um modulador que já existe, com profundidade +25% | Se o modulador já modula o controle, nada muda. Cada modulador aceita até 4 destinos: escolher um que já tem 4 mostra, dentro do diálogo, `Cada modulador tem no máximo 4 destinos.` |
| `Novo LFO` | Cria um LFO com defaults e o liga ao controle (+25%) | |
| `Novo seguidor de envelope` | Idem, com um seguidor | |
| `Nova macro` | Idem, com uma macro (em 0%, sem efeito até você subir o `Valor`) | |
| Linha `A faixa já tem 4 moduladores: escolha um deles.` | Aparece com a faixa cheia; os três `Novo...` ficam desligados | |

Depois de ligar, a aba `Modulação` abre na faixa do controle (a faixa vira a selecionada), para acertar a profundidade. O ato inteiro é um passo no desfazer.

### O anel e o pontinho

| Sinal | Onde | O que diz |
|---|---|---|
| **Anel ciano** por fora do trilho do knob | Knobs do painel de instrumento e do painel de efeitos com modulação | O intervalo em que o valor real se move, em volta do valor base que o knob mostra. Cor `#5FD4E8`. É **estático**: mostra o alcance possível (soma dos destinos, na escala do controle, sem passar das pontas), não o valor ao vivo |
| **Pontinho ciano** de 6 px, no canto superior esquerdo | Qualquer controle com modulação que aceita MIDI learn: knobs, fader, pan, envio e mini fader | "Este controle tem modulação" (o pontinho âmbar do MIDI learn fica no canto oposto) |

Mexer no knob desloca o anel junto (ele acompanha o valor base). Com o knob seguindo uma automação (laranja), o anel fica mais apagado. Os controles desenhados à mão nos editores de efeito (nós do gráfico do EQ, curvas do `Multibanda`) não mostram o anel `(não confirmado)`.

### Presets

`Presets` cria um modulador **e** o destino de uma vez. Todos são LFO de senoide, bipolar, profundidade 100%, fase 0°.

![O menu `Presets` aberto: `Wobble no corte`, `Tremolo no volume`, `Auto-pan` e `Vibrato de afinação`, cada um com a linha de descrição.](../img/modulacao-presets.jpg)

*O menu `Presets`.*

| Preset (rótulo exato) | Descrição no menu | O que cria | Destino que procura | Quando recusa |
|---|---|---|---|---|
| `Wobble no corte` | `LFO sincronizado (1/8) movendo o corte do filtro` | LFO em `Andamento`, divisão `1/8` (a 120 bpm, 4 Hz) | `Instrumento · Corte` (sintetizador, wavetable), senão o `Corte` do **primeiro** efeito `Filtro` da cadeia; profundidade **+40%** | Faixa sem instrumento com `Corte` e sem `Filtro` na cadeia (bateria, sampler e FM sem `Filtro`; áudio; barramento) |
| `Tremolo no volume` | `LFO de 6 Hz movendo o volume da faixa` | LFO livre, 6 Hz | `Volume`, **+15%** | Nunca (todo canal tem volume) |
| `Auto-pan` | `LFO sincronizado (1/2) passeando o som entre os lados` | LFO em `Andamento`, divisão `1/2` (a 120 bpm, 1 Hz) | `Pan`, **+50%** (de um lado ao outro se o pan está no centro) | Nunca |
| `Vibrato de afinação` | `LFO de 5,5 Hz movendo a afinação em centésimos de semitom` | LFO livre, 5,5 Hz | O **primeiro** parâmetro do instrumento em `ct` e escala linear, **+6%** (±12 ct em −100 a +100) | Faixa sem instrumento e bateria |

Sobre o alvo do `Vibrato de afinação` (lido da tabela de parâmetros, não ouvido): no `Sampler` é a `Afinação` da faixa toda (vibrato de verdade). No `Sintetizador` é a `Desafinação` do `Oscilador 2` (só o segundo oscilador desafina e bate contra o primeiro, o que soa mais como um coro lento que como vibrato). No `FM` é o `Fino` do `Operador 1`, e no `Wavetable` a `Desafinação` do `Oscilador 1`. Para um vibrato da voz inteira no sintetizador, use o `Vibrato` do LFO do próprio instrumento ([04a](04a-sintetizador.md)).

Aplicar o mesmo preset duas vezes cria dois moduladores que **somam** no mesmo controle. O preset entra como um passo no desfazer.

## O que a modulação soma e o que ela não alcança

### Como ela se soma ao valor

- **Valor efetivo = base + modulação**, no curso do controle, preso entre as pontas. A base é o que o knob mostra: o valor fixo (o que você deixou) ou, com o transporte tocando e uma raia com pontos naquele controle, o valor da [automação](07-automacao.md) naquele instante.
- **Nada é gravado no controle.** Apagar o destino (ou o modulador) devolve o controle ao valor base; o documento continua com o valor que você deixou e a curva que você desenhou.
- **Parado**, o motor não aplica curva de automação, então a base é o valor fixo; a modulação continua andando por cima (o LFO e o seguidor valem para as notas que você toca ao vivo).
- **Um modulador por vez ou vários:** vários destinos no mesmo controle (do mesmo modulador ou de outros) somam.
- **Passo de 32 quadros.** A modulação anda a cada 32 quadros do motor (cerca de 0,7 ms a 48 kHz), numa grade fixa: o resultado não depende do tamanho do bloco do aparelho, e a exportação sai igual ao tempo real (o LFO livre começa do zero na exportação, como num play do começo do projeto).
- **Parâmetros de instrumento e de efeito** recebem o valor novo a cada passo em que a base ou a modulação muda; a `Bateria` aplica `Afinação`, `Decaimento` e `Timbre` só no próximo golpe (o mesmo limite da automação, ver [04b](04b-bateria.md)) `(dedução)`.

### Automação e gravação de automação

- Um controle pode ter raia de automação **e** modulação: a curva move a base e a modulação balança por cima.
- O que grava a [gravação de automação](07-automacao.md#gravar-automação) (`Escrever`, `Toque`, `Trava`) é o movimento da sua mão no controle, isto é, a base. A modulação não vira pontos, e a raia não a desenha `(lido do código; não confirmado em uso)`.
- Exportar e [congelar](08-exportacao.md#congelar-uma-faixa): a exportação leva a modulação inteira. Ao congelar, a modulação de `Volume`, `Pan` e envios vai junto para a faixa nova (como a automação desses); a de instrumento e de efeitos vira som no arquivo.

### MIDI learn

- Um controle mapeado no [MIDI learn](06f-midi-learn.md) e modulado responde às duas coisas: o controlador move a **base** (o knob mostra e guarda esse valor) e a modulação soma por cima. O menu do controle traz `Aprender MIDI` e `Modular…` lado a lado.
- O controle modulado leva o pontinho ciano além do âmbar. No modo `Aprender MIDI` os controles com modulação também têm o pontinho.
- Os knobs dos cartões da aba `Modulação` (inclusive o `Valor` da macro) **não** se mapeiam e não têm menu `Aprender MIDI`.

### O que a modulação não alcança

- **Opções e inteiros:** `Onda`, `Tipo` do filtro, `Algoritmo`, `Modo`, `Solo` e `Bypass` das bandas, `Vozes`, `Uníssono`, `Semitons` (o `Modular…` nem aparece; o `Destino` não os lista).
- **`Sidechain`** de compressor e gate (nem a automação o alcança), armar, mudo, solo e saída da faixa.
- **Outra faixa:** cada modulador só liga controles da faixa a que ele pertence (ou do `Master`, no master). Não dá para um LFO da faixa A mexer num controle da faixa B.
- **Os próprios moduladores:** não há modulação de modulador, e a macro só se mexe no painel.
- Andamento, ganho e fades de clipes, warp e todo botão ou menu que não seja um dos controles acima.

### O que é salvo

A modulação mora no documento do projeto, e por isso vai junto com o salvamento, a [sincronização](01b-nuvem-e-sincronizacao.md), o `.jopendaw` exportado e o desfazer: campos `modulation` (por faixa) e `master_modulation` (no documento), que só aparecem quando há ao menos um modulador (um projeto sem modulação sai igual ao de antes). Guardam-se o tipo, a forma, a taxa livre **e** a divisão, a profundidade, a fase, bipolar, ataque, soltura, o valor da macro e os destinos (controle e profundidade). Campos, faixas aceitas e compatibilidade em [dev/10 App Flutter, Modulação](../dev/10-app-flutter.md#modulação-fase-16-b).

- **Duplicar a faixa** leva a modulação (ids novos; os destinos em efeitos passam para os efeitos da cópia). O MIDI learn, ao contrário, não é copiado.
- **Apagar** um efeito ou um envio (ou desfazer algo que o criou) tira os destinos que apontavam para o que sumiu; o modulador fica, sem esse destino. `Ctrl+Z` traz de volta.
- **Importar um `.jopendaw`** refaz os ids de efeitos e envios e reaponta os destinos; o que apontava para algo que não existe mais é descartado.
- **Presets do usuário** guardam só os valores dos knobs; a modulação não entra neles `(lido do código: os presets não a citam)`.
- Um app **anterior à fase 16** abre o projeto sem enxergar a modulação e, se salvar, a **perde** `(dedução; não testado)`.

## Passo a passo

### Wobble no filtro de um baixo (sincronizado ao andamento)

1. Numa faixa de sintetizador com o preset `Reese` (`Corte` em 700 Hz), com um clipe de notas, abra a aba `Modulação` (o assunto mostra `<faixa> · sem moduladores`).
2. Toque em `Presets` e escolha `Wobble no corte`. Nasce o cartão `1 · LFO senoide · 1/8` com o destino `Instrumento · Corte` em `+40%`.
3. Com o projeto tocando, arraste a barra do destino até `+30%`: o corte vai de 88 Hz a 5,6 kHz (em 40% chegaria a 44 Hz, quase fechado).
4. Para outro ritmo, troque a lista de divisões: `1/4` (mais lento), `1/8 pontilhada` ou `1/16` (rápido).
5. Suba a `Ressonância` do instrumento (por exemplo de 22% a 45%) para o "uau" ficar mais nítido. O knob `Corte` segue mostrando 700 Hz e ganha o anel ciano.

### Tremolo em um pad

1. Selecione a faixa do pad e abra a aba `Modulação`.
2. `Presets` e `Tremolo no volume`: LFO livre, senoide, 6 Hz, destino `Volume` em `+15%` (de −5,5 dB a +4,5 dB com o fader em 0 dB).
3. Para um tremolo mais lento e suave, arraste o knob `Taxa` para 3,5 Hz e a barra do destino para `+8%`.
4. Para o tremolo só descer a partir do volume que você acertou (sem passar dele), troque o LFO para `Unipolar` e ponha o destino em `-15%`.
5. Se o pad passa dos 0 dB quando o LFO sobe, abaixe o fader antes: o topo do curso é +6 dB e o valor é preso ali.

### Auto-pan em um sintetizador

1. Numa faixa de instrumento com pan no centro, abra a aba `Modulação` e escolha `Presets`, `Auto-pan`: LFO em `Andamento`, `1/2`, destino `Pan` em `+50%`.
2. Toque: o som vai de todo à esquerda a todo à direita em 2 tempos (a 120 bpm, uma volta por segundo).
3. Para um passeio mais discreto, baixe a profundidade do destino para `+20%` (de `E20` a `D20`).
4. Para o passeio "quadrado" (salta de um lado ao outro), troque a forma para `Quadrada`. A troca é alisada em cerca de 1 ms, sem estalo.
5. Duplique a faixa (o pan modulado vai junto) e ponha `Fase` em 50% (180°) na cópia para as duas andarem em oposição.

### Vibrato de afinação em um sampler

1. Numa faixa `Sampler` com um som sustentado, abra a aba `Modulação`, `Presets` e `Vibrato de afinação`.
2. O destino é `Instrumento · Afinação`, em `+6%` (±12 ct), a 5,5 Hz.
3. Para um vibrato que **entra devagar**, não há como atrasar o LFO; use a roda de modulação de MIDI ([04](04-painel-de-instrumento.md#rodas-de-pitch-bend-e-de-modulação)) ou o `Vibrato da roda` do sampler.
4. Num sintetizador, FM ou wavetable, o preset mexe só num oscilador ou operador (ver [Presets](#presets)); prefira o `Vibrato` do LFO do instrumento, ou ligue você mesmo um LFO ao parâmetro que quiser com `Modular…`.

### Seguidor de envelope no volume: bombeio falso

O seguidor lê a **própria faixa**, então não escuta o bumbo de outra faixa: não dá para o pad ser "abaixado pelo bumbo" só com um seguidor no pad (para isso existe o `Sidechain` do compressor, [06d](06d-efeitos-referencia.md#o-sidechain-o-que-ele-exige)). O que dá para fazer é ligar o seguidor a um barramento que recebe o bumbo junto:

1. Crie um barramento e mande a faixa do bumbo e a do pad para ele (saída da faixa, [06 Mixer](06-mixer.md#saída-e-nome)).
2. Selecione o barramento, abra a aba `Modulação`, `Adicionar` e `Seguidor de envelope`.
3. Ajuste: `Ganho` ×2 (o padrão), `Ataque` 5 ms, `Soltura` 200 ms, `Unipolar`.
4. No cartão, `Destino` e `Volume`; ponha a profundidade em `-30%`. A cada golpe do bumbo (o pico mais alto do grupo) o volume do barramento cai, chegando a cerca de −12 dB com a leitura cheia, e volta na soltura. O bumbo também é abaixado (depois do primeiro ataque), diferente de um sidechain verdadeiro.
5. Ouça e ajuste a soltura ao andamento; se pesar demais, suba o `Ataque` para deixar mais do golpe passar. `(não confirmado ao ouvido)`

Receita completa, com a variação de LFO no andamento, em [Modulação na prática](../guias/modulacao-na-pratica.md).

## Combina com

- [06c Painel de efeitos](06c-painel-de-efeitos.md) e [06d Referência dos efeitos](06d-efeitos-referencia.md): quase todo parâmetro de efeito é destino (`Filtro · Corte`, `Reverb · Mistura`, ...). O `Tremolo` já é um LFO de volume dentro de um efeito ([06d Tremolo](06d-efeitos-referencia.md#10-tremolo)); a modulação serve para mover os outros parâmetros e para ter mais de um movimento no mesmo controle.
- [04 Painel de instrumento](04-painel-de-instrumento.md), [04a Sintetizador](04a-sintetizador.md), [04d FM](04d-fm.md) e [04e Wavetable](04e-wavetable.md): os knobs de timbre são destinos e mostram o anel ciano; o LFO interno do sintetizador e o da wavetable têm taxa em Hz e não sincronizam com o andamento ([04a](04a-sintetizador.md), [04e](04e-wavetable.md)); o LFO desta aba pode sincronizar.
- [06 Mixer](06-mixer.md): o fader e o pan aceitam `Modular…` com o botão direito do mouse; os envios entram pelo `Destino`.
- [07 Automação](07-automacao.md): a curva move a base e a modulação soma por cima; uma raia não mostra a modulação.
- [06f MIDI learn](06f-midi-learn.md): o controlador move a base; a modulação soma por cima.
- [08 Exportação](08-exportacao.md): a exportação e o congelamento levam a modulação.
- [Guia: modulação na prática](../guias/modulacao-na-pratica.md): wobble de baixo, tremolo de pad, auto-pan e bombeio falso, com valores.
- Técnico: [Motor, modulação](../dev/01-motor.md#modulação-enginesrcmodulationrs-fase-16-b) e [App Flutter, modulação](../dev/10-app-flutter.md#modulação-fase-16-b).

## Limites e pegadinhas

- **Quatro moduladores por faixa, quatro destinos por modulador.** No `Master` também. Mais que isso o app recusa (o JSON de um arquivo de fora que passe do limite é cortado ao abrir).
- **O seguidor só ouve a própria faixa e só mexe nela.** Não há entrada externa nem escolha de faixa-chave. Para "abaixar por outra faixa", use o `Sidechain` do compressor.
- **O knob mostra a base, não o valor ao vivo.** O anel é o alcance possível, não o ponteiro. Para ver o movimento, ouça (ou olhe o medidor da faixa).
- **Editar a modulação com o projeto tocando pode reiniciar os LFOs livres.** Cada edição reenvia toda a modulação ao motor, e um modulador reenviado começa do zero: o LFO `Livre` recomeça o ciclo e o seguidor esquece o nível (o LFO em `Andamento` não sente, porque a fase vem da posição da música). Ao arrastar o `Profund.` de um LFO livre ouvindo, o movimento pode "engasgar" a cada passo do arraste `(lido do código; não confirmado ao ouvido)`.
- **Base perto da ponta do curso "corta" a onda.** Com `Corte` em 2400 Hz e o preset `Wobble no corte` (+40%), a metade de cima passa de 20 kHz e fica presa: o filtro passa boa parte do ciclo aberto. Baixe a profundidade ou abaixe o `Corte` base. Vale para todo controle: a onda é presa entre o mínimo e o máximo.
- **A profundidade é fração do curso, em Hz é em oitavas.** 10% no `Corte` (20 Hz a 20 kHz) é cerca de uma oitava, não 10% de Hz.
- **Volume: a mesma % soa mais forte com o fader baixo.** A profundidade anda na posição do fader (curva cúbica); com o fader em −12 dB o mesmo `+15%` varia mais em dB.
- **Macro nova em 0% não faz nada** (unipolar), e a macro não tem MIDI learn nem automação: hoje é um botão de mouse.
- **Presets recusam faixas sem o controle.** `Wobble no corte` numa faixa de bateria, `Vibrato de afinação` numa faixa de áudio: `<preset>: esta faixa não tem o controle que o preset move.`
- **Aplicar o mesmo preset de novo soma.** Dois `Tremolo no volume` na mesma faixa somam as duas ondas no volume.
- **Fader, pan e envio no celular.** Sem botão direito, o `Modular…` deles não abre por toque; use o `Destino` do cartão.
- **A dica dos knobs não cita `Modular…`.** O tooltip continua dizendo `menu (digitar o valor, Aprender MIDI)`; o menu tem o item `Modular…` mesmo assim.
- **O LFO sincronizado conta compasso de 4 tempos** nas divisões de compasso, qualquer que seja a fórmula de compasso do projeto.
- **A automação de um alvo modulado continua parando quando o transporte pára.** Parado vale o valor fixo (mais a modulação).
- **Web e Android** usam o mesmo motor. O `engine.wasm` e os três `.so` integrados já têm as chamadas de modulação; um `engine.wasm` ou APK **anterior** à fase 16 ignora as chamadas (na web) ou as conta como desconhecidas (no Android) e simplesmente não modula.

## Atalhos

| Tecla / gesto | Ação |
|---|---|
| Botão direito num knob (toque longo no celular) | Menu com `Modular…` |
| Botão direito do mouse no fader ou no pan do mixer | Menu com `Modular…` |
| Duplo clique num knob do cartão | Volta ao padrão do knob |
| `Shift` ao arrastar um knob | Ajuste fino |
| `Esc` | Fecha o painel de baixo |
| `Ctrl+Z` / `Ctrl+Shift+Z` (ou `Ctrl+Y`; padrões, os atalhos são personalizáveis) | Desfaz e refaz cada passo (adicionar, apagar, preset, ligar, arraste) |
