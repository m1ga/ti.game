#import "TGMetalContext.h"
enum { TGPostEffectNone = 0, TGPostEffectTint = 1, TGPostEffectGlitch = 2 };

/** Per-view offscreen surface. Queue ordering protects reuse across frames. */
@interface TGPostEffect : NSObject
@property (nonatomic, readonly) id<MTLTexture> target;
- (instancetype)initWithContext:(TGMetalContext *)context;
- (BOOL)beginWithWidth:(int)width height:(int)height;
- (void)finish:(int)mode tintR:(float)tintR tintG:(float)tintG tintB:(float)tintB
    intensity:(float)intensity time:(float)time encoder:(id<MTLRenderCommandEncoder>)encoder;
@end
