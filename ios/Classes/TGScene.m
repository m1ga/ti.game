#import "TGScene.h"
#import "TGDebugHud.h"
#import "TGFrameStats.h"
#import "TGParticleEmitter.h"
#import "TGPathfinder.h"
#import "TGRope.h"
#import "TGSkidTrail.h"
#import "TGSprite.h"
#import "TGTextSprite.h"
#import "TGTileLayer.h"
#import "TGBitmapFont.h"
#import "TGDefaultFont.h"
#import <float.h>
#import <math.h>

// Allowed penetration, in pixels. A body resting on a solid is pulled into
// it by gravity every frame — at 1400 px/s² and 60 fps that is 0.39 px of
// sink — and shoving it back out in full, 60 times a second, is what makes
// a settled pile tremble. Overlaps under this are left alone; the closing
// velocity is still cancelled, so the sink can never grow past it. Big
// enough to swallow a frame of gravity, small enough to stay invisible.
static const float TGSlop = 0.5f;

static float bottomEdge(TGSprite *s)
{
	return s.y + [s drawHeight] * fabsf(s.scaleY) * (1.0f - s.anchorY);
}

/** One game-clock timer (twin of Scene.GameTimer). */
@interface TGGameTimer : NSObject
@property (nonatomic, assign) int timerId;
@property (nonatomic, assign) float interval; // seconds, game time
@property (nonatomic, assign) BOOL repeats;
@property (nonatomic, assign) float remaining;
@end

@implementation TGGameTimer
@end

@implementation TGScene {
	NSMutableArray<TGSprite *> *_sprites;
	NSMutableArray<TGParticleEmitter *> *_emitters; // guarded by @synchronized(_sprites)
	NSMutableArray<TGRope *> *_ropes;               // guarded by @synchronized(_sprites)
	NSMutableArray<TGTileLayer *> *_tileLayers;     // guarded by @synchronized(_sprites)

	// Camera shake, requested from any thread, animated on the render thread
	volatile float _pendingShakeStrength;
	volatile float _pendingShakeDuration;
	float _shakeStrength, _shakeDuration, _shakeRemaining, _shakeTime;
	BOOL _zOrderDirty;   // guarded by @synchronized(_sprites)
	BOOL _hasYSort;      // guarded by @synchronized(_sprites)
	NSArray<TGSprite *> *_snapshotCache; // guarded by @synchronized(_sprites)
	TGBitmapFont *_defaultFont;             // guarded by @synchronized(self)
	float _aabbA[4];
	float _aabbB[4];
	float _centerA[2];
	float _centerB[2];
	float _boxA[5];   // oriented hitbox: cx, cy, hx, hy, radians
	float _boxB[5];
	float _satAxes[8];
	float _contact[3]; // nx, ny, penetration

	float _sweptResult[2]; // entry time in 0..1, entry axis (0 = x, 1 = y)

	NSMutableArray<TGGameTimer *> *_timers; // guarded by @synchronized(_timers)
	int _nextTimerId;                       // guarded by @synchronized(_timers)
}

- (instancetype)init
{
	if (self = [super init]) {
		_sprites = [NSMutableArray array];
		_emitters = [NSMutableArray array];
		_ropes = [NSMutableArray array];
		_tileLayers = [NSMutableArray array];
		_skidTrail = [[TGSkidTrail alloc] init];
		_hud = [[TGDebugHud alloc] init];
		_stats = [[TGFrameStats alloc] init];
		_effectTintR = 1.0f;
		_effectTintG = 1.0f;
		_effectTintB = 1.0f;
		_effectIntensity = 1.0f;
		_cameraScale = 1.0f;
		_timeScale = 1.0f;
		_followTopFraction = 0.33f;
		_followBottomFraction = 0.7f;
		_followLeftFraction = -1.0f;
		_followRightFraction = 0.65f;
		_pendingShakeStrength = -1.0f;
		_bgAlpha = 1.0f;
		_timers = [NSMutableArray array];
		_nextTimerId = 1;
	}
	return self;
}

// --- Game-clock timers --------------------------------------------------

- (int)addTimer:(float)seconds repeats:(BOOL)repeats
{
	@synchronized (_timers) {
		TGGameTimer *timer = [[TGGameTimer alloc] init];
		timer.timerId = _nextTimerId++;
		timer.interval = MAX(0.001f, seconds);
		timer.repeats = repeats;
		timer.remaining = timer.interval;
		[_timers addObject:timer];
		return timer.timerId;
	}
}

- (void)cancelTimer:(int)timerId
{
	@synchronized (_timers) {
		for (TGGameTimer *timer in _timers) {
			if (timer.timerId == timerId) {
				[_timers removeObject:timer];
				return;
			}
		}
	}
}

/** Ticks timers with scaled dt; fires the listener outside the lock. */
- (void)updateTimers:(float)dt
{
	if (dt <= 0.0f) {
		return; // frozen (timeScale 0) — game time stands still
	}
	NSMutableArray<TGGameTimer *> *fired = nil;
	@synchronized (_timers) {
		for (NSUInteger i = 0; i < _timers.count; ) {
			TGGameTimer *timer = _timers[i];
			timer.remaining -= dt;
			if (timer.remaining <= 0.0f) {
				if (fired == nil) {
					fired = [NSMutableArray array];
				}
				[fired addObject:timer];
				if (timer.repeats) {
					// at most one fire per frame; after a long stall,
					// restart the interval instead of bursting
					timer.remaining += timer.interval;
					if (timer.remaining < 0.0f) {
						timer.remaining = timer.interval;
					}
					i++;
				} else {
					[_timers removeObjectAtIndex:i];
				}
			} else {
				i++;
			}
		}
	}
	id<TGSceneTimerListener> listener = self.timerListener;
	if (fired != nil && listener != nil) {
		for (TGGameTimer *timer in fired) {
			[listener onTimer:timer.timerId repeats:timer.repeats];
		}
	}
}

- (void)recomputeYSort
{
	@synchronized (_sprites) {
		for (TGSprite *s in _sprites) {
			if (s.ySort) {
				_hasYSort = YES;
				return;
			}
		}
		_hasYSort = NO;
	}
}

// This scene's built-in pixel font, shared by every default-font text
// sprite in the view — one instance per scene, because the font's GL
// texture belongs to this view's context (a global one would go stale
// when another GameView creates its own context).
- (TGBitmapFont *)defaultFont
{
	@synchronized (self) {
		if (_defaultFont == nil) {
			_defaultFont = [TGDefaultFont makeFont];
		}
		return _defaultFont;
	}
}

- (void)resolveTextFont:(TGSprite *)sprite
{
	if ([sprite isKindOfClass:[TGTextSprite class]] && ((TGTextSprite *)sprite).usesDefaultFont) {
		[(TGTextSprite *)sprite setTextFont:[self defaultFont]];
	}
}

- (void)add:(TGSprite *)sprite
{
	if (sprite == nil) {
		return;
	}
	@synchronized (_sprites) {
		if (![_sprites containsObject:sprite]) {
			[_sprites addObject:sprite];
			sprite.scene = self;
			[self resolveTextFont:sprite];
			_zOrderDirty = YES;
			_snapshotCache = nil;
			if (sprite.ySort) {
				_hasYSort = YES;
			}
		}
	}
}

- (void)addSprites:(NSArray<TGSprite *> *)sprites
		  emitters:(NSArray<TGParticleEmitter *> *)emitters
			 ropes:(NSArray<TGRope *> *)ropes
			layers:(NSArray<TGTileLayer *> *)layers
{
	@synchronized (_sprites) {
		BOOL spritesAdded = NO;
		for (TGSprite *sprite in sprites) {
			if (sprite != nil && ![_sprites containsObject:sprite]) {
				[_sprites addObject:sprite];
				sprite.scene = self;
				[self resolveTextFont:sprite];
				spritesAdded = YES;
				if (sprite.ySort) {
					_hasYSort = YES;
				}
			}
		}
		for (TGParticleEmitter *emitter in emitters) {
			if (emitter != nil && ![_emitters containsObject:emitter]) {
				[_emitters addObject:emitter];
			}
		}
		for (TGRope *rope in ropes) {
			if (rope != nil && ![_ropes containsObject:rope]) {
				[_ropes addObject:rope];
			}
		}
		for (TGTileLayer *layer in layers) {
			if (layer != nil && ![_tileLayers containsObject:layer]) {
				[_tileLayers addObject:layer];
			}
		}
		if (spritesAdded) {
			_zOrderDirty = YES;
			_snapshotCache = nil;
		}
	}
}

- (void)remove:(TGSprite *)sprite
{
	if (sprite == nil) {
		return;
	}
	@synchronized (_sprites) {
		[self removeWithAttachmentsLocked:sprite];
	}
}

// Removes a sprite and, recursively, every sprite attached to it — a
// name tag or health bar never outlives its owner, and a chain (a hat
// on the tag) goes with it. Cycle-safe: a sprite no longer in the list
// is skipped. Caller holds the _sprites lock.
- (void)removeWithAttachmentsLocked:(TGSprite *)sprite
{
	if (![_sprites containsObject:sprite]) {
		return;
	}
	[_sprites removeObjectIdenticalTo:sprite];
	sprite.scene = nil;
	sprite.attachTarget = nil;
	sprite.attachOpacity = 1.0f;
	_snapshotCache = nil;
	NSMutableArray<TGSprite *> *attached = nil;
	for (TGSprite *s in _sprites) {
		if (s.attachTarget == sprite) {
			if (attached == nil) {
				attached = [NSMutableArray array];
			}
			[attached addObject:s];
		}
	}
	for (TGSprite *s in attached) {
		[self removeWithAttachmentsLocked:s];
	}
}

- (void)clear
{
	@synchronized (_sprites) {
		for (TGSprite *s in _sprites) {
			s.scene = nil;
			s.attachTarget = nil;
			s.attachOpacity = 1.0f;
		}
		[_sprites removeAllObjects];
		_snapshotCache = nil;
	}
}

- (void)markZOrderDirty
{
	@synchronized (_sprites) {
		_zOrderDirty = YES;
		_snapshotCache = nil;
	}
}

- (void)addEmitter:(TGParticleEmitter *)emitter
{
	if (emitter == nil) {
		return;
	}
	@synchronized (_sprites) {
		if (![_emitters containsObject:emitter]) {
			[_emitters addObject:emitter];
		}
	}
}

- (void)removeEmitter:(TGParticleEmitter *)emitter
{
	if (emitter == nil) {
		return;
	}
	@synchronized (_sprites) {
		[_emitters removeObjectIdenticalTo:emitter];
	}
}

- (NSArray<TGParticleEmitter *> *)emittersSnapshot
{
	@synchronized (_sprites) {
		if (_emitters.count == 0) {
			return @[];
		}
		return [_emitters sortedArrayWithOptions:NSSortStable
								 usingComparator:^NSComparisonResult(TGParticleEmitter *a, TGParticleEmitter *b) {
			if (a.zIndex != b.zIndex) {
				return (a.zIndex < b.zIndex) ? NSOrderedAscending : NSOrderedDescending;
			}
			return NSOrderedSame;
		}];
	}
}

- (void)addRope:(TGRope *)rope
{
	if (rope == nil) {
		return;
	}
	@synchronized (_sprites) {
		if (![_ropes containsObject:rope]) {
			[_ropes addObject:rope];
		}
	}
}

- (void)removeRope:(TGRope *)rope
{
	if (rope == nil) {
		return;
	}
	@synchronized (_sprites) {
		[_ropes removeObjectIdenticalTo:rope];
	}
}

- (NSArray<TGRope *> *)ropesSnapshot
{
	@synchronized (_sprites) {
		if (_ropes.count == 0) {
			return @[];
		}
		return [_ropes sortedArrayWithOptions:NSSortStable
							  usingComparator:^NSComparisonResult(TGRope *a, TGRope *b) {
			if (a.zIndex != b.zIndex) {
				return (a.zIndex < b.zIndex) ? NSOrderedAscending : NSOrderedDescending;
			}
			return NSOrderedSame;
		}];
	}
}

- (void)addTileLayer:(TGTileLayer *)layer
{
	if (layer == nil) {
		return;
	}
	@synchronized (_sprites) {
		if (![_tileLayers containsObject:layer]) {
			[_tileLayers addObject:layer];
		}
	}
}

- (void)removeTileLayer:(TGTileLayer *)layer
{
	if (layer == nil) {
		return;
	}
	@synchronized (_sprites) {
		[_tileLayers removeObjectIdenticalTo:layer];
	}
}

- (NSArray<TGTileLayer *> *)tileLayersSnapshot
{
	@synchronized (_sprites) {
		return [self sortedLayersLocked];
	}
}

/** Caller holds the _sprites lock. */
- (NSArray<TGTileLayer *> *)sortedLayersLocked
{
	if (_tileLayers.count == 0) {
		return @[];
	}
	return [_tileLayers sortedArrayWithOptions:NSSortStable
							   usingComparator:^NSComparisonResult(TGTileLayer *a, TGTileLayer *b) {
		if (a.zIndex != b.zIndex) {
			return (a.zIndex < b.zIndex) ? NSOrderedAscending : NSOrderedDescending;
		}
		return NSOrderedSame;
	}];
}

- (NSArray<TGSprite *> *)snapshot
{
	@synchronized (_sprites) {
		// ySort scenes re-sort every frame (bottom edges move); everything
		// else reuses the copy until the list or z-order changes
		if (_snapshotCache != nil && !_zOrderDirty && !_hasYSort) {
			return _snapshotCache;
		}
		if (_zOrderDirty || _hasYSort) {
			// Stable sort — sprites with equal keys keep insertion order,
			// like Collections.sort on Android
			[_sprites sortWithOptions:NSSortStable
					  usingComparator:^NSComparisonResult(TGSprite *a, TGSprite *b) {
				if (a.zIndex != b.zIndex) {
					return (a.zIndex < b.zIndex) ? NSOrderedAscending : NSOrderedDescending;
				}
				if (a.ySort && b.ySort) {
					float ba = bottomEdge(a);
					float bb = bottomEdge(b);
					if (ba != bb) {
						return (ba < bb) ? NSOrderedAscending : NSOrderedDescending;
					}
				}
				return NSOrderedSame;
			}];
			_zOrderDirty = NO;
		}
		_snapshotCache = [_sprites copy];
		return _snapshotCache;
	}
}

- (NSArray<TGSprite *> *)prepareFrame:(float)dt
							 emitters:(NSArray<TGParticleEmitter *> **)emitters
								ropes:(NSArray<TGRope *> **)ropes
							   layers:(NSArray<TGTileLayer *> **)layers
{
	dt *= MAX(0.0f, self.timeScale);
	__block NSArray<TGSprite *> *list;
	__block NSArray<TGParticleEmitter *> *emitterList;
	__block NSArray<TGRope *> *ropeList;
	__block NSArray<TGTileLayer *> *layerList;
	__block BOOL hasYSort;

	// Capture all scene collections under the same lock. The renderer reuses
	// these exact arrays for update, collision and draw, so no second set of
	// snapshots is allocated later in the frame.
	@synchronized (_sprites) {
		if (_zOrderDirty) {
			[_sprites sortWithOptions:NSSortStable
					  usingComparator:^NSComparisonResult(TGSprite *a, TGSprite *b) {
				if (a.zIndex != b.zIndex) {
					return (a.zIndex < b.zIndex) ? NSOrderedAscending : NSOrderedDescending;
				}
				if (a.ySort && b.ySort) {
					float ba = bottomEdge(a);
					float bb = bottomEdge(b);
					if (ba != bb) {
						return (ba < bb) ? NSOrderedAscending : NSOrderedDescending;
					}
				}
				return NSOrderedSame;
			}];
			_zOrderDirty = NO;
		}
		list = [_sprites copy];
		emitterList = [_emitters sortedArrayWithOptions:NSSortStable
										 usingComparator:^NSComparisonResult(TGParticleEmitter *a, TGParticleEmitter *b) {
			if (a.zIndex != b.zIndex) {
				return (a.zIndex < b.zIndex) ? NSOrderedAscending : NSOrderedDescending;
			}
			return NSOrderedSame;
		}];
		ropeList = [_ropes sortedArrayWithOptions:NSSortStable
								  usingComparator:^NSComparisonResult(TGRope *a, TGRope *b) {
			if (a.zIndex != b.zIndex) {
				return (a.zIndex < b.zIndex) ? NSOrderedAscending : NSOrderedDescending;
			}
			return NSOrderedSame;
		}];
		layerList = [self sortedLayersLocked];
		hasYSort = _hasYSort;
	}

	for (TGSprite *s in list) {
		[s update:dt];
	}
	for (TGParticleEmitter *e in emitterList) {
		[e update:dt];
	}
	// Ropes after sprites, so a dragged/physics-moved head is current
	for (TGRope *rope in ropeList) {
		[rope update:dt];
	}
	[self.skidTrail update:dt];
	[self updateTimers:dt];
	[self wrapSprites:list];
	[self resolveSolids:list layers:layerList];
	[self applyAttachments:list];
	[self checkCollisions:list];
	[self updateFollow:dt];
	[self applyCameraBounds];
	[self updateShake:dt];

	// ySort depends on positions advanced above. Sort the frame-local array,
	// leaving the synchronized backing store untouched until a real z change.
	if (hasYSort) {
		list = [list sortedArrayWithOptions:NSSortStable
						 usingComparator:^NSComparisonResult(TGSprite *a, TGSprite *b) {
			if (a.zIndex != b.zIndex) {
				return (a.zIndex < b.zIndex) ? NSOrderedAscending : NSOrderedDescending;
			}
			if (a.ySort && b.ySort) {
				float ba = bottomEdge(a);
				float bb = bottomEdge(b);
				if (ba != bb) {
					return (ba < bb) ? NSOrderedAscending : NSOrderedDescending;
				}
			}
			return NSOrderedSame;
		}];
	}
	if (emitters != NULL) {
		*emitters = emitterList;
	}
	if (ropes != NULL) {
		*ropes = ropeList;
	}
	if (layers != NULL) {
		*layers = layerList;
	}
	return list;
}

- (void)update:(float)dt
{
	[self prepareFrame:dt emitters:NULL ropes:NULL layers:NULL];
}

- (void)shakeWithStrength:(float)strength duration:(float)duration
{
	_pendingShakeDuration = duration;
	_pendingShakeStrength = strength;
}

- (float)viewOriginX
{
	float s = MAX(0.0001f, self.cameraScale);
	return self.cameraX + (self.worldWidth - self.worldWidth / s) / 2.0f;
}

- (float)viewOriginY
{
	float s = MAX(0.0001f, self.cameraScale);
	return self.cameraY + (self.worldHeight - self.worldHeight / s) / 2.0f;
}

- (float)screenToWorldX:(float)sx
{
	return [self viewOriginX] + sx / MAX(0.0001f, self.cameraScale);
}

- (float)screenToWorldY:(float)sy
{
	return [self viewOriginY] + sy / MAX(0.0001f, self.cameraScale);
}

- (float)worldToScreenX:(float)wx
{
	return (wx - [self viewOriginX]) * MAX(0.0001f, self.cameraScale);
}

- (float)worldToScreenY:(float)wy
{
	return (wy - [self viewOriginY]) * MAX(0.0001f, self.cameraScale);
}

/** Dead-zone follow, after physics so the camera never lags. */
- (void)updateFollow:(float)dt
{
	TGSprite *target = self.followTarget;
	float scale = MAX(0.0001f, self.cameraScale);
	float visibleH = self.worldHeight / scale;
	if (target == nil || visibleH <= 0.0f) {
		return;
	}
	// vertical dead-zone (fractions of the visible height)
	float top = visibleH * self.followTopFraction;
	float bottom = visibleH * self.followBottomFraction;
	float screenY = target.y - [self viewOriginY];
	float desiredY = self.cameraY;
	if (screenY < top) {
		desiredY += screenY - top;
	} else if (screenY > bottom) {
		desiredY += screenY - bottom;
	}
	if (desiredY > self.cameraMaxY) {
		desiredY = self.cameraMaxY;
	}
	// horizontal dead-zone, only when enabled via follow options
	float desiredX = self.cameraX;
	if (self.followLeftFraction >= 0.0f) {
		float visibleW = self.worldWidth / scale;
		float left = visibleW * self.followLeftFraction;
		float right = visibleW * self.followRightFraction;
		float screenX = target.x - [self viewOriginX];
		if (screenX < left) {
			desiredX += screenX - left;
		} else if (screenX > right) {
			desiredX += screenX - right;
		}
	}
	float smoothing = self.followSmoothing;
	if (smoothing > 0.0f) {
		// time-corrected lerp: `smoothing` of the remaining distance per 1/60 s
		float factor = 1.0f - powf(1.0f - MIN(0.99f, smoothing), dt * 60.0f);
		self.cameraX += (desiredX - self.cameraX) * factor;
		self.cameraY += (desiredY - self.cameraY) * factor;
	} else {
		self.cameraX = desiredX;
		self.cameraY = desiredY;
	}
}

/** Keeps the visible rect inside the bounds rect (centers if smaller). */
- (void)applyCameraBounds
{
	if (!self.cameraBoundsEnabled) {
		return;
	}
	float scale = MAX(0.0001f, self.cameraScale);
	float visibleW = self.worldWidth / scale;
	float visibleH = self.worldHeight / scale;
	float originX = [self viewOriginX];
	float originY = [self viewOriginY];
	float maxOriginX = self.boundsMaxX - visibleW;
	float maxOriginY = self.boundsMaxY - visibleH;
	float clampedX = (maxOriginX < self.boundsMinX)
		? (self.boundsMinX + maxOriginX) / 2.0f
		: MIN(MAX(originX, self.boundsMinX), maxOriginX);
	float clampedY = (maxOriginY < self.boundsMinY)
		? (self.boundsMinY + maxOriginY) / 2.0f
		: MIN(MAX(originY, self.boundsMinY), maxOriginY);
	self.cameraX += clampedX - originX;
	self.cameraY += clampedY - originY;
}

/**
 * Camera shake: two fast, detuned sine waves scaled by a linear falloff.
 * The offset only shifts the projection (renderer), never cameraX/Y, so
 * follow, bounds and touch mapping stay unaffected.
 */
- (void)updateShake:(float)dt
{
	float pending = _pendingShakeStrength;
	if (pending >= 0.0f) {
		_pendingShakeStrength = -1.0f;
		_shakeStrength = pending;
		_shakeDuration = MAX(0.001f, _pendingShakeDuration);
		_shakeRemaining = _shakeDuration;
		_shakeTime = 0.0f;
	}
	if (_shakeRemaining <= 0.0f) {
		self.shakeOffsetX = 0.0f;
		self.shakeOffsetY = 0.0f;
		return;
	}
	_shakeRemaining -= dt;
	_shakeTime += dt;
	float falloff = MAX(0.0f, _shakeRemaining / _shakeDuration);
	self.shakeOffsetX = _shakeStrength * falloff * sinf(_shakeTime * 71.0f);
	self.shakeOffsetY = _shakeStrength * falloff * sinf(_shakeTime * 83.0f + 1.3f);
}

/** Asteroids-style edge wrap: leaving one side re-enters the opposite. */
- (void)wrapSprites:(NSArray<TGSprite *> *)list
{
	float w = self.worldWidth;
	float h = self.worldHeight;
	if (w <= 0.0f || h <= 0.0f) {
		return;
	}
	for (TGSprite *s in list) {
		if (!s.wrapAround) {
			continue;
		}
		float marginX = [s drawWidth] * fabsf(s.scaleX) / 2.0f;
		float marginY = [s drawHeight] * fabsf(s.scaleY) / 2.0f;
		if (s.x < -marginX) {
			s.x = w + marginX;
		} else if (s.x > w + marginX) {
			s.x = -marginX;
		}
		if (s.y < -marginY) {
			s.y = h + marginY;
		} else if (s.y > h + marginY) {
			s.y = -marginY;
		}
	}
}

/**
 * Platformer collision resolution: sprites with `solidWith` groups are
 * pushed out of overlapping solids along the axis of least penetration.
 * Landing on top zeroes downward velocity, sets onGround and fires the
 * land callback on the ground-touch transition.
 */
/**
 * Swept AABB: does a point moving from (cx, cy) by (dx, dy) this frame
 * cross the box? Callers inflate the box by the mover's half extents
 * (Minkowski sum), turning box-vs-box sweeping into this segment test
 * (slab method). Catches fast movers that would tunnel straight through
 * thin targets between frames. Render thread only.
 */
/** Segment vs circle, same frame as the caller: smallest t in [0,1], or -1
 *  when it misses. Starting inside counts as t = 0. */
- (float)segmentFromX:(float)px y:(float)py dx:(float)dx dy:(float)dy
			vsCircleX:(float)cx y:(float)cy radius:(float)radius
{
	float fx = px - cx;
	float fy = py - cy;
	if (fx * fx + fy * fy <= radius * radius) {
		return 0.0f;
	}
	float a = dx * dx + dy * dy;
	float b = 2.0f * (fx * dx + fy * dy);
	float c = fx * fx + fy * fy - radius * radius;
	float disc = b * b - 4.0f * a * c;
	if (a < 1e-6f || disc < 0.0f) {
		return -1.0f;
	}
	float t = (-b - sqrtf(disc)) / (2.0f * a);
	return (t >= 0.0f && t <= 1.0f) ? t : -1.0f;
}

- (BOOL)sweptHitFromX:(float)cx y:(float)cy dx:(float)dx dy:(float)dy
				 minX:(float)minX minY:(float)minY maxX:(float)maxX maxY:(float)maxY
{
	return TGSegmentVsAabb(cx, cy, dx, dy, minX, minY, maxX, maxY, _sweptResult);
}

/** The slab test itself, writing {entry time, entry axis} into result —
 *  a plain function so raycast can run it from the main thread with its
 *  own buffer, never racing the render thread's _sweptResult. */
static BOOL TGSegmentVsAabb(float cx, float cy, float dx, float dy,
							float minX, float minY, float maxX, float maxY,
							float *result)
{
	float tmin = 0.0f;
	float tmax = 1.0f;
	float axis = 0.0f;
	if (dx > -1e-6f && dx < 1e-6f) {
		if (cx < minX || cx > maxX) {
			return NO;
		}
	} else {
		float t1 = (minX - cx) / dx;
		float t2 = (maxX - cx) / dx;
		if (t1 > t2) {
			float t = t1;
			t1 = t2;
			t2 = t;
		}
		if (t1 > tmin) {
			tmin = t1;
		}
		if (t2 < tmax) {
			tmax = t2;
		}
		if (tmin > tmax) {
			return NO;
		}
	}
	if (dy > -1e-6f && dy < 1e-6f) {
		if (cy < minY || cy > maxY) {
			return NO;
		}
	} else {
		float t1 = (minY - cy) / dy;
		float t2 = (maxY - cy) / dy;
		if (t1 > t2) {
			float t = t1;
			t1 = t2;
			t2 = t;
		}
		if (t1 > tmin) {
			tmin = t1;
			axis = 1.0f;
		}
		if (t2 < tmax) {
			tmax = t2;
		}
		if (tmin > tmax) {
			return NO;
		}
	}
	result[0] = tmin;
	result[1] = axis;
	return YES;
}

- (TGSprite *)raycastFromX:(float)x0 y:(float)y0 toX:(float)x1 y:(float)y1
					groups:(NSSet<NSString *> *)groups out:(float *)out
{
	float dx = x1 - x0;
	float dy = y1 - y0;
	float rayLength = hypotf(dx, dy);
	float box[4];
	float center[2];
	float entry[2];
	float bestT = FLT_MAX;
	TGSprite *best = nil;
	float bestNormalX = 0.0f;
	float bestNormalY = 0.0f;
	for (TGSprite *s in [self snapshot]) {
		NSString *group = s.collisionGroup;
		if (group == nil || !s.visible || s.screenFixed
				|| (groups != nil && groups.count > 0 && ![groups containsObject:group])) {
			continue;
		}
		if (s.circleHitbox) {
			// Ray vs circle: solve |P0 + t*d - C|^2 = r^2 for the
			// smallest t in [0, 1]
			[s hitCenter:center];
			float r = [s hitRadius];
			float fx = x0 - center[0];
			float fy = y0 - center[1];
			float t;
			if (fx * fx + fy * fy <= r * r) {
				t = 0.0f; // started inside
			} else {
				float a = dx * dx + dy * dy;
				float b = 2.0f * (fx * dx + fy * dy);
				float c = fx * fx + fy * fy - r * r;
				float disc = b * b - 4.0f * a * c;
				if (a < 1e-6f || disc < 0.0f) {
					continue;
				}
				t = (-b - sqrtf(disc)) / (2.0f * a);
				if (t < 0.0f || t > 1.0f) {
					continue;
				}
			}
			if (t < bestT) {
				bestT = t;
				best = s;
				float hx = x0 + dx * t;
				float hy = y0 + dy * t;
				float nl = hypotf(hx - center[0], hy - center[1]);
				bestNormalX = (nl > 1e-6f) ? (hx - center[0]) / nl : 0.0f;
				bestNormalY = (nl > 1e-6f) ? (hy - center[1]) / nl : 0.0f;
			}
		} else if (s.obbHitbox) {
			// Ray vs a turned rect: take the ray into the box's frame, run
			// the same slab test, rotate the normal back out
			float rayBox[5];
			[s hitBox:rayBox];
			float bc = cosf(rayBox[4]);
			float bs = sinf(rayBox[4]);
			float rx = x0 - rayBox[0];
			float ry = y0 - rayBox[1];
			float lx = rx * bc + ry * bs;
			float ly = -rx * bs + ry * bc;
			float ldx = dx * bc + dy * bs;
			float ldy = -dx * bs + dy * bc;
			if (!TGSegmentVsAabb(lx, ly, ldx, ldy,
					-rayBox[2], -rayBox[3], rayBox[2], rayBox[3], entry)) {
				continue;
			}
			if (entry[0] < bestT) {
				bestT = entry[0];
				best = s;
				float lnx, lny;
				if (entry[1] == 0.0f) {
					lnx = (ldx > 0.0f) ? -1.0f : (ldx < 0.0f) ? 1.0f : 0.0f;
					lny = 0.0f;
				} else {
					lnx = 0.0f;
					lny = (ldy > 0.0f) ? -1.0f : (ldy < 0.0f) ? 1.0f : 0.0f;
				}
				bestNormalX = lnx * bc - lny * bs;
				bestNormalY = lnx * bs + lny * bc;
			}
		} else {
			[s computeAABB:box];
			if (!TGSegmentVsAabb(x0, y0, dx, dy, box[0], box[1], box[2], box[3], entry)) {
				continue;
			}
			if (entry[0] < bestT) {
				bestT = entry[0];
				best = s;
				if (entry[1] == 0.0f) {
					bestNormalX = (dx > 0.0f) ? -1.0f : (dx < 0.0f) ? 1.0f : 0.0f;
					bestNormalY = 0.0f;
				} else {
					bestNormalX = 0.0f;
					bestNormalY = (dy > 0.0f) ? -1.0f : (dy < 0.0f) ? 1.0f : 0.0f;
				}
			}
		}
	}
	if (best == nil) {
		return nil;
	}
	out[0] = x0 + dx * bestT;
	out[1] = y0 + dy * bestT;
	out[2] = rayLength * bestT;
	out[3] = bestNormalX;
	out[4] = bestNormalY;
	return best;
}

- (NSArray<NSNumber *> *)findPathFromX:(float)startX y:(float)startY
								   toX:(float)goalX y:(float)goalY
								groups:(NSSet<NSString *> *)groups
							  cellSize:(float)cellSize clearance:(float)clearance
								  minX:(float)minX minY:(float)minY
								  maxX:(float)maxX maxY:(float)maxY
							 diagonals:(BOOL)diagonals simplify:(BOOL)simplify
{
	return [TGPathfinder findInSprites:[self snapshot] layers:[self tileLayersSnapshot] groups:groups
								startX:startX startY:startY goalX:goalX goalY:goalY
							  cellSize:cellSize clearance:clearance
								  minX:minX minY:minY maxX:maxX maxY:maxY
							 diagonals:diagonals simplify:simplify];
}

/**
 * Path-of-travel overlap test for swept sprites: did the mover's box
 * cross the target's box at any point this frame? Relative motion, so a
 * fast target can't slip past a slow bullet either.
 */
- (BOOL)sweptShapesOverlap:(TGSprite *)s with:(TGSprite *)other
{
	float dx = s.frameDeltaX - other.frameDeltaX;
	float dy = s.frameDeltaY - other.frameDeltaY;
	if (dx * dx + dy * dy < 1e-4f) {
		return NO;
	}
	[s computeAABB:_aabbA];
	[other computeAABB:_aabbB];
	float hw = (_aabbA[2] - _aabbA[0]) / 2.0f;
	float hh = (_aabbA[3] - _aabbA[1]) / 2.0f;
	float cx = (_aabbA[0] + _aabbA[2]) / 2.0f - dx; // center at frame start
	float cy = (_aabbA[1] + _aabbA[3]) / 2.0f - dy;
	return [self sweptHitFromX:cx y:cy dx:dx dy:dy
						  minX:_aabbB[0] - hw minY:_aabbB[1] - hh
						  maxX:_aabbB[2] + hw maxY:_aabbB[3] + hh];
}

/**
 * Swept solid blocking: finds the earliest wall the sprite's movement
 * crossed this frame and pulls the sprite back to the impact point,
 * half a pixel past contact — the static resolver below then sees an
 * ordinary touch and handles push-out, restitution, onGround and the
 * land event exactly like a slow collision. Without this, a sprite
 * faster than a solid is thick teleports straight through it.
 *
 * Two circle hitboxes sweep as circles: the Minkowski sum of two circles
 * is a circle of radius r1 + r2, so the test is the same ray vs circle
 * the raycast API solves. Every other pairing — including a circle
 * against a rectangular solid — stays on the inflated-AABB Minkowski box.
 */
- (void)sweepAgainstSolids:(TGSprite *)s
					inList:(NSArray<TGSprite *> *)list
					layers:(NSArray<TGTileLayer *> *)layers
					groups:(NSSet<NSString *> *)groups
{
	float dx = s.frameDeltaX;
	float dy = s.frameDeltaY;
	float len2 = dx * dx + dy * dy;
	if (len2 < 1e-4f) {
		return;
	}
	BOOL circle = s.circleHitbox;
	float r = 0.0f;
	float cx, cy, hw = 0.0f, hh = 0.0f;
	if (circle) {
		[s hitCenter:_centerA];
		r = [s hitRadius];
		cx = _centerA[0] - dx; // center at frame start
		cy = _centerA[1] - dy;
	} else {
		[s computeAABB:_aabbA];
		hw = (_aabbA[2] - _aabbA[0]) / 2.0f;
		hh = (_aabbA[3] - _aabbA[1]) / 2.0f;
		cx = (_aabbA[0] + _aabbA[2]) / 2.0f - dx; // center at frame start
		cy = (_aabbA[1] + _aabbA[3]) / 2.0f - dy;
	}
	// Tile cells sweep on the inflated-AABB Minkowski box, circles too
	// (the same approximation a circle gets against a rect solid)
	float earliest = [self sweepAgainstTiles:s layers:layers groups:groups
										  cx:cx cy:cy dx:dx dy:dy
										  hw:circle ? r : hw hh:circle ? r : hh];
	for (TGSprite *solid in list) {
		NSString *group = solid.collisionGroup;
		if (solid == s || group == nil || !solid.visible || ![groups containsObject:group]
				|| solid.solidMode != TGSolidBlock) {
			// contain would stop the ball against the OUTSIDE of the
			// boundary, and push bodies are meant to move — neither is a
			// wall, so neither belongs in a blocking sweep
			continue;
		}
		if (solid.obbHitbox) {
			// Take the whole sweep into the box's frame, where the box is
			// axis-aligned again and the existing Minkowski segment test
			// applies unchanged.
			[solid hitBox:_boxB];
			float bc = cosf(_boxB[4]);
			float bs = sinf(_boxB[4]);
			float rx = cx - _boxB[0];
			float ry = cy - _boxB[1];
			float lx = rx * bc + ry * bs;
			float ly = -rx * bs + ry * bc;
			float ldx = dx * bc + dy * bs;
			float ldy = -dx * bs + dy * bc;
			float best = FLT_MAX;
			if (circle) {
				// The Minkowski sum of a circle and a rect is a ROUNDED rect:
				// the box grown on each axis, plus a quarter circle at each
				// corner. Growing it as a square instead pokes out by 1.41r
				// along the diagonal — which is exactly where a ball dropped
				// on a turned box's tip arrives. It gets stopped short of a
				// contact that then never happens, and hangs in mid-air for a
				// quarter second until it drifts off the phantom corner.
				if ([self sweptHitFromX:lx y:ly dx:ldx dy:ldy
									minX:-_boxB[2] - r minY:-_boxB[3]
									maxX:_boxB[2] + r maxY:_boxB[3]]) {
					best = _sweptResult[0];
				}
				if ([self sweptHitFromX:lx y:ly dx:ldx dy:ldy
									minX:-_boxB[2] minY:-_boxB[3] - r
									maxX:_boxB[2] maxY:_boxB[3] + r]
						&& _sweptResult[0] < best) {
					best = _sweptResult[0];
				}
				for (int i = 0; i < 4; i++) {
					float ccx = ((i & 1) == 0) ? -_boxB[2] : _boxB[2];
					float ccy = (i < 2) ? -_boxB[3] : _boxB[3];
					float t = [self segmentFromX:lx y:ly dx:ldx dy:ldy
									   vsCircleX:ccx y:ccy radius:r];
					if (t >= 0.0f && t < best) {
						best = t;
					}
				}
			} else if ([self sweptHitFromX:lx y:ly dx:ldx dy:ldy
									   minX:-_boxB[2] - hw minY:-_boxB[3] - hh
									   maxX:_boxB[2] + hw maxY:_boxB[3] + hh]) {
				best = _sweptResult[0];
			}
			if (best == FLT_MAX || best <= 0.0f) {
				// t = 0 means the sprite was already touching when the frame
				// began, and you cannot tunnel out of a contact you are
				// already in. Pulling it back for that is what pins a body
				// resting on a slope: it is dragged back to where it started
				// every frame while its speed along the surface keeps
				// climbing, until it finally breaks loose and looks like it
				// was launched. The static resolver owns this case.
				continue;
			}
			if (solid.oneWay && (dy <= 0.0f || s.velocityY < 0.0f)) {
				continue; // one-way: only a fall onto the upper face counts
			}
			if (best < earliest) {
				earliest = best;
			}
			continue;
		}
		if (circle && solid.circleHitbox) {
			[solid hitCenter:_centerB];
			float sum = r + [solid hitRadius];
			float fx = cx - _centerB[0];
			float fy = cy - _centerB[1];
			float t;
			if (fx * fx + fy * fy <= sum * sum) {
				continue; // already touching: nothing to sweep, see above
			} else {
				float a = dx * dx + dy * dy;
				float b = 2.0f * (fx * dx + fy * dy);
				float c = fx * fx + fy * fy - sum * sum;
				float disc = b * b - 4.0f * a * c;
				if (disc < 0.0f) {
					continue;
				}
				t = (-b - sqrtf(disc)) / (2.0f * a);
				if (t < 0.0f || t > 1.0f) {
					continue;
				}
			}
			if (solid.oneWay) {
				// same top-face rule as the static resolver: the contact
				// normal has to point up out of the solid
				float hy = cy + dy * t - _centerB[1];
				float nl = hypotf(cx + dx * t - _centerB[0], hy);
				float ny = (nl > 1e-6f) ? hy / nl : -1.0f;
				if (ny > -0.7f || s.velocityY < 0.0f) {
					continue;
				}
			}
			if (t < earliest) {
				earliest = t;
			}
			continue;
		}
		[solid computeAABB:_aabbB];
		if (![self sweptHitFromX:cx y:cy dx:dx dy:dy
							minX:_aabbB[0] - hw minY:_aabbB[1] - hh
							maxX:_aabbB[2] + hw maxY:_aabbB[3] + hh]) {
			continue;
		}
		if (_sweptResult[0] <= 0.0f) {
			// Already overlapping when the frame began. There is nothing to
			// sweep out of a contact you are already in, and pulling the
			// sprite back for it drags a resting body backwards every frame
			// while its speed along the surface keeps building.
			continue;
		}
		if (solid.oneWay
				&& (_sweptResult[1] != 1.0f || dy <= 0.0f || s.velocityY < 0.0f)) {
			continue; // one-way: only falling onto the top face counts
		}
		if (_sweptResult[0] < earliest) {
			earliest = _sweptResult[0];
		}
	}
	if (earliest >= 1.0f) {
		return; // no crossing (end-position overlaps resolve statically)
	}
	float t = MIN(1.0f, earliest + 0.5f / sqrtf(len2));
	float back = 1.0f - t;
	s.x -= dx * back;
	s.y -= dy * back;
	// keep the carry delta honest in case something rides this sprite
	s.frameDeltaX -= dx * back;
	s.frameDeltaY -= dy * back;
}

/** Shape-aware overlap test (rect/rect, circle/circle, circle/rect, and
 *  either of those against a rect that turns with its sprite). */
- (BOOL)shapesOverlap:(TGSprite *)a with:(TGSprite *)b
{
	if (a.obbHitbox || b.obbHitbox) {
		if (a.circleHitbox || b.circleHitbox) {
			TGSprite *circle = a.circleHitbox ? a : b;
			TGSprite *box = a.circleHitbox ? b : a;
			[circle hitCenter:_centerA];
			[box hitBox:_boxB];
			// overlap only needs the yes/no, so the contact normal is moot here
			return [self circleAtX:_centerA[0] y:_centerA[1]
							radius:[circle hitRadius] vsObb:_boxB
								vx:0.0f vy:0.0f out:_contact];
		}
		[a hitBox:_boxA];
		[b hitBox:_boxB];
		return [self obb:_boxA vsObb:_boxB out:_contact];
	}
	if (a.circleHitbox && b.circleHitbox) {
		[a hitCenter:_centerA];
		[b hitCenter:_centerB];
		float dx = _centerB[0] - _centerA[0];
		float dy = _centerB[1] - _centerA[1];
		float r = [a hitRadius] + [b hitRadius];
		return dx * dx + dy * dy < r * r;
	}
	if (a.circleHitbox || b.circleHitbox) {
		TGSprite *circle = a.circleHitbox ? a : b;
		TGSprite *rect = a.circleHitbox ? b : a;
		[circle hitCenter:_centerA];
		[rect computeAABB:_aabbB];
		float closestX = MIN(MAX(_centerA[0], _aabbB[0]), _aabbB[2]);
		float closestY = MIN(MAX(_centerA[1], _aabbB[1]), _aabbB[3]);
		float dx = _centerA[0] - closestX;
		float dy = _centerA[1] - closestY;
		float r = [circle hitRadius];
		return dx * dx + dy * dy < r * r;
	}
	[a computeAABB:_aabbA];
	[b computeAABB:_aabbB];
	return _aabbA[0] < _aabbB[2] && _aabbA[2] > _aabbB[0]
		&& _aabbA[1] < _aabbB[3] && _aabbA[3] > _aabbB[1];
}

/**
 * Moving platforms carry: before resolving, the rider inherits the
 * per-frame movement of the solid it stood on last frame, so it is
 * carried sideways and stays glued on the way down instead of
 * re-landing every frame. frameDelta excludes wrap teleports, and
 * direct JS position writes never enter it, so a teleporting
 * platform leaves its rider behind (as it should).
 */
- (void)carryByGround:(TGSprite *)s
{
	TGSprite *ground = s.groundSprite;
	if (ground == nil || s.dragged) { // a held finger outranks the platform
		return;
	}
	if (!ground.visible || ground.scene != self) {
		s.groundSprite = nil; // platform vanished under the rider
		return;
	}
	if (!ground.carryRiders) {
		return; // world-scroll terrain: the rider stays put
	}
	s.x += ground.frameDeltaX;
	s.y += ground.frameDeltaY;
}

/**
 * Circle against an oriented rect. The circle's center is taken into the
 * box's own frame, where the box is axis-aligned and the existing
 * closest-point test applies unchanged; the contact normal is rotated back
 * out at the end. out = { nx, ny, penetration }, normal pointing from the
 * box toward the circle. NO when they miss. See the Android twin.
 */
- (BOOL)circleAtX:(float)cx y:(float)cy radius:(float)r vsObb:(float *)box
			   vx:(float)vx vy:(float)vy out:(float *)out
{
	float cos_ = cosf(box[4]);
	float sin_ = sinf(box[4]);
	float rx = cx - box[0];
	float ry = cy - box[1];
	float lx = rx * cos_ + ry * sin_;   // into the box's frame
	float ly = -rx * sin_ + ry * cos_;
	float hx = box[2];
	float hy = box[3];
	float clampedX = MIN(MAX(lx, -hx), hx);
	float clampedY = MIN(MAX(ly, -hy), hy);
	float dx = lx - clampedX;
	float dy = ly - clampedY;
	float d2 = dx * dx + dy * dy;
	if (d2 >= r * r) {
		return NO;
	}
	// A corner is a point, and a point cannot hold anything up. Left with the
	// corner-to-center normal, a ball landing on the tip of a turned box takes
	// the hit almost straight up: at high restitution it pops into the air and
	// hangs there, at low restitution the bounce falls under the settle
	// threshold and the ball perches on the point and creeps off. Both read as
	// the ball freezing. Resolving against the face it is actually running
	// into makes it glance off in a third of a second instead.
	if (fabsf(fabsf(clampedX) - hx) < 1e-4f && fabsf(fabsf(clampedY) - hy) < 1e-4f) {
		float lvx = vx * cos_ + vy * sin_;
		float lvy = -vx * sin_ + vy * cos_;
		float faceX = (clampedX < 0.0f) ? -1.0f : (clampedX > 0.0f) ? 1.0f : 0.0f;
		float faceY = (clampedY < 0.0f) ? -1.0f : (clampedY > 0.0f) ? 1.0f : 0.0f;
		BOOL useX = (lvx * faceX) < (lvy * faceY); // the one it runs into
		float fnx = useX ? faceX : 0.0f;
		float fny = useX ? 0.0f : faceY;
		float gap = (lx * fnx + ly * fny) - (useX ? hx : hy);
		float pen = r - gap;
		if (pen > 0.0f) {
			out[0] = fnx * cos_ - fny * sin_;
			out[1] = fnx * sin_ + fny * cos_;
			out[2] = pen;
			return YES;
		}
	}
	float lnx, lny, penetration;
	if (d2 > 1e-6f) {
		float d = sqrtf(d2);
		lnx = dx / d;
		lny = dy / d;
		penetration = r - d;
	} else {
		// center inside the box — out through the nearest face
		float toLeft = lx + hx;
		float toRight = hx - lx;
		float toTop = ly + hy;
		float toBottom = hy - ly;
		float minFace = MIN(MIN(toLeft, toRight), MIN(toTop, toBottom));
		lnx = (minFace == toLeft) ? -1.0f : (minFace == toRight) ? 1.0f : 0.0f;
		lny = (lnx != 0.0f) ? 0.0f : (minFace == toTop) ? -1.0f : 1.0f;
		penetration = minFace + r;
	}
	out[0] = lnx * cos_ - lny * sin_;   // back into world space
	out[1] = lnx * sin_ + lny * cos_;
	out[2] = penetration;
	return YES;
}

/**
 * Two oriented rects, by separating axes. Rectangles only need four
 * candidate axes — each box's own two — and if the boxes overlap on all
 * four, the smallest of those overlaps is the shortest way out. An
 * unrotated box is just an oriented one at zero radians, so this also
 * covers a plain rect against a tilted platform. out = { nx, ny,
 * penetration }, normal pointing from b toward a. NO when any axis
 * separates them.
 */
- (BOOL)obb:(float *)a vsObb:(float *)b out:(float *)out
{
	float ca = cosf(a[4]);
	float sa = sinf(a[4]);
	float cb = cosf(b[4]);
	float sb = sinf(b[4]);
	_satAxes[0] = ca;   _satAxes[1] = sa;    // a's own two axes
	_satAxes[2] = -sa;  _satAxes[3] = ca;
	_satAxes[4] = cb;   _satAxes[5] = sb;    // b's
	_satAxes[6] = -sb;  _satAxes[7] = cb;
	float dx = a[0] - b[0];
	float dy = a[1] - b[1];
	float best = FLT_MAX;
	float bestX = 0.0f;
	float bestY = 0.0f;
	for (int i = 0; i < 4; i++) {
		float nx = _satAxes[i * 2];
		float ny = _satAxes[i * 2 + 1];
		// how far each box reaches along this axis from its own center
		float ra = a[2] * fabsf(nx * ca + ny * sa) + a[3] * fabsf(-nx * sa + ny * ca);
		float rb = b[2] * fabsf(nx * cb + ny * sb) + b[3] * fabsf(-nx * sb + ny * cb);
		float along = dx * nx + dy * ny;
		float overlap = ra + rb - fabsf(along);
		if (overlap <= 0.0f) {
			return NO; // a separating axis: they cannot be touching
		}
		if (overlap < best) {
			best = overlap;
			float sign = (along < 0.0f) ? -1.0f : 1.0f; // orient from b toward a
			bestX = nx * sign;
			bestY = ny * sign;
		}
	}
	out[0] = bestX;
	out[1] = bestY;
	out[2] = best;
	return YES;
}

/**
 * Bilateral circle solids: a pair that lists each other's groups and whose
 * sprites are both in `solidMode: 'push'` is resolved once, not once per
 * direction. Each body takes half the separation, and the closing part of
 * the relative velocity is exchanged at equal mass — for two equal circles
 * with restitution 1 that is a straight swap of the normal components,
 * which is what a break shot needs. Tangential velocity is untouched: no
 * friction, no spin. See the Android twin.
 *
 * Runs before the one-sided resolver, which skips push solids, so a pair is
 * never corrected twice in a frame.
 */
- (void)resolveBilateralPairs:(NSArray<TGSprite *> *)list
{
	NSUInteger n = list.count;
	for (NSUInteger i = 0; i < n; i++) {
		TGSprite *a = list[i];
		NSSet<NSString *> *ga = a.solidWith;
		if (!a.circleHitbox || !a.visible || ga.count == 0
				|| a.solidMode != TGSolidPush) {
			continue;
		}
		for (NSUInteger j = i + 1; j < n; j++) {
			TGSprite *b = list[j];
			if (![self isBilateralPair:a with:b groups:ga]) {
				continue;
			}
			[a hitCenter:_centerA];
			[b hitCenter:_centerB];
			float dx = _centerA[0] - _centerB[0];
			float dy = _centerA[1] - _centerB[1];
			float sum = [a hitRadius] + [b hitRadius];
			float d2 = dx * dx + dy * dy;
			if (d2 >= sum * sum) {
				continue;
			}
			float nx, ny, penetration;
			if (d2 > 1e-6f) {
				float d = sqrtf(d2);
				nx = dx / d;
				ny = dy / d;
				penetration = sum - d;
			} else {
				// concentric — the geometry carries no direction
				nx = 0.0f;
				ny = -1.0f;
				penetration = sum;
			}
			// Split the separation instead of moving one body all of it
			if (penetration > TGSlop) {
				float half = penetration * 0.5f;
				a.x += nx * half;
				a.y += ny * half;
				b.x -= nx * half;
				b.y -= ny * half;
			}
			float vn = (a.velocityX - b.velocityX) * nx
					 + (a.velocityY - b.velocityY) * ny;
			if (vn >= 0.0f) {
				continue; // already separating — leave the velocities alone
			}
			// Equal masses: each body takes half of (1 + e) * vn, in opposite
			// directions. The springier of the two wins — the same mix a body
			// gets against a static surface.
			float e = MAX(a.restitution, b.restitution);
			float impulse = -(1.0f + e) * vn * 0.5f;
			a.velocityX += impulse * nx;
			a.velocityY += impulse * ny;
			b.velocityX -= impulse * nx;
			b.velocityY -= impulse * ny;
		}
	}
}

/** Both circles, both visible, both in push mode, and each listing the
 *  other's group. Anything less falls through to the ordinary one-sided
 *  resolver, so `solidWith` keeps its old meaning by default — including a
 *  one-way pairing, where only one side names the other. */
- (BOOL)isBilateralPair:(TGSprite *)a with:(TGSprite *)b groups:(NSSet<NSString *> *)ga
{
	if (!a.circleHitbox || !a.visible || a.solidMode != TGSolidPush) {
		return NO;
	}
	if (!b.circleHitbox || !b.visible || b.solidMode != TGSolidPush) {
		return NO;
	}
	NSSet<NSString *> *gb = b.solidWith;
	return a.collisionGroup != nil && b.collisionGroup != nil
		&& [ga containsObject:b.collisionGroup]
		&& [gb containsObject:a.collisionGroup];
}

- (void)resolveSolids:(NSArray<TGSprite *> *)list layers:(NSArray<TGTileLayer *> *)layers
{
	[self resolveBilateralPairs:list];
	for (TGSprite *s in list) {
		NSSet<NSString *> *groups = s.solidWith;
		if (groups.count == 0 || !s.visible) {
			continue;
		}
		[self carryByGround:s];
		if (s.swept) {
			[self sweepAgainstSolids:s inList:list layers:layers groups:groups];
		}
		if (s.circleHitbox) {
			[self resolveCircleSolids:s inList:list layers:layers groups:groups];
			continue;
		}
		BOOL wasOnGround = s.onGround;
		BOOL grounded = NO;
		TGSprite *groundedOn = nil;
		// The level comes first, moving solids on top of it
		BOOL onTiles = [self resolveTileRect:s layers:layers groups:groups];
		[s computeAABB:_aabbA];
		for (TGSprite *solid in list) {
			NSString *group = solid.collisionGroup;
			if (solid == s || group == nil || !solid.visible || ![groups containsObject:group]) {
				continue;
			}
			// Bounciness belongs to the contact, not to one side of it: the
			// springier of the two surfaces wins, the way Box2D mixes it.
			// Every solid defaults to 0, so a scene that never sets it on a
			// surface behaves exactly as before — but a floor can now be
			// given a bounce of its own without making the ball bouncy
			// everywhere else it touches.
			float e = MAX(s.restitution, solid.restitution);
			if (solid.obbHitbox || s.obbHitbox) {
				// Separating axes instead of the two screen axes, so a
				// tilted platform pushes along its own face — which is what
				// lets a rider slide down a slope instead of standing on an
				// invisible ledge.
				[s hitBox:_boxA];
				[solid hitBox:_boxB];
				if (![self obb:_boxA vsObb:_boxB out:_contact]) {
					continue;
				}
				float nx = _contact[0];
				float ny = _contact[1];
				float penetration = _contact[2];
				if (solid.oneWay && (ny > -0.7f || s.velocityY < 0.0f)) {
					continue; // one-way: riders only catch on the upper face
				}
				if (penetration > TGSlop) {
					s.x += nx * penetration;
					s.y += ny * penetration;
				}
				float vn = s.velocityX * nx + s.velocityY * ny;
				if (vn < 0.0f) {
					float bounce = -vn * e;
					if (e > 0.0f && bounce > 40.0f) {
						s.velocityX -= (1.0f + e) * vn * nx;
						s.velocityY -= (1.0f + e) * vn * ny;
					} else {
						s.velocityX -= vn * nx;
						s.velocityY -= vn * ny;
						if (ny < -0.7f) {
							grounded = YES;
							groundedOn = solid;
						}
					}
				}
				[s computeAABB:_aabbA]; // position changed — refresh for the next solid
				continue;
			}
			[solid computeAABB:_aabbB];
			float overlapX = MIN(_aabbA[2], _aabbB[2]) - MAX(_aabbA[0], _aabbB[0]);
			float overlapY = MIN(_aabbA[3], _aabbB[3]) - MAX(_aabbA[1], _aabbB[1]);
			if (overlapX <= 0.0f || overlapY <= 0.0f) {
				continue;
			}
			BOOL fromAbove = _aabbA[1] + _aabbA[3] < _aabbB[1] + _aabbB[3];
			if (solid.oneWay) {
				// pass-through except when falling onto the top edge:
				// the rider's bottom was above it last frame
				if (s.velocityY < 0.0f || _aabbA[3] - s.frameDeltaY > _aabbB[1] + 2.0f) {
					continue;
				}
				fromAbove = YES; // one-way only ever resolves as a landing
			}
			if (overlapY <= overlapX || solid.oneWay) {
				// vertical resolution (compare AABB centers, *2 avoids the division)
				if (fromAbove) {
					s.y -= overlapY; // hit the solid from above
					float bounce = (e > 0.0f && s.velocityY > 0.0f)
						? s.velocityY * e : 0.0f;
					if (bounce > 40.0f) {
						s.velocityY = -bounce; // rigid-body bounce
					} else {
						if (s.velocityY > 0.0f) {
							s.velocityY = 0.0f;
						}
						grounded = YES;
						groundedOn = solid;
					}
				} else {
					s.y += overlapY; // bumped from below
					if (s.velocityY < 0.0f) {
						s.velocityY = (e > 0.0f) ? -s.velocityY * e : 0.0f;
					}
				}
			} else {
				// horizontal resolution (walls); bouncy sprites reflect,
				// others keep velocity so held-button movement resumes
				// as soon as the wall ends
				if (_aabbA[0] + _aabbA[2] < _aabbB[0] + _aabbB[2]) {
					s.x -= overlapX;
					if (e > 0.0f && s.velocityX > 0.0f) {
						s.velocityX = -s.velocityX * e;
					}
				} else {
					s.x += overlapX;
					if (e > 0.0f && s.velocityX < 0.0f) {
						s.velocityX = -s.velocityX * e;
					}
				}
			}
			[s computeAABB:_aabbA]; // position changed — refresh for the next solid
		}
		grounded |= onTiles;
		s.onGround = grounded;
		s.groundSprite = grounded ? groundedOn : nil;
		if (grounded && !wasOnGround) {
			id<TGSpriteEventListener> listener = s.eventListener;
			if (listener != nil) {
				[listener sprite:s landedOn:groundedOn];
			}
		}
	}
}

/**
 * Circle-vs-solid resolution: pushed out along the contact normal, so the
 * ball bounces off corners naturally. A solid that declares a circle
 * hitbox is resolved as a circle — normal from center to center, no
 * phantom faces or corners — and every other solid keeps the
 * closest-point-on-AABB normal. See the Android twin.
 */
- (void)resolveCircleSolids:(TGSprite *)s
					 inList:(NSArray<TGSprite *> *)list
					 layers:(NSArray<TGTileLayer *> *)layers
					 groups:(NSSet<NSString *> *)groups
{
	BOOL wasOnGround = s.onGround;
	BOOL grounded = NO;
	TGSprite *groundedOn = nil;
	float r = [s hitRadius];
	// The level comes first, moving solids on top of it
	grounded = [self resolveTileCircle:s layers:layers groups:groups radius:r];
	for (TGSprite *solid in list) {
		NSString *group = solid.collisionGroup;
		if (solid == s || group == nil || !solid.visible || ![groups containsObject:group]) {
			continue;
		}
		if ([self isBilateralPair:s with:solid groups:groups]) {
			continue; // already resolved once, in resolveBilateralPairs
		}
		// Bounciness belongs to the contact, not to one side of it: the
		// springier of the two surfaces wins, the way Box2D mixes it.
		// Every solid defaults to 0, so a scene that never sets it on a
		// surface behaves exactly as before — but a floor can now be
		// given a bounce of its own without making the ball bouncy
		// everywhere else it touches.
		float e = MAX(s.restitution, solid.restitution);
		[s hitCenter:_centerA];
		float cx = _centerA[0];
		float cy = _centerA[1];
		float nx, ny, penetration;
		if (solid.solidMode == TGSolidContain && solid.circleHitbox) {
			// Inward boundary: keep the ball's center within R - r of the
			// container's. The correcting normal points back toward the
			// center, so the whole tail below (push-out, restitution,
			// grounding on the lower arc, land) works unchanged.
			[solid hitCenter:_centerB];
			float allowed = [solid hitRadius] - r;
			float dx = cx - _centerB[0];
			float dy = cy - _centerB[1];
			float d2 = dx * dx + dy * dy;
			if (allowed <= 0.0f || d2 <= allowed * allowed) {
				continue; // ball still inside, or it does not fit at all
			}
			float d = sqrtf(d2);
			nx = -dx / d;
			ny = -dy / d;
			penetration = d - allowed;
		} else if (solid.obbHitbox) {
			// Rect that turns with its sprite: the normal comes out
			// perpendicular to the real face, not to a phantom axis
			[solid hitBox:_boxB];
			if (![self circleAtX:cx y:cy radius:r vsObb:_boxB
								 vx:s.velocityX vy:s.velocityY out:_contact]) {
				continue;
			}
			nx = _contact[0];
			ny = _contact[1];
			penetration = _contact[2];
		} else if (solid.circleHitbox) {
			// Circle vs circle: the normal is the line between the two
			// centers and the overlap is r1 + r2 - d.
			[solid hitCenter:_centerB];
			float sum = r + [solid hitRadius];
			float dx = cx - _centerB[0];
			float dy = cy - _centerB[1];
			float d2 = dx * dx + dy * dy;
			if (d2 >= sum * sum) {
				continue;
			}
			if (d2 > 1e-6f) {
				float d = sqrtf(d2);
				nx = dx / d;
				ny = dy / d;
				penetration = sum - d;
			} else {
				// concentric — the geometry carries no direction, so pick
				// a fixed one rather than dividing by zero
				nx = 0.0f;
				ny = -1.0f;
				penetration = sum;
			}
		} else {
			[solid computeAABB:_aabbB];
			float closestX = MIN(MAX(cx, _aabbB[0]), _aabbB[2]);
			float closestY = MIN(MAX(cy, _aabbB[1]), _aabbB[3]);
			float dx = cx - closestX;
			float dy = cy - closestY;
			float d2 = dx * dx + dy * dy;
			if (d2 >= r * r) {
				continue;
			}
			if (d2 > 1e-6f) {
				float d = sqrtf(d2);
				nx = dx / d;
				ny = dy / d;
				penetration = r - d;
			} else {
				// center inside the solid — push out along the nearest face
				float toLeft = cx - _aabbB[0];
				float toRight = _aabbB[2] - cx;
				float toTop = cy - _aabbB[1];
				float toBottom = _aabbB[3] - cy;
				float minFace = MIN(MIN(toLeft, toRight), MIN(toTop, toBottom));
				nx = (minFace == toLeft) ? -1.0f : (minFace == toRight) ? 1.0f : 0.0f;
				ny = (nx != 0.0f) ? 0.0f : (minFace == toTop) ? -1.0f : 1.0f;
				penetration = minFace + r;
			}
		}
		if (solid.oneWay && solid.solidMode == TGSolidBlock
				&& (ny > -0.7f || s.velocityY < 0.0f)) {
			continue; // one-way: balls only land on the top face
		}
		if (penetration > TGSlop) {
			s.x += nx * penetration;
			s.y += ny * penetration;
		}
		float vn = s.velocityX * nx + s.velocityY * ny;
		if (vn < 0.0f) {
			float bounce = -vn * e;
			if (e > 0.0f && bounce > 40.0f) {
				s.velocityX -= (1.0f + e) * vn * nx;
				s.velocityY -= (1.0f + e) * vn * ny;
			} else {
				s.velocityX -= vn * nx;
				s.velocityY -= vn * ny;
				if (ny < -0.7f) {
					grounded = YES;
					groundedOn = solid;
				}
			}
		}
	}
	s.onGround = grounded;
	s.groundSprite = grounded ? groundedOn : nil;
	if (grounded && !wasOnGround) {
		id<TGSpriteEventListener> listener = s.eventListener;
		if (listener != nil) {
			[listener sprite:s landedOn:groundedOn];
		}
	}
}

/**
 * Pins attached sprites to their targets' final positions — after
 * physics and solid resolution, so a tag never lags its owner by a
 * frame, and before collision checks, so an attached hitbox tests at
 * its real position. Chains resolve parent-first via recursion
 * (re-applying a parent is harmless, placement is absolute) and the
 * depth cap breaks accidental cycles.
 */
- (void)applyAttachments:(NSArray<TGSprite *> *)list
{
	for (TGSprite *s in list) {
		if (s.attachTarget != nil) {
			[self applyAttachment:s depth:0];
		}
	}
}

- (void)applyAttachment:(TGSprite *)s depth:(int)depth
{
	TGSprite *target = s.attachTarget;
	if (target == nil || target == s || target.scene != self) {
		return; // orphaned — keep the last applied state
	}
	if (target.attachTarget != nil && depth < 8) {
		[self applyAttachment:target depth:depth + 1];
	}
	// Opacity inherits even while dragged; parent-first recursion
	// means a chain multiplies down correctly.
	s.attachOpacity = [target effectiveOpacity];
	if (s.dragged) {
		return; // held by a finger — the finger outranks the position
	}
	float ox = s.attachOffsetX;
	float oy = s.attachOffsetY;
	if (s.attachRotate) {
		float rad = target.rotation * (float)M_PI / 180.0f;
		float cosr = cosf(rad);
		float sinr = sinf(rad);
		float rx = ox * cosr - oy * sinr;
		oy = ox * sinr + oy * cosr;
		ox = rx;
		s.rotation = target.rotation;
	}
	float tx = target.x;
	float ty = target.y;
	// Cross-space attach (screenFixed tag on a world sprite, or the
	// reverse): convert the target position into this sprite's space,
	// so the offset stays in the sprite's own coordinates.
	if (s.screenFixed != target.screenFixed) {
		if (s.screenFixed) {
			tx = [self worldToScreenX:tx];
			ty = [self worldToScreenY:ty];
		} else {
			tx = [self screenToWorldX:tx];
			ty = [self screenToWorldY:ty];
		}
	}
	s.x = tx + ox;
	s.y = ty + oy;
}

/**
 * AABB overlap test between sprites that declare `collidesWith` groups
 * and visible sprites carrying a matching `collisionGroup`. Fires the
 * collision callback once per overlap-enter (re-fires after separation).
 */
#pragma mark Tile layer solids
// A mover only ever looks at the cells under its own hitbox (plus one
// ring for neighbor checks), so the cost is per contact, not per map.
// The one thing a grid has that a list of sprite solids does not is
// seams: two floor tiles side by side share an edge, and that edge is
// not a face anything can hit. A face is only real when the cell across
// it is not solid — the resolvers below push out through real faces
// only, which is what keeps a rider from snagging on every tile
// boundary it slides across. See the Android twin.

- (BOOL)resolveTileRect:(TGSprite *)s
				 layers:(NSArray<TGTileLayer *> *)layers
				 groups:(NSSet<NSString *> *)groups
{
	BOOL grounded = NO;
	for (TGTileLayer *layer in layers) {
		if (![layer blocks:groups]) {
			continue;
		}
		float tw = [layer cellWidth];
		float th = [layer cellHeight];
		if (tw <= 0.0f || th <= 0.0f) {
			continue;
		}
		float lx = layer.x;
		float ly = layer.y;
		float e = MAX(s.restitution, layer.restitution);
		[s computeAABB:_aabbA];
		int c0 = MAX(0, (int)floorf((_aabbA[0] - lx) / tw));
		int c1 = MIN([layer cols] - 1, (int)floorf((_aabbA[2] - lx) / tw));
		int r0 = MAX(0, (int)floorf((_aabbA[1] - ly) / th));
		int r1 = MIN([layer rows] - 1, (int)floorf((_aabbA[3] - ly) / th));
		for (int row = r0; row <= r1; row++) {
			for (int col = c0; col <= c1; col++) {
				uint8_t flag = [layer flagAtCol:col row:row];
				if (flag == 0) {
					continue;
				}
				float bx0 = lx + col * tw;
				float by0 = ly + row * th;
				float bx1 = bx0 + tw;
				float by1 = by0 + th;
				float overlapX = MIN(_aabbA[2], bx1) - MAX(_aabbA[0], bx0);
				float overlapY = MIN(_aabbA[3], by1) - MAX(_aabbA[1], by0);
				if (overlapX <= 0.0f || overlapY <= 0.0f) {
					continue;
				}
				BOOL fromAbove = _aabbA[1] + _aabbA[3] < by0 + by1;
				BOOL fromLeft = _aabbA[0] + _aabbA[2] < bx0 + bx1;
				BOOL vertical;
				if ((flag & TGTileFlagSolid) == 0) {
					// one-way: pass-through except when falling onto the
					// top edge — the rider's bottom was above it last frame
					if (s.velocityY < 0.0f || _aabbA[3] - s.frameDeltaY > by0 + 2.0f) {
						continue;
					}
					fromAbove = YES;
					vertical = YES;
				} else {
					BOOL canY = fromAbove ? ![layer isSolidCol:col row:row - 1] : ![layer isSolidCol:col row:row + 1];
					BOOL canX = fromLeft ? ![layer isSolidCol:col - 1 row:row] : ![layer isSolidCol:col + 1 row:row];
					if (!canX && !canY) {
						continue; // buried in the middle of a solid block
					}
					vertical = (overlapY <= overlapX && canY) || !canX;
				}
				if (vertical) {
					if (fromAbove) {
						s.y -= overlapY;
						float bounce = (e > 0.0f && s.velocityY > 0.0f) ? s.velocityY * e : 0.0f;
						if (bounce > 40.0f) {
							s.velocityY = -bounce;
						} else {
							if (s.velocityY > 0.0f) {
								s.velocityY = 0.0f;
							}
							grounded = YES;
						}
					} else {
						s.y += overlapY;
						if (s.velocityY < 0.0f) {
							s.velocityY = (e > 0.0f) ? -s.velocityY * e : 0.0f;
						}
					}
				} else if (fromLeft) {
					s.x -= overlapX;
					if (e > 0.0f && s.velocityX > 0.0f) {
						s.velocityX = -s.velocityX * e;
					}
				} else {
					s.x += overlapX;
					if (e > 0.0f && s.velocityX < 0.0f) {
						s.velocityX = -s.velocityX * e;
					}
				}
				[s computeAABB:_aabbA]; // position changed — refresh for the next cell
			}
		}
	}
	return grounded;
}

- (BOOL)resolveTileCircle:(TGSprite *)s
				   layers:(NSArray<TGTileLayer *> *)layers
				   groups:(NSSet<NSString *> *)groups
				   radius:(float)r
{
	BOOL grounded = NO;
	for (TGTileLayer *layer in layers) {
		if (![layer blocks:groups]) {
			continue;
		}
		float tw = [layer cellWidth];
		float th = [layer cellHeight];
		if (tw <= 0.0f || th <= 0.0f) {
			continue;
		}
		float lx = layer.x;
		float ly = layer.y;
		float e = MAX(s.restitution, layer.restitution);
		[s hitCenter:_centerA];
		float cx = _centerA[0];
		float cy = _centerA[1];
		int c0 = MAX(0, (int)floorf((cx - r - lx) / tw));
		int c1 = MIN([layer cols] - 1, (int)floorf((cx + r - lx) / tw));
		int r0 = MAX(0, (int)floorf((cy - r - ly) / th));
		int r1 = MIN([layer rows] - 1, (int)floorf((cy + r - ly) / th));
		for (int row = r0; row <= r1; row++) {
			for (int col = c0; col <= c1; col++) {
				uint8_t flag = [layer flagAtCol:col row:row];
				if (flag == 0) {
					continue;
				}
				float bx0 = lx + col * tw;
				float by0 = ly + row * th;
				float bx1 = bx0 + tw;
				float by1 = by0 + th;
				float closestX = MIN(MAX(cx, bx0), bx1);
				float closestY = MIN(MAX(cy, by0), by1);
				float dx = cx - closestX;
				float dy = cy - closestY;
				float d2 = dx * dx + dy * dy;
				if (d2 >= r * r) {
					continue;
				}
				float nx, ny, penetration;
				if (d2 > 1e-6f) {
					float d = sqrtf(d2);
					nx = dx / d;
					ny = dy / d;
					penetration = r - d;
				} else {
					// center inside the cell — out through the nearest face
					float toLeft = cx - bx0;
					float toRight = bx1 - cx;
					float toTop = cy - by0;
					float toBottom = by1 - cy;
					float minFace = MIN(MIN(toLeft, toRight), MIN(toTop, toBottom));
					nx = (minFace == toLeft) ? -1.0f : (minFace == toRight) ? 1.0f : 0.0f;
					ny = (nx != 0.0f) ? 0.0f : (minFace == toTop) ? -1.0f : 1.0f;
					penetration = minFace + r;
				}
				// Drop the part of the normal that points into a solid
				// neighbor; what remains is the real face, so measure the
				// overlap against that face instead of the corner
				BOOL cutX = (nx < 0.0f && [layer isSolidCol:col - 1 row:row])
					|| (nx > 0.0f && [layer isSolidCol:col + 1 row:row]);
				BOOL cutY = (ny < 0.0f && [layer isSolidCol:col row:row - 1])
					|| (ny > 0.0f && [layer isSolidCol:col row:row + 1]);
				if (cutX && cutY) {
					continue;
				}
				if (cutX && ny != 0.0f) {
					ny = (ny < 0.0f) ? -1.0f : 1.0f;
					nx = 0.0f;
					penetration = r - ((ny < 0.0f) ? (by0 - cy) : (cy - by1));
				} else if (cutY && nx != 0.0f) {
					nx = (nx < 0.0f) ? -1.0f : 1.0f;
					ny = 0.0f;
					penetration = r - ((nx < 0.0f) ? (bx0 - cx) : (cx - bx1));
				} else if (cutX || cutY) {
					continue; // the only component pointed into the block
				}
				if (penetration <= 0.0f) {
					continue;
				}
				if ((flag & TGTileFlagSolid) == 0 && (ny > -0.7f || s.velocityY < 0.0f)) {
					continue; // one-way: balls only land on the top face
				}
				if (penetration > TGSlop) {
					s.x += nx * penetration;
					s.y += ny * penetration;
				}
				float vn = s.velocityX * nx + s.velocityY * ny;
				if (vn < 0.0f) {
					float bounce = -vn * e;
					if (e > 0.0f && bounce > 40.0f) {
						s.velocityX -= (1.0f + e) * vn * nx;
						s.velocityY -= (1.0f + e) * vn * ny;
					} else {
						s.velocityX -= vn * nx;
						s.velocityY -= vn * ny;
						if (ny < -0.7f) {
							grounded = YES;
						}
					}
				}
				[s hitCenter:_centerA]; // position changed — refresh for the next cell
				cx = _centerA[0];
				cy = _centerA[1];
			}
		}
	}
	return grounded;
}

- (float)sweepAgainstTiles:(TGSprite *)s
					layers:(NSArray<TGTileLayer *> *)layers
					groups:(NSSet<NSString *> *)groups
						cx:(float)cx cy:(float)cy dx:(float)dx dy:(float)dy
						hw:(float)hw hh:(float)hh
{
	float earliest = FLT_MAX;
	float minX = MIN(cx, cx + dx) - hw;
	float maxX = MAX(cx, cx + dx) + hw;
	float minY = MIN(cy, cy + dy) - hh;
	float maxY = MAX(cy, cy + dy) + hh;
	for (TGTileLayer *layer in layers) {
		if (![layer blocks:groups]) {
			continue;
		}
		float tw = [layer cellWidth];
		float th = [layer cellHeight];
		if (tw <= 0.0f || th <= 0.0f) {
			continue;
		}
		float lx = layer.x;
		float ly = layer.y;
		int c0 = MAX(0, (int)floorf((minX - lx) / tw));
		int c1 = MIN([layer cols] - 1, (int)floorf((maxX - lx) / tw));
		int r0 = MAX(0, (int)floorf((minY - ly) / th));
		int r1 = MIN([layer rows] - 1, (int)floorf((maxY - ly) / th));
		for (int row = r0; row <= r1; row++) {
			for (int col = c0; col <= c1; col++) {
				uint8_t flag = [layer flagAtCol:col row:row];
				if (flag == 0) {
					continue;
				}
				float bx0 = lx + col * tw;
				float by0 = ly + row * th;
				if (![self sweptHitFromX:cx y:cy dx:dx dy:dy
									minX:bx0 - hw minY:by0 - hh
									maxX:bx0 + tw + hw maxY:by0 + th + hh]) {
					continue;
				}
				float t = _sweptResult[0];
				if (t <= 0.0f || t >= earliest) {
					continue; // already touching, or a later face than one found
				}
				BOOL onX = _sweptResult[1] == 0.0f;
				if ((flag & TGTileFlagSolid) == 0) {
					if (onX || dy <= 0.0f || s.velocityY < 0.0f) {
						continue; // one-way: only a fall onto the top face counts
					}
				} else if (onX) {
					if (dx > 0.0f ? [layer isSolidCol:col - 1 row:row] : [layer isSolidCol:col + 1 row:row]) {
						continue; // an internal seam, not a wall
					}
				} else if (dy > 0.0f ? [layer isSolidCol:col row:row - 1] : [layer isSolidCol:col row:row + 1]) {
					continue;
				}
				earliest = t;
			}
		}
	}
	return earliest;
}

/**
 * Fires the collision callback once per overlap-enter and the
 * collision-end callback once per separation (also when the contact
 * partner is hidden, removed from the scene, or stops matching the
 * groups) — the enter/exit contact lifecycle of Unity/Godot triggers,
 * minus a per-frame "stay" that would need bridge traffic.
 */
- (void)checkCollisions:(NSArray<TGSprite *> *)list
{
	for (TGSprite *s in list) {
		NSSet<NSString *> *groups = s.collidesWith;
		if (groups.count == 0 || !s.visible) {
			// hidden or de-configured mid-contact: everything separates
			[self endAllCollisions:s];
			continue;
		}
		for (TGSprite *other in list) {
			NSString *group = other.collisionGroup;
			if (other == s || group == nil || !other.visible || ![groups containsObject:group]) {
				continue;
			}
			BOOL overlap = [self shapesOverlap:s with:other];
			if (!overlap && s.swept) {
				overlap = [self sweptShapesOverlap:s with:other];
			}
			if (overlap) {
				if (![s.colliding containsObject:other]) {
					[s.colliding addObject:other];
					id<TGSpriteEventListener> listener = s.eventListener;
					if (listener != nil) {
						[listener sprite:s collidedWith:other];
					}
				}
			} else if ([s.colliding containsObject:other]) {
				[s.colliding removeObject:other];
				fireCollisionEnd(s, other);
			}
		}
		// Contacts the loop above can no longer see: partner left the
		// scene, went invisible, or the group filter changed.
		if (s.colliding.count > 0) {
			NSMutableArray<TGSprite *> *stale = nil;
			for (TGSprite *other in s.colliding) {
				NSString *group = other.collisionGroup;
				if (other.scene != self || !other.visible
						|| group == nil || ![groups containsObject:group]) {
					if (stale == nil) {
						stale = [NSMutableArray array];
					}
					[stale addObject:other];
				}
			}
			for (TGSprite *other in stale) {
				[s.colliding removeObject:other];
				fireCollisionEnd(s, other);
			}
		}
	}
}

/** Separates every tracked contact of a sprite (hidden/de-configured). */
- (void)endAllCollisions:(TGSprite *)s
{
	if (s.colliding.count == 0) {
		return;
	}
	NSArray<TGSprite *> *contacts = [s.colliding allObjects];
	[s.colliding removeAllObjects];
	for (TGSprite *other in contacts) {
		fireCollisionEnd(s, other);
	}
}

static void fireCollisionEnd(TGSprite *s, TGSprite *other)
{
	id<TGSpriteEventListener> listener = s.eventListener;
	if (listener != nil) {
		[listener sprite:s separatedFrom:other];
	}
}

- (TGSprite *)hitTestX:(float)x y:(float)y
{
	NSArray<TGSprite *> *list = [self snapshot];
	for (NSInteger i = (NSInteger)list.count - 1; i >= 0; i--) {
		TGSprite *s = list[i];
		if ([s hitTestX:x y:y]) {
			return s;
		}
	}
	return nil;
}

@end
