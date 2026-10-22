#import "TGBitmapFont.h"
#import "TGDebugHud.h"
#import "TGMetalContext.h"
#import "TGMetalView.h"
#import "TGParticleEmitter.h"
#import "TGPostEffect.h"
#import "TGRope.h"
#import "TGScene.h"
#import "TGSceneRenderer.h"
#import "TGScreenOverlay.h"
#import "TGSprite.h"
#import "TGSpriteBatch.h"
#import "TGTextSprite.h"
#import "TGTextureManager.h"
#import "TGTileLayer.h"
#import "TGTouchController.h"
#import <QuartzCore/CAMetalLayer.h>
#import <XCTest/XCTest.h>
#import <objc/runtime.h>
#import <stdatomic.h>

@interface ImageLoader : NSObject <TGSpriteSheetLoader>
@property UIImage *image;
@property int loads;
@end
@implementation ImageLoader
- (UIImage *)loadSpriteSheet:(TGSpriteSheet *)sheet
{
	self.loads++;
	return self.image;
}
@end

// A blocked decoder lets lifecycle/query calls race a real in-flight load.
@interface BlockingImageLoader : ImageLoader
@property dispatch_semaphore_t entered, proceed;
@end
@implementation BlockingImageLoader
- (UIImage *)loadSpriteSheet:(TGSpriteSheet *)sheet
{
 UIImage *image = [super loadSpriteSheet:sheet];
 if (self.loads == 1) {
  dispatch_semaphore_signal(self.entered);
  dispatch_semaphore_wait(self.proceed, DISPATCH_TIME_FOREVER);
 }
 return image;
}
@end

@interface CountingRenderer : TGSceneRenderer
{
  @public
	atomic_uint frames;
}
@end
@implementation CountingRenderer
- (BOOL)drawFrame:(CFTimeInterval)time
	commandBuffer:(id<MTLCommandBuffer>)command
		   target:(id<MTLTexture>)target
			 slot:(NSUInteger)slot
{
	BOOL encoded = [super drawFrame:time commandBuffer:command target:target slot:slot];
	if (encoded)
		atomic_fetch_add(&frames, 1);
	return encoded;
}
@end

// Allocation spy forwards to the actual Metal device; it counts requested GPU
// storage even on Simulator implementations reporting currentAllocatedSize as zero.
@interface RecordingDevice : NSObject
@property id<MTLDevice> realDevice;
@property NSUInteger requestedBytes;
@end
@implementation RecordingDevice
- (id<MTLBuffer>)newBufferWithLength:(NSUInteger)length options:(MTLResourceOptions)options
{
	self.requestedBytes += length;
	return [self.realDevice newBufferWithLength:length options:options];
}
@end
@interface BudgetContext : TGMetalContext
@property RecordingDevice *recorder;
@end
@implementation BudgetContext
- (id<MTLDevice>)device
{
	return self.recorder ? (id<MTLDevice>)self.recorder : [super device];
}
@end

@interface TGTouchController (GeometryTests)
- (CGPoint)surfacePoint:(UITouch *)touch inView:(UIView *)view;
- (float)worldSlop;
- (void)updateContentScale:(CGFloat)scale;
@end
@interface FixedTouch : NSObject
@end
@implementation FixedTouch
- (CGPoint)locationInView:(UIView *)view
{
	return CGPointMake(10, 15);
}
@end

// Deterministic scheduling fixture: production tick/renderer/stats remain real;
// only drawable availability and the GPU-owned semaphore are controlled.
@interface EmptyDrawableLayer : CAMetalLayer
@property NSTimeInterval acquisitionDelay;
@end
@implementation EmptyDrawableLayer
- (id<CAMetalDrawable>)nextDrawable
{
	if (self.acquisitionDelay > 0)
		[NSThread sleepForTimeInterval:self.acquisitionDelay];
	return nil;
}
@end
@interface EmptyDrawableView : TGMetalView
@end
@implementation EmptyDrawableView
+ (Class)layerClass
{
	return [EmptyDrawableLayer class];
}
@end
@interface DisplayTick : NSObject
@property CFTimeInterval timestamp, targetTimestamp, duration;
@end
@implementation DisplayTick
@end
@interface TGMetalView (SchedulingTests)
- (void)tick:(CADisplayLink *)link;
@end
static void *NativeIvar(id object, const char *name)
{
	return (uint8_t *)(__bridge void *)object +
		   ivar_getOffset(class_getInstanceVariable([object class], name));
}

@interface RendererTests : XCTestCase
@end
@implementation RendererTests
{
	TGMetalContext *_context;
	TGTextureManager *_textures;
	TGSpriteBatch *_batch;
	TGScreenOverlay *_overlay;
	id<MTLCommandQueue> _queue;
	id<MTLTexture> _target;
	id<MTLCommandBuffer> _command;
	id<MTLRenderCommandEncoder> _encoder;
	NSData *_pixels;
}
- (void)setUp
{
	_context = [TGMetalContext sharedContext];
	XCTAssertNotNil(_context);
	_textures = [[TGTextureManager alloc] initWithContext:_context];
	_batch = [[TGSpriteBatch alloc] initWithContext:_context];
	_overlay = [TGScreenOverlay new];
	[_overlay surfaceChangedWithWidth:64 height:64];
	_queue = [_context.device newCommandQueue];
	MTLTextureDescriptor *desc =
		[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
														   width:64
														  height:64
													   mipmapped:NO];
	desc.usage = MTLTextureUsageRenderTarget;
	desc.storageMode = MTLStorageModeShared;
	_target = [_context.device newTextureWithDescriptor:desc];
}
- (void)begin
{
	_command = [_queue commandBuffer];
	MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
	pass.colorAttachments[0].texture = _target;
	pass.colorAttachments[0].loadAction = MTLLoadActionClear;
	pass.colorAttachments[0].storeAction = MTLStoreActionStore;
	pass.colorAttachments[0].clearColor = MTLClearColorMake(.2, .4, .6, 1);
	_encoder = [_command renderCommandEncoderWithDescriptor:pass];
	[_batch beginFrameWithEncoder:_encoder slot:0];
	[_batch begin:_overlay.projection
		screenProjection:_overlay.projection
				 originX:0
				 originY:0
			 screenScale:1
				 travelX:0
				 travelY:0];
}
- (void)finish
{
	[_batch end];
	[_encoder endEncoding];
	[_batch setRenderEncoder:nil];
	[_command commit];
	[_command waitUntilCompleted];
	XCTAssertEqual(_command.status, MTLCommandBufferStatusCompleted, @"%@", _command.error);
	[self readPixels];
}
- (void)readPixels
{
	NSMutableData *pixels = [NSMutableData dataWithLength:64 * 64 * 4];
	[_target getBytes:pixels.mutableBytes
		  bytesPerRow:64 * 4
		   fromRegion:MTLRegionMake2D(0, 0, 64, 64)
		  mipmapLevel:0];
	_pixels = pixels;
	XCTAttachment *attachment = [XCTAttachment attachmentWithData:pixels
											uniformTypeIdentifier:@"public.data"];
	attachment.name = self.name;
	attachment.lifetime = XCTAttachmentLifetimeKeepAlways;
	[self addAttachment:attachment];
}
- (void)pixelX:(int)x y:(int)y r:(int)r g:(int)g b:(int)b
{
	const uint8_t *p = _pixels.bytes;
	int i = (y * 64 + x) * 4;
	XCTAssertEqualWithAccuracy(p[i + 2], r, 2, @"red (%d,%d)", x, y);
	XCTAssertEqualWithAccuracy(p[i + 1], g, 2, @"green (%d,%d)", x, y);
	XCTAssertEqualWithAccuracy(p[i], b, 2, @"blue (%d,%d)", x, y);
}
- (ImageLoader *)loader
{
	// Two asymmetric rows, so flips/orientation and atlas selection are observable.
	const uint8_t pixels[] = {255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 255, 255, 0, 255};
	CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
	CGContextRef bitmap = CGBitmapContextCreate((void *)pixels, 2, 2, 8, 8, space,
												kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
	CGImageRef image = CGBitmapContextCreateImage(bitmap);
	ImageLoader *loader = [ImageLoader new];
	loader.image = [UIImage imageWithCGImage:image];
	CGImageRelease(image);
	CGContextRelease(bitmap);
	CGColorSpaceRelease(space);
	return loader;
}
- (TGSpriteSheet *)sheet:(ImageLoader *)loader
{
	TGSpriteSheet *sheet = [[TGSpriteSheet alloc] initWithLoader:loader gridFrameWidth:2 gridFrameHeight:2];
	sheet.smoothing = NO;
	XCTAssertTrue([sheet ensureLoaded:_textures]);
	[_textures track:sheet];
	return sheet;
}
- (void)testTopLeftGeometryAndBlendModes
{
	const int expected[4][3] = {{153, 51, 76}, {179, 102, 153}, {51, 51, 76}, {153, 102, 153}};
	for (int mode = 0; mode < 4; mode++)
	{
		[self begin];
		[_batch setBlendMode:mode];
		TGFrame f = {0, 0, 1, 1, 1, 1};
		[_batch drawFrame:[_textures whiteTexture] frame:f cx:8 cy:8 halfW:8 halfH:8 r:1 g:0 b:0 a:.5];
		[self finish];
		[self pixelX:4 y:4 r:expected[mode][0] g:expected[mode][1] b:expected[mode][2]];
		[self pixelX:4 y:50 r:51 g:102 b:153];
	}
}
- (void)testMultipleFlushesAndHudPassDoNotOverwriteVertices
{
	[self begin];
	TGFrame f = {0, 0, 1, 1, 1, 1};
	for (int i = 0; i < 1001; i++)
		[_batch drawFrame:[_textures whiteTexture] frame:f cx:8 cy:8 halfW:8 halfH:8 r:1 g:0 b:0 a:1];
	[_batch end];
	XCTAssertEqual(_batch.drawCalls, 2);
	// A second begin in the SAME frame (the HUD) must not reset the buffer pool cursor.
	[_batch begin:_overlay.projection
		screenProjection:_overlay.projection
				 originX:0
				 originY:0
			 screenScale:1
				 travelX:0
				 travelY:0];
	[_batch drawFrame:[_textures whiteTexture] frame:f cx:48 cy:48 halfW:8 halfH:8 r:0 g:1 b:0 a:1];
	[self finish];
	[self pixelX:4 y:4 r:255 g:0 b:0];
	[self pixelX:48 y:48 r:0 g:255 b:0];
}
- (void)testTextureOrientationFlipsAndNearestFiltering
{
	ImageLoader *loader = [self loader];
	TGSpriteSheet *sheet = [self sheet:loader];
	TGSprite *sprite = [TGSprite new];
	sprite.sheet = sheet;
	sprite.x = 16;
	sprite.y = 16;
	sprite.scaleX = 16;
	sprite.scaleY = 16;
	[self begin];
	[_batch draw:sprite];
	[self finish];
	[self pixelX:4 y:4 r:255 g:0 b:0];
	[self pixelX:28 y:4 r:0 g:255 b:0];
	[self pixelX:4 y:28 r:0 g:0 b:255];
	[self pixelX:28 y:28 r:255 g:255 b:0];
	sprite.flipX = YES;
	sprite.flipY = YES;
	[self begin];
	[_batch draw:sprite];
	[self finish];
	[self pixelX:4 y:4 r:255 g:255 b:0];
	[self pixelX:28 y:28 r:255 g:0 b:0];
}
- (void)testUnloadWhileCommandIsEncodedRetainsGpuTextureAndBlocksReload
{
	ImageLoader *loader = [self loader];
	TGSpriteSheet *sheet = [self sheet:loader];
	TGTextureManager *other = [[TGTextureManager alloc] initWithContext:_context];
	XCTAssertFalse([sheet ensureLoaded:other]);
	XCTAssertEqual(loader.loads, 1);
	[self begin];
	TGFrame f;
	[sheet frame:0 into:&f];
	[_batch drawFrame:[sheet textureResource] frame:f cx:16 cy:16 halfW:16 halfH:16 r:1 g:1 b:1 a:1];
	[_batch end];
	[sheet dispose];
	[_textures deleteDisposed];
	XCTAssertFalse([sheet isReady]);
	XCTAssertFalse([sheet ensureLoaded:other]);
	XCTAssertEqual(loader.loads, 1);
	[self finish];
	[self pixelX:4 y:4 r:255 g:0 b:0];
}
- (void)testSharedSheetSurvivesManagerDeallocation
{
	ImageLoader *loader = [self loader];
	TGSpriteSheet *sheet = [self sheet:loader];
	TGMetalTexture *resource = [sheet textureResource];
	_textures = nil;
	TGTextureManager *other = [[TGTextureManager alloc] initWithContext:_context];
	XCTAssertFalse([sheet ensureLoaded:other]);
	XCTAssertEqual([sheet textureResource], resource);
	[self begin];
	TGFrame f;
	[sheet frame:0 into:&f];
	[_batch drawFrame:resource frame:f cx:16 cy:16 halfW:16 halfH:16 r:1 g:1 b:1 a:1];
	[self finish];
	[self pixelX:4 y:4 r:255 g:0 b:0];
}
- (void)testCameraEffectsPreserveExpectedColor
{
	TGScene *scene = [TGScene new];
	scene.bgRed = 1;
	scene.bgGreen = 0;
	scene.bgBlue = 0;
	scene.bgAlpha = 1;
	scene.cameraEffect = TGPostEffectTint;
	scene.effectTintR = 0;
	scene.effectTintG = 1;
	scene.effectTintB = 1;
	scene.effectIntensity = 1;
	TGSceneRenderer *renderer = [[TGSceneRenderer alloc] initWithScene:scene viewProxy:nil];
	[renderer surfaceCreated];
	[renderer surfaceChangedWithWidth:64 height:64];
	_command = [_queue commandBuffer];
	XCTAssertTrue([renderer drawFrame:1 commandBuffer:_command target:_target slot:0]);
	[_command commit];
	[_command waitUntilCompleted];
	XCTAssertEqual(_command.status, MTLCommandBufferStatusCompleted);
	[self readPixels];
	[self pixelX:4 y:4 r:0 g:0 b:0];
	scene.cameraEffect = TGPostEffectGlitch;
	scene.effectIntensity = 0;
	_command = [_queue commandBuffer];
	XCTAssertTrue([renderer drawFrame:2 commandBuffer:_command target:_target slot:1]);
	[_command commit];
	[_command waitUntilCompleted];
	[self readPixels];
	[self pixelX:4 y:4 r:255 g:0 b:0];
}
- (void)testWorldWrapAndParallaxKeepNativeDrawCoordinates
{
	TGSprite *sprite = [TGSprite new];
	sprite.x = 98;
	sprite.y = 20;
	sprite.wrapWorldX = YES;
	sprite.scrollFactor = .5;
	[self begin];
	[_batch begin:_overlay.projection
		screenProjection:_overlay.projection
				 originX:0
				 originY:0
			 screenScale:1
				 travelX:10
				 travelY:8];
	[_batch setWorldWrapX:YES minX:0 maxX:100 referenceX:0];
	XCTAssertEqualWithAccuracy([_batch parallaxX:sprite], 3, .001);
	XCTAssertEqualWithAccuracy([_batch parallaxY:sprite], 24, .001);
	sprite.screenFixed = YES;
	XCTAssertEqualWithAccuracy([_batch parallaxX:sprite], 98, .001);
	XCTAssertEqualWithAccuracy([_batch parallaxY:sprite], 20, .001);
	[self finish];
}

- (void)testManualPauseSurvivesLifecycleWhileOtherViewKeepsRendering
{
	TGScene *a = [TGScene new], *b = [TGScene new];
	CountingRenderer *ra = [[CountingRenderer alloc] initWithScene:a viewProxy:nil],
					 *rb = [[CountingRenderer alloc] initWithScene:b viewProxy:nil];
	atomic_init(&ra->frames, 0);
	atomic_init(&rb->frames, 0);
	__block UIWindow *window;
	__block TGMetalView *hidden, *visible;
	void (^setup)(void) = ^{
	  window = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 128, 64)];
	  window.rootViewController = [UIViewController new];
	  [window makeKeyAndVisible];
	  hidden = [[TGMetalView alloc] initWithFrame:CGRectMake(0, 0, 64, 64) renderer:ra];
	  visible = [[TGMetalView alloc] initWithFrame:CGRectMake(64, 0, 64, 64) renderer:rb];
	  [window.rootViewController.view addSubview:hidden];
	  [window.rootViewController.view addSubview:visible];
	  [hidden pauseRendering];
	  [hidden startRendering];
	  [visible startRendering];
	  [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidBecomeActiveNotification
														object:nil];
	};
	if (NSThread.isMainThread)
		setup();
	else
		dispatch_sync(dispatch_get_main_queue(), setup);
	XCTestExpectation *first = [self expectationWithDescription:@"visible view renders independently"];
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 400 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
	  [first fulfill];
	});
	[self waitForExpectations:@[ first ] timeout:4];
	XCTAssertEqual(atomic_load(&ra->frames), 0u);
	XCTAssertGreaterThan(atomic_load(&rb->frames), 0u);
	[NSNotificationCenter.defaultCenter postNotificationName:UIApplicationWillResignActiveNotification
													  object:nil];
	[hidden resumeRendering];
	XCTestExpectation *background =
		[self expectationWithDescription:@"explicit resume cannot bypass app suspension"];
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 150 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
	  [background fulfill];
	});
	[self waitForExpectations:@[ background ] timeout:4];
	XCTAssertEqual(atomic_load(&ra->frames), 0u);
	[NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidBecomeActiveNotification
													  object:nil];
	XCTestExpectation *resumed = [self expectationWithDescription:@"resumes after foreground"];
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 250 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
	  [resumed fulfill];
	});
	[self waitForExpectations:@[ resumed ] timeout:4];
	XCTAssertGreaterThan(atomic_load(&ra->frames), 0u);
	[hidden stopRendering];
	[visible stopRendering];
	unsigned stopped = atomic_load(&ra->frames);
	XCTestExpectation *closed = [self expectationWithDescription:@"closed view submits no more frames"];
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
	  [closed fulfill];
	});
	[self waitForExpectations:@[ closed ] timeout:4];
	XCTAssertEqual(atomic_load(&ra->frames), stopped);
	void (^cleanup)(void) = ^{
	  [hidden removeFromSuperview];
	  [visible removeFromSuperview];
	  window.hidden = YES;
	};
	if (NSThread.isMainThread)
		cleanup();
	else
		dispatch_sync(dispatch_get_main_queue(), cleanup);
}

- (void)testHudIsCompositedAfterTheCameraTint
{
	TGScene *scene = [TGScene new];
	scene.cameraEffect = TGPostEffectTint;
	scene.effectTintR = 0;
	scene.effectTintG = 0;
	scene.effectTintB = 0;
	scene.effectIntensity = 1;
	scene.hud.enabled = YES;
	scene.stats.enabled = YES;
	TGFrameStatsSnapshot snapshot = {0};
	[scene.hud update:snapshot];
	TGSceneRenderer *renderer = [[TGSceneRenderer alloc] initWithScene:scene viewProxy:nil];
	[renderer surfaceCreated];
	[renderer surfaceChangedWithWidth:64 height:64];
	_command = [_queue commandBuffer];
	XCTAssertTrue([renderer drawFrame:1 commandBuffer:_command target:_target slot:0]);
	[_command commit];
	[_command waitUntilCompleted];
	[self readPixels];
	const uint8_t *pixels = _pixels.bytes;
	BOOL hasHudColor = NO;
	for (int i = 0; i < 64 * 64; i++)
		if (pixels[i * 4 + 2] > 100 && pixels[i * 4 + 1] > 100)
			hasHudColor = YES;
	XCTAssertTrue(hasHudColor, @"camera tint must not black out the native HUD text");
	XCTAssertTrue([scene.hud hitTestX:10 y:10]);
}
- (void)testTileParticleRopeAndBitmapTextUseMetalTextureReferences
{
	ImageLoader *loader = [self loader];
	TGSpriteSheet *sheet = [self sheet:loader];
	TGTileLayer *layer = [TGTileLayer new];
	layer.sheet = sheet;
	layer.tileWidth = 16;
	layer.tileHeight = 16;
	int32_t tiles[2] = {0, -1};
	[layer setGridCols:2 rows:1 tiles:tiles count:2];
	TGParticleEmitter *emitter = [TGParticleEmitter new];
	emitter.sheet = sheet;
	emitter.x = 16;
	emitter.y = 48;
	emitter.speed = 0;
	emitter.size = 16;
	emitter.rate = 0;
	[emitter emit:1];
	[emitter update:0];
	TGRope *rope = [TGRope new];
	rope.sheet = sheet;
	rope.x = 48;
	rope.y = 32;
	rope.segments = 1;
	rope.segmentLength = 16;
	rope.thickness = 8;
	[rope update:0];
	TGBitmapFont *font = [TGBitmapFont gridFontWithSheet:sheet characters:@"A" charWidth:2 charHeight:2];
	TGTextSprite *text = [TGTextSprite new];
	text.font = font;
	text.text = @"A";
	text.x = 40;
	text.y = 0;
	text.anchorX = 0;
	text.anchorY = 0;
	text.scaleX = 8;
	text.scaleY = 8;
	[self begin];
	[layer draw:_batch viewLeft:0 viewTop:0 viewRight:64 viewBottom:64];
	[emitter draw:_batch];
	[rope draw:_batch];
	[_batch draw:text];
	[self finish];
	[self pixelX:4 y:4 r:255 g:0 b:0];
	[self pixelX:24 y:4 r:51 g:102 b:153];
	[self pixelX:12 y:44 r:255 g:0 b:0];
	[self pixelX:44 y:4 r:255 g:0 b:0];
	const uint8_t *pixels = _pixels.bytes;
	int i = (40 * 64 + 48) * 4;
	XCTAssertTrue(pixels[i + 2] != 51 || pixels[i + 1] != 102 || pixels[i] != 153,
				  @"rope segment must be drawn");
}
- (void)testGlowAndFlashUseTheSilhouettePipeline
{
	ImageLoader *loader = [self loader];
	TGSprite *sprite = [TGSprite new];
	sprite.sheet = [self sheet:loader];
	sprite.x = 32;
	sprite.y = 32;
	sprite.scaleX = 8;
	sprite.scaleY = 8;
	sprite.glowBlur = 4;
	sprite.glowOpacity = 1;
	sprite.glowR = 1;
	sprite.glowG = 0;
	sprite.glowB = 1;
	sprite.flashRemaining = 1;
	sprite.flashDuration = 1;
	sprite.flashR = 0;
	sprite.flashG = 1;
	sprite.flashB = 0;
	[self begin];
	[_batch draw:sprite];
	[self finish];
	[self pixelX:28 y:28 r:0 g:255 b:0];
	const uint8_t *p = _pixels.bytes;
	int i = (32 * 64 + 22) * 4;
	XCTAssertGreaterThan(p[i + 2], 51);
	XCTAssertGreaterThan(p[i], 153);
}

- (void)testAlternatingTexturesRetainPixelsWithinAReasonableMemoryBudget
{
	TGTextureManager *other = [[TGTextureManager alloc] initWithContext:_context];
	TGMetalTexture *a = [_textures whiteTexture], *b = [other whiteTexture];
	BudgetContext *budget = [BudgetContext new];
	RecordingDevice *recorder = [RecordingDevice new];
	recorder.realDevice = _context.device;
	budget.recorder = recorder;
	_batch = [[TGSpriteBatch alloc] initWithContext:budget];
	[self begin];
	TGFrame f = {0, 0, 1, 1, 1, 1};
	[_batch drawFrame:a frame:f cx:8 cy:8 halfW:8 halfH:8 r:1 g:0 b:0 a:1];
	for (int i = 0; i < 1000; i++)
		[_batch drawFrame:i % 2 ? a : b frame:f cx:48 cy:48 halfW:8 halfH:8 r:0 g:1 b:0 a:1];
	[self finish];
	NSUInteger allocated = recorder.requestedBytes;
	XCTAssertLessThan(allocated, 16u * 1024u * 1024u,
					  @"1000 tiny flushes must not retain 192 MB of full-size buffers");
	[self pixelX:4 y:4 r:255 g:0 b:0];
	[self pixelX:48 y:48 r:0 g:255 b:0];
}

- (void)testChangingDisplayScaleUpdatesTouchCoordinatesAndSlop
{
	TGScene *scene = [TGScene new];
	TGTouchController *touch = [[TGTouchController alloc] initWithScene:scene viewProxy:nil contentScale:1];
	if ([touch respondsToSelector:@selector(updateContentScale:)])
		[touch updateContentScale:2];
	CGPoint point = [touch surfacePoint:(UITouch *)[FixedTouch new] inView:nil];
	XCTAssertEqualWithAccuracy(point.x, 20, .001);
	XCTAssertEqualWithAccuracy(point.y, 30, .001);
	XCTAssertEqualWithAccuracy([touch worldSlop], 16, .001);
	scene.cameraScale = 2;
	XCTAssertEqualWithAccuracy([touch worldSlop], 8, .001);
}

- (EmptyDrawableView *)scheduledView:(TGSceneRenderer *)renderer
{
	EmptyDrawableView *view = [[EmptyDrawableView alloc] initWithFrame:CGRectMake(0, 0, 64, 64)
															  renderer:renderer];
	atomic_store((atomic_bool *)NativeIvar(view, "_running"), true);
	atomic_store((atomic_bool *)NativeIvar(view, "_appActive"), true);
	return view;
}
- (DisplayTick *)tickAt:(double)time
{
	DisplayTick *tick = [DisplayTick new];
	tick.timestamp = time;
	tick.targetTimestamp = time + 1.0 / 60;
	tick.duration = 1.0 / 60;
	return tick;
}
- (void)testBackpressurePreservesClockAndClampedRecovery
{
 for (NSNumber *busy in @[@NO, @YES]) {
  TGScene *scene = [TGScene new];
  TGSceneRenderer *renderer = [[TGSceneRenderer alloc] initWithScene:scene viewProxy:nil];
  [renderer surfaceCreated];
  EmptyDrawableView *view = [self scheduledView:renderer];
  id<MTLCommandBuffer> first = [_queue commandBuffer];
  XCTAssertTrue([renderer drawFrame:1 commandBuffer:first target:_target slot:0]);
  [first commit]; [first waitUntilCompleted];
  dispatch_semaphore_t __unsafe_unretained *slots =
   (dispatch_semaphore_t __unsafe_unretained *)NativeIvar(view, "_slots");
  if (busy.boolValue) dispatch_semaphore_wait(slots[0], DISPATCH_TIME_NOW);
  [view tick:(CADisplayLink *)[self tickAt:1.05]];
  if (busy.boolValue) dispatch_semaphore_signal(slots[0]);
  XCTAssertFalse(*(BOOL *)NativeIvar(view, "_clockStale"), @"GPU/drawable pressure is not suspension");
  XCTAssertEqual(*(CFTimeInterval *)NativeIvar(renderer, "_lastFrameTime"), 1);
  // Resume through the production renderer; elapsed time is retained and capped.
  id<MTLCommandBuffer> recovered = [_queue commandBuffer];
  XCTAssertTrue([renderer drawFrame:1.25 commandBuffer:recovered target:_target slot:1]);
  [recovered commit]; [recovered waitUntilCompleted];
  XCTAssertEqualWithAccuracy(*(float *)NativeIvar(renderer, "_effectTime"), .1, .0001);
  [view pauseRendering];
  [view tick:(CADisplayLink *)[self tickAt:2]];
  XCTAssertTrue(*(BOOL *)NativeIvar(view, "_clockStale"), @"explicit pause must still reset on resume");
  [view stopRendering];
 }
}

- (void)testDecodeDoesNotBlockQueriesDisposeOrInvalidation
{
 for (NSNumber *dispose in @[@NO, @YES]) {
  BlockingImageLoader *loader = [BlockingImageLoader new];
  loader.image = [self loader].image;
  loader.entered = dispatch_semaphore_create(0);
  loader.proceed = dispatch_semaphore_create(0);
  TGSpriteSheet *sheet = [[TGSpriteSheet alloc] initWithLoader:loader gridFrameWidth:2 gridFrameHeight:2];
  dispatch_semaphore_t finished = dispatch_semaphore_create(0), accessed = dispatch_semaphore_create(0);
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
   [sheet ensureLoaded:self->_textures];
   dispatch_semaphore_signal(finished);
  });
  XCTAssertEqual(dispatch_semaphore_wait(loader.entered, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)), 0);
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
   (void)[sheet textureResource]; (void)[sheet frameCount];
   // Another view must not run a duplicate decoder or wait for this load.
   [sheet ensureLoaded:self->_textures];
   if (dispose.boolValue) [sheet dispose]; else [sheet invalidateTexture];
   dispatch_semaphore_signal(accessed);
  });
  long accessResult = dispatch_semaphore_wait(accessed, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC));
  dispatch_semaphore_signal(loader.proceed); // Always release the worker, including failed assertions.
  XCTAssertEqual(accessResult, 0, @"metadata/lifecycle access must not wait for decode");
  XCTAssertEqual(dispatch_semaphore_wait(finished, dispatch_time(DISPATCH_TIME_NOW, 2*NSEC_PER_SEC)), 0);
  if (accessResult != 0) dispatch_semaphore_wait(accessed, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC));
  XCTAssertNil([sheet textureResource], @"an invalidated or disposed load must not publish");
  XCTAssertEqual(loader.loads, 1);
  XCTAssertEqual([sheet ensureLoaded:_textures], !dispose.boolValue);
  XCTAssertEqual(loader.loads, dispose.boolValue ? 1 : 2);
 }
}

- (void)testGpuSlotPressureRemainsVisibleInDroppedFrameCount
{
	TGScene *scene = [TGScene new];
	scene.stats.enabled = YES;
	TGSceneRenderer *renderer = [[TGSceneRenderer alloc] initWithScene:scene viewProxy:nil];
	[renderer surfaceCreated];
	EmptyDrawableView *view = [self scheduledView:renderer];
	*(CFTimeInterval *)NativeIvar(view, "_previousDisplayTimestamp") = 1;
	dispatch_semaphore_t __unsafe_unretained *slots =
		(dispatch_semaphore_t __unsafe_unretained *)NativeIvar(view, "_slots");
	dispatch_semaphore_wait(slots[0], DISPATCH_TIME_NOW);
	[view tick:(CADisplayLink *)[self tickAt:1.10]];
	dispatch_semaphore_signal(slots[0]);
	[view tick:(CADisplayLink *)[self tickAt:1.15]];
	TGFrameStatsSnapshot stats = [scene.stats closeWindow:CACurrentMediaTime()];
	XCTAssertEqual(stats.droppedFrames, 8);
	[view stopRendering];
}
- (void)testMultipleCommandFailuresAndMissingDrawableAreCountedSeparately
{
	TGScene *scene = [TGScene new];
	scene.stats.enabled = YES;
	TGSceneRenderer *renderer = [[TGSceneRenderer alloc] initWithScene:scene viewProxy:nil];
	[renderer surfaceCreated];
	EmptyDrawableView *view = [self scheduledView:renderer];
	id completion = object_getIvar(view, class_getInstanceVariable([TGMetalView class], "_completion"));
	atomic_store((atomic_uint *)NativeIvar(completion, "failures"), 2);
	[view tick:(CADisplayLink *)[self tickAt:1]];
	TGFrameStatsSnapshot stats = [scene.stats closeWindow:CACurrentMediaTime()];
	XCTAssertEqual(stats.presentFailures, 3);
	[view stopRendering];
}

- (void)testDrawableAcquisitionTimeIsReportedAsPresentationCost
{
	TGScene *scene = [TGScene new];
	scene.stats.enabled = YES;
	TGSceneRenderer *renderer = [[TGSceneRenderer alloc] initWithScene:scene viewProxy:nil];
	[renderer surfaceCreated];
	EmptyDrawableView *view = [self scheduledView:renderer];
	((EmptyDrawableLayer *)view.layer).acquisitionDelay = .04;
	[view tick:(CADisplayLink *)[self tickAt:1]];
	TGFrameStatsSnapshot stats = [scene.stats closeWindow:CACurrentMediaTime()];
	XCTAssertGreaterThanOrEqual(stats.averagePresentMs, 30);
	[view stopRendering];
}
@end
