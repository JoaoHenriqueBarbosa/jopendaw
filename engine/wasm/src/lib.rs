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

use jopendaw_engine::api::MAX_TRACKS;
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
pub extern "C" fn tempo_clear() {
    engine().tempo_clear();
}

#[unsafe(no_mangle)]
pub extern "C" fn tempo_point(beat: f64, bpm: f64, ramp: u32) {
    engine().tempo_point(beat, bpm, ramp != 0);
}

#[unsafe(no_mangle)]
pub extern "C" fn meter_clear() {
    engine().meter_clear();
}

#[unsafe(no_mangle)]
pub extern "C" fn meter_point(bar: u32, num: u32, den: u32) {
    engine().meter_point(bar, num, den);
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

/// Número de faixas, de 0 a [`MAX_TRACKS`] como em `api::apply` (o Android e o render usam o mesmo
/// teto); acima disso a chamada é ignorada e o motor fica como estava, em vez de reservar
/// gigabytes na memória do wasm (um −1 que deu a volta vira 4294967295).
#[unsafe(no_mangle)]
pub extern "C" fn tracks(n: usize) {
    if n <= MAX_TRACKS {
        engine().set_track_count(n);
    }
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

/// Tipo da faixa `i` (0 áudio, 1 sintetizador, 2 bateria, 3 sampler, 4 barramento, 5 FM, 6 wavetable). Mandar o
/// mesmo tipo de novo não mexe em nada; trocar recria o instrumento nos padrões, então vem antes
/// dos `param`.
#[unsafe(no_mangle)]
pub extern "C" fn track_kind(i: usize, kind: u32) {
    engine().set_track_kind(i, kind);
}

/// Parâmetro `id` do instrumento da faixa `i`, na unidade da tabela (Hz, s, semitons...).
#[unsafe(no_mangle)]
pub extern "C" fn param(i: usize, id: u32, value: f32) {
    engine().set_param(i, id, value);
}

/// Áudio (id de `sample_load`, 0 = nenhum) que o sampler da faixa `i` toca; pode vir antes do
/// áudio chegar.
#[unsafe(no_mangle)]
pub extern "C" fn instrument_sample(i: usize, sample_id: u32) {
    engine().set_instrument_sample(i, sample_id);
}

/// Apaga as zonas do sampler da faixa `i` (volta a tocar o áudio único de `instrument_sample`).
#[unsafe(no_mangle)]
pub extern "C" fn zones_clear(i: usize) {
    engine().clear_zones(i);
}

/// Zona do sampler da faixa `i`: áudio `sample_id`, nota base, notas `lo..=hi`, velocidades
/// `vlo..=vhi` (1..127), afinação em cents, ganho em dB, pan, modo (0 sustentado, ≠ 0 até o fim),
/// trecho e loop em segundos do áudio (fim ≤ 0 é o fim do áudio) e grupo de round-robin (0 nenhum).
#[unsafe(no_mangle)]
#[allow(clippy::too_many_arguments)]
pub extern "C" fn zone_add(
    i: usize,
    sample_id: u32,
    root: u32,
    lo: u32,
    hi: u32,
    vlo: u32,
    vhi: u32,
    cents: f32,
    gain_db: f32,
    pan: f32,
    mode: u32,
    start: f64,
    end: f64,
    loop_start: f64,
    loop_end: f64,
    group: u32,
) {
    let byte = |v: u32| v.min(127) as u8;
    let def = jopendaw_engine::sampler::ZoneDef {
        root: byte(root),
        lo: byte(lo),
        hi: byte(hi),
        vlo: byte(vlo),
        vhi: byte(vhi),
        cents,
        gain_db,
        pan,
        one_shot: mode != 0,
        group: group.min(255) as u8,
        start,
        end,
        loop_start,
        loop_end,
    };
    engine().add_zone(i, sample_id, def);
}

/// Apaga as notas do sequenciador de todas as faixas (antes de reenviá-las com `note_add`).
#[unsafe(no_mangle)]
pub extern "C" fn notes_clear() {
    engine().clear_notes();
}

/// Nota do sequenciador: início e duração em batidas absolutas, altura MIDI, velocidade 0..1.
#[unsafe(no_mangle)]
pub extern "C" fn note_add(track: usize, start: f64, length: f64, pitch: u32, velocity: f32) {
    engine().add_note(track, start, length, pitch, velocity);
}

/// Nota ao vivo (teclado, MIDI, prévia), fora do transporte. Velocidade 0 solta.
#[unsafe(no_mangle)]
pub extern "C" fn live_on(track: usize, pitch: u32, velocity: f32) {
    engine().live_on(track, pitch, velocity);
}

#[unsafe(no_mangle)]
pub extern "C" fn live_off(track: usize, pitch: u32) {
    engine().live_off(track, pitch);
}

/// Corta na hora todo som de instrumento.
#[unsafe(no_mangle)]
pub extern "C" fn panic() {
    engine().panic();
}

// ------------------------------------------------------------------ efeitos, roteamento, automação
// Faixa −1 é o master onde faz sentido (efeitos, automação de volume/pan/efeito, analisador).

/// Quantos slots de efeito a faixa tem (até 16). Os que sobram saem em fade.
#[unsafe(no_mangle)]
pub extern "C" fn fx_count(track: i32, n: u32) {
    engine().set_fx_count(track, n as usize);
}

/// Tipo do efeito no slot (1..12, 0 esvazia). O mesmo tipo de novo não faz nada; outro tipo cria o
/// efeito nos padrões (então vem antes dos `fx_param`) e troca por crossfade.
#[unsafe(no_mangle)]
pub extern "C" fn fx_set(track: i32, slot: u32, kind: u32) {
    engine().set_fx(track, slot as usize, kind);
}

/// Parâmetro `id` do efeito no slot, na unidade da tabela (dB, Hz, s...).
#[unsafe(no_mangle)]
pub extern "C" fn fx_param(track: i32, slot: u32, id: u32, value: f32) {
    engine().set_fx_param(track, slot as usize, id, value);
}

#[unsafe(no_mangle)]
pub extern "C" fn fx_bypass(track: i32, slot: u32, on: u32) {
    engine().set_fx_bypass(track, slot as usize, on != 0);
}

/// Quantos envios a faixa tem (até 16).
#[unsafe(no_mangle)]
pub extern "C" fn sends_count(track: i32, n: u32) {
    if track >= 0 {
        engine().set_sends_count(track as usize, n as usize);
    }
}

/// Envio `index` da faixa para o barramento `bus_track`, nível em ganho linear, `pre` 1 =
/// pré-fader.
#[unsafe(no_mangle)]
pub extern "C" fn send_set(track: i32, index: u32, bus_track: i32, level: f32, pre: u32) {
    if track >= 0 {
        engine().set_send(track as usize, index as usize, bus_track, level, pre != 0);
    }
}

/// Saída da faixa: −1 master, senão o índice do barramento.
#[unsafe(no_mangle)]
pub extern "C" fn track_output(track: i32, target: i32) {
    if track >= 0 {
        engine().set_output(track as usize, target);
    }
}

/// Apaga as lanes de automação (antes de reenviá-las com `auto_lane` e `auto_point`).
#[unsafe(no_mangle)]
pub extern "C" fn auto_clear() {
    engine().clear_automation();
}

/// Nova lane: alvo 0 volume, 1 pan, 2 parâmetro do instrumento (`id`), 3 parâmetro do efeito
/// (`slot`, `id`), 4 nível do envio (`slot` = índice). Devolve o índice da lane.
#[unsafe(no_mangle)]
pub extern "C" fn auto_lane(track: i32, target: u32, slot: u32, id: u32) -> u32 {
    engine().add_lane(track, target, slot, id)
}

/// Ponto na lane: batida absoluta, valor na unidade do alvo e curva −1..1 até o próximo.
#[unsafe(no_mangle)]
pub extern "C" fn auto_point(lane: u32, beat: f64, value: f32, curve: f32) {
    engine().add_point(lane, beat, value, curve);
}

/// Efeito cujo indicador vai em `fx_meter` (slot −1 desliga).
#[unsafe(no_mangle)]
pub extern "C" fn watch_fx(track: i32, slot: i32) {
    engine().watch_fx(track, slot);
}

/// Faixa do analisador de espectro (−1 master, −2 desliga).
#[unsafe(no_mangle)]
pub extern "C" fn watch_analyzer(track: i32) {
    engine().watch_analyzer(track);
}

/// Indicador do efeito observado (redução de ganho em dB na dinâmica; 0 se nenhum).
#[unsafe(no_mangle)]
pub extern "C" fn fx_meter() -> f32 {
    engine().fx_meter()
}

/// Escreve em `out` (memória de `alloc`) até `n` magnitudes em dB (−120..0) do espectro da faixa
/// observada: FFT de 2n pontos com janela de Hann, faixas lineares de 0 à metade da taxa. Devolve
/// quantas escreveu (a maior potência de 2 até `n` e 2048; 0 sem faixa observada).
#[unsafe(no_mangle)]
pub unsafe extern "C" fn analyzer(out: *mut f32, n: u32) -> u32 {
    if out.is_null() {
        return 0;
    }
    let out = unsafe { std::slice::from_raw_parts_mut(out, n as usize) };
    engine().analyzer(out) as u32
}

// ------------------------------------------------------------------ gravação e render

/// Entrada de áudio do próximo bloco: `n` quadros (até 4096) nas memórias de `alloc`; `right` nulo
/// é mono (vale nos dois lados). Vale só para o `process` seguinte: bloco sem entrada, o worklet
/// não chama e o motor não soma nada.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn set_input(left: *const f32, right: *const f32, n: usize) {
    if left.is_null() {
        return;
    }
    let l = unsafe { std::slice::from_raw_parts(left, n) };
    let r = if right.is_null() { None } else { Some(unsafe { std::slice::from_raw_parts(right, n) }) };
    engine().set_input(l, r);
}

/// Monitoramento da entrada na faixa `track` (1 liga): a entrada soma no buffer dela antes dos
/// inserts e passa pela cadeia, pelo fader e pelo roteamento. Só faixas de áudio.
#[unsafe(no_mangle)]
pub extern "C" fn input_monitor(track: i32, on: u32) {
    if track >= 0 {
        engine().set_monitor(track as usize, on != 0);
    }
}

/// Começa a registrar (do zero) as notas ao vivo com a batida exata do quadro em que foram
/// aplicadas; só entram as tocadas com o transporte andando.
#[unsafe(no_mangle)]
pub extern "C" fn rec_notes_start() {
    engine().rec_notes_start();
}

/// Para de registrar; as teclas ainda seguradas terminam na posição de agora.
#[unsafe(no_mangle)]
pub extern "C" fn rec_notes_stop() {
    engine().rec_notes_stop();
}

/// Escreve em `out` (memória de `alloc`, `max` floats) as notas registradas, em grupos de 5
/// floats: faixa, altura, início e fim em batidas, velocidade. Nota ainda segurada termina na
/// posição atual. As escritas saem do registro (com espaço para todas, ele fica vazio; as que não
/// couberam ficam para a próxima chamada). Devolve quantos floats escreveu.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rec_notes(out: *mut f32, max: usize) -> usize {
    if out.is_null() {
        return 0;
    }
    let out = unsafe { std::slice::from_raw_parts_mut(out, max) };
    engine().rec_notes(out)
}

/// Render: esquece as capturas. O próximo `process` com capturas prepara o render (transições
/// terminadas no silêncio, latência do limitador compensada): chame antes do `seek`/`play` dele.
#[unsafe(no_mangle)]
pub extern "C" fn capture_clear() {
    engine().capture_clear();
}

/// Render: passa a copiar, a cada bloco, a saída pós-fader da faixa `track` (a posição dos
/// medidores) ou, com −1, a do master depois do limitador. Devolve o índice para `captured`, ou
/// −1 (até 64 capturas; faixa menor que −1). Com captura, blocos de até 4096 quadros.
#[unsafe(no_mangle)]
pub extern "C" fn capture_add(track: i32) -> i32 {
    engine().capture_add(track)
}

/// Render: copia para `left`/`right` (memórias de `alloc`, `n` quadros) o que a captura `index`
/// soltou no último bloco processado; o que passar do bloco sai zerado. Devolve quantos quadros
/// eram do bloco.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn captured(index: i32, left: *mut f32, right: *mut f32, n: usize) -> usize {
    if left.is_null() || right.is_null() {
        return 0;
    }
    // índice negativo é inválido: silêncio, como um além do fim
    let index = usize::try_from(index).unwrap_or(usize::MAX);
    let l = unsafe { std::slice::from_raw_parts_mut(left, n) };
    if left == right {
        // a mesma memória para os dois lados não pode virar duas referências mutáveis: vai o
        // esquerdo
        return engine().captured(index, l, &mut []);
    }
    let r = unsafe { std::slice::from_raw_parts_mut(right, n) };
    engine().captured(index, l, r)
}

/// Posição em batidas do próximo quadro que sai (no render, já descontado o adiantamento).
#[unsafe(no_mangle)]
pub extern "C" fn beat() -> f64 {
    engine().beat()
}

#[unsafe(no_mangle)]
pub extern "C" fn playing() -> u32 {
    engine().playing() as u32
}

/// Pitch bend ao vivo numa faixa, −1..1.
#[unsafe(no_mangle)]
pub extern "C" fn live_bend(track: usize, value: f32) {
    engine().live_bend(track, value);
}

/// Controle ao vivo: 1 modulação (0..1), 64 pedal de sustain (0,5 ou mais = embaixo), 128 pitch bend.
#[unsafe(no_mangle)]
pub extern "C" fn live_cc(track: usize, cc: u32, value: f32) {
    engine().live_cc(track, cc, value);
}

/// Evento de controle do clipe, na batida absoluta da linha do tempo (mesmos controles do `live_cc`).
#[unsafe(no_mangle)]
pub extern "C" fn cc_add(track: usize, cc: u32, beat: f64, value: f32) {
    engine().add_cc(track, cc, beat, value);
}

/// Apaga os eventos de controle de todas as faixas (junto do `notes_clear`).
#[unsafe(no_mangle)]
pub extern "C" fn cc_clear() {
    engine().clear_cc();
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

// ------------------------------------------------------------------ warp (fora do tempo real)
// Usado só pelo Worker de render (`render-worker.js`), nunca pelo worklet: o resultado fica
// guardado aqui até `stretch_free`, e o JS lê os canais por ponteiro.

struct Stash(UnsafeCell<Vec<Vec<f32>>>);
// uma thread só, como o motor
unsafe impl Sync for Stash {}

static STRETCHED: Stash = Stash(UnsafeCell::new(Vec::new()));

unsafe fn take_channels(left: *mut f32, right: *mut f32, frames: usize) -> Vec<Vec<f32>> {
    let mut ch = vec![unsafe { take(left, frames) }];
    if !right.is_null() {
        ch.push(unsafe { take(right, frames) });
    }
    ch
}

/// Estica (`ratio` = duração final / original) e transpõe (`semitones`) o áudio. `right` nulo é
/// mono. As memórias de entrada passam a ser da função. Devolve os quadros do resultado, que fica
/// disponível em `stretch_channel` até `stretch_free`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn stretch_run(left: *mut f32, right: *mut f32, frames: usize, rate: f64, ratio: f64, semitones: f64) -> usize {
    let ch = unsafe { take_channels(left, right, frames) };
    let out = jopendaw_engine::stretch::stretch(&ch, rate, ratio, semitones);
    let n = out.first().map_or(0, Vec::len);
    unsafe { *STRETCHED.0.get() = out };
    n
}

/// Ponteiro do canal `i` do último `stretch_run` (nulo se não existe). Vale até o próximo
/// `stretch_run` ou `stretch_free`.
#[unsafe(no_mangle)]
pub extern "C" fn stretch_channel(i: usize) -> *const f32 {
    unsafe { (&*STRETCHED.0.get()).get(i).map_or(std::ptr::null(), |c| c.as_ptr()) }
}

#[unsafe(no_mangle)]
pub extern "C" fn stretch_free() {
    unsafe { *STRETCHED.0.get() = Vec::new() };
}

/// Estima o andamento: devolve o BPM (0 se não deu) e deixa a confiança (0..1) em `detect_confidence`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn detect_bpm(left: *mut f32, right: *mut f32, frames: usize, rate: f64) -> f64 {
    let ch = unsafe { take_channels(left, right, frames) };
    let t = jopendaw_engine::stretch::detect_bpm(&ch, rate);
    DETECT_CONFIDENCE.store(t.confidence.to_bits(), std::sync::atomic::Ordering::Relaxed);
    t.bpm
}

static DETECT_CONFIDENCE: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);

#[unsafe(no_mangle)]
pub extern "C" fn detect_confidence() -> f64 {
    f64::from_bits(DETECT_CONFIDENCE.load(std::sync::atomic::Ordering::Relaxed))
}

// ------------------------------------------------------------------ loudness

/// Zera a medida de loudness do master (integrado, faixa, máximos e true peak).
#[unsafe(no_mangle)]
pub extern "C" fn loudness_reset() {
    engine().loudness_reset();
}

/// Medida de loudness do master (BS.1770-4 / EBU R128, depois do limitador): 0 momentâneo, 1 curto
/// prazo, 2 integrado (LUFS), 3 true peak máximo (dBTP), 4 faixa de loudness (LU). −200 = sem medida.
#[unsafe(no_mangle)]
pub extern "C" fn loudness(kind: u32) -> f64 {
    engine().loudness(kind)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// O motor é global (uma thread só no worklet): só um teste mexe nele aqui.
    #[test]
    fn tracks_acima_do_teto_e_ignorado_como_no_apply() {
        init(48_000.0);
        tracks(3);
        assert_eq!(engine().tracks().len(), 3);
        // um −1 que deu a volta, e o teto mais um: nada é reservado, o motor fica como estava
        tracks(usize::MAX);
        tracks(u32::MAX as usize);
        tracks(MAX_TRACKS + 1);
        assert_eq!(engine().tracks().len(), 3);
        tracks(0);
        assert_eq!(engine().tracks().len(), 0);
        tracks(MAX_TRACKS);
        assert_eq!(engine().tracks().len(), MAX_TRACKS);
    }
}
