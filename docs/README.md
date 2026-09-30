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
| [02 Transporte](manual/02-transporte.md) | Barra superior, andamento, loop, metrônomo |
| [02b Timeline e clipes](manual/02b-timeline-e-clipes.md) | Faixas, clipes, marcadores, minimapa |
| [03 Áudio e clipes](manual/03-audio-e-clipes.md) | Importar, fades, ganho |
| [03b Warp e altura](manual/03b-warp-e-altura.md) | Esticar no tempo, transpor, detectar andamento |
| [03c Gravação](manual/03c-gravacao.md) | Microfone, tomadas, MIDI ao vivo |
| [03d Áudio para MIDI](manual/03d-audio-para-midi.md) | Converter melodia cantada em notas |
| [04 Painel de instrumento](manual/04-painel-de-instrumento.md) | Presets, teclado, knobs |
| [04a Sintetizador](manual/04a-sintetizador.md) | Subtrativo |
| [04b Bateria](manual/04b-bateria.md) | 12 peças sintetizadas |
| [04c Sampler](manual/04c-sampler.md) | Tocar um áudio como instrumento |
| [04d FM](manual/04d-fm.md) | 4 operadores, 8 algoritmos |
| [04e Wavetable](manual/04e-wavetable.md) | Tabelas morfáveis |
| [05 Piano roll](manual/05-piano-roll.md) | Editor de notas |
| [05b Ferramentas MIDI](manual/05b-ferramentas-midi.md) | Escalas, acordes, arpejo, humanizar |
| [06 Mixer](manual/06-mixer.md) | Faders, envios, barramentos, master |
| [06b Analisador e medidores](manual/06b-analisador-e-medidores.md) | Espectro e níveis |
| [06c Painel de efeitos](manual/06c-painel-de-efeitos.md) | Cadeia de efeitos |
| [06d Referência dos efeitos](manual/06d-efeitos-referencia.md) | Os 12 efeitos, parâmetro por parâmetro |
| [07 Automação](manual/07-automacao.md) | Mover parâmetros no tempo |
| [08 Exportação](manual/08-exportacao.md) | WAV, stems, congelar faixa |
| [09 Configurações, atalhos e Android](manual/09-configuracoes-atalhos-android.md) | Ajustes, teclas, diferenças de plataforma |

### Guias de combinações

Receitas que juntam vários recursos, com valores concretos (`guias/`):

| Guia | Resultado |
|---|---|
| [Primeira batida do zero](guias/primeira-batida-do-zero.md) | Bateria, baixo e pad em loop, exportados |
| [Gravar uma banda e mixar](guias/gravar-uma-banda-e-mixar.md) | Microfone, tomadas, reverb em barramento, stems |
| [Melodia e harmonia com as ferramentas](guias/melodia-e-harmonia-com-as-ferramentas.md) | Acordes, arpejo, humanizar, escala |
| [FM e wavetable na prática](guias/fm-e-wavetable-na-pratica.md) | Seis timbres com efeitos |
| [Sampler multi-zona e fatiar loops](guias/sampler-multi-zona-e-fatiar-loops.md) | Piano em camadas, kit de um loop, round-robin |
| [Expressão MIDI na prática](guias/expressao-midi-na-pratica.md) | Bend, modulação e pedal |
| [Efeitos em combinação](guias/efeitos-em-combinacao.md) | Cadeia vocal, sidechain, delay em tempo |
| [Mixagem e automação](guias/mixagem-e-automacao.md) | Mix do zero e automação de filtro e volume |
| [Loudness e master](guias/loudness-e-master.md) | Nível competitivo e seguro |
| [Remix com warp e altura](guias/remix-com-warp-e-altura.md) | Esticar, transpor e sobrepor |
| [Trabalhar em dois aparelhos](guias/trabalhar-em-dois-aparelhos.md) | Nuvem, conflito, offline |
| [Backup e levar o projeto para outro aparelho](guias/backup-e-levar-projeto-para-outro-aparelho.md) | Arquivo `.jopendaw` |
| [Atalhos e fluxo rápido](guias/atalhos-e-fluxo-rapido.md) | Trabalhar sem tirar a mão do teclado |

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
