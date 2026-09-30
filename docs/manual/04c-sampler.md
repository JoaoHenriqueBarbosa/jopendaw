# Sampler

> Toca um áudio seu (uma nota, um golpe de bateria, uma frase) como instrumento: cada nota do teclado ou do piano roll dispara o áudio afinado naquela altura, com envelope e sensibilidade à força do toque.

## Onde fica

1. Crie a faixa em `Nova faixa` (coluna de faixas do arranjo) > `Sampler`, ou selecione uma faixa `Sampler`.
2. Abra o painel de baixo na aba `Instrumento` (tecla `I`).
3. O cabeçalho é o do [painel de instrumento](04-painel-de-instrumento.md); abaixo dele ficam três cartões: `ÁUDIO` (com o seletor do arquivo), `ENVELOPE` e `GERAL`.

No teclado da tela, a nota base do sampler aparece marcada com um ponto colorido. O teclado abre em C3, como o do sintetizador.

## Como o sampler toca

- O áudio é lido em velocidade variável: tocar a nota base toca o áudio na velocidade e na altura originais; uma nota um semitom acima toca mais rápido e mais agudo, e uma abaixo toca mais lento e mais grave. Como a duração muda junto com a altura, uma nota aguda dura menos que o áudio original e uma grave dura mais. Não há esticamento sem mudar a altura (para isso, ver [03b Warp e altura](03b-warp-e-altura.md), que vale para clipes de áudio).
- O áudio toca uma vez, do começo ao fim. Não existe loop no sampler: quando o áudio acaba, a voz acaba, mesmo que a tecla continue apertada.
- Sem áudio escolhido, as notas ficam mudas.
- Áudio estéreo continua estéreo; áudio mono sai igual dos dois lados. A taxa de amostragem do arquivo é convertida sozinha.
- Ao tocar mais agudo que o original, o sampler filtra os agudos que passariam do limite do áudio digital (anti-aliasing), então notas altas não produzem chiado de aliasing.

## Controles

### Áudio

O cartão tem, ao lado do título, o botão do arquivo; abaixo, o visor; embaixo, os três knobs.

| Controle (rótulo exato) | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| Botão do arquivo, tooltip `Áudio que o sampler toca` | Abre o menu para escolher, importar ou remover o áudio | O texto do botão muda: `Importar o áudio` (projeto ainda sem nenhum áudio), `Escolher o áudio` (há áudios no projeto mas nenhum escolhido), o nome do arquivo quando há um escolhido, ou `Áudio fora do projeto` | Sem áudio escolhido o botão fica destacado com a cor da faixa |
| Item de áudio (nome e duração, como `0.84 s`, `12.5 s` ou `3:07`) | Escolhe esse áudio para o sampler | Lista de todos os áudios do projeto, em ordem alfabética sem distinção de maiúsculas; um visto marca o atual | Inclui os áudios que você importou para clipes |
| `Importar um arquivo…` | Abre o seletor de arquivos (`Áudio do sampler`), lê o áudio e o faz o som do sampler | Aceita `wav`, `mp3`, `ogg`, `oga`, `flac`, `m4a`, `aac`, `opus`, `webm`, `aif` e `aiff` | Aparece o aviso `Importando nome…` enquanto decodifica |
| `Sem áudio` | Tira o áudio do sampler | Só aparece se já há um áudio escolhido | O áudio continua no projeto, só deixa de ser o do sampler |
| Visor da forma de onda | Mostra o áudio inteiro, ampliado pelo pico para amostras baixas aparecerem; a legenda diz a duração e a nota base (`0.84 s · C4`). Tem um ícone de play no canto | Segurar o mouse ou o dedo sobre o visor toca o áudio na nota base, com 80% de força (tooltip `Segure para ouvir na nota base`) | Serve para conferir o áudio e a nota base sem abrir o teclado |
| Nota base | A nota em que o áudio soa na altura original | 0 a 127, inteiro, padrão C4 (60); o knob mostra o nome da nota (`C4`) | No diálogo de valor (botão direito) dá para digitar `C3`, `F#3`. Ajuste para a altura real do áudio: se o áudio é um lá 440 Hz, ponha `A4` |
| Afinação | Ajuste fino da afinação de todas as notas | -100 a +100 ct, padrão +0 ct | Corrige um áudio levemente desafinado sem mexer na nota base |
| Modo | Como a nota termina | Lista: `Sustenta` (padrão) e `Até o fim` | `Sustenta`: soltar a tecla dispara a `Soltura`. `Até o fim`: soltar a tecla não faz nada, o áudio toca inteiro (percussão, golpes); com esse modo a `Soltura` fica apagada no cartão `ENVELOPE` |

Enquanto o áudio não está escolhido, o visor mostra uma orientação:

- `Nenhum áudio no projeto ainda. Importe um arquivo pelo menu acima: ele vira o som deste sampler, sem entrar no arranjo.`
- `Escolha acima qual áudio do projeto este sampler toca.`
- `Este áudio não está neste aparelho. Importe o arquivo de novo para ouvi-lo.` (o projeto guarda o áudio, mas este aparelho ainda não o tem)

Se o arquivo não puder ser lido, o app avisa `Não deu para abrir nome: é um formato de áudio que este navegador decodifica?`.

### Envelope

Visor: o desenho do envelope (ataque em rampa; decaimento e soltura exponenciais; tempos em escala logarítmica). No modo `Até o fim`, a legenda diz `até o fim: a soltura não entra`.

| Controle | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| Ataque | Tempo para o volume subir do zero ao máximo no começo da nota | 0,5 ms a 10 s, logarítmico, padrão 2.0 ms | Deixe curto para não cortar o começo do áudio; longo para entrar suave |
| Decaimento | Tempo da queda do máximo até a `Sustentação` | 1 ms a 10 s, logarítmico, padrão 500 ms | Sem efeito audível com `Sustentação` em 100% |
| Sustentação | Nível mantido enquanto a tecla está apertada | 0 a 100%, padrão 100% | Em 0% a nota morre sozinha depois do decaimento, mesmo com a tecla apertada (pluck) |
| Soltura | Tempo da queda depois de soltar a tecla | 1 ms a 10 s, logarítmico, padrão 200 ms | Apagada no modo `Até o fim` (só entra quando o transporte para) |

### Geral

| Controle | O que faz | Valores / padrão | Dica |
|---|---|---|---|
| Velocidade | Sensibilidade à força do toque (velocity), não uma velocidade de reprodução | 0 a 100%, padrão 70% | Em 0% todas as notas soam com o mesmo volume; em 100% o volume cresce com o quadrado da força (metade da força dá -12 dB) |
| Volume | Nível de saída do instrumento | 0 a 150%, padrão 80% | Muda sem degraus, mesmo com notas soando |

## Presets

O seletor de presets (categoria `SAMPLER`) tem cinco ajustes de envelope. Nenhum preset mexe no áudio escolhido, na `Nota base` nem na `Afinação`: elas pertencem ao áudio. Todo o resto volta ao padrão a cada preset, inclusive o `Modo` (ver [Presets](04-painel-de-instrumento.md#presets)).

| Preset | Ajustes | Caráter |
|---|---|---|
| Padrão | Tudo nos padrões | Ponto de partida: ataque de 2 ms, sustentação 100%, soltura de 200 ms |
| Instrumento | Ataque 3 ms, decaimento 500 ms, sustentação 100%, soltura 350 ms, `Velocidade` 80% | Áudio de uma nota tocado como teclado: soltura um pouco mais longa e resposta à força |
| Percussão (até o fim) | `Modo` `Até o fim`, ataque 0,5 ms, soltura 50 ms, `Velocidade` 80% | Golpes e vozes curtas: a nota sempre toca inteira, com ataque instantâneo |
| Pad lento | Ataque 0,8 s, decaimento 1 s, sustentação 90%, soltura 1,8 s, `Velocidade` 30% | Áudio longo que entra e sai devagar; pouca resposta à força |
| Pluck | Ataque 1 ms, decaimento 350 ms, sustentação 0%, soltura 250 ms, `Velocidade` 80% | Nota curta e seca, mesmo com tecla apertada |

O rótulo do seletor compara só os parâmetros de timbre: como a `Nota base` e a `Afinação` são ignoradas, o preset continua marcado mesmo depois de você mudá-las.

## Relação com os clipes de áudio

- **Mesmo depósito.** O sampler e os clipes de áudio usam a mesma lista de áudios do projeto, identificados pela impressão digital (SHA-256) do arquivo. Um áudio que você já importou para um clipe (ver [03 Áudio e clipes](03-audio-e-clipes.md)) aparece no menu do sampler, e um áudio importado pelo sampler entra na mesma lista de áudios do projeto. Arquivos idênticos são um só.
- **Importar pelo sampler não põe clipe no arranjo.** O `Importar um arquivo…` do sampler guarda o áudio no projeto e o liga ao sampler, sem criar nenhum clipe na linha do tempo.
- **Clipe toca uma vez numa posição; o sampler toca a cada nota.** Um clipe de áudio fica num ponto do arranjo, com fades e warp. Um sampler dispara o áudio sempre que uma nota (do piano roll, do teclado ou do MIDI) é tocada, e afina o áudio pela nota.
- **Áudio do sampler é usado na exportação.** O áudio escolhido entra na renderização da exportação junto com os clipes (ver [08 Exportação](08-exportacao.md)).
- **Não há sampler "a partir do clipe".** Não existe um comando que transforma um clipe já colocado no arranjo num sampler; o caminho é escolher o mesmo áudio no menu do sampler.

## Passo a passo

### Tocar uma nota gravada como instrumento

1. `Nova faixa` > `Sampler`. Abra o painel `Instrumento` (`I`).
2. No cartão `ÁUDIO`, clique em `Importar o áudio` e escolha o arquivo.
3. Descubra a altura do áudio (por exemplo, com o teclado da tela) e ponha o knob `Nota base` nela: se o áudio é um lá, `A3` ou `A4` conforme a oitava. Com o botão direito no knob, digite `A3`.
4. Toque o teclado da tela e confira que a nota base soa como o original (o ponto colorido marca a tecla).
5. Escolha o preset `Instrumento`, ou ajuste `Soltura` para o corte da nota ficar natural.

### Um golpe de percussão em qualquer nota

1. Importe o golpe (kick, palma, efeito) como acima.
2. Escolha o preset `Percussão (até o fim)`.
3. No piano roll, escreva o ritmo sempre na `Nota base` (C4 por padrão): a duração da nota não corta o áudio, só o começo importa.
4. Para variar o timbre, use notas mais agudas (a batida fica mais aguda e mais curta) ou graves (mais grave e mais longa).

### Um pad a partir de um som longo

1. Importe um som sustentado e ajuste a `Nota base`.
2. Escolha `Pad lento`.
3. Escreva acordes longos no piano roll. Como o áudio toca uma vez sem loop, a nota fica muda quando o áudio acaba: use um áudio mais longo que as notas.

### Trocar o áudio sem perder o timbre

1. Abra o menu do botão do arquivo e escolha outro áudio da lista, ou `Importar um arquivo…`.
2. O envelope, o `Modo` e o volume continuam; a `Nota base` e a `Afinação` também continuam: ajuste-as para o áudio novo.

## Combina com

- [04 Painel de instrumento](04-painel-de-instrumento.md): presets, teclado da tela, gestos dos knobs.
- [03 Áudio e clipes](03-audio-e-clipes.md): importar áudios, fades e ganho de clipes; os áudios do projeto são os mesmos que o sampler usa.
- [05 Piano roll](05-piano-roll.md): escrever as notas que disparam o áudio; use a grade e a faixa de velocidade.
- [06c Painel de efeitos](06c-painel-de-efeitos.md): efeitos da faixa (reverberação, filtro) sobre o sampler.
- [07 Automação](07-automacao.md): dá para automatizar `Volume`, `Afinação` e o envelope.
- [03b Warp e altura](03b-warp-e-altura.md): para esticar ou transpor um áudio sem mudar a duração, use um clipe de áudio, não o sampler.

## Limites e pegadinhas

- **Sem loop.** O áudio toca uma vez; para sustentar uma nota longa num áudio curto não há como repetir o trecho. Use um áudio mais longo ou repita as notas.
- **Sem recorte.** Não há controles de início e fim, nem de fatias: o áudio toca do começo ao fim. Recorte o arquivo antes de importar.
- **Um áudio só por faixa** e sem camadas por nota ou por força: cada faixa `Sampler` toca um único áudio.
- **Altura e duração andam juntas.** Tocar mais agudo encurta a nota; tocar mais grave a alonga. Acima de cerca de quatro oitavas da nota base (com o áudio na mesma taxa do motor), a velocidade de leitura para de subir, e as notas ainda mais agudas soam todas na mesma altura.
- **16 vozes.** Ao passar disso, a voz mais antiga (de preferência já solta) sai em um fade de 3 ms. Tocar a mesma nota de novo solta a anterior (que faz a `Soltura`) e começa uma nova.
- **`Até o fim` ignora a nota solta.** Nem o fim da nota no piano roll nem soltar a tecla cortam o áudio. Parar o transporte solta tudo com a `Soltura`, mesmo nesse modo.
- **Áudio fora do aparelho.** Um projeto aberto em outro aparelho pode mostrar `Este áudio não está neste aparelho. Importe o arquivo de novo para ouvi-lo.` até que o áudio chegue ou seja importado de novo. `(não confirmado)`: se ele chega sozinho pela sincronização.
- **Formatos.** A decodificação depende do navegador (ou do aparelho, no Android); um formato não suportado produz o aviso de erro acima.
- **O que é salvo.** O áudio escolhido, a `Nota base`, a `Afinação` e o resto dos knobs são guardados no projeto. O nome do preset não é.
- **O visor pode confundir**: a forma de onda é normalizada pelo pico, então um áudio muito baixo parece cheio; o volume real é o do arquivo.

## Atalhos

| Tecla | Ação |
|---|---|
| `I` | Abre e fecha o painel `Instrumento` |
| `Ctrl+K` | Liga o teclado do computador (`A` a `P` tocam a partir da oitava mostrada no botão da barra; `Z`/`X` mudam a oitava) |
| Segurar o visor da forma de onda | Toca o áudio na nota base |
| Botão direito no knob `Nota base` | Digitar o valor (aceita `C4`, `F#3`) |
