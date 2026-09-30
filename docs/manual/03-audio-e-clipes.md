# Áudio e clipes

> Como trazer um arquivo de áudio para o projeto e mexer no clipe que nasce dele: mover, aparar, fazer fades, cortar, duplicar e levar para outra faixa de áudio.

## Onde fica

- **Importar:** barra do transporte (a faixa de botões em cima no computador, embaixo no celular). O botão é o ícone de arquivo com tooltip `Importar áudio (Ctrl+I)`; em janela larga (a partir de uns 1540 px, só no computador) ele mostra também o texto `Importar`. No Mac o atalho é `⌘+I`.
- **Clipes:** na linha do tempo (o arranjo), dentro da raia da faixa. Clipe de áudio só existe em **faixa de áudio** (tipo `Áudio`).
- **Menu do clipe:** botão direito no clipe (computador) ou toque longo (celular).
- **Nova faixa de áudio:** botão `Faixa` no pé da lista de faixas (tooltip `Nova faixa`), item `Áudio`.

## Controles

### Importar

| Controle (rótulo exato) | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| `Importar áudio (Ctrl+I)` (ícone) / `Importar` (texto) | Abre o seletor de arquivos (título `Importar áudio`) e põe cada arquivo escolhido como um clipe, a partir do cursor de reprodução | Aceita escolher vários arquivos de uma vez | Fica desligado enquanto há outro trabalho em andamento (aparece o texto de status ao lado, com um círculo girando) e durante a gravação |
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

Como funciona: o ganho fica no documento do projeto (campo `gain` do clipe), é enviado ao motor (multiplica o clipe junto com os fades) e vai junto com o projeto na sincronização; a exportação e o congelamento usam o mesmo documento `(não testado ouvindo o arquivo exportado)`. A onda desenhada no clipe cresce ou diminui na mesma proporção (o desenho é escalado pelo ganho; se a onda passa da altura do clipe e é cortada na borda, `(não confirmado)`). A cópia (`Duplicar`) leva o ganho.

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
- [Exportação](08-exportacao.md): o que soa (inclusive o warp já processado) é o que sai no WAV.

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
- Importar, exportar e o desfazer ficam bloqueados enquanto se grava; arrastar clipes, aparar e cortar continuam liberados na tela, mas a gravação que está rolando não leva em conta o que mudou.
- O botão `Importar` de um instrumento **Sampler** (dentro do painel do instrumento) é outra coisa: escolhe o áudio do sampler e **não** cria clipe no arranjo.
- Clipe com o áudio ausente deste aparelho não toca. O app tenta buscar no servidor ao abrir o projeto.

## Atalhos

| Tecla | Ação |
|---|---|
| `Ctrl+I` (`⌘+I`) | Importar áudio |
| `S` | Cortar no cursor |
| `Ctrl+D` (`⌘+D`) | Duplicar o clipe |
| `Delete` ou `Backspace` | Apagar o clipe |
| `Ctrl+Z` / `Ctrl+Shift+Z` (ou `Ctrl+Y`) | Desfazer / refazer |
| `Alt` ao arrastar | Move o clipe sem encaixe na grade |
| `Z` / `Shift+Z` | Enquadrar o projeto / o clipe selecionado (com o teclado do computador ligado, `Z` vira oitava) |
