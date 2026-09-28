// AudioWorklet do jopendaw: hospeda o motor em Rust (engine.wasm) na thread de áudio.
//
// O host (host.js) baixa o engine.wasm e manda os bytes; a compilação é aqui (o Chrome não entrega
// um WebAssembly.Module compilado na thread principal para o escopo do worklet).
// Os comandos chegam pela porta como listas de chamadas ([nome, ...args]) e rodam entre um bloco
// e outro; o estado (posição, tocando, picos, indicador do efeito observado e, com o analisador
// ligado, o espectro) volta pela porta ~60 vezes por segundo.
const BLOCK = 128;
const MAX_PEAKS = 2 * 257;
// Faixas do espectro (FFT de 2048 pontos), mandado a cada 3 estados (~20 por segundo).
const SPECTRUM = 1024;
const SPECTRUM_EVERY = 3;

class EngineProcessor extends AudioWorkletProcessor {
  constructor() {
    super();
    this.wasm = null;
    this.blocks = 0;
    this.states = 0;
    // o analisador só custa (FFT e cópia) quando alguém observa uma faixa
    this.analyzing = false;
    this.port.onmessage = (e) => {
      try {
        this.onMessage(e.data);
      } catch (err) {
        this.port.postMessage({ t: 'error', message: String(err && err.stack || err) });
      }
    };
  }

  onMessage(msg) {
    if (msg.t === 'init') {
      this.wasm = new WebAssembly.Instance(new WebAssembly.Module(msg.bytes), {}).exports;
      this.wasm.init(sampleRate);
      this.left = this.wasm.alloc(BLOCK);
      this.right = this.wasm.alloc(BLOCK);
      this.peaks = this.wasm.alloc(MAX_PEAKS);
      this.spectrum = this.wasm.alloc(SPECTRUM);
      this.analyzing = false;
      this.port.postMessage({ t: 'ready', rate: sampleRate });
      return;
    }
    if (!this.wasm) return;
    const w = this.wasm;
    if (msg.t === 'sample') {
      const [l, r] = msg.channels;
      const frames = l.length;
      const pl = w.alloc(frames);
      new Float32Array(w.memory.buffer, pl, frames).set(l);
      let pr = 0;
      if (r) {
        pr = w.alloc(frames);
        new Float32Array(w.memory.buffer, pr, frames).set(r);
      }
      w.sample_load(msg.id, pl, pr, frames, msg.rate);
    } else if (msg.t === 'calls') {
      for (const [name, ...args] of msg.list) {
        w[name](...args);
        if (name === 'watch_analyzer') this.analyzing = args[0] !== -2;
      }
    }
  }

  process(_inputs, outputs) {
    const out = outputs[0];
    if (!this.wasm || !out || out.length === 0) return true;
    const w = this.wasm;
    const n = out[0].length;
    w.process(this.left, this.right, n);
    // a memória pode ter crescido desde o último bloco: as vistas são refeitas sempre
    const mem = w.memory.buffer;
    out[0].set(new Float32Array(mem, this.left, n));
    if (out[1]) out[1].set(new Float32Array(mem, this.right, n));

    if (++this.blocks % 6 === 0) {
      const count = w.peaks(this.peaks, MAX_PEAKS);
      const peaks = new Float32Array(w.memory.buffer, this.peaks, count).slice();
      const transfer = [peaks.buffer];
      let spectrum = null;
      if (this.analyzing && ++this.states % SPECTRUM_EVERY === 0) {
        const bins = w.analyzer(this.spectrum, SPECTRUM);
        if (bins > 0) {
          spectrum = new Float32Array(w.memory.buffer, this.spectrum, bins).slice();
          transfer.push(spectrum.buffer);
        }
      }
      this.port.postMessage(
        { t: 'state', beat: w.beat(), playing: w.playing() === 1, peaks, fxMeter: w.fx_meter(), analyzing: this.analyzing, spectrum },
        transfer,
      );
    }
    return true;
  }
}

registerProcessor('jopendaw-engine', EngineProcessor);
