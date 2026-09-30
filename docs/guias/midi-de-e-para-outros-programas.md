# MIDI de e para outros programas

> Levar uma melodia do jopendaw para outro DAW, trazer um `.mid` de pacote de acordes e mexer nele com as ferramentas MIDI, e guardar as notas do projeto num arquivo MIDI padrão; cada cenário leva de 2 a 10 minutos.

Um arquivo MIDI (`.mid`) leva **notas, não som**: altura, começo, duração e velocidade de cada nota, mais três controles (pitch bend, modulação e pedal). O timbre, os efeitos e o mixer ficam de fora, nos dois sentidos. Por isso ele serve para trocar música entre programas, e não para trocar o projeto inteiro (para isso há o `.jopendaw`, ver o cenário 3).

## Ingredientes

- [Exportação](../manual/08-exportacao.md#notas-em-midi-mid): o botão `Notas em MIDI (.mid)…` da janela **Exportar áudio**, com as opções `Clipe selecionado` e `Todas as faixas de notas`.
- [Áudio e clipes](../manual/03-audio-e-clipes.md#importar-um-arquivo-midi-mid): o botão `Importar` (ou `Ctrl+I`), que aceita `.mid` e `.midi`, a pergunta de andamento (`Usar o andamento do arquivo (X BPM)?` ou, se o arquivo muda de andamento, `Usar os andamentos do arquivo (N mudanças, a partir de X BPM)?`) e a janela `<nome>.mid importado, com avisos`.
- [Editor de notas](../manual/05-piano-roll.md): abrir o clipe, `Ctrl+A`, `↑`/`↓` e `Shift+↑`/`Shift+↓` para transpor, `Quantizar`.
- [Ferramentas MIDI](../manual/05b-ferramentas-midi.md): `Escala…`, `Prender na escala`, `Arpejador…`, `Desdobrar acorde em arpejo`, `Humanizar…`.
- [Bateria](../manual/04b-bateria.md): as 12 peças que recebem as notas do canal 10.
- Para o cenário 3: [Projeto em arquivo (`.jopendaw`)](../manual/01-projetos-modelos-conta.md#projeto-em-arquivo-jopendaw) e o guia [Backup e levar o projeto para outro aparelho](backup-e-levar-projeto-para-outro-aparelho.md).

O que o app escreve é um arquivo MIDI tipo 1 com 480 pulsos por semínima, uma trilha por faixa e um canal fixo por trilha (bateria no canal 10). Abrir esses arquivos em Ableton Live, FL Studio, MuseScore ou outro programa e abrir arquivos deles no jopendaw `(testado só por testes automáticos)`: os testes escrevem e leem os bytes com o próprio app, nenhum programa externo abriu um arquivo do jopendaw.

## Passo a passo

### Cenário 1: levar uma melodia para outro DAW

Resultado: a melodia do jopendaw como notas editáveis na faixa de instrumento do outro programa. Uns 2 minutos.

1. Na linha do tempo, **clique no clipe de notas** da melodia para selecioná-lo (um clipe de áudio não serve: a opção fica desligada).
2. Toque em **Exportar** na barra do transporte e, na janela **Exportar áudio**, em **Notas em MIDI (.mid)…**. Abre a janela `Exportar MIDI (.mid)`.
3. Deixe marcada `Clipe selecionado` (a legenda diz `<nome do clipe>, começa no início do arquivo.`) e toque em **Exportar**. A janela responde `<nome>.mid salvo: 1 faixa, N notas.`; se alguma nota ficou de fora, ela diz quantas (`fora do clipe ou de 0–127`).
4. Na web o arquivo vai para a pasta de downloads; no Android abre a janela `Salvar <nome>`.
5. No outro programa, arraste o `.mid` para uma faixa de instrumento e escolha o timbre lá. O arquivo traz o mapa de andamento e o de compassos do projeto (uma fórmula como `6/8` sai como `6/8`; as rampas saem em degraus); se o programa perguntar, aceite.

O clipe sai **do começo do arquivo**, mesmo que esteja no compasso 9 do projeto: o outro programa vai colocá-lo onde você soltar. Para levar várias faixas de uma vez (a melodia, o baixo e a bateria) e manter cada uma na sua posição do projeto, use `Todas as faixas de notas` no lugar do passo 3: sai uma trilha por faixa e a bateria vem no canal 10.

Para levar também o **som**, exporte o WAV (ou os stems) da mesma janela e importe no outro programa ao lado do `.mid`, ver [Exportação](../manual/08-exportacao.md).

### Cenário 2: trazer um `.mid` de pacote de acordes e usar as ferramentas MIDI

Resultado: uma progressão de um pacote de acordes, na sua tonalidade, arpejada e menos rígida, tocando num timbre seu. Uns 10 minutos.

1. Clique na régua para pôr o cursor no compasso onde a progressão deve começar (o início do arquivo cai no cursor).
2. Toque em **Importar** (ou `Ctrl+I`), escolha o `.mid`. Se o arquivo traz um andamento ou compasso diferente do projeto, abre `Usar o andamento do arquivo (X BPM)?` (ou `Usar os andamentos do arquivo (N mudanças, a partir de X BPM)?` se ele muda de andamento no meio). Escolha `Manter o do projeto` para tocar no seu andamento (as notas ficam nas mesmas batidas, só a velocidade da música muda) ou `Usar o do arquivo` para trocar o mapa de andamento e o de compassos do projeto pelos dele.
3. As faixas novas aparecem no fim da lista, uma por canal com notas, como `Sintetizador` (a do canal 10 vira `Bateria`). Se abrir `<nome>.mid importado, com avisos`, leia os avisos e toque em `Entendi`.
4. O arquivo não escolhe o timbre (o `Program Change` é ignorado): abra o [painel do instrumento](../manual/04-painel-de-instrumento.md) da faixa e escolha o som que quiser.
5. Dê dois cliques no clipe para abrir o editor. Para mudar de tonalidade, aperte `Ctrl+A` e transponha com `↑`/`↓` (1 semitom) e `Shift+↑`/`Shift+↓` (1 oitava) até a fundamental cair onde você quer.
6. Clique em `Escala`, escolha a `Tônica` e a `Escala` da sua música e `Aplicar`: a grade realça as notas da escala e você enxerga quais acordes saem dela. Com `Prender na escala` ligado, o que você desenhar depois encaixa na escala.
7. Selecione os acordes e use `Ferramentas > Escala e acordes > Arpejador…` (por exemplo `Padrão` `Subir`, `Taxa` `1/16`, `Gate` 90%) ou `Desdobrar acorde em arpejo`. Só funciona onde as notas do acorde começam juntas, como nos pacotes de acordes em bloco.
8. `Ferramentas > Seleção > Humanizar…` (padrão `Tempo` 50%, `Velocidade` 50%) tira o ar de máquina; se exagerou, `Quantizar` com força `50%` traz parte das notas de volta à grade.

Se o pacote traz baixo e bateria em outros canais, cada canal virou uma faixa: aproveite só as que quiser e apague as outras.

### Cenário 3: backup das notas em arquivo MIDI padrão

Resultado: um `.mid` com as notas de todas as faixas, para abrir em qualquer programa mesmo que o projeto se perca. Uns 2 minutos.

1. **Exportar** > **Notas em MIDI (.mid)…**.
2. Escolha `Todas as faixas de notas` (a legenda diz quantas faixas vão) e toque em **Exportar**. O arquivo se chama `<nome do projeto>.mid`.
3. Guarde-o junto do arquivo do projeto. O `.mid` **não é** o backup do projeto: o backup de verdade é `Projeto inteiro (.jopendaw)…` (faixas, sons, efeitos, automação, áudios). O `.mid` é o seguro extra das notas.
4. Para recuperar as notas num projeto novo: ponha o cursor no compasso 1, toque em **Importar**, escolha o `.mid` e, na pergunta de andamento (`Usar o andamento do arquivo (X BPM)?` ou `Usar os andamentos do arquivo (N mudanças, a partir de X BPM)?`), escolha `Usar o do arquivo` (o andamento, as mudanças de andamento e os compassos voltam; as rampas voltam como degraus de andamento, sem a marca de rampa). Cada trilha volta como uma faixa com o nome que tinha; a bateria volta como `Bateria`.

## Variações

- **Só a bateria.** Selecione o clipe da faixa `Bateria` e exporte com `Clipe selecionado`: sai no canal 10, e programas que seguem o General MIDI mostram uma faixa de percussão. As alturas são as das peças do app (36 bumbo, 38 caixa, 42 chimbal fechado e assim por diante).
- **Pitch bend e pedal.** Os pontos que você desenhou ou gravou na faixa de controle vão junto (`Pitch bend`, `Modulação` e `Sustain`). O `Alcance do bend` do instrumento **não** vai: se o outro programa usa outro alcance, o bend soa mais ou menos aberto. Ver [Expressão MIDI na prática](expressao-midi-na-pratica.md).
- **Levar o `.mid` de volta depois de mexer no outro programa.** Importe de novo: cada trilha vira uma faixa nova (não substitui a antiga). Apague a original se não precisar dela.
- **Vários `.mid` de uma vez.** O seletor aceita mais de um arquivo; cada um é lido em sequência, com a sua pergunta de andamento e a sua janela de avisos.

## Por que funciona

- **O arquivo MIDI guarda batidas, não segundos.** O app conta as notas em batidas e escreve 480 pulsos por batida; por isso a melodia continua na mesma posição musical em qualquer programa, e recusar o andamento do arquivo (`Manter o do projeto`) só muda a velocidade, nunca a posição das notas.
- **O canal 10 é a bateria.** É a convenção do General MIDI: o app escreve a faixa `Bateria` no 10 e lê o 10 como bateria, então um pacote de bateria de outro programa cai nas peças certas (`Bumbo` 36, `Caixa` 38, e as parecidas por aproximação, como o prato chinês no `Prato de ataque`).
- **Um `.mid` não tem som.** O timbre fica com quem toca o arquivo. É a razão de o cenário 2 pedir que você escolha o instrumento, e de o cenário 3 não substituir o `.jopendaw`.

## Se der errado

- **`Não deu para importar <nome>: Este arquivo não é um MIDI padrão (.mid): falta o cabeçalho "MThd".`** O arquivo não é MIDI (ou está corrompido). Exporte-o de novo do programa de origem como "MIDI" (formato 0 ou 1).
- **`... usa tempo em quadros SMPTE, que o app não lê. Salve-o de novo com tempo em pulsos por semínima (PPQ).`** O arquivo usa relógio de vídeo. No programa de origem exporte com resolução em PPQ (o mais comum).
- **`O arquivo MIDI não tem nenhuma nota.`** O arquivo só tem andamento ou controles. Confira no programa de origem se a faixa certa foi exportada.
- **Tocou mais rápido ou mais lento do que no original.** Você escolheu `Manter o do projeto` e o andamento do arquivo era outro. Desfaça (`Ctrl+Z`; a importação inteira é um passo) e importe de novo com `Usar o do arquivo`, ou mude o `BPM` no botão de andamento.
- **A música tinha mudança de andamento e agora anda reta.** Você escolheu `Manter o do projeto` na pergunta `Usar os andamentos do arquivo (…)?`; o app avisa `O arquivo muda de andamento no meio (de X a Y BPM); mantive o do projeto.` Desfaça (`Ctrl+Z`) e importe de novo com `Usar o do arquivo`. A exportação leva o mapa de andamento e o de compassos inteiros; as rampas saem em degraus de 1/16 de batida e voltam como pontos comuns. Se o arquivo tem mais de 256 pontos de andamento, o app funde os que diferem menos de 0,05 BPM (e, se ainda passar, aumenta a tolerância) e avisa `O arquivo tem N mudanças de andamento; fundi as que diferem…` `(testado só por testes automáticos)`.
- **A bateria importada tem notas sem som.** O aviso `A bateria do app não tem: ...` lista as peças que a bateria do app não tem (pandeiro, vibraslap, notas fora de 35–59). As notas estão no clipe, mas não soam: leve-as para uma peça que exista.
- **Tudo soa como piano ou como o mesmo timbre no outro programa.** O app não escreve `Program Change`: escolha o timbre de cada trilha lá.
- **Faltam notas no arquivo exportado.** A janela avisou `K notas fora do clipe ou de 0–127 ficaram de fora`: as que começam depois do fim do clipe, ou com altura fora de 0–127, não saem. Estenda o clipe na régua do editor e exporte de novo.
- **Ao recuperar o backup, os clipes viraram um só por faixa.** É como o `.mid` funciona: clipes da mesma faixa viram uma trilha só, e o nome do clipe, a escala do clipe, o tipo de instrumento (`Sampler`, `FM`, `Wavetable` voltam como `Sintetizador`), o volume, o pan, o mudo e os efeitos não estão no arquivo. Para tudo isso, use o `.jopendaw`.
- **`Pare a gravação para importar MIDI.`** Não se importa gravando; pare a gravação antes.
