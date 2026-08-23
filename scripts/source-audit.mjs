import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(fileURLToPath(new URL('..', import.meta.url)));
const read = (path) => readFileSync(join(root, path), 'utf8');
const packageJson = JSON.parse(read('package.json'));
const readme = read('README.md');
const tsView = read('src/FastVideo.tsx');
const webView = read('src/FastVideo.web.tsx');
const kotlinModule = read(
  'android/src/main/java/com/vivekjm/fastvideo/ReactNativeFastVideoModule.kt'
);
const swiftModule = read('ios/ReactNativeFastVideoModule.swift');
const kotlinRecords = read(
  'android/src/main/java/com/vivekjm/fastvideo/FastVideoRecords.kt'
);
const swiftRecords = read('ios/FastVideoRecords.swift');

const requiredPaths = [
  'src/FastVideo.tsx',
  'src/FastVideo.web.tsx',
  'src/FastVideo.types.ts',
  'src/normalizeSource.ts',
  'android/src/main/java/com/vivekjm/fastvideo/FastVideoEngine.kt',
  'android/src/main/java/com/vivekjm/fastvideo/FastVideoDownloadRuntime.kt',
  'android/src/main/java/com/vivekjm/fastvideo/FastVideoPreloadRuntime.kt',
  'ios/FastVideoEngine.swift',
  'ios/FastVideoOfflineRuntime.swift',
  'ios/FastVideoPreloader.swift',
  'cpp/include/rnfv/c_api.h',
  'cpp/src/c_api.cpp',
  'cpp/tests/hardening_tests.cpp',
  'benchmarks/device-gate.mjs',
  '.github/workflows/ci.yml',
];
for (const path of requiredPaths) {
  try {
    statSync(join(root, path));
  } catch {
    throw new Error(`Required source path is missing: ${path}`);
  }
}

if (packageJson.name !== 'react-native-fast-video') {
  throw new Error('Package name drifted from react-native-fast-video.');
}
if (!packageJson.version.startsWith('0.0.')) {
  throw new Error(`Unexpected pre-1.0 version: ${packageJson.version}`);
}
if (packageJson.repository?.url !== 'https://github.com/vivekjm/react-native-fast-video.git') {
  throw new Error('Canonical GitHub repository URL is incorrect.');
}
if ((readme.match(/^```mermaid$/gm) ?? []).length < 5) {
  throw new Error('README must contain all five architecture diagrams.');
}

const sharedProps = [
  'source',
  'autoplay',
  'paused',
  'muted',
  'volume',
  'rate',
  'repeat',
  'latencyMode',
  'progressIntervalMs',
  'surfaceType',
  'contentFit',
  'maxBitrate',
  'preferredAudioLanguage',
  'preferredTextLanguage',
  'allowsExternalPlayback',
];
for (const prop of sharedProps) {
  if (!tsView.includes(`${prop}=`)) throw new Error(`React view does not forward ${prop}.`);
  if (!kotlinModule.includes(`Prop("${prop}")`)) {
    throw new Error(`Android module is missing shared prop ${prop}.`);
  }
  if (!swiftModule.includes(`Prop("${prop}")`)) {
    throw new Error(`Apple module is missing shared prop ${prop}.`);
  }
}

const sharedEvents = [
  'onLoadStart',
  'onReady',
  'onPlaybackStateChange',
  'onBuffer',
  'onFirstFrame',
  'onProgress',
  'onMetrics',
  'onAdaptiveDecision',
  'onTracksChanged',
  'onVideoSize',
  'onEnd',
  'onError',
  'onPictureInPictureChange',
];
for (const event of sharedEvents) {
  if (!kotlinModule.includes(`"${event}"`) || !swiftModule.includes(`"${event}"`)) {
    throw new Error(`Native event parity is missing ${event}.`);
  }
}

const androidSourceFields = recordFields(
  kotlinRecords,
  /class FastVideoSource\s*:\s*Record\s*\{([\s\S]*?)\n\}/
);
const appleSourceFields = recordFields(
  swiftRecords,
  /struct FastVideoSource\s*:\s*Record\s*\{([\s\S]*?)\n\}/
);
for (const field of new Set([...androidSourceFields, ...appleSourceFields])) {
  if (!androidSourceFields.has(field) || !appleSourceFields.has(field)) {
    throw new Error(`FastVideoSource native-record parity drifted at field: ${field}`);
  }
}

if (!tsView.includes('requireNativeViewManager')) {
  throw new Error('React view is not using the supported Expo native view manager API.');
}
if (/onEnterPictureInPicture\s*=/.test(webView)) {
  throw new Error('Browser PiP events must use DOM listeners, not unsupported React JSX props.');
}
if (!read('android/src/main/java/com/vivekjm/fastvideo/FastVideoDownloadRuntime.kt').includes(
  'Offline DRM license persistence is a Phase 6 capability'
)) {
  throw new Error('Android offline DRM boundary is not explicit.');
}
if (!read('ios/FastVideoOfflineRuntime.swift').includes(
  'Offline FairPlay license persistence is reserved for Phase 6'
)) {
  throw new Error('Apple offline DRM boundary is not explicit.');
}

const banned = [
  ['reactnative-fast-video', 'old repository slug'],
  ['paste.rs/', 'temporary external publication transport'],
  ['requireNativeView<', 'removed Expo native-view API'],
  ['.bootstrap-bundle', 'temporary repository import bundle'],
  ['.fast-export-v1', 'temporary repository import bundle'],
];
for (const file of sourceFiles(root)) {
  const path = relative(root, file);
  if (path === 'scripts/source-audit.mjs') continue;
  const content = readFileSync(file, 'utf8');
  for (const [needle, description] of banned) {
    if (content.includes(needle)) throw new Error(`${path} contains ${description}.`);
  }
}

console.log(
  `Source audit passed for ${packageJson.name}@${packageJson.version}; ` +
    `${androidSourceFields.size} native source fields are aligned.`
);

function recordFields(content, blockPattern) {
  const block = content.match(blockPattern)?.[1];
  if (!block) throw new Error(`Unable to locate native FastVideoSource record using ${blockPattern}.`);
  return new Set(
    [...block.matchAll(/@Field\s+var\s+(\w+)/g)].map((match) => match[1])
  );
}

function sourceFiles(directory) {
  const output = [];
  for (const name of readdirSync(directory)) {
    if (['.git', 'node_modules', 'build', 'Pods', '.cxx'].includes(name)) continue;
    const path = join(directory, name);
    const stat = statSync(path);
    if (stat.isDirectory()) output.push(...sourceFiles(path));
    else if (/\.(?:c|cc|cpp|h|hpp|js|mjs|json|kt|md|mm|swift|ts|tsx|yml)$/.test(name)) {
      output.push(path);
    }
  }
  return output;
}
