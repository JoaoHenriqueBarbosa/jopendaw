//! Só para testes: conta as alocações de uma thread para provar que o caminho de áudio (eventos e
//! `render`) não aloca depois de criado.
//!
//! O alocador global embrulha o do sistema e só conta enquanto a thread que chamou [`count`] está
//! dentro dele; as outras threads de teste rodando em paralelo não interferem.

use std::alloc::{GlobalAlloc, Layout, System};
use std::cell::Cell;

struct Counting;

thread_local! {
    /// Alocações da thread enquanto `count` roda; `None` fora dele.
    static COUNT: Cell<Option<usize>> = const { Cell::new(None) };
}

fn bump() {
    // `try_with`: o alocador também roda na criação e no fim das threads, quando o TLS não existe
    let _ = COUNT.try_with(|c| {
        if let Some(n) = c.get() {
            c.set(Some(n + 1));
        }
    });
}

// SAFETY: só delega ao alocador do sistema; a contagem não aloca (Cell em TLS com inicializador const).
unsafe impl GlobalAlloc for Counting {
    unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
        bump();
        unsafe { System.alloc(layout) }
    }

    unsafe fn dealloc(&self, ptr: *mut u8, layout: Layout) {
        unsafe { System.dealloc(ptr, layout) }
    }

    unsafe fn alloc_zeroed(&self, layout: Layout) -> *mut u8 {
        bump();
        unsafe { System.alloc_zeroed(layout) }
    }

    unsafe fn realloc(&self, ptr: *mut u8, layout: Layout, new_size: usize) -> *mut u8 {
        bump();
        unsafe { System.realloc(ptr, layout, new_size) }
    }
}

#[global_allocator]
static ALLOCATOR: Counting = Counting;

/// Roda `f` e devolve quantas alocações ela fez nesta thread.
pub fn count(f: impl FnOnce()) -> usize {
    COUNT.with(|c| c.set(Some(0)));
    f();
    COUNT.with(|c| c.replace(None)).unwrap_or(0)
}
