//! As chamadas do documento como dados: `[[nome, arg...], ...]`, o JSON que o worklet recebe.
//!
//! O parse é na thread do Dart; a thread de áudio só recebe [`Call`]s prontas, de tamanho fixo
//! (nome e argumentos dentro da própria estrutura), para aplicar sem alocar nem liberar nada.
//! Argumentos numéricos viram f64 (o protocolo de `engine::api::apply`); booleanos viram 0/1, como
//! o `engine_web.dart` já converte.

use std::fmt;

use serde::de::{self, Deserializer, SeqAccess, Visitor};

/// Maior nome de chamada (o maior de hoje, `instrument_sample`, tem 17).
pub const NAME_MAX: usize = 32;

/// Mais argumentos numa chamada (o `zone_add` tem 16; o `clip_add`, 8).
pub const ARGS_MAX: usize = 16;

/// Uma chamada pronta para a thread de áudio.
#[derive(Clone, Copy)]
pub struct Call {
    name: [u8; NAME_MAX],
    name_len: u8,
    args: [f64; ARGS_MAX],
    argc: u8,
}

impl Call {
    /// `None` com nome vazio ou longo demais, ou argumentos demais.
    pub fn new(name: &str, args: &[f64]) -> Option<Self> {
        if name.is_empty() || name.len() > NAME_MAX || args.len() > ARGS_MAX {
            return None;
        }
        let mut c = Self { name: [0; NAME_MAX], name_len: name.len() as u8, args: [0.0; ARGS_MAX], argc: args.len() as u8 };
        c.name[..name.len()].copy_from_slice(name.as_bytes());
        c.args[..args.len()].copy_from_slice(args);
        Some(c)
    }

    pub fn name(&self) -> &str {
        // SAFETY: só `new` escreve o nome, e a partir de um &str inteiro
        unsafe { std::str::from_utf8_unchecked(&self.name[..self.name_len as usize]) }
    }

    pub fn args(&self) -> &[f64] {
        &self.args[..self.argc as usize]
    }
}

impl fmt::Debug for Call {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "[{:?}", self.name())?;
        for a in self.args() {
            write!(f, ", {a}")?;
        }
        write!(f, "]")
    }
}

/// Lê a lista de chamadas. O erro diz o que estava errado (para o log), mas o Dart só recebe o
/// código.
pub fn parse_calls(json: &[u8]) -> Result<Vec<Call>, String> {
    let list: Vec<Wire> = serde_json::from_slice(json).map_err(|e| e.to_string())?;
    Ok(list.into_iter().map(|w| w.0).collect())
}

/// Uma chamada no fio: lida direto da sequência, sem montar um `Value` no meio (uma sincronização
/// grande tem milhares).
struct Wire(Call);

impl<'de> de::Deserialize<'de> for Wire {
    fn deserialize<D: Deserializer<'de>>(d: D) -> Result<Self, D::Error> {
        d.deserialize_seq(WireVisitor)
    }
}

struct WireVisitor;

impl<'de> Visitor<'de> for WireVisitor {
    type Value = Wire;

    fn expecting(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("uma chamada [nome, números...]")
    }

    fn visit_seq<A: SeqAccess<'de>>(self, mut seq: A) -> Result<Wire, A::Error> {
        let name: std::borrow::Cow<'de, str> = seq.next_element()?.ok_or_else(|| de::Error::custom("chamada sem nome"))?;
        let mut args = [0.0f64; ARGS_MAX];
        let mut n = 0;
        while let Some(Arg(v)) = seq.next_element()? {
            if n == ARGS_MAX {
                return Err(de::Error::custom(format!("argumentos demais em {name}")));
            }
            args[n] = v;
            n += 1;
        }
        Call::new(&name, &args[..n]).map(Wire).ok_or_else(|| de::Error::custom(format!("nome de chamada inválido: {name:?}")))
    }
}

/// Um argumento: número ou booleano.
struct Arg(f64);

impl<'de> de::Deserialize<'de> for Arg {
    fn deserialize<D: Deserializer<'de>>(d: D) -> Result<Self, D::Error> {
        d.deserialize_any(ArgVisitor)
    }
}

struct ArgVisitor;

impl Visitor<'_> for ArgVisitor {
    type Value = Arg;

    fn expecting(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("um número ou booleano")
    }

    fn visit_bool<E: de::Error>(self, v: bool) -> Result<Arg, E> {
        Ok(Arg(if v { 1.0 } else { 0.0 }))
    }

    fn visit_i64<E: de::Error>(self, v: i64) -> Result<Arg, E> {
        Ok(Arg(v as f64))
    }

    fn visit_u64<E: de::Error>(self, v: u64) -> Result<Arg, E> {
        Ok(Arg(v as f64))
    }

    fn visit_f64<E: de::Error>(self, v: f64) -> Result<Arg, E> {
        Ok(Arg(v))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_names_numbers_and_booleans() {
        let calls =
            parse_calls(br#"[["tempo", 128, 4], ["play"], ["track", 0, 0.5, -0.25, true, false], ["clip_add", 0, 7, 1.5, 0, 2, 1, 0.01, 0.01]]"#).unwrap();
        assert_eq!(calls.len(), 4);
        assert_eq!(calls[0].name(), "tempo");
        assert_eq!(calls[0].args(), &[128.0, 4.0]);
        assert_eq!(calls[1].name(), "play");
        assert!(calls[1].args().is_empty());
        assert_eq!(calls[2].args(), &[0.0, 0.5, -0.25, 1.0, 0.0]);
        assert_eq!(calls[3].args().len(), 8);
        assert_eq!(format!("{:?}", calls[0]), "[\"tempo\", 128, 4]");
    }

    #[test]
    fn zone_add_cabe_com_os_16_argumentos() {
        let args = (0..16).map(|i| i.to_string()).collect::<Vec<_>>().join(",");
        let calls = parse_calls(format!(r#"[["zone_add", {args}]]"#).as_bytes()).unwrap();
        assert_eq!(calls[0].args().len(), 16);
        assert!(parse_calls(format!(r#"[["zone_add", {args}, 16]]"#).as_bytes()).is_err(), "17 já é demais");
        assert!(Call::new("zones_clear", &[0.0]).is_some());
    }

    #[test]
    fn rejects_what_is_not_a_call_list() {
        for bad in [
            &br#"{"a": 1}"#[..],
            br#"[["tempo", "120"]]"#,
            br#"[[]]"#,
            br#"[[1, 2]]"#,
            br#"[["x", 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17]]"#,
            br#"[["um_nome_de_chamada_comprido_demais_para_caber", 1]]"#,
            br#"[["tempo", null]]"#,
            b"[[\"tempo\", 1]",
            b"",
        ] {
            assert!(parse_calls(bad).is_err(), "{}", String::from_utf8_lossy(bad));
        }
        assert!(parse_calls(b"[]").unwrap().is_empty());
    }

    #[test]
    fn escaped_names_are_unescaped() {
        let calls = parse_calls(br#"[["play"]]"#).unwrap();
        assert_eq!(calls[0].name(), "play");
    }
}
