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
| Texto de apoio | Estado da lista | Na web: `O navegador pede permissão para o microfone na primeira vez.` No Android: `O Android pede permissão para o microfone na primeira vez.` Nos dois: `Nenhuma entrada encontrada. Conecte um microfone ou interface e toque em procurar.`; `Pare a gravação para trocar de entrada.` | O seletor fica desligado durante a gravação e enquanto procura |
| `Nível` | Barra horizontal com o nível de entrada | Texto: `Mexe enquanto a entrada está aberta: com uma faixa de áudio armada ou monitorando.` | Serve para acertar o ganho do microfone antes de gravar |
| Aviso vermelho | Erro ao procurar ou trocar a entrada | Mensagens na seção "Permissões" | |

A escolha da entrada é do **aparelho**: fica guardada nele e não vai para a nuvem nem muda ao abrir o mesmo projeto em outro aparelho.

**Seção `GRAVAÇÃO`**

| Controle (rótulo exato) | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| Interruptor `Contagem de um compasso` | Liga a contagem: o metrônomo conta um compasso antes de a gravação começar. Legenda: `O metrônomo conta um compasso antes de a gravação começar` | Padrão: ligado, em qualquer projeto novo | Mesmo controle do item `Contagem de um compasso` do menu `Opções de gravação`. Não entra no desfazer |
| Controle deslizante `Compensação de latência` | Ajusta o quanto o áudio gravado é deslocado para acertar a batida | De −200 a 500 ms, passos de 1 ms, padrão 0 ms | O número aparece sobre o controle enquanto se arrasta; só vale ao soltar |
| Campo numérico com o sufixo `ms` | O mesmo valor, digitado | Aceita dígitos e o sinal de menos (`-` ou `−`); fora da faixa mostra `De -200 a 500 ms` | Vale ao apertar `Enter`, ao sair do campo ou ao tocar em `Fechar` |
| Texto de apoio | Como usar | `Quanto o áudio gravado chega atrasado, além do que o navegador já informa: positivo adianta o que for gravado, negativo atrasa. Para medir, grave o metrônomo pelo microfone e ajuste até a batida gravada cair na grade.` No Android, onde está "o navegador" o texto diz `o sistema` | Um número inválido segura a janela aberta com o motivo à vista |
| `Fechar` | Fecha a janela | | Leva junto o número digitado e ainda não confirmado |

A contagem e a latência valem para **este projeto** (ficam no documento do projeto, e por isso sobem à nuvem), mas ao receber uma versão nova da nuvem cada aparelho mantém a sua. Nenhuma das duas entra no desfazer (é calibragem, não edição da música). Detalhes de como gravar: [capítulo 03c](03c-gravacao.md).

### Janela `Atalhos do teclado`

Abre com a tecla `?` (ou `Shift+/`) ou com o botão da barra. Tem um botão `Fechar`. Os títulos dos grupos aparecem em maiúsculas. Nesta tabela `Ctrl` vale para Windows, Linux e Chrome OS; no Mac (e no iOS) a mesma tecla é `⌘` (`Cmd`), e a janela já mostra o símbolo certo (`⌘+Z`). A tabela abaixo foi conferida contra `app/lib/daw/shortcuts_dialog.dart` e `app/lib/screens/project_screen.dart` na versão `15670b7`; a janela tem 8 grupos.

**Transporte**

| Tecla | Ação |
|---|---|
| `Espaço` | Tocar / pausar |
| `Enter` · `Home` | Parar e voltar ao começo (ou ao início do loop) |
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
| Menu `Visão` | Altura das faixas (pequena, média, grande), seguir o cursor, régua em mm:ss |
| Clique em `comp.` / `mm:ss` | Alterna a régua entre compassos e tempo |
| `Visão geral` (embaixo) | Clique ou arraste para rolar o projeto |

**Edição**

| Tecla | Ação |
|---|---|
| `Ctrl+Z` | Desfazer |
| `Ctrl+Shift+Z` ou `Ctrl+Y` | Refazer |
| `Ctrl+D` | Duplicar o clipe |
| `S` | Cortar no cursor |
| `Delete` · `Backspace` | Apagar o clipe |
| `Ctrl+I` | Importar áudio (a janela de atalhos diz só isso, mas o atalho abre o mesmo seletor do botão, que também aceita arquivos MIDI `.mid` e `.midi`) |
| `=` ou `+` / `−` | Aproximar / afastar |
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

O título do grupo escreve o modificador do sistema (`⌘+K liga` no Mac).

| Tecla | Ação |
|---|---|
| `A W S E D F T G Y H U J K O L P` | Notas: do dó até o ré# da oitava de cima |
| `Z` / `X` | Oitava abaixo / acima (só da faixa que está tocando: a bateria começa no C2) |
| `C` / `V` | Velocidade menor / maior |

**Suspensos enquanto o teclado do computador está ligado**

Grupo novo: lista os atalhos de letra que deixam de agir (a letra vira nota, oitava ou velocidade) até o teclado ser desligado. Vem do valor `suspendedShortcuts` do código, e um teste confere que cada letra listada é mesmo uma tecla do teclado musical.

| Tecla | Ação suspensa (e no que a tecla se transforma) |
|---|---|
| `C` | Metrônomo (vira velocidade menor) |
| `L` | Loop liga/desliga (vira nota) |
| `S` | Cortar no cursor (vira nota) |
| `X` | Mixer (vira oitava acima) |
| `Z` · `Shift+Z` | Enquadrar projeto / clipe (vira oitava abaixo) |
| `E` | Editor de notas (vira nota) |
| `F` | Efeitos da faixa (vira nota) |
| `K` · `J` | Dividir / unir notas no piano roll (viram nota) |
| `Shift+H` · `Shift+L` | Humanizar e legato no piano roll; `Shift+L` também faz o loop no clipe (viram nota) |
| Com `Ctrl` (`⌘`) | Os atalhos com `Ctrl` continuam valendo (desfazer, duplicar, importar; `Ctrl+K` desliga o teclado) |

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

**O que a janela ainda não lista, mas o código aceita**

| Tecla | Ação |
|---|---|
| `+` e `−` do teclado numérico | Aproximar / afastar (o `=` e o `-` do teclado principal estão na janela) |
| `+` do teclado principal (`Shift` + `=`) | A janela escreve `=` ou `+`, mas o código só compara com a tecla `=` e com o `+` do teclado numérico; se `Shift` + `=` vale como `=` no navegador, funciona `(não confirmado)` |
| `Ctrl+K` | Liga/desliga o teclado do computador (aparece só no título do grupo e nos tooltips) |

**Regras de prioridade (quando duas coisas usam a mesma tecla)**

- As teclas só valem com o foco no estúdio e **não** valem enquanto você digita num campo de texto.
- Com o **teclado do computador ligado**, as letras dele (`A W S E D F T G Y H U J K O L P`, mais `Z`, `X`, `C`, `V`) viram nota, oitava e velocidade e passam à frente dos outros atalhos; a lista exata do que fica suspenso é o grupo acima (`C`, `L`, `S`, `X`, `Z`, `E`, `F`, e no piano roll `K`, `J` e `Shift+H`/`Shift+L`). `R`, `I`, `M`, `Espaço`, `Enter`, `Home`, `Esc` e todos os atalhos com `Ctrl`/`⌘` continuam funcionando. Com `Ctrl`, `⌘` ou `Alt` apertados a letra deixa de ser nota. Na barra, o botão do teclado avisa o estado: fica com o rótulo `C4 · sem atalhos` (a oitava e o aviso) e o tooltip lista os atalhos suspensos.
- **A oitava do teclado é uma por tipo de faixa.** O botão mostra a oitava da faixa que ele toca (a selecionada, ou a primeira faixa de instrumento armada). Cada tipo (áudio, sintetizador, bateria, sampler, FM, wavetable) guarda a sua; todas partem de `C4` (a tecla `A` é o dó central, nota 60), menos a bateria, que parte de `C2` (a tecla `A` toca a nota 36, o `Bumbo`, porque a bateria só responde às notas 35 a 59). Mudar a oitava numa bateria não muda a do sintetizador, e vice-versa; ao trocar de faixa o botão passa a mostrar a oitava do tipo novo. A oitava vai de 0 a 8 e não é gravada no projeto (volta ao padrão ao reabrir o projeto).
- Os atalhos do **piano roll** só respondem depois que você clica dentro do editor (ele precisa ser o último lugar clicado); senão `Delete` e `Ctrl+D` continuam sendo do arranjo. `Shift+L` fora do editor faz o loop do clipe/seção; dentro dele, `Legato`.
- **Gravando**, `Ctrl+Z`, `Ctrl+Y` e `Ctrl+I` são engolidos (não fazem nada) para não apagar ou deslocar a faixa que está recebendo o áudio. `Ctrl+R` fica para o navegador.
- **Tooltips e menus usam o símbolo do sistema.** Os textos `Desfazer (Ctrl+Z)`, `Refazer (Ctrl+Shift+Z)`, `Duplicar (Ctrl+D)`, `Importar áudio ou MIDI (Ctrl+I)`, o tooltip do teclado (`Ctrl+K`), o atalho do item `Duplicar` do menu do clipe e a ajuda do piano roll passam por `withMod` (`app/lib/widgets/format.dart`): no Mac e no iOS o `Ctrl` vira `⌘` (`⌘+Z`), nos outros continua `Ctrl`.

### Permissões

| Permissão | Quando o app pede | Se você negar | Como liberar de novo |
|---|---|---|---|
| Microfone (web) | Ao abrir `Configurações`, ao armar uma faixa de áudio, ao ligar `Monitorar a entrada` ou ao gravar pela primeira vez | Mensagem: `O navegador negou o acesso ao microfone. Libere o microfone nas permissões do site e tente de novo.` A faixa que pediu volta a ficar desarmada | Cadeado ao lado do endereço, permissões do site, microfone |
| Microfone (Android) | Na mesma hora do uso (não ao abrir o app) | Negado uma vez: `O Android negou o acesso ao microfone. Permita o microfone para o jopendaw e tente de novo.` Negado de vez ou restrito: `O Android negou o acesso ao microfone de vez: libere o microfone nas permissões do jopendaw (Configurações › Apps › jopendaw › Permissões) e tente de novo.` | Ajustes do Android, Apps, jopendaw, Permissões |
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
| Motor de áudio | Rust compilado para WebAssembly, dentro de um AudioWorklet | O mesmo Rust como biblioteca nativa (`libjopendaw_engine.so`), tocando pela saída do Android (AAudio) |
| Onde ficam o documento e os áudios | IndexedDB do navegador (banco `jopendaw`, repositório `kv`), por site e perfil | Arquivos na pasta de documentos privada do app, subpasta `jopendaw/` (documento, estado de sincronização, áudios) |
| Onde ficam os tokens de sessão | Armazenamento local cifrado do navegador | Armazenamento seguro do Android (Keystore) |
| Entrar com Google/Discord | A página vai ao provedor e volta ao jopendaw | Uma aba do Chrome sobre o app; o Discord, com o app dele instalado, autoriza dentro dele |
| Link do email de entrada | Abre no navegador | Abre o app, se o Android confirmou o vínculo com o domínio; senão, o navegador |
| Microfone | Pedido do navegador, por site | Pedido do Android na hora de usar (`RECORD_AUDIO`) |
| MIDI | Web MIDI (Chrome e Edge) | USB e aparelhos que o Android já conhece (`android.media.midi`); conecta em todas as entradas, ignora aparelhos que só recebem |
| Exportar e salvar arquivos | Download do navegador | Janela de salvar do Android (`Salvar <nome>`); sem ela, a folha de compartilhar |
| Importar áudio ou MIDI (`.mid`) | Seletor de arquivos do navegador | Seletor de arquivos do Android |
| Exportar notas em MIDI (`.mid`) | Download do navegador | Janela `Salvar <nome>` do Android (ou o compartilhar do sistema, se a janela não estiver disponível) |
| Menu do botão direito | Usado pelo app nos clipes (o do navegador é desligado no projeto) | Não há botão direito; o toque longo faz o papel (não confirmado) |
| Teclado | Todos os atalhos | Só com teclado físico (não confirmado) |
| Instalar como app | Navegadores que oferecem instalar sites (o site tem manifesto `standalone` e abre a casca sem rede) | App do Android |
| Exigências | Navegador atual, `https` para gravar | Android 8.0 (API 26) ou mais novo; ABIs `arm64-v8a`, `armeabi-v7a` e `x86_64` |
| Ajustar áudio ao andamento (warp) | Progresso durante o processamento | Só avisa o fim (sem barra de progresso) |
| Tela enquanto toca ou grava | A aba do navegador cuida sozinha (o app não faz nada) | O app mantém a tela acesa enquanto o transporte toca ou grava e solta ao parar (ver "O aparelho no Android") |
| O app sai da tela | A aba segue tocando em segundo plano, como qualquer player do navegador | Para o transporte (gravando, encerra a gravação, que fica salva), solta as notas ao vivo e fecha a entrada de áudio |
| O fone sai | O app não faz nada (o navegador decide) | Para o transporte, sem voltar o cursor |
| Falha do motor | Aviso na tela do projeto com o botão `Reiniciar o áudio` | O mesmo aviso e o mesmo botão |
| Palavras das mensagens | `este navegador`, `O navegador negou...` | `este aparelho`, `O Android negou...` |

**O que só existe num dos lados**

- Só no Android: a permissão `RECORD_AUDIO` em tempo de execução, a folha de compartilhar como plano B ao exportar e a autorização pelo app do Discord.
- Só na web: a instalação como app pelo navegador e a casca do app offline (`sw.js`).
- Em qualquer outro sistema (um build de computador nativo, testes) não há motor: a tela do projeto avisa `O motor de áudio não roda neste sistema: use o jopendaw no navegador ou no Android.` (o mesmo texto de "não roda neste sistema" vale para a gravação, a exportação, o warp e o MIDI, cada um com o seu verbo).

### O aparelho no Android

Só no app do Android o estúdio conversa com o aparelho por um canal próprio (`app/lib/platform/platform_native.dart` e `MainActivity.kt`). Tudo abaixo vale só enquanto a tela do projeto está aberta e foi coberto por testes automáticos com o canal simulado (`app/test/android_session_test.dart`); **não foi visto num aparelho nem no emulador** `(testado só por testes automáticos)`.

| Situação | O que o app faz |
|---|---|
| O transporte começa a tocar ou a gravação começa | Liga o sinal de manter a tela acesa (`FLAG_KEEP_SCREEN_ON`). Repetir o mesmo estado não repete o pedido ao Android. |
| O transporte para, ou você fecha a tela do projeto | Solta a tela: ela volta a apagar pelo tempo normal do aparelho. |
| O app sai da tela (outro app na frente, botão de início, tela desligada) | Para o transporte sem voltar o cursor; se estava gravando, encerra a gravação e ela fica salva (como no `stop`); solta as notas tocadas ao vivo; fecha a entrada de áudio (o aviso de privacidade do microfone apaga). Um diálogo por cima, a cortina de notificações ou a tela dividida **não** contam como sair. |
| O app volta à tela | Pede ao motor que garanta a saída tocando e reabre a entrada de áudio se alguma faixa de áudio ficou armada ou monitorando. |
| O fone (com fio ou Bluetooth) sai | Para o transporte, como todo app de mídia, sem voltar o cursor, e solta as notas ao vivo; gravando, encerra a gravação. Sem nada tocando, não faz nada. |
| Um aparelho de áudio entra ou sai (fone plugado, interface USB) | Não pausa; pede ao motor que garanta a saída. |

Os dois avisos (fone que sai; aparelho que entra ou sai) só são escutados enquanto o app está à mostra. O de aparelho compara a lista de aparelhos de áudio com a da última vez e só avisa quando ela mudou, inclusive de algo plugado enquanto o app estava fora.

No Android o pedido "garanta a saída" (`AudioEngine.resume()`) hoje não faz nada dentro do motor nativo: quem reabre a saída de áudio que o sistema derrubou ou que trocou de rota é o supervisor do motor (`jopendaw-sup`, verifica a cada 250 ms). O comportamento visível é o mesmo, mas a explicação dos comentários do código não bate com isso.

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

- **As mensagens falam do lugar onde você está.** No Android os textos dizem `este aparelho` e `O Android negou o acesso ao microfone` onde a web diz `este navegador` e `O navegador negou o acesso ao microfone` (a janela `Configurações` e os erros de importar áudio, ligar o MIDI e abrir a entrada).
- **A entrada de áudio é do aparelho; a latência e a contagem são do projeto.** Se você calibrar a latência num aparelho e abrir o projeto em outro, a versão da nuvem não troca o valor de cada aparelho, então calibre em cada um.
- **A latência está limitada a −200 a 500 ms.** O valor é guardado no projeto e entra na sincronização, mas não no desfazer.
- **Trocar a entrada no meio da gravação não é permitido:** o seletor fica desligado e o texto pede `Pare a gravação para trocar de entrada.`
- **Um atalho que "não pega"** costuma ser: campo de texto com foco, teclado do computador ligado (as letras viram notas; o botão da barra mostra `C4 · sem atalhos` e a janela de atalhos tem um grupo que lista o que ficou suspenso), ou o piano roll sem ter sido o último lugar clicado.
- **Ao sair do app no Android o transporte para sozinho, e ao desplugar o fone também.** Isto é intencional (ver "O aparelho no Android"); a tela fica acesa só enquanto toca ou grava. `(testado só por testes automáticos)`
- **Sair do app no meio de uma gravação a encerra.** O que já foi gravado fica salvo, mas a gravação não continua em segundo plano (sem serviço em primeiro plano o Android poderia matar o processo).
- **Se o som some e aparece o aviso `O motor de áudio parou de responder e o som ficou mudo...`,** o projeto está intacto: use o botão `Reiniciar o áudio` do aviso (ver o [capítulo 00](00-visao-geral.md)).
- **`Esc` fecha o painel de baixo**, mas se o editor tiver notas selecionadas o primeiro `Esc` só limpa a seleção.

## Atalhos

Os atalhos deste assunto:

| Tecla | Ação |
|---|---|
| `?` | Abrir a janela `Atalhos do teclado` |
| `Ctrl+K` (`⌘+K` no Mac) | Ligar/desligar o teclado do computador |
| `R` | Gravar |
| `C` | Metrônomo (com o teclado do computador ligado, vira "velocidade menor" e fica listado em `Suspensos enquanto o teclado do computador está ligado`) |
| `Z` / `X` | Com o teclado ligado: oitava abaixo / acima da faixa que toca (a bateria começa no `C2`) |
| `Enter` · `Home` | Parar e voltar ao começo |
| `Delete` · `Backspace` | Apagar o clipe |
| `=` ou `+` / `−` | Aproximar / afastar |
| `Esc` | Fechar o painel de baixo |
| `Enter` no campo de latência | Confirmar o número digitado |
