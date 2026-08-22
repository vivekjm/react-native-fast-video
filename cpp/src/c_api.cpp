#include "rnfv/c_api.h"

#include "rnfv/session.hpp"
#include "rnfv/preload_policy.hpp"
#include "rnfv/adaptive_policy.hpp"
#include "rnfv/predictive_policy.hpp"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <new>
#include <string>

namespace {

rnfv::Session* asSession(rnfv_session_t value) noexcept {
  return static_cast<rnfv::Session*>(value);
}

std::uint64_t safeU64(double value) noexcept {
  if (!std::isfinite(value) || value <= 0.0) return 0;
  return static_cast<std::uint64_t>(value);
}

}  // namespace

extern "C" {

rnfv_session_t rnfv_session_create(void) {
  try {
    return new rnfv::Session();
  } catch (...) {
    return nullptr;
  }
}

void rnfv_session_destroy(rnfv_session_t session) {
  delete asSession(session);
}

void rnfv_session_event(
    rnfv_session_t session,
    int32_t event_code,
    double value_a,
    double value_b,
    double value_c) {
  auto* core = asSession(session);
  if (core == nullptr) return;

  switch (event_code) {
    case RNFV_EVENT_LOAD: core->onLoadRequested(value_a != 0.0); break;
    case RNFV_EVENT_READY: core->onReady(); break;
    case RNFV_EVENT_PLAY: core->onPlay(); break;
    case RNFV_EVENT_PAUSE: core->onPause(); break;
    case RNFV_EVENT_BUFFERING_START: core->onBufferingStart(); break;
    case RNFV_EVENT_BUFFERING_END: core->onBufferingEnd(); break;
    case RNFV_EVENT_FIRST_FRAME: core->onFirstFrame(); break;
    case RNFV_EVENT_SEEK_START: core->onSeekStart(); break;
    case RNFV_EVENT_SEEK_COMPLETE: core->onSeekComplete(); break;
    case RNFV_EVENT_FRAMES: core->onFrames(safeU64(value_a), safeU64(value_b)); break;
    case RNFV_EVENT_BYTES: core->onBytesTransferred(safeU64(value_a), value_b); break;
    case RNFV_EVENT_PROGRESS: core->onProgress(value_a, value_b, value_c); break;
    case RNFV_EVENT_LIVE_OFFSET: core->onLiveOffset(value_a); break;
    case RNFV_EVENT_ENDED: core->onEnded(); break;
    case RNFV_EVENT_ERROR: core->onError(); break;
    case RNFV_EVENT_RELEASE: core->release(); break;
    case RNFV_EVENT_FRAME_PROCESSING: core->onFrameProcessingOffset(value_a, safeU64(value_b)); break;
    default: break;
  }
}

void rnfv_session_set_progress_interval(rnfv_session_t session, int64_t interval_ms) {
  if (auto* core = asSession(session)) core->setProgressIntervalMs(interval_ms);
}

int32_t rnfv_session_should_emit_progress(rnfv_session_t session) {
  if (auto* core = asSession(session)) return core->shouldEmitProgress() ? 1 : 0;
  return 0;
}

const char* rnfv_session_snapshot_json(rnfv_session_t session) {
  const std::string value = asSession(session) ? asSession(session)->snapshotJson() : "{}";
  auto* output = new (std::nothrow) char[value.size() + 1];
  if (output == nullptr) return nullptr;
  std::memcpy(output, value.c_str(), value.size() + 1);
  return output;
}

void rnfv_string_destroy(const char* value) {
  delete[] value;
}

int32_t rnfv_preload_stage_for_distance(int32_t distance) {
  return static_cast<int32_t>(rnfv::preloadDecisionForDistance(distance).stage);
}

int64_t rnfv_preload_duration_ms_for_distance(int32_t distance) {
  return rnfv::preloadDecisionForDistance(distance).durationMs;
}

const char* rnfv_adaptive_decision_json(
    double bandwidth_estimate_bps,
    double rebuffer_ratio,
    double dropped_frame_ratio,
    int32_t active_players,
    int32_t width,
    int32_t height,
    int32_t network_class,
    int32_t thermal_class,
    int32_t low_power_mode) {
  rnfv::AdaptiveInputs input;
  input.bandwidthEstimateBps = bandwidth_estimate_bps;
  input.rebufferRatio = rebuffer_ratio;
  input.droppedFrameRatio = dropped_frame_ratio;
  input.activePlayers = active_players;
  input.width = width;
  input.height = height;
  input.network = static_cast<rnfv::NetworkClass>(std::max(0, std::min(4, network_class)));
  input.thermal = static_cast<rnfv::ThermalClass>(std::max(0, std::min(3, thermal_class)));
  input.lowPowerMode = low_power_mode != 0;
  const auto decision = rnfv::decideAdaptivePolicy(input);
  std::string value = std::string("{\"maxBitrateBps\":") + std::to_string(decision.maxBitrateBps) +
    ",\"preferredForwardBufferMs\":" + std::to_string(decision.preferredForwardBufferMs) +
    ",\"maxWidth\":" + std::to_string(decision.maxWidth) +
    ",\"maxHeight\":" + std::to_string(decision.maxHeight) +
    ",\"allowHdr\":" + (decision.allowHdr ? "true" : "false") +
    ",\"confidence\":" + std::to_string(decision.confidence) + "}";
  auto* output = new (std::nothrow) char[value.size() + 1];
  if (output == nullptr) return nullptr;
  std::memcpy(output, value.c_str(), value.size() + 1);
  return output;
}

const char* rnfv_viewport_intent_json(
    int32_t current_index,
    int32_t previous_index,
    int32_t item_count,
    double velocity_items_per_second) {
  rnfv::ViewportIntentInputs input;
  input.currentIndex = current_index;
  input.previousIndex = previous_index;
  input.itemCount = item_count;
  input.velocityItemsPerSecond = velocity_items_per_second;
  const auto decision = rnfv::predictViewportIntent(input);
  std::string value = std::string("{\"predictedIndex\":") + std::to_string(decision.predictedIndex) +
    ",\"forwardRadius\":" + std::to_string(decision.forwardRadius) +
    ",\"backwardRadius\":" + std::to_string(decision.backwardRadius) +
    ",\"confidence\":" + std::to_string(decision.confidence) + "}";
  auto* output = new (std::nothrow) char[value.size() + 1];
  if (output == nullptr) return nullptr;
  std::memcpy(output, value.c_str(), value.size() + 1);
  return output;
}

const char* rnfv_cdn_health_json(
    double success_rate,
    double error_rate,
    double median_ttff_ms,
    double median_response_ms,
    int32_t consecutive_failures) {
  rnfv::CdnHealthInputs input;
  input.successRate = success_rate;
  input.errorRate = error_rate;
  input.medianTtffMs = median_ttff_ms;
  input.medianResponseMs = median_response_ms;
  input.consecutiveFailures = consecutive_failures;
  const auto decision = rnfv::scoreCdnHealth(input);
  std::string value = std::string("{\"score\":") + std::to_string(decision.score) +
    ",\"penalty\":" + std::to_string(decision.penalty) + "}";
  auto* output = new (std::nothrow) char[value.size() + 1];
  if (output == nullptr) return nullptr;
  std::memcpy(output, value.c_str(), value.size() + 1);
  return output;
}

}  // extern "C"
