//! O motor do jopendaw como biblioteca nativa do app Android (`libjopendaw_engine.so`), aberta
//! pelo Dart com `dart:ffi`. O mesmo crate do motor que roda em WASM no navegador, com o mesmo
//! protocolo de chamadas por nome (`engine::api::apply`), então o app Android faz tudo o que a web
//! faz, processando no aparelho.
//!
//! # Threads
//!
//! A thread de áudio (o callback do AAudio) é dona do [`Engine`](jopendaw_engine::Engine). O Dart
//! chama as funções `jd_*` na thread dele; os comandos vão por uma fila sem trava (rtrb) e são
//! aplicados antes de cada bloco. Nada aloca nem trava na thread de áudio: os áudios chegam já
//! montados pela fila, o que ela solta volta por outra fila para ser liberado fora dela, e o que o
//! motor solta por dentro o alocador desta biblioteca adia ([`alloc`]). O estado (batida, tocando,
//! picos, indicador do efeito, espectro) é publicado pela thread de áudio sem trava e lido pelo
//! Dart por polling (~60 Hz).
//!
//! Saída e entrada são streams do AAudio (baixa latência, taxa nativa do aparelho, estéreo float)
//! carregados em tempo de execução: a biblioteca abre até no Android 7 (sem AAudio), onde só o
//! áudio ao vivo falha e a decodificação e o render continuam. Fora do Android (os testes no
//! macOS) não há E/S e o host aplica os comandos direto.
//!
//! # Convenções da FFI
//!
//! Só números e ponteiros (C ABI). Tamanhos são `size_t`; handles são `uint64_t`, 0 = falhou.
//! Ponteiros de saída pertencem a quem chama e precisam ter o tamanho indicado; os de entrada são
//! copiados antes de a função voltar. Os códigos de erro são negativos (`ERR_*`). Toda função pega
//! o pânico e devolve [`ERR_PANIC`] (ou o valor neutro de quem não devolve código).
//!
//! | função | o quê |
//! |---|---|
//! | `jd_start() -> f64` | abre a saída (e o motor, na 1ª vez); devolve a taxa, ou um `ERR_*` |
//! | `jd_stop()` | fecha saída e entrada; o motor fica (o `jd_start` seguinte continua dali) |
//! | `jd_calls(json, len) -> i32` | `[[nome, arg...], ...]` como o worklet recebe; 0 ou `ERR_*` |
//! | `jd_sample_load(id, l, r, frames, rate) -> i32` | copia um áudio (r nulo = mono) |
//! | `jd_sample_drop(id) -> i32` | esquece um áudio |
//! | `jd_state(out: *f64, max) -> i32` | `[batida, tocando, fxMeter, n, picos...]`; quantos valores |
//! | `jd_spectrum(out: *f32, n) -> i32` | até 1024 faixas em dB; 0 sem faixa observada |
//! | `jd_decode(bytes, len) -> u64` | decodifica (wav, aiff, flac, mp3, ogg, aac/m4a, alac) |
//! | `jd_decoded_info(h, *i64 frames, *i32 channels, *f64 rate) -> i32` | 0 ou `ERR_BAD_ARG` |
//! | `jd_decoded_copy(h, channel, out: *f32) -> i32` | copia `frames` floats do canal |
//! | `jd_decoded_free(h)` | |
//! | `jd_stretch(l, r, frames, rate, ratio, semitones) -> u64` | warp offline; handle como o de `jd_decode` |
//! | `jd_detect_bpm(l, r, frames, rate, *f64 bpm, *f64 conf) -> i32` | andamento 60..200 (0 = não deu) |
//! | `jd_input_start(device) -> f64` | abre a entrada (0 = padrão); latência em s ou `ERR_*` |
//! | `jd_input_stop()` | |
//! | `jd_input_devices(out: *u8, max) -> i32` | JSON `[["id", "nome"], ...]`; bytes necessários |
//! | `jd_capture(on) -> i32` | liga/desliga a captura (áudio da entrada e notas ao vivo) |
//! | `jd_recorded(l, r, max, *f64 beat) -> i32` | quadros capturados de um trecho, batida do 1º |
//! | `jd_input_level() -> f32` | pico da entrada desde a última leitura; −1 = a entrada caiu |
//! | `jd_rec_notes(out: *f32, max) -> i32` | notas da captura encerrada (5 floats cada); −1 = ainda não |
//! | `jd_offline_new(rate) -> u64` | um motor fora de tempo real, sem thread de áudio |
//! | `jd_offline_calls(h, json, len) -> i32` | chamadas; quantas o motor não conhecia, ou `ERR_*` |
//! | `jd_offline_sample(h, id, l, r, frames, rate) -> i32` | |
//! | `jd_offline_process(h, frames) -> i32` | processa até 4096 quadros; quantos |
//! | `jd_offline_captured(h, index, l, r, n) -> i32` | −1 = saída do process, ≥ 0 = `capture_add` |
//! | `jd_offline_free(h)` | |
//! | `jd_latency() -> f64` | latência de saída em s (0 sem saída) |

// O contrato de segurança de todas as funções é o do topo: ponteiros válidos do tamanho indicado.
#![allow(clippy::missing_safety_doc)]
// Fora do Android não há thread de áudio: o caminho dela (render, entrada, supervisor) só roda nos
// testes, e o compilador o veria como código morto.
#![cfg_attr(not(target_os = "android"), allow(dead_code))]

mod alloc;
mod call;
mod capture;
mod core;
mod decode;
mod host;
mod offline;
mod platform;
mod state;

use std::panic::{AssertUnwindSafe, catch_unwind};
use std::sync::{Mutex, Once};

use jopendaw_engine::{Sample, api};

use crate::host::Host;
use crate::state::SPECTRUM_BINS;

#[global_allocator]
static ALLOC: alloc::RtAlloc = alloc::RtAlloc;

/// `jd_start` ainda não foi chamado (ou falhou), ou a saída não está aberta.
pub const ERR_NOT_STARTED: i32 = -1;
/// JSON malformado ou chamada inválida (nome longo demais, argumento que não é número).
pub const ERR_BAD_JSON: i32 = -2;
/// A fila de comandos continua cheia: a thread de áudio parou de consumir.
pub const ERR_BUSY: i32 = -3;
/// Ponteiro nulo, tamanho ou taxa inválidos, handle inexistente.
pub const ERR_BAD_ARG: i32 = -4;
/// Falha interna (pânico pego); se foi na thread de áudio, o motor fica mudo até reiniciar o app.
pub const ERR_PANIC: i32 = -5;
/// Sem AAudio (Android 7) ou fora do Android.
pub const ERR_UNSUPPORTED: i32 = -6;
/// O dispositivo de áudio não abriu (ocupado, formato recusado, erro do sistema).
pub const ERR_DEVICE: i32 = -7;
/// A entrada escolhida não existe (desconectada).
pub const ERR_NOT_FOUND: i32 = -8;
/// Sem a permissão de gravar áudio (RECORD_AUDIO).
pub const ERR_DENIED: i32 = -9;
/// Não coube na memória.
pub const ERR_MEMORY: i32 = -10;

static HOST: Mutex<Option<Host>> = Mutex::new(None);

/// Roda `f` pegando o pânico (que vira `fallback`).
fn guard<R>(fallback: R, f: impl FnOnce() -> R) -> R {
    catch_unwind(AssertUnwindSafe(f)).unwrap_or(fallback)
}

/// Roda `f` com o host; sem host, `missing`.
fn with_host<R>(missing: R, f: impl FnOnce(&mut Host) -> R) -> R {
    let mut g = HOST.lock().unwrap_or_else(|e| e.into_inner());
    match g.as_mut() {
        Some(h) => f(h),
        None => missing,
    }
}

/// O pânico vai para o log do sistema (no Android o stderr some).
fn install_panic_hook() {
    static ONCE: Once = Once::new();
    ONCE.call_once(|| {
        std::panic::set_hook(Box::new(|info| platform::log(&format!("pânico: {info}"))));
    });
}

unsafe fn bytes<'a>(ptr: *const u8, len: usize) -> Option<&'a [u8]> {
    if ptr.is_null() {
        return None;
    }
    // SAFETY: o contrato da FFI (ponteiro válido de `len` bytes)
    Some(unsafe { std::slice::from_raw_parts(ptr, len) })
}

/// Copia um áudio vindo do Dart num [`Sample`] (`right` nulo = mono).
unsafe fn sample_from(left: *const f32, right: *const f32, frames: usize, rate: f64) -> Result<Sample, i32> {
    if left.is_null() || !(rate.is_finite() && rate > 0.0) {
        return Err(ERR_BAD_ARG);
    }
    let copy = |p: *const f32| -> Result<Vec<f32>, i32> {
        let mut v = Vec::new();
        v.try_reserve_exact(frames).map_err(|_| ERR_MEMORY)?;
        // SAFETY: o contrato da FFI (`frames` floats)
        v.extend_from_slice(unsafe { std::slice::from_raw_parts(p, frames) });
        Ok(v)
    };
    let mut channels = vec![copy(left)?];
    if !right.is_null() {
        channels.push(copy(right)?);
    }
    Ok(Sample::new(channels, rate))
}

// ------------------------------------------------------------------ motor que toca

/// Abre a saída de áudio (baixa latência, taxa nativa) e, na primeira vez, cria o motor nessa
/// taxa. Devolve a taxa, ou um `ERR_*` (como f64). Depois de um `jd_stop`, reabre na mesma taxa e
/// reabre a entrada que estava aberta. Depois de um `ERR_PANIC` (a thread de áudio caiu), recria
/// o motor vazio: o Dart reenvia os áudios e o documento como na primeira vez.
#[unsafe(no_mangle)]
pub extern "C" fn jd_start() -> f64 {
    install_panic_hook();
    guard(ERR_PANIC as f64, || {
        let mut g = HOST.lock().unwrap_or_else(|e| e.into_inner());
        if let Some(h) = g.as_mut()
            && h.broken()
        {
            platform::log("recriando o motor depois de um pânico na thread de áudio");
            h.stop();
            *g = None;
        }
        let r = match g.as_mut() {
            Some(h) => h.resume(),
            None => Host::open(api::apply).map(|h| {
                let rate = h.rate;
                *g = Some(h);
                rate
            }),
        };
        drop(g);
        platform::spawn_supervisor();
        r.unwrap_or_else(|e| e as f64)
    })
}

/// Fecha a saída e a entrada (app em segundo plano, tela do projeto fechada). O motor e tudo o
/// que ele tem ficam; os comandos continuam sendo aplicados, sem áudio.
#[unsafe(no_mangle)]
pub extern "C" fn jd_stop() {
    guard((), || with_host((), |h| h.stop()))
}

/// Chamadas do documento, `[[nome, arg...], ...]` em UTF-8, como o worklet recebe (números, e
/// booleanos como 0/1). A lista inteira é aplicada entre dois blocos, na ordem. 0 ou `ERR_*`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn jd_calls(json: *const u8, len: usize) -> i32 {
    guard(ERR_PANIC, || {
        let Some(bytes) = (unsafe { bytes(json, len) }) else { return ERR_BAD_ARG };
        // o parse é aqui, fora da trava do host
        let calls = match call::parse_calls(bytes) {
            Ok(c) => c,
            Err(e) => {
                platform::log(&format!("jd_calls: {e}"));
                return ERR_BAD_JSON;
            }
        };
        with_host(ERR_NOT_STARTED, |h| h.calls(calls).map_or_else(|e| e, |()| 0))
    })
}

/// Entrega um áudio decodificado ao motor (copiado): `frames` quadros em `left` e, se não nulo,
/// em `right`, na taxa `rate`. Recarregar um id troca o áudio.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn jd_sample_load(id: u32, left: *const f32, right: *const f32, frames: usize, rate: f64) -> i32 {
    guard(ERR_PANIC, || {
        let sample = match unsafe { sample_from(left, right, frames, rate) } {
            Ok(s) => s,
            Err(e) => return e,
        };
        with_host(ERR_NOT_STARTED, |h| h.load_sample(id, sample).map_or_else(|e| e, |()| 0))
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn jd_sample_drop(id: u32) -> i32 {
    guard(ERR_PANIC, || with_host(ERR_NOT_STARTED, |h| h.drop_sample(id).map_or_else(|e| e, |()| 0)))
}

/// Escreve em `out` (até `max` doubles): batida, tocando (0/1), indicador do efeito observado,
/// quantos picos seguem e os picos desde a última leitura (esq, dir de cada faixa e por último o
/// master). Devolve quantos valores escreveu (`4 + n`), ou `ERR_*` (`ERR_PANIC` = a thread de áudio
/// caiu).
#[unsafe(no_mangle)]
pub unsafe extern "C" fn jd_state(out: *mut f64, max: usize) -> i32 {
    guard(ERR_PANIC, || {
        if out.is_null() {
            return ERR_BAD_ARG;
        }
        // SAFETY: o contrato da FFI
        let out = unsafe { std::slice::from_raw_parts_mut(out, max) };
        with_host(ERR_NOT_STARTED, |h| h.state(out))
    })
}

/// Escreve em `out` até `n` magnitudes em dB (−120..0) do espectro da faixa observada
/// (`watch_analyzer`): 1024 faixas lineares de 0 à metade da taxa, como o `analyzer` do wasm.
/// Devolve quantas escreveu; 0 sem faixa observada.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn jd_spectrum(out: *mut f32, n: usize) -> i32 {
    guard(ERR_PANIC, || {
        if out.is_null() {
            return ERR_BAD_ARG;
        }
        // SAFETY: o contrato da FFI
        let out = unsafe { std::slice::from_raw_parts_mut(out, n.min(SPECTRUM_BINS)) };
        with_host(0, |h| h.spectrum(out) as i32)
    })
}

/// Latência de saída em segundos (do buffer ao alto-falante, pelo relógio do AAudio); 0 sem saída.
#[unsafe(no_mangle)]
pub extern "C" fn jd_latency() -> f64 {
    guard(0.0, || with_host(0.0, |h| h.io.output_latency()))
}

// ------------------------------------------------------------------ decodificação

/// Decodifica um arquivo de áudio inteiro (o formato é descoberto pelo conteúdo). Devolve o
/// handle, 0 se não decodificou (formato desconhecido, arquivo corrompido, memória).
#[unsafe(no_mangle)]
pub unsafe extern "C" fn jd_decode(bytes_ptr: *const u8, len: usize) -> u64 {
    guard(0, || {
        let Some(bytes) = (unsafe { bytes(bytes_ptr, len) }) else { return 0 };
        match decode::decode(bytes) {
            Ok(d) => decode::keep(d),
            Err(e) => {
                platform::log(&format!("jd_decode: não decodificou ({e:?}, {len} bytes)"));
                0
            }
        }
    })
}

/// Quadros, canais (1 ou 2) e taxa do decodificado. 0, ou `ERR_BAD_ARG` com handle inexistente.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn jd_decoded_info(handle: u64, frames: *mut i64, channels: *mut i32, rate: *mut f64) -> i32 {
    guard(ERR_PANIC, || {
        let Some((f, c, r)) = decode::info(handle) else { return ERR_BAD_ARG };
        // SAFETY: o contrato da FFI (nulo = quem chama não quer esse valor)
        unsafe {
            if !frames.is_null() {
                *frames = f as i64;
            }
            if !channels.is_null() {
                *channels = c as i32;
            }
            if !rate.is_null() {
                *rate = r;
            }
        }
        0
    })
}

/// Copia o canal `channel` (0 ou 1) para `out`, que precisa ter os `frames` floats de
/// `jd_decoded_info`. 0 ou `ERR_BAD_ARG`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn jd_decoded_copy(handle: u64, channel: i32, out: *mut f32) -> i32 {
    guard(ERR_PANIC, || {
        if out.is_null() || channel < 0 {
            return ERR_BAD_ARG;
        }
        decode::with_channel(handle, channel as usize, |c| {
            // SAFETY: o contrato da FFI (`frames` floats)
            unsafe { std::ptr::copy_nonoverlapping(c.as_ptr(), out, c.len()) };
            0
        })
        .unwrap_or(ERR_BAD_ARG)
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn jd_decoded_free(handle: u64) {
    guard((), || {
        decode::free(handle);
    })
}

// ------------------------------------------------------------------ warp

/// Copia os canais vindos do Dart (`right` nulo = mono).
unsafe fn channels_from(left: *const f32, right: *const f32, frames: usize, rate: f64) -> Option<Vec<Vec<f32>>> {
    if left.is_null() || frames == 0 || !(rate.is_finite() && rate > 0.0) {
        return None;
    }
    // SAFETY: o contrato da FFI (`frames` floats por ponteiro não nulo)
    let mut ch = vec![unsafe { std::slice::from_raw_parts(left, frames) }.to_vec()];
    if !right.is_null() {
        ch.push(unsafe { std::slice::from_raw_parts(right, frames) }.to_vec());
    }
    Some(ch)
}

/// Estica (`ratio` = duração final / original, 0,25..4) e transpõe (`semitones`, −24..24) um
/// áudio, offline e na thread que chamar (o Dart usa um isolate). Devolve um handle no mesmo
/// formato de `jd_decode`: `jd_decoded_info`, `jd_decoded_copy` e `jd_decoded_free` leem e soltam
/// o resultado. 0 se falhou (argumento inválido, memória).
#[unsafe(no_mangle)]
pub unsafe extern "C" fn jd_stretch(left: *const f32, right: *const f32, frames: usize, rate: f64, ratio: f64, semitones: f64) -> u64 {
    guard(0, || {
        let Some(ch) = (unsafe { channels_from(left, right, frames, rate) }) else { return 0 };
        let out = jopendaw_engine::stretch::stretch(&ch, rate, ratio, semitones);
        decode::keep(decode::Decoded { channels: out, rate })
    })
}

/// Estima o andamento (60..200 BPM): escreve o BPM (0 = não deu) e a confiança (0..1). 0 ou
/// `ERR_BAD_ARG`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn jd_detect_bpm(left: *const f32, right: *const f32, frames: usize, rate: f64, bpm: *mut f64, confidence: *mut f64) -> i32 {
    guard(ERR_PANIC, || {
        let Some(ch) = (unsafe { channels_from(left, right, frames, rate) }) else { return ERR_BAD_ARG };
        let t = jopendaw_engine::stretch::detect_bpm(&ch, rate);
        // SAFETY: o contrato da FFI (nulo = quem chama não quer esse valor)
        unsafe {
            if !bpm.is_null() {
                *bpm = t.bpm;
            }
            if !confidence.is_null() {
                *confidence = t.confidence;
            }
        }
        0
    })
}

// ------------------------------------------------------------------ entrada e gravação

/// Abre a entrada de áudio (`device` 0 = a padrão do sistema, senão um id de `jd_input_devices`)
/// sem processamento de voz, e a liga ao motor (monitoramento, medidor, captura). Abrir de novo
/// troca a entrada. Devolve a latência de entrada em segundos, ou `ERR_*`: `ERR_NOT_STARTED` sem
/// `jd_start`, `ERR_DENIED` sem a permissão RECORD_AUDIO, `ERR_NOT_FOUND` com a entrada escolhida
/// desconectada, `ERR_DEVICE` se o sistema não abriu (ocupada), `ERR_UNSUPPORTED` fora do Android.
#[unsafe(no_mangle)]
pub extern "C" fn jd_input_start(device: i32) -> f64 {
    guard(ERR_PANIC as f64, || with_host(ERR_NOT_STARTED as f64, |h| h.input_start(device).unwrap_or_else(|e| e as f64)))
}

/// Fecha a entrada (o sistema solta o microfone).
#[unsafe(no_mangle)]
pub extern "C" fn jd_input_stop() {
    guard((), || with_host((), |h| h.input_stop()))
}

/// Escreve em `out` as entradas de áudio conectadas em JSON UTF-8, `[["id", "nome"], ...]` (sem a
/// padrão, que é o id 0). Devolve quantos bytes o JSON tem; se for mais que `max`, nada é escrito
/// e quem chama tenta de novo com espaço maior.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn jd_input_devices(out: *mut u8, max: usize) -> i32 {
    guard(ERR_PANIC, || {
        let json = platform::input_devices();
        if !out.is_null() && json.len() <= max {
            // SAFETY: o contrato da FFI (`max` bytes)
            unsafe { std::ptr::copy_nonoverlapping(json.as_ptr(), out, json.len()) };
        }
        json.len() as i32
    })
}

/// Liga (1) ou desliga (0) a captura: com o transporte tocando, o que entra vai para o anel
/// (`jd_recorded`) e o motor registra as notas tocadas ao vivo; desligar fecha o áudio e entrega
/// as notas (`jd_rec_notes`). Sem entrada aberta, só as notas.
#[unsafe(no_mangle)]
pub extern "C" fn jd_capture(on: i32) -> i32 {
    guard(ERR_PANIC, || with_host(ERR_NOT_STARTED, |h| h.capture(on != 0).map_or_else(|e| e, |()| 0)))
}

/// Lê em `left`/`right` (até `max` quadros) o áudio capturado desde a última leitura, de um trecho
/// contínuo só (um salto de posição ou uma parada começam outro, lido na chamada seguinte), e
/// escreve em `beat` a batida do primeiro quadro. Devolve quantos quadros leu (0 = nada novo).
/// Chame até voltar 0.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn jd_recorded(left: *mut f32, right: *mut f32, max: usize, beat: *mut f64) -> i32 {
    guard(ERR_PANIC, || {
        if left.is_null() || right.is_null() || left == right {
            return ERR_BAD_ARG;
        }
        // SAFETY: o contrato da FFI (duas memórias diferentes de `max` floats)
        let (l, r) = unsafe { (std::slice::from_raw_parts_mut(left, max), std::slice::from_raw_parts_mut(right, max)) };
        with_host(0, |h| {
            let (n, b) = h.recorded(l, r);
            if !beat.is_null() && n > 0 {
                // SAFETY: o contrato da FFI
                unsafe { *beat = b };
            }
            n as i32
        })
    })
}

/// Pico da entrada desde a última leitura (0..1); −1, uma vez, quando a entrada caiu sozinha e
/// não voltou (dispositivo desconectado): ela já está fechada.
#[unsafe(no_mangle)]
pub extern "C" fn jd_input_level() -> f32 {
    guard(0.0, || with_host(0.0, |h| h.input_level()))
}

/// Notas tocadas ao vivo durante a captura encerrada, em grupos de 5 floats (faixa, altura MIDI,
/// início e fim em batidas, velocidade 0..1), como o `rec_notes` do wasm. Devolve quantos floats
/// escreveu (as que não couberam ficam para a próxima chamada), −1 enquanto o fim da captura
/// ainda não chegou à thread de áudio (quando chega, todo o áudio dela já está em `jd_recorded`).
#[unsafe(no_mangle)]
pub unsafe extern "C" fn jd_rec_notes(out: *mut f32, max: usize) -> i32 {
    guard(ERR_PANIC, || {
        if out.is_null() {
            return ERR_BAD_ARG;
        }
        // SAFETY: o contrato da FFI
        let out = unsafe { std::slice::from_raw_parts_mut(out, max) };
        with_host(0, |h| h.rec_notes(out))
    })
}

// ------------------------------------------------------------------ render fora de tempo real

/// Um motor novo para render fora de tempo real, na taxa `rate` (8000..384000), sem thread de
/// áudio: tudo roda na thread que chamar (um isolate do Dart). 0 com taxa inválida.
#[unsafe(no_mangle)]
pub extern "C" fn jd_offline_new(rate: f64) -> u64 {
    guard(0, || {
        if !(8_000.0..=384_000.0).contains(&rate) {
            return 0;
        }
        offline::keep(offline::Offline::new(rate, api::apply))
    })
}

/// Aplica chamadas no motor do render, na ordem. Devolve quantas o motor não conhecia (ignoradas,
/// o resto vale), ou `ERR_*`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn jd_offline_calls(handle: u64, json: *const u8, len: usize) -> i32 {
    guard(ERR_PANIC, || {
        let Some(bytes) = (unsafe { bytes(json, len) }) else { return ERR_BAD_ARG };
        let Ok(calls) = call::parse_calls(bytes) else { return ERR_BAD_JSON };
        offline::with(handle, |o| o.calls(&calls) as i32).unwrap_or(ERR_BAD_ARG)
    })
}

/// Um áudio para o render (copiado), como `jd_sample_load`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn jd_offline_sample(handle: u64, id: u32, left: *const f32, right: *const f32, frames: usize, rate: f64) -> i32 {
    guard(ERR_PANIC, || {
        let sample = match unsafe { sample_from(left, right, frames, rate) } {
            Ok(s) => s,
            Err(e) => return e,
        };
        offline::with(handle, |o| {
            o.load_sample(id, sample);
            0
        })
        .unwrap_or(ERR_BAD_ARG)
    })
}

/// Processa o próximo bloco do render, até 4096 quadros. Devolve quantos processou.
#[unsafe(no_mangle)]
pub extern "C" fn jd_offline_process(handle: u64, frames: usize) -> i32 {
    guard(ERR_PANIC, || offline::with(handle, |o| o.process(frames) as i32).unwrap_or(ERR_BAD_ARG))
}

/// Copia para `left`/`right` (`n` quadros) o último bloco de uma saída: −1 = a saída do
/// `jd_offline_process` (o master depois do limitador), ≥ 0 = o índice que `capture_add` deu. O
/// que passar do bloco sai zerado. Devolve quantos quadros eram do bloco. Com `left == right`, só
/// o esquerdo é escrito.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn jd_offline_captured(handle: u64, index: i32, left: *mut f32, right: *mut f32, n: usize) -> i32 {
    guard(ERR_PANIC, || {
        if left.is_null() || right.is_null() {
            return ERR_BAD_ARG;
        }
        // SAFETY: o contrato da FFI; a mesma memória não vira duas referências mutáveis
        let l = unsafe { std::slice::from_raw_parts_mut(left, n) };
        let mut none: [f32; 0] = [];
        let r = if left == right { &mut none[..] } else { unsafe { std::slice::from_raw_parts_mut(right, n) } };
        offline::with(handle, |o| o.captured(index, l, r) as i32).unwrap_or(ERR_BAD_ARG)
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn jd_offline_free(handle: u64) {
    guard((), || {
        offline::free(handle);
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::decode::tests::{flac16, wav16};

    /// O host é global: os testes que mexem nele não podem rodar ao mesmo tempo.
    static SERIAL: Mutex<()> = Mutex::new(());

    fn calls(json: &str) -> i32 {
        unsafe { jd_calls(json.as_ptr(), json.len()) }
    }

    fn decode_through_ffi(bytes: &[u8]) -> (i64, i32, f64, Vec<Vec<f32>>) {
        unsafe {
            let h = jd_decode(bytes.as_ptr(), bytes.len());
            assert_ne!(h, 0);
            let (mut frames, mut channels, mut rate) = (0i64, 0i32, 0.0f64);
            assert_eq!(jd_decoded_info(h, &mut frames, &mut channels, &mut rate), 0);
            let mut out = Vec::new();
            for c in 0..channels {
                let mut buf = vec![0.0f32; frames as usize];
                assert_eq!(jd_decoded_copy(h, c, buf.as_mut_ptr()), 0);
                out.push(buf);
            }
            let mut spare = [0.0f32; 1];
            assert_eq!(jd_decoded_copy(h, channels, spare.as_mut_ptr()), ERR_BAD_ARG);
            jd_decoded_free(h);
            assert_eq!(jd_decoded_info(h, &mut frames, &mut channels, &mut rate), ERR_BAD_ARG);
            (frames, channels, rate, out)
        }
    }

    #[test]
    fn decode_wav_and_flac_through_the_c_abi() {
        let l: Vec<f32> = (0..2000).map(|i| (i as f32 * 0.01).sin() * 0.5).collect();
        let r: Vec<f32> = l.iter().map(|v| -v).collect();
        let (frames, channels, rate, out) = decode_through_ffi(&wav16(&[l.clone(), r.clone()], 32_000));
        assert_eq!((frames, channels, rate), (2000, 2, 32_000.0));
        assert!((out[1][500] - r[500]).abs() < 1e-4);
        let (frames, channels, rate, out) = decode_through_ffi(&flac16(std::slice::from_ref(&l), 96_000));
        assert_eq!((frames, channels, rate), (2000, 1, 96_000.0));
        assert!((out[0][1500] - l[1500]).abs() < 1e-4);
        unsafe {
            assert_eq!(jd_decode(std::ptr::null(), 10), 0);
            assert_eq!(jd_decode(b"nada".as_ptr(), 4), 0);
        }
    }

    #[test]
    fn host_surface_without_audio_output() {
        let _one = SERIAL.lock().unwrap_or_else(|e| e.into_inner());
        assert_eq!(jd_start(), 48_000.0);
        assert_eq!(calls("[]"), 0);
        assert_eq!(calls("isto não é json"), ERR_BAD_JSON);
        assert_eq!(unsafe { jd_calls(std::ptr::null(), 3) }, ERR_BAD_ARG);
        // o despachante decide o que conhece; a fila aceita qualquer nome
        assert_eq!(calls(r#"[["tempo", 100, 4], ["seek", 4], ["qualquer_coisa", 1]]"#), 0);
        let mut st = [0.0f64; 16];
        let n = unsafe { jd_state(st.as_mut_ptr(), st.len()) };
        assert!(n >= 6, "{n}");
        assert_eq!(st[3] as i32 + 4, n);
        assert_eq!(unsafe { jd_state(std::ptr::null_mut(), 4) }, ERR_BAD_ARG);
        let one = [0.25f32; 64];
        unsafe {
            assert_eq!(jd_sample_load(9, one.as_ptr(), std::ptr::null(), one.len(), 44_100.0), 0);
            assert_eq!(jd_sample_load(9, std::ptr::null(), std::ptr::null(), 1, 44_100.0), ERR_BAD_ARG);
            assert_eq!(jd_sample_load(9, one.as_ptr(), one.as_ptr(), one.len(), f64::NAN), ERR_BAD_ARG);
        }
        assert_eq!(jd_sample_drop(9), 0);
        // captura sem entrada: só notas, e nenhuma foi tocada
        assert_eq!(jd_capture(1), 0);
        assert_eq!(jd_capture(0), 0);
        let mut notes = [0.0f32; 10];
        assert_eq!(unsafe { jd_rec_notes(notes.as_mut_ptr(), notes.len()) }, 0);
        let (mut l, mut r) = ([0.0f32; 8], [0.0f32; 8]);
        let mut beat = -1.0;
        assert_eq!(unsafe { jd_recorded(l.as_mut_ptr(), r.as_mut_ptr(), 8, &mut beat) }, 0);
        assert_eq!(unsafe { jd_recorded(l.as_mut_ptr(), l.as_mut_ptr(), 8, &mut beat) }, ERR_BAD_ARG);
        assert_eq!(jd_input_start(0), ERR_UNSUPPORTED as f64);
        assert_eq!(jd_input_level(), 0.0);
        jd_input_stop();
        let mut spec = [0.0f32; 1024];
        assert_eq!(unsafe { jd_spectrum(spec.as_mut_ptr(), spec.len()) }, 0);
        assert_eq!(jd_latency(), 0.0);
        let mut json = [0u8; 16];
        assert_eq!(unsafe { jd_input_devices(json.as_mut_ptr(), json.len()) }, 2);
        assert_eq!(&json[..2], b"[]");
        assert_eq!(unsafe { jd_input_devices(json.as_mut_ptr(), 1) }, 2);
        jd_stop();
        assert_eq!(jd_start(), 48_000.0);
    }

    #[test]
    fn offline_surface() {
        assert_eq!(jd_offline_new(1000.0), 0);
        assert_eq!(jd_offline_new(f64::NAN), 0);
        let h = jd_offline_new(48_000.0);
        assert_ne!(h, 0);
        let s = [0.5f32; 4800];
        let json = r#"[["tempo", 120, 4], ["seek", 0], ["play"]]"#;
        unsafe {
            assert_eq!(jd_offline_sample(h, 1, s.as_ptr(), s.as_ptr(), s.len(), 48_000.0), 0);
            assert!(jd_offline_calls(h, json.as_ptr(), json.len()) >= 0);
            assert_eq!(jd_offline_calls(h, b"[".as_ptr(), 1), ERR_BAD_JSON);
        }
        assert_eq!(jd_offline_process(h, 10_000), 4096);
        let (mut l, mut r) = (vec![1.0f32; 5000], vec![1.0f32; 5000]);
        unsafe {
            assert_eq!(jd_offline_captured(h, -1, l.as_mut_ptr(), r.as_mut_ptr(), 5000), 4096);
            assert!(l[4096..].iter().all(|&v| v == 0.0));
            // a mesma memória nos dois lados: só o esquerdo
            assert_eq!(jd_offline_captured(h, -1, l.as_mut_ptr(), l.as_mut_ptr(), 5000), 4096);
            assert_eq!(jd_offline_captured(h, 3, l.as_mut_ptr(), r.as_mut_ptr(), 5000), 0);
        }
        jd_offline_free(h);
        assert_eq!(jd_offline_process(h, 10), ERR_BAD_ARG);
    }

    /// Precisa do `engine::api::apply` de verdade (outro agente da fase 5 implementa; neste
    /// worktree ele é um esqueleto que não conhece nome nenhum). Depois da integração:
    /// `cargo test -p jopendaw-engine-android -- --ignored`.
    #[test]
    #[ignore = "depende do engine::api::apply completo"]
    fn offline_render_with_the_real_apply() {
        let h = jd_offline_new(48_000.0);
        let s = [0.5f32; 24_000];
        let json = r#"[["tempo", 120, 4], ["tracks", 1], ["track_kind", 0, 0], ["track", 0, 1, 0, 0, 0], ["master", 1, 0],
            ["clip_add", 0, 1, 0, 0, 0.5, 1, 0, 0], ["capture_clear"], ["capture_add", 0], ["capture_add", -1], ["seek", 0], ["play"]]"#;
        unsafe {
            assert_eq!(jd_offline_sample(h, 1, s.as_ptr(), s.as_ptr(), s.len(), 48_000.0), 0);
            assert_eq!(jd_offline_calls(h, json.as_ptr(), json.len()), 0, "o apply não conhece alguma chamada");
        }
        let (mut l, mut r) = (vec![0.0f32; 1024], vec![0.0f32; 1024]);
        let mut track = Vec::new();
        for _ in 0..40 {
            let n = jd_offline_process(h, 1024) as usize;
            unsafe { jd_offline_captured(h, 0, l.as_mut_ptr(), r.as_mut_ptr(), n) };
            track.extend_from_slice(&l[..n]);
        }
        assert!(track[100] > 0.2 && track[30_000].abs() < 1e-4);
        jd_offline_free(h);
    }

    /// O motor que toca com o despachante de verdade: notas ao vivo registradas na captura.
    #[test]
    #[ignore = "depende do engine::api::apply completo"]
    fn live_notes_with_the_real_apply() {
        let _one = SERIAL.lock().unwrap_or_else(|e| e.into_inner());
        assert_eq!(jd_start(), 48_000.0);
        assert_eq!(calls(r#"[["tracks", 1], ["track_kind", 0, 1], ["seek", 0], ["play"]]"#), 0);
        assert_eq!(jd_capture(1), 0);
        assert_eq!(calls(r#"[["live_on", 0, 62, 0.9]]"#), 0);
        assert_eq!(calls(r#"[["live_off", 0, 62]]"#), 0);
        assert_eq!(jd_capture(0), 0);
        let mut notes = [0.0f32; 10];
        assert_eq!(unsafe { jd_rec_notes(notes.as_mut_ptr(), notes.len()) }, 5);
        assert_eq!(notes[1], 62.0);
        assert_eq!(calls(r#"[["stop"]]"#), 0);
    }
    #[test]
    fn stretch_and_detect_through_ffi() {
        let rate = 48_000.0;
        let mut x = vec![0.0f32; 48_000 * 6];
        for beat in 0..12 {
            for i in 0..200 {
                x[beat * 24_000 + i] = if i % 2 == 0 { 0.9 } else { -0.9 };
            }
        }
        let (mut bpm, mut conf) = (0.0f64, 0.0f64);
        assert_eq!(unsafe { jd_detect_bpm(x.as_ptr(), std::ptr::null(), x.len(), rate, &mut bpm, &mut conf) }, 0);
        assert!((bpm - 120.0).abs() <= 1.0, "{bpm}");
        assert_eq!(unsafe { jd_detect_bpm(std::ptr::null(), std::ptr::null(), 10, rate, &mut bpm, &mut conf) }, ERR_BAD_ARG);

        let h = unsafe { jd_stretch(x.as_ptr(), x.as_ptr(), x.len(), rate, 2.0, 0.0) };
        assert_ne!(h, 0);
        let (mut frames, mut channels, mut r) = (0i64, 0i32, 0.0f64);
        assert_eq!(unsafe { jd_decoded_info(h, &mut frames, &mut channels, &mut r) }, 0);
        assert_eq!((frames, channels), (x.len() as i64 * 2, 2));
        jd_decoded_free(h);
        assert_eq!(unsafe { jd_stretch(std::ptr::null(), std::ptr::null(), 10, rate, 2.0, 0.0) }, 0);
    }
}
