//! Warp de áudio: esticar no tempo sem mudar a altura, transpor sem mudar a duração e estimar o
//! andamento. Tudo offline (funções puras sobre canais → canais), fora da thread de áudio: o app
//! roda isto num Worker (web) ou num isolate (Android) e depois carrega o resultado como um
//! sample comum.
//!
//! # Por que WSOLA e não phase vocoder
//!
//! Os alvos típicos são loops de bateria e trechos rítmicos que precisam grudar no andamento do
//! projeto. O phase vocoder puro borra os transientes e deixa o som "de tubo" (fase reconstruída);
//! corrigi-lo bem exige detecção de transientes e travamento de fase, muito mais código. O WSOLA
//! (overlap-add com busca de correlação) trabalha no tempo: cada janela é copiada do original sem
//! alterar a forma de onda, só o ponto de leitura é ajustado (±~16 ms) para casar com a
//! continuação da janela anterior, então a fase é coerente por construção e batidas ficam nítidas
//! nas razões usuais (0,5..2). O custo é o "flutter" em material polifônico muito denso com razões
//! extremas, um compromisso aceito.
//!
//! Estéreo: a busca de correlação usa a soma mono e o mesmo deslocamento vale para os dois canais,
//! então a diferença de fase entre eles (a imagem estéreo) é preservada.

use std::f64::consts::PI;

/// Menor e maior razão de duração (saída/entrada) aceitas.
pub const MIN_RATIO: f64 = 0.25;
pub const MAX_RATIO: f64 = 4.0;
/// Limite da transposição, em semitons.
pub const MAX_SEMITONES: f64 = 24.0;

/// Janela do WSOLA (~40 ms).
const WINDOW_SECS: f64 = 0.040;
/// Quanto a janela pode se afastar da posição nominal para achar a melhor emenda.
const SEEK_SECS: f64 = 0.016;
/// Meia-largura (em cruzamentos por zero) do sinc do reamostrador.
const SINC_ZEROS: f64 = 12.0;

fn clamp_params(ratio: f64, semitones: f64) -> (f64, f64) {
    let ratio = if ratio.is_finite() { ratio.clamp(MIN_RATIO, MAX_RATIO) } else { 1.0 };
    let semitones = if semitones.is_finite() { semitones.clamp(-MAX_SEMITONES, MAX_SEMITONES) } else { 0.0 };
    (ratio, semitones)
}

/// Estica o áudio para `ratio` vezes a duração (>1 mais longo) e transpõe `semitones`, uma coisa
/// independente da outra: a duração final é `frames * ratio` e a altura sobe `semitones`.
/// `channels` tem 1 ou 2 canais do mesmo tamanho; a saída tem o mesmo número de canais.
pub fn stretch(channels: &[Vec<f32>], rate: f64, ratio: f64, semitones: f64) -> Vec<Vec<f32>> {
    stretch_with_progress(channels, rate, ratio, semitones, &mut |_| {})
}

/// Como [`stretch`], chamando `progress` (0..1) durante o trabalho.
pub fn stretch_with_progress(channels: &[Vec<f32>], rate: f64, ratio: f64, semitones: f64, progress: &mut dyn FnMut(f32)) -> Vec<Vec<f32>> {
    let (ratio, semitones) = clamp_params(ratio, semitones);
    let n = channels.first().map_or(0, Vec::len);
    if n == 0 || !(rate.is_finite() && rate > 0.0) {
        return channels.to_vec();
    }
    let pitch = (semitones / 12.0).exp2();
    let shifted = (pitch - 1.0).abs() > 1e-9;
    if (ratio - 1.0).abs() < 1e-9 && !shifted {
        progress(1.0);
        return channels.to_vec();
    }
    // Transpor = esticar por `ratio * pitch` e tocar `pitch` vezes mais rápido: a altura sobe
    // `pitch` e a duração volta a `ratio`.
    let inner = ratio * pitch;
    let share = if shifted { 0.7 } else { 1.0 };
    let stretched = if (inner - 1.0).abs() < 1e-9 { channels.to_vec() } else { wsola(channels, rate, inner, &mut |p| progress(share * p)) };
    let out = if shifted { resample(&stretched, pitch, &mut |p| progress(0.7 + 0.3 * p)) } else { stretched };
    progress(1.0);
    out
}

/// Soma mono para a busca de correlação.
fn mono(channels: &[Vec<f32>]) -> Vec<f32> {
    let n = channels[0].len();
    if channels.len() == 1 {
        return channels[0].clone();
    }
    (0..n).map(|i| 0.5 * (channels[0][i] + channels[1][i])).collect()
}

/// Amostra com zeros fora do sinal (o áudio é tratado como cercado de silêncio).
fn at(x: &[f32], i: i64) -> f32 {
    if i < 0 { 0.0 } else { x.get(i as usize).copied().unwrap_or(0.0) }
}

/// Correlação normalizada entre `x[a..a+len]` e `x[b..b+len]`, andando de `step` em `step`.
fn correlation(x: &[f32], a: i64, b: i64, len: usize, step: usize) -> f64 {
    let (mut xy, mut xx, mut yy) = (0.0f64, 1e-9f64, 1e-9f64);
    let mut i = 0;
    while i < len {
        let (p, q) = (at(x, a + i as i64) as f64, at(x, b + i as i64) as f64);
        xy += p * q;
        xx += p * p;
        yy += q * q;
        i += step;
    }
    xy / (xx * yy).sqrt()
}

fn wsola(channels: &[Vec<f32>], rate: f64, ratio: f64, progress: &mut dyn FnMut(f32)) -> Vec<Vec<f32>> {
    let n = channels[0].len();
    // janela par: com hop = janela/2 e Hann periódica a soma das janelas é 1
    let win = ((rate * WINDOW_SECS) as usize).max(64) & !1;
    let hop = win / 2;
    let seek = ((rate * SEEK_SECS) as i64).max(4);
    let out_len = ((n as f64) * ratio).round().max(1.0) as usize;
    let hann: Vec<f32> = (0..win).map(|i| (0.5 - 0.5 * (2.0 * PI * i as f64 / win as f64).cos()) as f32).collect();
    let m = mono(channels);

    let mut out: Vec<Vec<f32>> = channels.iter().map(|_| vec![0.0f32; out_len + 2 * win]).collect();
    let mut wsum = vec![0.0f32; out_len + 2 * win];
    let frames = out_len.div_ceil(hop) + 1;
    // onde a janela anterior foi lida: a continuação natural dela é `prev + hop`
    let mut prev: i64 = 0;
    for k in 0..frames {
        let nominal = ((k * hop) as f64 / ratio).round() as i64;
        let pos = if k == 0 { nominal } else { best_position(&m, prev + hop as i64, nominal, seek, hop) };
        // depois do fim do original só resta silêncio
        if pos >= n as i64 + win as i64 {
            break;
        }
        let o = k * hop;
        for (c, ch) in channels.iter().enumerate() {
            let dst = &mut out[c][o..o + win];
            for (i, d) in dst.iter_mut().enumerate() {
                *d += at(ch, pos + i as i64) * hann[i];
            }
        }
        for (i, w) in wsum[o..o + win].iter_mut().enumerate() {
            *w += hann[i];
        }
        prev = pos;
        if k % 64 == 0 {
            progress(k as f32 / frames as f32);
        }
    }
    for ch in &mut out {
        for (d, w) in ch.iter_mut().zip(&wsum) {
            // nas bordas a soma das janelas é menor que 1: normaliza (sem dividir por quase zero)
            if *w > 1e-3 {
                *d /= *w;
            }
        }
        ch.truncate(out_len);
    }
    progress(1.0);
    out
}

/// A leitura, dentro de `nominal ± seek`, cuja continuação melhor casa com a de `target`. Busca
/// grossa (passo 4, correlação em metade das amostras) e depois fina em volta do melhor. Um pequeno
/// desconto por distância desempata a favor da posição nominal (com razão 1 volta a copiar reto).
fn best_position(m: &[f32], target: i64, nominal: i64, seek: i64, len: usize) -> i64 {
    let score = |c: i64, step: usize| correlation(m, c, target, len, step) - 1e-4 * ((c - nominal).abs() as f64 / seek as f64);
    let mut best = nominal;
    let mut best_score = f64::NEG_INFINITY;
    let mut c = nominal - seek;
    while c <= nominal + seek {
        let s = score(c, 2);
        if s > best_score {
            best_score = s;
            best = c;
        }
        c += 4;
    }
    let coarse = best;
    best_score = f64::NEG_INFINITY;
    for c in coarse - 3..=coarse + 3 {
        if (c - nominal).abs() > seek {
            continue;
        }
        let s = score(c, 1);
        if s > best_score {
            best_score = s;
            best = c;
        }
    }
    best
}

/// Toca `speed` vezes mais rápido (altura ×`speed`, duração ÷`speed`) com sinc janelado; ao
/// acelerar, o corte do filtro desce para `1/speed` da banda e não deixa aliasing.
fn resample(channels: &[Vec<f32>], speed: f64, progress: &mut dyn FnMut(f32)) -> Vec<Vec<f32>> {
    let n = channels[0].len();
    let out_len = ((n as f64) / speed).round().max(1.0) as usize;
    let cut = speed.max(1.0).recip();
    let half = SINC_ZEROS / cut;
    let mut out = Vec::with_capacity(channels.len());
    for ch in channels {
        let mut o = vec![0.0f32; out_len];
        for (j, d) in o.iter_mut().enumerate() {
            let t = j as f64 * speed;
            let first = (t - half).ceil() as i64;
            let last = (t + half).floor() as i64;
            let mut acc = 0.0f64;
            for i in first.max(0)..=last.min(n as i64 - 1) {
                let x = t - i as f64;
                let arg = PI * x * cut;
                let sinc = if arg.abs() < 1e-9 { 1.0 } else { arg.sin() / arg };
                let w = 0.5 + 0.5 * (PI * x / half).cos();
                acc += ch[i as usize] as f64 * sinc * w;
            }
            *d = (acc * cut) as f32;
        }
        out.push(o);
        progress(out.len() as f32 / channels.len() as f32);
    }
    out
}

/// Andamento estimado.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Tempo {
    /// Batidas por minuto (60..200); 0 quando não deu para estimar (silêncio, áudio curto).
    pub bpm: f64,
    /// 0..1: o quanto o pico de periodicidade se destaca do resto.
    pub confidence: f64,
}

/// Estima o andamento pela autocorrelação do envelope de onsets, entre 60 e 200 BPM.
///
/// O envelope é o fluxo positivo da energia em log (do sinal e da derivada dele, esta pega cliques
/// e chimbais) a ~400 quadros/s; a periodicidade sai da autocorrelação e é pontuada por um pente
/// (o período, o dobro e o quádruplo) em passos de 0,05 BPM com interpolação linear, para passar de
/// ±1 BPM. A ambiguidade de oitava (60 contra 120) é resolvida por um peso suave em torno de
/// 120 BPM e pelo pente, que premia quem também explica os meios tempos.
pub fn detect_bpm(channels: &[Vec<f32>], rate: f64) -> Tempo {
    const NONE: Tempo = Tempo { bpm: 0.0, confidence: 0.0 };
    let n = channels.first().map_or(0, Vec::len);
    if n == 0 || !(rate.is_finite() && rate > 0.0) || (n as f64) < rate * 3.0 {
        return NONE;
    }
    // no máximo 90 s: o andamento aparece cedo e o custo cresce com o comprimento
    let n = n.min((rate * 90.0) as usize);
    let m: Vec<f32> = mono(channels)[..n].to_vec();
    let hop = (rate / 400.0).max(1.0) as usize;
    let fps = rate / hop as f64;
    let frames = n / hop;
    let mut level = Vec::with_capacity(frames);
    for f in 0..frames {
        let s = &m[f * hop..(f + 1) * hop];
        let e: f64 = s.iter().map(|&v| (v as f64).powi(2)).sum::<f64>() / hop as f64;
        let d: f64 = s.windows(2).map(|w| ((w[1] - w[0]) as f64).powi(2)).sum::<f64>() / hop as f64;
        level.push((1.0 + 1e4 * e).ln() + (1.0 + 1e4 * d).ln());
    }
    // fluxo positivo, com a média móvel (~0,5 s) tirada para sobrar só o que salta
    let flux: Vec<f64> = (0..frames).map(|f| if f == 0 { 0.0 } else { (level[f] - level[f - 1]).max(0.0) }).collect();
    let w = ((fps * 0.5) as usize).max(2);
    let mut acc = 0.0;
    let mut env = vec![0.0; frames];
    for f in 0..frames {
        acc += flux[f];
        if f >= w {
            acc -= flux[f - w];
        }
        let mean = acc / (f.min(w - 1) + 1) as f64;
        env[f] = (flux[f] - mean).max(0.0);
    }
    let energy: f64 = env.iter().map(|v| v * v).sum();
    if energy < 1e-6 {
        return NONE;
    }
    // Sem batidas não há andamento: um pad, um tom sustentado ou um ruído sempre têm *algum* pico de
    // periodicidade (a confiança relativa abaixo o destaca de qualquer jeito), então antes se exige
    // que existam onsets de verdade, isto é, picos do envelope claros e em quantidade.
    if !has_onsets(&env, fps, n as f64 / rate) {
        return NONE;
    }

    // autocorrelação normalizada até o quádruplo do maior período (60 BPM = 1 s)
    let max_lag = (fps * 4.0) as usize + 2;
    if frames <= max_lag {
        return NONE;
    }
    let acf: Vec<f64> = (0..=max_lag)
        .map(|lag| {
            let s: f64 = env[lag..].iter().zip(&env).map(|(a, b)| a * b).sum();
            s / (frames - lag) as f64
        })
        .collect();
    let acf0 = acf[0].max(1e-12);
    let get = |l: f64| -> f64 {
        if l < 0.0 || l >= max_lag as f64 {
            return 0.0;
        }
        let i = l as usize;
        let f = l - i as f64;
        (acf[i] * (1.0 - f) + acf[i + 1] * f) / acf0
    };

    let mut best = (0.0, f64::NEG_INFINITY);
    let mut sum = 0.0;
    let mut count = 0.0;
    let mut bpm = 60.0;
    while bpm <= 200.0 + 1e-9 {
        let lag = fps * 60.0 / bpm;
        let comb = get(lag) + 0.5 * get(2.0 * lag) + 0.25 * get(4.0 * lag) + 0.5 * get(lag / 2.0);
        // preferência suave por volta de 120 BPM (desvio de uma oitava)
        let prior = (-0.5 * ((bpm / 120.0).log2() / 0.9).powi(2)).exp();
        let s = comb * prior;
        sum += s;
        count += 1.0;
        if s > best.1 {
            best = (bpm, s);
        }
        bpm += 0.05;
    }
    let mean = sum / count;
    if best.1 <= 0.0 {
        return NONE;
    }
    // periodicidade de verdade: batidas regulares dão de 0,5 a 0,9 na autocorrelação normalizada,
    // ruído fica perto de 0,05; abaixo de 0,25 o pico é só acaso
    let strength = get(fps * 60.0 / best.0);
    if strength < 0.25 {
        return NONE;
    }
    Tempo { bpm: best.0, confidence: ((best.1 - mean) / best.1).clamp(0.0, 1.0) }
}

/// Há onsets de verdade no envelope: o maior pico se destaca muito da média (ritmos dão 50 a 60,
/// um pad com batimentos, 11), e há picos locais a pelo menos um quarto dele, separados por 80 ms, em
/// quantidade razoável (no mínimo 8 e 0,3 por segundo; música esparsa em meio tempo passa) e sem
/// virar uma chuva de picos (ruído, mais de 12 por segundo).
fn has_onsets(env: &[f64], fps: f64, secs: f64) -> bool {
    let top = env.iter().cloned().fold(0.0, f64::max);
    let mean = env.iter().sum::<f64>() / env.len() as f64;
    if top <= 0.0 || mean <= 0.0 || top / mean < 25.0 {
        return false;
    }
    let gap = ((fps * 0.08) as usize).max(1);
    let mut peaks = 0usize;
    let mut last: Option<usize> = None;
    for f in 1..env.len().saturating_sub(1) {
        let v = env[f];
        if v >= 0.25 * top && v >= env[f - 1] && v > env[f + 1] && last.is_none_or(|l| f - l >= gap) {
            peaks += 1;
            last = Some(f);
        }
    }
    let per_s = peaks as f64 / secs;
    peaks >= 8 && (0.3..=12.0).contains(&per_s)
}

#[cfg(test)]
mod tests {
    use super::*;

    const RATE: f64 = 48_000.0;

    fn sine(freq: f64, secs: f64) -> Vec<f32> {
        (0..(RATE * secs) as usize).map(|i| (2.0 * PI * freq * i as f64 / RATE).sin() as f32 * 0.5).collect()
    }

    /// Frequência pelos cruzamentos ascendentes por zero, ignorando as bordas.
    fn freq_of(x: &[f32]) -> f64 {
        let cut = x.len() / 10;
        let x = &x[cut..x.len() - cut];
        let crossings = x.windows(2).filter(|w| w[0] < 0.0 && w[1] >= 0.0).count();
        crossings as f64 / (x.len() as f64 / RATE)
    }

    #[test]
    fn stretch_keeps_frequency_and_scales_duration() {
        for ratio in [0.5, 0.8, 1.5, 2.0, 3.0] {
            let out = stretch(&[sine(440.0, 1.0)], RATE, ratio, 0.0);
            let expected = RATE * ratio;
            assert!((out[0].len() as f64 - expected).abs() <= 1.0, "duração {} para razão {ratio}", out[0].len());
            let f = freq_of(&out[0]);
            assert!((f - 440.0).abs() < 5.0, "razão {ratio}: {f} Hz");
        }
    }

    #[test]
    fn stretch_preserves_level() {
        let out = stretch(&[sine(220.0, 1.0)], RATE, 1.7, 0.0);
        let peak = out[0][out[0].len() / 4..out[0].len() * 3 / 4].iter().fold(0.0f32, |a, &b| a.max(b.abs()));
        assert!((peak - 0.5).abs() < 0.05, "pico {peak}");
    }

    #[test]
    fn pitch_up_octave_doubles_frequency_keeping_duration() {
        let out = stretch(&[sine(440.0, 1.0)], RATE, 1.0, 12.0);
        assert!((out[0].len() as f64 - RATE).abs() <= 1.0);
        let f = freq_of(&out[0]);
        assert!((f - 880.0).abs() < 8.0, "{f} Hz");
    }

    #[test]
    fn pitch_down_and_combined_with_stretch() {
        let out = stretch(&[sine(440.0, 1.0)], RATE, 2.0, -12.0);
        assert!((out[0].len() as f64 - 2.0 * RATE).abs() <= 1.0);
        let f = freq_of(&out[0]);
        assert!((f - 220.0).abs() < 4.0, "{f} Hz");
    }

    #[test]
    fn odd_lengths_and_ratios_do_not_overrun() {
        // comprimentos e razões que não caem numa grade exata de janelas
        for (secs, ratio, st) in [(0.37, 1.37, 3.0), (1.13, 0.61, -5.0), (0.05, 3.3, 7.0), (0.01, 1.5, 0.0)] {
            let x = sine(330.0, secs);
            let out = stretch(&[x.clone(), x.clone()], RATE, ratio, st);
            let pitch = (st / 12.0f64).exp2();
            let want = (x.len() as f64 * ratio * pitch).round() / pitch;
            assert!((out[0].len() as f64 - want).abs() <= 2.0, "{secs} {ratio} {st}: {} contra {want}", out[0].len());
            assert_eq!(out[0].len(), out[1].len());
        }
    }

    #[test]
    fn stereo_channels_stay_aligned() {
        // o mesmo sinal com o direito atrasado 1 ms: a defasagem sobrevive ao esticar
        let l = sine(300.0, 1.0);
        let d = 48;
        let mut r = vec![0.0; d];
        r.extend_from_slice(&l[..l.len() - d]);
        let out = stretch(&[l, r], RATE, 1.5, 0.0);
        let (a, b) = (&out[0], &out[1]);
        assert_eq!(a.len(), b.len());
        let mid = a.len() / 2;
        let mut best = (0i64, f64::MIN);
        for lag in -100..=100i64 {
            let s: f64 = (mid..mid + 4800).map(|i| a[i] as f64 * b[(i as i64 + lag) as usize] as f64).sum();
            if s > best.1 {
                best = (lag, s);
            }
        }
        assert!((best.0 - d as i64).abs() <= 2, "atraso {}", best.0);
    }

    #[test]
    fn identity_and_bad_input() {
        let x = vec![sine(100.0, 0.5)];
        assert_eq!(stretch(&x, RATE, 1.0, 0.0), x);
        assert!(stretch(&[vec![]], RATE, 2.0, 0.0)[0].is_empty());
        // razão fora do limite é apertada, não explode
        let out = stretch(&x, RATE, 100.0, 0.0);
        assert!(out[0].len() as f64 <= RATE * 0.5 * MAX_RATIO + 2.0);
    }

    fn clicks(bpm: f64, secs: f64) -> Vec<f32> {
        let mut x = vec![0.0f32; (RATE * secs) as usize];
        let period = RATE * 60.0 / bpm;
        let mut t = 0.0;
        while (t as usize) + 200 < x.len() {
            for i in 0..200 {
                x[t as usize + i] = (1.0 - i as f32 / 200.0) * if i % 2 == 0 { 0.9 } else { -0.9 };
            }
            t += period;
        }
        x
    }

    #[test]
    fn click_loop_tempo_is_estimated() {
        for bpm in [120.0, 90.0, 140.0, 75.0] {
            let t = detect_bpm(&[clicks(bpm, 10.0)], RATE);
            assert!((t.bpm - bpm).abs() <= 1.0, "esperado {bpm}, veio {} (conf {})", t.bpm, t.confidence);
            assert!(t.confidence > 0.3, "confiança {}", t.confidence);
        }
    }

    #[test]
    fn accented_pattern_tempo_is_not_halved() {
        // acento no 1 de cada 4 cliques: o período de compasso não pode virar o andamento
        let mut x = clicks(120.0, 16.0);
        for (b, chunk) in x.chunks_mut((RATE * 0.5) as usize).enumerate() {
            if b % 4 != 0 {
                for v in chunk.iter_mut() {
                    *v *= 0.4;
                }
            }
        }
        let t = detect_bpm(&[x], RATE);
        assert!((t.bpm - 120.0).abs() <= 1.0, "veio {}", t.bpm);
    }

    #[test]
    fn silence_and_short_audio_give_no_tempo() {
        assert_eq!(detect_bpm(&[vec![0.0; 480_000]], RATE).bpm, 0.0);
        assert_eq!(detect_bpm(&[vec![0.5; 1000]], RATE).bpm, 0.0);
    }

    #[test]
    fn stretched_loop_keeps_its_beats() {
        // esticar um loop de 120 para 100 BPM (razão 1,2) deve dar ~100 BPM
        let out = stretch(&[clicks(120.0, 10.0)], RATE, 1.2, 0.0);
        let t = detect_bpm(&out, RATE);
        assert!((t.bpm - 100.0).abs() <= 2.0, "veio {}", t.bpm);
    }

    /// Faixa sintética: bumbo em todo tempo, caixa nos contratempos e chimbal em colcheias.
    fn beat_track(bpm: f64, secs: f64) -> Vec<f32> {
        let n = (RATE * secs) as usize;
        let mut out = vec![0.0f32; n];
        let mut seed = 12345u32;
        let mut noise = move || {
            seed = seed.wrapping_mul(1664525).wrapping_add(1013904223);
            (seed >> 8) as f32 / (1 << 23) as f32 - 1.0
        };
        let beat = 60.0 / bpm;
        let mut put = |t: f64, sig: &[f32]| {
            let i0 = (t * RATE) as usize;
            for (k, v) in sig.iter().enumerate() {
                if i0 + k < n {
                    out[i0 + k] += v;
                }
            }
        };
        let kick: Vec<f32> = {
            let mut ph = 0.0f64;
            (0..(0.28 * RATE) as usize)
                .map(|i| {
                    let t = i as f64 / RATE;
                    ph += 2.0 * PI * (50.0 + 110.0 * (-t * 22.0).exp()) / RATE;
                    (0.9 * ph.sin() * (-t * 11.0).exp()) as f32
                })
                .collect()
        };
        let snare: Vec<f32> = (0..(0.16 * RATE) as usize).map(|i| 0.5 * noise() * (-(i as f64 / RATE) * 26.0).exp() as f32).collect();
        let hat: Vec<f32> = {
            let mut prev = 0.0f32;
            (0..(0.05 * RATE) as usize)
                .map(|i| {
                    let x = noise();
                    let y = x - prev;
                    prev = x;
                    0.25 * y * (-(i as f64 / RATE) * 70.0).exp() as f32
                })
                .collect()
        };
        for b in 0..(secs / beat) as usize {
            let t = b as f64 * beat;
            put(t, &kick);
            if b % 2 == 1 {
                put(t, &snare);
            }
            put(t + beat / 2.0, &hat);
        }
        out
    }

    #[test]
    fn tempo_in_the_common_range_is_exact_on_long_clips() {
        for bpm in [75.0, 90.0, 100.0, 120.0, 140.0] {
            let t = detect_bpm(&[beat_track(bpm, 30.0)], RATE);
            assert!((t.bpm - bpm).abs() < 0.5, "{bpm} BPM deu {}", t.bpm);
            assert!(t.confidence > 0.8, "{bpm} BPM: confiança {}", t.confidence);
        }
    }

    #[test]
    fn tempo_at_the_extremes_may_be_off_by_an_octave_but_never_by_anything_else() {
        // ambiguidade de batida contra meio tempo: o usuário corrige com ÷2 e ×2
        for bpm in [65.0, 170.0, 190.0] {
            let got = detect_bpm(&[beat_track(bpm, 30.0)], RATE).bpm;
            let octave = [bpm, bpm * 2.0, bpm / 2.0].iter().any(|c| (got - c).abs() < 0.6);
            assert!(octave, "{bpm} BPM deu {got}");
        }
    }

    #[test]
    fn no_tempo_without_beats() {
        let mut seed = 99u32;
        let noise: Vec<f32> = (0..(RATE * 20.0) as usize)
            .map(|_| {
                seed = seed.wrapping_mul(1664525).wrapping_add(1013904223);
                (seed >> 8) as f32 / (1 << 23) as f32 - 1.0
            })
            .collect();
        let pad: Vec<f32> = (0..(RATE * 20.0) as usize)
            .map(|i| {
                let t = i as f64 / RATE;
                (0.1 * ((2.0 * PI * 220.0 * t).sin() + (2.0 * PI * 277.0 * t).sin() + (2.0 * PI * 330.0 * t).sin())) as f32
            })
            .collect();
        for (name, sig) in [("tom puro", sine(440.0, 20.0)), ("ruído branco", noise), ("pad de acorde", pad)] {
            let t = detect_bpm(&[sig], RATE);
            assert_eq!(t.bpm, 0.0, "{name} não tem andamento, mas deu {}", t.bpm);
        }
    }

    #[test]
    fn swung_syncopated_pattern_keeps_its_tempo() {
        // a fase muda mas o andamento é o mesmo: bumbo extra fora do tempo a cada quatro batidas
        let mut x = beat_track(90.0, 28.0);
        let extra: Vec<f32> =
            (0..(0.2 * RATE) as usize).map(|i| 0.7 * (2.0 * PI * 70.0 * i as f64 / RATE).sin() as f32 * (-(i as f64 / RATE) * 14.0).exp() as f32).collect();
        let beat = 60.0 / 90.0;
        for b in (2..(28.0 / beat) as usize).step_by(4) {
            let i0 = ((b as f64 + 0.75) * beat * RATE) as usize;
            for (k, v) in extra.iter().enumerate() {
                if i0 + k < x.len() {
                    x[i0 + k] += v;
                }
            }
        }
        let t = detect_bpm(&[x], RATE);
        assert!((t.bpm - 90.0).abs() < 0.5, "deu {}", t.bpm);
    }
}
