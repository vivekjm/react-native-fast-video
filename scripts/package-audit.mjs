import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';

const packageJson = JSON.parse(readFileSync(new URL('../package.json', import.meta.url), 'utf8'));
const readme = readFileSync(new URL('../README.md', import.meta.url), 'utf8');
const expoConfig = JSON.parse(
  readFileSync(new URL('../expo-module.config.json', import.meta.url), 'utf8')
);

const packed = JSON.parse(
  execFileSync('npm', ['pack', '--dry-run', '--json', '--ignore-scripts'], {
    cwd: new URL('..', import.meta.url),
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
  })
)[0];
const files = new Set(packed.files.map((entry) => entry.path));

const required = [
  'package.json',
  'README.md',
  'LICENSE',
  'app.plugin.js',
  'expo-module.config.json',
  'build/index.js',
  'build/index.d.ts',
  'plugin/build/withReactNativeFastVideo.js',
  'android/build.gradle',
  'android/src/main/AndroidManifest.xml',
  'ios/ReactNativeFastVideo.podspec',
  'cpp/include/rnfv/c_api.h',
];
for (const path of required) {
  if (!files.has(path)) throw new Error(`Published package is missing ${path}.`);
}

const forbiddenPrefixes = ['.github/', 'benchmarks/', 'example/', 'tests/', 'cpp/tests/'];
for (const path of files) {
  const forbidden = forbiddenPrefixes.find((prefix) => path.startsWith(prefix));
  if (forbidden) throw new Error(`Published package leaks development path ${path}.`);
}

if (packageJson.name !== 'react-native-fast-video') {
  throw new Error('Unexpected package name.');
}
if (!/^0\.0\.\d+-alpha\.\d+$/.test(packageJson.version)) {
  throw new Error(`Alpha version is malformed: ${packageJson.version}`);
}
if (packageJson.repository?.url !== 'https://github.com/vivekjm/react-native-fast-video.git') {
  throw new Error('Repository URL drifted from the canonical repository.');
}
if (packageJson.exports?.['.']?.types !== './build/index.d.ts') {
  throw new Error('Package exports do not expose generated declarations.');
}
if ((readme.match(/^```mermaid$/gm) ?? []).length < 5) {
  throw new Error('README must retain all five architecture diagrams.');
}
if (!expoConfig.apple?.modules?.includes('ReactNativeFastVideoModule')) {
  throw new Error('Expo Apple module registration is missing.');
}
if (!expoConfig.android?.modules?.includes('com.vivekjm.fastvideo.ReactNativeFastVideoModule')) {
  throw new Error('Expo Android module registration is missing.');
}

console.log(
  `Package audit passed: ${packed.filename}, ${packed.entryCount} files, ${packed.size} bytes.`
);
