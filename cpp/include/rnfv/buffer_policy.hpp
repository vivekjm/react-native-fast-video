#pragma once

#include <cstdint>
#include <string_view>

namespace rnfv {

enum class LatencyMode {
  LowLatency,
  Balanced,
  Quality,
  MemorySaver,
};

struct BufferPolicy {
  std::int32_t minBufferMs;
  std::int32_t maxBufferMs;
  std::int32_t bufferForPlaybackMs;
  std::int32_t bufferForPlaybackAfterRebufferMs;
  std::int32_t targetLiveOffsetMs;
  float minLivePlaybackSpeed;
  float maxLivePlaybackSpeed;
  bool prioritizeTimeOverSize;
};

[[nodiscard]] LatencyMode latencyModeFromString(std::string_view value) noexcept;
[[nodiscard]] BufferPolicy bufferPolicyFor(LatencyMode mode) noexcept;

}  // namespace rnfv
