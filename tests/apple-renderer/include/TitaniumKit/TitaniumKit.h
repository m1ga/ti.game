#import <Foundation/Foundation.h>
// Graphics tests pass nil for the optional proxy. Only the bridge declaration
// is needed to compile the production renderer; no fake events are delivered.
@interface TiProxy : NSObject
- (BOOL)_hasListeners:(NSString *)name;
- (void)fireEvent:(NSString *)name withObject:(id)object;
@end
