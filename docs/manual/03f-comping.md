# Comping por trecho

> Monte uma interpretação boa a partir de várias tomadas gravadas em loop: em vez de escolher uma tomada para o clipe inteiro, você escolhe, trecho a trecho, qual tomada soa, arrastando numa raia por tomada; o app emenda os trechos com um crossfade de 20 ms quando dá.

Este capítulo é a continuação de [Gravação, tomadas em loop](03c-gravacao.md). Tudo o que está aqui foi lido do código (`app/lib/daw/comp.dart`, `comp_ui.dart`, `controller.dart`, `timeline.dart`, `keymap.dart`, fase 26 A, commit `ab57a40`) e dos testes automáticos (`app/test/fase26_test.dart`). `(testado só por testes automáticos: nada foi visto nem ouvido rodando no navegador ou no Android; as cores, as opacidades e os tamanhos vêm do código)`

## Onde fica

1. **De onde vêm as tomadas.** Só de uma **gravação em loop** numa faixa de áudio: loop marcado e ligado, faixa armada, `R`, várias voltas. Nasce um clipe cobrindo o loop, com o selo `N tomadas`, e cada passada do loop é uma tomada (quais passadas contam e qual fica ativa: [Gravação](03c-gravacao.md), seção `Gravar várias tomadas em loop e escolher`, e os [Limites](03c-gravacao.md#limites-e-pegadinhas) dela). Não existe outro jeito de criar tomadas: importar áudios ou "empilhar" clipes **não** gera tomadas, e o comp não abre em clipe sem a lista de tomadas.
2. **Abrir o comp.** Três caminhos, todos no clipe de tomadas (o que tem o selo `N tomadas`):
   - botão direito no clipe (toque longo no celular) › **`Comp por trecho`**, logo abaixo de `Tomadas`;
   - com o clipe selecionado, a ação **`Comp por trecho (tomadas)`** (id `edit.comp`, categoria `Edição`, contexto `Arranjo`), que liga e desliga o modo. Ela **não tem tecla padrão**: atribua uma em `Personalizar` ([09 Configurações, Personalizar os atalhos](09-configuracoes-atalhos-android.md#personalizar-os-atalhos));
   - com o comp aberto, o mesmo item do menu vira **`Fechar o comp`**.
3. **O que aparece.** Logo abaixo da faixa do clipe nascem **uma raia por tomada**, cada uma com **30 px** de altura (fixos: não seguem `P`/`M`/`G` de altura da faixa), entre a faixa e as raias de automação dela. A faixa fica selecionada. Só uma faixa tem raias de comp de cada vez.

O modo comp é **estado de tela**: não entra no projeto, não entra no histórico, não sincroniza. Abrir e fechar não gastam passo do desfazer. Os clipes do comp continuam no arranjo quando você o fecha.

## Controles

### Menu do clipe e ação

| Controle (rótulo exato) | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| `Comp por trecho` (menu do clipe; só em clipe com tomadas) | Abre o modo comp neste clipe. Recusa o que não serve (ver [Recusas](#recusas-com-a-mensagem-exata)) | | Com o comp de **qualquer** clipe aberto, o item muda de texto e só fecha (ver [Limites](#limites-e-pegadinhas)) |
| `Fechar o comp` (o mesmo item, com o modo ligado) | Some com as raias. Não mexe em clipe nenhum | | Também existe o `X` na primeira raia |
| `Comp por trecho (tomadas)` (ação `edit.comp`, janela `?` e `Personalizar`) | Liga ou desliga o modo usando o clipe **selecionado** (sem seleção: `Selecione um clipe gravado em loop (com tomadas) para fazer o comp.`). Texto de ajuda: `Abre ou fecha o comp do clipe gravado em loop: escolha, trecho a trecho, a tomada que soa` | Sem tecla padrão | |

### O cabeçalho de cada raia (coluna da esquerda)

Um cabeçalho por tomada, na altura de 30 px, alinhado com a raia.

| Controle (rótulo exato) | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| Traço colorido de 4 px na borda esquerda | Só identifica: é a cor da faixa, translúcida | | |
| `Tomada 1`, `Tomada 2`… (no celular e nas larguras estreitas, `T1`, `T2`…) | **Tocar usa a tomada no comp inteiro**: o comp todo passa a tocar essa tomada, e as emendas somem (vira um clipe só). Tooltip `Usar a tomada N no comp inteiro` | Uma tomada por linha, na ordem das voltas da gravação | Vale do começo ao fim do que o comp cobre, não do que o loop tinha |
| Visto (`✓`) à esquerda do nome | Aparece na tomada que soa em **todos** os trechos do comp | | Com trechos de tomadas diferentes, nenhuma leva visto |
| Nome em cinza apagado e tooltip `Esta tomada não está neste aparelho` | A tomada não está neste aparelho (ainda não baixou do servidor, ou não veio): tocar no nome não faz nada | | Ver [Recusas](#recusas-com-a-mensagem-exata) |
| Ícone de camadas riscadas (só na **primeira** raia; tooltip `Achatar: manter os clipes e descartar as tomadas`) | Achata o comp ([abaixo](#achatar)) | | |
| Ícone `X` (só na **primeira** raia; tooltip `Fechar o comp`) | Fecha o modo | | |

### A raia de cada tomada (área do arranjo)

A raia de cada tomada mostra a **onda daquela tomada** ao longo de todo o trecho que o comp cobre (do começo do primeiro pedaço ao fim do último), na cor da faixa. Onde essa tomada é a que **soa**, o fundo e a onda ficam acesos (fundo a 22% e onda a 95% de opacidade); onde é outra que soa, ficam apagados (fundo a 5% e onda a 35%). Um fio branco fino (1 px, 35% de opacidade) marca o começo de cada trecho: é a **emenda**. Tomada ausente do aparelho: a raia fica cinza e sem onda.

| Gesto na raia | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| **Arrastar** na horizontal (para a direita ou para a esquerda) | Escolhe **aquela tomada** no trecho arrastado. Enquanto arrasta, um retângulo na cor de destaque (verde-água) mostra o trecho; ao soltar, o comp é refeito | O começo e o fim **encaixam na grade** do transporte (`Livre`, `Compasso`, `1/4`, `1/8`, `1/16`); o trecho começa onde o dedo ou o mouse **tocou**, não onde o arraste foi reconhecido | O `Alt` **não** desliga o encaixe aqui (só a grade `Livre` o desliga) `(não confirmado em uso: o código desta raia não consulta o Alt)` |
| **Tocar** (sem arrastar) | Usa aquela tomada no **trecho entre emendas** sob o toque (o pedaço inteiro, de emenda a emenda) | Sem encaixe: a borda é a da emenda. Tocar fora de qualquer trecho não faz nada | Útil para trocar uma frase já separada sem arrastar de novo |
| Arrastar ou tocar sobre o que **já** é aquela tomada | Nada: não há passo do desfazer | | |
| Arrastar além do começo ou do fim do comp | O trecho é **cortado** nas bordas do comp (o comp não cresce) | | |

O trecho de menos de **1 ms** não existe: uma borda a menos de 1 ms de uma emenda existente vira a própria emenda, sem deixar um pedaço minúsculo.

## O que o comp produz

Nada de novo no projeto: o resultado são **clipes de áudio comuns**, um por trecho, cada um apontando para a tomada escolhida e ainda carregando a **lista completa de tomadas** (por isso cada pedaço mostra o selo `N tomadas` e o item `Tomadas`). Não há campo novo no arquivo do projeto, na sincronização nem no `.jopendaw`. A exportação e o motor tratam cada pedaço como qualquer clipe (mover, cortar, fades, ganho e o resto continuam valendo nele).

**Como o app sabe quais clipes formam o comp.** Ele não guarda nada: a cada momento o "grupo" é **derivado**: os clipes da mesma faixa que têm **a mesma lista de tomadas**, o **mesmo alinhamento** com o áudio (o instante em que o segundo 0 de cada tomada cairia, com tolerância de 0,1 ms) e nenhum warp, reverso, transposição ou loop. Consequências:

- **Dividir** (`S`) um pedaço mantém os dois lados no grupo.
- **Duplicar** não entra no grupo (a cópia vai para depois do clipe, em outro alinhamento).
- **Mover** um pedaço o tira do grupo (muda o alinhamento); ligar warp, reverso, transposição ou loop nele também.
- Fechar e reabrir o projeto, desfazer ou reabrir o comp de qualquer pedaço recuperam o mesmo grupo.

## Emendas e crossfade

Quando dois trechos vizinhos **de tomadas diferentes** se encostam, o app tenta uma emenda com **crossfade automático** de **20 ms** (`potência constante`, o mesmo crossfade automático dos clipes sobrepostos, que o [capítulo de áudio](03-audio-e-clipes.md#fades-e-crossfade) descreve): cada lado avança **10 ms** sobre o outro, centrado no ponto da emenda, e o clipe ganha fade automático de 20 ms daquele lado. A linha da raia fica no ponto que **você** marcou, não nos 10 ms de folga.

Só há crossfade se **todas** estas condições forem verdadeiras; senão a emenda fica em **corte seco** (sem erro nem aviso):

| Condição | Quando falha |
|---|---|
| A tomada que sai tem **pelo menos 10 ms de áudio depois** do ponto da emenda | Emenda a menos de 10 ms do fim do áudio da tomada |
| A tomada que entra tem **pelo menos 10 ms de áudio antes** do ponto | Emenda a menos de 10 ms do começo do áudio (por exemplo, exatamente no começo do loop) |
| O áudio dos dois lados é conhecido no projeto | O projeto não tem a duração daquele áudio |
| **Sem fade do usuário** naquela borda (saída do que sai, entrada do que entra) | Você já pôs um fade à mão numa das bordas da emenda |
| O crossfade cabe nos trechos: ele nunca passa de **metade do menor dos dois** (um trecho de 20 ms leva um crossfade de 10 ms) e precisa de pelo menos 0,1 ms | Trecho minúsculo (o mínimo de um trecho é 1 ms, então na prática só o limite de metade age) |

Trechos vizinhos da **mesma** tomada não têm emenda: quando um deles foi mexido pela escolha, eles se juntam num clipe só; uma divisão sua (`S`) que a escolha não tocou fica como está.

**Fade do usuário nas pontas.** Os fades que você tinha na **primeira e na última borda** do comp continuam como estavam; o fade que um pedaço tinha numa borda que foi cortada some (a borda nova é emenda).

**Para um fade seu numa emenda.** Selecione o pedaço e use `Fade de entrada…` ou `Fade de saída…` no menu do clipe ([03](03-audio-e-clipes.md#tamanho-do-fade-por-campo)): o fade deixa de ser automático e o comp respeita o que você pôs, deixando **aquela emenda como está** `(lido do código)`. Para voltar ao crossfade automático de 20 ms numa emenda que você mexeu, o caminho seguro é desfazer (`Ctrl+Z`) até antes do ajuste do fade; zerar o fade à mão e refazer a escolha pode não bastar, porque a sobreposição de 20 ms que o crossfade deixou nas bordas fica como geometria do clipe `(lido do código; não confirmado em uso)`.

## Achatar

O ícone de camadas riscadas (primeira raia), tooltip `Achatar: manter os clipes e descartar as tomadas`, **fecha o modo** e **tira a lista de tomadas de todos os clipes do comp**. Os clipes ficam exatamente como estão (mesmas emendas, mesmos crossfades), mas agora são clipes comuns: somem o selo `N tomadas` e o item `Tomadas`, e o comp **não pode mais ser refeito** (o app não sabe mais quais eram as outras tomadas). É **um passo** do desfazer, `Comp: achatar`; desfazer devolve a lista de tomadas, mas o modo comp continua **fechado**: abra de novo pelo menu.

Quando achatar: quando a interpretação está decidida e você quer seguir com a mixagem sem as raias e sem o selo em cada pedaço.

`Achatar` **não apaga os áudios** das tomadas que não entraram: eles continuam na lista de áudios do projeto (e na cota da conta) até você limpá-los `(lido do código: só a lista de tomadas dos clipes é esvaziada)`. Para liberar cota, use `Limpar áudios sem uso` na tela `Conta` quando nenhum projeto citar mais o áudio.

## Fechar

O `X` da primeira raia (ou `Fechar o comp` no menu, ou a ação `edit.comp` de novo) apenas esconde as raias. Os clipes, a lista de tomadas e as emendas ficam: reabrir o comp em qualquer pedaço mostra tudo de volta.

## Desfazer

| Passo no histórico | Quando aparece |
|---|---|
| `Comp: escolher trecho` | Cada arraste ou toque que muda alguma coisa, e cada toque no nome da tomada que muda alguma coisa. Um passo só, por maior que seja o trecho e quantos clipes nasçam |
| `Comp: achatar` | O ícone de achatar |

`Ctrl+Z` desfaz a escolha: o documento volta **igual byte a byte** ao de antes, e o modo comp segue ligado (as raias voltam a mostrar os trechos do estado anterior). Refazer volta a escolha. Ver [02d Histórico e versões](02d-historico-e-versoes.md#os-nomes-dos-passos).

## Recusas com a mensagem exata

As recusas aparecem como o aviso de erro da tela do projeto (abaixo da barra, com `X` para fechar).

| Quando | Mensagem |
|---|---|
| Abrir o comp sem clipe selecionado (a ação `edit.comp`) ou com um clipe que não existe mais | `Selecione um clipe gravado em loop (com tomadas) para fazer o comp.` |
| Abrir o comp num clipe com menos de duas tomadas | `Este clipe não tem tomadas: o comp é para a gravação em loop, que guarda uma tomada por volta.` |
| Abrir o comp num clipe com **warp, reverso, transposição ou loop** (desligue antes em `Warp e altura…` e no item de loop do menu) | `O comp não funciona num clipe com warp, reverso, transposição ou loop: desligue isso primeiro.` |
| Escolher (arrastando ou tocando numa raia) uma tomada que **não está neste aparelho** | `A tomada N não está neste aparelho: não dá para escolhê-la.` (com o número da tomada, a partir de 1) |

A mesma mensagem do warp vale se a tomada ativa do clipe não estiver na lista de tomadas dele, o que o app não cria sozinho `(lido do código: a condição é a mesma)`. Nada disso gasta passo do desfazer. A recusa por tomada ausente some quando o áudio chega ao aparelho (o app tenta buscar no servidor ao abrir o projeto: [Nuvem e sincronização](01b-nuvem-e-sincronizacao.md)).

## Passo a passo

Os números supõem **120 BPM em 4/4** (um compasso = 2 s, uma batida = 0,5 s) e um loop de 4 compassos, do `5.1.1` ao `9.1.1` (8 s), gravado em **3 tomadas**; o clipe nasce com a tomada 3 ativa (a última volta completa).

**Montar um vocal a partir de 3 tomadas**
1. Selecione o clipe da voz (selo `3 tomadas`), botão direito › `Comp por trecho`. Nascem três raias, `Tomada 1` a `Tomada 3`, e a `Tomada 3` leva o visto.
2. Mude a grade do transporte para `Compasso` (`Grade de encaixe`). Com ela, cada arraste pega compassos inteiros.
3. Ouça cada tomada com o loop ligado (`Espaço`). Para ouvir uma tomada inteira, toque no nome dela (`Tomada N`): o comp todo passa a usá-la (um passo do desfazer; `Ctrl+Z` devolve). O `✓` mostra qual tomada soa no comp todo.
4. Escolha o verso 1 (compassos 5 e 6): arraste na raia `Tomada 2`, do `5.1.1` ao `7.1.1`. A raia acende nesse trecho, nasce a emenda em `7.1.1` (12 s do projeto), com o crossfade de 20 ms.
5. O verso 2 (compasso 7): arraste na raia `Tomada 1`, do `7.1.1` ao `8.1.1`. A emenda em `8.1.1` (14 s).
6. O compasso 8 fica com a tomada 3. Toque para ouvir a sequência inteira; cada passo é desfazível com `Ctrl+Z`.
7. Terminou: `Achatar` (se quer seguir sem as raias) ou `Fechar`.

**Trocar uma palavra de uma tomada por outra**
1. Com o comp aberto (vocal já montado como acima), a palavra ruim está no compasso 6, de 10,25 s a 10,75 s do projeto (batidas 20,5 a 21,5), e você a cantou melhor na tomada 1. Ajuste a grade para `1/8` (meia batida, 0,25 s a 120 BPM).
2. Na raia `Tomada 1`, arraste de **um pouco antes** até **um pouco depois** da palavra: das batidas 20 a 22 (10 s a 11 s), o que dá 0,25 s de folga de cada lado. Escolha bordas em silêncio ou numa respiração, para a emenda não cair no meio de uma vogal.
3. Se a emenda ficou audível, desfaça (`Ctrl+Z`) e arraste de novo com outras bordas, ou troque a grade para `1/16` ou `Livre` para colocar a borda em cima da respiração.
4. Toque de novo a região com o loop para aprovar, e feche o comp.

**Conferir as emendas**
1. Aproxime o zoom (`+`) até ver as emendas como fios brancos finos nas raias; cada fio é o **começo** de um trecho.
2. Selecione um dos pedaços na faixa: o clipe tem fade de entrada e/ou de saída de **20 ms** nas emendas que ganharam crossfade. Abra `Fade de entrada…` (ou `Fade de saída…`) para ler o valor (o diálogo mostra em `ms` ou `batidas`; só olhar, e fechar sem alterar, porque mexer à mão tira o fade do automático).
3. Ouça com o loop curto (1 compasso) em volta de cada emenda e compare com o mesmo trecho numa tomada inteira.
4. Emenda sem fade = corte seco (ver a [tabela acima](#emendas-e-crossfade)): se estalar, ponha um fade curto à mão ou afaste a emenda para dentro do áudio, como no [guia de fades](../guias/fades-e-crossfades.md).

**Achatar e seguir com a mixagem**
1. Com as escolhas feitas, toque o comp todo uma vez e confirme que não há emenda estalando.
2. Clique no ícone de achatar (primeira raia, tooltip `Achatar: manter os clipes e descartar as tomadas`). As raias somem e o selo `N tomadas` também.
3. Siga para o [mixer](06-mixer.md): volume, pan, efeitos. Os pedaços são clipes comuns.
4. Se ainda quiser rever uma tomada, `Ctrl+Z` logo em seguida (`Comp: achatar`) devolve a lista, e você reabre o comp.

**Pegadinhas de quem acabou de começar**
- Tocar num cabeçalho (`Tomada 2`) **substitui tudo** o que você montou por aquela tomada; `Ctrl+Z` desfaz.
- Arrastar de um lado ao outro numa raia depois de montar cobre as emendas que estavam no meio.
- Tocar numa raia troca o **trecho inteiro** entre duas emendas, não só um pedacinho.

## Combina com

- [03c Gravação](03c-gravacao.md): de onde vêm as tomadas (loop, tomada ativa, selo `N tomadas`, `Tomadas`) e o ciclo de gravar e regravar.
- [02b Timeline e clipes](02b-timeline-e-clipes.md#menu-do-clipe-de-áudio): o menu do clipe onde o comp abre, e a grade de encaixe.
- [03 Áudio e clipes, Fades e crossfade](03-audio-e-clipes.md#fades-e-crossfade): o crossfade automático (curva `Potência constante`) que as emendas usam.
- [02d Histórico e versões](02d-historico-e-versoes.md): os passos `Comp: escolher trecho` e `Comp: achatar`.
- [09 Configurações e atalhos](09-configuracoes-atalhos-android.md): a ação `edit.comp`, sem tecla padrão.
- Guias: [Vocal perfeito com comping](../guias/vocal-perfeito-com-comping.md) (vocal de 3 tomadas, solo de guitarra por compasso e conserto de uma palavra), [Fades e crossfades na prática](../guias/fades-e-crossfades.md) e [Gravar uma banda e mixar](../guias/gravar-uma-banda-e-mixar.md#6-voz-monitor-e-tomadas-em-loop).

## Limites e pegadinhas

- **Só gravação em loop.** Sem tomadas não há comp. Nada de empilhar clipes importados como tomadas.
- **Só clipe liso.** Warp, reverso, transposição e loop no clipe impedem o comp (mensagem na tabela de recusas); um pedaço que ganhe um desses sai do grupo e deixa de aparecer nas raias.
- **O comp não cresce.** Só se escolhe dentro do que o comp já cobre; não dá para estender além das bordas.
- **Pedaço movido deixa buraco.** Mover um pedaço o tira do grupo (mudou o alinhamento): as raias desenham só o que ficou no grupo, então o buraco não aparece, e uma escolha que atravessa o buraco o preenche `(lido do código; não visto rodando)`.
- **O menu do clipe fecha o comp aberto.** O item se chama `Fechar o comp` sempre que **algum** comp está aberto, mesmo quando você clica num clipe de outra gravação; para abrir o de outro clipe, feche e abra de novo.
- **Escolha nova herda as propriedades do primeiro clipe.** Um trecho **novo** (que não vem do corte de um pedaço que já existia) nasce como cópia do **primeiro** clipe do comp: o ganho, o mudo e a fase invertida dele valem no trecho novo, não os do pedaço que soava ali `(lido do código; não visto rodando)`. Se você ajustou `Ganho do clipe…` em pedaços separados, confira o resultado depois de escolher trechos.
- **`Tomadas` num pedaço troca só o pedaço.** O item `Tomadas` do menu de um pedaço troca o áudio dele sem refazer emendas nem juntar vizinhos; pelas raias as emendas são refeitas `(lido do código)`.
- **Se os clipes somem, as raias somem.** Apagar os pedaços esconde as raias; `Ctrl+Z` os traz de volta e as raias voltam junto.
- **Com o transporte tocando,** a escolha vai ao motor na hora e o que você ouve já é o novo comp; o render offline usa as mesmas chamadas `(testado só por testes automáticos)`.
- **Achatar não libera áudio** (veja a seção Achatar).
- **Tomada ausente.** Um pedaço cuja tomada não está neste aparelho não toca, como qualquer áudio ausente; o app tenta buscar no servidor ao abrir o projeto.

## Atalhos

| Tecla | Ação |
|---|---|
| Sem tecla padrão | `Comp por trecho (tomadas)` (`edit.comp`): liga e desliga o comp do clipe selecionado. Atribua em `Personalizar` |
| `S` | `Cortar no cursor`: dividir um pedaço mantém o grupo |
| `Ctrl+Z` / `Ctrl+Shift+Z` | Desfazer e refazer cada escolha (`Comp: escolher trecho`) e o `Comp: achatar` |
| `Espaço`, `L` | Tocar e ligar o loop para ouvir as emendas |
