# Backup e levar o projeto para outro aparelho

> Guardar uma cópia do projeto que nenhuma edição altera, levar o projeto do computador para o celular sem passar pela sincronização e mandar uma cópia a um colaborador, tudo com o arquivo `.jopendaw`. Cada cenário leva de 2 a 10 minutos, conforme o tamanho dos áudios.

## Ingredientes

| Recurso | Para quê aqui | Capítulo |
|---|---|---|
| `Exportar` na barra e, na janela `Exportar áudio`, o botão `Projeto inteiro (.jopendaw)…` | Gera o arquivo do projeto que está aberto | [01 Projetos, modelos e conta](../manual/01-projetos-modelos-conta.md#projeto-em-arquivo-jopendaw) |
| `Exportar projeto…` (menu `Mais` do card em `Projetos`) | Gera o arquivo sem abrir o projeto | [01 Projetos, modelos e conta](../manual/01-projetos-modelos-conta.md#projeto-em-arquivo-jopendaw) |
| `Importar projeto` (tela `Projetos`) | Cria um projeto novo a partir do arquivo | [01 Projetos, modelos e conta](../manual/01-projetos-modelos-conta.md#projeto-em-arquivo-jopendaw) |
| Ícone de nuvem e conflito | O outro caminho: o mesmo projeto em vários aparelhos, pela conta | [01b Nuvem e sincronização](../manual/01b-nuvem-e-sincronizacao.md) |
| `Exportar` em WAV | O som pronto, para quem só precisa ouvir | [08 Exportação](../manual/08-exportacao.md) |

O que o arquivo leva e o que não leva (faixas, clipes, efeitos, automação, áudios, configurações do documento; sem desfazer, sem sons derivados do warp e sem vínculo com a nuvem) está listado no [capítulo 01](../manual/01-projetos-modelos-conta.md#projeto-em-arquivo-jopendaw).

## Arquivo ou nuvem: quando usar cada um

| | Arquivo `.jopendaw` | Nuvem (sincronização) |
|---|---|---|
| O que é | Uma cópia do projeto, congelada no instante da exportação | O mesmo projeto, mantido igual nos aparelhos da conta |
| Como acontece | Você exporta e importa, à mão | Sozinho, 3 segundos depois da última edição |
| Ao importar / abrir no outro aparelho | Um projeto **novo**, independente do original | O **mesmo** projeto |
| Mudanças feitas depois | Não passam de um lado para o outro | Passam, e o app pergunta se os dois lados mudaram (conflito) |
| Histórico de versões | Cada arquivo é uma versão (você guarda quantas quiser) | Só a versão atual; sem volta |
| Precisa de rede | Só para importar (o projeto novo é cadastrado no servidor); exportar do projeto aberto funciona sem rede se os áudios estão no aparelho | Sim, para enviar e receber (editar segue sem rede) |
| Precisa de conta | Sim, nos dois lados: o app não abre sem sessão | Sim, a mesma conta |
| Cota da conta (4 GB de áudio) | Só o que for enviado ao importar, e o áudio repetido conta uma vez | Sim |
| Sai da sua mão | Sim: o arquivo tem todos os áudios e você o guarda onde quiser | Não: fica na sua conta |

Regra prática:

- **Use a nuvem** quando o projeto é seu e você quer continuar de onde parou em outro aparelho: mesma conta, abra o projeto e pronto.
- **Use o arquivo** para ter uma cópia que ninguém sobrescreve (backup, versão fechada), para passar o projeto a **outra conta** (outra pessoa, outro email) e para guardar uma versão antes de uma decisão irreversível, como o `Manter esta e enviar` ou o `Usar a versão do servidor` de um conflito.
- **Use os dois** no dia a dia sério: a nuvem mantém os aparelhos em dia, o arquivo é o seguro contra apagar por engano, sobrescrever, perder a conta ou a nuvem devolver uma versão antiga.

## Passo a passo

### 1. Backup periódico

O jopendaw não faz backup automático do arquivo: é um hábito seu. A nuvem **não** é backup de verdade, porque guarda só a versão atual (sem histórico), e apagar um projeto o apaga de vez (os áudios dele, porém, ficam na conta como `sem uso` até você limpá-los na tela `Conta`; isso ocupa cota, mas não guarda o projeto).

1. Combine um ritmo: no fim de cada sessão de trabalho, ou toda vez que o projeto chega a um marco (mixagem fechada, arranjo aprovado).
2. Tenha uma pasta de backups fora do aparelho de trabalho (disco externo, Drive, o serviço que você já usa). Uma pasta por música ajuda.
3. Se o projeto está aberto: pare a gravação, se houver, e espere sumir o texto de trabalho em andamento na barra. Toque em `Exportar` na barra e, na janela `Exportar áudio`, em `Projeto inteiro (.jopendaw)…`. Se não está aberto: em `Projetos`, menu `Mais` do card, `Exportar projeto…`.
4. Espere a janela `Exportar projeto` chegar a `Pronto: <nome>.jopendaw (N áudios).`. **Leia o aviso da janela, se houver:** `N áudios não estão neste aparelho nem no servidor e ficaram de fora do arquivo`. Nesse caso o backup está incompleto; abra o projeto em um aparelho que tenha os áudios (ou reimporte os arquivos) e exporte de novo.
5. Na web o arquivo cai na pasta de downloads do navegador; no Android abre o `Salvar <nome>.jopendaw`: escolha a pasta. Depois **confira que o arquivo existe** onde você mandou salvar (no Android, cancelar o "salvar como" também mostra `Pronto`).
6. Acrescente a data ao nome do arquivo ao guardá-lo (`Minha música 2026-09-30.jopendaw`) e mova para a pasta de backups. O nome do **projeto** não muda com isso: só o nome do arquivo.
7. De tempos em tempos, **teste o backup**: em `Projetos`, toque em `Importar projeto` e escolha o arquivo. Ele abre como `<nome> (importado)`; se tocar direito, o backup vale. Apague o projeto de teste (menu `Mais`, `Apagar`).

Vale saber: a cópia é do que está **no aparelho** no instante da exportação. Se o projeto aberto tem edições ainda não sincronizadas, elas entram no arquivo (o `Projeto inteiro (.jopendaw)…` da janela `Exportar áudio` exporta o que está na tela). Já o `Exportar projeto…` do card usa a cópia guardada no aparelho.

### 2. Migrar do computador para o celular, sem depender da nuvem

O caso: você trabalhou no computador e quer o projeto no celular sem esperar a sincronização, ou com outra conta, ou sem confiar na rede do momento.

**Antes: o celular precisa de uma conta.** O app não abre nada sem entrar, e a importação cadastra o projeto novo no servidor. O que muda é que não precisa ser a **mesma** conta do computador, e o projeto não depende de o computador ter sincronizado. Se o celular ainda não tem conta, entre pelo email ou pelo Google/Discord ([capítulo 01](../manual/01-projetos-modelos-conta.md)); a conta se cria na primeira entrada.

1. No computador, abra o projeto e espere o trabalho em andamento acabar.
2. Toque em `Exportar` e, na janela `Exportar áudio`, em `Projeto inteiro (.jopendaw)…`; espere `Pronto: <nome>.jopendaw (N áudios).`. O navegador baixa o arquivo.
3. Passe o arquivo para o celular por qualquer caminho: cabo, Drive ou outra nuvem de arquivos, AirDrop ou compartilhamento próximo, email (atenção ao limite de anexo do seu email; o arquivo tem todos os áudios). Ele precisa ficar em um lugar que o seletor de arquivos do Android enxerga.
4. No celular, abra o jopendaw, vá em `Projetos` e toque no ícone de seta para cima (tooltip `Importar projeto`).
5. Escolha o arquivo. O seletor aceita `.jopendaw` e `.zip`: se o Android não mostrar o arquivo, renomeie para `.zip` e tente de novo `(não confirmado no Android: o filtro de extensão é do seletor do sistema)`.
6. Acompanhe `Conferindo o arquivo…`, `Criando o projeto…` e `Guardando os áudios: 3 de 12`. O estúdio do projeto novo abre sozinho.
7. Deixe o app aberto até o ícone de nuvem dizer `Sincronizado`: é quando os áudios e o documento chegam à conta do celular. Só depois trate esse projeto como guardado.

O que esperar: o projeto no celular é uma **cópia**. O original no computador segue existindo e as duas versões não se falam. Se a partir daí você editar nos dois, as mudanças não se juntam. Para o mesmo projeto vivo nos dois aparelhos, o caminho é a mesma conta e a nuvem ([capítulo 01b](../manual/01b-nuvem-e-sincronizacao.md)).

### 3. Mandar o projeto para um colaborador

1. **Prepare o projeto:** dê um nome que diga a versão (`Música v3 para a Ana`) pelo `Renomear` do card. O nome do projeto vai dentro do arquivo e é o que a outra pessoa vê ao importar. Depois exporte por `Exportar` > `Projeto inteiro (.jopendaw)…` ou por `Exportar projeto…` no card.
2. **Confira o aviso de áudio ausente** da janela `Exportar projeto` (passo 4 do backup). Um áudio que ficou de fora chega mudo para a outra pessoa.
3. **Envie o arquivo** por um serviço de arquivos grandes ou por um link do seu Drive: o arquivo carrega todos os áudios do projeto, então pode ser grande. Pense no que você está entregando: gravações e amostras de terceiros também vão dentro.
4. **A outra pessoa** entra no jopendaw com a conta dela, abre `Projetos`, toca em `Importar projeto` e escolhe o arquivo. Vira um projeto novo na conta dela, com o nome que você deu (com ` (importado)` no fim se ela já tem um projeto com esse nome). O projeto dela e o seu não se conhecem.
5. **Para receber de volta**, ela exporta o projeto dela e manda o arquivo; você importa e ele vira mais um projeto novo na sua conta (`Música v3 para a Ana (importado)` se o nome existe). Ouça, compare e escolha qual fica.
6. **Combine quem edita o quê** e trabalhem em turnos: não há como juntar duas versões. Uma boa divisão é por faixas: cada um mexe nas suas, e a pessoa que fecha a música recria no projeto principal o que veio do outro (por exemplo, exportando a faixa em WAV e importando como áudio, [capítulo 08](../manual/08-exportacao.md) e [capítulo 03](../manual/03-audio-e-clipes.md)).

Se a outra pessoa só precisa **ouvir**, mande o WAV (`Exportar`) em vez do projeto: é menor e não expõe o projeto editável.

## Variações

- **Backup antes de decidir um conflito.** Com o diálogo `O projeto mudou em outro aparelho` aberto (ou depois de `Decidir depois`), exporte o `.jopendaw` neste aparelho: ele leva a versão daqui. Depois escolha `Usar a versão do servidor` sem medo de perder o que só existia neste aparelho: importe o arquivo e você tem as duas versões, cada uma num projeto.
- **Duplicar um projeto para experimentar.** Exporte e importe na mesma conta: nasce `<nome> (importado)`, com os mesmos áudios (sem gastar mais cota, porque áudio repetido conta uma vez). Teste o arranjo radical nele.
- **Restaurar um projeto apagado.** Apagar remove o projeto do servidor e da lista (e, no aparelho, o documento local e os áudios que só ele usava); se você tem o `.jopendaw`, `Importar projeto` o traz de volta como projeto novo (o histórico de desfazer não volta). Os áudios **continuam na conta** como `sem uso` até você apagá-los na tela `Conta` ([armazenamento de áudios](../manual/01-projetos-modelos-conta.md#armazenamento-de-áudios-na-tela-conta)): se ainda estiverem lá, a importação os reaproveita sem gastar cota; se você já limpou, eles sobem de novo a partir do arquivo.
- **Mudar de conta.** Exporte na conta antiga, saia (`Sair`), entre na nova e importe.
- **Arquivar uma música terminada.** Exporte o `.jopendaw` e o WAV e guarde os dois juntos: o primeiro para reeditar, o segundo para ouvir.

## Por que funciona

- O arquivo é o projeto inteiro (documento mais os áudios originais) num zip: o que o app precisa para reconstruir tudo está dentro, e o destino não precisa de mais nada.
- Cada áudio vai identificado pelo SHA-256 do conteúdo e é conferido na importação: arquivo cortado ou alterado é recusado com uma mensagem, em vez de abrir um projeto quebrado.
- Importar **sempre cria um projeto novo**. Isso elimina o risco de sobrescrever um projeto seu, e é também por isso que o arquivo serve a outra conta, a outra pessoa e a você mesmo como versão.
- Depois de importado, o projeto entra na sincronização normal: o app trata o documento local que ainda não subiu como mudança pendente e o envia à conta, com os áudios primeiro. Por isso o passo final dos cenários é esperar o `Sincronizado`.
- A nuvem e o arquivo resolvem problemas diferentes. A nuvem mantém **um** projeto atual em vários lugares; o arquivo guarda **vários** instantes de um projeto e o leva para fora da conta.

## Se der errado

| Sintoma | Causa provável | O que fazer |
|---|---|---|
| Aviso `N áudios não estão neste aparelho nem no servidor e ficaram de fora do arquivo` | O aparelho que exportou não tem esses áudios (limpou os dados do navegador, ou o projeto nunca terminou de baixar) e a nuvem também não | Exporte de um aparelho que tenha os áudios, ou reimporte os arquivos de som no projeto e exporte de novo |
| A janela mostra `Não deu para exportar o projeto: …` | Falha ao montar ou salvar (espaço, permissão de pasta) | `Tentar de novo`; libere espaço; no Android escolha outra pasta |
| `Este projeto ainda não tem nada para exportar: abra-o e adicione algo primeiro.` | O projeto do card nunca foi aberto neste aparelho e o servidor não tem documento dele | Abra o projeto, adicione algo (ou espere ele sincronizar) e exporte |
| `Isto não parece um arquivo de projeto do jopendaw (ou ele está truncado ou corrompido).` | Download cortado, arquivo alterado ou de outro programa | Baixe ou copie de novo; confira o tamanho do arquivo |
| `O arquivo está truncado ou incompleto: falta o áudio 1a2b3c4d….` | O envio ou a cópia do arquivo foi interrompido | Refaça a cópia; se persistir, exporte de novo na origem |
| `Este arquivo foi criado por uma versão mais nova do jopendaw ...` | Quem exportou usa um app mais novo | Atualize o app (no celular, o APK; na web, recarregue a página) |
| Importou e o ícone fica em `Offline` ou `Erro` | Sem rede para enviar, ou cota de 4 GB (libere espaço em `Conta`, `Limpar áudios sem uso`), ou documento acima de 8 MB | O projeto está no aparelho e abre; veja as mensagens da tabela `Mensagens do estado Erro` em [01b](../manual/01b-nuvem-e-sincronizacao.md) |
| `Não deu para importar o projeto: …` | Sem rede ou sem sessão ao cadastrar o projeto | Confira a rede e a conta, e tente de novo |
| Sobrou um projeto vazio na lista depois de uma importação que falhou | O app não conseguiu apagar o projeto criado no meio da falha | Apague o projeto vazio pelo menu `Mais` do card |
| No projeto importado, um clipe está em silêncio e diz `áudio fora deste aparelho` | O áudio faltava no arquivo (ver o primeiro sintoma) | Importe o som de novo naquele clipe |
| O celular não mostra o arquivo no seletor | O filtro de extensão do Android | Renomeie para `.zip` (o app aceita) |
| O andamento ou o compasso mudou na cópia | O andamento vira inteiro, de 20 a 400 BPM, e o compasso vai de 1 a 32 | Ajuste na barra do estúdio ([capítulo 02](../manual/02-transporte.md)) |
