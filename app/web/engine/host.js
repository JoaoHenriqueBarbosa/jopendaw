// Ponte entre o Flutter (lib/audio/engine_web.dart) e o motor no AudioWorklet, mais o guardado
// local do DAW no IndexedDB (documento do projeto e os áudios importados) e as entradas MIDI.
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

  // ------------------------------------------------------------ MIDI (Web MIDI)

  let midi = null;
  let midiRequest = null;
  let onMidi = null;
  let onMidiInputs = null;

  function midiNames() {
    const names = [];
    for (const input of midi.inputs.values()) {
      if (input.state === 'connected') names.push(input.name || 'Entrada MIDI');
    }
    return names;
  }

  // Só mensagens de canal (nota, controle, pitch bend...): relógio e active sensing chegam
  // dezenas de vezes por segundo e não interessam ao Dart.
  function onMidiMessage(e) {
    const d = e.data;
    if (!onMidi || !d || d.length === 0 || d[0] < 0x80 || d[0] >= 0xf0) return;
    onMidi(d[0], d.length > 1 ? d[1] : 0, d.length > 2 ? d[2] : 0);
  }

  // A propriedade (e não addEventListener) não dobra o ouvinte quando uma entrada volta; atribuir
  // já abre a porta.
  function listenAll() {
    for (const input of midi.inputs.values()) input.onmidimessage = onMidiMessage;
  }

  // Devolve { inputs } ou { error: 'unsupported' | 'denied' | 'failed', message }: o Dart escreve a
  // mensagem para o usuário.
  async function enableMidi() {
    if (!navigator.requestMIDIAccess) return { error: 'unsupported' };
    if (!midi) {
      midiRequest ??= navigator.requestMIDIAccess({ sysex: false });
      try {
        midi = await midiRequest;
      } catch (err) {
        midiRequest = null; // deixa tentar de novo depois de liberar a permissão
        const name = err && err.name;
        const denied = name === 'SecurityError' || name === 'NotAllowedError';
        return { error: denied ? 'denied' : 'failed', message: String((err && err.message) || err) };
      }
      // aparelho entrando ou saindo com a página aberta
      midi.onstatechange = () => {
        listenAll();
        if (onMidiInputs) onMidiInputs(midiNames());
      };
    }
    listenAll();
    return { inputs: midiNames() };
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
    enableMidi,
    setOnMidi: (cb) => { onMidi = cb; },
    setOnMidiInputs: (cb) => { onMidiInputs = cb; },
  };
})();
