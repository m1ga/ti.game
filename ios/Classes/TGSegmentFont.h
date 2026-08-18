//
//  ti.game — engine (iOS twin of android/src/ti/game/engine/SegmentFont.java)
//
#import <Foundation/Foundation.h>
#import <OpenGLES/ES2/gl.h>

@class TGSpriteBatch;

/**
 * Seven-segment glyphs drawn with the batcher's line primitive and the
 * TGTextureManager's 1x1 white texture — no font atlas, no GL resources of
 * its own, nothing to recreate after context loss. Enough to label and
 * print the debug HUD's numbers until the bitmap font lands; when it does,
 * the HUD swaps its text renderer without touching the public API.
 *
 * Seven segments cannot draw every letter (no M, K, V, W, X, Z), so HUD
 * labels are picked from what this table can render. Undrawable characters
 * render blank rather than throwing.
 *
 * Monospaced on purpose: a proportional HUD makes numbers jitter sideways
 * as they change. Render thread only, like everything that touches the batch.
 */
@interface TGSegmentFont : NSObject

/** Distance from one glyph's left edge to the next one's. */
+ (float)advance:(float)glyphHeight;

/** Width of `text` without the trailing gap — for layout and hit rects. */
+ (float)measure:(NSString *)text glyphHeight:(float)glyphHeight;

/**
 * Draws `text` with its top-left corner at (x, y), in surface pixels.
 * Color is straight-alpha, like TGSpriteBatch's drawLine.
 */
+ (void)draw:(TGSpriteBatch *)batch
	 texture:(GLuint)whiteTexture
		text:(NSString *)text
		   x:(float)x
		   y:(float)y
 glyphHeight:(float)glyphHeight
		   r:(float)r g:(float)g b:(float)b a:(float)a;

@end
