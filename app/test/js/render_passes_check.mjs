// Render da web com mais saídas que as 64 capturas do motor: roda em passadas (como o Android) e cada
// saída sai no lugar dela. Usa o engine.wasm de verdade. Imprime "ok" ou sai com erro.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const { renderWith } = require('../../web/engine/render-worker.js');
const bytes = readFileSync(new URL('../../web/engine/engine.wasm', import.meta.url));
const { instance } = await WebAssembly.instantiate(bytes, {});

const TRACKS = 70;
const calls = [['tempo', 120, 4], ['tracks', TRACKS], ['master', 1, 0]];
for (let i = 0; i < TRACKS; i++) calls.push(['track', i, 1, 0, 0, 0]);
// um clipe só, na última faixa (segunda passada)
calls.push(['clip_add', TRACKS - 2, 1, 0, 0, 0.5, 1, 0, 0]);
const sample = { id: 1, channels: [new Float32Array(48000).fill(0.5)], rate: 48000 };

const outputs = [-1];
for (let i = 0; i < TRACKS; i++) outputs.push(i);
const progress = [];
const r = renderWith(instance.exports, { calls, samples: [sample], fromBeat: 0, toBeat: 1, tail: 0, outputs, rate: 48000 }, (p) => progress.push(p));

assert.equal(r.outputs.length, outputs.length, 'uma saída para cada pedida');
const peak = (o) => Math.max(...o[0].map(Math.abs).slice(2000, 20000));
assert.ok(peak(r.outputs[0]) > 0.01, 'o master ouve o clipe');
assert.ok(peak(r.outputs[1 + TRACKS - 2]) > 0.01, 'a faixa do clipe (2ª passada) tem o som');
for (const i of [0, 3, 63, 64, TRACKS - 1]) assert.equal(peak(r.outputs[1 + i]), 0, `a faixa ${i} está muda`);
assert.equal(progress.at(-1), 1);
assert.ok(progress.every((p, i) => i === 0 || p >= progress[i - 1]), 'o progresso não volta');
console.log('ok');
