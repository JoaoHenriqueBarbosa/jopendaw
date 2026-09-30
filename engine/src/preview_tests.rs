//! Testes da pré-escuta (`preview.rs`): a voz à parte do transporte.

use crate::{Engine, Sample};

const RATE: f64 = 48_000.0;

fn tone(rate: f64, secs: f64) -> Sample {
    let n = (rate * secs) as usize;
    Sample::new(vec![(0..n).map(|i| 0.5 * (std::f64::consts::TAU * 440.0 * i as f64 / rate).sin() as f32).collect()], rate)
}

fn block(e: &mut Engine, frames: usize) -> (Vec<f32>, Vec<f32>) {
    let (mut l, mut r) = (vec![0.0; frames], vec![0.0; frames]);
    e.process(&mut l, &mut r);
    (l, r)
}

fn peak(v: &[f32]) -> f32 {
    v.iter().fold(0.0, |m, s| m.max(s.abs()))
}

#[test]
fn toca_com_o_transporte_parado_e_sem_mexer_nele() {
    let mut e = Engine::new(RATE);
    e.load_sample(7, tone(RATE, 1.0));
    assert_eq!(peak(&block(&mut e, 256).0), 0.0);
    e.preview_play(7, 0.0, 1.0);
    let (l, r) = block(&mut e, 512);
    assert!(peak(&l) > 0.3 && peak(&r) > 0.3, "mono sai nos dois lados");
    assert!(!e.playing());
    assert_eq!(e.beat(), 0.0);
}

#[test]
fn para_com_fade_e_fica_mudo() {
    let mut e = Engine::new(RATE);
    e.load_sample(7, tone(RATE, 1.0));
    e.preview_play(7, 0.0, 1.0);
    block(&mut e, 1024);
    e.preview_stop();
    let (l, _) = block(&mut e, 128);
    assert!(peak(&l) > 0.0, "ainda sai o começo do fade");
    // o fade dura 12 ms (576 quadros)
    block(&mut e, 1024);
    assert_eq!(peak(&block(&mut e, 512).0), 0.0);
}

#[test]
fn acaba_no_fim_do_audio_e_respeita_o_inicio() {
    let mut e = Engine::new(RATE);
    e.load_sample(7, tone(RATE, 0.1));
    e.preview_play(7, 0.05, 1.0);
    // sobram 0,05 s (2400 quadros)
    let (l, _) = block(&mut e, 4800);
    assert!(peak(&l[..2000]) > 0.3);
    assert_eq!(peak(&l[2500..]), 0.0);
    // início além do fim: nada toca
    e.preview_play(7, 5.0, 1.0);
    assert_eq!(peak(&block(&mut e, 512).0), 0.0);
}

#[test]
fn converte_a_taxa_do_audio_para_a_do_motor() {
    let mut e = Engine::new(RATE);
    // 0,5 s em 24 kHz dura 0,5 s na saída: 24000 quadros
    e.load_sample(7, tone(24_000.0, 0.5));
    e.preview_play(7, 0.0, 1.0);
    let (l, _) = block(&mut e, 30_000);
    assert!(peak(&l[22_000..23_900]) > 0.3);
    assert_eq!(peak(&l[24_200..]), 0.0);
}

#[test]
fn trocar_de_audio_deixa_o_antigo_sair_com_fade() {
    let mut e = Engine::new(RATE);
    e.load_sample(7, tone(RATE, 1.0));
    e.load_sample(8, tone(RATE, 1.0));
    e.preview_play(7, 0.0, 1.0);
    block(&mut e, 1024);
    e.preview_play(8, 0.0, 1.0);
    let (l, _) = block(&mut e, 2048);
    assert!(peak(&l) > 0.3);
    // id que não existe não derruba o que toca
    e.preview_play(99, 0.0, 1.0);
    assert!(peak(&block(&mut e, 512).0) > 0.3);
}

#[test]
fn nunca_passa_do_limite_e_nao_toca_no_medidor() {
    let mut e = Engine::new(RATE);
    e.load_sample(7, tone(RATE, 1.0));
    e.preview_play(7, 0.0, 2.0);
    let (l, _) = block(&mut e, 4096);
    assert!(peak(&l) > 0.5 && peak(&l) <= 1.0);
    assert_eq!(e.master_mut().take_peaks(), (0.0, 0.0));
}
