#import "TGScene.h"
#import "TGParticleEmitter.h"
#import "TGPathfinder.h"
#import "TGRope.h"
#import "TGSkidTrail.h"
#import "TGSprite.h"
#import "TGTextSprite.h"
#import "TGBitmapFont.h"
#import "TGDefaultFont.h"
#import <float.h>
#import <math.h>

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
		_skidTrail = [[TGSkidTrail alloc] init];
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
		if ([_sprites containsObject:sprite]) {
			[_sprites removeObjectIdenticalTo:sprite];
			sprite.scene = nil;
			_snapshotCache = nil;
		}
	}
}

- (void)clear
{
	@synchronized (_sprites) {
		for (TGSprite *s in _sprites) {
			s.scene = nil;
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
{
	dt *= MAX(0.0f, self.timeScale);
	__block NSArray<TGSprite *> *list;
	__block NSArray<TGParticleEmitter *> *emitterList;
	__block NSArray<TGRope *> *ropeList;
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
	[self resolveSolids:list];
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
	return list;
}

- (void)update:(float)dt
{
	[self prepareFrame:dt emitters:NULL ropes:NULL];
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
	return [TGPathfinder findInSprites:[self snapshot] groups:groups
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
 */
- (void)sweepAgainstSolids:(TGSprite *)s
					inList:(NSArray<TGSprite *> *)list
					groups:(NSSet<NSString *> *)groups
{
	float dx = s.frameDeltaX;
	float dy = s.frameDeltaY;
	float len2 = dx * dx + dy * dy;
	if (len2 < 1e-4f) {
		return;
	}
	[s computeAABB:_aabbA];
	float hw = (_aabbA[2] - _aabbA[0]) / 2.0f;
	float hh = (_aabbA[3] - _aabbA[1]) / 2.0f;
	float cx = (_aabbA[0] + _aabbA[2]) / 2.0f - dx; // center at frame start
	float cy = (_aabbA[1] + _aabbA[3]) / 2.0f - dy;
	float earliest = FLT_MAX;
	for (TGSprite *solid in list) {
		NSString *group = solid.collisionGroup;
		if (solid == s || group == nil || !solid.visible || ![groups containsObject:group]) {
			continue;
		}
		[solid computeAABB:_aabbB];
		if (![self sweptHitFromX:cx y:cy dx:dx dy:dy
							minX:_aabbB[0] - hw minY:_aabbB[1] - hh
							maxX:_aabbB[2] + hw maxY:_aabbB[3] + hh]) {
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

/** Shape-aware overlap test (rect/rect, circle/circle, circle/rect). */
- (BOOL)shapesOverlap:(TGSprite *)a with:(TGSprite *)b
{
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

- (void)resolveSolids:(NSArray<TGSprite *> *)list
{
	for (TGSprite *s in list) {
		NSSet<NSString *> *groups = s.solidWith;
		if (groups.count == 0 || !s.visible) {
			continue;
		}
		[self carryByGround:s];
		if (s.swept) {
			[self sweepAgainstSolids:s inList:list groups:groups];
		}
		if (s.circleHitbox) {
			[self resolveCircleSolids:s inList:list groups:groups];
			continue;
		}
		BOOL wasOnGround = s.onGround;
		BOOL grounded = NO;
		TGSprite *groundedOn = nil;
		[s computeAABB:_aabbA];
		for (TGSprite *solid in list) {
			NSString *group = solid.collisionGroup;
			if (solid == s || group == nil || !solid.visible || ![groups containsObject:group]) {
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
					float bounce = (s.restitution > 0.0f && s.velocityY > 0.0f)
						? s.velocityY * s.restitution : 0.0f;
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
						s.velocityY = (s.restitution > 0.0f) ? -s.velocityY * s.restitution : 0.0f;
					}
				}
			} else {
				// horizontal resolution (walls); bouncy sprites reflect,
				// others keep velocity so held-button movement resumes
				// as soon as the wall ends
				if (_aabbA[0] + _aabbA[2] < _aabbB[0] + _aabbB[2]) {
					s.x -= overlapX;
					if (s.restitution > 0.0f && s.velocityX > 0.0f) {
						s.velocityX = -s.velocityX * s.restitution;
					}
				} else {
					s.x += overlapX;
					if (s.restitution > 0.0f && s.velocityX < 0.0f) {
						s.velocityX = -s.velocityX * s.restitution;
					}
				}
			}
			[s computeAABB:_aabbA]; // position changed — refresh for the next solid
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
}

/**
 * Circle-vs-AABB solid resolution: pushed out along the contact normal,
 * so the ball bounces off corners naturally — see the Android twin.
 */
- (void)resolveCircleSolids:(TGSprite *)s
					 inList:(NSArray<TGSprite *> *)list
					 groups:(NSSet<NSString *> *)groups
{
	BOOL wasOnGround = s.onGround;
	BOOL grounded = NO;
	TGSprite *groundedOn = nil;
	float r = [s hitRadius];
	for (TGSprite *solid in list) {
		NSString *group = solid.collisionGroup;
		if (solid == s || group == nil || !solid.visible || ![groups containsObject:group]) {
			continue;
		}
		[s hitCenter:_centerA];
		float cx = _centerA[0];
		float cy = _centerA[1];
		[solid computeAABB:_aabbB];
		float closestX = MIN(MAX(cx, _aabbB[0]), _aabbB[2]);
		float closestY = MIN(MAX(cy, _aabbB[1]), _aabbB[3]);
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
		if (solid.oneWay && (ny > -0.7f || s.velocityY < 0.0f)) {
			continue; // one-way: balls only land on the top face
		}
		s.x += nx * penetration;
		s.y += ny * penetration;
		float vn = s.velocityX * nx + s.velocityY * ny;
		if (vn < 0.0f) {
			float bounce = -vn * s.restitution;
			if (s.restitution > 0.0f && bounce > 40.0f) {
				s.velocityX -= (1.0f + s.restitution) * vn * nx;
				s.velocityY -= (1.0f + s.restitution) * vn * ny;
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
	if (target == nil || target == s || target.scene != self || s.dragged) {
		return; // orphaned or held by a finger — the finger outranks
	}
	if (target.attachTarget != nil && depth < 8) {
		[self applyAttachment:target depth:depth + 1];
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
