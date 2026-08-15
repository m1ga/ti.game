#import "TGGLView.h"
#import "TGSceneRenderer.h"
#import <OpenGLES/EAGL.h>
#import <OpenGLES/EAGLDrawable.h>
#import <OpenGLES/ES2/gl.h>
#import <QuartzCore/QuartzCore.h>
#import <stdatomic.h>

@implementation TGGLView {
	TGSceneRenderer *_renderer;
	NSThread *_renderThread;
	EAGLContext *_context;      // render thread only
	CADisplayLink *_displayLink; // render thread only
	GLuint _framebuffer;
	GLuint _colorRenderbuffer;
	GLint _drawableWidth;
	GLint _drawableHeight;

	// Cross-thread flags (main writes, render thread reads)
	atomic_bool _running;
	atomic_bool _paused;
	atomic_bool _needsLayout;
}

+ (Class)layerClass
{
	return [CAEAGLLayer class];
}

- (instancetype)initWithFrame:(CGRect)frame renderer:(TGSceneRenderer *)renderer
{
	if (self = [super initWithFrame:frame]) {
		_renderer = renderer;

		CAEAGLLayer *layer = (CAEAGLLayer *)self.layer;
		layer.opaque = YES;
		layer.drawableProperties = @{
			kEAGLDrawablePropertyRetainedBacking: @NO,
			kEAGLDrawablePropertyColorFormat: kEAGLColorFormatRGBA8
		};
		// Scene units are surface pixels, like Android — render at native scale
		self.contentScaleFactor = [UIScreen mainScreen].scale;
		layer.contentsScale = [UIScreen mainScreen].scale;

		// Touches are handled by the containing TiUIView (the engine's
		// touch controller), never by this surface
		self.userInteractionEnabled = NO;

		atomic_store(&_needsLayout, true);

		// GL in the background kills the app — stop the loop the moment the
		// app resigns active, resume when it becomes active again
		NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
		[center addObserver:self selector:@selector(pauseRendering)
					   name:UIApplicationWillResignActiveNotification object:nil];
		[center addObserver:self selector:@selector(resumeRendering)
					   name:UIApplicationDidBecomeActiveNotification object:nil];
	}
	return self;
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[self stopRendering];
}

- (void)layoutSubviews
{
	[super layoutSubviews];
	atomic_store(&_needsLayout, true);
}

- (void)startRendering
{
	if (_renderThread != nil) {
		return;
	}
	atomic_store(&_running, true);
	_renderThread = [[NSThread alloc] initWithTarget:self
											selector:@selector(renderThreadMain)
											  object:nil];
	_renderThread.name = @"ti.game.render";
	[_renderThread start];
}

- (void)stopRendering
{
	atomic_store(&_running, false);
	_renderThread = nil;
}

- (void)pauseRendering
{
	atomic_store(&_paused, true);
}

- (void)resumeRendering
{
	atomic_store(&_paused, false);
}

// --- Render thread ------------------------------------------------------

- (void)renderThreadMain
{
	@autoreleasepool {
		_context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
		[EAGLContext setCurrentContext:_context];
		[_renderer surfaceCreated];

		_displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
		[_displayLink addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];

		while (atomic_load(&_running)) {
			@autoreleasepool {
				[[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
										 beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
			}
		}

		[_displayLink invalidate];
		_displayLink = nil;
		[self destroyFramebuffer];
		[EAGLContext setCurrentContext:nil];
		_context = nil;
	}
}

- (void)tick:(CADisplayLink *)link
{
	if (!atomic_load(&_running) || atomic_load(&_paused)) {
		return;
	}
	if (atomic_exchange(&_needsLayout, false)) {
		[self recreateFramebuffer];
	}
	if (_drawableWidth <= 0 || _drawableHeight <= 0) {
		atomic_store(&_needsLayout, true); // zero-sized — try again next tick
		return;
	}
	glBindFramebuffer(GL_FRAMEBUFFER, _framebuffer);
	[_renderer drawFrame];
	glBindRenderbuffer(GL_RENDERBUFFER, _colorRenderbuffer);
	[_context presentRenderbuffer:GL_RENDERBUFFER];
}

- (void)recreateFramebuffer
{
	if (_framebuffer == 0) {
		glGenFramebuffers(1, &_framebuffer);
		glGenRenderbuffers(1, &_colorRenderbuffer);
	}
	glBindFramebuffer(GL_FRAMEBUFFER, _framebuffer);
	glBindRenderbuffer(GL_RENDERBUFFER, _colorRenderbuffer);
	// Allocates the color buffer from the layer at its current size
	[_context renderbufferStorage:GL_RENDERBUFFER fromDrawable:(CAEAGLLayer *)self.layer];
	glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
		GL_RENDERBUFFER, _colorRenderbuffer);
	glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &_drawableWidth);
	glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &_drawableHeight);
	if (_drawableWidth > 0 && _drawableHeight > 0) {
		[_renderer surfaceChangedWithWidth:_drawableWidth height:_drawableHeight];
	}
}

- (void)destroyFramebuffer
{
	if (_framebuffer != 0) {
		glDeleteFramebuffers(1, &_framebuffer);
		glDeleteRenderbuffers(1, &_colorRenderbuffer);
		_framebuffer = 0;
		_colorRenderbuffer = 0;
	}
}

@end
