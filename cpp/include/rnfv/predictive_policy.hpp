#pragma once

#include <cstdint>

namespace rnfv {

struct ViewportIntentInputs {
  int currentIndex{0};
  int previousIndex{0};
  int itemCount{0};
  double velocityItemsPerSecond{0.0};
};

struct ViewportIntentDecision {
  int predictedIndex{0};
  int forwardRadius{2};
  int backwardRadius{1};
  double confidence{0.0};
};

struct CdnHealthInputs {
  double successRate{1.0};
  double errorRate{0.0};
  double medianTtffMs{0.0};
  double medianResponseMs{0.0};
  int consecutiveFailures{0};
};

struct CdnHealthDecision {
  double score{0.0};
  double penalty{0.0};
};

ViewportIntentDecision predictViewportIntent(const ViewportIntentInputs& input) noexcept;
CdnHealthDecision scoreCdnHealth(const CdnHealthInputs& input) noexcept;

}  // namespace rnfv
