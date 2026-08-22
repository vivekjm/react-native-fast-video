package com.vivekjm.fastvideo

import android.net.Uri
import org.json.JSONObject

/** Process-local health model for source/fallback origins. Never exports path/query credentials. */
internal object FastVideoCdnRuntime {
  private data class Health(
    var successes: Int = 0,
    var failures: Int = 0,
    var consecutiveFailures: Int = 0,
    var averageTtffMs: Double = 0.0,
    var averageResponseMs: Double = 0.0
  )

  private val health = mutableMapOf<String, Health>()

  @Synchronized
  fun rank(uris: List<String>): List<String> = uris.withIndex()
    .sortedWith(compareByDescending<IndexedValue<String>> { score(it.value) }.thenBy { it.index })
    .map { it.value }

  @Synchronized
  fun recordFirstFrame(uri: String, ttffMs: Double, responseMs: Double = ttffMs) {
    val item = health.getOrPut(origin(uri)) { Health() }
    item.successes += 1
    item.consecutiveFailures = 0
    if (ttffMs.isFinite() && ttffMs >= 0.0) item.averageTtffMs = ema(item.averageTtffMs, ttffMs)
    if (responseMs.isFinite() && responseMs >= 0.0) item.averageResponseMs = ema(item.averageResponseMs, responseMs)
  }

  @Synchronized
  fun recordFailure(uri: String, responseMs: Double = 0.0) {
    val item = health.getOrPut(origin(uri)) { Health() }
    item.failures += 1
    item.consecutiveFailures += 1
    if (responseMs.isFinite() && responseMs >= 0.0) item.averageResponseMs = ema(item.averageResponseMs, responseMs)
  }

  @Synchronized
  fun diagnostics(uri: String): Map<String, Any?> {
    val key = origin(uri)
    val item = health[key] ?: Health()
    return mapOf(
      "origin" to key,
      "score" to scoreFor(item),
      "successes" to item.successes,
      "failures" to item.failures,
      "consecutiveFailures" to item.consecutiveFailures,
      "averageTtffMs" to item.averageTtffMs,
      "averageResponseMs" to item.averageResponseMs
    )
  }

  @Synchronized
  fun stats(): Map<String, Any> = mapOf(
    "cdnOriginsTracked" to health.size,
    "cdnHealth" to health.entries.sortedBy { it.key }.map { (key, value) ->
      mapOf("origin" to key, "score" to scoreFor(value), "failures" to value.failures, "successes" to value.successes)
    }
  )

  @Synchronized
  fun clear() = health.clear()

  private fun score(uri: String): Double = scoreFor(health[origin(uri)] ?: Health())

  private fun scoreFor(item: Health): Double {
    val total = item.successes + item.failures
    val successRate = if (total == 0) 1.0 else item.successes.toDouble() / total
    val errorRate = if (total == 0) 0.0 else item.failures.toDouble() / total
    return runCatching {
      JSONObject(FastCoreNative.cdnHealth(successRate, errorRate, item.averageTtffMs, item.averageResponseMs, item.consecutiveFailures))
        .optDouble("score", 0.0)
    }.getOrDefault(0.0)
  }

  private fun ema(previous: Double, sample: Double): Double = if (previous <= 0.0) sample else 0.25 * sample + 0.75 * previous

  private fun origin(value: String): String = runCatching {
    val uri = Uri.parse(value)
    if (uri.scheme.isNullOrBlank() || uri.host.isNullOrBlank()) "local" else buildString {
      append(uri.scheme!!.lowercase())
      append("://")
      append(uri.host!!.lowercase())
      if (uri.port > 0) append(":${uri.port}")
    }
  }.getOrDefault("unknown")
}
