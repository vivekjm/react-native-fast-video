from __future__ import annotations

from pathlib import Path
import json
import re
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text()


def write(path: str, value: str) -> None:
    target = ROOT / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(value)


def replace_required(value: str, old: str, new: str, label: str) -> str:
    if old in value:
        return value.replace(old, new)
    if new in value:
        return value
    raise RuntimeError(f"Could not apply {label}")


# TypeScript / Expo native-view contract.
s = read("src/FastVideo.tsx")
s = s.replace("import { requireNativeView } from 'expo-modules-core';", "import { requireNativeViewManager } from 'expo-modules-core';")
s = s.replace(
    "const NativeFastVideo = requireNativeView<NativeFastVideoProps>(\n  'ReactNativeFastVideo',\n  'FastVideoView'\n);",
    "const NativeFastVideo = requireNativeViewManager<NativeFastVideoProps>(\n  'ReactNativeFastVideo'\n);",
)
write("src/FastVideo.tsx", s)

# Source normalization: preserve the real metadata type and reject ambiguous/unsafe inputs.
s = read("src/normalizeSource.ts")
m = re.search(r"import type \\{([\\s\\S]*?)\\} from './FastVideo\\.types';", s)
if m:
    items = [item.strip() for item in m.group(1).split(',') if item.strip()]
    if "FastVideoMetadata" not in items:
        items.append("FastVideoMetadata")
    block = "import type {\n  " + ",\n  ".join(dict.fromkeys(items)) + "\n} from './FastVideo.types';"
    s = s[:m.start()] + block + s[m.end():]
s = s.replace("metadata?: Record<string, string | undefined>;", "metadata?: FastVideoMetadata;")
s = s.replace("metadata?: Record<string, string | null | undefined>;", "metadata?: FastVideoMetadata;")
for old, new in {
    "uri: source.uri,": "uri: requiredUri(source.uri),",
    "uri: resolved.uri,": "uri: requiredUri(resolved.uri),",
    "uri: source,": "uri: requiredUri(source),",
    "headers: source.headers ?? {},": "headers: normalizeHeaders(source.headers),",
    "headers: source.headers || {},": "headers: normalizeHeaders(source.headers),",
    "fallbackUris: source.fallbackUris ?? [],": "fallbackUris: normalizeFallbackUris(source.uri, source.fallbackUris),",
    "fallbackUris: source.fallbackUris || [],": "fallbackUris: normalizeFallbackUris(source.uri, source.fallbackUris),",
    "maxRetryAttempts: source.maxRetryAttempts ?? 2,": "maxRetryAttempts: boundedInteger(source.maxRetryAttempts, 2, 0, 8),",
    "retryBackoffMs: source.retryBackoffMs ?? 350,": "retryBackoffMs: boundedNumber(source.retryBackoffMs, 350, 50, 10_000),",
    "latencyMode: source.latencyMode ?? 'balanced',": "latencyMode: normalizeLatencyMode(source.latencyMode),",
}.items():
    s = s.replace(old, new)
if "function requiredUri(" not in s:
    s += """

function requiredUri(value: string): string {
  const uri = value.trim();
  if (!uri) throw new TypeError('FastVideo source URI must not be blank.');
  return uri;
}

function normalizeHeaders(value: Record<string, string> | undefined): Record<string, string> {
  if (!value) return {};
  const result: Record<string, string> = {};
  for (const [rawName, rawValue] of Object.entries(value)) {
    const name = rawName.trim();
    const headerValue = rawValue.trim();
    if (!name || /[\\r\\n]/.test(name) || /[\\r\\n]/.test(headerValue)) {
      throw new TypeError('FastVideo headers must not contain blank names or line breaks.');
    }
    result[name] = headerValue;
  }
  return result;
}

function normalizeFallbackUris(primary: string, values: readonly string[] | undefined): string[] {
  const normalizedPrimary = requiredUri(primary);
  const seen = new Set([normalizedPrimary]);
  const result: string[] = [];
  for (const value of values ?? []) {
    const uri = requiredUri(value);
    if (!seen.has(uri)) {
      seen.add(uri);
      result.push(uri);
    }
  }
  return result;
}

function boundedInteger(value: number | undefined, fallback: number, min: number, max: number): number {
  return Math.trunc(boundedNumber(value, fallback, min, max));
}

function boundedNumber(value: number | undefined, fallback: number, min: number, max: number): number {
  const resolved = value === undefined ? fallback : value;
  if (!Number.isFinite(resolved)) throw new TypeError('FastVideo numeric source options must be finite.');
  return Math.min(max, Math.max(min, resolved));
}

function normalizeLatencyMode(value: string | undefined): 'lowLatency' | 'balanced' | 'quality' | 'memorySaver' {
  return value === 'lowLatency' || value === 'quality' || value === 'memorySaver' ? value : 'balanced';
}
"""
write("src/normalizeSource.ts", s)

# Web parity: typed DOM PiP events, measured first frame, complete metrics defaults.
s = read("src/FastVideo.web.tsx")
if "useEffect" not in s.split("from 'react';", 1)[0]:
    s = s.replace("  useImperativeHandle,", "  useEffect,\n  useImperativeHandle,")
if "loadStartedAtRef" not in s:
    s = re.sub(r"(const\\s+videoRef\\s*=\\s*useRef<[^;]+;)", r"\\1\n  const loadStartedAtRef = useRef(performance.now());", s, count=1)
if "loadStartedAtRef.current = performance.now()" not in s:
    marker = "  useImperativeHandle("
    effect = """  useEffect(() => {
    loadStartedAtRef.current = performance.now();
  }, [normalized.sourceObject.uri]);

"""
    if marker in s:
        s = s.replace(marker, effect + marker, 1)
s = re.sub(
    r"props\\.onFirstFrame\\?\\.\\(\\{\\s*timestampMs:\\s*(?:Date\\.now\\(\\)|performance\\.now\\(\\))\\s*\\}\\);",
    "props.onFirstFrame?.({\n        timestampMs: Date.now(),\n        timeToFirstFrameMs: Math.max(0, performance.now() - loadStartedAtRef.current),\n        startupPath: 'web',\n      });",
    s,
    count=1,
    flags=re.S,
)
s = re.sub(r"\\n\\s*onEnterPictureInPicture=\\{[\\s\\S]*?\\}(?=\\n\\s*[A-Za-z/>])", "", s)
s = re.sub(r"\\n\\s*onLeavePictureInPicture=\\{[\\s\\S]*?\\}(?=\\n\\s*[A-Za-z/>])", "", s)
if "enterpictureinpicture" not in s:
    marker = re.search(r"(const\\s+videoRef\\s*=\\s*useRef<[^;]+;)", s)
    if not marker:
        raise RuntimeError("Web video ref not found")
    effect = """

  useEffect(() => {
    const element = videoRef.current;
    if (!element) return;
    const onEnter = () => props.onPictureInPictureChange?.({ active: true });
    const onLeave = () => props.onPictureInPictureChange?.({ active: false });
    element.addEventListener('enterpictureinpicture', onEnter as EventListener);
    element.addEventListener('leavepictureinpicture', onLeave as EventListener);
    return () => {
      element.removeEventListener('enterpictureinpicture', onEnter as EventListener);
      element.removeEventListener('leavepictureinpicture', onLeave as EventListener);
    };
  }, [props.onPictureInPictureChange]);
"""
    s = s[:marker.end()] + effect + s[marker.end():]

types = read("src/FastVideo.types.ts")
metrics = re.search(r"export interface FastVideoMetrics\\s*\\{([\\s\\S]*?)\\n\\}", types)
if not metrics:
    raise RuntimeError("FastVideoMetrics interface not found")
required = []
for name, optional, typ in re.findall(r"^\\s*([A-Za-z_$][\\w$]*)(\\?)?:\\s*([^;]+);", metrics.group(1), re.M):
    if not optional:
        required.append((name, typ.strip()))

def default_value(name: str, typ: str) -> str:
    lower = name.lower()
    if name == "state" or "PlaybackState" in typ:
        return "'idle'"
    if name == "startupPath" or "StartupPath" in typ:
        return "'cold'"
    if "boolean" in typ or lower.startswith("is") or lower.endswith("rendered") or lower == "playwhenready":
        return "false"
    if "number" in typ:
        return "0"
    if "string" in typ:
        return "''"
    if "[]" in typ or "Array<" in typ:
        return "[]"
    if "Record<" in typ:
        return "{}"
    literal = re.search(r"'([^']+)'", typ)
    return repr(literal.group(1)) if literal else "null as never"

body = "\n".join(f"    {name}: {default_value(name, typ)}," for name, typ in required)
pattern = re.compile(r"function\\s+(\\w+)\\s*\\(([^)]*)\\)\\s*:\\s*FastVideoMetrics\\s*\\{[\\s\\S]*?\\n\\}", re.M)
s = pattern.sub(lambda match: f"function {match.group(1)}({match.group(2)}): FastVideoMetrics {{\n  return {{\n{body}\n  }};\n}}", s)
write("src/FastVideo.web.tsx", s)

# Direction-aware asymmetric preload windows on Android.
s = read("android/src/main/java/com/vivekjm/fastvideo/FastVideoPreloadRuntime.kt")
old = """  private class StatusControl : TargetPreloadStatusControl<Int, DefaultPreloadManager.PreloadStatus> {
    @Volatile var currentIndex: Int = 0

    override fun getTargetPreloadStatus(index: Int): DefaultPreloadManager.PreloadStatus {
      val distance = index - currentIndex
      return when (FastCoreNative.preloadStage(distance)) {"""
new = """  private class StatusControl : TargetPreloadStatusControl<Int, DefaultPreloadManager.PreloadStatus> {
    @Volatile var currentIndex: Int = 0
    @Volatile private var direction: Int = 0
    @Volatile private var forwardRadius: Int = 4
    @Volatile private var backwardRadius: Int = 4

    fun updateIntent(index: Int, nextDirection: Int, nextForwardRadius: Int, nextBackwardRadius: Int) {
      currentIndex = index
      direction = nextDirection.coerceIn(-1, 1)
      forwardRadius = nextForwardRadius.coerceIn(1, 8)
      backwardRadius = nextBackwardRadius.coerceIn(0, 8)
    }

    override fun getTargetPreloadStatus(index: Int): DefaultPreloadManager.PreloadStatus {
      val distance = index - currentIndex
      val inWindow = when {
        distance == 0 || direction == 0 -> kotlin.math.abs(distance) <= maxOf(forwardRadius, backwardRadius)
        direction > 0 && distance > 0 -> distance <= forwardRadius
        direction > 0 -> -distance <= backwardRadius
        direction < 0 && distance < 0 -> -distance <= forwardRadius
        else -> distance <= backwardRadius
      }
      if (!inWindow) return DefaultPreloadManager.PreloadStatus.PRELOAD_STATUS_NOT_PRELOADED
      return when (FastCoreNative.preloadStage(distance)) {"""
s = replace_required(s, old, new, "Android preload status control")
s = s.replace("runtime.control.currentIndex = currentIndex", "runtime.control.updateIntent(currentIndex, 0, 4, 4)")
old = """    val predicted = (intent["predictedIndex"] as? Number)?.toInt()?.coerceIn(0, maxOf(0, itemCount - 1)) ?: index
    previousFocusIndex = index
    runtimes.values.forEach { runtime ->
      runtime.control.currentIndex = predicted
      runtime.manager.setCurrentPlayingIndex(index)
      runtime.manager.invalidate()
    }
    return intent + mapOf("actualIndex" to index)"""
new = """    val predicted = (intent["predictedIndex"] as? Number)?.toInt()?.coerceIn(0, maxOf(0, itemCount - 1)) ?: index
    val resolvedDirection = (intent["direction"] as? Number)?.toInt()?.coerceIn(-1, 1)
      ?: (predicted - index).compareTo(0)
    fun radius(defaultValue: Int, vararg keys: String): Int = keys
      .firstNotNullOfOrNull { key -> (intent[key] as? Number)?.toInt() }
      ?.coerceIn(0, 8)
      ?: defaultValue
    val speed = kotlin.math.abs(velocityItemsPerSecond)
    val defaultForward = when { speed >= 5.0 -> 7; speed >= 2.0 -> 5; else -> 4 }
    val defaultBackward = when { speed >= 5.0 -> 1; speed >= 2.0 -> 2; else -> 4 }
    val forwardRadius = radius(defaultForward, "forwardRadius", "aheadRadius", "forwardPreloadRadius", "aheadWindow", "forwardWindow")
    val backwardRadius = radius(defaultBackward, "backwardRadius", "behindRadius", "backwardPreloadRadius", "behindWindow", "backwardWindow")
    previousFocusIndex = index
    runtimes.values.forEach { runtime ->
      runtime.control.updateIntent(predicted, resolvedDirection, forwardRadius, backwardRadius)
      runtime.manager.setCurrentPlayingIndex(index)
      runtime.manager.invalidate()
    }
    return intent + mapOf(
      "actualIndex" to index,
      "resolvedDirection" to resolvedDirection,
      "resolvedForwardRadius" to forwardRadius,
      "resolvedBackwardRadius" to backwardRadius
    )"""
s = replace_required(s, old, new, "Android viewport intent")
write("android/src/main/java/com/vivekjm/fastvideo/FastVideoPreloadRuntime.kt", s)

# Direction-aware asymmetric preload retention on Apple.
s = read("ios/FastVideoPreloader.swift")
old = """    let predicted = min(max(0, (intent["predictedIndex"] as? NSNumber)?.intValue ?? currentIndex), max(0, itemCount - 1))
    previousFocusIndex = currentIndex
    let evicted = order.filter { key in
      guard let index = indexByKey[key] else { return true }
      return abs(index - predicted) > retentionDistance
    }"""
new = """    let predicted = min(max(0, (intent["predictedIndex"] as? NSNumber)?.intValue ?? currentIndex), max(0, itemCount - 1))
    let fallbackDirection = predicted == currentIndex ? 0 : (predicted > currentIndex ? 1 : -1)
    let resolvedDirection = min(1, max(-1, (intent["direction"] as? NSNumber)?.intValue ?? fallbackDirection))
    func radius(_ fallback: Int, _ keys: [String]) -> Int {
      for key in keys {
        if let value = (intent[key] as? NSNumber)?.intValue { return min(8, max(0, value)) }
      }
      return fallback
    }
    let speed = abs(velocityItemsPerSecond)
    let defaultForward = speed >= 5 ? 7 : (speed >= 2 ? 5 : retentionDistance)
    let defaultBackward = speed >= 5 ? 1 : (speed >= 2 ? 2 : retentionDistance)
    let forwardRadius = radius(defaultForward, ["forwardRadius", "aheadRadius", "forwardPreloadRadius", "aheadWindow", "forwardWindow"])
    let backwardRadius = radius(defaultBackward, ["backwardRadius", "behindRadius", "backwardPreloadRadius", "behindWindow", "backwardWindow"])
    previousFocusIndex = currentIndex
    let evicted = order.filter { key in
      guard let index = indexByKey[key] else { return true }
      let distance = index - predicted
      if distance == 0 || resolvedDirection == 0 { return abs(distance) > max(forwardRadius, backwardRadius) }
      if resolvedDirection > 0 { return distance > forwardRadius || -distance > backwardRadius }
      return -distance > forwardRadius || distance > backwardRadius
    }"""
s = replace_required(s, old, new, "Apple viewport intent")
s = s.replace(
    "    result[\"actualIndex\"] = currentIndex\n    return result",
    "    result[\"actualIndex\"] = currentIndex\n    result[\"resolvedDirection\"] = resolvedDirection\n    result[\"resolvedForwardRadius\"] = forwardRadius\n    result[\"resolvedBackwardRadius\"] = backwardRadius\n    return result",
    1,
)
write("ios/FastVideoPreloader.swift", s)

# Idempotent adaptive-player leases.
s = read("android/src/main/java/com/vivekjm/fastvideo/FastVideoAdaptiveRuntime.kt")
s = s.replace("activePlayers.decrementAndGet()", "activePlayers.updateAndGet { current -> (current - 1).coerceAtLeast(0) }")
s = s.replace("activePlayerCount.decrementAndGet()", "activePlayerCount.updateAndGet { current -> (current - 1).coerceAtLeast(0) }")
write("android/src/main/java/com/vivekjm/fastvideo/FastVideoAdaptiveRuntime.kt", s)

s = read("android/src/main/java/com/vivekjm/fastvideo/FastVideoEngine.kt")
if "adaptiveLeaseHeld" not in s:
    s = s.replace("  private var candidateLoadStartedAtMs = 0L\n", "  private var candidateLoadStartedAtMs = 0L\n  private var adaptiveLeaseHeld = true\n")
s = s.replace("    FastVideoAdaptiveRuntime.onPlayerReleased()\n    FastCoreNative.destroy(coreHandle)", "    releaseAdaptiveLease()\n    FastCoreNative.destroy(coreHandle)")
if "private fun releaseAdaptiveLease()" not in s:
    s = s.replace("  override fun onPlaybackStateChanged(playbackState: Int) {", "  private fun releaseAdaptiveLease() {\n    if (!adaptiveLeaseHeld) return\n    adaptiveLeaseHeld = false\n    FastVideoAdaptiveRuntime.onPlayerReleased()\n  }\n\n  override fun onPlaybackStateChanged(playbackState: Int) {")
write("android/src/main/java/com/vivekjm/fastvideo/FastVideoEngine.kt", s)

s = read("android/src/main/java/com/vivekjm/fastvideo/FastVideoMediaSessionRuntime.kt")
if "backgroundLeaseHeld" not in s:
    s = s.replace("  @Volatile private var backgroundPlayer: Player? = null\n", "  @Volatile private var backgroundPlayer: Player? = null\n  @Volatile private var backgroundLeaseHeld = false\n")
s = s.replace("      FastVideoAdaptiveRuntime.onPlayerReleased()\n    }", "      releaseBackgroundLease()\n    }", 1)
s = s.replace("      if (backgroundPlayer !== player) FastVideoAdaptiveRuntime.onPlayerAcquired()\n      backgroundPlayer = player", "      if (backgroundPlayer !== player) acquireBackgroundLease()\n      backgroundPlayer = player")
s = s.replace("    if (backgroundPlayer != null) FastVideoAdaptiveRuntime.onPlayerReleased()\n    backgroundPlayer = null", "    releaseBackgroundLease()\n    backgroundPlayer = null")
if "private fun acquireBackgroundLease()" not in s:
    s = s.replace("  @Synchronized\n  fun release() = stopBackgroundPlayback()", "  private fun acquireBackgroundLease() {\n    if (backgroundLeaseHeld) return\n    backgroundLeaseHeld = true\n    FastVideoAdaptiveRuntime.onPlayerAcquired()\n  }\n\n  private fun releaseBackgroundLease() {\n    if (!backgroundLeaseHeld) return\n    backgroundLeaseHeld = false\n    FastVideoAdaptiveRuntime.onPlayerReleased()\n  }\n\n  @Synchronized\n  fun release() = stopBackgroundPlayback()")
# Metadata is already in the MediaItem; replacing the active item here can reset buffering/position.
s = re.sub(r"\n\s*val metadata = source\\.metadata[\\s\\S]*?player\\.replaceMediaItem\\(player\\.currentMediaItemIndex, current\\.buildUpon\\(\\)\\.setMediaMetadata\\(mediaMetadata\\)\\.build\\(\\)\\)\n\s*\\}\n", "\n", s, count=1)
s = s.replace("import androidx.media3.common.MediaMetadata\n", "")
write("android/src/main/java/com/vivekjm/fastvideo/FastVideoMediaSessionRuntime.kt", s)

s = read("ios/FastVideoAdaptiveRuntime.swift").replace("activePlayers -= 1", "activePlayers = max(0, activePlayers - 1)")
write("ios/FastVideoAdaptiveRuntime.swift", s)

s = read("ios/FastVideoEngine.swift")
if "adaptiveLeaseHeld" not in s:
    s = s.replace("  private var adaptiveDecision: [String: Any] = [:]\n", "  private var adaptiveDecision: [String: Any] = [:]\n  private var adaptiveLeaseHeld = true\n")
s = s.replace("    FastVideoAdaptiveRuntime.shared.releasedPlayer()\n  }\n\n  private func observePlayer()", "    releaseAdaptiveLease()\n  }\n\n  private func releaseAdaptiveLease() {\n    guard adaptiveLeaseHeld else { return }\n    adaptiveLeaseHeld = false\n    FastVideoAdaptiveRuntime.shared.releasedPlayer()\n  }\n\n  private func observePlayer()")
write("ios/FastVideoEngine.swift", s)

s = read("ios/FastVideoNowPlayingRuntime.swift")
if "backgroundLeaseHeld" not in s:
    s = s.replace("  private var backgroundPlayer: AVPlayer?\n", "  private var backgroundPlayer: AVPlayer?\n  private var backgroundLeaseHeld = false\n")
s = s.replace("      FastVideoAdaptiveRuntime.shared.releasedPlayer()\n    }", "      releaseBackgroundLease()\n    }", 1)
s = s.replace("      if backgroundPlayer !== engine.player { FastVideoAdaptiveRuntime.shared.acquiredPlayer() }\n      backgroundPlayer = engine.player", "      if backgroundPlayer !== engine.player { acquireBackgroundLease() }\n      backgroundPlayer = engine.player")
s = s.replace("    if backgroundPlayer != nil { FastVideoAdaptiveRuntime.shared.releasedPlayer() }\n    backgroundPlayer = nil", "    releaseBackgroundLease()\n    backgroundPlayer = nil")
if "private func acquireBackgroundLease()" not in s:
    s = s.replace("  private func updateMetadata(source: FastVideoSource) {", "  private func acquireBackgroundLease() {\n    guard !backgroundLeaseHeld else { return }\n    backgroundLeaseHeld = true\n    FastVideoAdaptiveRuntime.shared.acquiredPlayer()\n  }\n\n  private func releaseBackgroundLease() {\n    guard backgroundLeaseHeld else { return }\n    backgroundLeaseHeld = false\n    FastVideoAdaptiveRuntime.shared.releasedPlayer()\n  }\n\n  private func updateMetadata(source: FastVideoSource) {")
write("ios/FastVideoNowPlayingRuntime.swift", s)

# Offline behavior is explicit and relaunch-safe.
s = read("android/src/main/java/com/vivekjm/fastvideo/FastVideoDownloadRuntime.kt")
if "Offline downloads with per-request headers" not in s:
    match = re.search(r"(fun\\s+enqueue\\s*\\([^)]*source:\\s*FastVideoSource[^)]*\\)\\s*(?::\\s*Map<String,\\s*Any\\??>)?\\s*\\{)", s)
    if not match:
        raise RuntimeError("Android offline enqueue function not found")
    guards = """
    require(source.uri.isNotBlank()) { "Offline download URI must not be blank" }
    require(!source.isLive) { "Offline downloads require VOD content" }
    require(source.drm == null) { "Offline DRM license persistence is reserved for Phase 6" }
    require(source.headers.isEmpty()) {
      "Offline downloads with per-request headers are not supported safely; use a short-lived signed URL"
    }
"""
    s = s[:match.end()] + guards + s[match.end():]
write("android/src/main/java/com/vivekjm/fastvideo/FastVideoDownloadRuntime.kt", s)

s = read("ios/FastVideoOfflineRuntime.swift")
if "reconcileBackgroundTasks()" not in s:
    s = s.replace("  private override init() {\n    super.init()\n    restore()\n  }", "  private override init() {\n    super.init()\n    restore()\n    reconcileBackgroundTasks()\n  }")
    s = s.replace("    _ = session\n  }", "    reconcileBackgroundTasks()\n  }", 1)
    marker = "  func enqueue(source: FastVideoSource, id requestedId: String?, title: String?) throws -> [String: Any] {"
    helper = """  private func reconcileBackgroundTasks() {
    session.getAllTasks { [weak self] tasks in
      guard let self else { return }
      let knownTaskIds = Set(tasks.compactMap(\\.taskDescription))
      for task in tasks {
        guard let id = task.taskDescription else { continue }
        self.attachProgressObservation(task: task, id: id)
        self.mutate {
          guard var entry = self.entries[id] else { return }
          entry.progress = task.progress.fractionCompleted
          switch task.state {
          case .running: entry.state = "downloading"
          case .suspended: entry.state = "stopped"
          case .canceling: entry.state = "removing"
          case .completed: if entry.localUri != nil { entry.state = "completed" }
          @unknown default: break
          }
          self.entries[id] = entry
        }
      }
      self.mutate {
        for id in Array(self.entries.keys) {
          guard var entry = self.entries[id], entry.state == "downloading" || entry.state == "queued" else { continue }
          if !knownTaskIds.contains(id) {
            entry.state = entry.localUri == nil ? "failed" : "completed"
            if entry.state == "failed" { entry.error = "Native download task was not restored" }
            self.entries[id] = entry
          }
        }
      }
    }
  }

  private func attachProgressObservation(task: URLSessionTask, id: String) {
    lock.lock()
    if observations[task.taskIdentifier] != nil {
      lock.unlock()
      return
    }
    let observation = task.progress.observe(\\.fractionCompleted, options: [.new]) { [weak self, weak task] progress, _ in
      guard let self, let task else { return }
      self.mutate {
        guard var entry = self.entries[id] else { return }
        entry.progress = progress.fractionCompleted
        if task.state == .running { entry.state = "downloading" }
        self.entries[id] = entry
      }
    }
    observations[task.taskIdentifier] = observation
    lock.unlock()
  }

"""
    if marker not in s:
        raise RuntimeError("Apple offline enqueue function not found")
    s = s.replace(marker, helper + marker)
    s = re.sub(r"\n\s*let observation = task\\.progress\\.observe\\(\\\\\\.fractionCompleted,[\\s\\S]*?lock\\.lock\\(\\); observations\\[task\\.taskIdentifier\\] = observation; lock\\.unlock\\(\\)", "\n    attachProgressObservation(task: task, id: id)", s, count=1)
write("ios/FastVideoOfflineRuntime.swift", s)

# Android manifest permissions/services required by the already-claimed background subsystems.
manifest_path = ROOT / "android/src/main/AndroidManifest.xml"
ET.register_namespace("android", "http://schemas.android.com/apk/res/android")
tree = ET.parse(manifest_path)
manifest = tree.getroot()
ns = "{http://schemas.android.com/apk/res/android}"
required = [
    "android.permission.INTERNET",
    "android.permission.WAKE_LOCK",
    "android.permission.FOREGROUND_SERVICE",
    "android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK",
    "android.permission.FOREGROUND_SERVICE_DATA_SYNC",
    "android.permission.POST_NOTIFICATIONS",
]
existing = {element.get(ns + "name") for element in manifest.findall("uses-permission")}
for name in reversed(required):
    if name not in existing:
        element = ET.Element("uses-permission")
        element.set(ns + "name", name)
        manifest.insert(0, element)
application = manifest.find("application")
if application is None:
    application = ET.SubElement(manifest, "application")
services = {element.get(ns + "name"): element for element in application.findall("service")}
for names, foreground in [
    ((".FastVideoPlaybackService", "com.vivekjm.fastvideo.FastVideoPlaybackService"), "mediaPlayback"),
    ((".FastVideoDownloadService", "com.vivekjm.fastvideo.FastVideoDownloadService"), "dataSync"),
]:
    service = next((services[name] for name in names if name in services), None)
    if service is None:
        service = ET.SubElement(application, "service")
        service.set(ns + "name", names[1])
    service.set(ns + "exported", "false")
    service.set(ns + "foregroundServiceType", foreground)
ET.indent(tree, space="  ")
tree.write(manifest_path, encoding="utf-8", xml_declaration=True)

# Package/release contract.
package_path = ROOT / "package.json"
package = json.loads(package_path.read_text())
package["version"] = "0.0.7-alpha.0"
package["exports"] = {
    ".": {"types": "./build/index.d.ts", "react-native": "./src/index.ts", "default": "./build/index.js"},
    "./app.plugin.js": "./app.plugin.js",
    "./package.json": "./package.json",
}
scripts = package.setdefault("scripts", {})
scripts["test:contracts"] = "node tests/contracts.mjs"
scripts["pack:check"] = "node tests/package-contents.mjs"
scripts["validate:hardening"] = "npm run audit && npm run typecheck && npm run build && npm run test:contracts && npm run test:core && npm run benchmark:sample && npm run benchmark:qoe && npm run benchmark:predictive && npm run benchmark:device-sample && npm run pack:check"
package_path.write_text(json.dumps(package, indent=2) + "\n")

write("tests/contracts.mjs", r'''import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
const read = (path) => readFile(new URL(`../${path}`, import.meta.url), 'utf8');
const [pkgText, nativeView, web, normalize, androidPreload, applePreload, androidSession, appleSession] = await Promise.all([
  read('package.json'), read('src/FastVideo.tsx'), read('src/FastVideo.web.tsx'), read('src/normalizeSource.ts'),
  read('android/src/main/java/com/vivekjm/fastvideo/FastVideoPreloadRuntime.kt'), read('ios/FastVideoPreloader.swift'),
  read('android/src/main/java/com/vivekjm/fastvideo/FastVideoMediaSessionRuntime.kt'), read('ios/FastVideoNowPlayingRuntime.swift'),
]);
const pkg = JSON.parse(pkgText);
assert.equal(pkg.name, 'react-native-fast-video');
assert.equal(pkg.version, '0.0.7-alpha.0');
assert.equal(pkg.exports['.']['react-native'], './src/index.ts');
assert.match(nativeView, /requireNativeViewManager/);
assert.doesNotMatch(nativeView, /\brequireNativeView\b/);
assert.match(web, /enterpictureinpicture/);
assert.match(web, /timeToFirstFrameMs/);
assert.match(normalize, /normalizeFallbackUris/);
assert.match(normalize, /must not contain blank names or line breaks/);
for (const source of [androidPreload, applePreload]) {
  assert.match(source, /resolvedForwardRadius/);
  assert.match(source, /resolvedBackwardRadius/);
}
assert.match(androidSession, /backgroundLeaseHeld/);
assert.match(appleSession, /backgroundLeaseHeld/);
console.log('Phase 1–5 contract checks passed.');
''')
write("tests/package-contents.mjs", r'''import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
const result = spawnSync('npm', ['pack', '--dry-run', '--json', '--ignore-scripts'], {
  encoding: 'utf8', env: { ...process.env, npm_config_loglevel: 'silent' },
});
if (result.status !== 0) throw new Error(result.stderr || result.stdout || 'npm pack failed');
const report = JSON.parse(result.stdout)[0];
const files = new Set(report.files.map((file) => file.path));
for (const required of ['package.json', 'README.md', 'LICENSE', 'app.plugin.js', 'expo-module.config.json', 'android/build.gradle', 'ios/ReactNativeFastVideo.podspec', 'cpp/include/rnfv/c_api.h', 'src/index.ts']) {
  assert(files.has(required), `npm package is missing ${required}`);
}
assert(report.unpackedSize < 2_000_000, `npm package unexpectedly exceeds 2 MB (${report.unpackedSize})`);
console.log(`Package contract passed: ${report.files.length} files, ${report.unpackedSize} bytes.`);
''')

# C API numeric edge regression test.
write("cpp/tests/c_api_edge_test.cpp", r'''#include "rnfv/c_api.h"
#include <cassert>
#include <cctype>
#include <cfloat>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <limits>
#include <regex>
#include <string>
#include <string_view>
namespace {
std::string take(const char* value) { assert(value); std::string result(value); rnfv_string_destroy(value); return result; }
void assert_valid(std::string_view json) {
  assert(!json.empty()); std::string lower(json);
  for (char& c : lower) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
  assert(lower.find("nan") == std::string::npos); assert(lower.find("infinity") == std::string::npos); assert(lower.find(":inf") == std::string::npos);
}
double number(std::string_view json, const char* key) {
  const std::regex pattern(std::string("\\\"") + key + "\\\"\\s*:\\s*(-?[0-9]+(?:\\.[0-9]+)?(?:[eE][+-]?[0-9]+)?)");
  std::cmatch match; const std::string value(json); assert(std::regex_search(value.c_str(), match, pattern)); return std::strtod(match[1].str().c_str(), nullptr);
}
}
int main() {
  void* session = rnfv_session_create(); assert(session); rnfv_session_set_progress_interval(session, -1);
  const double nan = std::numeric_limits<double>::quiet_NaN(); const double inf = std::numeric_limits<double>::infinity();
  rnfv_session_event(session, RNFV_EVENT_LOAD, nan, inf, -DBL_MAX);
  rnfv_session_event(session, RNFV_EVENT_READY, 0, 0, 0); rnfv_session_event(session, RNFV_EVENT_PLAY, 0, 0, 0);
  rnfv_session_event(session, RNFV_EVENT_PROGRESS, -DBL_MAX, inf, nan); rnfv_session_event(session, RNFV_EVENT_BYTES, DBL_MAX, inf, 0);
  rnfv_session_event(session, RNFV_EVENT_FRAMES, DBL_MAX, DBL_MAX, 0);
  const std::string snapshot = take(rnfv_session_snapshot_json(session)); assert_valid(snapshot);
  const double qoe = number(snapshot, "qoeScore"); assert(std::isfinite(qoe) && qoe >= 0 && qoe <= 100);
  const double confidence = number(snapshot, "bandwidthConfidence"); assert(std::isfinite(confidence) && confidence >= 0 && confidence <= 1);
  assert_valid(take(rnfv_viewport_intent_json(INT32_MAX, INT32_MIN, 0, nan)));
  assert_valid(take(rnfv_cdn_health_json(nan, inf, -1, DBL_MAX, INT32_MAX)));
  assert_valid(take(rnfv_adaptive_decision_json(inf, nan, -DBL_MAX, INT32_MAX, INT32_MAX, INT32_MAX, INT32_MAX, INT32_MAX, 1)));
  rnfv_session_event(session, RNFV_EVENT_RELEASE, 0, 0, 0); rnfv_session_destroy(session); return 0;
}
''')
cmake_path = ROOT / "cpp/CMakeLists.txt"
cmake = cmake_path.read_text()
if "rnfv_c_api_edge_test" not in cmake:
    libraries = re.findall(r"add_library\\s*\\(\\s*([A-Za-z0-9_\\-]+)", cmake, re.I)
    target = libraries[0] if libraries else "rnfv_core"
    cmake += f"\nif(RNFV_BUILD_TESTS)\n  add_executable(rnfv_c_api_edge_test tests/c_api_edge_test.cpp)\n  target_link_libraries(rnfv_c_api_edge_test PRIVATE {target})\n  target_compile_features(rnfv_c_api_edge_test PRIVATE cxx_std_20)\n  add_test(NAME rnfv_c_api_edge_test COMMAND rnfv_c_api_edge_test)\nendif()\n"
cmake_path.write_text(cmake)

# Documentation and changelog.
changelog = read("CHANGELOG.md")
entry = """## 0.0.7-alpha.0 — Phase 1–5 hardening

- Fixed Expo native-view API compatibility and the complete web metrics contract.
- Added deterministic source/header/fallback validation and bounded retry inputs.
- Applied viewport intent direction and asymmetric preload radii on Android and Apple.
- Made active/background player ownership counters idempotent.
- Prevented Android media-session metadata updates from replacing the active media item.
- Reconciled Apple background download tasks after process relaunch.
- Added C API edge tests, source-contract checks, npm package validation, and lockfile-based CI.

"""
if "## 0.0.7-alpha.0" not in changelog:
    index = changelog.find("\n", changelog.find("# Changelog")) + 1
    changelog = changelog[:index] + "\n" + entry + changelog[index:]
write("CHANGELOG.md", changelog)
write("docs/PHASE5_HARDENING.md", """# Phase 1–5 hardening gate

This release closes correctness and parity gaps inside features already advertised by Phases 1–5. It intentionally does not add offline DRM, Cast, or certification claims from Phase 6.

## Closed gaps

- React Native/Expo and web public type contracts compile from a clean install.
- Source inputs reject blank URIs, header injection, non-finite numeric values, duplicate fallbacks, and unbounded retry settings.
- Viewport prediction controls asymmetric native preload windows.
- Foreground-to-background player ownership uses idempotent leases and cannot drive active-player counts negative.
- Explicit offline downloads reject live, DRM, and per-request-header combinations that cannot be persisted safely yet.
- Apple background downloads reconcile URL-session tasks after process relaunch.
- npm package contents, C API numeric behavior, TypeScript declarations, C++ tests, Swift parsing, Android assembly, Expo prebuild, and CocoaPods integration are CI gates.

## Certification boundary

Green CI proves source integration and deterministic host behavior. It does not substitute for physical-device 4K/HDR/DRM, battery, thermal, or competitor benchmark certification. Those remain Phase 6.
""")
for path in ["README.md", "docs/FEATURE_MATRIX.md", "docs/PHASE5_RUNTIME.md"]:
    target = ROOT / path
    if target.exists():
        target.write_text(target.read_text().replace("0.0.6-alpha.0", "0.0.7-alpha.0"))

# CI reproducibility and hardening gates.
ci = read(".github/workflows/ci.yml")
if "workflow_dispatch:" not in ci:
    ci = ci.replace("on:\n", "on:\n  workflow_dispatch:\n", 1)
ci = ci.replace("node-version: 20", "node-version: 22")
ci = ci.replace("npm install --ignore-scripts --no-audit --no-fund", "npm ci --ignore-scripts --no-audit --no-fund")
if "npm run test:contracts" not in ci:
    ci = ci.replace("      - run: npm run build\n      - run: npm run benchmark:sample", "      - run: npm run build\n      - run: npm run test:contracts\n      - run: npm run pack:check\n      - run: npm run benchmark:sample", 1)
if "cancel-in-progress:" not in ci:
    ci = ci.replace("permissions:\n  contents: read\n", "permissions:\n  contents: read\n\nconcurrency:\n  group: ci-${{ github.workflow }}-${{ github.ref }}\n  cancel-in-progress: true\n")
write(".github/workflows/ci.yml", ci)

# Remove temporary runner files from the resulting commit.
for relative in ["scripts/apply-phase5-hardening.py", ".github/workflows/apply-phase5-hardening.yml", ".phase5-hardening-trigger"]:
    target = ROOT / relative
    if target.exists():
        target.unlink()
