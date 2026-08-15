//
//  ti.game — engine (iOS twin of android/src/ti/game/engine/TouchController.java)
//
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@class TGScene;
@class TiProxy;

/**
 * Runs on the main thread and drives all interaction natively: hit-testing,
 * drag and drop, pinch-to-scale and two-finger rotation. JS only receives
 * high-level events (tap, dragstart, throttled drag, dragend, pinch,
 * rotate) — never per-frame move traffic.
 *
 * Touch positions are converted from view points to surface pixels
 * (x contentScale), so they map 1:1 onto the scene's coordinate system —
 * exactly like Android, where both are in the same pixel space.
 */
@interface TGTouchController : NSObject

- (instancetype)initWithScene:(TGScene *)scene
					viewProxy:(TiProxy *)viewProxy
				 contentScale:(CGFloat)contentScale;

// Forwarded by the game view (which does NOT call TiUIView's own touch
// handling — the engine owns all touches, like the registerForTouch
// override on Android).
- (void)touchesBegan:(NSSet<UITouch *> *)touches inView:(UIView *)view;
- (void)touchesMoved:(NSSet<UITouch *> *)touches inView:(UIView *)view;
- (void)touchesEnded:(NSSet<UITouch *> *)touches inView:(UIView *)view;
- (void)touchesCancelled:(NSSet<UITouch *> *)touches inView:(UIView *)view;

@end
