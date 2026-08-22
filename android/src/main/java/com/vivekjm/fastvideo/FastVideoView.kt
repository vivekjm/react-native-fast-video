package com.vivekjm.fastvideo

import android.app.Activity
import android.app.PictureInPictureParams
import android.content.Context
import android.content.ContextWrapper
import android.graphics.SurfaceTexture
import android.os.Build
import android.util.Rational
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.TextureView
import android.view.View
import android.widget.FrameLayout
import androidx.annotation.OptIn
import androidx.media3.common.util.UnstableApi
import androidx.media3.ui.AspectRatioFrameLayout
import expo.modules.kotlin.AppContext
import expo.modules.kotlin.viewevent.EventDispatcher
import expo.modules.kotlin.views.ExpoView

@OptIn(UnstableApi::class)
class FastVideoView(
  context: Context,
  appContext: AppContext
) : ExpoView(context, appContext), FastVideoEngineListener {
  val onLoadStart by EventDispatcher<Map<String, Any?>>()
  val onReady by EventDispatcher<Map<String, Any?>>()
  val onPlaybackStateChange by EventDispatcher<Map<String, Any?>>()
  val onBuffer by EventDispatcher<Map<String, Any?>>()
  val onFirstFrame by EventDispatcher<Map<String, Any?>>()
  val onProgress by EventDispatcher<Map<String, Any?>>()
  val onMetrics by EventDispatcher<Map<String, Any?>>()
  val onAdaptiveDecision by EventDispatcher<Map<String, Any?>>()
  val onTracksChanged by EventDispatcher<Map<String, Any?>>()
  val onVideoSize by EventDispatcher<Map<String, Any?>>()
  val onEnd by EventDispatcher<Map<String, Any?>>()
  val onError by EventDispatcher<Map<String, Any?>>()
  val onPictureInPictureChange by EventDispatcher<Map<String, Any?>>()

  private val aspectFrame = AspectRatioFrameLayout(context).apply {
    resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT
  }
  private var renderView: View? = null
  private var surfaceType: String = "surface"
  private var contentFit: String = "contain"
  private var engine: FastVideoEngine? = null
  private var source: FastVideoSource? = null
  private var latencyMode: String = "balanced"
  private var autoplay = false
  private var paused = true
  private var muted = false
  private var volume = 1f
  private var rate = 1f
  private var repeat = false
  private var progressIntervalMs = 250L
  private var maxBitrate: Int? = null
  private var preferredAudioLanguage: String? = null
  private var preferredTextLanguage: String? = null
  private var released = false

  init {
    addView(
      aspectFrame,
      FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT)
    )
    replaceRenderView()
  }

  fun setSource(value: FastVideoSource?) {
    if (released) return
    source = value
    if (value == null || value.uri.isBlank()) {
      engine?.release()
      engine = null
      return
    }
    loadCurrentSource()
  }

  fun setAutoplay(value: Boolean) {
    autoplay = value
    if (value) {
      paused = false
      engine?.play()
    }
  }

  fun setPaused(value: Boolean) {
    paused = value
    if (value) engine?.pause() else engine?.play()
  }

  fun setMuted(value: Boolean) {
    muted = value
    applyVolume()
  }

  fun setVolume(value: Double) {
    if (!value.isFinite()) return
    volume = value.toFloat().coerceIn(0f, 1f)
    applyVolume()
  }

  fun setRate(value: Double) {
    if (!value.isFinite()) return
    rate = value.toFloat().coerceIn(0.25f, 4f)
    engine?.setRate(rate)
  }

  fun setRepeat(value: Boolean) {
    repeat = value
    engine?.setRepeat(value)
  }

  fun setLatencyMode(value: String) {
    val normalized = when (value) {
      "lowLatency", "quality", "memorySaver" -> value
      else -> "balanced"
    }
    if (latencyMode == normalized) return
    latencyMode = normalized
    if (source != null) recreateEngineAndLoad()
  }

  fun setProgressInterval(value: Double) {
    if (!value.isFinite()) return
    progressIntervalMs = value.toLong().coerceIn(100L, 2_000L)
    engine?.setProgressInterval(progressIntervalMs)
  }

  fun setSurfaceType(value: String) {
    val normalized = if (value == "texture") "texture" else "surface"
    if (surfaceType == normalized) return
    surfaceType = normalized
    replaceRenderView()
  }

  fun setContentFit(value: String) {
    contentFit = value
    aspectFrame.resizeMode = when (value) {
      "cover" -> AspectRatioFrameLayout.RESIZE_MODE_ZOOM
      "fill" -> AspectRatioFrameLayout.RESIZE_MODE_FILL
      "none" -> AspectRatioFrameLayout.RESIZE_MODE_FIXED_WIDTH
      else -> AspectRatioFrameLayout.RESIZE_MODE_FIT
    }
  }

  fun setMaxBitrate(value: Double?) {
    maxBitrate = value?.takeIf { it.isFinite() && it > 0 }?.toInt()
    engine?.setMaxBitrate(maxBitrate)
  }

  fun setPreferredAudioLanguage(value: String?) {
    preferredAudioLanguage = value
    engine?.setPreferredLanguages(preferredAudioLanguage, preferredTextLanguage)
  }

  fun setPreferredTextLanguage(value: String?) {
    preferredTextLanguage = value
    engine?.setPreferredLanguages(preferredAudioLanguage, preferredTextLanguage)
  }

  fun play() = engine?.play()
  fun pause() = engine?.pause()
  fun replay() = engine?.replay()
  fun seekTo(positionMs: Double) = engine?.seekTo(positionMs)
  fun seekBy(deltaMs: Double) = engine?.seekBy(deltaMs)
  fun goToLive() = engine?.goToLive()
  fun selectTrack(type: String, id: String?) = engine?.selectTrack(type, id)
  fun snapshot(): Map<String, Any?> = engine?.snapshot() ?: emptyMap()

  fun enterPictureInPicture(): Boolean {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
    val activity = context.findActivity() ?: return false
    val width = measuredWidth.coerceAtLeast(1)
    val height = measuredHeight.coerceAtLeast(1)
    val params = PictureInPictureParams.Builder()
      .setAspectRatio(Rational(width, height))
      .build()
    val entered = activity.enterPictureInPictureMode(params)
    if (entered) onPictureInPictureChange(mapOf("active" to true))
    return entered
  }

  fun release() {
    if (released) return
    released = true
    detachSurface(engine)
    engine?.release(preserveForBackground = source?.mediaSession == true)
    engine = null
  }

  private fun loadCurrentSource() {
    val item = source ?: return
    val current = engine ?: createEngine()
    // Keep the same ExoPlayer alive across feed/source changes. Media3 can reuse renderers,
    // codec instances, bandwidth state and preloaded MediaSources instead of paying a full
    // player construction cost for every cell transition.
    current.load(item, autoplay || !paused)
  }

  private fun recreateEngineAndLoad() {
    val old = engine
    detachSurface(old)
    old?.release()
    engine = null
    val item = source ?: return
    createEngine().load(item, autoplay || !paused)
  }

  private fun createEngine(): FastVideoEngine {
    val next = FastVideoEngine(context.applicationContext, latencyMode, this)
    engine = next
    next.setProgressInterval(progressIntervalMs)
    next.setRate(rate)
    next.setRepeat(repeat)
    next.setMaxBitrate(maxBitrate)
    next.setPreferredLanguages(preferredAudioLanguage, preferredTextLanguage)
    applyVolume()
    attachSurface(next)
    return next
  }

  private fun applyVolume() {
    engine?.setVolume(if (muted) 0f else volume)
  }

  private fun replaceRenderView() {
    val old = renderView
    detachSurface(engine)
    if (old != null) aspectFrame.removeView(old)

    val nextRenderView: View = if (surfaceType == "texture") {
      TextureView(context).also { texture ->
        texture.surfaceTextureListener = object : TextureView.SurfaceTextureListener {
          override fun onSurfaceTextureAvailable(surface: SurfaceTexture, width: Int, height: Int) {
            engine?.player?.setVideoTextureView(texture)
          }

          override fun onSurfaceTextureSizeChanged(surface: SurfaceTexture, width: Int, height: Int) = Unit

          override fun onSurfaceTextureDestroyed(surface: SurfaceTexture): Boolean {
            engine?.player?.clearVideoTextureView(texture)
            return true
          }

          override fun onSurfaceTextureUpdated(surface: SurfaceTexture) = Unit
        }
      }
    } else {
      SurfaceView(context).also { surface ->
        surface.holder.addCallback(object : SurfaceHolder.Callback {
          override fun surfaceCreated(holder: SurfaceHolder) {
            engine?.player?.setVideoSurfaceView(surface)
          }

          override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) = Unit

          override fun surfaceDestroyed(holder: SurfaceHolder) {
            engine?.player?.clearVideoSurfaceView(surface)
          }
        })
      }
    }

    renderView = nextRenderView
    aspectFrame.addView(
      nextRenderView,
      FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT)
    )
    attachSurface(engine)
  }

  private fun attachSurface(target: FastVideoEngine?) {
    val view = renderView ?: return
    val player = target?.player ?: return
    when (view) {
      is SurfaceView -> if (view.holder.surface?.isValid == true) player.setVideoSurfaceView(view)
      is TextureView -> if (view.isAvailable) player.setVideoTextureView(view)
    }
  }

  private fun detachSurface(target: FastVideoEngine?) {
    val view = renderView ?: return
    val player = target?.player ?: return
    when (view) {
      is SurfaceView -> player.clearVideoSurfaceView(view)
      is TextureView -> player.clearVideoTextureView(view)
    }
  }

  override fun emitLoadStart(uri: String) = onLoadStart(mapOf("uri" to uri))

  override fun emitReady(durationMs: Double, isLive: Boolean) {
    onReady(mapOf("durationMs" to durationMs, "isLive" to isLive))
  }

  override fun emitState(state: String) = onPlaybackStateChange(mapOf("state" to state))
  override fun emitBuffering(buffering: Boolean) = onBuffer(mapOf("buffering" to buffering))
  override fun emitFirstFrame() {
    val snapshot = engine?.snapshot().orEmpty()
    onFirstFrame(
      mapOf(
        "timestampMs" to System.currentTimeMillis(),
        "timeToFirstFrameMs" to snapshot["timeToFirstFrameMs"],
        "startupPath" to snapshot["startupPath"]
      )
    )
  }
  override fun emitProgress(payload: Map<String, Any?>) = onProgress(payload)
  override fun emitMetrics(payload: Map<String, Any?>) = onMetrics(payload)
  override fun emitAdaptiveDecision(payload: Map<String, Any?>) = onAdaptiveDecision(payload)
  override fun emitTracksChanged(payload: Map<String, Any?>) = onTracksChanged(payload)

  override fun emitVideoSize(width: Int, height: Int, pixelRatio: Float) {
    if (width > 0 && height > 0) {
      aspectFrame.setAspectRatio((width * pixelRatio) / height.toFloat())
    }
    onVideoSize(mapOf("width" to width, "height" to height, "pixelRatio" to pixelRatio))
  }

  override fun emitEnded() = onEnd(emptyMap())

  override fun emitError(code: String, message: String, nativeCode: String?) {
    onError(mapOf("code" to code, "message" to message, "nativeCode" to nativeCode))
  }
}

private tailrec fun Context.findActivity(): Activity? = when (this) {
  is Activity -> this
  is ContextWrapper -> baseContext.findActivity()
  else -> null
}
