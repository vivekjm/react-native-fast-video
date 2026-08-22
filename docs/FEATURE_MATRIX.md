# Feature Matrix

Legend: ✅ implemented • 🧪 foundation/needs device fixtures • ⚙️ platform/device dependent • 🗓 planned • — not native to platform

| Capability | Android | Apple | Notes |
|---|---:|---:|---|
| Progressive playback | ✅ | ✅ | Device codec/container support applies |
| HLS | ✅ | ✅ | Native adaptive playback |
| Low-Latency HLS | ⚙️ | ⚙️ | Stream and OS dependent; device validation pending |
| DASH | ✅ | — | Supply HLS for Apple |
| 4K playback | ⚙️ | ⚙️ | Runtime decoder/display/stream capability |
| HDR10 / HLG | ⚙️ | ⚙️ | Codec profile, display and OS dependent |
| Dolby Vision | ⚙️ | ⚙️ | Device and licensed stream dependent |
| Hardware decode | ✅ | ✅ | MediaCodec / system AVFoundation path |
| SurfaceView render path | ✅ | — | Android default |
| TextureView render path | ✅ | — | Explicit compatibility mode |
| AVPlayerLayer render path | — | ✅ | Apple default |
| Play/pause/seek/replay | ✅ | ✅ | Native commands |
| Rate/volume/mute/repeat | ✅ | ✅ | Native commands |
| Live-edge seek | ✅ | ✅ | For detected live streams |
| Audio/text track listing | ✅ | ✅ | Embedded plus Android side-loaded text |
| Track selection | ✅ | ✅ | Native selection APIs |
| Side-loaded subtitles | ✅ | 🗓 | Apple implementation to be hardened |
| Widevine | 🧪 | — | Integration surface implemented; provider fixtures required |
| FairPlay Streaming | — | 🧪 | Resource-loader foundation; provider fixtures required |
| PiP | 🧪 | 🧪 | Entry points implemented; app configuration/device tests required |
| AirPlay/external playback | — | ✅ | AVPlayer external playback |
| Google Cast | 🗓 | — | Optional package planned |
| Background media session | 🗓 | 🗓 | Apple audio mode partly configured; full lifecycle pending |
| Fullscreen native host | 🗓 | 🗓 | App UI can compose fullscreen today |
| Offline downloads | 🗓 | 🗓 | Native managers planned |
| Cache/preloading/player pool | ✅ | ✅ | Android: byte-bounded SimpleCache + Media3 memory/disk preload tiers + ExoPlayer pool. Apple: staged AVURLAsset warming + AVPlayer pool; AVFoundation disk cache is OS-managed. |
| Client-side ads | 🗓 | 🗓 | Optional IMA adapters planned |
| Timed metadata / SSAI markers | 🗓 | 🗓 | Planned |
| Web fallback | ✅ | ✅ | Browser `<video>`; not the native FastCore path |
| Expo development build | ✅ | ✅ | Config plugin + autolinking |
| Expo Go | — | — | Custom native code is not bundled in Expo Go |
| C++ performance telemetry | ✅ | ✅ | Shared FastCore |
| Reproducible benchmark gate | ✅ | ✅ | Device results still required |

## Phase 4 systems

| Capability | Android | Apple | Notes |
| --- | --- | --- | --- |
| Native adaptive policy | ✅ | ✅ | Shared C++ decision core; platform-native enforcement |
| Network / thermal / low-power adaptation | ✅ | ✅ | No JavaScript control loop |
| Multi-player bandwidth fair-share | ✅ | ✅ | Active player count is an adaptive-policy input |
| Native QoE score | ✅ | ✅ | 0–100 deterministic diagnostic score |
| Media session / system controls | ✅ | ✅ | Media3 MediaSessionService / MPNowPlayingInfoCenter |
| Background playback after view teardown | ✅ | ✅ | Opt-in with `mediaSession: true` |
| Durable offline VOD | ✅ | HLS VOD | Android Media3 download stack; Apple AVAssetDownloadURLSession |
| Offline DRM licenses | ⏳ | ⏳ | Not advertised until renewal/revocation fixtures exist |

## Phase 5 predictive runtime

| Capability | Android | Apple | Notes |
| --- | --- | --- | --- |
| Smoothed bandwidth prediction | ✅ | ✅ | Shared FastCore model |
| Bandwidth confidence/volatility | ✅ | ✅ | Native observations only |
| Velocity-aware viewport prediction | ✅ | ✅ | C++ policy; native preload application |
| Health-ranked fallback CDN ordering | ✅ | ✅ | Origin-only diagnostics |
| Frame-processing offset telemetry | ✅ | — | Media3 signal; not fabricated on Apple |
| Predictive benchmark gate | ✅ | ✅ | Portable/synthetic gate only |
| Physical-device benchmark contract | ✅ | ✅ | Real results must be collected externally |
