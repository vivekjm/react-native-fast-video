import { Image } from 'react-native';

import type { FastVideoProps } from './FastVideo.types';

export interface NativeFastVideoDrm {
  type: string;
  licenseUrl: string;
  certificateUrl?: string;
  headers: Record<string, string>;
  contentId?: string;
  multiSession: boolean;
  licenseResponseType: string;
}

export interface NativeFastVideoSubtitle {
  id?: string;
  uri: string;
  mimeType: string;
  language?: string;
  label?: string;
  isDefault: boolean;
}

export interface NativeFastVideoMetadata {
  title?: string;
  artist?: string;
  albumTitle?: string;
  artworkUri?: string;
}

export interface NativeFastVideoSource {
  uri: string;
  type: string;
  headers: Record<string, string>;
  drm?: NativeFastVideoDrm;
  subtitles: NativeFastVideoSubtitle[];
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
  metadata?: NativeFastVideoMetadata;
  mediaSession: boolean;
}

export interface NormalizedFastVideoSource {
  nativeSource: NativeFastVideoSource;
  sourceObject: NativeFastVideoSource;
}

type FastVideoSourceInput = FastVideoProps['source'];
type UnknownRecord = Record<string, unknown>;

export function normalizeFastVideoSource(input: FastVideoSourceInput): NormalizedFastVideoSource {
  const raw = sourceRecord(input);
  const uri = normalizeUri(resolveUri(input, raw), 'source.uri');
  const type = stringValue(raw.type) ?? inferType(uri);
  const headers = normalizeHeaders(raw.headers, 'source.headers');
  const drm = normalizeDrm(raw.drm);
  const subtitles = normalizeSubtitles(raw.subtitles);
  const fallbackUris = normalizeFallbackUris(raw.fallbackUris, uri);
  const latencyMode = normalizeLatencyMode(raw.latencyMode);

  const normalized: NativeFastVideoSource = {
    uri,
    type,
    headers,
    drm,
    subtitles,
    isLive: booleanValue(raw.isLive, false),
    startPositionMs: finiteOptional(raw.startPositionMs, 'source.startPositionMs', 0),
    targetLiveOffsetMs: finiteOptional(raw.targetLiveOffsetMs, 'source.targetLiveOffsetMs', 0),
    customCacheKey: nonEmptyOptional(raw.customCacheKey),
    offlineId: nonEmptyOptional(raw.offlineId),
    preloadIndex: integerOptional(raw.preloadIndex, 'source.preloadIndex', 0),
    fallbackUris,
    maxRetryAttempts: integerValue(raw.maxRetryAttempts, 2, 0, 8),
    retryBackoffMs: finiteValue(raw.retryBackoffMs, 350, 50, 10_000),
    latencyMode,
    metadata: normalizeMetadata(raw.metadata),
    mediaSession: booleanValue(raw.mediaSession, false),
  };

  if (normalized.offlineId && normalized.isLive) {
    throw new TypeError('A live source cannot be opened through offlineId.');
  }

  return { nativeSource: normalized, sourceObject: normalized };
}

function sourceRecord(input: FastVideoSourceInput): UnknownRecord {
  return input !== null && typeof input === 'object' && !Array.isArray(input)
    ? (input as unknown as UnknownRecord)
    : {};
}

function resolveUri(input: FastVideoSourceInput, raw: UnknownRecord): string {
  if (typeof input === 'string') return input;
  if (typeof input === 'number') {
    const resolved = Image.resolveAssetSource(input);
    if (!resolved?.uri) throw new TypeError('Unable to resolve the bundled FastVideo asset.');
    return resolved.uri;
  }

  const uri = raw.uri;
  if (typeof uri === 'number') {
    const resolved = Image.resolveAssetSource(uri);
    if (!resolved?.uri) throw new TypeError('Unable to resolve source.uri as a bundled asset.');
    return resolved.uri;
  }
  if (typeof uri === 'string') return uri;
  throw new TypeError('FastVideo source must be a URI string, bundled asset, or source object.');
}

function normalizeUri(value: string, field: string): string {
  const uri = value.trim();
  if (!uri) throw new TypeError(`${field} must not be empty.`);
  if (/^(?:javascript|vbscript):/i.test(uri)) {
    throw new TypeError(`${field} uses an unsafe URI scheme.`);
  }
  return uri;
}

function normalizeHeaders(value: unknown, field: string): Record<string, string> {
  if (value === undefined || value === null) return {};
  if (typeof value !== 'object' || Array.isArray(value)) {
    throw new TypeError(`${field} must be an object.`);
  }

  const output: Record<string, string> = {};
  for (const [rawName, rawValue] of Object.entries(value as UnknownRecord)) {
    const name = rawName.trim();
    if (!name || /[\r\n:]/.test(name)) throw new TypeError(`${field} contains an invalid header name.`);
    if (typeof rawValue !== 'string') throw new TypeError(`${field}.${name} must be a string.`);
    if (/[\r\n]/.test(rawValue)) throw new TypeError(`${field}.${name} contains a newline.`);
    output[name] = rawValue;
  }
  return output;
}

function normalizeDrm(value: unknown): NativeFastVideoDrm | undefined {
  if (value === undefined || value === null) return undefined;
  if (typeof value !== 'object' || Array.isArray(value)) throw new TypeError('source.drm must be an object.');
  const drm = value as UnknownRecord;
  const type = requiredString(drm.type, 'source.drm.type').toLowerCase();
  const licenseUrl = normalizeUri(requiredString(drm.licenseUrl, 'source.drm.licenseUrl'), 'source.drm.licenseUrl');
  return {
    type,
    licenseUrl,
    certificateUrl: nonEmptyOptional(drm.certificateUrl),
    headers: normalizeHeaders(drm.headers, 'source.drm.headers'),
    contentId: nonEmptyOptional(drm.contentId),
    multiSession: booleanValue(drm.multiSession, false),
    licenseResponseType: stringValue(drm.licenseResponseType) ?? 'raw',
  };
}

function normalizeSubtitles(value: unknown): NativeFastVideoSubtitle[] {
  if (value === undefined || value === null) return [];
  if (!Array.isArray(value)) throw new TypeError('source.subtitles must be an array.');
  return value.map((entry, index) => {
    if (entry === null || typeof entry !== 'object' || Array.isArray(entry)) {
      throw new TypeError(`source.subtitles[${index}] must be an object.`);
    }
    const subtitle = entry as UnknownRecord;
    return {
      id: nonEmptyOptional(subtitle.id),
      uri: normalizeUri(requiredString(subtitle.uri, `source.subtitles[${index}].uri`), `source.subtitles[${index}].uri`),
      mimeType: stringValue(subtitle.mimeType) ?? 'text/vtt',
      language: nonEmptyOptional(subtitle.language),
      label: nonEmptyOptional(subtitle.label),
      isDefault: booleanValue(subtitle.isDefault, false),
    };
  });
}

function normalizeFallbackUris(value: unknown, primary: string): string[] {
  if (value === undefined || value === null) return [];
  if (!Array.isArray(value)) throw new TypeError('source.fallbackUris must be an array.');
  const seen = new Set([primary]);
  const output: string[] = [];
  value.forEach((candidate, index) => {
    if (typeof candidate !== 'string') throw new TypeError(`source.fallbackUris[${index}] must be a string.`);
    const uri = normalizeUri(candidate, `source.fallbackUris[${index}]`);
    if (!seen.has(uri)) {
      seen.add(uri);
      output.push(uri);
    }
  });
  return output;
}

function normalizeMetadata(value: unknown): NativeFastVideoMetadata | undefined {
  if (value === undefined || value === null) return undefined;
  if (typeof value !== 'object' || Array.isArray(value)) throw new TypeError('source.metadata must be an object.');
  const metadata = value as UnknownRecord;
  const normalized: NativeFastVideoMetadata = {
    title: nonEmptyOptional(metadata.title),
    artist: nonEmptyOptional(metadata.artist),
    albumTitle: nonEmptyOptional(metadata.albumTitle),
    artworkUri: nonEmptyOptional(metadata.artworkUri),
  };
  return Object.values(normalized).some((item) => item !== undefined) ? normalized : undefined;
}

function normalizeLatencyMode(value: unknown): string {
  return value === 'lowLatency' || value === 'quality' || value === 'memorySaver' ? value : 'balanced';
}

function inferType(uri: string): string {
  const path = uri.split(/[?#]/, 1)[0]?.toLowerCase() ?? uri.toLowerCase();
  if (path.endsWith('.m3u8')) return 'hls';
  if (path.endsWith('.mpd')) return 'dash';
  if (path.endsWith('.ism') || path.includes('.ism/manifest')) return 'smoothstreaming';
  return 'auto';
}

function requiredString(value: unknown, field: string): string {
  const string = stringValue(value);
  if (!string) throw new TypeError(`${field} must be a non-empty string.`);
  return string;
}

function stringValue(value: unknown): string | undefined {
  return typeof value === 'string' && value.trim() ? value.trim() : undefined;
}

function nonEmptyOptional(value: unknown): string | undefined {
  return stringValue(value);
}

function booleanValue(value: unknown, fallback: boolean): boolean {
  return typeof value === 'boolean' ? value : fallback;
}

function finiteOptional(value: unknown, field: string, minimum: number): number | undefined {
  if (value === undefined || value === null) return undefined;
  if (typeof value !== 'number' || !Number.isFinite(value) || value < minimum) {
    throw new TypeError(`${field} must be a finite number greater than or equal to ${minimum}.`);
  }
  return value;
}

function integerOptional(value: unknown, field: string, minimum: number): number | undefined {
  const number = finiteOptional(value, field, minimum);
  if (number === undefined) return undefined;
  if (!Number.isInteger(number)) throw new TypeError(`${field} must be an integer.`);
  return number;
}

function finiteValue(value: unknown, fallback: number, minimum: number, maximum: number): number {
  if (value === undefined || value === null) return fallback;
  if (typeof value !== 'number' || !Number.isFinite(value)) return fallback;
  return Math.min(maximum, Math.max(minimum, value));
}

function integerValue(value: unknown, fallback: number, minimum: number, maximum: number): number {
  return Math.round(finiteValue(value, fallback, minimum, maximum));
}
