# Compensação de latência dos efeitos

> Alguns efeitos atrasam o som que passa por eles; o motor atrasa o resto da mixagem na mesma medida, sozinho, para que faixas, retornos e sidechain continuem alinhados. Leia para saber quais efeitos atrasam, quanto, e o que fazer ao gravar por cima de um projeto com esses efeitos.

Nome técnico: PDC (*plugin delay compensation*). Não há botão, janela nem indicador dela no app: ela roda no motor a cada mudança de efeito ou de roteamento. O único controle que muda a latência é o `Lookahead` do `Limitador`.

Toda a parte de "o motor faz" vem da leitura do código (`engine/src/lib.rs`, `mixer.rs`, `dsp.rs`) e dos testes automáticos do motor. **Nada disto foi ouvido no navegador nem no Android** `(testado só por testes automáticos)`.

## Onde fica

Em lugar nenhum da tela: é automática. Você a percebe por três caminhos:

- Ao pôr ou tirar um `Limitador` ou uma `Distorção` numa faixa, num barramento ou no `Master` (painel `Efeitos`, [06c](06c-painel-de-efeitos.md)), o resto da mixagem se realinha sozinho.
- Ao mexer no knob `Lookahead` do `Limitador` (editor do efeito, [06d](06d-efeitos-referencia.md#4-limitador)).
- Ao mudar saída ou envio de uma faixa ([06 Mixer](06-mixer.md)) ou a faixa-chave de um `Compressor` ou `Gate`: a conta é refeita.

## O que é a latência de um efeito

Um efeito com latência só devolve o som depois de ver um pedaço do que vem a seguir. O `Limitador` precisa enxergar o pico antes de ele chegar para abaixar o ganho a tempo (é o `Lookahead`); a `Distorção` usa filtros de sobreamostragem que atrasam o sinal. Em ambos o áudio sai atrasado do mesmo tanto, sempre, tocando ou não.

Sem compensação, uma faixa com `Limitador` soaria alguns milissegundos depois das outras, e um envio para um barramento com esses efeitos chegaria atrasado em relação ao som seco da mesma faixa (filtro de pente, som oco). A compensação atrasa o que não passou pelo efeito.

## Quais efeitos têm latência

| Fonte | Latência | Entra na compensação? |
|---|---|---|
| `Limitador` (efeito, em faixa, barramento ou master) | Igual ao `Lookahead`: 0 a 10 ms, padrão 3 ms. Em quadros inteiros: 3 ms são 144 quadros a 48 kHz e 132 a 44,1 kHz; 10 ms são 480 quadros a 48 kHz. Com `Lookahead` 0, nenhuma | Sim |
| `Distorção` | 32 quadros fixos nos seis tipos e nas três sobreamostragens: 0,67 ms a 48 kHz, cerca de 0,73 ms a 44,1 kHz | Sim |
| Limitador de segurança do `Master` (sempre ligado, sem controle na tela) | 1,5 ms (72 quadros a 48 kHz) | Não precisa: fica depois da soma, atrasa tudo por igual. Conta só na latência total do motor |
| Os outros dez efeitos (`EQ`, `Compressor`, `Gate`, `Utilitário`, `Reverb`, `Delay`, `Chorus`, `Phaser`, `Tremolo`, `Filtro`) | 0. O pré-atraso do reverb e o tempo do delay fazem parte do som | Nada a compensar |

Os quadros são o que o motor usa; para converter, divida pela taxa de amostragem (a taxa do aparelho, em geral 44,1 ou 48 kHz).

## Como o motor alinha as faixas

O motor pensa no projeto como um caminho: faixas, depois barramentos, depois o `Master`. Para cada faixa ou barramento ele calcula:

1. **Quanto o sinal já chega atrasado** na entrada da cadeia de efeitos. Uma faixa de som nasce com 0; um barramento chega com a maior latência entre tudo o que entra nele.
2. **Quanto sai atrasado**: o de entrada mais a soma da latência dos efeitos da cadeia.
3. **O que falta para alinhar** com os outros que chegam ao mesmo destino: cada saída e cada envio ganha um atraso igual à diferença. Assim tudo que entra num barramento (ou no `Master`) chega junto.

A latência do projeto é a maior soma de ponta a ponta, e todas as fontes são levadas a ela.

Exemplo, a 48 kHz: a faixa 1 tem um `Limitador` de 3 ms (144 quadros), sai direto no `Master` e manda também um envio para um barramento com uma `Distorção` (32 quadros). A faixa 2 não tem efeito e sai direto no `Master`. O barramento recebe o envio com 144 quadros e sai com 144 + 32 = 176 (cerca de 3,67 ms), que é o caminho mais longo. Então a saída direta da faixa 1 é atrasada 32 quadros (para chegar ao `Master` junto com o retorno do barramento, sem pente) e a faixa 2 é atrasada 176 quadros. Todo o projeto sai 176 quadros depois do cursor.

Vale para:

| Situação | O que o motor faz |
|---|---|
| Faixa com efeito de latência e outra sem | A sem efeito é atrasada da diferença |
| Saída de faixa para um barramento com efeito de latência | A saída direta e as outras entradas do barramento esperam para chegar juntas |
| Envio pré-fader e pós-fader | Cada envio ganha o seu atraso; o retorno não faz pente com o seco da mesma faixa |
| Barramentos em cadeia | As latências somam ao longo do caminho |
| Sidechain (`Compressor` e `Gate` com faixa-chave) | A chave é atrasada até chegar alinhada com o sinal do efeito; se a chave é mais tardia que o sinal, a fonte da faixa espera |
| Efeito de latência no `Master` | Soma-se à latência total; não há o que alinhar depois dele |

Se a faixa-chave só é processada depois da faixa que a usa (por exemplo, um barramento como chave de uma faixa comum), a chave já chega um bloco atrasada por outra razão e ela não entra na conta.

## Bypass, trocar e tirar efeitos

- **Bypass não muda o alinhamento.** A latência do efeito conta ligado ou desligado. Com a luz do efeito apagada o som segue atravessando um atraso do mesmo tamanho, então ligar e desligar não desloca nada e não estala (a mistura entre seco e efeito continua sendo o crossfade de 10 ms de sempre). Para tirar de vez a latência, remova o efeito ou ponha o `Lookahead` do `Limitador` em 0.
- **Pôr, remover, trocar o tipo ou mudar o `Lookahead` com som passando** refaz a conta entre um bloco e outro e muda os atrasos por um crossfade de 10 ms, sem estalo (os testes automáticos medem que não há degrau).
- **Faixa sem som.** Se a faixa está calada quando a latência muda, o novo valor vale de uma vez (não há som para misturar); só faixas com som fazem crossfade.
- **Cauda.** Depois que a fonte cala, a faixa continua rodando com silêncio o tempo da latência total, para o que ainda está nos atrasos sair. Parar o transporte não corta esse resto.
- **Voltar de um bypass** com `Limitador`: o efeito reaprende os últimos milissegundos de entrada antes de voltar, para o crossfade não abrir um buraco.

## Exportar, stems e congelar

- **Mixagem e stems saem alinhados com a linha do tempo.** O render offline descarta a latência total no começo: o primeiro quadro do arquivo é o da posição de partida, para a mixagem e para cada stem. Um stem de faixa é capturado no ponto em que a faixa entra no destino dela (depois do fader e do atraso de saída), e os stems de faixas com e sem efeito de latência batem quadro a quadro com a mixagem.
- **O resultado do render é o mesmo do tempo real**, só deslocado da latência (teste automático).
- **Congelar em áudio** usa o mesmo render; pelo código o resultado também sai alinhado `(não confirmado)`.
- Ver [08 Exportação](08-exportacao.md).

## Limite de 1 segundo

Cada efeito, cada nó e a latência total são limitados a **1 s** (uma taxa de amostragem em quadros). Na prática não se chega perto: 16 `Limitador` com 10 ms numa cadeia dão 160 ms. Numa cena absurda que passasse de 1 s o alinhamento degrada, sem travar nem estourar `(testado só por testes automáticos)`.

## Controles

Não há controles próprios. Estes são os que interferem:

| Controle | Efeito na compensação | Valores / padrão | Dica |
|---|---|---|---|
| `Lookahead` (`LIMITADOR`) | Define a latência do `Limitador`; a conta é refeita ao mudar | 0 a 10 ms, linear, padrão 3 ms | Mais lookahead = ataque mais suave e mais latência; 0 = sem latência |
| Luz de ligar e desligar o efeito | Nenhum: a latência conta ligado ou não | | Para desfazer a latência, remova o efeito |
| `Adicionar efeito` e `Remover` | Soma ou tira a latência do efeito | | Refaz a conta sem estalo |
| Saída da faixa e envios | Mudam os caminhos, então a conta é refeita | | |
| `Sidechain` do `Compressor` e do `Gate` | A chave passa a ser alinhada com o sinal | | |

Automatizar o `Lookahead` do `Limitador` não é acompanhado pela compensação: a latência real muda com a automação, mas a conta só é refeita no próximo comando (mudar um parâmetro à mão, adicionar ou tirar efeito, mexer no roteamento). Não automatize o `Lookahead` em projeto que dependa de alinhamento `(lido do código; não confirmado por uso)`.

## Passo a passo

### Saber quanta latência o projeto tem

1. Liste, faixa por faixa e barramento por barramento, os efeitos com latência: `Limitador` com `Lookahead` acima de 0 e `Distorção`.
2. Some, ao longo de cada caminho (faixa, depois o barramento para onde ela vai por saída ou envio, depois o `Master`), as latências dos efeitos que o sinal atravessa.
3. O maior total é a latência do projeto. Converta: ms = quadros ÷ taxa × 1000. O `Master` soma a dele por cima (a cadeia dele e mais 1,5 ms do limitador de segurança).

### Conferir se a mix está alinhada

Este é um teste de cancelamento: dois caminhos idênticos, um com efeito de latência, somam silêncio se estiverem alinhados. Não foi feito no navegador `(não confirmado)`.

1. Numa faixa de áudio, ponha um clipe com transientes (uma batida ou pizzicato) que não passe de −6 dBFS.
2. No menu da faixa, escolha `Duplicar a faixa` ([02b](02b-timeline-e-clipes.md)). A cópia leva o clipe.
3. Na cópia, adicione o efeito `Utilitário` com `Inverter esq.` e `Inverter dir.` em `Sim`, e depois dele um `Limitador` com `Ganho` 0 dB, `Teto` 0 dB e `Lookahead` 3 ms.
4. Toque. Alinhado, as duas faixas se cancelam e sobra só um resíduo muito abaixo do clipe original. Desalinhado, você ouve o transiente do clipe (um clique ou um "flange" curto) no começo de cada batida.
5. Mude o `Lookahead` com o projeto tocando (por exemplo para 8 ms). A saída da cópia abaixa por um instante (fade de 4 ms do limitador) e, depois de uns 10 ms de crossfade, o resíduo deve voltar a ser baixo.
6. Para testar um barramento, passe o `Utilitário` invertido e o `Limitador` para um barramento novo, mande a saída da cópia para ele (botão de saída da faixa, [06 Mixer](06-mixer.md)) e deixe a original no `Master`; o resultado esperado é o mesmo.

### Gravar por cima de um projeto com efeitos de latência

O app soma a latência do projeto (PDC, cadeia do `Master` e limitador de segurança) à do aparelho ao compensar a gravação, tanto no áudio quanto nas notas MIDI (ver [03c](03c-gravacao.md)). Você não precisa mais somá-la ao campo `Compensação de latência` da janela `Configurações`; ele continua sendo um ajuste fino, em ms inteiros. `(precisa do motor recompilado; testado só por testes automáticos)`

1. Se o clipe gravado ainda cair um pouco fora, ajuste `Compensação de latência` como antes: positivo adianta o clipe gravado.
2. O clique do metrônomo é atrasado da mesma latência total e soa junto das faixas; tocando junto dele, o clipe cai na grade `(testado só por testes automáticos; não confirmado ao ouvido)`.

### Mudar o Lookahead tocando

1. Abra o `Limitador` no painel `Efeitos` e mova `Lookahead`.
2. O limitador abaixa a saída por um instante (fade de 4 ms) para trocar o atraso e volta; a compensação das outras faixas troca por crossfade de 10 ms. Se ouvir um sopro curto, é isso.

## Combina com

- [06d Referência dos efeitos](06d-efeitos-referencia.md#latência-e-custo-de-cada-efeito): `Limitador` e `Distorção`, parâmetro por parâmetro.
- [06 Mixer](06-mixer.md): envios, barramentos, sidechain e o limitador de segurança do master.
- [06c Painel de efeitos](06c-painel-de-efeitos.md): adicionar, tirar e ligar efeitos.
- [03c Gravação](03c-gravacao.md): a latência do aparelho e a da PDC são compensadas.
- [08 Exportação](08-exportacao.md): mixagem e stems saem alinhados.
- [07 Automação](07-automacao.md): a automação age alguns ms adiantada numa faixa com efeito de latência.
- [Efeitos em combinação](../guias/efeitos-em-combinacao.md) e [Mixagem e automação](../guias/mixagem-e-automacao.md): compressão paralela e retorno por barramento sem som oco.

## Limites e pegadinhas

- **A latência do motor só chega ao app com o motor recompilado.** Com `engine.wasm` ou os `.so` de antes da fase 13, o app compensa só a latência do aparelho e a manual.
- **O monitoramento de uma faixa de áudio armada também passa pelos atrasos.** A entrada soma antes dos efeitos da faixa e sai com a latência do projeto, além da do aparelho. Sem nenhum efeito de latência no projeto (`Lookahead` em 0 e sem `Distorção`), o monitor volta à latência do aparelho mais 1,5 ms do limitador de segurança.
- **A automação age alguns milissegundos adiantada** em relação ao som de uma faixa (ou barramento) cuja cadeia tenha latência: o valor automatizado é aplicado ao som que está a essa latência de chegar. Numa faixa com `Limitador` de 3 ms, um fade de volume começa 3 ms antes do som correspondente. Faixas sem efeito de latência não sofrem isso. Notas e automação são agendadas no tempo da faixa; a compensação atrasa só o áudio já renderizado.
- **Ao vivo, o som sai a latência do projeto depois do cursor.** Uns poucos milissegundos com os padrões; o app não mostra esse número.
- **Reordenar efeitos e trocar o tipo** recria efeitos no motor ([06c](06c-painel-de-efeitos.md)); a latência é reavaliada, e a compensação segue.
- **Automatizar `Lookahead`** não é acompanhado (ver Controles).
- **Nada disto foi ouvido no Chrome nem no Android.** Vale o que os testes automáticos do motor medem: impulsos alinhados em faixas, barramentos, envios, sidechain e master; bypass e troca de efeito sem degrau; render offline igual ao tempo real; ausência de alocação no meio do áudio.
- **Salvo com o projeto:** nada é salvo por causa da compensação; ela é recalculada a partir dos efeitos, envios e saídas que o projeto tem.

## Atalhos

Este assunto não tem atalho próprio.
