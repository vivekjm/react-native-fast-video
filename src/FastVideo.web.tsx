import {
  forwardRef,
  useEffect,
  useImperativeHandle,
  useMemo,
  useRef,
  type CSSProperties,
  type ForwardedRef,
} from 'react';

import type {
  FastVideoError,
  FastVideoMetrics,
  FastVideoProgress,
  FastVideoProps,
  FastVideoRef,
  FastVideoTracks,
} from './FastVideo.types';
import { normalizeFastVideoSource } from './normalizeSource';

type WebVideoElement = HTMLVideoElement & {
  requestPictureInPicture?: () => Promise<PictureInPictureWindow>;
  webkitEnterFullscreen?: () => void;
};

type PictureInPictureDocument = Document & {
  pictureInPictureElement?: Element | null;
  exitPictureInPicture?: () => Promise<void>;
};

const EMPTY_TRACKS: FastVideoTracks = {
  video: [],
  audio: [],
  text: [],
};

function FastVideoWebComponent(
  props: FastVideoProps,
  forwardedRef: ForwardedRef<FastVideoRef>
) {
  const videoRef = useRef<WebVideoElement | null>(null);
  const normalized = useMemo(() => normalizeFastVideoSource(props.source), [props.source]);
  const source = normalized.sourceObject;
  const loadStartedAt = useRef(now());
  const firstFrameSeen = useRef(false);
  const lastProgressEmitAt = useRef(0);
  const metricsRef = useRef<FastVideoMetrics>(initialMetrics());

  const updateMetrics = (patch: Partial<FastVideoMetrics>) => {
    metricsRef.current = { ...metricsRef.current, ...patch };
    props.onMetrics?.(metricsRef.current);
  };

  useImperativeHandle(
    forwardedRef,
    () => ({
      async play() {
        await mounted(videoRef).play();
      },
      async pause() {
        mounted(videoRef).pause();
      },
      async replay() {
        const video = mounted(videoRef);
        video.currentTime = 0;
        await video.play();
      },
      async seekTo(positionMs) {
        mounted(videoRef).currentTime = finite(positionMs, 'positionMs') / 1_000;
      },
      async seekBy(deltaMs) {
        const video = mounted(videoRef);
        video.currentTime = Math.max(0, video.currentTime + finite(deltaMs, 'deltaMs') / 1_000);
      },
      async goToLive() {
        const video = mounted(videoRef);
        const end = seekableEnd(video);
        if (end !== null) video.currentTime = end;
        await video.play();
      },
      async selectTrack(type, id) {
        const video = mounted(videoRef);
        if (type !== 'text') return;
        const selected = id === null ? -1 : Number(id.split(':').at(-1));
        Array.from(video.textTracks).forEach((track, index) => {
          track.mode = index === selected ? 'showing' : 'disabled';
        });
      },
      async getSnapshot() {
        return metricsRef.current;
      },
      async enterPictureInPicture() {
        const video = mounted(videoRef);
        if (video.requestPictureInPicture) {
          await video.requestPictureInPicture();
          return true;
        }
        video.webkitEnterFullscreen?.();
        return false;
      },
      async stopPictureInPicture() {
        const documentWithPiP = document as PictureInPictureDocument;
        if (documentWithPiP.pictureInPictureElement && documentWithPiP.exitPictureInPicture) {
          await documentWithPiP.exitPictureInPicture();
        }
      },
    }),
    []
  );

  useEffect(() => {
    const video = videoRef.current;
    if (!video) return;
    const onEnter = () => props.onPictureInPictureChange?.({ active: true });
    const onLeave = () => props.onPictureInPictureChange?.({ active: false });
    video.addEventListener('enterpictureinpicture', onEnter);
    video.addEventListener('leavepictureinpicture', onLeave);
    return () => {
      video.removeEventListener('enterpictureinpicture', onEnter);
      video.removeEventListener('leavepictureinpicture', onLeave);
    };
  }, [props.onPictureInPictureChange]);

  useEffect(() => {
    const video = videoRef.current;
    if (!video) return;
    video.volume = clamp(props.volume ?? 1, 0, 1);
    video.muted = props.muted ?? false;
    video.playbackRate = clamp(props.rate ?? 1, 0.25, 4);
    video.loop = props.repeat ?? false;
  }, [props.volume, props.muted, props.rate, props.repeat]);

  useEffect(() => {
    const video = videoRef.current;
    if (!video) return;
    const autoplay = props.autoplay ?? false;
    const paused = props.paused ?? !autoplay;
    if (paused) video.pause();
    else void video.play().catch(() => undefined);
  }, [props.autoplay, props.paused, source.uri]);

  useEffect(() => {
    loadStartedAt.current = now();
    firstFrameSeen.current = false;
    metricsRef.current = initialMetrics();
    props.onLoadStart?.({ uri: source.uri });
  }, [source.uri, props.onLoadStart]);

  const objectFit: CSSProperties['objectFit'] =
    props.contentFit === 'cover'
      ? 'cover'
      : props.contentFit === 'fill'
        ? 'fill'
        : props.contentFit === 'none'
          ? 'none'
          : 'contain';
  const webStyle = { ...(props.style as CSSProperties | undefined), objectFit };

  const emitProgress = () => {
    const video = videoRef.current;
    if (!video) return;
    const timestamp = now();
    const interval = clamp(props.progressIntervalMs ?? 250, 100, 2_000);
    if (timestamp - lastProgressEmitAt.current < interval) return;
    lastProgressEmitAt.current = timestamp;

    const positionMs = finiteOrZero(video.currentTime) * 1_000;
    const durationMs = finiteOrZero(video.duration) * 1_000;
    const bufferedPositionMs = bufferedEnd(video) * 1_000;
    const liveEnd = seekableEnd(video);
    const liveOffsetMs = liveEnd === null ? undefined : Math.max(0, (liveEnd - video.currentTime) * 1_000);
    const progress: FastVideoProgress = {
      positionMs,
      durationMs,
      bufferedPositionMs,
      isLive: liveEnd !== null && !Number.isFinite(video.duration),
      isPlaying: !video.paused && !video.ended,
      playbackState: stateFor(video),
      ...(liveOffsetMs === undefined ? {} : { liveOffsetMs }),
    };
    props.onProgress?.(progress);
    updateMetrics({
      state: progress.playbackState,
      playWhenReady: !video.paused,
      positionMs,
      durationMs,
      bufferedPositionMs,
      liveOffsetMs: liveOffsetMs ?? -1,
      activePlaybackMs: positionMs,
    } as Partial<FastVideoMetrics>);
  };

  return (
    <video
      ref={videoRef}
      data-testid={props.testID}
      aria-label={props.accessibilityLabel}
      src={source.uri}
      style={webStyle}
      autoPlay={props.autoplay ?? false}
      muted={props.muted ?? false}
      loop={props.repeat ?? false}
      playsInline
      preload="auto"
      onLoadedMetadata={(event) => {
        const video = event.currentTarget;
        const durationMs = finiteOrZero(video.duration) * 1_000;
        props.onReady?.({ durationMs, isLive: !Number.isFinite(video.duration) });
        props.onVideoSize?.({ width: video.videoWidth, height: video.videoHeight, pixelRatio: 1 });
        props.onTracksChanged?.(EMPTY_TRACKS);
        updateMetrics({ state: 'ready', durationMs } as Partial<FastVideoMetrics>);
      }}
      onLoadedData={() => {
        if (firstFrameSeen.current) return;
        firstFrameSeen.current = true;
        const timeToFirstFrameMs = Math.max(0, now() - loadStartedAt.current);
        props.onFirstFrame?.({
          timestampMs: Date.now(),
          timeToFirstFrameMs,
          startupPath: 'browser-native',
        });
        updateMetrics({ firstFrameRendered: true, timeToFirstFrameMs } as Partial<FastVideoMetrics>);
      }}
      onWaiting={() => {
        props.onBuffer?.({ buffering: true });
        props.onPlaybackStateChange?.({ state: 'buffering' });
        updateMetrics({ state: 'buffering' } as Partial<FastVideoMetrics>);
      }}
      onPlaying={() => {
        props.onBuffer?.({ buffering: false });
        props.onPlaybackStateChange?.({ state: 'playing' });
        updateMetrics({ state: 'playing', playWhenReady: true } as Partial<FastVideoMetrics>);
      }}
      onPause={(event) => {
        if (event.currentTarget.ended) return;
        props.onPlaybackStateChange?.({ state: 'paused' });
        updateMetrics({ state: 'paused', playWhenReady: false } as Partial<FastVideoMetrics>);
      }}
      onEnded={() => {
        props.onPlaybackStateChange?.({ state: 'ended' });
        updateMetrics({ state: 'ended', playWhenReady: false } as Partial<FastVideoMetrics>);
        props.onEnd?.();
      }}
      onTimeUpdate={emitProgress}
      onProgress={emitProgress}
      onError={(event) => {
        const mediaError = event.currentTarget.error;
        const error: FastVideoError = {
          code: 'E_WEB_PLAYBACK',
          message: mediaError?.message || 'Browser video playback failed.',
          nativeCode: mediaError ? String(mediaError.code) : undefined,
        };
        props.onError?.(error);
        updateMetrics({ state: 'error', playWhenReady: false } as Partial<FastVideoMetrics>);
      }}
    >
      {source.subtitles?.map((subtitle, index) => (
        <track
          key={subtitle.id ?? `${subtitle.uri}:${index}`}
          src={subtitle.uri}
          kind="subtitles"
          srcLang={subtitle.language}
          label={subtitle.label}
          default={subtitle.isDefault}
        />
      ))}
    </video>
  );
}

function initialMetrics(): FastVideoMetrics {
  return {
    state: 'idle',
    playWhenReady: false,
    sequence: 0,
    timeToFirstFrameMs: -1,
    lastSeekLatencyMs: -1,
    totalRebufferMs: 0,
    activePlaybackMs: 0,
    rebufferRatio: 0,
    rebufferCount: 0,
    renderedFrames: 0,
    droppedFrames: 0,
    droppedFrameRatio: 0,
    bytesTransferred: 0,
    estimatedBitrateBps: 0,
    predictedBandwidthBps: 0,
    bandwidthConfidence: 0,
    bandwidthVolatility: 0,
    bandwidthSamples: 0,
    liveOffsetMs: -1,
    positionMs: 0,
    durationMs: 0,
    bufferedPositionMs: 0,
    qoeScore: 100,
    averageFrameProcessingOffsetUs: 0,
    frameProcessingSamples: 0,
    isLive: false,
    firstFrameRendered: false,
  };
}

function mounted(ref: { current: WebVideoElement | null }): WebVideoElement {
  if (!ref.current) throw new Error('FastVideo web element is not mounted.');
  return ref.current;
}

function now(): number {
  return typeof performance === 'undefined' ? Date.now() : performance.now();
}

function finite(value: number, name: string): number {
  if (!Number.isFinite(value)) throw new TypeError(`${name} must be a finite number.`);
  return value;
}

function finiteOrZero(value: number): number {
  return Number.isFinite(value) && value >= 0 ? value : 0;
}

function clamp(value: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, finite(value, 'FastVideo numeric prop')));
}

function bufferedEnd(video: HTMLVideoElement): number {
  return video.buffered.length ? video.buffered.end(video.buffered.length - 1) : 0;
}

function seekableEnd(video: HTMLVideoElement): number | null {
  return video.seekable.length ? video.seekable.end(video.seekable.length - 1) : null;
}

function stateFor(video: HTMLVideoElement): FastVideoMetrics['state'] {
  if (video.error) return 'error';
  if (video.ended) return 'ended';
  if (video.readyState < HTMLMediaElement.HAVE_FUTURE_DATA) return 'buffering';
  return video.paused ? 'paused' : 'playing';
}

export const FastVideo = forwardRef(FastVideoWebComponent);
FastVideo.displayName = 'FastVideo';
