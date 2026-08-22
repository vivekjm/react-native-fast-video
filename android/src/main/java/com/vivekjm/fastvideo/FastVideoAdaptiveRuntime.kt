package com.vivekjm.fastvideo

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import android.os.PowerManager
import org.json.JSONObject
import java.util.concurrent.atomic.AtomicInteger

internal object FastVideoAdaptiveRuntime {
  private val activePlayers = AtomicInteger(0)
  @Volatile private var adaptiveMode = "balanced"

  fun configure(value: String?) {
    adaptiveMode = when (value) {
      "off", "conservative", "aggressive" -> value
      else -> "balanced"
    }
  }

  fun onPlayerAcquired() {
    activePlayers.incrementAndGet()
  }

  fun onPlayerReleased() {
    activePlayers.updateAndGet { current -> (current - 1).coerceAtLeast(0) }
  }

  fun activePlayerCount(): Int = activePlayers.get().coerceAtLeast(1)

  fun decision(
    context: Context,
    bandwidthEstimateBps: Long,
    rebufferRatio: Double,
    droppedFrameRatio: Double,
    width: Int,
    height: Int
  ): Map<String, Any?> {
    if (adaptiveMode == "off") return emptyMap()
    val json = FastCoreNative.adaptiveDecision(
      bandwidthEstimateBps.coerceAtLeast(0L).toDouble(),
      rebufferRatio.coerceAtLeast(0.0),
      droppedFrameRatio.coerceAtLeast(0.0),
      activePlayerCount(),
      width.coerceAtLeast(0),
      height.coerceAtLeast(0),
      networkClass(context),
      thermalClass(context),
      isLowPowerMode(context)
    )
    val base = runCatching {
      val value = JSONObject(json)
      value.keys().asSequence().associateWith { key -> value.opt(key).takeUnless { it === JSONObject.NULL } }
    }.getOrDefault(emptyMap())
    if (base.isEmpty()) return base
    val multiplier = when (adaptiveMode) {
      "conservative" -> 0.78
      "aggressive" -> 1.12
      else -> 1.0
    }
    val bitrate = (base["maxBitrateBps"] as? Number)?.toLong()?.let { (it * multiplier).toLong() }
    return if (bitrate != null) base + mapOf("maxBitrateBps" to bitrate, "mode" to adaptiveMode) else base
  }

  fun runtimeStats(context: Context): Map<String, Any> = mapOf(
    "adaptivePlaybackEnabled" to (adaptiveMode != "off"),
    "adaptiveMode" to adaptiveMode,
    "activePlayers" to activePlayers.get(),
    "networkClass" to networkClassName(networkClass(context)),
    "thermalClass" to thermalClass(context),
    "lowPowerMode" to isLowPowerMode(context)
  )

  private fun networkClass(context: Context): Int {
    val manager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager ?: return 0
    val capabilities = manager.getNetworkCapabilities(manager.activeNetwork) ?: return 0
    return when {
      capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED) &&
        capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> 4
      capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> 3
      capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> 2
      capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) -> 1
      else -> 0
    }
  }

  private fun networkClassName(value: Int): String = when (value) {
    4 -> "ethernet"
    3 -> "wifi"
    2 -> "cellular"
    1 -> "constrained"
    else -> "offline"
  }

  private fun thermalClass(context: Context): Int {
    if (Build.VERSION.SDK_INT < 29) return 0
    val power = context.getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return 0
    return when (power.currentThermalStatus) {
      PowerManager.THERMAL_STATUS_CRITICAL, PowerManager.THERMAL_STATUS_EMERGENCY, PowerManager.THERMAL_STATUS_SHUTDOWN -> 3
      PowerManager.THERMAL_STATUS_SEVERE -> 2
      PowerManager.THERMAL_STATUS_MODERATE -> 1
      else -> 0
    }
  }

  private fun isLowPowerMode(context: Context): Boolean {
    val power = context.getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return false
    return power.isPowerSaveMode
  }
}
