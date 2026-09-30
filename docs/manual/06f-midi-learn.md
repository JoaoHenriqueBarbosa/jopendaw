# MIDI learn (Aprender MIDI)

> Liga um botão, fader ou pedal do seu teclado ou controlador MIDI a um controle do app (fader, pan, envio, knob de instrumento ou de efeito): clique no controle, mexa no botão do controlador e pronto. Use para mixar e tocar com as mãos no hardware, e para gravar automação com fader de verdade.

Legenda de confiança deste capítulo: o que foi visto no Chrome com uma mensagem MIDI injetada (`jopendawEngine.injectMidi`, ver [Gravação](03c-gravacao.md)) está dito no texto; **nada foi conferido com um controlador de verdade**, no Chrome nem no Android. O resto vem da leitura do código e de testes automáticos `(testado só por testes automáticos)`.

## Onde fica

- **Ligar a entrada MIDI primeiro.** O ícone de cabo da barra do transporte (tooltip `Entrada MIDI: ligar teclado ou controlador`) pede acesso ao MIDI do aparelho; no Chrome aparece o pedido de permissão. Ver [Gravação, Teclado do computador e MIDI](03c-gravacao.md#teclado-do-computador-e-midi). Se você ligar o modo pelo botão de MIDI learn ou por `Shift+K` sem ter ligado o MIDI, o app pede o MIDI na hora (o clique ou a tecla é o gesto que o navegador exige).
- **Botão `Aprender MIDI`** na barra do transporte, logo depois do ícone de cabo (ícone de controle remoto). Ele **só aparece** quando o MIDI está ligado, ou o modo já está ligado, ou o projeto já tem mapeamentos: sem controlador, o botão só gastaria largura da barra. Desligado o MIDI, sem mapeamentos e com o modo desligado, use `Shift+K` (que liga o modo e pede o MIDI).
- **Atalho `Shift+K`** liga e desliga o modo em qualquer lugar da tela do projeto. Não vale com o teclado do computador ligado (a tecla vira nota; ver [Limites e pegadinhas](#limites-e-pegadinhas)).
- **Faixa `Aprender MIDI`** que aparece logo abaixo da barra do transporte enquanto o modo está ligado.
- **Janela `Mapeamentos MIDI`**: pelo botão `Mapeamentos (N)` da faixa, pelo botão direito (ou toque longo) no botão `Aprender MIDI` da barra, ou pelo item `Mapeamentos MIDI…` do menu de um controle.
- **Celular (Android):** o mesmo fluxo; no lugar do botão direito vale o toque longo. O MIDI chega pelo plugin do app `(não confirmado com um controlador de verdade)`.

## Controles

### Botão da barra

| Controle (rótulo exato) | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| Botão de ícone de controle remoto, tooltip `Aprender MIDI (Shift+K): clique num controle e mexa no botão do seu teclado` | Liga o modo. Com mapeamentos, o tooltip ganha uma segunda linha: `N mapeamento(s) · botão direito: lista` (`1 mapeamento`, `2 mapeamentos`...) | Desligado ao abrir o projeto; o modo não é salvo | Com mapeamentos, um pontinho de aviso aparece sobre o ícone |
| O mesmo botão com o modo ligado (ícone e contorno âmbar; tooltip `Sair do modo Aprender MIDI (Shift+K)`) | Desliga o modo | | |
| Botão direito ou toque longo no botão | Abre a janela `Mapeamentos MIDI` | | |

### A faixa do modo

A faixa fica logo abaixo da barra, com o ícone de controle remoto, um texto e dois botões. O texto muda com o estado (exatamente assim):

| Situação | Texto |
|---|---|
| MIDI ainda desligado | `Aprender MIDI: ligue a entrada MIDI (botão do cabo) e clique num controle contornado.` |
| MIDI ligado, nenhum aparelho conectado | `Aprender MIDI: nenhum aparelho conectado. Conecte o teclado; ele aparece sozinho.` |
| Pronto para aprender | `Aprender MIDI: clique num controle contornado e mexa no botão do seu teclado (Esc sai).` |
| Um controle armado | `Mexa no controle do seu teclado que vai comandar "Volume"… (Esc cancela)` (o nome entre aspas é o do alvo: `Volume`, `Pan`, `Instrumento · Corte`, `Filtro · Corte`, `Envio → Reverb`...) |
| Acabou de aprender | `Aprendido: Canal 1 · CC 21 → Pad · Volume. Clique noutro controle contornado ou Esc para sair.` (visto no Chrome com `injectMidi`) |

| Botão da faixa | O que faz |
|---|---|
| `Mapeamentos (N)` | Abre a janela `Mapeamentos MIDI`; `N` é a quantidade de mapeamentos do projeto |
| `Sair` | Desliga o modo |

### Como os controles ficam no modo

No modo, cada controle mapeável ganha um contorno e **passa a responder só a clique** (arrastar, roda e duplo clique ficam desligados até você sair do modo):

| Aparência | Significa | Tooltip do controle |
|---|---|---|
| Contorno âmbar fino e fundo escurecido | Mapeável, ainda sem mapeamento | `Aprender MIDI: clique e mexa num controle do seu teclado` |
| Contorno âmbar grosso, fundo âmbar | Armado: o próximo CC, pitch bend ou pressão do canal vira o mapeamento | `Mexa no controle do seu teclado…` |
| Contorno verde e uma etiqueta verde no canto superior esquerdo (`CC21`, `Bend`, `Pres.`) | Já mapeado; a etiqueta diz de onde vem | `Mapeado em Canal 1 · CC 21. Clique para aprender outro; botão direito ou toque longo: remover` |

Fora do modo, um controle mapeado leva só um pontinho âmbar de 6 px no canto superior direito. Clicar num controle armado desarma. Botão direito ou toque longo num controle contornado abre o menu do controle (abaixo). A etiqueta do fader do `Pad` mapeado ao `CC 21` mostrou `CC21` (visto no Chrome com `injectMidi`).

### Menu do controle

O mesmo mapeamento se faz e se desfaz pelo menu, sem ligar o modo:

| Onde | Como abrir | Itens |
|---|---|---|
| Knob de instrumento ou de efeito, fora do modo | Botão direito (toque longo no celular). O tooltip do knob já diz isso: `<nome>: arraste ou use a roda (Shift: ajuste fino)` / `Duplo clique: padrão (<valor>) · botão direito ou toque longo: menu (digitar o valor, Aprender MIDI, Modular)` (a lista entre parênteses vem das ações do menu; os knobs sem o menu dizem `botão direito ou toque longo: digitar o valor`) | `Digitar o valor…`, uma linha divisória, `Aprender MIDI`, se já mapeado, `Remover mapeamento (Canal 1 · CC 74)` (a origem vem entre parênteses) e `Modular…` (só nos knobs contínuos; ver [06g](06g-modulacao.md)) |
| Fader e pan do mixer, fora do modo | Botão direito do mouse (o toque longo só vale no modo) | `Aprender MIDI`, `Remover mapeamento (Canal 1 · CC 21)` (só se mapeado), `Modular…`, `Mapeamentos MIDI…` |
| Qualquer controle contornado, no modo | Botão direito ou toque longo | Os mesmos itens do fader |
| Nível de envio do mixer, fora do modo | Botão direito é o menu do envio (ver [Mixer](06-mixer.md#envios)), que **não** tem `Aprender MIDI`: para mapear o envio, ligue o modo | |
| Mini fader do cabeçalho da faixa, fora do modo | Não há menu; ligue o modo | |
| Seletores de opção (`Onda`, `Tipo`, `Algoritmo`), fora do modo | Não há menu; ligue o modo | |

`Aprender MIDI` (com o modo desligado) já liga o modo e arma o controle. `Remover mapeamento` apaga só o mapeamento daquele controle. `Modular…` não tem a ver com o MIDI: abre o seletor de modulador do [capítulo 06g](06g-modulacao.md) (ver a próxima seção sobre como os dois se somam).

### MIDI learn e modulação no mesmo controle

Um controle pode ter um mapeamento **e** modulação. O controlador move o valor **base** (o que o knob mostra e o que fica no projeto); o LFO, o seguidor ou a macro somam por cima, sem tirar o mapeamento nem mudar o valor guardado. O controle modulado leva um pontinho ciano no canto superior esquerdo (o pontinho âmbar do mapeamento fica no direito), também no modo `Aprender MIDI`. O `Suave` (takeover) compara o botão com o valor base, não com o som que sai. Os knobs dos cartões da aba `Modulação` (o `Valor` da macro, a `Taxa` do LFO...) **não** se mapeiam: a macro só se mexe com o mouse ou o toque `(lido do código; não confirmado com um controlador)`.

### O que pode ser mapeado

| Controle | Alvo | Onde | Como o valor anda |
|---|---|---|---|
| Fader de volume de uma faixa, de um barramento e do `Master` | `Volume` | Fader do [mixer](06-mixer.md) e mini fader do cabeçalho da faixa na linha do tempo (o mini fader do `Master` não tem contorno) | Pela curva do fader: −∞ a +6 dB; 0 dB fica a 79% do curso |
| Knob de pan (e o balanço do `Master`) | `Pan` | Mixer | Reto de −1 (esquerda) a +1 (direita) |
| Nível de envio | `Envio → nome do barramento` | Linha do envio no mixer, se o envio já existe | Pela curva do fader: −∞ a +6 dB |
| Knobs do [painel de instrumento](04-painel-de-instrumento.md), inclusive os seletores de opção e os inteiros | `Instrumento · parâmetro` (com o grupo quando o nome se repete) | Painel `I` | Na escala do knob (logarítmica em Hz e segundos, reta nos outros); seletores e inteiros arredondam para a opção ou o número mais próximo |
| Knobs do [painel de efeitos](06c-painel-de-efeitos.md), inclusive os do `Master` | `Nome do efeito · parâmetro` (`Filtro · Corte`; dois efeitos do mesmo tipo levam número: `Reverb 2 · ...`) | Painel `F` | Igual ao instrumento |

Não podem ser mapeados: `M`, `S`, armar e monitorar, tocar, parar, gravar, andamento, loop, o `Sidechain` do compressor e do gate, o gráfico do `EQ`, as zonas do sampler, a saída da faixa e todos os botões e menus. Em resumo: o que a [automação](07-automacao.md) automatiza, é o que o MIDI learn mapeia.

### O que o controlador pode mandar

| Mensagem MIDI | Origem que o app mostra | Valor 0 a 1 |
|---|---|---|
| Controle contínuo (CC) de 0 a 119, em qualquer canal | `Canal 1 · CC 74` | Valor de 0 a 127 dividido por 127 |
| Pitch bend | `Canal 1 · Pitch bend` | 14 bits: de 0 a 16383 dividido por 16383 (a roda no centro vale 0,5) |
| Pressão do canal (aftertouch de canal) | `Canal 1 · Pressão do canal` | Valor de 0 a 127 dividido por 127 |

A origem é sempre **canal mais controle**: o mesmo CC em canais diferentes são origens diferentes, e o app não distingue aparelhos (só recebe `status`, `dado1`, `dado2`). Notas nunca são aprendidas nem mapeadas: passam e tocam normalmente, até com um controle armado. Os CC 120 a 127 (som cortado, reset, notas desligadas, modo local, e o resto do bloco de modo de canal) **nunca são aprendidos nem consumidos**: um controle armado continua armado e a mensagem segue o caminho de sempre (`CC 120` = pânico, `CC 121` = reset dos controles, `CC 123` = notas desligadas). A pressão *por nota* (aftertouch polifônico) não é lida.

### O que passa quando o CC chega

A cada mensagem mapeada, o app faz esta conta, na ordem:

1. Valor do controlador em 0 a 1 (tabela acima).
2. **Curva** (`Linear` ou `Logarítmica`).
3. **Invertido**, se ligado: `1 − valor`.
4. **Mín e Máx**: o valor é levado para dentro do trecho escolhido do curso do controle.
5. **Suave** (takeover), se ligado: decide se o controle assume ou espera (abaixo).
6. O valor vai para a **escala do controle** (o fader pela curva dele, Hz em logarítmica...) e é aplicado pelo mesmo caminho de quem mexe com o mouse.

Por ser o mesmo caminho do mouse: o motor é atualizado, o projeto é salvo, e com o botão `Automação` em `Escrever`, `Toque` ou `Trava` e a música tocando o movimento **grava automação** ([Automação, Gravar automação](07-automacao.md#gravar-automação)). Um movimento do controlador vale **um passo só** no desfazer: o gesto começa na primeira mensagem que muda o valor (uma primeira mensagem que cai no valor que o controle já tinha não conta) e termina depois de 700 ms sem mensagens (uma pausa de mais de 0,7 s no meio do giro abre um passo novo, e é também o que solta o controle no modo `Toque`). Só mexe no valor fixo do controle; se ele está com automação em `Ler`, a curva continua mandando quando o transporte toca.

Funciona com o transporte parado ou tocando, com o painel do controle aberto ou não, com o modo de aprender ligado ou desligado.

### Janela `Mapeamentos MIDI`

Diálogo de 620 px, com a opção `Suave` no alto, uma linha por mapeamento e os botões de baixo.

| Controle (rótulo exato) | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| Chave `Suave (só assume ao cruzar o valor atual)` (subtítulo `O controle não salta: o botão do teclado só passa a mandar quando chega ao valor que o controle já tem`) | Liga e desliga o takeover de **todos** os mapeamentos do projeto | Ligada | Explicação e exemplo abaixo |
| Texto da origem (`Canal 1 · CC 74`, `Canal 2 · Pitch bend`, `Canal 1 · Pressão do canal`) | De onde vem o valor | Só se muda aprendendo de novo | Aprender de novo o mesmo controle **substitui** o mapeamento dele, e o novo nasce com `Linear`, sem `Invertido` e com `Mín` 0% e `Máx` 100% (perde os ajustes do antigo) |
| Texto do alvo (`Sintetizador 1 · Instrumento · Corte`, `Pad · Volume`, `Master · Pan`) | O que o mapeamento comanda: nome da faixa, um ponto e o nome do alvo | | Vermelho quando o alvo sumiu: `Faixa removida` (faixa apagada) ou `Nome da faixa · alvo removido` (efeito, envio ou instrumento que não existe mais) |
| Botão de lixeira, tooltip `Remover mapeamento` | Apaga aquele mapeamento | | Alvo sumido: é a única forma de tirar a linha |
| `Invertido` (chip) | Espelha o controlador: o botão no máximo põe o controle no mínimo | Desligado | Serve para pedal que sobe ao pisar ou botão ao contrário |
| Caixa `Linear` / `Logarítmica` | Formato da resposta do controlador | `Linear` | Ver "Curva" abaixo |
| `Mín 0%` ... `Máx 100%` com um seletor de faixa de duas pontas | Trecho do curso do controle que o controlador percorre | 0% a 100% | Percentuais **do curso do controle**, na escala dele, não do valor bruto. O seletor mantém sempre `Mín` menor que `Máx`; para virar ao contrário use `Invertido` |
| `Salvar como padrão para novos projetos` | Guarda os mapeamentos de volume, pan e instrumento como padrão dos projetos novos | Desabilitado sem mapeamentos | Só neste aparelho. Ver "Padrão para novos projetos" |
| `Apagar o padrão` | Esquece o padrão guardado | | Não mexe nos mapeamentos do projeto aberto |
| `Remover todos` | Apaga todos os mapeamentos do projeto | Desabilitado sem mapeamentos | Não pede confirmação e **não entra no desfazer** |
| `Fechar` | Fecha a janela | | |

Sem mapeamentos, a lista mostra `Nenhum mapeamento. Ligue "Aprender MIDI" na barra, clique num controle e mexa no botão do teclado.`

### Curva: `Linear` ou `Logarítmica`

A curva age no valor do controlador **antes** da escala do controle. `Linear` deixa o giro reto. `Logarítmica` sobe depressa no começo e devagar no fim (0 vira 0, 1 vira 1; a metade do curso do controlador já chega a 74%). Serve para dar mais espaço útil ao trecho baixo de um fader de volume, ou para abrir um filtro mais cedo.

Exemplo com o **fader de volume**, que já tem a curva cúbica dele (0 dB a 79% do curso). Valores calculados pelas fórmulas do código, não medidos ao ouvido (só o `CC 40` linear foi visto, −24,1 dB):

| CC | Fader `Linear` | Fader `Logarítmica` |
|---|---|---|
| 16 | −48,0 dB | −22,9 dB |
| 32 | −29,9 dB | −11,3 dB |
| 64 | −11,8 dB | −1,7 dB |
| 96 | −1,3 dB | +3,1 dB |
| 127 | +6,0 dB | +6,0 dB |

No `Linear`, o 0 dB cai no `CC 101` (79% de 127). Exemplo com o `Corte` do sintetizador (20 Hz a 20 kHz, logarítmico): no `Linear`, `CC 64` dá cerca de 650 Hz; no `Logarítmica`, cerca de 3,4 kHz.

### Suave (takeover): por que o controle não salta

Um botão de hardware tem uma posição física; o controle na tela tem outra. Sem cuidado, ao mexer no botão o controle saltaria para onde o botão está. Com `Suave` ligado (o padrão), o controle **fica parado** até o controlador cruzar o valor que ele já tem, ou chegar a **2% do curso** dele; a partir daí segue o controlador.

Exemplo: o `Corte` do sintetizador está no padrão, 2400 Hz, o que é 69% do curso do knob. Seu botão está no zero (`CC 0`). Você começa a girar: nada acontece até o `CC 86` (cerca de 68%, a 2% do valor do knob); dali para cima o knob acompanha. Se o botão pulasse de `CC 60` para `CC 100` numa mensagem só, cruzando os 69%, ele também assume. O mesmo vale descendo.

Regras que valem no código:

- Ao aprender, o valor da mensagem que criou o mapeamento **não** é aplicado: ele só serve de ponto de partida para o cruzamento.
- Se você mexe no controle por outro caminho (mouse, desfazer, preset) e ele se afasta mais de 2% do que o controlador pôs, o mapeamento solta o controle e ele só volta a seguir depois de cruzar de novo.
- Mudar `Invertido`, a curva ou `Mín`/`Máx` de um mapeamento também o solta até o próximo cruzamento.
- Com `Mín` e `Máx` estreitos, um controle que está fora do trecho é alcançado pela borda mais próxima (senão nunca seria pego).
- Ao comparar, o app usa o valor que o controle **mostra**: com o transporte tocando e o controle com automação em `Ler`, é o valor da curva naquele ponto; parado, ou com o controle já sendo gravado como automação (`Escrever`, `Toque` ou `Trava` com a mão nele), é o valor fixo. Para reconhecer que outra mão mexeu (a regra acima), o app olha o valor **fixo**, que é o que este mapeamento escreve: a curva da automação andando sozinha não solta o controle `(testado só por testes automáticos)`.
- Desligado `Suave`, o controle salta direto para o valor do controlador na primeira mensagem.

### O que é salvo e o que fica no aparelho

| Dado | Onde fica |
|---|---|
| Os mapeamentos (origem, alvo, faixa mín/máx, curva, invertido) e a opção `Suave` | No **projeto** (campo `midi_map` do documento): vão junto na sincronização com a nuvem, na cópia para outro aparelho e no arquivo `.jopendaw`. O campo é gravado quando há mapeamentos ou quando `Suave` está desligado (um `Suave` desligado, mesmo sem mapeamentos, é salvo e volta ao abrir); só o mapa vazio com `Suave` ligado, o padrão, fica de fora. Ao abrir, um mapeamento cuja faixa não é texto nem vazia (documento de outra versão) é descartado sem derrubar os outros |
| O modo `Aprender MIDI` ligado e o controle armado | Só na tela; não são salvos |
| O padrão para novos projetos | Só no **aparelho** (guardado local, chave `midimap:default`): não vai à nuvem nem ao projeto |
| O desfazer | Mapear, remover e editar mapeamentos **não** entram no `Ctrl+Z`; desfazer uma nota ou um movimento de fader não desfaz o mapeamento |

Como o mapa é parte do projeto, um projeto puxado de outro aparelho traz o mapa dele e **substitui** o deste. Abrir o projeto num aparelho sem controlador não muda nada: o mapa só age quando chega MIDI.

### Padrão para novos projetos

`Salvar como padrão para novos projetos` guarda os mapeamentos deste projeto para os projetos que você criar depois neste aparelho. Ele leva `Volume`, `Pan` (do `Master` e das faixas) e parâmetros de instrumento, com a opção `Suave`. **Não leva** efeitos nem envios (dependem de ids que só existem no projeto onde foram criados). Os parâmetros de instrumento guardam também o **tipo da faixa** (o id 13 é o `Corte` no sintetizador e o `Ataque` do operador 2 no FM): o mapeamento só é aplicado numa faixa do mesmo tipo, e numa faixa de outro tipo é descartado (padrões guardados antes disso, sem o tipo, seguem valendo como antes, com o risco de cair noutro parâmetro). As faixas vão pela **posição** (o mapeamento da terceira faixa vai para a terceira faixa do projeto novo); o que aponta para uma posição que não existe é descartado. O aviso que aparece:

- ao guardar: `Guardado: os projetos novos começam com estes mapeamentos de volume, pan e instrumento (efeitos e envios ficam de fora).`
- ao apagar (`Apagar o padrão`): `Padrão apagado: projetos novos começam sem mapeamentos.`
- se a gravação local falhar: `Não deu para guardar o padrão: ...` ou `Não deu para apagar o padrão: ...`

O padrão só é aplicado quando o projeto **nasce** (vazio ou de um modelo); um projeto que já tem documento não é tocado. Nos modelos, como a faixa é pela posição, o mapeamento de instrumento só entra se a faixa da mesma posição tiver o mesmo tipo de instrumento (o id 13 é `Corte` no sintetizador, `Ataque` do operador 2 no FM e `Desafino` no wavetable, por isso o tipo é guardado). `(testado só por testes automáticos)`

### CC 1, pedal (CC 64) e pitch bend: expressão ou mapeamento

Sem mapeamento, o `CC 1` (roda de modulação), o `CC 64` (pedal de sustain) e o pitch bend seguem sendo **expressão do instrumento** ([Gravação](03c-gravacao.md#teclado-do-computador-e-midi)). Se você mapeia um deles **de propósito**, aquela origem (canal + controle) passa a ser só do mapeamento: a mensagem é consumida, não chega ao instrumento e, gravando, não vira ponto de bend, modulação ou pedal no clipe. Outros canais do mesmo controle continuam sendo expressão (a expressão ignora o canal; o mapeamento não). A regra vale enquanto o mapeamento existir, **mesmo com o alvo sumido**: um `CC 1` mapeado a um efeito removido segue sendo consumido e não faz nada, até você remover o mapeamento na janela. Para voltar o `CC 1` a ser modulação, remova o mapeamento.

## Passo a passo

**Mapear um fader de volume (uma faixa)**
1. Ligue a entrada MIDI (ícone de cabo) e confira se o controlador aparece (o número no ícone). Abra o mixer (`X`).
2. Ligue o modo: botão `Aprender MIDI` da barra ou `Shift+K`. Os faders, os pans e os envios ganham contorno.
3. Clique no fader da faixa. A faixa diz `Mexa no controle do seu teclado que vai comandar "Volume"… (Esc cancela)`.
4. Mexa no fader do controlador. A faixa passa a dizer `Aprendido: Canal 1 · CC 21 → Pad · Volume...` e o fader ganha a etiqueta `CC21`.
5. Ainda no modo, mapeie outros controles do mesmo jeito. `Esc` (ou `Sair`) desliga o modo.
6. Mexa no fader do controlador: o fader do app só passa a acompanhar quando o controlador chega ao valor que ele já tem (`Suave`). Para ele saltar direto, desligue `Suave` na janela `Mapeamentos MIDI`.

**Mapear um knob de filtro**
1. Selecione a faixa do sintetizador e abra o painel de instrumento (`I`).
2. Ligue o modo (`Shift+K`) e clique no knob `Corte` (cartão `FILTRO`). Ou, sem o modo, botão direito no knob e `Aprender MIDI`.
3. Gire o botão do controlador; a faixa mostra `Aprendido: Canal 1 · CC 74 → Sintetizador 1 · Instrumento · Corte`.
4. Saia do modo. Gire de novo: o `Corte` fica onde estava até o botão chegar perto dele (2400 Hz no padrão) e depois acompanha, de 20 Hz a 20 kHz na escala logarítmica do knob.
5. Para um efeito, faça igual no painel `F`: por exemplo o `Corte` do efeito `Filtro` (20 Hz a 20 kHz, padrão 1000 Hz).

**Mapear com curva logarítmica e limitar o curso**
1. Abra `Mapeamentos MIDI` (botão `Mapeamentos (N)` da faixa do modo, ou botão direito no botão da barra).
2. Na linha do fader de volume, troque `Linear` por `Logarítmica`: o trecho baixo do controlador passa a ter mais volume audível (`CC 32` sai de −29,9 para −11,3 dB).
3. Para o fader nunca passar de 0 dB, arraste a ponta direita do seletor até `Máx 79%` (o 0 dB fica a 79,4% do curso).
4. Se o pedal ou botão sobe ao contrário, ligue `Invertido`.
5. Depois de mudar curva, `Invertido` ou faixa, o mapeamento espera o próximo cruzamento para assumir (`Suave`).

**Desfazer, remover e limpar**
1. Um movimento que o controlador fez no controle desfaz com `Ctrl+Z` (um passo por gesto); o mapeamento, não.
2. Para tirar **um** mapeamento: botão direito no controle e `Remover mapeamento (...)`, ou a lixeira da linha na janela `Mapeamentos MIDI`.
3. Para trocar a origem: no modo, clique no controle e mexa no botão novo (substitui o antigo).
4. Para tirar todos: `Remover todos`. Não há confirmação nem desfazer.
5. Para apagar também o padrão dos projetos novos: `Apagar o padrão`.

## Combina com

- [Gravação](03c-gravacao.md): o MIDI de bend, modulação e pedal que **não** foi mapeado é gravado no clipe; o mapeado não.
- [Automação](07-automacao.md): com `Escrever`, `Toque` ou `Trava`, o fader do controlador grava pontos na raia.
- [Modulação](06g-modulacao.md): o controlador move a base de um controle e o LFO ou o seguidor soma por cima; `Modular…` fica no mesmo menu do controle.
- [Mixer](06-mixer.md), [Painel de instrumento](04-painel-de-instrumento.md) e [Painel de efeitos](06c-painel-de-efeitos.md): os controles mapeáveis.
- [Transporte](02-transporte.md): o botão `Aprender MIDI` na barra.
- [Configurações, atalhos e Android](09-configuracoes-atalhos-android.md): a lista de atalhos e a lista de atalhos suspensos.
- [Guia: controlador MIDI e MIDI learn](../guias/controlador-midi-e-midi-learn.md): três montagens (mixer com knobs, pedal de expressão no filtro, fader gravando automação).
- [Guia: expressão MIDI na prática](../guias/expressao-midi-na-pratica.md): bend, modulação e pedal gravados.
- Técnico: [App Flutter, MIDI learn](../dev/10-app-flutter.md#midi-learn) e [Expressão MIDI](../dev/04-expressao-midi.md).

## Limites e pegadinhas

- **Nunca testado com hardware.** A conta, o aprender, o `Suave`, o painel e o padrão passam nos testes automáticos; o fluxo com fader mapeado foi visto no Chrome só com mensagens injetadas. Comportamentos específicos de um controlador (pitch bend com mola, faders de 14 bits, CC enviado em rajada) não foram vistos.
- **Sem o MIDI ligado nada acontece.** O botão só aparece com o MIDI ligado (ou mapeamentos no projeto); a faixa avisa `ligue a entrada MIDI (botão do cabo)`.
- **No modo, os controles contornados não arrastam.** Só clique e menu; saia do modo (`Esc`, `Sair` ou `Shift+K`) para usar o mouse no controle.
- **`Shift+K` conflita com a nota K.** Com o teclado do computador ligado (`Ctrl+K`), `Shift+K` vira nota e `Aprender MIDI liga/desliga (vira nota)` aparece na lista de atalhos suspensos. Use o botão da barra.
- **A dica do teclado cita o `Shift+K`.** O tooltip do ícone de teclado ligado lista `C L S X Z E F K J e Shift+H/K/L` (a mesma lista da janela de atalhos suspensos, `?`).
- **Pitch bend com mola.** A roda de bend volta ao meio sozinha (14 bits, valor 0,5): um controle mapeado ao bend acompanha a roda e, ao soltar, vai para o meio do curso dele.
- **Um controle, uma origem; uma origem, vários controles.** Aprender de novo o mesmo controle substitui o mapeamento; o mesmo CC pode comandar vários controles.
- **Alvo apagado não some da lista.** Faixa, efeito ou envio removidos deixam o mapeamento em vermelho (`Faixa removida`, `... · alvo removido`), inerte mas ainda consumindo a mensagem. Desfazer a remoção do alvo o reativa (o mapeamento aponta pelo id).
- **Faixa duplicada ou importada.** O mapeamento aponta para o id da faixa; uma faixa duplicada não herda o mapeamento. Ao importar um `.jopendaw`, os ids de faixa, efeito e envio que não são seguros ou se repetem são refeitos, e o `midi_map` é reescrito junto: cada mapeamento passa a apontar para o novo id da faixa (e do efeito ou do envio, quando o alvo é um deles). O que apontava para uma faixa, efeito ou envio que não existe no arquivo é descartado na importação, em vez de virar `Faixa removida` `(testado só por testes automáticos)`.
- **Automação não grava junto com a gravação de áudio ou MIDI.** Com `R` gravando (ou na contagem), mexer num controle mapeado muda o valor, mas mostra o aviso `A automação não grava junto com a gravação de áudio ou MIDI.` ao lado do botão `Automação` e não grava pontos.
- **No `Toque`, a mão solta em 0,7 s.** O controlador não tem "soltar": o app entende que você soltou depois de 700 ms sem mensagens, e o valor volta à automação.
- **O que não vale:** notas, pressão por nota, `CC 120` a `CC 127`, mensagens de sistema e de relógio; e controles que não são automatizáveis.
- **Web e Android.** O mapeamento é o mesmo; a diferença é o toque longo no lugar do botão direito e o plugin de MIDI do Android `(não confirmado com um controlador de verdade)`.

## Atalhos

| Tecla / gesto | Ação |
|---|---|
| `Shift+K` | Liga e desliga o modo `Aprender MIDI` (fica suspenso com o teclado do computador ligado) |
| Clique num controle contornado | Arma o controle; o próximo CC, pitch bend ou pressão do canal vira o mapeamento |
| Clique no controle armado | Desarma |
| `Esc` | Desarma o controle armado; sem nenhum armado, sai do modo. Tem prioridade sobre o `Esc` que fecha o painel de baixo |
| Botão direito · toque longo | Menu do controle: `Aprender MIDI`, `Remover mapeamento (...)`, `Modular…` |
