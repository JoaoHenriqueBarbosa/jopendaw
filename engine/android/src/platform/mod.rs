//! A E/S de áudio da plataforma: o AAudio no Android e, fora dele (os testes no macOS), um motor
//! sem saída, em que o host aplica os comandos direto.

#[cfg(target_os = "android")]
mod aaudio;
#[cfg(target_os = "android")]
mod android;
#[cfg(target_os = "android")]
mod devices;
#[cfg(target_os = "android")]
pub use android::{Io, input_devices, log, spawn_supervisor};

#[cfg(not(target_os = "android"))]
mod none;
#[cfg(not(target_os = "android"))]
pub use none::{Io, input_devices, log, spawn_supervisor};
