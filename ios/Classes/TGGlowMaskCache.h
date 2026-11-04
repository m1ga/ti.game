//
//  ti.game — engine (iOS twin of android/src/ti/game/engine/GlowMaskCache.java)
//
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import "TGMetalContext.h"
#import "TGSpriteSheet.h"

@class TGSpriteBatch;

/** Gaussian sigma per px of glowBlur: the halo fades over ~2 sigma. */
extern const float TGGlowSigmaPerBlur;
/** Mask padding past the sprite rect, in sigmas (tail below 1%). */
extern const float TGGlowPadSigmas;

/** Sigma in sprite-local units for a glowBlur in px on an axis scaled by
 *  `scale` — the blur stays isotropic on screen. */
float TGGlowLocalSigma(float blur, float scale);

/** What gets blurred: a sheet rect at a draw size, or a text layout. The
 *  cache reuses one mutable instance for lookups; NSCopying makes it a
 *  dictionary key. Compared by sheet/layout identity and exact floats. */
@interface TGGlowSilhouette : NSObject <NSCopying>
@property (nonatomic, strong) TGSpriteSheet *sheet;
@property (nonatomic, strong) id layout; // TGTextLayout, nil for a frame
@property (nonatomic) float u0, v0, u1, v1, w, h;
@end

/** A built mask: texture covering the sprite rect plus padX/padY
 *  (sprite-local units) on each side; texture nil = build failed. */
@interface TGGlowMaskEntry : NSObject
@property (nonatomic, strong) TGMetalTexture *texture;
@property (nonatomic) float sigmaX, sigmaY;
@property (nonatomic) float padX, padY;
@property (nonatomic) int lastUsed;
@end

/**
 * Blurred silhouette masks for sprite glows. A glow is the sprite's alpha
 * silhouette, Gaussian-blurred by glowBlur and tinted, drawn behind the
 * sprite. Blurring per frame would be too slow, so the mask is rendered
 * once into a small offscreen texture and cached by silhouette (sheet +
 * UV rect + draw size, or a text layout) and blur radius; the batcher then
 * draws one textured quad per glow per frame.
 *
 * Build: the silhouette is drawn at 1:1 into a render target padded by
 * 2.5 sigma on every side, halved (box filter) until the sigma is at most
 * 1.5 texels per axis, then blurred with a separable 9-tap Gaussian. The
 * mask is stored premultiplied white (rgb = a), so the silhouette pipeline
 * (color * alpha) composites it with the glow color. Bilinear upsampling
 * of the low-resolution mask is what makes the halo smooth at any radius.
 *
 * Builds are encoded between frames (beginFrame, before the scene's
 * render pass, in the same command buffer), a few per frame at most; a
 * miss draws the nearest cached radius of the same silhouette for that
 * frame, or nothing. Entries idle for a few seconds are released; already
 * encoded commands retain their textures. Render thread only.
 */
@interface TGGlowMaskCache : NSObject
- (instancetype)initWithContext:(TGMetalContext *)context;

/** The mask for this silhouette at these sigmas (sprite-local units), or
 *  nil to draw no glow this frame. A miss queues a build for the next
 *  beginFrame and returns the nearest cached radius meanwhile. */
- (TGGlowMaskEntry *)lookupSheet:(TGSpriteSheet *)sheet layout:(id)layout
							  u0:(float)u0 v0:(float)v0 u1:(float)u1 v1:(float)v1
							   w:(float)w h:(float)h
						  sigmaX:(float)sigmaX sigmaY:(float)sigmaY;

/** Encodes queued builds (a few per frame) and frees idle masks. Call
 *  before the frame's scene encoder is created; the batch's frame slot
 *  must already be reset (beginFrameWithEncoder:slot:). */
- (void)beginFrame:(TGSpriteBatch *)batch commandBuffer:(id<MTLCommandBuffer>)command;
@end
