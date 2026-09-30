# Projetos, modelos e conta

> Como entrar no jopendaw, criar, renomear e apagar projetos, o que cada um dos três modelos monta de saída, e o que a tela `Conta` faz. É o primeiro capítulo prático: em dois minutos você tem um projeto tocando.

## Onde fica

- **Entrar:** é a primeira tela quando não há sessão (`/login`). Qualquer endereço do app sem sessão cai aqui e, depois de entrar, você volta para onde ia.
- **Projetos:** botão `Projetos` do rail lateral (computador, 800 px ou mais) ou da barra inferior (celular). É a tela inicial depois de entrar.
- **Conta:** botão `Conta` do mesmo rail ou barra.
- **Novo projeto:** botão `Novo projeto` na barra da página (computador) ou botão flutuante (celular). Quando a lista está vazia há também `Criar o primeiro`.

## Controles

### Tela `Entrar`

O cabeçalho mostra a marca, `jopendaw` e a frase `Grave, arranje e mixe, no navegador ou no celular.`. Não há senha: a conta é criada na primeira entrada.

| Controle (rótulo exato) | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| `Continuar com o Google` | Entra com a conta do Google | Só aparece se o servidor tiver o Google ligado | O texto acima muda para `Sem senha: com a sua conta do Google ou do Discord, ou com um link no seu email.` conforme os provedores ligados |
| `Continuar com o Discord` | Entra com a conta do Discord | Só aparece se o servidor tiver o Discord ligado | No Android, com o app do Discord instalado, autoriza dentro dele; sem o app, abre uma aba do Chrome |
| `ou pelo email` | Divisor entre os provedores e o campo de email | Só aparece com algum provedor ligado | |
| Campo `Email` | O email que vai receber o link | Precisa ter `@` | `Enter` envia. Em telas com menos de 600 px o campo não pega o foco sozinho (o teclado cobriria os botões) |
| `Receber link de entrada` | Manda o link de entrada para o email | O link vale por 15 minutos e só funciona uma vez | Gira o ícone de envio enquanto manda |
| `Tenho um código de acesso` | Abre o diálogo `Código de acesso` | Serve à conta de demonstração da revisão da Play Store | Sem a conta de demonstração ligada no servidor, o código sempre é recusado |
| `Política de privacidade` e `Termos de uso` | Abrem as páginas fora do app | | Também na tela `Conta` |

Diálogo `Código de acesso`:

| Controle | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| Campo `Email` | O email da conta de demonstração | | |
| Campo `Código` | O código de acesso | Texto oculto | `Enter` confirma |
| `Cancelar` | Fecha sem entrar | | |
| `Entrar` | Entra (ignora se um dos dois campos está vazio) | | Erro: `Email ou código de acesso não conferem.` |

Depois de pedir o link, a tela vira `Confira o seu email`:

| Controle | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| Texto `Mandamos um link de entrada para <email>. Ele vale por 15 minutos e só funciona uma vez.` | Confirma o envio | | Se já abriu o link em outra aba, esta tela entra junto (confere a cada 2 segundos) |
| `Mandar de novo` | Pede outro link para o mesmo email | Limite de 5 pedidos por email e 30 por IP por hora | Estourou: `Muitas tentativas; aguarde.` |
| `Usar outro email` | Volta ao formulário | | |

O link do email abre `/entrar?token=…`. Essa tela mostra `Entrando…` e leva para `Projetos`. Se o link não serve:

| Mensagem | Quando | Botão |
|---|---|---|
| `Esse link está incompleto. Copie o endereço inteiro do email.` | O endereço veio sem o token | `Pedir um link novo` |
| `Esse link já foi usado ou venceu. Peça outro.` | Já usado ou passou de 15 minutos | `Pedir um link novo` (ou `Ir para os projetos` se já há sessão) |
| `Não deu para abrir o link: <motivo>.` | O servidor recusou | idem |
| `Sem conexão com o servidor. Tente de novo.` | Sem rede | idem |

Mensagens de erro do login com Google/Discord:

| Mensagem | Quando |
|---|---|
| `Não deu para abrir a entrada pelo <provedor>. Tente de novo ou entre pelo link do email.` | A aba do provedor não abriu |
| `A entrada pelo <provedor> demorou demais e venceu. Tente de novo.` | A volta chegou tarde |
| `A sua conta do <provedor> não tem um email verificado. Verifique o email lá, ou entre pelo link do email aqui.` | O provedor não deu um email verificado |
| `A entrada começou em outro navegador. Tente de novo por aqui.` | Na web, a volta caiu num navegador que não iniciou a entrada |
| `Não deu para entrar pelo <provedor> agora. Tente de novo ou entre pelo link do email.` | Qualquer outra falha |
| `Não deu para mandar o email agora. Tente de novo em instantes.` | Falha do servidor ao mandar o link |
| `Digite o seu email.` | O campo não tem `@` |

### Tela `Projetos`

O título é `Projetos`; embaixo, o total (`1 projeto`, `3 projetos`). Os cards ficam numa grade que se adapta à largura (colunas de até 360 px; uma coluna no celular), do mais recentemente mexido para o mais antigo. Puxar a lista para baixo recarrega.

| Controle (rótulo exato) | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| `Novo projeto` | Abre o diálogo `Novo projeto` | Fica desligado enquanto uma ação roda | |
| `Criar o primeiro` | Mesmo diálogo, na lista vazia | Aparece com o título `Nenhum projeto ainda` e o texto `Um projeto guarda as faixas, os clipes e a mixagem de uma música.` | |
| Card do projeto | Clicar abre o projeto (estúdio) | Mostra o nome, `120 BPM · 4/4 · 48.0 kHz` e `Mexido agora` / `Mexido há N min` / `Mexido há N h` / `Mexido dd/mm` | O `kHz` é o cadastrado no servidor (48.0 nos projetos criados pelo app) |
| Menu `Mais` (três pontos do card) | `Renomear` e `Apagar` | | |
| `Renomear` | Abre `Renomear projeto` (campo `Nome`, botão `Salvar`) | Até 120 caracteres | Só salva se o nome mudou e não ficou vazio |
| `Apagar` | Pede confirmação: `Apagar "<nome>"?` / `O projeto some para sempre, com tudo o que estiver nele.` | Botões `Cancelar` e `Apagar` (vermelho) | Depois: `Projeto apagado.` |
| `Tentar de novo` | Recarrega a lista quando deu erro | Erro na tela: `Não deu para carregar` | Sem rede: `Sem conexão com o servidor. Tente de novo.` |

Diálogo `Novo projeto`:

| Controle | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| Campo `Nome` | O nome do projeto | Até 120 caracteres; vazio dá `Dê um nome ao projeto.` | `Enter` cria |
| `Começar com` (três blocos) | Escolhe o modelo | `Vazio`, `Batida eletrônica`, `Gravação de banda`; o padrão marcado é `Batida eletrônica` | O bloco marcado leva um contorno ciano e um visto |
| `Cancelar` | Fecha | | |
| `Criar` | Cria e abre o projeto | | Precisa de rede: o cadastro do projeto é no servidor |

Todo projeto nasce com **120 BPM, compasso 4/4 e 48.0 kHz**; o app não pergunta nada disso ao criar. O andamento e o compasso se mudam depois, na barra do estúdio ([capítulo 02](02-transporte.md)).

### Os três modelos

O modelo só monta o documento na **primeira abertura** do projeto, no aparelho onde ele foi criado. As posições são em batidas, então valem em qualquer andamento. Os timbres são presets do próprio app.

#### `Vazio`

Descrição na tela: `Uma faixa de áudio, pronta para importar ou gravar`.

| Item | O que vem |
|---|---|
| Faixas | Uma: `Áudio 1` (áudio, cor ciano), sem clipes, sem efeitos |
| Loop | Região de 0 a 4 compassos (16 batidas em 4/4) definida, mas **desligado** |
| Metrônomo | Desligado |
| Contagem | Ligada (é o padrão de todo documento) |
| Andamento | 120 BPM |

Os dois outros modelos também deixam a contagem ligada.

#### `Batida eletrônica`

Descrição na tela: `Bateria 808, baixo, pad e um reverb em barramento, tocando em loop`.

Loop **ligado**, de 0 a 4 compassos (16 batidas em 4/4); metrônomo desligado. Quatro faixas, nesta ordem:

| Faixa | Tipo e cor | Timbre | Volume | Envio para `Reverb` | Clipe (4 compassos) |
|---|---|---|---|---|---|
| `Bateria` | `Bateria`, lilás | Kit `808` | 0 dB (padrão) | 0,12 (cerca de −18,4 dB) | `Batida`: 88 notas |
| `Baixo` | `Sintetizador`, amarelo | Preset `Baixo sub` | 0,8 (cerca de −1,9 dB) | nenhum | `Baixo`: 16 notas |
| `Pad` | `Sintetizador`, salmão | Preset `Pad quente` | 0,55 (cerca de −5,2 dB) | 0,45 (cerca de −6,9 dB) | `Acordes`: 12 notas |
| `Reverb` | `Barramento`, azul | Um efeito `Reverb`, preset `Sala` | 0 dB | | Sem clipes |

O que toca:

- **Bateria:** bumbo (nota 36) em todas as batidas; `Palmas` (39) na 2ª e na 4ª batida do compasso; chimbal aberto (46) no contratempo de cada batida; chimbal fechado (42) na 1ª, 2ª e 4ª semicolcheia de cada batida, com a primeira mais forte.
- **Baixo:** uma nota por batida, no contratempo (colcheia), na raiz do acorde: `A2`, `F2`, `C3`, `G2` (um compasso cada).
- **Pad:** acordes de um compasso inteiro: `Am` (A3 C4 E4), `F` (F3 A3 C4), `C` (G3 C4 E4) e `G` (G3 B3 D4). A progressão é lá menor, fá, dó, sol.
- **Reverb:** o efeito com `Mistura` em 100% (o som seco vem das faixas, pelos envios) e os valores do preset `Sala`: `Pré-atraso` 0,015 s, `Tamanho` 50%, `Decaimento` 1,4 s, `Abafar` 7500 Hz, `Cortar graves` 120 Hz, `Largura` 90%, `Modulação` 30%, `Primeiras reflexões` 55%.

#### `Gravação de banda`

Descrição na tela: `Faixas de voz, violão, baixo e bateria, com metrônomo, contagem e reverb`.

Metrônomo **ligado**, contagem ligada, loop desligado (região de 0 a 4 compassos já marcada). Cinco faixas, sem nenhum clipe e **nenhuma armada**:

| Faixa | Tipo e cor | Envio para `Reverb` |
|---|---|---|
| `Voz` | `Áudio`, ciano | 0,3 (cerca de −10,5 dB) |
| `Violão` | `Áudio`, amarelo | 0,2 (cerca de −14,0 dB) |
| `Baixo` | `Áudio`, verde | Envio criado com nível 0: não manda som ao reverb até você subir |
| `Bateria` | `Bateria`, lilás, kit `Acústico eletrônico` | 0,1 (−20 dB) |
| `Reverb` | `Barramento`, azul, efeito `Reverb` com preset `Placa` | |

O `Reverb` daqui tem `Mistura` em 100% e os valores do preset `Placa`: `Pré-atraso` 0,01 s, `Tamanho` 55%, `Decaimento` 1,8 s, `Abafar` 12000 Hz, `Cortar graves` 200 Hz, `Largura` 100%, `Modulação` 45%, `Primeiras reflexões` 15%. A `Bateria` vem sem notas: escreva no piano roll ou grave por MIDI.

### Tela `Conta`

O título é `Conta` e o subtítulo, o seu email.

| Controle (rótulo exato) | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| Linha com o nome (`Sem nome` se ainda não há) e a legenda `Nome` | Clicar abre `Seu nome` (campo `Nome`, `Cancelar`, `Salvar`) | Até 80 caracteres, sem quebra de linha | Depois: `Nome salvo.` |
| Linha `Email` | Mostra o email da conta | Só leitura | Não dá para trocar o email aqui |
| `Sair` | Encerra a sessão neste aparelho | Sem confirmação | Volta ao login |
| `Sair de todos os aparelhos` | Encerra todas as sessões da conta, inclusive esta | Pede `Sair de todos os aparelhos?` / `Todas as sessões desta conta são encerradas, inclusive esta.`; botões `Cancelar` e `Sair de todos` | Use se perdeu um aparelho |
| `Apagar a conta` (vermelho) | Apaga a conta e tudo o que há nela | Pede `Apagar a conta?` / `A conta e todos os projetos dela somem para sempre. Não tem volta.`; botões `Cancelar` e `Apagar a conta` | Leva junto os projetos, os áudios e as tarefas no servidor |
| `Política de privacidade` · `Termos de uso` | Abrem as páginas fora do app | | |

A sessão dura até 30 dias sem uso e, no máximo, 90 dias de qualquer forma; o acesso é renovado sozinho a cada 15 minutos, sem você ver.

## Passo a passo

**Entrar pela primeira vez (link no email)**

1. Digite o email no campo `Email` e toque em `Receber link de entrada`.
2. Abra o email e toque no link. Ele abre no navegador (ou, no Android, no app) e a tela `Entrando…` leva a `Projetos`.
3. Se abriu o link em outra aba, a aba do login entra junto sozinha.

**Entrar com Google ou Discord**

1. Toque em `Continuar com o Google` ou `Continuar com o Discord`.
2. Autorize na tela do provedor. No navegador a página sai e volta; no Android a autorização abre por cima do app e fecha sozinha.
3. Se desistir, você volta ao login sem mensagem de erro.

**Criar um projeto a partir de um modelo**

1. Em `Projetos`, toque em `Novo projeto`.
2. Digite o `Nome` e escolha o modelo em `Começar com`.
3. Toque em `Criar`. O estúdio abre com o modelo montado.
4. Ajuste o andamento em `120 BPM · 4/4` na barra do estúdio, se precisar.

**Renomear ou apagar**

1. No card, abra o menu `Mais`.
2. `Renomear` pede o novo nome; `Apagar` pede confirmação.
3. Depois de apagar, aparece `Projeto apagado.` e a lista recarrega.

**Sair de todos os aparelhos**

1. Abra `Conta` e toque em `Sair de todos os aparelhos`.
2. Confirme em `Sair de todos`. Você cai no login; nos outros aparelhos a sessão acaba na próxima chamada.

## Combina com

- [00 Visão geral](00-visao-geral.md): o mapa do estúdio que abre depois de criar o projeto.
- [01b Nuvem e sincronização](01b-nuvem-e-sincronizacao.md): o que acontece com o projeto ao mudar de aparelho.
- [04 Painel de instrumento](04-painel-de-instrumento.md) e [04b Bateria](04b-bateria.md): para mexer nos timbres que o modelo `Batida eletrônica` monta.
- [06 Mixer](06-mixer.md): os envios e o barramento `Reverb` dos modelos.
- [03c Gravação](03c-gravacao.md): usar as faixas armáveis do modelo `Gravação de banda`.

## Limites e pegadinhas

- **Criar, renomear e apagar precisam de rede**: a lista de projetos vem do servidor. Sem rede a tela `Projetos` mostra o erro com `Tentar de novo`. Já dentro de um projeto aberto, a edição segue funcionando ([capítulo 01b](01b-nuvem-e-sincronizacao.md)).
- **O modelo é aplicado só uma vez, no aparelho que criou o projeto.** A escolha fica guardada no aparelho até a primeira abertura. Se você abrir o projeto recém-criado antes em outro aparelho, ele começa como o `Vazio` (uma faixa `Áudio 1`); o modelo só vira documento quando o aparelho que criou abrir o projeto. Evite editar no outro aparelho antes disso, senão os dois lados terão mudado e aparecerá o diálogo de conflito ([capítulo 01b](01b-nuvem-e-sincronizacao.md)).
- **Apagar o projeto apaga só o cadastro e o documento no servidor.** O código do app não remove a cópia local do documento nem dos áudios no aparelho, e os áudios enviados continuam contando na cota da conta ([capítulo 01b](01b-nuvem-e-sincronizacao.md)).
- **`Mexido ...` no card** acompanha o servidor: só muda quando o documento é enviado (ou o nome, alterado). Uma edição que ainda não sincronizou não atualiza o card.
- O `Email` da conta não pode ser trocado na tela `Conta`.
- `Sair` encerra a sessão, mas não apaga do aparelho os projetos e áudios já guardados: eles continuam lá e voltam a valer quando a conta entrar de novo.
- Os nomes de projeto não precisam ser únicos.

## Atalhos

Nestas telas só há o `Enter`:

| Tecla | Ação |
|---|---|
| `Enter` no campo `Email` | Receber link de entrada |
| `Enter` no campo `Código` | Entrar com o código de acesso |
| `Enter` no campo `Nome` (novo projeto, renomear, seu nome) | Confirmar |
