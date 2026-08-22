#include "rnfv/adaptive_policy.hpp"
#include "rnfv/buffer_policy.hpp"
#include "rnfv/session.hpp"
#include "rnfv/c_api.h"
#include "rnfv/predictive_policy.hpp"
#include "rnfv/preload_policy.hpp"

#include <cassert>
#include <cmath>
#include <cstdint>
#include <iostream>
#include <limits>
#include <memory>
#include <string>

namespace {

struct ManualClock {
  std::int64_t value{0};
  void advance(std::int64_t milliseconds) { value += milliseconds; }
};

void testStateOrdering() {
  auto clock = std::make_shared<ManualClock>();
  rnfv::Session session([clock] { return clock->value; });
  session.onLoadRequested(false);
  session.onPlay();
  session.onReady();
  assert(session.snapshot().state == rnfv::PlaybackState::Playing);
}

void testStartupBufferIsNotRebuffer() {
  auto clock = std::make_shared<ManualClock>();
  rnfv::Session session([clock] { return clock->value; });
  session.onLoadRequested(false);
  session.onBufferingStart();
  clock->advance(700);
  session.onBufferingEnd();
  session.onFirstFrame();
  const auto metrics = session.snapshot().metrics;
  assert(metrics.rebufferCount == 0);
  assert(metrics.totalRebufferMs == 0.0);
  assert(metrics.timeToFirstFrameMs == 700.0);
}

void testPostStartupRebuffer() {
  auto clock = std::make_shared<ManualClock>();
  rnfv::Session session([clock] { return clock->value; });
  session.onLoadRequested(true);
  clock->advance(100);
  session.onReady();
  session.onFirstFrame();
  session.onPlay();
  clock->advance(1'000);
  session.onBufferingStart();
  clock->advance(250);
  session.onBufferingEnd();
  clock->advance(1'000);
  session.onPause();
  const auto metrics = session.snapshot().metrics;
  assert(metrics.rebufferCount == 1);
  assert(metrics.totalRebufferMs == 250.0);
  assert(metrics.activePlaybackMs == 2'000.0);
  assert(std::abs(metrics.rebufferRatio - 0.125) < 0.00001);
}

void testReleaseIsTerminal() {
  rnfv::Session session;
  session.onLoadRequested(false);
  session.release();
  session.onReady();
  session.onPlay();
  session.onError();
  assert(session.snapshot().state == rnfv::PlaybackState::Released);
}

void testIntervalClamping() {
  auto clock = std::make_shared<ManualClock>();
  rnfv::Session session([clock] { return clock->value; });
  session.onLoadRequested(false);
  session.setProgressIntervalMs(1);
  assert(session.shouldEmitProgress());
  clock->advance(99);
  assert(!session.shouldEmitProgress());
  clock->advance(1);
  assert(session.shouldEmitProgress());

  session.setProgressIntervalMs(50'000);
  clock->advance(1'999);
  assert(!session.shouldEmitProgress());
  clock->advance(1);
  assert(session.shouldEmitProgress());
}

void testNonFiniteMetricsAreSanitized() {
  rnfv::Session session;
  session.onLoadRequested(false);
  session.onProgress(
      std::numeric_limits<double>::quiet_NaN(),
      std::numeric_limits<double>::infinity(),
      -100.0);
  session.onBytesTransferred(10, std::numeric_limits<double>::quiet_NaN());
  const auto metrics = session.snapshot().metrics;
  assert(metrics.positionMs == 0.0);
  assert(metrics.durationMs == 0.0);
  assert(metrics.bufferedPositionMs == 0.0);
  assert(metrics.estimatedBitrateBps == 0.0);
}

void testPolicyProfiles() {
  const auto low = rnfv::bufferPolicyFor(rnfv::LatencyMode::LowLatency);
  const auto quality = rnfv::bufferPolicyFor(rnfv::LatencyMode::Quality);
  assert(low.maxBufferMs < quality.maxBufferMs);
  assert(low.targetLiveOffsetMs < quality.targetLiveOffsetMs);
  assert(rnfv::latencyModeFromString("memorySaver") == rnfv::LatencyMode::MemorySaver);
}

void testPreloadPolicy() {
  const auto next = rnfv::preloadDecisionForDistance(1);
  assert(next.stage == rnfv::PreloadStage::rangeLoaded);
  assert(next.durationMs == 3000);

  const auto previous = rnfv::preloadDecisionForDistance(-1);
  assert(previous.stage == rnfv::PreloadStage::rangeLoaded);
  assert(previous.durationMs == 3000);

  const auto second = rnfv::preloadDecisionForDistance(2);
  assert(second.stage == rnfv::PreloadStage::rangeCached);
  assert(second.durationMs == 6000);
  assert(rnfv::preloadDecisionForDistance(3).stage == rnfv::PreloadStage::tracksSelected);
  assert(rnfv::preloadDecisionForDistance(4).stage == rnfv::PreloadStage::sourcePrepared);
  assert(rnfv::preloadDecisionForDistance(5).stage == rnfv::PreloadStage::none);
}

void testJsonSnapshot() {
  rnfv::Session session;
  session.onLoadRequested(true);
  session.onReady();
  const std::string json = session.snapshotJson();
  assert(json.find("\"state\":\"ready\"") != std::string::npos);
  assert(json.find("\"isLive\":true") != std::string::npos);
  assert(json.find("\"qoeScore\":") != std::string::npos);
}

}  // namespace

int main() {
  testStateOrdering();
  testStartupBufferIsNotRebuffer();
  testPostStartupRebuffer();
  testReleaseIsTerminal();
  testIntervalClamping();
  testNonFiniteMetricsAreSanitized();
  testPolicyProfiles();
  testPreloadPolicy();
  testJsonSnapshot();

  {
    rnfv::Session session;
    session.onLoadRequested(false);
    session.onBytesTransferred(1000, 8'000'000);
    session.onBytesTransferred(1000, 10'000'000);
    session.onBytesTransferred(1000, 9'000'000);
    const auto snapshot = session.snapshot();
    assert(snapshot.metrics.predictedBandwidthBps > 8'000'000);
    assert(snapshot.metrics.predictedBandwidthBps < 10'000'000);
    assert(snapshot.metrics.bandwidthSamples == 3);
    assert(snapshot.metrics.bandwidthConfidence > 0.3);
    session.onFrameProcessingOffset(12'000, 6);
    session.onFrameProcessingOffset(4'000, 2);
    const auto diagnostics = session.snapshot();
    assert(diagnostics.metrics.frameProcessingSamples == 8);
    assert(std::abs(diagnostics.metrics.averageFrameProcessingOffsetUs - 2000.0) < 0.01);
  }

  {
    rnfv::ViewportIntentInputs input;
    input.currentIndex = 10;
    input.previousIndex = 9;
    input.itemCount = 30;
    input.velocityItemsPerSecond = 3.8;
    const auto intent = rnfv::predictViewportIntent(input);
    assert(intent.predictedIndex == 13);
    assert(intent.forwardRadius == 4);
    assert(intent.backwardRadius == 1);
    assert(intent.confidence > 0.6);

    rnfv::CdnHealthInputs healthy;
    healthy.successRate = 0.99;
    healthy.errorRate = 0.01;
    healthy.medianTtffMs = 350;
    healthy.medianResponseMs = 80;
    const auto healthyScore = rnfv::scoreCdnHealth(healthy);

    rnfv::CdnHealthInputs failing = healthy;
    failing.successRate = 0.7;
    failing.errorRate = 0.3;
    failing.consecutiveFailures = 3;
    const auto failingScore = rnfv::scoreCdnHealth(failing);
    assert(healthyScore.score > failingScore.score);
    assert(failingScore.penalty > healthyScore.penalty);
  }

  {
    const char* viewport = rnfv_viewport_intent_json(5, 4, 20, 3.2);
    assert(viewport != nullptr);
    const std::string viewportJson(viewport);
    rnfv_string_destroy(viewport);
    assert(viewportJson.find("\"predictedIndex\":8") != std::string::npos);

    const char* cdn = rnfv_cdn_health_json(0.99, 0.01, 300, 70, 0);
    assert(cdn != nullptr);
    const std::string cdnJson(cdn);
    rnfv_string_destroy(cdn);
    assert(cdnJson.find("\"score\":") != std::string::npos);
  }
  std::cout << "FastCore tests passed\n";
  {
    rnfv::AdaptiveInputs fast{};
    fast.bandwidthEstimateBps = 20'000'000;
    fast.activePlayers = 2;
    auto decision = rnfv::decideAdaptivePolicy(fast);
    assert(decision.maxBitrateBps > 5'000'000);
    assert(decision.maxWidth >= 1920);

    fast.activePlayers = 4;
    auto shared = rnfv::decideAdaptivePolicy(fast);
    assert(shared.maxBitrateBps < decision.maxBitrateBps);

    fast.activePlayers = 2;
    fast.thermal = rnfv::ThermalClass::Critical;
    fast.lowPowerMode = true;
    auto constrained = rnfv::decideAdaptivePolicy(fast);
    assert(constrained.maxBitrateBps < decision.maxBitrateBps);
    assert(constrained.maxHeight <= 1080);
    assert(!constrained.allowHdr);
  }

  return 0;
}

// Phase 4 adaptive policy smoke tests are compiled into the same deterministic host binary.
