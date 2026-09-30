# Áudio para MIDI

> Transforma um clipe de áudio **monofônico** (voz, assobio, baixo, flauta, uma linha de solo) em notas: o servidor analisa o som e o app cria uma faixa de sintetizador com um clipe de notas por cima do clipe de áudio.

## Onde fica

Botão direito no clipe de áudio (computador) ou toque longo (celular), item `Converter em notas (MIDI)` (ícone de piano). Abre o diálogo `Converter em notas (MIDI)`. Não há botão na barra nem atalho.

Precisa de **conta** (entrar no app) e de conexão com o servidor: a análise roda lá, não no aparelho.

## Controles

O diálogo **não tem opções para ajustar**: ele começa a converter assim que abre. Os controles são só de acompanhamento.

| Controle (rótulo exato) | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| Título `Converter em notas (MIDI)` | Identifica o diálogo. Ele não fecha ao clicar fora | | |
| Texto de etapa | Diz em que passo está: `Enviando o áudio…` (o arquivo sobe ao servidor), `Na fila do servidor…` (esperando vez), `Analisando o áudio…` (a análise em si) | | |
| Barra de progresso | Vazia e "correndo" (indeterminada) enquanto envia, espera na fila ou o servidor ainda não informou; depois mostra a fração da análise | Atualiza a cada 1 s | Depois de ler o arquivo o servidor marca 10%; a análise leva o valor até 100%. O servidor grava o progresso a cada 0,5 s e o app consulta a cada 1 s, então a barra anda em saltos |
| `Cancelar` | Fecha o diálogo e para de acompanhar | | **Não cancela o trabalho no servidor**: a tarefa termina lá, mas o resultado é descartado e nenhuma faixa é criada. Se o envio já estava em curso, ele conclui mesmo assim |
| Mensagem de erro (no lugar da barra) + `Fechar` | Mostra por que não deu e o botão `Fechar` | Ver "Mensagens" abaixo | |

Quando dá certo o diálogo **fecha sozinho** e nasce uma faixa nova. Não aparece contagem nem mensagem de sucesso.

### O que a conversão cria

| O que | Como fica |
|---|---|
| Faixa nova | Tipo `Sintetizador`, no **fim** da lista, com o nome `Sintetizador N` (o próximo N livre) e a cor seguinte da paleta. Fica selecionada. O clipe de áudio original continua intacto |
| Clipe de notas | Mesmo nome da faixa, começa **no mesmo ponto** do clipe de áudio e cobre **a mesma duração** dele |
| Notas | Só as que caem dentro do trecho que o clipe de áudio mostra (respeita o corte à esquerda e à direita: o que foi aparado fica de fora, e notas que atravessam a borda são cortadas nela). Início e duração em **batidas** no andamento do projeto. Altura de 0 a 127 |
| Velocidade de cada nota | Vem do volume do trecho: de −45 dBFS (piso, o mínimo, 5%) a −6 dBFS (100%) |
| Desfazer | Tudo (a faixa e o clipe) é **um** passo do desfazer |

A faixa usa o sintetizador padrão. Troque o som pelo painel do instrumento (`I`).

## Passo a passo

**Transformar uma melodia cantada em notas**
1. Grave (ou importe) a melodia como **WAV**, sem base nenhuma por baixo, e com o microfone bem perto.
2. Ajuste o clipe: apare o começo e o fim para pegar só a linha.
3. Botão direito no clipe, `Converter em notas (MIDI)`. Espere: `Enviando o áudio…`, `Analisando o áudio…`.
4. Ao terminar, abra o clipe de notas no editor (`E` com ele selecionado) e limpe: as notas têm tempos **soltos**, sem grade.
5. Quantize (`Q` no editor) e apague ou una notas que sobraram.

**Se aparece "Não encontrei notas neste áudio."**
1. Confira se o trecho não é só ruído, percussão ou silêncio.
2. Se o volume é baixo (abaixo de −45 dBFS de RMS), o servidor trata como silêncio. Aumente o ganho na fonte e grave de novo (o clipe não tem controle de ganho).

## Combina com

- [Gravação](03c-gravacao.md): a gravação do microfone sai como WAV, o formato que o servidor lê.
- [Áudio e clipes](03-audio-e-clipes.md): apare o clipe antes de converter para levar só o que interessa.
- [Warp e altura](03b-warp-e-altura.md): a conversão ignora warp, transposição e reverso do clipe (ver abaixo).
- [Editor de notas (piano roll)](05-piano-roll.md): onde limpar e quantizar as notas que a conversão cria.

## Limites e pegadinhas

**O que o detector faz (servidor, `server/src/audio.rs`)**
- Usa o **YIN**, um detector de altura para **uma nota de cada vez** (monofônico). Ele analisa quadros de 2048 amostras a cada 512, acha o período fundamental e converte para nota MIDI.
- Faixa de alturas: **50 Hz a 2000 Hz** (de cerca de sol 1, nota 31, até cerca de si 6, nota 95). Abaixo ou acima disso a altura não é reconhecida.
- **Não faz polifonia.** Acordes, violão tocando várias cordas, piano com mão esquerda, mixagem inteira ou vozes sobrepostas dão resultado errado ou nenhum. Ruído, percussão e sons sem altura clara são ignorados (ficam sem nota).
- Os quadros com energia **abaixo de −45 dBFS (RMS)** contam como silêncio e cortam a nota.
- As alturas passam por uma mediana de 5 quadros (tira saltos de oitava de um quadro só). Uma nota nova nasce quando a altura se afasta **0,7 semitom ou mais** da altura média da nota atual por **3 quadros seguidos** (uns 35 ms a 44,1 kHz). Vibrato pequeno (até ±0,3 semitom, nos testes) **não** divide a nota; glissando e bends acabam em degraus de nota.
- Notas com **menos de 60 ms** são descartadas.
- Altura arredondada para o semitom mais próximo (mediana da nota). Sem bend nem microafinação: uma voz desafinada pode cair na nota vizinha.
- Os tempos vêm em segundos com resolução de um quadro (cerca de 11 ms a 44,1 kHz): **não são quantizados**.
- O servidor sabe usar outros limites (duração mínima de 0 a 5000 ms e piso de ruído de −120 a 0 dB), mas o app **não os envia**: o diálogo usa sempre 60 ms e −45 dB.
- Áudio com taxa alta é reduzido antes da análise (faixas de 60 kHz para cima, por média de blocos, chegando a uns 30 kHz).

**Formato do arquivo: só WAV**
- O servidor lê **WAV** (PCM inteiro de 16, 24 ou 32 bits, ou float de 32 bits; mono ou estéreo). Estéreo é misturado em mono para a análise.
- Clipe importado de **MP3, FLAC, OGG, M4A, AAC, AIFF, Opus, WebM** vai ao servidor no formato de origem e a conversão **falha** com `Formato não suportado.` (também falha WAV de 8 bits ou 64 bits, e mais de 2 canais). Para converter, exporte/converta o áudio para WAV antes de importar.
- Gravações feitas no próprio jopendaw saem como WAV de 32 bits float e funcionam.
- Dá para converter um clipe **aparado**: o servidor analisa o arquivo inteiro e o app usa só as notas dentro da janela do clipe.

**Mensagens que podem aparecer no diálogo** (texto lido do código)

| Mensagem | Quando |
|---|---|
| `O clipe não existe mais.` | O clipe foi apagado antes de começar |
| `Entre na sua conta para converter áudio em notas.` | Sem sessão |
| `Formato não suportado.` | O arquivo não é WAV nos formatos acima |
| `Áudio vazio.` | WAV sem amostras |
| `Não encontrei notas neste áudio.` | A análise voltou sem nenhuma nota |
| `O clipe foi apagado durante a conversão.` | Você apagou o clipe enquanto esperava |
| `Você já tem 10 tarefas em andamento; aguarde alguma terminar.` | Já há 10 tarefas suas na fila ou rodando (limite por conta) |
| `O servidor terminou sem devolver as notas.` | Resposta sem resultado |
| `A conversão falhou no servidor.` | Falha sem mensagem específica |
| `Cota de armazenamento de 4 GB excedida; apague áudios que não usa mais.` / erro de tamanho | O áudio não coube no envio (limite de 512 MB por arquivo) |
| `Sem conexão com o servidor. Tente de novo.` / `A sessão acabou. Entre de novo.` | Rede caiu ou sessão venceu |

**Espera**
- O tempo é o de **enviar** o arquivo (uma vez; se o áudio já estava no servidor por causa da sincronização, não sobe de novo) mais **esperar a vez** (o servidor roda no máximo **2** conversões ao mesmo tempo, de todas as contas) mais a **análise**, que cresce em proporção à duração do áudio (áudio em silêncio é rápido, porque quadros silenciosos pulam a parte cara).
- Uma estimativa grosseira pelo código, não medida: da ordem de alguns segundos de análise por minuto de áudio numa máquina comum (não confirmado). Não há limite de tempo no app: ele acompanha a tarefa a cada 1 s e tolera até 5 falhas de rede seguidas no acompanhamento (a tarefa segue no servidor).
- Se você cancela ou fecha o app, a tarefa não é interrompida no servidor.

**Coerência com o clipe**
- **Com warp ligado** (o clipe esticado ao andamento do projeto), as notas são convertidas de segundos para batidas pelo andamento do **projeto**, mas o clipe de notas e o clipe de áudio têm a duração em batidas calculada pelo andamento do **áudio**; se os dois andamentos diferem, as notas ficam **fora de sincronia** com o clipe. Para converter, desligue o warp antes (`Desligar o warp`), converta e religue. (Comportamento lido do código; não testado.)
- Transposição (`+3 st`) e reverso do clipe de áudio **não** entram: as notas saem da altura do arquivo original, para frente.

## Atalhos

Nenhum atalho para converter. Depois da conversão, o clipe de notas fica selecionado: `E` abre o editor (piano roll), `S` corta no cursor, `Ctrl+D` duplica, `Delete` apaga.
