import type { FastVideoProps } from './FastVideo.types';
import { normalizeFastVideoSource } from './normalizeSource';

export interface FastVideoWebRuntimeStats {
  platform: 'web';
  cacheStrategy: 'browser-managed';
  cacheBudgetControllable: false;
  pooledPlayers: 0;
  preloadedSources: number;
  offlineDownloads: 0;
}

let preloadedSources = 0;
const preloadElements = new Set<HTMLLinkElement>();

export async function getFastVideoCapabilities(): Promise<Record<string, unknown>> {
  const video = typeof document === 'undefined' ? null : document.createElement('video');
  const pictureInPicture =
    typeof document !== 'undefined' &&
    'pictureInPictureEnabled' in document &&
    Boolean((document as Document & { pictureInPictureEnabled?: boolean }).pictureInPictureEnabled);
  return {
    platform: 'web',
    nativeEngine: 'HTMLMediaElement',
    hls: video?.canPlayType('application/vnd.apple.mpegurl') !== '',
    dash: false,
    pictureInPicture,
    offlineDownloads: false,
    cacheBudgetControllable: false,
  };
}

export async function preloadFastVideoSources(
  sources: FastVideoProps['source'][],
  currentIndex = 0
): Promise<Record<string, unknown>> {
  clearFastVideoPreloads();
  if (typeof document === 'undefined') {
    return { platform: 'web', accepted: 0, strategy: 'server-noop', currentIndex };
  }

  const candidates = sources
    .map((source, index) => ({ source: normalizeFastVideoSource(source).sourceObject, index }))
    .sort((left, right) => Math.abs(left.index - currentIndex) - Math.abs(right.index - currentIndex))
    .slice(0, 3);

  for (const candidate of candidates) {
    const link = document.createElement('link');
    link.rel = 'preload';
    link.as = 'video';
    link.href = candidate.source.uri;
    link.crossOrigin = 'anonymous';
    document.head.appendChild(link);
    preloadElements.add(link);
  }
  preloadedSources = candidates.length;
  return {
    platform: 'web',
    accepted: candidates.length,
    strategy: 'link-preload',
    currentIndex,
  };
}

export async function focusFastVideoPreloads(
  currentIndex: number,
  velocityItemsPerSecond = 0
): Promise<Record<string, unknown>> {
  return {
    platform: 'web',
    actualIndex: finiteInteger(currentIndex, 'currentIndex'),
    predictedIndex: finiteInteger(
      currentIndex + Math.sign(velocityItemsPerSecond) * Math.min(2, Math.floor(Math.abs(velocityItemsPerSecond))),
      'predictedIndex'
    ),
    velocityItemsPerSecond: finite(velocityItemsPerSecond, 'velocityItemsPerSecond'),
    confidence: 0,
  };
}

export function clearFastVideoPreloads(): void {
  for (const element of preloadElements) element.remove();
  preloadElements.clear();
  preloadedSources = 0;
}

export async function configureFastVideoRuntime(
  _options: Record<string, unknown> = {}
): Promise<FastVideoWebRuntimeStats> {
  return getFastVideoRuntimeStats();
}

export async function getFastVideoRuntimeStats(): Promise<FastVideoWebRuntimeStats> {
  return {
    platform: 'web',
    cacheStrategy: 'browser-managed',
    cacheBudgetControllable: false,
    pooledPlayers: 0,
    preloadedSources,
    offlineDownloads: 0,
  };
}

export async function clearFastVideoCache(): Promise<FastVideoWebRuntimeStats> {
  // Browser HTTP/media caches are controlled by browser policy. Do not pretend a JS call can
  // reliably clear them across origins.
  return getFastVideoRuntimeStats();
}

export async function downloadFastVideoOffline(): Promise<never> {
  throw unsupportedOffline();
}

export async function removeFastVideoOfflineDownload(): Promise<never> {
  throw unsupportedOffline();
}

export async function listFastVideoOfflineDownloads(): Promise<[]> {
  return [];
}

export async function pauseFastVideoOfflineDownloads(): Promise<void> {}
export async function resumeFastVideoOfflineDownloads(): Promise<void> {}
export async function stopFastVideoBackgroundPlayback(): Promise<void> {}
export async function resetFastVideoNetworkDiagnostics(): Promise<void> {}

function unsupportedOffline(): Error {
  const error = new Error(
    'Durable offline downloads are unavailable in the web runtime; use a native development build.'
  );
  error.name = 'E_WEB_OFFLINE_UNSUPPORTED';
  return error;
}

function finite(value: number, name: string): number {
  if (!Number.isFinite(value)) throw new TypeError(`${name} must be finite.`);
  return value;
}

function finiteInteger(value: number, name: string): number {
  return Math.max(0, Math.round(finite(value, name)));
}
