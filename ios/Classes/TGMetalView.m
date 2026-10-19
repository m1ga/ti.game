#import "TGMetalView.h"
#import "TGMetalContext.h"
#import "TGSceneRenderer.h"
#import <QuartzCore/CAMetalLayer.h>
#import <TargetConditionals.h>
#import <stdatomic.h>

// Completion handlers retain this state, never the view, scene or JS proxies.
@interface TGMetalCompletionState : NSObject
{
  @public
	atomic_uint failures;
}
@end
@implementation TGMetalCompletionState
- (instancetype)init
{
	if (self = [super init])
		atomic_init(&failures, 0);
	return self;
}
@end

@implementation TGMetalView
{
	TGSceneRenderer *_renderer;
	TGMetalContext *_context;
	id<MTLCommandQueue> _queue;
	NSThread *_renderThread;
	NSCondition *_threadCondition;
	CADisplayLink *_displayLink;
	dispatch_semaphore_t _slots[3];
	dispatch_group_t _pending;
	TGMetalCompletionState *_completion;
	NSUInteger _nextSlot;
	atomic_bool _running, _paused, _appActive;
	atomic_int _pixelWidth, _pixelHeight, _maxFps;
	int _appliedMaxFps, _drawableWidth, _drawableHeight;
	CFTimeInterval _previousDisplayTimestamp;
	BOOL _clockStale;
}
+ (Class)layerClass
{
	return [CAMetalLayer class];
}
- (instancetype)initWithFrame:(CGRect)frame renderer:(TGSceneRenderer *)renderer
{
	if (self = [super initWithFrame:frame])
	{
		_context = [TGMetalContext sharedContext];
		_queue = [_context.device newCommandQueue];
		if (!_context || !_queue || !renderer)
		{
			NSLog(@"[ERROR] ti.game: cannot initialize Metal view");
			return nil;
		}
		_renderer = renderer;
		CAMetalLayer *layer = (CAMetalLayer *)self.layer;
		layer.device = _context.device;
		layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
		layer.framebufferOnly = YES;
		layer.opaque = YES;
		layer.maximumDrawableCount = 3;
		layer.allowsNextDrawableTimeout = YES;
		layer.magnificationFilter = kCAFilterNearest;
		self.userInteractionEnabled = NO;
		_threadCondition = [NSCondition new];
		_pending = dispatch_group_create();
		_completion = [TGMetalCompletionState new];
		for (int i = 0; i < 3; i++)
			_slots[i] = dispatch_semaphore_create(1);
		atomic_init(&_running, false);
		atomic_init(&_paused, false);
		atomic_init(&_appActive,
					UIApplication.sharedApplication.applicationState == UIApplicationStateActive);
		atomic_init(&_pixelWidth, 0);
		atomic_init(&_pixelHeight, 0);
		atomic_init(&_maxFps, 0);
		[self updateDrawableSize];
		NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
		[center addObserver:self
				   selector:@selector(applicationWillResignActive)
					   name:UIApplicationWillResignActiveNotification
					 object:nil];
		[center addObserver:self
				   selector:@selector(applicationDidBecomeActive)
					   name:UIApplicationDidBecomeActiveNotification
					 object:nil];
	}
	return self;
}
- (void)dealloc
{
	[NSNotificationCenter.defaultCenter removeObserver:self];
	[self stopRendering];
}
- (void)layoutSubviews
{
	[super layoutSubviews];
	[self updateDrawableSize];
}
- (void)didMoveToWindow
{
	[super didMoveToWindow];
	[self updateDrawableSize];
}
- (void)updateDrawableSize
{
#if TARGET_OS_SIMULATOR
	CGFloat scale = 1.0; // baseline policy, matching the previous OpenGL surface
#else
	CGFloat scale = (self.window.screen ?: UIScreen.mainScreen).scale;
#endif
	BOOL scaleChanged = self.contentScaleFactor != scale;
	self.contentScaleFactor = scale;
	CAMetalLayer *layer = (CAMetalLayer *)self.layer;
	layer.contentsScale = scale;
	CGSize size = CGSizeMake(MAX(0, floor(self.bounds.size.width * scale)),
							 MAX(0, floor(self.bounds.size.height * scale)));
	layer.drawableSize = size;
	_renderer.screenScale = (float)scale;
	if (scaleChanged && self.drawableScaleChanged)
		self.drawableScaleChanged(scale);
	atomic_store(&_pixelWidth, (int)size.width);
	atomic_store(&_pixelHeight, (int)size.height);
}
- (void)startRendering
{
	[_threadCondition lock];
	if (_renderThread)
	{
		[_threadCondition unlock];
		return;
	}
	atomic_store(&_running, true);
	_renderThread = [[NSThread alloc] initWithTarget:self selector:@selector(renderThreadMain) object:nil];
	_renderThread.name = @"ti.game.render";
	_renderThread.qualityOfService = NSQualityOfServiceUserInteractive;
	NSThread *thread = _renderThread;
	[_threadCondition unlock];
	[thread start];
}
- (void)stopRendering
{
	atomic_store(&_running, false);
	[_threadCondition lock];
	NSThread *thread = _renderThread;
	if (thread != NSThread.currentThread)
		while (_renderThread == thread && thread)
			[_threadCondition wait];
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
- (void)applicationWillResignActive
{
	atomic_store(&_appActive, false);
}
- (void)applicationDidBecomeActive
{
	atomic_store(&_appActive, true);
}
- (void)setMaxFps:(int)maxFps
{
	atomic_store(&_maxFps, MAX(0, maxFps));
}
- (void)renderThreadMain
{
	@autoreleasepool
	{
		[_renderer surfaceCreated];
		_displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
		_appliedMaxFps = atomic_load(&_maxFps);
		[self applyMaxFps:_appliedMaxFps];
		[_displayLink addToRunLoop:NSRunLoop.currentRunLoop forMode:NSDefaultRunLoopMode];
		while (atomic_load(&_running))
		{
			@autoreleasepool
			{
				[NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode
									   beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
			}
		}
		[_displayLink invalidate];
		_displayLink = nil;
		// Drain asynchronously: the main thread waits for CPU shutdown only.
		// Retain scene resources until the last command completes, without firing bridge events.
		TGSceneRenderer *retiredRenderer = _renderer;
		id<MTLCommandQueue> retiredQueue = _queue;
		dispatch_group_notify(_pending, dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
		  (void)[retiredRenderer class];
		  (void)[retiredQueue label];
		});
	}
	[_threadCondition lock];
	_renderThread = nil;
	[_threadCondition broadcast];
	[_threadCondition unlock];
}
- (void)tick:(CADisplayLink *)link
{
	if (!atomic_load(&_running) || atomic_load(&_paused) || !atomic_load(&_appActive))
	{
		_previousDisplayTimestamp = 0;
		_clockStale = YES;
		return;
	}
	int maxFps = atomic_load(&_maxFps);
	if (maxFps != _appliedMaxFps)
	{
		_appliedMaxFps = maxFps;
		[self applyMaxFps:maxFps];
	}
	int width = atomic_load(&_pixelWidth), height = atomic_load(&_pixelHeight);
	if (width <= 0 || height <= 0)
	{
		_clockStale = YES;
		_previousDisplayTimestamp = 0;
		return;
	}
	if (width != _drawableWidth || height != _drawableHeight)
	{
		_drawableWidth = width;
		_drawableHeight = height;
		[_renderer surfaceChangedWithWidth:width height:height];
	}
	dispatch_semaphore_t slot = _slots[_nextSlot];
	if (dispatch_semaphore_wait(slot, DISPATCH_TIME_NOW) != 0)
	{
		// Freeze simulation, but keep the last measured timestamp so the next
		// sample includes display intervals missed under GPU backpressure.
		_clockStale = YES;
		return;
	}
	@autoreleasepool
	{
		BOOL measuring = [_renderer isMeasuring];
		CFTimeInterval start = measuring ? CACurrentMediaTime() : 0;
		id<CAMetalDrawable> drawable = [(CAMetalLayer *)self.layer nextDrawable];
		id<MTLCommandBuffer> command = drawable ? [_queue commandBuffer] : nil;
		CFTimeInterval acquired = measuring ? CACurrentMediaTime() : 0;
		BOOL encoded = NO;
		if (command && atomic_load(&_running) && atomic_load(&_appActive) && !atomic_load(&_paused))
		{
			if (_clockStale)
			{
				_clockStale = NO;
				[_renderer resetClock];
			}
			// Use actual drawable dimensions when a resize races its acquisition.
			if (drawable.texture.width != _drawableWidth || drawable.texture.height != _drawableHeight)
			{
				_drawableWidth = (int)drawable.texture.width;
				_drawableHeight = (int)drawable.texture.height;
				[_renderer surfaceChangedWithWidth:_drawableWidth height:_drawableHeight];
			}
			encoded = [_renderer drawFrame:link.targetTimestamp
							 commandBuffer:command
									target:drawable.texture
									  slot:_nextSlot];
		}
		CFTimeInterval drawEnd = measuring ? CACurrentMediaTime() : 0;
		encoded = encoded && atomic_load(&_running) && atomic_load(&_appActive) && !atomic_load(&_paused);
		if (encoded)
		{
			dispatch_group_t pending = _pending;
			TGMetalCompletionState *completion = _completion;
			dispatch_group_enter(pending);
			[command addCompletedHandler:^(id<MTLCommandBuffer> completed) {
			  if (completed.status == MTLCommandBufferStatusError)
			  {
				  atomic_fetch_add(&completion->failures, 1);
				  NSLog(@"[ERROR] ti.game: Metal command failed: %@", completed.error);
			  }
			  dispatch_semaphore_signal(slot);
			  dispatch_group_leave(pending);
			}];
			[command presentDrawable:drawable];
			[command commit];
			_nextSlot = (_nextSlot + 1) % 3;
		}
		else
		{
			dispatch_semaphore_signal(slot);
			_clockStale = YES;
			[_renderer resetClock];
		}
		unsigned failures = atomic_exchange(&_completion->failures, 0);
		if (measuring)
		{
			CFTimeInterval end = CACurrentMediaTime();
			CFTimeInterval target = link.targetTimestamp - link.timestamp;
			if (target <= 0)
				target = link.duration > 0 ? link.duration : 1.0 / 60.0;
			CFTimeInterval interval =
				_previousDisplayTimestamp > 0 ? link.timestamp - _previousDisplayTimestamp : target;
			[_renderer recordFrameCpuMs:(drawEnd - acquired) * 1000
							  presentMs:((acquired - start) + (end - drawEnd)) * 1000
							  presented:encoded
						commandFailures:failures
							   interval:interval
								 target:target];
		}
		_previousDisplayTimestamp = measuring ? link.timestamp : 0;
	}
}
- (void)applyMaxFps:(int)maxFps
{
	if (@available(iOS 15.0, *))
	{
		_displayLink.preferredFrameRateRange =
			maxFps > 0 ? CAFrameRateRangeMake(10, maxFps, maxFps) : CAFrameRateRangeDefault;
	}
	else
	{
		_displayLink.preferredFramesPerSecond = maxFps;
	}
}
@end
