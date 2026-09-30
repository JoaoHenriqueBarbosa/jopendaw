//! Fora do Android: sem saída nem entrada de áudio. O motor existe (testes, ferramentas) e o host
//! aplica os comandos na hora, como faz no Android com a saída parada.

use std::sync::{Arc, Mutex};

use crate::ERR_UNSUPPORTED;
use crate::core::{AudioCore, InputSource};

/// Taxa do motor sem aparelho: a do navegador comum.
const RATE: f64 = 48_000.0;

#[derive(Default)]
pub struct Io;

impl Io {
    /// Há entrada de áudio nesta plataforma.
    pub const HAS_INPUT: bool = false;

    pub fn new() -> Self {
        Self
    }

    pub fn open_output(&mut self, rate: Option<f64>) -> Result<f64, i32> {
        Ok(rate.unwrap_or(RATE))
    }

    pub fn start_output(&mut self, _core: &Arc<Mutex<AudioCore>>) -> Result<(), i32> {
        Ok(())
    }

    pub fn close_output(&mut self) {}

    /// Nunca há saída rodando: o host aplica tudo.
    pub fn output_open(&self) -> bool {
        false
    }

    pub fn needs_restart(&self) -> bool {
        false
    }

    pub fn restart(&mut self, _rate: f64, _core: &Arc<Mutex<AudioCore>>) {}

    pub fn heartbeat(&self) -> u64 {
        0
    }

    pub fn output_latency(&self) -> f64 {
        0.0
    }

    pub fn open_input(&mut self, _device: i32, _rate: f64) -> Result<(Box<dyn InputSource>, f64), i32> {
        Err(ERR_UNSUPPORTED)
    }

    pub fn has_input(&self) -> bool {
        false
    }

    pub fn input_closed(&mut self) {}
}

/// Entradas de áudio em JSON (`[[id, nome], ...]`): nenhuma fora do Android.
pub fn input_devices() -> String {
    "[]".to_owned()
}

pub fn log(msg: &str) {
    eprintln!("jopendaw_engine: {msg}");
}

pub fn spawn_supervisor() {}
