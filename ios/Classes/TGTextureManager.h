//
//  ti.game — engine (iOS twin of android/src/ti/game/engine/TextureManager.java)
//
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <OpenGLES/ES2/gl.h>

@class TGSpriteSheet;

/**
 * Owns GL texture objects. All methods must be called from the render
 * thread. Tracks the sheets it has uploaded so they can be invalidated
 * together if the GL context is ever recreated (rare on iOS, but the code
 * path is kept identical to Android).
 */
@interface TGTextureManager : NSObject

/** Lazily-created 1x1 white texture for untextured shapes (debug overlays). */
- (GLuint)whiteTexture;

/** Uploads an image (premultiplied RGBA) and returns the GL texture id.
 *  smoothing=NO uses GL_NEAREST for crisp pixel-art scaling; repeat=YES
 *  uses GL_REPEAT wrap (power-of-two dimensions on ES 2.0). */
- (GLuint)upload:(UIImage *)image smoothing:(BOOL)smoothing repeat:(BOOL)repeat;

- (void)track:(TGSpriteSheet *)sheet;

/** After context recreation: forget every texture so sheets re-upload lazily. */
- (void)invalidateAll;

@end
