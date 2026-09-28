//! Instrumentos: o que transforma notas em som numa faixa de instrumento.
//!
//! Todo instrumento implementa [`Instrument`]. O motor chama `note_on`/`note_off` no quadro exato
//! de cada evento (fatiando o bloco nos pontos dos eventos) e `render` para cada fatia. Nada aqui
//! pode alocar, travar ou fazer E/S depois de criado: `render` e os eventos rodam na thread de
//! áudio. As vozes são pré-alocadas em `new`.
//!
//! Os ids de parâmetro abaixo são contrato com o app (`app/lib/daw/instruments.dart`): mudar um
//! id quebra projetos salvos. Os valores chegam já na unidade da tabela (Hz, segundos, semitons),
//! nunca normalizados.

use std::sync::Arc;

use crate::Sample;

pub trait Instrument: Send {
    /// Começa uma nota. `velocity` em 0..=1. A mesma nota de novo antes do `note_off` reataca.
    fn note_on(&mut self, pitch: u8, velocity: f32);
    /// Solta uma nota (entra no release).
    fn note_off(&mut self, pitch: u8);
    /// Solta todas as notas, com release normal (parar o transporte).
    fn release_all(&mut self);
    /// Corta tudo na hora, sem cauda (pânico, troca de instrumento).
    fn silence(&mut self);
    /// Muda um parâmetro. Id desconhecido é ignorado; valor fora da faixa é limitado.
    fn set_param(&mut self, id: u32, value: f32);
    /// O áudio que o instrumento toca (só o sampler usa).
    fn set_sample(&mut self, _sample: Option<Arc<Sample>>) {}
    /// Soma o som no bloco (`left.len() == right.len() <= MAX_BLOCK`). Não zera a saída.
    fn render(&mut self, left: &mut [f32], right: &mut [f32]);
    /// Alguma voz soando (inclusive em release)? Faixa sem voz ativa pode pular o `render`.
    fn active(&self) -> bool;
}

/// Tipos de faixa, como o app manda em `track_kind`.
pub mod kind {
    pub const AUDIO: u32 = 0;
    pub const SYNTH: u32 = 1;
    pub const DRUMS: u32 = 2;
    pub const SAMPLER: u32 = 3;
}

/// Cria o instrumento de um tipo; `None` para faixa de áudio ou tipo desconhecido.
pub fn create(kind: u32, rate: f64) -> Option<Box<dyn Instrument>> {
    match kind {
        kind::SYNTH => Some(Box::new(crate::synth::Synth::new(rate))),
        kind::DRUMS => Some(Box::new(crate::drums::Drums::new(rate))),
        kind::SAMPLER => Some(Box::new(crate::sampler::Sampler::new(rate))),
        _ => None,
    }
}

/// Frequência de uma nota MIDI (lá 440 no 69), com desvio em semitons fracionários.
pub fn pitch_hz(pitch: f32) -> f32 {
    440.0 * 2f32.powf((pitch - 69.0) / 12.0)
}

/// Parâmetros do sintetizador subtrativo (tipo 1). Faixas e padrões em `instruments.dart`.
pub mod synth_param {
    /// Forma de onda: 0 serra, 1 quadrada (pulso), 2 triângulo, 3 senoide.
    pub const OSC1_WAVE: u32 = 0;
    pub const OSC1_LEVEL: u32 = 1;
    /// Largura do pulso da onda quadrada dos dois osciladores, 0,05..0,95.
    pub const PULSE_WIDTH: u32 = 2;
    pub const OSC2_WAVE: u32 = 3;
    pub const OSC2_LEVEL: u32 = 4;
    /// Semitons, −24..24.
    pub const OSC2_SEMI: u32 = 5;
    /// Cents, −100..100.
    pub const OSC2_DETUNE: u32 = 6;
    /// Senoide uma oitava abaixo.
    pub const SUB_LEVEL: u32 = 7;
    pub const NOISE_LEVEL: u32 = 8;
    /// Vozes de uníssono por nota, 1..7.
    pub const UNISON: u32 = 9;
    /// Espalhamento de afinação do uníssono, em cents (0..100).
    pub const UNISON_DETUNE: u32 = 10;
    /// Abertura estéreo do uníssono, 0..1.
    pub const UNISON_SPREAD: u32 = 11;
    /// 0 passa-baixa, 1 passa-alta, 2 passa-banda (12 dB/oit, SVF).
    pub const FILTER_TYPE: u32 = 12;
    /// Hz, 20..20000.
    pub const CUTOFF: u32 = 13;
    /// 0..1 (perto de 1 auto-oscila).
    pub const RESONANCE: u32 = 14;
    /// Quanto o envelope do filtro move o corte, −1..1 (×6 oitavas).
    pub const FILTER_ENV: u32 = 15;
    /// Acompanhamento do teclado, 0..1 (1 = o corte sobe uma oitava por oitava).
    pub const KEYTRACK: u32 = 16;
    /// Envelope de amplitude: segundos, segundos, nível 0..1, segundos.
    pub const AMP_ATTACK: u32 = 17;
    pub const AMP_DECAY: u32 = 18;
    pub const AMP_SUSTAIN: u32 = 19;
    pub const AMP_RELEASE: u32 = 20;
    /// Envelope do filtro.
    pub const FLT_ATTACK: u32 = 21;
    pub const FLT_DECAY: u32 = 22;
    pub const FLT_SUSTAIN: u32 = 23;
    pub const FLT_RELEASE: u32 = 24;
    /// 0 senoide, 1 triângulo, 2 serra, 3 quadrada, 4 aleatório (sample & hold).
    pub const LFO_WAVE: u32 = 25;
    /// Hz, 0,05..30.
    pub const LFO_RATE: u32 = 26;
    /// Vibrato, em semitons (0..12).
    pub const LFO_PITCH: u32 = 27;
    /// Modulação do corte, em oitavas (0..4).
    pub const LFO_CUTOFF: u32 = 28;
    /// Tremolo, 0..1.
    pub const LFO_AMP: u32 = 29;
    /// Portamento, segundos (0..2).
    pub const GLIDE: u32 = 30;
    /// Polifonia máxima, 1..16 (1 = mono com legato).
    pub const VOICES: u32 = 31;
    /// Sensibilidade à velocidade, 0..1.
    pub const VELOCITY: u32 = 32;
    /// Volume de saída do instrumento, 0..1,5.
    pub const LEVEL: u32 = 33;
    /// Saturação antes do filtro, 0..1.
    pub const DRIVE: u32 = 34;
    pub const COUNT: u32 = 35;
}

/// Bateria sintetizada (tipo 2): 12 peças, cada uma com 4 parâmetros em `peça * 4 + k`.
pub mod drum_param {
    /// k = 0: volume da peça, 0..1,5.
    pub const LEVEL: u32 = 0;
    /// k = 1: afinação, semitons −12..12.
    pub const TUNE: u32 = 1;
    /// k = 2: multiplicador do decaimento, 0,25..4.
    pub const DECAY: u32 = 2;
    /// k = 3: timbre (brilho/ataque), 0..1.
    pub const TONE: u32 = 3;
    /// Volume geral da bateria, 0..1,5.
    pub const MASTER: u32 = 48;
    pub const PIECES: usize = 12;

    /// Peças na ordem dos ids, com a nota MIDI principal (mapa General MIDI).
    pub const PIECE_PITCH: [u8; PIECES] = [
        36, // 0 bumbo
        38, // 1 caixa
        39, // 2 palmas
        42, // 3 chimbal fechado
        46, // 4 chimbal aberto (o fechado corta o aberto)
        41, // 5 surdo / tom grave
        45, // 6 tom médio
        48, // 7 tom agudo
        49, // 8 prato de ataque
        51, // 9 prato de condução
        37, // 10 aro
        56, // 11 cowbell
    ];

    /// Peça que toca numa nota MIDI (aceita as notas vizinhas do GM também).
    pub fn piece_for(pitch: u8) -> Option<usize> {
        Some(match pitch {
            35 | 36 => 0,
            38 | 40 => 1,
            39 => 2,
            42 | 44 => 3,
            46 => 4,
            41 | 43 => 5,
            45 | 47 => 6,
            48 | 50 => 7,
            49 | 52 | 55 | 57 => 8,
            51 | 53 | 59 => 9,
            37 => 10,
            56 => 11,
            _ => return None,
        })
    }
}

/// Sampler (tipo 3): toca o áudio escolhido afinado pelas notas.
pub mod sampler_param {
    /// Nota em que o áudio soa na altura original, 0..127.
    pub const ROOT: u32 = 0;
    pub const ATTACK: u32 = 1;
    pub const DECAY: u32 = 2;
    pub const SUSTAIN: u32 = 3;
    pub const RELEASE: u32 = 4;
    /// 0..1,5.
    pub const LEVEL: u32 = 5;
    /// 1 = toca até o fim ignorando o note off.
    pub const ONE_SHOT: u32 = 6;
    /// Cents, −100..100.
    pub const TUNE: u32 = 7;
    /// Sensibilidade à velocidade, 0..1.
    pub const VELOCITY: u32 = 8;
}
