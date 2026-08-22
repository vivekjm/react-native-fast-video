#pragma once

#include <cstdint>

namespace rnfv {

enum class NetworkClass : std::uint8_t { Offline = 0, Constrained = 1, Cellular = 2, Wifi = 3, Ethernet = 4 };
enum class ThermalClass : std::uint8_t { Nominal = 0, Fair = 1, Serious = 2, Critical = 3 };

struct AdaptiveInputs {
  double bandwidthEstimateBps{0.0};
  double rebufferRatio{0.0};
  double droppedFrameRatio{0.0};
  int activePlayers{1};
  int width{0};
  int height{0};
  bool hdr{false};
  NetworkClass network{NetworkClass::Wifi};
  ThermalClass thermal{ThermalClass::Nominal};
  bool lowPowerMode{false};
};

struct AdaptiveDecision {
  std::int64_t maxBitrateBps{0};
  std::int64_t preferredForwardBufferMs{0};
  int maxWidth{0};
  int maxHeight{0};
  bool allowHdr{true};
  double confidence{0.0};
};

AdaptiveDecision decideAdaptivePolicy(const AdaptiveInputs& input) noexcept;

} // namespace rnfv
