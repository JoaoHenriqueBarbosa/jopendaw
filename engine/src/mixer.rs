//! Canal do mixer: volume, pan, mudo, solo e o medidor de pico; a cadeia de efeitos (inserts) e
//! os envios para os barramentos.

use crate::dsp::Delay;
use crate::effect::{self, Effect};

/// Constante de tempo com que o ganho aplicado persegue o pedido: curta o bastante para parecer
/// imediata, longa o bastante para que mexer no volume, no pan ou no mudo com som passando não
/// estale nem dê o "zíper" de degraus a cada bloco.
const SMOOTH_SECS: f64 = 0.005;

/// Duração das transições da cadeia (bypass, efeito entrando, saindo ou trocando de tipo): um
/// crossfade linear curto, que troca o som sem estalo e sem se ouvir como fade.
pub(crate) const FADE_SECS: f64 = 0.01;

/// Distância em que um ganho suavizado encosta no alvo. Não pode ser menor: em f32, perto de 1, o
/// passo `(alvo − g) · k` some no arredondamento quando a distância cai abaixo de ~ulp/k (7e-6 a
/// 48 kHz, 3e-5 a 192 kHz) e o ganho empacaria para sempre um fio abaixo do alvo. Um degrau de
/// 1e-4 (−80 dB) é inaudível.
const SNAP: f32 = 1e-4;

/// Slots de efeito por cadeia (contrato com o app).
pub const MAX_SLOTS: usize = 16;

/// Envios por faixa.
pub const MAX_SENDS: usize = 16;

/// Parâmetros de um efeito ou instrumento cujo valor estático o motor guarda, para voltar a ele
/// quando a automação solta (o maior, o EQ, usa 49).
pub const STATIC_PARAMS: usize = 64;

/// Um canal (faixa ou master).
#[derive(Clone, Debug)]
pub struct Track {
    /// Ganho linear (1.0 = 0 dB).
    pub gain: f32,
    /// -1 (esquerda) a 1 (direita).
    pub pan: f32,
    pub mute: bool,
    pub solo: bool,
    /// Valores da automação enquanto o transporte toca; `None` = vale o estático (`gain`, `pan`),
    /// que o app mandou e que a automação sobrepõe sem apagar.
    pub auto_gain: Option<f32>,
    pub auto_pan: Option<f32>,
    peak_l: f32,
    peak_r: f32,
    /// Ganhos do fader (esq, dir) aplicados agora; `None` até o primeiro bloco, que já começa no
    /// alvo.
    now: Option<[f32; 2]>,
    /// Porta do solo na saída (0 = calada pelo solo de outra faixa), suavizada como o fader.
    gate: Option<f32>,
    /// Fração do caminho até o alvo andada a cada quadro.
    smooth: f32,
}

impl Default for Track {
    fn default() -> Self {
        Self::new(48_000.0)
    }
}

/// Lei de pan de potência constante (-3 dB no centro).
pub fn pan_gains(pan: f32) -> (f32, f32) {
    let a = (pan.clamp(-1.0, 1.0) + 1.0) * std::f32::consts::FRAC_PI_4;
    (a.cos(), a.sin())
}

/// Coeficiente do polo de suavização de `SMOOTH_SECS` na taxa `rate`.
pub fn smooth_coef(rate: f64) -> f32 {
    (1.0 - (-1.0 / (SMOOTH_SECS * rate.max(1.0))).exp()) as f32
}

/// Ganho finito e não negativo (automação e app mandam números crus).
fn sane_gain(g: f32) -> f32 {
    if g.is_finite() { g.max(0.0) } else { 0.0 }
}

impl Track {
    /// Canal para um motor na taxa `rate` (a suavização é medida em segundos).
    pub fn new(rate: f64) -> Self {
        Self {
            gain: 1.0,
            pan: 0.0,
            mute: false,
            solo: false,
            auto_gain: None,
            auto_pan: None,
            peak_l: 0.0,
            peak_r: 0.0,
            now: None,
            gate: None,
            smooth: smooth_coef(rate),
        }
    }

    /// Ganho e pan valendo agora (a automação, se houver, senão o estático).
    pub fn effective(&self) -> (f32, f32) {
        let pan = self.auto_pan.unwrap_or(self.pan);
        (sane_gain(self.auto_gain.unwrap_or(self.gain)), if pan.is_finite() { pan } else { 0.0 })
    }

    /// Alvo do fader: volume e pan, zero no mudo. O solo fica fora (é a porta da saída), para que
    /// os envios de uma faixa calada pelo solo de outra possam seguir para um barramento solado.
    fn fader_target(&self) -> [f32; 2] {
        if self.mute {
            return [0.0; 2];
        }
        let (gain, pan) = self.effective();
        let (pl, pr) = pan_gains(pan);
        [gain * pl, gain * pr]
    }

    /// Volume, pan e mudo no bloco, no lugar: o que sai daqui é o sinal pós-fader (o dos envios
    /// pós-fader e o da saída).
    pub fn fader(&mut self, l: &mut [f32], r: &mut [f32]) {
        let target = self.fader_target();
        self.now = Some(ramp2(self.now, target, self.smooth, l, r));
    }

    /// Manda o sinal pós-fader para o destino (master ou barramento) pela porta do solo e mede o
    /// pico. `audible` falso (outra faixa em solo) leva a porta a zero suavemente. O bloco de
    /// origem fica com o que saiu (para o analisador).
    pub fn output(&mut self, l: &mut [f32], r: &mut [f32], dst_l: &mut [f32], dst_r: &mut [f32], audible: bool) {
        let target = if audible { 1.0 } else { 0.0 };
        let mut g = self.gate.unwrap_or(target);
        let (mut pl, mut pr) = (self.peak_l, self.peak_r);
        let k = self.smooth;
        let n = l.len().min(r.len()).min(dst_l.len()).min(dst_r.len());
        for i in 0..n {
            if g != target {
                g += (target - g) * k;
                if (g - target).abs() < SNAP {
                    g = target;
                }
            }
            let (a, b) = (l[i] * g, r[i] * g);
            l[i] = a;
            r[i] = b;
            dst_l[i] += a;
            dst_r[i] += b;
            pl = pl.max(a.abs());
            pr = pr.max(b.abs());
        }
        self.gate = Some(g);
        (self.peak_l, self.peak_r) = (pl, pr);
    }

    /// Fader e porta do solo no lugar, com o pico: o canal inteiro de uma vez.
    pub fn apply(&mut self, l: &mut [f32], r: &mut [f32], audible: bool) {
        self.fader(l, r);
        let target = if audible { 1.0 } else { 0.0 };
        let mut g = self.gate.unwrap_or(target);
        let (mut pl, mut pr) = (self.peak_l, self.peak_r);
        for (a, b) in l.iter_mut().zip(r.iter_mut()) {
            if g != target {
                g += (target - g) * self.smooth;
                if (g - target).abs() < SNAP {
                    g = target;
                }
            }
            *a *= g;
            *b *= g;
            pl = pl.max(a.abs());
            pr = pr.max(b.abs());
        }
        self.gate = Some(g);
        (self.peak_l, self.peak_r) = (pl, pr);
    }

    /// O bloco não teve som nesta faixa: não há o que suavizar, os ganhos vão direto ao alvo.
    pub fn settle(&mut self, audible: bool) {
        self.now = Some(self.fader_target());
        self.gate = Some(if audible { 1.0 } else { 0.0 });
    }

    /// O master: volume e balanço (o pan só atenua o lado oposto, o centro fica em 0 dB).
    pub fn apply_master(&mut self, l: &mut [f32], r: &mut [f32]) {
        let (gain, pan) = self.effective();
        let p = pan.clamp(-1.0, 1.0);
        let target = [gain * (1.0 - p.max(0.0)), gain * (1.0 + p.min(0.0))];
        self.now = Some(ramp2(self.now, target, self.smooth, l, r));
    }

    /// Ganhos (esq, dir) do fader neste momento.
    pub fn now_gains(&self) -> [f32; 2] {
        self.now.unwrap_or_else(|| self.fader_target())
    }

    /// Soma o bloco ao pico desde a última leitura (o master mede o que sai depois do limitador).
    pub fn meter(&mut self, l: &[f32], r: &[f32]) {
        self.peak_l = l.iter().fold(self.peak_l, |m, s| m.max(s.abs()));
        self.peak_r = r.iter().fold(self.peak_r, |m, s| m.max(s.abs()));
    }

    /// Pico desde a última leitura; zera para a próxima.
    pub fn take_peaks(&mut self) -> (f32, f32) {
        let p = (self.peak_l, self.peak_r);
        self.peak_l = 0.0;
        self.peak_r = 0.0;
        p
    }
}

/// Aplica um par de ganhos que persegue `target` por um polo e devolve onde parou. Perto o
/// bastante encosta no alvo e vira multiplicação simples.
fn ramp2(now: Option<[f32; 2]>, target: [f32; 2], k: f32, l: &mut [f32], r: &mut [f32]) -> [f32; 2] {
    let [mut gl, mut gr] = now.unwrap_or(target);
    let near = |gl: f32, gr: f32| (gl - target[0]).abs() < SNAP && (gr - target[1]).abs() < SNAP;
    let mut i = 0;
    let n = l.len().min(r.len());
    while i < n && !near(gl, gr) {
        gl += (target[0] - gl) * k;
        gr += (target[1] - gr) * k;
        l[i] *= gl;
        r[i] *= gr;
        i += 1;
    }
    if i < n {
        [gl, gr] = target;
        for (a, b) in l[i..n].iter_mut().zip(r[i..n].iter_mut()) {
            *a *= gl;
            *b *= gr;
        }
    }
    [gl, gr]
}

// ------------------------------------------------------------------------------------ envios

/// Um envio da faixa para um barramento.
#[derive(Clone, Debug)]
pub struct Send {
    /// Barramento pedido pelo app (índice da faixa), −1 = nenhum.
    pub bus: i32,
    /// Nível (ganho linear) estático.
    pub level: f32,
    /// Pré-fader: tira o sinal antes do volume e do mudo (mix de fone, reverb que não segue o
    /// fader).
    pub pre: bool,
    /// Nível da automação tocando (sobrepõe `level`).
    pub auto_level: Option<f32>,
    /// Destino validado pelo motor (−1 = inválido: índice fora, não é barramento ou processado
    /// antes da origem).
    pub(crate) dst: i32,
    now: Option<f32>,
    /// Atraso que alinha o que chega ao destino com as outras entradas dele (PDC).
    pub(crate) line: Delay,
}

impl Default for Send {
    fn default() -> Self {
        Self { bus: -1, level: 0.0, pre: false, auto_level: None, dst: -1, now: None, line: Delay::new() }
    }
}

impl Send {
    fn target(&self, on: bool) -> f32 {
        if on { sane_gain(self.auto_level.unwrap_or(self.level)) } else { 0.0 }
    }

    /// Soma a origem no destino com o nível do envio (suavizado com o coeficiente `k`).
    pub fn mix(&mut self, src_l: &[f32], src_r: &[f32], dst_l: &mut [f32], dst_r: &mut [f32], on: bool, k: f32) {
        let target = self.target(on);
        let mut g = self.now.unwrap_or(target);
        if g == target && g == 0.0 {
            return;
        }
        for i in 0..src_l.len().min(src_r.len()).min(dst_l.len()).min(dst_r.len()) {
            if g != target {
                g += (target - g) * k;
                if (g - target).abs() < SNAP {
                    g = target;
                }
            }
            dst_l[i] += src_l[i] * g;
            dst_r[i] += src_r[i] * g;
        }
        self.now = Some(g);
    }

    /// Muda o barramento de destino; o nível entra do zero no novo (sem degrau).
    pub fn retarget(&mut self, bus: i32) {
        if bus != self.bus {
            self.bus = bus;
            self.now = Some(0.0);
        }
    }

    /// A origem não soou no bloco: o nível vai direto ao alvo.
    pub fn settle(&mut self, on: bool) {
        self.now = Some(self.target(on));
    }
}

// ------------------------------------------------------------------------------------ inserts

/// Buffers de rascunho das transições da cadeia (o seco e a saída do efeito que sai), divididos
/// por todas as cadeias: o processamento é uma faixa por vez.
pub struct Scratch {
    dry_l: Vec<f32>,
    dry_r: Vec<f32>,
    old_l: Vec<f32>,
    old_r: Vec<f32>,
    /// A chave de sidechain atrasada, e a cópia atrasada de um envio (PDC).
    key_l: Vec<f32>,
    key_r: Vec<f32>,
    send_l: Vec<f32>,
    send_r: Vec<f32>,
}

impl Scratch {
    pub fn new(len: usize) -> Self {
        Self {
            dry_l: vec![0.0; len],
            dry_r: vec![0.0; len],
            old_l: vec![0.0; len],
            old_r: vec![0.0; len],
            key_l: vec![0.0; len],
            key_r: vec![0.0; len],
            send_l: vec![0.0; len],
            send_r: vec![0.0; len],
        }
    }

    /// Cópia de trabalho de `n` quadros de um envio com atraso (o envio lê daqui).
    pub fn send_copy(&mut self, src_l: &[f32], src_r: &[f32]) -> (&mut [f32], &mut [f32]) {
        let n = src_l.len().min(src_r.len()).min(self.send_l.len());
        self.send_l[..n].copy_from_slice(&src_l[..n]);
        self.send_r[..n].copy_from_slice(&src_r[..n]);
        (&mut self.send_l[..n], &mut self.send_r[..n])
    }

    /// Dois canais zerados de `n` quadros para quem precisa de um bloco temporário (o metrônomo).
    pub fn pair(&mut self, n: usize) -> (&mut [f32], &mut [f32]) {
        let (l, r) = (&mut self.dry_l[..n], &mut self.dry_r[..n]);
        l.fill(0.0);
        r.fill(0.0);
        (l, r)
    }
}

/// Um canal estéreo de trabalho.
pub struct Stereo {
    pub l: Vec<f32>,
    pub r: Vec<f32>,
}

impl Stereo {
    pub fn new(len: usize) -> Self {
        Self { l: vec![0.0; len], r: vec![0.0; len] }
    }
}

/// Um lugar da cadeia de efeitos.
pub struct Slot {
    /// Tipo pedido ([`effect::kind`]), 0 = vazio.
    pub kind: u32,
    fx: Option<Box<dyn Effect>>,
    /// O efeito que estava no lugar, em crossfade com `fx` depois de uma troca de tipo.
    old: Option<Box<dyn Effect>>,
    /// Progresso do crossfade `old` → `fx` (1 = só o novo).
    fade: f32,
    /// Quanto do efeito sai (0 = passa direto, 1 = só o efeito); anda até o alvo em `FADE_SECS`.
    wet: f32,
    pub bypass: bool,
    /// Esvaziado (tipo 0) ou cortado pelo `fx_count`: desce a mistura a zero e então sai.
    dying: bool,
    /// Faixa-chave do sidechain (compressor e gate), −1 = a própria entrada.
    pub sidechain: i32,
    /// Últimos valores que o app mandou (NaN = nunca), para a automação devolver ao soltar.
    statics: [f32; STATIC_PARAMS],
    /// Latência do efeito contada pela PDC (quadros); 0 sem efeito ou saindo. Vale também em
    /// bypass: a cadeia não muda de latência quando o efeito é ligado ou desligado.
    latency: usize,
    /// O sinal seco atrasado da latência do efeito: o bypass e o crossfade misturam sinais
    /// alinhados, e um slot em bypass segue atrasando igual.
    dry: Delay,
    /// A chave de sidechain atrasada para chegar alinhada com o sinal do slot.
    key_delay: Delay,
}

impl Slot {
    fn empty() -> Self {
        Self {
            kind: 0,
            fx: None,
            old: None,
            fade: 1.0,
            wet: 0.0,
            bypass: false,
            dying: false,
            sidechain: -1,
            statics: [f32::NAN; STATIC_PARAMS],
            latency: 0,
            dry: Delay::new(),
            key_delay: Delay::new(),
        }
    }

    fn target(&self) -> f32 {
        if self.bypass || self.dying || self.fx.is_none() { 0.0 } else { 1.0 }
    }

    /// Nada a processar: vazio, ou em bypass já assentado.
    fn idle(&self) -> bool {
        self.fx.is_none() || (self.old.is_none() && self.wet == 0.0 && self.target() == 0.0)
    }

    /// Este parâmetro é o da faixa-chave?
    fn is_sidechain(&self, id: u32) -> bool {
        (self.kind == effect::kind::COMPRESSOR && id == effect::compressor_param::SIDECHAIN)
            || (self.kind == effect::kind::GATE && id == effect::gate_param::SIDECHAIN)
    }
}

/// Quanto tempo de saída em silêncio, com a entrada calada, garante que o efeito não tem mais nada
/// guardado: o atraso mais longo que ele pode devolver depois de um silêncio (o eco de 4 s do
/// delay, o pré-atraso do reverb). A cauda que ainda soa não entra aqui: enquanto sai som, a
/// cadeia continua rodando.
fn tail_secs(kind: u32) -> f64 {
    match kind {
        effect::kind::DELAY => 4.5,
        effect::kind::REVERB => 0.5,
        effect::kind::CHORUS | effect::kind::PHASER => 0.1,
        _ => 0.05,
    }
}

/// A cadeia de inserts de uma faixa ou do master.
pub struct Chain {
    slots: Vec<Slot>,
    /// Slots pedidos pelo app; os de índice maior que ainda estão no vetor saem em fade.
    count: usize,
    rate: f64,
    bpm: f64,
    /// Passo por quadro das transições (1 / quadros de `FADE_SECS`).
    step: f32,
    /// Silêncio necessário na saída para a cadeia parar de rodar com a entrada calada (quadros).
    hold: usize,
    /// Alguma transição terminou e há efeito para soltar (entre um bloco e outro, não no meio).
    garbage: bool,
    /// Duração das transições em quadros (o crossfade dos atrasos da PDC).
    fade_len: usize,
}

impl Chain {
    pub fn new(rate: f64) -> Self {
        Self {
            slots: Vec::with_capacity(MAX_SLOTS * 2),
            count: 0,
            rate,
            bpm: 120.0,
            step: (1.0 / (FADE_SECS * rate).max(1.0)) as f32,
            hold: 0,
            garbage: false,
            fade_len: (FADE_SECS * rate) as usize,
        }
    }

    /// Slots pedidos.
    pub fn len(&self) -> usize {
        self.count
    }

    pub fn is_empty(&self) -> bool {
        self.count == 0
    }

    pub fn slot(&self, i: usize) -> Option<&Slot> {
        self.slots[..self.count].get(i)
    }

    /// Faixas-chave de sidechain que a cadeia usa.
    pub fn keys(&self) -> impl Iterator<Item = usize> + '_ {
        self.slots.iter().filter(|s| s.fx.is_some() && s.sidechain >= 0).map(|s| s.sidechain as usize)
    }

    /// Quantos slots a cadeia tem (até [`MAX_SLOTS`]). Os que sobram saem em fade; os novos
    /// nascem vazios. Devolve se mudou.
    pub fn set_count(&mut self, n: usize) -> bool {
        let n = n.min(MAX_SLOTS);
        if n == self.count {
            return false;
        }
        if n > self.count {
            // slots que ainda saíam em fade no lugar dos novos: cortados (raro: diminuir e aumentar
            // de novo em menos de 10 ms)
            self.slots.truncate(self.count);
            self.slots.resize_with(n, Slot::empty);
        } else {
            for s in &mut self.slots[n..self.count] {
                s.dying = true;
            }
            self.garbage = true;
        }
        self.count = n;
        self.update_hold();
        true
    }

    /// Tipo do efeito no slot. O mesmo tipo de novo não faz nada; outro tipo cria o efeito nos
    /// padrões (os parâmetros vêm depois) e troca por crossfade; 0 esvazia o slot em fade. Criar
    /// o efeito aloca (buffers de atraso no tamanho máximo): aceitável porque só acontece quando o
    /// usuário põe ou troca um efeito, nunca a cada bloco. Um slot além do fim estica a cadeia até
    /// ele (o app pode mandar o tipo antes da contagem). Devolve se mudou.
    pub fn set_kind(&mut self, slot: usize, kind: u32) -> bool {
        if slot >= MAX_SLOTS {
            return false;
        }
        if slot >= self.count {
            if kind == 0 {
                return false;
            }
            self.set_count(slot + 1);
        }
        if self.slots[slot].kind == kind {
            return false;
        }
        match effect::create(kind, self.rate) {
            Some(fx) => self.install(slot, kind, fx),
            None => self.clear(slot),
        }
        true
    }

    /// Põe um efeito já criado no slot (o `set_kind` usa; os testes põem efeitos próprios).
    pub fn install(&mut self, slot: usize, kind: u32, mut fx: Box<dyn Effect>) {
        if slot >= self.count {
            return;
        }
        fx.set_tempo(self.bpm);
        let s = &mut self.slots[slot];
        s.kind = kind;
        s.sidechain = -1;
        s.statics = [f32::NAN; STATIC_PARAMS];
        match s.fx.take() {
            // o que soava sai em crossfade com o novo; um crossfade anterior ainda no meio é cortado
            Some(prev) if s.wet > 0.0 => {
                s.old = Some(prev);
                s.fade = 0.0;
            }
            // nada soava (slot vazio ou em bypass): o novo entra do seco, pela mistura
            _ => {}
        }
        s.fx = Some(fx);
        s.dying = false;
        self.update_hold();
    }

    fn clear(&mut self, slot: usize) {
        let s = &mut self.slots[slot];
        s.kind = 0;
        s.sidechain = -1;
        s.statics = [f32::NAN; STATIC_PARAMS];
        if s.fx.is_some() {
            s.dying = true;
            self.garbage = true;
        }
    }

    /// Parâmetro de um efeito, na unidade da tabela. `from_app` guarda o valor como o estático
    /// (a automação não guarda); `forward` falso só guarda (a automação está no comando dele).
    /// Devolve se era o parâmetro da faixa-chave e ela mudou.
    pub fn set_param(&mut self, slot: usize, id: u32, value: f32, from_app: bool, forward: bool) -> bool {
        let Some(s) = self.slots[..self.count].get_mut(slot) else { return false };
        if !value.is_finite() {
            return false;
        }
        let mut routing = false;
        if s.is_sidechain(id) {
            if !from_app {
                // a faixa-chave não é automatizável: mudaria o roteamento a cada bloco
                return false;
            }
            let key = if value >= 0.0 { value.round() as i32 } else { -1 };
            routing = key != s.sidechain;
            s.sidechain = key;
        }
        if from_app && (id as usize) < STATIC_PARAMS {
            s.statics[id as usize] = value;
        }
        if forward && let Some(fx) = s.fx.as_mut() {
            fx.set_param(id, value);
        }
        routing
    }

    /// Volta o parâmetro ao último valor que o app mandou (a automação soltou).
    pub fn restore_param(&mut self, slot: usize, id: u32) {
        let Some(s) = self.slots[..self.count].get_mut(slot) else { return };
        let Some(&v) = s.statics.get(id as usize) else { return };
        if let (false, Some(fx)) = (v.is_nan(), s.fx.as_mut()) {
            fx.set_param(id, v);
        }
    }

    /// Liga ou desliga o bypass, por crossfade. Voltar de um bypass assentado esquece o estado
    /// velho do efeito (senão um delay devolveria os ecos de antes do bypass).
    pub fn set_bypass(&mut self, slot: usize, on: bool) {
        let Some(s) = self.slots[..self.count].get_mut(slot) else { return };
        if !on
            && s.bypass
            && s.wet == 0.0
            && s.old.is_none()
            && let Some(fx) = s.fx.as_mut()
        {
            fx.reset();
            // um efeito de lookahead recomeçaria mudo (o atraso dele vazio) e o crossfade de volta
            // abriria um buraco: ele reaprende os últimos quadros de entrada que o atraso do seco
            // guardou
            let mut left = s.latency;
            let (mut bl, mut br) = ([0.0f32; 128], [0.0f32; 128]);
            while left > 0 {
                let k = left.min(128);
                s.dry.history(left - 1, &mut bl[..k], &mut br[..k]);
                fx.process(&mut bl[..k], &mut br[..k]);
                left -= k;
            }
        }
        if !on && s.bypass {
            // a chave que o slot não viu durante o bypass é passado velho
            s.key_delay.clear();
        }
        s.bypass = on;
    }

    pub fn set_tempo(&mut self, bpm: f64) {
        self.bpm = bpm;
        for s in &mut self.slots {
            for fx in s.fx.iter_mut().chain(s.old.iter_mut()) {
                fx.set_tempo(bpm);
            }
        }
    }

    /// Esquece o estado de todos os efeitos (pânico).
    pub fn reset(&mut self) {
        for s in &mut self.slots {
            for fx in s.fx.iter_mut().chain(s.old.iter_mut()) {
                fx.reset();
            }
        }
    }

    /// Redução de ganho (ou o indicador que for) do efeito no slot; 0 sem efeito.
    pub fn meter(&self, slot: usize) -> f32 {
        self.slot(slot).and_then(|s| s.fx.as_ref()).map_or(0.0, |fx| fx.meter())
    }

    /// Há algo a processar? (Um slot em bypass com latência ainda atrasa o sinal.)
    pub fn live(&self) -> bool {
        self.slots.iter().any(|s| !s.idle() || s.dry.active())
    }

    /// Lê de novo a latência de cada efeito e a passa aos atrasos do seco (PDC). Roda no comando
    /// ou entre um bloco e outro, nunca no meio do processamento: os atrasos podem crescer aqui.
    /// `cap` limita a latência de cada efeito.
    pub fn refresh_latency(&mut self, cap: usize) {
        for s in &mut self.slots {
            s.latency = match &s.fx {
                Some(fx) if !s.dying => fx.latency().min(cap),
                _ => 0,
            };
            s.dry.set_target(s.latency, self.fade_len);
        }
        self.update_hold();
    }

    /// Latência da cadeia inteira em quadros: a soma dos efeitos, ligados ou em bypass.
    pub fn latency(&self) -> usize {
        self.slots.iter().map(|s| s.latency).sum()
    }

    /// Faixa-chave do slot quando ela vale para a PDC: efeito vivo, chave que não é a própria
    /// entrada, existe (`n` faixas) e é processada antes (`known`), no mesmo bloco.
    fn key_track(s: &Slot, own: usize, n: usize, known: &impl Fn(usize) -> bool) -> Option<usize> {
        let k = usize::try_from(s.sidechain).ok()?;
        (s.fx.is_some() && !s.dying && k != own && k < n && known(k)).then_some(k)
    }

    /// Quanto a entrada da cadeia precisa estar atrasada para que nenhuma chave de sidechain (com
    /// a latência `out[k]` da faixa `k`, a saída dela depois dos inserts) chegue depois do sinal no
    /// slot que a usa: o maior `out[k]` menos a latência dos slots antes dele.
    pub fn key_need(&self, own: usize, out: &[usize], known: impl Fn(usize) -> bool) -> usize {
        let (mut need, mut before) = (0, 0);
        for s in &self.slots {
            if let Some(k) = Self::key_track(s, own, out.len(), &known) {
                need = need.max(out[k].saturating_sub(before));
            }
            before += s.latency;
        }
        need
    }

    /// Atrasa cada chave até o sinal do slot: a entrada da cadeia chega com latência `arrive`.
    pub fn set_key_delays(&mut self, arrive: usize, own: usize, out: &[usize], known: impl Fn(usize) -> bool) {
        let mut before = 0;
        for s in &mut self.slots {
            let d = Self::key_track(s, own, out.len(), &known).map_or(0, |k| (arrive + before).saturating_sub(out[k]));
            s.key_delay.set_target(d, self.fade_len);
            before += s.latency;
        }
    }

    /// Termina na hora as mudanças de atraso e esvazia os anéis (começo de um render).
    pub fn snap_delays(&mut self) {
        for s in &mut self.slots {
            s.dry.snap();
            s.key_delay.snap();
        }
    }

    /// Silêncio de saída (quadros) que a cadeia precisa, com a entrada calada, para poder parar.
    pub fn hold(&self) -> usize {
        self.hold
    }

    fn update_hold(&mut self) {
        let secs = self.slots.iter().filter(|s| s.fx.is_some()).map(|s| tail_secs(s.kind)).fold(0.0, f64::max);
        // a latência entra no silêncio exigido: o que está nos atrasos precisa sair antes de parar
        self.hold = ((secs * self.rate) as usize).max(self.latency());
    }

    /// Solta o que as transições terminaram: o efeito antigo de um crossfade, o de um slot
    /// esvaziado, os slots cortados. Entre um bloco e outro (liberar memória não é para o meio
    /// do processamento).
    pub fn collect(&mut self) {
        if !self.garbage {
            return;
        }
        self.garbage = false;
        for s in &mut self.slots {
            if s.old.is_some() && s.fade >= 1.0 {
                s.old = None;
            }
            // o slot que sai só some quando o atraso do seco também terminou de descer a zero
            if s.dying && s.wet == 0.0 && s.old.is_none() && !s.dry.active() {
                s.fx = None;
            }
            // ainda no meio de uma transição: fica para a próxima
            self.garbage |= s.old.is_some() || (s.dying && s.fx.is_some());
        }
        while self.slots.len() > self.count && self.slots.last().is_some_and(|s| s.fx.is_none()) {
            self.slots.pop();
        }
        self.update_hold();
    }

    /// Slots no vetor, contando os que ainda saem em fade.
    #[cfg(test)]
    pub fn slots_len(&self) -> usize {
        self.slots.len()
    }

    /// Termina na hora as transições (testes que medem amostras exatas).
    #[cfg(test)]
    pub fn snap(&mut self) {
        for s in &mut self.slots {
            s.wet = s.target();
            s.fade = 1.0;
            s.old = None;
        }
    }

    /// Processa o bloco no lugar, efeito por efeito. `keys` são as saídas das faixas-chave (por
    /// índice de faixa); `own` é a faixa desta cadeia (a chave dela mesma é a própria entrada).
    pub fn process(&mut self, l: &mut [f32], r: &mut [f32], keys: &[Stereo], own: usize, scratch: &mut Scratch) {
        let n = l.len().min(r.len());
        let (l, r) = (&mut l[..n], &mut r[..n]);
        let step = self.step;
        for s in &mut self.slots {
            if s.idle() {
                // em bypass assentado o sinal só atravessa o atraso da latência do efeito
                if s.dry.active() {
                    s.dry.process(l, r);
                }
                continue;
            }
            let key = match s.sidechain {
                k if k >= 0 && k as usize != own => keys.get(k as usize).map(|b| (&b.l[..n], &b.r[..n])),
                _ => None,
            };
            let key = match key {
                Some((kl, kr)) if s.key_delay.active() => {
                    scratch.key_l[..n].copy_from_slice(kl);
                    scratch.key_r[..n].copy_from_slice(kr);
                    s.key_delay.process(&mut scratch.key_l[..n], &mut scratch.key_r[..n]);
                    Some((&scratch.key_l[..n], &scratch.key_r[..n]))
                }
                other => other,
            };
            let target = s.target();
            let Some(fx) = s.fx.as_mut() else { continue };
            if s.old.is_none() && s.wet == target {
                // o caso comum: efeito ligado, sem transição
                if s.dry.active() {
                    s.dry.record(l, r);
                }
                fx.process_keyed(l, r, key);
                continue;
            }
            let (dl, dr) = (&mut scratch.dry_l[..n], &mut scratch.dry_r[..n]);
            let (ol, or) = (&mut scratch.old_l[..n], &mut scratch.old_r[..n]);
            dl.copy_from_slice(l);
            dr.copy_from_slice(r);
            // o seco chega atrasado da latência do efeito, alinhado com a saída dele
            if s.dry.active() {
                s.dry.process(dl, dr);
            }
            let crossfade = match s.old.as_mut() {
                Some(old) => {
                    ol.copy_from_slice(l);
                    or.copy_from_slice(r);
                    old.process_keyed(ol, or, key);
                    true
                }
                None => false,
            };
            fx.process_keyed(l, r, key);
            let (mut w, mut f) = (s.wet, s.fade);
            for i in 0..n {
                let (mut el, mut er) = (l[i], r[i]);
                if crossfade {
                    el = ol[i] + (el - ol[i]) * f;
                    er = or[i] + (er - or[i]) * f;
                    f = (f + step).min(1.0);
                }
                l[i] = dl[i] + (el - dl[i]) * w;
                r[i] = dr[i] + (er - dr[i]) * w;
                w = if w < target { (w + step).min(target) } else { (w - step).max(target) };
            }
            s.wet = w;
            s.fade = f;
            if (crossfade && f >= 1.0) || (s.dying && w == 0.0) {
                self.garbage = true;
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn primeiro_bloco_ja_no_alvo() {
        let mut t = Track::new(48_000.0);
        t.gain = 0.5;
        let (mut l, mut r) = (vec![1.0; 64], vec![1.0; 64]);
        t.apply(&mut l, &mut r, true);
        let (gl, _) = pan_gains(0.0);
        assert!((l[0] - 0.5 * gl).abs() < 1e-6);
    }

    #[test]
    fn mudo_desce_sem_degrau() {
        let mut t = Track::new(48_000.0);
        let (mut l, mut r) = (vec![1.0; 128], vec![1.0; 128]);
        t.apply(&mut l, &mut r, true);
        let (mut l, mut r) = (vec![1.0; 4800], vec![1.0; 4800]);
        t.apply(&mut l, &mut r, false);
        let jump = l.windows(2).map(|w| (w[0] - w[1]).abs()).fold(0.0, f32::max);
        assert!(jump < 0.01, "{jump}");
        assert!(l[4799] < 1e-6);
        // assentado em zero, o próximo bloco sai zerado de verdade
        let (mut l, mut r) = (vec![1.0; 128], vec![1.0; 128]);
        t.apply(&mut l, &mut r, false);
        assert!(l.iter().chain(&r).all(|&s| s == 0.0));
    }

    #[test]
    fn automacao_sobrepoe_sem_apagar_o_estatico() {
        let mut t = Track::new(48_000.0);
        t.gain = 0.8;
        t.auto_gain = Some(0.25);
        assert_eq!(t.effective().0, 0.25);
        t.auto_gain = None;
        assert_eq!(t.effective().0, 0.8);
        t.auto_gain = Some(f32::NAN);
        assert_eq!(t.effective().0, 0.0);
    }

    #[test]
    fn envio_suaviza_o_nivel() {
        let mut s = Send { level: 1.0, ..Send::default() };
        let src = vec![1.0; 256];
        let (mut dl, mut dr) = (vec![0.0; 256], vec![0.0; 256]);
        s.mix(&src, &src, &mut dl, &mut dr, true, 0.01);
        assert!((dl[0] - 1.0).abs() < 1e-6, "primeiro bloco já no alvo");
        s.level = 0.0;
        let (mut dl, mut dr) = (vec![0.0; 256], vec![0.0; 256]);
        s.mix(&src, &src, &mut dl, &mut dr, true, 0.01);
        assert!(dl[0] > 0.9 && dl[255] < 0.2, "{} {}", dl[0], dl[255]);
    }
}
