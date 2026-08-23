'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');
const Module = require('node:module');

const originalLoad = Module._load;
Module._load = function patchedLoad(request, parent, isMain) {
  if (request === 'react-native') {
    return {
      Image: {
        resolveAssetSource(value) {
          return typeof value === 'number' ? { uri: `asset://bundle/${value}` } : value;
        },
      },
    };
  }
  return originalLoad.call(this, request, parent, isMain);
};

const { normalizeFastVideoSource } = require('../../build/normalizeSource.js');

 test('normalizes a simple URI and infers HLS', () => {
  const result = normalizeFastVideoSource('https://media.example/video/master.m3u8?token=secret');
  assert.equal(result.nativeSource.uri, 'https://media.example/video/master.m3u8?token=secret');
  assert.equal(result.nativeSource.type, 'hls');
  assert.equal(result.nativeSource.latencyMode, 'balanced');
  assert.deepEqual(result.nativeSource.headers, {});
});

test('resolves bundled assets and clamps retry policy', () => {
  const result = normalizeFastVideoSource({
    uri: 42,
    maxRetryAttempts: 100,
    retryBackoffMs: 1,
  });
  assert.equal(result.nativeSource.uri, 'asset://bundle/42');
  assert.equal(result.nativeSource.maxRetryAttempts, 8);
  assert.equal(result.nativeSource.retryBackoffMs, 50);
});

test('deduplicates the primary and fallback URIs', () => {
  const result = normalizeFastVideoSource({
    uri: 'https://a.example/video.m3u8',
    fallbackUris: [
      'https://a.example/video.m3u8',
      'https://b.example/video.m3u8',
      'https://b.example/video.m3u8',
    ],
  });
  assert.deepEqual(result.nativeSource.fallbackUris, ['https://b.example/video.m3u8']);
});

test('preserves the closed metadata shape', () => {
  const result = normalizeFastVideoSource({
    uri: 'https://media.example/video.mp4',
    metadata: { title: 'Episode 1', artist: 'Example', ignored: 'not forwarded' },
  });
  assert.deepEqual(result.nativeSource.metadata, {
    title: 'Episode 1',
    artist: 'Example',
    albumTitle: undefined,
    artworkUri: undefined,
  });
});

test('rejects header injection', () => {
  assert.throws(
    () =>
      normalizeFastVideoSource({
        uri: 'https://media.example/video.mp4',
        headers: { Authorization: 'Bearer valid\r\nX-Injected: yes' },
      }),
    /newline/
  );
});

test('rejects unsafe URI schemes', () => {
  assert.throws(() => normalizeFastVideoSource('javascript:alert(1)'), /unsafe URI scheme/);
});

test('rejects live playback through an offline identifier', () => {
  assert.throws(
    () =>
      normalizeFastVideoSource({
        uri: 'https://media.example/live.m3u8',
        isLive: true,
        offlineId: 'live-copy',
      }),
    /live source cannot be opened through offlineId/
  );
});
