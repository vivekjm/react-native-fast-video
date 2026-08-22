#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RNFVFastCoreBridge : NSObject {
 @private
  void *_session;
}

- (void)event:(NSInteger)eventCode
       valueA:(double)valueA
       valueB:(double)valueB
       valueC:(double)valueC;
- (void)setProgressIntervalMs:(NSInteger)intervalMs;
- (BOOL)shouldEmitProgress;
- (NSDictionary<NSString *, id> *)snapshot;
- (NSDictionary<NSString *, id> *)viewportIntentWithCurrentIndex:(NSInteger)currentIndex
                                             previousIndex:(NSInteger)previousIndex
                                                 itemCount:(NSInteger)itemCount
                                    velocityItemsPerSecond:(double)velocityItemsPerSecond;
- (NSDictionary<NSString *, id> *)cdnHealthWithSuccessRate:(double)successRate
                                                  errorRate:(double)errorRate
                                               medianTtffMs:(double)medianTtffMs
                                           medianResponseMs:(double)medianResponseMs
                                       consecutiveFailures:(NSInteger)consecutiveFailures;
- (NSDictionary<NSString *, id> *)adaptiveDecisionWithBandwidth:(double)bandwidthEstimateBps
                                             rebufferRatio:(double)rebufferRatio
                                         droppedFrameRatio:(double)droppedFrameRatio
                                             activePlayers:(NSInteger)activePlayers
                                                     width:(NSInteger)width
                                                    height:(NSInteger)height
                                              networkClass:(NSInteger)networkClass
                                              thermalClass:(NSInteger)thermalClass
                                              lowPowerMode:(BOOL)lowPowerMode;
- (void)releaseSession;

@end

NS_ASSUME_NONNULL_END
