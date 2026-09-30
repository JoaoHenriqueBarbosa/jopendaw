//! Alocador global que tira da thread de áudio a liberação de memória.
//!
//! O motor solta memória em alguns comandos: um áudio recarregado ou esquecido (`load_sample` sobre
//! um id que já existia, `drop_sample`), um instrumento ou efeito trocado, uma lista que cresceu. A
//! API dele não devolve o que soltou, e liberar um bloco grande no alocador do sistema pode virar
//! `munmap` (chamada ao kernel) no meio do callback do AAudio. Então toda liberação feita dentro do
//! callback de áudio vira um pedido numa fila fixa, sem trava; quem tem tempo (a thread do Dart, a
//! cada leitura de estado, e o supervisor) libera de verdade em [`collect`]. Fila cheia (ninguém
//! coletando por muito tempo): libera ali mesmo, que ainda é melhor que perder memória.
//!
//! Fora do callback é o alocador do sistema puro. A thread de áudio se marca com [`AudioThread`]
//! pelo tempo do callback; a identificação é pelo `pthread_self`, que não aloca (um `thread_local!`
//! aqui poderia alocar no primeiro acesso, dentro do próprio alocador).

use std::alloc::{GlobalAlloc, Layout, System};
use std::sync::Mutex;
use std::sync::atomic::{AtomicPtr, AtomicUsize, Ordering};

/// Liberações que cabem na fila entre uma coleta e outra: com a coleta a ~60 Hz, sobra muito.
const DEFERRED: usize = 8192;

struct Slot {
    ptr: AtomicPtr<u8>,
    size: AtomicUsize,
    align: AtomicUsize,
}

static SLOTS: [Slot; DEFERRED] =
    [const { Slot { ptr: AtomicPtr::new(std::ptr::null_mut()), size: AtomicUsize::new(0), align: AtomicUsize::new(0) } }; DEFERRED];

/// Próxima posição a escrever (só a thread marcada escreve) e a próxima a coletar.
static HEAD: AtomicUsize = AtomicUsize::new(0);
static TAIL: AtomicUsize = AtomicUsize::new(0);

/// `pthread_self` da thread que está no callback de áudio agora (0 = nenhuma).
static AUDIO_THREAD: AtomicUsize = AtomicUsize::new(0);

/// Liberações feitas direto na thread de áudio porque a fila estava cheia, e as adiadas, desde o
/// começo (diagnóstico).
static OVERFLOWS: AtomicUsize = AtomicUsize::new(0);
static DEFERRALS: AtomicUsize = AtomicUsize::new(0);

/// Um coletor por vez (a fila tem um consumidor só).
static COLLECTING: Mutex<()> = Mutex::new(());

fn this_thread() -> usize {
    // SAFETY: pthread_self não tem pré-condição; nunca devolve 0 para uma thread viva
    unsafe { libc::pthread_self() as usize }
}

fn on_audio_thread() -> bool {
    let t = AUDIO_THREAD.load(Ordering::Relaxed);
    t != 0 && t == this_thread()
}

/// Enfileira a liberação; `false` se a fila está cheia.
fn defer(ptr: *mut u8, layout: Layout) -> bool {
    let head = HEAD.load(Ordering::Relaxed);
    let tail = TAIL.load(Ordering::Acquire);
    if head.wrapping_sub(tail) >= DEFERRED {
        return false;
    }
    let slot = &SLOTS[head % DEFERRED];
    slot.ptr.store(ptr, Ordering::Relaxed);
    slot.size.store(layout.size(), Ordering::Relaxed);
    slot.align.store(layout.align(), Ordering::Relaxed);
    HEAD.store(head.wrapping_add(1), Ordering::Release);
    DEFERRALS.fetch_add(1, Ordering::Relaxed);
    true
}

/// O alocador do processo (só o código Rust desta biblioteca passa por ele).
pub struct RtAlloc;

unsafe impl GlobalAlloc for RtAlloc {
    unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
        unsafe { System.alloc(layout) }
    }

    unsafe fn alloc_zeroed(&self, layout: Layout) -> *mut u8 {
        unsafe { System.alloc_zeroed(layout) }
    }

    unsafe fn dealloc(&self, ptr: *mut u8, layout: Layout) {
        if on_audio_thread() {
            if defer(ptr, layout) {
                return;
            }
            OVERFLOWS.fetch_add(1, Ordering::Relaxed);
        }
        unsafe { System.dealloc(ptr, layout) }
    }

    unsafe fn realloc(&self, ptr: *mut u8, layout: Layout, new_size: usize) -> *mut u8 {
        if !on_audio_thread() {
            return unsafe { System.realloc(ptr, layout, new_size) };
        }
        // na thread de áudio: bloco novo, cópia e a liberação do velho para depois
        // SAFETY: o contrato do realloc garante tamanho não nulo e alinhamento válido
        let new_layout = unsafe { Layout::from_size_align_unchecked(new_size, layout.align()) };
        let new = unsafe { System.alloc(new_layout) };
        if !new.is_null() {
            unsafe { std::ptr::copy_nonoverlapping(ptr, new, layout.size().min(new_size)) };
            unsafe { self.dealloc(ptr, layout) };
        }
        new
    }
}

/// Libera de verdade o que a thread de áudio deixou na fila. Chame fora dela.
pub fn collect() -> usize {
    let _one = COLLECTING.lock().unwrap_or_else(|e| e.into_inner());
    let tail = TAIL.load(Ordering::Relaxed);
    let head = HEAD.load(Ordering::Acquire);
    let mut n = 0;
    let mut i = tail;
    while i != head {
        let slot = &SLOTS[i % DEFERRED];
        let ptr = slot.ptr.load(Ordering::Relaxed);
        let (size, align) = (slot.size.load(Ordering::Relaxed), slot.align.load(Ordering::Relaxed));
        // SAFETY: o par veio de um `dealloc` legítimo, com o layout da alocação
        unsafe { System.dealloc(ptr, Layout::from_size_align_unchecked(size, align)) };
        i = i.wrapping_add(1);
        n += 1;
    }
    TAIL.store(head, Ordering::Release);
    n
}

/// Liberações na fila esperando a coleta.
#[cfg(test)]
pub fn pending() -> usize {
    HEAD.load(Ordering::Acquire).wrapping_sub(TAIL.load(Ordering::Acquire))
}

/// Liberações que não couberam na fila e foram feitas na thread de áudio, desde o começo.
pub fn overflows() -> usize {
    OVERFLOWS.load(Ordering::Relaxed)
}

/// Liberações adiadas desde o começo.
#[cfg(test)]
pub fn deferrals() -> usize {
    DEFERRALS.load(Ordering::Relaxed)
}

/// Marca a thread atual como a de áudio enquanto viver. Só uma thread fica marcada por vez (a
/// fila tem um produtor só): se outra já está marcada, esta segue sem adiar nada.
pub struct AudioThread {
    me: usize,
}

impl AudioThread {
    pub fn enter() -> Self {
        let me = this_thread();
        match AUDIO_THREAD.compare_exchange(0, me, Ordering::AcqRel, Ordering::Relaxed) {
            Ok(_) => Self { me },
            Err(_) => Self { me: 0 },
        }
    }
}

impl Drop for AudioThread {
    fn drop(&mut self) {
        if self.me != 0 {
            let _ = AUDIO_THREAD.compare_exchange(self.me, 0, Ordering::AcqRel, Ordering::Relaxed);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A marca é global e os testes rodam em paralelo: este é o único teste que marca a thread (os
    /// do núcleo chamam o `render` sem marca), e as contagens são pelos totais, que as coletas dos
    /// outros testes não mexem.
    #[test]
    fn frees_on_the_audio_thread_wait_for_collect() {
        // black_box: sem ele o otimizador tira o par alocação/liberação de quem nunca é usado
        use std::hint::black_box;
        let big = black_box(vec![1.0f32; 1 << 20]);
        let small = black_box(Box::new(7u64));
        let before = deferrals();
        {
            let mark = AudioThread::enter();
            assert_ne!(mark.me, 0, "outra thread marcada");
            drop(big);
            drop(small);
            // realloc na thread de áudio também adia o bloco velho
            let mut v: Vec<u8> = black_box(Vec::with_capacity(16));
            v.extend_from_slice(black_box(&[0; 64]));
            drop(black_box(v));
            assert!(deferrals() >= before + 4, "as liberações não foram adiadas");
        }
        // fora da marca libera direto
        let outside = deferrals();
        drop(black_box(vec![0u8; 1024]));
        assert_eq!(deferrals(), outside);
        collect();
        assert_eq!(pending(), 0);
    }
}
