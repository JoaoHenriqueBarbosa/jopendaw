// AudioWorklet do jopendaw: hospeda o motor em Rust (engine.wasm) na thread de áudio.
//
// O host (host.js) baixa o engine.wasm e manda os bytes; a compilação é aqui (o Chrome não entrega
// um WebAssembly.Module compilado na thread principal para o escopo do worklet).
// Os comandos chegam pela porta como listas de chamadas ([nome, ...args]) e rodam entre um bloco
// e outro; o estado (posição, tocando, picos, indicador do efeito observado e, com o analisador
// ligado, o espectro) volta pela porta ~60 vezes por segundo.
//
// Entrada de áudio (fase 4): o nó tem sempre uma entrada, ligada pelo host ao microfone quando a
// gravação ou o monitoramento pedem. Cada bloco que chega vai ao motor por `set_input` antes do
// `process` (mono vira os dois canais); o pico dela volta ~30 vezes por segundo. Com a captura
// ligada e o transporte tocando, a entrada é juntada em blocos grandes e mandada ao host, e o
// motor registra as notas tocadas ao vivo.
const BLOCK = 128;
const MAX_PEAKS = 2 * 257;
// Faixas do espectro (FFT de 2048 pontos), mandado a cada 3 estados (~20 por segundo).
const SPECTRUM = 1024;
const SPECTRUM_EVERY = 3;
// Captura: blocos de 4096 quadros (~85 ms a 48 kHz) são poucas mensagens por segundo e ainda
// deixam o que foi gravado aparecer quase na hora.
const REC_FRAMES = 4096;
// Pares de blocos reservados para a captura. Cada par vai transferido ao host, que copia e devolve
// (`recycle`); só se o host atrasar mais que o pool inteiro (~0,7 s) um par novo é criado aqui.
const REC_POOL = 8;
// Pico da entrada para o medidor das faixas armadas.
const LEVELS_PER_SEC = 30;
// Notas registradas numa gravação: grupos de 5 floats (faixa, altura, início, fim, velocidade).
// 16384 notas são quase meia hora de um pianista rápido (10 por segundo); reservado uma vez, na
// inicialização. Os eventos de controle (bend, modulação, pedal) vêm no mesmo formato, com a
// altura 256 + controle e o valor no lugar da velocidade, e têm cota própria de 32768.
const REC_NOTE_FLOATS = 5;
const REC_NOTES_MAX = REC_NOTE_FLOATS * (16384 + 32768);
// Chamadas de expressão que um engine.wasm de antes dela não exporta: ignoradas em vez de
// derrubar o lote inteiro de chamadas.
const EXPRESSION_CALLS = new Set(['live_bend', 'live_cc', 'cc_add', 'cc_clear']);
// Diferença de posição entre um bloco e o seguinte que conta como salto (seek) e não como
// arredondamento: um milionésimo de batida é bem menos que um quadro.
const BEAT_EPS = 1e-6;

class EngineProcessor extends AudioWorkletProcessor {
  constructor() {
    super();
    this.wasm = null;
    this.blocks = 0;
    this.states = 0;
    // o analisador só custa (FFT e cópia) quando alguém observa uma faixa
    this.analyzing = false;
    // entrada aberta no host (o microfone pode chegar alguns blocos depois de aberto)
    this.inputOpen = false;
    this.levelEvery = Math.max(1, Math.round(sampleRate / BLOCK / LEVELS_PER_SEC));
    this.levelBlocks = 0;
    this.levelPeak = 0;
    this.levelSent = false;
    // batidas por quadro no andamento que o app mandou (o motor começa em 120)
    this.beatsPerFrame = 120 / 60 / sampleRate;
    this.resetCapture();
    this.pool = [];
    for (let i = 0; i < REC_POOL; i++) this.pool.push([new Float32Array(REC_FRAMES), new Float32Array(REC_FRAMES)]);
    this.port.onmessage = (e) => {
      try {
        this.onMessage(e.data);
      } catch (err) {
        this.port.postMessage({ t: 'error', message: String((err && err.stack) || err) });
      }
    };
  }

  resetCapture() {
    this.capturing = false;
    // a captura desta gravação já pegou áudio: segue gravando (silêncio, se a entrada cair) para
    // o que vier depois continuar no lugar certo da linha do tempo
    this.recStarted = false;
    this.recL = null;
    this.recR = null;
    this.recPos = 0;
    this.recBeat = 0;
    // posição esperada no começo do próximo bloco capturado; outra = houve salto
    this.recNext = NaN;
  }

  onMessage(msg) {
    if (msg.t === 'init') {
      this.wasm = new WebAssembly.Instance(new WebAssembly.Module(msg.bytes), {}).exports;
      const w = this.wasm;
      w.init(sampleRate);
      this.left = w.alloc(BLOCK);
      this.right = w.alloc(BLOCK);
      this.peaks = w.alloc(MAX_PEAKS);
      this.spectrum = w.alloc(SPECTRUM);
      this.inLeft = w.alloc(BLOCK);
      this.inRight = w.alloc(BLOCK);
      // um motor de antes da fase 4 não tem entrada nem registro de notas: o resto funciona igual
      this.canInput = typeof w.set_input === 'function';
      this.canRecNotes = typeof w.rec_notes_start === 'function' && typeof w.rec_notes === 'function';
      this.recNotes = this.canRecNotes ? w.alloc(REC_NOTES_MAX) : 0;
      this.mem = null;
      this.analyzing = false;
      this.resetCapture();
      this.port.postMessage({ t: 'ready', rate: sampleRate });
      return;
    }
    if (msg.t === 'recycle') {
      // par de captura devolvido pelo host
      if (msg.left && msg.left.length === REC_FRAMES && this.pool.length < 2 * REC_POOL) this.pool.push([msg.left, msg.right]);
      return;
    }
    if (msg.t === 'input') {
      this.inputOpen = !!msg.on;
      if (!this.inputOpen) this.levelPeak = 0;
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
        if (EXPRESSION_CALLS.has(name) && typeof w[name] !== 'function') continue;
        w[name](...args);
        if (name === 'watch_analyzer') this.analyzing = args[0] !== -2;
        // o mesmo limite que o motor aplica ao andamento
        else if (name === 'tempo' && Number.isFinite(args[0])) this.beatsPerFrame = Math.min(999, Math.max(20, args[0])) / 60 / sampleRate;
      }
    } else if (msg.t === 'capture') {
      this.capture(!!msg.on);
    }
  }

  // Liga ou desliga a captura. Desligar manda o resto do bloco em andamento e depois as notas
  // registradas; o host recebe os dois nessa ordem (a porta preserva a ordem das mensagens).
  capture(on) {
    const w = this.wasm;
    if (on) {
      if (this.capturing) return;
      this.resetCapture();
      this.capturing = true;
      if (this.canRecNotes) w.rec_notes_start();
      return;
    }
    if (!this.capturing) return;
    this.flushRec();
    let notes = null;
    if (this.canRecNotes) {
      // lidas antes de parar: a que ainda está segurada termina na posição atual
      const count = w.rec_notes(this.recNotes, REC_NOTES_MAX);
      notes = new Float32Array(w.memory.buffer, this.recNotes, Math.max(0, Math.min(count, REC_NOTES_MAX))).slice();
      w.rec_notes_stop();
    }
    this.resetCapture();
    if (notes) this.port.postMessage({ t: 'captured', notes }, [notes.buffer]);
    else this.port.postMessage({ t: 'captured', notes: new Float32Array(0) });
  }

  // As vistas da memória do wasm só são refeitas quando ela cresce (o buffer antigo fica vazio):
  // nada de objeto novo por bloco no caminho de áudio.
  views() {
    const buf = this.wasm.memory.buffer;
    if (buf === this.mem) return;
    this.mem = buf;
    this.vLeft = new Float32Array(buf, this.left, BLOCK);
    this.vRight = new Float32Array(buf, this.right, BLOCK);
    this.vInLeft = new Float32Array(buf, this.inLeft, BLOCK);
    this.vInRight = new Float32Array(buf, this.inRight, BLOCK);
  }

  // Junta `n` quadros da entrada (null = silêncio) no bloco de captura em andamento; cheio, vai.
  record(il, ir, n, beat) {
    let from = 0;
    while (from < n) {
      if (!this.recL) {
        const pair = this.pool.pop() || [new Float32Array(REC_FRAMES), new Float32Array(REC_FRAMES)];
        this.recL = pair[0];
        this.recR = pair[1];
        this.recPos = 0;
        // um bloco novo no meio do bloco do motor começa `from` quadros depois (sem contar uma
        // volta do loop bem ali: com o quantum de 128, que divide 4096, isso nem acontece)
        this.recBeat = beat + from * this.beatsPerFrame;
      }
      const take = Math.min(n - from, REC_FRAMES - this.recPos);
      if (il) {
        if (from === 0 && take === n) {
          this.recL.set(il, this.recPos);
          this.recR.set(ir, this.recPos);
        } else {
          for (let i = 0; i < take; i++) {
            this.recL[this.recPos + i] = il[from + i];
            this.recR[this.recPos + i] = ir[from + i];
          }
        }
      } else {
        this.recL.fill(0, this.recPos, this.recPos + take);
        this.recR.fill(0, this.recPos, this.recPos + take);
      }
      this.recPos += take;
      from += take;
      if (this.recPos >= REC_FRAMES) this.flushRec();
    }
  }

  // Manda o bloco de captura em andamento (inteiro ou parcial) com a batida do primeiro quadro.
  // Vai o par inteiro, transferido, e `frames` diz quanto dele vale.
  flushRec() {
    if (!this.recL) return;
    const left = this.recL;
    const right = this.recR;
    const frames = this.recPos;
    this.recL = null;
    this.recR = null;
    this.recPos = 0;
    if (frames === 0) {
      this.pool.push([left, right]);
      return;
    }
    this.port.postMessage({ t: 'rec', left, right, frames, beat: this.recBeat }, [left.buffer, right.buffer]);
  }

  process(inputs, outputs) {
    const out = outputs[0];
    if (!this.wasm || !out || out.length === 0) return true;
    const w = this.wasm;
    // o quantum do Web Audio é 128; as memórias do motor têm esse tamanho
    const n = Math.min(out[0].length, BLOCK);
    this.views();

    // entrada: sem nada ligado, o navegador entrega zero canais e o motor não recebe o bloco; mono
    // vai aos dois lados, e de uma interface com mais canais valem os dois primeiros
    const input = inputs[0];
    let il = null;
    let ir = null;
    if (input && input.length > 0 && input[0].length >= n) {
      il = input[0];
      ir = input.length > 1 ? input[1] : il;
      if (this.canInput) {
        if (n === BLOCK) {
          this.vInLeft.set(il);
          this.vInRight.set(ir);
        } else {
          for (let i = 0; i < n; i++) {
            this.vInLeft[i] = il[i];
            this.vInRight[i] = ir[i];
          }
        }
        w.set_input(this.inLeft, this.inRight, n);
      }
      let peak = this.levelPeak;
      for (let i = 0; i < n; i++) {
        const a = Math.abs(il[i]);
        const b = Math.abs(ir[i]);
        if (a > peak) peak = a;
        if (b > peak) peak = b;
      }
      this.levelPeak = peak;
    }

    // posição e estado deste bloco (os comandos só mudam entre um bloco e outro)
    const playing = w.playing() === 1;
    const beat = playing ? w.beat() : 0;

    w.process(this.left, this.right, n);
    // `process` pode ter feito a memória crescer
    this.views();
    if (n === BLOCK) {
      out[0].set(this.vLeft);
      if (out[1]) out[1].set(this.vRight);
    } else {
      for (let i = 0; i < n; i++) {
        out[0][i] = this.vLeft[i];
        if (out[1]) out[1][i] = this.vRight[i];
      }
    }

    if (this.capturing) {
      if (playing && (this.inputOpen || this.recStarted)) {
        // saltou (seek no meio da gravação): o bloco em andamento fecha e o próximo começa na
        // posição nova; a volta do loop acontece dentro do `process` e não conta como salto
        if (this.recL && Math.abs(beat - this.recNext) > BEAT_EPS) this.flushRec();
        this.record(il, ir, n, beat);
        this.recStarted = true;
        this.recNext = w.beat();
      } else if (this.recL) {
        // parou: o que foi gravado até aqui vai; tocar de novo começa outro bloco
        this.flushRec();
      }
    }

    if (++this.levelBlocks >= this.levelEvery) {
      this.levelBlocks = 0;
      if (this.inputOpen || il) {
        this.port.postMessage({ t: 'level', peak: this.levelPeak });
        this.levelSent = true;
      } else if (this.levelSent) {
        // a entrada fechou: o medidor desce a zero uma vez e as mensagens param
        this.port.postMessage({ t: 'level', peak: 0 });
        this.levelSent = false;
      }
      this.levelPeak = 0;
    }

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
    // loudness do master (~30 por segundo, e só quando muda): momentâneo, curto prazo, integrado,
    // true peak e faixa, como as chamadas `loudness(0..4)`; um motor mais antigo não tem a função
    if (this.blocks % 12 === 0 && typeof w.loudness === 'function') {
      const v = [w.loudness(0), w.loudness(1), w.loudness(2), w.loudness(3), w.loudness(4)];
      const last = this.lastLoudness;
      if (!last || v.some((x, i) => x !== last[i])) {
        this.lastLoudness = v;
        this.port.postMessage({ t: 'loudness', v });
      }
    }
    return true;
  }
}

registerProcessor('jopendaw-engine', EngineProcessor);
