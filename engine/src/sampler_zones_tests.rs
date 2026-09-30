//! Testes das zonas e do fatiamento do sampler (submódulo de `sampler_zones.rs`).

use super::slice_ref::*;
use super::*;
use crate::instrument::{Instrument, kind, sampler_param as param};

const RATE: f64 = 48_000.0;

fn sampler() -> Sampler {
    let mut s = Sampler::new(RATE);
    s.set_param(param::LEVEL, 1.0);
    s.set_param(param::VELOCITY, 0.0);
    s.set_param(param::ATTACK, 0.0005);
    s
}

fn audio(channels: Vec<Vec<f32>>, rate: f64) -> Arc<Sample> {
    Arc::new(Sample::new(channels, rate))
}

fn constant(v: f32, frames: usize) -> Arc<Sample> {
    audio(vec![vec![v; frames]], RATE)
}

fn ramp(frames: usize) -> Arc<Sample> {
    audio(vec![(0..frames).map(|i| i as f32 / frames as f32).collect()], RATE)
}

/// Zona de faixa de notas dada, sobre o que `ZoneDef::default` dá.
fn zone(lo: u8, hi: u8) -> ZoneDef {
    ZoneDef { lo, hi, ..ZoneDef::default() }
}

fn add(s: &mut Sampler, id: u32, a: &Arc<Sample>, def: ZoneDef) {
    s.zone_add(def, id, Some(a.clone()));
}

fn render(s: &mut Sampler, frames: usize) -> (Vec<f32>, Vec<f32>) {
    let (mut l, mut r) = (vec![0.0; frames], vec![0.0; frames]);
    for (cl, cr) in l.chunks_mut(128).zip(r.chunks_mut(128)) {
        s.render(cl, cr);
    }
    (l, r)
}

fn voices(s: &Sampler) -> usize {
    s.voices.iter().filter(|v| v.on).count()
}

/// Nível em regime de uma nota (depois do ataque).
fn level_of(s: &mut Sampler, pitch: u8, velocity: f32) -> f32 {
    s.silence();
    s.note_on(pitch, velocity);
    let (l, _) = render(s, 400);
    l[399]
}

// ---------------------------------------------------------------- compatibilidade

#[test]
fn zona_que_cobre_tudo_e_o_sampler_de_sempre() {
    // o mesmo áudio, o mesmo pedido: com uma zona que cobre tudo na nota base o resultado é o
    // do sampler de sample único, quadro a quadro
    let a = audio(vec![(0..20_000).map(|i| (i as f32 * 0.05).sin() * 0.5).collect()], RATE);
    let mut legacy = sampler();
    legacy.set_sample(Some(a.clone()));
    let mut zoned = sampler();
    add(&mut zoned, 1, &a, ZoneDef::default());
    for pitch in [60u8, 67, 48, 84] {
        legacy.silence();
        zoned.silence();
        legacy.note_on(pitch, 0.9);
        zoned.note_on(pitch, 0.9);
        let (a, ar) = render(&mut legacy, 3000);
        let (b, br) = render(&mut zoned, 3000);
        assert_eq!(a, b, "nota {pitch}");
        assert_eq!(ar, br, "nota {pitch}");
    }
}

#[test]
fn limpar_as_zonas_volta_ao_sample_unico() {
    let a = constant(0.5, 48_000);
    let mut s = sampler();
    s.set_sample(Some(constant(0.25, 48_000)));
    add(&mut s, 1, &a, zone(0, 127));
    assert!((level_of(&mut s, 60, 1.0) - 0.5).abs() < 1e-3);
    s.clear_zones();
    assert!(s.zones.is_empty());
    assert!((level_of(&mut s, 60, 1.0) - 0.25).abs() < 1e-3, "toca o áudio único de novo");
}

#[test]
fn com_zonas_o_audio_unico_e_ignorado() {
    let mut s = sampler();
    s.set_sample(Some(constant(0.25, 48_000)));
    add(&mut s, 1, &constant(0.5, 48_000), zone(72, 72));
    s.note_on(60, 1.0);
    assert!(!s.active(), "nenhuma zona cobre a nota 60");
}

// ---------------------------------------------------------------- notas, velocidade, camadas

#[test]
fn faixa_de_notas_inclui_os_limites_e_lacunas_calam() {
    let a = constant(0.5, 48_000);
    let mut s = sampler();
    add(&mut s, 1, &a, zone(40, 50));
    add(&mut s, 1, &a, zone(60, 60));
    for (pitch, sounds) in
        [(39, false), (40, true), (45, true), (50, true), (51, false), (55, false), (59, false), (60, true), (61, false), (0, false), (127, false)]
    {
        s.silence();
        s.note_on(pitch, 1.0);
        assert_eq!(s.active(), sounds, "nota {pitch}");
    }
}

#[test]
fn notas_nas_pontas_do_teclado() {
    let a = constant(0.5, 48_000);
    let mut s = sampler();
    add(&mut s, 1, &a, zone(0, 0));
    add(&mut s, 1, &a, zone(127, 127));
    for (pitch, sounds) in [(0, true), (1, false), (126, false), (127, true)] {
        s.silence();
        s.note_on(pitch, 1.0);
        assert_eq!(s.active(), sounds, "nota {pitch}");
        let (l, _) = render(&mut s, 1000);
        assert!(l.iter().all(|x| x.is_finite()));
    }
}

#[test]
fn camadas_de_velocidade_escolhem_pela_velocidade() {
    let mut s = sampler();
    add(&mut s, 1, &constant(0.2, 48_000), ZoneDef { vlo: 1, vhi: 63, ..zone(0, 127) });
    add(&mut s, 2, &constant(0.6, 48_000), ZoneDef { vlo: 64, vhi: 127, ..zone(0, 127) });
    // 63/127 e 64/127 são os dois lados da fronteira
    assert!((level_of(&mut s, 60, 63.0 / 127.0) - 0.2).abs() < 1e-3);
    assert!((level_of(&mut s, 60, 64.0 / 127.0) - 0.6).abs() < 1e-3);
    // velocidade máxima, mínima e zero (no MIDI zero é note off, aqui vale como a mais leve)
    assert!((level_of(&mut s, 60, 1.0) - 0.6).abs() < 1e-3);
    assert!((level_of(&mut s, 60, 0.0) - 0.2).abs() < 1e-3);
    assert!((level_of(&mut s, 60, f32::NAN) - 0.2).abs() < 1e-3);
    assert!((level_of(&mut s, 60, 7.0) - 0.6).abs() < 1e-3, "acima de 1 é limitada");
}

#[test]
fn faixa_de_velocidade_com_lacuna_cala() {
    let mut s = sampler();
    add(&mut s, 1, &constant(0.2, 48_000), ZoneDef { vlo: 100, vhi: 127, ..zone(0, 127) });
    s.note_on(60, 0.3);
    assert!(!s.active());
    s.note_on(60, 1.0);
    assert!(s.active());
}

#[test]
fn zonas_sobrepostas_empilham() {
    let mut s = sampler();
    add(&mut s, 1, &constant(0.25, 48_000), zone(50, 70));
    add(&mut s, 2, &constant(0.5, 48_000), zone(60, 80));
    assert!((level_of(&mut s, 55, 1.0) - 0.25).abs() < 1e-3);
    assert!((level_of(&mut s, 65, 1.0) - 0.75).abs() < 1e-3, "as duas soam");
    assert!((level_of(&mut s, 75, 1.0) - 0.5).abs() < 1e-3);
    s.silence();
    s.note_on(65, 1.0);
    assert_eq!(voices(&s), 2);
}

#[test]
fn ganho_e_pan_da_zona() {
    let mut s = sampler();
    add(&mut s, 1, &constant(0.5, 48_000), ZoneDef { gain_db: -6.0206, ..zone(0, 127) });
    assert!((level_of(&mut s, 60, 1.0) - 0.25).abs() < 1e-3);
    s.clear_zones();
    add(&mut s, 1, &constant(0.5, 48_000), ZoneDef { pan: -1.0, ..zone(0, 127) });
    s.silence();
    s.note_on(60, 1.0);
    let (l, r) = render(&mut s, 400);
    assert!((l[399] - 0.5).abs() < 1e-3 && r[399] == 0.0, "{} {}", l[399], r[399]);
    s.clear_zones();
    s.silence();
    add(&mut s, 1, &constant(0.5, 48_000), ZoneDef { pan: 0.5, ..zone(0, 127) });
    s.note_on(60, 1.0);
    let (l, r) = render(&mut s, 400);
    assert!((l[399] - 0.25).abs() < 1e-3 && (r[399] - 0.5).abs() < 1e-3);
}

// ---------------------------------------------------------------- afinação e taxas

#[test]
fn nota_base_e_cents_da_zona() {
    let a = ramp(48_000);
    let mut s = sampler();
    add(&mut s, 1, &a, ZoneDef { root: 48, ..zone(0, 127) });
    s.note_on(60, 1.0);
    assert_eq!(s.voices.iter().find(|v| v.on).unwrap().step, 2.0);
    s.clear_zones();
    s.silence();
    add(&mut s, 1, &a, ZoneDef { cents: 1200.0, ..zone(0, 127) });
    s.note_on(60, 1.0);
    assert!((s.voices.iter().find(|v| v.on).unwrap().step - 2.0).abs() < 1e-12);
    // a afinação do instrumento soma com a da zona, e reafina a voz soando
    s.set_param(param::TUNE, -100.0);
    let want = (1100.0f64 / 1200.0).exp2();
    assert!((s.voices.iter().find(|v| v.on).unwrap().step - want).abs() < 1e-12);
}

#[test]
fn zonas_de_taxas_e_canais_diferentes() {
    let mut s = sampler();
    // 24 kHz mono e 96 kHz estéreo, cada uma na sua nota
    add(&mut s, 1, &audio(vec![vec![0.5; 24_000]], 24_000.0), zone(60, 60));
    add(&mut s, 2, &audio(vec![vec![0.25; 96_000], vec![-0.25; 96_000]], 96_000.0), ZoneDef { root: 62, ..zone(62, 62) });
    s.note_on(60, 1.0);
    assert_eq!(s.voices.iter().find(|v| v.on).unwrap().step, 0.5);
    let (l, r) = render(&mut s, 400);
    assert!((l[399] - 0.5).abs() < 1e-3 && (r[399] - 0.5).abs() < 1e-3, "mono nos dois lados");
    s.silence();
    s.note_on(62, 1.0);
    assert_eq!(s.voices.iter().find(|v| v.on).unwrap().step, 2.0);
    let (l, r) = render(&mut s, 400);
    assert!((l[399] - 0.25).abs() < 1e-3 && (r[399] + 0.25).abs() < 1e-3, "estéreo");
}

// ---------------------------------------------------------------- trecho, loop, modos

#[test]
fn trecho_toca_so_o_que_esta_entre_inicio_e_fim() {
    let a = ramp(48_000);
    let mut s = sampler();
    // de 0,25 s a 0,30 s: 2400 quadros
    add(&mut s, 1, &a, ZoneDef { start: 0.25, end: 0.30, one_shot: true, ..zone(0, 127) });
    s.note_on(60, 1.0);
    let (l, _) = render(&mut s, 4000);
    assert!(!s.active(), "acabou no fim do trecho");
    assert!((l[200] - 0.25).abs() < 0.01, "começa em 0,25 do áudio: {}", l[200]);
    assert!(l[2300] < 0.31 && l[2300] > 0.28, "{}", l[2300]);
    assert!(l[2401..].iter().all(|&x| x == 0.0), "nada depois do fim");
    // desce a zero no fim (sem estalo)
    assert!(l[2399].abs() < 0.02, "{}", l[2399]);
    let max_jump = l.windows(2).skip(30).map(|w| (w[1] - w[0]).abs()).fold(0.0, f32::max);
    assert!(max_jump < 0.02, "{max_jump}");
}

#[test]
fn trechos_vazios_ou_invertidos_nao_soam() {
    let a = constant(0.5, 4800);
    let mut s = sampler();
    add(&mut s, 1, &a, ZoneDef { start: 0.05, end: 0.02, ..zone(0, 127) });
    add(&mut s, 1, &a, ZoneDef { start: 5.0, ..zone(0, 127) });
    add(&mut s, 1, &a, ZoneDef { start: 0.1, end: 0.1, ..zone(0, 127) });
    s.note_on(60, 1.0);
    assert!(!s.active());
    // fim além do áudio vale o fim do áudio
    s.clear_zones();
    add(&mut s, 1, &a, ZoneDef { start: 0.0, end: 99.0, ..zone(0, 127) });
    s.note_on(60, 1.0);
    render(&mut s, 6000);
    assert!(!s.active());
}

#[test]
fn loop_sustenta_a_nota_enquanto_ela_esta_presa() {
    // rampa de 0..1 em 4800 quadros; o loop é o trecho de 1000 a 2000
    let a = ramp(4800);
    let mut s = sampler();
    add(&mut s, 1, &a, ZoneDef { loop_start: 1000.0 / RATE, loop_end: 2000.0 / RATE, ..zone(0, 127) });
    s.note_on(60, 1.0);
    let (l, _) = render(&mut s, 24_000);
    assert!(s.active(), "o loop mantém a voz viva muito além do fim do áudio");
    let lo = 1000.0 / 4800.0 - 0.01;
    let hi = 2000.0 / 4800.0 + 0.01;
    assert!(l[3000..].iter().all(|&x| x > lo && x < hi), "fica dentro do loop");
    // periódico: 1000 quadros
    for i in 5000..6000 {
        assert!((l[i] - l[i + 1000]).abs() < 1e-3, "quadro {i}");
    }
    s.note_off(60);
    let (l, _) = render(&mut s, 24_000);
    assert!(!s.active(), "o release acaba a voz");
    assert!(l.iter().all(|x| x.is_finite()));
}

#[test]
fn loop_de_uma_amostra_e_de_uma_amostra_so() {
    let a = audio(vec![(0..1000).map(|i| if i == 500 { 0.7 } else { 0.1 }).collect()], RATE);
    let mut s = sampler();
    add(&mut s, 1, &a, ZoneDef { loop_start: 500.0 / RATE, loop_end: 501.0 / RATE, ..zone(0, 127) });
    s.note_on(60, 1.0);
    let (l, _) = render(&mut s, 20_000);
    assert!(s.active());
    // depois de chegar na amostra do loop o som é o valor dela, constante
    assert!(l[2000..].iter().all(|&x| (x - 0.7).abs() < 1e-3), "{} {}", l[2000], l[19_999]);
}

#[test]
fn loop_e_ignorado_no_modo_ate_o_fim() {
    let a = ramp(4800);
    let mut s = sampler();
    add(&mut s, 1, &a, ZoneDef { one_shot: true, loop_start: 0.01, loop_end: 0.05, ..zone(0, 127) });
    s.note_on(60, 1.0);
    render(&mut s, 6000);
    assert!(!s.active());
}

#[test]
fn loop_fora_do_trecho_e_descartado() {
    let a = ramp(4800);
    let mut s = sampler();
    // loop invertido, e loop que termina antes do começo do trecho
    add(&mut s, 1, &a, ZoneDef { loop_start: 0.05, loop_end: 0.02, ..zone(0, 127) });
    add(&mut s, 1, &a, ZoneDef { start: 0.05, loop_start: 0.0, loop_end: 0.04, ..zone(0, 127) });
    assert!(s.zones.iter().all(|z| z.span.unwrap().looped.is_none()));
    s.note_on(60, 1.0);
    render(&mut s, 6000);
    assert!(!s.active());
}

#[test]
fn modo_sustentado_solta_e_modo_ate_o_fim_nao() {
    let a = constant(0.5, 48_000);
    let mut s = sampler();
    s.set_param(param::RELEASE, 0.005);
    add(&mut s, 1, &a, zone(60, 60));
    add(&mut s, 1, &a, ZoneDef { one_shot: true, ..zone(62, 62) });
    s.note_on(60, 1.0);
    s.note_on(62, 1.0);
    render(&mut s, 500);
    s.note_off(60);
    s.note_off(62);
    render(&mut s, 2000);
    assert_eq!(voices(&s), 1, "só a sustentada acabou");
    assert_eq!(s.voices.iter().find(|v| v.on).unwrap().pitch, 62);
    // o parâmetro de um-tiro do instrumento não vale com zonas
    s.set_param(param::ONE_SHOT, 1.0);
    s.note_on(60, 1.0);
    render(&mut s, 100);
    s.note_off(60);
    render(&mut s, 2000);
    assert_eq!(voices(&s), 1);
    // e parar o transporte solta até as de um tiro
    s.release_all();
    render(&mut s, 2000);
    assert!(!s.active());
}

#[test]
fn mesma_nota_de_novo_solta_todas_as_camadas_antigas() {
    let mut s = sampler();
    add(&mut s, 1, &constant(0.2, 48_000), zone(0, 127));
    add(&mut s, 2, &constant(0.2, 48_000), zone(0, 127));
    s.note_on(60, 1.0);
    s.note_on(60, 1.0);
    let on: Vec<_> = s.voices.iter().filter(|v| v.on).collect();
    assert_eq!(on.len(), 4);
    assert_eq!(on.iter().filter(|v| v.released).count(), 2, "só as antigas entram no release");
}

#[test]
fn mesma_nota_de_novo_nao_corta_a_voz_ate_o_fim() {
    let mut s = sampler();
    s.set_param(param::RELEASE, 0.001);
    add(&mut s, 1, &constant(0.2, 48_000), ZoneDef { one_shot: true, ..zone(0, 127) });
    s.note_on(60, 1.0);
    render(&mut s, 200);
    s.note_on(60, 1.0);
    assert_eq!(s.voices.iter().filter(|v| v.on && v.released).count(), 0, "nenhuma entra no release");
    render(&mut s, 2000);
    assert_eq!(voices(&s), 2, "a anterior segue soando e a nova empilha");
    // até o limite de vozes: depois disso a mais antiga é roubada
    for _ in 0..VOICES + 4 {
        s.note_on(60, 1.0);
    }
    assert!(s.voices.iter().filter(|v| v.held()).count() <= VOICES);
}

#[test]
fn sustentacao_baixa_nao_faz_decair_a_voz_ate_o_fim() {
    let mut s = sampler();
    s.set_param(param::DECAY, 0.01);
    s.set_param(param::SUSTAIN, 0.2);
    add(&mut s, 1, &constant(0.5, 48_000), ZoneDef { one_shot: true, ..zone(60, 60) });
    add(&mut s, 2, &constant(0.5, 48_000), zone(62, 62));
    s.note_on(60, 1.0);
    s.note_on(62, 1.0);
    let (l, _) = render(&mut s, 12_000);
    // as duas somadas: a sustentada caiu a 20% (0,1), a até o fim segue em 0,5
    assert!((l[11_999] - 0.6).abs() < 0.01, "{}", l[11_999]);
    // mexer na sustentação com a voz soando também não a derruba
    s.set_param(param::SUSTAIN, 0.0);
    let (l, _) = render(&mut s, 12_000);
    assert!((l[11_999] - 0.5).abs() < 0.01, "{}", l[11_999]);
}

// ---------------------------------------------------------------- round-robin

#[test]
fn round_robin_alterna_as_zonas_do_grupo() {
    let mut s = sampler();
    add(&mut s, 1, &constant(0.1, 48_000), ZoneDef { group: 1, ..zone(0, 127) });
    add(&mut s, 2, &constant(0.2, 48_000), ZoneDef { group: 1, ..zone(0, 127) });
    add(&mut s, 3, &constant(0.4, 48_000), ZoneDef { group: 1, ..zone(0, 127) });
    // uma camada fora do grupo toca sempre (0,05)
    add(&mut s, 4, &constant(0.05, 48_000), zone(0, 127));
    let got: Vec<f32> = (0..6).map(|_| level_of(&mut s, 60, 1.0)).collect();
    let want = [0.15, 0.25, 0.45, 0.15, 0.25, 0.45];
    for (g, w) in got.iter().zip(want) {
        assert!((g - w).abs() < 1e-3, "{got:?}");
    }
}

#[test]
fn round_robin_so_conta_as_zonas_que_casam() {
    let mut s = sampler();
    add(&mut s, 1, &constant(0.1, 48_000), ZoneDef { group: 2, ..zone(0, 59) });
    add(&mut s, 2, &constant(0.3, 48_000), ZoneDef { group: 2, ..zone(60, 127) });
    // no grave só a primeira casa: não há o que alternar
    assert!((level_of(&mut s, 50, 1.0) - 0.1).abs() < 1e-3);
    assert!((level_of(&mut s, 50, 1.0) - 0.1).abs() < 1e-3);
    assert!((level_of(&mut s, 70, 1.0) - 0.3).abs() < 1e-3);
    assert!((level_of(&mut s, 70, 1.0) - 0.3).abs() < 1e-3);
}

// ---------------------------------------------------------------- áudio ausente, trocado, removido

#[test]
fn zona_sem_audio_carregado_fica_calada_ate_o_audio_chegar() {
    let mut s = sampler();
    s.zone_add(zone(0, 127), 7, None);
    s.note_on(60, 1.0);
    assert!(!s.active());
    s.zone_sample(8, Some(constant(0.5, 48_000)));
    s.note_on(60, 1.0);
    assert!(!s.active(), "outro id não liga");
    s.zone_sample(7, Some(constant(0.5, 48_000)));
    assert!((level_of(&mut s, 60, 1.0) - 0.5).abs() < 1e-3);
    s.zone_sample(7, None);
    s.silence();
    s.note_on(60, 1.0);
    assert!(!s.active());
}

#[test]
fn audio_removido_com_a_nota_tocando_deixa_a_voz_terminar() {
    let mut s = sampler();
    let a = constant(0.5, 48_000);
    add(&mut s, 7, &a, zone(0, 127));
    s.note_on(60, 1.0);
    render(&mut s, 500);
    drop(a);
    s.zone_sample(7, None);
    let (l, _) = render(&mut s, 500);
    assert!((l[499] - 0.5).abs() < 1e-3, "a voz segue no áudio que guardou");
    s.set_param(param::RELEASE, 0.001);
    s.note_off(60);
    render(&mut s, 4000);
    assert!(!s.active());
    assert!(s.voices.iter().all(|v| v.own.is_none()), "soltou o áudio");
}

#[test]
fn mexer_nas_zonas_com_voz_soando_nao_corta() {
    let mut s = sampler();
    add(&mut s, 1, &constant(0.5, 48_000), zone(0, 127));
    s.note_on(60, 1.0);
    render(&mut s, 300);
    s.clear_zones();
    add(&mut s, 2, &constant(0.1, 48_000), zone(0, 127));
    let (l, _) = render(&mut s, 300);
    assert!((l[299] - 0.5).abs() < 1e-3, "a voz antiga segue igual");
    s.note_on(62, 1.0);
    let (l, _) = render(&mut s, 300);
    assert!((l[299] - 0.6).abs() < 1e-3, "e a nota nova toca a zona nova: {}", l[299]);
}

#[test]
fn muitas_zonas_e_notas_nao_estouram_nem_alocam() {
    let mut s = sampler();
    let cap = s.zones.capacity();
    assert!(cap >= MAX_ZONES);
    for _ in 0..MAX_ZONES + 50 {
        add(&mut s, 1, &constant(0.01, 48_000), zone(0, 127));
    }
    assert_eq!(s.zones.len(), MAX_ZONES);
    assert_eq!(s.zones.capacity(), cap, "a lista não cresceu");
    for p in 0..100u8 {
        s.note_on(p, 1.0);
    }
    assert!(s.voices.iter().filter(|v| v.held()).count() <= VOICES);
    let (l, r) = render(&mut s, 512);
    assert!(l.iter().chain(&r).all(|x| x.is_finite()));
    assert_eq!(s.zones.capacity(), cap);
}

#[test]
fn amostras_curtissimas_nao_quebram() {
    for frames in [1usize, 2, 3, 4] {
        let mut s = sampler();
        let a = audio(vec![vec![0.5; frames]], RATE);
        add(&mut s, 1, &a, zone(0, 127));
        add(&mut s, 1, &a, ZoneDef { loop_start: 0.0, loop_end: frames as f64 / RATE, ..zone(0, 127) });
        add(&mut s, 1, &a, ZoneDef { one_shot: true, pan: 0.3, cents: 700.0, ..zone(0, 127) });
        for pitch in [0u8, 60, 127] {
            s.note_on(pitch, 1.0);
        }
        let (l, r) = render(&mut s, 2000);
        assert!(l.iter().chain(&r).all(|x| x.is_finite()), "{frames} quadros");
        s.set_param(param::RELEASE, 0.001);
        s.release_all();
        render(&mut s, 4000);
        assert!(!s.active(), "{frames} quadros");
    }
}

#[test]
fn zona_de_um_quadro_via_trecho() {
    let a = audio(vec![(0..100).map(|i| i as f32 / 100.0).collect()], RATE);
    let mut s = sampler();
    add(&mut s, 1, &a, ZoneDef { start: 50.0 / RATE, end: 51.0 / RATE, one_shot: true, ..zone(0, 127) });
    s.note_on(60, 1.0);
    let (l, _) = render(&mut s, 500);
    assert!(!s.active());
    assert!(l.iter().all(|x| x.is_finite() && x.abs() < 0.6));
}

// ---------------------------------------------------------------- sanitização

#[test]
fn definicao_e_limitada_as_faixas() {
    let d = ZoneDef {
        root: 200,
        lo: 90,
        hi: 10,
        vlo: 0,
        vhi: 0,
        cents: f32::NAN,
        gain_db: 999.0,
        pan: -9.0,
        group: 250,
        start: -1.0,
        end: f64::NAN,
        loop_start: f64::INFINITY,
        loop_end: 3.0,
        ..ZoneDef::default()
    }
    .sanitized();
    assert_eq!((d.root, d.lo, d.hi, d.vlo, d.vhi), (127, 10, 90, 1, 1));
    assert_eq!((d.cents, d.gain_db, d.pan), (0.0, 24.0, -1.0));
    assert_eq!(usize::from(d.group), MAX_GROUPS - 1);
    assert_eq!((d.start, d.end, d.loop_start, d.loop_end), (0.0, 0.0, 0.0, 3.0));
    assert!(d.matches(50, 1) && !d.matches(9, 1) && !d.matches(91, 1) && !d.matches(50, 2));
}

// ---------------------------------------------------------------- pelo motor e pela API

fn engine_with_sampler() -> crate::Engine {
    let mut e = crate::Engine::new(RATE);
    e.set_limiter(false);
    e.set_track_count(2);
    e.set_track_kind(0, kind::SAMPLER);
    e.set_param(0, param::LEVEL, 1.0);
    e.set_param(0, param::VELOCITY, 0.0);
    e
}

fn peak(e: &mut crate::Engine, blocks: usize) -> f32 {
    let (mut l, mut r) = ([0.0f32; 128], [0.0f32; 128]);
    let mut p = 0.0f32;
    for _ in 0..blocks {
        e.process(&mut l, &mut r);
        p = l.iter().chain(&r).fold(p, |a, &x| a.max(x.abs()));
    }
    p
}

#[test]
fn motor_liga_a_zona_quando_o_audio_chega_e_solta_quando_sai() {
    let mut e = engine_with_sampler();
    e.add_zone(0, 5, zone(0, 127));
    e.live_on(0, 60, 1.0);
    assert_eq!(peak(&mut e, 8), 0.0, "sem o áudio ainda");
    e.live_off(0, 60);
    e.load_sample(5, Sample::new(vec![vec![0.5; 48_000]], RATE));
    e.live_on(0, 60, 1.0);
    assert!(peak(&mut e, 8) > 0.3, "o áudio chegou depois da zona");
    e.panic();
    e.drop_sample(5);
    peak(&mut e, 200);
    e.live_on(0, 60, 1.0);
    assert_eq!(peak(&mut e, 8), 0.0, "áudio descartado");
    // zona em faixa que não é de sampler, ou que não existe, não faz nada
    e.add_zone(1, 5, zone(0, 127));
    e.add_zone(9, 5, zone(0, 127));
    e.clear_zones(1);
    e.clear_zones(9);
}

#[test]
fn motor_termina_a_nota_de_um_sample_removido_com_ela_tocando() {
    let mut e = engine_with_sampler();
    e.load_sample(5, Sample::new(vec![vec![0.5; 48_000]], RATE));
    e.add_zone(0, 5, zone(0, 127));
    e.live_on(0, 60, 1.0);
    assert!(peak(&mut e, 4) > 0.3);
    e.drop_sample(5);
    assert!(peak(&mut e, 4) > 0.3, "a nota que soava termina");
}

#[test]
fn api_manda_a_zona_como_o_export() {
    let mut e = engine_with_sampler();
    e.load_sample(5, Sample::new(vec![vec![0.5; 48_000]], RATE));
    let args = [0.0, 5.0, 60.0, 50.0, 70.0, 1.0, 127.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0];
    crate::api::apply(&mut e, "zone_add", &args).unwrap();
    e.live_on(0, 80, 1.0);
    assert_eq!(peak(&mut e, 8), 0.0, "fora da faixa de notas");
    e.live_on(0, 60, 1.0);
    assert!(peak(&mut e, 8) > 0.3);
    crate::api::apply(&mut e, "zones_clear", &[0.0]).unwrap();
    e.panic();
    peak(&mut e, 200);
    e.live_on(0, 60, 1.0);
    assert_eq!(peak(&mut e, 8), 0.0, "sem zonas e sem áudio único");
    // notas e velocidades acima de 127 são limitadas, faltando argumento é erro
    let args = [0.0, 5.0, 60.0, 500.0, 900.0, 0.0, 999.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0];
    crate::api::apply(&mut e, "zone_add", &args).unwrap();
    assert_eq!(e.tracks().len(), 2);
    assert!(crate::api::apply(&mut e, "zone_add", &args[..15]).is_err());
}

// ---------------------------------------------------------------- fatiamento

/// Explosões de ruído com decaimento em silêncio quase total (ruído determinístico).
fn bursts(starts: &[(f64, f32)], secs: f64) -> Vec<f32> {
    let n = (secs * RATE) as usize;
    let mut x = vec![0.0f32; n];
    let mut seed = 12345u32;
    let mut rnd = || {
        seed = seed.wrapping_mul(1_664_525).wrapping_add(1_013_904_223);
        (seed >> 8) as f32 / (1u32 << 24) as f32 * 2.0 - 1.0
    };
    for v in &mut x {
        *v = 1e-4 * rnd();
    }
    for &(t, amp) in starts {
        let s = (t * RATE) as usize;
        for k in 0..(0.12 * RATE) as usize {
            if s + k < n {
                let env = (-(k as f32) / (0.03 * RATE as f32)).exp();
                let tone = (std::f32::consts::TAU * 220.0 * k as f32 / RATE as f32).sin();
                x[s + k] += amp * env * (0.6 * tone + 0.4 * rnd());
            }
        }
    }
    x
}

#[test]
fn fatias_iguais() {
    let ch = vec![vec![0.0f32; 48_000]];
    let p = slice_points(&ch, RATE, SliceMode::Count(4));
    assert_eq!(p, vec![0.0, 0.25, 0.5, 0.75]);
    assert_eq!(slice_points(&ch, RATE, SliceMode::Count(1)), vec![0.0, 0.5], "o mínimo é 2");
    assert_eq!(slice_points(&ch, RATE, SliceMode::Count(0)), vec![0.0, 0.5], "zero vira o mínimo");
    assert_eq!(slice_points(&ch, RATE, SliceMode::Count(10_000)).len(), MAX_SLICES);
    // mais fatias do que quadros: uma por quadro
    let tiny = vec![vec![0.0f32; 3]];
    assert_eq!(slice_points(&tiny, RATE, SliceMode::Count(8)), vec![0.0, 1.0 / RATE, 2.0 / RATE]);
    // sem áudio ou taxa inválida: nada
    assert!(slice_points(&[Vec::new()], RATE, SliceMode::Count(4)).is_empty());
    assert!(slice_points(&[], RATE, SliceMode::Count(4)).is_empty());
    assert!(slice_points(&ch, 0.0, SliceMode::Count(4)).is_empty());
    assert!(slice_points(&ch, f64::NAN, SliceMode::Transients(0.5)).is_empty());
}

#[test]
fn transientes_acham_cada_ataque_no_lugar() {
    let hits = [0.30, 0.80, 1.20, 1.75];
    let x = bursts(&[(0.30, 0.8), (0.80, 0.7), (1.20, 0.9), (1.75, 0.6)], 2.4);
    let p = slice_points(&[x], RATE, SliceMode::Transients(0.5));
    assert_eq!(p.len(), 5, "{p:?}");
    assert_eq!(p[0], 0.0);
    for (found, want) in p[1..].iter().zip(hits) {
        assert!(*found <= want + 0.001 && *found > want - 0.008, "achou {found}, ataque em {want}");
    }
    assert!(p.windows(2).all(|w| w[1] > w[0]));
}

#[test]
fn transientes_estereo_e_taxa_diferente() {
    let x = bursts(&[(0.5, 0.8), (1.0, 0.8)], 1.5);
    let p = slice_points(&[x.clone(), x.clone()], RATE, SliceMode::Transients(0.5));
    assert_eq!(p.len(), 3, "{p:?}");
    let low: Vec<f32> = x.into_iter().step_by(2).collect();
    let p = slice_points(&[low], RATE / 2.0, SliceMode::Transients(0.5));
    assert_eq!(p.len(), 3, "{p:?}");
    assert!((p[1] - 0.5).abs() < 0.01 && (p[2] - 1.0).abs() < 0.01, "{p:?}");
}

#[test]
fn sensibilidade_pega_ataques_fracos() {
    let x = bursts(&[(0.3, 0.8), (0.9, 0.8), (1.5, 0.03)], 2.2);
    let strict = slice_points(std::slice::from_ref(&x), RATE, SliceMode::Transients(0.0));
    let loose = slice_points(std::slice::from_ref(&x), RATE, SliceMode::Transients(1.0));
    assert_eq!(strict.len(), 3, "{strict:?}");
    assert_eq!(loose.len(), 4, "{loose:?}");
    assert!(loose.iter().any(|&t| (t - 1.5).abs() < 0.01));
}

#[test]
fn transientes_de_silencio_tom_e_audio_curto() {
    assert_eq!(slice_points(&[vec![0.0; 48_000]], RATE, SliceMode::Transients(1.0)), vec![0.0]);
    let tone: Vec<f32> = (0..48_000).map(|i| (i as f32 * 0.05).sin() * 0.5).collect();
    assert_eq!(slice_points(&[tone], RATE, SliceMode::Transients(0.5)), vec![0.0], "tom estável não tem ataque");
    assert_eq!(slice_points(&[vec![0.5; 5]], RATE, SliceMode::Transients(0.5)), vec![0.0]);
    assert_eq!(slice_points(&[vec![0.5; 1]], RATE, SliceMode::Transients(f32::NAN)), vec![0.0]);
}

#[test]
fn ataque_colado_no_comeco_ou_no_fim_nao_gera_corte() {
    // estalo em 2 ms do início e outro em 3 ms do fim: já são o começo e o fim
    let mut y = bursts(&[(0.002, 0.9), (1.0, 0.9)], 1.2);
    let n = y.len();
    y[n - 144..].iter_mut().for_each(|v| *v = 0.9);
    let p = slice_points(&[y], RATE, SliceMode::Transients(0.5));
    assert!(p.iter().all(|&t| t == 0.0 || (t > 0.02 && t < 1.2 - 0.01)), "{p:?}");
}

#[test]
fn muitos_ataques_ficam_no_limite_de_fatias() {
    // 150 estalos a cada 80 ms
    let hits: Vec<(f64, f32)> = (0..150).map(|i| (0.1 + i as f64 * 0.08, 0.8)).collect();
    let x = bursts(&hits, 13.0);
    let p = slice_points(&[x], RATE, SliceMode::Transients(0.7));
    assert!(p.len() <= MAX_SLICES && p.len() > 50, "{}", p.len());
    assert!(p.windows(2).all(|w| w[1] > w[0]));
}

#[test]
fn zonas_de_fatias_uma_nota_cada_a_partir_de_c1() {
    let z = slice_zones(&[0.0, 0.25, 0.5, 0.75], FIRST_SLICE_NOTE);
    assert_eq!(z.len(), 4);
    for (i, d) in z.iter().enumerate() {
        let note = 24 + i as u8;
        assert_eq!((d.root, d.lo, d.hi, d.one_shot), (note, note, note, true));
        assert_eq!((d.vlo, d.vhi), (1, 127));
    }
    assert_eq!((z[1].start, z[1].end), (0.25, 0.5));
    assert_eq!(z[3].end, 0.0, "a última vai até o fim");
    // pontos repetidos, fora de ordem ou inválidos são pulados
    let z = slice_zones(&[0.0, 0.0, 0.5, 0.3, f64::NAN, -1.0, 0.9], 60);
    assert_eq!(z.iter().map(|d| d.start).collect::<Vec<_>>(), vec![0.0, 0.5, 0.9]);
    // pára no fim do teclado
    let z = slice_zones(&(0..96).map(f64::from).collect::<Vec<_>>(), 100);
    assert_eq!(z.len(), 28);
    assert_eq!(z.last().unwrap().hi, 127);
    assert!(slice_zones(&[], 24).is_empty());
}

#[test]
fn cada_fatia_toca_so_o_seu_trecho() {
    // quatro degraus de nível: 0,1 / 0,2 / 0,3 / 0,4 (0,25 s cada)
    let x: Vec<f32> = (0..48_000).map(|i| 0.1 * (1 + i / 12_000) as f32).collect();
    let a = audio(vec![x.clone()], RATE);
    let pts = slice_points(&[x], RATE, SliceMode::Count(4));
    let mut s = sampler();
    for d in slice_zones(&pts, FIRST_SLICE_NOTE) {
        s.zone_add(d, 1, Some(a.clone()));
    }
    for (i, want) in [0.1f32, 0.2, 0.3, 0.4].into_iter().enumerate() {
        s.silence();
        s.note_on(24 + i as u8, 1.0);
        let (l, _) = render(&mut s, 12_500);
        assert!((l[6000] - want).abs() < 1e-3, "fatia {i}: {}", l[6000]);
        assert!(!s.active(), "a fatia acaba sozinha");
        assert!(l[12_001..].iter().all(|&v| v == 0.0), "e não toca a seguinte");
    }
    s.note_on(28, 1.0);
    assert!(!s.active(), "nota sem fatia");
}

#[test]
fn zonas_nao_alocam_na_thread_de_audio() {
    let mut s = sampler();
    let a = ramp(20_000);
    let b = audio(vec![vec![0.1; 9000], vec![0.2; 9000]], 44_100.0);
    let (mut l, mut r) = (vec![0.0; 128], vec![0.0; 128]);
    let allocs = crate::testalloc::count(|| {
        s.clear_zones();
        for i in 0..MAX_ZONES as u8 {
            let def = ZoneDef { group: i % 4, loop_start: 0.01, loop_end: 0.1, ..zone(i % 64, 127) };
            s.zone_add(def, 1 + u32::from(i % 2), Some(if i % 2 == 0 { a.clone() } else { b.clone() }));
        }
        for p in 20..90u8 {
            s.note_on(p, 0.8);
            s.render(&mut l, &mut r);
        }
        s.zone_sample(1, None);
        s.zone_sample(2, Some(a.clone()));
        s.note_off(30);
        s.release_all();
        s.set_param(param::TUNE, 30.0);
        for _ in 0..50 {
            s.render(&mut l, &mut r);
        }
        s.silence();
        s.note_on(60, 1.0);
        s.render(&mut l, &mut r);
    });
    assert_eq!(allocs, 0);
}

#[test]
fn trocar_o_audio_unico_nao_mexe_nas_vozes_de_zona() {
    let mut s = sampler();
    add(&mut s, 1, &constant(0.5, 48_000), zone(0, 127));
    s.note_on(60, 1.0);
    render(&mut s, 300);
    // três trocas seguidas do áudio único (o que mataria uma voz que lesse o penúltimo)
    s.set_sample(Some(constant(0.1, 100)));
    s.set_sample(Some(constant(0.2, 100)));
    s.set_sample(None);
    let (l, _) = render(&mut s, 300);
    assert!((l[299] - 0.5).abs() < 1e-3, "{}", l[299]);
    assert_eq!(voices(&s), 1);
}

// ---------------------------------------------------------------- paridade com o Dart

/// O sinal dos vetores de paridade: só aritmética exata (ruído de um LCG inteiro, degraus de potência de dois),
/// para que o Dart (`paritySignal` em `app/test/sampler_zones_test.dart`) gere os mesmos bits.
fn parity_signal() -> Vec<f32> {
    let mut seed = 12345u32;
    let mut rnd = || {
        seed = seed.wrapping_mul(1_664_525).wrapping_add(1_013_904_223);
        f64::from(seed >> 8) / f64::from(1u32 << 24) * 2.0 - 1.0
    };
    let mut x: Vec<f64> = (0..96_000).map(|_| 1e-4 * rnd()).collect();
    for (s, amp) in [(14_400usize, 0.8f64), (38_400, 0.7), (57_600, 0.9), (84_000, 0.6)] {
        for k in 0..5760 {
            x[s + k] += amp * 0.5f64.powi((k / 1440) as i32) * rnd();
        }
    }
    x.into_iter().map(|v| v as f32).collect()
}

/// Os mesmos vetores estão em `app/test/sampler_zones_test.dart` (grupo "paridade com o motor").
#[test]
fn paridade_com_o_dart() {
    let x = parity_signal();
    let want = [0.0, 0.299_979_166_666_666_7, 0.8, 1.2, 1.749_895_833_333_333_4];
    for sensitivity in [0.0f32, 0.5, 1.0] {
        let p = slice_points(std::slice::from_ref(&x), RATE, SliceMode::Transients(sensitivity));
        assert_eq!(p.len(), want.len(), "{p:?}");
        for (a, b) in p.iter().zip(want) {
            assert!((a - b).abs() < 1e-12, "{p:?}");
        }
    }
    let seven = [0.0, 0.148_812_5, 0.297_625, 0.446_437_5, 0.595_229_166_666_666_7, 0.744_041_666_666_666_7, 0.892_854_166_666_666_6];
    let p = slice_points(&[vec![0.0; 50_000]], RATE, SliceMode::Count(7));
    assert_eq!(p.len(), seven.len());
    for (a, b) in p.iter().zip(seven) {
        assert!((a - b).abs() < 1e-12, "{p:?}");
    }
    // e as zonas que o app cria a partir deles: uma nota cada a partir de C1, cada uma até o próximo corte
    let z = slice_zones(&want, FIRST_SLICE_NOTE);
    assert_eq!(
        z.iter().map(|d| (d.root, d.start, d.end)).collect::<Vec<_>>(),
        vec![(24, 0.0, want[1]), (25, want[1], 0.8), (26, 0.8, 1.2), (27, 1.2, want[4]), (28, want[4], 0.0)]
    );
}
