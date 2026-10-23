#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

/** Immutable shared device, library and pipelines. Mutable frame state belongs to each view. */
@interface TGMetalContext : NSObject
@property(nonatomic, readonly) id<MTLDevice> device;
+ (instancetype)sharedContext;
- (id<MTLRenderPipelineState>)spritePipelineWithBlend:(NSInteger)blend silhouette:(BOOL)silhouette;
- (id<MTLRenderPipelineState>)effectPipeline:(NSInteger)mode;
- (id<MTLSamplerState>)samplerWithSmoothing:(BOOL)smoothing repeat:(BOOL)repeat;
@end

/** Strong texture + sampler reference; retained by encoded command buffers until GPU completion. */
@interface TGMetalTexture : NSObject
@property(nonatomic, readonly) id<MTLTexture> texture;
@property(nonatomic, readonly) id<MTLSamplerState> sampler;
- (instancetype)initWithTexture:(id<MTLTexture>)texture sampler:(id<MTLSamplerState>)sampler;
@end
