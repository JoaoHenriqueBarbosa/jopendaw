# Entregar uma música por seções e stems

> Sair do app com a música cortada do jeito que quem recebe precisa: um arquivo por seção num `.zip` para o mixer, só o refrão em MP3 para uma prévia, ou stems só de algumas faixas com a cauda do reverb; de 5 a 10 minutos cada, com marcadores na régua.

**Aviso de confiança (fase 26 C, `f12d405`).** O que aparece na janela de opções (rótulos, prévia de nome, contador, resumo) foi lido do código e conferido por testes automáticos; a janela abrir e as opções de marcador ficarem apagadas sem marcadores foi visto no Chrome. **Nenhuma exportação por seção, por faixa escolhida ou em `.zip` foi feita de verdade**: nomes, contagens e fluxo vêm do plano (`export_plan.dart`) e de testes com motor e servidor falsos; nada foi ouvido nem aberto num programa externo `(testado só por testes automáticos)`. Durações e tamanhos abaixo são contas a partir do andamento e das fórmulas do manual `(conta feita à mão)`.

## Ingredientes

| Recurso | Para quê aqui | Capítulo |
|---|---|---|
| Marcadores na régua (`Shift+M`, menu do marcador) | Dizem onde cada seção começa; o nome do marcador vai para o nome do arquivo | [02b Timeline e clipes, Marcadores e seções](../manual/02b-timeline-e-clipes.md#marcadores-e-seções) |
| **Exportar esta seção…** (menu do marcador) | Abre a exportação já no trecho de um marcador ao seguinte | [08 Exportação, Onde fica](../manual/08-exportacao.md#onde-fica) |
| `INTERVALO` > **Uma por seção** e **Entre marcadores** | Um arquivo por seção, ou um trecho entre dois marcadores | [08 Exportação, Entre marcadores e Uma por seção](../manual/08-exportacao.md#entre-marcadores) |
| **NOME DOS ARQUIVOS** (`{projeto}`, `{marcador}`, `{n}`) e a prévia | Os nomes que o receptor vai ver, sem colisão | [08 Exportação, O modelo de nome e a prévia](../manual/08-exportacao.md#o-modelo-de-nome-e-a-prévia) |
| **Faixas** (chips, **Só a selecionada**) | A mixagem e os stems só das faixas que você quer mandar | [08 Exportação, Faixas escolhidas](../manual/08-exportacao.md#faixas-escolhidas) |
| **Stems** e **Cauda** | Um arquivo por faixa e o tempo para o reverb terminar | [08 Exportação, Stems](../manual/08-exportacao.md#stems) |
| **Reunir num .zip** | Um arquivo só para mandar, em vez de dezenas de downloads | [08 Exportação, O zip](../manual/08-exportacao.md#o-zip) |
| `MP3 (para compartilhar)` e `Artista (opcional)` | A prévia leve, com conta e rede | [08 Exportação, FLAC e MP3 pelo servidor](../manual/08-exportacao.md#flac-e-mp3-pelo-servidor), [guia Exportar para compartilhar](exportar-para-compartilhar.md) |
| Loudness | Por que não normalizar seções que serão coladas de novo | [08 Exportação, Loudness e cauda por arquivo](../manual/08-exportacao.md#loudness-e-cauda-por-arquivo), [guia Loudness e master](loudness-e-master.md) |

O projeto dos exemplos: `Minha Música`, 120 BPM em 4/4 (um compasso dura 2 s), 32 compassos (1:04). Marcadores: `Intro` no compasso 1, `Verso` no 5, `Refrão` no 13, `Ponte` no 21 e `Final` no 25. O exemplo 3 tem 7 faixas: `Bateria`, `Baixo`, `Guitarra`, `Teclado`, `Voz`, `Coro` e um barramento `Retorno reverb` para onde `Voz` e `Guitarra` mandam um envio.

## Passo a passo

### Cenário 1: cinco seções, um arquivo cada, num zip de WAV para o mixer

1. Ponha os marcadores: leve o cursor ao compasso 1 e aperte **Shift+M**, digite `Intro` e **Salvar**; repita no compasso 5 (`Verso`), 13 (`Refrão`), 21 (`Ponte`) e 25 (`Final`). O nome aceita até 40 caracteres.
2. Toque em **Exportar** e, em `INTERVALO`, em **Uma por seção**. A janela lista cinco caixas, todas marcadas, e o contador `5 de 5 seções`:

   | Caixa | Linha de baixo |
   |---|---|
   | `Intro` | `Compassos 1 a 4 · 0:08` |
   | `Verso` | `Compassos 5 a 12 · 0:16` |
   | `Refrão` | `Compassos 13 a 20 · 0:16` |
   | `Ponte` | `Compassos 21 a 24 · 0:08` |
   | `Final` | `Compassos 25 a 32 · 0:16` |

3. Deixe **NOME DOS ARQUIVOS** no padrão `{projeto}-{marcador}-{n}`. A prévia mostra `Minha Música-Intro-1.wav, Minha Música-Verso-2.wav, Minha Música-Refrão-3.wav e mais 2`.
4. `FORMATO` em `WAV 24 bits`, `TAXA DE AMOSTRAGEM` em `A do aparelho (48 kHz)`, `Stems` desligado, `Normalizar` e `Normalizar o loudness` **desligados**, `Cauda` em 2 s. O resumo diz `5 arquivos · o maior com 0:16 + 2 s de cauda`.
5. Confira o `Reunir num .zip`: ele ligou sozinho ao tocar em `Uma por seção` e diz `Um arquivo só com os 5`.
6. Toque em **Exportar**. A janela mostra `Intervalo 1 de 5: Intro`, depois `Intervalo 2 de 5: Verso`, e assim por diante; o `Renderizando N%` é o da exportação toda. No fim: `Os 5 arquivos (WAV 24 bits) foram reunidos em "Minha Música.zip" em N s. No navegador, o arquivo fica nos downloads.` (no Android abre uma janela `Salvar` só, para o zip).
7. Abra o zip: cinco WAV, `Minha Música-Intro-1.wav` a `Minha Música-Final-5.wav`. Cada um vai do começo da seção ao fim dela mais 2 s de cauda: os de 8 s ficam com 10 s (cerca de 2,9 MB em 24 bits a 48 kHz) e os de 16 s com 18 s (cerca de 5,2 MB); o zip inteiro, cerca de 21 MB. Mande ao mixer e avise que as seções **não** foram normalizadas: o nível relativo entre elas é o da música.

### Cenário 2: só o refrão, em MP3, para uma prévia

1. Na régua, clique com o botão direito (toque longo no celular) na bandeirinha `Refrão` e escolha **Exportar esta seção…**.
2. A janela abre em `Entre marcadores`, com **De** em `Refrão · compasso 13` e **Até** em `Ponte · compasso 21`. O resumo diz `Compassos 13 a 20 · 0:16 + 2 s de cauda`. Esse caminho abre com as opções de fábrica (`WAV 24 bits`, `Cauda` de 2 s), não com as da última exportação.
3. Em `FORMATO`, escolha `MP3 (para compartilhar)` e deixe `192 kbps (CBR)`. A prévia do nome passa a terminar em `.mp3`: `Minha Música-Refrão a Ponte-1.mp3` (o trecho entre dois marcadores leva os dois nomes no `{marcador}`).
4. Se quiser o volume de streaming, ligue `Normalizar o loudness`, deixe `Streaming −14,0` e baixe o teto para −1,5 dBTP (folga para o MP3, como no [guia de compartilhar](exportar-para-compartilhar.md#cenário-3-o-master-final-em-wav-24-bits-e-mp3-320)). Um trecho de 18 s já é longo o bastante para o loudness ser medido (o mínimo é 400 ms).
5. Em `Artista (opcional)`, `Fulana`, se quiser o nome nos metadados e no arquivo.
6. **Exportar** (precisa de conta e de rede). Acompanhe `Enviando ao servidor…` e `Compactando no servidor N%…`. O arquivo sai como `Fulana - Minha Música-Refrão a Ponte-1.mp3`, com cerca de 0,43 MB (18 s a 192 kbps).

### Cenário 3: stems de três faixas, com a cauda do reverb

1. **Exportar**, `INTERVALO` em `Música inteira`, `FORMATO` em `WAV 32 bits float`, `Normalizar` e `Normalizar o loudness` desligados (assim o balanço entre os stems se mantém).
2. Abra o bloco **Faixas** (`Todas (7)`). Selecione `Voz` na linha do tempo antes de abrir a janela, se quiser o atalho: **Só a selecionada** deixa só ela marcada. Toque nos chips `Guitarra` e `Retorno reverb`. O bloco passa a dizer `3 de 7`.
3. Ligue **Stems**. Ponha a **Cauda** em 6 s: o reverb do retorno precisa desse tempo para terminar.
4. Ligue `Reunir num .zip` (legenda `Um arquivo só com os 4 (no máximo: faixa sem som não gera stem)`). O resumo diz `Compassos 1 a 32 · 1:04 + 6 s de cauda`.
5. **Exportar**. O resultado é `Minha Música.zip` com `Minha Música.wav` (a mixagem só de `Voz`, `Guitarra` e do retorno que elas alimentam, com o master) e um stem por faixa marcada, na ordem das faixas do projeto: `Minha Música - Guitarra.wav`, `Minha Música - Voz.wav` e `Minha Música - Retorno reverb.wav` (a ordem real depende de onde estão as faixas). Cada arquivo tem 1:04 + 6 s = 70 s, cerca de 27 MB em 32 bits float a 48 kHz, o zip cerca de 108 MB.
6. Para remontar no outro programa, use o stem do retorno **junto** dos da `Voz` e da `Guitarra`: o stem de cada faixa sai **sem** o retorno (o envio vai para o barramento). Se o reverb fosse um efeito na própria faixa, a cauda já estaria no stem dela.

## Variações

- **Seções × stems.** Com `Uma por seção`, `Stems` ligado e as mesmas três faixas em `Faixas`, cada seção ganha a mixagem e 3 stems: 5 × 4 = 20 arquivos no zip, nomeados `Minha Música-Refrão-3 - Voz.wav`. O resumo do zip diz `Um arquivo só com os 20 (no máximo: …)`. Sem o zip seriam 20 downloads.
- **Só algumas seções.** Toque em **Nenhuma** e marque `Verso` e `Refrão`: os arquivos saem `Minha Música-Verso-1.wav` e `Minha Música-Refrão-2.wav` (o `{n}` conta só as marcadas).
- **Outro modelo de nome.** `{n} {marcador}` dá `1 Intro.wav`, `2 Verso.wav`… (com 10 ou mais seções o `{n}` ganha zeros: `01`). `{marcador} ({projeto})` dá `Refrão (Minha Música).wav`. `/` no modelo vira `_`: não cria pasta, nem dentro do zip.
- **Nome só com o marcador no refrão.** Em `Uma por seção`, **Nenhuma** e só `Refrão` marcada: `Minha Música-Refrão-1.wav` (sem o `a Ponte` do `Entre marcadores`).
- **Um trecho qualquer.** `Entre marcadores` com **De** `Verso · compasso 5` e **Até** `Ponte · compasso 21`: um arquivo só, `Minha Música-Verso a Ponte-1.wav`, dos compassos 5 a 20.
- **Zip de MP3 ou FLAC.** Vale o mesmo, mas cada arquivo passa pelo servidor, um de cada vez (5 seções são 5 conversões em fila), e o zip só sai no fim. Se a conversão falha, a janela diz `Nada foi salvo ainda: os arquivos ficam prontos para o .zip…` e **Exportar em WAV mesmo assim** põe os que faltam no zip em WAV.
- **Cada seção no alvo de loudness.** Se a entrega é cada seção como faixa independente (por exemplo, prévias de 15 s), `Normalizar o loudness` por seção faz sentido; ver o aviso em "Por que funciona".

## Por que funciona

- **A janela e o render leem o mesmo plano.** O que a prévia de nome e o contador mostram é o que `planExport` entrega ao render: a lista de intervalos com os nomes já limpos e sem colisão. Por isso o nome da prévia é o do arquivo (menos o `<artista> - ` que o servidor põe na frente em MP3 e FLAC).
- **Uma seção é um render à parte.** Cada intervalo é renderizado do começo ao fim dele e mais a `Cauda`: o arquivo termina com o reverb e o delay do que tocava, mas não com o que a seção seguinte toca. Clipes que atravessam o fim são cortados ali, com o fade curto de sempre `(dedução do código; não ouvido)`.
- **Escolher faixas é pôr as outras em silêncio pelo solo.** A mixagem das faixas marcadas é o solo delas, então o retorno que elas alimentam continua soando (as regras do [mixer](../manual/06-mixer.md#solo-e-mudo)) e o master também; o mudo do projeto continua valendo. Marcar só um barramento deixa só ele soar, e como os envios das faixas em silêncio são cortados, a mixagem provavelmente sai muda `(dedução; não visto)`.
- **Loudness por arquivo nivela as seções.** Cada mixagem é medida e ganha o **seu** ganho até o alvo: um `Intro` de 8 s baixo sobe ao mesmo `I` do `Refrão`. Para seções que o receptor vai colar de volta, entregue sem normalizar (cenário 1) ou normalize a música inteira antes e exporte sem normalizar.
- **O zip reúne no fim, e por isso cancelar não salva nada.** Os arquivos ficam na memória do aparelho (somados ao zip montado) até o último; é o preço de entregar uma coisa só. Sem zip, o que já saiu antes do cancelamento continua nos downloads.
- **Nome e zip sem surpresa.** Nomes iguais (sem distinguir maiúsculas) ganham ` (2)`, nomes que o Windows não aceita ganham um `_` na frente, e o zip repete a limpeza para o caso de dois stems de faixas com o mesmo nome.

## Se der errado

| Sintoma | Causa provável | O que fazer |
|---|---|---|
| `Entre marcadores` e `Uma por seção` apagados (tooltip `Ponha marcadores na régua…`) | Não há marcadores (ou todos estão no fim da música ou depois dele) | Crie marcadores (`Shift+M`) antes do fim do último clipe |
| `Não há o que exportar: Nenhuma seção escolhida: marque ao menos uma.` | Todas as caixas desmarcadas | **Todas**, ou marque as seções |
| `Não há o que exportar: Nenhuma faixa escolhida: marque ao menos uma faixa para exportar.` | Nenhum chip de **Faixas** marcado | **Todas**, ou marque uma faixa |
| `Os dois marcadores estão no mesmo ponto: não há trecho entre eles.` | **De** e **Até** no mesmo marcador (ou em dois na mesma batida) | Troque um deles |
| `Não há nada para exportar nesse trecho: ele começa depois do fim da música.` | O trecho começa depois do último clipe (ou tem duração zero, como `Início do projeto` até um marcador na batida 0) | Escolha outro trecho |
| `Uma seção sem som ficou de fora.` (ou `N seções sem som ficaram de fora.`) | Nada toca naquela seção nas faixas marcadas | Confira as faixas em **Faixas** e o mudo; o `{n}` do arquivo seguinte não muda |
| Mixagem muda ou sem o reverb | Só um barramento marcado, ou o retorno não foi marcado e o envio não chega | Marque também as faixas que o alimentam; para ter o reverb separado, marque o retorno e ligue `Stems` |
| Uma seção do meio sai mais alta que o normal | `Normalizar o loudness` ou `Normalizar` ligado: cada arquivo vai ao alvo por conta própria | Desligue as duas normalizações |
| `O loudness foi normalizado em cada um dos N arquivos.` e caixas `<nome>.wav: …` | O teto de true peak segurou o ganho, ou a seção é curta demais para medir | Leia cada frase; ver [08, Normalizar o loudness](../manual/08-exportacao.md#normalizar-o-loudness) |
| Cancelei e não saiu nada | Com `Reunir num .zip`, nada é salvo antes do fim | Exporte de novo; sem zip, o que já saiu fica (aviso `Exportação cancelada no meio: …`) |
| `Exportação cancelada: você não escolheu onde salvar "Minha Música.zip".` | No Android, a janela `Salvar` foi fechada | **Voltar às opções** (refaz o render de tudo) |
| Janela `Não deu para compactar` com o zip ligado | MP3 ou FLAC sem conta, sem rede ou com erro do servidor | **Exportar em WAV mesmo assim** (põe os que faltam no zip em `.wav`) ou **Voltar às opções** |
| Resultado `Os 1 arquivos (…) foram reunidos em "….zip"` (ou `Os 0 arquivos`) | Só sobrou 1 (ou nenhum) arquivo depois de pular seções sem som e stems mudos; o zip sai mesmo assim `(lido do código; não reproduzido)` | Confira as faixas e as seções; com 0 nada foi salvo |
| Muitos downloads seguidos | Sem `Reunir num .zip` | Ligue o zip |
| Ao abrir pelo menu do marcador a exportação falha com `Pare a gravação antes de exportar.` | O item do menu abre a janela mesmo gravando (o botão **Exportar** da barra fica desligado) | Pare a gravação e exporte de novo |
| O nome do arquivo sem o `a Ponte` que eu queria | **Exportar esta seção…** usa `Entre marcadores`, cujo `{marcador}` é `<início> a <fim>` | Use `Uma por seção` com só aquela seção marcada, ou mude o modelo |
| Falhas de conta, rede, 30 minutos por arquivo, 512 MB no envio | As de FLAC e MP3 | [Exportar para compartilhar, Se der errado](exportar-para-compartilhar.md#se-der-errado) |
