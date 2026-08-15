//
//  ti.game — engine (iOS twin of android/src/ti/game/engine/PostEffect.java)
//
#import <Foundation/Foundation.h>
#import <OpenGLES/ES2/gl.h>

// Camera effect modes, mirroring PostEffect.NONE/TINT/GLITCH
enum { TGPostEffectNone = 0, TGPostEffectTint = 1, TGPostEffectGlitch = 2 };

/**
 * Fullscreen camera effects. When active, the renderer redirects the
 * whole scene into an offscreen framebuffer texture (begin), then this
 * class draws that texture to the screen through an effect shader
 * (finish) — one extra fullscreen pass, nothing else changes.
 *
 * Render thread only; all GL resources are recreated after context
 * loss via createGLResources.
 */
@interface TGPostEffect : NSObject

/** (Re)creates shaders and invalidates the FBO; call from surfaceCreated. */
- (void)createGLResources;

/**
 * Redirect rendering into the offscreen texture. Returns NO (and leaves
 * the screen framebuffer bound) if the FBO can't be set up — the caller
 * then renders directly, skipping the effect.
 */
- (BOOL)beginWithWidth:(int)width height:(int)height;

/** Draw the captured scene to the screen through the effect shader. */
- (void)finish:(int)mode
		 tintR:(float)tintR tintG:(float)tintG tintB:(float)tintB
	 intensity:(float)intensity time:(float)time;

@end
