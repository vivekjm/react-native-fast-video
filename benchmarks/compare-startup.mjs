import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';

const [coldPath, warmPath] = process.argv.slice(2);
if (!coldPath || !warmPath) {
  console.error('Usage: node benchmarks/compare-startup.mjs <cold.json> <warm.json>');
  process.exit(2);
}

const cold = JSON.parse(fs.readFileSync(path.resolve(coldPath), 'utf8'));
const warm = JSON.parse(fs.readFileSync(path.resolve(warmPath), 'utf8'));

for (const [name, result] of [['cold', cold], ['warm', warm]]) {
  if (typeof result.metrics?.ttffP50Ms !== 'number' || typeof result.metrics?.ttffP95Ms !== 'number') {
    throw new Error(`${name} result must contain finite metrics.ttffP50Ms and metrics.ttffP95Ms`);
  }
}

const same = ['device', 'os', 'fixtureId', 'scenario'].every(
  (key) => cold.metadata?.[key] === warm.metadata?.[key]
);
if (!same) throw new Error('Cold and warm results must use the same device, OS, fixture and scenario.');

function improvement(coldValue, warmValue) {
  if (coldValue <= 0) return 0;
  return ((coldValue - warmValue) / coldValue) * 100;
}

const p50 = improvement(cold.metrics.ttffP50Ms, warm.metrics.ttffP50Ms);
const p95 = improvement(cold.metrics.ttffP95Ms, warm.metrics.ttffP95Ms);

console.log(JSON.stringify({
  device: cold.metadata.device,
  fixtureId: cold.metadata.fixtureId,
  scenario: cold.metadata.scenario,
  cold: { p50Ms: cold.metrics.ttffP50Ms, p95Ms: cold.metrics.ttffP95Ms },
  warm: { p50Ms: warm.metrics.ttffP50Ms, p95Ms: warm.metrics.ttffP95Ms },
  improvementPct: { p50: Number(p50.toFixed(2)), p95: Number(p95.toFixed(2)) }
}, null, 2));
