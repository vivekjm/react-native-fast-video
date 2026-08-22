import type { StyleProp, ViewStyle } from 'react-native';

export type FastVideoSourceType = 'auto' | 'progressive' | 'hls' | 'dash' | 'smoothstreaming';
export type FastVideoLatencyMode = 'lowLatency' | 'balanced' | 'quality' | 'memorySaver';
export type FastVideoSurfaceType = 'surface' | 'texture';
export type FastVideoContentFit = 'contain' | 'cover' | 'fill' | 'none';

export interface FastVideoMetadata {
  title?: string;
  artist?: string;
  albumTitle?: string;
  artworkUri?: string;
}

export type FastVideoAdaptiveMode = 'off' | 'conservative' | 'balanced' | 'aggressive';
export type FastVideoPlaybackState =
  | 'idle'
  | 'loading'
  | 'ready'
  | 'playing'
  | 'paused'
  | 'buffering'
  | 'ended'
  | 'error'
  | 'released';

export interface FastVideoWidevineDrm {
  type: 'widevine';
  licenseUrl: string;
  headers?: Record<string, string>;
  multiSession?: boolean;
}

export interface FastVideoFairPlayDrm {
  type: 'fairplay';
  certificateUrl: string;
  licenseUrl: string;
  headers?: Record<string, string>;
  contentId?: string;
  licenseResponseType?: 'raw' | 'base64';
}

export type FastVideoDrm = FastVideoWidevineDrm | FastVideoFairPlayDrm;

export interface FastVideoSubtitle {
  id?: string;
  uri: string;
  mimeType?: 'text/vtt' | 'application/x-subrip' | 'application/ttml+xml' | string;
  language?: string;
  label?: string;
  isDefault?: boolean;
}

export interface FastVideoSourceObject {
  uri: string | number;
  type?: FastVideoSourceType;
  headers?: Record<string, string>;
  drm?: FastVideoDrm;
  subtitles?: FastVideoSubtitle[];
  isLive?: boolean;
  startPositionMs?: number;
  targetLiveOffsetMs?: number;
  customCacheKey?: string;
  /** Play from the durable native offline store using this download id. */
  offlineId?: string;
  /** Index used by native preload managers for feed/carousel prioritization. */
  preloadIndex?: number;
  /** CDN/source failover candidates tried natively after retry attempts are exhausted. */
  fallbackUris?: string[];
  /** Retry attempts per URI before moving to the next fallback. Defaults to 2. */
  maxRetryAttempts?: number;
  /** Base native retry delay. Exponential backoff is applied. Defaults to 350ms. */
  retryBackoffMs?: number;
  latencyMode?: FastVideoLatencyMode;
  metadata?: FastVideoMetadata;
  /** Enables lock-screen/system media controls and background audio handoff. */
  mediaSession?: boolean;
}

export type FastVideoSource = string | number | FastVideoSourceObject;

export interface FastVideoTrack {
  id: string;
  nativeId?: string;
  label?: string;
  language?: string;
  mimeType?: string;
  codecs?: string;
  bitrate?: number;
  width?: number;
  height?: number;
  frameRate?: number;
  selected: boolean;
  supported: boolean;
}

export interface FastVideoTracks {
  video: FastVideoTrack[];
  audio: FastVideoTrack[];
  text: FastVideoTrack[];
}

export interface FastVideoProgress {
  positionMs: number;
  durationMs: number;
  bufferedPositionMs: number;
  liveOffsetMs?: number;
  isLive: boolean;
  isPlaying: boolean;
  playbackState: FastVideoPlaybackState;
}

export interface FastVideoMetrics {
  state: FastVideoPlaybackState;
  playWhenReady: boolean;
  sequence: number;
  timeToFirstFrameMs: number;
  lastSeekLatencyMs: number;
  totalRebufferMs: number;
  activePlaybackMs: number;
  rebufferRatio: number;
  rebufferCount: number;
  renderedFrames: number;
  droppedFrames: number;
  droppedFrameRatio: number;
  /** Native 0-100 QoE score combining TTFF, rebuffering and dropped frames. */
  qoeScore: number;
  bytesTransferred: number;
  estimatedBitrateBps: number;
  predictedBandwidthBps: number;
  bandwidthConfidence: number;
  bandwidthVolatility: number;
  bandwidthSamples: number;
  averageFrameProcessingOffsetUs: number;
  frameProcessingSamples: number;
  positionMs: number;
  durationMs: number;
  bufferedPositionMs: number;
  liveOffsetMs: number;
  isLive: boolean;
  firstFrameRendered: boolean;
  startupPath?: string;
  cachedBytesRead?: number;
  cdn?: FastVideoCdnDiagnostics;
}

export interface FastVideoError {
  code: string;
  message: string;
  nativeCode?: string;
}

export interface FastVideoCapabilities {
  platform: 'android' | 'ios' | 'web';
  [key: string]: unknown;
}

export interface FastVideoPreloadResult {
  platform: 'android' | 'ios' | 'web';
  accepted: number;
  strategy: 'media3-memory' | 'media3-memory-disk' | 'avasset-warm' | 'browser-preconnect' | 'unsupported';
}


export interface FastVideoViewportIntent {
  actualIndex: number;
  predictedIndex: number;
  forwardRadius: number;
  backwardRadius: number;
  confidence: number;
}

export interface FastVideoCdnDiagnostics {
  origin: string;
  score: number;
  successes: number;
  failures: number;
  consecutiveFailures: number;
  averageTtffMs: number;
  averageResponseMs: number;
}
export interface FastVideoRuntimeConfig {
  /** Android LRU disk cache budget. Configure before mounting/preloading for guaranteed application. */
  cacheMaxBytes?: number;
  /** Maximum idle native players retained per latency profile. */
  maxPooledPlayersPerMode?: number;
  /** C++ driven bandwidth/thermal/resource arbitration. Defaults to balanced. */
  adaptiveMode?: FastVideoAdaptiveMode;
  /** Max parallel durable offline downloads on Android. */
  maxParallelDownloads?: number;
}

export interface FastVideoRuntimeStats {
  platform: 'android' | 'ios' | 'web';
  cacheBytes?: number;
  cacheMaxBytes?: number;
  pooledPlayers?: number;
  poolSizePerLatencyMode?: number;
  maxPooledPlayers?: number;
  warmedAssets?: number;
  latencyRuntimes?: number;
  cacheStrategy?: string;
  cacheBudgetControllable?: boolean;
  applied?: boolean;
  requiresRuntimeReset?: boolean;
  adaptivePlaybackEnabled?: boolean;
  activePlayers?: number;
  networkClass?: string;
  thermalClass?: number;
  lowPowerMode?: boolean;
  offlineDownloads?: number;
  offlineCacheBytes?: number;
  cdnOriginsTracked?: number;
  cdnHealth?: Array<{ origin: string; score: number; failures: number; successes: number }>;
}

export interface FastVideoOfflineDownload {
  id: string;
  uri: string;
  state: 'queued' | 'downloading' | 'stopped' | 'completed' | 'failed' | 'removing' | 'restarting' | 'unknown';
  bytesDownloaded?: number;
  percentDownloaded?: number;
  contentLength?: number;
  localUri?: string;
  failureReason?: number | string;
}

export interface FastVideoOfflineOptions {
  id?: string;
  title?: string;
  prefersHDR?: boolean;
}

export interface FastVideoRef {
  play(): Promise<void>;
  pause(): Promise<void>;
  replay(): Promise<void>;
  seekTo(positionMs: number): Promise<void>;
  seekBy(deltaMs: number): Promise<void>;
  goToLive(): Promise<void>;
  selectTrack(type: 'video' | 'audio' | 'text', id: string | null): Promise<void>;
  getSnapshot(): Promise<FastVideoMetrics>;
  enterPictureInPicture(): Promise<boolean>;
  stopPictureInPicture(): Promise<void>;
}

export interface FastVideoProps {
  source: FastVideoSource;
  style?: StyleProp<ViewStyle>;
  testID?: string;
  autoplay?: boolean;
  paused?: boolean;
  muted?: boolean;
  volume?: number;
  rate?: number;
  repeat?: boolean;
  latencyMode?: FastVideoLatencyMode;
  progressIntervalMs?: number;
  surfaceType?: FastVideoSurfaceType;
  contentFit?: FastVideoContentFit;
  maxBitrate?: number;
  preferredAudioLanguage?: string;
  preferredTextLanguage?: string;
  allowsExternalPlayback?: boolean;
  accessible?: boolean;
  accessibilityLabel?: string;
  onLoadStart?: (event: { uri: string }) => void;
  onReady?: (event: { durationMs: number; isLive: boolean }) => void;
  onPlaybackStateChange?: (event: { state: FastVideoPlaybackState }) => void;
  onBuffer?: (event: { buffering: boolean }) => void;
  onFirstFrame?: (event: { timestampMs: number; timeToFirstFrameMs: number; startupPath: 'cold' | 'disk-cache' | 'memory-preloaded' | 'asset-warmed' | 'offline' | string }) => void;
  onProgress?: (event: FastVideoProgress) => void;
  onMetrics?: (event: FastVideoMetrics) => void;
  onTracksChanged?: (event: FastVideoTracks) => void;
  onVideoSize?: (event: { width: number; height: number; pixelRatio: number }) => void;
  onEnd?: () => void;
  onError?: (event: FastVideoError) => void;
  onPictureInPictureChange?: (event: { active: boolean }) => void;
  onAdaptiveDecision?: (event: Record<string, unknown>) => void;
}

export interface FastVideoControllerState {
  playbackState: FastVideoPlaybackState;
  positionMs: number;
  durationMs: number;
  bufferedPositionMs: number;
  liveOffsetMs?: number;
  isLive: boolean;
  buffering: boolean;
  tracks: FastVideoTracks;
  metrics?: FastVideoMetrics;
  error?: FastVideoError;
}
