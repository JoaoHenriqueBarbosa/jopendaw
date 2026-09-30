# Congelar faixa e converter em áudio

> Fixar o som de uma faixa (instrumento, notas e efeitos) num áudio renderizado, para poupar processamento ou travar um timbre, e poder voltar atrás com `Descongelar`; ou trocar o conteúdo por um clipe de áudio de vez com `Converter em áudio…`. Vem da fase 20 (`3bd56fd`).

## Onde fica

Tudo está no menu de três pontos de cada faixa (tooltip `Opções da faixa`, no cabeçalho da faixa na timeline, no computador e no celular; ver [Timeline e clipes, Menu Opções da faixa](02b-timeline-e-clipes.md#menu-opções-da-faixa-três-pontos)). Os itens, na ordem em que aparecem (logo depois de `Duplicar a faixa`):

1. `Congelar faixa…` (se a faixa não está congelada) ou `Descongelar` (se está).
2. `Converter em áudio…`.
3. `Renderizar em faixa nova`.

Não há botão na barra, atalho de teclado nem item no mixer: só esse menu. O estado "congelada" aparece no cabeçalho da faixa (ícone de floco) e na raia (faixa azul), descritos abaixo.

## Para que serve

- **Poupar CPU.** Uma faixa congelada toca um áudio pronto: o motor não gera mais as notas do instrumento nem roda a cadeia de efeitos dela. O `Reverb` (rede de 8 linhas) e a `Distorção` em `4×` são, por construção, os que mais fazem conta ([06d, Latência e custo](06d-efeitos-referencia.md#latência-e-custo-de-cada-efeito)); quanto se economiza **não foi medido** `(não confirmado)`.
- **Travar um som.** Com o timbre aprovado, congelar impede que uma mexida sem querer no instrumento ou num efeito o mude; o conteúdo original continua guardado no projeto.
- **Levar o som pronto a outro aparelho.** O áudio renderizado entra nos áudios do projeto e viaja com ele (nuvem e `.jopendaw`); o outro aparelho toca o mesmo som sem precisar processar o instrumento de novo. Um projeto que depende de um efeito pesado fica mais leve de abrir.
- **Converter em áudio** é para quando você quer mexer no som como áudio (cortar, esticar com warp, fades, `Editar áudio`) e não precisa mais das notas nem dos efeitos.

## Controles

### Itens do menu da faixa

| Item (rótulo exato e legenda) | O que faz | Quando aparece / está habilitado | Dica |
|---|---|---|---|
| `Congelar faixa…` (legenda `Toca o áudio renderizado; o conteúdo fica guardado`) | Abre o diálogo `Congelar "nome"` (abaixo). Confirmando, renderiza a faixa e ela passa a tocar o áudio. | Em faixa de áudio e de instrumento (não em barramento) que **não** está congelada. Desligado, com o motivo na legenda, nas recusas abaixo. | Um passo do desfazer (`Congelar faixa`). |
| `Descongelar` (legenda `Volta o instrumento, as notas e os efeitos`) | Tira o congelamento: a faixa volta a tocar o conteúdo dela, exatamente como está no projeto agora. | Só em faixa congelada. Desligado durante a gravação (sem legenda de motivo). | Um passo do desfazer (`Descongelar faixa`). |
| `Converter em áudio…` (legenda `Troca o conteúdo por um clipe de áudio`) | Abre o diálogo `Converter "nome" em áudio`. Confirmando, o instrumento, as notas e os efeitos saem e a faixa vira uma faixa de áudio com um clipe só. | Em faixa de instrumento (congelada ou não) e em faixa de áudio **congelada**. **Não aparece** em faixa de áudio comum nem em barramento. Desligado, com o motivo na legenda, nas recusas abaixo. | Um passo do desfazer (`Converter em áudio`). Numa faixa já congelada não pergunta a cauda: reaproveita o áudio que ela já tem. |
| `Renderizar em faixa nova` (legenda `Vira uma faixa de áudio nova; esta fica muda`) | O antigo `Congelar em áudio` (até a fase 19): cria uma faixa de áudio nova logo abaixo com o som renderizado e deixa a original muda. Ver [08 Exportação, Renderizar em faixa nova](08-exportacao.md#renderizar-em-faixa-nova-antigo-congelar-em-áudio). | Em toda faixa, desligado em barramento (`Barramento não tem som próprio`), faixa vazia (`A faixa está vazia`), durante a gravação (`Pare a gravação antes`) e em faixa congelada (legenda `Descongele antes`). | Não pergunta a cauda (usa 8 s fixos) e não recusa sidechain. |

### Diálogo `Congelar "nome"` (e `Converter "nome" em áudio`)

Abre ao escolher `Congelar faixa…` ou `Converter em áudio…` (numa faixa não congelada). Fechar sem confirmar (`Cancelar`, ou tocar fora) não faz nada.

| Controle | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| Título | `Congelar "nome"` ou, na conversão, `Converter "nome" em áudio`. | | |
| Texto do congelar | `A faixa passa a tocar o áudio renderizado, com o instrumento e os efeitos. O conteúdo original fica guardado: "Descongelar" devolve tudo. O fader, o pan e os envios continuam vivos.` | | |
| Texto do converter | `O instrumento, as notas e os efeitos da faixa saem e ficam um clipe de áudio só (dá para desfazer). O fader, o pan e os envios continuam.` | | |
| Controle deslizante `Cauda dos efeitos: N s` | Quantos segundos o som da faixa pode continuar depois do fim do último clipe (reverb e delay que passam do fim). Legenda: `Quanto o reverb e o delay podem soar depois do fim do último clipe. O silêncio no fim é aparado.` | **0 a 30 s, de 1 em 1 s, padrão 8 s.** O tooltip do controle mostra `N s`. | É um **máximo**: o silêncio depois do som é aparado, então um valor alto não deixa o arquivo longo à toa. Um valor curto demais **corta seco** a cauda (não há fade). |
| **Cancelar** | Fecha sem renderizar. | | |
| **Congelar** / **Converter** | Começa o render. | | |

> O controlador aceita caudas de 0 a 60 s (`kMaxFreezeTail`), mas o controle do diálogo só vai até 30 s: é o que a interface oferece hoje.

### Janela de progresso

Depois de confirmar, abre uma janela que o render mantém aberta (não fecha por fora, nem com Esc; só o botão a interrompe).

| Elemento | O que mostra |
|---|---|
| Título `Congelando "nome"` (ou `Convertendo "nome"`) | Em andamento. |
| Texto | Congelar: `A faixa é renderizada com o instrumento e os efeitos e passa a tocar o áudio.` Converter: `A faixa é renderizada e vira um clipe de áudio.` (em `Renderizar em faixa nova`: `A faixa vira áudio com o instrumento e os efeitos, numa faixa nova logo abaixo; esta fica muda.`) |
| Barra e percentual | `Preparando…`, depois `N%`. |
| **Cancelar** | Interrompe o render (vira `Cancelando…`). Nada é alterado e não aparece erro. |
| Título `Não deu para congelar` (ou `Não deu para converter`) | Erro. Botão **Fechar**. As mensagens possíveis estão em "Recusas e erros". |

Enquanto a barra do transporte mostra o círculo de ocupado, o texto é `Congelando <nome>…` ou `Convertendo <nome>…`.

### O que a faixa congelada mostra

| Sinal | Onde | O que é |
|---|---|---|
| Ícone de floco azul (14 px), à esquerda do nome | Cabeçalho da faixa (computador e celular). Tooltip: `Congelada: toca o áudio renderizado ("Descongelar" no menu devolve o conteúdo)`. | A faixa está congelada. |
| Faixa azul-gelo translúcida com um floco pequeno no canto de cima à esquerda | Raia da faixa, sobre o trecho que o áudio congelado ocupa (do começo do primeiro clipe ao fim do áudio renderizado, cauda incluída). Não pega cliques. | Onde o som congelado toca. |

Não há indicador no mixer nem no painel de efeitos.

## O que é renderizado e o que fica vivo

O render é o mesmo da exportação (fora de tempo real, sem precisar tocar; [08 Exportação](08-exportacao.md)), da faixa sozinha:

| Entra no áudio congelado | Fica fora e continua vivo na faixa |
|---|---|
| Os clipes de áudio (com warp, fades e ganho) ou as notas, e o instrumento | O **fader** (`Volume` da faixa) |
| Os **efeitos da faixa** (a cadeia de inserts inteira, na ordem) | O **pan** |
| A automação e a modulação do **instrumento** e dos **efeitos** | `M` (mudo) e `S` (solo) |
| | A **saída** da faixa (Master, pasta ou barramento) |
| | Os **envios** (pré e pós-fader) e os barramentos para onde vão |
| | A automação e a modulação de `Volume`, `Pan` e envios |

Como o render pega a faixa com o fader em 0 dB, o pan no centro, sem mudo e sem nenhuma faixa em solo, e sem a automação de volume e pan, o áudio sai "limpo" e você continua mixando: o fader e o pan da faixa congelada atuam **depois** do áudio, como antes. Um envio para o reverb continua mandando o som da faixa para o barramento de reverb; o reverb do barramento **não** entra no áudio (ele não é da faixa). O master também não entra.

O render vai **do começo do primeiro clipe ao fim do último, mais a cauda**; o silêncio depois disso (abaixo de −100 dB) é aparado. O resultado é guardado como WAV de 32 bits float na taxa do motor (mono se os dois canais saem idênticos) e vira um áudio do projeto chamado `<nome da faixa> (congelada).wav` (na conversão de uma faixa não congelada: `<nome da faixa> (convertida).wav`).

Com a faixa congelada, o motor a trata como faixa de áudio com **um** clipe (o áudio renderizado): o instrumento fica calado, as notas não tocam, a cadeia de efeitos da faixa é esvaziada e a automação e modulação de instrumento e efeitos não são enviadas. O instrumento, as notas, os clipes, os efeitos e a automação **continuam no projeto**, sem mudança nenhuma, esperando o `Descongelar`.

## Descongelar

`Descongelar` tira o congelamento e a faixa volta a tocar o conteúdo dela. Como nada foi tocado no congelamento, volta tudo: instrumento, parâmetros, notas, clipes, efeitos e automação. **O que você editou na faixa enquanto ela estava congelada vale agora**: notas movidas, parâmetros do instrumento, efeitos mudados. Durante o congelamento essas edições não soam (a faixa toca o áudio renderizado), mas ficam guardadas.

O áudio renderizado **permanece na lista de áudios do projeto** depois do descongelar (não é apagado): continua indo para a nuvem e para o `.jopendaw` e conta na cota ([Nuvem e sincronização](01b-nuvem-e-sincronizacao.md#cotas-e-limites)). Como o documento ainda o cita, o servidor o trata como em uso e a tela `Conta` não o deixa apagar `(lido do código; não testado)`. Congelar de novo gera outro áudio (se o som for idêntico, o mesmo arquivo, pelo SHA-256).

## Converter em áudio

`Converter em áudio…` é o congelamento **sem volta direta** (mas desfazível): em vez de guardar o conteúdo original ao lado, troca-o pelo áudio.

| Depois de converter | Como fica |
|---|---|
| Tipo da faixa | Vira faixa de **áudio** (`Faixa de áudio`). |
| Conteúdo | Um clipe de áudio só, que começa onde o primeiro clipe começava, com o som renderizado (nome do arquivo `<nome> (convertida).wav`). É um clipe normal: corta, arrasta, tem fades, warp, `Ganho do clipe…`, `Editar áudio`. |
| Saem | O instrumento e os parâmetros dele, o sampler e as zonas, as notas (clipes MIDI), os efeitos da faixa, a monitoração de entrada, e a automação e a modulação do instrumento e dos efeitos. |
| Ficam | Fader, pan, mudo, solo, saída, **envios** (inclusive pré-fader) e a automação e a modulação de volume, pan e envios. |
| Faixa já congelada | Não renderiza de novo nem pergunta a cauda: o áudio congelado vira o clipe (com o mesmo arquivo). |
| Desfazer | `Ctrl+Z` volta tudo de uma vez, inclusive o instrumento (um passo chamado `Converter em áudio`). |

Diferença para o congelar: no congelar o conteúdo original continua no projeto (`Descongelar` o devolve); na conversão ele **sai do projeto** (só o `Ctrl+Z` e o histórico do desfazer o trazem de volta). Diferença para `Renderizar em faixa nova`: a conversão acontece **na própria faixa** (mesmo lugar, mesmo nome, mesmos envios), sem criar faixa nova nem deixar a original muda.

## Renderizar em faixa nova (antigo `Congelar em áudio`)

Até a fase 19 o item se chamava `Congelar em áudio` e fazia outra coisa: criava uma **faixa nova** `<nome> (áudio)` com o som e deixava a original muda. Desde a fase 20 o nome é `Renderizar em faixa nova`, e `Congelar faixa…` passou a congelar **no lugar**. O comportamento do antigo item é o mesmo de antes (8 s de cauda fixos, o volume, o pan e os envios passam para a faixa nova); o detalhe está em [08 Exportação](08-exportacao.md#renderizar-em-faixa-nova-antigo-congelar-em-áudio). Em faixa congelada ele fica desligado (`Descongele antes`).

## Recusas e erros

As recusas de `Congelar faixa…` e `Converter em áudio…` aparecem de duas formas: como **legenda** do item (que fica desligado) e, se o controlador for chamado assim mesmo, como texto `<nome da faixa>: <motivo>.`

| Motivo (legenda do item) | Quando |
|---|---|
| `Barramento não tem som próprio` | A faixa é um barramento. Os itens de congelar e converter nem aparecem; só `Renderizar em faixa nova` fica, desligado, com essa legenda. |
| `Pare a gravação antes` | Há gravação em andamento. |
| `A faixa já está congelada` | Só para o congelar (o item vira `Descongelar`). A conversão de uma faixa congelada não precisa disso. |
| `A faixa está vazia` | Faixa de áudio sem clipes, ou de instrumento sem nenhuma nota nos clipes. (Só vale para quem precisa renderizar: a conversão de uma faixa já congelada não exige conteúdo.) |
| `Um efeito usa o sidechain de "nome": tire a chave antes de congelar` (ou `... de outra faixa: ...`) | Um `Compressor` ou `Gate` da faixa tem como chave (seletor `Sidechain`, grupo `CHAVE`) **outra** faixa; `Própria entrada` (o padrão) não impede. A mensagem diz "congelar" mesmo na conversão. |

Durante o render, na janela de progresso (título `Não deu para congelar` ou `Não deu para converter`):

| Mensagem | Quando |
|---|---|
| `Espere o render em andamento terminar antes de congelar.` (ou `... converter.`) | Já há outro render rodando (exportação, por exemplo). |
| `Pare a gravação antes de congelar.` (ou `... converter.`) | A gravação começou no intervalo. |
| `A faixa "nome" está vazia: nada para congelar.` | O trecho do conteúdo não tem duração. |
| `A faixa "nome" não soou nada: nada para congelar.` | O render saiu em silêncio (faixa muda por dentro: clipes mudos, instrumento sem volume, `Gate` fechado...). |
| `A faixa "nome" foi apagada enquanto congelava.` | Você apagou a faixa durante o render. |
| `A faixa "nome" mudou durante o render: o áudio já nasceria velho. Tente de novo.` | Você editou o som da faixa (tipo ou parâmetros do instrumento, amostra, zonas, clipes, notas ou efeitos) com o render rodando. Mexer no fader, no pan ou em envios durante o render **não** invalida. |
| `O congelamento não terminou: ...` (na conversão, `A conversão não terminou: ...`) | Falha do render (por exemplo, sem memória ou sem suporte no aparelho). |

Em `Descongelar`, durante a gravação o item fica desligado; se for acionado assim mesmo, o aviso é `Pare a gravação para descongelar.`

Cancelar o render não é erro: nada muda.

## Efeito no projeto, na nuvem e nos arquivos

- **Documento.** A faixa congelada ganha um campo `frozen` com o hash do áudio, onde ele começa (em batidas), quanto dura (em segundos, cauda incluída) e a cauda pedida. Um projeto sem faixa congelada sai idêntico ao de antes. O áudio entra também em `samples` (lista de áudios do projeto). Detalhes em [dev/10 App Flutter, Congelar no lugar](../dev/10-app-flutter.md#congelar-no-lugar-e-converter-em-áudio-freezedart).
- **Sincronização.** O áudio congelado sobe à nuvem como qualquer outro áudio (endereçado por SHA-256, antes do documento) e **conta na cota de 4 GB** da conta, e no limite de 512 MB por arquivo ([Nuvem e sincronização](01b-nuvem-e-sincronizacao.md#áudios)). Tamanho: WAV de 32 bits float, cerca de 23 MB por minuto em estéreo a 48 kHz (48.000 × 2 canais × 4 bytes × 60 s; a metade se sai mono). Uma faixa de 4 minutos congelada ocupa cerca de 92 MB, não 5 MB como o som comprimido: congelar muitas faixas longas enche a cota.
- **Arquivo `.jopendaw`.** O áudio congelado vai dentro do pacote, como os outros, e a faixa continua congelada ao importar ([Projetos, `.jopendaw`](01-projetos-modelos-conta.md#projeto-em-arquivo-jopendaw)).
- **Outro aparelho sem o áudio.** Se o áudio congelado não está neste aparelho, a faixa congelada fica **muda** e, diferente dos clipes de áudio comuns, não mostra o aviso `áudio fora deste aparelho` `(lido do código; não testado)`. `Descongelar` devolve o som da faixa.
- **Exportação.** A exportação (WAV, FLAC, MP3 e stems) usa o mesmo render: a faixa congelada sai com o áudio congelado (e o fader, o pan e os envios vivos). O fim do arquivo é o fim do último clipe **do conteúdo** mais a `Cauda` da janela `Exportar áudio` (0 a 10 s, padrão 2 s): o fim do **áudio congelado** não estende o arquivo, então uma cauda congelada de 8 s só sai inteira se a `Cauda` da exportação também cobrir isso `(lido do código)`. O `.mid` leva as notas da faixa de instrumento congelada normalmente (elas seguem no projeto).
- **Desfazer.** `Congelar faixa`, `Descongelar faixa` e `Converter em áudio` são um passo cada no histórico ([Histórico e versões](02d-historico-e-versoes.md)). `Ctrl+Z` logo depois de congelar descongela (testado no Chrome pela sessão de código); refazer volta a congelar. Durante a reprodução congelar e descongelar não param o transporte `(testado só por testes automáticos)`.
- **Duplicar a faixa.** A cópia de uma faixa congelada também é congelada e usa o mesmo áudio (`(testado só por testes automáticos)`).
- **Pastas.** Congelar no lugar não muda a faixa de lugar, então não mexe na pasta. (`Renderizar em faixa nova` cria a faixa nova na mesma pasta.)

## Passo a passo

**1. Congelar um baixo com efeitos pesados e mixar o resto**
1. Numa faixa `Sintetizador` chamada `Baixo`, com notas escritas e, na cadeia, por exemplo um `Compressor`, uma `Distorção` em `4×` e um `Reverb`, confira o som tocando.
2. No cabeçalho do `Baixo`, abra `Opções da faixa` (três pontos) e toque em `Congelar faixa…`.
3. No diálogo `Congelar "Baixo"`, deixe `Cauda dos efeitos: 8 s` (padrão) e toque em **Congelar**. Acompanhe `Preparando…` e o `N%`.
4. Ao fim, o cabeçalho ganha o floco azul e a raia ganha a faixa azul. Toque: o som é o mesmo, vindo do áudio.
5. Continue mixando normalmente: o fader, o pan, `M`, `S` e os envios do `Baixo` seguem valendo. Abra o mixer para ajustar o resto do projeto.

**2. Descongelar para mudar uma nota**
1. Em `Opções da faixa` da faixa congelada, toque em `Descongelar` (ou `Ctrl+Z`, se acabou de congelar).
2. O floco e a faixa azul somem; o instrumento, as notas e os efeitos voltam a tocar.
3. Abra o clipe de notas e mude a nota; se quiser, mexa também no instrumento.
4. Ouça. Quando estiver bom, `Congelar faixa…` de novo. O áudio anterior continua na lista de áudios do projeto e, como o documento ainda o cita, o servidor o considera em uso: ele segue contando na cota e a tela `Conta` não o oferece para apagar `(lido do código; não testado)`.

**3. Converter em áudio para esticar ou cortar**
1. Numa faixa de instrumento com as notas e os efeitos que quer, abra `Opções da faixa` e toque em `Converter em áudio…`.
2. Escolha a `Cauda dos efeitos` (o padrão de 8 s serve para a maioria) e toque em **Converter**.
3. A faixa vira faixa de áudio com um clipe só. Agora use o que é de áudio: corte com `S`, aplique fades, abra [Warp e altura](03b-warp-e-altura.md) para esticar ao andamento, ou [Editar áudio](03e-editar-audio.md).
4. Se errou, `Ctrl+Z` desfaz a conversão inteira e devolve o instrumento. Depois de outras edições, use o [Histórico](02d-historico-e-versoes.md) (passo `Converter em áudio`).

**4. Congelar escolhendo a cauda certa para um reverb**
1. Numa faixa com `Reverb` de `Decaimento` 2,2 s (o padrão), a cauda cai 60 dB em 2,2 s; para chegar perto do silêncio (−100 dB) leva cerca de 100/60 do `Decaimento`, uns 3,7 s `(estimativa feita a partir da definição de RT60, não medida)`.
2. `Congelar faixa…` e coloque `Cauda dos efeitos` em 4 s: o reverb termina natural e o silêncio do fim é aparado.
3. Com um `Reverb` longo (`Catedral`, `Decaimento` 7 s), a estimativa sobe para uns 12 s: coloque de 12 a 15 s. O diálogo vai até 30 s.
4. Com `Congelar` ligado no `Reverb` (o preset `Shimmer congelado`), o som **nunca** cai: a cauda vai sempre até o valor da `Cauda dos efeitos` e termina cortada. Escolha o tempo que quer ouvir (até 30 s) e confira o fim.
5. Se depois quiser a exportação com essa cauda inteira, suba `Cauda` na janela `Exportar áudio` (máximo 10 s), ou deixe o fim do projeto depois do último clipe.

**Pegadinhas do dia a dia**
- Mexeu no instrumento ou num efeito "e nada mudou"? A faixa está congelada: a edição vale só no `Descongelar`. Olhe o floco no cabeçalho.
- Um `Compressor` com sidechain de outra faixa impede congelar: a legenda do item diz qual faixa. Tire a chave (`Sidechain` em `Própria entrada`), congele e volte a ligar depois do descongelar, ou converta a faixa-chave antes.
- Um barramento não congela: para fixar o som de um retorno de reverb, exporte como stem.

## Combina com

- [Timeline e clipes](02b-timeline-e-clipes.md): o menu `Opções da faixa`, o cabeçalho e as raias.
- [Mixer](06-mixer.md): o fader, o pan, os envios e a saída continuam atuando numa faixa congelada.
- [Painel de efeitos](06c-painel-de-efeitos.md) e [Referência dos efeitos](06d-efeitos-referencia.md): o que fica dentro do áudio congelado e o custo de cada efeito.
- [Exportação](08-exportacao.md): o mesmo render; `Renderizar em faixa nova`.
- [Nuvem e sincronização](01b-nuvem-e-sincronizacao.md): o áudio congelado é um áudio do projeto e conta na cota.
- [Áudio e clipes](03-audio-e-clipes.md), [Warp e altura](03b-warp-e-altura.md) e [Editar áudio](03e-editar-audio.md): o que fazer com o clipe de uma faixa convertida.
- [Histórico e versões](02d-historico-e-versoes.md): os passos `Congelar faixa`, `Descongelar faixa` e `Converter em áudio`.
- Guia: [Congelar faixas e poupar CPU](../guias/congelar-faixas-e-poupar-cpu.md).

## Limites e pegadinhas

- **Editar o conteúdo de uma faixa congelada não soa.** As notas, o instrumento, os efeitos, a automação deles e até os clipes de áudio originais (fades, warp, ganho) podem ser mexidos com a faixa congelada, mas só valem depois do `Descongelar`. O app não avisa na hora da edição `(lido do código)`.
- **Automação de instrumento e de efeito não anda numa faixa congelada.** As raias continuam no projeto e voltam a valer no descongelar; só `Volume`, `Pan` e envios seguem ao vivo.
- **Os efeitos continuam aparecendo no painel de efeitos**, como se estivessem ligados, mas a cadeia da faixa não roda no motor enquanto ela está congelada.
- **O áudio é renderizado uma vez e fica velho.** Se depois de congelar você muda algo de que o som da faixa dependia, o áudio não acompanha. É por isso que um efeito com sidechain de outra faixa é recusado: o áudio ficaria preso ao que a faixa-chave tocava naquele momento. O `Descongelar` refaz tudo com o projeto de agora.
- **Sidechain.** A faixa congelada **continua** servindo de chave para outra faixa (o áudio dela conta, como antes). O que não dá é congelar a faixa que **usa** a chave de outra.
- **Cauda curta corta seco.** Se o reverb ainda soava quando a cauda acabou, o som para de repente. O diálogo vai de 0 a 30 s.
- **Cota.** Cada congelamento é um WAV de 32 bits float novo no projeto e na conta (veja os números acima); `Descongelar` não o apaga e nenhum passo do app o tira da lista de áudios do projeto.
- **Barramento não congela** (a linha de uma pasta nem tem este menu). O som de um barramento depende das outras faixas.
- **Latência de efeitos.** O áudio congelado sai alinhado com a linha do tempo como a exportação (que descarta a latência dos efeitos), `(não confirmado)` para o congelamento em si ([06e](06e-compensacao-de-latencia.md)).
- **Aviso falso possível na exportação.** O aviso da janela `Exportar áudio` (`Um efeito está em solo ou ouvindo a banda...`, para o solo do `Multibanda` e o `Ouvir banda` do `De-esser`) varre os efeitos de todas as faixas, inclusive os das congeladas (que não os rodam mais) `(lido do código; não visto na tela)`.
- **Web e Android:** o mesmo comportamento; o render roda no Web Worker ou no isolado, como a exportação ([08](08-exportacao.md#memória-lotes-e-limites)).

## Atalhos

Nenhum atalho abre o congelamento ou a conversão. Valem os de sempre: `Ctrl+Z` (desfazer) e `Ctrl+Shift+Z` ou `Ctrl+Y` (refazer), em [Transporte](02-transporte.md).
