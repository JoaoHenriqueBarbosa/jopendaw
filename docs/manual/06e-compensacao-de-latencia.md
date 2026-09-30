# Compensação de latência dos efeitos

> Alguns efeitos atrasam o som que passa por eles; o motor atrasa o resto da mixagem na mesma medida, sozinho, para que faixas, retornos e sidechain continuem alinhados. Leia para saber quais efeitos atrasam, quanto, e o que fazer ao gravar por cima de um projeto com esses efeitos.

Nome técnico: PDC (*plugin delay compensation*). Não há botão, janela nem indicador dela no app: ela roda no motor a cada mudança de efeito ou de roteamento. O único controle que muda a latência é o `Lookahead` do `Limitador`.

Toda a parte de "o motor faz" vem da leitura do código (`engine/src/lib.rs`, `mixer.rs`, `dsp.rs`) e dos testes automáticos do motor; a parte da gravação vem de `app/lib/daw/controller.dart` e dos testes do app. **Nada disto foi ouvido no navegador nem no Android** `(testado só por testes automáticos)`.

## Onde fica

Em lugar nenhum da tela: é automática. Você a percebe por três caminhos:

- Ao pôr ou tirar um `Limitador` ou uma `Distorção` numa faixa, num barramento ou no `Master` (painel `Efeitos`, [06c](06c-painel-de-efeitos.md)), o resto da mixagem se realinha sozinho.
- Ao mexer no knob `Lookahead` do `Limitador` (editor do efeito, [06d](06d-efeitos-referencia.md#4-limitador)), à mão ou por automação ([07](07-automacao.md)).
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
| Os outros treze efeitos (`EQ`, `Compressor`, `Gate`, `Utilitário`, `Reverb`, `Delay`, `Chorus`, `Phaser`, `Tremolo`, `Filtro`, `Multibanda`, `De-esser`, `Imagem estéreo`) | 0. O pré-atraso do reverb e o tempo do delay fazem parte do som. Os três últimos (fase 15) dividem o som com filtros Linkwitz-Riley ou passa-banda que giram a fase mas não atrasam no tempo, e o teste do motor confere `latency() == 0` neles `(testado só por testes automáticos)` | Nada a compensar |

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
| Clique do metrônomo | Entra depois da cadeia do `Master`, então é atrasado da latência total das faixas mais a da cadeia do `Master`: soa junto do som das faixas. Nos testes automáticos, com `Limitador` de 3 ms numa faixa ou no `Master` o clique sai 144 quadros depois; com um em cada, 288 (a 48 kHz) |

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

**Alinhamento durante a troca do `Lookahead`.** A PDC usa o lookahead pedido, mas o limitador só troca o atraso real depois do fade de saída de 4 ms (e sobe a entrada em outros 4 ms): nesse intervalo, no máximo uns 8 ms por mudança e com o som do limitador abaixado, as faixas ficam desalinhadas pela diferença entre o lookahead antigo e o novo (no máximo 10 ms). Documentado e limitado, não corrigido `(lido do código)`.

**Anéis da PDC sem alocar.** Uma lane que automatiza o `Lookahead` de um limitador faz o comando que a cria reservar folga (10 ms por lane) em todos os atrasos, então a rampa não aloca na thread de áudio, nem numa faixa que antes não tinha atraso nem numa cadeia de vários limitadores de 10 ms. Se algo ainda não couber, o atraso fica limitado à capacidade até o próximo comando refazer a conta `(testado só por testes automáticos)`.

**Automatizar o `Lookahead`** é acompanhado: o motor percebe que a latência do efeito mudou e refaz a conta no máximo a cada 20 ms (uma rampa contínua recalcula até 50 vezes por segundo; a última mudança sempre chega, com até 20 ms de atraso). O limitador, porém, troca o `Lookahead` abaixando a própria saída por um instante (fade de 4 ms para baixo e outro para cima) a cada valor novo; numa rampa contínua isso se repete o tempo todo e o som pulsa. Prefira degraus (um valor, depois outro) a rampas `(lido do código; não confirmado ao ouvido)`. O teste automático mede o degrau de 3 ms para 10 ms (144 para 480 quadros a 48 kHz): antes o clipe sai alinhado com 144, depois com 480 `(testado só por testes automáticos)`.

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

O app pergunta ao motor a latência dele (PDC das faixas e barramentos, cadeia de inserts do `Master` e limitador de segurança de 1,5 ms) e a soma à do aparelho ao compensar a gravação. Você não soma mais nada à mão no campo `Compensação de latência` da janela `Configurações`; ele continua sendo só um ajuste fino, de −200 a +500 ms, em ms inteiros ([03c](03c-gravacao.md)). O que é somado, e onde:

| Gravação | O que o app desconta | Leva em conta |
|---|---|---|
| Áudio (clipe do microfone) | Do começo do que a entrada mandou | Latência do motor + latência de saída do aparelho (`baseLatency` + `outputLatency` na web) + latência da entrada + `Compensação de latência` |
| Notas e controles MIDI (bend, modulação, pedal) | Cada nota e cada ponto voltam para antes | Latência do motor + latência de saída do aparelho. A latência da entrada e a `Compensação de latência` **não** valem para o MIDI |

1. Toque junto do que você ouve: o motor soa `latência do motor` depois do cursor, e as notas que você toca ouvindo esse som chegam atrasadas desse tanto (mais o da saída do aparelho); o app as devolve para a posição em que você as ouviu. As notas e os pontos de bend, modulação e pedal não recuam para antes do começo da gravação (com o loop ligado, do que vier primeiro entre o começo da gravação e o começo do loop).
2. O clique do metrônomo passa por um atraso da latência total (PDC mais a cadeia do `Master`) e soa junto das faixas; tocando junto dele, o clipe cai na grade. O clique do tempo 0 também sai com esse atraso. O limitador de segurança atrasa clique e faixas por igual, então não entra nessa conta.
3. Se o clipe gravado ainda cair um pouco fora, ajuste `Compensação de latência`: positivo adianta o clipe gravado. Só vale para o áudio.
4. A latência é lida **uma vez, ao começar a gravação**. Mudar o `Lookahead` ou o roteamento no meio da gravação não altera a compensação daquela tomada.

`(testado só por testes automáticos; não confirmado ao ouvido nem no navegador ou no Android)`. O texto de ajuda da janela `Configurações` ("Quanto o áudio gravado chega atrasado, além do que já é medido sozinho (a latência do motor, com os efeitos e o limitador, e a que o navegador informa para a entrada e a saída)…") cita a latência do motor, e a linha `Ida e volta do monitoramento: N ms`, logo abaixo, mostra o que quem toca ouve entre o gesto e o som.

### Mudar o Lookahead tocando

1. Abra o `Limitador` no painel `Efeitos` e mova `Lookahead`.
2. O limitador abaixa a saída por um instante (fade de 4 ms) para trocar o atraso e volta; a compensação das outras faixas troca por crossfade de 10 ms. Se ouvir um sopro curto, é isso.

## Combina com

- [06d Referência dos efeitos](06d-efeitos-referencia.md#latência-e-custo-de-cada-efeito): `Limitador` e `Distorção`, parâmetro por parâmetro.
- [06 Mixer](06-mixer.md): envios, barramentos, sidechain e o limitador de segurança do master.
- [06c Painel de efeitos](06c-painel-de-efeitos.md): adicionar, tirar e ligar efeitos.
- [03c Gravação](03c-gravacao.md): a latência do aparelho e a do motor (PDC, `Master`, limitador de segurança) são compensadas, no áudio e nas notas MIDI.
- [08 Exportação](08-exportacao.md): mixagem e stems saem alinhados.
- [07 Automação](07-automacao.md): a automação age alguns ms adiantada numa faixa com efeito de latência.
- [Efeitos em combinação](../guias/efeitos-em-combinacao.md) e [Mixagem e automação](../guias/mixagem-e-automacao.md): compressão paralela e retorno por barramento sem som oco.

## Limites e pegadinhas

- **A latência do motor só chega ao app com o motor da fase 13.** O `engine.wasm` e os três `.so` commitados já trazem `latency_frames` e `jd_engine_latency`; uma página web em cache do `engine.wasm`/`worklet.js`/`host.js` antigos ou um APK de antes da fase 13 fica com a latência do motor valendo 0, e aí o app compensa só a do aparelho e a manual (as notas MIDI não recuam nada). Na web o worklet publica o valor só quando ele muda e a cada 12 blocos (cerca de 32 ms a 48 kHz): logo depois de mexer num efeito, o valor lido pode estar até esse tanto atrasado.
- **O monitoramento de uma faixa de áudio armada também passa pelos atrasos.** A entrada soma antes dos efeitos da faixa e sai com a latência do projeto (PDC mais a cadeia do `Master` e o limitador de segurança), além da do aparelho: o teste automático mede o impulso monitorado saindo exatamente `latência do motor` quadros depois. Sem nenhum efeito de latência no projeto (`Lookahead` em 0 e sem `Distorção`), o monitor volta à latência do aparelho mais 1,5 ms do limitador de segurança. O app calcula a ida e volta do monitor (`monitorLatency`: entrada, motor e saída) e a mostra em `Configurações`, abaixo da compensação (a parte da entrada só aparece com o microfone aberto).
- **A automação age alguns milissegundos adiantada** em relação ao som de uma faixa (ou barramento) cuja cadeia tenha latência: o valor automatizado é aplicado ao som que está a essa latência de chegar. Numa faixa com `Limitador` de 3 ms, um fade de volume começa 3 ms antes do som correspondente. Faixas sem efeito de latência não sofrem isso. Notas e automação são agendadas no tempo da faixa; a compensação atrasa só o áudio já renderizado.
- **Ao vivo, o som sai a latência do projeto depois do cursor.** Uns poucos milissegundos com os padrões; o app não mostra esse número. O clique do metrônomo acompanha o som das faixas, mas o cursor e a posição da régua mostram o transporte, não o que está saindo agora.
- **Parar corta o resto do clique.** Ao parar o transporte, dar `seek` ou usar o pânico, o clique que ainda estava no atraso do metrônomo é descartado junto com o dele.
- **Reordenar efeitos e trocar o tipo** recria efeitos no motor ([06c](06c-painel-de-efeitos.md)); a latência é reavaliada, e a compensação segue.
- **Automatizar `Lookahead`** é acompanhado com até 20 ms de atraso, mas faz o limitador abaixar a saída a cada valor novo (ver Controles).
- **Trocar o tipo de um efeito que soava mantém o crossfade de 10 ms**, também nos efeitos bem audíveis (`Distorção`, `EQ`, `Filtro`): o teste automático mede que o degrau na troca não passa de 1,5 vez o degrau normal do próprio som (mais uma folga de 0,01).
- **Nada disto foi ouvido no Chrome nem no Android.** Vale o que os testes automáticos do motor medem: impulsos alinhados em faixas, barramentos, envios, sidechain e master; clique do metrônomo alinhado; bypass e troca de efeito sem degrau; render offline igual ao tempo real; ausência de alocação no meio do áudio, com os anéis já dimensionados ou com a folga que o comando da lane de `Lookahead` reserva. Os testes do app medem a compensação da gravação com um motor de mentira (`FakeEngine`), sem som real.
- **Salvo com o projeto:** nada é salvo por causa da compensação; ela é recalculada a partir dos efeitos, envios e saídas que o projeto tem.

## Atalhos

Este assunto não tem atalho próprio.
