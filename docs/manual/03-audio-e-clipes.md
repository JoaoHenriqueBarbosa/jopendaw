# Áudio e clipes

> Como trazer um arquivo de áudio (ou um arquivo MIDI `.mid`) para o projeto e mexer no clipe que nasce dele: mover, aparar, fazer fades (com a curva de cada um) e crossfades, cortar, duplicar e levar para outra faixa de áudio.

## Onde fica

- **Importar:** barra do transporte (a faixa de botões em cima no computador, embaixo no celular). O botão é o ícone de arquivo com tooltip `Importar áudio ou MIDI (Ctrl+I)`; em janela larga (a partir de uns 1540 px, só no computador) ele mostra também o texto `Importar`. No Mac o atalho é `⌘+I`.
- **Clipes:** na linha do tempo (o arranjo), dentro da raia da faixa. Clipe de áudio só existe em **faixa de áudio** (tipo `Áudio`).
- **Menu do clipe:** botão direito no clipe (computador) ou toque longo (celular).
- **Nova faixa de áudio:** botão `Faixa` no pé da lista de faixas (tooltip `Nova faixa`), item `Áudio`.

## Controles

### Importar

| Controle (rótulo exato) | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| `Importar áudio ou MIDI (Ctrl+I)` (ícone) / `Importar` (texto) | Abre o seletor de arquivos (título `Importar áudio ou MIDI`) e põe cada arquivo de áudio escolhido como um clipe, a partir do cursor de reprodução. Os arquivos `.mid` e `.midi` seguem outro caminho: viram faixas de notas (ver [Importar um arquivo MIDI (.mid)](#importar-um-arquivo-midi-mid)) | Aceita escolher vários arquivos de uma vez, áudio e MIDI misturados: os áudios entram primeiro, depois cada `.mid`, um de cada vez | Fica desligado enquanto há outro trabalho em andamento (aparece o texto de status ao lado, com um círculo girando) e durante a gravação |
| Posição do clipe novo | Começa no cursor, **encaixado na grade** (`Livre`, `Compasso`, `1/4`, `1/8`, `1/16`; padrão `1/4`) | Duração do clipe = duração do arquivo | Para importar em ponto exato, mova o cursor antes (clique na régua) |
| Faixa do clipe novo | O primeiro arquivo vai na faixa **selecionada**, se ela for de áudio e estiver livre naquele trecho; senão (e sempre para o 2.º arquivo em diante) nasce uma **faixa de áudio nova**, com o nome do arquivo sem extensão (até 40 caracteres) | Cor da faixa: a próxima da paleta | Vários arquivos importados juntos começam todos no mesmo ponto, cada um na sua faixa |
| Nome do clipe | O clipe mostra o nome do arquivo (com extensão) no canto de cima à esquerda | | O nome vem do primeiro arquivo importado com aquele conteúdo |

### Formatos aceitos

O seletor filtra por extensão. Quem decodifica é o navegador (web) ou o motor nativo (Android).

| Extensão | Web (navegador) | Android (motor nativo, symphonia) |
|---|---|---|
| `wav` | Sim | Sim (PCM, ADPCM) |
| `aif`, `aiff` | Depende do navegador | Sim |
| `flac` | Sim | Sim |
| `mp3` | Sim | Sim |
| `ogg`, `oga` | Depende do navegador (Vorbis) | Sim (Ogg Vorbis) |
| `m4a`, `aac` | Depende do navegador | Sim (AAC e ALAC em MP4) |
| `opus`, `webm` | Depende do navegador | **Não** (o motor nativo não tem Opus) |

O arquivo é decodificado em 1 ou 2 canais. Arquivo com mais de 2 canais fica só com os dois primeiros (esquerda e direita). Mono continua mono e sai nos dois lados. Se o arquivo não decodifica, aparece o aviso `Não deu para abrir <nome>: é um formato de áudio que este navegador decodifica?` (o texto fala em "navegador" mesmo no Android).

### Importar um arquivo MIDI (.mid)

O mesmo botão `Importar` (e o `Ctrl+I`) aceita os arquivos MIDI padrão, com extensão `mid` ou `midi`. Em vez de um clipe de áudio, cada arquivo vira **faixas de notas** com um clipe de notas cada, que você edita no [editor de notas](05-piano-roll.md) e nas [ferramentas MIDI](05b-ferramentas-midi.md) como qualquer outro. Enquanto lê, a barra mostra `Lendo <nome>…`. Se o arquivo tem alguma faixa de notas que não é bateria, abre antes a janela `Importar como` (ver a primeira linha da tabela). O passo a passo do outro lado (levar as notas do jopendaw para outro programa) está em [Exportação](08-exportacao.md#notas-em-midi-mid).

| O que | Como fica no projeto | Valores | Dica |
|---|---|---|---|
| Faixas criadas | Uma **faixa nova por canal com notas**: cada trilha do arquivo vira uma faixa, e uma trilha que mistura vários canais rende uma faixa por canal. Trilhas sem nota (a de andamento, por exemplo) não viram faixa | Faixas ao fim da lista; a primeira nova fica selecionada, com o clipe dela selecionado | Cada faixa nova leva a próxima cor da paleta |
| Tipo da faixa (janela `Importar como`) | Uma lista de escolha única com `Sintetizador` (padrão na primeira vez), `FM`, `Wavetable` e `Sampler`; vale para as faixas dos canais 1 a 9 e 11 a 16. O **canal 10** (o `9` do protocolo) é sempre `Bateria`. A janela tem o aviso `Vale para as faixas de notas do arquivo; o canal 10 vira Bateria. O Sampler fica mudo até você dar um áudio a ele.` e os botões `Cancelar` e `Importar` | `Cancelar` desiste da importação inteira (nada muda). A última escolha fica lembrada até fechar o app e já vem marcada na próxima importação; um arquivo só de bateria não abre a janela. Vários `.mid` escolhidos juntos abrem a janela uma vez por arquivo | O programa (`Program Change`, o "som" escolhido no arquivo) continua **ignorado**: a faixa nasce com o instrumento escolhido no timbre padrão dele. Ajuste o timbre depois no [painel do instrumento](04-painel-de-instrumento.md) (presets); no `Sampler`, escolha um áudio |
| Nome da faixa e do clipe | O nome da trilha no arquivo. Trilha com vários canais: `<nome> (canal N)`, ou `Canal N` se não tem nome. Sem nome nenhum, a faixa é `Sintetizador 1`, `Bateria 1`… (o nome do tipo escolhido e o primeiro número livre). **O clipe leva o nome da trilha** (ou o da faixa nova, se a trilha não tem nome) | Caracteres de controle são removidos do nome | Não há limite de tamanho do nome nem tratamento de nomes repetidos |
| Onde o clipe começa | No **cursor**, encaixado na grade (como o áudio). O instante zero do arquivo cai no cursor: um silêncio no começo do arquivo é preservado | Todas as faixas do mesmo arquivo começam no mesmo ponto | Ponha o cursor no compasso onde a música deve entrar antes de importar |
| Duração do clipe | Fecha no fim do compasso em que a última nota (ou controle) termina, com no mínimo 1 compasso | Compassos pelo **mapa de compassos** que o projeto terá depois da importação (o do arquivo, se você aceitou usá-lo; senão o do projeto): num `6/8` ou `3/4` o clipe cresce de 3 em 3 batidas, num `7/8` de 3,5 em 3,5, e mudanças de compasso no meio contam | Dá para puxar o fim do clipe na régua do editor |
| Notas | Altura, início, duração e velocidade (a velocidade 1–127 do arquivo vira 0–1 no app). `Note On` com velocidade 0 desliga a nota. Nota de duração zero ganha 1/32 de batida | Notas ligadas que nunca desligam fecham no fim da trilha (aviso: `N nota(s) sem desligar: fechei no fim da faixa.`) | A velocidade de soltar (`Note Off`) não é lida |
| Pitch bend, modulação e pedal | Viram os pontos de controle do clipe: `Pitch bend`, `Modulação` (CC 1) e `Sustain` (CC 64), os mesmos da [faixa de controle](05-piano-roll.md#faixa-de-controle) do editor. O pedal vale ligado a partir de 64. Só entra um ponto quando o valor muda | Bend de −1 a 1 (o alcance em semitons é o `Alcance do bend` do instrumento, não o do arquivo) | O arquivo pode dizer outro alcance de bend (`RPN 0`, como o que o jopendaw escreve na exportação); o app ignora isso sem aviso e usa o `Alcance do bend` do instrumento: se o arquivo usa mais que 2 semitons, ajuste o `Alcance do bend` para o mesmo valor |
| Outros controles | **Ignorados**: volume (CC 7), pan (CC 10), expressão (CC 11), reverb e o resto dos CC, pressão do canal, `Program Change`, letras, marcadores, SysEx. Os CC 120 em diante (all notes off) e os de `RPN`/`NRPN` (CC 6, 38 e 98 a 101, o alcance do bend) são descartados sem aviso e não entram na contagem do aviso | Aviso: `Ignorei N evento(s) de controle que o app não usa (volume, pan, expressão…).` | Quem mixou no programa de origem precisa refazer volume e pan no [mixer](06-mixer.md) |
| Bateria (canal 10) | As notas GM vão para as peças da [bateria](04b-bateria.md) pela altura. As que o app tem entram como estão: 36 `Bumbo`, 37 `Aro`, 38 `Caixa`, 39 `Palmas`, 41 `Tom grave`, 42 `Chimbal fechado`, 45 `Tom médio`, 46 `Chimbal aberto`, 48 `Tom agudo`, 49 `Prato de ataque`, 51 `Prato de condução`, 56 `Cowbell` | Aproximadas para a peça parecida: 35→36, 40→38, 43→41, 44→42, 47→45, 50→48, 52→49, 53→51, 55→49, 57→49, 59→51 (aviso com a contagem). Sem peça (por exemplo 54 pandeiro, 58 vibraslap, qualquer nota fora de 35–59): a nota **entra no clipe mas fica sem som** (aviso: `A bateria do app não tem: <lista>. Essas notas entraram, mas ficam sem som.`) | A nota sem som pode ser movida para uma peça que existe no editor da bateria |

**Andamento e compasso.** Se o arquivo traz andamento (`Set Tempo`) ou compasso (`Time Signature`) e algum dos dois difere do projeto, abre uma pergunta. O que se compara é o mapa inteiro: o BPM inicial (comparado **arredondado ao inteiro**: um arquivo em `97,5` contra um projeto em `98` não abre a pergunta e o projeto fica em `98`), cada ponto do [mapa de andamento](02b-timeline-e-clipes.md#faixa-andamento-e-mapa-de-compassos), os tempos por compasso e cada mudança do mapa de compassos. Se tudo já é igual ao projeto, a pergunta nem aparece.

| Situação do arquivo | Título da pergunta |
|---|---|
| Com mudanças de andamento | `Usar os andamentos do arquivo (N mudanças, a partir de X BPM)?` (`1 mudança` no singular; `X` é o andamento do primeiro ponto, inteiro ou com uma casa e vírgula, como `97,5`) |
| Um andamento só | `Usar o andamento do arquivo (X BPM)?` (`X` inteiro, ou com uma casa e vírgula quando não é inteiro, como `97,5`) |
| Sem andamento, com mudanças de compasso | `Usar os compassos do arquivo (N mudanças)?` |
| Só um compasso | `Usar o compasso do arquivo?` |

O texto da pergunta é `O arquivo traz <partes>; o projeto está em <agora>. As notas ficam nas mesmas batidas, só a velocidade muda.` As partes são, por exemplo, `120 BPM e 3 mudanças de andamento` e `compasso 6/8 e 1 mudança de compasso` (a fórmula do primeiro compasso do arquivo), ligadas por ` e `. O `<agora>` é `Y BPM`, mais ` e N mudança(s) de andamento` se o projeto já tem mapa, uma vírgula e o **compasso real do projeto** (o do compasso 1, com a figura verdadeira: um projeto em `6/8` aparece como `6/8`, não como `3/4`), mais ` e N mudança(s) de compasso` se o projeto tem mapa de compassos (fase 13; antes o trecho era `Z/4` fixo e ignorava a fórmula e as mudanças de compasso do projeto). Exemplo: `o projeto está em 120 BPM, 6/8 e 1 mudança de compasso`. Os BPM (do arquivo e do projeto) passam pelo formatador único de andamento: uma casa, vírgula, sem `,0` (`120,04` aparece `120`). `(testado só por testes automáticos)`.

| Botão | Efeito |
|---|---|
| `Usar o do arquivo` | O mapa de andamento e o de compassos do arquivo **substituem** os do projeto (não se misturam), no mesmo passo do desfazer da importação. Com um andamento só, o BPM **mantém a fração**, com uma casa decimal, que é a resolução do app (20 a 999: `97,5` entra como `97,5`, e um `Set Tempo` de 90 BPM que o arquivo guarda como 90,00009 entra como `90`); até a fase 13 o BPM virava inteiro e `97,5` entrava como `98` `(testado só por testes automáticos)`; com mudanças, o BPM inicial é o do primeiro ponto, sem arredondar, e os pontos seguintes entram como saltos (sem rampa). Sem andamento (ou sem compasso) no arquivo, o do projeto fica como está |
| `Manter o do projeto` (ou fechar a pergunta clicando fora) | O projeto continua como está; as notas ficam nas mesmas batidas, então a música toca mais rápida ou mais lenta |

**Limites do mapa que entra.** `(testado só por testes automáticos)`
- Pontos a menos de 0,05 BPM do último mantido são fundidos (uma rampa gravada em milhares de eventos vira poucas centenas de pontos). Se ainda passar de **1024 pontos**, o app dobra esse limiar até caber (o limite da importação subiu de 256 para 1024 na fase 14; o mapa do projeto aceita até 4096, e 1024 mantém baixo o custo de CPU do motor). Só aparece aviso quando algum ponto foi fundido: `O arquivo tem N mudanças de andamento; fundi as que diferem menos de 0,05 BPM e M ficaram no mapa (o limite é 1024 pontos).` Desde a fase 13 o aviso está em português do Brasil: vírgula decimal (`0,05`; antes saía `0.05`) e concordância de número (`1 mudança` e `ficou` no singular, `mudanças` e `ficaram` no plural).
- Se o primeiro `Set Tempo` não está no começo do arquivo, o andamento vale 120 BPM (o padrão do MIDI) até ele. O andamento fica entre 20 e 999 BPM.
- O compasso do arquivo é lido como fórmula de verdade: `6/8` fica `6/8` (3 batidas por compasso) e `7/8` fica `7/8` (3,5 batidas), sem aviso. O valor de `Tempos por compasso` do projeto recebe o arredondamento (`6/8` vira 3, `7/8` vira 4, limitado a 1–32), mas o mapa de compassos guarda a fórmula exata. Na janela `Andamento e compasso`, a lista `Tempos por compasso` mostra o compasso inicial que não é `n/4` como `6/8 (atual)` e a lista vai de `1/4` a `32/4` (desde a fase 13; antes parava em `12/4` e só se estendia para caber um primeiro compasso maior, como `13/4`; antes da fase 12 esse valor ficava fora da lista). O compasso do **clipe** criado usa o mesmo limite do documento, **1 a 32 batidas** (antes da fase 13 o clipe limitava o primeiro compasso a 12 batidas: um arquivo em `13/4` ou `4/1` criava o clipe com 12 tempos por compasso, agora com o certo) `(testado só por testes automáticos; não confirmado no navegador)`. Se o primeiro `Time Signature` vem depois do começo, vale `4/4` até ele.
- O mapa de compassos que entra tem no máximo **1024 entradas** (o compasso inicial mais 1023 mudanças). Se o arquivo tem mais, as que passam do limite ficam de fora, agora **com aviso** (fase 14; antes eram cortadas em silêncio): `O arquivo tem N mudanças de compasso; o app aceita até 1023, então as seguintes ficaram de fora.` (N é o total de mudanças do arquivo) `(testado só por testes automáticos)`.
- Uma mudança de compasso que cai no meio de um compasso do arquivo é alinhada ao compasso mais próximo, com o aviso `Uma mudança de compasso caiu no meio de um compasso: alinhei ao compasso mais próximo.` Numerador acima de 64 ou denominador acima de 32 é aproximado, com o aviso `Uma fórmula de compasso do arquivo passa dos limites do app (denominador até 32, numerador até 64) e foi aproximada.`
- Se você escolhe `Manter o do projeto` e o arquivo muda de andamento (algum BPM difere do primeiro em mais de 0,5), aparece `O arquivo muda de andamento no meio (de X a Y BPM); mantive o do projeto.` (X e Y inteiros). Mudança de compasso ignorada não gera aviso.

Os avisos antigos (`o app tem um andamento só, então as mudanças foram ignoradas`, `O arquivo muda de compasso no meio: o app usa só o primeiro` e `O compasso 7/8 foi aproximado para 4/4`) não existem mais. A duração do clipe criado é contada pelo mapa de compassos (ver a linha `Duração do clipe` da tabela acima).

**Formatos de arquivo lidos.** SMF tipo 0, 1 e 2, com qualquer resolução em pulsos por semínima (PPQ), eventos com *running status*, e também um MIDI embutido em RIFF (RMID) renomeado para `.mid`. Tipo 2 (sequências independentes) entra todo junto, cada sequência começando do início, com o aviso `Este é um MIDI tipo 2 (sequências independentes): todas as sequências entraram juntas, começando do início.` Um arquivo cortado ou com trecho corrompido importa o que deu para ler, com o aviso `O arquivo está cortado ou tem trechos corrompidos: usei só o que deu para ler.`

**Avisos.** Se houve algum aviso, abre a janela `<nome>.mid importado, com avisos`, com `N faixa(s), M nota(s).`, uma linha `•` por aviso e o botão `Entendi`. Sem avisos, as faixas só aparecem, sem janela. A importação inteira (faixas, clipes e o andamento aceito) é um só passo do `Ctrl+Z`.

**Erros** (aparecem no aviso vermelho abaixo da barra, sem criar nada; o texto começa com `Não deu para importar <nome>: `):

| Situação | Mensagem depois do prefixo |
|---|---|
| Arquivo de 0 byte | `O arquivo está vazio.` |
| Não é MIDI | `Este arquivo não é um MIDI padrão (.mid): falta o cabeçalho "MThd".` |
| Cabeçalho incompleto | `O arquivo MIDI está cortado logo no começo (cabeçalho incompleto).` ou `O cabeçalho do arquivo MIDI está corrompido.` |
| Tipo desconhecido | `Formato MIDI N desconhecido: só leio os tipos 0, 1 e 2.` |
| Tempo em quadros (SMPTE) | `Este arquivo usa tempo em quadros SMPTE, que o app não lê. Salve-o de novo com tempo em pulsos por semínima (PPQ).` |
| Zero pulsos por semínima | `O arquivo MIDI diz que tem 0 pulsos por semínima: está corrompido.` |
| Sem trilha | `O arquivo MIDI não tem nenhuma faixa (está cortado ou corrompido).` |
| Sem nenhuma nota | `O arquivo MIDI não tem nenhuma nota.` |
| Qualquer outra falha | `o arquivo MIDI está corrompido.` (mensagem completa: `Não deu para importar <nome>: o arquivo MIDI está corrompido.`) |
| Gravando | `Pare a gravação para importar MIDI.` (o botão já fica desligado gravando; a mensagem só aparece por outro caminho) |

Não há limite de tamanho de arquivo nem de quantidade de notas no código; a leitura devolve o controle à tela a cada 20 mil eventos para não travar num arquivo grande (o teste automático usa 100 mil notas). O comportamento com arquivos MIDI reais de outros programas (Ableton, FL Studio, MuseScore, pacotes de acordes) `(testado só por testes automáticos)`: os testes montam os bytes à mão, nenhum arquivo exportado por esses programas foi aberto.

### O clipe na linha do tempo

| Controle | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| Forma de onda | Desenho do áudio em picos mínimo/máximo (um pico a cada 256 amostras). Só mostra o trecho do clipe (do `offset` ao fim), na altura do ganho do clipe | Cor da faixa | Sem o arquivo neste aparelho o clipe fica vermelho e mostra `áudio fora deste aparelho` |
| Clique no clipe | Seleciona (borda branca, fundo mais claro) e seleciona também a faixa dele | | O clipe selecionado é o alvo de `Cortar`, `Duplicar` e `Apagar` |
| Arrastar o miolo | **Move** o clipe no tempo, com encaixe na grade. Arrastando na vertical, passa para **outra faixa de áudio** | Início nunca abaixo de 0 | `Alt` ao arrastar: livre, sem grade. Numa faixa que não é de áudio o clipe fica onde está |
| Arrastar a borda esquerda | **Apara o começo**: o clipe encurta pela esquerda e o áudio continua no mesmo lugar do tempo (o `offset` anda junto) | Limites: começo do arquivo e fim do clipe (mínimo 0,01 s) | Borda de 8 px com mouse, 16 px com o dedo (e no máximo um quarto da largura do clipe) |
| Arrastar a borda direita | **Apara o fim** (ou estende, até o fim do arquivo) | Mínimo 0,01 s; máximo o que sobra do arquivo depois do `offset` | Não dá para esticar além do arquivo |
| Alça de fade in (círculo branco no canto de cima à esquerda) | Arrasta para a direita para criar/alongar o **fade in** | 0 até (duração do clipe − fade out); padrão 0 | O sombreado escuro mostra o que o fade tira e uma linha branca desenha a curva escolhida (ver [Fades e crossfade](#fades-e-crossfade)). Não usa grade. Mexer na alça faz o fade deixar de ser "automático" |
| Alça de fade out (círculo branco no canto de cima à direita) | Arrasta para a esquerda para criar/alongar o **fade out** | 0 até (duração do clipe − fade in); padrão 0 | A curva é a do item `Fade de saída: …` do menu; a de fábrica, `Linear`, é a rampa **elevada ao quadrado** (`x²`; o fade in começa bem suave e ganha força no fim; o fade out é o inverso) |
| Selo `W` / `+3st` / `R` / `processando…` | Aparece quando o clipe tem warp, transposição ou reverso ativos (só em clipe com 40 px ou mais de largura). Tooltip `Warp e altura` | | Detalhes em [Warp e altura](03b-warp-e-altura.md) |
| Selo `N tomadas` | Aparece em clipe gravado em loop; tocar abre a lista de tomadas | | Detalhes em [Gravação](03c-gravacao.md) |

Depois de qualquer arrasto que mexeu no clipe, ele passa a ficar **por cima** dos outros da mesma faixa: o que ele cobre é aparado, partido em dois ou removido. **A exceção é o crossfade automático:** se o clipe só cruza a borda de outro (entra na cauda ou na cabeça dele) e cobre no máximo metade do menor dos dois, o outro **não** é aparado: os dois ficam tocando juntos naquele trecho, um saindo e o outro entrando (ver [Fades e crossfade](#fades-e-crossfade)). Fora esse caso, não existem dois clipes de áudio tocando um sobre o outro na mesma faixa. Cada arrasto inteiro vale um só passo do desfazer.

### Menu do clipe (botão direito ou toque longo)

| Item (rótulo exato) | O que faz | Atalho | Dica |
|---|---|---|---|
| `Tomadas` (só em clipe gravado em loop, com o número de tomadas) | Abre a lista `TOMADAS`; escolher uma troca o áudio do clipe (posição, corte e fades ficam) | | Ver [Gravação](03c-gravacao.md) |
| `Duplicar` | Cria uma cópia logo depois do clipe (no fim dele) e seleciona a cópia | `Ctrl+D` (`⌘+D`) | A cópia leva warp, fades (com as curvas) e ganho |
| `Cortar no cursor` | Parte o clipe em dois no cursor. O fade out fica só no pedaço da esquerda e o fade in só no da direita | `S` | Com clipe selecionado corta ele; sem seleção, corta tudo o que o cursor cruza na faixa atual (áudio e notas). Só corta se o cursor está dentro do clipe |
| `Warp e altura…` | Abre o diálogo de warp, transposição e reverso | | [Warp e altura](03b-warp-e-altura.md) |
| `Ganho do clipe…` | Abre o diálogo `Ganho do clipe` (ver a seção abaixo) | | Só no clipe de áudio; o volume da faixa continua no mixer |
| `Fade de entrada: Linear`, `Fade de entrada: Potência constante`, `Fade de entrada: Exponencial`, `Fade de entrada: S (seno cosseno)` | Escolhe a **curva do fade de entrada** do clipe. Os quatro itens ficam juntos, num bloco entre dois divisores, e o da curva atual leva uma marca de visto. A rampa desenhada no clipe muda na hora | Padrão `Linear` (o envelope de sempre, `x²`). Desfazível, um passo por escolha | A curva só se ouve se o clipe tem fade de entrada (alça do canto esquerdo). Ver [Fades e crossfade](#fades-e-crossfade) |
| `Fade de saída: Linear`, `Fade de saída: Potência constante`, `Fade de saída: Exponencial`, `Fade de saída: S (seno cosseno)` | Igual, para o **fade de saída** | Padrão `Linear` | Cada lado tem a sua curva: entrada e saída podem ser diferentes |
| `Crossfade nas sobreposições` | Nos clipes desta faixa que se cruzam pela borda, põe fade de saída no anterior e de entrada no posterior, do tamanho da sobreposição e com curva `Potência constante`, **sem** o teto de metade e **por cima** de fades que você tenha posto | Um passo do desfazer. Se não há sobreposição, não acontece nada (não aparece aviso) | Para sobreposições que já existem; ao mover ou aparar, o crossfade já sai sozinho |
| `Converter em notas (MIDI)` | Manda o áudio ao servidor e cria uma faixa de sintetizador com as notas | | [Áudio para MIDI](03d-audio-para-midi.md) |
| `Apagar` | Remove o clipe (o arquivo continua guardado no projeto) | `Delete` | Desfazer traz o clipe de volta |

#### Ganho do clipe

`Ganho do clipe…` (menu do clipe de áudio) abre um diálogo pequeno que muda o volume só daquele clipe, antes do fader da faixa. Serve para nivelar clipes da mesma faixa (uma tomada mais baixa que a outra) sem mexer no volume da faixa inteira.

| Controle (rótulo exato) | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| Título `Ganho do clipe` | Nome do diálogo | | |
| Leitura em dB (texto acima do controle) | Mostra o valor atual, por exemplo `+3,5 dB`, `−6,0 dB` ou `0,0 dB`; no piso, `−∞ dB (mudo)` | Vírgula decimal, uma casa | |
| Controle deslizante | Ajusta o ganho do clipe. O som e o desenho da onda acompanham enquanto se arrasta | −40 a +12 dB, passos de 0,5 dB (104 divisões), padrão 0 dB. No piso (−40) o clipe fica mudo (ganho 0); acima disso o valor é `10^(dB/20)`, então +12 dB multiplica a amplitude por cerca de 3,98 | Um arraste inteiro é um passo só no desfazer |
| Nota `Só este clipe; o volume da faixa continua à parte.` | Lembra que o fader e a automação de volume da faixa seguem valendo por cima | | |
| `Zerar (0 dB)` | Volta o ganho a 0 dB (ganho 1). Fica desligado quando já está em 0 dB | | Entra no desfazer como um passo |
| `Fechar` | Fecha o diálogo. Não há botão de cancelar: o que foi mexido já vale, e o desfazer (`Ctrl+Z`) volta | | |

Como funciona: o ganho fica no documento do projeto (campo `gain` do clipe), é enviado ao motor (multiplica o clipe junto com os fades) e vai junto com o projeto na sincronização; a exportação e o congelamento usam o mesmo documento `(não testado ouvindo o arquivo exportado)`. A onda desenhada no clipe cresce ou diminui na mesma proporção (o desenho é escalado pelo ganho). Com ganho alto (num áudio com picos cheios, a onda passa da altura já a partir de cerca de +0,4 dB, pois o desenho usa 95% da meia altura) ela é **cortada na borda da própria área da onda**, que fica abaixo da faixa do nome do clipe, então nunca invade o nome nem sai do clipe. `(lido do código; o corte não foi visto no Chrome)` A cópia (`Duplicar`) leva o ganho.

### Fades e crossfade

Todo clipe de áudio tem dois fades, o de entrada (sobe do silêncio no começo do clipe) e o de saída (desce ao silêncio no fim). O **tamanho** de cada um se ajusta nas alças do canto de cima (tabela `O clipe na linha do tempo`, acima); a **curva** de cada um se escolhe nos itens `Fade de entrada: …` e `Fade de saída: …` do menu do clipe. Fades, curvas e ganho do clipe multiplicam o áudio juntos e vão no projeto (sincronizam e entram no WAV exportado e no congelamento).

#### As quatro curvas

`x` é o progresso do fade, de 0 (silêncio) a 1 (volume cheio). No fade de entrada `x` é o tempo desde o começo do clipe dividido pelo tamanho do fade; no fade de saída é o tempo que falta para o fim do clipe dividido pelo tamanho do fade, ou seja, a **mesma curva vista de trás**. A tabela dá o ganho de amplitude (1 = sem alteração) e, entre parênteses, o mesmo em dB.

| Curva (texto do menu) | Fórmula do ganho | Em `x` = 25% | Em `x` = 50% | Em `x` = 75% | Como soa | Quando usar |
|---|---|---|---|---|---|---|
| `Linear` (padrão) | `x²` | 0,063 (−24 dB) | 0,25 (−12 dB) | 0,56 (−5 dB) | Entra bem devagar e ganha força no fim; a saída é o inverso | Fade simples de um clipe sozinho, como sempre foi. **Não** serve para crossfade: afunda no meio (ver a tabela seguinte) |
| `Potência constante` | `sin(x · π/2)` | 0,38 (−8,3 dB) | 0,71 (−3,0 dB) | 0,92 (−0,7 dB) | Sobe depressa no começo e chega suave ao topo | **Crossfade entre dois sons diferentes** (duas tomadas de voz, dois trechos de música): entrada e saída somam potência 1 em qualquer ponto |
| `Exponencial` | `(e^(4x) − 1) / (e^4 − 1)` | 0,032 (−30 dB) | 0,12 (−18 dB) | 0,36 (−9 dB) | Na entrada, sobe devagar e acelera; na saída, cai depressa e some suave no fim | Fim natural de uma nota, pad ou cauda que "esvai"; entrada em crescendo. Não serve para crossfade |
| `S (seno cosseno)` | `(1 − cos(π · x)) / 2` | 0,15 (−16,7 dB) | 0,50 (−6,0 dB) | 0,85 (−1,4 dB) | Suave nas duas pontas (começa e termina sem quina) | **Crossfade entre dois sons iguais ou quase** (as duas metades de um mesmo clipe, uma emenda de loop); fade de clipe sozinho sem "quina" no começo nem no topo |

Nas quatro, o ganho vale exatamente 0 em `x` = 0 e exatamente 1 em `x` = 1, e nunca desce ao longo do fade `(testado só por testes automáticos)`.

**O que soma no meio de um crossfade** (o ponto em que cada clipe está a meio do fade, `x` = 50%; os dois clipes com a mesma curva, o que sai é a curva espelhada). "Sons diferentes" quer dizer sem relação de fase entre os dois (potência soma); "sons iguais" quer dizer o mesmo áudio dos dois lados, em fase (amplitude soma). Um material real fica entre os dois casos.

| Curva dos dois lados | Sons diferentes (potência no meio) | Sons iguais (amplitude no meio) |
|---|---|---|
| `Linear` | 0,125 (−9,0 dB): afunda | 0,50 (−6,0 dB): afunda |
| `Potência constante` | 1,00 (0 dB): reta | 1,41 (+3,0 dB): estufa um pouco |
| `Exponencial` | 0,028 (−15,5 dB): afunda muito | 0,24 (−12,5 dB): afunda muito |
| `S (seno cosseno)` | 0,50 (−3,0 dB): afunda um pouco | 1,00 (0 dB): reta |

Os números são a conta das fórmulas acima; o motor tem um teste automático que mede o crossfade de dois tons sem relação (100 Hz e 150 Hz): com `Potência constante` a potência fica a 3% da de um clipe solo, e com `Linear` e `S` ela afunda. Como soa de verdade no material do usuário **(não confirmado ao ouvido)**.

**Regra prática.** Dois sons diferentes: `Potência constante` (é a que o crossfade automático usa). O mesmo som dos dois lados (emenda de duas partes do mesmo áudio, loop que cai sobre si mesmo): `S (seno cosseno)`, porque a soma das amplitudes fica constante. Não há uma rampa reta em amplitude entre as opções: no lugar dela, para material coerente, use a `S`.

**Por que a curva de fábrica chama `Linear` e é `x²`.** Antes das curvas selecionáveis, o motor já fazia o fade assim: uma rampa reta de 0 a 1 **elevada ao quadrado**. O nome `Linear` e o código 0 ficaram para essa curva, e ela continua sendo o padrão, para que todo projeto que já tinha fades soe **exatamente** igual depois da atualização (o documento antigo abre com `Linear` nos dois lados e não ganha campo novo). O nome vem da rampa que é reta antes de ser elevada; a curva em si, no ganho de amplitude, não é reta.

#### Crossfade automático

Quando você **solta** um arrasto que move ou apara um clipe de áudio e ele passa por cima de outro da mesma faixa, o app tenta fazer um crossfade em vez de aparar o de baixo. Acontece ao mover (inclusive para outra faixa de áudio) e ao aparar as bordas; não acontece ao arrastar uma alça de fade, ao `Duplicar` nem ao gravar por cima de um clipe (esses continuam aparando o de baixo como antes).

Só vira crossfade se **todas** estas condições valem; senão o outro clipe é aparado, partido ou removido, como sempre:

1. **Travessia de borda:** o clipe que você mexeu entra na cauda do outro (e termina depois dele) ou na cabeça do outro (e começa antes dele). Se um clipe fica **todo dentro** do outro, ou os dois começam no mesmo ponto, não é crossfade.
2. **Sobreposição pequena:** o trecho em comum tem, no máximo, **metade do menor dos dois clipes**.
3. **Sem fade seu no lado do crossfade:** o clipe da esquerda não pode ter um fade de saída posto por você, nem o da direita um fade de entrada posto por você. (Os fades do outro lado, como o de entrada do primeiro e o de saída do segundo, não atrapalham, mas precisam caber.)
4. **Cabe:** o fade novo mais o fade do outro lado do mesmo clipe não passam da duração dele.

O resultado: o clipe da esquerda ganha um **fade de saída** e o da direita um **fade de entrada**, cada um com o tamanho exato da sobreposição e a curva `Potência constante`. Nenhum dos dois é aparado: durante a sobreposição os dois tocam juntos, um saindo e o outro entrando. Exemplos a 120 BPM (1 batida = 0,5 s), com dois clipes de 4 s (8 batidas) na mesma faixa, o primeiro na batida 0:

| Você faz | Sobreposição | Resultado |
|---|---|---|
| Arrasta o segundo clipe para a batida 6 | 2 batidas = 1 s (o teto é metade de 4 s = 2 s) | Crossfade: o primeiro clipe ganha fade de saída de 1 s, o segundo fade de entrada de 1 s; os dois seguem com 4 s |
| Solta o segundo na batida 7 | 1 batida = 0,5 s | Crossfade de 0,5 s |
| Arrasta o segundo para a batida 2 | 6 batidas = 3 s, mais que os 2 s do teto | Sem crossfade: o primeiro clipe é aparado e fica com 1 s |
| O primeiro clipe já tinha um `fade de saída` de 0,2 s posto por você; arrasta o segundo para a batida 6 | 1 s | Sem crossfade (o fade é seu): o primeiro é aparado e fica com 3 s, com o fade de 0,2 s |
| Arrasta o segundo clipe, que estava na batida 6, para a batida 20 | 0 | Os fades automáticos voltam ao que eram antes (tamanho e curva) |

Esses valores vêm dos testes automáticos do controlador `(testado só por testes automáticos; não visto no navegador)`.

**Os fades automáticos acompanham e se desfazem.** O app guarda, em cada fade que o crossfade gerou, o tamanho e a curva que ele tinha antes. Cada vez que o app reacomoda clipes (ao soltar um arrasto que move ou apara, ao `Duplicar` e ao gravar por cima), os fades automáticos são revistos em todas as faixas: se a sobreposição mudou de tamanho, o fade muda junto (no exemplo, de 1 s para 0,5 s ao mover para a batida 7); se ela sumiu (ou o fade já não cabe), o fade volta ao tamanho e à curva de antes. **Um fade que você mexeu deixa de ser automático:** arrastar a alça dele ou escolher a curva dele no menu tira a marca, e dali em diante ele é seu e nunca mais é revertido nem redimensionado. Só o fade que o crossfade gerou é tocado; um fade seu do outro lado do clipe fica como está.

A duração de cada fade é medida em segundos do áudio original (o mesmo dos fades feitos à mão), então com warp o crossfade também acompanha o esticamento e o mapa de andamento vigente na borda `(lido do código; os testes do crossfade não usam warp)`.

#### O comando `Crossfade nas sobreposições`

Para clipes que **já** se sobrepõem na faixa (o app normalmente não os deixa assim, mas um projeto antigo ou um arquivo vindo de fora pode trazer), o item `Crossfade nas sobreposições` do menu do clipe faz o mesmo crossfade em **todas** as travessias de borda da faixa do clipe (não só nas do clipe onde você clicou), em um único passo do desfazer. Diferenças em relação ao automático: **não há teto** de metade do menor clipe e ele **passa por cima de fades que você tenha posto** nos dois lados do cruzamento (o tamanho e a curva anteriores ficam guardados, então mover o clipe depois ainda devolve o que era). Continua exigindo travessia de borda e que os fades caibam nos clipes. Sem nenhuma sobreposição, o item não faz nada e não avisa.


| Controle (tooltip) | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| `Cortar no cursor (S)` | Igual ao item do menu | | |
| `Duplicar (Ctrl+D)` | Igual ao item do menu | Desligado sem clipe selecionado | |
| `Apagar o clipe (Delete)` | Igual ao item do menu | Desligado sem clipe selecionado | Também vale a tecla `Backspace` |
| `Desfazer (Ctrl+Z)` / `Refazer (Ctrl+Shift+Z)` | Desfazem/refazem importar, mover, aparar, fades, cortar, apagar | | Desligados durante a gravação |

### Faixa de áudio e as outras faixas

| Tipo de faixa | Aceita | Grava | Monitora a entrada |
|---|---|---|---|
| `Áudio` | Clipes de áudio | Sim (microfone ou interface) | Sim |
| `Sintetizador`, `Bateria`, `Sampler`, `FM`, `Wavetable` | Clipes de **notas** (MIDI), nunca de áudio | Sim (só as notas tocadas) | Não |
| `Barramento` | Nenhum clipe (só recebe áudio de outras faixas) | Não | Não |

O clipe de áudio só muda para outra faixa **de áudio**; clipe de notas só para faixa de instrumento. Uma faixa de áudio nova tem o nome `Áudio N` (o próximo N livre entre as faixas de áudio).

## Passo a passo

**Importar um loop e encaixar num ponto**
1. Clique na régua para pôr o cursor onde o loop deve começar.
2. Selecione uma faixa de áudio vazia (ou nenhuma: ele cria uma).
3. Toque em `Importar` (ou `Ctrl+I`) e escolha o arquivo.
4. O clipe aparece selecionado, com a forma de onda. Ajuste a posição arrastando o miolo.

**Trazer um arquivo MIDI (.mid)**
1. Clique na régua para pôr o cursor onde a música do arquivo deve começar.
2. Toque em `Importar` (ou `Ctrl+I`) e escolha o `.mid` (ou `.midi`).
3. Se abrir `Importar como`, escolha o instrumento das faixas de notas (`Sintetizador`, `FM`, `Wavetable` ou `Sampler`) e toque em `Importar`. Se abrir `Usar o andamento do arquivo (X BPM)?`, escolha `Usar o do arquivo` para tocar na velocidade do arquivo ou `Manter o do projeto` para não mexer no andamento.
4. As faixas novas aparecem no fim da lista; se abrir a janela `<nome>.mid importado, com avisos`, leia e toque em `Entendi`. `Ctrl+Z` desfaz tudo de uma vez.

**Aparar e fazer fade**
1. Arraste a borda esquerda para a direita para tirar o começo (o resto fica no lugar).
2. Arraste a borda direita para tirar o final.
3. Puxe a alça do canto de cima à esquerda para um fade in e a da direita para um fade out. Use `Alt` na hora de mover o clipe se quiser posição sem grade.

**Trocar a curva de um fade**
1. Puxe a alça do canto de cima do clipe para criar o fade (sem fade, a curva não tem o que mudar).
2. Botão direito no clipe (toque longo no celular) e, no bloco de fades do menu, escolha `Fade de entrada: S (seno cosseno)` (ou outra curva; o item da curva atual leva a marca).
3. A linha branca no clipe passa a desenhar a nova curva. Toque o trecho e ouça; `Ctrl+Z` volta à curva anterior.
4. O outro lado tem a escolha própria (`Fade de saída: …`): mudar um não muda o outro.

**Emendar dois clipes com crossfade (automático)**
1. Ponha os dois clipes na mesma faixa, sem fades seus nas pontas que vão se encontrar (no fim do primeiro e no começo do segundo).
2. Arraste o segundo pelo miolo, ou apare a borda esquerda dele, até que ele entre na cauda do primeiro por menos da metade do menor dos dois clipes. Se o encaixe da grade atrapalha, segure `Alt`.
3. Solte. Os dois ficam inteiros, o primeiro ganha um fade de saída e o segundo um fade de entrada, do tamanho da sobreposição, com curva `Potência constante` (a linha branca de cada clipe mostra a rampa).
4. Para outra curva (por exemplo `Fade de saída: S (seno cosseno)` no primeiro e `Fade de entrada: S (seno cosseno)` no segundo, se os dois são o mesmo som), escolha no menu de cada clipe. Isso torna o fade seu: mover o clipe depois não o redimensiona nem o reverte.
5. Se cobrir mais que a metade do menor clipe, o app apara o de baixo em vez de fazer crossfade: solte menos por cima.

**Fazer crossfade em clipes que já se sobrepõem**
1. Botão direito num dos clipes da faixa, `Crossfade nas sobreposições`.
2. Cada travessia de borda da faixa ganha o fade de saída e o de entrada, do tamanho do trecho em comum e com `Potência constante`. Se nada mudar, a faixa não tem clipes que se cruzam pela borda.
3. `Ctrl+Z` desfaz tudo de uma vez.

**Cortar um clipe em dois**
1. Toque o áudio ou clique na régua para o cursor cair onde quer o corte.
2. Selecione o clipe.
3. Aperte `S` (ou `Cortar no cursor`). Agora são dois clipes independentes; cada um pode ir para uma faixa de áudio diferente.

**Levar um clipe para outra faixa**
1. Segure o clipe pelo miolo e arraste na vertical até a raia de outra faixa de áudio.
2. Solte. Se o lugar já tem clipe, o que estava embaixo é aparado.

## Combina com

- [Warp e altura](03b-warp-e-altura.md): esticar o clipe ao andamento do projeto, transpor e inverter, sem tocar no arquivo original.
- [Gravação](03c-gravacao.md): clipes que nascem do microfone, tomadas em loop e monitorar a entrada.
- [Áudio para MIDI](03d-audio-para-midi.md): transformar um clipe monofônico (voz, baixo, solo) em notas.
- [Mixer](06-mixer.md): volume, pan, efeitos e roteamento da faixa onde o clipe está.
- [Timeline e clipes](02b-timeline-e-clipes.md): o arranjo em geral (faixas, régua, sobreposição, menu de faixa).
- [Transporte e barra de ferramentas](02-transporte.md): os botões `Importar`, `Cortar no cursor`, grade e as configurações.
- [Exportação](08-exportacao.md): o que soa (inclusive o warp já processado) é o que sai no WAV; as notas saem à parte em `.mid` (`Notas em MIDI (.mid)…`).
- [Editor de notas](05-piano-roll.md) e [Ferramentas MIDI](05b-ferramentas-midi.md): onde se mexe nas notas de um `.mid` importado (quantizar, escala, acordes).
- [MIDI de e para outros programas](../guias/midi-de-e-para-outros-programas.md): levar uma melodia para outro DAW, trazer um pacote de acordes e guardar as notas em `.mid`.
- [Fades e crossfades na prática](../guias/fades-e-crossfades.md): emendar duas tomadas de voz, um loop sem clique e a entrada suave de um pad, com a curva recomendada em cada caso.

## Limites e pegadinhas

**O que acontece com o arquivo importado**
- O app calcula o **sha-256** dos bytes do arquivo. É a identidade do áudio: importar o mesmo arquivo duas vezes reaproveita o mesmo áudio (não decodifica nem guarda de novo) e cada importação só cria um clipe novo.
- O arquivo **original** (bytes intactos, no formato de origem) é guardado no aparelho (IndexedDB no navegador; arquivos na pasta de documentos do app no Android) sob a chave `sample:<sha-256>`. O projeto guarda só o sha-256, o nome e a duração; o áudio decodificado é regenerado ao abrir.
- Conectado à conta, o app envia os áudios ao servidor endereçados pelo sha-256 (limite de 512 MB por arquivo e cota de 4 GB por conta). Se a cota estoura, o projeto sincroniza mas o áudio acusa `Alguns áudios não foram enviados` e, em outro aparelho, o clipe aparece como `áudio fora deste aparelho`.
- Na web o navegador decodifica e entrega o áudio na taxa do motor; no Android o arquivo mantém a taxa dele e o motor converte ao tocar (não confirmado o detalhe da conversão na web: é comportamento do navegador).

**Sobre o clipe**
- **O ganho do clipe** se ajusta em `Ganho do clipe…` (−40 a +12 dB, padrão 0 dB). Ele soma ao volume da faixa (fader do mixer), não o substitui. O ganho máximo é +12 dB: um valor maior vindo de um arquivo de projeto é limitado a esse teto ao ser editado no diálogo. Só clipes de áudio têm esse controle; o clipe de notas não.
- **Fades e curvas: o que existe e o que não.** São só as quatro curvas do menu, uma por lado; não há curva desenhada à mão nem forma de ajustar a "força" de uma curva. Escolher a curva de um clipe sem fade guarda a escolha, mas não muda o som (o tamanho do fade é 0). O tamanho do fade continua limitado a 0 até a duração do clipe menos o fade do outro lado.
- **A curva `Linear` é `x²`, não uma rampa reta em amplitude.** É proposital (mantém o som dos projetos antigos). Para crossfade em material igual dos dois lados, use `S (seno cosseno)`, que soma amplitude constante; ver [Fades e crossfade](#fades-e-crossfade).
- **O crossfade automático só age ao soltar um arrasto de mover ou aparar.** Depois disso os fades só são revistos quando o app reacomoda clipes de novo (outro arrasto, `Duplicar`, gravar por cima). `Apagar` um dos dois clipes de um crossfade **não** revê o fade do que ficou: o fade de saída (ou de entrada) automático continua lá até o próximo arrasto de um clipe de áudio, quando volta ao que era `(lido do código; não visto no navegador)`. `Cortar no cursor` num clipe que tem fade automático também não revê as marcas das duas metades `(lido do código)`.
- **Dois clipes sobrepostos na mesma faixa agora existem** (o do crossfade): a sobreposição de até metade do menor clipe toca os dois somados, com os fades. Fora o crossfade, vale a regra de que o clipe que você mexeu fica por cima.
- **Projeto com curvas em app ou motor antigo:** o motor sem a chamada `clip_fade_shape` a ignora e o fade toca como `Linear` (`x²`); o desenho no clipe segue o que estiver salvo `(lido do código; não testado com um motor antigo de verdade)`.
- O clipe nunca passa do fim do arquivo: aparar/estender à direita para nesse ponto.
- Aparar não apaga nada do arquivo: o `offset` e a duração só escolhem o trecho que toca.
- Não há arrastar-e-soltar de arquivos do sistema sobre a tela: só o botão `Importar` e `Ctrl+I`.
- O arquivo `.mid` **não é guardado** no aparelho nem no servidor (ao contrário do áudio): só ficam as notas e os controles que viraram clipes. Importar o mesmo `.mid` duas vezes cria duas levas de faixas.
- Importar um `.mid` não usa o sha-256, o armazenamento de áudio nem a cota de 4 GB.
- Importar, exportar e o desfazer ficam bloqueados enquanto se grava; arrastar clipes, aparar e cortar continuam liberados na tela, mas a gravação que está rolando não leva em conta o que mudou.
- O botão `Importar` de um instrumento **Sampler** (dentro do painel do instrumento) é outra coisa: escolhe o áudio do sampler e **não** cria clipe no arranjo.
- Clipe com o áudio ausente deste aparelho não toca. O app tenta buscar no servidor ao abrir o projeto.

## Atalhos

| Tecla | Ação |
|---|---|
| `Ctrl+I` (`⌘+I`) | Importar áudio ou MIDI (a janela de atalhos diz `Importar áudio ou MIDI`) |
| `S` | Cortar no cursor |
| `Ctrl+D` (`⌘+D`) | Duplicar o clipe |
| `Delete` ou `Backspace` | Apagar o clipe |
| `Ctrl+Z` / `Ctrl+Shift+Z` (ou `Ctrl+Y`) | Desfazer / refazer |
| `Alt` ao arrastar | Move o clipe sem encaixe na grade |
| `Z` / `Shift+Z` | Enquadrar o projeto / o clipe selecionado (com o teclado do computador ligado, `Z` vira oitava) |
