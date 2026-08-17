#import "TiGameGameViewProxy.h"
#import "TGPostEffect.h"
#import "TGScene.h"
#import "TGSceneRenderer.h"
#import "TGSprite.h"
#import "TiGameEmitterProxy.h"
#import "TiGameGameView.h"
#import "TiGameRopeProxy.h"
#import "TiGameSpriteProxy.h"
#import <float.h>

@implementation TiGameGameViewProxy {
	NSDictionary *_cameraBoundsDict;
	NSString *_cameraTint;
}

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

#pragma mark Fullscreen camera effects

/** 'none', 'tint' or 'glitch' — applied to the whole rendered scene. */
- (void)setCameraEffect:(id)value
{
	NSString *name = [TiUtils stringValue:value];
	if ([@"tint" isEqualToString:name]) {
		self.scene.cameraEffect = TGPostEffectTint;
	} else if ([@"glitch" isEqualToString:name]) {
		self.scene.cameraEffect = TGPostEffectGlitch;
	} else {
		self.scene.cameraEffect = TGPostEffectNone;
	}
}

- (NSString *)cameraEffect
{
	switch (self.scene.cameraEffect) {
		case TGPostEffectTint:
			return @"tint";
		case TGPostEffectGlitch:
			return @"glitch";
		default:
			return @"none";
	}
}

/** Tint color for the 'tint' effect, e.g. '#3f6' or '#33ff66'. */
- (void)setCameraTint:(id)value
{
	_cameraTint = [TiUtils stringValue:value];
	TiColor *tiColor = [TiUtils colorValue:value];
	if (tiColor == nil) {
		self.scene.effectTintR = 1.0f;
		self.scene.effectTintG = 1.0f;
		self.scene.effectTintB = 1.0f;
		return;
	}
	CGFloat r = 1, g = 1, b = 1, a = 1;
	[[tiColor color] getRed:&r green:&g blue:&b alpha:&a];
	self.scene.effectTintR = (float)r;
	self.scene.effectTintG = (float)g;
	self.scene.effectTintB = (float)b;
}

- (NSString *)cameraTint
{
	return _cameraTint;
}

/** Effect strength 0..1 (tint mix / glitch amount). */
- (void)setCameraEffectIntensity:(id)value
{
	self.scene.effectIntensity = [TiUtils floatValue:value def:1];
}

- (NSNumber *)cameraEffectIntensity
{
	return @(self.scene.effectIntensity);
}

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

/** Zoom, anchored on the view center (1 = no zoom, 2 = 2x). */
- (void)setCameraScale:(id)value
{
	self.scene.cameraScale = MAX(0.05f, [TiUtils floatValue:value def:1]);
}

- (NSNumber *)cameraScale
{
	return @(self.scene.cameraScale);
}

/** Global time multiplier: 1 = normal, 0.5 = slow motion, 0 freezes
 *  the whole scene while rendering and touch keep running (pause
 *  menus, hit-stop). Negative values clamp to 0. */
- (void)setTimeScale:(id)value
{
	self.scene.timeScale = MAX(0.0f, [TiUtils floatValue:value def:1]);
}

- (NSNumber *)timeScale
{
	return @(self.scene.timeScale);
}

/** Clamps the visible rect into a world rect; null removes the bounds. */
- (void)setCameraBounds:(id)value
{
	if (![value isKindOfClass:[NSDictionary class]]) {
		_cameraBoundsDict = nil;
		self.scene.cameraBoundsEnabled = NO;
		return;
	}
	NSDictionary *bounds = value;
	_cameraBoundsDict = bounds;
	self.scene.boundsMinX = (bounds[@"minX"] != nil)
		? [TiUtils floatValue:bounds[@"minX"] def:0] : -FLT_MAX;
	self.scene.boundsMinY = (bounds[@"minY"] != nil)
		? [TiUtils floatValue:bounds[@"minY"] def:0] : -FLT_MAX;
	self.scene.boundsMaxX = (bounds[@"maxX"] != nil)
		? [TiUtils floatValue:bounds[@"maxX"] def:0] : FLT_MAX;
	self.scene.boundsMaxY = (bounds[@"maxY"] != nil)
		? [TiUtils floatValue:bounds[@"maxY"] def:0] : FLT_MAX;
	self.scene.cameraBoundsEnabled = YES;
}

- (id)cameraBounds
{
	return _cameraBoundsDict;
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

- (void)collectGameObjects:(id)value
				 proxies:(NSMutableArray *)proxies
				 sprites:(NSMutableArray *)sprites
			 emitters:(NSMutableArray *)emitters
				ropes:(NSMutableArray *)ropes
{
	if ([value isKindOfClass:[NSArray class]]) {
		for (id item in value) {
			[self collectGameObjects:item proxies:proxies sprites:sprites emitters:emitters ropes:ropes];
		}
		return;
	}
	if ([value isKindOfClass:[TiGameSpriteProxy class]]) {
		[proxies addObject:value];
		[sprites addObject:((TiGameSpriteProxy *)value).sprite];
	} else if ([value isKindOfClass:[TiGameEmitterProxy class]]) {
		[proxies addObject:value];
		[emitters addObject:((TiGameEmitterProxy *)value).emitter];
	} else if ([value isKindOfClass:[TiGameRopeProxy class]]) {
		[proxies addObject:value];
		[ropes addObject:((TiGameRopeProxy *)value).rope];
	}
}

- (void)add:(id)arg
{
	NSMutableArray *proxies = [NSMutableArray array];
	NSMutableArray *sprites = [NSMutableArray array];
	NSMutableArray *emitters = [NSMutableArray array];
	NSMutableArray *ropes = [NSMutableArray array];
	[self collectGameObjects:arg proxies:proxies sprites:sprites emitters:emitters ropes:ropes];

	if (proxies.count > 0) {
		// Keep every proxy alive on the JS side while its native object is in the scene.
		for (id proxy in proxies) {
			[self rememberProxy:proxy];
		}
		[self.scene addSprites:sprites emitters:emitters ropes:ropes];
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
	if ([value isKindOfClass:[TiGameEmitterProxy class]]) {
		TiGameEmitterProxy *emitterProxy = value;
		[self.scene removeEmitter:emitterProxy.emitter];
		[self forgetProxy:emitterProxy];
		return;
	}
	if ([value isKindOfClass:[TiGameRopeProxy class]]) {
		TiGameRopeProxy *ropeProxy = value;
		[self.scene removeRope:ropeProxy.rope];
		[self forgetProxy:ropeProxy];
		return;
	}
	[super remove:arg];
}

- (void)removeAllSprites:(id)unused
{
	[self.scene clear];
}

/**
 * Native camera follow with dead-zones — see the Android twin for the
 * full option list (topMargin/bottomMargin/maxY vertical, leftMargin/
 * rightMargin enable horizontal, smoothing eases the camera). Each call
 * resets unspecified options to their defaults.
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
	self.scene.followTopFraction = 0.33f;
	self.scene.followBottomFraction = 0.7f;
	self.scene.followLeftFraction = -1.0f;
	self.scene.followRightFraction = 0.65f;
	self.scene.followSmoothing = 0.0f;
	self.scene.cameraMaxY = 0.0f;
	if (options != nil) {
		if (options[@"topMargin"] != nil) {
			self.scene.followTopFraction = [TiUtils floatValue:options[@"topMargin"] def:0.33f];
		}
		if (options[@"bottomMargin"] != nil) {
			self.scene.followBottomFraction = [TiUtils floatValue:options[@"bottomMargin"] def:0.7f];
		}
		BOOL horizontal = NO;
		if (options[@"leftMargin"] != nil) {
			self.scene.followLeftFraction = [TiUtils floatValue:options[@"leftMargin"] def:0.35f];
			horizontal = YES;
		}
		if (options[@"rightMargin"] != nil) {
			self.scene.followRightFraction = [TiUtils floatValue:options[@"rightMargin"] def:0.65f];
			horizontal = YES;
		}
		if (horizontal && self.scene.followLeftFraction < 0.0f) {
			self.scene.followLeftFraction = 0.35f;
		}
		if (options[@"smoothing"] != nil) {
			self.scene.followSmoothing = [TiUtils floatValue:options[@"smoothing"] def:0];
		}
		if (options[@"maxY"] != nil) {
			self.scene.cameraMaxY = [TiUtils floatValue:options[@"maxY"] def:0];
		}
	}
	self.scene.followTarget = ((TiGameSpriteProxy *)first).sprite;
}

/** Camera shake: gameView.shake({ strength: 14, duration: 400 }). */
- (void)shake:(id)args
{
	NSDictionary *options = ([args isKindOfClass:[NSArray class]] ? [args firstObject] : args);
	if (![options isKindOfClass:[NSDictionary class]]) {
		options = nil;
	}
	float strength = [TiUtils floatValue:options[@"strength"] def:12];
	float duration = [TiUtils floatValue:options[@"duration"] def:400];
	[self.scene shakeWithStrength:strength duration:duration / 1000.0f];
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
