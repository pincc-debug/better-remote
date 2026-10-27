#import "NativeDisplay.h"
#import <dlfcn.h>

NSString *RFDisplayUUID(uint32_t displayID) {
    typedef CFUUIDRef (*CreateUUID)(uint32_t);
    CreateUUID create = (CreateUUID)dlsym(RTLD_DEFAULT, "CGDisplayCreateUUIDFromDisplayID");
    if (!create) return nil;
    CFUUIDRef uuid = create(displayID);
    if (!uuid) return nil;
    NSString *result = CFBridgingRelease(CFUUIDCreateString(NULL, uuid));
    CFRelease(uuid);
    return result;
}

// Runtime-only CoreGraphics interfaces; keep this boundary separate from Swift.
@interface NSObject (RFVirtualDisplayAPI)
- (id)initWithDescriptor:(id)descriptor;
- (id)initWithWidth:(unsigned int)width height:(unsigned int)height refreshRate:(double)refresh;
- (BOOL)applySettings:(id)settings;
- (unsigned int)displayID;
@end

@implementation RFVirtualDisplay {
    id _display;
}
+ (BOOL)isAvailable {
    return NSClassFromString(@"CGVirtualDisplay") && NSClassFromString(@"CGVirtualDisplayDescriptor") &&
        NSClassFromString(@"CGVirtualDisplayMode") && NSClassFromString(@"CGVirtualDisplaySettings") &&
        [NSClassFromString(@"CGVirtualDisplay") instancesRespondToSelector:@selector(initWithDescriptor:)] &&
        [NSClassFromString(@"CGVirtualDisplay") instancesRespondToSelector:@selector(applySettings:)];
}
- (instancetype)initWithWidth:(uint32_t)width height:(uint32_t)height serialNumber:(uint32_t)serial {
    self = [super init];
    if (!self || ![RFVirtualDisplay isAvailable] || width < 512 || height < 512 || width > 3840 || height > 3840) return nil;
    @try {
        id descriptor = [[NSClassFromString(@"CGVirtualDisplayDescriptor") alloc] init];
        [descriptor setValue:@"Better Remote Virtual Display" forKey:@"name"];
        [descriptor setValue:dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0) forKey:@"queue"];
        // Each display has a single target size for its entire lifetime.
        [descriptor setValue:@(width * 2) forKey:@"maxPixelsWide"];
        [descriptor setValue:@(height * 2) forKey:@"maxPixelsHigh"];
        [descriptor setValue:[NSValue valueWithSize:NSMakeSize(width * 25.4 / 110, height * 25.4 / 110)] forKey:@"sizeInMillimeters"];
        [descriptor setValue:[NSValue valueWithPoint:NSMakePoint(0.3127, 0.3290)] forKey:@"whitePoint"];
        [descriptor setValue:[NSValue valueWithPoint:NSMakePoint(0.64, 0.33)] forKey:@"redPrimary"];
        [descriptor setValue:[NSValue valueWithPoint:NSMakePoint(0.30, 0.60)] forKey:@"greenPrimary"];
        [descriptor setValue:[NSValue valueWithPoint:NSMakePoint(0.15, 0.06)] forKey:@"bluePrimary"];
        [descriptor setValue:@(0x5246) forKey:@"vendorID"];
        [descriptor setValue:@(1) forKey:@"productID"];
        [descriptor setValue:@(serial) forKey:@"serialNum"];
        if ([descriptor respondsToSelector:NSSelectorFromString(@"setSerialNumber:")]) [descriptor setValue:@(serial) forKey:@"serialNumber"];
        _display = [[NSClassFromString(@"CGVirtualDisplay") alloc] initWithDescriptor:descriptor];
        if (!_display) return nil;
        id settings = [[NSClassFromString(@"CGVirtualDisplaySettings") alloc] init];
        [settings setValue:@(1) forKey:@"hiDPI"];
        id mode = [[NSClassFromString(@"CGVirtualDisplayMode") alloc] initWithWidth:width height:height refreshRate:60];
        if (!mode) return nil;
        [settings setValue:@[mode] forKey:@"modes"];
        if (![_display applySettings:settings]) return nil;
    } @catch (NSException *exception) {
        return nil;
    }
    return self;
}
- (uint32_t)displayID { return [_display displayID]; }
@end
