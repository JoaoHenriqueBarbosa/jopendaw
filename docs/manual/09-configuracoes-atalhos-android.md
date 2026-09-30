# Configurações, atalhos e Android

> Tudo o que se ajusta uma vez e se esquece: a janela `Configurações` (entrada de áudio, contagem, latência), a lista completa de atalhos de teclado, as permissões de microfone e MIDI, e o que muda entre usar o jopendaw no navegador ou no app Android.

## Onde fica

- **Configurações:** botão de engrenagem na barra de transporte (tooltip `Configurações: entrada de áudio, latência e contagem`), ou a seta ao lado do botão de gravar (`Opções de gravação`) e o item `Configurações de gravação…`.
- **Atalhos:** botão de teclado com o símbolo de comando na barra de transporte (tooltip `Atalhos do teclado (?)`), ou a tecla `?` com o estúdio em foco.
- **Permissões:** aparecem sozinhas na primeira vez que o app precisa do microfone ou do MIDI (ver abaixo).
- **Barra de transporte:** no computador fica no topo do projeto; no celular, embaixo ([capítulo 00](00-visao-geral.md)).

## Controles

### Janela `Configurações`

Abre com duas seções, `ENTRADA DE ÁUDIO` e `GRAVAÇÃO`, e um único botão `Fechar`. Ao abrir, a janela procura as entradas de áudio e, na web, é aí que o navegador pede permissão para o microfone. Se ninguém mais precisava do microfone, a entrada é fechada de novo ao terminar a procura.

**Seção `ENTRADA DE ÁUDIO`**

| Controle (rótulo exato) | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| Seletor de entrada | Escolhe de onde vem o áudio da gravação e do monitoramento | Primeiro item `Padrão do sistema` (ou `Padrão (<nome do aparelho>)` quando o navegador informa qual é a padrão); depois cada entrada pelo nome; sem permissão os nomes ficam escondidos e aparecem como `Entrada 1`, `Entrada 2`… | Trocar com uma faixa armada reabre a entrada na hora |
| Item `Entrada desconectada` | Aparece quando a entrada escolhida antes sumiu (cabo puxado, interface desligada) | Em vermelho: `A entrada escolhida não está conectada. Conecte de novo ou escolha outra.` | Se a escolhida não abrir, o app usa a padrão e avisa: `A entrada de áudio escolhida não abriu (foi desconectada?): usando a entrada padrão.` |
| Botão de atualizar (tooltip `Procurar as entradas de novo (depois de conectar um microfone ou interface)`) | Refaz a lista | Vira um círculo girando enquanto procura ou troca | Use depois de plugar um microfone ou interface |
| Texto de apoio | Estado da lista | `O navegador pede permissão para o microfone na primeira vez.`; `Nenhuma entrada encontrada. Conecte um microfone ou interface e toque em procurar.`; `Pare a gravação para trocar de entrada.` | O seletor fica desligado durante a gravação e enquanto procura |
| `Nível` | Barra horizontal com o nível de entrada | Texto: `Mexe enquanto a entrada está aberta: com uma faixa de áudio armada ou monitorando.` | Serve para acertar o ganho do microfone antes de gravar |
| Aviso vermelho | Erro ao procurar ou trocar a entrada | Mensagens na seção "Permissões" | |

A escolha da entrada é do **aparelho**: fica guardada nele e não vai para a nuvem nem muda ao abrir o mesmo projeto em outro aparelho.

**Seção `GRAVAÇÃO`**

| Controle (rótulo exato) | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| Interruptor `Contagem de um compasso` | Liga a contagem: o metrônomo conta um compasso antes de a gravação começar. Legenda: `O metrônomo conta um compasso antes de a gravação começar` | Padrão: ligado, em qualquer projeto novo | Mesmo controle do item `Contagem de um compasso` do menu `Opções de gravação`. Não entra no desfazer |
| Controle deslizante `Compensação de latência` | Ajusta o quanto o áudio gravado é deslocado para acertar a batida | De −200 a 500 ms, passos de 1 ms, padrão 0 ms | O número aparece sobre o controle enquanto se arrasta; só vale ao soltar |
| Campo numérico com o sufixo `ms` | O mesmo valor, digitado | Aceita dígitos e o sinal de menos (`-` ou `−`); fora da faixa mostra `De -200 a 500 ms` | Vale ao apertar `Enter`, ao sair do campo ou ao tocar em `Fechar` |
| Texto de apoio | Como usar | `Quanto o áudio gravado chega atrasado, além do que o navegador já informa: positivo adianta o que for gravado, negativo atrasa. Para medir, grave o metrônomo pelo microfone e ajuste até a batida gravada cair na grade.` | Um número inválido segura a janela aberta com o motivo à vista |
| `Fechar` | Fecha a janela | | Leva junto o número digitado e ainda não confirmado |

A contagem e a latência valem para **este projeto** (ficam no documento do projeto, e por isso sobem à nuvem), mas ao receber uma versão nova da nuvem cada aparelho mantém a sua. Nenhuma das duas entra no desfazer (é calibragem, não edição da música). Detalhes de como gravar: [capítulo 03c](03c-gravacao.md).

### Janela `Atalhos do teclado`

Abre com a tecla `?` (ou `Shift+/`) ou com o botão da barra. Tem um botão `Fechar`. Os títulos dos grupos aparecem em maiúsculas. Nesta tabela `Ctrl` vale para Windows, Linux e Chrome OS; no Mac (e no iOS) a mesma tecla é `⌘` (`Cmd`), e a janela já mostra o símbolo certo.

**Transporte**

| Tecla | Ação |
|---|---|
| `Espaço` | Tocar / pausar |
| `Enter` | Parar e voltar ao começo (ou ao início do loop) |
| `R` | Gravar (com faixas armadas) |
| `L` | Loop liga/desliga (arraste na régua para marcar a região) |
| `C` | Metrônomo |

**Marcadores e loop**

| Tecla | Ação |
|---|---|
| `M` | Marcador no cursor (`Shift+M`: pede o nome) |
| `[` / `]` | Cursor no marcador anterior / seguinte |
| `Shift+L` | Loop no clipe selecionado (ou na seção do cursor) |
| Arrastar · duplo clique | Move (com encaixe) · renomeia o marcador na régua |
| Botão direito | Menu do marcador: cor, loop da seção, apagar |
| Menu `Seções` | Lista de marcadores, loop entre marcadores e da seção |

**Visão**

| Tecla | Ação |
|---|---|
| `Z` | Enquadrar o projeto inteiro |
| `Shift+Z` | Enquadrar o clipe selecionado |
| Menu `Visão` | Altura das faixas (P/M/G), seguir o cursor, régua em mm:ss |
| Clique em `comp.` / `mm:ss` | Alterna a régua entre compassos e tempo |
| `Visão geral` (embaixo) | Clique ou arraste para rolar o projeto |

**Edição**

| Tecla | Ação |
|---|---|
| `Ctrl+Z` | Desfazer |
| `Ctrl+Shift+Z` ou `Ctrl+Y` | Refazer |
| `Ctrl+D` | Duplicar o clipe |
| `S` | Cortar no cursor |
| `Delete` | Apagar o clipe |
| `Ctrl+I` | Importar áudio |
| `+` / `−` | Aproximar / afastar |
| `Ctrl` + roda | Zoom no ponto do mouse |
| `Shift` + roda | Rolar na horizontal |

**Painéis**

| Tecla | Ação |
|---|---|
| `X` | Mixer |
| `E` | Editor de notas (piano roll) |
| `I` | Instrumento da faixa |
| `F` | Efeitos da faixa |
| `Esc` | Fechar o painel |
| `?` | Esta janela |

**Teclado do computador (`Ctrl+K` liga)**

| Tecla | Ação |
|---|---|
| `A W S E D F T G Y H U J K O L P` | Notas: do dó até o ré# da oitava de cima |
| `Z` / `X` | Oitava abaixo / acima (com o teclado ligado, o `Z` não enquadra) |
| `C` / `V` | Velocidade menor / maior |

**Piano roll**

| Tecla | Ação |
|---|---|
| Clique no vazio | Nova nota (arraste para a duração) |
| `Alt` ao arrastar | Sem grade; no começo do arraste, duplica |
| `Ctrl+A` · `Ctrl+C`/`X`/`V` · `Ctrl+D` | Tudo · copiar/recortar/colar no cursor · duplicar |
| `↑` `↓` (`Shift`: oitava) | Transpor |
| `←` `→` (`Shift`: compasso) | Mover pela grade |
| `Q` | Quantizar |
| `K` | Dividir as notas no cursor (a seleção, ou todas) |
| `J` | Unir notas iguais adjacentes |
| `Shift+H` | Humanizar com os últimos ajustes |
| `Shift+L` | Legato: cada nota vai até a próxima |
| Menu `Ferramentas` | Escala, acordes, arpejador, rampa de velocidade, inverter, escalar o tempo, fantasmas |

**O que a janela não lista, mas o código aceita**

| Tecla | Ação |
|---|---|
| `Home` | Igual a `Enter`: parar e voltar |
| `Backspace` | Igual a `Delete`: apagar o clipe selecionado |
| `=` (a tecla do sinal de igual, onde fica o `+` no teclado) e `+` do teclado numérico | Aproximar |
| `-` (a tecla do menos) e `-` do teclado numérico | Afastar |
| `Ctrl+K` | Liga/desliga o teclado do computador (só aparece no título do grupo) |

**Regras de prioridade (quando duas coisas usam a mesma tecla)**

- As teclas só valem com o foco no estúdio e **não** valem enquanto você digita num campo de texto.
- Com o **teclado do computador ligado**, as letras dele (`A W S E D F T G Y H U J K O L P`, mais `Z`, `X`, `C`, `V`) viram nota, oitava e velocidade e passam à frente dos outros atalhos: `S` (cortar), `E` (editor), `F` (efeitos), `L` (loop), `X` (mixer), `C` (metrônomo), `Z` (enquadrar), e no piano roll também `J`, `K` e `Shift+H`. `R`, `I`, `M`, `Espaço`, `Enter`, `Esc` e todos os atalhos com `Ctrl`/`⌘` continuam funcionando. Com `Ctrl`, `⌘` ou `Alt` apertados a letra deixa de ser nota.
- Os atalhos do **piano roll** só respondem depois que você clica dentro do editor (ele precisa ser o último lugar clicado); senão `Delete` e `Ctrl+D` continuam sendo do arranjo. `Shift+L` fora do editor faz o loop do clipe/seção; dentro dele, `Legato`.
- **Gravando**, `Ctrl+Z`, `Ctrl+Y` e `Ctrl+I` são engolidos (não fazem nada) para não apagar ou deslocar a faixa que está recebendo o áudio. `Ctrl+R` fica para o navegador.

### Permissões

| Permissão | Quando o app pede | Se você negar | Como liberar de novo |
|---|---|---|---|
| Microfone (web) | Ao abrir `Configurações`, ao armar uma faixa de áudio, ao ligar `Monitorar a entrada` ou ao gravar pela primeira vez | Mensagem: `O navegador negou o acesso ao microfone. Libere o microfone nas permissões do site e tente de novo.` A faixa que pediu volta a ficar desarmada | Cadeado ao lado do endereço, permissões do site, microfone |
| Microfone (Android) | Na mesma hora do uso (não ao abrir o app) | Negado uma vez: `O Android negou o acesso ao microfone. Para gravar, tente de novo e permita o acesso.` Bloqueado: `O acesso ao microfone está bloqueado para o jopendaw. Libere o microfone em Configurações > Apps > jopendaw > Permissões e tente de novo.` | Ajustes do Android, Apps, jopendaw, Permissões |
| MIDI (web) | Ao clicar no botão de cabo (tooltip `Entrada MIDI: ligar teclado ou controlador`) | `O navegador negou o acesso ao MIDI. Libere o MIDI nas permissões do site e tente de novo.` Sem suporte: `Este navegador não dá acesso a MIDI. Use o Chrome ou o Edge, com o jopendaw aberto em https.` | Permissões do site |
| MIDI (Android) | Ao clicar no mesmo botão | Sem MIDI no aparelho: `Este aparelho não dá acesso a MIDI.` Outra falha: `Não deu para abrir o MIDI: <motivo>.` | |

Outros avisos de entrada de áudio (web):

| Mensagem | Causa |
|---|---|
| `Este navegador não dá acesso ao microfone. Use um navegador atual, com o jopendaw aberto em https.` | Navegador sem suporte, ou página sem `https` |
| `Nenhuma entrada de áudio encontrada. Conecte um microfone ou uma interface de áudio e tente de novo.` | Nenhum microfone |
| `A entrada de áudio escolhida não está mais conectada. Escolha outra ou volte para a padrão.` | Aparelho sumiu |
| `A entrada de áudio está ocupada por outro programa ou não respondeu. Feche o que estiver usando ela e tente de novo.` | Outro programa usa o microfone |
| `A entrada de áudio está em <N> Hz e o motor em <M> Hz, e este navegador não converte. Ajuste a entrada para <M> Hz nas configurações de som do sistema.` | Taxas diferentes de entrada e saída |
| `A abertura da entrada de áudio foi cancelada.` | Fechada durante a abertura |

Depois de conectado, o botão de cabo mostra quantos aparelhos MIDI há (`0` ligado sem aparelho). Aparelhos plugados depois entram sozinhos na contagem.

## Web e Android

O app é o mesmo; o motor de áudio e o acesso ao aparelho é que mudam.

| Aspecto | Web (navegador) | Android (app) |
|---|---|---|
| Motor de áudio | Rust compilado para WebAssembly, dentro de um AudioWorklet | O mesmo Rust como biblioteca nativa (`libjopendaw_engine.so`), tocando pela saída do Android (AAudio/Oboe) |
| Onde ficam o documento e os áudios | IndexedDB do navegador (banco `jopendaw`, repositório `kv`), por site e perfil | Arquivos na pasta de documentos privada do app, subpasta `jopendaw/` (documento, estado de sincronização, áudios) |
| Onde ficam os tokens de sessão | Armazenamento local cifrado do navegador | Armazenamento seguro do Android (Keystore) |
| Entrar com Google/Discord | A página vai ao provedor e volta ao jopendaw | Uma aba do Chrome sobre o app; o Discord, com o app dele instalado, autoriza dentro dele |
| Link do email de entrada | Abre no navegador | Abre o app, se o Android confirmou o vínculo com o domínio; senão, o navegador |
| Microfone | Pedido do navegador, por site | Pedido do Android na hora de usar (`RECORD_AUDIO`) |
| MIDI | Web MIDI (Chrome e Edge) | USB e aparelhos que o Android já conhece (`android.media.midi`); conecta em todas as entradas, ignora aparelhos que só recebem |
| Exportar e salvar arquivos | Download do navegador | Janela de salvar do Android (`Salvar <nome>`); sem ela, a folha de compartilhar |
| Importar áudio | Seletor de arquivos do navegador | Seletor de arquivos do Android |
| Menu do botão direito | Usado pelo app nos clipes (o do navegador é desligado no projeto) | Não há botão direito; o toque longo faz o papel (não confirmado) |
| Teclado | Todos os atalhos | Só com teclado físico (não confirmado) |
| Instalar como app | Navegadores que oferecem instalar sites (o site tem manifesto `standalone` e abre a casca sem rede) | App do Android |
| Exigências | Navegador atual, `https` para gravar | Android 8.0 (API 26) ou mais novo; ABIs `arm64-v8a`, `armeabi-v7a` e `x86_64` |
| Ajustar áudio ao andamento (warp) | Progresso durante o processamento | Só avisa o fim (sem barra de progresso) |

**O que só existe num dos lados**

- Só no Android: a permissão `RECORD_AUDIO` em tempo de execução, a folha de compartilhar como plano B ao exportar e a autorização pelo app do Discord.
- Só na web: a instalação como app pelo navegador e a casca do app offline (`sw.js`).
- Em qualquer outro sistema (um build de computador nativo, testes) não há motor: a tela do projeto avisa `O motor de áudio ainda não roda neste aparelho: use o jopendaw no navegador por enquanto.`; a gravação, a exportação e o MIDI também respondem com "não funciona neste sistema: use o jopendaw no navegador ou no Android".

Existe código de plataforma para manter a tela acesa durante a reprodução, parar o transporte ao sair do app e ao desplugar o fone, mas ele **não está ligado ao estúdio** nesta versão (lido no código; não confirmado em uso): não conte com a tela permanecendo acesa nem com o transporte parando sozinho.

## Instalação do app Android

**Requisitos:** Android 8.0 (API 26) ou mais novo, em aparelho `arm64-v8a`, `armeabi-v7a` ou `x86_64`. Pacote: `tech.johnenrique.jopendaw`. O app precisa de internet (só HTTPS) e pede o microfone só quando você usa a gravação. Bluetooth e USB MIDI são usados quando existem, nunca exigidos.

**Instalar**

1. Baixe o app. O repositório não fixa um canal de distribuição (há uma conta de demonstração pensada para a revisão da Play Store, então a publicação lá é prevista, mas não confirmada). Sem loja, use o arquivo `.apk`.
2. Para instalar um `.apk` fora da loja, o Android pede para permitir "instalar apps desconhecidos" para o app que o abriu (navegador ou gerenciador de arquivos). Permita, abra o arquivo e toque em `Instalar`. Com o cabo e o `adb`: `adb install -r app-release.apk`.
3. Abra o jopendaw e entre (link no email, Google, Discord ou código de acesso). Ele fala por padrão com o servidor de produção (`https://jopendaw.johnenrique.tech`).
4. Abra ou crie um projeto. Na primeira gravação, o Android pede o microfone.

**Para quem compila:** `cd app && flutter build apk --release -PdiscordClientId=<id>` (o `<id>` é o id do app do Discord, o mesmo `DISCORD_CLIENT_ID` do servidor; sem ele o valor é `0` e a volta da autorização pelo app do Discord não funciona). O `.apk` sai no caminho padrão do Flutter, `app/build/app/outputs/flutter-apk/app-release.apk` (não confirmado). A chave de assinatura de release fica fora do repositório (`android/key.properties` ou `~/.config/jopendaw/android-release.properties`); sem ela o release sai com a chave de debug, que instala e roda, mas não abre os links do email dentro do app. Se mudar o motor de áudio, recompile os `.so` antes (`./engine/build-android.sh`); o passo a passo técnico está em [dev/03](../dev/03-build-teste-e-depuracao.md).

## Passo a passo

**Gravar com o microfone certo**

1. Abra `Configurações` (engrenagem da barra). Permita o microfone quando o navegador ou o Android pedir.
2. No seletor de entrada, escolha o microfone ou a interface. Se acabou de plugar, toque no botão de atualizar.
3. Fale ou toque e veja a barra `Nível` andar; ajuste o ganho no próprio aparelho até ela subir sem passar do fim.
4. Toque em `Fechar`.

**Calibrar a latência da gravação**

1. Ligue o metrônomo (`C`) e arme uma faixa de áudio; ponha o microfone perto do alto-falante ou use um cabo de retorno.
2. Grave alguns compassos só com o clique.
3. Olhe onde a batida gravada caiu em relação à grade. Em `Configurações`, mova `Compensação de latência` (positivo adianta o gravado, negativo atrasa) e grave de novo.
4. Repita até a batida gravada cair na grade. O valor fica no projeto.

**Ligar ou desligar a contagem**

1. Abra a seta ao lado do botão de gravar (`Opções de gravação`).
2. Marque ou desmarque `Contagem de um compasso`. O mesmo interruptor existe em `Configurações`.

**Ligar um teclado MIDI**

1. Conecte o teclado (USB, ou Bluetooth já pareado no Android).
2. Toque no botão de cabo da barra. Permita o MIDI se o navegador perguntar.
3. Confira o número ao lado do cabo (`1` para um aparelho) e toque na faixa de instrumento: as notas tocam a faixa selecionada, ou a armada.

**Consultar os atalhos**

1. Aperte `?` ou o botão de atalhos da barra.
2. Role a lista, e feche em `Fechar`.

## Combina com

- [00 Visão geral](00-visao-geral.md): onde fica cada botão citado aqui.
- [03c Gravação](03c-gravacao.md): usar a entrada, a contagem e a latência numa tomada de verdade.
- [02 Transporte](02-transporte.md): metrônomo, loop e o menu `Opções de gravação`.
- [05 Piano roll](05-piano-roll.md) e [05b Ferramentas MIDI](05b-ferramentas-midi.md): os atalhos do grupo `Piano roll`.
- [01b Nuvem e sincronização](01b-nuvem-e-sincronizacao.md): o que sobe e o que fica só no aparelho.
- [08 Exportação](08-exportacao.md): salvar arquivos na web e no Android.

## Limites e pegadinhas

- **A janela `Configurações` fala em "navegador" também no Android.** O texto `O navegador pede permissão para o microfone na primeira vez.` e a explicação da latência ("além do que o navegador já informa") aparecem iguais no app; no Android leia "sistema" onde estiver "navegador".
- **A entrada de áudio é do aparelho; a latência e a contagem são do projeto.** Se você calibrar a latência num aparelho e abrir o projeto em outro, a versão da nuvem não troca o valor de cada aparelho, então calibre em cada um.
- **A latência está limitada a −200 a 500 ms.** O valor é guardado no projeto e entra na sincronização, mas não no desfazer.
- **Trocar a entrada no meio da gravação não é permitido:** o seletor fica desligado e o texto pede `Pare a gravação para trocar de entrada.`
- **Os tooltips da barra escrevem `Ctrl` em qualquer sistema**, mesmo no Mac, onde a tecla é `Cmd`. A janela de atalhos mostra o símbolo certo.
- **Um atalho que "não pega"** costuma ser: campo de texto com foco, teclado do computador ligado (as letras viram notas), ou o piano roll sem ter sido o último lugar clicado.
- **Tela apagando ou transporte que continua ao sair do app no Android:** não há tratamento de sessão de áudio ligado ao estúdio (ver acima); não confirmado em uso.
- **`Esc` fecha o painel de baixo**, mas se o editor tiver notas selecionadas o primeiro `Esc` só limpa a seleção.

## Atalhos

Os atalhos deste assunto:

| Tecla | Ação |
|---|---|
| `?` | Abrir a janela `Atalhos do teclado` |
| `Ctrl+K` (`⌘K` no Mac) | Ligar/desligar o teclado do computador |
| `R` | Gravar |
| `C` | Metrônomo (com o teclado do computador ligado, vira "velocidade menor") |
| `Esc` | Fechar o painel de baixo |
| `Enter` no campo de latência | Confirmar o número digitado |
