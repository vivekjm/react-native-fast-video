# Roadmap

The original implementation sequence lives in [`docs/IMPLEMENTATION_PLAN.md`](docs/IMPLEMENTATION_PLAN.md). Phase-specific architecture and evidence requirements are documented separately so feature status is not confused with certification status.

## Completed foundation

### Phase 1 — native vertical slice

- Shared C++20 FastCore state, timing, buffer policy, and metrics.
- Android Media3/ExoPlayer playback and Apple AVPlayer/AVPlayerLayer playback.
- React Native/Expo module, typed TypeScript API, example app, and basic benchmark gates.

### Phase 2 — feed runtime hardening

- Native feed/carousel preloading.
- Player reuse across source changes.
- Viewport-driven reprioritization and bounded native retry/CDN fallback.

See [`docs/PHASE2_RUNTIME.md`](docs/PHASE2_RUNTIME.md) and [`docs/PRELOADING.md`](docs/PRELOADING.md).

### Phase 3 — cache and pooled startup

- Android byte-budgeted transient LRU cache and disk-range preloading.
- Latency-profile-isolated Media3 runtimes and ExoPlayer pools.
- AVPlayer pooling and AVURLAsset warm reuse.
- Cold/warm startup classification and runtime statistics.

See [`docs/PHASE3_RUNTIME.md`](docs/PHASE3_RUNTIME.md).

### Phase 4 — native playback intelligence

- Shared C++ network/thermal/resource-aware playback policy.
- Cross-platform bitrate, resolution, and buffer decisions.
- Active-player bandwidth arbitration and QoE scoring.
- Clear-content durable offline downloads.
- Media sessions, system controls, and background ownership.

See [`docs/PHASE4_PLAN.md`](docs/PHASE4_PLAN.md) and [`docs/PHASE4_RUNTIME.md`](docs/PHASE4_RUNTIME.md).

### Phase 5 — predictive runtime and diagnostics

- Stateful native bandwidth prediction with confidence/volatility.
- Velocity-aware viewport intent prediction.
- Health-ranked multi-CDN failover.
- Native frame-pipeline diagnostics.
- Predictive/device benchmark result contracts.

See [`docs/PHASE5_PLAN.md`](docs/PHASE5_PLAN.md) and [`docs/PHASE5_RUNTIME.md`](docs/PHASE5_RUNTIME.md).

### Phase 1–5 hardening gate

Phase 6 implementation depends on merging and certifying the active Phase 1–5 hardening work. It closes packaging, TypeScript/web, lifecycle, offline, C++ edge-case, Android, Apple, and CI gaps. Phase 6 branches must start from the merged hardening baseline rather than copying unmerged code.

## Phase 6 — certified advanced media

**Current status: architecture and certification planning; runtime implementation intentionally deferred.**

Phase 6 is governed by six documents that must be reviewed together:

1. [`docs/PHASE6_MASTER_PLAN.md`](docs/PHASE6_MASTER_PLAN.md) — architecture, workstreams, dependencies, gates, and definition of done.
2. [`docs/PHASE6_API_PROPOSAL.md`](docs/PHASE6_API_PROPOSAL.md) — proposed offline DRM, remote playback, decoder, and certification APIs.
3. [`docs/PHASE6_CERTIFICATION_MATRIX.md`](docs/PHASE6_CERTIFICATION_MATRIX.md) — fixtures, devices, scenarios, statistics, competitors, and claim rules.
4. [`docs/PHASE6_THREAT_MODEL.md`](docs/PHASE6_THREAT_MODEL.md) — key boundaries, storage, account policy, Cast, telemetry, and supply-chain threats.
5. [`docs/PHASE6_DECISION_REGISTER.md`](docs/PHASE6_DECISION_REGISTER.md) — accepted principles and open decisions that cannot be hidden inside implementation.
6. [`docs/PHASE6_IMPLEMENTATION_BACKLOG.md`](docs/PHASE6_IMPLEMENTATION_BACKLOG.md) — PR-sized work packages and dependency graph.

### Phase 6 workstreams

#### A. Secure offline DRM

- [ ] Provider-neutral native credential/license adapter contract.
- [ ] Widevine acquire, query, renew, release, and offline restore.
- [ ] FairPlay persistable-key acquire, update, renew, invalidate, and offline restore.
- [ ] One durable media/license transaction with compensation and process-death reconciliation.
- [ ] Account/logout/reinstall/backup policy and encrypted native storage.
- [ ] Deterministic and real-provider certification fixtures.

#### B. Codec and decoder intelligence

- [ ] Normalized codec/pipeline inventory and privacy-safe evidence.
- [ ] Android exact-profile `MediaCodecSelector` experiments with fallback.
- [ ] Signed, expiring, rollback-safe device profiles.
- [ ] Apple public capability/outcome telemetry without unsupported decoder pinning claims.
- [ ] Secure, HDR, concurrent-player, power, and thermal certification.

#### C. Remote playback

- [ ] Route-neutral single-owner transfer state machine.
- [ ] First-class AirPlay route picker, availability, and active-route events.
- [ ] Optional Google Cast sender packaging with zero dependency when disabled.
- [ ] Android/iOS Cast session, queue, tracks, live DVR, reconnect, and system controls.
- [ ] Application-owned Custom Web Receiver DRM/authorization contract.

#### D. Physical-device certification lab

- [ ] Versioned clear/live/HDR/DRM/track/error fixture manifest.
- [ ] Deterministic network and provider fault injection.
- [ ] Android instrumentation, Macrobenchmark, Perfetto, and controlled power runs.
- [ ] Apple XCTest performance/signpost and physical FairPlay/AirPlay/HDR runs.
- [ ] Fair competitor adapters and predeclared statistical methodology.

#### E. Evidence and release integrity

- [ ] Versioned raw/normalized result schema.
- [ ] Environment, source, build, fixture, and device fingerprints.
- [ ] Reproducible report generator and claim-policy gate.
- [ ] SHA-256 manifest, SBOM, provenance attestations, and independent verification.
- [ ] Capability labels: implemented, integration-tested, device-certified, provider-certified, experimental, device-dependent, unsupported.

### Phase 6 beta gate

A `0.1.0-beta.x` release is considered only after the declared beta subset has:

- secure/restart-safe lifecycle behavior;
- physical-device and real-provider evidence where applicable;
- clear rollback/kill switches;
- no raw DRM material in JavaScript, logs, traces, or artifacts;
- published raw evidence and attested release assets;
- precise documentation that avoids unsupported universal performance claims.

## Beyond Phase 6

Potential later work—not implicitly included in Phase 6—includes advertising, editing/transcoding, advanced rendering/effects, server-side packaging, broader tvOS/Android TV product APIs, and any aggregate “fastest player” claim framework not separately reviewed.
