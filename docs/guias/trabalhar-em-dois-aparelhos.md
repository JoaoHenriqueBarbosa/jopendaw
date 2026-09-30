# Trabalhar em dois aparelhos

> Começar um projeto no computador, abrir no celular, editar nos dois sem perder nada: como saber que subiu, o que fazer no conflito, como trabalhar sem internet e o que a cota de 4 GB significa na prática; cerca de 10 minutos para fazer a primeira vez.

O jopendaw guarda o projeto no aparelho (é a cópia que você edita) e sincroniza com a nuvem em segundo plano. Este guia mostra o ciclo completo, com os textos exatos do ícone de nuvem e do diálogo de conflito. Os tempos e limites vêm do código do app e do servidor.

## Ingredientes

| Recurso | Para quê aqui | Capítulo |
|---|---|---|
| Conta: `Continuar com o Google`, `Continuar com o Discord`, `Receber link de entrada` | A mesma conta nos dois aparelhos | [01 Projetos, modelos e conta](../manual/01-projetos-modelos-conta.md) |
| Indicador de nuvem, diálogo `O projeto mudou em outro aparelho`, cotas | Saber o que subiu, resolver conflito | [01b Nuvem e sincronização](../manual/01b-nuvem-e-sincronizacao.md) |
| Tela `Projetos` (puxar para recarregar), `Importar projeto`, `Exportar projeto…` | Encontrar o projeto no outro aparelho; levar o arquivo | [01 Projetos, modelos e conta](../manual/01-projetos-modelos-conta.md) |
| `Exportar` (WAV) e `Projeto inteiro (.jopendaw)…` | Guardar o som e o projeto inteiro do que está no aparelho antes de decidir um conflito | [08 Exportação](../manual/08-exportacao.md), [01 Projetos, modelos e conta](../manual/01-projetos-modelos-conta.md#projeto-em-arquivo-jopendaw) |
| Gravação, `Compensação de latência`, entrada de áudio | O que é do aparelho e o que é do projeto | [03c Gravação](../manual/03c-gravacao.md), [09 Configurações, atalhos e Android](../manual/09-configuracoes-atalhos-android.md) |
| Barra de transporte no celular | Onde ficam os botões quando a tela é estreita | [00 Visão geral](../manual/00-visao-geral.md), [02 Transporte](../manual/02-transporte.md) |

## Passo a passo

### 1. Preparar os dois aparelhos

1. No computador, abra o jopendaw no navegador e entre. No celular, instale o app Android (`tech.johnenrique.jopendaw`, Android 8.0 ou mais novo; instalação em [09 Configurações, atalhos e Android](../manual/09-configuracoes-atalhos-android.md)) ou abra o mesmo endereço no navegador do celular.
2. Entre com **a mesma conta** nos dois: o mesmo email (link de entrada), ou a mesma conta do Google ou do Discord. Sem senha: a conta é criada na primeira entrada, e uma conta com outro email é uma conta separada, que não enxerga os projetos da primeira.
3. O indicador de nuvem só existe com sessão iniciada e só dentro de um projeto (barra de transporte, depois dos botões `Configurações: entrada de áudio, latência e contagem` e `Atalhos do teclado (?)`).

### 2. Começar no computador

1. Em `Projetos`, `Novo projeto` (precisa de rede), escolha o modelo e `Criar`. Se usar `Batida eletrônica` ou `Gravação de banda`, o modelo só vira faixas **no aparelho que criou o projeto**: abra o projeto nesse aparelho e espere `Sincronizado` antes de abri-lo em outro. Abrindo antes no outro, ele começa vazio (uma faixa `Áudio 1`).
2. Trabalhe normalmente. Cada mexida é salva no aparelho 0,4 s depois de você parar; 3 s depois da última edição o app envia à nuvem, primeiro os áudios que ela ainda não tem (um por vez) e depois o documento.
3. Leia o ícone de nuvem:

| Estado | Ícone | Tooltip | O que significa |
|---|---|---|---|
| Sincronizado | Nuvem com visto, cinza | `Sincronizado` | A nuvem tem exatamente o que está aqui, com os áudios |
| Sincronizando | Nuvem com setas, ciano | `Sincronizando` ou `Sincronizando (3/12 arquivos)` | Há mudança a enviar (a espera de 3 s conta) ou áudios em transferência |
| Offline | Nuvem riscada, âmbar | `Offline (tentando de novo em 8 s)` | Sem rede, servidor fora do ar ou resposta lenta; o app tenta de novo sozinho (2 s, 4 s, 8 s... até 2 minutos) |
| Conflito | Sincronização com alerta, vermelho | `Conflito: o projeto mudou em outro aparelho. Toque para resolver` | Os dois lados mudaram; nada sobe até você escolher. É o único estado clicável |
| Erro | Círculo com exclamação, vermelho | O motivo, ou `Não deu para sincronizar` | Falha que repetir não resolve (cota, arquivo grande, documento grande) |

4. Antes de trocar de aparelho: pare de editar, espere 3 s e confira `Sincronizado`. Isso significa documento **e** áudios na nuvem.
5. Em `Projetos`, o card do projeto mostra `Mexido agora` ou `Mexido há N min`: esse texto só anda quando o documento sobe, então serve de segunda confirmação.

### 3. Abrir no celular

1. No celular, entre com a mesma conta. Em `Projetos`, puxe a lista para baixo para recarregar se o projeto ainda não apareceu.
2. Toque no card do projeto. Como esse aparelho não tem cópia local, o app **espera a primeira conversa com a nuvem**: baixa o documento e todos os áudios. Você vê só um círculo girando no meio da tela, sem texto nem porcentagem.
3. Quando tudo chegou, o estúdio abre com o projeto completo e o ícone `Sincronizado`.
4. Se a nuvem não respondeu em 25 segundos (rede lenta, muitos áudios grandes, sem rede), o estúdio abre mesmo assim com uma faixa `Áudio 1` vazia e a sincronização continua em segundo plano (`Sincronizando` ou `Offline`). Quando o documento chegar, ele **substitui** a faixa vazia sozinho. **Não edite nesse intervalo**: se você mexer no projeto vazio antes de a versão da nuvem chegar, os dois lados terão mudado e aparece o conflito.
5. No celular a barra de transporte fica **embaixo**; o cabeçalho de faixa é mais estreito (132 px) e não tem o chip `FX` nem o mini-fader (os efeitos ficam no menu `Opções da faixa`, item `Efeitos`, ou no mixer, `X`); o painel de baixo ocupa 60% da altura. O menu de contexto do clipe é o **toque longo**; o duplo toque cria o clipe de notas.

### 4. Editar no celular e voltar ao computador

1. Edite no celular o que quiser (por exemplo, gravar uma voz: o Android pede a permissão de microfone na primeira vez). Cada gravação vira um áudio novo do projeto e sobe antes do documento.
2. Espere o ícone `Sincronizado` (ele passa por `Sincronizando (x/y arquivos)` enquanto os áudios sobem).
3. No computador, se o projeto já estava aberto e **sem mudanças pendentes** (ícone `Sincronizado`), não precisa fazer nada: o app olha a nuvem a cada 30 segundos e quando você volta à janela, e troca o projeto sozinho pela versão que o celular enviou. É silencioso: não há aviso, o ícone não pisca, o arranjo simplesmente muda e o histórico de desfazer é zerado (`Ctrl+Z` não volta para antes da troca). Se preferir, feche o projeto (seta de voltar do cabeçalho) e abra-o de novo em `Projetos`, ou recarregue a página: a versão nova é buscada na abertura. `(o pull a cada 30 s e ao voltar o foco: testado só por testes automáticos; não visto no Chrome)`
4. Se você tem **mudanças pendentes** no computador (editou e ainda não subiu, ou está offline), a troca automática **não acontece**: o app nunca sobrescreve trabalho seu. Nesse caso o conflito aparece quando o computador tentar enviar (a versão-base dele ficou velha). Evite: espere `Sincronizado` antes de mexer no outro aparelho.

### 5. Resolver um conflito

O diálogo `O projeto mudou em outro aparelho` abre sozinho uma vez, com o texto `Há uma versão mais nova no servidor e também mudanças feitas aqui que ainda não foram enviadas. Nada foi sobrescrito. Escolha qual vale:`. Depois disso, só o ícone vermelho reabre. Ele aparece quando: você abre um projeto que tem mudanças pendentes e a nuvem tem versão mais nova; você envia e a nuvem responde que a base ficou velha **e o documento dela é diferente do seu**; ou você edita enquanto os áudios da nuvem ainda estavam descendo. Se a nuvem responde "base velha" mas o documento dela é idêntico ao seu (o envio tinha chegado e só a resposta se perdeu), o app adota a versão em silêncio, sem diálogo `(testado só por testes automáticos)`.

As três escolhas:

| Botão | O que faz | Quando escolher |
|---|---|---|
| `Decidir depois` | Fecha o diálogo e deixa o conflito de pé; suas mudanças continuam salvas no aparelho e nada sobe | Você está no meio de uma edição, ou ainda não sabe qual lado vale |
| `Usar a versão do servidor` (vermelho) | Baixa a versão da nuvem (com os áudios que faltarem) e **descarta** as mudanças deste aparelho. Não dá para desfazer; o histórico de desfazer também é limpo | O outro aparelho tem o trabalho bom e o daqui foi pouco ou por engano |
| `Manter esta e enviar` (botão cheio) | Assume a versão deste aparelho e a envia por cima; a versão da nuvem é **substituída** | Este aparelho tem o trabalho que vale (por exemplo, horas de edição offline) |

Não há mistura automática, e a nuvem guarda só a versão atual: as duas escolhas destrutivas são definitivas. Por isso, antes de decidir, guarde o que pode perder:

1. Toque em `Decidir depois`. O conflito continua e o app segue salvando no aparelho, sem enviar nada.
2. **Neste aparelho**, guarde a versão daqui: `Exportar` (o som em WAV) e, para guardar o projeto inteiro, `Exportar` de novo e, na janela `Exportar áudio`, o botão `Projeto inteiro (.jopendaw)…` no pé dela. O arquivo `.jopendaw` reúne faixas, clipes, mixagem e os áudios ([01 Projetos, modelos e conta](../manual/01-projetos-modelos-conta.md#projeto-em-arquivo-jopendaw)); o guia [Backup e levar o projeto para outro aparelho](backup-e-levar-projeto-para-outro-aparelho.md) tem o passo a passo completo.
3. Decida. Se escolher `Manter esta e enviar` e a versão que está na nuvem tem valor, faça o mesmo procedimento **no outro aparelho** antes, exportando o `.jopendaw` de lá.
4. Toque no ícone vermelho e escolha `Usar a versão do servidor` ou `Manter esta e enviar`. Espere o ícone voltar a `Sincronizado`.
5. Para recuperar algo do lado descartado: em `Projetos`, `Importar projeto` (no celular, o botão só com ícone, tooltip `Importar projeto`), escolha o `.jopendaw`. Nasce um projeto novo, chamado `<nome> (importado)` (ou `(importado 2)`), e o app o abre. Você ouve os dois e refaz à mão o que faltar: a timeline não copia clipes entre projetos, e a área de transferência de notas do editor (`Ctrl+C`, `Ctrl+V`) vale para a sessão `(não confirmado se passa de um projeto a outro)`.

Se `Usar a versão do servidor` falhar (a rede caiu no meio do download), o conflito continua e o tooltip mostra `Não deu para baixar a versão do servidor agora.`: tente de novo. Se você tinha acabado de editar (nos últimos 0,4 s), o app espera e tenta até 4 vezes trocar o projeto; se não der, o tooltip mostra `Você editou agora há pouco e o projeto não pôde ser trocado. Tente de novo.` e basta escolher de novo `(testado só por testes automáticos)`.

O que **não** é trocado ao aplicar a versão da nuvem: metrônomo, contagem, compensação de latência e o estado de armar/monitorar de cada faixa ficam como estavam neste aparelho. O andamento e o compasso, ao contrário, **vêm com o documento**: ao usar a versão da nuvem, o andamento passa a ser o dela.

### 6. Sem internet

1. **Antes de sair da rede**, abra o projeto com internet e espere `Sincronizado`: assim os áudios já estão no aparelho.
2. Trabalhe normalmente. O ícone fica `Offline (tentando de novo em N s)`; é esperado. Tudo é salvo no aparelho e marcado como pendente. Gravar, esticar (warp), exportar em WAV e editar notas rodam no próprio aparelho e não dependem da rede.
3. **Não feche o app nem a aba enquanto estiver sem rede.** A lista de projetos vem do servidor: sem rede você não chega ao estúdio (aparece o erro com `Tentar de novo`). O que estava aberto não é interrompido pela queda; o que fechou só reabre com rede.
4. O que exige rede mesmo com o projeto aberto: `Converter em notas (MIDI)`. Criar, renomear e apagar projeto também. **Mudar o andamento ou o compasso funciona offline**: o valor entra no projeto, é salvo no aparelho e sobe com o documento; só o número que a lista `Projetos` mostra (uma cópia no servidor) espera a rede voltar `(lido do código e coberto por testes automáticos; não visto no Chrome)`.
5. De volta à rede, deixe o app **aberto no projeto** até o ícone dizer `Sincronizado` (ele também tenta de novo na hora quando volta ao primeiro plano). Envia áudios primeiro, depois o documento.
6. Se ficar muito tempo sem abrir o app (30 dias sem uso, 90 no máximo), a sessão pode expirar; o que estava pendente continua guardado no aparelho e sobe depois de entrar de novo, na próxima vez que o projeto for aberto. Limpar os dados do site no navegador, ou desinstalar o app no Android, apaga o que ainda não subiu.

### 7. Cota de armazenamento

| Limite | Valor |
|---|---|
| Espaço de áudio por conta | 4 GB (arquivos diferentes; o mesmo arquivo em dois projetos conta uma vez) |
| Um arquivo de áudio | 512 MB (o app deixa importar; o envio é que recusa) |
| Documento do projeto (faixas, notas, automação; sem os áudios) | 8 MB |

1. Cada gravação é guardada como WAV de 32 bits float, na taxa do motor. A 48 kHz isso dá cerca de 11,5 MB por minuto em mono e 23 MB por minuto em estéreo (conta feita a partir do formato). Cada tomada de uma gravação em loop é um arquivo separado. Os 4 GB dão, em ordem de grandeza, umas 3 horas de estéreo ou 6 horas de mono.
2. Um áudio **importado** sobe no formato original (um `mp3` continua pequeno). Os sons derivados do warp (esticados, transpostos, invertidos) **não** sobem: cada aparelho refaz os seus.
3. Estourou a cota: o ícone fica `Erro` com o tooltip `Alguns áudios não foram enviados: cota de armazenamento de 4 GB excedida; apague áudios que não usa mais`. O **documento sobe mesmo assim**; em outro aparelho o projeto abre e os clipes sem áudio mostram `áudio fora deste aparelho`. O envio dos que faltam é tentado de novo na próxima vez que houver algo a enviar.
4. A cota de 4 GB é da conta. Desde a fase 9 a tela `Conta` mostra o uso (`Armazenamento de áudios`), lista os áudios (`Ver N áudios`, com o tamanho e os projetos que os usam) e tem `Limpar áudios sem uso` e apagar por item. Apagar um projeto não apaga os áudios no servidor: eles ficam como "sem uso" até você limpar. Ainda vale não gravar 20 tomadas onde bastam 4 e preferir importar arquivos comprimidos quando a qualidade permite. Ver [01b](../manual/01b-nuvem-e-sincronizacao.md).
5. Um arquivo acima de 512 MB: `Alguns áudios não foram enviados: arquivo grande demais (máximo de 512 MB)`; divida ou reduza o arquivo. Documento acima de 8 MB: `documento grande demais (máximo de 8 MB)`; simplifique o projeto.
6. O áudio de uma faixa **congelada** (`Congelar em áudio`) é um WAV de 32 bits float novo no projeto; se ele entra na cota, é `(não confirmado)`, porque o capítulo 08 não afirma.

## Variações

- **Gravar a ideia no celular, mixar no computador.** Grave a voz no celular (permissão de microfone do Android), espere `Sincronizado`, abra no computador e mixe lá. A entrada de áudio escolhida é do aparelho, e a compensação de latência de cada aparelho também: cada um mantém a sua ao receber a versão da nuvem, então calibre no aparelho em que vai gravar ([Gravar uma banda e mixar](gravar-uma-banda-e-mixar.md)).
- **Levar o projeto para outra conta.** Exporte o `.jopendaw` na conta A, entre na conta B e use `Importar projeto`: sai sempre um projeto novo, sem vínculo com o original. O arquivo tem no máximo 1 GB e cada áudio até 512 MB (limites de leitura do app). Passo a passo em [Backup e levar o projeto para outro aparelho](backup-e-levar-projeto-para-outro-aparelho.md).
- **Backup antes de uma grande mexida.** Exporte um `.jopendaw` antes de reorganizar o projeto; ele não depende da nuvem e abre em qualquer conta. A nuvem guarda só a versão atual, então o arquivo é o único histórico.
- **Um só aparelho por sessão.** A regra que evita quase todo conflito: termine, espere `Sincronizado` e só então mexa no outro. Com o outro já aberto e parado, ele recebe sozinho em até cerca de 30 s; o que evita o conflito é o outro não ter mudança pendente.
- **Apagar um projeto.** Em `Projetos`, apagar remove o projeto da conta e limpa o aparelho onde você apagou (documento local, estado de sincronização e os áudios que só ele usava). Outro aparelho que já tinha aberto o projeto guarda a cópia local dele (o projeto some da lista lá) `(lido do código)`.

## Por que funciona

- **Local primeiro.** O documento e os áudios ficam no aparelho (IndexedDB no navegador, arquivos do app no Android). Abrir e editar não esperam a rede, e a nuvem trabalha atrás do palco.
- **Áudios antes do documento.** Quem baixar o documento nunca encontra um clipe apontando para um arquivo que ainda não chegou.
- **Nunca sobrescreve sozinho.** O app lembra a versão da nuvem que você viu por último; se a nuvem tem uma mais nova e você também mudou coisas, ele para e pergunta. A resposta do servidor a um envio de base velha, com um documento diferente do seu, é o que dispara o conflito. Sem nada pendente no aparelho, a versão mais nova entra sozinha, pelo pull de 30 s.
- **Andamento e compasso são do projeto.** Ficam no documento como as faixas e viajam com ele; o servidor só guarda uma cópia para a lista de projetos, enviada em segundo plano.
- **Sem mistura automática.** O documento é um arquivo só (faixas, notas, mixagem); juntar dois estados válidos sem perder trabalho exigiria entender a música. Escolher um lado, com o outro exportado, é previsível.
- **Preferências do aparelho ficam fora do conflito.** Entrada de áudio, zoom, rolagem, grade, altura de faixa, seleção e estado do teclado são do aparelho e nunca entram em conflito.

## Se der errado

| Sintoma | Causa provável | Como resolver |
|---|---|---|
| O projeto não aparece no celular | A lista não recarregou | Puxe a lista para baixo em `Projetos`; confirme que é a mesma conta |
| O círculo gira sem fim ao abrir | Aparelho novo baixando muitos áudios, ou sem rede | Espere até 25 s: o estúdio abre com `Áudio 1` vazia e o documento substitui depois; não edite nesse intervalo |
| O projeto abriu com uma só faixa `Áudio 1` | Modelo aberto antes em outro aparelho (começa como `Vazio`), ou a nuvem ainda não respondeu | Espere o ícone; abra o projeto novo primeiro no aparelho que o criou |
| Conflito logo depois de abrir o projeto num aparelho novo | Você editou o projeto ainda vazio (`Áudio 1`) antes de a versão da nuvem chegar | `Usar a versão do servidor` (o que você mexeu no vazio era pouco); depois espere o ícone antes de editar |
| O ícone fica `Offline` | Sem rede, servidor fora ou resposta lenta (o app espera até 120 s por pedido) | Continue trabalhando; volte à rede e deixe o projeto aberto |
| O ícone fica `Erro` com `A versão do servidor não abre nesta versão do app. Atualize o jopendaw.` | A nuvem tem um documento salvo por uma versão mais nova | Atualize o app (Android) ou recarregue a página (web) |
| O clipe mostra `áudio fora deste aparelho` | O áudio não está neste aparelho e a nuvem não o tem (ou ainda não desceu) | Espere `Sincronizado`; se a cota estourou no outro aparelho, abra o projeto lá e sincronize |
| `Detectar` diz `O áudio deste clipe não está neste aparelho.` | O original ainda não desceu | Espere o ícone ficar `Sincronizado` |
| O projeto mudou sozinho e o `Ctrl+Z` não volta | Outro aparelho enviou uma versão nova e este não tinha nada pendente: o app a aplicou sozinho (pull de 30 s ou ao voltar à janela) | É o comportamento esperado; o que estava aqui foi enviado antes. Para guardar um estado, exporte `Projeto inteiro (.jopendaw)…` |
| O andamento na lista `Projetos` é diferente do do estúdio | A cópia no servidor ainda não foi enviada (você mudou o andamento sem rede) | Deixe o projeto aberto até `Sincronizado`; o andamento que vale é o do estúdio |
| `Usar a versão do servidor` não termina | A rede caiu no meio do download | Tooltip `Não deu para baixar a versão do servidor agora.`: tente de novo com rede |
| Perdi mudanças ao escolher o lado errado | As duas escolhas são definitivas e a nuvem não guarda histórico | Só se você exportou o `.jopendaw` antes: `Importar projeto` |
| O card em `Projetos` continua com `Mexido há N h` | O documento não subiu ainda | O texto só anda quando o documento sobe; confira o ícone no projeto |
| Volta ao login | A sessão terminou (`Sair de todos os aparelhos`, ou 30 dias sem uso) | Entre de novo; o que estava pendente sobe na próxima abertura do projeto |
