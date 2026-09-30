//! As chamadas do documento por nome, o mesmo protocolo que o worklet executa pelas funções do
//! wasm (`engine/wasm/src/lib.rs`), para hospedeiros que recebem as chamadas como lista de dados:
//! o Android (FFI) e o render fora de tempo real nativo. Cada chamada é `[nome, ...args]` com os
//! números como f64 (booleanos como 0/1, índices e ids como inteiros exatos em f64).
//!
//! Só entram aqui as chamadas sem ponteiro: carregar sample, ler picos, espectro, notas gravadas e
//! capturas têm funções próprias em cada hospedeiro.
//!
//! # Semântica
//!
//! A dos exports do wasm chamados pelo worklet, que é o que a web faz hoje. Cada número vira o tipo
//! do parâmetro do export como o JavaScript converte ao chamar o wasm: inteiro truncado e com volta
//! módulo 2³² (−1 num índice `usize` é uma faixa que não existe, e nada acontece, como na web),
//! booleano é "diferente de zero" depois dessa conversão (0,5 é desligado) e f32 é o mais próximo.
//! Faixa −1 é o master onde o export recebe `i32`. Argumentos a mais são ignorados, como no
//! JavaScript. As diferenças são deliberadas e só onde a web recebe lixo em silêncio: argumento
//! faltando ou não finito (lá chegaria NaN, ou 0 num inteiro) e número de faixas acima de
//! [`MAX_TRACKS`] voltam erro sem tocar no motor.
//!
//! # Tempo real
//!
//! [`Call::parse`] valida e converte (e só o erro aloca, para a mensagem); [`Call::apply`] só
//! aplica: não falha e não aloca nada além do que o próprio método do motor já faz (criar faixa,
//! instrumento ou efeito). O hospedeiro com thread de áudio valida na thread dele e manda o
//! [`Call`], uma cópia simples sem heap, pela fila; [`apply`] faz os dois passos de uma vez, para
//! quem roda tudo na mesma thread (o render fora de tempo real).

use std::fmt;

use crate::sampler::ZoneDef;
use crate::{Clip, Engine};
use Ty::{F32, F64, I32, U32, Usize};

/// Nome de chamada que o motor não conhece, argumento faltando ou número inválido. O texto é a
/// mensagem para o log, em português, já com o nome da chamada.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct UnknownCall(pub String);

impl fmt::Display for UnknownCall {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}

impl std::error::Error for UnknownCall {}

/// Faixas que `tracks` aceita. Na web o teto é a memória do wasm (4 GiB, e o worklet morre com
/// ela); num hospedeiro nativo um número absurdo (um −1 que deu a volta vira 4294967295) tentaria
/// reservar gigabytes na thread de áudio e derrubaria o app inteiro. Cada faixa reserva uns 40 KB
/// (notas, buffers, slots): 1024 dão uns 40 MB, ainda suportável num celular, e são quatro vezes
/// o que os medidores da web acompanham (256).
pub const MAX_TRACKS: usize = 1024;

/// Aplica uma chamada. `Ok(Some(v))` para as que devolvem valor (`auto_lane`, `capture_add`,
/// `fx_meter`, `beat`, `playing`, `loudness`, `latency_frames`), `Ok(None)` para as outras. Com erro, o motor fica intocado.
pub fn apply(engine: &mut Engine, name: &str, args: &[f64]) -> Result<Option<f64>, UnknownCall> {
    Call::parse(name, args).map(|call| call.apply(engine))
}

/// Uma chamada validada, com os argumentos já nos tipos do motor: o que o export do wasm de mesmo
/// nome recebe depois da conversão do JavaScript. `Copy` e sem heap, para atravessar uma fila sem
/// trava até a thread de áudio.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Call {
    SampleDrop {
        id: u32,
    },
    Tempo {
        bpm: f64,
        beats_per_bar: u32,
    },
    TempoClear,
    TempoPoint {
        beat: f64,
        bpm: f64,
        ramp: bool,
    },
    MeterClear,
    MeterPoint {
        bar: u32,
        num: u32,
        den: u32,
    },
    Play,
    Stop,
    Seek {
        beat: f64,
    },
    LoopSet {
        on: bool,
        start: f64,
        end: f64,
    },
    Metronome {
        on: bool,
        gain: f32,
    },
    Tracks {
        n: usize,
    },
    Track {
        track: usize,
        gain: f32,
        pan: f32,
        mute: bool,
        solo: bool,
    },
    Master {
        gain: f32,
        pan: f32,
    },
    ClipsClear,
    ClipAdd {
        track: usize,
        sample: u32,
        start: f64,
        offset: f64,
        length: f64,
        gain: f32,
        fade_in: f64,
        fade_out: f64,
    },
    ClipFadeShape {
        fade_in: u32,
        fade_out: u32,
    },
    TrackKind {
        track: usize,
        kind: u32,
    },
    Param {
        track: usize,
        id: u32,
        value: f32,
    },
    InstrumentSample {
        track: usize,
        sample: u32,
    },
    NotesClear,
    NoteAdd {
        track: usize,
        start: f64,
        length: f64,
        pitch: u32,
        velocity: f32,
    },
    LiveOn {
        track: usize,
        pitch: u32,
        velocity: f32,
    },
    LiveOff {
        track: usize,
        pitch: u32,
    },
    Panic,
    FxCount {
        track: i32,
        n: u32,
    },
    FxSet {
        track: i32,
        slot: u32,
        kind: u32,
    },
    FxParam {
        track: i32,
        slot: u32,
        id: u32,
        value: f32,
    },
    FxBypass {
        track: i32,
        slot: u32,
        on: bool,
    },
    SendsCount {
        track: i32,
        n: u32,
    },
    SendSet {
        track: i32,
        index: u32,
        bus: i32,
        level: f32,
        pre: bool,
    },
    TrackOutput {
        track: i32,
        target: i32,
    },
    AutoClear,
    AutoLane {
        track: i32,
        target: u32,
        slot: u32,
        id: u32,
    },
    AutoPoint {
        lane: u32,
        beat: f64,
        value: f32,
        curve: f32,
    },
    WatchFx {
        track: i32,
        slot: i32,
    },
    WatchAnalyzer {
        track: i32,
    },
    FxMeter,
    InputMonitor {
        track: i32,
        on: bool,
    },
    RecNotesStart,
    RecNotesStop,
    CaptureClear,
    CaptureAdd {
        track: i32,
    },
    Beat,
    Playing,
    LoudnessReset,
    Loudness {
        kind: u32,
    },
    LatencyFrames,
    ZonesClear {
        track: usize,
    },
    ZoneAdd {
        track: usize,
        sample: u32,
        zone: ZoneDef,
    },
    LiveBend {
        track: usize,
        value: f32,
    },
    LiveCc {
        track: usize,
        cc: u32,
        value: f32,
    },
    CcAdd {
        track: usize,
        cc: u32,
        beat: f64,
        value: f32,
    },
    CcClear,
    ModClear,
    ModSource {
        track: i32,
        index: u32,
        kind: u32,
        rate: f32,
        sync: bool,
        depth: f32,
        phase: f32,
        bipolar: bool,
        shape: u32,
        attack_ms: f32,
        release_ms: f32,
        value: f32,
    },
    ModDest {
        track: i32,
        index: u32,
        dest: u32,
        target_kind: u32,
        slot: u32,
        id: u32,
        amount: f32,
        min: f32,
        max: f32,
        scale: u32,
    },
}

/// Tipo de um parâmetro, como na assinatura do export do wasm (booleano é `u32` lá).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Ty {
    F64,
    F32,
    U32,
    I32,
    Usize,
}

/// Assinatura de uma chamada: o nome, os parâmetros (rótulo para as mensagens e tipo) e o tipo do
/// retorno. A tabela é conferida contra os exports do wasm nos testes.
struct Signature {
    name: &'static str,
    params: &'static [(&'static str, Ty)],
    // quem devolve valor é o `Call::apply`; o tipo aqui existe para os testes conferirem com o
    // retorno do export
    #[cfg_attr(not(test), expect(dead_code, reason = "só os testes conferem o retorno com o do wasm"))]
    ret: Option<Ty>,
}

const fn sig(name: &'static str, params: &'static [(&'static str, Ty)], ret: Option<Ty>) -> Signature {
    Signature { name, params, ret }
}

/// Todas as chamadas sem ponteiro dos exports do wasm, com os mesmos tipos, na ordem do arquivo.
const CALLS: &[Signature] = &[
    sig("sample_drop", &[("id", U32)], None),
    sig("tempo", &[("bpm", F64), ("tempos por compasso", U32)], None),
    sig("tempo_clear", &[], None),
    sig("tempo_point", &[("batida", F64), ("bpm", F64), ("rampa", U32)], None),
    sig("meter_clear", &[], None),
    sig("meter_point", &[("compasso", U32), ("numerador", U32), ("denominador", U32)], None),
    sig("play", &[], None),
    sig("stop", &[], None),
    sig("seek", &[("batida", F64)], None),
    sig("loop_set", &[("ligado", U32), ("início", F64), ("fim", F64)], None),
    sig("metronome", &[("ligado", U32), ("ganho", F32)], None),
    sig("tracks", &[("quantidade", Usize)], None),
    sig("track", &[("faixa", Usize), ("ganho", F32), ("pan", F32), ("mudo", U32), ("solo", U32)], None),
    sig("master", &[("ganho", F32), ("pan", F32)], None),
    sig("clips_clear", &[], None),
    sig(
        "clip_add",
        &[("faixa", Usize), ("sample", U32), ("início", F64), ("offset", F64), ("duração", F64), ("ganho", F32), ("fade in", F64), ("fade out", F64)],
        None,
    ),
    sig("clip_fade_shape", &[("curva in", U32), ("curva out", U32)], None),
    sig("track_kind", &[("faixa", Usize), ("tipo", U32)], None),
    sig("param", &[("faixa", Usize), ("id", U32), ("valor", F32)], None),
    sig("instrument_sample", &[("faixa", Usize), ("sample", U32)], None),
    sig("notes_clear", &[], None),
    sig("note_add", &[("faixa", Usize), ("início", F64), ("duração", F64), ("altura", U32), ("velocidade", F32)], None),
    sig("live_on", &[("faixa", Usize), ("altura", U32), ("velocidade", F32)], None),
    sig("live_off", &[("faixa", Usize), ("altura", U32)], None),
    sig("panic", &[], None),
    sig("fx_count", &[("faixa", I32), ("quantidade", U32)], None),
    sig("fx_set", &[("faixa", I32), ("slot", U32), ("tipo", U32)], None),
    sig("fx_param", &[("faixa", I32), ("slot", U32), ("id", U32), ("valor", F32)], None),
    sig("fx_bypass", &[("faixa", I32), ("slot", U32), ("ligado", U32)], None),
    sig("sends_count", &[("faixa", I32), ("quantidade", U32)], None),
    sig("send_set", &[("faixa", I32), ("envio", U32), ("barramento", I32), ("nível", F32), ("pré-fader", U32)], None),
    sig("track_output", &[("faixa", I32), ("destino", I32)], None),
    sig("auto_clear", &[], None),
    sig("auto_lane", &[("faixa", I32), ("alvo", U32), ("slot", U32), ("id", U32)], Some(U32)),
    sig("auto_point", &[("lane", U32), ("batida", F64), ("valor", F32), ("curva", F32)], None),
    sig("watch_fx", &[("faixa", I32), ("slot", I32)], None),
    sig("watch_analyzer", &[("faixa", I32)], None),
    sig("fx_meter", &[], Some(F32)),
    sig("input_monitor", &[("faixa", I32), ("ligado", U32)], None),
    sig("rec_notes_start", &[], None),
    sig("rec_notes_stop", &[], None),
    sig("capture_clear", &[], None),
    sig("capture_add", &[("faixa", I32)], Some(I32)),
    sig("beat", &[], Some(F64)),
    sig("playing", &[], Some(U32)),
    sig("loudness_reset", &[], None),
    sig("loudness", &[("tipo", U32)], Some(F64)),
    sig("latency_frames", &[], Some(F64)),
    sig("zones_clear", &[("faixa", Usize)], None),
    sig(
        "zone_add",
        &[
            ("faixa", Usize),
            ("sample", U32),
            ("nota base", U32),
            ("nota mínima", U32),
            ("nota máxima", U32),
            ("velocidade mínima", U32),
            ("velocidade máxima", U32),
            ("afinação em cents", F32),
            ("ganho em dB", F32),
            ("pan", F32),
            ("modo", U32),
            ("início", F64),
            ("fim", F64),
            ("início do loop", F64),
            ("fim do loop", F64),
            ("grupo", U32),
        ],
        None,
    ),
    sig("live_bend", &[("faixa", Usize), ("valor", F32)], None),
    sig("live_cc", &[("faixa", Usize), ("controle", U32), ("valor", F32)], None),
    sig("cc_add", &[("faixa", Usize), ("controle", U32), ("batida", F64), ("valor", F32)], None),
    sig("cc_clear", &[], None),
    sig("mod_clear", &[], None),
    sig(
        "mod_source",
        &[
            ("faixa", I32),
            ("modulador", U32),
            ("tipo", U32),
            ("taxa", F32),
            ("sincronizado", U32),
            ("profundidade", F32),
            ("fase", F32),
            ("bipolar", U32),
            ("forma", U32),
            ("ataque em ms", F32),
            ("soltura em ms", F32),
            ("valor", F32),
        ],
        None,
    ),
    sig(
        "mod_dest",
        &[
            ("faixa", I32),
            ("modulador", U32),
            ("destino", U32),
            ("alvo", U32),
            ("slot", U32),
            ("id", U32),
            ("quantidade", F32),
            ("mínimo", F32),
            ("máximo", F32),
            ("escala", U32),
        ],
        None,
    ),
];

/// Os nomes das chamadas que [`apply`] aceita (a tabela inteira), para os hospedeiros conferirem que
/// cobrem todas.
pub fn call_names() -> impl Iterator<Item = &'static str> {
    CALLS.iter().map(|s| s.name)
}

/// Exports do wasm que não passam por aqui: `init` recria o motor com a taxa do hospedeiro (quem
/// hospeda cria o dele), e os outros levam memória por ponteiro, então cada hospedeiro tem uma
/// função própria para eles.
pub const HOST_ONLY: &[&str] = &[
    "alloc",
    "dealloc",
    "init",
    "process",
    "sample_load",
    "analyzer",
    "set_input",
    "rec_notes",
    "captured",
    "peaks",
    "stretch_run",
    "stretch_channel",
    "stretch_free",
    "detect_bpm",
    "detect_confidence",
];

/// Como o JavaScript converte um número para `i32`/`u32` ao chamar o wasm (ToInt32/ToUint32):
/// trunca em direção ao zero e dá a volta módulo 2³². Saturar em vez disso faria de um −1 num
/// índice `usize` a faixa 0, e a chamada mexeria onde a web não mexe.
fn wrap32(v: f64) -> u32 {
    // depois do trunc o resto é inteiro e exato: cabe no u32 sem arredondar
    v.trunc().rem_euclid(4_294_967_296.0) as u32
}

impl Signature {
    /// Aridade e números finitos (no f32 também depois de arredondado: 1e39 vira infinito).
    fn check(&self, args: &[f64]) -> Result<(), UnknownCall> {
        let want = self.params.len();
        if args.len() < want {
            let labels: Vec<&str> = self.params.iter().map(|&(label, _)| label).collect();
            let noun = if want == 1 { "argumento" } else { "argumentos" };
            let came = if args.len() == 1 { "veio" } else { "vieram" };
            return Err(UnknownCall(format!("{}: espera {want} {noun} ({}), {came} {}", self.name, labels.join(", "), args.len())));
        }
        for (k, (&(label, ty), &v)) in self.params.iter().zip(args).enumerate() {
            if !v.is_finite() {
                return Err(UnknownCall(format!("{}: o argumento {} ({label}) não é um número finito: {v}", self.name, k + 1)));
            }
            if ty == F32 && !(v as f32).is_finite() {
                return Err(UnknownCall(format!("{}: o argumento {} ({label}) não cabe num f32: {v}", self.name, k + 1)));
            }
        }
        Ok(())
    }
}

/// Os argumentos já conferidos, lidos no tipo do parâmetro.
struct Args<'a> {
    sig: &'static Signature,
    v: &'a [f64],
}

impl Args<'_> {
    fn get(&self, k: usize, ty: Ty) -> f64 {
        // a conversão escrita em `parse` tem de bater com a tabela (que os testes conferem contra o
        // wasm); os testes passam por todas as chamadas com as asserções de depuração ligadas
        debug_assert_eq!(self.sig.params.get(k).map(|p| p.1), Some(ty), "{}: argumento {k} lido com o tipo errado", self.sig.name);
        // a aridade já foi conferida; o 0 só evita um pânico se a conversão e a tabela divergirem
        self.v.get(k).copied().unwrap_or(0.0)
    }

    fn f64(&self, k: usize) -> f64 {
        self.get(k, F64)
    }

    fn f32(&self, k: usize) -> f32 {
        self.get(k, F32) as f32
    }

    fn u32(&self, k: usize) -> u32 {
        wrap32(self.get(k, U32))
    }

    fn i32(&self, k: usize) -> i32 {
        wrap32(self.get(k, I32)) as i32
    }

    fn usize(&self, k: usize) -> usize {
        // o `usize` do wasm tem 32 bits: a mesma volta que a web faz
        wrap32(self.get(k, Usize)) as usize
    }

    /// Booleano do export: `u32` diferente de zero.
    fn flag(&self, k: usize) -> bool {
        self.u32(k) != 0
    }
}

impl Call {
    /// Valida e converte uma chamada (ver o topo do módulo). Não mexe em motor nenhum: serve para
    /// validar fora da thread de áudio.
    pub fn parse(name: &str, args: &[f64]) -> Result<Call, UnknownCall> {
        let Some(sig) = CALLS.iter().find(|s| s.name == name) else {
            return Err(UnknownCall(match name {
                "init" => "init: o motor nasce no hospedeiro, com a taxa dele; não vem na lista de chamadas".to_owned(),
                _ if HOST_ONLY.contains(&name) => format!("{name}: passa memória por ponteiro; o hospedeiro tem função própria para ela"),
                _ => format!("chamada desconhecida: {name:?}"),
            }));
        };
        sig.check(args)?;
        let a = Args { sig, v: args };
        Ok(match sig.name {
            "sample_drop" => Call::SampleDrop { id: a.u32(0) },
            "tempo" => Call::Tempo { bpm: a.f64(0), beats_per_bar: a.u32(1) },
            "tempo_clear" => Call::TempoClear,
            "tempo_point" => Call::TempoPoint { beat: a.f64(0), bpm: a.f64(1), ramp: a.flag(2) },
            "meter_clear" => Call::MeterClear,
            "meter_point" => Call::MeterPoint { bar: a.u32(0), num: a.u32(1), den: a.u32(2) },
            "play" => Call::Play,
            "stop" => Call::Stop,
            "seek" => Call::Seek { beat: a.f64(0) },
            "loop_set" => Call::LoopSet { on: a.flag(0), start: a.f64(1), end: a.f64(2) },
            "metronome" => Call::Metronome { on: a.flag(0), gain: a.f32(1) },
            "tracks" => {
                let n = a.usize(0);
                if n > MAX_TRACKS {
                    return Err(UnknownCall(format!("tracks: {} não é um número de faixas válido (0 a {MAX_TRACKS})", a.get(0, Usize))));
                }
                Call::Tracks { n }
            }
            "track" => Call::Track { track: a.usize(0), gain: a.f32(1), pan: a.f32(2), mute: a.flag(3), solo: a.flag(4) },
            "master" => Call::Master { gain: a.f32(0), pan: a.f32(1) },
            "clips_clear" => Call::ClipsClear,
            "clip_add" => Call::ClipAdd {
                track: a.usize(0),
                sample: a.u32(1),
                start: a.f64(2),
                offset: a.f64(3),
                length: a.f64(4),
                gain: a.f32(5),
                fade_in: a.f64(6),
                fade_out: a.f64(7),
            },
            "clip_fade_shape" => Call::ClipFadeShape { fade_in: a.u32(0), fade_out: a.u32(1) },
            "track_kind" => Call::TrackKind { track: a.usize(0), kind: a.u32(1) },
            "param" => Call::Param { track: a.usize(0), id: a.u32(1), value: a.f32(2) },
            "instrument_sample" => Call::InstrumentSample { track: a.usize(0), sample: a.u32(1) },
            "notes_clear" => Call::NotesClear,
            "note_add" => Call::NoteAdd { track: a.usize(0), start: a.f64(1), length: a.f64(2), pitch: a.u32(3), velocity: a.f32(4) },
            "live_on" => Call::LiveOn { track: a.usize(0), pitch: a.u32(1), velocity: a.f32(2) },
            "live_off" => Call::LiveOff { track: a.usize(0), pitch: a.u32(1) },
            "panic" => Call::Panic,
            "fx_count" => Call::FxCount { track: a.i32(0), n: a.u32(1) },
            "fx_set" => Call::FxSet { track: a.i32(0), slot: a.u32(1), kind: a.u32(2) },
            "fx_param" => Call::FxParam { track: a.i32(0), slot: a.u32(1), id: a.u32(2), value: a.f32(3) },
            "fx_bypass" => Call::FxBypass { track: a.i32(0), slot: a.u32(1), on: a.flag(2) },
            "sends_count" => Call::SendsCount { track: a.i32(0), n: a.u32(1) },
            "send_set" => Call::SendSet { track: a.i32(0), index: a.u32(1), bus: a.i32(2), level: a.f32(3), pre: a.flag(4) },
            "track_output" => Call::TrackOutput { track: a.i32(0), target: a.i32(1) },
            "auto_clear" => Call::AutoClear,
            "auto_lane" => Call::AutoLane { track: a.i32(0), target: a.u32(1), slot: a.u32(2), id: a.u32(3) },
            "auto_point" => Call::AutoPoint { lane: a.u32(0), beat: a.f64(1), value: a.f32(2), curve: a.f32(3) },
            "watch_fx" => Call::WatchFx { track: a.i32(0), slot: a.i32(1) },
            "watch_analyzer" => Call::WatchAnalyzer { track: a.i32(0) },
            "fx_meter" => Call::FxMeter,
            "input_monitor" => Call::InputMonitor { track: a.i32(0), on: a.flag(1) },
            "rec_notes_start" => Call::RecNotesStart,
            "rec_notes_stop" => Call::RecNotesStop,
            "capture_clear" => Call::CaptureClear,
            "capture_add" => Call::CaptureAdd { track: a.i32(0) },
            "beat" => Call::Beat,
            "playing" => Call::Playing,
            "loudness_reset" => Call::LoudnessReset,
            "loudness" => Call::Loudness { kind: a.u32(0) },
            "latency_frames" => Call::LatencyFrames,
            "zones_clear" => Call::ZonesClear { track: a.usize(0) },
            "zone_add" => {
                // notas, velocidades e grupo passam pelo limite do MIDI; o modo é "diferente de zero" = até o fim
                let byte = |k: usize| a.u32(k).min(127) as u8;
                Call::ZoneAdd {
                    track: a.usize(0),
                    sample: a.u32(1),
                    zone: ZoneDef {
                        root: byte(2),
                        lo: byte(3),
                        hi: byte(4),
                        vlo: byte(5),
                        vhi: byte(6),
                        cents: a.f32(7),
                        gain_db: a.f32(8),
                        pan: a.f32(9),
                        one_shot: a.flag(10),
                        start: a.f64(11),
                        end: a.f64(12),
                        loop_start: a.f64(13),
                        loop_end: a.f64(14),
                        group: a.u32(15).min(255) as u8,
                    },
                }
            }
            "live_bend" => Call::LiveBend { track: a.usize(0), value: a.f32(1) },
            "live_cc" => Call::LiveCc { track: a.usize(0), cc: a.u32(1), value: a.f32(2) },
            "cc_add" => Call::CcAdd { track: a.usize(0), cc: a.u32(1), beat: a.f64(2), value: a.f32(3) },
            "cc_clear" => Call::CcClear,
            "mod_clear" => Call::ModClear,
            "mod_source" => Call::ModSource {
                track: a.i32(0),
                index: a.u32(1),
                kind: a.u32(2),
                rate: a.f32(3),
                sync: a.flag(4),
                depth: a.f32(5),
                phase: a.f32(6),
                bipolar: a.flag(7),
                shape: a.u32(8),
                attack_ms: a.f32(9),
                release_ms: a.f32(10),
                value: a.f32(11),
            },
            "mod_dest" => Call::ModDest {
                track: a.i32(0),
                index: a.u32(1),
                dest: a.u32(2),
                target_kind: a.u32(3),
                slot: a.u32(4),
                id: a.u32(5),
                amount: a.f32(6),
                min: a.f32(7),
                max: a.f32(8),
                scale: a.u32(9),
            },
            // os testes passam por toda a tabela: chegar aqui é chamada nova sem conversão
            other => return Err(UnknownCall(format!("{other}: está na tabela de chamadas mas sem conversão (erro no motor)"))),
        })
    }

    /// Aplica no motor, exatamente como o corpo do export do wasm de mesmo nome. Devolve o valor
    /// das chamadas que o export devolve.
    pub fn apply(self, e: &mut Engine) -> Option<f64> {
        match self {
            Call::SampleDrop { id } => e.drop_sample(id),
            Call::Tempo { bpm, beats_per_bar } => e.set_tempo(bpm, beats_per_bar),
            Call::TempoClear => e.tempo_clear(),
            Call::TempoPoint { beat, bpm, ramp } => e.tempo_point(beat, bpm, ramp),
            Call::MeterClear => e.meter_clear(),
            Call::MeterPoint { bar, num, den } => e.meter_point(bar, num, den),
            Call::Play => e.play(),
            Call::Stop => e.stop(),
            Call::Seek { beat } => e.seek(beat),
            Call::LoopSet { on, start, end } => e.set_loop(on, start, end),
            Call::Metronome { on, gain } => e.set_metronome(on, gain),
            Call::Tracks { n } => e.set_track_count(n),
            Call::Track { track, gain, pan, mute, solo } => {
                if let Some(t) = e.track_mut(track) {
                    t.gain = gain;
                    t.pan = pan;
                    t.mute = mute;
                    t.solo = solo;
                }
            }
            Call::Master { gain, pan } => {
                let m = e.master_mut();
                m.gain = gain;
                m.pan = pan;
            }
            Call::ClipsClear => e.clear_clips(),
            Call::ClipAdd { track, sample, start, offset, length, gain, fade_in, fade_out } => {
                e.add_clip(Clip { track, sample, start, offset, length, gain, fade_in, fade_out })
            }
            Call::ClipFadeShape { fade_in, fade_out } => e.set_clip_fade_shape(fade_in, fade_out),
            Call::TrackKind { track, kind } => e.set_track_kind(track, kind),
            Call::Param { track, id, value } => e.set_param(track, id, value),
            Call::InstrumentSample { track, sample } => e.set_instrument_sample(track, sample),
            Call::NotesClear => e.clear_notes(),
            Call::NoteAdd { track, start, length, pitch, velocity } => e.add_note(track, start, length, pitch, velocity),
            Call::LiveOn { track, pitch, velocity } => e.live_on(track, pitch, velocity),
            Call::LiveOff { track, pitch } => e.live_off(track, pitch),
            Call::Panic => e.panic(),
            Call::FxCount { track, n } => e.set_fx_count(track, n as usize),
            Call::FxSet { track, slot, kind } => e.set_fx(track, slot as usize, kind),
            Call::FxParam { track, slot, id, value } => e.set_fx_param(track, slot as usize, id, value),
            Call::FxBypass { track, slot, on } => e.set_fx_bypass(track, slot as usize, on),
            // envios, saída e monitoramento são de faixa: o export ignora o master (−1) e abaixo
            Call::SendsCount { track, n } => {
                if track >= 0 {
                    e.set_sends_count(track as usize, n as usize)
                }
            }
            Call::SendSet { track, index, bus, level, pre } => {
                if track >= 0 {
                    e.set_send(track as usize, index as usize, bus, level, pre)
                }
            }
            Call::TrackOutput { track, target } => {
                if track >= 0 {
                    e.set_output(track as usize, target)
                }
            }
            Call::AutoClear => e.clear_automation(),
            Call::AutoLane { track, target, slot, id } => return Some(f64::from(e.add_lane(track, target, slot, id))),
            Call::AutoPoint { lane, beat, value, curve } => e.add_point(lane, beat, value, curve),
            Call::WatchFx { track, slot } => e.watch_fx(track, slot),
            Call::WatchAnalyzer { track } => e.watch_analyzer(track),
            Call::FxMeter => return Some(f64::from(e.fx_meter())),
            Call::InputMonitor { track, on } => {
                if track >= 0 {
                    e.set_monitor(track as usize, on)
                }
            }
            Call::RecNotesStart => e.rec_notes_start(),
            Call::RecNotesStop => e.rec_notes_stop(),
            Call::CaptureClear => e.capture_clear(),
            Call::CaptureAdd { track } => return Some(f64::from(e.capture_add(track))),
            Call::Beat => return Some(e.beat()),
            Call::Playing => return Some(f64::from(u32::from(e.playing()))),
            Call::LoudnessReset => e.loudness_reset(),
            Call::Loudness { kind } => return Some(e.loudness(kind)),
            Call::LatencyFrames => return Some(e.latency_frames() as f64),
            Call::ZonesClear { track } => e.clear_zones(track),
            Call::ZoneAdd { track, sample, zone } => e.add_zone(track, sample, zone),
            Call::LiveBend { track, value } => e.live_bend(track, value),
            Call::LiveCc { track, cc, value } => e.live_cc(track, cc, value),
            Call::CcAdd { track, cc, beat, value } => e.add_cc(track, cc, beat, value),
            Call::CcClear => e.clear_cc(),
            Call::ModClear => e.mod_clear(),
            Call::ModSource { track, index, kind, rate, sync, depth, phase, bipolar, shape, attack_ms, release_ms, value } => {
                e.mod_source(track, index as usize, kind, rate, sync, depth, phase, bipolar, shape, attack_ms, release_ms, value)
            }
            Call::ModDest { track, index, dest, target_kind, slot, id, amount, min, max, scale } => {
                e.mod_dest(track, index as usize, dest as usize, target_kind, slot, id, amount, min, max, scale)
            }
        }
        // o que o comando mudou na PDC (latência nova, crescimento dos atrasos) se resolve já, no
        // comando, e não no começo do próximo bloco
        e.settle();
        None
    }
}

#[cfg(test)]
mod tests {
    use std::f32::consts::TAU;

    use super::*;
    use crate::Sample;
    use crate::effect::{auto_target, compressor_param, kind as fx, utility_param};
    use crate::instrument::{kind, synth_param};

    const RATE: f64 = 48_000.0;
    const BLOCK: usize = 128;
    /// Blocos processados em cada observação: 4096 quadros, ~0,17 batida a 120 bpm.
    const BLOCKS: usize = 32;

    fn run(e: &mut Engine, blocks: usize) {
        let (mut l, mut r) = ([0.0f32; BLOCK], [0.0f32; BLOCK]);
        for _ in 0..blocks {
            e.process(&mut l, &mut r);
        }
    }

    // ------------------------------------------------------------ cenários de partida

    /// Quatro faixas: áudio com um clipe do sample 1 (tons diferentes em cada lado), sintetizador e
    /// sampler (ainda sem áudio) com notas desde a batida 0, e um barramento a meio volume. Parado
    /// na batida 0.
    fn base(e: &mut Engine) {
        let tone = |hz: f32| (0..48_000).map(|i| 0.5 * (TAU * hz * i as f32 / RATE as f32).sin()).collect::<Vec<f32>>();
        e.load_sample(1, Sample::new(vec![tone(440.0), tone(660.0)], RATE));
        e.set_track_count(4);
        e.add_clip(Clip { track: 0, sample: 1, start: 0.0, offset: 0.0, length: 1.0, gain: 1.0, fade_in: 0.0, fade_out: 0.0 });
        e.set_track_kind(1, kind::SYNTH);
        e.add_note(1, 0.0, 4.0, 60, 0.8);
        e.set_track_kind(2, kind::SAMPLER);
        e.add_note(2, 0.0, 4.0, 60, 0.8);
        e.set_track_kind(3, kind::BUS);
        e.track_mut(3).unwrap().gain = 0.5;
    }

    fn playing(e: &mut Engine) {
        base(e);
        e.play();
    }

    /// Tocando há alguns blocos: as notas da batida 0 já soam.
    fn sounding(e: &mut Engine) {
        playing(e);
        run(e, 8);
    }

    /// Tocando com uma mudança de andamento logo no começo (240 bpm a partir da batida 0,05).
    fn mapped(e: &mut Engine) {
        playing(e);
        e.tempo_point(0.05, 240.0, false);
    }

    /// Metrônomo ligado, perto do clique da batida 1 (a 0,9), num compasso de 1 tempo.
    fn metered(e: &mut Engine) {
        playing(e);
        e.set_metronome(true, 0.8);
        e.seek(0.9);
        e.meter_point(1, 1, 4);
    }

    /// Tocando, com um clipe de fade longo nas duas pontas (a curva do fade se ouve).
    fn faded(e: &mut Engine) {
        playing(e);
        e.clear_clips();
        e.add_clip(Clip { track: 0, sample: 1, start: 0.0, offset: 0.0, length: 0.5, gain: 1.0, fade_in: 0.2, fade_out: 0.2 });
    }

    fn utility(e: &mut Engine) {
        playing(e);
        e.set_fx_count(0, 1);
        e.set_fx(0, 0, fx::UTILITY);
        e.set_fx_param(0, 0, utility_param::GAIN, -12.0);
    }

    fn master_utility(e: &mut Engine) {
        playing(e);
        e.set_fx_count(-1, 1);
        e.set_fx(-1, 0, fx::UTILITY);
    }

    fn compressor(e: &mut Engine) {
        playing(e);
        e.set_fx_count(0, 1);
        e.set_fx(0, 0, fx::COMPRESSOR);
        e.set_fx_param(0, 0, compressor_param::THRESHOLD, -40.0);
        e.set_fx_param(0, 0, compressor_param::RATIO, 10.0);
    }

    fn watched(e: &mut Engine) {
        compressor(e);
        e.watch_fx(0, 0);
        run(e, 16);
    }

    fn send(e: &mut Engine) {
        playing(e);
        e.set_sends_count(0, 1);
        e.set_send(0, 0, 3, 1.0, false);
    }

    fn lane(e: &mut Engine) {
        playing(e);
        e.add_lane(0, auto_target::VOLUME, 0, 0);
    }

    fn automated(e: &mut Engine) {
        lane(e);
        e.add_point(0, 0.0, 0.05, 0.0);
    }

    /// Tocando há mais de 400 ms: a janela do momentâneo já fechou.
    fn measured(e: &mut Engine) {
        playing(e);
        run(e, 200);
    }

    fn held(e: &mut Engine) {
        playing(e);
        e.live_on(1, 60, 1.0);
        run(e, 4);
    }

    /// O sampler da faixa 2 com uma zona que cobre o teclado inteiro, tocando o sample 1.
    fn zoned(e: &mut Engine) {
        playing(e);
        e.add_zone(2, 1, ZoneDef::default().sanitized());
    }

    fn recording(e: &mut Engine) {
        playing(e);
        e.rec_notes_start();
        e.live_on(1, 64, 0.8);
        run(e, 4);
    }

    /// Tocando com um bend de clipe já valendo (sintetizador da faixa 1).
    fn bent(e: &mut Engine) {
        playing(e);
        e.add_cc(1, 128, 0.0, 1.0);
        run(e, 8);
    }

    /// Tocando com uma macro cheia (unipolar) modulando o volume da faixa 0 em −50%.
    fn modulated(e: &mut Engine) {
        playing(e);
        e.mod_source(0, 0, 2, 1.0, false, 1.0, 0.0, false, 0, 10.0, 100.0, 1.0);
        e.mod_dest(0, 0, 0, 0, 0, 0, -0.5, 0.0, 2.0, 2);
    }

    fn capturing(e: &mut Engine) {
        playing(e);
        e.capture_add(0);
    }

    // ------------------------------------------------------------ observação

    /// Tudo o que dá para ver de fora do motor, em bits (NaN igual a NaN): o estado logo depois da
    /// chamada, a saída e as capturas de alguns blocos (com entrada de áudio chegando), e depois os
    /// picos, o estado, o espectro e as notas gravadas.
    #[derive(Debug, PartialEq)]
    struct Obs {
        ret: Option<u64>,
        state: Vec<u64>,
        out: Vec<u32>,
        captured: Vec<u32>,
        peaks: Vec<u32>,
        end: Vec<u64>,
        spectrum: Vec<u32>,
        notes: Vec<u32>,
    }

    impl Obs {
        /// O primeiro aspecto em que as duas diferem (o retorno só conta com `ret`).
        fn diff(&self, o: &Obs, ret: bool) -> Option<&'static str> {
            [
                ("o retorno", !ret || self.ret == o.ret),
                ("o estado", self.state == o.state),
                ("a saída", self.out == o.out),
                ("as capturas", self.captured == o.captured),
                ("os picos", self.peaks == o.peaks),
                ("o estado final", self.end == o.end),
                ("o espectro", self.spectrum == o.spectrum),
                ("as notas gravadas", self.notes == o.notes),
            ]
            .into_iter()
            .find(|&(_, same)| !same)
            .map(|(what, _)| what)
        }
    }

    fn bits(v: &[f32]) -> impl Iterator<Item = u32> + '_ {
        v.iter().map(|s| s.to_bits())
    }

    fn status(e: &mut Engine) -> Vec<u64> {
        let mut v = vec![e.beat().to_bits(), u64::from(e.playing()), f64::from(e.fx_meter()).to_bits()];
        v.extend((0..5).map(|k| e.loudness(k).to_bits()));
        v
    }

    fn observe(e: &mut Engine, ret: Option<f64>, post: fn(&mut Engine)) -> Obs {
        post(e);
        let mut state = status(e);
        for (i, t) in e.tracks().iter().enumerate() {
            state.extend([t.gain, t.pan].map(|v| u64::from(v.to_bits())));
            state.extend([u64::from(t.mute), u64::from(t.solo), u64::from(e.track_kind(i).unwrap_or(u32::MAX))]);
        }
        state.extend([e.master().gain, e.master().pan].map(|v| u64::from(v.to_bits())));

        let (mut l, mut r, mut cl, mut cr) = ([0.0f32; BLOCK], [0.0f32; BLOCK], [0.0f32; BLOCK], [0.0f32; BLOCK]);
        let (mut out, mut captured) = (Vec::new(), Vec::new());
        for b in 0..BLOCKS {
            let input: Vec<f32> = (0..BLOCK).map(|i| 0.3 * (TAU * 1000.0 * (b * BLOCK + i) as f32 / RATE as f32).sin()).collect();
            e.set_input(&input, None);
            e.process(&mut l, &mut r);
            out.extend(bits(&l).chain(bits(&r)));
            for k in 0..2 {
                let n = e.captured(k, &mut cl, &mut cr);
                captured.push(n as u32);
                captured.extend(bits(&cl).chain(bits(&cr)));
            }
        }

        let mut peaks = Vec::new();
        for i in 0..e.tracks().len() {
            let (pl, pr) = e.track_mut(i).unwrap().take_peaks();
            peaks.extend(bits(&[pl, pr]));
        }
        let (pl, pr) = e.master_mut().take_peaks();
        peaks.extend(bits(&[pl, pr]));
        let mut spectrum = vec![0.0f32; 1024];
        let n = e.analyzer(&mut spectrum);
        let mut notes = vec![0.0f32; 5 * 16];
        let m = e.rec_notes(&mut notes);
        Obs {
            ret: ret.map(f64::to_bits),
            state,
            out,
            captured,
            peaks,
            end: status(e),
            spectrum: bits(&spectrum[..n]).collect(),
            notes: bits(&notes[..m]).collect(),
        }
    }

    // ------------------------------------------------------------ casos

    #[derive(Clone, Copy, Debug)]
    enum Effect {
        /// Muda algo visível em relação ao motor que não recebeu a chamada.
        Changes,
        /// Não muda nada visível (o export também não faria nada).
        Same,
        /// Consulta: devolve um valor (não zero, no cenário escolhido) e não muda nada.
        Query,
    }

    /// Uma chamada aplicada num cenário, o corpo do export equivalente (os mesmos métodos do motor
    /// com os argumentos já nos tipos da assinatura) e o que se faz nos três motores logo depois
    /// dela, antes de observar.
    struct Case {
        setup: fn(&mut Engine),
        name: &'static str,
        args: &'static [f64],
        direct: Direct,
        post: fn(&mut Engine),
        effect: Effect,
    }

    /// O corpo do export: sem retorno, ou devolvendo um número (já em f64).
    #[derive(Clone, Copy)]
    enum Direct {
        Unit(fn(&mut Engine)),
        Value(fn(&mut Engine) -> f64),
    }

    impl Direct {
        fn run(self, e: &mut Engine) -> Option<f64> {
            match self {
                Direct::Unit(f) => {
                    f(e);
                    None
                }
                Direct::Value(f) => Some(f(e)),
            }
        }
    }

    fn case(setup: fn(&mut Engine), name: &'static str, args: &'static [f64], direct: fn(&mut Engine), effect: Effect) -> Case {
        Case { setup, name, args, direct: Direct::Unit(direct), post: |_| {}, effect }
    }

    fn valued(setup: fn(&mut Engine), name: &'static str, args: &'static [f64], direct: fn(&mut Engine) -> f64, effect: Effect) -> Case {
        Case { setup, name, args, direct: Direct::Value(direct), post: |_| {}, effect }
    }

    impl Case {
        fn post(self, post: fn(&mut Engine)) -> Case {
            Case { post, ..self }
        }
    }

    fn cases() -> Vec<Case> {
        use Effect::{Changes, Query, Same};
        vec![
            case(playing, "sample_drop", &[1.0], |e| e.drop_sample(1), Changes),
            case(playing, "tempo", &[140.0, 3.0], |e| e.set_tempo(140.0, 3), Changes),
            // inteiro fora do u32 dá a volta como no JavaScript: −1 é u32::MAX, que o motor limita
            case(playing, "tempo", &[90.0, -1.0], |e| e.set_tempo(90.0, u32::MAX), Changes),
            case(mapped, "tempo_clear", &[], |e| e.tempo_clear(), Changes),
            case(playing, "tempo_point", &[0.05, 240.0, 0.0], |e| e.tempo_point(0.05, 240.0, false), Changes),
            case(playing, "tempo_point", &[0.0, 60.0, 1.0], |e| e.tempo_point(0.0, 60.0, true), Changes),
            case(metered, "meter_clear", &[], |e| e.meter_clear(), Changes),
            case(metered, "meter_point", &[1.0, 4.0, 4.0], |e| e.meter_point(1, 4, 4), Changes),
            case(base, "play", &[], |e| e.play(), Changes),
            case(playing, "stop", &[], |e| e.stop(), Changes),
            case(playing, "seek", &[2.5], |e| e.seek(2.5), Changes),
            case(playing, "loop_set", &[1.0, 0.0, 0.1], |e| e.set_loop(true, 0.0, 0.1), Changes),
            case(playing, "metronome", &[1.0, 0.8], |e| e.set_metronome(true, 0.8), Changes),
            // booleano é "diferente de zero" depois de virar inteiro: 0,5 é desligado
            case(playing, "metronome", &[0.5, 0.8], |e| e.set_metronome(false, 0.8), Same),
            case(playing, "tracks", &[2.0], |e| e.set_track_count(2), Changes),
            case(
                playing,
                "track",
                &[0.0, 0.25, 0.5, 0.0, 1.0],
                |e| {
                    let t = e.track_mut(0).unwrap();
                    (t.gain, t.pan, t.mute, t.solo) = (0.25, 0.5, false, true);
                },
                Changes,
            ),
            // índice usize negativo é faixa que não existe (na web, −1 vira 4294967295)
            case(playing, "track", &[-1.0, 0.0, 0.0, 1.0, 1.0], |_| {}, Same),
            case(
                playing,
                "master",
                &[0.5, -0.5],
                |e| {
                    let m = e.master_mut();
                    (m.gain, m.pan) = (0.5, -0.5);
                },
                Changes,
            ),
            case(playing, "clips_clear", &[], |e| e.clear_clips(), Changes),
            case(
                playing,
                "clip_add",
                &[0.0, 1.0, 0.0, 0.25, 0.5, 0.8, 0.01, 0.02],
                |e| e.add_clip(Clip { track: 0, sample: 1, start: 0.0, offset: 0.25, length: 0.5, gain: 0.8, fade_in: 0.01, fade_out: 0.02 }),
                Changes,
            ),
            case(faded, "clip_fade_shape", &[1.0, 3.0], |e| e.set_clip_fade_shape(1, 3), Changes),
            case(playing, "track_kind", &[1.0, 3.0], |e| e.set_track_kind(1, kind::SAMPLER), Changes),
            case(playing, "param", &[1.0, 13.0, 300.0], |e| e.set_param(1, synth_param::CUTOFF, 300.0), Changes),
            case(playing, "instrument_sample", &[2.0, 1.0], |e| e.set_instrument_sample(2, 1), Changes),
            case(playing, "notes_clear", &[], |e| e.clear_notes(), Changes),
            case(playing, "note_add", &[1.0, 0.0, 1.0, 72.0, 0.9], |e| e.add_note(1, 0.0, 1.0, 72, 0.9), Changes),
            case(playing, "live_on", &[1.0, 67.0, 1.0], |e| e.live_on(1, 67, 1.0), Changes),
            case(held, "live_off", &[1.0, 60.0], |e| e.live_off(1, 60), Changes),
            case(sounding, "panic", &[], |e| e.panic(), Changes),
            case(utility, "fx_count", &[0.0, 0.0], |e| e.set_fx_count(0, 0), Changes),
            case(utility, "fx_set", &[0.0, 0.0, 11.0], |e| e.set_fx(0, 0, fx::DISTORTION), Changes),
            case(utility, "fx_param", &[0.0, 0.0, 0.0, -24.0], |e| e.set_fx_param(0, 0, utility_param::GAIN, -24.0), Changes),
            // −1 num `i32` é o master
            case(master_utility, "fx_param", &[-1.0, 0.0, 0.0, -12.0], |e| e.set_fx_param(-1, 0, utility_param::GAIN, -12.0), Changes),
            case(utility, "fx_bypass", &[0.0, 0.0, 1.0], |e| e.set_fx_bypass(0, 0, true), Changes),
            case(send, "sends_count", &[0.0, 0.0], |e| e.set_sends_count(0, 0), Changes),
            // o master não tem envios: o export ignora
            case(send, "sends_count", &[-1.0, 0.0], |_| {}, Same),
            case(send, "send_set", &[0.0, 0.0, 3.0, 0.25, 1.0], |e| e.set_send(0, 0, 3, 0.25, true), Changes),
            case(playing, "track_output", &[0.0, 3.0], |e| e.set_output(0, 3), Changes),
            case(automated, "auto_clear", &[], |e| e.clear_automation(), Changes),
            case(zoned, "zones_clear", &[2.0], |e| e.clear_zones(2), Changes),
            case(
                playing,
                "zone_add",
                &[2.0, 1.0, 60.0, 0.0, 127.0, 1.0, 127.0, 0.0, -3.0, 0.25, 1.0, 0.1, 0.5, 0.0, 0.0, 2.0],
                |e| e.add_zone(2, 1, ZoneDef { gain_db: -3.0, pan: 0.25, one_shot: true, start: 0.1, end: 0.5, group: 2, ..ZoneDef::default() }),
                Changes,
            ),
            valued(playing, "auto_lane", &[0.0, 0.0, 0.0, 0.0], |e| f64::from(e.add_lane(0, 0, 0, 0)), Changes).post(|e| e.add_point(0, 0.0, 0.05, 0.0)),
            case(lane, "auto_point", &[0.0, 0.0, 0.05, 0.0], |e| e.add_point(0, 0.0, 0.05, 0.0), Changes),
            case(compressor, "watch_fx", &[0.0, 0.0], |e| e.watch_fx(0, 0), Changes),
            case(playing, "watch_analyzer", &[-1.0], |e| e.watch_analyzer(-1), Changes),
            valued(watched, "fx_meter", &[], |e| f64::from(e.fx_meter()), Query),
            case(playing, "input_monitor", &[0.0, 1.0], |e| e.set_monitor(0, true), Changes),
            case(playing, "rec_notes_start", &[], |e| e.rec_notes_start(), Changes).post(|e| e.live_on(1, 67, 0.8)),
            case(recording, "rec_notes_stop", &[], |e| e.rec_notes_stop(), Changes).post(|e| e.live_on(1, 67, 0.8)),
            case(capturing, "capture_clear", &[], |e| e.capture_clear(), Changes),
            valued(playing, "capture_add", &[0.0], |e| f64::from(e.capture_add(0)), Changes),
            valued(sounding, "beat", &[], |e| e.beat(), Query),
            valued(playing, "playing", &[], |e| f64::from(u32::from(e.playing())), Query),
            case(measured, "loudness_reset", &[], |e| e.loudness_reset(), Changes),
            valued(measured, "loudness", &[3.0], |e| e.loudness(3), Query),
            valued(playing, "latency_frames", &[], |e| e.latency_frames() as f64, Query),
            case(sounding, "live_bend", &[1.0, 1.0], |e| e.live_bend(1, 1.0), Changes),
            case(sounding, "live_cc", &[1.0, 1.0, 1.0], |e| e.live_cc(1, 1, 1.0), Changes),
            // controle que o motor não conhece e faixa que não existe: inócuos
            case(sounding, "live_cc", &[1.0, 7.0, 1.0], |_| {}, Same),
            case(sounding, "live_cc", &[-1.0, 128.0, 1.0], |_| {}, Same),
            case(playing, "cc_add", &[1.0, 128.0, 0.0, 1.0], |e| e.add_cc(1, 128, 0.0, 1.0), Changes),
            case(bent, "cc_clear", &[], |e| e.clear_cc(), Changes),
            case(modulated, "mod_clear", &[], |e| e.mod_clear(), Changes),
            case(
                modulated,
                "mod_source",
                &[0.0, 0.0, 2.0, 1.0, 0.0, 1.0, 0.0, 0.0, 0.0, 10.0, 100.0, 0.0],
                |e| e.mod_source(0, 0, 2, 1.0, false, 1.0, 0.0, false, 0, 10.0, 100.0, 0.0),
                Changes,
            ),
            case(modulated, "mod_dest", &[0.0, 0.0, 0.0, 0.0, 0.0, 0.0, -0.25, 0.0, 2.0, 2.0], |e| e.mod_dest(0, 0, 0, 0, 0, 0, -0.25, 0.0, 2.0, 2), Changes),
        ]
    }

    #[test]
    fn cada_chamada_muda_o_motor_como_o_export() {
        let cases = cases();
        for c in &cases {
            let label = format!("{}{:?}", c.name, c.args);
            let (mut a, mut b, mut control) = (Engine::new(RATE), Engine::new(RATE), Engine::new(RATE));
            for e in [&mut a, &mut b, &mut control] {
                (c.setup)(e);
            }
            let got = apply(&mut a, c.name, c.args).unwrap_or_else(|err| panic!("{label}: {err}"));
            let want = c.direct.run(&mut b);
            let (a, b, control) = (observe(&mut a, got, c.post), observe(&mut b, want, c.post), observe(&mut control, None, c.post));
            if let Some(what) = a.diff(&b, true) {
                panic!("{label}: apply e o export diferem n{what}");
            }
            let changed = a.diff(&control, false);
            match c.effect {
                Effect::Changes => assert!(changed.is_some(), "{label}: não mudou nada no motor"),
                Effect::Same => assert!(changed.is_none(), "{label}: devia ser inócua e mudou {}", changed.unwrap_or_default()),
                Effect::Query => {
                    assert!(matches!(got, Some(v) if v != 0.0), "{label}: consulta devolveu {got:?}");
                    assert!(changed.is_none(), "{label}: consulta mudou {}", changed.unwrap_or_default());
                }
            }
        }
        for s in CALLS {
            assert!(cases.iter().any(|c| c.name == s.name), "{}: chamada sem caso de teste", s.name);
        }
    }

    /// Um export do wasm lido do fonte: nome, tipos dos parâmetros e do retorno.
    struct Export {
        name: String,
        params: Vec<String>,
        ret: Option<String>,
    }

    fn wasm_exports() -> Vec<Export> {
        let src = include_str!("../wasm/src/lib.rs");
        src.split("extern \"C\" fn ")
            .skip(1)
            .map(|rest| {
                let (open, close, body) = (rest.find('(').unwrap(), rest.find(')').unwrap(), rest.find('{').unwrap());
                let params =
                    rest[open + 1..close].split(',').map(str::trim).filter(|p| !p.is_empty()).map(|p| p.split_once(':').unwrap().1.trim().to_owned()).collect();
                let ret = rest[close + 1..body].trim().strip_prefix("->").map(|t| t.trim().to_owned());
                Export { name: rest[..open].trim().to_owned(), params, ret }
            })
            .collect()
    }

    fn ty_name(ty: Ty) -> &'static str {
        match ty {
            F64 => "f64",
            F32 => "f32",
            U32 => "u32",
            I32 => "i32",
            Usize => "usize",
        }
    }

    #[test]
    fn apply_conhece_todos_os_exports_sem_ponteiro_do_wasm() {
        let exports = wasm_exports();
        // o fonte ainda tem o formato que a leitura espera (uma troca por macro não passa batida)
        assert!(exports.len() >= CALLS.len() + HOST_ONLY.len(), "só {} exports lidos do wasm", exports.len());
        for x in &exports {
            let pointer = x.params.iter().chain(&x.ret).any(|t| t.contains('*'));
            if pointer || HOST_ONLY.contains(&x.name.as_str()) {
                assert!(HOST_ONLY.contains(&x.name.as_str()), "{}: export com ponteiro precisa de função no hospedeiro (e de entrar em HOST_ONLY)", x.name);
                assert!(!CALLS.iter().any(|s| s.name == x.name), "{}: é do hospedeiro e está na tabela", x.name);
                let err = Call::parse(&x.name, &[0.0; 8]).unwrap_err();
                assert!(err.0.starts_with(&format!("{}:", x.name)), "{}: mensagem {err}", x.name);
                continue;
            }
            let Some(s) = CALLS.iter().find(|s| s.name == x.name) else {
                panic!("apply não conhece o export {}: espelhe em CALLS e em Call", x.name);
            };
            let params: Vec<&str> = s.params.iter().map(|&(_, ty)| ty_name(ty)).collect();
            assert_eq!(params, x.params, "{}: parâmetros diferentes do export", x.name);
            assert_eq!(s.ret.map(ty_name), x.ret.as_deref(), "{}: retorno diferente do export", x.name);
        }
        for s in CALLS {
            assert!(exports.iter().any(|x| x.name == s.name), "{}: na tabela mas não existe no wasm", s.name);
            assert_eq!(CALLS.iter().filter(|o| o.name == s.name).count(), 1, "{}: repetida na tabela", s.name);
        }
        for name in HOST_ONLY {
            assert!(exports.iter().any(|x| x.name == *name), "{name}: em HOST_ONLY mas não existe no wasm");
        }
    }

    #[test]
    fn clip_fade_shape_vale_para_o_ultimo_clipe() {
        let mut e = Engine::new(RATE);
        e.set_track_count(1);
        apply(&mut e, "clip_add", &[0.0, 1.0, 0.0, 0.0, 1.0, 1.0, 0.1, 0.1]).unwrap();
        apply(&mut e, "clip_add", &[0.0, 1.0, 2.0, 0.0, 1.0, 1.0, 0.1, 0.1]).unwrap();
        apply(&mut e, "clip_fade_shape", &[1.0, 3.0]).unwrap();
        assert_eq!(e.clip_shapes, vec![(0, 0), (1, 3)]);
        assert!(apply(&mut e, "clip_fade_shape", &[1.0]).is_err());
    }

    #[test]
    fn so_as_chamadas_com_retorno_devolvem_valor() {
        for s in CALLS {
            let mut e = Engine::new(RATE);
            e.set_track_count(2);
            let got = apply(&mut e, s.name, &[0.0; 16]).unwrap_or_else(|err| panic!("{err}"));
            assert_eq!(got.is_some(), s.ret.is_some(), "{}: devolveu {got:?}", s.name);
        }
    }

    #[test]
    fn argumento_ruim_e_erro_e_nao_mexe_no_motor() {
        let mut e = Engine::new(RATE);
        e.set_track_count(2);
        let err = |e: &mut Engine, name: &str, args: &[f64]| apply(e, name, args).unwrap_err().0;

        let m = err(&mut e, "tempo", &[140.0]);
        assert!(m.starts_with("tempo:") && m.contains("tempos por compasso") && m.contains("veio 1"), "{m}");
        let m = err(&mut e, "seek", &[]);
        assert!(m.contains("espera 1 argumento (batida), vieram 0"), "{m}");
        for bad in [f64::NAN, f64::INFINITY, f64::NEG_INFINITY] {
            let m = err(&mut e, "seek", &[bad]);
            assert!(m.starts_with("seek:") && m.contains("batida") && m.contains("finito"), "{m}");
            let m = err(&mut e, "note_add", &[0.0, 0.0, 1.0, 60.0, bad]);
            assert!(m.contains("argumento 5 (velocidade)"), "{m}");
        }
        let m = err(&mut e, "param", &[0.0, 1.0, 1e39]);
        assert!(m.contains("não cabe num f32"), "{m}");
        let m = err(&mut e, "frobnicate", &[1.0]);
        assert!(m.contains("desconhecida") && m.contains("frobnicate"), "{m}");
        assert!(err(&mut e, "init", &[RATE]).contains("hospedeiro"));
        assert!(err(&mut e, "peaks", &[]).contains("ponteiro"));
        assert!(err(&mut e, "", &[]).contains("desconhecida"));
        for n in [-1.0, (MAX_TRACKS + 1) as f64, 1e12] {
            let m = err(&mut e, "tracks", &[n]);
            assert!(m.starts_with("tracks:") && m.contains(&format!("0 a {MAX_TRACKS}")), "{m}");
        }
        // nada do que falhou chegou ao motor
        assert_eq!(e.tracks().len(), 2);
        assert_eq!(e.beat(), 0.0);
        assert!(!e.playing());

        // argumento a mais é ignorado (inclusive não finito), como no JavaScript
        assert_eq!(apply(&mut e, "play", &[1.0, f64::NAN]), Ok(None));
        assert!(e.playing());
        assert_eq!(apply(&mut e, "tracks", &[MAX_TRACKS as f64]), Ok(None));
        assert_eq!(e.tracks().len(), MAX_TRACKS);
    }

    #[test]
    fn numeros_convertem_como_o_javascript_chamando_o_wasm() {
        assert_eq!(wrap32(0.0), 0);
        assert_eq!(wrap32(-0.0), 0);
        assert_eq!(wrap32(2.9), 2);
        assert_eq!(wrap32(-1.0), u32::MAX);
        assert_eq!(wrap32(-2.9), u32::MAX - 1);
        assert_eq!(wrap32(4_294_967_296.0), 0);
        assert_eq!(wrap32(4_294_967_297.0), 1);
        assert_eq!(wrap32(-4_294_967_297.0), u32::MAX);
        // 2⁵³ + 2³² ainda é exato em f64: sobra 0 depois da volta
        assert_eq!(wrap32(9_007_199_254_740_992.0 + 4_294_967_296.0), 0);

        let p = |name: &str, args: &[f64]| Call::parse(name, args).unwrap();
        assert_eq!(p("fx_count", &[-1.0, 2.0]), Call::FxCount { track: -1, n: 2 });
        assert_eq!(p("watch_analyzer", &[-2.0]), Call::WatchAnalyzer { track: -2 });
        assert_eq!(p("watch_analyzer", &[4_294_967_294.0]), Call::WatchAnalyzer { track: -2 });
        assert_eq!(p("track_kind", &[-1.0, 1.0]), Call::TrackKind { track: u32::MAX as usize, kind: 1 });
        assert_eq!(p("fx_bypass", &[0.0, 1.5, 2.0]), Call::FxBypass { track: 0, slot: 1, on: true });
        assert_eq!(p("fx_bypass", &[0.0, 0.0, 0.5]), Call::FxBypass { track: 0, slot: 0, on: false });
        assert_eq!(p("loop_set", &[-1.0, 1.0, 2.0]), Call::LoopSet { on: true, start: 1.0, end: 2.0 });
        assert_eq!(p("live_on", &[1.0, 60.0, 0.1]), Call::LiveOn { track: 1, pitch: 60, velocity: 0.1f32 });
        assert_eq!(p("playing", &[]), Call::Playing);
        assert_eq!(p("cc_add", &[1.0, 64.0, 2.5, 1.0]), Call::CcAdd { track: 1, cc: 64, beat: 2.5, value: 1.0 });
        assert_eq!(p("live_bend", &[1.0, -0.5]), Call::LiveBend { track: 1, value: -0.5 });
    }

    #[test]
    fn chamada_convertida_e_copia_simples() {
        // atravessa uma fila sem trava de elementos fixos até a thread de áudio, sem heap
        fn plain<T: Copy + Send + 'static>() {}
        plain::<Call>();
        // a maior é `zone_add` (uma zona inteira, com o trecho e o loop em f64)
        assert!(std::mem::size_of::<Call>() <= 96, "{} bytes", std::mem::size_of::<Call>());
    }
}
