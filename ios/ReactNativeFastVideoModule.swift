import ExpoModulesCore

public final class ReactNativeFastVideoModule: Module {
  public func definition() -> ModuleDefinition {
    Name("ReactNativeFastVideo")

    Function("getCapabilities") {
      FastVideoCapabilities.read()
    }

    Function("preload") { (sources: [FastVideoSource], currentIndex: Int) in
      let accepted = FastVideoPreloader.shared.preload(sources, currentIndex: currentIndex)
      return ["platform": "ios", "accepted": accepted, "strategy": "avasset-warm"] as [String: Any]
    }

    Function("focusPreloads") { (currentIndex: Int, velocityItemsPerSecond: Double) in
      FastVideoPreloader.shared.focus(currentIndex, velocityItemsPerSecond: velocityItemsPerSecond)
    }

    Function("clearPreloads") {
      FastVideoPreloader.shared.clear()
    }

    Function("configureRuntime") { (_: Double?, maxPooledPlayersPerMode: Int?, adaptiveMode: String?, _: Int?) in
      FastVideoAdaptiveRuntime.shared.configure(mode: adaptiveMode)
      var result = FastVideoAppleRuntime.shared.configure(maxPooledPlayers: maxPooledPlayersPerMode)
      result.merge(FastVideoAdaptiveRuntime.shared.stats()) { _, new in new }
      result.merge(FastVideoOfflineRuntime.shared.stats()) { _, new in new }
      result.merge(FastVideoCdnRuntime.shared.stats()) { _, new in new }
      result["platform"] = "ios"
      result["cacheStrategy"] = "avfoundation-managed"
      result["cacheBudgetControllable"] = false
      return result
    }

    Function("getRuntimeStats") {
      var result = FastVideoAppleRuntime.shared.stats()
      result.merge(FastVideoAdaptiveRuntime.shared.stats()) { _, new in new }
      result.merge(FastVideoOfflineRuntime.shared.stats()) { _, new in new }
      result.merge(FastVideoCdnRuntime.shared.stats()) { _, new in new }
      result["platform"] = "ios"
      result["cacheStrategy"] = "avfoundation-managed"
      result["cacheBudgetControllable"] = false
      return result
    }

    AsyncFunction("clearCache") {
      FastVideoAppleRuntime.shared.clearTransientState()
      return FastVideoAppleRuntime.shared.stats()
    }


    Function("downloadOffline") { (source: FastVideoSource, id: String?, title: String?) in
      try FastVideoOfflineRuntime.shared.enqueue(source: source, id: id, title: title)
    }

    Function("removeOfflineDownload") { (id: String) in
      FastVideoOfflineRuntime.shared.remove(id: id)
    }

    Function("listOfflineDownloads") {
      FastVideoOfflineRuntime.shared.list()
    }

    Function("pauseOfflineDownloads") {
      FastVideoOfflineRuntime.shared.pauseAll()
    }

    Function("resumeOfflineDownloads") {
      FastVideoOfflineRuntime.shared.resumeAll()
    }

    Function("stopBackgroundPlayback") {
      FastVideoNowPlayingRuntime.shared.stopBackgroundPlayback()
    }

    Function("resetNetworkDiagnostics") {
      FastVideoCdnRuntime.shared.clear()
    }

    View(FastVideoView.self) {
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

      Prop("source") { (view: FastVideoView, source: FastVideoSource?) in view.setSource(source) }
      Prop("autoplay") { (view: FastVideoView, value: Bool?) in view.setAutoplay(value ?? false) }
      Prop("paused") { (view: FastVideoView, value: Bool?) in view.setPaused(value ?? true) }
      Prop("muted") { (view: FastVideoView, value: Bool?) in view.setMuted(value ?? false) }
      Prop("volume") { (view: FastVideoView, value: Double?) in view.setVolume(value ?? 1) }
      Prop("rate") { (view: FastVideoView, value: Double?) in view.setRate(value ?? 1) }
      Prop("repeat") { (view: FastVideoView, value: Bool?) in view.setRepeat(value ?? false) }
      Prop("latencyMode") { (view: FastVideoView, value: String?) in
        view.setLatencyMode(value ?? "balanced")
      }
      Prop("progressIntervalMs") { (view: FastVideoView, value: Double?) in
        view.setProgressInterval(value ?? 250)
      }
      Prop("contentFit") { (view: FastVideoView, value: String?) in
        view.setContentFit(value ?? "contain")
      }
      Prop("maxBitrate") { (view: FastVideoView, value: Double?) in
        view.setMaxBitrate(value)
      }
      Prop("preferredAudioLanguage") { (view: FastVideoView, value: String?) in
        view.setPreferredAudioLanguage(value)
      }
      Prop("preferredTextLanguage") { (view: FastVideoView, value: String?) in
        view.setPreferredTextLanguage(value)
      }
      Prop("allowsExternalPlayback") { (view: FastVideoView, value: Bool?) in
        view.setAllowsExternalPlayback(value ?? true)
      }

      AsyncFunction("play") { (view: FastVideoView) in view.play() }
      AsyncFunction("pause") { (view: FastVideoView) in view.pause() }
      AsyncFunction("replay") { (view: FastVideoView) in view.replay() }
      AsyncFunction("seekTo") { (view: FastVideoView, positionMs: Double) in view.seekTo(positionMs) }
      AsyncFunction("seekBy") { (view: FastVideoView, deltaMs: Double) in view.seekBy(deltaMs) }
      AsyncFunction("goToLive") { (view: FastVideoView) in view.goToLive() }
      AsyncFunction("selectTrack") { (view: FastVideoView, type: String, id: String?) in
        view.selectTrack(type: type, id: id)
      }
      AsyncFunction("getSnapshot") { (view: FastVideoView) in view.snapshot() }
      AsyncFunction("enterPictureInPicture") { (view: FastVideoView) in
        view.enterPictureInPicture()
      }
      AsyncFunction("stopPictureInPicture") { (view: FastVideoView) in
        view.stopPictureInPicture()
      }

      OnViewDestroys { view in view.release() }
    }
  }
}
