package com.vivekjm.fastvideo

import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService

class FastVideoPlaybackService : MediaSessionService() {
  override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession? =
    FastVideoMediaSessionRuntime.currentSession()

  override fun onTaskRemoved(rootIntent: android.content.Intent?) {
    val session = FastVideoMediaSessionRuntime.currentSession()
    val player = session?.player
    if (player == null || !player.playWhenReady || player.mediaItemCount == 0) {
      stopSelf()
    }
  }
}
