//! As chamadas do documento por nome, o mesmo protocolo que o worklet executa pelas funções do
//! wasm (`engine/wasm/src/lib.rs`), para hospedeiros que recebem as chamadas como lista de dados:
//! o Android (FFI) e o render fora de tempo real nativo. Cada chamada é `[nome, ...args]` com os
//! números como f64 (booleanos como 0/1, índices e ids como inteiros exatos em f64).
//!
//! Só entram aqui as chamadas sem ponteiro: carregar sample, ler picos, espectro, notas gravadas e
//! capturas têm funções próprias em cada hospedeiro. (esqueleto: implementação em andamento)

use crate::Engine;

/// Nome de chamada que o motor não conhece (ou com argumentos de menos).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct UnknownCall(pub String);

/// Aplica uma chamada. `Ok(Some(v))` para as que devolvem valor (`auto_lane`, `capture_add`,
/// `fx_meter`, `beat`, `playing`), `Ok(None)` para as outras.
pub fn apply(_engine: &mut Engine, name: &str, _args: &[f64]) -> Result<Option<f64>, UnknownCall> {
    Err(UnknownCall(name.to_owned()))
}
