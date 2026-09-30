# Nuvem e sincronização

> Como o jopendaw leva o mesmo projeto de um aparelho a outro sem nunca travar o seu trabalho: o que cada estado do ícone de nuvem quer dizer, o que fazer quando aparece o conflito, como funcionam os áudios, a cota e o modo offline.

## Onde fica

- **Indicador de nuvem:** na barra de transporte do projeto aberto, depois dos botões `Configurações: entrada de áudio, latência e contagem` e `Atalhos do teclado (?)` e antes do texto de trabalho em andamento. No computador a barra está no topo; no celular, embaixo ([capítulo 00](00-visao-geral.md)). Só existe dentro de um projeto e só aparece com sessão iniciada.
- **Diálogo de conflito:** abre sozinho uma vez quando o conflito aparece; depois, só clicando no ícone vermelho.
- **Spinner de abertura:** o círculo girando no meio da tela quando você abre, num aparelho novo, um projeto que já existe na nuvem.

## A ideia em quatro linhas

1. **Local primeiro.** O documento do projeto e os áudios ficam no aparelho (no navegador, no IndexedDB; no Android, em arquivos do app). Abrir e editar não esperam a rede.
2. **Salvar é local e imediato:** 0,4 s depois da última mexida o documento é gravado no aparelho e o projeto passa a ter "mudanças pendentes".
3. **Enviar é em segundo plano:** 3 segundos depois da última edição, o app manda primeiro os áudios que a nuvem ainda não tem e depois o documento.
4. **Nunca sobrescreve sozinho.** Se a nuvem tem uma versão mais nova e você também mudou coisas, o app para e pergunta.

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

**Retomada:** o app tenta de novo na hora quando volta ao primeiro plano se estava `Offline`, em `Erro`, com mudança pendente ou ainda sem ter buscado a versão da nuvem. (No Android é o ciclo de vida do app; na web, a aba voltar a ficar visível é o equivalente, não confirmado.)

### Diálogo `O projeto mudou em outro aparelho`

Texto do diálogo: `Há uma versão mais nova no servidor e também mudanças feitas aqui que ainda não foram enviadas. Nada foi sobrescrito. Escolha qual vale:`

| Botão (rótulo exato) | O que faz | Quando usar |
|---|---|---|
| `Decidir depois` | Fecha o diálogo e deixa o conflito de pé. O ícone vermelho reabre | Você está no meio de uma edição e quer terminar antes. Nada se perde e nada é enviado; suas mudanças continuam salvas no aparelho |
| `Usar a versão do servidor` (vermelho) | Baixa a versão da nuvem (com os áudios que faltarem) e **descarta** as mudanças deste aparelho. Não dá para desfazer; o histórico de desfazer também é limpo | O outro aparelho tem o trabalho bom e o que se mexeu aqui foi pouco ou por engano |
| `Manter esta e enviar` (botão cheio) | Assume a versão deste aparelho e a envia por cima; a versão da nuvem é **substituída** | Este aparelho tem o trabalho que vale (por exemplo, você editou por horas offline) e o outro só tinha uma mexida acidental |

Detalhes do que acontece:

- Não há mistura automática das duas versões. Se os dois lados têm coisa boa, antes de decidir use `Exportar` neste aparelho para guardar o som do que está aqui (o botão continua disponível durante o conflito). Para guardar o projeto editável, abra `Exportar` e, na janela `Exportar áudio`, escolha `Projeto inteiro (.jopendaw)…`: o arquivo leva a versão deste aparelho e, depois, dá para importá-lo como projeto novo mesmo que você escolha `Usar a versão do servidor`.
- Com o conflito de pé, as edições seguem sendo salvas no aparelho, mas nada sobe.
- Se `Usar a versão do servidor` falhar (por exemplo, a rede caiu no meio do download), o conflito continua e o tooltip do ícone mostra `Não deu para baixar a versão do servidor agora.` para você tentar de novo.
- O conflito aparece em três situações: você abre um projeto que tem mudanças pendentes e a nuvem tem versão mais nova; você envia e a nuvem responde que a versão-base ficou velha; ou você edita enquanto os áudios da nuvem ainda estavam descendo.
- O que é preferência do aparelho não é trocado ao aplicar a versão da nuvem: metrônomo, contagem, compensação de latência e o estado de armar/monitorar de cada faixa ficam como estavam. Andamento e compasso seguem os do projeto (do servidor).

### Mensagens do estado `Erro`

| Mensagem no tooltip | Causa | O que fazer |
|---|---|---|
| `Alguns áudios não foram enviados: cota de armazenamento de 4 GB excedida; apague áudios que não usa mais` | A conta chegou a 4 GB | Veja "Cotas" abaixo |
| `Alguns áudios não foram enviados: arquivo grande demais (máximo de 512 MB)` | Um áudio passa de 512 MB | Divida ou reduza o arquivo |
| `documento grande demais (máximo de 8 MB)` | O documento do projeto (faixas, notas, automação; sem os áudios) passa de 8 MB | Simplifique o projeto |
| `A versão do servidor não abre nesta versão do app. Atualize o jopendaw.` | O documento da nuvem foi salvo por uma versão mais nova | Atualize o app ou recarregue a página |
| `Não deu para sincronizar` | Erro sem detalhe | Continue trabalhando; a próxima edição ou a volta ao app tenta de novo |

No caso dos áudios, o **documento é enviado mesmo assim**: quem abrir o projeto em outro aparelho verá os clipes sem o áudio (`áudio fora deste aparelho`). O envio dos áudios que faltam é tentado de novo na próxima vez que houver algo a enviar.

Se a sessão acabar (a conta foi encerrada em outro lugar), o indicador some e o app volta ao login; o que estava pendente continua guardado no aparelho.

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

**Sobre liberar espaço.** A mensagem de cota fala em "apagar áudios que não usa mais", mas o app hoje não tem tela para ver o uso da conta nem para apagar áudios da nuvem, e o servidor não tem rota para isso. Pelo código do servidor, apagar um projeto, uma faixa ou um clipe **não** devolve espaço: o registro do áudio pertence à conta. Só `Apagar a conta` (tela `Conta`) apaga tudo.

## Quando você está offline

- **Já dentro de um projeto aberto:** continue normalmente. Cada edição é salva no aparelho e marcada como pendente. O ícone fica `Offline` e o app tenta de novo com a espera crescente. Quando a rede volta (ou você volta ao app), ele envia sozinho, áudios primeiro.
- **O que precisa de rede mesmo com o projeto aberto:** mudar o andamento ou o compasso (a barra chama o servidor: sem rede, o novo valor vale só nesta sessão e ao reabrir o projeto volta o do servidor), e `Converter áudio em notas`.
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
3. Ao voltar ao celular mais tarde, abra o projeto de novo: ele traz a versão mais nova do computador se você não tiver mudanças pendentes lá.

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
- [03 Áudio e clipes](03-audio-e-clipes.md) e [03c Gravação](03c-gravacao.md): de onde vêm os áudios que sobem.
- [08 Exportação](08-exportacao.md): guardar o som do que está no aparelho antes de decidir um conflito.
- [01 Projetos, modelos e conta](01-projetos-modelos-conta.md#projeto-em-arquivo-jopendaw): o arquivo `.jopendaw`, cópia do projeto que não depende da nuvem.
- [Guia: backup e levar o projeto para outro aparelho](../guias/backup-e-levar-projeto-para-outro-aparelho.md): quando usar o arquivo e quando usar a sincronização.
- [09 Configurações, atalhos e Android](09-configuracoes-atalhos-android.md): onde ficam os dados locais em cada plataforma.

## Limites e pegadinhas

- **Não há atualização ao vivo.** O app não fica perguntando à nuvem se outro aparelho mudou o projeto. A versão nova é buscada quando você abre o projeto (ou volta ao app com algo por resolver); se você deixar dois aparelhos abertos no mesmo projeto e editar nos dois, o conflito só aparece quando o segundo tentar enviar.
- **Sem histórico de versões.** A nuvem guarda só a versão atual do documento; `Manter esta e enviar` e `Usar a versão do servidor` são definitivos. Um `.jopendaw` exportado antes de decidir é a forma de guardar uma versão que a nuvem vai perder.
- **Dados só do aparelho** (não sincronizam): zoom e rolagem, altura das faixas, seleção, grade de encaixe, altura do painel inferior, a entrada de áudio escolhida, o estado do teclado do computador e do MIDI.
- **O que fica só no aparelho se nunca sincronizar é seu risco:** limpar os dados do site no navegador ou desinstalar o app no Android apaga o que ainda não subiu. O app Android não participa do backup automático do sistema (`allowBackup` desligado no manifesto).
- **Aparelho com documento local mas sem registro de sincronização** (por exemplo, dados de uma versão antiga): o app trata o documento como mudança pendente e o envia; se a nuvem já tiver uma versão, aparece o conflito.
- **Se a nuvem voltar a uma versão mais antiga** (uma restauração do servidor), o app entende que o seu aparelho é a verdade e reenvia a versão local por cima, sem perguntar.
- O `Mexido ...` do card em `Projetos` só anda quando o documento sobe.
- Se você ficar muito tempo sem abrir o app, a sessão pode expirar (30 dias sem uso, 90 no máximo): o que estava pendente continua guardado e sobe depois de entrar de novo, na próxima vez que o projeto for aberto.

## Atalhos

Não há atalhos de teclado para a sincronização. O ícone é o único ponto de interação e só aceita clique no estado `Conflito`.
