#import <Foundation/Foundation.h>
typedef void (^TGInputListener)(NSString *action, NSString *context, BOOL down);
/** Digital edge resolver; independent of UIKit, Kroll and the graphics backend. */
@interface TGInputResolver : NSObject
- (instancetype)initWithListener:(TGInputListener)listener;
- (void)setMap:(id)value;
- (NSDictionary *)map;
- (void)setContext:(NSString *)context;
- (NSString *)context;
- (BOOL)hasBindings:(NSString *)device;
- (BOOL)transition:(NSString *)device identity:(NSString *)identity code:(NSString *)code down:(BOOL)down;
- (void)releaseDevice:(NSString *)device identity:(NSString *)identity;
- (void)releaseAll;
@end
