#import "TGPostEffect.h"
#import <simd/simd.h>

@implementation TGPostEffect {
	TGMetalContext *_context;
}
- (instancetype)initWithContext:(TGMetalContext *)context
{
	if (self = [super init]) _context = context;
	return self;
}
- (BOOL)beginWithWidth:(int)width height:(int)height
{
	if (width <= 0 || height <= 0) return NO;
	if (_target.width == width && _target.height == height) return YES;
	MTLTextureDescriptor *d = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:width height:height mipmapped:NO];
	d.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
	d.storageMode = MTLStorageModePrivate;
	_target = [_context.device newTextureWithDescriptor:d];
	if (!_target) NSLog(@"[WARN] ti.game: Metal camera effect texture allocation failed; drawing without effect");
	return _target != nil;
}
- (void)finish:(int)mode tintR:(float)tintR tintG:(float)tintG tintB:(float)tintB
    intensity:(float)intensity time:(float)time encoder:(id<MTLRenderCommandEncoder>)encoder
{
	struct { vector_float4 tint; float intensity; float time; } uniforms = {
		{tintR,tintG,tintB,1}, MAX(0.0f,MIN(1.0f,intensity)), time
	};
	[encoder setRenderPipelineState:[_context effectPipeline:mode]];
	[encoder setFragmentTexture:_target atIndex:0];
	[encoder setFragmentSamplerState:[_context samplerWithSmoothing:YES repeat:NO] atIndex:0];
	[encoder setFragmentBytes:&uniforms length:sizeof(uniforms) atIndex:0];
	[encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
}
@end
