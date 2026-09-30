# Nuvem e sincronização

> Como o jopendaw leva o mesmo projeto de um aparelho a outro sem nunca travar o seu trabalho: o que cada estado do ícone de nuvem quer dizer, como a versão nova de outro aparelho chega sozinha, o que fazer quando aparece o conflito, como funcionam os áudios, a cota, o andamento e o modo offline.

## Onde fica

- **Indicador de nuvem:** na barra de transporte do projeto aberto, depois dos botões `Configurações: entrada de áudio, latência e contagem` e `Atalhos do teclado (?)` e antes do texto de trabalho em andamento. No computador a barra está no topo; no celular, embaixo ([capítulo 00](00-visao-geral.md)). Só existe dentro de um projeto e só aparece com sessão iniciada.
- **Diálogo de conflito:** abre sozinho uma vez quando o conflito aparece; depois, só clicando no ícone vermelho.
- **Spinner de abertura:** o círculo girando no meio da tela quando você abre, num aparelho novo, um projeto que já existe na nuvem.

## A ideia em quatro linhas

1. **Local primeiro.** O documento do projeto e os áudios ficam no aparelho (no navegador, no IndexedDB; no Android, em arquivos do app). Abrir e editar não esperam a rede.
2. **Salvar é local e imediato:** 0,4 s depois da última mexida o documento é gravado no aparelho e o projeto passa a ter "mudanças pendentes".
3. **Enviar é em segundo plano:** 3 segundos depois da última edição, o app manda primeiro os áudios que a nuvem ainda não tem e depois o documento.
4. **Nunca sobrescreve sozinho.** Se a nuvem tem uma versão mais nova e você também mudou coisas, o app para e pergunta. Se você **não** tem nada pendente, a versão mais nova entra sozinha (ver "Receber o que outro aparelho mudou").

## Controles

### Indicador de nuvem (na barra de transporte)

É um botão de ícone. Só o estado `Conflito` é clicável; nos outros o toque não faz nada e serve só para ler o tooltip.

| Estado | Ícone e cor | Tooltip (texto exato) | O que significa | O que fazer |
|---|---|---|---|---|
| Sem sessão | Nada (o botão some) | | Sem usuário autenticado: não há sincronização | Entre na conta |
| Sincronizado | Nuvem com visto, cinza | `Sincronizado` | A nuvem tem exatamente o que está aqui, com os áudios | Nada |
| Sincronizando | Nuvem com setas, ciano | `Sincronizando` ou `Sincronizando (3/12 arquivos)` | Há mudança a enviar (espera de 3 s inclusa), ou está baixando/enviando áudios | Espere; a contagem `x/y` só aparece quando há arquivos a mover |
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
| `Usar a versão do servidor` (vermelho) | Baixa a versão da nuvem (com os áudios que faltarem) e **descarta** as mudanças deste aparelho. Não dá para desfazer; o histórico de desfazer também é limpo | O outro aparelho tem o trabalho bom e o que se mexeu aqui foi pouco ou por engano |
| `Manter esta e enviar` (botão cheio) | Assume a versão deste aparelho e a envia por cima; a versão da nuvem é **substituída** | Este aparelho tem o trabalho que vale (por exemplo, você editou por horas offline) e o outro só tinha uma mexida acidental |

Detalhes do que acontece:

- **Um envio cuja resposta se perdeu não vira conflito.** Se o documento chegou à nuvem mas a resposta não voltou (a rede caiu no meio), o app tenta de novo e a nuvem responde que a versão-base está velha. Antes de perguntar, o app compara: se o documento da nuvem é **idêntico** ao deste aparelho (a comparação ignora a ordem dos campos), ele simplesmente adota a versão da nuvem como a sua, em silêncio, e segue como `Sincronizado` (ou continua enviando, se você editou nesse meio-tempo). O diálogo só aparece quando os dois documentos são de fato diferentes. `(testado só por testes automáticos)`
- Não há mistura automática das duas versões. Se os dois lados têm coisa boa, antes de decidir use `Exportar` neste aparelho para guardar o som do que está aqui (o botão continua disponível durante o conflito). Para guardar o projeto editável, abra `Exportar` e, na janela `Exportar áudio`, escolha `Projeto inteiro (.jopendaw)…`: o arquivo leva a versão deste aparelho e, depois, dá para importá-lo como projeto novo mesmo que você escolha `Usar a versão do servidor`.
- Com o conflito de pé, as edições seguem sendo salvas no aparelho, mas nada sobe.
- Se `Usar a versão do servidor` falhar (por exemplo, a rede caiu no meio do download), o conflito continua e o tooltip do ícone mostra `Não deu para baixar a versão do servidor agora.` para você tentar de novo.
- O app não troca o projeto no instante em que há um salvamento local pendente (uma edição dos últimos 0,4 s). Como você já escolheu o servidor, `Usar a versão do servidor` espera e **tenta até 4 vezes** (com 0,45 s entre elas) antes de desistir. Se as 4 falharem, o conflito continua e o tooltip mostra `Você editou agora há pouco e o projeto não pôde ser trocado. Tente de novo.` Toque no ícone e escolha de novo. `(testado só por testes automáticos)`
- O conflito aparece em três situações: você abre um projeto que tem mudanças pendentes e a nuvem tem versão mais nova; você envia e a nuvem responde que a versão-base ficou velha (e o documento dela é diferente do seu); ou você edita enquanto os áudios da nuvem ainda estavam descendo.
- O que é preferência do aparelho não é trocado ao aplicar a versão da nuvem: metrônomo, contagem, compensação de latência e o estado de armar/monitorar de cada faixa ficam como estavam. **Andamento e compasso vêm junto com o documento** da nuvem (são do documento, como as faixas): ao aplicar a versão do outro aparelho, o seu andamento passa a ser o dele. Ver "Andamento e compasso".

### Mensagens do estado `Erro`

| Mensagem no tooltip | Causa | O que fazer |
|---|---|---|
| `Alguns áudios não foram enviados: cota de armazenamento de 4 GB excedida; apague áudios sem uso na tela Conta` | A conta chegou a 4 GB | Veja "Cotas e limites" abaixo: a tela `Conta` mostra o uso e apaga os áudios sem uso |
| `Alguns áudios não foram enviados: arquivo grande demais (máximo de 512 MB)` | Um áudio passa de 512 MB | Divida ou reduza o arquivo |
| `documento grande demais (máximo de 8 MB)` | O documento do projeto (faixas, notas, automação; sem os áudios) passa de 8 MB | Simplifique o projeto |
| `A versão do servidor não abre nesta versão do app. Atualize o jopendaw.` | O documento da nuvem foi salvo por uma versão mais nova | Atualize o app ou recarregue a página |
| `Não deu para sincronizar` | Erro sem detalhe | Continue trabalhando; a próxima edição ou a volta ao app tenta de novo |

No caso dos áudios, o **documento é enviado mesmo assim**: quem abrir o projeto em outro aparelho verá os clipes sem o áudio (`áudio fora deste aparelho`). O envio dos áudios que faltam é tentado de novo na próxima vez que houver algo a enviar.

Se a sessão acabar (a conta foi encerrada em outro lugar), o indicador some e o app volta ao login; o que estava pendente continua guardado no aparelho.

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
- a nuvem tem uma versão **mais nova** que a que este aparelho conhece.

Como se comporta:

- **Silenciosa.** O ícone não pisca, não aparece erro se a rede falhar e não há aviso de que o projeto mudou: o arranjo simplesmente passa a ser o da nuvem. Se você olha a tela enquanto outro aparelho envia, pode ver o projeto mudar sozinho.
- **Baixa os áudios antes** e só troca o documento quando tudo está à mão. Se você editar no meio do caminho (ou nos últimos 0,4 s antes da troca), a troca não acontece; o que você editou continua seu e, quando o app enviar, cai no conflito de sempre (se o outro aparelho já tinha mudado) e aí você decide.
- **Zera o desfazer**, como qualquer versão que vem da nuvem: `Ctrl+Z` não volta para antes da troca.
- **Mantém as preferências do aparelho** (metrônomo, contagem, latência, armar e monitorar); o andamento e o compasso vêm com o documento.
- Nunca sobrescreve trabalho seu: com qualquer coisa pendente, ela não age.

`(o pull periódico e o pull ao voltar o foco: testado só por testes automáticos)`

## Andamento e compasso

O andamento (BPM) e o compasso (tempos por compasso) são **parte do documento do projeto**, como as faixas e os clipes. Isso muda três coisas em relação ao que se poderia esperar:

- **Trocar é sempre possível, com ou sem rede.** Ao tocar em `Salvar` na janela `Andamento e compasso` ([capítulo 02](02-transporte.md)), o valor entra no documento, no desfazer e no envio normal do documento. Nada espera o servidor.
- **O servidor guarda também um espelho** do andamento e do compasso (é o que a lista `Projetos` mostra). O envio do espelho é em segundo plano e sem alarde: se falhar, não aparece erro; ele fica pendente e sai de novo quando o documento é salvo (inclusive ao desfazer ou refazer), ao abrir o projeto, depois de aplicar uma versão vinda da nuvem e quando o ícone volta a `Sincronizado`. O espelho vai como inteiro entre 20 e 400.
- **Reabrir ou trocar de aparelho não desfaz o andamento.** O andamento que vale é o do documento local (ou o do documento novo que veio da nuvem), nunca mais o do cadastro do projeto. Só um projeto sem documento ainda (recém-criado) parte do andamento e do compasso do cadastro.

O subtítulo do projeto (`120 BPM · 4/4`) mostra o do documento aberto. `(lido do código e coberto por testes automáticos; não visto no Chrome)`

## Apagar um projeto: o que sai do aparelho

Na lista `Projetos`, apagar um projeto (confirmação `Apagar "nome"?`, `O projeto some para sempre, com tudo o que estiver nele.`) apaga primeiro o projeto no servidor e depois **limpa este aparelho**:

- o documento local do projeto, o estado de sincronização e o modelo pendente (se houver);
- os **áudios guardados no aparelho que só esse projeto usava**. Um áudio que o documento local de **qualquer outro projeto da lista** ainda cita fica.

A limpeza nunca dá erro para você: o que não deu para apagar fica como lixo inofensivo. Os sons derivados do warp (cache `warp:`) não entram na limpeza: não há como listá-los e eles se refazem a partir do original.

O que **não** acontece: a limpeza é só deste aparelho. Um outro aparelho que já abriu o projeto continua com a cópia local dele (o projeto some da lista lá, mas o documento e os áudios guardados ficam). E os áudios continuam registrados na conta na nuvem até você apagá-los na tela `Conta` (ver "Cotas e limites"). `(lido do código e coberto por testes automáticos; não visto no Chrome)`

## Áudios

- Cada áudio é identificado pelo SHA-256 do arquivo. Antes de enviar, o app pergunta à nuvem quais dos áudios do projeto ela ainda não tem e manda só esses, um por vez (`Sincronizando (x/y arquivos)`). O mesmo arquivo importado em dois projetos, ou duas vezes, é guardado e contado uma vez só na conta.
- Os áudios sobem **antes** do documento. Assim, quem baixar o documento nunca encontra um clipe apontando para um arquivo que ainda não chegou.
- Ao abrir um projeto, ou ao receber uma versão nova, o app baixa os áudios que faltam no aparelho e só troca o documento quando tudo está à mão. Um áudio que a nuvem não tem (ou que não decodifica) fica marcado como faltando: o clipe mostra `áudio fora deste aparelho` e o app tenta de novo a cada abertura.
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

- **O que conta como "em uso":** um áudio está em uso se o documento **sincronizado** de qualquer projeto da sua conta cita o arquivo (clipes de áudio, faixas de sampler, zonas do sampler). O que está em uso não pode ser apagado (o servidor responde `409` e o app nem oferece o botão); o resto aparece como `sem uso`.
- **Apagar um projeto, uma faixa ou um clipe não devolve espaço sozinho.** O registro do áudio pertence à conta, não ao projeto: depois de apagar, o áudio fica `sem uso` e continua na cota até você apagá-lo na tela `Conta`. Apagar o projeto pelo app ainda limpa o aparelho (documento local e áudios que só ele usava), mas não o servidor.
- **Limpeza em massa poupa o recém-enviado:** `Limpar áudios sem uso` não apaga o que subiu há menos de 1 hora (o áudio sobe antes do documento que o cita). O apagar por item não tem essa folga.
- **Áudio que só ainda não subiu no documento:** se você acabou de adicionar um áudio e o projeto ainda não sincronizou, o servidor não vê a citação. Espere o `Sincronizado` antes de limpar.
- **Áudio igual em contas diferentes:** o servidor guarda o arquivo uma vez; ele só sai do disco (ou do S3) quando **nenhuma** conta o registra. Apagar o seu libera a **sua** cota do mesmo jeito.
- Limite conhecido do servidor: se um documento passar a citar o áudio **exatamente durante** um apagar por item, o servidor pode apagar um áudio que acabou de ser citado (ele confere o uso uma vez, antes de apagar, e não trava as gravações de documento). Nesse caso outros aparelhos ficam sem conseguir baixar o áudio e mostram `áudio fora deste aparelho`; o aparelho que ainda tem o arquivo guardado pode tornar a enviá-lo `(lido do código; o efeito no app não foi reproduzido)`.
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
3. Quando tudo chegou, o estúdio abre com o projeto completo e o ícone `Sincronizado`.
4. Se a nuvem não respondeu em **25 segundos** (rede lenta, muitos áudios grandes, offline), o estúdio abre mesmo assim com uma faixa `Áudio 1` vazia. A sincronização continua em segundo plano (o ícone mostra `Sincronizando` ou `Offline`) e, quando o documento chegar, ele **substitui** a faixa vazia sozinho.
5. **Não edite nesse intervalo.** Se você mexer no projeto vazio antes de a versão da nuvem chegar, os dois lados terão mudado e aparecerá o conflito.

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
| Levo de volta as mudanças? | Não há como fundir. Para trazer de volta o que foi mexido na cópia, exporte a cópia e importe de novo: sai mais um projeto novo. Quem precisa do **mesmo** projeto nos dois lados usa a mesma conta e a sincronização. |

O que pode dar errado na primeira subida de um projeto importado (as mensagens são as de sempre, na tabela `Mensagens do estado Erro`): áudios que passam de 4 GB de cota, arquivo de áudio acima de 512 MB ou documento acima de 8 MB. O importador aceita um `project.json` de até 64 MB, então um arquivo importado com documento entre 8 e 64 MB abre no aparelho e depois fica no estado `Erro` (`documento grande demais (máximo de 8 MB)`) `(deduzido do código; não testado com um arquivo assim)`.

Conflito só aparece se outro aparelho abrir o projeto recém-importado e editar antes de o aparelho que importou terminar a primeira subida: os dois lados terão mudado, como no caso do modelo descrito no [capítulo 01](01-projetos-modelos-conta.md). Evite abrir o projeto novo em outro aparelho antes de o ícone mostrar `Sincronizado`.

## Passo a passo

**Continuar no computador o que começou no celular**

1. No celular, espere o ícone ficar `Sincronizado` (ele passa por `Sincronizando` alguns segundos depois da última edição).
2. No computador, entre com a mesma conta, abra o projeto e espere o círculo sumir.
3. Ao voltar ao celular mais tarde, ele traz a versão mais nova do computador sozinho, se você não tiver mudanças pendentes lá: com o projeto já aberto, em até cerca de 30 s ou ao voltar ao app; ao abrir de novo, na abertura.

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
- [03 Áudio e clipes](03-audio-e-clipes.md) e [03c Gravação](03c-gravacao.md): de onde vêm os áudios que sobem.
- [08 Exportação](08-exportacao.md): guardar o som do que está no aparelho antes de decidir um conflito.
- [01 Projetos, modelos e conta](01-projetos-modelos-conta.md#projeto-em-arquivo-jopendaw): o arquivo `.jopendaw`, cópia do projeto que não depende da nuvem.
- [Guia: backup e levar o projeto para outro aparelho](../guias/backup-e-levar-projeto-para-outro-aparelho.md): quando usar o arquivo e quando usar a sincronização.
- [09 Configurações, atalhos e Android](09-configuracoes-atalhos-android.md): onde ficam os dados locais em cada plataforma.

## Limites e pegadinhas

- **Não é tempo real.** A versão nova de outro aparelho chega em até cerca de 30 s (ou ao voltar ao app), e só se você não tiver nada pendente. Se dois aparelhos abertos editam ao mesmo tempo, quem tiver mudança pendente não recebe: o conflito aparece quando o segundo tentar enviar. A troca automática é silenciosa e zera o desfazer (ver "Receber o que outro aparelho mudou").
- **Sem histórico de versões.** A nuvem guarda só a versão atual do documento; `Manter esta e enviar` e `Usar a versão do servidor` são definitivos. Um `.jopendaw` exportado antes de decidir é a forma de guardar uma versão que a nuvem vai perder.
- **Dados só do aparelho** (não sincronizam): zoom e rolagem, altura das faixas, seleção, grade de encaixe, altura do painel inferior, a entrada de áudio escolhida, o estado do teclado do computador e do MIDI.
- **O que fica só no aparelho se nunca sincronizar é seu risco:** limpar os dados do site no navegador ou desinstalar o app no Android apaga o que ainda não subiu. O app Android não participa do backup automático do sistema (`allowBackup` desligado no manifesto).
- **Aparelho com documento local mas sem registro de sincronização** (por exemplo, dados de uma versão antiga): o app trata o documento como mudança pendente e o envia; se a nuvem já tiver uma versão, aparece o conflito.
- **Se a nuvem voltar a uma versão mais antiga** (uma restauração do servidor), o app entende que o seu aparelho é a verdade e reenvia a versão local por cima, sem perguntar.
- O `Mexido ...` do card em `Projetos` só anda quando o documento sobe.
- Se você ficar muito tempo sem abrir o app, a sessão pode expirar (30 dias sem uso, 90 no máximo): o que estava pendente continua guardado e sobe depois de entrar de novo, na próxima vez que o projeto for aberto.

## Atalhos

Não há atalhos de teclado para a sincronização. O ícone é o único ponto de interação e só aceita clique no estado `Conflito`.
