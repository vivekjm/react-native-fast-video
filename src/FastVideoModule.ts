import { Platform } from 'react-native';
import { requireNativeModule } from 'expo-modules-core';

import type { FastVideoCapabilities, FastVideoOfflineDownload, FastVideoOfflineOptions, FastVideoPreloadResult, FastVideoRuntimeConfig, FastVideoViewportIntent, FastVideoRuntimeStats, FastVideoSource } from './FastVideo.types';
import { normalizeFastVideoSource } from './normalizeSource';

interface NativeFastVideoModule {
  getCapabilities(): FastVideoCapabilities | Promise<FastVideoCapabilities>;
  preload(sources: ReturnType<typeof normalizeFastVideoSource>['nativeSource'][], currentIndex: number): FastVideoPreloadResult | Promise<FastVideoPreloadResult>;
  focusPreloads(currentIndex: number, velocityItemsPerSecond: number): FastVideoViewportIntent | Promise<FastVideoViewportIntent>;
  clearPreloads(): void | Promise<void>;
  configureRuntime(cacheMaxBytes?: number, maxPooledPlayersPerMode?: number, adaptiveMode?: string, maxParallelDownloads?: number): FastVideoRuntimeStats | Promise<FastVideoRuntimeStats>;
  getRuntimeStats(): FastVideoRuntimeStats | Promise<FastVideoRuntimeStats>;
  clearCache(): FastVideoRuntimeStats | Promise<FastVideoRuntimeStats>;
  downloadOffline(source: ReturnType<typeof normalizeFastVideoSource>['nativeSource'], id?: string, title?: string): FastVideoOfflineDownload | Promise<FastVideoOfflineDownload>;
  removeOfflineDownload(id: string): unknown | Promise<unknown>;
  listOfflineDownloads(): FastVideoOfflineDownload[] | Promise<FastVideoOfflineDownload[]>;
  pauseOfflineDownloads(): void | Promise<void>;
  resumeOfflineDownloads(): void | Promise<void>;
  stopBackgroundPlayback(): void | Promise<void>;
  resetNetworkDiagnostics(): void | Promise<void>;
}

let cachedModule: NativeFastVideoModule | undefined;

function nativeModule(): NativeFastVideoModule {
  if (Platform.OS === 'web') {
    return {
      getCapabilities: () => ({
        platform: 'web',
        pictureInPicture: typeof document !== 'undefined' && 'pictureInPictureEnabled' in document,
      }),
      preload: (sources) => {
        if (typeof document !== 'undefined') {
          for (const source of sources.slice(0, 4)) {
            try {
              const link = document.createElement('link');
              link.rel = 'preconnect';
              link.href = new URL(source.uri, document.baseURI).origin;
              document.head.appendChild(link);
            } catch {
              // Ignore malformed/non-network URLs on web.
            }
          }
        }
        return { platform: 'web', accepted: sources.length, strategy: 'browser-preconnect' };
      },
      focusPreloads: (currentIndex) => ({ actualIndex: currentIndex, predictedIndex: currentIndex, forwardRadius: 0, backwardRadius: 0, confidence: 0 }),
      clearPreloads: () => undefined,
      configureRuntime: () => ({ platform: 'web', cacheStrategy: 'browser-managed', cacheBudgetControllable: false }),
      getRuntimeStats: () => ({ platform: 'web', cacheStrategy: 'browser-managed', cacheBudgetControllable: false }),
      clearCache: () => ({ platform: 'web', cacheStrategy: 'browser-managed', cacheBudgetControllable: false }),
      downloadOffline: async () => { throw new Error('Durable offline downloads are not managed by react-native-fast-video on web.'); },
      removeOfflineDownload: () => undefined,
      listOfflineDownloads: () => [],
      pauseOfflineDownloads: () => undefined,
      resumeOfflineDownloads: () => undefined,
      stopBackgroundPlayback: () => undefined,
      resetNetworkDiagnostics: () => undefined,
    };
  }
  cachedModule ??= requireNativeModule<NativeFastVideoModule>('ReactNativeFastVideo');
  return cachedModule;
}

export async function getFastVideoCapabilities(): Promise<FastVideoCapabilities> {
  return await nativeModule().getCapabilities();
}

export async function preloadFastVideoSources(
  sources: FastVideoSource[],
  currentIndex = 0
): Promise<FastVideoPreloadResult> {
  const normalized = sources.map((source, index) => {
    const value = normalizeFastVideoSource(source).nativeSource;
    return { ...value, preloadIndex: value.preloadIndex ?? index };
  });
  return await nativeModule().preload(normalized, Math.max(0, Math.trunc(currentIndex)));
}

export async function focusFastVideoPreloads(currentIndex: number, velocityItemsPerSecond = 0): Promise<FastVideoViewportIntent> {
  const velocity = Number.isFinite(velocityItemsPerSecond) ? velocityItemsPerSecond : 0;
  return await nativeModule().focusPreloads(Math.max(0, Math.trunc(currentIndex)), velocity);
}

export async function clearFastVideoPreloads(): Promise<void> {
  await nativeModule().clearPreloads();
}

export async function configureFastVideoRuntime(config: FastVideoRuntimeConfig = {}): Promise<FastVideoRuntimeStats> {
  const cacheMaxBytes = config.cacheMaxBytes !== undefined && Number.isFinite(config.cacheMaxBytes)
    ? Math.max(0, Math.trunc(config.cacheMaxBytes))
    : undefined;
  const maxPooledPlayersPerMode = config.maxPooledPlayersPerMode !== undefined && Number.isFinite(config.maxPooledPlayersPerMode)
    ? Math.max(0, Math.trunc(config.maxPooledPlayersPerMode))
    : undefined;
  const adaptiveMode = config.adaptiveMode ?? 'balanced';
  const maxParallelDownloads = config.maxParallelDownloads !== undefined && Number.isFinite(config.maxParallelDownloads)
    ? Math.max(1, Math.min(6, Math.trunc(config.maxParallelDownloads)))
    : undefined;
  return await nativeModule().configureRuntime(cacheMaxBytes, maxPooledPlayersPerMode, adaptiveMode, maxParallelDownloads);
}

export async function getFastVideoRuntimeStats(): Promise<FastVideoRuntimeStats> {
  return await nativeModule().getRuntimeStats();
}

export async function clearFastVideoCache(): Promise<FastVideoRuntimeStats> {
  return await nativeModule().clearCache();
}


export async function downloadFastVideoOffline(source: FastVideoSource, options: FastVideoOfflineOptions = {}): Promise<FastVideoOfflineDownload> {
  const normalized = normalizeFastVideoSource(source).nativeSource;
  return await nativeModule().downloadOffline(normalized, options.id, options.title);
}

export async function removeFastVideoOfflineDownload(id: string): Promise<void> {
  await nativeModule().removeOfflineDownload(id);
}

export async function listFastVideoOfflineDownloads(): Promise<FastVideoOfflineDownload[]> {
  return await nativeModule().listOfflineDownloads();
}

export async function pauseFastVideoOfflineDownloads(): Promise<void> {
  await nativeModule().pauseOfflineDownloads();
}

export async function resumeFastVideoOfflineDownloads(): Promise<void> {
  await nativeModule().resumeOfflineDownloads();
}

export async function stopFastVideoBackgroundPlayback(): Promise<void> {
  await nativeModule().stopBackgroundPlayback();
}

export async function resetFastVideoNetworkDiagnostics(): Promise<void> {
  await nativeModule().resetNetworkDiagnostics();
}
