#import <Foundation/Foundation.h>
@interface TiProxy : NSObject
@property NSMutableArray *events;
- (BOOL)_hasListeners:(NSString *)event;
- (void)fireEvent:(NSString *)event withObject:(NSDictionary *)data;
@end
