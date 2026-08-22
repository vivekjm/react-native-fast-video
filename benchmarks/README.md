# Benchmark Lab

The benchmark directory defines a portable result schema and performance budgets. The sample result is synthetic and exists only to test the gate.

A real device runner should write JSON with:

- device model and OS build;
- app and library commit SHA;
- media fixture ID/hash;
- network profile and cache state;
- cold/warm classification;
- sample count;
- TTFF p50/p95;
- seek p95;
- rebuffer and dropped-frame ratios;
- live-offset p95;
- native-to-JS event rate;
- memory/CPU/energy traces as attached artifacts.

Do not compare players with different render surfaces, event intervals, DRM levels or buffer modes.


## Cold vs warm startup

Capture the same fixture/device/network profile twice with explicit `cacheState` metadata and compare with `compare-startup.mjs`. `onFirstFrame` exposes FastCore TTFF plus the native startup path so the capture does not require a JS stopwatch.
