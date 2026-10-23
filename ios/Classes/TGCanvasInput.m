#import "TGCanvasInput.h"
#import "TGInputResolver.h"
@implementation TGCanvasInput {
 TGInputResolver *_resolver;
}
- (instancetype)initWithResolver:(TGInputResolver *)resolver
{
 if (self=[super initWithTarget:nil action:nil]) {
  _resolver=resolver;self.delegate=self;self.cancelsTouchesInView=NO;self.delaysTouchesBegan=NO;self.delaysTouchesEnded=NO;
  if (@available(iOS 13.4,*)) self.allowedTouchTypes=@[@(UITouchTypeIndirectPointer)];
  else self.enabled=NO;
 }
 return self;
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldReceiveTouch:(UITouch *)touch
{
 // UIKit controls above the canvas retain their click and focus behavior.
 if (@available(iOS 13.4,*)) return touch.type==UITouchTypeIndirectPointer && touch.view==self.view;
 return NO;
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)a shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)b { return YES; }
- (void)update:(UIEvent *)event
{
 if (@available(iOS 13.4,*)) {
  UIEventButtonMask mask=event.buttonMask;
  [_resolver transition:@"mouse" identity:@"pointer" code:@"left" down:(mask & UIEventButtonMaskPrimary)!=0];
  [_resolver transition:@"mouse" identity:@"pointer" code:@"right" down:(mask & UIEventButtonMaskSecondary)!=0];
  [_resolver transition:@"mouse" identity:@"pointer" code:@"middle" down:(mask & (1<<2))!=0];
 }
}
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { [self update:event];self.state=self.state==UIGestureRecognizerStatePossible?UIGestureRecognizerStateBegan:UIGestureRecognizerStateChanged; }
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { [self update:event];self.state=UIGestureRecognizerStateChanged; }
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { [self update:event];
 if (@available(iOS 13.4,*)) self.state=event.buttonMask?UIGestureRecognizerStateChanged:UIGestureRecognizerStateEnded; }
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { [_resolver releaseDevice:@"mouse" identity:@"pointer"];self.state=UIGestureRecognizerStateCancelled; }
@end
NSString *TGKeyboardCode(NSInteger usage)
{
 if (usage>=4 && usage<=29) return [NSString stringWithFormat:@"Key%c",(int)('A'+usage-4)];
 if (usage>=30 && usage<=38) return [NSString stringWithFormat:@"Digit%ld",(long)(usage-29)];
 if (usage==39) return @"Digit0";
 if (usage>=58 && usage<=69) return [NSString stringWithFormat:@"F%ld",(long)(usage-57)];
 switch(usage) {
  case 40:return @"Enter";case 41:return @"Escape";case 42:return @"Backspace";case 43:return @"Tab";case 44:return @"Space";
  case 74:return @"Home";case 75:return @"PageUp";case 76:return @"Delete";case 77:return @"End";case 78:return @"PageDown";
  case 79:return @"ArrowRight";case 80:return @"ArrowLeft";case 81:return @"ArrowDown";case 82:return @"ArrowUp";
  case 224:return @"ControlLeft";case 225:return @"ShiftLeft";case 226:return @"AltLeft";case 227:return @"MetaLeft";
  case 228:return @"ControlRight";case 229:return @"ShiftRight";case 230:return @"AltRight";case 231:return @"MetaRight";
  default:return nil;
 }
}
