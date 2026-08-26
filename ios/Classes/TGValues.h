#import <Foundation/Foundation.h>

/**
 Names and percentages for properties whose bare number reads like a riddle.

 The engine already does this where it matters: `blend`, `hitboxShape`,
 `tintColor` and `glowColor` all take strings. The numeric properties are simply
 the ones that never got the same treatment.

 Everything here is additive: a number keeps working exactly as before, and a
 value that cannot be understood falls back to what the caller passed rather
 than throwing, so a typo degrades to the current value instead of taking the
 app down mid-frame.
 */
@interface TGValues : NSObject

/** A ratio, as a number or as a percentage string: 0.5 and @"50%" are equal. */
+ (float)ratio:(id)value fallback:(float)fallback;

/** The horizontal anchor, as a number or `left`, `center`, `right`. */
+ (float)anchorX:(id)value fallback:(float)fallback;

/** The vertical anchor, as a number or `top`, `middle`, `bottom`. */
+ (float)anchorY:(id)value fallback:(float)fallback;

/**
 Both axes at once: `anchor: "bottom-left"`. Accepts the nine corners and edges
 in either order. Returns NO when the value is not a recognised preset, which is
 the caller's cue to leave the anchors alone.
 */
+ (BOOL)anchor:(id)value x:(float *)x y:(float *)y;

/** The preset a pair of anchors sits on, or `custom`. */
+ (NSString *)anchorNameForX:(float)x y:(float)y;

@end
