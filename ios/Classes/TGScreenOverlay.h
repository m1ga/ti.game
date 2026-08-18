//
//  ti.game — engine (iOS twin of android/src/ti/game/engine/ScreenOverlay.java)
//
#import <Foundation/Foundation.h>

// Screen-space anchor corners, mirroring ScreenOverlay.TOP_LEFT/...
enum {
	TGOverlayCornerTopLeft = 0,
	TGOverlayCornerTopRight = 1,
	TGOverlayCornerBottomLeft = 2,
	TGOverlayCornerBottomRight = 3
};

/**
 * The screen-space drawing pass. The scene's projection follows the camera
 * (position, zoom, shake), so anything pinned to a corner would drift with
 * the world; this holds the second projection — plain surface pixels,
 * top-left origin — plus the corner anchoring every screen-space element
 * needs.
 *
 * The pass runs after the post-effect, not inside it: the glitch shader
 * would otherwise smear exactly the numbers you turned the HUD on to read.
 *
 * Nothing here owns GL resources, so there is nothing to recreate after
 * context loss. The debug HUD is its first client; bitmap text pinned to
 * the screen and the virtual joystick want the same two halves (draw in
 * surface pixels, hit-test in surface pixels) and should hang here too.
 */
@interface TGScreenOverlay : NSObject

/** Recomputed whenever the drawable resizes. */
- (void)surfaceChangedWithWidth:(int)width height:(int)height;

/** Orthographic surface-pixel projection; feed it to TGSpriteBatch begin. */
- (const float *)projection;

+ (int)cornerFromName:(NSString *)name fallback:(int)fallback;
+ (NSString *)cornerName:(int)corner;

/**
 * Top-left corner of a content box of the given size, anchored in
 * `corner` with `margin` px of breathing room. Result goes into
 * out[0] = x, out[1] = y.
 */
+ (void)resolveOrigin:(int)corner
		 contentWidth:(float)contentWidth
		contentHeight:(float)contentHeight
		 surfaceWidth:(float)surfaceWidth
		surfaceHeight:(float)surfaceHeight
			   margin:(float)margin
				  out:(float *)out;

@end
