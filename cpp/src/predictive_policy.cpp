#include "rnfv/predictive_policy.hpp"

#include <algorithm>
#include <cmath>

namespace rnfv {
namespace {

double finite(double value, double fallback = 0.0) noexcept {
  return std::isfinite(value) ? value : fallback;
}

}  // namespace

ViewportIntentDecision predictViewportIntent(const ViewportIntentInputs& in) noexcept {
  ViewportIntentDecision out;
  const int count = std::max(0, in.itemCount);
  if (count == 0) return out;

  const int current = std::clamp(in.currentIndex, 0, count - 1);
  const int previous = std::clamp(in.previousIndex, 0, count - 1);
  const double velocity = finite(in.velocityItemsPerSecond);
  const double speed = std::abs(velocity);
  int direction = velocity > 0.12 ? 1 : velocity < -0.12 ? -1 : (current > previous ? 1 : current < previous ? -1 : 0);

  int lead = 0;
  if (speed >= 5.0) lead = 4;
  else if (speed >= 3.0) lead = 3;
  else if (speed >= 1.5) lead = 2;
  else if (speed >= 0.35) lead = 1;

  if (direction == 0) lead = 0;
  out.predictedIndex = std::clamp(current + direction * lead, 0, count - 1);
  out.forwardRadius = speed >= 3.0 ? 4 : speed >= 1.0 ? 3 : 2;
  out.backwardRadius = speed >= 3.0 ? 1 : 2;
  out.confidence = std::clamp(0.25 + std::min(0.55, speed / 7.0) + (current != previous ? 0.15 : 0.0), 0.0, 0.95);
  return out;
}

CdnHealthDecision scoreCdnHealth(const CdnHealthInputs& in) noexcept {
  const double success = std::clamp(finite(in.successRate, 1.0), 0.0, 1.0);
  const double error = std::clamp(finite(in.errorRate), 0.0, 1.0);
  const double ttff = std::max(0.0, finite(in.medianTtffMs));
  const double response = std::max(0.0, finite(in.medianResponseMs));
  const double failurePenalty = std::min(45.0, static_cast<double>(std::max(0, in.consecutiveFailures)) * 12.0);
  const double reliability = success * 60.0 - error * 35.0;
  const double latencyPenalty = std::min(20.0, ttff / 150.0) + std::min(12.0, response / 100.0);

  CdnHealthDecision out;
  out.penalty = failurePenalty + latencyPenalty;
  out.score = std::clamp(40.0 + reliability - out.penalty, 0.0, 100.0);
  return out;
}

}  // namespace rnfv
