# Navegador de áudios

> Uma lista, dentro do painel de baixo, com os áudios do projeto e da sua conta: dá para buscar pelo nome, ouvir sem mexer no projeto (com o transporte parado ou tocando) e levar o áudio para o arranjo com um clique ou arrastando, como clipe numa faixa de áudio ou como zona num sampler. Serve para achar um som que você já tem sem abrir o seletor de arquivos.

Fase 26 B, commits `d567f76` (app e motor) e `de20512` (`engine.wasm` e os três `.so` recompilados). O que este capítulo afirma vem da leitura do código (`app/lib/daw/browser.dart`, `app/lib/daw/browser_panel.dart`, `engine/src/preview.rs`). Foi visto rodando no Chrome, pelo agente de código: a aba, a lista e a pré-escuta com a barra de progresso. O **som** da pré-escuta não foi medido nem ouvido por quem escreveu (a voz fica fora do `probe` do motor). **Inserir, arrastar para o arranjo, criar zona e baixar** só foram vistos nos testes automáticos (o teste do arrasto usa linhas de faixa de mentira), e o que o Android faz não foi visto num aparelho `(testado só por testes automáticos)`. Quando um trecho diz `(testado só por testes automáticos)`, ele vem de `app/test/browser_test.dart` e de `engine/src/preview_tests.rs`.

## Onde fica

- **Aba `Áudios`** do painel de baixo, depois de `Modulação` (ícone de pilha de músicas). Tooltip: `Navegador de áudios: ouvir, buscar e inserir (Shift+B)`. O texto ao lado das abas diz `Áudios do projeto e da conta`.
- **Atalho `Shift+B`** (ação `Navegador de áudios`, id `panel.browser`): abre o painel na aba `Áudios`; apertar de novo com ela aberta fecha o painel (é o mesmo liga e desliga de `X`, `E`, `I` e `F`). Dá para trocar a tecla em `Personalizar` ([09](09-configuracoes-atalhos-android.md)). `Shift+B` era uma tecla que não fazia nada antes; o `B` sozinho continua sem ação. O teclado do computador ligado (`Ctrl+K`) não tem a letra `B`, então `Shift+B` segue valendo com ele.
- **No celular** a aba fica no mesmo painel de baixo, e com o painel estreito as abas mostram só o ícone: o limite subiu de 560 para **620 px** de largura (de 760 para **820 px** quando a aba `Passos` está presente), para a sexta aba caber. A lista cabe em 360 px `(testado só por testes automáticos)`.
- A lista é carregada **toda vez que o painel abre** e quando você toca em `Atualizar a lista`. O que você importa ou insere no projeto aparece sozinho; o que outro aparelho ou outro projeto mandou para a conta só aparece depois de `Atualizar a lista`.
- Fechar o painel, ou trocar de aba, **cala a pré-escuta** e devolve ao motor a memória que ela usou. A busca, o filtro e o chip `No andamento do projeto` ficam como estavam quando você voltar (valem enquanto o projeto está aberto).

## Controles

### Em cima da lista

| Controle (rótulo exato) | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| Campo de busca (dica `Buscar áudio pelo nome`, ícone de lupa) | Filtra a lista enquanto você digita | Sem acento nem diferença entre maiúsculas e minúsculas (`bumbo` acha `Bumbô`); **todas as palavras** têm de estar no nome, em qualquer ordem (`grave bumbô` acha `Bumbo grave.wav`). Só o nome conta: o nome do projeto que usa o áudio não entra na busca | Com o cursor no campo as teclas viram texto e os atalhos (`Espaço`, `K`…) não valem; `Esc`, `Enter` ou um clique fora devolvem o foco à tela do estúdio |
| `Limpar a busca` (ícone `x` no campo) | Apaga o texto | Só aparece com texto na busca | |
| `Atualizar a lista` (ícone de setas circulares) | Lê de novo a conta (servidor) e o que está guardado neste aparelho | Enquanto lê, o botão vira um círculo girando | Use depois de sincronizar outro projeto ou outro aparelho |
| Chip `Todos` | Mostra o que é do projeto **ou** da conta | Padrão | |
| Chip `Projeto` | Só o que está no documento deste projeto | | Inclui o que ainda não subiu para a conta |
| Chip `Conta` | Só o que o servidor guarda na sua conta (inclusive o áudio deste projeto que já sincronizou) | | Um áudio só deste aparelho e que ainda não sincronizou **não** aparece aqui |
| Chip `No andamento do projeto` (tooltip `Estica a pré-escuta para o andamento do projeto (120 BPM), estimando o andamento do áudio. O áudio do projeto não muda.`; o número é o andamento do projeto) | Liga o esticamento da pré-escuta: o app estima o andamento do áudio e o ouve esticado para o andamento do projeto | Desligado por padrão. A razão é `andamento do áudio ÷ andamento do projeto`, limitada a `0,25` a `4` (4 casas). Só vale para a pré-escuta que começar depois de ligar | **Não muda o que `+` ou o arrasto inserem**: o clipe entra no arranjo do jeito que o arquivo é (ver [Limites e pegadinhas](#limites-e-pegadinhas)) |

Sem áudio para mostrar, a lista diz o porquê (texto exato):

| Situação | Mensagem |
|---|---|
| Busca sem resultado | `Nenhum áudio com "texto" no nome.` |
| Chip `Conta` sem nada (e a conta respondeu) | `A conta ainda não tem áudios no servidor. Eles aparecem aqui depois que um projeto sincroniza.` |
| Chip `Projeto` sem nada | `Este projeto ainda não tem áudios. Importe um arquivo (Ctrl+I) ou escolha um da conta.` (o atalho é o de agora de `Importar áudio ou MIDI`) |
| Lendo | `Carregando os áudios…` |
| Nada em lugar nenhum | `Nenhum áudio ainda. Importe um arquivo (Ctrl+I) para ele aparecer aqui.` |

Se a conta não responde (sem rede, sessão acabada), aparece um aviso vermelho `Não deu para ler os áudios da conta.` mais o motivo, com o botão `Tentar de novo`; a lista segue só com os áudios do projeto.

**Ordem da lista.** Os áudios **do projeto primeiro**, depois os só da conta; dentro de cada grupo, por nome (sem acento nem caixa). Um áudio que está no projeto e na conta aparece **uma vez só** (o app junta os dois pelo hash do arquivo, o SHA-256).

### A linha de um áudio

| Controle (rótulo exato) | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| Alça (ícone de seis pontinhos; tooltip `Arraste para o arranjo (clipe) ou para uma faixa de sampler (zona)`; o cursor vira mão) | Pega o áudio para soltá-lo no arranjo | Ver [Arrastar](#arrastar) | No toque também vale segurar a linha toda (toque longo): arrastar a linha rola a lista |
| Nome (tooltip: o nome e, se outros projetos o usam, `Usado em: projeto A, projeto B`) | Identifica o áudio | O nome do arquivo no projeto ou, só na conta, o nome que o projeto que o usa guardou; sem nome em nenhum lado, `Áudio` e os 8 primeiros caracteres do hash (como `Áudio 1a2b3c4d`) | O `Usado em` vem da conta: lista os projetos **sincronizados** que citam o áudio (inclusive este) |
| Linha de detalhes: `duração · tamanho · origem` | Dados do arquivo | **Duração**: `0,4 s` abaixo de 1 s, senão `m:ss` (`0:07`, `1:05`; `99:59+` a partir de 100 min). **Tamanho**: `12,3 MB` (base 1024, vírgula decimal), vem do servidor. **Origem**: `no projeto` ou `só na conta` | A duração só aparece para áudio **do projeto** (a conta não a guarda); o tamanho só para o que está na conta. Áudio só da conta mostra tamanho sem duração, mesmo depois de baixado `(lido do código)` |
| `baixando…` | O download do servidor está em curso | | Some sozinho |
| `fora deste aparelho` (ícone de nuvem cortada, em amarelo) | O áudio está na conta mas o arquivo **não** está neste aparelho (nem decodificado nem guardado) | Vale também para um áudio **do projeto** que este aparelho ainda não recebeu | Ouvir ou inserir baixa o arquivo sozinho; `Baixar para este aparelho` só baixa |
| Botão de pré-escuta (ícone de play) | Toca o áudio sem mexer no projeto | Tooltips: `Ouvir (não mexe no projeto)`; `Ouvir: baixa o áudio deste aparelho antes` (fora do aparelho); com ele tocando vira um quadrado e o tooltip é `Parar a pré-escuta` | Tocar o mesmo de novo para |
| Botão `+` (ícone de mais) | Insere o áudio | Tooltips: `Inserir na faixa selecionada, no cursor`, ou `Criar uma zona no sampler selecionado` quando a faixa selecionada é um sampler | Ver [Inserir](#inserir-com-o-botão-) |
| `Mais ações` (três pontinhos) | Menu com `Criar zona no sampler selecionado` e, só para áudio fora do aparelho, `Baixar para este aparelho` | `Criar zona no sampler selecionado` fica apagado se a faixa selecionada não é um sampler | |

Com a pré-escuta tocando, a linha ganha contorno na cor de destaque e uma barra de progresso embaixo.

### A barra de pré-escuta

| Controle | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| Barra fina de progresso | Mostra onde a pré-escuta está | Anda a cada 50 ms. Ao chegar ao fim do áudio a pré-escuta termina sozinha e a barra some | A posição é a do relógio do app, não a que o motor leu: pode diferir alguns milissegundos do que se ouve |
| Tocar ou arrastar na barra | Ouve a partir daquele ponto | De 0 a 100% da duração; ao soltar, a pré-escuta recomeça dali (com o fade curto de troca) | No celular arraste na horizontal |
| Legenda `0:03 / 0:07` | Posição e duração do que toca | Com o chip `No andamento do projeto` e áudio esticado, acrescenta ` · esticado ×0,75` (a razão aplicada, vírgula decimal) | A duração mostrada já é a do áudio esticado |
| `Baixando o áudio do servidor…` / `Ajustando ao andamento…` / `Preparando…` | O que o app está fazendo antes de o som sair | Uma barra indeterminada aparece acima do texto | `Ajustando ao andamento…` é o esticamento (pode demorar em áudio longo) |

### Avisos do painel

Um quadro acima da lista diz o que a última ação fez (azul) ou por que não deu (vermelho); o `x` o dispensa.

| Aviso (texto exato, `<nome>` é o do áudio) | Quando |
|---|---|
| `<nome> agora está neste aparelho.` | `Baixar para este aparelho` deu certo |
| `<nome>: o servidor não tem este áudio e ele não está neste aparelho.` (vermelho) | Ouvir, baixar ou inserir um áudio que nenhum dos dois lados tem (por exemplo, apagado da conta) |
| `Não deu para baixar <nome>.` mais o motivo (vermelho) | Falha de rede ao baixar |
| `Não deu para tocar <nome>. É um formato que este aparelho decodifica?` (vermelho; se foi erro de rede, em vez da pergunta vem o motivo) | O arquivo não abriu |
| `Não deu para estimar o andamento de <nome>; toquei no original.` (azul) | Com `No andamento do projeto`: a estimativa não teve confiança (mínimo 0,2) |
| `<nome> entrou no arranjo.` | `+` ou arrasto inseriu um clipe |
| `Não deu para inserir <nome>.` mais o motivo (vermelho) | Falha ao baixar ou abrir na inserção |
| `<nome> virou uma zona do sampler "<faixa>".` | `+`, `Criar zona…` ou o arrasto criou a zona; se o teclado estava todo coberto, o aviso da divisão vem junto (ver [O sampler](#o-sampler-zona-nova)) |
| `Escolha uma faixa de sampler para criar a zona.` (vermelho) | `Criar zona no sampler selecionado` sem um sampler selecionado |
| `Não deu para abrir <nome>.` (vermelho) | O arquivo não decodifica ao virar zona |
| `Não deu para criar a zona.` mais o motivo, ou `Não dá para criar outra zona: o limite é de 128 zonas ou o teclado já está todo ocupado por zonas de uma nota só. Apague alguma antes.` (vermelho) | O sampler não comporta outra zona |

## A pré-escuta: uma voz à parte

O som da pré-escuta sai de uma **voz própria do motor**, que não é faixa, não é clipe e não está no documento. Na prática:

- **Toca com o transporte parado ou tocando.** Dar `Espaço` não a interrompe, e ouvir um áudio não move o cursor nem liga o transporte.
- **Não entra no projeto:** não cria passo no desfazer, não marca o projeto como alterado, não sincroniza e não sobe para a nuvem.
- **Não entra no medidor, na exportação nem no render.** Ela é somada ao som **depois** da cadeia e do limitador de segurança do master: o medidor de pico do master, o de loudness (LUFS), o analisador e a exportação (incluindo `Congelar faixa…`) não a veem.
- **Um áudio por vez.** Tocar outro troca a voz: o antigo sai com um fade de 12 ms enquanto o novo entra com um de 3 ms (sem estalo no corte). Parar também usa o fade de 12 ms.
- **Volume:** o áudio toca como ele é (ganho 1, fixo); **não há fader** da pré-escuta, use o volume do aparelho. Sem passar pelo limitador, um áudio muito forte somado a um projeto já alto pode passar de 0 dBFS e ser cortado seco em ±1 `(lido do código; não ouvido)`.
- **Estéreo ou mono:** o mono sai igual nos dois lados; áudio de outra taxa de amostragem é convertido para a do motor `(testado só por testes automáticos)`.
- **Com `No andamento do projeto`**, o app estima o andamento do áudio (o mesmo detector de [03b](03b-warp-e-altura.md), de 60 a 200 BPM), estica uma cópia com o mesmo esticador dos clipes e toca a cópia. A estimativa fica guardada por áudio, então ouvir de novo não a repete. Se o áudio já está no andamento do projeto (razão 1) toca o original. O andamento que conta é o **inicial** do projeto; o mapa de andamento não entra.
- **Web:** o navegador só libera o som depois de um gesto seu; o toque no botão de pré-escuta vale como esse gesto.

## Inserir e arrastar

O áudio entra no arranjo por três caminhos, com regras que dependem do tipo da faixa.

| Destino | Clipe ou zona | Onde |
|---|---|---|
| Faixa de **áudio** | Clipe | Em `+`: no cursor, encaixado na grade. No arrasto: no ponto da régua onde você soltou, encaixado na grade. Se já há clipe nesse trecho da faixa, vai para uma **faixa de áudio nova** |
| Faixa de **sampler** | Zona | Numa faixa livre do teclado (ver [O sampler](#o-sampler-zona-nova)); o ponto do arrasto não importa |
| Qualquer outra faixa (sintetizador, bateria, FM, wavetable, barramento, pasta) | Clipe | Numa **faixa de áudio nova** no fim da lista, no ponto da régua |
| Fora das linhas de faixa (abaixo da última, ou sobre uma linha de automação, de comp ou do master) | Clipe | Numa **faixa de áudio nova** no fim da lista, no ponto da régua |

A faixa nova leva o nome do arquivo sem extensão (até 40 caracteres) e a próxima cor da paleta, e fica selecionada junto com o clipe.

### Inserir com o botão `+`

1. Selecione a faixa de destino (clique no nome dela) e posicione o cursor onde o clipe deve começar (clique na régua).
2. Toque em `+` na linha do áudio.

O clipe entra **no cursor**, arredondado pela grade de agora (`Livre`, `Compasso`, `1/4`, `1/8`, `1/16`; o padrão é `1/4`), com a duração do arquivo. Sem faixa selecionada, ou com uma que não é de áudio nem sampler, o clipe vai para uma faixa de áudio nova. Inserir duas vezes no mesmo cursor, na mesma faixa, põe o segundo numa faixa nova, porque o trecho está ocupado; o navegador **não apara** clipe que já estava lá.

### Arrastar

1. Segure a alça (ou, no toque, a linha toda) e arraste: uma etiqueta com o ícone de nota e o nome (até 220 px) acompanha o ponteiro.
2. Passando sobre as raias do arranjo, uma linha vertical na cor de destaque marca o ponto da régua e a faixa sob o ponteiro ganha um realce.
3. Solte. O ponto é arredondado pela grade de agora; soltando antes do começo da régua o clipe começa em 0.

Soltar fora do arranjo não faz nada.

### Desfazer

- Um clipe inserido (por `+` ou pelo arrasto) é **um passo** do desfazer, chamado `Importar áudio`; `Ctrl+Z` tira o clipe (e a faixa nova, se houve). Importar o áudio para o projeto (registrar o arquivo) não tem passo próprio.
- Uma zona criada é **um passo**, `Adicionar zona do sampler`.
- Ouvir, buscar e baixar não entram no desfazer.

## O sampler: zona nova

`+` com um sampler selecionado, o item `Criar zona no sampler selecionado` ou soltar o áudio na linha de um sampler criam uma **zona** (não um clipe). Ela nasce como no botão `Adicionar sample como zona` do painel do instrumento ([04c](04c-sampler.md#zonas-a-barra-do-cartão)):

| Zona nova | Valor |
|---|---|
| Primeira zona da faixa | Teclado todo (0 a 127), `Nota base` C4 |
| Da segunda em diante | Na maior lacuna que as outras deixam, com a `Nota base` mais perto do C4 |
| Sem lacuna | Divide ao meio a zona de faixa mais larga: a antiga fica com a metade de baixo, a nova com a de cima, e o aviso do painel acrescenta `O teclado já estava coberto: a zona "<nome>" foi dividida e a nova ficou com <nota> a <nota>.` com o que mais tiver mudado (ver 04c) |
| Trecho | O áudio inteiro (início e fim em 0), sem loop |
| Velocidade, ganho, pan, modo | 1 a 127, 0 dB, centro, `Sustentado` |
| Limite | 128 zonas por sampler, ou o teclado todo ocupado por zonas de uma nota só: o aviso `Não dá para criar outra zona…` aparece |

Três coisas diferem do botão do painel do instrumento: (1) a zona **não é selecionada** no mapa da aba `Instrumento`; (2) o aviso da divisão aparece no quadro do navegador, não no cartão `ZONAS`; (3) o áudio é registrado no projeto **antes** de o app checar se cabe outra zona, então com o limite estourado o arquivo entra no projeto (na lista do `Projeto`) sem virar zona `(lido do código)`.

A altura real do áudio o app não sabe: acerte a `Nota base` (ela vem em C4) no editor de zona. Se o sampler tinha **um áudio só** (o modo sem zonas), a primeira zona faz o sampler passar ao modo de zonas e o áudio único deixa de tocar ([04c](04c-sampler.md#dois-modos-áudio-único-e-zonas)).

## Áudio fora deste aparelho

Um áudio da conta cujo arquivo este aparelho não tem aparece com `fora deste aparelho`. Três caminhos o trazem:

| Ação | O que acontece |
|---|---|
| `Baixar para este aparelho` (menu `Mais ações`) | Baixa o arquivo e o guarda no aparelho. Se ele é **do projeto** e faltava, o app também o registra de novo no projeto, e os clipes que o citam voltam a soar. Aviso: `<nome> agora está neste aparelho.` |
| Ouvir | Baixa, guarda e toca. O áudio **não** entra no projeto, e um áudio do projeto que faltava continua faltando até você baixar |
| `+`, menu ou arrasto | Baixa, guarda, registra no projeto e insere |

- **Cota.** Baixar não gasta a cota da conta, que é de 4 GB e conta **arquivos diferentes uma vez só** (o servidor os identifica pelo SHA-256). Inserir num projeto um áudio que já está na conta também não sobe nada de novo: o app pergunta ao servidor quais áudios faltam e a resposta é nenhum ([01b](01b-nuvem-e-sincronizacao.md#áudios)). Ocupa espaço **neste aparelho** (navegador ou pasta do app) o que foi baixado.
- **Só um download por áudio de cada vez.** Se você já está baixando um áudio e manda ouvir ou inserir o mesmo, o app responde com o aviso de que o servidor não tem o áudio, o que não é verdade: espere o `baixando…` sumir e tente de novo `(lido do código)`.
- O arquivo que o servidor não tem mais (apagado em `Conta`, [01](01-projetos-modelos-conta.md#armazenamento-de-áudios-na-tela-conta)) acusa `<nome>: o servidor não tem este áudio e ele não está neste aparelho.`

## Passo a passo

### Achar um kick na conta e testar

1. Abra o painel na aba `Áudios` (`Shift+B`).
2. Toque no chip `Conta` e digite `kick` no campo de busca (vale `Kick`, `kick_01.wav` ou `Bumbô`, se a palavra estiver no nome).
3. Toque no play da linha que parece certa. Se ela traz `fora deste aparelho`, a barra mostra `Baixando o áudio do servidor…` uma vez e o áudio fica guardado; das próximas vezes toca na hora.
4. Toque no meio da barra para ouvir só o final, ou toque no play de outra linha para trocar (o anterior sai com um fade curto).
5. Gostou? Toque em `+` (ver o passo a passo de baixo para o que isso faz) ou arraste pela alça. Não gostou? Nada mudou no projeto.

### Levar um loop já no andamento

O `No andamento do projeto` só serve para **conferir**; o clipe é inserido do jeito que o arquivo é. Para o clipe ficar no andamento:

1. Ligue o chip `No andamento do projeto` e toque no play do loop (por exemplo, um loop de 4 compassos a 90 BPM num projeto a 100 BPM). A legenda diz `esticado ×0,90` e a duração cai de `0:11` (10,67 s) para `0:10` (9,6 s), que é o que 16 tempos a 100 BPM duram.
2. Se ouviu que encaixa, insira com `+` (ou arraste para a faixa de áudio, soltando no começo de um compasso com a grade em `Compasso`).
3. Clique com o botão direito no clipe (ou toque longo) e escolha `Warp e altura…` ([03b](03b-warp-e-altura.md)): `Detectar` estima o andamento e liga o warp (ou digite `90` em `BPM do áudio` e use `Ajustar ao andamento`). O clipe passa a durar 9,6 s sem mexer no arquivo.
4. Se a pré-escuta avisou `Não deu para estimar o andamento de <nome>; toquei no original.`, o detector não teve confiança nesse áudio; digite o `BPM do áudio` à mão em `Warp e altura…`.

### Arrastar um sample para uma faixa de sampler

1. Crie a faixa em `Nova faixa` › `Sampler` (ou selecione uma que você já tem).
2. Na aba `Áudios`, pegue a alça do primeiro áudio e solte na **linha da faixa sampler** (o realce mostra que ela vale).
3. Aviso: `<nome> virou uma zona do sampler "Sampler".` A zona cobre o teclado todo, com a `Nota base` C4.
4. Arraste um segundo áudio para a mesma linha: como o teclado já estava coberto, a primeira zona é dividida ao meio e o aviso diz `O teclado já estava coberto…`.
5. Abra a aba `Instrumento`, o cartão `ZONAS`, e acerte `Notas de` / `até` e a `Nota base` de cada zona (as zonas novas não vêm selecionadas: toque no bloco do mapa).

### Juntar áudios de outro projeto

1. Abra o projeto que vai receber os sons. Confirme que o outro projeto já mostrou `Sincronizado` ([01b](01b-nuvem-e-sincronizacao.md)), senão os áudios dele ainda não estão na conta.
2. Na aba `Áudios`, toque em `Atualizar a lista` e depois no chip `Conta`.
3. Passe o mouse sobre o nome (ou segure no toque) para ler `Usado em: <outro projeto>` e confirme que é o áudio certo; ouça.
4. Arraste para o arranjo, ou toque em `+` com a faixa de destino selecionada. O áudio é baixado uma vez e fica neste aparelho e neste projeto.
5. Áudios de um projeto apagado continuam na conta, sem `Usado em`, e aparecem do mesmo jeito (até você os apagar na tela `Conta`).

## Combina com

- [03 Áudio e clipes](03-audio-e-clipes.md): o botão `Importar` traz um arquivo de fora; o navegador reaproveita o que já está no projeto ou na conta. O clipe que nasce daqui é igual ao importado (mover, aparar, fades, loop).
- [03b Warp e altura](03b-warp-e-altura.md): esticar o clipe ao andamento depois de inserir; o chip `No andamento do projeto` usa o mesmo detector e o mesmo esticador.
- [04c Sampler](04c-sampler.md): o cartão `ZONAS` (mapa, editor da zona, fatiar) para ajustar as zonas que o arrasto cria.
- [02b Timeline e clipes](02b-timeline-e-clipes.md): a grade de encaixe, as linhas de faixa e o que vale ao soltar.
- [01b Nuvem e sincronização](01b-nuvem-e-sincronizacao.md) e [01 Conta](01-projetos-modelos-conta.md#armazenamento-de-áudios-na-tela-conta): de onde vem a lista da conta, a cota de 4 GB e como apagar áudios sem uso.
- [08 Exportação](08-exportacao.md): a pré-escuta nunca sai no arquivo exportado.
- [Achar e usar samples com o navegador](../guias/achar-e-usar-samples-com-o-navegador.md): montar uma batida arrastando samples, conferir um loop no andamento e reaproveitar áudios de outro projeto.

## Limites e pegadinhas

- **A pré-escuta não passa pelo mixer.** Sem fader, sem efeitos, sem pan, sem envio: é o arquivo como ele é. Um áudio pode soar diferente dentro da faixa, com os efeitos dela.
- **`No andamento do projeto` só muda o que se ouve na lista.** O que `+` e o arrasto inserem é o arquivo original; para esticar o clipe use o warp do clipe.
- **O som real da pré-escuta não foi ouvido** por quem documentou; a conferência foi da tela, da barra de progresso e dos testes automáticos.
- **Ouvir não baixa para o projeto, só para o aparelho.** Um áudio do projeto que este aparelho não tem continua `fora deste aparelho` até `Baixar para este aparelho` (ou `+`).
- **A duração não aparece para áudio só da conta**, nem depois de baixado; a do clipe fica conhecida quando você o insere.
- **Só a conta "vê" outros projetos.** `Usado em` lista projetos **sincronizados**; um áudio que só existe num documento que ainda não subiu não aparece no chip `Conta`.
- **Lista antiga.** A conta é lida ao abrir o painel e em `Atualizar a lista`; o que outro aparelho mandou depois não aparece sozinho.
- **Inserir ao gravar.** O navegador não consulta se há gravação em curso; o botão `Importar` fica desligado enquanto se grava, e aqui isso não foi visto `(lido do código; não testado gravando)`.
- **Clipes só em faixa de áudio.** Soltar numa faixa de sintetizador, bateria, FM, wavetable, barramento ou pasta cria uma faixa de áudio nova no fim da lista (fora da pasta) em vez de recusar.
- **Sampler com áudio único.** A primeira zona desliga o áudio único daquele sampler ([04c](04c-sampler.md)).
- **Android.** O arrasto pela alça e o toque longo na linha, o download e a pré-escuta pelo motor nativo só foram conferidos pelos testes e pela leitura do código `(não confirmado no aparelho)`. O `.so` foi recompilado junto (`de20512`); um app com o `.so` antigo não toca a pré-escuta (a chamada vira "desconhecida" e é ignorada).
- **Web com motor antigo.** Um `engine.wasm` de antes da fase 26 B ignora `preview_play`, e a pré-escuta fica muda sem erro.
- **Formatos.** Os mesmos aceitos na importação ([03](03-audio-e-clipes.md#formatos-aceitos)): um arquivo que o aparelho não decodifica dá `Não deu para tocar <nome>. É um formato que este aparelho decodifica?`.

## Atalhos

| Tecla | Ação |
|---|---|
| `Shift+B` | Abrir ou fechar o painel na aba `Áudios` (id `panel.browser`, categoria `Painéis`) |
| `Esc` | Com o cursor no campo de busca, sai do campo; fora dele, fecha o painel |
| `Ctrl+I` (`⌘+I`) | Importar áudio ou MIDI (o arquivo aparece na lista do projeto na hora) |
| `Ctrl+Z` | Desfaz o último clipe ou a última zona inserida |
