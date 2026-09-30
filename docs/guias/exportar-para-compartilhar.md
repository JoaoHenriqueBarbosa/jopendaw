# Exportar para compartilhar e arquivar

> Sair do WAV: mandar uma prévia leve em MP3 por mensagem, guardar o som sem perda em FLAC e entregar o master final em WAV 24 bits mais MP3 320, tudo pela janela `Exportar áudio`; de 5 a 10 minutos por arquivo, com conta e rede.

## Ingredientes

| Recurso | Para quê aqui | Capítulo |
|---|---|---|
| Formato `MP3 (para compartilhar)` e a lista `Qualidade do MP3` | Arquivo pequeno, com perda, que abre em qualquer lugar | [08 Exportação, FLAC e MP3 pelo servidor](../manual/08-exportacao.md#flac-e-mp3-pelo-servidor) |
| Formato `FLAC (sem perda, menor)`, chips `16 bits` e `24 bits` e a lista `Padrão` / `Rápido` / `Menor arquivo` | Guardar o som idêntico ao WAV, ocupando menos espaço | [08 Exportação, Formatos](../manual/08-exportacao.md#formatos) |
| Formato `WAV 24 bits` | O arquivo de estúdio, para masterizar ou converter depois | [08 Exportação](../manual/08-exportacao.md) |
| `Normalizar o loudness` (chips `Streaming −14,0`, `Podcast −16,0`, `Broadcast −23,0`) e `Teto de true peak` | Entregar no volume que a plataforma espera, também nos arquivos convertidos | [08 Exportação, Normalizar o loudness](../manual/08-exportacao.md#normalizar-o-loudness), [guia Loudness e master](loudness-e-master.md) |
| `Stems` | Um FLAC por faixa para arquivar o projeto separado | [08 Exportação, Stems](../manual/08-exportacao.md#stems) |
| `Exportar em WAV mesmo assim` | Não perder o render se o servidor falhar | [08 Exportação, FLAC e MP3 pelo servidor](../manual/08-exportacao.md#flac-e-mp3-pelo-servidor) |
| Sua conta e a cota de 4 GB | A conversão é feita no servidor: o WAV sobe, volta o arquivo, e o app apaga os dois | [01b Nuvem e sincronização, Cotas e limites](../manual/01b-nuvem-e-sincronizacao.md#cotas-e-limites) |

O que vale para os três cenários:

- **Precisa de conta e de rede.** O motor do app só escreve WAV; FLAC e MP3 são gerados no servidor a partir do WAV que o app renderiza no aparelho. Sem conta, sem rede ou com erro do servidor, a janela oferece `Exportar em WAV mesmo assim` (salva o WAV já renderizado, sem renderizar de novo).
- **Até 30 minutos por arquivo** (trecho mais `Cauda`). Passando disso, aparece o aviso `O servidor converte até 30 minutos por arquivo: escolha um trecho menor, diminua a cauda ou exporte em WAV.` e `Exportar` fica desligado.
- **O WAV que sobe não pode passar de 512 MB.** Em taxa e profundidade altas (por exemplo 96 kHz e 24 bits) isso acontece antes dos 30 minutos, com uns 15 minutos: a janela mostra `O WAV desta música passa de 512 MB (N MB), o limite do servidor para converter: exporte em WAV, ou reduza a taxa de amostragem, o trecho ou a cauda.` e deixa `Exportar` desligado, em vez de descobrir no envio.
- **O MP3 só existe a 44,1 ou 48 kHz.** Ao escolher `MP3 (para compartilhar)` com outra taxa, a janela passa a taxa para 44,1 kHz sozinha.
- **Tamanhos:** um MP3 CBR pesa a taxa dividida por 8: 128 kbps dá cerca de 0,96 MB por minuto, 192 kbps 1,44 MB, 256 kbps 1,92 MB e 320 kbps 2,40 MB. O WAV 24 bits a 48 kHz pesa 17,3 MB por minuto e o FLAC fica em geral bem abaixo disso (estimativa de 50% a 70%, varia com a música `(não confirmado)`).

## Passo a passo

### Cenário 1: uma prévia em MP3 para mandar por mensagem

1. Com a sessão aberta, toque em `Exportar` na barra do transporte.
2. Em `FORMATO`, escolha `MP3 (para compartilhar)`. Em `Qualidade do MP3`, deixe `192 kbps (CBR)` (padrão) ou, se quiser o menor arquivo, `128 kbps (CBR)`.
3. Deixe `INTERVALO` em `Música inteira` (ou `Região do loop`, para mandar só o refrão; se a música tem marcadores, o menu do marcador tem **Exportar esta seção…**, que já abre em `Entre marcadores`, ver o [guia de seções e stems](entregar-uma-musica-por-secoes-e-stems.md#cenário-2-só-o-refrão-em-mp3-para-uma-prévia)) e `Cauda` em 2 s.
4. Se quiser que a prévia soe no volume de um serviço de streaming, ligue `Normalizar o loudness` e deixe `Streaming −14,0` com o teto em −1,0 dBTP.
5. Se quiser o seu nome nos metadados e no nome do arquivo, preencha `Artista (opcional)` (o campo aparece com FLAC e MP3).
6. Toque em `Exportar`. Acompanhe `Enviando ao servidor…`, `Na fila do servidor…` (só se outra exportação estiver sendo convertida), `Compactando no servidor N%…`, `Baixando o arquivo…`. A barra soma o render (metade) e a conversão (outra metade) e não volta para trás. Ao fim, `Exportação concluída` (o texto sai como `A mixagem foi salva (MP3) em N s.`).
7. Pegue o arquivo `<nome do projeto>.mp3` (ou `<artista> - <nome do projeto>.mp3`, se preencheu o artista) nos downloads (no Android, escolha onde salvar) e envie. Uma prévia de 3 minutos a 192 kbps tem cerca de 4,3 MB; a 128 kbps, cerca de 2,9 MB.

### Cenário 2: arquivar em FLAC

1. `Exportar` e, em `FORMATO`, `FLAC (sem perda, menor)`.
2. Nos chips, deixe `24 bits` (o mesmo que o WAV de estúdio). Na lista, `Padrão` serve; `Menor arquivo` demora mais e economiza um pouco de espaço; `Rápido` o contrário.
3. Deixe `Normalizar` e `Normalizar o loudness` **desligados**: o arquivo morto guarda o som como saiu do mix, com folga para masterizar depois.
4. Para guardar o projeto separado por faixa, ligue `Stems`. Cada faixa vira um `.flac` (`<projeto> - <faixa>.flac`, com `<artista> - ` na frente se você preencheu `Artista (opcional)`), convertido um de cada vez; faixa muda sai de fora.
5. `Exportar`. Guarde os arquivos junto do `.jopendaw` do projeto (`Projeto inteiro (.jopendaw)…` na mesma janela; ver [Backup e levar o projeto](backup-e-levar-projeto-para-outro-aparelho.md)): o FLAC guarda o som, o `.jopendaw` guarda o projeto editável.

### Cenário 3: o master final em WAV 24 bits e MP3 320

Pressuposto: o mix já passou pelo guia [Loudness e master](loudness-e-master.md), com um `Limitador` no `Master`.

1. Exporte primeiro o **WAV**: `WAV 24 bits`, `Normalizar o loudness` ligado, chip `Streaming −14,0`, `Teto de true peak` em −1,5 dBTP (folga para o MP3, ver "Por que funciona"). Leia a frase do resultado: `mediu −14,0 LUFS` quer dizer que chegou.
2. Abra `Exportar` de novo: a janela já abre com as últimas opções (alvo e teto ficam guardados até fechar o app). Troque só o `FORMATO` para `MP3 (para compartilhar)` e, em `Qualidade do MP3`, para `320 kbps (CBR)` (ou `V0 (VBR, ~245 kbps, a melhor)` para um arquivo menor).
3. `Exportar`. Os dois arquivos saem com o mesmo nome e extensões diferentes (`<projeto>.wav` e `<projeto>.mp3`), então não se sobrescrevem. Se você preencher `Artista (opcional)`, só o MP3 (e o FLAC) leva o artista: `<artista> - <projeto>.mp3`, enquanto o WAV continua `<projeto>.wav`.
4. Ouça o MP3 de ponta a ponta antes de mandar. A frase de loudness do segundo export descreve o WAV que foi ao servidor, não o MP3.
5. Entregue o WAV 24 bits a quem vai masterizar ou distribuir e o MP3 320 a quem só vai ouvir. Guarde o WAV (ou um FLAC dele, cenário 2).

## Variações

- **Prévia mínima.** `128 kbps (CBR)` ou `V4 (VBR, ~165 kbps)`, `Região do loop` com o trecho que interessa. Menos de 1 MB por minuto.
- **FLAC de 16 bits.** Chip `16 bits`: para tocar em aparelho que não lê 24 bits. O WAV que sobe ao servidor é de 16 bits, com dither.
- **Podcast.** MP3 com `Normalizar o loudness` no chip `Podcast −16,0` (ver [Loudness e master, variações](loudness-e-master.md#variações)).
- **Guardar em FLAC e ainda tocar em um leitor simples.** Exporte os dois formatos, um de cada vez; a janela guarda as últimas opções.
- **Uma seção por arquivo, ou só algumas faixas (fase 26 C).** Com marcadores na régua, `Uma por seção` exporta cada parte da música como um arquivo (o nome do marcador vai no nome), o bloco `Faixas` limita a mixagem e os stems às faixas marcadas e `Reunir num .zip` entrega tudo num arquivo só; vale também em MP3 e FLAC, com cada arquivo convertido pelo servidor, um de cada vez. Receita: [Entregar uma música por seções e stems](entregar-uma-musica-por-secoes-e-stems.md). Cuidado: `Normalizar o loudness` passa a valer por arquivo (cada seção vai ao alvo por conta própria).
- **Vários stems.** Cada arquivo espera a fila do servidor: 8 stems são 8 conversões em série (e, se outra pessoa estiver exportando no mesmo servidor, a sua espera em `Na fila do servidor…`). Deixe a aba aberta até a janela dizer `Exportação concluída`; se ela disser `Exportação cancelada`, no Android, é porque a janela `Salvar` foi fechada (vale para FLAC, MP3 e também para o WAV direto, desde a fase 19: antes o WAV terminava em `Exportação concluída` mesmo sem salvar nada; desde a fase 22 o aviso do WAV direto diz o nome do arquivo e quantos já saíram).

## Por que funciona

- **O WAV é o intermediário.** O app renderiza o WAV no aparelho, exatamente como nas exportações de sempre (mesmo motor, mesma normalização, mesmo limitador de −0,3 dBFS do master), e só depois o servidor o converte. Por isso o FLAC decodificado é idêntico ao WAV e por isso o loudness medido é o do WAV.
- **O MP3 sai de um WAV de 16 bits.** O app manda 16 bits (com dither) ao servidor para o MP3. Não há vantagem em mandar mais bits a um formato com perda; para preservar os 24 bits, use o FLAC ou o WAV.
- **Perda no MP3.** Um MP3 é um arquivo com perda: o pico e o loudness dele podem ficar um pouco diferentes do WAV. O `Teto de true peak` de −1,5 dBTP no passo 1 do cenário 3 deixa folga para isso (medida pensada como margem, não medida no codificador do servidor `(não confirmado)`).
- **Só o que precisa passa pelo servidor.** O WAV temporário e o arquivo convertido contam na cota de 4 GB enquanto existem e o app os apaga sozinho depois de salvar; os stems seguem a mesma regra, um por vez.
- **Sempre há saída.** Se a conversão falhar, o WAV renderizado fica guardado na janela: você não paga o render de novo.

## Se der errado

| Sintoma | Causa provável | O que fazer |
|---|---|---|
| Janela `Não deu para compactar`: `Entre na sua conta para exportar em MP3: a conversão é feita no servidor.` | Sem sessão | Entre na conta e volte às opções, ou `Exportar em WAV mesmo assim` |
| `Não consegui falar com o servidor (sem conexão?).` | Sem rede | Reconecte e `Voltar às opções` (refaz o render) ou salve o WAV agora |
| `Sua sessão terminou; entre de novo para exportar em MP3.` | A sessão expirou no meio | Entre de novo; `Exportar em WAV mesmo assim` guarda o que já estava pronto |
| `cota de armazenamento de 4 GB excedida; apague áudios sem uso na tela Conta` | A conta está cheia (o WAV temporário também conta) | Na tela `Conta`, `Limpar áudios sem uso`; depois `Voltar às opções` |
| `O WAV desta música passa de 512 MB ...` e `Exportar` desligado | O WAV que sobe ao servidor passaria de 512 MB (acontece com trechos longos a 88,2 ou 96 kHz) | Exporte em WAV, ou reduza a taxa, o trecho ou a cauda |
| `O servidor demorou demais para responder.` | Envio ou conversão lentos (teto de 120 s por pedido e de 20 min de espera) | Tente de novo, com um trecho menor ou numa rede melhor |
| `O servidor converte até 30 minutos por arquivo...` e `Exportar` desligado | Trecho mais `Cauda` acima de 30 minutos | `Região do loop`, cauda menor ou WAV |
| A taxa mudou para 44,1 kHz sozinha | O MP3 só aceita 44,1 e 48 kHz | Escolha `48 kHz`, se preferir |
| Cancelei e sobrou áudio na conta | Só num servidor antigo: ele não cancela a conversão em andamento (`409`) | O app tenta apagar de novo depois de 3, 10 e 30 s; se sobrar, na tela `Conta`, `Limpar áudios sem uso` (só leva o que subiu há mais de 1 hora) |
| A janela diz `Exportação cancelada: você não escolheu onde salvar` (o nome do arquivo vem entre aspas, com FLAC, MP3 e, desde a fase 22, também no WAV direto; se algum arquivo já tinha sido salvo, o aviso acrescenta `O arquivo anterior já tinha sido salvo.` ou `Os N arquivos anteriores já tinham sido salvos.`) | Você fechou a janela `Salvar <nome>` do Android | `Voltar às opções` e exporte de novo, concluindo o `Salvar <nome>`. A exportação para no arquivo cancelado: os stems seguintes não são oferecidos |
| `1 arquivo foi salvo compactado` / `N arquivos foram salvos compactados` no aviso `Não deu para compactar` | Parte dos stems já saiu em FLAC ou MP3 antes da falha | `Exportar em WAV mesmo assim` salva só os que faltam, em WAV |
| O MP3 soa mais alto ou estoura na decodificação | Pico do MP3 acima do WAV | Baixe o `Teto de true peak` (−1,5 ou −2,0 dBTP) e exporte de novo |
| Aviso `Um efeito está em solo ou ouvindo a banda: a exportação sairá assim (...)` | Um `Solo` de banda do `Multibanda` ou o `Ouvir banda` do `De-esser` ficou ligado (o cartão do efeito mostra o selo `SOLO` ou `OUVINDO A BANDA`) | Feche a janela, desligue o solo ou o `Ouvir banda` e exporte de novo; o aviso não impede a exportação |
