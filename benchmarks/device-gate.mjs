import fs from 'node:fs';

const file = process.argv[2];
if (!file) throw new Error('Usage: node benchmarks/device-gate.mjs <device-result.json>');
const r = JSON.parse(fs.readFileSync(file, 'utf8'));
const b = r.budgets ?? {};
const m = r.metrics ?? {};

const checks = [
  ['cold TTFF p50', m.coldTtffP50Ms <= b.maxColdTtffP50Ms, `${m.coldTtffP50Ms}ms`],
  ['warm TTFF p50', m.warmTtffP50Ms <= b.maxWarmTtffP50Ms, `${m.warmTtffP50Ms}ms`],
  ['warm improvement', m.warmTtffP50Ms <= m.coldTtffP50Ms * b.maxWarmVsColdRatio, `${m.warmTtffP50Ms}/${m.coldTtffP50Ms}`],
  ['rebuffer ratio', m.rebufferRatio <= b.maxRebufferRatio, m.rebufferRatio],
  ['dropped frame ratio', m.droppedFrameRatio <= b.maxDroppedFrameRatio, m.droppedFrameRatio],
  ['QoE', m.qoeP50 >= b.minQoeP50, m.qoeP50],
];
let failed = false;
for (const [name, pass, value] of checks) {
  console.log(`${pass ? 'PASS' : 'FAIL'}  ${name}: ${value}`);
  failed ||= !pass;
}
if (failed) process.exit(1);
