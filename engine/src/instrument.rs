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
    /// Apaga as zonas do instrumento (só o sampler tem zonas).
    fn zones_clear(&mut self) {}
    /// Acrescenta uma zona que toca o áudio `sample_id` (`sample` é o áudio, se já foi carregado).
    fn zone_add(&mut self, _def: crate::sampler::ZoneDef, _sample_id: u32, _sample: Option<Arc<Sample>>) {}
    /// O áudio `id` chegou (ou foi descartado, com `None`): as zonas que o citam passam a usá-lo.
    fn zone_sample(&mut self, _id: u32, _sample: Option<Arc<Sample>>) {}
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
    /// Barramento (retorno de envios, grupo): sem instrumento nem clipes, só recebe áudio de
    /// outras faixas (envios e saídas roteadas para ele).
    pub const BUS: u32 = 4;
    /// Sintetizador FM de 4 operadores.
    pub const FM: u32 = 5;
    /// Sintetizador de wavetable (2 osciladores, tabelas em séries de 8).
    pub const WAVETABLE: u32 = 6;
}

/// Cria o instrumento de um tipo; `None` para faixa de áudio ou tipo desconhecido.
pub fn create(kind: u32, rate: f64) -> Option<Box<dyn Instrument>> {
    match kind {
        kind::SYNTH => Some(Box::new(crate::synth::Synth::new(rate))),
        kind::DRUMS => Some(Box::new(crate::drums::Drums::new(rate))),
        kind::SAMPLER => Some(Box::new(crate::sampler::Sampler::new(rate))),
        kind::FM => Some(Box::new(crate::fm::Fm::new(rate))),
        kind::WAVETABLE => Some(Box::new(crate::wavetable::Wavetable::new(rate))),
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

/// Sintetizador FM (tipo 5): 4 operadores senoidais, 8 algoritmos, realimentação no operador 1.
/// Os parâmetros de cada operador ficam em `OP_BASE + operador * OP_STRIDE + k` (operador 0..3).
pub mod fm_param {
    /// Roteamento dos operadores, 0..7 (diagramas em `fm.rs`).
    pub const ALGORITHM: u32 = 0;
    /// Realimentação do operador 1 nele mesmo, 0..1.
    pub const FEEDBACK: u32 = 1;
    /// Primeiro id do operador 1; os do operador `n` começam em `OP_BASE + n * OP_STRIDE`.
    pub const OP_BASE: u32 = 2;
    pub const OP_STRIDE: u32 = 8;
    pub const OPS: u32 = 4;
    /// k = 0: razão de frequência com a nota, 0,25..16.
    pub const RATIO: u32 = 0;
    /// k = 1: ajuste fino da razão, cents −100..100.
    pub const FINE: u32 = 1;
    /// k = 2: nível do operador, 0..1 (no modulador, é o índice de modulação).
    pub const LEVEL: u32 = 2;
    /// k = 3..6: envelope do operador (segundos, segundos, nível 0..1, segundos).
    pub const ATTACK: u32 = 3;
    pub const DECAY: u32 = 4;
    pub const SUSTAIN: u32 = 5;
    pub const RELEASE: u32 = 6;
    /// k = 7: quanto a velocidade da nota move o nível do operador, 0..1.
    pub const VELOCITY: u32 = 7;
    /// Id de um parâmetro de operador (`op` 0..3, `k` uma das constantes acima).
    pub const fn op(op: u32, k: u32) -> u32 {
        OP_BASE + op * OP_STRIDE + k
    }
    /// 0 senoide, 1 triângulo, 2 serra, 3 quadrada, 4 aleatório (sample & hold).
    pub const LFO_WAVE: u32 = 34;
    /// Hz, 0,05..30.
    pub const LFO_RATE: u32 = 35;
    /// Vibrato, em semitons (0..12).
    pub const LFO_PITCH: u32 = 36;
    /// Tremolo, 0..1.
    pub const LFO_AMP: u32 = 37;
    /// Quanto o LFO move o índice de modulação (o brilho), 0..1.
    pub const LFO_INDEX: u32 = 38;
    /// Polifonia máxima, 1..16 (1 = mono com legato).
    pub const VOICES: u32 = 39;
    /// Portamento no modo mono, segundos (0..2).
    pub const GLIDE: u32 = 40;
    /// Volume de saída, 0..1,5.
    pub const LEVEL_OUT: u32 = 41;
    pub const COUNT: u32 = 42;
}

/// Sintetizador de wavetable (tipo 6): 2 osciladores de tabela, sub, ruído, uníssono, filtro SVF.
pub mod wavetable_param {
    /// Série de tabelas do oscilador 1: 0 clássica, 1 vozes, 2 digital.
    pub const OSC1_SERIES: u32 = 0;
    /// Posição na série, 0..1 (0 = 1ª tabela, 1 = 8ª; entre elas as tabelas vizinhas se misturam).
    pub const OSC1_POS: u32 = 1;
    pub const OSC1_LEVEL: u32 = 2;
    /// Semitons, −24..24.
    pub const OSC1_SEMI: u32 = 3;
    /// Cents, −100..100.
    pub const OSC1_DETUNE: u32 = 4;
    pub const OSC2_SERIES: u32 = 5;
    pub const OSC2_POS: u32 = 6;
    pub const OSC2_LEVEL: u32 = 7;
    pub const OSC2_SEMI: u32 = 8;
    pub const OSC2_DETUNE: u32 = 9;
    /// Senoide uma oitava abaixo.
    pub const SUB_LEVEL: u32 = 10;
    pub const NOISE_LEVEL: u32 = 11;
    /// Vozes de uníssono por nota, 1..7.
    pub const UNISON: u32 = 12;
    /// Espalhamento de afinação do uníssono, em cents (0..100).
    pub const UNISON_DETUNE: u32 = 13;
    /// Abertura estéreo do uníssono, 0..1.
    pub const UNISON_SPREAD: u32 = 14;
    /// 0 passa-baixa, 1 passa-alta, 2 passa-banda (12 dB/oit, SVF).
    pub const FILTER_TYPE: u32 = 15;
    /// Hz, 20..20000.
    pub const CUTOFF: u32 = 16;
    /// 0..1.
    pub const RESONANCE: u32 = 17;
    /// Quanto o envelope do filtro move o corte, −1..1 (×6 oitavas).
    pub const FILTER_ENV: u32 = 18;
    /// Acompanhamento do teclado, 0..1.
    pub const KEYTRACK: u32 = 19;
    /// Envelope de amplitude: segundos, segundos, nível 0..1, segundos.
    pub const AMP_ATTACK: u32 = 20;
    pub const AMP_DECAY: u32 = 21;
    pub const AMP_SUSTAIN: u32 = 22;
    pub const AMP_RELEASE: u32 = 23;
    /// Envelope do filtro (que também pode mover a posição da tabela, `ENV_POS`).
    pub const FLT_ATTACK: u32 = 24;
    pub const FLT_DECAY: u32 = 25;
    pub const FLT_SUSTAIN: u32 = 26;
    pub const FLT_RELEASE: u32 = 27;
    /// 0 senoide, 1 triângulo, 2 serra, 3 quadrada, 4 aleatório (sample & hold).
    pub const LFO_WAVE: u32 = 28;
    /// Hz, 0,05..30.
    pub const LFO_RATE: u32 = 29;
    /// Vibrato, em semitons (0..12).
    pub const LFO_PITCH: u32 = 30;
    /// Modulação do corte, em oitavas (0..4).
    pub const LFO_CUTOFF: u32 = 31;
    /// Tremolo, 0..1.
    pub const LFO_AMP: u32 = 32;
    /// Quanto o LFO move a posição da tabela nos dois osciladores, −1..1 (fração do percurso).
    pub const LFO_POS: u32 = 33;
    /// Portamento, segundos (0..2).
    pub const GLIDE: u32 = 34;
    /// Polifonia máxima, 1..16 (1 = mono com legato).
    pub const VOICES: u32 = 35;
    /// Sensibilidade à velocidade, 0..1.
    pub const VELOCITY: u32 = 36;
    /// Volume de saída do instrumento, 0..1,5.
    pub const LEVEL: u32 = 37;
    /// Quanto o envelope do filtro move a posição da tabela, −1..1 (fração do percurso).
    pub const ENV_POS: u32 = 38;
    pub const COUNT: u32 = 39;
}

/// Conferência das tabelas de parâmetros do motor contra as do app (`instruments.dart`).
#[cfg(test)]
pub(crate) mod contract {
    /// Mínimo, máximo, padrão e se o valor é inteiro de cada id, na ordem dos ids.
    pub type Row = (f32, f32, f32, bool);

    /// Lê `const <name> = <ParamSpec>[...]` do app e confere cada linha com `rows`.
    pub fn check(name: &str, rows: &[Row]) {
        let path = concat!(env!("CARGO_MANIFEST_DIR"), "/../app/lib/daw/instruments.dart");
        let Ok(src) = std::fs::read_to_string(path) else {
            eprintln!("sem {path}: conferência pulada");
            return;
        };
        let start = src.find(&format!("const {name} = <ParamSpec>[")).unwrap_or_else(|| panic!("{name} não está no app"));
        let body = &src[start..];
        let body = &body[..body.find("];").unwrap()];
        let quoted = |s: &str| s.matches('\'').count() / 2;
        let mut seen = vec![false; rows.len()];
        for line in body.lines().map(str::trim) {
            if let Some(rest) = line.strip_prefix("ParamSpec.choice(") {
                let id: usize = rest.split(',').next().unwrap().trim().parse().unwrap();
                // as opções vêm numa lista literal ou numa constante (`_waves`)
                let options = match rest.split(',').nth(3).map(str::trim) {
                    Some(n) if n.starts_with('_') => {
                        let n = n.trim_end_matches(')');
                        let decl = &src[src.find(&format!("const {n} = [")).unwrap()..];
                        quoted(&decl[..decl.find(']').unwrap()])
                    }
                    _ => quoted(rest) - 2,
                };
                // o padrão, quando não é a primeira opção, vem em `def: n`
                let def: f32 = rest.split("def:").nth(1).map_or(0.0, |d| d.trim().trim_end_matches([')', ',']).parse().unwrap());
                let (min, max, rdef, discrete) = rows[id];
                assert!(discrete && min == 0.0 && max == (options - 1) as f32 && rdef == def, "{name} id {id}");
                assert!(!seen[id], "{name}: id {id} repetido");
                seen[id] = true;
            } else if let Some(rest) = line.strip_prefix("ParamSpec(") {
                let fields: Vec<&str> = rest.split(',').map(|f| f.trim().trim_end_matches(')')).collect();
                let id: usize = fields[0].parse().unwrap();
                let (min, max, def): (f32, f32, f32) = (fields[3].parse().unwrap(), fields[4].parse().unwrap(), fields[5].parse().unwrap());
                assert_eq!(rows[id], (min, max, def, line.contains("Curve.integer")), "{name} id {id}");
                assert!(!seen[id], "{name}: id {id} repetido");
                seen[id] = true;
            }
        }
        assert!(seen.iter().all(|&s| s), "{name}: ids sem espelho no app: {seen:?}");
    }
}
