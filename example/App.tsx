import { StatusBar } from 'expo-status-bar';
import { useEffect, useState } from 'react';
import { SafeAreaView, ScrollView, StyleSheet, Text, View } from 'react-native';
import {
  FastVideo,
  FastVideoControls,
  configureFastVideoRuntime,
  getFastVideoCapabilities,
  getFastVideoRuntimeStats,
  downloadFastVideoOffline,
  listFastVideoOfflineDownloads,
  stopFastVideoBackgroundPlayback,
  preloadFastVideoSources,
  useFastVideoController,
  type FastVideoCapabilities,
  type FastVideoRuntimeStats,
  type FastVideoOfflineDownload,
} from 'react-native-fast-video';

const HLS_SAMPLE = 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8';
const PRELOAD_SAMPLE = { uri: HLS_SAMPLE, type: 'hls' as const, preloadIndex: 0 };

export default function App() {
  const controller = useFastVideoController();
  const [capabilities, setCapabilities] = useState<FastVideoCapabilities>();
  const [runtimeStats, setRuntimeStats] = useState<FastVideoRuntimeStats>();
  const [downloads, setDownloads] = useState<FastVideoOfflineDownload[]>([]);

  useEffect(() => {
    void configureFastVideoRuntime({
      cacheMaxBytes: 256 * 1024 * 1024,
      maxPooledPlayersPerMode: 2,
      adaptiveMode: 'balanced',
      maxParallelDownloads: 2,
    }).then(setRuntimeStats);
  }, []);

  return (
    <SafeAreaView style={styles.safeArea}>
      <StatusBar style="light" />
      <ScrollView contentContainerStyle={styles.content}>
        <Text style={styles.title}>Fast Video Lab</Text>
        <Text style={styles.subtitle}>
          Native HLS playback with coalesced C++ telemetry. Use physical devices for meaningful results.
        </Text>

        <View style={styles.playerShell}>
          <FastVideo
            ref={controller.ref}
            source={{ ...PRELOAD_SAMPLE, latencyMode: 'balanced', mediaSession: true, metadata: { title: 'Fast Video Lab HLS', artist: 'react-native-fast-video' } }}
            style={styles.player}
            autoplay
            contentFit="contain"
            {...controller.handlers}
          />
          <FastVideoControls
            player={controller.ref}
            positionMs={controller.state.positionMs}
            durationMs={controller.state.durationMs}
            isPlaying={controller.state.playbackState === 'playing'}
            isLive={controller.state.isLive}
          />
        </View>

        <Text style={styles.metric}>
          State: {controller.state.playbackState} · Buffering: {String(controller.state.buffering)}
        </Text>
        <Text style={styles.metric}>
          TTFF: {controller.state.metrics?.timeToFirstFrameMs ?? '—'} ms · QoE:{' '}
          {controller.state.metrics?.qoeScore?.toFixed?.(1) ?? '—'} · Rebuffers: {controller.state.metrics?.rebufferCount ?? 0}
        </Text>
        <Text
          accessibilityRole="button"
          style={styles.action}
          onPress={() => void preloadFastVideoSources([PRELOAD_SAMPLE], 0)}
        >
          Warm native preload
        </Text>
        <Text
          accessibilityRole="button"
          style={styles.action}
          onPress={() => void getFastVideoCapabilities().then(setCapabilities)}
        >
          Read native capabilities
        </Text>
        <Text
          accessibilityRole="button"
          style={styles.action}
          onPress={() => void getFastVideoRuntimeStats().then(setRuntimeStats)}
        >
          Read runtime/cache stats
        </Text>
        <Text
          accessibilityRole="button"
          style={styles.action}
          onPress={() => void downloadFastVideoOffline(PRELOAD_SAMPLE, { id: 'lab-hls', title: 'Fast Video Lab HLS' }).then(() => listFastVideoOfflineDownloads()).then(setDownloads)}
        >
          Download HLS for offline playback
        </Text>
        <Text
          accessibilityRole="button"
          style={styles.action}
          onPress={() => void listFastVideoOfflineDownloads().then(setDownloads)}
        >
          List offline downloads
        </Text>
        <Text
          accessibilityRole="button"
          style={styles.action}
          onPress={() => void stopFastVideoBackgroundPlayback()}
        >
          Stop retained background playback
        </Text>
        {capabilities ? (
          <Text selectable style={styles.code}>{JSON.stringify(capabilities, null, 2)}</Text>
        ) : null}
        {runtimeStats ? (
          <Text selectable style={styles.code}>{JSON.stringify(runtimeStats, null, 2)}</Text>
        ) : null}
        {downloads.length ? (
          <Text selectable style={styles.code}>{JSON.stringify(downloads, null, 2)}</Text>
        ) : null}
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safeArea: { backgroundColor: '#07090d', flex: 1 },
  content: { gap: 16, padding: 20 },
  title: { color: 'white', fontSize: 30, fontWeight: '800' },
  subtitle: { color: '#aeb7c6', lineHeight: 21 },
  playerShell: { backgroundColor: '#111620', borderRadius: 14, overflow: 'hidden' },
  player: { aspectRatio: 16 / 9, width: '100%' },
  metric: { color: '#d8e0ec' },
  action: { color: '#66d9ff', fontSize: 16, fontWeight: '700', paddingVertical: 8 },
  code: { backgroundColor: '#111620', color: '#b8ffcf', fontFamily: 'monospace', padding: 12 },
});
