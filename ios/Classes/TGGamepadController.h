//
//  ti.game — engine (iOS twin of android/src/ti/game/engine/GamepadController.java)
//
#import <Foundation/Foundation.h>

@class TiProxy;

/**
 * Game controller input (Bluetooth MFi/Xbox/PlayStation/Stadia pads via
 * GameController.framework). Runs on the main thread and turns raw
 * element changes into a handful of discrete, named events on the game
 * view:
 *
 *   gamepadconnected / gamepaddisconnected  { gamepad, name }
 *   buttondown / buttonup   { button, gamepad, input, keyCode }
 *   stick                   { stick: 'left'|'right', x, y, gamepad }
 *   trigger                 { trigger: 'l2'|'r2', value, gamepad }
 *
 * Button names are normalized across controllers: a b x y l1 r1 l2 r2
 * l3 r3 start select home up down left right. The d-pad reaches JS as
 * up/down/left/right buttons, and the left stick fires the same four
 * names (input 'leftstick') once it is pushed past half way — so a
 * single 'buttondown' handler can drive a game without caring which
 * control the player used. Analog values go out as 'stick'/'trigger'
 * events, throttled to ~20 Hz per channel while they change, always
 * ending with the rest value. Stick y follows the engine's y-down
 * convention (-1 = up), like Android.
 */
@interface TGGamepadController : NSObject

- (instancetype)initWithViewProxy:(TiProxy *)viewProxy;

/** Radial dead zone applied to both sticks (0..0.9, default 0.2). */
@property (atomic, assign) float deadzone;

// Left-stick deflection that presses a direction button, and the lower
// value that releases it again (hysteresis). Twin of setStickThresholds.
@property (atomic, assign) float stickPress;
@property (atomic, assign) float stickRelease;

/** Any thread. Stops listening; held buttons are released to JS. */
- (void)shutdown;

/** Main thread. Fires buttonup for everything held. */
- (void)releaseAll;

/** Connected game controllers as [{ id, name }]. */
+ (NSArray<NSDictionary *> *)connectedGamepads;

/** Snapshot of the most recently used pad (nil if none was used yet). */
- (NSDictionary *)snapshot;

@end
