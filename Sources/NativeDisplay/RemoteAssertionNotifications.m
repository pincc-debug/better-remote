#import "RemoteAssertionNotifications.h"
#import <IOKit/pwr_mgt/IOPMLib.h>
#import <notify.h>
#import <dlfcn.h>
typedef IOReturn (*RFRegisterAssertionNotify)(char *, int);
@implementation RFAssertionNotifications {
    RFRegisterAssertionNotify _registration;
    int _token;
    BOOL _registered;
    void (^_handler)(void);
}
- (BOOL)startWithHandler:(void (^)(void))handler {
    [self stop];
    _registration = (RFRegisterAssertionNotify)dlsym(RTLD_DEFAULT, "IOPMAssertionNotify");
    if (!_registration) return NO;
    char name[] = "com.apple.system.powermanagement.assertions.anychange";
    __weak RFAssertionNotifications *weakSelf = self;
    if (notify_register_dispatch(name, &_token, dispatch_get_main_queue(), ^(int token) {
        RFAssertionNotifications *owner = weakSelf;
        if (owner && owner->_registered && owner->_handler) owner->_handler();
    }) != NOTIFY_STATUS_OK) return NO;
    if (_registration(name, 1) != kIOReturnSuccess) { notify_cancel(_token); return NO; }
    _handler = [handler copy];
    _registered = YES;
    return YES;
}
- (void)stop {
    if (_registered) {
        _registered = NO;
        char name[] = "com.apple.system.powermanagement.assertions.anychange";
        _registration(name, 2);
        notify_cancel(_token);
    }
    _handler = nil;
}
- (void)dealloc { [self stop]; }
@end
