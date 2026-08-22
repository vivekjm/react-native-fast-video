package com.vivekjm.fastvideo

import android.content.Context
import android.content.pm.PackageManager
import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.media.MediaDrm
import android.os.Build
import android.view.Display
import android.view.WindowManager
import androidx.media3.common.C

internal object FastVideoCapabilities {
  fun read(context: Context): Map<String, Any?> {
    val codecInfos = runCatching {
      MediaCodecList(MediaCodecList.ALL_CODECS).codecInfos.filterNot { it.isEncoder }
    }.getOrDefault(emptyList())

    val mimeTypes = codecInfos.flatMap { it.supportedTypes.asIterable() }.distinct().sorted()
    var decoder4k60: String? = null
    val main10Decoders = mutableListOf<String>()

    codecInfos.forEach { codec ->
      codec.supportedTypes.forEach { mime ->
        runCatching {
          val capabilities = codec.getCapabilitiesForType(mime)
          val video = capabilities.videoCapabilities
          if (decoder4k60 == null && video != null && video.areSizeAndRateSupported(3840, 2160, 60.0)) {
            decoder4k60 = codec.name
          }
          val supportsMain10 = capabilities.profileLevels.any { profile ->
            profile.profile == MediaCodecInfo.CodecProfileLevel.HEVCProfileMain10 ||
              (Build.VERSION.SDK_INT >= 29 &&
                profile.profile == MediaCodecInfo.CodecProfileLevel.AV1ProfileMain10)
          }
          if (supportsMain10 && codec.name !in main10Decoders) main10Decoders += codec.name
        }
      }
    }

    val hdrTypes = if (Build.VERSION.SDK_INT >= 24) {
      val display = if (Build.VERSION.SDK_INT >= 30) {
        context.display
      } else {
        @Suppress("DEPRECATION")
        (context.getSystemService(Context.WINDOW_SERVICE) as? WindowManager)?.defaultDisplay
      }
      display?.hdrCapabilities?.supportedHdrTypes?.map { hdrName(it) }.orEmpty()
    } else {
      emptyList()
    }

    val widevine = readWidevine()

    return mapOf(
      "platform" to "android",
      "apiLevel" to Build.VERSION.SDK_INT,
      "hardwareDecoderMimeTypes" to mimeTypes,
      "decoder4k60" to decoder4k60,
      "supports4k60" to (decoder4k60 != null),
      "main10Decoders" to main10Decoders,
      "hdrDisplayTypes" to hdrTypes,
      "supportsHdrDisplay" to hdrTypes.isNotEmpty(),
      "widevine" to widevine,
      "supportsPictureInPicture" to (
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
          context.packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
        ),
      "defaultSurface" to "surface",
      "adaptiveStreaming" to listOf("hls", "dash", "smoothstreaming")
    )
  }

  private fun readWidevine(): Map<String, Any?> {
    var mediaDrm: MediaDrm? = null
    return try {
      mediaDrm = MediaDrm(C.WIDEVINE_UUID)
      mapOf(
        "supported" to true,
        "securityLevel" to mediaDrm.getPropertyString("securityLevel"),
        "vendor" to mediaDrm.getPropertyString("vendor"),
        "version" to mediaDrm.getPropertyString("version")
      )
    } catch (error: Throwable) {
      mapOf("supported" to false, "error" to (error.message ?: "Unavailable"))
    } finally {
      runCatching { mediaDrm?.release() }
    }
  }

  private fun hdrName(value: Int): String {
    if (Build.VERSION.SDK_INT < 24) return "unknown:$value"
    return when {
      value == Display.HdrCapabilities.HDR_TYPE_DOLBY_VISION -> "dolbyVision"
      value == Display.HdrCapabilities.HDR_TYPE_HDR10 -> "hdr10"
      value == Display.HdrCapabilities.HDR_TYPE_HLG -> "hlg"
      Build.VERSION.SDK_INT >= 29 && value == Display.HdrCapabilities.HDR_TYPE_HDR10_PLUS -> "hdr10Plus"
      else -> "unknown:$value"
    }
  }
}
