#import "TiGameGameViewProxy.h"
#import "TGBitmapFont.h"
#import "TGDebugHud.h"
#import "TGFrameStats.h"
#import "TGPostEffect.h"
#import "TGScene.h"
#import "TGSceneRenderer.h"
#import "TGScreenOverlay.h"
#import "TGSprite.h"
#import "TiGameEmitterProxy.h"
#import "TiGameFontProxy.h"
#import "TiGameGameView.h"
#import "TiGameRopeProxy.h"
#import "TiGameSpriteProxy.h"
#import <float.h>
#import "TGValues.h"

@interface TiGameGameViewProxy () <TGSceneTimerListener>
@end

@implementation TiGameGameViewProxy {
	NSDictionary *_cameraBoundsDict;
	NSString *_cameraTint;
	NSMutableDictionary<NSNumber *, KrollCallback *> *_timerCallbacks; // guarded by @synchronized(_timerCallbacks)
}

- (instancetype)init
{
	if (self = [super init]) {
		_scene = [[TGScene alloc] init];
		_timerCallbacks = [NSMutableDictionary dictionary];
		_scene.timerListener = self;
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

- (void)viewWillDetach
{
	[[self gameView] shutdownRendering];
	[super viewWillDetach];
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
	self.scene.effectIntensity = [TGValues ratio:value fallback:1];
}

- (NSNumber *)cameraEffectIntensity
{
	return @(self.scene.effectIntensity);
}

// Developer aids, both off by default:
//   debug: true                        collision shapes for every sprite
//   debug: { hitbox: true }            the same, spelled out
//   debug: { hud: true }               performance HUD in the default corner
//   debug: { hud: 'topRight' }         ...in the corner you pick
//   debug: { hud: true, hudFont: f }   ...in the game's own typeface
// The HUD key name is not settled with the maintainer yet; it appears
// here and in the Android twin, nowhere else.
static NSString *const kDebugHitboxKey = @"hitbox";
static NSString *const kDebugHudKey = @"hud";
static NSString *const kDebugHudFontKey = @"hudFont";

- (void)setDebug:(id)value
{
	if ([value isKindOfClass:[NSDictionary class]]) {
		NSDictionary *options = value;
		self.scene.debugAll = [TiUtils boolValue:options[kDebugHitboxKey] def:NO];
		[self applyHud:options[kDebugHudKey]];
		id fontValue = options[kDebugHudFontKey];
		self.scene.hud.font = [fontValue isKindOfClass:[TiGameFontProxy class]]
			? ((TiGameFontProxy *)fontValue).font : nil;
	} else {
		// debug: true — the shorthand that predates the object form
		self.scene.debugAll = [TiUtils boolValue:value def:NO];
		[self applyHud:nil];
		self.scene.hud.font = nil;
	}
	[self refreshStats];
}

/**
 * Reads back the normalized form, whichever form was written:
 * { hitbox: <boolean>, hud: false | 'topLeft' | ... }.
 */
- (id)debug
{
	TGDebugHud *hud = self.scene.hud;
	return @{
		kDebugHitboxKey: @(self.scene.debugAll),
		kDebugHudKey: hud.enabled ? (id) [TGScreenOverlay cornerName:hud.corner] : (id) @NO
	};
}

- (void)applyHud:(id)value
{
	TGDebugHud *hud = self.scene.hud;
	if (value == nil || value == [NSNull null]) {
		hud.enabled = NO;
		return;
	}
	if ([value isKindOfClass:[NSString class]]) {
		hud.corner = [TGScreenOverlay cornerFromName:value fallback:TGOverlayCornerTopLeft];
		hud.enabled = YES;
		return;
	}
	hud.enabled = [TiUtils boolValue:value def:NO];
}

// Measuring costs nothing while nobody is looking: the flag only goes up
// for the HUD or for a live 'performance' listener. TiProxy has no
// listener-added hook of its own (the one in TiProxyDelegate belongs to
// the view), so the two JS entry points are where the state is refreshed —
// the Android twin overrides eventListenerAdded/Removed instead.
- (void)refreshStats
{
	self.scene.stats.enabled = self.scene.hud.enabled || [self _hasListeners:@"performance"];
}

- (void)addEventListener:(NSArray *)args
{
	[super addEventListener:args];
	[self refreshStats];
}

- (void)removeEventListener:(NSArray *)args
{
	[super removeEventListener:args];
	[self refreshStats];
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
	self.scene.cameraScale = MAX(0.05f, [TGValues ratio:value fallback:1]);
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
	self.scene.timeScale = MAX(0.0f, [TGValues ratio:value fallback:1]);
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

#pragma mark Game-clock timers

/**
 * gameView.after(ms, callback): runs the callback once after `ms` of
 * game time — it stretches with slow motion and freezes at timeScale 0,
 * unlike setTimeout. Returns an id for cancelTimer(). Without a
 * callback, the view fires a 'timer' event with the id.
 */
- (NSNumber *)after:(id)args
{
	return @([self addGameTimer:args repeats:NO]);
}

/** gameView.every(ms, callback): like after(), repeating until cancelled. */
- (NSNumber *)every:(id)args
{
	return @([self addGameTimer:args repeats:YES]);
}

- (void)cancelTimer:(id)args
{
	id first = [args isKindOfClass:[NSArray class]] ? [args firstObject] : args;
	int timerId = [TiUtils intValue:first def:0];
	[self.scene cancelTimer:timerId];
	@synchronized (_timerCallbacks) {
		[_timerCallbacks removeObjectForKey:@(timerId)];
	}
}

- (int)addGameTimer:(id)args repeats:(BOOL)repeats
{
	float ms = 0.0f;
	KrollCallback *callback = nil;
	if ([args isKindOfClass:[NSArray class]]) {
		ms = [TiUtils floatValue:[args firstObject] def:0];
		if ([args count] > 1 && [args[1] isKindOfClass:[KrollCallback class]]) {
			callback = args[1];
		}
	} else {
		ms = [TiUtils floatValue:args def:0];
	}
	int timerId = [self.scene addTimer:ms / 1000.0f repeats:repeats];
	if (callback != nil) {
		@synchronized (_timerCallbacks) {
			_timerCallbacks[@(timerId)] = callback;
		}
	}
	return timerId;
}

/** Render thread — both dispatch paths hand off to the JS thread. */
- (void)onTimer:(int)timerId repeats:(BOOL)repeats
{
	KrollCallback *callback;
	@synchronized (_timerCallbacks) {
		callback = _timerCallbacks[@(timerId)];
		if (!repeats && callback != nil) {
			[_timerCallbacks removeObjectForKey:@(timerId)];
		}
	}
	if (callback != nil) {
		[self _fireEventToListener:@"timer" withObject:@{ @"id": @(timerId) }
						  listener:callback thisObject:nil];
	} else if ([self _hasListeners:@"timer"]) {
		[self fireEvent:@"timer" withObject:@{ @"id": @(timerId) }];
	}
}

/**
 * gameView.raycast(x0, y0, x1, y1, groups): one-shot nearest-hit query
 * along the segment, against visible sprites whose collisionGroup is in
 * `groups` (omit for any tagged sprite). Returns null for a clear ray,
 * else { x, y, distance, group, sprite, normal: { x, y } }. Line of
 * sight, ground probes, hitscan weapons — a discrete query, not
 * something to poll every frame from JS.
 */
- (id)raycast:(id)args
{
	NSArray *list = [args isKindOfClass:[NSArray class]] ? args : @[];
	float x0 = (list.count > 0) ? [TiUtils floatValue:list[0] def:0] : 0.0f;
	float y0 = (list.count > 1) ? [TiUtils floatValue:list[1] def:0] : 0.0f;
	float x1 = (list.count > 2) ? [TiUtils floatValue:list[2] def:0] : 0.0f;
	float y1 = (list.count > 3) ? [TiUtils floatValue:list[3] def:0] : 0.0f;
	NSMutableSet<NSString *> *groups = nil;
	if (list.count > 4 && [list[4] isKindOfClass:[NSArray class]]) {
		groups = [NSMutableSet set];
		for (id group in (NSArray *)list[4]) {
			[groups addObject:[TiUtils stringValue:group]];
		}
	}
	float out[5];
	TGSprite *hit = [self.scene raycastFromX:x0 y:y0 toX:x1 y:y1 groups:groups out:out];
	if (hit == nil) {
		return [NSNull null];
	}
	return @{
		@"x": @(out[0]),
		@"y": @(out[1]),
		@"distance": @(out[2]),
		@"normal": @{ @"x": @(out[3]), @"y": @(out[4]) },
		@"group": (hit.collisionGroup != nil) ? hit.collisionGroup : [NSNull null],
		@"sprite": (hit.proxy != nil) ? hit.proxy : [NSNull null]
	};
}

/**
 * gameView.findPath(from, to, options): grid A* over the visible sprites
 * whose collisionGroup is in options.groups (omit for any tagged sprite).
 * `from`/`to` are { x, y } world points; returns an array of { x, y }
 * waypoints ready for sprite.followPath(), or null when no route exists.
 * Options: cellSize (grid resolution in px, default 32), clearance
 * (extra obstacle inflation in px — about half the walker's width keeps
 * it from scraping corners), bounds ({ minX, minY, maxX, maxY } search
 * rect, default the surface), diagonals (default true), simplify
 * (line-of-sight waypoint reduction, default true). A blocked start or
 * goal snaps to the nearest free cell a few cells out, so tapping an
 * obstacle walks to its edge. A discrete query like raycast — run it on
 * taps and AI timers, not per frame.
 */
- (id)findPath:(id)args
{
	NSArray *list = [args isKindOfClass:[NSArray class]] ? args : @[];
	NSDictionary *from = (list.count > 0 && [list[0] isKindOfClass:[NSDictionary class]]) ? list[0] : nil;
	NSDictionary *to = (list.count > 1 && [list[1] isKindOfClass:[NSDictionary class]]) ? list[1] : nil;
	if (from == nil || to == nil) {
		return [NSNull null];
	}
	NSDictionary *options = (list.count > 2 && [list[2] isKindOfClass:[NSDictionary class]]) ? list[2] : nil;
	float cellSize = [TiUtils floatValue:options[@"cellSize"] def:32.0f];
	float clearance = [TiUtils floatValue:options[@"clearance"] def:0.0f];
	BOOL diagonals = [TiUtils boolValue:options[@"diagonals"] def:YES];
	BOOL simplify = [TiUtils boolValue:options[@"simplify"] def:YES];
	NSMutableSet<NSString *> *groups = nil;
	if ([options[@"groups"] isKindOfClass:[NSArray class]]) {
		groups = [NSMutableSet set];
		for (id group in (NSArray *)options[@"groups"]) {
			[groups addObject:[TiUtils stringValue:group]];
		}
	}
	float minX = 0.0f;
	float minY = 0.0f;
	float maxX = self.scene.worldWidth;
	float maxY = self.scene.worldHeight;
	if ([options[@"bounds"] isKindOfClass:[NSDictionary class]]) {
		NSDictionary *bounds = options[@"bounds"];
		minX = [TiUtils floatValue:bounds[@"minX"] def:minX];
		minY = [TiUtils floatValue:bounds[@"minY"] def:minY];
		maxX = [TiUtils floatValue:bounds[@"maxX"] def:maxX];
		maxY = [TiUtils floatValue:bounds[@"maxY"] def:maxY];
	}
	NSArray<NSNumber *> *points = [self.scene
		findPathFromX:[TiUtils floatValue:from[@"x"] def:0.0f]
					y:[TiUtils floatValue:from[@"y"] def:0.0f]
				  toX:[TiUtils floatValue:to[@"x"] def:0.0f]
					y:[TiUtils floatValue:to[@"y"] def:0.0f]
			   groups:groups cellSize:cellSize clearance:clearance
				 minX:minX minY:minY maxX:maxX maxY:maxY
			diagonals:diagonals simplify:simplify];
	if (points == nil) {
		return [NSNull null];
	}
	NSMutableArray *result = [NSMutableArray arrayWithCapacity:points.count / 2];
	for (NSUInteger i = 0; i + 1 < points.count; i += 2) {
		[result addObject:@{ @"x": points[i], @"y": points[i + 1] }];
	}
	return result;
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
