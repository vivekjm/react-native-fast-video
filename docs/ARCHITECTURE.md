# Architecture

## 1. Principles

1. Playback must continue correctly when the JavaScript thread is busy.
2. Decoding and rendering stay on platform hardware paths.
3. No per-frame React state updates.
4. Commands cross the boundary; frames do not.
5. High-frequency observations are aggregated and coalesced natively.
6. Every premium capability is runtime-detected and stream-dependent.
7. Performance claims require repeatable results on named devices and media.

## 2. Layers

### TypeScript control plane

Responsibilities:

- normalize bundled and remote sources;
- expose typed props, callbacks and imperative commands;
- compose application-specific controls;
- provide hooks for state snapshots;
- never decode, schedule frames or run adaptive bitrate logic.

### Expo Modules boundary

The module exports a native view and view-bound async functions. View ownership matters: a player is created and released with its native view, avoiding a global registry and stale player IDs. Native events are throttled before entering JavaScript.

### Android engine

- Media3 `ExoPlayer` drives manifests, adaptation, MediaCodec and audio output.
- `SurfaceView` is the default render target for the efficient direct-composition path.
- `TextureView` is opt-in for transforms and clipping that require texture composition.
- `DefaultTrackSelector` handles language, resolution and bitrate constraints.
- `DefaultLoadControl` is rebuilt from FastCore buffer profiles.
- Analytics callbacks feed frame, bandwidth and startup observations to FastCore.

### Apple engine

- `AVPlayer` owns loading, adaptation, audio and time control.
- `AVPlayerLayer` is the default render path; no React view is updated per frame.
- HLS and Low-Latency HLS use the system stack.
- `AVAssetResourceLoaderDelegate` provides a FairPlay integration point.
- Access logs and KVO observations feed FastCore.
- `AVPictureInPictureController` and external playback remain native.

### C++20 FastCore

FastCore is platform-independent and intentionally codec-agnostic. It owns:

- legal state transitions;
- startup, seek, rebuffer and live-latency timers;
- rendered/dropped-frame counters;
- byte and throughput aggregation;
- buffer-policy profiles;
- monotonic sequence numbers;
- snapshot serialization;
- progress/metrics emission cadence.

The core is protected by a mutex because platform callbacks can arrive from different native queues. Time uses a monotonic clock to avoid wall-clock jumps.

## 3. State model

```text
idle → loading → ready → playing ↔ paused
                  │        │
                  └── buffering ──┘
playing/paused → ended
any non-released state → error
any state → released (terminal)
```

Startup buffering before the first rendered frame is not counted as a rebuffer. This prevents time-to-first-frame and stall metrics from double-counting the same delay.

## 4. Event strategy

Immediate events:

- load start;
- ready;
- first frame;
- error;
- ended;
- track list changes.

Coalesced events:

- position/buffer progress;
- live-edge distance;
- metric snapshots;
- bandwidth estimates.

The default interval is 250 ms and is clamped to a safe range. A 60 fps video therefore does not produce 60 bridge events per second.

## 5. Playback formats

- Android: progressive formats supported by Media3/device codecs, HLS, DASH and SmoothStreaming dependency-ready.
- Apple: progressive formats supported by AVFoundation and HLS/LL-HLS.
- DASH is not presented as native Apple support; applications should provide an HLS rendition for Apple platforms.

Container support never guarantees codec support. Runtime capability reporting and player errors are authoritative.

## 6. DRM

- Android: Widevine through `MediaItem.DrmConfiguration`.
- Apple: FairPlay Streaming through a resource-loader delegate.

DRM is deployment-specific. License headers, certificate flow, content-ID extraction and license response encoding vary by provider. The library exposes native integration primitives but cannot guarantee a provider works without provider fixtures and device tests.

## 7. 4K and HDR

The package does not force 4K or HDR. It reports decoder/display capability, lets adaptive streaming select a compatible rendition, and allows applications to set bitrate/resolution ceilings. Actual playback depends on device silicon, display, OS, codec profile, DRM security level, thermal state and stream encoding.

## 8. Threading

- JS: API calls and UI only.
- Android main looper: player commands and view attachment.
- Media3 internal threads: loading, codec and rendering.
- Apple main queue: AVPlayer/view mutations.
- URLSession/resource-loader queues: network/DRM.
- FastCore: short lock-protected accounting operations; no blocking I/O.

## 9. Memory policy

FastCore exposes profiles rather than a single magical buffer size:

- `lowLatency`: small live buffer and aggressive live correction;
- `balanced`: default startup/stability compromise;
- `quality`: larger buffer for unreliable networks and high bitrates;
- `memorySaver`: constrained buffering for feeds and multi-player screens.

Future preloading and cache layers must use explicit byte budgets and LRU eviction.

## 10. Failure isolation

Native errors are normalized into stable codes while preserving platform details. A failed player is releasable and cannot leave timers running. The C++ released state is terminal, preventing late callbacks from resurrecting a disposed session.

## 8. Predictive control loop (Phase 5)

FastCore now distinguishes a noisy instantaneous bandwidth sample from a usable forecast. The session stores an EWMA prediction, volatility, sample count, and confidence. Platform ABR only consumes the forecast after confidence reaches the minimum threshold; otherwise it falls back to the native estimate.

Feed preloading accepts viewport velocity. C++ predicts a likely destination index and asymmetric forward/backward pressure. The real playing index remains authoritative while preload work is biased toward the prediction.

Multi-CDN health is intentionally origin-scoped. Paths, query strings, signed tokens, and cookies are never exported through diagnostics. Native runtimes record first-frame/failure observations and rank caller-provided fallbacks using FastCore's deterministic health score.

Renderer diagnostics remain capability-based. Android exposes Media3 frame-processing offsets and FastCore aggregates them. Apple does not fabricate an equivalent signal where AVFoundation does not expose one.
