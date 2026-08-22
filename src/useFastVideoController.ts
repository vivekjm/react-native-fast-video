import { useCallback, useMemo, useRef, useState } from 'react';

import type {
  FastVideoControllerState,
  FastVideoError,
  FastVideoMetrics,
  FastVideoProgress,
  FastVideoProps,
  FastVideoRef,
  FastVideoTracks,
} from './FastVideo.types';

const emptyTracks: FastVideoTracks = { video: [], audio: [], text: [] };

export function useFastVideoController() {
  const ref = useRef<FastVideoRef | null>(null);
  const [state, setState] = useState<FastVideoControllerState>({
    playbackState: 'idle',
    positionMs: 0,
    durationMs: 0,
    bufferedPositionMs: 0,
    isLive: false,
    buffering: false,
    tracks: emptyTracks,
  });

  const onProgress = useCallback((progress: FastVideoProgress) => {
    setState((current) => ({
      ...current,
      playbackState: progress.playbackState,
      positionMs: progress.positionMs,
      durationMs: progress.durationMs,
      bufferedPositionMs: progress.bufferedPositionMs,
      liveOffsetMs: progress.liveOffsetMs,
      isLive: progress.isLive,
    }));
  }, []);

  const onMetrics = useCallback((metrics: FastVideoMetrics) => {
    setState((current) => ({ ...current, metrics }));
  }, []);

  const onTracksChanged = useCallback((tracks: FastVideoTracks) => {
    setState((current) => ({ ...current, tracks }));
  }, []);

  const onError = useCallback((error: FastVideoError) => {
    setState((current) => ({ ...current, error, playbackState: 'error' }));
  }, []);

  const handlers = useMemo<Pick<
    FastVideoProps,
    | 'onProgress'
    | 'onMetrics'
    | 'onTracksChanged'
    | 'onError'
    | 'onBuffer'
    | 'onPlaybackStateChange'
  >>(() => ({
    onProgress,
    onMetrics,
    onTracksChanged,
    onError,
    onBuffer: ({ buffering }) => setState((current) => ({ ...current, buffering })),
    onPlaybackStateChange: ({ state: playbackState }) =>
      setState((current) => ({ ...current, playbackState })),
  }), [onError, onMetrics, onProgress, onTracksChanged]);

  return {
    ref,
    state,
    handlers,
    play: () => ref.current?.play(),
    pause: () => ref.current?.pause(),
    seekTo: (positionMs: number) => ref.current?.seekTo(positionMs),
    goToLive: () => ref.current?.goToLive(),
  } as const;
}
