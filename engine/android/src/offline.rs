//! Render fora de tempo real (exportar, stems, congelar faixa): um [`Engine`] próprio por handle,
//! sem thread de áudio nem fila, processado o mais rápido que a CPU deixa, na thread que chamar
//! (um isolate do Dart). O motor que toca segue intacto.
//!
//! Quem monta o render é o Dart, como o `render-worker.js` faz com o wasm: manda as chamadas do
//! documento (já aparadas no fim do trecho), `capture_clear`/`capture_add` para as faixas
//! separadas, `seek` e `play`, e então pede blocos com `process` e copia cada saída com
//! `captured` (índice −1 = a saída do próprio `process`, o master depois do limitador).

use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};

use jopendaw_engine::{Engine, MAX_BLOCK, Sample};

use crate::call::Call;
use crate::core::ApplyFn;

pub struct Offline {
    engine: Engine,
    apply: ApplyFn,
    left: Box<[f32]>,
    right: Box<[f32]>,
    /// Quadros do último bloco processado.
    last: usize,
}

impl Offline {
    pub fn new(rate: f64, apply: ApplyFn) -> Self {
        Self { engine: Engine::new(rate), apply, left: vec![0.0; MAX_BLOCK].into_boxed_slice(), right: vec![0.0; MAX_BLOCK].into_boxed_slice(), last: 0 }
    }

    /// Aplica as chamadas na ordem; devolve quantas o motor não conhecia (ignoradas, como o worker
    /// faz com uma função que o wasm não tem: o resto do documento vale).
    pub fn calls(&mut self, calls: &[Call]) -> usize {
        calls.iter().filter(|c| (self.apply)(&mut self.engine, c.name(), c.args()).is_err()).count()
    }

    pub fn load_sample(&mut self, id: u32, sample: Sample) {
        self.engine.load_sample(id, sample);
    }

    /// Processa até [`MAX_BLOCK`] quadros (o limite das capturas do motor); devolve quantos.
    pub fn process(&mut self, frames: usize) -> usize {
        let n = frames.min(MAX_BLOCK);
        self.engine.process(&mut self.left[..n], &mut self.right[..n]);
        self.last = n;
        n
    }

    /// Copia o último bloco de uma saída: `index` −1 é a do `process` (o master), os outros são os
    /// índices de `capture_add`. O que passar do bloco sai zerado; devolve quantos quadros eram do
    /// bloco.
    pub fn captured(&self, index: i32, left: &mut [f32], right: &mut [f32]) -> usize {
        if index == -1 {
            let (nl, nr) = (self.last.min(left.len()), self.last.min(right.len()));
            left[..nl].copy_from_slice(&self.left[..nl]);
            left[nl..].fill(0.0);
            right[..nr].copy_from_slice(&self.right[..nr]);
            right[nr..].fill(0.0);
            return nl;
        }
        // índice negativo (fora o −1) é inválido: silêncio, como um além do fim
        let index = usize::try_from(index).unwrap_or(usize::MAX);
        self.engine.captured(index, left, right)
    }
}

// ------------------------------------------------------------------ handles para o Dart

type Shared = Arc<Mutex<Offline>>;

static RENDERS: Mutex<Option<HashMap<u64, Shared>>> = Mutex::new(None);
static NEXT: AtomicU64 = AtomicU64::new(1);

pub fn keep(o: Offline) -> u64 {
    let id = NEXT.fetch_add(1, Ordering::Relaxed);
    RENDERS.lock().unwrap_or_else(|e| e.into_inner()).get_or_insert_with(HashMap::new).insert(id, Arc::new(Mutex::new(o)));
    id
}

/// Roda `f` com o render do handle (a tabela fica livre enquanto ele trabalha: renders em isolates
/// diferentes não se esperam).
pub fn with<R>(handle: u64, f: impl FnOnce(&mut Offline) -> R) -> Option<R> {
    let shared = RENDERS.lock().unwrap_or_else(|e| e.into_inner()).as_ref()?.get(&handle)?.clone();
    let mut o = shared.lock().unwrap_or_else(|e| e.into_inner());
    Some(f(&mut o))
}

pub fn free(handle: u64) -> bool {
    RENDERS.lock().unwrap_or_else(|e| e.into_inner()).as_mut().and_then(|t| t.remove(&handle)).is_some()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::call::parse_calls;
    use crate::core::tests::{dc, test_apply};

    fn calls(o: &mut Offline, json: &str) -> usize {
        o.calls(&parse_calls(json.as_bytes()).unwrap())
    }

    /// Um clipe de 0,5 s de DC 0,5 numa faixa, renderizado do começo com a faixa e o master
    /// capturados: sai o clipe, alinhado com a linha do tempo, e silêncio depois dele.
    #[test]
    fn renders_a_sample_and_captures_the_track_and_the_master() {
        let mut o = Offline::new(48_000.0, test_apply);
        o.load_sample(3, dc(24_000, 0.5));
        let ignored = calls(
            &mut o,
            r#"[["tempo", 120, 4], ["tracks", 1], ["track_kind", 0, 0], ["track", 0, 1, 0, 0, 0], ["master", 1, 0],
                ["clip_add", 0, 3, 0, 0, 0.5, 1, 0, 0], ["capture_clear"], ["capture_add", 0], ["capture_add", -1],
                ["seek", 0], ["play"], ["nao_existe", 1]]"#,
        );
        assert_eq!(ignored, 1);
        let total = 48_000;
        let (mut track, mut master, mut out) = (Vec::new(), Vec::new(), Vec::new());
        let (mut l, mut r) = (vec![0.0f32; 1024], vec![0.0f32; 1024]);
        let mut done = 0;
        while done < total {
            let n = o.process(1024.min(total - done));
            assert_eq!(o.captured(0, &mut l, &mut r), n);
            track.extend_from_slice(&l[..n]);
            assert_eq!(o.captured(1, &mut l, &mut r), n);
            master.extend_from_slice(&l[..n]);
            assert_eq!(o.captured(-1, &mut l, &mut r), n);
            out.extend_from_slice(&l[..n]);
            done += n;
        }
        // a faixa: o clipe desde o primeiro quadro (o preparo do render compensa o limitador)
        let level = track[100];
        assert!(level > 0.2, "nível da faixa {level}");
        assert!(track[..24_000 - 64].iter().all(|&s| (s - level).abs() < 1e-3), "a faixa não ficou constante no clipe");
        assert!(track[24_000 + 64..].iter().all(|&s| s.abs() < 1e-4), "sobrou som depois do clipe");
        // o master capturado é a própria saída do process
        assert_eq!(master, out);
        assert!(master[100] > 0.2);
        assert!(master[30_000..].iter().all(|&s| s.abs() < 1e-3));
        // índices inválidos: silêncio e 0 quadros do bloco
        assert_eq!(o.captured(7, &mut l, &mut r), 0);
        assert_eq!(o.captured(-2, &mut l, &mut r), 0);
        assert!(l.iter().all(|&s| s == 0.0));
    }

    #[test]
    fn blocks_are_limited_to_max_block_and_handles_are_independent() {
        let a = keep(Offline::new(44_100.0, test_apply));
        let b = keep(Offline::new(48_000.0, test_apply));
        assert_ne!(a, b);
        assert_eq!(with(a, |o| o.process(100_000)), Some(MAX_BLOCK));
        assert_eq!(with(b, |o| o.engine.rate()), Some(48_000.0));
        assert!(free(a));
        assert_eq!(with(a, |o| o.process(10)), None);
        assert!(free(b));
    }
}
