import {
  forwardRef,
  useEffect,
  useImperativeHandle,
  useMemo,
  useRef,
  type CSSProperties,
  type ForwardedRef,
} from 'react';
import { StyleSheet } from 'react-native';

import type {
  FastVideoMetrics,
  FastVideoProps,
  FastVideoRef,
  FastVideoTrack,
} from './FastVideo.types';
import { normalizeFastVideoSource } from './normalizeSource';

function WebFastVideo(
  props: FastVideoProps,
  forwardedRef: ForwardedRef<FastVideoRef>
) {
  const videoRef = useRef<HTMLVideoElement | null>(null);
  const normalized = useMemo(() => normalizeFastVideoSource(props.source), [props.source]);
  const firstFrameSent = useRef(false);
  const metrics = useRef<FastVideoMetrics>(emptyMetrics());

  useEffect(() => {
    const video = videoRef.current;
    if (!video) return;
    video.playbackRate = props.rate ?? 1;
    video.volume = Math.min(1, Math.max(0, props.volume ?? 1));
    video.muted = props.muted ?? false;
    video.loop = props.repeat ?? false;
    if (props.paused === false || props.autoplay) void video.play().catch(() => undefined);
    else video.pause();
  }, [props.autoplay, props.muted, props.paused, props.rate, props.repeat, props.volume]);

  useImperativeHandle(
    forwardedRef,
    () => ({
      async play() {
        await videoRef.current?.play();
      },
      async pause() {
        videoRef.current?.pause();
      },
      async replay() {
        if (!videoRef.current) return;
        videoRef.current.currentTime = 0;
        await videoRef.current.play();
      },
      async seekTo(positionMs) {
        if (videoRef.current) videoRef.current.currentTime = Math.max(0, positionMs / 1_000);
      },
      async seekBy(deltaMs) {
        if (videoRef.current) {
          videoRef.current.currentTime = Math.max(0, videoRef.current.currentTime + deltaMs / 1_000);
        }
      },
      async goToLive() {
        const video = videoRef.current;
        if (video?.seekable.length) {
          video.currentTime = video.seekable.end(video.seekable.length - 1);
          await video.play();
        }
      },
      async selectTrack(type, id) {
        const video = videoRef.current;
        if (!video || type !== 'text') return;
        Array.from(video.textTracks).forEach((track, index) => {
          track.mode = id === `text:${index}` ? 'showing' : 'disabled';
        });
      },
      async getSnapshot() {
        return metrics.current;
      },
      async enterPictureInPicture() {
        const video = videoRef.current as HTMLVideoElement & {
          requestPictureInPicture?: () => Promise<unknown>;
        };
        if (!video?.requestPictureInPicture) return false;
        await video.requestPictureInPicture();
        return true;
      },
      async stopPictureInPicture() {
        const pipDocument = typeof document === 'undefined' ? undefined : document as Document & {
          pictureInPictureElement?: Element | null;
          exitPictureInPicture?: () => Promise<void>;
        };
        if (pipDocument?.pictureInPictureElement) {
          await pipDocument.exitPictureInPicture?.();
        }
      },
    }),
    []
  );

  const style = StyleSheet.flatten(props.style) as unknown as CSSProperties | undefined;
  const native = normalized.nativeSource;

  return (
    <video
      ref={videoRef}
      data-testid={props.testID}
      src={native.uri}
      style={{
        ...style,
        objectFit: objectFit(props.contentFit),
      }}
      autoPlay={props.autoplay}
      muted={props.muted}
      loop={props.repeat}
      playsInline
      onLoadStart={() => props.onLoadStart?.({ uri: native.uri })}
      onLoadedMetadata={(event) => {
        const video = event.currentTarget;
        props.onReady?.({ durationMs: finiteSeconds(video.duration) * 1_000, isLive: !Number.isFinite(video.duration) });
        props.onVideoSize?.({ width: video.videoWidth, height: video.videoHeight, pixelRatio: 1 });
        props.onTracksChanged?.({
          video: [],
          audio: [],
          text: Array.from(video.textTracks).map<FastVideoTrack>((track, index) => ({
            id: `text:${index}`,
            label: track.label,
            language: track.language,
            selected: track.mode === 'showing',
            supported: true,
          })),
        });
      }}
      onPlaying={() => {
        props.onPlaybackStateChange?.({ state: 'playing' });
        props.onBuffer?.({ buffering: false });
        if (!firstFrameSent.current) {
          firstFrameSent.current = true;
          props.onFirstFrame?.({ timestampMs: Date.now() });
        }
      }}
      onPause={() => props.onPlaybackStateChange?.({ state: 'paused' })}
      onWaiting={() => {
        props.onBuffer?.({ buffering: true });
        props.onPlaybackStateChange?.({ state: 'buffering' });
      }}
      onEnded={() => {
        props.onPlaybackStateChange?.({ state: 'ended' });
        props.onEnd?.();
      }}
      onTimeUpdate={(event) => {
        const video = event.currentTarget;
        const buffered = video.buffered.length ? video.buffered.end(video.buffered.length - 1) : 0;
        const progress = {
          positionMs: video.currentTime * 1_000,
          durationMs: finiteSeconds(video.duration) * 1_000,
          bufferedPositionMs: buffered * 1_000,
          isLive: !Number.isFinite(video.duration),
          isPlaying: !video.paused,
          playbackState: video.paused ? ('paused' as const) : ('playing' as const),
        };
        metrics.current = { ...metrics.current, ...progress, state: progress.playbackState };
        props.onProgress?.(progress);
      }}
      onError={() => props.onError?.({ code: 'E_WEB_PLAYBACK', message: 'Browser video playback failed.' })}
      onEnterPictureInPicture={() => props.onPictureInPictureChange?.({ active: true })}
      onLeavePictureInPicture={() => props.onPictureInPictureChange?.({ active: false })}
    >
      {native.subtitles.map((subtitle, index) => (
        <track
          key={subtitle.id ?? subtitle.uri}
          src={subtitle.uri}
          kind="subtitles"
          srcLang={subtitle.language}
          label={subtitle.label}
          default={subtitle.isDefault || index === 0}
        />
      ))}
    </video>
  );
}

function objectFit(value: FastVideoProps['contentFit']): CSSProperties['objectFit'] {
  switch (value) {
    case 'cover': return 'cover';
    case 'fill': return 'fill';
    case 'none': return 'none';
    default: return 'contain';
  }
}

function finiteSeconds(value: number): number {
  return Number.isFinite(value) && value >= 0 ? value : 0;
}

function emptyMetrics(): FastVideoMetrics {
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
    positionMs: 0,
    durationMs: 0,
    bufferedPositionMs: 0,
    liveOffsetMs: -1,
    isLive: false,
    firstFrameRendered: false,
  };
}

export const FastVideo = forwardRef(WebFastVideo);
FastVideo.displayName = 'FastVideo';
