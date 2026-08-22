package com.vivekjm.fastvideo

import expo.modules.kotlin.records.Field
import expo.modules.kotlin.records.Record

class FastVideoDrm : Record {
  @Field var type: String = ""
  @Field var licenseUrl: String = ""
  @Field var certificateUrl: String? = null
  @Field var headers: Map<String, String> = emptyMap()
  @Field var contentId: String? = null
  @Field var multiSession: Boolean = false
  @Field var licenseResponseType: String = "raw"
}

class FastVideoSubtitle : Record {
  @Field var id: String? = null
  @Field var uri: String = ""
  @Field var mimeType: String = "text/vtt"
  @Field var language: String? = null
  @Field var label: String? = null
  @Field var isDefault: Boolean = false
}


class FastVideoMetadata : Record {
  @Field var title: String? = null
  @Field var artist: String? = null
  @Field var albumTitle: String? = null
  @Field var artworkUri: String? = null
}

class FastVideoSource : Record {
  @Field var uri: String = ""
  @Field var type: String = "auto"
  @Field var headers: Map<String, String> = emptyMap()
  @Field var drm: FastVideoDrm? = null
  @Field var subtitles: List<FastVideoSubtitle> = emptyList()
  @Field var isLive: Boolean = false
  @Field var startPositionMs: Double? = null
  @Field var targetLiveOffsetMs: Double? = null
  @Field var customCacheKey: String? = null
  @Field var offlineId: String? = null
  @Field var preloadIndex: Int? = null
  @Field var fallbackUris: List<String> = emptyList()
  @Field var maxRetryAttempts: Int = 2
  @Field var retryBackoffMs: Long = 350
  @Field var latencyMode: String = "balanced"
  @Field var metadata: FastVideoMetadata? = null
  @Field var mediaSession: Boolean = false
}
