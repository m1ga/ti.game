#import <Foundation/Foundation.h>
#import <GameController/GameController.h>
#import <TitaniumKit/TitaniumKit.h>
#import "TGGamepadController.h"
@interface TGGamepadController (Testing)
- (void)attachController:(GCController *)controller announce:(BOOL)announce;
- (void)gamepad:(GCExtendedGamepad *)pad changed:(GCControllerElement *)element device:(id)device;
@end
@interface CountingReceiver : TGGamepadController
@property NSUInteger dispatchCount;
@end
@implementation CountingReceiver
- (void)gamepad:(GCExtendedGamepad *)pad changed:(GCControllerElement *)element device:(id)device {
    self.dispatchCount++;
    [super gamepad:pad changed:element device:device];
}
@end
@implementation TiProxy
- (instancetype)init { if (self = [super init]) _events = [NSMutableArray array]; return self; }
- (BOOL)_hasListeners:(NSString *)event { return YES; }
- (void)fireEvent:(NSString *)event withObject:(NSDictionary *)data { [_events addObject:@{ @"event": event, @"data": data }]; }
@end
static NSUInteger downs(TiProxy *proxy) {
    return [[proxy.events filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"event == 'buttondown'"]] count];
}
static void press(GCController *controller, float value) {
    [controller.extendedGamepad.buttonA setValue:value];
    controller.extendedGamepad.valueChangedHandler(controller.extendedGamepad, controller.extendedGamepad.buttonA);
}
int main(void) { @autoreleasepool {
    GCController *controller = [GCController controllerWithExtendedGamepad];
    for (int order = 0; order < 2; order++) {
        TiProxy *menu = [TiProxy new], *game = [TiProxy new];
        CountingReceiver *first = [[CountingReceiver alloc] initWithViewProxy:menu];
        CountingReceiver *second = [[CountingReceiver alloc] initWithViewProxy:game];
        [first attachController:controller announce:NO];
        [second attachController:controller announce:NO];
        NSUInteger beforeFirst = first.dispatchCount, beforeSecond = second.dispatchCount;
        press(controller, 1);
        NSLog(@"Dispatch calls per input: first=%lu second=%lu", (unsigned long)(first.dispatchCount-beforeFirst), (unsigned long)(second.dispatchCount-beforeSecond));
        if (first.dispatchCount-beforeFirst != 1 || second.dispatchCount-beforeSecond != 1) { NSLog(@"FAIL redundant dispatch"); return 1; }
        if (downs(menu) != 1 || downs(game) != 1) { NSLog(@"FAIL live fanout"); return 1; }
        press(controller, 0);
        TGGamepadController *retired = order == 0 ? second : first;
        TGGamepadController *survivor = order == 0 ? first : second;
        TiProxy *remaining = order == 0 ? menu : game;
        TiProxy *closed = order == 0 ? game : menu;
        [retired shutdown];
        if (!controller.extendedGamepad.valueChangedHandler) { NSLog(@"FAIL closing one erased another"); return 1; }
        press(controller, 1);
        if (downs(remaining) != 2 || downs(closed) != 1) { NSLog(@"FAIL survivor/stale receiver"); return 1; }
        [survivor shutdown];
        if (controller.extendedGamepad.valueChangedHandler) { NSLog(@"FAIL last cleanup"); return 1; }
        [survivor attachController:controller announce:NO];
        if (controller.extendedGamepad.valueChangedHandler) { NSLog(@"FAIL shutdown reattached"); return 1; }
        [controller.extendedGamepad.buttonA setValue:0];
    }
    TiProxy *next = [TiProxy new];
    TGGamepadController *receiver = [[TGGamepadController alloc] initWithViewProxy:next];
    [receiver attachController:controller announce:NO];
    press(controller, 1);
    [controller.extendedGamepad.leftThumbstick setValueForXAxis:0.8f yAxis:0.5f];
    controller.extendedGamepad.valueChangedHandler(controller.extendedGamepad, controller.extendedGamepad.leftThumbstick);
    NSUInteger beforePending = [[next.events filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"event == 'stick'"]] count];
    [controller.extendedGamepad.leftThumbstick setValueForXAxis:0.9f yAxis:0.6f];
    controller.extendedGamepad.valueChangedHandler(controller.extendedGamepad, controller.extendedGamepad.leftThumbstick);
    if ([[next.events filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"event == 'stick'"]] count] != beforePending) { NSLog(@"FAIL analog update was not throttled before shutdown"); return 1; }
    [receiver shutdown];
    NSUInteger finalCount = next.events.count;
    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    if (next.events.count != finalCount || controller.extendedGamepad.valueChangedHandler) { NSLog(@"FAIL late input after shutdown"); return 1; }
    BOOL released = NO, rested = NO;
    for (NSDictionary *event in next.events) {
        if ([event[@"event"] isEqual:@"buttonup"]) released = YES;
        NSDictionary *data = event[@"data"];
        if ([event[@"event"] isEqual:@"stick"] && [data[@"x"] floatValue] == 0 && [data[@"y"] floatValue] == 0) rested = YES;
    }
    if (!released || !rested) { NSLog(@"FAIL held input release"); return 1; }
    // Three concurrent views, disconnect/reconnect and two independent pads.
    GCController *other = [GCController controllerWithExtendedGamepad];
    NSMutableArray *views = [NSMutableArray array], *proxies = [NSMutableArray array];
    for (int i=0;i<3;i++) {
        TiProxy *proxy=[TiProxy new];CountingReceiver *view=[[CountingReceiver alloc] initWithViewProxy:proxy];
        [views addObject:view];[proxies addObject:proxy];
        [view attachController:controller announce:NO];[view attachController:other announce:NO];
    }
    [controller.extendedGamepad.buttonA setValue:0];[other.extendedGamepad.buttonA setValue:0];
    press(controller,1);
    for (CountingReceiver *view in views) if(view.dispatchCount!=1){NSLog(@"FAIL three-view dispatch");return 1;}
    press(other,1);
    for (CountingReceiver *view in views) if(view.dispatchCount!=2){NSLog(@"FAIL second controller dispatch");return 1;}
    [[NSNotificationCenter defaultCenter] postNotificationName:GCControllerDidDisconnectNotification object:controller];
    if(controller.extendedGamepad.valueChangedHandler==nil && other.extendedGamepad.valueChangedHandler!=nil) {
        [[NSNotificationCenter defaultCenter] postNotificationName:GCControllerDidConnectNotification object:controller];
    } else {NSLog(@"FAIL disconnect isolation");return 1;}
    [controller.extendedGamepad.buttonA setValue:0];press(controller,1);
    for (CountingReceiver *view in views) if(view.dispatchCount!=3){NSLog(@"FAIL reconnect fanout");return 1;}
    for (TGGamepadController *view in views) [view shutdown];
    if(controller.extendedGamepad.valueChangedHandler || other.extendedGamepad.valueChangedHandler){NSLog(@"FAIL multi-controller cleanup");return 1;}
    NSLog(@"PASS: fanout, both close orders, recreate, last cleanup, shut-down attach, held release, delayed-input cleanup, three views, two pads and reconnect");
    return 0;
} }
