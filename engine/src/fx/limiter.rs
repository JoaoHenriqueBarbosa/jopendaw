//! (esqueleto: implementação em andamento; por enquanto passa o áudio intacto)

use crate::effect::Effect;

pub struct Limiter {
    _rate: f64,
}

impl Limiter {
    pub fn new(rate: f64) -> Self {
        Self { _rate: rate }
    }
}

impl Effect for Limiter {
    fn set_param(&mut self, _id: u32, _value: f32) {}
    fn process(&mut self, _left: &mut [f32], _right: &mut [f32]) {}
    fn reset(&mut self) {}
}
