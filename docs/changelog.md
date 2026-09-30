# Registro de mudanças

Do mais novo para o mais antigo. Cada linha diz o que muda para quem usa e onde está documentado. Detalhes técnicos por fase: [processo e histórico](dev/20-processo-e-historico.md).

## 30/09/2026 (fase 8, em andamento)

- **Zonas do sampler e fatiar loops** (`b6b7abb`, `6f3d245`, `6e5fa7b`): o sampler deixa de tocar um áudio só e passa a ter mapa de teclado com zonas (faixa de notas e de velocidade, round-robin, loop) e o fatiamento de um loop em zonas. Manual: [sampler](manual/04c-sampler.md). Guia: [sampler multi-zona e fatiar loops](guias/sampler-multi-zona-e-fatiar-loops.md).
- **Expressão MIDI** (`b7e802e`, `01c0c44`): pitch bend, roda de modulação e pedal de sustain ao vivo (Web MIDI e Android), gravados no clipe e editáveis numa faixa de controle sob a grade do piano roll (Velocidade, Pitch bend, Modulação, Sustain); rodas de bend e de modulação ao lado do teclado da tela; knobs `Alcance do bend` e `Vibrato da roda`. Manual: [piano roll](manual/05-piano-roll.md), [ferramentas MIDI](manual/05b-ferramentas-midi.md), [gravação](manual/03c-gravacao.md), [painel de instrumento](manual/04-painel-de-instrumento.md). Técnico: [expressão MIDI](dev/04-expressao-midi.md). Guia: [expressão MIDI na prática](guias/expressao-midi-na-pratica.md).
- **Projeto em arquivo no diálogo de exportar** (`677f064`): o botão da barra saiu (a barra estourava); agora `Projeto inteiro (.jopendaw)…` fica no diálogo `Exportar áudio`, e `Exportar projeto…` no menu do card em Projetos.
- **Correção do dart2js** (`606664f`): no navegador os operadores de bit trabalham em 32 bits; isso fazia o `Fatiar sample` nunca achar cortes e errava o limite de tamanho do `.jopendaw`. Corrigido.
- **Servidor** (`0c0593e`): a imagem Docker do servidor passa a construir com o workspace inteiro e o nginx aceita uploads de até 600 MB. Técnico: [servidor](dev/11-servidor.md).
- **Medição de loudness e normalização na exportação** (`dca27bc`, binários em `357b6fc`): leitura `M`, `S`, `I` e `TP` no Master, alerta acima de −1 dBTP, `Zerar`, e na exportação `Normalizar o loudness` (Streaming −14, Podcast −16, Broadcast −23, Personalizado) com teto de true peak. Manual: [mixer](manual/06-mixer.md), [medidores](manual/06b-analisador-e-medidores.md), [exportação](manual/08-exportacao.md). Guia: [loudness e master](guias/loudness-e-master.md).
- **Projeto em arquivo `.jopendaw`** (`7af1f19`): exportar e importar o projeto inteiro (documento e áudios) como um arquivo. Manual: [projetos](manual/01-projetos-modelos-conta.md) e [nuvem](manual/01b-nuvem-e-sincronizacao.md). Guia: [backup e levar o projeto para outro aparelho](guias/backup-e-levar-projeto-para-outro-aparelho.md).
- **Documentação**: manual de uso completo (capítulos 00 a 09), guias de combinações, documentação técnica e capturas de tela em `docs/img/`.

## 30/09/2026 (fase 7 e ajustes)

- **Seletor de presets do instrumento** (`9a790a2`): largura fixa (os botões anterior/próximo não andam mais a cada nome) e a faixa recém-criada mostra `Inicial` no lugar de `Personalizado`. Manual: [painel de instrumento](manual/04-painel-de-instrumento.md).
- **Detector de andamento** (`f1cfbaa`): passa a recusar o que não tem batida (tom puro, ruído, pad); nos extremos (abaixo de 75 e acima de 140 BPM) pode errar por oitava, corrigível com ÷2 e ×2. Manual: [warp e altura](manual/03b-warp-e-altura.md).
- **Instrumentos FM e Wavetable** (`8e3c6a6`): manual em [FM](manual/04d-fm.md) e [Wavetable](manual/04e-wavetable.md). Guia: [FM e wavetable na prática](guias/fm-e-wavetable-na-pratica.md).
- **Ferramentas MIDI, marcadores e minimapa, warp de áudio, modelos de projeto, janela de atalhos** (fase 7): [piano roll](manual/05-piano-roll.md), [ferramentas MIDI](manual/05b-ferramentas-midi.md), [timeline](manual/02b-timeline-e-clipes.md), [warp](manual/03b-warp-e-altura.md), [projetos](manual/01-projetos-modelos-conta.md), [atalhos](manual/09-configuracoes-atalhos-android.md).
