package com.vivekjm.fastvideo

import android.content.Context
import androidx.annotation.OptIn
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.MediaSource
import androidx.media3.exoplayer.source.preload.DefaultPreloadManager
import androidx.media3.exoplayer.source.preload.TargetPreloadStatusControl
import java.util.ArrayDeque
import org.json.JSONObject

/**
 * Process-wide Android feed runtime.
 *
 * Media3 requires a playing ExoPlayer and its preload manager to share the same builder-owned
 * components. We therefore keep one runtime per latency profile. Each runtime owns a preload
 * manager plus a tiny ExoPlayer pool, avoiding cross-profile LoadControl contamination.
 */
@OptIn(UnstableApi::class)
internal object FastVideoPreloadRuntime {
  private const val DEFAULT_POOL_SIZE = 2
  private const val MAX_POOL_SIZE = 6
  private const val DEFAULT_FORWARD_RADIUS = 4
  private const val DEFAULT_BACKWARD_RADIUS = 2

  private class StatusControl : TargetPreloadStatusControl<Int, DefaultPreloadManager.PreloadStatus> {
    @Volatile var currentIndex: Int = 0
    @Volatile private var direction: Int = 0
    @Volatile private var forwardRadius: Int = DEFAULT_FORWARD_RADIUS
    @Volatile private var backwardRadius: Int = DEFAULT_BACKWARD_RADIUS

    fun update(index: Int, direction: Int, forwardRadius: Int, backwardRadius: Int) {
      currentIndex = index
      this.direction = direction.coerceIn(-1, 1)
      this.forwardRadius = forwardRadius.coerceIn(1, 12)
      this.backwardRadius = backwardRadius.coerceIn(0, 8)
    }

    override fun getTargetPreloadStatus(index: Int): DefaultPreloadManager.PreloadStatus {
      val distance = index - currentIndex
      if (!insideIntentWindow(distance)) {
        return DefaultPreloadManager.PreloadStatus.PRELOAD_STATUS_NOT_PRELOADED
      }
      return when (FastCoreNative.preloadStage(distance)) {
        4 -> DefaultPreloadManager.PreloadStatus.specifiedRangeCached(
          FastCoreNative.preloadDurationMs(distance)
        )
        3 -> DefaultPreloadManager.PreloadStatus.specifiedRangeLoaded(
          FastCoreNative.preloadDurationMs(distance)
        )
        2 -> DefaultPreloadManager.PreloadStatus.PRELOAD_STATUS_TRACKS_SELECTED
        1 -> DefaultPreloadManager.PreloadStatus.PRELOAD_STATUS_SOURCE_PREPARED
        else -> DefaultPreloadManager.PreloadStatus.PRELOAD_STATUS_NOT_PRELOADED
      }
    }

    private fun insideIntentWindow(distance: Int): Boolean {
      if (distance == 0) return false
      if (direction == 0) {
        return distance in -maxOf(forwardRadius, backwardRadius)..maxOf(forwardRadius, backwardRadius)
      }
      val directedDistance = distance * direction
      return if (directedDistance > 0) {
        directedDistance <= forwardRadius
      } else {
        -directedDistance <= backwardRadius
      }
    }
  }

  private data class Runtime(
    val mode: String,
    val context: Context,
    val control: StatusControl,
    val builder: DefaultPreloadManager.Builder,
    val manager: DefaultPreloadManager,
    val itemsByIndex: MutableMap<Int, MediaItem> = mutableMapOf(),
    val pooledPlayers: ArrayDeque<ExoPlayer> = ArrayDeque()
  )

  private val runtimes = mutableMapOf<String, Runtime>()
  private var poolSizePerMode = DEFAULT_POOL_SIZE
  private var previousFocusIndex = 0

  @Synchronized
  fun configurePoolSize(value: Int?) {
    poolSizePerMode = (value ?: poolSizePerMode).coerceIn(0, MAX_POOL_SIZE)
    runtimes.values.forEach { runtime ->
      while (runtime.pooledPlayers.size > poolSizePerMode) {
        runtime.pooledPlayers.removeLast().release()
      }
    }
  }

  @Synchronized
  private fun ensure(context: Context, latencyMode: String): Runtime {
    val mode = normalizeMode(latencyMode)
    runtimes[mode]?.let { return it }

    val appContext = context.applicationContext
    val control = StatusControl()
    val policy = bufferPolicy(mode)
    val loadControl = DefaultLoadControl.Builder()
      .setBufferDurationsMs(
        policy.minBufferMs,
        policy.maxBufferMs,
        policy.playbackMs,
        policy.rebufferMs
      )
      .setPrioritizeTimeOverSizeThresholds(true)
      .build()

    val builder = DefaultPreloadManager.Builder(appContext, control)
      .setCache(FastVideoCacheRuntime.cache(appContext))
      .setDataSourceFactory(FastVideoCacheRuntime.upstreamFactory(appContext))
      .setLoadControl(loadControl)

    val runtime = Runtime(
      mode = mode,
      context = appContext,
      control = control,
      builder = builder,
      manager = builder.build()
    )
    runtimes[mode] = runtime
    return runtime
  }

  @Synchronized
  fun acquirePlayer(context: Context, latencyMode: String): ExoPlayer {
    val runtime = ensure(context, latencyMode)
    runtime.pooledPlayers.pollFirst()?.let { return it }
    return runtime.builder.buildExoPlayer(ExoPlayer.Builder(runtime.context))
  }

  @Synchronized
  fun recyclePlayer(latencyMode: String, player: ExoPlayer) {
    val runtime = runtimes[normalizeMode(latencyMode)]
    if (runtime == null || poolSizePerMode == 0 || runtime.pooledPlayers.size >= poolSizePerMode) {
      player.release()
      return
    }

    player.pause()
    player.stop()
    player.clearMediaItems()
    player.playWhenReady = false
    player.repeatMode = Player.REPEAT_MODE_OFF
    player.volume = 1f
    player.setPlaybackSpeed(1f)
    player.trackSelectionParameters = player.trackSelectionParameters
      .buildUpon()
      .clearOverrides()
      .setMaxVideoBitrate(Int.MAX_VALUE)
      .setMaxVideoSize(Int.MAX_VALUE, Int.MAX_VALUE)
      .setPreferredAudioLanguage(null)
      .setPreferredTextLanguage(null)
      .build()
    runtime.pooledPlayers.addFirst(player)
  }

  @Synchronized
  fun preload(context: Context, sources: List<FastVideoSource>, currentIndex: Int): Int {
    val grouped = sources.groupBy { normalizeMode(it.latencyMode) }
    var accepted = 0

    grouped.forEach { (mode, modeSources) ->
      val runtime = ensure(context, mode)
      runtime.manager.reset()
      runtime.itemsByIndex.clear()

      modeSources.forEachIndexed { fallbackIndex, source ->
        if (
          source.uri.isBlank() ||
          source.headers.isNotEmpty() ||
          source.drm != null ||
          source.subtitles.isNotEmpty()
        ) {
          return@forEachIndexed
        }
        val index = source.preloadIndex ?: fallbackIndex
        if (index < 0 || runtime.itemsByIndex.containsKey(index)) return@forEachIndexed
        val item = FastVideoMediaItemFactory.build(source, mode)
        runtime.itemsByIndex[index] = item
        runtime.manager.add(item, index)
        accepted += 1
      }

      runtime.control.update(currentIndex, 0, DEFAULT_FORWARD_RADIUS, DEFAULT_BACKWARD_RADIUS)
      runtime.manager.setCurrentPlayingIndex(currentIndex)
      runtime.manager.invalidate()
    }

    previousFocusIndex = currentIndex
    return accepted
  }

  @Synchronized
  fun mediaSource(latencyMode: String, index: Int?, item: MediaItem): MediaSource? {
    if (index == null) return null
    val runtime = runtimes[normalizeMode(latencyMode)] ?: return null
    val registered = runtime.itemsByIndex[index] ?: return null
    if (registered != item) return null
    return runtime.manager.getMediaSource(item)
  }

  @Synchronized
  fun focus(index: Int?, velocityItemsPerSecond: Double = 0.0): Map<String, Any?> {
    if (index == null || index < 0) return emptyMap()
    val itemCount = (runtimes.values.flatMap { it.itemsByIndex.keys }.maxOrNull() ?: index) + 1
    val intent = runCatching {
      val json = JSONObject(
        FastCoreNative.viewportIntent(index, previousFocusIndex, itemCount, velocityItemsPerSecond)
      )
      json.keys().asSequence().associateWith { key ->
        json.opt(key).takeUnless { it === JSONObject.NULL }
      }
    }.getOrDefault(emptyMap())

    val predicted = (intent["predictedIndex"] as? Number)
      ?.toInt()
      ?.coerceIn(0, maxOf(0, itemCount - 1))
      ?: index
    val direction = (intent["direction"] as? Number)?.toInt()?.coerceIn(-1, 1)
      ?: (index - previousFocusIndex).coerceIn(-1, 1)
    val forwardRadius = (intent["forwardRadius"] as? Number)
      ?.toInt()
      ?.coerceIn(1, 12)
      ?: DEFAULT_FORWARD_RADIUS
    val backwardRadius = (intent["backwardRadius"] as? Number)
      ?.toInt()
      ?.coerceIn(0, 8)
      ?: DEFAULT_BACKWARD_RADIUS

    previousFocusIndex = index
    runtimes.values.forEach { runtime ->
      runtime.control.update(predicted, direction, forwardRadius, backwardRadius)
      runtime.manager.setCurrentPlayingIndex(index)
      runtime.manager.invalidate()
    }
    return intent + mapOf(
      "actualIndex" to index,
      "appliedDirection" to direction,
      "appliedForwardRadius" to forwardRadius,
      "appliedBackwardRadius" to backwardRadius
    )
  }

  @Synchronized
  fun stats(): Map<String, Any> = mapOf(
    "pooledPlayers" to runtimes.values.sumOf { it.pooledPlayers.size },
    "poolSizePerLatencyMode" to poolSizePerMode,
    "latencyRuntimes" to runtimes.size
  )

  @Synchronized
  fun clear() {
    previousFocusIndex = 0
    runtimes.values.forEach { runtime ->
      runtime.manager.reset()
      runtime.itemsByIndex.clear()
      runtime.control.update(0, 0, DEFAULT_FORWARD_RADIUS, DEFAULT_BACKWARD_RADIUS)
    }
  }

  @Synchronized
  fun release() {
    runtimes.values.forEach { runtime ->
      runtime.pooledPlayers.forEach { it.release() }
      runtime.pooledPlayers.clear()
      runtime.manager.release()
      runtime.itemsByIndex.clear()
    }
    runtimes.clear()
    FastVideoCacheRuntime.release()
  }

  private data class BufferPolicy(
    val minBufferMs: Int,
    val maxBufferMs: Int,
    val playbackMs: Int,
    val rebufferMs: Int
  )

  private fun bufferPolicy(mode: String): BufferPolicy = when (mode) {
    "lowLatency" -> BufferPolicy(1_000, 8_000, 250, 500)
    "quality" -> BufferPolicy(15_000, 60_000, 1_500, 3_000)
    "memorySaver" -> BufferPolicy(2_000, 12_000, 500, 1_000)
    else -> BufferPolicy(5_000, 30_000, 750, 1_500)
  }

  private fun normalizeMode(value: String?): String = when (value) {
    "lowLatency", "quality", "memorySaver" -> value
    else -> "balanced"
  }
}
