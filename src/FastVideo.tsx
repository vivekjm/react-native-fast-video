import {
  forwardRef,
  useImperativeHandle,
  useMemo,
  useRef,
  type ForwardedRef,
  type Ref,
  type RefObject,
} from 'react';
import type { NativeSyntheticEvent, ViewProps } from 'react-native';
import { requireNativeView } from 'expo-modules-core';

import type {
  FastVideoError,
  FastVideoMetrics,
  FastVideoProgress,
  FastVideoProps,
  FastVideoRef,
  FastVideoTracks,
} from './FastVideo.types';
import { normalizeFastVideoSource, type NativeFastVideoSource } from './normalizeSource';

interface NativeFastVideoRef {
  play(): Promise<void>;
  pause(): Promise<void>;
  replay(): Promise<void>;
  seekTo(positionMs: number): Promise<void>;
  seekBy(deltaMs: number): Promise<void>;
  goToLive(): Promise<void>;
  selectTrack(type: string, id: string | null): Promise<void>;
  getSnapshot(): Promise<FastVideoMetrics>;
  enterPictureInPicture(): Promise<boolean>;
  stopPictureInPicture?(): Promise<void>;
}

type EventHandler<T> = (event: NativeSyntheticEvent<T>) => void;

interface NativeFastVideoProps extends ViewProps {
  ref?: Ref<NativeFastVideoRef>;
  source: NativeFastVideoSource;
  autoplay: boolean;
  paused: boolean;
  muted: boolean;
  volume: number;
  rate: number;
  repeat: boolean;
  latencyMode: string;
  progressIntervalMs: number;
  surfaceType: string;
  contentFit: string;
  maxBitrate?: number;
  preferredAudioLanguage?: string;
  preferredTextLanguage?: string;
  allowsExternalPlayback: boolean;
  onLoadStart?: EventHandler<{ uri: string }>;
  onReady?: EventHandler<{ durationMs: number; isLive: boolean }>;
  onPlaybackStateChange?: EventHandler<{ state: FastVideoMetrics['state'] }>;
  onBuffer?: EventHandler<{ buffering: boolean }>;
  onFirstFrame?: EventHandler<{ timestampMs: number; timeToFirstFrameMs: number; startupPath: string }>;
  onProgress?: EventHandler<FastVideoProgress>;
  onMetrics?: EventHandler<FastVideoMetrics>;
  onAdaptiveDecision?: EventHandler<Record<string, unknown>>;
  onTracksChanged?: EventHandler<FastVideoTracks>;
  onVideoSize?: EventHandler<{ width: number; height: number; pixelRatio: number }>;
  onEnd?: EventHandler<Record<string, never>>;
  onError?: EventHandler<FastVideoError>;
  onPictureInPictureChange?: EventHandler<{ active: boolean }>;
}

const NativeFastVideo = requireNativeView<NativeFastVideoProps>(
  'ReactNativeFastVideo',
  'FastVideoView'
);

function FastVideoComponent(
  props: FastVideoProps,
  forwardedRef: ForwardedRef<FastVideoRef>
) {
  const nativeRef = useRef<NativeFastVideoRef | null>(null);
  const normalized = useMemo(() => normalizeFastVideoSource(props.source), [props.source]);

  useImperativeHandle(
    forwardedRef,
    () => ({
      play: () => mounted(nativeRef).play(),
      pause: () => mounted(nativeRef).pause(),
      replay: () => mounted(nativeRef).replay(),
      seekTo: (positionMs) => mounted(nativeRef).seekTo(finite(positionMs, 'positionMs')),
      seekBy: (deltaMs) => mounted(nativeRef).seekBy(finite(deltaMs, 'deltaMs')),
      goToLive: () => mounted(nativeRef).goToLive(),
      selectTrack: (type, id) => mounted(nativeRef).selectTrack(type, id),
      getSnapshot: () => mounted(nativeRef).getSnapshot(),
      enterPictureInPicture: () => mounted(nativeRef).enterPictureInPicture(),
      stopPictureInPicture: async () => {
        await mounted(nativeRef).stopPictureInPicture?.();
      },
    }),
    []
  );

  const autoplay = props.autoplay ?? false;
  const paused = props.paused ?? !autoplay;

  return (
    <NativeFastVideo
      ref={nativeRef as any}
      style={props.style}
      testID={props.testID}
      accessible={props.accessible}
      accessibilityLabel={props.accessibilityLabel}
      source={normalized.nativeSource}
      autoplay={autoplay}
      paused={paused}
      muted={props.muted ?? false}
      volume={clamp(props.volume ?? 1, 0, 1)}
      rate={clamp(props.rate ?? 1, 0.25, 4)}
      repeat={props.repeat ?? false}
      latencyMode={props.latencyMode ?? normalized.sourceObject.latencyMode ?? 'balanced'}
      progressIntervalMs={clamp(props.progressIntervalMs ?? 250, 100, 2_000)}
      surfaceType={props.surfaceType ?? 'surface'}
      contentFit={props.contentFit ?? 'contain'}
      maxBitrate={positiveOptional(props.maxBitrate)}
      preferredAudioLanguage={props.preferredAudioLanguage}
      preferredTextLanguage={props.preferredTextLanguage}
      allowsExternalPlayback={props.allowsExternalPlayback ?? true}
      onLoadStart={event(props.onLoadStart)}
      onReady={event(props.onReady)}
      onPlaybackStateChange={event(props.onPlaybackStateChange)}
      onBuffer={event(props.onBuffer)}
      onFirstFrame={event(props.onFirstFrame)}
      onProgress={event(props.onProgress)}
      onMetrics={event(props.onMetrics)}
      onAdaptiveDecision={event(props.onAdaptiveDecision)}
      onTracksChanged={event(props.onTracksChanged)}
      onVideoSize={event(props.onVideoSize)}
      onEnd={props.onEnd ? () => props.onEnd?.() : undefined}
      onError={event(props.onError)}
      onPictureInPictureChange={event(props.onPictureInPictureChange)}
    />
  );
}

function event<T>(callback: ((payload: T) => void) | undefined): EventHandler<T> | undefined {
  return callback ? (nativeEvent) => callback(nativeEvent.nativeEvent) : undefined;
}

function mounted(ref: RefObject<NativeFastVideoRef | null>): NativeFastVideoRef {
  if (!ref.current) throw new Error('FastVideo native view is not mounted.');
  return ref.current;
}

function finite(value: number, name: string): number {
  if (!Number.isFinite(value)) throw new TypeError(`${name} must be a finite number.`);
  return value;
}

function clamp(value: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, finite(value, 'FastVideo numeric prop')));
}

function positiveOptional(value: number | undefined): number | undefined {
  return value !== undefined && Number.isFinite(value) && value > 0 ? value : undefined;
}

export const FastVideo = forwardRef(FastVideoComponent);
FastVideo.displayName = 'FastVideo';
