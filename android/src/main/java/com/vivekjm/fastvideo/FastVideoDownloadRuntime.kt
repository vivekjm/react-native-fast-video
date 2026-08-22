package com.vivekjm.fastvideo

import android.content.Context
import android.net.Uri
import androidx.annotation.OptIn
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.database.StandaloneDatabaseProvider
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.cache.CacheDataSource
import androidx.media3.datasource.cache.NoOpCacheEvictor
import androidx.media3.datasource.cache.SimpleCache
import androidx.media3.exoplayer.offline.Download
import androidx.media3.exoplayer.offline.DownloadManager
import androidx.media3.exoplayer.offline.DownloadRequest
import androidx.media3.exoplayer.offline.DownloadService
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors

@OptIn(UnstableApi::class)
internal object FastVideoDownloadRuntime {
  private var databaseProvider: StandaloneDatabaseProvider? = null
  private var downloadCache: SimpleCache? = null
  private var downloadManager: DownloadManager? = null

  @Synchronized
  fun manager(context: Context): DownloadManager {
    downloadManager?.let { return it }
    val app = context.applicationContext
    val db = StandaloneDatabaseProvider(app)
    val directory = File(app.getExternalFilesDir(null) ?: app.filesDir, "react-native-fast-video-offline")
    val cache = SimpleCache(directory, NoOpCacheEvictor(), db)
    val upstream = DefaultHttpDataSource.Factory()
      .setUserAgent("react-native-fast-video/0.0.5")
      .setAllowCrossProtocolRedirects(true)
    val manager = DownloadManager(app, db, cache, upstream, Executors.newFixedThreadPool(3)).apply {
      maxParallelDownloads = 3
      minRetryCount = 3
    }
    databaseProvider = db
    downloadCache = cache
    downloadManager = manager
    return manager
  }

  fun offlineDataSourceFactory(context: Context): DataSource.Factory {
    manager(context)
    return CacheDataSource.Factory()
      .setCache(requireNotNull(downloadCache))
      .setUpstreamDataSourceFactory(null)
      .setFlags(CacheDataSource.FLAG_IGNORE_CACHE_ON_ERROR)
  }

  fun isCompleted(context: Context, id: String): Boolean =
    runCatching { manager(context).downloadIndex.getDownload(id)?.state == Download.STATE_COMPLETED }.getOrDefault(false)

  fun enqueue(context: Context, source: FastVideoSource, requestedId: String?): Map<String, Any?> {
    require(source.uri.isNotBlank()) { "Offline source URI must not be blank" }
    require(source.headers.isEmpty()) { "Authenticated offline downloads require app-level signed URLs in 0.0.5" }
    require(source.drm == null) { "Offline DRM licenses are not enabled in 0.0.5" }
    val id = requestedId?.takeIf { it.isNotBlank() } ?: source.customCacheKey ?: UUID.randomUUID().toString()
    val request = DownloadRequest.Builder(id, Uri.parse(source.uri))
      .setMimeType(mimeType(source.type))
      .apply {
        if (source.type.equals("progressive", true) || source.type.equals("auto", true)) {
          source.customCacheKey?.let { setCustomCacheKey(it) }
        }
      }
      .build()
    manager(context) // initialize before service receives the command
    DownloadService.sendAddDownload(context, FastVideoDownloadService::class.java, request, true)
    return mapOf("id" to id, "state" to "queued", "uri" to source.uri)
  }

  fun remove(context: Context, id: String): Map<String, Any?> {
    DownloadService.sendRemoveDownload(context, FastVideoDownloadService::class.java, id, true)
    return mapOf("id" to id, "removed" to true)
  }

  fun pauseAll(context: Context) {
    DownloadService.sendPauseDownloads(context, FastVideoDownloadService::class.java, true)
  }

  fun resumeAll(context: Context) {
    DownloadService.sendResumeDownloads(context, FastVideoDownloadService::class.java, true)
  }

  fun list(context: Context): List<Map<String, Any?>> {
    val cursor = manager(context).downloadIndex.getDownloads()
    val output = mutableListOf<Map<String, Any?>>()
    cursor.use {
      while (it.moveToNext()) output += describe(it.download)
    }
    return output
  }

  fun stats(context: Context): Map<String, Any?> {
    val manager = manager(context)
    return mapOf(
      "offlineDownloads" to list(context).size,
      "offlineDownloadsPaused" to manager.downloadsPaused,
      "offlineCacheBytes" to (downloadCache?.cacheSpace ?: 0L)
    )
  }

  @Synchronized
  fun release() {
    downloadManager?.release()
    downloadManager = null
    downloadCache?.release()
    downloadCache = null
    databaseProvider?.close()
    databaseProvider = null
  }

  private fun describe(download: Download): Map<String, Any?> = mapOf(
    "id" to download.request.id,
    "uri" to download.request.uri.toString(),
    "state" to stateName(download.state),
    "bytesDownloaded" to download.bytesDownloaded,
    "percentDownloaded" to download.percentDownloaded.toDouble().takeIf { it.isFinite() && it >= 0 },
    "contentLength" to download.contentLength.takeIf { it >= 0 },
    "failureReason" to download.failureReason.takeIf { it != Download.FAILURE_REASON_NONE },
    "stopReason" to download.stopReason
  )

  private fun stateName(state: Int): String = when (state) {
    Download.STATE_QUEUED -> "queued"
    Download.STATE_STOPPED -> "stopped"
    Download.STATE_DOWNLOADING -> "downloading"
    Download.STATE_COMPLETED -> "completed"
    Download.STATE_FAILED -> "failed"
    Download.STATE_REMOVING -> "removing"
    Download.STATE_RESTARTING -> "restarting"
    else -> "unknown"
  }

  private fun mimeType(type: String): String? = when (type.lowercase()) {
    "hls" -> MimeTypes.APPLICATION_M3U8
    "dash" -> MimeTypes.APPLICATION_MPD
    "smoothstreaming", "ss" -> MimeTypes.APPLICATION_SS
    else -> null
  }
}
