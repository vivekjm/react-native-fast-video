package com.vivekjm.fastvideo

internal object FastCoreNative {
  init {
    System.loadLibrary("react-native-fast-video")
  }

  external fun create(): Long
  external fun destroy(handle: Long)
  external fun event(handle: Long, eventCode: Int, a: Double, b: Double, c: Double)
  external fun setProgressInterval(handle: Long, intervalMs: Long)
  external fun shouldEmitProgress(handle: Long): Boolean
  external fun snapshot(handle: Long): String
  external fun preloadStage(distance: Int): Int
  external fun preloadDurationMs(distance: Int): Long
  external fun viewportIntent(currentIndex: Int, previousIndex: Int, itemCount: Int, velocityItemsPerSecond: Double): String
  external fun cdnHealth(successRate: Double, errorRate: Double, medianTtffMs: Double, medianResponseMs: Double, consecutiveFailures: Int): String
  external fun adaptiveDecision(
    bandwidthEstimateBps: Double,
    rebufferRatio: Double,
    droppedFrameRatio: Double,
    activePlayers: Int,
    width: Int,
    height: Int,
    networkClass: Int,
    thermalClass: Int,
    lowPowerMode: Boolean
  ): String
}

internal object FastCoreEvent {
  const val LOAD = 1
  const val READY = 2
  const val PLAY = 3
  const val PAUSE = 4
  const val BUFFERING_START = 5
  const val BUFFERING_END = 6
  const val FIRST_FRAME = 7
  const val SEEK_START = 8
  const val SEEK_COMPLETE = 9
  const val FRAMES = 10
  const val BYTES = 11
  const val PROGRESS = 12
  const val LIVE_OFFSET = 13
  const val ENDED = 14
  const val ERROR = 15
  const val RELEASE = 16
  const val FRAME_PROCESSING = 17
}
