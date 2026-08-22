# Changelog

## 0.0.6-alpha.0 — Phase 5 predictive runtime

- Added stateful FastCore bandwidth forecasting with confidence and volatility.
- Phase 4 adaptive bitrate decisions now consume the native prediction instead of a single noisy bandwidth sample.
- Added velocity-aware viewport intent prediction and native preload reprioritization.
- Added health-ranked multi-CDN failover with origin-only diagnostics that do not expose URL paths or query credentials.
- Added Android Media3 frame-processing-offset aggregation in FastCore.
- Added predictive and physical-device benchmark gates; bundled fixtures are synthetic gate tests, not performance claims.
- Added Phase 5 runtime and completion documentation.

## 0.0.5-alpha.0

- Added shared C++ adaptive playback policy driven by bandwidth, rebuffers, frame drops, active-player count, network class, thermal pressure and low-power state.
- Added Android Media3 bitrate/resolution arbitration and Apple AVPlayer bitrate/resolution/buffer adaptation.
- Added `onAdaptiveDecision` plus native 0-100 QoE scoring in FastCore snapshots.
- Added durable Android offline downloads using DownloadManager/DownloadService with a separate non-evicting cache.
- Added background HLS VOD downloads on Apple using AVAssetDownloadURLSession.
- Added cross-platform offline list/pause/resume/remove APIs.
- Added Media3 MediaSessionService and Apple Now Playing/remote-command integration.
- Added background player ownership so media-session playback can survive React view teardown, plus explicit background-stop API.
- Added metadata/media-session source fields and Phase 4 benchmark/QoE tooling.

## 0.0.4-alpha.0

- Added Android LRU media disk cache with a configurable byte budget.
- Added Media3 disk-range preloading for second-nearest feed items.
- Isolated preload/player builders by latency profile and added native ExoPlayer pooling.
- Added AVPlayer pooling and startup-path telemetry on Apple.
- Added runtime configuration/stat APIs and cache clearing.
- Added cold-vs-warm TTFF comparison tooling.
- Fixed Phase 2 source normalization dropping fallback/retry/latency fields.

## 0.0.3-alpha.0

- Reuse Android ExoPlayer across source changes instead of reconstructing the native engine per feed cell.
- Add `focusFastVideoPreloads()` for viewport-driven native preload reprioritization and cancellation.
- Evict Apple warmed assets outside the active feed retention window.
- Add native retry with bounded exponential backoff.
- Add ordered CDN/source failover through `fallbackUris`.
- Add `maxRetryAttempts` and `retryBackoffMs` source controls.
- Document Phase 2 runtime behavior and validation boundaries.

## 0.0.2-alpha.0

- Upgrade Android Media3 baseline to 1.11.0.
- Add native feed/carousel preloading API.
- Add C++ FastCore preload ranking policy with deterministic tests.
- Add Android `DefaultPreloadManager` integration and preloaded MediaSource handoff.
- Add Apple `AVURLAsset` warming and retained-asset reuse.
- Add `preloadIndex`, `preloadFastVideoSources`, and `clearFastVideoPreloads` TypeScript APIs.
- Add Apple `maxBitrate` support through `AVPlayerItem.preferredPeakBitRate`.
- Add preload architecture documentation and example-app controls.

## 0.0.1-alpha.0

- Initial C++ FastCore, Android Media3, Apple AVFoundation, Expo Modules, DRM foundation, telemetry, and benchmark-gate foundation.
