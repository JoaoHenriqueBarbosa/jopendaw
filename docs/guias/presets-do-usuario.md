# Presets do usuário

> Guardar com nome o som que você ajustou (um instrumento ou um efeito), chamá-lo em outra faixa ou projeto com dois toques e levá-lo a outro aparelho ou a um colega num arquivo `.jopreset`; cerca de 5 minutos para o primeiro preset e mais 5 para levar um a outro aparelho.

Tudo o que está aqui sai do código do app (commit `b39d3d4`; a posição da seção `MEUS PRESETS` no **topo** dos menus vem do commit `18c72f4`, da fase 13; os avisos do guardado, o backup e o `(editado)` que segue renomear e apagar vêm do `504b4b8`, da fase 14). O uso no Chrome foi relatado pela sessão de código (salvar `Meu baixo grave` e o preset aparecer marcado com o visto); o resto das receitas segue o comportamento lido do código e dos testes automáticos, e foi montado sem ouvir o resultado `(não confirmado ao ouvido)`. Os presets ficam **neste aparelho**: não sincronizam com a conta e não vão dentro do arquivo do projeto (ver [Limitações](#limitações-reais)).

## Ingredientes

| Recurso | Para quê aqui | Capítulo |
|---|---|---|
| Seletor de presets do instrumento (tooltip `Presets`; na bateria, `Kits de bateria`), seção `MEUS PRESETS` | Salvar, aplicar, renomear, exportar e apagar o timbre de um instrumento | [04 Painel de instrumento, Meus presets](../manual/04-painel-de-instrumento.md#meus-presets) |
| Menu de três pontos do cartão de efeito (tooltip `Presets e mais`), seção `MEUS PRESETS` | O mesmo para cada efeito | [06c Painel de efeitos, Presets do usuário](../manual/06c-painel-de-efeitos.md#presets-do-usuário) |
| `Baixo Moog` e os knobs do sintetizador | Ponto de partida do baixo da receita 1 | [04a Sintetizador](../manual/04a-sintetizador.md) |
| `Gate`, `EQ`, `Compressor` e `Reverb` | A cadeia vocal da receita 2 | [06d Referência dos efeitos](../manual/06d-efeitos-referencia.md), [Efeitos em combinação, receita 1](efeitos-em-combinacao.md#receita-1-cadeia-vocal-gate-eq-compressor-reverb) |
| `Exportar preset…` e `Importar preset…` | Levar os presets a outro aparelho ou a um colega (receita 3) | [04 Painel de instrumento](../manual/04-painel-de-instrumento.md#renomear-exportar-e-apagar) |

## Passo a passo

### Receita 1: salvar o som de um baixo que você ajustou

1. Crie uma faixa `Sintetizador`, tecle `I` para abrir o painel `Instrumento` e, no seletor de presets, escolha `Baixo Moog` (categoria `BAIXOS`, mono).
2. Ajuste do seu jeito. Valores de partida do [04a](../manual/04a-sintetizador.md#um-baixo-mono): `Sub` em 40%, `Ressonância` em 45%, `Corte` entre 300 e 500 Hz (por exemplo 400 Hz) e, para um baixo mais curto, `Sustentação` da `AMPLITUDE` em 40%. O seletor passa a mostrar `Baixo Moog (editado)`.
3. Abra o seletor de presets: a seção `MEUS PRESETS` é a **primeira** do menu, acima das sete categorias de fábrica, e não precisa de rolagem (antes da fase 13 ficava no fim do menu de uns 30 itens). Escolha `Salvar como preset…`, logo abaixo da lista dos seus.
4. Na janela `Salvar como preset`, digite `Meu baixo grave` no campo `Nome` e toque em `Salvar` (ou `Enter`). O preset entra na seção e o seletor mostra `Meu baixo grave`, com o visto na linha dele.
5. Numa segunda faixa `Sintetizador` (pode ser em outro projeto), abra o seletor e escolha `Meu baixo grave` na seção `MEUS PRESETS`, no topo. Todos os parâmetros do sintetizador vêm de uma vez e `Ctrl+Z` desfaz a troca.
6. Mexeu no baixo e gostou mais? Repita `Salvar como preset…` com o **mesmo** nome: a janela `Substituir o preset?` pergunta `Já existe um preset chamado "Meu baixo grave". Substituir pelos valores atuais?`; `Substituir` troca os valores e mantém o nome.

Valores que o preset leva: todos os parâmetros do sintetizador (osciladores, mistura, filtro, amplitude, envelope do filtro, LFO e `Geral`). Não leva as notas do clipe nem a automação; um knob automatizado entra com o valor fixo dele, não com a curva.

### Receita 2: montar uma cadeia vocal favorita (efeitos por tipo)

Cada efeito guarda o **seu** preset, por tipo: `Gate`, `EQ`, `Compressor` e `Reverb` são quatro presets, não um preset de cadeia. O nome pode repetir entre tipos (`Minha voz` no `Gate`, no `EQ` e no `Compressor`), já que a regra de nome único vale dentro de cada tipo.

1. Numa faixa de voz, tecle `F` e monte a cadeia como na [receita 1 de Efeitos em combinação](efeitos-em-combinacao.md#receita-1-cadeia-vocal-gate-eq-compressor-reverb): `Gate` (preset `Ruído de fundo`), `EQ` (`Voz presente`) e `Compressor` (`Voz`), nesta ordem, e o `Reverb` `Placa` num barramento com `Mistura` em 100%.
2. Ajuste cada um à sua voz: no `EQ`, o nó 3 em torno de 250 Hz (voz grave) ou 350 Hz (voz aguda); no `Compressor`, arraste o `Limiar` até o medidor marcar de −3 a −6 dB nas frases fortes.
3. No menu de três pontos do `Gate`, escolha `Salvar como preset…` e dê o nome `Minha voz`. Repita no `EQ` (as 8 bandas entram, com a `Saída`), no `Compressor` e no `Reverb` do barramento (a `Mistura` de 100% entra no preset).
4. Numa faixa de voz de outro projeto, tecle `F` e adicione `Gate`, `EQ` e `Compressor`, nesta ordem. Em cada cartão, abra o menu de três pontos e escolha `Minha voz` em `MEUS PRESETS`. O subtítulo do cartão passa a mostrar `Minha voz`. No barramento de retorno, adicione o `Reverb` e escolha o `Minha voz` dele.
5. O `Sidechain` do `Compressor` e do `Gate` **não** entra no preset: se a sua cadeia usa uma faixa-chave, escolha-a de novo em cada projeto ([06c, sidechain](../manual/06c-painel-de-efeitos.md#escolher-a-faixa-chave-de-um-compressor-sidechain)). Também não entram o bypass, a posição do cartão na cadeia nem o roteamento (`Envio` da faixa e o barramento): a ordem e o retorno você refaz à mão.

### Receita 3: levar presets para outro aparelho ou para um colega

Os presets não sobem para a nuvem. O caminho é um arquivo `.jopreset` por preset.

1. No aparelho de origem, abra o menu de presets (do instrumento ou do efeito), toque no `…` (tooltip `Renomear, apagar ou exportar`) da linha do preset e escolha `Exportar preset…`. No navegador o arquivo `Meu baixo grave.jopreset` é baixado direto para a pasta de downloads; no Android abre o "salvar como" do sistema; se você cancelar ali, a janela `Exportação cancelada` diz que o preset não foi exportado `(testado só por testes automáticos)`.
2. Repita para cada preset que quer levar (a cadeia vocal são quatro arquivos). Leve os arquivos como levaria qualquer outro: e-mail, mensageiro, pendrive, nuvem de arquivos.
3. No aparelho de destino, abra o menu de presets do **mesmo tipo** de instrumento ou de efeito e escolha `Importar preset…`. No seletor (título `Importar preset`), escolha o arquivo `.jopreset` (o seletor também aceita `.json`). O app usa só o primeiro arquivo escolhido: um por vez.
4. Sem ressalvas, o preset entra em silêncio: confira na seção `MEUS PRESETS`. Se o nome já existia no destino, ele entra como `Nome (2)` e a janela `Preset "Nome (2)" importado` avisa. Se o arquivo era de outro tipo (um preset de `reverb` importado pelo menu do `Gate`), ele é guardado no tipo dele e a janela avisa `O preset é de outro tipo (Reverb): ele foi guardado, mas só aparece no menu desse tipo.` (o nome do tipo vem em português).
5. Aplique o preset numa faixa do tipo certo e confira o rótulo do seletor: com os valores idênticos aos do arquivo, ele mostra o nome do preset.

Para um colega, o arquivo é o mesmo: o `.jopreset` é um JSON pequeno e legível (o formato está em [dev 10, Presets do usuário](../dev/10-app-flutter.md#presets-do-usuário-user_presetsdart-user_presets_uidart)). Ele recusa arquivo com mais de 256 KB e de versão mais nova do app (`O preset é de uma versão mais nova do jopendaw. Atualize o app para importá-lo.`).

## Variações

- **Um preset por função, não por música.** `Baixo curto`, `Baixo longo`, `Pad largo`, `Lead com scoop`: no menu eles aparecem na ordem em que você os criou, depois dos de fábrica, e as setas anterior e próximo (só no computador) passam por eles.
- **Bateria:** `Salvar como preset…` no seletor `Kits de bateria` guarda os 49 valores (as 12 peças e o `Volume` geral). Seus kits ficam depois dos 7 de fábrica.
- **Sampler:** o preset leva só o timbre (`Modo`, envelope, `Sens. vel.`, `Volume`, bend e vibrato). Guardar um `Ataque` e uma `Soltura` que você usa sempre funciona; o áudio e as zonas ficam de fora (ver [Limitações](#limitações-reais)).
- **Ponto de partida a partir de um preset de fábrica:** aplique o de fábrica, ajuste e salve com outro nome; o de fábrica continua lá.
- **Renomear e arrumar:** `…` da linha, `Renomear…` (título `Renomear preset`) e `Apagar…` (`Apagar o preset?`, sem desfazer). Renomear e apagar não entram no `Ctrl+Z` do projeto.
- **Cópia de segurança:** exporte os presets de que não abre mão. Se o navegador recusar a gravação, o menu de presets mostra um aviso em vermelho e os presets valem só até fechar o app (ver [Avisos do guardado](#avisos-do-guardado)).

## Por que funciona

- **O preset guarda valores, não uma ligação.** Aplicar copia todos os parâmetros do tipo para a faixa (o instrumento volta ao padrão e recebe os valores por cima). Por isso o projeto soa igual em outro aparelho mesmo sem o preset lá, e apagar um preset não muda faixa nenhuma.
- **Tudo o que é do tipo entra, menos o que é do projeto.** `Nota base` e `Afinação` do sampler pertencem ao áudio da faixa; o `Sidechain` é uma faixa do projeto atual. Por isso ficam de fora e continuam como estão ao aplicar.
- **Um tipo, uma lista.** O preset de um `Reverb` só aparece no menu do `Reverb`. Isso evita aplicar parâmetros de um efeito em outro, e é o motivo de não haver um "preset de cadeia".
- **O arquivo é o transporte.** Sem servidor nem conta no meio, o `.jopreset` viaja como qualquer arquivo, e a importação valida tudo (versão, tipo, faixas de valor) antes de aceitar.

## Limitações reais

- **Só neste aparelho.** Na web, os presets ficam no IndexedDB do site (banco `jopendaw`); no Android, num arquivo do app. Outro navegador, outro perfil, janela anônima, limpar os dados do site ou desinstalar o app começam sem presets. Não sincronizam com a conta e não entram no `.jopendaw` do projeto ([Backup e levar o projeto para outro aparelho](backup-e-levar-projeto-para-outro-aparelho.md) cobre o projeto, não os presets).
- **Global por aparelho.** Os presets ficam na chave `userpresets`, sem id de conta: quem entra com outra conta no mesmo aparelho vê os mesmos presets. Proposta, não feita: prefixar a chave com o id do usuário (`userpresets:<id>`) e migrar a chave antiga na primeira abertura; não foi feito porque `Session.user` chega depois do carregamento e o guardado do documento também é por aparelho.
- **A cópia de um arquivo ilegível não tem tela.** O app guarda o conteúdo em `userpresets.bak`, mas não há botão para abri-lo ou restaurá-lo (ver [Avisos do guardado](#avisos-do-guardado)).
- **Sampler sem áudio e sem zonas.** O preset do sampler é só timbre; um multi-sample não viaja pelo preset.
- **Sem preset de cadeia.** Um preset por efeito; a ordem, o bypass, o `Sidechain` e os envios são refeitos à mão.
- **A seção `MEUS PRESETS` ficava no fim do menu: resolvido na fase 13 (`18c72f4`).** Ela, `Salvar como preset…` e `Importar preset…` agora abrem no topo dos menus de instrumento e de efeito. O inverso passa a valer: com muitos presets seus, os de fábrica descem e o menu (460 px de altura máxima no instrumento, 680 px no efeito) precisa rolar para chegar neles.
- **Máximo de 300 presets por tipo** e nomes de até 60 caracteres, únicos por tipo sem diferenciar maiúsculas.
- **Um arquivo por vez** na importação (só o primeiro arquivo escolhido é lido).
- **Android e o seletor de arquivos reais:** `(testado só por testes automáticos)`, com o seletor e o "salvar como" simulados; não foi visto no aparelho.

## Se der errado

- **Não acho `Salvar como preset…`:** ele fica no topo do menu, logo abaixo da lista de `MEUS PRESETS` (ou de `Nenhum ainda`). Com muitos presets seus, a lista deles empurra o item para baixo: role o menu.
- **O botão `Salvar` está apagado:** o nome está vazio (ou só tinha espaços). O campo não deixa entrar marcas invisíveis (largura zero, direção do texto), então o nome guardado é o que você vê.
- **`Nome em uso` ao renomear:** já existe outro preset do mesmo tipo com esse nome (maiúsculas não contam).
- **`Limite de 300 presets para este tipo. Apague algum antes.`:** apague os que não usa (`…`, `Apagar…`).
- **A importação disse `Não foi possível importar`:** leia o motivo na janela: `O arquivo não é um preset do jopendaw.` (outro tipo de arquivo), `(não é um JSON válido)` (arquivo cortado ou editado), versão mais nova, `Tipo de preset desconhecido`, `O preset não tem nenhum valor utilizável para este tipo.` ou `O arquivo é grande demais para ser um preset.`
- **A importação avisou `N valores fora da faixa foram limitados`:** o arquivo tinha valores que o parâmetro não aceita (por exemplo, editado à mão); eles foram encostados no limite.
- **Importei e não vi nada:** sem avisos não abre janela. Olhe `MEUS PRESETS` do tipo certo; se o arquivo era de outro tipo, a janela teria avisado, e o preset está no menu desse outro tipo.
- **O preset sumiu:** outro navegador ou perfil, dados do site apagados, ou o app não conseguiu gravar (o menu avisaria, em vermelho, com `Não deu para guardar seus presets neste aparelho.`). Importe de novo do `.jopreset`.
- **O menu mostra uma linha vermelha no topo:** é um aviso do guardado; a tabela em [Avisos do guardado](#avisos-do-guardado) diz o que cada texto significa.
- **O seletor mostra `Nome (editado)` depois de eu renomear ou apagar o preset:** renomear atualiza o nome no `(editado)` e apagar o faz sumir; se ainda vê o nome antigo, feche e reabra o painel `(testado só por testes automáticos)`.
- **O seletor de uma faixa nova diz `Inicial` mesmo eu tendo salvo um preset todo no padrão:** é o esperado: numa faixa nova vale `Inicial`; o seu preset segue marcado com o visto no menu e passa a dar o nome ao rótulo quando você o aplica.
- **O seletor mostra `Personalizado` depois de reabrir o projeto:** o `(editado)` não é salvo com o projeto. Os valores continuam lá; se baterem com um preset, o nome dele aparece.
- **Apliquei um preset de sampler e o áudio não veio:** o preset do sampler não leva áudio nem zonas; escolha o áudio no cartão `Áudio` e refaça as zonas.

## Avisos do guardado

Quando o app não consegue guardar ou ler os seus presets, mostra uma linha **em vermelho** no topo do menu de presets (acima de `MEUS PRESETS`, no instrumento e no efeito) e, depois de salvar, renomear, apagar ou importar, a janela `Presets não guardados` com o mesmo texto. O aviso vale até fechar o app `(testado só por testes automáticos)`.

| Aviso | O que houve | O que fazer |
|---|---|---|
| `Não deu para guardar seus presets neste aparelho.` | O guardado local recusou a gravação (cota do navegador, disco cheio). Os presets seguem na memória | Exporte os que importam (`Exportar preset…`) e libere espaço; uma gravação seguinte que der certo tira o aviso |
| `Não deu para ler seus presets guardados neste aparelho. O que você salvar agora vale só até fechar o app.` | Não foi possível ler o que estava guardado; por segurança nada é gravado por cima | Exporte o que criar nesta sessão |
| `O arquivo dos seus presets estava ilegível. Guardei uma cópia dele (userpresets.bak) e a lista começou vazia.` | O conteúdo guardado estava corrompido (ou não era do app). A cópia vai para `userpresets.bak` (se já havia outra cópia diferente, `userpresets.bak.` e um número) antes de qualquer gravação por cima; o que você salvar depois é gravado normalmente | Reimporte os `.jopreset` que tiver; a cópia fica no guardado do aparelho, sem tela para abri-la |
| `O arquivo dos seus presets está ilegível e não deu para guardar uma cópia dele. Nada será gravado por cima; o que você salvar vale só até fechar o app.` | Ilegível e a cópia também falhou | Exporte o que criar nesta sessão |
| `Seus presets foram guardados por uma versão mais nova do app. Aqui eles ficam só para leitura: o que você salvar, renomear ou apagar vale só até fechar o app.` | Você voltou a um app mais antigo que o que escreveu o arquivo. Os presets legíveis aparecem e podem ser aplicados; nada é sobrescrito | Use o app mais novo para gravar; aqui, exporte o que criar |

No aviso do arquivo ilegível a janela `Presets não guardados` também abre depois de cada ação, embora a gravação funcione: o título é mais assustador que o caso.

## O que mudou no rótulo e no campo de nome (fase 14)

- **`(editado)`** segue o renomear do preset aplicado e some ao apagá-lo.
- **`Inicial`** vale numa faixa nova mesmo que exista um preset seu com todos os valores no padrão.
- O campo de nome não aceita marcas de largura zero nem de direção (U+200B a U+200F, U+202A a U+202E, U+FEFF): o nome guardado é o digitado.
- O aviso de importação de outro tipo usa o nome em português (`Reverb`, `Sintetizador`).
- Cancelar o `salvar como` da exportação (Android) mostra `Exportação cancelada`.
