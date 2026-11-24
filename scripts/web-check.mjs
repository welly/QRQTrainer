// Checks web/qrq.wasm in Node: runs a short attempt with made-up answers and prints what the page would show.
//   node scripts/web-check.mjs [mode] [items]     e.g. node scripts/web-check.mjs words 10
import { readFile } from 'node:fs/promises';
import { createEngine } from '../web/engine.js';

const mode = process.argv[2] ?? 'callsigns';
const count = Number(process.argv[3] ?? 8);
const t0 = performance.now();
const engine = await createEngine(readFile(new URL('../web/qrq.wasm', import.meta.url)));
console.log(`load ${(performance.now() - t0).toFixed(0)} ms`);

const settings = { trainerMode: mode, count, startCPM: 150 };
console.log(engine.call('describe', { settings, seed: 7 }));
let state = engine.call('start', { settings });
console.log(`start: ${state.source}, ${state.total} items at ${state.cpm} CPM`);
const results = [];
while (!state.finished) {
  let t = performance.now();
  const { result: played, samples } = engine.call('play', {}, { audio: true });
  const ms = (performance.now() - t).toFixed(1);
  // Every third answer has a mistake.
  state = engine.call('submit', { answer: results.length % 3 === 2 ? played.text.slice(1) : played.text, responseTime: played.soundSeconds + 1.2, firstKeyTime: played.soundSeconds + 0.4 });
  const r = state.result;
  results.push(r);
  console.log(`${String(r.index + 1).padStart(2)}. ${r.sent.padEnd(12)} ${r.received.padEnd(12)} ${r.cpm.toFixed(0)} CPM  ${r.points}/${state.detail.maxPoints} pts  sound ${played.soundSeconds.toFixed(2)} s (${samples.length} samples, ${ms} ms)`);
}
console.log(`score ${state.score}`);
const insights = engine.call('analyse', { results, minSamples: 1 });
console.log(`answered ${insights.answered}, ranked ${insights.ranked}, mix-ups ${insights.confusions.length}, bands ${insights.bands.length}`);
const list = engine.call('setList', { text: '# test\nG3AJM DL1ABC\nnot-a-call, ea8/g4abc\n' });
console.log('setList', list);
