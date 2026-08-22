#include "rnfv/preload_policy.hpp"

#include <cstdlib>

namespace rnfv {

PreloadDecision preloadDecisionForDistance(std::int32_t distance) noexcept {
  const auto absolute = std::abs(distance);
  if (absolute == 1) return {PreloadStage::rangeLoaded, 3000};
  if (absolute == 2) return {PreloadStage::rangeCached, 6000};
  if (absolute == 3) return {PreloadStage::tracksSelected, 0};
  if (absolute == 4) return {PreloadStage::sourcePrepared, 0};
  return {PreloadStage::none, 0};
}

}  // namespace rnfv
