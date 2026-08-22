# Phase 2 Runtime Hardening

Phase 2 targets feed-scale playback where source switches are frequent and JavaScript must stay out of recovery and preload scheduling.

## Native player reuse

Android no longer destroys and reconstructs ExoPlayer on every source prop change. A `FastVideoView` retains its engine when the latency profile is unchanged and replaces media on the existing player. This preserves renderer setup, bandwidth history, Media3 preload-manager affinity and platform codec reuse opportunities. A latency-mode change still recreates the engine because load-control configuration is constructor-time state.

Apple already retained one `AVPlayer` per view; source changes continue to replace only the current `AVPlayerItem`.

## Viewport-driven preload focus

`focusFastVideoPreloads(index)` updates native preload priority without rebuilding the source list. Android updates `DefaultPreloadManager`'s current-playing index and invalidates its plan. Apple removes retained warmed assets farther than four feed positions from the focused index.

Typical feed integration:

```ts
await preloadFastVideoSources(feed, initialIndex);

function onViewableIndexChanged(index: number) {
  void focusFastVideoPreloads(index);
}
```

## Native retry and CDN failover

Each source can include native recovery policy:

```ts
{
  uri: primary,
  fallbackUris: [secondary, tertiary],
  maxRetryAttempts: 2,
  retryBackoffMs: 350,
}
```

The native engine retries the active URI using bounded exponential backoff. After its retry budget is exhausted it advances to the next distinct fallback URI. React is not remounted and no JS recovery loop is required. `onError` is emitted only after all native candidates are exhausted.

## Validation boundary

Portable C++ tests, benchmark smoke gates, source audit, Podspec syntax, Swift parsing and diff validation run in the host environment. Full Gradle/Android SDK and Xcode device builds remain device/CI gates.
