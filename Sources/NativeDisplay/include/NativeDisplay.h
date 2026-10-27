#import "RemoteAssertionNotifications.h"
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSString * _Nullable RFDisplayUUID(uint32_t displayID);
// The owner is confined to DisplayEngine. Releasing it disconnects the display.
@interface RFVirtualDisplay : NSObject
+ (BOOL)isAvailable;
// A single target mode and a distinct serial avoid reusing a capture stream's old size.
- (nullable instancetype)initWithWidth:(uint32_t)width height:(uint32_t)height serialNumber:(uint32_t)serial;
@property(nonatomic, readonly) uint32_t displayID;
@end
NS_ASSUME_NONNULL_END
