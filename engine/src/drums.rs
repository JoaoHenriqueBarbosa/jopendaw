//! (esqueleto: implementação em andamento)

use crate::instrument::Instrument;

pub struct Drums {
    _rate: f64,
}

impl Drums {
    pub fn new(rate: f64) -> Self {
        Self { _rate: rate }
    }
}

impl Instrument for Drums {
    fn note_on(&mut self, _pitch: u8, _velocity: f32) {}
    fn note_off(&mut self, _pitch: u8) {}
    fn release_all(&mut self) {}
    fn silence(&mut self) {}
    fn set_param(&mut self, _id: u32, _value: f32) {}
    fn render(&mut self, _left: &mut [f32], _right: &mut [f32]) {}
    fn active(&self) -> bool {
        false
    }
}
