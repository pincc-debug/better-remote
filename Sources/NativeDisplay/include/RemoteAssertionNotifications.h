#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
/// Main-queue subscription; unavailable private API is a normal fallback case.
@interface RFAssertionNotifications : NSObject
- (BOOL)startWithHandler:(void (^)(void))handler NS_SWIFT_NAME(start(handler:));
- (void)stop;
@end
NS_ASSUME_NONNULL_END
