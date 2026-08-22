package com.vivekjm.fastvideo

import expo.modules.kotlin.functions.Queues
import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition

class ReactNativeFastVideoModule : Module() {
  override fun definition() = ModuleDefinition {
    Name("ReactNativeFastVideo")

    AsyncFunction("getCapabilities") {
      FastVideoCapabilities.read(appContext.reactContext ?: appContext.throwingActivity.applicationContext)
    }

    Function("preload") { sources: List<FastVideoSource>, currentIndex: Int ->
      val context = appContext.reactContext ?: appContext.throwingActivity.applicationContext
      val accepted = FastVideoPreloadRuntime.preload(context, sources, currentIndex)
      mapOf("platform" to "android", "accepted" to accepted, "strategy" to "media3-memory-disk")
    }

    Function("configureRuntime") { cacheMaxBytes: Double?, maxPooledPlayersPerMode: Int?, adaptiveMode: String?, maxParallelDownloads: Int? ->
      val context = appContext.reactContext ?: appContext.throwingActivity.applicationContext
      val cache = FastVideoCacheRuntime.configure(cacheMaxBytes?.takeIf { it.isFinite() && it > 0 }?.toLong())
      FastVideoPreloadRuntime.configurePoolSize(maxPooledPlayersPerMode)
      FastVideoAdaptiveRuntime.configure(adaptiveMode)
      maxParallelDownloads?.coerceIn(1, 6)?.let { FastVideoDownloadRuntime.manager(context).maxParallelDownloads = it }
      cache + FastVideoPreloadRuntime.stats() + FastVideoAdaptiveRuntime.runtimeStats(context) + FastVideoDownloadRuntime.stats(context) + FastVideoCdnRuntime.stats()
    }

    Function("getRuntimeStats") {
      val context = appContext.reactContext ?: appContext.throwingActivity.applicationContext
      FastVideoCacheRuntime.stats(context) + FastVideoPreloadRuntime.stats() + FastVideoAdaptiveRuntime.runtimeStats(context) + FastVideoDownloadRuntime.stats(context) + FastVideoCdnRuntime.stats() + mapOf("platform" to "android")
    }

    AsyncFunction("clearCache") {
      val context = appContext.reactContext ?: appContext.throwingActivity.applicationContext
      FastVideoCacheRuntime.clear(context)
    }


    Function("downloadOffline") { source: FastVideoSource, id: String?, _: String? ->
      val context = appContext.reactContext ?: appContext.throwingActivity.applicationContext
      FastVideoDownloadRuntime.enqueue(context, source, id)
    }

    Function("removeOfflineDownload") { id: String ->
      val context = appContext.reactContext ?: appContext.throwingActivity.applicationContext
      FastVideoDownloadRuntime.remove(context, id)
    }

    Function("listOfflineDownloads") {
      val context = appContext.reactContext ?: appContext.throwingActivity.applicationContext
      FastVideoDownloadRuntime.list(context)
    }

    Function("pauseOfflineDownloads") {
      val context = appContext.reactContext ?: appContext.throwingActivity.applicationContext
      FastVideoDownloadRuntime.pauseAll(context)
    }

    Function("resumeOfflineDownloads") {
      val context = appContext.reactContext ?: appContext.throwingActivity.applicationContext
      FastVideoDownloadRuntime.resumeAll(context)
    }

    Function("stopBackgroundPlayback") {
      FastVideoMediaSessionRuntime.stopBackgroundPlayback()
    }

    Function("resetNetworkDiagnostics") {
      FastVideoCdnRuntime.clear()
    }

    Function("focusPreloads") { currentIndex: Int, velocityItemsPerSecond: Double ->
      FastVideoPreloadRuntime.focus(currentIndex, velocityItemsPerSecond)
    }

    Function("clearPreloads") {
      FastVideoPreloadRuntime.clear()
    }

    OnDestroy {
      FastVideoPreloadRuntime.release()
    }

    View(FastVideoView::class) {
      Events(
        "onLoadStart",
        "onReady",
        "onPlaybackStateChange",
        "onBuffer",
        "onFirstFrame",
        "onProgress",
        "onMetrics",
        "onAdaptiveDecision",
        "onTracksChanged",
        "onVideoSize",
        "onEnd",
        "onError",
        "onPictureInPictureChange"
      )

      Prop("source") { view: FastVideoView, source: FastVideoSource? -> view.setSource(source) }
      Prop("autoplay") { view: FastVideoView, value: Boolean? -> view.setAutoplay(value ?: false) }
      Prop("paused") { view: FastVideoView, value: Boolean? -> view.setPaused(value ?: true) }
      Prop("muted") { view: FastVideoView, value: Boolean? -> view.setMuted(value ?: false) }
      Prop("volume") { view: FastVideoView, value: Double? -> view.setVolume(value ?: 1.0) }
      Prop("rate") { view: FastVideoView, value: Double? -> view.setRate(value ?: 1.0) }
      Prop("repeat") { view: FastVideoView, value: Boolean? -> view.setRepeat(value ?: false) }
      Prop("latencyMode") { view: FastVideoView, value: String? -> view.setLatencyMode(value ?: "balanced") }
      Prop("progressIntervalMs") { view: FastVideoView, value: Double? -> view.setProgressInterval(value ?: 250.0) }
      Prop("surfaceType") { view: FastVideoView, value: String? -> view.setSurfaceType(value ?: "surface") }
      Prop("contentFit") { view: FastVideoView, value: String? -> view.setContentFit(value ?: "contain") }
      Prop("maxBitrate") { view: FastVideoView, value: Double? -> view.setMaxBitrate(value) }
      Prop("preferredAudioLanguage") { view: FastVideoView, value: String? ->
        view.setPreferredAudioLanguage(value)
      }
      Prop("preferredTextLanguage") { view: FastVideoView, value: String? ->
        view.setPreferredTextLanguage(value)
      }

      AsyncFunction("play") { view: FastVideoView -> view.play() }.runOnQueue(Queues.MAIN)
      AsyncFunction("pause") { view: FastVideoView -> view.pause() }.runOnQueue(Queues.MAIN)
      AsyncFunction("replay") { view: FastVideoView -> view.replay() }.runOnQueue(Queues.MAIN)
      AsyncFunction("seekTo") { view: FastVideoView, positionMs: Double -> view.seekTo(positionMs) }
        .runOnQueue(Queues.MAIN)
      AsyncFunction("seekBy") { view: FastVideoView, deltaMs: Double -> view.seekBy(deltaMs) }
        .runOnQueue(Queues.MAIN)
      AsyncFunction("goToLive") { view: FastVideoView -> view.goToLive() }.runOnQueue(Queues.MAIN)
      AsyncFunction("selectTrack") { view: FastVideoView, type: String, id: String? ->
        view.selectTrack(type, id)
      }.runOnQueue(Queues.MAIN)
      AsyncFunction("getSnapshot") { view: FastVideoView -> view.snapshot() }.runOnQueue(Queues.MAIN)
      AsyncFunction("enterPictureInPicture") { view: FastVideoView -> view.enterPictureInPicture() }
        .runOnQueue(Queues.MAIN)

      OnViewDestroys { view -> view.release() }
    }
  }
}
