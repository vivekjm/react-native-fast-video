# Phase 4 Runtime Architecture

## Adaptive loop

Native telemetry is sampled where the platform already knows the truth. Media3 bandwidth/video callbacks and AVPlayer access logs feed FastCore's shared policy. The policy returns a bitrate budget, forward-buffer target, resolution cap and HDR allowance. JavaScript is not part of this control loop.

The bitrate budget is divided across active players before safety factors are applied. Rebuffering, dropped frames, thermal pressure and low-power mode progressively lower the ceiling. User `maxBitrate` remains a hard upper bound.

## Background playback ownership

A React view is not the lifetime owner of background playback. If `source.mediaSession` is true and playback is active when the view is destroyed, native code detaches rendering/listeners but keeps the media player owned by the platform session runtime. A later explicit stop releases it. Normal non-background players still return to the latency-profile pool.

Android uses one Media3 `MediaSession` whose player can be swapped as the focused pooled player changes. Apple installs MPRemoteCommandCenter once, updates MPNowPlayingInfoCenter, and can issue commands directly to the retained AVPlayer after its view disappears.

## Offline storage separation

Transient feed cache and explicit offline media have different correctness requirements. Android therefore maintains a second SimpleCache with `NoOpCacheEvictor` plus DownloadManager's persistent index. Clearing the feed LRU cannot evict an offline item. Apple stores the URL handed back by AVAssetDownloadURLSession; the downloaded package is not moved by the library.

## QoE score

FastCore emits a 0–100 diagnostic score. It penalizes slow first frame, rebuffer ratio/count and dropped-frame ratio. It is deliberately simple, deterministic and cross-platform. It is useful for regression gates and experiment comparison, not as a universal MOS replacement.

## Public control surface

```ts
await configureFastVideoRuntime({
  adaptiveMode: 'balanced',
  cacheMaxBytes: 512 * 1024 * 1024,
  maxPooledPlayersPerMode: 2,
  maxParallelDownloads: 3,
});

await downloadFastVideoOffline(source, { id: 'episode-7', title: 'Episode 7' });
const downloads = await listFastVideoOfflineDownloads();
await pauseFastVideoOfflineDownloads();
await resumeFastVideoOfflineDownloads();
await removeFastVideoOfflineDownload('episode-7');

await stopFastVideoBackgroundPlayback();
```

For Expo background playback, enable the plugin option `backgroundPlayback: true`. That adds the required Android foreground-service permissions and Apple `UIBackgroundModes: ['audio']` entry.

## Playing a durable download

The download id is also the native durable-cache key. Keep the original source URI/type and add `offlineId`:

```ts
<FastVideo
  source={{
    uri: originalHlsUrl,
    type: 'hls',
    offlineId: 'episode-7',
  }}
/>
```

Android switches the entire MediaSource to the non-evicting download cache with network upstream disabled. Apple resolves `offlineId` to the persisted AVAssetDownload package URL. If the requested download is not complete, native emits `E_OFFLINE_NOT_READY` rather than silently falling back to network.
