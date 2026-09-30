# Voltar atrás: histórico e versões

> Mexer no projeto sem medo de perder o que estava bom: experimentar uma mixagem e voltar, recuperar o projeto como ele estava ontem e tirar uma cópia para uma variação. Cada cenário leva de 2 a 5 minutos.

Situação de teste deste guia: os textos e os números vêm do código (`app/lib/daw/history.dart`, `history_ui.dart`, `snapshots.dart`, `snapshots_ui.dart`). Foram vistos no Chrome o painel `Histórico`, o painel `Versões`, `Salvar versão…` e a versão automática `Ao abrir o projeto`. O resto (`Restaurar`, `Comparar`, `Renomear…`, `Duplicar como projeto novo…`, as automáticas a cada N minutos) é `(testado só por testes automáticos)`; nenhum cenário foi refeito de ponta a ponta no Chrome nem no Android `(não confirmado)`.

## Ingredientes

| Recurso | Para quê aqui | Capítulo |
|---|---|---|
| Botões `Desfazer` e `Refazer` (botão direito ou pressão longa) | Abrir o menu `Histórico… (N)`, `Versões…` e `Salvar versão…`; o tooltip diz o passo | [02 Transporte](../manual/02-transporte.md#edição-e-visão), [02d](../manual/02d-historico-e-versoes.md#onde-fica) |
| Painel `Histórico` (`Ctrl+Shift+H`) | Ver cada passo com nome e hora e voltar a qualquer um de uma vez | [02d](../manual/02d-historico-e-versoes.md#painel-histórico) |
| `Salvar versão…` | Guardar o projeto inteiro com um nome, que dura além da sessão | [02d](../manual/02d-historico-e-versoes.md#salvar) |
| Painel `Versões`: `Restaurar`, `Comparar`, `Renomear…`, `Duplicar como projeto novo…` | Voltar a uma versão, ver o que mudou, proteger uma automática, tirar uma cópia | [02d](../manual/02d-historico-e-versoes.md#versões-do-projeto) |
| `Salvar automaticamente` (`a cada 15 min`, as últimas 20, `Ao abrir o projeto`) | O que já estará guardado sem você pedir | [02d](../manual/02d-historico-e-versoes.md#versões-automáticas) |
| Mixer, efeitos e automação | O que se mexe no cenário 1 | [06 Mixer](../manual/06-mixer.md), [06c Painel de efeitos](../manual/06c-painel-de-efeitos.md), [07 Automação](../manual/07-automacao.md) |

Regra de ouro: o **histórico** some ao fechar o projeto; as **versões** ficam (neste aparelho).

## Passo a passo

### Cenário 1: experimentar uma mixagem sem medo

O objetivo: testar um compressor no master e outra volta de faders, e poder ouvir o antes e o depois.

1. Com a mix como está, botão direito em `Desfazer` e `Salvar versão…`. Nome: `Mix A`, nota: `antes do compressor no master`. `Salvar`. O aviso é `Versão “Mix A” salva neste aparelho.` Se acabou de abrir o projeto e o `Desfazer` está apagado (nada a desfazer), o botão direito não abre menu: use o menu `Visão`, `Versões…` e o botão `Salvar versão…` do painel.
2. Experimente: abaixe o fader da `Bateria`, ponha um `Compressor` no master, mexa no `Limiar` (padrão −18 dB). Cada gesto vira um passo: no painel aparecem nomes como `Volume da faixa`, `Adicionar efeito` e `Mudar parâmetro do efeito`, com a hora ([nomes dos passos](../manual/02d-historico-e-versoes.md#os-nomes-dos-passos)).
3. Desfazer só o último passo: `Ctrl+Z`. Voltar vários de uma vez: `Ctrl+Shift+H`, e toque na linha que tem o estado que você quer (a linha três abaixo de `Estado de agora` desfaz três passos). Os passos que você pulou ficam em cinza e dá para voltar neles até fazer uma edição nova.
4. Gostou desta mix? `Salvar versão…` de novo: `Mix B`, nota `compressor no master`.
5. Ouvir A contra B: `Versões…`, `Restaurar` em `Mix A`, confirme, toque; depois `Restaurar` em `Mix B`. O `Restaurar` de `Mix A` não cria cópia de segurança (o projeto era idêntico à `Mix B`, a versão mais nova); o `Restaurar` de volta em `Mix B` cria uma `Antes de restaurar Mix B` com o que estava (a `Mix A`). Apague essa sobra com `Apagar…` se quiser a lista limpa.
6. Para ver o que separa as duas sem ouvir, `Comparar` no cartão de `Mix A`: aparecem só as linhas que diferem, como `Efeitos: +1` (o compressor) e `Faixas: 1 mudado` (o fader da `Bateria`), e `Igual ao projeto de agora.` se nada difere.

Metrônomo, contagem, punch, latência, mapeamentos de MIDI learn, faixas armadas e pastas recolhidas **não** mudam ao restaurar: ficam como estão. Isso é bom para A/B (o clique não liga e desliga sozinho) e ruim se você esperava que a versão os trouxesse de volta.

### Cenário 2: recuperar o projeto de ontem

O objetivo: o projeto como estava no fim da sessão de ontem, depois de uma tarde de edições que não valeram.

1. `Versões…`. A lista vai da mais nova para a mais velha, com data e hora (`30/09/2026 13:50 · 4 faixas · 3 clipes · 10 KB · automática`).
2. A versão `Ao abrir o projeto` guarda o projeto **como ele estava ao abrir** (só se a última versão tinha mais de 1 hora e o projeto tem mais que a faixa de áudio vazia do início: mais faixas, clipes, notas, instrumento, efeito ou áudio de sampler). A de hoje cedo é, portanto, o projeto como você o deixou ontem. Localize-a pela data e pela hora.
3. `Comparar` nela antes de decidir: `Faixas: +2`, `Clipes MIDI: +3, 1 mudado` e `Notas MIDI: +40, −6` dizem o que você fez desde então. `+` é o que existe agora e não existia lá; `−`, o contrário.
4. `Restaurar` e confirme. O app guarda `Antes de restaurar Ao abrir o projeto` (o projeto de agora) e leva o projeto ao estado da versão, como **um passo** do histórico.
5. Mudou de ideia? `Ctrl+Z` (o tooltip diz `Desfazer: Restaurar versão “Ao abrir o projeto”`). Se você já fechou o projeto, `Versões…` e `Restaurar` em `Antes de restaurar Ao abrir o projeto`.
6. Quer guardar esse ponto de volta para sempre? `Renomear…` (três pontos do cartão) e dê um nome, por exemplo `Fim de 29/09`. Uma versão renomeada deixa de ser automática e nunca sai sozinha.

Cuidado com o prazo: só as **20 últimas automáticas** ficam. Com `a cada 15 min`, uma sessão longa de edição enche as 20 em poucas horas e empurra as de ontem para fora. Se você sabe que vai precisar de um ponto, salve à mão ou renomeie a automática.

### Cenário 3: tirar uma cópia do projeto para uma variação

O objetivo: uma versão acústica da música, sem mexer no projeto principal.

1. Salve o ponto de partida: `Salvar versão…`, nome `Base da acústica`. **A cópia sai de uma versão, não do projeto aberto**; sem este passo você duplicaria uma versão mais velha.
2. `Versões…`, nos três pontos do cartão `Base da acústica`, `Duplicar como projeto novo…`.
3. Confira o nome (vem `<projeto> — Base da acústica`) e `Criar projeto`. Precisa de conta e de rede: o projeto é criado na sua conta.
4. No aviso `Criei o projeto “…” com esta versão. Ele já está na sua lista de projetos.`, toque em `Abrir`.
5. Edite à vontade. O projeto novo é independente do original, sobe para a nuvem como qualquer projeto e começa **sem versões**. Os áudios não são copiados: os dois citam os mesmos, que ocupam a cota uma vez só.

## Variações

- **Um ensaio rápido, sem versão:** faça as mexidas, ouça e volte com o `Histórico` (toque em `Início do histórico` para desfazer tudo o que a sessão guarda). Serve enquanto você não fecha o projeto.
- **Menos automáticas:** no painel `Versões`, mude `a cada 15 min` para `a cada 60 min`, ou desligue `Salvar automaticamente` (desliga também a `Ao abrir o projeto`).
- **Levar uma versão para o celular:** `Duplicar como projeto novo…` e deixe o ícone de nuvem chegar a `Sincronizado`; o projeto novo aparece no outro aparelho. As versões em si não sincronizam ([Trabalhar em dois aparelhos](trabalhar-em-dois-aparelhos.md)).
- **Antes de um conflito de sincronização:** `Decidir depois` e `Salvar versão…` guardam o que está neste aparelho antes de você escolher o lado ([Trabalhar em dois aparelhos, passo 5](trabalhar-em-dois-aparelhos.md#5-resolver-um-conflito)). `(não confirmado com um conflito de verdade)`
- **Backup em arquivo:** a versão não vai dentro do `.jopendaw`; para o arquivo, use o [backup](backup-e-levar-projeto-para-outro-aparelho.md).

## Por que funciona

- O **histórico** guarda o projeto de antes de cada ação, com o nome e a hora dela; por isso tocar num passo leva direto àquele estado, e por isso ele é curto (200 passos) e de sessão.
- A **versão** é uma cópia do projeto inteiro (sem os áudios, que já estão guardados à parte pelo hash), então é pequena (da ordem de 10 KB num projeto pequeno) e dá para guardar muitas.
- **Restaurar é um passo do histórico** mais uma cópia de segurança: você pode voltar da restauração pelo `Ctrl+Z` e, se o histórico acabou, pela versão `Antes de restaurar`.
- Como as versões moram só no aparelho, nenhuma edição de outro aparelho as toca; o preço é que elas não viajam.

## Se der errado

| Sintoma | Causa provável | O que fazer |
|---|---|---|
| `O projeto está igual à versão mais nova: não guardei outra cópia idêntica.` | Você salvou sem mudar nada desde a versão mais nova | Nada: a versão que você queria já existe |
| O `Histórico` está vazio (`Nenhuma edição ainda…`) | O projeto acabou de abrir, ou a nuvem trocou o projeto por o de outro aparelho (aparece `Projeto atualizado de outro aparelho. Desfazer não disponível para o que veio de lá.`) | Use uma versão; o histórico só guarda o que você faz depois de abrir |
| Não há `Antes de restaurar` depois de restaurar | O projeto já era idêntico à versão mais nova, então a cópia de segurança seria duplicada | Procure a versão mais nova na lista: ela tem o que estava |
| A versão de ontem sumiu | Era automática e saiu da lista das 20 últimas | Da próxima vez, `Renomear…` ou `Salvar versão…` antes |
| `Pare a gravação antes de restaurar uma versão.` | Gravando, o desfazer e a restauração ficam parados | Pare a gravação e restaure de novo |
| `O arquivo desta versão está ilegível ou sumiu: não dá para restaurar.` | O arquivo da versão foi cortado ou apagado | Apague-a (`Limpar` no aviso de arquivos ilegíveis) e use outra |
| O painel avisa `As versões deste projeto já ocupam … (mais de 50,0 MB)` | As versões somam mais de 50 MB | `Apagar…` as que não precisa; nada foi bloqueado |
| O aparelho novo não mostra as versões | As versões não sobem para a nuvem | Faça `Duplicar como projeto novo…` no aparelho antigo |
| `Duplicar como projeto novo…` falha | Sem rede ou sem sessão (o projeto é criado pela API) | Volte à rede, entre na conta e tente de novo |
| `Ctrl+Shift+H` não abre o histórico | Em alguns navegadores a tecla é do próprio navegador `(não confirmado)` | Botão direito em `Desfazer` ou o menu `Visão` |
| Restaurei e o metrônomo ou o punch não voltaram | Preferências do aparelho e do gravar não fazem parte do passo | É assim de propósito: ajuste-os à mão |
