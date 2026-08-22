import fs from 'node:fs';

const file = process.argv[2];
if (!file) throw new Error('Usage: node benchmarks/predictive-gate.mjs <result.json>');
const result = JSON.parse(fs.readFileSync(file, 'utf8'));

const checks = [
  ['bandwidth confidence', result.bandwidthConfidence >= 0.55, result.bandwidthConfidence],
  ['bandwidth volatility', result.bandwidthVolatility <= 0.45, result.bandwidthVolatility],
  ['viewport confidence', result.viewportIntent?.confidence >= 0.55, result.viewportIntent?.confidence],
  ['cdn primary score', result.cdn?.primaryScore >= 70, result.cdn?.primaryScore],
  ['cdn degraded score separation', (result.cdn?.primaryScore - result.cdn?.degradedScore) >= 20, `${result.cdn?.primaryScore} / ${result.cdn?.degradedScore}`],
  ['average frame processing offset', result.averageFrameProcessingOffsetUs <= 6_000, result.averageFrameProcessingOffsetUs],
];

let failed = false;
for (const [name, pass, value] of checks) {
  console.log(`${pass ? 'PASS' : 'FAIL'}  ${name}: ${value}`);
  failed ||= !pass;
}
if (failed) process.exit(1);
