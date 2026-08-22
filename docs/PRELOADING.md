# Native preloading

`react-native-fast-video` keeps preload decisions out of JavaScript. The public API only supplies the candidate list and focused index; native runtimes execute the plan.

## Public API

```ts
import { preloadFastVideoSources, clearFastVideoPreloads } from 'react-native-fast-video';

await preloadFastVideoSources(
  feed.map((source, preloadIndex) => ({ ...source, preloadIndex })),
  focusedIndex
);

// When the feed is dismissed:
await clearFastVideoPreloads();
```

Each `<FastVideo />` source that belongs to the same feed should carry the same `preloadIndex` used when the list was registered.

## C++ policy

FastCore owns the deterministic distance policy:

| Distance from focused item | Target |
| ---: | --- |
| ±1 | Load 3 seconds |
| ±2 | Select tracks |
| ±3…±4 | Prepare source/manifest |
| >4 | Do not preload |

The policy is deliberately small and benchmarkable. It can evolve independently from the React API.

## Android

Android uses Media3 `DefaultPreloadManager`. Players that consume preloaded sources are created from the same native builder as the preload manager, which is a Media3 requirement. The runtime reprioritizes work when the active `preloadIndex` changes.

For this first implementation, Media3 memory preloading accepts sources without per-source headers, DRM, or side-loaded subtitles. Those sources still play normally, but bypass the shared preload path until the request stack is unified.

## Apple

Apple retains warmed `AVURLAsset` objects and triggers asynchronous property loading for playable state, tracks, and duration. When a matching source becomes active, the engine reuses that retained asset rather than constructing a fresh one.

This is intentionally described as asset warming, not a guaranteed segment cache. AVFoundation ultimately controls how network and media data are cached.

## Web

Web performs lightweight origin preconnect hints only. Browser media buffering policy remains browser-owned.

## Benchmark requirement

Preloading is useful only if it lowers time-to-first-frame without unacceptable memory/network cost. Device runs must compare:

- cold TTFF vs preloaded TTFF;
- bytes fetched for watched vs skipped items;
- memory held by 1, 3, 5, and 9 candidate windows;
- thermal behavior during rapid feed scrolling;
- decoder churn and surface reattachment cost.


## Phase 3 tiering

Android Media3 1.11 uses four distance tiers: distance 1 loads 3 seconds into memory, distance 2 caches 6 seconds to the LRU disk cache, distance 3 selects tracks, and distance 4 prepares the source. This keeps the next swipe instant without multiplying RAM use across several feed items. Apple mirrors the intent with staged AVURLAsset warming because AVFoundation does not expose Media3-style disk range preloading.
