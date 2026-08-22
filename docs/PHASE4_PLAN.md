# Phase 4 — Native Playback Intelligence

Phase 4 turns react-native-fast-video from a fast native wrapper into a resource-aware media runtime. The rule is simple: decisions that affect decode, buffering, bandwidth, background ownership, or durable media stay native. TypeScript exposes intent and diagnostics only.

## Release gates

Phase 4 is complete when all five tracks below are implemented behind one public API and the portable validation suite passes. Physical-device certification remains a separate release gate because Android/iOS hardware, thermals, HDR panels and network radios cannot be emulated faithfully in host CI.

## Track A — Adaptive playback intelligence

- Shared C++ adaptive policy fed by native bandwidth estimates, rebuffer ratio, dropped-frame ratio, active-player count, network class, thermal pressure and low-power state.
- Native policy modes: `off`, `conservative`, `balanced`, `aggressive`.
- Per-player fair-share bandwidth caps so background/preloaded players cannot starve the focused player.
- Resolution and HDR pressure caps under constrained networks, thermal stress, low-power mode or repeated frame drops.
- Forward-buffer targets derived from network class and playback health.
- Android maps decisions to Media3 track selection constraints.
- Apple maps decisions to AVPlayerItem peak bitrate, maximum resolution and forward-buffer duration.
- Every material policy change is observable through `onAdaptiveDecision`.

## Track B — Resource arbitration and lifecycle ownership

- Track active native player count and feed it into the shared policy.
- Preserve latency-profile-specific player pools rather than mixing incompatible load-control policies.
- Keep feed preloading and durable downloads on separate storage/lifetime domains.
- Media-session-enabled playback may outlive its React view.
- Android hands a still-playing player to Media3 MediaSessionService on view teardown.
- Apple retains the active AVPlayer behind MPRemoteCommandCenter/Now Playing after view teardown.
- Explicit `stopFastVideoBackgroundPlayback()` terminates retained background playback.

## Track C — Durable offline media

- Android uses Media3 DownloadManager/DownloadService and a non-evicting offline SimpleCache separate from the feed LRU cache.
- Persistent download index, retry policy, bounded parallelism, pause/resume/remove/list APIs and foreground service ownership.
- HLS/DASH/SmoothStreaming/progressive support on Android through Media3 downloader selection.
- Apple uses AVAssetDownloadURLSession background HLS VOD downloads and persists the system-provided asset URL.
- Download state survives React component and module lifetime.
- Feed cache clearing must never remove explicitly downloaded media.
- Offline DRM license persistence is intentionally not advertised until license-renewal/revocation fixtures exist.

## Track D — QoE observability and benchmark contract

- FastCore emits a normalized 0–100 QoE score from TTFF, rebuffers and frame drops.
- Startup path remains explicit (`cold`, `disk-cache`, `memory-preloaded`, `asset-warmed`).
- Runtime stats expose adaptive state, network class, thermal/low-power state, pool counts and offline counts.
- Benchmark result schema records device, OS, fixture, cache state, network profile, thermal state and native QoE.
- Synthetic fixtures only validate benchmark tooling; performance claims require physical-device result artifacts.

## Track E — Expo and production integration

- Expo config plugin can enable background playback permissions/modes and PiP.
- Android manifest declares media playback and data-sync foreground services.
- Public TS API remains thin and cross-platform.
- Native/source normalizers carry metadata, media-session intent, fallback/retry and adaptive inputs end to end.
- Source audit rejects unverified superlative performance claims.

## Explicit non-goals for this release

- A custom software decoder replacing MediaCodec/VideoToolbox.
- Offline FairPlay/Widevine license persistence without provider fixtures.
- Claiming benchmark leadership from synthetic data.
- Web durable download management.
