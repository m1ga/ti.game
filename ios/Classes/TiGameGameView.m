#import "TiGameGameView.h"
#import "TGGLView.h"
#import "TGScene.h"
#import "TGSceneRenderer.h"
#import "TGTouchController.h"
#import "TiGameGameViewProxy.h"

@implementation TiGameGameView {
	TGGLView *_glView;
	TGTouchController *_touchController;
}

- (TGGLView *)glView
{
	if (_glView == nil) {
		TGScene *scene = ((TiGameGameViewProxy *)self.proxy).scene;
		_renderer = [[TGSceneRenderer alloc] initWithScene:scene viewProxy:self.proxy];
		_glView = [[TGGLView alloc] initWithFrame:self.bounds renderer:_renderer];
		_touchController = [[TGTouchController alloc]
			initWithScene:scene
				viewProxy:self.proxy
			 contentScale:[UIScreen mainScreen].scale];
		self.multipleTouchEnabled = YES;
		[self addSubview:_glView];
		[_glView startRendering];
	}
	return _glView;
}

- (void)dealloc
{
	[_glView stopRendering];
}

- (void)frameSizeChanged:(CGRect)frame bounds:(CGRect)bounds
{
	[super frameSizeChanged:frame bounds:bounds];
	[TiUtils setView:[self glView] positionRect:bounds];
}

- (void)pauseRendering
{
	[_glView pauseRendering];
}

- (void)resumeRendering
{
	[_glView resumeRendering];
}

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

#pragma mark Touch handling

// The engine's TGTouchController owns every touch on this view — standard
// Titanium touch/click events are not supported here (same rule as the
// registerForTouch override on Android). Overlaid sibling views (buttons,
// labels) receive their own touches normally.

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
	[self glView]; // make sure the controller exists
	[_touchController touchesBegan:touches inView:self];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
	[_touchController touchesMoved:touches inView:self];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
	[_touchController touchesEnded:touches inView:self];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
	[_touchController touchesCancelled:touches inView:self];
}

@end
