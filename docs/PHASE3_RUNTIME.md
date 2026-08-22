# Phase 3: cache, pooling, and startup measurement

Phase 3 attacks repeated startup cost in feed/carousel playback.

## Android

- Media3 runtimes are isolated by latency profile so shared `LoadControl` state never leaks between low-latency and quality players.
- Each latency runtime owns a small reusable ExoPlayer pool.
- A process-wide `SimpleCache` uses an LRU byte budget (256 MiB by default).
- Media3 preload rank 1 loads three seconds into memory.
- Rank 2 caches six seconds to disk instead of consuming another player-sized memory buffer.
- Rank 3 selects tracks and rank 4 prepares the source/manifest.
- Playback data sources read through the same cache, including custom HTTP headers.
- Runtime/cache statistics are exposed to TypeScript.

Configure the disk budget before any player or preload call. Once Media3 has constructed the cache/preload runtime, changing the byte limit requires a runtime restart; the API reports this instead of releasing a cache underneath an active player.

## Apple

- `AVPlayer` objects are pooled after observers and current items are detached.
- Warmed `AVURLAsset` objects continue to provide feed startup reuse.
- Apple does not expose a safe public AVPlayer disk-cache byte budget comparable to Media3 `SimpleCache`, so the API reports `cacheBudgetControllable: false` rather than pretending `URLCache` controls HLS/AVPlayer media caching.

## Startup-path telemetry

`onFirstFrame` and `getSnapshot()` now identify the startup path. Current values include:

- `cold` / `disk-cache`
- `memory-preloaded`
- `asset-warmed`

`onFirstFrame` also returns the C++ FastCore TTFF measurement, allowing the benchmark runner to compare cold and warmed sessions without JS stopwatch noise.

## Benchmark workflow

Run the normal budget gate on cold and warm captures, then compare startup directly:

```sh
node benchmarks/gate.mjs cold.json
node benchmarks/gate.mjs warm.json
node benchmarks/compare-startup.mjs cold.json warm.json
```

Synthetic cold/warm files are committed only to validate the comparison tooling. They are not product benchmark claims.
