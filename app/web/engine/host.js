// Ponte entre o Flutter (lib/audio/engine_web.dart) e o motor no AudioWorklet, mais o guardado
// local do DAW no IndexedDB (documento do projeto e os áudios importados).
(() => {
  let ctx = null;
  let node = null;
  let starting = null;
  let onState = null;

  async function start() {
    if (starting) return starting;
    starting = (async () => {
      ctx = new AudioContext({ latencyHint: 'interactive' });
      const [bytes] = await Promise.all([
        fetch('engine/engine.wasm').then((r) => r.arrayBuffer()),
        ctx.audioWorklet.addModule('engine/worklet.js'),
      ]);
      node = new AudioWorkletNode(ctx, 'jopendaw-engine', { numberOfInputs: 0, outputChannelCount: [2] });
      node.connect(ctx.destination);
      const ready = new Promise((resolve, reject) => {
        node.port.onmessage = (e) => {
          const m = e.data;
          if (m.t === 'ready') resolve(m.rate);
          else if (m.t === 'error') {
            console.error('motor de áudio:', m.message);
            reject(new Error(m.message));
          }
          else if (m.t === 'state' && onState) onState(m.beat, m.playing, m.peaks);
        };
      });
      node.port.postMessage({ t: 'init', bytes }, [bytes]);
      return ready;
    })();
    return starting;
  }

  // O navegador só deixa o áudio sair depois de um gesto do usuário.
  async function resume() {
    if (ctx && ctx.state !== 'running') await ctx.resume();
  }

  async function decode(bytes) {
    await start();
    // decodeAudioData destaca o buffer: vai uma cópia
    const buf = await ctx.decodeAudioData(bytes.slice().buffer);
    const channels = [];
    for (let c = 0; c < Math.min(2, buf.numberOfChannels); c++) channels.push(buf.getChannelData(c));
    return { channels, rate: buf.sampleRate };
  }

  function loadSample(id, channels, rate) {
    node.port.postMessage({ t: 'sample', id, channels: channels.map((c) => c.slice()), rate });
  }

  function calls(list) {
    if (node) node.port.postMessage({ t: 'calls', list });
  }

  // ------------------------------------------------------------ IndexedDB

  let dbp = null;
  function db() {
    dbp ??= new Promise((resolve, reject) => {
      const req = indexedDB.open('jopendaw', 1);
      req.onupgradeneeded = () => req.result.createObjectStore('kv');
      req.onsuccess = () => resolve(req.result);
      req.onerror = () => reject(req.error);
    });
    return dbp;
  }

  async function tx(mode, fn) {
    const d = await db();
    return new Promise((resolve, reject) => {
      const t = d.transaction('kv', mode);
      const req = fn(t.objectStore('kv'));
      t.oncomplete = () => resolve(req.result);
      t.onerror = () => reject(t.error);
    });
  }

  window.jopendawEngine = {
    start,
    resume,
    decode,
    loadSample,
    calls,
    setOnState: (cb) => { onState = cb; },
    latency: () => (ctx ? (ctx.baseLatency || 0) + (ctx.outputLatency || 0) : 0),
    idbGet: (key) => tx('readonly', (s) => s.get(key)).then((v) => v ?? null),
    idbPut: (key, value) => tx('readwrite', (s) => s.put(value, key)),
    idbDelete: (key) => tx('readwrite', (s) => s.delete(key)),
  };
})();
