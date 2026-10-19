#import <UIKit/UIKit.h>
#import <XCTest/XCTest.h>
#import "TGInputResolver.h"
#import "TGCanvasInput.h"
@interface InputProxy : NSObject
@property TGInputResolver *inputResolver;
@property NSMutableArray *events;
@end
@implementation InputProxy
- (BOOL)_hasListeners:(NSString *)event {return YES;}
- (void)fireEvent:(NSString *)event withObject:(NSDictionary *)data {[_events addObject:@{@"event":event,@"data":data}];}
@end
@interface CanvasOwner : UIView { BOOL _renderingShutdown; }
@property InputProxy *proxy;
@end
@implementation CanvasOwner
PRODUCTION_METHODS
@end
@interface TestKey : UIKey
@property NSInteger usage;
@end
@implementation TestKey
- (UIKeyboardHIDUsage)keyCode {return self.usage;}
- (NSString *)characters {return @"w";}
- (UIKeyModifierFlags)modifierFlags {return UIKeyModifierShift;}
@end
@interface TestPress : UIPress
@property UIKey *testKey;
@end
@implementation TestPress
- (UIKey *)key {return self.testKey;}
@end
@interface TestTouch : UITouch
@property UIView *target;
@end
@implementation TestTouch
- (UIView *)view {return self.target;}
- (UITouchType)type {return UITouchTypeIndirectPointer;}
@end
@interface TestEvent : UIEvent
@property UIEventButtonMask mask;
@end
@implementation TestEvent
- (UIEventButtonMask)buttonMask {return self.mask;}
@end
@interface UIKitTests : XCTestCase
@end
@implementation UIKitTests
- (void)testKeyboardFocusRepeatCancellationAndNativeTextField
{
 UIWindow *window=UIApplication.sharedApplication.windows.firstObject;
 UIViewController *controller=window.rootViewController;
 CanvasOwner *canvas=[[CanvasOwner alloc] initWithFrame:CGRectMake(0,0,300,300)];
 InputProxy *proxy=[InputProxy new];proxy.events=[NSMutableArray array];canvas.proxy=proxy;
 NSMutableArray *actions=[NSMutableArray array];
 proxy.inputResolver=[[TGInputResolver alloc] initWithListener:^(NSString *action,NSString *context,BOOL down){[actions addObject:@(down)];}];
 [proxy.inputResolver setMap:@{@"gameplay":@{@"thrust":@[@{@"device":@"keyboard",@"code":@"KeyW"}]}}];
 [controller.view addSubview:canvas];[canvas focusInput];XCTAssertTrue(canvas.isFirstResponder);
 TestKey *key=[TestKey new];key.usage=26;TestPress *press=[TestPress new];press.testKey=key;NSSet *presses=[NSSet setWithObject:press];
 [canvas pressesBegan:presses withEvent:nil];[canvas pressesBegan:presses withEvent:nil];
 XCTAssertEqual(actions.count,1);XCTAssertEqual(proxy.events.count,1);
 XCTAssertEqualObjects(proxy.events.lastObject[@"data"][@"code"],@"KeyW");
 XCTAssertEqualObjects(proxy.events.lastObject[@"data"][@"modifiers"][@"shift"],@YES);
 UITextField *field=[[UITextField alloc] initWithFrame:CGRectMake(0,310,300,40)];[controller.view addSubview:field];[field becomeFirstResponder];
 XCTAssertTrue(field.isFirstResponder);XCTAssertFalse(canvas.isFirstResponder);XCTAssertEqualObjects(actions.lastObject,@NO);
 [canvas pressesBegan:presses withEvent:nil];XCTAssertEqual(actions.count,2);
 [field resignFirstResponder];[canvas focusInput];[canvas pressesBegan:presses withEvent:nil];XCTAssertEqual(actions.count,3);
 [canvas pressesCancelled:presses withEvent:nil];XCTAssertEqualObjects(actions.lastObject,@NO);
 [canvas removeFromSuperview];[field removeFromSuperview];
}
- (void)testPointerTransitionsCancelAndOverlayOwnership
{
 TGInputResolver *r=[[TGInputResolver alloc] initWithListener:^(NSString *a,NSString *c,BOOL down){}];
 UIView *canvas=[UIView new];UIButton *overlay=[UIButton buttonWithType:UIButtonTypeSystem];[canvas addSubview:overlay];
 TGCanvasInput *capture=[[TGCanvasInput alloc] initWithResolver:r];[canvas addGestureRecognizer:capture];
 TestTouch *touch=[TestTouch new];touch.target=canvas;
 XCTAssertTrue([capture gestureRecognizer:capture shouldReceiveTouch:touch]);
 touch.target=overlay;XCTAssertFalse([capture gestureRecognizer:capture shouldReceiveTouch:touch]);
 XCTAssertFalse(capture.cancelsTouchesInView);
 NSMutableArray *events=[NSMutableArray array];
 r=[[TGInputResolver alloc] initWithListener:^(NSString *a,NSString *c,BOOL down){[events addObject:@(down)];}];
 [r setMap:@{@"gameplay":@{@"fire":@[@{@"device":@"mouse",@"button":@"right"}]}}];
 capture=[[TGCanvasInput alloc] initWithResolver:r];[canvas addGestureRecognizer:capture];
 TestEvent *event=[TestEvent new];event.mask=UIEventButtonMaskSecondary;
 [capture touchesBegan:[NSSet setWithObject:touch] withEvent:event];XCTAssertEqualObjects(events.lastObject,@YES);
 [capture touchesCancelled:[NSSet setWithObject:touch] withEvent:event];XCTAssertEqualObjects(events.lastObject,@NO);
}
- (void)testNormalizedCodes
{
 XCTAssertEqualObjects(TGKeyboardCode(4),@"KeyA");XCTAssertEqualObjects(TGKeyboardCode(29),@"KeyZ");
 XCTAssertEqualObjects(TGKeyboardCode(44),@"Space");XCTAssertEqualObjects(TGKeyboardCode(82),@"ArrowUp");XCTAssertEqualObjects(TGKeyboardCode(41),@"Escape");
 XCTAssertNil(TGKeyboardCode(0));
}
@end
