#import "TGGLView.h"
#import "TGSceneRenderer.h"
#import <OpenGLES/EAGL.h>
#import <OpenGLES/EAGLDrawable.h>
#import <OpenGLES/ES2/gl.h>
#import <QuartzCore/QuartzCore.h>
#import <TargetConditionals.h>
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
	NSCondition *_threadCondition;
	CFTimeInterval _previousDisplayTimestamp; // render thread only

	// Cross-thread flags (main writes, render thread reads)
	atomic_bool _running;
	atomic_bool _paused;
	atomic_bool _needsLayout;
	atomic_int _maxFps; // 0 = display default

	BOOL _clockStale;   // render thread only — set while paused
	int _appliedMaxFps; // render thread only — last value applied to the link
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
		// Real devices keep their native Retina drawable. CoreSimulator's
		// translated OpenGL path otherwise rasterizes 3x more pixels per axis
		// than its visible window; use the logical surface there and let Core
		// Animation enlarge pixel art with nearest-neighbour filtering.
#if TARGET_OS_SIMULATOR
		CGFloat renderScale = 1.0f;
#else
		CGFloat renderScale = [UIScreen mainScreen].scale;
#endif
		self.contentScaleFactor = renderScale;
		layer.contentsScale = renderScale;
		layer.magnificationFilter = kCAFilterNearest;

		// Touches are handled by the containing TiUIView (the engine's
		// touch controller), never by this surface
		self.userInteractionEnabled = NO;

		_threadCondition = [[NSCondition alloc] init];
		atomic_init(&_running, false);
		atomic_init(&_paused, false);
		atomic_init(&_needsLayout, true);

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
	[_threadCondition lock];
	if (_renderThread != nil) {
		[_threadCondition unlock];
		return;
	}
	atomic_store(&_running, true);
	NSThread *thread = [[NSThread alloc] initWithTarget:self
											selector:@selector(renderThreadMain)
											  object:nil];
	thread.name = @"ti.game.render";
	thread.qualityOfService = NSQualityOfServiceUserInteractive;
	_renderThread = thread;
	[_threadCondition unlock];
	[thread start];
}

- (void)stopRendering
{
	atomic_store(&_running, false);
	[_threadCondition lock];
	NSThread *thread = _renderThread;
	[_threadCondition unlock];
	if (thread == nil || thread == [NSThread currentThread]) {
		return;
	}

	// NSThread has no join API. The condition is signalled only after the
	// display link, framebuffer and EAGL context have all been released.
	[_threadCondition lock];
	while (_renderThread == thread) {
		[_threadCondition wait];
	}
	[_threadCondition unlock];
}

- (void)pauseRendering
{
	atomic_store(&_paused, true);
}

- (void)resumeRendering
{
	atomic_store(&_paused, false);
}

- (void)setMaxFps:(int)maxFps
{
	atomic_store(&_maxFps, MAX(0, maxFps));
}

// --- Render thread ------------------------------------------------------

- (void)renderThreadMain
{
	@autoreleasepool {
		_context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
		[EAGLContext setCurrentContext:_context];
		[_renderer surfaceCreated];

		_displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
		_appliedMaxFps = atomic_load(&_maxFps);
		[self applyMaxFps:_appliedMaxFps];
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

	[_threadCondition lock];
	if (_renderThread == [NSThread currentThread]) {
		_renderThread = nil;
	}
	[_threadCondition broadcast];
	[_threadCondition unlock];
}

- (void)tick:(CADisplayLink *)link
{
	if (!atomic_load(&_running) || atomic_load(&_paused)) {
		_previousDisplayTimestamp = 0;
		_clockStale = YES;
		return;
	}
	int maxFps = atomic_load(&_maxFps);
	if (maxFps != _appliedMaxFps) {
		_appliedMaxFps = maxFps;
		[self applyMaxFps:maxFps];
	}
	if (_clockStale) {
		// Don't fast-forward the pause gap into the first frame back
		_clockStale = NO;
		[_renderer resetClock];
	}
	if (atomic_exchange(&_needsLayout, false)) {
		[self recreateFramebuffer];
	}
	if (_drawableWidth <= 0 || _drawableHeight <= 0) {
		atomic_store(&_needsLayout, true); // zero-sized — try again next tick
		return;
	}
	// The renderer decides whether this frame is measured; with the debug
	// HUD off and nobody listening for 'performance' not one clock is read
	BOOL measuring = [_renderer isMeasuring];
	// Per-frame pool: the outer runloop pool only drains every few frames,
	// letting snapshot copies from multiple ticks pile up
	@autoreleasepool {
		CFTimeInterval frameStart = measuring ? CACurrentMediaTime() : 0;
		glBindFramebuffer(GL_FRAMEBUFFER, _framebuffer);
		[_renderer drawFrame:link.targetTimestamp];
		CFTimeInterval drawEnd = measuring ? CACurrentMediaTime() : 0;
		glBindRenderbuffer(GL_RENDERBUFFER, _colorRenderbuffer);
		// The swap is the one thing GLSurfaceView hides from the Android
		// twin, which is why present time is an iOS-only HUD row
		BOOL presented = [_context presentRenderbuffer:GL_RENDERBUFFER];
		if (measuring) {
			CFTimeInterval presentEnd = CACurrentMediaTime();
			CFTimeInterval target = link.targetTimestamp - link.timestamp;
			if (target <= 0.0) {
				target = (link.duration > 0.0) ? link.duration : (1.0 / 60.0);
			}
			CFTimeInterval interval = (_previousDisplayTimestamp > 0.0)
				? link.timestamp - _previousDisplayTimestamp : target;
			[_renderer recordFrameCpuMs:(drawEnd - frameStart) * 1000.0
							  presentMs:(presentEnd - drawEnd) * 1000.0
							  presented:presented
							   interval:interval
								 target:target];
		}
	}
	_previousDisplayTimestamp = link.timestamp;
}

- (void)applyMaxFps:(int)maxFps
{
	if (@available(iOS 15.0, *)) {
		// Low minimum keeps the range valid on displays that can't hit the
		// requested rate exactly; preferred pins the cap.
		_displayLink.preferredFrameRateRange = (maxFps > 0)
			? CAFrameRateRangeMake(10.0f, (float)maxFps, (float)maxFps)
			: CAFrameRateRangeDefault;
	} else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
		_displayLink.preferredFramesPerSecond = maxFps;
#pragma clang diagnostic pop
	}
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
