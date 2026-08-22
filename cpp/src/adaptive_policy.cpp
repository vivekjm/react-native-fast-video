#include "rnfv/adaptive_policy.hpp"

#include <algorithm>
#include <cmath>

namespace rnfv {

AdaptiveDecision decideAdaptivePolicy(const AdaptiveInputs& in) noexcept {
  AdaptiveDecision out;
  const int players = std::max(1, in.activePlayers);
  double estimate = std::isfinite(in.bandwidthEstimateBps) ? std::max(0.0, in.bandwidthEstimateBps) : 0.0;
  if (estimate <= 0.0) {
    estimate = in.network == NetworkClass::Ethernet ? 30'000'000.0 :
      in.network == NetworkClass::Wifi ? 18'000'000.0 :
      in.network == NetworkClass::Cellular ? 6'000'000.0 :
      in.network == NetworkClass::Constrained ? 1'500'000.0 : 0.0;
  }

  double safety = 0.78;
  if (in.rebufferRatio > 0.03) safety -= 0.20;
  if (in.rebufferRatio > 0.08) safety -= 0.18;
  if (in.droppedFrameRatio > 0.02) safety -= 0.12;
  if (in.lowPowerMode) safety -= 0.10;
  if (in.thermal == ThermalClass::Serious) safety -= 0.18;
  if (in.thermal == ThermalClass::Critical) safety -= 0.30;
  safety = std::clamp(safety, 0.28, 0.88);

  const double fairShare = estimate / static_cast<double>(players);
  out.maxBitrateBps = static_cast<std::int64_t>(std::max(0.0, fairShare * safety));
  out.preferredForwardBufferMs = in.network == NetworkClass::Constrained ? 12'000 :
    in.network == NetworkClass::Cellular ? 8'000 : 5'000;

  const bool stressed = in.thermal >= ThermalClass::Serious || in.lowPowerMode || in.droppedFrameRatio > 0.04;
  const bool severelyStressed = in.thermal == ThermalClass::Critical || in.droppedFrameRatio > 0.10;
  if (severelyStressed || out.maxBitrateBps < 2'000'000) {
    out.maxWidth = 1280; out.maxHeight = 720;
  } else if (stressed || out.maxBitrateBps < 6'000'000) {
    out.maxWidth = 1920; out.maxHeight = 1080;
  } else {
    out.maxWidth = 3840; out.maxHeight = 2160;
  }
  out.allowHdr = !stressed && out.maxBitrateBps >= 5'000'000;
  out.confidence = std::clamp((estimate > 0.0 ? 0.55 : 0.2) + (in.bandwidthEstimateBps > 0.0 ? 0.30 : 0.0), 0.0, 1.0);
  return out;
}

} // namespace rnfv
