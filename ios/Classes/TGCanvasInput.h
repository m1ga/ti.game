#import <UIKit/UIKit.h>
@class TGInputResolver;
/** Canvas-only pointer recognizer. Does not cancel native overlay touches. */
@interface TGCanvasInput : UIGestureRecognizer <UIGestureRecognizerDelegate>
- (instancetype)initWithResolver:(TGInputResolver *)resolver;
@end
NSString *TGKeyboardCode(NSInteger usage);
