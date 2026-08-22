import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve(import.meta.dirname, '..');
const required = [
  'README.md',
  'docs/ARCHITECTURE.md',
  'docs/FEATURE_MATRIX.md',
  'cpp/include/rnfv/session.hpp',
  'android/src/main/java/com/vivekjm/fastvideo/FastVideoEngine.kt',
  'ios/FastVideoEngine.swift',
  'src/FastVideo.tsx',
  'plugin/src/withReactNativeFastVideo.ts',
];

const missing = required.filter((file) => !fs.existsSync(path.join(root, file)));
if (missing.length) {
  console.error(`Missing required files:\n${missing.map((file) => `- ${file}`).join('\n')}`);
  process.exit(1);
}

const readme = fs.readFileSync(path.join(root, 'README.md'), 'utf8').toLowerCase();
const forbiddenClaims = ['fastest video player', 'crushes every benchmark', 'zero dropped frames'];
const violations = forbiddenClaims.filter((claim) => readme.includes(claim));
if (violations.length) {
  console.error(`Unverified performance claims found: ${violations.join(', ')}`);
  process.exit(1);
}

console.log('Source audit passed.');
