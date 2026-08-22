package com.vivekjm.fastvideo

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.Tracks
import androidx.media3.common.VideoSize
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.cache.CacheDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.analytics.AnalyticsListener
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import org.json.JSONObject
import java.util.Locale

internal interface FastVideoEngineListener {
  fun emitLoadStart(uri: String)
  fun emitReady(durationMs: Double, isLive: Boolean)
  fun emitState(state: String)
  fun emitBuffering(buffering: Boolean)
  fun emitFirstFrame()
  fun emitProgress(payload: Map<String, Any?>)
  fun emitMetrics(payload: Map<String, Any?>)
  fun emitAdaptiveDecision(payload: Map<String, Any?>)
  fun emitTracksChanged(payload: Map<String, Any?>)
  fun emitVideoSize(width: Int, height: Int, pixelRatio: Float)
  fun emitEnded()
  fun emitError(code: String, message: String, nativeCode: String?)
}

@OptIn(UnstableApi::class)
internal class FastVideoEngine(
  context: Context,
  private val latencyMode: String,
  private val listener: FastVideoEngineListener
) : Player.Listener, AnalyticsListener {
  val player: ExoPlayer
  private val coreHandle = FastCoreNative.create()
  private val handler = Handler(Looper.getMainLooper())
  private var released = false
  private var source: FastVideoSource? = null
  private var baseSource: FastVideoSource? = null
  private var candidateUris: List<String> = emptyList()
  private var candidateIndex = 0
  private var retryAttempt = 0
  private var autoplayRequested = false
  private var firstFrame = false
  private var lastIsBuffering = false
  private var startupPath = "cold"
  private var cachedBytesRead = 0L
  private var configuredMaxBitrate: Int? = null
  private var latestBandwidthEstimate = 0L
  private var currentVideoWidth = 0
  private var currentVideoHeight = 0
  private var adaptiveDecision: Map<String, Any?> = emptyMap()
  private var candidateLoadStartedAtMs = 0L

  private val progressRunnable = object : Runnable {
    override fun run() {
      if (released) return
      updateProgressAndMaybeEmit()
      handler.postDelayed(this, 50L)
    }
  }

  init {
    player = FastVideoPreloadRuntime.acquirePlayer(context, latencyMode).also {
      it.addListener(this)
      it.addAnalyticsListener(this)
    }

    FastCoreNative.setProgressInterval(coreHandle, 250L)
    FastVideoAdaptiveRuntime.onPlayerAcquired()
    handler.post(progressRunnable)
  }

  fun setProgressInterval(intervalMs: Long) {
    FastCoreNative.setProgressInterval(coreHandle, intervalMs)
  }

  fun load(source: FastVideoSource, autoplay: Boolean) {
    baseSource = source
    candidateUris = FastVideoCdnRuntime.rank((listOf(source.uri) + source.fallbackUris)
      .filter { it.isNotBlank() }
      .distinct())
    candidateIndex = 0
    retryAttempt = 0
    autoplayRequested = autoplay
    loadCandidate(sourceForUri(source, candidateUris.firstOrNull() ?: source.uri), autoplay)
  }

  private fun loadCandidate(candidate: FastVideoSource, autoplay: Boolean) {
    this.source = candidate
    firstFrame = false
    lastIsBuffering = false
    cachedBytesRead = 0L
    candidateLoadStartedAtMs = SystemClock.elapsedRealtime()
    listener.emitLoadStart(candidate.uri)
    core(FastCoreEvent.LOAD, if (candidate.isLive) 1.0 else 0.0)

    val mediaItem = FastVideoMediaItemFactory.build(candidate, latencyMode)
    val cacheListener = object : CacheDataSource.EventListener {
      override fun onCacheIgnored(reason: Int) = Unit

      override fun onCachedBytesRead(cacheSizeBytes: Long, cachedBytesRead: Long) {
        this@FastVideoEngine.cachedBytesRead += cachedBytesRead.coerceAtLeast(0L)
      }
    }
    val offlineId = candidate.offlineId?.takeIf { it.isNotBlank() }
    if (offlineId != null && !FastVideoDownloadRuntime.isCompleted(contextRef, offlineId)) {
      listener.emitError("E_OFFLINE_NOT_READY", "Offline download is not completed: $offlineId", null)
      return
    }
    val mediaSourceFactory = if (offlineId != null) {
      DefaultMediaSourceFactory(FastVideoDownloadRuntime.offlineDataSourceFactory(contextRef))
    } else {
      DefaultMediaSourceFactory(FastVideoCacheRuntime.dataSourceFactory(contextRef, candidate.headers, cacheListener))
    }

    val preloadedSource = if (offlineId == null && candidate.headers.isEmpty() && candidate.drm == null && candidate.subtitles.isEmpty()) {
      FastVideoPreloadRuntime.mediaSource(latencyMode, candidate.preloadIndex, mediaItem)
    } else null

    startupPath = when { offlineId != null -> "offline"; preloadedSource != null -> "memory-preloaded"; else -> "cold" }
    player.setMediaSource(preloadedSource ?: mediaSourceFactory.createMediaSource(mediaItem), true)
    FastVideoPreloadRuntime.focus(candidate.preloadIndex)
    candidate.startPositionMs?.takeIf { it.isFinite() && it >= 0.0 }?.let { player.seekTo(it.toLong()) }
    player.prepare()
    player.playWhenReady = autoplay
    if (candidate.mediaSession) FastVideoMediaSessionRuntime.attach(contextRef, player, candidate)
    else FastVideoMediaSessionRuntime.detach(player, false)
    if (autoplay) core(FastCoreEvent.PLAY)
  }

  private fun retryOrFail(error: PlaybackException) {
    val responseMs = (SystemClock.elapsedRealtime() - candidateLoadStartedAtMs).coerceAtLeast(0L).toDouble()
    source?.uri?.let { FastVideoCdnRuntime.recordFailure(it, responseMs) }
    val base = baseSource
    if (base == null || released) {
      emitTerminalError(error)
      return
    }
    val maxRetries = base.maxRetryAttempts.coerceIn(0, 8)
    if (retryAttempt < maxRetries) {
      val delay = (base.retryBackoffMs.coerceIn(50L, 10_000L) * (1L shl retryAttempt.coerceAtMost(4)))
      retryAttempt += 1
      handler.postDelayed({
        if (!released) loadCandidate(sourceForUri(base, candidateUris.getOrElse(candidateIndex) { base.uri }), autoplayRequested)
      }, delay)
      return
    }
    if (candidateIndex + 1 < candidateUris.size) {
      candidateIndex += 1
      retryAttempt = 0
      handler.postDelayed({
        if (!released) loadCandidate(sourceForUri(base, candidateUris[candidateIndex]), autoplayRequested)
      }, base.retryBackoffMs.coerceIn(50L, 10_000L))
      return
    }
    emitTerminalError(error)
  }

  private fun emitTerminalError(error: PlaybackException) {
    core(FastCoreEvent.ERROR)
    listener.emitError("E_PLAYBACK", error.message ?: "Native playback failed", error.errorCodeName)
  }

  private fun sourceForUri(base: FastVideoSource, uri: String): FastVideoSource = FastVideoSource().also { copy ->
    copy.uri = uri
    copy.type = base.type
    copy.headers = base.headers
    copy.drm = base.drm
    copy.subtitles = base.subtitles
    copy.isLive = base.isLive
    copy.startPositionMs = base.startPositionMs
    copy.targetLiveOffsetMs = base.targetLiveOffsetMs
    copy.customCacheKey = base.customCacheKey
    copy.offlineId = base.offlineId
    copy.preloadIndex = base.preloadIndex
    copy.fallbackUris = base.fallbackUris
    copy.maxRetryAttempts = base.maxRetryAttempts
    copy.retryBackoffMs = base.retryBackoffMs
    copy.latencyMode = base.latencyMode
    copy.metadata = base.metadata
    copy.mediaSession = base.mediaSession
  }

  private val contextRef: Context = context.applicationContext

  fun play() {
    player.play()
    core(FastCoreEvent.PLAY)
  }

  fun pause() {
    player.pause()
    core(FastCoreEvent.PAUSE)
  }

  fun seekTo(positionMs: Double) {
    if (!positionMs.isFinite()) return
    core(FastCoreEvent.SEEK_START)
    player.seekTo(positionMs.coerceAtLeast(0.0).toLong())
  }

  fun seekBy(deltaMs: Double) {
    seekTo(player.currentPosition + deltaMs)
  }

  fun replay() {
    player.seekTo(0L)
    player.play()
    core(FastCoreEvent.PLAY)
  }

  fun goToLive() {
    if (player.isCurrentMediaItemLive) {
      core(FastCoreEvent.SEEK_START)
      player.seekToDefaultPosition()
      player.play()
    }
  }

  fun setRate(rate: Float) {
    if (rate.isFinite()) player.setPlaybackSpeed(rate.coerceIn(0.25f, 4f))
  }

  fun setVolume(volume: Float) {
    if (volume.isFinite()) player.volume = volume.coerceIn(0f, 1f)
  }

  fun setMuted(muted: Boolean) {
    player.volume = if (muted) 0f else 1f
  }

  fun setRepeat(repeat: Boolean) {
    player.repeatMode = if (repeat) Player.REPEAT_MODE_ONE else Player.REPEAT_MODE_OFF
  }

  fun setMaxBitrate(maxBitrate: Int?) {
    configuredMaxBitrate = maxBitrate?.takeIf { it > 0 }
    applyAdaptiveDecision()
  }

  fun setPreferredLanguages(audio: String?, text: String?) {
    val builder = player.trackSelectionParameters.buildUpon()
    if (!audio.isNullOrBlank()) builder.setPreferredAudioLanguage(audio)
    if (!text.isNullOrBlank()) builder.setPreferredTextLanguage(text)
    player.trackSelectionParameters = builder.build()
  }

  fun selectTrack(type: String, id: String?) {
    val trackType = when (type.lowercase(Locale.US)) {
      "audio" -> C.TRACK_TYPE_AUDIO
      "text", "subtitle" -> C.TRACK_TYPE_TEXT
      "video" -> C.TRACK_TYPE_VIDEO
      else -> return
    }
    val builder = player.trackSelectionParameters.buildUpon().clearOverridesOfType(trackType)
    if (!id.isNullOrBlank()) {
      val parts = id.split(':')
      if (parts.size == 3) {
        val groupIndex = parts[1].toIntOrNull()
        val trackIndex = parts[2].toIntOrNull()
        val group = groupIndex?.let { player.currentTracks.groups.getOrNull(it) }
        if (group != null && trackIndex != null && trackIndex in 0 until group.length) {
          builder.setOverrideForType(TrackSelectionOverride(group.mediaTrackGroup, trackIndex))
        }
      }
    }
    player.trackSelectionParameters = builder.build()
  }

  fun snapshot(): Map<String, Any?> = parseSnapshot(FastCoreNative.snapshot(coreHandle)) + mapOf(
    "startupPath" to startupPath,
    "cachedBytesRead" to cachedBytesRead,
    "adaptiveDecision" to adaptiveDecision,
    "activePlayers" to FastVideoAdaptiveRuntime.activePlayerCount(),
    "cdn" to (source?.uri?.let { FastVideoCdnRuntime.diagnostics(it) } ?: emptyMap<String, Any?>())
  )

  fun release(preserveForBackground: Boolean = false) {
    if (released) return
    released = true
    handler.removeCallbacksAndMessages(null)
    core(FastCoreEvent.RELEASE)
    player.removeListener(this)
    player.removeAnalyticsListener(this)
    val preserved = FastVideoMediaSessionRuntime.detach(player, preserveForBackground && source?.mediaSession == true)
    if (!preserved) FastVideoPreloadRuntime.recyclePlayer(latencyMode, player)
    FastVideoAdaptiveRuntime.onPlayerReleased()
    FastCoreNative.destroy(coreHandle)
  }

  override fun onPlaybackStateChanged(playbackState: Int) {
    when (playbackState) {
      Player.STATE_BUFFERING -> {
        if (!lastIsBuffering) {
          lastIsBuffering = true
          core(FastCoreEvent.BUFFERING_START)
          listener.emitBuffering(true)
        }
        listener.emitState("buffering")
      }
      Player.STATE_READY -> {
        if (lastIsBuffering) {
          lastIsBuffering = false
          core(FastCoreEvent.BUFFERING_END)
          listener.emitBuffering(false)
        }
        core(FastCoreEvent.READY)
        listener.emitReady(safeDuration(), player.isCurrentMediaItemLive)
        listener.emitState(if (player.isPlaying) "playing" else "ready")
      }
      Player.STATE_ENDED -> {
        core(FastCoreEvent.ENDED)
        listener.emitState("ended")
        listener.emitEnded()
      }
      Player.STATE_IDLE -> listener.emitState("idle")
    }
  }

  override fun onIsPlayingChanged(isPlaying: Boolean) {
    if (isPlaying) core(FastCoreEvent.PLAY) else if (player.playbackState == Player.STATE_READY) core(FastCoreEvent.PAUSE)
    listener.emitState(if (isPlaying) "playing" else stateName())
  }

  override fun onPositionDiscontinuity(
    oldPosition: Player.PositionInfo,
    newPosition: Player.PositionInfo,
    reason: Int
  ) {
    if (reason == Player.DISCONTINUITY_REASON_SEEK || reason == Player.DISCONTINUITY_REASON_SEEK_ADJUSTMENT) {
      core(FastCoreEvent.SEEK_COMPLETE)
    }
  }

  override fun onPlayerError(error: PlaybackException) {
    retryOrFail(error)
  }

  override fun onTracksChanged(tracks: Tracks) {
    listener.emitTracksChanged(trackPayload(tracks))
  }

  override fun onVideoSizeChanged(videoSize: VideoSize) {
    currentVideoWidth = videoSize.width
    currentVideoHeight = videoSize.height
    applyAdaptiveDecision()
    listener.emitVideoSize(videoSize.width, videoSize.height, videoSize.pixelWidthHeightRatio)
  }

  override fun onRenderedFirstFrame(eventTime: AnalyticsListener.EventTime, output: Any, renderTimeMs: Long) {
    if (firstFrame) return
    firstFrame = true
    if (startupPath == "cold" && cachedBytesRead > 0L) startupPath = "disk-cache"
    core(FastCoreEvent.FIRST_FRAME)
    val snapshot = parseSnapshot(FastCoreNative.snapshot(coreHandle))
    val ttff = (snapshot["timeToFirstFrameMs"] as? Number)?.toDouble() ?: -1.0
    val responseMs = (SystemClock.elapsedRealtime() - candidateLoadStartedAtMs).coerceAtLeast(0L).toDouble()
    source?.uri?.let { FastVideoCdnRuntime.recordFirstFrame(it, ttff, responseMs) }
    listener.emitFirstFrame()
  }

  override fun onDroppedVideoFrames(
    eventTime: AnalyticsListener.EventTime,
    droppedFrames: Int,
    elapsedMs: Long
  ) {
    core(FastCoreEvent.FRAMES, 0.0, droppedFrames.toDouble())
  }

  override fun onVideoFrameProcessingOffset(
    eventTime: AnalyticsListener.EventTime,
    totalProcessingOffsetUs: Long,
    frameCount: Int
  ) {
    core(FastCoreEvent.FRAMES, frameCount.toDouble(), 0.0)
    core(FastCoreEvent.FRAME_PROCESSING, totalProcessingOffsetUs.toDouble(), frameCount.toDouble())
  }

  override fun onBandwidthEstimate(
    eventTime: AnalyticsListener.EventTime,
    totalLoadTimeMs: Int,
    totalBytesLoaded: Long,
    bitrateEstimate: Long
  ) {
    latestBandwidthEstimate = bitrateEstimate.coerceAtLeast(0L)
    core(FastCoreEvent.BYTES, totalBytesLoaded.toDouble(), bitrateEstimate.toDouble())
    applyAdaptiveDecision()
  }

  private fun applyAdaptiveDecision() {
    if (released) return
    val snapshot = parseSnapshot(FastCoreNative.snapshot(coreHandle))
    val rebufferRatio = (snapshot["rebufferRatio"] as? Number)?.toDouble() ?: 0.0
    val droppedFrameRatio = (snapshot["droppedFrameRatio"] as? Number)?.toDouble() ?: 0.0
    val bandwidthConfidence = (snapshot["bandwidthConfidence"] as? Number)?.toDouble() ?: 0.0
    val predictedBandwidth = (snapshot["predictedBandwidthBps"] as? Number)?.toLong()?.takeIf { it > 0 && bandwidthConfidence >= 0.35 } ?: latestBandwidthEstimate
    val decision = FastVideoAdaptiveRuntime.decision(
      contextRef,
      predictedBandwidth,
      rebufferRatio,
      droppedFrameRatio,
      currentVideoWidth,
      currentVideoHeight
    )
    if (decision.isEmpty()) {
      player.trackSelectionParameters = player.trackSelectionParameters.buildUpon()
        .setMaxVideoBitrate(configuredMaxBitrate ?: Int.MAX_VALUE)
        .build()
      adaptiveDecision = emptyMap()
      return
    }

    val adaptiveBitrate = (decision["maxBitrateBps"] as? Number)?.toLong()?.coerceAtLeast(0L) ?: 0L
    val userLimit = configuredMaxBitrate?.toLong()?.takeIf { it > 0 } ?: Long.MAX_VALUE
    val resolvedBitrate = when {
      adaptiveBitrate <= 0L -> userLimit
      else -> minOf(userLimit, adaptiveBitrate)
    }.coerceAtMost(Int.MAX_VALUE.toLong()).toInt()
    val maxWidth = (decision["maxWidth"] as? Number)?.toInt()?.coerceAtLeast(1) ?: Int.MAX_VALUE
    val maxHeight = (decision["maxHeight"] as? Number)?.toInt()?.coerceAtLeast(1) ?: Int.MAX_VALUE

    player.trackSelectionParameters = player.trackSelectionParameters.buildUpon()
      .setMaxVideoBitrate(if (resolvedBitrate > 0) resolvedBitrate else Int.MAX_VALUE)
      .setMaxVideoSize(maxWidth, maxHeight)
      .build()
    val nextDecision = decision + mapOf(
      "resolvedMaxBitrateBps" to resolvedBitrate,
      "predictedBandwidthBps" to predictedBandwidth,
      "bandwidthConfidence" to bandwidthConfidence
    )
    if (nextDecision != adaptiveDecision) {
      adaptiveDecision = nextDecision
      listener.emitAdaptiveDecision(nextDecision)
    }
  }

  private fun updateProgressAndMaybeEmit() {
    if (released || player.playbackState == Player.STATE_IDLE) return
    val duration = safeDuration()
    val buffered = player.bufferedPosition.coerceAtLeast(0L).toDouble()
    val position = player.currentPosition.coerceAtLeast(0L).toDouble()
    core(FastCoreEvent.PROGRESS, position, duration, buffered)
    val liveOffset = player.currentLiveOffset
    if (liveOffset != C.TIME_UNSET && liveOffset >= 0L) {
      core(FastCoreEvent.LIVE_OFFSET, liveOffset.toDouble())
    }
    if (!FastCoreNative.shouldEmitProgress(coreHandle)) return

    val payload = mutableMapOf<String, Any?>(
      "positionMs" to position,
      "durationMs" to duration,
      "bufferedPositionMs" to buffered,
      "isLive" to player.isCurrentMediaItemLive,
      "isPlaying" to player.isPlaying,
      "playbackState" to stateName()
    )
    if (liveOffset != C.TIME_UNSET && liveOffset >= 0L) payload["liveOffsetMs"] = liveOffset.toDouble()
    listener.emitProgress(payload)
    listener.emitMetrics(snapshot())
  }

  private fun safeDuration(): Double {
    val duration = player.duration
    return if (duration == C.TIME_UNSET || duration < 0) 0.0 else duration.toDouble()
  }

  private fun stateName(): String = when (player.playbackState) {
    Player.STATE_BUFFERING -> "buffering"
    Player.STATE_READY -> if (player.isPlaying) "playing" else "ready"
    Player.STATE_ENDED -> "ended"
    else -> "idle"
  }

  private fun trackPayload(tracks: Tracks): Map<String, Any?> {
    val video = mutableListOf<Map<String, Any?>>()
    val audio = mutableListOf<Map<String, Any?>>()
    val text = mutableListOf<Map<String, Any?>>()

    tracks.groups.forEachIndexed { groupIndex, group ->
      repeat(group.length) { trackIndex ->
        val format = group.getTrackFormat(trackIndex)
        val item = mapOf(
          "id" to "${group.type}:$groupIndex:$trackIndex",
          "nativeId" to format.id,
          "label" to format.label,
          "language" to format.language,
          "mimeType" to format.sampleMimeType,
          "codecs" to format.codecs,
          "bitrate" to format.bitrate.takeIf { it > 0 },
          "width" to format.width.takeIf { it > 0 },
          "height" to format.height.takeIf { it > 0 },
          "frameRate" to format.frameRate.takeIf { it > 0f },
          "selected" to group.isTrackSelected(trackIndex),
          "supported" to group.isTrackSupported(trackIndex)
        )
        when (group.type) {
          C.TRACK_TYPE_VIDEO -> video += item
          C.TRACK_TYPE_AUDIO -> audio += item
          C.TRACK_TYPE_TEXT -> text += item
        }
      }
    }
    return mapOf("video" to video, "audio" to audio, "text" to text)
  }

  private fun parseSnapshot(json: String): Map<String, Any?> {
    return try {
      val value = JSONObject(json)
      value.keys().asSequence().associateWith { key ->
        when (val item = value.opt(key)) {
          JSONObject.NULL -> null
          else -> item
        }
      }
    } catch (_: Throwable) {
      emptyMap()
    }
  }

  private fun core(event: Int, a: Double = 0.0, b: Double = 0.0, c: Double = 0.0) {
    if (!released) FastCoreNative.event(coreHandle, event, a, b, c)
  }

  private data class Policy(
    val minBufferMs: Int,
    val maxBufferMs: Int,
    val playbackMs: Int,
    val rebufferMs: Int,
    val targetLiveOffsetMs: Int,
    val minLiveSpeed: Float,
    val maxLiveSpeed: Float
  )

  private fun bufferPolicy(mode: String): Policy = when (mode) {
    "lowLatency" -> Policy(1_000, 6_000, 250, 500, 2_000, 0.97f, 1.05f)
    "quality" -> Policy(20_000, 90_000, 1_500, 3_000, 8_000, 0.98f, 1.02f)
    "memorySaver" -> Policy(1_500, 8_000, 500, 1_000, 5_000, 0.98f, 1.03f)
    else -> Policy(8_000, 40_000, 750, 1_500, 5_000, 0.98f, 1.03f)
  }
}
