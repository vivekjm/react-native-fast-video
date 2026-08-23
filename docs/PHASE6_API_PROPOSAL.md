# Phase 6 API Proposal

**Status:** proposal; no API in this document is implemented  
**Review rule:** API names may change during planning, but the security and ownership invariants may not be weakened.

## 1. API goals

The Phase 6 API must:

- make offline media and offline licenses one operation from the application’s point of view;
- expose stable, sanitized state instead of platform-native key objects;
- preserve existing clear-content APIs through a documented migration path;
- model local, Cast, and AirPlay playback as explicit transport ownership;
- expose decoder policy without pretending both platforms offer identical controls;
- keep certification instrumentation out of normal production bundles;
- remain usable in Expo development builds through a config plugin;
- support background renewal/reconciliation without depending on a live JavaScript runtime.

## 2. API invariants

1. Raw Widevine key-set IDs and FairPlay persistable keys are native-only.
2. Every long-running operation returns or accepts a library-generated opaque asset ID.
3. Every mutating operation is idempotent for the same asset ID and operation token.
4. Offline status is durable and survives process death.
5. A remote session has one authoritative transport owner.
6. Platform-specific capability differences are visible in capability/status objects.
7. Experimental decoder behavior is opt-in; `system` is the default.
8. Public metrics contain no signed URL paths, authorization values, content keys, SPC, or CKC.

## 3. Proposed source and DRM types

Existing streaming DRM fields remain valid. Phase 6 adds an optional offline policy and a provider-adapter reference.

```ts
export interface FastVideoDrmRequestPolicy {
  /** Built-in adapters cover common raw/base64 exchanges. Complex providers use a native adapter. */
  adapter?: 'standard' | `native:${string}`;

  /** Identifier resolved by the host application's native credential provider. */
  credentialProviderId?: string;

  /** Opaque, non-secret metadata passed to the native provider adapter. */
  providerMetadata?: Record<string, string | number | boolean>;
}

export interface FastVideoOfflineDrmPolicy {
  mode: 'persistent';

  /** Automatic renewal is performed natively and does not require the JS runtime. */
  renewal?: 'automatic' | 'manual';

  /** Attempt renewal before either license or playback duration reaches this threshold. */
  renewBeforeSeconds?: number;

  /** Behavior when the user removes an offline asset without network access. */
  deletePolicy?:
    | 'release-before-local-delete'
    | 'delete-local-and-queue-release'
    | 'keep-until-release';

  /** Whether a license is account-bound in the library's metadata model. */
  accountScope?: string;
}

export interface FastVideoWidevineDrm {
  type: 'widevine';
  licenseUrl: string;
  headers?: Record<string, string>;
  multiSession?: boolean;
  requestPolicy?: FastVideoDrmRequestPolicy;
  offline?: FastVideoOfflineDrmPolicy;
}

export interface FastVideoFairPlayDrm {
  type: 'fairplay';
  certificateUrl: string;
  licenseUrl: string;
  headers?: Record<string, string>;
  contentId?: string;
  licenseResponseType?: 'raw' | 'base64';
  requestPolicy?: FastVideoDrmRequestPolicy;
  offline?: FastVideoOfflineDrmPolicy;
}
```

### Why `credentialProviderId` exists

A header captured from JavaScript at download time may expire before a background renewal. Phase 6 therefore distinguishes:

- **request-time headers**, suitable for immediate foreground work; and
- a **native credential provider**, suitable for process restart, background renewal, and release.

The library does not store a callback closure from JavaScript and assume it will exist later.

## 4. Unified offline asset model

### 4.1 Durable states

```ts
export type FastVideoOfflineState =
  | 'requested'
  | 'acquiringLicense'
  | 'licenseReady'
  | 'downloadingMedia'
  | 'ready'
  | 'renewing'
  | 'expired'
  | 'revoked'
  | 'releasePending'
  | 'removing'
  | 'removed'
  | 'failed';
```

### 4.2 Sanitized license status

```ts
export interface FastVideoOfflineLicenseStatus {
  protected: boolean;
  scheme?: 'widevine' | 'fairplay';
  state:
    | 'notRequired'
    | 'acquiring'
    | 'usable'
    | 'renewing'
    | 'expired'
    | 'revoked'
    | 'releasePending'
    | 'released'
    | 'failed';
  acquiredAtMs?: number;
  expiresAtMs?: number;
  playbackExpiresAtMs?: number;
  renewAfterMs?: number;
  lastRenewedAtMs?: number;
  providerAdapter?: string;
  securityLevel?: string;
  outputRestricted?: boolean;
  error?: FastVideoOfflineError;
}
```

No field contains native key bytes or a platform key-set identifier.

### 4.3 Offline asset record

```ts
export interface FastVideoOfflineAsset {
  id: string;
  state: FastVideoOfflineState;
  sourceType: FastVideoSourceType;
  protected: boolean;
  media: {
    state: 'notStarted' | 'queued' | 'downloading' | 'completed' | 'failed' | 'removed';
    bytesDownloaded?: number;
    contentLength?: number;
    percentDownloaded?: number;
    selectedTracks?: FastVideoOfflineTrackSelection;
  };
  license: FastVideoOfflineLicenseStatus;
  createdAtMs: number;
  updatedAtMs: number;
  failureStage?: 'validation' | 'license' | 'media' | 'renewal' | 'release' | 'reconcile';
  error?: FastVideoOfflineError;
}
```

### 4.4 Track-selection contract

Track selection must be semantic and portable rather than exposing platform group indices.

```ts
export interface FastVideoOfflineTrackSelection {
  video?:
    | { mode: 'automatic'; maxHeight?: number; maxBitrate?: number; prefersHDR?: boolean }
    | { mode: 'all' };
  audioLanguages?: string[];
  textLanguages?: string[];
  includeForcedSubtitles?: boolean;
  includeUndeterminedText?: boolean;
}
```

## 5. Proposed offline functions

### 5.1 Prepare atomically

```ts
export interface PrepareFastVideoOfflineOptions {
  id?: string;
  title?: string;
  operationId?: string;
  tracks?: FastVideoOfflineTrackSelection;
  startBehavior?: 'immediate' | 'wifiOnly' | 'manual';
  allowCellular?: boolean;
}

export async function prepareFastVideoOffline(
  source: FastVideoSource,
  options?: PrepareFastVideoOfflineOptions
): Promise<FastVideoOfflineAsset>;
```

Semantics:

- validates the complete operation before acquiring a license;
- creates a durable item record;
- acquires a persistent license when required;
- prepares selected adaptive tracks;
- queues the media download;
- returns current durable state, not a claim that the operation already finished;
- repeated calls using the same `id`/`operationId` return the same logical operation.

### 5.2 Read and subscribe

```ts
export async function getFastVideoOfflineAsset(
  id: string
): Promise<FastVideoOfflineAsset | null>;

export async function listFastVideoOfflineAssets(
  filter?: { state?: FastVideoOfflineState[]; accountScope?: string }
): Promise<FastVideoOfflineAsset[]>;

export interface FastVideoOfflineEvent {
  id: string;
  previousState?: FastVideoOfflineState;
  asset: FastVideoOfflineAsset;
  reason?: string;
}

export function addFastVideoOfflineListener(
  listener: (event: FastVideoOfflineEvent) => void
): { remove(): void };
```

Events are coalesced; applications must always be able to rebuild UI by listing durable records.

### 5.3 Renew, reconcile, and remove

```ts
export async function renewFastVideoOfflineLicense(
  id: string,
  options?: { operationId?: string; force?: boolean }
): Promise<FastVideoOfflineAsset>;

export async function reconcileFastVideoOfflineAssets(
  options?: { ids?: string[]; reason?: 'startup' | 'foreground' | 'manual' }
): Promise<FastVideoOfflineAsset[]>;

export async function removeFastVideoOfflineAsset(
  id: string,
  options?: {
    operationId?: string;
    deletePolicy?: FastVideoOfflineDrmPolicy['deletePolicy'];
  }
): Promise<FastVideoOfflineAsset>;
```

`remove` may return `releasePending`. That is a successful durable transition, not a false claim that provider release already occurred.

### 5.4 Pause/resume media transfer

```ts
export async function pauseFastVideoOfflineAsset(id: string): Promise<FastVideoOfflineAsset>;
export async function resumeFastVideoOfflineAsset(id: string): Promise<FastVideoOfflineAsset>;
```

Pausing media does not discard or pause license validity. Renewal policy remains active unless the item is removed.

### 5.5 Migration from existing clear-content API

Existing APIs remain during the beta transition:

```ts
// Existing clear-content entry point
await downloadFastVideoOffline(source, options);
```

Planned behavior:

- implemented internally by `prepareFastVideoOffline`;
- clear content receives `license.state = 'notRequired'`;
- deprecated only after one beta cycle and migration documentation;
- existing `offlineId` playback continues to work.

## 6. Offline playback semantics

```tsx
<FastVideo
  source={{
    uri: canonicalOnlineUri,
    type: 'dash',
    offlineId: 'episode-42',
  }}
/>
```

Rules:

- `offlineId` is authoritative when present;
- no network upstream is used for media bytes;
- protected playback restores the native offline license internally;
- canonical online URI is metadata/fallback identity only and is not fetched;
- `onError` uses stable offline error codes when media or license is unavailable;
- an expired asset never silently falls back to streaming unless the application explicitly supplies a separate online source and chooses that behavior.

## 7. Native provider-adapter contract

Provider differences belong behind native interfaces.

### 7.1 Android conceptual contract

```kotlin
internal interface FastVideoWidevineProviderAdapter {
  val id: String

  suspend fun credentials(context: CredentialContext): LicenseCredentials

  suspend fun transformRequest(
    request: WidevineLicenseRequest,
    credentials: LicenseCredentials
  ): HttpLicenseRequest

  suspend fun parseResponse(response: HttpLicenseResponse): ByteArray

  suspend fun onReleaseResult(result: LicenseReleaseResult)
}
```

### 7.2 Apple conceptual contract

```swift
internal protocol FastVideoFairPlayProviderAdapter {
  var id: String { get }

  func credentials(for context: CredentialContext) async throws -> LicenseCredentials
  func makeSPCRequest(_ input: FairPlaySPCInput,
                      credentials: LicenseCredentials) async throws -> HTTPRequest
  func parseCKC(_ response: HTTPResponse) throws -> Data
  func didCompleteRelease(_ result: LicenseReleaseResult) async
}
```

### 7.3 Registration

The Expo plugin may accept adapter class names/identifiers, but it must not generate source containing secrets.

```ts
interface ReactNativeFastVideoPluginOptions {
  drmAdapters?: {
    widevine?: string[];
    fairplay?: string[];
  };
}
```

The exact registration mechanism is an implementation ADR because Expo autolinking, Android initialization, and Apple module visibility differ.

## 8. Remote playback types

### 8.1 Transport and route state

```ts
export type FastVideoTransport = 'local' | 'airplay' | 'cast';

export interface FastVideoRemoteRoute {
  id: string;
  type: 'airplay' | 'cast';
  name: string;
  available: boolean;
  connected: boolean;
  capabilities: {
    video: boolean;
    audio: boolean;
    live: boolean;
    queue: boolean;
    tracks: boolean;
    hdr?: boolean;
    drm?: boolean;
  };
}

export interface FastVideoRemotePlaybackState {
  transport: FastVideoTransport;
  connectionState:
    | 'local'
    | 'discovering'
    | 'connecting'
    | 'connected'
    | 'reconnecting'
    | 'disconnecting'
    | 'failed';
  route?: FastVideoRemoteRoute;
  sessionId?: string;
  mediaSessionId?: string;
  positionMs: number;
  durationMs: number;
  liveSeekableRange?: { startMs: number; endMs: number };
  isPlaying: boolean;
  selectedAudioLanguage?: string;
  selectedTextLanguage?: string;
  error?: FastVideoRemotePlaybackError;
}
```

Session IDs are sanitized correlation identifiers, not Cast credentials.

### 8.2 Route UI

Two supported integration levels are proposed:

```tsx
<FastVideoRouteButton
  types={['airplay', 'cast']}
  tintColor="currentColor"
  onAvailabilityChange={...}
/>
```

and:

```ts
export async function presentFastVideoRoutePicker(
  options?: { types?: Array<'airplay' | 'cast'> }
): Promise<void>;
```

Platform-native picker UI is preferred. The library should not recreate Cast/AirPlay discovery UI in React.

### 8.3 Transfer APIs

Transfer belongs to the player instance because current position, live range, tracks, and source are instance state.

```ts
export interface FastVideoTransferOptions {
  routeId?: string;
  receiverAuthorization?: {
    credentialProviderId: string;
    metadata?: Record<string, string | number | boolean>;
  };
  resumePolicy?: 'exact' | 'nearestLivePosition' | 'receiverDefault';
}

export interface FastVideoRef {
  // Existing methods omitted
  transferToRemote(
    transport: 'cast' | 'airplay',
    options?: FastVideoTransferOptions
  ): Promise<FastVideoRemotePlaybackState>;

  transferToLocal(
    options?: { resumePolicy?: 'exact' | 'nearestLivePosition' }
  ): Promise<FastVideoRemotePlaybackState>;

  stopRemotePlayback(): Promise<void>;
  getRemotePlaybackState(): Promise<FastVideoRemotePlaybackState>;
}
```

AirPlay may ultimately map to system route selection rather than programmatic route choice; the final API will reflect platform policy after prototype validation.

### 8.4 Remote events

```ts
interface FastVideoProps {
  // Existing props omitted
  onTransportChange?: (state: FastVideoRemotePlaybackState) => void;
  onRemoteSessionChange?: (state: FastVideoRemotePlaybackState) => void;
  onRemoteCapabilities?: (route: FastVideoRemoteRoute) => void;
  onRemoteError?: (error: FastVideoRemotePlaybackError) => void;
}
```

Local `onProgress` remains local-engine progress. When Cast owns playback, the event includes `transport: 'cast'` or a dedicated remote progress event is introduced. This must be resolved before implementation to avoid ambiguous metrics.

## 9. Cast-specific configuration

Cast is optional.

```ts
export interface FastVideoCastPluginOptions {
  enabled: boolean;
  receiverApplicationId: string;
  customReceiver: boolean;
  expandedController?: boolean;
  miniController?: boolean;
  androidNotification?: boolean;
}

export interface ReactNativeFastVideoPluginOptions {
  supportsPictureInPicture?: boolean;
  backgroundPlayback?: boolean;
  cast?: FastVideoCastPluginOptions;
}
```

Rules:

- enabling Cast adds platform SDK dependencies and manifest/plist configuration;
- omitting `cast` adds no Cast SDK dependency;
- DRM media requires `customReceiver: true` and a receiver authorization provider;
- the plugin validates incompatible combinations during prebuild;
- receiver app ID is configuration, not a secret.

## 10. AirPlay-specific behavior

AirPlay uses the existing AVPlayer pipeline. Proposed additions:

```ts
export interface FastVideoCapabilities {
  // Existing dynamic fields remain
  airPlay?: {
    supported: boolean;
    multipleRoutesDetected: boolean;
    externalPlaybackActive: boolean;
  };
}
```

The route button uses `AVRoutePickerView`. Route availability uses `AVRouteDetector`. System route choice remains user-controlled.

## 11. Decoder policy API

```ts
export type FastVideoDecoderPolicy =
  | 'system'
  | 'certified'
  | 'performance'
  | 'powerSaver';

export interface FastVideoRuntimeConfig {
  // Existing options omitted
  decoderPolicy?: FastVideoDecoderPolicy;
  decoderProfileSource?: 'bundled' | 'application';
}

export interface FastVideoDecoderDecision {
  platform: 'android' | 'ios';
  policy: FastVideoDecoderPolicy;
  ruleId?: string;
  requestedMimeType?: string;
  secureDecoderRequired?: boolean;
  selectedDecoder?: string;
  fallbackCount: number;
  reason: string;
  experimental: boolean;
}
```

Semantics:

- Android may use a certified `MediaCodecSelector` ordering.
- Apple reports policy/outcome but does not claim decoder-name selection.
- `system` is the production default.
- `performance` and `powerSaver` require an explicit experimental opt-in during beta.
- applications cannot pass arbitrary decoder names through JavaScript.

Possible event:

```ts
interface FastVideoProps {
  onDecoderDecision?: (event: FastVideoDecoderDecision) => void;
}
```

## 12. Certification instrumentation API

Certification controls must not pollute the stable player API. Proposed packaging:

```ts
import {
  beginCertificationScenario,
  markCertificationEvent,
  endCertificationScenario,
} from 'react-native-fast-video/certification';
```

This export is:

- development/release-lab only;
- tree-shakable and excluded from the normal package surface when possible;
- incapable of reading DRM key material;
- guarded by an explicit native build flag;
- stable enough for benchmark harnesses but not covered by normal semver until promoted.

```ts
export interface CertificationScenarioInput {
  schemaVersion: string;
  scenarioId: string;
  runId: string;
  fixtureId: string;
  coldStart: boolean;
  networkProfile: string;
  expectedTransport: FastVideoTransport;
  tags?: Record<string, string>;
}
```

## 13. Error taxonomy

### 13.1 Offline errors

```ts
export type FastVideoOfflineErrorCode =
  | 'E_OFFLINE_VALIDATION'
  | 'E_OFFLINE_PROVIDER_ADAPTER_MISSING'
  | 'E_OFFLINE_CREDENTIALS_UNAVAILABLE'
  | 'E_OFFLINE_DRM_UNSUPPORTED'
  | 'E_OFFLINE_LICENSE_ACQUIRE'
  | 'E_OFFLINE_LICENSE_EXPIRED'
  | 'E_OFFLINE_LICENSE_REVOKED'
  | 'E_OFFLINE_LICENSE_RENEW'
  | 'E_OFFLINE_LICENSE_RELEASE'
  | 'E_OFFLINE_MEDIA_PREPARE'
  | 'E_OFFLINE_MEDIA_DOWNLOAD'
  | 'E_OFFLINE_MEDIA_MISSING'
  | 'E_OFFLINE_RECONCILE'
  | 'E_OFFLINE_STORAGE_PROTECTED'
  | 'E_OFFLINE_ACCOUNT_SCOPE_MISMATCH';
```

### 13.2 Remote errors

```ts
export type FastVideoRemotePlaybackErrorCode =
  | 'E_ROUTE_UNAVAILABLE'
  | 'E_REMOTE_CONNECT'
  | 'E_REMOTE_SESSION_LOST'
  | 'E_REMOTE_LOAD'
  | 'E_REMOTE_AUTHORIZATION'
  | 'E_REMOTE_DRM_RECEIVER_REQUIRED'
  | 'E_REMOTE_TRACK_UNSUPPORTED'
  | 'E_REMOTE_LIVE_RANGE'
  | 'E_REMOTE_TRANSFER_ROLLBACK';
```

### 13.3 Error payload rules

- stable code and stage;
- retryable Boolean and suggested action;
- sanitized provider/native code;
- no request body, CKC/SPC, key ID, authorization value, or signed URL query;
- correlation ID shared with native logs and evidence artifacts.

## 14. Account and entitlement lifecycle

The library cannot decide product entitlement policy, but the API must make it enforceable.

Proposed account-scope operation:

```ts
export async function reconcileFastVideoOfflineAccount(
  accountScope: string | null,
  policy: 'keep' | 'suspend' | 'remove'
): Promise<FastVideoOfflineAsset[]>;
```

Before implementation, the project must decide:

- whether downloads survive logout;
- whether switching accounts hides, suspends, or releases assets;
- whether device backup/restore is supported;
- whether app reinstall preserves any native key material;
- how queued release is completed after logout.

## 15. Backward compatibility

- Existing streaming source objects remain source-compatible.
- Existing clear offline functions remain available during the beta migration.
- Existing `mediaSession`, PiP, cache, preload, and metric behavior remains unchanged when new options are omitted.
- Cast dependencies are not linked unless explicitly enabled.
- `decoderPolicy` defaults to `system`.
- Offline DRM is rejected with a specific capability error on unsupported platform/device/provider combinations.
- New event fields are additive; ambiguous event ownership is resolved before beta, not patched after stable release.

## 16. API review checklist

The API is ready for implementation only when reviewers can answer “yes” to all items:

- Can an app render every offline state without platform-specific branching?
- Can the library renew/release after app restart without JavaScript callbacks?
- Is every key-like object confined to native code?
- Is delete behavior explicit when the network is unavailable?
- Can clear-content users migrate without rewriting their player source?
- Is remote transport ownership unambiguous?
- Can Cast remain absent from applications that do not enable it?
- Does the decoder API accurately describe Apple limitations?
- Can certification instrumentation be excluded from normal production use?
- Are error codes stable, sanitized, and actionable?
