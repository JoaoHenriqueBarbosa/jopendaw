# Guia de escrita da documentação

Vale para tudo em `docs/`. Quem escreve (pessoa ou agente) segue isto.

## Regras gerais

1. **Português do Brasil com acentos completos.** Identificadores de código, nomes de arquivo e chamadas do motor ficam em inglês, entre crases.
2. **Só o que existe.** Cada botão, campo, atalho, parâmetro e faixa de valores vem da leitura do código-fonte (Flutter em `app/lib/`, motor em `engine/src/`, servidor em `server/src/`). Nada de inventar recurso nem "provavelmente". Se não deu para confirmar, escreva `(não confirmado)` ao lado.
3. **Nome de tela é o nome de verdade.** Use exatamente o texto do rótulo, do tooltip ou do item de menu que aparece na interface (ex.: `Nova faixa`, `Inserir acorde…`). Quando o rótulo só aparece em tooltip, diga "tooltip".
4. **Um capítulo por assunto, todo botão coberto.** Nada de "e outros controles". Se há 8 knobs, são 8 linhas.
5. **Valores reais.** Faixa, unidade, padrão e escala de cada controle (ex.: `Corte: 20 Hz–20 kHz, padrão 8 kHz, escala logarítmica`). Os padrões estão nas tabelas `ParamSpec` de `app/lib/daw/instruments.dart` e `effects.dart`, e nas constantes do motor.
6. **Sem repetir o código.** Explique o efeito para quem faz música, não o que a linha faz.
7. **Links relativos** entre capítulos (`../manual/06-mixer.md`). Links para código como `app/lib/daw/timeline.dart` (sem número de linha nos manuais; nas docs técnicas pode citar `arquivo:linha`).
8. Sem emojis. Sem trailers de assinatura em nada. Não commitar: quem coordena commita.

## Molde de um capítulo do manual (`docs/manual/`)

```
# Título do assunto

> Uma frase: para que serve este assunto e quando usar.

## Onde fica
Caminho até chegar lá na interface (barra, painel, menu), no computador e no celular quando diferir.

## Controles
Tabela: | Controle (rótulo exato) | O que faz | Valores / padrão | Dica |
(uma tabela por seção da tela)

## Passo a passo
Tarefas comuns numeradas (3 a 6 passos cada).

## Combina com
Links para outros capítulos e para os guias em `../guias/`, dizendo por que combinam.

## Limites e pegadinhas
O que não faz, o que surpreende, diferenças entre web e Android, o que é salvo e o que não é.

## Atalhos
Tabela tecla → ação (só as que valem neste assunto).
```

## Molde de um capítulo técnico (`docs/dev/`)

```
# Título

> Escopo em uma frase e para quem é (quem mexe no motor, no app, no servidor).

## Visão geral         (diagrama ASCII ou mermaid quando ajudar)
## Peças e responsabilidades   (arquivo → papel)
## Fluxo de dados / ciclo de vida
## Contratos            (formatos, ids, chamadas, JSON, rotas)
## Decisões e por quê
## Como testar
## Armadilhas conhecidas
```

## Molde de um guia de combinações (`docs/guias/`)

```
# Nome da receita

> Resultado que se quer, em uma frase, e em quanto tempo se faz.

## Ingredientes      (recursos usados, com link para o capítulo de cada um)
## Passo a passo     (com valores concretos de parâmetros)
## Variações
## Por que funciona  (o raciocínio, para o leitor reaproveitar em outros casos)
## Se der errado
```
