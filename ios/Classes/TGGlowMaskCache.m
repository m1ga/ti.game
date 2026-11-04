#import "TGGlowMaskCache.h"
#import "TGSpriteBatch.h"
#import <float.h>
#import <math.h>
#import <simd/simd.h>
#import <string.h>

const float TGGlowSigmaPerBlur = 0.5f;
const float TGGlowPadSigmas = 2.5f;
// Alpha gain on the blurred coverage: a plain blur is only half opaque at
// the sprite edge, which reads as a faint shadow instead of a halo.
static const float kGain = 2.5f;
static const float kMaxLowSigma = 1.5f;
static const int kMaxFullRes = 2048;
static const int kMaxEntries = 64;
static const int kMaxPending = 64;
static const int kBuildsPerFrame = 4;
static const int kIdleFrames = 180;
static const int kSweepInterval = 60;
// Radii are quantized in 12% steps so a scale tween builds a handful of
// masks, not one per frame
static const double kSigmaStep = 0.11332868530700317; // log(1.12)
static const float kMinSigma = 0.25f;
static const float kMaxSigma = 512.0f;

float TGGlowLocalSigma(float blur, float scale)
{
	float s = MAX(fabsf(scale), 0.001f);
	return blur * TGGlowSigmaPerBlur / s;
}

static float quantize(float sigma)
{
	sigma = MAX(kMinSigma, MIN(kMaxSigma, sigma));
	return (float)exp(round(log(sigma) / kSigmaStep) * kSigmaStep);
}

static int levels(float sigma)
{
	if (sigma <= kMaxLowSigma) {
		return 0;
	}
	return (int)ceil(log(sigma / kMaxLowSigma) / log(2.0));
}

static int ceilDiv(int a, int b)
{
	return (a + b - 1) / b;
}

typedef struct {
	vector_float2 step;
	float gain;
	float w0, w1, w2, w3, w4;
} TGGlowBlurUniforms;

@implementation TGGlowSilhouette

- (id)copyWithZone:(NSZone *)zone
{
	TGGlowSilhouette *c = [[TGGlowSilhouette allocWithZone:zone] init];
	c.sheet = _sheet;
	c.layout = _layout;
	c.u0 = _u0;
	c.v0 = _v0;
	c.u1 = _u1;
	c.v1 = _v1;
	c.w = _w;
	c.h = _h;
	return c;
}

- (BOOL)isEqual:(id)object
{
	if (![object isKindOfClass:[TGGlowSilhouette class]]) {
		return NO;
	}
	TGGlowSilhouette *s = object;
	return s.sheet == _sheet && s.layout == _layout
		&& s.u0 == _u0 && s.v0 == _v0 && s.u1 == _u1 && s.v1 == _v1
		&& s.w == _w && s.h == _h;
}

- (NSUInteger)hash
{
	NSUInteger hash = (NSUInteger)(uintptr_t)_sheet;
	hash = hash * 31 + (NSUInteger)(uintptr_t)_layout;
	union { float f; uint32_t i; } bits;
	bits.f = _u0; hash = hash * 31 + bits.i;
	bits.f = _v0; hash = hash * 31 + bits.i;
	bits.f = _u1; hash = hash * 31 + bits.i;
	bits.f = _v1; hash = hash * 31 + bits.i;
	bits.f = _w; hash = hash * 31 + bits.i;
	bits.f = _h; hash = hash * 31 + bits.i;
	return hash;
}

@end

@implementation TGGlowMaskEntry
@end

@interface TGGlowJob : NSObject
@property (nonatomic, strong) TGGlowSilhouette *key;
@property (nonatomic) float sigmaX, sigmaY;
@end

@implementation TGGlowJob
@end

@implementation TGGlowMaskCache {
	TGMetalContext *_context;
	NSMutableDictionary<TGGlowSilhouette *, NSMutableArray<TGGlowMaskEntry *> *> *_entries;
	NSMutableArray<TGGlowJob *> *_pending;
	TGGlowSilhouette *_scratch;
	int _count;
	int _frame;
}

- (instancetype)initWithContext:(TGMetalContext *)context
{
	if (self = [super init]) {
		_context = context;
		_entries = [NSMutableDictionary dictionary];
		_pending = [NSMutableArray array];
		_scratch = [TGGlowSilhouette new];
	}
	return self;
}

- (TGGlowMaskEntry *)lookupSheet:(TGSpriteSheet *)sheet layout:(id)layout
							  u0:(float)u0 v0:(float)v0 u1:(float)u1 v1:(float)v1
							   w:(float)w h:(float)h
						  sigmaX:(float)sigmaX sigmaY:(float)sigmaY
{
	sigmaX = quantize(sigmaX);
	sigmaY = quantize(sigmaY);
	_scratch.sheet = sheet;
	_scratch.layout = layout;
	_scratch.u0 = u0;
	_scratch.v0 = v0;
	_scratch.u1 = u1;
	_scratch.v1 = v1;
	_scratch.w = w;
	_scratch.h = h;
	NSMutableArray<TGGlowMaskEntry *> *list = _entries[_scratch];
	TGGlowMaskEntry *nearest = nil;
	double nearestDistance = DBL_MAX;
	for (TGGlowMaskEntry *e in list) {
		if (e.sigmaX == sigmaX && e.sigmaY == sigmaY) {
			e.lastUsed = _frame;
			return e.texture ? e : nil;
		}
		if (!e.texture) {
			continue;
		}
		double d = fabs(log(e.sigmaX / sigmaX)) + fabs(log(e.sigmaY / sigmaY));
		if (d < nearestDistance) {
			nearestDistance = d;
			nearest = e;
		}
	}
	[self enqueueSigmaX:sigmaX sigmaY:sigmaY];
	if (nearest) {
		nearest.lastUsed = _frame;
	}
	return nearest;
}

- (void)enqueueSigmaX:(float)sigmaX sigmaY:(float)sigmaY
{
	if (_pending.count >= kMaxPending) {
		return;
	}
	for (TGGlowJob *j in _pending) {
		if (j.sigmaX == sigmaX && j.sigmaY == sigmaY && [j.key isEqual:_scratch]) {
			return;
		}
	}
	TGGlowJob *job = [TGGlowJob new];
	job.key = [_scratch copy];
	job.sigmaX = sigmaX;
	job.sigmaY = sigmaY;
	[_pending addObject:job];
}

- (void)beginFrame:(TGSpriteBatch *)batch commandBuffer:(id<MTLCommandBuffer>)command
{
	_frame++;
	if (_pending.count > 0) {
		int built = 0;
		while (_pending.count > 0 && built < kBuildsPerFrame) {
			TGGlowJob *job = _pending.firstObject;
			[_pending removeObjectAtIndex:0];
			[self build:job batch:batch commandBuffer:command];
			built++;
		}
		while (_count > kMaxEntries) {
			[self evictLeastRecentlyUsed];
		}
	}
	if (_frame % kSweepInterval == 0) {
		[self sweepIdle];
	}
}

/** Column-major ortho mapping sprite-local [-padX, w+padX] x [-padY,
 *  h+padY] onto the mask texture (row 0 = the top edge; Metal's NDC y
 *  points up, so y is negated relative to the GL twin). */
static void orthoLocal(float *m, float padX, float padY, int fullW, int fullH)
{
	memset(m, 0, 16 * sizeof(float));
	m[0] = 2.0f / fullW;
	m[5] = -2.0f / fullH;
	m[10] = -1.0f;
	m[12] = 2.0f * padX / fullW - 1.0f;
	m[13] = 1.0f - 2.0f * padY / fullH;
	m[15] = 1.0f;
}

static void gaussianWeights(float sigma, float *w)
{
	float twoSigmaSquared = 2.0f * sigma * sigma;
	float sum = 0.0f;
	for (int i = 0; i < 5; i++) {
		w[i] = (twoSigmaSquared > 0.0f) ? expf(-(float)(i * i) / twoSigmaSquared) : (i == 0 ? 1.0f : 0.0f);
		sum += (i == 0) ? w[i] : 2.0f * w[i];
	}
	for (int i = 0; i < 5; i++) {
		w[i] /= sum;
	}
}

- (id<MTLTexture>)allocTextureWidth:(int)width height:(int)height
{
	MTLTextureDescriptor *d = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
																				  width:width height:height mipmapped:NO];
	d.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
	d.storageMode = MTLStorageModePrivate;
	return [_context.device newTextureWithDescriptor:d];
}

/** One fullscreen pass with `pipeline` reading `source` into `target`. */
- (BOOL)encodePass:(id<MTLRenderPipelineState>)pipeline from:(id<MTLTexture>)source to:(id<MTLTexture>)target
		  uniforms:(const void *)uniforms length:(NSUInteger)length commandBuffer:(id<MTLCommandBuffer>)command
{
	MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
	pass.colorAttachments[0].texture = target;
	pass.colorAttachments[0].loadAction = MTLLoadActionDontCare;
	pass.colorAttachments[0].storeAction = MTLStoreActionStore;
	id<MTLRenderCommandEncoder> encoder = [command renderCommandEncoderWithDescriptor:pass];
	if (!encoder) {
		return NO;
	}
	[encoder setRenderPipelineState:pipeline];
	[encoder setFragmentTexture:source atIndex:0];
	[encoder setFragmentSamplerState:[_context samplerWithSmoothing:YES repeat:NO] atIndex:0];
	[encoder setFragmentBytes:uniforms length:length atIndex:0];
	[encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
	[encoder endEncoding];
	return YES;
}

- (void)build:(TGGlowJob *)job batch:(TGSpriteBatch *)batch commandBuffer:(id<MTLCommandBuffer>)command
{
	TGGlowMaskEntry *entry = [TGGlowMaskEntry new];
	entry.sigmaX = job.sigmaX;
	entry.sigmaY = job.sigmaY;
	entry.lastUsed = _frame;
	NSMutableArray<TGGlowMaskEntry *> *list = _entries[job.key];
	if (!list) {
		list = [NSMutableArray arrayWithCapacity:2];
		_entries[job.key] = list;
	}
	[list addObject:entry];
	_count++;

	TGSpriteSheet *sheet = job.key.sheet;
	if (!sheet || ![sheet isReady]) {
		return; // unloaded meanwhile; the failed entry blocks retries
	}

	float padX = ceilf(TGGlowPadSigmas * job.sigmaX);
	float padY = ceilf(TGGlowPadSigmas * job.sigmaY);
	int fullW = MAX(1, (int)ceilf(job.key.w + 2.0f * padX));
	int fullH = MAX(1, (int)ceilf(job.key.h + 2.0f * padY));

	// Halvings per axis until sigma fits the 9-tap kernel; oversize
	// silhouettes start below 1:1 (k0) so the first texture fits
	int kx = levels(job.sigmaX);
	int ky = levels(job.sigmaY);
	int k0 = 0;
	while ((fullW >> k0) > kMaxFullRes || (fullH >> k0) > kMaxFullRes) {
		k0++;
	}
	int curW = MAX(1, ceilDiv(fullW, 1 << k0));
	int curH = MAX(1, ceilDiv(fullH, 1 << k0));

	// 1. Silhouette at (near) full resolution, blended onto transparent
	id<MTLTexture> texA = [self allocTextureWidth:curW height:curH];
	if (!texA) {
		return;
	}
	MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
	pass.colorAttachments[0].texture = texA;
	pass.colorAttachments[0].loadAction = MTLLoadActionClear;
	pass.colorAttachments[0].storeAction = MTLStoreActionStore;
	pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0);
	id<MTLRenderCommandEncoder> encoder = [command renderCommandEncoderWithDescriptor:pass];
	if (!encoder) {
		return;
	}
	float ortho[16];
	orthoLocal(ortho, padX, padY, fullW, fullH);
	[batch renderSilhouette:job.key ortho:ortho encoder:encoder];
	[encoder endEncoding];

	// 2. Box-halve each axis down to its target level
	int remX = MAX(0, kx - k0);
	int remY = MAX(0, ky - k0);
	while (remX > 0 || remY > 0) {
		int nextW = (remX > 0) ? MAX(1, ceilDiv(curW, 2)) : curW;
		int nextH = (remY > 0) ? MAX(1, ceilDiv(curH, 2)) : curH;
		id<MTLTexture> texB = [self allocTextureWidth:nextW height:nextH];
		if (!texB) {
			return;
		}
		vector_float2 off = { (remX > 0) ? 0.5f / curW : 0.0f, (remY > 0) ? 0.5f / curH : 0.0f };
		if (![self encodePass:[_context glowDownsamplePipeline] from:texA to:texB
					 uniforms:&off length:sizeof(off) commandBuffer:command]) {
			return;
		}
		texA = texB;
		curW = nextW;
		curH = nextH;
		remX = MAX(0, remX - 1);
		remY = MAX(0, remY - 1);
	}

	// 3. Separable Gaussian, horizontal then vertical (with gain)
	float lowSigmaX = job.sigmaX / (float)(1 << MAX(kx, k0));
	float lowSigmaY = job.sigmaY / (float)(1 << MAX(ky, k0));
	float w[5];
	TGGlowBlurUniforms blur;
	id<MTLTexture> texB = [self allocTextureWidth:curW height:curH];
	id<MTLTexture> texC = [self allocTextureWidth:curW height:curH];
	if (!texB || !texC) {
		return;
	}
	gaussianWeights(lowSigmaX, w);
	blur.step = (vector_float2){ 1.0f / curW, 0.0f };
	blur.gain = 1.0f;
	blur.w0 = w[0]; blur.w1 = w[1]; blur.w2 = w[2]; blur.w3 = w[3]; blur.w4 = w[4];
	if (![self encodePass:[_context glowBlurPipeline] from:texA to:texB
				 uniforms:&blur length:sizeof(blur) commandBuffer:command]) {
		return;
	}
	gaussianWeights(lowSigmaY, w);
	blur.step = (vector_float2){ 0.0f, 1.0f / curH };
	blur.gain = kGain;
	blur.w0 = w[0]; blur.w1 = w[1]; blur.w2 = w[2]; blur.w3 = w[3]; blur.w4 = w[4];
	if (![self encodePass:[_context glowBlurPipeline] from:texB to:texC
				 uniforms:&blur length:sizeof(blur) commandBuffer:command]) {
		return;
	}

	entry.texture = [[TGMetalTexture alloc] initWithTexture:texC
													sampler:[_context samplerWithSmoothing:YES repeat:NO]];
	entry.padX = padX;
	entry.padY = padY;
}

- (void)evictLeastRecentlyUsed
{
	NSMutableArray<TGGlowMaskEntry *> *oldestList = nil;
	TGGlowMaskEntry *oldest = nil;
	for (NSMutableArray<TGGlowMaskEntry *> *list in _entries.allValues) {
		for (TGGlowMaskEntry *e in list) {
			if (!oldest || e.lastUsed < oldest.lastUsed) {
				oldest = e;
				oldestList = list;
			}
		}
	}
	if (!oldest) {
		_count = 0;
		return;
	}
	[self remove:oldest from:oldestList];
}

- (void)sweepIdle
{
	for (TGGlowSilhouette *key in _entries.allKeys) {
		NSMutableArray<TGGlowMaskEntry *> *list = _entries[key];
		for (NSInteger i = (NSInteger)list.count - 1; i >= 0; i--) {
			TGGlowMaskEntry *e = list[i];
			if (_frame - e.lastUsed > kIdleFrames) {
				[self remove:e from:list];
			}
		}
		if (list.count == 0) {
			[_entries removeObjectForKey:key];
		}
	}
}

- (void)remove:(TGGlowMaskEntry *)e from:(NSMutableArray<TGGlowMaskEntry *> *)list
{
	e.texture = nil; // encoded commands keep the texture alive until done
	[list removeObjectIdenticalTo:e];
	_count--;
}

@end
