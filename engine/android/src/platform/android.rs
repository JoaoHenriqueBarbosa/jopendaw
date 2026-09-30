//! A E/S de áudio no Android: streams do AAudio de baixa latência, a saída com callback (a thread
//! de áudio) e a entrada sem callback, lida sem bloquear de dentro do callback de saída (o full
//! duplex do Oboe: um relógio só, sem anel entre duas threads).
//!
//! Queda de dispositivo (fone plugado ou tirado, USB, Bluetooth): o AAudio desconecta o stream e
//! avisa pelo callback de erro, que não pode fechar nada ali; ele só marca e acorda o supervisor,
//! que reabre a saída na mesma taxa (o motor não muda de taxa; o AAudio converte se o aparelho
//! novo tiver outra) e, se a entrada era a padrão, reabre a entrada também. Sem conseguir, tenta de
//! novo com intervalo crescente enquanto o Dart quiser a saída aberta.

use std::ffi::c_void;
use std::panic::{AssertUnwindSafe, catch_unwind};
use std::sync::atomic::{AtomicBool, AtomicI32, AtomicU64, AtomicUsize, Ordering};
use std::sync::{Arc, Mutex, OnceLock, TryLockError};
use std::thread::Thread;
use std::time::{Duration, Instant};

use jopendaw_engine::MAX_BLOCK;

use super::aaudio::{self, Config, Stream};
use super::devices;
use crate::core::{AudioCore, InputRead, InputSource};
use crate::state::Meters;
use crate::{ERR_DENIED, ERR_DEVICE, ERR_NOT_FOUND, ERR_NOT_STARTED, ERR_UNSUPPORTED, alloc};

/// O que o callback de saída, o de erro e o host dividem. Vive num `Arc` que o `Output` segura
/// até depois de o stream fechar (o AAudio guarda o ponteiro cru dele).
struct OutShared {
    core: OnceLock<Arc<Mutex<AudioCore>>>,
    meters: OnceLock<Arc<Meters>>,
    channels: AtomicUsize,
    heartbeat: AtomicU64,
    failed: AtomicBool,
    error: AtomicI32,
    xruns: AtomicI32,
}

struct Output {
    // o stream fecha (drop) antes do `shared` que o callback usa: ordem dos campos
    stream: Stream,
    shared: Arc<OutShared>,
    started: bool,
}

pub struct Io {
    output: Option<Output>,
    /// O Dart quer a saída aberta (entre `start_output` e `close_output`): o supervisor reabre.
    wanted: bool,
    attempts: u32,
    next_try: Instant,
    input_open: bool,
}

unsafe extern "C" fn on_output(stream: *mut c_void, user: *mut c_void, data: *mut c_void, frames: i32) -> i32 {
    // SAFETY: `user` é o `OutShared` do `Output`, vivo até o stream fechar
    let sh = unsafe { &*(user as *const OutShared) };
    let _mark = alloc::AudioThread::enter();
    sh.heartbeat.fetch_add(1, Ordering::Relaxed);
    let ch = sh.channels.load(Ordering::Relaxed).max(1);
    // SAFETY: o AAudio entrega `frames` quadros de `ch` floats
    let out = unsafe { std::slice::from_raw_parts_mut(data as *mut f32, frames.max(0) as usize * ch) };
    let ok = catch_unwind(AssertUnwindSafe(|| match sh.core.get().map(|c| c.try_lock()) {
        Some(Ok(mut core)) => {
            core.render(out, ch);
            true
        }
        // o host está aplicando comandos com a saída dada como parada: um bloco de silêncio
        Some(Err(TryLockError::WouldBlock)) | None => {
            out.fill(0.0);
            true
        }
        Some(Err(TryLockError::Poisoned(_))) => false,
    }));
    if !matches!(ok, Ok(true)) {
        // pânico no motor (agora ou antes): o estado dele é desconhecido, então só silêncio
        out.fill(0.0);
        if let Some(m) = sh.meters.get() {
            m.set_broken();
        }
    }
    // underrun: um burst a mais de buffer (troca latência por estabilidade, como o Oboe faz)
    if let Some(a) = aaudio::api() {
        // SAFETY: o stream do callback, aberto
        let x = unsafe { aaudio::xruns(a, stream) };
        if x > sh.xruns.swap(x, Ordering::Relaxed) {
            unsafe { aaudio::grow_buffer(a, stream) };
        }
    }
    aaudio::CALLBACK_RESULT_CONTINUE
}

unsafe extern "C" fn on_output_error(_stream: *mut c_void, user: *mut c_void, error: i32) {
    // SAFETY: como no `on_output`
    let sh = unsafe { &*(user as *const OutShared) };
    sh.error.store(error, Ordering::Relaxed);
    sh.failed.store(true, Ordering::Release);
    wake_supervisor();
}

struct InShared {
    failed: AtomicBool,
}

unsafe extern "C" fn on_input_error(_stream: *mut c_void, user: *mut c_void, _error: i32) {
    // SAFETY: `user` é o `InShared` da entrada, vivo até o stream dela fechar
    let sh = unsafe { &*(user as *const InShared) };
    sh.failed.store(true, Ordering::Release);
    wake_supervisor();
}

/// A entrada, lida pelo callback de saída.
struct Input {
    stream: Stream,
    shared: Arc<InShared>,
    channels: usize,
    buf: Box<[f32]>,
    /// Quadros além do pedido que podem ficar esperando antes de o excesso ser descartado: segura
    /// a latência da entrada quando os relógios escorregam ou o começo acumula.
    cushion: usize,
}

impl InputSource for Input {
    fn read(&mut self, l: &mut [f32], r: &mut [f32]) -> InputRead {
        if self.shared.failed.load(Ordering::Acquire) {
            return InputRead::Lost;
        }
        let Some(a) = aaudio::api() else { return InputRead::Lost };
        let s = self.stream.raw();
        let n = l.len().min(r.len()).min(MAX_BLOCK);
        // SAFETY: stream aberto; `buf` tem MAX_BLOCK quadros de `channels` floats
        unsafe {
            let avail = aaudio::available(a, s);
            let keep = (n + self.cushion) as i64;
            if avail > keep + self.cushion as i64 {
                let mut excess = (avail - keep) as usize;
                while excess > 0 {
                    let k = excess.min(MAX_BLOCK);
                    let got = aaudio::read(a, s, self.buf.as_mut_ptr(), k as i32);
                    if got <= 0 {
                        break;
                    }
                    excess -= (got as usize).min(excess);
                }
            }
            let got = aaudio::read(a, s, self.buf.as_mut_ptr(), n as i32);
            if got < 0 {
                return if got == aaudio::ERROR_DISCONNECTED { InputRead::Lost } else { InputRead::Frames(0) };
            }
            let got = (got as usize).min(n);
            let ch = self.channels;
            if ch == 1 {
                l[..got].copy_from_slice(&self.buf[..got]);
                r[..got].copy_from_slice(&self.buf[..got]);
            } else {
                for i in 0..got {
                    l[i] = self.buf[i * ch];
                    r[i] = self.buf[i * ch + 1];
                }
            }
            InputRead::Frames(got)
        }
    }
}

impl Io {
    /// Há entrada de áudio nesta plataforma.
    pub const HAS_INPUT: bool = true;

    pub fn new() -> Self {
        Self { output: None, wanted: false, attempts: 0, next_try: Instant::now(), input_open: false }
    }

    /// Abre a saída (sem começar): `rate` `None` = a taxa nativa do aparelho. Devolve a taxa.
    pub fn open_output(&mut self, rate: Option<f64>) -> Result<f64, i32> {
        aaudio::api().ok_or(ERR_UNSUPPORTED)?;
        self.output = None;
        let shared = Arc::new(OutShared {
            core: OnceLock::new(),
            meters: OnceLock::new(),
            channels: AtomicUsize::new(2),
            heartbeat: AtomicU64::new(0),
            failed: AtomicBool::new(false),
            error: AtomicI32::new(0),
            xruns: AtomicI32::new(0),
        });
        let user = Arc::as_ptr(&shared) as *mut c_void;
        let want = rate.map_or(aaudio::UNSPECIFIED, |r| r.round() as i32);
        // exclusivo (MMAP) é o caminho de menor latência; nem todo aparelho dá, e o exclusivo só
        // aceita a taxa nativa: o compartilhado converte
        let tries = [(aaudio::SHARING_MODE_EXCLUSIVE, 2), (aaudio::SHARING_MODE_SHARED, 2), (aaudio::SHARING_MODE_SHARED, aaudio::UNSPECIFIED)];
        let mut last = 0;
        let mut opened = None;
        for (sharing, channels) in tries {
            let cfg = Config {
                direction: aaudio::DIRECTION_OUTPUT,
                device: aaudio::UNSPECIFIED,
                rate: want,
                channels,
                sharing,
                input_preset: None,
                data: Some((on_output, user)),
                error: Some((on_output_error, user)),
            };
            match Stream::open(&cfg) {
                Ok(s) if s.format() == aaudio::FORMAT_PCM_FLOAT && s.channels() > 0 && s.rate() > 0 && (want == 0 || s.rate() == want) => {
                    opened = Some(s);
                    break;
                }
                Ok(s) => log(&format!("saída recusada: {} Hz, {} canais, formato {}", s.rate(), s.channels(), s.format())),
                Err(e) => last = e,
            }
        }
        let Some(stream) = opened else {
            log(&format!("a saída de áudio não abriu: {}", aaudio::text(last)));
            return Err(ERR_DEVICE);
        };
        shared.channels.store(stream.channels() as usize, Ordering::Relaxed);
        // dois bursts: o mínimo sem underrun num aparelho saudável; o callback cresce se precisar
        let burst = stream.burst();
        if burst > 0 {
            stream.set_buffer_size(2 * burst);
        }
        log(&format!(
            "saída aberta: {} Hz, {} canais, burst {}, buffer {}/{}, {}, desempenho {}",
            stream.rate(),
            stream.channels(),
            burst,
            stream.buffer_size(),
            stream.capacity(),
            if stream.sharing() == aaudio::SHARING_MODE_EXCLUSIVE { "exclusiva" } else { "compartilhada" },
            stream.performance(),
        ));
        let rate = stream.rate() as f64;
        self.output = Some(Output { stream, shared, started: false });
        Ok(rate)
    }

    /// Liga a saída aberta ao núcleo e começa.
    pub fn start_output(&mut self, core: &Arc<Mutex<AudioCore>>) -> Result<(), i32> {
        let out = self.output.as_mut().ok_or(ERR_NOT_STARTED)?;
        let meters = core.lock().unwrap_or_else(|e| e.into_inner()).meters().clone();
        let _ = out.shared.core.set(core.clone());
        let _ = out.shared.meters.set(meters);
        let r = out.stream.start();
        if r != aaudio::OK {
            log(&format!("a saída de áudio não começou: {}", aaudio::text(r)));
            self.output = None;
            return Err(ERR_DEVICE);
        }
        out.started = true;
        self.wanted = true;
        self.attempts = 0;
        Ok(())
    }

    /// Fecha a saída (pedido do Dart: o supervisor não reabre).
    pub fn close_output(&mut self) {
        self.wanted = false;
        self.output = None;
    }

    /// A saída está rodando (callbacks chegando ou por chegar).
    pub fn output_open(&self) -> bool {
        self.output.as_ref().is_some_and(|o| o.started && !o.shared.failed.load(Ordering::Acquire))
    }

    /// A saída caiu (ou não reabriu) e o Dart ainda a quer: hora de tentar de novo.
    pub fn needs_restart(&self) -> bool {
        self.wanted && !self.output_open() && Instant::now() >= self.next_try
    }

    /// Reabre a saída na taxa do motor; sem conseguir, agenda outra tentativa (250 ms dobrando
    /// até 5 s).
    pub fn restart(&mut self, rate: f64, core: &Arc<Mutex<AudioCore>>) {
        if let Some(o) = &self.output {
            log(&format!("a saída caiu ({}): reabrindo", aaudio::text(o.shared.error.load(Ordering::Relaxed))));
        }
        self.output = None;
        let ok = self.open_output(Some(rate)).and_then(|_| self.start_output(core)).is_ok();
        if !ok {
            self.wanted = true;
            self.attempts += 1;
            let wait = Duration::from_millis(250u64 << self.attempts.min(5)).min(Duration::from_secs(5));
            self.next_try = Instant::now() + wait;
        }
    }

    pub fn heartbeat(&self) -> u64 {
        self.output.as_ref().map_or(0, |o| o.shared.heartbeat.load(Ordering::Relaxed))
    }

    /// Latência de saída (s): pelo relógio do AAudio, ou o buffer quando ele ainda não informa.
    pub fn output_latency(&self) -> f64 {
        let Some(o) = &self.output else { return 0.0 };
        o.stream.measured_latency(false).unwrap_or_else(|| {
            let rate = o.stream.rate().max(1) as f64;
            o.stream.buffer_size().max(0) as f64 / rate
        })
    }

    /// Abre a entrada `device` (0 = padrão) na taxa do motor, sem processamento de voz, e começa.
    /// Devolve a fonte para o núcleo e a latência de entrada (s).
    pub fn open_input(&mut self, device: i32, rate: f64) -> Result<(Box<dyn InputSource>, f64), i32> {
        aaudio::api().ok_or(ERR_UNSUPPORTED)?;
        let Some(out) = self.output.as_ref().filter(|o| o.started) else { return Err(ERR_NOT_STARTED) };
        let t = Instant::now();
        let permission = devices::record_permission();
        if t.elapsed() > Duration::from_millis(100) {
            log(&format!("a consulta da permissão de gravar levou {} ms", t.elapsed().as_millis()));
        }
        if permission == Some(false) {
            return Err(ERR_DENIED);
        }
        if device != 0 && devices::input_exists(device) == Some(false) {
            return Err(ERR_NOT_FOUND);
        }
        let shared = Arc::new(InShared { failed: AtomicBool::new(false) });
        let user = Arc::as_ptr(&shared) as *mut c_void;
        let want = rate.round() as i32;
        // VOICE_PERFORMANCE (API 29) é o caminho de baixa latência sem processamento, feito para
        // tocar ao vivo; UNPROCESSED (API 28) é o cru; VOICE_RECOGNITION, o padrão, quase cru. Um
        // aparelho que não conhece o preset recusa o stream, e a próxima tentativa vale.
        let tries = [
            (Some(aaudio::INPUT_PRESET_VOICE_PERFORMANCE), aaudio::SHARING_MODE_EXCLUSIVE, 2),
            (Some(aaudio::INPUT_PRESET_VOICE_PERFORMANCE), aaudio::SHARING_MODE_SHARED, 2),
            (Some(aaudio::INPUT_PRESET_UNPROCESSED), aaudio::SHARING_MODE_SHARED, 2),
            (Some(aaudio::INPUT_PRESET_VOICE_RECOGNITION), aaudio::SHARING_MODE_SHARED, 2),
            (None, aaudio::SHARING_MODE_SHARED, 1),
        ];
        let mut last = 0;
        let mut opened = None;
        for (preset, sharing, channels) in tries {
            let cfg = Config {
                direction: aaudio::DIRECTION_INPUT,
                device,
                rate: want,
                channels,
                sharing,
                input_preset: preset,
                data: None,
                error: Some((on_input_error, user)),
            };
            let t = Instant::now();
            match Stream::open(&cfg) {
                Ok(s) if s.format() == aaudio::FORMAT_PCM_FLOAT && s.channels() > 0 && s.rate() == want => {
                    opened = Some(s);
                    break;
                }
                Ok(s) => log(&format!("entrada recusada: {} Hz, {} canais, formato {}", s.rate(), s.channels(), s.format())),
                Err(e) => {
                    log(&format!(
                        "entrada (preset {preset:?}, modo {sharing}, {channels} canais) não abriu em {} ms: {}",
                        t.elapsed().as_millis(),
                        aaudio::text(e)
                    ));
                    last = e;
                }
            }
        }
        let Some(stream) = opened else {
            log(&format!("a entrada de áudio não abriu: {}", aaudio::text(last)));
            return Err(ERR_DEVICE);
        };
        let r = stream.start();
        if r != aaudio::OK {
            log(&format!("a entrada de áudio não começou: {}", aaudio::text(r)));
            return Err(ERR_DEVICE);
        }
        let burst = stream.burst().max(64) as usize;
        let channels = stream.channels() as usize;
        // a latência pelo relógio do AAudio aparece quando o hardware já entregou quadros
        let deadline = Instant::now() + Duration::from_millis(300);
        let mut device_latency = None;
        while device_latency.is_none() && Instant::now() < deadline {
            std::thread::sleep(Duration::from_millis(10));
            device_latency = stream.measured_latency(true);
        }
        let device_latency = device_latency.unwrap_or(2.0 * burst as f64 / rate);
        // mais o que espera na entrada até o callback de saída ler (um burst da saída)
        let latency = device_latency + out.stream.burst().max(0) as f64 / rate;
        log(&format!(
            "entrada aberta: dispositivo {device}, {} Hz, {channels} canais, burst {burst}, {}, latência {:.1} ms",
            stream.rate(),
            if stream.sharing() == aaudio::SHARING_MODE_EXCLUSIVE { "exclusiva" } else { "compartilhada" },
            latency * 1000.0
        ));
        let input = Input { stream, shared, channels, buf: vec![0.0f32; MAX_BLOCK * channels].into_boxed_slice(), cushion: burst };
        self.input_open = true;
        Ok((Box::new(input), latency))
    }

    pub fn has_input(&self) -> bool {
        self.input_open
    }

    pub fn input_closed(&mut self) {
        self.input_open = false;
    }
}

/// Entradas de áudio conectadas em JSON (`[["id", "nome"], ...]`).
pub fn input_devices() -> String {
    devices::input_devices_json()
}

/// Escreve no logcat (tag `jopendaw`). Nunca da thread de áudio.
pub fn log(msg: &str) {
    const INFO: i32 = 4;
    #[link(name = "log")]
    unsafe extern "C" {
        fn __android_log_write(prio: i32, tag: *const std::ffi::c_char, text: *const std::ffi::c_char) -> i32;
    }
    let text = std::ffi::CString::new(msg.replace('\0', " ")).unwrap_or_default();
    // SAFETY: strings C válidas
    unsafe { __android_log_write(INFO, c"jopendaw".as_ptr(), text.as_ptr()) };
}

static SUPERVISOR: OnceLock<Thread> = OnceLock::new();

fn wake_supervisor() {
    if let Some(t) = SUPERVISOR.get() {
        t.unpark();
    }
}

/// O supervisor: reabre dispositivos que caíram, libera o que a thread de áudio soltou (mesmo com
/// o Dart parado, em segundo plano) e escreve os diagnósticos no log.
pub fn spawn_supervisor() {
    SUPERVISOR.get_or_init(|| {
        let spawned = std::thread::Builder::new().name("jopendaw-sup".into()).spawn(|| {
            let mut last = String::new();
            let mut logged = Instant::now();
            loop {
                std::thread::park_timeout(Duration::from_millis(250));
                let _ = catch_unwind(AssertUnwindSafe(|| {
                    crate::with_host((), |h| {
                        h.maintain();
                        if logged.elapsed() > Duration::from_secs(10) {
                            logged = Instant::now();
                            let d = h.diagnostics();
                            if d != last {
                                log(&d);
                                last = d;
                            }
                        }
                    })
                }));
            }
        });
        match spawned {
            Ok(j) => j.thread().clone(),
            Err(_) => std::thread::current(),
        }
    });
}
