# Achar e usar samples com o navegador de áudios

> Montar uma batida arrastando samples que você já tem na conta, conferir um loop no andamento do projeto antes de inserir e reaproveitar os áudios de outro projeto, tudo pela aba `Áudios` do painel de baixo; uns 10 minutos por cenário.

## Ingredientes

| Recurso | Para quê aqui | Capítulo |
|---|---|---|
| Aba `Áudios` (`Shift+B`), busca, chips `Todos` / `Projeto` / `Conta` | Achar o áudio certo entre os do projeto e os da conta | [03g Navegador de áudios](../manual/03g-navegador-de-audios.md) |
| Botão de play e barra de progresso | Ouvir sem mexer no projeto, com o transporte parado ou tocando, e pular para um ponto | [03g, A pré-escuta](../manual/03g-navegador-de-audios.md#a-pré-escuta-uma-voz-à-parte) |
| Alça de arrastar e botão `+` | Levar o áudio para o arranjo (clipe na faixa de áudio, zona no sampler) | [03g, Inserir e arrastar](../manual/03g-navegador-de-audios.md#inserir-e-arrastar) |
| Chip `No andamento do projeto` | Ouvir um loop esticado para o andamento do projeto antes de decidir | [03g, Controles](../manual/03g-navegador-de-audios.md#em-cima-da-lista) |
| Grade de encaixe (`Livre`, `Compasso`, `1/4`, `1/8`, `1/16`) | Decidir em que ponto o clipe cai quando você solta | [02b Timeline e clipes](../manual/02b-timeline-e-clipes.md) |
| Região de loop na régua e `L` | Ouvir o compasso montado em repetição | [02 Transporte](../manual/02-transporte.md) |
| `Warp e altura…` no menu do clipe | Deixar o clipe inserido no andamento de verdade | [03b Warp e altura](../manual/03b-warp-e-altura.md) |
| Cartão `ZONAS` do sampler | Acertar as zonas que o arrasto cria | [04c Sampler](../manual/04c-sampler.md) |
| Conta, cota de 4 GB e `Usado em` | Reusar áudio de outro projeto sem gastar cota nova | [01b Nuvem e sincronização](../manual/01b-nuvem-e-sincronizacao.md), [01 Conta](../manual/01-projetos-modelos-conta.md#armazenamento-de-áudios-na-tela-conta) |

O que vale para os três cenários:

- A lista mostra os áudios **do projeto** (primeiro) e os **da conta** (depois), sem repetir o que está nos dois. A conta é lida quando o painel abre; depois de sincronizar outro projeto, use `Atualizar a lista`.
- Um áudio com `fora deste aparelho` é baixado sozinho ao ouvir ou inserir.
- Os nomes dos arquivos (`kick_01.wav`, `loop_90bpm.wav`) e as durações abaixo são **exemplos** para fazer as contas; o que o app faz com eles vem do código.
- O som da pré-escuta não foi ouvido por quem escreveu este guia `(não confirmado ao ouvido)`; o arrasto para o arranjo foi conferido só por testes automáticos `(testado só por testes automáticos)`.

## Passo a passo

### Cenário 1: montar uma batida de 1 compasso arrastando samples da conta

Resultado: `kick_01.wav` nos tempos 1 e 3, `snare_01.wav` nos tempos 2 e 4 e `hat_closed.wav` em todos os tempos, cada um na sua faixa, com o compasso em loop. Projeto a **120 BPM**, 4/4: 1 tempo = 0,5 s e 1 compasso = 2 s. Os exemplos duram 0,4 s (kick), 0,3 s (snare) e 0,1 s (hat), então cada um cabe dentro de um tempo.

1. Abra o projeto, ponha a grade de encaixe em `1/4` (cada tempo) e abra `Áudios` (`Shift+B`).
2. Toque no chip `Conta` e busque `kick`. Ouça `kick_01.wav` no play; se ele tiver `fora deste aparelho`, a barra mostra `Baixando o áudio do servidor…` uma vez.
3. Pegue a alça de `kick_01.wav` e solte **abaixo da última faixa** (na linha de adicionar faixa ou no master), no começo da régua. Nasce uma faixa de áudio `kick_01` com o clipe no tempo 1 (o ponto é arredondado à grade).
4. Pegue o mesmo áudio de novo e solte **na linha da faixa `kick_01`**, no tempo 3. O clipe entra na mesma faixa, porque o trecho está livre: o primeiro termina em 0,4 s e o segundo começa em 1 s.
5. Faça o mesmo com `snare_01.wav` (busque `snare`): primeiro solte abaixo das faixas, no tempo 2; depois na faixa dele, no tempo 4.
6. Com `hat_closed.wav`: solte abaixo das faixas no tempo 1 e depois na faixa dele nos tempos 2, 3 e 4.
7. Marque o compasso 1 na régua arrastando do começo ao fim dele (0 a 2 s no andamento de 120 BPM), aperte `L` e `Espaço`: o compasso repete. Acerte os níveis no mixer ([06](../manual/06-mixer.md)).

Se um clipe cair numa faixa nova quando você esperava a mesma, o trecho estava ocupado (clipe por baixo do ponto onde você soltou) ou a linha sob o ponteiro não era a da faixa: o realce de faixa e a linha vertical mostram onde vai cair antes de soltar.

### Cenário 2: conferir um loop no andamento antes de inserir

Resultado: você ouve `loop_90bpm.wav` (4 compassos a 90 BPM) já no andamento de um projeto a **100 BPM** antes de decidir e, se servir, deixa o clipe exato em 4 compassos. A conta: 16 tempos a 90 BPM duram 10,67 s; a 100 BPM duram 9,6 s; a razão é 90 ÷ 100 = 0,90.

1. Com o projeto a 100 BPM, abra `Áudios`, busque `loop` e ligue o chip `No andamento do projeto`.
2. Toque no play de `loop_90bpm.wav`. Aparece `Ajustando ao andamento…` (o app estima o andamento do áudio e estica uma cópia). Quando toca, a legenda diz algo como `0:03 / 0:10 · esticado ×0,90` (a duração cai de `0:11` para `0:10`).
3. Se a legenda disser outra razão (por exemplo `×1,80`), o detector achou o dobro ou a metade do real; nesse caso use a pré-escuta só como referência de timbre e acerte o andamento no passo 5.
4. Ouça com o transporte tocando o resto do projeto: a pré-escuta soma por cima, sem parar nem mover nada.
5. Gostou? Toque em `+` com uma faixa de áudio selecionada e o cursor no compasso 1: o clipe entra **como o arquivo é** (10,67 s, cerca de 17,8 tempos a 100 BPM). Clique com o botão direito nele, `Warp e altura…`, `Detectar` (ou digite `90` em `BPM do áudio` e `Ajustar ao andamento`): o clipe passa a durar 9,6 s, exatos 4 compassos.
6. Se a pré-escuta avisou `Não deu para estimar o andamento de loop_90bpm.wav; toquei no original.`, digite `90` à mão no passo 5.

### Cenário 3: reaproveitar áudios de outro projeto

Resultado: os vocais do projeto `Música A` entram no projeto `Música B`, sem importar de novo nem gastar cota. Exemplo: `vocal_take3.wav` de 42 s, no compasso 5 de `Música B` (a 120 BPM, o compasso 5 começa em 8 s).

1. Em `Música A`, espere o indicador de nuvem mostrar `Sincronizado` ([01b](../manual/01b-nuvem-e-sincronizacao.md)): só então os áudios dela estão na conta.
2. Abra `Música B`, `Áudios`, `Atualizar a lista` e o chip `Conta`. Busque `vocal`.
3. Passe o mouse no nome (no toque, segure) para ler `Usado em: Música A` e confira que é o áudio certo. Ouça com o play; arraste a barra para pular ao refrão.
4. Ponha a grade em `Compasso`, pegue a alça e solte na faixa de áudio de `Música B` no compasso 5. O arquivo é baixado uma vez e fica neste aparelho. O aviso diz `vocal_take3.wav entrou no arranjo.`
5. O áudio passou a aparecer como `no projeto` na lista. Como o servidor já tinha esse arquivo (mesmo SHA-256), o app só envia o documento de `Música B` na próxima sincronização: a cota de 4 GB não muda.

## Variações

- **Sampler em vez de clipes.** Crie uma faixa `Sampler` e arraste para a linha dela: cada áudio vira uma **zona**. A primeira cobre o teclado todo; a segunda divide a primeira ao meio (aviso `O teclado já estava coberto…`). Depois acerte `Notas de`, `até` e `Nota base` no cartão `ZONAS` ([04c](../manual/04c-sampler.md)). Para um kit de batida, prefira clipes (cenário 1) ou fatie um loop ([guia do sampler](sampler-multi-zona-e-fatiar-loops.md)).
- **Inserir sem arrastar.** Selecione a faixa, posicione o cursor e toque em `+`; é o que funciona melhor no celular. Com um sampler selecionado o `+` cria a zona.
- **Só ouvir e voltar.** A pré-escuta nunca mexe no projeto: dá para passar por 20 áudios da conta, nenhum entra, nada vai para o desfazer.
- **Áudios de projetos apagados.** Eles continuam na conta (sem `Usado em`) até você os apagar na tela `Conta`, e servem do mesmo jeito.

## Por que funciona

- O áudio é identificado pelo **hash do arquivo**. Por isso a lista junta o do projeto e o da conta sem duplicar, o mesmo arquivo em dois projetos conta uma vez na cota e inseri-lo de novo não sobe nada.
- A pré-escuta é uma **voz à parte** no motor: não é faixa, então não passa pelo mixer, não entra no medidor nem na exportação e não cria passo no desfazer. É por isso que dá para ouvir à vontade com o projeto parado ou tocando.
- O chip `No andamento do projeto` estica uma **cópia** só para a audição (a mesma técnica do warp dos clipes); por isso o clipe inserido é o original e o andamento dele se acerta depois, no warp.
- O ponto de soltura passa pela **grade de encaixe**: a grade em `Compasso` ou `1/4` faz os clipes caírem no tempo sem régua.

## Se der errado

| Sintoma | Causa provável | O que fazer |
|---|---|---|
| Um áudio que você acabou de sincronizar em outro projeto não aparece em `Conta` | A lista é lida ao abrir o painel | `Atualizar a lista`; se ainda faltar, espere o `Sincronizado` do outro projeto |
| Aviso `<nome>: o servidor não tem este áudio e ele não está neste aparelho.` | O áudio foi apagado da conta (tela `Conta`) e nunca esteve neste aparelho | Importe o arquivo de novo (`Ctrl+I`) |
| `Não deu para tocar <nome>. É um formato que este aparelho decodifica?` | Formato que o navegador ou o app não abre | Converta para WAV ou FLAC ([03 Formatos aceitos](../manual/03-audio-e-clipes.md#formatos-aceitos)) |
| A legenda não mostra `esticado` com o chip ligado | O áudio já está no andamento do projeto (razão 1) ou a estimativa não teve confiança (aviso `toquei no original`) | Confira o andamento do projeto; digite o `BPM do áudio` no warp |
| O clipe caiu numa faixa nova | O trecho estava ocupado, a faixa sob o ponteiro não era de áudio (sintetizador, bateria, barramento e pasta criam faixa de áudio nova) ou você soltou fora das faixas | Solte sobre a linha de uma faixa de áudio livre naquele trecho, ou mova o clipe depois |
| A pré-escuta não soa na web | O navegador só libera som depois de um gesto, ou o `engine.wasm` é anterior à fase 26 B | Toque no play de novo; recarregue o app para pegar o motor novo |
| A pré-escuta some quando troco de aba | Fechar o painel ou trocar de aba a cala de propósito | Volte à aba `Áudios` e toque no play de novo |
| Distorce ou corta quando a pré-escuta toca junto com o projeto | A pré-escuta soma depois do limitador do master e sem controle de volume, então o total pode passar de 0 dBFS `(lido do código; não ouvido)` | Baixe o volume do aparelho, ou ouça com o projeto parado |
