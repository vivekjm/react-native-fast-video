package com.vivekjm.fastvideo

import android.content.Context
import android.net.Uri
import androidx.annotation.OptIn
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.datasource.ResolvingDataSource
import java.util.concurrent.ConcurrentHashMap
import org.json.JSONObject

/**
 * Media3's DownloadRequest does not carry per-request HTTP headers into every segment DataSpec.
 * This registry persists header scopes by offline id and resolves them for manifest/segment URIs.
 * The longest matching directory scope wins; origin scope is the fallback for absolute segments.
 */
@OptIn(UnstableApi::class)
internal object FastVideoDownloadHeaderRegistry {
  private const val PREFS = "react-native-fast-video.offline-headers.v1"
  private val entries = ConcurrentHashMap<String, Entry>()
  @Volatile private var restored = false

  private data class Entry(
    val id: String,
    val directoryScope: String,
    val originScope: String,
    val headers: Map<String, String>
  )

  fun register(context: Context, id: String, uri: String, headers: Map<String, String>) {
    ensureRestored(context)
    if (headers.isEmpty()) {
      unregister(context, id)
      return
    }
    val parsed = Uri.parse(uri)
    val entry = Entry(
      id = id,
      directoryScope = directoryScope(parsed),
      originScope = originScope(parsed),
      headers = headers.toMap()
    )
    entries[id] = entry
    persist(context, entry)
  }

  fun unregister(context: Context, id: String) {
    ensureRestored(context)
    entries.remove(id)
    context.applicationContext
      .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
      .edit()
      .remove(id)
      .apply()
  }

  fun factory(context: Context): DataSource.Factory {
    ensureRestored(context)
    val upstream = DefaultHttpDataSource.Factory()
      .setUserAgent("react-native-fast-video")
      .setAllowCrossProtocolRedirects(true)
    return ResolvingDataSource.Factory(
      upstream,
      object : ResolvingDataSource.Resolver {
        override fun resolveDataSpec(dataSpec: DataSpec): DataSpec {
          val resolved = headersFor(dataSpec.uri)
          if (resolved.isEmpty()) return dataSpec
          return dataSpec.buildUpon()
            .setHttpRequestHeaders(dataSpec.httpRequestHeaders + resolved)
            .build()
        }
      }
    )
  }

  fun stats(context: Context): Map<String, Any> {
    ensureRestored(context)
    return mapOf("offlineHeaderProfiles" to entries.size)
  }

  private fun headersFor(uri: Uri): Map<String, String> {
    val value = uri.toString()
    val origin = originScope(uri)
    return entries.values
      .asSequence()
      .filter { entry ->
        value.startsWith(entry.directoryScope) ||
          (entry.originScope.isNotEmpty() && entry.originScope == origin)
      }
      .maxByOrNull { entry ->
        if (value.startsWith(entry.directoryScope)) entry.directoryScope.length else 0
      }
      ?.headers
      .orEmpty()
  }

  @Synchronized
  private fun ensureRestored(context: Context) {
    if (restored) return
    val prefs = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    prefs.all.forEach { (id, raw) ->
      val json = (raw as? String)?.let(::JSONObject) ?: return@forEach
      val headersJson = json.optJSONObject("headers") ?: JSONObject()
      val headers = headersJson.keys().asSequence().associateWith { key ->
        headersJson.optString(key)
      }
      if (headers.isNotEmpty()) {
        entries[id] = Entry(
          id = id,
          directoryScope = json.optString("directoryScope"),
          originScope = json.optString("originScope"),
          headers = headers
        )
      }
    }
    restored = true
  }

  private fun persist(context: Context, entry: Entry) {
    val headers = JSONObject()
    entry.headers.forEach(headers::put)
    val json = JSONObject()
      .put("directoryScope", entry.directoryScope)
      .put("originScope", entry.originScope)
      .put("headers", headers)
    context.applicationContext
      .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
      .edit()
      .putString(entry.id, json.toString())
      .apply()
  }

  private fun directoryScope(uri: Uri): String {
    val raw = uri.buildUpon().clearQuery().fragment(null).build().toString()
    val slash = raw.lastIndexOf('/')
    return if (slash >= 0) raw.substring(0, slash + 1) else raw
  }

  private fun originScope(uri: Uri): String {
    val scheme = uri.scheme ?: return ""
    val authority = uri.encodedAuthority ?: return ""
    return "$scheme://$authority/"
  }
}
