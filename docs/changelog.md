# Registro de mudanças

Do mais novo para o mais antigo. Cada linha diz o que muda para quem usa e onde está documentado. Detalhes técnicos por fase: [processo e histórico](dev/20-processo-e-historico.md).

## 30/09/2026

- **Seletor de presets do instrumento** (`9a790a2`): largura fixa (os botões anterior/próximo não andam mais a cada nome) e a faixa recém-criada mostra `Inicial` no lugar de `Personalizado`. Manual: [painel de instrumento](manual/04-painel-de-instrumento.md).
- **Detector de andamento** (`f1cfbaa`): passa a recusar o que não tem batida (tom puro, ruído, pad); nos extremos (abaixo de 75 e acima de 140 BPM) pode errar por oitava, corrigível com ÷2 e ×2. Manual: [warp e altura](manual/03b-warp-e-altura.md).
- **Instrumentos FM e Wavetable** (`8e3c6a6`): manual em [FM](manual/04d-fm.md) e [Wavetable](manual/04e-wavetable.md).
- **Fase 8 em andamento (sessão principal):** LUFS e true-peak com normalização na exportação; expressão MIDI (pitch bend, mod wheel, sustain, faixas de CC); projeto em arquivo `.jopendaw`; sampler multi-zona e fatiar loops. Os capítulos entram quando cada item for integrado.
