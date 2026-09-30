# Documentação do jopendaw

DAW completo que roda no navegador e no Android: o mesmo app Flutter e o mesmo motor de áudio em Rust nos dois, com sincronização opcional pela nuvem. Esta pasta reúne o manual de uso, os guias de combinações e a documentação técnica. Ela acompanha o código: quando uma feature sai, o capítulo dela sai junto.

Convenções de escrita: [`_estilo.md`](_estilo.md).

## Para quem usa

Comece por aqui, na ordem:

| Capítulo | Assunto |
|---|---|
| [00 Visão geral](manual/00-visao-geral.md) | Mapa da tela, conceitos e glossário |
| [01 Projetos, modelos e conta](manual/01-projetos-modelos-conta.md) | Entrar, criar projeto, modelos prontos |
| [01b Nuvem e sincronização](manual/01b-nuvem-e-sincronizacao.md) | Vários aparelhos, conflitos, cotas |
| [02 Transporte](manual/02-transporte.md) | Barra superior, andamento e tap tempo, loop, metrônomo, punch |
| [02b Timeline e clipes](manual/02b-timeline-e-clipes.md) | Faixas, clipes, marcadores, minimapa |
| [02c Pastas de faixa](manual/02c-pastas-de-faixa.md) | Agrupar faixas sob um barramento, recolher e expandir, solo e stems da pasta |
| [02d Histórico e versões](manual/02d-historico-e-versoes.md) | Passos do desfazer com nome e hora, painel `Histórico`, versões nomeadas do projeto (salvar, restaurar, comparar, duplicar) e as automáticas |
| [02e Congelar faixa e converter em áudio](manual/02e-congelar-faixa.md) | `Congelar faixa…` no lugar (o conteúdo fica guardado, `Descongelar` devolve), `Cauda dos efeitos`, `Converter em áudio…`, `Renderizar em faixa nova` (antigo `Congelar em áudio`), recusas e o que sobe à nuvem |
| [03 Áudio e clipes](manual/03-audio-e-clipes.md) | Importar, fades, ganho, mudo, fase invertida (polaridade) e loop por clipe |
| [03b Warp e altura](manual/03b-warp-e-altura.md) | Esticar no tempo, transpor, detectar andamento |
| [03c Gravação](manual/03c-gravacao.md) | Microfone, tomadas, MIDI ao vivo, punch in/out, pré-roll e opções do metrônomo |
| [03d Áudio para MIDI](manual/03d-audio-para-midi.md) | Converter melodia cantada em notas |
| [03e Editar áudio](manual/03e-editar-audio.md) | Dividir um clipe por transientes, em partes iguais ou na grade, remover silêncio, normalizar por pico, RMS ou LUFS e quantizar por fatias |
| [04 Painel de instrumento](manual/04-painel-de-instrumento.md) | Presets, teclado, knobs |
| [04a Sintetizador](manual/04a-sintetizador.md) | Subtrativo |
| [04b Bateria](manual/04b-bateria.md) | 12 peças sintetizadas |
| [04c Sampler](manual/04c-sampler.md) | Tocar um áudio como instrumento |
| [04d FM](manual/04d-fm.md) | 4 operadores, 8 algoritmos |
| [04e Wavetable](manual/04e-wavetable.md) | Tabelas morfáveis |
| [05 Piano roll](manual/05-piano-roll.md) | Editor de notas |
| [05b Ferramentas MIDI](manual/05b-ferramentas-midi.md) | Escalas, acordes, arpejo, humanizar |
| [05c Sequenciador de passos](manual/05c-sequenciador-de-passos.md) | Aba `Passos`: grade de quadradinhos para bateria e sampler fatiado, swing, acentos, fantasmas e 9 padrões prontos |
| [06 Mixer](manual/06-mixer.md) | Faders, envios, barramentos, master |
| [06b Analisador e medidores](manual/06b-analisador-e-medidores.md) | Espectro e níveis |
| [06c Painel de efeitos](manual/06c-painel-de-efeitos.md) | Cadeia de efeitos |
| [06d Referência dos efeitos](manual/06d-efeitos-referencia.md) | Os 15 efeitos, parâmetro por parâmetro |
| [06e Compensação de latência](manual/06e-compensacao-de-latencia.md) | Como o motor alinha faixas e envios quando o `Limitador` e a `Distorção` atrasam o som |
| [06f MIDI learn](manual/06f-midi-learn.md) | Ligar knobs, faders e pedais de um controlador MIDI a controles do app |
| [06g Modulação](manual/06g-modulacao.md) | LFO, seguidor de envelope e macro movendo os controles por cima do valor do knob, na aba `Modulação` |
| [07 Automação](manual/07-automacao.md) | Mover parâmetros no tempo |
| [08 Exportação](manual/08-exportacao.md) | WAV, FLAC e MP3 (pelo servidor), stems, `Renderizar em faixa nova` (antigo congelar em áudio) |
| [09 Configurações, atalhos e Android](manual/09-configuracoes-atalhos-android.md) | Ajustes, teclas, diferenças de plataforma |

### Guias de combinações

Receitas que juntam vários recursos, com valores concretos (`guias/`). Para achar o guia certo, ou para saber o que combina com o quê e o que evitar juntos, comece pelo [mapa de combinações](guias/README.md): objetivos por guia, matrizes recurso × recurso, combinações que atrapalham e receitas de uma linha.

| Guia | Resultado |
|---|---|
| [Primeira batida do zero](guias/primeira-batida-do-zero.md) | Bateria, baixo e pad em loop, exportados |
| [Batida com o sequenciador de passos](guias/batida-com-o-sequenciador-de-passos.md) | House de quatro no chão com chimbal, hip-hop com swing e fantasmas, trap com rolos de chimbal, na aba `Passos` |
| [Gravar uma banda e mixar](guias/gravar-uma-banda-e-mixar.md) | Microfone, tomadas, reverb em barramento, stems |
| [Regravar um trecho com punch e pré-roll](guias/regravar-um-trecho-com-punch-e-pre-roll.md) | Consertar uma frase de voz com punch in/out, solo com pré-roll sem contagem, tap tempo e metrônomo com subdivisões |
| [Melodia e harmonia com as ferramentas](guias/melodia-e-harmonia-com-as-ferramentas.md) | Acordes, arpejo, humanizar, escala |
| [FM e wavetable na prática](guias/fm-e-wavetable-na-pratica.md) | Seis timbres com efeitos |
| [Sampler multi-zona e fatiar loops](guias/sampler-multi-zona-e-fatiar-loops.md) | Piano em camadas, kit de um loop, round-robin |
| [Expressão MIDI na prática](guias/expressao-midi-na-pratica.md) | Bend, modulação e pedal |
| [Efeitos em combinação](guias/efeitos-em-combinacao.md) | Cadeia vocal, sidechain, delay em tempo |
| [Modulação na prática](guias/modulacao-na-pratica.md) | Wobble de baixo preso ao andamento, tremolo de pad, auto-pan e bombeio falso com o seguidor de envelope |
| [Mixagem e automação](guias/mixagem-e-automacao.md) | Mix do zero e automação de filtro e volume |
| [Organizar um projeto com pastas](guias/organizar-um-projeto-com-pastas.md) | Bateria com compressor no grupo, coro com reverb no grupo, projeto grande recolhido |
| [Loudness e master](guias/loudness-e-master.md) | Nível competitivo e seguro |
| [Exportar para compartilhar e arquivar](guias/exportar-para-compartilhar.md) | Prévia em MP3 por mensagem, arquivo em FLAC e master final em WAV 24 bits e MP3 320 |
| [Remix com warp e altura](guias/remix-com-warp-e-altura.md) | Esticar, transpor e sobrepor |
| [Editar áudio: dividir, limpar silêncios e nivelar](guias/editar-audio-dividir-quantizar-normalizar.md) | Loop de bateria fatiado e reordenado, voz sem silêncios longos e três vozes no mesmo LUFS |
| [Fades e crossfades na prática](guias/fades-e-crossfades.md) | Emendar tomadas de voz, loop sem clique, entrada suave de um pad, com a curva de cada caso |
| [Congelar faixas e poupar CPU](guias/congelar-faixas-e-poupar-cpu.md) | Baixo pesado congelado para mixar o resto, descongelar para mudar uma nota, converter em áudio para cortar e esticar, e a cauda certa para o reverb |
| [Loops e polaridade de clipes](guias/loops-e-polaridade-de-clipes.md) | 1 compasso esticado em 8 com o loop do clipe, fase de dois microfones numa caixa (mutar e inverter) e A/B de tomadas mutando clipes |
| [Trabalhar em dois aparelhos](guias/trabalhar-em-dois-aparelhos.md) | Nuvem, conflito, offline |
| [Backup e levar o projeto para outro aparelho](guias/backup-e-levar-projeto-para-outro-aparelho.md) | Arquivo `.jopendaw` |
| [Voltar atrás: histórico e versões](guias/voltar-atras-historico-e-versoes.md) | Experimentar uma mixagem e voltar (A contra B), recuperar o projeto de ontem, tirar uma cópia para uma variação |
| [Mapa de andamento e compasso](guias/mapa-de-andamento-e-compasso.md) | Virada de andamento, ritardando em rampa, 4/4 para 3/4 e 6/8 |
| [MIDI de e para outros programas](guias/midi-de-e-para-outros-programas.md) | Exportar e importar `.mid`: melodia para outro DAW, pacote de acordes, backup das notas |
| [Atalhos e fluxo rápido](guias/atalhos-e-fluxo-rapido.md) | Trabalhar sem tirar a mão do teclado |
| [Controlador MIDI e MIDI learn](guias/controlador-midi-e-midi-learn.md) | Knobs no mixer, pedal de expressão no filtro, faders gravando automação |

## Para quem mexe no código

| Documento | Assunto |
|---|---|
| [00 Arquitetura](dev/00-arquitetura.md) | Visão de ponta a ponta e mapa de diretórios |
| [01 Motor](dev/01-motor.md) | O crate `engine/`, ciclo de render, chamadas da API |
| [02 Pontes web e Android](dev/02-pontes-web-e-android.md) | Como o motor chega ao Dart; checklist de chamada nova |
| [03 Build, teste e depuração](dev/03-build-teste-e-depuracao.md) | Comandos, armadilhas, ferramentas de teste |
| [04 Expressão MIDI](dev/04-expressao-midi.md) | Bend, modulação e pedal no motor e no app |
| [10 App Flutter](dev/10-app-flutter.md) | Modelo do documento (JSON), controlador, como adicionar recursos |
| [11 Servidor](dev/11-servidor.md) | Rotas, banco, armazenamento, jobs |
| [12 Sincronização](dev/12-sincronizacao.md) | Protocolo e máquina de estados |
| [20 Processo e histórico](dev/20-processo-e-historico.md) | Como o projeto é construído e a cronologia por fase |

## Manutenção

- Cada feature nova ganha (ou altera) um capítulo do manual e, se muda a arquitetura, um capítulo técnico. O registro de mudanças fica em [`changelog.md`](changelog.md).
- As capturas de tela ficam em [`img/`](img/) e são do app real; quando a interface mudar, refaça a captura junto com o texto.
- Rótulos de tela citados nos manuais são copiados do código. Se um rótulo mudar no app, o capítulo muda no mesmo dia.
- Quando algo no manual estiver marcado `(não confirmado)`, é porque só foi lido no código e ainda não foi visto rodando.
