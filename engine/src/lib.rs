//! Motor de áudio do jopendaw.
//!
//! Tudo o que soa passa por aqui: o transporte (tocar, parar, loop), os clipes de áudio na linha do
//! tempo, as faixas de instrumento com as notas do sequenciador e as tocadas ao vivo, o mixer
//! (volume, pan, mudo, solo) e o metrônomo. O crate não sabe de plataforma: quem o hospeda (o
//! AudioWorklet na web, o AAudio no Android) chama [`Engine::process`] com blocos de amostras e manda
//! os comandos entre um bloco e outro, na mesma thread de áudio.
//!
//! O tempo da linha do tempo é contado em quadros (amostras por canal) na taxa do motor; posições
//! do documento chegam em tempos musicais (batidas) e viram quadros pelo andamento atual.
//!
//! # Notas
//!
//! Cada faixa guarda as notas do sequenciador ordenadas pelo início, em batidas absolutas da linha
//! do tempo; o app reenvia todas a cada edição ([`Engine::clear_notes`] + [`Engine::add_note`]),
//! inclusive tocando. Os eventos caem no quadro exato: o bloco é fatiado nos pontos das notas e o
//! instrumento renderiza cada fatia. O note on vem da lista; o note off vem do conjunto de notas
//! que o sequenciador disparou e ainda soam (altura e fim), mantido aqui, e não da lista: assim um
//! reenvio no meio de uma nota (que pode até apagá-la) nunca deixa nota presa. Tocar a partir do
//! meio de uma nota não a "persegue": só soam as notas que começam dali em diante.
//!
//! # Roteamento
//!
//! Cada faixa tem um buffer de trabalho por bloco. O caminho de uma faixa é: instrumento e clipes
//! (ou, num barramento, o que chegou nele) → inserts ([`Chain`]) → envios pré-fader → volume, pan
//! e mudo → envios pós-fader → porta do solo → saída (master ou um barramento). As faixas normais
//! são processadas primeiro (quem serve de chave de sidechain antes de quem a usa), depois os
//! barramentos em ordem de índice: o app garante que barramento só sai ou envia para barramento
//! de índice maior; um destino que quebre isso é ignorado (a saída vira o master). O master soma
//! tudo, passa pela cadeia dele, aplica o volume e, por último, o limitador de segurança.
//!
//! Os efeitos rodam mesmo sem nada tocando enquanto houver cauda; quando a entrada está calada e
//! a saída da cadeia fica em silêncio por mais tempo que o maior atraso que ela pode devolver, a
//! cadeia para de rodar até a entrada voltar. A latência de efeito (lookahead, filtros de fase
//! linear) é compensada por atrasos nas faixas que chegam mais cedo (PDC, `Engine::pdc_update`) e
//! também no clique do metrônomo; a latência total sai em [`Engine::latency_frames`].
//!
//! # Automação
//!
//! Lanes com pontos em batidas (curva entre um ponto e o próximo). Tocando, o bloco é fatiado em
//! passos de [`AUTO_STEP`] quadros e cada passo avalia as lanes e aplica: volume, pan, parâmetro
//! do instrumento, parâmetro de efeito, nível de envio. O valor estático que o app manda fica
//! guardado; parado (ou quando a lane some), vale ele de novo.
//!
//! # Gravação
//!
//! O hospedeiro entrega a entrada de áudio de cada bloco ([`Engine::set_input`]) antes do
//! `process`; faixas de áudio monitorando ([`Engine::set_monitor`]) somam essa entrada no buffer
//! delas antes dos inserts, então o que se ouve passa pela cadeia, pelo fader e pelo roteamento da
//! faixa. Bloco sem entrada entregue não soma nada. O áudio gravado em si o hospedeiro copia da
//! entrada; o motor registra as notas ao vivo ([`Engine::rec_notes_start`]) com a batida em que
//! as aplicou, só com o transporte tocando.
//!
//! # Render fora de tempo real
//!
//! O mesmo motor, numa instância à parte, recebe as mesmas chamadas do documento e é processado
//! o mais rápido possível; as capturas ([`Engine::capture_add`]) copiam a saída pós-fader de
//! faixas (a mesma posição dos medidores) e a do master depois do limitador. O resultado depende
//! só das chamadas e dos quadros processados, nunca de relógio: as fatias internas seguem uma
//! grade fixa de [`CHUNK`] quadros contada desde o começo do render, então processar em blocos de
//! 4096 dá exatamente o mesmo que em blocos de 128. No primeiro `process` depois de mexer nas
//! capturas o motor prepara o render: termina no silêncio as transições que um motor recém-criado
//! ainda faria (efeitos entrando em crossfade, envios subindo do zero) e adianta o transporte da
//! latência do limitador do master, atrasando as faixas do mesmo tanto, para que todas as
//! capturas saiam alinhadas com a linha do tempo desde o primeiro quadro.

pub mod analyzer;
pub mod api;
pub mod drums;
pub mod dsp;
pub mod effect;
pub mod expression;
pub mod fm;
pub mod fx;
pub mod instrument;
mod limiter;
pub mod loudness;
mod metronome;
pub mod mixer;
#[cfg(test)]
mod pdc_tests;
pub mod record;
pub mod sampler;
pub mod stretch;
pub mod synth;
pub mod tempo;
#[cfg(test)]
mod tempo_tests;
#[cfg(test)]
mod testalloc;
pub mod wavetable;

use std::collections::HashMap;
use std::sync::Arc;

pub use metronome::Metronome;
pub use mixer::{Chain, MAX_SENDS, MAX_SLOTS, STATIC_PARAMS, Send, Track, pan_gains};

use analyzer::Analyzer;
use dsp::Delay;
use instrument::Instrument;
use mixer::{Scratch, Stereo};
use record::{Captures, NoteRecorder};
use tempo::{MeterMap, TempoMap};

/// Maior bloco que instrumentos e efeitos recebem de uma vez (contrato com eles). Também é o maior
/// bloco do hospedeiro cuja entrada e capturas o motor guarda inteiras.
pub const MAX_BLOCK: usize = 4096;

/// Bloco interno de processamento, numa grade fixa: as fatias terminam nos múltiplos de `CHUNK`
/// do relógio do motor (quadros processados), seja qual for o bloco do hospedeiro. Com isso um
/// bloco de 4096 é fatiado nos mesmos pontos que 32 blocos de 128 (o que o worklet manda) e o
/// render fora de tempo real sai idêntico, amostra por amostra. Os buffers de cada faixa têm este
/// tamanho.
pub const CHUNK: usize = 128;

/// Silêncio que o preparo do render passa pelas cadeias de efeitos para terminar as transições
/// (crossfade de 10 ms de efeito entrando), com folga.
const WARMUP_SECS: f64 = 0.05;

/// Com automação tocando, o bloco é fatiado neste passo (quadros) e cada fatia avalia as lanes:
/// 0,7 ms a 48 kHz, fino o bastante para uma rampa de volume não dar degraus (o fader ainda
/// suaviza entre um passo e outro).
pub const AUTO_STEP: usize = 32;

/// Intervalo mínimo entre dois recálculos da PDC causados por automação de latência (segundos).
const PDC_AUTO_SECS: f64 = 0.02;

/// Saída abaixo disso (−120 dB) conta como silêncio para a cadeia de efeitos poder parar.
const SILENCE: f32 = 1e-6;

/// Fade dos clipes de áudio ao parar: cortar o áudio no meio de uma onda estala.
const STOP_FADE_SECS: f64 = 0.01;

/// Notas reservadas por faixa (cabem sem realocar; passar disso realoca no comando, nunca no
/// `process`).
const NOTES_RESERVED: usize = 1024;
/// Eventos de controle (bend, modulação, pedal) reservados por faixa.
const CC_RESERVED: usize = 512;

/// Um áudio decodificado: um ou dois canais na taxa em que foi gravado.
pub struct Sample {
    channels: Vec<Vec<f32>>,
    rate: f64,
}

impl Sample {
    /// `channels` precisa ter 1 ou 2 canais do mesmo tamanho.
    pub fn new(mut channels: Vec<Vec<f32>>, rate: f64) -> Self {
        channels.truncate(2);
        if channels.is_empty() {
            channels.push(Vec::new());
        }
        let len = channels.iter().map(Vec::len).min().unwrap_or(0);
        for c in &mut channels {
            c.truncate(len);
        }
        Self { channels, rate }
    }

    pub fn frames(&self) -> usize {
        self.channels[0].len()
    }

    pub fn channels(&self) -> usize {
        self.channels.len()
    }

    /// As amostras de um canal (o último, se `ch` passar do número de canais).
    pub fn channel(&self, ch: usize) -> &[f32] {
        &self.channels[ch.min(self.channels.len() - 1)]
    }

    pub fn rate(&self) -> f64 {
        self.rate
    }

    pub fn duration(&self) -> f64 {
        self.frames() as f64 / self.rate
    }

    /// Amostra em `pos` (quadro fracionário) com interpolação linear; fora do áudio é silêncio.
    pub fn at(&self, ch: usize, pos: f64) -> f32 {
        let data = self.channel(ch);
        if pos < 0.0 {
            return 0.0;
        }
        let i = pos as usize;
        if i + 1 >= data.len() {
            return if i < data.len() { data[i] } else { 0.0 };
        }
        let frac = (pos - i as f64) as f32;
        data[i] + (data[i + 1] - data[i]) * frac
    }

    /// Amostra em `pos` com interpolação cúbica ([`hermite`]); fora do áudio é silêncio. Mais
    /// limpa que a linear na conversão de taxa (menos perda de agudos e menos imagens).
    pub fn at_cubic(&self, ch: usize, pos: f64) -> f32 {
        let data = self.channel(ch);
        if !(pos >= 0.0 && pos < data.len() as f64) {
            return 0.0;
        }
        let i = pos as usize;
        let t = (pos - i as f64) as f32;
        let get = |k: usize| data.get(k).copied().unwrap_or(0.0);
        let before = if i > 0 { data[i - 1] } else { 0.0 };
        hermite(before, data[i], get(i + 1), get(i + 2), t)
    }
}

/// Interpolação de Hermite (Catmull-Rom) de 4 pontos: o valor entre `x1` e `x2` na fração `t`.
/// Reproduz retas exatamente e passa pelos pontos.
#[inline]
pub fn hermite(x0: f32, x1: f32, x2: f32, x3: f32, t: f32) -> f32 {
    let c1 = 0.5 * (x2 - x0);
    let c2 = x0 - 2.5 * x1 + 2.0 * x2 - 0.5 * x3;
    let c3 = 0.5 * (x3 - x0) + 1.5 * (x1 - x2);
    ((c3 * t + c2) * t + c1) * t + x1
}

/// Um clipe de áudio numa faixa: que pedaço do sample toca e onde.
#[derive(Clone, Debug, PartialEq)]
pub struct Clip {
    pub track: usize,
    pub sample: u32,
    /// Início na linha do tempo, em batidas.
    pub start: f64,
    /// De onde o clipe começa a ler o sample, em segundos.
    pub offset: f64,
    /// Duração, em segundos do sample.
    pub length: f64,
    pub gain: f32,
    pub fade_in: f64,
    pub fade_out: f64,
}

/// Uma nota do sequenciador, em batidas absolutas da linha do tempo.
#[derive(Clone, Copy, Debug, PartialEq)]
struct Note {
    start: f64,
    end: f64,
    pitch: u8,
    velocity: f32,
}

/// Nota que o sequenciador disparou e ainda não soltou: altura e fim (batidas).
#[derive(Clone, Copy, Debug)]
struct Held {
    pitch: u8,
    end: f64,
}

/// Folga para posições que caem num quadro inteiro "quase exato" (erro de ponto flutuante na
/// conversão batida → quadro) não escorregarem para o quadro seguinte.
const FRAME_EPS: f64 = 1e-6;

/// Quadro do bloco (a partir de `pos`) em que cai um evento no quadro fracionário `frame`: o
/// primeiro quadro inteiro que o alcança. Negativo = já passou.
#[inline]
fn event_offset(frame: f64, pos: f64) -> f64 {
    (frame - pos - FRAME_EPS).ceil()
}

/// O que uma faixa tem além do canal do mixer: o tipo, o instrumento e as notas.
struct Lane {
    kind: u32,
    instrument: Option<Box<dyn Instrument>>,
    /// Áudio do sampler (id do motor, 0 = nenhum). Guardado para ligar quando o áudio chegar ou
    /// quando o instrumento for recriado.
    sample: u32,
    notes: Vec<Note>,
    /// Próxima nota da lista a disparar.
    cursor: usize,
    /// Notas do sequenciador soando; no máximo uma por altura.
    held: Vec<Held>,
    /// Últimos valores de parâmetro que o app mandou (NaN = nunca), para a automação devolver.
    statics: [f32; STATIC_PARAMS],
    /// Monitorando a entrada de áudio (só vale em faixa de áudio). Guardado mesmo em outro tipo:
    /// voltar a ser de áudio volta a monitorar.
    monitor: bool,
    /// Eventos de controle do clipe (ver `expression`), ordenados por batida; o cursor aponta o
    /// próximo a disparar e `cc_seq` numera a chegada para desempatar a ordenação.
    cc: Vec<expression::CcEvent>,
    cc_cursor: usize,
    cc_seq: u32,
    expr: expression::ExprState,
}

impl Lane {
    fn new() -> Self {
        Self {
            kind: instrument::kind::AUDIO,
            instrument: None,
            sample: 0,
            notes: Vec::with_capacity(NOTES_RESERVED),
            cursor: 0,
            held: Vec::with_capacity(128),
            statics: [f32::NAN; STATIC_PARAMS],
            monitor: false,
            cc: Vec::with_capacity(CC_RESERVED),
            cc_cursor: 0,
            cc_seq: 0,
            expr: expression::ExprState::new(instrument::kind::AUDIO),
        }
    }

    /// Aponta o cursor para a primeira nota que ainda não começou em `pos`.
    fn cue(&mut self, pos: f64, tempo: &TempoMap, playing: bool) {
        self.cursor = self.notes.partition_point(|n| event_offset(tempo.to_frames(n.start), pos) < 0.0);
        self.cue_cc(pos, tempo, playing);
    }

    /// Solta as notas do sequenciador (seek, volta do loop). As ao vivo continuam.
    fn release_held(&mut self) {
        self.release_held_pedal();
    }

    /// Soma o instrumento no bloco que começa em `pos`, disparando e soltando as notas do
    /// sequenciador nos quadros exatos quando o transporte anda. Devolve se renderizou algo.
    fn render(&mut self, l: &mut [f32], r: &mut [f32], playing: bool, pos: f64, tempo: &TempoMap) -> bool {
        let Self { instrument, notes, cursor, held, cc, cc_cursor, expr, .. } = self;
        let Some(inst) = instrument.as_mut() else { return false };
        let n = l.len();
        let offset = |beat: f64| event_offset(tempo.to_frames(beat), pos).clamp(0.0, n as f64) as usize;
        // próximo quadro com evento: o fim mais próximo das que soam ou o início da próxima nota
        let next_event = |held: &[Held], cursor: usize, cc_cursor: usize| {
            let off = held.iter().map(|h| offset(h.end)).min().unwrap_or(n);
            let off = notes.get(cursor).map_or(off, |note| off.min(offset(note.start)));
            cc.get(cc_cursor).map_or(off, |e| off.min(offset(e.beat)))
        };
        let mut at = 0;
        let mut sounded = false;
        // parado não há eventos do sequenciador: o instrumento só soa (notas ao vivo, caudas)
        let mut next = if playing { next_event(held, *cursor, *cc_cursor) } else { n };
        while next < n {
            if next > at {
                if inst.active() {
                    inst.render(&mut l[at..next], &mut r[at..next]);
                    sounded = true;
                }
                at = next;
            }
            // controles primeiro: o pedal que desce na batida de uma nota a segura, e o que sobe na
            // batida de outra solta as anteriores antes dela
            while let Some(&ev) = cc.get(*cc_cursor) {
                if offset(ev.beat) > next {
                    break;
                }
                *cc_cursor += 1;
                expr.set(inst.as_mut(), ev.cc, ev.value);
            }
            // no mesmo quadro, primeiro solta: uma nota que termina onde a mesma altura recomeça
            // não pode cortar a nova
            held.retain(|h| {
                let due = offset(h.end) <= next;
                if due {
                    expr.note_off(inst.as_mut(), h.pitch);
                }
                !due
            });
            while let Some(&note) = notes.get(*cursor) {
                if offset(note.start) > next {
                    break;
                }
                *cursor += 1;
                expr.note_on(inst.as_mut(), note.pitch, note.velocity);
                hold(held, note.pitch, note.end);
            }
            next = next_event(held, *cursor, *cc_cursor);
        }
        if at < n && inst.active() {
            inst.render(&mut l[at..], &mut r[at..]);
            sounded = true;
        }
        sounded
    }
}

/// Guarda uma nota que o sequenciador disparou. A mesma altura de novo antes de soltar (notas
/// sobrepostas) fica com o fim mais tardio; senão o note off da primeira cortaria a segunda.
fn hold(held: &mut Vec<Held>, pitch: u8, end: f64) {
    match held.iter_mut().find(|h| h.pitch == pitch) {
        Some(h) => h.end = h.end.max(end),
        None => held.push(Held { pitch, end }),
    }
}

/// Um ponto de automação: o valor numa batida e a curva até o próximo ponto.
#[derive(Clone, Copy, Debug)]
struct AutoPoint {
    beat: f64,
    value: f32,
    /// −1..1: entre este ponto e o próximo o valor segue t^(2^(curva·3)) (0 = reta).
    curve: f32,
}

/// O que uma lane de automação move: faixa (−1 master), tipo ([`effect::auto_target`]), slot (do
/// efeito ou índice do envio) e id do parâmetro. Campos que o tipo não usa ficam em 0.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct Target {
    track: i32,
    kind: u32,
    slot: u32,
    id: u32,
}

impl Target {
    fn new(track: i32, kind: u32, slot: u32, id: u32) -> Self {
        use effect::auto_target as at;
        let (slot, id) = match kind {
            at::VOLUME | at::PAN => (0, 0),
            at::INSTRUMENT => (0, id),
            at::SEND => (slot, 0),
            _ => (slot, id),
        };
        Self { track, kind, slot, id }
    }
}

/// Pontos reservados por lane (cabem sem realocar; passar disso realoca no comando).
const POINTS_RESERVED: usize = 256;

struct AutoLane {
    target: Target,
    /// Ordenados pela batida; pontos na mesma batida ficam na ordem em que chegaram (um salto).
    points: Vec<AutoPoint>,
    /// Último valor aplicado (NaN = nenhum): parâmetros de instrumento e efeito só são mexidos
    /// quando o valor muda.
    last: f32,
}

impl AutoLane {
    fn new() -> Self {
        Self { target: Target::new(-1, 0, 0, 0), points: Vec::with_capacity(POINTS_RESERVED), last: f32::NAN }
    }

    /// Valor na batida: antes do primeiro ponto vale o primeiro; depois do último, o último.
    fn value_at(&self, beat: f64) -> Option<f32> {
        let p = &self.points;
        let first = p.first()?;
        let j = p.partition_point(|q| q.beat <= beat);
        if j == 0 {
            return Some(first.value);
        }
        let a = p[j - 1];
        let Some(b) = p.get(j) else { return Some(a.value) };
        // b.beat > beat >= a.beat: o intervalo nunca é vazio
        let t = ((beat - a.beat) / (b.beat - a.beat)).clamp(0.0, 1.0) as f32;
        let shaped = if a.curve == 0.0 { t } else { t.powf((a.curve * 3.0).exp2()) };
        Some(a.value + (b.value - a.value) * shaped)
    }
}

/// O roteamento e os inserts de uma faixa.
struct Strip {
    chain: Chain,
    sends: Vec<Send>,
    /// Saída pedida pelo app: −1 master, senão o índice de um barramento.
    output: i32,
    /// Saída validada (−1 = master): só um barramento processado depois desta faixa.
    out_dst: i32,
    /// Cadeia parada: entrada calada e saída em silêncio há `chain.hold()` quadros.
    idle: bool,
    quiet: usize,
    /// Alguma cadeia usa esta faixa como chave de sidechain: a saída pós-inserts é guardada.
    is_key: bool,
    /// A chave guardada já foi zerada (a faixa está calada).
    key_silent: bool,
    /// PDC: atraso da fonte antes dos inserts (só faixas que não são barramento: a fonte precisa
    /// esperar quando a chave do sidechain dela vem de uma faixa de latência maior) e atraso da
    /// saída para o destino (master ou barramento).
    pre: Delay,
    out_line: Delay,
    /// PDC: quadros que a faixa segue rodando, com silêncio, depois que a fonte calou: o que está
    /// nos atrasos ainda precisa sair.
    flush: usize,
    /// PDC: a faixa tem som nos atrasos (desde que a fonte começou até esvaziarem). Fria, os
    /// atrasos estão vazios e uma mudança de latência pendente vale de uma vez, sem crossfade: o
    /// começo do áudio não pode chegar adiantado nem em fade só porque um efeito foi posto antes.
    warm: bool,
}

impl Strip {
    fn new(rate: f64, bpm: f64) -> Self {
        let mut chain = Chain::new(rate);
        chain.set_tempo(bpm);
        Self {
            chain,
            sends: Vec::with_capacity(MAX_SENDS),
            output: -1,
            out_dst: -1,
            idle: false,
            quiet: 0,
            is_key: false,
            key_silent: false,
            pre: Delay::new(),
            out_line: Delay::new(),
            flush: 0,
            warm: false,
        }
    }
}

/// Maior pico e se o bloco é todo finito (NaN ou infinito não entram no pico: `max` os ignora).
fn scan(l: &[f32], r: &[f32]) -> (f32, bool) {
    let mut peak = 0.0f32;
    let mut sum = 0.0f32;
    for &v in l.iter().chain(r) {
        peak = peak.max(v.abs());
        sum += v;
    }
    (peak, sum.is_finite())
}

/// Soma os envios pré (ou pós) fader da faixa `src` nos barramentos. `audible` é a faixa passar
/// pelo solo; um envio para um barramento solado (ou que alimenta um solado) segue mesmo com a
/// origem calada pelo solo, para o retorno solado soar com tudo o que chega nele.
#[allow(clippy::too_many_arguments)]
fn mix_sends(
    sends: &mut [Send],
    bufs: &mut [Stereo],
    incoming: &mut [bool],
    up: &[bool],
    audible: bool,
    src: usize,
    n: usize,
    pre: bool,
    k: f32,
    scratch: &mut Scratch,
) {
    for s in sends.iter_mut().filter(|s| s.pre == pre && s.dst >= 0) {
        let d = s.dst as usize;
        let on = audible || up[d];
        let Ok([from, to]) = bufs.get_disjoint_mut([src, d]) else { continue };
        if s.line.active() {
            // PDC: o envio chega ao destino junto com as outras entradas dele. A linha vê todo
            // bloco, mesmo com o nível em zero (senão guardaria som velho para quando o nível subir)
            let (dl, dr) = scratch.send_copy(&from.l[..n], &from.r[..n]);
            s.line.process(dl, dr);
            s.mix(dl, dr, &mut to.l[..n], &mut to.r[..n], on, k);
        } else {
            s.mix(&from.l[..n], &from.r[..n], &mut to.l[..n], &mut to.r[..n], on, k);
        }
        incoming[d] = true;
    }
}

/// O motor. Um por contexto de áudio.
pub struct Engine {
    rate: f64,
    /// Mapa de andamento (batida ↔ quadros) e de compassos (o metrônomo); ver [`tempo`].
    tempo: TempoMap,
    meter: MeterMap,
    /// O `beats_per_bar` do último `tempo`: o compasso a que `meter_clear` volta.
    beats_per_bar: u32,
    /// O mapa de compassos vem de `meter_point` (o app o reenvia sempre que muda): o `tempo`,
    /// reenviado a cada sincronização com o número de tempos arredondado, não mexe nele.
    meter_custom: bool,
    /// Posições musicais a preservar enquanto o app reenvia o mapa (`tempo_clear` + pontos): o
    /// transporte e o loop em batidas, lidas antes da primeira mudança do lote e reaplicadas a cada
    /// ponto. Vale até o próximo bloco.
    anchor: Option<[f64; 3]>,
    playing: bool,
    /// Posição do transporte em quadros.
    pos: f64,
    loop_on: bool,
    loop_start: f64,
    loop_end: f64,
    samples: HashMap<u32, Arc<Sample>>,
    clips: Vec<Clip>,
    /// Curva de fade (entrada, saída) de cada clipe de `clips`, em paralelo (ver [`fade_curve`]); zero = padrão.
    clip_shapes: Vec<(u8, u8)>,
    tracks: Vec<Track>,
    /// Paralelos a `tracks`: instrumento e notas, roteamento e inserts, o buffer de trabalho do
    /// bloco (o barramento acumula nele o que chega) e a última saída pós-inserts (chave de
    /// sidechain).
    lanes: Vec<Lane>,
    strips: Vec<Strip>,
    bufs: Vec<Stereo>,
    keys: Vec<Stereo>,
    /// Algo chegou no barramento neste bloco.
    incoming: Vec<bool>,
    /// Solo: `up` = solada ou alimenta pela saída uma solada; `aud` = passa pelo solo (`up` mais
    /// os barramentos que recebem de alguma dessas).
    up: Vec<bool>,
    aud: Vec<bool>,
    /// Ordem de processamento: faixas normais (as que servem de chave de sidechain antes das que
    /// as usam), depois os barramentos em ordem de índice. `rank` é a posição de cada faixa nela.
    order: Vec<usize>,
    rank: Vec<usize>,
    routing_dirty: bool,
    master: Track,
    master_fx: Chain,
    master_idle: bool,
    master_quiet: usize,
    limiter: limiter::Limiter,
    limiter_on: bool,
    /// Medidor de loudness do master (depois do limitador).
    loudness: loudness::Meter,
    metronome: Metronome,
    scratch: Scratch,
    /// Coeficiente de suavização dos envios (o mesmo dos canais).
    smooth: f32,
    /// Depois do stop, os clipes de áudio ainda soam por alguns quadros descendo a zero: quantos
    /// faltam, de quantos, e de que posição (quadros).
    tail: usize,
    tail_len: usize,
    tail_pos: f64,
    /// Notas mudaram desde o último bloco: reordenar antes de tocar.
    notes_dirty: bool,
    /// Reposicionar os cursores das notas na posição atual antes do próximo bloco.
    recue: bool,
    /// Lanes de automação: as `auto_count` primeiras valem; as outras são reaproveitadas (com os
    /// pontos já reservados) no próximo envio.
    auto: Vec<AutoLane>,
    auto_count: usize,
    /// Alvos das lanes apagadas pelo último `clear_automation`: os que não voltarem a ser
    /// automatizados retornam ao valor estático.
    auto_restore: Vec<Target>,
    /// A automação está aplicada (tocando): ao parar, tudo volta ao estático.
    auto_live: bool,
    /// Efeito observado (faixa, slot; slot −1 = nenhum) e faixa do analisador (−1 master, −2
    /// nenhuma).
    watch_fx: (i32, i32),
    watch_analyzer: i32,
    analyzer: Analyzer,
    /// Quadros processados desde o começo (ou desde o preparo do render): a grade das fatias.
    clock: u64,
    /// Entrada de áudio do bloco atual e quantos quadros dela valem (0 = o hospedeiro não entregou
    /// entrada neste bloco); `block_at` é onde a fatia sendo renderizada começa dentro do bloco do
    /// hospedeiro (para ler a entrada e escrever as capturas no lugar certo).
    input: Stereo,
    input_len: usize,
    block_at: usize,
    /// A faixa soou na fatia atual (as capturas de faixa calada saem em silêncio).
    sounded: Vec<bool>,
    recorder: NoteRecorder,
    captures: Captures,
    /// Latência do limitador de segurança do master (quadros), medida ao criar o motor.
    latency: usize,
    /// Quanto o transporte anda à frente do que sai (o adiantamento do render): [`Engine::beat`]
    /// informa a posição do que sai.
    out_delay: f64,
    /// Bloco de rascunho do preparo do render (saída descartada do adiantamento, silêncio para as
    /// cadeias do master).
    spare: Stereo,
    /// PDC: a latência dos efeitos mudou (ou o roteamento): recalcular os atrasos antes do próximo
    /// bloco.
    pdc_dirty: bool,
    /// PDC: latência com que todas as fontes chegam ao master (a maior entre as faixas que saem
    /// nele, em quadros) e a da cadeia de inserts do master, depois dele.
    pdc_total: usize,
    pdc_master: usize,
    /// PDC: por faixa, a latência do sinal na entrada da cadeia (`arrive`), na saída dela (`out`) e
    /// a maior que chega de fora (`inmax`, só barramentos).
    pdc_arrive: Vec<usize>,
    pdc_out: Vec<usize>,
    pdc_inmax: Vec<usize>,
    /// O clique do metrônomo entra depois da cadeia do master: atrasa `pdc_total + pdc_master`
    /// para soar junto das faixas (o limitador de segurança atrasa os dois igual). `metro_dirty`:
    /// o anel tem clique gravado (esvaziar antes de voltar a gravar).
    metro_delay: Delay,
    metro_dirty: bool,
    /// Quadros processados desde a criação (relógio do limite de frequência da PDC automatizada).
    frames_run: u64,
    /// A automação mexeu numa latência: recalcular a PDC quando o intervalo mínimo passar.
    pdc_auto_pending: bool,
    pdc_auto_last: u64,
    /// Quantas vezes a PDC foi recalculada (os testes conferem o limite de frequência).
    #[cfg(test)]
    pdc_runs: u32,
}

/// Latência do limitador de segurança em quadros, medida por um impulso (o lookahead é detalhe
/// dele; medir não deixa esta conta envelhecer se ele mudar).
fn limiter_latency(rate: f64) -> usize {
    let mut lim = limiter::Limiter::new(rate);
    let n = ((0.1 * rate) as usize).max(4096);
    let (mut l, mut r) = (vec![0.0f32; n], vec![0.0f32; n]);
    l[0] = 0.5;
    r[0] = 0.5;
    lim.process(&mut l, &mut r);
    l.iter().position(|&s| s != 0.0).unwrap_or(0)
}

impl Engine {
    pub fn new(rate: f64) -> Self {
        Self {
            rate,
            tempo: TempoMap::new(rate, 120.0),
            meter: MeterMap::new(4),
            beats_per_bar: 4,
            meter_custom: false,
            anchor: None,
            playing: false,
            pos: 0.0,
            loop_on: false,
            loop_start: 0.0,
            loop_end: 0.0,
            samples: HashMap::new(),
            clips: Vec::new(),
            clip_shapes: Vec::new(),
            tracks: Vec::new(),
            lanes: Vec::new(),
            strips: Vec::new(),
            bufs: Vec::new(),
            keys: Vec::new(),
            incoming: Vec::new(),
            up: Vec::new(),
            aud: Vec::new(),
            order: Vec::new(),
            rank: Vec::new(),
            routing_dirty: false,
            master: Track::new(rate),
            master_fx: Chain::new(rate),
            master_idle: false,
            master_quiet: 0,
            limiter: limiter::Limiter::new(rate),
            limiter_on: true,
            loudness: loudness::Meter::new(rate, 2),
            metronome: Metronome::default(),
            scratch: Scratch::new(CHUNK),
            smooth: mixer::smooth_coef(rate),
            tail: 0,
            tail_len: ((STOP_FADE_SECS * rate) as usize).max(1),
            tail_pos: 0.0,
            notes_dirty: false,
            recue: false,
            auto: Vec::new(),
            auto_count: 0,
            auto_restore: Vec::with_capacity(64),
            auto_live: false,
            watch_fx: (-1, -1),
            watch_analyzer: -2,
            analyzer: Analyzer::new(),
            clock: 0,
            input: Stereo::new(MAX_BLOCK),
            input_len: 0,
            block_at: 0,
            sounded: Vec::new(),
            recorder: NoteRecorder::new(),
            captures: Captures::new(),
            latency: limiter_latency(rate),
            out_delay: 0.0,
            spare: Stereo::new(CHUNK),
            pdc_dirty: false,
            pdc_total: 0,
            pdc_master: 0,
            pdc_arrive: Vec::new(),
            pdc_out: Vec::new(),
            pdc_inmax: Vec::new(),
            metro_delay: Delay::new(),
            metro_dirty: false,
            frames_run: 0,
            pdc_auto_pending: false,
            pdc_auto_last: 0,
            #[cfg(test)]
            pdc_runs: 0,
        }
    }

    pub fn rate(&self) -> f64 {
        self.rate
    }

    // ---------------------------------------------------------------- andamento e posição

    /// Muda o andamento inicial e o compasso (`beats_per_bar`/4, só quando o app não mandou mapa de
    /// compassos por `meter_point`: com mapa, quem manda nele é o mapa, e o `beats_per_bar` daqui
    /// só vale para o `meter_clear` seguinte).
    /// As notas e os fins das que soam estão em batidas: seguem o andamento novo sem mais nada. Os
    /// efeitos sincronizados (delay, tremolo, filtro) recebem o andamento inicial.
    pub fn set_tempo(&mut self, bpm: f64, beats_per_bar: u32) {
        // a posição musical fica onde estava: quem toca no tempo 9 continua no tempo 9
        let beat = self.transport_beat();
        let (ls, le) = (self.frames_to_beats(self.loop_start), self.frames_to_beats(self.loop_end));
        let old = self.tempo.bpm0();
        self.tempo.set_bpm0(bpm);
        self.beats_per_bar = beats_per_bar.clamp(1, 32);
        if !self.meter_custom {
            self.meter.set_initial(self.beats_per_bar);
        }
        self.pos = self.beats_to_frames(beat);
        self.loop_start = self.beats_to_frames(ls);
        self.loop_end = self.beats_to_frames(le);
        self.tempo_changed(old);
    }

    /// O app manda o andamento a cada sincronização: os efeitos só recebem quando muda.
    fn tempo_changed(&mut self, old_bpm0: f64) {
        let bpm = self.tempo.bpm0();
        if bpm != old_bpm0 {
            for s in &mut self.strips {
                s.chain.set_tempo(bpm);
            }
            self.master_fx.set_tempo(bpm);
        }
    }

    /// Zera o mapa de andamento para um ponto só (o andamento inicial de agora). A posição
    /// musical do transporte e do loop se mantém. O app manda `tempo_clear` e os pontos em
    /// seguida, no mesmo lote.
    pub fn tempo_clear(&mut self) {
        self.keep_anchor();
        let old = self.tempo.bpm0();
        self.tempo.clear(old);
        self.reanchor();
    }

    /// Põe um ponto no mapa de andamento (`ramp`: rampa linear até o ponto seguinte; senão salto).
    /// Fora de ordem entra no lugar, na mesma batida o último vale e a batida 0 é o andamento
    /// inicial; ver [`tempo::TempoMap::insert`].
    pub fn tempo_point(&mut self, beat: f64, bpm: f64, ramp: bool) {
        self.keep_anchor();
        let old = self.tempo.bpm0();
        self.tempo.insert(beat, bpm, ramp);
        self.reanchor();
        self.tempo_changed(old);
    }

    /// Volta o mapa de compassos a um compasso só (`beats_per_bar`/4, o do último `tempo`).
    pub fn meter_clear(&mut self) {
        self.meter_custom = false;
        self.meter.clear(self.beats_per_bar);
    }

    /// Mudança de compasso a partir do compasso `bar` (1 = o primeiro): `num`/`den`. O compasso
    /// muda onde o metrônomo põe o tempo forte e a cada quanto clica; a batida do documento segue
    /// sendo a semínima (6/8 dura 3 batidas).
    pub fn meter_point(&mut self, bar: u32, num: u32, den: u32) {
        self.meter_custom = true;
        self.meter.insert(bar, num, den);
    }

    /// Guarda a posição musical do transporte e do loop antes de o mapa mudar (uma vez por lote).
    fn keep_anchor(&mut self) {
        if self.anchor.is_none() {
            self.anchor = Some([self.transport_beat(), self.frames_to_beats(self.loop_start), self.frames_to_beats(self.loop_end)]);
        }
    }

    /// Refaz as posições em quadros a partir das batidas guardadas, no mapa de agora.
    fn reanchor(&mut self) {
        if let Some([beat, ls, le]) = self.anchor {
            self.pos = self.beats_to_frames(beat);
            self.loop_start = self.beats_to_frames(ls);
            self.loop_end = self.beats_to_frames(le);
        }
    }

    /// Batida → quadros pelo mapa de andamento.
    pub fn beats_to_frames(&self, beats: f64) -> f64 {
        self.tempo.to_frames(beats)
    }

    /// Quadros → batida pelo mapa de andamento.
    pub fn frames_to_beats(&self, frames: f64) -> f64 {
        self.tempo.to_beats(frames)
    }

    /// Posição do transporte em batidas: a do próximo quadro que sai. Só no render as duas diferem
    /// do transporte interno (adiantado da latência do limitador), e aqui vale a do que sai, para
    /// quem renderiza "até a batida X" parar no quadro certo.
    pub fn beat(&self) -> f64 {
        self.frames_to_beats((self.pos - self.out_delay).max(0.0))
    }

    /// Posição do transporte interno em batidas (automação, notas, andamento).
    fn transport_beat(&self) -> f64 {
        self.frames_to_beats(self.pos)
    }

    pub fn playing(&self) -> bool {
        self.playing
    }

    /// Toca a partir da posição atual. Notas que já tinham começado antes dela não soam.
    pub fn play(&mut self) {
        if !self.playing {
            self.playing = true;
            self.recue = true;
            self.tail = 0;
        }
    }

    /// Para. Os instrumentos soltam tudo com o release normal (as caudas continuam soando, e as
    /// dos efeitos também) e os clipes de áudio descem a zero num fade curto. A automação solta e
    /// valem de novo os valores estáticos.
    pub fn stop(&mut self) {
        if self.playing {
            self.tail = self.tail_len;
            self.tail_pos = self.pos;
            // parado não se grava: as teclas seguradas terminam onde o transporte parou
            self.recorder.close_all(self.transport_beat());
        }
        self.playing = false;
        self.silence_click();
        for lane in &mut self.lanes {
            lane.held.clear();
            if let Some(inst) = lane.instrument.as_mut() {
                inst.release_all();
            }
            lane.stop_cc();
        }
    }

    /// Corta o clique do metrônomo e o que ele guardava no atraso da PDC.
    fn silence_click(&mut self) {
        self.metronome.silence();
        if self.metro_dirty {
            self.metro_delay.clear();
            self.metro_dirty = false;
        }
    }

    /// Vai para uma posição; as notas do sequenciador que soavam são soltas.
    pub fn seek(&mut self, beat: f64) {
        let from = self.transport_beat();
        self.anchor = None;
        self.pos = self.beats_to_frames(beat.max(0.0));
        self.out_delay = 0.0;
        if self.playing {
            self.recorder.jump(from, self.transport_beat());
        }
        self.silence_click();
        for lane in &mut self.lanes {
            lane.release_held();
        }
        self.recue = true;
    }

    /// Loop entre duas posições em batidas; `end <= start` desliga.
    pub fn set_loop(&mut self, on: bool, start: f64, end: f64) {
        self.anchor = None;
        self.loop_on = on && end > start;
        self.loop_start = self.beats_to_frames(start.max(0.0));
        self.loop_end = self.beats_to_frames(end.max(0.0));
    }

    pub fn set_metronome(&mut self, on: bool, gain: f32) {
        self.metronome.on = on;
        self.metronome.gain = gain;
    }

    // ---------------------------------------------------------------- conteúdo

    /// Guarda um áudio. Faixas de sampler que já apontavam para `id` (o áudio chegou depois da
    /// escolha, ou foi recarregado) passam a tocá-lo.
    pub fn load_sample(&mut self, id: u32, sample: Sample) {
        let sample = Arc::new(sample);
        for lane in self.lanes.iter_mut().filter(|l| l.sample == id) {
            if let Some(inst) = lane.instrument.as_mut() {
                inst.set_sample(Some(sample.clone()));
            }
        }
        // as zonas do sampler citam áudios por id, em qualquer faixa
        for inst in self.lanes.iter_mut().filter_map(|l| l.instrument.as_mut()) {
            inst.zone_sample(id, Some(sample.clone()));
        }
        self.samples.insert(id, sample);
    }

    /// Esquece um áudio; os instrumentos que o tocavam ficam sem áudio (as vozes que soam
    /// terminam, o instrumento guarda a referência até lá).
    pub fn drop_sample(&mut self, id: u32) {
        self.samples.remove(&id);
        for lane in self.lanes.iter_mut().filter(|l| l.sample == id) {
            if let Some(inst) = lane.instrument.as_mut() {
                inst.set_sample(None);
            }
        }
        for inst in self.lanes.iter_mut().filter_map(|l| l.instrument.as_mut()) {
            inst.zone_sample(id, None);
        }
    }

    /// Número de faixas. Os buffers de cada faixa (trabalho e chave) são alocados aqui, nunca no
    /// `process`; faixas novas nascem sem efeitos, sem envios e saindo no master.
    pub fn set_track_count(&mut self, n: usize) {
        if n == self.tracks.len() {
            return;
        }
        let (rate, bpm) = (self.rate, self.tempo.bpm0());
        self.tracks.resize_with(n, || Track::new(rate));
        self.lanes.resize_with(n, Lane::new);
        self.strips.resize_with(n, || Strip::new(rate, bpm));
        self.bufs.resize_with(n, || Stereo::new(CHUNK));
        self.keys.resize_with(n, || Stereo::new(CHUNK));
        self.incoming.resize(n, false);
        self.sounded.resize(n, false);
        self.up.resize(n, false);
        self.aud.resize(n, true);
        self.rank.resize(n, usize::MAX);
        self.pdc_arrive.resize(n, 0);
        self.pdc_out.resize(n, 0);
        self.pdc_inmax.resize(n, 0);
        self.order.reserve(n.saturating_sub(self.order.len()));
        self.routing_dirty = true;
    }

    pub fn track_mut(&mut self, i: usize) -> Option<&mut Track> {
        self.tracks.get_mut(i)
    }

    pub fn tracks(&self) -> &[Track] {
        &self.tracks
    }

    /// Liga o limitador de segurança do master (ligado por padrão; os testes que medem amostras em
    /// quadros exatos desligam, por causa do atraso do lookahead).
    pub fn set_limiter(&mut self, on: bool) {
        self.limiter_on = on;
    }

    /// Menor ganho do limitador desde a última leitura (1 = não reduziu).
    pub fn take_limiter_gain(&mut self) -> f32 {
        self.limiter.take_min_gain()
    }

    pub fn master_mut(&mut self) -> &mut Track {
        &mut self.master
    }

    pub fn master(&self) -> &Track {
        &self.master
    }

    pub fn clear_clips(&mut self) {
        self.clips.clear();
        self.clip_shapes.clear();
    }

    pub fn add_clip(&mut self, clip: Clip) {
        self.clips.push(clip);
        self.clip_shapes.push((0, 0));
    }

    /// Curvas de fade do ÚLTIMO clipe acrescentado por `add_clip`: entrada e saída, cada uma um dos
    /// `FADE_*` (valor desconhecido vale [`FADE_DEFAULT`]). Sem clipe, não faz nada. É relativa ao
    /// último clipe (e não a um índice) para sobreviver a quem filtra a lista de chamadas, como o
    /// render offline, que descarta clipes depois do fim.
    pub fn set_clip_fade_shape(&mut self, fade_in: u32, fade_out: u32) {
        if let Some(s) = self.clip_shapes.last_mut() {
            *s = (fade_in.min(255) as u8, fade_out.min(255) as u8);
        }
    }

    // ---------------------------------------------------------------- instrumentos e notas

    /// Tipo da faixa ([`instrument::kind`]). Só faz algo quando o tipo muda: aí o instrumento
    /// antigo é descartado e o novo nasce nos padrões (os parâmetros vêm depois, por
    /// [`Engine::set_param`]). Criar e destruir o instrumento aloca e libera memória na thread de
    /// áudio; é aceitável porque só acontece ao criar a faixa ou mudar o tipo dela (o app manda o
    /// tipo a cada sync, mas o mesmo tipo de novo não faz nada), nunca a cada bloco.
    pub fn set_track_kind(&mut self, i: usize, kind: u32) {
        let Some(lane) = self.lanes.get_mut(i) else { return };
        if lane.kind == kind {
            return;
        }
        // virar ou deixar de ser barramento muda a ordem de processamento
        self.routing_dirty |= lane.kind == instrument::kind::BUS || kind == instrument::kind::BUS;
        lane.kind = kind;
        lane.held.clear();
        lane.statics = [f32::NAN; STATIC_PARAMS];
        lane.expr = expression::ExprState::new(kind);
        self.recue = true;
        lane.instrument = instrument::create(kind, self.rate);
        if let Some(inst) = lane.instrument.as_mut()
            && lane.sample != 0
        {
            inst.set_sample(self.samples.get(&lane.sample).cloned());
        }
    }

    /// Tipo atual da faixa.
    pub fn track_kind(&self, i: usize) -> Option<u32> {
        self.lanes.get(i).map(|l| l.kind)
    }

    /// Parâmetro do instrumento da faixa, na unidade da tabela. Com a automação tocando esse
    /// parâmetro, o valor fica guardado como o estático (vale ao parar) e a automação segue no
    /// comando.
    pub fn set_param(&mut self, i: usize, id: u32, value: f32) {
        if !value.is_finite() {
            return;
        }
        let automated = self.automated(Target::new(i as i32, effect::auto_target::INSTRUMENT, 0, id));
        let Some(lane) = self.lanes.get_mut(i) else { return };
        if let Some(s) = lane.statics.get_mut(id as usize) {
            *s = value;
        }
        if automated {
            return;
        }
        if let Some(inst) = lane.instrument.as_mut() {
            inst.set_param(id, value);
        }
    }

    /// O áudio (id de [`Engine::load_sample`], 0 = nenhum) que o instrumento da faixa toca. Um id
    /// ainda não carregado fica guardado e é ligado quando o áudio chegar.
    pub fn set_instrument_sample(&mut self, i: usize, sample: u32) {
        let Some(lane) = self.lanes.get_mut(i) else { return };
        lane.sample = sample;
        if let Some(inst) = lane.instrument.as_mut() {
            inst.set_sample(if sample == 0 { None } else { self.samples.get(&sample).cloned() });
        }
    }

    /// Apaga as zonas do sampler da faixa (volta a ser o de sample único). As notas que soam
    /// terminam: cada voz guarda o trecho e o áudio da zona que a disparou.
    pub fn clear_zones(&mut self, i: usize) {
        if let Some(inst) = self.lanes.get_mut(i).and_then(|l| l.instrument.as_mut()) {
            inst.zones_clear();
        }
    }

    /// Acrescenta uma zona ao sampler da faixa; `sample` é o id de [`Engine::load_sample`] (pode
    /// vir antes do áudio chegar). Em faixa que não é de sampler não faz nada.
    pub fn add_zone(&mut self, i: usize, sample: u32, def: sampler::ZoneDef) {
        let audio = self.samples.get(&sample).cloned();
        if let Some(inst) = self.lanes.get_mut(i).and_then(|l| l.instrument.as_mut()) {
            inst.zone_add(def, sample, audio);
        }
    }

    /// Apaga as notas do sequenciador de todas as faixas. As que soam agora terminam no fim
    /// delas (o conjunto das que soam é do motor, não da lista).
    pub fn clear_notes(&mut self) {
        for lane in &mut self.lanes {
            lane.notes.clear();
        }
        self.notes_dirty = true;
    }

    /// Nota do sequenciador: início e duração em batidas absolutas da linha do tempo, altura MIDI
    /// 0..=127 e velocidade 0..=1. Nota vazia, fora da faixa de alturas ou com número inválido é
    /// ignorada.
    pub fn add_note(&mut self, track: usize, start: f64, length: f64, pitch: u32, velocity: f32) {
        let Some(lane) = self.lanes.get_mut(track) else { return };
        if pitch > 127 || !start.is_finite() || !(length > 0.0 && length.is_finite()) {
            return;
        }
        let start = start.max(0.0);
        let velocity = if velocity.is_finite() { velocity.clamp(0.0, 1.0) } else { 0.8 };
        lane.notes.push(Note { start, end: start + length, pitch: pitch as u8, velocity });
        self.notes_dirty = true;
    }

    /// Toca uma nota na hora, fora do sequenciador (teclado, MIDI, prévia do editor): não depende
    /// do transporte e não é solta por seek nem pela volta do loop. Velocidade 0 é note off, como
    /// no MIDI. Gravando e tocando, entra no registro com a batida de agora: os comandos chegam
    /// entre um bloco e outro, então é o quadro em que o instrumento começa a nota.
    pub fn live_on(&mut self, track: usize, pitch: u32, velocity: f32) {
        if velocity.is_nan() || velocity <= 0.0 {
            self.live_off(track, pitch);
            return;
        }
        if pitch > 127 || track >= self.lanes.len() {
            return;
        }
        let velocity = velocity.min(1.0);
        if self.playing {
            self.recorder.note_on(track as u32, pitch as u8, velocity, self.transport_beat());
        }
        self.lanes[track].live_note_on(pitch as u8, velocity);
    }

    pub fn live_off(&mut self, track: usize, pitch: u32) {
        if pitch > 127 || track >= self.lanes.len() {
            return;
        }
        if self.playing {
            self.recorder.note_off(track as u32, pitch as u8, self.transport_beat());
        }
        self.lanes[track].live_note_off(pitch as u8);
    }

    /// Pânico: corta na hora todo som de instrumento (notas presas, caudas), as caudas dos efeitos
    /// e o metrônomo. O transporte segue como estava.
    pub fn panic(&mut self) {
        self.silence_click();
        for lane in &mut self.lanes {
            lane.held.clear();
            if let Some(inst) = lane.instrument.as_mut() {
                inst.silence();
            }
            lane.panic_cc();
        }
        for s in &mut self.strips {
            s.chain.reset();
            // o que os atrasos da PDC guardam também é cauda
            s.pre.snap();
            s.out_line.snap();
            for send in &mut s.sends {
                send.line.snap();
            }
            s.chain.snap_delays();
        }
        self.master_fx.reset();
        self.master_fx.snap_delays();
    }

    // ---------------------------------------------------------------- efeitos

    fn chain_mut(&mut self, track: i32) -> Option<&mut Chain> {
        match track {
            -1 => Some(&mut self.master_fx),
            t if t >= 0 => self.strips.get_mut(t as usize).map(|s| &mut s.chain),
            _ => None,
        }
    }

    fn chain(&self, track: i32) -> Option<&Chain> {
        match track {
            -1 => Some(&self.master_fx),
            t if t >= 0 => self.strips.get(t as usize).map(|s| &s.chain),
            _ => None,
        }
    }

    /// Quantos slots de efeito a faixa (−1 = master) tem, até [`MAX_SLOTS`]. Os que sobram saem
    /// em fade; os novos nascem vazios.
    pub fn set_fx_count(&mut self, track: i32, n: usize) {
        if let Some(c) = self.chain_mut(track)
            && c.set_count(n)
        {
            self.routing_dirty = true;
        }
    }

    /// Tipo do efeito num slot ([`effect::kind`], 0 esvazia). O mesmo tipo de novo não faz nada;
    /// outro tipo cria o efeito nos padrões, então vem antes dos [`Engine::set_fx_param`]. Criar
    /// aloca (buffers de atraso no tamanho máximo), o que é aceitável porque só acontece quando o
    /// usuário põe ou troca um efeito. A troca é por crossfade curto, sem estalo.
    pub fn set_fx(&mut self, track: i32, slot: usize, kind: u32) {
        if let Some(c) = self.chain_mut(track)
            && c.set_kind(slot, kind)
        {
            self.routing_dirty = true;
        }
    }

    /// Parâmetro de um efeito, na unidade da tabela. A faixa-chave do sidechain (compressor e
    /// gate) é interceptada aqui (o motor entrega a chave) e também repassada ao efeito. Com a
    /// automação tocando esse parâmetro, o valor só fica guardado como o estático.
    pub fn set_fx_param(&mut self, track: i32, slot: usize, id: u32, value: f32) {
        let automated = self.automated(Target::new(track, effect::auto_target::EFFECT, slot as u32, id));
        if let Some(c) = self.chain_mut(track)
            && c.set_param(slot, id, value, true, !automated)
        {
            self.routing_dirty = true;
        }
        // o lookahead do limitador é latência
        if id == effect::limiter_param::LOOKAHEAD {
            self.pdc_dirty = true;
        }
    }

    /// Bypass de um efeito, por crossfade.
    pub fn set_fx_bypass(&mut self, track: i32, slot: usize, on: bool) {
        if let Some(c) = self.chain_mut(track) {
            c.set_bypass(slot, on);
        }
    }

    // ---------------------------------------------------------------- roteamento

    /// Quantos envios a faixa tem, até [`MAX_SENDS`]; os novos nascem sem destino.
    pub fn set_sends_count(&mut self, track: usize, n: usize) {
        let Some(s) = self.strips.get_mut(track) else { return };
        let n = n.min(MAX_SENDS);
        if n != s.sends.len() {
            s.sends.resize_with(n, Send::default);
            self.routing_dirty = true;
        }
    }

    /// Envio `index` da faixa para o barramento `bus` (índice da faixa), com nível em ganho linear,
    /// antes (`pre`) ou depois do fader. Um destino que não seja barramento, ou que seja processado
    /// antes da origem (barramento só envia para barramento de índice maior), é ignorado.
    /// Um índice além do fim estica a lista até ele (o app pode mandar o envio antes da contagem).
    pub fn set_send(&mut self, track: usize, index: usize, bus: i32, level: f32, pre: bool) {
        let Some(strip) = self.strips.get_mut(track) else { return };
        if index >= MAX_SENDS {
            return;
        }
        if index >= strip.sends.len() {
            strip.sends.resize_with(index + 1, Send::default);
            self.routing_dirty = true;
        }
        let send = &mut strip.sends[index];
        if send.bus != bus {
            send.retarget(bus);
            self.routing_dirty = true;
        }
        if level.is_finite() {
            send.level = level.max(0.0);
        }
        send.pre = pre;
    }

    /// Saída da faixa: −1 master, senão o índice de um barramento processado depois dela (um
    /// destino inválido vale como master).
    pub fn set_output(&mut self, track: usize, target: i32) {
        if let Some(s) = self.strips.get_mut(track)
            && s.output != target
        {
            s.output = target;
            self.routing_dirty = true;
        }
    }

    /// Refaz a ordem de processamento, as chaves de sidechain e os destinos validados. Só quando
    /// algo do roteamento mudou, entre um bloco e outro.
    fn route(&mut self) {
        self.routing_dirty = false;
        self.pdc_dirty = true;
        let n = self.tracks.len();
        let is_bus = |lanes: &[Lane], t: usize| lanes[t].kind == instrument::kind::BUS;
        // faixas que servem de chave (usa `up` como rascunho: o solo o refaz a cada bloco)
        self.up.fill(false);
        for t in 0..n {
            for k in self.strips[t].chain.keys() {
                if k < n && k != t {
                    self.up[k] = true;
                }
            }
        }
        for k in self.master_fx.keys() {
            if k < n {
                self.up[k] = true;
            }
        }
        for (s, &key) in self.strips.iter_mut().zip(&self.up) {
            if s.is_key != key {
                s.is_key = key;
                s.key_silent = false;
            }
        }
        // faixas normais: a chave antes de quem a usa, para a chave ser do mesmo bloco; num ciclo
        // (A é chave de B e B de A) uma delas fica com a chave do bloco anterior
        self.order.clear();
        self.rank.fill(usize::MAX);
        loop {
            let mut waiting = None;
            let mut placed = false;
            for t in 0..n {
                if is_bus(&self.lanes, t) || self.rank[t] != usize::MAX {
                    continue;
                }
                let ready = self.strips[t].chain.keys().all(|k| k >= n || k == t || is_bus(&self.lanes, k) || self.rank[k] != usize::MAX);
                if ready {
                    self.rank[t] = self.order.len();
                    self.order.push(t);
                    placed = true;
                } else if waiting.is_none() {
                    waiting = Some(t);
                }
            }
            match (waiting, placed) {
                (None, _) => break,
                (Some(_), true) => {}
                (Some(t), false) => {
                    self.rank[t] = self.order.len();
                    self.order.push(t);
                }
            }
        }
        // barramentos em ordem de índice: recebem de todas as normais e dos barramentos antes deles
        for t in 0..n {
            if is_bus(&self.lanes, t) {
                self.rank[t] = self.order.len();
                self.order.push(t);
            }
        }
        for t in 0..n {
            let valid = |b: i32| {
                let ok = b >= 0 && (b as usize) < n && b as usize != t && is_bus(&self.lanes, b as usize) && self.rank[b as usize] > self.rank[t];
                if ok { b } else { -1 }
            };
            let out = valid(self.strips[t].output);
            let strip = &mut self.strips[t];
            strip.out_dst = out;
            for s in &mut strip.sends {
                s.dst = valid(s.bus);
            }
        }
    }

    /// Compensação de latência dos efeitos (PDC). Cada efeito com latência (limitador, distorção)
    /// atrasa o sinal que passa por ele; sem compensação a faixa com efeito soaria atrasada das
    /// outras, e envios e retornos somariam versões desalinhadas (filtro de pente). Aqui o grafo
    /// (faixas → barramentos → master, envios pré e pós, sidechain) ganha atrasos que alinham tudo
    /// à maior latência:
    ///
    /// - `arrive[t]`: latência do sinal na entrada da cadeia de `t`. Uma faixa-fonte nasce em 0; um
    ///   barramento recebe a maior `out` entre as entradas dele; uma cadeia com sidechain nunca
    ///   deixa a chave chegar depois do sinal do slot que a usa (aí a fonte espera: `pre`).
    /// - `out[t] = arrive[t]` mais a latência dos inserts.
    /// - Cada aresta (saída ou envio) de `t` para `d` ganha o atraso `arrive[d] − out[t]`, então
    ///   todas as entradas de um nó chegam juntas. Os atrasos são todos ≥ 0 e a latência total é
    ///   a chegada ao master: a maior de todas.
    /// - A chave do sidechain é atrasada até o sinal do slot que a usa.
    ///
    /// Roda entre um bloco e outro quando o roteamento ou uma latência mudou (efeito posto,
    /// trocado, tirado, lookahead novo): é aí que os atrasos podem crescer (alocar). Bypass não
    /// muda nada: a latência do efeito conta ligado ou não. Os atrasos mudam por crossfade curto.
    /// Uma faixa que só chega em outro barramento (ciclo de sidechain) não conta a chave.
    fn pdc_update(&mut self) {
        self.pdc_dirty = false;
        #[cfg(test)]
        {
            self.pdc_runs += 1;
        }
        let n = self.tracks.len();
        let cap = self.rate as usize;
        let fade = (mixer::FADE_SECS * self.rate) as usize;
        for s in &mut self.strips {
            s.chain.refresh_latency(cap);
        }
        self.master_fx.refresh_latency(cap);
        self.pdc_inmax[..n].fill(0);
        let mut master_in = 0;
        for oi in 0..self.order.len() {
            let t = self.order[oi];
            let rank = &self.rank;
            let known = |k: usize| rank[k] < rank[t];
            let strip = &self.strips[t];
            let base = if self.lanes[t].kind == instrument::kind::BUS { self.pdc_inmax[t] } else { 0 };
            let arrive = base.max(strip.chain.key_need(t, &self.pdc_out[..n], known)).min(cap);
            let out = (arrive + strip.chain.latency()).min(cap);
            self.pdc_arrive[t] = arrive;
            self.pdc_out[t] = out;
            if strip.out_dst >= 0 {
                let d = strip.out_dst as usize;
                self.pdc_inmax[d] = self.pdc_inmax[d].max(out);
            } else {
                master_in = master_in.max(out);
            }
            for s in strip.sends.iter().filter(|s| s.dst >= 0) {
                let d = s.dst as usize;
                self.pdc_inmax[d] = self.pdc_inmax[d].max(out);
            }
        }
        let arrive_master = master_in.max(self.master_fx.key_need(usize::MAX, &self.pdc_out[..n], |_| true)).min(cap);
        self.pdc_total = arrive_master;
        self.pdc_master = self.master_fx.latency();
        self.metro_delay.set_target(self.pdc_total + self.pdc_master, fade);
        for t in 0..n {
            let (arrive, out) = (self.pdc_arrive[t], self.pdc_out[t]);
            let rank = &self.rank;
            let known = |k: usize| rank[k] < rank[t];
            let bus = self.lanes[t].kind == instrument::kind::BUS;
            let strip = &mut self.strips[t];
            strip.pre.set_target(if bus { 0 } else { arrive }, fade);
            let to = if strip.out_dst >= 0 { self.pdc_arrive[strip.out_dst as usize] } else { arrive_master };
            strip.out_line.set_target(to.saturating_sub(out), fade);
            for s in &mut strip.sends {
                let to = if s.dst >= 0 { self.pdc_arrive[s.dst as usize] } else { out };
                s.line.set_target(to.saturating_sub(out), fade);
            }
            strip.chain.set_key_delays(arrive, t, &self.pdc_out[..n], known);
        }
        self.master_fx.set_key_delays(arrive_master, usize::MAX, &self.pdc_out[..n], |_| true);
    }

    /// Latência total do motor em quadros: a com que todas as fontes chegam ao master (PDC), mais a
    /// cadeia de inserts do master e o limitador de segurança. É quanto o som sai depois do que o
    /// transporte toca, e quanto o começo de um render offline descarta.
    pub fn latency_frames(&mut self) -> usize {
        self.refresh();
        self.pdc_total + self.pdc_master + if self.limiter_on { self.latency } else { 0 }
    }

    /// Só a parte da PDC (efeitos de faixas e barramentos), em quadros.
    pub fn pdc_latency(&mut self) -> usize {
        self.refresh();
        self.pdc_total
    }

    /// Põe em dia o roteamento e a PDC logo depois de um comando: os atrasos que crescem alocam
    /// aqui, no comando (que já pode alocar, como o `set_fx`), e não no `process` seguinte.
    pub fn settle(&mut self) {
        self.refresh();
    }

    /// Põe em dia o roteamento e a PDC (o `process` faz isso a cada bloco; quem consulta a latência
    /// logo depois de um comando também).
    fn refresh(&mut self) {
        if self.routing_dirty {
            self.route();
        }
        if self.pdc_dirty {
            self.pdc_update();
        }
    }

    /// Solo com barramentos: uma faixa solada mantém audível o que recebe dela (a saída e os
    /// envios, em cadeia) e um barramento solado mantém audível o que sai nele.
    fn solo(&mut self) {
        if !self.tracks.iter().any(|t| t.solo) {
            self.aud.fill(true);
            self.up.fill(false);
            return;
        }
        for (u, t) in self.up.iter_mut().zip(&self.tracks) {
            *u = t.solo;
        }
        // subindo: quem sai num solado (a saída vai sempre para alguém depois na ordem)
        for oi in (0..self.order.len()).rev() {
            let t = self.order[oi];
            let d = self.strips[t].out_dst;
            if d >= 0 && self.up[d as usize] {
                self.up[t] = true;
            }
        }
        self.aud.copy_from_slice(&self.up);
        // descendo: o que recebe de quem toca
        for oi in 0..self.order.len() {
            let t = self.order[oi];
            if !self.aud[t] {
                continue;
            }
            let s = &self.strips[t];
            if s.out_dst >= 0 {
                self.aud[s.out_dst as usize] = true;
            }
            for send in s.sends.iter().filter(|s| s.dst >= 0) {
                self.aud[send.dst as usize] = true;
            }
        }
    }

    // ---------------------------------------------------------------- automação

    /// Apaga todas as lanes (antes de reenviá-las). Os alvos que não voltarem a ser automatizados
    /// retornam ao valor estático no próximo bloco; os que voltarem seguem sem degrau.
    pub fn clear_automation(&mut self) {
        for lane in &mut self.auto[..self.auto_count] {
            self.auto_restore.push(lane.target);
            lane.points.clear();
        }
        self.auto_count = 0;
    }

    /// Nova lane: faixa (−1 master), alvo ([`effect::auto_target`]), slot (efeito ou índice do
    /// envio) e id do parâmetro. Devolve o índice para [`Engine::add_point`].
    pub fn add_lane(&mut self, track: i32, target: u32, slot: u32, id: u32) -> u32 {
        if self.auto_count == self.auto.len() {
            self.auto.push(AutoLane::new());
        }
        let lane = &mut self.auto[self.auto_count];
        lane.target = Target::new(track, target, slot, id);
        lane.points.clear();
        lane.last = f32::NAN;
        self.auto_count += 1;
        (self.auto_count - 1) as u32
    }

    /// Ponto numa lane: batida absoluta, valor na unidade do alvo (ganho linear no volume e nos
    /// envios, −1..1 no pan, a unidade da tabela nos parâmetros) e curva até o próximo.
    pub fn add_point(&mut self, lane: u32, beat: f64, value: f32, curve: f32) {
        if !beat.is_finite() || !value.is_finite() {
            return;
        }
        let Some(lane) = self.auto[..self.auto_count].get_mut(lane as usize) else { return };
        let beat = beat.max(0.0);
        let curve = if curve.is_finite() { curve.clamp(-1.0, 1.0) } else { 0.0 };
        // chegam em ordem quase sempre: a inserção vira um push
        let at = lane.points.partition_point(|p| p.beat <= beat);
        lane.points.insert(at, AutoPoint { beat, value, curve });
    }

    /// O alvo está sob automação agora (tocando, com pontos)?
    fn automated(&self, t: Target) -> bool {
        self.playing && self.auto[..self.auto_count].iter().any(|l| l.target == t && !l.points.is_empty())
    }

    /// Avalia as lanes na posição atual e aplica; parado, devolve tudo ao estático.
    fn automate(&mut self) {
        if !self.auto_restore.is_empty() {
            for i in 0..self.auto_restore.len() {
                let t = self.auto_restore[i];
                if !self.automated(t) {
                    self.restore(t);
                }
            }
            self.auto_restore.clear();
        }
        if !self.playing {
            if self.auto_live {
                self.auto_live = false;
                for i in 0..self.auto_count {
                    let t = self.auto[i].target;
                    self.restore(t);
                }
            }
            return;
        }
        let beat = self.transport_beat();
        for i in 0..self.auto_count {
            let lane = &mut self.auto[i];
            let Some(v) = lane.value_at(beat) else { continue };
            let changed = v != lane.last;
            lane.last = v;
            let t = lane.target;
            self.apply_auto(t, v, changed);
        }
        self.auto_live = self.auto_count > 0;
    }

    fn channel_mut(&mut self, track: i32) -> Option<&mut Track> {
        match track {
            -1 => Some(&mut self.master),
            t if t >= 0 => self.tracks.get_mut(t as usize),
            _ => None,
        }
    }

    fn apply_auto(&mut self, t: Target, v: f32, changed: bool) {
        use effect::auto_target as at;
        match t.kind {
            at::VOLUME => {
                if let Some(ch) = self.channel_mut(t.track) {
                    ch.auto_gain = Some(v.max(0.0));
                }
            }
            at::PAN => {
                if let Some(ch) = self.channel_mut(t.track) {
                    ch.auto_pan = Some(v.clamp(-1.0, 1.0));
                }
            }
            at::INSTRUMENT if changed && t.track >= 0 => {
                if let Some(inst) = self.lanes.get_mut(t.track as usize).and_then(|l| l.instrument.as_mut()) {
                    inst.set_param(t.id, v);
                }
            }
            at::EFFECT if changed => {
                // um parâmetro que mexe na latência (lookahead do limitador) deixa a PDC velha
                let stale = self.chain_mut(t.track).is_some_and(|c| {
                    c.set_param(t.slot as usize, t.id, v, false, true);
                    c.latency_stale(t.slot as usize)
                });
                self.pdc_auto_pending |= stale;
            }
            at::SEND if t.track >= 0 => {
                if let Some(s) = self.strips.get_mut(t.track as usize).and_then(|s| s.sends.get_mut(t.slot as usize)) {
                    s.auto_level = Some(v.max(0.0));
                }
            }
            _ => {}
        }
    }

    /// Devolve o alvo ao último valor estático que o app mandou.
    fn restore(&mut self, t: Target) {
        use effect::auto_target as at;
        for lane in self.auto[..self.auto_count].iter_mut().filter(|l| l.target == t) {
            lane.last = f32::NAN;
        }
        match t.kind {
            at::VOLUME => {
                if let Some(ch) = self.channel_mut(t.track) {
                    ch.auto_gain = None;
                }
            }
            at::PAN => {
                if let Some(ch) = self.channel_mut(t.track) {
                    ch.auto_pan = None;
                }
            }
            at::INSTRUMENT if t.track >= 0 => {
                if let Some(lane) = self.lanes.get_mut(t.track as usize)
                    && let Some(&v) = lane.statics.get(t.id as usize)
                    && !v.is_nan()
                    && let Some(inst) = lane.instrument.as_mut()
                {
                    inst.set_param(t.id, v);
                }
            }
            at::EFFECT => {
                let stale = self.chain_mut(t.track).is_some_and(|c| {
                    c.restore_param(t.slot as usize, t.id);
                    c.latency_stale(t.slot as usize)
                });
                self.pdc_auto_pending |= stale;
            }
            at::SEND if t.track >= 0 => {
                if let Some(s) = self.strips.get_mut(t.track as usize).and_then(|s| s.sends.get_mut(t.slot as usize)) {
                    s.auto_level = None;
                }
            }
            _ => {}
        }
    }

    // ---------------------------------------------------------------- medição

    /// Efeito cujo indicador ([`Effect::meter`](effect::Effect::meter)) vai em
    /// [`Engine::fx_meter`]; slot −1 desliga.
    pub fn watch_fx(&mut self, track: i32, slot: i32) {
        self.watch_fx = (track, slot);
    }

    /// Indicador do efeito observado (redução de ganho em dB na dinâmica); 0 se nenhum.
    pub fn fx_meter(&self) -> f32 {
        let (track, slot) = self.watch_fx;
        if slot < 0 {
            return 0.0;
        }
        self.chain(track).map_or(0.0, |c| c.meter(slot as usize))
    }

    /// Faixa cuja saída pós-fader vai para o analisador (−1 master, depois do limitador; −2
    /// desliga). Trocar esquece o que o anel tinha.
    pub fn watch_analyzer(&mut self, track: i32) {
        let track = track.max(-2);
        if track != self.watch_analyzer {
            self.watch_analyzer = track;
            self.analyzer.clear();
        }
    }

    /// Espectro da faixa observada em `out` (dB, −120..0, faixas lineares de 0 à metade da taxa);
    /// devolve quantas faixas escreveu (0 sem faixa observada).
    pub fn analyzer(&mut self, out: &mut [f32]) -> usize {
        if self.watch_analyzer < -1 { 0 } else { self.analyzer.spectrum(out) }
    }

    // ---------------------------------------------------------------- entrada, gravação e render

    /// Entrada de áudio do próximo bloco (até [`MAX_BLOCK`] quadros; `right` `None` = mono, vale
    /// nos dois lados). Vale só para o `process` seguinte: bloco sem entrega não tem entrada (o
    /// microfone foi fechado ou desconectado e nada fica repetindo). Amostra inválida vira
    /// silêncio, para não chegar NaN às cadeias.
    pub fn set_input(&mut self, left: &[f32], right: Option<&[f32]>) {
        let right = right.unwrap_or(left);
        let n = left.len().min(right.len()).min(MAX_BLOCK);
        let clean = |s: f32| if s.is_finite() { s } else { 0.0 };
        for (d, &s) in self.input.l[..n].iter_mut().zip(&left[..n]) {
            *d = clean(s);
        }
        for (d, &s) in self.input.r[..n].iter_mut().zip(&right[..n]) {
            *d = clean(s);
        }
        self.input_len = n;
    }

    /// Monitoramento da entrada na faixa: a entrada soma no buffer dela antes dos inserts e passa
    /// pela cadeia, pelo fader (mudo, solo, pan) e pelo roteamento como qualquer som da faixa. Só
    /// faixas de áudio monitoram.
    pub fn set_monitor(&mut self, track: usize, on: bool) {
        if let Some(lane) = self.lanes.get_mut(track) {
            lane.monitor = on;
        }
    }

    /// Começa a registrar as notas ao vivo (do zero), com a batida exata em que cada uma foi
    /// aplicada; só entram as tocadas com o transporte andando.
    pub fn rec_notes_start(&mut self) {
        self.recorder.start();
    }

    /// Para de registrar; as teclas ainda seguradas terminam na posição de agora.
    pub fn rec_notes_stop(&mut self) {
        let beat = self.transport_beat();
        self.recorder.stop(beat);
    }

    /// Escreve as notas registradas em grupos de 5 floats (faixa, altura, início e fim em batidas,
    /// velocidade); nota ainda segurada termina na posição atual. As escritas saem do registro (com
    /// espaço para todas, ele fica vazio). Devolve quantos floats escreveu.
    pub fn rec_notes(&mut self, out: &mut [f32]) -> usize {
        let beat = self.transport_beat();
        self.recorder.drain(out, beat)
    }

    /// Notas descartadas por falta de espaço na gravação atual (o registro guarda
    /// [`record::MAX_REC_NOTES`]).
    pub fn rec_notes_dropped(&self) -> usize {
        self.recorder.dropped()
    }

    /// Esquece as capturas. O próximo `process` com capturas prepara o render de novo.
    pub fn capture_clear(&mut self) {
        self.captures.clear();
        self.out_delay = 0.0;
    }

    /// Passa a capturar, a cada bloco, a saída pós-fader da faixa `track` (a mesma posição dos
    /// medidores: depois do volume, do pan, do mudo e da porta do solo) ou, com −1, a do master
    /// depois do limitador (exatamente o que o `process` devolve). Devolve o índice para
    /// [`Engine::captured`], ou −1 sem lugar (até [`record::MAX_CAPTURES`]) ou faixa inválida. Uma
    /// faixa que ainda não existe captura silêncio até existir. Com captura, o hospedeiro processa
    /// blocos de até [`MAX_BLOCK`] quadros. As capturas são montadas antes do render começar: mexer
    /// nelas faz o próximo `process` preparar o render de novo.
    pub fn capture_add(&mut self, track: i32) -> i32 {
        self.captures.add(track, self.latency)
    }

    /// O que a captura `index` soltou no último bloco processado, em `left`/`right`; além do bloco
    /// (ou com índice inválido) sai silêncio. Devolve quantos quadros eram do bloco.
    pub fn captured(&self, index: usize, left: &mut [f32], right: &mut [f32]) -> usize {
        self.captures.read(index, left, right)
    }

    /// Primeiro bloco de um render. Um motor recém-criado ainda faria transições que tocando ao
    /// vivo acontecem longe de qualquer som (efeitos entrando em crossfade do seco, envios subindo
    /// do zero, o fader indo ao valor da automação): aqui elas terminam no silêncio, com o
    /// transporte parado no lugar. Depois o transporte é adiantado da latência do limitador do
    /// master, com a saída descartada e as faixas capturadas esperando o mesmo tanto, para o
    /// primeiro quadro de toda captura ser o da posição de partida.
    fn start_render(&mut self) {
        self.captures.pending = false;
        self.clock = 0;
        // PDC: os atrasos começam vazios e já no valor certo (o render não tem passado)
        for s in &mut self.strips {
            s.pre.snap();
            s.out_line.snap();
            s.flush = 0;
            s.warm = false;
            for send in &mut s.sends {
                send.line.snap();
            }
            s.chain.snap_delays();
        }
        self.master_fx.snap_delays();
        self.metro_delay.snap();
        self.metro_dirty = false;
        let warm = ((WARMUP_SECS * self.rate) as usize).max(CHUNK);
        for t in 0..self.tracks.len() {
            let (strip, buf) = (&mut self.strips[t], &mut self.bufs[t]);
            if strip.chain.live() {
                silence_through(&mut strip.chain, buf, warm, &self.keys, t, &mut self.scratch);
            }
            strip.chain.collect();
        }
        if self.master_fx.live() {
            silence_through(&mut self.master_fx, &mut self.spare, warm, &self.keys, usize::MAX, &mut self.scratch);
        }
        self.master_fx.collect();
        // volume, pan, porta do solo e envios direto no alvo, com a automação da partida aplicada
        self.automate();
        self.solo();
        for t in 0..self.tracks.len() {
            let audible = self.aud[t];
            self.tracks[t].settle(audible);
            for s in &mut self.strips[t].sends {
                s.settle(audible || (s.dst >= 0 && self.up[s.dst as usize]));
            }
        }
        // o transporte anda à frente do que sai: o limitador do master, a cadeia dele e a PDC
        let delay = self.latency_frames();
        let (strips, arrive, total) = (&self.strips, &self.pdc_arrive, self.pdc_total);
        // uma faixa é capturada depois do fader e da saída dela: com a latência do destino
        self.captures.arm(|track| match strips.get(track as usize) {
            Some(s) => delay.saturating_sub(if s.out_dst >= 0 { arrive[s.out_dst as usize] } else { total }),
            None => delay,
        });
        if delay > 0 {
            // o render não tem entrada; a de um bloco entregue fica para o bloco de verdade
            let input = std::mem::replace(&mut self.input_len, 0);
            let mut spare = std::mem::replace(&mut self.spare, Stereo { l: Vec::new(), r: Vec::new() });
            self.captures.priming = true;
            let mut left = delay;
            while left > 0 {
                let k = left.min(CHUNK);
                self.run(&mut spare.l[..k], &mut spare.r[..k]);
                left -= k;
            }
            self.captures.priming = false;
            self.spare = spare;
            self.input_len = input;
        }
        self.out_delay = delay as f64;
        // a grade das fatias recomeça junto com os blocos do render
        self.clock = 0;
    }

    // ---------------------------------------------------------------- áudio

    /// Enche `left` e `right` (mesmo tamanho) com o próximo bloco e avança o transporte.
    pub fn process(&mut self, left: &mut [f32], right: &mut [f32]) {
        self.prepare();
        if self.captures.pending && !self.captures.is_empty() {
            self.start_render();
        }
        let n = left.len().min(right.len());
        self.captures.begin_block(n);
        self.run(&mut left[..n], &mut right[..n]);
        // a entrada valia só para este bloco
        self.input_len = 0;
    }

    /// O bloco fatiado na grade (e nas voltas do loop), fatia por fatia.
    fn run(&mut self, left: &mut [f32], right: &mut [f32]) {
        let n = left.len().min(right.len());
        let mut done = 0;
        while done < n {
            let mut chunk = (n - done).min(CHUNK - (self.clock % CHUNK as u64) as usize);
            // com automação tocando, fatias curtas: cada uma avalia as lanes na posição dela
            if self.playing && self.auto_count > 0 {
                chunk = chunk.min(AUTO_STEP - (self.clock % AUTO_STEP as u64) as usize);
            }
            // o loop fatia o bloco na volta; tocando depois do fim do loop, segue reto
            let looping = self.playing && self.loop_on && self.pos < self.loop_end;
            if looping {
                let until_end = (self.loop_end - self.pos).ceil().max(1.0) as usize;
                chunk = chunk.min(until_end);
            }
            self.block_at = done;
            let (l, r) = (&mut left[done..done + chunk], &mut right[done..done + chunk]);
            self.render(l, r);
            done += chunk;
            self.clock += chunk as u64;
            self.frames_run += chunk as u64;
            if self.playing {
                self.pos += chunk as f64;
                if looping && self.pos >= self.loop_end {
                    self.pos = self.loop_start + (self.pos - self.loop_end);
                    let (from, to) = (self.frames_to_beats(self.loop_end), self.frames_to_beats(self.loop_start));
                    self.recorder.jump(from, to);
                    self.wrap_notes();
                }
            }
        }
    }

    /// Entre um bloco e outro: notas, efeitos que terminaram de sair e o roteamento.
    fn prepare(&mut self) {
        self.anchor = None;
        self.prepare_notes();
        for s in &mut self.strips {
            s.chain.collect();
        }
        self.master_fx.collect();
        // a latência automatizada recalcula a PDC no máximo a cada PDC_AUTO_SECS
        if self.pdc_auto_pending && self.frames_run.saturating_sub(self.pdc_auto_last) >= (PDC_AUTO_SECS * self.rate) as u64 {
            self.pdc_auto_pending = false;
            self.pdc_auto_last = self.frames_run;
            self.pdc_dirty = true;
        }
        self.refresh();
    }

    /// Reordena as notas mexidas e reposiciona os cursores, entre um bloco e outro.
    fn prepare_notes(&mut self) {
        if self.notes_dirty {
            // sem alocar: o sort instável ordena no lugar (e é linear na lista já ordenada, o caso
            // comum de um reenvio)
            for lane in &mut self.lanes {
                lane.notes.sort_unstable_by(|a, b| a.start.total_cmp(&b.start));
                lane.sort_cc();
            }
            self.notes_dirty = false;
            self.recue = true;
        }
        if self.recue {
            for lane in &mut self.lanes {
                lane.cue(self.pos, &self.tempo, self.playing);
            }
            self.recue = false;
        }
    }

    /// Volta do loop: o que o sequenciador segurava é solto no ponto da volta, e as notas do
    /// início do loop disparam no primeiro quadro depois dela.
    fn wrap_notes(&mut self) {
        for lane in &mut self.lanes {
            lane.release_held();
            lane.cue(self.pos, &self.tempo, true);
        }
    }

    fn render(&mut self, out_l: &mut [f32], out_r: &mut [f32]) {
        out_l.fill(0.0);
        out_r.fill(0.0);
        let n = out_l.len();
        self.automate();
        self.solo();
        // barramentos começam o bloco vazios e acumulam o que chega
        for t in 0..self.tracks.len() {
            if self.lanes[t].kind == instrument::kind::BUS {
                self.bufs[t].l[..n].fill(0.0);
                self.bufs[t].r[..n].fill(0.0);
            }
        }
        self.incoming.fill(false);
        let mut to_master = false;
        for oi in 0..self.order.len() {
            let t = self.order[oi];
            let sounded = self.render_track(t, n, out_l, out_r);
            self.sounded[t] = sounded;
            to_master |= sounded && self.strips[t].out_dst < 0;
        }
        if !self.captures.is_empty() {
            self.capture_tracks(n);
        }

        // master: cadeia dele, volume, limitador (inserts antes do fader, como nas faixas: um
        // fade do master não é desfeito por um compressor ou limitador da cadeia)
        if self.master_fx.live() && (to_master || !self.master_idle) {
            if self.master_idle {
                // acordando: os atrasos estão vazios, uma mudança de latência pendente vale já
                self.master_fx.snap_delays();
            }
            self.master_fx.process(out_l, out_r, &self.keys, usize::MAX, &mut self.scratch);
            let (peak, finite) = scan(out_l, out_r);
            if !finite {
                // as amostras ruins viram silêncio logo abaixo; o estado estragado é esquecido
                self.master_fx.reset();
            }
            if to_master {
                self.master_quiet = 0;
                self.master_idle = false;
            } else if peak > SILENCE {
                self.master_quiet = 0;
            } else {
                self.master_quiet += n;
                self.master_idle = self.master_quiet >= self.master_fx.hold();
            }
        } else if to_master {
            self.master_idle = false;
            self.master_quiet = 0;
        }
        self.master.apply_master(out_l, out_r);
        // NaN que escape de algum instrumento ou efeito vira silêncio antes do limitador (senão
        // contaminaria o estado dele); depois do limitador a trava só pega o que ele não pegou
        for s in out_l.iter_mut().chain(out_r.iter_mut()) {
            if !s.is_finite() {
                *s = 0.0;
            }
        }
        if self.playing {
            // o clique fica fora da cadeia do master (não ganha o reverb dele), mas segue o volume
            if self.metronome.on {
                let [gl, gr] = self.master.now_gains();
                let (cl, cr) = self.scratch.pair(n);
                self.metronome.render(cl, cr, self.pos, &self.tempo, &self.meter, self.rate);
                // o clique espera a latência das faixas (PDC e cadeia do master)
                if self.metro_delay.active() {
                    self.metro_delay.process(cl, cr);
                    self.metro_dirty = true;
                }
                for i in 0..n {
                    out_l[i] += cl[i] * gl;
                    out_r[i] += cr[i] * gr;
                }
            } else {
                self.silence_click();
            }
        } else if self.tail > 0 {
            self.tail = self.tail.saturating_sub(n);
            self.tail_pos += n as f64;
        }
        if self.limiter_on {
            self.limiter.process(out_l, out_r);
        }
        for s in out_l.iter_mut().chain(out_r.iter_mut()) {
            *s = s.clamp(-1.0, 1.0);
        }
        // o pré-roll do render (que alinha as capturas) não é música: fica fora da medida
        if !self.captures.priming {
            self.loudness.push(out_l, Some(out_r));
        }
        self.master.meter(out_l, out_r);
        if self.watch_analyzer == -1 {
            self.analyzer.push(out_l, out_r);
        }
        for i in 0..self.captures.len() {
            if self.captures.track(i) == -1 {
                self.captures.write(i, self.block_at, n, Some((out_l, out_r)));
            }
        }
    }

    /// Guarda nas capturas de faixa a saída pós-fader da fatia (silêncio se a faixa não soou ou
    /// não existe).
    fn capture_tracks(&mut self, n: usize) {
        for i in 0..self.captures.len() {
            let track = self.captures.track(i);
            if track < 0 {
                continue;
            }
            let t = track as usize;
            let src = (t < self.tracks.len() && self.sounded[t]).then(|| (&self.bufs[t].l[..n], &self.bufs[t].r[..n]));
            self.captures.write(i, self.block_at, n, src);
        }
    }

    /// O som próprio da faixa no buffer dela: clipes, instrumento e, monitorando, a entrada.
    /// Devolve se soou algo.
    fn render_source(&mut self, t: usize, n: usize) -> bool {
        let buf = &mut self.bufs[t];
        let (bl, br) = (&mut buf.l[..n], &mut buf.r[..n]);
        bl.fill(0.0);
        br.fill(0.0);
        let mut sounded = false;
        if self.playing {
            sounded = render_clips(&self.clips, &self.clip_shapes, &self.samples, t, bl, br, self.pos, &self.tempo, self.rate);
        } else if self.tail > 0 && render_clips(&self.clips, &self.clip_shapes, &self.samples, t, bl, br, self.tail_pos, &self.tempo, self.rate) {
            sounded = true;
            let len = self.tail_len as f32;
            for (i, (l, r)) in bl.iter_mut().zip(br.iter_mut()).enumerate() {
                let g = (self.tail as f32 - i as f32).max(0.0) / len;
                *l *= g;
                *r *= g;
            }
        }
        // a entrada depois do fade de parada dos clipes: monitorar não depende do transporte
        let lane = &self.lanes[t];
        if lane.monitor && lane.kind == instrument::kind::AUDIO && self.block_at < self.input_len {
            let (from, m) = (self.block_at, (self.input_len - self.block_at).min(n));
            for (d, s) in bl[..m].iter_mut().zip(&self.input.l[from..from + m]) {
                *d += s;
            }
            for (d, s) in br[..m].iter_mut().zip(&self.input.r[from..from + m]) {
                *d += s;
            }
            sounded = true;
        }
        // instrumentos tocam parados também (notas ao vivo e caudas)
        sounded | self.lanes[t].render(bl, br, self.playing, self.pos, &self.tempo)
    }

    /// Uma faixa inteira: fonte (ou o que chegou no barramento) → inserts → envios pré-fader →
    /// volume/pan/mudo → envios pós-fader → porta do solo → saída. Devolve se mandou som.
    fn render_track(&mut self, t: usize, n: usize, out_l: &mut [f32], out_r: &mut [f32]) -> bool {
        let mut active = if self.lanes[t].kind == instrument::kind::BUS { self.incoming[t] } else { self.render_source(t, n) };
        let strip = &mut self.strips[t];
        let buf = &mut self.bufs[t];
        let (bl, br) = (&mut buf.l[..n], &mut buf.r[..n]);
        // PDC: com a fonte calada ainda há som nos atrasos (o da fonte, os das linhas de saída e
        // envio): a faixa segue rodando com silêncio até esvaziá-los
        if active {
            strip.flush = self.pdc_total;
            if !strip.warm {
                strip.warm = true;
                strip.pre.snap();
                strip.out_line.snap();
                for s in &mut strip.sends {
                    s.line.snap();
                }
                strip.chain.snap_delays();
            }
        } else if strip.flush > 0 {
            bl.fill(0.0);
            br.fill(0.0);
            strip.flush = strip.flush.saturating_sub(n);
            active = true;
        } else {
            strip.warm = false;
        }
        if active && strip.pre.active() {
            strip.pre.process(bl, br);
        }
        // os inserts rodam também com a entrada calada, enquanto houver cauda (reverb, delay)
        if strip.chain.live() && (active || !strip.idle) {
            strip.chain.process(bl, br, &self.keys, t, &mut self.scratch);
            let (peak, finite) = scan(bl, br);
            if !finite {
                // um efeito explodiu: silêncio neste bloco e estado esquecido, em vez de NaN
                // contaminando barramentos e master para sempre
                bl.fill(0.0);
                br.fill(0.0);
                strip.chain.reset();
            }
            if active {
                strip.quiet = 0;
                strip.idle = false;
            } else if peak > SILENCE {
                strip.quiet = 0;
            } else {
                strip.quiet += n;
                strip.idle = strip.quiet >= strip.chain.hold();
            }
            active |= finite && peak > 0.0;
        } else if active {
            strip.idle = false;
            strip.quiet = 0;
        }
        // chave de sidechain: a saída pós-inserts, pré-fader
        if strip.is_key {
            let key = &mut self.keys[t];
            if active {
                key.l[..n].copy_from_slice(bl);
                key.r[..n].copy_from_slice(br);
                strip.key_silent = false;
            } else if !strip.key_silent {
                key.l.fill(0.0);
                key.r.fill(0.0);
                strip.key_silent = true;
            }
        }
        let track = &mut self.tracks[t];
        let audible = self.aud[t];
        if !active {
            track.settle(audible);
            for s in &mut strip.sends {
                s.settle(audible || (s.dst >= 0 && self.up[s.dst as usize]));
            }
            if self.watch_analyzer == t as i32 {
                self.analyzer.push_silence(n);
            }
            return false;
        }
        let k = self.smooth;
        mix_sends(&mut strip.sends, &mut self.bufs, &mut self.incoming, &self.up, audible, t, n, true, k, &mut self.scratch);
        {
            let buf = &mut self.bufs[t];
            track.fader(&mut buf.l[..n], &mut buf.r[..n]);
        }
        mix_sends(&mut strip.sends, &mut self.bufs, &mut self.incoming, &self.up, audible, t, n, false, k, &mut self.scratch);
        if strip.out_line.active() {
            // PDC: a saída chega ao destino alinhada com as outras entradas dele
            let buf = &mut self.bufs[t];
            strip.out_line.process(&mut buf.l[..n], &mut buf.r[..n]);
        }
        let d = strip.out_dst;
        if d >= 0 {
            let Ok([from, to]) = self.bufs.get_disjoint_mut([t, d as usize]) else { return false };
            track.output(&mut from.l[..n], &mut from.r[..n], &mut to.l[..n], &mut to.r[..n], audible);
            self.incoming[d as usize] = true;
        } else {
            let buf = &mut self.bufs[t];
            track.output(&mut buf.l[..n], &mut buf.r[..n], out_l, out_r, audible);
        }
        if self.watch_analyzer == t as i32 {
            let buf = &self.bufs[t];
            self.analyzer.push(&buf.l[..n], &buf.r[..n]);
        }
        true
    }
}

/// Passa `frames` quadros de silêncio pela cadeia, com a saída descartada: as transições dela
/// (crossfades de efeito entrando, trocando ou saindo) terminam sem som nenhum passando.
fn silence_through(chain: &mut Chain, buf: &mut Stereo, frames: usize, keys: &[Stereo], own: usize, scratch: &mut Scratch) {
    let mut left = frames;
    while left > 0 && !buf.l.is_empty() {
        let k = left.min(CHUNK).min(buf.l.len());
        buf.l[..k].fill(0.0);
        buf.r[..k].fill(0.0);
        chain.process(&mut buf.l[..k], &mut buf.r[..k], keys, own, scratch);
        left -= k;
    }
    buf.l.fill(0.0);
    buf.r.fill(0.0);
}

/// Soma os clipes de áudio da faixa `track` no bloco que começa em `pos` (quadros). Devolve se
/// algum clipe caiu no bloco.
#[allow(clippy::too_many_arguments)]
fn render_clips(
    clips: &[Clip],
    shapes: &[(u8, u8)],
    samples: &HashMap<u32, Arc<Sample>>,
    track: usize,
    bl: &mut [f32],
    br: &mut [f32],
    pos: f64,
    tempo: &TempoMap,
    rate: f64,
) -> bool {
    let n = bl.len();
    let (start, end) = (pos, pos + n as f64);
    let mut sounded = false;
    for (ci, clip) in clips.iter().enumerate().filter(|(_, c)| c.track == track) {
        let (shape_in, shape_out) = shapes.get(ci).copied().unwrap_or((0, 0));
        let Some(sample) = samples.get(&clip.sample) else { continue };
        let c_start = tempo.to_frames(clip.start);
        let c_end = c_start + clip.length * rate;
        if c_end <= start || c_start >= end {
            continue;
        }
        sounded = true;
        let step = sample.rate / rate;
        let stereo = sample.channels.len() > 1;
        let from = ((c_start - start).max(0.0)).ceil() as usize;
        let to = ((c_end - start).min(n as f64)).ceil() as usize;
        for i in from..to.min(n) {
            let t = start + i as f64 - c_start; // quadros desde o início do clipe
            let secs = t / rate;
            let env = fade(secs, clip.length, clip.fade_in, clip.fade_out, shape_in, shape_out) * clip.gain;
            let sp = clip.offset * sample.rate + t * step;
            let l = sample.at_cubic(0, sp);
            let r = if stereo { sample.at_cubic(1, sp) } else { l };
            bl[i] += l * env;
            br[i] += r * env;
        }
    }
    sounded
}

/// Curvas de fade (o valor de `clip_fade_shape`). O padrão, 0, é o envelope histórico do motor
/// (`x²`, o de todo projeto que ainda não escolheu curva): mantê-lo preserva o som dos projetos
/// antigos. As demais são curvas de amplitude sobre `x` (0 a 1 = progresso da entrada; a saída usa
/// o mesmo desenho espelhado).
pub const FADE_DEFAULT: u32 = 0;
/// Potência constante: `sin(x·π/2)`. Dois clipes sem correlação num crossfade somam potência 1.
pub const FADE_EQUAL_POWER: u32 = 1;
/// Exponencial (`(e^{4x}−1)/(e^4−1)`): na saída cai depressa e some suave no fim; na entrada
/// sobe devagar e acelera.
pub const FADE_EXP: u32 = 2;
/// S (seno cosseno): `(1−cos πx)/2`, suave nas duas pontas.
pub const FADE_S: u32 = 3;

/// Ganho de amplitude da curva `shape` no progresso `x` (0 a 1, fora disso é limitado). Vale
/// exatamente 0 em 0 e 1 em 1, e não decresce. Sem alocação.
pub fn fade_curve(shape: u32, x: f64) -> f64 {
    let x = x.clamp(0.0, 1.0);
    match shape {
        FADE_EQUAL_POWER => (x * std::f64::consts::FRAC_PI_2).sin(),
        FADE_EXP => {
            const K: f64 = 4.0;
            ((K * x).exp() - 1.0) / (K.exp() - 1.0)
        }
        FADE_S => (1.0 - (x * std::f64::consts::PI).cos()) * 0.5,
        _ => x * x,
    }
}

/// Envelope de fade de entrada e saída do clipe, no instante `t` (segundos desde o início).
fn fade(t: f64, length: f64, fade_in: f64, fade_out: f64, shape_in: u8, shape_out: u8) -> f32 {
    let mut g = 1.0;
    if fade_in > 0.0 && t < fade_in {
        g *= fade_curve(shape_in as u32, t / fade_in);
    }
    let left = length - t;
    if fade_out > 0.0 && left < fade_out {
        g *= fade_curve(shape_out as u32, (left / fade_out).max(0.0));
    }
    g as f32
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Motor sem o limitador do master (o lookahead atrasaria as amostras que os testes medem).
    fn engine() -> Engine {
        let mut e = Engine::new(RATE);
        e.set_limiter(false);
        e
    }

    const RATE: f64 = 48_000.0;

    fn engine_with_dc_clip(start: f64, length: f64) -> Engine {
        let mut e = engine();
        e.set_tempo(120.0, 4); // 1 batida = 0,5 s = 24000 quadros
        e.set_track_count(1);
        e.track_mut(0).unwrap().pan = 0.0;
        e.load_sample(1, Sample::new(vec![vec![0.5; 96_000]], RATE));
        e.add_clip(Clip { track: 0, sample: 1, start, offset: 0.0, length, gain: 1.0, fade_in: 0.0, fade_out: 0.0 });
        e
    }

    fn run(e: &mut Engine, frames: usize) -> (Vec<f32>, Vec<f32>) {
        let (mut l, mut r) = (vec![0.0; frames], vec![0.0; frames]);
        for (cl, cr) in l.chunks_mut(128).zip(r.chunks_mut(128)) {
            e.process(cl, cr);
        }
        (l, r)
    }

    #[test]
    fn curvas_de_fade_nos_quartos_e_nas_pontas() {
        let xs = [0.0, 0.25, 0.5, 0.75, 1.0];
        let s2 = std::f64::consts::FRAC_1_SQRT_2;
        let expect: [(u32, [f64; 5]); 4] = [
            (FADE_DEFAULT, [0.0, 0.0625, 0.25, 0.5625, 1.0]),
            (FADE_EQUAL_POWER, [0.0, (std::f64::consts::PI / 8.0).sin(), s2, (3.0 * std::f64::consts::PI / 8.0).sin(), 1.0]),
            (FADE_EXP, [0.0, (1f64.exp() - 1.0) / (4f64.exp() - 1.0), (2f64.exp() - 1.0) / (4f64.exp() - 1.0), (3f64.exp() - 1.0) / (4f64.exp() - 1.0), 1.0]),
            (FADE_S, [0.0, (1.0 - s2) / 2.0, 0.5, (1.0 + s2) / 2.0, 1.0]),
        ];
        for (shape, want) in expect {
            for (x, w) in xs.iter().zip(want) {
                assert!((fade_curve(shape, *x) - w).abs() < 1e-12, "curva {shape} em {x}: {} != {w}", fade_curve(shape, *x));
            }
            // pontas exatas, fora do intervalo limitado, monótona e sem passar de 1
            assert_eq!(fade_curve(shape, 0.0), 0.0);
            assert_eq!(fade_curve(shape, 1.0), 1.0);
            assert_eq!(fade_curve(shape, -3.0), 0.0);
            assert_eq!(fade_curve(shape, 7.0), 1.0);
            let mut prev = 0.0;
            for i in 0..=10_000 {
                let g = fade_curve(shape, i as f64 / 10_000.0);
                assert!(g >= prev && g <= 1.0, "curva {shape} não monótona em {i}");
                prev = g;
            }
        }
        // valor desconhecido = padrão
        assert_eq!(fade_curve(99, 0.5), fade_curve(FADE_DEFAULT, 0.5));
    }

    /// Clipe de DC (1,0) de 1 s com os fades e as curvas pedidos; devolve o canal esquerdo de 1 s.
    fn render_faded(fade_in: f64, fade_out: f64, shapes: Option<(u32, u32)>) -> Vec<f32> {
        let mut e = engine();
        e.set_tempo(120.0, 4);
        e.set_track_count(1);
        e.track_mut(0).unwrap().pan = 0.0;
        e.load_sample(1, Sample::new(vec![vec![1.0; 96_000]], RATE));
        e.add_clip(Clip { track: 0, sample: 1, start: 0.0, offset: 0.0, length: 1.0, gain: 1.0, fade_in, fade_out });
        if let Some((a, b)) = shapes {
            e.set_clip_fade_shape(a, b);
        }
        e.play();
        run(&mut e, 48_000).0
    }

    #[test]
    fn clipe_aplica_a_curva_escolhida_em_cada_lado() {
        let base = render_faded(0.0, 0.0, None);
        let full = base[24_000]; // ganho da faixa com pan central
        assert!(full > 0.5);
        let f = 0.5; // 24000 quadros de fade nos dois lados
        for shape in [FADE_DEFAULT, FADE_EQUAL_POWER, FADE_EXP, FADE_S] {
            let l = render_faded(f, f, Some((shape, shape)));
            for i in [0usize, 6000, 12_000, 18_000, 23_999] {
                let want = fade_curve(shape, i as f64 / 24_000.0) as f32 * full;
                assert!((l[i] - want).abs() < 1e-4, "curva {shape} entrada em {i}: {} != {want}", l[i]);
            }
            for i in [24_000usize, 30_000, 36_000, 42_000] {
                let left = (48_000 - i) as f64 / 24_000.0;
                let want = fade_curve(shape, left) as f32 * full;
                assert!((l[i] - want).abs() < 1e-4, "curva {shape} saída em {i}: {} != {want}", l[i]);
            }
            assert_eq!(l[0], 0.0);
            assert!(l[47_999] < 1e-3 * full);
        }
        // lados independentes: entrada equal-power, saída padrão
        let l = render_faded(f, f, Some((FADE_EQUAL_POWER, FADE_DEFAULT)));
        assert!((l[6000] - fade_curve(FADE_EQUAL_POWER, 0.25) as f32 * full).abs() < 1e-4);
        assert!((l[42_000] - fade_curve(FADE_DEFAULT, 0.25) as f32 * full).abs() < 1e-4);
        // sem a chamada nova, o som é o histórico (x²)
        let old = render_faded(f, f, None);
        assert!((old[12_000] - 0.25 * full).abs() < 1e-4);
    }

    #[test]
    fn fade_de_zero_amostra_e_sem_fade_em_qualquer_curva() {
        let base = render_faded(0.0, 0.0, None);
        for shape in [FADE_DEFAULT, FADE_EQUAL_POWER, FADE_EXP, FADE_S] {
            assert_eq!(render_faded(0.0, 0.0, Some((shape, shape))), base, "curva {shape}");
        }
    }

    #[test]
    fn curva_sem_clipe_ou_de_clipe_limpo_nao_estraga_nada() {
        let mut e = engine();
        e.set_clip_fade_shape(1, 1); // sem clipe: ignora
        e.set_track_count(1);
        e.load_sample(1, Sample::new(vec![vec![1.0; 100]], RATE));
        e.add_clip(Clip { track: 0, sample: 1, start: 0.0, offset: 0.0, length: 0.001, gain: 1.0, fade_in: 0.0, fade_out: 0.0 });
        e.set_clip_fade_shape(FADE_S, FADE_S);
        e.clear_clips();
        e.set_clip_fade_shape(1, 1);
        assert!(e.clip_shapes.is_empty());
        e.add_clip(Clip { track: 0, sample: 1, start: 0.0, offset: 0.0, length: 0.001, gain: 1.0, fade_in: 0.0, fade_out: 0.0 });
        assert_eq!(e.clip_shapes, vec![(0, 0)]);
    }

    /// Dois clipes de tons sem correlação, com sobreposição de 0,5 s e crossfade da mesma duração.
    fn crossfade_power(shape: u32) -> Vec<f64> {
        let tone = |hz: f64| -> Vec<f32> { (0..96_000).map(|i| (2.0 * std::f64::consts::PI * hz * i as f64 / RATE).sin() as f32).collect() };
        let mut e = engine();
        e.set_tempo(120.0, 4);
        e.set_track_count(1);
        e.track_mut(0).unwrap().pan = 0.0;
        e.load_sample(1, Sample::new(vec![tone(100.0)], RATE));
        e.load_sample(2, Sample::new(vec![tone(150.0)], RATE));
        // A: 0 a 1 s, sai em 0,5 s; B: 0,5 s a 1,5 s, entra em 0,5 s (1 batida = 0,5 s)
        e.add_clip(Clip { track: 0, sample: 1, start: 0.0, offset: 0.0, length: 1.0, gain: 1.0, fade_in: 0.0, fade_out: 0.5 });
        e.set_clip_fade_shape(shape, shape);
        e.add_clip(Clip { track: 0, sample: 2, start: 1.0, offset: 0.0, length: 1.0, gain: 1.0, fade_in: 0.5, fade_out: 0.0 });
        e.set_clip_fade_shape(shape, shape);
        e.play();
        let (l, _) = run(&mut e, 72_000);
        // potência média em 5 janelas de 4800 quadros (ciclos inteiros dos dois tons) na sobreposição
        (0..5).map(|k| l[24_000 + k * 4800..24_000 + (k + 1) * 4800].iter().map(|&x| (x as f64).powi(2)).sum::<f64>() / 4800.0).collect()
    }

    #[test]
    fn crossfade_de_potencia_constante_mantem_a_potencia() {
        let solo = {
            let mut e = engine();
            e.set_tempo(120.0, 4);
            e.set_track_count(1);
            e.track_mut(0).unwrap().pan = 0.0;
            e.load_sample(1, Sample::new(vec![(0..96_000).map(|i| (2.0 * std::f64::consts::PI * 100.0 * i as f64 / RATE).sin() as f32).collect()], RATE));
            e.add_clip(Clip { track: 0, sample: 1, start: 0.0, offset: 0.0, length: 1.0, gain: 1.0, fade_in: 0.0, fade_out: 0.0 });
            e.play();
            let (l, _) = run(&mut e, 4800);
            l.iter().map(|&x| (x as f64).powi(2)).sum::<f64>() / 4800.0
        };
        assert!(solo > 0.1);
        let eq = crossfade_power(FADE_EQUAL_POWER);
        for (k, p) in eq.iter().enumerate() {
            assert!((p / solo - 1.0).abs() < 0.03, "janela {k}: potência {} vs {solo}", p);
        }
        // a curva padrão (x²) e a S afundam no meio: prova que a curva importa
        let dip = crossfade_power(FADE_DEFAULT);
        assert!(dip[2] < 0.8 * solo, "curva padrão não afunda: {}", dip[2] / solo);
        assert!(crossfade_power(FADE_S)[2] < 0.9 * solo);
    }

    #[test]
    fn parado_e_silencio() {
        let mut e = engine_with_dc_clip(0.0, 1.0);
        let (l, _) = run(&mut e, 1024);
        assert!(l.iter().all(|&s| s == 0.0));
        assert_eq!(e.beat(), 0.0);
    }

    #[test]
    fn clipe_toca_no_lugar_certo() {
        // clipe começa na batida 1 (quadro 24000) e dura 0,25 s (12000 quadros)
        let mut e = engine_with_dc_clip(1.0, 0.25);
        e.play();
        let (l, r) = run(&mut e, 48_000);
        let g = pan_gains(0.0).0 * 0.5;
        assert_eq!(l[23_999], 0.0);
        assert!((l[24_000] - g).abs() < 1e-5, "{}", l[24_000]);
        assert!((r[30_000] - g).abs() < 1e-5);
        assert!((l[35_999] - g).abs() < 1e-5);
        assert_eq!(l[36_000], 0.0);
        assert!((e.beat() - 2.0).abs() < 1e-9);
    }

    #[test]
    fn loop_volta_para_o_inicio() {
        let mut e = engine_with_dc_clip(0.0, 4.0);
        e.set_loop(true, 1.0, 2.0);
        e.seek(1.0);
        e.play();
        run(&mut e, 24_000 + 100);
        assert!((e.frames_to_beats(e.pos) - (1.0 + 100.0 / 24_000.0)).abs() < 1e-9);
    }

    #[test]
    fn stop_desce_o_audio_sem_estalo() {
        let mut e = engine_with_dc_clip(0.0, 2.0);
        e.play();
        run(&mut e, 1280);
        e.stop();
        e.seek(0.0);
        let (l, _) = run(&mut e, 1280);
        let g = pan_gains(0.0).0 * 0.5;
        assert!((l[0] - g).abs() < 0.01, "{}", l[0]);
        let jump = l.windows(2).map(|w| (w[0] - w[1]).abs()).fold(0.0, f32::max);
        assert!(jump < 0.001, "{jump}");
        assert!(l[480..].iter().all(|&s| s == 0.0));
        // tocar de novo não herda o fade
        e.play();
        let (l, _) = run(&mut e, 128);
        assert!((l[0] - g).abs() < 1e-5);
    }

    #[test]
    fn depois_do_fim_do_loop_segue_reto() {
        let mut e = engine_with_dc_clip(0.0, 4.0);
        e.seek(3.0);
        e.set_loop(true, 1.0, 2.0);
        e.play();
        run(&mut e, 1280);
        assert!((e.beat() - (3.0 + 1280.0 / 24_000.0)).abs() < 1e-9);
    }

    #[test]
    fn mudo_e_solo() {
        let mut e = engine_with_dc_clip(0.0, 1.0);
        e.set_track_count(2);
        e.add_clip(Clip { track: 1, sample: 1, start: 0.0, offset: 0.0, length: 1.0, gain: 1.0, fade_in: 0.0, fade_out: 0.0 });
        e.track_mut(1).unwrap().solo = true;
        e.track_mut(1).unwrap().mute = true;
        e.play();
        let (l, _) = run(&mut e, 256);
        // a 1 está em solo mas muda; a 0 não está em solo: silêncio
        assert!(l.iter().all(|&s| s == 0.0));
    }

    #[test]
    fn mudar_andamento_preserva_a_batida() {
        let mut e = engine_with_dc_clip(0.0, 1.0);
        e.seek(3.0);
        e.set_tempo(90.0, 4);
        assert!((e.beat() - 3.0).abs() < 1e-9);
    }

    #[test]
    fn taxa_diferente_e_reamostrada() {
        let mut e = engine();
        e.set_track_count(1);
        // rampa a 24 kHz: no motor a 48 kHz cada amostra do sample vira duas
        let ramp: Vec<f32> = (0..1000).map(|i| i as f32 / 1000.0).collect();
        e.load_sample(7, Sample::new(vec![ramp], 24_000.0));
        e.add_clip(Clip { track: 0, sample: 7, start: 0.0, offset: 0.0, length: 1000.0 / 24_000.0, gain: 1.0, fade_in: 0.0, fade_out: 0.0 });
        e.play();
        let (l, _) = run(&mut e, 256);
        let g = pan_gains(0.0).0;
        assert!((l[2] - 0.001 * g).abs() < 1e-5);
        assert!((l[3] - 0.0015 * g).abs() < 1e-5);
    }

    #[test]
    fn metronomo_clica_na_batida() {
        let mut e = engine();
        e.set_metronome(true, 1.0);
        e.play();
        let (l, _) = run(&mut e, 24_100);
        assert!(l[10..500].iter().any(|s| s.abs() > 0.1));
        assert!(l[20_000..23_999].iter().all(|&s| s == 0.0));
        assert!(l[24_010..24_100].iter().any(|s| s.abs() > 0.1));
    }

    #[test]
    fn hermite_reproduz_retas_e_passa_pelos_pontos() {
        assert!((hermite(1.0, 2.0, 3.0, 4.0, 0.25) - 2.25).abs() < 1e-6);
        assert_eq!(hermite(0.3, -0.7, 0.9, 0.1, 0.0), -0.7);
        assert!((hermite(0.3, -0.7, 0.9, 0.1, 1.0) - 0.9).abs() < 1e-6);
    }

    // ------------------------------------------------------------ instrumentos e notas

    use std::sync::Mutex;

    #[derive(Clone, Debug, PartialEq)]
    enum Ev {
        On(u64, u8),
        Off(u64, u8),
        ReleaseAll(u64),
        Silence(u64),
    }

    type Log = Arc<Mutex<Vec<Ev>>>;

    /// Instrumento de teste: anota cada evento com o quadro em que caiu (conta os quadros que
    /// renderizou; está sempre ativo, então renderiza todos) e soa 0,25 por nota presa.
    struct Probe {
        frame: u64,
        log: Log,
        held: [bool; 128],
    }

    impl Instrument for Probe {
        fn note_on(&mut self, pitch: u8, _velocity: f32) {
            self.log.lock().unwrap().push(Ev::On(self.frame, pitch));
            self.held[pitch as usize] = true;
        }
        fn note_off(&mut self, pitch: u8) {
            self.log.lock().unwrap().push(Ev::Off(self.frame, pitch));
            self.held[pitch as usize] = false;
        }
        fn release_all(&mut self) {
            self.log.lock().unwrap().push(Ev::ReleaseAll(self.frame));
            self.held = [false; 128];
        }
        fn silence(&mut self) {
            self.log.lock().unwrap().push(Ev::Silence(self.frame));
            self.held = [false; 128];
        }
        fn set_param(&mut self, _id: u32, _value: f32) {}
        fn render(&mut self, left: &mut [f32], right: &mut [f32]) {
            let v = self.held.iter().filter(|&&h| h).count() as f32 * 0.25;
            for (l, r) in left.iter_mut().zip(right.iter_mut()) {
                *l += v;
                *r += v;
            }
            self.frame += left.len() as u64;
        }
        fn active(&self) -> bool {
            true
        }
    }

    /// Motor a 120 bpm (24000 quadros por batida) com uma faixa de instrumento de teste.
    fn probe_engine() -> (Engine, Log) {
        let mut e = engine();
        e.set_tempo(120.0, 4);
        e.set_track_count(1);
        e.set_track_kind(0, instrument::kind::SYNTH);
        let log = Log::default();
        e.lanes[0].instrument = Some(Box::new(Probe { frame: 0, log: log.clone(), held: [false; 128] }));
        (e, log)
    }

    fn events(log: &Log) -> Vec<Ev> {
        log.lock().unwrap().clone()
    }

    /// Batidas de um quadro a 120 bpm / 48 kHz.
    fn b(frames: f64) -> f64 {
        frames / 24_000.0
    }

    #[test]
    fn notas_caem_no_quadro_exato() {
        let (mut e, log) = probe_engine();
        e.add_note(0, b(100.0), b(50.0), 60, 0.9);
        e.add_note(0, 0.5, 0.25, 64, 0.9);
        // fora de ordem: o motor ordena
        e.add_note(0, b(130.0), b(1000.0), 62, 0.9);
        e.play();
        run(&mut e, 24_000);
        assert_eq!(events(&log), vec![Ev::On(100, 60), Ev::On(130, 62), Ev::Off(150, 60), Ev::Off(1130, 62), Ev::On(12_000, 64), Ev::Off(18_000, 64)]);
    }

    #[test]
    fn nota_no_quadro_zero_toca_ao_dar_play() {
        let (mut e, log) = probe_engine();
        e.add_note(0, 0.0, 1.0, 60, 0.9);
        e.play();
        run(&mut e, 128);
        assert_eq!(events(&log), vec![Ev::On(0, 60)]);
    }

    #[test]
    fn nota_que_termina_onde_a_mesma_recomeca() {
        let (mut e, log) = probe_engine();
        e.add_note(0, 0.0, 0.5, 60, 0.9);
        e.add_note(0, 0.5, 0.5, 60, 0.9);
        e.play();
        run(&mut e, 30_000);
        assert_eq!(events(&log), vec![Ev::On(0, 60), Ev::Off(12_000, 60), Ev::On(12_000, 60), Ev::Off(24_000, 60)]);
    }

    #[test]
    fn notas_sobrepostas_da_mesma_altura_soltam_no_fim_mais_tardio() {
        let (mut e, log) = probe_engine();
        e.add_note(0, 0.0, 1.0, 60, 0.9);
        e.add_note(0, 0.25, 0.25, 60, 0.9);
        e.play();
        run(&mut e, 30_000);
        assert_eq!(events(&log), vec![Ev::On(0, 60), Ev::On(6000, 60), Ev::Off(24_000, 60)]);
    }

    #[test]
    fn volta_do_loop_solta_e_redispara() {
        let (mut e, log) = probe_engine();
        e.set_loop(true, 0.0, 1.0);
        e.add_note(0, 0.0, 0.25, 60, 0.9);
        // passa do fim do loop: é solta na volta
        e.add_note(0, 0.5, 1.0, 64, 0.9);
        e.play();
        run(&mut e, 48_000 + 128);
        assert_eq!(
            events(&log),
            vec![
                Ev::On(0, 60),
                Ev::Off(6000, 60),
                Ev::On(12_000, 64),
                Ev::Off(24_000, 64),
                Ev::On(24_000, 60),
                Ev::Off(30_000, 60),
                Ev::On(36_000, 64),
                Ev::Off(48_000, 64),
                Ev::On(48_000, 60),
            ]
        );
    }

    #[test]
    fn loop_fora_da_grade_de_blocos() {
        // fim do loop no meio de um bloco de 128: a volta fatia o bloco no ponto certo
        let (mut e, log) = probe_engine();
        e.set_loop(true, 0.0, b(1000.0));
        e.add_note(0, 0.0, b(100.0), 60, 0.9);
        e.play();
        run(&mut e, 2100);
        assert_eq!(events(&log), vec![Ev::On(0, 60), Ev::Off(100, 60), Ev::On(1000, 60), Ev::Off(1100, 60), Ev::On(2000, 60)]);
    }

    #[test]
    fn apagar_as_notas_no_meio_nao_prende() {
        let (mut e, log) = probe_engine();
        e.add_note(0, 0.0, 1.0, 60, 0.9);
        e.play();
        run(&mut e, 6000);
        e.clear_notes();
        run(&mut e, 30_000);
        assert_eq!(events(&log), vec![Ev::On(0, 60), Ev::Off(24_000, 60)]);
    }

    #[test]
    fn reenviar_as_notas_tocando_nao_redispara() {
        let (mut e, log) = probe_engine();
        let send = |e: &mut Engine| {
            e.clear_notes();
            e.add_note(0, 0.0, 1.0, 60, 0.9);
            e.add_note(0, 0.5, 0.25, 62, 0.9);
        };
        send(&mut e);
        e.play();
        for _ in 0..10 {
            run(&mut e, 2560);
            send(&mut e);
        }
        run(&mut e, 10_000);
        assert_eq!(events(&log), vec![Ev::On(0, 60), Ev::On(12_000, 62), Ev::Off(18_000, 62), Ev::Off(24_000, 60)]);
    }

    #[test]
    fn stop_solta_tudo_e_play_no_meio_nao_persegue() {
        let (mut e, log) = probe_engine();
        e.add_note(0, 0.0, 4.0, 60, 0.9);
        e.play();
        run(&mut e, 1280);
        e.stop();
        run(&mut e, 256);
        e.play();
        run(&mut e, 1280);
        assert_eq!(events(&log), vec![Ev::On(0, 60), Ev::ReleaseAll(1280)]);
    }

    #[test]
    fn seek_solta_as_notas_do_sequenciador() {
        let (mut e, log) = probe_engine();
        e.add_note(0, 0.0, 4.0, 60, 0.9);
        e.add_note(0, 2.0, 0.5, 62, 0.9);
        e.play();
        run(&mut e, 1000);
        e.seek(2.0);
        run(&mut e, 256);
        assert_eq!(events(&log), vec![Ev::On(0, 60), Ev::Off(1000, 60), Ev::On(1000, 62)]);
    }

    #[test]
    fn andamento_converte_as_batidas() {
        let (mut e, log) = probe_engine();
        e.set_tempo(60.0, 4); // 1 batida = 48000 quadros
        e.add_note(0, 1.0, 0.5, 60, 0.9);
        e.play();
        run(&mut e, 72_100);
        assert_eq!(events(&log), vec![Ev::On(48_000, 60), Ev::Off(72_000, 60)]);
    }

    #[test]
    fn notas_ao_vivo_independem_do_transporte() {
        let (mut e, log) = probe_engine();
        e.live_on(0, 60, 0.8);
        let (l, _) = run(&mut e, 256);
        assert!(l[10] > 0.0, "parado, a nota ao vivo soa");
        e.add_note(0, 0.0, 4.0, 62, 0.9);
        e.play();
        run(&mut e, 256);
        // seek solta as do sequenciador, não as ao vivo
        e.seek(0.0);
        run(&mut e, 256);
        e.live_off(0, 60);
        e.live_on(0, 64, 0.0); // velocidade 0 = note off
        e.panic();
        let (l, _) = run(&mut e, 256);
        assert_eq!(events(&log), vec![Ev::On(0, 60), Ev::On(256, 62), Ev::Off(512, 62), Ev::On(512, 62), Ev::Off(768, 60), Ev::Off(768, 64), Ev::Silence(768)]);
        assert!(l.iter().all(|&s| s == 0.0));
    }

    #[test]
    fn faixa_muda_nao_soa() {
        let (mut e, _) = probe_engine();
        e.track_mut(0).unwrap().mute = true;
        e.add_note(0, 0.0, 4.0, 60, 0.9);
        e.play();
        let (l, _) = run(&mut e, 1024);
        assert!(l.iter().all(|&s| s == 0.0));
        // tirar o mudo com a nota soando traz o som de volta (a nota seguiu presa, só calada)
        e.track_mut(0).unwrap().mute = false;
        let (l, _) = run(&mut e, 4800);
        assert!(l[4000] > 0.1);
        // e mudar de novo leva a zero sem degrau
        e.track_mut(0).unwrap().mute = true;
        let (l, _) = run(&mut e, 4800);
        let jump = l.windows(2).map(|w| (w[0] - w[1]).abs()).fold(0.0, f32::max);
        assert!(jump < 0.01, "{jump}");
        assert!(l[4799].abs() < 1e-6);
    }

    #[test]
    fn solo_de_instrumento_cala_as_outras() {
        let (mut e, _) = probe_engine();
        e.set_track_count(2);
        e.set_track_kind(1, instrument::kind::SYNTH);
        let log2 = Log::default();
        e.lanes[1].instrument = Some(Box::new(Probe { frame: 0, log: log2, held: [false; 128] }));
        e.track_mut(1).unwrap().solo = true;
        e.add_note(0, 0.0, 1.0, 60, 0.9);
        e.play();
        let (l, _) = run(&mut e, 512);
        assert!(l.iter().all(|&s| s == 0.0));
    }

    #[test]
    fn faixa_de_audio_nao_toca_notas() {
        let mut e = engine();
        e.set_track_count(1);
        e.add_note(0, 0.0, 1.0, 60, 0.9);
        e.live_on(0, 60, 1.0);
        e.play();
        let (l, _) = run(&mut e, 1024);
        assert!(l.iter().all(|&s| s == 0.0));
        assert_eq!(e.track_kind(0), Some(instrument::kind::AUDIO));
    }

    #[test]
    fn trocar_o_tipo_recria_o_instrumento_so_quando_muda() {
        let (mut e, log) = probe_engine();
        // o mesmo tipo de novo (o app manda a cada sync) não mexe no instrumento
        e.set_track_kind(0, instrument::kind::SYNTH);
        e.live_on(0, 60, 1.0);
        assert_eq!(events(&log), vec![Ev::On(0, 60)]);
        e.set_track_kind(0, instrument::kind::AUDIO);
        assert!(e.lanes[0].instrument.is_none());
        e.set_track_kind(0, instrument::kind::SAMPLER);
        assert!(e.lanes[0].instrument.is_some());
    }

    #[test]
    fn notas_invalidas_sao_ignoradas() {
        let (mut e, _) = probe_engine();
        e.add_note(0, 0.0, 0.0, 60, 0.9);
        e.add_note(0, 0.0, 1.0, 128, 0.9);
        e.add_note(0, f64::NAN, 1.0, 60, 0.9);
        e.add_note(0, 0.0, f64::INFINITY, 60, 0.9);
        e.add_note(5, 0.0, 1.0, 60, 0.9);
        assert!(e.lanes[0].notes.is_empty());
    }

    // ------------------------------------------------------------ sampler pelo motor

    fn sampler_engine() -> Engine {
        let mut e = engine();
        e.set_tempo(120.0, 4);
        e.set_track_count(1);
        e.set_track_kind(0, instrument::kind::SAMPLER);
        e.set_param(0, instrument::sampler_param::LEVEL, 1.0);
        e.set_param(0, instrument::sampler_param::VELOCITY, 0.0);
        e
    }

    #[test]
    fn sampler_toca_as_notas_da_faixa() {
        let mut e = sampler_engine();
        e.load_sample(3, Sample::new(vec![vec![0.5; 48_000]], RATE));
        e.set_instrument_sample(0, 3);
        e.add_note(0, 0.5, 0.25, 60, 1.0);
        e.play();
        let (l, _) = run(&mut e, 24_000);
        let g = pan_gains(0.0).0 * 0.5;
        assert!(l[..12_000].iter().all(|&s| s == 0.0));
        assert!((l[14_000] - g).abs() < 1e-4, "{}", l[14_000]);
        // o release (0,2 s) passa do fim do bloco, mas o note off veio no quadro 18000
        assert!(l[23_999] < l[17_999]);
    }

    #[test]
    fn fm_e_wavetable_tocam_pelo_motor() {
        for kind in [instrument::kind::FM, instrument::kind::WAVETABLE] {
            let mut e = engine();
            e.set_tempo(120.0, 4);
            e.set_track_count(1);
            e.set_track_kind(0, kind);
            assert_eq!(e.track_kind(0), Some(kind));
            e.add_note(0, 0.0, 1.0, 60, 0.9);
            e.play();
            let (l, r) = run(&mut e, 12_000);
            assert!(l.iter().chain(&r).all(|s| s.is_finite()));
            assert!(l[2400..].iter().any(|s| s.abs() > 0.01), "tipo {kind} mudo");
            // os parâmetros chegam pelo mesmo caminho dos outros instrumentos
            e.set_param(0, 0, 1.0);
        }
    }

    #[test]
    fn audio_que_chega_depois_da_escolha_e_ligado() {
        let mut e = sampler_engine();
        e.set_instrument_sample(0, 9);
        e.live_on(0, 60, 1.0);
        let (l, _) = run(&mut e, 256);
        assert!(l.iter().all(|&s| s == 0.0), "sem áudio ainda: silêncio");
        e.load_sample(9, Sample::new(vec![vec![0.5; 48_000]], RATE));
        e.live_on(0, 60, 1.0);
        let (l, _) = run(&mut e, 256);
        assert!(l[200] > 0.3);
        // recriar o instrumento (troca de tipo e volta) religa o áudio guardado
        e.set_track_kind(0, instrument::kind::SYNTH);
        e.set_track_kind(0, instrument::kind::SAMPLER);
        e.set_param(0, instrument::sampler_param::VELOCITY, 0.0);
        e.live_on(0, 60, 1.0);
        let (l, _) = run(&mut e, 256);
        assert!(l[200] > 0.2);
    }

    #[test]
    fn caudas_soam_depois_do_stop() {
        let mut e = sampler_engine();
        e.set_param(0, instrument::sampler_param::RELEASE, 0.5);
        e.load_sample(3, Sample::new(vec![vec![0.5; 96_000]], RATE));
        e.set_instrument_sample(0, 3);
        e.add_note(0, 0.0, 4.0, 60, 1.0);
        e.play();
        run(&mut e, 4800);
        e.stop();
        let (l, _) = run(&mut e, 4800);
        assert!(l[4000] > 0.01, "o release continua depois do stop: {}", l[4000]);
        e.panic();
        let (l, _) = run(&mut e, 256);
        assert!(l.iter().all(|&s| s == 0.0));
    }

    // ------------------------------------------------------------ efeitos, roteamento, automação

    use effect::{Effect, auto_target, kind as fx_kind};

    /// O que um efeito de teste viu em cada bloco: primeira amostra da entrada (esq), primeira da
    /// chave (NaN sem chave) e o tamanho do bloco; e os parâmetros que recebeu.
    #[derive(Default)]
    struct Seen {
        input: Vec<f32>,
        key: Vec<f32>,
        frames: usize,
        params: Vec<(u32, f32)>,
        resets: usize,
    }

    type Shared = Arc<Mutex<Seen>>;

    /// Efeito de teste: multiplica pelo ganho, anota o que viu e devolve `meter`. Com `echo`,
    /// devolve a entrada de novo depois de `echo` quadros (um delay de um eco só).
    struct TestFx {
        gain: f32,
        seen: Shared,
        meter: f32,
        echo: usize,
        line: Vec<(f32, f32)>,
        at: usize,
        nan_once: bool,
    }

    impl TestFx {
        fn new(gain: f32) -> (Box<Self>, Shared) {
            let seen = Shared::default();
            (Box::new(Self { gain, seen: seen.clone(), meter: 0.0, echo: 0, line: Vec::new(), at: 0, nan_once: false }), seen)
        }

        fn echo(frames: usize) -> (Box<Self>, Shared) {
            let (mut fx, seen) = Self::new(1.0);
            fx.echo = frames;
            fx.line = vec![(0.0, 0.0); frames];
            (fx, seen)
        }
    }

    impl Effect for TestFx {
        fn set_param(&mut self, id: u32, value: f32) {
            self.seen.lock().unwrap().params.push((id, value));
        }
        fn process(&mut self, left: &mut [f32], right: &mut [f32]) {
            self.process_keyed(left, right, None);
        }
        fn process_keyed(&mut self, left: &mut [f32], right: &mut [f32], key: Option<(&[f32], &[f32])>) {
            {
                let mut s = self.seen.lock().unwrap();
                s.input.push(left[0]);
                s.key.push(key.map_or(f32::NAN, |(k, _)| k[0]));
                s.frames += left.len();
            }
            for (l, r) in left.iter_mut().zip(right.iter_mut()) {
                *l *= self.gain;
                *r *= self.gain;
                if self.echo > 0 {
                    let (dl, dr) = std::mem::replace(&mut self.line[self.at], (*l, *r));
                    self.at = (self.at + 1) % self.echo;
                    *l += dl;
                    *r += dr;
                }
            }
            if self.nan_once {
                self.nan_once = false;
                left[0] = f32::NAN;
            }
        }
        fn reset(&mut self) {
            self.seen.lock().unwrap().resets += 1;
            self.line.fill((0.0, 0.0));
        }
        fn meter(&self) -> f32 {
            self.meter
        }
    }

    /// Põe um efeito de teste no slot, já assentado (sem o fade de entrada).
    fn put(e: &mut Engine, track: i32, slot: usize, kind: u32, fx: Box<dyn Effect>) {
        let c = e.chain_mut(track).unwrap();
        if c.len() <= slot {
            c.set_count(slot + 1);
        }
        c.install(slot, kind, fx);
        c.snap();
        e.routing_dirty = true;
    }

    fn seen(s: &Shared) -> std::sync::MutexGuard<'_, Seen> {
        s.lock().unwrap()
    }

    /// Ganho do pan central (−3 dB).
    fn c() -> f32 {
        pan_gains(0.0).0
    }

    /// Motor com a faixa 0 tocando o clipe DC de 0,5 e mais `extra` faixas (as de `buses` viram
    /// barramentos), tocando.
    fn routed(extra: usize, buses: &[usize]) -> Engine {
        let mut e = engine_with_dc_clip(0.0, 2.0);
        e.set_track_count(1 + extra);
        for &b in buses {
            e.set_track_kind(b, instrument::kind::BUS);
        }
        e.play();
        e
    }

    fn max_jump(l: &[f32]) -> f32 {
        l.windows(2).map(|w| (w[0] - w[1]).abs()).fold(0.0, f32::max)
    }

    #[test]
    fn envio_pos_fader_chega_ao_barramento_com_o_nivel_certo() {
        let mut e = routed(1, &[1]);
        e.track_mut(0).unwrap().gain = 0.5;
        e.set_sends_count(0, 1);
        e.set_send(0, 0, 1, 0.25, false);
        let (tap, s) = TestFx::new(1.0);
        put(&mut e, 1, 0, fx_kind::EQ, tap);
        // o envio novo entra do zero (sem degrau no barramento)
        let (l, _) = run(&mut e, 4800);
        assert!(seen(&s).input[0].abs() < 0.001);
        let post = 0.5 * 0.5 * c();
        assert!((seen(&s).input.last().unwrap() - post * 0.25).abs() < 1e-6, "{:?}", seen(&s).input.last());
        // no master: a faixa direto e o barramento (pan central de novo)
        assert!((l[4700] - (post + post * 0.25 * c())).abs() < 1e-5, "{}", l[4700]);
        // nível 0: o barramento para de receber (suave)
        e.set_send(0, 0, 1, 0.0, false);
        run(&mut e, 4800);
        assert!(seen(&s).input.last().unwrap().abs() < 1e-6);
    }

    #[test]
    fn saida_roteada_para_o_barramento() {
        let mut e = routed(2, &[2]);
        e.set_output(0, 2);
        e.track_mut(2).unwrap().gain = 0.5;
        let (l, _) = run(&mut e, 1024);
        let expect = 0.5 * c() * 0.5 * c();
        assert!((l[1000] - expect).abs() < 1e-5, "{}", l[1000]);
        assert!(e.tracks[2].take_peaks().0 > 0.0);
        // mudo do barramento cala o que sai nele
        e.track_mut(2).unwrap().mute = true;
        let (l, _) = run(&mut e, 4800);
        assert!(l[4799].abs() < 1e-6);
        // destino que não é barramento vale como master
        e.track_mut(2).unwrap().mute = false;
        e.set_output(0, 1);
        let (l, _) = run(&mut e, 128);
        assert!((l[100] - 0.5 * c()).abs() < 1e-5, "{}", l[100]);
    }

    #[test]
    fn barramento_so_sai_para_barramento_de_indice_maior() {
        // faixa 0 → barramento 2 → barramento 1: o 1 é processado antes do 2, a saída vira master
        let mut e = routed(2, &[1, 2]);
        e.set_output(0, 2);
        e.set_output(2, 1);
        e.track_mut(1).unwrap().gain = 0.0;
        let (l, _) = run(&mut e, 256);
        assert!((l[200] - 0.5 * c() * c()).abs() < 1e-5, "{}", l[200]);
        // e um envio para trás é ignorado
        e.set_output(2, -1);
        e.set_sends_count(2, 1);
        e.set_send(2, 0, 1, 1.0, false);
        let (l, _) = run(&mut e, 256);
        assert!((l[200] - 0.5 * c() * c()).abs() < 1e-5, "{}", l[200]);
    }

    #[test]
    fn mudo_da_origem_corta_o_envio_pos_mas_nao_o_pre() {
        let mut e = routed(2, &[1, 2]);
        e.track_mut(0).unwrap().gain = 0.5;
        e.set_sends_count(0, 2);
        e.set_send(0, 0, 1, 1.0, false);
        e.set_send(0, 1, 2, 0.5, true);
        let (post, sp) = TestFx::new(1.0);
        let (pre, sq) = TestFx::new(1.0);
        put(&mut e, 1, 0, fx_kind::EQ, post);
        put(&mut e, 2, 0, fx_kind::EQ, pre);
        run(&mut e, 4800);
        assert!((seen(&sp).input.last().unwrap() - 0.5 * 0.5 * c()).abs() < 1e-6);
        // o pré-fader não passa pelo volume nem pelo pan
        assert!((seen(&sq).input.last().unwrap() - 0.25).abs() < 1e-6);
        e.track_mut(0).unwrap().mute = true;
        run(&mut e, 4800);
        assert!(seen(&sp).input.last().unwrap().abs() < 1e-6);
        assert!((seen(&sq).input.last().unwrap() - 0.25).abs() < 1e-6);
    }

    #[test]
    fn solo_com_barramentos() {
        // 0 → barramento 2; 1 → master e envia para o barramento 3 (retorno)
        let mut e = routed(3, &[2, 3]);
        e.add_clip(Clip { track: 1, sample: 1, start: 0.0, offset: 0.0, length: 2.0, gain: 1.0, fade_in: 0.0, fade_out: 0.0 });
        e.set_output(0, 2);
        e.set_sends_count(1, 1);
        e.set_send(1, 0, 3, 1.0, false);
        let (ret, sr) = TestFx::new(1.0);
        put(&mut e, 3, 0, fx_kind::REVERB, ret);
        // solo da 0: o barramento 2 que ela alimenta continua audível; a 1 e o retorno não
        e.track_mut(0).unwrap().solo = true;
        let (l, _) = run(&mut e, 4800);
        assert!((l[4799] - 0.5 * c() * c()).abs() < 1e-4, "{}", l[4799]);
        assert!(seen(&sr).input.last().unwrap().abs() < 1e-6, "o envio da faixa calada pelo solo para");
        // solo do barramento 2: a faixa que sai nele soa
        e.track_mut(0).unwrap().solo = false;
        e.track_mut(2).unwrap().solo = true;
        let (l, _) = run(&mut e, 4800);
        assert!((l[4799] - 0.5 * c() * c()).abs() < 1e-4, "{}", l[4799]);
        // solo do retorno: só ele soa, com o que chega pelos envios
        e.track_mut(2).unwrap().solo = false;
        e.track_mut(3).unwrap().solo = true;
        let (l, _) = run(&mut e, 4800);
        assert!((seen(&sr).input.last().unwrap() - 0.5 * c()).abs() < 1e-5);
        assert!((l[4799] - 0.5 * c() * c()).abs() < 1e-4, "{}", l[4799]);
    }

    #[test]
    fn bypass_sem_estalo() {
        let mut e = engine_with_dc_clip(0.0, 2.0);
        let (fx, s) = TestFx::new(2.0);
        put(&mut e, 0, 0, fx_kind::UTILITY, fx);
        e.play();
        let (l, _) = run(&mut e, 256);
        let dry = 0.5 * c();
        assert!((l[200] - 2.0 * dry).abs() < 1e-5);
        e.set_fx_bypass(0, 0, true);
        let (l, _) = run(&mut e, 1280);
        assert!(max_jump(&l) < 0.01, "{}", max_jump(&l));
        assert!((l[1279] - dry).abs() < 1e-6, "{}", l[1279]);
        // assentado em bypass, o efeito nem roda
        let frames = seen(&s).frames;
        run(&mut e, 256);
        assert_eq!(seen(&s).frames, frames);
        // ao voltar, esquece o estado velho e entra suave
        e.set_fx_bypass(0, 0, false);
        assert_eq!(seen(&s).resets, 1);
        let (l, _) = run(&mut e, 1280);
        assert!(max_jump(&l) < 0.01, "{}", max_jump(&l));
        assert!((l[1279] - 2.0 * dry).abs() < 1e-5);
    }

    #[test]
    fn trocar_o_efeito_por_crossfade_e_o_mesmo_tipo_nao_recria() {
        let mut e = engine_with_dc_clip(0.0, 2.0);
        let (fx, s) = TestFx::new(2.0);
        put(&mut e, 0, 0, fx_kind::UTILITY, fx);
        e.play();
        run(&mut e, 256);
        // o mesmo tipo de novo (o app manda a cada sync) não mexe no efeito
        e.set_fx(0, 0, fx_kind::UTILITY);
        run(&mut e, 256);
        assert_eq!(seen(&s).frames, 512);
        // outro tipo: um efeito de ganho 1 no lugar; a troca é um crossfade
        e.set_fx(0, 0, fx_kind::EQ);
        let (unity, _) = TestFx::new(1.0);
        e.strips[0].chain.install(0, fx_kind::EQ, unity);
        let (l, _) = run(&mut e, 1280);
        assert!(max_jump(&l) < 0.01, "{}", max_jump(&l));
        assert!((l[1279] - 0.5 * c()).abs() < 1e-5);
        assert!(e.strips[0].chain.slot(0).is_some_and(|s| s.kind == fx_kind::EQ));
        // o antigo sai de vez entre um bloco e outro
        let frames = seen(&s).frames;
        run(&mut e, 256);
        assert_eq!(seen(&s).frames, frames);
        // esvaziar e encolher a cadeia também desce sem degrau
        let (fx, _) = TestFx::new(0.25);
        put(&mut e, 0, 1, fx_kind::UTILITY, fx);
        run(&mut e, 256);
        e.set_fx_count(0, 1);
        let (l, _) = run(&mut e, 1280);
        assert!(max_jump(&l) < 0.01, "{}", max_jump(&l));
        assert!((l[1279] - 0.5 * c()).abs() < 1e-5);
        run(&mut e, 128);
        assert_eq!(e.strips[0].chain.slots_len(), 1);
        let (fx, _) = TestFx::new(0.25);
        put(&mut e, 0, 0, fx_kind::UTILITY, fx);
        run(&mut e, 256);
        e.set_fx(0, 0, 0);
        let (l, _) = run(&mut e, 1280);
        assert!(max_jump(&l) < 0.01, "{}", max_jump(&l));
        assert!((l[1279] - 0.5 * c()).abs() < 1e-5);
        assert!(!e.strips[0].chain.live());
    }

    #[test]
    fn automacao_de_volume() {
        let mut e = engine_with_dc_clip(0.0, 4.0);
        e.track_mut(0).unwrap().gain = 1.0;
        let lane = e.add_lane(0, auto_target::VOLUME, 0, 0);
        e.add_point(lane, 1.0, 0.0, 0.0);
        e.add_point(lane, 2.0, 1.0, 0.0);
        e.play();
        let (l, _) = run(&mut e, 48_000);
        let dry = 0.5 * c();
        // antes do primeiro ponto vale o primeiro
        assert!(l[12_000].abs() < 1e-6, "{}", l[12_000]);
        // no meio da rampa (o fader segue com 5 ms de atraso)
        assert!((l[36_000] - 0.5 * dry).abs() < 0.01, "{}", l[36_000]);
        assert!(max_jump(&l) < 0.001, "sem degraus: {}", max_jump(&l));
        // depois do último, o último
        let (l, _) = run(&mut e, 24_000);
        assert!((l[20_000] - dry).abs() < 1e-5);
        // parado, volta o estático (que a automação não apagou)
        e.track_mut(0).unwrap().gain = 0.3;
        e.stop();
        run(&mut e, 128);
        assert_eq!(e.tracks[0].effective().0, 0.3);
        // tocando de novo, a automação volta
        e.seek(1.5);
        e.play();
        run(&mut e, 128);
        assert!((e.tracks[0].effective().0 - 0.5).abs() < 0.01);
        // reenviar sem a lane devolve o estático mesmo tocando
        e.clear_automation();
        run(&mut e, 128);
        assert_eq!(e.tracks[0].effective().0, 0.3);
    }

    #[test]
    fn curva_da_automacao() {
        let mut lane = AutoLane::new();
        lane.points.push(AutoPoint { beat: 0.0, value: 0.0, curve: 1.0 });
        lane.points.push(AutoPoint { beat: 1.0, value: 1.0, curve: 0.0 });
        // curva 1: t^8
        assert!((lane.value_at(0.5).unwrap() - 0.5f32.powi(8)).abs() < 1e-6);
        lane.points[0].curve = -1.0;
        assert!((lane.value_at(0.5).unwrap() - 0.5f32.powf(0.125)).abs() < 1e-6);
        // dois pontos na mesma batida: salto, vale o de depois
        lane.points = vec![
            AutoPoint { beat: 0.0, value: 0.2, curve: 0.0 },
            AutoPoint { beat: 1.0, value: 0.2, curve: 0.0 },
            AutoPoint { beat: 1.0, value: 0.9, curve: 0.0 },
        ];
        assert_eq!(lane.value_at(0.99).unwrap(), 0.2);
        assert_eq!(lane.value_at(1.0).unwrap(), 0.9);
        assert!(AutoLane::new().value_at(1.0).is_none());
        // pontos fora de ordem são inseridos no lugar; os da mesma batida na ordem de chegada
        let mut e = engine();
        let i = e.add_lane(-1, auto_target::VOLUME, 0, 0);
        e.add_point(i, 2.0, 1.0, 0.0);
        e.add_point(i, 1.0, 0.5, 0.0);
        e.add_point(i, 1.0, 0.7, 0.0);
        e.add_point(i, f64::NAN, 0.7, 0.0);
        e.add_point(9, 1.0, 0.7, 0.0);
        let beats: Vec<(f64, f32)> = e.auto[0].points.iter().map(|p| (p.beat, p.value)).collect();
        assert_eq!(beats, vec![(1.0, 0.5), (1.0, 0.7), (2.0, 1.0)]);
    }

    #[test]
    fn automacao_de_efeito_envio_e_master() {
        let mut e = routed(1, &[1]);
        let (fx, s) = TestFx::new(1.0);
        put(&mut e, 0, 0, fx_kind::FILTER, fx);
        e.stop();
        e.set_fx_param(0, 0, 3, 10.0);
        let lane = e.add_lane(0, auto_target::EFFECT, 0, 3);
        e.add_point(lane, 0.0, 100.0, 0.0);
        e.add_point(lane, 4.0, 200.0, 0.0);
        e.set_sends_count(0, 1);
        e.set_send(0, 0, 1, 1.0, false);
        let send = e.add_lane(0, auto_target::SEND, 0, 0);
        e.add_point(send, 0.0, 0.25, 0.0);
        let master = e.add_lane(-1, auto_target::VOLUME, 0, 0);
        e.add_point(master, 0.0, 0.5, 0.0);
        e.seek(0.0);
        e.play();
        run(&mut e, 256);
        let last = *seen(&s).params.last().unwrap();
        assert_eq!(last.0, 3);
        assert!((100.0..101.0).contains(&last.1), "{last:?}");
        assert_eq!(e.strips[0].sends[0].auto_level, Some(0.25));
        assert_eq!(e.master.effective().0, 0.5);
        // o app mexe no botão tocando: fica guardado, a automação segue no comando
        e.set_fx_param(0, 0, 3, 20.0);
        assert!(seen(&s).params.iter().all(|&(_, v)| v != 20.0));
        e.stop();
        run(&mut e, 128);
        assert_eq!(*seen(&s).params.last().unwrap(), (3, 20.0));
        assert_eq!(e.strips[0].sends[0].auto_level, None);
        assert_eq!(e.master.effective().0, 1.0);
    }

    #[test]
    fn automacao_de_instrumento_volta_ao_estatico() {
        let (mut e, _) = probe_engine();
        struct Param(Arc<Mutex<Vec<(u32, f32)>>>);
        impl Instrument for Param {
            fn note_on(&mut self, _: u8, _: f32) {}
            fn note_off(&mut self, _: u8) {}
            fn release_all(&mut self) {}
            fn silence(&mut self) {}
            fn set_param(&mut self, id: u32, value: f32) {
                self.0.lock().unwrap().push((id, value));
            }
            fn render(&mut self, _: &mut [f32], _: &mut [f32]) {}
            fn active(&self) -> bool {
                false
            }
        }
        let log = Arc::new(Mutex::new(Vec::new()));
        e.lanes[0].instrument = Some(Box::new(Param(log.clone())));
        e.set_param(0, 13, 5000.0);
        let lane = e.add_lane(0, auto_target::INSTRUMENT, 7, 13);
        e.add_point(lane, 0.0, 300.0, 0.0);
        e.play();
        run(&mut e, 256);
        // valor constante: aplicado uma vez só, não a cada passo
        assert_eq!(*log.lock().unwrap(), vec![(13, 5000.0), (13, 300.0)]);
        e.set_param(0, 13, 800.0);
        e.stop();
        run(&mut e, 128);
        assert_eq!(*log.lock().unwrap(), vec![(13, 5000.0), (13, 300.0), (13, 800.0)]);
    }

    #[test]
    fn sidechain_entrega_a_chave() {
        // 0: a faixa com o compressor (e o clipe); 1: a chave, com clipe próprio e volume baixo
        let mut e = routed(2, &[2]);
        e.add_clip(Clip { track: 1, sample: 1, start: 0.0, offset: 0.0, length: 2.0, gain: 0.5, fade_in: 0.0, fade_out: 0.0 });
        e.track_mut(1).unwrap().gain = 0.1;
        let (comp, s) = TestFx::new(1.0);
        put(&mut e, 0, 0, fx_kind::COMPRESSOR, comp);
        e.set_fx_param(0, 0, effect::compressor_param::SIDECHAIN, 1.0);
        run(&mut e, 128);
        // chave pós-inserts e pré-fader, do mesmo bloco mesmo com índice maior (a chave vem antes)
        assert!((seen(&s).key[0] - 0.25).abs() < 1e-6, "{:?}", seen(&s).key);
        // o parâmetro também chega ao efeito
        assert!(seen(&s).params.contains(&(effect::compressor_param::SIDECHAIN, 1.0)));
        // −1: a própria entrada (sem chave externa)
        e.set_fx_param(0, 0, effect::compressor_param::SIDECHAIN, -1.0);
        run(&mut e, 128);
        assert!(seen(&s).key.last().unwrap().is_nan());
        // um barramento como chave é processado depois: vale a saída do bloco anterior
        e.set_sends_count(1, 1);
        e.set_send(1, 0, 2, 1.0, true);
        e.set_fx_param(0, 0, effect::compressor_param::SIDECHAIN, 2.0);
        run(&mut e, 128);
        assert_eq!(*seen(&s).key.last().unwrap(), 0.0, "primeiro bloco: a chave ainda está vazia");
        // (o envio novo entra do zero em 5 ms)
        run(&mut e, 4800);
        assert!((seen(&s).key.last().unwrap() - 0.25).abs() < 1e-6, "{:?}", seen(&s).key.last());
        // no gate também
        let (gate, g) = TestFx::new(1.0);
        put(&mut e, 0, 1, fx_kind::GATE, gate);
        e.set_fx_param(0, 1, effect::gate_param::SIDECHAIN, 1.0);
        run(&mut e, 128);
        assert!((seen(&g).key[0] - 0.25).abs() < 1e-6);
        // a chave não é automatizável
        let lane = e.add_lane(0, auto_target::EFFECT, 1, effect::gate_param::SIDECHAIN);
        e.add_point(lane, 0.0, 0.0, 0.0);
        run(&mut e, 128);
        assert!((seen(&g).key.last().unwrap() - 0.25).abs() < 1e-6);
    }

    #[test]
    fn efeito_no_master_roda_antes_do_volume_e_do_limitador() {
        let mut e = Engine::new(RATE);
        e.set_track_count(1);
        e.load_sample(1, Sample::new(vec![vec![0.5; 96_000]], RATE));
        e.add_clip(Clip { track: 0, sample: 1, start: 0.0, offset: 0.0, length: 2.0, gain: 1.0, fade_in: 0.0, fade_out: 0.0 });
        e.master_mut().gain = 0.5;
        let (fx, s) = TestFx::new(8.0);
        put(&mut e, -1, 0, fx_kind::UTILITY, fx);
        e.play();
        let (l, _) = run(&mut e, 4800);
        // o efeito vê a soma antes do volume do master (inserts antes do fader)
        assert!((seen(&s).input[10] - 0.5 * c()).abs() < 1e-6);
        // 0,35 × 8 × 0,5 = 1,4 antes do limitador: ele segura no teto (depois dele, a trava daria 1)
        let max = l.iter().fold(0.0f32, |m, v| m.max(v.abs()));
        assert!(max <= 0.967 && l[4000] > 0.9, "{max} {}", l[4000]);
        assert!(e.take_limiter_gain() < 0.8);
    }

    #[test]
    fn caudas_dos_efeitos_depois_do_clipe_e_cadeia_parada_no_silencio() {
        // clipe de 0,1 s; eco de 1 s num "delay": o eco soa com o clipe já terminado
        let mut e = engine_with_dc_clip(0.0, 0.1);
        let (fx, s) = TestFx::echo(48_000);
        put(&mut e, 0, 0, fx_kind::DELAY, fx);
        e.play();
        let (l, _) = run(&mut e, 72_000);
        assert!(l[20_000].abs() < 1e-6);
        assert!((l[50_000] - 0.5 * c()).abs() < 1e-5, "o eco: {}", l[50_000]);
        // depois do eco e do silêncio de segurança do delay, a cadeia para de rodar
        run(&mut e, (4.6 * RATE) as usize);
        let frames = seen(&s).frames;
        run(&mut e, 4800);
        assert_eq!(seen(&s).frames, frames);
        assert!(e.strips[0].idle);
        // a entrada volta: roda de novo
        e.seek(0.0);
        run(&mut e, 128);
        assert!(seen(&s).frames > frames);
        // num efeito sem cauda longa, a parada vem logo (50 ms)
        let mut e = engine_with_dc_clip(0.0, 0.1);
        let (fx, s) = TestFx::new(1.0);
        put(&mut e, 0, 0, fx_kind::EQ, fx);
        e.play();
        run(&mut e, 4800 + 2400 + 256);
        let frames = seen(&s).frames;
        run(&mut e, 4800);
        assert_eq!(seen(&s).frames, frames);
        assert!(frames < 4800 + 2400 + 256);
    }

    #[test]
    fn nan_de_um_efeito_vira_silencio_e_reinicia_o_efeito() {
        let mut e = routed(1, &[1]);
        e.set_output(0, 1);
        let (mut fx, s) = TestFx::new(1.0);
        fx.nan_once = true;
        put(&mut e, 0, 0, fx_kind::EQ, fx);
        let (l, _) = run(&mut e, 256);
        assert!(l.iter().all(|v| v.is_finite()));
        assert!(l[..128].iter().all(|&v| v == 0.0));
        assert!((l[200] - 0.5 * c() * c()).abs() < 1e-5, "{}", l[200]);
        assert_eq!(seen(&s).resets, 1);
    }

    #[test]
    fn indicador_do_efeito_observado() {
        let mut e = engine_with_dc_clip(0.0, 1.0);
        let (mut fx, _) = TestFx::new(1.0);
        fx.meter = 4.5;
        put(&mut e, 0, 2, fx_kind::COMPRESSOR, fx);
        assert_eq!(e.fx_meter(), 0.0);
        e.watch_fx(0, 2);
        assert_eq!(e.fx_meter(), 4.5);
        e.watch_fx(0, 1);
        assert_eq!(e.fx_meter(), 0.0);
        e.watch_fx(7, 2);
        assert_eq!(e.fx_meter(), 0.0);
        e.watch_fx(0, -1);
        assert_eq!(e.fx_meter(), 0.0);
    }

    #[test]
    fn analisador_da_faixa_e_do_master() {
        let mut e = engine();
        e.set_track_count(2);
        // senoide na faixa 25 de uma FFT de 2048 pontos, na faixa 0
        let f = 25.0 * RATE / 2048.0;
        let sine: Vec<f32> = (0..96_000).map(|i| (std::f64::consts::TAU * f * i as f64 / RATE).sin() as f32).collect();
        e.load_sample(1, Sample::new(vec![sine], RATE));
        e.add_clip(Clip { track: 0, sample: 1, start: 0.0, offset: 0.0, length: 2.0, gain: 1.0, fade_in: 0.0, fade_out: 0.0 });
        let mut out = vec![0.0; 1024];
        assert_eq!(e.analyzer(&mut out), 0, "nada observado");
        e.watch_analyzer(0);
        e.play();
        run(&mut e, 4096);
        assert_eq!(e.analyzer(&mut out), 1024);
        let peak = out.iter().enumerate().fold((0, f32::MIN), |b, (i, &v)| if v > b.1 { (i, v) } else { b });
        assert_eq!(peak.0, 25);
        // pós-fader: pan central (−3 dB), mono = média dos canais
        assert!((peak.1 - 20.0 * c().log10()).abs() < 0.2, "{peak:?}");
        // a faixa 1 está calada
        e.watch_analyzer(1);
        run(&mut e, 4096);
        e.analyzer(&mut out);
        assert!(out.iter().all(|&v| v == analyzer::FLOOR_DB));
        // o master
        e.watch_analyzer(-1);
        run(&mut e, 4096);
        e.analyzer(&mut out);
        assert!(out[25] > -4.0, "{}", out[25]);
        e.watch_analyzer(-2);
        assert_eq!(e.analyzer(&mut out), 0);
    }

    #[test]
    fn efeitos_recebem_o_andamento() {
        struct Bpm(Arc<Mutex<f64>>);
        impl Effect for Bpm {
            fn set_param(&mut self, _: u32, _: f32) {}
            fn process(&mut self, _: &mut [f32], _: &mut [f32]) {}
            fn reset(&mut self) {}
            fn set_tempo(&mut self, bpm: f64) {
                *self.0.lock().unwrap() = bpm;
            }
        }
        let mut e = engine();
        e.set_tempo(90.0, 4);
        e.set_track_count(1);
        let bpm = Arc::new(Mutex::new(0.0));
        put(&mut e, 0, 0, fx_kind::DELAY, Box::new(Bpm(bpm.clone())));
        assert_eq!(*bpm.lock().unwrap(), 90.0, "ao nascer");
        e.set_tempo(140.0, 4);
        assert_eq!(*bpm.lock().unwrap(), 140.0);
        let master = Arc::new(Mutex::new(0.0));
        put(&mut e, -1, 0, fx_kind::DELAY, Box::new(Bpm(master.clone())));
        e.set_tempo(100.0, 4);
        assert_eq!(*master.lock().unwrap(), 100.0);
    }

    #[test]
    fn tipo_e_envio_antes_da_contagem_valem() {
        let mut e = routed(1, &[1]);
        // o app pode mandar o tipo antes do `fx_count` e o envio antes do `sends_count`
        e.set_fx(0, 2, fx_kind::EQ);
        assert_eq!(e.strips[0].chain.len(), 3);
        assert!(e.strips[0].chain.slot(2).is_some_and(|s| s.kind == fx_kind::EQ));
        e.set_fx_count(0, 3);
        assert!(e.strips[0].chain.slot(2).is_some_and(|s| s.kind == fx_kind::EQ));
        // esvaziar um slot que não existe não estica nada; além do máximo é ignorado
        e.set_fx(0, 5, 0);
        e.set_fx(0, MAX_SLOTS, fx_kind::EQ);
        assert_eq!(e.strips[0].chain.len(), 3);
        e.set_send(0, 1, 1, 0.5, false);
        e.set_sends_count(0, 2);
        assert_eq!(e.strips[0].sends.len(), 2);
        assert_eq!(e.strips[0].sends[1].bus, 1);
        e.set_send(0, MAX_SENDS, 1, 0.5, false);
        assert_eq!(e.strips[0].sends.len(), 2);
        run(&mut e, 128);
        assert_eq!(e.strips[0].sends[1].dst, 1);
    }

    #[test]
    fn efeitos_reais_na_cadeia_nao_quebram_o_motor() {
        // todos os tipos, em todas as faixas e no master, com parâmetros nos extremos
        let mut e = Engine::new(RATE);
        e.set_track_count(3);
        e.set_track_kind(1, instrument::kind::SYNTH);
        e.set_track_kind(2, instrument::kind::BUS);
        e.load_sample(1, Sample::new(vec![(0..96_000).map(|i| ((i as f32) * 0.03).sin() * 0.8).collect()], RATE));
        e.add_clip(Clip { track: 0, sample: 1, start: 0.0, offset: 0.0, length: 2.0, gain: 1.0, fade_in: 0.0, fade_out: 0.0 });
        e.add_note(1, 0.0, 2.0, 60, 1.0);
        e.set_output(1, 2);
        e.set_sends_count(0, 1);
        e.set_send(0, 0, 2, 0.7, false);
        for t in [-1, 0, 1, 2] {
            e.set_fx_count(t, 12);
            for k in 1..=12u32 {
                e.set_fx(t, k as usize - 1, k);
                for id in 0..50 {
                    e.set_fx_param(t, k as usize - 1, id, if id % 2 == 0 { 1e9 } else { -1e9 });
                }
            }
        }
        e.play();
        let (l, r) = run(&mut e, 48_000);
        assert!(l.iter().chain(&r).all(|v| v.is_finite() && v.abs() <= 1.0));
    }

    // ------------------------------------------------------------ gravação e render

    /// Roda `frames` quadros em blocos de 128 entregando a cada bloco a entrada constante `left`
    /// (e `right`; `None` = mono).
    fn run_input(e: &mut Engine, frames: usize, left: f32, right: Option<f32>) -> (Vec<f32>, Vec<f32>) {
        let (mut l, mut r) = (vec![0.0; frames], vec![0.0; frames]);
        for (cl, cr) in l.chunks_mut(128).zip(r.chunks_mut(128)) {
            let il = vec![left; cl.len()];
            let ir = right.map(|v| vec![v; cl.len()]);
            e.set_input(&il, ir.as_deref());
            e.process(cl, cr);
        }
        (l, r)
    }

    #[test]
    fn monitor_soma_a_entrada_na_faixa_e_passa_pelos_efeitos() {
        let mut e = engine();
        e.set_track_count(2);
        let (fx, s) = TestFx::new(2.0);
        put(&mut e, 0, 0, fx_kind::UTILITY, fx);
        // sem monitorar, a entrada não soa
        let (l, _) = run_input(&mut e, 256, 0.1, None);
        assert!(l.iter().all(|&v| v == 0.0));
        e.set_monitor(0, true);
        let (l, r) = run_input(&mut e, 256, 0.1, Some(0.05));
        // pelos inserts (×2) e pelo pan central, com o transporte parado
        assert!((l[200] - 0.2 * c()).abs() < 1e-6, "{}", l[200]);
        assert!((r[200] - 0.1 * c()).abs() < 1e-6, "{}", r[200]);
        assert!((seen(&s).input.last().unwrap() - 0.1).abs() < 1e-7, "a entrada chega antes do efeito");
        // mono vale nos dois lados
        let (_, r) = run_input(&mut e, 128, 0.1, None);
        assert!((r[100] - 0.2 * c()).abs() < 1e-6);
        // bloco sem entrada entregue: nada (o efeito de teste não tem cauda)
        let (l, _) = run(&mut e, 256);
        assert!(l.iter().all(|&v| v == 0.0), "{:?}", &l[..4]);
        // entrada mais curta que o bloco: o resto é silêncio
        e.set_input(&[0.1; 64], None);
        let (mut l, mut r) = (vec![0.0; 128], vec![0.0; 128]);
        e.process(&mut l, &mut r);
        assert!(l[63] > 0.1 && l[64] == 0.0, "{} {}", l[63], l[64]);
        // amostra inválida vira silêncio, sem estragar a cadeia
        e.set_input(&[f32::NAN; 128], Some(&[f32::INFINITY; 128]));
        e.process(&mut l, &mut r);
        assert!(l.iter().chain(&r).all(|&v| v == 0.0));
        assert_eq!(seen(&s).resets, 0);
        // fader e mudo valem
        e.track_mut(0).unwrap().gain = 0.5;
        let (l, _) = run_input(&mut e, 4800, 0.1, None);
        assert!((l[4799] - 0.1 * c()).abs() < 1e-5, "{}", l[4799]);
        e.track_mut(0).unwrap().mute = true;
        let (l, _) = run_input(&mut e, 4800, 0.1, None);
        assert!(l[4799].abs() < 1e-6);
        e.track_mut(0).unwrap().mute = false;
        // solo de outra faixa cala
        e.track_mut(1).unwrap().solo = true;
        let (l, _) = run_input(&mut e, 4800, 0.1, None);
        assert!(l[4799].abs() < 1e-6);
        e.track_mut(1).unwrap().solo = false;
        // roteada para um barramento, sai por ele
        e.set_track_kind(1, instrument::kind::BUS);
        e.set_output(0, 1);
        e.track_mut(1).unwrap().gain = 0.5;
        let (l, _) = run_input(&mut e, 4800, 0.1, None);
        assert!((l[4799] - 0.1 * c() * 0.5 * c()).abs() < 1e-5, "{}", l[4799]);
        // tocando, soma com os clipes da faixa
        e.set_output(0, -1);
        e.load_sample(1, Sample::new(vec![vec![0.5; 96_000]], RATE));
        e.add_clip(Clip { track: 0, sample: 1, start: 0.0, offset: 0.0, length: 1.0, gain: 1.0, fade_in: 0.0, fade_out: 0.0 });
        e.play();
        let (l, _) = run_input(&mut e, 4800, 0.1, None);
        assert!((l[4799] - 0.6 * c()).abs() < 1e-5, "{}", l[4799]);
        // e parar não leva a entrada junto no fade dos clipes
        e.stop();
        let (l, _) = run_input(&mut e, 4800, 0.1, None);
        assert!((l[4799] - 0.1 * c()).abs() < 1e-5, "{}", l[4799]);
        // faixa de instrumento não monitora
        e.set_track_kind(0, instrument::kind::SYNTH);
        let (l, _) = run_input(&mut e, 4800, 0.1, None);
        assert!(l[4000..].iter().all(|&v| v == 0.0));
    }

    fn rec_read(e: &mut Engine) -> Vec<[f32; 5]> {
        let mut out = vec![0.0f32; 500];
        let n = e.rec_notes(&mut out);
        out[..n].as_chunks::<5>().0.to_vec()
    }

    #[test]
    fn rec_notes_com_a_batida_do_quadro_e_nada_parado() {
        let (mut e, _) = probe_engine();
        e.rec_notes_start();
        // parado não entra
        e.live_on(0, 60, 0.8);
        run(&mut e, 256);
        e.live_off(0, 60);
        assert!(rec_read(&mut e).is_empty());
        e.play();
        run(&mut e, 24_000); // batida 1
        e.live_on(0, 60, 0.8);
        run(&mut e, 12_000); // 1,5
        e.live_off(0, 60);
        e.live_on(0, 62, 0.5);
        run(&mut e, 100); // fora da grade dos blocos
        e.live_on(0, 64, 1.0);
        e.live_on(7, 64, 1.0); // faixa inexistente não entra
        run(&mut e, 5900); // 1,75
        e.live_on(0, 64, 0.0); // velocidade 0 solta
        e.rec_notes_stop(); // a 62, ainda segurada, termina aqui
        e.live_off(0, 62);
        let at = b(36_100.0) as f32;
        assert_eq!(rec_read(&mut e), vec![[0.0, 60.0, 1.0, 1.5, 0.8], [0.0, 62.0, 1.5, 1.75, 0.5], [0.0, 64.0, at, 1.75, 1.0]]);
        assert!(rec_read(&mut e).is_empty(), "a leitura zera");
        // sem gravar, nada
        e.live_on(0, 60, 0.8);
        run(&mut e, 128);
        e.live_off(0, 60);
        assert!(rec_read(&mut e).is_empty());
    }

    #[test]
    fn rec_notes_seguradas_na_volta_do_loop_no_seek_e_no_stop() {
        let (mut e, _) = probe_engine();
        e.set_loop(true, 0.0, 1.0);
        e.rec_notes_start();
        e.play();
        run(&mut e, 18_000); // 0,75
        e.live_on(0, 60, 1.0);
        run(&mut e, 12_000); // passa da volta: 0,25
        e.live_off(0, 60);
        e.live_on(0, 62, 1.0);
        run(&mut e, 6000); // 0,5
        e.seek(0.125);
        run(&mut e, 3000); // 0,25
        // parar fecha a segurada onde parou, e o que vem depois não muda nada
        e.stop();
        e.seek(0.0);
        e.live_off(0, 62);
        // leitura ainda gravando: a nota segurada termina na posição atual
        e.play();
        e.live_on(0, 67, 1.0);
        run(&mut e, 2400);
        assert_eq!(
            rec_read(&mut e),
            vec![
                [0.0, 60.0, 0.75, 1.0, 1.0],
                [0.0, 60.0, 0.0, 0.25, 1.0],
                [0.0, 62.0, 0.25, 0.5, 1.0],
                [0.0, 62.0, 0.125, 0.25, 1.0],
                [0.0, 67.0, 0.0, 0.1, 1.0]
            ]
        );
    }

    type Channels = (Vec<f32>, Vec<f32>);

    /// Renderiza como o render fora de tempo real faz: capturas das saídas pedidas, depois
    /// `seek`/`play` e blocos de `blocks(i)` quadros. Devolve (esq, dir) de cada captura, na
    /// ordem de `outputs`, e o que o `process` devolveu.
    fn render_offline(e: &mut Engine, outputs: &[i32], from: f64, frames: usize, blocks: &dyn Fn(usize) -> usize) -> (Vec<Channels>, Channels) {
        e.capture_clear();
        let idx: Vec<i32> = outputs.iter().map(|&t| e.capture_add(t)).collect();
        e.seek(from);
        e.play();
        let mut caps = vec![(Vec::with_capacity(frames), Vec::with_capacity(frames)); outputs.len()];
        let (mut out_l, mut out_r) = (Vec::with_capacity(frames), Vec::with_capacity(frames));
        let (mut l, mut r) = (vec![0.0; MAX_BLOCK], vec![0.0; MAX_BLOCK]);
        let (mut cl, mut cr) = (vec![0.0; MAX_BLOCK], vec![0.0; MAX_BLOCK]);
        let mut done = 0;
        let mut i = 0;
        while done < frames {
            let n = blocks(i).min(frames - done);
            e.process(&mut l[..n], &mut r[..n]);
            out_l.extend_from_slice(&l[..n]);
            out_r.extend_from_slice(&r[..n]);
            for (c, &k) in caps.iter_mut().zip(&idx) {
                assert_eq!(e.captured(k as usize, &mut cl[..n], &mut cr[..n]), n);
                c.0.extend_from_slice(&cl[..n]);
                c.1.extend_from_slice(&cr[..n]);
            }
            done += n;
            i += 1;
        }
        (caps, (out_l, out_r))
    }

    #[test]
    fn capturas_de_faixa_e_master_batem_com_o_que_sai() {
        // com o limitador do master ligado: a latência dele é compensada e tudo sai alinhado
        let mut e = Engine::new(RATE);
        e.set_tempo(120.0, 4);
        e.set_track_count(3);
        e.load_sample(1, Sample::new(vec![vec![0.25; 96_000]], RATE));
        e.add_clip(Clip { track: 0, sample: 1, start: 0.5, offset: 0.0, length: 1.0, gain: 1.0, fade_in: 0.0, fade_out: 0.0 });
        e.add_clip(Clip { track: 1, sample: 1, start: 0.0, offset: 0.0, length: 0.25, gain: 0.5, fade_in: 0.0, fade_out: 0.0 });
        e.track_mut(1).unwrap().pan = -1.0;
        assert!(e.latency > 0);
        let (caps, (out_l, out_r)) = render_offline(&mut e, &[-1, 0, 1, 2, 9], 0.25, 30_000, &|_| 4096);
        let [m, a, b1, quiet, missing] = &caps[..] else { unreachable!() };
        // o master capturado é exatamente o que saiu
        assert_eq!(&m.0, &out_l);
        assert_eq!(&m.1, &out_r);
        // a faixa 0 entra na batida 0,5: quadro 6000 do render (que começou em 0,25)
        let g = 0.25 * c();
        assert_eq!(a.0[5999], 0.0);
        assert_eq!(a.0[6000], g);
        assert_eq!(a.1[29_999], g);
        // a 1, toda à esquerda, termina no mesmo quadro (0,25 s = 0,5 batida)
        assert_eq!(b1.0[5999], 0.125);
        assert_eq!(b1.0[6000], 0.0);
        assert!(b1.1.iter().all(|&v| v == 0.0));
        // o master é a soma das faixas, sem atraso nenhum
        for i in 0..30_000 {
            assert_eq!(out_l[i], a.0[i] + b1.0[i], "quadro {i}");
            assert_eq!(out_r[i], a.1[i] + b1.1[i], "quadro {i}");
        }
        assert!(quiet.0.iter().chain(&missing.0).all(|&v| v == 0.0));
        // a posição informada é a do que sai
        assert!((e.beat() - (0.25 + 30_000.0 / 24_000.0)).abs() < 1e-9, "{}", e.beat());
        // índice inválido: silêncio
        let (mut l, mut r) = (vec![1.0; 8], vec![1.0; 8]);
        assert_eq!(e.captured(40, &mut l, &mut r), 0);
        assert!(l.iter().chain(&r).all(|&v| v == 0.0));
        assert_eq!(e.capture_add(-2), -1);
    }

    #[test]
    fn render_comeca_com_as_transicoes_terminadas() {
        // efeito posto sem assentar (como o `fx_set` num motor novo) e envio recém-apontado: no
        // render, o primeiro quadro já sai com o efeito inteiro e o envio no nível
        let mut e = engine_with_dc_clip(0.0, 2.0);
        e.set_track_count(2);
        e.set_track_kind(1, instrument::kind::BUS);
        e.set_fx_count(0, 1);
        let (fx, _) = TestFx::new(2.0);
        e.strips[0].chain.install(0, fx_kind::UTILITY, fx);
        e.set_sends_count(0, 1);
        e.set_send(0, 0, 1, 0.5, true);
        e.track_mut(0).unwrap().gain = 0.0;
        let (caps, _) = render_offline(&mut e, &[0, 1], 0.0, 256, &|_| 128);
        assert_eq!(caps[0].0[0], 0.0, "o volume 0 já vale no primeiro quadro");
        let bus = 0.5 * 2.0 * 0.5 * c();
        assert!((caps[1].0[0] - bus).abs() < 1e-6, "{}", caps[1].0[0]);
        assert!((caps[1].0[255] - bus).abs() < 1e-6);
    }

    /// Uma cena com quase tudo: clipes, sintetizador, bateria, sampler, efeitos reais nas faixas,
    /// no barramento e no master, envio, saída roteada, sidechain, automação e loop.
    fn scene(e: &mut Engine) {
        use effect::{compressor_param as cp, delay_param as dp, distortion_param as sp, reverb_param as rp};
        e.set_tempo(128.0, 4);
        e.set_track_count(5);
        let noise: Vec<f32> = (0..96_000u32).map(|i| ((i.wrapping_mul(2_654_435_761) >> 8) as f32 / 16_777_216.0 - 0.5) * 0.6).collect();
        let tone: Vec<f32> = (0..48_000).map(|i| (i as f32 * 0.05).sin() * 0.5).collect();
        e.load_sample(1, Sample::new(vec![noise.clone(), noise.iter().rev().copied().collect()], 44_100.0));
        e.load_sample(2, Sample::new(vec![tone], RATE));
        e.add_clip(Clip { track: 0, sample: 1, start: 0.5, offset: 0.1, length: 1.5, gain: 0.8, fade_in: 0.01, fade_out: 0.2 });
        e.set_track_kind(1, instrument::kind::SYNTH);
        e.set_track_kind(2, instrument::kind::DRUMS);
        e.set_track_kind(3, instrument::kind::SAMPLER);
        e.set_track_kind(4, instrument::kind::BUS);
        e.set_instrument_sample(3, 2);
        for (i, p) in [60, 64, 67, 72].into_iter().enumerate() {
            e.add_note(1, i as f64 * 0.75, 1.0, p, 0.9);
            e.add_note(3, 0.25 + i as f64 * 0.5, 0.4, p - 12, 0.7);
        }
        for i in 0..16 {
            e.add_note(2, i as f64 * 0.25, 0.1, [36, 42, 38, 42][i % 4], 1.0);
        }
        e.set_fx(0, 0, fx_kind::EQ);
        e.set_fx(0, 1, fx_kind::COMPRESSOR);
        e.set_fx_param(0, 1, cp::SIDECHAIN, 2.0);
        e.set_fx_param(0, 1, cp::THRESHOLD, -30.0);
        e.set_fx(0, 2, fx_kind::DISTORTION);
        e.set_fx_param(0, 2, sp::DRIVE, 12.0);
        e.set_fx(1, 0, fx_kind::CHORUS);
        e.set_fx(1, 1, fx_kind::PHASER);
        e.set_fx(1, 2, fx_kind::FILTER);
        e.set_sends_count(1, 1);
        e.set_send(1, 0, 4, 0.6, false);
        e.set_output(3, 4);
        e.set_fx(4, 0, fx_kind::REVERB);
        e.set_fx_param(4, 0, rp::MIX, 0.5);
        e.set_fx(4, 1, fx_kind::DELAY);
        e.set_fx_param(4, 1, dp::FEEDBACK, 0.5);
        e.set_fx(-1, 0, fx_kind::COMPRESSOR);
        e.set_fx(-1, 1, fx_kind::LIMITER);
        e.master_mut().gain = 1.5;
        let vol = e.add_lane(1, auto_target::VOLUME, 0, 0);
        e.add_point(vol, 0.0, 0.2, 0.0);
        e.add_point(vol, 2.0, 1.0, 0.5);
        let cut = e.add_lane(1, auto_target::EFFECT, 2, effect::filter_param::CUTOFF);
        e.add_point(cut, 0.0, 300.0, 0.0);
        e.add_point(cut, 3.0, 8000.0, -0.3);
        let send = e.add_lane(1, auto_target::SEND, 0, 0);
        e.add_point(send, 1.0, 0.0, 0.0);
        e.add_point(send, 2.5, 1.0, 0.0);
        e.set_loop(true, 1.0, 3.0);
    }

    #[test]
    fn mesma_sequencia_de_chamadas_da_a_mesma_saida_em_qualquer_bloco() {
        const FRAMES: usize = 72_000;
        let outputs = [-1, 0, 1, 2, 3, 4];
        // com e sem automação: com ela as fatias são de 32 quadros, sem ela de 128
        for automation in [true, false] {
            let go = |blocks: &dyn Fn(usize) -> usize| {
                let mut e = Engine::new(RATE);
                scene(&mut e);
                if !automation {
                    e.clear_automation();
                }
                render_offline(&mut e, &outputs, 0.5, FRAMES, blocks)
            };
            let (a, out) = go(&|_| 128);
            let peak = out.0.iter().chain(&out.1).fold(0.0f32, |m, v| m.max(v.abs()));
            assert!(peak > 0.05 && out.0.iter().chain(&out.1).all(|v| v.is_finite()), "{peak}");
            for (c, _) in &a[1..] {
                assert!(c.iter().any(|&v| v != 0.0), "toda faixa soa na cena");
            }
            assert_eq!(go(&|_| 128).0, a, "de novo, igual");
            assert_eq!(go(&|_| MAX_BLOCK).0, a, "em blocos de 4096, igual (automação: {automation})");
            let mixed = [256, 1024, 128, 4096, 384, 640, 2048];
            assert_eq!(go(&|i| mixed[i % mixed.len()]).0, a, "em blocos variados, igual (automação: {automation})");
        }
    }
}
