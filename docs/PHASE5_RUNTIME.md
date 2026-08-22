# Phase 5 runtime

## Predictive bandwidth

FastCore keeps a smoothed bandwidth estimate, sample count, volatility, and confidence. Large sample changes raise the EWMA adaptation rate so the predictor reacts to genuine network transitions while smaller fluctuations are filtered. Android Media3 and Apple AVFoundation observations feed the same core model. Phase 4 ABR now consumes `predictedBandwidthBps` when available.

## Viewport intent

`focusFastVideoPreloads(index, velocityItemsPerSecond)` sends scroll velocity directly to native. FastCore predicts a future index and asymmetric preload radii. Android moves Media3 preload pressure toward that predicted index while retaining the real playing index; Apple retains/warm-evicts assets around the predicted destination.

## CDN health

Every candidate URI is reduced to a safe origin key (`scheme://host[:port]`). Native runtimes track success/failure streaks and moving TTFF/response observations. FastCore produces a 0–100 health score. Initial and fallback candidates are ranked by score while preserving caller order for ties.

## Frame diagnostics

Android Media3 `onVideoFrameProcessingOffset` feeds average processing offset and sample count into FastCore. Dropped-frame observations remain separate. Apple exposes dropped frames through access logs but does not provide the same processing-offset signal, so unsupported fields remain zero instead of being fabricated.

## Public additions

- `predictedBandwidthBps`
- `bandwidthConfidence`
- `bandwidthVolatility`
- `bandwidthSamples`
- `averageFrameProcessingOffsetUs`
- `frameProcessingSamples`
- `FastVideoCdnDiagnostics`
- `FastVideoViewportIntent`
- velocity-aware `focusFastVideoPreloads`

## Deterministic benchmark resets

`resetFastVideoNetworkDiagnostics()` clears process-local CDN health history so A/B benchmark runs can start from the same network-history state. It does not clear media caches or durable downloads.
