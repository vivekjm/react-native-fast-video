import ExpoModulesCore

internal struct FastVideoDrm: Record {
  @Field var type: String = ""
  @Field var licenseUrl: String = ""
  @Field var certificateUrl: String? = nil
  @Field var headers: [String: String] = [:]
  @Field var contentId: String? = nil
  @Field var multiSession: Bool = false
  @Field var licenseResponseType: String = "raw"
}

internal struct FastVideoSubtitle: Record {
  @Field var id: String? = nil
  @Field var uri: String = ""
  @Field var mimeType: String = "text/vtt"
  @Field var language: String? = nil
  @Field var label: String? = nil
  @Field var isDefault: Bool = false
}


internal struct FastVideoMetadata: Record {
  @Field var title: String? = nil
  @Field var artist: String? = nil
  @Field var albumTitle: String? = nil
  @Field var artworkUri: String? = nil
}

internal struct FastVideoSource: Record {
  @Field var uri: String = ""
  @Field var type: String = "auto"
  @Field var headers: [String: String] = [:]
  @Field var drm: FastVideoDrm? = nil
  @Field var subtitles: [FastVideoSubtitle] = []
  @Field var isLive: Bool = false
  @Field var startPositionMs: Double? = nil
  @Field var targetLiveOffsetMs: Double? = nil
  @Field var customCacheKey: String? = nil
  @Field var offlineId: String? = nil
  @Field var preloadIndex: Int? = nil
  @Field var fallbackUris: [String] = []
  @Field var maxRetryAttempts: Int = 2
  @Field var retryBackoffMs: Double = 350
  @Field var latencyMode: String = "balanced"
  @Field var metadata: FastVideoMetadata? = nil
  @Field var mediaSession: Bool = false
}
