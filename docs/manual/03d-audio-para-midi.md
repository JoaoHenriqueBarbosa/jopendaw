# Áudio para MIDI

> Transforma um clipe de áudio **monofônico** (voz, assobio, baixo, flauta, uma linha de solo) em notas: o servidor analisa o trecho do arquivo que o clipe toca e o app cria uma faixa de sintetizador com um clipe de notas por cima do clipe de áudio.

## Onde fica

Botão direito no clipe de áudio (computador) ou toque longo (celular), item `Converter em notas (MIDI)` (ícone de piano). Abre o diálogo `Converter em notas (MIDI)`. Não há botão na barra nem atalho.

Precisa de **conta** (entrar no app) e de conexão com o servidor: a análise roda lá, não no aparelho.

## Controles

O diálogo tem **duas etapas**. Primeiro os ajustes (nada é enviado ainda); só ao tocar em `Converter` ele envia o áudio e passa ao acompanhamento.

**Etapa 1: ajustes** (o diálogo abre assim)

| Controle (rótulo exato) | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| Título `Converter em notas (MIDI)` | Identifica o diálogo. Ele não fecha ao clicar fora | | |
| Texto `Funciona melhor com uma voz ou instrumento por vez (monofônico).` | Lembrete do limite do detector | | Ver "Limites e pegadinhas" |
| `Nota mínima: N ms` (controle deslizante) | Notas mais curtas que isto são descartadas. A legenda embaixo diz `Notas mais curtas que isto são descartadas.` | 20 a 500 ms, em passos de 1 ms, padrão **60 ms** | Suba para limpar notinhas de ruído e de vibrato; baixe para não perder notas rápidas (staccato, fusas) |
| `Nível de silêncio: N dB` (controle deslizante) | Trechos abaixo deste nível de energia (RMS) não viram nota. A legenda diz `Trechos abaixo deste nível não viram nota. Suba para ignorar ruído de fundo.` | −80 a −20 dB, em passos de 1 dB, padrão **−45 dB** | Sussurro ou gravação baixa: desça (−60). Ruído de fundo virando nota: suba (−35) |
| `Cancelar` | Fecha o diálogo sem enviar nada e sem criar tarefa | | |
| `Converter` | Envia o áudio e começa a conversão com os dois valores mostrados, pedindo ao servidor só o **trecho do arquivo que o clipe toca** (do início ao fim do clipe, com 0,25 s de folga de cada lado) | | Os ajustes não são lembrados: cada vez que o diálogo abre, voltam a 60 ms e −45 dB. O arquivo **inteiro** sobe (se ainda não estiver na conta); o recorte é feito no servidor |

**Etapa 2: acompanhamento**

| Controle (rótulo exato) | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| Texto de etapa | Diz em que passo está: `Enviando o áudio…` (o arquivo sobe ao servidor), `Na fila do servidor…` (esperando vez), `Analisando o áudio…` (a decodificação e a análise em si) | | |
| Barra de progresso | Vazia e "correndo" (indeterminada) enquanto envia, espera na fila ou o servidor ainda não informou; depois mostra a fração da análise | Atualiza a cada 1 s | Depois de decodificar o arquivo o servidor marca 10%; a análise leva o valor até 100%. O servidor grava o progresso a cada 0,5 s e o app consulta a cada 1 s, então a barra anda em saltos |
| `Cancelar` | Fecha o diálogo e para de acompanhar | | **Não cancela o trabalho no servidor**: a tarefa termina lá, mas o resultado é descartado e nenhuma faixa é criada. Se o envio já estava em curso, ele conclui mesmo assim |
| Mensagem de erro (no lugar da barra) + `Fechar` | Mostra por que não deu e o botão `Fechar` | Ver "Mensagens" abaixo | |

Quando dá certo o diálogo **fecha sozinho** e nasce uma faixa nova. Não aparece contagem nem mensagem de sucesso.

### O que a conversão cria

| O que | Como fica |
|---|---|
| Faixa nova | Tipo `Sintetizador`, no **fim** da lista, com o nome `Sintetizador N` (o próximo N livre) e a cor seguinte da paleta. Fica selecionada. O clipe de áudio original continua intacto |
| Clipe de notas | Mesmo nome da faixa, começa **no mesmo ponto** do clipe de áudio e cobre **a mesma duração** dele |
| Notas | Só as que caem dentro do trecho que o clipe de áudio mostra (respeita o corte à esquerda e à direita: o que foi aparado nem é analisado, e notas que atravessam a borda são cortadas nela; os 0,25 s de folga que o servidor analisa a mais de cada lado servem só de contexto para o detector e as notas deles são descartadas). Início e duração em **batidas** no mesmo andamento com que o clipe de áudio toca: o do projeto num clipe sem warp, o do próprio áudio (`BPM do áudio`) num clipe com warp. A **transposição** do clipe soma à altura e o **reverso** espelha as notas (ver "Coerência com o clipe"). Altura de 0 a 127 |
| Velocidade de cada nota | Vem do volume do trecho: do `Nível de silêncio` (−45 dBFS por padrão; é o piso, o mínimo, 5%) a −6 dBFS (100%) |
| Desfazer | Tudo (a faixa e o clipe) é **um** passo do desfazer |

A faixa usa o sintetizador padrão. Troque o som pelo painel do instrumento (`I`).

## Passo a passo

**Transformar uma melodia cantada em notas**
1. Grave (ou importe) a melodia, sem base nenhuma por baixo e com o microfone bem perto. Serve WAV, MP3, FLAC, OGG Vorbis, M4A/AAC (o **trecho** convertido pode ter até 10 minutos; o arquivo pode ser maior).
2. Ajuste o clipe: apare o começo e o fim para pegar só a linha. Só o que o clipe mostra é analisado.
3. Botão direito no clipe, `Converter em notas (MIDI)`. Ajuste `Nota mínima` e `Nível de silêncio` se precisar e toque em `Converter`. Espere: `Enviando o áudio…`, `Analisando o áudio…`.
4. Ao terminar, abra o clipe de notas no editor (`E` com ele selecionado) e limpe: as notas têm tempos **soltos**, sem grade.
5. Quantize (`Q` no editor) e apague ou una notas que sobraram.

**Se aparece "Não encontrei notas neste áudio."**
1. Confira se o trecho não é só ruído, percussão ou silêncio.
2. Se o volume é baixo (abaixo de −45 dBFS de RMS), o servidor trata como silêncio. Aumente o ganho na fonte e grave de novo. O `Ganho do clipe…` ([capítulo 03](03-audio-e-clipes.md#ganho-do-clipe)) não ajuda aqui: a análise lê o arquivo original, sem o ganho do clipe.

## Combina com

- [Gravação](03c-gravacao.md): a gravação do microfone sai como WAV, o caminho mais rápido do servidor.
- [Áudio e clipes](03-audio-e-clipes.md): apare o clipe antes de converter para levar só o que interessa.
- [Warp e altura](03b-warp-e-altura.md): a conversão respeita o warp, a transposição e o reverso do clipe (ver "Coerência com o clipe").
- [Editor de notas (piano roll)](05-piano-roll.md): onde limpar e quantizar as notas que a conversão cria.

## Limites e pegadinhas

**O que o detector faz (servidor, `server/src/audio.rs`)**
- Usa o **YIN**, um detector de altura para **uma nota de cada vez** (monofônico). Ele analisa quadros de 2048 amostras a cada 512, acha o período fundamental e converte para nota MIDI.
- Faixa de alturas: **50 Hz a 2000 Hz** (de cerca de sol 1, nota 31, até cerca de si 6, nota 95). Abaixo ou acima disso a altura não é reconhecida.
- **Não faz polifonia.** Acordes, violão tocando várias cordas, piano com mão esquerda, mixagem inteira ou vozes sobrepostas dão resultado errado ou nenhum. Ruído, percussão e sons sem altura clara são ignorados (ficam sem nota).
- Os quadros com energia **abaixo do `Nível de silêncio`** (RMS; −45 dB por padrão) contam como silêncio e cortam a nota.
- As alturas passam por uma mediana de 5 quadros (tira saltos de oitava de um quadro só). Uma nota nova nasce quando a altura se afasta **0,7 semitom ou mais** da altura média da nota atual por **3 quadros seguidos** (uns 35 ms a 44,1 kHz). Vibrato pequeno (até ±0,3 semitom, nos testes) **não** divide a nota; glissando e bends acabam em degraus de nota.
- Notas mais curtas que a `Nota mínima` (60 ms por padrão) são descartadas.
- Altura arredondada para o semitom mais próximo (mediana da nota). Sem bend nem microafinação: uma voz desafinada pode cair na nota vizinha.
- Os tempos vêm em segundos com resolução de um quadro (cerca de 11 ms a 44,1 kHz): **não são quantizados**.
- O diálogo oferece 20 a 500 ms de nota mínima e −80 a −20 dB de nível de silêncio. O servidor aceita mais (duração mínima de 0 a 5000 ms e piso de −120 a −10 dB) e recusa com `400` o que passar disso, mas o app não passa da faixa dos controles. O teto de −10 dB do piso é do servidor (acima de −6 dB a conta da velocidade das notas deixaria de fazer sentido); antes era 0 dB.
- Áudio com taxa alta é reduzido antes da análise (faixas de 60 kHz para cima, por média de blocos, chegando a uns 30 kHz).

**Formato do arquivo**
- O servidor decodifica: **WAV** (caminho rápido próprio: PCM inteiro de 16, 24 ou 32 bits, ou float de 32 bits, inclusive o formato `EXTENSIBLE`), **FLAC**, **MP3**, **OGG Vorbis**, **AAC/M4A** e **ALAC** (esses cinco pela biblioteca symphonia). Mono ou estéreo: estéreo é misturado em mono para a análise. Taxa de amostragem até 655 350 Hz.
- **Não entram:** **OGG/Opus** (a symphonia não decodifica Opus), AIFF, WebM/MKV (nenhum desses decodificadores está ligado no servidor: `server/Cargo.toml` lista só `flac`, `mp3`, `ogg`, `vorbis`, `aac`, `isomp4` e `alac`), WAV de 8 ou 64 bits, e qualquer arquivo com mais de 2 canais ou cuja taxa/canais mudem no meio. Nesses casos a conversão falha com uma mensagem clara (ver "Mensagens"). Um arquivo OGG/Opus tem mensagem própria: `Áudio Opus não é suportado; converta para WAV, FLAC, MP3, OGG Vorbis ou AAC/M4A.` O servidor reconhece o Opus por um cabeçalho `OpusHead` nos primeiros 512 bytes do Ogg; foi conferido por testes automáticos com um cabeçalho sintético, não com um `.opus` de verdade `(testado só por testes automáticos; não executado com um arquivo Opus real)`.
- O app manda o arquivo no formato **original** em que foi importado; não precisa converter antes. Um MP3 importado como clipe foi convertido em notas pelo menu do clipe no Chrome (visto rodando); FLAC, OGG Vorbis e M4A foram exercitados só por testes automáticos `(testado só por testes automáticos)`.
- **Limite de 10 minutos por conversão, medido no trecho e não no arquivo** (a memória e o tempo de análise crescem com a duração). O trecho é o do clipe mais os 0,25 s de folga de cada lado, então um clipe de até cerca de **599,5 s** de áudio converte (599,75 s se começa no início do arquivo); um WAV com o trecho acima disso é recusado antes de virar amostras, nos outros formatos a recusa vem durante a decodificação. Exatamente 10 minutos de trecho passa. Um clipe curto cortado de um arquivo de mais de 10 minutos **converte** normalmente (antes o limite valia para o arquivo inteiro e esse caso falhava). O limite do arquivo inteiro só vale para a tarefa de FLAC do servidor, que o app hoje não pede.
- Arquivo **cortado no meio** (download interrompido, por exemplo) ainda converte o que deu para ler; pacote corrompido no meio é pulado. Cortado antes do primeiro quadro, falha.
- Gravações feitas no próprio jopendaw saem como WAV de 32 bits float e funcionam.
- Dá para converter um clipe **aparado**: o app pede ao servidor só o trecho que o clipe toca (com 0,25 s de folga de cada lado) e usa as notas dentro da janela do clipe. O servidor decodifica o arquivo até o fim do trecho (o que vem antes do começo dele é decodificado e descartado, sem ficar na memória), então um clipe que começa muito fundo num arquivo comprido leva um pouco mais para começar a analisar. `(deduzido do código; não medido)` Os tempos das notas voltam em segundos do arquivo inteiro e o app os alinha ao clipe.
- Clipe com **mais de cerca de 10 minutos** de comprimento (arquivo tocado inteiro, sem cortar) ainda falha, agora com `Trecho longo demais: o máximo é 10 minutos.`: corte o clipe em partes e converta uma de cada vez.

**Mensagens que podem aparecer no diálogo** (texto lido do código)

| Mensagem | Quando |
|---|---|
| `O clipe não existe mais.` | O clipe foi apagado antes de começar |
| `Entre na sua conta para converter áudio em notas.` | Sem sessão |
| `Formato de áudio não suportado (aceitos: WAV, FLAC, MP3, OGG Vorbis e AAC/M4A, mono ou estéreo).` | O arquivo não é de um dos formatos acima, está com lixo no lugar do áudio, tem mais de 2 canais ou mudou de taxa/canais no meio |
| `Trecho longo demais: o máximo é 10 minutos.` | O trecho que o clipe toca (mais a folga de 0,25 s de cada lado) passa de 10 minutos. Vem como recusa na criação da tarefa ou, se o servidor só percebe ao decodificar, como falha da tarefa; o texto é o mesmo |
| `Áudio Opus não é suportado; converta para WAV, FLAC, MP3, OGG Vorbis ou AAC/M4A.` | O arquivo é Ogg com fluxo Opus |
| `Não consegui decodificar o áudio (arquivo corrompido ou formato não suportado).` | O formato foi reconhecido, mas nenhum pacote de áudio pôde ser decodificado |
| `O trecho pedido está fora do áudio.` | O trecho do clipe não pegou nenhuma amostra (por exemplo, o clipe aponta para além do fim do arquivo, ou o arquivo não tem amostras). O app sempre pede um trecho, então é esta a mensagem no lugar de `Áudio vazio.` |
| `Áudio longo demais: o máximo é 10 minutos.` e `Áudio vazio.` | São as mensagens do servidor para um pedido **sem** trecho (arquivo inteiro). O app sempre manda o trecho do clipe, então elas não devem aparecer aqui `(deduzido do código)` |
| `Áudio não encontrado no armazenamento.` | O servidor não achou o arquivo enviado (falha rara de armazenamento) |
| `Não encontrei notas neste áudio.` | A análise voltou sem nenhuma nota |
| `O clipe foi apagado durante a conversão.` | Você apagou o clipe enquanto esperava |
| `Você já tem 10 tarefas em andamento; aguarde alguma terminar.` | Já há 10 tarefas suas na fila ou rodando (limite por conta) |
| `O servidor terminou sem devolver as notas.` | Resposta sem resultado |
| `A conversão falhou no servidor.` | Falha sem mensagem específica |
| `Cota de armazenamento de 4 GB excedida; apague áudios sem uso na tela Conta.` / `Arquivo grande demais (máximo de 512 MB).` | O áudio não coube no envio (cota de 4 GB da conta, ver [01b](01b-nuvem-e-sincronizacao.md#cotas-e-limites); ou 512 MB por arquivo). O texto da cota é o mesmo em qualquer lugar em que ela estoure (envio e tarefa de FLAC do servidor) |
| `Min_note_ms: número entre 0 e 5000.` / `Rms_floor_db: número entre -120 e -10.` | O servidor recusa valores fora da faixa dele. O diálogo não deixa chegar lá (os controles vão de 20 a 500 ms e de −80 a −20 dB), então só aparecem se algo mandar o pedido por fora do app `(testado só por testes automáticos)` |
| `Sem conexão com o servidor. Tente de novo.` / `A sessão acabou. Entre de novo.` | Rede caiu ou sessão venceu |

**Espera**
- O tempo é o de **enviar** o arquivo **inteiro** (uma vez; se o áudio já estava no servidor por causa da sincronização, não sobe de novo; um clipe curto de um arquivo grande também sobe o arquivo todo) mais **esperar a vez** (o servidor roda no máximo **2** conversões ao mesmo tempo, de todas as contas) mais a **análise**, que cresce em proporção à duração do áudio (áudio em silêncio é rápido, porque quadros silenciosos pulam a parte cara).
- Uma estimativa grosseira pelo código, não medida: da ordem de alguns segundos de análise por minuto de áudio numa máquina comum (não confirmado). Não há limite de tempo no app: ele acompanha a tarefa a cada 1 s e tolera até 5 falhas de rede seguidas no acompanhamento (a tarefa segue no servidor).
- Se você cancela ou fecha o app, a tarefa não é interrompida no servidor.

**Coerência com o clipe**
- **Warp:** as notas ficam alinhadas ao clipe qualquer que seja o andamento do projeto. Com o warp ligado (o clipe esticado ao andamento do projeto) os segundos do áudio viram batidas pelo andamento do **próprio áudio**, o mesmo com que o clipe toca; sem warp, pelo do projeto. Não precisa mais desligar o warp antes de converter.
- **Transposição:** o valor do clipe (`+3 st`) é somado à altura das notas (arredondado ao semitom, limitado a 0..127). O clipe de notas soa na altura que o clipe de áudio soa.
- **Reverso:** com o clipe invertido, as notas são espelhadas dentro da janela (o que era o fim vira o começo).
- **Só vale na hora da conversão:** as notas ficam gravadas no clipe de notas, em batidas. Se depois você mudar o warp, a transposição, o reverso ou o andamento do projeto, o clipe de notas **não** acompanha; para refazer, converta de novo. `(deduzido do código; o clipe de notas não guarda vínculo com o de áudio)`
- Ganho do clipe e volume da faixa não mexem na análise nem na velocidade das notas: ela vem do volume do arquivo original.
- Essas regras vêm do código e dos testes automáticos do app `(testado só por testes automáticos)`.

## Atalhos

Nenhum atalho para converter. Depois da conversão, o clipe de notas fica selecionado: `E` abre o editor (piano roll), `S` corta no cursor, `Ctrl+D` duplica, `Delete` apaga.
