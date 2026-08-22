package com.vivekjm.fastvideo

import android.content.Context
import android.content.Intent
import androidx.annotation.OptIn
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.session.MediaSession

@OptIn(UnstableApi::class)
internal object FastVideoMediaSessionRuntime {
  @Volatile private var session: MediaSession? = null
  @Volatile private var attachedPlayer: Player? = null
  @Volatile private var backgroundPlayer: Player? = null

  @Synchronized
  fun attach(context: Context, player: Player, source: FastVideoSource) {
    if (backgroundPlayer !== null && backgroundPlayer !== player) {
      backgroundPlayer?.stop()
      backgroundPlayer?.release()
      backgroundPlayer = null
      FastVideoAdaptiveRuntime.onPlayerReleased()
    }
    val metadata = source.metadata
    val mediaMetadata = MediaMetadata.Builder()
      .setTitle(metadata?.title)
      .setArtist(metadata?.artist)
      .setAlbumTitle(metadata?.albumTitle)
      .setArtworkUri(metadata?.artworkUri?.takeIf { it.isNotBlank() }?.let(android.net.Uri::parse))
      .build()
    player.currentMediaItem?.let { current ->
      player.replaceMediaItem(player.currentMediaItemIndex, current.buildUpon().setMediaMetadata(mediaMetadata).build())
    }
    val existing = session
    if (existing == null) session = MediaSession.Builder(context.applicationContext, player).setId("react-native-fast-video").build()
    else if (attachedPlayer !== player) existing.player = player
    attachedPlayer = player
    runCatching { context.applicationContext.startService(Intent(context.applicationContext, FastVideoPlaybackService::class.java)) }
  }

  @Synchronized
  fun detach(player: Player, keepAlive: Boolean = false): Boolean {
    if (attachedPlayer !== player) return false
    if (keepAlive && player.isPlaying) {
      if (backgroundPlayer !== player) FastVideoAdaptiveRuntime.onPlayerAcquired()
      backgroundPlayer = player
      attachedPlayer = player
      return true
    }
    attachedPlayer = null
    if (backgroundPlayer === player) backgroundPlayer = null
    session?.release(); session = null
    return false
  }

  @Synchronized fun currentSession(): MediaSession? = session

  @Synchronized
  fun stopBackgroundPlayback() {
    backgroundPlayer?.stop()
    backgroundPlayer?.release()
    if (backgroundPlayer != null) FastVideoAdaptiveRuntime.onPlayerReleased()
    backgroundPlayer = null
    attachedPlayer = null
    session?.release(); session = null
  }

  @Synchronized
  fun release() = stopBackgroundPlayback()
}
