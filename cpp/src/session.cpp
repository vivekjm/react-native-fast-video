#include "rnfv/session.hpp"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <iomanip>
#include <limits>
#include <sstream>
#include <string_view>
#include <utility>

namespace rnfv {
namespace {

std::int64_t monotonicNowMs() noexcept {
  using namespace std::chrono;
  return duration_cast<milliseconds>(steady_clock::now().time_since_epoch()).count();
}

double finiteOr(double value, double fallback = 0.0) noexcept {
  return std::isfinite(value) ? value : fallback;
}

double nonNegativeFinite(double value, double fallback = 0.0) noexcept {
  value = finiteOr(value, fallback);
  return value < 0.0 ? fallback : value;
}

}  // namespace

Session::Session(Clock clock)
    : clock_(clock ? std::move(clock) : Clock{monotonicNowMs}) {}

void Session::onLoadRequested(bool isLive) {
  std::scoped_lock lock(mutex_);
  if (isReleasedLocked()) return;

  state_ = PlaybackState::Loading;
  stateBeforeBuffering_ = PlaybackState::Loading;
  playWhenReady_ = false;
  metrics_ = MetricsSnapshot{};
  metrics_.sequence = 1;
  metrics_.isLive = isLive;
  loadStartedAtMs_ = nowMs();
  seekStartedAtMs_ = -1;
  bufferingStartedAtMs_ = -1;
  activePlaybackStartedAtMs_ = -1;
  lastProgressEmissionAtMs_ = -1;
}

void Session::onReady() {
  std::scoped_lock lock(mutex_);
  if (isReleasedLocked() || state_ == PlaybackState::Error || state_ == PlaybackState::Ended) {
    return;
  }

  // A platform may emit READY after playWhenReady already became true. Do not
  // regress a legitimately playing state back to ready.
  if (state_ != PlaybackState::Playing && state_ != PlaybackState::Paused) {
    state_ = playWhenReady_ ? PlaybackState::Playing : PlaybackState::Ready;
  }
  incrementSequenceLocked();
}

void Session::onPlay() {
  std::scoped_lock lock(mutex_);
  if (isReleasedLocked() || state_ == PlaybackState::Error) return;
  const auto now = nowMs();
  playWhenReady_ = true;
  if (state_ == PlaybackState::Buffering) {
    stateBeforeBuffering_ = PlaybackState::Playing;
  } else if (state_ != PlaybackState::Loading) {
    state_ = PlaybackState::Playing;
    if (activePlaybackStartedAtMs_ < 0) activePlaybackStartedAtMs_ = now;
  }
  incrementSequenceLocked();
}

void Session::onPause() {
  std::scoped_lock lock(mutex_);
  if (isReleasedLocked() || state_ == PlaybackState::Error) return;
  const auto now = nowMs();
  accrueActivePlaybackLocked(now);
  playWhenReady_ = false;
  if (state_ == PlaybackState::Buffering) {
    stateBeforeBuffering_ = PlaybackState::Paused;
  } else {
    state_ = PlaybackState::Paused;
  }
  incrementSequenceLocked();
}

void Session::onBufferingStart() {
  std::scoped_lock lock(mutex_);
  if (isReleasedLocked() || state_ == PlaybackState::Error || bufferingStartedAtMs_ >= 0) {
    return;
  }
  const auto now = nowMs();
  accrueActivePlaybackLocked(now);
  stateBeforeBuffering_ = state_;
  state_ = PlaybackState::Buffering;
  bufferingStartedAtMs_ = now;
  incrementSequenceLocked();
}

void Session::onBufferingEnd() {
  std::scoped_lock lock(mutex_);
  if (isReleasedLocked() || bufferingStartedAtMs_ < 0) return;
  const auto now = nowMs();
  finishBufferingLocked(now);
  state_ = playWhenReady_ ? PlaybackState::Playing : PlaybackState::Ready;
  if (state_ == PlaybackState::Playing && activePlaybackStartedAtMs_ < 0) {
    activePlaybackStartedAtMs_ = now;
  }
  incrementSequenceLocked();
}

void Session::onFirstFrame() {
  std::scoped_lock lock(mutex_);
  if (isReleasedLocked() || metrics_.firstFrameRendered) return;
  const auto now = nowMs();
  metrics_.firstFrameRendered = true;
  if (loadStartedAtMs_ >= 0) {
    metrics_.timeToFirstFrameMs = static_cast<double>(std::max<std::int64_t>(0, now - loadStartedAtMs_));
  }
  incrementSequenceLocked();
}

void Session::onSeekStart() {
  std::scoped_lock lock(mutex_);
  if (isReleasedLocked()) return;
  seekStartedAtMs_ = nowMs();
  incrementSequenceLocked();
}

void Session::onSeekComplete() {
  std::scoped_lock lock(mutex_);
  if (isReleasedLocked() || seekStartedAtMs_ < 0) return;
  const auto elapsed = std::max<std::int64_t>(0, nowMs() - seekStartedAtMs_);
  metrics_.lastSeekLatencyMs = static_cast<double>(elapsed);
  seekStartedAtMs_ = -1;
  incrementSequenceLocked();
}

void Session::onFrames(std::uint64_t rendered, std::uint64_t dropped) {
  std::scoped_lock lock(mutex_);
  if (isReleasedLocked()) return;
  metrics_.renderedFrames += rendered;
  metrics_.droppedFrames += dropped;
  normalizeRatiosLocked();
  incrementSequenceLocked();
}

void Session::onBytesTransferred(std::uint64_t bytes, double estimatedBitrateBps) {
  std::scoped_lock lock(mutex_);
  if (isReleasedLocked()) return;
  metrics_.bytesTransferred += bytes;
  const double sample = nonNegativeFinite(estimatedBitrateBps);
  metrics_.estimatedBitrateBps = sample;
  if (sample > 0.0) {
    if (metrics_.bandwidthSamples == 0 || metrics_.predictedBandwidthBps <= 0.0) {
      metrics_.predictedBandwidthBps = sample;
      metrics_.bandwidthVolatility = 0.0;
    } else {
      const double previous = metrics_.predictedBandwidthBps;
      const double relativeError = std::abs(sample - previous) / std::max(1.0, previous);
      const double alpha = relativeError > 0.65 ? 0.50 : relativeError > 0.25 ? 0.38 : 0.24;
      metrics_.predictedBandwidthBps = alpha * sample + (1.0 - alpha) * previous;
      metrics_.bandwidthVolatility = 0.20 * relativeError + 0.80 * metrics_.bandwidthVolatility;
    }
    if (metrics_.bandwidthSamples != std::numeric_limits<std::uint64_t>::max()) ++metrics_.bandwidthSamples;
    const double sampleConfidence = std::min(1.0, static_cast<double>(metrics_.bandwidthSamples) / 8.0);
    const double stability = std::clamp(1.0 - metrics_.bandwidthVolatility, 0.0, 1.0);
    metrics_.bandwidthConfidence = std::clamp(0.15 + sampleConfidence * 0.55 + stability * 0.30, 0.0, 1.0);
  }
  incrementSequenceLocked();
}

void Session::onFrameProcessingOffset(double totalOffsetUs, std::uint64_t frameCount) {
  std::scoped_lock lock(mutex_);
  if (isReleasedLocked() || frameCount == 0 || !std::isfinite(totalOffsetUs)) return;
  const double sampleAverage = totalOffsetUs / static_cast<double>(frameCount);
  const double previousWeight = static_cast<double>(metrics_.frameProcessingSamples);
  const double nextWeight = previousWeight + static_cast<double>(frameCount);
  metrics_.averageFrameProcessingOffsetUs = nextWeight <= 0.0
      ? 0.0
      : ((metrics_.averageFrameProcessingOffsetUs * previousWeight) + sampleAverage * static_cast<double>(frameCount)) / nextWeight;
  metrics_.frameProcessingSamples = metrics_.frameProcessingSamples > std::numeric_limits<std::uint64_t>::max() - frameCount
      ? std::numeric_limits<std::uint64_t>::max()
      : metrics_.frameProcessingSamples + frameCount;
  incrementSequenceLocked();
}

void Session::onProgress(double positionMs, double durationMs, double bufferedPositionMs) {
  std::scoped_lock lock(mutex_);
  if (isReleasedLocked()) return;
  metrics_.positionMs = nonNegativeFinite(positionMs);
  metrics_.durationMs = nonNegativeFinite(durationMs);
  metrics_.bufferedPositionMs = nonNegativeFinite(bufferedPositionMs);
  if (state_ == PlaybackState::Playing && activePlaybackStartedAtMs_ < 0) {
    activePlaybackStartedAtMs_ = nowMs();
  }
  normalizeRatiosLocked();
  incrementSequenceLocked();
}

void Session::onLiveOffset(double liveOffsetMs) {
  std::scoped_lock lock(mutex_);
  if (isReleasedLocked()) return;
  metrics_.isLive = true;
  metrics_.liveOffsetMs = nonNegativeFinite(liveOffsetMs, -1.0);
  incrementSequenceLocked();
}

void Session::onEnded() {
  std::scoped_lock lock(mutex_);
  if (isReleasedLocked()) return;
  const auto now = nowMs();
  accrueActivePlaybackLocked(now);
  finishBufferingLocked(now);
  state_ = PlaybackState::Ended;
  playWhenReady_ = false;
  incrementSequenceLocked();
}

void Session::onError() {
  std::scoped_lock lock(mutex_);
  if (isReleasedLocked()) return;
  const auto now = nowMs();
  accrueActivePlaybackLocked(now);
  finishBufferingLocked(now);
  state_ = PlaybackState::Error;
  playWhenReady_ = false;
  incrementSequenceLocked();
}

void Session::release() {
  std::scoped_lock lock(mutex_);
  if (isReleasedLocked()) return;
  const auto now = nowMs();
  accrueActivePlaybackLocked(now);
  finishBufferingLocked(now);
  state_ = PlaybackState::Released;
  playWhenReady_ = false;
  incrementSequenceLocked();
}

void Session::setProgressIntervalMs(std::int64_t intervalMs) {
  std::scoped_lock lock(mutex_);
  progressIntervalMs_ = std::clamp<std::int64_t>(intervalMs, 100, 2'000);
}

bool Session::shouldEmitProgress() {
  std::scoped_lock lock(mutex_);
  if (isReleasedLocked()) return false;
  const auto now = nowMs();
  if (lastProgressEmissionAtMs_ < 0 || now - lastProgressEmissionAtMs_ >= progressIntervalMs_) {
    lastProgressEmissionAtMs_ = now;
    return true;
  }
  return false;
}

SessionSnapshot Session::snapshot() const {
  std::scoped_lock lock(mutex_);
  auto copy = metrics_;
  const auto now = nowMs();
  if (activePlaybackStartedAtMs_ >= 0) {
    copy.activePlaybackMs += static_cast<double>(std::max<std::int64_t>(0, now - activePlaybackStartedAtMs_));
  }
  if (bufferingStartedAtMs_ >= 0 && copy.firstFrameRendered) {
    copy.totalRebufferMs += static_cast<double>(std::max<std::int64_t>(0, now - bufferingStartedAtMs_));
  }
  const auto frameTotal = copy.renderedFrames + copy.droppedFrames;
  copy.droppedFrameRatio = frameTotal == 0 ? 0.0 : static_cast<double>(copy.droppedFrames) / static_cast<double>(frameTotal);
  copy.rebufferRatio = copy.activePlaybackMs <= 0.0 ? 0.0 : copy.totalRebufferMs / copy.activePlaybackMs;
  return SessionSnapshot{state_, playWhenReady_, copy};
}

std::string Session::snapshotJson() const {
  const auto value = snapshot();
  const auto& m = value.metrics;
  std::ostringstream out;
  const double ttffPenalty = m.timeToFirstFrameMs < 0 ? 0.0 : std::min(25.0, m.timeToFirstFrameMs / 120.0);
  const double rebufferPenalty = std::min(45.0, m.rebufferRatio * 450.0 + static_cast<double>(m.rebufferCount) * 1.5);
  const double droppedPenalty = std::min(25.0, m.droppedFrameRatio * 500.0);
  const double qoeScore = std::clamp(100.0 - ttffPenalty - rebufferPenalty - droppedPenalty, 0.0, 100.0);
  out << std::boolalpha << std::setprecision(12)
      << '{'
      << "\"state\":\"" << stateName(value.state) << "\"," 
      << "\"playWhenReady\":" << value.playWhenReady << ','
      << "\"sequence\":" << m.sequence << ','
      << "\"timeToFirstFrameMs\":" << m.timeToFirstFrameMs << ','
      << "\"lastSeekLatencyMs\":" << m.lastSeekLatencyMs << ','
      << "\"totalRebufferMs\":" << m.totalRebufferMs << ','
      << "\"activePlaybackMs\":" << m.activePlaybackMs << ','
      << "\"rebufferRatio\":" << m.rebufferRatio << ','
      << "\"rebufferCount\":" << m.rebufferCount << ','
      << "\"renderedFrames\":" << m.renderedFrames << ','
      << "\"droppedFrames\":" << m.droppedFrames << ','
      << "\"droppedFrameRatio\":" << m.droppedFrameRatio << ','
      << "\"qoeScore\":" << qoeScore << ','
      << "\"bytesTransferred\":" << m.bytesTransferred << ','
      << "\"estimatedBitrateBps\":" << m.estimatedBitrateBps << ','
      << "\"predictedBandwidthBps\":" << m.predictedBandwidthBps << ','
      << "\"bandwidthConfidence\":" << m.bandwidthConfidence << ','
      << "\"bandwidthVolatility\":" << m.bandwidthVolatility << ','
      << "\"bandwidthSamples\":" << m.bandwidthSamples << ','
      << "\"averageFrameProcessingOffsetUs\":" << m.averageFrameProcessingOffsetUs << ','
      << "\"frameProcessingSamples\":" << m.frameProcessingSamples << ','
      << "\"positionMs\":" << m.positionMs << ','
      << "\"durationMs\":" << m.durationMs << ','
      << "\"bufferedPositionMs\":" << m.bufferedPositionMs << ','
      << "\"liveOffsetMs\":" << m.liveOffsetMs << ','
      << "\"isLive\":" << m.isLive << ','
      << "\"firstFrameRendered\":" << m.firstFrameRendered
      << '}';
  return out.str();
}

std::string_view Session::stateName(PlaybackState state) noexcept {
  switch (state) {
    case PlaybackState::Idle: return "idle";
    case PlaybackState::Loading: return "loading";
    case PlaybackState::Ready: return "ready";
    case PlaybackState::Playing: return "playing";
    case PlaybackState::Paused: return "paused";
    case PlaybackState::Buffering: return "buffering";
    case PlaybackState::Ended: return "ended";
    case PlaybackState::Error: return "error";
    case PlaybackState::Released: return "released";
  }
  return "unknown";
}

std::int64_t Session::nowMs() const noexcept {
  try {
    return clock_ ? clock_() : monotonicNowMs();
  } catch (...) {
    return monotonicNowMs();
  }
}

void Session::incrementSequenceLocked() noexcept {
  if (metrics_.sequence != std::numeric_limits<std::uint64_t>::max()) {
    ++metrics_.sequence;
  }
}

void Session::accrueActivePlaybackLocked(std::int64_t now) noexcept {
  if (activePlaybackStartedAtMs_ < 0) return;
  metrics_.activePlaybackMs += static_cast<double>(std::max<std::int64_t>(0, now - activePlaybackStartedAtMs_));
  activePlaybackStartedAtMs_ = -1;
  normalizeRatiosLocked();
}

void Session::finishBufferingLocked(std::int64_t now) noexcept {
  if (bufferingStartedAtMs_ < 0) return;
  // Initial loading/buffering belongs to TTFF. A rebuffer is a stall after the
  // first rendered frame.
  if (metrics_.firstFrameRendered) {
    metrics_.totalRebufferMs += static_cast<double>(std::max<std::int64_t>(0, now - bufferingStartedAtMs_));
    ++metrics_.rebufferCount;
  }
  bufferingStartedAtMs_ = -1;
  normalizeRatiosLocked();
}

void Session::normalizeRatiosLocked() noexcept {
  const auto totalFrames = metrics_.renderedFrames + metrics_.droppedFrames;
  metrics_.droppedFrameRatio = totalFrames == 0
      ? 0.0
      : static_cast<double>(metrics_.droppedFrames) / static_cast<double>(totalFrames);
  metrics_.rebufferRatio = metrics_.activePlaybackMs <= 0.0
      ? 0.0
      : metrics_.totalRebufferMs / metrics_.activePlaybackMs;
}

bool Session::isReleasedLocked() const noexcept {
  return state_ == PlaybackState::Released;
}

}  // namespace rnfv
