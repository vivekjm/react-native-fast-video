#pragma once

#include <stdint.h>

#if defined(_WIN32)
#define RNFV_EXPORT __declspec(dllexport)
#else
#define RNFV_EXPORT __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef void* rnfv_session_t;

enum rnfv_event_code {
  RNFV_EVENT_LOAD = 1,
  RNFV_EVENT_READY = 2,
  RNFV_EVENT_PLAY = 3,
  RNFV_EVENT_PAUSE = 4,
  RNFV_EVENT_BUFFERING_START = 5,
  RNFV_EVENT_BUFFERING_END = 6,
  RNFV_EVENT_FIRST_FRAME = 7,
  RNFV_EVENT_SEEK_START = 8,
  RNFV_EVENT_SEEK_COMPLETE = 9,
  RNFV_EVENT_FRAMES = 10,
  RNFV_EVENT_BYTES = 11,
  RNFV_EVENT_PROGRESS = 12,
  RNFV_EVENT_LIVE_OFFSET = 13,
  RNFV_EVENT_ENDED = 14,
  RNFV_EVENT_ERROR = 15,
  RNFV_EVENT_RELEASE = 16,
  RNFV_EVENT_FRAME_PROCESSING = 17
};

RNFV_EXPORT rnfv_session_t rnfv_session_create(void);
RNFV_EXPORT void rnfv_session_destroy(rnfv_session_t session);
RNFV_EXPORT void rnfv_session_event(
    rnfv_session_t session,
    int32_t event_code,
    double value_a,
    double value_b,
    double value_c);
RNFV_EXPORT void rnfv_session_set_progress_interval(
    rnfv_session_t session,
    int64_t interval_ms);
RNFV_EXPORT int32_t rnfv_session_should_emit_progress(rnfv_session_t session);
RNFV_EXPORT const char* rnfv_session_snapshot_json(rnfv_session_t session);
RNFV_EXPORT void rnfv_string_destroy(const char* value);
RNFV_EXPORT int32_t rnfv_preload_stage_for_distance(int32_t distance);
RNFV_EXPORT int64_t rnfv_preload_duration_ms_for_distance(int32_t distance);
RNFV_EXPORT const char* rnfv_adaptive_decision_json(
    double bandwidth_estimate_bps,
    double rebuffer_ratio,
    double dropped_frame_ratio,
    int32_t active_players,
    int32_t width,
    int32_t height,
    int32_t network_class,
    int32_t thermal_class,
    int32_t low_power_mode);

RNFV_EXPORT const char* rnfv_viewport_intent_json(
    int32_t current_index,
    int32_t previous_index,
    int32_t item_count,
    double velocity_items_per_second);
RNFV_EXPORT const char* rnfv_cdn_health_json(
    double success_rate,
    double error_rate,
    double median_ttff_ms,
    double median_response_ms,
    int32_t consecutive_failures);

#ifdef __cplusplus
}
#endif
