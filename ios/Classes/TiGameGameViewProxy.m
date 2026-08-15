#import "TiGameGameViewProxy.h"
#import "TGScene.h"
#import "TGSceneRenderer.h"
#import "TGSprite.h"
#import "TiGameGameView.h"
#import "TiGameSpriteProxy.h"

@implementation TiGameGameViewProxy

- (instancetype)init
{
	if (self = [super init]) {
		_scene = [[TGScene alloc] init];
	}
	return self;
}

- (NSString *)apiName
{
	return @"ti.game.GameView";
}

// Fill the parent by default, like the Android view's autoFill layout
- (TiDimension)defaultAutoWidthBehavior:(id)unused
{
	return TiDimensionAutoFill;
}

- (TiDimension)defaultAutoHeightBehavior:(id)unused
{
	return TiDimensionAutoFill;
}

- (TiGameGameView *)gameView
{
	return [self viewAttached] ? (TiGameGameView *)[self view] : nil;
}

#pragma mark Properties

/** Renders debug overlays (collision box, bounds, anchor) for every sprite. */
- (void)setDebug:(id)value
{
	self.scene.debugAll = [TiUtils boolValue:value def:NO];
}

- (NSNumber *)debug
{
	return @(self.scene.debugAll);
}

- (void)setCameraX:(id)value
{
	self.scene.cameraX = [TiUtils floatValue:value def:0];
}

- (NSNumber *)cameraX
{
	return @(self.scene.cameraX);
}

- (void)setCameraY:(id)value
{
	self.scene.cameraY = [TiUtils floatValue:value def:0];
}

- (NSNumber *)cameraY
{
	return @(self.scene.cameraY);
}

/** Rendered surface size in pixels — the scene coordinate space. */
- (NSNumber *)surfaceWidth
{
	TiGameGameView *view = [self gameView];
	return @(view != nil ? view.renderer.surfaceWidth : 0);
}

- (NSNumber *)surfaceHeight
{
	TiGameGameView *view = [self gameView];
	return @(view != nil ? view.renderer.surfaceHeight : 0);
}

#pragma mark Methods

- (void)add:(id)arg
{
	id value = [arg isKindOfClass:[NSArray class]] ? [arg firstObject] : arg;
	if ([value isKindOfClass:[TiGameSpriteProxy class]]) {
		TiGameSpriteProxy *spriteProxy = value;
		// keep the sprite proxy alive on the JS side while it's in the scene
		[self rememberProxy:spriteProxy];
		[self.scene add:spriteProxy.sprite];
		return;
	}
	[super add:arg];
}

- (void)remove:(id)arg
{
	id value = [arg isKindOfClass:[NSArray class]] ? [arg firstObject] : arg;
	if ([value isKindOfClass:[TiGameSpriteProxy class]]) {
		TiGameSpriteProxy *spriteProxy = value;
		[self.scene remove:spriteProxy.sprite];
		[self forgetProxy:spriteProxy];
		return;
	}
	[super remove:arg];
}

- (void)removeAllSprites:(id)unused
{
	[self.scene clear];
}

/**
 * Native camera follow with a vertical dead-zone: the view scrolls when
 * the sprite rises above `topMargin` (fraction of the surface height,
 * default 0.33) or sinks below `bottomMargin` (default 0.7), clamped to
 * `maxY` (default 0 — never scrolls below the start position).
 */
- (void)follow:(id)args
{
	id first = [args isKindOfClass:[NSArray class]] ? [args firstObject] : args;
	if (![first isKindOfClass:[TiGameSpriteProxy class]]) {
		self.scene.followTarget = nil;
		return;
	}
	NSDictionary *options = ([args isKindOfClass:[NSArray class]] && [args count] > 1
		&& [args[1] isKindOfClass:[NSDictionary class]]) ? args[1] : nil;
	if (options != nil) {
		if (options[@"topMargin"] != nil) {
			self.scene.followTopFraction = [TiUtils floatValue:options[@"topMargin"] def:0.33f];
		}
		if (options[@"bottomMargin"] != nil) {
			self.scene.followBottomFraction = [TiUtils floatValue:options[@"bottomMargin"] def:0.7f];
		}
		if (options[@"maxY"] != nil) {
			self.scene.cameraMaxY = [TiUtils floatValue:options[@"maxY"] def:0];
		}
	}
	self.scene.followTarget = ((TiGameSpriteProxy *)first).sprite;
}

- (void)stopFollow:(id)unused
{
	self.scene.followTarget = nil;
}

/** Manually pause the render loop (also happens on app resign-active). */
- (void)pause:(id)unused
{
	[[self gameView] pauseRendering];
}

- (void)resume:(id)unused
{
	[[self gameView] resumeRendering];
}

@end
