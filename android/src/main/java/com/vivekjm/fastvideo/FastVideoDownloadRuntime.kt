package com.vivekjm.fastvideo

import android.content.Context
import android.net.Uri
import androidx.annotation.OptIn
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.database.StandaloneDatabaseProvider
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.cache.CacheDataSource
import androidx.media3.datasource.cache.NoOpCacheEvictor
import androidx.media3.datasource.cache.SimpleCache
import androidx.media3.exoplayer.offline.Download
import androidx.media3.exoplayer.offline.DownloadManager
import androidx.media3.exoplayer.offline.DownloadRequest
import androidx.media3.exoplayer.offline.DownloadService
import java.io.File
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.json.JSONObject

/** Durable media downloads. This cache is intentionally separate from the evicting feed cache. */
@OptIn(UnstableApi::class)
internal object FastVideoDownloadRuntime {
  private const val COMPLETION_PREFS = "react-native-fast-video.offline-completion.v1"
  private const val DEFAULT_PARALLEL_DOWNLOADS = 3

  @Volatile private var databaseProvider: StandaloneDatabaseProvider? = null
  @Volatile private var offlineCache: SimpleCache? = null
  @Volatile private var downloadManager: DownloadManager? = null
  private val downloadExecutor = Executors.newFixedThreadPool(DEFAULT_PARALLEL_DOWNLOADS)
  private val indexExecutor = Executors.newSingleThreadExecutor()
  private val completedIds = ConcurrentHashMap.newKeySet<String>()
  @Volatile private var completionIndexLoaded = false

  @Synchronized
  fun manager(context: Context): DownloadManager {
    downloadManager?.let { return it }
    val appContext = context.applicationContext
    val provider = databaseProvider ?: StandaloneDatabaseProvider(appContext).also {
      databaseProvider = it
    }
    val cache = cache(appContext)
    val manager = DownloadManager(
      appContext,
      provider,
      cache,
      FastVideoDownloadHeaderRegistry.factory(appContext),
      downloadExecutor
    )
    manager.maxParallelDownloads = DEFAULT_PARALLEL_DOWNLOADS
    manager.addListener(object : DownloadManager.Listener {
      override fun onDownloadChanged(
        downloadManager: DownloadManager,
        download: Download,
        finalException: Exception?
      ) {
        updateCompletion(appContext, download)
      }

      override fun onDownloadRemoved(downloadManager: DownloadManager, download: Download) {
        completedIds.remove(download.request.id)
        completionPrefs(appContext).edit().remove(download.request.id).apply()
        FastVideoDownloadHeaderRegistry.unregister(appContext, download.request.id)
      }
    })
    downloadManager = manager
    loadCompletionIndex(appContext, manager)
    return manager
  }

  @Synchronized
  private fun cache(context: Context): SimpleCache {
    offlineCache?.let { return it }
    val provider = databaseProvider ?: StandaloneDatabaseProvider(context.applicationContext).also {
      databaseProvider = it
    }
    val directory = File(context.applicationContext.filesDir, "react-native-fast-video/offline")
      .apply { mkdirs() }
    return SimpleCache(directory, NoOpCacheEvictor(), provider).also { offlineCache = it }
  }

  fun enqueue(context: Context, source: FastVideoSource, requestedId: String?): Map<String, Any?> {
    require(source.uri.isNotBlank()) { "Offline source URI must not be empty." }
    require(!source.isLive) { "Active live streams cannot be stored as durable offline media." }
    require(source.drm == null) {
      "Offline DRM license persistence is a Phase 6 capability; clear-content downloads only."
    }

    val appContext = context.applicationContext
    val id = requestedId?.trim()?.takeIf { it.isNotEmpty() }
      ?: source.customCacheKey?.trim()?.takeIf { it.isNotEmpty() }
      ?: stableId(source.uri)
    val mimeType = mimeType(source)
    val adaptive = mimeType == MimeTypes.APPLICATION_M3U8 ||
      mimeType == MimeTypes.APPLICATION_MPD ||
      mimeType == MimeTypes.APPLICATION_SS

    FastVideoDownloadHeaderRegistry.register(appContext, id, source.uri, source.headers)
    completedIds.remove(id)
    completionPrefs(appContext).edit().putBoolean(id, false).apply()

    val metadata = JSONObject()
      .put("uri", source.uri)
      .put("type", source.type)
      .put("title", source.metadata?.title)
      .put("headersPersisted", source.headers.isNotEmpty())
      .toString()
      .toByteArray(StandardCharsets.UTF_8)

    val builder = DownloadRequest.Builder(id, Uri.parse(source.uri))
      .setData(metadata)
    mimeType?.let(builder::setMimeType)
    if (!adaptive) {
      source.customCacheKey
        ?.trim()
        ?.takeIf { it.isNotEmpty() }
        ?.let(builder::setCustomCacheKey)
    }
    val request = builder.build()

    DownloadService.sendAddDownload(
      appContext,
      FastVideoDownloadService::class.java,
      request,
      true
    )
    return mapOf(
      "id" to id,
      "uri" to source.uri,
      "state" to "queued",
      "headersPersisted" to source.headers.isNotEmpty()
    )
  }

  fun remove(context: Context, id: String): Map<String, Any?> {
    val normalized = id.trim()
    require(normalized.isNotEmpty()) { "Offline download id must not be empty." }
    val appContext = context.applicationContext
    completedIds.remove(normalized)
    completionPrefs(appContext).edit().remove(normalized).apply()
    FastVideoDownloadHeaderRegistry.unregister(appContext, normalized)
    DownloadService.sendRemoveDownload(
      appContext,
      FastVideoDownloadService::class.java,
      normalized,
      false
    )
    return mapOf("id" to normalized, "state" to "removing")
  }

  fun pauseAll(context: Context) {
    DownloadService.sendPauseDownloads(
      context.applicationContext,
      FastVideoDownloadService::class.java,
      false
    )
  }

  fun resumeAll(context: Context) {
    DownloadService.sendResumeDownloads(
      context.applicationContext,
      FastVideoDownloadService::class.java,
      false
    )
  }

  fun list(context: Context): List<Map<String, Any?>> {
    val appContext = context.applicationContext
    val manager = manager(appContext)
    val result = mutableListOf<Map<String, Any?>>()
    manager.downloadIndex.getDownloads().use { cursor ->
      while (cursor.moveToNext()) {
        val download = cursor.download
        updateCompletion(appContext, download)
        val metadata = parseMetadata(download.request.data)
        result += mapOf(
          "id" to download.request.id,
          "uri" to download.request.uri.toString(),
          "state" to stateName(download.state),
          "percentDownloaded" to download.percentDownloaded.toDouble(),
          "bytesDownloaded" to download.bytesDownloaded.toDouble(),
          "contentLength" to download.contentLength.toDouble(),
          "failureReason" to download.failureReason.takeIf { it != Download.FAILURE_REASON_NONE },
          "stopReason" to download.stopReason,
          "title" to metadata.optString("title").takeIf { it.isNotBlank() },
          "headersPersisted" to metadata.optBoolean("headersPersisted", false)
        )
      }
    }
    return result
  }

  fun isCompleted(context: Context, id: String): Boolean {
    val normalized = id.trim()
    if (normalized.isEmpty()) return false
    val appContext = context.applicationContext
    if (completedIds.contains(normalized)) return true
    val prefs = completionPrefs(appContext)
    if (prefs.contains(normalized)) return prefs.getBoolean(normalized, false)

    // Legacy migration: perform index I/O on a dedicated worker, never directly on the UI thread.
    return runCatching {
      indexExecutor.submit<Boolean> {
        val download = manager(appContext).downloadIndex.getDownload(normalized)
        if (download != null) updateCompletion(appContext, download)
        download?.state == Download.STATE_COMPLETED
      }.get(750, TimeUnit.MILLISECONDS)
    }.getOrDefault(false)
  }

  fun offlineDataSourceFactory(context: Context): DataSource.Factory =
    CacheDataSource.Factory()
      .setCache(cache(context.applicationContext))
      .setUpstreamDataSourceFactory(null)
      .setCacheWriteDataSinkFactory(null)
      .setFlags(CacheDataSource.FLAG_BLOCK_ON_CACHE)

  fun stats(context: Context): Map<String, Any> {
    val appContext = context.applicationContext
    val manager = manager(appContext)
    return mapOf(
      "offlineCacheBytes" to cache(appContext).cacheSpace.toDouble(),
      "maxParallelDownloads" to manager.maxParallelDownloads,
      "downloadsPaused" to manager.downloadsPaused,
      "completionIndexLoaded" to completionIndexLoaded,
      "completedOfflineDownloads" to completedIds.size
    ) + FastVideoDownloadHeaderRegistry.stats(appContext)
  }

  private fun loadCompletionIndex(context: Context, manager: DownloadManager) {
    if (completionIndexLoaded) return
    indexExecutor.execute {
      runCatching {
        manager.downloadIndex.getDownloads().use { cursor ->
          while (cursor.moveToNext()) updateCompletion(context, cursor.download)
        }
      }
      completionIndexLoaded = true
    }
  }

  private fun updateCompletion(context: Context, download: Download) {
    val completed = download.state == Download.STATE_COMPLETED
    if (completed) completedIds.add(download.request.id) else completedIds.remove(download.request.id)
    completionPrefs(context).edit().putBoolean(download.request.id, completed).apply()
  }

  private fun completionPrefs(context: Context) = context.applicationContext
    .getSharedPreferences(COMPLETION_PREFS, Context.MODE_PRIVATE)

  private fun parseMetadata(data: ByteArray): JSONObject = runCatching {
    JSONObject(String(data, StandardCharsets.UTF_8))
  }.getOrDefault(JSONObject())

  private fun mimeType(source: FastVideoSource): String? = when (source.type.lowercase()) {
    "hls" -> MimeTypes.APPLICATION_M3U8
    "dash" -> MimeTypes.APPLICATION_MPD
    "smoothstreaming", "ss" -> MimeTypes.APPLICATION_SS
    else -> when {
      source.uri.substringBefore('?').substringBefore('#').endsWith(".m3u8", true) ->
        MimeTypes.APPLICATION_M3U8
      source.uri.substringBefore('?').substringBefore('#').endsWith(".mpd", true) ->
        MimeTypes.APPLICATION_MPD
      else -> null
    }
  }

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

  private fun stableId(uri: String): String {
    val digest = MessageDigest.getInstance("SHA-256")
      .digest(uri.toByteArray(StandardCharsets.UTF_8))
      .joinToString("") { byte -> "%02x".format(byte) }
    return "rnfv-${digest.take(24)}"
  }
}
