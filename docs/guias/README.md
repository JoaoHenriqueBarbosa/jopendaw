# Mapa de combinações

> O que combina com o quê no jopendaw: objetivos de produção apontando para os capítulos e guias, matrizes recurso × recurso com valores de partida, as combinações que atrapalham e receitas de uma linha. É um índice de consulta rápida; o passo a passo mora nos guias desta pasta e o detalhe de cada botão, nos capítulos de [`../manual/`](../manual/).

## Como ler este mapa

- **Quatro partes.** [1. Por objetivo](#1-por-objetivo) (quero fazer X, leia Y) · [2. Matriz recurso × recurso](#2-matriz-recurso--recurso) (o que uma coisa faz com a outra) · [3. Combinações que atrapalham](#3-combinações-que-atrapalham) (o que evitar juntos e por quê) · [4. Receitas rápidas de uma linha](#4-receitas-rápidas-de-uma-linha).
- **Célula em branco** nas matrizes quer dizer que os capítulos e os guias não registram uma combinação útil daquele par (ou que o par não existe: a `Bateria` não tem afinação, por exemplo). Não é uma promessa de que soe mal; é só a ausência de receita.
- **Valores de partida** são pontos de partida musicais tirados dos presets, das tabelas de parâmetros e dos guias. O que se ouve deve ser acertado de ouvido. Quando um capítulo marca `(não confirmado)`, `(não confirmado ao ouvido)`, `(não confirmado em uso)` ou `(testado só por testes automáticos)`, a marca vem junto aqui.
- **Efeitos de faixa.** Todo efeito citado nas matrizes é um insert da cadeia da faixa (depois do instrumento ou dos clipes, antes do volume e do pan), a não ser que a célula diga que é num barramento ou no master ([06c Painel de efeitos](../manual/06c-painel-de-efeitos.md)).
- **Links.** `../manual/...` são capítulos; os nomes sem pasta são guias desta mesma pasta. Rótulos em `crase` são os do app.
- **Deduções.** Quando uma célula junta dois fatos dos capítulos sem que haja receita testada, ela diz `(dedução)`.

Guias desta pasta, por ordem de uso comum: [Primeira batida do zero](primeira-batida-do-zero.md) · [Gravar uma banda e mixar](gravar-uma-banda-e-mixar.md) · [Melodia e harmonia com as ferramentas](melodia-e-harmonia-com-as-ferramentas.md) · [FM e wavetable na prática](fm-e-wavetable-na-pratica.md) · [Sampler multi-zona e fatiar loops](sampler-multi-zona-e-fatiar-loops.md) · [Expressão MIDI na prática](expressao-midi-na-pratica.md) · [Efeitos em combinação](efeitos-em-combinacao.md) · [Mixagem e automação](mixagem-e-automacao.md) · [Loudness e master](loudness-e-master.md) · [Remix com warp e altura](remix-com-warp-e-altura.md) · [Trabalhar em dois aparelhos](trabalhar-em-dois-aparelhos.md) · [Backup e levar o projeto para outro aparelho](backup-e-levar-projeto-para-outro-aparelho.md) · [Atalhos e fluxo rápido](atalhos-e-fluxo-rapido.md).

---

## 1. Por objetivo

Cada linha é um objetivo real de produção. A coluna "Leia" começa pelo guia que resolve o caso inteiro e depois lista os capítulos com os controles usados.

### Ritmo, notas e composição

| Quero… | Leia |
|---|---|
| Fazer uma batida do zero (bateria, baixo, pad, retorno de reverb, loop e WAV) | [Primeira batida do zero](primeira-batida-do-zero.md) · [04b Bateria](../manual/04b-bateria.md) · [05 Piano roll](../manual/05-piano-roll.md) · [01 modelo `Batida eletrônica`](../manual/01-projetos-modelos-conta.md#batida-eletrônica) |
| Programar bateria com groove e notas fantasma | [04b Bateria, dinâmica e notas fantasma](../manual/04b-bateria.md#dinâmica-e-notas-fantasma) · [05 Piano roll, painel de velocidade](../manual/05-piano-roll.md#painel-de-velocidade-vel) · [Primeira batida do zero, variações](primeira-batida-do-zero.md#variações) |
| Tocar a bateria no teclado do computador, camada por camada | [Gravar uma banda e mixar, passo 4](gravar-uma-banda-e-mixar.md#4-bateria-tocada-nas-teclas-camada-por-camada-overdub-midi) · [04b Bateria, tocar no computador](../manual/04b-bateria.md#tocar-a-bateria-no-computador) · [03c Gravação](../manual/03c-gravacao.md) |
| Escrever acordes com um clique, sem sair da escala | [Melodia e harmonia, passo 1](melodia-e-harmonia-com-as-ferramentas.md#1-a-progressão-c-am-f-g-um-compasso-cada) · [05b Ferramentas MIDI, escala e acordes](../manual/05b-ferramentas-midi.md#escala-e-acordes) |
| Transformar acordes em arpejo, ou fazer um baixo em oitavas a partir das fundamentais | [Melodia e harmonia, passos 2 e 4](melodia-e-harmonia-com-as-ferramentas.md#2-virar-arpejo) · [05b Arpejador](../manual/05b-ferramentas-midi.md#diálogo-arpejador) |
| Escrever uma melodia que nunca erra nota | [Melodia e harmonia, passo 6](melodia-e-harmonia-com-as-ferramentas.md#6-uma-melodia-que-nunca-erra-nota) · [05b Escala do clipe](../manual/05b-ferramentas-midi.md#diálogo-escala-do-clipe) |
| Deixar uma linha tocada ao vivo firme (quantizar) ou mais humana (humanizar) | [Melodia e harmonia, passo 3](melodia-e-harmonia-com-as-ferramentas.md#3-humanizar-e-quantizar) · [05 Piano roll, `Quantizar`](../manual/05-piano-roll.md) · [05b Humanizar](../manual/05b-ferramentas-midi.md#diálogo-humanizar) |
| Organizar a música em seções e ensaiar uma parte em loop | [Atalhos e fluxo rápido, passo 1](atalhos-e-fluxo-rapido.md#1-marcar-a-música-enquanto-ela-toca-e-ensaiar-uma-parte) · [02b Marcadores e seções](../manual/02b-timeline-e-clipes.md#marcadores-e-seções) · [02 Transporte](../manual/02-transporte.md) |
| Mudar andamento e compasso, ligar loop e metrônomo | [02 Transporte](../manual/02-transporte.md) · [01b Andamento e compasso](../manual/01b-nuvem-e-sincronizacao.md#andamento-e-compasso) |

### Gravação

| Quero… | Leia |
|---|---|
| Gravar voz e limpar (gate, EQ, compressor, reverb) | [Gravar uma banda e mixar](gravar-uma-banda-e-mixar.md) · [Efeitos em combinação, receita 1](efeitos-em-combinacao.md#receita-1-cadeia-vocal-gate-eq-compressor-reverb) · [03c Gravação](../manual/03c-gravacao.md) |
| Acertar o nível do microfone e calibrar a latência | [Gravar uma banda e mixar, passos 2 e 3](gravar-uma-banda-e-mixar.md#2-o-microfone-permissão-entrada-e-nível) · [06b Medidor de entrada](../manual/06b-analisador-e-medidores.md#medidor-de-entrada-e-o-clip) · [09 Configurações](../manual/09-configuracoes-atalhos-android.md) |
| Gravar várias tomadas em loop e escolher a melhor | [Gravar uma banda e mixar, passos 6 e 7](gravar-uma-banda-e-mixar.md#6-voz-monitor-e-tomadas-em-loop) · [03c Gravação](../manual/03c-gravacao.md) |
| Gravar bend, modulação e pedal com um teclado MIDI | [Expressão MIDI, receita 4](expressao-midi-na-pratica.md#receita-4-gravar-com-um-teclado-midi-de-verdade) · [03c Gravação](../manual/03c-gravacao.md) |
| Transformar uma melodia cantada em notas | [03d Áudio para MIDI](../manual/03d-audio-para-midi.md) · [Remix, variação "Tirar a melodia do trecho esticado"](remix-com-warp-e-altura.md#variações) |

### Mixagem, efeitos e espaço

| Quero… | Leia |
|---|---|
| Montar um mix do zero (níveis, pan, envios, master) | [Mixagem e automação, passo 1](mixagem-e-automacao.md#1-ajustar-um-mix-do-zero) · [06 Mixer](../manual/06-mixer.md) · [06b Medidores](../manual/06b-analisador-e-medidores.md) |
| Dar espaço com reverb sem encher a mix | [Mixagem e automação, passo 2](mixagem-e-automacao.md#2-criar-um-barramento-de-reverb-compartilhado) · [06 Mixer, envios](../manual/06-mixer.md#envios) · [06d Reverb](../manual/06d-efeitos-referencia.md#6-reverb-fdn) |
| Fazer o baixo (ou o pad) "bombear" com o bumbo | [Efeitos em combinação, receita 3](efeitos-em-combinacao.md#receita-3-sidechain-pumping-com-o-bumbo) · [06d O sidechain](../manual/06d-efeitos-referencia.md#o-sidechain-o-que-ele-exige) |
| Dar peso à bateria sem perder o ataque (compressão paralela) | [Efeitos em combinação, receita 2](efeitos-em-combinacao.md#receita-2-bateria-com-compressor-paralelo-em-barramento) · [06d Compressor](../manual/06d-efeitos-referencia.md#2-compressor) |
| Fazer ecos presos ao andamento (ping-pong, pontilhado) | [Efeitos em combinação, receita 4](efeitos-em-combinacao.md#receita-4-delay-em-ping-pong-sincronizado-ao-andamento) · [06d Delay](../manual/06d-efeitos-referencia.md#7-delay) |
| Fazer um pad largo sem embolar os graves | [Efeitos em combinação, receita 5](efeitos-em-combinacao.md#receita-5-pad-largo-com-chorus-e-reverb) · [04a Sintetizador](../manual/04a-sintetizador.md) |
| Fazer um baixo com dentes e mordida | [Efeitos em combinação, receita 6](efeitos-em-combinacao.md#receita-6-distorção-de-baixo-com-filtro-e-eq) · [06d Distorção](../manual/06d-efeitos-referencia.md#11-distorção-sobreamostragem) |
| Agrupar faixas num barramento (bateria, vozes) | [06 Mixer, saída](../manual/06-mixer.md#saída-e-nome) · [Mixagem e automação, variações](mixagem-e-automacao.md#variações) |
| Ouvir só uma faixa com o reverb dela | [06 Mixer, solo e mudo](../manual/06-mixer.md#solo-e-mudo) |
| Fazer uma subida de filtro até o refrão | [Mixagem e automação, passo 3](mixagem-e-automacao.md#3-automatizar-um-filtro-para-a-subida-da-música) · [07 Automação](../manual/07-automacao.md) |
| Fazer um fade-out da música | [Mixagem e automação, passo 4](mixagem-e-automacao.md#4-fazer-um-fade-de-volume-por-automação) · [07 Automação](../manual/07-automacao.md) |

### Instrumentos e expressão

| Quero… | Leia |
|---|---|
| Tocar um solo expressivo (scoop de bend e vibrato que entra devagar) | [Expressão MIDI, receita 1](expressao-midi-na-pratica.md#receita-1-solo-de-sintetizador-com-scoop-e-vibrato-que-entra) · [04 Painel de instrumento, rodas](../manual/04-painel-de-instrumento.md#rodas-de-pitch-bend-e-de-modulação) |
| Segurar acordes de teclado com o pedal de sustain | [Expressão MIDI, receita 2](expressao-midi-na-pratica.md#receita-2-pedal-de-sustain-em-acordes-de-teclado) · [05 Piano roll, faixa de controle](../manual/05-piano-roll.md#faixa-de-controle) |
| Desenhar uma queda de altura (laser) ou um riser | [Expressão MIDI, receita 3](expressao-midi-na-pratica.md#receita-3-queda-de-altura-desenhada-e-automatizada) |
| Montar um piano com camadas de força do toque | [Sampler multi-zona, receita 1](sampler-multi-zona-e-fatiar-loops.md#receita-1-piano-multi-sample-com-camadas-de-velocidade) · [04c Sampler](../manual/04c-sampler.md) |
| Fazer um kit de bateria a partir de um loop | [Sampler multi-zona, receita 2](sampler-multi-zona-e-fatiar-loops.md#receita-2-kit-de-bateria-a-partir-de-um-loop-fatiado) · [04c Fatiar sample](../manual/04c-sampler.md#fatiar-sample) |
| Repetir um golpe sem efeito de metralhadora (round-robin) | [Sampler multi-zona, receita 3](sampler-multi-zona-e-fatiar-loops.md#receita-3-round-robin-para-o-mesmo-golpe-não-soar-mecânico) · [04c Round-robin](../manual/04c-sampler.md#round-robin) |
| Sustentar uma nota curta de sample além do arquivo | [04c, sustentar uma nota curta com loop](../manual/04c-sampler.md#sustentar-uma-nota-curta-com-loop) · [04c Loop da zona](../manual/04c-sampler.md#loop-da-zona) |
| Criar sino, baixo, pad, lead ou coro com FM e wavetable | [FM e wavetable na prática](fm-e-wavetable-na-pratica.md) · [04d FM](../manual/04d-fm.md) · [04e Wavetable](../manual/04e-wavetable.md) |
| Fazer o timbre mudar durante a música (morfar) | [FM e wavetable, automatizando a posição](fm-e-wavetable-na-pratica.md#automatizando-a-posição-da-wavetable) · [07 Automação](../manual/07-automacao.md) |

### Áudio: warp, altura e remix

| Quero… | Leia |
|---|---|
| Esticar um loop para o andamento do projeto | [Remix, passo 3](remix-com-warp-e-altura.md#3-detectar-o-andamento-e-esticar) · [03b Warp e altura](../manual/03b-warp-e-altura.md) |
| Transpor um sample sem mudar a duração | [Remix, passo 6](remix-com-warp-e-altura.md#6-transpor-o-tom) · [03b Warp e altura, seção `ALTURA`](../manual/03b-warp-e-altura.md) |
| Tocar um trecho de trás para frente (subida de prato antes da virada) | [Remix, passo 7](remix-com-warp-e-altura.md#7-reverso-como-efeito-subida-antes-da-virada) |
| Fazer um remix por cima de outra música | [Remix com warp e altura](remix-com-warp-e-altura.md) · [03 Áudio e clipes](../manual/03-audio-e-clipes.md) |

### Entrega: exportar e volume

| Quero… | Leia |
|---|---|
| Deixar a música tão alta quanto o Spotify (−14 LUFS) sem estourar | [Loudness e master](loudness-e-master.md) · [08 Exportação, Normalizar o loudness](../manual/08-exportacao.md#normalizar-o-loudness) |
| Medir o volume percebido (LUFS) e o true peak | [06b Medidor de loudness](../manual/06b-analisador-e-medidores.md#medidor-de-loudness-do-master-m-s-i-tp) · [Loudness e master, passo 2](loudness-e-master.md#2-medir-o-ponto-de-partida) |
| Entregar para podcast (−16) ou rádio e TV (−23) | [Loudness e master, variações](loudness-e-master.md#variações) · [08 Exportação](../manual/08-exportacao.md) |
| Exportar stems para outro programa | [08 Exportação, Stems](../manual/08-exportacao.md#stems) · [Gravar uma banda e mixar, passo 9](gravar-uma-banda-e-mixar.md#9-exportar-a-mixagem-e-os-stems) |
| Exportar só um trecho para testar | [08 Exportação, passo a passo](../manual/08-exportacao.md#passo-a-passo) |
| Aliviar um sintetizador pesado (congelar em áudio) | [08 Exportação, congelar uma faixa](../manual/08-exportacao.md#congelar-uma-faixa) |

### Projeto, aparelhos e conta

| Quero… | Leia |
|---|---|
| Levar o projeto para o celular | [Trabalhar em dois aparelhos](trabalhar-em-dois-aparelhos.md) · [Backup, passo 2](backup-e-levar-projeto-para-outro-aparelho.md#2-migrar-do-computador-para-o-celular-sem-depender-da-nuvem) · [01b Nuvem](../manual/01b-nuvem-e-sincronizacao.md) |
| Fazer backup do projeto | [Backup, passo 1](backup-e-levar-projeto-para-outro-aparelho.md#1-backup-periódico) · [01 Projeto em arquivo](../manual/01-projetos-modelos-conta.md#projeto-em-arquivo-jopendaw) |
| Mandar o projeto para um colaborador | [Backup, passo 3](backup-e-levar-projeto-para-outro-aparelho.md#3-mandar-o-projeto-para-um-colaborador) |
| Resolver o conflito "O projeto mudou em outro aparelho" | [Trabalhar em dois aparelhos, passo 5](trabalhar-em-dois-aparelhos.md#5-resolver-um-conflito) · [01b Diálogo de conflito](../manual/01b-nuvem-e-sincronizacao.md) |
| Trabalhar sem internet | [Trabalhar em dois aparelhos, passo 6](trabalhar-em-dois-aparelhos.md#6-sem-internet) |
| Liberar cota de armazenamento (4 GB) | [01 Armazenamento de áudios](../manual/01-projetos-modelos-conta.md#armazenamento-de-áudios-na-tela-conta) · [Trabalhar em dois aparelhos, passo 7](trabalhar-em-dois-aparelhos.md#7-cota-de-armazenamento) · [01b Cotas](../manual/01b-nuvem-e-sincronizacao.md#cotas-e-limites) |
| Trabalhar sem tirar as mãos do teclado | [Atalhos e fluxo rápido](atalhos-e-fluxo-rapido.md) · [09 Atalhos](../manual/09-configuracoes-atalhos-android.md) |
| Configurar microfone, MIDI e permissões, ou instalar no Android | [09 Configurações, atalhos e Android](../manual/09-configuracoes-atalhos-android.md) |

---

## 2. Matriz recurso × recurso

Cada célula tem uma frase do resultado, os parâmetros de partida e o link. Célula em branco: sem combinação útil registrada.

### 2.1 Instrumentos × efeitos

As linhas são os cinco instrumentos; as colunas, os doze efeitos, repartidos em quatro tabelas de três. Um efeito de faixa processa **a faixa inteira**: numa faixa `Bateria` as 12 peças passam juntas, e numa faixa `Sampler` todas as zonas.

**Timbre e dinâmica: `EQ`, `Compressor`, `Gate`**

| Instrumento | `EQ` | `Compressor` | `Gate` |
|---|---|---|---|
| **Sintetizador** | Tira o subgrave que `Sub` e uníssono acumulam: banda 1 `Passa-alta` 150 Hz, 24 dB/oit no pad ([receita 5](efeitos-em-combinacao.md#receita-5-pad-largo-com-chorus-e-reverb)); 40 Hz num baixo antes da distorção ([receita 6](efeitos-em-combinacao.md#receita-6-distorção-de-baixo-com-filtro-e-eq)) | Baixo: nível constante antes da distorção, preset `Baixo` (−22 dB, 5:1, 3 ms, 120 ms, `Ganho` +5 dB) ([receita 6](efeitos-em-combinacao.md#receita-6-distorção-de-baixo-com-filtro-e-eq)). Pad ou baixo com `Sidechain` no bumbo ([receita 3](efeitos-em-combinacao.md#receita-3-sidechain-pumping-com-o-bumbo)) | Portão rítmico num pad: `Sidechain` no chimbal, `Alcance` −80 dB, `Retenção` 50 ms, `Soltura` 100 ms ([06d Gate](../manual/06d-efeitos-referencia.md#3-gate)) |
| **Bateria** | Só o bumbo: numa segunda faixa `Bateria` com só as notas do bumbo (outras peças com `Volume` 0%), preset `Bumbo` ([04b](../manual/04b-bateria.md), [06d EQ](../manual/06d-efeitos-referencia.md#1-eq-8-bandas)). Na cópia paralela, preset `Brilho` depois do compressor ([receita 2](efeitos-em-combinacao.md#receita-2-bateria-com-compressor-paralelo-em-barramento)) | Cola do conjunto: `Bateria cola` (−16 dB, 2:1, 30 ms, 200 ms). Peso: `Paralelo pesado` num barramento, `Mistura` 100% ([receita 2](efeitos-em-combinacao.md#receita-2-bateria-com-compressor-paralelo-em-barramento)) | |
| **Sampler** (zonas) | Piano: banda 1 `Passa-alta` 40 Hz, `Inclinação` 12 dB/oit, tira o rumor grave das gravações ([sampler, receita 1](sampler-multi-zona-e-fatiar-loops.md#receita-1-piano-multi-sample-com-camadas-de-velocidade)) | Piano: −18 dB, 2:1, 30 ms, 200 ms (suaviza a passagem entre camadas). Fatias: −18 dB, 4:1, 10 ms, 150 ms. Round-robin: −18 dB, 3:1, 8 ms ([sampler](sampler-multi-zona-e-fatiar-loops.md)) | |
| **FM** | | Baixo FM: se precisar segurar picos, `Compressor` no padrão (−18 dB, 4:1) ([FM e wavetable](fm-e-wavetable-na-pratica.md#combinando-com-efeitos)). Com `Sidechain` no bumbo vale como em qualquer faixa (dedução) | |
| **Wavetable** | | Pad ou baixo com `Sidechain` no bumbo: o efeito age na faixa, qualquer que seja o instrumento (dedução de [receita 3](efeitos-em-combinacao.md#receita-3-sidechain-pumping-com-o-bumbo)) | |

**Dinâmica e timbre: `Limitador`, `Utilitário`, `Filtro`**

| Instrumento | `Limitador` | `Utilitário` | `Filtro` |
|---|---|---|---|
| **Sintetizador** | | Baixo em mono: `Mono` `Sim` ([06d Utilitário](../manual/06d-efeitos-referencia.md#5-utilitário)). Pad: `Largura` 130% no fim da cadeia, conferindo o mono ([receita 5](efeitos-em-combinacao.md#receita-5-pad-largo-com-chorus-e-reverb)) | Baixo com wobble: preset `Wobble 1/8` (`Nota` `1/8`). Mordida no ataque: `Envelope` +2,5 oit com `Corte` 600 Hz ([receita 6](efeitos-em-combinacao.md#receita-6-distorção-de-baixo-com-filtro-e-eq)) |
| **Bateria** | Amaciar picos do barramento do grupo: `Ganho` +4 dB, `Teto` −3 dB, `Soltura` 80 ms, `Lookahead` 3 ms ([06d Limitador](../manual/06d-efeitos-referencia.md#4-limitador)) | | Build-up: `Passa-alta de transição` na mistura ou num barramento, `Corte` automatizado de 250 Hz a 2 kHz nos 4 compassos antes do refrão ([06d Filtro](../manual/06d-efeitos-referencia.md#12-filtro)) |
| **Sampler** (zonas) | | | Kit de fatias: `Passa-baixa 24`, `Corte` 20 kHz automatizado até 800 Hz em 4 compassos. Piano que respira: automatizar `Corte` nos refrões ([sampler](sampler-multi-zona-e-fatiar-loops.md)) |
| **FM** | | | O FM não tem filtro interno ([04d](../manual/04d-fm.md)); o efeito `Filtro` cobre a varredura de `Corte` (dedução, sem receita testada) |
| **Wavetable** | | | |

**Espaço e modulação: `Reverb`, `Delay`, `Chorus` (chorus e flanger)**

| Instrumento | `Reverb` | `Delay` | `Chorus` |
|---|---|---|---|
| **Sintetizador** | Pad: `Salão` (`Mistura` 28%, `Pré-atraso` 30 ms, `Decaimento` 2,8 s) com `Cortar graves` 200 Hz, ou retorno com `Mistura` 100% e envio em −9 dB ([receita 5](efeitos-em-combinacao.md#receita-5-pad-largo-com-chorus-e-reverb)). Lead: `Sala` (`Mistura` 22%) | Lead com scoop: `Nota` `1/8D`, `Mistura` 25%, `Realimentação` 35%; os ecos repetem o bend e o vibrato ([expressão, receita 1](expressao-midi-na-pratica.md#receita-1-solo-de-sintetizador-com-scoop-e-vibrato-que-entra)) | Pad: `Ensemble` com `Mistura` 40% **antes** da reverb ([receita 5](efeitos-em-combinacao.md#receita-5-pad-largo-com-chorus-e-reverb)). Supersaw e pads pedem chorus e reverb ([04a](../manual/04a-sintetizador.md)). Transição: `Flanger jato` com `Mistura` automatizada de 0 a 50% ([06d Chorus](../manual/06d-efeitos-referencia.md#8-chorus-chorus-e-flanger)) |
| **Bateria** | Retorno com `Sala` ou `Placa` e `Mistura` 100%; o modelo manda a `Bateria` com 0,12 (cerca de −18,4 dB). Reverb só em caixa e palmas pede outra faixa `Bateria`, porque o envio é da faixa inteira ([04b](../manual/04b-bateria.md), [01 modelo](../manual/01-projetos-modelos-conta.md#batida-eletrônica)) | | `Flanger jato` num build-up, `Mistura` de 0 a 50% ([06d Chorus](../manual/06d-efeitos-referencia.md#8-chorus-chorus-e-flanger)) |
| **Sampler** (zonas) | Piano: `Mistura` 20%, `Decaimento` 2,2 s, `Cortar graves` 120 Hz. Fatias: `Mistura` 12%, `Decaimento` 1,2 s, `Pré-atraso` 20 ms. Round-robin: `Mistura` 10%, `Decaimento` 0,8 s ([sampler](sampler-multi-zona-e-fatiar-loops.md)) | | |
| **FM** | Sino e som metálico: `Placa` ou `Catedral` ([FM e wavetable](fm-e-wavetable-na-pratica.md#combinando-com-efeitos)) | Lead: `Delay` funciona bem ([04d](../manual/04d-fm.md)) | Sino: `Chorus leve` abre o estéreo, já que o FM sai em mono ([FM e wavetable](fm-e-wavetable-na-pratica.md#combinando-com-efeitos)); `Ensemble` também é citado no [04d](../manual/04d-fm.md) |
| **Wavetable** | Pad morfante: `Salão` (`Mistura` 28%, 2,8 s). Coro: `Catedral` (7 s) ou `Salão` | Lead PWM: `1/8 pontilhado` (`Ducking` 30%). Queda de altura: `Nota` `1/8D`, `Realimentação` 45%, `Passa-baixa` 3 kHz, `Mistura` 30% ([expressão, receita 3](expressao-midi-na-pratica.md#receita-3-queda-de-altura-desenhada-e-automatizada)) | Pad: `Ensemble` com `Mistura` reduzida a 25 a 30% (o pad já tem uníssono). Coro: `Ensemble` para vários cantores |

**Modulação e saturação: `Phaser`, `Tremolo`, `Distorção`**

| Instrumento | `Phaser` | `Tremolo` | `Distorção` |
|---|---|---|---|
| **Sintetizador** | Teclas: `Lento` com `Mistura` 40%. Pad: `Profundo (12 estágios)` antes da reverb, ou entre `Chorus` e `EQ` com `Mistura` 30% ([06d Phaser](../manual/06d-efeitos-referencia.md#9-phaser), [receita 5](efeitos-em-combinacao.md#receita-5-pad-largo-com-chorus-e-reverb)) | Pad: `Autopan 1/4` (`Nota` `1/2` para mais lento). Acorde sustentado: `Picotado 1/16` ([06d Tremolo](../manual/06d-efeitos-referencia.md#10-tremolo)) | Baixo: `Válvula quente` com `Drive` 18 dB, `Mistura` 55%, `Tom` 5 kHz ([receita 6](efeitos-em-combinacao.md#receita-6-distorção-de-baixo-com-filtro-e-eq)) |
| **Bateria** | | Percussão: `Autopan 1/4` ([06d Tremolo](../manual/06d-efeitos-referencia.md#10-tremolo)) | Barramento de bateria: `Lo-fi 8 bits` com `Mistura` 40% ([06d Distorção](../manual/06d-efeitos-referencia.md#11-distorção-sobreamostragem)). Na cópia paralela: `Fita`, `Drive` 6 dB ([receita 2](efeitos-em-combinacao.md#receita-2-bateria-com-compressor-paralelo-em-barramento)) |
| **Sampler** (zonas) | | | |
| **FM** | | | Som metálico: `Tipo` `Dobra`, `Mistura` 25% ([FM e wavetable](fm-e-wavetable-na-pratica.md#combinando-com-efeitos)) |
| **Wavetable** | | | |

### 2.2 Instrumentos × automação

A raia de automação abre pelo botão `A` da faixa ([07 Automação](../manual/07-automacao.md)). Tocando, o knob segue a curva em laranja; parado, vale o valor fixo.

| Instrumento | `Volume` e `Pan` da faixa | Parâmetro do próprio instrumento | Parâmetro de um efeito da cadeia |
|---|---|---|---|
| **Sintetizador** | Fade só desta faixa ou do grupo pela raia `Volume` dela ([mixagem, passo 4](mixagem-e-automacao.md#4-fazer-um-fade-de-volume-por-automação)) | `Corte` e `Ressonância` (subida: `Ressonância` de 20% a 45%); `Vibrato` ([04a](../manual/04a-sintetizador.md), [mixagem, passo 3](mixagem-e-automacao.md#3-automatizar-um-filtro-para-a-subida-da-música)) | `Chorus` `Mistura` de 0 a 40% na entrada do pad ([receita 5](efeitos-em-combinacao.md#receita-5-pad-largo-com-chorus-e-reverb)); `Filtro` `Corte` |
| **Bateria** | | `Volume` de cada peça vale na hora; `Afinação`, `Decaimento` e `Timbre` só valem no **próximo golpe** ([04b](../manual/04b-bateria.md)) | `Flanger jato`: `Mistura` de 0 a 50% no build-up; `Filtro` `Corte` no barramento do grupo ([06d](../manual/06d-efeitos-referencia.md)) |
| **Sampler** (zonas) | Crescendo na frase pela raia `Volume` ([sampler, receita 3](sampler-multi-zona-e-fatiar-loops.md#receita-3-round-robin-para-o-mesmo-golpe-não-soar-mecânico)) | `Volume`, `Afinação` e o envelope. `Afinação` de 0 a −100 ct dá um efeito de fita desacelerando, discreto (o rótulo exato do menu é `(não confirmado)`). Ganho, pan, faixas e loop de cada zona **não** são automatizáveis ([04c](../manual/04c-sampler.md)) | `Filtro` `Corte` de 20 kHz a 800 Hz em 4 compassos ([sampler, receita 2](sampler-multi-zona-e-fatiar-loops.md#receita-2-kit-de-bateria-a-partir-de-um-loop-fatiado)) |
| **FM** | | `Nível` de um modulador abre e fecha o brilho no tempo; `Realimentação` também. Automatizar o `Nível` durante uma queda de altura faz o timbre "morrer" ([04d](../manual/04d-fm.md), [expressão, receita 3](expressao-midi-na-pratica.md#receita-3-queda-de-altura-desenhada-e-automatizada)) | |
| **Wavetable** | | `Posição` de cada oscilador (por exemplo 0% no compasso 1 a 100% no compasso 9); `Corte`; `Nível` do `Oscilador 2` para fazer entrar uma camada. Junto da queda de altura: `Corte` de 5,50 kHz a 800 Hz ([FM e wavetable](fm-e-wavetable-na-pratica.md#automatizando-a-posição-da-wavetable)) | |

### 2.3 Efeitos × automação

Todo parâmetro de efeito é automatizável, **menos** o `Sidechain` ([07 Automação](../manual/07-automacao.md)). Só há linha para os efeitos com uso registrado; os demais (`EQ`, `Compressor`, `Gate`, `Limitador`, `Utilitário`, `Delay`, `Phaser`, `Tremolo`, `Distorção`) não têm receita de automação nos capítulos.

| Efeito | Parâmetro | Resultado e valores de partida |
|---|---|---|
| `Filtro` | `Corte` | Subida de 8 compassos: `Passa-alta de transição`, `Corte` de 60 Hz a 3 kHz (cerca de 0,7 oitava por compasso na escala do knob); ou `Passa-baixa 24` de 300 Hz a 12 kHz para "abrir". Antes do primeiro ponto vale o valor do primeiro ponto ([mixagem, passo 3](mixagem-e-automacao.md#3-automatizar-um-filtro-para-a-subida-da-música)) |
| `Filtro` | `Ressonância` | De 20% no começo a 45% no fim: o assobio da subida |
| `Chorus` | `Mistura` | De 0 a 40% na entrada do pad; de 0 a 50% no `Flanger jato` durante um build-up ([06d Chorus](../manual/06d-efeitos-referencia.md#8-chorus-chorus-e-flanger)) |
| `Reverb` | `Mistura` | Mistura de reverb subindo ao longo da música ([06c](../manual/06c-painel-de-efeitos.md)); no retorno de barramento a `Mistura` fica em 100% e o que anda é o envio |

### 2.4 Automação de volume, pan e envio × mixer, exportação e barramentos

| Alvo | Mixer | Exportar e congelar | Barramentos e mover faixas |
|---|---|---|---|
| **`Volume` da faixa** | Fader e leitura em dB andam em laranja; arrastar o fader muda só o valor fixo, sem efeito enquanto a curva toca ([06](../manual/06-mixer.md), [07](../manual/07-automacao.md)). O desenho segue a curva do fader: uma reta na tela é um fade parelho (−7,5 dB, −18 dB e −36 dB em 25%, 50% e 75%) | Entra no arquivo. Ao congelar, o volume e o pan **com as automações deles** passam para a faixa nova; a automação de instrumento e de efeito vira som ([08](../manual/08-exportacao.md#congelar-uma-faixa)) | Raia de volume no barramento do grupo faz o fade só do grupo |
| **`Volume` do master** | Fader do master anda em laranja | Fade-out em 4 compassos: ponto em 0 dB no compasso 33 e em −∞ dB no 37, com a grade em `Compasso`; o `Compressor` do master não desfaz o fade ([mixagem, passo 4](mixagem-e-automacao.md#4-fazer-um-fade-de-volume-por-automação)) | |
| **`Pan`** | O `Pan` do master é balanço (o centro fica em 0 dB); o da faixa tem lei de potência constante, com −3 dB no centro ([06](../manual/06-mixer.md)) | Vai para a faixa nova ao congelar | |
| **Nível de `Envio`** | O knob de envio do mixer **não** anda com a automação; quem mostra o valor é a raia | Vai para a faixa nova ao congelar (com os envios pós-fader) | Remover o envio ou o barramento apaga a raia; mover faixa contra a ordem dos barramentos desfaz o envio e a automação dele, depois de perguntar ([06](../manual/06-mixer.md#como-o-som-corre-ordem-de-processamento)) |

### 2.5 Instrumentos × ferramentas MIDI

Ferramentas do menu `Ferramentas` do editor de notas ([05b](../manual/05b-ferramentas-midi.md)). Sem seleção, agem em todas as notas do clipe.

| Instrumento | Escala e acordes | Arpejador | `Humanizar` e `Quantizar` | `Legato`, `Staccato…` e `Escalar o tempo` |
|---|---|---|---|---|
| **Sintetizador, FM e Wavetable** (faixas melódicas) | `Escala…` com `Prender na escala` e `Acorde no clique` em `Diatônico: tríade`, `Nota: 1/1` ([melodia, passo 1](melodia-e-harmonia-com-as-ferramentas.md#1-a-progressão-c-am-f-g-um-compasso-cada)) | Acordes: `Subir e descer`, `1/8`, 1 oitava, `Gate` 90%. Baixo a partir de uma nota só: `Subir`, `1/8`, 2 oitavas, `Gate` 60% ([melodia, passos 2 e 4](melodia-e-harmonia-com-as-ferramentas.md#2-virar-arpejo)) | `Humanizar…` `Tempo` 30%, `Velocidade` 40%; depois `Quantizar` com `Força` 50% e a grade em `1/8` ([melodia, passo 3](melodia-e-harmonia-com-as-ferramentas.md#3-humanizar-e-quantizar)) | `Staccato…` `Duração` 50% deixa o baixo seco; `Legato` (`Shift+L`) cola as notas. `Escalar o tempo` ×0,5 dobra a velocidade da progressão; ×2 faz o clipe crescer sozinho |
| **Sampler** (áudio único ou zonas) | `Acorde no clique` com zonas em camadas: cada nota dispara todas as zonas que a contêm, então 3 camadas por nota gastam 3 das 16 vozes ([04c](../manual/04c-sampler.md)) | | `Humanizar…` (`Tempo` 15 a 20%, `Velocidade` 20 a 25%) varia a camada de velocidade e o round-robin, e isso é o efeito desejado. `Rampa de velocidade` (por exemplo de 40 a 115) passeia pelas camadas ([sampler](sampler-multi-zona-e-fatiar-loops.md)) | `Legato` e `Staccato…` não mudam zonas `Até o fim` e fatias. `Inverter na altura` e `Reverter a ordem das notas` trocam **quais** fatias tocam ([sampler, receita 2](sampler-multi-zona-e-fatiar-loops.md#receita-2-kit-de-bateria-a-partir-de-um-loop-fatiado)) |
| **Bateria** | | Existe, mas arpejar peças raramente faz sentido musical ([05b](../manual/05b-ferramentas-midi.md)) | Depois de tocar nas teclas: `Ctrl+A`, `Q` com a grade `1/16` e `Força` 100% ([gravar uma banda, passo 4](gravar-uma-banda-e-mixar.md#4-bateria-tocada-nas-teclas-camada-por-camada-overdub-midi)). Notas fantasma: velocidade de 25 a 40% no painel `Vel.` ([04b](../manual/04b-bateria.md)) | `Escalar o tempo` muda o ritmo. `Legato` e `Staccato…` não mudam o som: a peça toca até o fim, com nota curta ou longa (dedução de [04b](../manual/04b-bateria.md)) |

A `Bateria` não tem o botão `Escala`, nem acordes, nem `Inverter na altura` ([05b](../manual/05b-ferramentas-midi.md)); por isso a célula de escala fica em branco.

### 2.6 Instrumentos × expressão MIDI

Pitch bend, roda de modulação e pedal (`CC 64`), desenhados na faixa de controle do editor ([05](../manual/05-piano-roll.md#faixa-de-controle)) ou gravados ao vivo ([03c](../manual/03c-gravacao.md)). O `Alcance do bend` (0 a 24 st, padrão 2) fica no cartão `GERAL`.

| Instrumento | Pitch bend | Modulação (vibrato da roda) | Pedal de sustain | Gravar ao vivo |
|---|---|---|---|---|
| **Sintetizador** | `Lead serra`, `Alcance do bend` 2 st: scoop com a grade em `1/32`, do fundo (−2,00 st) ao meio em meio tempo ([receita 1](expressao-midi-na-pratica.md#receita-1-solo-de-sintetizador-com-scoop-e-vibrato-que-entra)) | `Vibrato da roda` 0 a 2 st (padrão 1): use 0,5 st e leve a modulação de 0% a cerca de 60% em um tempo ([receita 1](expressao-midi-na-pratica.md#receita-1-solo-de-sintetizador-com-scoop-e-vibrato-que-entra)) | `Teclado (EP)` com `Vozes` 8 ou mais; pintar um trecho de `Sustain` por acorde, a subida um quarto de tempo antes do acorde seguinte ([receita 2](expressao-midi-na-pratica.md#receita-2-pedal-de-sustain-em-acordes-de-teclado)) | Teclado MIDI, faixa armada, `Alcance` 2 st e `Vibrato da roda` 0,5 st ([receita 4](expressao-midi-na-pratica.md#receita-4-gravar-com-um-teclado-midi-de-verdade)) |
| **FM** | O bend afina os quatro operadores juntos e o timbre se mantém `(não confirmado ao ouvido)`. `Lead FM` com `Alcance do bend` 24 st cai duas oitavas do mesmo jeito ([receita 3](expressao-midi-na-pratica.md#receita-3-queda-de-altura-desenhada-e-automatizada)) | `Lead FM` com `Vibrato da roda` 0,4 st, porque o preset já traz `Vibrato` de LFO (0,25 st) | `Sino elétrico` com pedal: as solturas longas do preset já misturam as notas; encurte o trecho do pedal | Igual ao sintetizador |
| **Wavetable** | `Lead PWM`: o bend não mexe na `Posição`, o PWM segue igual enquanto a nota sobe. Com `Alcance do bend` 24 st, reta do meio ao fundo em 3 tempos: queda de duas oitavas, com `Corte` automatizado de 5,50 kHz a 800 Hz ([receita 3](expressao-midi-na-pratica.md#receita-3-queda-de-altura-desenhada-e-automatizada)) | Mesmo knob `Vibrato da roda` (0 a 2 st) | `Teclas de cristal` com o mesmo pedal ([receita 2](expressao-midi-na-pratica.md#receita-2-pedal-de-sustain-em-acordes-de-teclado)) | Igual ao sintetizador |
| **Sampler** | Vale, com o mesmo `Alcance do bend` (0 a 24 st) | Vale, mas o vibrato tem profundidade fixa de 1 st (sem knob) ([04](../manual/04-painel-de-instrumento.md#alcance-do-bend-e-vibrato-da-roda-por-instrumento)) | Vale: piano em zonas com pedal ([receita 2](expressao-midi-na-pratica.md#receita-2-pedal-de-sustain-em-acordes-de-teclado)) | Igual ao sintetizador |
| **Bateria** | | | | |

A `Bateria` ignora bend, roda e pedal: a faixa de controle aceita pontos, mas nada muda no som ([05](../manual/05-piano-roll.md), [04b](../manual/04b-bateria.md)).

### 2.7 Warp e altura × outros recursos

Menu do clipe de áudio, `Warp e altura…` ([03b](../manual/03b-warp-e-altura.md)). O áudio original nunca é alterado; o que o warp gera é um derivado guardado só no aparelho.

| Função | Cortar, fades e `Ganho do clipe…` | `Converter em notas (MIDI)` | Efeitos, sidechain e batida por cima | Exportar, congelar e nuvem |
|---|---|---|---|---|
| **Esticar ao andamento** (`Detectar`, `Ajustar ao andamento`, `÷2`, `×2`) | Cortes e fades acompanham a escala do esticamento. Cada pedaço cortado mantém o warp e pode ganhar o próprio `BPM do áudio` quando o andamento oscila ([remix, passo 4](remix-com-warp-e-altura.md#4-alinhar-a-primeira-batida-e-conferir-o-fim)). O `Ganho do clipe…` é independente do warp | As notas seguem o `BPM do áudio` do clipe e ficam alinhadas; são gravadas na hora, então mudar o warp depois não as move: converta de novo ([03d](../manual/03d-audio-para-midi.md)) | O clipe esticado passa pela cadeia da faixa. Para a música respirar com o bumbo: `Compressor` na faixa com `Sidechain` numa faixa `Bateria` só de bumbo. Bateria MIDI escrita em batidas acompanha o andamento sozinha ([remix, passo 8](remix-com-warp-e-altura.md#8-sobrepor-uma-batida)) | Exportar e congelar esperam o `Processando o warp…`: o que soa é o que exporta. O derivado não sobe à nuvem; cada aparelho refaz o seu ([08](../manual/08-exportacao.md), [01b](../manual/01b-nuvem-e-sincronizacao.md)) |
| **Transpor** (`ALTURA`, ±24 st) | Vale sobre o som já processado; não muda a duração | A transposição do clipe soma à altura das notas | Sample transposto (por exemplo `+5 st`) sob a batida dá um segundo tom sem gravar nada ([remix, variações](remix-com-warp-e-altura.md#variações)) | Igual ao esticar; juntos, o `processando…` demora mais |
| **Inverter o áudio** | O fade in fica no começo do clipe (o que se ouve primeiro) e o fade out no fim, mesmo invertido ([remix, passo 7](remix-com-warp-e-altura.md#7-reverso-como-efeito-subida-antes-da-virada)) | As notas saem espelhadas dentro da janela do clipe | Cauda de prato invertida cresce até a virada: cópia da faixa, um compasso, clipe terminando no compasso 33 | Reverso puro fica pronto quase na hora, sem esticamento |

Para esticar ou transpor **sem** mudar a duração use um clipe de áudio, não o `Sampler`: no sampler altura e duração andam juntas ([04c](../manual/04c-sampler.md)).

### 2.8 Efeitos × barramentos, envios e sidechain

`Sidechain` só existe no `Compressor` e no `Gate` ([06 Mixer, sidechain](../manual/06-mixer.md#sidechain-de-onde-vem-a-fonte)). No retorno de um barramento os efeitos de espaço ficam com `Mistura` em **100%**: o seco vai pela faixa, o molhado pelo barramento.

| Efeito | Insert na faixa | Retorno (barramento com envios) | Grupo ou master | Sidechain |
|---|---|---|---|---|
| `EQ` | Voz: `Voz presente`. Limpeza geral: `Corte de graves` ([06d EQ](../manual/06d-efeitos-referencia.md#1-eq-8-bandas)) | Na cópia esmagada, depois do compressor paralelo: `Brilho` | Master: `EQ` leve, o começo sugerido pelo próprio app com `Compressor` e `Limitador` ([06](../manual/06-mixer.md)) | |
| `Compressor` | Voz: `Voz`. Baixo: `Baixo`. Cola: `Bateria cola` | Bateria em paralelo: `Paralelo pesado` com `Mistura` 100%, envio 0 dB pós-fader | Grupo de bateria: `Compressor` no barramento. Master: `Razão` 2:1 a 3:1, `Ataque` 30 ms, `Soltura` 200 ms, 2 a 3 dB de redução | Bumbo → pad ou baixo: `Detector` `Pico`, `Passa-alta` 20 Hz, `Razão` 8:1, `Ataque` 1 ms, `Soltura` de `0,4 × 60 ÷ BPM` s ([receita 3](efeitos-em-combinacao.md#receita-3-sidechain-pumping-com-o-bumbo)). Ducking do reverb: `Compressor` depois do `Reverb` com `Sidechain` na voz, −30 dB, 4:1, 10 ms, 300 ms ([mixagem, passo 2](mixagem-e-automacao.md#2-criar-um-barramento-de-reverb-compartilhado)) |
| `Gate` | Voz: `Ruído de fundo` | | | Pad ou faixa rítmica com `Sidechain` no chimbal: `Alcance` −80 dB, `Retenção` 50 ms |
| `Limitador` | Atrasa a faixa pelo `Lookahead` (ver [parte 3](#3-combinações-que-atrapalham)) | Barramento de bateria: `Ganho` +4 dB, `Teto` −3 dB | Último efeito do master: `Master −1 dB` (`Ganho` +3 dB, `Teto` −1 dB, `Soltura` 80 ms, `Lookahead` 5 ms) | |
| `Utilitário` | Baixo: `Mono` `Sim` | | Master ou mistura: preset `Mono` para conferir a compatibilidade mono | |
| `Reverb` | Só com `Mistura` até cerca de 30%; acima empasta ([06d Reverb](../manual/06d-efeitos-referencia.md#6-reverb-fdn)) | O caminho normal: `Placa` ou `Sala`, `Mistura` 100%, `Pré-atraso` 20 ms, `Cortar graves` 200 Hz; envios de −18 dB (fundo) a −14 dB (voz); bumbo e baixo sem envio | | |
| `Delay` | `Ping-pong 1/4` na faixa | `Mistura` 100%, `1/8 pontilhado` com `Ducking` 30%, envio em −18 dB. Para o delay alimentar o reverb, ele precisa ficar **acima** dele na lista ([mixagem, variações](mixagem-e-automacao.md#variações)) | | |
| `Chorus` | Pad: `Ensemble`, `Mistura` 40% | | | |
| `Phaser` | Teclas e pad | | | |
| `Tremolo` | Autopan e picotado | | | |
| `Distorção` | Baixo: `Válvula quente`, `Mistura` 55% | Cópia paralela: `Fita` com `Mistura` 100%, que atrasa 0,67 ms | Barramento de bateria: `Lo-fi 8 bits`, `Mistura` 40% | |
| `Filtro` | Baixo: `Wobble 1/8` | | Subida na mistura inteira: o mesmo efeito no canal `Master` ([mixagem, variações](mixagem-e-automacao.md#variações)) | |

### 2.9 Barramentos, envios e sidechain × exportação e congelar

| Recurso do mixer | Stems | Congelar em áudio |
|---|---|---|
| **Retorno de reverb ou delay** (barramento com envios) | O barramento gera o próprio stem, com o que recebeu; a voz sai **seca**, sem o reverb dela. A soma dos stems não é igual à mixagem ([08 Stems](../manual/08-exportacao.md#stems)) | Barramento não congela (`Barramento não tem som próprio`); para fixá-lo, exporte a faixa como stem |
| **Grupo** (saída de várias faixas para um barramento) | O grupo é um stem à parte; cada faixa é o stem dela depois do fader, do pan, do mudo e da porta do solo | A faixa nova mantém a saída e os envios da original |
| **Envio pré-fader e pós-fader** | | Os envios **pré-fader** da original saem (senão dobrariam); os pós-fader ficam e calam junto com o mudo |
| **Sidechain** | | Um sidechain que a original alimentava continua funcionando |

### 2.10 Exportação e loudness × master, stems e mix

| Opção da janela `Exportar áudio` | Master e `Limitador` | Stems e barramentos | Trecho, automação, warp e cauda |
|---|---|---|---|
| **`Normalizar o loudness`** (`Streaming −14,0`, `Podcast −16,0`, `Broadcast −23,0`, `Personalizado`; teto −1,0 dBTP) | É só ganho, aplicado **depois** do limitador do master. Chegar ao alvo com o teto de −1 dBTP exige `TP − I` da mixagem de no máximo 13 dB (−14), 15 dB (−16) ou 22 dB (−23); acima disso, `Limitador` no master antes ([loudness, passo 3](loudness-e-master.md#3-ganhar-volume-com-o-limitador-no-master-não-com-o-fader)) | Só mexe nos stems com `Stems com o mesmo ganho`; o teto de true peak vale para a mixagem, não para eles | Mixagem de menos de 400 ms, silêncio ou tudo abaixo de −70 LUFS não é medida: sai sem normalizar (típico de `Região do loop` muito curta) |
| **`Normalizar`** (pico −1 dBFS) | Mexe em cada arquivo à parte; ligar este desliga o de loudness. Uma mixagem que já bate no teto desce cerca de 0,7 dB | Cada stem vai a −1 dBFS separadamente: o equilíbrio entre eles muda | |
| **`Stems`** com **WAV 32 bits float** | A mixagem sai com teto de −0,3 dBFS em qualquer formato; os stems saem sem a cadeia do master e sem o limitador | Para levar a outro programa mantendo o balanço: `Normalizar` desligado e 32 bits float; em 16 e 24 bits o que passa de 0 dB é cortado. Faixa vazia, muda ou calada por solo não gera stem ([gravar uma banda, passo 9](gravar-uma-banda-e-mixar.md#9-exportar-a-mixagem-e-os-stems)) | |
| **`Stems com o mesmo ganho`** (com o loudness ligado) | | Cada stem recebe o mesmo ganho em dB da mixagem e o equilíbrio se mantém; um stem já alto pode passar de 0 dBFS e, em 16 e 24 bits, é cortado: use 32 bits float | |
| **`Região do loop`** | | | Exporta só o trecho marcado, com a `Cauda`; serve para testar |
| **`Cauda`** (0 a 10 s, padrão 2 s) | | Vale também para os stems | Deixa o reverb, o delay e a soltura terminarem; a automação continua valendo nela. Com reverb longo use 4 a 6 s. O fim do arquivo é o último clipe: automação e marcadores depois dele não o estendem |

---

## 3. Combinações que atrapalham

O que evitar juntos, por quê, o que fazer no lugar e onde está registrado. Tudo isso vem das seções "Limites e pegadinhas" dos capítulos e dos guias.

### 3.1 Roteamento, mixer e limites do motor

| Evite juntar | Por quê | Em vez disso | Ver |
|---|---|---|---|
| `Limitador` numa faixa e `Distorção` em outra faixa duplicada | Latência sem compensação: o `Limitador` atrasa só a faixa dele pelo `Lookahead` (3 ms padrão, até 10 ms) e a `Distorção` atrasa a dela por 32 quadros fixos (0,67 ms a 48 kHz). O motor sabe a latência, mas não alinha as faixas | Distorção paralela pelo `Mistura` do próprio efeito, não por duas faixas; `Limitador` no master, onde a latência não importa | [06d, latência](../manual/06d-efeitos-referencia.md#latência-e-custo-de-cada-efeito) · [06 Mixer](../manual/06-mixer.md) |
| Compressão paralela por envio e `Limitador` ou `Distorção` no barramento | A cópia chega atrasada em relação ao seco: som oco, efeito de pente | Só `Compressor` no barramento (não tem latência), ou o `Mistura` do `Compressor` como insert (`Paralelo pesado` com 40%) | [receita 2](efeitos-em-combinacao.md#receita-2-bateria-com-compressor-paralelo-em-barramento) |
| Um 17.º efeito na cadeia ou um 17.º envio na faixa | O motor comporta até **16 efeitos por cadeia** (faixa ou master) e **16 envios por faixa**; o app desabilita `Efeito`/`Adicionar efeito` e o envio, com a dica `Limite de 16 efeitos por faixa` ou `Limite de 16 envios por faixa` `(testado só por testes automáticos)` | Remova um para liberar lugar; consolide em barramentos | [06](../manual/06-mixer.md) · [06c](../manual/06c-painel-de-efeitos.md#limites-e-pegadinhas) |
| Envio ou saída de um barramento para um barramento de **índice menor** (que vem antes na lista) | As faixas comuns são processadas antes de todos os barramentos; um barramento só manda para os que vêm depois dele. O motor ignora o destino inválido e a saída vira o master | Crie primeiro os barramentos que alimentam outros (grupos, delay) e por último o retorno; `Mover para cima` ou `Mover para baixo` acertam a ordem | [06, ordem de processamento](../manual/06-mixer.md#como-o-som-corre-ordem-de-processamento) · [mixagem, variações](mixagem-e-automacao.md#variações) |
| Mover faixas ou barramentos sem olhar os envios | Se a nova ordem quebra uma rota, o app pergunta (`Mover a faixa?`); `Mover mesmo assim` apaga o envio (com a automação dele) ou devolve a saída ao Master `(testado só por testes automáticos)` | `Cancelar`, ou `Ctrl+Z` para trazer tudo de volta | [06](../manual/06-mixer.md#como-o-som-corre-ordem-de-processamento) |
| `Reverb` com `Mistura` 25% (o padrão) num retorno de barramento | Soma seco duplicado: o seco já vai direto da faixa | `Mistura` **100%** no retorno; como insert direto, no máximo cerca de 30% | [mixagem, passo 2](mixagem-e-automacao.md#2-criar-um-barramento-de-reverb-compartilhado) · [06d Reverb](../manual/06d-efeitos-referencia.md#6-reverb-fdn) |
| Bumbo e baixo no envio de reverb | Cauda de grave suja e empasta o mix | Sem envio para eles; `Cortar graves` 200 Hz no reverb | [mixagem, passo 2](mixagem-e-automacao.md#2-criar-um-barramento-de-reverb-compartilhado) · [modelo `Gravação de banda`](../manual/01-projetos-modelos-conta.md#gravação-de-banda) |
| Envio **pós-fader** e faixa muda ou em fade | O reverb some junto com a faixa. O envio **pré-fader** continua soando com a faixa muda ou em fade (etiqueta `PRÉ`) | Escolha conscientemente; `Pré-fader` só para deixar a cauda de uma frase | [06, envios](../manual/06-mixer.md#envios) |
| `S` (solo) numa faixa e esperar ouvir o reverb das outras | O solo corta os envios das faixas que não estão em solo (menos os que vão para um barramento solado) | Desligue o solo para ouvir tudo | [06, solo e mudo](../manual/06-mixer.md#solo-e-mudo) |
| Subir o fader do master para ganhar volume | O fader vem **antes** do limitador de segurança: só empurra o som contra −0,3 dBFS e achata | Fader do master em 0 dB; volume com o efeito `Limitador` no master | [loudness, passo 1](loudness-e-master.md#1-nível-de-cada-faixa-deixe-folga) |
| O limitador de segurança do master como ferramenta de volume | Sempre ligado, sem controles nem medidor de redução; existe só para não haver corte duro | O efeito `Limitador` (você escolhe `Ganho` e `Teto`) | [06, limitador de segurança](../manual/06-mixer.md#o-limitador-de-segurança-do-master) |
| `Pan` `E100` ou `D100` num conteúdo estéreo | O pan da faixa é lei de potência constante por canal: −3 dB no centro, e o extremo descarta o canal oposto em vez de somá-lo | Pan entre `E30` e `E60` (e o espelho) em pares estéreo; extremos só em fontes que já saem iguais nos dois lados. O pan do master é balanço | [06, pegadinhas](../manual/06-mixer.md#limites-e-pegadinhas) |
| `Compressor`: `Ganho` manual e `Ganho automático` ligados juntos | Os dois **somam** no motor | `Ganho` em 0 se quiser só o automático | [06d Compressor](../manual/06d-efeitos-referencia.md#2-compressor) |

### 3.2 Sidechain e medidores

| Evite juntar | Por quê | Em vez disso | Ver |
|---|---|---|---|
| Sidechain com a `Bateria` inteira como chave | A `Bateria` é um instrumento só (12 peças numa faixa): todas as peças disparam o efeito | Bumbo numa faixa própria (uma segunda faixa `Bateria` só com as notas do bumbo) | [receita 3](efeitos-em-combinacao.md#receita-3-sidechain-pumping-com-o-bumbo) · [04b](../manual/04b-bateria.md) |
| Chave circular (A é chave de B e B de A) ou um barramento como chave | Numa chave circular uma delas usa o bloco anterior; um barramento como chave chega com 128 quadros de atraso (cerca de 2,7 ms a 48 kHz) | Faixa normal como chave | [06d, sidechain](../manual/06d-efeitos-referencia.md#o-sidechain-o-que-ele-exige) |
| Esperar que preset, automação ou apagar faixa mantenham o sidechain | Não é automatizável, nenhum preset o altera, e a faixa-chave apagada vira `Faixa N (removida)` com o efeito voltando à própria entrada | Conferir o seletor `Sidechain` depois de mexer nas faixas | [06d](../manual/06d-efeitos-referencia.md#o-sidechain-o-que-ele-exige) · [06c](../manual/06c-painel-de-efeitos.md#limites-e-pegadinhas) |
| Contar com o fader da faixa-chave para mudar o bombeio | Pelo código a chave é lida depois dos efeitos e **antes** do fader, do mudo e do solo; baixar o fader do bumbo não deveria mudar o bombeio `(não confirmado ouvindo)` | Ajustar `Limiar`, não o fader do bumbo | [receita 3](efeitos-em-combinacao.md#receita-3-sidechain-pumping-com-o-bumbo) |
| Vários efeitos de dinâmica e esperar medir todos | O medidor de redução mede **um efeito de dinâmica por vez** (o último em que se tocou) | Tocar no cartão que se quer medir | [06b](../manual/06b-analisador-e-medidores.md) · [06c](../manual/06c-painel-de-efeitos.md) |
| Ler o espectro do `EQ` como o ponto da cadeia | O analisador mostra a saída da faixa depois do fader e de todos os efeitos, não o ponto onde o EQ está | Comparar com o bypass do efeito | [06b, analisador](../manual/06b-analisador-e-medidores.md#analisador-de-espectro) |

### 3.3 Automação

| Evite juntar | Por quê | Em vez disso | Ver |
|---|---|---|---|
| Automação de volume e arrastar o fader durante o play | Arrastar muda só o **valor fixo**, que a curva cobre; nada se ouve até parar | Editar os pontos ou remover a raia (`X` no cabeçalho dela) | [07, limites](../manual/07-automacao.md#limites-e-pegadinhas) · [mixagem, se der errado](mixagem-e-automacao.md#se-der-errado) |
| Esperar a curva com o transporte parado ou tocando notas ao vivo | Parado, o motor não aplica a curva: o som usa o valor fixo. A leitura no cabeçalho da raia mostra o valor da curva no cursor | Tocar o projeto para ouvir | [07](../manual/07-automacao.md#limites-e-pegadinhas) |
| Automação de nível de envio e o knob do mixer | O knob de envio **não** anda com a automação | Ler o valor na raia | [06](../manual/06-mixer.md#limites-e-pegadinhas) |
| Automatizar `Afinação`, `Decaimento` ou `Timbre` de uma peça da `Bateria` | Só valem no próximo golpe (o `Volume` vale na hora) | Automatizar o `Volume` da peça, ou aceitar o golpe seguinte | [04b](../manual/04b-bateria.md#limites-e-pegadinhas) |
| Automatizar ganho, pan, faixas ou loop das zonas do `Sampler` | Não são automatizáveis; só `Volume`, `Afinação` e o envelope | Automatizar os do cartão do instrumento | [04c](../manual/04c-sampler.md#combina-com) |
| `Posição` da wavetable com LFO e envelope no mesmo oscilador | Automação, LFO e envelope **somam** na posição e o resultado é preso entre 0% e 100%, sem dar a volta | `Posição` base afastada das pontas; `Posição` do LFO em 0% quando só a automação deve mandar | [04e](../manual/04e-wavetable.md#limites-e-pegadinhas) · [FM e wavetable](fm-e-wavetable-na-pratica.md#automatizando-a-posição-da-wavetable) |
| Automatizar `Tipo`, `Onda`, `Vozes` (opções e inteiros) | Andam em degraus: o `Tipo` do filtro troca a cada valor inteiro que a curva atravessa | Automatizar `Corte` e `Mistura` | [07](../manual/07-automacao.md#limites-e-pegadinhas) |
| Remover um efeito, um envio ou um barramento com raia aberta | A automação dele é apagada junto | Desfazer (`Ctrl+Z`) traz de volta | [06c](../manual/06c-painel-de-efeitos.md) · [07](../manual/07-automacao.md#limites-e-pegadinhas) |
| Congelar uma faixa esperando manter a automação de instrumento e efeito | Só volume, pan e envios passam para a faixa nova; o resto vira som no arquivo | Desfazer o congelamento, ajustar e congelar de novo | [08, congelar](../manual/08-exportacao.md#congelar-uma-faixa) |
| Primeiro ponto de uma raia no meio do trecho | Antes do primeiro ponto vale o valor dele: o filtro "pula" no começo do play | Primeiro ponto no início do trecho, no valor de partida | [mixagem, se der errado](mixagem-e-automacao.md#se-der-errado) |

### 3.4 Instrumentos e presets

| Evite juntar | Por quê | Em vez disso | Ver |
|---|---|---|---|
| Aplicar um preset depois de ajustar knobs | O preset aplica **todos** os valores; o que ele não cita volta ao padrão (no FM e no wavetable inclusive `Volume`, `Vozes` e o LFO). Nos efeitos só o `Sidechain` é preservado | Preset primeiro, ajuste depois; `Ctrl+Z` desfaz | [04](../manual/04-painel-de-instrumento.md#presets) · [06c](../manual/06c-painel-de-efeitos.md) |
| `Sampler` com zonas e o cartão `ÁUDIO` (áudio único, `Nota base`, `Modo`) | Com ao menos uma zona esses três deixam de valer; só a `Afinação` do cartão soma. O `Modo` do cartão ainda apaga a `Soltura` e desenha o envelope curto, mesmo com as zonas em outro modo (inconsistência da interface) | Ajustar `Nota base` e modo em cada zona | [04c](../manual/04c-sampler.md#limites-e-pegadinhas) |
| Acordes e camadas no `Sampler` | Cada zona que dispara consome uma voz (16 no total): 3 camadas por nota gastam 3 vozes por nota | Uma camada por região, ou menos notas juntas | [sampler, se der errado](sampler-multi-zona-e-fatiar-loops.md#se-der-errado) |
| Camadas de velocidade com um valor sem zona | A força que cai no vão fica muda | Sobrepor de 2 a 3 valores (suaves 1 a 83, fortes 81 a 127) | [sampler, receita 1](sampler-multi-zona-e-fatiar-loops.md#receita-1-piano-multi-sample-com-camadas-de-velocidade) |
| Camadas gravadas e `Sens. vel.` alta | A dinâmica é contada duas vezes | `Sens. vel.` em 35% | [sampler, receita 1](sampler-multi-zona-e-fatiar-loops.md#receita-1-piano-multi-sample-com-camadas-de-velocidade) |
| Round-robin com várias regiões ou camadas no mesmo `grupo` | A alternância pode pular gravações; editar uma zona reenvia a lista e reinicia o ciclo `(não confirmado em uso)` | Um grupo por região e por camada | [04c, round-robin](../manual/04c-sampler.md#round-robin) |
| `Sampler` para esticar ou transpor sem mudar a duração | Altura e duração andam juntas; acima de cerca de quatro oitavas da nota base a leitura para de subir | Clipe de áudio com `Warp e altura…` | [04c](../manual/04c-sampler.md) · [03b](../manual/03b-warp-e-altura.md) |
| Áudio único do `Sampler` para uma nota longa | Toca uma vez, sem loop: quando o áudio acaba a nota fica muda | Zona `Sustentado` com `Loop enquanto a nota está presa`; sem emenda suave (crossfade), então escolha um trecho estável `(não confirmado em uso)` | [04c, loop](../manual/04c-sampler.md#loop-da-zona) |
| Fatias e mudança de andamento | Fatias tocam no tamanho e na altura originais e não seguem o andamento: as notas se afastam ou as fatias se sobrepõem | Ajustar `Soltura` e a nota mais curta | [sampler, receita 2](sampler-multi-zona-e-fatiar-loops.md#receita-2-kit-de-bateria-a-partir-de-um-loop-fatiado) |
| Efeito para uma peça só da `Bateria` | As 12 peças saem numa faixa: o efeito vale para todas | Segunda faixa `Bateria` com só essa peça e o `Volume` das outras em 0% | [04b](../manual/04b-bateria.md#limites-e-pegadinhas) |
| `Legato`, `Staccato…` ou duração de nota na `Bateria` | A peça toca até o fim; nota curta e longa soam iguais. Nota fora do mapa (`sem peça`) é silêncio | Variar linha, posição e velocidade | [04b](../manual/04b-bateria.md#programar-no-piano-roll) |
| Trocar o algoritmo do FM sem reajustar os operadores | O `Nível` é volume no portador e brilho no modulador: o timbre pode ficar de repente muito brilhante | Reajustar o `Nível` dos operadores que mudaram de papel | [04d](../manual/04d-fm.md#limites-e-pegadinhas) |
| `Utilitário` com `Largura` para abrir o estéreo de um FM | O FM sai com o mesmo sinal nos dois lados; a `Largura` age em mid/side, e sem lado (esquerdo = direito) não há o que abrir (`engine/src/fx/utility.rs`). O capítulo 04d cita o `Utilitário` nesse contexto; as receitas usam outros efeitos | `Chorus` (`Chorus leve`, `Ensemble`), `Reverb` ou `Delay` com `Ping-pong` | [04d](../manual/04d-fm.md) · [FM e wavetable](fm-e-wavetable-na-pratica.md#combinando-com-efeitos) |
| `Sustentação` 0% em todos os portadores (FM) ou na `AMPLITUDE` (sintetizador e wavetable) | A nota decai até o silêncio mesmo com a tecla presa, e a voz nem é calculada depois | Subir a `Sustentação` de pelo menos um portador ou da amplitude | [04d](../manual/04d-fm.md) · [04a](../manual/04a-sintetizador.md) · [04e](../manual/04e-wavetable.md) |
| `Uníssono` em 1 e mexer em `Desafino` e `Espalhar` | Sem cópias não há o que afastar: os dois ficam sem efeito (apagados na tela) | Subir o `Uníssono` para 2 ou mais | [04e](../manual/04e-wavetable.md) |
| `Uníssono` alto e `Vozes` 16 em celular fraco | Cada nota usa até 7 cópias de 2 osciladores (custo estimado pelo código, não medido) | `Uníssono` e `Vozes` menores | [04e](../manual/04e-wavetable.md#limites-e-pegadinhas) |
| Pad com soltura longa e pedal com poucas `Vozes` | Notas seguradas pelo pedal ocupam voz até ele subir; passando de 16 a voz mais antiga sai em fade | Subir `Vozes` ou encurtar a `Soltura` | [04a](../manual/04a-sintetizador.md#limites-e-pegadinhas) · [expressão, receita 2](expressao-midi-na-pratica.md#receita-2-pedal-de-sustain-em-acordes-de-teclado) |
| Vogais da série `Vozes` da wavetable em notas muito agudas ou graves | Os formantes são fixos, feitos para uma fundamental de cerca de 150 Hz: a vogal muda | Tocar em região média ou transpor o oscilador `Semitons` −12 | [04e](../manual/04e-wavetable.md#limites-e-pegadinhas) |

### 3.5 MIDI, expressão e edição de notas

| Evite juntar | Por quê | Em vez disso | Ver |
|---|---|---|---|
| Pontos de bend, modulação e pedal e as ferramentas de notas | Só `Escalar o tempo` e `Inverter no tempo` levam os pontos junto (e cortar, duplicar, mover e aparar o clipe na linha do tempo). `Humanizar`, `Quantizar`, arpejo, mover notas e `Dividir no cursor` não os movem | Mover os pontos também; cortar o clipe com `S` na linha do tempo | [05b, os controles nas ferramentas](../manual/05b-ferramentas-midi.md#os-controles-nas-ferramentas) |
| Desenhar bend com a grade em `1/16` ou `Livre` | Curva em degraus de 0,25 tempo (125 ms a 120 bpm): audível como escada | Grade `1/32` | [expressão, receita 1](expressao-midi-na-pratica.md#receita-1-solo-de-sintetizador-com-scoop-e-vibrato-que-entra) |
| Bend ou modulação sem ponto em zero e um clipe com mais notas depois | O motor só devolve bend e modulação ao repouso no fim do clipe | Ponto em zero logo depois do fim do gesto | [expressão, receita 3](expressao-midi-na-pratica.md#receita-3-queda-de-altura-desenhada-e-automatizada) |
| Vibrato da roda de modulação da tela e fechar o painel | A roda não tem mola nem é salva com o projeto; fechar o painel, trocar de aba ou de faixa a devolve a zero | Desenhar o vibrato na faixa `Modulação` do editor | [04, pegadinhas](../manual/04-painel-de-instrumento.md#limites-e-pegadinhas) |
| Bend, roda e pedal numa faixa de `Bateria` | A bateria ignora os três (a gravação os registra do mesmo jeito, sem som `(não confirmado)`) | Instrumento com afinação | [05](../manual/05-piano-roll.md#limites-e-pegadinhas) |
| Gravar só os controles (sem notas) sem clipe sob o cursor | Nada é criado e o app não avisa | Cursor dentro de um clipe existente | [03c](../manual/03c-gravacao.md) |
| `Prender na escala` ligado e transpor com as setas, `Inverter na altura` ou `Inserir acorde…` | Essas operações só respeitam a escala se `Manter o encaixe ao mudar a altura` também estiver ligado (vem desligado); `Prender na escala` sozinho age só ao criar, mover de linha e colar | Ligar as duas caixas, ou `Prender seleção na escala` para consertar `(testado só por testes automáticos)` | [05b, escala e acordes](../manual/05b-ferramentas-midi.md#escala-e-acordes) |
| `Acorde no clique` esquecido ligado | Todo clique seguinte também cria acorde | Desligar no menu `Ferramentas > Escala e acordes` | [melodia, se der errado](melodia-e-harmonia-com-as-ferramentas.md#se-der-errado) |
| `Quantizar` com a grade `1/4` num arpejo de colcheias | A quantização usa a grade do **editor**: as colcheias seriam puxadas para o tempo | Grade `1/8` (ou a menor subdivisão usada) | [melodia, passo 3](melodia-e-harmonia-com-as-ferramentas.md#3-humanizar-e-quantizar) |
| `Shift+H` repetido | A semente muda a cada uso e os desvios se empilham | `Ctrl+Z` e `Tempo` menor | [05b, Humanizar](../manual/05b-ferramentas-midi.md#diálogo-humanizar) |
| Ferramentas que esticam notas além do fim do clipe | Notas depois do fim não tocam; `Escalar o tempo`, `Legato` e outras fazem o clipe crescer até o compasso que contém a última nota (e ele não encolhe de volta) | `Ctrl+Z` desfaz notas e comprimento juntos | [05b](../manual/05b-ferramentas-midi.md#limites-e-pegadinhas) · [05](../manual/05-piano-roll.md#limites-e-pegadinhas) |
| Teclado do computador ligado (`Ctrl+K`) e atalhos de letra | `S`, `E`, `F`, `L`, `C`, `X`, `Z` e, no editor, `K`, `J`, `Shift+H`, `Shift+L` viram nota, oitava ou intensidade (o botão mostra `C4 · sem atalhos`) | `Ctrl+K` desliga; com `Ctrl`, `⌘` ou `Alt` a letra volta a ser atalho | [09, prioridades](../manual/09-configuracoes-atalhos-android.md) · [atalhos, regra 3](atalhos-e-fluxo-rapido.md#0-cinco-regras-que-decidem-se-a-tecla-pega) |
| Teclado do computador na `Bateria` fora da oitava `C2` | A bateria só responde a um trecho do mapa (notas 35 a 59); a oitava é uma por tipo de faixa | `Z` até o botão mostrar `C2` | [04b](../manual/04b-bateria.md#limites-e-pegadinhas) |
| `Converter em notas (MIDI)` em acordes, mixagem ou percussão | O detector é monofônico (50 Hz a 2 kHz); polifonia dá resultado errado ou nenhum. Limite de 10 minutos; o `Ganho do clipe…` não ajuda (a análise lê o original) | Uma voz ou instrumento por vez, sem base por baixo | [03d](../manual/03d-audio-para-midi.md#limites-e-pegadinhas) |
| Mudar warp, transposição, reverso ou andamento depois de converter em notas | As notas ficam gravadas em batidas e não acompanham | Converter de novo | [03d, coerência com o clipe](../manual/03d-audio-para-midi.md) |

### 3.6 Warp, clipes e gravação

| Evite juntar | Por quê | Em vez disso | Ver |
|---|---|---|---|
| Warp com **transposição grande em voz** | O método reamostra e não preserva formantes: o timbre muda junto (consequência do método; o quanto incomoda é `(não confirmado)`) | 1 a 3 semitons, ou outra fonte | [03b](../manual/03b-warp-e-altura.md#limites-e-pegadinhas) · [remix, passo 6](remix-com-warp-e-altura.md#6-transpor-o-tom) |
| Warp com razão fora de 0,5 a 2 em pad denso, acordes ou mixagem completa | Aparece "flutter" (tremulação); o método foi escolhido para loops de bateria e trechos rítmicos | Aproximar os andamentos; usar um trecho rítmico | [03b](../manual/03b-warp-e-altura.md#limites-e-pegadinhas) · [remix, se der errado](remix-com-warp-e-altura.md#se-der-errado) |
| Warp e transposição juntos num material longo | Transpor é esticar e reamostrar: o trabalho dobra e o `processando…` demora (o clipe toca o original até ficar pronto) | Trabalhar em pedaços cortados | [03b](../manual/03b-warp-e-altura.md) · [remix, se der errado](remix-com-warp-e-altura.md#se-der-errado) |
| Um só `BPM do áudio` numa música com andamento que oscila | O detector estima **um** andamento fixo (e foi testado só com material sintético); o erro pequeno se acumula até o fim | Cortar em pedaços com um valor cada, ou refinar com decimais (`99,8`) | [remix, passo 4](remix-com-warp-e-altura.md#4-alinhar-a-primeira-batida-e-conferir-o-fim) |
| Detector em pad, tom puro, ruído ou trecho de menos de 3 s | Devolve "sem andamento"; nos extremos (por volta de 65 ou acima de 170 BPM) pode dar o dobro ou a metade | Digitar o BPM; `÷2` ou `×2` | [03b, detector](../manual/03b-warp-e-altura.md) |
| Mudar o andamento **depois** de gravar áudio | Um clipe de áudio sem warp mantém a duração em segundos: o fim dele anda em batidas, enquanto as notas MIDI acompanham | Fechar o andamento antes da primeira tomada | [gravar uma banda, passo 1](gravar-uma-banda-e-mixar.md#1-o-projeto-e-o-andamento-antes-de-gravar) |
| Mexer em warp, andamento, loop, importar, exportar ou desfazer **gravando** | Tudo isso fica travado durante a gravação (`Pare a gravação para…`) | Parar antes | [03c](../manual/03c-gravacao.md) · [02](../manual/02-transporte.md#limites-e-pegadinhas) |
| Dois clipes de áudio sobrepostos na mesma faixa | O clipe que você mexeu ganha e o que ele cobre é aparado, partido ou removido | Outra faixa; `Duplicar a faixa` em vez de `Duplicar` o clipe | [02b, sobreposição](../manual/02b-timeline-e-clipes.md#cortar-duplicar-apagar-e-sobreposição) · [remix, passo 7](remix-com-warp-e-altura.md#7-reverso-como-efeito-subida-antes-da-virada) |
| Microfone, alto-falante e clique do metrônomo durante a gravação | Microfonia; o clique vaza para o microfone | Fones; metrônomo desligado depois da contagem (a contagem continua) | [gravar uma banda, passo 5](gravar-uma-banda-e-mixar.md#5-violão-e-baixo-uma-tomada-com-contagem) |
| Duas faixas de áudio armadas ao mesmo tempo | A entrada é uma só: cada faixa recebe um clipe com o mesmo áudio | Armar uma de cada vez | [03c](../manual/03c-gravacao.md) |
| Começar a gravar em loop no meio do loop | A primeira tomada fica com silêncio na frente e não é escolhida como ativa | Cursor no começo do loop | [gravar uma banda, passo 6](gravar-uma-banda-e-mixar.md#6-voz-monitor-e-tomadas-em-loop) |
| Esperar que os efeitos da faixa fiquem gravados no arquivo | A gravação é a entrada crua; os efeitos entram só no que se ouve | Decidir o som depois, na mixagem | [03c](../manual/03c-gravacao.md#limites-e-pegadinhas) |
| Calibrar a latência num aparelho e abrir o projeto em outro | Cada aparelho mantém a sua `Compensação de latência` ao receber a versão da nuvem | Calibrar em cada aparelho | [09](../manual/09-configuracoes-atalhos-android.md#limites-e-pegadinhas) |

### 3.7 Exportação e loudness

| Evite juntar | Por quê | Em vez disso | Ver |
|---|---|---|---|
| **Normalizar o loudness** e o teto de true peak numa mixagem "espetada" | É só ganho: se subir até o alvo passaria do teto, o ganho para no teto e o arquivo sai **abaixo** do alvo, com aviso. Vale a regra `TP − I` de no máximo 13 dB (−14 LUFS), 15 dB (−16) ou 22 dB (−23). Baixar o teto só piora | `Limitador` no master antes (por exemplo `Master −1 dB` com `Teto` −1,5 dB e 2 a 4 dB de redução nos picos) | [08](../manual/08-exportacao.md#normalizar-o-loudness) · [loudness, passo 3](loudness-e-master.md#3-ganhar-volume-com-o-limitador-no-master-não-com-o-fader) |
| Confiar no `Teto` do `Limitador` como true peak | O `Limitador` trabalha com o pico de amostra (o código não mostra detecção de pico verdadeiro `(não confirmado)`), então o `TP` pode ler perto de 0 dBTP com a barra em −0,3 | `Teto` cerca de 0,5 dB abaixo do desejado | [06d Limitador](../manual/06d-efeitos-referencia.md#4-limitador) · [06b](../manual/06b-analisador-e-medidores.md) |
| `Normalizar` (pico) e `Normalizar o loudness` | São pedidos contrários: ligar um desliga o outro | Escolher um | [08](../manual/08-exportacao.md) |
| `Normalizar` (pico) com `Stems` | Cada stem é levado a −1 dBFS separadamente e o equilíbrio muda | `Normalizar` desligado e WAV 32 bits float | [08, stems](../manual/08-exportacao.md#stems) |
| `Stems com o mesmo ganho` em WAV 16 ou 24 bits | O teto de true peak vale para a mixagem, não para os stems: um stem alto passa de 0 dBFS e é cortado | WAV 32 bits float, ou desligar a opção | [loudness, se der errado](loudness-e-master.md#se-der-errado) |
| Normalizar uma região muito curta, silêncio ou tudo abaixo de −70 LUFS | Sem medida não há ganho: sai sem normalizar (`Não deu para medir o loudness…`) | Exportar um trecho maior | [08](../manual/08-exportacao.md#normalizar-o-loudness) |
| Comparar o `I` do mixer com o do arquivo | O mixer mede a saída ao vivo (com metrônomo e entrada monitorada, tudo desde o último `Zerar`); a exportação mede só a mixagem | `Zerar`, metrônomo desligado, música inteira; vale o número da janela do resultado | [06b](../manual/06b-analisador-e-medidores.md#limites-e-pegadinhas) |
| `I` de um trecho só | O `I` só vale para a música inteira tocada desde o `Zerar` | Tocar do começo ao fim | [06b](../manual/06b-analisador-e-medidores.md#medidor-de-loudness-do-master-m-s-i-tp) |
| Esperar MP3, FLAC ou AAC da exportação | Só WAV (16, 24 ou 32 bits float); o outro arquivo da janela é o `.jopendaw` | Converter fora do app | [08](../manual/08-exportacao.md#limites-e-pegadinhas) |
| `Cauda` em 0 com reverb ou delay | O fim é o último clipe; a cauda deixa soar o que já tocava | 2 s (padrão), 4 a 6 s com reverb longo | [08](../manual/08-exportacao.md) |
| Esperar metrônomo ou loop no arquivo exportado | O arquivo é linear, sem cliques; metrônomo e loop não entram | Marcar a `Região do loop` só para escolher o trecho | [08](../manual/08-exportacao.md#o-que-entra-no-arquivo) |
| Congelar um barramento ou esperar editar notas depois de congelar | Barramento não congela; a faixa congelada é áudio, sem instrumento nem efeitos | Desfazer o congelamento, ajustar e congelar de novo; barramento: exportar como stem | [08, congelar](../manual/08-exportacao.md#congelar-uma-faixa) |
| Exportar e congelar ao mesmo tempo, ou exportar gravando | Um render por vez; gravando, exportar e congelar ficam desligados | Esperar o render acabar | [08](../manual/08-exportacao.md#memória-lotes-e-limites) |
| Exportar com áudio `fora deste aparelho` | Os clipes sem o arquivo saem em silêncio, com aviso | Abrir no aparelho que tem os áudios ou sincronizar antes | [08](../manual/08-exportacao.md#limites-e-pegadinhas) |

### 3.8 Nuvem, arquivos, cota e plataforma

| Evite juntar | Por quê | Em vez disso | Ver |
|---|---|---|---|
| Abrir num segundo aparelho um projeto criado com modelo (`Batida eletrônica`, `Gravação de banda`) antes de o aparelho criador abri-lo | O modelo só vira faixas no aparelho que criou o projeto; o outro abre como `Vazio` e os dois lados mudam: conflito | Abrir primeiro no aparelho criador e esperar `Sincronizado` | [01, pegadinhas](../manual/01-projetos-modelos-conta.md#limites-e-pegadinhas) |
| Editar um aparelho novo durante os 25 s do círculo girando | Abre com uma faixa `Áudio 1` vazia e a versão da nuvem a substitui depois; editar ali gera conflito | Não editar nesse intervalo | [01b](../manual/01b-nuvem-e-sincronizacao.md#abrir-um-projeto-num-aparelho-novo) |
| Editar em dois aparelhos com mudança pendente | A troca automática só acontece sem pendência; com pendência, o conflito aparece quando o segundo tentar enviar. A troca automática é silenciosa e zera o desfazer (`(testado só por testes automáticos)`) | Terminar, esperar `Sincronizado`, e só então mexer no outro | [01b](../manual/01b-nuvem-e-sincronizacao.md) · [dois aparelhos, passo 4](trabalhar-em-dois-aparelhos.md#4-editar-no-celular-e-voltar-ao-computador) |
| `Usar a versão do servidor` ou `Manter esta e enviar` sem exportar antes | As duas escolhas são definitivas; a nuvem guarda só a versão atual | `Decidir depois` e exportar o `.jopendaw` neste aparelho (e no outro) | [dois aparelhos, passo 5](trabalhar-em-dois-aparelhos.md#5-resolver-um-conflito) · [backup, variações](backup-e-levar-projeto-para-outro-aparelho.md#variações) |
| Tratar o `.jopendaw` como sincronização | Importar cria **sempre** um projeto novo, sem vínculo com o original; precisa de conta e de rede; mudanças não se juntam | Mesma conta e nuvem para o mesmo projeto vivo | [01, arquivo](../manual/01-projetos-modelos-conta.md#projeto-em-arquivo-jopendaw) · [backup](backup-e-levar-projeto-para-outro-aparelho.md) |
| Apagar projeto, faixa ou clipe esperando devolver cota | O áudio fica `sem uso` na conta até ser apagado na tela `Conta`; um áudio de documento ainda não sincronizado parece `sem uso`; a limpeza em massa poupa o enviado há menos de 1 hora | Esperar `Sincronizado`, depois `Limpar áudios sem uso` | [01, armazenamento](../manual/01-projetos-modelos-conta.md#armazenamento-de-áudios-na-tela-conta) · [01b, cotas](../manual/01b-nuvem-e-sincronizacao.md#cotas-e-limites) |
| Limpar dados do site ou desinstalar o app antes de sincronizar | Apaga o que ainda não subiu; o app Android não participa do backup do sistema | Esperar `Sincronizado`; ou exportar o `.jopendaw` | [01b, pegadinhas](../manual/01b-nuvem-e-sincronizacao.md#limites-e-pegadinhas) |
| Muitas tomadas em loop e importar arquivos enormes | Cota de **4 GB** por conta, **512 MB** por arquivo e **8 MB** de documento; cada tomada é um WAV de 32 bits float (cerca de 23 MB por minuto em estéreo a 48 kHz) | Importar arquivos comprimidos; gravar só as tomadas necessárias | [dois aparelhos, passo 7](trabalhar-em-dois-aparelhos.md#7-cota-de-armazenamento) |
| Importar `opus` ou `webm` no Android | O motor nativo não decodifica Opus; na web depende do navegador. `Converter em notas (MIDI)` também não aceita OGG/Opus, AIFF nem WebM | `wav`, `flac`, `mp3`, `ogg` Vorbis ou `m4a` | [03](../manual/03-audio-e-clipes.md#formatos-aceitos) · [03d](../manual/03d-audio-para-midi.md#limites-e-pegadinhas) |
| Sair do app no Android com a gravação rodando | O app para o transporte e encerra a gravação (o que já foi gravado fica salvo) `(testado só por testes automáticos)`; atalhos de teclado só com teclado físico `(não confirmado)` | Ficar no app enquanto grava | [09](../manual/09-configuracoes-atalhos-android.md#o-aparelho-no-android) |

---

## 4. Receitas rápidas de uma linha

Formato: "faça X → use Y com Z=valor". Os números são pontos de partida; o link leva ao capítulo ou ao guia com o passo a passo.

### Mixagem e espaço

| Faça… | Use… | Ver |
|---|---|---|
| Tirar o subgrave de uma faixa que não é bumbo nem baixo | `EQ` preset `Corte de graves` (banda 1 `Passa-alta` 80 Hz, 24 dB/oit); para o resto da mix, `Frequência` 100 Hz | [06d EQ](../manual/06d-efeitos-referencia.md#1-eq-8-bandas) |
| Limpar o chiado entre frases | `Gate` preset `Ruído de fundo` (`Limiar` −55 dB, `Alcance` −30 dB, `Retenção` 50 ms) | [06d Gate](../manual/06d-efeitos-referencia.md#3-gate) |
| Nivelar uma voz | `Compressor` preset `Voz` (−20 dB, 3,5:1, 5 ms, 80 ms); arraste o `Limiar` até 3 a 6 dB de redução | [receita 1](efeitos-em-combinacao.md#receita-1-cadeia-vocal-gate-eq-compressor-reverb) |
| Dar presença à voz | `EQ` preset `Voz presente` e mover o nó 3 entre 200 e 400 Hz até o "embolado" sumir | [receita 1](efeitos-em-combinacao.md#receita-1-cadeia-vocal-gate-eq-compressor-reverb) |
| Ambiência sem encher a mix | Barramento com `Reverb` `Placa`, `Mistura` 100%, `Pré-atraso` 20 ms, `Cortar graves` 200 Hz; envios de −18 dB (fundo) a −14 dB (voz); bumbo e baixo sem envio | [mixagem, passo 2](mixagem-e-automacao.md#2-criar-um-barramento-de-reverb-compartilhado) |
| Fazer o reverb abaixar quando a voz canta | `Compressor` depois do `Reverb` no retorno, `Sidechain` na faixa da voz, −30 dB, 4:1, 10 ms, 300 ms | [mixagem, passo 2](mixagem-e-automacao.md#2-criar-um-barramento-de-reverb-compartilhado) |
| Fazer o baixo ou o pad bombear com o bumbo | `Compressor` na faixa dele, `Sidechain` na faixa do bumbo, `Detector` `Pico`, `Passa-alta` 20 Hz, 8:1, `Ataque` 1 ms, `Soltura` `0,4 × 60 ÷ BPM` s | [receita 3](efeitos-em-combinacao.md#receita-3-sidechain-pumping-com-o-bumbo) |
| Dar peso à bateria sem perder o ataque | Envio 0 dB pós-fader para um barramento com `Compressor` `Paralelo pesado`, `Mistura` 100%; fader do barramento perto de −10 dB e subir | [receita 2](efeitos-em-combinacao.md#receita-2-bateria-com-compressor-paralelo-em-barramento) |
| Colar o conjunto da bateria | `Compressor` preset `Bateria cola` (−16 dB, 2:1, `Ataque` 30 ms) | [06d Compressor](../manual/06d-efeitos-referencia.md#2-compressor) |
| Ecos presos ao andamento | `Delay` com `Tempo` `Andamento` e `Nota` `1/8D` (a 120 BPM são 375 ms: batidas × 60 ÷ BPM) | [06d Delay](../manual/06d-efeitos-referencia.md#7-delay) |
| Ecos que pulam de lado | `Delay` preset `Ping-pong 1/4` (30%, `1/4`, 45%, `Ping-pong` `Sim`) | [receita 4](efeitos-em-combinacao.md#receita-4-delay-em-ping-pong-sincronizado-ao-andamento) |
| Ecos só nas pausas da voz | `Delay` `Ducking` 30 a 40% (preset `1/8 pontilhado`) | [06d Delay](../manual/06d-efeitos-referencia.md#7-delay) |
| Eco curto de rockabilly | `Delay` preset `Slapback` (`Tempo` `Livre`, 110 ms, `Realimentação` 5%) | [06d Delay](../manual/06d-efeitos-referencia.md#7-delay) |
| Pad largo sem embolar os graves | `Chorus` `Ensemble` com `Mistura` 40%, `EQ` banda 1 `Passa-alta` 150 Hz, `Reverb` `Salão` com `Cortar graves` 200 Hz | [receita 5](efeitos-em-combinacao.md#receita-5-pad-largo-com-chorus-e-reverb) |
| Conferir se o pad ou o baixo somem em mono | `Utilitário` `Mono` `Sim` no fim da cadeia, escutar e tirar | [06d Utilitário](../manual/06d-efeitos-referencia.md#5-utilitário) |
| Baixo com dentes sem perder o grave | `EQ` 40 Hz, `Compressor` `Baixo`, `Distorção` `Válvula quente` com `Drive` 18 dB e `Mistura` 55% | [receita 6](efeitos-em-combinacao.md#receita-6-distorção-de-baixo-com-filtro-e-eq) |
| Wobble de baixo | `Filtro` preset `Wobble 1/8` (`Nota` `1/8`); no sintetizador, `LFO` `Taxa` 3 Hz com `Filtro` 3 oit e `Vozes` 1 | [04a, wobble à mão](../manual/04a-sintetizador.md) · [06d Filtro](../manual/06d-efeitos-referencia.md#12-filtro) |
| Baixo em mono | `Utilitário` `Mono` `Sim` na faixa do baixo | [06d Utilitário](../manual/06d-efeitos-referencia.md#5-utilitário) |
| Ouvir só uma faixa com o reverb dela | `S` na faixa (o retorno é alimentado só por quem está em solo) | [06, solo e mudo](../manual/06-mixer.md#solo-e-mudo) |
| Agrupar a bateria | Botão de saída de cada faixa em `Novo barramento` e depois o mesmo; `Compressor` no barramento | [mixagem, variações](mixagem-e-automacao.md#variações) |

### Automação

| Faça… | Use… | Ver |
|---|---|---|
| Subida de filtro de 8 compassos | `Filtro` `Passa-alta de transição`, raia `Corte` de 60 Hz a 3 kHz (reta na tela vira reta em oitavas) | [mixagem, passo 3](mixagem-e-automacao.md#3-automatizar-um-filtro-para-a-subida-da-música) |
| Fade-out da música | Raia `Volume` do `Master`: 0 dB no compasso 33, −∞ dB no 37, grade `Compasso` | [mixagem, passo 4](mixagem-e-automacao.md#4-fazer-um-fade-de-volume-por-automação) |
| Fade parelho de ouvido | Reta na raia de volume: −7,5 dB, −18 dB e −36 dB em 25%, 50% e 75% do trecho (a escala é a do fader) | [07, escala](../manual/07-automacao.md) |
| Salto seco no refrão | Dois pontos na mesma batida formam um degrau; arraste um até a batida do outro | [07](../manual/07-automacao.md#curva-entre-pontos-curve) |
| Timbre morfando ao longo da música | Raia `Posição` do `Oscilador 1` da wavetable, de 0% no compasso 1 a 100% no 9; `Posição` do LFO em 0% se só a automação deve mandar | [FM e wavetable](fm-e-wavetable-na-pratica.md#automatizando-a-posição-da-wavetable) |

### Instrumentos e expressão

| Faça… | Use… | Ver |
|---|---|---|
| Sino elétrico | FM `Sino elétrico` (`Algoritmo 5`, razões 3,5 e 7) e `Chorus` `Chorus leve`, depois `Reverb` `Placa` | [FM e wavetable, receita 1](fm-e-wavetable-na-pratica.md#receita-1-sino-elétrico-fm) |
| Baixo de DX | FM `Baixo DX` (`Algoritmo 1`, `Vozes` 1, `Realimentação` 15%) | [FM e wavetable, receita 2](fm-e-wavetable-na-pratica.md#receita-2-baixo-fm) |
| Lead com PWM | Wavetable série `Clássica`, `Posição` 71%, `LFO` `Triângulo` a 2,2 Hz com `Posição` 18%, `Vozes` 1, `Glide` 50 ms | [FM e wavetable, receita 4](fm-e-wavetable-na-pratica.md#receita-4-lead-com-pwm-wavetable) |
| Coro que percorre as vogais | Wavetable `Coro AEIOU` (série `Vozes`, `LFO` `Triângulo` 0,35 Hz, `Posição` 45%) em região média | [FM e wavetable, receita 5](fm-e-wavetable-na-pratica.md#receita-5-coro-vocal-wavetable) |
| Pluck cujo timbre cai | Wavetable `Posição` base 15%, `Posição (env. do filtro)` +50%, `Envelope` do filtro +80%, `Sustentação` 0% | [04e](../manual/04e-wavetable.md) |
| Solo com scoop e vibrato que entra | `Alcance do bend` 2 st, grade `1/32`, `Pitch bend` do fundo ao meio em meio tempo; `Vibrato da roda` 0,5 st e `Modulação` de 0% a 60% em um tempo | [expressão, receita 1](expressao-midi-na-pratica.md#receita-1-solo-de-sintetizador-com-scoop-e-vibrato-que-entra) |
| Acordes que ressoam e se limpam na troca | `Teclado (EP)`, `Vozes` 8 ou mais, visão `Sustain` pintada de cada acorde até um quarto de tempo antes do próximo | [expressão, receita 2](expressao-midi-na-pratica.md#receita-2-pedal-de-sustain-em-acordes-de-teclado) |
| Queda de duas oitavas em três tempos | `Alcance do bend` 24 st e reta de `Pitch bend` do meio ao fundo, com `Corte` automatizado de 5,50 kHz a 800 Hz | [expressão, receita 3](expressao-midi-na-pratica.md#receita-3-queda-de-altura-desenhada-e-automatizada) |
| Piano em camadas de força | Zonas suaves (velocidade 1 a 83) e fortes (81 a 127) na mesma região, `Sens. vel.` 35%, preset `Instrumento` | [sampler, receita 1](sampler-multi-zona-e-fatiar-loops.md#receita-1-piano-multi-sample-com-camadas-de-velocidade) |
| Kit de um loop de bateria | `Fatiar sample…` `Por transientes` com `Sensibilidade` 50% e preset `Percussão (até o fim)`; notas a partir do C1 | [sampler, receita 2](sampler-multi-zona-e-fatiar-loops.md#receita-2-kit-de-bateria-a-partir-de-um-loop-fatiado) |
| Golpe que não repete o mesmo áudio | Três zonas com o mesmo `Round-robin` `grupo 1` e variações de `Ganho`, `Afinação` e `Pan` | [sampler, receita 3](sampler-multi-zona-e-fatiar-loops.md#receita-3-round-robin-para-o-mesmo-golpe-não-soar-mecânico) |
| Sustentar uma nota curta de sample | Zona `Sustentado` com `Loop enquanto a nota está presa` (nasce em 25% a 75% do trecho) | [04c](../manual/04c-sampler.md#sustentar-uma-nota-curta-com-loop) |
| Tocar a bateria no teclado do computador | `Ctrl+K` com a oitava em `C2`: `A` Bumbo, `S` Caixa, `T` Chimbal fechado, `U` Chimbal aberto, `E` Palmas | [04b](../manual/04b-bateria.md#tocar-a-bateria-no-computador) |

### Notas e edição MIDI

| Faça… | Use… | Ver |
|---|---|---|
| Progressão de acordes com um clique cada | `Escala…` (`C` `Maior`, `Prender na escala`) e `Acorde no clique` `Diatônico: tríade`, `Nota: 1/1`, grade `1/4` | [melodia, passo 1](melodia-e-harmonia-com-as-ferramentas.md#1-a-progressão-c-am-f-g-um-compasso-cada) |
| Acordes viram arpejo | `Arpejador…` `Subir e descer`, `Taxa` `1/8`, 1 oitava, `Gate` 90% | [melodia, passo 2](melodia-e-harmonia-com-as-ferramentas.md#2-virar-arpejo) |
| Baixo em oitavas a partir de uma nota por compasso | `Arpejador…` `Subir`, `1/8`, 2 oitavas, `Gate` 60% (uma nota sozinha vira repetição com salto de oitava) | [melodia, passo 4](melodia-e-harmonia-com-as-ferramentas.md#4-a-linha-de-baixo-a-partir-da-fundamental-de-cada-acorde) |
| Tirar o ar de máquina | `Humanizar…` `Tempo` 30%, `Velocidade` 40%; `Shift+H` repete com os últimos ajustes | [05b](../manual/05b-ferramentas-midi.md#diálogo-humanizar) |
| Firmar uma linha tocada ao vivo | `Ctrl+A`, grade na menor subdivisão (`1/16`), `Q` com `Força` 100% (ou 50% para manter a pegada) | [melodia, passo 3](melodia-e-harmonia-com-as-ferramentas.md#3-humanizar-e-quantizar) |
| Dobrar a velocidade de um trecho | `Ctrl+A` e `Escalar o tempo` `×0,5 (metade)` | [05b](../manual/05b-ferramentas-midi.md#escalar-o-tempo) |
| Repetir e transpor um compasso sem redesenhar | `Ctrl+A`, `Ctrl+D`, depois `↓` ou `↑` (1 semitom), `Shift+↓` (1 oitava) | [primeira batida, passo 3](primeira-batida-do-zero.md#3-baixo-sintetizador-com-o-preset-baixo-sub) |

### Gravação

| Faça… | Use… | Ver |
|---|---|---|
| Acertar o ganho do microfone | Armar a faixa de áudio e ajustar na fonte até o pico ficar em verde ou âmbar, sem acender a luz vermelha do topo | [06b](../manual/06b-analisador-e-medidores.md#medidor-de-entrada-e-o-clip) |
| Calibrar a latência | Gravar o metrônomo pelo microfone e mover `Compensação de latência` (−200 a 500 ms) de 10 em 10 ms até a batida cair na grade | [gravar uma banda, passo 3](gravar-uma-banda-e-mixar.md#3-calibrar-a-latência-uma-vez-por-aparelho) |
| Várias tomadas de voz | Loop marcado, cursor no começo dele, faixa armada e `R`; escolher no selo `N tomadas` | [gravar uma banda, passos 6 e 7](gravar-uma-banda-e-mixar.md#6-voz-monitor-e-tomadas-em-loop) |
| Ouvir-se com efeitos ao gravar | `Monitorar a entrada` na faixa de áudio, com fones | [03c](../manual/03c-gravacao.md) |
| Melodia cantada em MIDI | `Converter em notas (MIDI)` com `Nota mínima` 60 ms e `Nível de silêncio` −45 dB (uma voz por vez, até 10 minutos) | [03d](../manual/03d-audio-para-midi.md) |

### Warp e remix

| Faça… | Use… | Ver |
|---|---|---|
| Esticar um loop de 100 BPM para um projeto de 120 BPM | `Warp e altura…`, `Detectar` (ou digitar `100`) e `Ajustar ao andamento`; o clipe passa a durar 100 ÷ 120 | [03b](../manual/03b-warp-e-altura.md) · [remix, passo 3](remix-com-warp-e-altura.md#3-detectar-o-andamento-e-esticar) |
| Corrigir o erro de oitava do detector | `÷2` se achou o dobro (música arrastada), `×2` se achou a metade (música corrida) | [03b](../manual/03b-warp-e-altura.md) |
| Subir um sample 3 semitons sem mudar o tempo | Seção `ALTURA`, botão `+` três vezes (`+3 st`); não precisa ligar o warp | [03b](../manual/03b-warp-e-altura.md) |
| Subida de prato antes da virada | `Duplicar a faixa`, cortar um compasso com o prato, `Inverter o áudio` e terminar o clipe no compasso da virada, com fade in curto | [remix, passo 7](remix-com-warp-e-altura.md#7-reverso-como-efeito-subida-antes-da-virada) |
| Dar folga à batida sobre uma música | `Ganho do clipe…` −3 dB só no trecho, ou fader −3 dB; `Compressor` com `Sidechain` no bumbo | [remix, passo 8](remix-com-warp-e-altura.md#8-sobrepor-uma-batida) |

### Exportação e volume

| Faça… | Use… | Ver |
|---|---|---|
| Ler o loudness da música inteira | `Zerar` no `Master`, tocar do começo ao fim, ler `I` e `TP` (vermelho acima de −1 dBTP) | [06b](../manual/06b-analisador-e-medidores.md#medidor-de-loudness-do-master-m-s-i-tp) |
| Entregar em −14 LUFS para streaming | `Limitador` `Master −1 dB` com `Teto` −1,5 dB e 2 a 4 dB de redução; exportar com `Normalizar o loudness` `Streaming −14,0` e teto −1,0 dBTP | [loudness, passos 3 e 6](loudness-e-master.md#3-ganhar-volume-com-o-limitador-no-master-não-com-o-fader) |
| Entregar para podcast ou rádio e TV | `Normalizar o loudness` com `Podcast −16,0` ou `Broadcast −23,0` (rádio e TV quase sempre só descem) | [loudness, variações](loudness-e-master.md#variações) |
| Levar stems a outro programa com o balanço intacto | `Stems` ligado, `Normalizar` desligado, `WAV 32 bits float`, `Cauda` de 4 a 6 s | [gravar uma banda, passo 9](gravar-uma-banda-e-mixar.md#9-exportar-a-mixagem-e-os-stems) |
| Stems no mesmo volume relativo do alvo | `Normalizar o loudness` com `Stems com o mesmo ganho` e WAV 32 bits float | [08](../manual/08-exportacao.md#stems) |
| Testar só um trecho | `Região do loop` (arrastar na régua) na janela `Exportar áudio` | [08](../manual/08-exportacao.md#passo-a-passo) |
| Fixar um sintetizador pesado | `Opções da faixa` (três pontos), `Congelar em áudio`; `Ctrl+Z` desfaz | [08, congelar](../manual/08-exportacao.md#congelar-uma-faixa) |

### Projeto, aparelhos e ritmo de trabalho

| Faça… | Use… | Ver |
|---|---|---|
| Backup do projeto | `Exportar` e, na janela `Exportar áudio`, `Projeto inteiro (.jopendaw)…`; testar com `Importar projeto` | [backup, passo 1](backup-e-levar-projeto-para-outro-aparelho.md#1-backup-periódico) |
| Levar o projeto ao celular sem depender da nuvem | Exportar o `.jopendaw` e `Importar projeto` no celular (projeto novo, esperar `Sincronizado`) | [backup, passo 2](backup-e-levar-projeto-para-outro-aparelho.md#2-migrar-do-computador-para-o-celular-sem-depender-da-nuvem) |
| Guardar o que se perde num conflito | `Decidir depois` e exportar o `.jopendaw` neste aparelho antes de escolher | [dois aparelhos, passo 5](trabalhar-em-dois-aparelhos.md#5-resolver-um-conflito) |
| Trabalhar sem rede | Abrir o projeto com rede, esperar `Sincronizado`, e deixar o app aberto no projeto ao voltar | [dois aparelhos, passo 6](trabalhar-em-dois-aparelhos.md#6-sem-internet) |
| Liberar cota | Tela `Conta`, `Limpar áudios sem uso`, depois de `Sincronizado` | [01](../manual/01-projetos-modelos-conta.md#armazenamento-de-áudios-na-tela-conta) |
| Ensaiar uma seção | `M` ou `Shift+M` para marcar; com o cursor no marcador e nenhum clipe selecionado, `Shift+L` | [atalhos, passo 1](atalhos-e-fluxo-rapido.md#1-marcar-a-música-enquanto-ela-toca-e-ensaiar-uma-parte) |
| Cortar, repetir e apagar clipes só com o teclado | Clique no clipe, `S` no cursor, `Ctrl+D`, `Delete` | [atalhos, passo 2](atalhos-e-fluxo-rapido.md#2-cortar-repetir-e-apagar-clipes) |
