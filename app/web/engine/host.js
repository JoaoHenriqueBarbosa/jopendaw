// Ponte entre o Flutter (lib/audio/engine_web.dart) e o motor no AudioWorklet, mais o guardado
// local do DAW no IndexedDB (documento do projeto e os áudios importados), as entradas MIDI e,
// na fase 4, a entrada de áudio (gravação e monitoramento), o render fora de tempo real num Worker
// (exportar e congelar) e o download de arquivos.
(() => {
  let ctx = null;
  let node = null;
  let starting = null;
  let onState = null;

  // Último estado do motor e o maior pico de cada canal desde a última leitura: para conferir de
  // fora (console, testes automatizados) que o áudio está saindo mesmo, sem precisar ouvir.
  const probe = { beat: 0, playing: false, peaks: [], fxMeter: 0, spectrum: null, inputPeak: 0 };
  // O worklet manda o espectro a cada poucos estados; entre um e outro vale o último (null só
  // quando nada é observado, como o Dart espera).
  let spectrum = null;
  function track(beat, playing, peaks, fxMeter) {
    probe.beat = beat;
    probe.playing = playing;
    probe.fxMeter = Math.max(probe.fxMeter, fxMeter);
    probe.spectrum = spectrum;
    // faixas entraram ou saíram: as posições agora são de outros canais
    if (peaks.length !== probe.peaks.length) probe.peaks = [];
    for (let i = 0; i < peaks.length; i++) probe.peaks[i] = Math.max(probe.peaks[i] || 0, peaks[i]);
    probe.peaks.length = peaks.length;
  }

  // Os bytes do engine.wasm, baixados uma vez: o worklet recebe uma cópia (os bytes vão
  // transferidos) e o render compila o módulo dele a partir daqui, sem depender da rede de novo.
  let wasmBytes = null;
  function engineBytes() {
    if (!wasmBytes) {
      const p = fetch('engine/engine.wasm').then((r) => {
        if (!r.ok) throw new Error(`engine.wasm: HTTP ${r.status}`);
        return r.arrayBuffer();
      });
      wasmBytes = p;
      // deixa tentar de novo quando a rede voltar
      p.catch(() => {
        if (wasmBytes === p) wasmBytes = null;
      });
    }
    return wasmBytes;
  }

  async function start() {
    if (starting) return starting;
    starting = (async () => {
      ctx = new AudioContext({ latencyHint: 'interactive' });
      const [bytes] = await Promise.all([engineBytes(), ctx.audioWorklet.addModule('engine/worklet.js')]);
      // Uma entrada sempre: o microfone liga nela quando a gravação pede, sem recriar o nó (que
      // levaria junto o motor e tudo o que ele sabe). Sem nada ligado, o worklet vê zero canais.
      node = new AudioWorkletNode(ctx, 'jopendaw-engine', { numberOfInputs: 1, numberOfOutputs: 1, outputChannelCount: [2] });
      node.connect(ctx.destination);
      const ready = new Promise((resolve, reject) => {
        node.port.onmessage = (e) => {
          const m = e.data;
          if (m.t === 'state') {
            if (!m.analyzing) spectrum = null;
            else if (m.spectrum) spectrum = m.spectrum;
            const fxMeter = m.fxMeter || 0;
            track(m.beat, m.playing, m.peaks, fxMeter);
            if (onState) onState(m.beat, m.playing, m.peaks, fxMeter, spectrum);
          } else if (m.t === 'level') {
            probe.inputPeak = Math.max(probe.inputPeak, m.peak);
            if (onInputLevel) onInputLevel(m.peak);
          } else if (m.t === 'rec') {
            onRecBlock(m);
          } else if (m.t === 'captured') {
            if (onCaptureEnd) onCaptureEnd(m.notes);
          } else if (m.t === 'ready') resolve(m.rate);
          else if (m.t === 'error') {
            console.error('motor de áudio:', m.message);
            reject(new Error(m.message));
          }
        };
      });
      const copy = bytes.slice(0);
      node.port.postMessage({ t: 'init', bytes: copy }, [copy]);
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

  // ------------------------------------------------------------ entrada de áudio (gravação)

  // A entrada aberta: o stream do getUserMedia e o nó que liga ele no worklet.
  let input = null;
  // Cada abertura ou fechamento ganha um número: uma permissão que chega depois de um stopInput
  // (ou de outro startInput) é descartada em vez de reabrir a entrada por trás.
  let inputGen = 0;
  let onRecord = null;
  let onInputLevel = null;
  let onCaptureEnd = null;
  let onInputLost = null;

  function closeInput() {
    if (!input) return;
    const { stream, source } = input;
    input = null;
    for (const t of stream.getTracks()) {
      t.onended = null;
      t.stop();
    }
    try {
      source.disconnect();
    } catch (_) {
      // já desligado
    }
    if (node) node.port.postMessage({ t: 'input', on: false });
    if (onInputLevel) onInputLevel(0);
  }

  // Erros do getUserMedia viram códigos que o Dart transforma em mensagem para o usuário.
  function inputError(err) {
    const name = err && err.name;
    const message = String((err && err.message) || err);
    if (name === 'NotAllowedError' || name === 'SecurityError' || name === 'PermissionDeniedError') return { error: 'denied', message };
    if (name === 'NotFoundError' || name === 'DevicesNotFoundError') return { error: 'notfound', message };
    if (name === 'OverconstrainedError' || name === 'ConstraintNotSatisfiedError') return { error: 'missing', message };
    if (name === 'NotReadableError' || name === 'TrackStartError' || name === 'AbortError') return { error: 'busy', message };
    return { error: 'failed', message };
  }

  // Abre a entrada ([deviceId] null = a padrão do sistema) sem nenhum processamento de voz (eco,
  // ruído e ganho automático estragam instrumento e voz gravada) e liga no worklet. Devolve
  // { latency, label } (latência de entrada em segundos: a do aparelho, quando o navegador
  // informa, mais a base do contexto) ou { error, message }.
  async function startInput(deviceId) {
    const md = navigator.mediaDevices;
    if (!md || !md.getUserMedia) return { error: 'unsupported' };
    const gen = ++inputGen;
    closeInput();
    try {
      await start();
    } catch (err) {
      return { error: 'failed', message: String((err && err.message) || err) };
    }
    if (gen !== inputGen) return { error: 'aborted' };
    const audio = {
      echoCancellation: false,
      noiseSuppression: false,
      autoGainControl: false,
      channelCount: { ideal: 2 },
      // na mesma taxa do motor, o navegador não precisa converter (o Firefox nem converte)
      sampleRate: { ideal: ctx.sampleRate },
    };
    if (deviceId) audio.deviceId = { exact: deviceId };
    let stream;
    try {
      stream = await md.getUserMedia({ audio });
    } catch (err) {
      return inputError(err);
    }
    if (gen !== inputGen) {
      // fechada ou reaberta enquanto o navegador pedia a permissão
      for (const t of stream.getTracks()) t.stop();
      return { error: 'aborted' };
    }
    const tracks = stream.getAudioTracks();
    if (tracks.length === 0) {
      for (const t of stream.getTracks()) t.stop();
      return { error: 'notfound', message: 'o stream veio sem áudio' };
    }
    let source;
    try {
      source = new MediaStreamAudioSourceNode(ctx, { mediaStream: stream });
    } catch (err) {
      for (const t of stream.getTracks()) t.stop();
      const settings = tracks[0].getSettings ? tracks[0].getSettings() : {};
      // o Firefox recusa ligar um microfone numa taxa diferente da do contexto
      if (err && err.name === 'NotSupportedError') return { error: 'rate', message: String(err.message || err), inputRate: settings.sampleRate || 0, rate: ctx.sampleRate };
      return { error: 'failed', message: String((err && err.message) || err) };
    }
    source.connect(node);
    input = { stream, source };
    const track0 = tracks[0];
    // cabo puxado, interface desligada, permissão revogada: a trilha termina sozinha
    track0.onended = () => {
      if (!input || input.stream !== stream) return;
      closeInput();
      if (onInputLost) onInputLost(track0.label || '');
    };
    node.port.postMessage({ t: 'input', on: true });
    const settings = track0.getSettings ? track0.getSettings() : {};
    const deviceLatency = typeof settings.latency === 'number' && Number.isFinite(settings.latency) ? settings.latency : 0;
    return { latency: deviceLatency + (ctx.baseLatency || 0), label: track0.label || '' };
  }

  async function stopInput() {
    inputGen++;
    closeInput();
  }

  // Entradas de áudio: [{ id, name }]. Os nomes (e, no Safari, os próprios ids) só aparecem depois
  // de o site ganhar a permissão do microfone. As pseudo-entradas "default" e "communications" do
  // Chrome repetem uma entrada de verdade e ficam de fora: a padrão é o id nulo.
  async function inputDevices() {
    const md = navigator.mediaDevices;
    if (!md || !md.enumerateDevices) return [];
    const all = await md.enumerateDevices();
    const list = [];
    for (const d of all) {
      if (d.kind !== 'audioinput' || !d.deviceId || d.deviceId === 'default' || d.deviceId === 'communications') continue;
      list.push({ id: d.deviceId, name: d.label || `Entrada ${list.length + 1}` });
    }
    return list;
  }

  // Liga ou desliga a captura no worklet (entrada em blocos para onRecord e notas ao vivo no
  // motor). Desligar faz chegar o resto da gravação e depois onCaptureEnd, nessa ordem.
  function setCapture(on) {
    if (node) node.port.postMessage({ t: 'capture', on: !!on });
  }

  // O par de captura chega transferido: o Dart fica com uma cópia do trecho válido e o par volta ao
  // worklet para ser reusado (lá, criar arrays no caminho de áudio é o que se evita).
  function onRecBlock(m) {
    try {
      if (onRecord) onRecord(m.left.slice(0, m.frames), m.right.slice(0, m.frames), m.beat);
    } finally {
      // mesmo se o Dart falhar no bloco: sem a devolução o pool do worklet secaria
      if (node) node.port.postMessage({ t: 'recycle', left: m.left, right: m.right }, [m.left.buffer, m.right.buffer]);
    }
  }

  // ------------------------------------------------------------ render fora de tempo real

  let wasmModule = null;
  function engineModule() {
    if (!wasmModule) {
      const p = engineBytes().then((b) => WebAssembly.compile(b));
      wasmModule = p;
      p.catch(() => {
        if (wasmModule === p) wasmModule = null;
      });
    }
    return wasmModule;
  }

  // Renders em andamento (cada um num Worker próprio): cancelar encerra o Worker na hora, mesmo
  // no meio de um bloco.
  const renders = new Set();

  // Renderiza num Worker com um motor só dele. `job`: { calls, samples: [{ id, channels, rate }],
  // fromBeat, toBeat, tail, outputs, rate }. Devolve { outputs: [[esq, dir], ...], frames } ou
  // { error, message } (nunca rejeita: o Dart escreve a mensagem).
  async function renderOffline(job, onProgress) {
    if (typeof Worker === 'undefined') return { error: 'unsupported', message: 'Este navegador não consegue renderizar em segundo plano (sem Web Worker).' };
    let module;
    try {
      module = await engineModule();
    } catch (err) {
      return { error: 'failed', message: `Não deu para carregar o motor de áudio: ${(err && err.message) || err}` };
    }
    return new Promise((resolve) => {
      const worker = new Worker('engine/render-worker.js');
      const entry = { worker, resolve };
      renders.add(entry);
      const finish = (r) => {
        if (!renders.delete(entry)) return;
        worker.terminate();
        resolve(r);
      };
      entry.finish = finish;
      worker.onmessage = (e) => {
        const m = e.data;
        if (m.t === 'progress') {
          if (onProgress) onProgress(m.p);
        } else if (m.t === 'done') {
          finish({ outputs: m.outputs, frames: m.frames });
        } else if (m.t === 'error') {
          finish({ error: m.code || 'failed', message: m.message });
        }
      };
      worker.onerror = (e) => {
        e.preventDefault();
        finish({ error: 'failed', message: `O render parou: ${e.message || 'erro no Worker'}` });
      };
      worker.onmessageerror = () => finish({ error: 'failed', message: 'O render devolveu dados ilegíveis.' });
      try {
        // os áudios vão copiados: o Dart continua dono dos dele
        worker.postMessage({
          t: 'render',
          wasm: module,
          rate: job.rate,
          calls: job.calls,
          samples: job.samples,
          fromBeat: job.fromBeat,
          toBeat: job.toBeat,
          tail: job.tail,
          outputs: job.outputs,
        });
      } catch (err) {
        const memory = err && (err.name === 'DataCloneError' || err instanceof RangeError);
        finish({ error: memory ? 'memory' : 'failed', message: String((err && err.message) || err) });
      }
    });
  }

  function cancelRender() {
    for (const entry of [...renders]) entry.finish({ error: 'canceled' });
  }

  // ------------------------------------------------------------ warp

  // Roda uma tarefa do warp ('stretch' ou 'detect') num Worker próprio, com o mesmo engine.wasm.
  // Nunca rejeita: devolve a resposta do Worker ou { error, message } (o Dart escreve a mensagem).
  // O wasm do worklet não serve: aqui é uma instância à parte, então nada disso toca a thread de
  // áudio nem a da interface. Sem progresso fino (o wasm é síncrono): só 0 e 1.
  async function warpJob(kind, job, onProgress) {
    if (typeof Worker === 'undefined') return { error: 'unsupported', message: 'Este navegador não consegue processar em segundo plano (sem Web Worker).' };
    let module;
    try {
      module = await engineModule();
    } catch (err) {
      return { error: 'failed', message: `Não deu para carregar o motor de áudio: ${(err && err.message) || err}` };
    }
    if (onProgress) onProgress(0);
    return new Promise((resolve) => {
      const worker = new Worker('engine/render-worker.js');
      const finish = (r) => {
        worker.terminate();
        resolve(r);
      };
      worker.onmessage = (e) => {
        const m = e.data;
        if (m.t === 'stretched') {
          if (onProgress) onProgress(1);
          finish({ channels: m.channels, frames: m.frames });
        } else if (m.t === 'tempo') {
          finish({ bpm: m.bpm, confidence: m.confidence });
        } else if (m.t === 'error') {
          finish({ error: m.code || 'failed', message: m.message });
        }
      };
      worker.onerror = (e) => {
        e.preventDefault();
        finish({ error: 'failed', message: `O processamento parou: ${e.message || 'erro no Worker'}` });
      };
      worker.onmessageerror = () => finish({ error: 'failed', message: 'O processamento devolveu dados ilegíveis.' });
      try {
        // os canais vão copiados: o Dart continua dono do áudio dele
        worker.postMessage({ t: kind, wasm: module, ...job });
      } catch (err) {
        const memory = err && (err.name === 'DataCloneError' || err instanceof RangeError);
        finish({ error: memory ? 'memory' : 'failed', message: String((err && err.message) || err) });
      }
    });
  }

  const stretchAudio = (job, onProgress) => warpJob('stretch', job, onProgress);
  const detectBpm = (job) => warpJob('detect', job);

  // ------------------------------------------------------------ arquivos

  // Oferece os bytes como download. O link temporário vive um minuto: revogar logo depois do
  // clique cancela o download em alguns navegadores.
  // sha-256 em hexa pelo WebCrypto: nativo e assíncrono, não trava a tela com gravações longas
  // (o sha-256 em Dart levava segundos com centenas de MB na thread da interface)
  async function sha256(bytes) {
    const digest = new Uint8Array(await crypto.subtle.digest('SHA-256', bytes));
    let hex = '';
    for (const b of digest) hex += b.toString(16).padStart(2, '0');
    return hex;
  }

  async function saveFile(name, bytes, mime) {
    const blob = new Blob([bytes], { type: mime || 'application/octet-stream' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = name;
    a.rel = 'noopener';
    a.style.display = 'none';
    document.body.appendChild(a);
    a.click();
    a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 60000);
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
    // mensagem MIDI entrando pelo mesmo caminho de um aparelho (teste e depuração sem hardware)
    injectMidi: (status, d1, d2) => onMidiMessage({ data: [status, d1, d2] }),
    startInput,
    stopInput,
    inputDevices,
    setCapture,
    setOnRecord: (cb) => { onRecord = cb; },
    setOnInputLevel: (cb) => { onInputLevel = cb; },
    setOnCaptureEnd: (cb) => { onCaptureEnd = cb; },
    setOnInputLost: (cb) => { onInputLost = cb; },
    renderOffline,
    cancelRender,
    stretchAudio,
    detectBpm,
    saveFile,
    sha256,
    // posição, tocando, estado do contexto, os picos (esq, dir por faixa; o master por último) e
    // o maior indicador do efeito observado desde a leitura anterior, que zera os dois; com o
    // analisador ligado, a faixa mais forte do espectro (índice e dB) e quantas faixas ele tem; com
    // a entrada aberta, o maior pico dela
    probe: () => {
      const r = { beat: probe.beat, playing: probe.playing, context: ctx ? ctx.state : 'none', peaks: probe.peaks.map((v) => Math.round(v * 1000) / 1000) };
      r.fxMeter = Math.round(probe.fxMeter * 100) / 100;
      const s = probe.spectrum;
      if (s) {
        let bin = 0;
        for (let i = 1; i < s.length; i++) if (s[i] > s[bin]) bin = i;
        r.spectrum = { bins: s.length, peakBin: bin, peakDb: Math.round(s[bin] * 10) / 10 };
      }
      if (input) r.input = Math.round(probe.inputPeak * 1000) / 1000;
      probe.peaks = probe.peaks.map(() => 0);
      probe.fxMeter = 0;
      probe.inputPeak = 0;
      return r;
    },
  };
})();
