# Phase 6 Certification Matrix

**Status:** proposed certification contract  
**Purpose:** define what must be measured, where it must run, how results are interpreted, and what evidence is required before a capability or performance claim is published.

## 1. Certification philosophy

Phase 6 separates four kinds of evidence:

1. **Host correctness** — deterministic state, schema, serialization, redaction, and policy tests.
2. **Native integration** — Android/iOS builds, platform API contracts, simulator/emulator smoke tests.
3. **Physical-device functional certification** — actual decoder, DRM, HDR, route, background, and lifecycle behavior.
4. **Controlled performance certification** — repeatable physical-device measurements under a documented environment.

A lower tier can never substitute for a higher tier. A simulator can prove that code links; it cannot certify Widevine L1, FairPlay persistent keys, 4K HDR output, thermal behavior, Cast hardware, or battery efficiency.

## 2. Test tiers

| Tier | Trigger | Environment | Runs per scenario | Purpose | Release blocking |
|---|---|---|---:|---|---|
| T0 | every commit | host CI | deterministic | C++/TS/schema/security contracts | yes |
| T1 | every PR | emulator + iOS simulator | 1–3 | native build and basic smoke | yes |
| T2 | nightly | Firebase Test Lab / physical farm | 3–10 | broad device functional matrix | yes for repeated failures |
| T3 | scheduled | controlled owned devices | 10–20 | performance, power, thermal, route hardware | yes for protected scenarios |
| T4 | release candidate | frozen full matrix | at least 30 claim-bearing samples | beta/release evidence and competitor comparison | yes |

Flaky tests are recorded as failures until classified. Reruns are additional samples, not replacements for inconvenient results.

## 3. Evidence identity

Every run has a globally unique `runId` and immutable environment fingerprint:

```json
{
  "schemaVersion": "phase6-evidence-1",
  "runId": "...",
  "scenarioId": "vod-hls-1080p-cold",
  "commitSha": "...",
  "packageVersion": "...",
  "fixtureManifestSha256": "...",
  "applicationBuildSha256": "...",
  "platform": "android",
  "osVersion": "...",
  "osBuild": "...",
  "deviceModel": "...",
  "soc": "...",
  "memoryBytes": 0,
  "displayRefreshRateHz": 0,
  "networkProfile": "wifi-clean-25mbps",
  "decoderPolicy": "system",
  "transport": "local",
  "drmScheme": null,
  "coldStart": true,
  "cacheState": "empty",
  "batteryLevelStart": 0,
  "thermalStateStart": "nominal",
  "timestampUtc": "..."
}
```

Signed URLs, request headers, license payloads, content keys, user identifiers, and provider account data are prohibited from this file.

## 4. Fixture matrix

### 4.1 Clear VOD

| Fixture | Container/protocol | Video | Audio | Resolution | Purpose |
|---|---|---|---|---|---|
| `clear-mp4-h264-720` | progressive MP4 | H.264 | AAC | 720p | minimum baseline |
| `clear-mp4-h264-1080` | progressive MP4 | H.264 | AAC | 1080p | common VOD |
| `clear-hls-avc-ladder` | HLS/CMAF | H.264 | AAC | 360p–1080p | ABR/startup |
| `clear-dash-avc-ladder` | DASH/CMAF | H.264 | AAC | 360p–1080p | Android DASH parity |
| `clear-hls-hevc-4k` | HLS | HEVC | AAC/E-AC-3 | 2160p | 4K capability |
| `clear-dash-av1-ladder` | DASH | AV1 | AAC/Opus where valid | 480p–2160p | modern codec capability |

Fixtures are encoded once per fixture version. They are not regenerated between competitor runs.

### 4.2 HDR

| Fixture | Format | Certification condition |
|---|---|---|
| `hdr10-hevc-4k` | HDR10/HEVC | device declares support and output remains HDR |
| `hlg-hevc-4k` | HLG/HEVC | device/display route supports HLG |
| `dolby-vision-hls` | Dolby Vision/HLS | licensing and certified Apple/Android device support |
| `hdr-fallback-sdr` | dual ladder | unsupported devices select valid SDR without fatal error |

A library-level “HDR supported” result requires stream, codec, device, OS, secure path when DRM is used, and display/route agreement.

### 4.3 Live

| Fixture | Protocol | Characteristics |
|---|---|---|
| `live-hls-standard` | HLS | sliding DVR window, discontinuities |
| `live-hls-low-latency` | LL-HLS | parts, preload hints, rendition reports |
| `live-dash-standard` | DASH | dynamic MPD and time-shift buffer |
| `live-failover` | HLS/DASH aliases | deterministic CDN delay/error injection |

The fixture controller records server-side media time so client live-offset measurements can be independently checked.

### 4.4 Tracks and manifest edge cases

Required fixtures:

- multiple audio languages;
- commentary and descriptive audio;
- WebVTT and TTML subtitles;
- forced subtitles;
- undetermined-language tracks;
- codec/resolution switch boundaries;
- HLS discontinuity;
- DASH period transition;
- segment gap;
- stale manifest;
- malformed manifest;
- unsupported codec rendition mixed into an otherwise playable ladder.

### 4.5 DRM fixtures

#### Widevine

- streaming CENC;
- streaming cbcs where supported;
- persistent renewable license;
- short-lived license;
- expired license;
- revoked license;
- release-required license;
- L1-required protected HD/4K fixture;
- L3-compatible lower-resolution fixture;
- output-restricted fixture.

#### FairPlay

- streaming FPS HLS;
- persistable renewable key;
- short-lived persistent key;
- expired key;
- revoked entitlement;
- invalidated local key;
- updated persistent-key response;
- output-restricted/AirPlay-policy fixture where provider rules allow.

The deterministic test provider may emulate policy transitions, but release certification also requires selected real provider implementations.

### 4.6 Remote playback fixtures

- clear VOD supported by default receiver;
- clear live DVR;
- alternate audio/text tracks;
- queue of at least three items;
- Custom Web Receiver DRM fixture;
- receiver authorization expiry and refresh;
- sender disconnect/reconnect;
- receiver reboot/termination;
- unsupported receiver codec/HDR fallback.

## 5. Fault-injection matrix

The fixture proxy provides deterministic fault profiles:

| Profile | Behavior |
|---|---|
| `latency-100` | fixed 100 ms request latency |
| `latency-jitter` | seeded latency distribution |
| `bandwidth-step` | 25 Mbps → 3 Mbps → 12 Mbps |
| `packet-loss-light` | low seeded loss/retry pattern |
| `http-404-segment` | selected segment missing |
| `http-500-window` | bounded server failure period |
| `connection-reset` | deterministic TCP reset |
| `manifest-stale` | old live manifest served temporarily |
| `manifest-corrupt` | syntactic/semantic manifest error |
| `cdn-primary-down` | primary origin fails, fallback healthy |
| `license-timeout` | license request timeout |
| `license-500` | provider server error |
| `license-revoked` | entitlement revoked |
| `clock-skew` | fixture/provider time skew test |

Seeds and exact schedules are stored in the evidence manifest.

## 6. Scenario catalog

### 6.1 Startup

- cold process + empty cache;
- warm process + empty cache;
- warm process + warmed manifest/asset;
- disk-cache hit;
- memory-preloaded feed item;
- clear offline item;
- DRM offline item;
- post-background restore;
- post-process-death restore.

Primary metric: time from native source assignment to rendered first frame. Secondary metrics: item-ready latency, decoder initialization, bytes before first frame, selected initial resolution, failure rate.

### 6.2 Seeking

- forward seek within buffered range;
- forward seek outside buffer;
- backward seek;
- exact seek versus tolerant seek;
- seek near VOD end;
- live DVR seek;
- go-to-live;
- Cast remote seek;
- AirPlay route seek.

Primary metric: command accepted to first rendered frame at target. Correctness includes target tolerance and no stale-frame presentation beyond the declared allowance.

### 6.3 Feed scrolling

- 20, 50, and 100-item feeds;
- slow scroll, fast fling, reversal, and random jumps;
- one visible item and two-visible-item layouts;
- mixed HLS/progressive sources;
- cache budget pressure;
- low-memory warning;
- background/foreground during scrolling.

Metrics: warm TTFF, player creation count, decoder initialization count, cache hit bytes, dropped UI frames, process memory, active player count, network bytes, and wrong-item playback incidents.

### 6.4 Long playback

- 30 minutes, 2 hours, and overnight soak where infrastructure permits;
- VOD, live, DRM streaming, and DRM offline;
- background/foreground cycles;
- route changes;
- network changes;
- thermal pressure.

Metrics: crash/ANR, memory slope, rebuffer ratio, frame drops, live drift, license status, energy, temperature/thermal class, and error recovery.

### 6.5 Concurrent playback/resource pressure

- 2, 3, and 4 prepared players;
- one active + preload players;
- picture-in-picture plus foreground preview;
- audio-only background plus foreground video where product policy permits;
- secure and nonsecure decoder combinations.

The scenario must respect platform policy; success is not defined as forcing unsupported concurrent secure decoders.

### 6.6 Offline DRM lifecycle

For each DRM platform/provider:

1. acquire and download;
2. kill process at every durable state boundary;
3. restart and reconcile;
4. play with network disabled;
5. query validity;
6. renew near threshold;
7. play after renewal;
8. expire intentionally;
9. revoke intentionally;
10. remove online;
11. remove offline and complete queued release later;
12. switch account scope;
13. app upgrade with existing asset;
14. corrupt media metadata, license metadata, and one storage side independently;
15. verify no secret appears in logs/artifacts.

### 6.7 Remote playback

- local → Cast while playing;
- local → Cast while paused;
- Cast → local;
- local route → AirPlay and back;
- transfer during live DVR playback;
- transfer with selected audio/subtitle;
- Cast sender app background/terminate/relaunch;
- implicit Wi-Fi disconnect and reconnect;
- explicit disconnect versus stop casting;
- multiple sender devices;
- queue navigation;
- receiver-side pause/seek reflected on sender;
- DRM receiver token expiry;
- route capability mismatch.

## 7. Metrics dictionary

### 7.1 Playback QoE

- `timeToFirstFrameMs`
- `itemReadyMs`
- `seekToFirstFrameMs`
- `rebufferCount`
- `totalRebufferMs`
- `rebufferRatio`
- `renderedFrames`
- `droppedFrames`
- `droppedFrameRatio`
- `averageFrameProcessingOffsetUs`
- `liveOffsetMs`
- `liveOffsetErrorMs` against fixture clock
- `initialVideoBitrateBps`
- `averageVideoBitrateBps`
- `qualitySwitchCount`
- `bytesTransferred`
- `cacheBytesRead`
- `qoeScore`

### 7.2 Resource metrics

- CPU time and utilization;
- physical/resident memory and memory slope;
- frame overrun/jank distribution;
- power and energy where supported;
- thermal-state transitions;
- decoder initialization count/duration;
- active decoder/player count;
- network radio/bytes when measurable;
- storage read/write volume for offline scenarios.

### 7.3 DRM metrics

- manifest/DRM init-data preparation time;
- certificate fetch time;
- SPC generation time;
- license network time;
- CKC/license parse time;
- persistable-key conversion time;
- total license acquisition time;
- renewal time;
- release time;
- remaining license/playback duration;
- recovery/reconciliation time;
- provider failures by sanitized class.

No metric payload contains key bytes, request/response bodies, authorization values, or full protected URLs.

### 7.4 Remote metrics

- discovery-to-route-visible time;
- connection time;
- receiver launch time;
- remote media load-to-first-frame time when receiver reports it;
- local-to-remote transfer interruption duration;
- position transfer error;
- reconnection time;
- command round-trip latency;
- live-window synchronization error;
- remote fatal/session failure rate.

Remote metrics are not merged into local FastCore metrics without an explicit `transport` dimension.

## 8. Device matrix

Exact model identifiers are frozen in each release manifest because cloud availability changes. The matrix categories are mandatory.

### 8.1 Android phone/tablet

| Category | Minimum representation |
|---|---|
| minimum supported OS | physical API 24/25 class device where obtainable |
| older supported | API 28–30 physical device |
| modern baseline | API 31–33 physical device |
| current reference | current Android on recent Pixel |
| Samsung flagship | current or previous generation |
| Samsung midrange | current supported midrange |
| Qualcomm non-Pixel | at least one additional OEM |
| MediaTek | at least one supported device |
| low memory | 3–4 GB class device |
| high refresh | 90/120 Hz device |
| tablet/foldable | at least one large/folding form factor |
| Widevine L1 | verified protected HD-capable device |
| Widevine L3 | verified L3/fallback scenario |

### 8.2 Android TV / Google TV

- one current Google TV reference device;
- one OEM Android TV device;
- protected 4K/HDR-capable route where available;
- remote/HDMI capability changes;
- controller, background, and media-session behavior.

### 8.3 Apple

| Category | Minimum representation |
|---|---|
| minimum supported iOS | device capable of the minimum declared iOS version |
| older A-series | oldest performance tier retained for support |
| mid-generation | representative mainstream device |
| current generation | current iPhone reference |
| high-refresh | ProMotion-capable device |
| iPad | one supported iPad class |
| HDR display | device/route capable of target HDR fixture |
| FairPlay persistent key | real FPS-capable physical device |
| AirPlay sender | physical iPhone/iPad |
| AirPlay receiver | Apple TV or certified AirPlay receiver |

### 8.4 Cast hardware

- current Google TV/Cast receiver;
- one older supported Cast generation;
- one Cast built-in TV or speaker/video receiver where applicable;
- Custom Web Receiver DRM environment;
- multiple-sender scenario.

## 9. Controlled environment rules

### 9.1 Before every controlled run

- charge within the declared battery band;
- disable battery saver unless the scenario explicitly tests it;
- allow device temperature/thermal state to return to the declared baseline;
- set fixed brightness and refresh-rate policy;
- close unrelated applications and accounts where practical;
- freeze orientation, locale, and accessibility settings;
- verify fixture and build hashes;
- reset cache/download state according to scenario;
- verify network shaper profile and seed;
- record free storage and memory pressure;
- record route/display capabilities.

### 9.2 Run ordering

- randomize or use a Latin-square/counterbalanced order across players;
- do not run every competitor after one player has heated the device;
- interleave cool-down periods where required;
- separate cold and warm experiments;
- exclude a run only for a predeclared infrastructure-invalid reason;
- retain excluded-run metadata and reason.

### 9.3 Cloud farm limitations

Cloud physical devices are excellent for functional breadth. They are not the authoritative source for cross-player energy or fine-grained thermal claims because background load, radio conditions, and device history are less controlled. Power/thermal claims use owned or reserved controlled hardware.

## 10. Statistical plan

### 10.1 Required reporting

For every numeric metric:

- sample count;
- valid/invalid/failure count;
- median;
- mean only as supplementary information;
- standard deviation or median absolute deviation;
- P90, P95, and P99 when sample count permits;
- minimum and maximum;
- 95% confidence interval using the predeclared bootstrap method;
- device-level and aggregate views kept separate.

### 10.2 Pairing

Competitor comparisons should be paired by:

- device;
- fixture;
- network seed;
- cache/start state;
- thermal band;
- run block.

A paired comparison is preferred over pooling unrelated runs.

### 10.3 Regression gate

Budgets live in a versioned scenario file, not hard-coded in prose. Initial gate rules:

- zero new crash/ANR/fatal decoder failures in the certification sample;
- functional pass rate must meet the scenario’s declared threshold, normally 100% for deterministic core flows;
- a metric regression blocks when both statistical and practical-significance thresholds are exceeded;
- reliability cannot be traded for a small TTFF improvement;
- power improvement cannot justify visible frame/rebuffer regression;
- unsupported scenarios are reported as unsupported, not silently removed.

### 10.4 Comparative claim gate

A public “faster than X” statement requires:

- a pre-registered scenario and primary metric;
- same environment and feature-equivalent configuration;
- confidence interval excluding no difference;
- minimum practical effect declared before execution;
- no material reliability regression;
- raw evidence and source/build identities published.

A broad “fastest” claim is prohibited until a separate reviewed claim policy defines the scenario weighting and the full competitor set. Phase 6 should prefer precise claims such as “lower median warm-feed TTFF in the published Pixel X/API Y fixture” rather than a universal slogan.

## 11. Platform harnesses

### 11.1 Android

- instrumentation for functional state and DRM workflows;
- Macrobenchmark `StartupTimingMetric`, `FrameTimingMetric`, and trace sections where applicable;
- experimental `PowerMetric` only on supported controlled Pixel hardware;
- Perfetto traces attached to failed/regressed runs;
- Media3 analytics and FastCore snapshots correlated by run/session ID;
- device-side log redaction assertion after every protected scenario.

### 11.2 Apple

- XCTest UI flows for player, offline, route, and process-relaunch scenarios;
- `XCTClockMetric`, `XCTCPUMetric`, `XCTMemoryMetric`, `XCTHitchMetric`, and `XCTOSSignpostMetric` as applicable;
- OS signposts for source set, item ready, first frame, seek, stall, license acquire/renew/release, offline ready, and transport transfer;
- `.xcresult` and diagnostic logs retained;
- physical hardware required for FairPlay persistent keys, AirPlay, HDR, and energy/thermal evidence.

## 12. Competitor adapter contract

Each competitor adapter implements only orchestration around its public API:

```ts
interface BenchmarkPlayerAdapter {
  id: string;
  version: string;
  capabilities: ScenarioCapabilities;
  reset(state: ResetState): Promise<void>;
  mount(source: BenchmarkSource): Promise<void>;
  play(): Promise<void>;
  pause(): Promise<void>;
  seekTo(positionMs: number): Promise<void>;
  snapshot(): Promise<NormalizedBenchmarkSnapshot>;
  unmount(): Promise<void>;
}
```

Rules:

- no private fork patches unless clearly disclosed as a separate competitor;
- exact dependency version and build flags recorded;
- native defaults documented;
- unavailable metrics remain null, not estimated;
- an adapter failure is visible in raw evidence;
- feature mismatches are declared before the run.

Initial comparison candidates are selected during planning review based on current adoption and maintained versions; the list is frozen per release candidate.

## 13. Release evidence schema validation

Every bundle passes:

- JSON Schema validation;
- required-file manifest validation;
- SHA-256 verification;
- fixture hash validation;
- source commit/tag validation;
- package/binary hash validation;
- secret/redaction scan;
- duplicate/missing run detection;
- statistical recomputation from raw samples;
- summary-to-raw consistency check;
- artifact/SBOM attestation verification.

The report generator reads only the normalized evidence bundle. Hand-edited headline numbers are not allowed.

## 14. Capability certification labels

Documentation uses these labels:

- **Implemented** — source exists and host/native build tests pass.
- **Integration-tested** — simulator/emulator or deterministic fixture passes.
- **Device-certified** — required physical-device matrix passes.
- **Provider-certified** — named real DRM provider fixture passes.
- **Experimental** — opt-in, evidence incomplete, rollback available.
- **Device-dependent** — capability truth comes from runtime/device evidence.
- **Unsupported** — deliberately unavailable or outside scope.

No feature moves directly from “implemented” to “device-certified.”

## 15. Phase 6 release gate checklist

### Offline DRM

- [ ] Widevine acquire/query/renew/release physical-device suite.
- [ ] FairPlay persistent-key acquire/update/invalidate physical-device suite.
- [ ] Process-death reconciliation at every state boundary.
- [ ] Expiry, revocation, account switch, and queued release.
- [ ] Provider-adapter fixtures and redaction audit.

### Decoder intelligence

- [ ] Inventory telemetry complete and schema-valid.
- [ ] `system` policy regression-free.
- [ ] Every certified Android override supported by repeated device evidence.
- [ ] Secure/HDR/concurrent decoder matrix.
- [ ] Profile expiry and kill-switch tests.

### Remote playback

- [ ] AirPlay route selection, interruption, tracks, live, PiP, and background tests.
- [ ] Cast sender UX and session-resume tests.
- [ ] Queue/live/track parity.
- [ ] Custom Web Receiver DRM authorization tests.
- [ ] Local/remote ownership and rollback tests.

### Performance and evidence

- [ ] Frozen fixture manifest.
- [ ] Frozen device matrix.
- [ ] PR/nightly/release pipelines operational.
- [ ] Controlled performance sample counts met.
- [ ] Raw traces and samples published.
- [ ] Statistical report reproduced automatically.
- [ ] SBOM and provenance attestations verified.
- [ ] Claim-policy job passes or comparative claims are omitted.
