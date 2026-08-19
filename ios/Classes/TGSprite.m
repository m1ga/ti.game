#import "TGSprite.h"
#import "TGAnimation.h"
#import "TGPath.h"
#import "TGScene.h"
#import "TGSkidTrail.h"
#import "TGSpriteSheet.h"
#import "TGTween.h"
#import <float.h>
#import <math.h>
#import <stdatomic.h>

static _Atomic int TGIdleSequence = 0;

@implementation TGSprite {
	// Idle wobble state (render thread only)
	float _idlePhase;
	float _idleTime;
	float _idleAppliedRot;
	float _idleAppliedX;
	float _idleAppliedY;

	// Skid mark state (render thread only)
	float _lastTireX[2];
	float _lastTireY[2];
	BOOL _skidActive;

	// Animation state, guarded by @synchronized(self)
	NSMutableDictionary<NSString *, TGAnimation *> *_animations;
	TGAnimation *_currentAnimation;
	float _animationTime;
	BOOL _playing;
	atomic_bool _animationActive;
	// Chained follow-ups (play:then:): each queued name auto-plays as
	// the previous non-looping animation finishes.
	NSMutableArray<NSString *> *_animationQueue;

	// Path follow scratch buffer (render thread only)
	float _pathOut[3];

	// Active tweens, guarded by @synchronized(_tweens)
	NSMutableArray<TGTween *> *_tweens;
}

- (instancetype)init
{
	if (self = [super init]) {
		_scaleX = 1.0f;
		_scaleY = 1.0f;
		_anchorX = 0.5f;
		_anchorY = 0.5f;
		_opacity = 1.0f;
		_tintR = 1.0f;
		_tintG = 1.0f;
		_tintB = 1.0f;
		_flashR = 1.0f;
		_flashG = 1.0f;
		_flashB = 1.0f;
		_glowOpacity = 1.0f;
		_glowR = 1.0f;
		_glowG = 1.0f;
		_glowB = 1.0f;
		_visible = YES;
		_touchEnabled = YES;
		_carryRiders = YES;
		_hitboxScale = 1.0f;
		_scrollFactor = 1.0f;
		_enginePower = 600.0f;
		_maxSpeed = 500.0f;
		_turnRate = 200.0f;
		_grip = 4.0f;
		_drag = 0.6f;
		_idleRotation = 3.0f;
		_idleMovement = 4.0f;
		_idleSpeed = 1.0f;
		_idlePhase = atomic_fetch_add(&TGIdleSequence, 1) * 1.7f;
		_colliding = [NSMutableSet set];
		_animations = [NSMutableDictionary dictionary];
		_animationQueue = [NSMutableArray array];
		_tweens = [NSMutableArray array];
		atomic_init(&_animationActive, false);
	}
	return self;
}

- (float)drawWidth
{
	float w = self.width;
	if (w > 0.0f) {
		return w;
	}
	TGSpriteSheet *s = self.sheet;
	return (s != nil) ? [s frameWidth:self.frame] : 0.0f;
}

- (float)drawHeight
{
	float h = self.height;
	if (h > 0.0f) {
		return h;
	}
	TGSpriteSheet *s = self.sheet;
	return (s != nil) ? [s frameHeight:self.frame] : 0.0f;
}

- (void)addAnimation:(TGAnimation *)animation named:(NSString *)name
{
	@synchronized (self) {
		_animations[name] = animation;
	}
}

- (BOOL)play:(NSString *)name
{
	return [self play:name then:nil];
}

- (BOOL)play:(NSString *)name then:(NSArray<NSString *> *)chain
{
	@synchronized (self) {
		TGAnimation *a = _animations[name];
		if (a == nil || a.frameCount == 0) {
			return NO;
		}
		[_animationQueue removeAllObjects];
		if (chain != nil) {
			[_animationQueue addObjectsFromArray:chain];
		}
		_currentAnimation = a;
		_animationTime = 0.0f;
		_playing = YES;
		self.frame = a.frames[0];
		atomic_store_explicit(&_animationActive, true, memory_order_release);
		return YES;
	}
}

- (void)stopAnimation
{
	@synchronized (self) {
		_playing = NO;
		[_animationQueue removeAllObjects];
		atomic_store_explicit(&_animationActive, false, memory_order_release);
	}
}

- (NSString *)currentAnimationName
{
	@synchronized (self) {
		return _currentAnimation.name;
	}
}

- (void)addTween:(TGTween *)tween
{
	[tween captureStartValues:self];
	@synchronized (_tweens) {
		[_tweens addObject:tween];
	}
}

- (void)clearTweens
{
	@synchronized (_tweens) {
		[_tweens removeAllObjects];
	}
}

- (void)clearPositionTweens
{
	@synchronized (_tweens) {
		NSIndexSet *positionTweens = [_tweens indexesOfObjectsPassingTest:
			^BOOL(TGTween *t, NSUInteger idx, BOOL *stop) {
				return t.toX != nil || t.toY != nil;
			}];
		[_tweens removeObjectsAtIndexes:positionTweens];
	}
}

- (void)update:(float)dt
{
	float startX = self.x;
	float startY = self.y;
	if (self.carMode) {
		[self updateCar:dt];
	}
	float angularVelocity = self.angularVelocity;
	if (angularVelocity != 0.0f) {
		self.rotation += angularVelocity * dt;
	}
	float thrust = self.thrust;
	if (thrust != 0.0f) {
		float rad = self.rotation * (float)M_PI / 180.0f;
		float velocityX = self.velocityX + sinf(rad) * thrust * dt;
		float velocityY = self.velocityY - cosf(rad) * thrust * dt;
		float speed = sqrtf(velocityX * velocityX + velocityY * velocityY);
		float maxSpeed = self.maxSpeed;
		if (speed > maxSpeed && speed > 0.0f) {
			velocityX *= maxSpeed / speed;
			velocityY *= maxSpeed / speed;
		}
		self.velocityX = velocityX;
		self.velocityY = velocityY;
	}
	// Semi-implicit Euler: accelerate first, then move
	float gravity = self.gravity;
	if (gravity != 0.0f) {
		self.velocityY += gravity * dt;
	}
	float velocityX = self.velocityX;
	if (velocityX != 0.0f) {
		self.x += velocityX * dt;
	}
	float velocityY = self.velocityY;
	if (velocityY != 0.0f) {
		self.y += velocityY * dt;
	}
	float wrapShift = self.wrapShift;
	if (wrapShift > 0.0f && self.x < self.wrapX) {
		self.x += wrapShift;
		startX += wrapShift; // teleport, not movement — keep it out of frameDelta
	} else if (wrapShift < 0.0f && self.x > self.wrapX) {
		self.x += wrapShift;
		startX += wrapShift;
	}
	// Path following overrides the position absolutely; between the
	// startX capture and the frameDelta computation, so path platforms
	// still carry their riders.
	TGPath *p = self.path;
	if (p != nil) {
		BOOL pathFinished = [p advance:dt out:_pathOut];
		self.x = _pathOut[0];
		self.y = _pathOut[1];
		if (p.rotate) {
			self.rotation = _pathOut[2];
		}
		if (pathFinished) {
			self.path = nil;
			id<TGSpriteEventListener> pathListener = self.eventListener;
			if (pathListener != nil) {
				[pathListener spritePathComplete:self];
			}
		}
	}
	float flashLeft = self.flashRemaining;
	if (flashLeft > 0.0f) {
		self.flashRemaining = MAX(0.0f, flashLeft - dt);
	}
	[self updateAnimation:dt];
	[self updateTweens:dt];
	[self updateIdle:dt];
	self.frameDeltaX = self.x - startX;
	self.frameDeltaY = self.y - startY;
}

/**
 * Idle wobble: three slightly detuned sine waves (rotation, x, y) give an
 * organic float instead of a metronome. Only the CHANGE in offset is
 * applied each frame, so the base transform stays writable underneath.
 */
- (void)updateIdle:(float)dt
{
	float newRot = 0.0f;
	float newX = 0.0f;
	float newY = 0.0f;
	if (self.idleAnimation && (self.idleRotation != 0.0f || self.idleMovement != 0.0f)) {
		_idleTime += dt;
		float w = (float)(M_PI * 2.0) * self.idleSpeed;
		newRot = self.idleRotation * sinf(_idleTime * w * 0.50f + _idlePhase);
		newX = self.idleMovement * 0.6f * sinf(_idleTime * w * 0.37f + _idlePhase * 1.3f);
		newY = self.idleMovement * sinf(_idleTime * w * 0.43f + _idlePhase * 2.1f);
	} else if (_idleAppliedRot == 0.0f && _idleAppliedX == 0.0f && _idleAppliedY == 0.0f) {
		return;
	}
	self.rotation += newRot - _idleAppliedRot;
	self.x += newX - _idleAppliedX;
	self.y += newY - _idleAppliedY;
	_idleAppliedRot = newRot;
	_idleAppliedX = newX;
	_idleAppliedY = newY;
}

/**
 * Arcade top-down car model — see the Android twin for the full physics
 * commentary. Finite lateral grip is what makes the car drift.
 */
- (void)updateCar:(float)dt
{
	float rad = self.rotation * (float)M_PI / 180.0f;
	float fwdX = sinf(rad);
	float fwdY = -cosf(rad);
	float rightX = cosf(rad);
	float rightY = sinf(rad);

	float velocityX = self.velocityX;
	float velocityY = self.velocityY;
	float vForward = velocityX * fwdX + velocityY * fwdY;
	float vLateral = velocityX * rightX + velocityY * rightY;

	float maxSpeed = self.maxSpeed;
	float steerFactor = MAX(-1.0f, MIN(1.0f, vForward / (maxSpeed * 0.25f)));
	self.rotation += self.steering * self.turnRate * steerFactor * dt;

	vForward += self.throttle * self.enginePower * dt;
	vForward -= vForward * MIN(1.0f, self.drag * dt);
	vLateral -= vLateral * MIN(1.0f, self.grip * dt);

	if (vForward > maxSpeed) {
		vForward = maxSpeed;
	} else if (vForward < -maxSpeed * 0.4f) {
		vForward = -maxSpeed * 0.4f;
	}

	// Recompose along the (updated) heading
	rad = self.rotation * (float)M_PI / 180.0f;
	fwdX = sinf(rad);
	fwdY = -cosf(rad);
	rightX = cosf(rad);
	rightY = sinf(rad);
	self.velocityX = fwdX * vForward + rightX * vLateral;
	self.velocityY = fwdY * vForward + rightY * vLateral;

	float threshold = (self.skidThreshold > 0.0f) ? self.skidThreshold : maxSpeed * 0.2f;
	self.drifting = fabsf(vLateral) > threshold;
	if (self.skidMarks) {
		[self emitSkidMarksFwdX:fwdX fwdY:fwdY rightX:rightX rightY:rightY
					   vLateral:vLateral threshold:threshold];
	}
}

/** Appends one trail segment per rear tire while drifting. Render thread. */
- (void)emitSkidMarksFwdX:(float)fwdX fwdY:(float)fwdY
				   rightX:(float)rightX rightY:(float)rightY
				 vLateral:(float)vLateral threshold:(float)threshold
{
	TGScene *sc = self.scene;
	if (!self.drifting || sc == nil) {
		_skidActive = NO; // break the ribbon so no segment bridges the gap
		return;
	}
	float w = [self drawWidth] * fabsf(self.scaleX);
	float h = [self drawHeight] * fabsf(self.scaleY);
	float axleX = self.x - fwdX * h * 0.28f;
	float axleY = self.y - fwdY * h * 0.28f;
	float trackX = rightX * w * 0.3f; // half the rear track width
	float trackY = rightY * w * 0.3f;
	float intensity = MIN(1.0f, fabsf(vLateral) / (threshold * 3.0f));
	float alpha = 0.15f + 0.3f * intensity;
	float markHalf = MAX(1.5f, w * 0.07f);

	for (int i = 0; i < 2; i++) {
		float side = (i == 0) ? -1.0f : 1.0f;
		float tireX = axleX + side * trackX;
		float tireY = axleY + side * trackY;
		if (_skidActive) {
			[sc.skidTrail addFromX:_lastTireX[i] y:_lastTireY[i]
							   toX:tireX y:tireY
						 halfWidth:markHalf alpha:alpha];
		}
		_lastTireX[i] = tireX;
		_lastTireY[i] = tireY;
	}
	_skidActive = YES;
}

- (float)hitRadius
{
	float w = [self drawWidth] * fabsf(self.scaleX);
	float h = [self drawHeight] * fabsf(self.scaleY);
	return MIN(w, h) * 0.5f * self.hitboxScale;
}

- (void)hitCenter:(float *)out
{
	float w = [self drawWidth];
	float h = [self drawHeight];
	float lx = (w / 2.0f - self.anchorX * w) * self.scaleX;
	float ly = (h / 2.0f - self.anchorY * h) * self.scaleY;
	float rad = self.rotation * (float)M_PI / 180.0f;
	float cosr = cosf(rad);
	float sinr = sinf(rad);
	out[0] = self.x + lx * cosr - ly * sinr;
	out[1] = self.y + lx * sinr + ly * cosr;
}

- (void)computeAABB:(float *)out
{
	float w = [self drawWidth];
	float h = [self drawHeight];
	float ax = self.anchorX * w;
	float ay = self.anchorY * h;
	float rad = self.rotation * (float)M_PI / 180.0f;
	float cosr = cosf(rad);
	float sinr = sinf(rad);
	float hitboxScale = self.hitboxScale;
	float sx = self.scaleX * hitboxScale;
	float sy = self.scaleY * hitboxScale;
	float x = self.x;
	float y = self.y;
	out[0] = out[1] = FLT_MAX;
	out[2] = out[3] = -FLT_MAX;
	for (int i = 0; i < 4; i++) {
		float lx = (((i & 1) == 0) ? -ax : w - ax) * sx;
		float ly = ((i < 2) ? -ay : h - ay) * sy;
		float wx = x + lx * cosr - ly * sinr;
		float wy = y + lx * sinr + ly * cosr;
		out[0] = MIN(out[0], wx);
		out[1] = MIN(out[1], wy);
		out[2] = MAX(out[2], wx);
		out[3] = MAX(out[3], wy);
	}
}

- (void)updateAnimation:(float)dt
{
	if (!atomic_load_explicit(&_animationActive, memory_order_acquire)) {
		return;
	}
	TGAnimation *finished = nil;
	@synchronized (self) {
		if (!_playing || _currentAnimation == nil) {
			atomic_store_explicit(&_animationActive, false, memory_order_release);
			return;
		}
		_animationTime += dt;
		TGAnimation *a = _currentAnimation;
		NSInteger frameIndex = (NSInteger)(_animationTime * a.fps);
		if ((NSUInteger)frameIndex >= a.frameCount) {
			if (a.loop) {
				frameIndex = frameIndex % (NSInteger)a.frameCount;
			} else {
				finished = a;
				// Chained follow-up (play:then:): start the next queued
				// animation instead of holding the end frame.
				TGAnimation *next = nil;
				while (_animationQueue.count > 0) {
					TGAnimation *candidate = _animations[_animationQueue[0]];
					[_animationQueue removeObjectAtIndex:0];
					if (candidate != nil && candidate.frameCount > 0) {
						next = candidate;
						break;
					}
				}
				if (next != nil) {
					_currentAnimation = next;
					_animationTime = 0.0f;
					self.frame = next.frames[0];
				} else {
					self.frame = a.frames[a.frameCount - 1];
					_playing = NO;
					atomic_store_explicit(&_animationActive, false, memory_order_release);
				}
			}
		}
		if (finished == nil) {
			self.frame = a.frames[frameIndex];
		}
	}
	if (finished != nil) {
		id<TGSpriteEventListener> listener = self.eventListener;
		if (listener != nil) {
			[listener spriteAnimationComplete:self animationName:finished.name];
		}
	}
}

- (void)updateTweens:(float)dt
{
	// Ticked in place under the lock — copying the array here would
	// allocate every frame for every animating sprite (the Android twin
	// iterates its COW list without copying). Tween updates only write
	// sprite properties, never back into _tweens.
	NSUInteger finishedCount = 0;
	@synchronized (_tweens) {
		if (_tweens.count == 0) {
			return;
		}
		for (NSUInteger i = 0; i < _tweens.count; ) {
			if ([_tweens[i] update:self delta:dt]) {
				[_tweens removeObjectAtIndex:i];
				finishedCount++;
			} else {
				i++;
			}
		}
	}
	if (finishedCount > 0) {
		id<TGSpriteEventListener> listener = self.eventListener;
		if (listener != nil) {
			for (NSUInteger i = 0; i < finishedCount; i++) {
				[listener spriteTweenComplete:self];
			}
		}
	}
}

- (BOOL)hitTestX:(float)px y:(float)py
{
	if (!self.visible || self.opacity <= 0.0f || !self.touchEnabled) {
		return NO;
	}
	// Screen-fixed sprites live in surface coordinates; the touch
	// arrives in world space, so map it back before testing. Parallax
	// sprites render shifted by the unapplied part of the camera
	// travel — shift the touch the same way (shake is already absent
	// from touch mapping).
	if (self.screenFixed) {
		TGScene *sc = self.scene;
		if (sc != nil) {
			px = [sc worldToScreenX:px];
			py = [sc worldToScreenY:py];
		}
	} else if (self.scrollFactor != 1.0f) {
		TGScene *sc = self.scene;
		if (sc != nil) {
			px -= (1.0f - self.scrollFactor) * sc.cameraX;
			py -= (1.0f - self.scrollFactor) * sc.cameraY;
		}
	}
	float w = [self drawWidth];
	float h = [self drawHeight];
	if (w <= 0.0f || h <= 0.0f) {
		return NO;
	}
	float dx = px - self.x;
	float dy = py - self.y;
	float rad = -self.rotation * (float)M_PI / 180.0f;
	float cosr = cosf(rad);
	float sinr = sinf(rad);
	float rx = dx * cosr - dy * sinr;
	float ry = dx * sinr + dy * cosr;
	float scaleX = self.scaleX;
	float scaleY = self.scaleY;
	float sx = (scaleX != 0.0f) ? scaleX : 1e-6f;
	float sy = (scaleY != 0.0f) ? scaleY : 1e-6f;
	float lx = rx / sx + self.anchorX * w;
	float ly = ry / sy + self.anchorY * h;
	if (self.circleHitbox) {
		// ellipse in local space, so touch matches the round art
		float nx = lx / w - 0.5f;
		float ny = ly / h - 0.5f;
		return nx * nx + ny * ny <= 0.25f;
	}
	return lx >= 0.0f && lx <= w && ly >= 0.0f && ly <= h;
}

@end
