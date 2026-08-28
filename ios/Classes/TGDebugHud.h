//
//  ti.game — engine (iOS twin of android/src/ti/game/engine/DebugHud.java)
//
#import <Foundation/Foundation.h>
#import <OpenGLES/ES2/gl.h>
#import "TGFrameStats.h"

@class TGBitmapFont;
@class TGSpriteBatch;

/**
 * The on-screen performance HUD: a compact line that expands into the full
 * set of counters when tapped. Drawn in the batcher's screen-space mode —
 * the same one screenFixed sprites use — so it stays pinned to its corner
 * whatever the camera does, and laid out straight into the batch as glyph
 * quads, without a TGTextSprite or a place in the scene.
 *
 * Configured from JS as GameView.debug = { hud: 'topRight' }, optionally
 * with { hudFont: myFont } to print it in the game's own typeface. With no
 * font of its own it borrows the scene's built-in pixel font — the same one
 * createText() falls back to — so the HUD costs no extra texture.
 *
 * The text is rebuilt once per second, when a TGFrameStats window closes —
 * drawing it every frame only replays cached strings.
 *
 * Two rows the Android twin does not have: present time and present
 * failures, which only this platform can measure. See TGFrameStats.
 */
@interface TGDebugHud : NSObject

/** HUD visible at all. */
@property (atomic, assign) BOOL enabled;

/** One of the TGOverlayCorner values. */
@property (atomic, assign) int corner;

/** Set from JS via debug: { hudFont: ... }; nil borrows the scene's. */
@property (atomic, strong) TGBitmapFont *font;

/** Tapping the panel swaps between the compact line and the full set. */
- (void)toggleExpanded;
- (BOOL)isExpanded;

/** Main thread: is this surface-pixel point on the panel? */
- (BOOL)hitTestX:(float)surfaceX y:(float)surfaceY;

/** Called when a TGFrameStats window closes — once a second. */
- (void)update:(TGFrameStatsSnapshot)snapshot;

/**
 * Draws the panel in surface pixels. Call inside the screen-space pass,
 * after the post-effect. `screenScale` is the drawable's content scale, so
 * the HUD reads the same size at 1x and on a 3x Retina drawable.
 */
- (void)draw:(TGSpriteBatch *)batch
	 texture:(GLuint)whiteTexture
		font:(TGBitmapFont *)hudFont
surfaceWidth:(float)surfaceWidth
surfaceHeight:(float)surfaceHeight
 screenScale:(float)screenScale;

@end
