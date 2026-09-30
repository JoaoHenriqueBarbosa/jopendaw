# Vocal perfeito com comping

> Montar uma interpretação só a partir de várias tomadas gravadas em loop, pegando a melhor de cada trecho, sem regravar nada: um vocal de 3 tomadas com emendas nas frases, um solo de guitarra escolhido compasso a compasso e o conserto de uma única palavra; cerca de 15 minutos por cenário depois de gravar.

Tudo abaixo supõe **120 BPM em 4/4** (um compasso = 2 s, uma batida = 0,5 s) e uma faixa de áudio já gravada em loop com várias tomadas ([Gravar uma banda e mixar, passos 6 e 7](gravar-uma-banda-e-mixar.md#6-voz-monitor-e-tomadas-em-loop)). Os tempos são contas de andamento, não medidas de uso; as contas dos clipes novos vêm do algoritmo do código (`app/lib/daw/controller.dart`, `comp.dart`) e de testes automáticos: **nada foi visto nem ouvido rodando** `(testado só por testes automáticos)`. O que soa bem, e em que ponto, é decisão de ouvido.

## Ingredientes

| Recurso | Para quê aqui | Capítulo |
|---|---|---|
| Gravação em loop (`Loop (L)`, faixa armada, `R`) e o selo `N tomadas` | Gera as tomadas: uma por passada do loop | [03c Gravação](../manual/03c-gravacao.md) |
| Menu do clipe › `Comp por trecho` | Abre uma raia de 30 px por tomada sob a faixa | [03f Comping por trecho](../manual/03f-comping.md) |
| Arrastar numa raia | Escolhe aquela tomada no trecho, com encaixe na grade | [03f, as raias](../manual/03f-comping.md#a-raia-de-cada-tomada-área-do-arranjo) |
| Tocar numa raia / tocar no nome (`Tomada N`) | Troca o trecho entre emendas / usa a tomada no comp todo | [03f](../manual/03f-comping.md#o-cabeçalho-de-cada-raia-coluna-da-esquerda) |
| `Grade de encaixe` (`Livre`, `Compasso`, `1/4`, `1/8`, `1/16`) | Decide onde as emendas caem | [02 Transporte](../manual/02-transporte.md) |
| Crossfade automático de 20 ms | Emenda entre tomadas sem estalo | [03f, emendas](../manual/03f-comping.md#emendas-e-crossfade), [Fades e crossfades na prática](fades-e-crossfades.md) |
| `Achatar` | Fecha o comp e segue com os clipes comuns | [03f, Achatar](../manual/03f-comping.md#achatar) |
| `Ctrl+Z` e os passos `Comp: escolher trecho` e `Comp: achatar` | Desfazer cada escolha | [02d Histórico e versões](../manual/02d-historico-e-versoes.md) |

## Passo a passo

### Cenário 1. Vocal de 3 tomadas com emendas nas frases

O loop foi marcado do compasso 5 ao 9 (`5.1.1` a `9.1.1`, batidas 16 a 32, **8 s**, de 8 s a 16 s do projeto) e a `Voz` cantou 3 passadas. O clipe nasceu com a **tomada 3** ativa (a última completa). As frases: versos nos compassos 5 e 6, uma frase no compasso 7 e o fecho no compasso 8.

1. Toque as 3 tomadas com o loop ligado (`Espaço`) e anote de ouvido: verso 1 melhor na tomada 2, frase do compasso 7 melhor na tomada 1, fecho melhor na 3.
2. Selecione o clipe da voz, botão direito (toque longo no celular) › `Comp por trecho`. Aparecem `Tomada 1`, `Tomada 2` e `Tomada 3`, uma sob a outra; a 3 leva o visto (`✓`) porque soa em tudo.
3. Mude a `Grade de encaixe` do transporte para `Compasso`, para as emendas caírem nas linhas de compasso.
4. Arraste na raia `Tomada 2` do `5.1.1` ao `7.1.1` (8 s a 12 s). Um retângulo verde-água acompanha o dedo; ao soltar, a raia acende nesse trecho e nasce uma emenda em 12 s.
5. Arraste na raia `Tomada 1` do `7.1.1` ao `8.1.1` (12 s a 14 s). Segunda emenda em 14 s.
6. O compasso 8 continua na tomada 3: não precisa arrastar.
7. Resultado na faixa: 3 clipes comuns, `Tomada 2` de 8 s a 12 s, `Tomada 1` de 12 s a 14 s e `Tomada 3` de 14 s a 16 s. Em cada emenda há um **crossfade de 20 ms**: o clipe da frente avança 10 ms sobre o de trás e o de trás recua 10 ms (por exemplo, o pedaço da tomada 1 passa a começar em 11,99 s, com o trecho do áudio a partir de 3,99 s, e a terminar em 14,01 s). A linha que você vê nas raias fica em 12 s e 14 s, onde você marcou.
8. Toque de novo com o loop ligado, prestando atenção às duas emendas. Se não gostou de uma, `Ctrl+Z` (cada arraste é um passo, `Comp: escolher trecho`) ou arraste de novo por cima.
9. Decidiu: clique no ícone de achatar (primeira raia, tooltip `Achatar: manter os clipes e descartar as tomadas`). Os clipes ficam como estão, sem as raias e sem o selo `N tomadas`.

**Se quiser ouvir uma tomada inteira antes de montar:** toque no nome (`Tomada 2`) e ela passa a valer no comp todo; `Ctrl+Z` volta ao que tinha.

### Cenário 2. Solo de guitarra: o melhor compasso de 4 tomadas

Loop de 4 compassos no solo, do `9.1.1` ao `13.1.1` (16 s a 24 s), **4 tomadas**; a ativa é a 4. Quer o compasso 9 da tomada 1, o 10 da 3, o 11 da 4 (já está) e o 12 da 2.

1. `Comp por trecho` no clipe do solo e `Grade de encaixe` em `Compasso`.
2. Raia `Tomada 1`: arraste de `9.1.1` a `10.1.1` (16 s a 18 s).
3. Raia `Tomada 3`: de `10.1.1` a `11.1.1` (18 s a 20 s).
4. Raia `Tomada 2`: de `12.1.1` a `13.1.1` (22 s a 24 s). O compasso 11 fica na tomada 4.
5. As emendas estão em 18 s, 20 s e 22 s, cada uma com crossfade de 20 ms. Como uma nota de guitarra sustentada atravessa a linha do compasso, ouça com o loop curto em volta de cada emenda: a emenda é 20 ms, então o ideal é cair num **ataque** ou numa pausa.
6. Quer comparar só o compasso 10 com outra tomada? **Toque** (sem arrastar) em qualquer ponto da raia `Tomada 2` dentro dele: o pedaço inteiro entre as duas emendas (18 s a 20 s) passa para a tomada 2, e as emendas ficam onde estavam. Toque na raia `Tomada 3` para voltar. Cada toque é um passo e dá para desfazer.
7. Se uma emenda caiu no meio de uma nota longa, mude a `Grade de encaixe` para `1/8` (0,25 s) ou `1/16` (0,125 s) e arraste de novo só o trecho afetado, empurrando a emenda para a pausa ou para o próximo ataque.
8. `Achatar` ou `Fechar`: `Fechar` deixa tudo como está e permite reabrir o comp depois; `Achatar` é definitivo (com `Ctrl+Z` logo em seguida).

### Cenário 3. Consertar uma palavra

O vocal está montado como no cenário 1, mas a palavra do compasso 6 (de **10,25 s a 10,75 s**, batidas 20,5 a 21,5) saiu torta e você a cantou melhor na tomada 1.

1. Se o comp está fechado: selecione qualquer pedaço (todos têm o selo `3 tomadas`) › `Comp por trecho`. Os pedaços de tomadas diferentes formam o mesmo grupo enquanto não forem movidos.
2. `Grade de encaixe` em `1/8` (meia batida, 0,25 s).
3. Na raia `Tomada 1`, arraste da batida 20 à batida 22 (10 s a 11 s): 0,25 s de folga antes e depois da palavra. Escolha bordas numa respiração ou no silêncio entre palavras.
4. Toque só essa região com o loop. Se ouvir a emenda, refine: `1/16` (0,125 s) ou `Livre` deixam a borda mais perto da respiração; arraste de novo só o que for preciso.
5. Se a palavra da tomada 1 também não serve, **toque** na raia de outra tomada no pedaço: a troca vale para o trecho inteiro entre emendas, e o pedaço que você acabou de criar é exatamente esse trecho.
6. Feche (`X`) e siga. O trecho novo herda ganho, mudo e fase invertida do **primeiro** clipe do comp, não do pedaço que estava ali (ver [Se der errado](#se-der-errado)).

## Variações

- **Comp na cópia:** duplique a faixa (ou salve uma versão, [Voltar atrás](voltar-atras-historico-e-versoes.md)) antes de `Achatar`, para poder voltar às tomadas.
- **Fade maior que 20 ms numa emenda** (uma nota longa que atravessa): selecione o pedaço e use `Fade de entrada…` ou `Fade de saída…` do menu do clipe; o fade deixa de ser automático e o comp respeita o que você pôs. Ver [Fades e crossfades na prática](fades-e-crossfades.md).
- **Só as bordas do loop:** as emendas não têm crossfade se caírem a menos de 10 ms do começo ou do fim do áudio da tomada (a do começo do loop, por exemplo). Nesses pontos o corte é seco; afaste a emenda alguns ms para dentro.
- **Comp e punch:** para refazer só um verso, regrave com punch ([Regravar um trecho com punch e pré-roll](regravar-um-trecho-com-punch-e-pre-roll.md)); o comp serve quando a gravação já tem as tomadas e você quer escolher entre elas.

## Por que funciona

- **O comp só decide quem toca onde.** Cada pedaço é um clipe comum que aponta para uma tomada, então nada se perde: o áudio de todas as tomadas segue no projeto, e desfazer devolve o estado anterior exato.
- **Todos os pedaços ficam alinhados ao mesmo instante zero das tomadas.** Como as tomadas foram gravadas no mesmo loop, cada trecho escolhido cai exatamente no tempo dele, sem deslocar a frase.
- **A emenda de 20 ms** (10 ms para cada lado, curva de potência constante) é curta o bastante para não borrar o ataque e longa o bastante para evitar o estalo de um corte seco em vozes e instrumentos diferentes; é a mesma mecânica dos clipes que se sobrepõem.
- **A grade decide a musicalidade.** Emendas em linha de compasso são fáceis de ouvir; emendas dentro de uma frase pedem `1/8`, `1/16` ou `Livre`.

## Se der errado

| Sintoma | Causa provável | O que fazer |
|---|---|---|
| Não há `Comp por trecho` no menu do clipe | O clipe não tem tomadas (não foi gravado em loop) | Só a gravação em loop cria tomadas. Ver [03c](../manual/03c-gravacao.md) |
| `Este clipe não tem tomadas: o comp é para a gravação em loop, que guarda uma tomada por volta.` | Clipe com menos de 2 tomadas | Grave de novo em loop |
| `O comp não funciona num clipe com warp, reverso, transposição ou loop: desligue isso primeiro.` | O clipe tem warp, altura, reverso ou loop | Desligue em `Warp e altura…` e no item de loop do menu do clipe, depois abra o comp |
| `A tomada N não está neste aparelho: não dá para escolhê-la.` | O áudio da tomada não está neste aparelho (ainda) | Abra o projeto com rede para o app buscar no servidor, ou escolha outra tomada |
| A emenda estala | Emenda em corte seco (a menos de 10 ms do fim ou começo do áudio, ou com fade seu na borda) ou nota sustentada atravessando | Mude a grade para `1/16` ou `Livre` e mova a emenda; ou ponha um fade curto à mão ([fades e crossfades](fades-e-crossfades.md)) |
| Um trecho novo ficou mais baixo ou mais alto que os vizinhos | Ele herdou o ganho do primeiro clipe do comp | Ajuste com `Ganho do clipe…` no pedaço (`(lido do código; não visto rodando)`) |
| O item do menu diz `Fechar o comp` no clipe que eu queria abrir | Há um comp aberto em outro clipe | Feche (`X` da primeira raia) e abra de novo |
| Depois de `Achatar` as tomadas sumiram | É o que `Achatar` faz | `Ctrl+Z` logo em seguida devolve a lista (`Comp: achatar`); o modo comp volta fechado, reabra pelo menu |
| As raias sumiram depois de apagar um pedaço | Um pedaço apagado ou movido sai do comp | `Ctrl+Z` traz de volta e as raias voltam junto |
| Quero liberar a cota das tomadas que sobraram | `Achatar` não remove o áudio do projeto | Só `Limpar áudios sem uso` na tela `Conta` libera, e apenas o que nenhum projeto cita mais (`(lido do código)`) |

Mais sobre limites e mensagens: [03f Comping por trecho](../manual/03f-comping.md#limites-e-pegadinhas).
