# Warp e altura

> Faz um clipe de áudio seguir o andamento do projeto sem mudar o tom, transpõe em semitons sem mudar a velocidade e toca de trás para a frente; serve para encaixar loops e samples de andamentos diferentes.

## Onde fica

Clique com o botão direito no clipe de áudio (computador) ou faça um toque longo (celular) e escolha `Warp e altura…`. Abre o diálogo `Warp e altura`, que vale para o clipe em que você clicou. Não há botão de warp na barra: o único caminho é o menu do clipe.

O que o diálogo faz fica guardado no clipe (não no arquivo): o áudio original nunca é alterado.

## Controles

### Seção `ANDAMENTO`

| Controle (rótulo exato) | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| Campo `BPM do áudio` | O andamento em que o áudio **foi gravado**. É a base do warp: o clipe é esticado por (BPM do áudio ÷ BPM do projeto) | 20 a 999 BPM; aceita vírgula ou ponto (`120,5`). Vem preenchido com o valor já usado no clipe; vazio no clipe sem warp | `Enter` no campo equivale a `Ajustar ao andamento` |
| `÷2` (tooltip `Metade (÷2)`) | Divide o BPM do campo por 2 (arredonda a 0,1) e já aplica | Resultado limitado a 20 a 999 | Use quando o detector achou o dobro do real (ex.: 180 no lugar de 90) |
| `×2` (tooltip `Dobro (×2)`) | Multiplica o BPM do campo por 2 (arredonda a 0,1) e já aplica | Idem | Use quando achou a metade |
| `Detectar` (vira `Analisando…` enquanto trabalha) | Estima o andamento do arquivo de áudio, preenche o campo e **liga o warp na hora** com esse valor | Detector: 60 a 200 BPM, ver abaixo | Se o resultado for meio ou dobro do real, corrija com `÷2` ou `×2` |
| Linha `Detectado: …` | Mostra o resultado, por exemplo `Detectado: 120 BPM, confiança 87%` | Arredondado a 0,1 BPM; confiança em % | Abaixo de 35% de confiança, o texto acrescenta `(baixa: confira de ouvido)` |
| `Ajustar ao andamento` | Lê o campo `BPM do áudio`, liga o warp e passa a esticar o clipe para seguir o andamento do projeto | Campo fora de 20 a 999: aviso `Digite um andamento entre 20 e 999 BPM.` | É o botão para quando você sabe o andamento e digita |
| `Desligar o warp` (só aparece com o warp ligado) | Desliga o esticamento. O número no campo fica guardado; para religar, `Ajustar ao andamento` | | Não zera a transposição nem o reverso |
| Texto de estado (abaixo dos botões) | Com warp: `Segue o andamento do projeto (<BPM> BPM): o áudio é esticado sem mudar a altura.` Sem warp: `Sem warp: o clipe toca na velocidade original.` | | O BPM que aparece é o do projeto |

### Seção `ALTURA`

| Controle (rótulo exato) | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| Botão `−` (tooltip `Um semitom abaixo`) | Baixa a altura em 1 semitom | −24 a +24 semitons; desligado em −24 | Cada clique é um passo no desfazer |
| Leitura `+3 st` / `-5 st` / `0 st` | Mostra a transposição atual | Passos de 1 st pela interface | Valores fracionários existem no documento, mas a interface só anda de 1 em 1 |
| Botão `+` (tooltip `Um semitom acima`) | Sobe a altura em 1 semitom | Desligado em +24 | 12 semitons = 1 oitava |
| `Zerar` | Volta a transposição para 0 | Desligado quando já está em 0 | |

### Restante do diálogo

| Controle (rótulo exato) | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| Interruptor `Inverter o áudio` | Toca o clipe de trás para a frente. Vale o trecho que o clipe mostra: o que era o fim vira o começo | Desligado por padrão | O fade in continua no começo do clipe (o que ouve primeiro) e o fade out no fim |
| Barra de progresso + `processando…` | Aparece enquanto o som novo está sendo gerado | | Enquanto isso o clipe toca o **original** |
| Aviso `O warp não ficou pronto (…): o clipe toca o original.` | Aparece se a geração falhou; o motivo vem entre parênteses | Ex.: `O áudio original não está neste aparelho.` | O clipe fica com o selo de borda vermelha |
| Aviso de erro do detector | `O áudio deste clipe não está neste aparelho.` ou o texto da falha | | |
| Aviso `Não deu para achar o andamento (pouca batida ou trecho curto). Digite o andamento do áudio.` | O detector devolveu "sem andamento" | Ver "O que o detector aceita" | Digite o BPM à mão e use `Ajustar ao andamento` |
| `Fechar` | Fecha o diálogo (as mudanças já estavam valendo) | | |

Tudo vale **na hora** e cada mudança é um passo do desfazer. Nada disso funciona durante uma gravação: o app avisa `Pare a gravação para mudar o warp.`.

### No clipe

O selo no canto de cima do clipe resume o que está ligado: `W` (esticado ao andamento), `+3st`/`-5st` (transposição), `R` (invertido), juntos separados por espaço, ou `processando…`. Só aparece em clipe com 40 px ou mais de largura. Falha: a borda do selo fica vermelha (tooltip `O warp não ficou pronto: o clipe toca o original`).

## Passo a passo

**Encaixar um loop de 100 BPM num projeto de 120 BPM**
1. Menu do clipe, `Warp e altura…`.
2. Toque `Detectar` (ou digite `100` no campo `BPM do áudio`).
3. Confira a linha `Detectado: …`. Se o número for o dobro ou a metade do que você sabe, use `÷2` ou `×2`.
4. Aguarde o `processando…` acabar. O clipe passa a durar menos (100 ÷ 120 da duração original) e o selo mostra `W`.
5. Feche o diálogo. Se mudar o andamento do projeto depois, o som é refeito sozinho.

**Subir um sample 3 semitons sem mudar o tempo**
1. Abra `Warp e altura…` no clipe.
2. Toque `+` três vezes (leitura `+3 st`). Não precisa ligar o warp.
3. Espere o `processando…`. Para voltar, `Zerar`.

**Tocar um clipe ao contrário**
1. Abra `Warp e altura…` e ligue `Inverter o áudio`. Reverso puro não passa pelo esticamento: fica pronto quase na hora.

## Combina com

- [Áudio e clipes](03-audio-e-clipes.md): aparar, cortar e fades; todos valem sobre o som já processado (os cortes e fades acompanham a escala do esticamento).
- [Áudio para MIDI](03d-audio-para-midi.md): a análise lê o arquivo **original**, mas as notas criadas respeitam o warp (o andamento do próprio áudio vira a régua das batidas), somam a transposição e espelham no reverso, para caírem alinhadas com o clipe como ele toca. As notas são gravadas na hora da conversão: mudar o warp depois não as move (ver "Coerência com o clipe" lá).
- [Áudio e clipes](03-audio-e-clipes.md#ganho-do-clipe): `Ganho do clipe…`, outro item do mesmo menu, muda o volume do clipe; o warp não mexe nele.
- [Mixer](06-mixer.md): o clipe esticado passa pela cadeia de efeitos da faixa como qualquer outro.

## Limites e pegadinhas

**Como funciona, em termos de uso**
- O **esticamento** usa WSOLA: o motor corta o áudio em janelas de cerca de 40 ms, escolhe o melhor ponto de emenda (procura até ±16 ms) e reemenda as janelas. As janelas são copiadas sem alterar a forma de onda, então os **transientes** (batidas de bateria, ataques) saem nítidos. A imagem estéreo é preservada: os dois canais recebem o mesmo deslocamento.
- **Soa melhor** em loops de bateria e trechos rítmicos que precisam grudar no andamento, com razões entre 0,5 e 2 (por exemplo, de 100 para 200 BPM ou de 200 para 100): é o alvo para o qual o método foi escolhido.
- **Artefatos:** em material polifônico muito denso (pad de acordes, orquestra, mixagem completa) e razões extremas aparece um "flutter" (tremulação). É um compromisso do método, aceito de propósito.
- A **transposição** estica o áudio pela razão × fator de altura e depois reamostra (sinc de alta qualidade). Como o método reamostra, ele não tem preservação de formantes: em voz falada ou cantada, transposições grandes mudam também o timbre (consequência do método, não medida) (não confirmado o quanto incomoda). Quanto menor o passo, menos se nota.
- Transposição e esticamento **juntos** duplicam o trabalho (transpor é esticar e depois reamostrar).

**Faixa de valores**
- Razão de duração (BPM do áudio ÷ BPM do projeto): **0,25 a 4**, arredondada a 4 casas. Fora disso o valor é apertado nos limites (BPM do áudio 20 a 999, do projeto 20 a 400).
- Transposição: **−24 a +24 semitons**, arredondada a 2 casas.
- Com warp ligado, um segundo do áudio original passa a ocupar sempre a mesma fração de batida (a do andamento do próprio áudio), então **a largura do clipe na linha do tempo não muda** quando você muda o andamento do projeto; o som é que é refeito para caber.

**Cache `warp:`**
- Cada combinação (áudio de origem + razão + semitons + reverso) vira um áudio derivado, gerado em segundo plano (Worker no navegador; isolate no Android) **400 ms depois da última mudança**: arrastar o andamento não refaz o som a cada valor.
- O derivado é guardado no aparelho como WAV de 32 bits float sob a chave `warp:<sha-256>|r<razão>|p<semitons>|fwd` ou `rev` (por exemplo `…|r1.2000|p0.00|fwd`). Se a mesma combinação for pedida de novo, vem do cache, sem reprocessar.
- O derivado **nunca entra no projeto nem vai para o servidor**. Em outro aparelho, o cache se refaz a partir do original. O cache no disco não é limpo automaticamente quando o clipe deixa de usá-lo.
- Enquanto o derivado não está pronto, o clipe toca o original (no tempo original). Exportar e congelar faixa esperam o warp acabar (`Processando o warp…`), então o que soa é o que exporta.
- Sem o áudio original neste aparelho, o warp não é gerado (aviso `O áudio original não está neste aparelho.`).

**O que o detector aceita** (`Detectar`; engine/src/stretch.rs)
- Procura o andamento entre **60 e 200 BPM** pela periodicidade dos ataques (onsets), com preferência suave por volta de 120 BPM. Analisa **no máximo os primeiros 90 s** do arquivo e usa o arquivo **inteiro**, não só o trecho que o clipe mostra.
- Exige **pelo menos 3 s** de áudio; menos que isso volta "sem andamento".
- Nos testes do motor com material rítmico sintético (bumbo, caixa e chimbal, 30 s), o resultado fica **exato (erro abaixo de 0,5 BPM) de 75 a 140 BPM**, com confiança acima de 80%. Em cliques regulares de 10 s, dentro de 1 BPM (confiança acima de 30%).
- **Nos extremos** (por volta de 65 BPM ou acima de 170) o detector pode devolver o valor certo, o **dobro** ou a **metade** (oitava): nunca outro valor. É para isso que existem `÷2` e `×2`.
- **Rejeita** o que não tem batida: silêncio, tom puro, ruído branco e pad de acordes dão "sem andamento" (aparece a mensagem `Não deu para achar o andamento…`). Também rejeita se não há ataques claros em quantidade (mínimo de 8 ataques, entre 0,3 e 12 por segundo) e se a periodicidade é fraca demais.
- A **confiança** (0 a 100%) é o quanto o pico de andamento se destaca do resto; abaixo de 35% o app avisa para conferir de ouvido.
- Música real, com andamento que varia (bateria humana, rubato), pode dar valores fora do esperado; confira de ouvido e corrija a mão (não confirmado além dos testes sintéticos).

**Outros**
- `Detectar` liga o warp assim que acha o andamento, sem esperar `Ajustar ao andamento`.
- Web e Android usam o mesmo código do motor; só muda onde ele roda.

## Atalhos

Este diálogo não tem atalhos próprios. Vale `Enter` dentro do campo `BPM do áudio` (equivale a `Ajustar ao andamento`).
