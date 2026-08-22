#include "rnfv/buffer_policy.hpp"

namespace rnfv {

LatencyMode latencyModeFromString(std::string_view value) noexcept {
  if (value == "lowLatency" || value == "low-latency") {
    return LatencyMode::LowLatency;
  }
  if (value == "quality") {
    return LatencyMode::Quality;
  }
  if (value == "memorySaver" || value == "memory-saver") {
    return LatencyMode::MemorySaver;
  }
  return LatencyMode::Balanced;
}

BufferPolicy bufferPolicyFor(LatencyMode mode) noexcept {
  switch (mode) {
    case LatencyMode::LowLatency:
      return BufferPolicy{
          .minBufferMs = 1'000,
          .maxBufferMs = 6'000,
          .bufferForPlaybackMs = 250,
          .bufferForPlaybackAfterRebufferMs = 500,
          .targetLiveOffsetMs = 2'000,
          .minLivePlaybackSpeed = 0.97F,
          .maxLivePlaybackSpeed = 1.05F,
          .prioritizeTimeOverSize = true,
      };
    case LatencyMode::Quality:
      return BufferPolicy{
          .minBufferMs = 20'000,
          .maxBufferMs = 90'000,
          .bufferForPlaybackMs = 1'500,
          .bufferForPlaybackAfterRebufferMs = 3'000,
          .targetLiveOffsetMs = 8'000,
          .minLivePlaybackSpeed = 0.98F,
          .maxLivePlaybackSpeed = 1.02F,
          .prioritizeTimeOverSize = true,
      };
    case LatencyMode::MemorySaver:
      return BufferPolicy{
          .minBufferMs = 1'500,
          .maxBufferMs = 8'000,
          .bufferForPlaybackMs = 500,
          .bufferForPlaybackAfterRebufferMs = 1'000,
          .targetLiveOffsetMs = 5'000,
          .minLivePlaybackSpeed = 0.98F,
          .maxLivePlaybackSpeed = 1.03F,
          .prioritizeTimeOverSize = true,
      };
    case LatencyMode::Balanced:
    default:
      return BufferPolicy{
          .minBufferMs = 8'000,
          .maxBufferMs = 40'000,
          .bufferForPlaybackMs = 750,
          .bufferForPlaybackAfterRebufferMs = 1'500,
          .targetLiveOffsetMs = 5'000,
          .minLivePlaybackSpeed = 0.98F,
          .maxLivePlaybackSpeed = 1.03F,
          .prioritizeTimeOverSize = true,
      };
  }
}

}  // namespace rnfv
