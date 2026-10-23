#import "TGScreenOverlay.h"
#import "TGSprite.h"
#import "TGSpriteBatch.h"
#import "TGTextureManager.h"
#import <OpenGLES/EAGL.h>
#import <OpenGLES/ES2/glext.h>
#import <XCTest/XCTest.h>

// Offscreen tests use the production geometry, shaders and texture upload.
// Expected colors are hand-derived premultiplied blend results, tolerance 2/255.
@interface RendererTests : XCTestCase
@end
@implementation RendererTests
{
	EAGLContext *_context;
	GLuint _framebuffer, _color;
	TGSpriteBatch *_batch;
	TGTextureManager *_textures;
	TGScreenOverlay *_overlay;
}
- (void)setUp
{
	_context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
	XCTAssertTrue([EAGLContext setCurrentContext:_context]);
	glGenFramebuffers(1, &_framebuffer);
	glBindFramebuffer(GL_FRAMEBUFFER, _framebuffer);
	glGenRenderbuffers(1, &_color);
	glBindRenderbuffer(GL_RENDERBUFFER, _color);
	glRenderbufferStorage(GL_RENDERBUFFER, GL_RGBA8_OES, 64, 64);
	glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, _color);
	XCTAssertEqual(glCheckFramebufferStatus(GL_FRAMEBUFFER), (GLenum)GL_FRAMEBUFFER_COMPLETE);
	glViewport(0, 0, 64, 64);
	_batch = [TGSpriteBatch new];
	[_batch createGLResources];
	_textures = [TGTextureManager new];
	_overlay = [TGScreenOverlay new];
	[_overlay surfaceChangedWithWidth:64 height:64];
}
- (void)tearDown
{
	glDeleteFramebuffers(1, &_framebuffer);
	glDeleteRenderbuffers(1, &_color);
	[EAGLContext setCurrentContext:nil];
	_context = nil;
}
- (void)begin
{
	glClearColor(0.2, 0.4, 0.6, 1);
	glClear(GL_COLOR_BUFFER_BIT);
	[_batch begin:_overlay.projection
		screenProjection:_overlay.projection
				 originX:0
				 originY:0
			 screenScale:1
				 travelX:0
				 travelY:0];
}
- (void)assertPixelX:(int)x y:(int)y r:(int)r g:(int)g b:(int)b
{
	uint8_t pixel[4];
	glReadPixels(x, 63 - y, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel);
	XCTAssertEqualWithAccuracy(pixel[0], r, 2);
	XCTAssertEqualWithAccuracy(pixel[1], g, 2);
	XCTAssertEqualWithAccuracy(pixel[2], b, 2);
}
- (void)testTopLeftGeometryAndBlendModes
{
	const int expected[4][3] = {{153, 51, 76}, {179, 102, 153}, {51, 51, 76}, {153, 102, 153}};
	for (int mode = 0; mode < 4; mode++)
	{
		[self begin];
		[_batch setBlendMode:mode];
		TGFrame f = {0, 0, 1, 1, 1, 1};
		[_batch drawFrame:[_textures whiteTexture] frame:f cx:8 cy:8 halfW:8 halfH:8 r:1 g:0 b:0 a:0.5];
		[_batch end];
		[self assertPixelX:4 y:4 r:expected[mode][0] g:expected[mode][1] b:expected[mode][2]];
		[self assertPixelX:4 y:50 r:51 g:102 b:153];
	}
}
- (void)testFlushesKeepOrderAndVertexStorage
{
	[self begin];
	TGFrame f = {0, 0, 1, 1, 1, 1};
	for (int i = 0; i < 1001; i++)
		[_batch drawFrame:[_textures whiteTexture] frame:f cx:8 cy:8 halfW:8 halfH:8 r:1 g:0 b:0 a:1];
	[_batch drawFrame:[_textures whiteTexture] frame:f cx:48 cy:48 halfW:8 halfH:8 r:0 g:1 b:0 a:1];
	[_batch end];
	XCTAssertEqual(_batch.drawCalls, 2);
	[self assertPixelX:4 y:4 r:255 g:0 b:0];
	[self assertPixelX:48 y:48 r:0 g:255 b:0];
}
@end
