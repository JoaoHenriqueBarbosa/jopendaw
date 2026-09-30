//! O AAudio (a API de áudio de baixa latência do Android 8+, a mesma que o Oboe usa por baixo)
//! carregado em tempo de execução com `dlopen`.
//!
//! Ligar direto na `libaaudio.so` faria a biblioteca inteira falhar ao abrir no Android 7 (o app
//! aceita a partir da API 24, o AAudio é da 26), levando junto a decodificação e o render, que não
//! precisam dele. Assim, sem AAudio só o áudio ao vivo diz que não há suporte. As funções da API
//! 28 (uso, tipo de conteúdo, preset de entrada) são opcionais.

use std::ffi::{CStr, c_char, c_void};
use std::ptr::NonNull;
use std::sync::OnceLock;

pub const OK: i32 = 0;
pub const DIRECTION_OUTPUT: i32 = 0;
pub const DIRECTION_INPUT: i32 = 1;
pub const FORMAT_PCM_FLOAT: i32 = 2;
pub const SHARING_MODE_EXCLUSIVE: i32 = 0;
pub const SHARING_MODE_SHARED: i32 = 1;
pub const PERFORMANCE_MODE_LOW_LATENCY: i32 = 12;
pub const USAGE_MEDIA: i32 = 1;
pub const CONTENT_TYPE_MUSIC: i32 = 2;
pub const INPUT_PRESET_VOICE_RECOGNITION: i32 = 6;
pub const INPUT_PRESET_UNPROCESSED: i32 = 9;
pub const INPUT_PRESET_VOICE_PERFORMANCE: i32 = 10;
pub const CALLBACK_RESULT_CONTINUE: i32 = 0;
pub const ERROR_DISCONNECTED: i32 = -899;
pub const UNSPECIFIED: i32 = 0;
const CLOCK_MONOTONIC: libc::clockid_t = libc::CLOCK_MONOTONIC;

pub type DataCallback = unsafe extern "C" fn(stream: *mut c_void, user: *mut c_void, data: *mut c_void, frames: i32) -> i32;
pub type ErrorCallback = unsafe extern "C" fn(stream: *mut c_void, user: *mut c_void, error: i32);

type P = *mut c_void;

/// As funções usadas, resolvidas uma vez.
pub struct Api {
    create_builder: unsafe extern "C" fn(*mut P) -> i32,
    builder_delete: unsafe extern "C" fn(P) -> i32,
    set_device_id: unsafe extern "C" fn(P, i32),
    set_sample_rate: unsafe extern "C" fn(P, i32),
    set_channel_count: unsafe extern "C" fn(P, i32),
    set_format: unsafe extern "C" fn(P, i32),
    set_sharing_mode: unsafe extern "C" fn(P, i32),
    set_direction: unsafe extern "C" fn(P, i32),
    set_performance_mode: unsafe extern "C" fn(P, i32),
    set_usage: Option<unsafe extern "C" fn(P, i32)>,
    set_content_type: Option<unsafe extern "C" fn(P, i32)>,
    set_input_preset: Option<unsafe extern "C" fn(P, i32)>,
    set_data_callback: unsafe extern "C" fn(P, Option<DataCallback>, P),
    set_error_callback: unsafe extern "C" fn(P, Option<ErrorCallback>, P),
    open_stream: unsafe extern "C" fn(P, *mut P) -> i32,
    close: unsafe extern "C" fn(P) -> i32,
    request_start: unsafe extern "C" fn(P) -> i32,
    request_stop: unsafe extern "C" fn(P) -> i32,
    read: unsafe extern "C" fn(P, P, i32, i64) -> i32,
    set_buffer_size: unsafe extern "C" fn(P, i32) -> i32,
    get_buffer_size: unsafe extern "C" fn(P) -> i32,
    get_buffer_capacity: unsafe extern "C" fn(P) -> i32,
    get_frames_per_burst: unsafe extern "C" fn(P) -> i32,
    get_xrun_count: unsafe extern "C" fn(P) -> i32,
    get_sample_rate: unsafe extern "C" fn(P) -> i32,
    get_channel_count: unsafe extern "C" fn(P) -> i32,
    get_format: unsafe extern "C" fn(P) -> i32,
    get_sharing_mode: unsafe extern "C" fn(P) -> i32,
    get_performance_mode: unsafe extern "C" fn(P) -> i32,
    get_frames_written: unsafe extern "C" fn(P) -> i64,
    get_frames_read: unsafe extern "C" fn(P) -> i64,
    get_timestamp: unsafe extern "C" fn(P, libc::clockid_t, *mut i64, *mut i64) -> i32,
    result_text: unsafe extern "C" fn(i32) -> *const c_char,
}

unsafe fn sym<T: Copy>(lib: *mut c_void, name: &CStr) -> Option<T> {
    // SAFETY: `lib` é um handle do dlopen; o tipo T é o da função na documentação do AAudio
    let p = unsafe { libc::dlsym(lib, name.as_ptr()) };
    if p.is_null() {
        None
    } else {
        debug_assert_eq!(std::mem::size_of::<T>(), std::mem::size_of::<*mut c_void>());
        Some(unsafe { std::mem::transmute_copy::<*mut c_void, T>(&p) })
    }
}

fn load() -> Option<Api> {
    // SAFETY: dlopen com nome fixo; o handle nunca é fechado (as funções valem até o fim)
    let lib = unsafe { libc::dlopen(c"libaaudio.so".as_ptr(), libc::RTLD_NOW) };
    if lib.is_null() {
        return None;
    }
    unsafe {
        Some(Api {
            create_builder: sym(lib, c"AAudio_createStreamBuilder")?,
            builder_delete: sym(lib, c"AAudioStreamBuilder_delete")?,
            set_device_id: sym(lib, c"AAudioStreamBuilder_setDeviceId")?,
            set_sample_rate: sym(lib, c"AAudioStreamBuilder_setSampleRate")?,
            set_channel_count: sym(lib, c"AAudioStreamBuilder_setChannelCount")?,
            set_format: sym(lib, c"AAudioStreamBuilder_setFormat")?,
            set_sharing_mode: sym(lib, c"AAudioStreamBuilder_setSharingMode")?,
            set_direction: sym(lib, c"AAudioStreamBuilder_setDirection")?,
            set_performance_mode: sym(lib, c"AAudioStreamBuilder_setPerformanceMode")?,
            set_usage: sym(lib, c"AAudioStreamBuilder_setUsage"),
            set_content_type: sym(lib, c"AAudioStreamBuilder_setContentType"),
            set_input_preset: sym(lib, c"AAudioStreamBuilder_setInputPreset"),
            set_data_callback: sym(lib, c"AAudioStreamBuilder_setDataCallback")?,
            set_error_callback: sym(lib, c"AAudioStreamBuilder_setErrorCallback")?,
            open_stream: sym(lib, c"AAudioStreamBuilder_openStream")?,
            close: sym(lib, c"AAudioStream_close")?,
            request_start: sym(lib, c"AAudioStream_requestStart")?,
            request_stop: sym(lib, c"AAudioStream_requestStop")?,
            read: sym(lib, c"AAudioStream_read")?,
            set_buffer_size: sym(lib, c"AAudioStream_setBufferSizeInFrames")?,
            get_buffer_size: sym(lib, c"AAudioStream_getBufferSizeInFrames")?,
            get_buffer_capacity: sym(lib, c"AAudioStream_getBufferCapacityInFrames")?,
            get_frames_per_burst: sym(lib, c"AAudioStream_getFramesPerBurst")?,
            get_xrun_count: sym(lib, c"AAudioStream_getXRunCount")?,
            get_sample_rate: sym(lib, c"AAudioStream_getSampleRate")?,
            get_channel_count: sym(lib, c"AAudioStream_getChannelCount")?,
            get_format: sym(lib, c"AAudioStream_getFormat")?,
            get_sharing_mode: sym(lib, c"AAudioStream_getSharingMode")?,
            get_performance_mode: sym(lib, c"AAudioStream_getPerformanceMode")?,
            get_frames_written: sym(lib, c"AAudioStream_getFramesWritten")?,
            get_frames_read: sym(lib, c"AAudioStream_getFramesRead")?,
            get_timestamp: sym(lib, c"AAudioStream_getTimestamp")?,
            result_text: sym(lib, c"AAudio_convertResultToText")?,
        })
    }
}

/// A API, ou `None` sem AAudio (Android 7).
pub fn api() -> Option<&'static Api> {
    static API: OnceLock<Option<Api>> = OnceLock::new();
    API.get_or_init(load).as_ref()
}

/// O texto de um código de resultado, para o log.
pub fn text(code: i32) -> String {
    match api() {
        // SAFETY: a função devolve uma string estática
        Some(a) => unsafe { CStr::from_ptr((a.result_text)(code)) }.to_string_lossy().into_owned(),
        None => code.to_string(),
    }
}

/// Configuração de um stream a abrir.
pub struct Config {
    pub direction: i32,
    pub device: i32,
    pub rate: i32,
    pub channels: i32,
    pub sharing: i32,
    pub input_preset: Option<i32>,
    pub data: Option<(DataCallback, *mut c_void)>,
    pub error: Option<(ErrorCallback, *mut c_void)>,
}

/// Um stream aberto; fecha no drop. O AAudio não trava por dentro: quem tem o `Stream` chama as
/// funções de controle de uma thread por vez (o host), e o callback só usa o ponteiro que recebe.
pub struct Stream {
    api: &'static Api,
    ptr: NonNull<c_void>,
}

// SAFETY: o ponteiro do AAudio pode mudar de thread; as chamadas de controle são serializadas pelo
// dono (o host, atrás da trava dele) e o ponteiro cru que a entrada guarda é lido só pela thread de
// áudio
unsafe impl Send for Stream {}

impl Stream {
    pub fn open(cfg: &Config) -> Result<Stream, i32> {
        let a = api().ok_or(crate::ERR_UNSUPPORTED)?;
        let mut b: P = std::ptr::null_mut();
        // SAFETY: as funções do AAudio com o builder que ele criou, apagado no fim
        unsafe {
            let r = (a.create_builder)(&mut b);
            if r != OK || b.is_null() {
                return Err(r.min(-1));
            }
            (a.set_direction)(b, cfg.direction);
            (a.set_device_id)(b, cfg.device);
            (a.set_sample_rate)(b, cfg.rate);
            (a.set_channel_count)(b, cfg.channels);
            (a.set_format)(b, FORMAT_PCM_FLOAT);
            (a.set_sharing_mode)(b, cfg.sharing);
            (a.set_performance_mode)(b, PERFORMANCE_MODE_LOW_LATENCY);
            if let Some(f) = a.set_usage
                && cfg.direction == DIRECTION_OUTPUT
            {
                f(b, USAGE_MEDIA);
            }
            if let Some(f) = a.set_content_type
                && cfg.direction == DIRECTION_OUTPUT
            {
                f(b, CONTENT_TYPE_MUSIC);
            }
            if let (Some(f), Some(p)) = (a.set_input_preset, cfg.input_preset) {
                f(b, p);
            }
            if let Some((cb, user)) = cfg.data {
                (a.set_data_callback)(b, Some(cb), user);
            }
            if let Some((cb, user)) = cfg.error {
                (a.set_error_callback)(b, Some(cb), user);
            }
            let mut s: P = std::ptr::null_mut();
            let r = (a.open_stream)(b, &mut s);
            (a.builder_delete)(b);
            match NonNull::new(s) {
                Some(ptr) if r == OK => Ok(Stream { api: a, ptr }),
                _ => Err(r.min(-1)),
            }
        }
    }

    pub fn raw(&self) -> *mut c_void {
        self.ptr.as_ptr()
    }

    pub fn start(&self) -> i32 {
        unsafe { (self.api.request_start)(self.raw()) }
    }

    pub fn rate(&self) -> i32 {
        unsafe { (self.api.get_sample_rate)(self.raw()) }
    }

    pub fn channels(&self) -> i32 {
        unsafe { (self.api.get_channel_count)(self.raw()) }
    }

    pub fn format(&self) -> i32 {
        unsafe { (self.api.get_format)(self.raw()) }
    }

    pub fn sharing(&self) -> i32 {
        unsafe { (self.api.get_sharing_mode)(self.raw()) }
    }

    pub fn performance(&self) -> i32 {
        unsafe { (self.api.get_performance_mode)(self.raw()) }
    }

    pub fn burst(&self) -> i32 {
        unsafe { (self.api.get_frames_per_burst)(self.raw()) }
    }

    pub fn buffer_size(&self) -> i32 {
        unsafe { (self.api.get_buffer_size)(self.raw()) }
    }

    pub fn set_buffer_size(&self, frames: i32) -> i32 {
        unsafe { (self.api.set_buffer_size)(self.raw(), frames) }
    }

    pub fn capacity(&self) -> i32 {
        unsafe { (self.api.get_buffer_capacity)(self.raw()) }
    }

    /// Latência medida pelo relógio do AAudio (s), ou `None` antes de o stream ter posição.
    pub fn measured_latency(&self, input: bool) -> Option<f64> {
        latency(self.api, self.raw(), input)
    }
}

impl Drop for Stream {
    fn drop(&mut self) {
        // SAFETY: fechar espera o callback em andamento terminar; depois disso ninguém mais usa
        unsafe {
            (self.api.request_stop)(self.raw());
            (self.api.close)(self.raw());
        }
    }
}

// a conversão é inútil só no arm64 e no x86_64: no armeabi-v7a time_t e long têm 32 bits
#[allow(clippy::useless_conversion)]
fn now_nanos() -> i64 {
    let mut ts = libc::timespec { tv_sec: 0, tv_nsec: 0 };
    // SAFETY: timespec válido
    unsafe { libc::clock_gettime(CLOCK_MONOTONIC, &mut ts) };
    i64::from(ts.tv_sec) * 1_000_000_000 + i64::from(ts.tv_nsec)
}

/// Latência pelo par (quadro, instante) que o AAudio dá do hardware, como o
/// `calculateLatencyMillis` do Oboe. Saída: quanto falta para o último quadro escrito tocar.
/// Entrada: há quanto tempo o quadro mais novo disponível passou pelo conversor.
fn latency(a: &Api, s: *mut c_void, input: bool) -> Option<f64> {
    let (mut frame, mut time) = (0i64, 0i64);
    // SAFETY: stream aberto; as saídas são locais
    let r = unsafe { (a.get_timestamp)(s, CLOCK_MONOTONIC, &mut frame, &mut time) };
    let rate = unsafe { (a.get_sample_rate)(s) } as f64;
    if r != OK || rate <= 0.0 {
        return None;
    }
    let now = now_nanos() as f64 / 1e9;
    let time = time as f64 / 1e9;
    let lat = if input {
        let newest = unsafe { (a.get_frames_written)(s) };
        now - (time + (newest - frame) as f64 / rate)
    } else {
        let written = unsafe { (a.get_frames_written)(s) };
        time + (written - frame) as f64 / rate - now
    };
    (0.0..2.0).contains(&lat).then_some(lat)
}

// ------------------------------------------------------------------ para o callback (sem Stream)

/// Leitura sem bloquear de um stream de entrada sem callback. Devolve quadros lidos ou o erro.
///
/// # Safety
/// `s` é um stream de entrada aberto e `buf` tem `frames × canais` floats.
pub unsafe fn read(a: &Api, s: *mut c_void, buf: *mut f32, frames: i32) -> i32 {
    unsafe { (a.read)(s, buf as *mut c_void, frames, 0) }
}

/// Quadros disponíveis para ler numa entrada (escritos pelo hardware e ainda não lidos).
///
/// # Safety
/// `s` é um stream aberto.
pub unsafe fn available(a: &Api, s: *mut c_void) -> i64 {
    unsafe { (a.get_frames_written)(s) - (a.get_frames_read)(s) }
}

/// # Safety
/// `s` é um stream aberto.
pub unsafe fn xruns(a: &Api, s: *mut c_void) -> i32 {
    unsafe { (a.get_xrun_count)(s) }
}

/// # Safety
/// `s` é um stream aberto.
pub unsafe fn grow_buffer(a: &Api, s: *mut c_void) {
    unsafe {
        let (size, burst, cap) = ((a.get_buffer_size)(s), (a.get_frames_per_burst)(s), (a.get_buffer_capacity)(s));
        if burst > 0 && size + burst <= cap {
            (a.set_buffer_size)(s, size + burst);
        }
    }
}
