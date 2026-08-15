//
//  ti.game — engine (iOS twin of android/src/ti/game/engine/Tween.java)
//
#import <Foundation/Foundation.h>

@class TGSprite;

/**
 * Native property tween, ticked by the render loop. This exists because JS
 * can't animate per-frame across the bridge — sprite.animate({...}) creates
 * one of these and the sprite fires a 'complete' event when it finishes.
 */
@interface TGTween : NSObject

// Target values; nil = property not animated
@property (nonatomic, strong) NSNumber *toX;
@property (nonatomic, strong) NSNumber *toY;
@property (nonatomic, strong) NSNumber *toScaleX;
@property (nonatomic, strong) NSNumber *toScaleY;
@property (nonatomic, strong) NSNumber *toRotation;
@property (nonatomic, strong) NSNumber *toOpacity;
@property (nonatomic, strong) NSNumber *toGlowOpacity;
@property (nonatomic, assign) float duration; // seconds
@property (nonatomic, assign) float delay;
@property (nonatomic, copy) NSString *easing;

- (void)captureStartValues:(TGSprite *)sprite;

/** Advances the tween; returns YES when finished. Called on the render thread. */
- (BOOL)update:(TGSprite *)sprite delta:(float)dt;

@end
