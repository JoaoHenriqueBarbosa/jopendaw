# Gravar uma banda e mixar

> Voz, violão, baixo e bateria gravados por cima uns dos outros no modelo `Gravação de banda`, com contagem, tomadas em loop, monitor, mixagem (níveis, pan, reverb em barramento, compressor no vocal) e stems exportados; cerca de 1 hora para uma música curta, sem contar os ensaios.

Tudo abaixo supõe compasso de 4 tempos. Números de nível e de efeito são pontos de partida musicais; ajuste de ouvido. O que depende do programa (rótulos, teclas, faixas de valor) vem do código.

## Ingredientes

| Recurso | Para quê aqui | Capítulo |
|---|---|---|
| Modelo `Gravação de banda` | Cinco faixas prontas (`Voz`, `Violão`, `Baixo`, `Bateria`, `Reverb`), metrônomo e contagem ligados | [01 Projetos, modelos e conta](../manual/01-projetos-modelos-conta.md) |
| Janela `Configurações` (entrada, `Nível`, `Compensação de latência`, `Contagem de um compasso`) | Microfone, nível e calibragem | [09 Configurações, atalhos e Android](../manual/09-configuracoes-atalhos-android.md), [02 Transporte](../manual/02-transporte.md) |
| Armar (`Armar para gravar`), `Monitorar a entrada`, `R`, loop, tomadas | Gravar em camadas, ouvir o que grava, escolher a melhor passada | [03c Gravação](../manual/03c-gravacao.md) |
| Clipe de áudio: cortar (`S`), fades, menu `Tomadas` | Arrumar o que foi gravado | [03 Áudio e clipes](../manual/03-audio-e-clipes.md), [02b Timeline e clipes](../manual/02b-timeline-e-clipes.md) |
| Bateria (kit `Acústico eletrônico`, teclado do computador) | Bateria tocada nas teclas, camada por camada | [04b Bateria](../manual/04b-bateria.md), [05 Piano roll](../manual/05-piano-roll.md) |
| Mixer: fader, pan, `Envio`, barramento `Reverb` | Níveis, posição e espaço | [06 Mixer](../manual/06-mixer.md) |
| Efeitos `Compressor`, `EQ`, `Gate`, `Reverb` | Cadeia da voz e do baixo | [06c Painel de efeitos](../manual/06c-painel-de-efeitos.md), [06d Referência dos efeitos](../manual/06d-efeitos-referencia.md) |
| `Exportar` com `Stems` | Um WAV por faixa | [08 Exportação](../manual/08-exportacao.md) |

Receitas para consultar no meio do caminho: a cadeia vocal completa em [Efeitos em combinação](efeitos-em-combinacao.md) (receita 1) e a ordem de uma mixagem em [Mixagem e automação](mixagem-e-automacao.md).

## Passo a passo

### 1. O projeto e o andamento (antes de gravar)

1. Em `Projetos`, `Novo projeto`, `Nome` `Ensaio da banda`, `Começar com` `Gravação de banda`, `Criar`. O estúdio abre com o metrônomo ligado, a contagem ligada, o loop desligado (com a região do compasso 1 ao 4 já marcada) e cinco faixas, nenhuma armada:

| Faixa | Tipo | Envio para o `Reverb` |
|---|---|---|
| `Voz` | `Áudio` | 0,3 (cerca de −10,5 dB) |
| `Violão` | `Áudio` | 0,2 (cerca de −14,0 dB) |
| `Baixo` | `Áudio` | sem envio (o baixo vai só para o master, seco) |
| `Bateria` | `Bateria`, kit `Acústico eletrônico`, sem nenhuma nota | 0,1 (−20 dB) |
| `Reverb` | `Barramento`, efeito `Reverb`, preset `Placa`, `Mistura` 100% | |

2. Ajuste o andamento **agora**: toque em `120 BPM · 4/4`, digite `92` em `BPM`, `Salvar`. Depois de gravar, mudar o andamento desalinha o áudio: um clipe de áudio sem warp mantém a duração em segundos, então o fim dele anda em batidas, enquanto as notas MIDI acompanham. (O botão fica desligado durante a gravação.)

### 2. O microfone: permissão, entrada e nível

1. Abra a janela `Configurações` (engrenagem da barra, tooltip `Configurações: entrada de áudio, latência e contagem`). No navegador, é aqui que aparece o pedido de permissão do microfone; aceite. O navegador precisa estar em `https` (ou `localhost`). No Android, o pedido é do sistema (`RECORD_AUDIO`) e vem na primeira vez que o app abre o microfone.
2. Em `ENTRADA DE ÁUDIO`, escolha o microfone ou a interface. Se acabou de conectar, toque no botão de atualizar (tooltip `Procurar as entradas de novo (depois de conectar um microfone ou interface)`). A escolha fica no aparelho, não no projeto.
3. Arme a faixa `Voz` (o ponto vermelho `Armar para gravar`, no cabeçalho ou no canal do mixer) para a entrada abrir. A barra `Nível` da janela (e a barra fina do cabeçalho da faixa) começa a se mexer.
4. Cante ou toque no volume mais forte da música. O pico deve ficar no verde ou no âmbar (a escala vai de −48 a 0 dB; o verde vai até cerca de −14 dB e o âmbar até cerca de −6 dB), sem acender a luz vermelha do topo, que fica acesa por 2 s quando o pico chega a −0,1 dBFS (cortou no conversor). Abaixe o ganho na própria interface ou no sistema.
5. Feche em `Fechar`.

Se o navegador negar: `O navegador negou o acesso ao microfone. Libere o microfone nas permissões do site e tente de novo.` A faixa volta a ficar desarmada. Libere no cadeado ao lado do endereço. No Android negado de vez, o caminho é Configurações, Apps, jopendaw, Permissões.

### 3. Calibrar a latência (uma vez por aparelho)

O app já desconta sozinho do começo do áudio a latência que o navegador informa (`baseLatency` mais `outputLatency`) e a da entrada; a `Compensação de latência` é um ajuste manual por cima disso, de −200 a 500 ms.

1. Deixe o metrônomo ligado (`C`; o modelo já o liga) e arme uma faixa de áudio. Ponha o microfone perto do alto-falante (ou use um cabo de retorno); nada de fones nesta medida.
2. Grave 4 compassos só com o clique (`R`, contagem, `R`).
3. Aproxime a régua (`+`) e veja onde o clique gravado caiu em relação às linhas de compasso e de batida. Se ele chega depois da linha, a compensação deve ser positiva (adianta o gravado); se chega antes, negativa.
4. Em `Configurações`, mova o controle `Compensação de latência` (campo com `ms`), de 10 em 10 ms para começar, apague o clipe de teste (selecione e `Delete`) e grave de novo. Repita até o clique cair na grade.
5. O valor fica no projeto (não entra no desfazer). Ao receber uma versão do projeto pela nuvem, cada aparelho mantém a sua compensação: calibre no computador e no celular separadamente.

### 4. Bateria tocada nas teclas, camada por camada (overdub MIDI)

A faixa `Bateria` do modelo vem sem notas. Toque-as você mesmo, em camadas, usando o loop:

1. Desarme a `Voz` (toque no ponto de novo) e arme a `Bateria` (tooltip `Armar para gravar as notas (teclado ou MIDI)`).
2. Marque o loop **antes** de ligar o teclado (com o teclado ligado, `L` vira nota): o modelo já traz a região de 4 compassos, só ligue-a com `L`, e ponha o cursor no começo com `Enter`.
3. Ligue o teclado do computador (`Ctrl+K`; o botão mostra `C4`). Aperte `Z` duas vezes: o botão mostra `C2`, onde ficam as peças. Com a oitava em C2: `A` toca o `Bumbo`, `S` a `Caixa`, `T` o `Chimbal fechado`, `U` o `Chimbal aberto`, `E` as `Palmas`.
4. `R`. O botão pisca por um compasso de contagem (o metrônomo conta) e a gravação começa. **Passada 1:** bumbo (`A`) nas batidas 1 e 3, caixa (`S`) nas 2 e 4. **Passada 2:** chimbal fechado (`T`) em toda colcheia; entre uma passada e outra, aperte `C` três vezes para baixar a intensidade das teclas de 80% para 50% (`C` e `V` mexem em passos de 10%, entre 10% e 100%). Em loop, as notas de todas as passadas caem no **mesmo** clipe (não há tomadas de MIDI) e se somam.
5. Pare com `R`. Nasce um clipe de bateria que cobre compassos inteiros (aqui, os 4 do loop). Confira no editor (`E`, com o clipe selecionado).
6. Ajuste o tempo do que foi tocado ao vivo: clique dentro do editor, `Ctrl+A` e `Q` (quantiza na grade do editor, `1/16` por padrão, com `Força` 100%). Um passo só de `Ctrl+Z` desfaz.
7. Para dar outra camada depois (um prato, um tom), volte o cursor para dentro do mesmo clipe e grave de novo: as notas novas somam às antigas.
   Nota: pelo código atual, o app grava também o pitch bend, a roda de modulação e o pedal de sustain tocados junto (com um controlador MIDI ou com as rodas do teclado da tela), e eles aparecem na faixa de controle do editor; a `Bateria` ignora os três, então nada disso muda o som aqui. Para um baixo ou um teclado sintetizado, veja [05 Piano roll](../manual/05-piano-roll.md#faixa-de-controle). `(não confirmado em uso)`
8. Desligue o teclado (`Ctrl+K`) e desarme a `Bateria`. Com o teclado ligado, `S`, `E`, `F`, `L`, `C`, `X` e `Z` são notas e não atalhos.
9. Estenda a bateria até o tamanho da música: selecione o clipe (clique nele no arranjo) e aperte `Ctrl+D` quantas vezes precisar; cada cópia cai colada no fim da anterior (3 cópias dão 16 compassos no total). É o guia de tempo para o que vem a seguir.

### 5. Violão e baixo: uma tomada com contagem

1. Desligue o metrônomo com `C` (a contagem de entrada continua tocando, porque `Contagem de um compasso` é uma opção à parte: `O metrônomo conta um compasso antes de a gravação começar`). Assim o clique não vaza para o microfone durante a música. Use fones.
2. Arme o `Violão` (uma faixa de áudio de cada vez: se duas estiverem armadas, cada uma recebe um clipe com o mesmo áudio, porque a entrada é uma só).
3. Ponha o cursor no compasso 1 (`Enter`) e desligue o loop (`L`). Aperte `R`: contagem de um compasso, bateria tocando, e você grava. Pare com `R`, `Espaço` ou `Enter`. Aparece `Salvando a gravação…` e nasce um clipe `Gravação N.wav` (o N é o próximo livre do projeto); o cursor volta ao ponto em que você começou.
4. Ouça. O que foi gravado é a entrada crua: os efeitos da faixa entram só no que você ouve, não no arquivo. Depois você pode trocar o `Compressor` e o `EQ` à vontade.
5. Repita para o `Baixo`: desarme o `Violão`, arme o `Baixo`, `Enter`, `R`.
6. Errou um trecho? Grave por cima: ponha o cursor onde quer começar e grave de novo; a gravação nova **substitui** o trecho e apara, parte ou remove o que estava embaixo. Depois de parar, `Ctrl+Z` deve trazer o trecho de volta. `(não confirmado)`

### 6. Voz: monitor e tomadas em loop

1. No canal da `Voz` no mixer (`X`), ligue `Monitorar a entrada` (o botão de fones, azul; tooltip `Monitorar a entrada: ouvir o microfone ao vivo pelos efeitos e pelo fader desta faixa (use fones, senão microfona)`). Com ele você se ouve pela cadeia da faixa e pelo fader, mesmo com o transporte parado; pelo caminho do sinal do mixer, o envio de reverb da faixa também carrega essa entrada. `(não confirmado em uso)` Só funciona em faixa de áudio; use fones.
2. Marque o loop no verso que vai cantar: arraste na régua de um compasso ao outro (por exemplo, do compasso 5 ao 9, 4 compassos): arrastar já liga o loop, então não aperte `L` depois. Ponha o cursor no **começo** do loop (clique na régua, ou `[` e `]` se você marcou o ponto com `M`). Uma gravação que começa no meio do loop deixa a primeira tomada com silêncio na frente.
3. Arme a `Voz` e aperte `R`. Depois da contagem, cante; a cada volta do loop o retângulo vermelho na raia passa de `Gravando` para `Tomada 2`, `Tomada 3`... Cante 3 a 5 passadas.
4. Pare com `R`. Nasce **um clipe** cobrindo o loop, com o selo `N tomadas` (por exemplo, `4 tomadas`). A tomada ativa é a última passada completa (uma passada só conta como completa se cobre pelo menos 98% do loop e não começou no meio); uma última passada com menos de uma batida é descartada.

### 7. Escolher a tomada

1. Toque o selo `N tomadas` no clipe (tooltip `Tomada X de N: escolher outra`) ou abra o menu do clipe (botão direito, toque longo no celular) e escolha `Tomadas`. A lista `TOMADAS` mostra `Tomada 1`, `Tomada 2`... com um visto na ativa.
2. Escolha outra tomada. Posição, corte e fades do clipe ficam; só o áudio troca. É um passo do desfazer.
3. Com o loop ligado (o botão `Loop (L)` aceso), aperte `Espaço` e compare as tomadas ouvindo a voz com a bateria e o violão.
4. Para ficar com uma frase de cada tomada, corte o clipe nos limites das frases (cursor no ponto, `S`) e escolha a tomada de cada pedaço: o corte copia as tomadas para os dois lados e a troca só muda o áudio. `(não confirmado em uso)`

### 8. Mixar

Siga a ordem de [Mixagem e automação](mixagem-e-automacao.md): níveis, pan, envios, master. Aqui, com os valores deste projeto:

1. **Loop e nível.** Marque um loop de 8 compassos no trecho mais cheio (arrastando na régua, o que já liga o loop). Abra o mixer (`X`). Duplo clique em cada fader para voltar a 0 dB. Leve `Bateria` e `Baixo` a um pico de −12 a −10 dB, some o `Violão` e por último a `Voz`, que fica um pouco acima do resto. Os faders costumam acabar entre −6 e −20 dB.
2. **Pan.** `Voz`, `Baixo` e `Bateria` em `C` (a bateria já espalha as peças no estéreo). `Violão` em `E35` (knob de pan, arrastando na vertical); se você gravar uma segunda camada de violão em outra faixa, ponha-a em `D35`.
3. **Reverb em barramento.** O `Reverb` já está pronto (`Placa`, `Mistura` 100%). Abra o rack dele (`F` com o `Reverb` selecionado) e ponha `Pré-atraso` em 20 ms (deixa a voz na frente). Os envios do modelo servem de partida (`Voz` −10,5 dB, `Violão` −14 dB, `Bateria` −20 dB); ajuste arrastando o knob de envio do `Reverb` em cada canal (`Shift` deixa fino). O `Baixo` já vem sem envio: deixe assim, para o reverb não empastar os graves. `M` no barramento liga e desliga o reverb inteiro, para comparar.
4. **Compressor no vocal.** Selecione a `Voz`, aperte `F` e adicione, nesta ordem, `EQ` (preset `Voz presente`) e `Compressor` (preset `Voz`: `Limiar` −20 dB, `Razão` 3,5:1, `Ataque` 5 ms, `Soltura` 80 ms, `Joelho` 6 dB, `Ganho` +4 dB, `Detector` `RMS`, `Passa-alta` 80 Hz). Arraste o `Limiar` no gráfico até o medidor de redução marcar de −3 a −6 dB nas frases mais fortes. Se a sala tinha ruído, ponha o `Gate` (preset `Ruído de fundo`) antes de todos.
5. **Baixo e violão.** No `Baixo`, um `Compressor` com o preset `Baixo` (`Limiar` −22 dB, `Razão` 5:1, `Ataque` 3 ms, `Soltura` 120 ms, `Ganho` +5 dB). No `Violão`, um `EQ` com o preset `Corte de graves` e a `Frequência` da banda 1 subida a 100 Hz, para abrir espaço para o baixo.
6. **Master.** Deixe o fader do `Master` em 0 dB. O pico do canal deve ficar entre −12 e −6 dB; se passar, baixe as faixas mais altas, não suba o master. Se o medidor vive grudado no topo, o limitador de segurança (−0,3 dBFS, sempre ligado) está segurando o som e achatando a mistura.
7. Confira exportando um WAV (passo seguinte) e ouvindo fora do programa.

### 9. Exportar a mixagem e os stems

1. Pare a gravação e o transporte. Toque em `Exportar`.
2. `INTERVALO` `Música inteira`, `FORMATO` `WAV 32 bits float` (sem perda, para levar a outro programa), `TAXA DE AMOSTRAGEM` `A do aparelho`, `Stems` **ligado**, `Normalizar` **desligado** (ele normaliza cada arquivo separado e muda o equilíbrio entre os stems), `Cauda` em 4 a 6 s (o reverb precisa de tempo para terminar; vale também para os stems).
3. `Exportar`. Espere o `Renderizando N%`. Saem, como downloads (no Android, uma janela `Salvar <nome>` por arquivo):
   - `Ensaio da banda.wav`: a mixagem, com a cadeia do master e o limitador;
   - `Ensaio da banda - Voz.wav`, `... - Violão.wav`, `... - Baixo.wav`, `... - Bateria.wav`, `... - Reverb.wav`: um por faixa que soa.
4. Cada stem é a saída da faixa depois do fader, do pan e do mudo, **com** os efeitos da faixa e **sem** a cadeia do master nem o limitador. A `Voz` sai seca, sem o reverb; o reverb dela está no stem `Reverb`, que é o barramento com o que recebeu. A soma dos stems não é igual à mixagem. Faixa vazia ou muda não gera arquivo.

## Variações

- **Sem contagem de um compasso.** Desmarque `Contagem de um compasso` (menu da seta ao lado do gravar, ou em `Configurações`). Sem contagem, gravar com o transporte já tocando (`Espaço`, depois `R` no ponto) entra "de surpresa": a posição vem do primeiro bloco de áudio capturado.
- **Baixo sintetizado no lugar do baixo tocado.** Crie uma faixa `Sintetizador`, preset `Baixo sub` (mono, glide de 30 ms), arme, `Ctrl+K` e toque nas teclas (oitava em `C2` ou `C3` com `Z`); as notas gravadas se editam no piano roll. Veja [Primeira batida do zero](primeira-batida-do-zero.md) para o baixo em duas oitavas graves.
- **Stems para outro programa com volume percebido igual.** Na janela `Exportar áudio`, `Normalizar o loudness` (ficha `Streaming −14,0`, teto `−1,0 dBTP`) e `Stems com o mesmo ganho`: a mixagem vai ao alvo e os stems levam o mesmo ganho, mantendo o equilíbrio (ele só aparece com `Stems` ligado; sem ele, os stems saem como renderizados). Ver [08 Exportação](../manual/08-exportacao.md) e o guia [Loudness e master](loudness-e-master.md). `(não confirmado em uso)`
- **Ducking do reverb pela voz.** Um `Compressor` depois do `Reverb` no barramento, com `Sidechain` na `Voz`: receita em [Mixagem e automação](mixagem-e-automacao.md#2-criar-um-barramento-de-reverb-compartilhado).
- **Só ouvir a voz com o reverb.** `S` na `Voz` deixa soar só ela e o reverb dela (o retorno é alimentado apenas por quem está em solo).

## Por que funciona

- **Camadas, com a bateria de guia.** Bateria tocada nas teclas e quantizada dá um relógio firme para o resto; o violão e a voz gravados por cima ficam colados nele. Como a gravação é a entrada crua, nenhuma decisão de som (compressor, EQ, reverb) é definitiva: dá para refazer a mixagem depois.
- **Andamento antes de gravar.** As notas MIDI acompanham o andamento; o áudio gravado não. Por isso o andamento se fecha antes da primeira tomada.
- **Tomadas no loop.** Cada volta é um arquivo de áudio guardado no clipe; trocar de tomada só troca o arquivo (com o mesmo corte e os mesmos fades), então escolher é barato e desfazível.
- **Latência compensada uma vez.** O app soma o que o navegador informa e o ajuste manual; calibrado, o áudio novo cai na grade e o cortar/mover dos clipes fica exato.
- **Reverb num só barramento.** Um `Reverb` com `Mistura` 100% dá o mesmo espaço para todos; a quantidade de cada faixa é o envio. O baixo, sem envio, fica firme.
- **Stems depois do fader.** Você leva para outro programa o que cada faixa soava, com o nível da sua mixagem, e pode refazer o master lá.

## Se der errado

| Sintoma | Causa provável | Como resolver |
|---|---|---|
| A barra `Nível` não se mexe | Nenhuma faixa de áudio armada (nem monitorando), ou a entrada errada | Arme a faixa de áudio; em `Configurações` escolha a entrada e toque no botão de atualizar |
| `A entrada não mandou áudio durante a gravação: confira o microfone e a entrada escolhida.` | A entrada ficou muda | Confira o cabo, a entrada escolhida e o ganho na interface |
| `Arme uma faixa para gravar (o botão de gravação dela)...` | Nenhuma faixa armada | Arme a faixa (nenhuma vem armada no modelo) |
| `Nenhuma nota foi tocada na faixa armada durante a gravação.` | A `Bateria` estava armada e você não tocou | Toque, ou desarme a faixa antes de gravar as de áudio |
| O clipe gravado cai atrasado em relação à grade | Falta a compensação de latência | Passo 3: positiva quando o áudio chega depois da linha |
| Eco ou microfonia | O microfone capta o alto-falante (monitor ou clique do metrônomo) | Fones; desligue o metrônomo (`C`) depois da contagem |
| As notas do teclado do computador não tocam a bateria | A oitava do teclado está em `C4`, fora do mapa da bateria | `Z` duas vezes até o botão mostrar `C2` |
| As teclas `S`, `E`, `L`, `C` e `X` não fazem o que se espera | O teclado do computador está ligado (viram notas e oitava) | `Ctrl+K` desliga |
| Duas faixas de áudio receberam o mesmo clipe | As duas estavam armadas | Desarme uma; apague o clipe sobrando (`Delete`) |
| A primeira tomada tem silêncio na frente | A gravação começou no meio do loop | Ponha o cursor no começo do loop antes de gravar |
| A tomada ativa não é a que você queria | A ativa é a última passada completa | Passo 7: escolha outra na lista `TOMADAS` |
| Não deu para desfazer, mudar o andamento ou marcar o loop | Estão travados durante a gravação | Pare a gravação primeiro (`Pare a gravação para <ação>.`) |
| `A entrada de áudio "<nome>" foi desconectada.` | Cabo, interface desligada ou permissão revogada | Reconecte; a gravação em andamento segue com silêncio no lugar até você parar |
| O WAV da mixagem tem o pico em −0,3 dBFS e mais nada | É o limitador de segurança do master | É o esperado; para mais folga, baixe as faixas |
| Falta um stem | Faixa vazia, muda ou calada por solo de outra | Confira `M`/`S`; faixa que não soa no trecho é pulada |
