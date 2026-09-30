# Nuvem e sincronização

> Como o jopendaw leva o mesmo projeto de um aparelho a outro sem nunca travar o seu trabalho: o que cada estado do ícone de nuvem quer dizer, como a versão nova de outro aparelho chega sozinha, o que fazer quando aparece o conflito, como funcionam os áudios, a cota, o andamento e o modo offline.

## Onde fica

- **Indicador de nuvem:** no **cabeçalho da tela do projeto**, no canto superior direito, à direita do nome e do andamento do projeto ([capítulo 00](00-visao-geral.md)); é o mesmo lugar no computador e no celular. Ele **não está na barra do transporte**: saiu de lá porque a barra passava da largura de uma janela de uns 1500 px e o ícone ficava para fora da tela. Só existe dentro de um projeto, só aparece depois que o estúdio abriu (durante o spinner de abertura ainda não há ícone) e só com sessão iniciada.
- **Diálogo de conflito:** abre sozinho uma vez quando o conflito aparece; depois, só clicando no ícone vermelho.
- **Spinner de abertura:** o círculo girando no meio da tela quando você abre, num aparelho novo, um projeto que já existe na nuvem.

## A ideia em quatro linhas

1. **Local primeiro.** O documento do projeto e os áudios ficam no aparelho (no navegador, no IndexedDB; no Android, em arquivos do app). Abrir e editar não esperam a rede.
2. **Salvar é local e imediato:** 0,4 s depois da última mexida o documento é gravado no aparelho e o projeto passa a ter "mudanças pendentes".
3. **Enviar é em segundo plano:** 3 segundos depois da última edição, o app manda primeiro os áudios que a nuvem ainda não tem e depois o documento.
4. **Nunca sobrescreve sozinho.** Se a nuvem tem uma versão mais nova e você também mudou coisas, o app para e pergunta. Se você **não** tem nada pendente, a versão mais nova entra sozinha (ver "Receber o que outro aparelho mudou").

## Controles

### Indicador de nuvem (no cabeçalho do projeto)

É um botão de ícone. Só o estado `Conflito` é clicável; nos outros o toque não faz nada e serve só para ler o tooltip.

| Estado | Ícone e cor | Tooltip (texto exato) | O que significa | O que fazer |
|---|---|---|---|---|
| Sem sessão | Nada (o botão some) | | Sem usuário autenticado: não há sincronização | Entre na conta |
| Sincronizado | Nuvem com visto, cinza | `Sincronizado` | A nuvem tem exatamente o que está aqui, com os áudios | Nada |
| Sincronizando | Nuvem com setas, ciano | `Sincronizando` ou `Sincronizando (3/12 arquivos)` (no singular, `Sincronizando (0/1 arquivo)`; desde a fase 22 o total usa o plural do app, com ponto no milhar: `1.025 arquivos`) | Há mudança a enviar (espera de 3 s inclusa), ou está baixando/enviando áudios | Espere; a contagem `x/y` só aparece quando há arquivos a mover |
| Offline | Nuvem riscada, âmbar | `Offline (tentando de novo em 8 s)` | Sem rede, servidor fora do ar, ou resposta lenta demais. O app tenta de novo sozinho | Pode continuar trabalhando: tudo fica guardado |
| Conflito | Ícone de sincronização com alerta, vermelho | `Conflito: o projeto mudou em outro aparelho. Toque para resolver` | Os dois lados mudaram. Nada será enviado até você escolher | Toque no ícone e escolha |
| Erro | Círculo com ponto de exclamação, vermelho | O motivo, ou `Não deu para sincronizar` | Falha que repetir não resolve (áudio recusado, documento grande demais, documento do servidor ilegível) | Veja a tabela de mensagens abaixo |

A espera do `Offline` cresce a cada falha seguida: 2 s, 4 s, 8 s, 16 s, 32 s, 64 s e daí 2 minutos no máximo. O número no tooltip é o valor nominal.

**Retomada:** o app tenta de novo na hora quando volta ao primeiro plano se estava `Offline`, em `Erro`, com mudança pendente ou ainda sem ter buscado a versão da nuvem. Nos outros casos (tudo `Sincronizado`), a volta ao primeiro plano faz só uma olhada leve para ver se outro aparelho mudou o projeto (ver "Receber o que outro aparelho mudou"). (No Android é o ciclo de vida do app; na web, a aba voltar a ficar visível é o equivalente, não confirmado.)

### Diálogo `O projeto mudou em outro aparelho`

Texto do diálogo: `Há uma versão mais nova no servidor e também mudanças feitas aqui que ainda não foram enviadas. Nada foi sobrescrito. Escolha qual vale:`

| Botão (rótulo exato) | O que faz | Quando usar |
|---|---|---|
| `Decidir depois` | Fecha o diálogo e deixa o conflito de pé. O ícone vermelho reabre | Você está no meio de uma edição e quer terminar antes. Nada se perde e nada é enviado; suas mudanças continuam salvas no aparelho |
| `Usar a versão do servidor` (vermelho) | Baixa a versão da nuvem (com os áudios que faltarem) e **descarta** as mudanças deste aparelho. Não dá para desfazer; o histórico de desfazer também é limpo (e aparece o aviso `Projeto atualizado de outro aparelho. Desfazer não disponível para o que veio de lá.`) | O outro aparelho tem o trabalho bom e o que se mexeu aqui foi pouco ou por engano |
| `Manter esta e enviar` (botão cheio) | Assume a versão deste aparelho e a envia por cima; a versão da nuvem é **substituída** | Este aparelho tem o trabalho que vale (por exemplo, você editou por horas offline) e o outro só tinha uma mexida acidental |

Detalhes do que acontece:

- **Um envio cuja resposta se perdeu não vira conflito.** Se o documento chegou à nuvem mas a resposta não voltou (a rede caiu no meio), o app tenta de novo e a nuvem responde que a versão-base está velha. Antes de perguntar, o app compara: se o documento da nuvem é **idêntico** ao deste aparelho (a comparação ignora a ordem dos campos), ele simplesmente adota a versão da nuvem como a sua, em silêncio, e segue como `Sincronizado` (ou continua enviando, se você editou nesse meio-tempo). O diálogo só aparece quando os dois documentos são de fato diferentes. `(testado só por testes automáticos)`
- Não há mistura automática das duas versões. Se os dois lados têm coisa boa, antes de decidir use `Exportar` neste aparelho para guardar o som do que está aqui (o botão continua disponível durante o conflito). Para guardar o projeto editável, abra `Exportar` e, na janela `Exportar áudio`, escolha `Projeto inteiro (.jopendaw)…`: o arquivo leva a versão deste aparelho e, depois, dá para importá-lo como projeto novo mesmo que você escolha `Usar a versão do servidor`.
- Com o conflito de pé, as edições seguem sendo salvas no aparelho, mas nada sobe.
- Se `Usar a versão do servidor` falhar (por exemplo, a rede caiu no meio do download), o conflito continua e o tooltip do ícone mostra `Não deu para baixar a versão do servidor agora.` para você tentar de novo.
- O app não troca o projeto no instante em que há um salvamento local pendente (uma edição dos últimos 0,4 s). Como você já escolheu o servidor, `Usar a versão do servidor` espera e **tenta até 4 vezes** (com 0,45 s entre elas) antes de desistir. Se as 4 falharem, o conflito continua e o tooltip mostra `Você editou agora há pouco e o projeto não pôde ser trocado. Tente de novo.` Toque no ícone e escolha de novo. Se, nesse instante, há uma gravação, a música tocando ou um gesto em andamento, o app também não troca o projeto (desde `1180152`) e o tooltip mostra `Há uma gravação, a reprodução ou um gesto em andamento e o projeto não pôde ser trocado. Termine e tente de novo.` `(as 4 tentativas: testado só por testes automáticos; o caso com gravação, reprodução ou gesto foi lido do código e não tem teste: não confirmado)`
- O conflito aparece em três situações: você abre um projeto que tem mudanças pendentes e a nuvem tem versão mais nova; você envia e a nuvem responde que a versão-base ficou velha (e o documento dela é diferente do seu); ou você edita enquanto os áudios da nuvem ainda estavam descendo.
- O que é preferência do aparelho não é trocado ao aplicar a versão da nuvem: metrônomo, contagem, compensação de latência e o estado de armar/monitorar de cada faixa ficam como estavam. **Andamento e compasso vêm junto com o documento** da nuvem (são do documento, como as faixas): ao aplicar a versão do outro aparelho, o seu andamento passa a ser o dele. Ver "Andamento e compasso".

### Mensagens do estado `Erro`

| Mensagem no tooltip | Causa | O que fazer |
|---|---|---|
| `Alguns áudios não foram enviados: cota de armazenamento de 4 GB excedida; apague áudios sem uso na tela Conta` | A conta chegou a 4 GB | Veja "Cotas e limites" abaixo: a tela `Conta` mostra o uso e apaga os áudios sem uso |
| `Alguns áudios não foram enviados: arquivo grande demais (máximo de 512 MB)` | Um áudio passa de 512 MB | Divida ou reduza o arquivo |
| `um áudio citado pelo projeto foi apagado neste instante; envie o áudio de novo e tente salvar outra vez` | O servidor recusou salvar o documento (`422`) porque um áudio que ele cita foi apagado (pela tela `Conta` ou por outro aparelho) no mesmo instante. Nada foi salvo na nuvem; o projeto continua íntegro no aparelho | O app já reenvia os áudios citados e tenta salvar de novo sozinho (até 3 repetições, com espera crescente); só se isso falhar o ícone vai a `Erro`, com esta mensagem seguida de `. Faltam áudios neste aparelho: abra o projeto onde eles estão e tente de novo.` (este aparelho não tem o áudio; o app nem repete) ou de `. Não consegui reenviar o áudio; abra o projeto no aparelho que o tem e tente de novo.` (as repetições acabaram). Aí, abra o projeto no aparelho que tem o áudio |
| `documento grande demais (máximo de 8 MB)` | O documento do projeto (faixas, notas, automação; sem os áudios) passa de 8 MB | Simplifique o projeto |
| `O documento do projeto é de uma versão mais nova do jopendaw (documento 3; esta versão lê até o 2). Atualize o app.` (os números variam: `documento N` é a versão do formato do documento que a nuvem guarda, e `esta versão lê até o M` é a que o seu app lê, hoje 2) | O documento da nuvem foi salvo por um app **mais novo** que este (fase 25, `55cc53b`; antes a sincronização nem conferia). Nada foi trocado aqui nem enviado para lá | Atualize o app (na web, recarregue a página; no Android, instale a versão nova). Detalhes em "Quando a nuvem tem um documento de um app mais novo", logo abaixo |
| `A versão do servidor não abre nesta versão do app. Atualize o jopendaw.` | O documento da nuvem não abre neste app, mesmo sem declarar uma versão mais nova (a leitura falhou: formato que o app não entende, ou ilegível). Desde a fase 25 o documento de versão mais nova tem a mensagem da linha de cima; esta ficou para os outros casos de leitura que falha | Atualize o app ou recarregue a página |
| `Não deu para sincronizar` | Erro sem detalhe | Continue trabalhando; a próxima edição ou a volta ao app tenta de novo |

No caso dos áudios, o **documento é enviado mesmo assim**: quem abrir o projeto em outro aparelho verá os clipes sem o áudio (`áudio fora deste aparelho`). O envio dos áudios que faltam é tentado de novo na próxima vez que houver algo a enviar.

Se a sessão acabar (a conta foi encerrada em outro lugar), o indicador some e o app volta ao login; o que estava pendente continua guardado no aparelho.

### Quando a nuvem tem um documento de um app mais novo

Cada projeto guarda no documento o número do formato dele (o campo `version` do documento, `DawDoc.version`, hoje 2). Ele não tem relação com o número de versão da nuvem que o conflito compara (`Mexido ...`, "versão do servidor"): é só a "edição" do formato que o app sabe ler. Um app velho que lesse e depois salvasse um documento de formato novo perderia o que não conhece e rebaixaria o projeto. Por isso, desde a fase 25 (`55cc53b`), a sincronização **recusa** um documento de formato mais novo que o do app, com a mesma mensagem que o `.jopendaw` já usava (ver [01](01-projetos-modelos-conta.md#mensagens-de-erro-da-importação)).

| Situação | O que você vê | O que acontece |
|---|---|---|
| Você abre o projeto (ou o app faz a primeira conversa), a nuvem tem um documento de formato mais novo, e você **não** tem mudança pendente | Ícone `Erro` (vermelho); o tooltip traz `O documento do projeto é de uma versão mais nova do jopendaw (documento N; esta versão lê até o M). Atualize o app.` O estúdio abre com a cópia deste aparelho (num aparelho novo, sem cópia, com a faixa `Áudio 1` vazia: não edite) | A cópia local **não é trocada nem rebaixada**. Nada é baixado nem enviado. O app não agenda nova tentativa sozinho: tenta de novo ao voltar ao primeiro plano, a cada edição (cerca de 3 s depois) e ao reabrir o projeto, e cada uma dessas rodadas termina no mesmo erro até você atualizar `(testado só por testes automáticos: o caso da cópia local sem pendência)` |
| Você edita neste aparelho enquanto está assim | O ícone pisca em `Sincronizando` e volta a `Erro` | Suas edições ficam guardadas no aparelho (continuam marcadas como pendentes), mas **nunca sobem** enquanto o app for velho. Depois de atualizar o app, a nuvem tem versão mais nova e você tem mudança pendente: aparece o diálogo de conflito de sempre ([acima](#diálogo-o-projeto-mudou-em-outro-aparelho)), e você escolhe `Usar a versão do servidor` ou `Manter esta e enviar` `(deduzido do código)` |
| A recusa acontece já com o projeto aberto e sincronizado (outro aparelho, com o app novo, salva o projeto) | **Nada**: o ícone continua `Sincronizado` | A olhada periódica (a cada 30 s e ao voltar ao app) falha em silêncio, como falha de rede, e o documento novo **não chega**; ela tenta de novo a cada 30 s. O erro só aparece quando você reabre o projeto (a primeira conversa é a rodada completa); se você editar antes disso, o envio cai no conflito da linha de baixo `(lido do código; não testado)` |
| Você tem mudança pendente e a nuvem tem um documento de formato mais novo (e diferente do seu): na abertura, ou no envio, quando a nuvem responde que a versão-base ficou velha | O diálogo de conflito, como sempre (o app ainda não abriu o documento da nuvem) | `Usar a versão do servidor` **falha** com a mensagem acima no tooltip do ícone de conflito (que continua de pé e nada é trocado). **`Manter esta e enviar` não é barrado**: envia o documento deste app velho por cima do da nuvem e o projeto volta ao formato antigo, perdendo o que só o app novo gravou. Não use essa opção até atualizar o app `(lido do código; não testado)` |

O que **não** é coberto por essa recusa (fase 25, lido no código; nenhum desses caminhos tem teste):
- A **cópia local** no aparelho: se um app velho abre um projeto cujo documento local foi gravado por um app mais novo (por exemplo, uma aba web com o app antigo em cache aberta depois de o novo ter salvo), ele lê o que entende e, no próximo salvamento, regrava como formato 2.
- **`Restaurar`** uma versão de `Versões…` ([02d](02d-historico-e-versoes.md)) e **`Exportar projeto…`** da lista (que lê a cópia local ou a da nuvem sem conferir): o que o app velho não entende é perdido no documento restaurado ou exportado.
- O **servidor** não confere o campo `version` do documento: só o app recusa.
- Só vale para o número inteiro `version`: um documento sem esse campo é lido como formato 1.

Como resolver: atualize o app (recarregue a página na web; no Android, instale a versão nova). Com o app novo, a próxima conversa com a nuvem traz o documento normalmente.

## Receber o que outro aparelho mudou

O app não fica só esperando você abrir o projeto de novo: com o projeto aberto e sem nada seu pendente, ele olha a nuvem de tempos em tempos e, se há versão mais nova, troca o documento sozinho.

| Quando olha | Condição |
|---|---|
| A cada **30 segundos** com o projeto aberto | Só depois da primeira conversa com a nuvem |
| Ao **voltar ao primeiro plano** (voltar ao app no celular; a aba voltar a ficar visível na web, `(não confirmado)`) | Quando o ícone está `Sincronizado`. Se estava `Offline`, `Erro`, com pendência ou ainda sem a primeira conversa, o app faz a rodada completa (enviar e receber) em vez da olhada leve |

A olhada só troca o projeto quando **todas** estas coisas são verdade; se qualquer uma falha, ela não faz nada e tenta de novo na próxima:

- há sessão iniciada e o ícone não está sumido;
- você **não** tem mudança pendente neste aparelho (nada por enviar) e não há conflito de pé;
- não há outra conversa com a nuvem em andamento;
- você **não está gravando**;
- o **transporte não está tocando**: a versão nova espera a música parar, em vez de trocar o projeto debaixo do som;
- **nenhum gesto está em andamento**: enquanto algum dedo, botão do mouse ou arraste estiver apertado em qualquer lugar da tela, a troca espera o gesto acabar (assim um arraste de clipe, de nota ou de ponto não vê o documento mudar no meio). Um toque que nunca chega a ser solto (por exemplo, a janela perdeu o foco no meio do gesto) não trava a troca para sempre: ele deixa de contar depois de 30 s sem se mexer, e também ao sair do app e voltar (resolvido em `1180152`; antes a troca ficava esperando até você reabrir o app). Com o **mouse** vale outra regra: um botão principal apertado e parado não manda evento nenhum, então o tempo parado não prova que o gesto acabou, e a troca espera enquanto o último evento do mouse disser que o botão está apertado, sem o limite de 30 s (antes um botão segurado quieto por mais de 30 s deixava a troca acontecer no meio do gesto). Se o soltar se perder, o primeiro movimento seguinte do mouse sem o botão apertado encerra o gesto; perder ou voltar o foco do app também zera a conta. Só dedo e caneta continuam com o limite de 30 s `(testado só por testes automáticos)`;
- a nuvem tem uma versão **mais nova** que a que este aparelho conhece.

Se o projeto está tocando ou você está com um gesto em andamento, a olhada não faz nada e tenta de novo na rodada seguinte (30 s depois, ou ao voltar ao app). Essas duas condições valem também no último instante: se você der play ou pegar um clipe enquanto os áudios da versão nova ainda descem, a troca é cancelada e fica para a próxima olhada.

Como se comporta:

- **Não pisca, mas avisa.** O ícone de nuvem não muda e não aparece erro se a rede falhar. Quando o projeto é de fato trocado, aparece um aviso neutro (ícone de visto, na cor de destaque, não vermelho) com o texto `Projeto atualizado de outro aparelho. Desfazer não disponível para o que veio de lá.` Ele fica logo abaixo da barra de transporte no computador (no celular, no topo da tela do projeto, acima da barra de baixo), junto dos outros avisos, e só some quando você toca no `x` (tooltip `Dispensar`) ou fecha o projeto.
- **Só avisa quando algo mudou.** Se o documento da nuvem é **igual** ao deste aparelho (a comparação ignora a ordem dos campos e as preferências do aparelho: metrônomo, contagem, latência, armar e monitorar), o app apenas adota o número da versão nova, **sem aviso e sem zerar o desfazer**. Acontece, por exemplo, quando o outro aparelho só mexeu numa preferência dele (ligou o metrônomo, armou uma faixa) ou deixou o projeto de novo como estava: a versão da nuvem subiu, mas não há nada para trazer.
- **Baixa os áudios antes** e só troca o documento quando tudo está à mão. Se você editar no meio do caminho (ou nos últimos 0,4 s antes da troca), a troca não acontece; o que você editou continua seu e, quando o app enviar, cai no conflito de sempre (se o outro aparelho já tinha mudado) e aí você decide.
- **Zera o desfazer e o refazer** quando troca: `Ctrl+Z` não volta para antes da troca. É o que o aviso diz.
- **Mantém as preferências do aparelho** (metrônomo, contagem, latência, armar e monitorar); o andamento e o compasso vêm com o documento.
- Nunca sobrescreve trabalho seu: com qualquer coisa pendente, ela não age.
- Uma versão da nuvem também entra por dois outros caminhos: ao abrir um projeto que já tem cópia neste aparelho (mas a nuvem tem versão mais nova e você não tem nada pendente), e depois de `Usar a versão do servidor`. Desde `1180152` esses dois caminhos também esperam: se você está gravando, com a música tocando ou com um gesto em andamento, o app não troca o projeto. Na abertura de um projeto que já tem cópia neste aparelho ele tenta de novo sozinho depois de 2 s, sem conflito e sem erro (o ícone fica em `Sincronizando` até lá; no aparelho novo, sem cópia, a espera é a do círculo girando, ver "Abrir um projeto num aparelho novo"); no `Usar a versão do servidor` o conflito continua e o tooltip mostra `Há uma gravação, a reprodução ou um gesto em andamento e o projeto não pôde ser trocado. Termine e tente de novo.` Antes esses caminhos trocavam o projeto mesmo assim (menos com uma gravação). Só a abertura com uma edição sua no meio do caminho ainda vira conflito.
- **O aviso só sai quando havia um projeto seu para atualizar.** Ao abrir, num aparelho novo, um projeto que já existe na nuvem, o projeto vazio que aparece no lugar até o documento chegar é trocado **sem** o aviso `Projeto atualizado de outro aparelho…` (resolvido em `1180152`; antes o aviso saía também aí, sobre um projeto que você nunca tinha visto). Com cópia neste aparelho (inclusive um projeto criado de um modelo), o aviso continua saindo quando o documento muda; se você editou o projeto vazio antes de a versão da nuvem chegar, também sai `(deduzido do código)`. Depois de `Usar a versão do servidor` o aviso sai como sempre.
- **Sobre esperar até 25 s:** se a nuvem não responde em 25 s, o estúdio abre com o projeto vazio e a troca acontece quando o documento chegar, pelas mesmas regras (sem aviso, se você não mexeu no vazio). `(testado só por testes automáticos: o aviso só quando havia documento local, o gesto que segura a troca na abertura, a troca depois dele; não visto no Chrome nem no Android)`
- **A primeira conversa ocupada não solta o círculo.** Num aparelho novo, se na abertura o projeto está "ocupado" (um gesto do mouse ou do dedo em andamento, por exemplo, ou uma gravação), a primeira rodada da sincronização repete o pull a cada 2 s por dentro, em vez de terminar e deixar o estúdio vazio aparecer para ser trocado depois. O círculo continua até o documento chegar e ser aplicado, ou até os 25 s acabarem (aí vale o item acima). Antes o círculo saía na primeira recusa e o estúdio abria vazio e depois trocava tudo de uma vez. `(testado só por testes automáticos)`

`(o pull periódico, o pull ao voltar o foco, a espera do transporte e do gesto, o aviso e o "documento igual não avisa": testado só por testes automáticos)`

## Andamento e compasso

O andamento (BPM) e o compasso (tempos por compasso) são **parte do documento do projeto**, como as faixas e os clipes. Isso muda três coisas em relação ao que se poderia esperar:

- **Trocar é sempre possível, com ou sem rede.** Ao tocar em `Salvar` na janela `Andamento e compasso` ([capítulo 02](02-transporte.md)), o valor entra no documento, no desfazer e no envio normal do documento. Nada espera o servidor.
- **O servidor guarda também um espelho** do andamento e do compasso (é o que a lista `Projetos` mostra). O envio do espelho é em segundo plano e sem alarde: se falhar, não aparece erro; ele fica pendente e sai de novo quando o documento é salvo (inclusive ao desfazer ou refazer), ao abrir o projeto, depois de aplicar uma versão vinda da nuvem e quando o ícone volta a `Sincronizado`. O espelho vai como inteiro entre 20 e 999, com o numerador real do compasso 1 (limitado a 32 **de propósito**: o servidor e a regra do banco só aceitam de 1 a 32; o mapa de compassos do documento aceita numerador até 64 ao ler o arquivo, mas a tela `Mudar compasso` e a lista `Tempos por compasso` só oferecem até 32, e um 40/4 vindo de um arquivo ficaria como 32 no servidor, senão o envio seria recusado e ficaria pendente para sempre) e a figura do tempo (`beat_unit`, só quando muda): um projeto em `6/8` fica `6/8` no servidor, e a lista `Projetos` e o subtítulo do projeto, antes de o estúdio abrir, mostram `6/8` (antes mostravam `3/4`, porque o espelho não levava a figura). `(testado só por testes automáticos)`
- **Projeto que abre sem documento neste aparelho** (o documento de um projeto novo, ou de um projeto que ainda não tem um): parte do andamento e do compasso do cadastro no servidor, e desde a fase 17 o compasso é convertido para o do documento, que conta semínimas: um `6/8` do cadastro abre como `6/8` de verdade (3 batidas por compasso, com o compasso exato guardado no mapa de compassos), um `7/8` abre como `7/8` (3,5 batidas) e o laço inicial de 4 compassos tem a duração certa. Antes o `6/8` abria como `6/4` e o espelho tentava trocar a figura do cadastro para `4` logo ao abrir. Um projeto criado de um modelo recebe o mesmo compasso (`beatsPerBar` em semínimas e o mapa de compassos); o laço inicial do modelo em compassos que não são `n/4` não foi conferido `(não confirmado)`. `(testado só por testes automáticos)`
- **Reabrir ou trocar de aparelho não desfaz o andamento.** O andamento que vale é o do documento local (ou o do documento novo que veio da nuvem), nunca mais o do cadastro do projeto. Só um projeto sem documento ainda (recém-criado) parte do andamento e do compasso do cadastro.

O subtítulo do projeto (`120 BPM · 4/4`) mostra o do documento aberto, e a barra de transporte mostra o mesmo texto: o andamento sai sem casas quando é inteiro e com uma casa e vírgula quando não é (`120,5 BPM · 4/4`), nos dois lugares. `(lido do código e coberto por testes automáticos; não visto no Chrome)`

## Apagar um projeto: o que sai do aparelho

Na lista `Projetos`, apagar um projeto (confirmação `Apagar "nome"?`, `O projeto some para sempre, com tudo o que estiver nele.`) apaga primeiro o projeto no servidor e depois **limpa este aparelho**:

- o documento local do projeto, o estado de sincronização e o modelo pendente (se houver);
- as **versões nomeadas** do projeto (`Versões…`, [capítulo 02d](02d-historico-e-versoes.md)), que só existem neste aparelho;
- os **áudios guardados no aparelho que só esse projeto usava**. Um áudio que o documento local de **qualquer outro projeto** ainda cita fica. "Qualquer outro" é conferido de dois jeitos: os projetos da lista que está na tela e **todos os documentos de projeto guardados neste aparelho**, mesmo os que a lista não mostra (lista velha, projeto de outra conta que foi aberto aqui, projeto que só existe neste aparelho). Assim um áudio compartilhado com um projeto que a lista não conhece não é apagado por engano.

A limpeza nunca dá erro para você: o que não deu para apagar fica como lixo inofensivo. Os sons derivados do warp (o cache `warp:` dos clipes esticados, transpostos ou invertidos) dos áudios apagados saem junto: a chave deles começa pelo hash do áudio de origem, e a limpeza apaga os que pertencem a um áudio que foi embora. Os derivados de um áudio que outro projeto ainda usa ficam, e o que sobrar continua se refazendo a partir do original (resolvido em `1180152`; antes o cache do warp não entrava na limpeza e ficava no aparelho para sempre). `(testado só por testes automáticos)`

O que **não** acontece: a limpeza é só deste aparelho. Um outro aparelho que já abriu o projeto continua com a cópia local dele (o projeto some da lista lá, mas o documento e os áudios guardados ficam). E os áudios continuam registrados na conta na nuvem até você apagá-los na tela `Conta` (ver "Cotas e limites"). `(lido do código e coberto por testes automáticos; não visto no Chrome)`

## Áudios

- Cada áudio é identificado pelo SHA-256 do arquivo. Antes de enviar, o app pergunta à nuvem quais dos áudios do projeto ela ainda não tem e manda só esses, um por vez (`Sincronizando (x/y arquivos)`). O mesmo arquivo importado em dois projetos, ou duas vezes, é guardado e contado uma vez só na conta.
- Os áudios sobem **antes** do documento. Assim, quem baixar o documento nunca encontra um clipe apontando para um arquivo que ainda não chegou.
- Ao abrir um projeto, ou ao receber uma versão nova, o app baixa os áudios que faltam no aparelho e só troca o documento quando tudo está à mão. Um áudio que a nuvem não tem (ou que não decodifica) fica marcado como faltando: o clipe mostra `áudio fora deste aparelho` e o app tenta de novo a cada abertura.
- **O áudio de uma faixa congelada sobe como os outros.** `Congelar faixa…`, `Converter em áudio…` e `Renderizar em faixa nova` guardam o som renderizado como um áudio do projeto (WAV de 32 bits float, `<faixa> (congelada).wav` ou `(convertida).wav`), enviado pelo SHA-256 antes do documento, e ele **conta na cota de 4 GB** e no limite de 512 MB por arquivo: cerca de 23 MB por minuto em estéreo a 48 kHz (a metade se sai mono). Desde a fase 24 (`ebea0b1`) o `Descongelar` tira o áudio congelado da lista de áudios do projeto (se nenhuma outra faixa o usa); depois que o projeto sincroniza, o documento deixa de citá-lo, ele aparece como `sem uso` na tela `Conta` e pode ser apagado de lá, e só então a cota é devolvida: o arquivo já enviado continua na conta até isso `(lido do código; não testado)`. Antes da fase 24 o áudio ficava citado para sempre e a tela `Conta` não o oferecia para apagar. Faixa congelada cujo áudio não está neste aparelho mostra `áudio fora deste aparelho` na raia dela. Detalhes em [Congelar faixa e converter em áudio](02e-congelar-faixa.md#efeito-no-projeto-na-nuvem-e-nos-arquivos).
- Os sons derivados do warp (esticados, transpostos, invertidos) não sobem: cada aparelho refaz os seus a partir do original.
- `Converter áudio em notas` ([capítulo 03d](03d-audio-para-midi.md)) também envia o áudio do clipe à nuvem e precisa de sessão.

## Cotas e limites

| Limite | Valor | Onde vale |
|---|---|---|
| Espaço de áudio por conta | 4 GB (arquivos diferentes; repetidos contam uma vez) | Servidor |
| Tamanho de um arquivo de áudio | 512 MB | Servidor (o app deixa importar, o envio é que recusa) |
| Tamanho do documento do projeto | 8 MB | Servidor |
| Espera antes de enviar depois da última edição | 3 s | App |
| Espera para gravar a mudança no aparelho | 0,4 s | App |
| Tempo de cada pedido ao servidor | 120 s | App |
| Espera do spinner de abertura | 25 s | App |

**Sobre liberar espaço.** A tela `Conta` mostra o cartão `Armazenamento de áudios` (barra de uso, `X de 4,0 GB usados`, os áudios sem uso e a lista de todos os áudios com os projetos que os usam), com `Limpar áudios sem uso` e o apagar por item. Passo a passo e rótulos em [capítulo 01, seção Armazenamento de áudios](01-projetos-modelos-conta.md#armazenamento-de-áudios-na-tela-conta).

- **O que conta como "em uso":** um áudio está em uso se o documento **sincronizado** de qualquer projeto da sua conta cita o arquivo (clipes de áudio, faixas de sampler, zonas do sampler). O que está em uso não pode ser apagado (o servidor responde `409` com a lista dos projetos e o app nem oferece o botão; se o uso apareceu depois de a tela carregar, o app mostra `Este áudio ainda é usado em projetos; tire-o de lá antes de apagar.`); o resto aparece como `sem uso`.
- **Exportar em FLAC ou MP3 usa a cota por alguns instantes.** Nesses formatos o app sobe o WAV renderizado para a sua conta, o servidor gera o arquivo e ele também entra na conta; os dois contam nos 4 GB (e o WAV, nos 512 MB por arquivo) até o app apagá-los no fim, sem você fazer nada. Cancelar com a conversão rodando interrompe a tarefa no servidor (desde a fase 17) e apaga o que subiu; só se a limpeza falhar (ou o servidor for antigo), o que sobrou aparece como áudio `sem uso` na tela `Conta` (a `Limpar áudios sem uso` só o leva depois de 1 hora de enviado). Cota cheia derruba a exportação com `cota de armazenamento de 4 GB excedida; apague áudios sem uso na tela Conta`, e o app oferece o WAV. Ver [Exportação, FLAC e MP3 pelo servidor](08-exportacao.md#flac-e-mp3-pelo-servidor).
- **Apagar um projeto, uma faixa ou um clipe não devolve espaço sozinho.** O registro do áudio pertence à conta, não ao projeto: depois de apagar, o áudio fica `sem uso` e continua na cota até você apagá-lo na tela `Conta`. Apagar o projeto pelo app ainda limpa o aparelho (documento local e áudios que só ele usava), mas não o servidor.
- **O recém-enviado tem proteção de 1 hora nos dois apagares:** `Limpar áudios sem uso` não apaga o que subiu há menos de 1 hora (o áudio sobe antes do documento que o cita) e avisa quantos ficaram de fora (junto com os que passaram a ser usados por um projeto ou a ter tarefa em andamento no meio da limpeza, que também são contados no aviso). O apagar por item também recusa esse áudio (o servidor responde `409` com `recent: true`), mas o app pergunta antes (`Áudio enviado há pouco`, botão `Apagar mesmo assim`) e aí insiste, passando por cima só dessa proteção. Na lista, o áudio aparece como `sem uso · recém-enviado`. Antes da fase 11 o apagar por item não tinha essa folga. Detalhes em [capítulo 01, Armazenamento de áudios](01-projetos-modelos-conta.md#armazenamento-de-áudios-na-tela-conta).
- **Áudio que só ainda não subiu no documento:** se você acabou de adicionar um áudio e o projeto ainda não sincronizou, o servidor não vê a citação. Espere o `Sincronizado` antes de limpar.
- **Áudio igual em contas diferentes:** o servidor guarda o arquivo uma vez; ele só sai do disco (ou do S3) quando **nenhuma** conta o registra. Apagar o seu libera a **sua** cota do mesmo jeito.
- **Salvar o projeto no mesmo instante de um apagar (resolvido na fase 11).** Antes, se um documento passasse a citar o áudio exatamente durante um apagar por item, o servidor podia apagar um áudio recém-citado e outros aparelhos ficavam com `áudio fora deste aparelho`. Agora apagar, limpar, salvar o documento e criar uma conversão em MIDI tomam a mesma trava por conteúdo no servidor, e cada um confere o uso **depois** de tomá-la: ou o apagar espera o documento e o vê citando (recusa com `409`), ou o apagar termina antes e o salvar do documento é recusado com `422` (que o app resolve reenviando o áudio, ver o item seguinte). `(testado só por testes automáticos do servidor; não reproduzido com dois aparelhos)`
- **`422` ao sincronizar: um áudio que o projeto cita foi apagado neste instante.** Quando o servidor recusa o documento por isso, nada foi gravado e a versão da nuvem não mudou. Desde `1180152` o app trata a recusa sozinho: lê a lista de áudios sumidos, reenvia os que tem neste aparelho e repete o envio do documento (até 3 repetições, isto é, no máximo 4 tentativas, com uma espera crescente entre elas: 0,25 s, 0,5 s e 0,75 s), e você nem vê o `422` (o ícone segue em `Sincronizando`). Se este aparelho **também não tem** o áudio que sumiu (ele só existia no outro aparelho), reenviar não adianta e o app para na hora, sem repetir: o ícone vai a `Erro` com a mensagem `um áudio citado pelo projeto foi apagado neste instante; envie o áudio de novo e tente salvar outra vez. Faltam áudios neste aparelho: abra o projeto onde eles estão e tente de novo.` Só se as tentativas acabarem com o áudio à mão (o servidor seguiu recusando) o erro é `... Não consegui reenviar o áudio; abra o projeto no aparelho que o tem e tente de novo.` (tabela `Mensagens do estado Erro`). Nos dois casos o projeto continua pendente e íntegro no aparelho. Antes o app mostrava só a primeira frase, sem reenviar nada, e a tentativa seguinte repetia o mesmo erro. Se o documento enviado tiver a versão velha, o servidor responde primeiro com o conflito (`409`), nunca com este `422`. `(testado só por testes automáticos, com servidor de mentira; não reproduzido com dois aparelhos)`
- `Apagar a conta` (tela `Conta`) apaga tudo de uma vez.

## Quando você está offline

- **Já dentro de um projeto aberto:** continue normalmente. Cada edição é salva no aparelho e marcada como pendente. O ícone fica `Offline` e o app tenta de novo com a espera crescente. Quando a rede volta (ou você volta ao app), ele envia sozinho, áudios primeiro.
- **Andamento e compasso funcionam offline.** O valor novo entra no documento e sobe com ele; só o espelho no cadastro do projeto espera a rede (ver "Andamento e compasso").
- **O que precisa de rede mesmo com o projeto aberto:** `Converter áudio em notas`.
- **Abrir um projeto:** a lista de projetos e o cadastro do projeto vêm do servidor. Sem rede, você não chega ao estúdio: a lista mostra `Tentar de novo`. O que já estava aberto não é interrompido pela queda.
- **Web:** o app instalável guarda a "casca" do app para abrir sem rede, mas a lista e o projeto são sempre buscados ao vivo.

## Abrir um projeto num aparelho novo

1. Entre com a mesma conta e abra o projeto na lista.
2. O aparelho não tem cópia local, então o app **espera a primeira conversa com a nuvem**: baixa o documento e todos os áudios. Durante essa espera você vê só o círculo girando no meio da tela (sem texto nem porcentagem).
3. Quando tudo chegou, o estúdio abre com o projeto completo e o ícone `Sincronizado`. Nesse caminho **não** aparece o aviso `Projeto atualizado de outro aparelho…`: você nunca tinha visto esse projeto neste aparelho, então não há o que "atualizar" (resolvido em `1180152`) `(testado só por testes automáticos)`.
4. Se a nuvem não respondeu em **25 segundos** (rede lenta, muitos áudios grandes, offline), o estúdio abre mesmo assim com uma faixa `Áudio 1` vazia. A sincronização continua em segundo plano (o ícone mostra `Sincronizando` ou `Offline`) e, quando o documento chegar, ele **substitui** a faixa vazia sozinho (também sem o aviso de atualização, se você não mexeu nela; e, se nessa hora você estiver gravando, com a música tocando ou com um gesto em andamento, a troca espera e tenta de novo 2 s depois). Se isso acontecer ainda **antes** dos 25 s (você está com o mouse apertado quando o documento chega), o círculo simplesmente segue girando: a troca repete a cada 2 s por dentro da primeira conversa e o estúdio só abre já com o projeto completo.
5. **Não edite nesse intervalo.** Se você mexer no projeto vazio antes de a versão da nuvem chegar, os dois lados terão mudado e aparecerá o conflito.
6. Se o projeto na nuvem for de um formato **mais novo** que o do app deste aparelho, o documento não é baixado: o estúdio abre com a faixa `Áudio 1` vazia e o ícone fica em `Erro` com `O documento do projeto é de uma versão mais nova do jopendaw (documento N; esta versão lê até o M). Atualize o app.` (fase 25; ver "Quando a nuvem tem um documento de um app mais novo"). Atualize o app em vez de editar esse projeto vazio `(deduzido do código)`.

Nos aparelhos que já têm o projeto, o spinner não aparece: o estúdio abre na hora com a cópia local e a conversa com a nuvem corre atrás.

## Arquivo `.jopendaw` e a nuvem

O arquivo `.jopendaw` ([capítulo 01](01-projetos-modelos-conta.md#projeto-em-arquivo-jopendaw)) é uma cópia do projeto fora da nuvem. Ele não é outra forma de sincronizar: os dois caminhos não se falam.

| Pergunta | Resposta |
|---|---|
| Importar um `.jopendaw` cria um projeto novo ou atualiza um existente? | **Sempre um projeto novo**, com id novo no servidor, cadastrado na conta que está logada neste aparelho. Nunca sobrescreve nem mistura com um projeto existente, nem com o de onde o arquivo saiu. |
| O projeto importado sincroniza? | Sim, como qualquer projeto. O app abre o estúdio dele logo depois de importar; como o aparelho já tem o documento e não tem estado de sincronização, o documento vale como mudança pendente e sobe sozinho: primeiro os áudios que a nuvem ainda não tem, depois o documento (versão 1 no servidor). O ícone passa por `Sincronizando (x/y arquivos)` e chega a `Sincronizado`. |
| Pode dar conflito de ids com o projeto original? | Não. Os ids de faixas, clipes e efeitos só precisam ser únicos **dentro** do projeto; cada projeto tem o seu documento e o seu id de servidor. O importador ainda refaz ids repetidos ou fora do padrão dentro do próprio documento. |
| E os áudios? | Cada áudio é identificado pelo SHA-256, na conta inteira. Se o original e a cópia usam o mesmo áudio, o áudio sobe (e conta na cota de 4 GB) uma vez só. O importador também não regrava no aparelho um áudio que ele já tem. |
| Exportar exige que o projeto esteja sincronizado? | Não. Do projeto aberto, o arquivo leva o que está na tela agora, sincronizado ou não. Na lista, leva a cópia guardada no aparelho (ou a do servidor, se o aparelho nunca abriu o projeto). Áudio que o aparelho não tem é buscado na nuvem; se nenhum dos dois tem, fica de fora e a janela avisa. |
| Importar funciona sem rede ou sem conta? | Não. O projeto novo é cadastrado no servidor antes de tudo, e o app não passa do login sem sessão. Depois de importado, o envio do documento e dos áudios segue as regras normais: sem rede, o ícone fica `Offline` e sobe quando a rede voltar. |
| Exportar de um projeto e importar no mesmo aparelho e conta? | Vira um segundo projeto, ` (importado)` no nome, com o mesmo conteúdo. Os áudios repetidos não ocupam cota nem espaço de novo. |
| E as versões nomeadas (`Versões…`)? | Não vão no arquivo nem sobem para a nuvem: são só do aparelho. O projeto importado começa sem versões. Para levar uma, `Duplicar como projeto novo…` no painel `Versões` ([capítulo 02d](02d-historico-e-versoes.md)) cria um projeto novo com aquela versão, que aí sim sobe e pode ser exportado. |
| Levo de volta as mudanças? | Não há como fundir. Para trazer de volta o que foi mexido na cópia, exporte a cópia e importe de novo: sai mais um projeto novo. Quem precisa do **mesmo** projeto nos dois lados usa a mesma conta e a sincronização. |

O que pode dar errado na primeira subida de um projeto importado (as mensagens são as de sempre, na tabela `Mensagens do estado Erro`): áudios que passam de 4 GB de cota, arquivo de áudio acima de 512 MB ou documento acima de 8 MB. O importador aceita um `project.json` de até 64 MB, então um arquivo importado com documento entre 8 e 64 MB abre no aparelho e depois fica no estado `Erro` (`documento grande demais (máximo de 8 MB)`) `(deduzido do código; não testado com um arquivo assim)`.

Conflito só aparece se outro aparelho abrir o projeto recém-importado e editar antes de o aparelho que importou terminar a primeira subida: os dois lados terão mudado, como no caso do modelo descrito no [capítulo 01](01-projetos-modelos-conta.md). Evite abrir o projeto novo em outro aparelho antes de o ícone mostrar `Sincronizado`.

## Passo a passo

**Continuar no computador o que começou no celular**

1. No celular, espere o ícone ficar `Sincronizado` (ele passa por `Sincronizando` alguns segundos depois da última edição).
2. No computador, entre com a mesma conta, abra o projeto e espere o círculo sumir.
3. Ao voltar ao celular mais tarde, ele traz a versão mais nova do computador sozinho, se você não tiver mudanças pendentes lá: com o projeto já aberto, em até cerca de 30 s ou ao voltar ao app, desde que a música esteja parada e você não esteja no meio de um arraste (aparece o aviso `Projeto atualizado de outro aparelho...`); ao abrir de novo, na abertura.

**Resolver um conflito**

1. Quando aparecer `O projeto mudou em outro aparelho`, leia as três opções (tabela acima).
2. Se ainda não sabe qual vale, toque em `Decidir depois` e, se quiser, use `Exportar` para guardar o som do que está neste aparelho.
3. Quando decidir, toque no ícone vermelho e escolha `Usar a versão do servidor` ou `Manter esta e enviar`.
4. Espere o ícone voltar a `Sincronizado`.

**Trabalhar sem rede (viagem, estúdio sem wifi)**

1. Abra o projeto com rede antes de sair, para os áudios estarem no aparelho.
2. Trabalhe normalmente; o ícone `Offline` é esperado.
3. De volta à rede, deixe o app aberto no projeto até o ícone dizer `Sincronizado`.

**Garantir que tudo subiu antes de trocar de aparelho**

1. Pare de editar e espere 3 segundos.
2. Confira o ícone: `Sincronizado` significa que documento e áudios estão na nuvem.
3. Só então feche o app ou abra o projeto em outro lugar.

## Combina com

- [01 Projetos, modelos e conta](01-projetos-modelos-conta.md): entrar na mesma conta nos dois aparelhos; o modelo é aplicado só no aparelho que criou.
- [02 Transporte](02-transporte.md): a janela `Andamento e compasso` e o que dela vai ao servidor.
- [02d Histórico e versões](02d-historico-e-versoes.md): o que zera o desfazer quando a nuvem troca o projeto, e as versões locais que a nuvem não guarda.
- [03 Áudio e clipes](03-audio-e-clipes.md) e [03c Gravação](03c-gravacao.md): de onde vêm os áudios que sobem.
- [08 Exportação](08-exportacao.md): guardar o som do que está no aparelho antes de decidir um conflito.
- [01 Projetos, modelos e conta](01-projetos-modelos-conta.md#projeto-em-arquivo-jopendaw): o arquivo `.jopendaw`, cópia do projeto que não depende da nuvem.
- [Guia: backup e levar o projeto para outro aparelho](../guias/backup-e-levar-projeto-para-outro-aparelho.md): quando usar o arquivo e quando usar a sincronização.
- [09 Configurações, atalhos e Android](09-configuracoes-atalhos-android.md): onde ficam os dados locais em cada plataforma.

## Limites e pegadinhas

- **Não é tempo real.** A versão nova de outro aparelho chega em até cerca de 30 s (ou ao voltar ao app), e só se você não tiver nada pendente. Se dois aparelhos abertos editam ao mesmo tempo, quem tiver mudança pendente não recebe: o conflito aparece quando o segundo tentar enviar. A troca automática espera o transporte parar e o gesto acabar, mostra o aviso `Projeto atualizado de outro aparelho. Desfazer não disponível para o que veio de lá.` e zera o desfazer; se o documento da nuvem for igual ao seu, só adota a versão, sem aviso e sem zerar (ver "Receber o que outro aparelho mudou").
- **Sem histórico de versões.** A nuvem guarda só a versão atual do documento; `Manter esta e enviar` e `Usar a versão do servidor` são definitivos. Um `.jopendaw` exportado antes de decidir é a forma de guardar uma versão que a nuvem vai perder. Outra forma, sem sair do app, é `Decidir depois` e `Salvar versão…` ([capítulo 02d](02d-historico-e-versoes.md)): a versão fica neste aparelho, não é tocada pela troca da nuvem e dá para `Restaurar` depois. `(lido do código: as versões moram em outras chaves do guardado local; não visto com um conflito de verdade)`
- **Dados só do aparelho** (não sincronizam): o histórico de desfazer, as versões nomeadas e a preferência das versões automáticas ([02d](02d-historico-e-versoes.md)), zoom e rolagem, altura das faixas, seleção, grade de encaixe, altura do painel inferior, a entrada de áudio escolhida, o estado do teclado do computador e do MIDI.
- **O que fica só no aparelho se nunca sincronizar é seu risco:** limpar os dados do site no navegador ou desinstalar o app no Android apaga o que ainda não subiu. O app Android não participa do backup automático do sistema (`allowBackup` desligado no manifesto).
- **Aparelho com documento local mas sem registro de sincronização** (por exemplo, dados de uma versão antiga): o app trata o documento como mudança pendente e o envia; se a nuvem já tiver uma versão, aparece o conflito.
- **App velho e app novo no mesmo projeto:** a sincronização recusa o documento de formato mais novo que o app lê (`documento N; esta versão lê até o M`), o que protege a cópia deste aparelho, mas só barra a **chegada**: `Manter esta e enviar` ainda envia o documento do app velho por cima. Ver "Quando a nuvem tem um documento de um app mais novo" e o guia [Trabalhar em dois aparelhos](../guias/trabalhar-em-dois-aparelhos.md).
- **Se a nuvem voltar a uma versão mais antiga** (uma restauração do servidor), o app entende que o seu aparelho é a verdade e reenvia a versão local por cima, sem perguntar.
- O `Mexido ...` do card em `Projetos` só anda quando o documento sobe.
- Se você ficar muito tempo sem abrir o app, a sessão pode expirar (30 dias sem uso, 90 no máximo): o que estava pendente continua guardado e sobe depois de entrar de novo, na próxima vez que o projeto for aberto.

## Atalhos

Não há atalhos de teclado para a sincronização. O ícone é o único ponto de interação e só aceita clique no estado `Conflito`.
