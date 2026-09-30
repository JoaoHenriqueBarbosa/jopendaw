# Exportação e congelamento

> Como transformar o projeto em arquivos WAV (a música inteira e, se quiser, uma faixa por arquivo), como levar a mixagem a um volume-alvo em LUFS (streaming, podcast, rádio e TV) e como congelar uma faixa em áudio para aliviar o projeto ou fixar um som.

![Diálogo Exportar áudio: intervalo, formato, taxa, Stems, Normalizar, Normalizar o loudness e Cauda.](../img/exportar-audio.jpg)

*Diálogo Exportar áudio: intervalo, formato, taxa, Stems, Normalizar, Normalizar o loudness e Cauda.*

![Com Normalizar o loudness ligado aparecem os alvos (Streaming, Podcast, Broadcast, Personalizado) e o teto de true peak.](../img/exportar-loudness.jpg)

*Com Normalizar o loudness ligado aparecem os alvos (Streaming, Podcast, Broadcast, Personalizado) e o teto de true peak.*

## Onde fica

- **Exportar:** botão **Exportar** (ícone de disquete com seta) na barra do transporte, à direita dos painéis e das entradas de notas. Tooltip: `Exportar a música (e as faixas separadas) em WAV`. Em barra estreita ou no celular mostra só o ícone. Não tem atalho de teclado. A mesma janela leva ao arquivo do projeto (`.jopendaw`): botão `Projeto inteiro (.jopendaw)…` no rodapé, descrito na tabela abaixo.
- **Congelar:** menu de três pontos (**Opções da faixa**) no cabeçalho de cada faixa, item **Congelar em áudio**.
- Os dois rodam **fora de tempo real**, em um motor separado e sem tocar: não é preciso reproduzir a música, e o render é mais rápido do que tocar (não há medida documentada de quanto, `(não confirmado)`).

## Controles

### Janela Exportar áudio

Abre ao tocar em **Exportar**. Enquanto o projeto está gravando ou ocupado (importando, congelando), o botão fica desligado (`Pare a gravação para exportar`).

| Controle (rótulo exato) | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| **INTERVALO** > **Música inteira** | Exporta do compasso 1 (batida 0) até o fim do último clipe (de áudio ou de notas), mais a cauda. | Padrão. | Começa sempre em 0, mesmo que o primeiro clipe entre depois (o silêncio inicial vai junto). |
| **INTERVALO** > **Região do loop** | Exporta só a região marcada na régua. Funciona com o loop desligado, desde que a região exista (mais de 0,01 batida). Tooltip: os compassos da região, por exemplo `Compassos 5 a 8`; sem região, `Marque uma região arrastando na régua para exportar só ela` e a opção fica desligada. | | Se a região sumiu desde a última exportação, volta para **Música inteira**. |
| Linha de resumo (texto pequeno) | Mostra `Compassos 1 a 8 · 0:16` (ou `Compasso 3`), com ` + 2 s de cauda` quando a cauda é maior que zero. Sem nada para exportar mostra `O projeto ainda não tem clipes.` ou `A região do loop está vazia.` | | |
| **FORMATO** (lista) | Profundidade do WAV. Veja a tabela abaixo. | `WAV 24 bits` (padrão) | O texto embaixo da lista explica a escolha. |
| **TAXA DE AMOSTRAGEM** (lista) | Taxa do arquivo. O render já é feito nessa taxa (não é reamostrado depois). | `A do aparelho (48 kHz)` (padrão; o número é a taxa real do aparelho), `44,1 kHz`, `48 kHz`, `88,2 kHz`, `96 kHz` (a que for igual à do aparelho não repete). | Taxa maior deixa o arquivo e o render proporcionalmente maiores. |
| **Stems** (interruptor) | Além da mixagem, gera um arquivo por faixa. Legenda: `Um arquivo por faixa, além da mixagem` (ou `Um arquivo da faixa, além da mixagem` se só há uma faixa com clipes). | Desligado. | Ver a seção Stems. |
| **Normalizar** (interruptor) | Leva o pico de cada arquivo a −1 dBFS. Legenda: `Sobe (ou desce) tudo até o pico ficar em −1 dBFS`. | Desligado. | Vale para cada arquivo separadamente. Ligar este desliga o `Normalizar o loudness` (e o contrário): são pedidos contrários. |
| **Normalizar o loudness** (interruptor) | Leva a mixagem inteira ao volume percebido do alvo, em LUFS, sem passar do teto de true peak. Legenda: `Leva a mixagem inteira ao volume percebido do alvo (LUFS), sem passar do teto de pico`. Ao ligar, abrem as quatro linhas abaixo. | Desligado. | Ver a seção Normalizar o loudness. |
| Chips de alvo (com o loudness ligado): **Streaming −14,0**, **Podcast −16,0**, **Broadcast −23,0**, **Personalizado** | Escolhe o loudness integrado que a mixagem deve ter. O texto embaixo diz para quê: `Spotify, YouTube, Apple Music.`, `podcasts e vídeos.`, `EBU R128, rádio e TV.` | Padrão **Streaming** (−14 LUFS). | Um chip só fica marcado por vez. |
| **Alvo** (controle deslizante, só com **Personalizado**; valor à direita, ex.: `−14,0 LUFS`) | O alvo livre. Texto: `Alvo de −14,0 LUFS integrado.` | −40 a 0 LUFS, passo de 0,5, começa em −14,0. | Escolher um chip pré-definido depois não apaga o valor do **Alvo**: ele volta se você retornar a **Personalizado**. |
| **Teto de true peak** (controle deslizante, valor à direita, ex.: `−1,0 dBTP`) | O maior true peak que o arquivo pode ter depois do ganho. Se subir até o alvo passaria disso, o ganho para no teto e o volume fica abaixo do alvo. Texto: `Se subir até o alvo passaria do teto, o ganho para no teto e o volume fica abaixo do alvo: a janela do resultado avisa.` | −10 a 0 dBTP, passo de 0,5, padrão **−1,0 dBTP**. | −1 dBTP é o que serviços de streaming pedem para não estourar na recodificação. |
| **Stems com o mesmo ganho** (interruptor; só aparece com **Stems** ligado e o loudness ligado). Legenda: `Sem isto os stems saem como renderizados, sem normalização` | Aplica a cada stem o mesmo ganho, em dB, que a mixagem recebeu, mantendo o equilíbrio entre eles. | Desligado. | Ver Stems, abaixo. |
| **Cauda** (controle deslizante, com o valor à direita) | Segundos extras depois do fim, para o reverb, o delay e a soltura das notas terminarem. Texto: `Tempo depois do fim para o reverb, o delay e a soltura das notas terminarem.` | 0 a 10 s, passo de 0,5 s, padrão 2 s. | Vale também para os stems e para o intervalo `Região do loop`. |
| Aviso vermelho | `Não há o que exportar: grave, importe ou desenhe um clipe primeiro.` (música inteira) ou `Não há o que exportar: a região do loop não tem duração.` | | Aparece com o intervalo vazio. |
| **Projeto inteiro (.jopendaw)…** (botão de texto com ícone de caixa, no rodapé, à esquerda de **Cancelar**) | Troca o WAV pelo arquivo do projeto editável: fecha esta janela sem exportar áudio e abre a janela `Exportar projeto` (o documento como está na tela e os áudios, num zip). Ver [Projeto em arquivo](01-projetos-modelos-conta.md#projeto-em-arquivo-jopendaw). | | Não guarda as opções da tela como "últimas usadas": só o `Exportar` guarda. |
| **Cancelar** | Fecha sem exportar. | | |
| **Exportar** (com ícone) | Começa o render. Desligado com o intervalo vazio. | | |

As últimas opções escolhidas (inclusive alvo, teto e stems com o mesmo ganho) ficam guardadas até você fechar ou recarregar o app: a próxima exportação da sessão já abre com elas.

#### Formatos

| Item da lista | Codificação | Texto de ajuda na janela | Tamanho aproximado (estéreo a 48 kHz) |
|---|---|---|---|
| **WAV 16 bits** | Inteiro de 16 bits, com dither TPDF (ruído triangular de ±1 LSB) | `Qualidade de CD, o menor arquivo. Para ouvir e publicar.` | 11,5 MB por minuto |
| **WAV 24 bits** | Inteiro de 24 bits, com dither TPDF | `O padrão de estúdio: folga para masterizar depois.` | 17,3 MB por minuto |
| **WAV 32 bits float** | Ponto flutuante de 32 bits (formato IEEE float, com o bloco `fact`), sem dither e sem teto | `Sem perda nenhuma, nem acima de 0 dB. Para levar a outro programa.` | 23,0 MB por minuto |

Nos formatos de 16 e 24 bits, o que passar de 0 dBFS é cortado (limitado a ±1). O tamanho dobra a 96 kHz. O WAV tem limite de 4 GB por arquivo: passando disso a exportação falha com `O arquivo passaria de 4 GB, o limite do WAV: exporte um trecho menor ou em 16 bits.`

### Janela de progresso (Exportando…)

Abre sozinha depois de **Exportar** e não fecha por fora (clicar fora ou o botão voltar do celular não a fecha enquanto trabalha).

| Elemento | O que mostra |
|---|---|
| Título **Exportando…** | Renderizando. |
| Barra de progresso e texto | `Preparando…` até o primeiro aviso; depois `Renderizando N%`; no fim `Salvando o arquivo…`. O render ocupa até 95% da barra; o resto é converter para WAV e entregar o arquivo. Com **Normalizar o loudness**, dos 95% aos 99% o texto é `Medindo o loudness…` (a mixagem é medida, ganha o ganho e é medida de novo). |
| Texto fixo | `O render roda mais rápido que tocar, no próprio aparelho. Deixe esta aba aberta até terminar.` |
| **Cancelar** | Interrompe o render e fecha. Vira `Cancelando…` e fica desligado depois de 100%. Não salva o lote que estava rodando (lotes anteriores já entregues ficam). |
| Título **Exportação concluída** | `A mixagem foi salva (WAV 24 bits) em N s. No navegador, o arquivo fica nos downloads.` Com stems: `A mixagem e os stems foram salvos (...) em N s. ...`. Botão **Fechar**. |
| Frase do loudness (só com **Normalizar o loudness**) | Logo abaixo da mensagem, diz o que a normalização fez e o que o arquivo mediu de verdade, por exemplo `A mixagem subiu 4,0 dB até o alvo e mediu −14,0 LUFS · −2,0 dBTP.` Se o ganho ficou abaixo de 0,05 dB (o arquivo já estava no alvo), a frase é `A mixagem já estava no alvo e mediu −14,0 LUFS · −1,6 dBTP.`, sem repetir a menção ao alvo. Quando o teto segurou o ganho, ou não deu para medir, a frase vem em aviso (caixa destacada). Detalhes na seção Normalizar o loudness. |
| Aviso no resultado | Se algum áudio do projeto não está neste aparelho: `Exportado sem um áudio que não está neste aparelho.` (ou `N áudios que não estão`). O arquivo sai sem esses clipes. |
| Título **A exportação falhou** | A mensagem do erro. Botões **Fechar** e **Voltar às opções** (reabre a janela de opções com as mesmas escolhas). |

Erros de exportação que você pode ver: `O projeto está vazio: não há nada para exportar.`, `A região do loop está vazia: marque o loop antes de exportar.`, `Pare a gravação antes de exportar.`, `Espere o render em andamento terminar antes de exportar.`, `A exportação não terminou: ...` (com o motivo, por exemplo falta de memória) e o do limite de 4 GB.

## O que entra no arquivo

O render aplica ao motor as mesmas chamadas do projeto e processa tudo até o fim, sem esperar o relógio:

- **Entra:** todas as faixas de áudio (com posição, corte, fades, ganho, warp, altura e inversão) e de instrumento (sintetizador, bateria, sampler, FM, wavetable), o volume, o pan, o mudo e o solo de cada faixa, os efeitos de cada faixa, os envios e os barramentos, o volume, o pan e os efeitos do master, **toda a automação** (de faixas, de efeitos e do master) e o limitador de segurança do master.
- **Não entra:** o metrônomo, o loop (o arquivo é linear, do começo ao fim), a entrada do microfone e o monitoramento, notas tocadas ao vivo.
- **Warp pendente:** se algum clipe ainda está processando o warp, a barra mostra `Processando o warp…` e a exportação espera terminar.
- **Fim do trecho:** clipes que atravessam o fim terminam ali (com um fade de 10 ms); notas que atravessam terminam com a soltura do instrumento; a cauda deixa soar o que já estava tocando (reverb, delay, releases) e a automação continua valendo nela. Nada novo começa depois do fim.
- **Limitador do master:** a mixagem passa pelo limitador de segurança do motor (teto de −0,3 dBFS, antecipação de 1,5 ms, liberação de 80 ms). Por isso, sem normalização, a mixagem não passa de −0,3 dBFS em nenhum formato, nem em 32 bits float.
- **Ganho final (opcional):** com **Normalizar** ou **Normalizar o loudness**, um ganho fixo é aplicado ao arquivo **depois** do render, portanto depois do limitador do master. O primeiro leva o pico de amostra a −1 dBFS; o segundo leva o loudness integrado ao alvo (seção abaixo). Nenhum dos dois é compressor nem limitador: só multiplicam todas as amostras pelo mesmo número.
- **Estéreo:** todos os arquivos saem estéreo (2 canais).

### Stems

Com **Stems** ligado, saem a mixagem e um arquivo por faixa, na ordem das faixas. Cada stem é a saída da faixa **depois do fader, do pan, do mudo e da porta do solo** (a mesma posição dos medidores), com os efeitos da faixa, mas **sem a cadeia do master e sem o limitador**. Consequências:

- A soma dos stems não é igual à mixagem: faltam os efeitos e o limitador do master. Um barramento gera o próprio stem (com o que recebeu).
- Faixa que não soa nada no trecho (vazia, muda, calada pelo solo de outra) é **pulada**: não gera arquivo de silêncio.
- Stems podem passar de 0 dB. Em 16 e 24 bits, o excesso é cortado; em 32 bits float, vai inteiro.
- Com **Normalizar**, cada stem é levado a −1 dBFS separadamente, então o equilíbrio entre eles muda. Para levar os stems a outro programa mantendo o balanço, deixe **Normalizar** desligado e use **WAV 32 bits float**.
- Com **Normalizar o loudness**, os stems só são mexidos se **Stems com o mesmo ganho** estiver ligado; então cada um recebe o mesmo ganho em dB que a mixagem recebeu, e o equilíbrio entre eles se mantém. Sem essa opção os stems saem como renderizados (também não recebem o `Normalizar` de pico). O teto de true peak vale para a mixagem, não para os stems: um stem que já era alto pode passar de 0 dBFS com o ganho e, em 16 e 24 bits, é cortado.

## Normalizar o loudness

Serve para entregar a música no volume que a plataforma espera, sem ouvir e ajustar de tentativa em tentativa. O medidor ao vivo do master (`M`, `S`, `I`, `TP`) está em [06b](06b-analisador-e-medidores.md); aqui o mesmo cálculo (BS.1770-4 / EBU R128) roda sobre o arquivo já renderizado.

**Como funciona.**

1. O render da mixagem termina (com toda a cadeia do master e o limitador de segurança).
2. O app mede o loudness integrado (`I`, com os gates de −70 LUFS e de 10 LU) e o true peak dessa mixagem.
3. O ganho é `alvo − I medido`, limitado a ±40 dB. Se `true peak medido + ganho` passaria do **Teto de true peak**, o ganho vira `teto − true peak medido`: o arquivo fica **abaixo do alvo**, mas dentro do teto.
4. Todas as amostras são multiplicadas por esse ganho (o mesmo do começo ao fim do arquivo: a dinâmica da música não muda).
5. O arquivo resultante é medido de novo, e o que ele mediu de verdade vai para a janela do resultado.

Exemplos com o teto padrão (−1,0 dBTP) e o alvo **Streaming** (−14 LUFS):

| A mixagem mediu (`I` · true peak) | Ganho pedido | Ganho aplicado | Arquivo final | Frase no resultado |
|---|---|---|---|---|
| −18,0 LUFS · −6,0 dBTP | +4,0 dB | +4,0 dB | −14,0 LUFS · −2,0 dBTP | `A mixagem subiu 4,0 dB até o alvo e mediu −14,0 LUFS · −2,0 dBTP.` |
| −18,0 LUFS · −3,0 dBTP | +4,0 dB | +2,0 dB (o teto segurou) | −16,0 LUFS · −1,0 dBTP | `A mixagem subiu 2,0 dB e ficou em −16,0 LUFS · −1,0 dBTP, abaixo dos −14,0 LUFS pedidos: o teto de −1,0 dBTP não deixou subir mais sem estourar.` (em aviso) |
| −9,0 LUFS · −0,4 dBTP | −5,0 dB | −5,0 dB | −14,0 LUFS · −5,4 dBTP | `A mixagem desceu 5,0 dB até o alvo e mediu −14,0 LUFS · −5,4 dBTP.` |
| −13,5 LUFS · −0,3 dBTP | −0,5 dB | −0,7 dB (o teto segurou) | −14,2 LUFS · −1,0 dBTP | aviso, como na segunda linha |
| −14,0 LUFS · −3,0 dBTP | 0,0 dB | 0,0 dB (menos de 0,05 dB) | −14,0 LUFS · −3,0 dBTP | `A mixagem já estava no alvo e mediu −14,0 LUFS · −3,0 dBTP.` |

Regra de bolso: chegar ao alvo com o teto de −1 dBTP exige que a diferença entre o true peak e o `I` da mixagem (a dinâmica de pico) seja de no máximo `−1 − alvo` dB, isto é, **13 dB para −14 LUFS**, **15 dB para −16 LUFS** e **22 dB para −23 LUFS**. Uma mixagem mais "espetada" que isso não chega ao alvo só com ganho; para subir o `I` sem passar do teto, ponha um `Limitador` no master antes (ver [guia loudness e master](../guias/loudness-e-master.md)).

**Quando não mede.** Se a mixagem tem menos de 400 ms, é silêncio, ou fica toda abaixo de −70 LUFS, não há `I` para comparar: nada é normalizado e o resultado avisa `Não deu para medir o loudness (o trecho é curto demais, mudo ou muito baixo): a mixagem foi exportada sem normalizar.` Os stems também saem sem ganho nesse caso. A região do loop curta demais cai aqui.

**O que cada opção decide.**

| Opção | Efeito | Limites |
|---|---|---|
| Alvo `Streaming` | −14 LUFS | Fixo |
| Alvo `Podcast` | −16 LUFS | Fixo |
| Alvo `Broadcast` | −23 LUFS (EBU R128) | Fixo |
| Alvo `Personalizado` | O valor do controle **Alvo** | −40 a 0 LUFS, passo 0,5 |
| **Teto de true peak** | O true peak máximo permitido depois do ganho | −10 a 0 dBTP, passo 0,5, padrão −1,0 |
| **Stems com o mesmo ganho** | Cada stem recebe o ganho da mixagem, em dB | Só com **Stems** ligado; só se a mixagem foi medida e o ganho não é 0 |

**Cancelar** durante `Medindo o loudness…` interrompe sem salvar a mixagem (os arquivos de lotes anteriores já entregues ficam).

## Nomes dos arquivos

| Arquivo | Nome |
|---|---|
| Mixagem | `<nome do projeto>.wav` |
| Stem | `<nome do projeto> - <nome da faixa>.wav` |
| Stem com nome repetido | `<nome do projeto> - <nome da faixa> (2).wav`, `(3)`, … (a comparação ignora maiúsculas) |

Os nomes são limpos para os sistemas de arquivos: `\ / : * ? " < > |` e caracteres de controle viram `_`, espaços seguidos viram um, pontos e espaços no fim saem, e cada parte é cortada em 80 caracteres. Projeto sem nome vira `jopendaw`; faixa sem nome vira `Faixa N` (N é a posição da faixa, contando de 1).

- **No navegador**, cada arquivo é um download (`<a download>`); fica na pasta de downloads. Com stems são vários downloads seguidos; o navegador pode pedir permissão para baixar vários arquivos (`(não confirmado)`).
- **No Android**, cada arquivo abre o seletor **Salvar como** do sistema, com o título `Salvar <nome>` (o mesmo seletor para cada stem: com 8 faixas soando são até 9 janelas). Se o aparelho não tem o app de arquivos, abre a folha de compartilhar. Cancelar uma janela não é erro.

## Memória, lotes e limites

- **Web:** o render roda num Web Worker (`engine/render-worker.js`) com o mesmo motor em WebAssembly do áudio; a tela não trava. **Android:** roda num isolado (thread) com o motor nativo, a mesma biblioteca do áudio. Sem Web Worker o navegador responde `Este navegador não consegue renderizar em segundo plano (sem Web Worker).`
- O render guarda as saídas em memória (2 canais de 32 bits por arquivo). O app divide as saídas em **lotes** de até 384 MB e faz um render completo por lote: um projeto longo com muitos stems demora mais porque repete o render a cada lote. Um exemplo: 4 minutos a 48 kHz ocupam cerca de 92 MB por arquivo, então cabem 4 arquivos por lote e 12 stems mais a mixagem (13 saídas) viram 4 renders.
- **Teto por render:** 4 GiB de saída no navegador (cerca de 186 minutos de estéreo a 48 kHz) e 1,5 GiB no Android (cerca de 68 minutos). Acima disso: `Não há memória para renderizar N min em N saídas. Exporte um trecho menor ou menos faixas separadas.`
- O motor captura no máximo 64 faixas por render, e o app divide os lotes só pela memória; num projeto curto com mais de 64 faixas e Stems ligado, o lote pode passar disso e falhar com `O motor não conseguiu separar a faixa N no render.` `(não confirmado)`
- Um render de cada vez: exportar e congelar não rodam juntos (`Espere o render em andamento terminar antes de exportar.`).

## Congelar uma faixa

**Congelar em áudio** renderiza uma faixa (instrumento, clipes, efeitos e a automação deles) para um clipe de áudio numa faixa nova, e deixa a original muda. Serve para fixar um som, poupar processamento ou levar o resultado para outro trabalho.

### Quando está disponível

O item fica desligado, com o motivo na legenda dele, em três casos: `Barramento não tem som próprio`, `A faixa está vazia` (faixa de áudio sem clipes, ou de instrumento sem nenhuma nota) e `Pare a gravação antes`. Se outro render está rodando, aparece `Espere o render em andamento terminar antes de congelar.`

### Janela de progresso

| Elemento | O que mostra |
|---|---|
| Título `Congelando "nome"` | Em andamento. |
| Texto | `A faixa vira áudio com o instrumento e os efeitos, numa faixa nova logo abaixo; esta fica muda.` |
| Barra e percentual | `Preparando…`, depois `N%`. |
| **Cancelar** | Interrompe e fecha (vira `Cancelando…`). Nada é alterado. |
| Título `Não deu para congelar` | Erro. Botão **Fechar**. Mensagens: `A faixa "nome" não soou nada: nada para congelar.`, `A faixa "nome" foi apagada enquanto congelava.`, `O congelamento não terminou: ...`. |

### O que acontece

1. O render vai do começo do primeiro clipe da faixa ao fim do último, mais uma cauda de até 8 s. A cauda é aparada onde o som cai abaixo de −100 dB (nunca menos que o trecho dos clipes).
2. O render pega a faixa **depois dos efeitos**, com o fader em 0 dB e o pan no centro, sem mudo e sem solo de nenhuma faixa, e sem a automação de volume e de pan (para não aplicá-las duas vezes).
3. O resultado é gravado em WAV 32 bits float na taxa do aparelho, e vira mono se os dois canais são idênticos.
4. Uma **faixa de áudio nova** entra logo abaixo, chamada `<nome> (áudio)`, com a mesma cor, e fica selecionada junto com o clipe. O clipe começa onde começava o primeiro clipe da original e o arquivo aparece como `<nome> (congelada).wav` na lista de áudios do projeto.
5. A faixa nova recebe o **volume, o pan, o mudo, o solo, a saída, os envios e a automação de volume, pan e envios** da original: ela soa na mixagem como a original soava, e o fader continua mexível.
6. A **original fica muda**, com o instrumento, os efeitos e os clipes intactos (é só reativar o M para voltar). Os envios pré-fader dela saem (senão continuariam soando e dobrariam); os pós-fader ficam, e calam junto com o mudo. Um sidechain que a original alimentava continua funcionando.
7. Tudo é **um passo só do desfazer**: Ctrl+Z tira a faixa nova e devolve o som da original.

A faixa congelada não tem instrumento nem efeitos (eles já estão no áudio). Para mudar o som, desfaça o congelamento, ajuste e congele de novo.

## Passo a passo

**Exportar a música em WAV**
1. Confira o fim da música: o intervalo vai até o último clipe. Pare a gravação se estiver gravando.
2. Toque em **Exportar**.
3. Deixe **Música inteira**, **WAV 24 bits**, **A do aparelho**, **Cauda** em 2 s.
4. **Exportar**, espere o `Renderizando N%` e abra o arquivo nos downloads (Android: escolha onde salvar).

**Exportar para streaming a −14 LUFS**
1. Confira antes o `I` e o `TP` no mixer ([06b](06b-analisador-e-medidores.md)): quanto mais perto do alvo o mix já está, menos o ganho mexe.
2. Em **Exportar**, ligue **Normalizar o loudness** (o **Normalizar** de pico desliga sozinho) e deixe o chip **Streaming −14,0** e o **Teto de true peak** em −1,0 dBTP.
3. **WAV 24 bits**, **Cauda** em 2 s, **Exportar**. A barra passa por `Medindo o loudness…` perto do fim.
4. Na janela **Exportação concluída**, leia a frase: `mediu −14,0 LUFS` quer dizer que chegou. Se vier em aviso (`abaixo dos −14,0 LUFS pedidos`), veja o guia [Loudness e master](../guias/loudness-e-master.md).

**Exportar só um trecho para testar**
1. Arraste na régua para marcar o trecho.
2. Em **Exportar**, escolha **Região do loop**; o resumo mostra `Compassos N a M`.
3. Confirme com **Exportar**.

**Exportar stems para outro programa**
1. **Stems** ligado, **Normalizar** desligado, formato **WAV 32 bits float**.
2. **Cauda** de 4 a 6 s se há reverb longo.
3. Exporte; guarde a mixagem e os stems juntos (o nome da faixa fica no arquivo).

**Congelar um sintetizador pesado**
1. No cabeçalho da faixa, abra os três pontos.
2. **Congelar em áudio**; espere o `N%`.
3. A faixa `<nome> (áudio)` aparece embaixo. Se quiser voltar, use Ctrl+Z.

## Combina com

- [Transporte](02-transporte.md): o botão **Exportar** e a região do loop marcada na régua.
- [Projetos, modelos e conta](01-projetos-modelos-conta.md#projeto-em-arquivo-jopendaw): o botão `Projeto inteiro (.jopendaw)…` desta janela, que guarda o projeto editável em vez do som.
- [Timeline e clipes](02b-timeline-e-clipes.md): o menu da faixa (**Congelar em áudio**) e o comprimento do projeto.
- [Mixer](06-mixer.md) e [Painel de efeitos](06c-painel-de-efeitos.md): o que define o som do master e dos stems.
- [Analisador e medidores](06b-analisador-e-medidores.md): as leituras `M`, `S`, `I` e `TP` do master, para conferir o mix antes de normalizar.
- [Guia: loudness e master](../guias/loudness-e-master.md): do nível das faixas ao arquivo entregue no alvo certo.
- [Automação](07-automacao.md): vai inteira para o arquivo.
- [Nuvem e sincronização](01b-nuvem-e-sincronizacao.md): o áudio congelado é um áudio novo do projeto (`(não confirmado)` se conta na cota da nuvem).
- Receitas: pasta [`../guias/`](../guias/).

## Limites e pegadinhas

- **Só WAV.** Não há MP3, FLAC nem AAC na exportação do app. O único outro arquivo que sai desta janela é o do projeto (`Projeto inteiro (.jopendaw)…`), que não é áudio.
- **A mixagem tem teto de −0,3 dBFS** pelo limitador do master, em qualquer formato, quando não há normalização. O texto de ajuda do WAV 32 bits float (`nem acima de 0 dB`) vale para os stems, não para a mixagem. Com **Normalizar o loudness** o teto passa a ser o **Teto de true peak** escolhido (até 0 dBTP).
- **Normalizar** mexe em cada arquivo à parte (mixagem e stems); uma mixagem que já bate no teto é abaixada em cerca de 0,7 dB.
- **Normalizar o loudness é só ganho.** Não comprime nem limita: se o alvo pede mais volume do que o teto permite, o arquivo sai abaixo do alvo (com aviso), e o remédio é limitar no master antes de exportar.
- **O `I` do arquivo pode diferir do que o mixer mostrou.** O mixer mede a saída ao vivo (com metrônomo e entrada monitorada, tudo desde o último `Zerar`); a exportação mede só a mixagem. Vale o número da janela do resultado.
- **Uma mixagem que já está perto do limitador de segurança desce.** Com true peak em torno de −0,3 dBTP e o teto padrão de −1,0, o ganho nunca é maior que −0,7 dB, mesmo que o alvo peça menos.
- **Loudness só na mixagem.** Os stems só recebem o ganho (opcional); nenhum é medido.
- **O fim é o último clipe.** Automação, marcadores e loop depois dele não estendem o arquivo; use **Cauda** para o que precisa soar depois.
- **Áudios que faltam** (`áudio fora deste aparelho`) saem como silêncio, com o aviso ao final. Abra o projeto no aparelho que tem os arquivos ou sincronize antes.
- **Deixe a aba aberta** durante o render no navegador; feche o app e o render some sem salvar.
- **Um render por vez**, e não é possível exportar nem congelar gravando.
- **Congelar não aceita barramento.** O som de um barramento depende das outras faixas; para fixá-lo, exporte a faixa como stem.
- **A faixa congelada perde a edição de notas:** o clipe dela é áudio. A original continua com as notas.
- **Web e Android:** mesmo motor e mesmas opções; muda só a entrega do arquivo (download versus janela de salvar) e o teto de memória (4 GiB versus 1,5 GiB).

## Atalhos

Nenhum atalho de teclado abre a exportação ou o congelamento. A janela de progresso não fecha por fora (nem com Esc) enquanto trabalha; só o botão **Cancelar** a interrompe.
