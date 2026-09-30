// Render fora de tempo real do jopendaw (exportar e congelar faixa).
//
// Um Worker com uma instância própria do mesmo engine.wasm do AudioWorklet: recebe as chamadas do
// documento (as mesmas que o app manda ao motor que toca), os áudios, o trecho e as saídas
// pedidas, e processa o mais rápido que a CPU deixa, sem esperar o relógio e sem tocar na thread
// da interface. O motor que toca segue intacto: tocar e exportar ao mesmo tempo não se atrapalham.
//
// Protocolo (host.js):
//   entra  { t: 'render', wasm: WebAssembly.Module | ArrayBuffer, rate, calls, samples: [{ id,
//            channels, rate }], fromBeat, toBeat, tail, outputs }
//   sai    { t: 'progress', p }   0..1, algumas vezes por segundo
//          { t: 'done', outputs: [[esq, dir], ...], frames }   canais transferidos
//          { t: 'error', code, message }   code: empty | memory | unsupported | failed
//
// Warp de áudio (mesmo Worker, mesmo wasm, sem motor de render):
//   entra  { t: 'stretch', wasm, channels: [esq, dir?], rate, ratio, semitones }
//   sai    { t: 'stretched', channels: [esq, dir?], frames }   canais transferidos
//   entra  { t: 'detect', wasm, channels, rate }
//   sai    { t: 'tempo', bpm, confidence }
//          { t: 'error', code, message }   como acima
//
// O resto do arquivo (sem `self`) também roda no node, para os testes da lógica de render.
'use strict';

// Quadros por chamada de `process`. O motor fatia internamente numa grade fixa de 128 quadros
// contada do começo do render (e mais fino com automação), então o bloco maior só economiza
// chamadas e dá o mesmo resultado; 1024 (múltiplo de 128) fica bem abaixo do MAX_BLOCK dele
// (4096), que também limita o que `captured` devolve de uma vez.
const RENDER_BLOCK = 1024;
// Capturas por motor (`record::MAX_CAPTURES`): com mais saídas o render roda em passadas.
const MAX_CAPTURES = 64;

// Fade curto de um clipe cortado no fim do trecho: sem ele a cauda começaria com um estalo (o
// mesmo tempo do fade do motor ao parar).
const CUT_FADE_SECS = 0.01;

// Folga para uma nota ou clipe que começa "exatamente" no fim do trecho (erro de ponto flutuante).
const EDGE_EPS = 1e-9;

// Teto da memória das saídas (todas as pedidas, os dois canais): 4 GiB são ~186 minutos de saída
// estéreo a 48 kHz (10 min de música em 18 saídas, por exemplo). O Dart recebe tudo de uma vez,
// então passar disso travaria a aba de qualquer jeito.
const MAX_RENDER_BYTES = 4 * 1024 * 1024 * 1024;

// Chamadas que não entram no render: o transporte e a observação são dele, as notas ao vivo e a
// entrada de áudio não existem aqui, e memória e amostras chegam por outro caminho.
const SKIP = new Set([
  'init',
  'alloc',
  'dealloc',
  'process',
  'sample_load',
  'sample_drop',
  'play',
  'stop',
  'seek',
  'panic',
  'live_on',
  'live_off',
  'live_bend',
  'live_cc',
  'watch_fx',
  'watch_analyzer',
  'set_input',
  'input_monitor',
  'rec_notes_start',
  'rec_notes_stop',
  'rec_notes',
  'capture_clear',
  'capture_add',
  'captured',
  'peaks',
  'analyzer',
  'beat',
  'playing',
  'fx_meter',
  'loudness',
  'loudness_reset',
]);

class RenderError extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
  }
}

// O andamento que vale no fim das chamadas (o motor aplica em ordem: a última ganha), com o mesmo
// limite que ele impõe.
function tempoOf(calls) {
  let bpm = 120;
  for (const c of calls) {
    if (c[0] === 'tempo' && Number.isFinite(c[1])) bpm = c[1];
  }
  return Math.min(999, Math.max(20, bpm));
}

// O mapa de andamento que vale no fim das chamadas: `tempo` (o inicial), `tempo_clear` e
// `tempo_point(batida, bpm, rampa)`, aplicados em ordem como o motor os aplica. A mesma conta do
// motor (engine/src/tempo.rs) e de lib/daw/tempo_map.dart: pontos {beat, bpm, ramp} ordenados, o
// primeiro na batida 0; salto (bpm constante até o ponto seguinte) ou rampa linear em bpm.
// Devolve { single, bpm0, secondsAt(beat), beatAt(seconds) }.
function tempoMapOf(calls) {
  const clamp = (v) => Math.min(999, Math.max(20, v));
  let bpm0 = 120;
  let raw = [];
  for (const c of calls) {
    if (c[0] === 'tempo' && Number.isFinite(c[1])) bpm0 = clamp(c[1]);
    else if (c[0] === 'tempo_clear') raw = [];
    else if (c[0] === 'tempo_point' && Number.isFinite(c[1]) && Number.isFinite(c[2])) {
      if (c[1] <= 0) bpm0 = clamp(c[2]);
      raw.push({ beat: Math.max(0, c[1]), bpm: clamp(c[2]), ramp: !!c[3] });
    }
  }
  // ordena; na mesma batida o último vale; a batida 0 sempre existe e é o andamento inicial
  const byBeat = new Map();
  for (const p of raw) byBeat.set(p.beat, p);
  const pts = [...byBeat.values()].sort((a, b) => a.beat - b.beat);
  if (pts.length === 0 || pts[0].beat !== 0) pts.unshift({ beat: 0, bpm: bpm0, ramp: false });
  pts[0] = { beat: 0, bpm: bpm0, ramp: pts[0].ramp };
  if (pts.length === 1) {
    return { single: true, bpm0, secondsAt: (b) => (b * 60) / bpm0, beatAt: (s) => (s * bpm0) / 60 };
  }
  const flat = (a, b) => Math.abs(b - a) <= 1e-9 * a;
  const segSecs = (i, x) => {
    const p = pts[i];
    const q = pts[i + 1];
    if (q && p.ramp && !flat(p.bpm, q.bpm)) {
      const len = q.beat - p.beat;
      return ((60 * len) / (q.bpm - p.bpm)) * Math.log((p.bpm + ((q.bpm - p.bpm) * x) / len) / p.bpm);
    }
    return (x * 60) / p.bpm;
  };
  const secs = [0];
  for (let i = 1; i < pts.length; i++) secs.push(secs[i - 1] + segSecs(i - 1, pts[i].beat - pts[i - 1].beat));
  const last = (arr, ok) => {
    let lo = 0;
    let hi = arr.length - 1;
    while (lo < hi) {
      const mid = (lo + hi + 1) >> 1;
      if (ok(arr[mid])) lo = mid;
      else hi = mid - 1;
    }
    return lo;
  };
  return {
    single: false,
    bpm0,
    secondsAt(beat) {
      if (beat <= 0) return (beat * 60) / pts[0].bpm;
      const i = last(pts, (p) => p.beat <= beat);
      return secs[i] + segSecs(i, beat - pts[i].beat);
    },
    beatAt(s) {
      if (s <= 0) return (s * pts[0].bpm) / 60;
      const i = last(secs, (t) => t <= s);
      const p = pts[i];
      const q = pts[i + 1];
      const x = s - secs[i];
      if (q && p.ramp && !flat(p.bpm, q.bpm)) {
        const len = q.beat - p.beat;
        const k = (q.bpm - p.bpm) / (60 * len);
        return p.beat + Math.min(len, Math.max(0, (len * p.bpm * Math.expm1(k * x)) / (q.bpm - p.bpm)));
      }
      return p.beat + (x * p.bpm) / 60;
    },
  };
}

// Quadros do trecho e da cauda. O trecho é medido no andamento do documento (ou pelo mapa de
// andamento, `map`, quando ele tem mudanças); a cauda, em segundos.
function frameCounts(fromBeat, toBeat, tail, bpm, rate, map) {
  const perBeat = (60 / bpm) * rate;
  const seconds = map && !map.single ? map.secondsAt(toBeat) - map.secondsAt(fromBeat) : null;
  const range = Math.max(0, Math.round(seconds === null ? (toBeat - fromBeat) * perBeat : seconds * rate));
  const tailFrames = Math.max(0, Math.round((Number.isFinite(tail) ? tail : 0) * rate));
  return { range, tail: tailFrames, total: range + tailFrames };
}

// As chamadas do documento como o render as aplica: sem as de SKIP e com o que passa do fim do
// trecho aparado. O transporte segue tocando na cauda (a automação continua valendo, sem pular
// para os valores estáticos como faria um `stop`), mas nada começa depois do fim: clipes e notas
// que começam ali saem, e os que atravessam terminam no fim (clipe com um fade curto, nota com a
// soltura normal do instrumento). A cauda fica só com o que já soava: reverb, delay, soltura.
function prepareCalls(calls, toBeat, bpm, map) {
  const secsPerBeat = 60 / bpm;
  const mapped = map && !map.single ? map : null;
  const out = [];
  // `clip_fade_shape` vale para o último `clip_add`: sai junto com o clipe que saiu do trecho
  let lastClipKept = false;
  for (const c of calls) {
    const name = c[0];
    if (typeof name !== 'string' || SKIP.has(name)) continue;
    if (name === 'clip_fade_shape') {
      if (lastClipKept) out.push(c);
      continue;
    }
    if (name === 'clip_add') {
      lastClipKept = false;
      // clip_add(faixa, amostra, início em batidas, offset s, duração s, ganho, fade in s, fade out s)
      const [, track, sample, start, offset, length, gain, fadeIn, fadeOut] = c;
      if (start >= toBeat - EDGE_EPS) continue;
      lastClipKept = true;
      // o clipe toca em tempo real constante: com mapa de andamento, o fim vem dos segundos
      const end = mapped ? mapped.beatAt(mapped.secondsAt(start) + length) : start + length / secsPerBeat;
      if (end <= toBeat) {
        out.push(c);
        continue;
      }
      const cut = mapped ? mapped.secondsAt(toBeat) - mapped.secondsAt(start) : (toBeat - start) * secsPerBeat;
      // o fade de saída começa onde começava (se o corte cai dentro dele, só fica mais íngreme)
      const removed = length - cut;
      let fade = fadeOut > removed ? fadeOut - removed : 0;
      fade = Math.min(cut, Math.max(fade, CUT_FADE_SECS));
      out.push(['clip_add', track, sample, start, offset, cut, gain, fadeIn, fade]);
    } else if (name === 'note_add') {
      // note_add(faixa, início em batidas, duração em batidas, altura, velocidade)
      const [, track, start, length, pitch, velocity] = c;
      if (start >= toBeat - EDGE_EPS) continue;
      out.push(start + length > toBeat ? ['note_add', track, start, toBeat - start, pitch, velocity] : c);
    } else if (name === 'cc_add') {
      // cc_add(faixa, controle, batida, valor): depois do fim só fica o pedal que sobe, no próprio
      // fim (senão as notas cortadas ali seguiriam presas por um pedal que o trecho não solta)
      const [, track, cc, beat, value] = c;
      if (beat < toBeat - EDGE_EPS) out.push(c);
      else if (cc === 64 && value < 0.5) out.push(['cc_add', track, cc, toBeat, value]);
    } else {
      out.push(c);
    }
  }
  return out;
}

function checkJob(job) {
  const { fromBeat, toBeat, tail, rate, outputs } = job;
  if (!Number.isFinite(rate) || rate < 8000 || rate > 384000) throw new RenderError('failed', `Taxa de amostragem inválida para o render: ${rate}.`);
  if (!Number.isFinite(fromBeat) || !Number.isFinite(toBeat) || fromBeat < 0) throw new RenderError('failed', 'Trecho inválido para o render.');
  if (!Array.isArray(outputs) || outputs.length === 0) throw new RenderError('failed', 'Nenhuma saída pedida para o render.');
  if (!Number.isFinite(tail) || tail < 0) throw new RenderError('failed', 'Cauda inválida para o render.');
}

// Renderiza com as funções do engine.wasm já instanciado (`w`). Devolve os canais (esq, dir) de
// cada saída pedida (−1 = master, pós-limitador; i = faixa i, pós-fader) e o total de quadros.
function renderWith(w, job, onProgress) {
  checkJob(job);
  const { fromBeat, toBeat, tail, rate, outputs } = job;
  const calls = job.calls || [];
  const bpm = tempoOf(calls);
  const map = tempoMapOf(calls);
  const frames = frameCounts(fromBeat, toBeat, tail, bpm, rate, map);
  if (frames.range === 0) throw new RenderError('empty', 'Nada para renderizar: o trecho está vazio.');
  const wantsTracks = outputs.some((o) => o !== -1);
  if (wantsTracks && (typeof w.capture_add !== 'function' || typeof w.captured !== 'function')) {
    throw new RenderError('unsupported', 'Este motor de áudio não separa as faixas no render. Atualize o app e tente de novo.');
  }

  // os canais de saída primeiro: se não couberem na memória, nem vale começar. Acima do teto nem
  // se tenta: um pedido absurdo (trecho errado) derruba o processo inteiro em vez de dar RangeError
  const total = frames.total;
  const result = [];
  const noMemory = () => {
    const minutes = (total / rate / 60).toFixed(1).replace('.', ',');
    const outs = `${outputs.length} ${outputs.length === 1 ? 'saída' : 'saídas'}`;
    return new RenderError('memory', `Não há memória para renderizar ${minutes} min em ${outs}. Exporte um trecho menor ou menos faixas separadas.`);
  };
  if (outputs.length * 2 * total * 4 > MAX_RENDER_BYTES) throw noMemory();
  try {
    for (let i = 0; i < outputs.length; i++) result.push([new Float32Array(total), new Float32Array(total)]);
  } catch (err) {
    if (err instanceof RangeError) throw noMemory();
    throw err;
  }

  // Cada passada roda um motor novo com até MAX_CAPTURES saídas (o limite de capturas do motor);
  // um pedido com mais faixas separadas roda em várias, como no Android.
  const passes = Math.ceil(outputs.length / MAX_CAPTURES);
  for (let pass = 0; pass < passes; pass++) {
    const first = pass * MAX_CAPTURES;
    const outs = outputs.slice(first, first + MAX_CAPTURES);
    const passTracks = outs.some((o) => o !== -1);
    w.init(rate);
    // os áudios: a memória do wasm fica com eles (o `sample_load` toma posse)
    for (const s of job.samples || []) {
      const [l, r] = s.channels;
      if (!l || l.length === 0) continue;
      const n = l.length;
      const pl = w.alloc(n);
      new Float32Array(w.memory.buffer, pl, n).set(l);
      let pr = 0;
      if (r && r.length === n) {
        pr = w.alloc(n);
        new Float32Array(w.memory.buffer, pr, n).set(r);
      }
      w.sample_load(s.id, pl, pr, n, s.rate);
      // no Worker a cópia que veio na mensagem já não serve: solta antes do render (num projeto
      // longo, os áudios em dobro pesam tanto quanto as saídas); só na última passada, que as
      // anteriores precisam deles de novo
      if (job.releaseSamples && pass === passes - 1) s.channels = null;
    }

    for (const [name, ...args] of prepareCalls(calls, toBeat, bpm, map)) {
      // um motor mais antigo que o app não conhece alguma função nova: o resto do documento vale
      if (typeof w[name] === 'function') w[name](...args);
    }
    // o render nunca tem metrônomo nem loop (o trecho é linear, do começo ao fim) e ninguém observa
    // espectro ou indicador: só custariam
    w.loop_set(0, 0, 0);
    w.metronome(0, 0);
    w.watch_fx(-1, -1);
    w.watch_analyzer(-2);

    // de onde vem cada saída: o master é a própria saída do `process`; as faixas, capturas do motor.
    // Com capturas, o primeiro `process` prepara o render: as transições de um motor recém-criado
    // (efeitos entrando do seco, envios subindo do zero) terminam no silêncio e o atraso do limitador
    // do master é descontado, para a saída começar alinhada na posição de partida. Só o master
    // também quer isso (senão a mixagem sairia diferente com e sem stems): a captura dele serve só
    // para preparar.
    const canCapture = typeof w.capture_clear === 'function' && typeof w.capture_add === 'function';
    const sources = [];
    if (canCapture) w.capture_clear();
    for (const o of outs) {
      if (o === -1) {
        sources.push(-1);
        continue;
      }
      const index = w.capture_add(o);
      if (!(index >= 0)) throw new RenderError('failed', `O motor não conseguiu separar a faixa ${o + 1} no render.`);
      sources.push(index);
    }
    if (canCapture && !passTracks) w.capture_add(-1);

    const pl = w.alloc(RENDER_BLOCK);
    const pr = w.alloc(RENDER_BLOCK);
    const cl = passTracks ? w.alloc(RENDER_BLOCK) : 0;
    const cr = passTracks ? w.alloc(RENDER_BLOCK) : 0;
    let mem = null;
    let vl, vr, vcl, vcr;

    w.seek(fromBeat);
    w.play();
    let done = 0;
    let lastReport = -1;
    const now = typeof performance !== 'undefined' ? () => performance.now() : () => Date.now();
    while (done < total) {
      const n = Math.min(RENDER_BLOCK, total - done);
      w.process(pl, pr, n);
      // a memória pode crescer em qualquer chamada: as vistas são refeitas quando o buffer muda
      if (w.memory.buffer !== mem) {
        mem = w.memory.buffer;
        vl = new Float32Array(mem, pl, RENDER_BLOCK);
        vr = new Float32Array(mem, pr, RENDER_BLOCK);
        if (passTracks) {
          vcl = new Float32Array(mem, cl, RENDER_BLOCK);
          vcr = new Float32Array(mem, cr, RENDER_BLOCK);
        }
      }
      for (let k = 0; k < sources.length; k++) {
        const [ol, or] = result[first + k];
        if (sources[k] === -1) {
          ol.set(n === RENDER_BLOCK ? vl : vl.subarray(0, n), done);
          or.set(n === RENDER_BLOCK ? vr : vr.subarray(0, n), done);
        } else {
          w.captured(sources[k], cl, cr, n);
          if (w.memory.buffer !== mem) {
            mem = w.memory.buffer;
            vl = new Float32Array(mem, pl, RENDER_BLOCK);
            vr = new Float32Array(mem, pr, RENDER_BLOCK);
            vcl = new Float32Array(mem, cl, RENDER_BLOCK);
            vcr = new Float32Array(mem, cr, RENDER_BLOCK);
          }
          ol.set(n === RENDER_BLOCK ? vcl : vcl.subarray(0, n), done);
          or.set(n === RENDER_BLOCK ? vcr : vcr.subarray(0, n), done);
        }
      }
      done += n;
      if (onProgress) {
        const t = now();
        if (t - lastReport >= 100) {
          lastReport = t;
          onProgress((pass + done / total) / passes);
        }
      }
    }
    // o motor da próxima passada nasce de `init`: solta os blocos desta (o `alloc` não se solta sozinho)
    if (typeof w.dealloc !== 'function') continue;
    w.dealloc(pl, RENDER_BLOCK);
    w.dealloc(pr, RENDER_BLOCK);
    if (passTracks) {
      w.dealloc(cl, RENDER_BLOCK);
      w.dealloc(cr, RENDER_BLOCK);
    }
  }
  if (onProgress) onProgress(1);
  return { outputs: result, frames: total };
}

// Copia os canais para a memória do wasm (que toma posse: `stretch_run` e `detect_bpm` os consomem).
function loadChannels(w, channels) {
  const [l, r] = channels;
  if (!l || l.length === 0) throw new RenderError('empty', 'Este áudio está vazio.');
  const n = l.length;
  const pl = w.alloc(n);
  new Float32Array(w.memory.buffer, pl, n).set(l);
  let pr = 0;
  if (r && r.length === n) {
    pr = w.alloc(n);
    new Float32Array(w.memory.buffer, pr, n).set(r);
  }
  return { pl, pr, n };
}

// Esticar e transpor com as funções do engine.wasm já instanciado. Devolve os canais novos.
function stretchWith(w, job) {
  if (typeof w.stretch_run !== 'function') throw new RenderError('unsupported', 'Este motor de áudio não faz warp. Atualize o app e tente de novo.');
  const { pl, pr, n } = loadChannels(w, job.channels);
  const frames = w.stretch_run(pl, pr, n, job.rate, job.ratio, job.semitones || 0);
  const out = [];
  const count = pr ? 2 : 1;
  for (let i = 0; i < count; i++) {
    // cópia: a memória do wasm pode crescer e o buffer é solto no `stretch_free`
    out.push(new Float32Array(w.memory.buffer, w.stretch_channel(i), frames).slice());
  }
  w.stretch_free();
  return { channels: out, frames };
}

function detectWith(w, job) {
  if (typeof w.detect_bpm !== 'function') throw new RenderError('unsupported', 'Este motor de áudio não detecta andamento. Atualize o app e tente de novo.');
  const { pl, pr, n } = loadChannels(w, job.channels);
  const bpm = w.detect_bpm(pl, pr, n, job.rate);
  return { bpm, confidence: w.detect_confidence() };
}

if (typeof module !== 'undefined' && module.exports) {
  module.exports = { stretchWith, detectWith, renderWith, prepareCalls, frameCounts, tempoOf, tempoMapOf, RenderError, RENDER_BLOCK, CUT_FADE_SECS };
}

// ------------------------------------------------------------------ Worker

if (typeof self !== 'undefined' && typeof self.postMessage === 'function' && typeof module === 'undefined') {
  self.onmessage = async (e) => {
    const job = e.data;
    if (!job || (job.t !== 'render' && job.t !== 'stretch' && job.t !== 'detect')) return;
    try {
      const instance = job.wasm instanceof WebAssembly.Module ? await WebAssembly.instantiate(job.wasm, {}) : (await WebAssembly.instantiate(job.wasm, {})).instance;
      const w = instance.exports;
      if (job.t === 'stretch') {
        const r = stretchWith(w, job);
        self.postMessage({ t: 'stretched', channels: r.channels, frames: r.frames }, r.channels.map((c) => c.buffer));
        return;
      }
      if (job.t === 'detect') {
        const r = detectWith(w, job);
        self.postMessage({ t: 'tempo', bpm: r.bpm, confidence: r.confidence });
        return;
      }
      job.releaseSamples = true;
      const r = renderWith(w, job, (p) => self.postMessage({ t: 'progress', p }));
      const transfer = [];
      for (const [l, rr] of r.outputs) transfer.push(l.buffer, rr.buffer);
      self.postMessage({ t: 'done', outputs: r.outputs, frames: r.frames }, transfer);
    } catch (err) {
      const code = err instanceof RenderError ? err.code : err instanceof RangeError ? 'memory' : 'failed';
      const message =
        err instanceof RenderError
          ? err.message
          : code === 'memory'
            ? 'Não há memória para terminar o render. Exporte um trecho menor ou menos faixas separadas.'
            : `O motor falhou no render: ${(err && err.message) || err}`;
      self.postMessage({ t: 'error', code, message });
    }
  };
}
