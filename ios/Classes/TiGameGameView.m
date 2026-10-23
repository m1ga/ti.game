#import "TiGameGameView.h"
#import "TGMetalView.h"
#import "TGScene.h"
#import "TGSceneRenderer.h"
#import "TGGamepadController.h"
#import "TGTouchController.h"
#import "TiGameGameViewProxy.h"
#import <objc/runtime.h>
#import "TGInputResolver.h"
#import "TGCanvasInput.h"
#import <GameController/GameController.h>

static NSHashTable<TiGameGameView *> *TGActiveGameViews;
static __weak id<TiEvaluator> TGActiveRuntimeContext;
static void (*TGOriginalRebootApp)(id, SEL);

static void TGRebootAppWithGameViewShutdown(id app, SEL command)
{
	[TiGameGameView shutdownAllViews];
	if (TGOriginalRebootApp != NULL) {
		TGOriginalRebootApp(app, command);
	}
}

@interface TiGameGameView ()
+ (BOOL)registerActiveView:(TiGameGameView *)view runtimeContext:(id<TiEvaluator>)context;
+ (void)unregisterActiveView:(TiGameGameView *)view;
@end

@implementation TiGameGameView {
	TGMetalView *_metalView;
	TGTouchController *_touchController;
	__weak id<TiEvaluator> _runtimeContext;
	float _gamepadDeadzone; // held until the controller exists (0 is a valid value)
	float _gamepadStickPress;
	float _gamepadStickRelease;
	BOOL _gamepadDeadzoneSet;
	BOOL _renderingShutdown;
	BOOL _wasAttachedToWindow;
	int _maxFps; // held until the GL view exists
}

+ (void)initialize
{
	if (self == [TiGameGameView class]) {
		TGActiveGameViews = [NSHashTable weakObjectsHashTable];
	}
}

+ (void)installLiveViewRestartHook
{
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		Class tiAppClass = NSClassFromString(@"TiApp");
		SEL rebootSelector = NSSelectorFromString(@"rebootApp");
		Method rebootMethod = class_getInstanceMethod(tiAppClass, rebootSelector);
		if (rebootMethod == NULL) {
			return;
		}
		IMP implementation = method_getImplementation(rebootMethod);
		if (implementation == (IMP)TGRebootAppWithGameViewShutdown) {
			return;
		}
		TGOriginalRebootApp = (void (*)(id, SEL))implementation;
		method_setImplementation(rebootMethod, (IMP)TGRebootAppWithGameViewShutdown);
	});
}

+ (void)activateRuntimeContext:(id<TiEvaluator>)context
{
	NSMutableArray<TiGameGameView *> *staleViews = [NSMutableArray array];
	@synchronized(self) {
		TGActiveRuntimeContext = context;
		for (TiGameGameView *view in TGActiveGameViews) {
			if (view->_runtimeContext != context) {
				[staleViews addObject:view];
			}
		}
		for (TiGameGameView *view in staleViews) {
			[TGActiveGameViews removeObject:view];
		}
	}

	// stopRendering joins the render thread; never hold the registry lock
	// while waiting for it to finish.
	for (TiGameGameView *view in staleViews) {
		[view shutdownRendering];
	}
}

+ (void)shutdownAllViews
{
	[self shutdownViewsForRuntimeContext:nil];
}

+ (void)shutdownViewsForRuntimeContext:(id<TiEvaluator>)context
{
	NSMutableArray<TiGameGameView *> *contextViews = [NSMutableArray array];
	@synchronized(self) {
		for (TiGameGameView *view in TGActiveGameViews) {
			if (context == nil || view->_runtimeContext == context) {
				[contextViews addObject:view];
			}
		}
		for (TiGameGameView *view in contextViews) {
			[TGActiveGameViews removeObject:view];
		}
		if (context == nil || TGActiveRuntimeContext == context) {
			TGActiveRuntimeContext = nil;
		}
	}

	for (TiGameGameView *view in contextViews) {
		[view shutdownRendering];
	}
}

+ (BOOL)registerActiveView:(TiGameGameView *)view runtimeContext:(id<TiEvaluator>)context
{
	@synchronized(self) {
		if (TGActiveRuntimeContext != nil && TGActiveRuntimeContext != context) {
			return NO;
		}
		if (TGActiveRuntimeContext == nil) {
			TGActiveRuntimeContext = context;
		}
		[TGActiveGameViews addObject:view];
		return YES;
	}
}

+ (void)unregisterActiveView:(TiGameGameView *)view
{
	@synchronized(self) {
		[TGActiveGameViews removeObject:view];
	}
}

- (TGMetalView *)metalView
{
	if (_metalView == nil) {
		@synchronized(self) {
			if (_renderingShutdown) {
				return nil;
			}
		}
		_runtimeContext = self.proxy.pageContext;
		BOOL mayStartRendering = [TiGameGameView registerActiveView:self runtimeContext:_runtimeContext];
		if (!mayStartRendering) {
			@synchronized(self) {
				_renderingShutdown = YES;
			}
			return nil;
		}
		TGScene *scene = ((TiGameGameViewProxy *)self.proxy).scene;
		_renderer = [[TGSceneRenderer alloc] initWithScene:scene viewProxy:self.proxy];
		_metalView = [[TGMetalView alloc] initWithFrame:self.bounds renderer:_renderer];
		if (!_metalView) {
			@synchronized(self) { _renderingShutdown = YES; }
			[TiGameGameView unregisterActiveView:self];
			_renderer = nil;
			return nil;
		}
		// The surface is in drawable pixels; the HUD sizes itself in points
		// so it reads the same at 1x and on a 3x Retina drawable
		_renderer.screenScale = (float)_metalView.contentScaleFactor;
		// Touches must be scaled by the drawable's actual scale, not the
		// screen's — the Metal view renders at 1x in the simulator
		_touchController = [[TGTouchController alloc]
			initWithScene:scene
				viewProxy:self.proxy
			 contentScale:_metalView.contentScaleFactor];
		__weak TiGameGameView *weakSelf = self;
		_metalView.drawableScaleChanged = ^(CGFloat scale) {
			TiGameGameView *view = weakSelf;
			if (view) [view->_touchController updateContentScale:scale];
		};
		self.multipleTouchEnabled = YES;
		// Bluetooth game controllers (GameController.framework) — like the
		// Window hook on Android, independent of which view has focus
		_gamepadController = [[TGGamepadController alloc] initWithViewProxy:self.proxy];
		_gamepadController.inputResolver = ((TiGameGameViewProxy *)self.proxy).inputResolver;
		[self addGestureRecognizer:[[TGCanvasInput alloc] initWithResolver:_gamepadController.inputResolver]];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(releaseInput) name:UIApplicationWillResignActiveNotification object:nil];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(inputWindowResigned:) name:UIWindowDidResignKeyNotification object:nil];
		if (@available(iOS 14.0,*)) {
			[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(releaseKeyboardInput) name:GCKeyboardDidDisconnectNotification object:nil];
			[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(releasePointerInput) name:GCMouseDidDisconnectNotification object:nil];
		}
		_gamepadController.deadzone = _gamepadDeadzoneSet ? _gamepadDeadzone : 0.2f;
		[self applyStickThresholds];
		[_metalView setMaxFps:_maxFps];
		[self addSubview:_metalView];
		[_metalView startRendering];
	}
	return _metalView;
}

- (void)dealloc
{
	[self shutdownRendering];
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)frameSizeChanged:(CGRect)frame bounds:(CGRect)bounds
{
	[super frameSizeChanged:frame bounds:bounds];
	[TiUtils setView:[self metalView] positionRect:bounds];
}

- (void)didMoveToWindow
{
	[super didMoveToWindow];
	if (self.window != nil) {
		_wasAttachedToWindow = YES;
	} else if (_wasAttachedToWindow) {
		// Normal view removal must not rely on dealloc; Titanium may retain
		// the proxy hierarchy beyond the visible window's lifetime.
		[self shutdownRendering];
	}
}

- (void)pauseRendering
{
	@synchronized(self) {
		if (!_renderingShutdown) {
			[_metalView pauseRendering];
		}
	}
}

- (void)resumeRendering
{
	@synchronized(self) {
		if (!_renderingShutdown) {
			[_metalView resumeRendering];
		}
	}
}

- (void)shutdownRendering
{
	TGMetalView *metalView;
	@synchronized(self) {
		if (_renderingShutdown) {
			return;
		}
		_renderingShutdown = YES;
		metalView = _metalView;
	}

	[TiGameGameView unregisterActiveView:self];
	[self releaseInput];
	[metalView stopRendering];
	[_gamepadController shutdown];

	void (^releaseViewResources)(void) = ^{
		[metalView removeFromSuperview];
		@synchronized(self) {
			if (_metalView == metalView) {
				_metalView = nil;
				_touchController = nil;
				_gamepadController = nil;
				_renderer = nil;
			}
		}
	};
	if ([NSThread isMainThread]) {
		releaseViewResources();
	} else {
		dispatch_async(dispatch_get_main_queue(), releaseViewResources);
	}
}

- (BOOL)canBecomeFirstResponder { return !_renderingShutdown; }
- (void)focusInput { if (!_renderingShutdown) [self becomeFirstResponder]; }
- (void)releaseKeyboardInput { [((TiGameGameViewProxy *)self.proxy).inputResolver releaseDevice:@"keyboard" identity:@"keyboard"]; }
- (void)releasePointerInput { [((TiGameGameViewProxy *)self.proxy).inputResolver releaseDevice:@"mouse" identity:@"pointer"]; }
- (void)inputWindowResigned:(NSNotification *)notification { if (notification.object == self.window) [self releaseInput]; }
- (void)releaseInput { [((TiGameGameViewProxy *)self.proxy).inputResolver releaseAll]; }
- (BOOL)resignFirstResponder
{
	BOOL result = [super resignFirstResponder];
	if (result) [self releaseInput];
	return result;
}
- (NSSet<UIPress *> *)handleKeys:(NSSet<UIPress *> *)presses down:(BOOL)down
{
	NSMutableSet *unhandled = [presses mutableCopy];
	if (@available(iOS 13.4,*)) {
		if (!self.isFirstResponder) return unhandled;
		TGInputResolver *resolver = ((TiGameGameViewProxy *)self.proxy).inputResolver;
		for (UIPress *press in presses) {
			UIKey *key = press.key;
			NSString *code = key ? TGKeyboardCode(key.keyCode) : nil;
			if (!code) continue;
			[unhandled removeObject:press];
			if (![resolver transition:@"keyboard" identity:@"keyboard" code:code down:down]) continue;
			NSString *event = down ? @"keydown" : @"keyup";
			if ([self.proxy _hasListeners:event]) [self.proxy fireEvent:event withObject:@{
				@"code":code, @"character":key.characters ?: @"", @"modifiers":@{
					@"shift":@((key.modifierFlags & UIKeyModifierShift)!=0), @"control":@((key.modifierFlags & UIKeyModifierControl)!=0),
					@"alt":@((key.modifierFlags & UIKeyModifierAlternate)!=0), @"meta":@((key.modifierFlags & UIKeyModifierCommand)!=0)}}];
		}
	}
	return unhandled;
}
- (void)pressesBegan:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event { [super pressesBegan:[self handleKeys:presses down:YES] withEvent:event]; }
- (void)pressesEnded:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event { [super pressesEnded:[self handleKeys:presses down:NO] withEvent:event]; }
- (void)pressesCancelled:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event { [self releaseKeyboardInput];[super pressesCancelled:presses withEvent:event]; }

#pragma mark Properties

/** Consumed by the GL clear color; never becomes a UIView background. */
- (void)setBackgroundColor_:(id)value
{
	TiColor *tiColor = [TiUtils colorValue:value];
	if (tiColor == nil) {
		return; // leave previous clear color
	}
	CGFloat r = 0, g = 0, b = 0, a = 1;
	[[tiColor color] getRed:&r green:&g blue:&b alpha:&a];
	TGScene *scene = ((TiGameGameViewProxy *)self.proxy).scene;
	scene.bgRed = (float)r;
	scene.bgGreen = (float)g;
	scene.bgBlue = (float)b;
	scene.bgAlpha = (float)a;
}

/** Radial dead zone for the analog sticks, 0..0.9 (default 0.2). */
- (void)setGamepadDeadzone_:(id)value
{
	_gamepadDeadzone = MAX(0.0f, MIN(0.9f, [TiUtils floatValue:value def:0.2f]));
	_gamepadDeadzoneSet = YES;
	_gamepadController.deadzone = _gamepadDeadzone;
}

/** Left-stick deflection that presses a direction (default 0.5) and the
 *  lower value that releases it (default 0.4) — twin of GameViewProxy. */
- (void)setGamepadStickPress_:(id)value
{
	_gamepadStickPress = [TiUtils floatValue:value def:0.5f];
	[self applyStickThresholds];
}

- (void)setGamepadStickRelease_:(id)value
{
	_gamepadStickRelease = [TiUtils floatValue:value def:0.4f];
	[self applyStickThresholds];
}

- (void)applyStickThresholds
{
	if (_gamepadController == nil) {
		return;
	}
	float press = MAX(0.1f, MIN(0.95f, _gamepadStickPress > 0 ? _gamepadStickPress : 0.5f));
	float release = _gamepadStickRelease > 0 ? _gamepadStickRelease : 0.4f;
	_gamepadController.stickPress = press;
	_gamepadController.stickRelease = MAX(0.05f, MIN(press, release));
}

/** Frame rate cap (e.g. 60 on a 120 Hz ProMotion display); 0 = display default. */
- (void)setMaxFps_:(id)value
{
	_maxFps = [TiUtils intValue:value def:0];
	[_metalView setMaxFps:_maxFps];
}

#pragma mark Touch handling

// The engine's TGTouchController owns every touch on this view — standard
// Titanium touch/click events are not supported here (same rule as the
// registerForTouch override on Android). Overlaid sibling views (buttons,
// labels) receive their own touches normally.

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
	if (@available(iOS 13.4,*)) { if (touches.anyObject.type == UITouchTypeIndirectPointer && [((TiGameGameViewProxy *)self.proxy).inputResolver hasBindings:@"mouse"]) return; }
	[self metalView]; // make sure the controller exists
	[_touchController touchesBegan:touches inView:self];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
	if (@available(iOS 13.4,*)) { if (touches.anyObject.type == UITouchTypeIndirectPointer && [((TiGameGameViewProxy *)self.proxy).inputResolver hasBindings:@"mouse"]) return; }
	[_touchController touchesMoved:touches inView:self];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
	if (@available(iOS 13.4,*)) { if (touches.anyObject.type == UITouchTypeIndirectPointer && [((TiGameGameViewProxy *)self.proxy).inputResolver hasBindings:@"mouse"]) return; }
	[_touchController touchesEnded:touches inView:self];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
	if (@available(iOS 13.4,*)) { if (touches.anyObject.type == UITouchTypeIndirectPointer && [((TiGameGameViewProxy *)self.proxy).inputResolver hasBindings:@"mouse"]) return; }
	[_touchController touchesCancelled:touches inView:self];
}

@end
