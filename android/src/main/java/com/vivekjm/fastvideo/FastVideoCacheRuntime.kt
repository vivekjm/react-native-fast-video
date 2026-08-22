package com.vivekjm.fastvideo

import android.content.Context
import androidx.annotation.OptIn
import androidx.media3.common.util.UnstableApi
import androidx.media3.database.StandaloneDatabaseProvider
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.datasource.cache.CacheDataSource
import androidx.media3.datasource.cache.LeastRecentlyUsedCacheEvictor
import androidx.media3.datasource.cache.SimpleCache
import java.io.File

@OptIn(UnstableApi::class)
internal object FastVideoCacheRuntime {
  private const val DEFAULT_MAX_BYTES = 256L * 1024L * 1024L
  private const val MIN_MAX_BYTES = 16L * 1024L * 1024L
  private const val MAX_MAX_BYTES = 4L * 1024L * 1024L * 1024L

  private var configuredMaxBytes = DEFAULT_MAX_BYTES
  private var cache: SimpleCache? = null
  private var databaseProvider: StandaloneDatabaseProvider? = null

  @Synchronized
  fun configure(maxBytes: Long?): Map<String, Any> {
    val requested = (maxBytes ?: configuredMaxBytes).coerceIn(MIN_MAX_BYTES, MAX_MAX_BYTES)
    val initialized = cache != null
    val changed = requested != configuredMaxBytes
    if (!initialized) configuredMaxBytes = requested
    return mapOf(
      "platform" to "android",
      "cacheMaxBytes" to configuredMaxBytes,
      "applied" to (!initialized || !changed),
      "requiresRuntimeReset" to (initialized && changed)
    )
  }

  @Synchronized
  fun cache(context: Context): SimpleCache {
    cache?.let { return it }
    val appContext = context.applicationContext
    val provider = StandaloneDatabaseProvider(appContext)
    val next = SimpleCache(
      File(appContext.cacheDir, "react-native-fast-video"),
      LeastRecentlyUsedCacheEvictor(configuredMaxBytes),
      provider
    )
    databaseProvider = provider
    cache = next
    return next
  }

  fun upstreamFactory(context: Context, headers: Map<String, String> = emptyMap()): DataSource.Factory {
    val http = DefaultHttpDataSource.Factory()
      .setUserAgent("react-native-fast-video/0.0.5")
      .setAllowCrossProtocolRedirects(true)
      .setDefaultRequestProperties(headers)
    return DefaultDataSource.Factory(context.applicationContext, http)
  }

  fun dataSourceFactory(
    context: Context,
    headers: Map<String, String> = emptyMap(),
    eventListener: CacheDataSource.EventListener? = null
  ): DataSource.Factory {
    return CacheDataSource.Factory()
      .setCache(cache(context))
      .setUpstreamDataSourceFactory(upstreamFactory(context, headers))
      .setEventListener(eventListener)
      .setFlags(CacheDataSource.FLAG_IGNORE_CACHE_ON_ERROR)
  }

  @Synchronized
  fun stats(context: Context): Map<String, Any> {
    val current = cache(context)
    return mapOf(
      "cacheBytes" to current.cacheSpace,
      "cacheMaxBytes" to configuredMaxBytes
    )
  }

  @Synchronized
  fun clear(context: Context): Map<String, Any> {
    val current = cache(context)
    current.keys.toList().forEach { key -> current.removeResource(key) }
    return stats(context)
  }

  @Synchronized
  fun release() {
    cache?.release()
    cache = null
    databaseProvider?.close()
    databaseProvider = null
  }
}
