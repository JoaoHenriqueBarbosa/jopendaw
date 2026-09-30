// Confere, sem navegador, a detecção de falha do host.js: `processorerror`, mensagem fatal do
// worklet e falta de estados com o áudio rodando viram um único `onEngineFailed`; `restart` recria
// o contexto e o nó e volta a avisar. Imprime "ok" ou sai com erro.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

let now = 0;
const timers = new Set();
const contexts = [];
const nodes = [];

class FakePort {
  constructor() {
    this.onmessage = null;
    this.sent = [];
  }
  postMessage(m) {
    this.sent.push(m);
    // o worklet responde ao init com o ready
    if (m.t === 'init') queueMicrotask(() => this.onmessage?.({ data: { t: 'ready', rate: 48000 } }));
  }
}
class FakeNode {
  constructor() {
    this.port = new FakePort();
    this.onprocessorerror = null;
    this.disconnected = false;
    nodes.push(this);
  }
  connect() {}
  disconnect() {
    this.disconnected = true;
  }
}
class FakeContext {
  constructor() {
    this.state = 'running';
    this.baseLatency = 0;
    this.sampleRate = 48000;
    this.closed = false;
    this.audioWorklet = { addModule: async () => {} };
    this.destination = {};
    contexts.push(this);
  }
  async resume() {
    this.state = 'running';
  }
  async close() {
    this.closed = true;
    this.state = 'closed';
  }
}

const window = {};
const sandbox = {
  window,
  console: { error() {}, log() {} },
  AudioContext: FakeContext,
  AudioWorkletNode: FakeNode,
  fetch: async () => ({ ok: true, arrayBuffer: async () => new ArrayBuffer(8) }),
  performance: { now: () => now },
  setInterval: (fn) => {
    const t = { fn };
    timers.add(t);
    return t;
  },
  clearInterval: (t) => timers.delete(t),
  setTimeout: () => 0,
  queueMicrotask,
  Promise,
  Math,
  Number,
  String,
  Array,
  Set,
  Error,
  indexedDB: {},
  navigator: {},
};
vm.createContext(sandbox);
vm.runInContext(readFileSync(new URL('../../web/engine/host.js', import.meta.url), 'utf8'), sandbox);
const host = window.jopendawEngine;

const failures = [];
host.setOnEngineFailed((m) => failures.push(m));
const tick = (ms) => {
  now += ms;
  for (const t of [...timers]) t.fn();
};
const state = (n, playing = true) => n.port.onmessage({ data: { t: 'state', beat: 1, playing, peaks: new Float32Array(0), fxMeter: 0, analyzing: false, spectrum: null } });
const tickWithStates = (n, times) => {
  for (let i = 0; i < times; i++) {
    state(n);
    tick(1000);
  }
};

// 1) sobe e roda: estados chegando, nenhuma falha
assert.equal(await host.start(), 48000);
let node = nodes[0];
tickWithStates(node, 8);
assert.deepEqual(failures, []);

// 2) sem estado por mais de 4 s com o contexto rodando: falha, uma vez só
tick(1000);
tick(1000);
tick(1000);
assert.deepEqual(failures, [], 'ainda dentro do limite');
tick(1000);
tick(1000);
assert.equal(failures.length, 1, 'parou de responder');
tick(5000);
tick(5000);
assert.equal(failures.length, 1, 'avisa uma vez só');

// 3) reiniciar: contexto e nó novos, o velho solto
assert.equal(await host.restart(), 48000);
assert.equal(contexts.length, 2);
assert.equal(contexts[0].closed, true);
assert.equal(nodes[0].disconnected, true);
node = nodes[1];
tickWithStates(node, 8);
assert.equal(failures.length, 1, 'motor novo saudável: sem aviso');

// 4) processorerror
node.onprocessorerror({});
assert.equal(failures.length, 2);
node.onprocessorerror({});
assert.equal(failures.length, 2, 'uma vez só');

// 5) mensagem fatal do worklet (trap do wasm); a que não é fatal não avisa
await host.restart();
node = nodes[2];
node.port.onmessage({ data: { t: 'error', message: 'chamada desconhecida', fatal: false } });
assert.equal(failures.length, 2);
node.port.onmessage({ data: { t: 'error', message: 'RuntimeError: unreachable', fatal: true } });
assert.equal(failures.length, 3);
assert.match(failures[2], /unreachable/);

// 6) contexto suspenso (aba sem gesto) e página travada não são falha
await host.restart();
node = nodes[3];
tickWithStates(node, 2);
contexts[3].state = 'suspended';
tick(10000);
tick(10000);
assert.equal(failures.length, 3, 'suspenso não é falha');
contexts[3].state = 'running';
now += 30000; // a página ficou travada: o timer atrasou junto com os estados
tick(1000);
assert.equal(failures.length, 3, 'timer atrasado não é falha');

console.log('ok');
