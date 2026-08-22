#import "RNFVFastCoreBridge.h"

#import "rnfv/c_api.h"

#include <cstring>

@implementation RNFVFastCoreBridge

- (instancetype)init {
  self = [super init];
  if (self) {
    _session = rnfv_session_create();
  }
  return self;
}

- (void)dealloc {
  [self releaseSession];
}

- (void)event:(NSInteger)eventCode
       valueA:(double)valueA
       valueB:(double)valueB
       valueC:(double)valueC {
  if (_session == nullptr) {
    return;
  }
  rnfv_session_event(_session, (int32_t)eventCode, valueA, valueB, valueC);
}

- (void)setProgressIntervalMs:(NSInteger)intervalMs {
  if (_session != nullptr) {
    rnfv_session_set_progress_interval(_session, (int64_t)intervalMs);
  }
}

- (BOOL)shouldEmitProgress {
  return _session != nullptr && rnfv_session_should_emit_progress(_session) != 0;
}

- (NSDictionary<NSString *, id> *)snapshot {
  if (_session == nullptr) {
    return @{};
  }
  const char *json = rnfv_session_snapshot_json(_session);
  if (json == nullptr) {
    return @{};
  }
  NSData *data = [NSData dataWithBytes:json length:strlen(json)];
  rnfv_string_destroy(json);
  NSError *error = nil;
  id value = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
  return [value isKindOfClass:[NSDictionary class]] ? value : @{};
}


- (NSDictionary<NSString *, id> *)dictionaryFromOwnedJson:(const char *)json {
  if (json == nullptr) return @{};
  NSData *data = [NSData dataWithBytes:json length:strlen(json)];
  rnfv_string_destroy(json);
  NSError *error = nil;
  id value = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
  return [value isKindOfClass:[NSDictionary class]] ? value : @{};
}

- (NSDictionary<NSString *, id> *)viewportIntentWithCurrentIndex:(NSInteger)currentIndex
                                             previousIndex:(NSInteger)previousIndex
                                                 itemCount:(NSInteger)itemCount
                                    velocityItemsPerSecond:(double)velocityItemsPerSecond {
  return [self dictionaryFromOwnedJson:rnfv_viewport_intent_json(
      (int32_t)currentIndex, (int32_t)previousIndex, (int32_t)itemCount, velocityItemsPerSecond)];
}

- (NSDictionary<NSString *, id> *)cdnHealthWithSuccessRate:(double)successRate
                                                  errorRate:(double)errorRate
                                               medianTtffMs:(double)medianTtffMs
                                           medianResponseMs:(double)medianResponseMs
                                       consecutiveFailures:(NSInteger)consecutiveFailures {
  return [self dictionaryFromOwnedJson:rnfv_cdn_health_json(
      successRate, errorRate, medianTtffMs, medianResponseMs, (int32_t)consecutiveFailures)];
}

- (NSDictionary<NSString *, id> *)adaptiveDecisionWithBandwidth:(double)bandwidthEstimateBps
                                             rebufferRatio:(double)rebufferRatio
                                         droppedFrameRatio:(double)droppedFrameRatio
                                             activePlayers:(NSInteger)activePlayers
                                                     width:(NSInteger)width
                                                    height:(NSInteger)height
                                              networkClass:(NSInteger)networkClass
                                              thermalClass:(NSInteger)thermalClass
                                              lowPowerMode:(BOOL)lowPowerMode {
  const char *json = rnfv_adaptive_decision_json(
      bandwidthEstimateBps, rebufferRatio, droppedFrameRatio,
      (int32_t)activePlayers, (int32_t)width, (int32_t)height,
      (int32_t)networkClass, (int32_t)thermalClass, lowPowerMode ? 1 : 0);
  if (json == nullptr) return @{};
  NSData *data = [NSData dataWithBytes:json length:strlen(json)];
  rnfv_string_destroy(json);
  NSError *error = nil;
  id value = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
  return [value isKindOfClass:[NSDictionary class]] ? value : @{};
}

- (void)releaseSession {
  if (_session == nullptr) {
    return;
  }
  rnfv_session_event(_session, RNFV_EVENT_RELEASE, 0, 0, 0);
  rnfv_session_destroy(_session);
  _session = nullptr;
}

@end
