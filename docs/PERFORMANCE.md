# Performance and Benchmarking

## No benchmark theater

“Fastest” is not a source-code property. It must be demonstrated on real devices with controlled media, network conditions, thermal state and comparable feature settings. This repository therefore ships budgets and a result gate before it ships a leaderboard.

## Core metrics

- **TTFF**: load request to first rendered frame.
- **Seek latency**: seek request to the first frame at/after the target.
- **Rebuffer ratio**: post-startup buffering time divided by active playback time.
- **Dropped-frame ratio**: dropped divided by rendered plus dropped frames.
- **Live offset**: current distance from the live edge.
- **Bridge event rate**: native-to-JS events per second.
- **Memory delta**: process memory increase from baseline.
- **CPU and energy**: sampled during steady playback.

Startup buffering is excluded from rebuffer metrics and measured as TTFF.

## Initial budgets

Budgets are stored in `benchmarks/budgets.json`. They are targets for a controlled reference suite, not universal promises. Network scenarios have separate thresholds from local-file scenarios.

## Running the gate

```bash
node benchmarks/gate.mjs benchmarks/results/sample.json
```

A real result file must include device, OS, build SHA, media fixture ID, scenario, samples and metrics. The gate fails on missing metadata or exceeded thresholds.

## Required comparison protocol

1. Same physical device and OS build.
2. Same media URL/cache state and network shaping.
3. Same surface type, controls and progress-event interval.
4. Same DRM/security level when comparing protected content.
5. Cold and warm runs reported separately.
6. At least 20 runs for latency percentiles.
7. Median, p95 and confidence interval—not only the best run.
8. Raw JSON committed or attached to a release.
9. Thermal state recorded before and after long runs.
10. Competitor versions and configuration recorded exactly.

## Optimization priorities

1. Avoid unnecessary texture composition.
2. Avoid per-frame bridge traffic.
3. Reuse platform ABR and hardware codec paths.
4. Bound buffers and caches by bytes.
5. Cancel offscreen/feed work immediately.
6. Prefer measurement to speculative micro-optimization.
