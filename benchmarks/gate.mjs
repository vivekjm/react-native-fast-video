import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';

const resultPath = process.argv[2];
if (!resultPath) {
  console.error('Usage: node benchmarks/gate.mjs <result.json>');
  process.exit(2);
}

const root = path.resolve(import.meta.dirname, '..');
const budgets = JSON.parse(fs.readFileSync(path.join(root, 'benchmarks/budgets.json'), 'utf8'));
const result = JSON.parse(fs.readFileSync(path.resolve(resultPath), 'utf8'));

const requiredMetadata = ['device', 'os', 'buildSha', 'fixtureId', 'scenario', 'runs'];
for (const field of requiredMetadata) {
  if (result.metadata?.[field] === undefined || result.metadata[field] === '') {
    throw new Error(`Missing metadata.${field}`);
  }
}

const scenario = result.metadata.scenario;
const budget = budgets.budgets[scenario];
if (!budget) throw new Error(`Unknown benchmark scenario: ${scenario}`);

const failures = [];
for (const [metric, limit] of Object.entries(budget)) {
  const value = result.metrics?.[metric];
  if (typeof value !== 'number' || !Number.isFinite(value)) {
    failures.push(`${metric}: missing or non-finite`);
    continue;
  }
  if (value > limit) failures.push(`${metric}: ${value} > ${limit}`);
}

if (failures.length) {
  console.error(`Performance budget failed for ${scenario}:`);
  for (const failure of failures) console.error(`- ${failure}`);
  process.exit(1);
}

console.log(`Performance budget passed for ${scenario}${result.metadata.synthetic ? ' (synthetic smoke data)' : ''}.`);
