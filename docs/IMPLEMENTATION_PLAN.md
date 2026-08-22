# Implementation Plan

## Phase 0 — measurable foundation

- [x] Publish architecture, feature truth table and performance budgets.
- [x] Create C++20 state/metrics core with deterministic tests.
- [x] Define one cross-platform TypeScript contract.
- [x] Add an Expo Modules native view and config plugin.
- [x] Add benchmark result schema and gate.

Exit condition: core tests and TypeScript build pass; no unqualified “fastest” claim.

## Phase 1 — native playback vertical slice

- [x] Progressive playback on Android and Apple.
- [x] HLS on Android and Apple.
- [x] DASH on Android.
- [x] Hardware render surfaces.
- [x] Play/pause/seek/rate/volume/mute/repeat.
- [x] First-frame, progress, buffer, end and error events.
- [x] Track discovery and language/track selection.
- [x] Live detection, live offset and go-to-live.
- [x] Native telemetry feeding FastCore.

Exit condition: sample streams play in the example development build on physical Android and iOS devices.

## Phase 2 — streaming hardening

- [ ] ABR constraint tests across bandwidth changes.
- [ ] LL-HLS and low-latency DASH fixture matrix.
- [ ] Request retry/backoff and CDN failover policy.
- [ ] Custom manifest/segment request hooks without JS on the hot path.
- [ ] Gap, discontinuity and timestamp-reset fixtures.
- [ ] Background audio/media-session behavior.

## Phase 3 — protected media

- [x] Widevine configuration surface.
- [x] FairPlay resource-loader foundation.
- [ ] Provider test harnesses and reference adapters.
- [ ] Offline licenses.
- [ ] License renewal and expiration events.
- [ ] HDCP/external-playback policy controls.

## Phase 4 — feed and preload performance

- [ ] Native player pool with strict ownership.
- [x] Warm manifest/first-segment preload foundation (Media3 memory preload; Apple AVURLAsset warming).
- [ ] Surface handoff without decoder churn where supported.
- [~] Native distance-based priority is implemented; automatic viewport ownership/cancellation is next.
- [ ] Byte-budgeted memory/disk cache.
- [ ] Multi-player stress benchmarks.

## Phase 5 — playback experience

- [x] Picture-in-Picture entry points.
- [x] Apple external playback/AirPlay setting.
- [ ] Android MediaSession and notification service.
- [ ] Native fullscreen host.
- [ ] Cast integration as an optional native package.
- [ ] Thumbnail/sprite preview extraction.
- [ ] Chapter metadata and timed metadata.
- [ ] Spatial audio and advanced audio-route events.

## Phase 6 — offline and ads

- [ ] Native download manager for HLS/DASH/progressive media.
- [ ] Download selection, pause/resume, integrity and eviction.
- [ ] Client-side IMA adapter as an optional package.
- [ ] Server-side ad marker/timed-metadata APIs.

## Phase 7 — verified optimization

- [ ] Device lab: low/mid/high Android and multiple iPhone generations.
- [ ] 720p, 1080p, 4K, SDR, HDR10, HLG and Dolby Vision fixtures where licensed.
- [ ] Thermal, battery and memory profiling over long playback.
- [ ] Side-by-side runs against current maintained alternatives.
- [ ] Publish raw results, harness version, media hashes and confidence intervals.

Only after this phase may the README make comparative performance claims.
