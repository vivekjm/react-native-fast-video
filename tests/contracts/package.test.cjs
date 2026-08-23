'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const root = path.resolve(__dirname, '../..');
const packageJson = JSON.parse(fs.readFileSync(path.join(root, 'package.json'), 'utf8'));
const expoConfig = JSON.parse(
  fs.readFileSync(path.join(root, 'expo-module.config.json'), 'utf8')
);

 test('generated package entry points exist', () => {
  assert.ok(fs.existsSync(path.join(root, packageJson.main)), packageJson.main);
  assert.ok(fs.existsSync(path.join(root, packageJson.types)), packageJson.types);
  assert.ok(fs.existsSync(path.join(root, 'plugin/build/withReactNativeFastVideo.js')));
});

test('exports map agrees with legacy package entry points', () => {
  assert.equal(packageJson.exports['.'].types, `./${packageJson.types}`);
  assert.equal(packageJson.exports['.'].default, `./${packageJson.main}`);
  assert.equal(packageJson.exports['.']['react-native'], `./${packageJson['react-native']}`);
});

test('Expo registration matches native module names', () => {
  assert.deepEqual(expoConfig.apple.modules, ['ReactNativeFastVideoModule']);
  assert.deepEqual(expoConfig.android.modules, [
    'com.vivekjm.fastvideo.ReactNativeFastVideoModule',
  ]);
});

test('published source contains both platform implementations and FastCore', () => {
  for (const required of [
    'android/src/main/java/com/vivekjm/fastvideo/ReactNativeFastVideoModule.kt',
    'ios/ReactNativeFastVideoModule.swift',
    'cpp/include/rnfv/c_api.h',
    'cpp/src/c_api.cpp',
  ]) {
    assert.ok(fs.existsSync(path.join(root, required)), required);
  }
});
