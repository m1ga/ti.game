//
//  ti.game — engine (iOS twin of android/src/ti/game/engine/DebugHud.java)
//
#import <Foundation/Foundation.h>
#import <OpenGLES/ES2/gl.h>
#import "TGFrameStats.h"

@class TGSpriteBatch;

/**
 * The on-screen performance HUD: a compact line that expands into the full
 * set of counters when tapped. Draws through TGScreenOverlay's screen-space
 * pass, so it stays pinned to its corner whatever the camera does, and
 * through TGSegmentFont, so it needs no font atlas.
 *
 * Configured from JS as GameView.debug = { hud: 'topRight' }.
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
surfaceWidth:(float)surfaceWidth
surfaceHeight:(float)surfaceHeight
 screenScale:(float)screenScale;

@end
