# Roadmap

The detailed, test-gated plan lives in [`docs/IMPLEMENTATION_PLAN.md`](docs/IMPLEMENTATION_PLAN.md).

Priorities:

1. Prove the native vertical slice on physical devices.
2. Publish reproducible baseline benchmarks.
3. Harden ABR/live/DRM behavior with fixtures.
4. Extend retained-player/preload focus into a byte-budgeted disk cache and multi-player pool for feeds.
5. Add offline, media-session, cast and ads as optional native subsystems.


## Phase 3 — cache and pooled startup (implemented in 0.0.4-alpha.0)

- Android byte-budgeted LRU media cache and disk-range preloading.
- Latency-profile-isolated Media3 runtimes and ExoPlayer pooling.
- AVPlayer pooling and AVURLAsset warm reuse on Apple.
- Runtime/cache statistics and cold-vs-warm TTFF tooling.


## Phase 4 — native playback intelligence (implemented in 0.0.5-alpha.0)

- Shared C++ network/thermal/resource-aware playback policy.
- Cross-platform adaptive bitrate, resolution and buffer decisions.
- Active-player bandwidth arbitration and QoE scoring.
- Durable offline download managers separated from transient feed cache.
- MediaSessionService / Now Playing system controls and background ownership.
- Phase 4 benchmark metadata and QoE regression gate.

Next release gate: compile/link in Android/Xcode CI and publish physical-device benchmark artifacts before making comparative performance claims.
## Phase 5 — Predictive runtime and diagnostics ✅

- [x] Stateful native bandwidth predictor with confidence/volatility.
- [x] Velocity-aware viewport intent prediction.
- [x] Health-ranked multi-CDN failover.
- [x] Native frame-pipeline diagnostics.
- [x] Predictive regression gates and physical-device result contract.

## Phase 6 — Certified advanced media

- [ ] Offline Widevine/FairPlay license lifecycle with provider fixtures.
- [ ] Device-certified codec/decoder affinity experiments.
- [ ] Cast orchestration with optional platform SDK integration.
- [ ] Automated physical-device farm collection and competitor matrices.
- [ ] Signed benchmark artifacts and reproducible release reports.
