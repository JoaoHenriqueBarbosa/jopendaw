# Controlador MIDI e MIDI learn

> Três montagens para mixar e tocar com as mãos num controlador: knobs comandando o mixer, um pedal de expressão abrindo um filtro e os faders de um pad controller gravando automação em `Toque`. Cada uma leva uns 5 minutos, com o controlador já ligado.

Os valores vêm do código (curvas, faixas e padrões dos controles) e do modelo `Batida eletrônica`. Nenhuma das receitas foi conferida com um controlador de verdade nem de ouvido `(testado só por testes automáticos; não confirmado ao ouvido)`. O mais próximo de uso real foi visto no Chrome com mensagens MIDI injetadas: aprender o `CC 21` no fader do `Pad` e vê-lo ir a −24,1 dB com o `CC 40`. Os números em dB e Hz das receitas são contas das fórmulas do app: use-os como ponto de partida.

## Ingredientes

- [MIDI learn](../manual/06f-midi-learn.md): o modo `Aprender MIDI` (botão da barra ou `Shift+K`), a janela `Mapeamentos MIDI` (curva, `Invertido`, `Mín`/`Máx`, `Suave`) e o padrão para novos projetos.
- [Gravação, Teclado do computador e MIDI](../manual/03c-gravacao.md#teclado-do-computador-e-midi): ligar a entrada (ícone de cabo) e o que o app faz com o `CC 1`, o pedal e o bend quando **não** há mapeamento.
- [Mixer](../manual/06-mixer.md): fader, pan, envios e o `Master`, que são os alvos da receita 1.
- [Painel de efeitos](../manual/06c-painel-de-efeitos.md) e [referência dos efeitos](../manual/06d-efeitos-referencia.md): o efeito `Filtro` (`Corte` de 20 Hz a 20 kHz, padrão 1000 Hz) da receita 2.
- [Automação](../manual/07-automacao.md#gravar-automação): os modos `Ler`, `Escrever`, `Toque` e `Trava` da receita 3.
- [Mixagem e automação, passo 5](mixagem-e-automacao.md#5-gravar-um-fade-e-uma-varredura-de-filtro-com-o-mouse): a mesma gravação de automação, com o mouse.
- [Expressão MIDI na prática](expressao-midi-na-pratica.md): o que fazer com o bend, a roda e o pedal quando o que se quer é **tocar** e gravar expressão no clipe (o oposto do mapeamento).

Quatro coisas para saber antes:

1. **A entrada MIDI tem de estar ligada.** Ícone de cabo da barra (o número ao lado é a quantidade de aparelhos). O botão `Aprender MIDI` só aparece na barra depois disso; `Shift+K` liga o modo e o MIDI de uma vez.
2. **No modo, os controles só respondem a clique.** Arrastar, roda e duplo clique voltam quando você sai (`Esc`, `Sair` ou `Shift+K`).
3. **A origem é canal + controle** (`Canal 1 · CC 21`), não o aparelho. Dois controladores mandando o mesmo CC no mesmo canal se misturam.
4. **`Suave` está ligado por padrão.** O controle na tela não salta: só passa a seguir o botão quando o botão cruza o valor que ele já tem, o que ele mostra na tela (ou chega a 2% do curso dele). Parece "não pegou" no primeiro giro: gire até o valor atual e ele assume.

## Passo a passo

### Receita 1: um controlador com knobs para o mixer

Resultado: oito knobs (`CC 21` a `CC 28`, os padrões de muitos controladores) comandando o volume das quatro faixas do modelo, o envio de reverb do `Pad`, o pan do `Pad` e o volume do `Master`.

1. Crie um projeto com o modelo `Batida eletrônica` (faixas `Bateria`, `Baixo`, `Pad` e o barramento `Reverb`). Ligue a entrada MIDI (ícone de cabo) e abra o mixer (`X`).
2. Ligue o modo: botão `Aprender MIDI` da barra ou `Shift+K`. Faders, pans e envios ganham contorno âmbar.
3. Clique no fader da `Bateria`. A faixa diz `Mexa no controle do seu teclado que vai comandar "Volume"… (Esc cancela)`. Gire o knob 1 do controlador: `Aprendido: Canal 1 · CC 21 → Bateria · Volume`.
4. Repita, em ordem: fader do `Baixo` (knob 2), fader do `Pad` (3), fader do `Reverb` (4); a linha de envio `Reverb` do canal `Pad` (5, o alvo se chama `Envio → Reverb`); o knob de pan do `Pad` (6); o fader do `Master` (7). Cada clique arma um controle, o giro seguinte o mapeia.
5. Abra `Mapeamentos MIDI` (botão `Mapeamentos (7)` da faixa) e ajuste os faders de volume: curva `Logarítmica` e, com a ponta direita do seletor de faixa, `Máx` em **79%** (o 0 dB do fader fica a 79,4% do curso). Com isso o knob todo no máximo dá 0 dB e nunca +6 dB; no meio do giro (`CC 64`) o fader está em cerca de −7,9 dB, e a −29 dB no `CC 16`, em vez de −48 dB.
6. Saia do modo (`Esc`). Gire os knobs: cada fader do mixer fica parado até o knob cruzar a posição dele e depois acompanha. Exemplo: o `Pad` do modelo está em ganho 0,55 (−5,2 dB), 65% do curso; com curva `Linear` e sem `Máx` o knob só assume perto do `CC 83`.
7. Se quiser o mesmo ao criar projetos novos, `Salvar como padrão para novos projetos` na janela: leva os volumes, o pan e o `Master` (as faixas pela posição); **não** leva o envio de reverb. Um mapeamento de knob de instrumento leva junto o tipo da faixa e só vale numa faixa do mesmo tipo do projeto novo.

Variações:

- **Só pan e envio no controlador, volume no mouse:** mapeie só esses controles. Fora do modo o mouse volta a funcionar em tudo.
- **Trocar o knob de um controle:** no modo, clique no controle e gire o knob novo; o mapeamento antigo é substituído (e a curva, o `Invertido` e a faixa `Mín`/`Máx` voltam ao padrão: ajuste de novo).
- **Um knob para dois controles:** dá para mapear o mesmo `CC` a controles diferentes (o volume de uma faixa e o pan de outra, por exemplo); cada um leva a sua curva e faixa.

### Receita 2: um pedal de expressão abrindo um filtro

Resultado: o pedal (`CC 11`, `CC 4` ou o que o seu manda: o app mostra o número quando você aprende) varre o `Corte` de um efeito `Filtro` do `Pad`, de uns 110 Hz a uns 7 kHz.

1. Selecione a faixa `Pad`, abra o painel de efeitos (`F`) e adicione o efeito `Filtro` (família `Timbre`). Ele nasce em `Passa-baixa 24`, `Corte` 1000 Hz, `Ressonância` 20%.
2. Com o pedal no calcanhar (valor 0), ligue o modo (`Shift+K`) e clique no knob `Corte` do `Filtro`. A faixa mostra `Mexa no controle do seu teclado que vai comandar "Filtro · Corte"… (Esc cancela)`. Pise no pedal: `Aprendido: Canal 1 · CC 11 → Pad · Filtro · Corte`.
3. Abra `Mapeamentos MIDI` e, na linha do `Corte`, arraste as pontas do seletor para `Mín 25%` e `Máx 85%`. Como o `Corte` é logarítmico, `Linear` na curva já reparte as oitavas parelho pelo curso do pedal: com esses limites o pedal vai de 112 Hz (calcanhar) a 7,1 kHz (ponta), passando por cerca de 900 Hz no meio do curso.
4. Se o seu pedal manda o contrário (abre com o calcanhar), ligue `Invertido` na mesma linha.
5. Saia do modo, toque o `Pad` (`Espaço`) e mexa o pedal. O `Corte` fica onde estava (1000 Hz, 57% do curso do knob) até o pedal chegar perto desse valor (cerca de 53% do curso do pedal, `CC 67`, com esses limites); dali em diante acompanha, e o knob na tela gira junto.
6. Para o pedal mandar também um brilho a mais, mapeie a `Ressonância` do mesmo `Filtro` ao mesmo `CC` com curva `Linear` e `Mín` 10%, `Máx` 40%: o mesmo pedal comanda os dois controles.

Variações:

- **Pedal no filtro do próprio instrumento:** no painel `I`, o `Corte` do sintetizador (20 Hz a 20 kHz, padrão 2400 Hz) se mapeia do mesmo jeito; o mapeamento fica com o instrumento e não some ao mexer nos efeitos.
- **Abrir o filtro mais cedo no curso do pedal:** curva `Logarítmica` (o meio do curso do pedal, `CC 64`, já chega a 74% do curso do knob, cerca de 3,4 kHz no `Corte` de 20 Hz a 20 kHz sem `Mín`/`Máx`).
- **Pedal de sustain ou modulação como mapeamento:** se mapear o `CC 64` ou o `CC 1` (o pedal e a roda de modulação de sempre), eles **deixam de ser sustain e vibrato** naquele canal, e não são gravados nos clipes ([03c](../manual/03c-gravacao.md)).

### Receita 3: faders do pad controller gravando automação em Toque

Resultado: dois faders de um pad controller (`CC 41` e `CC 42`) gravam, com a música tocando, uma passada de volume do `Pad` e outra de `Corte`, e devolvem o controle à curva antiga quando você para de mexer. Complementa o [passo 5 de mixagem e automação](mixagem-e-automacao.md#5-gravar-um-fade-e-uma-varredura-de-filtro-com-o-mouse), que faz o mesmo com o mouse.

1. No modelo `Batida eletrônica`, mapeie o fader do `Pad` no mixer ao `CC 41` e o `Corte` do `Filtro` (efeito da receita 2) ao `CC 42`, como nas receitas anteriores (mapear de novo o fader do `Pad` substitui o `CC 23` da receita 1 e o mapeamento novo nasce com curva `Linear` e `Mín`/`Máx` em 0% e 100%, que é o que os números abaixo supõem). Deixe `Suave` **ligado** na janela `Mapeamentos MIDI`: para gravar, ele é útil, porque o trecho só começa a valer quando o fader físico passa pelo valor do controle (sem salto no primeiro ponto).
2. Saia do modo (`Esc`). No botão `Automação` da barra, escolha `Toque` (`Grava só enquanto você segura o controle; ao soltar, volta ao valor automatizado.`).
3. Ligue o loop nos quatro compassos (`L`) e aperte `Espaço`. **Não** aperte `R`: com a gravação de áudio ou MIDI ligada, a automação não grava e a barra avisa `A automação não grava junto com a gravação de áudio ou MIDI.`
4. Suba e desça o fader do `CC 41`. Ao passar pelo valor atual do fader do `Pad` na tela (ganho 0,55, −5,2 dB, cerca de `CC 83` com curva `Linear`), o fader do app passa a acompanhar e o movimento começa a ser gravado. Se a raia `Volume` já tem uma curva e o fader ainda está seguindo ela (antes de você pegar o controle), o valor comparado é o que o fader mostra naquele ponto da curva, não o valor fixo dele.
5. Pare de mexer. Depois de **0,7 s sem mensagens** o app entende que você soltou (o controlador não tem "soltar"): o valor volta ao da automação numa rampa de 1/4 de batida (e o valor fixo do fader do app volta ao de antes de você mexer), e os pontos gravados aparecem na raia `Volume`. Com o loop ligado, se a volta acabar enquanto você ainda mexe, o `Toque` para na virada e só grava de novo quando o fader mexer outra vez `(testado só por testes automáticos; com MIDI vem da leitura do código)`. Mexa o `CC 42` na volta seguinte da mesma forma para gravar o `Corte`.
6. Pare (`Espaço`). Confira as raias `Volume` do `Pad` e `Filtro · Corte`. `Ctrl+Z` desfaz a passada inteira de uma vez; refazer com `Ctrl+Shift+Z`.
7. Para o fader ficar onde você o largou até o fim, troque `Toque` por `Trava` (o app mantém o último valor até parar). Com o loop ligado, a `Trava` só segue gravando na volta seguinte enquanto o controle ainda conta como seguro (menos de 0,7 s sem mensagens); depois disso ela para na virada do loop `(lido do código)`.

Variações:

- **Regravar só um trecho:** com o loop no trecho, `Toque` e mexa o fader só onde quer trocar; o resto da curva não muda ([Automação, passo a passo](../manual/07-automacao.md#passo-a-passo)).
- **Um fader só, vários controles:** mapear o mesmo `CC` a `Volume` e `Corte` grava as duas raias com um gesto só.
- **Sem controlador:** os mesmos modos valem com o mouse ([mixagem e automação, passo 5](mixagem-e-automacao.md#5-gravar-um-fade-e-uma-varredura-de-filtro-com-o-mouse)).

## Por que funciona

O app trata a mensagem do controlador como um gesto do mouse: a conta leva o valor de 0 a 1 do controlador à posição do controle (curva, `Invertido`, `Mín`/`Máx`), converte para a escala do controle (curva do fader no volume, logarítmica em Hz) e chama os mesmos setters de quem arrasta. Por isso valem o desfazer, o motor, a gravação de automação e a escala certa sem configuração extra: em Hz o meio do giro é a média geométrica (632 Hz entre 20 Hz e 20 kHz), e no fader o meio do giro é bem abaixo de 0 dB (−11,8 dB no `CC 64` linear), o que a curva `Logarítmica` e o `Máx` de 79% consertam. O `Suave` existe porque um botão de hardware não sabe onde o controle na tela está; a troca é ter de "pegar" o valor antes.

## Se der errado

| Sintoma | Causa provável | O que fazer |
|---|---|---|
| O botão `Aprender MIDI` não aparece na barra | Entrada MIDI desligada e sem mapeamentos no projeto | Ligue o cabo, ou use `Shift+K` (que liga o modo e pede o MIDI). Com o teclado do computador ligado `Shift+K` vira nota |
| A faixa diz `nenhum aparelho conectado` | O navegador não vê o controlador (permissão negada, outro programa segurando o aparelho, cabo) | Confira a permissão do site e reconecte; o aparelho aparece sozinho |
| Girei o knob e o controle não mexe | `Suave`: o controle espera o botão cruzar o valor dele | Gire até o valor do controle (o app não salta) ou desligue `Suave` na janela |
| Aprendi o knob errado | Arma o controle certo e gira o certo de novo | O mapeamento novo substitui o anterior; ou `Remover mapeamento (...)` no menu do controle |
| O pedal de sustain parou de segurar notas | Um `CC 64` está mapeado nesse canal | Ache a linha `Canal N · CC 64` em `Mapeamentos MIDI` e remova (vale também com o alvo apagado) |
| A automação não grava | Botão `Automação` em `Ler`, música parada ou gravando `R` | `Escrever`, `Toque` ou `Trava`; play; sem `R` |
| O valor volta sozinho no `Toque` | 0,7 s sem mexer conta como soltar | É esperado; use `Trava` para manter |
| Uma linha vermelha na janela | A faixa, o efeito ou o envio foi removido | Remova a linha (lixeira); desfazer a remoção do alvo a reativa |
| O mapeamento sumiu em outro aparelho | O projeto trouxe o mapa da nuvem e substituiu o local | O mapa é parte do projeto; mapeie de novo ou use o padrão para novos projetos (só no aparelho) |
| Com o modo ligado o knob não gira | No modo os controles só respondem a clique | `Esc` (ou `Sair`) e use o mouse |
