//
//  ti.game — engine (iOS twin of android/src/ti/game/engine/TextureManager.java)
//
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "TGMetalContext.h"

@class TGSpriteSheet;

/** Render-thread texture upload and sheet tracking. Sheets publish strong native
 * references shared by views on the same device. Closing one manager does not
 * invalidate a sheet owned by another view; commands retain their GPU resources. */
@interface TGTextureManager : NSObject

/** Lazily-created 1x1 white texture for untextured shapes (debug overlays). */
- (instancetype)initWithContext:(TGMetalContext *)context;
- (TGMetalTexture *)whiteTexture;

/** Uploads an image (premultiplied RGBA) and returns a texture/sampler reference.
 *  smoothing=NO uses nearest filtering; repeat=YES uses repeat addressing. */
- (TGMetalTexture *)upload:(UIImage *)image smoothing:(BOOL)smoothing repeat:(BOOL)repeat;

- (void)track:(TGSpriteSheet *)sheet;

/** Releases tracking for textures of sheets disposed since the last frame. */
- (void)deleteDisposed;

@end
