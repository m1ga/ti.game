//
//  ti.game — engine (iOS twin of android/src/ti/game/engine/Easing.java)
//
#import <Foundation/Foundation.h>

extern NSString *const TGEasingLinear;
extern NSString *const TGEasingEaseIn;
extern NSString *const TGEasingEaseOut;
extern NSString *const TGEasingEaseInOut;
extern NSString *const TGEasingBounce;
extern NSString *const TGEasingElastic;

/** Easing functions for native tweens. Input/output t in [0, 1]. */
float TGEasingApply(NSString *name, float t);
