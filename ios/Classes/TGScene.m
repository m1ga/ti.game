#import "TGScene.h"
#import "TGParticleEmitter.h"
#import "TGRope.h"
#import "TGSkidTrail.h"
#import "TGSprite.h"
#import <math.h>

static float bottomEdge(TGSprite *s)
{
	return s.y + [s drawHeight] * fabsf(s.scaleY) * (1.0f - s.anchorY);
}

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
	float _aabbA[4];
	float _aabbB[4];
	float _centerA[2];
	float _centerB[2];
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
		_followTopFraction = 0.33f;
		_followBottomFraction = 0.7f;
		_followLeftFraction = -1.0f;
		_followRightFraction = 0.65f;
		_pendingShakeStrength = -1.0f;
		_bgAlpha = 1.0f;
	}
	return self;
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

- (void)add:(TGSprite *)sprite
{
	if (sprite == nil) {
		return;
	}
	@synchronized (_sprites) {
		if (![_sprites containsObject:sprite]) {
			[_sprites addObject:sprite];
			sprite.scene = self;
			_zOrderDirty = YES;
			if (sprite.ySort) {
				_hasYSort = YES;
			}
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
	}
}

- (void)markZOrderDirty
{
	@synchronized (_sprites) {
		_zOrderDirty = YES;
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
		return [_sprites copy];
	}
}

- (void)update:(float)dt
{
	NSArray<TGSprite *> *list = [self snapshot];
	for (TGSprite *s in list) {
		[s update:dt];
	}
	for (TGParticleEmitter *e in [self emittersSnapshot]) {
		[e update:dt];
	}
	// Ropes after sprites, so a dragged/physics-moved head is current
	for (TGRope *rope in [self ropesSnapshot]) {
		[rope update:dt];
	}
	[self.skidTrail update:dt];
	[self wrapSprites:list];
	[self resolveSolids:list];
	[self checkCollisions:list];
	[self updateFollow:dt];
	[self applyCameraBounds];
	[self updateShake:dt];
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

- (void)resolveSolids:(NSArray<TGSprite *> *)list
{
	for (TGSprite *s in list) {
		NSSet<NSString *> *groups = s.solidWith;
		if (groups.count == 0 || !s.visible) {
			continue;
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
			if (overlapY <= overlapX) {
				// vertical resolution (compare AABB centers, *2 avoids the division)
				if (_aabbA[1] + _aabbA[3] < _aabbB[1] + _aabbB[3]) {
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
	if (grounded && !wasOnGround) {
		id<TGSpriteEventListener> listener = s.eventListener;
		if (listener != nil) {
			[listener sprite:s landedOn:groundedOn];
		}
	}
}

/**
 * AABB overlap test between sprites that declare `collidesWith` groups
 * and visible sprites carrying a matching `collisionGroup`. Fires the
 * collision callback once per overlap-enter (re-fires after separation).
 */
- (void)checkCollisions:(NSArray<TGSprite *> *)list
{
	for (TGSprite *s in list) {
		NSSet<NSString *> *groups = s.collidesWith;
		if (groups.count == 0 || !s.visible) {
			continue;
		}
		for (TGSprite *other in list) {
			NSString *group = other.collisionGroup;
			if (other == s || group == nil || !other.visible || ![groups containsObject:group]) {
				continue;
			}
			BOOL overlap = [self shapesOverlap:s with:other];
			if (overlap) {
				if (![s.colliding containsObject:other]) {
					[s.colliding addObject:other];
					id<TGSpriteEventListener> listener = s.eventListener;
					if (listener != nil) {
						[listener sprite:s collidedWith:other];
					}
				}
			} else {
				[s.colliding removeObject:other];
			}
		}
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
