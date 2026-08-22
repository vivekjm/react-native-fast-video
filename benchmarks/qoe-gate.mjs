import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';

const input = process.argv[2];
if (!input) { console.error('Usage: node benchmarks/qoe-gate.mjs <result.json>'); process.exit(2); }
const result = JSON.parse(fs.readFileSync(path.resolve(input), 'utf8'));
const required = ['device', 'os', 'buildSha', 'fixtureId', 'scenario', 'runs'];
for (const key of required) if (result.metadata?.[key] === undefined || result.metadata[key] === '') throw new Error(`Missing metadata.${key}`);
const qoe = result.metrics?.qoeScoreP50;
if (typeof qoe !== 'number' || !Number.isFinite(qoe)) throw new Error('Missing finite metrics.qoeScoreP50');
const minimum = result.metadata.scenario === 'live-low-latency' ? 78 : 82;
if (qoe < minimum) { console.error(`QoE gate failed: ${qoe} < ${minimum}`); process.exit(1); }
console.log(`QoE gate passed: ${qoe} >= ${minimum}${result.metadata.synthetic ? ' (synthetic smoke data)' : ''}.`);
