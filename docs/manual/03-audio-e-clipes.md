# Áudio e clipes

> Como trazer um arquivo de áudio (ou um arquivo MIDI `.mid`) para o projeto e mexer no clipe que nasce dele: mover, aparar, fazer fades, cortar, duplicar e levar para outra faixa de áudio.

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

**Andamento e compasso.** Se o arquivo traz andamento (`Set Tempo`) ou compasso (`Time Signature`) e algum dos dois difere do projeto, abre uma pergunta. O que se compara é o mapa inteiro: o BPM inicial (arredondado ao inteiro), cada ponto do [mapa de andamento](02b-timeline-e-clipes.md#faixa-andamento-e-mapa-de-compassos), os tempos por compasso e cada mudança do mapa de compassos. Se tudo já é igual ao projeto, a pergunta nem aparece.

| Situação do arquivo | Título da pergunta |
|---|---|
| Com mudanças de andamento | `Usar os andamentos do arquivo (N mudanças, a partir de X BPM)?` (`1 mudança` no singular; `X` é o andamento do primeiro ponto, inteiro ou com uma casa e vírgula, como `97,5`) |
| Um andamento só | `Usar o andamento do arquivo (X BPM)?` (`X` inteiro, ou com uma casa e vírgula quando não é inteiro, como `97,5`) |
| Sem andamento, com mudanças de compasso | `Usar os compassos do arquivo (N mudanças)?` |
| Só um compasso | `Usar o compasso do arquivo?` |

O texto da pergunta é `O arquivo traz <partes>; o projeto está em <agora>. As notas ficam nas mesmas batidas, só a velocidade muda.` As partes são, por exemplo, `120 BPM e 3 mudanças de andamento` e `compasso 6/8 e 1 mudança de compasso` (a fórmula do primeiro compasso do arquivo), ligadas por ` e `. O `<agora>` é `Y BPM`, mais ` e N mudanças de andamento` se o projeto já tem mapa, e `Z/4` (os tempos por compasso do projeto; esse trecho continua sem contar a fórmula do primeiro compasso nem as mudanças do mapa de compassos do projeto: um projeto em `6/8` aparece como `3/4`) `(lido do código; não confirmado em uso)`.

| Botão | Efeito |
|---|---|
| `Usar o do arquivo` | O mapa de andamento e o de compassos do arquivo **substituem** os do projeto (não se misturam), no mesmo passo do desfazer da importação. Com um andamento só, o BPM vira inteiro (20 a 999, mesmo quando a pergunta mostrou uma casa decimal: `97,5` entra como `98`); com mudanças, o BPM inicial é o do primeiro ponto, sem arredondar, e os pontos seguintes entram como saltos (sem rampa). Sem andamento (ou sem compasso) no arquivo, o do projeto fica como está |
| `Manter o do projeto` (ou fechar a pergunta clicando fora) | O projeto continua como está; as notas ficam nas mesmas batidas, então a música toca mais rápida ou mais lenta |

**Limites do mapa que entra.** `(testado só por testes automáticos)`
- Pontos a menos de 0,05 BPM do último mantido são fundidos (uma rampa gravada em milhares de eventos vira poucas centenas de pontos). Se ainda passar de **256 pontos**, o app dobra esse limiar até caber. Só aparece aviso quando algum ponto foi fundido: `O arquivo tem N mudanças de andamento; fundi as que diferem menos de 0.05 BPM e M ficaram no mapa (o limite é 256 pontos).` (o `0.05` sai com ponto, não vírgula).
- Se o primeiro `Set Tempo` não está no começo do arquivo, o andamento vale 120 BPM (o padrão do MIDI) até ele. O andamento fica entre 20 e 999 BPM.
- O compasso do arquivo é lido como fórmula de verdade: `6/8` fica `6/8` (3 batidas por compasso) e `7/8` fica `7/8` (3,5 batidas), sem aviso. O valor de `Tempos por compasso` do projeto recebe o arredondamento (`6/8` vira 3, `7/8` vira 4, limitado a 1–32), mas o mapa de compassos guarda a fórmula exata. Na janela `Andamento e compasso`, a lista `Tempos por compasso` mostra o compasso inicial que não é `n/4` como `6/8 (atual)` e estende a lista para caber um primeiro compasso acima de 12 batidas (por exemplo `13/4`); antes da fase 12 esse valor ficava fora da lista `(lido do código; não confirmado no navegador)`. Se o primeiro `Time Signature` vem depois do começo, vale `4/4` até ele.
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
| Alça de fade in (círculo branco no canto de cima à esquerda) | Arrasta para a direita para criar/alongar o **fade in** | 0 até (duração do clipe − fade out); padrão 0 | O sombreado triangular mostra o trecho do fade. Não usa grade |
| Alça de fade out (círculo branco no canto de cima à direita) | Arrasta para a esquerda para criar/alongar o **fade out** | 0 até (duração do clipe − fade in); padrão 0 | Curva do fade: a rampa linear é **elevada ao quadrado** na amplitude (o fade in começa bem suave e ganha força no fim; o fade out é o inverso) |
| Selo `W` / `+3st` / `R` / `processando…` | Aparece quando o clipe tem warp, transposição ou reverso ativos (só em clipe com 40 px ou mais de largura). Tooltip `Warp e altura` | | Detalhes em [Warp e altura](03b-warp-e-altura.md) |
| Selo `N tomadas` | Aparece em clipe gravado em loop; tocar abre a lista de tomadas | | Detalhes em [Gravação](03c-gravacao.md) |

Depois de qualquer arrasto que mexeu no clipe, ele passa a ficar **por cima** dos outros da mesma faixa: o que ele cobre é aparado, partido em dois ou removido (não existem dois clipes de áudio tocando um sobre o outro na mesma faixa). Cada arrasto inteiro vale um só passo do desfazer.

### Menu do clipe (botão direito ou toque longo)

| Item (rótulo exato) | O que faz | Atalho | Dica |
|---|---|---|---|
| `Tomadas` (só em clipe gravado em loop, com o número de tomadas) | Abre a lista `TOMADAS`; escolher uma troca o áudio do clipe (posição, corte e fades ficam) | | Ver [Gravação](03c-gravacao.md) |
| `Duplicar` | Cria uma cópia logo depois do clipe (no fim dele) e seleciona a cópia | `Ctrl+D` (`⌘+D`) | A cópia leva warp, fades e ganho |
| `Cortar no cursor` | Parte o clipe em dois no cursor. O fade out fica só no pedaço da esquerda e o fade in só no da direita | `S` | Com clipe selecionado corta ele; sem seleção, corta tudo o que o cursor cruza na faixa atual (áudio e notas). Só corta se o cursor está dentro do clipe |
| `Warp e altura…` | Abre o diálogo de warp, transposição e reverso | | [Warp e altura](03b-warp-e-altura.md) |
| `Ganho do clipe…` | Abre o diálogo `Ganho do clipe` (ver a seção abaixo) | | Só no clipe de áudio; o volume da faixa continua no mixer |
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

### Botões da barra que agem no clipe

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

## Limites e pegadinhas

**O que acontece com o arquivo importado**
- O app calcula o **sha-256** dos bytes do arquivo. É a identidade do áudio: importar o mesmo arquivo duas vezes reaproveita o mesmo áudio (não decodifica nem guarda de novo) e cada importação só cria um clipe novo.
- O arquivo **original** (bytes intactos, no formato de origem) é guardado no aparelho (IndexedDB no navegador; arquivos na pasta de documentos do app no Android) sob a chave `sample:<sha-256>`. O projeto guarda só o sha-256, o nome e a duração; o áudio decodificado é regenerado ao abrir.
- Conectado à conta, o app envia os áudios ao servidor endereçados pelo sha-256 (limite de 512 MB por arquivo e cota de 4 GB por conta). Se a cota estoura, o projeto sincroniza mas o áudio acusa `Alguns áudios não foram enviados` e, em outro aparelho, o clipe aparece como `áudio fora deste aparelho`.
- Na web o navegador decodifica e entrega o áudio na taxa do motor; no Android o arquivo mantém a taxa dele e o motor converte ao tocar (não confirmado o detalhe da conversão na web: é comportamento do navegador).

**Sobre o clipe**
- **O ganho do clipe** se ajusta em `Ganho do clipe…` (−40 a +12 dB, padrão 0 dB). Ele soma ao volume da faixa (fader do mixer), não o substitui. O ganho máximo é +12 dB: um valor maior vindo de um arquivo de projeto é limitado a esse teto ao ser editado no diálogo. Só clipes de áudio têm esse controle; o clipe de notas não.
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
