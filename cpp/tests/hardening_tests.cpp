#include "rnfv/c_api.h"

#include <cassert>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <iostream>
#include <limits>
#include <string>

namespace {

std::string owned_string(const char* raw) {
  assert(raw != nullptr);
  std::string value(raw);
  rnfv_string_destroy(raw);
  return value;
}

void require_finite_json(const std::string& json) {
  assert(!json.empty());
  assert(json.find("nan") == std::string::npos);
  assert(json.find("NaN") == std::string::npos);
  assert(json.find("inf") == std::string::npos);
  assert(json.find("Infinity") == std::string::npos);
}

void require_contains(const std::string& value, const char* needle) {
  if (value.find(needle) == std::string::npos) {
    std::cerr << "Expected " << value << " to contain " << needle << '\n';
    std::abort();
  }
}

}  // namespace

int main() {
  void* session = rnfv_session_create();
  assert(session != nullptr);

  // Hostile native observations must never leak non-finite JSON into Kotlin/Swift/JS.
  const double nan = std::numeric_limits<double>::quiet_NaN();
  const double infinity = std::numeric_limits<double>::infinity();
  rnfv_session_event(session, RNFV_EVENT_PROGRESS, nan, infinity, -infinity);
  rnfv_session_event(session, RNFV_EVENT_BYTES, infinity, nan, 0.0);
  rnfv_session_event(session, RNFV_EVENT_FRAMES, -1.0, infinity, 0.0);
  rnfv_session_event(session, RNFV_EVENT_FRAME_PROCESSING, nan, -100.0, 0.0);
  rnfv_session_event(session, RNFV_EVENT_LIVE_OFFSET, -infinity, 0.0, 0.0);

  // Unknown/negative intervals are clamped by the core and remain safe to query.
  rnfv_session_set_progress_interval(session, -1);
  (void)rnfv_session_should_emit_progress(session);

  std::string snapshot = owned_string(rnfv_session_snapshot_json(session));
  require_finite_json(snapshot);
  require_contains(snapshot, "\"qoeScore\"");
  require_contains(snapshot, "\"predictedBandwidthBps\"");
  require_contains(snapshot, "\"frameProcessingSamples\"");

  // Predictions must remain bounded even with impossible indices and velocity values.
  std::string viewport = owned_string(
      rnfv_viewport_intent_json(-50, 5000, 3, infinity));
  require_finite_json(viewport);
  require_contains(viewport, "\"predictedIndex\"");
  require_contains(viewport, "\"forwardRadius\"");
  require_contains(viewport, "\"backwardRadius\"");

  // CDN scoring and ABR output must sanitize malformed telemetry rather than emitting NaN.
  std::string cdn = owned_string(
      rnfv_cdn_health_json(nan, infinity, -1.0, infinity,
                           std::numeric_limits<std::int32_t>::max()));
  require_finite_json(cdn);
  require_contains(cdn, "\"score\"");

  std::string adaptive = owned_string(rnfv_adaptive_decision_json(
      infinity, nan, infinity, std::numeric_limits<std::int32_t>::max(),
      -3840, -2160, 999, -999, 1));
  require_finite_json(adaptive);
  require_contains(adaptive, "\"maxBitrateBps\"");
  require_contains(adaptive, "\"confidence\"");

  // Repeated large observations exercise saturating/finite counter paths under sanitizers.
  for (int i = 0; i < 10000; ++i) {
    rnfv_session_event(session, RNFV_EVENT_BYTES, 9.0e18, 9.0e18, 0.0);
    rnfv_session_event(session, RNFV_EVENT_FRAMES, 9.0e18, 9.0e18, 0.0);
  }
  snapshot = owned_string(rnfv_session_snapshot_json(session));
  require_finite_json(snapshot);

  rnfv_session_event(session, RNFV_EVENT_RELEASE, 0.0, 0.0, 0.0);
  rnfv_session_destroy(session);
  return 0;
}
