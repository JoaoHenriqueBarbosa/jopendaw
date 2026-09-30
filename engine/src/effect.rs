//! Efeitos: o que processa o áudio de uma faixa (inserts) ou do master.
//!
//! Todo efeito implementa [`Effect`]. O motor chama `process` bloco a bloco, na ordem da cadeia,
//! depois do instrumento/clipes e antes do volume da faixa. Nada aqui pode alocar, travar ou fazer
//! E/S depois de criado: buffers (atrasos, reverbs) são alocados em `new`, no tamanho máximo.
//!
//! Os ids de parâmetro abaixo são contrato com o app (`app/lib/daw/effects.dart`): mudar um id
//! quebra projetos salvos. Os valores chegam na unidade da tabela (dB, Hz, segundos), nunca
//! normalizados; valor fora da faixa é limitado. Parâmetros contínuos precisam de suavização
//! (sem zipper) e trocas discretas não podem estalar.

pub trait Effect: Send {
    /// Muda um parâmetro. Id desconhecido é ignorado.
    fn set_param(&mut self, id: u32, value: f32);
    /// Processa no lugar (`left.len() == right.len() <= MAX_BLOCK`).
    fn process(&mut self, left: &mut [f32], right: &mut [f32]);
    /// Como [`Effect::process`], com uma chave externa de sidechain (mesmo tamanho do bloco).
    /// Só dinâmica usa; o padrão ignora a chave.
    fn process_keyed(&mut self, left: &mut [f32], right: &mut [f32], _key: Option<(&[f32], &[f32])>) {
        self.process(left, right);
    }
    /// Andamento atual, para efeitos sincronizados (delay, tremolo, filtro).
    fn set_tempo(&mut self, _bpm: f64) {}
    /// Esquece o estado (linhas de atraso, envelopes): pânico e troca de projeto.
    fn reset(&mut self);
    /// Atraso que o efeito introduz, em quadros (lookahead, filtros de fase linear). O motor o
    /// compensa (PDC, ver `Engine::pdc_update`): o efeito não faz nada além de declará-lo. Deve ser
    /// a latência que os parâmetros já mandados terão depois de assentar (o valor pedido, não o em
    /// transição), constante enquanto o parâmetro não muda, e não pode depender do sinal.
    fn latency(&self) -> usize {
        0
    }
    /// Um indicador para a interface: redução de ganho em dB (≥ 0) nos de dinâmica, 0 nos outros.
    fn meter(&self) -> f32 {
        0.0
    }
}

/// Tipos de efeito, como o app manda em `fx_set` (0 = slot vazio).
pub mod kind {
    pub const EQ: u32 = 1;
    pub const COMPRESSOR: u32 = 2;
    pub const GATE: u32 = 3;
    pub const LIMITER: u32 = 4;
    pub const UTILITY: u32 = 5;
    pub const REVERB: u32 = 6;
    pub const DELAY: u32 = 7;
    pub const CHORUS: u32 = 8;
    pub const PHASER: u32 = 9;
    pub const TREMOLO: u32 = 10;
    pub const DISTORTION: u32 = 11;
    pub const FILTER: u32 = 12;
}

/// Cria o efeito de um tipo; `None` para 0 ou tipo desconhecido.
pub fn create(kind: u32, rate: f64) -> Option<Box<dyn Effect>> {
    use crate::fx::*;
    Some(match kind {
        kind::EQ => Box::new(eq::Eq::new(rate)),
        kind::COMPRESSOR => Box::new(compressor::Compressor::new(rate)),
        kind::GATE => Box::new(gate::Gate::new(rate)),
        kind::LIMITER => Box::new(limiter::Limiter::new(rate)),
        kind::UTILITY => Box::new(utility::Utility::new(rate)),
        kind::REVERB => Box::new(reverb::Reverb::new(rate)),
        kind::DELAY => Box::new(delay::Delay::new(rate)),
        kind::CHORUS => Box::new(chorus::Chorus::new(rate)),
        kind::PHASER => Box::new(phaser::Phaser::new(rate)),
        kind::TREMOLO => Box::new(tremolo::Tremolo::new(rate)),
        kind::DISTORTION => Box::new(distortion::Distortion::new(rate)),
        kind::FILTER => Box::new(filter::Filter::new(rate)),
        _ => return None,
    })
}

/// Figuras rítmicas dos efeitos sincronizados (índice do parâmetro "nota"), em batidas.
pub const NOTE_BEATS: [f64; 12] = [
    0.125,     // 1/32
    1.0 / 6.0, // 1/16T
    0.25,      // 1/16
    0.375,     // 1/16D
    1.0 / 3.0, // 1/8T
    0.5,       // 1/8
    0.75,      // 1/8D
    2.0 / 3.0, // 1/4T
    1.0,       // 1/4
    1.5,       // 1/4D
    2.0,       // 1/2
    4.0,       // 1/1
];

/// EQ paramétrico de 8 bandas: banda `b` em `b * 6 + k`, saída em 48.
pub mod eq_param {
    /// k = 0: banda ligada (0/1).
    pub const ON: u32 = 0;
    /// k = 1: 0 passa-alta, 1 prateleira grave, 2 sino, 3 prateleira aguda, 4 passa-baixa,
    /// 5 rejeita-faixa.
    pub const TYPE: u32 = 1;
    /// k = 2: Hz, 20..20000.
    pub const FREQ: u32 = 2;
    /// k = 3: dB, −24..24 (sino e prateleiras).
    pub const GAIN: u32 = 3;
    /// k = 4: Q, 0,1..18.
    pub const Q: u32 = 4;
    /// k = 5: inclinação do passa-alta/baixa: 0 12 dB/oit, 1 24, 2 48.
    pub const SLOPE: u32 = 5;
    pub const BANDS: usize = 8;
    /// Ganho de saída, dB −24..24.
    pub const OUTPUT: u32 = 48;
}

pub mod compressor_param {
    /// dB, −60..0.
    pub const THRESHOLD: u32 = 0;
    /// 1..20.
    pub const RATIO: u32 = 1;
    /// s, 0,0001..0,25.
    pub const ATTACK: u32 = 2;
    /// s, 0,005..3.
    pub const RELEASE: u32 = 3;
    /// dB, 0..24.
    pub const KNEE: u32 = 4;
    /// dB, 0..36.
    pub const MAKEUP: u32 = 5;
    /// 0..1 (compressão paralela).
    pub const MIX: u32 = 6;
    /// 0 pico, 1 RMS.
    pub const DETECTOR: u32 = 7;
    /// Passa-alta na chave, Hz 20..500 (o grave não bombeia o resto).
    pub const SC_HPF: u32 = 8;
    /// 0/1: compensa o ganho sozinho pelo limiar e razão.
    pub const AUTO_MAKEUP: u32 = 9;
    /// Faixa que serve de chave (−1 = a própria entrada). O motor entrega a chave em
    /// `process_keyed`; o efeito não precisa saber de faixas.
    pub const SIDECHAIN: u32 = 10;
}

pub mod gate_param {
    /// dB, −80..0.
    pub const THRESHOLD: u32 = 0;
    /// s, 0,0001..0,1.
    pub const ATTACK: u32 = 1;
    /// s, 0..1.
    pub const HOLD: u32 = 2;
    /// s, 0,005..2.
    pub const RELEASE: u32 = 3;
    /// Quanto fecha, dB −80..0.
    pub const RANGE: u32 = 4;
    /// Passa-alta na chave, Hz 20..2000.
    pub const SC_HPF: u32 = 5;
    /// Faixa-chave, −1 = a própria.
    pub const SIDECHAIN: u32 = 6;
}

pub mod limiter_param {
    /// Ganho de entrada, dB 0..24.
    pub const GAIN: u32 = 0;
    /// Teto, dB −24..0.
    pub const CEILING: u32 = 1;
    /// s, 0,001..1.
    pub const RELEASE: u32 = 2;
    /// s, 0..0,01.
    pub const LOOKAHEAD: u32 = 3;
    /// 0..1.
    pub const LINK: u32 = 4;
}

pub mod utility_param {
    /// dB, −48..24.
    pub const GAIN: u32 = 0;
    /// −1..1.
    pub const PAN: u32 = 1;
    /// Largura estéreo (mid/side), 0..2.
    pub const WIDTH: u32 = 2;
    /// 0/1.
    pub const MONO: u32 = 3;
    pub const INVERT_L: u32 = 4;
    pub const INVERT_R: u32 = 5;
    pub const SWAP: u32 = 6;
    /// Tira o DC (passa-alta de 5 Hz).
    pub const DC: u32 = 7;
}

pub mod reverb_param {
    /// Mistura seca/molhada, 0..1.
    pub const MIX: u32 = 0;
    /// s, 0..0,25.
    pub const PREDELAY: u32 = 1;
    /// Tamanho da sala, 0..1.
    pub const SIZE: u32 = 2;
    /// RT60, s 0,2..20.
    pub const DECAY: u32 = 3;
    /// Abafamento dos agudos na cauda, Hz 1000..20000.
    pub const DAMPING: u32 = 4;
    /// Corte de graves na entrada da cauda, Hz 20..1000.
    pub const LOW_CUT: u32 = 5;
    /// 0..1.
    pub const WIDTH: u32 = 6;
    /// Modulação das linhas (tira o metálico), 0..1.
    pub const MODULATION: u32 = 7;
    /// Reflexões iniciais, 0..1.
    pub const EARLY: u32 = 8;
    /// 0/1: congela a cauda.
    pub const FREEZE: u32 = 9;
}

pub mod delay_param {
    pub const MIX: u32 = 0;
    /// 0 livre (TIME), 1 sincronizado (NOTE).
    pub const SYNC: u32 = 1;
    /// s, 0,001..4.
    pub const TIME: u32 = 2;
    /// Índice em [`super::NOTE_BEATS`].
    pub const NOTE: u32 = 3;
    /// 0..0,98.
    pub const FEEDBACK: u32 = 4;
    /// 0/1.
    pub const PING_PONG: u32 = 5;
    /// Desvio entre esquerda e direita, s −0,05..0,05.
    pub const OFFSET: u32 = 6;
    /// Filtros na realimentação, Hz.
    pub const HIGH_PASS: u32 = 7;
    pub const LOW_PASS: u32 = 8;
    /// Wow/flutter, 0..1.
    pub const MODULATION: u32 = 9;
    /// Saturação na realimentação, 0..1.
    pub const DRIVE: u32 = 10;
    /// Abaixa os ecos enquanto a entrada toca, 0..1.
    pub const DUCKING: u32 = 11;
}

pub mod chorus_param {
    pub const MIX: u32 = 0;
    /// Hz, 0,02..10.
    pub const RATE: u32 = 1;
    /// 0..1.
    pub const DEPTH: u32 = 2;
    /// Atraso base, s 0,001..0,03 (curto + realimentação = flanger).
    pub const DELAY: u32 = 3;
    /// Vozes, 1..4.
    pub const VOICES: u32 = 4;
    /// −0,95..0,95.
    pub const FEEDBACK: u32 = 5;
    /// 0..1.
    pub const WIDTH: u32 = 6;
}

pub mod phaser_param {
    pub const MIX: u32 = 0;
    pub const RATE: u32 = 1;
    pub const DEPTH: u32 = 2;
    /// Hz, 100..8000.
    pub const CENTER: u32 = 3;
    /// −0,95..0,95.
    pub const FEEDBACK: u32 = 4;
    /// Índice em 2, 4, 6, 8, 12 estágios.
    pub const STAGES: u32 = 5;
    /// Defasagem do LFO entre os canais, 0..1 (1 = 180°).
    pub const STEREO: u32 = 6;
}

pub mod tremolo_param {
    /// Hz, 0,05..20.
    pub const RATE: u32 = 0;
    pub const DEPTH: u32 = 1;
    /// 0 senoide, 1 triângulo, 2 quadrada.
    pub const WAVE: u32 = 2;
    /// Defasagem entre os canais, 0..1 (0,5 = autopan).
    pub const STEREO: u32 = 3;
    pub const SYNC: u32 = 4;
    pub const NOTE: u32 = 5;
}

pub mod distortion_param {
    /// dB, 0..48.
    pub const DRIVE: u32 = 0;
    /// 0 suave (tanh), 1 válvula (assimétrica), 2 fita, 3 dura, 4 dobra (foldback), 5 bitcrusher.
    pub const TYPE: u32 = 1;
    /// Passa-baixa depois da saturação, Hz 500..20000.
    pub const TONE: u32 = 2;
    pub const MIX: u32 = 3;
    /// dB, −24..12.
    pub const OUTPUT: u32 = 4;
    /// Bitcrusher: bits 1..16 e redução de taxa 1..32.
    pub const BITS: u32 = 5;
    pub const DOWNSAMPLE: u32 = 6;
    /// Sobreamostragem: 0 1×, 1 2×, 2 4×.
    pub const OVERSAMPLE: u32 = 7;
    /// Dither TPDF na quantização do bitcrusher: 0 desligado, 1 ligado.
    pub const DITHER: u32 = 8;
}

pub mod filter_param {
    /// 0 PB 12, 1 PB 24, 2 PA 12, 3 PA 24, 4 passa-banda, 5 rejeita-faixa.
    pub const TYPE: u32 = 0;
    pub const CUTOFF: u32 = 1;
    pub const RESONANCE: u32 = 2;
    pub const LFO_RATE: u32 = 3;
    /// Oitavas, 0..6.
    pub const LFO_DEPTH: u32 = 4;
    /// 0 senoide, 1 triângulo, 2 serra, 3 quadrada, 4 aleatório.
    pub const LFO_WAVE: u32 = 5;
    /// Seguidor de envelope, oitavas −6..6.
    pub const ENVELOPE: u32 = 6;
    pub const DRIVE: u32 = 7;
    pub const MIX: u32 = 8;
    pub const SYNC: u32 = 9;
    pub const NOTE: u32 = 10;
}

/// Alvos de automação (`auto_lane`).
pub mod auto_target {
    /// Volume da faixa (ganho linear).
    pub const VOLUME: u32 = 0;
    /// Pan, −1..1.
    pub const PAN: u32 = 1;
    /// Parâmetro do instrumento (`id`).
    pub const INSTRUMENT: u32 = 2;
    /// Parâmetro do efeito no slot `slot` (`id`).
    pub const EFFECT: u32 = 3;
    /// Nível do envio de índice `slot` (ganho linear).
    pub const SEND: u32 = 4;
}
