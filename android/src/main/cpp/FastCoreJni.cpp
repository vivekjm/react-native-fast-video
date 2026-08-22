#include <jni.h>

#include <cstdint>
#include <string>

#include "rnfv/c_api.h"

namespace {

rnfv_session_t fromHandle(jlong handle) noexcept {
  return reinterpret_cast<rnfv_session_t>(static_cast<std::uintptr_t>(handle));
}

jlong toHandle(rnfv_session_t session) noexcept {
  return static_cast<jlong>(reinterpret_cast<std::uintptr_t>(session));
}

}  // namespace

extern "C" JNIEXPORT jlong JNICALL
Java_com_vivekjm_fastvideo_FastCoreNative_create(JNIEnv*, jobject) {
  return toHandle(rnfv_session_create());
}

extern "C" JNIEXPORT void JNICALL
Java_com_vivekjm_fastvideo_FastCoreNative_destroy(JNIEnv*, jobject, jlong handle) {
  rnfv_session_destroy(fromHandle(handle));
}

extern "C" JNIEXPORT void JNICALL
Java_com_vivekjm_fastvideo_FastCoreNative_event(
    JNIEnv*, jobject, jlong handle, jint eventCode, jdouble a, jdouble b, jdouble c) {
  rnfv_session_event(fromHandle(handle), eventCode, a, b, c);
}

extern "C" JNIEXPORT void JNICALL
Java_com_vivekjm_fastvideo_FastCoreNative_setProgressInterval(
    JNIEnv*, jobject, jlong handle, jlong intervalMs) {
  rnfv_session_set_progress_interval(fromHandle(handle), intervalMs);
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_vivekjm_fastvideo_FastCoreNative_shouldEmitProgress(
    JNIEnv*, jobject, jlong handle) {
  return rnfv_session_should_emit_progress(fromHandle(handle)) != 0 ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_vivekjm_fastvideo_FastCoreNative_snapshot(JNIEnv* env, jobject, jlong handle) {
  const char* json = rnfv_session_snapshot_json(fromHandle(handle));
  if (json == nullptr) return env->NewStringUTF("{}");
  jstring result = env->NewStringUTF(json);
  rnfv_string_destroy(json);
  return result;
}

extern "C" JNIEXPORT jint JNICALL
Java_com_vivekjm_fastvideo_FastCoreNative_preloadStage(JNIEnv*, jobject, jint distance) {
  return rnfv_preload_stage_for_distance(distance);
}

extern "C" JNIEXPORT jlong JNICALL
Java_com_vivekjm_fastvideo_FastCoreNative_preloadDurationMs(JNIEnv*, jobject, jint distance) {
  return static_cast<jlong>(rnfv_preload_duration_ms_for_distance(distance));
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_vivekjm_fastvideo_FastCoreNative_adaptiveDecision(
    JNIEnv* env,
    jobject,
    jdouble bandwidthEstimateBps,
    jdouble rebufferRatio,
    jdouble droppedFrameRatio,
    jint activePlayers,
    jint width,
    jint height,
    jint networkClass,
    jint thermalClass,
    jboolean lowPowerMode) {
  const char* json = rnfv_adaptive_decision_json(
      bandwidthEstimateBps,
      rebufferRatio,
      droppedFrameRatio,
      activePlayers,
      width,
      height,
      networkClass,
      thermalClass,
      lowPowerMode == JNI_TRUE ? 1 : 0);
  if (json == nullptr) return env->NewStringUTF("{}");
  jstring result = env->NewStringUTF(json);
  rnfv_string_destroy(json);
  return result;
}


extern "C" JNIEXPORT jstring JNICALL
Java_com_vivekjm_fastvideo_FastCoreNative_viewportIntent(
    JNIEnv* env,
    jobject,
    jint currentIndex,
    jint previousIndex,
    jint itemCount,
    jdouble velocityItemsPerSecond) {
  const char* json = rnfv_viewport_intent_json(currentIndex, previousIndex, itemCount, velocityItemsPerSecond);
  if (json == nullptr) return env->NewStringUTF("{}");
  jstring result = env->NewStringUTF(json);
  rnfv_string_destroy(json);
  return result;
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_vivekjm_fastvideo_FastCoreNative_cdnHealth(
    JNIEnv* env,
    jobject,
    jdouble successRate,
    jdouble errorRate,
    jdouble medianTtffMs,
    jdouble medianResponseMs,
    jint consecutiveFailures) {
  const char* json = rnfv_cdn_health_json(successRate, errorRate, medianTtffMs, medianResponseMs, consecutiveFailures);
  if (json == nullptr) return env->NewStringUTF("{}");
  jstring result = env->NewStringUTF(json);
  rnfv_string_destroy(json);
  return result;
}
