#import "TGMetalContext.h"

// Embedded source makes module archives independent of the consuming app's default.metallib.
static NSString *const TGShaderSource =
	@
"#include <metal_stdlib>\n"
	 "using namespace metal;\n"
	 "struct Vertex { packed_float2 pos; packed_float2 uv; packed_float4 color; };\n"
	 "struct Out { float4 pos [[position]]; float2 uv; float4 color; };\n"
	 "vertex Out spriteVertex(const device Vertex *v [[buffer(0)]], constant float4x4 &p [[buffer(1)]], uint "
	 "i [[vertex_id]]) {\n"
	 " Out o; o.pos=p*float4(float2(v[i].pos),0,1); o.pos.z=(o.pos.z+o.pos.w)*0.5; o.uv=float2(v[i].uv); "
	 "o.color=float4(v[i].color); return o; }\n"
	 "fragment float4 spriteFragment(Out i [[stage_in]], texture2d<float> t [[texture(0)]], sampler s "
	 "[[sampler(0)]]) { return t.sample(s,i.uv)*i.color; }\n"
	 "fragment float4 silhouetteFragment(Out i [[stage_in]], texture2d<float> t [[texture(0)]], sampler s "
	 "[[sampler(0)]]) { return t.sample(s,i.uv).a*i.color; }\n"
	 "struct Effect { float4 tint; float intensity; float time; };\n"
	 "vertex Out effectVertex(uint i [[vertex_id]]) {\n"
	 " const float2 pos[4]={float2(-1,-1),float2(1,-1),float2(-1,1),float2(1,1)};\n"
	 " Out o; o.pos=float4(pos[i],0,1); o.uv=float2((pos[i].x+1)*0.5,(1-pos[i].y)*0.5); o.color=1;return "
	 "o;}\n"
	 "fragment float4 tintFragment(Out i [[stage_in]], texture2d<float> t [[texture(0)]], sampler s "
	 "[[sampler(0)]], constant Effect &e [[buffer(0)]]) {\n"
	 " float4 c=t.sample(s,i.uv);return float4(mix(c.rgb,c.rgb*e.tint.rgb,e.intensity),c.a); }\n"
	 "float rnd(float2 c){return fract(sin(dot(c,float2(12.9898,78.233)))*43758.5453);}\n"
	 "fragment float4 glitchFragment(Out i [[stage_in]], texture2d<float> t [[texture(0)]], sampler s "
	 "[[sampler(0)]], constant Effect &e [[buffer(0)]]) {\n"
	 // Legacy FBO UVs were bottom-up. Preserve the effect's band/noise orientation separately from Metal
	 // texture UVs.
	 " float2 uv=float2(i.uv.x,1-i.uv.y);float jump=floor(e.time*12);float band=floor(uv.y*24);float "
	 "r=rnd(float2(band,jump));\n"
	 " float shift=(r-.5)*step(1-e.intensity*.5,r)*.2*e.intensity;uv.x=fract(uv.x+shift);\n"
	 " float split=.006*e.intensity*(.5+.5*sin(e.time*40));\n"
	 " float4 c; c.r=t.sample(s,float2(fract(uv.x+split),1-uv.y)).r;c.g=t.sample(s,float2(uv.x,1-uv.y)).g;\n"
	 " c.b=t.sample(s,float2(fract(uv.x-split),1-uv.y)).b;c.a=t.sample(s,float2(uv.x,1-uv.y)).a;\n"
	 " c.rgb*=1-.15*e.intensity*rnd(float2(floor(uv.y*120),jump));return c;}\n";

@implementation TGMetalContext
{
	id<MTLLibrary> _library;
	id<MTLRenderPipelineState> _sprites[2][4];
	id<MTLRenderPipelineState> _effects[2];
	id<MTLSamplerState> _samplers[2][2];
}
+ (instancetype)sharedContext
{
	static TGMetalContext *context;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
	  context = [[self alloc] init];
	});
	return context;
}
- (instancetype)init
{
	if (!(self = [super init]))
		return nil;
	_device = MTLCreateSystemDefaultDevice();
	NSError *error = nil;
	MTLCompileOptions *options = [MTLCompileOptions new];
	options.languageVersion = MTLLanguageVersion2_0;
	_library = [_device newLibraryWithSource:TGShaderSource options:options error:&error];
	if (!_library)
	{
		NSLog(@"[ERROR] ti.game: Metal device/library unavailable: %@", error);
		return nil;
	}
	for (int silhouette = 0; silhouette < 2; silhouette++)
	{
		for (int blend = 0; blend < 4; blend++)
		{
			MTLRenderPipelineDescriptor *p = [MTLRenderPipelineDescriptor new];
			p.vertexFunction = [_library newFunctionWithName:@"spriteVertex"];
			p.fragmentFunction =
				[_library newFunctionWithName:silhouette ? @"silhouetteFragment" : @"spriteFragment"];
			MTLRenderPipelineColorAttachmentDescriptor *a = p.colorAttachments[0];
			a.pixelFormat = MTLPixelFormatBGRA8Unorm;
			a.blendingEnabled = YES;
			a.sourceRGBBlendFactor = (blend == 2) ? MTLBlendFactorDestinationColor : MTLBlendFactorOne;
			a.destinationRGBBlendFactor = (blend == 1)	 ? MTLBlendFactorOne
										  : (blend == 3) ? MTLBlendFactorOneMinusSourceColor
														 : MTLBlendFactorOneMinusSourceAlpha;
			// glBlendFunc applied the same factors to RGB and alpha.
			a.sourceAlphaBlendFactor = (blend == 2) ? MTLBlendFactorDestinationAlpha : MTLBlendFactorOne;
			a.destinationAlphaBlendFactor =
				(blend == 1) ? MTLBlendFactorOne : MTLBlendFactorOneMinusSourceAlpha;
			_sprites[silhouette][blend] = [_device newRenderPipelineStateWithDescriptor:p error:&error];
			if (!_sprites[silhouette][blend])
			{
				NSLog(@"[ERROR] ti.game: Metal sprite pipeline: %@", error);
				return nil;
			}
		}
	}
	for (int effect = 0; effect < 2; effect++)
	{
		MTLRenderPipelineDescriptor *p = [MTLRenderPipelineDescriptor new];
		p.vertexFunction = [_library newFunctionWithName:@"effectVertex"];
		p.fragmentFunction = [_library newFunctionWithName:effect ? @"glitchFragment" : @"tintFragment"];
		p.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
		_effects[effect] = [_device newRenderPipelineStateWithDescriptor:p error:&error];
		if (!_effects[effect])
		{
			NSLog(@"[ERROR] ti.game: Metal effect pipeline: %@", error);
			return nil;
		}
	}
	for (int smoothing = 0; smoothing < 2; smoothing++)
	{
		for (int repeat = 0; repeat < 2; repeat++)
		{
			MTLSamplerDescriptor *s = [MTLSamplerDescriptor new];
			s.minFilter = s.magFilter =
				smoothing ? MTLSamplerMinMagFilterLinear : MTLSamplerMinMagFilterNearest;
			s.sAddressMode = s.tAddressMode =
				repeat ? MTLSamplerAddressModeRepeat : MTLSamplerAddressModeClampToEdge;
			_samplers[smoothing][repeat] = [_device newSamplerStateWithDescriptor:s];
		}
	}
	return self;
}
- (id<MTLRenderPipelineState>)spritePipelineWithBlend:(NSInteger)blend silhouette:(BOOL)silhouette
{
	return _sprites[silhouette ? 1 : 0][(blend >= 0 && blend <= 3) ? blend : 0];
}
- (id<MTLRenderPipelineState>)effectPipeline:(NSInteger)mode
{
	return _effects[mode == 2 ? 1 : 0];
}
- (id<MTLSamplerState>)samplerWithSmoothing:(BOOL)smoothing repeat:(BOOL)repeat
{
	return _samplers[smoothing ? 1 : 0][repeat ? 1 : 0];
}
@end
@implementation TGMetalTexture
- (instancetype)initWithTexture:(id<MTLTexture>)texture sampler:(id<MTLSamplerState>)sampler
{
	if (self = [super init])
	{
		_texture = texture;
		_sampler = sampler;
	}
	return self;
}
@end
