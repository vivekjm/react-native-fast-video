# Phase 6 Decision Register

**Status:** active planning register  
**Rule:** an implementation PR may not make an unresolved product/security/platform decision implicitly. It must reference an approved decision ID or introduce an ADR for review.

## 1. Decision states

- **Accepted** — binding for Phase 6 unless superseded by a reviewed ADR.
- **Proposed** — recommended default; approval still required.
- **Open** — no implementation should assume an answer.
- **Deferred** — explicitly outside the current beta scope.
- **Superseded** — replaced by another decision ID.

## 2. Accepted architectural decisions

| ID | Decision | Rationale | Consequence |
|---|---|---|---|
| P6-D001 | Phase 6 planning is documentation-only before implementation | Prevent architecture from being retrofitted after code | Master plan, API, threat model, matrix, and backlog reviewed together |
| P6-D002 | Phase 6 depends on merged Phase 1–5 hardening | Avoid building on a branch incorrectly assumed to be `main` | First implementation branch starts after the baseline gate |
| P6-D003 | Raw DRM key material never crosses the JS bridge | Protect secrets from JS dependencies, logs, and devtools | Public API exposes opaque asset IDs and sanitized status only |
| P6-D004 | Media and persistent license form one logical offline transaction | Prevent unusable half-completed downloads and entitlement leaks | Durable coordinator, compensation, and reconciliation are mandatory |
| P6-D005 | `system` remains the default decoder policy | Platform defaults are safest without device evidence | Certified overrides are opt-in and exact-profile scoped |
| P6-D006 | Apple does not expose decoder-name pinning in the cross-platform API | AVPlayer has no public Android-equivalent selector | Apple work focuses on capability/outcome telemetry and public controls |
| P6-D007 | Cast is an optional integration | Avoid binary/dependency/manifest cost for non-Cast apps | Plugin-controlled dependency or sibling package/subspec |
| P6-D008 | DRM Cast requires an application-owned Custom Web Receiver | Default/styled receivers cannot satisfy arbitrary DRM/business logic | Receiver contract and authorization are application responsibilities |
| P6-D009 | Cast authorization is separate from mobile DRM/media authorization | Prevent mobile credential leakage to receiver | Receiver-specific short-lived token provider |
| P6-D010 | Exactly one transport owns playback at a time | Prevent double audio, conflicting progress, and command races | Transfer transaction with rollback snapshot |
| P6-D011 | Physical-device evidence is required for DRM, HDR, routes, power, and comparative claims | Simulator/emulator cannot prove hardware/platform behavior | Certification labels distinguish build, integration, and device proof |
| P6-D012 | Synthetic benchmark fixtures validate tooling only | Prevent fabricated performance claims | Claim-bearing results require physical raw samples |
| P6-D013 | Broad “fastest player” claims are prohibited without a separate reviewed claim policy | Avoid cherry-picked/universal marketing | Prefer precise scenario/device claims with public evidence |
| P6-D014 | Evidence and binaries require provenance attestation before beta release | Tie reports and artifacts to source/workflow | SBOM, hashes, attestation, independent verification |
| P6-D015 | Certification instrumentation is isolated from the normal stable API | Avoid production API pollution and overhead | Separate export/build flag with explicit lab contract |

## 3. Proposed defaults awaiting approval

| ID | Proposed decision | Default | Alternatives | Must be decided before |
|---|---|---|---|---|
| P6-D101 | Offline delete behavior without network | delete local media, retain encrypted `releasePending` tombstone, retry provider release | block local delete; retain everything until release | offline coordinator implementation |
| P6-D102 | Automatic renewal | enabled when provider supports it, threshold provider policy or 72h default | manual only; fixed threshold | public offline API freeze |
| P6-D103 | Clear download migration | existing `downloadFastVideoOffline` delegates to unified prepare API for one beta cycle | immediate replacement; permanent alias | public API implementation |
| P6-D104 | Cast packaging | optional sibling entry/package plus plugin-controlled native dependencies | CocoaPods subspec/Gradle property only; always bundled | Cast prototype |
| P6-D105 | Decoder profile distribution | signed bundled profile first; host-controlled remote disable only | application endpoint updates; library-hosted registry | certified selector implementation |
| P6-D106 | Benchmark sample counts | PR 3, nightly 10, release 30 minimum for claim scenarios | adaptive sequential testing | lab pipeline implementation |
| P6-D107 | Apple persistent-key storage | file-protected encrypted blob with Keychain-wrapped key, excluded from backup | Keychain-only chunks; platform file protection only | FairPlay storage prototype |
| P6-D108 | Android key-set metadata storage | Keystore-backed AEAD record, excluded from backup | EncryptedSharedPreferences; SQLCipher-style DB | Widevine storage prototype |
| P6-D109 | Release train | `0.1.0-beta.x` after Phase 6 certification subset passes | continue `0.0.x-alpha`; wait for full stable | beta scope approval |
| P6-D110 | Remote progress event | one normalized progress event with explicit `transport` field | separate local/remote progress events | remote API freeze |

## 4. Open product/security decisions

### P6-D201 — Reference DRM providers

**Question:** Which real Widevine and FairPlay provider implementations certify the adapter contract?  
**Required output:** provider names, test-account ownership, fixture policy capabilities, rate limits, credential rotation, redistribution restrictions, CI suitability, and responsible owner.

### P6-D202 — Logout behavior

Choose one documented policy:

1. **Suspend:** keep encrypted asset/license, block playback until same account returns.
2. **Remove:** initiate release/delete on logout.
3. **Keep:** continue playback after logout because entitlement is device-bound/product-approved.

The library supports policy; the host application owns the choice. The default may not be guessed in implementation.

### P6-D203 — Account switching

**Question:** Does switching accounts hide, suspend, or remove prior account assets?  
**Required output:** UI visibility, playback check, renewal credentials, queued-release ownership, and failure behavior.

### P6-D204 — App reinstall and backup/restore

**Question:** Are protected offline assets expected to survive backup/restore or reinstall?  
**Proposed security default:** no. Sensitive records are excluded from backup and restored orphan metadata is removed/reconciled, not silently reacquired.

### P6-D205 — Provider release while offline

**Question:** How long can a `releasePending` tombstone remain, and when may the user consider storage removal complete?  
**Required output:** retention period, retry cadence, account logout interaction, user messaging, and support export behavior.

### P6-D206 — Native credential provider registration

Candidate mechanisms:

- Android interface/class registered through application initializer and adapter ID.
- Apple protocol implementation registered through Expo module/AppDelegate subscriber.
- Generated registry from config plugin class names.
- Host-app explicit runtime registration before any offline operation.

Decision criteria: background availability, process restart, Expo compatibility, testability, no secret generation in config files.

### P6-D207 — Certificate pinning

**Question:** Does the core expose a pinning policy, or is pinning entirely provider-adapter-owned?  
**Proposed answer:** adapter-owned because providers need rotation and failure policy. The core enforces HTTPS/redirect/header rules.

### P6-D208 — Cast receiver ownership

**Question:** Will the repository include only a reference receiver contract/fixture, or also a deployable example Custom Web Receiver?  
**Required output:** hosting owner, app ID management, license terms, DRM provider integration, release cadence, and security review.

### P6-D209 — Cast dependency packaging

Evaluate:

- `react-native-fast-video/cast` export with optional native build configuration;
- sibling `@react-native-fast-video/cast` package;
- CocoaPods subspec plus Gradle property;
- plugin-injected direct SDK dependencies.

Measure binary size, install complexity, Expo prebuild behavior, autolinking, and version compatibility before approval.

### P6-D210 — Public route API semantics

AirPlay route selection is system-controlled, while Cast exposes SDK sessions. Decide whether one `FastVideoRouteButton`/state model is sufficiently honest or whether route-specific components are clearer.

### P6-D211 — First certified decoder-profile scope

Choose exact target:

- no overrides in first beta, telemetry only;
- Pixel reference devices only;
- a limited known-problem device set;
- broad OEM matrix.

Proposed answer: telemetry first, then a deliberately small exact-profile set.

### P6-D212 — Decoder profile signing/update ownership

**Question:** Who signs profiles and where do updates originate?  
**Required output:** key ownership, rotation, offline behavior, profile expiry, rollback, and audit trail.

### P6-D213 — Competitor set

Freeze maintained versions and disclose:

- package/version;
- platform support;
- build flags;
- preload/cache settings;
- unsupported scenarios;
- adapter source.

The set is selected before release measurements, not after seeing results.

### P6-D214 — Claim policy

Define whether Phase 6 beta publishes:

- certification only, no competitor claims;
- precise per-scenario comparisons;
- an aggregate score;
- a broad superlative.

Proposed answer: certification plus precise per-scenario comparisons only. An aggregate or superlative requires a later dedicated review.

### P6-D215 — Statistical practical-significance thresholds

For each metric family define the minimum effect that matters, such as TTFF milliseconds/percentage, failure-rate delta, energy delta, or rebuffer change. Statistical significance alone is insufficient.

### P6-D216 — Production telemetry

**Question:** Is decoder/CDN/DRM outcome telemetry solely a lab capability, or is opt-in production aggregation supported?  
**Required output:** consent, privacy policy, retention, data minimization, endpoint ownership, sampling, and deletion.

### P6-D217 — Phase 6 beta scope

Options:

- all workstreams required;
- secure offline DRM + evidence first, Cast/decoder profiles later;
- remote playback first, DRM later;
- certification infrastructure first with features behind experimental flags.

The release label must enumerate certified versus experimental items.

## 5. Platform compatibility decisions

### P6-D301 — Minimum OS versions

Current project declarations are Android minSdk 24 and iOS/tvOS 15.1. Phase 6 must decide whether advanced features:

- preserve package minimums and use capability gating; or
- raise minimum versions for the entire package.

Proposed answer: preserve package minimums, capability-gate Phase 6 features, and document provider/device exceptions.

### P6-D302 — Media3 version policy

Phase 6 uses unstable APIs such as offline DRM helpers/codec selection. Decide:

- pin exact Media3 version per beta;
- support a bounded override range;
- test minimum and current supported versions.

Proposed answer: exact default plus a narrow tested override range; no unbounded arbitrary override guarantee.

### P6-D303 — Cast SDK version policy

Because Cast is optional, define independent compatibility and release notes. Core package updates must not silently force a Cast SDK major upgrade.

### P6-D304 — tvOS scope

The podspec declares tvOS, but Phase 6 planning is primarily iOS sender playback. Decide whether tvOS local playback, FairPlay persistent keys, AirPlay receiver behavior, or Cast sender behavior is certified in the beta.

## 6. Evidence/release decisions

### P6-D401 — Evidence repository location

Options:

- GitHub release assets in the main repository;
- dedicated evidence repository;
- object storage plus signed manifest;
- combination with compact release summary in main repo.

Selection must support immutable/public verification without bloating npm/git source history.

### P6-D402 — Raw trace retention

Define retention for large Perfetto, `.xcresult`, and energy traces. Summaries alone are insufficient for claim verification, but unlimited retention is expensive.

### P6-D403 — Attestation subjects

At minimum attest:

- npm package tarball;
- Android example/benchmark binary;
- Apple example/benchmark build artifact where distributable;
- evidence bundle;
- SBOM.

### P6-D404 — Release branch/tag protection

Define required reviewers, status checks, immutable release handling, and who may publish npm/GitHub releases.

## 7. Decision review order

Decisions are not all equally urgent. Review in this order:

1. P6-D201–D207: DRM provider, account, storage, and credential policy.
2. P6-D217: beta scope.
3. P6-D208–D210: Cast/route packaging and ownership.
4. P6-D211–D212: decoder profile scope/signing.
5. P6-D213–D215: competitor and statistical claim policy.
6. P6-D301–D304: platform/version scope.
7. P6-D401–D404: evidence publication and release governance.

## 8. ADR template

Every resolved open decision receives an ADR:

```md
# ADR P6-XXX — Title

- Status: Accepted
- Date:
- Owners:
- Related issues/PRs:

## Context

## Options considered

## Decision

## Security implications

## Compatibility implications

## Operational implications

## Test/certification requirements

## Rollback or migration
```

## 9. Implementation-PR rule

A Phase 6 implementation PR description must include:

- workstream/milestone ID;
- accepted decision IDs used;
- new decisions introduced;
- threat-model entries addressed;
- capability label before and after;
- tests and physical fixtures required;
- rollback/feature flag;
- evidence schema changes;
- items explicitly left unsupported.
