#import "TGScene.h"
#import "TGSkidTrail.h"
#import "TGSprite.h"
#import <math.h>

static float bottomEdge(TGSprite *s)
{
	return s.y + [s drawHeight] * fabsf(s.scaleY) * (1.0f - s.anchorY);
}

@implementation TGScene {
	NSMutableArray<TGSprite *> *_sprites;
	BOOL _zOrderDirty;   // guarded by @synchronized(_sprites)
	BOOL _hasYSort;      // guarded by @synchronized(_sprites)
	float _aabbA[4];
	float _aabbB[4];
}

- (instancetype)init
{
	if (self = [super init]) {
		_sprites = [NSMutableArray array];
		_skidTrail = [[TGSkidTrail alloc] init];
		_followTopFraction = 0.33f;
		_followBottomFraction = 0.7f;
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
	[self.skidTrail update:dt];
	[self wrapSprites:list];
	[self resolveSolids:list];
	[self checkCollisions:list];
	[self updateCamera];
}

/** Vertical dead-zone follow, after physics so the camera never lags. */
- (void)updateCamera
{
	TGSprite *target = self.followTarget;
	float h = self.worldHeight;
	if (target == nil || h <= 0.0f) {
		return;
	}
	float top = h * self.followTopFraction;
	float bottom = h * self.followBottomFraction;
	float screenY = target.y - self.cameraY;
	if (screenY < top) {
		self.cameraY = target.y - top;
	} else if (screenY > bottom) {
		self.cameraY = target.y - bottom;
	}
	if (self.cameraY > self.cameraMaxY) {
		self.cameraY = self.cameraMaxY;
	}
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
- (void)resolveSolids:(NSArray<TGSprite *> *)list
{
	for (TGSprite *s in list) {
		NSSet<NSString *> *groups = s.solidWith;
		if (groups.count == 0 || !s.visible) {
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
		[s computeAABB:_aabbA];
		for (TGSprite *other in list) {
			NSString *group = other.collisionGroup;
			if (other == s || group == nil || !other.visible || ![groups containsObject:group]) {
				continue;
			}
			[other computeAABB:_aabbB];
			BOOL overlap = _aabbA[0] < _aabbB[2] && _aabbA[2] > _aabbB[0]
				&& _aabbA[1] < _aabbB[3] && _aabbA[3] > _aabbB[1];
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
