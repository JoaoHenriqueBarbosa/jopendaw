# Presets do usuário

> Guardar com nome o som que você ajustou (um instrumento ou um efeito), chamá-lo em outra faixa ou projeto com dois toques e levá-lo a outro aparelho ou a um colega num arquivo `.jopreset`; cerca de 5 minutos para o primeiro preset e mais 5 para levar um a outro aparelho.

Tudo o que está aqui sai do código do app (commit `b39d3d4`; a posição da seção `MEUS PRESETS` no **topo** dos menus vem do commit `18c72f4`, da fase 13). O uso no Chrome foi relatado pela sessão de código (salvar `Meu baixo grave` e o preset aparecer marcado com o visto); o resto das receitas segue o comportamento lido do código e dos testes automáticos, e foi montado sem ouvir o resultado `(não confirmado ao ouvido)`. Os presets ficam **neste aparelho**: não sincronizam com a conta e não vão dentro do arquivo do projeto (ver [Limitações](#limitações-reais)).

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

1. No aparelho de origem, abra o menu de presets (do instrumento ou do efeito), toque no `…` (tooltip `Renomear, apagar ou exportar`) da linha do preset e escolha `Exportar preset…`. No navegador o arquivo `Meu baixo grave.jopreset` é baixado direto para a pasta de downloads; no Android abre o "salvar como" do sistema.
2. Repita para cada preset que quer levar (a cadeia vocal são quatro arquivos). Leve os arquivos como levaria qualquer outro: e-mail, mensageiro, pendrive, nuvem de arquivos.
3. No aparelho de destino, abra o menu de presets do **mesmo tipo** de instrumento ou de efeito e escolha `Importar preset…`. No seletor (título `Importar preset`), escolha o arquivo `.jopreset` (o seletor também aceita `.json`). O app usa só o primeiro arquivo escolhido: um por vez.
4. Sem ressalvas, o preset entra em silêncio: confira na seção `MEUS PRESETS`. Se o nome já existia no destino, ele entra como `Nome (2)` e a janela `Preset "Nome (2)" importado` avisa. Se o arquivo era de outro tipo (um preset de `reverb` importado pelo menu do `Gate`), ele é guardado no tipo dele e a janela avisa `O preset é de outro tipo (reverb): ele foi guardado, mas só aparece no menu desse tipo.`
5. Aplique o preset numa faixa do tipo certo e confira o rótulo do seletor: com os valores idênticos aos do arquivo, ele mostra o nome do preset.

Para um colega, o arquivo é o mesmo: o `.jopreset` é um JSON pequeno e legível (o formato está em [dev 10, Presets do usuário](../dev/10-app-flutter.md#presets-do-usuário-user_presetsdart-user_presets_uidart)). Ele recusa arquivo com mais de 256 KB e de versão mais nova do app (`O preset é de uma versão mais nova do jopendaw. Atualize o app para importá-lo.`).

## Variações

- **Um preset por função, não por música.** `Baixo curto`, `Baixo longo`, `Pad largo`, `Lead com scoop`: no menu eles aparecem na ordem em que você os criou, depois dos de fábrica, e as setas anterior e próximo (só no computador) passam por eles.
- **Bateria:** `Salvar como preset…` no seletor `Kits de bateria` guarda os 49 valores (as 12 peças e o `Volume` geral). Seus kits ficam depois dos 7 de fábrica.
- **Sampler:** o preset leva só o timbre (`Modo`, envelope, `Sens. vel.`, `Volume`, bend e vibrato). Guardar um `Ataque` e uma `Soltura` que você usa sempre funciona; o áudio e as zonas ficam de fora (ver [Limitações](#limitações-reais)).
- **Ponto de partida a partir de um preset de fábrica:** aplique o de fábrica, ajuste e salve com outro nome; o de fábrica continua lá.
- **Renomear e arrumar:** `…` da linha, `Renomear…` (título `Renomear preset`) e `Apagar…` (`Apagar o preset?`, sem desfazer). Renomear e apagar não entram no `Ctrl+Z` do projeto.
- **Cópia de segurança:** exporte os presets de que não abre mão. Se o navegador recusar a gravação, o app não avisa e os presets somem ao fechar (ver a seção abaixo).

## Por que funciona

- **O preset guarda valores, não uma ligação.** Aplicar copia todos os parâmetros do tipo para a faixa (o instrumento volta ao padrão e recebe os valores por cima). Por isso o projeto soa igual em outro aparelho mesmo sem o preset lá, e apagar um preset não muda faixa nenhuma.
- **Tudo o que é do tipo entra, menos o que é do projeto.** `Nota base` e `Afinação` do sampler pertencem ao áudio da faixa; o `Sidechain` é uma faixa do projeto atual. Por isso ficam de fora e continuam como estão ao aplicar.
- **Um tipo, uma lista.** O preset de um `Reverb` só aparece no menu do `Reverb`. Isso evita aplicar parâmetros de um efeito em outro, e é o motivo de não haver um "preset de cadeia".
- **O arquivo é o transporte.** Sem servidor nem conta no meio, o `.jopreset` viaja como qualquer arquivo, e a importação valida tudo (versão, tipo, faixas de valor) antes de aceitar.

## Limitações reais

- **Só neste aparelho.** Na web, os presets ficam no IndexedDB do site (banco `jopendaw`); no Android, num arquivo do app. Outro navegador, outro perfil, janela anônima, limpar os dados do site ou desinstalar o app começam sem presets. Não sincronizam com a conta e não entram no `.jopendaw` do projeto ([Backup e levar o projeto para outro aparelho](backup-e-levar-projeto-para-outro-aparelho.md) cobre o projeto, não os presets).
- **Sem aviso se a gravação falhar.** O app guarda o erro internamente, mas nenhuma tela o mostra.
- **Sampler sem áudio e sem zonas.** O preset do sampler é só timbre; um multi-sample não viaja pelo preset.
- **Sem preset de cadeia.** Um preset por efeito; a ordem, o bypass, o `Sidechain` e os envios são refeitos à mão.
- **A seção `MEUS PRESETS` ficava no fim do menu: resolvido na fase 13 (`18c72f4`).** Ela, `Salvar como preset…` e `Importar preset…` agora abrem no topo dos menus de instrumento e de efeito. O inverso passa a valer: com muitos presets seus, os de fábrica descem e o menu (460 px de altura máxima no instrumento, 680 px no efeito) precisa rolar para chegar neles.
- **Máximo de 300 presets por tipo** e nomes de até 60 caracteres, únicos por tipo sem diferenciar maiúsculas.
- **Um arquivo por vez** na importação (só o primeiro arquivo escolhido é lido).
- **Android e o seletor de arquivos reais:** `(testado só por testes automáticos)`, com o seletor e o "salvar como" simulados; não foi visto no aparelho.

## Se der errado

- **Não acho `Salvar como preset…`:** ele fica no topo do menu, logo abaixo da lista de `MEUS PRESETS` (ou de `Nenhum ainda`). Com muitos presets seus, a lista deles empurra o item para baixo: role o menu.
- **O botão `Salvar` está apagado:** o nome está vazio (ou só tinha espaços e caracteres invisíveis).
- **`Nome em uso` ao renomear:** já existe outro preset do mesmo tipo com esse nome (maiúsculas não contam).
- **`Limite de 300 presets para este tipo. Apague algum antes.`:** apague os que não usa (`…`, `Apagar…`).
- **A importação disse `Não foi possível importar`:** leia o motivo na janela: `O arquivo não é um preset do jopendaw.` (outro tipo de arquivo), `(não é um JSON válido)` (arquivo cortado ou editado), versão mais nova, `Tipo de preset desconhecido`, `O preset não tem nenhum valor utilizável para este tipo.` ou `O arquivo é grande demais para ser um preset.`
- **A importação avisou `N valores fora da faixa foram limitados`:** o arquivo tinha valores que o parâmetro não aceita (por exemplo, editado à mão); eles foram encostados no limite.
- **Importei e não vi nada:** sem avisos não abre janela. Olhe `MEUS PRESETS` do tipo certo; se o arquivo era de outro tipo, a janela teria avisado, e o preset está no menu desse outro tipo.
- **O preset sumiu:** outro navegador ou perfil, dados do site apagados, ou o app não conseguiu gravar (sem aviso). Importe de novo do `.jopreset`.
- **O seletor mostra `Nome (editado)` de um preset que apaguei ou renomeei:** o painel guarda o último nome aplicado até você fechá-lo; é só o rótulo (achado sem correção no app).
- **O seletor mostra `Personalizado` depois de reabrir o projeto:** o `(editado)` não é salvo com o projeto. Os valores continuam lá; se baterem com um preset, o nome dele aparece.
- **Apliquei um preset de sampler e o áudio não veio:** o preset do sampler não leva áudio nem zonas; escolha o áudio no cartão `Áudio` e refaça as zonas.

## Correções da fase 14

- **Não deu para guardar:** se o guardado local recusa a gravação, o menu de presets mostra em vermelho `Não deu para guardar seus presets neste aparelho.` e a ação (salvar, renomear, apagar, importar) abre uma janela `Presets não guardados`. Os presets seguem na memória até fechar o app.
- **Arquivo ilegível:** a cópia do conteúdo ilegível vai para a chave `userpresets.bak` antes de qualquer gravação (se já há outra cópia diferente, `userpresets.bak.<ms>`), e o menu avisa.
- **Arquivo de versão mais nova** (você voltou a um app antigo): os presets legíveis aparecem, mas o arquivo fica só para leitura: salvar, renomear e apagar valem só até fechar o app, e o menu avisa. Nada é sobrescrito.
- **`(editado)`** segue o renomear e some ao apagar o preset aplicado.
- **`Inicial`** vale numa faixa nova mesmo que exista um preset seu com todos os valores no padrão.
- O campo de nome não aceita marcas de largura zero nem de direção (U+200B..U+200F, U+202A..U+202E, U+FEFF): o nome guardado é o digitado.
- O aviso de importação de outro tipo usa o nome em português (`Reverb`, `Sintetizador`).
- Cancelar o `salvar como` da exportação (Android) mostra `Exportação cancelada`.
- **Global por aparelho:** os presets ficam na chave `userpresets`, sem id de conta: quem entra com outra conta no mesmo aparelho vê os mesmos presets. Proposta, não feita: prefixar a chave com o id do usuário (`userpresets:<id>`) e migrar a chave antiga na primeira abertura; não foi feito porque `Session.user` chega depois do carregamento e o guardado do documento também é por aparelho.
