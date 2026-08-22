#pragma once

#include <cstdint>
#include <functional>
#include <mutex>
#include <string>

namespace rnfv {

enum class PlaybackState {
  Idle,
  Loading,
  Ready,
  Playing,
  Paused,
  Buffering,
  Ended,
  Error,
  Released,
};

struct MetricsSnapshot {
  std::uint64_t sequence{0};
  double timeToFirstFrameMs{-1.0};
  double lastSeekLatencyMs{-1.0};
  double totalRebufferMs{0.0};
  double activePlaybackMs{0.0};
  double rebufferRatio{0.0};
  std::uint64_t rebufferCount{0};
  std::uint64_t renderedFrames{0};
  std::uint64_t droppedFrames{0};
  double droppedFrameRatio{0.0};
  std::uint64_t bytesTransferred{0};
  double estimatedBitrateBps{0.0};
  double predictedBandwidthBps{0.0};
  double bandwidthConfidence{0.0};
  double bandwidthVolatility{0.0};
  std::uint64_t bandwidthSamples{0};
  double averageFrameProcessingOffsetUs{0.0};
  std::uint64_t frameProcessingSamples{0};
  double positionMs{0.0};
  double durationMs{0.0};
  double bufferedPositionMs{0.0};
  double liveOffsetMs{-1.0};
  bool isLive{false};
  bool firstFrameRendered{false};
};

struct SessionSnapshot {
  PlaybackState state{PlaybackState::Idle};
  bool playWhenReady{false};
  MetricsSnapshot metrics{};
};

class Session final {
 public:
  using Clock = std::function<std::int64_t()>;

  explicit Session(Clock clock = {});
  ~Session() = default;

  Session(const Session&) = delete;
  Session& operator=(const Session&) = delete;
  Session(Session&&) = delete;
  Session& operator=(Session&&) = delete;

  void onLoadRequested(bool isLive);
  void onReady();
  void onPlay();
  void onPause();
  void onBufferingStart();
  void onBufferingEnd();
  void onFirstFrame();
  void onSeekStart();
  void onSeekComplete();
  void onFrames(std::uint64_t rendered, std::uint64_t dropped);
  void onBytesTransferred(std::uint64_t bytes, double estimatedBitrateBps);
  void onFrameProcessingOffset(double totalOffsetUs, std::uint64_t frameCount);
  void onProgress(double positionMs, double durationMs, double bufferedPositionMs);
  void onLiveOffset(double liveOffsetMs);
  void onEnded();
  void onError();
  void release();

  void setProgressIntervalMs(std::int64_t intervalMs);
  [[nodiscard]] bool shouldEmitProgress();
  [[nodiscard]] SessionSnapshot snapshot() const;
  [[nodiscard]] std::string snapshotJson() const;

  [[nodiscard]] static std::string_view stateName(PlaybackState state) noexcept;

 private:
  [[nodiscard]] std::int64_t nowMs() const noexcept;
  void incrementSequenceLocked() noexcept;
  void accrueActivePlaybackLocked(std::int64_t now) noexcept;
  void finishBufferingLocked(std::int64_t now) noexcept;
  void normalizeRatiosLocked() noexcept;
  [[nodiscard]] bool isReleasedLocked() const noexcept;

  mutable std::mutex mutex_;
  Clock clock_;
  PlaybackState state_{PlaybackState::Idle};
  PlaybackState stateBeforeBuffering_{PlaybackState::Ready};
  bool playWhenReady_{false};
  MetricsSnapshot metrics_{};

  std::int64_t loadStartedAtMs_{-1};
  std::int64_t seekStartedAtMs_{-1};
  std::int64_t bufferingStartedAtMs_{-1};
  std::int64_t activePlaybackStartedAtMs_{-1};
  std::int64_t progressIntervalMs_{250};
  std::int64_t lastProgressEmissionAtMs_{-1};
};

}  // namespace rnfv
