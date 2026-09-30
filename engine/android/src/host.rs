//! O lado do Dart: o que as funções `jd_*` do motor que toca fazem, fora a FFI.
//!
//! O [`Host`] é dono do núcleo (em `Arc<Mutex>`, que o callback só tenta pegar com `try_lock` e
//! nunca espera), das pontas das filas e da E/S da plataforma. Com a saída rodando, os comandos vão
//! pela fila e a thread de áudio aplica; sem ela (parada, segundo plano, dispositivo trocando, ou
//! fora do Android), [`Host::pump`] aplica os comandos aqui mesmo, para a fila não encher e o
//! estado refletir o que o Dart mandou. Quem "está sem saída" é decidido pelo pulso do callback:
//! 100 ms sem callback contam como parada.

use std::collections::VecDeque;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use jopendaw_engine::Sample;
use rtrb::PushError;

use crate::call::Call;
use crate::core::{ApplyFn, AudioCore, Command, CoreLink, Garbage, core};
use crate::platform::Io;
use crate::{ERR_BUSY, ERR_NOT_STARTED, ERR_PANIC, ERR_UNSUPPORTED, alloc};

/// Sem callback por mais que isso, a saída conta como parada.
const STALL: Duration = Duration::from_millis(100);

/// Tentativas de reabrir a entrada padrão depois de uma queda (o sistema leva um instante para
/// trocar de dispositivo).
const REOPEN_TRIES: u32 = 8;

/// Quanto o Dart espera por vaga na fila antes de desistir (só acontece com a thread de áudio
/// travada: com ela viva a fila esvazia a cada callback).
const PUSH_WAIT: Duration = Duration::from_millis(250);

pub struct Host {
    pub rate: f64,
    core: Arc<Mutex<AudioCore>>,
    link: CoreLink,
    pub io: Io,
    capturing: bool,
    epoch: u32,
    /// Capturas encerradas cujas notas ainda não chegaram.
    notes_pending: u32,
    notes_ready: VecDeque<f32>,
    /// A entrada que o usuário abriu (id do dispositivo, 0 = padrão): reaberta no `start` depois de
    /// um `stop` e depois de uma queda do dispositivo padrão.
    input_device: Option<i32>,
    /// Tentativas que restam de reabrir a entrada padrão que caiu (uma por manutenção, ~250 ms).
    reopen_tries: u32,
    /// Entradas devolvidas pela thread de áudio (fechadas) desde o começo.
    inputs_closed: u64,
    heartbeat: u64,
    heartbeat_at: Instant,
}

impl Host {
    /// Abre a saída (na taxa nativa do aparelho) e cria o motor nessa taxa.
    pub fn open(apply: ApplyFn) -> Result<Self, i32> {
        let mut io = Io::new();
        let rate = io.open_output(None)?;
        let (core, link) = core(rate, apply);
        let core = Arc::new(Mutex::new(core));
        io.start_output(&core)?;
        Ok(Self {
            rate,
            core,
            link,
            io,
            capturing: false,
            epoch: 0,
            notes_pending: 0,
            notes_ready: VecDeque::new(),
            input_device: None,
            reopen_tries: 0,
            inputs_closed: 0,
            heartbeat: 0,
            heartbeat_at: Instant::now(),
        })
    }

    /// Reabre a saída depois de um [`Host::stop`] (na mesma taxa: o motor não muda de taxa) e a
    /// entrada que estava aberta. Já rodando, nada.
    pub fn resume(&mut self) -> Result<f64, i32> {
        if self.broken() {
            return Err(ERR_PANIC);
        }
        if !self.io.output_open() {
            // uma entrada que ficou no núcleo (a saída caiu com ela aberta) sai antes: muitos
            // aparelhos não abrem uma segunda
            self.remove_input();
            self.io.open_output(Some(self.rate))?;
            self.io.start_output(&self.core)?;
            if let Some(device) = self.input_device
                && self.open_input(device).is_err()
            {
                self.lose_input();
            }
        }
        Ok(self.rate)
    }

    /// Fecha a saída e a entrada; o motor e tudo o que ele tem ficam (o `resume` continua dali).
    pub fn stop(&mut self) {
        self.remove_input();
        self.io.close_output();
        self.pump();
    }

    /// A thread de áudio entrou em pânico: o motor ficou num estado desconhecido.
    pub fn broken(&self) -> bool {
        self.meters().broken()
    }

    fn meters(&self) -> &crate::state::Meters {
        &self.link.state.meters
    }

    /// Manda um comando; com a fila cheia, espera um pouco por vaga.
    fn push(&mut self, cmd: Command) -> Result<(), i32> {
        let mut cmd = cmd;
        let deadline = Instant::now() + PUSH_WAIT;
        loop {
            match self.link.commands.push(cmd) {
                Ok(()) => {
                    self.pump();
                    return Ok(());
                }
                Err(PushError::Full(c)) => cmd = c,
            }
            // aplica aqui se a saída estiver parada, e libera o lixo, que também segura a thread
            // de áudio (ela só tira um comando da fila se houver vaga para o lixo dele)
            self.pump();
            if Instant::now() >= deadline {
                return Err(ERR_BUSY);
            }
            std::thread::sleep(Duration::from_millis(1));
        }
    }

    pub fn calls(&mut self, calls: Vec<Call>) -> Result<(), i32> {
        if calls.is_empty() {
            return Ok(());
        }
        self.push(Command::Calls(calls.into_boxed_slice()))
    }

    pub fn load_sample(&mut self, id: u32, sample: Sample) -> Result<(), i32> {
        self.push(Command::Sample { id, sample })
    }

    pub fn drop_sample(&mut self, id: u32) -> Result<(), i32> {
        self.push(Command::DropSample(id))
    }

    /// Aplica os comandos aqui se a saída estiver parada e libera o que a thread de áudio soltou.
    pub fn pump(&mut self) {
        self.collect();
        let beat = self.io.heartbeat();
        let now = Instant::now();
        if beat != self.heartbeat {
            self.heartbeat = beat;
            self.heartbeat_at = now;
        }
        if !self.io.output_open() || now.duration_since(self.heartbeat_at) > STALL {
            // try_lock: se o callback voltou bem agora, ele mesmo aplica
            if let Ok(mut core) = self.core.try_lock() {
                core.idle();
            }
            self.collect();
        }
    }

    fn collect(&mut self) {
        while let Ok(g) = self.link.garbage.pop() {
            if matches!(g, Garbage::Input(_)) {
                self.inputs_closed += 1;
            }
            // a entrada fecha o stream do AAudio no drop, aqui, fora da thread de áudio
            drop(g);
        }
        alloc::collect();
    }

    /// `jd_state`: o estado no formato do worklet; [`ERR_PANIC`] se a thread de áudio caiu.
    pub fn state(&mut self, out: &mut [f64]) -> i32 {
        if self.broken() {
            return ERR_PANIC;
        }
        self.pump();
        self.link.state.write_state(out) as i32
    }

    /// `jd_loudness`: a última medida de loudness do master publicada pela thread de áudio.
    pub fn loudness(&mut self, kind: usize) -> f64 {
        self.pump();
        self.meters().loudness(kind)
    }

    /// `jd_engine_latency`: a última latência do motor (quadros) publicada pela thread de áudio.
    pub fn engine_latency(&mut self) -> f64 {
        self.pump();
        self.meters().latency()
    }

    pub fn spectrum(&mut self, out: &mut [f32]) -> usize {
        self.link.state.spectrum(out)
    }

    /// Liga/desliga a captura. Ligar de novo com ela ligada (ou desligar desligada) não faz nada.
    pub fn capture(&mut self, on: bool) -> Result<(), i32> {
        if on == self.capturing {
            return Ok(());
        }
        if on {
            self.epoch = self.epoch.wrapping_add(1);
            self.link.rec.begin(self.epoch);
        }
        self.push(Command::Capture { on, epoch: self.epoch })?;
        if !on {
            self.notes_pending += 1;
        }
        self.capturing = on;
        Ok(())
    }

    /// `jd_recorded`: quadros capturados desde a última leitura, de um trecho só.
    pub fn recorded(&mut self, l: &mut [f32], r: &mut [f32]) -> (usize, f64) {
        self.link.rec.read(l, r)
    }

    /// `jd_rec_notes`: as notas das capturas encerradas (grupos de 5 floats); −1 enquanto a thread
    /// de áudio ainda não fechou a captura pedida (o áudio dela todo já está no anel quando as
    /// notas chegam).
    pub fn rec_notes(&mut self, out: &mut [f32]) -> i32 {
        self.pump();
        while let Ok(n) = self.link.notes_done.pop() {
            for _ in 0..n {
                match self.link.notes.pop() {
                    Ok(v) => self.notes_ready.push_back(v),
                    Err(_) => break,
                }
            }
            self.notes_pending = self.notes_pending.saturating_sub(1);
        }
        if !self.notes_ready.is_empty() {
            let n = out.len().min(self.notes_ready.len());
            for (o, v) in out.iter_mut().zip(self.notes_ready.drain(..n)) {
                *o = v;
            }
            return n as i32;
        }
        if self.notes_pending > 0 { -1 } else { 0 }
    }

    fn open_input(&mut self, device: i32) -> Result<f64, i32> {
        let (src, latency) = self.io.open_input(device, self.rate)?;
        self.push(Command::Input(Some(src)))?;
        Ok(latency)
    }

    /// `jd_input_start`: abre (ou troca) a entrada; devolve a latência de entrada em segundos.
    pub fn input_start(&mut self, device: i32) -> Result<f64, i32> {
        if !Io::HAS_INPUT {
            return Err(ERR_UNSUPPORTED);
        }
        if !self.io.output_open() {
            return Err(ERR_NOT_STARTED);
        }
        // fecha a anterior antes: muitos aparelhos não abrem duas entradas ao mesmo tempo
        self.input_device = None;
        self.reopen_tries = 0;
        self.remove_input();
        self.meters().take_input_dropped();
        self.meters().take_input_lost();
        self.meters().take_input();
        let latency = self.open_input(device)?;
        self.input_device = Some(device);
        Ok(latency)
    }

    pub fn input_stop(&mut self) {
        self.input_device = None;
        self.reopen_tries = 0;
        self.remove_input();
        self.meters().take_input();
    }

    /// Tira a entrada do núcleo e espera ela voltar (fechada) pela fila de lixo.
    fn remove_input(&mut self) {
        if !self.io.has_input() {
            return;
        }
        let before = self.inputs_closed;
        if self.push(Command::Input(None)).is_err() {
            return;
        }
        let deadline = Instant::now() + PUSH_WAIT;
        while self.io.has_input() && self.inputs_closed == before && Instant::now() < deadline {
            std::thread::sleep(Duration::from_millis(2));
            self.pump();
        }
        self.io.input_closed();
    }

    /// `jd_input_level`: o pico da entrada desde a última leitura; −1 (uma vez) se ela caiu e não
    /// voltou.
    pub fn input_level(&mut self) -> f32 {
        if self.meters().take_input_lost() {
            return -1.0;
        }
        self.meters().take_input()
    }

    /// Manutenção fora do caminho do Dart (o supervisor chama): reabre a saída que caiu (fone
    /// plugado, dispositivo trocado) e a entrada padrão que caiu junto; uma entrada escolhida que
    /// sumiu vira aviso para o Dart.
    pub fn maintain(&mut self) {
        if self.io.needs_restart() && !self.broken() {
            self.io.restart(self.rate, &self.core);
        }
        if self.meters().take_input_dropped() {
            self.io.input_closed();
            match self.input_device {
                // a padrão segue o sistema (o fone plugado vira a entrada): reabre
                Some(0) => self.reopen_tries = REOPEN_TRIES,
                Some(_) => self.lose_input(),
                None => {}
            }
        }
        if self.reopen_tries > 0 && self.io.output_open() {
            self.reopen_tries -= 1;
            if self.open_input(0).is_ok() {
                self.reopen_tries = 0;
            } else if self.reopen_tries == 0 {
                self.lose_input();
            }
        }
        self.pump();
    }

    /// A entrada caiu e não volta: o Dart fica sabendo pelo `jd_input_level`.
    fn lose_input(&mut self) {
        self.input_device = None;
        self.reopen_tries = 0;
        self.meters().set_input_lost();
    }

    pub fn diagnostics(&self) -> String {
        let d = &self.link.diag;
        let r = std::sync::atomic::Ordering::Relaxed;
        format!(
            "chamadas desconhecidas: {} (última: {:?}); entrada curta: {}; quadros de captura perdidos: {}; liberações na thread de áudio: {}",
            d.unknown_calls.load(r),
            d.last_unknown(),
            d.input_short.load(r),
            d.rec_dropped.load(r),
            alloc::overflows(),
        )
    }

    /// Nos testes: um callback de saída, como o do AAudio faria.
    #[cfg(test)]
    pub fn render(&mut self, out: &mut [f32], channels: usize) {
        if let Ok(mut core) = self.core.try_lock() {
            core.render(out, channels);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::call::parse_calls;
    use crate::core::tests::test_apply;

    fn host() -> Host {
        Host::open(test_apply).unwrap()
    }

    #[test]
    fn without_output_the_host_applies_the_commands_itself() {
        let mut h = host();
        assert_eq!(h.rate, 48_000.0);
        h.calls(parse_calls(br#"[["tempo", 60, 4], ["tracks", 3], ["seek", 5]]"#).unwrap()).unwrap();
        let mut st = [0.0f64; 32];
        let n = h.state(&mut st);
        assert_eq!(n, 4 + 8);
        assert_eq!(st[0], 5.0);
        assert_eq!(st[1], 0.0);
        assert_eq!(st[3], 8.0);
        // milhares de listas não enchem a fila: sem saída, cada push aplica
        for i in 0..3000 {
            h.calls(parse_calls(format!(r#"[["seek", {i}]]"#).as_bytes()).unwrap()).unwrap();
        }
        h.state(&mut st);
        assert_eq!(st[0], 2999.0);
    }

    #[test]
    fn capture_notes_arrive_after_the_capture_ends() {
        let mut h = host();
        assert_eq!(h.rec_notes(&mut [0.0; 10]), 0);
        h.calls(parse_calls(br#"[["tracks", 1], ["track_kind", 0, 1], ["play"]]"#).unwrap()).unwrap();
        h.capture(true).unwrap();
        // simula a thread de áudio andando (a saída "roda" nos testes pelo render manual)
        let mut out = vec![0.0f32; 2 * 480];
        h.render(&mut out, 2);
        h.calls(parse_calls(br#"[["live_on", 0, 64, 1]]"#).unwrap()).unwrap();
        h.render(&mut out, 2);
        h.calls(parse_calls(br#"[["live_off", 0, 64]]"#).unwrap()).unwrap();
        h.render(&mut out, 2);
        // o fim da captura é aplicado pelo pump (sem saída de verdade), e as notas chegam
        h.capture(false).unwrap();
        let mut notes = [0.0f32; 3];
        // espaço para menos de uma nota: vem aos pedaços
        assert_eq!(h.rec_notes(&mut notes), 3);
        assert_eq!(notes[1], 64.0);
        let mut rest = [0.0f32; 10];
        assert_eq!(h.rec_notes(&mut rest), 2);
        assert_eq!(rest[1], 1.0);
        assert_eq!(h.rec_notes(&mut rest), 0);
        // desligar de novo não faz nada
        h.capture(false).unwrap();
        assert_eq!(h.rec_notes(&mut rest), 0);
    }

    #[test]
    fn input_needs_a_platform_and_reports_nothing_without_one() {
        let mut h = host();
        // fora do Android não há entrada de áudio
        assert!(h.input_start(0).is_err());
        assert_eq!(h.input_level(), 0.0);
        h.input_stop();
        h.stop();
        assert!(h.input_start(0).is_err());
        assert_eq!(h.resume(), Ok(48_000.0));
    }
}
