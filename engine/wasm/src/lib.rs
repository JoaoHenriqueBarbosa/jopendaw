//! O motor exposto como funções C para o AudioWorklet (`app/web/engine/worklet.js`).
//!
//! Sem wasm-bindgen: o escopo do worklet não tem `TextDecoder`, `fetch` e cia, e a cola que ele
//! gera conta com isso. Aqui a interface é só número e ponteiro: o JS pede memória com [`alloc`],
//! copia as amostras para lá e passa o ponteiro; quem recebe o ponteiro vira dono da memória.
//!
//! Tudo roda na thread de áudio do navegador, uma chamada por vez: o motor global não precisa de
//! trava.

// O contrato de segurança de todas as funções é o do topo do arquivo: ponteiros vindos de `alloc`.
#![allow(clippy::missing_safety_doc)]

use std::cell::UnsafeCell;

use jopendaw_engine::{Clip, Engine, Sample};

struct Global(UnsafeCell<Option<Engine>>);
// o wasm do worklet tem uma thread só
unsafe impl Sync for Global {}

static ENGINE: Global = Global(UnsafeCell::new(None));

fn engine() -> &'static mut Engine {
    // SAFETY: uma thread, e nenhuma função deste arquivo guarda a referência entre chamadas
    unsafe { (*ENGINE.0.get()).get_or_insert_with(|| Engine::new(48_000.0)) }
}

unsafe fn take(ptr: *mut f32, len: usize) -> Vec<f32> {
    if ptr.is_null() {
        return Vec::new();
    }
    // SAFETY: `ptr` veio de `alloc(len)`, que fez um Box<[f32]> de exatamente `len`
    unsafe { Box::from_raw(std::ptr::slice_from_raw_parts_mut(ptr, len)).into_vec() }
}

/// Reserva `len` floats zerados; o JS escreve nelas pela `memory.buffer`.
#[unsafe(no_mangle)]
pub extern "C" fn alloc(len: usize) -> *mut f32 {
    Box::into_raw(vec![0.0f32; len].into_boxed_slice()) as *mut f32
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn dealloc(ptr: *mut f32, len: usize) {
    drop(unsafe { take(ptr, len) });
}

#[unsafe(no_mangle)]
pub extern "C" fn init(rate: f64) {
    unsafe { *ENGINE.0.get() = Some(Engine::new(rate)) };
}

/// Enche os `n` quadros em `left`/`right` (memórias de `alloc`) e avança o transporte.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn process(left: *mut f32, right: *mut f32, n: usize) {
    let (l, r) = unsafe { (std::slice::from_raw_parts_mut(left, n), std::slice::from_raw_parts_mut(right, n)) };
    engine().process(l, r);
}

/// Entrega um áudio decodificado ao motor. `right` nulo é mono. O motor fica dono das memórias.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn sample_load(id: u32, left: *mut f32, right: *mut f32, frames: usize, rate: f64) {
    let mut ch = vec![unsafe { take(left, frames) }];
    if !right.is_null() {
        ch.push(unsafe { take(right, frames) });
    }
    engine().load_sample(id, Sample::new(ch, rate));
}

#[unsafe(no_mangle)]
pub extern "C" fn sample_drop(id: u32) {
    engine().drop_sample(id);
}

#[unsafe(no_mangle)]
pub extern "C" fn tempo(bpm: f64, beats_per_bar: u32) {
    engine().set_tempo(bpm, beats_per_bar);
}

#[unsafe(no_mangle)]
pub extern "C" fn play() {
    engine().play();
}

#[unsafe(no_mangle)]
pub extern "C" fn stop() {
    engine().stop();
}

#[unsafe(no_mangle)]
pub extern "C" fn seek(beat: f64) {
    engine().seek(beat);
}

#[unsafe(no_mangle)]
pub extern "C" fn loop_set(on: u32, start: f64, end: f64) {
    engine().set_loop(on != 0, start, end);
}

#[unsafe(no_mangle)]
pub extern "C" fn metronome(on: u32, gain: f32) {
    engine().set_metronome(on != 0, gain);
}

#[unsafe(no_mangle)]
pub extern "C" fn tracks(n: usize) {
    engine().set_track_count(n);
}

#[unsafe(no_mangle)]
pub extern "C" fn track(i: usize, gain: f32, pan: f32, mute: u32, solo: u32) {
    if let Some(t) = engine().track_mut(i) {
        t.gain = gain;
        t.pan = pan;
        t.mute = mute != 0;
        t.solo = solo != 0;
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn master(gain: f32, pan: f32) {
    let m = engine().master_mut();
    m.gain = gain;
    m.pan = pan;
}

#[unsafe(no_mangle)]
pub extern "C" fn clips_clear() {
    engine().clear_clips();
}

#[unsafe(no_mangle)]
#[allow(clippy::too_many_arguments)]
pub extern "C" fn clip_add(track: usize, sample: u32, start: f64, offset: f64, length: f64, gain: f32, fade_in: f64, fade_out: f64) {
    engine().add_clip(Clip { track, sample, start, offset, length, gain, fade_in, fade_out });
}

#[unsafe(no_mangle)]
pub extern "C" fn beat() -> f64 {
    engine().beat()
}

#[unsafe(no_mangle)]
pub extern "C" fn playing() -> u32 {
    engine().playing() as u32
}

/// Escreve em `out` os picos desde a última leitura: (esq, dir) de cada faixa e por último o
/// master. Devolve quantos floats escreveu (no máximo `max`).
#[unsafe(no_mangle)]
pub unsafe extern "C" fn peaks(out: *mut f32, max: usize) -> usize {
    let out = unsafe { std::slice::from_raw_parts_mut(out, max) };
    let e = engine();
    let mut n = 0;
    let mut put = |(l, r): (f32, f32)| {
        if n + 2 <= max {
            out[n] = l;
            out[n + 1] = r;
            n += 2;
        }
    };
    for i in 0..e.tracks().len() {
        put(e.track_mut(i).map(|t| t.take_peaks()).unwrap_or_default());
    }
    put(e.master_mut().take_peaks());
    n
}
