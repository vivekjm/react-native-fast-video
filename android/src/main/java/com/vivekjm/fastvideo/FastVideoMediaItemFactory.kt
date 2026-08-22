package com.vivekjm.fastvideo

import android.net.Uri
import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import java.util.Locale

@OptIn(UnstableApi::class)
internal object FastVideoMediaItemFactory {
  fun build(source: FastVideoSource, latencyMode: String): MediaItem {
    val builder = MediaItem.Builder().setUri(Uri.parse(source.uri))
    when (source.type.lowercase(Locale.US)) {
      "hls" -> builder.setMimeType(MimeTypes.APPLICATION_M3U8)
      "dash" -> builder.setMimeType(MimeTypes.APPLICATION_MPD)
      "smoothstreaming", "ss" -> builder.setMimeType(MimeTypes.APPLICATION_SS)
    }

    source.customCacheKey?.let { builder.setCustomCacheKey(it) }
    source.metadata?.let { metadata ->
      builder.setMediaMetadata(
        MediaMetadata.Builder()
          .setTitle(metadata.title)
          .setArtist(metadata.artist)
          .setAlbumTitle(metadata.albumTitle)
          .setArtworkUri(metadata.artworkUri?.takeIf { it.isNotBlank() }?.let(Uri::parse))
          .build()
      )
    }

    if (source.isLive || source.targetLiveOffsetMs != null) {
      val policy = policy(latencyMode)
      val live = MediaItem.LiveConfiguration.Builder()
        .setTargetOffsetMs((source.targetLiveOffsetMs ?: policy.targetLiveOffsetMs.toDouble()).toLong())
        .setMinPlaybackSpeed(policy.minLiveSpeed)
        .setMaxPlaybackSpeed(policy.maxLiveSpeed)
        .build()
      builder.setLiveConfiguration(live)
    }

    val subtitles = source.subtitles
      .filter { it.uri.isNotBlank() }
      .map { subtitle ->
        MediaItem.SubtitleConfiguration.Builder(Uri.parse(subtitle.uri))
          .setId(subtitle.id ?: subtitle.uri)
          .setMimeType(subtitle.mimeType)
          .setLanguage(subtitle.language)
          .setLabel(subtitle.label)
          .setSelectionFlags(if (subtitle.isDefault) C.SELECTION_FLAG_DEFAULT else 0)
          .build()
      }
    if (subtitles.isNotEmpty()) builder.setSubtitleConfigurations(subtitles)

    source.drm?.takeIf { it.type.equals("widevine", ignoreCase = true) && it.licenseUrl.isNotBlank() }?.let { drm ->
      builder.setDrmConfiguration(
        MediaItem.DrmConfiguration.Builder(C.WIDEVINE_UUID)
          .setLicenseUri(drm.licenseUrl)
          .setLicenseRequestHeaders(drm.headers)
          .setMultiSession(drm.multiSession)
          .build()
      )
    }
    return builder.build()
  }

  internal data class LivePolicy(
    val targetLiveOffsetMs: Int,
    val minLiveSpeed: Float,
    val maxLiveSpeed: Float
  )

  private fun policy(mode: String): LivePolicy = when (mode) {
    "lowLatency" -> LivePolicy(2_000, 0.97f, 1.05f)
    "quality" -> LivePolicy(8_000, 0.98f, 1.02f)
    "memorySaver" -> LivePolicy(5_000, 0.98f, 1.03f)
    else -> LivePolicy(5_000, 0.98f, 1.03f)
  }
}
