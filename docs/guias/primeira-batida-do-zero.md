# Primeira batida do zero

> Do projeto vazio a uma batida eletrônica de quatro compassos (bateria, baixo, pad e um retorno de reverb), tocando em loop a 124 BPM e exportada em WAV, em cerca de 10 minutos.

Tudo abaixo supõe compasso de 4 tempos. Os números de andamento, nível e efeito são pontos de partida musicais, não regras do programa: ajuste de ouvido. O que depende do programa (rótulos, faixas de valor, teclas) vem do código.

## Ingredientes

| Recurso | Para quê aqui | Capítulo |
|---|---|---|
| Tela `Projetos`, `Novo projeto`, modelo `Vazio` | Começar do zero | [01 Projetos, modelos e conta](../manual/01-projetos-modelos-conta.md) |
| Barra de transporte: `120 BPM · 4/4`, `Loop (L)`, `Metrônomo (C)` | Andamento, repetir os 4 compassos, contar o tempo enquanto programa | [02 Transporte](../manual/02-transporte.md) |
| `Faixa` (tooltip `Nova faixa`), duplo clique na raia | Criar as faixas e os clipes de notas | [02b Timeline e clipes](../manual/02b-timeline-e-clipes.md) |
| Bateria: kits, 12 peças, linhas do piano roll | Bumbo, caixa e chimbal | [04b Bateria](../manual/04b-bateria.md) |
| Sintetizador: presets `Baixo sub` e `Pad quente` | Baixo e pad | [04a Sintetizador](../manual/04a-sintetizador.md), [04 Painel de instrumento](../manual/04-painel-de-instrumento.md) |
| Editor de notas: Lápis, grade, `Ctrl+A`, `Ctrl+D`, setas | Escrever e repetir as notas | [05 Piano roll](../manual/05-piano-roll.md) |
| `Escala` e `Acorde no clique` | Os acordes do pad | [05b Ferramentas MIDI](../manual/05b-ferramentas-midi.md) |
| Mixer: fader, `Envio`, barramento; efeito `Reverb` | Níveis e o retorno de reverb | [06 Mixer](../manual/06-mixer.md), [06d Referência dos efeitos](../manual/06d-efeitos-referencia.md) |
| `Exportar` | Tirar o WAV | [08 Exportação](../manual/08-exportacao.md) |

Para ir além depois: [Melodia e harmonia com as ferramentas](melodia-e-harmonia-com-as-ferramentas.md) (acordes, arpejo, humanizar), [Mixagem e automação](mixagem-e-automacao.md) (níveis, retorno de reverb, fade) e [Loudness e master](loudness-e-master.md) (levar o master ao volume de streaming).

## Passo a passo

### 0. O atalho de um clique: o modelo `Batida eletrônica`

Antes de construir, vale ouvir o alvo. Em `Projetos`, `Novo projeto`, deixe marcado `Batida eletrônica` (é o padrão de `Começar com`) e toque em `Criar`. Espere o estúdio abrir e aperte `Espaço`. O modelo já traz, em 120 BPM e 4/4:

| Item | O que o modelo monta | Esta receita |
|---|---|---|
| Loop | Ligado, do compasso 1 ao 4 (16 batidas) | Você liga com `L` (a região 1 a 4 já vem marcada no `Vazio`, desligada) |
| `Bateria` | Kit `808`, clipe `Batida` com 88 notas: bumbo em todas as batidas, `Palmas` na 2ª e na 4ª, chimbal aberto no contratempo, chimbal fechado em 3 das 4 semicolcheias de cada batida | Kit `909`, 10 notas no compasso 1, copiadas 3 vezes; `Caixa` no lugar das `Palmas` |
| `Baixo` | `Sintetizador`, preset `Baixo sub`, fader em 0,8 (cerca de −1,9 dB), clipe com 16 notas: uma por contratempo, na raiz do acorde (`A2`, `F2`, `C3`, `G2`) | O mesmo preset, as mesmas notas e o mesmo fader |
| `Pad` | `Sintetizador`, preset `Pad quente`, fader em 0,55 (cerca de −5,2 dB), 12 notas: `Am`, `F`, `C`, `G`, um compasso cada | Os mesmos acordes, feitos com `Acorde no clique` |
| `Reverb` | `Barramento` com um `Reverb` (preset `Sala`, `Mistura` 100%); envios: `Bateria` 0,12 (cerca de −18,4 dB), `Pad` 0,45 (cerca de −6,9 dB), `Baixo` nenhum | O mesmo desenho, montado à mão |
| Metrônomo, contagem | Metrônomo desligado, contagem ligada | Igual |

O modelo é só um ponto de partida e não ensina nada que você não possa desmontar: abra o piano roll de cada faixa (`E`) e veja onde ficam as notas. Quando tiver visto, apague o projeto de teste (menu `Mais` do card, `Apagar`) e volte aqui para fazer o seu.

### 1. Projeto vazio e andamento

1. Em `Projetos`, toque em `Novo projeto`. No campo `Nome`, `Minha primeira batida`; em `Começar com`, `Vazio`; `Criar`. (Criar precisa de rede: o cadastro do projeto é no servidor.)
2. O estúdio abre com uma faixa `Áudio 1` vazia, que esta receita não usa. No cabeçalho dela, abra `Opções da faixa` (três pontos) e escolha `Apagar a faixa`: faixa vazia apaga direto, sem pergunta.
3. Toque no botão `120 BPM · 4/4`. Em `BPM`, digite `124`; deixe `Tempos por compasso` em `4/4`; `Salvar` (ou `Enter`). A janela aceita de 20 a 999 BPM, com decimais (`124,5`).
4. Ligue o loop com `L`. A região do compasso 1 ao 4 já vem marcada, só desligada. Ligue também o metrônomo (`C`) para programar no tempo; ele não vai para a exportação.

Um compasso a 124 BPM dura cerca de 1,9 s (4 batidas x 60 / 124); os 4 compassos do loop, cerca de 7,7 s.

### 2. Bateria: kit e um compasso

1. Toque em `Faixa` (fim da lista de faixas) e escolha `Bateria`. A faixa nasce selecionada, com o nome `Bateria 1`.
2. Aperte `I` para abrir a aba `Instrumento`. No seletor `Kits de bateria` (categoria `KITS`), escolha `909`: bumbo curto com clique, caixa com esteira, chimbais brilhantes. Para um som mais grave e longo, use `808`.
3. Dê dois cliques no vazio da raia da `Bateria 1`, no compasso 1 (dica na raia: `Clique duas vezes para criar um clipe de notas`). Nasce um clipe de 1 compasso e o editor abre. O Lápis e a grade `1/16` já são o padrão; as linhas têm o nome das peças (`Bumbo`, `Caixa`, `Chimbal fechado`...).
4. Escolha a grade `1/4` (botão da grade, tooltip `Grade do editor (Alt ao arrastar desliga)`). Com o Lápis, clique **logo depois** de cada linha de batida (o início da nota cai na linha anterior da grade, então não clique antes dela):
   - linha `Bumbo`: batidas 1, 2, 3 e 4;
   - linha `Caixa`: batidas 2 e 4.
5. Troque a grade para `1/8` e, na linha `Chimbal aberto`, clique depois de cada contratempo (1,5; 2,5; 3,5; 4,5, ou seja, o "e" de cada batida).
6. Confira o desenho: 10 notas no compasso.

| Linha | Batidas | Notas |
|---|---|---|
| `Bumbo` | 1, 2, 3, 4 | 4 |
| `Caixa` | 2, 4 | 2 |
| `Chimbal aberto` | 1,5; 2,5; 3,5; 4,5 | 4 |

7. Copie o compasso: `Ctrl+A` (o contador mostra `10 de 10 selecionadas`) e depois `Ctrl+D` três vezes. Cada `Ctrl+D` cola a cópia logo depois do trecho, em compasso inteiro, e o clipe cresce sozinho até caber. Ao fim, o contador mostra `10 de 40 selecionadas` e o clipe tem 4 compassos.
8. Aperte `Espaço`. Você ouve a bateria repetindo os 4 compassos. Enquanto o loop roda, ajuste no painel `Instrumento` (`I`): por exemplo, `Volume` do `Chimbal aberto` em 60% e o `Decaimento` do `Chimbal fechado` em ×0.40, para ele não brigar com o aberto.

As teclas de edição só agem nas notas enquanto o editor é o último lugar clicado; se `Ctrl+A` ou `Ctrl+D` fizerem outra coisa (duplicar o clipe inteiro, por exemplo), clique uma vez dentro do editor e repita.

### 3. Baixo: sintetizador com o preset `Baixo sub`

1. `Faixa` > `Sintetizador`. Aperte `I` e, em `Presets`, escolha `Baixo sub` (categoria `BAIXOS`): senoide com sub, mono, glide de 30 ms.
2. Dois cliques no vazio da raia do baixo, no compasso 1, para criar o clipe. No editor, escolha a grade `1/8` e `Nota: grade`.
3. Com o Lápis, clique na linha `A2` (nota MIDI 45, o nome aparece dentro da nota e no rótulo enquanto você arrasta) depois de cada contratempo: 0,5; 1,5; 2,5; 3,5. São 4 notas curtas, no compasso 1.
4. Agora as outras raízes, só com teclado, sem redesenhar:
   1. `Ctrl+A` e `Ctrl+D`: a cópia cai no compasso 2, já selecionada. Aperte `↓` 4 vezes (cada seta é um semitom): `A2` vira `F2`.
   2. `Ctrl+D` de novo (compasso 3) e `↑` 7 vezes: `F2` vira `C3`.
   3. `Ctrl+D` (compasso 4) e `↓` 5 vezes: `C3` vira `G2`.
5. O clipe agora tem 4 compassos e 16 notas: `A2`, `F2`, `C3`, `G2`, uma nota por contratempo, o mesmo desenho do modelo. O bumbo fica com as batidas; o baixo, com os contratempos.
6. No cabeçalho da faixa, dê duplo toque no nome e chame de `Baixo` (`Nome da faixa`, `Salvar`).

### 4. Pad: acordes com `Acorde no clique`

1. `Faixa` > `Sintetizador`, nome `Pad`, e em `Presets` escolha `Pad quente` (categoria `PADS`): serras em uníssono 3, ataque de 0,9 s, soltura de 1,8 s.
2. Dois cliques no vazio da raia, no compasso 1. No editor, puxe a bandeirinha do fim do clipe, na régua, até o fim do compasso 4 (notas depois do fim do clipe não tocam).
3. Clique em `Escala`: `Tônica` `A`, `Escala` `Menor natural`, chave `Prender na escala` ligada, `Aplicar`. O botão passa a mostrar `A menor natural`.
4. `Ferramentas` > `Escala e acordes` > `Acorde no clique`. No diálogo `Acorde`, `Tipo` `Diatônico: tríade`, `Inversão` `Fundamental`, `Usar no clique`.
5. Grade `1/4` e `Nota: 1/1` (4 tempos por clique). Com o Lápis, clique logo depois da linha de cada compasso:
   - compasso 1, linha `A3`: `Am` (A3 C4 E4);
   - compasso 2, linha `F3`: `F` (F3 A3 C4);
   - compasso 3, linha `C4`: `C` (C4 E4 G4);
   - compasso 4, linha `G3`: `G` (G3 B3 D4).
6. Desligue o carimbo: `Ferramentas` > `Escala e acordes` > `Acorde no clique: Diatônico: tríade` (um clique desmarca). Sem isso, todo clique novo também cria acorde.

O modelo usa `C/G` (G3 C4 E4) no terceiro compasso; aqui o `C` fica na fundamental. A diferença é só de voicing.

### 5. Níveis e o retorno de reverb

1. Aperte `X` para abrir o mixer. Leve os faders a estes pontos de partida (a leitura em dB fica embaixo do fader; duplo clique volta a 0 dB):

| Canal | Fader | O que o modelo usa |
|---|---|---|
| `Bateria 1` | 0 dB | 0 dB |
| `Baixo` | −1,9 dB | 0,8 |
| `Pad` | −5,2 dB | 0,55 |

2. No canal do `Pad`, toque na linha `Envio`. Nasce o `Barramento 1` no fim da lista, e o `Pad` já manda para ele em −6,0 dB, pós-fader (o modelo usa −6,9 dB; a diferença é pequena).
3. No cabeçalho do `Barramento 1`, dê duplo toque no nome e chame de `Reverb`.
4. No canal `Reverb`, toque em `Efeito` e escolha `Reverb` (família `Espaço`). No cartão, abra `Presets e mais` e escolha `Sala` (`Pré-atraso` 15 ms, `Tamanho` 50%, `Decaimento` 1,4 s). Depois do preset, ponha `Mistura` em **100%**: o retorno leva só o som molhado; o seco já vai das faixas ao master.
5. Na `Bateria 1`, toque no knob de envio do `Reverb` e arraste para baixo até cerca de −18 dB (o modelo usa −18,4). No `Baixo`, não mande nada: cauda de grave suja a mistura.
6. Ouça o loop. `M` no barramento `Reverb` liga e desliga o reverb inteiro, para comparar.
7. Olhe o canal `Master`: o pico deve ficar entre −12 e −6 dB. Se passar, baixe as faixas, não suba o master. O canal também mostra a leitura de loudness (`M`, `S`, `I` e `TP`, com o botão `Zerar`); `TP` fica vermelho quando o true peak passa de −1 dBTP. Para conferir o volume percebido, toque em `Zerar`, deixe a música passar do começo ao fim e leia o `I` (em [06 Mixer](../manual/06-mixer.md) e no guia [Loudness e master](loudness-e-master.md)).

### 6. Exportar

1. Pare (`Enter`). Toque em `Exportar` (tooltip `Exportar a música (e as faixas separadas) em WAV`).
2. Deixe `Música inteira`, `WAV 24 bits`, taxa `A do aparelho` e `Cauda` em 2 s. `Stems` e `Normalizar` desligados. O resumo da janela deve dizer `Compassos 1 a 4 · 0:08 + 2 s de cauda` (o tempo exato depende do andamento).
3. `Exportar`. Espere `Renderizando N%` e abra o arquivo `Minha primeira batida.wav` nos downloads (no Android, escolha onde salvar). Cerca de 10 s de áudio a 24 bits e 48 kHz dá uns 2,8 MB.
4. O arquivo sai linear: sem metrônomo e sem repetição do loop. Se quiser a batida mais longa, duplique os clipes (`Ctrl+D` no arranjo) antes de exportar.

## Variações

- **Groove de chimbal como o do modelo.** Na linha `Chimbal fechado`, grade `1/16`, clique a 1ª, a 2ª e a 4ª semicolcheia de cada batida (12 notas no compasso; o modelo põe a primeira mais forte, cerca de 70%, e as outras em 45%). Ligue a faixa de velocidade do editor (tooltip `Mostrar a faixa de velocidade e controles`) e arraste as bolinhas das notas fracas para baixo.
- **Kit e clima.** `808` para o graves longo do modelo; `Trap` (bumbo virando baixo) a 70 ou 140 BPM; `Lo-fi` mais escuro e curto. No baixo, `Baixo ácido (303)` ou `Reese`. No pad, `Pad estéreo` ou `Cordas`.
- **Mais de 4 compassos.** No arranjo, selecione cada clipe (clique) e aperte `Ctrl+D`. Cada cópia cai colada no fim da anterior, e o loop pode ser redesenhado arrastando na régua.
- **Volume percebido para streaming.** Na janela `Exportar áudio`, ligue `Normalizar o loudness`, escolha a ficha `Streaming −14,0` e deixe o teto de true peak em `−1,0 dBTP`. A janela do resultado diz o quanto a mixagem subiu ou desceu e onde ela mediu. Detalhes em [08 Exportação](../manual/08-exportacao.md) e no guia [Loudness e master](loudness-e-master.md). `(não confirmado em uso)`
- **Arquivo de backup do projeto.** Em `Exportar`, o botão `Projeto inteiro (.jopendaw)…` no pé da janela `Exportar áudio` (ou `Exportar projeto…` no menu `Mais` do card em `Projetos`) guarda faixas, clipes, mixagem e áudios num arquivo `.jopendaw`. Serve de plano B; não substitui o WAV. Veja [Backup e levar o projeto para outro aparelho](backup-e-levar-projeto-para-outro-aparelho.md).

## Por que funciona

- **Cada faixa tem o seu lugar no tempo e na frequência.** O bumbo ocupa as batidas, o baixo ocupa os contratempos (não se atropelam), o chimbal aberto preenche o "e" e o pad segura o acorde por trás. Trocar o baixo de contratempo para batida faria os dois disputarem o grave.
- **Copiar em vez de redesenhar.** `Ctrl+A` mais `Ctrl+D` repete o compasso; setas transpõem 1 semitom. Uma progressão de baixo sai em cinco teclas.
- **Retorno com `Mistura` 100%.** O reverb do barramento carrega só o molhado; a quantidade de cada faixa é decidida pelo envio dela. Assim o baixo fica seco e a bateria só ganha um toque de sala.
- **Folga no master.** Os canais podem passar de 0 dBFS por dentro sem distorcer, mas a soma no master passa por um limitador de segurança em −0,3 dBFS (sempre ligado). Pico entre −12 e −6 dB evita que ele trabalhe sem você notar.
- **Loop enquanto se mexe.** Com o loop ligado, cada ajuste de knob ou de nota é ouvido no contexto, sem parar e voltar.

## Se der errado

| Sintoma | Causa provável | Como resolver |
|---|---|---|
| Nada toca ao apertar `Espaço` | O navegador só libera o áudio depois do primeiro clique ou tecla | Clique uma vez em qualquer lugar do estúdio e aperte `Espaço` de novo |
| A bateria toca só o primeiro compasso | O clipe tem 1 compasso (o duplo clique cria 1 compasso) | Repita `Ctrl+A` e `Ctrl+D` no editor, ou puxe o fim do clipe |
| As notas do baixo ou do pad aparecem escurecidas | Estão depois do fim do clipe e não tocam | Puxe a bandeirinha do fim do clipe na régua do editor |
| `Ctrl+D` duplicou o clipe em vez das notas | O editor não era o último lugar clicado | Clique dentro do editor e repita (o contador de notas confirma) |
| Uma nota da bateria não soa | A nota está numa altura sem peça (a linha aparece como `sem peça`) | Arraste a nota para a linha da peça (`Bumbo`, `Caixa`, `Chimbal aberto`) |
| O baixo some no reverb ou na caixa pequena | Envio para o retorno, ou preset sem o sub | Tire o envio do baixo; confira `Sub` do `Baixo sub` (45%) |
| O reverb "lava" a mistura | Envios altos, cauda longa | Baixe os envios, `Decaimento` 1,0 s, `Cortar graves` 200 Hz |
| O medidor do `Master` vive no topo | O limitador de segurança está segurando o som | Baixe os faders até o pico ficar entre −12 e −6 dB |
| `O projeto ainda não tem clipes.` na janela `Exportar áudio` | Nenhum clipe com notas | Crie o clipe de bateria antes de exportar |
| O WAV exportado tem silêncio no fim | É a `Cauda` (2 s): serve para o reverb terminar | Reduza a `Cauda` a 0 s se não quiser |
