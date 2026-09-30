//! Referência do fatiamento de loops, só para os testes (submódulo de `sampler_zones.rs`).
//!
//! O app fatia no Dart (`app/lib/daw/sampler_zones.dart`): decodifica o áudio, mostra a prévia dos cortes e
//! manda uma zona por fatia. Manter uma segunda cópia em produção no motor era código morto (e a divergência
//! das duas já causou um bug: o deslocamento de 32 bits do dart2js). Esta cópia não vai para o binário; ela
//! existe para que os vetores fixos de paridade (`paridade_com_o_dart` nos testes daqui e o teste
//! `paridade com o motor` em `app/test/sampler_zones_test.dart`) valham dos dois lados: mexeu num algoritmo,
//! atualize o outro e os números dos dois testes.

use super::ZoneDef;

/// Fatias de uma vez (uma nota cada, a partir de [`FIRST_SLICE_NOTE`]; 24 + 96 − 1 = 119 < 127).
pub const MAX_SLICES: usize = 96;
/// Mínimo de fatias iguais: uma fatia só não fatia nada (o diálogo do app começa em 2).
pub const MIN_SLICES: usize = 2;
/// Primeira nota das zonas de fatias: C1.
pub const FIRST_SLICE_NOTE: u8 = 24;

/// Como escolher os pontos de corte de [`slice_points`].
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum SliceMode {
    /// N fatias iguais ([`MIN_SLICES`]..=[`MAX_SLICES`]; fora disso é limitado).
    Count(usize),
    /// Um corte em cada transiente. Sensibilidade 0..1: com 1 pega também os ataques fracos.
    Transients(f32),
}

/// Tamanho do passo do envelope dos transientes.
const HOP_SECS: f64 = 0.005;
/// Distância mínima entre dois cortes.
const MIN_GAP_SECS: f64 = 0.05;
/// Os cortes a menos disto do começo ou do fim do áudio não valem.
const EDGE_SECS: f64 = 0.01;

/// Os pontos de corte de um áudio, em segundos, crescentes; o primeiro é sempre 0 (áudio vazio: nenhum).
/// Cada ponto é o início de uma fatia, que vai até o ponto seguinte (a última, até o fim).
pub fn slice_points(channels: &[Vec<f32>], rate: f64, mode: SliceMode) -> Vec<f64> {
    let n = channels.iter().map(Vec::len).min().unwrap_or(0);
    if n == 0 || !(rate.is_finite() && rate > 0.0) {
        return Vec::new();
    }
    let frames = match mode {
        SliceMode::Count(k) => {
            let k = k.clamp(MIN_SLICES, MAX_SLICES).min(n);
            let mut p: Vec<usize> = (0..k).map(|i| (i as f64 * n as f64 / k as f64).round() as usize).collect();
            p.dedup();
            p
        }
        SliceMode::Transients(sensitivity) => transients(channels, n, rate, sensitivity),
    };
    frames.into_iter().map(|f| f as f64 / rate).collect()
}

/// Cortes por transientes, em quadros (o primeiro é 0).
///
/// O envelope é a energia do sinal e da derivada dele em log (mesma ideia do detector de andamento,
/// a derivada pega cliques e chimbais) a cada 5 ms; o fluxo positivo dele é comparado com a média
/// local (±0,2 s) e com o maior pico, e só os máximos locais distantes 50 ms passam. O ponto de corte
/// é refinado no áudio: o primeiro quadro em que o sinal passa de 10% do pico do ataque, recuado até o
/// cruzamento de zero mais próximo (até 2 ms), para o corte não estalar.
fn transients(channels: &[Vec<f32>], n: usize, rate: f64, sensitivity: f32) -> Vec<usize> {
    let mut points = vec![0usize];
    let hop = ((rate * HOP_SECS).round() as usize).max(1);
    let nf = n / hop;
    if nf < 4 {
        return points;
    }
    let m = |i: usize| -> f64 { channels.iter().map(|c| f64::from(c[i])).sum::<f64>() / channels.len() as f64 };
    let mono: Vec<f32> = (0..n).map(|i| m(i) as f32).collect();
    let level: Vec<f64> = (0..nf)
        .map(|f| {
            let w = &mono[f * hop..(f + 1) * hop];
            let e = w.iter().map(|&v| f64::from(v).powi(2)).sum::<f64>() / hop as f64;
            let d = w.windows(2).map(|p| f64::from(p[1] - p[0]).powi(2)).sum::<f64>() / hop as f64;
            (1.0 + 1e4 * e).ln() + (1.0 + 1e4 * d).ln()
        })
        .collect();
    let flux: Vec<f64> = (0..nf).map(|f| if f == 0 { 0.0 } else { (level[f] - level[f - 1]).max(0.0) }).collect();
    let top = flux.iter().copied().fold(0.0, f64::max);
    if top < 0.5 {
        return points;
    }
    // soma acumulada para a média local
    let mut prefix = vec![0.0; nf + 1];
    for f in 0..nf {
        prefix[f + 1] = prefix[f] + flux[f];
    }
    let half = ((0.2 / HOP_SECS) as usize).max(2);
    let s = f64::from(if sensitivity.is_finite() { sensitivity.clamp(0.0, 1.0) } else { 0.5 });
    let (relative, floor, of_top) = (6.0 - 4.5 * s, 1.2 - 0.8 * s, 0.30 - 0.22 * s);
    let gap = ((MIN_GAP_SECS / HOP_SECS) as usize).max(1);
    let edge = (EDGE_SECS * rate) as usize;

    let mut found: Vec<(usize, f64)> = Vec::new();
    for f in 1..nf - 1 {
        let v = flux[f];
        if v < floor || v < of_top * top {
            continue;
        }
        let (a, b) = (f.saturating_sub(gap), (f + gap + 1).min(nf));
        if flux[a..b].iter().any(|&o| o > v) || flux[f - 1] > v || flux[f + 1] >= v {
            continue;
        }
        let (a, b) = (f.saturating_sub(half), (f + half + 1).min(nf));
        if v < relative * (prefix[b] - prefix[a]) / (b - a) as f64 {
            continue;
        }
        found.push((onset(&mono, f, hop, rate), v));
    }
    // o refinamento pode juntar dois cortes: fica o mais forte de cada par próximo demais
    found.sort_by_key(|&(at, _)| at);
    let min_gap = (MIN_GAP_SECS * rate) as usize / 2;
    let mut kept: Vec<(usize, f64)> = Vec::new();
    for c in found {
        match kept.last_mut() {
            Some(last) if c.0 - last.0 < min_gap => {
                if c.1 > last.1 {
                    *last = c;
                }
            }
            _ => kept.push(c),
        }
    }
    kept.retain(|&(at, _)| at > edge && at + edge < n);
    if kept.len() > MAX_SLICES - 1 {
        kept.sort_by(|a, b| b.1.total_cmp(&a.1));
        kept.truncate(MAX_SLICES - 1);
        kept.sort_by_key(|&(at, _)| at);
    }
    points.extend(kept.into_iter().map(|(at, _)| at));
    points
}

/// Onde o ataque do quadro de envelope `f` começa no áudio.
fn onset(mono: &[f32], f: usize, hop: usize, rate: f64) -> usize {
    let n = mono.len();
    let from = f.saturating_sub(1) * hop;
    let peak = mono[f * hop..((f + 2) * hop).min(n)].iter().fold(0.0f32, |a, &v| a.max(v.abs()));
    let mut at = (from..((f + 1) * hop).min(n)).find(|&i| mono[i].abs() >= 0.1 * peak).unwrap_or(f * hop);
    let back = (0.002 * rate) as usize;
    if let Some(zero) = (at.saturating_sub(back).max(1)..=at).rev().find(|&j| j < n && (mono[j - 1] <= 0.0) != (mono[j] <= 0.0)) {
        at = zero;
    }
    at
}

/// Uma zona de uma nota por fatia, a partir de `first_note` (cromático): cada uma toca só a fatia
/// `[pontos[i], pontos[i+1])`, até o fim, na altura original (a nota é a base). `points` em segundos,
/// crescentes (a saída de [`slice_points`]); pontos fora de ordem ou repetidos são pulados; para no
/// limite de notas (127) ou de [`MAX_SLICES`].
pub fn slice_zones(points: &[f64], first_note: u8) -> Vec<ZoneDef> {
    let mut clean: Vec<f64> = Vec::new();
    for &p in points {
        if p.is_finite() && p >= 0.0 && clean.last().is_none_or(|&l| p > l) {
            clean.push(p);
        }
    }
    clean
        .iter()
        .enumerate()
        .take(MAX_SLICES)
        .map_while(|(i, &start)| {
            let note = u8::try_from(usize::from(first_note) + i).ok().filter(|&n| n <= 127)?;
            let end = clean.get(i + 1).copied().unwrap_or(0.0);
            Some(ZoneDef { root: note, lo: note, hi: note, one_shot: true, start, end, ..ZoneDef::default() })
        })
        .collect()
}
