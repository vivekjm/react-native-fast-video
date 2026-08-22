import { Image } from 'react-native';

import type {
  FastVideoSource,
  FastVideoSourceObject,
  FastVideoSubtitle,
} from './FastVideo.types';

export interface NativeFastVideoSource {
  uri: string;
  type: string;
  headers: Record<string, string>;
  drm?: Record<string, unknown>;
  subtitles: Array<Required<Pick<FastVideoSubtitle, 'uri' | 'mimeType' | 'isDefault'>> & FastVideoSubtitle>;
  isLive: boolean;
  startPositionMs?: number;
  targetLiveOffsetMs?: number;
  customCacheKey?: string;
  offlineId?: string;
  preloadIndex?: number;
  fallbackUris: string[];
  maxRetryAttempts: number;
  retryBackoffMs: number;
  latencyMode: string;
  metadata?: Record<string, string | undefined>;
  mediaSession: boolean;
}

function resolveUri(uri: string | number): string {
  if (typeof uri === 'string') return uri;
  const resolved = Image.resolveAssetSource(uri);
  if (!resolved?.uri) {
    throw new Error(`Unable to resolve bundled video asset: ${String(uri)}`);
  }
  return resolved.uri;
}

export function normalizeFastVideoSource(source: FastVideoSource): {
  nativeSource: NativeFastVideoSource;
  sourceObject: FastVideoSourceObject;
} {
  const object: FastVideoSourceObject =
    typeof source === 'string' || typeof source === 'number' ? { uri: source } : source;

  if (object.uri === '' || object.uri === null || object.uri === undefined) {
    throw new Error('FastVideo source.uri must be a non-empty URI or bundled asset number.');
  }

  return {
    sourceObject: object,
    nativeSource: {
      uri: resolveUri(object.uri),
      type: object.type ?? 'auto',
      headers: object.headers ?? {},
      drm: object.drm as unknown as Record<string, unknown> | undefined,
      subtitles: (object.subtitles ?? []).map((subtitle) => ({
        ...subtitle,
        mimeType: subtitle.mimeType ?? 'text/vtt',
        isDefault: subtitle.isDefault ?? false,
      })),
      isLive: object.isLive ?? false,
      startPositionMs: finiteOptional(object.startPositionMs),
      targetLiveOffsetMs: finiteOptional(object.targetLiveOffsetMs),
      customCacheKey: object.customCacheKey,
      offlineId: object.offlineId,
      preloadIndex: integerOptional(object.preloadIndex),
      fallbackUris: (object.fallbackUris ?? []).filter((uri) => typeof uri === 'string' && uri.length > 0),
      maxRetryAttempts: integerClamp(object.maxRetryAttempts, 2, 0, 8),
      retryBackoffMs: integerClamp(object.retryBackoffMs, 350, 50, 10_000),
      latencyMode: object.latencyMode ?? 'balanced',
      metadata: object.metadata,
      mediaSession: object.mediaSession ?? false,
    },
  };
}

function finiteOptional(value: number | undefined): number | undefined {
  return value !== undefined && Number.isFinite(value) ? value : undefined;
}

function integerOptional(value: number | undefined): number | undefined {
  return value !== undefined && Number.isInteger(value) && value >= 0 ? value : undefined;
}

function integerClamp(value: number | undefined, fallback: number, min: number, max: number): number {
  if (value === undefined || !Number.isFinite(value)) return fallback;
  return Math.max(min, Math.min(max, Math.trunc(value)));
}
