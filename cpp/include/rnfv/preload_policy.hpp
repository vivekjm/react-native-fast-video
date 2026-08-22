#pragma once

#include <cstdint>

namespace rnfv {

enum class PreloadStage : std::int32_t {
  none = 0,
  sourcePrepared = 1,
  tracksSelected = 2,
  rangeLoaded = 3,
  rangeCached = 4,
};

struct PreloadDecision {
  PreloadStage stage{PreloadStage::none};
  std::int64_t durationMs{0};
};

// Feed/carousel policy intentionally tiny and deterministic. Platform runtimes can execute this
// plan with Media3, AVFoundation, or another native backend without involving JavaScript.
PreloadDecision preloadDecisionForDistance(std::int32_t distance) noexcept;

}  // namespace rnfv
