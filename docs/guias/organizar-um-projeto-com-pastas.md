# Organizar um projeto com pastas

> Reunir faixas em pastas para tratá-las como um só instrumento (compressor na bateria, reverb no coro) e recolher o que não se está mexendo para navegar num projeto grande; cerca de 10 minutos por cenário.

Os números são pontos de partida musicais; ajuste de ouvido. Rótulos, menus e faixas de valor vêm do código. Nada abaixo foi ouvido por quem escreveu: o comportamento das pastas está `(testado só por testes automáticos)`.

## Ingredientes

| Recurso | Para quê aqui | Capítulo |
|---|---|---|
| Menu da faixa, `Agrupar em pasta…` | Criar a pasta com as faixas marcadas | [02c Pastas de faixa](../manual/02c-pastas-de-faixa.md#diálogo-agrupar-em-pasta) |
| Linha da pasta: seta, `M`, `S`, `Efeitos da pasta`, volume | Tratar o conjunto e recolher | [02c, cabeçalho da pasta](../manual/02c-pastas-de-faixa.md#cabeçalho-da-pasta) |
| Painel `Efeitos` na pasta | Compressor, EQ e reverb sobre a soma das faixas | [06c Painel de efeitos](../manual/06c-painel-de-efeitos.md#efeitos-numa-pasta-de-faixas) · [06d Referência dos efeitos](../manual/06d-efeitos-referencia.md) |
| Mixer: barra `Grupo`, envios, saída | Conferir o grupo e mandar as faixas ao retorno de reverb | [06 Mixer](../manual/06-mixer.md) |
| Solo e mudo da pasta | Ouvir o grupo sozinho ou uma faixa dele | [02c, solo](../manual/02c-pastas-de-faixa.md#solo-da-pasta-e-solo-das-faixas) |
| `Recolher a pasta` / `Recolher todas as pastas` | Navegar num projeto grande | [02c, recolher e expandir](../manual/02c-pastas-de-faixa.md#recolher-e-expandir) |
| Stems | Exportar o grupo (e as faixas dele) | [08 Exportação](../manual/08-exportacao.md#stems) |

## Passo a passo

### 1. Bateria em várias faixas, com compressor no grupo

O resultado: bumbo, caixa e chimbal em faixas separadas, com um volume e um compressor só para o conjunto.

1. No cabeçalho da faixa do bumbo, menu de três pontos, `Agrupar em pasta…`.
2. Em `Nome da pasta`, digite `Bateria`. Marque as caixas da caixa e do chimbal (`Faixas da pasta (3 de N)`). Toque em `Agrupar`.
3. Em cada faixa dela, ajuste o nível **entre si** (bumbo perto de −10 dB, caixa e chimbal mais baixos): é o equilíbrio interno.
4. Na linha `Bateria`, toque em `Efeitos da pasta`, `Adicionar efeito`, `Compressor`. Preset `Bateria cola` (−16 dB, 2:1, `Ataque` 30 ms, `Soltura` 200 ms). Toque em loop e ajuste o `Limiar` até o medidor de redução marcar 2 a 4 dB nos golpes fortes.
5. Compare ligando e desligando o efeito; use `Ganho` para repor o nível.
6. Mexa no volume da linha `Bateria` para acertar o grupo contra o resto da mix, sem mexer nos faders internos.
7. Confira com `S` na pasta (só a bateria) e depois `S` só na caixa (a caixa e a pasta soam; as outras faixas da pasta calam).

### 2. Coro de vozes, com reverb no grupo

O resultado: três vozes de coro compartilhando um espaço, e um só botão para o nível do coro.

1. Agrupe as três faixas de coro numa pasta chamada `Coro`.
2. Pan de cada voz no mixer: uma em `E30`, outra em `C`, outra em `D30`.
3. Nas faixas do coro, **não** ponha envio para o retorno de reverb do projeto se quiser o espaço só no grupo (o reverb da pasta é um insert, não um retorno).
4. Na pasta, `Efeitos da pasta`, `Adicionar efeito`, `Reverb`, preset `Sala` (`Mistura` 22%, `Pré-atraso` 15 ms, `Decaimento` 1,4 s). Como o reverb está num insert, a `Mistura` fica baixa (20 a 30%): 100% só se usa em retorno. Se quiser mais cauda, suba a `Mistura` aos poucos.
5. Ponha antes dele um `EQ` com `Passa-alta` em 120 Hz, para o grupo não encher o grave.
6. Baixe o volume da linha `Coro` até ele entrar atrás da voz principal. Automatize esse volume, se quiser o coro subindo no refrão: botão `Automação` da barra em `Toque` e arraste o volume da pasta com a música tocando ([07 Automação](../manual/07-automacao.md#gravar-automação)).

### 3. Projeto grande, recolhido para navegar

O resultado: 20 faixas viram cinco linhas, e você vai direto ao que quer mexer.

1. Crie uma pasta por família: `Bateria`, `Baixos`, `Guitarras`, `Vozes`, `Sintes`. Faixas de retorno (reverb, delay) e barramentos ficam de fora: não entram em pasta.
2. Numa das linhas, menu `Opções da pasta`, `Recolher todas as pastas` (o item só aparece com mais de uma pasta).
3. Cada linha recolhida mostra uma miniatura dos clipes das faixas, com o zoom e a rolagem da timeline. Use para ver onde cada família entra e sai.
4. Para mexer numa família, `Expandir a pasta` (a seta). Se a faixa selecionada estava escondida quando você recolheu, a seleção foi para a pasta.
5. O mixer continua mostrando todos os canais, com a barra `Grupo` sobre cada família.
6. Recolher e expandir não entram no desfazer e ficam salvos no projeto.

## Variações

- **Reverb comum às pastas:** em vez de um reverb por pasta, monte um retorno ([Mixagem e automação, passo 2](mixagem-e-automacao.md#2-criar-um-barramento-de-reverb-compartilhado)) e use os envios das faixas. O retorno precisa vir **depois** das pastas na lista; o retorno novo já entra no fim.
- **Pasta com sidechain:** compressor de um baixo com `Sidechain` na faixa do bumbo continua valendo com as duas em pastas diferentes (a faixa do bumbo é uma faixa normal); ver [Efeitos em combinação, receita 3](efeitos-em-combinacao.md#receita-3-sidechain-pumping-com-o-bumbo) `(não confirmado com pastas)`.
- **Stems por grupo:** exporte com `Stems` ligado; a pasta gera o stem `<projeto> - Bateria.wav` com o compressor e o volume dela, e as faixas geram os stems delas sem eles.
- **Mover a faixa de família:** `Mover para a pasta "Nome"` no menu da faixa, ou arraste o cabeçalho dela para entre duas faixas da pasta. Se a faixa saía para outro barramento, o app pergunta antes de trocar a saída (`Mover "Nome" para a pasta "Pasta"?`).
- **Desfazer a pasta:** `Desagrupar…` mantém as faixas e, se a pasta tem efeitos, automação ou envios, mantém também o barramento com as faixas saindo nele (o compressor continua no som). Para tirar a pasta **e** o efeito dela, `Apagar a pasta (as faixas ficam)…`: as faixas ficam soltas, saindo no `Master`.

## Por que funciona

A pasta é um barramento: a saída de cada faixa vai para ela, então o que você pôr na cadeia dela age sobre a **soma**, e o compressor "cola" o conjunto em vez de comprimir cada faixa à parte. O volume e o mudo da pasta mexem no conjunto sem tocar nos faders internos. Já os envios das faixas para um retorno saem da faixa, direto, sem passar pela pasta; por isso o volume da pasta não muda a quantidade de reverb de retorno (a proporção fica como você ajustou). Recolher é só arrumação: o som e a automação seguem iguais, e a miniatura da linha da pasta dá a ideia do arranjo.

## Se der errado

| Sintoma | Causa provável | O que fazer |
|---|---|---|
| Mudei o volume ou o `M` da pasta e o reverb do retorno continua | Os envios saem das faixas, não da pasta | Baixe os envios, ou dê `M` nas faixas |
| O item `Agrupar em pasta…` abre `Não dá para agrupar` | A faixa é um barramento | Só faixas de áudio e de instrumento entram |
| A faixa não aparece na lista do diálogo | Já está numa pasta | `Tirar da pasta` antes, ou `Mover para a pasta "Nome"` |
| Depois de `Desagrupar…` o efeito da pasta continua no som | Com efeitos, automação ou envios, o barramento fica e as faixas seguem saindo nele | Se não quer o efeito, `Ctrl+Z` e use `Apagar a pasta (as faixas ficam)…`, ou mande as faixas ao `Master` pelo botão de saída do mixer |
| Mudei a saída de uma faixa da pasta no mixer e ela saiu da pasta | Fora da pasta ela não passaria mais pelo volume nem pelos efeitos dela; o app avisa antes (`Tirar "Nome" da pasta?`) | `Cancelar`, ou `Ctrl+Z` depois; para manter a faixa no grupo, deixe a saída dela na pasta |
| Uma faixa congelada (`(áudio)`) e a original | A congelada entra na mesma pasta, logo abaixo da original (a original fica muda) | Nada a arrumar; apague uma das duas se não precisar |
| `Mover a faixa?`, `Agrupar as faixas?` ou `Tirar "Nome" da pasta?` avisam que uma saída vai mudar | A faixa entra ou sai de uma pasta (ou a pasta passaria de um barramento que ela alimenta) e tinha outra saída | `Cancelar`, ou confirme e `Ctrl+Z` se não gostar |
| Recolhi e não vi o retângulo da gravação | Faixas armadas dentro de pasta recolhida não desenham a gravação | Expanda a pasta antes de gravar |
