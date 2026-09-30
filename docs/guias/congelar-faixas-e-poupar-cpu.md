# Congelar faixas e poupar CPU

> Fixar o som de um baixo pesado em áudio para aliviar o projeto e seguir mixando, voltar atrás para mudar uma nota, ou converter um sintetizador em áudio para cortar e esticar; de 5 a 10 minutos cada, com um projeto que já tenha uma faixa de instrumento com efeitos.

## Ingredientes

| Recurso | Para quê aqui | Capítulo |
|---|---|---|
| `Congelar faixa…` (menu `Opções da faixa`) e o campo `Cauda dos efeitos` | A faixa passa a tocar o áudio renderizado, com o instrumento e os efeitos dentro; o conteúdo original fica guardado | [02e Congelar faixa](../manual/02e-congelar-faixa.md) |
| `Descongelar` | Devolve a faixa ao que ela era, para mexer em nota, instrumento ou efeito | [02e, Descongelar](../manual/02e-congelar-faixa.md#descongelar) |
| `Converter em áudio…` | Troca instrumento, notas e efeitos por um clipe de áudio, para cortar, esticar e fazer fades | [02e, Converter em áudio](../manual/02e-congelar-faixa.md#converter-em-áudio) |
| Ícone de floco e faixa azul | Mostram quais faixas estão congeladas | [02b, Cabeçalho de faixa](../manual/02b-timeline-e-clipes.md#cabeçalho-de-faixa) |
| Fader, pan, `M`, `S`, envios e saída | Seguem vivos na faixa congelada: a mixagem continua | [06 Mixer](../manual/06-mixer.md) |
| `Reverb`, `Distorção`, `Compressor` | Os efeitos que mais pesam e que vão para dentro do áudio | [06d Referência dos efeitos](../manual/06d-efeitos-referencia.md) |
| `Warp e altura…`, `Cortar no cursor` (`S`) e fades | O que se faz com o clipe de uma faixa convertida | [03b Warp e altura](../manual/03b-warp-e-altura.md), [02b](../manual/02b-timeline-e-clipes.md) |
| Cota de 4 GB | O áudio congelado é um WAV de 32 bits float novo no projeto e na conta | [01b Cotas e limites](../manual/01b-nuvem-e-sincronizacao.md#cotas-e-limites) |

O que vale para os três cenários:

- **Congelar é desfazível de dois jeitos:** `Ctrl+Z` logo depois, ou `Descongelar` a qualquer hora. `Converter em áudio…` desfaz por `Ctrl+Z` ou pelo [histórico](../manual/02d-historico-e-versoes.md) (passo `Converter em áudio`); depois de fechado o histórico do desfazer não há volta.
- **O áudio sai da faixa sozinha**, com o fader em 0 dB e o pan no centro, sem o master e sem o reverb do barramento (o envio continua ao vivo). O fader, o pan e os envios da faixa continuam valendo **depois** do áudio.
- **Barramento não congela**, e um `Compressor` ou `Gate` com `Sidechain` em **outra** faixa impede congelar (a legenda do item diz qual).
- **Quanto de CPU se poupa não foi medido** `(não confirmado)`: por construção, o `Reverb` e a `Distorção` em `4×` são os que mais fazem conta.

## Passo a passo

### Cenário 1: um baixo com efeitos pesados, congelado, e o resto da mixagem livre

Um projeto com a faixa `Baixo` (`Sintetizador`) com notas, e na cadeia um `Distorção` (sobreamostragem `4×`), um `Compressor` e um `Reverb` de preset `Sala` (`Decaimento` 1,4 s).

1. Toque o projeto e confirme que o `Baixo` soa como você quer: depois de congelar, o timbre fica preso.
2. No cabeçalho do `Baixo`, abra `Opções da faixa` (três pontos) e toque em `Congelar faixa…`. A legenda do item deve dizer `Toca o áudio renderizado; o conteúdo fica guardado`; se estiver desligado, leia o motivo (`A faixa está vazia`, ou o sidechain de outra faixa).
3. No diálogo `Congelar "Baixo"`, ajuste `Cauda dos efeitos` para 3 s: o `Reverb` `Sala` tem `Decaimento` de 1,4 s e leva cerca de 2,3 s para chegar perto do silêncio (100/60 do `Decaimento`, uma estimativa, não medida). O valor é um máximo: o silêncio no fim é aparado. Toque em **Congelar**.
4. Espere `Preparando…` e o `N%`. O render roda fora de tempo real, sem precisar tocar, e é mais rápido do que tocar `(quanto não foi medido)`.
5. Confira: o cabeçalho do `Baixo` ganhou o floco azul e a raia uma faixa azul sobre o trecho. Toque: deve soar igual.
6. Siga mixando o resto: o fader, o pan, `M`, `S` e os envios do `Baixo` continuam funcionando. Para o retorno de reverb do projeto, o envio do `Baixo` ainda alimenta o barramento.
7. Se o projeto ainda pesa, repita em outras faixas de instrumento com efeitos longos.

### Cenário 2: congelar e descongelar para mudar uma nota

1. Com o `Baixo` congelado (cenário 1), você percebe uma nota errada no compasso 5. Dê duplo clique no clipe de notas e mude a nota: **nada muda no som**, porque a faixa toca o áudio congelado. É esperado.
2. Abra `Opções da faixa` e toque em `Descongelar` (legenda `Volta o instrumento, as notas e os efeitos`). O floco e a faixa azul somem e o instrumento toca de novo, já com a nota nova. Se você acabou de congelar e ainda não mexeu em mais nada, `Ctrl+Z` também serve.
3. Ajuste o que quiser (nota, `Corte` do sintetizador, um efeito) e ouça.
4. Volte a `Congelar faixa…`, com a mesma `Cauda dos efeitos`. O app renderiza de novo e grava outro áudio.
5. O áudio do primeiro congelamento **continua na lista de áudios do projeto** e, como o documento o cita, a nuvem o conta como em uso: a cota de 4 GB carrega os dois `(lido do código; não testado)`. Um baixo de 4 minutos em estéreo a 48 kHz tem cerca de 92 MB (23 MB por minuto). Não congele e descongele sem parar em faixas longas.

### Cenário 3: converter em áudio e cortar (ou esticar)

Um pad de `Sintetizador` de 8 compassos com `Reverb` que você quer cortar ao meio e com um fade de saída.

1. No cabeçalho do pad, `Opções da faixa` e `Converter em áudio…` (o item só existe em faixa de instrumento ou em faixa de áudio já congelada).
2. No diálogo `Converter "Pad" em áudio`, deixe `Cauda dos efeitos` em 8 s (padrão) e toque em **Converter**. O texto avisa: `O instrumento, as notas e os efeitos da faixa saem e ficam um clipe de áudio só (dá para desfazer)`.
3. A faixa vira faixa de áudio com **um** clipe (arquivo `Pad (convertida).wav`). Ponha o cursor no compasso 5 e aperte `S` (`Cortar no cursor`). Apague a metade de trás, ou arraste uma das pontas.
4. Arraste o canto de cima à direita do clipe para um fade de saída, ou use o menu do clipe (`Fade de saída…`) com o tamanho exato.
5. Para esticar ao andamento do projeto, abra `Warp e altura…` no clipe, digite o `BPM do áudio` e toque em `Ajustar ao andamento` ([Warp e altura](../manual/03b-warp-e-altura.md)). Um pad sem ritmo não tem andamento para o `Detectar` achar; o valor é o andamento em que as notas foram pensadas.
6. Se não gostou, `Ctrl+Z` desfaz passo a passo até o `Converter em áudio`, que devolve o instrumento. Depois disso não há mais como voltar às notas, então se duvida use `Congelar faixa…`.

## Variações

- **Só para a cauda do reverb.** O mesmo congelar com `Cauda dos efeitos` escolhida pelo reverb: cerca de 100/60 do `Decaimento` (estimativa). Um `Reverb` `Catedral` (`Decaimento` 7 s) pede uns 12 s; o diálogo vai até 30 s. Um `Reverb` com `Congelar` ligado (`Shimmer congelado`) nunca cai e termina cortado na cauda escolhida.
- **Congelar uma faixa de áudio.** `Congelar faixa…` também existe em faixa de áudio: os efeitos dela (e o warp dos clipes) passam para dentro do áudio. Depois, `Converter em áudio…` (agora disponível) troca os clipes por um só, com os efeitos já embutidos.
- **Manter a original ao lado.** Use `Renderizar em faixa nova` (o antigo `Congelar em áudio`): cria uma faixa `(áudio)` logo abaixo e deixa a original muda, com as notas e os efeitos ([08](../manual/08-exportacao.md#renderizar-em-faixa-nova-antigo-congelar-em-áudio)).
- **Levar o projeto para um aparelho mais fraco.** Congele as faixas pesadas antes de sincronizar ou exportar o `.jopendaw`; o outro aparelho só toca áudio. Ver [trabalhar em dois aparelhos](trabalhar-em-dois-aparelhos.md) e [backup e levar o projeto](backup-e-levar-projeto-para-outro-aparelho.md).

## Por que funciona

- O render é o mesmo da exportação, da faixa sozinha. Por isso o áudio congelado soa como a faixa soava antes do fader, do pan e do master, e o que sobra na mixagem (fader, pan, envios, saída) é aplicado depois, ao vivo.
- Congelar não apaga nada: o instrumento, as notas, os clipes, os efeitos e a automação continuam no projeto; o motor só deixa de recebê-los. É por isso que `Descongelar` devolve a faixa idêntica, inclusive com o que você editou enquanto ela estava congelada.
- Converter troca em vez de guardar: por isso o clipe pode ser cortado, esticado e ter fades como qualquer áudio, e por isso não há `Descongelar` depois.
- A cauda é um máximo e o silêncio do fim é aparado (abaixo de −100 dB), então o custo de uma cauda generosa é só o tempo do render; o custo de uma cauda curta é um corte seco.

## Se der errado

| Sintoma | Causa provável | O que fazer |
|---|---|---|
| Mexo no instrumento ou num efeito e nada muda | A faixa está congelada (floco no cabeçalho) | `Descongelar`, ajuste e congele de novo |
| O item `Congelar faixa…` está desligado | A legenda diz o motivo: `A faixa está vazia`, `Pare a gravação antes`, ou `Um efeito usa o sidechain de "nome": tire a chave antes de congelar` | Escreva notas ou clipes; pare a gravação; volte o `Sidechain` do efeito a `Própria entrada` e congele (religue depois do `Descongelar`) |
| Não vejo o item `Converter em áudio…` | A faixa é de áudio comum (já é áudio) ou um barramento | Congele a faixa de áudio antes (aparece na faixa congelada) |
| O reverb corta de repente no fim | `Cauda dos efeitos` curta demais | Desfaça e congele com uma cauda maior (até 30 s) |
| O reverb some quando exporto | O fim do arquivo é o fim do último clipe mais a `Cauda` da exportação (0 a 10 s), e não o fim do áudio congelado | Suba a `Cauda` em `Exportar áudio` ([08](../manual/08-exportacao.md)) |
| `A faixa "nome" mudou durante o render: o áudio já nasceria velho. Tente de novo.` | Você editou o som da faixa com o render rodando | Espere a barra terminar e congele de novo |
| `A faixa "nome" não soou nada: nada para congelar.` | O render saiu mudo (clipes mudos, instrumento sem volume, `Gate` fechado) | Confira a faixa tocando e congele de novo |
| Uma faixa congelada fica muda em outro aparelho | O áudio congelado não chegou a esse aparelho `(lido do código; não testado)` | Espere a sincronização, ou `Descongelar` para voltar ao instrumento |
| A cota de 4 GB encheu | Cada congelamento é um WAV de 32 bits float (cerca de 23 MB por minuto em estéreo a 48 kHz) | [01b, Cotas e limites](../manual/01b-nuvem-e-sincronizacao.md#cotas-e-limites); `Descongelar` não apaga o áudio renderizado |
